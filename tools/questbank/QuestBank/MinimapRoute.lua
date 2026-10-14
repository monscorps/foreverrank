-- SPDX-License-Identifier: GPL-3.0-or-later AND MIT
-- Contains code from QuestTrail 3.0.6, Copyright (c) 2026 Krom, MIT licence (LICENSE-QuestTrail.txt): QuestTrail_ZoneMap.lua: Smooth, ZM_Show, ZM_Color, ZoneMapLine, ZoneMapArrow, RouteDraw, DrawMinimapRoute; QuestTrail_GoldenPath.lua: WidthOf, ColorOf, Simplify, Cut, Update, Advance, MMFrame, HideFrom, Edge, Clip, DrawMinimap, Tick
-- The route's strokes on the minimap, after QuestTrail's: one stroke a step (you to the next place, then stop to
-- stop), each a line of art/line_arrow.png (a light core between dark edges, tinted), cut where it leaves the
-- minimap's circle (or square) and stopping at the edge of the pin it leads to. And the golden path: the way your
-- walked trails know from you to that next place (QB.Walk.Path), kept while you walk along it and trimmed behind you,
-- gold along your trails, paler and thinner where it crosses ground you never walked. All in pixels from the
-- minimap's centre, where the view (MinimapView.lua) puts them; Minimap.lua says what to draw.
local _, QB = ...
local MR = { THICK = 8 }
QB.MiniRoute = MR

local TEX = "Interface\\AddOns\\QuestBank\\art\\line_arrow.png"
local sqrt, min, max, abs = math.sqrt, math.min, math.max, math.abs

-- no snapping to the pixel grid: a slanted or scaled stroke jitters and stair-steps when snapped
function MR.Smooth(tex)
  if tex.SetSnapToPixelGrid then pcall(tex.SetSnapToPixelGrid, tex, false) end
  if tex.SetTexelSnappingBias then pcall(tex.SetTexelSnappingBias, tex, 0) end
end
-- retained drawing, 20 times a second: each stroke keeps what it was last given and the game is called only for what
-- changed (most strokes stay put while you stand still)
function MR.Show(o, on)
  if o.on == on then return end
  o.on = on
  if on then o:Show() else o:Hide() end
end
function MR.Color(o, r, g, b, a)
  if o.cr == r and o.cg == g and o.cb == b and o.ca == a then return end
  o.cr, o.cg, o.cb, o.ca = r, g, b, a
  o:SetVertexColor(r, g, b, a)
end

-- one edge of the square: the part of the segment's range on its inner side (Liang-Barsky; no table, it runs for
-- every stroke at every update)
local function edge(p, q, t0, t1)
  if p == 0 then
    if q < 0 then return end
    return t0, t1
  end
  local t = q / p
  if p < 0 then
    if t > t1 then return end
    if t > t0 then t0 = t end
  else
    if t < t0 then return end
    if t < t1 then t1 = t end
  end
  return t0, t1
end
-- the part of a segment within r of the minimap's centre: its circle, or its square on a square minimap. Nil when
-- none is: lines cannot be masked, so they are cut here
function MR.Clip(x1, y1, x2, y2, r, square)
  local dx, dy = x2 - x1, y2 - y1
  if square then
    local t0, t1 = edge(-dx, x1 + r, 0, 1)
    if t0 then t0, t1 = edge(dx, r - x1, t0, t1) end
    if t0 then t0, t1 = edge(-dy, y1 + r, t0, t1) end
    if t0 then t0, t1 = edge(dy, r - y1, t0, t1) end
    if not t0 then return end
    return x1 + dx * t0, y1 + dy * t0, x1 + dx * t1, y1 + dy * t1
  end
  local a = dx * dx + dy * dy
  local b = 2 * (dx * x1 + dy * y1)
  local c = x1 * x1 + y1 * y1 - r * r
  if a == 0 then
    if c <= 0 then return x1, y1, x2, y2 end
    return
  end
  local disc = b * b - 4 * a * c
  if disc <= 0 then return end
  local s = sqrt(disc)
  local t0, t1 = max(0, (-b - s) / (2 * a)), min(1, (-b + s) / (2 * a))
  if t0 >= t1 then return end
  return x1 + dx * t0, y1 + dy * t0, x1 + dx * t1, y1 + dy * t1
end

