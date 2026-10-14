-- SPDX-License-Identifier: GPL-3.0-or-later AND MIT
-- Contains code from QuestTrail 3.0.6, Copyright (c) 2026 Krom, MIT licence (LICENSE-QuestTrail.txt): QuestTrail_Minimap.lua: MV, Tiles, Extended, Square, Reach, View, Frame, SetShape, Tile, DrawGround, DrawPlayer, NativePlayer, PartyDot, NewPart, Layout, HideBlob, DrawBlob, Debug, DrawParty, Cursor, ScreenToMap, Wheel, Menu, Recentre, OnMouseDown, OnMouseUp, OnUpdateDrag, ZoomButtons, Hook (its re-wrap), Moving, Tick
-- The minimap's view, after QuestTrail's extended minimap. Centred on you at the game's own zoom levels it is the
-- game's minimap as it is. Wheeled out past the game's widest (1.5 times a step, up to 12,000 yards across) or dragged
-- away from you, the ground is drawn from the game's own minimap tiles (MinimapTiles.lua) over the minimap, cut by the
-- minimap's own mask, with your arrow, your party and the quest's blue areas on it; 3 seconds after a drag it eases
-- back to you. A click that does not drag pings, as the game's does; a right-click opens the minimap's menu. Indoors,
-- or where no tile is known, the game's minimap shows (/qb minimap debug says why). Everything QuestBank draws on the
-- minimap goes through one view (MV.View): its centre and radius in continent yards (QB.Model.World's), its scale in
-- pixels a yard and its turn.
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

-- a world spot on the minimap: pixels from its centre, x right and y up
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
-- Your arrow, the game's MinimapArrow, on a frame of its own above everything QuestBank draws on the minimap (the
-- strokes, the circles, the markers), at the game's zoom and over the far ground alike, as QuestTrail draws it:
-- the route sits under you. Its size the mmArrowSize setting, in pixels (12 to 64; the party dots follow it). The
-- game's own arrow is left alone, under ours (QuestTrail sized it away, a call Forever's minimap does not have)
-------------------------------------------------------------------------
local arrowFrame, arrow
function MV.ArrowSize() return max(12, min(64, tonumber(QB:Settings().mmArrowSize) or MV.ARROW)) end
local function drawPlayer(v, me)
  if not arrowFrame then
    arrowFrame = CreateFrame("Frame", nil, Minimap)
    arrowFrame:SetAllPoints(Minimap)
    arrow = arrowFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    MV.arrow = arrow
  end
  local sz = MV.ArrowSize()
  if arrow.sz ~= sz then arrow:SetSize(sz, sz); arrow.sz = sz end
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

-- a value from the client: nil when the call fails or the value is secret
local function ask(fn, ...)
  if not fn then return nil end
  local ok, v = pcall(fn, ...)
  return ok and plain(v) or nil
end

