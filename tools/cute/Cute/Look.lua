-- SPDX-License-Identifier: GPL-3.0-or-later
-- The look (the windows round, sub-project D): one visual system for the rows and cards of every window. Each row has
-- five channels and each carries one kind of meaning: the icon (the game's own art) says what kind of thing it is; the
-- 2 px bar at its left its category (QUEST gold for questing, GROUP teal for dungeons and raids, NEW blue for found
-- data, LINE for none); the text colour its hierarchy (WHITE, INK, DIM, MUTE: the game's colours only for class names,
-- item names by quality and a quest's level by difficulty); the right-hand word its status (GOOD, WARN, BAD, NEW); the
-- background its state (0.06 white for open, target or you, 0.035 for a group head, +0.05 on hover). No drawn marks: a
-- category is a bar, a status a word. Art as QuestBank draws it: the atlas where the client has it, else the file
-- (UI.Art); every file named here is in the client's manifest.
-- The three patterns the quest window is made of, each a widget a page takes from a pool and fills:
--   A  the list row: a head (24 px), a compact row (20), a two-line row (34), a place (40)
--   B  the route stop: 40 px and 18 a quest under it, on a rail; the level-up rule between two stops
--   C  the dungeon card: the art at its own 174 x 96, the name, the level range, the bosses, the foot
local _, C = ...
local UI = C.UI
local L = {}
UI.Look = L
if C.API then C.API.Look = L end -- (Cute.Look: a module's pages draw with the same pieces)
local K = UI.COLORS
local FLAT = "Interface\\Buttons\\WHITE8x8"
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local DOT = " \194\183 "
L.DOT = DOT

-- the art, by what it means: { atlas, file, file's corners }. The quest POI's disc and its glyphs, the objectives' cursors
-- (QuestBank's QuestMap.lua QM.ART), the ways to travel (QuestBank's D.TEX), the group's marks, the ready checks
L.ART = {
  accept = { "QuestNormal", 132049 }, repeatable = { "UI-QuestPoiRecurring-QuestBang", 132049 },
  turnin = { "UI-QuestIcon-TurnIn-Normal", 132048 }, progress = { "Quest-In-Progress-Icon-yellow", 132048 },
  disc = { "UI-QuestPoi-QuestNumber", 334391, { 0.875, 1, 0.875, 1 } },
  k = { "Crosshair_Attack_32", 131013 }, c = { "Crosshair_LootAll_32", 131023 }, u = { "Crosshair_Interact_32", 131021 },
  b = { "Crosshair_Buy_32", 131014 }, e = { "QuestObjective", 131017 }, f = { "Crosshair_Fishing_32", 303902 },
  s = { "Crosshair_LootAll_32", 131023 }, d = { "Dungeon", 136347 },
  flight = { "FlightPath", 132239 }, gryphon = { nil, 132239 }, wyvern = { nil, 132268 }, hearth = { nil, 134414 },
  boat = { nil, 1686581 }, zeppelin = { nil, 1519491 }, tram = { nil, 132996 }, portal = { nil, 135741 },
  foot = { nil, 132307 }, mount = { nil, 132261 }, skull = { nil, 137025 },
  dungeon = { "Dungeon", 136347 }, raid = { "Raid", 136347 }, party = { nil, 134149 },
  leader = { nil, 132062 }, assist = { nil, 132061 }, lock = { nil, 130944 }, alert = { nil, 357854 },
  ready = { nil, 136814 }, notready = { nil, 136813 }, waiting = { nil, 136815 },
  player = { nil, 803894 }, ring = { nil, 136430 }, unknown = { nil, 134400 },
  upgrade = { nil, 969828, { 66 / 512, 86 / 512, 93 / 256, 115 / 256 } }, -- (the bags' green arrow, bags-greenarrow)
}

-- a texture painted with an art by name or as { atlas, file, corners }: the atlas where the client has it, else the
-- file at its corners (an icon's file cropped of its border). Kept per texture: a redraw paints nothing it painted
function L.Paint(t, art, crop)
  if type(art) == "string" then art = L.ART[art] end
  if type(art) == "number" then art = { nil, art } end
  if t.cuteArt == art and t.cuteCrop == crop then t:Show() return end
  t.cuteArt, t.cuteCrop = art, crop
  if not art then t:Hide() return end
  local info = art[1] and type(C_Texture) == "table" and type(C_Texture.GetAtlasInfo) == "function" and C.Get(C_Texture.GetAtlasInfo, art[1])
  if type(info) == "table" and t.SetAtlas then
    t:SetTexCoord(0, 1, 0, 1)
    t:SetAtlas(art[1])
  else
    t:SetTexture(art[2])
    local tc = art[3] or (crop and { 0.08, 0.92, 0.08, 0.92 }) or { 0, 1, 0, 1 }
    t:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
  end
  t:Show()
end
-- text over art or the world: the font's outline and a 1 px shadow
function L.Outline(fs, size)
  fs:SetFont(UI.FONT, size or fs.cuteSize or 12, "OUTLINE")
  if fs.SetShadowOffset then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1) end
end

-- item quality: the game's exact colour on an icon's 1 px edge (black for poor and common), and a name's colour lifted
-- to keep its hue at 4.5:1 on the window's panels (rare #4094ED, epic #BA69F2)
local EDGE = { [0] = { 0, 0, 0 }, [1] = { 0, 0, 0 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 } }
local NAME = { [0] = { 0.62, 0.62, 0.62 }, [1] = K.INK, [2] = { 0.12, 1, 0 }, [3] = { 0.25, 0.58, 0.93 }, [4] = { 0.73, 0.41, 0.95 }, [5] = { 1, 0.5, 0 } }
function L.QualityEdge(q) return EDGE[q or 1] or EDGE[1] end
function L.QualityName(q) return NAME[q or 1] or K.INK end
-- a quest's level in the game's colour for it against yours (QuestDifficultyColors, Constants.lua:195, as
-- GetQuestDifficultyColor gives it), the ink where the client has none
-- (the game's rule where the client has no such function: red five and more above you, orange three, yellow within two,
-- green above the grey range, grey; QuestUtils' GetQuestDifficultyColor, the grey range as Classic's)
local DIFF = { red = { 1, 0.1, 0.1 }, orange = { 1, 0.5, 0.25 }, yellow = { 1, 0.82, 0 }, green = { 0.25, 0.75, 0.25 }, grey = { 0.5, 0.5, 0.5 } }
function L.LevelColor(level)
  local f = GetQuestDifficultyColor
  if type(level) ~= "number" then return K.INK end
  if type(f) == "function" then
    local c = C.Get(f, level)
    if type(c) == "table" and type(c.r) == "number" then return { c.r, c.g, c.b } end
  end
  local me = C.Num("UnitLevel", "player") or level
  local d = level - me
  if d >= 5 then return DIFF.red elseif d >= 3 then return DIFF.orange elseif d >= -2 then return DIFF.yellow end
  local grey = me <= 5 and 0 or (me <= 39 and (me - math.floor(me / 10) - 5) or (me - math.floor(me / 5) - 1))
  return level > grey and DIFF.green or DIFF.grey
end
-- the inline glyph of an art in a line of text (|A atlas|a where the client has it, else |T file|t), size px
function L.Inline(art, size)
  if type(art) == "string" then art = L.ART[art] end
  if not art then return "" end
  size = size or 12
  local info = art[1] and type(C_Texture) == "table" and type(C_Texture.GetAtlasInfo) == "function" and C.Get(C_Texture.GetAtlasInfo, art[1])
  if type(info) == "table" then return string.format("|A:%s:%d:%d|a", art[1], size, size) end
  local tc = art[3]
  if tc then return string.format("|T%s:%d:%d:0:0:512:256:%d:%d:%d:%d|t", tostring(art[2]), size, size, tc[1] * 512, tc[2] * 512, tc[3] * 256, tc[4] * 256) end
  return string.format("|T%s:%d:%d|t", tostring(art[2]), size, size)
end

----------------------------------------------------------------------------
-- an icon's slot: the art, an item's 1 px quality edge, the quest POI's disc under a glyph, the upgrade arrow, a count
----------------------------------------------------------------------------
local function flat(parent, layer, c, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  return t
end
L.Flat = flat
function L.MakeSlot(parent, size)
  local s = CreateFrame("Frame", nil, parent)
  s:SetSize(size, size)
  s.edge = flat(s, "BACKGROUND", { 0, 0, 0 }, 1)
  s.edge:SetAllPoints()
  s.edge:Hide()
  s.disc = s:CreateTexture(nil, "BORDER")
  s.disc:SetAllPoints()
  s.disc:Hide()
  s.tex = s:CreateTexture(nil, "ARTWORK")
  s.tex:SetAllPoints()
  s.up = s:CreateTexture(nil, "OVERLAY")
  s.up:SetSize(10, 10)
  s.up:SetPoint("TOPLEFT", -1, 1)
  s.up:Hide()
  s.badge = UI.Text(s, 10, K.WHITE, "RIGHT")
  L.Outline(s.badge, 10)
  s.badge:SetPoint("BOTTOMRIGHT", 3, -2)
  s.badge:Hide()
  -- (round: an item or a creature's face cut round, as the game's finds and bosses are)
  if s.CreateMaskTexture and s.tex.AddMaskTexture then
    s.mask = s:CreateMaskTexture()
    s.mask:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    s.mask:SetAllPoints(s.tex)
  end
  return s
end
-- what a slot shows: spec = { art = name or { atlas, file }, poi = "log" | "ready", item = icon file, q = quality,
-- up = an upgrade, round = cut round, desat = greyed, n = a count }; nil hides it
function L.FillSlot(s, spec)
  if not spec then s:Hide() return end
  s:Show()
  local size = s:GetWidth() or 20
  s.tex:ClearAllPoints()
  if spec.item then
    -- an item: its icon inside its 1 px edge in the quality's colour, the border cropped
    local e = L.QualityEdge(spec.q)
    s.edge:SetColorTexture(e[1], e[2], e[3], 1)
    s.edge:Show()
    s.tex:SetPoint("TOPLEFT", 1, -1)
    s.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    L.Paint(s.tex, { nil, spec.item }, true)
    s.disc:Hide()
  elseif spec.poi then
    -- the game's quest POI (Pins.lua P.StylePoi): the disc with the in-progress or hand-in glyph on it; under 18 px the
    -- ready one is the bare hand-in glyph
    s.edge:Hide()
    if spec.poi == "ready" and size < 18 then
      s.disc:Hide()
      s.tex:SetAllPoints()
      L.Paint(s.tex, "turnin")
    else
      L.Paint(s.disc, "disc")
      local k = spec.poi == "ready" and 0.72 or 0.62
      s.tex:SetPoint("CENTER")
      s.tex:SetSize(size * k, size * k)
      L.Paint(s.tex, spec.poi == "ready" and "turnin" or "progress")
    end
  else
    s.edge:Hide(); s.disc:Hide()
    s.tex:SetAllPoints()
    L.Paint(s.tex, spec.art, spec.crop)
  end
  if s.mask then
    if spec.round and not s.masked then pcall(s.tex.AddMaskTexture, s.tex, s.mask); s.masked = true
    elseif not spec.round and s.masked and s.tex.RemoveMaskTexture then pcall(s.tex.RemoveMaskTexture, s.tex, s.mask); s.masked = nil end
  end
  s.tex:SetDesaturated(spec.desat and true or false)
  s.tex:SetAlpha(spec.alpha or 1)
  if spec.up then L.Paint(s.up, "upgrade"); s.up:Show() else s.up:Hide() end
  if spec.n and spec.n ~= "" then s.badge:SetText(tostring(spec.n)); s.badge:Show() else s.badge:Hide() end
end

----------------------------------------------------------------------------
-- A. the list row
----------------------------------------------------------------------------
-- heights by kind: a group's head, a row of one line, of two, a place with its picture
L.H = { head = 24, row = 20, two = 34, place = 40, note = 22, mate = 24 }
-- one row widget for every kind: the background, the category bar, the icon's slot (or a place's picture), the
-- level, the name, line 2, and on the right the who, the value and a reward's icon. Callers set fn and tip
function L.MakeRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(L.H.row)
  r.bg = flat(r, "BACKGROUND", K.WHITE, 0)
  r.bg:SetAllPoints()
  r.bar = flat(r, "ARTWORK", K.WHITE, 1)
  r.bar:SetPoint("TOPLEFT", 0, 0)
  r.bar:SetPoint("BOTTOMLEFT", 0, 0)
  r.bar:SetWidth(2)
  r:SetHighlightTexture(FLAT, "ADD")
  r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)
  r.pic = r:CreateTexture(nil, "BORDER")
  r.pic:SetSize(64, 40)
  r.pic:Hide()
  r.slot = L.MakeSlot(r, 20)
  r.lvl = UI.Text(r, 12, K.INK, "RIGHT", 24)
  r.name = UI.Text(r, 13, K.INK, "LEFT")
  r.line2 = UI.Text(r, 11, K.DIM, "LEFT")
  r.who = UI.Text(r, 11, K.DIM, "RIGHT")
  r.val = UI.Text(r, 12, K.INK, "RIGHT")
  r.sub = UI.Text(r, 11, K.DIM, "RIGHT")
  r.rew = L.MakeSlot(r, 16)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", C.Safe(function(self, which) if self.fn then self.fn(self, which) end end, "row: click"))
  r:SetScript("OnEnter", C.Safe(function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    self.tip(GameTooltip, self)
    GameTooltip:Show()
  end, "tooltip"))
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return r
end
local function put(fs, point, x, y, width, s, c, justify, size)
  fs:ClearAllPoints()
  fs:SetPoint(point, x, y)
  fs:SetWidth(width)
  fs:SetJustifyH(justify or "LEFT")
  if size and fs.cuteSize ~= size then fs.cuteSize = size; fs:SetFont(UI.FONT, size, "") end
  UI.Color(fs, c or K.INK)
  UI.FitText(fs, s or "", width - 2)
  fs:Show()
end
L.Put = put
-- a row filled: it = { kind = head | row | two | place | note | mate, bar = colour (nil none), bg = alpha, icon = a
-- slot's spec, lvl, lvlC, name, nameC, line2, who, whoC, val, sub, rew = a slot's spec, pic = { file, corners },
-- fn, tip }; w its width; returns its height
function L.FillRow(r, it, w)
  local kind = it.kind or (it.line2 and "two" or "row")
  local h = it.h or L.H[kind] or L.H.row
  r:SetSize(w, h)
  r.bg:SetColorTexture(1, 1, 1, it.bg or (kind == "head" and 0.035 or 0))
  if it.bar then r.bar:SetColorTexture(it.bar[1], it.bar[2], it.bar[3], 1); r.bar:Show() else r.bar:Hide() end
  r.fn, r.tip = it.fn, it.tip
  r:EnableMouse(it.fn ~= nil or it.tip ~= nil)
  r.lvl:Hide(); r.line2:Hide(); r.who:Hide(); r.val:Hide(); r.sub:Hide(); r.rew:Hide(); r.pic:Hide(); r.slot:Hide()
  local narrow = w <= 320
  if kind == "head" then
    -- a group's head: its icon at 16, its name at 12, the status word at its right
    r.slot:SetSize(16, 16); r.slot:ClearAllPoints(); r.slot:SetPoint("LEFT", 8, 0)
    L.FillSlot(r.slot, it.icon)
    local x = it.icon and 30 or 10
    local right = it.who and 210 or 8
    put(r.name, "LEFT", x, 0, w - x - right, it.name, it.nameC or K.INK, "LEFT", 12)
    if it.who then put(r.who, "RIGHT", -8, 0, 200, it.who, it.whoC or K.DIM, "RIGHT", 11) end
    return h
  end
  if kind == "place" then
    -- a place: its painted picture (the middle of its 256 x 128) at 64 x 40, else its icon; its name white, how many
    -- quests and how far on line 2; its XP and its XP a minute on the right
    local x = 76
    if it.pic then
      r.pic:ClearAllPoints(); r.pic:SetPoint("LEFT", 4, 0)
      r.pic:SetTexture(it.pic[1])
      local tc = it.pic[2] or { 0.1, 0.9, 0, 1 }
      r.pic:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
      r.pic:Show()
    else
      r.slot:SetSize(20, 20); r.slot:ClearAllPoints(); r.slot:SetPoint("LEFT", 26, 0)
      L.FillSlot(r.slot, it.icon)
    end
    local right = it.val and 120 or 8
    put(r.name, "TOPLEFT", x, -4, w - x - right, it.name, it.nameC or K.WHITE, "LEFT", 13)
    if it.line2 then put(r.line2, "TOPLEFT", x, -22, w - x - right, it.line2, K.DIM, "LEFT", 11) end
    if it.val then put(r.val, "TOPRIGHT", -8, -4, 112, it.val, K.INK, "RIGHT", 12) end
    if it.sub then put(r.sub, "TOPRIGHT", -8, -21, 112, it.sub, K.DIM, "RIGHT", 11) end
    return h
  end
  if kind == "note" or kind == "more" then
    put(r.name, "LEFT", it.x or 56, 0, w - (it.x or 56) - 8, it.name, it.nameC or K.DIM, "LEFT", 12)
    return h
  end
  if kind == "mate" then
    -- a party member: the class's bar and name, their step
    put(r.name, "LEFT", 12, 0, 90, it.name, it.nameC or K.INK, "LEFT", 12)
    if it.line2 then put(r.line2, "LEFT", 106, 0, w - 114, it.line2, K.DIM, "LEFT", 12) end
    return h
  end
  -- a quest, a gear row, any row with an icon: the icon at 8 (20 in two lines, 16 in one), the level right-aligned
  -- from 28 to 50, the name from 56 (34 without a level), line 2 under it; on the right, from the edge in: a reward's
  -- icon, the value, the who (none in a list 320 px wide or less)
  local two = kind == "two"
  local isz = two and 20 or 16
  r.slot:SetSize(isz, isz); r.slot:ClearAllPoints(); r.slot:SetPoint("TOPLEFT", 8, two and -7 or -2)
  L.FillSlot(r.slot, it.icon)
  local x = it.lvl and 56 or (it.icon and 34 or 10)
  if it.lvl then put(r.lvl, "TOPLEFT", 26, two and -3 or -4, 24, it.lvl, it.lvlC or K.INK, "RIGHT", 12) end
  local right = 8
  if it.rew then
    r.rew:ClearAllPoints(); r.rew:SetPoint("TOPRIGHT", -8, two and -9 or -2)
    L.FillSlot(r.rew, it.rew)
    right = right + 16 + 8
  end
  local valW = it.valW or (narrow and 56 or 64)
  if it.val then put(r.val, "TOPRIGHT", -right, two and -10 or -4, valW, it.val, it.valC or K.INK, "RIGHT", 12); right = right + valW + 8 end
  if it.who and not narrow then put(r.who, "TOPRIGHT", -right, two and -11 or -5, 112, it.who, it.whoC or K.DIM, "RIGHT", 11); right = right + 112 + 8 end
  put(r.name, "TOPLEFT", x, two and -3 or -3, w - x - right, it.name, it.nameC or K.INK, "LEFT", 13)
  if it.line2 and two then put(r.line2, "TOPLEFT", x, -19, w - x - (narrow and 8 or right), it.line2, it.line2C or K.DIM, "LEFT", 11) end
  return h
end

----------------------------------------------------------------------------
-- the XP bar: your XP white, each gain to come as its own green segment (1 px apart), a tick at each level
----------------------------------------------------------------------------
function L.MakeXP(parent)
  local b = CreateFrame("Frame", nil, parent)
  b:SetHeight(6)
  b.track = flat(b, "BACKGROUND", { 0.16, 0.16, 0.16 }, 1)
  b.track:SetAllPoints()
  b.mine = flat(b, "ARTWORK", K.WHITE, 1)
  b.mine:SetPoint("TOPLEFT"); b.mine:SetPoint("BOTTOMLEFT")
  b.segs, b.ticks = {}, {}
  return b
end
-- from, to: the levels the bar spans; at: where you stand (a level and its fraction); gains: the XP each part to come
-- adds, as fractions of a level, in order
function L.FillXP(b, w, from, to, at, gains)
  b:SetWidth(w)
  local span = math.max(0.01, to - from)
  local function x(v) return math.floor((math.min(to, math.max(from, v)) - from) / span * w + 0.5) end
  b.mine:SetWidth(math.max(1, x(at)))
  local pos, n = at, 0
  for _, g in ipairs(gains or {}) do
    if g > 0 and pos < to then
      n = n + 1
      local s = b.segs[n]
      if not s then s = flat(b, "ARTWORK", K.GOOD, 1); b.segs[n] = s end
      local a, e = x(pos) + 1, x(pos + g)
      s:ClearAllPoints(); s:SetPoint("TOPLEFT", a, 0); s:SetPoint("BOTTOMLEFT", a, 0)
      s:SetWidth(math.max(1, e - a))
      s:Show()
      pos = pos + g
    end
  end
  for i = n + 1, #b.segs do b.segs[i]:Hide() end
  local k = 0
  for l = math.floor(from) + 1, math.ceil(to) - 1 do
    k = k + 1
    local t = b.ticks[k]
    if not t then t = flat(b, "OVERLAY", { 0.45, 0.45, 0.45 }, 1); t:SetSize(1, 10); b.ticks[k] = t end
    t:ClearAllPoints(); t:SetPoint("LEFT", x(l), 0)
    t:Show()
  end
  for i = k + 1, #b.ticks do b.ticks[i]:Hide() end
  return pos
end

----------------------------------------------------------------------------
-- B. the route stop
----------------------------------------------------------------------------
L.STOP_H, L.STOP_Q, L.RULE_H = 40, 18, 22
function L.MakeStop(parent)
  local st = CreateFrame("Button", nil, parent)
  st.bg = flat(st, "BACKGROUND", K.WHITE, 0)
  st.bg:SetAllPoints()
  st:SetHighlightTexture(FLAT, "ADD")
  st:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.04)
  st.rail = flat(st, "BORDER", K.EDGE, 1)
  st.rail:SetWidth(2)
  st.ring = st:CreateTexture(nil, "ARTWORK")
  st.ring:SetSize(30, 30)
  st.ring:SetPoint("TOPLEFT", 0, -5)
  st.ring:Hide()
  st.node = L.MakeSlot(st, 24)
  st.node:SetPoint("TOPLEFT", 3, -8)
  st.node:SetFrameLevel(st:GetFrameLevel() + 2)
  st.line1 = UI.Text(st, 11, K.DIM, "LEFT")
  st.way = L.MakeSlot(st, 14)
  st.wayText = UI.Text(st, 11, K.INK, "LEFT")
  st.name = UI.Text(st, 13, K.INK, "LEFT")
  st.xp = UI.Text(st, 12, K.INK, "RIGHT")
  st.lvl = UI.Text(st, 11, K.DIM, "RIGHT")
  st.qs = {}
  st:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  st:SetScript("OnClick", C.Safe(function(self, which) if self.fn then self.fn(self, which) end end, "stop: click"))
  st:SetScript("OnEnter", C.Safe(function(self)
    if self.hover then self.hover(true) end
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); self.tip(GameTooltip, self); GameTooltip:Show()
  end, "tooltip"))
  st:SetScript("OnLeave", function(self) if self.hover then self.hover(false) end; GameTooltip:Hide() end)
  return st
end
local function stopQuest(st, i)
  local q = st.qs[i]
  if q then return q end
  q = CreateFrame("Button", nil, st)
  q:SetHeight(L.STOP_Q)
  q.glyph = L.MakeSlot(q, 14)
  q.glyph:SetPoint("LEFT", 0, 0)
  q.name = UI.Text(q, 12, K.INK, "LEFT")
  q.prog = UI.Text(q, 11, K.DIM, "LEFT")
  q.right = UI.Text(q, 11, K.DIM, "RIGHT")
  q:SetHighlightTexture(FLAT, "ADD")
  q:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)
  q:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  q:SetScript("OnClick", C.Safe(function(self, which) if self.fn then self.fn(self, which) end end, "stop: a quest"))
  q:SetScript("OnEnter", C.Safe(function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); self.tip(GameTooltip, self); GameTooltip:Show()
  end, "tooltip"))
  q:SetScript("OnLeave", function() GameTooltip:Hide() end)
  st.qs[i] = q
  return q