-- The strokes' frames over the minimap: the route's (and the trails', Minimap.lua) at +2, the golden path's at +3,
-- over the far ground (+1) and under QuestBank's pins (+5). Each a pool of lines; r and square: where they are cut
MR.route, MR.gold = { lines = {}, used = 0 }, { lines = {}, used = 0 }
function MR.Frames()
  local base = Minimap:GetFrameLevel() or 1
  for i, ctx in ipairs({ MR.route, MR.gold }) do
    if not ctx.frame then
      ctx.frame = CreateFrame("Frame", nil, Minimap)
      ctx.frame:SetAllPoints(Minimap)
    end
    -- (the minimap's level can change after the frames were made: the game's or another addon's doing)
    if ctx.level ~= base then ctx.frame:SetFrameLevel(base + 1 + i); ctx.level = base end
  end
  return MR.route.frame, MR.gold.frame
end

-- a stroke from (x1, y1) to (x2, y2), cut to the context's reach: one line of its pool, line_arrow.png stretched along
-- it (CLAMP and plain LINEAR: mipmaps blurred the dark edges into the colour), col tinting its core. False when
-- nothing of it is on the minimap
function MR.Line(ctx, x1, y1, x2, y2, col, thick, alpha)
  local a1, b1, a2, b2 = MR.Clip(x1, y1, x2, y2, ctx.r, ctx.square)
  if not a1 or (a2 - a1) ^ 2 + (b2 - b1) ^ 2 <= 0.25 then return false end
  ctx.used = ctx.used + 1
  local line = ctx.lines[ctx.used]
  if not line then
    line = ctx.frame:CreateLine(nil, "OVERLAY", nil, 1)
    line:SetTexture(TEX, "CLAMP", "CLAMP", "LINEAR")
    MR.Smooth(line)
    ctx.lines[ctx.used] = line
  end
  MR.Color(line, col[1], col[2], col[3], alpha)
  if line.th ~= thick then line:SetThickness(thick); line.th = thick end
  if line.a1 ~= a1 or line.b1 ~= b1 then line:SetStartPoint("CENTER", ctx.frame, a1, b1); line.a1, line.b1 = a1, b1 end
  if line.a2 ~= a2 or line.b2 ~= b2 then line:SetEndPoint("CENTER", ctx.frame, a2, b2); line.a2, line.b2 = a2, b2 end
  MR.Show(line, true)
  return true
end
local function hideFrom(ctx, k) for i = k, #ctx.lines do MR.Show(ctx.lines[i], false) end end
MR.HideFrom = hideFrom -- (the Map page's strokes, MapPage.lua)

-- a stroke that stops 0.45 of the pin's size short of its end (at the pin's edge); none under 6 pixels
function MR.Stroke(ctx, x1, y1, x2, y2, col, thick, alpha, size)
  local dx, dy = x2 - x1, y2 - y1
  local len = sqrt(dx * dx + dy * dy)
  if len < 6 then return false end
  local back = min(size * 0.45, len)
  return MR.Line(ctx, x1, y1, x2 - dx / len * back, y2 - dy / len * back, col, thick, alpha)
end

-- the route's strokes, segs[i] = { x1, y1, x2, y2, col, alpha, size (of the pin at its end), gold (you to the next
-- place: left to the golden path when that is drawn) }. A stroke to a place off the minimap runs to its edge, pointing
-- the way, and stops short of nothing. Returns how many were drawn
function MR.DrawRoute(ctx, segs, n, thick, skipGold)
  ctx.used = 0
  local drawn = 0
  for i = 1, n do
    local sg = segs[i]
    if not (sg.gold and skipGold) then
      local cut = QB.MiniView.Reach(sg.x2, sg.y2) > ctx.r
      if MR.Stroke(ctx, sg.x1, sg.y1, sg.x2, sg.y2, sg.col, thick, sg.alpha, cut and 0 or sg.size) then drawn = drawn + 1 end
    end
  end
  hideFrom(ctx, ctx.used + 1)
  return drawn
end

