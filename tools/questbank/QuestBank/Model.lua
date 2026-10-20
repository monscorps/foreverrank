-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank model: Forever quest XP and the hand-in route planner.
-- XP: Classic base x the quest's Forever multiplier, the Classic grey penalty, rounded to 10
-- below 1,000 and 50 above (Wowhead's Forever formula).
-- Route: every turn-in NPC becomes a stop (NPCs a few steps apart share one). Travel between
-- stops is the faster of walking straight there or walking to the nearest flight master, taking
-- the faction's flights, boats, zeppelins and the tram, and walking on. The hearthstone is one
-- jump to an inn you bind first. The order comes from a local search (move a stop, reverse a
-- run of stops, move the hearthstone) over several starting tours, spread over frames.
-- Once this character's flight paths are read and some are not known, the flights between flight masters are only
-- those it knows (Travel.lua's router, as the arrow goes), so the plan, the arrow and the minutes agree.
-- A new plan keeps the last one's first stop unless it is clearly better (5%, QuestTrail's margin): what the arrow, the
-- minimap and the Map page lead to (Target.lua) changes on what you do, not on a near tie.
local _, QB = ...
if QB.dormant then return end
local M = {}
QB.Model = M

local floor, sqrt, huge = math.floor, math.sqrt, math.huge
local D

local RUN = 7          -- yards a second on foot: the pace the tables' walking minutes were built at (travel.py)
local DETOUR = 1.3     -- roads against a straight line
local CLUSTER = 90     -- NPCs closer than this share a stop
local TALK = 0.25      -- minutes per NPC: talk and pick rewards
local PER_QUEST = 0.06 -- minutes per extra quest at the same NPC
local HEARTH = 0.5     -- the cast and the loading screen
local MOUNT = 0.625    -- a 60% mount, until this character's own is measured
local TAKEOFF = 0.25   -- minutes a flight's takeoff takes before the air (travel.py's TAKEOFF)
local CHEAP = 400      -- a stop worth less XP than this goes last, unless it is in reach or on the way (below)
local REACH = 60       -- yards: a stop whose NPC stands this near where you plan from is handed in first
local PASS = 1         -- minutes: a cheap stop that costs no more of a detour than this is handed in as you pass
M.CHEAP, M.REACH, M.PASS = CHEAP, REACH, PASS
M.MOUNT, M.RUN, M.DETOUR, M.TAKEOFF = MOUNT, RUN, DETOUR, TAKEOFF

-- this character's pace: yards a second on foot and the mounted factor (minutes mounted against on foot), measured
-- by QB.Measure when it has enough samples, the tables' guesses (7 and a 60% mount) until then. The third return says
-- what was measured, for /qb legacy
function M.Speed()
  local foot, ride = nil, nil
  if QB.Measure and QB.Measure.Speeds then foot, ride = QB.Measure.Speeds() end
  local run = foot or RUN
  local mount = ride and (run / ride) or MOUNT
  local what = foot and ride and "measured on foot and mounted" or foot and "measured on foot" or ride and "measured mounted" or nil
  return run, mount, what
end

-- the factor on the tables' walking minutes (built at RUN on foot): mounted or not, at this character's own pace
function M.Factor(mounted)
  local run, mount = M.Speed()
  return (mounted and mount or 1) * RUN / run
end

local function round(x) return floor(x + 0.5) end

-- planning in the background (M.Async, below) yields at these points once its slice of the frame is used
M.SLICE = 6 -- milliseconds a frame while planning in the background
local function clock()
  if debugprofilestop then return debugprofilestop() end
  return os.clock() * 1000
end
local function step()
  if M.async and clock() - M.sliceStart > M.SLICE then coroutine.yield() end
end

-- the game's own rounding of quest XP (the server's RoundXPValue): to 5 up to 100, to 10 up to 500, to 25 up to
-- 1,000, to 50 above. Hand-ins on 2026-10-02 showed it: 590 paid 600, 870 paid 875, 4,935 paid 4,950.
local function roundQuestXp(e)
  e = floor(e)
  if e <= 100 then return floor((e + 2) / 5) * 5
  elseif e <= 500 then return floor((e + 5) / 10) * 10
  elseif e <= 1000 then return floor((e + 12) / 25) * 25 end
  return floor((e + 25) / 50) * 50
