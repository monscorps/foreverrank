-- SPDX-License-Identifier: GPL-3.0-or-later AND MIT
-- Contains code from QuestTrail 3.0.6, Copyright (c) 2026 Krom, MIT licence (LICENSE-QuestTrail.txt): QuestTrail_Pins.lua: WeightScale, ByWeight, MergeOverlaps, Item, SizePin, RebuildMinimapCache, GroupMinimap, UpdateMinimap, the selected quest's pulse
-- The route on the minimap: a numbered pin for every stop of the hand-in route, a stroke from you to the next place
-- and from stop to stop (MinimapRoute.lua), the NPCs who take your finished quests, your pick-up list, the objectives
-- of the quests in your log, and the entrances of the dungeons around you, ticked once their quests are all done.
-- While the arrow sends you by a flight master, a pier or the tram first, that is pinned too, and the stroke and the
-- label go there. Placed QuestTrail's way: out of reach, the stops, the step and the hand-ins sit on the rim, dimmer,
-- in the direction they lie, and the rest fade out over their last width before it; one quest's objectives close
-- together on the ground are one pin, a little bigger; each place keeps its pin while the view moves. Click a pin: a
-- waypoint there, as on the world map; right-click it: the minimap's menu. Alt-drag moves the minimap, Ctrl-wheel
-- sizes it, the wheel zooms it: the game's own levels, then further out over the game's minimap tiles, and a drag pans
-- that far view (MinimapView.lua). Everything here is QuestBank's own frames laid over the Minimap; of the game's only
-- its release script is wrapped (MinimapView.lua), and the minimap itself is only scaled, moved and zoomed, never in
-- a fight. (QuestBank's Map is the game's world map: UI.OpenMap.)
--   where a pin is: the stop's map and position go through QB.Model.World to continent yards, as the arrow's do, and
--   then through the minimap's view (MV.View: its centre, its radius in yards from C_Minimap.GetViewRadius or the far
--   zoom, its turn with your facing under rotateMinimap).
local _, QB = ...
local Mini = {}
QB.Mini = Mini

