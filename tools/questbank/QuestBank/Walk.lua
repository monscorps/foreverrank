-- SPDX-License-Identifier: GPL-3.0-or-later
-- Walked trails: where you have walked, noted every 15 yards as you go, outdoors and on foot (never inside an
-- instance, never on a flight), as continent yards in QuestBankDB.disc.walk, so the minimap can draw the paths you
-- know and foreverrank.com can merge everyone's into the routes' golden paths. A gap of 150 yards or more (a
-- hearth, a boat, a loading screen) starts a new trail. At most 12,000 points a continent: the oldest trail goes.
--   disc.walk[c] = { { x1, y1, x2, y2, ... }, ... }   (c = 0 Eastern Kingdoms, 1 Kalimdor; whole yards)
-- Only reads: your position, as the arrow reads it.
local _, QB = ...
local Walk = {}
QB.Walk = Walk

local STEP = 15          -- yards between points
local BREAK = 150        -- a jump this long starts a new trail
local MAX_POINTS = 12000 -- a continent
local TICK = 1.0         -- seconds between looks
local DRAW_MAX = 160     -- trail segments drawn on the minimap at once
Walk.STEP, Walk.BREAK, Walk.MAX_POINTS = STEP, BREAK, MAX_POINTS

local plain = QB.Plain
local sqrt, floor = math.sqrt, math.floor

local function on() return QB:Settings().walkRecord ~= false end

local function db()
  local d = QB.Discover.DB()
  if type(d.walk) ~= "table" then d.walk = {} end
  return d.walk
end
Walk.DB = db

local last -- { c, wx, wy } of the last point noted
local function outdoors()
  if IsInInstance then
    local ok, inside = pcall(IsInInstance)
    if not ok or plain(inside) ~= false then return false end
  end
  if UnitOnTaxi and plain(UnitOnTaxi("player")) == true then return false end
  return true
end

local function count(trails)
  local n = 0
  for _, t in ipairs(trails) do n = n + #t / 2 end
  return n
end