-------------------------------------------------------------------------
-- The golden path: QB.Walk.Path's way from you to the next place, its points simplified, each stretch of a kind
-- ("own": along your trails; "line": the straight bits from you to the trails and from them to the place, when longer
-- than JOIN_LINE yards), cut in pieces of SPACING yards to draw. Searched again for a new place; for the same one, not
-- until you moved MOVE yards: then trimmed behind you while you walk along it (searched again after REFRESH seconds,
-- for trails noted meanwhile), else searched again, at most every EVERY seconds. In continent yards
-------------------------------------------------------------------------
local GP = { MOVE = 8, EVERY = 2, REFRESH = 15, SIMPLIFY = 1, JOIN_LINE = 20, ON_WAY = 20, MAX_SUB = 200, SPACING = 15 / 0.9144,
  NEAR = 20 / 0.9144, THICK = 8, ALPHA = 0.9, LINE_PALE = 0.7, LINE_THIN = 0.6, n = 0, np = 0,
  x = {}, y = {}, seg = {}, ax = {}, ay = {}, bx = {}, by = {}, pk = {}, wx = {}, wy = {}, wk = {}, stack = {} }
MR.GP = GP
GP.DEFAULTS = { gpSpacing = 15, gpWidth = 8, gpAlpha = 0.9, gpColor = { 1, 0.82, 0 } }

-- QuestTrail's settings: shown (goldenPath), its pieces in metres (gpSpacing 5 to 50), its width in pixels (gpWidth 2
-- to 32), its opacity (gpAlpha 0.2 to 1) and its colour (gpColor)
function GP.On() return QB:Settings().goldenPath ~= false end
function GP.Thickness() return max(2, min(32, tonumber(QB:Settings().gpWidth) or GP.THICK)) end
function GP.Alpha() return max(0.2, min(1, tonumber(QB:Settings().gpAlpha) or GP.ALPHA)) end
function GP.Spacing() return max(5, min(50, tonumber(QB:Settings().gpSpacing) or 15)) / 0.9144 end
-- gold where you walked (line_arrow.png multiplied by the colour: its dark edges stay dark); paler (LINE_PALE of the
-- way to white) and thinner (LINE_THIN) across ground you never did. The same tables while the colour is unchanged
local TINT = { r = 1, g = 0.82, b = 0, own = { 1, 0.82, 0 } }
TINT.line = { 1, 0.82 + 0.18 * GP.LINE_PALE, GP.LINE_PALE }
function GP.ColorOf(kind)
  local c = QB:Settings().gpColor
  if type(c) ~= "table" then c = GP.DEFAULTS.gpColor end
  local r, g, b = tonumber(c[1]) or 1, tonumber(c[2]) or 0.82, tonumber(c[3]) or 0
  if TINT.r ~= r or TINT.g ~= g or TINT.b ~= b then
    local k = GP.LINE_PALE
    TINT.r, TINT.g, TINT.b = r, g, b
    TINT.own = { r, g, b }
    TINT.line = { r + (1 - r) * k, g + (1 - g) * k, b + (1 - b) * k }
  end
  return kind == "own" and TINT.own or TINT.line
end
function GP.WidthOf(kind) return kind == "own" and 1 or GP.LINE_THIN end

