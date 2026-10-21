-- SPDX-License-Identifier: GPL-3.0-or-later
-- The Guide (6.0): what to do next, as a list of steps, from the one target (Target.lua), the planned route
-- (Model.lua) and your quest log. No frames here: StepFrame.lua draws the list, and Cute's leveling module may read it.
--   steps     accept A from X; kill/collect/use for A (the objective spots of the route's quests, clustered within
--             CLUSTER yards, the nearest first); hand in A at X; travel steps the arrow's way gives (Travel.lua);
--             Train at X; Kill around X until level N; Run to your corpse; Choose a reward
--   first     the target of 5.4.4: the route's first stop, its kept objective spot or a hand-in in reach, so the arrow,
--             the minimap, the Map page and the step frame agree, and the first step changes only on a real event
--   done      a step completes when the game says so: the quest accepted, every objective of its spots done or the
--             quest complete, the quest handed in, the flight landed, the level reached
--   skipped   "Not now" for an hour (QuestBankDB.chars[key].guide.later), "Drop" for good (QB:SetSkipped)
--   reward    a hand-in with a choice: Auto.lua hands it here (G.HoldReward), the step says QuestBank's pick, the
--             frame marks it over the game's button; nothing is chosen for you
--   party     the fill weighs what the party holds (G.Rank); each member's first step comes by Sync's 1G line
--             (G.MemberSteps) for the frame
--   time      "about 14 min to level 6" (G.TimeToLevel): the plan's XP a minute, then the measured XP an hour
--   train     at your level's new spells, the trainer of your class nearest a hand-in stop (D.TRAINER, or learned at
--             its window into QuestBankDB.disc.trainer); none in reach: a reminder line, no step
-- Replan runs after each re-plan (Core.lua, QB:Changed) and on the Guide's own events; it reuses its tables, so a
-- re-plan makes a few kilobytes and a tick none.
local _, QB = ...
if QB.dormant then return end
local G = { steps = {}, ver = 0, later = nil }
QB.Guide = G

local CLUSTER = 150        -- yards: objective spots this close are one step
local LATER = 3600         -- seconds "Not now" holds
local AUTO_MAX = 8         -- auto picks at once (G.Fill)
G.CLUSTER, G.LATER, G.AUTO_MAX = CLUSTER, LATER, AUTO_MAX
G.GIVER_MERGE, G.GIVER_MAX = 30, 40 -- the minimap's ! (Minimap.lua): givers this close are one pin; at most this many

local plain = QB.Plain
local sqrt, huge = math.sqrt, math.huge
local pool, used = {}, 0   -- step tables reused from one Replan to the next
local wbuf, meBuf = {}, {}

local function step(kind)
  used = used + 1
  local s = pool[used]
  if not s then s = {}; pool[used] = s end
  for k in pairs(s) do s[k] = nil end
  s.kind = kind
  return s
end

local function npcName(idx)
  local n = idx and QB.Data.NPC[idx]
  return n and n[1] or "?"
end
local function questName(id)
  local q = QB.Quest.Get(id)
  return q and q.name or plain(QB.state.log[id] and QB.state.log[id].title) or ("Quest " .. tostring(id))
end

-- "Kobold Vermin slain: 3/8" -> "Kobold Vermin", 3, 8; "Investigate Echo Ridge: 0/1" -> "Investigate Echo Ridge", 0, 1
local function parseLine(text)
  text = plain(text)
  if type(text) ~= "string" then return nil end
  local name, have, need = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)")
  if not name then return text, nil, nil end
  name = name:gsub(" slain$", ""):gsub(" killed$", "")
  return name, tonumber(have), tonumber(need)
end
G.ParseLine = parseLine

-- the verb for a spot kind (Data.lua's D.SPOT kinds)
local VERB = { k = "Kill", c = "Collect", u = "Use", b = "Buy", e = "Go to", f = "Gather", s = "Find", d = "Do" }

-- the words of a step, made when asked (the frame asks each refresh; no string is kept on the step)
function G.Text(s)
  if not s then return "" end
  local k = s.kind
  if k == "accept" then return "Accept " .. questName(s.qid) .. " from " .. npcName(s.npc)
  elseif k == "handin" then
    if s.near then return s.n and s.n > 1 and string.format("Hand in %d quests here", s.n) or ("Hand in " .. questName(s.qid) .. " here") end
    return s.n and s.n > 1 and string.format("Hand in %d quests at %s", s.n, npcName(s.npc)) or ("Hand in " .. questName(s.qid))
  elseif k == "objective" then
    -- a quest with no objective spot in the world (a dungeon's: its objectives are inside): "Do <quest> in <dungeon>",
    -- or, with the way in not known, "Do <quest> (<dungeon>: entrance not known yet)"; no dungeon: "Do <quest>"
    if s.obj == "d" then
      local t = "Do " .. questName(s.qid)
      if s.dungeon then t = t .. (s.noEntrance and (" (" .. s.dungeon .. ": entrance not known yet)") or (" in " .. s.dungeon)) end
      return t
    end
    local e = QB.state.log[s.qid]
    local o = e and e.objectives and e.objectives[s.slot or 1]
    local name, have, need = parseLine(o and o.text)
    local verb = VERB[s.obj] or "Do"
    local what = name or questName(s.qid)
    local t = (have and need) and string.format("%s %s %d/%d", verb, what, have, need) or (verb .. " " .. what)
    if s.n and s.n > 1 then t = t .. string.format(", and %d more here", s.n - 1) end
    return t
  elseif k == "travel" then return s.text or "Travel"
  elseif k == "train" then return "Train at " .. (s.name or "your class trainer")
  elseif k == "grind" then return s.text or "Kill around here"
  elseif k == "corpse" then return "Run to your corpse"
  elseif k == "reward" then return "Choose a reward: " .. (s.name or "the marked one") .. " is " .. (QB.NAME or "QuestBank") .. "'s pick"
  end
  return s.text or ""
end

-- the shorter words, when the frame's row cannot hold the whole line: "Accept X" without the giver (the row's
-- tooltip names them); nil for the other kinds, which are cut with "..." as before
function G.Short(s)
  if s and s.kind == "accept" then return "Accept " .. questName(s.qid) end
  return nil
end

-- (the launch round) the step frame's words in parts: the owner's frame read "Hand in In Nightmares" / "Hand in The
-- Absent Minded Prospector" / "Hand in Ziz Fizziks", one stop or three trips nobody could tell, and five quests share
-- the Prospector's name. Now a step carries its leg of the route (s.stop, s.mins, s.way, s.leg: Replan) and the frame
-- shows, beside the kind's game icon, the name (G.Title), who and where (G.Where, "Mathrengyl Bearwalker - Darnassus";
-- G.Place, the stop alone) and the minutes to that stop (G.Mins)
-- the name: a quest's for a pick-up or a hand-in (the icon says which), "3 quests to hand in" for several, else the
-- step's own words
function G.Title(s)
  if not s then return "" end
  local k = s.kind
  if k == "accept" then return questName(s.qid) end
  if k == "handin" then return (s.n and s.n > 1) and string.format("%d quests to hand in", s.n) or questName(s.qid) end
  return G.Text(s)
