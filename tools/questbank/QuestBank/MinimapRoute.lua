-- SPDX-License-Identifier: GPL-3.0-or-later AND MIT
-- Contains code from QuestTrail 3.0.6, Copyright (c) 2026 Krom, MIT licence (LICENSE-QuestTrail.txt): QuestTrail_ZoneMap.lua: Smooth, ZM_Show, ZM_Color, ZoneMapLine, ZoneMapArrow, RouteDraw, DrawMinimapRoute; QuestTrail_GoldenPath.lua: WidthOf, ColorOf, Simplify, Cut, Update, Advance, MMFrame, HideFrom, Edge, Clip, DrawMinimap, Tick
-- The route's strokes on the minimap, after QuestTrail's: one stroke a step (you to the next place, then stop to
-- stop), each a line of art/line_arrow.png (a light core between dark edges, tinted), cut where it leaves the
-- minimap's circle (or square) and stopping at the edge of the pin it leads to. And the golden path: the way your
-- walked trails know from you to that next place (QB.Walk.Path), kept while you walk along it and trimmed behind you,
-- gold along your trails, paler and thinner where it crosses ground you never walked. All in pixels from the
-- minimap's centre, where the view (MinimapView.lua) puts them; Minimap.lua says what to draw.
local _, QB = ...
local MR = { THICK = 6, GAP = 3, SOFT = 0.55 } -- (THICK 8 before 5.4.4: a quarter thinner, the owner's "slightly thinner")
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
-- over the far ground (+1) and under QuestBank's pins (+5), the ! and ? among them: a stroke never covers a quest's
-- icon. Each a pool of lines; r and square: where they are cut
MR.route, MR.gold = { lines = {}, used = 0 }, { lines = {}, used = 0 }
local CONTEXTS = { MR.route, MR.gold }
function MR.Frames()
  local base = Minimap:GetFrameLevel() or 1
  for i, ctx in ipairs(CONTEXTS) do
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

-- the parts of a stroke from (x1, y1) to (x2, y2) that cross a quest's icon other than the two it joins (marks:
-- { x, y, r } in the same pixels, n of them, each widened by pad; an icon round either end is one it joins), as
-- fractions of the stroke, in order and merged: spans[1], spans[2] the first, and so on. Returns how many. Into one
-- table kept here: nothing is made
local spans = {}
MR.spans = spans
function MR.Spans(x1, y1, x2, y2, marks, n, pad)
  local dx, dy = x2 - x1, y2 - y1
  local l2 = dx * dx + dy * dy
  local k = 0
  if l2 <= 0 then return 0 end
  pad = pad or 0
  for i = 1, n or 0 do
    local m = marks[i]
    local r = m.r + pad + MR.GAP
    local r2 = r * r
    if (m.x - x1) ^ 2 + (m.y - y1) ^ 2 > r2 and (m.x - x2) ^ 2 + (m.y - y2) ^ 2 > r2 then
      local rr = m.r + pad
      local fx, fy = x1 - m.x, y1 - m.y
      local b = 2 * (fx * dx + fy * dy)
      local disc = b * b - 4 * l2 * (fx * fx + fy * fy - rr * rr)
      if disc > 0 then
        local sq = sqrt(disc)
        local t0, t1 = max(0, (-b - sq) / (2 * l2)), min(1, (-b + sq) / (2 * l2))
        if t0 < t1 then
          -- (kept in order of their start as they come: a few at most)
          k = k + 1
          local j = k
          while j > 1 and spans[2 * j - 3] > t0 do
            spans[2 * j - 1], spans[2 * j] = spans[2 * j - 3], spans[2 * j - 2]
            j = j - 1
          end
          spans[2 * j - 1], spans[2 * j] = t0, t1
        end
      end
    end
  end
  -- (overlapping ones as one)
  local m = 0
  for j = 1, k do
    local a, b = spans[2 * j - 1], spans[2 * j]
    if m > 0 and a <= spans[2 * m] then
      if b > spans[2 * m] then spans[2 * m] = b end
    else
      m = m + 1
      spans[2 * m - 1], spans[2 * m] = a, b
    end
  end
  return m
end

