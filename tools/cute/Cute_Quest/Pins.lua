-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank map pins: on the world map (and on QuestBank's own Map page) a pin for every stop on the route, drawn
-- as the game's own quest POI (the disc with the in-progress glyph, or the turn-in glyph once the stop's quests are
-- done; the next stop as the quest the game super-tracks), and the game's ! where a quest you plan to fetch starts.
-- A click on one is a waypoint (Core.lua, API.SetWaypoint); a Ctrl+click goes through to the map, where the game
-- places its own pin (P.through, below). The middle of this file holds what every QuestBank pin kind shares: the
-- game's atlases at the sizes the game draws them (P.Atlas), and its quest POI, quest offer and POI pin looks
-- (P.StylePoi, P.StyleOffer, P.StyleMark), which QuestMap.lua's icons and MapPage.lua's layers draw with too.
local _, QB = ...
if QB.dormant then return end
local P = { list = {} }
QB.Pins = P

----------------------------------------------------------------------------
-- what every QuestBank layer on the world map shares (this one and the quest icons, QuestMap.lua)
----------------------------------------------------------------------------
-- QuestBank draws its own frames on the world map, never the map canvas's pins. Each pin call of the canvas
-- (AcquirePin, RemoveAllPinsByTemplate, RemovePin, a pin's SetPosition) writes into the map's own tables: its pin
-- pools, the scroll container's scale and scroll (MarkCanvasDirty), the pins to nudge. Written from QuestBank's code,
-- those values carry QuestBank's taint, and Blizzard's code reads them later: a quest pin or the waypoint pin the map
-- acquires in combat then calls SetPassThroughButtons (protected, restricted in combat) as QuestBank, the call is
-- blocked, and the game blames QuestBank ("Interface action failed because of an AddOn"). 3.5.9 even acquired its
-- own pins in combat. So a layer keeps a data provider only to be told (the map calls RefreshAllData, OnMapChanged
-- and a new scale or size through secureexecuterange), only reads the map (its id, canvas, scale, zoom and frame
-- levels), and shows QuestBank's own frames, made from the templates in Pins.xml on the map's canvas. Those are
-- made only out of combat, where SetPassThroughButtons can let a right-click through to zoom the map out, as on
-- Blizzard's pins; in combat a layer only shows, hides and moves the frames it has, and draws again when combat ends.

-- in combat, or while the game holds addons back as it does in combat (C_RestrictedActions: the Combat and Encounter
-- restrictions; a client without them has InCombatLockdown alone)
local RESTRICTIONS = { "Combat", "Encounter" }
local function restricted()
  local RA, kinds = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
  if not (RA and RA.IsAddOnRestrictionActive and kinds) then return false end
  for _, name in ipairs(RESTRICTIONS) do
    local kind = kinds[name]
    if kind ~= nil then
      local ok, on = pcall(RA.IsAddOnRestrictionActive, kind)
      if ok and QB.Plain(on) == true then return true end
    end
  end
  return false
end
local function inCombat()
  if InCombatLockdown and InCombatLockdown() then return true end
  return restricted()
end
P.InCombat = inCombat

-- may QuestBank's code call a protected method of this frame now? Not in combat; and where the client can say, only
-- when it says so (asked silently: asking never trips the block)
local function mayProtect(f)
  if inCombat() then return false end
  local RA = C_RestrictedActions
  if RA and RA.CheckAllowProtectedFunctions then
    local ok, yes = pcall(RA.CheckAllowProtectedFunctions, f, true)
    if ok then return QB.Plain(yes) == true end
  end
  return true
end
P.MayProtect = mayProtect

-- the world map on screen: its data providers hear the game's events only while it is (MapCanvas OnShow and OnHide)
local function mapOpen()
  local f = WorldMapFrame
  if not f then return false end
  if f.IsVisible then return f:IsVisible() and true or false end
  return f.IsShown and f:IsShown() and true or false
end
P.MapOpen = mapOpen

-- the game's own map pin: a Ctrl+click on the map, or a click while the map's pin button is on, places it
-- (WaypointLocationDataProvider, on a click that reaches the canvas or one of the canvas's own pins). QuestBank's frames
-- are neither, so they would take that click (and set QuestBank's waypoint instead), and hide the pin cursor the map
-- shows over itself. While Ctrl is held or the button is on, they let the mouse through: EnableMouse(false) on
-- QuestBank's own frames, and the player's click lands on the map as the player's own, where the game places its pin as
-- its own code. QuestBank calls nothing of the map's for it. Not on a map the game has no pins for (an instance's), nor
-- where a game rule switches them off: a click there still sets QuestBank's waypoint. A frame of QuestBank's on the
-- canvas watches the keys, so it runs only while the map is open
P.layers = {}
P.through = false

local function pinKeys(map)
  if IsControlKeyDown and IsControlKeyDown() then return true end
  local button = map and map.WorldMapTrackingPinButton
  return type(button) == "table" and button.isActive == true
end

-- would a click on this map place the game's pin?
local function pinsHere(m)
  if not (m and WaypointLocationDataProviderMixin and C_Map and C_Map.CanSetUserWaypointOnMap) then return false end
  local rules, kinds = C_GameRules, Enum and Enum.GameRule
  if rules and rules.IsGameRuleActive and kinds and kinds.WorldMapTrackingPinDisabled ~= nil then
    local ok, off = pcall(rules.IsGameRuleActive, kinds.WorldMapTrackingPinDisabled)
    if ok and QB.Plain(off) == true then return false end
  end
  local ok, can = pcall(C_Map.CanSetUserWaypointOnMap, m)
  return ok and QB.Plain(can) == true
end

-- EnableMouse is protected on protected frames only, with no combat restriction (unlike SetPassThroughButtons), and
-- QuestBank's are plain frames. One that says it is protected keeps the mouse
local function mayMouse(f)
  local ok, prot = pcall(function() return f:IsProtected() end)
  return not (ok and QB.Plain(prot))
end

-- a frame that takes the mouse: taking it, or letting it through to the world map while P.through (QuestBank's own
-- map page has no game pin to let it through to)
local function mouseFor(f)
  if not f.kind.mouse then return end
  local want = not (P.through and f.layer.world)
  if f.mouseOn == want or not mayMouse(f) then return end
  f.mouseOn = want
  f:EnableMouse(want)
  if not want and GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(f) then GameTooltip:Hide() end
end

local function setThrough(on)
  P.through = on and true or false
  for _, layer in ipairs(P.layers) do
    for _, f in ipairs(layer.active) do mouseFor(f) end
  end
end
P.SetThrough = setThrough

-- every frame the map is open: the keys and the map, and the frames switched only when those change
local seen -- false: no pin keys; a map id: the keys down on that map
local function watch()
  local map = P.layers[1] and P.layers[1]:GetMap()
  local m = map and mapOpen() and pinKeys(map) and QB.Plain(map:GetMapID()) or false
  if m == seen then return end
  seen = m
  local on = m and pinsHere(m) or false
  if on ~= P.through then setThrough(on) end
end
local watchFailed = false
local function watchKeys()
  if watchFailed then return end
  local ok, err = pcall(watch)
  if not ok then
    watchFailed = true -- once: an error every frame would flood the list
    QB.Try("map pin keys", error, err, 0)
  end
end

-- a layer's map on screen: the world map as mapOpen says, QuestBank's own map page (MapPage.lua) by its canvas
local function shown(layer)
  if layer.world then return mapOpen() end
  local map = layer:GetMap()
  return map and map:IsVisible() and true or false
end
P.Shown = shown

-- layers that were told to redraw in combat: they draw when combat ends (or the game stops holding addons back), if
-- their map is still open; opening it later draws anyway
local afterCombat = {}
local function redrawLater()
  if inCombat() then return end
  local list = {}
  for layer in pairs(afterCombat) do list[#list + 1] = layer end
  afterCombat = {}
  for _, layer in ipairs(list) do
    if shown(layer) then layer:RefreshAllData() end
  end
end
P.combatFrame = CreateFrame and CreateFrame("Frame")
if P.combatFrame then
  P.combatFrame:SetScript("OnEvent", QB.Safe(function(_, event, _, state)
    -- ADDON_RESTRICTION_STATE_CHANGED comes before a restriction starts and after one ends: only the end matters
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
      local inactive = Enum and Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive or 0
      if QB.Plain(state) ~= inactive then return end
    end
    redrawLater()
  end, "map pins: after combat"))
  P.combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  pcall(P.combatFrame.RegisterEvent, P.combatFrame, "ADDON_RESTRICTION_STATE_CHANGED") -- a client without it says no
end

-- run fn once Blizzard's world map is loaded: now, or when it loads after us
local function mapReady()
  return WorldMapFrame and WorldMapFrame.AddDataProvider and WorldMapFrame.GetCanvas and MapCanvasDataProviderMixin and CreateFromMixins
    and true or false
end
function P.WhenMap(fn, where)
  if mapReady() then fn() return end
  if not CreateFrame then return end
  local wait = CreateFrame("Frame")
  wait:SetScript("OnEvent", QB.Safe(function(self, _, name)
    if (name == "Blizzard_WorldMap" or name == "Blizzard_MapCanvas") and mapReady() then
      self:UnregisterEvent("ADDON_LOADED")
      fn()
    end
  end, where))
  wait:RegisterEvent("ADDON_LOADED")
  return wait
end

-- the map's answer, read only, or nil (an older client without the method, a canvas not laid out yet)
local function ask(obj, method, ...)
  local f = obj and obj[method]
  if type(f) ~= "function" then return nil end
  local ok, v = pcall(f, obj, ...)
  if ok then return QB.Plain(v) end
  return nil
end

-- a frame's scale on the canvas, as the map's own pins work it out (MapCanvasPinMixin:ApplyCurrentScale): the canvas
-- zoom undone, then { factor, scale zoomed out, scale zoomed in } by how far in the map is zoomed, times the map's pin
-- scale. A kind without limits grows and shrinks with the terrain
local function pinScale(map, limits)
  if not limits then return 1 end
  local canvasScale = tonumber(ask(map, "GetCanvasScale")) or 1
  if canvasScale <= 0 then canvasScale = 1 end
  local zoom = tonumber(ask(map, "GetCanvasZoomPercent")) or 0
  if zoom ~= zoom then zoom = 0 end -- a map with one zoom level: 0 / 0
  local t = math.min(1, math.max(0, limits[1] * zoom))
  local global = tonumber(ask(map, "GetGlobalPinScale")) or 1
  return (limits[2] + (limits[3] - limits[2]) * t) / canvasScale * global
end
P.PinScale = pinScale

-- the frame level the map gives pins of this type (MapCanvas_PinFrameLevelsManager: read only), the index-th of a
-- type with a range (the game's quest pins: PIN_FRAME_LEVEL_ACTIVE_QUEST, one level a quest)
local function frameLevel(map, levelType, index)
  local mgr = ask(map, "GetPinFrameLevelsManager")
  if type(mgr) ~= "table" then return nil end
  return tonumber(ask(mgr, "GetValidFrameLevel", levelType, index))
end

-- a method of the frame's kind, or nil (read from the kind: a frame answers only for what it has)
local function method(f, name)
  local m = f.kind and f.kind.methods
  return m and m[name] or nil
end

-- the mouse on QuestBank's frames: its own scripts (the canvas's are for its own pins). A quest POI lights its inner
-- glow under the mouse and shows its pressed disc while the button is held, as the game's button does
local function onEnter(f)
  if rawget(f, "Hi") then f.Hi:Show() end
  local fn = method(f, "OnMouseEnter"); if fn then fn(f) end
end
local function onLeave(f)
  if rawget(f, "Hi") then f.Hi:Hide() end
  if f.pressed then P.Press(f, false) end
  local fn = method(f, "OnMouseLeave"); if fn then fn(f) end
end
local function onMouseDown(f, button) if button == "LeftButton" and rawget(f, "Disc") then P.Press(f, true) end end
local onMouseUp = QB.Safe(function(f, button, upInside)
  if f.pressed then P.Press(f, false) end
  if upInside == false then return end -- let go outside the frame
  local fn = method(f, "OnMouseClickAction")
  if fn then fn(f, button) end
end, "map pin click")

local Layer = {}

-- a new frame of this kind, on the canvas: out of combat only
-- a right-click goes on to the map below, which zooms out (as on the game's pins; a kind with rightClick takes it, as
-- the game's dungeon entrance does). SetPassThroughButtons is protected and restricted in combat: called once a
-- frame, out of combat and when the client allows it (a frame made when it didn't gets it on a later draw)
local function passThrough(f)
  if f.passSet or f.kind.rightClick or not f.SetPassThroughButtons or not mayProtect(f) then return end
  f.passSet = true
  pcall(f.SetPassThroughButtons, f, "RightButton")
end

function Layer:Make(kind)
  if inCombat() or not self.canvas then return nil end
  local f = CreateFrame("Frame", nil, self.canvas, kind.template)
  f.kind, f.layer = kind, self
  for k, v in pairs(kind.methods or {}) do f[k] = v end
  if kind.mouse then
    f:EnableMouse(true)
    f.mouseOn = true
    f:SetScript("OnEnter", onEnter)
    f:SetScript("OnLeave", onLeave)
    f:SetScript("OnMouseDown", onMouseDown)
    f:SetScript("OnMouseUp", onMouseUp)
    passThrough(f)
  else
    f:EnableMouse(false)
  end
  self.made = (self.made or 0) + 1
  return f
end

-- where a frame stands: x and y fractions of the map (or the cell the quantizer snapped it to, below), placed as
-- Blizzard_MapCanvas.lua's ApplyPinPosition does. scales: each kind's scale, worked out once for a whole draw or zoom step
function Layer:Place(f, scales)
  local map, canvas = self:GetMap(), self.canvas
  if not (map and canvas) then return end
  local limits = f.kind.scale
  local scale = scales and scales[f.kind]
  if not scale then
    scale = pinScale(map, limits)
    if scales then scales[f.kind] = scale end
  end
  if limits then f:SetScale(scale) end
  local fit = method(f, "Fit")
  if fit then fit(f, canvas) end
  f:ClearAllPoints()
  f:SetPoint("CENTER", canvas, "TOPLEFT", (canvas:GetWidth() or 0) * (f.qX or f.mapX) / scale, -(canvas:GetHeight() or 0) * (f.qY or f.mapY) / scale)
end

-- the game's quantizer (Blizzard_UIPanels_Game/Shared/WorldMapPOIQuantizer.lua, as QuestDataProvider uses it: a grid
-- 75 cells high and as many wide as the canvas is wider): quest pins that would share a cell snap to the nearest free
-- cell's centre, so none lies on another, and a pin with no neighbour stays where it is. QuestBank's quest POI kinds
-- (quantize = true) go through it after each draw, each layer against its own pins and the other layers' on the
-- same canvas (whose cells are read, never moved)
local CELLS = 75
local C0, UR, R, LR, LO, LL, L, UL, U = { 0, 0 }, { 1, 1 }, { 1, 0 }, { 1, -1 }, { 0, -1 }, { -1, -1 }, { -1, 0 }, { -1, 1 }, { 0, 1 }
local RIGHT_TOP, TOP_RIGHT = { C0, UR, R, U, LR, UL, LO, L, LL }, { C0, UR, U, R, UL, LR, L, LO, LL }
local LEFT_TOP, TOP_LEFT = { C0, UL, L, U, LL, UR, LO, R, LR }, { C0, UL, U, L, UR, LL, R, LO, LR }
local LEFT_BOTTOM, BOTTOM_LEFT = { C0, LL, L, LO, UL, LR, U, R, UR }, { C0, LL, LO, L, LR, UL, R, U, UR }
local RIGHT_BOTTOM, BOTTOM_RIGHT = { C0, LR, R, LO, UR, LL, U, L, UL }, { C0, LR, LO, R, LL, UR, L, U, UL }
local function enumerator(nx, ny)
  if nx > 0.5 then
    if ny > 0.5 then return nx > ny and RIGHT_TOP or TOP_RIGHT end
    return (1 - nx < ny) and RIGHT_BOTTOM or BOTTOM_RIGHT
  end
  if ny > 0.5 then return (nx < 1 - ny) and LEFT_TOP or TOP_LEFT end
  return nx < ny and LEFT_BOTTOM or BOTTOM_LEFT
end
P.allLayers = {}
function Layer:Quantize()
  local canvas = self.canvas
  if not canvas then return end
  local w, h = canvas:GetWidth() or 0, canvas:GetHeight() or 0
  local wide = math.max(1, math.ceil(CELLS * (h > 0 and w / h or 1.5)))
  local grid = {}
  local function key(x, y) return y * 10000 + x end
  for _, other in ipairs(P.allLayers) do
    if other ~= self and other.canvas == canvas then
      for _, f in ipairs(other.active) do if f.kind.quantize and f.cell then grid[f.cell] = f end end
    end
  end
  local moved = false
  for _, f in ipairs(self.active) do
    if f.kind.quantize then
      if f.qX then moved = true end
      f.qX, f.qY, f.cell = nil, nil, nil
      local cx, cy = f.mapX * wide, f.mapY * CELLS
      local ix, iy = math.min(math.floor(cx) + 1, wide), math.min(math.floor(cy) + 1, CELLS)
      local found, neighbour = false, false
      for _, off in ipairs(enumerator(cx % 1, cy % 1)) do
        local x, y = ix + off[1], iy + off[2]
        if x >= 1 and x <= wide and y >= 1 and y <= CELLS then
          local there = grid[key(x, y)]
          if there then
            if not there.qX then
              there.qX, there.qY = (x - 0.5) / wide, (y - 0.5) / CELLS
              if there.layer == self then moved = true else there.layer:Place(there) end
            end
            neighbour = true
          elseif not found then
            found = true
            grid[key(x, y)] = f
            f.cell, f.qX, f.qY = key(x, y), (x - 0.5) / wide, (y - 0.5) / CELLS
          end
        end
      end
      if found and not neighbour then f.qX, f.qY = nil, nil end -- nothing near: left where it stands
      if f.qX then moved = true end
    end
  end
  if moved then
    local scales = {}
    for _, f in ipairs(self.active) do if f.kind.quantize then self:Place(f, scales) end end
  end
end

-- one frame of this kind for data at (x, y): one put away, or a new one; at the map's level for its type (the
-- index-th of that type's range, as the game stacks its quest pins)
function Layer:Add(kind, data, x, y, levelType, levelIndex)
  self.free[kind] = self.free[kind] or {}
  local f = table.remove(self.free[kind]) or self:Make(kind)
  if not f then return nil end
  if kind.mouse and not f.passSet then passThrough(f) end
  mouseFor(f)
  f.data, f.mapX, f.mapY, f.levelType, f.levelIndex = data, x, y, levelType or kind.level, levelIndex
  local level = frameLevel(self:GetMap(), f.levelType, levelIndex)
  if level then f:SetFrameLevel(level) end
  local setup = method(f, "Setup")
  if setup then setup(f, data) end
  P.Glow(f, self.lit and self.lit(data))
  self:Place(f, self.scales)
  f:Show()
  self.active[#self.active + 1] = f
  return f
end

-- every frame put away (hidden, kept for the next draw)
function Layer:RemoveAllData()
  for i = #self.active, 1, -1 do
    local f = self.active[i]
    self.active[i] = nil
    f:Hide()
    f.data, f.levelIndex, f.qX, f.qY, f.cell = nil, nil, nil, nil, nil
    self.free[f.kind] = self.free[f.kind] or {}
    table.insert(self.free[f.kind], f)
  end
end

function Layer:RefreshAllData()
  local map = self:GetMap()
  if not map then return end
  local shown = QB.Plain(map:GetMapID())
  if inCombat() then
    -- nothing made or redrawn now: frames drawn for another map hide until the redraw after combat
    for _, f in ipairs(self.active) do f:SetShown(shown == self.drawnFor) end
    afterCombat[self] = true
    return
  end
  afterCombat[self] = nil
  self:RemoveAllData()
  self.drawnFor = shown
  self.draws = (self.draws or 0) + 1
  self.scales = {}
  if shown then self.draw(self, shown) end
  self.scales = nil
  self:Quantize()
end

function Layer:OnMapChanged() self:RefreshAllData() end

-- the map shut (MapCanvas OnHide tells every provider): the frames take the mouse again for the next time it opens,
-- and once the map's own OnHide is done TomTom hears of a waypoint it was kept from while the map was open (Core.lua,
-- API.SetWaypoint). The next frame: by then the scroll container has cleared its scale and scroll (its own OnHide)
local closing = false
function P.AfterClose()
  seen = nil
  if P.through then setThrough(false) end
  if closing or not (C_Timer and C_Timer.After) then return end
  closing = true
  C_Timer.After(0, QB.Safe(function()
    closing = false
    QB.API.TomTomLater()
  end, "map closed"))
end

-- zoomed, or the map made bigger or smaller: every frame placed and sized again (allowed in combat: QuestBank's own)
function Layer:OnCanvasScaleChanged()
  local scales = {}
  for _, f in ipairs(self.active) do self:Place(f, scales) end
end

-- the game's glow under a pin (QuestPinTemplate's LinkGlow: UI-QuestPoi-OuterGlow at 75 px, added, while the quest
-- log highlights the quest): col = { r, g, b, a }, or nil for none. A layer with a lit(data) function lights its
-- frames as they are drawn (QuestBank's map page: the quest hovered or picked in its list, the arrow's step). The
-- atlas keeps the game's own colour; a client without it gets art/glow.tga in col, as the minimap's pins have
local GLOW = (QB.ART or "Interface\\AddOns\\QuestBank\\art\\") .. "glow.tga"
function P.Glow(f, col)
  if not (col or f.glow) then return end
  if not f.glow then
    f.glow = f:CreateTexture(nil, "BACKGROUND")
    f.glow:SetBlendMode("ADD")
    f.glow:SetPoint("CENTER")
    local _, _, atlas = P.Atlas(f.glow, "UI-QuestPoi-OuterGlow", GLOW)
    f.glowAtlas = atlas
  end
  if col then
    local size = (f.kind.glow or (f:GetWidth() or 20) * 2.2) * (f.iconK or 1) -- (a smaller icon, a smaller glow)
    f.glow:SetSize(size, size)
    if f.glowAtlas then f.glow:SetVertexColor(1, 1, 1, col[4] or 1) else f.glow:SetVertexColor(col[1], col[2], col[3], col[4] or 1) end
  end
  f.glow:SetShown(col and true or false)
end

-- a layer on a map: the world map, or another canvas built from the game's map templates (map; QuestBank's map page).
-- draw(layer, mapID) adds its frames (layer:Add), after the last draw's are put away. Whatever goes wrong in it stays
-- in it: the map runs every provider in one loop
function P.NewLayer(draw, where, map)
  map = map or WorldMapFrame
  local layer = CreateFromMixins(MapCanvasDataProviderMixin, Layer)
  layer.draw, layer.active, layer.free, layer.canvas = draw, {}, {}, map:GetCanvas()
  layer.world = map == WorldMapFrame
  P.allLayers[#P.allLayers + 1] = layer
  layer.RefreshAllData = QB.Safe(Layer.RefreshAllData, where)
  layer.OnCanvasScaleChanged = QB.Safe(Layer.OnCanvasScaleChanged, where)
  layer.OnCanvasSizeChanged = layer.OnCanvasScaleChanged
  if layer.world then
    -- only the world map has the game's own pin to let Ctrl+clicks through to, and TomTom to hold back while open
    layer.OnHide = QB.Safe(P.AfterClose, where)
    P.layers[#P.layers + 1] = layer
    if not P.watcher then
      -- on the canvas, so it runs only while the map is open; no mouse, nothing drawn
      P.watcher = CreateFrame("Frame", nil, layer.canvas)
      P.watcher:SetScript("OnUpdate", watchKeys)
    end
  end
  map:AddDataProvider(layer)
  return layer
end

----------------------------------------------------------------------------
-- the game's pins, drawn again on QuestBank's frames (Pins.xml): what every layer draws with
----------------------------------------------------------------------------
-- the size the game draws each atlas at (SetAtlas(name, true): the member's override size where it has one, from the
-- live build's UiTextureAtlasMember), for a client that can't say. The quest POI family is 32 px, the flight points 21
local ATLAS_SIZE = {
  ["UI-QuestPoi-QuestNumber"] = 32, ["UI-QuestPoi-QuestNumber-SuperTracked"] = 32, ["UI-QuestPoi-QuestNumber-Pressed"] = 32,
  ["UI-QuestPoi-QuestNumber-Pressed-SuperTracked"] = 32, ["UI-QuestPoi-InnerGlow"] = 32, ["UI-QuestPoi-OuterGlow"] = 64,
  ["UI-QuestPoiRecurring-QuestNumber"] = 32, ["UI-QuestPoiRecurring-QuestNumber-SuperTracked"] = 32,
  ["UI-QuestPoiRecurring-QuestNumber-Pressed"] = 32, ["UI-QuestPoiRecurring-QuestNumber-Pressed-SuperTracked"] = 32,
  ["UI-QuestPoiRecurring-InnerGlow"] = 32, ["UI-QuestPoiRecurring-QuestBang"] = 32, ["UI-QuestPoiRecurring-QuestBangTurnIn"] = 32,
  ["Quest-In-Progress-Icon-yellow"] = 32, ["Quest-In-Progress-Icon-Brown"] = 32, ["UI-QuestIcon-TurnIn-Normal"] = 32,
  QuestNormal = 32, QuestTurnin = 32, Dungeon = 32, Raid = 32, FlightPath = 32,
  taxinode_neutral = 21, taxinode_alliance = 21, taxinode_horde = 21, taxinode_undiscovered = 21,
}
P.ATLAS_SIZE = ATLAS_SIZE

local function atlasInfo(atlas)
  if not (atlas and C_Texture and type(C_Texture.GetAtlasInfo) == "function") then return nil end
  local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
  return ok and type(info) == "table" and info or nil
end

-- an atlas on a texture at the size the game draws it, as the game's pins set theirs (SetAtlas(name, true)): the size
-- above where this build is known, else the client's own answer, else size (32). Where the client lacks the atlas,
-- QuestBank's file at that size, with coords = { left, right, top, bottom } of its part of the file. Returns the width,
-- the height and whether the atlas was there
function P.Atlas(tex, atlas, file, coords, size)
  local info = atlasInfo(atlas)
  local w, h
  tex:SetTexCoord(0, 1, 0, 1)
  if info and tex.SetAtlas then
    tex:SetAtlas(atlas, false)
    w = ATLAS_SIZE[atlas] or tonumber(QB.Plain(info.width))
    h = ATLAS_SIZE[atlas] or tonumber(QB.Plain(info.height))
  else
    tex:SetTexture(file)
    if coords then tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) end
  end
  if not (w and w > 0) then w = ATLAS_SIZE[atlas] or size or 32 end
  if not (h and h > 0) then h = w end
  tex:SetSize(w, h)
  return w, h, info ~= nil
end

-- the two families the game's quest pins come in on this server: the basic look (Normal and Questline quests) and the
-- Recurring one (repeatables and dailies); each atlas named as POIButton.lua and QuestOfferDataProvider.lua name it
local FAMILY = {
  basic = { disc = "UI-QuestPoi-QuestNumber", turn = "UI-QuestIcon-TurnIn-Normal", bang = "QuestNormal", hi = "UI-QuestPoi-InnerGlow" },
  recurring = { disc = "UI-QuestPoiRecurring-QuestNumber", turn = "UI-QuestPoiRecurring-QuestBangTurnIn", bang = "UI-QuestPoiRecurring-QuestBang", hi = "UI-QuestPoiRecurring-InnerGlow" },
}
P.FAMILY = FAMILY

-- which family a quest's pins come in: the client's word on it (C_QuestLog.GetQuestClassification), else the
-- catalog's: repeatable quests are Recurring
function P.Family(q)
  local id = type(q) == "table" and q.id or q
  local E = Enum and Enum.QuestClassification
  if id and E and C_QuestLog and C_QuestLog.GetQuestClassification then
    local ok, c = pcall(C_QuestLog.GetQuestClassification, id)
    c = ok and QB.Plain(c) or nil
    if c ~= nil then return c == E.Recurring and "recurring" or "basic" end
  end
  return (type(q) == "table" and q.repeatable) and "recurring" or "basic"
end

-- a client without the atlases (Classic Era): the disc from UI-QuestPoi-NumberIcons, the parts POIButton.xml names,
-- and the gossip frame's ? for the glyph
local T = QB.Data.TEX
local DISC_FILE = 334391
local DISC = { normal = { 0.875, 1, 0.875, 1 }, pressed = { 0.75, 0.875, 0.875, 1 }, hi = { 0.625, 0.75, 0.375, 0.5 } }

-- the game's quest POI on a QuestBankPoiTemplate frame (POIButton.lua: POIButton_UpdateQuestInProgressStyle and
-- POIButton_UpdateNormalStyle, the basic look). look = { complete, tracked, family, late }: the disc
-- (UI-QuestPoi-QuestNumber, -SuperTracked for the quest the game super-tracks), the glyph on it (in progress:
-- Quest-In-Progress-Icon-yellow, Brown when super-tracked; complete: UI-QuestIcon-TurnIn-Normal) and the inner glow
-- the mouse lights; late (a stop past the hour's goal): greyed, QuestBank's own
-- (the regions' anchors are the template's; set once here too, so a frame built without the template's anchors, as
-- the harness builds them, stands the same)
local function centre(tex) tex:ClearAllPoints(); tex:SetPoint("CENTER", 0, 0) end

-- QuestBank's quest icons (a quest POI, an offer's !) drawn at mapIconPct of the game's own art (5.4.4: half, from the
-- owner's "quest icons on the map are massive, can be halved"; a size you set stays yours), 30 to 100 percent. Only
-- the art: the frame, and so where a click lands, stays the game's own pin's (20 by 20 for a quest POI, 22 for an
-- offer), and it scales with the map's zoom as the game's pins do (each kind's scale)
function P.IconScale()
  local pct = tonumber(QB:Settings().mapIconPct) or 50
  return math.max(0.3, math.min(1, pct / 100))
end
-- an atlas at the game's size times the icon scale (P.Atlas, then sized down)
local function atlasScaled(tex, atlas, file, coords, k)
  local w, h, has = P.Atlas(tex, atlas, file, coords)
  if k ~= 1 then tex:SetSize(w * k, h * k) end
  return w * k, h * k, has
end
P.AtlasScaled = atlasScaled

function P.StylePoi(f, look)
  local fam = FAMILY[look.family or "basic"] or FAMILY.basic
  local k = P.IconScale()
  f.look, f.pressed, f.iconK = look, nil, k
  if not f.anchored then f.anchored = true; centre(f.Disc); centre(f.Hi) end
  atlasScaled(f.Disc, fam.disc .. (look.tracked and "-SuperTracked" or ""), DISC_FILE, DISC.normal, k)
  if look.complete then atlasScaled(f.Glyph, fam.turn, T.questActive, nil, k)
  else atlasScaled(f.Glyph, look.tracked and "Quest-In-Progress-Icon-Brown" or "Quest-In-Progress-Icon-yellow", T.questActive, nil, k) end
  f.Glyph:ClearAllPoints()
  f.Glyph:SetPoint("CENTER", 0, 0)
  atlasScaled(f.Hi, fam.hi, DISC_FILE, DISC.hi, k)
  f.Hi:SetBlendMode("ADD")
  f.Hi:Hide()
  f.Disc:SetDesaturated(look.late or false)
  f.Glyph:SetDesaturated(look.late or false)
end

-- the button held (POIButtonMixin:OnMouseDown, UpdatePoint): the pressed disc, the glyph a pixel right and down
function P.Press(f, down)
  if not (rawget(f, "Disc") and f.look) then return end
  local fam = FAMILY[f.look.family or "basic"] or FAMILY.basic
  f.pressed = down or nil
  atlasScaled(f.Disc, fam.disc .. (down and "-Pressed" or "") .. (f.look.tracked and "-SuperTracked" or ""), DISC_FILE, down and DISC.pressed or DISC.normal, f.iconK or 1)
  f.Glyph:ClearAllPoints()
  f.Glyph:SetPoint("CENTER", down and 1 or 0, down and -1 or 0)
end

-- the game's quest offer on a QuestBankOfferTemplate frame (QuestOfferDataProvider.lua): the ! at its own 32 px,
-- QuestNormal or the Recurring bang; look = { family, drop, trivial }. drop: the item that starts the quest drops here,
-- marked as QuestTrail marks it (the ! red, greyed); trivial: half as bright, as the game draws a trivial offer
function P.StyleOffer(f, look)
  local fam = FAMILY[look.family or "basic"] or FAMILY.basic
  f.look = look
  if not f.anchored then f.anchored = true; centre(f.Texture) end
  f.iconK = P.IconScale()
  atlasScaled(f.Texture, fam.bang, T.questAvail, nil, f.iconK)
  f.Texture:SetDesaturated(look.drop or false)
  if look.drop then f.Texture:SetVertexColor(1, 0.22, 0.18) else f.Texture:SetVertexColor(1, 1, 1) end
  f:SetAlpha(look.trivial and 0.5 or 1)
end

-- the game's POI pin on a QuestBankMarkTemplate frame (SharedMapPoiTemplates.lua, BaseMapPoiPinMixin:SetTexture): the
-- atlas at its own size (or size), the frame sized to it, the same atlas added over it at 0.4 while the mouse is on it
-- (its HighlightTexture; f.hi here)
function P.StyleMark(f, atlas, file, size)
  if not f.anchored then f.anchored = true; centre(f.Texture) end
  local w, h = P.Atlas(f.Texture, atlas, file, nil, size)
  if size then w, h = size, size; f.Texture:SetSize(size, size) end
  f:SetSize(w, h)
  if f.kind and f.kind.mouse then
    if not f.hi then
      f.hi = f:CreateTexture(nil, "HIGHLIGHT")
      f.hi:SetBlendMode("ADD")
      f.hi:SetAlpha(0.4)
      f.hi:SetPoint("TOPLEFT", f.Texture, "TOPLEFT")
      f.hi:SetPoint("BOTTOMRIGHT", f.Texture, "BOTTOMRIGHT")
    end
    P.Atlas(f.hi, atlas, file, nil, size)
    if size then f.hi:SetSize(size, size) end
  end
  return w, h
end

-- the game's own words on its tooltips (GlobalStrings), as far as the client has them
function P.Word(name, fallback)
  local v = _G[name]
  return type(v) == "string" and v or fallback
end
-- a green instruction line in angle brackets, as the game's tooltips give theirs (<Right Click to open Adventure Guide>)
function P.Instruct(tip, text) tip:AddLine("<" .. text .. ">", 0.1, 1, 0.1, true) end

----------------------------------------------------------------------------
-- the route's pins
----------------------------------------------------------------------------
-- QuestBankPoiTemplate (a stop) and QuestBankOfferTemplate (a planned pick-up), Pins.xml, with these on top
local Pin = {}
P.Pin = Pin

-- a stop: the game's quest POI, with the turn-in glyph once every quest it takes is done, and stop 1 as the quest the
-- game super-tracks (the gold disc, the brown glyph); a planned pick-up: the game's !
function Pin:Setup(data)
  if data.num then P.StylePoi(self, { complete = data.ready, tracked = data.num == 1, late = data.late, family = data.family })
  else P.StyleOffer(self, { family = data.family }) end
end

-- the stop's tooltip in the game's words: the place as the title, each quest as the game's quest pin titles it
-- ([level] name, in the colour of its level) with its XP beside it, then QuestBank's lines: which stop this is and
-- when the route gets there, what else the NPC under the pin has (QuestMap.lua), and the click
Pin.OnMouseEnter = QB.Safe(function(self)
  local d = self.data
  if not d then return end
  local QM = QB.QuestMap
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(d.title or d.name, 1, 0.82, 0)
  if not d.num then
    local many = #(d.quests or {}) > 1
    GameTooltip:AddLine(many and P.Word("QUEST_HUB_TOOLTIP_AVAILABLE_QUESTS_HEADER", "Available Quests") or P.Word("AVAILABLE_QUEST", "Available quest"), 1, 1, 1, true)
  end
  if QM and QM.QuestLines and d.quests then QM.QuestLines(GameTooltip, d.quests, d.labels)
  else for _, line in ipairs(d.lines or {}) do GameTooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 0.6, 1, 0.6) end end
  -- the pick-ups the route plans at this stop's NPC (folded into the stop, as the game's hub pin folds its offers)
  if d.pickups and QM and QM.QuestLines then
    GameTooltip:AddLine(#d.pickups > 1 and P.Word("QUEST_HUB_TOOLTIP_AVAILABLE_QUESTS_HEADER", "Available Quests") or P.Word("AVAILABLE_QUEST", "Available quest"), 1, 1, 1, true)
    QM.QuestLines(GameTooltip, d.pickups, d.labels)
  end
  if d.when then GameTooltip:AddLine(P.WhenNow(d), 0.8, 0.8, 0.8) end
  -- the quest icons leave the NPC under this pin to it: what they would have shown there
  if QM and QM.AlsoHere then
    local map = self.layer and self.layer:GetMap()
    QM.AlsoHere(GameTooltip, d, map and QB.Plain(map:GetMapID()))
  end
  P.Instruct(GameTooltip, "Click to show it on the arrow for now")
  -- the one labelled change to the route a pin makes: a pick-up taken out of it, or a stop's quests skipped (the
  -- quest icons' Shift-click routes them again)
  local ids, n = P.PinQuests(d)
  if n > 0 then
    P.Instruct(GameTooltip, d.num and (n > 1 and "Shift-click: skip these quests" or "Shift-click: skip this quest") or "Shift-click: take it out of my route")
  end
  GameTooltip:Show()
end, "map pin tooltip")

function Pin:OnMouseLeave() GameTooltip:Hide() end

-- a route pin's quests: a stop's in your log (what its Shift-click skips, and what ends the arrow's showing it), a
-- pick-up's on your list. Returns them as a set, and how many
function P.PinQuests(d)
  local ids, n = {}, 0
  for id in pairs(d.ids or {}) do
    if type(id) == "number" and ((d.num and QB.state.log[id]) or (not d.num and QB:IsAdded(id))) then ids[id], n = true, n + 1 end
  end
  return ids, n
end

-- a click: the place on the arrow for now (it ends as you get there, or as the stop's quests are handed in), nothing
-- more. Shift-click: the labelled change, a stop's quests skipped or a pick-up off the list
function Pin:OnMouseClickAction(button)
  local d = self.data
  if not d or button == "RightButton" then return end
  local ids, n = P.PinQuests(d)
  if IsShiftKeyDown and IsShiftKeyDown() and n > 0 then
    local names = {}
    for id in pairs(ids) do
      if d.num then QB:SetSkipped(id, true) else QB:SetAdded(id, false) end
      local q = QB.Quest.Get(id)
      names[#names + 1] = q and q.name or ("Quest " .. id)
    end
    table.sort(names)
    QB:Print((d.num and "Skipped, out of your route: " or "Out of your route (off your pick-up list): ") .. table.concat(names, ", ") .. ".")
    return
  end
  local about = d.num and n > 0 and { ids = ids } or nil
  if not d.num then
    local first = next(ids)
    if first then about = { qid = first, what = "give" } end
  end
  QB.API.SetWaypoint(d.m, d.x, d.y, d.name, nil, nil, about)
end

-- the stops: the game's quest POI, the same size at every zoom (QuestPinMixin: SetScalingLimits(1, 1, 1)), on the
-- level the game gives its quest pins (stop 1 on the super-tracked quest's, above them all); the planned pick-ups:
-- the game's offer, a little bigger as you zoom in (QuestOfferPinMixin: 1.0 to 1.2), on the offers' level
local ROUTE = { template = "QuestBankPoiTemplate", level = "PIN_FRAME_LEVEL_ACTIVE_QUEST", scale = { 1, 1, 1 }, mouse = true, methods = Pin, glow = 75, size = 32, quantize = true }
local PICKUP = { template = "QuestBankOfferTemplate", level = "PIN_FRAME_LEVEL_QUEST_OFFER", scale = { 1, 1.0, 1.2 }, mouse = true, methods = Pin, glow = 68, size = 32 }
P.ROUTE, P.PICKUP = ROUTE, PICKUP

-- a point on one map, placed on another (a city on its continent, a zone on the world map)
local function project(d, mapID)
  if d.m == mapID then return d.x / 100, d.y / 100 end
  if not (C_Map and C_Map.GetMapRectOnMap) then return nil end
  local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, d.m, mapID)
  if not ok or not minX or maxX == minX then return nil end
  local x, y = minX + d.x / 100 * (maxX - minX), minY + d.y / 100 * (maxY - minY)
  if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  return x, y
end
P.Project = project

-- is the route drawn: on the world map by its own switch (pins, "The route's pins on the world map"), on
-- QuestBank's map page by the page's (mapRoute, its strip's Route)
function P.RouteOn(world)
  local set = QB:Settings()
  if world then return set.pins and true or false end
  return set.mapRoute ~= false
end

-- every pin of the route that falls on the map shown: the stops on the quest pins' levels in their order, stop 1 on
-- the super-tracked quest's; the planned pick-ups on the offers' level
local function drawRoute(layer, m)
  if not P.RouteOn(layer.world) then return end
  for _, d in ipairs(P.list) do
    local x, y = project(d, m)
    if x and d.num then layer:Add(ROUTE, d, x, y, d.num == 1 and "PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST" or nil, d.num)
    elseif x then layer:Add(PICKUP, d, x, y) end
  end
end

function P:Init()
  if self.provider or self.waiting then return end
  self.waiting = P.WhenMap(function()
    if P.provider then return end
    P.provider = P.NewLayer(drawRoute, "map pins")
  end, "map pins: waiting for the map")
end

-- the same pins on QuestBank's own map page (MapPage.lua), once. pageLayers: the page's layers drawn from the route
-- (these pins, and MapPage.lua's strokes and arrow step), drawn again with it while the page shows
P.pageLayers = {}
function P.AddTo(map)
  if not P.pageProvider then
    P.pageProvider = P.NewLayer(drawRoute, "map page pins", map)
    P.pageLayers[#P.pageLayers + 1] = P.pageProvider
  end
  return P.pageProvider
end

-- the route on screen: the one the arrow, the minimap and the Map page follow (Target.lua, T.Mode): the run's rest;
-- questing, the planned route (what is ready now while the Route page shows that); banking, what is ready now (the
-- planned route while that page shows it)
function P:Route() return QB.Target.Route() end

-- (the launch round) a stop's title: the NPC its pin stands on and the town, "Smith Argus, Goldshire" (6.1 titled a
-- stop out of a flight master's town by its zone and spot, "Elwynn Forest (42, 65)", beside the map's own Goldshire):
-- the place as Travel.lua's TV.StopPlace words it (the stop's town, else the inn town within 150 yards, else the zone).
-- A stop of several NPCs: the place alone. Its name (Model.lua) stays as it is: stops are matched by it
function P.StopTitle(s)
  local D = QB.Data
  local npcs = s and s.npcs
  local n = npcs and npcs[1] and D.NPC[npcs[1]]
  if not n then return s and s.name end
  local town = QB.Travel.StopPlace(s)
  if #npcs > 1 then return town or s.name end
  if not town or town == n[1] then return n[1] end
  return n[1] .. ", " .. town
end
-- the minutes to a stop in words, true when read: a route planned from where you stand counts down from the time it was
-- planned (first seen here: P:Update runs at each re-plan's QB:Changed), "51 min from now", "1 h 05 min from now"; once
-- that count is spent, or on a route planned from elsewhere (banked: from where you log out), where the stop falls
-- along the route, "51 min into the route" (or "where the route starts"). (6.1's "at 0:51" read as a clock; the launch round's "from now" was the
-- plan's figure, stale as you went: the route is not planned again as you walk.) The tooltips read it again as they
-- show (P.WhenNow)
local planned = setmetatable({}, { __mode = "k" }) -- a route -> GetTime() when first seen (a re-plan makes a new one)
local function minutes(t)
  t = math.max(0, math.floor(t + 0.5))
  if t < 60 then return t .. " min" end
  return string.format("%d h %02d min", math.floor(t / 60), t % 60)
end
local function fromNow(t, r)
  t = t or 0
  if r and r.fromHere then
    local now = GetTime and GetTime() or 0
    local at = planned[r]
    if not at then at = now; planned[r] = at end
    local left = t - (now - at) / 60
    if left >= 0.5 then return minutes(left) .. " from now" end
  end
  if t < 0.5 then return "where the route starts" end
  return minutes(t) .. " into the route"
end
-- a stop's line as it reads now (the list's reads as at P:Build): its minutes counted again
function P.WhenNow(d)
  local w = d and d.when
  if not (w and d.ago and d.route) then return w end
  local now = fromNow(d.t, d.route)
  if now == d.ago then return w end
  local a, b = w:find(d.ago, 1, true)
  if not a then return w end
  return w:sub(1, a - 1) .. now .. w:sub(b + 1)
end

function P:Build()
  local list = {}
  local r = self:Route()
  if r and r.legs then
    for i, leg in ipairs(r.legs) do
      local s = leg.stop
      if s.m and s.m > 0 then
        local lines, ids, quests, ready, family = {}, {}, {}, true, "basic"
        for _, row in ipairs(leg.rows) do
          lines[#lines + 1] = { row.q.name, QB.Comma(row.xp) }
          ids[row.q.id] = true
          quests[#quests + 1] = row.q
          -- the stop's look: the turn-in glyph once every quest it takes is done, else in progress; the Recurring
          -- family when they are repeatables
          local e = QB.state.log[row.q.id]
          if not (e and e.complete) then ready = false end
          if P.Family(row.q) == "recurring" then family = "recurring" end
        end
        -- who: the NPC the pin stands on (a stop stands at its first NPC, and may be named for its town or place);
        -- ids: the quests it lists. The quest icons (QuestMap.lua) read both
        local first = s.npcs and s.npcs[1] and QB.Data.NPC[s.npcs[1]]
        local ago = fromNow(leg.t, r) -- (and t, route, ago: P.WhenNow counts it again as a tooltip shows)
        list[#list + 1] = { m = s.m, x = s.x, y = s.y, num = i, name = s.name, title = P.StopTitle(s), who = first and first[1] or nil, ids = ids, icon = T.questActive, stop = s,
                            quests = quests, ready = ready, family = family, late = (leg.late and r.goal == "hour") or nil,
                            when = string.format("Stop %d of %d, %s: %s", i, #r.legs, ago, QB.Model.Gain(leg)), lines = lines,
                            t = leg.t, route = r, ago = ago }
      end
    end
  end
  -- where the quests you plan to fetch start; a giver a stop stands on (the same NPC, or one at its spot) is folded
  -- into the stop, as the game's hub pin folds the offers at it: its quests on the stop's tooltip, no ! under the disc
  local givers = {}
  local function stopAt(at)
    for _, d in ipairs(list) do
      if d.num and d.m == at.m and ((d.who or d.name) == at.n or (math.abs(d.x - at.x) <= 0.2 and math.abs(d.y - at.y) <= 0.2)) then return d end
    end
    return nil
  end
  for id in pairs(QB:Plan().add) do
    local q = QB.Quest.Get(id)
    if q and not q.repeatable and not QB.state.log[id] and not QB:IsSkipped(id) then
      local st = QB:Status(q)
      if st.code == "todo" or st.code == "prereq" then
        -- a chain: the first open step's giver, or the held step's hand-in (what the click and the arrow aim at)
        local at, label, step = q.give, nil, q
        if st.code == "prereq" and QB.Arrow and QB.Arrow.FirstStep then
          local first, held = QB.Arrow.FirstStep(q, st)
          if first and first ~= q then
            at, step = held and first.turn or first.give, first
            label = (held and "chain: hand in " or "chain: pick up ") .. first.name
          end
        end
        if at and not at.inside and at.m and at.m > 0 then
          local key = at.n .. at.m
          local g = givers[key]
          if not g then
            local stop = stopAt(at)
            if stop then
              stop.pickups, stop.labels = stop.pickups or {}, stop.labels or {}
              g = { ids = stop.ids, quests = stop.pickups, labels = stop.labels, lines = stop.lines, stop = stop }
            else
              g = { m = at.m, x = at.x, y = at.y, name = at.n, who = at.n, ids = {}, icon = T.questAvail, lines = {}, quests = {}, labels = {}, family = "basic" }
              list[#list + 1] = g
            end
            givers[key] = g
          end
          g.ids[q.id], g.ids[step.id] = true, true
          g.quests[#g.quests + 1] = q
          g.labels[q.id] = label or (st.code == "prereq" and "chain first" or nil)
          if not g.stop and P.Family(q) == "recurring" then g.family = "recurring" end
          if not g.stop then g.lines[#g.lines + 1] = { q.name, label or (st.code == "prereq" and "chain first" or QB.Comma(QB.Model.XpAt(q, QB.state.level))) } end
        end
      end
    end
  end
  self.list = list
  return list
end

function P:Update()
  self:Build()
  QB.API.TomTomLater() -- a waypoint TomTom was kept from while the map was open, if the map is shut (else it waits)
  if self.provider and mapOpen() then self.provider:RefreshAllData() end
  for _, layer in ipairs(self.pageLayers) do
    if shown(layer) then layer:RefreshAllData() end
  end
  -- then the quest icons, whenever these pins change (a new plan, /qb pins, Settings): they leave the NPCs these
  -- pins stand on to them
  if QB.QuestMap then QB.Try("map icons", QB.QuestMap.Update, QB.QuestMap) end
  -- during a run TomTom's waypoint follows the route (a quiet one: QuestBank's arrow follows it by itself, and the
  -- game's own pin is never set by QuestBank, Core.lua API.SetWaypoint)
  local r = QB.routeNow
  if QB.Run.Get() and QB:Settings().pins and r and r.legs and r.legs[1] then
    local s = r.legs[1].stop
    local key = s.name .. (s.m or 0) .. (s.x or 0) .. (s.y or 0)
    if key ~= self.next then
      self.next = key
      QB.API.SetWaypoint(s.m, s.x, s.y, s.name, true)
    end
  end
end

function P:PinNext(announce)
  local r = self:Route()
  local leg = r and r.legs and r.legs[1]
  if not leg then
    if announce then QB:Print("Nothing on the route yet.") end
    return
  end
  local s = leg.stop
  QB.API.SetWaypoint(s.m, s.x, s.y, s.name, not announce, false) -- the route's own: the arrow stays as it is
end

function P:Toggle()
  local set = QB:Settings()
  set.pins = not set.pins
  QB:Print(set.pins and "Map pins on." or "Map pins off.")
  self:Update()
end