end
M.RoundXp = roundQuestXp

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

function M.XpAt(q, plvl)
  -- the quest log's own number is exact for the level you are now (grey or not)
  if q.logXp and QB.state and plvl == QB.state.level then return q.logXp end
  return xpAt(raw(q), q.lvl, plvl)
end

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
  local fixed, kind = (B64[f1] * 64 + B64[f2]) / 10, KIND[d.k:sub(i, i)] or "flight"
  -- a flight's minutes with Frequent Flier (a boat's, the tram's and a portal's are the game's own)
  if kind == "flight" and QB.Legacy then fixed = QB.Legacy.FlightMinutes(fixed) end
  return fixed, (B64[w1] * 64 + B64[w2]) / 10, kind
end

local function yards(a, b)
  local dx, dy = a.wx - b.wx, a.wy - b.wy
  return sqrt(dx * dx + dy * dy)
end

-- the flight paths this character can't take: true once the client said which it knows and one with flights is not
-- among them (Travel.lua). Until then every flight counts, as it always did
local function partial(fac)
  local TV = QB.Travel
  return TV and TV.Partial and TV.Partial(fac) or false
end

-- minutes from one flight master to another (D.HUB indices, not the same), walking at mf, and the main way: the tables'
-- whole network (D.DIST, travel.py's), or with flight paths not known, only those you know (Travel.lua's router)
local function hubTrip(fac, a, b, mf)
  if partial(fac) then return QB.Travel.HubMinutes(fac, a, b, mf) end
  local f, w, kind = M.HubTravel(fac, a, b)
  return f + w * mf, kind
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
      via, k = hubTrip(fac, a.hub, b.hub, mf)
      via = via + (a.walk + b.walk) * mf
    end
    if via < best then best, kind = via, k end
  end
  return best, kind
end

-- An open map off the two continents (Zephras Isle, map 2991 under its zone map 2521): a zone map (or a continent's)
-- whose world is no instance. The client places a point there as on a continent, by that map's own id and yards, and
-- Data.lua gives its NPCs the same (gen_data.py, OPEN_MAPS); no flight master stands there, so the route, the arrow and
-- the minutes walk there as on one land. A dungeon's map (and a battleground's, an orphan) still places nothing: inside
-- an instance the rule is as it was. Before 5.4.4 nothing off the two continents was placed, and the isle had no
-- arrow, minimap pins, minutes or route. Asked of the client once a map (again while it doesn't answer)
local openMap = {}
local function isOpen(mapID)
  local v = openMap[mapID]
  if v ~= nil then return v end
  if not (C_Map and C_Map.GetMapInfo) then return false end
  local ok, info = pcall(C_Map.GetMapInfo, mapID)
  info = ok and QB.Plain(info) or nil
  local kind = type(info) == "table" and QB.Plain(info.mapType) or nil
  if type(kind) ~= "number" then return false end
  local E = Enum and Enum.UIMapType
  v = kind == ((E and E.Zone) or 3) or kind == ((E and E.Continent) or 2)
  openMap[mapID] = v
  return v
end

-- a land off the two continents (a place's c, as M.World gives it): no flight master, walked on alone
function M.Off(c) return type(c) == "number" and c > 1 end

-- world position of a map point: {c, wx, wy} (into the table into when given)
function M.World(mapID, x, y, into)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x / 100, y / 100))
  if not ok or not cont or not pos then return nil end
  cont = QB.Plain(cont)
  if type(cont) ~= "number" then return nil end
  local wx, wy = pos.x, pos.y
  if pos.GetXY then wx, wy = pos:GetXY() end
  if cont ~= 0 and cont ~= 1 and not (cont > 1 and isOpen(mapID)) then return nil end
  if into then into.c, into.wx, into.wy = cont, wx, wy; return into end
  return { c = cont, wx = wx, wy = wy }
end

