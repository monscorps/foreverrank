-- SPDX-License-Identifier: GPL-3.0-or-later AND MIT
-- Contains code from QuestTrail 3.0.6, Copyright (c) 2026 Krom, MIT licence (LICENSE-QuestTrail.txt): QuestTrail_Pins.lua: Colors, ColorFor, AssignRouteColors, WeightScale, ByWeight, MergeOverlaps, Item, StylePin, SizePin, ShowQuestTooltip, RebuildMinimapCache, GroupMinimap, UpdateMinimap, the selected quest's pulse; QuestTrail_ZoneMap.lua: ZoneMapDot; QuestTrail_Dungeons.lua: UpdateMinimap
-- The route on the minimap: a step circle for every stop of the hand-in route, a stroke from you to the next place
-- and from stop to stop (MinimapRoute.lua), the NPCs who take your finished quests, your pick-up list, the objectives
-- of the quests in your log, and the entrances of the dungeons around you, ticked once their quests are all done.
-- While the arrow sends you by a flight master, a pier or the tram first, that is pinned too, and the stroke goes
-- there. Drawn as QuestTrail draws them (Krom's art, art/*.png; the Marker style setting, "questtrail"): an objective
-- is a diamond in its quest's colour under a gold frame, with a glyph for the work (a skull to kill, a cog to use or
-- click, a banner for a place to reach, a bag for the mob that drops the item to use; the plain disc for loot), an
-- elite quest's under a dragon-claw ring; the ! and ? are the game's; a stop is a disc in its quest's colour under a
-- gold ring with the ? (or !) inside, two stops at one place one bigger circle; the strokes take the colours too. Each
-- quest gets a colour of QuestTrail's palette in the route's order, kept per character. "game" draws the game's own
-- numbered pins and cursor icons instead. Placed QuestTrail's way: out of reach, the stops, the step and the hand-ins
-- sit on the rim, dimmer, in the direction they lie, and the rest fade out over their last width before it; one
-- quest's objectives close together on the ground are one pin, a little bigger; each place keeps its pin while the
-- view moves. Click a pin: a waypoint there, as on the world map; right-click it: the minimap's menu. Alt-drag moves
-- the minimap, Ctrl-wheel sizes it, the wheel zooms it: the game's own levels, then further out over the game's
-- minimap tiles, and a drag pans that far view (MinimapView.lua). Everything here is QuestBank's own frames laid over
-- the Minimap; of the game's only its release script is wrapped (MinimapView.lua), and the minimap itself is only
-- scaled, moved and zoomed, never in a fight. (QuestBank's Map is the game's world map: UI.OpenMap.)
--   where a pin is: the stop's map and position go through QB.Model.World to continent yards, as the arrow's do, and
--   then through the minimap's view (MV.View: its centre, its radius in yards from C_Minimap.GetViewRadius or the far
--   zoom, its turn with your facing under rotateMinimap).
local _, QB = ...
if QB.dormant then return end
local Mini = {}
QB.Mini = Mini

local TICK = 0.05          -- seconds between placements (the pins follow you); every frame while the view moves
local ART = QB.ART or "Interface\\AddOns\\QuestBank\\art\\" -- (a host holding a copy of the engine names its own folder: QB.ART)
local MAX_PINS = 60        -- pins at once: the step and the stops first, then the nearest
local EDGE = 7             -- the rim: pins kept on it sit this far inside the minimap's edge
local LIST_EVERY = 30      -- seconds the list is kept at most, a safety net: it is made again at once when
                           -- QuestBank's data (QB:Changed), the route's pins, your quest log or a switch changes.
                           -- (Every 0.5 s before 5.4.2, the same list again nearly every time: 30 KB of garbage each)
Mini.TICK, Mini.MAX_PINS = TICK, MAX_PINS
local RANK = { step = 0, stop = 1, turn = 1 }
local PINNED = { step = true, stop = true, turn = true } -- out of reach: on the rim, the way to go
-- the game-icon style's sizes; QuestTrail's come from the marker size setting (Mini.Sizes)
local SIZE_GAME = { stop = 22, step = 18, dungeon = 18, obj = 16, pickup = 16, turn = 16, give = 16 }
local SIZE = {}
local GOLD, BLUE = { 1, 0.84, 0.18 }, { 0.4, 0.55, 1 } -- the game style's strokes: you to the target, stop to stop
Mini.GOLD, Mini.BLUE = GOLD, BLUE -- (the Map page's strokes, MapPage.lua)
-- QuestTrail's colours: one of the palette per quest, the picked quest's blue, the single colour, the way to a flight
-- master or a pier
local PALETTE = {
  { 1, 0.55, 0.1 }, { 0.2, 0.8, 1 }, { 0.6, 1, 0.2 }, { 1, 0.3, 0.6 }, { 0.75, 0.5, 1 },
  { 1, 0.9, 0.2 }, { 0.2, 1, 0.75 }, { 1, 0.4, 0.3 }, { 0.35, 0.5, 1 }, { 0.85, 0.7, 0.45 },
}
local SELECTED, SINGLE, TRAVEL = { 0.3, 0.55, 1 }, { 1, 0.82, 0 }, { 0.4, 0.8, 1 }
Mini.PALETTE, Mini.SELECTED, Mini.SINGLE, Mini.TRAVEL = PALETTE, SELECTED, SINGLE, TRAVEL
local ELITE_RING = 1.5           -- the elite ring's width, as the marker's times this
local DOT_SCALE = 32 / 26.5      -- the step circle's images hold its shadow: drawn that much larger than the circle
local DOT_ALPHA = 0.5            -- the circles fade less than the strokes (the marker in them stays readable)
local DUNGEON_SIZE = 1.3         -- a dungeon's portal, as the marker's size times this
local DUNGEON_ICON = "Interface\\Minimap\\Dungeon_Icon"
-- the glyph of an objective's marker, by the kind of work (QuestMap.lua's spot kinds): kill, use or click, buy, an
-- object to collect (loot from mobs is the plain disc), a place to reach, the mob that drops the item that starts a
-- quest; fishing, skinning and the like the plain disc
local GLYPH = { k = "glyph_kill", u = "glyph_use", b = "glyph_use", c = "glyph_use", e = "glyph_area", s = "glyph_usedrop" }
Mini.GLYPH = GLYPH

