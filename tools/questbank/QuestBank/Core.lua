-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank core: game state, quest status, the plan, the hand-in run, settings, events, export.
-- Everything here reads the game. Nothing accepts, abandons or hands in a quest for you.
local ADDON, QB = ...
QB.version = "3.0.1"
QB.CAP = 30

local D = QB.Data
local API = {}
QB.API = API

----------------------------------------------------------------------------
-- API shims: the Forever client carries the modern API, Classic names are the fallback
----------------------------------------------------------------------------
-- A quest counts as handed in when the game's list of completed quests has it, or its flag says so.
-- The two can disagree (a player's Glowing Shard was in the list while the flag said no), so both
-- are asked. The list is read once and kept up to date on every hand-in.
local doneSet, doneCount, doneRead = nil, 0, -100

local function readDone()
  local t, n = {}, 0
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    local ok, ids = pcall(C_QuestLog.GetAllCompletedQuestIDs)
    if ok and type(ids) == "table" then for i = 1, #ids do t[ids[i]] = true; n = n + 1 end end
  end
  if n == 0 and GetQuestsCompleted then
    local ok, list = pcall(GetQuestsCompleted)
    if ok and type(list) == "table" then for id in pairs(list) do t[id] = true; n = n + 1 end end
  end
  return t, n
end

function API.RefreshDone()
  doneSet, doneCount = readDone()
  doneRead = GetTime and GetTime() or 0
end

function API.MarkDone(id)
  if not doneSet then API.RefreshDone() end
  if not doneSet[id] then doneSet[id] = true; doneCount = doneCount + 1 end
end

function API.DoneList()
  if not doneSet or doneCount == 0 then API.RefreshDone() end
  local out = {}
  for id in pairs(doneSet) do out[#out + 1] = id end
  table.sort(out)
  return out
end

-- what each source says, for /qb done
function API.DoneSources(id)
  if not doneSet or doneCount == 0 then API.RefreshDone() end
  local flag
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
    local ok, v = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
    flag = ok and v and true or false
  elseif IsQuestFlaggedCompleted then
    local ok, v = pcall(IsQuestFlaggedCompleted, id)
    flag = ok and v and true or false
  end
  return doneSet[id] and true or false, flag, doneCount
end

function API.IsDone(id)
  -- an empty list usually means the game hasn't sent it yet: look again, but not on every call
  if not doneSet or (doneCount == 0 and (GetTime and GetTime() or 0) - doneRead > 5) then API.RefreshDone() end
  if doneSet[id] then return true end
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
    local ok, v = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
    return ok and v and true or false
  end
  if IsQuestFlaggedCompleted then
    local ok, v = pcall(IsQuestFlaggedCompleted, id)
    return ok and v and true or false
  end
  return false
end

local function isComplete(questID, flag)
  if C_QuestLog and C_QuestLog.IsComplete then
    local ok, v = pcall(C_QuestLog.IsComplete, questID)
    if ok and v ~= nil then return v and true or false end
  end
  if IsQuestComplete then
    local ok, v = pcall(IsQuestComplete, questID)
    if ok and v ~= nil then return v and true or false end
  end
  return flag == 1 or flag == true
end

function API.Objectives(questID, index)
  local out = {}
  if C_QuestLog and C_QuestLog.GetQuestObjectives then
    local ok, objs = pcall(C_QuestLog.GetQuestObjectives, questID)
    if ok and objs then
      for _, o in ipairs(objs) do
        out[#out + 1] = { text = o.text, done = o.finished and true or false, have = o.numFulfilled, need = o.numRequired }
      end
      return out
    end
  end
  if index and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
    for j = 1, (GetNumQuestLeaderBoards(index) or 0) do
      local text, _, finished = GetQuestLogLeaderBoard(j, index)
      out[#out + 1] = { text = text, done = finished and true or false }
    end
  end
  return out
end

-- The quest log's own XP number is not read: on Classic-style clients that means selecting each
-- entry in the game's quest log, which disturbs the log (and at the cap it shows 0 anyway). The
-- quest window at the NPC and the hand-in itself give the game's number without touching the log.

function API.LogQuests()
  local out, order = {}, {}
  local n = 0
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
    n = C_QuestLog.GetNumQuestLogEntries() or 0
  elseif GetNumQuestLogEntries then
    n = GetNumQuestLogEntries() or 0
  end
  for i = 1, n do
    local title, level, isHeader, flag, questID
    if C_QuestLog and C_QuestLog.GetInfo then
      local info = C_QuestLog.GetInfo(i)
      if info then title, level, isHeader, questID = info.title, info.level, info.isHeader, info.questID end
    elseif GetQuestLogTitle then
      local t, l, _, h, _, c, _, id = GetQuestLogTitle(i)
      title, level, isHeader, flag, questID = t, l, h, c, id
    end
    if title and not isHeader and questID and questID > 0 then
      local e = { id = questID, title = title, level = level, index = i, complete = isComplete(questID, flag) }
      e.objectives = API.Objectives(questID, i)
      out[questID] = e
      order[#order + 1] = e
    end
  end
  return out, order
end

function API.ItemCount(itemID)
  local f = (C_Item and C_Item.GetItemCount) or GetItemCount
  if not f then return 0 end
  local ok, n = pcall(f, itemID)
  return ok and n or 0
end

function API.ItemIcon(itemID, fallback)
  local f = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
  if f and itemID then
    local ok, icon = pcall(f, itemID)
    if ok and icon then return icon end
  end
  return fallback
end

-- Quests an item in your bags would start: the item waits in your bags, no log slot used.
function API.BagQuestStarts()
  local out = {}
  local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local questInfo = (C_Container and C_Container.GetContainerItemQuestInfo) or GetContainerItemQuestInfo
  local itemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
  if not (numSlots and questInfo) then return out end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (numSlots(bag) or 0) do
      local ok, a, b, c = pcall(questInfo, bag, slot)
      if ok then
        local qid, active
        if type(a) == "table" then qid, active = a.questID, a.isActive else qid, active = b, c end
        if qid and qid > 0 and not active then out[qid] = itemID and itemID(bag, slot) or true end
      end
    end
  end
  return out
end

function API.MapID()
  if C_Map and C_Map.GetBestMapForUnit then
    local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
    if ok then return m end
  end
end

-- where you stand, as a place on the continent: {c, wx, wy}
function API.WorldPosition()
  local m = API.MapID()
  if not (m and C_Map and C_Map.GetPlayerMapPosition) then return nil end
  local ok, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
  if not ok or not pos then return nil end
  local x, y = pos.x, pos.y
  if pos.GetXY then x, y = pos:GetXY() end
  if not x then return nil end
  return QB.Model.World(m, x * 100, y * 100)
end

function API.BindName()
  return GetBindLocation and GetBindLocation() or ""
end

-- the hearthstone is ready within a minute and a half
function API.HearthReady()
  local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
  if not f then return true end
  local ok, start, duration = pcall(f, 6948)
  if not ok or not start or start == 0 or not duration then return true end
  return (start + duration - GetTime()) < 90
end

function API.KnowsRiding()
  local known = IsPlayerSpell or IsSpellKnown
  if not known then return false end
  for _, id in ipairs({ 33388, 33391, 34090 }) do
    local ok, v = pcall(known, id)
    if ok and v then return true end
  end
  return false
end

function API.HasWellRested()
  if AuraUtil and AuraUtil.FindAuraByName then
    local ok, name = pcall(AuraUtil.FindAuraByName, "Well Rested", "player", "HELPFUL")
    if ok and name then return true end
  end
  return false
end

function API.Faction()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return f == "Horde" and "H" or "A"
end

function API.ClassBit()
  local _, _, id = UnitClass("player")
  if not id then return 0 end
  return 2 ^ (id - 1)
end

function API.RaceBit()
  local _, _, id = UnitRace("player")
  if not id then return 0 end
  return 2 ^ (id - 1)
end

-- one waypoint at a time: TomTom's arrow if you have it, else the game's own map pin
local tomtomUid
function API.SetWaypoint(m, x, y, title, quiet)
  if not (m and x and y) or m == 0 then return false end
  if TomTom and TomTom.AddWaypoint then
    if tomtomUid and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, tomtomUid) end
    tomtomUid = TomTom:AddWaypoint(m, x / 100, y / 100, { title = title, persistent = false, minimap = true, world = true })
    return true
  end
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint then
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(m) then return false end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(m, x / 100, y / 100))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    if not quiet then QB:Print(string.format("Waypoint: %s (%.0f, %.0f)", title or "", x, y)) end
    return true
  end
  QB:Print(string.format("%s: %.1f, %.1f", title or "", x, y))
  return false
end

----------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------
function QB:Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffc6af8dQuestBank|r " .. msg)
  else
    print("QuestBank " .. msg)
  end
end

function QB.Comma(n)
  local s = tostring(math.floor((n or 0) + 0.5))
  local k
  repeat s, k = s:gsub("^(%-?%d+)(%d%d%d)", "%1,%2") until k == 0
  return s
end

function QB.Short(n)
  n = n or 0
  if n >= 1000 then return (string.format("%.1fk", n / 1000):gsub("%.0k", "k")) end
  return tostring(n)
end

function QB.Clock(minutes)
  local m = math.floor((minutes or 0) + 0.5)
  return string.format("%d:%02d", math.floor(m / 60), m % 60)
end

----------------------------------------------------------------------------
-- the catalog: every quest a character around level 20 can hold, both factions
-- D.Q[id] = { level, req, side, base, mult, turn NPC, giver NPC, category, class mask, flags }
-- flags: 1 dungeon, 2 group, 4 starts from an item, 8 multiplier not read from its page
----------------------------------------------------------------------------
local Q = {}
QB.Quest = Q
local cache = {}

local function npcView(i)
  local n = i and i > 0 and D.NPC[i]
  if not n then return nil end
  return { n = n[1], m = n[2], x = n[3], y = n[4], inside = n[5] < 0, place = n[12], idx = i }
end

function Q.Get(id)
  local c = cache[id]
  if c ~= nil then return c or nil end
  local r = D.Q[id]
  if not r then cache[id] = false; return nil end
  local turnIdx = r[6]
  if D.TURNH and D.TURNH[id] and (QB.faction or API.Faction()) == "H" then turnIdx = D.TURNH[id] end
  c = { id = id, name = D.QN[id] or ("Quest " .. id), lvl = r[1], req = r[2], side = r[3], base = r[4], mult = r[5],
        turnIdx = turnIdx, giveIdx = r[7], turn = npcView(turnIdx), give = npcView(r[7]), cat = D.CAT[r[8]], cls = r[9],
        flags = r[10], pre = D.PRE[id], tip = D.TIPS[id], bag = D.BAGQ[id], follow = D.FOLLOW[id],
        race = D.RACE[id], excl = D.EXCL[id], nextSteps = D.NEXT[id] }
  c.dungeon = c.flags % 2 == 1
  c.group = math.floor(c.flags / 2) % 2 == 1
  c.unconfirmed = math.floor(c.flags / 8) % 2 == 1
  c.icon = D.QICON[id] or (c.bag and c.bag[3] ~= 2 and API.ItemIcon(c.bag[1])) or API.ItemIcon(D.QITEM[id])
    or (c.cat and c.cat.icon) or D.TEX.questGeneric
  cache[id] = c
  return c
end

function Q.Full(q)
  return q.liveFull or QB.Model.Full(q)
end

-- Model reads this: the game's number if it reported one, else Classic base x the Forever multiplier
function Q.Raw(q)
  if q.liveFull then return q.liveFull end
  return math.floor((q.base or 0) * (q.mult or 1) + 0.5)
end

function Q.Label(id)
  if type(id) == "table" then
    local names = {}
    for _, x in ipairs(id) do names[#names + 1] = Q.Label(x) end
    return table.concat(names, " or ")
  end
  return D.STEPNAME[id] or D.QN[id] or ("quest " .. id)
end

-- a prerequisite: one quest, or a list of which any one will do
local function preDone(p)
  if type(p) == "table" then
    for _, x in ipairs(p) do if API.IsDone(x) then return true end end
    return false
  end
  return API.IsDone(p)
end
Q.PreDone = preDone

-- the chain up to and including this quest, for tooltips: "A Watchful Eye > Looking Further > Morganth"
function Q.ChainText(q)
  if not q.pre then return nil end
  local parts = {}
  for _, p in ipairs(q.pre) do parts[#parts + 1] = (preDone(p) and "|cff808080" or "") .. Q.Label(p) .. (preDone(p) and "|r" or "") end
  parts[#parts + 1] = q.name
  return table.concat(parts, " > ")
end

function Q.ForMe(q)
  local fac = QB.faction or API.Faction()
  if q.side == 1 and fac ~= "A" then return false end
  if q.side == 2 and fac ~= "H" then return false end
  if q.cls and q.cls > 0 then
    local bit = API.ClassBit()
    if bit > 0 and (math.floor(q.cls / bit) % 2) == 0 then return false end
  end
  if q.race then
    local bit = API.RaceBit()
    if bit > 0 and bit <= 128 and (math.floor(q.race / bit) % 2) == 0 then return false end
  end
  return true
end

----------------------------------------------------------------------------
-- XP straight from the game: what the quest log, the NPC's quest window or a hand-in reported.
-- QuestBankDB.live[id] = { full = XP at full value, lvl = your level then, src = "log" | "npc" | "turnin" | "party" }
----------------------------------------------------------------------------
local Live = {}
QB.Live = Live

function Live.Record(id, xp, level, src, rested)
  local q = Q.Get(id)
  if not (q and xp and xp > 0 and level) then return end
  local pct = QB.Model.Pct(q.lvl, level)
  if pct < 100 then return end -- a grey quest's number says little about its full value
  local full = xp
  if rested then full = math.floor(xp / 1.03 / 10 + 0.5) * 10 end
  -- a number far off what the quest could pay is someone else's quest, not this one's
  local listed = QB.Model.Listed(q)
  if listed > 0 and (full > listed * 6 or full < listed * 0.2) then return end
  QuestBankDB.live = QuestBankDB.live or {}
  local old = QuestBankDB.live[id]
  if old and old.src ~= "party" and src == "party" then return end
  QuestBankDB.live[id] = { full = full, lvl = level, src = src }
  q.liveFull = full
  if QB.Sync and src ~= "party" then QB.Sync:QueueLive(id, full, level) end
end

function Live.Apply()
  for id, v in pairs(QuestBankDB.live or {}) do
    local q = Q.Get(id)
    if q then q.liveFull = v.full end
  end
end

function Live.Source(q)
  local v = QuestBankDB.live and QuestBankDB.live[q.id]
  if not v then return nil end
  local where = { log = "your quest log", npc = "the quest window", turnin = "a hand-in", party = "a party member's game" }
  return string.format("the game (%s, level %d)", where[v.src] or v.src, v.lvl)
end

-- the quest the NPC window shows, and the XP it offers
local function windowXP(src)
  local id = GetQuestID and GetQuestID()
  local xp = GetRewardXP and GetRewardXP()
  if id and id > 0 and xp and xp > 0 then Live.Record(id, xp, UnitLevel("player"), src, API.HasWellRested()) end
end
QB.WindowXP = windowXP

----------------------------------------------------------------------------
-- settings: account-wide switches, and one plan per character
----------------------------------------------------------------------------
local DEFAULTS = {
  mounted = "auto", bag = "auto", goal = "hour", routeMode = "now", tab = 1, pins = true,
  minimap = { angle = 205, hide = false }, share = { party = true, guild = true },
}

function QB:Settings()
  QuestBankDB = QuestBankDB or {}
  local db = QuestBankDB
  db.chars = db.chars or {}
  for k, v in pairs(db) do
    if type(v) == "table" and v.completed and k ~= "chars" then db.chars[k] = v; db[k] = nil end
  end
  db.settings = db.settings or {}
  local s = db.settings
  for k, v in pairs(DEFAULTS) do
    if s[k] == nil then
      if type(v) == "table" then
        local c = {}
        for kk, vv in pairs(v) do c[kk] = vv end
        s[k] = c
      else
        s[k] = v
      end
    end
  end
  db.turnins = db.turnins or {}
  db.runs = db.runs or {}
  db.plans = db.plans or {}
  return s
end

function QB:CharKey()
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "?"
  return (UnitName("player") or "?") .. "-" .. realm
end

function QB:Plan()
  local s = self:Settings()
  local db = QuestBankDB
  local key = self:CharKey()
  local p = db.plans[key]
  if not p then
    p = { add = {}, cut = {}, seen = {}, removed = {} }
    -- 2.0 kept one account-wide list of explicit choices
    if s.plan then
      for id, on in pairs(s.plan) do if on then p.add[id] = true end end
      s.plan = nil
    end
    db.plans[key] = p
  end
  p.add, p.cut, p.seen, p.removed = p.add or {}, p.cut or {}, p.seen or {}, p.removed or {}
  return p
end

function QB:Mounted()
  local s = self:Settings().mounted
  if s == "auto" then return API.KnowsRiding(), true end
  return s == true, false
end

function QB:BagBonus()
  local s = self:Settings().bag
  if s == "auto" then return API.HasWellRested(), true end
  return s == true, false
end

----------------------------------------------------------------------------
-- state
----------------------------------------------------------------------------
QB.state = { level = 1, xp = 0, log = {}, logOrder = {}, bagStarts = {} }
local function emptyRoute() return { legs = {}, t = 0, xp = 0, level = 0, at60 = 0, count = 0, byQuest = {}, unplaced = {}, empty = true } end
QB.routeNow, QB.routePlan = emptyRoute(), emptyRoute()
local turnedIn = {} -- this session, so a hand-in is never mistaken for an abandon

-- quests that left your log without being handed in
local function trackRemovals(s)
  if not QB.logReady then return end
  local p = QB:Plan()
  for id, title in pairs(p.seen) do
    if not s.log[id] then
      if not turnedIn[id] and not API.IsDone(id) then
        local q = Q.Get(id)
        local value = q and QB.Model.XpAt(q, math.max(s.level, 20)) or nil
        p.removed[id] = { title = title, at = time and time() or 0, value = value }
        if QB.loggedIn then
          QB:Print(string.format("%s left your log without a hand-in%s. The plan no longer counts it.", title,
            value and (" (worth about " .. QB.Comma(value) .. " XP)") or ""))
        end
      end
      p.seen[id] = nil
    end
  end
  for id, e in pairs(s.log) do
    p.seen[id] = e.title
    p.removed[id] = nil
  end
end

function QB:ReadState()
  local s = self.state
  s.level = UnitLevel("player") or 1
  s.xp = UnitXP("player") or 0
  s.xpMax = UnitXPMax("player") or 1
  s.log, s.logOrder = API.LogQuests()
  s.logCount = #s.logOrder
  s.mapID = API.MapID()
  s.bagStarts = API.BagQuestStarts()
  local _, class = UnitClass("player")
  s.class = class
  s.name = UnitName("player")
  QB.faction = API.Faction()
  trackRemovals(s)
  return s
end

local function progressText(entry)
  local parts = {}
  for _, o in ipairs(entry.objectives or {}) do
    if not o.done then
      if o.have and o.need and o.need > 0 then
        parts[#parts + 1] = o.have .. "/" .. o.need
      elseif o.text then
        parts[#parts + 1] = o.text
      end
    end
  end
  if #parts == 0 then return "In your log" end
  return "In your log: " .. table.concat(parts, ", ")
end

-- code: done | banked | active | partial | bagstart | item | locked | prereq | todo | wrong
function QB:Status(q)
  local s = self.state
  if API.IsDone(q.id) then return { code = "done", text = "Handed in already" } end
  local e = s.log[q.id]
  if e then
    if e.complete then return { code = "banked", text = "Banked, ready to hand in" } end
    return { code = "active", text = progressText(e) }
  end
  local bag = q.bag
  if bag and bag[3] == 1 then
    local n = API.ItemCount(bag[1])
    if n >= bag[2] then return { code = "banked", text = "Banked in your bags", bag = true } end
    if n > 0 then return { code = "partial", text = n .. "/" .. bag[2] .. " in your bags" } end
  elseif s.bagStarts[q.id] or (bag and bag[3] == 0 and API.ItemCount(bag[1]) > 0) then
    return { code = "bagstart", text = "Starts from an item in your bags" }
  end
  local fromItem = bag and bag[3] == 0
  if not Q.ForMe(q) then return { code = "wrong", text = "Not for your faction, race or class" } end
  if q.excl then
    for _, other in ipairs(q.excl) do
      if API.IsDone(other) or s.log[other] then
        return { code = "wrong", text = "Ruled out: you took " .. Q.Label(other) .. " instead" }
      end
    end
  end
  if s.level < (q.req or 1) then return { code = "locked", text = "Needs level " .. q.req } end
  if q.pre then
    -- a step you hold or finished means every step before it is behind you
    local from = 1
    for k = #q.pre, 1, -1 do
      local p = q.pre[k]
      if preDone(p) or (type(p) ~= "table" and s.log[p]) then from = k break end
    end
    local left = 0
    for k = from, #q.pre do if not preDone(q.pre[k]) then left = left + 1 end end
    for k = from, #q.pre do
      local p = q.pre[k]
      if not preDone(p) then
        local held = type(p) ~= "table" and s.log[p]
        local steps = left > 1 and string.format(" (%d steps)", left) or ""
        if held then return { code = "prereq", text = "Hand in " .. Q.Label(p) .. " first" .. steps, pre = p } end
        return { code = "prereq", text = "First: " .. Q.Label(p) .. steps, pre = p }
      end
    end
  end
  if fromItem then return { code = "item", text = "Starts from an item: " .. (bag[4] or "a drop") } end
  return { code = "todo", text = "Not started" }
end

----------------------------------------------------------------------------
-- the plan: what you hold (minus what you cut) plus what you chose to fetch
----------------------------------------------------------------------------
function QB:IsCut(id) return self:Plan().cut[id] and true or false end
function QB:IsAdded(id) return self:Plan().add[id] and true or false end

function QB:InPlan(q, st)
  if self:IsCut(q.id) then return false end
  st = st or self:Status(q)
  if st.code == "done" or st.code == "wrong" then return false end
  if self.state.log[q.id] or st.bag then return true end
  return self:IsAdded(q.id)
end

-- in the log: cut it or keep it; not in the log: fetch it or not
function QB:ToggleAdd(id)
  local p = self:Plan()
  local q = Q.Get(id)
  if self.state.log[id] or (q and self:Status(q).bag) then
    p.cut[id] = (not p.cut[id]) or nil
  else
    p.add[id] = (not p.add[id]) or nil
  end
  self:MarkDirty()
end

-- entries for the planner: { q, st, after }
function QB:RouteEntries(mode)
  local list, seen = {}, {}
  local s = self.state
  local function consider(id)
    if seen[id] then return end
    seen[id] = true
    local q = Q.Get(id)
    if not q then return end
    local st = self:Status(q)
    -- a delivery you're handed on the day is planned behind its first step, unless you already hold it
    if q.follow and not s.log[id] and not st.bag then return end
    local want
    if mode == "plan" then
      want = self:InPlan(q, st)
    else
      want = st.code == "banked" and not self:IsCut(id)
    end
    if want then list[#list + 1] = { q = q, st = st } end
  end
  for _, e in ipairs(s.logOrder) do consider(e.id) end
  for id in pairs(s.bagStarts) do consider(id) end
  for id in pairs(D.BAGQ) do consider(id) end
  if mode == "plan" then for id in pairs(self:Plan().add) do consider(id) end end
  -- quests handed to you on the day by another hand-in, delivered at once
  local inList = {}
  for _, e in ipairs(list) do inList[e.q.id] = true end
  for id, parent in pairs(D.FOLLOW) do
    local q = Q.Get(id)
    if q and inList[parent] and not inList[id] and not API.IsDone(id) and Q.ForMe(q) then
      list[#list + 1] = { q = q, st = { code = "follow", text = "Given when you hand in " .. Q.Label(parent) }, after = parent }
    end
  end
  return list
end

-- quests in your log the catalog does not know
function QB:Unknown()
  local out = {}
  for _, e in ipairs(self.state.logOrder) do
    if not Q.Get(e.id) then out[#out + 1] = e end
  end
  return out
end

----------------------------------------------------------------------------
-- the hand-in run: what you handed in, when, and what it paid
----------------------------------------------------------------------------
local Run = {}
QB.Run = Run

function Run.Get()
  local run = QuestBankDB and QuestBankDB.run
  if run and run.key == QB:CharKey() then return run end
end

function Run.Start()
  local r = QB.routeNow
  local run = { started = time(), key = QB:CharKey(), level = QB.state.level, xp = QB.state.xp, done = {}, plan = {},
                predicted = r and r.xp or 0, predictedT = r and r.t or 0, hearthUsed = false }
  if r then
    for _, leg in ipairs(r.legs) do
      for _, row in ipairs(leg.rows) do run.plan[row.q.id] = { t = leg.t, xp = row.xp, stop = leg.stop.name } end
    end
  end
  QuestBankDB.run = run
  QB:Print("Hand-in run started. Each quest is ticked off with the XP it paid; the route re-plans from where you stand.")
  QB:MarkDirty()
end

function Run.Stop()
  local run = Run.Get()
  if not run then return end
  run.ended = time()
  local got, n = 0, 0
  for _, d in pairs(run.done) do got, n = got + (d.xp or 0), n + 1 end
  run.got, run.count = got, n
  table.insert(QuestBankDB.runs, run)
  QuestBankDB.run = nil
  QB:Print(string.format("Run ended: %d quests, %s XP in %s.", n, QB.Comma(got), QB.Clock((run.ended - run.started) / 60)))
  QB:MarkDirty()
end

function Run.Elapsed()
  local run = Run.Get()
  if not run then return 0 end
  return (time() - run.started) / 60
end

function Run.Record(id, xp, name)
  local run = Run.Get()
  if not run then return end
  run.done[id] = { xp = xp, t = Run.Elapsed(), name = name, n = run.n and run.n + 1 or 1 }
  run.n = (run.n or 0) + 1
end

-- minutes ahead of the plan (negative: behind), from the last hand-in the plan timed
function Run.Pace()
  local run = Run.Get()
  if not run then return nil end
  local lastT, planT
  for id, d in pairs(run.done) do
    local p = run.plan[id]
    if p and (not lastT or d.t > lastT) then lastT, planT = d.t, p.t end
  end
  if not lastT then return nil end
  return planT - lastT
end

function Run.Totals()
  local run = Run.Get()
  if not run then return 0, 0 end
  local got, n = 0, 0
  for _, d in pairs(run.done) do got, n = got + (d.xp or 0), n + 1 end
  return got, n
end

----------------------------------------------------------------------------
-- recompute: two routes, cached until something they depend on changes, planned in the background
----------------------------------------------------------------------------
local function signature(list, opts)
  local parts = { opts.level, opts.xp, tostring(opts.mounted), tostring(opts.bonus), opts.goal, opts.fac,
                  opts.startHub or "-", tostring(opts.noHearth) }
  for _, e in ipairs(list) do parts[#parts + 1] = e.q.id .. (e.st and e.st.code or "") end
  return table.concat(parts, ":")
end

function QB:Recompute(sync)
  self:ReadState()
  local set = self:Settings()
  local opts = {
    level = self.state.level, xp = self.state.xp, mounted = (self:Mounted()), bonus = (self:BagBonus()),
    goal = set.goal, fac = QB.faction,
  }
  local nowOpts = {}
  for k, v in pairs(opts) do nowOpts[k] = v end
  if Run.Get() then
    -- mid-run: the rest of the route from where you stand
    local wp = API.WorldPosition()
    if wp then
      local place = QB.Model.Place(QB.faction, wp.c, wp.wx, wp.wy)
      if place.hub > 0 then nowOpts.start, nowOpts.startHub = wp, place.hub end
    end
    nowOpts.noHearth = Run.Get().hearthUsed or not API.HearthReady()
    nowOpts.goal = "route"
  end
  local now, plan = self:RouteEntries("now"), self:RouteEntries("plan")
  local sigNow, sigPlan = signature(now, nowOpts), signature(plan, opts)
  local needNow = sigNow ~= self.sigNow
  local needPlan = sigPlan ~= self.sigPlan
  if not (needNow or needPlan) then return self.routeNow, self.routePlan end
  local want = sigNow .. "|" .. sigPlan
  if self.pending == want and not sync then return self.routeNow, self.routePlan end
  local function work()
    if needNow then self.routeNow, self.sigNow = QB.Model.Plan(now, nowOpts), sigNow end
    if needPlan then self.routePlan, self.sigPlan = QB.Model.Plan(plan, opts), sigPlan end
  end
  if sync then
    self.pending = nil
    QB.Model.Cancel()
    work()
  else
    self.pending = want
    QB.Model.Async(work, function()
      QB.pending = nil
      QB:Changed()
    end)
  end
  self.dirty = false
  return self.routeNow, self.routePlan
end

-- XP a quest is worth on the day: from a route, else at your level (20 at the least)
function QB:Value(id)
  for _, r in ipairs({ self.routePlan, self.routeNow }) do
    if r and r.byQuest and r.byQuest[id] then return r.byQuest[id], true end
  end
  local q = Q.Get(id)
  if not q then return nil end
  return QB.Model.XpAt(q, math.max(self.state.level, 20)), false
end

----------------------------------------------------------------------------
-- export: the file someone can read to check your plan
----------------------------------------------------------------------------
local function completedIDs()
  API.RefreshDone()
  return API.DoneList()
end

local function bagItems()
  local found = {}
  local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local itemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
  local itemLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
  local itemInfo = C_Container and C_Container.GetContainerItemInfo
  if not (numSlots and itemID) then return {} end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (numSlots(bag) or 0) do
      local id = itemID(bag, slot)
      if id then
        local count = 1
        if itemInfo then
          local info = itemInfo(bag, slot)
          if info and info.stackCount then count = info.stackCount end
        elseif GetContainerItemInfo then
          local _, c = GetContainerItemInfo(bag, slot)
          count = c or 1
        end
        local link = itemLink and itemLink(bag, slot)
        local e = found[id]
        if not e then
          e = { id = id, name = link and link:match("%[(.-)%]") or nil, count = 0 }
          found[id] = e
        end
        e.count = e.count + count
      end
    end
  end
  local list = {}
  for _, e in pairs(found) do list[#list + 1] = e end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

function QB:Snapshot(reason)
  local s = self:ReadState()
  local _, race = UnitRace("player")
  local log = {}
  for _, e in ipairs(s.logOrder) do
    log[#log + 1] = { id = e.id, title = e.title, level = e.level, complete = e.complete, objectives = e.objectives }
  end
  local done = completedIDs()
  QuestBankDB.chars[self:CharKey()] = {
    saved = date("%Y-%m-%d %H:%M"), reason = reason, version = QB.version,
    level = s.level, xp = s.xp, xpMax = s.xpMax, class = s.class, race = race,
    faction = UnitFactionGroup("player"), completed = done, log = log, bags = bagItems(),
  }
  return #done, #log
end

----------------------------------------------------------------------------
-- events
----------------------------------------------------------------------------
local frame = CreateFrame("Frame")
QB.eventFrame = frame
local pending = false

-- something the plan depends on changed: refresh what is on screen a moment later
function QB:MarkDirty()
  self.dirty = true
  if pending then return end
  pending = true
  C_Timer.After(0.3, function()
    pending = false
    QB:Changed()
  end)
end

function QB:Changed()
  QB:Recompute()
  if QB.UI and QB.UI.frame and QB.UI.frame:IsShown() then QB.UI:Refresh() end
  if QB.Pins then QB.Pins:Update() end
  if QB.Sync then QB.Sync:Changed() end
end

local function onTurnIn(questID, xpReward)
  turnedIn[questID] = true
  API.MarkDone(questID)
  local q = Q.Get(questID)
  Live.Record(questID, xpReward, QB.state.level or UnitLevel("player"), "turnin", API.HasWellRested())
  local predicted = QB.routeNow and QB.routeNow.byQuest and QB.routeNow.byQuest[questID]
  table.insert(QuestBankDB.turnins, {
    id = questID, xp = xpReward, predicted = predicted, level = UnitLevel("player"), at = date("%Y-%m-%d %H:%M:%S"),
    mult = q and q.mult, base = q and q.base,
  })
  local level = UnitLevel("player") or 0
  if not Run.Get() and predicted and level < QB.CAP and (xpReward or 0) > 0 then Run.Start() end
  Run.Record(questID, xpReward, q and q.name)
  if not q then return end
  if (xpReward or 0) == 0 and predicted and predicted > 0 then
    QB:Print(string.format("%s paid no XP (the level cap?). The plan counted %s for it.", q.name, QB.Comma(predicted)))
    return
  end
  local msg = string.format("%s: +%s XP", q.name, QB.Comma(xpReward or 0))
  if predicted and xpReward and xpReward > 0 and math.abs(predicted - xpReward) > 25 then
    msg = msg .. string.format(" (plan said %s)", QB.Comma(predicted))
  end
  QB:Print(msg)
end

frame:SetScript("OnEvent", function(_, event, a1, a2, a3)
  if event == "ADDON_LOADED" then
    if a1 == ADDON then QB:Settings(); Live.Apply() end
    return
  elseif event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" then
    windowXP("npc")
    return
  elseif event == "PLAYER_LOGIN" then
    QB:ReadState()
    if QB.Minimap then QB.Minimap:Create() end
    if QB.Pins then QB.Pins:Init() end
    if QB.Sync then QB.Sync:Init() end
    C_Timer.After(8, function() QB:Snapshot("login") end)
    C_Timer.After(4, function() QB:Changed() end)
    return
  elseif event == "PLAYER_LOGOUT" then
    QB:Snapshot("logout")
    return
  elseif event == "QUEST_LOG_UPDATE" then
    if not QB.logReady then
      API.RefreshDone()
      QB.logReady = true
      QB:ReadState()
      QB.loggedIn = true
    end
  elseif event == "QUEST_TURNED_IN" then
    onTurnIn(a1, a2)
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    if a1 ~= "player" then return end
    if (a3 == 8690 or a3 == 556) and Run.Get() then Run.Get().hearthUsed = true end
  elseif event == "UNIT_AURA" and a1 ~= "player" then
    return
  end
  QB:MarkDirty()
end)

for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN",
  "QUEST_ACCEPTED", "QUEST_REMOVED", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE",
  "ZONE_CHANGED_NEW_AREA", "UNIT_AURA", "HEARTHSTONE_BOUND", "UNIT_SPELLCAST_SUCCEEDED", "QUEST_DETAIL", "QUEST_COMPLETE" }) do
  pcall(frame.RegisterEvent, frame, e)
end

----------------------------------------------------------------------------
-- slash
----------------------------------------------------------------------------
SLASH_QUESTBANK1 = "/questbank"
SLASH_QUESTBANK2 = "/qb"
SlashCmdList.QUESTBANK = function(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "export" then
    local done, inLog = QB:Snapshot("manual")
    QB:Print(done .. " completed quests and " .. inLog .. " in your log saved. Type /reload to write the file.")
  elseif cmd == "reset" then
    QB:Settings().pos = nil
    if QB.UI.frame then QB.UI.frame:ClearAllPoints(); QB.UI.frame:SetPoint("CENTER") end
  elseif cmd == "minimap" then
    local m = QB:Settings().minimap
    m.hide = not m.hide
    if QB.Minimap then QB.Minimap:Update() end
  elseif cmd == "route" then
    QB.UI:Open(3)
  elseif cmd == "prep" then
    QB.UI:Open(2)
  elseif cmd == "party" then
    QB.UI:Open(4)
  elseif cmd == "start" then
    QB:Recompute(true); Run.Start()
  elseif cmd == "stop" then
    Run.Stop()
  elseif cmd == "sync" and QB.Sync then
    if rest ~= "" then QB.Sync:Whisper(rest) else QB.Sync:Broadcast(true) end
  elseif cmd == "pins" and QB.Pins then
    QB.Pins:Toggle()
  elseif cmd == "next" and QB.Pins then
    QB.Pins:PinNext(true)
  elseif cmd == "done" then
    QB:ReadState()
    local ids = {}
    if tonumber(rest) then
      ids[1] = tonumber(rest)
    elseif rest ~= "" then
      local want = rest:lower()
      for id, name in pairs(D.QN) do
        if name:lower():find(want, 1, true) then ids[#ids + 1] = id end
      end
      table.sort(ids)
    end
    if #ids == 0 then QB:Print("Type /qb done and a quest name or ID, like /qb done Glowing Shard.") end
    for i = 1, math.min(6, #ids) do
      local id = ids[i]
      local q = Q.Get(id)
      local inList, flag, count = API.DoneSources(id)
      QB:Print(string.format("%d %s: %s. The game's list of %d completed quests: %s. The quest's own flag: %s.", id,
        D.QN[id] or "?", q and QB:Status(q).text or "not in QuestBank's catalog", count, inList and "yes" or "no",
        flag == nil and "can't ask" or (flag and "yes" or "no")))
    end
  else
    QB.UI:Toggle()
  end
end
