-- SPDX-License-Identifier: GPL-3.0-or-later
-- Travel: the way to what the arrow points at, step by step, by the ways this character can take. Flights only
-- between flight masters this character knows (the world map's flight points say which, the flight master's own map
-- has the last word; a continent never read counts all of them, as QuestBank always did), the faction's boats,
-- zeppelins, the tram and the Rut'theran portal (D.LINK), walking only on one land (Teldrassil's canopy, Rut'theran at
-- its foot and Sardor Isle are islands: D.LAND), and the hearthstone or Astral Recall when it is in your bags, nearly
-- ready and QuestBank knows where it lands. The router is Dijkstra over the faction's flight masters and docks (D.HUB,
-- D.FLY, D.LINK) with you, the hearth's landing and the target added; TV.Guide turns its plan into what the arrow
-- shows, tick by tick.
--   QuestBankDB.travel[character] (by the character's GUID, "g" and UnitGUID("player"); 5.4.4: by its name and realm
--     before, so a character deleted and made again under the same name inherited what the old one knew, and its data
--     kept no record of whose it was) = { guid, known = { [TaxiNodes id] = "m" the world map | "t" the flight master's map |
--     "n" "New flight path discovered!" | "f" flown | false not known }, readC = { [continent] = time() read },
--     bind = { name, c, wx, wy, src = "bound" | "landed", at },
--     flown = { ["from>to" (TaxiNodes ids)] = { n = flights, secs = seconds in the air, the mean of the last few } }:
--     how long each flight you took really lasted, from the pick (TakeTaxiNode) to landing (UnitOnTaxi off, or
--     PLAYER_CONTROL_GAINED); a flight you flew counts its own seconds, the rest the tables' minutes with Frequent
--     Flier (QB.Legacy) }
--   QuestBankDB.diag.taxi = { cont, zone, open, known, scanBad, bind, at }: how many flight points each read of the
--     client gave, so the uploads show what this client answers
--   QuestBankDB.disc.rides (6.1.1, every character's: a boat sails the same for all) = { ["<kind>:<town>><town>" (D.LINK's
--     ends, the one boarded first)] = { b = where you boarded { c, wx, wy }, l = where you landed, t = seconds on board
--     (the mean of the last few), n = rides, at = time() } }: each boat or zeppelin leg ridden to its far end, or off it
--     through a loading screen. The graph takes the measured time from then on, and a landing more than LAND_YD from
--     the seed's end in that end's place (the Southshore ferry: the client's track turns at Menethil Harbor; the owner
--     says it goes to Darkshore)
-- Only reads: QuestBank never takes a flight or uses the hearthstone for you.
local _, QB = ...
if QB.dormant then return end
local TV = {}
QB.Travel = TV

local D, M = QB.Data, QB.Model
local plain = QB.Plain
local sqrt, floor, huge, max = math.sqrt, math.floor, math.huge, math.max