-- a stroke between two pins that stops a little short of each (5.4.4: half the pin's size and GAP pixels more, a small
-- gap round each icon, so the icon reads clearly; 5.4.3 ran to 0.45 of it at the end and into the pin at the start).
-- size: the pin at its end; size0: the one at its start (0 or nil: none, the stroke starts where it starts). None
-- under 6 pixels, nor where the gaps leave nothing. With marks (n of them, widened by pad: MR.Spans), softened (SOFT)
-- only where it crosses another quest's icon, a line for each part: 5.4.4 as first built softened the whole stroke,
-- and the stroke from you dimmed and came back as you walked past an icon beside it. True when any of it was drawn
function MR.Stroke(ctx, x1, y1, x2, y2, col, thick, alpha, size, size0, marks, n, pad)
  local dx, dy = x2 - x1, y2 - y1
  local len = sqrt(dx * dx + dy * dy)
  if len < 6 then return false end
  local back = (size or 0) > 0 and size * 0.5 + MR.GAP or 0
  local front = (size0 or 0) > 0 and size0 * 0.5 + MR.GAP or 0
  -- (a short one keeps 6 pixels: the gap at its start gives way first, then the one at its end)
  if back + front > len - 6 then
    front = max(0, len - 6 - back)
    if back > len - 6 then back = max(0, len - 6) end
  end
  local ux, uy = dx / len, dy / len
  local k = 0
  if marks and (n or 0) > 0 then
    -- (judged on its part on the minimap: a stroke cut at the edge joins the pin on the rim there, its stop's)
    local a1, b1, a2, b2 = MR.Clip(x1, y1, x2, y2, ctx.r, ctx.square)
    if a1 then
      local l2 = len * len
      local c0 = ((a1 - x1) * dx + (b1 - y1) * dy) / l2
      local c1 = ((a2 - x1) * dx + (b2 - y1) * dy) / l2
      k = MR.Spans(a1, b1, a2, b2, marks, n, pad)
      for j = 1, 2 * k do spans[j] = c0 + spans[j] * (c1 - c0) end
    end
  end
  -- (each line drawn names its stroke, line.of: the strokes counted from the context's first, ctx.strokes)
  ctx.strokes = (ctx.strokes or 0) + 1
  local was = ctx.used
  local drew = false
  if k == 0 then
    drew = MR.Line(ctx, x1 + ux * front, y1 + uy * front, x2 - ux * back, y2 - uy * back, col, thick, alpha)
  else
    local t, tEnd = front / len, 1 - back / len
    for j = 1, k do
      local a, b = max(t, spans[2 * j - 1]), min(tEnd, spans[2 * j])
      if a < b then
        if a > t and MR.Line(ctx, x1 + dx * t, y1 + dy * t, x1 + dx * a, y1 + dy * a, col, thick, alpha) then drew = true end
        if MR.Line(ctx, x1 + dx * a, y1 + dy * a, x1 + dx * b, y1 + dy * b, col, thick, alpha * MR.SOFT) then drew = true end
        t = b
      end
    end
    if tEnd > t and MR.Line(ctx, x1 + dx * t, y1 + dy * t, x1 + dx * tEnd, y1 + dy * tEnd, col, thick, alpha) then drew = true end
  end
  for i = was + 1, ctx.used do ctx.lines[i].of = ctx.strokes end
  return drew
end

-- how much a stroke from (x1, y1) to (x2, y2) is softened, as a whole: SOFT where it crosses a quest's icon other than
-- the two it joins (marks: { x, y, r } in the same pixels, n of them; an icon round either end is one it joins), else
-- 1. The golden path's pieces, a few yards each, take it whole; a stroke is softened only where it crosses (MR.Stroke)
function MR.Soften(x1, y1, x2, y2, marks, n, pad)
  local dx, dy = x2 - x1, y2 - y1
  local l2 = dx * dx + dy * dy
  for i = 1, n or 0 do
    local m = marks[i]
    local r = m.r + (pad or 0) + MR.GAP
    local r2 = r * r
    if (m.x - x1) ^ 2 + (m.y - y1) ^ 2 > r2 and (m.x - x2) ^ 2 + (m.y - y2) ^ 2 > r2 then
      local t = l2 > 0 and ((m.x - x1) * dx + (m.y - y1) * dy) / l2 or 0
      if t > 0 and t < 1 then
        local ex, ey = x1 + dx * t - m.x, y1 + dy * t - m.y
        local rr = m.r + (pad or 0)
        if ex * ex + ey * ey <= rr * rr then return MR.SOFT end
      end
    end
  end
  return 1
end

-- the route's strokes, segs[i] = { x1, y1, x2, y2, col, alpha, size (of the pin at its end), gold (you to the next
-- place: left to the golden path when that is drawn) }, softened where they cross another quest's icon (marks, nm:
-- Minimap.lua's, MR.Stroke). Each starts a gap off the pin before it (the one before's end; from you, your arrow's)
-- and stops a gap short of its own; a stroke to a place off the minimap runs to its edge, pointing the way, and stops
-- short of nothing. Returns how many were drawn
MR.YOU = 10 -- pixels: the gap round your arrow, where the first stroke starts
function MR.DrawRoute(ctx, segs, n, thick, skipGold, marks, nm)
  ctx.used, ctx.strokes = 0, 0
  local drawn = 0
  for i = 1, n do
    local sg = segs[i]
    if not (sg.gold and skipGold) then
      local cut = QB.MiniView.Reach(sg.x2, sg.y2) > ctx.r
      local start = i == 1 and MR.YOU or (QB.MiniView.Reach(sg.x1, sg.y1) > ctx.r and 0 or segs[i - 1].size or 0)
      if MR.Stroke(ctx, sg.x1, sg.y1, sg.x2, sg.y2, sg.col, thick, sg.alpha, cut and 0 or sg.size, start, marks, nm, thick * 0.5) then drawn = drawn + 1 end
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
-- for trails noted meanwhile), else searched again, at most every EVERY seconds. In continent yards.
-- Both edges have a band (5.4.4): you join the way within ON_WAY yards of it and leave it past ON_WAY_KEEP; the trails
-- are found within Walk.REACH yards of you and kept to Walk.REACH_KEEP while a way is shown. On the edge itself (5.4.3)
-- the path came and went, and was searched again, with each step. GP.searches counts the searches (/qb trace)
-------------------------------------------------------------------------
local GP = { MOVE = 8, EVERY = 2, REFRESH = 15, SIMPLIFY = 1, JOIN_LINE = 20, ON_WAY = 20, ON_WAY_KEEP = 35, MAX_SUB = 200,
  SPACING = 15 / 0.9144, NEAR = 20 / 0.9144, THICK = 6, ALPHA = 0.9, LINE_PALE = 0.7, LINE_THIN = 0.6, n = 0, np = 0, searches = 0,
  x = {}, y = {}, seg = {}, ax = {}, ay = {}, bx = {}, by = {}, pk = {}, wx = {}, wy = {}, wk = {}, stack = {},
  dx = {}, dy = {}, dk = {}, dn = 0 }
