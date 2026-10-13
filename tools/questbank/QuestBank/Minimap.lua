-- SPDX-License-Identifier: GPL-3.0-or-later
-- The route on the minimap: a numbered pin for every stop of the hand-in route, a line from stop to stop and from you
-- to the next one, your pick-up list, and the entrances of the dungeons around you. A pin outside the minimap's reach
-- sits on its rim, dimmer, in the direction it lies. Click a pin: a waypoint there, as on the world map. /qb bigmap
-- (or the Big map setting) grows the minimap to most of the screen, zoomed all the way out, so it reads as a map of
-- the area; the same command puts it back. Everything here is QuestBank's own frames laid over the Minimap: nothing
-- of the game's is replaced, and the minimap itself is only resized and zoomed, never in a fight.
--   where a pin is: the stop's map and position go through QB.Model.World to continent yards, as the arrow's do; the
--   minimap's radius in yards comes from C_Minimap.GetViewRadius; rotateMinimap turns the pins with your facing.
local _, QB = ...
local Mini = {}
QB.Mini = Mini

local TICK = 0.1           -- seconds between placements (the pins follow you)
local MAX_PINS = 60        -- route stops, pick-ups and entrances, the nearest first past that
local EDGE = 7             -- the rim: pins past the minimap's reach sit this far inside its edge
local LINE_REACH = 1.6     -- a line is drawn when both ends are within this many radii
Mini.TICK, Mini.MAX_PINS = TICK, MAX_PINS

local plain = QB.Plain
local sqrt, atan2, sin, cos, pi = math.sqrt, math.atan2, math.sin, math.cos, math.pi
local pins, lines, worldOf = {}, {}, {}

local function on() return QB:Settings().minimapPins ~= false end

-- the minimap's reach in yards: the client says; else the Classic zoom table
local ZOOM_YARDS = { 233.33, 200, 166.67, 133.33, 100, 66.67 }
function Mini.Radius()
  if C_Minimap and C_Minimap.GetViewRadius then
    local ok, r = pcall(C_Minimap.GetViewRadius)
    r = ok and plain(r) or nil
    if type(r) == "number" and r > 0 then return r end
  end
  local z = Minimap and Minimap.GetZoom and plain(Minimap:GetZoom()) or 0
  return ZOOM_YARDS[(type(z) == "number" and z or 0) + 1] or 233.33
end

local function rotated()
  if not GetCVar then return false end
  local ok, v = pcall(GetCVar, "rotateMinimap")
  return ok and plain(v) == "1"
end

-- continent yards of a pin's place, kept once per pin key
local function worldPos(d)
  local key = d.m .. ":" .. d.x .. ":" .. d.y
  local w = worldOf[key]
  if w == nil then
    w = QB.Model.World(d.m, d.x, d.y) or false
    worldOf[key] = w
  end
  return w or nil
end

-- screen offset of a world point from where you stand: north up, west left, turned with you when the minimap turns.
-- Returns x, y (pixels), the distance in yards, and whether it is past the rim
function Mini.Project(me, w, radius, R, facing)
  local dn, dw = w.wx - me.wx, w.wy - me.wy
  local d = sqrt(dn * dn + dw * dw)
  local b = atan2(dw, dn) - (facing or 0)
  local px = d / radius * R
  local far = px > R - EDGE
  if far then px = R - EDGE end
  return -sin(b) * px, cos(b) * px, d, far
end