local BOARD = 0.5       -- minutes a flight, boat or tram costs on top when choosing (the talk, the wait); never shown
local HEARTH_COST = 3   -- minutes charged for spending the hearthstone's hour, except on the route's own hearth
local READY = 90        -- seconds: a hearthstone or Astral Recall this close to ready is a step
local JUMP = 300        -- yards in one look: a summons, a portal, a loading screen
local DRIFT_YD, DRIFT_S = 30, 2 -- moved this far, plan again this often (kept only if clearly better)
local KEEP_TRAVEL = 0.05 -- a way that travels stays so while it saves this share over walking (TV.Route)
local ARRIVE_S = 20     -- seconds after a loading screen in which a new plan travels on at KEEP_TRAVEL's line (replan)
local HEARTH_S = 5      -- seconds between looks at the hearthstone
local NEAR = 60         -- yards: at a flight master
local LEARN_NEAR = 40   -- yards: "Learn this flight path"
local THERE = 15        -- yards: at the target
local TRAM_MAP = 369    -- the Deeprun Tram's instance map (no instance as IsInInstance counts)
local START_R = { fly = 25, boat = 35, zeppelin = 35, tram = 25, portal = 12 }   -- at a step's start
local BOARD_YD = 120    -- yards from the pier: on board past this (a tower's two zeppelins dock 51-60 yd apart)
local END_R = { fly = 60, boat = 80, zeppelin = 80, tram = 60, portal = 60, hearth = 400, recall = 400 }
local KIND = { b = "boat", z = "zeppelin", t = "tram", p = "portal" }
local STRONG = { t = true, n = true, f = true } -- evidence the world map's word never overrides
local CONT_MAP = { [0] = 1415, [1] = 1414 }
local CONT_NAME = { [0] = "Eastern Kingdoms", [1] = "Kalimdor" }
-- each kind of step: its step line, and what to do at its start
local STEP = {
  fly = { "Fly to %s", "Talk to the flight master" }, boat = { "Boat to %s", "Wait for the boat" },
  zeppelin = { "Zeppelin to %s", "Wait for the zeppelin" }, tram = { "Tram to %s", "Take the tram" },
  -- (the portal: the walk-in one between Rut'theran Village and Darnassus, its step "Portal in <here> to <there>": 6.1.1,
  -- "Portal to Darnassus" read as the mage spell Portal: Darnassus)
  portal = { "Portal in %s to %s", "Step into the portal" }, hearth = { "Hearth to %s", "Use your Hearthstone" },
  recall = { "Recall to %s", "Cast Astral Recall" },
}
local SAY = { fly = "flight", boat = "boat", zeppelin = "zeppelin", tram = "tram", portal = "portal", hearth = "hearthstone", recall = "Astral Recall" }

TV.ver = 0                           -- goes up with everything the router counts on: flight paths, the bind, the switches
TV.stats = { routes = 0, maxMs = 0 } -- routes planned this session, the slowest in milliseconds
TV.slots = {}                        -- the open flight master's map: slot -> TaxiNodes id

local function now() return GetTime and GetTime() or 0 end
local function faction() return QB.faction or QB.API.Faction() end
local function class()
  if type(UnitClass) ~= "function" then return nil end
  local ok, _, file = pcall(UnitClass, "player")
  return ok and plain(file) or nil
end
local function yd(c1, x1, y1, c2, x2, y2)
  if c1 ~= c2 then return huge end
  local dx, dy = x1 - x2, y1 - y2
  return sqrt(dx * dx + dy * dy)
end
local function ydTo(me, p) return yd(me.c, me.wx, me.wy, p.c, p.wx, p.wy) end
local WALK -- minutes on foot a yard, at a run
local function walkMin() WALK = WALK or M.DETOUR / M.RUN / 60; return WALK end
-- on a flight now (false when the client won't say)
local function taxiNow()
  if type(UnitOnTaxi) ~= "function" then return false end
  local ok, v = pcall(UnitOnTaxi, "player")
  return ok and plain(v) == true
end

----------------------------------------------------------------------------
-- what QuestBank keeps per character, and what the client said
----------------------------------------------------------------------------
-- this character's key: "g" and its GUID (read once a session), or its name and realm where the client won't say
local guidKey
local function charKey()
  if guidKey then return guidKey end
  if type(UnitGUID) == "function" then
    local ok, g = pcall(UnitGUID, "player")
    g = ok and plain(g) or nil
    if type(g) == "string" and g:find("^Player%-") then guidKey = "g" .. g; return guidKey end
  end
  return QB:CharKey()
end
TV.CharKey = charKey

-- An entry kept by name and realm (before 5.4.4) is taken over by this character once, keeping only what is its own
-- beyond doubt: the flights it timed (flown: seconds in the air, used only between flight masters it knows) and where
-- its hearthstone lands (bind). The flight paths it knew are let go: nothing recorded whose they were, and a character
-- made again under an old name inherited them. The client says again which this character knows (the world map's
-- flight points 3 seconds after login, and every flight master's map you open: TV.Learn, TV.ReadTaxiMap)
local function adopt(all, key)
  local old = all[QB:CharKey()]
  if key == QB:CharKey() or type(old) ~= "table" then return nil end
  all[QB:CharKey()] = nil
  return { flown = type(old.flown) == "table" and old.flown or nil, bind = type(old.bind) == "table" and old.bind or nil }
end
TV.Adopt = adopt

function TV.DB()
  QuestBankDB = QuestBankDB or {}
  local all = type(QuestBankDB.travel) == "table" and QuestBankDB.travel or {}
  QuestBankDB.travel = all
  local key = charKey()
  local t = all[key]
  if type(t) ~= "table" then
    t = adopt(all, key) or {}
    all[key] = t
  end
  if key:sub(1, 1) == "g" then t.guid = key:sub(2) end
  if type(t.known) ~= "table" then t.known = {} end
  if type(t.readC) ~= "table" then t.readC = {} end
  if type(t.flown) ~= "table" then t.flown = {} end
  return t
end

local function diag()
  QuestBankDB = QuestBankDB or {}
  QuestBankDB.diag = type(QuestBankDB.diag) == "table" and QuestBankDB.diag or {}
  local d = type(QuestBankDB.diag.taxi) == "table" and QuestBankDB.diag.taxi or {}
  QuestBankDB.diag.taxi = d
  return d
end

local function build()
  if type(GetBuildInfo) ~= "function" then return "?" end
  local ok, _, b = pcall(GetBuildInfo)
  return ok and plain(b) or "?"
end
-- the world map's word on flight points proved wrong on this build: the flight master's own map said otherwise
local function scanBad() local b = diag().scanBad; return b ~= nil and b == build() end

----------------------------------------------------------------------------
-- the graph: the faction's flight masters (D.HUB, same order), then two docks for each of its rides
----------------------------------------------------------------------------
-- an island's land from D.LAND, else the continent
function TV.Land(c, wx, wy)
  for _, b in ipairs(D.LAND) do
    if b[1] == c and wx >= b[2] and wx <= b[4] and wy >= b[3] and wy <= b[5] then return b[6] end
  end
  return c
end

local function push(list, ...) for i = 1, select("#", ...) do list[#list + 1] = (select(i, ...)) end end

local AT -- D.ALPHA's characters, by byte: 0 to 63
local graphs = {}

-- rides learned (QuestBankDB.disc.rides): the key of D.LINK row li ridden from its end `from` (1 or 2)
local LAND_YD, RIDE_MEAN = 150, 5
TV.LAND_YD = LAND_YD
local function rideKey(li, from)
  local l = D.LINK[li]
  if not l then return nil end
  local a, b = l[from == 1 and 4 or 5], l[from == 1 and 5 or 4]
  return l[2] .. ":" .. tostring(a[7]) .. ">" .. tostring(b[7])
end
TV.RideKey = rideKey
-- the table, kept to the keys of today's D.LINK (a ride of a link the data no longer has goes)
local ridesPruned = false
local function rides()
  local db = QuestBankDB
  if type(db) ~= "table" then return nil end
  if type(db.disc) ~= "table" then db.disc = {} end
  local r = db.disc.rides
  if type(r) ~= "table" then r = {}; db.disc.rides = r end
  if not ridesPruned then
    ridesPruned = true
    local ok = {}
    for li in ipairs(D.LINK) do ok[rideKey(li, 1)], ok[rideKey(li, 2)] = true, true end
    for k in pairs(r) do if not ok[k] then r[k] = nil end end
  end
  return r
end
-- what a ride of row li from end `from` taught, or nil
function TV.RideLearned(li, from)
  local all = rides()
  local e = all and all[rideKey(li, from)]
  return type(e) == "table" and type(e.t) == "number" and e.t > 0 and e or nil
end
-- an end of a ride as the graph has it: the seed's, or the landing you learned when it lies more than LAND_YD away
-- (its town then the nearest flight master's of the faction on that continent)
local function placeEnd(e, r, hubs)
  local l = r and type(r.l) == "table" and r.l
  if not (l and type(l[1]) == "number" and type(l[2]) == "number" and type(l[3]) == "number") then return e[1], e[2], e[3], e[7] end
  if l[1] == e[1] and (l[2] - e[2]) ^ 2 + (l[3] - e[3]) ^ 2 <= LAND_YD * LAND_YD then return e[1], e[2], e[3], e[7] end
  local town, best = e[7], 2000 * 2000
  for _, h in ipairs(hubs) do
    if h[2] == l[1] then
      local d = (h[3] - l[2]) ^ 2 + (h[4] - l[3]) ^ 2
      if d < best then town, best = h[1], d end
    end
  end
  return l[1], l[2], l[3], town
end

function TV.Graph(fac)
  if graphs[fac] then return graphs[fac] end
  if not AT then AT = {}; for i = 1, #D.ALPHA do AT[D.ALPHA:byte(i)] = i - 1 end end
  local hubs = D.HUB[fac]
  local G = { fac = fac, h = #hubs, c = {}, wx = {}, wy = {}, land = {}, taxi = {}, flag = {}, town = {}, kind = {},
              pos = {}, fly = {}, ride = {}, track = {}, byTaxi = {}, W = {}, endOf = {},
              dist = {}, prev = {}, how = {}, via = {}, done = {}, use = {}, path = {} }
  local n = 0
  local function node(c, wx, wy, taxi, flag, town, kind)
    n = n + 1
    G.c[n], G.wx[n], G.wy[n], G.taxi[n], G.flag[n], G.town[n], G.kind[n] = c, wx, wy, taxi, flag, town, kind
    G.land[n], G.pos[n], G.fly[n], G.ride[n] = TV.Land(c, wx, wy), { c = c, wx = wx, wy = wy }, {}, {}
    return n
  end
  for _, h in ipairs(hubs) do
    local i = node(h[2], h[3], h[4], h[6], h[10], h[1], "m")
    if h[6] > 0 then G.byTaxi[h[6]] = i end
  end
  for li, l in ipairs(D.LINK) do
    if l[1]:find(fac, 1, true) then
      -- (what your rides taught: the minutes measured, an end where you landed instead of the seed's)
      local r12, r21 = TV.RideLearned(li, 1), TV.RideLearned(li, 2)
      local c1, x1, y1, t1 = placeEnd(l[4], r21, hubs)
      local c2, x2, y2, t2 = placeEnd(l[5], r12, hubs)
      local a = node(c1, x1, y1, 0, 0, t1, l[2])
      local b = node(c2, x2, y2, 0, 0, t2, l[2])
      G.endOf[a], G.endOf[b] = 1, 2
      push(G.ride[a], b, r12 and r12.t / 60 or l[3], KIND[l[2]], li)
      push(G.ride[b], a, r21 and r21.t / 60 or l[3], KIND[l[2]], li)
      local tr = {}
      for c, x, y in l[6]:gmatch("(%-?%d+),(%-?[%d.]+),(%-?[%d.]+)") do push(tr, tonumber(c), tonumber(x), tonumber(y)) end
      G.track[li] = tr
    end
  end
  G.n = n
  G.flyModel = {}
  for u = 1, G.h do G.flyModel[u] = {} end
  local s = D.FLY[fac]
  for e = 1, #s, 4 do
    local b1, b2, b3, b4 = s:byte(e, e + 3)
    push(G.flyModel[AT[b1] + 1], AT[b2] + 1, (AT[b3] * 64 + AT[b4]) / 10)
  end
  TV.ApplyFlights(G)
  local k = walkMin()
  for u = 1, n do
    for v = 1, n do
      G.W[(u - 1) * n + v] = G.land[u] == G.land[v] and yd(G.c[u], G.wx[u], G.wy[u], G.c[v], G.wx[v], G.wy[v]) * k or false
    end
  end
  graphs[fac] = G
  return G
end

-- the seconds a flight from one flight master to another took you (TV.DB().flown), or nil
local function flownKey(G, a, b)
  local ta, tb = G.taxi[a], G.taxi[b]
  if not (ta and tb and ta > 0 and tb > 0) then return nil end
  return ta .. ">" .. tb
end
function TV.Learned(G, a, b)
  local key = flownKey(G, a, b)
  local e = key and TV.DB().flown[key]
  return type(e) == "table" and type(e.secs) == "number" and e.secs > 0 and e.secs or nil, key
end

-- the graph's flight minutes from the tables' (G.flyModel): a flight you flew counts its own seconds; the rest the
-- tables' minutes with Frequent Flier's faster mount (QB.Legacy.FlightMinutes). A flight you flew in one go that the
-- tables have no edge for (through flight masters you know) becomes an edge of its own. True when a minute moved
local function same(a, b)
  if not b or #a ~= #b then return false end
  for k = 1, #a do if a[k] ~= b[k] then return false end end
  return true
end
function TV.ApplyFlights(G)
  local flown = TV.DB().flown
  local L = QB.Legacy
  local moved = false
  for u = 1, G.h do
    local f, m, has = {}, G.flyModel[u], {}
    for k = 1, #m, 2 do
      local v, model = m[k], m[k + 1]
      local secs = TV.Learned(G, u, v)
      f[k], f[k + 1] = v, secs and secs / 60 or (L and L.FlightMinutes(model) or model)
      has[v] = true
    end
    if G.taxi[u] > 0 then
      for key, e in pairs(flown) do
        local ta, tb = key:match("^(%d+)>(%d+)$")
        if ta and tonumber(ta) == G.taxi[u] and type(e) == "table" and type(e.secs) == "number" and e.secs > 0 then
          local v = G.byTaxi[tonumber(tb)]
          if v and not has[v] then push(f, v, e.secs / 60) end
        end
      end
    end
    if not same(f, G.fly[u]) then moved = true end
    G.fly[u] = f
  end
  return moved
end

-- the flights changed (a flight timed, Frequent Flier's rank read): every graph's again, and the plans with them when
-- some minutes moved (force: the tables' minutes moved, Frequent Flier, which the planner reads without a graph).
-- 5.4.4 as first built planned the route again, and the arrow's way, at every trait event, nothing changed
function TV.Refly(force)
  local moved = force and true or false
  for _, G in pairs(graphs) do if TV.ApplyFlights(G) then moved = true end end
  if moved then TV.ver = TV.ver + 1 end
end

-- the hub of a town on a continent (a flight master's first, where a town has two rows)
local function hubByTown(G, town, c)
  local best
  for i = 1, G.h do
    if G.town[i] == town and (c == nil or G.c[i] == c) and (not best or G.flag[best] ~= 0) then best = i end
  end
  return best
end
-- "Stormwind, Elwynn" -> "Stormwind" (travel.py names the hubs so)
local function townOf(name) return ((name:match("^([^,]+)") or name):gsub(" City$", "")) end

-- the flight master nearest you, within some yards (one with flights: Light's Hope's stands 18 yards from a dead node)
local function nearestMaster(G, me, within)
  local best, bd = nil, within * within
  for i = 1, G.h do
    if (G.flag[i] == 0 or G.flag[i] == 2) and G.c[i] == me.c then
      local dx, dy = G.wx[i] - me.wx, G.wy[i] - me.wy
      if dx * dx + dy * dy <= bd then best, bd = i, dx * dx + dy * dy end
    end
  end
  return best
end

----------------------------------------------------------------------------
-- which flight paths this character knows
----------------------------------------------------------------------------
-- can a flight start or end at graph node i: never at a node without flights (flag 1) or a world-PvP tower (4), at a
-- druids' one (2) only for a druid; then what this character knows. A continent never read counts every flight master
-- only on a client that has not said a word about flight paths this session (TV.tells: an old client without the
-- calls, or the first seconds after login); once it has, an unread continent counts only what it said. 5.4.3 counted
-- every flight master there whatever the client said, and a level-21 mage whose world map named only the six flight
-- paths he had (too few of the continent's for a read) was sent to fly to Sentinel Hill
local function usable(G, i, druid, known, readC)
  local f = G.flag[i]
  if G.kind[i] ~= "m" or f == 1 or f == 4 or (f == 2 and not druid) then return false end
  local k = known[G.taxi[i]]
  if k ~= nil then return k ~= false end
  return not readC[G.c[i]] and not TV.tells
end

-- the client's first word this session on the flight paths (TV.tells). Before it, a continent never read counted every
-- flight master, so a plan made then (at login, a few seconds before the client is asked) may start at a stop reached
-- by flights this character lacks: the next plan starts afresh, as after a jump in place (Target.lua), where 5.4.4 as
-- first built kept that first stop against the plan by the flights it knows. Both continents read already: the plan
-- before it counted the same flights, and nothing starts afresh
local function told()
  local readC = TV.DB().readC
  local unread = not (readC[0] and readC[1])
  TV.tells = true
  if unread and QB.Target and QB.Target.Jump then QB.Target.Jump("the client named your flight paths") end
end

function TV.Usable(fac, i, druid)
  local db = TV.DB()
  if druid == nil then druid = class() == "DRUID" end
  return usable(TV.Graph(fac), i, druid, db.known, db.readC)
end

-- The route planner's flights (Model.lua): which flight masters you can fly from, worked out again when what the router
-- counts on changes (TV.ver). doors[i]: usable; partial: one with flights is not, so the planner goes by the flights
-- you know (TV.HubMinutes) instead of the tables' whole network. Asked for every pair of stops: a few reads
local doors = {}
local function doorsOf(fac)
  local d = doors[fac]
  if d and d.ver == TV.ver then return d end
  local G, db = TV.Graph(fac), TV.DB()
  local druid = class() == "DRUID"
  d = { ver = TV.ver, partial = false }
  for i = 1, G.h do
    d[i] = usable(G, i, druid, db.known, db.readC)
    if G.flag[i] == 0 and not d[i] then d.partial = true end
  end
  doors[fac] = d
  return d
end
function TV.Partial(fac) return doorsOf(fac).partial end
-- a flight master you can fly from, on this land
function TV.Door(fac, i, land) return doorsOf(fac)[i] and TV.Graph(fac).land[i] == land end

-- flight masters the router can use on a continent, of how many, and whether the client ever said which
function TV.Known(fac, c)
  local G, db = TV.Graph(fac), TV.DB()
  local druid = class() == "DRUID"
  local n, total = 0, 0
  for i = 1, G.h do
    if G.flag[i] == 0 and G.c[i] == c then
      total = total + 1
      if usable(G, i, druid, db.known, db.readC) then n = n + 1 end
    end
  end
  return n, total, db.readC[c] ~= nil
end

-- strong evidence for one flight master (the taxi map, the "new flight path" line, a flight); true when it is news
local function mark(G, i, how)
  local id = i and G.taxi[i]
  if not id or id <= 0 then return false end
  local K = TV.DB().known
  if STRONG[K[id]] then return false end
  K[id] = how
  return true
end

local function countKnown(G, K)
  local n = 0
  for i = 1, G.h do if K[G.taxi[i]] then n = n + 1 end end
  return n
end

local function nodesOn(map)
  if not (C_TaxiMap and type(C_TaxiMap.GetTaxiNodesForMap) == "function") then return nil end
  local ok, list = pcall(C_TaxiMap.GetTaxiNodesForMap, map)
  list = ok and plain(list) or nil
  return type(list) == "table" and list or nil
end
-- the game's own word that a map shows flight points at all (the world map's FlightPointDataProvider asks it before
-- it lists them): true or false, nil where the call is missing, errors or hides its answer
local function showsNodes(map)
  if not (C_TaxiMap and type(C_TaxiMap.ShouldMapShowTaxiNodes) == "function") then return nil end
  local ok, v = pcall(C_TaxiMap.ShouldMapShowTaxiNodes, map)
  v = ok and plain(v) or nil
  if type(v) ~= "boolean" then return nil end
  return v
end

-- the world map's flight points, anywhere: each continent's map, then the zone map of every flight master the continent
-- left out (once a map). A secret or missing answer is skipped. Never overrides the taxi map, a flight or the message
function TV.Learn()
  local G, db = TV.Graph(faction()), TV.DB()
  local K = db.known
  local bad = scanBad()
  local got, changed = {}, false
  local function take(list)
    local n = 0
    for _, e in ipairs(list) do
      e = plain(e)
      if type(e) == "table" then
        local id, und = plain(e.nodeID), plain(e.isUndiscovered)
        local i = type(id) == "number" and G.byTaxi[id]
        if i and type(und) == "boolean" then
          n, got[i] = n + 1, true
          local want = not und and "m" or false
          if not (want == "m" and bad) and not STRONG[K[id]] and K[id] ~= want then K[id], changed = want, true end
        end
      end
    end
    return n
  end
  local cont, zone, asked, answered = 0, 0, {}, 0
  for _, map in pairs(CONT_MAP) do
    local list = nodesOn(map)
    if list then
      cont = cont + take(list)
      if showsNodes(map) == true then answered = answered + 1 end
    end
  end
  for i = 1, G.h do
    local m = D.HUB[G.fac][i][7]
    if G.flag[i] == 0 and not got[i] and not asked[m] then
      asked[m] = true
      local list = nodesOn(m)
      if list then zone = zone + take(list) end
    end
  end
  -- the client has said which flight paths this character has: from now on only those count (usable). Forever's world
  -- map lists only the flight paths you found, so a character who has found none gets empty lists: both continents'
  -- maps answering with a list, each saying it shows flight points, is that word too ("none yet"). 5.4.4 as first built
  -- waited for a name, and before your first flight path the plan flew you everywhere. A client without the calls, or
  -- one whose maps say they show none, still says nothing: every flight counts there, as before
  if (cont + zone > 0 or answered == 2) and not TV.tells then told(); changed = true end
  -- a continent is read once the client answered for most of its flight masters (a doubted map reads nothing)
  if not bad then
    for c = 0, 1 do
      local total, said = 0, 0
      for i = 1, G.h do
        if G.flag[i] == 0 and G.c[i] == c then
          total = total + 1
          if got[i] then said = said + 1 end
        end
      end
      if total > 0 and said >= 0.8 * total then
        if not db.readC[c] then changed = true end
        db.readC[c] = time and time() or 0
      end
    end
  end
  local d = diag()
  d.cont, d.zone, d.known, d.at = cont, zone, countKnown(G, K), date and date("%Y-%m-%d") or nil
  if changed then TV.ver = TV.ver + 1 end
end

-- the flight master's own map, as it opens: what it lists is what you know on this continent. Current and Reachable
-- are known, Unreachable stays as it was, a flight master it leaves out is not known. A flight master the world map
-- called known and this map leaves out: the world map is wrong on this build, and its word goes
function TV.ReadTaxiMap()
  TV.taxiOpen, TV.cur = true, nil
  for s in pairs(TV.slots) do TV.slots[s] = nil end
  local G = TV.Graph(faction())
  local me = QB.API.WorldPosition()
  local mapID
  if type(GetTaxiMapID) == "function" then
    local ok, m = pcall(GetTaxiMapID)
    mapID = ok and plain(m) or nil
    if type(mapID) ~= "number" then mapID = nil end
  end
  local c = me and me.c or (mapID == 1463 and 0) or (mapID == 1464 and 1) or nil
  if c == nil then return end
  local listed, known, matched, unmatched = {}, {}, 0, 0
  local list
  if C_TaxiMap and type(C_TaxiMap.GetAllTaxiNodes) == "function" then
    local ok, l = pcall(C_TaxiMap.GetAllTaxiNodes, mapID or (c == 0 and 1463 or 1464))
    l = ok and plain(l) or nil
    if type(l) == "table" and #l > 0 then list = l end
  end
  if list then
    for _, e in ipairs(list) do
      e = plain(e)
      local id, state, slot
      if type(e) == "table" then id, state, slot = plain(e.nodeID), plain(e.state), plain(e.slotIndex) end
      local i = type(id) == "number" and G.byTaxi[id]
      if type(id) == "number" and type(slot) == "number" then TV.slots[slot] = id end
      if i then
        listed[i] = true
        if state == 0 or state == 1 then known[i], matched = true, matched + 1 end
        if state == 0 then TV.cur = i end
      end
    end
  elseif type(NumTaxiNodes) == "function" and type(TaxiNodeGetType) == "function" and type(TaxiNodeName) == "function" then
    -- the old taxi frame's calls, the flight masters by name (enUS; another language matches none and learns nothing)
    local ok, count = pcall(NumTaxiNodes)
    count = ok and plain(count) or 0
    for s = 1, type(count) == "number" and count or 0 do
      local ok1, kind = pcall(TaxiNodeGetType, s)
      local ok2, name = pcall(TaxiNodeName, s)
      kind, name = ok1 and plain(kind) or nil, ok2 and plain(name) or nil
      if type(kind) == "string" and kind ~= "NONE" then
        local i = type(name) == "string" and hubByTown(G, townOf(name), c)
        local can = kind == "CURRENT" or kind == "REACHABLE"
        if i then
          listed[i], TV.slots[s] = true, G.taxi[i]
          if can then known[i], matched = true, matched + 1 end
          if kind == "CURRENT" then TV.cur = i end
        elseif can then
          unmatched = unmatched + 1
        end
      end
    end
  end
  local d = diag()
  d.open = matched
  if matched == 0 and unmatched == 0 then return end -- nothing on it QuestBank can read
  if not TV.tells then told(); TV.ver = TV.ver + 1 end
  -- the flight master you talk to is one you know, whatever the list says of it
  if not TV.cur and me then TV.cur = nearestMaster(G, me, NEAR) end
  if TV.cur then listed[TV.cur], known[TV.cur] = true, true end
  -- a list read in full (by id, or every name matched) is all you know here; else only what it named counts
  local whole = unmatched == 0
  local db = TV.DB()
  local K = db.known
  local changed, wrong = false, false
  for i = 1, G.h do
    if G.flag[i] == 0 and G.c[i] == c then
      local id = G.taxi[i]
      if known[i] then
        if not STRONG[K[id]] then K[id], changed = "t", true end
      elseif not listed[i] and whole then
        if K[id] == "m" then wrong = true end
        if K[id] ~= false then K[id], changed = false, true end
      end
    end
  end
  if wrong then
    -- every character's world-map word goes, and every continent read only by it
    d.scanBad = build()
    for _, ch in pairs(QuestBankDB.travel) do
      if type(ch) == "table" and type(ch.known) == "table" then
        for id, v in pairs(ch.known) do if v == "m" then ch.known[id] = nil end end
        if type(ch.readC) == "table" then
          for rc in pairs(ch.readC) do if not (ch == db and rc == c) then ch.readC[rc] = nil end end
        end
      end
    end
  end
  if whole then
    if not db.readC[c] then changed = true end
    db.readC[c] = time and time() or 0
  end
  d.known = countKnown(G, K)
  if changed or wrong then TV.ver = TV.ver + 1 end
end

-- the fewest minutes in the air from one flight master to another, over the ones you know
local function flightMin(G, a, b)
  local db = TV.DB()
  local druid = class() == "DRUID"
  local dist, done = {}, {}
  for v = 1, G.h do dist[v] = huge end
  dist[a] = 0
  while true do
    local u, du = nil, huge
    for v = 1, G.h do if not done[v] and dist[v] < du then u, du = v, dist[v] end end
    if not u or u == b then break end
    done[u] = true
    local f = G.fly[u]
    for k = 1, #f, 2 do
      local v = f[k]
      if du + f[k + 1] < dist[v] and usable(G, v, druid, db.known, db.readC) then dist[v] = du + f[k + 1] end
    end
  end
  return dist[b] < huge and dist[b] or nil
end

-- you picked a flight on the flight master's map (TakeTaxiNode, hooked): where it goes, from where, and about how long
function TV.OnTakeTaxi(slot)
  slot = plain(slot)
  if type(slot) ~= "number" then return end
  local G = TV.Graph(faction())
  local me = QB.API.WorldPosition()
  local from = TV.cur or (me and nearestMaster(G, me, NEAR))
  local to = TV.slots[slot] and G.byTaxi[TV.slots[slot]]
  if not to and type(TaxiNodeName) == "function" then
    local ok, name = pcall(TaxiNodeName, slot)
    name = ok and plain(name) or nil
    if type(name) == "string" then to = hubByTown(G, townOf(name), from and G.c[from] or (me and me.c)) end
  end
  local news = mark(G, to, "f")
  news = mark(G, from, "f") or news
  if news then TV.ver = TV.ver + 1 end
  local min, key
  if from and to then
    local secs
    secs, key = TV.Learned(G, from, to)
    min = secs and secs / 60 or flightMin(G, from, to)
  end
  TV.flying = { to = to, from = from, at = now(), min = min }
  TV.WatchFlight(from, to, key, min)
end

----------------------------------------------------------------------------
-- the flight timer: how long the flight you picked really takes, from takeoff to landing, whatever the arrow does.
-- Takeoff: UnitOnTaxi on, or PLAYER_CONTROL_LOST; landing: UnitOnTaxi off, or PLAYER_CONTROL_GAINED. A look a second
-- in between. Learned into TV.DB().flown (the mean of the last few), and every graph's minutes follow
----------------------------------------------------------------------------
local watch -- { from, to, key, model (minutes), at (picked), up (took off) }
local MEAN_OF = 5        -- flights a learned edge averages over
local MIN_FLIGHT = 10    -- seconds: shorter was no flight
TV.MEAN_OF = MEAN_OF

local function landed(w, secs)
  watch = nil
  if not w.key or secs < MIN_FLIGHT then return end
  if w.model and secs > max(600, 3 * w.model * 60) then return end -- (a disconnect, a loading screen: not a flight)
  local flown = TV.DB().flown
  local e = flown[w.key]
  if type(e) == "table" and type(e.n) == "number" and type(e.secs) == "number" and e.n > 0 then
    local n = math.min(e.n, MEAN_OF - 1)
    e.secs, e.n = floor((e.secs * n + secs) / (n + 1) + 0.5), n + 1
  else
    flown[w.key] = { n = 1, secs = floor(secs + 0.5) }
  end
  TV.flownLast = { key = w.key, secs = secs, model = w.model }
  TV.Refly()
end

local function flightTick(w)
  if watch ~= w then return end
  local tnow = now()
  local on = taxiNow()
  if not w.up then
    if on then w.up = tnow
    elseif tnow - w.at > 60 then watch = nil; return end -- (never took off: refused, or the map shut)
  elseif not on then
    landed(w, tnow - w.up)
    return
  end
  C_Timer.After(1, QB.Safe(function() flightTick(w) end, "flight timer"))
end

function TV.WatchFlight(from, to, key, model)
  local w = { from = from, to = to, key = key, model = model, at = now() }
  watch = w
  C_Timer.After(1, QB.Safe(function() flightTick(w) end, "flight timer")) -- (a pick after it: this one's ticks stop)
end
-- the flight timer's state, for the tests: nil, "picked" or "up"
function TV.Watching() return watch and (watch.up and "up" or "picked") or nil end

function TV.OnControl(lost)
  local w = watch
  if not w then return end
  local tnow = now()
  if lost then
    if not w.up and (taxiNow() or tnow - w.at <= 10) then w.up = tnow end
  elseif w.up then
    landed(w, tnow - w.up)
  end
end

-- "New flight path discovered!": the flight master you stand at
local function newPath()
  local me = QB.API.WorldPosition()
  local G = TV.Graph(faction())
  if me and mark(G, nearestMaster(G, me, NEAR), "n") then TV.ver = TV.ver + 1 end
end

----------------------------------------------------------------------------
-- the hearthstone: where it lands, and whether it is a step
----------------------------------------------------------------------------
local function norm(s) return (s:lower():gsub("^the ", ""):gsub(" city$", "")) end
local function bindName()
  if type(GetBindLocation) ~= "function" then return nil end
  local ok, name = pcall(GetBindLocation)
  name = ok and plain(name) or nil
  return type(name) == "string" and name ~= "" and name or nil
end

local bindRows -- D.BIND by its normalized town name
-- where the hearthstone lands: the spot QuestBank saw for this bind (you bound there, or landed there), else the inn of
-- the town the game names (D.BIND_ALIAS for an inn's own name, then the town, then the longest name either holds, at
-- least 4 letters and only one). {name, c, wx, wy, src}, or nil and why
function TV.Bind()
  local name = bindName()
  if not name then return nil, "unknown" end
  local b = TV.DB().bind
  if type(b) == "table" and b.name == name and b.c and b.wx and b.wy then return b end
  if not bindRows then
    bindRows = {}
    for _, r in ipairs(D.BIND) do bindRows[norm(r[1])] = r end
  end
  local key = norm(name)
  local row = (D.BIND_ALIAS[key] and bindRows[norm(D.BIND_ALIAS[key])]) or bindRows[key]
  if not row then
    local best, bl, tie = nil, 0, false
    for k, r in pairs(bindRows) do
      local l = math.min(#k, #key)
      if l >= 4 and (key:find(k, 1, true) or k:find(key, 1, true)) then
        if l > bl then best, bl, tie = r, l, false elseif l == bl then tie = true end
      end
    end
    if not tie then row = best end
  end
  if not row then return nil, "unknown" end
  return { name = name, c = row[2], wx = row[3], wy = row[4], src = "town" }
end

-- seconds until Astral Recall is ready, with its cooldown's start and duration; nil when unreadable (secret in a fight)
local function recallLeft()
  if not (C_Spell and type(C_Spell.GetSpellCooldown) == "function") then return nil end
  local ok, cd = pcall(C_Spell.GetSpellCooldown, 556)
  cd = ok and plain(cd) or nil
  if type(cd) ~= "table" then return nil end
  local start, dur = plain(cd.startTime), plain(cd.duration)
  if type(start) ~= "number" or type(dur) ~= "number" then return nil end
  if start == 0 then return 0, 0, 0 end
  return max(0, start + dur - now()), start, dur
end
local function knowsRecall()
  if class() ~= "SHAMAN" or type(IsPlayerSpell) ~= "function" then return false end
  local ok, yes = pcall(IsPlayerSpell, 556)
  return ok and plain(yes) == true
end

-- the hearthstone (or a shaman's Astral Recall, first: its cooldown is a quarter of the stone's) as a step:
-- {kind, c, wx, wy, name, min, penalty, left}, or nil and why not. On the route's arrow only the route's own hearth,
-- free; elsewhere its hour costs HEARTH_COST minutes, so it is never spent to save one. The Crumbling Hearthstone is
-- single-use and never a step
function TV.Hearth(mode)
  if QB:Settings().arrowHearth == false then return nil, "off" end
  local kind, left
  if knowsRecall() then
    left = recallLeft()
    if left and left <= READY then kind = "recall" end
  end
  if not kind then
    if not QB.API.HasHearth() then return nil, "none" end
    left = QB.API.HearthLeft()
    if not (left and left <= READY) then return nil, "cooldown" end
    kind = "hearth"
  end
  local b, why = TV.Bind()
  if not b then return nil, why end
  -- (a continent, or an open map off the two where you landed or bound: Zephras Isle's inn, walked from there)
  if type(b.c) ~= "number" or b.c < 0 then return nil, "unknown" end
  local penalty = HEARTH_COST
  if mode == "route" then
    local r = QB.Target and QB.Target.Route() or QB.routeNow
    local leg = r and r.legs and r.legs[1]
    if not (leg and leg.kind == "hearth") then return nil, "route" end
    penalty = 0
  end
  return { kind = kind, c = b.c, wx = b.wx, wy = b.wy, name = b.name, min = 0.5 + left / 60, penalty = penalty, left = left }
end

local function hearthSig(h) return h and (h.kind .. ":" .. h.name .. ":" .. h.c .. ":" .. floor(h.wx) .. ":" .. floor(h.wy)) or "-" end

-- the hearthstone in a line, for the arrow's tooltip and /qb way; nil with no hearthstone
function TV.HearthLine()
  if not QB.API.HasHearth() then return nil end
  local b = TV.Bind()
  if not b then return "Hearthstone: " .. (QB.NAME or "QuestBank") .. " learns where it goes when you bind or use it" end
  local left = QB.API.HearthLeft()
  if left == nil then return "Hearthstone: " .. b.name end
  if left <= 0 then return "Hearthstone: " .. b.name .. ", ready" end
  return string.format("Hearthstone: %s, ready in %d min", b.name, math.ceil(left / 60))
end

-- after a hearth or a recall: the first place 300 yards on from where you cast it is the bind's own spot. True once landed
local function landed(me)
  local c = TV.cast
  if c.c and me.c == c.c and yd(me.c, me.wx, me.wy, c.c, c.wx, c.wy) <= JUMP then return false end
  if c.c and c.name and c.name == bindName() then
    TV.DB().bind = { name = c.name, c = me.c, wx = me.wx, wy = me.wy, src = "landed", at = time and time() or 0 }
    diag().bind = c.name
    TV.ver = TV.ver + 1
  end
  TV.cast = nil
  return true
end
local function watchLanding(n)
  if not (TV.cast and TV.cast.done) then return end
  local me = QB.API.WorldPosition()
  if me and landed(me) then return end
  if n >= 30 then TV.cast = nil; return end
  C_Timer.After(1, QB.Safe(function() watchLanding(n + 1) end, "hearth landing"))
end

----------------------------------------------------------------------------
-- the router
----------------------------------------------------------------------------
-- what to say and show for each kind of step, by faction (the flight master's fallback art is the faction's mount)
local ICONS = {}
local function icons(fac)
  if ICONS[fac] then return ICONS[fac] end
  local T = D.TEX
  local bird = fac == "H" and T.wyvern or T.gryphon
  local recall
  if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
    local ok, id = pcall(C_Spell.GetSpellTexture, 556)
    recall = ok and plain(id) or nil
  end
  local dungeon = QB.QuestMap and QB.QuestMap.ART.dungeon.file or T.unknown
  local I = {
    fly = { atlas = "flightmaster", file = bird }, flying = { file = bird },
    boat = { atlas = "flightmasterferry", file = T.boat }, zeppelin = { file = T.zeppelin }, tram = { file = T.tram },
    -- (a world portal on the map, the client's atlas "portalpurple": UiTextureAtlasMember 4705; 6.1.1, never the mage's
    -- "mageportalalliance")
    portal = { atlas = "portalpurple", file = T.portal }, hearth = { file = T.hearth },
    recall = { file = type(recall) == "number" and recall or T.hearth },
    there = { atlas = "Waypoint-MapPin-Tracked", file = T.mapPin }, unreachable = { atlas = "Waypoint-MapPin-Untracked", file = T.mapPin },
    ghost = { atlas = "Navigation-Tombstone-Icon", file = T.unknown }, instance = { atlas = "dungeon", file = dungeon },
    learn = { atlas = "taxinode_undiscovered", file = T.taxiGray }, foot = { file = T.foot }, mount = { file = T.mount },
  }
  ICONS[fac] = I
  return I
end
TV.Icons = icons

-- what the router may use: the faction, the walking pace (mounted or not), druid flights, the hearthstone
function TV.Opts(mode)
  local mounted = QB:Mounted() and true or false
  return { fac = faction(), mounted = mounted, mf = M.Factor(mounted), druid = class() == "DRUID", hearth = TV.Hearth(mode), mode = mode }
end

-- Dijkstra (no heap: a few dozen nodes) from `from` to `to`, or to everywhere when `to` is nil. Nodes 1..n are the
-- graph's, then S (you), B (where the hearth lands) and T (the target). Walking joins any two places on one land;
-- a flight joins two flight masters you can use, and costs BOARD unless it carries on a flight; a ride costs BOARD
local function run(G, from, to, o)
  local n = G.n
  local S, B, T = n + 1, n + 2, n + 3
  local dist, prev, how, via, done, use, W = G.dist, G.prev, G.how, G.via, G.done, G.use, G.W
  local db = TV.DB()
  for v = 1, n do use[v] = usable(G, v, o.druid, db.known, db.readC) end
  for v = 1, T do dist[v], prev[v], how[v], via[v], done[v] = huge, nil, nil, nil, false end
  dist[S] = 0
  local k, mf, h = walkMin() * o.mf, o.mf, o.hearth
  local lS = TV.Land(from.c, from.wx, from.wy)
  local lB = h and TV.Land(h.c, h.wx, h.wy)
  local lT = to and TV.Land(to.c, to.wx, to.wy)
  local last = to and T or B
  while true do
    local u, du = nil, huge
    for v = 1, last do if not done[v] and dist[v] < du then u, du = v, dist[v] end end
    if not u or u == T then break end
    done[u] = true
    local function relax(v, d, kind, li)
      if d < dist[v] then dist[v], prev[v], how[v], via[v] = d, u, kind, li end
    end
    if u == S or u == B then
      local p, lp = from, lS
      if u == B then p, lp = h, lB end
      for v = 1, n do
        if G.land[v] == lp then relax(v, du + yd(p.c, p.wx, p.wy, G.c[v], G.wx[v], G.wy[v]) * k, "walk") end
      end
      if to and lT == lp then relax(T, du + ydTo(p, to) * k, "walk") end
      if u == S and h then relax(B, du + h.min + h.penalty, h.kind) end
    else
      local base = (u - 1) * n
      for v = 1, n do
        local w = W[base + v]
        if w then relax(v, du + w * mf, "walk") end
      end
      if to and G.land[u] == lT then relax(T, du + yd(G.c[u], G.wx[u], G.wy[u], to.c, to.wx, to.wy) * k, "walk") end
      if use[u] then
        local f, board = G.fly[u], how[u] == "fly" and 0 or BOARD
        for i = 1, #f, 2 do
          if use[f[i]] then relax(f[i], du + f[i + 1] + board, "fly") end
        end
      end
      local r = G.ride[u]
      for i = 1, #r, 4 do relax(r[i], du + r[i + 1] + BOARD, r[i + 2], r[i + 3]) end
    end
  end
  return lS, lT
end

local function spot(c, wx, wy, r) return { c = c, wx = wx, wy = wy, r = r } end

-- the path back from the target, as steps: walking is each step's approach, flights in a row are one flight (the game
-- flies on through flight masters you know), and the last step is always the walk to the target. Minutes as shown:
-- without BOARD and the hearth's charge
local function legsOf(G, to, o)
  local n = G.n
  local B, T = n + 2, n + 3
  local dist, prev, how, via, path = G.dist, G.prev, G.how, G.via, G.path
  local I, h = icons(G.fac), o.hearth
  local k, v = 0, T
  while v do k = k + 1; path[k] = v; v = prev[v] end
  local legs, walked = {}, 0
  for i = k - 1, 1, -1 do
    local u, w = path[i + 1], path[i]
    local kind, d = how[w], dist[w] - dist[u]
    local last = legs[#legs]
    if kind == "walk" then
      walked = walked + d
    elseif kind == "fly" and last and last.kind == "fly" and last.to == u and walked == 0 then
      last.to, last.min, last.town = w, last.min + d, G.town[w]
      last.finish = spot(G.c[w], G.wx[w], G.wy[w], END_R.fly)
    else
      local leg = { kind = kind, walk = walked }
      if w == B then
        leg.town, leg.min, leg.finish = h.name, d - h.penalty, spot(h.c, h.wx, h.wy, END_R[kind])
      else
        leg.from, leg.to, leg.town, leg.min, leg.link = u, w, G.town[w], d - BOARD, via[w]
        leg.start = spot(G.c[u], G.wx[u], G.wy[u], START_R[kind])
        leg.finish = spot(G.c[w], G.wx[w], G.wy[w], END_R[kind])
      end
      legs[#legs + 1] = leg
      walked = 0
    end
  end
  legs[#legs + 1] = { kind = "walk", walk = walked, min = 0, finish = spot(to.c, to.wx, to.wy, THERE) }
  -- what each step says and shows, and the minutes left after it
  local rest = 0
  for i = #legs, 1, -1 do
    local leg = legs[i]
    leg.rest = rest
    rest = rest + leg.walk + leg.min
    local say = STEP[leg.kind]
    if say then
      local step = leg.kind == "portal" and string.format(say[1], G.town[leg.from] or "?", leg.town) or string.format(say[1], leg.town)
      leg.step, leg.short, leg.wait, leg.icon = step, leg.town, say[2], I[leg.kind]
      if leg.kind == "fly" then leg.pick, leg.going = "Pick " .. leg.town, "Flying to " .. leg.town end
      if leg.kind == "tram" then leg.going = "On the tram to " .. leg.town end
    end
  end
  return legs, rest
end

-- the way from one place to another ({c, wx, wy}, the target with its name): plan = {key, ver, min, legs}, or nil and
-- "unreachable". On one land travel has to save a fair bit (15% and a minute) over walking straight there, or the plan
-- is that walk; a way that travels already (o.keepTravel, the guide's plan for the same target) stays so while it saves
-- 5%: between the two the guide keeps what it had, so standing near the cut-off never flips walk and flight.
-- leg = {kind = "fly"|"boat"|"zeppelin"|"tram"|"portal"|"hearth"|"recall"|"walk", from, to (graph
-- nodes), start = {c, wx, wy, r} (nil for the hearth and the last walk), finish = {c, wx, wy, r}, town, walk (minutes
-- on foot to its start), min (minutes of the step), rest (minutes after it), link (D.LINK row of a ride), step, short,
-- wait, pick, going (its texts), icon}
function TV.Route(from, to, o)
  local t0 = debugprofilestop and debugprofilestop()
  o = o or TV.Opts()
  local G = TV.Graph(o.fac)
  local lS, lT = run(G, from, to, o)
  local cost = G.dist[G.n + 3]
  local plan
  if cost < huge then
    local direct = lS == lT and ydTo(from, to) * walkMin() * o.mf
    local legs, total
    local travel = direct and (o.keepTravel and cost <= (1 - KEEP_TRAVEL) * direct or cost <= 0.85 * direct and direct - cost >= 1)
    if direct and not travel then
      legs, total = { { kind = "walk", walk = direct, min = 0, rest = 0, finish = spot(to.c, to.wx, to.wy, THERE) } }, direct
    else
      legs, total = legsOf(G, to, o)
    end
    plan = { key = string.format("%s:%d:%d:%d", tostring(to.name or ""), to.c, floor(to.wx / 5), floor(to.wy / 5)),
             ver = TV.ver, min = total, legs = legs }
  end
  TV.stats.routes = TV.stats.routes + 1
  if t0 then TV.stats.maxMs = max(TV.stats.maxMs, debugprofilestop() - t0) end
  if not plan then return nil, "unreachable" end
  return plan
end

-- minutes from where you stand to every flight master, dock and the hearth's landing, kept a second (on a 20-yard
-- square, while nothing the router counts on changed): for choosing the nearest of many targets by time (TV.Via)
local reach = { d = {} }
function TV.Reach(from, o)
  o = o or TV.Opts()
  local tnow = now()
  local bx, by = floor(from.wx / 20), floor(from.wy / 20)
  local R = reach
  if R.at and tnow - R.at < 1 and R.fc == from.c and R.bx == bx and R.by == by and R.ver == TV.ver and R.mf == o.mf and R.fac == o.fac then
    return R
  end
  local G = TV.Graph(o.fac)
  local t0 = debugprofilestop and debugprofilestop()
  R.land = run(G, from, nil, o)
  if t0 then TV.stats.maxMs = max(TV.stats.maxMs, debugprofilestop() - t0) end
  for v = 1, G.n + 2 do R.d[v] = G.dist[v] end
  R.G, R.hearth, R.mf, R.fac, R.ver = G, o.hearth, o.mf, o.fac, TV.ver
  R.at, R.fc, R.fx, R.fy, R.bx, R.by = tnow, from.c, from.wx, from.wy, bx, by
  return R
end

-- minutes from where Reach looked to a place: through the best node, or walking straight there (math.huge: no way)
function TV.Via(R, place)
  local G, k = R.G, walkMin() * R.mf
  local lp = TV.Land(place.c, place.wx, place.wy)
  local best = lp == R.land and yd(R.fc, R.fx, R.fy, place.c, place.wx, place.wy) * k or huge
  for v = 1, G.n do
    local d = R.d[v]
    if d < best and G.land[v] == lp then
      d = d + yd(G.c[v], G.wx[v], G.wy[v], place.c, place.wx, place.wy) * k
      if d < best then best = d end
    end
  end
  local h, d = R.hearth, R.d[G.n + 2]
  if h and d < best and TV.Land(h.c, h.wx, h.wy) == lp then best = math.min(best, d + ydTo(h, place) * k) end
  return best
end

-- The route planner's minutes from one flight master to another over the flights you know (Model.lua, once some are not
-- known): the router run from the first one's spot to everywhere, then on foot to the other's (no hearthstone: the
-- planner has its own), with the main way taken (the longest step that isn't a walk). A row a flight master, kept until
-- what the router counts on or the walking pace changes; the walking at mf, as the planner's
local MODEL_KIND = { fly = "flight", boat = "boat", zeppelin = "zeppelin", tram = "tram", portal = "portal" }
local rows = {}
local function hubRow(fac, a, mf)
  local G = TV.Graph(fac)
  local from = G.pos[a]
  run(G, from, nil, { fac = fac, mf = mf, druid = class() == "DRUID" })
  local k, n = walkMin() * mf, G.n
  local dist, prev, how = G.dist, G.prev, G.how
  local mins, kinds = {}, {}
  for b = 1, G.h do
    local p, lp = G.pos[b], G.land[b]
    local best, via = G.land[a] == lp and ydTo(from, p) * k or huge, nil
    for v = 1, n do
      local d = dist[v]
      if d < best and G.land[v] == lp then
        d = d + yd(G.c[v], G.wx[v], G.wy[v], p.c, p.wx, p.wy) * k
        if d < best then best, via = d, v end
      end
    end
    local kind, most = "foot", 0
    local v = via
    while v and prev[v] do
      local m = dist[v] - dist[prev[v]]
      if MODEL_KIND[how[v]] and m > most then kind, most = MODEL_KIND[how[v]], m end
      v = prev[v]
    end
    mins[b], kinds[b] = best, kind
  end
  return { min = mins, kind = kinds }
end
function TV.HubMinutes(fac, a, b, mf)
  local R, mk = rows[fac], floor(mf * 1000 + 0.5)
  if not (R and R.ver == TV.ver and R.mk == mk) then R = { ver = TV.ver, mk = mk }; rows[fac] = R end
  local row = R[a]
  if not row then row = hubRow(fac, a, mf); R[a] = row end
  return row.min[b], row.kind[b]
end

-- the way from where you stand now; mode as the arrow's (the route's own hearth only on the route)
function TV.PlanTo(place, mode)
  local me = QB.API.WorldPosition()
  if not (me and place and place.c) then return nil end
  return TV.Route(me, place, TV.Opts(mode))
end

-- "Tram, boat, flight, about 16 min"
function TV.Summary(plan)
  if not plan then return nil end
  local parts = {}
  for _, l in ipairs(plan.legs) do if SAY[l.kind] then parts[#parts + 1] = SAY[l.kind] end end
  local what = #parts > 0 and table.concat(parts, ", ") or "on foot"
  return string.format("%s, about %d min", (what:gsub("^%l", string.upper)), max(1, floor(plan.min + 0.5)))
end

-- "320 yards", "1.2k yards"
function TV.DistanceText(yards)
  if yards >= 1000 then return string.format("%.1fk yards", yards / 1000) end
  return string.format("%d yards", floor(yards / 5 + 0.5) * 5)
end

----------------------------------------------------------------------------
-- live guidance: what the arrow shows now
----------------------------------------------------------------------------
-- g is the one table TV.Guide hands back, filled anew each look (no table is made per tick):
--   state  "walk" (the last walk: aim at the target), "there" (at it), "approach" (on the way to a step's start), "at"
--          (at it: talk, wait, use), "underway" (in the air, on board, on the tram, hearthing), "straight" (no way
--          known, but on this continent: point straight at it, as before), "unreachable" (another continent, no way
--          known), "ghost", "instance", "nopos" (the client gives no position here)
--   plan, leg, li   the plan and its current step (always its first: a step done plans again from where you are)
--   aim    {c, wx, wy} the arrow points at; nil: show `act` in its place
--   step, short, icon   the step line, its short form (the town) and its icon; step nil hides the line
--   info   the line under it.   act: the icon in the arrow's place.   cd: {start, duration}, a cooldown on `act`
--   eta    minutes to the target from here.   trail: the icons of the steps left, this one first
--   An icon is {atlas = name or nil, file = id}: the client's atlas where it has it, the file otherwise (QB.Art)
local g = { trail = {}, li = 1 }
TV.g = g
local st = {} -- the guide's own: its plan, the target's key, where you were, the locks
local cdT = {}

local function show(state, aim, step, short, icon, info, act)
  g.state, g.aim, g.step, g.short, g.icon, g.info, g.act = state, aim, step, short, icon, info, act
  return g
end

-- the same text while its number stays the same
local memo = {}
local function say(slot, n, fmt, ...)
  local m = memo[slot]
  if not m then m = {}; memo[slot] = m end
  if m.n ~= n then m.n, m.s = n, string.format(fmt, ...) end
  return m.s
end

-- "320 yards, 2 min" (the minutes from a minute and a half)
local distKey, distMin, distText
local function distInfo(yards, mins)
  local key = yards >= 1000 and -floor(yards / 100 + 0.5) or floor(yards / 5 + 0.5)
  local m = mins and mins >= 1.5 and floor(mins + 0.5) or 0
  if key ~= distKey or m ~= distMin then
    distKey, distMin = key, m
    distText = m > 0 and (TV.DistanceText(yards) .. ", " .. m .. " min") or TV.DistanceText(yards)
  end
  return distText
end

local function instanceMap()
  if type(GetInstanceInfo) ~= "function" then return nil end
  local ok, _, _, _, _, _, _, _, id = pcall(GetInstanceInfo)
  return ok and plain(id) or nil
end
local function inInstance()
  if type(IsInInstance) ~= "function" then return false end
  local ok, inside = pcall(IsInInstance)
  return ok and plain(inside) == true
end
local function yes(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, v = pcall(fn, ...)
  return ok and plain(v) == true
end

-- yards from you to the way a ride's step sails: its track from the step's pier to the far one (the loop's other half
-- left out), never the pier itself, so standing on it or near it is not "on the boat's way". A leg of 2,000 yards or
-- more is a loading screen, not sea. Where the step's piers lie on the track is worked out once a step
local function stopAt(tr, from, p)
  for i = from, #tr - 2, 3 do
    if tr[i] == p.c and tr[i + 1] == p.wx and tr[i + 2] == p.wy then return i end
  end
end
local function offTrack(me, leg)
  local tr = TV.Graph(faction()).track[leg.link]
  if not tr then return huge end
  if not leg.t1 then
    local i1 = stopAt(tr, 1, leg.start)
    local i2 = i1 and stopAt(tr, i1 + 3, leg.finish)
    leg.t1, leg.t2 = i1 or 1, i2 or #tr - 2
  end
  local i1, i2 = leg.t1, leg.t2
  local x, y, best = me.wx, me.wy, huge
  for i = i1, i2, 3 do
    if tr[i] == me.c then
      local ax, ay = tr[i + 1], tr[i + 2]
      local d
      if i ~= i1 then
        d = (ax - x) * (ax - x) + (ay - y) * (ay - y)
        if d < best then best = d end
      end
      if i < i2 and tr[i + 3] == me.c then
        local sx, sy = tr[i + 4] - ax, tr[i + 5] - ay
        local len = sx * sx + sy * sy
        if len > 0 and len < 2000 * 2000 then
          local k = ((x - ax) * sx + (y - ay) * sy) / len
          if k > 0 and k < 1 then
            local px, py = ax + k * sx - x, ay + k * sy - y
            d = px * px + py * py
            if d < best then best = d end
          end
        end
      end
    end
  end
  return sqrt(best)
end

-- a flight master of your faction here that you haven't learned
local function unlearned(me)
  local G, K = TV.Graph(faction()), TV.DB().known
  for i = 1, G.h do
    if G.flag[i] == 0 and K[G.taxi[i]] == false and G.c[i] == me.c then
      local dx, dy = G.wx[i] - me.wx, G.wy[i] - me.wy
      if dx * dx + dy * dy <= LEARN_NEAR * LEARN_NEAR then return i end
    end
  end
end

-- minutes from here to the target along a plan
local function eta(me, plan, t)
  local leg = plan.legs[1]
  local p = leg.kind == "walk" and t or leg.start
  return (p and ydTo(me, p) * walkMin() * (st.mf or 1) or 0) + leg.min + leg.rest
end

-- plan again from here. Forced (the target, what you know, the hearthstone, a jump, a step done): the new plan. Else
-- (you moved, a new zone) only a plan whose first step is the same one, or one clearly quicker than going on, so the
-- arrow doesn't flicker. A plan for the same target that travels keeps travelling while that saves 5% (TV.Route).
-- why: what made it plan again, for /qb trace
-- Just off a ride, a flight, the hearthstone or an instance's door (st.arrived, ARRIVE_S), a new plan travels on as one
-- that travels already would: you came by a way that travels, and stand at its station. 5.4.3, off the tram in
-- Ironforge with a hand-in at Menethil Harbor: the flight you knew (3.2 minutes with the walk to the flight master) lost
-- to walking straight there (3.8 minutes, the 1.2k yards through the mountains that a straight line is) by the fresh
-- plan's 15% and a minute, and the arrow said "Go to Menethil, 1.2k yards". A plan carried over the tram for the same
-- target kept the flight from this round on; a target new at the far end, or none before, did not
local function replan(me, t, mode, forced, why)
  local o = TV.Opts(mode)
  local cur = st.plan
  local sameTarget = st.planFor == st.tkey
  o.keepTravel = (sameTarget and cur and #cur.legs > 1) or (st.arrived and now() - st.arrived < ARRIVE_S) or nil
  local plan = TV.Route(me, t, o)
  st.planned, st.planAt, st.pc, st.px, st.py = true, now(), me.c, me.wx, me.wy
  st.ver, st.hSig, st.mf, st.force, st.why, st.planFor = TV.ver, hearthSig(o.hearth), o.mf, false, nil, st.tkey
  local a, b = cur and cur.legs[1], plan and plan.legs[1]
  local same = a and b and a.kind == b.kind and a.to == b.to
  if not forced and cur and not same then
    local left = eta(me, cur, t)
    if not plan or plan.min >= left - max(0.5, 0.1 * left) then
      if QB.tracing then QB.Trace("way to %s: planned again (%s), the first step kept: %s", tostring(t.name), why or "moved", a.step or "walk") end
      return
    end
  end
  if QB.tracing and (forced or not same) then
    QB.Trace("way to %s: planned again (%s, %s): %s%s", tostring(t.name), forced and "forced" or "not forced", why or "moved",
      b and (b.step or "walk") or "no way", (cur and not same) and (", was " .. (a.step or "walk")) or "")
  end
  if not same then st.reached = false end
  st.plan = plan
  local tr = g.trail
  for i = #tr, 1, -1 do tr[i] = nil end
  if plan and #plan.legs > 1 then
    local I = icons(o.fac)
    for i, l in ipairs(plan.legs) do tr[i] = l.icon or ((o.mounted or (o.mounted == nil and o.mf < 1)) and I.mount or I.foot) end
  end
end

local function flying(tnow, I)
  local to = st.flyTo
  if not to then return show("underway", nil, "In flight", nil, I.flying, "", nil) end
  local G = TV.Graph(faction())
  local info = "Landing"
  if st.flyMin then
    local s = math.ceil(st.flyAt + st.flyMin * 60 - tnow)
    if s > 0 then info = say("lands", s, "Lands in %d:%02d", floor(s / 60), s % 60) end
  end
  return show("underway", G.pos[to], say("flying", to, "Flying to %s", G.town[to]), G.town[to], I.flying, info, nil)
end

-- a ride of a boat or zeppelin leg, from its pier to where you got off after secs seconds on board: learned
-- (QuestBankDB.disc.rides), and every graph made again with it
function TV.NoteRide(leg, me, secs)
  local G = TV.Graph(faction())
  local from = leg.link and G.endOf[leg.from]
  local key = from and rideKey(leg.link, from)
  local all = key and rides()
  if not (all and me and secs and secs > 0) then return end
  local e = all[key]
  if type(e) ~= "table" or type(e.n) ~= "number" or type(e.t) ~= "number" then e = { n = 0 }; all[key] = e end
  local n = math.min(e.n, RIDE_MEAN - 1)
  e.t = floor(((e.t or secs) * n + secs) / (n + 1) + 0.5)
  e.n = e.n + 1
  e.b = { leg.start.c, floor(leg.start.wx + 0.5), floor(leg.start.wy + 0.5) }
  e.l = { me.c, floor(me.wx + 0.5), floor(me.wy + 0.5) }
  e.at = type(time) == "function" and time() or nil
  for k in pairs(graphs) do graphs[k] = nil end
  TV.ver = TV.ver + 1
end

local function onBoard(leg, tnow)
  local m = max(1, floor(leg.min - (tnow - st.rideAt) / 60 + 0.5))
  return show("underway", leg.finish, leg.step, leg.short, leg.icon, say("board", m, "On board, about %d min", m), nil)
end

local function hearthStep(leg)
  local left, start, dur
  if leg.kind == "recall" then left, start, dur = recallLeft() else left, start, dur = QB.API.HearthLeft() end
  local info = leg.wait
  if yes(InCombatLockdown) then
    info = "After the fight"
  elseif left and left > 0 then
    local s = math.ceil(left)
    info = say("ready", s, "Ready in %d:%02d", floor(s / 60), s % 60)
  end
  if left and left > 0 then cdT.start, cdT.duration = start, dur; g.cd = cdT end
  return show("at", nil, leg.step, leg.short, leg.icon, info, leg.icon)
end

-- what the arrow shows now, from where you stand (me: {c, wx, wy} or nil) toward its target (t: {name, c, wx, wy}),
-- for the arrow's mode (the route's own hearth only on the route). Plans only when something changed (see replan)
function TV.Guide(me, t, mode)
  local tnow = now()
  g.at, g.cd, g.eta, st.t = tnow, nil, nil, t
  local tx, ty = floor(t.wx / 5), floor(t.wy / 5)
  if st.tname ~= t.name or st.tc ~= t.c or st.tx ~= tx or st.ty ~= ty then
    st.tname, st.tc, st.tx, st.ty, st.force, st.why = t.name, t.c, tx, ty, true, "a new target"
    st.tkey = (st.tkey or 0) + 1
  end
  if TV.force then TV.force, st.force, st.why, st.arrived = false, true, st.why or TV.forceWhy or "a loading screen", tnow end
  -- a new zone: planned again, but kept unless clearly better (5.4.3 forced it, and at the walk-or-fly cut-off the
  -- first step could flip at a zone's border)
  local soft = TV.soft
  TV.soft = false
  if st.mode ~= mode then st.mode, st.force, st.why = mode, true, st.why or "the arrow's choice" end
  local I = icons(faction())
  local leg = st.plan and st.plan.legs[1]
  g.plan, g.leg = st.plan, leg
  -- dead, or in a dungeon: nothing to steer by
  if yes(UnitIsDeadOrGhost, "player") then return show("ghost", nil, nil, nil, nil, "Resurrect first", I.ghost) end
  local tram = instanceMap() == TRAM_MAP
  if not tram and inInstance() then return show("instance", nil, nil, nil, nil, "Leave the dungeon first", I.instance) end
  -- in the air: the plan stands until you land, then plans again from there
  if yes(UnitOnTaxi, "player") then
    if st.lock ~= "fly" then
      -- the flight you just picked (TakeTaxiNode), else the plan's own
      local f, fly = TV.flying, leg and leg.kind == "fly" and leg or nil
      if f and tnow - f.at > 60 then f = nil end
      st.lock, st.flyAt = "fly", f and f.at or tnow
      st.flyTo = f and f.to or fly and fly.to
      st.flyMin = f and f.min or fly and fly.min
    end
    return flying(tnow, I)
  elseif st.lock == "fly" then
    if mark(TV.Graph(faction()), st.flyTo, "f") then TV.ver = TV.ver + 1 end
    st.lock, TV.flying, st.force, st.why, st.arrived = nil, nil, true, "landed", tnow
  end
  -- the tram has no position: ride to the end
  if tram then
    if leg and leg.kind == "tram" then
      st.lock = "tram"
      return show("underway", nil, leg.going, leg.short, leg.icon, "Ride to the end", leg.icon)
    end
    return show("nopos", nil, g.step, g.short, g.icon, "", nil)
  elseif st.lock == "tram" then
    st.lock, st.force, st.why, st.arrived = nil, true, "off the tram", tnow
  end
  -- casting the hearthstone, and the loading screen after it
  local cast = TV.cast
  if cast then
    if cast.done and me and landed(me) then
      st.force, st.why, st.arrived = true, "hearthed", tnow
    elseif not cast.done and tnow - cast.at > 15 then
      TV.cast = nil -- (no end of the cast heard)
    else
      local hl = leg and (leg.kind == "hearth" or leg.kind == "recall") and leg or nil
      local icon = hl and hl.icon or I.hearth
      return show("underway", nil, hl and hl.step, hl and hl.short, icon, "Hearthing", icon)
    end
  end
  if not me then return show("nopos", nil, g.step, g.short, g.icon, "", nil) end
  local jumped = st.lc ~= nil and yd(me.c, me.wx, me.wy, st.lc, st.lx, st.ly) > JUMP
  st.lc, st.lx, st.ly = me.c, me.wx, me.wy
  -- on board: the plan stands until the far pier, you are back on the pier, clearly off the boat's way, or it takes far
  -- too long. Boarding again takes the pier again
  if st.lock == "ride" then
    local atEnd = ydTo(me, leg.finish) <= leg.finish.r
    if atEnd or ydTo(me, leg.start) <= leg.start.r or tnow - st.rideAt > 3 * leg.min * 60
      or (offTrack(me, leg) > 120 and ydTo(me, leg.start) > 80) then
      -- (off at the far end, or somewhere else through a loading screen, not back at the pier: the ride learned)
      if atEnd or (jumped and ydTo(me, leg.start) > LAND_YD) then TV.NoteRide(leg, me, tnow - st.rideAt) end
      st.lock, st.force, st.reached, st.why, st.arrived = nil, true, false, "off the boat", tnow
    else
      return onBoard(leg, tnow)
    end
  end
  -- boarding: you were at the pier and are well out from it now (past any pier or tower), on the boat's way. Out that
  -- far and off its way, you walked off: the pier again first
  if leg and not st.force and st.reached and (leg.kind == "boat" or leg.kind == "zeppelin") and ydTo(me, leg.start) > BOARD_YD then
    if offTrack(me, leg) <= 80 then
      st.lock, st.rideAt = "ride", tnow
      return onBoard(leg, tnow)
    end
    st.reached = false
  end
  -- plan again: something changed, or you got to the far end of a step (the portal's) and stand on its land; or, every
  -- few seconds, you moved
  if jumped then st.force, st.why, st.arrived = true, st.why or "a jump", tnow
  elseif TV.ver ~= st.ver then st.force, st.why = true, st.why or "the flight paths or the hearthstone"
  elseif leg and leg.start and ydTo(me, leg.finish) <= leg.finish.r
    and TV.Land(me.c, me.wx, me.wy) == TV.Land(leg.finish.c, leg.finish.wx, leg.finish.wy) then st.force, st.why = true, st.why or "a step done" end
  if tnow - (st.hAt or -huge) >= HEARTH_S then
    st.hAt = tnow
    if hearthSig(TV.Hearth(mode)) ~= st.hSig then st.force, st.why = true, st.why or "the hearthstone" end
  end
  if st.force or not st.planned then
    replan(me, t, mode, true, st.why or "first look")
  elseif soft then
    replan(me, t, mode, false, "a new zone")
  elseif tnow - st.planAt >= DRIFT_S and yd(me.c, me.wx, me.wy, st.pc, st.px, st.py) >= DRIFT_YD then
    replan(me, t, mode, false, "moved")
  end
  local plan = st.plan
  leg = plan and plan.legs[1]
  g.plan, g.leg = plan, leg
  if not plan then
    if me.c == t.c then return show("straight", t, nil, nil, nil, distInfo(ydTo(me, t)), nil) end
    return show("unreachable", nil, nil, nil, nil, "No known way there", I.unreachable)
  end
  g.eta = eta(me, plan, t)
  if leg.kind == "walk" then
    local d = ydTo(me, t)
    if d < THERE then return show("there", t, nil, nil, nil, "You're there", I.there) end
    if unlearned(me) then return show("walk", t, "Learn this flight path", "New flight path", I.learn, distInfo(d, g.eta), nil) end
    return show("walk", t, nil, nil, nil, distInfo(d, g.eta), nil)
  end
  if leg.kind == "hearth" or leg.kind == "recall" then return hearthStep(leg) end
  local d = ydTo(me, leg.start)
  if d <= leg.start.r then
    st.reached = true
    return show("at", leg.start, leg.step, leg.short, leg.icon, TV.taxiOpen and leg.pick or leg.wait, leg.icon)
  end
  return show("approach", leg.start, leg.step, leg.short, leg.icon, distInfo(d, g.eta), nil)
end

----------------------------------------------------------------------------
-- the flight master's map: a glow on the place the arrow's flight goes. QuestBank's own frame over the game's button,
-- never a child of the game's map
----------------------------------------------------------------------------
local markFrame
local function makeMark()
  local T = D.TEX
  local f = CreateFrame("Frame", "QuestBankTaxiMark", UIParent)
  f:SetFrameStrata("HIGH")
  f:SetSize(36, 36)
  f:EnableMouse(false)
  f.glow = f:CreateTexture(nil, "OVERLAY")
  f.glow:SetAllPoints()
  f.glow:SetTexture(T.taxiHi)
  f.glow:SetBlendMode("ADD")
  f.ping = f:CreateTexture(nil, "OVERLAY")
  f.ping:SetPoint("CENTER")
  f.ping:SetTexture(T.ping)
  f.ping:SetBlendMode("ADD")
  f.t = 0
  f:SetScript("OnUpdate", QB.Safe(function(self, elapsed)
    self.t = (self.t + (elapsed or 0)) % 1.2
    local k = self.t / 1.2
    self.ping:SetSize(36 + 44 * k, 36 + 44 * k)
    self.ping:SetAlpha(0.9 * (1 - k))
  end, "taxi map mark"))
  f:Hide()
  markFrame = f
  return f
end

-- while the arrow shows a flight from this flight master (the guide brought up to date first: the map just read may
-- have changed what you know)
function TV.TaxiMark()
  if not (TV.taxiOpen and st.t and g.at and now() - g.at <= 2) then return end
  local me = QB.API.WorldPosition()
  local leg = me and TV.Guide(me, st.t, st.mode).leg
  if not (leg and leg.kind == "fly" and ydTo(me, leg.start) <= START_R.fly) then return end
  local id = TV.Graph(faction()).taxi[leg.to]
  local slot
  for s, nid in pairs(TV.slots) do if nid == id then slot = s end end
  local button = slot and _G["TaxiButton" .. slot]
  if not button then return end
  local f = markFrame or makeMark()
  f:ClearAllPoints()
  if pcall(f.SetPoint, f, "CENTER", button, "CENTER", 0, 0) then f:Show() end
end

----------------------------------------------------------------------------
-- /qb way
----------------------------------------------------------------------------
function TV.WayLines()
  local out = {}
  local A = QB.Arrow
  local me = QB.API.WorldPosition()
  local t = A and A.Target(me)
  if not (t and t.c and t.wx and t.wy) then
    out[1] = "The arrow points at nothing yet: click a quest or a stop in " .. (QB.NAME or "QuestBank") .. ", or right-click the arrow."
  elseif not me then
    out[1] = (QB.NAME or "QuestBank") .. " can't tell where you are here."
  else
    local plan = TV.Route(me, t, TV.Opts(A.Mode()))
    if not plan then
      out[1] = string.format("No way to %s that %s knows from here.", t.name or "there", QB.NAME or "QuestBank")
    else
      local steps = {}
      for _, l in ipairs(plan.legs) do
        steps[#steps + 1] = string.format("%s (%d min)", l.step or ("Walk to " .. (t.name or "it")), max(1, floor(l.walk + l.min + 0.5)))
      end
      out[1] = string.format("Way to %s, about %d min: %s.", t.name or "it", max(1, floor(plan.min + 0.5)), table.concat(steps, ". "))
    end
  end
  local c = me and me.c or 0
  local n, total, read = TV.Known(faction(), c)
  -- (an open map off the two continents, Zephras Isle, has none)
  -- (read: the client answered for most of the continent; named: it said which, too few for a read, and only those
  -- count; assumed: it said nothing yet, and every one counts)
  out[#out + 1] = CONT_NAME[c] and string.format("Flight paths: %d of %d known on %s (%s).", n, total, CONT_NAME[c],
    read and "read" or (TV.tells and "those the game named" or "assumed")) or "Flight paths: none here."
  out[#out + 1] = TV.HearthLine()
  return out
end

----------------------------------------------------------------------------
-- events
----------------------------------------------------------------------------
function TV.OnEvent(event, a1, a2, a3)
  if event == "PLAYER_ENTERING_WORLD" then
    TV.force, TV.forceWhy = true, "a loading screen"
    C_Timer.After(3, QB.Safe(TV.Learn, "flight paths"))
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    TV.soft = true -- (planned again, and kept unless clearly better: TV.Guide)
  elseif event == "TAXIMAP_OPENED" then
    TV.ReadTaxiMap()
    C_Timer.After(0, QB.Safe(TV.TaxiMark, "taxi map mark"))
  elseif event == "TAXIMAP_CLOSED" then
    TV.taxiOpen = false
    if markFrame then markFrame:Hide() end
    TV.Learn()
  elseif event == "TAXI_NODE_STATUS_CHANGED" then
    -- it comes in bursts: one read a second later
    if TV.learnSoon then return end
    TV.learnSoon = true
    C_Timer.After(1, QB.Safe(function() TV.learnSoon = false; TV.Learn() end, "flight paths"))
  elseif event == "UI_INFO_MESSAGE" then
    if type(ERR_NEWTAXIPATH) == "string" and plain(a2) == ERR_NEWTAXIPATH then newPath(); TV.Learn() end
  elseif event == "PLAYER_CONTROL_LOST" or event == "PLAYER_CONTROL_GAINED" then
    TV.OnControl(event == "PLAYER_CONTROL_LOST")
  elseif event == "HEARTHSTONE_BOUND" then
    -- you stand at the innkeeper: where the hearthstone lands from now on
    local name, me = bindName(), QB.API.WorldPosition()
    if name and me then
      TV.DB().bind = { name = name, c = me.c, wx = me.wx, wy = me.wy, src = "bound", at = time and time() or 0 }
      diag().bind = name
      TV.ver = TV.ver + 1
    end
  else
    -- the hearthstone or Astral Recall: cast, done (then where it lands), or broken off
    if plain(a1) ~= "player" then return end
    local spell = plain(a3)
    if spell ~= 8690 and spell ~= 556 then return end
    if event == "UNIT_SPELLCAST_START" or (event == "UNIT_SPELLCAST_SUCCEEDED" and not TV.cast) then
      local me = QB.API.WorldPosition()
      TV.cast = { at = now(), c = me and me.c, wx = me and me.wx, wy = me and me.wy }
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
      TV.cast.done, TV.cast.name = now(), bindName()
      watchLanding(0)
    elseif event ~= "UNIT_SPELLCAST_START" then
      TV.cast = nil
    end
  end
end

function TV:Init()
  if self.frame then return end
  local f = CreateFrame("Frame")
  self.frame = f
  f:SetScript("OnEvent", QB.Safe(function(_, event, ...) TV.OnEvent(event, ...) end, "travel"))
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "TAXIMAP_OPENED", "TAXIMAP_CLOSED",
                       "TAXI_NODE_STATUS_CHANGED", "UI_INFO_MESSAGE", "HEARTHSTONE_BOUND", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" }) do
    pcall(f.RegisterEvent, f, e)
  end
  for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do
    if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, e, "player") else pcall(f.RegisterEvent, f, e) end
  end
  -- the flight you pick: the game's TakeTaxiNode (both flight maps call it), heard after it ran
  if type(hooksecurefunc) == "function" and type(TakeTaxiNode) == "function" then
    pcall(hooksecurefunc, "TakeTaxiNode", QB.Safe(TV.OnTakeTaxi, "taxi"))
  end
end