MR.GP = GP
GP.DEFAULTS = { gpSpacing = 15, gpWidth = 6, gpAlpha = 0.9, gpColor = { 1, 0.82, 0 } }

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

-- the drawn way (GP.dx, dy, dk, dn: you, where you join the way, and the way on from there; GP.Aim) cut in pieces:
-- SPACING yards each (at most MAX_SUB of them), the way's own corners kept; each piece keeps its stretch's kind
function GP.Cut()
  local spacing = GP.Spacing()
  if GP.len and GP.len / spacing > GP.MAX_SUB then spacing = GP.len / GP.MAX_SUB end
  local np, nextCut, walked = 0, spacing, 0
  local DX, DY, DK = GP.dx, GP.dy, GP.dk
  for i = 1, GP.dn - 1 do
    local x1, y1, x2, y2 = DX[i], DY[i], DX[i + 1], DY[i + 1]
    local dx, dy = x2 - x1, y2 - y1
    local segLen = sqrt(dx * dx + dy * dy)
    local from = 0
    while segLen > 0 and walked + segLen >= nextCut and nextCut - walked > from do
      local t = (nextCut - walked) / segLen
      np = np + 1
      GP.ax[np], GP.ay[np] = x1 + dx * from / segLen, y1 + dy * from / segLen
      GP.bx[np], GP.by[np], GP.pk[np] = x1 + dx * t, y1 + dy * t, DK[i]
      from = nextCut - walked
      nextCut = nextCut + spacing
    end
    if from < segLen then
      np = np + 1
      GP.ax[np], GP.ay[np] = x1 + dx * from / segLen, y1 + dy * from / segLen
      GP.bx[np], GP.by[np], GP.pk[np] = x2, y2, DK[i]
    end
    walked = walked + segLen
  end
  GP.np = np
end

-- whether any stretch of the drawn way runs along your trails (GP.own): one that is all straight line is no golden path
local function walked()
  for i = 1, GP.dn - 1 do if GP.dk[i] == "own" then return true end end
  return false
end

