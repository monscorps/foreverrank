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
-- Replan runs after each re-plan (Core.lua, QB:Changed) and on the Guide's own events; it reuses its tables, so a
-- re-plan makes a few kilobytes and a tick none.
local _, QB = ...
local G = { steps = {}, ver = 0, later = nil }
QB.Guide = G

local CLUSTER = 150        -- yards: objective spots this close are one step
local LATER = 3600         -- seconds "Not now" holds
local AUTO_MAX = 8         -- auto picks at once (G.Fill)
G.CLUSTER, G.LATER, G.AUTO_MAX = CLUSTER, LATER, AUTO_MAX

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
local VERB = { k = "Kill", c = "Collect", u = "Use", b = "Buy", e = "Go to", f = "Gather", s = "Find" }

-- the words of a step, made when asked (the frame asks each refresh; no string is kept on the step)
function G.Text(s)
  if not s then return "" end
  local k = s.kind
  if k == "accept" then return "Accept " .. questName(s.qid) .. " from " .. npcName(s.npc)
  elseif k == "handin" then
    if s.near then return s.n and s.n > 1 and string.format("Hand in %d quests here", s.n) or ("Hand in " .. questName(s.qid) .. " here") end
    return s.n and s.n > 1 and string.format("Hand in %d quests at %s", s.n, npcName(s.npc)) or ("Hand in " .. questName(s.qid))
  elseif k == "objective" then
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
  elseif k == "reward" then return "Choose a reward: " .. (s.name or "QuestBank's pick") .. " is QuestBank's pick"
  end
  return s.text or ""
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
-- CLUSTER yards, nearest to `me` first; the kept spot (Target.lua's cur) leads when it is this quest's
local spotsOf, spotPool, taken = {}, {}, {}
local function objectiveSteps(e, me, lead)
  local QM, M = QB.QuestMap, QB.Model
  if not (QM and QM.OpenSpots) or e.complete then return end
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
  for i, a in ipairs(spotsOf) do
    if not taken[i] then
      local s = step("objective")
      s.qid, s.obj, s.slot = e.id, a.sp.kind, a.sp.slot > 0 and a.sp.slot or nil
      s.c, s.wx, s.wy, s.m, s.x, s.y = a.c, a.wx, a.wy, a.sp.m, a.sp.x * 100, a.sp.y * 100
      s.n = 1
      for j = i + 1, #spotsOf do
        local b = spotsOf[j]
        if not taken[j] and b.c == a.c and (b.wx - a.wx) ^ 2 + (b.wy - a.wy) ^ 2 <= CLUSTER * CLUSTER then taken[j] = true; s.n = s.n + 1 end
      end
      G.steps[#G.steps + 1] = s
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
-- slots minus two, at most AUTO_MAX. Picks already made stay while they still qualify, so the plan holds still
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
    if st.code ~= "todo" and st.code ~= "item" then return false end
    if QB.QuestMap and QB.QuestMap.Grey(q, level) and QB:ChainLead(id) < line then return false end
    return true
  end
  -- what is held already: dropped once it no longer qualifies
  local n = 0
  for id in pairs(p.auto) do
    if qualifies(id) then n = n + 1 else p.auto[id] = nil end
  end
  if free <= n or n >= AUTO_MAX then return n end
  for k = #ranked, 1, -1 do ranked[k] = nil end
  for _, c in ipairs(QB.UI and QB.UI.Candidates and QB.UI:Candidates(nil, level) or {}) do
    if not p.auto[c.id] and not c.waste and (c.mins == nil or c.mins <= 20) and qualifies(c.id) then
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

-- the steps, anew: the target first (its quest's objective spot, or its stop's hand-ins), then the rest of the route
-- stop by stop (each stop: the objectives of its quests on the way, its hand-ins, then the pick-ups there: what you
-- hand in to an NPC comes before what you take from the same one), then the pick-ups at no stop of the route
local doneQ, byNpc = {}, {}
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
      if d.qid and not doneQ[d.qid] and not putOff(d.qid) and d.idx and stop.seen and stop.seen[d.idx] then
        local s = step("accept")
        s.qid = d.qid
        placeNpc(s, d.idx)
        G.steps[#G.steps + 1] = s
        doneQ[d.qid] = true
      end
    end
  end
  for _, leg in ipairs(legs) do
    local stop = leg.stop
    if stop then
      -- the objectives of this stop's quests still open (the target's quest is moved first below)
      for _, row in ipairs(leg.rows or {}) do
        local e = log[row.q.id]
        if e and not e.complete and not putOff(e.id) then objectiveSteps(e, me, nil) end
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
    end
  end
  -- pick-ups at no stop of the route (a giver away from every hand-in): after the route, in the plan's order
  for _, d in ipairs(pickups) do
    if d.qid and not doneQ[d.qid] and not putOff(d.qid) then
      local s = step("accept")
      s.qid = d.qid
      placeNpc(s, d.idx)
      G.steps[#G.steps + 1] = s
      doneQ[d.qid] = true
    end
  end
  -- the first step is the target's: when the target leads to an objective spot of a quest, that quest's nearest
  -- objective step goes first (Target.lua keeps the quest and the spot; the list follows it, never the other way)
  if cur and cur.name and cur.obj and cur.qid and not (G.steps[1] and (G.steps[1].near or G.steps[1].kind == "corpse")) then
    for i, s in ipairs(G.steps) do
      if s.kind == "objective" and s.qid == cur.qid then
        if i > 1 then table.remove(G.steps, i); table.insert(G.steps, 1, s) end
        s.c, s.wx, s.wy, s.m, s.x, s.y = cur.c, cur.wx, cur.wy, cur.m, cur.x, cur.y
        break
      end
    end
  end
  -- the arrow's step on the way to the first step (a flight master, a pier, the tram: Target.lua's T.Step) goes before it
  local ts, onWay = nil, false
  if QB.Target and QB.Target.Step then ts, onWay = QB.Target.Step() end
  if ts and onWay and G.steps[1] and G.steps[1].kind ~= "corpse" then
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
  if event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" or event == "PLAYER_LEVEL_UP" then
    QB:MarkDirty() -- (Core.lua marks it too: the list is made again after the re-plan)
  end
end
