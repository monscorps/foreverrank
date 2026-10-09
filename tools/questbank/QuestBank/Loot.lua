-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank's notes on who drops what, for foreverrank.com's loot tables. Forever has no Dungeon Journal, so the
-- only record of a boss's drops is players' loot windows: each time you loot a creature or a chest, this notes its
-- id, the item ids in the window, the dungeon (or map) and difficulty, and which boss fight it ended, in
-- QuestBankDB.disc.loot. Only on the Forever client, under Settings' "Note items, spells and loot" (on by default;
-- unticking clears these too). Never a name: not yours, not the boss's. The site names the ids.
--   disc.loot[key]   key "c<creature id>" or "o<object id>", as disc.npc's: { im = instance map, d = difficulty }
--                    in a dungeon or raid, or { m = uiMap } outdoors, neither when the client hides the place;
--                    e = the boss fight's encounter id, ex = true when the game named the fight's creatures (absent:
--                    the first corpse looted after the kill); n = times looted; b = build last looted at;
--                    i = { [item id] = windows it showed in }
--   disc.lootN       a counter, bumped on every note; disc.lootAt[key] its value when the key was last touched
-- Every item id a window shows, and every boss drop the game announces to the group, also goes to Game.lua's
-- tooltip queue (QB.Game.Want), so its name and stats are read without anyone hovering it.
-- Only reads: no loot is taken, no window closed, no roll made, so the game has nothing of QuestBank's to block.
local _, QB = ...
local Loot = {}
QB.Loot = Loot

local LOOT_SOURCES = 400 -- creatures and chests kept; over that, the one touched longest ago goes
local LOOT_ITEMS = 40    -- items kept for one source; a new one when full replaces the least-seen, and is left out
                         -- when every kept item was seen more than once: one odd drop never pushes a boss's table out
local AGAIN = 120        -- seconds: the same corpse or chest opened again within this (you closed the window with
                         -- items left) adds items but is not another time looted; another corpse of the kind is
local KILL_WINDOW = 120  -- seconds after a boss kill in which the first creature looted is taken for that boss, when
                         -- the kill event did not say which creatures were in the fight
local GUIDS = 50         -- corpses and chests remembered for AGAIN (a session table, never saved)
Loot.LOOT_SOURCES, Loot.LOOT_ITEMS, Loot.AGAIN, Loot.KILL_WINDOW = LOOT_SOURCES, LOOT_ITEMS, AGAIN, KILL_WINDOW

local plain = QB.Plain
local function now() return GetTime and GetTime() or 0 end
local function num(v) v = plain(v); return type(v) == "number" and v or nil end

