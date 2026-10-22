-- SPDX-License-Identifier: GPL-3.0-or-later
-- Route: the quest window's second tab, always there (the base). The band: where the route takes you ("Level 21.6 to
-- 22.1, 11,300 XP, 43 min") over the XP bar, each stop's gain its own green segment, and the run's button. On the left
-- the route's map (340 x 226, at a zoom framing the stops of the target's zone): the zone's own art (C_Map's layer
-- tiles, as the game's map canvas lays them, Blizzard_MapCanvasDetailLayer.lua:50-70), the stops at the game's pin size,
-- merged with a count where they would touch, the one stroke from you to the target, you as the game's arrow; hovering
-- a stop lights its pin. On the right the stops as a timeline (Cute.Look's pattern B): the first is the one target (its
-- ring and its light); each stop's minutes and yards, the way when it is not on foot, its name, the XP it pays and the
-- level after it, the quests it takes; a 1 px white rule where the route crosses a level. A stop's click shows it on the
-- arrow; a quest's reads it. Its section has the route's own rows and the minimap's (they belong to the base, not to
-- the Map module: a player who keeps the game's map keeps them).
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local R = {}
local MAP_W, MAP_H, PIN = 340, 226, 22
local DOT = " \194\183 "
local function redraw() Cute.Refresh() end
local function plain(v) if issecretvalue and issecretvalue(v) then return nil end return v end
local WAY = { flight = { "flight", "flight" }, boat = { "boat", "boat" }, zeppelin = { "zeppelin", "zeppelin" }, tram = { "tram", "tram" },
  portal = { "portal", "portal" }, hearth = { "hearth", "hearthstone" } }

