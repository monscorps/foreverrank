-- SPDX-License-Identifier: GPL-3.0-or-later
-- The Map page (page 8 of the QuestBank window, the Forever client only): the game's own map canvas inside the window,
-- built in Lua from Blizzard_MapCanvas's mixins. Five of Blizzard's data providers give it the game's art and explored
-- areas, the zones lit and named under the mouse, your arrow and your party, and the quests' blue areas; QuestBank's
-- layers go on top, each the game's own pin drawn again on QuestBank's frames (Pins.lua, Pins.xml): QuestMap.lua's
-- quest pins, offers and dungeon entrances, Pins.lua's route pins, and here the flight points, the route's strokes and
-- the arrow's step. Above the map a bar of crumbs (Azeroth > Eastern Kingdoms > Elwynn Forest), Here, the dungeons on
-- the map and a "Game's map" button for the game's own world map; under it the zone's name and levels and a switch
-- for each layer; beside it the zone's quests: ready to hand in, in your log and to pick up, a row each, lit on the
-- map while hovered and shown there when clicked. A right-click on the map is its menu (zoom out, the game's map,
-- your zone, a waypoint). It opens on your zone and follows you until you go elsewhere. The game's world map is left
-- as it was, QuestBank's layers on it as before; the game's own map key always opens it, QuestBank's Map key this page.
local _, QB = ...
local MP = { follow = true }
QB.MapPage = MP

local MAP_W, MAP_H, PANEL_W, NAV_H, STRIP_H = 548, 365, 256, 26, 51
local PAGE_H = NAV_H + 4 + MAP_H + 6 + STRIP_H -- 452, the page's height
local GAP = 8           -- between the map and the quest panel
local CRUMB_MAX = 140   -- a crumb's widest
local SEP_W = 14        -- the ">" between two crumbs
local TOGGLE_W = 44     -- a layer's switch under the map: its 20 px icon and its count
local ROW_H, HEAD_H, SEL_H = 28, 24, 34 -- the quest panel's rows, its sections' headers and its selection bar
local LIST_W = PANEL_W - 8 - 20         -- the panel's list, its knob on the right
local NAME_W = LIST_W - 28 - 52         -- a row's title, between its icon and its XP
local LINE_W = 4        -- the route's strokes, in pixels on screen at any zoom (5 before 5.4.4: a quarter thinner)
local TICK = 0.25       -- seconds between looks at where you stand and at the arrow's step
local FLASH = 1.2       -- seconds a row shown from the map stays lit
local GOLD = { 1, 0.82, 0.3 }
local INK = { 0.86, 0.8, 0.68 }
local SOFT = { 0.6, 0.55, 0.47 }
local LIT = { 0.3, 0.55, 1, 0.9 }          -- the light under the pins of the quest hovered or picked in the list
local STEP_LIT = { 1, 0.82, 0.3, 0.8 }     -- and under the arrow's step
local PICKED, FOCUSED = { GOLD[1], GOLD[2], GOLD[3], 0.12 }, { 0.3, 0.55, 1, 0.16 } -- a row ticked, a row shown on the map
local FLAT = "Interface\\Buttons\\WHITE8x8"
local CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
local T = QB.Data.TEX
local P = QB.Pins
local min, max, abs, floor = math.min, math.max, math.abs, math.floor

-- Blizzard's providers on this canvas: each makes its one pin when it is added (out of combat) and writes nothing the
-- world map shares. The providers of quests, POIs, offers, world quests, bonus objectives, vignettes, the waypoint,
-- flight points and dungeon entrances never come here: they share the world map's caches, fire its events or make
-- pins again in a fight, all as QuestBank
local BLIZZARD = { "MapExplorationDataProviderMixin", "MapHighlightDataProviderMixin", "AreaLabelDataProviderMixin",
                   "GroupMembersDataProviderMixin", "QuestBlobDataProviderMixin" }

-- the switches under the map, a layer each, with the game's icon for it and how many there are on this map. The first
-- three and the dungeons are QuestMap.lua's own switches (Settings has them under "Quest icons on the world map": icons),
-- the route and the flight paths the page's. count: what the number counts (list: the panel's section of that kind)
local TOGGLES = {
  { key = "mapTurn", name = "Ready to hand in", atlas = "UI-QuestIcon-TurnIn-Normal", file = T.questActive, icons = true, count = "ready", list = "ready" },
  { key = "mapObj", name = "In your log", atlas = "Quest-In-Progress-Icon-yellow", file = T.questActive, icons = true, count = "log", list = "log" },
  { key = "mapGive", name = "To pick up", atlas = "QuestNormal", file = T.questAvail, icons = true, count = "pickup", list = "pickup" },
  { key = "mapRoute", name = "Route", atlas = "UI-QuestPoi-QuestNumber-SuperTracked", file = T.mapPin, count = "route" },
  { key = "mapDungeons", name = "Dungeons", atlas = "Dungeon", file = QB.QuestMap.ART.dungeon.file, icons = true, count = "dungeons" },
  { key = "mapFlights", name = "Flight paths", atlas = "FlightPath", file = T.taxiY, count = "flights" },
}
-- the panel's sections: the zone's quests of the first three kinds, as QuestMap.lua finds them (QM.ZoneQuests)
local SECTIONS = { TOGGLES[1], TOGGLES[2], TOGGLES[3] }

