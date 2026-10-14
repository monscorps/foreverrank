-- SPDX-License-Identifier: GPL-3.0-or-later
-- The Dungeon Journal: every dungeon with the Encounter Journal's own cover art, which the client still ships; its
-- bosses, rares, trash and chests (chips show or hide each kind), each with a face, and the loot players and the site
-- have recorded, by item id (the client names, colours and slots the items); the floor art of the dungeon; its quests
-- and where you stand with each; a waypoint on the entrance. /qb map opens it, /qb map <name> on a dungeon, and the
-- Map button on a dungeon's card on the Party page. Inside an instance the game hides where you are, so the map is a
-- map, not a tracker.
local _, QB = ...
local DM = {}
QB.DMap = DM

local TILE, COLS, ROWS = 256, 4, 3
-- sizes: set when the journal is built into its page of the QuestBank window (build)
local SCALE = 0.5                -- the 1002 x 668 floor art, scaled to fit the page
local W, H = 828, 468
local LIST_W = 220
local COVER_H, BODY_Y = 70, 78
local ROW_H = 68
local BOSS_W, BOSS_H = 216, 42  -- the boss list's width, and a boss's row: its face, its name on one or two lines
local MAX_ITEMS = 12

local ART = "Interface\\AddOns\\QuestBank\\art\\"
local plain = QB.Plain
local DARK = { 0.07, 0.06, 0.05 }
local GOLD = { 1, 0.82, 0.3 }
local INK = { 0.86, 0.8, 0.68 }
local SOFT = { 0.6, 0.55, 0.47 }
local QUALITY = { [0] = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 } }

function DM.Data(key) return QB.Data.DMAP and QB.Data.DMAP[key] or nil end