end
-- a stop filled: it = { node = a slot's spec, target = true for the one the arrow leads to (its ring and background),
-- ring = the ring's file, line1 = "+4 min, 420 yd", way = { icon spec, words } where the way changes from walking, name,
-- xp = "+4,250 XP", lvl = "21.7", quests = { { glyph = spec, name, prog, right, rightC, fn, tip } }, first, last, fn, tip,
-- hover }; returns its height
function L.FillStop(st, it, w)
  local n = #(it.quests or {})
  local h = L.STOP_H + n * L.STOP_Q
  st:SetSize(w, h)
  st.bg:SetColorTexture(1, 1, 1, it.target and 0.06 or 0)
  st.rail:ClearAllPoints()
  st.rail:SetPoint("TOPLEFT", 14, it.first and -20 or 0)
  if it.last then st.rail:SetHeight(it.first and 0.01 or 20) else st.rail:SetPoint("BOTTOMLEFT", 14, 0) end
  st.rail:SetShown(not (it.first and it.last))
  if it.target and it.ring then st.ring:SetTexture(it.ring); st.ring:Show() else st.ring:Hide() end
  L.FillSlot(st.node, it.node)
  st.fn, st.tip, st.hover = it.fn, it.tip, it.hover
  local x = 34
  put(st.line1, "TOPLEFT", x, -4, it.way and 150 or (w - x - 8), it.line1 or "", K.DIM, "LEFT", 11)
  if it.way then
    local lw = math.min(150, (st.line1.GetUnboundedStringWidth or st.line1.GetStringWidth)(st.line1) or 0)
    st.way:ClearAllPoints(); st.way:SetPoint("TOPLEFT", x + lw + 8, -3)
    L.FillSlot(st.way, it.way[1])
    put(st.wayText, "TOPLEFT", x + lw + 26, -4, w - (x + lw + 26) - 8, it.way[2], K.INK, "LEFT", 11)
  else
    st.way:Hide(); st.wayText:Hide()
  end
  local right = 8
  if it.lvl then put(st.lvl, "TOPRIGHT", -8, -19, 34, it.lvl, K.DIM, "RIGHT", 11); right = right + 34 + 6 else st.lvl:Hide() end
  if it.xp then put(st.xp, "TOPRIGHT", -right, -18, 90, it.xp, K.INK, "RIGHT", 12); right = right + 90 + 6 else st.xp:Hide() end
  put(st.name, "TOPLEFT", x, -18, w - x - right, it.name, it.target and K.WHITE or K.INK, "LEFT", 13)
  for i, q in ipairs(it.quests or {}) do
    local b = stopQuest(st, i)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", x, -(38 + (i - 1) * L.STOP_Q))
    b:SetWidth(w - x - 8)
    b:Show()
    L.FillSlot(b.glyph, q.glyph)
    local rw = q.right and 64 or 0
    local nw = math.max(40, w - x - 8 - 20 - rw - (q.prog and 110 or 0))
    put(b.name, "LEFT", 20, 0, nw, q.name, K.INK, "LEFT", 12)
    if q.prog then put(b.prog, "LEFT", 20 + math.min(nw, ((b.name.GetUnboundedStringWidth or b.name.GetStringWidth)(b.name) or 0)) + 8, 0, 104, q.prog, K.DIM, "LEFT", 11) else b.prog:Hide() end
    if q.right then put(b.right, "RIGHT", 0, 0, rw, q.right, q.rightC or K.DIM, "RIGHT", 11) else b.right:Hide() end
    b.fn, b.tip = q.fn, q.tip
  end
  for i = n + 1, #st.qs do st.qs[i]:Hide() end
  return h
