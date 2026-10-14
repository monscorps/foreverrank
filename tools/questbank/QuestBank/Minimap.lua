-- SPDX-License-Identifier: GPL-3.0-or-later
-- The route on the minimap: a numbered pin for every stop of the hand-in route, a line from stop to stop and from you
-- to the next one, your pick-up list, and the entrances of the dungeons around you. While the arrow sends you by a
-- flight master, a pier or the tram first, that is pinned too, and the line and the label go there. A pin outside the
-- minimap's reach sits on its rim, dimmer, in the direction it lies. Click a pin: a waypoint there, as on the world
-- map; right-click it: the minimap's menu. Alt-drag moves the minimap, Ctrl-wheel sizes it, the wheel zooms it: the
-- game's own levels, then further out over the game's minimap tiles, and a drag pans that far view
-- (MinimapView.lua). Everything here is QuestBank's own frames laid over the Minimap; of the game's only its release
-- script is wrapped (MinimapView.lua), and the minimap itself is only scaled, moved and zoomed, never in a fight.
-- (QuestBank's Map is the game's world map: UI.OpenMap.)
--   where a pin is: the stop's map and position go through QB.Model.World to continent yards, as the arrow's do, and
--   then through the minimap's view (MV.View: its centre, its radius in yards from C_Minimap.GetViewRadius or the far
--   zoom, its turn with your facing under rotateMinimap).
local _, QB = ...
local Mini = {}
QB.Mini = Mini

local TICK = 0.05          -- seconds between placements (the pins follow you); every frame while the view moves
local ART = "Interface\\AddOns\\QuestBank\\art\\"
local PATH_EVERY = 2       -- seconds between golden-path searches
local MAX_PINS = 60        -- route stops, pick-ups and entrances, the nearest first past that
local EDGE = 7             -- the rim: pins past the minimap's reach sit this far inside its edge
local LINE_REACH = 1.6     -- a line is drawn when both ends are within this many radii
Mini.TICK, Mini.MAX_PINS = TICK, MAX_PINS
local RANK = { step = 0, stop = 1 } -- pins placed first, and kept past MAX_PINS: the arrow's step, the route's stops

local plain = QB.Plain
local sqrt, atan2, sin, cos, pi, floor = math.sqrt, math.atan2, math.sin, math.cos, math.pi, math.floor
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

-- a pin's key: its map and spot, or its world spot (the arrow's step has no map)
local function keyOf(d)
  if d.wx then return d.c .. ":" .. floor(d.wx) .. ":" .. floor(d.wy) end
  return d.m .. ":" .. d.x .. ":" .. d.y
end

-- continent yards of a pin's place, kept once per pin key (a pin that has them already is its own)
local function worldPos(d)
  if d.wx then return d end
  local key = keyOf(d)
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