-- (the launch audit) a portal leg's start, as the arrow's step says it (Travel.lua STEP.portal: "Portal in <here> to
-- <there>"; 6.1.1, "portal to Darnassus" read as the mage spell Portal: Darnassus): of D.LINK's portals (kind "p", your
-- side's), the end nearest the stop the leg takes you to is where you come out, and the other one's town is where the
-- portal stands ("Rut'theran Village" for a stop in Darnassus). nil where none is known
local function portalFrom(stop)
  local M, D = E.Model, E.Data
  local w = M and M.World and stop and stop.m and M.World(stop.m, stop.x, stop.y)
  if not (w and D and type(D.LINK) == "table") then return nil end
  local fac = E.faction or "A"
  local best, bd
  for _, l in ipairs(D.LINK) do
    local a, b = l[4], l[5]
    if l[2] == "p" and type(l[1]) == "string" and l[1]:find(fac, 1, true) and type(a) == "table" and type(b) == "table" then
      for _, ends in ipairs({ { a, b }, { b, a } }) do
        local near, far = ends[1], ends[2]
        if near[1] == w.c and type(near[2]) == "number" and type(near[3]) == "number" then
          local d = (near[2] - w.wx) ^ 2 + (near[3] - w.wy) ^ 2
          if not bd or d < bd then best, bd = far[7], d end
        end
      end
    end
  end
  return type(best) == "string" and best or nil
end

-- a stop in words: its NPC where it has one alone, and where it is as the map's pins name it (TV.StopPlace:
-- "Smith Argus, Goldshire"; never Model.lua's "Elwynn Forest (42, 65)", kept for matching); the place alone otherwise
local function stopName(stop)
  local TV = E.Travel
  local place = (TV and TV.StopPlace and TV.StopPlace(stop)) or stop.name or "?"
  local one = stop.npcs and #stop.npcs == 1 and E.Data.NPC[stop.npcs[1]]
  if one and one[1] and one[1] ~= place then return one[1] .. ", " .. place, place end
  return place, place
end
-- yards between two stops (their spots on their maps, in the continent's yards), nil across continents
local function yardsBetween(a, b)
  local M = E.Model
  if not (M and M.World and a and b and a.m and b.m) then return nil end
  local wa, wb = M.World(a.m, a.x, a.y), M.World(b.m, b.x, b.y)
  if not (wa and wb and wa.c == wb.c) then return nil end
  return math.sqrt((wa.wx - wb.wx) ^ 2 + (wa.wy - wb.wy) ^ 2)
end
local function yardsFromYou(stop)
  local M = E.Model
  local me = E.API and E.API.WorldPosition and E.API.WorldPosition()
  local w = M and M.World and stop.m and M.World(stop.m, stop.x, stop.y)
  if not (me and w and me.c == w.c) then return nil end
  return math.sqrt((w.wx - me.wx) ^ 2 + (w.wy - me.wy) ^ 2)
end
-- a quest on a stop: its glyph (ready: the hand-in; held: its first open objective's cursor; to take: the offer's !),
-- its name, its progress, its XP or "take"; its click reads it
local function questLine(ui, q, xp, take)
  local e = E.state.log[q.id]
  local glyph, prog
  if e and e.complete then glyph = { poi = "ready" }
  elseif e then
    for slot, o in ipairs(e.objectives or {}) do
      if plain(o.done) ~= true then
        local text = plain(o.text)
        local name, have, need
        if E.Guide.ParseLine then name, have, need = E.Guide.ParseLine(text) else name = text end
        glyph = { art = QB.ObjKind(q.id, slot, text) }
        prog = (have and need) and string.format("%s %d/%d", name or "", have, need) or name
        break
      end
    end
    glyph = glyph or { poi = "log" }
  else glyph = { art = q.repeatable and "repeatable" or "accept" } end
  return { glyph = glyph, name = q.name, prog = prog, right = take and "take" or (xp and xp > 0 and E.Comma(xp)) or nil,
    fn = function(_, which)
      if which == "RightButton" then E.UI.QuestClick(q, E:Status(q), "RightButton") return end
      QB.Reader.Read(ui, q)
    end,
    tip = function(tip) E.UI.QuestTooltip(tip, q, E:Status(q), xp) end }
end

-- the route's map in a box: the target's zone, framed on its stops and you
local function mapOf(box)
  local L, K = Cute.Look, Cute.Look and Cute.Look.ART
  local m = box.map
  if m then return m end
  m = CreateFrame("Frame", nil, box, BackdropTemplateMixin and "BackdropTemplate" or nil)
  m:SetSize(MAP_W, MAP_H)
  m:SetPoint("TOPLEFT", 0, 0)
  if m.SetClipsChildren then m:SetClipsChildren(true) end
  m.ground = m:CreateTexture(nil, "BACKGROUND", nil, -8)
  m.ground:SetAllPoints()
  m.ground:SetColorTexture(0.08, 0.09, 0.09, 1)
  m.tiles, m.pins = {}, {}
  m.under = m:CreateLine(nil, "ARTWORK")
  m.under:SetThickness(4)
  m.under:SetColorTexture(0, 0, 0, 0.6)
  m.stroke = m:CreateLine(nil, "OVERLAY")
  m.stroke:SetThickness(2)
  m.stroke:SetColorTexture(0.96, 0.96, 0.96, 1)
  m.me = m:CreateTexture(nil, "OVERLAY", nil, 2)
  m.me:SetSize(26, 26)
  m.me:SetTexture(803894) -- (the game's player arrow, WorldMapArrow)
  m.edge = CreateFrame("Frame", nil, box, BackdropTemplateMixin and "BackdropTemplate" or nil)
  m.edge:SetAllPoints(m)
  if m.edge.SetBackdrop then
    m.edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    m.edge:SetBackdropBorderColor(0, 0, 0, 1)
  end
  box.map = m
  return m
end
local function pinOf(m, i)
  local p = m.pins[i]
  if p then return p end
  local L = Cute.Look
  p = CreateFrame("Button", nil, m)
  p:SetSize(PIN, PIN)
  p.slot = L.MakeSlot(p, PIN)
  p.slot:SetAllPoints()
  p.glow = p:CreateTexture(nil, "BACKGROUND")
  p.glow:SetPoint("CENTER")
  p.glow:SetSize(PIN + 10, PIN + 10)
  p.glow:SetTexture(136430) -- (the minimap button's ring, MiniMap-TrackingBorder, as a light round the pin)
  p.glow:SetVertexColor(1, 1, 1, 0.9)
  p.glow:Hide()
  p:SetScript("OnEnter", Cute.Safe(function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    for _, n in ipairs(self.names or {}) do GameTooltip:AddLine(n, 1, 1, 1) end
    GameTooltip:AddLine("Click: show it on the arrow.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
  end, "route: a pin"))
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  p:SetScript("OnClick", Cute.Safe(function(self) if self.fn then self.fn() end end, "route: a pin"))
  m.pins[i] = p
  return p
end
-- the map drawn: returns the pins by stop, so a stop's hover can light its own
local function drawMap(box, legs)
  local L = Cute.Look
  local m = mapOf(box)
  local first = legs[1] and legs[1].stop
  local zone = first and first.m
  local byStop = {}
  for _, t in ipairs(m.tiles) do t:Hide() end
  for _, p in ipairs(m.pins) do p:Hide() end
  m.under:Hide(); m.stroke:Hide(); m.me:Hide()
  if not zone then return byStop end
  -- the points: the stops on the zone's map (percent), and you on it (C_Map.GetPlayerMapPosition, a fraction)
  local pts = {}
  for i, leg in ipairs(legs) do
    local s = leg.stop
    if s.m == zone and s.x and s.y then pts[#pts + 1] = { x = s.x / 100, y = s.y / 100, i = i, leg = leg } end
  end
  local you
  if C_Map and C_Map.GetPlayerMapPosition then
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, zone, "player")
    pos = ok and plain(pos) or nil
    local px, py
    if pos and pos.GetXY then px, py = pos:GetXY() end
    px, py = plain(px), plain(py)
    if type(px) == "number" and type(py) == "number" and px > 0 and py > 0 then you = { x = px, y = py } end
  end
  local x0, x1, y0, y1 = 1, 0, 1, 0
  local function take(p) x0, x1, y0, y1 = math.min(x0, p.x), math.max(x1, p.x), math.min(y0, p.y), math.max(y1, p.y) end
  for _, p in ipairs(pts) do take(p) end
  if you then take(you) end
  if x1 < x0 then return byStop end
  -- the zone's art layer (its size in pixels and its tiles); a client that cannot say: the frame's own shape
  local W, H, tw, th, tex = 1002, 668, 256, 256, nil
  if C_Map and C_Map.GetMapArtLayers then
    local ok, layers = pcall(C_Map.GetMapArtLayers, zone)
    local li = ok and type(layers) == "table" and layers[1]
    if type(li) == "table" and type(li.layerWidth) == "number" then W, H, tw, th = li.layerWidth, li.layerHeight, li.tileWidth, li.tileHeight end
    local ok2, t = pcall(C_Map.GetMapArtLayerTextures, zone, 1)
    if ok2 and type(t) == "table" then tex = t end
  end
  -- framed on them with a margin, a quarter of the zone at least, to the box's shape, kept inside the zone
  local pad = 0.06
  x0, x1, y0, y1 = x0 - pad, x1 + pad, y0 - pad, y1 + pad
  local function grow(a, b, span) local mid = (a + b) / 2; return mid - span / 2, mid + span / 2 end
  if x1 - x0 < 0.25 then x0, x1 = grow(x0, x1, 0.25) end
  if y1 - y0 < 0.25 then y0, y1 = grow(y0, y1, 0.25) end
  local want = MAP_W / MAP_H
  if (x1 - x0) * W / ((y1 - y0) * H) > want then y0, y1 = grow(y0, y1, (x1 - x0) * W / want / H)
  else x0, x1 = grow(x0, x1, (y1 - y0) * H * want / W) end
  local function inside(a, b) local span = b - a; if span >= 1 then return (1 - span) / 2, (1 + span) / 2 end; if a < 0 then return 0, span end; if b > 1 then return 1 - span, 1 end; return a, b end
  x0, x1 = inside(x0, x1)
  y0, y1 = inside(y0, y1)
  local sc = MAP_W / ((x1 - x0) * W)
  local function at(fx, fy) return (fx - x0) * W * sc, (fy - y0) * H * sc end
  -- the tiles in view
  if tex then
    local cols, rows = math.ceil(W / tw), math.ceil(H / th)
    local n = 0
    for row = 1, rows do
      for col = 1, cols do
        local lx, ly = ((col - 1) * tw / W - x0) * W * sc, ((row - 1) * th / H - y0) * H * sc
        local sw, sh = tw * sc, th * sc
        if lx < MAP_W and lx + sw > 0 and ly < MAP_H and ly + sh > 0 and tex[(row - 1) * cols + col] then
          -- (the tile's part in view, cut by its corners: nothing drawn past the map's edge)
          local cl, cr = math.max(0, -lx), math.max(0, lx + sw - MAP_W)
          local ct, cb = math.max(0, -ly), math.max(0, ly + sh - MAP_H)
          n = n + 1
          local t = m.tiles[n]
          if not t then t = m:CreateTexture(nil, "BACKGROUND", nil, -6); m.tiles[n] = t end
          t:SetTexture(tex[(row - 1) * cols + col])
          t:SetTexCoord(cl / sw, 1 - cr / sw, ct / sh, 1 - cb / sh)
          t:ClearAllPoints(); t:SetPoint("TOPLEFT", lx + cl, -(ly + ct)); t:SetSize(sw - cl - cr, sh - ct - cb)
          t:Show()
        end
      end
    end
  end
  -- the pins, merged where they would touch (the hand-in's glyph first, then in progress, then the offer), a count on
  -- the merged one
  local groups = {}
  for _, p in ipairs(pts) do
    local px, py = at(p.x, p.y)
    local g
    for _, x in ipairs(groups) do if (x.px - px) ^ 2 + (x.py - py) ^ 2 < PIN * PIN then g = x break end end
    if not g then g = { px = px, py = py, items = {} }; groups[#groups + 1] = g end
    g.items[#g.items + 1] = p
  end
  for gi, g in ipairs(groups) do
    local pin = pinOf(m, gi)
    local ready, target = true, false
    local names = {}
    for _, p in ipairs(g.items) do
      for _, row in ipairs(p.leg.rows or {}) do local e = E.state.log[row.q.id]; if not (e and e.complete) then ready = false end end
      if p.i == 1 then target = true end
      names[#names + 1] = (stopName(p.leg.stop))
      byStop[p.i] = pin
    end
    pin.names = names
    pin:ClearAllPoints(); pin:SetPoint("CENTER", m, "TOPLEFT", g.px, -g.py)
    L.FillSlot(pin.slot, { poi = ready and "ready" or "log", n = #g.items > 1 and #g.items or nil })
    pin:SetFrameLevel(m:GetFrameLevel() + (target and 5 or 3))
    local s1 = g.items[1].leg.stop
    pin.fn = function() if E.API and E.API.SetWaypoint then E.API.SetWaypoint(s1.m, s1.x, s1.y, (stopName(s1))) end end
    pin:Show()
  end
  -- the one stroke, from you to the target; you as the game's arrow, turned your way
  if you and pts[1] and pts[1].i == 1 then
    local ax, ay = at(you.x, you.y)
    local bx, by = at(pts[1].x, pts[1].y)
    for _, line in ipairs({ m.under, m.stroke }) do
      line:SetStartPoint("TOPLEFT", m, ax, -ay)
      line:SetEndPoint("TOPLEFT", m, bx, -by)
      line:Show()
    end
  end
  if you then
    local ax, ay = at(you.x, you.y)
    m.me:ClearAllPoints(); m.me:SetPoint("CENTER", m, "TOPLEFT", ax, -ay)
    local face = GetPlayerFacing and plain(GetPlayerFacing()) or nil
    if type(face) == "number" and m.me.SetRotation then m.me:SetRotation(face) end
    m.me:Show()
  end
  return byStop
end

function R.Draw(ui, scroll)
  if not E then return QB.NeedPage(ui, scroll, "route") end
  QB.Reader.Left(ui)
  if QB.Reader.Open(ui) then return QB.Reader.Draw(ui, scroll) end
  local K, L = ui.COLORS, ui.Look
  local r = (E.Target and E.Target.Route()) or E.routeNow or { legs = {} }
  local legs = r.legs or {}
  local run = E.Run and E.Run.Get()
  -- the band: where the route takes you over the XP bar, each stop's gain its own segment; the run's button
  local kit = ui:Kit("route", function(k)
    k.line = ui.Text(k, 12, K.INK, "LEFT")
    k.xp = L.MakeXP(k)
    k.run = ui.Button(k, "Start run", 110, 20)
    k.rule = L.Flat(k, "ARTWORK", K.LINE, 1)
    k.rule:SetHeight(1)
  end)
  local bw = (ui.band:GetWidth() or 0)
  if bw < 100 then bw = scroll:Width() end
  local xp = Cute.QuestBand and Cute.QuestBand.XP and Cute.QuestBand.XP(true) or { level = E.state.level or 1 }
  local words
  if #legs == 0 then words = "Nothing on the route yet."
  else
    local last = legs[#legs].leave
    words = string.format("Level %.1f to %.1f%s%s XP%s%d min", xp.at or xp.level, type(last) == "number" and last or (xp.after or xp.level), DOT,
      E.Comma(r.xp or 0), DOT, math.floor((r.t or 0) + 0.5)) .. ((E.Model and E.Model.Busy()) and (DOT .. "planning") or "")
  end
  L.Put(kit.line, "TOPLEFT", 0, -6, bw - 130, words, K.INK, "LEFT", 12)
  kit.run:ClearAllPoints(); kit.run:SetPoint("TOPRIGHT", 0, -2)
  kit.run:SetLabel(run and "End run" or "Start run")
  kit.run:SetOn(E.Run ~= nil)
  kit.run:SetScript("OnClick", Cute.Safe(function() if E.Run.Get() then E.Run.Stop() else E:Recompute(true); E.Run.Start() end; redraw() end, "route: run"))
  if xp.from then
    kit.xp:ClearAllPoints(); kit.xp:SetPoint("TOPLEFT", 0, -28); kit.xp:Show()
    L.FillXP(kit.xp, bw, xp.from, xp.to, xp.at, xp.gains)
  else kit.xp:Hide() end
  kit.rule:ClearAllPoints(); kit.rule:SetPoint("TOPLEFT", 0, -42); kit.rule:SetPoint("TOPRIGHT", 0, -42)
  kit:SetHeight(43)
  ui:SetBand(46)
  -- the map on the left, under it a bigger one: "Open in the map", Cute's map (M) on the route's first stop while the Map
  -- module is on (the windows design; M is no panel, so it opens in a fight too: MapWin.lua MW.OpenOn); with Map off
  -- (or QuestBank loaded beside Cute, whose own Map page is its map) "Open the map", the game's world map
  local box = Cute.LeftBox(ui, MAP_W)
  local pins = drawMap(box, legs)
  local inM = not QB.dormant and Cute.ModuleOn("map") and QB.MapWin ~= nil and QB.MapWin.OpenOn ~= nil
  local label = inM and "Open in the map" or "Open the map"
  box.open = box.open or ui.Button(box, label, 140, 22)
  box.open:ClearAllPoints(); box.open:SetPoint("TOPLEFT", 0, -(MAP_H + 8))
  box.open:SetLabel(label)
  box.open:SetOn(true)
  local first = legs[1] and legs[1].stop
  -- (the game's map is UIParent's MEDIUM but for its border, Blizzard_WorldMap.xml:67-85, under Cute's HIGH window: L
  -- steps aside once the map is open; M is one of Cute's windows, raised over L)
  box.open:SetScript("OnClick", Cute.Safe(function()
    if inM then QB.MapWin.OpenOn(first and first.m) return end
    if E.UI and E.UI.OpenMap and E.UI.OpenMap() and ui.frame then ui.frame:Hide() end
  end, "route: the map"))
  -- the stops
  local w = scroll:Width()
  local host = Cute.Host(ui, "route")
  host:ClearAllPoints(); host:SetPoint("TOPLEFT", 0, 0)
  host.stops = host.stops or ui.Pool(host, function(parent) return L.MakeStop(parent) end)
  host.rules = host.rules or ui.Pool(host, function(parent) return L.MakeRule(parent) end)
  host.notes = host.notes or ui.Pool(host, function(parent) return L.MakeRow(parent) end)
  host.stops:Reset(); host.rules:Reset(); host.notes:Reset()
  local y = 0
  if #legs == 0 then
    local n = host.notes:Get()
    n:ClearAllPoints(); n:SetPoint("TOPLEFT", 0, 0)
    y = L.FillRow(n, { kind = "note", x = 10, name = "Nothing on the route yet: take a quest from Quests." }, w)
  end
  -- the pick-ups the plan folds into a stop (Pins.lua's list: a stop's pickups)
  local pickups = {}
  for _, d in ipairs((E.Pins and E.Pins.list) or {}) do if d.stop and d.pickups then pickups[d.stop] = d.pickups end end
  local prevStop, prevLeave = nil, xp.at
  for i, leg in ipairs(legs) do
    local s = leg.stop
    local name, place = stopName(s)
    local mins = math.floor((leg.travel or 0) + 0.5)
    local yd = i == 1 and yardsFromYou(s) or yardsBetween(prevStop, s)
    local line1 = (i == 1 and mins < 1) and "now" or ("+" .. math.max(1, mins) .. " min")
    if yd and yd >= 20 then line1 = line1 .. DOT .. E.Comma(math.floor(yd / 10 + 0.5) * 10) .. " yd" end
    local way
    local wk = WAY[leg.kind]
    if wk then
      local art = wk[1]
      if art == "flight" then art = (E.faction == "H") and "wyvern" or "gryphon" end
      local words = string.format("%s to %s, %d min", wk[2], place, math.max(1, mins))
      if leg.kind == "portal" then
        local from = portalFrom(s)
        words = from and string.format("Portal in %s to %s, %d min", from, place, math.max(1, mins))
          or string.format("Through the portal to %s, %d min", place, math.max(1, mins))
      end
      way = { { art = art, crop = true }, words }
    end
    local qs, gain = {}, 0
    for _, row in ipairs(leg.rows or {}) do
      gain = gain + (row.xp or 0)
      qs[#qs + 1] = questLine(ui, row.q, row.xp, false)
    end
    for _, q in ipairs(pickups[s] or {}) do qs[#qs + 1] = questLine(ui, q, nil, true) end
    local ready = true
    for _, row in ipairs(leg.rows or {}) do local e = E.state.log[row.q.id]; if not (e and e.complete) then ready = false end end
    local node = leg.kind == "hearth" and { art = "hearth", crop = true } or ((#(leg.rows or {}) == 0) and { art = "accept" }) or { poi = ready and "ready" or "log" }
    local pin = pins[i]
    local st = host.stops:Get()
    st:ClearAllPoints(); st:SetPoint("TOPLEFT", 0, -y)
    y = y + L.FillStop(st, {
      node = node, target = i == 1, ring = QB.ART .. "ring_frame", line1 = line1, way = way, name = name,
      xp = gain > 0 and ("+" .. E.Comma(gain) .. " XP") or nil, lvl = type(leg.leave) == "number" and string.format("%.1f", leg.leave) or nil,
      quests = qs, first = i == 1, last = i == #legs,
      fn = function() if E.API and E.API.SetWaypoint then E.API.SetWaypoint(s.m, s.x, s.y, name) end end,
      hover = pin and function(on) pin.glow:SetShown(on) end or nil,
      tip = function(tip)
        tip:AddLine((E.Pins and E.Pins.StopTitle and E.Pins.StopTitle(s)) or place, 1, 1, 1)
        for _, row in ipairs(leg.rows or {}) do tip:AddDoubleLine(row.q.name, E.Comma(row.xp or 0) .. " XP", 0.85, 0.85, 0.85, 0.6, 0.6, 0.6) end
        tip:AddLine("Click: show it on the arrow. A quest's line: read it.", 0.45, 0.45, 0.45, true)
      end,
    }, w)
    -- the level-up: a white rule after the stop where the route's XP crosses a level
    local leave = leg.leave
    if type(leave) == "number" and type(prevLeave) == "number" and math.floor(leave) > math.floor(prevLeave) then
      local rl = host.rules:Get()
      rl:ClearAllPoints(); rl:SetPoint("TOPLEFT", 0, -y)
      y = y + L.FillRule(rl, w, "Level " .. math.floor(leave))
    end
    prevStop, prevLeave = s, type(leave) == "number" and leave or prevLeave
  end
  host.stops:HideRest(); host.rules:HideRest(); host.notes:HideRest()
  host:SetSize(w, math.max(1, y))
  scroll:SetContentHeight(y + 10)
end

function R.Settings(_, col)
  if not E then return QB.NeedSettings(col, "Route") end
  local s = E:Settings()
  col:Head("Route")
  col:Choice("Follow", { "The plan", "Ready now" }, s.routeQuest == "now" and "Ready now" or "The plan", function(v) s.routeQuest = v == "Ready now" and "now" or nil; E:MarkDirty() end)
  col:Check("Show the way step by step on the arrow", s.arrowTravel ~= false, true, function(on) s.arrowTravel = on; if E.Arrow and E.Arrow.Invalidate then E.Arrow.Invalidate() end end)
  col:Check("The hearthstone may be a step", s.arrowHearth ~= false, true, function(on) s.arrowHearth = on; if E.Arrow and E.Arrow.Invalidate then E.Arrow.Invalidate() end end)
  -- the minimap's (Minimap.lua, MinimapView.lua): the route, one stroke unless the whole route is asked (6.1.1), the ! of
  -- the quests you can take, the far view
  local function mini() if E.Mini and E.Mini.Invalidate then E.Mini.Invalidate() end end
  col:Check("Route on the minimap", s.minimapPins ~= false and s.minimapLines ~= false, true, function(on) s.minimapPins, s.minimapLines = on, on; mini() end)
  col:Check("Show the whole route", s.wholeRoute == true, true, function(on) s.wholeRoute = on; mini() end)
  col:Note("Off, one stroke: from you to where the arrow leads.")
  col:Check("A ! on the minimap for quests you can take", s.minimapGivers == true, true, function(on) s.minimapGivers = on; mini() end)
  col:Check("Minimap far view", s.mmExtended == true, true, function(on) s.mmExtended = on; mini() end)
end

Cute:RegisterModule({
  id = "route", addon = ADDON, title = "Route", order = 22, window = "quests", base = true,
  notes = "The route's stops on its map and in order, what each pays and where you level; the first is where the arrow points.",
  page = R.Draw, settings = R.Settings,
  events = { QUEST_LOG_UPDATE = redraw, QUEST_TURNED_IN = redraw, ZONE_CHANGED_NEW_AREA = redraw },
})