end
-- the level-up rule: where the route's XP crosses a level, a 1 px white line across with "Level 22" on it, the rail
-- going on through
function L.MakeRule(parent)
  local r = CreateFrame("Frame", nil, parent)
  r:SetHeight(L.RULE_H)
  r.rail = flat(r, "BORDER", K.EDGE, 1)
  r.rail:SetWidth(2)
  r.rail:SetPoint("TOPLEFT", 14, 0); r.rail:SetPoint("BOTTOMLEFT", 14, 0)
  r.line = flat(r, "ARTWORK", K.WHITE, 1)
  r.line:SetHeight(1)
  r.line:SetPoint("LEFT", 8, 0); r.line:SetPoint("RIGHT", -8, 0)
  r.plate = flat(r, "OVERLAY", { 0.07, 0.07, 0.07 }, 1)
  r.text = UI.Text(r, 11, K.WHITE, "LEFT")
  return r
end
function L.FillRule(r, w, s)
  r:SetSize(w, L.RULE_H)
  r.text:ClearAllPoints(); r.text:SetPoint("LEFT", 40, 0)
  r.text:SetWidth(90)
  r.text:SetText(s)
  local tw = math.min(90, (r.text.GetUnboundedStringWidth or r.text.GetStringWidth)(r.text) or 60)
  r.plate:ClearAllPoints(); r.plate:SetPoint("LEFT", 34, 0); r.plate:SetSize(tw + 12, 14)
  return L.RULE_H