-------------------------------------------------------------------------
-- Your party (or raid) on the far ground, where the game's own dots are under it: a dot in each member's class
-- colour (the game's blip, Interface\Minimap\PartyRaidBlips: its white one, tinted), the name on mouseover, placed
-- as yours is (QB.API.WorldPosition). The mmParty switch
-------------------------------------------------------------------------
local party = {}
MV.PARTY_SIZE = 14 / 32 -- of your arrow: the arrow's image has room round it, the dot's none
local PARTY_UNITS, RAID_UNITS = {}, {}
for i = 1, 4 do PARTY_UNITS[i] = "party" .. i end
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end
local function partyDot(k)
  local d = party[k]
  if d then return d end
  d = CreateFrame("Frame", nil, frame)
  d:SetSize(MV.ArrowSize() * MV.PARTY_SIZE, MV.ArrowSize() * MV.PARTY_SIZE)
  d.tex = d:CreateTexture(nil, "OVERLAY")
  d.tex:SetAllPoints()
  d.tex:SetTexture("Interface\\Minimap\\PartyRaidBlips")
  d.tex:SetTexCoord(0.5, 0.625, 0, 0.25)
  d:EnableMouse(true)
  d:SetScript("OnEnter", function(self)
    if not self.unit then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetUnit(self.unit)
    GameTooltip:Show()
  end)
  d:SetScript("OnLeave", function() GameTooltip:Hide() end)
  party[k] = d
  return d
end
local function drawParty(v)
  local used = 0
  if QB:Settings().mmParty ~= false then
    local raid = ask(IsInRaid) == true
    local count = ask(raid and GetNumGroupMembers or GetNumSubgroupMembers)
    local lvl = (Minimap:GetFrameLevel() or 1) + 4
    for i = 1, type(count) == "number" and count or 0 do
      local unit = (raid and RAID_UNITS or PARTY_UNITS)[i]
      local w = unit and ask(UnitExists, unit) and not ask(UnitIsUnit, unit, "player") and QB.API.WorldPosition(unit)
      if w and w.c == v.c then
        local sx, sy = MV.Point(v, w.wx, w.wy)
        if MV.Reach(sx, sy) <= v.R then
          used = used + 1
          local d = partyDot(used)
          if d.lvl ~= lvl then d:SetFrameLevel(lvl); d.lvl = lvl end
          local ds = MV.ArrowSize() * MV.PARTY_SIZE
          if d.sz ~= ds then d:SetSize(ds, ds); d.sz = ds end
          local okC, _, file = pcall(UnitClass, unit)
          local class = okC and plain(file) or nil
          if d.class ~= class then
            local col = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            d.tex:SetVertexColor(col and col.r or 1, col and col.g or 1, col and col.b or 1)
            d.class = class
          end
          d.unit = unit
          if d.sx ~= sx or d.sy ~= sy then
            d:ClearAllPoints()
            d:SetPoint("CENTER", frame, "CENTER", sx, sy)
            d.sx, d.sy = sx, sy
          end
          if not d:IsShown() then d:Show() end
        end
      end
    end
  end
  for k = used + 1, #party do if party[k]:IsShown() then party[k]:Hide() end end
  MV.partyShown = used
end

-------------------------------------------------------------------------
-- The quest's blue areas on the far ground (the game draws them on its own minimap, under the tiles): frames of the
-- game's own kind for them (QuestPOIFrame, as its world map's), laid over your zone's map where the view puts it,
-- drawn by the game. The quest picked on QuestBank's Map (QB.MapPage.focus), else the first quest of your log at
-- route stop 1; the mmAreas switch. Not on a minimap that turns (a frame cannot turn), nor where the client has no
-- such frame. They cannot be masked: on a round minimap the circle is cut in BLOB_BANDS bands, each clipped as wide
-- as the circle at its outer edge and the areas drawn again in each (a staircase under the rim). The timing is
-- QuestTrail's, found in game: the game draws the areas at the frame's layout of a frame before
-------------------------------------------------------------------------
local blob -- nil: not made yet; false: no such frame on this client; else its state and frames
local BLOB_W, BLOB_SETTLE, BLOB_SHOW, BLOB_BANDS, BLOB_EARLY = 512, 0.15, 0.1, 16, 5
local function newPart(parent)
  local ok, b = pcall(CreateFrame, "QuestPOIFrame", nil, parent)
  if not (ok and b and b.DrawBlob) then return nil end
  pcall(b.SetFillTexture, b, "Interface\\WorldMap\\UI-QuestBlob-Inside")
  pcall(b.SetBorderTexture, b, "Interface\\WorldMap\\UI-QuestBlob-Outside")
  pcall(b.SetFillAlpha, b, 128)
  pcall(b.SetBorderAlpha, b, 192)
  pcall(b.SetBorderScalar, b, 1.0)
  b:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 3)
  -- (the wheel and the clicks go through it, to the minimap under it)
  pcall(b.EnableMouse, b, false)
  pcall(b.EnableMouseWheel, b, false)
  b:Hide()
  return b
