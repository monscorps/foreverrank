-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank core: game state, quest status, the plan, the hand-in run, settings, events, export.
-- Everything here reads the game. Nothing accepts, abandons or hands in a quest for you.
local ADDON, QB = ...
QB.version = "3.4.9"
QB.MAXLEVEL = 60
QB.LOG_SLOTS = 40 -- quests the Forever log holds (the game's own UI constant still says 25; see QB:FixEscortPrompt)
QB.CAP = 60 -- the level XP runs to in the plans: set from the level lock in ReadState

local D = QB.Data
local API = {}
QB.API = API

----------------------------------------------------------------------------
-- errors: caught where QuestBank runs code, recorded with the stack, and never in your way.
-- /qb errors shows them to copy. (QUESTBANK_DEV makes them fatal again, for the test harness.)
----------------------------------------------------------------------------
local Err = {}
QB.Err = Err
local toldErrors = false

local function catch(e)
  local stack = (debugstack and debugstack(2, 16, 4)) or (debug and debug.traceback and debug.traceback("", 2)) or ""
  return { msg = tostring(e), stack = stack }
end

function Err.Record(msg, stack, where)
  QuestBankDB = QuestBankDB or {}
  QuestBankDB.errors = QuestBankDB.errors or {}
  local list = QuestBankDB.errors
  local now = date and date("%Y-%m-%d %H:%M:%S") or ""
  for _, e in ipairs(list) do
    if e.msg == msg then e.count, e.last = e.count + 1, now; return end
  end
  table.insert(list, 1, { msg = msg, stack = stack, where = where, count = 1, first = now, last = now, version = QB.version })
  while #list > 20 do table.remove(list) end
  if not toldErrors then
    toldErrors = true
    if QB.Print then QB:Print("ran into a problem and carried on. /qb errors shows the details to copy into the Discord.") end
  end
end

-- a function that records its errors instead of raising them
function QB.Safe(fn, where)
  return function(...)
    local n, args = select("#", ...), { ... }
    local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end, catch)
    if not ok then
      if QUESTBANK_DEV then error(err.msg .. "\n" .. err.stack, 0) end
      Err.Record(err.msg, err.stack, where)
    end
  end
end

-- call now, the same way
function QB.Try(where, fn, ...)
  return QB.Safe(fn, where)(...)
end

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

-- what this character handed in with QuestBank watching, kept per character: uploads showed quests handed in one
-- day and missing from the game's list the next (Seeking the Kor Gem, Bailor's Ore Shipment), offered again as new
local function handedSet(create)
  local db = QuestBankDB
  if not (db and db.plans) then return nil end
  local key = QB.charKey or (UnitName and UnitName("player") and QB:CharKey()) or nil
  if not key then return nil end
  local p = db.plans[key]
  if not p and create then p = QB:Plan() end
  if p then p.handed = p.handed or {} end
  return p and p.handed or nil
end

local doneSig
function API.RefreshDone()
  local t, n = readDone()
  local sig = n
  for id in pairs(t) do sig = sig + id end
  local h = handedSet(false)
  if h then for id in pairs(h) do t[id] = true end end
  local changed = doneSet ~= nil and sig ~= doneSig
  doneSet, doneCount, doneSig = t, n, sig
  doneRead = GetTime and GetTime() or 0
  if changed then
    QB.doneVer = (QB.doneVer or 0) + 1
    if QB.loggedIn and QB.MarkDirty then QB:MarkDirty() end
  end
end

function API.MarkDone(id)
  if not doneSet then API.RefreshDone() end
  if not doneSet[id] then doneSet[id] = true; doneCount = doneCount + 1; QB.doneVer = (QB.doneVer or 0) + 1 end
  local h = handedSet(true)
  if h then h[id] = (time and time()) or 0 end
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
    flag = ok and not (issecretvalue and issecretvalue(v)) and v == true
  elseif IsQuestFlaggedCompleted then
    local ok, v = pcall(IsQuestFlaggedCompleted, id)
    flag = ok and not (issecretvalue and issecretvalue(v)) and v == true
  end
  return doneSet[id] and true or false, flag, doneCount
end

