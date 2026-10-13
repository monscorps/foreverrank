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
  Walk.dirty = true
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
  end, "walked trails"))
  f:SetScript("OnEvent", function() last = nil end) -- a loading screen: the next point starts a new trail
  pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")
end