-- what goes on the minimap: the arrow's step on the way (a flight master, a pier), the route's stops (numbered), the
-- pick-up list, the dungeon entrances of your continent
function Mini.List()
  local out = {}
  local step = QB.Arrow and QB.Arrow.MiniStep and QB.Arrow.MiniStep()
  if step then out[1] = step end
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
  if QB:Settings().minimapObjectives ~= false and QB.Data.SPOT and QB.QuestMap and QB.QuestMap.Spots then
    local n = 0
    for _, e in ipairs(QB.state.logOrder or {}) do
      if not e.complete then
        local q = QB.Quest.Get(e.id)
        for _, sp in ipairs(QB.QuestMap.Spots(QB.Data.SPOT[e.id]) or {}) do
          if n >= 120 then break end
          n = n + 1
          out[#out + 1] = { m = sp.m, x = sp.x * 100, y = sp.y * 100, name = q and q.name or ("Quest " .. e.id), kind = "obj", id = e.id, obj = sp.kind }
        end
      end
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
    if self.elapsed < TICK and not QB.MiniView.Moving() then return end
    local step = self.elapsed
    self.elapsed = 0
    Mini.Update(step)
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
  p.glow = p:CreateTexture(nil, "BACKGROUND")
  p.glow:SetTexture(ART .. "glow.tga")
  p.glow:SetPoint("CENTER")
  p.glow:SetSize(44, 44)
  p.glow:SetVertexColor(1, 0.82, 0.3, 0.55)
  p.glow:SetBlendMode("ADD")
  p.glow:Hide()
  p.icon = p:CreateTexture(nil, "ARTWORK")
  p.icon:SetAllPoints()
  p.num = p:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  p.num:SetPoint("CENTER", 0, 0)
  p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  p:SetScript("OnClick", QB.Safe(function(self, button)
    local d = self.d
    if not d then return end
    if button == "RightButton" then QB.MiniView.OpenMenu(d); return end
    if d.m then QB.API.SetWaypoint(d.m, d.x, d.y, d.name) end -- (the arrow's step: the arrow points there already)
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
    GameTooltip:AddLine(string.format(d.m and "%d yards. Click: waypoint." or "%d yards.", self.yards or 0), 0.5, 0.5, 0.5)
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
  local FLAT = "Interface\\Buttons\\WHITE8x8"
  l = f:CreateLine(nil, "ARTWORK", nil, 1)
  l:SetTexture(FLAT)
  l:SetThickness(4)
  l:SetVertexColor(1, 0.84, 0.18, 1)
  -- the dark edge under it, and a round joint so the turns read as one line
  l.under = f:CreateLine(nil, "ARTWORK", nil, 0)
  l.under:SetTexture(FLAT)
  l.under:SetThickness(8)
  l.under:SetVertexColor(0.05, 0.04, 0.02, 0.9)
  l.dot = f:CreateTexture(nil, "ARTWORK", nil, 2)
  l.dot:SetTexture(ART .. "dot.tga")
  l.dot:SetSize(7, 7)
  l.SetLine = function(self, x1, y1, x2, y2, r, g, b, a)
    self:SetVertexColor(r, g, b, a); self.under:SetVertexColor(0.05, 0.04, 0.02, 0.9 * a); self.dot:SetVertexColor(r, g, b, a)
    self:SetStartPoint("CENTER", f, x1, y1); self:SetEndPoint("CENTER", f, x2, y2)
    self.under:SetStartPoint("CENTER", f, x1, y1); self.under:SetEndPoint("CENTER", f, x2, y2)
    self.dot:ClearAllPoints(); self.dot:SetPoint("CENTER", f, "CENTER", x2, y2)
    self:Show(); self.under:Show(); self.dot:Show()
  end
  l.HideAll = function(self) self:Hide(); self.under:Hide(); self.dot:Hide() end
  lines[i] = l
  return l
end

-- the game's own crisp art where the client has it (the quest-number pin, the dungeon and quest marks), QuestBank's
-- textures otherwise
local atlasOr = QB.Art
local function style(p, d)
  T = T or QB.Data.TEX
  p.glow:Hide()
  p.icon:SetVertexColor(1, 1, 1, 1)
  if d.kind == "stop" then
    atlasOr(p.icon, d.num == 1 and "UI-QuestPoi-QuestNumber-SuperTracked" or "UI-QuestPoi-QuestNumber", T.mapPin)
    p.num:SetText(d.num and tostring(d.num) or "")
    p:SetSize(22, 22)
    if d.num == 1 then p.glow:SetSize(50, 50); p.glow:Show() end
  elseif d.kind == "obj" then
    -- the game's own cursor for the work: a sword to kill, a bag to loot, a cogwheel to use or click, coins to buy
    if QB.QuestMap and QB.QuestMap.PaintKind then QB.QuestMap.PaintKind(p.icon, d.obj) else p.icon:SetTexture(131021) end
    p.num:SetText("")
    p:SetSize(16, 16)
    return
  elseif d.kind == "dungeon" then
    atlasOr(p.icon, "Dungeon", d.icon or T.ring)
    p.num:SetText("")
    p:SetSize(18, 18)
  elseif d.kind == "step" then
    if not atlasOr(p.icon, d.atlas, d.icon) then p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    p.num:SetText("")
    p:SetSize(18, 18)
    p.glow:SetSize(40, 40)
    p.glow:Show()
  else
    atlasOr(p.icon, "QuestNormal", T.questAvail)
    p.num:SetText("")
    p:SetSize(16, 16)
  end
end

-- one update: the view (MinimapView.lua: a drag, the ease back, the far ground and your arrow), then the pins on it
function Mini.Update(dt)
  local me = QB.API.WorldPosition()
  Mini.Place(me, QB.MiniView.Tick(dt, me))
end

-- place every pin for where you stand now (me), on the view v (MV.View's for me when not given)
function Mini.Place(me, v)
  if not on() then Mini.Clear(); return end
  me = me or QB.API.WorldPosition()
  local f = overlayFrame()
  if not me then Mini.Clear(); return end
  v = v or QB.MiniView.View(me)
  local R, radius, facing = v.R, v.radius, v.facing
  local list, placed, n = Mini.List(), {}, 0
  -- nearest to you first when there are too many; placed round the view's centre (you, unless it was dragged)
  local pts = {}
  for _, d in ipairs(list) do
    local w = worldPos(d)
    if w and w.c == me.c then
      local x, y, _, far = Mini.Project(v, w, radius, R, facing)
      local dn, dw = w.wx - me.wx, w.wy - me.wy
      pts[#pts + 1] = { d = d, x = x, y = y, yards = sqrt(dn * dn + dw * dw), far = far }
    end
  end
  table.sort(pts, function(a, b)
    local ka, kb = RANK[a.d.kind] or 2, RANK[b.d.kind] or 2
    if ka ~= kb then return ka < kb end
    return a.yards < b.yards
  end)
  local nearestObj, step
  for _, pt in ipairs(pts) do
    if pt.d.kind == "obj" and (not nearestObj or pt.yards < nearestObj.yards) then nearestObj = pt end
    if pt.d.kind == "step" then step = pt end
  end
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
  -- lines: you to stop 1 (along the golden path when your trails know the way), then stop to stop, where both ends
  -- are near enough
  local li = 0
  -- where the line and the label go: the arrow's step on the way, else stop 1 or a nearer objective
  local target = placed[1]
  if nearestObj and (not target or nearestObj.yards < target.yards) then target = nearestObj end
  target = step or target
  Mini.target = target and target.d or nil
  Mini.Label(target, f)
  if QB:Settings().minimapLines ~= false then
    local yx, yy, _, yfar = Mini.Project(v, me, radius, R, facing)
    local prev = { x = yx, y = yy, far = yfar, yards = 0 }
    local num = 1
    local first = placed[1]
    if target and target ~= first then
      -- to the objective first: the golden path when your trails know it, else straight; the route's stops after
      local path = QB.Walk and QB.Walk.Path and Mini.GoldenPath(me, target.d)
      local pts2 = (path and #path >= 2) and path or { { me.wx, me.wy }, nil }
      if not (path and #path >= 2) then
        li = li + 1
        local l = line(li)
        if l then l:SetLine(yx, yy, target.x, target.y, 1, 0.84, 0.18, 1) end
      else
        for i = 1, #pts2 - 1 do
          local x1, y1, _, far1 = Mini.Project(v, { wx = pts2[i][1], wy = pts2[i][2] }, radius, R, facing)
          local x2, y2, _, far2 = Mini.Project(v, { wx = pts2[i + 1][1], wy = pts2[i + 1][2] }, radius, R, facing)
          if not (far1 and far2) then li = li + 1; local l = line(li); if l then l:SetLine(x1, y1, x2, y2, 1, 0.84, 0.18, 1) end end
        end
      end
      prev = target
    end
    if target == first and first and QB.Walk and QB.Walk.Path then
      local path = Mini.GoldenPath(me, first.d)
      if path and #path >= 2 then
        for i = 1, #path - 1 do
          local x1, y1, _, far1 = Mini.Project(v, { wx = path[i][1], wy = path[i][2] }, radius, R, facing)
          local x2, y2, _, far2 = Mini.Project(v, { wx = path[i + 1][1], wy = path[i + 1][2] }, radius, R, facing)
          if not (far1 and far2) then
            li = li + 1
            local l = line(li)
            if l then l:SetLine(x1, y1, x2, y2, 1, 0.84, 0.18, 1) end
          end
        end
        prev, num = first, 2 -- the straight line to stop 1 is replaced by the path
      end
    end
    while placed[num] do
      local pt = placed[num]
      if not prev.far and not pt.far and pt.yards <= radius * LINE_REACH and prev.yards <= radius * LINE_REACH then
        li = li + 1
        local l = line(li)
        if l then
          if num == 1 and target == first then l:SetLine(prev.x, prev.y, pt.x, pt.y, 1, 0.84, 0.18, 1) else l:SetLine(prev.x, prev.y, pt.x, pt.y, 0.4, 0.55, 1, 0.85) end
        end
      end
      prev, num = pt, num + 1
    end
  end
  for i = li + 1, #lines do lines[i]:HideAll() end
  Mini.shown, Mini.linesShown = n, li
  Mini.DrawTrails(v, radius, R, facing, f)
end

-- the target's name in a dark pill above it, the way the game labels a pin
local label
function Mini.Label(target, f)
  if not label then
    label = CreateFrame("Frame", "QuestBankMinimapLabel", f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    label:SetFrameLevel((f:GetFrameLevel() or 5) + 6)
    if label.SetBackdrop then
      label:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
                          insets = { left = 2, right = 2, top = 2, bottom = 2 } })
      label:SetBackdropColor(0.07, 0.06, 0.04, 0.92)
      label:SetBackdropBorderColor(0.85, 0.66, 0.25, 1)
    end
    label.text = label:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label.text:SetPoint("CENTER", 0, 0)
  end
  if not (target and not target.far and QB:Settings().minimapLabel ~= false) then label:Hide(); return end
  label.text:SetText(target.d.name or "")
  label:SetSize(math.min(200, (label.text:GetStringWidth() or 80) + 18), 22)
  label:ClearAllPoints()
  label:SetPoint("BOTTOM", f, "CENTER", target.x, target.y + 12)
  label:Show()
  Mini.labelText = target.d.name
end

-- your walked trails (Walk.lua) round the view's centre (me: {c, wx, wy}), as thin lines under the pins
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
          l:SetTexture(ART .. "line.tga")
          l:SetThickness(5)
          l:SetVertexColor(1, 0.85, 0.4, 0.22)
          l:SetBlendMode("ADD")
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

-- the golden path to the next stop: the way your trails know between where you stand and the stop, looked up at
-- most every PATH_EVERY seconds, kept while you and the stop stay put
local gold = {}
function Mini.GoldenPath(me, d)
  local w = worldPos(d)
  if not w or w.c ~= me.c then return nil end
  local key = keyOf(d)
  local t = GetTime and GetTime() or 0
  if gold.key == key and gold.at and t - gold.at < PATH_EVERY and gold.me and math.abs(gold.me.wx - me.wx) + math.abs(gold.me.wy - me.wy) < 30 then
    return gold.path
  end
  gold.key, gold.at, gold.me = key, t, { wx = me.wx, wy = me.wy }
  gold.path = QB.Walk.Path(me.c, me, w)
  return gold.path
end

function Mini.Clear()
  for _, p in ipairs(pins) do p:Hide() end
  for _, l in ipairs(lines) do l:HideAll() end
  for _, l in ipairs(trailLines) do l:Hide() end
  Mini.shown, Mini.linesShown, Mini.trailsShown = 0, 0, 0
end

function Mini.Invalidate() worldOf = {} end

----------------------------------------------------------------------------
-- The minimap you move and size. Alt-drag moves it (its header comes along), Ctrl and the wheel size it, the plain
-- wheel zooms it (MinimapView.lua). The size is the game's own: the minimap's container scale, which Edit Mode's Size
-- slider sets, so the border, the pins and other addons' buttons all grow with it and stay on the rim.
----------------------------------------------------------------------------
local SCALE_MIN, SCALE_MAX = 0.6, 4

local function container() return MinimapCluster and MinimapCluster.MinimapContainer or nil end
local function freeDB()
  local s = QB:Settings()
  if type(s.miniFree) ~= "table" then s.miniFree = {} end
  return s.miniFree
end
Mini.FreeDB = freeDB

-- a frame's centre in UIParent units
local function centreOf(fr)
  local x, y = fr:GetCenter()
  if not (x and y) then return nil end
  local k = (fr:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  return x * k, y * k
end

-- the minimap's centre to (x, y) in UIParent units, kept on the screen, by moving the whole cluster
function Mini.PlaceAt(x, y)
  local c = container()
  if not (c and x and y) then return end
  local W, H = UIParent:GetWidth() or 1920, UIParent:GetHeight() or 1080
  x, y = math.max(40, math.min(W - 40, x)), math.max(40, math.min(H - 40, y))
  local cx, cy = centreOf(c)
  local l, t = MinimapCluster:GetLeft(), MinimapCluster:GetTop()
  if not (cx and l and t) then return end
  local k = (MinimapCluster:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  MinimapCluster:ClearAllPoints()
  MinimapCluster:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l + (x - cx) / k, t + (y - cy) / k)
end

-- the largest size that still fits the screen's height
function Mini.MaxScale()
  local c = container()
  if not c then return SCALE_MAX end
  local k = (MinimapCluster:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  local h = (c:GetHeight() or 226) * k
  return math.max(SCALE_MIN, math.min(SCALE_MAX, (UIParent:GetHeight() or 1080) * 0.92 / h))
end

-- size the minimap around its centre; kept for next time
function Mini.SetScale(scale)
  local c = container()
  if not c then return nil end
  if InCombatLockdown and InCombatLockdown() then return nil end
  scale = math.max(SCALE_MIN, math.min(Mini.MaxScale(), scale))
  local db = freeDB()
  if not db.orig then db.orig = c:GetScale() or 1 end
  local x, y = centreOf(c)
  c:SetScale(scale)
  if x then Mini.PlaceAt(x, y) end
  db.scale = scale; db.x, db.y = centreOf(c)
  Mini.Place()
  return scale
end

-- k times its size now: Ctrl-wheel, and the Minimap bigger and smaller keys
function Mini.Size(k)
  local c = container()
  if c then return Mini.SetScale((c:GetScale() or 1) * k) end
end

-- the wheel over the minimap: with Ctrl it sizes the minimap; else it zooms it, past the game's widest too while the
-- far zoom is on (MinimapView.lua), or as the game's own zoom does
function Mini.Wheel(delta)
  if IsControlKeyDown and IsControlKeyDown() then Mini.Size(delta > 0 and 1.1 or 1 / 1.1); return end
  if QB.MiniView.On() then QB.MiniView.Wheel(delta); Mini.Update(0); return end
  local z = Minimap.GetZoom and plain(Minimap:GetZoom()) or 0
  if type(z) ~= "number" then z = 0 end
  if delta > 0 then
    if Minimap_ZoomIn then Minimap_ZoomIn() elseif Minimap.SetZoom then Minimap:SetZoom(math.min((Minimap:GetZoomLevels() or 6) - 1, z + 1)) end
  elseif delta < 0 then
    if Minimap_ZoomOut then Minimap_ZoomOut() elseif Minimap.SetZoom then Minimap:SetZoom(math.max(0, z - 1)) end
  end
end

-- Alt-drag: the whole minimap moves; where it ends up is kept
function Mini.DragStart(button)
  if button ~= "LeftButton" or not (IsAltKeyDown and IsAltKeyDown()) or (InCombatLockdown and InCombatLockdown()) then return end
  if not MinimapCluster then return end
  MinimapCluster:SetMovable(true)
  MinimapCluster:StartMoving()
  Mini.dragging = true
end
function Mini.DragStop()
  if not Mini.dragging then return end
  Mini.dragging = nil
  MinimapCluster:StopMovingOrSizing()
  if MinimapCluster.SetUserPlaced then pcall(MinimapCluster.SetUserPlaced, MinimapCluster, false) end
  local c = container()
  local x, y = c and centreOf(c)
  if x then
    Mini.PlaceAt(x, y)
    local db = freeDB(); db.x, db.y = centreOf(c)
  end
end

-- the kept size and place, again after a loading screen (Edit Mode puts its own back first)
function Mini.ApplyFree()
  local c, db = container(), freeDB()
  if not c or (InCombatLockdown and InCombatLockdown()) then return end
  if db.scale then c:SetScale(math.max(SCALE_MIN, math.min(Mini.MaxScale(), db.scale))) end
  if db.x and db.y then Mini.PlaceAt(db.x, db.y) end
end

-- other addons' minimap buttons, back on the rim: LibDBIcon's from their own saved angle, any other button left far
-- off the map (5.2's big map resized the minimap under them) onto the rim in the direction it was
function Mini.RescueButtons()
  local refreshed, moved = 0, 0
  local lib = LibStub and LibStub("LibDBIcon-1.0", true)
  if lib and lib.GetButtonList and lib.Refresh then
    for _, name in ipairs(lib:GetButtonList() or {}) do if pcall(lib.Refresh, lib, name) then refreshed = refreshed + 1 end end
  end
  local R = (Minimap:GetWidth() or 140) / 2
  for _, ch in ipairs({ Minimap:GetChildren() }) do
    if ch ~= overlay and ch.GetNumPoints and ch:GetNumPoints() == 1 then
      local p, rel, _, x, y = ch:GetPoint(1)
      if rel == Minimap and p == "CENTER" and type(x) == "number" and type(y) == "number" then
        local d = sqrt(x * x + y * y)
        if d > R * 1.6 then
          ch:ClearAllPoints()
          ch:SetPoint("CENTER", Minimap, "CENTER", x / d * (R + 10), y / d * (R + 10))
          moved = moved + 1
        end
      end
    end
  end
  return refreshed, moved
end

-- /qb minimap reset: the game's size and place again, every button back on the rim
function Mini.ResetFree()
  local c, db = container(), freeDB()
  if c then c:SetScale(db.orig or 1) end
  if MinimapCluster and MinimapCluster.ApplySystemAnchor then pcall(MinimapCluster.ApplySystemAnchor, MinimapCluster) end
  QB:Settings().miniFree = {}
  local a, b = Mini.RescueButtons()
  return a + b
end

function Mini:Init()
  if self.ready then return end
  self.ready = true
  if not (Minimap and QB.Model and QB.Model.World) then return end
  local f = CreateFrame("Frame")
  f:SetScript("OnEvent", QB.Safe(function(_, event)
    if event == "PLAYER_ENTERING_WORLD" or event == "EDIT_MODE_LAYOUTS_UPDATED" then
      -- after Edit Mode has put its own size and place back
      local again = function()
        Mini.ApplyFree()
        if not Mini.rescued then Mini.rescued = true; Mini.RescueButtons() end
      end
      if C_Timer and C_Timer.After then C_Timer.After(0.5, QB.Safe(again, "minimap size")) else again() end
      QB.MiniView.Recentre(true)
    end
    Mini.Invalidate()
    Mini.Place()
  end, "minimap pins"))
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "MINIMAP_UPDATE_ZOOM", "EDIT_MODE_LAYOUTS_UPDATED" }) do
    pcall(f.RegisterEvent, f, e)
  end
  -- the mouse: Ctrl-wheel sizes, the wheel zooms; Alt-drag moves the minimap, a plain drag pans its view, a click
  -- pings and a right-click opens its menu (MinimapView.lua; with QuestTrail loaded, its own)
  local MV = QB.MiniView
  MV.Guard()
  Minimap:EnableMouseWheel(true)
  Minimap:SetScript("OnMouseWheel", QB.Safe(function(_, delta) Mini.Wheel(delta) end, "minimap wheel"))
  Minimap:HookScript("OnMouseDown", QB.Safe(function(_, button)
    if IsAltKeyDown and IsAltKeyDown() then Mini.DragStart(button) else MV.MouseDown(button) end
  end, "minimap mouse"))
  MV.Hook(Mini.DragStop)
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
