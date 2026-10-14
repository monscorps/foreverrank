-- SPDX-License-Identifier: GPL-3.0-or-later AND MIT
-- Contains code from QuestTrail 3.0.6, Copyright (c) 2026 Krom, MIT licence (LICENSE-QuestTrail.txt): QuestTrail_Minimap.lua: MV, Tiles, Extended, Square, Reach, View, Frame, SetShape, Tile, DrawGround, DrawPlayer, NativePlayer, Cursor, ScreenToMap, Wheel, Menu, Recentre, OnMouseDown, OnMouseUp, OnUpdateDrag, ZoomButtons, Hook, Moving, Tick
-- The minimap's view, after QuestTrail's extended minimap. Centred on you at the game's own zoom levels it is the
-- game's minimap as it is. Wheeled out past the game's widest (1.5 times a step, up to 12,000 yards across) or dragged
-- away from you, the ground is drawn from the game's own minimap tiles (MinimapTiles.lua) over the minimap, cut by the
-- minimap's own mask, with your arrow on it; 3 seconds after a drag it eases back to you. A click that does not drag
-- pings, as the game's does; a right-click opens the minimap's menu. Indoors, or where no tile is known, the game's
-- minimap shows. Everything QuestBank draws on the minimap goes through one view (MV.View): its centre and radius in
-- continent yards (QB.Model.World's), its scale in pixels a yard and its turn.
local _, QB = ...
local MV = { MAX_YARDS = 12000, STEP = 1.5, SMOOTH = 0.12, DRAG = 4, RETURN = 3, TILE = 1600 / 3, ARROW = 32 }
QB.MiniView = MV

local plain = QB.Plain
local floor, sqrt, cos, sin, min, max, exp, abs = math.floor, math.sqrt, math.cos, math.sin, math.min, math.max, math.exp, math.abs

-- the view's state: the radius shown past the game's widest (nil at the game's own levels) and, dragged away from you,
-- the centre; the shown centre (cur) eases toward the wanted one (MV.SMOOTH seconds)
MV.want = { r = nil, wx = nil, wy = nil }
MV.cur = { r = nil, wx = nil, wy = nil }

-- on unless switched off, or QuestTrail is loaded too (its own minimap takes the same scripts)
function MV.On() return not MV.blocked and Minimap ~= nil and QB:Settings().mmExtended ~= false end

-- QuestTrail loaded as well: QuestBank leaves the minimap's scripts to it for the session
function MV.Guard()
  if not (C_AddOns and C_AddOns.IsAddOnLoaded) then return false end
  local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, "QuestTrail")
  if ok and plain(loaded) then
    MV.blocked = true
    QB:Print("QuestTrail is loaded: its minimap zooms and drags, QuestBank's far zoom is off.")
  end
  return MV.blocked or false
end

-- the tiles of your continent (QB.Model.World's 0 and 1), and the one under a spot: the game's 64 by 64 grid of
-- 533-yard squares, counted from the world's north-west corner
local CONTINENT = { [0] = "azeroth", [1] = "kalimdor" }
local function tilesOn(c) return QB.MinimapTiles and QB.MinimapTiles[CONTINENT[c] or ""] end
local function tileKey(wx, wy) return floor(32 - wy / MV.TILE) * 100 + floor(32 - wx / MV.TILE) end

local function zoom()
  local ok, z = pcall(Minimap.GetZoom, Minimap)
  z = ok and plain(z) or nil
  return type(z) == "number" and z or 0
end
local function indoors()
  if not IsIndoors then return false end
  local ok, v = pcall(IsIndoors)
  return ok and plain(v) and true or false
end

-- the game's widest reach outdoors, read at its zoom 0 (C_Minimap.GetViewRadius through Mini.Radius), so the far steps
-- start where the game's levels end; the Classic table's until it has been seen
function MV.NativeMax()
  if zoom() == 0 and not indoors() then MV.nativeMax = QB.Mini.Radius() end
  return MV.nativeMax or 233.33
end

-- whether the ground is drawn now (wheeled out past the game's widest, or dragged), and if not, why
function MV.Extended(me)
  if not MV.On() then return false, "off" end
  if indoors() then return false, "indoors" end
  me = me or QB.API.WorldPosition()
  local ids = me and tilesOn(me.c)
  if not ids then return false, "no tiles here" end
  local cur = MV.cur
  if not (cur.wx or (cur.r and cur.r > MV.NativeMax() + 1)) then return false, "the game's zoom" end
  -- (a zone the table lacks, Forever's own: the game's minimap)
  if not ids[tileKey(cur.wx or me.wx, cur.wy or me.wy)] then return false, "no tile under the centre" end
  return true
end

-- how far out (sx, sy) is against the half width: the circle's distance on a round minimap, the square's on a square
-- one (GetMinimapShape, as addons that square it set it); asked once a frame
local squareAt, squareWas = -1, false
function MV.Square()
  local now = GetTime()
  if now ~= squareAt then
    squareAt = now
    local ok, shape = false, nil
    if GetMinimapShape then ok, shape = pcall(GetMinimapShape) end
    squareWas = ok and shape == "SQUARE" or false
  end
  return squareWas
end
function MV.Reach(sx, sy)
  if MV.Square() then return max(abs(sx), abs(sy)) end
  return sqrt(sx * sx + sy * sy)
end

-- the minimap turns with you (rotateMinimap); your facing, nil while the client keeps it secret
function MV.Rotated()
  if not GetCVar then return false end
  local ok, v = pcall(GetCVar, "rotateMinimap")
  return ok and plain(v) == "1"
end
function MV.Facing()
  if not GetPlayerFacing then return nil end
  local ok, f = pcall(GetPlayerFacing)
  f = ok and plain(f) or nil
  return type(f) == "number" and f or nil
end

-- The view for you at me ({c, wx, wy}): its centre (you, or where it was dragged), its radius in yards, the minimap's
-- half width R in pixels and the scale between them, its turn (cos, sin) and whether the ground is drawn
function MV.View(me)
  local facing = MV.Rotated() and MV.Facing() or 0
  local ext = MV.Extended(me)
  local cur = MV.cur
  local R = (Minimap:GetWidth() or 140) / 2
  local radius = ext and cur.r or QB.Mini.Radius()
  return { c = me.c, wx = ext and cur.wx or me.wx, wy = ext and cur.wy or me.wy, radius = radius, R = R, scale = R / radius,
           cs = cos(facing), sn = sin(facing), facing = facing, ext = ext, square = MV.Square() }
end

-- a world spot on the minimap: pixels from its centre, x right and y up (Mini.Project's, without the rim)
function MV.Point(v, wx, wy)
  local e, n = v.wy - wy, wx - v.wx
  return (e * v.cs + n * v.sn) * v.scale, (-e * v.sn + n * v.cs) * v.scale
end
-- and back: a point of the minimap to continent yards
local function toWorld(v, sx, sy)
  local e = (sx * v.cs - sy * v.sn) / v.scale
  local n = (sx * v.sn + sy * v.cs) / v.scale
  return v.wx + n, v.wy - e
end

-------------------------------------------------------------------------
-- The ground: a pool of tile textures over the minimap, masked to its shape. Laid out once for a view, then moved and
-- scaled whole (two calls to the game for a step or a zoom, not two for every tile)
-------------------------------------------------------------------------
local frame, mask, ground, gmask, tiles = nil, nil, nil, nil, {}
MV.drawn = {} -- the view the tiles were last laid out for
local function groundFrame()
  if frame then return frame end
  frame = CreateFrame("Frame", nil, Minimap)
  frame:SetAllPoints(Minimap)
  frame:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 1)
  frame:SetClipsChildren(true)
  mask = frame:CreateMaskTexture()
  mask:SetAllPoints(frame)
  ground = CreateFrame("Frame", nil, frame)
  ground:SetSize(100, 100)
  ground:SetPoint("CENTER", frame, "CENTER")
  gmask = ground:CreateMaskTexture()
  gmask:SetAllPoints(frame)
  -- under the tiles a deep sea colour, where the game has none (the open sea, the world's edge)
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(frame)
  bg:SetColorTexture(0.05, 0.11, 0.16, 1)
  bg:AddMaskTexture(mask)
  frame:Hide()
  MV.frame = frame
  return frame
end

-- the minimap's own shape: the game's minimap mask (Blizzard_Minimap/Camelot/Skin.lua), a circle where the client lacks
-- it, the whole square on a square minimap
local MASK_ATLAS = "ui-hud-minimap-frame-generic-mask"
local function setMask(m, square)
  if not square and C_Texture and C_Texture.GetAtlasInfo then
    local ok, info = pcall(C_Texture.GetAtlasInfo, MASK_ATLAS)
    if ok and info and pcall(m.SetAtlas, m, MASK_ATLAS) then return "atlas" end
  end
  m:SetTexture(square and "Interface\\Buttons\\WHITE8X8" or "Interface\\COMMON\\CommonMaskCircle", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  return square and "square" or "circle"
end
local function setShape(square)
  -- (true or false, never nil: a mask left without a texture hides the whole ground)
  square = square and true or false
  if MV.square == square then return end
  MV.square = square
  MV.maskKind = setMask(mask, square)
  setMask(gmask, square)
end

local function tile(i)
  local t = tiles[i]
  if not t then
    t = ground:CreateTexture(nil, "ARTWORK")
    t:AddMaskTexture(gmask)
    tiles[i] = t
  end
  return t
end

-- the ground for the view: false where the continent has no tiles
local function drawGround(v)
  local ids = tilesOn(v.c)
  if not ids then return false end
  local T, lay, cwx, cwy = MV.TILE, MV.drawn, v.wx, v.wy
  local need = v.radius * (v.square and 1.42 or 1)
  -- laid out again only when the tiles no longer cover the view, or are too far from its scale (blurred, or too many),
  -- or the minimap turns (each tile turned round the centre, every update), or its shape or size changed
  local k = lay.scale and v.scale / lay.scale or 0
  local moved = lay.cwx and max(abs(cwx - lay.cwx), abs(cwy - lay.cwy)) or 0
  if v.facing ~= 0 or lay.turned or lay.c ~= v.c or lay.R ~= v.R or lay.square ~= v.square
    or k < 0.8 or k > 1.25 or moved + need > lay.reach then
    -- the tiles the minimap shows and a quarter as much again around them for walking and zooming out (no more than
    -- the farthest zoom shows); turned, half a tile's diagonal more and nothing around
    local turned = v.facing ~= 0
    local needMax = MV.MAX_YARDS / 2 * (v.square and 1.42 or 1)
    local reach = turned and (need + T * 0.71) or (max(min(need * 1.25, needMax), need * 1.1) + T * 0.5)
    lay.c, lay.R, lay.square, lay.turned, lay.cwx, lay.cwy, lay.scale, lay.reach = v.c, v.R, v.square, turned or nil, cwx, cwy, v.scale, reach
    local c0, c1 = floor(32 - (cwy + reach) / T), floor(32 - (cwy - reach) / T)
    local r0, r1 = floor(32 - (cwx + reach) / T), floor(32 - (cwx - reach) / T)
    local used, size = 0, T * v.scale + 1
    for col = c0, c1 do
      for row = r0, r1 do
        local id = ids[col * 100 + row]
        if id then
          local sx, sy = MV.Point(v, (32 - row - 0.5) * T, (32 - col - 0.5) * T)
          used = used + 1
          local t = tile(used)
          -- (the game called only for what changed)
          if t.id ~= id then t:SetTexture(id); t.id = id end
          if t.size ~= size then t:SetSize(size, size); t.size = size end
          if t.sx ~= sx or t.sy ~= sy then t:SetPoint("CENTER", ground, "CENTER", sx, sy); t.sx, t.sy = sx, sy end
          if t.rot ~= v.facing then t:SetRotation(-v.facing); t.rot = v.facing end
          if not t:IsShown() then t:Show() end
        end
      end
    end
    for i = used + 1, #tiles do if tiles[i]:IsShown() then tiles[i]:Hide() end end
    MV.layouts, MV.tilesShown = (MV.layouts or 0) + 1, used
    k = 1
  end
  -- the tiles laid out moved and scaled whole: where their centre is now, in their own scale
  local sx, sy = 0, 0
  if k ~= 1 or lay.cwx ~= cwx or lay.cwy ~= cwy then
    local e, n = cwy - lay.cwy, lay.cwx - cwx
    sx, sy = e * v.scale / k, n * v.scale / k
  end
  if lay.k ~= k then ground:SetScale(k); lay.k = k end
  if lay.sx ~= sx or lay.sy ~= sy then
    ground:ClearAllPoints()
    ground:SetPoint("CENTER", frame, "CENTER", sx, sy)
    lay.sx, lay.sy = sx, sy
  end
  return true
end

-------------------------------------------------------------------------
-- Your arrow over the ground (the game's own is under it there): the game's MinimapArrow, above QuestBank's pins.
-- The game's arrow is left alone (QuestTrail sized it away, a call Forever's minimap does not have)
-------------------------------------------------------------------------
local arrowFrame, arrow
local function drawPlayer(v, me)
  if not arrowFrame then
    arrowFrame = CreateFrame("Frame", nil, Minimap)
    arrowFrame:SetAllPoints(Minimap)
    arrow = arrowFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    arrow:SetSize(MV.ARROW, MV.ARROW)
    MV.arrow = arrow
  end
  local lvl = (Minimap:GetFrameLevel() or 1) + 9
  if arrowFrame:GetFrameLevel() ~= lvl then arrowFrame:SetFrameLevel(lvl) end
  local sx, sy = MV.Point(v, me.wx, me.wy)
  if arrow.sx ~= sx or arrow.sy ~= sy then
    arrow:ClearAllPoints()
    arrow:SetPoint("CENTER", arrowFrame, "CENTER", sx, sy)
    arrow.sx, arrow.sy = sx, sy
  end
  -- your way, or up on a minimap that turns with you; no arrow while your facing is secret
  local f = MV.Facing()
  local rot = f and (MV.Rotated() and 0 or f)
  if rot and arrow.rot ~= rot then arrow:SetRotation(rot); arrow.rot = rot end
  local inside = rot ~= nil and MV.Reach(sx, sy) <= v.R
  if arrow.inside ~= inside then arrow:SetShown(inside); arrow.inside = inside end
  if not arrowFrame:IsShown() then arrowFrame:Show() end
end
local function hidePlayer() if arrowFrame then arrowFrame:Hide() end end

-------------------------------------------------------------------------
-- The mouse: the wheel zooms (the game's levels first, then further out), a drag pans, a click that does not drag
-- pings (where it was clicked, for the game's minimap), a right-click opens the menu
-------------------------------------------------------------------------
local mouse -- the press: where (pixels from the minimap's centre), the view then, and whether it has moved
local function cursor()
  local x, y = GetCursorPosition()
  local s = Minimap:GetEffectiveScale() or 1
  local cx, cy = Minimap:GetCenter()
  if not (x and cx) then return nil end
  return x / s - cx, y / s - cy
end

-- the wheel (Mini.Wheel, without Ctrl): in, the far steps first and then the game's levels; out, the game's levels
-- first and then past its widest. The zoom changes at once; only a pan eases
function MV.Wheel(delta)
  local cur = MV.cur
  local r, z, native = cur.r, zoom(), MV.NativeMax()
  local ok, levels = pcall(Minimap.GetZoomLevels, Minimap)
  levels = ok and plain(levels) or 6
  if type(levels) ~= "number" then levels = 6 end
  if delta > 0 then
    if r then
      r = r / MV.STEP
      if r <= native + 1 then r = nil end
    elseif z < levels - 1 then
      pcall(Minimap.SetZoom, Minimap, z + 1)
    end
  elseif delta < 0 then
    if z > 0 and not r then
      pcall(Minimap.SetZoom, Minimap, z - 1)
    else
      local me = QB.API.WorldPosition()
      local ids = me and not indoors() and tilesOn(me.c)
      if ids and ids[tileKey(cur.wx or me.wx, cur.wy or me.wy)] then r = min(MV.MAX_YARDS / 2, max(r or native, native) * MV.STEP) end
    end
  end
  MV.want.r, cur.r = r, r
end

-- the minimap's menu (a right-click on it, or on a pin: "Waypoint here" first), its switches named as on the
-- Settings page. Built a frame later and owned by UIParent: QuestTrail found a menu owned by a map could crash the client
local SWITCHES = {
  { "Far zoom", "mmExtended" }, { "Route", "minimapPins" }, { "Lines", "minimapLines" }, { "Pick-ups", "minimapPickups" },
  { "Objectives", "minimapObjectives" }, { "Dungeons", "minimapEntrances" }, { "Trails", "walkShow" }, { "Label", "minimapLabel" },
}
function MV.Menu(d)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  local function check(root, label, key, after)
    root:CreateCheckbox(label, function() return QB:Settings()[key] ~= false end, function()
      local s = QB:Settings()
      s[key] = s[key] == false
      if after then after(s[key]) end
      QB.Mini.Place()
      if QB.UI and QB.UI.frame and QB.UI.frame:IsShown() then QB.UI:Refresh() end
    end)
  end
  MenuUtil.CreateContextMenu(UIParent, function(_, root)
    if d and d.m then
      root:CreateButton("Waypoint here", function() QB.API.SetWaypoint(d.m, d.x, d.y, d.name) end)
      root:CreateDivider()
    end
    check(root, "Back to me after a drag", "mmCenter", function(on) if on then MV.Recentre() end end)
    root:CreateButton("Back to me", function() MV.Recentre() end)
    root:CreateDivider()
    for _, s in ipairs(SWITCHES) do check(root, s[1], s[2]) end
    root:CreateDivider()
    root:CreateButton("QuestBank settings", function() if QB.UI then QB.UI:Open(5) end end)
  end)
end
function MV.OpenMenu(d)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return false end
  C_Timer.After(0, QB.Safe(function() MV.Menu(d) end, "minimap menu"))
  return true
end

-- back to you: eased (the menu, the ease after a drag), or at once (now: a loading screen, the old centre is elsewhere)
function MV.Recentre(now)
  MV.want.wx, MV.want.wy = nil, nil
  if now == true then MV.cur.wx, MV.cur.wy = nil, nil end
end

function MV.MouseDown(button)
  if button ~= "LeftButton" or not MV.On() then return end
  local me, x, y = QB.API.WorldPosition(), cursor()
  mouse = (me and x) and { x = x, y = y, moved = false, v = MV.View(me) } or nil
end

-- a release: true when it was QuestBank's (a drag's end, a ping on the far view, the menu), so the game's own handler
-- is not called
function MV.MouseUp(button)
  if button == "RightButton" then
    mouse = nil
    return MV.OpenMenu()
  end
  local md = mouse
  mouse = nil
  if not (md and MV.On()) then return false end
  if md.moved then MV.releasedAt = GetTime(); return true end
  local me = QB.API.WorldPosition()
  if not (me and MV.Extended(me)) then return false end
  -- a click on the far view: a ping where it was clicked, in the game's own scale round you
  local wx, wy = toWorld(md.v, md.x, md.y)
  local s = md.v.R / QB.Mini.Radius()
  local f = MV.Rotated() and MV.Facing() or 0
  local e, n, cs, sn = me.wy - wy, wx - me.wx, cos(f), sin(f)
  pcall(Minimap.PingLocation, Minimap, (e * cs + n * sn) * s, (-e * sn + n * cs) * s)
  return true
end

local function dragTo()
  local md = mouse
  local x, y = cursor()
  if not x then return end
  if not md.moved and (x - md.x) ^ 2 + (y - md.y) ^ 2 < MV.DRAG * MV.DRAG then return end
  md.moved = true
  -- the point grabbed stays under the cursor: the centre moves the other way
  local gx, gy = toWorld(md.v, md.x, md.y)
  local hx, hy = toWorld(md.v, x, y)
  MV.want.wx, MV.want.wy = md.v.wx + gx - hx, md.v.wy + gy - hy
end

-- The game's + and - (Minimap.ZoomIn and ZoomOut, shown on mouseover; MinimapZoomIn/Out on the old minimap): invisible
-- and not clickable while the wheel zooms past them. Shown again only if they were shown before
local zoomHidden, zoomHooked, zoomWasShown = false, {}, {}
local function zoomButtons(show)
  zoomHidden = not show
  for _, b in ipairs({ MinimapZoomIn or false, MinimapZoomOut or false, Minimap.ZoomIn or false, Minimap.ZoomOut or false }) do
    if type(b) == "table" and b.SetAlpha then
      b:SetAlpha(show and 1 or 0)
      if b.EnableMouse then b:EnableMouse(show and true or false) end
      if not show then zoomWasShown[b] = b:IsShown(); b:Hide()
      elseif zoomWasShown[b] then zoomWasShown[b] = nil; b:Show() end
      if not zoomHooked[b] and b.HookScript then
        zoomHooked[b] = true
        b:HookScript("OnShow", function(self) if zoomHidden then self:Hide() end end)
      end
    end
  end
end

-- The minimap's release, set once round the game's own handler (QuestTrail set it again whenever another addon replaced
-- it, so its chain could grow): before (Mini.DragStop) first, then the view's, then the game's (the ping). With
-- QuestTrail loaded it is only hooked: QuestTrail sets it. And the game's tooltips over its blips (under the far
-- ground, where nothing shows them) are hidden while the ground is drawn
function MV.Hook(before)
  if MV.hooked or not Minimap then return end
  MV.hooked = true
  if MV.blocked then Minimap:HookScript("OnMouseUp", QB.Safe(before, "minimap move")); return end
  local orig = Minimap:GetScript("OnMouseUp")
  Minimap:SetScript("OnMouseUp", function(self, button, ...)
    QB.Try("minimap move", before)
    local mine
    QB.Try("minimap click", function() mine = MV.MouseUp(button) end)
    if mine then return end
    if orig then return orig(self, button, ...) end
  end)
  if GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnShow", QB.Safe(function(tt)
      if not MV.extendedNow then return end
      -- the blips' tooltip: owned by the minimap, or by UIParent at the cursor over it (the game's Minimap_OnUpdate)
      local owner = tt:GetOwner()
      if owner == Minimap or owner == MinimapCluster or (owner == UIParent and Minimap:IsMouseOver()) then tt:Hide() end
    end, "minimap tooltip"))
  end
end

-- whether the view is moving (dragged, or easing): then it is drawn every frame, so the ground and the pins go smoothly
function MV.Moving()
  if mouse and mouse.moved then return true end
  local want, cur = MV.want, MV.cur
  if cur.wx and not want.wx then return true end
  return (want.wx and cur.wx and (want.wx - cur.wx) ^ 2 + (want.wy - cur.wy) ^ 2 > 0.25) and true or false
end

-- each update (Minimap.lua's overlay): the drag, the ease, then the ground and your arrow. Returns the view
function MV.Tick(dt, me)
  if MV.blocked or not Minimap then return nil end
  local on = MV.On()
  if MV.zoomButtons ~= on then MV.zoomButtons = on; zoomButtons(not on) end
  local want, cur = MV.want, MV.cur
  if not on then
    MV.extendedNow, mouse = nil, nil
    want.r, want.wx, want.wy, cur.r, cur.wx, cur.wy = nil, nil, nil, nil, nil, nil
    if frame then frame:Hide() end
    hidePlayer()
    return nil
  end
  if mouse then
    if not (IsMouseButtonDown and IsMouseButtonDown("LeftButton")) then
      if mouse.moved then MV.releasedAt = GetTime() end
      mouse = nil
    else
      dragTo()
    end
  end
  -- dragged away, the view comes back to you RETURN seconds after it was let go (mmCenter); off, it stays there
  if QB:Settings().mmCenter ~= false and not mouse and want.wx and GetTime() - (MV.releasedAt or 0) > MV.RETURN then MV.Recentre() end
  local k = 1 - exp(-(dt or 0.05) / MV.SMOOTH)
  if want.wx then
    if not cur.wx and me then cur.wx, cur.wy = me.wx, me.wy end
    -- (while dragged the ground follows the cursor as it is; eased once let go)
    if cur.wx and mouse and mouse.moved then cur.wx, cur.wy = want.wx, want.wy
    elseif cur.wx then cur.wx, cur.wy = cur.wx + (want.wx - cur.wx) * k, cur.wy + (want.wy - cur.wy) * k end
  elseif cur.wx and me then
    cur.wx, cur.wy = cur.wx + (me.wx - cur.wx) * k, cur.wy + (me.wy - cur.wy) * k
    if (cur.wx - me.wx) ^ 2 + (cur.wy - me.wy) ^ 2 < 1 then cur.wx, cur.wy = nil, nil end
  end
  local f = groundFrame()
  if not me then MV.extendedNow = nil; f:Hide(); hidePlayer(); return nil end
  local v = MV.View(me)
  MV.extendedNow = v.ext or nil
  if not v.ext then f:Hide(); hidePlayer(); return v end
  setShape(v.square)
  -- (just over the minimap: its level can change after the ground was made, the game's or another addon's doing)
  local lvl = (Minimap:GetFrameLevel() or 1) + 1
  if f:GetFrameLevel() ~= lvl then f:SetFrameLevel(lvl) end
  if drawGround(v) then f:Show(); drawPlayer(v, me) else f:Hide(); hidePlayer() end
  return v
end