function API.IsDone(id)
  -- an empty list usually means the game hasn't sent it yet: look again, but not on every call
  if not doneSet or (doneCount == 0 and (GetTime and GetTime() or 0) - doneRead > 5) then API.RefreshDone() end
  if doneSet[id] then return true end
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
    local ok, v = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
    return ok and not (issecretvalue and issecretvalue(v)) and v == true
  end
  if IsQuestFlaggedCompleted then
    local ok, v = pcall(IsQuestFlaggedCompleted, id)
    return ok and not (issecretvalue and issecretvalue(v)) and v == true
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
      -- (hidden entries are the game's own bookkeeping, not quests you hold)
      if info and not info.isHidden then title, level, isHeader, questID = info.title, info.level, info.isHeader, info.questID end
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

-- how many you carry (bags), or with includeBank, bags and bank together
function API.ItemCount(itemID, includeBank)
  local f = (C_Item and C_Item.GetItemCount) or GetItemCount
  if not f then return 0 end
  local ok, n = pcall(f, itemID, includeBank and true or false)
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
function API.SetWaypoint(m, x, y, title, quiet, place)
  -- a waypoint you asked for is one the arrow remembers; place == false says: not this one (the route's own)
  if not quiet and place ~= false and QB.Arrow then
    local p = place or (QB.Model and QB.Model.World and QB.Model.World(m, x, y))
    if p then QB.Arrow:Pin(title, p.c, p.wx, p.wy) end
  end
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
-- the bank: what each character keeps there, read whenever the bank is open and remembered
-- QuestBankDB.bank[character] = { at = time read, items = { [itemID] = count } }
----------------------------------------------------------------------------
local Bank = {}
QB.Bank = Bank

-- the items quests for your faction ask for, worked out once
local bankItems
local function bankItemList()
  if bankItems then return bankItems end
  local fac = QB.faction or API.Faction()
  local seen, out = {}, {}
  for qid, list in pairs(D.REQ) do
    local r = D.Q[qid]
    local side = r and r[3] or 0
    if side == 0 or (side == 1 and fac == "A") or (side == 2 and fac == "H") then
      for _, it in ipairs(list) do
        if not seen[it[1]] then seen[it[1]] = true; out[#out + 1] = it[1] end
      end
    end
  end
  bankItems = out
  return out
end

function Bank.Scan()
  if not QB.bankOpen then return end
  local items = {}
  for _, id in ipairs(bankItemList()) do
    local extra = API.ItemCount(id, true) - API.ItemCount(id)
    items[id] = extra > 0 and extra or false
  end
  for _, it in ipairs(D.TRACKED_ITEMS) do
    local extra = API.ItemCount(it.id, true) - API.ItemCount(it.id)
    items[it.id] = extra > 0 and extra or false
  end
  local keep = {}
  for id, n in pairs(items) do if n then keep[id] = n end end
  QuestBankDB.bank = QuestBankDB.bank or {}
  QuestBankDB.bank[QB:CharKey()] = { at = time(), items = keep }
end

-- how many sit in your bank, and when that was read (nil: never)
function Bank.Count(itemID)
  if QB.bankOpen then return math.max(0, API.ItemCount(itemID, true) - API.ItemCount(itemID)), time() end
  local b = QuestBankDB and QuestBankDB.bank and QuestBankDB.bank[QB:CharKey()]
  if not b then return 0, nil end
  return b.items[itemID] or 0, b.at
end

-- what a quest asks you to bring: { id, name, need, bags, bank }
function Bank.Items(q)
  local list = D.REQ[q.id]
  if not list then return nil end
  local out = {}
  for _, it in ipairs(list) do
    local bank = Bank.Count(it[1])
    out[#out + 1] = { id = it[1], need = it[2], name = it[3] ~= "" and it[3] or ("item " .. it[1]), bags = API.ItemCount(it[1]), bank = bank }
  end
  return out
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

-- is version a newer than b ("3.3.0" against "3.2.1")
function QB.Newer(a, b)
  local function parts(v)
    local x, y, z = tostring(v or ""):match("^(%d+)%.(%d+)%.?(%d*)")
    return tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
  end
  local a1, a2, a3 = parts(a)
  local b1, b2, b3 = parts(b)
  if a1 ~= b1 then return a1 > b1 end
  if a2 ~= b2 then return a2 > b2 end
  return a3 > b3
end

QB.DOWNLOAD = "https://foreverrank.com/questbank/"

-- a party or guild member runs a newer QuestBank: say so once a session (Settings can turn it off)
function QB:SawVersion(v, who)
  if not v or not v:match("^%d+%.%d+") or not QB.Newer(v, QB.version) then return end
  if QB.newest and not QB.Newer(v, QB.newest.version) then return end
  QB.newest = { version = v, who = who }
  if self:Settings().updates and not QB.toldNewer then
    QB.toldNewer = true
    QB:Print(string.format("QuestBank %s is out (%s runs it); you have %s. Type /qb update for the download link.", v, who or "someone", QB.version))
  end
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
  c.classic = math.floor(c.flags / 16) % 2 == 1      -- from the Classic database, not seen in Forever yet
  c.dungeonMult = math.floor(c.flags / 32) % 2 == 1  -- multiplier taken from its dungeon's other quests
  c.xpUnknown = math.floor(c.flags / 64) % 2 == 1
  c.sodLeftover = math.floor(c.flags / 128) % 2 == 1 -- Season of Discovery data whose NPC isn't known in Forever
  c.nerfed = math.floor(c.flags / 256) % 2 == 1      -- multiplier computed from the pre-cut read (D.NERF): the extra above x1 halved
  c.confirmed = math.floor(c.flags / 512) % 2 == 1   -- XP as the game paid it after the cut (a hand-in or quest window, build 70170+)
  c.wanted = math.floor(c.flags / 1024) % 2 == 1     -- a wanted poster
  c.escort = math.floor(c.flags / 2048) % 2 == 1     -- an escort
  c.repeatable = math.floor(c.flags / 4096) % 2 == 1 -- repeatable: never suggested
  c.near = math.floor(c.flags / 8192) % 2 == 1       -- kept as read: the game paid within a few percent of this number
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
    local names, seen = {}, {}
    for _, x in ipairs(id) do
      local n = Q.Label(x)
      if not seen[n] then seen[n] = true; names[#names + 1] = n end
    end
    return table.concat(names, " or ")
  end
  return D.STEPNAME[id] or D.QN[id] or ("quest " .. id)
end

-- a prerequisite: one quest, or a list of which any one will do
-- the quests each plain step leads to (every quest whose chain lists it), built once from D.PRE
local laterOf
local function laterSteps(id)
  if not laterOf then
    laterOf = {}
    for x, pre in pairs(D.PRE or {}) do
      for _, p in ipairs(pre) do
        if type(p) ~= "table" then laterOf[p] = laterOf[p] or {}; table.insert(laterOf[p], x) end
      end
    end
  end
  return laterOf[id]
end

-- a later step of this quest's chain is in your log or done: the game offers a step only once the ones before it
-- are handed in, so this one is behind you. Returns that later step and "held" or "done".
function Q.Behind(id)
  local s = QB.state
  for _, x in ipairs(laterSteps(id) or {}) do
    if s and s.log and s.log[x] then return x, "held" end
    if API.IsDone(x) then return x, "done" end
  end
  return nil
end

local function preDone(p)
  if type(p) == "table" then
    for _, x in ipairs(p) do if API.IsDone(x) or Q.Behind(x) then return true end end
    return false
  end
  return API.IsDone(p) or Q.Behind(p) ~= nil
end
Q.PreDone = preDone

-- the step of this group (or the step itself) that is in your log
local function heldOf(p)
  local s = QB.state
  if not (s and s.log) then return nil end
  if type(p) ~= "table" then return s.log[p] and p or nil end
  for _, x in ipairs(p) do if s.log[x] then return x end end
  return nil
end
Q.HeldOf = heldOf

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

function Live.Record(id, xp, level, src)
  local q = Q.Get(id)
  if not (q and xp and xp > 0 and level) then return end
  local pct = QB.Model.Pct(q.lvl, level)
  if pct < 100 then return end -- a grey quest's number says little about its full value
  -- (the level-30 build's Well Rested speeds up rested XP and no longer adds to quest XP, so the number is taken as is)
  local full = xp
  -- a number far off what the quest could pay is someone else's quest, not this one's
  local listed = QB.Model.Listed(q)
  if listed > 0 and (full > listed * 6 or full < listed * 0.2) then return end
  -- a party member's number within a few percent of the catalog's confirms it rather than correcting it: their
  -- game may carry a bonus yours doesn't (the old build's rest stacks), and your own windows and hand-ins still win
  if src == "party" and listed > 0 and math.abs(full - listed) <= listed * 0.05 then return end
  QuestBankDB.live = QuestBankDB.live or {}
  local old = QuestBankDB.live[id]
  if old and old.src ~= "party" and src == "party" then return end
  QuestBankDB.live[id] = { full = full, lvl = level, src = src, at = date("%Y-%m-%d") }
  if q.liveFull ~= full then QB.liveVer = (QB.liveVer or 0) + 1 end
  q.liveFull = full
  if QB.Sync and src ~= "party" then QB.Sync:QueueLive(id, full, level) end
end

function Live.Apply()
  local db = QuestBankDB
  db.live = db.live or {}
  -- Blizzard cut dungeon quests' extra XP (D.NERF, 2026-10-01): what the game said about those quests before the
  -- cut is stale, so it is forgotten once; fresh quest windows and hand-ins teach the new numbers. A pre-cut
  -- number is at least 1.4 times the cut one, so a reading well above the catalog's value is the stale kind and
  -- one at or below it is fresh and stays. (Era 2 was 3.4.4's purge; 3.4.6 runs once more for the quests it
  -- left out, keeping what 3.4.4 and 3.4.5 users learned since.)
  local era = db.liveEra or 0
  if era < 3 then -- (by era, not by D.NERF: the cut happened whatever the catalog's later state)
    for id, v in pairs(db.live) do
      local q = Q.Get(id)
      if q then
        local stale = false
        if q.nerfed or q.confirmed or (q.mult or 1) > 1 then
          stale = (v.full or 0) > QB.Model.Listed(q) * 1.15
        elseif q.dungeon and q.unconfirmed and not q.xpUnknown and era < 2 then
          stale = true -- an unread dungeon quest: the old reading may carry the old extra (a quest with no XP in
                       -- the catalog keeps its reading: a high number beats none)
        end
        if stale then db.live[id] = nil; q.liveFull = nil end
      end
    end
    db.liveEra = 3
  end
  for id, v in pairs(db.live) do
    local q = Q.Get(id)
    if q then q.liveFull = v.full end
  end
end

-- a value from the client, or nil when the client hides it (a secret value): for ids and names before any use
function QB.Plain(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

-- what the game hands addons for a quest's XP on this client, the last dozen times (window and hand-in): the
-- uploads show whether the number is there, hidden (a secret value) or missing, which decides how the catalog learns
function QB.NoteXPSeen(how, id, xp)
  local db = QuestBankDB
  if not db then return end
  db.diag = db.diag or {}
  local d = db.diag.xp or {}
  db.diag.xp = d
  local secret = issecretvalue or function() return false end
  local kind = secret(xp) and "secret" or type(xp)
  d[#d + 1] = { how = how, id = secret(id) and -1 or id, kind = kind, v = kind == "number" and xp or nil,
                lvl = UnitLevel("player"), at = date("%Y-%m-%d %H:%M") }
  while #d > 12 do table.remove(d, 1) end
end

function Live.Source(q)
  local v = QuestBankDB.live and QuestBankDB.live[q.id]
  if not v then return nil end
  local where = { log = "your quest log", npc = "the quest window", turnin = "a hand-in", party = "a party member's game" }
  return string.format("the game (%s, level %d)", where[v.src] or v.src, v.lvl)
end

-- the quest the NPC window shows, and the XP it offers
local function windowXP(src, event)
  local id = GetQuestID and GetQuestID()
  local xp = GetRewardXP and GetRewardXP()
  QB.NoteXPSeen(event == "QUEST_DETAIL" and "detail" or "complete", id, xp)
  if issecretvalue and (issecretvalue(id) or issecretvalue(xp)) then return end -- hidden from addons: nothing to learn
  if id and id > 0 and xp and xp > 0 then Live.Record(id, xp, UnitLevel("player"), src) end
end
QB.WindowXP = windowXP

----------------------------------------------------------------------------
-- settings: account-wide switches, and one plan per character
----------------------------------------------------------------------------
local DEFAULTS = {
  mounted = "auto", goal = "hour", routeMode = "now", tab = 1, pins = true,
  minimap = { angle = 205, hide = false }, share = { party = true, guild = true },
  post = { party = true, guild = true, auto = true }, updates = true,
  -- how far above and below your level suggestions reach ("auto": 12 above while banking, 4 while
  -- questing, 7 below), and the zones, dungeons (by D.CAT key) and continents (0 Eastern Kingdoms,
  -- 1 Kalimdor) you told QuestBank to leave out of its suggestions
  rangeAbove = "auto", rangeBelow = "auto", skipCat = {}, skipCont = {},
  escort = true, -- keep the join prompt for escort quests working with 25 or more quests in the log
  -- off until asked for: accept quests for you (pick-ups, and escorts a party member starts), hand finished
  -- ones in for you (Auto.lua decides when that is wise), and two party-chat lines
  autoAccept = false, autoTurnIn = false, sayAccept = false, sayComplete = false,
  arrowMode = "route", -- what the direction arrow points at: route, handin, pickup, or pin (Arrow.lua)
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
  if QB.charKey then return QB.charKey end
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "?"
  return (UnitName("player") or "?") .. "-" .. realm
end

-- the realm's name comes two ways (with spaces, and without), and at logout only the spaced one answers, so a
-- character's saved tables could split in two keys: fold the spaced one into the normalized one, once, at login
function QB:MergeCharKeys()
  local db, key = QuestBankDB, QB.charKey
  local plain = GetRealmName and GetRealmName()
  if not (db and key and plain) then return end
  local other = (UnitName("player") or "?") .. "-" .. plain
  if other == key then return end
  for _, name in ipairs({ "plans", "chars", "held", "bank" }) do
    local t = db[name]
    if type(t) == "table" and t[other] ~= nil then
      if t[key] == nil then
        t[key] = t[other]
      elseif name == "plans" and type(t[key]) == "table" and type(t[other]) == "table" then
        local a, b = t[key], t[other]
        for _, f in ipairs({ "add", "cut", "seen", "removed", "handed", "rep" }) do
          if type(b[f]) == "table" then
            a[f] = a[f] or {}
            for k, v in pairs(b[f]) do if a[f][k] == nil then a[f][k] = v end end
          end
        end
        for k, v in pairs(b) do if a[k] == nil then a[k] = v end end
      elseif name == "chars" and type(t[key]) == "table" and type(t[other]) == "table" then
        local a, b = t[key], t[other]
        local na, nb = #(a.completed or {}), #(b.completed or {})
        if (b.saved or "") > (a.saved or "") then
          if nb < na then b.completed = a.completed end
          t[key] = b
        elseif nb > na then
          a.completed = b.completed
        end
      end
      t[other] = nil
    end
  end
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
  p.handed, p.rep = p.handed or {}, p.rep or {}
  return p
end

function QB:Mounted()
  local s = self:Settings().mounted
  if s == "auto" then return API.KnowsRiding(), true end
  return s == true, false
end

----------------------------------------------------------------------------
-- the level lock. Banking a log only makes sense while the game holds your level at a cap: you
-- finish quests, keep them, and hand them all in the hour the cap goes up. QuestBank finds the lock
-- three ways: you turned XP off, the game reports your level as its highest for now (Season of
-- Discovery's clients reported their phase caps like that), or a hand-in at your level paid no XP
-- when it should have. Otherwise you're questing: hand in as you go, and no rush.
--   lock   held at a cap: bank, and plan the hour after it lifts
--   rush   the cap went up: cash the bank in, until the hand-in run ends
--   quest  levelling as usual
----------------------------------------------------------------------------
-- the highest level the game lets you reach for now
function API.GameCap()
  local cap = QB.MAXLEVEL
  for _, name in ipairs({ "GetMaxPlayerLevel", "GetMaxLevelForPlayerExpansion" }) do
    local fn = _G[name]
    if fn then
      local ok, v = pcall(fn)
      if ok and type(v) == "number" and v >= 10 and v < cap then cap = v end
    end
  end
  return cap
end

-- the lock learned from hand-ins, for this realm, and only while it's fresh (caps last weeks, not months)
local function learnedLock()
  local all = QuestBankDB and QuestBankDB.lock
  local mine = type(all) == "table" and all[QB.RealmKey()]
  if type(mine) == "table" and mine.level and (time() - (mine.at or 0)) < 30 * 86400 then return mine.level end
end

function QB.RealmKey()
  return (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "?"
end

-- your choice, per character: "auto" (QuestBank looks), "on" (bank at the level you chose it), "off"
function QB:LockChoice()
  local p = self:Plan()
  return p.lock or "auto", p
end

function QB:SetLock(value)
  local p = self:Plan()
  p.lock = value ~= "auto" and value or nil
  p.lockAt = value == "on" and self.state.level or nil
  -- whatever the last lock was, your choice replaces it; a lock found again is noted again
  if QuestBankDB.held then QuestBankDB.held[self:CharKey()] = nil end
  self:MarkDirty()
end

-- nil, or the level the game holds you at and the level XP runs to once it lifts. Reads only.
function QB:Lock()
  local choice, p = self:LockChoice()
  local level = self.state.level or 1
  if choice == "off" or level >= QB.MAXLEVEL then return nil end
  local held
  if choice == "on" then
    if p.lockAt and level > p.lockAt then return nil end -- you levelled past it (ReadState tidies up)
    held = p.lockAt or level
  elseif IsXPUserDisabled and IsXPUserDisabled() then
    held = level
  else
    local cap = API.GameCap()
    if level >= cap then held = cap
    elseif learnedLock() == level then held = level end
  end
  if not held then return nil end
  local nextCap = (p.nextCap and p.nextCap > held) and p.nextCap or math.min(held + 10, QB.MAXLEVEL)
  return held, nextCap
end

-- what the last lock was, for the rush after it lifts
function QB:Held()
  return QuestBankDB and QuestBankDB.held and QuestBankDB.held[self:CharKey()]
end

function QB:Mode()
  if self:Lock() then return "lock" end
  local run = QB.Run and QB.Run.Get()
  if run then return run.mode == "quest" and "quest" or "rush" end
  -- the lock just lifted and you haven't levelled since: your first hand-in starts the run
  local held = self:Held()
  if held and self:LockChoice() ~= "off" and (self.state.level or 1) <= held.level then return "rush" end
  return "quest"
end

-- XP amounts that matter scale with the level: 500 XP is a lot at level 3 and nothing at 50. These
-- were tuned at level 20, so the factor is 1 there.
function QB.Scale(level)
  local T = QB.Data.TO_NEXT
  level = math.max(1, math.min(level or 20, #T))
  return T[level] / T[20]
end

-- a follow-up step worth walking to: for you, not done or held, not a Season of Discovery leftover, not
-- in a place you skipped, and within reach of your level (two above while questing, none at a lock).
-- One gate for the arrow's chain walk and for what a quest leads on to, so the two can't drift apart.
local function stepOpen(nq, lvl, banking, s)
  return nq ~= nil and Q.ForMe(nq) and not API.IsDone(nq.id) and not s.log[nq.id] and not nq.sodLeftover and not nq.repeatable
    and not Q.Behind(nq.id) and not QB:SkipsQuest(nq) and (nq.req or 1) <= lvl + (banking and 0 or 2)
end

-- a chain worth carrying on: the best later step you could take (up to three steps on), what it
-- pays and how many steps on. At a lock it's the step to bank instead, and only when it pays more
-- than this one; questing, it's where the chain leads next.
function QB:Upgrade(q)
  if not (q and q.nextSteps) then return nil end
  local s = self.state
  local lvl = s.level or 1
  local banking = self:Banking()
  local here = QB.Model.XpAt(q, lvl)
  local best, bestV, bestDepth
  local seen = {}
  local function walk(x, depth)
    if depth > 3 or not x.nextSteps then return end
    for _, nid in ipairs(x.nextSteps) do
      local nq = Q.Get(nid)
      if nq and not seen[nid] and stepOpen(nq, lvl, banking, s) then
        seen[nid] = true
        local v = QB.Model.XpAt(nq, lvl)
        -- a step handed in inside a dungeon can't be banked; the one after it can
        if not (banking and nq.turn and nq.turn.inside) and (not bestV or v > bestV) then best, bestV, bestDepth = nq, v, depth end
        walk(nq, depth + 1)
      end
    end
  end
  walk(q, 1)
  if not best or bestV <= 0 then return nil end
  if banking and bestV <= here + 300 * QB.Scale(lvl) then return nil end
  return best, bestV, bestDepth
end

-- banking words only where banking happens
function QB:Banking() return self:Mode() ~= "quest" end

-- two plain lines in party chat (raid chat in a raid), only when asked for in Settings and only while grouped
function QB:Announce(kind, title)
  local s = self:Settings()
  if kind == "accept" and not s.sayAccept then return end
  if kind == "complete" and not s.sayComplete then return end
  local channel = (IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) and "INSTANCE_CHAT"
    or ((IsInRaid and IsInRaid()) and "RAID") or ((IsInGroup and IsInGroup()) and "PARTY") or nil
  if not channel or not SendChatMessage then return end
  local clean = tostring(title or "a quest"):gsub("|", ""):sub(1, 200)
  pcall(SendChatMessage, (kind == "accept" and "Quest accepted: " or "Quest complete: ") .. clean, channel)
end

----------------------------------------------------------------------------
-- what may be suggested: the level window and the skipped places (Settings, the Plan cards, /qb skip)
----------------------------------------------------------------------------
-- levels above and below yours that suggestions reach, and whether each is QuestBank's own choice
function QB:Range()
  local s = self:Settings()
  local autoA, autoB = s.rangeAbove == "auto", s.rangeBelow == "auto"
  local above = autoA and (self:Banking() and 12 or 4) or s.rangeAbove
  local below = autoB and 7 or s.rangeBelow
  return above, below, autoA, autoB
end

QB.CONTINENTS = { [0] = "Eastern Kingdoms", [1] = "Kalimdor" }

-- is this category (and, for class and other quests, the turn-in NPC's continent) skipped?
function QB:Skipped(catIdx, cont)
  local s = self:Settings()
  local c = catIdx and D.CAT[catIdx]
  if c then
    if s.skipCat[c.key] then return true end
    -- a place knows its continent; a dungeon that doesn't (a battleground, a new one) is never split
    -- quest by quest over its turn-in NPCs
    if c.cont ~= nil then cont = c.cont elseif c.dungeon then return false end
  end
  return cont ~= nil and cont >= 0 and s.skipCont[cont] == true
end

function QB:SkipsQuest(q)
  local r = D.Q[q.id]
  local turn = D.NPC[q.turnIdx]
  return r ~= nil and self:Skipped(r[8], turn and turn[5])
end

-- one string for everything skipped, so cached suggestion lists know when to refresh
function QB:SkipSignature()
  local s, parts = self:Settings(), {}
  for k in pairs(s.skipCat) do parts[#parts + 1] = k end
  for k in pairs(s.skipCont) do parts[#parts + 1] = "c" .. k end
  table.sort(parts)
  return table.concat(parts, ",")
end

-- the skipped places by name, continents first
function QB:SkipList()
  local s, names = self:Settings(), {}
  for k = 0, 1 do if s.skipCont[k] then names[#names + 1] = QB.CONTINENTS[k] end end
  local zones = {}
  for _, c in ipairs(D.CAT) do if s.skipCat[c.key] then zones[#zones + 1] = c.name end end
  table.sort(zones)
  for _, n in ipairs(zones) do names[#names + 1] = n end
  return names
end

function QB:SetSkip(key, on)
  local s = self:Settings()
  if type(key) == "number" then s.skipCont[key] = on and true or nil else s.skipCat[key] = on and true or nil end
  if QB.UI then QB.UI:Refresh() end
end

-- a continent, zone or dungeon by name (or part of one): flips it, and says what and which way
function QB:ToggleSkip(want)
  want = (want or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if want == "" then return nil end
  local s = self:Settings()
  for k = 0, 1 do
    local n = QB.CONTINENTS[k]:lower()
    if n == want or (#want >= 4 and n:find(want, 1, true) == 1) then
      self:SetSkip(k, not s.skipCont[k])
      return QB.CONTINENTS[k], s.skipCont[k] == true
    end
  end
  local best
  for _, c in ipairs(D.CAT) do
    local n = c.name:lower()
    if n == want then best = c break end
    if n:find(want, 1, true) and (not best or #c.name < #best.name) then best = c end
  end
  if not best then return nil end
  self:SetSkip(best.key, not s.skipCat[best.key])
  return best.name, s.skipCat[best.key] == true
end

----------------------------------------------------------------------------
-- the join prompt for escort quests. When a party member accepts an escort, the game asks the others
-- ("X has started a quest", QUEST_ACCEPT_CONFIRM). Which prompt it shows is decided by the UI's MAX_QUESTS
-- constant: at or above it, "your quest log is full" with Yes greyed out, and Yes stays grey by the same
-- comparison. Forever's UI still carries 25 there (Blizzard_FrameXMLBase/Constants.lua on the wow-ui-source
-- forever branch; Blizzard_Game/Mainline/EventImplementation.lua reads it) while the log holds 40, so anyone
-- with 25 or more quests can't join. Both reads happen the moment the prompt opens, so the real size in
-- that constant is enough. The server still has the last word.
----------------------------------------------------------------------------
function QB:FixEscortPrompt()
  if not self:Settings().escort or type(MAX_QUESTS) ~= "number" then return false end
  local api = C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and tonumber(C_QuestLog.GetMaxNumQuestsCanAccept()) or 0
  local real = math.max(QB.LOG_SLOTS, api)
  if MAX_QUESTS < real then
    QB.escortWas = QB.escortWas or MAX_QUESTS
    MAX_QUESTS = real
    if type(MAX_QUESTLOG_QUESTS) == "number" and MAX_QUESTLOG_QUESTS < real then MAX_QUESTLOG_QUESTS = real end
    -- a prompt already open with its Yes greyed out re-reads the constant when told
    if UpdateQuestAcceptLogFullDialog then pcall(UpdateQuestAcceptLogFullDialog) end
  end
  return true
end

function QB:UnfixEscortPrompt()
  if QB.escortWas and type(MAX_QUESTS) == "number" then
    MAX_QUESTS = QB.escortWas
    if type(MAX_QUESTLOG_QUESTS) == "number" then MAX_QUESTLOG_QUESTS = QB.escortWas end
    if UpdateQuestAcceptLogFullDialog then pcall(UpdateQuestAcceptLogFullDialog) end
  end
end

local toldEscort
function QB:EscortPrompt(who, title)
  if not self:FixEscortPrompt() or toldEscort or not QB.escortWas then return end
  if (self.state.logCount or 0) >= QB.escortWas then
    toldEscort = true
    self:Print(string.format("%s started %s. The game's prompt counts %d quests as a full log; the log holds %d, so QuestBank corrected it and you can say yes. /qb escort for the details.",
      who or "Someone", title or "a quest", QB.escortWas, MAX_QUESTS))
  end
end
function QB:OnTheDay() return self:Banking() and "on the day" or "at your level" end

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
  for id in pairs(p.add) do if API.IsDone(id) then p.add[id] = nil end end
  for id, title in pairs(p.seen) do
    if not s.log[id] then
      if not turnedIn[id] and not API.IsDone(id) then
        local q = Q.Get(id)
        local value = q and QB.Model.XpAt(q, s.level) or nil
        p.removed[id] = { title = title, at = time and time() or 0, value = value }
        if QB.loggedIn then
          QB:Print(string.format("%s left your log without a hand-in%s. The route no longer counts it.", title,
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

-- the game's own number for every quest you hold: the quest log shows each quest's XP at your level. Exact for
-- this level (q.logXp), and the full value is learned from it when the quest is not grey (Live, source "log").
function QB.ReadLogXp(s)
  if not GetQuestLogRewardXP then return end
  local vals, seen, dup, valued = {}, {}, 0, 0
  for _, e in ipairs(s.logOrder) do
    local ok, xp = pcall(GetQuestLogRewardXP, e.id)
    if ok and type(xp) == "number" and not (issecretvalue and issecretvalue(xp)) and xp > 0 then
      vals[e.id] = xp
      valued = valued + 1
      if seen[xp] then dup = dup + 1 end
      seen[xp] = true
    end
  end
  -- a client answering with the selected quest's number for every id repeats one value: trust none of it then
  if valued >= 3 and dup + 1 >= valued then vals = {} end
  for _, e in ipairs(s.logOrder) do
    local q = Q.Get(e.id)
    local xp = vals[e.id]
    if q then q.logXp = xp end
    if xp then
      e.xp = xp
      Live.Record(e.id, xp, s.level, "log")
    end
  end
  for id, q in pairs(cache) do if q and q.logXp and not s.log[id] then q.logXp = nil end end
end

function QB:ReadState()
  local s = self.state
  s.level = UnitLevel("player") or 1
  s.xp = UnitXP("player") or 0
  s.xpMax = UnitXPMax("player") or 1
  s.log, s.logOrder = API.LogQuests()
  QB.ReadLogXp(s)
  if QB.Run and QB.Run.Check then QB.Run.Check(s.level) end
  s.logCount = #s.logOrder
  s.mapID = API.MapID()
  s.bagStarts = API.BagQuestStarts()
  local _, class = UnitClass("player")
  s.class = class
  s.name = UnitName("player")
  QB.faction = API.Faction()
  local choice, p = QB:LockChoice()
  if choice == "on" and p.lockAt and s.level > p.lockAt then p.lock, p.lockAt = nil, nil end
  local held, nextCap = QB:Lock()
  QuestBankDB.held = QuestBankDB.held or {}
  local key = QB:CharKey()
  local run = QB.Run and QB.Run.Get()
  if held then
    QuestBankDB.held[key] = { level = held, next = nextCap }
  elseif QuestBankDB.held[key] and not run and (s.level > QuestBankDB.held[key].level or choice == "off") then
    QuestBankDB.held[key] = nil -- the bank is behind you
  end
  local was = QB:Held()
  local cap
  if nextCap then
    cap = nextCap
  elseif was and (run or s.level <= was.level) then
    -- the rush: the new cap if the game says, else the one you expected
    local game = API.GameCap()
    cap = (game > was.level and game < QB.MAXLEVEL) and game or was.next
  else
    cap = API.GameCap()
  end
  QB.CAP = math.max(cap or QB.MAXLEVEL, s.level)
  QB.mode = QB:Mode()
  trackRemovals(s)
  -- a quest that just turned complete: say so once. A quest that just arrived: party chat, if asked
  QB.wasComplete = QB.wasComplete or {}
  local firstRead = QB.wasInLog == nil
  QB.wasInLog = QB.wasInLog or {}
  local inLog = {}
  for _, e in ipairs(s.logOrder) do
    inLog[e.id] = true
    if not firstRead and not QB.wasInLog[e.id] and QB.loggedIn then QB:Announce("accept", e.title) end
    local before = QB.wasComplete[e.id]
    if e.complete and before == false and QB.loggedIn then
      local q = Q.Get(e.id)
      local value = q and QB.Model.XpAt(q, s.level)
      QB:Print(string.format("%s is complete%s%s.", e.title, QB:Banking() and ": banked" or ", hand it in",
        value and value > 0 and (", worth about " .. QB.Comma(value) .. " XP " .. QB:OnTheDay()) or ""))
      QB:Announce("complete", e.title)
    end
    QB.wasComplete[e.id] = e.complete and true or false
  end
  QB.wasInLog = inLog
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
  local items = Bank.Items(q)
  if e then
    if e.complete then return { code = "banked", text = QB:Banking() and "Banked, ready to hand in" or "Ready to hand in" } end
    local text = progressText(e)
    if items then
      local fromBank = 0
      for _, it in ipairs(items) do
        if it.bags < it.need and it.bags + it.bank >= it.need then fromBank = fromBank + (it.need - it.bags) end
      end
      if fromBank > 0 then text = text .. string.format(". Take %d out of your bank", fromBank) end
    end
    return { code = "active", text = text }
  end
  if not q.excl then
    local x, how = Q.Behind(q.id)
    if x then
      return { code = "todo", text = "Probably behind you", behind = true, later = x, how = how }
    end
  end
  local bag = q.bag
  if bag and bag[3] == 1 then
    local n = API.ItemCount(bag[1])
    if n >= bag[2] then return { code = "banked", text = QB:Banking() and "Banked in your bags" or "In your bags, ready", bag = true } end
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
      if preDone(p) or heldOf(p) then from = k break end
    end
    local left = 0
    for k = from, #q.pre do if not preDone(q.pre[k]) then left = left + 1 end end
    for k = from, #q.pre do
      local p = q.pre[k]
      if not preDone(p) then
        local held = heldOf(p)
        local steps = left > 1 and string.format(" (%d steps)", left) or ""
        if held then return { code = "prereq", text = "Hand in " .. Q.Label(held) .. " first" .. steps, pre = p } end
        return { code = "prereq", text = "First: " .. Q.Label(p) .. steps, pre = p }
      end
    end
  end
  if fromItem then return { code = "item", text = "Starts from an item: " .. (bag[4] or "a drop") } end
  if items then
    local all, bank = true, 0
    for _, it in ipairs(items) do
      if it.bags + it.bank < it.need then all = false end
      bank = bank + math.max(0, math.min(it.bank, it.need - it.bags))
    end
    if all then
      return { code = "todo", text = "Not started, and you already have what it asks for" .. (bank > 0 and string.format(" (%d in your bank)", bank) or "") }
    end
  end
  return { code = "todo", text = "Not started" }
end

----------------------------------------------------------------------------
-- the plan: what you hold (minus what you cut) plus what you chose to fetch
----------------------------------------------------------------------------
function QB:IsCut(id) return self:Plan().cut[id] and true or false end

-- what a quest leads on to, for you: the XP of its follow-up steps (three on at most) at your level,
-- the ones you haven't done or taken. Questing, a quest that opens a chain is worth more than it pays.
function QB:ChainLead(id)
  local q = Q.Get(id)
  if not (q and q.nextSteps) then return 0 end
  local s, level = self.state, self.state.level or 1
  local seen, sum = { [id] = true }, 0
  -- of two steps that rule each other out, only the first met counts
  local function exclTaken(nq)
    if not nq.excl then return false end
    for _, o in ipairs(nq.excl) do if seen[o] then return true end end
    return false
  end
  local function walk(x, depth)
    if depth > 3 or not x.nextSteps then return end
    for _, nid in ipairs(x.nextSteps) do
      local nq = Q.Get(nid)
      if nq and not seen[nid] and stepOpen(nq, level, false, s) and not exclTaken(nq) then
        seen[nid] = true
        sum = sum + QB.Model.XpAt(nq, level)
        walk(nq, depth + 1)
      end
    end
  end
  walk(q, 1)
  return sum
end

-- the alternative of an either-or prerequisite that is yours: one you hold, else one for your faction,
-- class and race, else the first
function QB:PreStep(p)
  if type(p) ~= "table" then return Q.Get(p) end
  local s = self.state
  for _, id in ipairs(p) do if s.log[id] and Q.Get(id) then return Q.Get(id) end end
  for _, id in ipairs(p) do
    local q = Q.Get(id)
    if q and Q.ForMe(q) then return q end
  end
  return Q.Get(p[1])
end

-- the steps of a chain still ahead of this quest, in order: { q = the step (false if the catalog lacks
-- it), held = it is in your log, so what is left of it is the hand-in }
function QB:ChainSteps(q)
  if not (q and q.pre) then return nil end
  local s = self.state
  local from = 1
  for k = #q.pre, 1, -1 do
    local p = q.pre[k]
    if preDone(p) or heldOf(p) then from = k break end
  end
  local steps = {}
  for k = from, #q.pre do
    local p = q.pre[k]
    if not preDone(p) then
      local h = heldOf(p)
      if h and not Q.Get(h) then
        steps[#steps + 1] = { q = false, held = true } -- you hold a step the catalog lacks: nothing to aim at but its hand-in
      else
        local sq = self:PreStep(p)
        steps[#steps + 1] = { q = sq or false, held = (sq and s.log[sq.id]) and true or false }
      end
    end
  end
  return #steps > 0 and steps or nil
end

-- what a quest behind a chain costs you first: the steps left, the XP they pay at your level, and the
-- minutes of moving between their NPCs from where you stand, by the hand-in route's own travel model
function QB:ChainCost(q)
  local steps = self:ChainSteps(q)
  if not steps then return nil end
  local s = self.state
  local M, fac = QB.Model, self.faction or API.Faction()
  local mf = self:Mounted() and 0.625 or 1
  local wp = API.WorldPosition()
  local prev = wp and M.Place(fac, wp.c, wp.wx, wp.wy) or nil
  local minutes, known, xp = 0, true, 0
  local function hop(to)
    if not to then known = false return end
    if prev then minutes = minutes + M.Between(prev, to, fac, mf) end
    prev = to
  end
  for _, st in ipairs(steps) do
    local sq = st.q
    if sq then
      xp = xp + M.XpAt(sq, s.level or 1)
      if not st.held then hop(M.NpcPlace(sq.giveIdx, fac)) end
      hop(M.NpcPlace(sq.turnIdx, fac))
    else
      known = false
    end
  end
  hop(M.NpcPlace(q.giveIdx, fac))
  return { n = #steps, xp = xp, minutes = known and math.floor(minutes + 0.5) or nil, first = steps[1].q or nil }
end
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

-- quests kept as items in your bags, for your faction, class and race: worked out once
local bagQuests
function QB:BagQuests()
  if bagQuests then return bagQuests end
  local out = {}
  for id in pairs(D.BAGQ) do
    local q = Q.Get(id)
    if q and Q.ForMe(q) then out[#out + 1] = id end
  end
  table.sort(out)
  bagQuests = out
  return out
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
  for _, id in ipairs(QB:BagQuests()) do consider(id) end
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

-- how far along a quest in your log is, summed over its counted objectives: have, need
function QB:Progress(id)
  local e = self.state.log[id]
  if not e then return nil end
  local have, need = 0, 0
  for _, o in ipairs(e.objectives or {}) do
    if o.need and o.need > 0 then
      have, need = have + math.min(o.have or 0, o.need), need + o.need
    end
  end
  if need == 0 then return nil end
  return have, need
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
                mode = QB.mode == "quest" and "quest" or "rush",
                predicted = r and r.xp or 0, predictedT = r and r.t or 0, hearthUsed = false }
  if r then
    for _, leg in ipairs(r.legs) do
      for _, row in ipairs(leg.rows) do run.plan[row.q.id] = { t = leg.t, xp = row.xp, stop = leg.stop.name } end
    end
  end
  QuestBankDB.run = run
  QB:Print("Hand-in run started. Each quest is ticked off with the XP it paid; the route re-plans from where you stand.")
  Run.ArmHour()
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
  -- the bank is cashed in: questing from here, until the next lock
  if QuestBankDB.held and not QB:Lock() then QuestBankDB.held[QB:CharKey()] = nil end
  QB.mode = QB:Mode()
  QB:Print(string.format("Run ended: %d quests, %s XP in %s.", n, QB.Comma(got), QB.Clock((run.ended - run.started) / 60)))
  if n > 0 then Run.Offer("done", run) end
  QB:MarkDirty()
end

-- a hand-in run ends by itself when it has outlived the hour it was for: two hours have passed, or an hour and
-- a half with you three levels past where it started. (The owner's run from the level-20 cap was still
-- on at level 24, and everything spoke of banking.)
function Run.Check(level)
  local run = Run.Get()
  if not run or run.mode == "quest" then return end
  local mins = (time() - run.started) / 60
  if mins > 120 or (mins > 90 and (level or 0) >= (run.level or level or 0) + 3) then
    QB:Print(mins > 120 and "Your hand-in run ended by itself: two hours have passed. Questing from here."
      or "Your hand-in run ended by itself: the hour is over and you are three levels on. Questing from here.")
    Run.Stop()
  end
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
-- telling your party and guild: QuestBank offers a post, you read it and press Post (UI:PostDialog).
-- Offered at each level of a hand-in run, when its first hour is up, and when it ends.
----------------------------------------------------------------------------
local function levelNow()
  return QB.Model.Frac(UnitLevel("player") or QB.state.level, UnitXP("player") or 0)
end

local function quests(n) return n == 1 and "1 quest" or (n .. " quests") end
local function minutes(m) return math.max(1, math.floor(m + 0.5)) end

-- the message, and a line on why it's offered. kind: level (arg: the new level), hour, done (arg: the ended run), status
function Run.PostText(kind, arg)
  local run = kind == "done" and arg or Run.Get()
  if run and kind == "level" then
    local got, n = Run.Totals()
    return string.format("Level %d, %d min into my hand-in run: %s handed in, +%s XP. (QuestBank)", arg,
      minutes(Run.Elapsed()), quests(n), QB.Comma(got)), "You reached level " .. arg .. "."
  elseif run and kind == "hour" and run.hour then
    return string.format("First hour of my hand-in run: level %.1f, %s handed in, +%s XP. (QuestBank)",
      run.hour.level, quests(run.hour.n), QB.Comma(run.hour.xp)), "The first hour of your hand-in run is up."
  elseif run and kind == "done" then
    return string.format("Hand-in run done: level %.1f to %.1f in %d min, %s, +%s XP. (QuestBank)",
      QB.Model.Frac(run.level or 1, run.xp or 0), levelNow(), minutes((run.ended - run.started) / 60),
      quests(run.count or 0), QB.Comma(run.got or 0)), "Your hand-in run is over."
  elseif run then
    local got, n = Run.Totals()
    return string.format("%d min into my hand-in run: level %.1f, %s handed in, +%s XP. (QuestBank)",
      minutes(Run.Elapsed()), levelNow(), quests(n), QB.Comma(got)), "Your hand-in run so far."
  end
  local now, plan = QB.routeNow, QB.routePlan
  local banked = (now and not now.empty) and now.level or levelNow()
  local full = (plan and not plan.empty) and plan.level or banked
  local hour = (plan and not plan.empty) and plan.at60 or banked
  if not QB:Banking() then
    return string.format("Level %.1f: the quests ready in my log take me to %.1f, my plan to %.1f. (QuestBank)",
      levelNow(), banked, full), "Your quest log and your plan."
  end
  if QB.mode == "rush" then
    return string.format("The cap is up: my bank takes me to level %.1f, my full plan to %.1f (%.1f inside the first hour). (QuestBank)",
      banked, full, hour), "Your bank and your plan."
  end
  return string.format("My banked quests take me to level %.1f when the cap goes up, my full plan to %.1f (%.1f inside the first hour). (QuestBank)",
    banked, full, hour), "Your bank and your plan."
end

-- only an offer: nothing is posted until you press Post
function Run.Offer(kind, arg)
  if not (QB:Settings().post.auto and QB.UI and QB.Sync) then return end
  local ch = QB.Sync.PostChannels()
  if not (ch.party or ch.guild) then return end
  local msg, why = Run.PostText(kind, arg)
  QB.UI:PostDialog(msg, why, true)
end

-- the first hour: noted once, when it's up (again after a /reload, if it hasn't passed)
function Run.ArmHour()
  local run = Run.Get()
  if not run or run.hour then return end
  local left = 3600 - (time() - run.started)
  if left <= 0 then return end
  local started = run.started
  C_Timer.After(left, QB.Safe(function()
    local r = Run.Get()
    if not r or r.started ~= started or r.hour then return end
    local got, n = Run.Totals()
    r.hour = { level = levelNow(), n = n, xp = got }
    Run.Offer("hour")
  end, "run: the first hour"))
end

----------------------------------------------------------------------------
-- recompute: two routes, cached until something they depend on changes, planned in the background
----------------------------------------------------------------------------
local function signature(list, opts)
  -- XP counts in fiftieths of a level (every kill would re-plan otherwise); XP numbers the game
  -- reported count by how many there have been
  local T = QB.Data.TO_NEXT
  local xpq = math.floor((opts.xp or 0) * 50 / (T[opts.level] or 1))
  local parts = { opts.level, xpq, tostring(opts.mounted), opts.goal, opts.fac,
                  opts.startHub or "-", tostring(opts.noHearth), opts.cap or 0, opts.mode or "", QB.liveVer or 0, QB.doneVer or 0 }
  for _, e in ipairs(list) do parts[#parts + 1] = e.q.id .. (e.st and e.st.code or "") end
  return table.concat(parts, ":")
end

function QB:Recompute(sync)
  self:ReadState()
  local set = self:Settings()
  local mode = QB.mode
  local opts = {
    level = self.state.level, xp = self.state.xp, mounted = (self:Mounted()),
    goal = mode == "quest" and "route" or set.goal, fac = QB.faction, cap = QB.CAP, mode = mode,
  }
  local nowOpts = {}
  for k, v in pairs(opts) do nowOpts[k] = v end
  -- mid-run, or questing: the route from where you stand. (At a lock you log out where the route starts.)
  local run = Run.Get()
  if run or mode == "quest" then
    local wp = API.WorldPosition()
    if wp then
      local place = QB.Model.Place(QB.faction, wp.c, wp.wx, wp.wy)
      if place.hub > 0 then nowOpts.start, nowOpts.startHub = wp, place.hub end
    end
    nowOpts.noHearth = (run and run.hearthUsed) or not API.HearthReady()
    nowOpts.goal = "route"
    if mode == "quest" then opts.start, opts.startHub, opts.noHearth = nowOpts.start, nowOpts.startHub, nowOpts.noHearth end
  end
  local now, plan = self:RouteEntries("now"), self:RouteEntries("plan")
  local sigNow, sigPlan = signature(now, nowOpts), signature(plan, opts)
  local needNow = sigNow ~= self.sigNow
  local needPlan = sigPlan ~= self.sigPlan
  if not (needNow or needPlan) then return self.routeNow, self.routePlan end
  local want = sigNow .. "|" .. sigPlan
  if self.pending == want and not sync then return self.routeNow, self.routePlan end
  local function work()
    -- each starts from the last route, so a change can only move it to a better one
    if needNow then self.routeNow, self.sigNow = QB.Model.Plan(now, nowOpts, self.routeNow), sigNow end
    if needPlan then self.routePlan, self.sigPlan = QB.Model.Plan(plan, opts, self.routePlan), sigPlan end
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

-- XP a quest is worth on the day: from a route, else at your level
function QB:Value(id)
  for _, r in ipairs({ self.routePlan, self.routeNow }) do
    if r and r.byQuest and r.byQuest[id] then return r.byQuest[id], true end
  end
  local q = Q.Get(id)
  if not q then return nil end
  return QB.Model.XpAt(q, self.state.level), false
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
  local prev, stale = QuestBankDB.chars[self:CharKey()], nil
  if #done == 0 and prev and type(prev.completed) == "table" and #prev.completed > 0 then done, stale = prev.completed, true end
  QuestBankDB.chars[self:CharKey()] = {
    saved = date("%Y-%m-%d %H:%M"), reason = reason, version = QB.version,
    level = s.level, xp = s.xp, xpMax = s.xpMax, class = s.class, race = race,
    faction = UnitFactionGroup("player"), completed = done, completedStale = stale, log = log, bags = bagItems(),
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
  if QB.Arrow and QB.Arrow.Invalidate then QB.Arrow.Invalidate() end
  self.dirty = true
  if pending then return end
  pending = true
  C_Timer.After(0.3, QB.Safe(function()
    pending = false
    QB:Changed()
  end, "refresh"))
end

function QB:Changed()
  QB.Try("plan", QB.Recompute, QB)
  -- the window shows what was just worked out, without working it out again
  QB.fresh = true
  if QB.UI and QB.UI.frame and QB.UI.frame:IsShown() then QB.Try("window", QB.UI.Refresh, QB.UI) end
  QB.fresh = false
  if QB.Pins then QB.Try("map pins", QB.Pins.Update, QB.Pins) end
  if QB.Sync then QB.Try("party sync", QB.Sync.Changed, QB.Sync) end
end

local function onTurnIn(questID, xpReward)
  QB.NoteXPSeen("turnin", questID, xpReward)
  if issecretvalue and issecretvalue(questID) then return end
  local hidden = (issecretvalue and issecretvalue(xpReward)) and true or false
  if hidden then xpReward = nil end -- hidden from addons: "not told", never 0 (see below)
  turnedIn[questID] = true
  API.MarkDone(questID)
  local q = Q.Get(questID)
  Live.Record(questID, xpReward, QB.state.level or UnitLevel("player"), "turnin")
  local predicted = QB.routeNow and QB.routeNow.byQuest and QB.routeNow.byQuest[questID]
  table.insert(QuestBankDB.turnins, {
    id = questID, xp = xpReward, predicted = predicted, level = UnitLevel("player"), at = date("%Y-%m-%d %H:%M:%S"),
    mult = q and q.mult, base = q and q.base, hidden = hidden or nil,
  })
  local level = UnitLevel("player") or 0
  -- the lock, learned: a quest worth XP at this level paid none (the cap holds for every character on
  -- the realm, so it counts account-wide), until a hand-in at that level pays again
  local expected = q and QB.Model.XpAt(q, level) or 0
  if hidden then
    -- the game hid the number: nothing to learn about locks, no run to start; a run under way counts the plan's figure
    Run.Record(questID, predicted or 0, q and q.name)
    if q then
      QB:Print(string.format("%s handed in. The game hides its XP from addons%s.", q.name,
        (predicted and predicted > 0) and string.format("; the plan counted %s", QB.Comma(predicted)) or ""))
    end
    return
  end
  -- (at a cap the game throws XP away, so the bar sits at 0: a stray quest that pays nothing isn't a lock)
  local locks = type(QuestBankDB.lock) == "table" and not QuestBankDB.lock.level and QuestBankDB.lock or {}
  QuestBankDB.lock = locks
  local realm = QB.RealmKey()
  if (xpReward or 0) == 0 and expected >= 100 * QB.Scale(level) and level < QB.MAXLEVEL and (UnitXP("player") or 0) == 0
    and not (IsXPUserDisabled and IsXPUserDisabled()) then
    locks[realm] = { level = level, at = time() }
  elseif (xpReward or 0) > 0 and locks[realm] and level >= locks[realm].level then
    locks[realm] = nil
  end
  -- the first banked quest that pays after a lock starts the hand-in run by itself
  if not Run.Get() and predicted and QB.mode ~= "quest" and (xpReward or 0) > 0 then Run.Start() end
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

frame:SetScript("OnEvent", QB.Safe(function(_, event, a1, a2, a3)
  if event == "ADDON_LOADED" then
    if a1 == ADDON then QB:Settings(); Live.Apply() end
    return
  elseif event == "QUEST_ACCEPT_CONFIRM" then
    if not (QB.Auto and QB.Auto.WillJoin()) then QB:EscortPrompt(a1, a2) else QB:FixEscortPrompt() end
    if QB.Auto then QB.Auto.OnEvent(event, a1, a2) end
    return
  elseif event == "QUEST_PROGRESS" or event == "QUEST_GREETING" or event == "GOSSIP_SHOW" then
    if QB.Auto then QB.Auto.OnEvent(event, a1, a2) end
    return
  elseif event == "QUEST_DETAIL" or event == "QUEST_COMPLETE" then
    local before = QB.liveVer
    windowXP("npc", event)
    if QB.Auto then QB.Auto.OnEvent(event, a1, a2) end -- after the window's XP is on record
    if QB.liveVer == before then return end -- nothing new: the plan stands
  elseif event == "PLAYER_LOGIN" then
    local nr = GetNormalizedRealmName and GetNormalizedRealmName()
    if nr then QB.charKey = (UnitName("player") or "?") .. "-" .. nr; QB:MergeCharKeys() end
    QB:ReadState()
    if QB.Minimap then QB.Minimap:Create() end
    if QB.Pins then QB.Pins:Init() end
    if QB.Sync then QB.Sync:Init() end
    if QB.Discover then QB.Discover:Init() end
    if QB.Arrow then QB.Arrow:Init() end
    QB:FixEscortPrompt()
    Run.ArmHour()
    C_Timer.After(8, QB.Safe(function() QB:Snapshot("login") end, "login snapshot"))
    C_Timer.After(4, QB.Safe(function() QB:Changed() end, "login"))
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
    elseif doneCount == 0 then
      API.RefreshDone() -- the game's completed list arrives a little after login; look again on every update until it does
    end
  elseif event == "QUEST_TURNED_IN" then
    onTurnIn(a1, a2)
  elseif event == "PLAYER_LEVEL_UP" then
    -- a moment later, once the XP bar has caught up
    local level = a1
    if Run.Get() and level then C_Timer.After(1, QB.Safe(function() Run.Offer("level", level) end, "run: level up")) end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    -- only the hearthstone (and astral recall) matter: the route can't use it again this run
    if a1 ~= "player" or not (a3 == 8690 or a3 == 556) then return end
    if Run.Get() then Run.Get().hearthUsed = true end
  elseif event == "UNIT_AURA" then
    -- only the sleeping bag's Well Rested changes a plan
    if a1 ~= "player" then return end
    local rested = API.HasWellRested() and true or false
    if rested == QB.lastRested then return end
    QB.lastRested = rested
  elseif event == "PLAYER_XP_UPDATE" then
    -- kills move the bar all the time: re-plan when it has moved a fiftieth of a level
    local T = QB.Data.TO_NEXT
    local lvl = UnitLevel("player") or 1
    local step = math.floor((UnitXP("player") or 0) * 50 / (T[lvl] or 1))
    if step == QB.xpStep then return end
    QB.xpStep = step
  elseif event == "BANKFRAME_OPENED" then
    QB.bankOpen = true
    Bank.Scan()
  elseif event == "BANKFRAME_CLOSED" then
    Bank.Scan()
    QB.bankOpen = false
  elseif event == "PLAYERBANKSLOTS_CHANGED" or (event == "BAG_UPDATE_DELAYED" and QB.bankOpen) then
    -- moving a stack fires this for every slot: scan once, a moment later
    if QB.bankScanSoon then return end
    QB.bankScanSoon = true
    C_Timer.After(0.5, QB.Safe(function()
      QB.bankScanSoon = false
      if QB.bankOpen then Bank.Scan() end
      QB:MarkDirty()
    end, "bank scan"))
    return
  end
  QB:MarkDirty()
end, "game event"))

for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_ACCEPT_CONFIRM",
  "QUEST_ACCEPTED", "QUEST_REMOVED", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE",
  "ZONE_CHANGED_NEW_AREA", "UNIT_AURA", "HEARTHSTONE_BOUND", "UNIT_SPELLCAST_SUCCEEDED", "QUEST_DETAIL", "QUEST_COMPLETE",
  "QUEST_PROGRESS", "QUEST_GREETING", "GOSSIP_SHOW",
  "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED" }) do
  if (e == "UNIT_AURA" or e == "UNIT_SPELLCAST_SUCCEEDED") and frame.RegisterUnitEvent then
    pcall(frame.RegisterUnitEvent, frame, e, "player") -- not every unit in sight
  else
    pcall(frame.RegisterEvent, frame, e)
  end
end

----------------------------------------------------------------------------
-- slash
----------------------------------------------------------------------------
SLASH_QUESTBANK1 = "/questbank"
SLASH_QUESTBANK2 = "/qb"
local slash
SlashCmdList.QUESTBANK = function(msg) QB.Try("/qb " .. tostring(msg or ""), slash, msg) end
slash = function(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "export" then
    local done, inLog = QB:Snapshot("manual")
    QB:Print(done .. " completed quests and " .. inLog .. " in your log saved. Type /reload to write the file.")
  elseif cmd == "reset" then
    QB:Settings().pos, QB:Settings().post.pos = nil, nil
    if QB.UI.frame then QB.UI.frame:ClearAllPoints(); QB.UI.frame:SetPoint("CENTER") end
    if QB.UI.postFrame then QB.UI.postFrame:ClearAllPoints(); QB.UI.postFrame:SetPoint("TOP", 0, -120) end
  elseif cmd == "minimap" then
    local m = QB:Settings().minimap
    m.hide = not m.hide
    if QB.Minimap then QB.Minimap:Update() end
  elseif cmd == "route" then
    QB.UI:Open(3)
  elseif cmd == "prep" or cmd == "plan" or cmd == "available" then
    QB.UI:Open(2)
  elseif cmd == "party" then
    QB.UI:Open(4)
  elseif cmd == "start" then
    QB:Recompute(true); Run.Start()
  elseif cmd == "stop" then
    Run.Stop()
  elseif cmd == "post" then
    QB.UI:PostDialog(Run.PostText("status"))
  elseif cmd == "arrow" then
    local want = rest:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if QB.Arrow.MODES[want] then
      QB.Arrow:SetMode(want)
      if not QB:Settings().arrow then QB.Arrow:Set(true) end
      QB:Print("The arrow points at " .. QB.Arrow.MODES[want] .. ".")
    elseif want == "on" or want == "off" then
      QB.Arrow:Set(want == "on")
      QB:Print(want == "on" and ("Direction arrow on: it points at " .. QB.Arrow.MODES[QB.Arrow.Mode()] .. ".") or "Direction arrow off.")
    else
      QB.Arrow:Set(not QB:Settings().arrow)
      QB:Print(QB:Settings().arrow and ("Direction arrow on: it points at " .. QB.Arrow.MODES[QB.Arrow.Mode()] .. ". Right-click it to choose: the route, the nearest hand-in or pick-up, or where you last clicked; /qb arrow route, handin, pickup or pin does the same. Drag it where you like.") or "Direction arrow off.")
    end
  elseif cmd == "discoveries" then
    local nq, nn, nc = QB.Discover.Count()
    local function n(k, one, many) return k == 1 and ("1 " .. one) or (k .. " " .. many) end
    QB:Print(string.format("Noted in game so far: %s, %s, %s. They stay in your saved file, QuestBank.lua. Upload it at foreverrank.com/questbank/ (or let ForeverProbe, optional, carry it) and it goes into the next release for everyone.",
      n(nq, "quest", "quests"), n(nn, "quest NPC", "quest NPCs"), n(nc, "chain step", "chain steps")))
  elseif cmd == "update" or cmd == "version" then
    QB:Print("You run QuestBank " .. QB.version .. (QB.newest and (". Newest seen: " .. QB.newest.version .. " (" .. (QB.newest.who or "?") .. ").") or "."))
    QB.UI:CopyLink("QuestBank download page", QB.DOWNLOAD)
  elseif cmd == "settings" or cmd == "options" then
    QB.UI:Open(5)
  elseif cmd == "sync" and QB.Sync then
    if rest ~= "" then QB.Sync:Whisper(rest) else QB.Sync:Broadcast(true) end
  elseif cmd == "pins" and QB.Pins then
    QB.Pins:Toggle()
  elseif cmd == "next" and QB.Pins then
    QB.Pins:PinNext(true)
  elseif cmd == "errors" then
    if rest == "clear" then
      QuestBankDB.errors = {}
      QB:Print("Error list cleared.")
    elseif QB.UI then
      QB.UI:ShowErrors()
    end
  elseif cmd == "escort" then
    local s = QB:Settings()
    local want = rest:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if want == "off" then
      s.escort = false
      QB:UnfixEscortPrompt()
    elseif want == "on" then
      s.escort = true
      QB:FixEscortPrompt()
    end
    local was = QB.escortWas or (type(MAX_QUESTS) == "number" and MAX_QUESTS) or 25
    if s.escort then
      QB:Print(string.format("The join prompt for escort quests works with %d or more quests in your log: the game's prompt counts %d as a full log, the log holds %d, QuestBank corrects that when you log in. /qb escort off leaves the game's number alone.",
        was, was, type(MAX_QUESTS) == "number" and MAX_QUESTS or QB.LOG_SLOTS))
    else
      QB:Print(string.format("The escort prompt fix is off: with %d or more quests in your log the game's prompt won't let you join an escort a party member starts. /qb escort on turns it back on.", was))
    end
  elseif cmd == "skip" then
    local want = rest:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if want == "" then
      local names = QB:SkipList()
      QB:Print(#names > 0 and ("Skipping " .. table.concat(names, ", ") .. ": nothing there is suggested. /qb skip and a name puts one back; /qb skip none clears the list.")
        or "Nothing skipped. Type /qb skip and a zone, dungeon or continent, like /qb skip Kalimdor or /qb skip Wailing Caverns, and QuestBank stops suggesting quests there. Settings has the same, and each Plan card has a Skip button.")
    elseif want == "none" or want == "clear" then
      local s = QB:Settings()
      s.skipCat, s.skipCont = {}, {}
      if QB.UI then QB.UI:Refresh() end
      QB:Print("Nothing is skipped any more.")
    else
      local label, on = QB:ToggleSkip(want)
      if not label then QB:Print(string.format("No zone, dungeon or continent called \"%s\". /qb skip Kalimdor, /qb skip Eastern Kingdoms, or a zone or dungeon name.", rest))
      elseif on then QB:Print(label .. " is skipped: nothing there is suggested. /qb skip " .. label .. " brings it back.")
      else QB:Print(label .. " is back in the suggestions.") end
    end
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
