-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank map pins: a numbered pin on the world map for every stop on the route, and a ! where a
-- quest you plan to fetch starts. A click on one is a waypoint (Core.lua, API.SetWaypoint); a Ctrl+click goes through
-- to the map, where the game places its own pin (P.through, below).
local _, QB = ...
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

-- a frame that takes the mouse: taking it, or letting it through to the map while P.through
local function mouseFor(f)
  if not f.kind.mouse then return end
  local want = not P.through
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

-- layers that were told to redraw in combat: they draw when combat ends (or the game stops holding addons back), if
-- the map is still open; opening it later draws anyway
local afterCombat = {}
local function redrawLater()
  if inCombat() then return end
  local list = {}
  for layer in pairs(afterCombat) do list[#list + 1] = layer end
  afterCombat = {}
  if mapOpen() then
    for _, layer in ipairs(list) do layer:RefreshAllData() end
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

-- the frame level the map gives pins of this type (MapCanvas_PinFrameLevelsManager: read only)
local function frameLevel(map, levelType)
  local mgr = ask(map, "GetPinFrameLevelsManager")
  if type(mgr) ~= "table" then return nil end
  return tonumber(ask(mgr, "GetValidFrameLevel", levelType))
end

-- a method of the frame's kind, or nil (read from the kind: a frame answers only for what it has)
local function method(f, name)
  local m = f.kind and f.kind.methods
  return m and m[name] or nil
end

-- the mouse on QuestBank's frames: its own scripts (the canvas's are for its own pins)
local function onEnter(f) local fn = method(f, "OnMouseEnter"); if fn then fn(f) end end
local function onLeave(f) local fn = method(f, "OnMouseLeave"); if fn then fn(f) end end
local onMouseUp = QB.Safe(function(f, button, upInside)
  if upInside == false then return end -- let go outside the frame
  local fn = method(f, "OnMouseClickAction")
  if fn then fn(f, button) end
end, "map pin click")

local Layer = {}

