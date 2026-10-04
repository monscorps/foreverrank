-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank discoveries: Forever is a discovery version of the game, so what players see beats any
-- database. This notes what the game shows you while you quest, in QuestBank's own saved file:
--   quests   title, quest level, and the XP the quest window and the hand-in show at your level
--   npcs     who gives and who takes each quest, with where they stand (map and position)
--   offers   which quests an NPC offers you, and the lowest level you were offered each at
--   chains   a quest offered straight after you hand one in, by the same NPC
--   os       where a quest's objective ticks for you (the Forever client only): map and position, no names
-- No player, guild or realm names; just your level, race and class for what you were offered.
-- It never leaves your PC on its own: upload QuestBank.lua at foreverrank.com/questbank/, or let QuestBank
-- Uploader send it on Windows. Everyone's notes are merged into the next QuestBank release.
local _, QB = ...
local Disc = {}
QB.Discover = Disc

local MAX_PLACES = 4 -- positions kept per NPC (they wander a little, and some stand in two places)

local function db()
  QuestBankDB = QuestBankDB or {}
  local d = QuestBankDB.disc
  if not d or d.v ~= 1 then
    d = { v = 1, q = {}, npc = {}, offer = {}, chain = {}, item = {} }
    QuestBankDB.disc = d
  end
  return d
end
Disc.DB = db

-- "Creature-0-...-<id>-..." -> "c123"; "GameObject-..." -> "o456"; players and pets don't count
local function who(unit)
  if not UnitGUID then return nil end
  local ok, guid = pcall(UnitGUID, unit)
  -- the Forever client hands addons a secret value for some units (seen in uploads): nobody, not an error
  if not ok or type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end
  local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
  if kind == "Creature" or kind == "Vehicle" then return "c" .. id, guid end
  if kind == "GameObject" then return "o" .. id, guid end
  return nil
end
Disc.Who = who

-- where you stand: "uiMap:x,y" in map percent, one decimal
local function here()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
  local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
  if not ok or not m then return nil end
  local ok2, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
  if not ok2 or not pos then return nil end
  local x, y = pos.x, pos.y
  if pos.GetXY then x, y = pos:GetXY() end
  if not x or not y or (x == 0 and y == 0) then return nil end
  return string.format("%d:%.1f,%.1f", m, x * 100, y * 100)
end
Disc.Here = here

local function level() return UnitLevel and UnitLevel("player") or 0 end

local function quest(id, title)
  local d = db()
  local q = d.q[id]
  if not q then
    q = { xp = {} }
    d.q[id] = q
  end
  if title and title ~= "" then q.t = title end
  return q
end

local function noteNpc(key, name, spot)
  if not key then return end
  local d = db()
  local n = d.npc[key]
  if not n then
    n = { p = {} }
    d.npc[key] = n
  end
  if name and name ~= "" then n.n = name end
  if spot then
    for _, p in ipairs(n.p) do if p == spot then return end end
    if #n.p < MAX_PLACES then n.p[#n.p + 1] = spot end
  end
end

local function addTo(list, value)
  for _, v in ipairs(list) do if v == value then return end end
  list[#list + 1] = value
end

-- the XP a quest pays at a level: the quest window's and the hand-in's, with the sleeping bag noted
local function noteXP(q, xp, how)
  if issecretvalue and issecretvalue(xp) then return end
  if not xp or xp <= 0 then return end
  local key = level() .. ((QB.API and QB.API.HasWellRested and QB.API.HasWellRested()) and "b" or "")
  q.xp[key] = xp
  if how == "turnin" then q.paid = (q.paid or 0) + 1 end
end

-- the reward items the quest window shows: c = choose one of these, r = always given. A reading with an item the
-- client hasn't loaded yet is not kept (the next window completes it); empty lists mean the quest gives no items
local function rewardItem(kind, i)
  local link = GetQuestItemLink and QB.Plain(GetQuestItemLink(kind, i))
  local id = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) or nil
  if not id and GetQuestItemInfo then
    local ok, _, _, _, _, _, itemID = pcall(GetQuestItemInfo, kind, i)
    itemID = ok and QB.Plain(itemID) or nil
    if type(itemID) == "number" and itemID > 0 then id = itemID end
  end
  if id and QB.Game then QB.Game.Want(id) end -- and its tooltip, for foreverrank.com's item pages
  return id