local TICK = 0.05          -- seconds between placements (the pins follow you); every frame while the view moves
local ART = "Interface\\AddOns\\QuestBank\\art\\"
local MAX_PINS = 60        -- pins at once: the step and the stops first, then the nearest
local EDGE = 7             -- the rim: pins kept on it sit this far inside the minimap's edge
local LIST_EVERY = 0.5     -- seconds the list is kept (and until QuestBank's data or a switch changes)
Mini.TICK, Mini.MAX_PINS = TICK, MAX_PINS
local RANK = { step = 0, stop = 1, turn = 1 }
local PINNED = { step = true, stop = true, turn = true } -- out of reach: on the rim, the way to go
local SIZE = { stop = 22, step = 18, dungeon = 18, obj = 16, pickup = 16, turn = 16 }
local GOLD, BLUE = { 1, 0.84, 0.18 }, { 0.4, 0.55, 1 }

local plain = QB.Plain
local sqrt, floor, cos, pi, max = math.sqrt, math.floor, math.cos, math.pi, math.max
local pins, worldOf, pinOf = {}, {}, {}

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

-- what goes on the minimap: the arrow's step on the way (a flight master, a pier; left out with noStep), the route's
-- stops (numbered), the pick-up list, the hand-ins of your finished quests, the objectives of the others, the dungeon
-- entrances of your continent
function Mini.List(noStep)
  local out = {}
  local step = not noStep and QB.Arrow and QB.Arrow.MiniStep and QB.Arrow.MiniStep()
  if step then out[1] = step end
  local P = QB.Pins
  local stopAt = {}
  if P and P.list then
    for _, d in ipairs(P.list) do
      if d.m and d.m > 0 then
        out[#out + 1] = { m = d.m, x = d.x, y = d.y, name = d.name, num = d.num, kind = "stop", when = d.when, lines = d.lines, late = d.late }
        stopAt[keyOf(d)] = true
      end
    end
  end
  if QB:Settings().minimapPickups ~= false and QB.Arrow and QB.Arrow.ListFor then
    for _, d in ipairs(QB.Arrow.ListFor("pickup") or {}) do
      if d.m and d.m > 0 then out[#out + 1] = { m = d.m, x = d.x, y = d.y, name = d.name, kind = "pickup" } end
    end
  end
  -- the NPCs who take your finished quests, a pin each with the quests it takes (none where a stop's pin stands)
  local turnAt = {}
  for _, e in ipairs(QB.state.logOrder or {}) do
    local q = e.complete and QB.Quest.Get(e.id)
    local t = q and q.turn
    if t and t.m and t.m > 0 and not t.inside then
      local key = keyOf(t)
      local g = turnAt[key]
      if not g and not stopAt[key] then
        g = { m = t.m, x = t.x, y = t.y, name = t.n, kind = "turn", id = e.id, lines = {} }
        turnAt[key] = g
        out[#out + 1] = g
      end
      if g then g.lines[#g.lines + 1] = { q.name, QB.Comma(QB.Model.XpAt(q, QB.state.level)) } end
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
    local done = QB.DMap and QB.DMap.Progress and QB.DMap.Progress() or {}
    for _, c in ipairs(QB.Data.CAT) do
      local e = c.entrance
      if c.dungeon and e and e.m and e.m > 0 then
        local p = done[c.key]
        out[#out + 1] = { m = e.m, x = e.x, y = e.y, name = c.name, kind = "dungeon", icon = c.icon, done = p and p.total > 0 and p.done == p.total or nil }
      end
    end
  end
  return out
end

-- the list as last made: made again after LIST_EVERY seconds, or when QuestBank's data (QB:Changed) or a switch of
-- what it holds changed. Each entry gets its key, so its pin stays its own while the view moves
local cache = {}
function Mini.ListCached()
  local s, now, c = QB:Settings(), GetTime(), cache
  if c.list and now >= c.at and now - c.at < LIST_EVERY and c.v == QB.changed and c.pk == s.minimapPickups
    and c.ob == s.minimapObjectives and c.en == s.minimapEntrances then return c.list end
  local list = Mini.List(true)
  for _, d in ipairs(list) do d.key = d.kind .. ":" .. keyOf(d) .. ":" .. (d.id or d.num or "") end
  c.list, c.at, c.v, c.pk, c.ob, c.en = list, now, QB.changed, s.minimapPickups, s.minimapObjectives, s.minimapEntrances
  return list
end

-- a pin a little bigger where more spots are one (x1 for one, up to x1.4)
local function weightScale(w)
  if not w or w <= 1 then return 1 end
  return 1 + math.min(0.4, 0.15 * math.log(w) / math.log(2))
end
-- the heaviest first; equals always in the same order (the sort is not stable, and the pins kept would change)
local function byWeight(a, b)
  if a.w ~= b.w then return a.w > b.w end
  local qa, qb = a.d.id or 0, b.d.id or 0
  if qa ~= qb then return qa < qb end
  if a.wx ~= b.wx then return a.wx < b.wx end
  return a.wy < b.wy
end

-- The list's places on the view's continent, grouped where they overlap: one quest's objectives closer than 0.8 of a
-- pin's width make one pin, the heaviest's, carrying the others' weight. Grouped on the ground (yards), not on the
-- screen, so a pin coming in at the edge never changes the groups inside; made again only when the list or the zoom
-- changes, its tables kept. Each group { d, w (weight), wx, wy }
local grp = { groups = {}, pool = {}, byQuest = {}, gen = 0 }
function Mini.Group(list, v)
  local zk = floor(math.log(max(v.scale, 1e-6)) * 50)
  if grp.list == list and grp.c == v.c and grp.z == zk then return grp.groups end
  if grp.list ~= list or grp.c ~= v.c then
    local ents = {}
    for _, d in ipairs(list) do
      local w = worldPos(d)
      if w and w.c == v.c then ents[#ents + 1] = { d = d, w = d.w or 1, wx = w.wx, wy = w.wy } end
    end
    table.sort(ents, byWeight)
    grp.ents = ents
  end
  grp.list, grp.c, grp.z, grp.gen = list, v.c, zk, grp.gen + 1
  local groups, reach, ng = grp.groups, SIZE.obj * 0.8 / max(v.scale, 1e-6), 0
  for k = #groups, 1, -1 do groups[k] = nil end
  for _, e in ipairs(grp.ents) do
    local q = e.d.kind == "obj" and e.d.id
    local mine = q and grp.byQuest[q]
    if mine and mine.gen ~= grp.gen then mine.gen, mine.n = grp.gen, 0 end
    local into
    for i = 1, mine and mine.n or 0 do
      local g = mine[i]
      local dx, dy = g.wx - e.wx, g.wy - e.wy
      if dx * dx + dy * dy < reach * reach then into = g; break end
    end
    if into then
      into.w = into.w + e.w
    else
      ng = ng + 1
      local g = grp.pool[ng] or {}
      grp.pool[ng] = g
      g.d, g.w, g.wx, g.wy = e.d, e.w, e.wx, e.wy
      groups[ng] = g
      if q then
        if not mine then mine = { gen = grp.gen, n = 0 }; grp.byQuest[q] = mine end
        mine.n = mine.n + 1
        mine[mine.n] = g
      end
    end
  end
  return groups
end

local overlay
local function overlayFrame()
  if overlay then return overlay end
  overlay = CreateFrame("Frame", "QuestBankMinimap", Minimap)
  overlay:SetAllPoints(Minimap)
  overlay:SetFrameLevel((Minimap:GetFrameLevel() or 2) + 5)
  overlay.elapsed = 0
  overlay:SetScript("OnUpdate", QB.Safe(function(self, dt)
    if Mini.pulsing then Mini.Pulse() end
    self.elapsed = self.elapsed + (dt or 0)
    if self.elapsed < TICK and not QB.MiniView.Moving() then return end
    local step = self.elapsed
    self.elapsed = 0
    Mini.Update(step)
  end, "minimap pins"))
  return overlay
end

local T
local function newPin()
  T = T or QB.Data.TEX
  local p = CreateFrame("Button", nil, overlayFrame())
  p:SetSize(16, 16)
  p.glow = p:CreateTexture(nil, "BACKGROUND")
  p.glow:SetTexture(ART .. "glow.tga")
  p.glow:SetPoint("CENTER")
  p.glow:SetBlendMode("ADD")
  p.glow:Hide()
  p.icon = p:CreateTexture(nil, "ARTWORK")
  p.icon:SetAllPoints()
  p.num = p:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  p.num:SetPoint("CENTER", 0, 0)
  -- a dungeon whose quests are all done: the ready check's tick on its corner
  p.badge = p:CreateTexture(nil, "OVERLAY")
  p.badge:SetTexture(T.ready)
  p.badge:SetSize(10, 10)
  p.badge:SetPoint("BOTTOMRIGHT", 3, -3)
  p.badge:Hide()
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
    if d.kind == "turn" then GameTooltip:AddLine("Hand in here", 0.3, 0.9, 0.3) end
    for _, l in ipairs(d.lines or {}) do GameTooltip:AddDoubleLine(l[1], l[2], 0.9, 0.9, 0.9, 0.6, 0.8, 0.6) end
    if d.kind == "dungeon" then GameTooltip:AddLine(d.done and "Dungeon entrance. Its quests are all done." or "Dungeon entrance", 0.8, 0.8, 0.8) end
    if d.kind == "pickup" then GameTooltip:AddLine("On your pick-up list", 0.8, 0.8, 0.8) end
    GameTooltip:AddLine(string.format(d.m and "%d yards. Click: waypoint." or "%d yards.", self.yards or 0), 0.5, 0.5, 0.5)
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  pins[#pins + 1] = p
  return p
end

-- the game's own crisp art where the client has it (the quest-number pin, the dungeon and quest marks), QuestBank's
-- textures otherwise. The quest picked on QuestBank's Map glows blue, pulsing (Mini.Pulse)
local atlasOr = QB.Art
local function style(p, it)
  local d = it.d
  T = T or QB.Data.TEX
  p.icon:SetVertexColor(1, 1, 1, 1)
  p.num:SetText(it.label or "")
  p.badge:SetShown(d.done == true)
  local glow
  if d.kind == "stop" then
    atlasOr(p.icon, d.num == 1 and "UI-QuestPoi-QuestNumber-SuperTracked" or "UI-QuestPoi-QuestNumber", T.mapPin)
    if d.num == 1 then glow = 2.3 end
  elseif d.kind == "obj" then
    -- the game's own cursor for the work: a sword to kill, a bag to loot, a cogwheel to use or click, coins to buy
    if QB.QuestMap and QB.QuestMap.PaintKind then QB.QuestMap.PaintKind(p.icon, d.obj) else p.icon:SetTexture(131021) end
  elseif d.kind == "dungeon" then
    atlasOr(p.icon, "Dungeon", d.icon or T.ring)
  elseif d.kind == "step" then
    if not atlasOr(p.icon, d.atlas, d.icon) then p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    glow = 2.2
  elseif d.kind == "turn" then
    atlasOr(p.icon, "QuestTurnin", T.questActive)
  else
    atlasOr(p.icon, "QuestNormal", T.questAvail)
  end
  if it.focus then glow = 2.4 end
  p.glow:SetAlpha(1)
  if it.focus then p.glow:SetVertexColor(0.3, 0.55, 1, 0.9) else p.glow:SetVertexColor(1, 0.82, 0.3, 0.55) end
  if glow then p.glow:SetSize(it.size * glow, it.size * glow); p.glow:Show() else p.glow:Hide() end
end

-- the picked quest's pins: their glow from faint to bright and back, once a second (every frame while there are any)
function Mini.Pulse()
  local k, any = (1 - cos(GetTime() * 2 * pi)) / 2, false
  for _, p in ipairs(pins) do
    if p.focus and p:IsShown() then p.glow:SetAlpha(0.25 + 0.75 * k); any = true end
  end
  Mini.pulsing = any
end

-- one update: the view (MinimapView.lua: a drag, the ease back, the far ground and your arrow), then the pins on it
function Mini.Update(dt)
  local me = QB.API.WorldPosition()
  Mini.Place(me, QB.MiniView.Tick(dt, me))
end

-- Where a place's pin goes on the view: whole pixels from the minimap's centre, and how clear; nil when it is gone.
-- Out of reach a stop, the step and a hand-in sit on the rim at 0.6 (the way to go), fading to that over their last
-- width before it; anything else fades out over that width and is gone past the minimap's edge
local function place(v, kind, wx, wy, size)
  local MV = QB.MiniView
  local x, y = MV.Point(v, wx, wy)
  local reach, alpha = MV.Reach(x, y), 1
  if PINNED[kind] then
    local rim = v.R - EDGE
    if reach > rim then x, y, alpha = x * rim / reach, y * rim / reach, 0.6
    elseif reach > rim - size then alpha = 0.6 + 0.4 * (rim - reach) / size end
  elseif reach > v.R then
    return nil
  elseif reach > v.R - size then
    alpha = (v.R - reach) / size
    if alpha < 0.05 then return nil end
  end
  return floor(x + 0.5), floor(y + 0.5), alpha
end

-- the pins of a placing, their tables kept from one to the next (20 a second): { d, key, x, y, alpha, size, label,
-- yards (from you), focus, pin }; the stops' true places, and by number; the strokes; the label's place
local items, itemPool, stops, byNum, segs, free, tinfo, gen = {}, {}, {}, {}, {}, {}, {}, 0
local function addItem(v, me, d, w, wx, wy, focus)
  local size = SIZE[d.kind] or 16
  if d.kind == "obj" then size = max(floor(size * weightScale(w) / 2 + 0.5) * 2, 8) end
  local x, y, alpha = place(v, d.kind, wx, wy, size)
  if not x then return nil end
  local n = #items + 1
  local it = itemPool[n] or {}
  itemPool[n], items[n] = it, it
  local dn, dw = wx - me.wx, wy - me.wy
  it.d, it.key, it.x, it.y, it.alpha, it.size, it.yards = d, d.key or d.kind, x, y, alpha, size, sqrt(dn * dn + dw * dw)
  it.label, it.focus, it.pin = d.num and tostring(d.num) or nil, (focus ~= nil and d.id == focus) or nil, nil
  return it
end
local function byRank(a, b)
  local ka, kb = RANK[a.d.kind] or 2, RANK[b.d.kind] or 2
  if ka ~= kb then return ka < kb end
  return a.yards < b.yards
end
local function seg(n, x1, y1, x2, y2, col, alpha, size, gold)
  local s = segs[n] or {}
  segs[n] = s
  s.x1, s.y1, s.x2, s.y2, s.col, s.alpha, s.size, s.gold = x1, y1, x2, y2, col, alpha, size, gold
  return n
end

-- place every pin for where you stand now (me), on the view v (MV.View's for me when not given): QuestTrail's
-- UpdateMinimap, with QuestBank's places and the game's art
function Mini.Place(me, v)
  if not on() then Mini.Clear(); return end
  me = me or QB.API.WorldPosition()
  local f = overlayFrame()
  if not me then Mini.Clear(); return end
  local MV = QB.MiniView
  v = v or MV.View(me)
  local set = QB:Settings()
  local list = Mini.ListCached()
  local groups = Mini.Group(list, v)
  local focus = QB.MapPage and QB.MapPage.focus
  for k = #items, 1, -1 do items[k] = nil end
  for k = #byNum, 1, -1 do byNum[k] = nil end
  -- the arrow's step first, read now: it moves with the arrow's guide
  local step = QB.Arrow and QB.Arrow.MiniStep and QB.Arrow.MiniStep()
  if step and step.c ~= me.c then step = nil end
  if step then step.key = "step"; addItem(v, me, step, 1, step.wx, step.wy, focus) end
  -- the route's stops in order, at their true places for the strokes; two at one place are one pin, "2,3"
  local ns = 0
  for _, d in ipairs(list) do
    local w = d.kind == "stop" and worldPos(d)
    if w and w.c == me.c then
      local x, y = MV.Point(v, w.wx, w.wy)
      local same
      for i = 1, d.num and ns or 0 do
        local s = stops[i]
        if s.d.num and (s.x - x) ^ 2 + (s.y - y) ^ 2 < SIZE.stop * SIZE.stop * 0.8 then same = s; break end
      end
      ns = ns + 1
      local s = stops[ns] or {}
      stops[ns] = s
      s.d, s.x, s.y = d, x, y
      if same and same.it then
        local it = same.it
        it.label = it.label .. "," .. d.num
        it.size = floor((SIZE.stop + (#it.label - 2) * SIZE.stop * 0.3) / 2 + 0.5) * 2
        s.it = it
      else
        s.it = addItem(v, me, d, 1, w.wx, w.wy, focus)
      end
      if d.num and not byNum[d.num] then byNum[d.num] = s end
    end
  end
  for _, g in ipairs(groups) do
    if g.d.kind ~= "stop" then addItem(v, me, g.d, g.w, g.wx, g.wy, focus) end
  end
  -- too many: the step and the stops first, then the nearest
  if #items > MAX_PINS then
    table.sort(items, byRank)
    for k = #items, MAX_PINS + 1, -1 do items[k] = nil end
  end
  -- each place on the pin it had (QuestTrail's: a place coming in or leaving at the edge moved every pin after it to
  -- another place, each restyled), the free pins to the new places
  gen = gen + 1
  for _, it in ipairs(items) do
    local p = pinOf[it.key]
    if p and p.gen ~= gen and p.key == it.key then p.gen = gen; it.pin = p end
  end
  local nf = 0
  for _, p in ipairs(pins) do
    if p.gen ~= gen then nf = nf + 1; free[nf] = p end
  end
  local fi = 0
  for _, it in ipairs(items) do
    if not it.pin then
      fi = fi + 1
      local p = free[fi] or newPin()
      if p.key and pinOf[p.key] == p then pinOf[p.key] = nil end
      p.gen, p.key, it.pin = gen, it.key, p
      pinOf[it.key] = p
    end
  end
  for i = fi + 1, nf do
    local p = free[i]
    if p:IsShown() then p:Hide() end
    if p.key and pinOf[p.key] == p then pinOf[p.key] = nil end
    p.key = nil
  end
  for i = nf, 1, -1 do free[i] = nil end
  -- (the game called only for what changed: most pins stay as they were while you walk)
  local pulsing = false
  for _, it in ipairs(items) do
    local p, d = it.pin, it.d
    if p.d ~= d or p.label ~= it.label or p.focus ~= it.focus or p.sz ~= it.size or p.sa ~= d.atlas or p.si ~= d.icon then
      if p.sz ~= it.size then p:SetSize(it.size, it.size); p.sz = it.size end
      style(p, it)
      p.label, p.focus, p.sa, p.si = it.label, it.focus, d.atlas, d.icon
    end
    p.d, p.yards = d, it.yards
    if p.a ~= it.alpha then p:SetAlpha(it.alpha); p.a = it.alpha end
    if p.x ~= it.x or p.y ~= it.y then
      p:ClearAllPoints()
      p:SetPoint("CENTER", f, "CENTER", it.x, it.y)
      p.x, p.y = it.x, it.y
    end
    if not p:IsShown() then p:Show() end
    pulsing = pulsing or it.focus or false
  end
  Mini.pulsing = pulsing
  -- where the stroke and the label go: the arrow's step on the way, else stop 1 or a nearer objective of your log
  local target, tw = step, step
  if not target then
    local s1 = byNum[1]
    tw = s1 and worldPos(s1.d)
    target = s1 and s1.d
    local best = tw and (tw.wx - me.wx) ^ 2 + (tw.wy - me.wy) ^ 2
    for _, e in ipairs(grp.ents) do
      local dd = e.d.kind == "obj" and (e.wx - me.wx) ^ 2 + (e.wy - me.wy) ^ 2
      if dd and (not best or dd < best) then target, tw, best = e.d, e, dd end
    end
  end
  Mini.target = target
  local tx, ty = 0, 0
  if target then
    tx, ty = MV.Point(v, tw.wx, tw.wy)
    tinfo.d, tinfo.x, tinfo.y, tinfo.far = target, tx, ty, MV.Reach(tx, ty) > v.R - EDGE
  end
  Mini.Label(target and tinfo, f)
  -- the strokes: you to the target (along the golden path when your trails know the way), on to stop 1 if that is
  -- not it, then stop to stop, up to minimapSteps stops
  local n, gold = 0, false
  if set.minimapLines ~= false and target then
    local mx, my = MV.Point(v, me.wx, me.wy)
    n = seg(1, mx, my, tx, ty, GOLD, 1, SIZE[target.kind] or 16, true)
    local prev, px, py = target, tx, ty
    for num = 1, set.minimapSteps or 5 do
      local s = byNum[num]
      if not s then break end
      if s.d ~= prev then n = seg(n + 1, px, py, s.x, s.y, BLUE, 0.85, s.it and s.it.size or SIZE.stop) end
      prev, px, py = s.d, s.x, s.y
    end
    gold = Mini.GoldenPath(me, target)
  end
  Mini.shown, Mini.linesShown = #items, QB.MiniRoute.Draw(v, segs, n, gold)
  Mini.DrawTrails(v)
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

-- your walked trails (Walk.lua) round the view's centre, faint lines under the route's (MinimapRoute.lua's frame),
-- cut at the minimap's edge
local trailLines = {}
function Mini.DrawTrails(v)
  local n = 0
  local f = QB.MiniRoute.Frames()
  if QB.Walk and QB:Settings().walkShow ~= false and f.CreateLine then
    local Clip, Point, r = QB.MiniRoute.Clip, QB.MiniView.Point, v.R - 3
    for _, seg in ipairs(QB.Walk.Near(v.c, v.wx, v.wy, v.radius * (v.square and 1.42 or 1.1))) do
      local x1, y1 = Point(v, seg[1], seg[2])
      local x2, y2 = Point(v, seg[3], seg[4])
      local a1, b1, a2, b2 = Clip(x1, y1, x2, y2, r, v.square)
      if a1 then
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
        l:SetStartPoint("CENTER", f, a1, b1)
        l:SetEndPoint("CENTER", f, a2, b2)
        l:Show()
      end
    end
  end
  for i = n + 1, #trailLines do trailLines[i]:Hide() end
  Mini.trailsShown = n
end

-- the golden path to a pin's place (MinimapRoute.lua): true when your trails know the way and it is drawn
function Mini.GoldenPath(me, d)
  local w = worldPos(d)
  if not w or w.c ~= me.c then return false end
  return QB.MiniRoute.Gold(me, w)
end

function Mini.Clear()
  for _, p in ipairs(pins) do p:Hide() end
  for _, l in ipairs(trailLines) do l:Hide() end
  if label then label:Hide() end
  QB.MiniRoute.Clear()
  Mini.shown, Mini.linesShown, Mini.trailsShown, Mini.pulsing = 0, 0, 0, false
end

-- QuestBank's data, read again: the places' yards, the list and its groups
function Mini.Invalidate() worldOf, cache.list, grp.list = {}, nil, nil end


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