-- a new frame of this kind, on the canvas: out of combat only
-- a right-click goes on to the map below, which zooms out. SetPassThroughButtons is protected and restricted in combat:
-- called once a frame, out of combat and when the client allows it (a frame made when it didn't gets it on a later draw)
local function passThrough(f)
  if f.passSet or not f.SetPassThroughButtons or not mayProtect(f) then return end
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
    f:SetScript("OnMouseUp", onMouseUp)
    passThrough(f)
  else
    f:EnableMouse(false)
  end
  self.made = (self.made or 0) + 1
  return f
end

-- where a frame stands: x and y fractions of the map, placed as Blizzard_MapCanvas.lua's ApplyPinPosition does.
-- scales: each kind's scale, worked out once for a whole draw or zoom step
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
  f:SetPoint("CENTER", canvas, "TOPLEFT", (canvas:GetWidth() or 0) * f.mapX / scale, -(canvas:GetHeight() or 0) * f.mapY / scale)
end

-- one frame of this kind for data at (x, y): one put away, or a new one; at the map's level for its type
function Layer:Add(kind, data, x, y, levelType)
  self.free[kind] = self.free[kind] or {}
  local f = table.remove(self.free[kind]) or self:Make(kind)
  if not f then return nil end
  if kind.mouse and not f.passSet then passThrough(f) end
  mouseFor(f)
  f.data, f.mapX, f.mapY, f.levelType = data, x, y, levelType or kind.level
  local level = frameLevel(self:GetMap(), f.levelType)
  if level then f:SetFrameLevel(level) end
  local setup = method(f, "Setup")
  if setup then setup(f, data) end
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
    f.data = nil
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
function Layer:OnHide() P.AfterClose() end

-- zoomed, or the map made bigger or smaller: every frame placed and sized again (allowed in combat: QuestBank's own)
function Layer:OnCanvasScaleChanged()
  local scales = {}
  for _, f in ipairs(self.active) do self:Place(f, scales) end
end

-- a layer on the world map: draw(layer, mapID) adds its frames (layer:Add), after the last draw's are put away.
-- Whatever goes wrong in it stays in it: the map runs every provider in one loop
function P.NewLayer(draw, where)
  local layer = CreateFromMixins(MapCanvasDataProviderMixin, Layer)
  layer.draw, layer.active, layer.free, layer.canvas = draw, {}, {}, WorldMapFrame:GetCanvas()
  layer.RefreshAllData = QB.Safe(Layer.RefreshAllData, where)
  layer.OnCanvasScaleChanged = QB.Safe(Layer.OnCanvasScaleChanged, where)
  layer.OnCanvasSizeChanged = layer.OnCanvasScaleChanged
  layer.OnHide = QB.Safe(Layer.OnHide, where)
  P.layers[#P.layers + 1] = layer
  if not P.watcher then
    -- on the canvas, so it runs only while the map is open; no mouse, nothing drawn
    P.watcher = CreateFrame("Frame", nil, layer.canvas)
    P.watcher:SetScript("OnUpdate", watchKeys)
  end
  WorldMapFrame:AddDataProvider(layer)
  return layer
end

----------------------------------------------------------------------------
-- the route's pins
----------------------------------------------------------------------------
-- QuestBankPinTemplate (Pins.xml) with these on top
local Pin = {}
P.Pin = Pin

function Pin:Setup(data)
  self.Icon:SetTexture(data.icon)
  self.Icon:SetDesaturated(data.late or false)
  self.Num:SetText(data.num and tostring(data.num) or "")
end

Pin.OnMouseEnter = QB.Safe(function(self)
  local d = self.data
  if not d then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine((d.num and (d.num .. ". ") or "") .. d.name, 1, 0.82, 0)
  if d.when then GameTooltip:AddLine(d.when, 0.8, 0.8, 0.8) end
  for _, line in ipairs(d.lines or {}) do GameTooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 0.6, 1, 0.6) end
  -- the quest icons leave the NPC under this pin to it: what they would have shown there
  if QB.QuestMap and QB.QuestMap.AlsoHere then
    local map = self.layer and self.layer:GetMap()
    QB.QuestMap.AlsoHere(GameTooltip, d, map and QB.Plain(map:GetMapID()))
  end
  GameTooltip:AddLine("Click: waypoint here.", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end, "map pin tooltip")

function Pin:OnMouseLeave() GameTooltip:Hide() end

function Pin:OnMouseClickAction(button)
  local d = self.data
  if d and button ~= "RightButton" then QB.API.SetWaypoint(d.m, d.x, d.y, d.name) end
end

-- the numbered pins: over the quest icons (AREA_POI), a little bigger as you zoom in
local ROUTE = { template = "QuestBankPinTemplate", level = "PIN_FRAME_LEVEL_AREA_POI", scale = { 1, 1.0, 1.25 }, mouse = true, methods = Pin }
P.ROUTE = ROUTE

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

function P:Init()
  if self.provider or self.waiting then return end
  self.waiting = P.WhenMap(function()
    if P.provider then return end
    P.provider = P.NewLayer(function(layer, shown)
      if not QB:Settings().pins then return end
      for _, d in ipairs(P.list) do
        local x, y = project(d, shown)
        if x then layer:Add(ROUTE, d, x, y) end
      end
    end, "map pins")
  end, "map pins: waiting for the map")
end

-- the route on screen: the run's rest, or what is banked now, else the full plan
function P:Route()
  local now, plan = QB.routeNow, QB.routePlan
  if QB.Run.Get() or (now and now.legs and #now.legs > 0) then return now end
  return plan
end

function P:Build()
  local list = {}
  local T = QB.Data.TEX
  local r = self:Route()
  if r and r.legs then
    for i, leg in ipairs(r.legs) do
      local s = leg.stop
      if s.m and s.m > 0 then
        local lines, ids = {}, {}
        for _, row in ipairs(leg.rows) do
          lines[#lines + 1] = { row.q.name, QB.Comma(row.xp) }
          ids[row.q.id] = true
        end
        -- who: the NPC the pin stands on (a stop stands at its first NPC, and may be named for its town or place);
        -- ids: the quests it lists. The quest icons (QuestMap.lua) read both
        local first = s.npcs and s.npcs[1] and QB.Data.NPC[s.npcs[1]]
        list[#list + 1] = { m = s.m, x = s.x, y = s.y, num = i, name = s.name, who = first and first[1] or nil, ids = ids, icon = T.questActive,
                            late = (leg.late and r.goal == "hour") or nil,
                            when = string.format("At %s, level %.1f to %.1f", QB.Clock(leg.t), leg.arrive, leg.leave), lines = lines }
      end
    end
  end
  -- where the quests you plan to fetch start
  local givers = {}
  for id in pairs(QB:Plan().add) do
    local q = QB.Quest.Get(id)
    if q and not q.repeatable and not QB.state.log[id] then
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
            g = { m = at.m, x = at.x, y = at.y, name = at.n, who = at.n, ids = {}, icon = T.questAvail, when = "Pick up", lines = {} }
            givers[key] = g
            list[#list + 1] = g
          end
          g.ids[q.id], g.ids[step.id] = true, true
          g.lines[#g.lines + 1] = { q.name, label or (st.code == "prereq" and "chain first" or QB.Comma(QB.Model.XpAt(q, QB.state.level))) }
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