end
-- where: the leg's stop (the town, or a place out in a zone), else the zone the step's spot is in
function G.Place(s)
  if not s then return nil end
  return s.stop or (s.m and QB.Data.MAPNAME and QB.Data.MAPNAME[s.m]) or nil
end
-- who and where: the NPC of a pick-up or a hand-in, the quest of an objective spot, then the place; the place alone
-- where nobody is to be found (a dungeon's Do step, travel, training)
function G.Where(s)
  if not s then return nil end
  local place = G.Place(s)
  local who
  if (s.kind == "accept" or s.kind == "handin") and s.npc then who = npcName(s.npc)
  elseif s.kind == "objective" and s.obj ~= "d" and s.qid then who = questName(s.qid) end
  if who and place and who ~= place then return who .. " - " .. place end
  return who or place
end
-- the minutes to the step's stop from the stop before it (the plan's leg), where a new leg starts: nil on the leg of the
-- step before it (prev), for a step of no leg, and under half a minute
function G.Mins(s, prev)
  if not (s and s.leg and s.mins) then return nil end
  if prev and prev.leg == s.leg then return nil end
  if s.mins < 0.5 then return nil end
  return math.floor(s.mins + 0.5)
end

-- the place of a stop's NPC, in continent yards and on its map (Data.lua's D.NPC row: name, uiMap, x, y, continent,
-- world x, world y)
local function placeNpc(s, idx)
  local n = idx and QB.Data.NPC[idx]
  if not n then return end
  s.npc, s.m, s.x, s.y = idx, n[2], n[3], n[4]
  s.c, s.wx, s.wy = n[5], n[6], n[7]
end

