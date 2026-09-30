-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank model: Forever quest XP and the hand-in route planner.
-- XP: Classic base x the quest's Forever multiplier, the Classic grey penalty, rounded to 10
-- below 1,000 and 50 above (Wowhead's Forever formula).
-- Route: every turn-in NPC becomes a stop (NPCs a few steps apart share one). Travel between
-- stops is the faster of walking straight there or walking to the nearest flight master, taking
-- the faction's flights, boats, zeppelins and the tram, and walking on. The hearthstone is one
-- jump to an inn you bind first. The order comes from a local search (move a stop, reverse a
-- run of stops, move the hearthstone) over several starting tours, spread over frames.
local _, QB = ...
local M = {}
QB.Model = M

local floor, sqrt, huge = math.floor, math.sqrt, math.huge
local D

local RUN = 7          -- yards a second on foot
local DETOUR = 1.3     -- roads against a straight line
local CLUSTER = 90     -- NPCs closer than this share a stop
local TALK = 0.25      -- minutes per NPC: talk and pick rewards
local PER_QUEST = 0.06 -- minutes per extra quest at the same NPC
local HEARTH = 0.5     -- the cast and the loading screen
local MOUNT = 0.625    -- a 60% mount
local CHEAP = 400      -- a stop worth less XP than this goes last
M.MOUNT = MOUNT

local function round(x) return floor(x + 0.5) end
local function roundQuestXp(e)
  local t = e < 1000 and 10 or 50
  return round(e / t) * t
end

----------------------------------------------------------------------------
-- XP
----------------------------------------------------------------------------
local function xpAt(full, qlvl, plvl)
  local m = plvl - qlvl
  local f = full
  if m >= 10 then f = f * 0.1 elseif m >= 6 then f = f * (1 - (m - 5) * 0.2) end
  return roundQuestXp(f)
end

local function raw(q)
  if q.liveFull then return q.liveFull end
  return round((q.base or 0) * (q.mult or 1))
end
M.Raw = raw

function M.XpAt(q, plvl) return xpAt(raw(q), q.lvl, plvl) end

function M.Pct(qlvl, plvl)
  local m = plvl - qlvl
  if m >= 10 then return 10 elseif m >= 6 then return 100 - (m - 5) * 20 end
  return 100
end

function M.Full(q) return roundQuestXp(raw(q)) end
-- the Wowhead number alone, to compare with the game's
function M.Listed(q) return roundQuestXp(round((q.base or 0) * (q.mult or 1))) end

function M.Frac(level, xp)
  if level >= QB.CAP then return QB.CAP end
  return level + xp / QB.Data.TO_NEXT[level]
end

----------------------------------------------------------------------------
-- travel
----------------------------------------------------------------------------
local B64
local KIND = { f = "flight", b = "boat", t = "tram", z = "zeppelin", p = "portal", w = "foot" }

function M.HubTravel(fac, a, b)
  local d = QB.Data.DIST[fac]
  if not B64 then
    B64 = {}
    local s = QB.Data.ALPHA
    for i = 1, #s do B64[s:byte(i)] = i - 1 end
  end
  local i = (a - 1) * d.n + b
  local f1, f2 = d.f:byte(2 * i - 1, 2 * i)
  local w1, w2 = d.w:byte(2 * i - 1, 2 * i)
  return (B64[f1] * 64 + B64[f2]) / 10, (B64[w1] * 64 + B64[w2]) / 10, KIND[d.k:sub(i, i)] or "flight"
end

local function yards(a, b)
  local dx, dy = a.wx - b.wx, a.wy - b.wy
  return sqrt(dx * dx + dy * dy)
end

-- minutes from one place to another (places: {c, wx, wy, hub, walk}) and the main way there
function M.Between(a, b, fac, mf)
  if a == b then return 0, "foot" end
  local best, kind = huge, "foot"
  if a.c == b.c then best = yards(a, b) * DETOUR / RUN / 60 * mf end
  if a.hub > 0 and b.hub > 0 then
    local via, k = nil, "foot"
    if a.hub == b.hub then
      via = (a.walk + b.walk) * mf
    else
      local f, w
      f, w, k = M.HubTravel(fac, a.hub, b.hub)
      via = f + (a.walk + w + b.walk) * mf
    end
    if via < best then best, kind = via, k end
  end
  return best, kind
end

-- world position of a map point: {c, wx, wy}
function M.World(mapID, x, y)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x / 100, y / 100))
  if not ok or not cont or not pos then return nil end
  local wx, wy = pos.x, pos.y
  if pos.GetXY then wx, wy = pos:GetXY() end
  if cont ~= 0 and cont ~= 1 then return nil end
  return { c = cont, wx = wx, wy = wy }
