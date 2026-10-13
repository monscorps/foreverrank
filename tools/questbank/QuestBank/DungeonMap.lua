-- SPDX-License-Identifier: GPL-3.0-or-later
-- The Dungeon Journal: every dungeon with the Encounter Journal's own cover art, which the client still ships; its
-- bosses with the journal's portraits where it had them and the loot players and the site have recorded, by item id
-- (the client names, colours and slots the items); the floor art of the dungeon; its quests and where you stand with
-- each; a waypoint on the entrance. /qb map opens it, /qb map <name> on a dungeon, and the Map button on a dungeon's
-- card on the Party page. Inside an instance the game hides where you are, so the map is a map, not a tracker.
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
  f.listScroll:SetPoint("TOPLEFT", 4, -4)
  f.listScroll:SetPoint("BOTTOMRIGHT", -4, 4)
  f.listChild = CreateFrame("Frame", nil, f.listScroll)
  f.listChild:SetSize(LIST_W - 8, 10)
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
  f.noArt = fs(f.map, "GameFontNormal", 13, SOFT, math.min(400, 1002 * SCALE - 20), "CENTER")
  f.noArt:SetPoint("CENTER")
  f.noArt:SetText("The client has no map art for this dungeon.")
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
  f.bossList:SetPoint("TOPLEFT", 0, 0); f.bossList:SetPoint("BOTTOMLEFT", 0, 0); f.bossList:SetWidth(200)
  f.bossHead = fs(f.bossList, "GameFontNormal", 12, GOLD, 200)
  f.bossHead:SetPoint("TOPLEFT", 10, -8)
  f.bossHead:SetText("Bosses")
  f.bossRows = {}
  f.lootPanel = panel(f.bossTab, 0.5)
  f.lootPanel:SetPoint("TOPLEFT", f.bossList, "TOPRIGHT", 8, 0); f.lootPanel:SetPoint("BOTTOMRIGHT", 0, 0)
  f.lootFace = f.lootPanel:CreateTexture(nil, "ARTWORK")
  f.lootFace:SetSize(64, 64)
  f.lootFace:SetPoint("TOPLEFT", 12, -10)
  local lootW = detailW - 16 - 208
  f.lootName = fs(f.lootPanel, "GameFontNormalLarge", 16, GOLD, lootW - 96)
  f.lootName:SetPoint("TOPLEFT", 86, -16)
  f.lootSub = fs(f.lootPanel, "GameFontDisableSmall", 11, SOFT, lootW - 96)
  f.lootSub:SetPoint("TOPLEFT", 86, -40)
  f.lootHead = fs(f.lootPanel, "GameFontNormal", 12, INK, lootW - 24)
  f.lootHead:SetPoint("TOPLEFT", 12, -86)
  f.lootRows = {}

  -- quests tab
  f.questTab = CreateFrame("Frame", nil, f.body); f.questTab:SetAllPoints()
  f.questHead = fs(f.questTab, "GameFontNormal", 12, GOLD, 300)
  f.questHead:SetPoint("TOPLEFT", 10, -6)
  f.questRows = {}

  f:SetScript("OnEvent", QB.Safe(function(_, event) if event == "GET_ITEM_INFO_RECEIVED" and f:IsShown() and f.boss then DM.ShowBoss(f.boss) end end, "dungeon journal"))
  pcall(f.RegisterEvent, f, "GET_ITEM_INFO_RECEIVED")
  f.lootW, f.bodyW = lootW, detailW - 16
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
  r:SetSize(LIST_W - 8, ROW_H - 4)
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
  r.name = fs(r, "GameFontNormalLarge", 15, GOLD, LIST_W - 28)
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
  f.noArt:SetShown(not floor)
  for i, b in ipairs(f.floors) do b:SetEnabled(i ~= n); b:SetOn(i == n) end
  DM.DrawPins()
end

-- a boss's face: the client's own portrait of its model where the boss has one (b.d), else the old Encounter
-- Journal's art (b.p, a 128 x 64 picture: the middle is the face), else the journal's default face
local function face(t, b, d, preferArt)
  if b.d and not (preferArt and b.p) and SetPortraitTextureFromCreatureDisplayID and pcall(SetPortraitTextureFromCreatureDisplayID, t, b.d) then
    t:SetTexCoord(0, 1, 0, 1)
    return
  end
  t:SetTexture(b.p or (d and d.defaultFace) or nil)
  t:SetTexCoord(0.2, 0.8, 0.02, 0.98)