local plain = QB.Plain
local sqrt, floor, cos, pi, max, min = math.sqrt, math.floor, math.cos, math.pi, math.max, math.min
local pins, worldOf, pinOf = {}, {}, {}

local function on() return QB:Settings().minimapPins ~= false end
-- QuestTrail's look (the default), or the game's own icons
function Mini.QT() return QB:Settings().markerStyle ~= "game" end

-- the sizes of this placing, in pixels: QuestTrail's marker size (mmRing, 8 to 40) for the objectives and the step
-- circles, and times the glyph size (mmGlyphPct) for the ! and ?; the game style's fixed ones
local function even(v) return max(floor(v / 2 + 0.5) * 2, 8) end
function Mini.Sizes()
  local s = QB:Settings()
  if not Mini.QT() then
    for k, v in pairs(SIZE_GAME) do SIZE[k] = v end
    SIZE.ring, SIZE.glyph = 18, 16
    return SIZE
  end
  local ring = max(8, min(40, tonumber(s.mmRing) or 18))
  local glyph = max(4, floor(ring * (tonumber(s.mmGlyphPct) or 100) / 100 / 2 + 0.5) * 2)
  SIZE.stop, SIZE.step, SIZE.dungeon, SIZE.obj, SIZE.pickup, SIZE.turn, SIZE.give = ring, glyph, ring * DUNGEON_SIZE, ring, glyph, glyph, glyph
  SIZE.ring, SIZE.glyph = ring, glyph
  return SIZE
end

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

----------------------------------------------------------------------------
-- A quest's colour, the same on its markers, its stroke, its step circle and the arrow's dial: QuestTrail's. The
-- colours are handed out in the order of the route: each quest that enters it gets the next colour of the palette
-- (cycling, never the colour of the step just before it), and keeps it. Kept per character:
-- QuestBankDB.chars[key].colors = { next = palette index, q = { [key] = index } }; a hand-in (key -id) gets a colour
-- of its own when the route reaches it (a route going to do a quest, then to hand it in, drew two strokes of one
-- colour in a row). A quest the route never had: a colour from its id. One colour for all: the mmColor setting
----------------------------------------------------------------------------
local function colorDB()
  if not QuestBankDB then return nil end
  QuestBankDB.chars = QuestBankDB.chars or {}
  local key = QB:CharKey()
  local ch = QuestBankDB.chars[key]
  if type(ch) ~= "table" then ch = {}; QuestBankDB.chars[key] = ch end
  if type(ch.colors) ~= "table" then ch.colors = { next = 0, q = {} } end
  return ch.colors