-- the dungeons with a map or bosses, by name
function DM.List()
  local out = {}
  for _, c in ipairs(QB.Data.CAT) do
    if c.dungeon and DM.Data(c.key) then out[#out + 1] = c end
  end
  table.sort(out, function(a, b)
    local la, lb = DM.Levels(a.key), DM.Levels(b.key)
    if la[1] ~= lb[1] then return la[1] < lb[1] end
    return a.name < b.name
  end)
  return out
end

-- the level range: the loot file's, else the quests'
function DM.Levels(key)
  local d = DM.Data(key)
  if d and d.lv then return d.lv end
  local lo, hi = 99, 0
  for id in pairs(QB.Data.Q) do
    local q = QB.Quest.Get(id)
    if q and q.cat and q.cat.key == key and q.lvl then lo, hi = math.min(lo, q.lvl), math.max(hi, q.lvl) end
  end
  return lo <= hi and { lo, hi } or { 0, 0 }
end

function DM.Find(text)
  text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return nil end
  local best
  for _, c in ipairs(DM.List()) do
    local n = c.name:lower()
    if n == text then return c end
    if n:find(text, 1, true) and (not best or #c.name < #best.name) then best = c end
  end
  return best
end

-- the client's word on an item: name, quality, icon, slot and kind. Asks the server when it does not know yet
local SLOT = { INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder", INVTYPE_BODY = "Shirt", INVTYPE_CHEST = "Chest",
               INVTYPE_ROBE = "Chest", INVTYPE_WAIST = "Waist", INVTYPE_LEGS = "Legs", INVTYPE_FEET = "Feet", INVTYPE_WRIST = "Wrist",
               INVTYPE_HAND = "Hands", INVTYPE_FINGER = "Finger", INVTYPE_TRINKET = "Trinket", INVTYPE_CLOAK = "Back",
               INVTYPE_WEAPON = "One-Hand", INVTYPE_SHIELD = "Shield", INVTYPE_2HWEAPON = "Two-Hand", INVTYPE_WEAPONMAINHAND = "Main Hand",
               INVTYPE_WEAPONOFFHAND = "Off Hand", INVTYPE_HOLDABLE = "Held", INVTYPE_RANGED = "Ranged", INVTYPE_RANGEDRIGHT = "Ranged",
               INVTYPE_THROWN = "Thrown", INVTYPE_RELIC = "Relic", INVTYPE_TABARD = "Tabard", INVTYPE_BAG = "Bag" }
function DM.Item(id)
  local it = { id = id, name = nil, q = 1, icon = nil, slot = nil, kind = nil }
  local CI = C_Item
  if CI and CI.GetItemNameByID then
    local ok, n = pcall(CI.GetItemNameByID, id); if ok then it.name = plain(n) end
  elseif GetItemInfo then
    local ok, n = pcall(GetItemInfo, id); if ok then it.name = plain(n) end
  end
  if CI and CI.GetItemQualityByID then local ok, q = pcall(CI.GetItemQualityByID, id); if ok and type(plain(q)) == "number" then it.q = q end end
  if CI and CI.GetItemIconByID then local ok, i = pcall(CI.GetItemIconByID, id); if ok then it.icon = plain(i) end end
  if CI and CI.GetItemInfoInstant then
    local ok, _, kind, sub, loc = pcall(CI.GetItemInfoInstant, id)
    if ok then it.kind = plain(sub) or plain(kind); it.slot = SLOT[plain(loc) or ""] end
  elseif GetItemInfoInstant then
    local ok, _, kind, sub, loc = pcall(GetItemInfoInstant, id)
    if ok then it.kind = plain(sub) or plain(kind); it.slot = SLOT[plain(loc) or ""] end
  end
  if not it.name and CI and CI.RequestLoadItemDataByID then pcall(CI.RequestLoadItemDataByID, id) end
  it.name = it.name or ("Item " .. id)
  return it
end
function DM.ItemName(id) return DM.Item(id).name end

function DM.Quests(key)
  local out, Q, API = {}, QB.Quest, QB.API
  for id in pairs(QB.Data.Q) do
    local q = Q.Get(id)
    if q and q.cat and q.cat.key == key and Q.ForMe(q) then
      local st = API.IsDone(id) and "done" or (QB.state.log[id] and (QB.state.log[id].complete and "ready" or "log") or "open")
      out[#out + 1] = { q = q, st = st }
    end
  end
  table.sort(out, function(a, b) if a.q.lvl ~= b.q.lvl then return (a.q.lvl or 0) < (b.q.lvl or 0) end return a.q.name < b.q.name end)
  return out
end
local STATUS = { done = { "Done", 0.5, 0.5, 0.5 }, ready = { "Ready to hand in", 0.3, 0.9, 0.3 }, log = { "In your log", 1, 0.82, 0.3 }, open = { "To take", 0.9, 0.9, 0.9 } }

-- what the search box matches: the dungeon's name, a boss, an item the client already names
function DM.Matches(cat, text)
  if not text or text == "" then return true end
  text = text:lower()
  if cat.name:lower():find(text, 1, true) then return true end
  local d = DM.Data(cat.key)
  for _, b in ipairs(d and d.bosses or {}) do
    if b.n:lower():find(text, 1, true) then return true end
    for _, id in ipairs(b.i) do
      local n = DM.Item(id).name
      if n and n:lower():find(text, 1, true) then return true end
    end
  end
  return false
end

-- what an entry is: its chip ("boss", "rare", "trash", or "other" for chests and events) and its word
function DM.Kind(b)
  return (b.k == "boss" or b.k == "rare" or b.k == "trash") and b.k or "other"
end
local WORD = { boss = "Boss", rare = "Rare", trash = "Trash", quest = "Event" }
function DM.KindLabel(b) return WORD[b.k] or "Chest" end

-- the entries the chips let through (djShow), in the list's order: each wing together, the wings as the loot file has
-- them; in a wing the bosses in the game's encounter order (b.o; one the client does not know keeps its place after
-- the entry before it in the loot file), then rares, trash and the rest, each in the loot file's order
local RANK = { boss = 1, rare = 2, trash = 3, other = 4 }
function DM.Visible(d)
  local show = QB:Settings().djShow
  local keys, wing, o = {}, {}, -1
  for i, b in ipairs(d and d.bosses or {}) do
    o = b.o or o
    local w = b.w or ""
    wing[w] = wing[w] or i
    local kind = DM.Kind(b)
    if show[kind] ~= false then keys[#keys + 1] = { b = b, w = wing[w], k = RANK[kind], o = kind == "boss" and o or 0, i = i } end
  end
  table.sort(keys, function(x, y)
    if x.w ~= y.w then return x.w < y.w end
    if x.k ~= y.k then return x.k < y.k end
    if x.o ~= y.o then return x.o < y.o end
    return x.i < y.i
  end)
  local out = {}
  for n, e in ipairs(keys) do out[n] = e.b end
  return out
end

----------------------------------------------------------------------------
-- the frame
----------------------------------------------------------------------------
local frame
local function fs(parent, font, size, color, w, justify)
  local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
  if size and t.SetFont then local f, _, fl = t:GetFont(); if f then t:SetFont(f, size, fl) end end
  if color then t:SetTextColor(color[1], color[2], color[3]) end
  if w then t:SetWidth(w) end
  t:SetJustifyH(justify or "LEFT")
  return t
end
local function panel(parent, alpha)
  local p = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  if p.SetBackdrop then
    p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = false, edgeSize = 10,
                    insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    p:SetBackdropColor(DARK[1], DARK[2], DARK[3], alpha or 0.85)
    p:SetBackdropBorderColor(0.42, 0.33, 0.18, 0.9)
  end
  return p
end

-- a boss's level: one number, or a range ({ 20, 21 }) for a pair that differs
local function levelText(l)
  if type(l) == "table" then return (l[1] and l[2] and l[1] ~= l[2]) and (l[1] .. "-" .. l[2]) or tostring(l[1] or "") end
  return tostring(l)
end
DM.LevelText = levelText

-- an entry's line under its name: its kind, level and wing
local function about(b)
  return DM.KindLabel(b) .. (b.l and (", level " .. levelText(b.l)) or "") .. (b.w and (", " .. b.w) or "")
end

-- a list that scrolls: the wheel, and a slim knob beside it while it runs past the bottom. viewH: the height it shows
-- (known from the page's size, so it holds before the game has laid the frame out)
local function scroller(parent, step, viewH)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(10, 10)
  sf:SetScrollChild(child)
  local bar = CreateFrame("Slider", nil, parent)
  bar:SetOrientation("VERTICAL")
  bar:SetWidth(10)
  bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 2, 0)
  bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 2, 0)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetColorTexture(0.25, 0.17, 0.08, 0.25)
  track:SetPoint("TOPLEFT", 3, 0)
  track:SetPoint("BOTTOMRIGHT", -3, 0)
  local knob = bar:CreateTexture(nil, "OVERLAY")
  knob:SetTexture(QB.Data.TEX.knob)
  knob:SetSize(14, 20)
  bar:SetThumbTexture(knob)
  bar:SetMinMaxValues(0, 0)
  bar:SetValueStep(1)
  bar:SetValue(0)
  bar:Hide()
  bar:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(_, d)
    local lo, hi = bar:GetMinMaxValues()
    bar:SetValue(math.max(lo, math.min(hi, bar:GetValue() - d * step)))
  end)
  sf.child, sf.bar, sf.viewH = child, bar, viewH
  -- the list's full height: the knob runs what does not fit; a new list starts at its top, the same one stays put
  function sf:SetContentHeight(h, keep)
    child:SetHeight(math.max(h, 1))
    local max = math.max(0, h - self.viewH)
    bar:SetMinMaxValues(0, max)
    bar:SetShown(max > 0)
    bar:SetValue(keep and math.min(bar:GetValue(), max) or 0)
  end
  return sf
end

local function pill(parent, label, w)
  local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  b:SetSize(w or 90, 24)
  if b.SetBackdrop then
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    b:SetBackdropColor(0.45, 0.08, 0.06, 0.95)
    b:SetBackdropBorderColor(0.6, 0.45, 0.2, 1)
  end
  b.text = fs(b, "GameFontNormal", 12, INK, w and (w - 8) or 82, "CENTER")
  b.text:SetPoint("CENTER")
  b.text:SetText(label)
  b.SetOn = function(self, on)
    if self.SetBackdropColor then self:SetBackdropColor(on and 0.6 or 0.25, on and 0.12 or 0.06, on and 0.08 or 0.05, 0.95) end
    self.text:SetTextColor(on and 1 or INK[1], on and 0.9 or INK[2], on and 0.6 or INK[3])
  end
  return b
end

----------------------------------------------------------------------------
-- faces
----------------------------------------------------------------------------
-- each kind's icon, the game's own: the boss skull (grey for trash), the nameplates' elite dragon, a chest, the
-- quest-giver's "!" for an event. A file icon loses its rim; an atlas keeps its own part of its file
local ICON = {
  boss = { file = 137025 }, trash = { file = 137025, grey = true }, chest = { file = 132594 },
  rare = { atlas = "nameplates-icon-elite-silver", file = 237678 }, event = { atlas = "QuestNormal", file = QB.Data.TEX.questAvail },
}
local function kindIcon(t, key)
  local i = ICON[key]
  if not QB.Art(t, i.atlas, i.file) then t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  t:SetDesaturated(i.grey or false)
  local v = i.grey and 0.8 or 1
  t:SetVertexColor(v, v, v)
end

-- the textures showing a portrait drawn from a display id, and whose: the client fills such a portrait in once the
-- model has loaded, often after the call, and says so with PORTRAITS_UPDATED (DM.RedrawFaces)
local faced = {}

-- an entry's face, the first of these the client can draw: the old Encounter Journal's art (b.p, a 128 x 64 picture
-- whose middle is the face; a file, never blank), the portrait of its model (b.d), an achievement's boss icon (b.a),
-- its kind's icon, and for a boss the journal's default face. Says which: "p", "d", "a", "kind" or "default"
function DM.Face(t, b, d)
  t:SetDesaturated(false)
  t:SetVertexColor(1, 1, 1)
  local drew
  if b.p then
    t:SetTexture(b.p); t:SetTexCoord(0.2, 0.8, 0.02, 0.98); drew = "p"
  elseif b.d and SetPortraitTextureFromCreatureDisplayID and pcall(SetPortraitTextureFromCreatureDisplayID, t, b.d) then
    t:SetTexCoord(0, 1, 0, 1); drew = "d"
  elseif b.a then
    t:SetTexture(b.a); t:SetTexCoord(0.08, 0.92, 0.08, 0.92); drew = "a"
  elseif DM.Kind(b) == "boss" then
    t:SetTexture(d and d.defaultFace or nil); t:SetTexCoord(0.2, 0.8, 0.02, 0.98); drew = "default"
  else
    kindIcon(t, DM.KindLabel(b):lower()); drew = "kind"
  end
  faced[t] = drew == "d" and b or nil
  return drew
end

-- the portraits drawn again (rows, pins and the loot face), while the page shows. How many
function DM.RedrawFaces()
  if not (frame and frame:IsVisible()) then return 0 end
  local n = 0
  for t, b in pairs(faced) do DM.Face(t, b, frame.data); n = n + 1 end
  return n
end
-- PORTRAITS_UPDATED comes in bursts: one redraw 0.2 s after the first
local redrawing = false
local function redrawSoon()
  if redrawing then return end
  redrawing = true
  C_Timer.After(0.2, QB.Safe(function() redrawing = false; DM.RedrawFaces() end, "dungeon journal"))
end
-- and in case it never comes: a second and three seconds after the page shows or a dungeon opens
local function redrawLater()
  C_Timer.After(1, QB.Safe(DM.RedrawFaces, "dungeon journal"))
  C_Timer.After(3, QB.Safe(DM.RedrawFaces, "dungeon journal"))
end

local function build(page, pw, ph)
  -- the page's size decides the rest: the list on the left, the floor art as large as the detail allows
  W, H = pw or W, ph or H
  local detailW = W - LIST_W - 8 - 4
  local bodyH = H - BODY_Y - 12
  SCALE = math.min((detailW - 24) / 1002, (bodyH - 46) / 668)
  local f = CreateFrame("Frame", "QuestBankDungeonMap", page)
  f:SetAllPoints(page)
  f.sub = fs(f, "GameFontDisableSmall", 10, SOFT, 200, "RIGHT")
  f.sub:SetPoint("BOTTOMRIGHT", -8, -2)
  f.sub:SetText("")

  -- search
  f.search = CreateFrame("EditBox", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f.search:SetSize(LIST_W - 8, 22)
  f.search:SetPoint("TOPLEFT", 4, -4)
  f.search:SetFontObject(ChatFontNormal)
  f.search:SetAutoFocus(false)
  f.search:SetMaxLetters(40)
  if f.search.SetBackdrop then
    f.search:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    f.search:SetBackdropColor(0.1, 0.09, 0.08, 0.9); f.search:SetBackdropBorderColor(0.35, 0.3, 0.2, 1)
  end
  f.search:SetTextInsets(8, 8, 0, 0)
  f.searchHint = fs(f.search, "GameFontDisableSmall", 11, SOFT, LIST_W - 24)
  f.searchHint:SetPoint("LEFT", 8, 0)
  f.searchHint:SetText("Search dungeons, bosses, items...")
  f.search:SetScript("OnTextChanged", function(self) f.searchHint:SetShown(self:GetText() == ""); DM.FillList() end)
  f.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  f.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

  -- the list of dungeons
  f.listPanel = panel(f, 0.6)
  f.listPanel:SetPoint("TOPLEFT", 0, -30)
  f.listPanel:SetPoint("BOTTOMLEFT", 0, 0)
  f.listPanel:SetWidth(LIST_W)
  f.listScroll = CreateFrame("ScrollFrame", nil, f.listPanel)
  f.listScroll:SetPoint("TOPLEFT", 6, -6)
  f.listScroll:SetPoint("BOTTOMRIGHT", -6, 6)
  f.listChild = CreateFrame("Frame", nil, f.listScroll)
  f.listChild:SetSize(LIST_W - 12, 10)
  f.listScroll:SetScrollChild(f.listChild)
  f.listScroll:EnableMouseWheel(true)
  f.listScroll:SetScript("OnMouseWheel", function(self, d)
    local cur = self:GetVerticalScroll() or 0
    local max = math.max(0, (f.listChild:GetHeight() or 0) - (self:GetHeight() or 0))
    self:SetVerticalScroll(math.max(0, math.min(max, cur - d * ROW_H)))
  end)
  f.rows = {}

  -- the detail
  f.detail = panel(f, 0.5)
  f.detail:SetPoint("TOPLEFT", f, "TOPLEFT", LIST_W + 8, 0)
  f.detail:SetPoint("BOTTOMRIGHT", 0, 0)
  f.cover = f.detail:CreateTexture(nil, "BACKGROUND")
  f.cover:SetPoint("TOPLEFT", 3, -3)
  f.cover:SetPoint("TOPRIGHT", -3, -3)
  f.cover:SetHeight(COVER_H)
  f.coverShade = f.detail:CreateTexture(nil, "BORDER")
  f.coverShade:SetAllPoints(f.cover)
  f.coverShade:SetColorTexture(0, 0, 0, 0.45)
  f.name = fs(f.detail, "GameFontNormalHuge", 20, GOLD, detailW - 300)
  f.name:SetPoint("TOPLEFT", 14, -12)
  f.level = fs(f.detail, "GameFontNormal", 12, INK, detailW - 300)
  f.level:SetPoint("TOPLEFT", 14, -38)
  f.where = fs(f.detail, "GameFontDisableSmall", 11, SOFT, detailW - 300)
  f.where:SetPoint("TOPLEFT", 14, -54)
  f.tabs = {}
  for i, name in ipairs({ "Map", "Bosses", "Quests" }) do
    local b = pill(f.detail, name, 84)
    b:SetPoint("TOPRIGHT", -10 - (3 - i) * 88, -12)
    b.tab = name:lower()
    b:SetScript("OnClick", function(self) DM.ShowTab(self.tab) end)
    f.tabs[i] = b
  end
  f.body = CreateFrame("Frame", nil, f.detail)
  f.body:SetPoint("TOPLEFT", 8, -BODY_Y)
  f.body:SetPoint("BOTTOMRIGHT", -8, 8)

  -- map tab
  f.mapTab = CreateFrame("Frame", nil, f.body); f.mapTab:SetAllPoints()
  f.map = CreateFrame("Frame", nil, f.mapTab)
  f.map:SetSize(1002 * SCALE, 668 * SCALE)
  f.map:SetPoint("TOP", 0, -8)
  f.tiles = {}
  for r = 0, ROWS - 1 do
    for c = 0, COLS - 1 do
      local t = f.map:CreateTexture(nil, "BACKGROUND")
      t:SetSize(TILE * SCALE, TILE * SCALE)
      t:SetPoint("TOPLEFT", c * TILE * SCALE, -r * TILE * SCALE)
      f.tiles[#f.tiles + 1] = t
    end
  end
  f.pins = {}
  f.floors = {}
  f.entrance = pill(f.mapTab, "Waypoint: entrance", 150)
  f.entrance:SetPoint("BOTTOMLEFT", 8, 8)
  f.entrance:SetScript("OnClick", QB.Safe(function()
    local e = f.cat and f.cat.entrance
    if e then QB.API.SetWaypoint(e.m, e.x, e.y, f.cat.name .. " entrance") end
  end, "dungeon map"))
  f.floorLabel = fs(f.mapTab, "GameFontNormalSmall", 11, SOFT, 40, "RIGHT")
  f.floorLabel:SetPoint("BOTTOMLEFT", 160, 13)
  f.floorLabel:SetText("Floor")
  -- the art's own tooltip: what the pins are, and why your own dot isn't there
  f.map:EnableMouse(true)
  f.map:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
    GameTooltip:SetText(f.cat and f.cat.name or "Dungeon map", GOLD[1], GOLD[2], GOLD[3])
    GameTooltip:AddLine("Each portrait is a boss where it stands. Click one for its loot.", 1, 1, 1, true)
    GameTooltip:AddLine("The game gives no positions inside dungeons, so you and your party aren't on it.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  f.map:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- bosses tab
  f.bossTab = CreateFrame("Frame", nil, f.body); f.bossTab:SetAllPoints()
  f.bossList = panel(f.bossTab, 0.5)
  f.bossList:SetPoint("TOPLEFT", 0, 0); f.bossList:SetPoint("BOTTOMLEFT", 0, 0); f.bossList:SetWidth(BOSS_W)
  -- the chips over the list, each a kind's icon and its count (the word in the tooltip): a click shows or hides that
  -- kind here and on the map, kept in djShow. Chests and events only where the dungeon has some (DM.FillBosses)
  f.chips = {}
  for i, c in ipairs({ { "boss", "Bosses", "boss" }, { "rare", "Rares", "rare" }, { "trash", "Trash", "trash" }, { "other", "Chests and events", "chest" } }) do
    local b = pill(f.bossList, "", 48)
    b:SetHeight(22)
    b:SetPoint("TOPLEFT", 8 + (i - 1) * 50, -6)
    b.kind, b.word = c[1], c[2]
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 6, 0)
    kindIcon(b.icon, c[3])
    b.text:ClearAllPoints(); b.text:SetPoint("LEFT", 25, 0); b.text:SetWidth(18); b.text:SetJustifyH("LEFT")
    b:SetScript("OnClick", function(self)
      local show = QB:Settings().djShow
      show[self.kind] = show[self.kind] == false
      DM.FillBosses(true); DM.DrawPins()
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(self.word, GOLD[1], GOLD[2], GOLD[3])
      GameTooltip:AddLine(QB:Settings().djShow[self.kind] == false and "Hidden. Click to show." or "Shown. Click to hide.", 1, 1, 1)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.chips[i] = b
  end
  f.bossEmpty = fs(f.bossList, "GameFontDisableSmall", 11, SOFT, BOSS_W - 24)
  f.bossEmpty:SetPoint("TOPLEFT", 12, -38)
  f.bossEmpty:SetText("All hidden by the filter")
  -- the bosses scroll under the chips (Blackrock Depths has 39), as the loot does under the boss
  local bodyH = H - BODY_Y - 8
  f.bossScroll = scroller(f.bossList, BOSS_H + 2, bodyH - 32 - 8)
  f.bossScroll:SetPoint("TOPLEFT", 8, -32)
  f.bossScroll:SetPoint("BOTTOMRIGHT", -20, 8)
  f.bossRows = {}
  f.lootPanel = panel(f.bossTab, 0.5)
  f.lootPanel:SetPoint("TOPLEFT", f.bossList, "TOPRIGHT", 8, 0); f.lootPanel:SetPoint("BOTTOMRIGHT", 0, 0)
  f.lootFace = f.lootPanel:CreateTexture(nil, "ARTWORK")
  f.lootFace:SetSize(64, 64)
  f.lootFace:SetPoint("TOPLEFT", 12, -10)
  -- the face as a live model over the picture (ShowBoss), in the pins' gold ring, which sits on a frame of its own
  -- above the model. The model is kept while the page is away: it is set once a boss
  f.lootModel = CreateFrame("PlayerModel", nil, f.lootPanel)
  f.lootModel:SetAllPoints(f.lootFace)
  pcall(f.lootModel.SetKeepModelOnHide, f.lootModel, true)
  f.lootRing = CreateFrame("Frame", nil, f.lootModel)
  f.lootRing:SetSize(74, 74)
  f.lootRing:SetPoint("CENTER")
  local ring = f.lootRing:CreateTexture(nil, "OVERLAY")
  ring:SetTexture(ART .. "ring")
  ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
  ring:SetAllPoints()
  local lootW = detailW - 16 - BOSS_W - 8
  f.lootName = fs(f.lootPanel, "GameFontNormalLarge", 16, GOLD, lootW - 96)
  f.lootName:SetPoint("TOPLEFT", 86, -16)
  f.lootSub = fs(f.lootPanel, "GameFontDisableSmall", 11, SOFT, lootW - 96)
  f.lootSub:SetPoint("TOPLEFT", 86, -40)
  f.lootHead = fs(f.lootPanel, "GameFontNormal", 12, INK, lootW - 24)
  f.lootHead:SetPoint("TOPLEFT", 12, -86)
  f.lootScroll = scroller(f.lootPanel, 40, bodyH - 106 - 8)
  f.lootScroll:SetPoint("TOPLEFT", 10, -106)
  f.lootScroll:SetPoint("BOTTOMRIGHT", -22, 8)
  f.lootRows = {}

  -- quests tab
  f.questTab = CreateFrame("Frame", nil, f.body); f.questTab:SetAllPoints()
  f.questHead = fs(f.questTab, "GameFontNormal", 12, GOLD, 300)
  f.questHead:SetPoint("TOPLEFT", 10, -6)
  f.questScroll = scroller(f.questTab, 36, bodyH - 28)
  f.questScroll:SetPoint("TOPLEFT", 10, -28)
  f.questScroll:SetPoint("BOTTOMRIGHT", -18, 0)
  f.questRows = {}

  -- an item's name came in: the boss's loot again; a portrait was drawn: the faces again
  f:SetScript("OnEvent", QB.Safe(function(_, event)
    if event == "PORTRAITS_UPDATED" then redrawSoon()
    elseif f:IsShown() and f.boss then DM.ShowBoss(f.boss) end
  end, "dungeon journal"))
  pcall(f.RegisterEvent, f, "GET_ITEM_INFO_RECEIVED")
  pcall(f.RegisterEvent, f, "PORTRAITS_UPDATED")
  f:SetScript("OnShow", redrawLater)
  -- the rows' widths: each list's scroll frame, less the knob beside it
  f.lootW, f.bodyW = lootW, detailW - 16
  f.bossRowW, f.lootRowW, f.questRowW = BOSS_W - 8 - 20, lootW + 4 - 10 - 22, detailW - 16 + 4 - 10 - 18
  return f
end

----------------------------------------------------------------------------
-- the list
----------------------------------------------------------------------------
local function listRow(i)
  local f = frame
  local r = f.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, f.listChild, BackdropTemplateMixin and "BackdropTemplate" or nil)
  r:SetSize(LIST_W - 12, ROW_H - 4)
  r.art = r:CreateTexture(nil, "BACKGROUND")
  r.art:SetAllPoints()
  r.shade = r:CreateTexture(nil, "BORDER")
  r.shade:SetAllPoints()
  r.shade:SetColorTexture(0, 0, 0, 0.35)
  if r.SetBackdrop then
    r:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    r:SetBackdropBorderColor(0.3, 0.24, 0.14, 0.9)
  end
  r.hi = r:CreateTexture(nil, "HIGHLIGHT")
  r.hi:SetAllPoints()
  r.hi:SetColorTexture(1, 0.82, 0.3, 0.08)
  r.name = fs(r, "GameFontNormalLarge", 15, GOLD, LIST_W - 32)
  r.name:SetPoint("TOPLEFT", 10, -8)
  r.lv = fs(r, "GameFontHighlightSmall", 10, INK, 80)
  r.lv:SetPoint("BOTTOMLEFT", 10, 7)
  r.quests = fs(r, "GameFontHighlightSmall", 10, INK, 90, "RIGHT")
  r.quests:SetPoint("BOTTOMRIGHT", -8, 7)
  r:SetScript("OnClick", function(self) DM.Open(self.cat) end)
  f.rows[i] = r
  return r
end

function DM.FillList()
  local f = frame
  if not f then return end
  local text = f.search and f.search:GetText() or ""
  local y, n = 0, 0
  for _, cat in ipairs(DM.List()) do
    if DM.Matches(cat, text) then
      n = n + 1
      local r = listRow(n)
      local d = DM.Data(cat.key) or {}
      r.cat = cat
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 0, -y)
      if d.cover then r.art:SetTexture(d.cover) elseif cat.bg then r.art:SetTexture(cat.bg) else r.art:SetTexture(nil) end
      r.art:SetTexCoord(0, 1, 0, 1)
      r.name:SetText(cat.name)
      local lv = DM.Levels(cat.key)
      r.lv:SetText(lv[1] > 0 and string.format("LV %d-%d", lv[1], lv[2]) or "")
      local qn = #DM.Quests(cat.key)
      r.quests:SetText(qn > 0 and (qn .. (qn == 1 and " quest" or " quests")) or "")
      if r.SetBackdropBorderColor then
        local on = f.cat == cat
        r:SetBackdropBorderColor(on and 1 or 0.3, on and 0.82 or 0.24, on and 0.3 or 0.14, 0.9)
      end
      r:Show()
      y = y + ROW_H
    end
  end
  for i = n + 1, #f.rows do f.rows[i]:Hide() end
  f.listChild:SetHeight(math.max(y, 10))
end

----------------------------------------------------------------------------
-- the detail
----------------------------------------------------------------------------
function DM.ShowFloor(n)
  local f = frame
  local d = f.data
  local floor = d and d.floors and d.floors[n]
  f.floor = n
  for i, t in ipairs(f.tiles) do
    if floor and floor[i] then t:SetTexture(floor[i]); t:Show() else t:Hide() end
  end
  for i, b in ipairs(f.floors) do b:SetEnabled(i ~= n); b:SetOn(i == n) end
  DM.DrawPins()
end

-- the entries on the shown floor, as the old Encounter Journal drew them: a round face in a ring where each stands
-- (boss_spots.py places them from the Classic database's spawns on the very same art). Click: the loot
local PIN = 30
local function pin(i)
  local f = frame
  local p = f.pins[i]
  if p then return p end
  p = CreateFrame("Button", nil, f.map)
  p:SetSize(PIN, PIN)
  p:SetFrameLevel(f.map:GetFrameLevel() + 5)
  p.shadow = p:CreateTexture(nil, "BACKGROUND")
  p.shadow:SetTexture(ART .. "glow")
  p.shadow:SetVertexColor(0, 0, 0, 0.8)
  p.shadow:SetPoint("CENTER")
  p.shadow:SetSize(PIN + 16, PIN + 16)
  p.face = p:CreateTexture(nil, "ARTWORK")
  p.face:SetPoint("CENTER")
  p.face:SetSize(PIN - 4, PIN - 4)
  p.mask = p.CreateMaskTexture and p:CreateMaskTexture() or nil
  if p.mask then
    p.mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    p.mask:SetAllPoints(p.face)
    pcall(p.face.AddMaskTexture, p.face, p.mask)
  end
  p.ring = p:CreateTexture(nil, "OVERLAY")
  p.ring:SetTexture(ART .. "ring")
  p.ring:SetAllPoints()
  p.hi = p:CreateTexture(nil, "HIGHLIGHT")
  p.hi:SetTexture(ART .. "glow")
  p.hi:SetVertexColor(1, 0.82, 0.3, 0.6)
  p.hi:SetPoint("CENTER")
  p.hi:SetSize(PIN + 14, PIN + 14)
  p:SetScript("OnEnter", function(self)
    local b = self.boss
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(b.n, GOLD[1], GOLD[2], GOLD[3])
    GameTooltip:AddLine(about(b), 1, 1, 1)
    GameTooltip:AddLine(#b.i > 0 and string.format("%d item%s of loot. Click to see them.", #b.i, #b.i == 1 and "" or "s") or "No loot recorded yet.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  p:SetScript("OnClick", function(self) DM.ShowBoss(self.boss); DM.ShowTab("bosses") end)
  f.pins[i] = p
  return p
end

function DM.DrawPins()
  local f = frame
  local d, n = f.data, 0
  local mw, mh = f.map:GetWidth(), f.map:GetHeight()
  local at = {}
  for _, b in ipairs(DM.Visible(d)) do
    if b.f == f.floor and b.x and b.y then
      n = n + 1
      local p = pin(n)
      p.boss = b
      DM.Face(p.face, b, d)
      -- a boss in a big gold ring, trash in a small grey one, the rest silver between
      local kind = DM.Kind(b)
      p.size = kind == "boss" and PIN or kind == "trash" and PIN - 12 or PIN - 8
      p:SetSize(p.size, p.size)
      p.face:SetSize(p.size - 4, p.size - 4)
      local v = kind == "trash" and 0.55 or 0.75
      if kind == "boss" then p.ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1) else p.ring:SetVertexColor(v, v, v, 1) end
      at[n] = { b.x * mw, b.y * mh, p.size }
      p:Show()
    end
  end
  -- bosses that stand close (Greenskin and Cookie on the ship) are pushed apart until their portraits only touch
  for _ = 1, 60 do
    local moved = false
    for i = 1, n do
      for j = i + 1, n do
        local a, c = at[i], at[j]
        local dx, dy = c[1] - a[1], c[2] - a[2]
        local dist, need = math.sqrt(dx * dx + dy * dy), (a[3] + c[3]) / 2 + 1
        if dist < need then
          if dist < 0.01 then dx, dy, dist = 1, 0, 1 end
          local push = (need - dist) / 2
          a[1], a[2] = a[1] - dx / dist * push, a[2] - dy / dist * push
          c[1], c[2] = c[1] + dx / dist * push, c[2] + dy / dist * push
          moved = true
        end
      end
    end
    if not moved then break end
  end
  for i = 1, n do
    local p, a = f.pins[i], at[i]
    p:ClearAllPoints()
    p:SetPoint("CENTER", f.map, "TOPLEFT", math.max(a[3] / 2, math.min(mw - a[3] / 2, a[1])), -math.max(a[3] / 2, math.min(mh - a[3] / 2, a[2])))
  end
  for i = n + 1, #f.pins do f.pins[i]:Hide(); faced[f.pins[i].face] = nil end
  f.pinCount = n
end

local function row(list, i, parent, height, w)
  local r = list[i]
  if r then return r end
  r = CreateFrame("Button", nil, parent)
  r:SetSize(w or 220, height)
  r.hi = r:CreateTexture(nil, "HIGHLIGHT")
  r.hi:SetAllPoints()
  r.hi:SetColorTexture(1, 0.82, 0.3, 0.08)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(height - 6, height - 6)
  r.icon:SetPoint("LEFT", 4, 0)
  r.text = fs(r, "GameFontHighlight", 12, INK, (w or 220) - height - 12)
  r.text:SetPoint("TOPLEFT", height + 4, -5)
  r.sub = fs(r, "GameFontDisableSmall", 10, SOFT, (w or 220) - height - 12)
  r.sub:SetPoint("TOPLEFT", height + 4, -21)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  list[i] = r
  return r
end

-- a boss's row: a long name takes two lines and the wing or kind sits under it, the pair centred on the face (a
-- second line ran into the wing's name)
local function fitRow(r, h)
  local width = r.text.GetUnboundedStringWidth or r.text.GetStringWidth -- (the text's whole width, not its box's)
  local lines = width(r.text) > r.text:GetWidth() and 2 or 1
  local sub = (r.sub:GetText() or "") ~= ""
  local top = math.floor((h - lines * 14 - (sub and 12 or 0)) / 2)
  r.text:ClearAllPoints(); r.text:SetPoint("TOPLEFT", h + 4, -top)
  r.sub:ClearAllPoints(); r.sub:SetPoint("TOPLEFT", h + 4, -top - lines * 14)
end

function DM.ShowBoss(b)
  local f = frame
  local same = f.boss == b -- (the item names coming in redraw the same boss: its list keeps its place)
  f.boss = b
  if b.f and b.f ~= f.floor and f.data and f.data.floors[b.f] then DM.ShowFloor(b.f) end
  for _, r in ipairs(f.bossRows) do if r.hi then r.hi:SetAlpha(r.boss == b and 1 or 0) end end
  DM.Face(f.lootFace, b, f.data)
  -- the face as a live model where there is one (b.d, else the creature b.c, which the server may not have sent: the
  -- picture stays under it); it draws itself once loaded. Set once a boss, not again as item names come in
  if not same then
    local m, live = f.lootModel, b.d or b.c
    m:SetShown(live ~= nil)
    if b.d then pcall(m.SetDisplayInfo, m, b.d) elseif b.c then pcall(m.SetCreature, m, b.c) else pcall(m.ClearModel, m) end
    if live then pcall(m.SetPortraitZoom, m, 0.6) end
  end
  f.lootFace:SetShown(not b.d)
  f.lootName:SetText(b.n)
  f.lootSub:SetText(about(b))
  f.lootHead:SetText(#b.i > 0 and string.format("Loot  |  %d items", #b.i) or "Loot  |  nothing recorded yet")
  local y = 0
  for i = 1, math.min(MAX_ITEMS, #b.i) do
    local id = b.i[i]
    local it = DM.Item(id)
    local r = row(f.lootRows, i, f.lootScroll.child, 38, f.lootRowW)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, y)
    r.id = id
    r.icon:SetTexture(it.icon or 134400) -- (the question-mark icon until the client knows)
    local qc = QUALITY[it.q] or QUALITY[1]
    r.text:SetText(it.name)
    r.text:SetTextColor(qc[1], qc[2], qc[3])
    local parts = {}
    if it.slot then parts[#parts + 1] = it.slot end
    if it.kind and it.kind ~= it.slot then parts[#parts + 1] = it.kind end
    r.sub:SetText(table.concat(parts, ", "))
    r:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, self.id) else GameTooltip:SetText(DM.Item(self.id).name) end
      GameTooltip:Show()
    end)
    r:SetScript("OnClick", function(self)
      if IsShiftKeyDown and IsShiftKeyDown() and QB.UI and QB.UI.LinkItem then QB.UI.LinkItem(self.id) end
    end)
    r:Show()
    y = y - 40
  end
  for i = math.min(MAX_ITEMS, #b.i) + 1, #f.lootRows do f.lootRows[i]:Hide() end
  f.lootScroll.child:SetWidth(f.lootRowW)
  f.lootScroll:SetContentHeight(-y - 2, same)
end

-- the loot panel with no entry to show, and why
local function noBoss(why)
  local f = frame
  f.boss = nil
  f.lootModel:Hide()
  f.lootFace:SetTexture(nil); f.lootFace:Show(); faced[f.lootFace] = nil
  f.lootName:SetText(why); f.lootSub:SetText(""); f.lootHead:SetText("")
  f.lootScroll:SetContentHeight(0)
  for _, r in ipairs(f.lootRows) do r:Hide() end
end

-- a row of the boss list: a row with a badge on the face's corner
local function bossRow(i)
  local f = frame
  local r = row(f.bossRows, i, f.bossScroll.child, BOSS_H, f.bossRowW)
  if not r.badge then
    r.badge = r:CreateTexture(nil, "OVERLAY")
    r.badge:SetSize(16, 16)
    r.badge:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 3, -1)
  end
  return r
end

-- the boss list: the entries the chips let through, a line when they hide them all, the chips' counts; then the loot
-- of the entry shown before while it is still listed (keep: a chip's click), else of the first
function DM.FillBosses(keep)
  local f = frame
  local d = f.data
  local list, y, still = DM.Visible(d), 0, false
  for i, b in ipairs(list) do
    local r = bossRow(i)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, y)
    r.boss = b
    -- a rare or an event wears its kind on the face's corner, unless the face is that icon already
    local drew, key = DM.Face(r.icon, b, d), DM.KindLabel(b):lower()
    local badge = (key == "rare" or key == "event") and drew ~= "kind"
    if badge then kindIcon(r.badge, key) end
    r.badge:SetShown(badge)
    r.text:SetText(b.n)
    r.sub:SetText(b.w or (b.l and ("Level " .. levelText(b.l))) or "")
    fitRow(r, BOSS_H)
    r:SetScript("OnClick", function(self) DM.ShowBoss(self.boss) end)
    r:SetScript("OnEnter", nil)
    r:Show()
    y = y - BOSS_H - 2
    still = still or b == f.boss
  end
  for i = #list + 1, #f.bossRows do f.bossRows[i]:Hide(); faced[f.bossRows[i].icon] = nil end
  f.bossScroll.child:SetWidth(f.bossRowW)
  f.bossScroll:SetContentHeight(-y - 2)
  f.bossEmpty:SetShown(#list == 0 and #d.bosses > 0)
  local count, show = {}, QB:Settings().djShow
  for _, b in ipairs(d.bosses) do local k = DM.Kind(b); count[k] = (count[k] or 0) + 1 end
  for _, c in ipairs(f.chips) do
    local on = show[c.kind] ~= false
    c.text:SetText(tostring(count[c.kind] or 0))
    c:SetShown(c.kind ~= "other" or (count.other or 0) > 0)
    c:SetOn(on)
    c:SetAlpha(on and 1 or 0.45)
    c.icon:SetDesaturated(not on or c.kind == "trash")
  end
  if keep and still then DM.ShowBoss(f.boss)
  elseif list[1] then DM.ShowBoss(list[1])
  else noBoss(#d.bosses > 0 and "" or "No bosses recorded") end
end

function DM.ShowTab(tab)
  local f = frame
  -- a dungeon the client has no floor art for has no Map tab: its bosses instead
  if tab == "map" and #f.data.floors == 0 then tab = "bosses" end
  f.tab = tab
  f.mapTab:SetShown(tab == "map"); f.bossTab:SetShown(tab == "bosses"); f.questTab:SetShown(tab == "quests")
  for _, b in ipairs(f.tabs) do b:SetOn(b.tab == tab) end
end

-- the journal is a page of the QuestBank window (UI.lua, page 7): built the first time the page shows, to its size
function DM.Attach(page, w, h)
  frame = frame or build(page, w, h)
  return frame
end

-- the page's refresh: a dungeon the first time, else the list's quest counts
function DM.Refresh()
  if not frame then return end
  if frame.cat then DM.FillList() else
    local list = DM.List()
    if list[1] then DM.Fill(list[1]) end
  end
end

-- open the journal's page on a dungeon (and a tab: "map", "bosses" or "quests")
function DM.Open(cat, tab)
  if QB.UI and QB.UI.Open then QB.UI:Open(7) end
  if not frame then return nil end
  return DM.Fill(cat, tab)
end

function DM.Fill(cat, tab)
  local f = frame
  local d = DM.Data(cat.key) or { floors = {}, bosses = {} }
  f.cat, f.data = cat, d
  f.name:SetText(cat.name)
  local lv = DM.Levels(cat.key)
  f.level:SetText(lv[1] > 0 and string.format("LV %d-%d", lv[1], lv[2]) or "")
  f.where:SetText(cat.where and cat.where ~= "" and cat.where or "")
  if d.cover then f.cover:SetTexture(d.cover) elseif cat.bg then f.cover:SetTexture(cat.bg) else f.cover:SetTexture(nil) end
  f.tabs[1]:SetShown(#d.floors > 0)
  -- floors
  for i = 1, math.max(#d.floors, #f.floors) do
    local b = f.floors[i]
    if not b and i <= #d.floors then
      b = pill(f.mapTab, tostring(i), 34)
      b:SetPoint("BOTTOMLEFT", f.mapTab, "BOTTOMLEFT", 206 + (i - 1) * 38, 8)
      b.n = i
      b:SetScript("OnClick", function(self) DM.ShowFloor(self.n) end)
      f.floors[i] = b
    end
    if b then b:SetShown(i <= #d.floors and #d.floors > 1) end
  end
  f.floorLabel:SetShown(#d.floors > 1)
  DM.ShowFloor(1)
  f.entrance:SetShown(cat.entrance ~= nil)
  DM.FillBosses()
  -- quests
  local qs = DM.Quests(cat.key)
  f.questHead:SetText(#qs > 0 and string.format("%d quests", #qs) or "No quests in the catalog for this dungeon")
  local y = 0
  for i, e in ipairs(qs) do
    local r = row(f.questRows, i, f.questScroll.child, 34, f.questRowW)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, y)
    r.q = e.q
    r.icon:SetTexture(e.q.icon or 136797)
    local st = STATUS[e.st]
    r.text:SetText(string.format("%s  |cff9a8a70L%d|r", e.q.name, e.q.lvl or 0))
    r.sub:SetText(st[1])
    r.sub:SetTextColor(st[2], st[3], st[4])
    r:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if QB.UI and QB.UI.QuestTooltip then QB.UI.QuestTooltip(GameTooltip, self.q, QB:Status(self.q)) else GameTooltip:SetText(self.q.name) end
      GameTooltip:Show()
    end)
    r:SetScript("OnClick", function(self) if QB.UI and QB.UI.QuestMenu then QB.UI.QuestMenu(self.q) end end)
    r:Show()
    y = y - 36
  end
  for i = #qs + 1, #f.questRows do f.questRows[i]:Hide() end
  f.questScroll.child:SetWidth(f.questRowW)
  f.questScroll:SetContentHeight(-y - 2)
  DM.ShowTab(tab or f.tab or (#d.bosses > 0 and "bosses" or "map"))
  DM.FillList()
  redrawLater()
  return f
end

local function onPage() return QB.UI and QB.UI.frame and QB.UI.frame:IsShown() and QB.UI.tab == 7 end

-- the Map button on a dungeon's card: the journal on that dungeon, or back to where you were when it already is
function DM.Toggle(cat)
  if onPage() and frame and frame.cat == cat then QB.UI:ShowTab(QB.UI.lastTab or 4) else DM.Open(cat) end
end

-- /qb map [name]: the journal, on a dungeon when one is named
function DM.Command(rest)
  if rest and rest ~= "" then
    local cat = DM.Find(rest)
    if cat then DM.Open(cat) else QB:Print("No dungeon called '" .. rest .. "'. /qb map opens the journal.") end
    return
  end
  if onPage() then QB.UI.frame:Hide(); return end
  local list = DM.List()
  if list[1] then DM.Open(frame and frame.cat or list[1]) end
end