end
-- The frames the areas are drawn in, for the minimap's shape and size: square, one, clipped by the ground's frame;
-- round, a band each, 2 pixels wider than the circle (under the rim)
local function layout()
  local fw, fh = Minimap:GetWidth() or 140, Minimap:GetHeight() or 140 -- (the ground's frame is the minimap's size)
  if blob.kSquare == MV.square and blob.kW == fw and blob.kH == fh then return end
  blob.kSquare, blob.kW, blob.kH = MV.square, fw, fh
  blob.key, blob.drawn = (blob.key or 0) + 1, nil
  if blob.use then for _, p in ipairs(blob.use) do p:Hide() end end
  for _, band in ipairs(blob.bands) do band.clip:Hide() end
  if MV.square then
    blob.use = { blob.single }
    return
  end
  blob.use = {}
  local r, bandH = fw / 2 + 2, fh / BLOB_BANDS
  for i = 1, BLOB_BANDS do
    local band = blob.bands[i]
    if not band then
      local clip = CreateFrame("Frame", nil, frame)
      clip:SetClipsChildren(true)
      clip:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 3)
      band = { clip = clip, part = newPart(clip) }
      blob.bands[i] = band
    end
    local y0, y1 = -fh / 2 + (i - 1) * bandH, -fh / 2 + i * bandH
    local far = max(abs(y0), abs(y1))
    local half = sqrt(max(r * r - far * far, 0))
    if half > 0 and band.part then
      band.clip:ClearAllPoints()
      band.clip:SetPoint("CENTER", frame, "CENTER", 0, (y0 + y1) / 2)
      band.clip:SetSize(half * 2, bandH)
      band.clip:Show()
      blob.use[#blob.use + 1] = band.part
    end
  end
end
local function hideBlob()
  if blob and blob.use then for _, p in ipairs(blob.use) do if p:IsShown() then p:Hide() end end end
end

-- the quest whose areas show: the one picked on QuestBank's Map, else the first quest of your log at route stop 1
function MV.AreaQuest()
  local picked = QB.MapPage and QB.MapPage.focus
  if picked then return picked end
  for _, d in ipairs(QB.Pins and QB.Pins.list or {}) do
    if d.num == 1 then
      for _, e in ipairs(QB.state.logOrder or {}) do if d.ids and d.ids[e.id] then return e.id end end
      return nil
    end
  end
end

-- your zone's map in continent yards: its centre and its width west to east, height north to south
local function zoneOf(m)
  local a, b = QB.Model.World(m, 0, 0), QB.Model.World(m, 100, 100)
  if not (a and b and a.c == b.c and a.wx ~= b.wx and a.wy ~= b.wy) then return nil end
  return { c = a.c, wx = (a.wx + b.wx) / 2, wy = (a.wy + b.wy) / 2, W = abs(a.wy - b.wy), H = abs(a.wx - b.wx) }
end

-- each frame where the view puts the zone (ox, oy: its centre in the frames' own scale), drawn if asked, seen or not
-- (a hidden frame is not drawn: one drawn unseen is shown, transparent)
local function placeParts(parts, ox, oy, q, draw, showing)
  for _, p in ipairs(parts) do
    if draw then
      pcall(p.DrawNone, p)
      pcall(p.DrawBlob, p, q, true)
    end
    p:ClearAllPoints()
    p:SetPoint("CENTER", frame, "CENTER", ox, oy)
    p:SetAlpha(showing and 1 or 0)
    p:Show()
  end
end

local function drawBlob(v)
  local q = QB:Settings().mmAreas ~= false and v.facing == 0 and MV.AreaQuest() or nil
  if not q then
    hideBlob()
    -- (picked again later: its first seconds again, the game giving the areas a moment after)
    if blob then blob.selected, blob.drawn, blob.zoom = nil, nil, nil end
    MV.blobBusy = nil
    return
  end
  if blob == nil then
    -- (one made first: where the client has no such frame, none)
    local test = newPart(frame)
    blob = test and { single = test, bands = {} } or false
    MV.blobSupported = blob and true or false
    if blob then
      -- (the quests' areas changed: drawn again)
      local ev = CreateFrame("Frame")
      pcall(ev.RegisterEvent, ev, "QUEST_POI_UPDATE")
      pcall(ev.RegisterEvent, ev, "QUEST_LOG_UPDATE")
      ev:SetScript("OnEvent", function() blob.dirty = true end)
    end
  end
  if not blob then return end
  local m = plain(QB.API.MapID())
  local z = m and zoneOf(m)
  if not (z and z.c == v.c) then hideBlob(); return end
  layout()
  local parts = blob.use
  MV.blobFrames = #parts
  -- The frames keep one modest size per zone (BLOB_W wide), laid out a frame before they are drawn; the zoom is their
  -- scale. (The game draws the areas at the frame's size of its last layout: drawn at a size just set, or at the
  -- zone's whole size on the ground, thousands of pixels, they came out shifted)
  local bh = BLOB_W * z.H / z.W
  if blob.map ~= m or blob.bh ~= bh or blob.sized ~= blob.key then
    blob.s = 1
    for _, part in ipairs(parts) do
      part:SetScale(1)
      part:SetSize(BLOB_W, bh)
      pcall(part.SetMapID, part, m)
    end
    blob.map, blob.bh, blob.sized, blob.drawn, blob.moved, blob.scaled = m, bh, blob.key, nil, GetTime(), true
  end
  local now, s = GetTime(), z.W * v.scale / BLOB_W
  -- a zoom step: the frames scaled at once, the areas drawn unseen in that frame, drawn again and shown the next
  -- (drawn right after a scale they came out shifted, and so did a drawing kept and scaled); the minimap updated
  -- every frame meanwhile (MV.Moving)
  if abs(s / blob.s - 1) > 0.0005 or not blob.scaled then
    blob.s, blob.moved, blob.scaled = s, now, true
    for _, p in ipairs(parts) do p:SetScale(s) end
    if blob.drawn == q then blob.zoom, MV.blobBusy = 1, true end
  end
  local cx, cy = MV.Point(v, z.wx, z.wy)
  local ox, oy = cx / blob.s, cy / blob.s
  if blob.zoom and blob.drawn ~= q then blob.zoom, MV.blobBusy = nil, nil end
  if blob.zoom == 1 then blob.zoom = 2; placeParts(parts, ox, oy, q, true, false); return end
  if blob.zoom == 2 then blob.zoom, MV.blobBusy, blob.at = nil, nil, now; placeParts(parts, ox, oy, q, true, true); return end
  local settling = now - (blob.moved or 0) < BLOB_SETTLE
  -- (a quest's areas not drawn yet, or another map's: they wait for the layout, unseen)
  if settling and not blob.drawn then hideBlob(); return end
  if blob.selected ~= q then blob.selected, blob.selAt = q, now end
  if blob.drawn ~= q then blob.drawn, blob.from, blob.at, blob.final = q, now, 0, nil end
  local showing = now - blob.from > BLOB_SHOW
  -- drawn twice once still (at once, and as it is shown, the layout settled); then each second for BLOB_EARLY seconds
  -- after the quest is picked; after that only when the game says the quests' areas changed
  local draw = not settling and (blob.at == 0 or (showing and not blob.final)
    or (now - blob.at > 1 and (now - blob.selAt < BLOB_EARLY or blob.dirty)))
  if showing then blob.final = true end
  if draw then blob.at, blob.dirty = now, nil end
  placeParts(parts, ox, oy, q, draw, showing)
end

-- /qb minimap debug: the far view's state, for a report
function MV.Debug()
  local me = QB.API.WorldPosition()
  local ext, why = MV.Extended(me)
  local shown = 0
  for _, t in ipairs(tiles) do if t:IsShown() then shown = shown + 1 end end
  QB:Print(string.format("Minimap: far view %s (%s), continent %s, radius %s yards (the game's %s, its widest %s), tiles %d shown of %d, %d layouts.",
    ext and "on" or "off", why or "drawn", tostring(me and me.c), tostring(MV.cur.r), tostring(QB.Mini.Radius()), tostring(MV.nativeMax),
    shown, #tiles, MV.layouts or 0))
  QB:Print(string.format("Ground: shown %s, level %s (minimap %s), mask %s, %s; your arrow %s; party dots %d.",
    tostring(frame and frame:IsShown()), tostring(frame and frame:GetFrameLevel()), tostring(Minimap:GetFrameLevel()),
    tostring(MV.maskKind), MV.square and "square" or "round", tostring(arrow and arrow:IsShown()), MV.partyShown or 0))
  QB:Print(string.format("Quest areas: %s, quest %s, %s frames, drawn for %s.",
    blob == false and "not on this client" or (blob and "made" or "not made yet"), tostring(MV.AreaQuest()), tostring(MV.blobFrames),
    tostring(blob and blob.drawn)))
end

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
  { "Far zoom", "mmExtended" }, { "Route", "minimapPins" }, { "Lines", "minimapLines" }, { "Golden path", "goldenPath" }, { "Pick-ups", "minimapPickups" },
  { "Objectives", "minimapObjectives" }, { "Dungeons", "minimapEntrances" }, { "Trails", "walkShow" }, { "Party", "mmParty" },
  { "Quest areas", "mmAreas" }, { "Label", "minimapLabel" },
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

-- The minimap's release, set round the game's own handler: before (Mini.DragStop) first, then the view's, then the
-- game's (the ping). Set again when another addon replaces it later (QuestTrail's re-wrap, each update: MV.Rehook),
-- else a drag's end, the ping on the far view and the menu would be lost; a release that comes round twice in one
-- frame (the other addon wrapped ours) runs ours once. With QuestTrail loaded it is only hooked: QuestTrail sets it.
-- And the game's tooltips over its blips (under the far ground, where nothing shows them) are hidden while the ground
-- is drawn
function MV.Hook(before)
  if MV.hooked or not Minimap then return end
  MV.hooked, MV.before = true, before
  if MV.blocked then Minimap:HookScript("OnMouseUp", QB.Safe(before, "minimap move")); return end
  local orig = Minimap:GetScript("OnMouseUp")
  MV.ourUp = function(self, button, ...)
    local now = GetTime()
    if MV.upAt == now and MV.upButton == button then
      if orig then return orig(self, button, ...) end
      return
    end
    MV.upAt, MV.upButton = now, button
    QB.Try("minimap move", before)
    local mine
    QB.Try("minimap click", function() mine = MV.MouseUp(button) end)
    if mine then return end
    if orig then return orig(self, button, ...) end
  end
  Minimap:SetScript("OnMouseUp", MV.ourUp)
  MV.rehooks = MV.rehooks or 0
  if MV.tipHooked then return end
  MV.tipHooked = true
  if GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnShow", QB.Safe(function(tt)
      if not MV.extendedNow then return end
      -- the blips' tooltip: owned by the minimap, or by UIParent at the cursor over it (the game's Minimap_OnUpdate)
      local owner = tt:GetOwner()
      if owner == Minimap or owner == MinimapCluster or (owner == UIParent and Minimap:IsMouseOver()) then tt:Hide() end
    end, "minimap tooltip"))
  end
end

-- another addon set the minimap's release since: ours round it again
function MV.Rehook()
  if not (MV.hooked and MV.ourUp and not MV.blocked and Minimap) then return false end
  if Minimap:GetScript("OnMouseUp") == MV.ourUp then return false end
  MV.hooked = nil
  MV.rehooks = (MV.rehooks or 0) + 1
  MV.Hook(MV.before)
  return true
end

-- whether the view is moving (dragged, or easing): then it is drawn every frame, so the ground and the pins go smoothly
function MV.Moving()
  if mouse and mouse.moved then return true end
  if MV.blobBusy then return true end -- (the quest's areas, the frame after a zoom step)
  local want, cur = MV.want, MV.cur
  if cur.wx and not want.wx then return true end
  return (want.wx and cur.wx and (want.wx - cur.wx) ^ 2 + (want.wy - cur.wy) ^ 2 > 0.25) and true or false
end

-- each update (Minimap.lua's overlay): the drag, the ease, then the ground and your arrow. Returns the view
function MV.Tick(dt, me)
  if MV.blocked or not Minimap then return nil end
  MV.Rehook()
  local on = MV.On()
  if MV.zoomButtons ~= on then MV.zoomButtons = on; zoomButtons(not on) end
  local want, cur = MV.want, MV.cur
  if not on then
    MV.extendedNow, mouse, MV.blobBusy = nil, nil, nil
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
  if not me then MV.extendedNow, MV.blobBusy = nil, nil; f:Hide(); hidePlayer(); return nil end
  local v = MV.View(me)
  MV.extendedNow = v.ext or nil
  -- (at the game's zoom: its own minimap, with your arrow over QuestBank's pins)
  if not v.ext then MV.blobBusy = nil; f:Hide(); drawPlayer(v, me); return v end
  setShape(v.square)
  -- (just over the minimap: its level can change after the ground was made, the game's or another addon's doing)
  local lvl = (Minimap:GetFrameLevel() or 1) + 1
  if f:GetFrameLevel() ~= lvl then f:SetFrameLevel(lvl) end
  if drawGround(v) then
    f:Show()
    drawPlayer(v, me)
    QB.Try("minimap quest areas", drawBlob, v)
    drawParty(v)
  else
    MV.blobBusy = nil
    f:Hide()
    hidePlayer()
  end
  return v
end
