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

-- The trails as a graph, kept for one continent at a time and grown point by point as you walk (5.4.2: it was built
-- afresh, a table for every point and every link, each time a point was noted; at thousands of points that froze the
-- game for a tenth of a second and more every few seconds and left megabytes of garbage each time). Flat arrays by
-- node id, no table per point:
--   x[id], y[id]: the point; tr[id]: its trail's serial (a trail keeps its serial while older ones go)
--   on its trail, the points before and after: id - 1 and id + 1 when they have the same serial
--   links to other trails' points within JOIN yards: lhead[id], then lto[e] and lnext[e] (0 ends a list)
--   join cells, JCELL yards (a point's joins all lie in the 3x3 cells round it): jhead[key], then jnext[id]
--   draw cells, CELL yards (Walk.Near): the segments starting in each, in the order noted: dhead[key] .. dtail[key],
--     dnext[id]
-- Points the cap drops keep their ids (ids below first are skipped) until they are half as many as the points kept;
-- then the graph is built again with fresh ids: once in thousands of points.
local JOIN, REACH, MAX_NODES = 25, 80, 6000
local REACH_KEEP = 110 -- yards: the trails looked for this far while a way to the same place is shown (MinimapRoute.lua)
local JCELL = 50 -- yards: no smaller than JOIN
local CELL = 250 -- yards: the draw cells, as the minimap looks round you
Walk.JOIN, Walk.REACH, Walk.REACH_KEEP = JOIN, REACH, REACH_KEEP
local G = { ver = 0, stale = true, n = 0 }
Walk.G = G
Walk.builds = 0 -- (graphs built whole: once at the first look, then only when the trails change under it or once in
                -- thousands of points; the harness counts them)
local function key(cx, cy) return (cx + 32768) * 65536 + (cy + 32768) end

local function reset(c, trails)
  Walk.builds = Walk.builds + 1
  G.c, G.trails, G.stale = c, trails, false
  G.n, G.first, G.last, G.tbase, G.nl = 0, 1, 0, 0, 0
  G.x, G.y, G.tr, G.lhead, G.jnext, G.dnext, G.lto, G.lnext = {}, {}, {}, {}, {}, {}, {}, {}
  G.jhead, G.dhead, G.dtail = {}, {}, {}
  G.g, G.came, G.mark, G.gen = {}, {}, {}, 0 -- the search's (Walk.Path), by node id
  G.ver = G.ver + 1
end

local function link(a, b)
  local e = G.nl + 1
  G.nl = e
  G.lto[e], G.lnext[e], G.lhead[a] = b, G.lhead[a], e
end

-- a point at the end of trail serial s: joined to the point before it on the trail, to every other trail's point within
-- JOIN yards (both ways), and its segment from the point before put in that point's draw cell
local function add(x, y, s)
  local id = G.last + 1
  G.last, G.n = id, G.n + 1
  local X, Y, T, first = G.x, G.y, G.tr, G.first
  X[id], Y[id], T[id], G.lhead[id], G.dnext[id] = x, y, s, 0, 0
  local p = id - 1
  if p >= first and T[p] == s then
    local k = key(floor(X[p] / CELL), floor(Y[p] / CELL))
    local tail = G.dtail[k]
    if tail then G.dnext[tail] = p else G.dhead[k] = p end
    G.dtail[k] = p
  end
  local jh, jn = G.jhead, G.jnext
  local cx, cy = floor(x / JCELL), floor(y / JCELL)
  for bx = cx - 1, cx + 1 do
    for by = cy - 1, cy + 1 do
      local o = jh[key(bx, by)] or 0
      while o > 0 do
        if o >= first and T[o] ~= s then
          local dx, dy = X[o] - x, Y[o] - y
          if dx * dx + dy * dy <= JOIN * JOIN then link(id, o); link(o, id) end
        end
        o = jn[o]
      end
    end
  end
  local k = key(cx, cy)
  jn[id] = jh[k] or 0
  jh[k] = id
end

-- the graph of continent c, built again only when it is not the one kept (another continent, the trails changed under
-- it, or Walk.dirty / Walk.dirtyNodes set by whoever changed them)
local NONE = {}
local function graph(c)
  local trails = db()[c]
  if G.c == c and G.trails == trails and not G.stale and not Walk.dirty and not Walk.dirtyNodes
    and G.n == count(trails or NONE) then return G end
  Walk.dirty, Walk.dirtyNodes = false, false
  reset(c, trails)
  for ti, t in ipairs(trails or NONE) do
    for i = 1, #t - 1, 2 do add(t[i], t[i + 1], ti) end
  end
  return G
end
Walk.Graph = graph

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
  local n = count(trails)
  -- the graph grows by this point when it is the one kept and up to date
  local synced = G.c == me.c and G.trails == trails and not G.stale and not Walk.dirty and not Walk.dirtyNodes and G.n == n
  local t = trails[#trails]
  if not t or d >= BREAK then t = {}; trails[#trails + 1] = t end
  t[#t + 1], t[#t + 2] = wx, wy
  n = n + 1
  last = { c = me.c, wx = wx, wy = wy }
  if synced then add(wx, wy, G.tbase + #trails) elseif G.c == me.c then G.stale = true end
  -- the cap: the oldest trail goes; one trail longer than the cap loses its oldest half, moved down in one pass
  while n > MAX_POINTS and #trails > 1 do
    local k = #trails[1] / 2
    table.remove(trails, 1)
    n = n - k
    if synced then G.first, G.n, G.tbase = G.first + k, G.n - k, G.tbase + 1 end
  end
  if n > MAX_POINTS then
    local t1 = trails[1]
    local len = #t1
    local drop = floor(len / 4) * 2
    for j = 1, len - drop do t1[j] = t1[j + drop] end
    for j = len, len - drop + 1, -1 do t1[j] = nil end
    n = n - drop / 2
    if synced then G.first, G.n = G.first + drop / 2, G.n - drop / 2 end
  end
  if synced and (G.first - 1) * 2 >= G.n and G.first > 1 then G.stale = true end
  G.ver = G.ver + 1
  return true
end

-- the trail segments within reach of a point: { {x1, y1, x2, y2}, ... }, at most DRAW_MAX, the nearest to the point
-- first (5.4.3 took them cell by cell from the window's corner and stopped at DRAW_MAX, so patches round you came and
-- went as you walked). The list and its entries are reused by the next call (the minimap draws them at once, 20 times
-- a second), and the same list is handed back while the point stays within a few yards and the trails are the same
-- (the list is a heap while it is made: the farthest kept on top, and put back by a nearer one once DRAW_MAX are in. No
-- sort of everything in reach: zoomed far out that is thousands)
local nearOut, nearPool = {}, {}
local nearAt = {}
function Walk.Near(c, wx, wy, reach)
  local g = graph(c)
  local out = nearOut
  local qx, qy = floor(wx / 4), floor(wy / 4)
  if nearAt.c == c and nearAt.x == qx and nearAt.y == qy and nearAt.r == reach and nearAt.v == g.ver and nearAt.f == g.first then return out end
  for k = #out, 1, -1 do out[k] = nil end
  nearAt.c = nil
  local X, Y, dnext, dhead, first = g.x, g.y, g.dnext, g.dhead, g.first
  if not X then return out end
  local cx, cy = floor(wx / CELL), floor(wy / CELL)
  local span = math.ceil(reach / CELL)
  local r2, n = reach * reach, 0
  for bx = cx - span, cx + span do
    for by = cy - span, cy + span do
      local i = dhead[key(bx, by)] or 0
      while i > 0 do
        if i >= first then
          local x1, y1, x2, y2 = X[i], Y[i], X[i + 1], Y[i + 1]
          local d1, d2 = (x1 - wx) ^ 2 + (y1 - wy) ^ 2, (x2 - wx) ^ 2 + (y2 - wy) ^ 2
          if d1 <= r2 or d2 <= r2 then
            local d = d1 < d2 and d1 or d2
            if n < DRAW_MAX then
              -- in, then up the heap past nearer ones
              n = n + 1
              local s = nearPool[n]
              if not s then s = {}; nearPool[n] = s end
              s[1], s[2], s[3], s[4], s[5] = x1, y1, x2, y2, d
              local h = n
              while h > 1 do
                local p = floor(h / 2)
                if out[p][5] >= d then break end
                out[h] = out[p]
                h = p
              end
              out[h] = s
            elseif d < out[1][5] then
              -- in place of the farthest, then down the heap past farther ones
              local s = out[1]
              s[1], s[2], s[3], s[4], s[5] = x1, y1, x2, y2, d
              local h = 1
              while true do
                local k = h * 2
                if k > n then break end
                if k < n and out[k + 1][5] > out[k][5] then k = k + 1 end
                if out[k][5] <= d then break end
                out[h] = out[k]
                h = k
              end
              out[h] = s
            end
          end
        end
        i = dnext[i]
      end
    end
  end
  nearAt.c, nearAt.x, nearAt.y, nearAt.r, nearAt.v, nearAt.f = c, qx, qy, reach, g.ver, g.first
  return out
end

-- the way your trails know from one point to another: a search over the trail points (each joined to its
-- neighbours on the trail, and to any other trail's point within JOIN yards), from the point nearest you to the
-- point nearest the goal, each within REACH yards. Nil when the trails do not connect the two. Returns
-- { {x, y}, ... } from you to the goal, the trail points between

-- the point nearest (wx, wy) within reach (the lowest id of equals), through the join cells
local function nearestNode(g, wx, wy, reach)
  local best, bd = nil, reach * reach
  local X, Y, jh, jn, first = g.x, g.y, g.jhead, g.jnext, g.first
  local cx, cy, span = floor(wx / JCELL), floor(wy / JCELL), math.ceil(reach / JCELL)
  for bx = cx - span, cx + span do
    for by = cy - span, cy + span do
      local o = jh[key(bx, by)] or 0
      while o > 0 do
        if o >= first then
          local dx, dy = X[o] - wx, Y[o] - wy
          local d = dx * dx + dy * dy
          if d < bd or (d == bd and best and o < best) then best, bd = o, d end
        end
        o = jn[o]
      end
    end
  end
  return best
end

-- the search's open set: a binary heap of (f, node), kept between searches
local hf, hid, hn = {}, {}, 0
local function push(f, id)
  hn = hn + 1
  local i = hn
  while i > 1 do
    local p = floor(i / 2)
    if hf[p] <= f then break end
    hf[i], hid[i] = hf[p], hid[p]
    i = p
  end
  hf[i], hid[i] = f, id
end
local function pop()
  local id = hid[1]
  local f, last = hf[hn], hid[hn]
  hn = hn - 1
  local i, n = 1, hn
  while true do
    local c = i * 2
    if c > n then break end
    if c < n and hf[c + 1] < hf[c] then c = c + 1 end
    if hf[c] >= f then break end
    hf[i], hid[i] = hf[c], hid[c]
    i = c
  end
  if n > 0 then hf[i], hid[i] = f, last end
  return id
end

local function same(p, q) return math.abs(p[1] - q[1]) + math.abs(p[2] - q[2]) < 2 end

-- one search's state (module locals, so a search makes no closure): a neighbour nb of cur reached at cost cg
local sX, sY, sMark, sG, sCame, sGen, sTx, sTy
local function relax(nb, cur, cx, cy, cg)
  local m = sMark[nb]
  if m == -sGen then return end
  local ng = cg + sqrt((sX[nb] - cx) ^ 2 + (sY[nb] - cy) ^ 2)
  if m ~= sGen or ng < sG[nb] then
    sMark[nb], sG[nb], sCame[nb] = sGen, ng, cur
    push(ng + sqrt((sX[nb] - sTx) ^ 2 + (sY[nb] - sTy) ^ 2), nb)
  end
end

function Walk.Path(c, from, to, reach)
  local g = graph(c)
  if g.n == 0 then return nil end
  reach = reach or REACH
  local a, b = nearestNode(g, from.wx, from.wy, reach), nearestNode(g, to.wx, to.wy, reach)
  if not a or not b then return nil end
  local X, Y = g.x, g.y
  if a == b then return { { from.wx, from.wy }, { X[a], Y[a] }, { to.wx, to.wy } } end
  -- the same two points on the same graph found no way last time: none now either (the minimap asks again every few
  -- seconds while you stand off your trails)
  if g.noVer == g.ver and g.noA == a and g.noB == b then return nil end
  g.gen = g.gen + 1
  sX, sY, sMark, sG, sCame, sGen, sTx, sTy = X, Y, g.mark, g.g, g.came, g.gen, X[b], Y[b]
  local T, lhead, lto, lnext, first, lastId = g.tr, g.lhead, g.lto, g.lnext, g.first, g.last
  -- sMark[id]: the search's number while open, minus it once closed
  sMark[a], sG[a], sCame[a] = sGen, 0, 0
  hn = 0
  push(sqrt((X[a] - sTx) ^ 2 + (Y[a] - sTy) ^ 2), a)
  local explored, found = 0, false
  while hn > 0 do
    local cur = pop()
    if sMark[cur] == sGen then
      if cur == b then found = true; break end
      sMark[cur] = -sGen
      explored = explored + 1
      if explored > MAX_NODES then break end
      local cx, cy, cg, s = X[cur], Y[cur], sG[cur], T[cur]
      -- the points before and after it on its trail, then the other trails' points it is joined to
      if cur - 1 >= first and T[cur - 1] == s then relax(cur - 1, cur, cx, cy, cg) end
      if cur + 1 <= lastId and T[cur + 1] == s then relax(cur + 1, cur, cx, cy, cg) end
      local e = lhead[cur]
      while e > 0 do
        local nb = lto[e]
        if nb >= first then relax(nb, cur, cx, cy, cg) end
        e = lnext[e]
      end
    end
  end
  hn = 0
  local came = sCame
  sX, sY, sMark, sG, sCame = nil, nil, nil, nil, nil -- (nothing kept of this graph past the search)
  if not found then g.noVer, g.noA, g.noB = g.ver, a, b; return nil end
  local out = { { to.wx, to.wy } }
  local cur = b
  while cur > 0 do
    out[#out + 1] = { X[cur], Y[cur] }
    cur = came[cur]
  end
  out[#out + 1] = { from.wx, from.wy }
  -- reverse: from you to the goal; a trail point you stand on, or the goal stands on, is not a leg
  for i = 1, floor(#out / 2) do out[i], out[#out + 1 - i] = out[#out + 1 - i], out[i] end
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