-- noting: the Forever client, with the Settings box ticked (the same box as the item and spell notes: loot sources
-- are foreverrank.com's Database data of the same kind)
function Loot.On() return (QB.Game and QB.Game.On()) and true or false end

local function db()
  local d = QB.Discover.DB()
  if type(d.loot) ~= "table" then d.loot = {} end
  if type(d.lootAt) ~= "table" then d.lootAt = {} end
  return d
end

-- counts of what the client showed, so the uploads settle what it hands addons (nothing else is known for sure
-- before them: GetLootSourceInfo is in no Blizzard file, and ENCOUNTER_END's creature list is new to this client):
-- w loot windows seen, s with a creature or chest behind an item, h where a source was hidden (or the call is
-- missing), f skipped (from an item, fishing, nothing lootable, players only), er ENCOUNTER_LOOT_RECEIVED fired,
-- eu ENCOUNTER_ENDs that named the fight's creatures, ee that did not
local function diag(k)
  if not QuestBankDB then return end
  QuestBankDB.diag = QuestBankDB.diag or {}
  local d = QuestBankDB.diag.loot
  if type(d) ~= "table" then
    d = {}
    QuestBankDB.diag.loot = d
  end
  d[k] = (tonumber(d[k]) or 0) + 1
end

-- the client's build number, as Game.lua reads it
local function build()
  if not GetBuildInfo then return nil end
  local ok, _, b = pcall(GetBuildInfo)
  return ok and tonumber(plain(b)) or nil
end

-- where you are: { im = instance map, d = difficulty } in a dungeon or raid, { m = uiMap } outdoors. When the client
-- hides the place, the side it did say is kept: { inside = true } in a battleground or arena or with the instance
-- hidden, { inside = false } outdoors with the map hidden, {} when not even that is known. The items still count
-- either way. Forever's dungeons have no uiMap, so inside one the instance map id is the place
local function where()
  local inside
  if IsInInstance then
    local ok, kind
    ok, inside, kind = pcall(IsInInstance)
    if not ok then return {} end
    inside, kind = plain(inside), plain(kind) -- (not "ok and plain(inside) or nil": outdoors is false, and stays so)
    if inside ~= true and inside ~= false then return {} end

    if inside then
      if (kind == "party" or kind == "raid") and GetInstanceInfo then
        local okI, _, _, diff, _, _, _, _, id = pcall(GetInstanceInfo)
        diff, id = okI and num(diff) or nil, okI and num(id) or nil
        if diff and diff > 0 and id and id > 0 then return { im = id, d = diff } end
      end
      return { inside = true }
    end
  end
  if C_Map and C_Map.GetBestMapForUnit then
    local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
    m = ok and num(m) or nil
    if m and m > 0 then return { m = m } end
  end
  return { inside = inside } -- false when IsInInstance said outdoors, nil when there was no answer
end

local function idOf(link)
  link = plain(link)
  return type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) or nil
end

-- an item id for Game.lua's tooltip queue: read a few a second, out of combat, with the hover's guards and caps
local function tip(id)
  if QB.Game and QB.Game.Want then QB.Game.Want(id) end
end

-- the GUIDs behind one loot slot (guid, count, guid, count, ...: a stack can come from more than one corpse)
local function take(ok, ...)
  local out = {}
  if ok then
    for k = 1, select("#", ...), 2 do out[#out + 1] = (select(k, ...)) end
  end
  return out
end

local seen, order = {}, {} -- [guid] = when it was last looted, and the GUIDs in that order, the last GUIDS of them
local lastKill -- { e = encounter id, t = when, c = { [creature id] = true } when the game named them, used = true
               --   once a corpse took a kill that named none }

-- one creature or chest looted: its items, where, and which boss fight it ended
local function note(key, guid, items, place)
  local d = db()
  local all, at = d.loot, d.lootAt
  local rec = all[key]
  local fresh = type(rec) ~= "table"
  if fresh then
    rec = { n = 0, i = {} }
    all[key] = rec
  end
  if type(rec.i) ~= "table" then rec.i = {} end
  local t = now()
  local again = seen[guid] ~= nil and t - seen[guid] < AGAIN
  if seen[guid] ~= nil then
    for k = #order, 1, -1 do if order[k] == guid then table.remove(order, k); break end end
  end
  order[#order + 1] = guid
  seen[guid] = t
  while #order > GUIDS do seen[table.remove(order, 1)] = nil end
  if not again then rec.n = (tonumber(rec.n) or 0) + 1 end
  -- the place: a dungeon with its difficulty, or the map outdoors, never both. Hidden, the place noted before stands
  -- only where it still can: a map from outdoors is wrong for a corpse looted inside, and the other way round
  if place.im then rec.im, rec.d, rec.m = place.im, place.d, nil
  elseif place.m then rec.m, rec.im, rec.d = place.m, nil, nil
  elseif place.inside == true then rec.m = nil
  elseif place.inside == false then rec.im, rec.d = nil, nil end
  rec.b = build() or rec.b
  if key:sub(1, 1) == "c" and lastKill then
    local id = tonumber(key:sub(2))
    if lastKill.c then
      if lastKill.c[id] then rec.e, rec.ex = lastKill.e, true end
    elseif not lastKill.used and t - lastKill.t <= KILL_WINDOW then
      -- the first creature looted within two minutes of a kill that named no creatures is taken for the boss (a
      -- guess the site weighs lower); a link the game itself made stands over it
      lastKill.used = true
      if rec.ex ~= true then rec.e, rec.ex = lastKill.e, nil end
    end
  end
  -- the items, each counted once per window it showed in. The same corpse opened again only adds what is new
  local i = rec.i
  for _, id in ipairs(items) do
    if i[id] then
      if not again then i[id] = (tonumber(i[id]) or 0) + 1 end
    else
      local n = 0
      for _ in pairs(i) do n = n + 1 end
      local room = n < LOOT_ITEMS
      if not room then
        -- full: the item seen fewest times goes (the lowest id of them); a new one is seen once, so when every kept
        -- item was seen more often, it is the one left out
        local low, lowId
        for k, c in pairs(i) do
          c = tonumber(c) or 0
          if not low or c < low or (c == low and k < lowId) then low, lowId = c, k end
        end
        if low <= 1 then
          i[lowId] = nil
          room = true
        end
      end
      if room then i[id] = 1 end
    end
  end
  d.lootN = (tonumber(d.lootN) or 0) + 1
  at[key] = d.lootN
  if fresh then
    local n = 0
    for _ in pairs(all) do n = n + 1 end
    while n > LOOT_SOURCES do
      local old, when
      for k in pairs(all) do
        local w = tonumber(at[k]) or 0
        if not when or w < when or (w == when and k < old) then old, when = k, w end
      end
      all[old], at[old] = nil, nil
      n = n - 1
    end
  end
end

-- a loot window opened: each item slot's id goes to the creature or chest behind it, and to Game.lua's tooltip queue
-- (an item auto-looted and never hovered still gets its name and stats read). Coins and currency are skipped, and
-- grey items unless they are quest items; a window from an item (a lockbox, a clam) or fishing has no source to note
-- (its items are still queued), and sources that are players (a corpse in PvP) are skipped. Item class is not looked
-- at here: the server-sent items this is after may have no client row; the site sorts them
local function window(isFromItem)
  diag("w")
  local sourced = plain(isFromItem) ~= true
  if sourced and IsFishingLoot then
    local ok, fishing = pcall(IsFishingLoot)
    if ok and plain(fishing) == true then sourced = false end
  end
  if not sourced then diag("f") end
  local okN, n = pcall(GetNumLootItems)
  n = okN and tonumber(plain(n)) or 0
  local ITEM = (Enum and Enum.LootSlotType and Enum.LootSlotType.Item) or 1
  local sources, hidden = {}, false
  for slot = 1, n do
    local kind = ITEM
    if GetLootSlotType then
      local okK, k = pcall(GetLootSlotType, slot)
      kind = okK and plain(k) or nil
    end
    if kind == ITEM then
      local okI, _, _, _, _, quality, _, isQuest, questID = pcall(GetLootSlotInfo, slot)
      quality, isQuest, questID = okI and plain(quality) or nil, okI and plain(isQuest) or nil, okI and plain(questID) or nil
      local okL, link = pcall(GetLootSlotLink, slot)
      local id = okL and idOf(link) or nil
      if id then tip(id) end
      local quest = isQuest == true or (type(questID) == "number" and questID > 0)
      if sourced and id and not (quality == 0 and not quest) then
        if not GetLootSourceInfo then
          hidden = true
        else
          for _, guid in ipairs(take(pcall(GetLootSourceInfo, slot))) do
            guid = plain(guid)
            if type(guid) ~= "string" then
              hidden = true
            else
              local key = QB.Discover.Key(guid)
              if key then
                local s = sources[key]
                if not s then
                  s = { guid = guid, has = {}, items = {} }
                  sources[key] = s
                end
                if not s.has[id] then
                  s.has[id] = true
                  s.items[#s.items + 1] = id
                end
              end
            end
          end
        end
      end
    end
  end
  if not sourced then return end
  if hidden then diag("h") end
  if next(sources) == nil then
    if not hidden then diag("f") end
    return
  end
  diag("s")
  local place = where()
  for key, s in pairs(sources) do note(key, s.guid, s.items, place) end
end

-- a boss fight ended: a kill (success 1) is remembered, with the creatures the game says were in it when it says
-- (encounterUnitStatus; creatureName is never read). A wipe or a hidden id links nothing
function Loot.EncounterEnd(encounterID, success, units)
  local e, won = num(encounterID), num(success)
  units = plain(units)
  diag(type(units) == "table" and "eu" or "ee")
  if not e or won ~= 1 then return end
  local kill = { e = e, t = now() }
  if type(units) == "table" then
    local list = {}
    for _, u in ipairs(units) do
      u = plain(u)
      local cid = type(u) == "table" and num(u.creatureID) or nil
      if cid then list[cid] = true end
    end
    if next(list) then kill.c = list end
  end
  lastKill = kill
end

-- BOSS_KILL: the same, without the list. A kill already noted for this fight stands (with its list, or with the
-- corpse that already took it)
function Loot.BossKill(encounterID)
  local e = num(encounterID)
  if not e then return end
  if lastKill and lastKill.e == e then return end
  lastKill = { e = e, t = now() }
end

function Loot.OnEvent(event, a1, a2, a3, a4, a5, a6)
  if not Loot.On() then return end
  if event == "LOOT_OPENED" then
    window(a2)
  elseif event == "ENCOUNTER_END" then
    Loot.EncounterEnd(a1, a5, a6)
  elseif event == "BOSS_KILL" then
    Loot.BossKill(a1)
  elseif event == "ENCOUNTER_START" then
    -- a new fight: a kill that named no creatures has had its corpse by now, or is not the next one looted
    if lastKill and not lastKill.c then lastKill = nil end
  elseif event == "ENCOUNTER_LOOT_RECEIVED" then
    -- (encounterID, itemID, itemLink, quantity, ...): a boss drop the game announces to the group, whoever looted the
    -- corpse. Its id goes to the tooltip queue; nothing else of it is read (the fifth argument is a player's name)
    diag("er")
    tip(a2)
  elseif event == "PLAYER_ENTERING_WORLD" then
    lastKill = nil
  end
end

-- how much is noted, for /qb discoveries and the Settings page: creatures and chests, and the items under them
function Loot.Count()
  local d = QuestBankDB and QuestBankDB.disc
  local all = type(d) == "table" and type(d.loot) == "table" and d.loot or {}
  local ns, ni = 0, 0
  for _, rec in pairs(all) do
    ns = ns + 1
    for _ in pairs(type(rec) == "table" and type(rec.i) == "table" and rec.i or {}) do ni = ni + 1 end
  end
  return ns, ni
end

-- the Settings box unticked (Game.SetOn): what was noted goes, since QuestBank.lua is uploaded whole
function Loot.Clear()
  local d = QuestBankDB and QuestBankDB.disc
  if type(d) ~= "table" then return end
  d.loot, d.lootAt, d.lootN = nil, nil, nil
end

function Loot:Init()
  if self.frame then return end
  local f = CreateFrame("Frame")
  self.frame = f
  if not (QB.Game and QB.Game.Forever()) then return end -- Classic Era: nothing to note, as Game.lua
  f:SetScript("OnEvent", QB.Safe(function(_, event, ...) Loot.OnEvent(event, ...) end, "loot notes"))
  -- LOOT_OPENED, not LOOT_READY: it says whether the window came from an item, fires once a window, and Blizzard's
  -- own frame reads the slots inside it. LOOT_CLOSED has nothing to do: the dedupe is by GUID and time
  for _, e in ipairs({ "LOOT_OPENED", "ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL", "ENCOUNTER_LOOT_RECEIVED", "PLAYER_ENTERING_WORLD" }) do
    pcall(f.RegisterEvent, f, e)
  end
end