-- Douglas-Peucker on points i..j: keep[k] = true for the points kept
local function simplify(xs, ys, i, j, tol, keep)
  local stack = GP.stack
  for k = #stack, 1, -1 do stack[k] = nil end
  stack[1], stack[2] = i, j
  while #stack > 0 do
    local b, a = table.remove(stack), table.remove(stack)
    local ax, ay, bx, by = xs[a], ys[a], xs[b], ys[b]
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local far, farD = nil, tol
    for k = a + 1, b - 1 do
      local px, py = xs[k], ys[k]
      local d
      if len2 == 0 then d = sqrt((px - ax) ^ 2 + (py - ay) ^ 2)
      else d = abs((px - ax) * dy - (py - ay) * dx) / sqrt(len2) end
      if d > farD then far, farD = k, d end
    end
    if far then
      keep[far] = true
      stack[#stack + 1] = a; stack[#stack + 1] = far
      stack[#stack + 1] = far; stack[#stack + 1] = b
    end
  end
end

-- the way cut in pieces: SPACING yards each (at most MAX_SUB of them), the way's own corners kept; each piece keeps
-- its stretch's kind
function GP.Cut()
  local spacing = GP.Spacing()
  if GP.len and GP.len / spacing > GP.MAX_SUB then spacing = GP.len / GP.MAX_SUB end
  local np, nextCut, walked = 0, spacing, 0
  for i = 1, GP.n - 1 do
    local x1, y1, x2, y2 = GP.x[i], GP.y[i], GP.x[i + 1], GP.y[i + 1]
    local dx, dy = x2 - x1, y2 - y1
    local segLen = sqrt(dx * dx + dy * dy)
    local from = 0
    while segLen > 0 and walked + segLen >= nextCut and nextCut - walked > from do
      local t = (nextCut - walked) / segLen
      np = np + 1
      GP.ax[np], GP.ay[np] = x1 + dx * from / segLen, y1 + dy * from / segLen
      GP.bx[np], GP.by[np], GP.pk[np] = x1 + dx * t, y1 + dy * t, GP.seg[i]
      from = nextCut - walked
      nextCut = nextCut + spacing
    end
    if from < segLen then
      np = np + 1
      GP.ax[np], GP.ay[np] = x1 + dx * from / segLen, y1 + dy * from / segLen
      GP.bx[np], GP.by[np], GP.pk[np] = x2, y2, GP.seg[i]
    end
    walked = walked + segLen
  end
  GP.np = np
end

-- whether any stretch of the way runs along your trails (GP.own): one that is all straight line is no golden path
local function walked()
  for i = 1, GP.n - 1 do if GP.seg[i] == "own" then return true end end
  return false
end

-- You still on the way (within ON_WAY yards of one of its first segments): the points behind you dropped, the way
-- starting where you stand. Anywhere: joined from you to its nearest point, however far (that first bit straight,
-- when long). False when you left it
function GP.Advance(px, py, anywhere)
  local bestI, bestD, bestT
  for i = 1, anywhere and GP.n - 1 or min(GP.n - 1, 8) do
    local ax, ay, bx, by = GP.x[i], GP.y[i], GP.x[i + 1], GP.y[i + 1]
    local dx, dy = bx - ax, by - ay
    local l2 = dx * dx + dy * dy
    local t = l2 > 0 and max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / l2)) or 0
    local ex, ey = ax + dx * t - px, ay + dy * t - py
    local d = ex * ex + ey * ey
    if not bestD or d < bestD then bestI, bestD, bestT = i, d, t end
  end
  if not bestD or (bestD > GP.ON_WAY * GP.ON_WAY and not anywhere) then return false end
  local drop = bestI - 1
  if bestT >= 1 then drop = bestI end
  if drop > 0 then
    local n = GP.n
    for k = 1, n - drop do GP.x[k], GP.y[k], GP.seg[k] = GP.x[k + drop], GP.y[k + drop], GP.seg[k + drop] end
    for k = n - drop + 1, n do GP.x[k], GP.y[k], GP.seg[k] = nil, nil, nil end
    GP.n = n - drop
  end
  if GP.n < 2 then return false end
  GP.x[1], GP.y[1] = px, py
  if bestD > GP.ON_WAY * GP.ON_WAY then GP.seg[1] = "line" end
  GP.own = walked()
  local len = 0
  for i = 1, GP.n - 1 do
    local dx, dy = GP.x[i + 1] - GP.x[i], GP.y[i + 1] - GP.y[i]
    len = len + sqrt(dx * dx + dy * dy)
  end
  GP.len = len
  GP.Cut()
  return true
end