-- how the keys fall, said wherever the two maps meet (the Game's map button, Settings): QuestBank's Map key is its
-- own binding, the game's map key is the game's
MP.KEYS = "QuestBank's Map key (Key Bindings, QuestBank) opens this page. The game's own map key (M, unless you changed it) always opens the game's map."

-- Forever's client with the game's map canvas and the five providers (not Classic Era)
function MP.Available()
  if not (QB.QuestMap and QB.QuestMap.Available() and MapCanvasMixin and MapCanvasScrollControllerMixin and Mixin
    and CreateFromMixins and secureexecuterange) then return false end
  for _, name in ipairs(BLIZZARD) do
    if not _G[name] then return false end
  end
  return true
end

-- the Map key and the sidebar open this page, unless Settings (or /qb map game) gave them back to the game's map
function MP.On() return MP.Available() and QB:Settings().mapPage ~= false end

----------------------------------------------------------------------------
-- the canvas
----------------------------------------------------------------------------
-- MapCanvasMixin with three of its methods again, without the call that empties the game's shared quest and POI
-- caches each frame, on show and on a new map: run from QuestBank's frame it would leave them written by QuestBank,
-- and the world map, the battlefield map and the flight map read them
local Canvas = {}
local function providerShow(dp) dp:OnShow() end
local function providerMapChanged(dp) dp:OnMapChanged() end

function Canvas:OnUpdate()
  self:UpdatePinSuppression()
  self:UpdatePinNudging()
  self:ProcessCursorHandlers()
  self:RunDataProviderOnUpdate()
end

function Canvas:OnShow()
  self:RefreshAll(true)
  secureexecuterange(self.dataProviders, providerShow)
  self:RegisterEvent("HANDLE_UI_ACTION")
end

function Canvas:OnMapChanged()
  secureexecuterange(self.dataProviders, providerMapChanged)
  QB.Try("map page", MP.MapChanged)
end

local function info(id)
  if type(id) ~= "number" or not (C_Map and C_Map.GetMapInfo) then return nil end
  local ok, i = pcall(C_Map.GetMapInfo, id)
  return ok and type(i) == "table" and i or nil
end

-- only a map with art may be shown: Blizzard's scroll container reads its first art layer unchecked
local function hasArt(id)
  if type(id) ~= "number" or not (C_Map and C_Map.MapHasArt) then return false end
  local ok, art = pcall(C_Map.MapHasArt, id)
  return ok and QB.Plain(art) == true
end

local function playerMap()
  if not (MapUtil and MapUtil.GetDisplayableMapForPlayer) then return nil end
  local ok, m = pcall(MapUtil.GetDisplayableMapForPlayer)
  return ok and QB.Plain(m) or nil
end

-- the map on show: the canvas's, or yours while there is none yet (a login in a fight)
local function shownMap()
  if MP.canvas then return QB.Plain(MP.canvas:GetMapID()) end
  return playerMap()
end

-- a click on the map itself (the canvas asks this before it opens a zone or goes up to its parent): Ctrl and a left
-- click is QuestBank's waypoint there; a right-click is the map's menu (MP.MapMenu), with the zoom out the game's
-- right-click does first on it
local function canvasClick(canvas, button, x, y)
  local m = QB.Plain(canvas:GetMapID())
  x, y = QB.Plain(x), QB.Plain(y)
  if not (m and type(x) == "number" and type(y) == "number") then return false end
  if button == "RightButton" then
    MP.MapMenu(canvas, m, x, y)
    return true
  end
  if button ~= "LeftButton" or not (IsControlKeyDown and IsControlKeyDown()) then return false end
  QB.Try("map page click", QB.API.SetWaypoint, m, x * 100, y * 100, "Map")
  return true
end

local function setMap(canvas, mapID) canvas:SetMapID(mapID) end

local function tip(owner, title, about, anchor)
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_BOTTOM")
  GameTooltip:AddLine(title, GOLD[1], GOLD[2], GOLD[3])
  GameTooltip:AddLine(about, 1, 1, 1, true)
  GameTooltip:Show()
end
local function untip() GameTooltip:Hide() end

----------------------------------------------------------------------------
-- QuestBank's layers made here (Pins.lua's: QuestBank's own frames on the canvas, made out of combat): the route's
-- strokes, the arrow's step and the flight paths. The quest icons and the route's pins are QuestMap.lua's and Pins.lua's
----------------------------------------------------------------------------
-- where you stand on map m, in fractions, or nil off it
local function youOn(m)
  local me = m and QB.API.WorldPosition()
  local x, y = nil, nil
  if me then x, y = QB.Model.MapPos(me.c, me.wx, me.wy, m) end
  return x and { x = x, y = y } or nil
end

local function canvasScale(map)
  local ok, s = pcall(map.GetCanvasScale, map)
  s = ok and tonumber(QB.Plain(s)) or 1
  return s > 0 and s or 1
end

-- a place in the world (continent c, yards) as fractions of map m, also beyond its edges (a stop in the next zone): from
-- where the map's corners lie in the world. Nil where the client won't say
local cornerA, cornerB = {}, {}
local function fracOf(m, c, wx, wy)
  local M = QB.Model
  local a, b = M.World(m, 0, 0, cornerA), M.World(m, 100, 100, cornerB)
  if not (a and b and a.c == c and b.c == c) then return nil end
  local dx, dy = b.wx - a.wx, b.wy - a.wy
  if dx == 0 or dy == 0 then return nil end
  return (wy - a.wy) / dy, (wx - a.wx) / dx
end
-- a pin's place ({m, x, y} in percent) on map m: on it (P.Project), else beyond its edge through the world
local wspot = {}
local function spotOn(d, m)
  local x, y = P.Project(d, m)
  if x then return x, y end
  local w = d.m and QB.Model.World(d.m, d.x, d.y, wspot)
  if w then return fracOf(m, w.c, w.wx, w.wy) end
end

-- the part of a segment within the rectangle of half-sizes hw, hh round the centre (Liang-Barsky, an edge at a time),
-- and whether its end was cut; nil when none of it is
local function edge(p, q, t0, t1)
  if not t0 then return nil end
  if p == 0 then
    if q < 0 then return nil end
    return t0, t1
  end
  local t = q / p
  if p < 0 then
    if t > t1 then return nil end
    if t > t0 then t0 = t end
  else
    if t < t0 then return nil end
    if t < t1 then t1 = t end
  end
  return t0, t1
end
local function clipRect(x1, y1, x2, y2, hw, hh)
  local dx, dy = x2 - x1, y2 - y1
  local t0, t1 = edge(-dx, x1 + hw, 0, 1)
  t0, t1 = edge(dx, hw - x1, t0, t1)
  t0, t1 = edge(-dy, y1 + hh, t0, t1)
  t0, t1 = edge(dy, hh - y1, t0, t1)
  if not t0 or t0 >= t1 then return nil end
  return x1 + dx * t0, y1 + dy * t0, x1 + dx * t1, y1 + dy * t1, t1 < 1
end

-- the route's strokes: one frame over the whole map (Fit sizes it to the canvas, as the quest areas are sized), a line
-- of art/line_arrow.png from you to the one target (gold: Target.lua's, the same the arrow and the minimap lead to: stop
-- 1, a spot of an objective of its quest, or the arrow's step toward it), on to stop 1 when that is not it, and from each
-- stop to the next (blue), drawn as the minimap draws its strokes (MinimapRoute.lua) and LINE_W pixels thick on screen
-- at any zoom. A place off this map (stop 1 in the zone you just left) is drawn to the map's edge, the way it lies: the
-- page follows you over a zone's border, and 5.4.3 dropped the stroke to it there. data: { stops = { { x, y, num }, ...
-- }, via = { the arrow's step, an objective's spot: { x, y }, those there are, in that order }, you = { x, y } or nil,
-- tv (Target.lua's T.ver when drawn) }
local Lines = {}
function Lines:Fit(canvas)
  local d, map, MR = self.data, self.layer:GetMap(), QB.MiniRoute
  if not (d and map) then return end
  local w, h = canvas:GetWidth() or 0, canvas:GetHeight() or 0
  self:SetSize(w, h)
  -- (a stroke stops short of its pin's disc, drawn at the icon scale: P.IconScale)
  local thick, size = LINE_W / canvasScale(map), P.ROUTE.size * P.IconScale() * P.PinScale(map, P.ROUTE.scale)
  local ctx = self.ctx or { frame = self, lines = {}, square = true }
  self.ctx = ctx
  ctx.used, ctx.strokes, ctx.r = 0, 0, max(w, h)
  -- the quest icons on the page (QuestMap.lua's and Pins.lua's layers), each { x, y, r } in this frame's units: a stroke
  -- crossing one it doesn't join is softened there, and only there (MR.Stroke). Strokes are drawn under every pin (the
  -- canvas's frame levels, MP.Levels: the quest blob's under the offers' and the quests')
  local marks, nm = self.marks or {}, 0
  self.marks = marks
  local r = size * 0.5
  for _, layer in ipairs({ QB.QuestMap.pageProvider, P.pageProvider }) do
    for _, f in ipairs(layer and layer.active or {}) do
      local fx, fy = f.qX or f.mapX, f.qY or f.mapY
      if fx and fy then
        nm = nm + 1
        local m = marks[nm] or {}
        marks[nm] = m
        m.x, m.y, m.r = (fx - 0.5) * w, (0.5 - fy) * h, r
      end
    end
  end
  for i = nm + 1, #marks do marks[i] = nil end
  -- a stroke from a to b: a gap off the pin at each end (from you, your arrow's), softened over another icon
  local function stroke(a, b, col, alpha, fromYou)
    local x1, y1, x2, y2, cut = clipRect((a.x - 0.5) * w, (0.5 - a.y) * h, (b.x - 0.5) * w, (0.5 - b.y) * h, w / 2, h / 2)
    if not x1 then return end
    local cut0 = math.abs(x1 - (a.x - 0.5) * w) + math.abs(y1 - (0.5 - a.y) * h) > 0.5
    MR.Stroke(ctx, x1, y1, x2, y2, col, thick, alpha, cut and 0 or size, cut0 and 0 or (fromYou and MR.YOU / canvasScale(map) or size),
      marks, nm, thick * 0.5)
  end
  -- you, then the step and the spot on the way, then stop 1 (the first stroke gold, the rest blue); then stop to stop.
  -- A stroke with both ends off this map is left out: it would cross the map touching neither
  local gold, blue = QB.Mini.GOLD, QB.Mini.BLUE
  local function inside(p) return p.x >= 0 and p.x <= 1 and p.y >= 0 and p.y <= 1 end
  local prev, col, alpha = d.you, gold, 1
  local function to(p)
    if prev and (inside(prev) or inside(p)) then stroke(prev, p, col, alpha, prev == d.you) end
    prev, col, alpha = p, blue, 0.85
  end
  for _, p in ipairs(d.via) do to(p) end
  local s = d.stops
  if s[1] and s[1].num == 1 then to(s[1]) end
  for i = 2, #s do
    if s[i].num == s[i - 1].num + 1 and (inside(s[i - 1]) or inside(s[i])) then stroke(s[i - 1], s[i], blue, 0.85) end
  end
  MR.HideFrom(ctx, ctx.used + 1)
end
local LINES = { level = "PIN_FRAME_LEVEL_QUEST_BLOB", mouse = false, methods = Lines }

-- the arrow's step toward the one target (while the arrow leads elsewhere its step is a pin of its own, drawStep), and
-- the target's objective spot or the hand-in in reach before stop 1 (a stop target is stop 1's own pin): on map m in
-- fractions, beyond its edge too. (Your place read into one table: the page's tick asks four times a second)
local herePos = {}
local function viaOn(m)
  local out, T = {}, QB.Target
  if not T then return out end
  local t = T.Get(QB.API.WorldPosition(nil, herePos))
  local s, via = T.Step()
  if not via then s = nil end
  for _, p in ipairs({ s or false, (t and (t.obj or t.near)) and t or false }) do
    if p then
      local x, y = nil, nil
      if p ~= s and p.m then x, y = P.Project(p, m) end
      if not x then x, y = fracOf(m, p.c, p.wx, p.wy) end
      if x then out[#out + 1] = { x = x, y = y } end
    end
  end
  return out
end

local function drawLines(layer, m)
  if MP.frame then MP.Strip() end -- (the route's count: the route has just changed)
  if not P.RouteOn(false) then return end
  local stops = {}
  for _, d in ipairs(P.list) do
    local x, y = nil, nil
    if d.num then x, y = spotOn(d, m) end
    if x then stops[#stops + 1] = { x = x, y = y, num = d.num } end
  end
  table.sort(stops, function(a, b) return a.num < b.num end)
  local via = viaOn(m)
  local T = QB.Target
  if #stops > 0 or #via > 0 then layer:Add(LINES, { stops = stops, via = via, you = youOn(m), tv = T and T.ver }, 0.5, 0.5) end
end

-- the arrow's step (a flight master, a pier, the tram) where it sends you first: its own icon on the game's POI pin,
-- lit with the game's glow
local Step = {}
function Step:Setup(d)
  P.StyleMark(self, d.atlas, d.icon, 24)
  self.Badge:Hide()
  self.Count:Hide()
end
Step.OnMouseEnter = QB.Safe(function(self) tip(self, self.data.name, "Where the arrow sends you first.", "ANCHOR_RIGHT") end, "map page step")
Step.OnMouseLeave = untip
local STEP = { template = "QuestBankMarkTemplate", level = "PIN_FRAME_LEVEL_AREA_POI", scale = { 1, 1.0, 1.2 }, mouse = true, methods = Step, size = 24 }

-- the step now (the arrow's, whatever it leads to: Target.lua's T.Step), and a key that changes when it does or when
-- it comes on or off the way to the one target (the strokes go by it then)
local function stepNow()
  local s, via
  if QB.Target then s, via = QB.Target.Step() end
  return s, s and string.format("%s:%d:%d:%s", s.name or "", floor(s.wx), floor(s.wy), via and "on" or "off") or false
end

local function drawStep(layer, m)
  local s, key = stepNow()
  MP.stepKey = key
  local x, y = nil, nil
  if s and P.RouteOn(false) then x, y = QB.Model.MapPos(s.c, s.wx, s.wy, m) end
  if x then layer:Add(STEP, { name = s.name or "Next step", atlas = s.atlas, icon = s.icon }, x, y) end
end

-- the flight points as the game's own pins (FlightPointDataProvider): the taxi node atlas at its 21 px, no tooltip:
-- hovered, the pin's name (and "Undiscovered ... Flightpoint") goes into the map's own area label, as the game's does
-- (SetAreaLabel, which the page's AreaLabelDataProvider shows); a click is a waypoint, as the game's super-tracks
local Flight = {}
local LABEL_POI = function() return MAP_AREA_LABEL_TYPE and MAP_AREA_LABEL_TYPE.POI or 4 end
function Flight:Setup(d)
  P.StyleMark(self, d.atlas, d.file)
  self.Badge:Hide()
  self.Count:Hide()
end
Flight.OnMouseEnter = QB.Safe(function(self)
  local d, map = self.data, self.layer:GetMap()
  if d and map and map.TriggerEvent then QB.Try("map page flight", map.TriggerEvent, map, "SetAreaLabel", LABEL_POI(), d.name, d.desc) end
end, "map page flight")
Flight.OnMouseLeave = QB.Safe(function(self)
  local map = self.layer:GetMap()
  if map and map.TriggerEvent then QB.Try("map page flight", map.TriggerEvent, map, "ClearAreaLabel", LABEL_POI()) end
end, "map page flight")
function Flight:OnMouseClickAction(button)
  local d = self.data
  if d and button ~= "RightButton" then QB.API.SetWaypoint(d.m, d.x * 100, d.y * 100, d.name) end
end
local FLIGHT = { template = "QuestBankMarkTemplate", level = "PIN_FRAME_LEVEL_FLIGHT_POINT", scale = { 1, 1.0, 1.2 }, mouse = true, methods = Flight, size = 21 }

-- the game's words for a flight point not found yet: "Undiscovered Alliance Flightpoint", or the neutral one
local function undiscovered(faction)
  local E = Enum and Enum.FlightPathFaction
  local side = faction == (E and E.Alliance or 2) and P.Word("FACTION_ALLIANCE", "Alliance") or faction == (E and E.Horde or 1) and P.Word("FACTION_HORDE", "Horde") or nil
  if side then return string.format(P.Word("UNDISCOVERED_FACTION_FLIGHTPOINT", "Undiscovered %s Flightpoint"), side) end
  return P.Word("UNDISCOVERED_NEUTRAL_FLIGHTPOINT", "Undiscovered Flightpoint")
end

-- the flight paths on map m (a zone, a city or a continent): the world map's own (C_TaxiMap, with their art, the other
-- faction's left out), else QuestBank's flight masters of your faction (Data.lua's D.HUB) on this map or a zone of it,
-- found or not as the arrow knows (Travel.lua). Each { m, x, y, name, known, atlas, file, desc }
function MP.Flights(m)
  local out = {}
  local i = info(m)
  if not (QB.QuestMap.Draws(m) or (i and QB.Plain(i.mapType) == CONTINENT)) then return out end
  local E = Enum and Enum.FlightPathFaction
  local theirs = QB.faction == "H" and (E and E.Alliance or 2) or (E and E.Horde or 1)
  local ok, nodes = false, nil
  if C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, m) end
  for _, n in ipairs(ok and type(QB.Plain(nodes)) == "table" and nodes or {}) do
    local pos = type(n) == "table" and QB.Plain(n.position)
    local x, y = pos and QB.Plain(pos.x), pos and QB.Plain(pos.y)
    if type(x) == "number" and type(y) == "number" and QB.Plain(n.faction) ~= theirs then
      local known = QB.Plain(n.isUndiscovered) ~= true
      local atlas, kit = QB.Plain(n.atlasName), QB.Plain(n.textureKit)
      if type(atlas) == "string" and type(kit) == "string" then atlas = kit .. "-" .. atlas end
      local side = QB.Plain(n.faction)
      out[#out + 1] = { m = m, x = x, y = y, name = QB.Plain(n.name) or "Flight path", known = known, desc = not known and undiscovered(side) or nil,
                        atlas = type(atlas) == "string" and atlas or (known and (QB.faction == "H" and "taxinode_horde" or "taxinode_alliance") or "taxinode_undiscovered"), file = known and T.taxiY or T.taxiGray }
    end
  end
  if #out > 0 then return out end
  local fac, TV = QB.faction, QB.Travel
  for k, h in ipairs(QB.Data.HUB[fac] or {}) do
    local zone = info(h[7])
    local x, y = nil, nil
    -- (flags: 1 no flights, 4 a world-PvP tower; 2 druids only, as TV.Usable says)
    if h[10] ~= 1 and h[10] ~= 4 and (h[10] ~= 2 or TV.Usable(fac, k)) and (h[7] == m or (zone and QB.Plain(zone.parentMapID) == m)) then
      x, y = P.Project({ m = h[7], x = h[8], y = h[9] }, m)
    end
    if x then
      local known = TV.Usable(fac, k)
      out[#out + 1] = { m = m, x = x, y = y, name = h[1], known = known, desc = not known and undiscovered(fac == "H" and 1 or 2) or nil,
                        atlas = known and (fac == "H" and "taxinode_horde" or "taxinode_alliance") or "taxinode_undiscovered", file = known and T.taxiY or T.taxiGray }
    end
  end
  return out
end

local function drawFlights(layer, m)
  if QB:Settings().mapFlights == false then return end
  for _, d in ipairs(MP.Flights(m)) do layer:Add(FLIGHT, d, d.x, d.y) end
end

-- does a pin's data hold quest id: a ! or ? (its quests, and a ?'s pick-ups), a mark (its quest), a route pin (its ids)
local function holds(d, id)
  if not (d and id) then return false end
  if d.id == id or (d.ids and d.ids[id]) then return true end
  for _, q in ipairs(d.quests or {}) do if q.id == id then return true end end
  for _, q in ipairs(d.offers or {}) do if q.id == id then return true end end
  return false
end

-- the light under a pin of the quest hovered in the list, or picked there (the layers' lit, Pins.lua)
function MP.Lit(d)
  if holds(d, MP.hover) or holds(d, MP.focus) then return LIT end
  return nil
end

-- every pin lit again (the quest hovered or picked changed)
function MP.Glow()
  for _, layer in ipairs({ QB.QuestMap.pageProvider, P.pageProvider }) do
    for _, f in ipairs(layer and layer.active or {}) do P.Glow(f, MP.Lit(f.data)) end
  end
end

-- The page's own canvas orders its pins as the world map does (Blizzard_WorldMap.lua, AddStandardDataProviders): the
-- explored areas, the quests' blue areas (and the route's strokes, on that level), the zone's highlight, the dungeon
-- entrances, the flight points, the arrow's step, the quest offers, the quests, the super-tracked one, your party. A
-- bare canvas has one level for every pin (PIN_FRAME_LEVEL_DEFAULT), and 5.4.3's gold stroke could cover a ! or a ?
-- (the owner: "hard to see quests with the yellow line"). Its own manager, QuestBank's canvas: nothing of the game's
local LEVELS = { { "PIN_FRAME_LEVEL_MAP_EXPLORATION" }, { "PIN_FRAME_LEVEL_QUEST_BLOB" }, { "PIN_FRAME_LEVEL_MAP_HIGHLIGHT" },
  { "PIN_FRAME_LEVEL_DUNGEON_ENTRANCE" }, { "PIN_FRAME_LEVEL_FLIGHT_POINT" }, { "PIN_FRAME_LEVEL_AREA_POI" },
  { "PIN_FRAME_LEVEL_QUEST_OFFER", 200 }, { "PIN_FRAME_LEVEL_ACTIVE_QUEST", 60 }, { "PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST" },
  { "PIN_FRAME_LEVEL_GROUP_MEMBER" } }
MP.LEVELS = LEVELS
function MP.Levels(canvas)
  local mgr = canvas.GetPinFrameLevelsManager and canvas:GetPinFrameLevelsManager()
  if type(mgr) ~= "table" or type(mgr.AddFrameLevel) ~= "function" then return false end
  for _, l in ipairs(LEVELS) do pcall(mgr.AddFrameLevel, mgr, l[1], l[2]) end
  return true
end

-- the canvas, once, out of combat: Blizzard's providers make their pins as they are added, and a pin made in a fight
-- calls a protected function (SetPassThroughButtons) as QuestBank. Built hidden on a holder of its own, as the
-- templates would build it, and put into the page when the page first shows (MP.Place)
local function build()
  if MP.canvas or not MP.Available() then return end
  if QB.Pins.InCombat() then MP.events:RegisterEvent("PLAYER_REGEN_ENABLED"); return end
  MP.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
  local holder = CreateFrame("Frame", nil, UIParent)
  holder:SetSize(MAP_W - 4, MAP_H - 4)
  holder:SetPoint("CENTER")
  holder:Hide()
  local canvas = CreateFrame("Frame", "QuestBankMapCanvas", holder)
  Mixin(canvas, MapCanvasMixin, Canvas)
  canvas:SetSize(MAP_W - 4, MAP_H - 4)
  canvas:SetPoint("TOPLEFT")
  -- the two children MapCanvasMixin reads (its template declares them): the scroll frame with the map on its child,
  -- over the whole canvas, and the frame its lock reasons give the mouse to
  canvas.ScrollContainer = CreateFrame("ScrollFrame", nil, canvas, "MapCanvasFrameScrollContainerTemplate")
  canvas.ScrollContainer:ClearAllPoints()
  canvas.ScrollContainer:SetAllPoints(canvas)
  canvas.BorderFrame = CreateFrame("Frame", nil, canvas)
  canvas.BorderFrame:SetAllPoints(canvas)
  canvas:OnLoad()
  MP.Levels(canvas)
  for _, s in ipairs({ "OnUpdate", "OnShow", "OnHide", "OnEvent" }) do canvas:SetScript(s, canvas[s]) end
  canvas:SetFrameStrata("MEDIUM")
  -- a click into a zone opens it, a right-click goes up to its parent; the wheel zooms and a drag pans
  canvas:SetShouldNavigateOnClick(true)
  canvas:SetShouldZoomInOnClick(false)
  canvas:SetShouldPanOnClick(false)
  for _, name in ipairs(BLIZZARD) do canvas:AddDataProvider(CreateFromMixins(_G[name])) end
  local QM = QB.QuestMap
  QM:AddTo(canvas)
  P.AddTo(canvas)
  MP.lines = P.NewLayer(drawLines, "map page lines", canvas)
  MP.step = P.NewLayer(drawStep, "map page step", canvas)
  MP.flight = P.NewLayer(drawFlights, "map page flights", canvas)
  -- the strokes and the step follow the route as its pins do; the quest hovered or picked in the list is lit
  P.pageLayers[#P.pageLayers + 1] = MP.lines
  P.pageLayers[#P.pageLayers + 1] = MP.step
  QM.pageProvider.lit, P.pageProvider.lit, MP.step.lit = MP.Lit, MP.Lit, function() return STEP_LIT end
  MP.layers = { QM.pageProvider, P.pageProvider, MP.lines, MP.step, MP.flight }
  canvas:AddCanvasClickHandler(canvasClick)
  MP.canvas = canvas
  -- your zone now, hidden: its art loads and QuestBank's layers make their frames (they make none in a fight), so a
  -- first open in one shows them
  MP.Go(playerMap(), "here")
  if MP.frame then MP.Place() end -- the page was opened first (in the fight): the map goes in now
end

-- the zone you are in, while the map follows you; the end of the fight the canvas waited for
MP.events = CreateFrame("Frame")
MP.events:SetScript("OnEvent", QB.Safe(function(_, event)
  if event == "PLAYER_REGEN_ENABLED" then build()
  elseif MP.follow then MP.Go(playerMap(), "follow") end
end, "map page"))

-- at login (Core.lua): the canvas as soon as Blizzard's map code is loaded
function MP:Init()
  if MP.waiting or not QB.QuestMap.Available() then return end
  MP.events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
  MP.waiting = QB.Pins.WhenMap(QB.Safe(build, "map page"), "map page: waiting for the map") or true
end

----------------------------------------------------------------------------
-- going places
----------------------------------------------------------------------------
-- show a map, one with art (the scroll container reads a map's art unchecked; a map without any, as the world map
-- can be, is never shown: a player asking for one is told). why: "user" (a crumb, a menu, /qb map) stops following
-- you; "here" and "follow" follow
function MP.Go(mapID, why)
  local canvas = MP.canvas
  if not canvas then return false end
  if not hasArt(mapID) then
    if why == "user" then
      local i = info(mapID)
      QB:Print(string.format("%s has no map art on this client.", i and QB.Plain(i.name) or "That map"))
    end
    return false
  end
  MP.follow = why ~= "user"
  MP.going = true
  QB.Try("map page", setMap, canvas, mapID)
  MP.going = false
  return true
end
MP.HasArt = hasArt

-- your zone, and the map follows you again
function MP.Here()
  MP.follow = true
  MP.Go(playerMap(), "here")
  MP.Update()
end

-- the canvas has a new map (Canvas:OnMapChanged): one QuestBank didn't ask for is a click into a zone or out to its
-- parent, and the map stays there
function MP.MapChanged()
  if not MP.going then MP.follow = false end
  MP.Update()
end

-- the zones in a map that have art of their own, by name: a continent's on the world map, a zone's on a continent
function MP.Children(mapID)
  local out = {}
  if not (C_Map and C_Map.GetMapChildrenInfo) then return out end
  local ok, kids = pcall(C_Map.GetMapChildrenInfo, mapID)
  for _, k in ipairs(ok and type(kids) == "table" and kids or {}) do
    local id = QB.Plain(k.mapID)
    if hasArt(id) and (QB.Plain(k.mapType) == CONTINENT or QB.QuestMap.Draws(id)) then out[#out + 1] = { id = id, name = QB.Plain(k.name) or "?" } end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- /qb map <name>: the zone of that name, or the shortest that has it in its name
function MP.Find(text)
  text = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
  local best, bestName
  for id, name in pairs(QB.Data.MAPNAME or {}) do
    local n = name:lower()
    if n == text then return id end
    if text ~= "" and n:find(text, 1, true) and (not bestName or #name < #bestName) then best, bestName = id, name end
  end
  return best
end

local function menuOK() return MenuUtil and MenuUtil.CreateContextMenu and true or false end

-- a crumb's menu: the zones in it
function MP.ChildMenu(owner, mapID)
  local kids = MP.Children(mapID)
  if #kids == 0 or not menuOK() then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    for _, k in ipairs(kids) do root:CreateButton(k.name, function() MP.Go(k.id, "user") end) end
  end)
end

-- the journal's dungeons whose entrance is on this map, or on a continent in one of its zones, by level
function MP.Dungeons(mapID)
  local out = {}
  for _, c in ipairs(QB.DMap.List()) do
    local e = c.entrance
    local parent = e and info(e.m)
    if e and (e.m == mapID or (parent and QB.Plain(parent.parentMapID) == mapID)) then out[#out + 1] = c end
  end
  return out
end

-- a right-click on the map: zoom out to the map it lies in (what the game's right-click does), the game's own world
-- map, your zone, a waypoint where you clicked. m, x, y: the map and the fraction of it under the mouse
function MP.MapMenu(owner, m, x, y)
  if not menuOK() then return end
  local i = info(m)
  local parent = i and QB.Plain(i.parentMapID)
  local up = type(parent) == "number" and parent > 0 and info(parent) or nil
  MenuUtil.CreateContextMenu(owner, function(_, root)
    if up then
      if hasArt(parent) then root:CreateButton("Zoom out to " .. (QB.Plain(up.name) or "the map above"), function() MP.Go(parent, "user") end)
      else root:CreateButton((QB.Plain(up.name) or "The map above") .. ": no map art", function() end) end
    end
    root:CreateButton("Game's map", function() QB.UI.OpenMap() end)
    root:CreateButton("Your zone", function() MP.Here() end)
    if type(x) == "number" and type(y) == "number" then
      root:CreateButton("Waypoint here", function() QB.Try("map page menu", QB.API.SetWaypoint, m, x * 100, y * 100, "Map") end)
    end
  end)
end

-- the Dungeons button: one picked opens in the Dungeon Journal
function MP.DungeonMenu(owner)
  local list = MP.Dungeons(shownMap())
  if #list == 0 or not menuOK() then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    for _, c in ipairs(list) do
      local lv = QB.DMap.Levels(c.key)
      root:CreateButton(lv[1] > 0 and string.format("%s  %d-%d", c.name, lv[1], lv[2]) or c.name, function() QB.DMap.Open(c) end)
    end
  end)
end

----------------------------------------------------------------------------
-- the page
----------------------------------------------------------------------------
-- a 24 px button with the game's icon, and its word in the tooltip
local function iconButton(parent, atlas, file, title, about)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(24, 24)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  QB.Art(b.icon, atlas, file)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetScript("OnEnter", function(self) tip(self, title, self.about or about) end)
  b:SetScript("OnLeave", untip)
  return b
end

local function textWidth(t) return (t.GetUnboundedStringWidth or t.GetStringWidth)(t) or 0 end

-- a crumb: a click opens its map; on the map shown already, or with the right button, its zones. A map without art
-- on this client (the world map can be one) can't be shown: its crumb is greyed and says so, and still gives its zones
local function crumb(f, i)
  local b = QB.DMap.Pill(f.nav, "", 80)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(self, button)
    if button == "RightButton" or self.last or self.noArt then MP.ChildMenu(self, self.mapID) else MP.Go(self.mapID, "user") end
  end)
  b:SetScript("OnEnter", function(self)
    tip(self, self.text:GetText(), self.noArt and "No map art for it on this client. Click: the zones in it."
      or (self.last and "Click: the zones in it." or "Click: open it. Right-click: the zones in it."))
  end)
  b:SetScript("OnLeave", untip)
  f.crumbs[i] = b
  return b
end

local function separator(f, i)
  local s = QB.DMap.Text(f.nav, "GameFontNormal", 12, SOFT, SEP_W, "CENTER")
  s:SetText(">")
  f.seps[i] = s
  return s
end

-- a layer's switch under the map: the game's icon (the route's the super-tracked disc) and how many there are
-- on this map; off, greyed. Its tooltip gives the word
local function layerOn(t)
  local set = QB:Settings()
  return not (t.icons and set.mapIcons == false) and set[t.key] ~= false
end

local function toggle(f, t, i)
  local DM = QB.DMap
  local b = CreateFrame("Button", nil, f.strip)
  b:SetSize(TOGGLE_W, 24)
  b:SetPoint("RIGHT", f.strip, "RIGHT", -4 - (#TOGGLES - i) * (TOGGLE_W + 2), 0)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(20, 20)
  b.icon:SetPoint("LEFT", 0, 0)
  QB.Art(b.icon, t.atlas, t.file)
  if t.num then
    b.num = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.num:SetPoint("CENTER", b.icon, "CENTER", 0, 0)
    b.num:SetText(t.num)
  end
  b.count = DM.Text(b, "GameFontNormal", 12, INK, TOGGLE_W - 22)
  b.count:SetPoint("LEFT", 22, 0)
  b.t = t
  b:SetHighlightTexture(T.rowHi, "ADD")
  b:SetScript("OnClick", function() MP.ToggleLayer(t.key) end)
  b:SetScript("OnEnter", function(self)
    tip(self, t.name, layerOn(t) and "On the map. Click: hide them." or "Hidden. Click: show them on the map.", "ANCHOR_TOP")
  end)
  b:SetScript("OnLeave", untip)
  return b
end

-- a section's header in the list: the game's campaign header mark (open or folded), the kind's icon, its word and
-- count; To pick up has "+ all", as the Available page's places have
local function header(f, s)
  local DM = QB.DMap
  local h = CreateFrame("Button", nil, f.list.child)
  h:SetSize(LIST_W, HEAD_H)
  h.caret = h:CreateTexture(nil, "ARTWORK")
  h.caret:SetSize(14, 14)
  h.caret:SetPoint("LEFT", 2, 0)
  h.icon = h:CreateTexture(nil, "ARTWORK")
  h.icon:SetSize(16, 16)
  h.icon:SetPoint("LEFT", 20, 0)
  QB.Art(h.icon, s.atlas, s.file)
  h.label = DM.Text(h, "GameFontNormal", 12, GOLD, LIST_W - 40 - 34 - (s.list == "pickup" and 42 or 0))
  h.label:SetPoint("LEFT", 40, 0)
  h.label:SetText(s.name)
  h.count = DM.Text(h, "GameFontNormal", 12, INK, 30, "RIGHT")
  h.count:SetPoint("RIGHT", -4, 0)
  h:SetScript("OnClick", function()
    MP.fold[s.list] = not MP.fold[s.list] or nil
    MP.FillPanel(true)
  end)
  h:SetScript("OnEnter", function(self) tip(self, s.name, MP.fold[s.list] and "Click: show the list." or "Click: fold the list.", "ANCHOR_LEFT") end)
  h:SetScript("OnLeave", untip)
  if s.list == "pickup" then
    h.all = CreateFrame("Button", nil, h)
    h.all:SetSize(36, 16)
    h.all:SetPoint("RIGHT", -38, 0)
    h.all.label = DM.Text(h.all, "GameFontNormalSmall", 11, GOLD, 36, "RIGHT")
    h.all.label:SetPoint("RIGHT", 0, 0)
    h.all.label:SetText("+ all")
    h.all:SetHighlightTexture(T.rowHi, "ADD")
    h.all:SetScript("OnClick", QB.Safe(function(self)
      for _, id in ipairs(self.ids or {}) do QB:SetAdded(id, true) end
      QB.UI:Refresh()
    end, "map page: pick up all here"))
    h.all:SetScript("OnEnter", function(self)
      tip(self, string.format("Pick up all %d here", #(self.ids or {})), "Puts every quest you can pick up here on your pick-up list.", "ANCHOR_LEFT")
    end)
    h.all:SetScript("OnLeave", untip)
  end
  f.heads[s.list] = h
  return h
end

-- the box on a pick-up row (shown while the mouse is on the row, and kept while it is ticked), and the row's wash:
-- gold while ticked, blue while it is the quest shown on the map
local function showBox(r, hover)
  local id = r.it and r.it.q.id
  local ticked = (r.pick and id and MP.sel[id]) and true or false
  r.sel:SetShown((r.pick and (hover or ticked)) and true or false)
  r.sel.check:SetShown(ticked)
  local wash = ticked and PICKED or (id and id == MP.focus and FOCUSED) or nil
  if wash then r.wash:SetVertexColor(wash[1], wash[2], wash[3], wash[4]) end
  r.wash:SetShown(wash and true or false)
end

local function mouseOn(f) return f.IsMouseOver and f:IsMouseOver() or false end

-- a quest's row: its icon, its title in the game's colour for its level, its XP; hovered, its pins light and the game
-- shows its area; a click shows it on the map, a right-click QuestBank's menu for it, Ctrl-click or the box (to pick
-- up) selects it
local function makeRow(f)
  local DM = QB.DMap
  local r = CreateFrame("Button", nil, f.list.child)
  r:SetSize(LIST_W, ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.wash = r:CreateTexture(nil, "BACKGROUND")
  r.wash:SetTexture(FLAT)
  r.wash:SetAllPoints()
  r.wash:Hide()
  r.hi = r:CreateTexture(nil, "HIGHLIGHT")
  r.hi:SetTexture(T.rowHi)
  r.hi:SetAllPoints()
  r.hi:SetBlendMode("ADD")
  r.hi:SetAlpha(0.6)
  -- shown from the map (MP.Reveal): lit, fading
  r.flash = r:CreateTexture(nil, "OVERLAY")
  r.flash:SetTexture(T.rowHi)
  r.flash:SetAllPoints()
  r.flash:SetBlendMode("ADD")
  r.flash:Hide()
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(18, 18)
  r.icon:SetPoint("LEFT", 4, 0)
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.name = DM.Text(r, "GameFontNormal", 12, INK, NAME_W)
  r.name:SetPoint("LEFT", 28, 0)
  r.xp = DM.Text(r, "GameFontNormal", 12, INK, 44, "RIGHT")
  r.xp:SetPoint("RIGHT", -4, 0)
  -- the game's own check box over the icon
  r.sel = CreateFrame("Button", nil, r)
  r.sel:SetSize(18, 18)
  r.sel:SetPoint("LEFT", 4, 0)
  r.sel.box = r.sel:CreateTexture(nil, "ARTWORK")
  r.sel.box:SetAllPoints()
  QB.Art(r.sel.box, "checkbox-minimal", "Interface\\Buttons\\UI-CheckBox-Up")
  r.sel.check = r.sel:CreateTexture(nil, "OVERLAY")
  r.sel.check:SetAllPoints()
  QB.Art(r.sel.check, "checkmark-minimal", "Interface\\Buttons\\UI-CheckBox-Check")
  r.sel:Hide()
  r.sel:SetScript("OnClick", QB.Safe(function(self) MP.Select(self:GetParent().it.q.id) end, "map page: select"))
  r.sel:SetScript("OnEnter", function(self)
    tip(self, MP.sel[self:GetParent().it.q.id] and "Selected" or "Select", "Pick up several at once, from the bar below. Ctrl-click a row does the same.", "ANCHOR_LEFT")
  end)
  r.sel:SetScript("OnLeave", function(self)
    untip()
    local row = self:GetParent()
    if not mouseOn(row) then showBox(row, false) end
  end)
  r:SetScript("OnClick", QB.Safe(function(self, button)
    local it = self.it
    if not it then return end
    if button == "RightButton" then QB.UI.QuestMenu(it.q, it.st) return end
    if self.pick and IsControlKeyDown and IsControlKeyDown() then MP.Select(it.q.id) return end
    MP.Focus(it.q.id)
  end, "map page: row"))
  r:SetScript("OnEnter", QB.Safe(function(self)
    local it = self.it
    if not it then return end
    MP.Hover(it.q.id)
    showBox(self, true)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    QB.UI.QuestTooltip(GameTooltip, it.q, it.st, it.xp)
    GameTooltip:AddLine(MP.focus == it.q.id and "Click: let it go. Right-click: more." or "Click: show it on the map. Right-click: more.", 0.5, 0.5, 0.5, true)
    if self.pick then GameTooltip:AddLine("Ctrl-click: select it, to pick up several at once.", 0.5, 0.5, 0.5, true) end
    GameTooltip:Show()
  end, "map page: row tooltip"))
  r:SetScript("OnLeave", function(self)
    MP.Hover(nil)
    untip()
    if not mouseOn(self.sel) then showBox(self, false) end
  end)
  return r
end

local function fillRow(r, it, pick)
  local q = it.q
  r.it, r.pick = it, pick or nil
  r.icon:SetTexture(q.icon or T.questGeneric)
  local c = GetQuestDifficultyColor and select(2, pcall(GetQuestDifficultyColor, q.lvl or 1))
  if type(c) ~= "table" then c = { r = GOLD[1], g = GOLD[2], b = GOLD[3] } end
  r.name:SetTextColor(c.r or 1, c.g or 1, c.b or 1)
  QB.UI.FitText(r.name, q.name)
  r.xp:SetText(QB.Short(it.xp))
  showBox(r, mouseOn(r))
end

local function buildPage(page)
  local DM = QB.DMap
  local f = CreateFrame("Frame", nil, page)
  f:SetAllPoints(page)
  -- the nav bar: crumbs from the left; Here, the dungeons and the game's map on the right
  f.nav = CreateFrame("Frame", nil, f)
  f.nav:SetPoint("TOPLEFT", 0, 0)
  f.nav:SetSize(MAP_W, NAV_H)
  f.crumbs, f.seps = {}, {}
  -- the game's own world map, by name: the map key story is in its tooltip (MP.KEYS)
  f.game = DM.Pill(f.nav, "Game's map", 88)
  f.game:SetPoint("RIGHT", -4, 0)
  f.game:SetScript("OnClick", function() QB.UI.OpenMap() end)
  f.game:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Game's map", GOLD[1], GOLD[2], GOLD[3])
    GameTooltip:AddLine("The game's own world map on your zone, with QuestBank's route and icons on it.", 1, 1, 1, true)
    GameTooltip:AddLine(MP.KEYS, 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  f.game:SetScript("OnLeave", untip)
  f.dungeons = iconButton(f.nav, "Dungeon", QB.QuestMap.ART.dungeon.file, "Dungeons", "The dungeons whose entrance is on this map.")
  f.dungeons:SetPoint("RIGHT", f.game, "LEFT", -4, 0)
  f.dungeons:SetScript("OnClick", function(self) MP.DungeonMenu(self) end)
  f.here = iconButton(f.nav, "Waypoint-MapPin-Tracked", T.mapPin, "Here", "Your zone; the map follows you again.")
  f.here:SetPoint("RIGHT", f.dungeons, "LEFT", -4, 0)
  f.here:SetScript("OnClick", function() MP.Here() end)
  -- the map in a frame of its own; until the canvas is built, a word on why
  f.map = DM.Panel(f, 0.9)
  f.map:SetPoint("TOPLEFT", 0, -(NAV_H + 4))
  f.map:SetSize(MAP_W, MAP_H)
  f.later = DM.Text(f.map, "GameFontNormal", 12, SOFT, MAP_W - 40, "CENTER")
  f.later:SetPoint("CENTER")
  -- under it, the zone and its levels, and the layers' switches
  f.strip = CreateFrame("Frame", nil, f)
  f.strip:SetPoint("TOPLEFT", f.map, "BOTTOMLEFT", 0, -6)
  f.strip:SetSize(MAP_W, STRIP_H)
  local textW = MAP_W - 4 - #TOGGLES * (TOGGLE_W + 2) - 16
  f.zone = DM.Text(f.strip, "GameFontNormalLarge", 16, GOLD, textW)
  f.zone:SetPoint("TOPLEFT", 8, -6)
  f.levels = DM.Text(f.strip, "GameFontNormal", 12, INK, textW)
  f.levels:SetPoint("TOPLEFT", 8, -28)
  f.toggles = {}
  for i, t in ipairs(TOGGLES) do f.toggles[i] = toggle(f, t, i) end
  -- beside it, the zone's quests in a list that scrolls: a section for each kind, a row for each quest
  f.panel = DM.Panel(f, 0.6)
  f.panel:SetPoint("TOPLEFT", MAP_W + GAP, 0)
  f.panel:SetPoint("BOTTOMRIGHT", 0, 0)
  f.list = DM.Scroller(f.panel, ROW_H, PAGE_H - 16)
  f.list:SetPoint("TOPLEFT", 8, -8)
  f.list:SetPoint("BOTTOMRIGHT", -20, 8)
  f.list.child:SetWidth(LIST_W)
  f.heads, f.rows = {}, {}
  for _, s in ipairs(SECTIONS) do header(f, s) end
  f.empty = DM.Text(f.panel, "GameFontNormal", 12, SOFT, PANEL_W - 24, "CENTER")
  f.empty:SetPoint("TOP", 0, -24)
  -- several quests to pick up at once: Ctrl-click rows or tick their box, then pick them all up
  f.bar = DM.Panel(f.panel, 0.95)
  f.bar:SetPoint("BOTTOMLEFT", 6, 6)
  f.bar:SetPoint("BOTTOMRIGHT", -6, 6)
  f.bar:SetHeight(SEL_H)
  f.bar.pick = CreateFrame("Button", nil, f.bar, "UIPanelButtonTemplate")
  f.bar.pick:SetSize(130, 22)
  f.bar.pick:SetPoint("LEFT", 8, 0)
  f.bar.pick:SetScript("OnClick", QB.Safe(function()
    for id in pairs(MP.sel) do QB:SetAdded(id, true) end
    MP.sel = {}
    QB.UI:Refresh()
  end, "map page: pick up all"))
  f.bar.pick:SetScript("OnEnter", function(self) tip(self, "Pick up all", "Puts the selected quests on your pick-up list.", "ANCHOR_TOP") end)
  f.bar.pick:SetScript("OnLeave", untip)
  f.bar.clear = CreateFrame("Button", nil, f.bar, "UIPanelButtonTemplate")
  f.bar.clear:SetSize(70, 22)
  f.bar.clear:SetPoint("RIGHT", -8, 0)
  f.bar.clear:SetText("Clear")
  f.bar.clear:SetScript("OnClick", function() MP.sel = {}; MP.FillPanel(true) end)
  f.bar:Hide()
  -- while the page shows: your place on the route's first stroke, the arrow's step, a row's light fading
  f:SetScript("OnUpdate", QB.Safe(function(_, dt) MP.Tick(dt) end, "map page"))
  return f
end

-- the canvas into the page's map frame (once it exists), over its border
function MP.Place()
  local f, canvas = MP.frame, MP.canvas
  f.later:SetShown(canvas == nil)
  f.later:SetText(QB.Pins.InCombat() and "Map after the fight" or "No map on this client")
  if not canvas or canvas:GetParent() == f.map then return end
  canvas:SetParent(f.map)
  canvas:ClearAllPoints()
  canvas:SetPoint("TOPLEFT", f.map, "TOPLEFT", 2, -2)
  canvas:SetSize(MAP_W - 4, MAP_H - 4)
  canvas:SetFrameLevel(f.map:GetFrameLevel() + 1)
  canvas:OnFrameSizeChanged()
end

-- the crumbs: the map shown and the maps it lies in, the outermost first
function MP.Crumbs()
  local f = MP.frame
  local chain, id = {}, shownMap()
  for _ = 1, 6 do
    local i = info(id)
    if not i then break end
    table.insert(chain, 1, { id = id, name = QB.Plain(i.name) or "?" })
    id = QB.Plain(i.parentMapID)
    if type(id) ~= "number" or id <= 0 then break end
  end
  local x = 4
  for i, c in ipairs(chain) do
    local b = f.crumbs[i] or crumb(f, i)
    b.mapID, b.last, b.noArt = c.id, i == #chain, not hasArt(c.id)
    b.text:SetText(c.name)
    b:SetAlpha(b.noArt and 0.5 or 1)
    local w = math.min(CRUMB_MAX, math.floor(textWidth(b.text) + 20))
    b:SetWidth(w)
    b.text:SetWidth(w - 8)
    b:ClearAllPoints()
    b:SetPoint("LEFT", f.nav, "LEFT", x, 0)
    b:SetOn(b.last)
    b:Show()
    x = x + w
    if not b.last then
      local s = f.seps[i] or separator(f, i)
      s:ClearAllPoints()
      s:SetPoint("LEFT", f.nav, "LEFT", x, 0)
      s:Show()
      x = x + SEP_W
    end
  end
  for i = #chain + 1, #f.crumbs do f.crumbs[i]:Hide() end
  for i = math.max(#chain, 1), #f.seps do f.seps[i]:Hide() end
end

-- the zone's quests as the panel lists them, { ready, log, pickup } with { q, st, xp } each, most XP first (QuestMap.lua's
-- QM.ZoneQuests, so the list matches the icons), and whether m is a zone (a continent has no list)
local NONE = { ready = {}, log = {}, pickup = {} }
function MP.ZoneQuests(m)
  if not QB.QuestMap.Draws(m) then return NONE, false end
  local out, ready, log, pickup = {}, QB.QuestMap.ZoneQuests(m)
  for key, list in pairs({ ready = ready, log = log, pickup = pickup }) do
    local rows = {}
    for _, q in ipairs(list) do rows[#rows + 1] = { q = q, st = QB:Status(q), xp = QB:Value(q.id) or 0 } end
    table.sort(rows, function(a, b) if a.xp ~= b.xp then return a.xp > b.xp end return a.q.name < b.q.name end)
    out[key] = rows
  end
  return out, true
end

-- how many of the route's pins fall on map m
local function routeCount(m)
  local n = 0
  for _, d in ipairs(P.list) do if P.Project(d, m) then n = n + 1 end end
  return n
end

-- under the map: the zone's name and the levels the game gives it, and each layer's switch with its count
function MP.Strip()
  local f, m = MP.frame, shownMap()
  local i = info(m)
  f.zone:SetText(i and QB.Plain(i.name) or "")
  local ok, lo, hi = false, nil, nil
  if m and C_Map and C_Map.GetMapLevels then ok, lo, hi = pcall(C_Map.GetMapLevels, m) end
  lo, hi = ok and QB.Plain(lo), ok and QB.Plain(hi)
  local known = type(lo) == "number" and type(hi) == "number" and lo > 0
  f.levels:SetText(known and (lo == hi and ("LV " .. lo) or string.format("LV %d-%d", lo, hi)) or "")
  local lists = MP.lists or NONE
  local counts = { ready = #lists.ready, log = #lists.log, pickup = #lists.pickup, route = routeCount(m),
                   dungeons = QB.QuestMap.Draws(m) and #QB.QuestMap.Entrances(m) or 0, flights = #MP.Flights(m) }
  for _, b in ipairs(f.toggles) do
    local on = layerOn(b.t)
    b.count:SetText(tostring(counts[b.t.count]))
    b.icon:SetDesaturated(not on)
    b:SetAlpha(on and 1 or 0.4)
  end
end

-- a switch flipped: one of QuestMap.lua's while its master switch is off turns that one on alone
function MP.ToggleLayer(key)
  local set = QB:Settings()
  for _, t in ipairs(TOGGLES) do
    if t.key == key then
      local on = not layerOn(t)
      if on and t.icons and set.mapIcons == false then
        set.mapIcons = true
        for _, o in ipairs(TOGGLES) do if o.icons then set[o.key] = false end end
      end
      set[key] = on
    end
  end
  MP.RefreshLayers()
  MP.Update()
end

-- every QuestBank layer on the page drawn again, and the world map's icons while it is open (they share the switches)
function MP.RefreshLayers()
  local QM = QB.QuestMap
  if QM.provider and P.MapOpen() then QM.provider:RefreshAllData() end
  for _, layer in ipairs(MP.layers or {}) do
    if P.Shown(layer) then layer:RefreshAllData() end
  end
end

-- beside the map: the zone's quests, ready to hand in, in your log and to pick up, each kind under its header (folded
-- or open) with its count; a continent asks for a zone. keep: the same list again, scrolled where it was
MP.fold, MP.sel = {}, {}
function MP.FillPanel(keep)
  local f, lists = MP.frame, MP.lists or NONE
  local any = MP.zone and (#lists.ready + #lists.log + #lists.pickup) > 0
  -- the selection keeps what can still be picked up here
  local here, selN = {}, 0
  for _, it in ipairs(lists.pickup) do here[it.q.id] = true end
  for id in pairs(MP.sel) do if here[id] then selN = selN + 1 else MP.sel[id] = nil end end
  f.bar:SetShown(selN > 0)
  f.bar.pick:SetText(string.format("Pick up all %d", selN))
  local bottom = selN > 0 and (6 + SEL_H + 4) or 8
  f.list:SetPoint("BOTTOMRIGHT", -20, bottom)
  f.list.viewH = PAGE_H - 8 - bottom
  local y, n = 0, 0
  for _, s in ipairs(SECTIONS) do
    local h, list = f.heads[s.list], lists[s.list]
    h:SetShown(any)
    if any then
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", 0, -y)
      QB.UI.Caret(h.caret, not MP.fold[s.list])
      h.count:SetText(tostring(#list))
      if h.all then
        local ids = {}
        for _, it in ipairs(list) do ids[#ids + 1] = it.q.id end
        h.all.ids = ids
        h.all:SetShown(#ids > 0)
      end
      y = y + HEAD_H
      for _, it in ipairs(MP.fold[s.list] and {} or list) do
        n = n + 1
        local r = f.rows[n] or makeRow(f)
        f.rows[n] = r
        fillRow(r, it, s.list == "pickup")
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        r.top = y
        r:Show()
        y = y + ROW_H
      end
      y = y + 4
    end
  end
  for i = n + 1, #f.rows do f.rows[i]:Hide(); f.rows[i].it = nil end
  f.list:SetContentHeight(y, keep)
  f.empty:SetShown(not any)
  f.empty:SetText(MP.zone and "No quests here" or "Pick a zone")
end

-- Ctrl-click or a row's box: a quest to pick up into the selection, or out of it
function MP.Select(id)
  MP.sel[id] = (not MP.sel[id]) or nil
  MP.FillPanel(true)
end

-- a row hovered: its quest's pins lit, and its areas shown by the game's quest blob (QuestBlobDataProvider); nil: none
function MP.Hover(id)
  if MP.hover == id then return end
  MP.hover = id
  local canvas = MP.canvas
  if canvas and id then QB.Try("map page", canvas.TriggerEvent, canvas, "SetHighlightedQuestID", id)
  elseif canvas then QB.Try("map page", canvas.TriggerEvent, canvas, "ClearHighlightedQuestID") end
  MP.Glow()
end

-- where a quest is on map m, in fractions: its hand-in when it is ready, its objectives (and its hand-in) while it is
-- in your log, its giver while it is to pick up
function MP.Points(id, m)
  local q, e, out = QB.Quest.Get(id), QB.state.log[id], {}
  if not q then return out end
  local function npc(n) if n and n.m == m and not n.inside then out[#out + 1] = { n.x / 100, n.y / 100 } end end
  if e and e.complete then npc(q.turn)
  elseif e then
    for _, sp in ipairs(QB.QuestMap.Spots(QB.Data.SPOT and QB.Data.SPOT[id]) or {}) do
      if sp.m == m then out[#out + 1] = { sp.x, sp.y } end
    end
    npc(q.turn)
    if #out == 0 then npc(q.give) end
  else
    npc(q.give)
  end
  return out
end

-- a row clicked: the map pans to the quest (and zooms in on one that keeps to a corner of it), the game's quest blob
-- shows its areas, its pins stay lit and the minimap pulses them (Minimap.lua reads MP.focus). Again: let go
function MP.Focus(id)
  local canvas = MP.canvas
  if MP.focus == id then
    MP.focus = nil
    if canvas then QB.Try("map page", canvas.TriggerEvent, canvas, "ClearFocusedQuestID") end
  else
    MP.focus = id
    local pts = MP.Points(id, shownMap())
    if canvas and #pts > 0 then
      local x0, y0, x1, y1 = 1, 1, 0, 0
      for _, p in ipairs(pts) do x0, y0, x1, y1 = min(x0, p[1]), min(y0, p[2]), max(x1, p[1]), max(y1, p[2]) end
      local pan = max(x1 - x0, y1 - y0) < 0.25 and canvas.PanAndZoomTo or canvas.PanTo
      QB.Try("map page", pan, canvas, (x0 + x1) / 2, (y0 + y1) / 2)
    end
    if canvas then QB.Try("map page", canvas.TriggerEvent, canvas, "SetFocusedQuestID", id) end
  end
  MP.Glow()
  MP.FillPanel(true)
end

-- an icon clicked on the map: the first of its quests' rows scrolled to and lit for a moment (its section opened)
function MP.Reveal(ids)
  local f = MP.frame
  if not (f and MP.lists) then return nil end
  local want = {}
  for _, id in ipairs(ids or {}) do want[id] = true end
  for _, s in ipairs(SECTIONS) do
    for _, it in ipairs(MP.lists[s.list]) do
      if want[it.q.id] and MP.fold[s.list] then MP.fold[s.list] = nil; MP.FillPanel(true) end
    end
  end
  for _, r in ipairs(f.rows) do
    if r:IsShown() and r.it and want[r.it.q.id] then
      local lo, hi = f.list.bar:GetMinMaxValues()
      f.list.bar:SetValue(max(lo, min(hi, r.top - (f.list.viewH - ROW_H) / 2)))
      if MP.flashing then MP.flashing.flash:Hide() end
      MP.flashing, MP.flashLeft = r, FLASH
      r.flash:SetAlpha(1)
      r.flash:Show()
      return r
    end
  end
  return nil
end

-- while the page shows: the lit row fading; every TICK, your place on the route's first stroke, the arrow's step
function MP.Tick(dt)
  local r = MP.flashing
  if r then
    MP.flashLeft = MP.flashLeft - dt
    if MP.flashLeft <= 0 then r.flash:Hide(); MP.flashing = nil else r.flash:SetAlpha(MP.flashLeft / FLASH) end
  end
  MP.wait = (MP.wait or 0) - dt
  if MP.wait > 0 or not MP.canvas then return end
  MP.wait = TICK
  local m = shownMap()
  -- the one target changed (an objective's spot done, the next one taken): the strokes again, from it
  local T = QB.Target
  if T then T.Get(QB.API.WorldPosition(nil, herePos)) end
  local lines = MP.lines.active[1]
  if T and T.ver ~= (lines and lines.data.tv or MP.linesTv) then
    MP.linesTv = T.ver
    MP.lines:RefreshAllData()
    lines = MP.lines.active[1]
  end
  if lines then
    local you, was = youOn(m), lines.data.you
    if (you == nil) ~= (was == nil) or (you and abs(you.x - was.x) + abs(you.y - was.y) > 0.0005) then
      lines.data.you = you
      MP.lines:Place(lines)
    end
  end
  local _, key = stepNow()
  if key ~= MP.stepKey then
    MP.stepKey = key
    MP.step:RefreshAllData()
    MP.lines:RefreshAllData() -- (the step is on the way: the strokes go by it)
  end
end

-- everything about the map shown
function MP.Update()
  local f = MP.frame
  if not f then return end
  local m = shownMap()
  MP.lists, MP.zone = MP.ZoneQuests(m)
  MP.Crumbs()
  MP.Strip()
  MP.FillPanel(MP.listFor == m)
  MP.listFor = m
  local none = #MP.Dungeons(m) == 0
  f.dungeons.icon:SetDesaturated(none)
  f.dungeons.about = none and "No dungeon entrance on this map." or nil
end

-- the page of the QuestBank window (UI.lua): built the first time it shows
function MP.Attach(page)
  MP.frame = MP.frame or buildPage(page)
  MP.Place()
  return MP.frame
end

-- the page's refresh: back to your zone while the map follows you, then the bar, the strip and the panel
function MP.Refresh()
  if not MP.frame then return end
  MP.Place()
  if MP.follow then MP.Go(playerMap(), "follow") end
  MP.Update()
end