end

-- a place tied to the nearest flight master of the faction
function M.Place(fac, c, wx, wy)
  local best, bi = huge, 0
  for i, h in ipairs(QB.Data.HUB[fac]) do
    if h[2] == c then
      local dx, dy = h[3] - wx, h[4] - wy
      local d = dx * dx + dy * dy
      if d < best then best, bi = d, i end
    end
  end
  return { c = c, wx = wx, wy = wy, hub = bi, walk = bi > 0 and sqrt(best) * DETOUR / RUN / 60 or 0 }
end

local function npcPlace(i, fac)
  local n = QB.Data.NPC[i]
  if not n or n[5] < 0 then return nil end
  local hub, walk = n[8], n[9]
  if fac == "H" then hub, walk = n[10], n[11] end
  if not hub or hub == 0 then return nil end
  return { c = n[5], wx = n[6], wy = n[7], hub = hub, walk = walk, npc = i }
end
M.NpcPlace = npcPlace

----------------------------------------------------------------------------
-- stops
----------------------------------------------------------------------------
-- is this NPC in the flight master's town (one stop for the whole town)?
local function inTown(n, place, fac)
  if n[12] then return false end
  local town = D.HUB[fac][place.hub][1]
  local zone = D.MAPNAME[n[2]] or ""
  return (zone ~= "" and (zone:find(town, 1, true) or town:find(zone, 1, true))) or place.walk <= 1.2
end