end
Mini.colorGen = 0
function Mini.ColorFor(id, kind)
  local s = QB:Settings()
  if s.mmColor == "single" then return type(s.oneColor) == "table" and s.oneColor or SINGLE end
  local db = colorDB()
  local idx = db and kind == "finish" and type(id) == "number" and db.q[-id]
  idx = idx or (db and db.q[id]) or (type(id) == "number" and id) or 0
  return PALETTE[(idx % #PALETTE) + 1]
end
-- the keys of a new route in its order (-id: a hand-in; id: a quest to do or take): those with no colour yet get theirs
function Mini.AssignColors(keys)
  local db = colorDB()
  if not db then return end
  local n, prev, changed = #PALETTE, nil, false
  for _, q in ipairs(keys) do
    if type(q) == "number" and q ~= 0 then
      local idx = db.q[q]
      if not idx then
        idx = db.next % n
        if idx == prev then idx = (idx + 1) % n end
        db.q[q], db.next, changed = idx, idx + 1, true
      end
      prev = idx
    end
  end
  if changed then Mini.colorGen = Mini.colorGen + 1 end
end
-- a pin's colour: its quest's, a hand-in's own; the way to a flight master or a pier is blue
local function colourOf(d)
  if d.kind == "obj" then return Mini.ColorFor(d.id, "progress") end
  if d.kind == "turn" then return Mini.ColorFor(d.id, "finish") end
  if d.kind == "stop" then return Mini.ColorFor(d.cid, d.num and "finish" or "start") end
  if d.kind == "pickup" then return Mini.ColorFor(d.qid, "start") end
  return TRAVEL
end
Mini.ColourOf = colourOf

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

-- what a minimap pin's click was for (Arrow.lua's A:Show ends on it): a stop's quests in your log, a hand-in's or an
-- objective's quest, a pick-up's giver
function Mini.About(d)
  if d.kind == "stop" then
    local ids, n = {}, 0
    for id in pairs(d.ids or {}) do if type(id) == "number" and QB.state.log[id] then ids[id], n = true, n + 1 end end
    return n > 0 and { ids = ids } or nil
  elseif d.kind == "turn" and d.id then return { qid = d.id, what = "turn" }
  elseif d.kind == "obj" and d.id then return { qid = d.id, what = "obj" }
  elseif d.kind == "pickup" and d.qid then return { qid = d.qid, what = "give" }
  elseif d.kind == "give" and d.ids and d.ids[1] then return { qid = d.ids[1], what = "give" } end
  return nil
end

-- the first (lowest) quest id of a stop: the colour its circle and its stroke take
local function firstId(ids)
  local best
  for id in pairs(ids or {}) do if type(id) == "number" and (not best or id < best) then best = id end end
  return best
end

-- what goes on the minimap: the arrow's step toward the one target (a flight master, a pier; left out with noStep), the
-- route's stops, the pick-up list, the hand-ins of your finished quests, a ! for every quest you can take now (6.0),
-- the objectives of the others still to do (MAX_SPOTS of them, the nearest first), the dungeon entrances of your
-- continent; and the quests' colours, handed out in that order
local MAX_SPOTS = 120
local function nearFirst(a, b)
  if a.far ~= b.far then return a.far < b.far end
  if a.id ~= b.id then return a.id < b.id end
  if a.x ~= b.x then return a.x < b.x end
  return a.y < b.y
end
function Mini.List(noStep)
  local out, keys = {}, {}
  local step = not noStep and QB.Target and QB.Target.Step()
  if step then out[1] = step end
  local P = QB.Pins
  local stopAt = {}
  if P and P.list then
    for _, d in ipairs(P.list) do
      if d.m and d.m > 0 then
        local cid = firstId(d.ids)
        out[#out + 1] = { m = d.m, x = d.x, y = d.y, name = d.name, num = d.num, kind = "stop", when = d.when, lines = d.lines, late = d.late,
                          cid = cid, ids = d.ids }
        stopAt[keyOf(d)] = true
        local sorted = {}
        for id in pairs(d.ids or {}) do if type(id) == "number" then sorted[#sorted + 1] = id end end
        table.sort(sorted)
        for _, id in ipairs(sorted) do keys[#keys + 1] = d.num and -id or id end
      end
    end
  end
  if QB:Settings().minimapPickups ~= false and QB.Arrow and QB.Arrow.ListFor then
    for _, d in ipairs(QB.Arrow.ListFor("pickup") or {}) do
      if d.m and d.m > 0 then
        out[#out + 1] = { m = d.m, x = d.x, y = d.y, name = d.name, kind = "pickup", qid = d.qid, escort = d.escort }
        keys[#keys + 1] = d.qid
      end
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
      keys[#keys + 1] = -e.id
    end
  end
  -- a ! for every quest you can take now on your map (6.0; the world map's own filter, QuestMap.GiversNear): givers
  -- within GIVER_MERGE yards one pin with a count, the nearest GIVER_MAX first; none where a stop, a pick-up or a
  -- hand-in has its pin already
  if QB:Settings().minimapGivers ~= false and QB.QuestMap and QB.QuestMap.GiversNear then
    local m = QB.state.mapID or QB.API.MapID()
    local me = QB.API.WorldPosition()
    local G = QB.Guide
    local MERGE, MAX = (G and G.GIVER_MERGE or 30), (G and G.GIVER_MAX or 40)
    local taken = {}
    for _, d in ipairs(out) do if d.m then taken[keyOf(d)] = true end end
    local gl = {}
    if type(m) == "number" then
      for _, g in ipairs(QB.QuestMap.GiversNear(m, QB.state.level)) do
        local d = { m = g.m, x = g.x, y = g.y, name = QB.Data.NPC[g.npc][1], kind = "give", n = 1, low = g.low }
        local w = not taken[keyOf(d)] and worldPos(d)
        if w then
          d.c, d.wx, d.wy = w.c, w.wx, w.wy
          d.far = (me and me.c == w.c) and ((w.wx - me.wx) ^ 2 + (w.wy - me.wy) ^ 2) or math.huge
          local home
          for _, o in ipairs(gl) do
            if o.c == w.c and (o.wx - w.wx) ^ 2 + (o.wy - w.wy) ^ 2 <= MERGE * MERGE then home = o break end
          end
          if home then
            home.n = home.n + 1
            if not g.low then home.low = nil end
            for _, id in ipairs(g.ids) do home.ids[#home.ids + 1] = id end
            if d.far < home.far then home.far = d.far end
          else
            d.ids = {}
            for _, id in ipairs(g.ids) do d.ids[#d.ids + 1] = id end
            gl[#gl + 1] = d
          end
        end
      end
    end
    table.sort(gl, nearFirst)
    for i = 1, math.min(MAX, #gl) do out[#out + 1] = gl[i] end
  end
  if QB.QuestMap and QB.QuestMap.PruneOpen then QB.QuestMap.PruneOpen(QB.state.log) end
  if QB:Settings().minimapObjectives ~= false and QB.Data.SPOT and QB.QuestMap and QB.QuestMap.OpenSpots then
    -- (a finished objective's spots left out, as the map leaves them out: 5.4.3 kept them, and led you to them)
    local me, spotList = QB.API.WorldPosition(), {}
    for _, e in ipairs(QB.state.logOrder or {}) do
      if not e.complete then
        local q = QB.Quest.Get(e.id)
        keys[#keys + 1] = e.id
        for _, sp in ipairs(QB.QuestMap.OpenSpots(e)) do
          local d = { m = sp.m, x = sp.x * 100, y = sp.y * 100, name = q and q.name or ("Quest " .. e.id), kind = "obj", id = e.id, obj = sp.kind, src = sp.src }
          local w = me and worldPos(d)
          d.far = (w and w.c == me.c) and ((w.wx - me.wx) ^ 2 + (w.wy - me.wy) ^ 2) or math.huge
          spotList[#spotList + 1] = d
        end
      end
    end
    -- too many: the nearest to you when the list was made (5.4.3 took the quest log's order, and the first quests'
    -- far spots crowded out the ones round you)
    if #spotList > MAX_SPOTS then table.sort(spotList, nearFirst) end
    for i = 1, math.min(MAX_SPOTS, #spotList) do out[#out + 1] = spotList[i] end
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
  Mini.AssignColors(keys)
  return out
end

-- the list as last made: made again after LIST_EVERY seconds, or when QuestBank's data (QB:Changed), the route's pins
-- (Pins.lua's list), your quest log (QB.state's) or a switch of what it holds changed. Each entry gets its key, so its
-- pin stays its own while the view moves
local cache = {}
function Mini.ListCached()
  local s, now, c = QB:Settings(), GetTime(), cache
  local pl, lo = QB.Pins and QB.Pins.list, QB.state and QB.state.logOrder
  local gv, mp = s.minimapGivers, QB.state and QB.state.mapID
  if c.list and now >= c.at and now - c.at < LIST_EVERY and c.v == QB.changed and c.pk == s.minimapPickups
    and c.ob == s.minimapObjectives and c.en == s.minimapEntrances and c.pl == pl and c.lo == lo and c.gv == gv and c.mp == mp then return c.list end
  local list = Mini.List(true)
  for _, d in ipairs(list) do d.key = d.kind .. ":" .. keyOf(d) .. ":" .. (d.id or d.num or "") end
  c.list, c.at, c.v, c.pk, c.ob, c.en, c.pl, c.lo, c.gv, c.mp = list, now, QB.changed, s.minimapPickups, s.minimapObjectives, s.minimapEntrances, pl, lo, gv, mp
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
-- screen, so a pin coming in at the edge never changes the groups inside; made again only when the list, the zoom or
-- the marker size changes, its tables kept. Each group { d, w (weight), wx, wy }
local grp = { groups = {}, pool = {}, byQuest = {}, gen = 0 }
function Mini.Group(list, v)
  local zk = floor(math.log(max(v.scale, 1e-6)) * 50)
  if grp.list == list and grp.c == v.c and grp.z == zk and grp.sz == SIZE.obj then return grp.groups end
  if grp.list ~= list or grp.c ~= v.c then
    local ents = {}
    for _, d in ipairs(list) do
      local w = worldPos(d)
      if w and w.c == v.c then ents[#ents + 1] = { d = d, w = d.w or 1, wx = w.wx, wy = w.wy } end
    end
    table.sort(ents, byWeight)
    grp.ents = ents
  end
  grp.list, grp.c, grp.z, grp.sz, grp.gen = list, v.c, zk, SIZE.obj, grp.gen + 1
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

-- whether the game says a quest of your log is elite (asked once; a no is asked again 10 seconds on, the game may not
-- know the quest's tag yet): the elite ring on its markers
local eliteOf = {}
function Mini.Elite(id)
  if type(id) ~= "number" then return false end
  local was = eliteOf[id]
  if was == true then return true end
  if was and GetTime() < was then return false end
  local elite = false
  if C_QuestLog and C_QuestLog.IsEliteQuest then
    local ok, v = pcall(C_QuestLog.IsEliteQuest, id)
    if ok and plain(v) == true then elite = true end
  end
  if not elite and C_QuestLog and C_QuestLog.GetQuestTagInfo then
    local ok, tag = pcall(C_QuestLog.GetQuestTagInfo, id)
    local eliteID = Constants and Constants.QuestConsts and plain(Constants.QuestConsts.QUEST_INFO_ELITE_ID) or 1
    if ok and type(tag) == "table" and (plain(tag.isElite) == true or plain(tag.tagID) == eliteID) then elite = true end
  end
  eliteOf[id] = elite or GetTime() + 10
  return elite
end

-- the game's own tooltip of a quest marker, as QuestTrail's minimap shows it: the title in gold, its objectives from
-- the log as "- 3/10 Thing" (done ones grey), "Ready for turn-in"
function Mini.QuestTooltip(self, id)
  local q = QB.Quest.Get(id)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText(q and q.name or self.d.name or ("Quest " .. tostring(id)), 1, 0.82, 0)
  local e = QB.state.log[id]
  if e then
    for _, o in ipairs(QB.API.Objectives(id) or {}) do
      local text = tostring(o.text or "")
      local name, have, need = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)%s*$")
      if name then text = string.format("%s/%s %s", have, need, name) end
      if text ~= "" then
        if o.done then GameTooltip:AddLine("- " .. text, 0.5, 0.5, 0.5) else GameTooltip:AddLine("- " .. text, 1, 1, 1) end
      end
    end
    if self.d.kind == "turn" or e.complete then
      GameTooltip:AddLine(type(QUEST_WATCH_QUEST_READY) == "string" and QUEST_WATCH_QUEST_READY or "Ready for turn-in", 0.4, 0.8, 1)
    end
  end
  GameTooltip:Show()
end

local T
local function newPin()
  T = T or QB.Data.TEX
  local p = CreateFrame("Button", nil, overlayFrame())
  p:SetSize(16, 16)
  -- the game style's glow behind the step and the picked quest, and a stop's disc (QuestTrail's step_bg, tinted) under
  -- its icon
  p.glow = p:CreateTexture(nil, "BACKGROUND")
  p.glow:SetTexture(ART .. "glow.tga")
  p.glow:SetPoint("CENTER")
  p.glow:SetBlendMode("ADD")
  p.glow:Hide()
  p.disc = p:CreateTexture(nil, "BACKGROUND", nil, 1)
  p.disc:SetTexture(ART .. "step_bg.png", "CLAMP", "CLAMP", "TRILINEAR")
  p.disc:SetPoint("CENTER")
  p.disc:Hide()
  p.icon = p:CreateTexture(nil, "ARTWORK")
  p.icon:SetAllPoints()
  -- an objective's gold frame over its disc, the elite ring, and the glyph on top; a stop's gold ring over all
  p.frame = p:CreateTexture(nil, "OVERLAY", nil, 1)
  p.frame:SetTexture(ART .. "ring_frame.png", nil, nil, "TRILINEAR")
  p.frame:SetAllPoints()
  p.frame:Hide()
  p.elite = p:CreateTexture(nil, "OVERLAY", nil, 2)
  p.elite:SetTexture(ART .. "ring_elite.png", nil, nil, "TRILINEAR")
  p.elite:SetPoint("CENTER")
  p.elite:Hide()
  p.glyph = p:CreateTexture(nil, "OVERLAY", nil, 3)
  p.glyph:SetPoint("CENTER")
  p.glyph:Hide()
  p.ring = p:CreateTexture(nil, "OVERLAY", nil, 7)
  p.ring:SetTexture(ART .. "step_tint.png", "CLAMP", "CLAMP", "TRILINEAR")
  p.ring:SetPoint("CENTER")
  p.ring:Hide()
  for _, t in ipairs({ p.disc, p.ring }) do QB.MiniRoute.Smooth(t) end
  p.num = p:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  p.num:SetPoint("CENTER", 0, 0)
  -- a dungeon whose quests are all done: the ready check's tick on its corner
  p.badge = p:CreateTexture(nil, "OVERLAY", nil, 4)
  p.badge:SetTexture(T.ready)
  p.badge:SetSize(10, 10)
  p.badge:SetPoint("BOTTOMRIGHT", 3, -3)
  p.badge:Hide()
  p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  p:SetScript("OnClick", QB.Safe(function(self, button)
    local d = self.d
    if not d then return end
    if button == "RightButton" then QB.MiniView.OpenMenu(d); return end
    -- shown on the arrow for now, nothing more (the arrow's step: the arrow points there already)
    if d.m then QB.API.SetWaypoint(d.m, d.x, d.y, d.name, nil, nil, Mini.About(d)) end
  end, "minimap pin"))
  p:SetScript("OnEnter", function(self)
    local d = self.d
    if not d then return end
    -- QuestTrail's look: the game's quest tooltip on a quest's own marker
    if Mini.QT() and d.id and (d.kind == "obj" or d.kind == "turn") then Mini.QuestTooltip(self, d.id); return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(d.name or "", 1, 1, 1)
    if d.when then GameTooltip:AddLine(d.when, 0.8, 0.8, 0.8) end
    if d.kind == "turn" then GameTooltip:AddLine("Hand in here", 0.3, 0.9, 0.3) end
    for _, l in ipairs(d.lines or {}) do GameTooltip:AddDoubleLine(l[1], l[2], 0.9, 0.9, 0.9, 0.6, 0.8, 0.6) end
    if d.kind == "dungeon" then GameTooltip:AddLine(d.done and "Dungeon entrance. Its quests are all done." or "Dungeon entrance", 0.8, 0.8, 0.8) end
    if d.kind == "pickup" then GameTooltip:AddLine("On your pick-up list", 0.8, 0.8, 0.8) end
    if d.kind == "give" and d.ids then
      -- the quests to take here, as the world map's ! lists them (one hover: a short list)
      GameTooltip:AddLine(#d.ids == 1 and "A quest to take here" or (#d.ids .. " quests to take here"), 0.8, 0.8, 0.8)
      local quests = {}
      for _, id in ipairs(d.ids) do local q = QB.Quest.Get(id); if q then quests[#quests + 1] = q end end
      if QB.QuestMap and QB.QuestMap.QuestLines then QB.QuestMap.QuestLines(GameTooltip, quests) end
    end
    GameTooltip:AddLine(string.format(d.m and "%d yards. Click: show it on the arrow for now." or "%d yards.", self.yards or 0), 0.5, 0.5, 0.5)
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  pins[#pins + 1] = p
  return p
end

local function shown(t, on) if (t:IsShown() and true or false) ~= (on and true or false) then t:SetShown(on and true or false) end end

-- the game's own crisp art where the client has it (the quest-number pin, the dungeon and quest marks), QuestBank's
-- textures otherwise: the game style. The quest picked on QuestBank's Map glows blue, pulsing (Mini.Pulse)
local atlasOr = QB.Art
-- a merged !'s count sits on the pin's bottom-right corner; a stop's number in its middle
local function placeNum(p, d)
  p.num:ClearAllPoints()
  if d.kind == "give" then p.num:SetPoint("CENTER", p, "BOTTOMRIGHT", -2, 2) else p.num:SetPoint("CENTER", 0, 0) end
end
local function styleGame(p, it)
  local d = it.d
  p.num:SetText(it.label or "")
  placeNum(p, d)
  p.badge:SetSize(10, 10)
  p.badge:ClearAllPoints()
  p.badge:SetPoint("BOTTOMRIGHT", 3, -3)
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

-- QuestTrail's look (StylePin, SizePin, ZoneMapDot): layers bottom to top, an objective's disc in its quest's colour
-- (ring_bg), the frame over it, never coloured (ring_frame), an elite quest's ring (ring_elite, ELITE_RING times as
-- wide), the glyph of the work (the marker's size times the glyph size setting); a stop's disc (step_bg, tinted,
-- DOT_SCALE larger: the image holds its shadow) under the ? or ! of its quest and the ring over it (step_tint, never
-- coloured); the ! and ? of givers and hand-ins the game's own; a dungeon the game's portal, the tick on its
-- bottom-left corner. The picked quest's markers blue, pulsing toward white (Mini.Pulse)
local function styleQT(p, it)
  local d, sz = it.d, it.size
  p.num:SetText(d.kind == "give" and it.label or "")
  placeNum(p, d)
  p.glow:Hide()
  local disc, frame, elite, glyph, ring = false, false, false, nil, false
  if d.kind == "obj" then
    local c = it.focus and SELECTED or colourOf(d)
    p.icon:SetTexture(ART .. "ring_bg.png", nil, nil, "TRILINEAR")
    p.icon:SetVertexColor(c[1], c[2], c[3], 1)
    frame = true
    elite = Mini.Elite(d.id)
    local g = GLYPH[d.obj]
    if d.obj == "c" and d.src == "c" then g = nil end -- (loot from mobs: the plain disc)
    glyph = g and (ART .. g .. ".png") or nil
    if glyph then
      local gs = max(4, floor(sz * (tonumber(QB:Settings().mmGlyphPct) or 100) / 100 / 2 + 0.5) * 2)
      p.glyph:SetSize(gs, gs)
      p.glyph:ClearAllPoints()
      p.glyph:SetPoint("CENTER")
    end
    if elite then
      local e = floor(sz * ELITE_RING / 2 + 0.5) * 2
      p.elite:SetSize(e, e)
    end
  elseif d.kind == "stop" then
    local c = colourOf(d)
    local a = max(tonumber(QB:Settings().zmAlpha) or 1, DOT_ALPHA)
    p.disc:SetVertexColor(c[1], c[2], c[3], a)
    p.disc:SetSize(sz * DOT_SCALE, sz * DOT_SCALE)
    p.ring:SetVertexColor(1, 1, 1, a)
    p.ring:SetSize(sz * DOT_SCALE, sz * DOT_SCALE)
    disc, ring = true, true
    -- the quest's own ? (or ! for a giver) inside, the glyphs' size
    local g = SIZE.glyph
    p.icon:ClearAllPoints()
    p.icon:SetSize(g, g)
    p.icon:SetPoint("CENTER")
    if d.num then atlasOr(p.icon, "QuestTurnin", T.questActive) else atlasOr(p.icon, "QuestNormal", T.questAvail) end
  elseif d.kind == "dungeon" then
    p.icon:SetTexture(DUNGEON_ICON)
    p.icon:SetTexCoord(0, 1, 0, 1)
  elseif d.kind == "step" then
    if not atlasOr(p.icon, d.atlas, d.icon) then p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  elseif d.kind == "turn" then
    atlasOr(p.icon, "QuestTurnin", T.questActive)
  else
    atlasOr(p.icon, "QuestNormal", T.questAvail)
    if d.escort then
      -- an escort quest: a small glyph in the bottom right corner of the !
      glyph = ART .. "glyph_escort.png"
      local g = floor(sz * 0.5 + 0.5)
      p.glyph:SetSize(g, g)
      p.glyph:ClearAllPoints()
      p.glyph:SetPoint("CENTER", p, "BOTTOMRIGHT", -floor(sz * 0.12 + 0.5), floor(sz * 0.12 + 0.5))
    end
  end
  if d.kind ~= "stop" then
    p.icon:ClearAllPoints()
    p.icon:SetAllPoints()
  end
  if glyph then
    p.glyph:SetTexture(glyph, nil, nil, "TRILINEAR")
    p.glyph:SetVertexColor(1, 1, 1, 1)
  end
  -- the tick: QuestTrail's place and size on a dungeon's portal
  p.badge:SetSize(sz * 0.51, sz * 0.51)
  p.badge:ClearAllPoints()
  p.badge:SetPoint("CENTER", p, "BOTTOMLEFT", sz * 0.305, sz * 0.305)
  shown(p.disc, disc); shown(p.frame, frame); shown(p.elite, elite); shown(p.glyph, glyph ~= nil); shown(p.ring, ring)
end

local function style(p, it)
  local d = it.d
  T = T or QB.Data.TEX
  p.icon:SetVertexColor(1, 1, 1, 1)
  p.icon:SetDesaturated(false)
  p.badge:SetShown(d.done == true)
  if Mini.QT() then styleQT(p, it) else
    p.icon:ClearAllPoints()
    p.icon:SetAllPoints()
    shown(p.disc, false); shown(p.frame, false); shown(p.elite, false); shown(p.glyph, false); shown(p.ring, false)
    styleGame(p, it)
  end
end

-- the picked quest's pins, once a second (every frame while there are any): QuestTrail's look, their blue disc a third
-- of the way to white and back; the game style, their glow from faint to bright and back
function Mini.Pulse()
  local k, any = (1 - cos(GetTime() * 2 * pi)) / 2, false
  local qt, c = Mini.QT(), SELECTED
  for _, p in ipairs(pins) do
    if p.focus and p:IsShown() then
      if qt then
        if p.d and p.d.kind == "obj" then
          local f = k * 0.33
          p.icon:SetVertexColor(c[1] + (1 - c[1]) * f, c[2] + (1 - c[2]) * f, c[3] + (1 - c[3]) * f, 1)
        end
      else
        p.glow:SetAlpha(0.25 + 0.75 * k)
      end
      any = true
    end
  end
  Mini.pulsing = any
end

-- one update: the view (MinimapView.lua: a drag, the ease back, the far ground and your arrow), then the pins on it.
-- Where you stand is read into one table kept for it (20 times a second; nothing keeps it past the update)
local here = {}
function Mini.Update(dt)
  local me = QB.API.WorldPosition(nil, here)
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
local placeView = {} -- (the view of a placing called without one)
local aimEntry = {}  -- the one target where no pin of the list stands for it (an objective's spot), filled anew
-- /qb trace: each change of the minimap's target, with how far it is
local traced = {}
local function traceTarget(d, w, me)
  local kind, id, wx, wy = d and d.kind, d and (d.id or d.num), w and floor(w.wx), w and floor(w.wy)
  if kind == traced.kind and id == traced.id and wx == traced.wx and wy == traced.wy then return end
  traced.kind, traced.id, traced.wx, traced.wy = kind, id, wx, wy
  QB.Trace("minimap: the stroke to %s%s", d and tostring(d.name) or "nothing",
    (d and w) and string.format(" (%s, %.0f yards)", kind, sqrt((w.wx - me.wx) ^ 2 + (w.wy - me.wy) ^ 2)) or "")
end
local function addItem(v, me, d, w, wx, wy, focus)
  local size = SIZE[d.kind] or 16
  if d.kind == "obj" then size = even(size * weightScale(w)) end
  local x, y, alpha = place(v, d.kind, wx, wy, size)
  if not x then return nil end
  if d.low then alpha = alpha * 0.5 end -- (a ! of grey quests alone, Low-level quests on: half bright, as the game's)
  local n = #items + 1
  local it = itemPool[n] or {}
  itemPool[n], items[n] = it, it
  local dn, dw = wx - me.wx, wy - me.wy
  it.d, it.key, it.x, it.y, it.alpha, it.size, it.yards = d, d.key or d.kind, x, y, alpha, size, sqrt(dn * dn + dw * dw)
  it.label, it.focus, it.pin = d.num and tostring(d.num) or (d.kind == "give" and d.n and d.n > 1 and tostring(d.n)) or nil, (focus ~= nil and d.id == focus) or nil, nil
  return it
end
local function byRank(a, b)
  local ka, kb = RANK[a.d.kind] or 2, RANK[b.d.kind] or 2
  if ka ~= kb then return ka < kb end
  return a.yards < b.yards
end
local marks = {} -- (each placing's pins, { x, y, r }, for the strokes' softening; the tables kept)
local function seg(n, x1, y1, x2, y2, col, alpha, size, gold)
  local s = segs[n] or {}
  segs[n] = s
  s.x1, s.y1, s.x2, s.y2, s.col, s.alpha, s.size, s.gold = x1, y1, x2, y2, col, alpha, size, gold
  return n
end

-- what a pin was last styled for, beyond its place and label: the look, the sizes, the colours
local function styleKey()
  local s = QB:Settings()
  return (Mini.QT() and "qt" or "game") .. ":" .. SIZE.ring .. ":" .. SIZE.glyph .. ":" .. tostring(s.mmColor) .. ":" .. Mini.colorGen .. ":" .. tostring(s.zmAlpha)
end

-- place every pin for where you stand now (me), on the view v (MV.View's for me when not given): QuestTrail's
-- UpdateMinimap, with QuestBank's places
function Mini.Place(me, v)
  if not on() then Mini.Clear(); return end
  me = me or QB.API.WorldPosition()
  local f = overlayFrame()
  if not me then Mini.Clear(); return end
  local MV = QB.MiniView
  v = v or MV.View(me, placeView)
  local set = QB:Settings()
  local qt = Mini.QT()
  Mini.Sizes()
  local list = Mini.ListCached()
  local groups = Mini.Group(list, v)
  local focus = QB.MapPage and QB.MapPage.focus
  for k = #items, 1, -1 do items[k] = nil end
  for k = #byNum, 1, -1 do byNum[k] = nil end
  -- the arrow's step first, read now: it moves with the arrow's guide (on the way to the one target the strokes go by
  -- it; while the arrow leads elsewhere, a hand-in or a place clicked, it is a pin of its own)
  local step, stepVia
  if QB.Target then step, stepVia = QB.Target.Step() end
  if step and step.c ~= me.c then step = nil end
  if step then step.key = "step"; addItem(v, me, step, 1, step.wx, step.wy, focus) end
  -- the route's stops in order, at their true places for the strokes; two at one place are one pin, "2,3" (a circle
  -- a third bigger for each more)
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
  local pulsing, sk = false, styleKey()
  for _, it in ipairs(items) do
    local p, d = it.pin, it.d
    if p.d ~= d or p.label ~= it.label or p.focus ~= it.focus or p.sz ~= it.size or p.sa ~= d.atlas or p.si ~= d.icon or p.sk ~= sk or p.done ~= d.done then
      if p.sz ~= it.size then p:SetSize(it.size, it.size); p.sz = it.size end
      p.d = d
      style(p, it)
      p.label, p.focus, p.sa, p.si, p.sk, p.done = it.label, it.focus, d.atlas, d.icon, sk, d.done
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
  -- where the stroke and the label go: the one target (Target.lua), the same the arrow and the Map page lead to: stop 1
  -- (its own pin), or a spot of an objective of its quest still to do; the arrow's step toward it first. 5.4.3 picked
  -- its own here 20 times a second, the nearest spot of any quest in your log, and the stroke jumped from one to the
  -- next as you walked
  local aim, aw
  local t = QB.Target and QB.Target.Get(me)
  if t and t.c == me.c then
    local s1 = byNum[1]
    if not t.obj and not t.near and s1 then
      aim, aw = s1.d, worldPos(s1.d)
    else
      -- an objective's spot, a hand-in in reach (Target.lua: before stop 1), or stop 1 without its pin
      local kind = t.obj and "obj" or (t.near and "turn" or "stop")
      aimEntry.kind, aimEntry.id, aimEntry.name, aimEntry.c, aimEntry.wx, aimEntry.wy = kind, t.qid, t.name, t.c, t.wx, t.wy
      aimEntry.cid, aimEntry.num, aimEntry.key = t.qid, kind == "stop" and 1 or nil, "aim:" .. kind
      aim, aw = aimEntry, aimEntry
    end
  end
  if not stepVia then step = nil end
  local target, tw = step or aim, step or aw
  Mini.target, Mini.aim = target, aim
  local tx, ty = 0, 0
  if target then
    tx, ty = MV.Point(v, tw.wx, tw.wy)
    tinfo.d, tinfo.x, tinfo.y, tinfo.far = target, tx, ty, MV.Reach(tx, ty) > v.R - EDGE
  end
  Mini.Label(target and tinfo, f)
  if QB.tracing then traceTarget(target, tw, me) end
  -- the strokes: you to the target (along the golden path when your trails know the way), on to the one target if the
  -- target is the arrow's step, on to stop 1 if that is not it, then stop to stop, up to minimapSteps stops.
  -- QuestTrail's look: each in its step's quest's colour (the first in the one target's; to a flight master, blue),
  -- the stroke setting's width and opacity; the game style, gold then blue
  local n, gold = 0, false
  local alpha = qt and (tonumber(set.zmAlpha) or 1) or 1
  if set.minimapLines ~= false and target then
    local mx, my = MV.Point(v, me.wx, me.wy)
    local tcol = GOLD
    if qt then tcol = (aim and target == aim) and colourOf(aim) or TRAVEL end
    n = seg(1, mx, my, tx, ty, tcol, alpha, SIZE[target.kind] or 16, true)
    local prev, px, py = target, tx, ty
    if aim and target ~= aim then
      local ax, ay = MV.Point(v, aw.wx, aw.wy)
      n = seg(n + 1, px, py, ax, ay, qt and colourOf(aim) or BLUE, qt and alpha or 0.85, SIZE[aim.kind] or 16)
      prev, px, py = aim, ax, ay
    end
    for num = 1, set.minimapSteps or 16 do
      local s = byNum[num]
      if not s then break end
      if s.d ~= prev then n = seg(n + 1, px, py, s.x, s.y, qt and colourOf(s.d) or BLUE, qt and alpha or 0.85, s.it and s.it.size or SIZE.stop) end
      prev, px, py = s.d, s.x, s.y
    end
    gold = Mini.GoldenPath(me, target)
  end
  -- the pins as the strokes see them: a stroke (and the golden path) crossing a quest's icon other than the two it
  -- joins is softened there, and only there (MinimapRoute.lua, MR.Stroke and MR.Soften); the strokes are drawn under
  -- the pins (their frames' levels)
  local MR = QB.MiniRoute
  local thick = qt and max(2, min(24, tonumber(set.zmWidth) or 6)) or MR.THICK
  local nm = #items
  for i = 1, nm do
    local it = items[i]
    local m = marks[i] or {}
    marks[i] = m
    m.x, m.y, m.r = it.x, it.y, (it.size or 16) * 0.5
  end
  Mini.shown, Mini.linesShown = #items, MR.Draw(v, segs, n, gold, qt and thick or nil, marks, nm)
  Mini.DrawTrails(v)
end

-- the target's name in a dark pill above it, the way the game labels a pin: the game style's (QuestTrail's minimap has
-- no label; the name is Mini.labelText either way)
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
  Mini.labelText = target and target.d.name or nil
  if not (target and not target.far and QB:Settings().minimapLabel ~= false and not Mini.QT()) then label:Hide(); return end
  label.text:SetText(target.d.name or "")
  label:SetSize(math.min(200, (label.text:GetStringWidth() or 80) + 18), 22)
  label:ClearAllPoints()
  label:SetPoint("BOTTOM", f, "CENTER", target.x, target.y + 12)
  label:Show()
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
function Mini.Invalidate()
  worldOf, cache.list, grp.list = {}, nil, nil
  if QB.Target then QB.Target.Invalidate() end
end


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