-- what goes on the minimap: the route's stops (numbered), the pick-up list, the dungeon entrances of your continent
function Mini.List()
  local out = {}
  local P = QB.Pins
  if P and P.list then
    for _, d in ipairs(P.list) do
      if d.m and d.m > 0 then out[#out + 1] = { m = d.m, x = d.x, y = d.y, name = d.name, num = d.num, kind = "stop", when = d.when, lines = d.lines, late = d.late } end
    end
  end
  if QB:Settings().minimapPickups ~= false and QB.Arrow and QB.Arrow.ListFor then
    for _, d in ipairs(QB.Arrow.ListFor("pickup") or {}) do
      if d.m and d.m > 0 then out[#out + 1] = { m = d.m, x = d.x, y = d.y, name = d.name, kind = "pickup" } end
    end
  end
  if QB:Settings().minimapEntrances ~= false then
    for _, c in ipairs(QB.Data.CAT) do
      local e = c.entrance
      if c.dungeon and e and e.m and e.m > 0 then out[#out + 1] = { m = e.m, x = e.x, y = e.y, name = c.name, kind = "dungeon", icon = c.icon } end
    end
  end
  return out
end

local overlay
local function overlayFrame()
  if overlay then return overlay end
  overlay = CreateFrame("Frame", "QuestBankMinimap", Minimap)
  overlay:SetAllPoints(Minimap)
  overlay:SetFrameLevel((Minimap:GetFrameLevel() or 2) + 5)
  overlay.elapsed = 0
  overlay:SetScript("OnUpdate", QB.Safe(function(self, dt)
    self.elapsed = self.elapsed + (dt or 0)
    if self.elapsed < TICK then return end
    self.elapsed = 0
    Mini.Place()
  end, "minimap pins"))
  return overlay
end

local T
local function pin(i)
  local p = pins[i]
  if p then return p end
  T = T or QB.Data.TEX
  p = CreateFrame("Button", nil, overlayFrame())
  p:SetSize(16, 16)
  p.icon = p:CreateTexture(nil, "ARTWORK")
  p.icon:SetAllPoints()
  p.num = p:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  p.num:SetPoint("CENTER", 0, 0)
  p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  p:SetScript("OnClick", QB.Safe(function(self, button)
    local d = self.d
    if not d then return end
    if button == "RightButton" then
      if d.kind == "stop" and QB.UI and QB.UI.StopMenu then QB.UI.StopMenu(d) end
      return
    end
    QB.API.SetWaypoint(d.m, d.x, d.y, d.name)
  end, "minimap pin"))
  p:SetScript("OnEnter", function(self)
    local d = self.d
    if not d then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(d.name or "", 1, 1, 1)
    if d.when then GameTooltip:AddLine(d.when, 0.8, 0.8, 0.8) end
    for _, l in ipairs(d.lines or {}) do GameTooltip:AddDoubleLine(l[1], l[2], 0.9, 0.9, 0.9, 0.6, 0.8, 0.6) end
    if d.kind == "dungeon" then GameTooltip:AddLine("Dungeon entrance", 0.8, 0.8, 0.8) end
    if d.kind == "pickup" then GameTooltip:AddLine("On your pick-up list", 0.8, 0.8, 0.8) end
    GameTooltip:AddLine(string.format("%d yards. Click: waypoint.", self.yards or 0), 0.5, 0.5, 0.5)
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  pins[i] = p
  return p
end

local function line(i)
  local l = lines[i]
  if l then return l end
  local f = overlayFrame()
  if not f.CreateLine then return nil end
  l = f:CreateLine(nil, "BACKGROUND")
  l:SetThickness(2)
  l:SetColorTexture(1, 0.82, 0.3, 0.6)
  lines[i] = l
  return l
end

local function style(p, d)
  T = T or QB.Data.TEX
  if d.kind == "stop" then
    p.icon:SetTexture(T.mapPin)
    p.icon:SetTexCoord(0, 1, 0, 1)
    p.num:SetText(d.num and tostring(d.num) or "")
    p:SetSize(18, 18)
  elseif d.kind == "dungeon" then
    p.icon:SetTexture(d.icon or T.ring)
    p.num:SetText("")
    p:SetSize(14, 14)
  else
    p.icon:SetTexture(T.questAvail)
    p.num:SetText("")
    p:SetSize(14, 14)
  end
end

-- place every pin for where you stand now
function Mini.Place()
  if not on() then Mini.Clear(); return end
  local me = QB.API.WorldPosition()
  local f = overlayFrame()
  if not me then Mini.Clear(); return end
  local R = (Minimap:GetWidth() or 140) / 2
  local radius = Mini.Radius()
  local facing = rotated() and (GetPlayerFacing and plain(GetPlayerFacing())) or 0
  if type(facing) ~= "number" then facing = 0 end
  local list, placed, n = Mini.List(), {}, 0
  -- nearest first when there are too many
  local pts = {}
  for _, d in ipairs(list) do
    local w = worldPos(d)
    if w and w.c == me.c then
      local x, y, yards, far = Mini.Project(me, w, radius, R, facing)
      pts[#pts + 1] = { d = d, x = x, y = y, yards = yards, far = far }
    end
  end
  table.sort(pts, function(a, b) if a.d.kind ~= b.d.kind then return a.d.kind == "stop" end return a.yards < b.yards end)
  for i, pt in ipairs(pts) do
    if i > MAX_PINS then break end
    local p = pin(i)
    style(p, pt.d)
    p.d, p.yards = pt.d, pt.yards
    p:ClearAllPoints()
    p:SetPoint("CENTER", f, "CENTER", pt.x, pt.y)
    p:SetAlpha(pt.far and 0.55 or 1)
    p:Show()
    n = n + 1
    if pt.d.kind == "stop" and pt.d.num then placed[pt.d.num] = pt end
  end
  for i = n + 1, #pins do pins[i]:Hide() end
  -- lines: you to stop 1, then stop to stop, where both ends are near enough
  local li = 0
  if QB:Settings().minimapLines ~= false then
    local prev = { x = 0, y = 0, far = false, yards = 0 }
    local num = 1
    while placed[num] do
      local pt = placed[num]
      if not prev.far and not pt.far and pt.yards <= radius * LINE_REACH and prev.yards <= radius * LINE_REACH then
        li = li + 1
        local l = line(li)
        if l then
          l:SetStartPoint("CENTER", f, prev.x, prev.y)
          l:SetEndPoint("CENTER", f, pt.x, pt.y)
          l:Show()
        end
      end
      prev, num = pt, num + 1
    end
  end
  for i = li + 1, #lines do lines[i]:Hide() end
  Mini.shown, Mini.linesShown = n, li
  Mini.DrawTrails(me, radius, R, facing, f)
end

-- your walked trails (Walk.lua), as thin lines under the pins
local trailLines = {}
function Mini.DrawTrails(me, radius, R, facing, f)
  local n = 0
  if QB.Walk and QB:Settings().walkShow ~= false and f.CreateLine then
    for _, seg in ipairs(QB.Walk.Near(me.c, me.wx, me.wy, radius * 1.1)) do
      local x1, y1, _, far1 = Mini.Project(me, { wx = seg[1], wy = seg[2] }, radius, R, facing)
      local x2, y2, _, far2 = Mini.Project(me, { wx = seg[3], wy = seg[4] }, radius, R, facing)
      if not (far1 and far2) then
        n = n + 1
        local l = trailLines[n]
        if not l then
          l = f:CreateLine(nil, "BACKGROUND", nil, -1)
          l:SetThickness(3)
          l:SetColorTexture(1, 0.85, 0.4, 0.28)
          trailLines[n] = l
        end
        l:SetStartPoint("CENTER", f, x1, y1)
        l:SetEndPoint("CENTER", f, x2, y2)
        l:Show()
      end
    end
  end
  for i = n + 1, #trailLines do trailLines[i]:Hide() end
  Mini.trailsShown = n
end

function Mini.Clear()
  for _, p in ipairs(pins) do p:Hide() end
  for _, l in ipairs(lines) do l:Hide() end
  for _, l in ipairs(trailLines) do l:Hide() end
  Mini.shown, Mini.linesShown, Mini.trailsShown = 0, 0, 0
end

function Mini.Invalidate() worldOf = {} end

-- the big map: the minimap grown to most of the screen and zoomed out, and back
local saved
function Mini.Big(on)
  if InCombatLockdown and InCombatLockdown() then QB:Print("Not in a fight: the minimap stays as it is until you are out."); return false end
  if on == nil then on = not saved end
  if on and not saved then
    local w, h = Minimap:GetWidth(), Minimap:GetHeight()
    local pt = { Minimap:GetPoint(1) }
    saved = { w = w, h = h, pt = pt, zoom = Minimap.GetZoom and Minimap:GetZoom() or 0 }
    local size = math.floor(math.min((UIParent:GetHeight() or 900) - 140, (UIParent:GetWidth() or 1600) - 200))
    Minimap:SetSize(size, size)
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", UIParent, "CENTER", 0, 10)
    if Minimap.SetZoom then Minimap:SetZoom(0) end
    QB:Print("The big map is up. /qb bigmap puts the minimap back.")
  elseif not on and saved then
    Minimap:SetSize(saved.w, saved.h)
    Minimap:ClearAllPoints()
    if saved.pt[1] then Minimap:SetPoint(unpack(saved.pt)) end
    if Minimap.SetZoom then Minimap:SetZoom(saved.zoom) end
    saved = nil
  end
  Mini.Place()
  return saved ~= nil
end
function Mini.IsBig() return saved ~= nil end

function Mini:Init()
  if self.ready then return end
  self.ready = true
  if not (Minimap and QB.Model and QB.Model.World) then return end
  local f = CreateFrame("Frame")
  f:SetScript("OnEvent", QB.Safe(function(_, event)
    if event == "PLAYER_REGEN_DISABLED" and saved then Mini.Big(false) end -- a fight: the minimap goes back
    Mini.Invalidate()
    Mini.Place()
  end, "minimap pins"))
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "MINIMAP_UPDATE_ZOOM", "PLAYER_REGEN_DISABLED" }) do
    pcall(f.RegisterEvent, f, e)
  end
  overlayFrame()
  Mini.InitTracking()
end

----------------------------------------------------------------------------
-- Target and Focus on the minimap. The client can show your target and your focus as dots on the minimap, but its
-- tracking menu lists the two only with the console's minimapTrackingShowAll on, and forgets the choice at every
-- loading screen. QuestBank adds the two to the menu, keeps the choice per character (Target on until you say
-- otherwise), and sets it again after each loading screen; with show-all on it does nothing, the game lists them.
----------------------------------------------------------------------------
local FILTER = { target = 16384, focus = 32768 } -- Enum.MinimapTrackingFilter.Target and .Focus
local NAMES = { target = "Target", focus = "Focus" }

local function trackDB()
  QuestBankDB = QuestBankDB or {}
  QuestBankDB.chars = QuestBankDB.chars or {}
  local key = QB:CharKey()
  local c = QuestBankDB.chars[key]
  if type(c) ~= "table" then c = {}; QuestBankDB.chars[key] = c end
  if type(c.track) ~= "table" then c.track = { target = true } end
  return c.track
end
Mini.TrackDB = trackDB

local function showAll()
  if C_CVar and C_CVar.GetCVarBool then
    local ok, v = pcall(C_CVar.GetCVarBool, "minimapTrackingShowAll")
    return ok and plain(v) == true
  end
  if GetCVar then
    local ok, v = pcall(GetCVar, "minimapTrackingShowAll")
    return ok and plain(v) == "1"
  end
  return false
end

-- the tracking index of Target or Focus, by the client's filter id, else by name
local function trackIndex(which)
  if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingFilter) then return nil end
  local ok, n = pcall(C_Minimap.GetNumTrackingTypes)
  n = ok and plain(n) or 0
  local want = (Enum and Enum.MinimapTrackingFilter and Enum.MinimapTrackingFilter[NAMES[which]]) or FILTER[which]
  for i = 1, n do
    local okF, f = pcall(C_Minimap.GetTrackingFilter, i)
    if okF and type(f) == "table" and plain(f.filterID) == want then return i end
  end
  for i = 1, n do
    local okI, info = pcall(C_Minimap.GetTrackingInfo, i)
    if okI and type(info) == "table" and plain(info.name) == NAMES[which] then return i end
  end
  return nil
end

function Mini.TrackOn(which)
  local i = trackIndex(which)
  if not i then return nil end
  local ok, info = pcall(C_Minimap.GetTrackingInfo, i)
  return ok and type(info) == "table" and plain(info.active) == true
end

function Mini.SetTrack(which, on)
  trackDB()[which] = on and true or false
  local i = trackIndex(which)
  if i and C_Minimap.SetTracking then pcall(C_Minimap.SetTracking, i, on and true or false) end
end

-- after a loading screen: the saved choices, when the game's own menu does not carry them
function Mini.ApplyTracking()
  if showAll() then return false end
  local saved = trackDB()
  local n = 0
  for which in pairs(NAMES) do
    if saved[which] ~= nil then
      local i = trackIndex(which)
      if i and C_Minimap.SetTracking then pcall(C_Minimap.SetTracking, i, saved[which] == true); n = n + 1 end
    end
  end
  return n
end

function Mini.TrackingMenu(owner, root)
  if showAll() or not root then return end
  if root.CreateDivider then root:CreateDivider() end
  if root.CreateTitle then root:CreateTitle("QuestBank") end
  for _, which in ipairs({ "target", "focus" }) do
    if trackIndex(which) and root.CreateCheckbox then
      root:CreateCheckbox(NAMES[which] .. " on the minimap",
        function() return Mini.TrackOn(which) == true end,
        function() Mini.SetTrack(which, not Mini.TrackOn(which)) end)
    end
  end
end

function Mini.InitTracking()
  if Mini.trackReady then return end
  Mini.trackReady = true
  if Menu and Menu.ModifyMenu then
    pcall(Menu.ModifyMenu, "MENU_MINIMAP_TRACKING", function(owner, root) QB.Try("minimap tracking menu", Mini.TrackingMenu, owner, root) end)
  end
  local f = CreateFrame("Frame")
  f:SetScript("OnEvent", QB.Safe(function()
    Mini.ApplyTracking()
    C_Timer.After(3, QB.Safe(Mini.ApplyTracking, "minimap tracking")) -- the game may reset it a moment after the load
  end, "minimap tracking"))
  pcall(f.RegisterEvent, f, "PLAYER_ENTERING_WORLD")
end