-- the way from you (continent c, px, py) to (tx, ty), worked out when needed: true when your trails know one
function GP.Update(c, px, py, tx, ty)
  local now = GetTime()
  if GP.c == c and GP.tx == tx and GP.ty == ty and GP.fx then
    local dx, dy = px - GP.fx, py - GP.fy
    if dx * dx + dy * dy < GP.MOVE * GP.MOVE then return GP.n > 1 and GP.own end
    if GP.n > 1 and now - GP.at < GP.REFRESH and GP.Advance(px, py) then GP.fx, GP.fy = px, py; return GP.own end
    -- off the way, searched a moment ago: joined from where you stand until the next search
    if now - GP.at < GP.EVERY then
      if GP.n > 1 and GP.Advance(px, py, true) then GP.fx, GP.fy = px, py end
      return GP.n > 1 and GP.own
    end
  end
  GP.c, GP.tx, GP.ty, GP.fx, GP.fy, GP.at = c, tx, ty, px, py, now
  local pts = QB.Walk and QB.Walk.Path(c, { wx = px, wy = py }, { wx = tx, wy = ty })
  if not pts then GP.n, GP.np, GP.own = 0, 0, false; return false end
  -- the points simplified (a trail noted every 15 yards is mostly straight runs); the bits from you and to the place
  -- kept as they are
  local xs, ys, keep, cnt = GP.wx, GP.wy, GP.wk, #pts
  for k in pairs(keep) do keep[k] = nil end
  for k = 1, cnt do xs[k], ys[k] = pts[k][1], pts[k][2] end
  keep[1], keep[cnt] = true, true
  if cnt > 2 then
    keep[2], keep[cnt - 1] = true, true
    if cnt > 4 then simplify(xs, ys, 2, cnt - 1, GP.SIMPLIFY, keep) end
  end
  local n = 0
  for k = 1, cnt do
    if keep[k] then n = n + 1; GP.x[n], GP.y[n] = xs[k], ys[k] end
  end
  for k = n + 1, #GP.x do GP.x[k], GP.y[k] = nil, nil end
  GP.n = n
  local len = 0
  for i = 1, n - 1 do
    local dx, dy = GP.x[i + 1] - GP.x[i], GP.y[i + 1] - GP.y[i]
    local d = sqrt(dx * dx + dy * dy)
    len = len + d
    GP.seg[i] = ((i == 1 or i == n - 1) and d > GP.JOIN_LINE) and "line" or "own"
  end
  for k = n, #GP.seg do GP.seg[k] = nil end
  GP.len, GP.own = len, walked()
  GP.Cut()
  return GP.own
end

-- not drawn within NEAR yards of the place (20 metres: it is in sight), in the air, nor on a flight
function GP.Hidden(px, py, tx, ty)
  local dx, dy = tx - px, ty - py
  if dx * dx + dy * dy < GP.NEAR * GP.NEAR then return true end
  if IsFlying then
    local ok, f = pcall(IsFlying)
    if ok and QB.Plain(f) == true then return true end
  end
  if UnitOnTaxi then
    local ok, t = pcall(UnitOnTaxi, "player")
    if ok and QB.Plain(t) == true then return true end
  end
  return false
end

-- the golden path from you (me) to w: worked out, and true when it is drawn (not with the switch off)
function MR.Gold(me, w)
  if not GP.On() then return false end
  return GP.Update(me.c, me.wx, me.wy, w.wx, w.wy) and not GP.Hidden(me.wx, me.wy, w.wx, w.wy)
end

-- the golden path on the view v: its pieces within the minimap (the stroke's whole width inside), turning with it;
-- zoomed far out, where a piece is under 4 pixels, the way's own stretches instead, a line each
function MR.DrawGold(v)
  local ctx = MR.gold
  local thick, alpha = GP.Thickness(), GP.Alpha()
  ctx.used, ctx.r, ctx.square = 0, v.R - thick / 2 - 1, v.square
  local ax, ay, bx, by, pk, count = GP.ax, GP.ay, GP.bx, GP.by, GP.pk, GP.np
  local whole = GP.Spacing() * v.scale < 4
  if whole then ax, ay, bx, by, pk, count = GP.x, GP.y, nil, nil, GP.seg, GP.n - 1 end
  local Point = QB.MiniView.Point
  for k = 1, count do
    local x1, y1 = Point(v, ax[k], ay[k])
    local x2, y2 = Point(v, whole and GP.x[k + 1] or bx[k], whole and GP.y[k + 1] or by[k])
    MR.Line(ctx, x1, y1, x2, y2, GP.ColorOf(pk[k]), thick * GP.WidthOf(pk[k]), alpha)
  end
  hideFrom(ctx, ctx.used + 1)
  return ctx.used
end

-- each placing (Mini.Place): the route's strokes (thick pixels wide: QuestTrail's stroke width setting, MR.THICK when
-- not given) and, when gold, the golden path in place of the first one. Returns the strokes and the golden path's
-- pieces drawn
function MR.Draw(v, segs, n, gold, thick)
  MR.Frames()
  thick = thick or MR.THICK
  local ctx = MR.route
  ctx.r, ctx.square = v.R - thick * 0.55, v.square
  local lines = MR.DrawRoute(ctx, segs, n, thick, gold)
  local pieces = 0
  if gold then pieces = MR.DrawGold(v) else hideFrom(MR.gold, 1) end
  MR.goldShown = pieces
  return lines, pieces
end

function MR.Clear()
  hideFrom(MR.route, 1)
  hideFrom(MR.gold, 1)
  MR.goldShown = 0
end