end

local function noteRewards(q)
  if not (GetNumQuestChoices and GetNumQuestRewards) then return end
  local nc, nr = QB.Plain(GetNumQuestChoices()), QB.Plain(GetNumQuestRewards())
  if type(nc) ~= "number" or type(nr) ~= "number" then return end
  local rw = { c = {}, r = {} }
  for i = 1, nc do local id = rewardItem("choice", i); if not id then return end; rw.c[#rw.c + 1] = id end
  for i = 1, nr do local id = rewardItem("reward", i); if not id then return end; rw.r[#rw.r + 1] = id end
  q.rw = rw
end

local lastTurnIn -- { id, npc, t }: a quest offered by the same NPC right after it is the next step
local lastComplete -- { id, npc }: the reward window, since the NPC may be gone by the hand-in event

local function now() return GetTime and GetTime() or 0 end

function Disc.OnEvent(event, a1, a2, a3)
  if event == "QUEST_LOG_UPDATE" or (event == "UNIT_QUEST_LOG_CHANGED" and a1 == "player") then
    Disc.LookSoon()
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    if QB.Plain(a1) == "player" then Disc.Cast(a3) end
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_CLOSE" or event == "CRAFT_SHOW" or event == "CRAFT_CLOSE" then
    Disc.Crafting()
  elseif event == "PLAYER_ENTERING_WORLD" or event == "LOADING_SCREEN_DISABLED" then
    Disc.Settle()
  elseif event == "QUEST_DETAIL" then
    local id = QB.Plain(GetQuestID and GetQuestID())
    if not id or id == 0 then return end
    local q = quest(id, QB.Plain(GetTitleText and GetTitleText()))
    local npc = who("npc")
    local item = tonumber(QB.Plain(a1))
    if item and item > 0 then
      db().item[item] = id
      q.from = q.from or {}
      addTo(q.from, "i" .. item)
    elseif npc then
      noteNpc(npc, UnitName and UnitName("npc"), here())
      q.from = q.from or {}
      addTo(q.from, npc)
      if lastTurnIn and lastTurnIn.npc == npc and lastTurnIn.id ~= id and now() - lastTurnIn.t < 8 then
        db().chain[lastTurnIn.id .. ">" .. id] = true
      end
    end
    noteXP(q, GetRewardXP and GetRewardXP(), "window")
    noteRewards(q)
    if GetSuggestedGroupNum then q.g = GetSuggestedGroupNum() or q.g end
  elseif event == "QUEST_COMPLETE" then
    local id = QB.Plain(GetQuestID and GetQuestID())
    if not id or id == 0 then return end
    local q = quest(id, QB.Plain(GetTitleText and GetTitleText()))
    local npc = who("npc")
    if npc then
      noteNpc(npc, UnitName and UnitName("npc"), here())
      q.to = q.to or {}
      addTo(q.to, npc)
    end
    lastComplete = { id = id, npc = npc }
    noteXP(q, GetRewardXP and GetRewardXP(), "window")
    noteRewards(q)
  elseif event == "QUEST_TURNED_IN" then
    local id, xp = a1, a2
    if not id or (issecretvalue and issecretvalue(id)) then return end
    local q = quest(id)
    noteXP(q, xp, "turnin")
    local npc = who("npc") or (lastComplete and lastComplete.id == id and lastComplete.npc) or nil
    lastTurnIn = { id = id, npc = npc, t = now() }
  elseif event == "QUEST_ACCEPTED" then
    -- (questID in the modern event; the log index first on Classic-style clients)
    local id = QB.Plain(a2 or a1)
    if type(id) == "number" then Disc.Accepted(id) end
    if not id or not C_QuestLog then return end
    local q = quest(id)
    if C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetInfo then
      local i = C_QuestLog.GetLogIndexForQuestID(id)
      local info = i and C_QuestLog.GetInfo(i)
      if info then
        if info.title then q.t = info.title end
        if info.level and info.level > 0 then q.lv = info.level end
        if info.suggestedGroup and info.suggestedGroup > 0 then q.g = info.suggestedGroup end
      end
    end
    q.min = math.min(q.min or 99, level())
  elseif event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
    local npc = who("npc")
    if not npc then return end
    noteNpc(npc, UnitName and UnitName("npc"), here())
    local offers = db().offer
    offers[npc] = offers[npc] or {}
    local lvl = level()
    local function offered(id, title, qlevel)
      if not id or id == 0 then return end
      local q = quest(id, title)
      if qlevel and qlevel > 0 then q.lv = qlevel end
      q.from = q.from or {}
      addTo(q.from, npc)
      offers[npc][id] = math.min(offers[npc][id] or 99, lvl)
      q.min = math.min(q.min or 99, lvl)
    end
    if event == "GOSSIP_SHOW" and C_GossipInfo and C_GossipInfo.GetAvailableQuests then
      for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do offered(info.questID, info.title, info.questLevel) end
      for _, info in ipairs((C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests()) or {}) do
        if info.questID and info.isComplete then
          local q = quest(info.questID, info.title)
          q.to = q.to or {}
          addTo(q.to, npc)
        end
      end
    elseif event == "QUEST_GREETING" and GetNumAvailableQuests and GetAvailableQuestInfo then
      for i = 1, GetNumAvailableQuests() or 0 do
        local _, _, _, _, id = GetAvailableQuestInfo(i)
        offered(id, GetAvailableTitle and GetAvailableTitle(i), GetAvailableLevel and GetAvailableLevel(i))
      end
    end
  end
end

----------------------------------------------------------------------------
-- objective spots: where a quest in your log gains progress (a kill, an item looted, an object used, an area
-- reached), so the map icons can show where Forever's objectives really are, the Forever-only quests above all.
-- disc.os = { [questId] = { [objective, as the game numbers them] = { t = the game's kind ("monster", "item", ...),
--   p = { { uiMap, x, y, n }, ... } } } }, x and y in thousandths of the map, n the sightings merged into that point.
-- Only the map, the place and the game's kind of objective: no names, nothing about you.
----------------------------------------------------------------------------
local OS_NEAR = 15    -- thousandths of the map: a sighting this close to a point on the same map is that point
local OS_POINTS = 8   -- points kept per objective; over that, the one seen fewest times goes
local OS_QUESTS = 400 -- quests kept; over that, the one touched longest ago goes
local SETTLE = 10     -- seconds after login, a reload or any loading screen (from when the world shows) when the log
                      -- only learns where things stand: the server can fill in objectives a moment after the quest
                      -- list, and that is no progress
local FRESH = 3       -- seconds a quest new to the log (or accepted again) only learns: an item objective's count for
                      -- what is in your bags can come a moment after the quest
local CRAFT = 5       -- seconds after a crafting window shuts, or a craft is cast, when an item that comes was made
Disc.OS_NEAR, Disc.OS_POINTS, Disc.OS_QUESTS = OS_NEAR, OS_POINTS, OS_QUESTS

local floor = math.floor
local function secret(v) return (issecretvalue and issecretvalue(v)) and true or false end
local function forever() return QB.Game and QB.Game.Forever() or false end

-- where you stand for an objective: uiMap, x, y (thousandths), or nil inside an instance, with no position, or
-- when the client hides any of it
local function spot()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
  if IsInInstance then
    local ok, inside = pcall(IsInInstance)
    if not ok or secret(inside) or inside then return nil end
  end
  local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
  if not ok or secret(m) or type(m) ~= "number" or m <= 0 then return nil end
  local ok2, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
  if not ok2 or pos == nil or secret(pos) or type(pos) ~= "table" then return nil end
  local ok3, x, y = pcall(function()
    if pos.GetXY then return pos:GetXY() end
    return pos.x, pos.y
  end)
  if not ok3 or secret(x) or secret(y) or type(x) ~= "number" or type(y) ~= "number" then return nil end
  if (x == 0 and y == 0) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  return m, floor(x * 1000 + 0.5), floor(y * 1000 + 0.5)
end
Disc.Spot = spot

local function shown(names)
  for _, name in ipairs(names) do
    local f = _G[name]
    if type(f) == "table" and f.IsShown then
      local ok, on = pcall(f.IsShown, f)
      if ok and on == true then return true end
    end
  end
  return false
end

-- progress that wasn't made where you stand: the bank, the mailbox, a trade, the auction house. Not a vendor's:
-- what you buy there is got there
local AWAY = { "BankFrame", "MailFrame", "TradeFrame", "AuctionFrame", "AuctionHouseFrame", "GuildBankFrame" }
local function elsewhere() return QB.bankOpen and true or shown(AWAY) end

-- an item made rather than found (it could be made anywhere): a crafting window is open (Forever's is the
-- ProfessionsFrame; the other two are Classic's), or shut a moment ago, or a craft was cast a moment ago (its item
-- comes after the cast, and "create all" can go on with the window shut). A kill meanwhile is still where you stand
local CRAFTING = { "ProfessionsFrame", "TradeSkillFrame", "CraftFrame" }
local craftUntil = 0
local crafts = {} -- [spell] = true: the recipes you cast at a crafting window, so a cast of one later is a craft too
local function crafting() return now() < craftUntil or shown(CRAFTING) end

-- a crafting window opens or shuts, or a craft is cast: an item in the next seconds was made
function Disc.Crafting() craftUntil = math.max(craftUntil, now() + CRAFT) end

-- a spell of yours went off: at a crafting window it is a recipe, unless the game says it is none (a heal cast with
-- the window open); and a recipe cast later, with the window shut, is a craft. (The client hides the spell while
-- spell casts are restricted: then the window's opening and shutting are all there is to go by)
function Disc.Cast(spell)
  spell = QB.Plain(spell)
  if type(spell) ~= "number" then return end
  if not crafts[spell] and shown(CRAFTING) then
    local T, recipe = C_TradeSkillUI, true
    if T and T.GetRecipeInfo then
      local ok, info = pcall(T.GetRecipeInfo, spell)
      recipe = not ok or QB.Plain(info) ~= nil
    end
    crafts[spell] = recipe or nil
  end
  if crafts[spell] then Disc.Crafting() end
end

local function osDB()
  local d = db()
  if type(d.os) ~= "table" then d.os = {} end
  if type(d.osAt) ~= "table" then d.osAt = {} end -- [questId] = when it was last touched (a counter, not a time)
  return d
end

-- one sighting of objective i of quest id (kind: the game's), at m, x, y: merged into the nearest point within
-- OS_NEAR on that map (which moves to the mean of its sightings), else a point of its own
function Disc.NoteSpot(id, i, kind, m, x, y)
  local d = osDB()
  local all, at = d.os, d.osAt
  d.osN = (d.osN or 0) + 1
  at[id] = d.osN
  local q = all[id]
  if type(q) ~= "table" then
    q = {}
    all[id] = q
    local n = 0
    for _ in pairs(all) do n = n + 1 end
    while n > OS_QUESTS do
      local old, when
      for k in pairs(all) do
        local t = at[k] or 0
        if not when or t < when or (t == when and k < old) then old, when = k, t end
      end
      all[old], at[old] = nil, nil
      n = n - 1
    end
  end
  local o = q[i]
  if type(o) ~= "table" then
    o = {}
    q[i] = o
  end
  if type(o.p) ~= "table" then o.p = {} end
  if type(kind) == "string" and kind ~= "" then o.t = kind end
  local best, bestD
  for _, p in ipairs(o.p) do
    if p[1] == m then
      local dx, dy = p[2] - x, p[3] - y
      local d2 = dx * dx + dy * dy
      if d2 <= OS_NEAR * OS_NEAR and (not bestD or d2 < bestD) then best, bestD = p, d2 end
    end
  end
  if best then
    local n = best[4] or 1
    best[2], best[3], best[4] = floor((best[2] * n + x) / (n + 1) + 0.5), floor((best[3] * n + y) / (n + 1) + 0.5), n + 1
    return best
  end
  if #o.p >= OS_POINTS then
    -- full: the point seen fewest times goes, the oldest of them; a new sighting is seen once, so when every
    -- point was seen more often, it is the one left out
    local low, li
    for k, p in ipairs(o.p) do
      local n = p[4] or 1
      if not low or n < low then low, li = n, k end
    end
    if low > 1 then return nil end
    table.remove(o.p, li)
  end
  local p = { m, x, y, 1 }
  o.p[#o.p + 1] = p
  return p
end

-- the log as the last look saw it: seen[questId][objective] = { have, finished }; nil before the first look.
-- born[questId]: when a look first saw the quest in the log (or it was accepted again)
local seen
local born = {}
local settleUntil = 0

local function plainNum(v) v = QB.Plain(v); return type(v) == "number" and v or nil end

-- login, a reload, a loading screen, the world showing after one: the next seconds only learn
function Disc.Settle() settleUntil = math.max(settleUntil, now() + SETTLE) end

-- a quest accepted (again, perhaps, after it was abandoned between two looks): what it has now isn't from here
function Disc.Accepted(id) born[id] = now() end

-- look at the log: an objective that has more than last time (or is finished now) was ticked where you stand
local function look()
  if not forever() then return end
  local L = C_QuestLog
  if not (L and L.GetNumQuestLogEntries and L.GetInfo and L.GetQuestObjectives) then return end
  local okN, n = pcall(L.GetNumQuestLogEntries)
  n = okN and plainNum(n) or 0
  local t = now()
  local settled = t >= settleUntil and seen ~= nil
  local fresh, since, here = {}, {}, nil
  for li = 1, n do
    local okI, info = pcall(L.GetInfo, li)
    local id = okI and type(info) == "table" and not secret(info) and plainNum(info.questID) or nil
    if id and id > 0 and not QB.Plain(info.isHeader) and not QB.Plain(info.isHidden) then
      local okO, objs = pcall(L.GetQuestObjectives, id)
      if okO and type(objs) == "table" and not secret(objs) then
        local cur, was = {}, seen and seen[id]
        since[id] = (was and born[id]) or t
        local old = settled and t - since[id] >= FRESH
        for i, o in ipairs(objs) do
          if type(o) == "table" and not secret(o) then
            -- finished: true or false, or nil when the client hides it (unknown is not "not finished")
            local have, done = plainNum(o.numFulfilled), QB.Plain(o.finished)
            if type(done) ~= "boolean" then done = nil end
            cur[i] = { have, done }
            local before = was and was[i]
            if old and before and ((have and before[1] and have > before[1]) or (done == true and before[2] == false)) then
              local kind = QB.Plain(o.type)
              kind = type(kind) == "string" and kind ~= "" and kind or nil
              -- an item (or a line whose kind is hidden) while crafting: made, not found where you stand
              if not ((kind == nil or kind == "item") and crafting()) then
                if here == nil then
                  here = false
                  if not elsewhere() then
                    local m, x, y = spot()
                    if m then here = { m, x, y } end
                  end
                end
                if here then Disc.NoteSpot(id, i, kind, here[1], here[2], here[3]) end
              end
            end
          end
        end
        fresh[id] = cur
      end
    end
  end
  seen, born = fresh, since
end
Disc.Look = look

-- many updates come at once (a loot window, a kill): one look, a moment later
local soon = false
local function lookSoon()
  if soon or not forever() then return end
  soon = true
  C_Timer.After(0, QB.Safe(function() soon = false; look() end, "objective spots"))
end
Disc.LookSoon = lookSoon

-- how much is noted, for /qb discoveries and the Settings page
function Disc.Count()
  local d = db()
  local nq, nn, nc = 0, 0, 0
  for _ in pairs(d.q) do nq = nq + 1 end
  for _ in pairs(d.npc) do nn = nn + 1 end
  for _ in pairs(d.chain) do nc = nc + 1 end
  return nq, nn, nc
end

function Disc:Init()
  if self.frame then return end
  local f = CreateFrame("Frame")
  self.frame = f
  f:SetScript("OnEvent", QB.Safe(function(_, event, a1, a2, a3) Disc.OnEvent(event, a1, a2, a3) end, "discoveries"))
  for _, e in ipairs({ "QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_LOG_UPDATE" }) do
    pcall(f.RegisterEvent, f, e)
  end
  if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, "UNIT_QUEST_LOG_CHANGED", "player") end
  if forever() then
    -- for the objective spots: loading screens, and crafting (what you make isn't found where you stand)
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "LOADING_SCREEN_DISABLED", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "CRAFT_SHOW", "CRAFT_CLOSE" }) do
      pcall(f.RegisterEvent, f, e)
    end
    if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_SUCCEEDED", "player") end
  end
  seen, born, settleUntil = nil, {}, now() + SETTLE
  local d = db()
  d.build = (GetBuildInfo and select(2, GetBuildInfo())) or d.build
  -- which client: Forever is 16xxx; notes from Classic Era must not mark Classic quests as seen in Forever
  d.iface = (GetBuildInfo and QB.Plain(select(4, GetBuildInfo()))) or d.iface
  d.ver = QB.version
end