-- the objective steps of one quest: its open spots (QuestMap.OpenSpots: finished objectives left out) clustered within
-- CLUSTER yards, nearest to `me` first; the kept spot (Target.lua's cur) leads when it is this quest's. Returns how
-- many steps it made
local spotsOf, spotPool, taken = {}, {}, {}
local function objectiveSteps(e, me, lead)
  local QM, M = QB.QuestMap, QB.Model
  if not (QM and QM.OpenSpots) or e.complete then return 0 end
  for k = #spotsOf, 1, -1 do spotsOf[k] = nil end
  for k in pairs(taken) do taken[k] = nil end
  local n = 0
  for _, sp in ipairs(QM.OpenSpots(e)) do
    local w = M.World(sp.m, sp.x * 100, sp.y * 100, wbuf)
    if w then
      n = n + 1
      local a = spotPool[n]
      if not a then a = {}; spotPool[n] = a end
      a.sp, a.c, a.wx, a.wy = sp, w.c, w.wx, w.wy
      a.d = (me and me.c == w.c) and ((w.wx - me.wx) ^ 2 + (w.wy - me.wy) ^ 2) or huge
      spotsOf[n] = a
    end
  end
  table.sort(spotsOf, function(a, b)
    if lead and (a.sp == lead) ~= (b.sp == lead) then return a.sp == lead end
    return a.d < b.d
  end)
  local made = 0
  for i, a in ipairs(spotsOf) do
    if not taken[i] then
      made = made + 1
      local s = step("objective")
      s.qid, s.obj, s.slot = e.id, a.sp.kind, a.sp.slot > 0 and a.sp.slot or nil
      s.c, s.wx, s.wy, s.m, s.x, s.y = a.c, a.wx, a.wy, a.sp.m, a.sp.x * 100, a.sp.y * 100
      s.n = 1 -- (the spawn spots merged here are one objective; other quests' steps near it are counted below)
      for j = i + 1, #spotsOf do
        local b = spotsOf[j]
        if not taken[j] and b.c == a.c and (b.wx - a.wx) ^ 2 + (b.wy - a.wy) ^ 2 <= CLUSTER * CLUSTER then taken[j] = true end
      end
      G.steps[#G.steps + 1] = s
    end
  end
  return made
end

-- a quest in your log, not complete, with no objective step (no spot in the world: a dungeon's, done inside): never a
-- "Hand in" step (6.0.0 made one, and the owner in Ironforge was told to hand in Old Ironforge Incursion at 0/1), but
-- "Do <quest> in <dungeon>" at the dungeon's entrance when the catalog has one (D.CAT's entrance), else at the hand-in
-- NPC, worded "(<dungeon>: entrance not known yet)"; a quest of no dungeon: "Do <quest>" at its hand-in NPC
local function doStep(e, q, turnIdx)
  local s = step("objective")
  s.qid, s.obj, s.n = e.id, "d", 1
  local cat = q and q.cat
  if cat and cat.dungeon then
    s.dungeon = cat.name
    local ent = cat.entrance
    local w = ent and QB.Model.World(ent.m, ent.x, ent.y, wbuf)
    if w then
      s.c, s.wx, s.wy, s.m, s.x, s.y = w.c, w.wx, w.wy, ent.m, ent.x, ent.y
      G.steps[#G.steps + 1] = s
      return s
    end
    s.noEntrance = true
  end
  placeNpc(s, turnIdx)
  G.steps[#G.steps + 1] = s
  return s
end

-- "and N more here": the objective steps of other quests within CLUSTER yards of a step (one quest's spawn spots
-- are one objective, never "more"); counted once the list is whole
local function countNear(steps)
  for i = 1, #steps do
    local a = steps[i]
    if a.kind == "objective" then
      a.n = 1
      for j = 1, #steps do
        local b = steps[j]
        if j ~= i and b.kind == "objective" and b.qid ~= a.qid and b.c == a.c and b.wx and a.wx
          and (b.wx - a.wx) ^ 2 + (b.wy - a.wy) ^ 2 <= CLUSTER * CLUSTER then a.n = a.n + 1 end
      end
    end
  end
end

-- "Not now": the quests put off, by character, for LATER seconds
local function laterDB()
  QuestBankDB = QuestBankDB or {}
  QuestBankDB.chars = QuestBankDB.chars or {}
  local key = QB:CharKey()
  local c = QuestBankDB.chars[key]
  if type(c) ~= "table" then c = {}; QuestBankDB.chars[key] = c end
  if type(c.guide) ~= "table" then c.guide = {} end
  if type(c.guide.later) ~= "table" then c.guide.later = {} end
  return c.guide
end
G.DB = laterDB
local function putOff(id)
  local at = laterDB().later[id]
  if not at then return false end
  if (time and time() or 0) - at < LATER then return true end
  laterDB().later[id] = nil
  return false
end
G.PutOff = putOff

-- dead: where your corpse lies (C_DeathInfo.GetCorpseMapPosition, DeathInfoDocumentation.lua, on the map you are on),
-- in continent yards; nil alive or where the client won't say. One table, read again once a second (the arrow asks
-- 20 times a second). G.dead: whether the last look found you a ghost (Target.lua's look turns the Guide on a client
-- that fires none of the death events)
local corpse = { kind = "corpse", name = "Your corpse" }
local corpseAt, corpseHad = -1, false
local function ghost()
  if type(UnitIsDeadOrGhost) ~= "function" then return false end
  local ok, v = pcall(UnitIsDeadOrGhost, "player")
  return ok and plain(v) == true
end
function G.Corpse()
  if not ghost() then G.dead = false; corpseAt = -1; return nil end
  G.dead = true
  if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then return nil end
  local now = GetTime and GetTime() or 0
  if corpseAt >= 0 and now - corpseAt < 1 then return corpseHad and corpse or nil end
  corpseAt, corpseHad = now, false
  local m = QB.API.MapID()
  if type(m) ~= "number" then return nil end
  local ok, pos = pcall(C_DeathInfo.GetCorpseMapPosition, m)
  pos = ok and plain(pos) or nil
  if type(pos) ~= "table" then return nil end
  local x, y = plain(pos.x), plain(pos.y)
  if pos.GetXY then
    local ok2, gx, gy = pcall(pos.GetXY, pos)
    if ok2 then x, y = plain(gx), plain(gy) end
  end
  if type(x) ~= "number" or type(y) ~= "number" then return nil end
  local w = QB.Model.World(m, x * 100, y * 100, wbuf)
  if not w then return nil end
  corpse.m, corpse.x, corpse.y, corpse.c, corpse.wx, corpse.wy = m, x * 100, y * 100, w.c, w.wx, w.wy
  corpseHad = true
  return corpse
end

-- the pick-ups: the quests of the plan (your own list, and the Guide's picks while it is on) you don't hold, each by
-- the giver of its first open step (Arrow.lua's A.FirstStep: a chain's next step you can take), or, when all that is
-- left of its chain is a step you hold, by its own giver: it comes right after that hand-in, so the frame shows it as
-- the step after. (The arrow's pick-up list, A.ListFor("pickup"), leaves those out, as the arrow cannot lead to them
-- yet.) Ids and givers only: { qid, idx }, pooled
local pickups, pickPool, pickIds = {}, {}, {}
local function readPickups()
  local Q, A = QB.Quest, QB.Arrow
  local p = QB:Plan()
  local n = 0
  for k = #pickups, 1, -1 do pickups[k] = nil end
  local function add(id)
    for i = 1, n do if pickups[i].qid == id then return end end
    local q = Q.Get(id)
    if not q or QB.state.log[id] or QB.API.IsDone(id) or QB:IsSkipped(id) or putOff(id) then return end
    local st = QB:Status(q)
    if st.code ~= "todo" and st.code ~= "prereq" then return end
    local g, held = q, false
    if A and A.FirstStep then g, held = A.FirstStep(q, st) end
    if held or not g then g = q end
    if not (g.giveIdx and g.giveIdx > 0 and g.give and not g.give.inside) or QB.state.log[g.id] or QB.API.IsDone(g.id) then return end
    for i = 1, n do if pickups[i].qid == g.id then return end end
    n = n + 1
    local d = pickPool[n]
    if not d then d = {}; pickPool[n] = d end
    d.qid, d.idx = g.id, g.giveIdx
    pickups[n] = d
  end
  -- (in id order: the list is the same from one re-plan to the next)
  for k = #pickIds, 1, -1 do pickIds[k] = nil end
  for id in pairs(p.add) do pickIds[#pickIds + 1] = id end
  if QB:GuideOn() then for id in pairs(p.auto) do if not p.add[id] then pickIds[#pickIds + 1] = id end end end
  table.sort(pickIds)
  for _, id in ipairs(pickIds) do add(id) end
  return pickups
end

-- the fill: the quests Now ranks best (UI:Candidates' rank: XP plus half the chain over trip and loop minutes, a
-- quarter when probably behind you), weighed by the drop rate as Now weighs it, half again as much when a party
-- member holds or can take it (Sync); never grey unless its chain pays the planner's low-value line, never more
-- than two levels above you, never one you put off or skipped, never one on your own list; up to the log's free
-- slots minus two, at most AUTO_MAX. Picks already made stay while they still qualify, so the plan holds still.
-- Its reach: a giver within 20 minutes, but 3 + your level minutes under 17 (a level-1 character is led around its
-- own valley, not 2,700 yards across the mountains to Coldridge: the straight-line minutes make that 8), and under
-- level 10 only a giver placed on your own map, never one the catalog cannot place
local function partyHas(id)
  local S = QB.Sync
  if not (S and S.members) then return false end
  for _, m in pairs(S.members) do if m.quests and m.quests[id] then return true end end
  return false
end
function G.Rank(c, level)
  local drop = QB.Data.DROP and QB.Data.DROP[c.id]
  local weight = (drop and drop < 25) and (0.5 + drop / 50) or 1
  return (c.rank or 0) * weight * (partyHas(c.id) and 1.5 or 1)
end
local ranked = {}
local function byRank(a, b) if a.grank ~= b.grank then return a.grank > b.grank end return a.id < b.id end
function G.Fill(level)
  local p = QB:Plan()
  local s = QB.state
  local free = QB.LOG_SLOTS - (s.logCount or 0) - 2
  local line = QB.Model.CHEAP * QB.Scale(level)
  local function qualifies(id)
    local q = QB.Quest.Get(id)
    if not q or q.lvl > level + 2 or (q.req or 1) > level then return false end
    if p.add[id] or putOff(id) or QB:IsSkipped(id) or s.log[id] or QB.API.IsDone(id) then return false end
    local st = QB:Status(q)
    -- (a chain's later step counts as Now lists it: the pick-ups lead to the chain's first open step)
    if st.code ~= "todo" and st.code ~= "item" and st.code ~= "prereq" then return false end
    if QB.QuestMap and QB.QuestMap.Grey(q, level) and QB:ChainLead(id) < line then return false end
    return true
  end
  -- what is held already: dropped once it no longer qualifies
  local n = 0
  for id in pairs(p.auto) do
    if qualifies(id) then n = n + 1 else p.auto[id] = nil end
  end
  if free <= n or n >= AUTO_MAX then return n end
  local reach, myMap = math.min(20, 3 + level), s.mapID
  local function inReach(c)
    if c.mins == nil then return level >= 10 end
    if c.mins > reach then return false end
    if level < 10 and myMap then
      local g = c.give and c.give > 0 and QB.Data.NPC[c.give]
      if not (g and g[2] == myMap) then return false end
    end
    return true
  end
  for k = #ranked, 1, -1 do ranked[k] = nil end
  for _, c in ipairs(QB.UI and QB.UI.Candidates and QB.UI:Candidates(nil, level) or {}) do
    if not p.auto[c.id] and not c.waste and inReach(c) and qualifies(c.id) then
      c.grank = G.Rank(c, level)
      if c.value and c.value >= line then ranked[#ranked + 1] = c end
    end
  end
  table.sort(ranked, byRank)
  for _, c in ipairs(ranked) do
    if n >= free or n >= AUTO_MAX then break end
    p.auto[c.id] = true
    n = n + 1
  end
  return n
end

-- the Train step: your level teaches something (D.SPELL_LV, the levels a class learns a new spell at) that you have
-- not trained yet (QuestBankDB.chars[key].guide.trained, the last level trained at), and a trainer of your class
-- (the seed D.TRAINER, or one learned at its window: QuestBankDB.disc.trainer) stands within TRAIN_MIN minutes'
-- walk of a route stop with a hand-in: "Train at <name>" goes before that stop's hand-in. No trainer known in reach:
-- G.reminder holds a deadline while the frame shows "New spells at your class trainer" (REMIND_S), once a level
local TRAIN_MIN, REMIND_S = 3, 180
G.TRAIN_MIN, G.REMIND_S = TRAIN_MIN, REMIND_S

local function classID()
  if type(UnitClass) ~= "function" then return nil, nil end
  local ok, _, tok, id = pcall(UnitClass, "player")
  if not ok then return nil, nil end
  return plain(id), plain(tok)
end

function G.NeedsTraining(level)
  if not level or level <= 1 then return false end -- (a new character holds its first spells)
  local _, tok = classID()
  local levels = tok and QB.Data.SPELL_LV and QB.Data.SPELL_LV[tok]
  if not levels then return false end
  if (laterDB().trained or 0) >= level then return false end
  for _, l in ipairs(levels) do if l == level then return true end end
  return false
end

-- the trainers of your class as places ({name, c, wx, wy, m, x, y, hub = 0, walk = 0}: on foot, M.Between): the seed's
-- rows and those learned in play; made again only when the seed table or the learned count changed
local trainerBuf, trainerFor, trainerN, trainerCls = {}, nil, -1, nil
local function trainers()
  local id = classID()
  local disc = QB.Discover and QB.Discover.DB and QB.Discover.DB()
  local learned = disc and disc.trainer
  local n = 0
  if learned then for _ in pairs(learned) do n = n + 1 end end
  if trainerFor == QB.Data.TRAINER and trainerN == n and trainerCls == id then return trainerBuf end
  trainerFor, trainerN, trainerCls = QB.Data.TRAINER, n, id
  for k = #trainerBuf, 1, -1 do trainerBuf[k] = nil end
  if not id then return trainerBuf end
  for _, t in ipairs(QB.Data.TRAINER or {}) do
    if t[3] == id then trainerBuf[#trainerBuf + 1] = { name = t[2], c = t[4], wx = t[5], wy = t[6], m = t[7], x = t[8], y = t[9], hub = 0, walk = 0 } end
  end
  for _, t in pairs(learned or {}) do
    if t.cl == id and t.m and t.x and t.y then
      local w = QB.Model.World(t.m, t.x, t.y, wbuf)
      if w then trainerBuf[#trainerBuf + 1] = { name = t.n, c = w.c, wx = w.wx, wy = w.wy, m = t.m, x = t.x, y = t.y, hub = 0, walk = 0 } end
    end
  end
  return trainerBuf
end

-- the nearest trainer of your class within TRAIN_MIN minutes of a stop (a place: {c, wx, wy, hub, walk})
function G.Trainer(stop)
  if not (stop and stop.c and stop.hub) then return nil end
  local M = QB.Model
  local mf = M.Factor(QB:Mounted())
  local best, bm
  for _, t in ipairs(trainers()) do
    if t.c == stop.c then
      local m = M.Between(stop, t, QB.faction, mf)
      if m and m <= TRAIN_MIN and (not bm or m < bm) then best, bm = t, m end
    end
  end
  return best
end

-- the seed knows this NPC already (by id): nothing to write down
local function seeded(key)
  local id = tonumber(key and key:match("^c(%d+)$"))
  if not id then return false end
  for _, t in ipairs(QB.Data.TRAINER or {}) do if t[1] == id then return true end end
  return false
end

-- the trainer's window: the NPC is written down as a trainer of your class (a class trainer's window opens for its
-- class alone; a profession's is told apart by IsTradeskillTrainer), and with nothing left to learn, this level is
-- trained. Nothing said in chat
local function onTrainer()
  if type(IsTradeskillTrainer) == "function" then
    local ok, trade = pcall(IsTradeskillTrainer)
    if ok and plain(trade) == true then return end
  end
  local id = classID()
  local okG, guid, okN, name = false, nil, false, nil
  if type(UnitGUID) == "function" then okG, guid = pcall(UnitGUID, "npc") end
  if type(UnitName) == "function" then okN, name = pcall(UnitName, "npc") end
  local key = okG and QB.Discover and QB.Discover.Key and QB.Discover.Key(guid)
  name = okN and plain(name) or nil
  if key and type(name) == "string" and id and not seeded(key) and QB.Discover.DB then
    local m = plain(QB.API.MapID())
    local pos = type(m) == "number" and C_Map and C_Map.GetPlayerMapPosition and select(2, pcall(C_Map.GetPlayerMapPosition, m, "player"))
    pos = plain(pos)
    local x, y = type(pos) == "table" and plain(pos.x), type(pos) == "table" and plain(pos.y)
    if type(x) == "number" and type(y) == "number" then
      local disc = QB.Discover.DB()
      disc.trainer = disc.trainer or {}
      local t = disc.trainer[key]
      if type(t) ~= "table" then t = {}; disc.trainer[key] = t end
      t.n, t.cl, t.m, t.x, t.y = name, id, m, x * 100, y * 100
    end
  end
  local okS, n = false, 0
  if type(GetNumTrainerServices) == "function" then okS, n = pcall(GetNumTrainerServices) end
  n = okS and plain(n) or 0
  local avail = 0
  if type(n) == "number" and type(GetTrainerServiceInfo) == "function" then
    for i = 1, n do
      local okI, _, kind = pcall(GetTrainerServiceInfo, i)
      if okI and plain(kind) == "available" then avail = avail + 1 end
    end
  end
  if avail == 0 then laterDB().trained = QB.state.level or 1 end
  QB:MarkDirty()
end

-- nothing worth taking in reach: where to kill until the next level that opens quests, and where they are. The
-- whole catalog is scanned for the nearest kill spot, but only when the list is empty (rare); one table reused
local grind = { kind = "grind" }
function G.Grind(level, me)
  local UI, D, M = QB.UI, QB.Data, QB.Model
  if not (UI and UI.Candidates) then return nil end
  local nextReq, nextCat
  for _, cand in ipairs(UI:Candidates(nil, level, level + 3)) do
    if cand.req and cand.req > level and (not nextReq or cand.req < nextReq or (cand.req == nextReq and (cand.mins or huge) < (nextCat and nextCat.mins or huge))) then
      nextReq, nextCat = cand.req, cand
    end
  end
  if not nextReq then return nil end
  -- the nearest kill spot of a quest around your level, for you
  local best, bd, bname
  local bit = QB.API.ClassBit()
  if me and D.SPOT and QB.QuestMap and QB.QuestMap.Spots then
    for id, r in pairs(D.Q) do
      if r[1] >= level - 2 and r[1] <= level + 1 and D.SPOT[id] then
        local side, cls = r[3], r[9]
        if (side == 0 or (side == 1 and QB.faction == "A") or (side == 2 and QB.faction == "H")) and (cls == 0 or bit == 0 or math.floor(cls / bit) % 2 == 1) then
          for _, sp in ipairs(QB.QuestMap.Spots(D.SPOT[id]) or {}) do
            if sp.kind == "k" then
              local w = M.World(sp.m, sp.x * 100, sp.y * 100, wbuf)
              if w and w.c == me.c then
                local d = (w.wx - me.wx) ^ 2 + (w.wy - me.wy) ^ 2
                if not bd or d < bd then
                  best, bd = sp, d
                  bname = (sp.name and D.SN and D.SN[sp.name]) or (D.MAPNAME and D.MAPNAME[sp.m]) or nil
                  grind.c, grind.wx, grind.wy, grind.m, grind.x, grind.y = w.c, w.wx, w.wy, sp.m, sp.x * 100, sp.y * 100
                end
              end
            end
          end
        end
      end
    end
  end
  local cat = D.CAT[nextCat.cat]
  local where = cat and cat.name or "the next zone"
  grind["until"] = nextReq
  if best then
    grind.text = string.format("Kill around %s until level %d, then %s", bname or "here", nextReq, where)
  else
    grind.text = string.format("Kill around here until level %d, then %s", nextReq, where)
    grind.c, grind.wx, grind.wy, grind.m, grind.x, grind.y = nil, nil, nil, nil, nil, nil
  end
  return grind
end

-- "about 14 min to level 6": the XP still needed (the game's bar, else D.TO_NEXT) over the plan's XP a minute until
-- ten minutes of play have been measured (Timer.XPPerHour), then over the measured rate; nil at the cap or with
-- nothing to go on. Returns the words, the minutes and whether they are measured
local function spanText(mins)
  if mins < 1 then return "under a minute" end
  if mins < 90 then return string.format("about %d min", math.floor(mins + 0.5)) end
  local h = math.floor(mins / 60)
  local m = math.floor((mins - h * 60) / 10 + 0.5) * 10
  if m == 60 then h, m = h + 1, 0 end
  return m > 0 and string.format("about %d h %d min", h, m) or string.format("about %d h", h)
end
G.SpanText = spanText
-- (the words are kept while they would read the same: the frame asks twice a second, and a tick makes no string)
local ttlLevel, ttlKey, ttlText = nil, nil, nil
function G.TimeToLevel()
  local s = QB.state
  local level = s.level or 1
  if level >= QB.MAXLEVEL or level >= (QB.CAP or QB.MAXLEVEL) then return nil end
  local max = (s.xpMax and s.xpMax > 1) and s.xpMax or QB.Data.TO_NEXT[level] or 0
  local need = max - (s.xp or 0)
  if need <= 0 then return nil end
  local rate = QB.Timer and QB.Timer.XPPerHour and QB.Timer.XPPerHour()
  local mins, measured
  if rate and rate > 0 then
    mins, measured = need / rate * 60, true
  else
    local r = QB.routePlan
    if not (r and r.xp and r.xp > 0 and r.t and r.t > 0) then return nil end
    -- the plan's XP a minute, with a minute a quest of doing (the planner counts travel and hand-ins, not the kills)
    local perMin = r.xp / (r.t + (r.count or 0))
    mins, measured = need / perMin, false
  end
  -- the minutes as the words round them: under one, whole minutes to 90, then tens
  local key = mins < 1 and 0 or (mins < 90 and math.floor(mins + 0.5) or math.floor(mins / 10 + 0.5) * 10)
  if level ~= ttlLevel or key ~= ttlKey then
    ttlLevel, ttlKey, ttlText = level, key, spanText(mins) .. " to level " .. (level + 1)
  end
  return ttlText, mins, measured
end

-- the quest's usable item, for the frame's button (GetQuestLogSpecialItemInfo, as the objective tracker's button:
-- link, texture, charges, showItemWhenComplete): id, link, texture; nil without one
function G.ItemFor(s)
  if not (s and s.qid and type(GetQuestLogSpecialItemInfo) == "function") then return nil end
  local e = QB.state.log[s.qid]
  if not (e and e.index) then return nil end
  local ok, link, tex = pcall(GetQuestLogSpecialItemInfo, e.index)
  link, tex = ok and plain(link) or nil, ok and plain(tex) or nil
  local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
  if not id then return nil end
  return id, link, tex
end

-- a hand-in with a reward to choose: the Guide holds QuestBank's pick (UI.BestReward's gear, else the first trinket,
-- else the first) and the frame marks it; nothing is chosen for you. G.reward = { qid, index, name } while the window
-- with the choice is open; the list is made again so the step says so
function G.HoldReward(qid, n)
  local level = QB.state.level or 1
  local UI = QB.UI
  local best = UI and UI.BestReward and (UI.BestReward(qid, "gear", level) or UI.BestReward(qid, "trinket", level)) or nil
  local index, name = 1, nil
  if type(GetQuestItemLink) == "function" then
    for i = 1, n do
      local ok, link = pcall(GetQuestItemLink, "choice", i)
      link = ok and plain(link) or nil
      local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
      if id and best and id == best then index = i end
      if i == index and type(link) == "string" then name = link:match("%[(.-)%]") end
    end
  end
  G.reward = { qid = qid, index = index, name = name }
  G.Replan()
  if QB.StepFrame and QB.StepFrame.MarkReward then QB.StepFrame.MarkReward() end
end
function G.DropReward()
  if not G.reward then return end
  G.reward = nil
  G.Replan()
  if QB.StepFrame and QB.StepFrame.MarkReward then QB.StepFrame.MarkReward() end
end

-- the steps, anew: the target first (its quest's objective spot, or its stop's hand-ins), then the rest of the route
-- stop by stop (each stop: the objectives of its quests on the way, its hand-ins, then the pick-ups there: what you
-- hand in to an NPC comes before what you take from the same one), then the pick-ups at no stop of the route,
-- the nearest first
local doneQ, byNpc, left = {}, {}, {}
-- a pick-up belongs to a stop when its giver is one of the stop's hand-in NPCs (stop.seen, Model.lua) or stands
-- within CLUSTER yards of one of its places on the same continent (Deputy Willem, twenty yards from the abbey's
-- hand-ins, is no hand-in of anyone's quest yet)
local function atStop(stop, idx)
  if stop.seen and stop.seen[idx] then return true end
  local n = QB.Data.NPC[idx]
  if not (n and n[5] == stop.c) then return false end
  local places = stop.places
  if places and #places > 0 then
    for _, p in ipairs(places) do
      if (p.wx - n[6]) ^ 2 + (p.wy - n[7]) ^ 2 <= CLUSTER * CLUSTER then return true end
    end
    return false
  end
  return stop.wx ~= nil and (stop.wx - n[6]) ^ 2 + (stop.wy - n[7]) ^ 2 <= CLUSTER * CLUSTER
end
local function byFar(a, b) if a.far ~= b.far then return a.far < b.far end return a.qid < b.qid end
function G.Replan()
  if not (QB:Settings().guide and QB:Settings().guide.on) then
    if #G.steps > 0 then for k = #G.steps, 1, -1 do G.steps[k] = nil end; G.ver = G.ver + 1 end
    return
  end
  if QB:GuideOn() then
    local before = QB:Plan().auto
    local n0 = 0
    for _ in pairs(before) do n0 = n0 + 1 end
    local n1 = G.Fill(QB.state.level or 1)
    if n1 ~= n0 and not G.filling then
      -- new picks: the route is planned again with them, and Replan runs again from QB:Changed
      G.filling = true
      QB.sigPlan, QB.sigNow = nil, nil
      QB:Recompute(true)
      G.filling = false
    end
  end
  local wasKey = G.FirstKey()
  for k = #G.steps, 1, -1 do G.steps[k] = nil end
  used = 0
  local T, A = QB.Target, QB.Arrow
  local me = QB.API.WorldPosition(nil, meBuf)
  local log = QB.state.log or {}
  local cur = T and T.Get(me)
  local r = T and T.Route()
  local legs = r and r.legs or {}
  for k in pairs(doneQ) do doneQ[k] = nil end
  -- dead: the corpse first; the route's steps follow, so the frame still shows what comes after
  local k = G.Corpse()
  if k then
    local s = step("corpse")
    s.c, s.wx, s.wy, s.m, s.x, s.y = k.c, k.wx, k.wy, k.m, k.x, k.y
    G.steps[1] = s
  end
  -- a hand-in in reach: first, whatever its value (Target.lua)
  if cur and cur.name and cur.near and not k then
    local s = step("handin")
    s.qid, s.n, s.near = cur.qid, cur.quests, true
    placeNpc(s, cur.near)
    G.steps[1] = s
    for id in pairs(cur.ids or {}) do if type(id) == "number" then doneQ[id] = true end end
  end
  local pickups = readPickups()
  local function pickupsAt(stop)
    for _, d in ipairs(pickups) do
      if d.qid and not doneQ[d.qid] and not putOff(d.qid) and d.idx and atStop(stop, d.idx) then
        local s = step("accept")
        s.qid = d.qid
        placeNpc(s, d.idx)
        G.steps[#G.steps + 1] = s
        doneQ[d.qid] = true
      end
    end
  end
  for li, leg in ipairs(legs) do
    local stop = leg.stop
    if stop then
      local n0 = #G.steps
      -- the objectives of this stop's quests still open (the target's quest is moved first below); one with no spot
      -- in the world gets its Do step (doStep) and no hand-in until it is complete
      for _, row in ipairs(leg.rows or {}) do
        local e = log[row.q.id]
        if e and not e.complete and not putOff(e.id) and not doneQ[e.id] and objectiveSteps(e, me, nil) == 0 then
          doStep(e, row.q, row.q.turnIdx)
          doneQ[e.id] = true
        end
      end
      -- its hand-ins, one step per NPC: the quests ready now, and the ones still to do after their objectives
      for k in pairs(byNpc) do byNpc[k] = nil end
      for _, row in ipairs(leg.rows or {}) do
        local e = log[row.q.id]
        if e and not doneQ[e.id] and not putOff(e.id) then
          local idx = row.q.turnIdx
          local s = byNpc[idx]
          if not s then
            s = step("handin")
            s.qid, s.n = e.id, 0
            placeNpc(s, idx)
            byNpc[idx] = s
            G.steps[#G.steps + 1] = s
          end
          s.n = s.n + 1
          if e.id < s.qid then s.qid = e.id end
          doneQ[e.id] = true
        end
      end
      pickupsAt(stop)
      -- the leg on each step made for it: its stop's name, the minutes to it from the stop before, how, which leg
      for i = n0 + 1, #G.steps do
        local s = G.steps[i]
        s.stop, s.mins, s.way, s.leg = stop.name, leg.travel, leg.kind, li
      end
    end
  end
  -- the quests held and not done that the route leaves out (Model.lua's route.waiting: a dungeon's, nothing to hand
  -- in yet, no spot to lead to): their Do steps, after the route's
  for _, w in ipairs(r and r.waiting or {}) do
    local e = log[w.q.id]
    if e and not e.complete and not doneQ[e.id] and not putOff(e.id) and objectiveSteps(e, me, nil) == 0 then
      doStep(e, w.q, w.q.turnIdx)
      doneQ[e.id] = true
    end
  end
  -- pick-ups at no stop of the route (a giver away from every hand-in): after the route, the nearest to you first
  -- (off your continent last, then by id)
  for k = #left, 1, -1 do left[k] = nil end
  for _, d in ipairs(pickups) do
    if d.qid and not doneQ[d.qid] and not putOff(d.qid) then
      local n = QB.Data.NPC[d.idx]
      d.far = (me and n and n[5] == me.c) and ((n[6] - me.wx) ^ 2 + (n[7] - me.wy) ^ 2) or huge
      left[#left + 1] = d
    end
  end
  table.sort(left, byFar)
  for _, d in ipairs(left) do
    local s = step("accept")
    s.qid = d.qid
    placeNpc(s, d.idx)
    s.stop = s.m and QB.Data.MAPNAME and QB.Data.MAPNAME[s.m] or nil -- (no stop of the route: its zone)
    G.steps[#G.steps + 1] = s
    doneQ[d.qid] = true
  end
  countNear(G.steps)
  -- the first step is the target's: when the target leads to an objective spot of a quest, that quest's nearest
  -- objective step goes first (Target.lua keeps the quest and the spot; the list follows it, never the other way); so
  -- does its Do step when the target is a dungeon's entrance, or a hand-in with nothing done yet (cur.pending)
  if cur and cur.name and (cur.obj or cur.pending) and cur.qid and not (G.steps[1] and (G.steps[1].near or G.steps[1].kind == "corpse")) then
    for i, s in ipairs(G.steps) do
      if s.kind == "objective" and s.qid == cur.qid then
        if i > 1 then table.remove(G.steps, i); table.insert(G.steps, 1, s) end
        s.c, s.wx, s.wy, s.m, s.x, s.y = cur.c, cur.wx, cur.wy, cur.m, cur.x, cur.y
        break
      end
    end
  end
  -- new spells to learn: Train at the trainer nearest a stop with a hand-in to come, before that hand-in; none within
  -- reach: the reminder line (once a level)
  local level = QB.state.level or 1
  if G.NeedsTraining(level) then
    local placed = false
    for i, s in ipairs(G.steps) do
      if s.kind == "handin" and not s.near then
        local stop
        for _, leg in ipairs(legs) do if leg.stop and leg.stop.seen and leg.stop.seen[s.npc] then stop = leg.stop break end end
        local t = stop and G.Trainer(stop)
        if t then
          local ts = step("train")
          ts.name, ts.c, ts.wx, ts.wy, ts.m, ts.x, ts.y = t.name, t.c, t.wx, t.wy, t.m, t.x, t.y
          table.insert(G.steps, i, ts)
          placed = true
          break
        end
      end
    end
    if placed then
      G.reminder, G.remindedAt = nil, nil
    elseif G.remindedAt ~= level then
      G.reminder, G.remindedAt = (GetTime and GetTime() or 0) + REMIND_S, level
    end
  else
    G.reminder, G.remindedAt = nil, nil
  end
  -- a reward to choose in the open window: that first, whatever else stands
  if G.reward then
    local s = step("reward")
    s.qid, s.name = G.reward.qid, G.reward.name
    table.insert(G.steps, 1, s)
  end
  -- the arrow's step on the way to the first step (a flight master, a pier, the tram: Target.lua's T.Step) goes before it
  local ts, onWay = nil, false
  if QB.Target and QB.Target.Step then ts, onWay = QB.Target.Step() end
  if ts and onWay and G.steps[1] and G.steps[1].kind ~= "corpse" and G.steps[1].kind ~= "reward" then
    local s = step("travel")
    s.text, s.c, s.wx, s.wy = ts.name, ts.c, ts.wx, ts.wy
    s.atlas, s.icon = ts.atlas, ts.icon
    table.insert(G.steps, 1, s)
  end
  -- nothing at all: where to grind until the next level opens quests
  if #G.steps == 0 then
    local g = G.Grind(QB.state.level or 1, me)
    if g then
      local s = step("grind")
      s.text, s["until"], s.c, s.wx, s.wy, s.m, s.x, s.y = g.text, g["until"], g.c, g.wx, g.wy, g.m, g.x, g.y
      G.steps[1] = s
    end
  end
  local nowKey = G.FirstKey()
  G.ver = G.ver + 1 -- (the texts may have changed: the frame redraws on any Replan; the key feeds the trace)
  if QB.tracing and nowKey ~= wasKey then QB.Trace("guide: first step %s -> %s", wasKey ~= "" and wasKey or "none", nowKey ~= "" and nowKey or "none") end
end

function G.Current() return G.steps[1] end

-- the party's steps (Sync's 1G line, one a member, received into m.step), by name: one list and its rows reused,
-- made again only when Sync's member-step version moved (a member came, went, or sent a step or status) or the
-- group state changed; a tick with nothing changed makes no table and no string (S:Members makes a list each call).
-- G.memberVer tells the frame which list it has
local memberSteps, memberPool = {}, {}
local memberFor, memberGrouped = -1, false
G.memberVer = 0
local function byName(x, y) return x.name < y.name end
function G.MemberSteps()
  local S = QB.Sync
  local grouped = (S and S.Members and S.members and IsInGroup and IsInGroup()) and true or false
  local ver = S and S.stepVer or 0
  if ver == memberFor and grouped == memberGrouped then return memberSteps end
  memberFor, memberGrouped = ver, grouped
  G.memberVer = G.memberVer + 1
  for k = #memberSteps, 1, -1 do memberSteps[k] = nil end
  if not grouped then return memberSteps end
  local n = 0
  for _, m in ipairs(S:Members()) do
    if type(m.step) == "string" and m.step ~= "" then
      n = n + 1
      local row = memberPool[n]
      if not row then row = {}; memberPool[n] = row end
      row.name, row.class, row.text = m.name or m.key, m.class, m.step
      memberSteps[n] = row
    end
  end
  table.sort(memberSteps, byName)
  return memberSteps
end
function G.Steps() return G.steps end

-- the first step told apart as the target tells stops: its kind, its quest, its NPC and its place
function G.FirstKey()
  local s = G.steps[1]
  if not s then return "" end
  return s.kind .. ":" .. tostring(s.qid) .. ":" .. tostring(s.npc) .. ":" .. tostring(s.wx and math.floor(s.wx) or "")
end

-- "Not now" (an hour) or "Drop" (for good); the list is made again
function G.Skip(id, how)
  if not id then return end
  if how == "drop" then QB:SetSkipped(id, true)
  else laterDB().later[id] = time and time() or 0 end
  QB:MarkDirty()
end

-- the game's events, from Core.lua's frame (and Target.lua's look, for a death the client did not announce)
function G.OnEvent(event, a1, a2)
  if event == "PLAYER_DEAD" or event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then
    -- (no re-plan: a release is no jump, and the route stands; the list is made again with or without the corpse)
    G.Replan()
    if QB.Arrow and QB.Arrow.Invalidate then QB.Arrow.Invalidate() end
    return
  end
  if event == "TRAINER_SHOW" then onTrainer() return end
  if event == "QUEST_FINISHED" then G.DropReward() return end
  if event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" or event == "PLAYER_LEVEL_UP" then
    QB:MarkDirty() -- (Core.lua marks it too: the list is made again after the re-plan)
  end
end