-- the other way: a world position (yards on continent c) as x and y fractions of a map, or nil off it (the Map page
-- draws the arrow's step with it)
function M.MapPos(c, wx, wy, mapID)
  if not (C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
  local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, c, CreateVector2D(wx, wy), mapID)
  if not ok or type(pos) ~= "table" then return nil end
  local x, y = pos.x, pos.y
  if pos.GetXY then x, y = pos:GetXY() end
  x, y = QB.Plain(x), QB.Plain(y)
  if type(x) ~= "number" or type(y) ~= "number" or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  return x, y
end

-- a place tied to the nearest flight master of the faction; with flight paths not known, the nearest you can fly from
-- on the same land (walking north out of Southshore, Chillwind Camp's was nearest long before you knew it). A land
-- where you can fly from none (Darnassus with only Rut'theran Village known, a continent before its first flight path)
-- takes the nearest on the continent all the same, as 5.4.3 did: the planner goes on from there by the flights you know
-- (Travel.lua's router walks you to them), so the route still starts from you (5.4.4 as first built found none there,
-- and the route, the minutes on the cards and Here had no start)
function M.Place(fac, c, wx, wy)
  local best, bi, any, ai = huge, 0, huge, 0
  local TV = QB.Travel
  local land = partial(fac) and TV.Land(c, wx, wy)
  for i, h in ipairs(QB.Data.HUB[fac]) do
    if h[2] == c then
      local dx, dy = h[3] - wx, h[4] - wy
      local d = dx * dx + dy * dy
      if d < any then any, ai = d, i end
      if land and d < best and TV.Door(fac, i, land) then best, bi = d, i end
    end
  end
  if bi == 0 then best, bi = any, ai end
  return { c = c, wx = wx, wy = wy, hub = bi, walk = bi > 0 and sqrt(best) * DETOUR / RUN / 60 or 0 }
end

local function npcPlace(i, fac)
  local n = QB.Data.NPC[i]
  if not n or n[5] < 0 then return nil end
  local hub, walk = n[8], n[9]
  if fac == "H" then hub, walk = n[10], n[11] end
  if not hub or hub == 0 then
    -- on an open map off the two continents (Zephras Isle): no flight master, walked to on its own land
    if not M.Off(n[5]) then return nil end
    hub, walk = 0, 0
  end
  return { c = n[5], wx = n[6], wy = n[7], hub = hub, walk = walk, npc = i }
end
M.NpcPlace = npcPlace

----------------------------------------------------------------------------
-- stops
----------------------------------------------------------------------------
-- is this NPC in the flight master's town (one stop for the whole town)? (Off the two continents there is none)
local function inTown(n, place, fac)
  if n[12] or place.hub == 0 then return false end
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
    -- walk the NPCs nearest-first from the flight master (off the two continents, from the first), and stand where
    -- you start
    local hub = s.hub > 0 and D.HUB[fac][s.hub] or nil
    local from = hub and { wx = hub[3], wy = hub[4] } or s.places[1]
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
-- a quest held and not done whose doing the route cannot lead to: a dungeon's with no objective spot in the world
-- (its objectives are inside; Target.lua leads to the entrance when the catalog has one). Its hand-in waits on a
-- dungeon run: it pays nothing in the plan (the time to level, Guide.lua) and counts no hand-in, and a stop with
-- nothing else is cheap and never "passed" on the way: it waits behind every real hand-in. (6.0.0 counted its XP as a
-- hand-in's and put the owner's Ironforge stop first, in reach, with Old Ironforge Incursion at 0/1.) Only a quest in
-- your log: the planner's own cases hand it entries of their own
local function pendingRow(e)
  local q = e.q
  local log = QB.state and QB.state.log
  local le = log and log[q.id]
  if not le or le.complete then return false end
  local cat = q.cat
  return (cat and cat.dungeon and not (D.SPOT and D.SPOT[q.id])) and true or false
end

local function problem(entries, opts)
  D = QB.Data
  local fac = opts.fac or "A"
  local mf = M.Factor(opts.mounted)
  local stops, unplaced = buildStops(entries, fac)
  -- a stop with nothing to hand in yet (every row pendingRow) is no hand-in stop: left out while any other stop
  -- stands, its entries in P.waiting (the Guide's Do steps, the Route page's "After a dungeon run"); with no other
  -- stop it stays, so the arrow has a target (the dungeon's entrance, or "Finish <quest>": Target.lua)
  local waiting, anyReal, stopPend = {}, false, {}
  for i, st in ipairs(stops) do
    local all = true
    for _, e in ipairs(st.rows) do if not pendingRow(e) then all = false break end end
    stopPend[i] = all
    if not all then anyReal = true end
  end
  if anyReal then
    local kept = {}
    for i, st in ipairs(stops) do
      if stopPend[i] then for _, e in ipairs(st.rows) do waiting[#waiting + 1] = e end else kept[#kept + 1] = st end
    end
    stops = kept
  end
  local n = #stops
  local P = { stops = stops, unplaced = unplaced, waiting = waiting, n = n, fac = fac, mf = mf, level = opts.level, xp = opts.xp,
              goal = opts.goal or "hour", C = {}, K = {}, start = {}, startKind = {}, hearth = {},
              inn = {}, work = {}, rowFull = {}, rowLvl = {}, rowAfter = {}, rowId = {}, rowPend = {}, pending = {} }
  for i = 1, n do
    local a = stops[i]
    P.C[i], P.K[i] = {}, {}
    for j = 1, n do P.C[i][j], P.K[i][j] = M.Between(a, stops[j], fac, mf) end
    step() -- (the flights you know: a flight master's minutes to all the others, worked out the first time asked)
    P.work[i] = a.work + a.inner * mf
    local full, lvl, after, ids, pend, allPend = {}, {}, {}, {}, {}, true
    for k, e in ipairs(a.rows) do
      full[k] = raw(e.q)
      lvl[k] = e.q.lvl
      after[k] = e.after or false
      ids[k] = e.q.id
      pend[k] = pendingRow(e)
      if not pend[k] then allPend = false end
      if e.after then P.hasAfter = true end
    end
    P.rowFull[i], P.rowLvl[i], P.rowAfter[i], P.rowId[i], P.rowPend[i] = full, lvl, after, ids, pend
    P.pending[i] = allPend and #a.rows > 0
  end
  -- a stop worth next to nothing waits until everything worth the trip is handed in (a quest held and not done pays
  -- nothing yet: pendingRow)
  P.cheap = {}
  for i = 1, n do
    local worth = 0
    for r = 1, #P.rowFull[i] do if not P.rowPend[i][r] then worth = worth + xpAt(P.rowFull[i][r], P.rowLvl[i][r], opts.level) end end
    P.cheap[i] = worth < CHEAP * QB.Scale(opts.level)
  end
  -- where the run starts: free (log out at the first stop) or from where you stand
  local here = opts.start and M.Place(fac, opts.start.c, opts.start.wx, opts.start.wy)
  if here and here.hub == 0 and not M.Off(here.c) then here = nil end
  P.here = here
  -- a stop in reach of where you stand (one of its NPCs within REACH yards, with a quest ready to hand in to that NPC)
  -- is handed in now, whatever its value: never cheap, and first (5.4.4: a level-21 mage a few yards from a hand-in worth
  -- little was sent to Booty Bay first; the low-value rule is for stops that cost a trip). Only a quest ready now, as
  -- the arrow's "Hand in X here" (Target.lua): 5.4.4 as first built put any stop within 60 yards first, its quests done
  -- or not, and a re-plan made beside an unfinished quest's NPC changed the objective to that quest. None in the air or
  -- as a ghost (opts.noReach): nothing is handed in there
  P.near = {}
  if here and not opts.noReach then
    local sc, sx, sy = opts.start.c, opts.start.wx, opts.start.wy
    for i = 1, n do
      for _, p in ipairs(stops[i].places) do
        if p.c == sc and (p.wx - sx) ^ 2 + (p.wy - sy) ^ 2 <= REACH * REACH then
          for _, e in ipairs(stops[i].rows) do
            if e.q.turnIdx == p.npc and e.st and e.st.code == "banked" then P.near[i], P.cheap[i], P.hasNear = true, false, true break end
          end
        end
      end
    end
  end
  for i = 1, n do
    if here then
      P.start[i], P.startKind[i] = M.Between(here, stops[i], fac, mf)
    else
      P.start[i], P.startKind[i] = 0, "start"
    end
  end
  -- the hearthstone lands at the inn nearest the stop it jumps to (none off the two continents)
  local hubs = D.HUB[fac]
  for i = 1, n do
    local s = stops[i]
    local best, inn = huge, 0
    for h = 1, s.hub > 0 and #hubs or 0 do
      if hubs[h][5] == 1 then
        local c
        if h == s.hub then
          c = s.walk * mf
        else
          c = hubTrip(fac, h, s.hub, mf) + s.walk * mf
        end
        if c < best then best, inn = c, h end
      end
    end
    step()
    P.hearth[i], P.inn[i] = HEARTH + best, inn
  end
  P.canHearth = not opts.noHearth and n > 1
  if P.hasAfter then P.handed, P.gen = {}, 0 end
  return P
end

-- A leg with no way known (to or from an open map off the two continents: the planner knows no boat or portal to
-- Zephras Isle) is no minutes: it counts GAP in the search's minutes, so an order crosses as few times as it can, and
-- what comes after it is past the first hour; the minutes shown leave it out (its kind "none": "No known way there")
local GAP = 10000

-- order: stop indices, 0 for the hearthstone. Returns level at 60 min, level at the end, minutes (the search's, with
-- GAP a leg with no known way), XP, the legs when keep, and the minutes as shown.
-- The quests handed in so far (for a follow-up handed you by another hand-in) are marked in one table per plan with
-- the evaluation's number, not in a new table each time: a plan evaluates thousands of orders (5.4.2: that table made
-- about 11 MB of garbage a re-plan)
local function evaluate(P, order, keep)
  local T, CAP = D.TO_NEXT, QB.CAP
  local level, xp = P.level, P.xp
  local t, total, gaps = 0, 0, 0
  local at60 = level >= CAP and CAP or level + xp / T[level]
  local prev, hearthNext = nil, false
  local cheapSeen, outOfOrder, otherSeen = false, false, false
  local handed, gen = P.handed, nil
  if handed then gen = P.gen + 1; P.gen = gen end
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
      if travel == huge then gaps, travel, kind = gaps + 1, 0, "none" end
      t = t + travel + P.work[s]
      -- a stop in reach of you comes before every other
      if P.near[s] then
        if otherSeen then outOfOrder = true end
      else
        otherSeen = true
      end
      -- a cheap stop goes after the rest, unless a route from where you stand passes it: under PASS minutes of detour
      -- between the stops either side of it (from you, when it is the first). (A banked route, planned free, keeps
      -- them last)
      if P.cheap[s] then
        local nxt = order[k + 1]
        local passing = false
        if P.here and nxt and nxt ~= 0 and kind ~= "hearth" and kind ~= "none" and not P.pending[s] then
          local direct = prev and P.C[prev][nxt] or P.start[nxt]
          passing = travel + P.C[s][nxt] - direct < PASS
        end
        if not passing then cheapSeen = true end
      elseif cheapSeen then outOfOrder = true end
      local arrive = keep and (level >= CAP and CAP or level + xp / T[level])
      local rows = keep and {} or nil
      local full, lvl, after, pend = P.rowFull[s], P.rowLvl[s], P.rowAfter[s], P.rowPend[s]
      for r = 1, #full do
        local a = after[r]
        if pend[r] then
          -- (held and not done, a dungeon's: nothing yet; its row stands for the hand-in to come)
          if rows then rows[#rows + 1] = { e = P.stops[s].rows[r], q = P.stops[s].rows[r].q, xp = 0, pct = 0, plvl = level, pending = true } end
        elseif not a or (handed and handed[a] == gen) then
          local m = level - lvl[r]
          local f = full[r]
          if m >= 10 then f = f * 0.1 elseif m >= 6 then f = f * (1 - (m - 5) * 0.2) end
          local x = roundQuestXp(f)
          if rows then rows[#rows + 1] = { e = P.stops[s].rows[r], q = P.stops[s].rows[r].q, xp = x, pct = M.Pct(lvl[r], level), plvl = level } end
          total = total + x
          if level < CAP then
            xp = xp + x
            while level < CAP and xp >= T[level] do xp = xp - T[level]; level = level + 1 end
          end
          if handed then handed[P.rowId[s][r]] = gen end
        elseif rows then
          rows[#rows + 1] = { e = P.stops[s].rows[r], q = P.stops[s].rows[r].q, xp = 0, pct = 0, plvl = level, blocked = true }
        end
      end
      local fr = level >= CAP and CAP or level + xp / T[level]
      if t <= 60 and gaps == 0 then at60 = fr end
      if legs then
        legs[#legs + 1] = { stop = P.stops[s], travel = travel, kind = kind, t = t, arrive = arrive, leave = fr,
                            rows = rows, late = t > 60 or gaps > 0, inn = kind == "hearth" and P.inn[s] or nil }
      end
      prev = s
    end
  end
  local final = level >= CAP and CAP or level + xp / T[level]
  local score = t + gaps * GAP
  if outOfOrder then return at60 - 100, final - 100, score, total, legs, t end
  return at60, final, score, total, legs, t
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
local function copy(t)
  local c = {}
  for i = 1, #t do c[i] = t[i] end
  return c
end
-- t's elements into c (a scratch array), c cut to t's length
local function copyInto(c, t)
  local n = #t
  for i = 1, n do c[i] = t[i] end
  for i = #c, n + 1, -1 do c[i] = nil end
  return c
end

local function nearestTour(P, first, pool)
  local order, used = { first }, { [first] = true }
  local cur = first
  for _ = 2, #pool do
    local best, bj = huge, nil
    for _, j in ipairs(pool) do
      if not used[j] and (not bj or P.C[cur][j] < best) then best, bj = P.C[cur][j], j end
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
        if not bj or c < best then best, bj = c, j end
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

-- an order's first stop (0 is the hearthstone, not a stop)
local function firstOf(order)
  for k = 1, #order do if order[k] ~= 0 then return order[k] end end
end
-- does an order lead with stop pin: its first stop, or, for a stop not in reach, its first after the stops in reach
-- (those go first whatever is kept: P.near)
local function leads(P, order, pin)
  local near = P.near[pin]
  for k = 1, #order do
    local s = order[k]
    if s ~= 0 and (near or not P.near[s]) then return s == pin end
  end
  return false
end
-- an order's first stop past those in reach (the stop a plan keeps: route.lead), else its first
local function leadOf(P, order)
  for k = 1, #order do
    local s = order[k]
    if s ~= 0 and not P.near[s] then return s end
  end
  return firstOf(order)
end

-- first-improvement local search: move one element, reverse a run, add or drop the hearthstone. Each candidate is
-- written into one spare array, which becomes the order when it wins (the order before it the spare): two arrays a
-- search, not one for every candidate. With pin, only orders that lead with that stop (leads)
local function improve(P, order, score, budget, pin)
  local b60, bf, bt = score[1], score[2], score[3]
  local evals = 0
  local improved = true
  local spare = {}
  local function try(cand)
    if pin and not leads(P, cand, pin) then return false end
    local a60, af, at = evaluate(P, cand)
    evals = evals + 1
    step()
    if better(P, a60, af, at, b60, bf, bt) then
      order, spare, b60, bf, bt = cand, order, a60, af, at
      return true
    end
  end
  while improved and evals < budget do
    improved = false
    local len = #order
    for i = 1, len do
      for j = 1, len do
        if i ~= j then
          local cand = copyInto(spare, order)
          table.insert(cand, j, table.remove(cand, i))
          if try(cand) then improved = true break end
        end
      end
      if improved or evals >= budget then break end
    end
    if not improved and evals < budget then
      for i = 1, len - 1 do
        for j = i + 1, len do
          local cand = copyInto(spare, order)
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
        local cand = copyInto(spare, order)
        table.remove(cand, has)
        improved = try(cand) or false
      else
        for k = 1, #order do
          local cand = copyInto(spare, order)
          table.insert(cand, k, 0)
          if try(cand) then improved = true break end
        end
      end
    end
  end
  return order, { b60, bf, bt }, evals
end

-- this problem's stops by their town and their NPCs, to find a stop of the last route again
local function stopKeys(P)
  local byKey = {}
  for i, s in ipairs(P.stops) do
    if s.town then byKey["t" .. s.town] = i end
    for _, npc in ipairs(s.npcs) do byKey["n" .. npc] = byKey["n" .. npc] or i end
  end
  return byKey
end
local function indexOf(byKey, st)
  local i = st and st.town and byKey["t" .. st.town]
  if st and not i then
    for _, npc in ipairs(st.npcs or {}) do i = byKey["n" .. npc]; if i then break end end
  end
  return i
end

-- the last route as a seed: its stops in the same order, the hearthstone where it was, new stops after
-- the old ones and before the cheap tail. Without it a fresh search can land on a worse order than the
-- one it had (adding Ratchet once cost 0.2 levels in the first hour).
local function carried(P, prev, byKey)
  if not (prev and prev.legs and #prev.legs > 0) then return nil end
  local main, tail, used = {}, {}, {}
  for _, l in ipairs(prev.legs) do
    local i = indexOf(byKey, l.stop)
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

-- The first stop kept (QuestTrail keeps its target unless another plan is 5% better): a plan that starts somewhere else
-- than the last one did must be clearly better than the best that starts where the last one did, in the planner's own
-- terms: the levels gained (the first hour's, then the run's), then the minutes (5% and half a minute fewer). Before
-- 5.4.4 a tie to a millionth decided, and walking north out of Southshore the next stop swapped back and forth
local SWITCH, SWITCH_MIN = 0.05, 0.5
M.SWITCH = SWITCH
local function clearly(P, a, b, start)
  for k = P.goal == "hour" and 1 or 2, 2 do
    local ga, gb = a[k] - start, b[k] - start
    if ga > gb + math.max(SWITCH * math.abs(gb), 1e-6) then return true end
    if ga < gb - 1e-6 then return false end
  end
  local at, bt = a[3], b[3]
  return bt - at > SWITCH * bt and bt - at >= SWITCH_MIN
end

----------------------------------------------------------------------------
-- plan: entries = { {q=, st=, after=parentId}, ... }
-- opts = { level, xp, mounted, goal ("hour" | "route"), fac, start = {c, wx, wy}, noHearth, jump (the jumps in place so
-- far: Core.lua's QB.jumpVer, for a route from where you stand), noReach (in the air or a ghost: no stop in reach) }
-- prev: the route planned last time, to start from; its first stop is kept unless another is clearly better (route.held:
-- the first stop kept against a free plan that scored better; route.alt: the plan that lost, { first, t, level };
-- route.lead: the first stop past those in reach, the one the next plan keeps; route.firstNear: its first stop is there
-- only for being in reach)
----------------------------------------------------------------------------
function M.Plan(entries, opts, prev)
  D = QB.Data
  local P = problem(entries, opts)
  local startFrac = M.Frac(opts.level, opts.xp)
  local route = { legs = {}, t = 0, xp = 0, level = startFrac, at60 = startFrac, count = 0, byQuest = {},
                  unplaced = P.unplaced, waiting = P.waiting, fac = P.fac, mounted = opts.mounted, fromHere = P.here ~= nil, goal = P.goal, jump = opts.jump }
  if P.n == 0 then return route end

  local scored = {}
  local all = seeds(P)
  local byKey = prev and stopKeys(P)
  local warm = byKey and carried(P, prev, byKey)
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

  -- the last route's first stop, kept unless the best above is clearly better: on a route from where you stand (the
  -- stop you walk to; a banked route starts where you log out, and only a change of the bank moves its first stop). A
  -- stop that is gone (its quests handed in, abandoned or failed, or no longer placed) is no stop of this problem, and
  -- the best above stands
  -- A stop in reach with a quest ready (P.near) goes first, and the stop kept comes next: while the last route's first
  -- stop was put first only for being in reach (prev.firstNear: in reach still, walked on past without handing in, or
  -- handed in with another of its quests still to do), or is gone (handed in), its lead is kept (its first stop past
  -- those in reach, route.lead), so a hand-in on the way neither drops the stop kept nor leaves the next one to a near
  -- tie once it is handed in (5.4.4 as first built dropped it, and after the hand-in the first stop was the one it had
  -- been kept against), and a stop in reach left behind takes its place in the route as any other (5.4.4 as first built
  -- kept it first from then on, behind you, for having been in reach once). A first stop kept for its own sake is kept,
  -- in reach or walked off from, as before.
  -- Walked away from (that stop still a stop, no longer in reach: Target.lua's leftBehind plans again for it) and
  -- kept first all the same, going back being clearly quicker (a hand-in 100 yards behind you against a trip back
  -- later), it is marked (route.firstLeft) and kept as any first stop from then on, and Target.lua plans again as you
  -- walk on, each REACH_KEEP yards further, until going back is no longer clearly quicker: then the stop walked away
  -- from gives way. (5.4.4 as first built made that one plan and no other until something else changed, and the stop
  -- stayed behind you as stop 1 for good; forcing the lead instead costs minutes: 100 yards out of Southshore with
  -- its hand-in ready, the lead first is 10 minutes against 7)
  local keep, left
  if P.here and byKey then
    local first = prev.legs[1] and indexOf(byKey, prev.legs[1].stop)
    local lead = prev.lead and indexOf(byKey, prev.lead)
    keep = first
    if lead and (not first or prev.firstNear) then keep = lead end
    left = (prev.firstNear or prev.firstLeft) and first and not P.near[first] and first or nil
  end
  -- (planned again after a jump in place: a flight, the hearthstone, a boat, a portal. You are somewhere else, and the
  -- stop kept from where you were may lie back where you came from: the best from here stands. 5.4.4 as first built
  -- kept it, and off a flight to Menethil Harbor the route flew you back to Southshore first. A last route planned with
  -- no place to start from (in a dungeon, where the client gives none) counts as before the jump out: it kept its free
  -- first stop, and out of the door the route sent you back to it)
  if keep and opts.jump and prev.jump ~= opts.jump then keep, left = nil, nil end
  if keep and not leads(P, best.order, keep) then
    -- the best order with the kept stop moved to the front (after the stops in reach), or the last route carried on,
    -- whichever is better; then searched with that stop leading
    local cand = copy(best.order)
    for k = #cand, 1, -1 do if cand[k] == keep then table.remove(cand, k) end end
    local at = #cand + 1
    if P.near[keep] then
      at = 1
    else
      for k = 1, #cand do if cand[k] ~= 0 and not P.near[cand[k]] then at = k break end end
    end
    table.insert(cand, at, keep)
    local k60, kf, kt = evaluate(P, cand)
    if warm and leads(P, warm, keep) then
      local w60, wf, wt = evaluate(P, warm)
      if better(P, w60, wf, wt, k60, kf, kt) then cand, k60, kf, kt = copy(warm), w60, wf, wt end
    end
    local order, score = improve(P, cand, { k60, kf, kt }, 1000 + 15 * P.n * P.n, keep)
    local lost
    if clearly(P, best.score, score, startFrac) then
      lost = { first = P.stops[keep].name, t = score[3], level = score[2], at60 = score[1] }
    else
      lost = { first = P.stops[leadOf(P, best.order)].name, t = best.score[3], level = best.score[2], at60 = best.score[1] }
      best = { order = order, score = score }
      route.held = true
    end
    route.alt = lost
  end

  local at60, final, _, total, legs, t = evaluate(P, best.order, true)
  route.legs, route.t, route.xp, route.level, route.at60 = legs, t, total, final, at60
  route.lead = P.stops[leadOf(P, best.order)]
  -- (its first stop put first only for being in reach, ahead of the lead: the next plan keeps the lead, and Target.lua
  -- plans again once you walk away from it without handing in. A plan with no stop kept too, the first of a session
  -- or one after a jump, landing or logging in beside a hand-in: 5.4.4 as first built marked only a plan with a stop
  -- kept, and the hand-in you walked past stayed first, behind you, and was kept for having been first)
  local f = firstOf(best.order)
  -- (a stop kept first after walking away from it, for going back being clearly quicker, back in reach: in reach
  -- again, not kept for its own sake)
  route.firstNear = (f and P.near[f] and (f ~= keep or (prev and prev.firstLeft)) and P.stops[f] ~= route.lead) or nil
  route.firstLeft = (left and f == left) or nil
  if P.here then route.startC, route.startX, route.startY = opts.start.c, opts.start.wx, opts.start.wy end
  for _, l in ipairs(legs) do
    for _, row in ipairs(l.rows) do
      if not row.pending then route.count = route.count + 1 end
      route.byQuest[row.q.id] = row.xp
    end
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