end

----------------------------------------------------------------------------
-- C. the dungeon card
----------------------------------------------------------------------------
L.CARD_H, L.CARD_H_NARROW = 98, 126
local FACE, FACES = 20, 8
function L.MakeCard(parent)
  local c = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  UI.Skin(c, { 0.11, 0.11, 0.11 }, 1)
  c:SetHighlightTexture(FLAT, "ADD")
  c:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.03)
  c.bar = flat(c, "OVERLAY", K.GROUP, 1)
  c.bar:SetPoint("TOPLEFT", 1, -1); c.bar:SetPoint("BOTTOMLEFT", 1, 1)
  c.bar:SetWidth(2)
  c.art = c:CreateTexture(nil, "ARTWORK")
  c.art:SetPoint("TOPLEFT", 3, -1)
  c.art:SetSize(174, 96)
  c.kind = c:CreateTexture(nil, "OVERLAY")
  c.kind:SetSize(20, 20)
  c.kind:SetPoint("TOPRIGHT", c.art, "TOPRIGHT", -4, -4)
  c.name = UI.Text(c, 15, K.WHITE, "LEFT")
  c.why = UI.Text(c, 11, K.DIM, "LEFT")
  c.lo = UI.Text(c, 11, K.INK, "RIGHT")
  c.hi = UI.Text(c, 11, K.INK, "LEFT")
  c.track = flat(c, "ARTWORK", { 0.16, 0.16, 0.16 }, 1)
  c.track:SetHeight(4)
  c.range = {}
  c.you = flat(c, "OVERLAY", K.WHITE, 1)
  c.you:SetSize(2, 10)
  c.faces = {}
  c.left = UI.Text(c, 11, K.DIM, "LEFT")
  c.qicon = L.MakeSlot(c, 14)
  c.quests = UI.Text(c, 11, K.INK, "LEFT")
  c.drop = L.MakeSlot(c, 20)
  c.mates = {}
  c.invite = UI.Button(c, "Invite", 58, 16)
  c.invite.label:SetFont(UI.FONT, 11, "")
  c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  c:SetScript("OnClick", C.Safe(function(self, which) if self.fn then self.fn(self, which) end end, "card: click"))
  c:SetScript("OnEnter", C.Safe(function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); self.tip(GameTooltip, self); GameTooltip:Show()
  end, "tooltip"))
  c:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return c
