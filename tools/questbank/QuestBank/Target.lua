-- SPDX-License-Identifier: GPL-3.0-or-later
-- The one target: where the route sends you next. The arrow (its route mode), the minimap (its first stroke, its label
-- and the golden path) and the Map page (its first stroke) all read it here, so the three agree. It is the route's first
-- stop; while a quest that stop takes is unfinished, the nearest spot of one of its objectives still to do (the
-- minimap's own marks, the finished ones left out); and while the arrow shows the way there step by step, its step
-- toward it (a flight master, a pier, the tram: T.Step).
-- It changes on what you do, not on where you happen to stand:
--   the route's first stop is the planner's, which keeps it unless another plan is clearly better (Model.lua, M.Plan),
--   and the route is planned again only when something it depends on changed (Core.lua's signature): your quests or
--   their state, your level, the flight paths you know, the hearthstone, or a jump in place (QB.jumpVer, below);
--   while questing the route is the planned one, your log's quests done or not, so a quest turning complete re-plans it
--   and keeps its first stop (5.4.4 as first built followed what was ready to hand in whenever anything was, and a
--   quest done in Alterac sent the arrow back to Southshore, 1,300 yards away, with the other quest's spot at hand);
--   the quest whose objectives it leads to is kept until its objectives there are done, it is complete or gone from your
--   log, or you jump in place (then it is picked afresh); progress on another quest of the stop never moves it (5.4.4
--   as first built named the other quest on each count of its that grew while the quest kept's did not, and a mob
--   that counts for the quest kept and drops an item for the other, the kill in one read of the log and the loot in
--   the next, flipped the objective on every mob);
--   among the kept quest's spots one is kept until that objective is done or another spot is clearly nearer (a quarter
--   nearer and 30 yards), so walking between two never flips it on the line halfway. (5.4.3's minimap picked the
--   nearest spot of any quest in your log, finished objectives too, 20 times a second, and the arrow went its own way;
--   5.4.4 as first built kept the spot but not the quest, and running north the objective went from one quest to the
--   other with nothing done.)
-- The route it comes from is the one the Route page shows (T.Route, T.Mode): a run's rest; while questing, the planned
-- route from where you stand (Log and pick-ups), or what is ready to hand in while that page shows it; while banking,
-- what is ready to hand in, or the planned route while that page shows it. The map's pins show the same (Pins.lua).
-- A hand-in in reach comes first (5.4.4, the owner's play test: told to go to Booty Bay a few yards from a quest he
-- could hand in, worth little): a stop of the route with a quest ready to hand in, its NPC within REACH yards of you
-- (kept to REACH_KEEP once chosen, and kept against another in reach unless that one is clearly nearer, as a spot is),
-- is the target at once, "Hand in X here", whatever its value; handed in, the route goes on from where you stand. The
-- planner puts it first too when it plans from here (Model.lua, M.Plan). Not in the air, nor as a ghost: you can hand
-- nothing in there; nor while you bank at a cap with no run under way: what is ready stays banked for the run.
-- Also here: the jumps in place that plan the route again (a loading screen, landing from a flight, a hearth, a portal:
-- 300 yards within a second, or another continent), and /qb trace, the opt-in diagnostic for a report.
local _, QB = ...
if QB.dormant then return end
local T = {}
QB.Target = T

local floor, huge = math.floor, math.huge
local NEARER, NEARER_YD = 0.75, 30 -- another objective spot takes over only this much nearer: a quarter, and 30 yards
local REACH, REACH_KEEP = 60, 90    -- yards: a hand-in this near is the target at once, kept to this
local LEFT_FOR = 3                  -- seconds past REACH_KEEP of a stop put first for its hand-in in reach: walked away
local JUMP = 300                    -- yards within a look (a second): a jump in place
local TICK = 1                      -- seconds between looks
T.NEARER, T.NEARER_YD, T.JUMP, T.REACH, T.REACH_KEEP, T.LEFT_FOR = NEARER, NEARER_YD, JUMP, REACH, REACH_KEEP, LEFT_FOR
T.ver = 0                           -- goes up each time the target changes (the Map page redraws its strokes on it)

-- which of the two routes is on screen: "now" (what is ready to hand in) or "plan" (the planned route, your log and
-- pick-ups). A run's rest is "now"; while questing the plan, unless the Route page shows what is ready now (routeQuest);
-- while banking what is ready now, unless that page shows the plan (routeMode). Questing has its own setting: routeMode
-- "now" was the default of every save, and questing follows the plan whatever it says
function T.Mode()
  if QB.Run and QB.Run.Get() then return "now" end
  local set = QB:Settings()
  if (QB.mode or "quest") == "quest" then return set.routeQuest == "now" and "now" or "plan" end
  return set.routeMode == "plan" and "plan" or "now"
end

-- the route on screen (T.Mode): the planned route, or what is ready now while anything is (else the plan)
function T.Route()
  local now, plan = QB.routeNow, QB.routePlan
  if T.Mode() == "plan" then return plan end
  if QB.Run and QB.Run.Get() then return now end
  if now and now.legs and #now.legs > 0 then return now end
  return plan
end

-- (the review round) a stop as the arrow names it (cur.shown): its place in words, as the map's pins and the step frame do
-- (Travel.lua's TV.StopPlace: "Goldshire", never Model.lua's "Elwynn Forest (42, 65)", which stays the stop's name, for
-- matching); and the tooltip's head with it. Worked out once a stop, no string a look
local placeFor, placeName, placeShown, placeHead = nil, nil, nil, nil
local function placeOf(st, name)
  if st ~= placeFor or name ~= placeName then
    placeFor, placeName = st, name
    placeShown = (st and QB.Travel and QB.Travel.StopPlace and QB.Travel.StopPlace(st)) or name
    placeHead = placeShown ~= name and ("Next stop: " .. placeShown:gsub("%%", "%%%%")) or nil
  end
  return placeShown, placeHead
end

-- stop 1 as the map's pins have it (Pins.lua's list, from T.Route), else the route's first leg
local function stopOne()
  local P = QB.Pins
  local list = P and P.list
  if list then
    for i = 1, #list do
      local d = list[i]
      if d.num == 1 then return d, nil end
    end
  end
  local r = T.Route()
  local leg = r and r.legs and r.legs[1]
  if leg and leg.stop then return nil, leg end
  return nil, nil
end

-- the target: one table, filled anew when it changes (the arrow's guide sees a new target by its name and place).
-- kind "route"; obj: an objective's spot, or a dungeon's entrance (else the stop); pending: the stop has nothing to
-- hand in yet (a quest held and not done leads: pendingOf); name, c, wx, wy (continent yards), m, x, y (its map, in
-- percent), qid (the quest whose colour it takes), quests and what (the arrow's tooltip), verb and head (the arrow's
-- words), after (what comes next), stop (the stop's name)
local cur = { kind = "route" }
T.cur = cur
local was = { gen = 0 }                -- the stop it was worked out for, the quest and the objective spot kept
local spots, spotPool, spotsAt, spotsGen = {}, {}, -1, -1 -- the open spots of the stop's quests, and what for
local pendCache                                           -- the stop's pending quest (pendingOf), read with the spots
local wbuf = {}                        -- (a world position read into it)
local idList = {}

-- the stop's quests still in progress: their objectives' spots not done (QuestMap.lua's rule), in continent yards.
-- Only read: which quest is kept is pickSpot's, and a count of another quest growing changes nothing (5.4.4 as first
-- built named that quest when its count grew near its spots while the quest kept's did not, and a mob that counts for
-- the quest kept and drops an item for the other flipped the objective on every mob; progress far from its spots
-- took the target to it wherever you were, and the arrow pointed 1,900 yards back behind you for the rest of the walk)
local function readSpots(ids)
  local QM, M = QB.QuestMap, QB.Model
  local n = 0
  for k = #idList, 1, -1 do idList[k] = nil end
  for id in pairs(ids) do if type(id) == "number" then idList[#idList + 1] = id end end
  table.sort(idList)
  local log = QB.state and QB.state.log or {}
  for _, id in ipairs(idList) do
    local e = log[id]
    if e and not e.complete and QM and QM.OpenSpots then
      local q = QB.Quest.Get(id)
      for _, sp in ipairs(QM.OpenSpots(e)) do
        local w = M.World(sp.m, sp.x * 100, sp.y * 100, wbuf)
        if w then
          n = n + 1
          local s = spotPool[n] or {}
          spotPool[n] = s
          s.sp, s.c, s.wx, s.wy, s.qid = sp, w.c, w.wx, w.wy, id
          s.name = q and q.name or QB.Plain(e.title) or ("Quest " .. id)
          spots[n] = s
        end
      end
    end
  end
  for k = #spots, n + 1, -1 do spots[k] = nil end
end

-- the objective spot to go to: of the quest kept while it has one (the nearest first), else of any of the stop's
-- quests (the nearest); the spot kept unless it is done (gone from the list) or another of the quest's is clearly nearer
local function pickSpot(me)
  local q = was.spotQ
  if q then
    local has = false
    for i = 1, #spots do if spots[i].qid == q then has = true break end end
    if not has then q = nil end
  end
  local keep, kd, best, bd
  for i = 1, #spots do
    local s = spots[i]
    if not q or s.qid == q then
      if s.sp == was.spot and s.qid == was.spotQ then keep = s end
      if me and s.c == me.c then
        local dx, dy = s.wx - me.wx, s.wy - me.wy
        local d = dx * dx + dy * dy
        if not bd or d < bd then best, bd = s, d end
        if s == keep then kd = d end
      end
    end
  end
  if not me then return keep end
  if keep and kd and best ~= keep then
    local dk, db = math.sqrt(kd), math.sqrt(bd)
    if not (db <= NEARER * dk and dk - db >= NEARER_YD) then best = keep end
  end
  return best
end

-- none of the stop's quests complete (its quests in your log, idList as readSpots sorted them), and no spot to lead to:
-- nothing to hand in there yet. A quest of the stop held and not done leads instead: the lowest id with a dungeon
-- entrance the catalog places (D.CAT's entrance: "Enter <dungeon>", to do it there), else the lowest id, the stop
-- itself as "Finish <quest>" (its pin and place as before: the minimap's stroke and label stay the stop's). Nil with
-- a quest complete there, or none held (a stop of quests not taken yet is the stop as before). One table reused:
-- { qid, n (held and not done there), ent, cat, c, wx, wy (the entrance's) }
-- (6.0.0 took the stop itself "to hand in there": the owner in Ironforge with Old Ironforge Incursion at 0/1, a quest
-- of The Hall of Thanes with no spot and no entrance, was sent to King Magni and told "You're there")
local pendBuf = {}
local function pendingOf()
  local log = QB.state and QB.state.log or {}
  local first, firstCat, n = nil, nil, 0
  local ent, entQ, entCat
  for _, id in ipairs(idList) do
    local e = log[id]
    if e then
      if e.complete then return nil end
      n = n + 1
      local q = QB.Quest.Get(id)
      local cat = q and q.cat
      if not first then first, firstCat = id, (cat and cat.dungeon) and cat or nil end
      if not ent then
        local en = cat and cat.dungeon and cat.entrance
        local w = en and QB.Model.World(en.m, en.x, en.y, wbuf)
        if w then ent, entQ, entCat = en, id, cat; pendBuf.c, pendBuf.wx, pendBuf.wy = w.c, w.wx, w.wy end
      end
    end
  end
  if not first then return nil end
  pendBuf.n, pendBuf.ent = n, ent
  if ent then pendBuf.qid, pendBuf.cat = entQ, entCat else pendBuf.qid, pendBuf.cat = first, firstCat end
  return pendBuf
end

-- the stop's quests: its pin's (Pins.lua's ids), else the leg's hand-ins; and the lowest id of them, whose colour the
-- stop's circle and its stroke take on the minimap (Mini's firstId)
local legIds = {}
local function idsOf(d, leg)
  if d and d.ids then return d.ids end
  for k in pairs(legIds) do legIds[k] = nil end
  for _, row in ipairs(leg and leg.rows or {}) do legIds[row.q.id] = true end
  return legIds
end
local function lowest(d, leg)
  local low
  if d and d.ids then
    for id in pairs(d.ids) do if type(id) == "number" and (not low or id < low) then low = id end end
  else
    for _, row in ipairs(leg and leg.rows or {}) do if not low or row.q.id < low then low = row.q.id end end
  end
  return low
end

-- a yes from the game (UnitOnTaxi, UnitIsDeadOrGhost): false where it errors or hides the answer
local function yes(fn, unit)
  if type(fn) ~= "function" then return false end
  local ok, v = pcall(fn, unit)
  return ok and QB.Plain(v) == true
end

-- the route's hand-in in reach: a stop with a quest ready to hand in whose NPC (who takes it) stands within REACH yards
-- of you (REACH_KEEP for the one chosen at the last look). The one chosen is kept while it is in reach, unless another
-- is clearly nearer (a quarter, and 30 yards: standing by one NPC of a town, walking round to the next never flips it on
-- the line halfway); else the nearest. None in the air or as a ghost (nothing is handed in there), and none while you
-- bank at the cap with no run under way (QB:Mode() "lock": what is ready stays banked for the run; 5.4.4 as first built
-- said "Hand in X here" at the cap, of a quest Accept for me kept banked). Returns the stop, that NPC's place, the
-- first such quest there (the lowest id), how many are ready there and the leg. Loops over the route's own tables:
-- nothing is made
local function noHandin() return yes(UnitOnTaxi, "player") or yes(UnitIsDeadOrGhost, "player") end
T.NoHandin = noHandin
local function nearHandin(me)
  local r = me and T.Route()
  local legs = r and r.legs
  if not legs then return nil end
  if noHandin() or (QB.mode == "lock" and not (QB.Run and QB.Run.Get())) then return nil end
  local log = QB.state and QB.state.log or {}
  local best, bd, bp, bq, bn, bl
  local kst, kd, kp, kq, kn, kl
  for i = 1, #legs do
    local leg = legs[i]
    local st = leg.stop
    if st and st.c == me.c and st.places then
      for _, p in ipairs(st.places) do
        local dx, dy = p.wx - me.wx, p.wy - me.wy
        local d = dx * dx + dy * dy
        local kept = was.near == p.npc
        local lim = kept and REACH_KEEP or REACH
        if d <= lim * lim and (kept or not bd or d < bd) then
          local q, n = nil, 0
          for _, row in ipairs(leg.rows or {}) do
            local e = log[row.q.id]
            if e and e.complete and row.q.turnIdx == p.npc then
              n = n + 1
              if not q or row.q.id < q.id then q = row.q end
            end
          end
          if q then
            if kept and not kst then kst, kd, kp, kq, kn, kl = st, d, p, q, n, leg end
            if not bd or d < bd then best, bd, bp, bq, bn, bl = st, d, p, q, n, leg end
          end
        end
      end
    end
  end
  if kst and bp ~= kp then
    local dk, db = math.sqrt(kd), math.sqrt(bd)
    if not (db <= NEARER * dk and dk - db >= NEARER_YD) then return kst, kp, kq, kn, kl end
  end
  return best, bp, bq, bn, bl
end
T.NearHandin = nearHandin

-- a route whose first stop the planner put first only for its hand-in in reach (Model.lua, route.firstNear: the
-- session's first plan and one after a jump in place too), walked away from without handing in (all its NPCs past
-- REACH_KEEP, reach and a margin, for LEFT_FOR seconds, on foot and alive: in the air the landing plans again, and a
-- ghost runs back; a step out and back is no leaving): planned again from where you are (QB.reachVer, which
-- Core.lua's signature counts), and the planner keeps the stop it kept before (route.lead) unless going back is
-- clearly quicker. Kept first by that (route.firstLeft), it is planned again each REACH_KEEP yards further from it
-- than where that plan was made, until going back is no longer clearly quicker and it gives way. 5.4.4 as first built
-- kept that stop first, behind you, until the next plan, and then kept it for having been first; left the stop first
-- behind you for good when it was the first plan's or one after a jump; and made the one plan for walking away, so
-- a stop that won it stayed stop 1 behind you until something else changed
local leftFrom      -- the route last planned again for it
local leftAt, leftR -- since when you have been past the line of the route's first stop, and of which route
local function nearestOf(st, c, wx, wy)
  local d = huge
  if st.c == c then
    for _, p in ipairs(st.places) do
      local dd = (p.wx - wx) ^ 2 + (p.wy - wy) ^ 2
      if dd < d then d = dd end
    end
  end
  return d
end
local function leftBehind(me)
  local r = me and T.Route()
  local leg = r and (r.firstNear or r.firstLeft) and r.legs and r.legs[1]
  local st = leg and leg.stop
  if not (st and st.places) or leftFrom == r or noHandin() then leftAt = nil return end
  local line = REACH_KEEP
  if r.firstLeft and r.startX then
    local d0 = nearestOf(st, r.startC, r.startX, r.startY)
    if d0 < huge then line = math.sqrt(d0) + REACH_KEEP end
  end
  if nearestOf(st, me.c, me.wx, me.wy) <= line * line then leftAt = nil return end
  local now = GetTime and GetTime() or 0
  if not leftAt or leftR ~= r then leftAt, leftR = now, r end
  if now - leftAt < LEFT_FOR then return end
  leftFrom, leftAt = r, nil
  QB.reachVer = (QB.reachVer or 0) + 1
  if QB.tracing then
    QB.Trace(r.firstLeft and "target: %s, walked away from, still first: the route planned again from further on"
      or "target: the hand-in in reach at %s left behind: the route planned again", tostring(st.name))
  end
  QB:MarkDirty()
end

local function nothing()
  if cur.name ~= nil then
    if QB.tracing then QB.Trace("target: %s -> nothing", cur.name) end
    cur.name, cur.c, cur.wx, cur.wy, cur.obj, cur.pending = nil, nil, nil, nil, nil, nil
    T.ver = T.ver + 1
  end
  return nil
end

-- the stop the target was worked out for, told apart as the planner tells stops (Model.lua's stopKeys and indexOf): its
-- town, else the NPCs it has (a copy in wasNpcs, one table reused); a stop without them (a pin of no route stop) by its
-- name. The same stop shares its town or an NPC with the last one, on the same land
local wasNpcs = {}
local function noteStop(st)
  was.town = st and st.town or nil
  for k = #wasNpcs, 1, -1 do wasNpcs[k] = nil end
  if st and st.npcs then for i, npc in ipairs(st.npcs) do wasNpcs[i] = npc end end
end
local function sameStop(st, name, c)
  if c ~= was.c then return false end
  if not (st and st.npcs) then return name == was.name end
  if st.town and st.town == was.town then return true end
  for _, npc in ipairs(st.npcs) do
    for k = 1, #wasNpcs do if wasNpcs[k] == npc then return true end end
  end
  return false
end

-- the target from where you stand (me: {c, wx, wy}, or nil where the client won't say), or nil
local nearIds, prunedAt = {}, -1
function T.Get(me)
  -- (the map's open-spot lists kept only for the quests in your log, as QuestBank's data changes: the minimap's list
  -- does it too, but only while its pins are on)
  if prunedAt ~= QB.changed and QB.QuestMap and QB.QuestMap.PruneOpen then
    prunedAt = QB.changed
    QB.QuestMap.PruneOpen(QB.state and QB.state.log)
  end
  -- after a jump in place (a flight, the hearthstone, a boat, a portal, a loading screen) the quest and the spot kept,
  -- and the hand-in chosen, are from where you were: picked afresh from where you landed, as the planner starts afresh
  -- (5.4.4 as first built kept the quest, and off a flight the arrow led back 1,500 yards to its spot)
  if was.jump ~= QB.jumpVer then
    was.jump, was.spot, was.spotQ, was.near = QB.jumpVer, nil, nil, nil
  end
  -- a hand-in in reach first, whatever its value
  local nst, np, nq, nn, nleg = nearHandin(me)
  if nst then
    local changed = cur.near ~= np.npc or cur.qid ~= nq.id or cur.name == nil
    was.near = np.npc
    local n = QB.Data.NPC[np.npc]
    -- (the quests ready there: the arrow's menu skips one)
    for k in pairs(nearIds) do nearIds[k] = nil end
    local log = QB.state and QB.state.log or {}
    for _, row in ipairs(nleg.rows or {}) do
      local e = log[row.q.id]
      if e and e.complete and row.q.turnIdx == np.npc then nearIds[row.q.id] = true end
    end
    cur.near, cur.obj, cur.pending, cur.c, cur.wx, cur.wy = np.npc, false, nil, np.c, np.wx, np.wy
    cur.name = nn > 1 and (n and n[1] or nst.name) or nq.name
    cur.m, cur.x, cur.y = n and n[2], n and n[3], n and n[4]
    cur.qid, cur.stop, cur.ids, cur.quests, cur.what = nq.id, nst.name, nearIds, nn, "to hand in there"
    cur.label = nn > 1 and string.format("Hand in %d quests here", nn) or ("Hand in " .. nq.name .. " here")
    cur.labelShort = "Hand in here: " .. cur.name -- (a long name: the words first, the name cut)
    cur.verb, cur.head, cur.after, cur.afterFor = "Hand in here", nn > 1 and "Hand in here: %s" or "Hand in %s here", "Then on with your route.", nil
    if changed then
      T.ver = T.ver + 1
      if QB.tracing then QB.Trace("target: a hand-in in reach first: %s at %s", nq.name, nst.name) end
    end
    return cur
  end
  if cur.near then was.near = nil; cur.near, cur.label, cur.labelShort = nil, nil, nil; T.ver = T.ver + 1 end
  leftBehind(me)
  local d, leg = stopOne()
  if not (d or leg) then return nothing() end
  local st = d and d.stop or (leg and leg.stop)
  local name = d and d.name or st.name
  local shown, head = placeOf(st, name)
  local c, wx, wy
  if st and st.c and st.wx then
    c, wx, wy = st.c, st.wx, st.wy
  else
    local w = QB.Model.World(d.m, d.x, d.y, wbuf)
    if not w then return nothing() end
    c, wx, wy = w.c, w.wx, w.wy
  end
  -- a new stop: its quests' spots read again, no spot kept. A stop is told as the planner tells it (Model.lua's
  -- indexOf): by its town, else by an NPC it shares with the last one, and its land; its name is only a label, and
  -- neither its name nor its first NPC's place says it is another stop: a quest taken or handed in elsewhere in a town
  -- moves that (the tour from the flight master starts at another NPC), and out of town names the stop after another
  -- NPC (the one nearest the flight master). 5.4.4 as first built took either for a new stop, and the objective went
  -- to another quest with nothing done. The same stop moved or renamed: its spots read again, the quest kept while it
  -- is the stop's (pickSpot)
  if not sameStop(st, name, c) then
    was.name, was.c, was.wx, was.wy, was.spot, was.spotQ, was.gen = name, c, wx, wy, nil, nil, was.gen + 1
    noteStop(st)
  elseif name ~= was.name or wx ~= was.wx or wy ~= was.wy then
    was.name, was.wx, was.wy, was.gen = name, wx, wy, was.gen + 1
    noteStop(st)
  end
  if spotsGen ~= was.gen or spotsAt ~= QB.changed then
    spotsGen, spotsAt = was.gen, QB.changed
    readSpots(idsOf(d, leg))
    pendCache = pendingOf()
  end
  local s = #spots > 0 and pickSpot(me) or nil
  local pend = (not s) and pendCache or nil
  local pendName
  if pend then
    local q = QB.Quest.Get(pend.qid)
    pendName = pend.ent and pend.cat.name or (q and q.name or ("Quest " .. pend.qid))
  end
  local before = cur.name
  cur.ids = idsOf(d, leg) -- (the stop's quests: the arrow's menu skips one)
  local changed = cur.name ~= ((s and s.name) or (pend and pend.ent and pendName) or name) or cur.stop ~= name or cur.obj ~= (s ~= nil or (pend and pend.ent ~= nil) or false)
    or (cur.pending or false) ~= (pend ~= nil) or (s and (s.sp ~= was.spot or s.qid ~= was.spotQ)) or (pend and cur.qid ~= pend.qid)
  was.spot, was.spotQ = s and s.sp or nil, s and s.qid or nil
  cur.stop = name
  cur.pending, cur.labelShort = pend ~= nil, nil
  if changed or not pend then cur.label = nil end
  if s then
    cur.obj, cur.name, cur.c, cur.wx, cur.wy = true, s.name, s.c, s.wx, s.wy
    cur.m, cur.x, cur.y, cur.qid = s.sp.m, s.sp.x * 100, s.sp.y * 100, s.qid
    cur.quests, cur.what, cur.verb, cur.head = nil, nil, "Objective", "Objective: %s"
    if cur.afterFor ~= name then cur.after, cur.afterFor = "Then hand it in at " .. shown .. ".", name end
  elseif pend and pend.ent then
    -- nothing to hand in there yet: the dungeon's entrance, to do the quest there
    cur.obj, cur.name, cur.c, cur.wx, cur.wy = true, pendName, pend.c, pend.wx, pend.wy
    cur.m, cur.x, cur.y, cur.qid = pend.ent.m, pend.ent.x, pend.ent.y, pend.qid
    cur.quests, cur.what, cur.verb, cur.head = pend.n, "to do there", "Enter", "Enter %s"
    if changed then cur.after, cur.afterFor = "Then hand in at " .. shown .. ".", nil end
  elseif pend then
    -- nothing to hand in there yet, and no way in known: the stop as it is, to finish the quest first ("Finish
    -- <quest>" on the arrow; its tooltip's head the same, the quest's name in it: no %s)
    cur.obj, cur.name, cur.c, cur.wx, cur.wy = false, name, c, wx, wy
    cur.m, cur.x, cur.y, cur.qid = d and d.m or st.m, d and d.x or st.x, d and d.y or st.y, pend.qid
    cur.quests, cur.what, cur.verb = pend.n, "to do first, then hand in there", "Finish"
    if changed then
      cur.label = "Finish " .. pendName
      cur.head = cur.label:gsub("%%", "%%%%")
      cur.after, cur.afterFor = pend.cat and (pend.cat.name .. ": entrance not known yet.") or nil, nil
    end
  else
    cur.obj, cur.name, cur.c, cur.wx, cur.wy = false, name, c, wx, wy
    cur.m, cur.x, cur.y = d and d.m or st.m, d and d.x or st.x, d and d.y or st.y
    cur.qid = lowest(d, leg)
    cur.quests = d and d.quests and #d.quests or (leg and leg.rows and #leg.rows) or nil
    cur.what, cur.verb, cur.head, cur.after, cur.afterFor = "to hand in there", nil, nil, nil, nil
    if shown ~= name then cur.head = head end
  end
  cur.shown = shown ~= cur.name and cur.name == name and shown or nil -- (the arrow's words for the stop: Arrow.lua)
  if changed then
    T.ver = T.ver + 1
    if QB.tracing then
      QB.Trace("target: %s -> %s%s%s", tostring(before or "nothing"), cur.obj and "objective of " or "", cur.name,
        me and string.format(" (you at %d: %.0f, %.0f; %.0f yards)", me.c, me.wx, me.wy, math.sqrt((cur.wx - me.wx) ^ 2 + (cur.wy - me.wy) ^ 2)) or "")
    end
  end
  return cur
end

-- the arrow's step (a flight master, a pier, the tram, as Arrow.lua's A.MiniStep gives it) whatever the arrow leads to
-- (its route, a hand-in, a pick-up, a place clicked), and whether it is on the way to this target (the arrow leads to
-- it): the minimap and the Map page show the step's pin either way, as 5.4.3 did, and draw their strokes by it only
-- when it is on the way (5.4.4 as first built showed no step at all while the arrow led to a hand-in or a pick-up).
-- Nil when the arrow is off or there is only the walk left
function T.Step()
  local A = QB.Arrow
  local s = A and A.MiniStep and A.MiniStep()
  if not s then return nil, false end
  return s, cur.name ~= nil and A.t == cur
end

-- QuestBank's data read again (the minimap's Mini.Invalidate): the spots' places
function T.Invalidate() spotsAt = -1 end

----------------------------------------------------------------------------
-- jumps in place: the route is planned again from where you are (Core.lua's signature counts QB.jumpVer)
----------------------------------------------------------------------------
local look, last = {}, {}
local function onTaxi() return yes(UnitOnTaxi, "player") end

-- (the trace says the jump alone: a route from where you stand is planned again for it, and Core.lua's re-plan line
-- says so; a banked route without a run, planned free, is not)
function T.Jump(why)
  QB.jumpVer = (QB.jumpVer or 0) + 1
  if QB.tracing then QB.Trace("a jump in place (%s)", why) end
  QB:MarkDirty()
end

-- A ghost is not counted: releasing your spirit puts you at a graveyard hundreds of yards off, and the run back is no
-- jump either. Where you died is kept, and the look that finds you alive again counts a jump only if you are then more
-- than 300 yards from it (a spirit healer's resurrection, where you stay at the graveyard). 5.4.4 as first built counted
-- the release, planned the route afresh from the graveyard, and its first stop stayed after you ran back to your body
function T.Look()
  local me = QB.API.WorldPosition(nil, look)
  local taxi = onTaxi()
  -- (the Guide turns to your corpse and back on the death events; a client that fires none of them: this look does)
  local G = QB.Guide
  if G and G.dead ~= nil and G.OnEvent and G.dead ~= yes(UnitIsDeadOrGhost, "player") then G.OnEvent(G.dead and "PLAYER_ALIVE" or "PLAYER_DEAD") end
  if yes(UnitIsDeadOrGhost, "player") then
    last.dead, last.taxi = true, taxi
    return
  end
  local why
  if last.dead then
    last.dead = nil
    if me and last.c ~= nil and (me.c ~= last.c or (me.wx - last.wx) ^ 2 + (me.wy - last.wy) ^ 2 > JUMP * JUMP) then
      why = "alive again away from where you died"
    end
  elseif last.taxi and not taxi then
    why = "landed from a flight"
  elseif me and last.c ~= nil and not taxi then
    if me.c ~= last.c then
      why = "another continent"
    elseif (me.wx - last.wx) ^ 2 + (me.wy - last.wy) ^ 2 > JUMP * JUMP then
      why = "300 yards within a second"
    end
  end
  last.taxi = taxi
  if me then last.c, last.wx, last.wy = me.c, me.wx, me.wy end
  if why then T.Jump(why) end
end

----------------------------------------------------------------------------
-- /qb trace: an opt-in diagnostic (off by default) for the owner's next report. A ring of the last 200 lines in
-- QuestBankDB.trace: each re-plan and what changed, the target before and after with where you stood, each change of
-- the minimap's target with its distance, each re-plan of the arrow's way (forced or not, and why), and the golden
-- path's searches a minute. /qb trace on, /qb trace off (clears it), /qb trace print (the last 30)
----------------------------------------------------------------------------
local RING, SHOW = 200, 30
T.RING = RING
local function traceDB()
  QuestBankDB = QuestBankDB or {}
  local t = QuestBankDB.trace
  if type(t) ~= "table" then return nil end
  if type(t.lines) ~= "table" then t.lines = {} end
  return t
end

-- a line, when tracing (callers check QB.tracing first, so nothing is formatted otherwise)
function QB.Trace(fmt, ...)
  local t = traceDB()
  if not (t and t.on) then QB.tracing = false; return end
  local ok, line = pcall(string.format, fmt, ...)
  if not ok then line = tostring(fmt) end
  local lines = t.lines
  lines[#lines + 1] = (date and date("%H:%M:%S") or "") .. " " .. line
  while #lines > RING do table.remove(lines, 1) end
end

function T.TraceCommand(rest, say)
  local want = (rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if want == "on" then
    QuestBankDB.trace = { on = true, lines = {}, since = date and date("%Y-%m-%d %H:%M") or nil, version = QB.version }
    QB.tracing = true
    say("Trace on: QuestBank notes each re-plan of the route, each change of what the arrow, the minimap and the Map page lead to, and each new way the arrow plans, in your saved file (the last 200 lines). /qb trace print shows the last 30; /qb trace off stops and clears it.")
  elseif want == "off" then
    QuestBankDB.trace = nil
    QB.tracing = false
    say("Trace off, and cleared.")
  elseif want == "print" or want == "show" then
    local t = traceDB()
    local lines = t and t.lines or {}
    if #lines == 0 then
      say(t and t.on and "Trace on, nothing noted yet." or "Trace off. /qb trace on starts it.")
      return
    end
    say(string.format("The last %d of %d lines:", math.min(SHOW, #lines), #lines))
    for i = math.max(1, #lines - SHOW + 1), #lines do say(lines[i]) end
  else
    local t = traceDB()
    say((t and t.on) and string.format("Trace on (%d lines). /qb trace print shows the last 30; /qb trace off stops and clears it.", #t.lines)
      or "Trace off. /qb trace on notes why the route and the arrow change, for a report; /qb trace off clears it.")
  end
end

----------------------------------------------------------------------------
-- at login (Core.lua): a look a second for jumps, and the golden path's searches counted a minute while tracing
----------------------------------------------------------------------------
function T:Init()
  if self.frame then return end
  local t = traceDB()
  QB.tracing = t and t.on and true or false
  local f = CreateFrame("Frame")
  self.frame = f
  f.elapsed, f.minute = 0, 0
  f:SetScript("OnUpdate", QB.Safe(function(self, dt)
    self.elapsed = self.elapsed + (dt or 0)
    if self.elapsed < TICK then return end
    self.minute = self.minute + self.elapsed
    self.elapsed = 0
    T.Look()
    if self.minute >= 60 then
      self.minute = 0
      local GP = QB.MiniRoute and QB.MiniRoute.GP
      if GP then
        if QB.tracing then QB.Trace("golden path: %d searches in the last minute", (GP.searches or 0) - (self.searched or 0)) end
        self.searched = GP.searches or 0
      end
    end
  end, "the one target"))
  f:SetScript("OnEvent", QB.Safe(function()
    -- a loading screen: you are somewhere else (the next look starts from there). Not as a ghost (a release that
    -- loads the graveyard): where you died is kept, and the look that finds you alive again decides (T.Look)
    if yes(UnitIsDeadOrGhost, "player") then last.dead = true return end
    last.c, last.taxi = nil, false
    T.Jump("a loading screen")
  end, "the one target"))
  pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")
end