-- Where you join the way (5.4.4, the owner: "even if I run the right direction, if I cut pathing the yellow line wants
-- me to 'go back' a while until it updates"): 5.4.3 drew the way from you to the next point after its nearest one, and
-- searched again only for a new place, so a corner you cut was a point behind you. The way itself (GP.x, y, seg) is kept
-- as before, anchored at its nearest point to you and trimmed behind you, so being on it or off it is judged as before;
-- what is drawn (GP.dx, dy, dk) joins it further on: at the furthest point within AHEAD yards of you, clear of its own
-- detours (from you along the way while it stays within reach: where it leaves the circle round you, round a lake or a
-- wall, the join stops; at most LOOK segments looked through). Worked out again at every look, without a search, and
-- never behind the anchor; the line shortens as you go. Straight to the place when it is within that reach, or nearer
-- than the join, or, off the way (you left it, cutting across), when going straight there is shorter than rejoining
-- (off a trail both count the roads' DETOUR, along it the way's own length). In place, on the arrays kept: no table made
GP.AHEAD, GP.LOOK = 80, 40
function GP.Aim(px, py, near)
  local X, Y, S, n = GP.x, GP.y, GP.seg, GP.n
  local DX, DY, DK = GP.dx, GP.dy, GP.dk
  local R = GP.AHEAD
  local ai, at = 1, 0
  for i = 1, min(n - 1, GP.LOOK) do
    local ax, ay = X[i], Y[i]
    local dx, dy = X[i + 1] - ax, Y[i + 1] - ay
    local a = dx * dx + dy * dy
    local t2 = 1
    if a > 0 then
      local fx, fy = ax - px, ay - py
      local b = 2 * (fx * dx + fy * dy)
      local disc = b * b - 4 * a * (fx * fx + fy * fy - R * R)
      if disc < 0 then break end
      t2 = (-b + sqrt(disc)) / (2 * a)
    end
    if t2 >= 1 then
      ai, at = i, 1
    else
      ai, at = i, max(0, t2)
      break
    end
  end
  local jx, jy = X[ai] + (X[ai + 1] - X[ai]) * at, Y[ai] + (Y[ai + 1] - Y[ai]) * at
  local tx, ty = X[n], Y[n]
  local d1 = sqrt((jx - px) ^ 2 + (jy - py) ^ 2)
  -- the bit from you to J: the way's own where every stretch it stands for is, and you are on the way
  local kind = "own"
  for i = 1, ai do if S[i] ~= "own" then kind = "line" end end
  if not near and d1 > GP.JOIN_LINE then kind = "line" end
  local straight = (ai == n - 1 and at >= 0.999) or (tx - px) ^ 2 + (ty - py) ^ 2 <= d1 * d1
  if not straight and not near then
    -- (once straight, kept so while you stay off the way, until rejoining is a tenth cheaper: no flip at the edge)
    local detour = (QB.Model and QB.Model.DETOUR) or 1.3
    local rest = sqrt((X[ai + 1] - jx) ^ 2 + (Y[ai + 1] - jy) ^ 2)
    for i = ai + 1, n - 1 do rest = rest + sqrt((X[i + 1] - X[i]) ^ 2 + (Y[i + 1] - Y[i]) ^ 2) end
    local direct, rejoin = sqrt((tx - px) ^ 2 + (ty - py) ^ 2) * detour, d1 * detour + rest
    if direct <= (GP.straight and rejoin / 0.9 or rejoin) then straight, kind = true, "line" end
  end
  GP.straight = (straight and not near) or nil
  local dn = 1
  DX[1], DY[1] = px, py
  if straight then
    dn = 2
    DX[2], DY[2], DK[1] = tx, ty, kind
  else
    DK[1] = kind
    if at < 0.999 then dn = dn + 1; DX[dn], DY[dn], DK[dn] = jx, jy, S[ai] end
    for i = ai + 1, n do
      dn = dn + 1
      DX[dn], DY[dn], DK[dn] = X[i], Y[i], S[i]
    end
  end
  for k = dn + 1, #DX do DX[k], DY[k], DK[k] = nil, nil, nil end
  DK[dn] = nil
  GP.dn = dn
  local len = 0
  for i = 1, dn - 1 do len = len + sqrt((DX[i + 1] - DX[i]) ^ 2 + (DY[i + 1] - DY[i]) ^ 2) end
  GP.len, GP.own = len, walked()
  GP.Cut()
end

-- You still on the way (within ON_WAY yards of one of its first segments, ON_WAY_KEEP while you were on it at the last
-- look): the points behind you dropped, the way starting at its point nearest you (the anchor: on the way itself, never
-- behind the last one). 5.4.3 started it where you stood, and its first stretch, from your last place, kept you "on the
-- way" as you ran off it at an angle: a cut corner was pointed back at for up to 15 seconds, until the next search.
-- Anywhere: joined to its nearest point, however far. Then what is drawn (GP.Aim). False when you left it
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
  local onWay = GP.onWay and GP.ON_WAY_KEEP or GP.ON_WAY
  local near = bestD and bestD <= onWay * onWay
  if not anywhere then GP.onWay = near or false end
  if not bestD or (not near and not anywhere) then return false end
  local drop = bestI - 1
  if bestT >= 1 then drop = bestI end
  if drop > 0 then
    local n = GP.n
    for k = 1, n - drop do GP.x[k], GP.y[k], GP.seg[k] = GP.x[k + drop], GP.y[k + drop], GP.seg[k + drop] end
    for k = n - drop + 1, n do GP.x[k], GP.y[k], GP.seg[k] = nil, nil, nil end
    GP.n = n - drop
  end
  if GP.n < 2 then return false end
  local ax, ay = GP.x[1], GP.y[1]
  if bestT < 1 and drop == bestI - 1 then
    ax, ay = ax + (GP.x[2] - ax) * bestT, ay + (GP.y[2] - ay) * bestT
  end
  GP.x[1], GP.y[1] = ax, ay
  GP.Aim(px, py, near)
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
  -- (the same place as before and a way shown: the trails are looked for a little further, the band at their edge; a
  -- new place: nothing kept of the last one's way)
  local keep = GP.c == c and GP.tx == tx and GP.ty == ty and GP.n > 1 and GP.own
  if not (GP.c == c and GP.tx == tx and GP.ty == ty) then GP.straight = nil end
  GP.c, GP.tx, GP.ty, GP.fx, GP.fy, GP.at = c, tx, ty, px, py, now
  GP.searches = GP.searches + 1
  local pts = QB.Walk and QB.Walk.Path(c, { wx = px, wy = py }, { wx = tx, wy = ty }, keep and QB.Walk.REACH_KEEP or nil)
  GP.onWay = true -- (a way found starts where you stand)
  if not pts then GP.n, GP.np, GP.dn, GP.own = 0, 0, 0, false; return false end
  -- the way from its first point on your trails (the search's first point is you: what is drawn starts there, GP.Aim),
  -- simplified (a trail noted every 15 yards is mostly straight runs); its first and last points and the bit to the
  -- place kept as they are
  local xs, ys, keep, cnt = GP.wx, GP.wy, GP.wk, #pts - 1
  for k in pairs(keep) do keep[k] = nil end
  for k = 1, cnt do xs[k], ys[k] = pts[k + 1][1], pts[k + 1][2] end
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
    GP.seg[i] = (i == n - 1 and d > GP.JOIN_LINE) and "line" or "own"
  end
  for k = n, #GP.seg do GP.seg[k] = nil end
  -- what is drawn: joined ahead of you from the start (a search starts at the trail point nearest you, which may lie
  -- behind you); on the way when that point is within ON_WAY yards
  local nd = n >= 1 and sqrt((GP.x[1] - px) ^ 2 + (GP.y[1] - py) ^ 2) or 0
  if n >= 2 then GP.Aim(px, py, nd <= GP.ON_WAY) else GP.n, GP.dn, GP.len, GP.own = 0, 0, 0, false; GP.Cut() end
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

-- the part of a piece outside the circle of radius r round (cx, cy): its end pulled back to the circle (atEnd), or its
-- start pushed out to it; nil when the whole piece is inside. The golden path's gap round its target's pin and your arrow
local function outside(x1, y1, x2, y2, cx, cy, r, atEnd)
  local r2 = r * r
  local in1 = (x1 - cx) ^ 2 + (y1 - cy) ^ 2 < r2
  local in2 = (x2 - cx) ^ 2 + (y2 - cy) ^ 2 < r2
  if in1 and in2 then return nil end
  if (atEnd and not in2) or (not atEnd and not in1) then return x1, y1, x2, y2 end
  -- where the piece meets the circle: |P(t) - C| = r, the root on the piece
  local dx, dy = x2 - x1, y2 - y1
  local a = dx * dx + dy * dy
  if a <= 0 then return nil end
  local b = 2 * (dx * (x1 - cx) + dy * (y1 - cy))
  local c = (x1 - cx) ^ 2 + (y1 - cy) ^ 2 - r2
  local disc = b * b - 4 * a * c
  if disc < 0 then return x1, y1, x2, y2 end
  local sq = sqrt(disc)
  if atEnd then
    local t = (-b - sq) / (2 * a)
    return x1, y1, x1 + dx * t, y1 + dy * t
  end
  local t = (-b + sq) / (2 * a)
  return x1 + dx * t, y1 + dy * t, x2, y2
end
MR.Outside = outside

-- the golden path on the view v: its pieces within the minimap (the stroke's whole width inside), turning with it;
-- zoomed far out, where a piece is under 4 pixels, the way's own stretches instead, a line each. It stops a gap short of
-- the pin it leads to (tsize: that pin's size; 0 none) and off your arrow, and is softened where it crosses another
-- quest's icon (marks, nm: Minimap.lua's, as MR.Soften reads them)
function MR.DrawGold(v, marks, nm, tsize)
  local ctx = MR.gold
  local thick, alpha = GP.Thickness(), GP.Alpha()
  ctx.used, ctx.r, ctx.square = 0, v.R - thick / 2 - 1, v.square
  local ax, ay, bx, by, pk, count = GP.ax, GP.ay, GP.bx, GP.by, GP.pk, GP.np
  local whole = GP.Spacing() * v.scale < 4
  if whole then ax, ay, bx, by, pk, count = GP.dx, GP.dy, nil, nil, GP.dk, GP.dn - 1 end
  local Point = QB.MiniView.Point
  -- a piece wholly further from the view's centre than the minimap reaches (its corner, when square) is not drawn
  -- (MR.Line would cut all of it away): skipped in yards, before it is turned and scaled. A long way has hundreds of
  -- pieces and only those round you are on the minimap (5.4.2; every one was worked out 20 times a second)
  local cx, cy = v.wx, v.wy
  local lim = (ctx.r * (v.square and 1.4143 or 1) + 2) / v.scale
  local lim2 = lim * lim
  -- the gaps: round the target's pin (the way's last point) and round you (its first)
  local n = GP.dn
  local tx, ty, sx, sy, tr = 0, 0, 0, 0, 0
  if n >= 2 then
    tx, ty = Point(v, GP.dx[n], GP.dy[n])
    sx, sy = Point(v, GP.dx[1], GP.dy[1])
    tr = (tsize or 0) > 0 and tsize * 0.5 + MR.GAP or 0
  end
  for k = 1, count do
    local ux, uy = ax[k], ay[k]
    local wx, wy = whole and GP.dx[k + 1] or bx[k], whole and GP.dy[k + 1] or by[k]
    local dx, dy = wx - ux, wy - uy
    local l2 = dx * dx + dy * dy
    local t = l2 > 0 and ((cx - ux) * dx + (cy - uy) * dy) / l2 or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local ex, ey = ux + dx * t - cx, uy + dy * t - cy
    if ex * ex + ey * ey <= lim2 then
      local x1, y1 = Point(v, ux, uy)
      local x2, y2 = Point(v, wx, wy)
      if tr > 0 then x1, y1, x2, y2 = outside(x1, y1, x2, y2, tx, ty, tr, true) end
      if x1 then x1, y1, x2, y2 = outside(x1, y1, x2, y2, sx, sy, MR.YOU, false) end
      if x1 then
        MR.Line(ctx, x1, y1, x2, y2, GP.ColorOf(pk[k]), thick * GP.WidthOf(pk[k]), alpha * MR.Soften(x1, y1, x2, y2, marks, nm, thick * 0.5))
      end
    end
  end
  hideFrom(ctx, ctx.used + 1)
  return ctx.used
end

-- each placing (Mini.Place): the route's strokes (thick pixels wide: QuestTrail's stroke width setting, MR.THICK when
-- not given) and, when gold, the golden path in place of the first one. Returns the strokes and the golden path's
-- pieces drawn
function MR.Draw(v, segs, n, gold, thick, marks, nm)
  MR.Frames()
  thick = thick or MR.THICK
  local ctx = MR.route
  ctx.r, ctx.square = v.R - thick * 0.55, v.square
  local lines = MR.DrawRoute(ctx, segs, n, thick, gold, marks, nm)
  local pieces = 0
  if gold then pieces = MR.DrawGold(v, marks, nm, n > 0 and segs[1].size or 0) else hideFrom(MR.gold, 1) end
  MR.goldShown = pieces
  return lines, pieces
end

function MR.Clear()
  hideFrom(MR.route, 1)
  hideFrom(MR.gold, 1)
  MR.goldShown = 0
end