-- entries -> stops (a town, or NPCs close together) and the entries no stop can hold
local function buildStops(entries, fac)
  local stops, unplaced = {}, {}
  for _, e in ipairs(entries) do
    local q = e.q
    local p = q.turnIdx and q.turnIdx > 0 and npcPlace(q.turnIdx, fac)
    if not p then
      unplaced[#unplaced + 1] = e
    else
      local n = D.NPC[p.npc]
      local town = inTown(n, p, fac) and p.hub or nil
      local home
      for _, s in ipairs(stops) do
        if town and s.town == town then home = s break end
        if not town and not s.town and s.c == p.c then
          for _, o in ipairs(s.places) do
            if yards(o, p) <= CLUSTER then home = s break end
          end
        end
        if home then break end
      end
      if not home then
        home = { c = p.c, wx = p.wx, wy = p.wy, hub = p.hub, walk = p.walk, town = town, places = {}, npcs = {}, rows = {}, seen = {} }
        stops[#stops + 1] = home
      end
      if not home.seen[p.npc] then
        home.seen[p.npc] = true
        home.places[#home.places + 1] = p
        home.npcs[#home.npcs + 1] = p.npc
      end
      home.rows[#home.rows + 1] = e
    end
  end
  for _, s in ipairs(stops) do
    -- walk the NPCs nearest-first from the flight master, and stand where you start
    local hub = D.HUB[fac][s.hub]
    local from = { wx = hub[3], wy = hub[4] }
    local left, tour, walkYards = {}, {}, 0
    for i, pl in ipairs(s.places) do left[i] = pl end
    while #left > 0 do
      local bi, bd = 1, math.huge
      for i, pl in ipairs(left) do
        local d = yards(from, pl)
        if d < bd then bi, bd = i, d end
      end
      local pl = table.remove(left, bi)
      if #tour > 0 then walkYards = walkYards + bd end
      tour[#tour + 1] = pl
      from = pl
    end
    local first = tour[1]
    s.wx, s.wy, s.walk = first.wx, first.wy, first.walk
    s.npcs = {}
    for i, pl in ipairs(tour) do s.npcs[i] = pl.npc end
    s.inner = walkYards * DETOUR / RUN / 60
    s.work = TALK * #s.npcs + PER_QUEST * (#s.rows - #s.npcs)
    local n = D.NPC[s.npcs[1]]
    s.name = s.town and hub[1] or (n[12] or string.format("%s (%.0f, %.0f)", D.MAPNAME[n[2]] or "", n[3], n[4]))
    s.m, s.x, s.y = n[2], n[3], n[4]
    table.sort(s.rows, function(a, b)
      if a.q.lvl ~= b.q.lvl then return a.q.lvl < b.q.lvl end
      return a.q.id < b.q.id
    end)
  end
  return stops, unplaced
end

----------------------------------------------------------------------------
-- the problem, in plain numbers so one evaluation is cheap
----------------------------------------------------------------------------
local function problem(entries, opts)
  D = QB.Data
  local fac = opts.fac or "A"
  local mf = opts.mounted and MOUNT or 1
  local stops, unplaced = buildStops(entries, fac)
  local n = #stops
  local P = { stops = stops, unplaced = unplaced, n = n, fac = fac, mf = mf, level = opts.level, xp = opts.xp,
              bonus = opts.bonus, goal = opts.goal or "hour", C = {}, K = {}, start = {}, startKind = {}, hearth = {},
              inn = {}, work = {}, rowFull = {}, rowLvl = {}, rowAfter = {}, rowId = {} }
  for i = 1, n do
    local a = stops[i]
    P.C[i], P.K[i] = {}, {}
    for j = 1, n do P.C[i][j], P.K[i][j] = M.Between(a, stops[j], fac, mf) end
    P.work[i] = a.work + a.inner * mf
    local full, lvl, after, ids = {}, {}, {}, {}
    for k, e in ipairs(a.rows) do
      full[k] = raw(e.q)
      lvl[k] = e.q.lvl
      after[k] = e.after or false
      ids[k] = e.q.id
      if e.after then P.hasAfter = true end
    end
    P.rowFull[i], P.rowLvl[i], P.rowAfter[i], P.rowId[i] = full, lvl, after, ids
  end
  -- a stop worth next to nothing waits until everything worth the trip is handed in
  P.cheap = {}
  for i = 1, n do
    local worth = 0
    for r = 1, #P.rowFull[i] do worth = worth + xpAt(P.rowFull[i][r], P.rowLvl[i][r], opts.level) end
    P.cheap[i] = worth < CHEAP
  end
  -- where the run starts: free (log out at the first stop) or from where you stand
  local here = opts.start and M.Place(fac, opts.start.c, opts.start.wx, opts.start.wy)
  if here and here.hub == 0 then here = nil end
  P.here = here
  for i = 1, n do
    if here then
      P.start[i], P.startKind[i] = M.Between(here, stops[i], fac, mf)
    else
      P.start[i], P.startKind[i] = 0, "start"
    end
  end
  -- the hearthstone lands at the inn nearest the stop it jumps to
  local hubs = D.HUB[fac]
  for i = 1, n do
    local s = stops[i]
    local best, inn = huge, 0
    for h = 1, #hubs do
      if hubs[h][5] == 1 then
        local c
        if h == s.hub then
          c = s.walk * mf
        else
          local f, w = M.HubTravel(fac, h, s.hub)
          c = f + (w + s.walk) * mf
        end
        if c < best then best, inn = c, h end
      end
    end
    P.hearth[i], P.inn[i] = HEARTH + best, inn
  end
  P.canHearth = not opts.noHearth and n > 1
  return P
end

-- order: stop indices, 0 for the hearthstone. Returns level at 60 min, level at the end, minutes.
local function evaluate(P, order, keep)
  local T, CAP = D.TO_NEXT, QB.CAP
  local level, xp = P.level, P.xp
  local t, total = 0, 0
  local at60 = level >= CAP and CAP or level + xp / T[level]
  local prev, hearthNext = nil, false
  local cheapSeen, outOfOrder = false, false
  local handed = P.hasAfter and {} or nil
  local bonus = P.bonus
  local legs = keep and {} or nil
  for k = 1, #order do
    local s = order[k]
    if s == 0 then
      hearthNext = prev ~= nil or P.here ~= nil
    else
      local travel, kind
      if hearthNext then
        travel, kind = P.hearth[s], "hearth"
        hearthNext = false
      elseif not prev then
        travel, kind = P.start[s], P.startKind[s]
      else
        travel, kind = P.C[prev][s], P.K[prev][s]
      end
      t = t + travel + P.work[s]
      if P.cheap[s] then cheapSeen = true elseif cheapSeen then outOfOrder = true end
      local arrive = keep and (level >= CAP and CAP or level + xp / T[level])
      local rows = keep and {} or nil
      local full, lvl, after = P.rowFull[s], P.rowLvl[s], P.rowAfter[s]
      for r = 1, #full do
        local a = after[r]
        if not a or (handed and handed[a]) then
          local m = level - lvl[r]
          local f = full[r]
          if m >= 10 then f = f * 0.1 elseif m >= 6 then f = f * (1 - (m - 5) * 0.2) end
          local tt = f < 1000 and 10 or 50
          local x = floor(f / tt + 0.5) * tt
          if bonus then x = floor(x * 1.03 + 0.5) end
          if rows then rows[#rows + 1] = { e = P.stops[s].rows[r], q = P.stops[s].rows[r].q, xp = x, pct = M.Pct(lvl[r], level), plvl = level } end
          total = total + x
          if level < CAP then
            xp = xp + x
            while level < CAP and xp >= T[level] do xp = xp - T[level]; level = level + 1 end
          end
          if handed then handed[P.rowId[s][r]] = true end
        elseif rows then
          rows[#rows + 1] = { e = P.stops[s].rows[r], q = P.stops[s].rows[r].q, xp = 0, pct = 0, plvl = level, blocked = true }
        end
      end
      local fr = level >= CAP and CAP or level + xp / T[level]
      if t <= 60 then at60 = fr end
      if legs then
        legs[#legs + 1] = { stop = P.stops[s], travel = travel, kind = kind, t = t, arrive = arrive, leave = fr,
                            rows = rows, late = t > 60, inn = kind == "hearth" and P.inn[s] or nil }
      end
      prev = s
    end
  end
  local final = level >= CAP and CAP or level + xp / T[level]
  if outOfOrder then return at60 - 100, final - 100, t, total, legs end
  return at60, final, t, total, legs
end

local function better(P, a60, af, at, b60, bf, bt)
  if not b60 then return true end
  if P.goal == "hour" then
    if a60 > b60 + 1e-6 then return true elseif a60 < b60 - 1e-6 then return false end
  end
  if af > bf + 1e-6 then return true elseif af < bf - 1e-6 then return false end
  return at < bt - 1e-6
end

----------------------------------------------------------------------------
-- search
----------------------------------------------------------------------------
M.SLICE = 6 -- milliseconds a frame while planning in the background
local function clock()
  if debugprofilestop then return debugprofilestop() end
  return os.clock() * 1000
end
local function step()
  if M.async and clock() - M.sliceStart > M.SLICE then coroutine.yield() end
end

local function copy(t)
  local c = {}
  for i = 1, #t do c[i] = t[i] end
  return c
end

local function nearestTour(P, first, pool)
  local order, used = { first }, { [first] = true }
  local cur = first
  for _ = 2, #pool do
    local best, bj = huge, nil
    for _, j in ipairs(pool) do
      if not used[j] and P.C[cur][j] < best then best, bj = P.C[cur][j], j end
    end
    order[#order + 1] = bj
    used[bj] = true
    cur = bj
  end
  return order
end

local function appendCheap(P, tour)
  local used = {}
  for _, s in ipairs(tour) do used[s] = true end
  local cur = tour[#tour]
  while true do
    local best, bj = huge, nil
    for j = 1, P.n do
      if P.cheap[j] and not used[j] then
        local c = cur and cur ~= 0 and P.C[cur][j] or 0
        if c < best then best, bj = c, j end
      end
    end
    if not bj then break end
    tour[#tour + 1] = bj
    used[bj] = true
    cur = bj
  end
  return tour
end

local function seeds(P)
  local n, out = P.n, {}
  local all = {}
  for i = 1, n do if not P.cheap[i] then all[#all + 1] = i end end
  if #all == 0 then
    for i = 1, n do all[i] = i end
  end
  local firsts = all
  if P.here then
    firsts = copy(all)
    table.sort(firsts, function(a, b) return P.start[a] < P.start[b] end)
    for i = #firsts, 5, -1 do firsts[i] = nil end
  end
  for _, f in ipairs(firsts) do out[#out + 1] = appendCheap(P, nearestTour(P, f, all)) end
  if P.canHearth then
    -- one continent, the hearthstone, then the other
    local byCont, groups = {}, {}
    for _, i in ipairs(all) do
      local c = P.stops[i].c
      if not byCont[c] then byCont[c] = {}; groups[#groups + 1] = byCont[c] end
      table.insert(byCont[c], i)
    end
    if #groups == 2 then
      for _, pair in ipairs({ { groups[1], groups[2] }, { groups[2], groups[1] } }) do
        local a, b = pair[1], pair[2]
        local bestTail, bestT
        for _, g in ipairs(b) do
          local tail = nearestTour(P, g, b)
          local tt = P.hearth[g]
          for k = 2, #tail do tt = tt + P.C[tail[k - 1]][tail[k]] end
          if not bestT or tt < bestT then bestT, bestTail = tt, tail end
        end
        for _, f in ipairs(a) do
          local tour = nearestTour(P, f, a)
          tour[#tour + 1] = 0
          for _, s in ipairs(bestTail) do tour[#tour + 1] = s end
          out[#out + 1] = appendCheap(P, tour)
        end
      end
    end
  end
  return out
end

-- first-improvement local search: move one element, reverse a run, add or drop the hearthstone
local function improve(P, order, score, budget)
  local b60, bf, bt = score[1], score[2], score[3]
  local evals = 0
  local improved = true
  local function try(cand)
    local a60, af, at = evaluate(P, cand)
    evals = evals + 1
    step()
    if better(P, a60, af, at, b60, bf, bt) then
      order, b60, bf, bt = cand, a60, af, at
      return true
    end
  end
  while improved and evals < budget do
    improved = false
    local len = #order
    for i = 1, len do
      for j = 1, len do
        if i ~= j then
          local cand = copy(order)
          table.insert(cand, j, table.remove(cand, i))
          if try(cand) then improved = true break end
        end
      end
      if improved or evals >= budget then break end
    end
    if not improved and evals < budget then
      for i = 1, len - 1 do
        for j = i + 1, len do
          local cand = copy(order)
          local lo, hi = i, j
          while lo < hi do cand[lo], cand[hi] = cand[hi], cand[lo]; lo, hi = lo + 1, hi - 1 end
          if try(cand) then improved = true break end
        end
        if improved or evals >= budget then break end
      end
    end
    if not improved and P.canHearth and evals < budget then
      local has
      for k = 1, #order do if order[k] == 0 then has = k end end
      if has then
        local cand = copy(order)
        table.remove(cand, has)
        improved = try(cand) or false
      else
        for k = 1, #order do
          local cand = copy(order)
          table.insert(cand, k, 0)
          if try(cand) then improved = true break end
        end
      end
    end
  end
  return order, { b60, bf, bt }, evals
end

-- the last route as a seed: its stops in the same order, the hearthstone where it was, new stops after
-- the old ones and before the cheap tail. Without it a fresh search can land on a worse order than the
-- one it had (adding Ratchet once cost 0.2 levels in the first hour).
local function carried(P, prev)
  if not (prev and prev.legs and #prev.legs > 0) then return nil end
  local byKey = {}
  for i, s in ipairs(P.stops) do
    if s.town then byKey["t" .. s.town] = i end
    for _, npc in ipairs(s.npcs) do byKey["n" .. npc] = byKey["n" .. npc] or i end
  end
  local main, tail, used = {}, {}, {}
  for _, l in ipairs(prev.legs) do
    local st = l.stop
    local i = st and st.town and byKey["t" .. st.town]
    if st and not i then
      for _, npc in ipairs(st.npcs or {}) do i = byKey["n" .. npc]; if i then break end end
    end
    if i and not used[i] then
      used[i] = true
      if P.cheap[i] then
        tail[#tail + 1] = i
      else
        if l.kind == "hearth" then main[#main + 1] = 0 end
        main[#main + 1] = i
      end
    end
  end
  if #main + #tail == 0 then return nil end
  for i = 1, P.n do
    if not used[i] then
      if P.cheap[i] then tail[#tail + 1] = i else main[#main + 1] = i end
    end
  end
  for _, i in ipairs(tail) do main[#main + 1] = i end
  return main
end

----------------------------------------------------------------------------
-- plan: entries = { {q=, st=, after=parentId}, ... }
-- opts = { level, xp, mounted, bonus, goal ("hour" | "route"), fac, start = {c, wx, wy}, noHearth }
-- prev: the route planned last time, to start from
----------------------------------------------------------------------------
function M.Plan(entries, opts, prev)
  D = QB.Data
  local P = problem(entries, opts)
  local startFrac = M.Frac(opts.level, opts.xp)
  local route = { legs = {}, t = 0, xp = 0, level = startFrac, at60 = startFrac, count = 0, byQuest = {},
                  unplaced = P.unplaced, fac = P.fac, mounted = opts.mounted, fromHere = P.here ~= nil, goal = P.goal }
  if P.n == 0 then return route end

  local scored = {}
  local all = seeds(P)
  local warm = carried(P, prev)
  if warm then all[#all + 1] = warm end
  for _, s in ipairs(all) do
    local a60, af, at = evaluate(P, s)
    scored[#scored + 1] = { order = s, score = { a60, af, at } }
    step()
  end
  table.sort(scored, function(a, b) return better(P, a.score[1], a.score[2], a.score[3], b.score[1], b.score[2], b.score[3]) end)
  local best
  local budget = 1000 + 15 * P.n * P.n  -- the search settles long before this (checked on the harness banks)
  for i = 1, math.min(3, #scored) do
    local order, score, used = improve(P, copy(scored[i].order), scored[i].score, budget)
    budget = budget - used
    if not best or better(P, score[1], score[2], score[3], best.score[1], best.score[2], best.score[3]) then
      best = { order = order, score = score }
    end
    if budget <= 0 then break end
  end

  local at60, final, t, total, legs = evaluate(P, best.order, true)
  route.legs, route.t, route.xp, route.level, route.at60 = legs, t, total, final, at60
  for _, l in ipairs(legs) do
    route.count = route.count + #l.rows
    for _, row in ipairs(l.rows) do route.byQuest[row.q.id] = row.xp end
    if l.kind == "hearth" then route.bind = { hub = l.inn, town = D.HUB[P.fac][l.inn][1], before = l.stop.name } end
    if l.late and not route.lateFrom then route.lateFrom = l end
  end
  route.first = legs[1] and legs[1].stop
  return route
end

----------------------------------------------------------------------------
-- planning in the background: a few milliseconds a frame
----------------------------------------------------------------------------
local runner
function M.Async(fn, done)
  runner = runner or CreateFrame("Frame")
  runner.co, runner.done = coroutine.create(fn), done
  runner:SetScript("OnUpdate", function(self)
    M.async, M.sliceStart = true, clock()
    local ok, err = coroutine.resume(self.co)
    M.async = false
    if not ok then
      self:SetScript("OnUpdate", nil)
      if QUESTBANK_DEV then error(err, 0) end
      QB.Err.Record(tostring(err), debugstack and debugstack(self.co) or "", "route planner")
    elseif coroutine.status(self.co) == "dead" then
      self:SetScript("OnUpdate", nil)
      if self.done then self.done() end
    end
  end)
end

function M.Busy() return runner ~= nil and runner:GetScript("OnUpdate") ~= nil end

-- drop a job that is no longer wanted
function M.Cancel()
  if runner then runner:SetScript("OnUpdate", nil); runner.co, runner.done = nil, nil end
  M.async = false
end

-- finish the background job now (the first open of the window, and tests)
function M.Finish()
  if not M.Busy() then return end
  local co, done = runner.co, runner.done
  runner:SetScript("OnUpdate", nil)
  M.async = false
  while coroutine.status(co) ~= "dead" do
    local ok, err = coroutine.resume(co)
    if not ok then error(err) end
  end
  if done then done() end
end