end
local function face(c, i)
  local f = c.faces[i]
  if f then return f end
  f = CreateFrame("Frame", nil, c)
  f:SetSize(FACE, FACE)
  f.ring = f:CreateTexture(nil, "BACKGROUND")
  f.ring:SetAllPoints()
  f.ring:SetColorTexture(K.MUTE[1], K.MUTE[2], K.MUTE[3], 1)
  f.hole = f:CreateTexture(nil, "BORDER")
  f.hole:SetPoint("TOPLEFT", 2, -2); f.hole:SetPoint("BOTTOMRIGHT", -2, 2)
  f.hole:SetColorTexture(0.11, 0.11, 0.11, 1)
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetAllPoints()
  if f.CreateMaskTexture then
    for _, t in ipairs({ f.ring, f.hole, f.tex }) do
      local m = f:CreateMaskTexture()
      m:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      m:SetAllPoints(t)
      if t.AddMaskTexture then pcall(t.AddMaskTexture, t, m) end
    end
  end
  f.check = f:CreateTexture(nil, "OVERLAY")
  f.check:SetSize(10, 10)
  f.check:SetPoint("BOTTOMRIGHT", 3, -3)
  L.Paint(f.check, "ready")
  c.faces[i] = f
  return f
end
-- a card filled: it = { name, why (one dim phrase after the name), min, max, level, cover = function(texture, w, h)
-- that paints the art, raid, faces = { { paint = function(texture), state = killed | left | doubted, name } }, left =
-- "4 left", quests = n, drop = a slot's spec, mates = { { name, class } }, invite = { on, why, fn, label }, fn, tip };
-- narrow: the 380 px column's (the foot on its own line); returns its height
function L.FillCard(c, it, w, narrow)
  local h = narrow and L.CARD_H_NARROW or L.CARD_H
  c:SetSize(w, h)
  c.fn, c.tip = it.fn, it.tip
  c.art:SetTexCoord(0, 1, 0, 1)
  if it.cover then it.cover(c.art, 174, 96) else c.art:SetColorTexture(0, 0, 0, 1) end
  L.Paint(c.kind, it.raid and "raid" or "dungeon")
  local x = 182
  local room = w - x - 8
  put(c.name, "TOPLEFT", x, -6, room, it.name, K.WHITE, "LEFT", 15)
  local nw = math.min(room, math.ceil((c.name.GetUnboundedStringWidth or c.name.GetStringWidth)(c.name) or 0))
  if it.why and room - nw > 40 then put(c.why, "TOPLEFT", x + nw + 6, -10, room - nw - 6, it.why, K.DIM, "LEFT", 11) else c.why:Hide() end
  -- the level range: a 4 px track, the range in its difficulty colours against your level, a white tick at yours
  local tw = narrow and 112 or 160
  local lo, hi = it.min, it.max
  for _, t in ipairs(c.range) do t:Hide() end
  if lo and hi and hi >= lo then
    put(c.lo, "TOPLEFT", x, -28, 18, tostring(lo), K.INK, "RIGHT", 11)
    c.track:ClearAllPoints(); c.track:SetPoint("TOPLEFT", x + 22, -33); c.track:SetWidth(tw); c.track:Show()
    local span = hi - lo + 1
    for l = lo, hi do
      local i = l - lo + 1
      local t = c.range[i]
      if not t then t = flat(c, "ARTWORK", K.INK, 1); t:SetHeight(4); c.range[i] = t end
      local a, b = math.floor((l - lo) / span * tw + 0.5), math.floor((l - lo + 1) / span * tw + 0.5)
      local col = L.LevelColor(l)
      t:SetColorTexture(col[1], col[2], col[3], 1)
      t:ClearAllPoints(); t:SetPoint("TOPLEFT", c.track, "TOPLEFT", a, 0); t:SetWidth(math.max(1, b - a))
      t:Show()
    end
    local lv = it.level or lo
    local at = math.floor((math.min(hi + 1, math.max(lo, lv + 0.5)) - lo) / span * tw + 0.5)
    c.you:ClearAllPoints(); c.you:SetPoint("TOPLEFT", c.track, "TOPLEFT", at - 1, 3); c.you:Show()
    put(c.hi, "TOPLEFT", x + 22 + tw + 4, -28, 24, tostring(hi), K.INK, "LEFT", 11)
  else
    c.lo:Hide(); c.hi:Hide(); c.track:Hide(); c.you:Hide()
  end
  -- the bosses: their faces, round, 3 px apart (killed in full colour with the ready check; not killed greyed; doubted a
  -- ring only), and how many are left
  local fit = math.max(0, math.min(FACES, math.floor((room - 60) / (FACE + 3))))
  local fx = x
  for i = 1, math.max(#c.faces, #(it.faces or {})) do
    local fd = it.faces and it.faces[i]
    if fd and i <= fit then
      local f = face(c, i)
      f:ClearAllPoints(); f:SetPoint("TOPLEFT", fx, -46)
      if fd.state == "doubted" then f.tex:Hide(); f.ring:Show(); f.hole:Show()
      else
        f.ring:Hide(); f.hole:Hide()
        if fd.paint then fd.paint(f.tex) else L.Paint(f.tex, "skull") end
        f.tex:SetDesaturated(fd.state ~= "killed")
        f.tex:SetAlpha(fd.state == "killed" and 1 or 0.7)
        f.tex:Show()
      end
      f.check:SetShown(fd.state == "killed")
      f:Show()
      fx = fx + FACE + 3
    elseif c.faces[i] then
      c.faces[i]:Hide()
    end
  end
  if it.left then put(c.left, "TOPLEFT", fx + 4, -50, room - (fx - x) - 4, it.left, K.DIM, "LEFT", 11) else c.left:Hide() end
  -- the foot: the quests for it, the best drop for you, up to four mates in their class colours, Invite
  local fy, fx0 = narrow and -100 or -72, narrow and 8 or x
  local cx = fx0
  if it.quests and it.quests > 0 then
    c.qicon:ClearAllPoints(); c.qicon:SetPoint("TOPLEFT", cx, fy - 1); L.FillSlot(c.qicon, { art = "accept" })
    put(c.quests, "TOPLEFT", cx + 18, fy, 60, it.quests .. (it.quests == 1 and " quest" or " quests"), K.INK, "LEFT", 11)
    cx = cx + 18 + math.min(60, math.ceil((c.quests.GetUnboundedStringWidth or c.quests.GetStringWidth)(c.quests) or 0)) + 8
  else
    c.qicon:Hide(); c.quests:Hide()
  end
  if it.drop then c.drop:ClearAllPoints(); c.drop:SetPoint("TOPLEFT", cx, fy + 4); L.FillSlot(c.drop, it.drop); cx = cx + 28 else c.drop:Hide() end
  local invW = it.invite and 66 or 0
  for i = 1, math.max(#c.mates, #(it.mates or {})) do
    local m = it.mates and it.mates[i]
    local t = c.mates[i]
    if m and i <= 4 then
      if not t then t = UI.Text(c, 11, K.INK, "LEFT"); c.mates[i] = t end
      local mw = math.min(80, w - 8 - invW - cx)
      if mw > 24 then
        put(t, "TOPLEFT", cx, fy, mw, m.name, m.class and UI.ClassColor(m.class) or K.INK, "LEFT", 11)
        cx = cx + math.min(mw, math.ceil((t.GetUnboundedStringWidth or t.GetStringWidth)(t) or 0)) + 6
      else t:Hide() end
    elseif t then t:Hide() end
  end
  if it.invite then
    local b = c.invite
    b:ClearAllPoints(); b:SetPoint("TOPRIGHT", -8, fy + 2)
    b:SetLabel(it.invite.label or "Invite")
    b:SetOn(it.invite.on ~= false)
    b:SetScript("OnClick", C.Safe(function() if it.invite.fn then it.invite.fn() end end, "card: invite"))
    b:SetScript("OnEnter", C.Safe(function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if it.invite.why then GameTooltip:AddLine(it.invite.why, 1, 1, 1, true) end
      GameTooltip:Show()
    end, "tooltip"))
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Show()
  else
    c.invite:Hide()
  end
  return h
end