end

-- the bosses on the shown floor, as the old Encounter Journal drew them: a round portrait in a gold ring where the
-- boss stands (boss_spots.py places them from the Classic database's spawns on the very same art). Click: the loot
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
    p.mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
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
    local kind = b.k == "boss" and "Boss" or b.k == "rare" and "Rare" or "Trash"
    GameTooltip:AddLine(kind .. (b.l and (" \194\183 level " .. b.l) or "") .. (b.w and (" \194\183 " .. b.w) or ""), 1, 1, 1)
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
  for _, b in ipairs(d and d.bosses or {}) do
    if b.f == f.floor and b.x and b.y and b.k ~= "trash" then
      n = n + 1
      local p = pin(n)
      p.boss = b
      face(p.face, b, d)
      local big = b.k == "boss"
      p.size = big and PIN or PIN - 8
      p:SetSize(p.size, p.size)
      p.face:SetSize(p.size - 4, p.size - 4)
      p.ring:SetVertexColor(big and 1 or 0.75, big and 0.82 or 0.75, big and 0.3 or 0.75, 1)
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
  for i = n + 1, #f.pins do f.pins[i]:Hide() end
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

function DM.ShowBoss(b)
  local f = frame
  f.boss = b
  if b.f and b.f ~= f.floor and f.data and f.data.floors[b.f] then DM.ShowFloor(b.f) end
  for _, r in ipairs(f.bossRows) do if r.hi then r.hi:SetAlpha(r.boss == b and 1 or 0) end end
  face(f.lootFace, b, f.data, true)
  f.lootName:SetText(b.n)
  f.lootSub:SetText((b.k == "boss" and "Boss" or b.k == "rare" and "Rare" or "Trash") .. (b.l and (" \194\183 level " .. b.l) or "") .. (b.w and (" \194\183 " .. b.w) or ""))
  f.lootHead:SetText(#b.i > 0 and string.format("Loot  |  %d items", #b.i) or "Loot  |  nothing recorded yet")
  local y = -108
  for i = 1, math.min(MAX_ITEMS, #b.i) do
    local id = b.i[i]
    local it = DM.Item(id)
    local r = row(f.lootRows, i, f.lootPanel, 38, f.lootW - 20)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 10, y)
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
end

function DM.ShowTab(tab)
  local f = frame
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
  -- bosses
  local y = -28
  for i, b in ipairs(d.bosses) do
    local r = row(f.bossRows, i, f.bossList, 40, 184)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 10, y)
    r.boss = b
    face(r.icon, b, d)
    r.text:SetText(b.n)
    r.sub:SetText((b.k == "boss" and "" or (b.k == "rare" and "Rare" or "Trash")) .. ((b.w and (b.k == "boss" and b.w or (" \194\183 " .. b.w))) or ""))
    r:SetScript("OnClick", function(self) DM.ShowBoss(self.boss) end)
    r:SetScript("OnEnter", nil)
    r:Show()
    y = y - 42
  end
  for i = #d.bosses + 1, #f.bossRows do f.bossRows[i]:Hide() end
  if d.bosses[1] then DM.ShowBoss(d.bosses[1]) else
    f.boss = nil; f.lootFace:SetTexture(nil); f.lootName:SetText("No bosses recorded"); f.lootSub:SetText(""); f.lootHead:SetText("")
    for _, r in ipairs(f.lootRows) do r:Hide() end
  end
  -- quests
  local qs = DM.Quests(cat.key)
  f.questHead:SetText(#qs > 0 and string.format("%d quests", #qs) or "No quests in the catalog for this dungeon")
  y = -28
  for i, e in ipairs(qs) do
    local r = row(f.questRows, i, f.questTab, 34, f.bodyW - 20)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 10, y)
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
  DM.ShowTab(tab or f.tab or (#d.bosses > 0 and "bosses" or "map"))
  DM.FillList()
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