-- note where you stand now, when it is a step on from the last point
function Walk.Note(me)
  if not on() then return false end
  me = me or (outdoors() and QB.API.WorldPosition()) or nil
  if not me then last = nil; return false end
  local wx, wy = floor(me.wx + 0.5), floor(me.wy + 0.5)
  local W = db()
  local trails = W[me.c]
  if type(trails) ~= "table" then trails = {}; W[me.c] = trails end
  local d = last and last.c == me.c and sqrt((wx - last.wx) ^ 2 + (wy - last.wy) ^ 2) or math.huge
  if d < STEP then return false end
  local t = trails[#trails]
  if not t or d >= BREAK then t = {}; trails[#trails + 1] = t end
  t[#t + 1], t[#t + 2] = wx, wy
  last = { c = me.c, wx = wx, wy = wy }
  Walk.dirty, Walk.dirtyNodes = true, true
  while count(trails) > MAX_POINTS and #trails > 1 do table.remove(trails, 1) end
  if count(trails) > MAX_POINTS then -- one trail longer than the cap: its oldest half goes
    local t1 = trails[1]
    for _ = 1, floor(#t1 / 4) * 2 do table.remove(t1, 1) end
  end
  return true
end

-- a grid over each continent's points, so the minimap looks only around you
local grid, gridC, gridN = nil, nil, 0
local CELL = 250
local function cell(x, y) return floor(x / CELL) .. ":" .. floor(y / CELL) end
local function index(c)
  local trails = db()[c] or {}
  local n = count(trails)
  if grid and gridC == c and gridN == n and not Walk.dirty then return grid end
  grid, gridC, gridN, Walk.dirty = {}, c, n, false
  for ti, t in ipairs(trails) do
    for i = 1, #t - 3, 2 do
      local k = cell(t[i], t[i + 1])
      local g = grid[k]
      if not g then g = {}; grid[k] = g end
      g[#g + 1] = { t, i }
    end
  end
  return grid
end

-- the trail segments within reach of a point: { {x1, y1, x2, y2}, ... }
function Walk.Near(c, wx, wy, reach)
  local g = index(c)
  local out = {}
  local cx, cy = floor(wx / CELL), floor(wy / CELL)
  local span = math.ceil(reach / CELL)
  for bx = cx - span, cx + span do
    for by = cy - span, cy + span do
      for _, e in ipairs(g[bx .. ":" .. by] or {}) do
        local t, i = e[1], e[2]
        local x1, y1, x2, y2 = t[i], t[i + 1], t[i + 2], t[i + 3]
        if (x1 - wx) ^ 2 + (y1 - wy) ^ 2 <= reach * reach or (x2 - wx) ^ 2 + (y2 - wy) ^ 2 <= reach * reach then
          out[#out + 1] = { x1, y1, x2, y2 }
          if #out >= DRAW_MAX then return out end
        end
      end
    end
  end
  return out
end

-- the way your trails know from one point to another: a search over the trail points (each joined to its
-- neighbours on the trail, and to any other trail's point within JOIN yards), from the point nearest you to the
-- point nearest the goal, each within REACH yards. Nil when the trails do not connect the two. Returns
-- { {x, y}, ... } from you to the goal, the trail points between
local JOIN, REACH, MAX_NODES = 25, 80, 6000
Walk.JOIN, Walk.REACH = JOIN, REACH
local nodes, nodesC, nodesN = nil, nil, 0
local function buildNodes(c)
  local trails = db()[c] or {}
  local n = count(trails)
  if nodes and nodesC == c and nodesN == n and not Walk.dirtyNodes then return nodes end
  nodes, nodesC, nodesN, Walk.dirtyNodes = {}, c, n, false
  local byCell = {}
  for ti, t in ipairs(trails) do
    for i = 1, #t - 1, 2 do
      local id = #nodes + 1
      nodes[id] = { x = t[i], y = t[i + 1], adj = {}, t = ti }
      if i > 1 then local prev = id - 1; nodes[id].adj[#nodes[id].adj + 1] = prev; nodes[prev].adj[#nodes[prev].adj + 1] = id end
      local k = cell(t[i], t[i + 1])
      byCell[k] = byCell[k] or {}
      byCell[k][#byCell[k] + 1] = id
    end
  end
  -- joins across trails
  for id, nd in ipairs(nodes) do
    local cx, cy = floor(nd.x / CELL), floor(nd.y / CELL)
    for bx = cx - 1, cx + 1 do
      for by = cy - 1, cy + 1 do
        for _, other in ipairs(byCell[bx .. ":" .. by] or {}) do
          local o = nodes[other]
          if other ~= id and o.t ~= nd.t and (o.x - nd.x) ^ 2 + (o.y - nd.y) ^ 2 <= JOIN * JOIN then nd.adj[#nd.adj + 1] = other end
        end
      end
    end
  end
  return nodes
end
Walk.Nodes = buildNodes

local function nearestNode(N, wx, wy, reach)
  local best, bd = nil, reach * reach
  for id, nd in ipairs(N) do
    local d = (nd.x - wx) ^ 2 + (nd.y - wy) ^ 2
    if d < bd then best, bd = id, d end
  end
  return best
end

function Walk.Path(c, from, to)
  local N = buildNodes(c)
  if #N == 0 then return nil end
  local a, b = nearestNode(N, from.wx, from.wy, REACH), nearestNode(N, to.wx, to.wy, REACH)
  if not a or not b then return nil end
  if a == b then return { { from.wx, from.wy }, { N[a].x, N[a].y }, { to.wx, to.wy } } end
  local open, g, came, closed = { [a] = true }, { [a] = 0 }, {}, {}
  local function h(id) return sqrt((N[id].x - N[b].x) ^ 2 + (N[id].y - N[b].y) ^ 2) end
  local f = { [a] = h(a) }
  local explored = 0
  while next(open) do
    local cur, best
    for id in pairs(open) do if not best or f[id] < best then cur, best = id, f[id] end end
    if cur == b then break end
    open[cur] = nil; closed[cur] = true
    explored = explored + 1
    if explored > MAX_NODES then return nil end
    for _, nb in ipairs(N[cur].adj) do
      if not closed[nb] then
        local ng = g[cur] + sqrt((N[nb].x - N[cur].x) ^ 2 + (N[nb].y - N[cur].y) ^ 2)
        if g[nb] == nil or ng < g[nb] then g[nb], came[nb], f[nb] = ng, cur, ng + h(nb); open[nb] = true end
      end
    end
  end
  if not came[b] and a ~= b then return nil end
  local out = { { to.wx, to.wy } }
  local cur = b
  while cur do
    out[#out + 1] = { N[cur].x, N[cur].y }
    cur = came[cur]
  end
  out[#out + 1] = { from.wx, from.wy }
  -- reverse: from you to the goal; a trail point you stand on, or the goal stands on, is not a leg
  for i = 1, floor(#out / 2) do out[i], out[#out + 1 - i] = out[#out + 1 - i], out[i] end
  local function same(p, q) return math.abs(p[1] - q[1]) + math.abs(p[2] - q[2]) < 2 end
  if #out > 2 and same(out[1], out[2]) then table.remove(out, 2) end
  if #out > 2 and same(out[#out], out[#out - 1]) then table.remove(out, #out - 1) end
  return out
end

function Walk:Init()
  if self.frame then return end
  local f = CreateFrame("Frame")
  self.frame = f
  f.elapsed = 0
  f:SetScript("OnUpdate", QB.Safe(function(self, dt)
    self.elapsed = self.elapsed + (dt or 0)
    if self.elapsed < TICK then return end
    self.elapsed = 0
    if on() then Walk.Note() end
    if QB.Measure then QB.Measure.Sample() end -- your pace, on foot and mounted (Legacy.lua)
  end, "walked trails"))
  f:SetScript("OnEvent", function() last = nil end) -- a loading screen: the next point starts a new trail
  pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")
end
