-- SPDX-License-Identifier: GPL-3.0-or-later
-- The window: one frame with five pages and Settings.
--   Race           every member as a row: level, XP, zone, pace, the leveling stats
--   Prog           attunements, item level, consumables, buffs, readiness
--   Hall of Shame  a card per funny stat with its leader
--   Officers       summaries, the officers' stats, the controls (officer ranks only)
--   Me             your whole record, with what members see
-- Columns and cards come from the registry (Stats.lua); the policy (Policy.lua) decides which cells a member sees.
-- Built on first open, rows are pooled, nothing updates while it is hidden.
local _, C = ...
local UI = { page = "race", sort = {} }
C.UI = UI

local W, H = 1040, 640
local MIN_W, MIN_H = 760, 420
local HEAD = 64          -- the header strip
local TABS = 28          -- the tab row
local ROW = 22
local NAME_W = 150
local INK = { 0.93, 0.88, 0.78 }
local INK_SOFT = { 0.62, 0.58, 0.50 }
local GOLD = { 0.91, 0.70, 0.29 }     -- #e8b24a
local TEAL = { 0.18, 0.54, 0.54 }     -- #2f8a8a
local GOOD = { 0.42, 0.86, 0.45 }
local WARN = { 0.95, 0.72, 0.30 }
local BAD = { 0.90, 0.38, 0.32 }
local SLATE = { 0.105, 0.137, 0.188 } -- #1b2330
local SLATE2 = { 0.14, 0.19, 0.26 }   -- #243042
local EDGE = "Interface\\DialogFrame\\UI-DialogBox-Border"
local FLAT = "Interface\\Buttons\\WHITE8x8"
local LOGO = "Interface\\AddOns\\Cute\\art\\logo"
local LOGO_WIDE = "Interface\\AddOns\\Cute\\art\\logo_wide"
local BD = BackdropTemplateMixin and "BackdropTemplate" or nil

local function hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end
local function classColor(class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return { c.r, c.g, c.b } end
  return INK
end

----------------------------------------------------------------------------
-- small builders
----------------------------------------------------------------------------
local function tex(parent, layer, file, w, h)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  if file then t:SetTexture(file) end
  if w then t:SetSize(w, h or w) end
  return t
end
local function flat(parent, layer, color, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(color[1], color[2], color[3], a or 1)
  return t
end
local function text(parent, obj, size, color, justify, width)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  local fo = _G[obj] or GameFontNormal
  fs:SetFontObject(fo)
  if size then
    local path, _, flags = fo:GetFont()
    if path then fs:SetFont(path, size, flags) end
  end
  if color then fs:SetTextColor(color[1], color[2], color[3]) end
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  if width then fs:SetWidth(width) end
  return fs
end
local function backdrop(frame, bg, edge, edgeSize, inset)
  if not frame.SetBackdrop then return end
  frame:SetBackdrop({ bgFile = bg, edgeFile = edge, tile = false, tileSize = 32, edgeSize = edgeSize,
    insets = { left = inset, right = inset, top = inset, bottom = inset } })
end
local function button(parent, label, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 110, 22)
  b:SetText(label)
  return b
end
local function tooltip(owner, fill)
  owner:SetScript("OnEnter", C.Safe(function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    fill(GameTooltip, self)
    GameTooltip:Show()
  end, "tooltip"))
  owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
-- a label cut after a whole word with "..." when it is wider than its box
local function fitText(fs, s, room)
  room = room or (fs:GetWidth() - 4)
  local width = fs.GetUnboundedStringWidth or fs.GetStringWidth
  fs:SetText(s)
  if width(fs) <= room then return end
  local cut = s
  while true do
    local shorter = cut:match("^(.*%S)%s+%S+$")
    if not shorter then break end
    cut = shorter
    fs:SetText(cut .. "...")
    if width(fs) <= room then return end
  end
  -- one word too wide: letters go
  while #cut > 1 do
    cut = cut:sub(1, -2)
    fs:SetText(cut .. "...")
    if width(fs) <= room then return end
  end
end
UI.FitText = fitText

local function pool(parent, make)
  local p = { items = {}, used = 0 }
  function p:Get()
    self.used = self.used + 1
    local it = self.items[self.used]
    if not it then it = make(parent, self.used); self.items[self.used] = it end
    it:Show()
    return it
  end
  function p:Reset() self.used = 0 end
  function p:HideRest() for i = self.used + 1, #self.items do self.items[i]:Hide() end end
  return p
end

-- ScrollFrame with a child and a knob
local function scrollArea(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  sf:SetPoint("TOPLEFT", 8, -6)
  sf:SetPoint("BOTTOMRIGHT", -26, 6)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(100, 10)
  sf:SetScrollChild(child)
  local bar = CreateFrame("Slider", nil, parent)
  bar:SetOrientation("VERTICAL")
  bar:SetPoint("TOPRIGHT", -10, -10)
  bar:SetPoint("BOTTOMRIGHT", -10, 10)
  bar:SetWidth(14)
  local track = flat(bar, "BACKGROUND", GOLD, 0.15)
  track:SetPoint("TOPLEFT", 4, 0)
  track:SetPoint("BOTTOMRIGHT", -4, 0)
  local knob = tex(bar, "OVERLAY", "Interface\\Buttons\\UI-ScrollBar-Knob", 18, 24)
  bar:SetThumbTexture(knob)
  bar:SetMinMaxValues(0, 0)
  bar:SetValueStep(1)
  bar:SetValue(0)
  bar:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(_, delta)
    local lo, hi = bar:GetMinMaxValues()
    bar:SetValue(math.max(lo, math.min(hi, bar:GetValue() - delta * 44)))
  end)
  sf:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then child:SetWidth(w) end end)
  sf.child, sf.bar = child, bar
  function sf:SetContentHeight(h)
    child:SetHeight(math.max(h, 1))
    local view = self:GetHeight() or 0
    if view < 50 then view = (UI.frame:GetHeight() or H) - HEAD - TABS - 40 end
    local max = math.max(0, h - view)
    bar:SetMinMaxValues(0, max)
    bar:SetShown(max > 0)
    if bar:GetValue() > max then bar:SetValue(max) end
  end
  function sf:Width()
    local w = self:GetWidth() or 0
    if w < 100 then w = (UI.frame:GetWidth() or W) - 16 - 26 - 8 end
    return w
  end
  return sf
end

----------------------------------------------------------------------------
-- values: how a stat shows in a cell, and in a tooltip
----------------------------------------------------------------------------
local function listCount(def, v)
  if type(v) ~= "table" then return nil end
  local n = 0
  for _, e in ipairs(def.of) do if v[e[1]] then n = n + 1 end end
  return n
end
local function listNames(def, v)
  local names = {}
  if type(v) ~= "table" then return names end
  for _, e in ipairs(def.of) do if v[e[1]] then names[#names + 1] = e[2] end end
  return names
end
function UI.Format(def, v)
  if v == nil then return "?" end
  if def.kind == "int" then
    if def.fmt then return def.fmt(v) end
    if type(v) ~= "number" then return "?" end
    if def.id == "last_login" then return v > 0 and (date and date("%d %b", v) or tostring(v)) or "-" end
    if v >= 100000 then return string.format("%.0fk", v / 1000) end
    return tostring(v)
  elseif def.kind == "flag" then return v and "yes" or "-"
  elseif def.kind == "text" then return (type(v) == "string" and v ~= "") and v or "-"
  elseif def.kind == "list" then local n = listCount(def, v); return n and string.format("%d/%d", n, #def.of) or "?"
  elseif def.kind == "pips" then return type(v) == "string" and v or "?" end
  return tostring(v)
end
local function ago(t)
  if not t then return nil end
  local d = C.Now() - t
  if d < 90 then return "just now" end
  if d < 5400 then return string.format("%d min ago", math.floor(d / 60)) end
  if d < 172800 then return string.format("%d h ago", math.floor(d / 3600)) end
  return string.format("%d days ago", math.floor(d / 86400))
end
UI.Ago = ago
local PIP_COLOR = { [0] = { 0.35, 0.35, 0.38 }, [1] = WARN, [2] = GOOD, [3] = GOOD, [4] = GOOD, [5] = TEAL, [6] = TEAL, [7] = GOLD, [8] = GOLD }

-- a column header's short form, where the label would not fit a column
local SHORT = { xp = "XP %", xp_hour = "XP/h", xp_session = "XP/h today", to60 = "To 60", played = "Played", played_lvl = "This lvl", rested = "Rested",
  group = "Group", quests_done = "Quests", quests_today = "Today", quests_log = "In log", quests_ready = "Ready", deaths_lvl = "Deaths", legacy = "Legacy",
  flights_known = "Flights", longest_flight = "Flight", hearth = "Hearth", hearths = "Hearths", ghost_time = "Ghost", gold_earned = "Earned", gold_quests = "Quest gold",
  vendor_sales = "Sold", talents_free = "Talents", zones_seen = "Zones", logins = "Logins", longest = "Longest", levelups = "Lvl-ups", still = "Stood still",
  ilvl = "iLvl", ilvl_slots = "Slots", empty_slots = "Empty", unenchanted = "No ench", old_gear = "Old gear", greens = "Greens", attune_mc = "MC", attune_ony_a = "Ony (A)",
  attune_ony_h = "Ony (H)", resist_fire = "FR", resist_nature = "NR", resist_frost = "FrR", resist_shadow = "SR", resist_arcane = "AR", raid_recipes = "Raid rec.",
  bags_free = "Bags free", bags_size = "Bags", pot_health = "HP pots", pot_mana = "MP pots", protpots = "Prot pots", world_buffs = "World", flask_on = "Flask",
  buffs_missing = "Missing", durability = "Dura", rep = "Rep", pvp_rank = "PvP", honor_week = "Honor", lockouts = "Locks", raids = "Raids", stones = "Stones",
  bank_in = "Bank in", bank_out = "Bank out", consumed = "Consumed", addon_ver = "Version", main = "Main", last_login = "Last login", raid_spec = "Raid spec",
  weekly_raids = "Raids/wk", ontime = "On time", deaths_today = "Today", hearth_waste = "Wasted HS", whispers = "Whispers/h", gchat = "Guild lines", inspected = "Inspected",
  ghost_yards = "Ghost yds", where = "Where r u", grey_gold = "Grey gold" }
UI.SHORT = SHORT
local function shortLabel(def) return SHORT[def.id] or def.label end

-- the width a column takes
local function colWidth(def)
  if def.kind == "flag" then return 44 end
  if def.kind == "text" then return 110 end
  if def.kind == "list" then return 62 end
  if def.kind == "pips" then return 8 + 7 * (def.pips or 8) end
  if def.fmt == C.Stats.FmtHours then return 70 end
  return math.max(56, 12 + #shortLabel(def) * 7)
end

----------------------------------------------------------------------------
-- which columns a page shows: the registry's category, filtered by the viewer's checklist (Settings), cut to what
-- fits the window
----------------------------------------------------------------------------
local DEFAULT_COLS = {
  race = { "level", "xp", "xp_hour", "to60", "zone", "played", "quests_done", "deaths_lvl", "group", "rested", "legacy" },
  prog = { "ilvl", "attune_mc", "attune_ony_a", "attune_ony_h", "keys", "resist_fire", "flasks", "pot_health", "pot_mana", "world_buffs", "durability", "rep", "unenchanted", "empty_slots" },
  officers = { "gold", "bank_in", "bank_out", "raids", "weekly_raids", "consumed", "main", "role", "last_login", "addon_ver" },
}
UI.DEFAULT_COLS = DEFAULT_COLS
local CAT_OF_PAGE = { race = "leveling", prog = "prog", officers = "officer", shame = "funny" }
UI.CAT_OF_PAGE = CAT_OF_PAGE

-- the ids ticked for a page (the default when the player never touched the checklist)
function UI.Ticked(page)
  local cols = C.Settings().columns[page]
  if cols then return cols end
  local set = {}
  for _, id in ipairs(DEFAULT_COLS[page] or {}) do set[id] = true end
  if page == "shame" then for _, def in ipairs(C.Stats.byCat.funny) do set[def.id] = true end end
  return set
end
function UI.SetTicked(page, id, on)
  local s = C.Settings()
  if not s.columns[page] then
    s.columns[page] = {}
    for k, v in pairs(UI.Ticked(page)) do s.columns[page][k] = v end
  end
  s.columns[page][id] = on or nil
  UI:Refresh()
end

local function columnsFor(page, room)
  local ticked = UI.Ticked(page)
  local cols, used, hidden = {}, 0, 0
  for _, def in ipairs(C.Stats.byCat[CAT_OF_PAGE[page]]) do
    if ticked[def.id] then
      local w = colWidth(def)
      if used + w <= room then cols[#cols + 1] = { def = def, w = w }; used = used + w else hidden = hidden + 1 end
    end
  end
  return cols, hidden
end

----------------------------------------------------------------------------
-- readiness: red, amber, green from the gaps the prog page knows about
----------------------------------------------------------------------------
function UI.Readiness(stats)
  local gaps = 0
  local S = C.Stats.byId
  if type(stats.empty_slots) == "table" and (listCount(S.empty_slots, stats.empty_slots) or 0) > 0 then gaps = gaps + 1 end
  if type(stats.unenchanted) == "table" and (listCount(S.unenchanted, stats.unenchanted) or 0) > 3 then gaps = gaps + 1 end
  if type(stats.durability) == "number" and stats.durability < 50 then gaps = gaps + 1 end
  if stats.flasks == 0 and stats.flask_on == false then gaps = gaps + 1 end
  if type(stats.pot_health) == "number" and stats.pot_health < 5 then gaps = gaps + 1 end
  if stats.ilvl == nil and stats.level == nil then return nil end
  if gaps == 0 then return "green", GOOD elseif gaps <= 2 then return "amber", WARN end
  return "red", BAD
end

----------------------------------------------------------------------------
-- the window
----------------------------------------------------------------------------
function UI:Build()
  if self.frame then return end
  local f = CreateFrame("Frame", "CuteFrame", UIParent, BD)
  self.frame = f
  f:SetSize(W, H)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(s) s:StartMoving() end)
  f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); UI:SavePos() end)
  if f.SetResizable then f:SetResizable(true) end
  if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H) end
  backdrop(f, FLAT, EDGE, 24, 7)
  f:SetBackdropColor(SLATE[1], SLATE[2], SLATE[3], 0.97)
  f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
  f:Hide()
  tinsert(UISpecialFrames, "CuteFrame")
  f:SetScript("OnShow", function() UI:Draw() end)
  f:SetScript("OnSizeChanged", function() if UI.frame:IsShown() then UI:Draw() end end)

  -- header: the logo strip, the title, the close X
  local head = CreateFrame("Frame", nil, f)
  head:SetPoint("TOPLEFT", 14, -14)
  head:SetPoint("TOPRIGHT", -14, -14)
  head:SetHeight(HEAD)
  self.head = head
  local strip = flat(head, "BACKGROUND", SLATE2, 1)
  strip:SetAllPoints()
  local logo = tex(head, "ARTWORK", LOGO_WIDE, 112, 56)
  logo:SetPoint("LEFT", 6, 0)
  local title = text(head, "GameFontNormalLarge", 18, GOLD)
  title:SetPoint("LEFT", logo, "RIGHT", 10, 10)
  title:SetText("Cute")
  local sub = text(head, "GameFontNormalSmall", 11, INK_SOFT)
  sub:SetPoint("LEFT", logo, "RIGHT", 10, -10)
  sub:SetText("the guild dashboard")
  self.status = text(head, "GameFontNormalSmall", 11, INK_SOFT, "RIGHT", 420)
  self.status:SetPoint("RIGHT", -34, -10)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -12, -12)
  close:SetScript("OnClick", function() f:Hide() end)

  -- tabs
  local tabs = CreateFrame("Frame", nil, f)
  tabs:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
  tabs:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -4)
  tabs:SetHeight(TABS)
  self.tabs = {}
  local defs = { { "race", "Race" }, { "prog", "Prog" }, { "shame", "Hall of Shame" }, { "officers", "Officers" }, { "me", "Me" }, { "settings", "Settings" } }
  local x = 0
  for _, d in ipairs(defs) do
    local b = button(tabs, d[2], d[1] == "shame" and 110 or (d[1] == "settings" and 90 or 80))
    b:SetPoint("LEFT", x, 0)
    b.page = d[1]
    b:SetScript("OnClick", function() UI:Open(d[1]) end)
    self.tabs[d[1]] = b
    x = x + (d[1] == "shame" and 110 or (d[1] == "settings" and 90 or 80)) + 4
  end

  -- the content panel
  local content = CreateFrame("Frame", nil, f, BD)
  content:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -4)
  content:SetPoint("BOTTOMRIGHT", -14, 14)
  backdrop(content, FLAT, nil, 0, 0)
  content:SetBackdropColor(0, 0, 0, 0.25)
  self.content = content
  self.scroll = scrollArea(content)
  self.rows = pool(self.scroll.child, function(parent) return UI:MakeRow(parent) end)
  self.cards = pool(self.scroll.child, function(parent) return UI:MakeCard(parent) end)
  self.labels = pool(self.scroll.child, function(parent) return text(parent, "GameFontNormal", 12, INK) end)
  self.buttons = pool(self.scroll.child, function(parent) return button(parent, "", 160) end)
  self.checks = pool(self.scroll.child, function(parent) return UI:MakeCheck(parent) end)
  self.header = CreateFrame("Frame", nil, self.scroll.child)
  self.header:SetPoint("TOPLEFT")
  self.header:SetHeight(ROW)
  self.headerCells = pool(self.header, function(parent) return UI:MakeHeaderCell(parent) end)
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -13, 13)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetScript("OnMouseDown", function() if f.StartSizing then f:StartSizing("BOTTOMRIGHT") end end)
  grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); UI:SavePos() end)
  self:RestorePos()
end

function UI:SavePos()
  local f = self.frame
  CuteDB.pos = { w = f:GetWidth(), h = f:GetHeight(), left = f:GetLeft(), top = f:GetTop() }
end
function UI:RestorePos()
  local p = CuteDB.pos
  if not p then return end
  local f = self.frame
  if p.w and p.h then f:SetSize(math.max(MIN_W, p.w), math.max(MIN_H, p.h)) end
  if p.left and p.top then f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.left, p.top) end
end

function UI:Toggle()
  self:Build()
  if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() end
end
function UI:Open(page)
  self:Build()
  if page == "officers" and not C.Roster:MeOfficer() then page = "race" end
  self.page = page or self.page
  if not self.frame:IsShown() then self.frame:Show() else self:Draw() end
end
function UI:Refresh()
  if self.frame and self.frame:IsShown() and not self.drawing then self:Draw() end
end

----------------------------------------------------------------------------
-- rows and cells
----------------------------------------------------------------------------
function UI:MakeHeaderCell(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(ROW)
  b.label = text(b, "GameFontNormalSmall", 11, GOLD, "LEFT")
  b.label:SetPoint("LEFT", 4, 0)
  b.label:SetPoint("RIGHT", -2, 0)
  b.under = flat(b, "BACKGROUND", GOLD, 0.35)
  b.under:SetPoint("BOTTOMLEFT", 2, 0)
  b.under:SetPoint("BOTTOMRIGHT", -2, 0)
  b.under:SetHeight(1)
  b:SetScript("OnClick", function(self)
    if not self.id then return end
    -- (the race sorts by level, highest first, until a header is clicked)
    local s = UI.sort[UI.page] or (UI.page == "race" and { id = "level", desc = true }) or {}
    if s.id == self.id then s.desc = not s.desc else s = { id = self.id, desc = true } end
    UI.sort[UI.page] = s
    UI:Draw()
  end)
  tooltip(b, function(tip, self)
    if not self.def then tip:AddLine(self.label:GetText() or "", 1, 1, 1) return end
    tip:AddLine(self.def.label, 1, 1, 1)
    if self.def.hint then tip:AddLine(self.def.hint, 0.7, 0.7, 0.7, true) end
    tip:AddLine(C.Policy:Vis(self.def.id) == "all" and "Everyone sees this." or "Only you and the officers see this.", 0.55, 0.75, 0.75)
    tip:AddLine("Click to sort.", 0.5, 0.5, 0.5)
  end)
  return b
end

function UI:MakeRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(ROW)
  r.bg = flat(r, "BACKGROUND", INK, 0.04)
  r.bg:SetAllPoints()
  r:SetHighlightTexture(FLAT, "ADD")
  r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
  r.name = text(r, "GameFontNormal", 12, INK, "LEFT", NAME_W - 10)
  r.name:SetPoint("LEFT", 6, 0)
  r.dot = flat(r, "ARTWORK", GOOD, 1)
  r.dot:SetSize(6, 6)
  r.dot:SetPoint("LEFT", 0, 0)
  r.cells = {}
  r.pips = {}
  tooltip(r, function(tip, self)
    local row = self.row
    if not row then return end
    tip:AddLine(row.short, 1, 1, 1)
    if row.guild then tip:AddLine(row.guild.rankName or "", 0.7, 0.7, 0.7) end
    if not row.addon then tip:AddLine("No Cute addon yet.", 0.6, 0.6, 0.6)
    elseif row.me then tip:AddLine("You.", 0.6, 0.6, 0.6)
    else tip:AddLine(row.online and "Online" or ("Last seen " .. (ago(row.seen) or "?")), 0.6, 0.6, 0.6) end
  end)
  return r
end

-- a cell for a column: a label, and pips for pip and list stats
function UI:Cell(r, i)
  local c = r.cells[i]
  if not c then
    c = CreateFrame("Button", nil, r)
    c:SetHeight(ROW)
    c.label = text(c, "GameFontNormalSmall", 11, INK, "LEFT")
    c.label:SetPoint("LEFT", 4, 0)
    c.label:SetPoint("RIGHT", -2, 0)
    c.bar = flat(c, "ARTWORK", TEAL, 0.9)
    c.bar:SetHeight(2)
    c.bar:SetPoint("BOTTOMLEFT", 4, 2)
    c.bar:Hide()
    c.pips = {}
    r.cells[i] = c
    tooltip(c, function(tip, self)
      local def, row = self.def, self.row
      if not (def and row) then return end
      tip:AddLine(def.label, 1, 1, 1)
      if self.hidden then tip:AddLine("Only " .. row.short .. " and the officers see this.", 0.55, 0.75, 0.75, true) return end
      local v = row.stats[def.id]
      if def.kind == "list" then
        local names = listNames(def, v)
        tip:AddLine(#names > 0 and table.concat(names, ", ") or "none", 0.9, 0.9, 0.9, true)
      elseif def.kind == "pips" and def.id == "rep" and type(v) == "string" then
        for k, f in ipairs(C.Stats.FACTIONS) do tip:AddDoubleLine(f[2], tostring(v:sub(k, k)), 0.8, 0.8, 0.8, 1, 1, 1) end
      elseif def.kind == "pips" and type(v) == "string" then
        local done, started = select(2, v:gsub("2", "")), select(2, v:gsub("1", ""))
        tip:AddLine(string.format("%d of %d steps done, %d in the log", done, #v, started), 0.9, 0.9, 0.9)
      else
        tip:AddLine(UI.Format(def, v), 0.9, 0.9, 0.9)
      end
      if def.hint then tip:AddLine(def.hint, 0.6, 0.6, 0.6, true) end
      local at = row.at and row.at[def.id]
      if row.me and C.Sample:Error(def.id) then tip:AddLine("Could not read: " .. C.Sample:Error(def.id), 0.9, 0.4, 0.4, true) end
      if at then tip:AddLine("Reported " .. (ago(at) or ""), 0.5, 0.5, 0.5) end
    end)
  end
  return c
end

local function fillCell(c, def, row, hidden, me)
  c.def, c.row, c.hidden = def, row, hidden
  for _, p in ipairs(c.pips) do p:Hide() end
  c.bar:Hide()
  if hidden then
    c.label:SetText("-")
    c.label:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
    return
  end
  local v = row.stats[def.id]
  c.label:SetTextColor(INK[1], INK[2], INK[3])
  if def.kind == "pips" and type(v) == "string" and v ~= "" then
    c.label:SetText("")
    for k = 1, math.min(#v, 13) do
      local p = c.pips[k]
      if not p then p = flat(c, "ARTWORK", INK, 1); p:SetSize(6, 10); c.pips[k] = p end
      local d = tonumber(v:sub(k, k)) or 0
      local col = PIP_COLOR[d] or PIP_COLOR[0]
      p:SetColorTexture(col[1], col[2], col[3], 1)
      p:SetPoint("LEFT", 4 + (k - 1) * 7, 0)
      p:Show()
    end
    return
  end
  local s = UI.Format(def, v)
  if def.kind == "list" and type(v) == "table" then
    local n = listCount(def, v)
    local inverse = def.id == "empty_slots" or def.id == "unenchanted" or def.id == "old_gear" or def.id == "buffs_missing"
    if n == 0 then c.label:SetTextColor(inverse and GOOD[1] or INK_SOFT[1], inverse and GOOD[2] or INK_SOFT[2], inverse and GOOD[3] or INK_SOFT[3])
    elseif inverse then c.label:SetTextColor(WARN[1], WARN[2], WARN[3]) end
  end
  if def.id == "xp" and type(v) == "number" then
    c.bar:SetWidth(math.max(1, (c:GetWidth() - 8) * v / 100))
    c.bar:Show()
  end
  if def.id == "durability" and type(v) == "number" and v < 50 then c.label:SetTextColor(BAD[1], BAD[2], BAD[3]) end
  if v == nil then c.label:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3]) end
  c.label:SetText(s)
end

----------------------------------------------------------------------------
-- pages
----------------------------------------------------------------------------
local function sortRows(rows, page, cols)
  local s = UI.sort[page]
  if not s then
    if page == "race" then s = { id = "level", desc = true } else return end
  end
  local def = C.Stats.byId[s.id]
  table.sort(rows, function(a, b)
    if a.me ~= b.me then return a.me end
    local va, vb = a.stats[s.id], b.stats[s.id]
    if def and def.kind == "list" then va, vb = listCount(def, va), listCount(def, vb) end
    if def and def.kind == "pips" then va, vb = type(va) == "string" and select(2, va:gsub("2", "")) or nil, type(vb) == "string" and select(2, vb:gsub("2", "")) or nil end
    if type(va) == "boolean" then va = va and 1 or 0 end
    if type(vb) == "boolean" then vb = vb and 1 or 0 end
    if va == nil and vb == nil then return a.short < b.short end
    if va == nil then return false end
    if vb == nil then return true end
    if type(va) ~= type(vb) then va, vb = tostring(va), tostring(vb) end
    if va == vb then
      if s.id == "level" and type(a.stats.xp) == "number" and type(b.stats.xp) == "number" and a.stats.xp ~= b.stats.xp then
        if s.desc then return a.stats.xp > b.stats.xp else return a.stats.xp < b.stats.xp end
      end
      return a.short < b.short
    end
    if s.desc then return va > vb else return va < vb end
  end)
end

-- a table page: the header row and one row per member. y0: room above it the page used already (the officers' lines)
function UI:DrawTable(page, y0)
  y0 = y0 or 0
  local sf = self.scroll
  local room = sf:Width() - NAME_W - 8
  local cols, hidden = columnsFor(page, room)
  local officer = C.Roster:MeOfficer()
  local rows = C.Roster:Rows()
  if not C.Settings().offline then
    local kept = {}
    for _, r in ipairs(rows) do if r.online or r.me then kept[#kept + 1] = r end end
    rows = kept
  end
  sortRows(rows, page, cols)
  -- header
  self.header:Show()
  self.header:ClearAllPoints()
  self.header:SetPoint("TOPLEFT", 0, -y0)
  self.header:SetWidth(sf:Width())
  self.headerCells:Reset()
  local hc = self.headerCells:Get()
  hc:SetPoint("LEFT", 0, 0)
  hc:SetWidth(NAME_W)
  hc.id, hc.def = nil, nil
  hc.label:SetText("Member")
  local x = NAME_W
  for _, col in ipairs(cols) do
    local h = self.headerCells:Get()
    h:SetPoint("LEFT", x, 0)
    h:SetWidth(col.w)
    h.id, h.def = col.def.id, col.def
    fitText(h.label, shortLabel(col.def), col.w - 8)
    local s = self.sort[page]
    if s and s.id == col.def.id then h.label:SetTextColor(1, 1, 1) else h.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
    x = x + col.w
  end
  self.headerCells:HideRest()
  -- rows
  self.rows:Reset()
  local y = y0 + ROW + 2
  for i, row in ipairs(rows) do
    local r = self.rows:Get()
    r.row = row
    r:SetPoint("TOPLEFT", 0, -y)
    r:SetWidth(sf:Width())
    r.bg:SetColorTexture(INK[1], INK[2], INK[3], i % 2 == 0 and 0.05 or 0.02)
    if row.me then r.bg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.10) end
    local cc = row.addon and classColor(row.class) or INK_SOFT
    if row.addon and not row.online then cc = { cc[1] * 0.6, cc[2] * 0.6, cc[3] * 0.6 } end
    r.name:SetTextColor(cc[1], cc[2], cc[3])
    local nameText = row.short
    if row.me then nameText = row.short .. " (you)" end
    if not row.addon then nameText = row.short .. "  (no addon)" end
    fitText(r.name, nameText, NAME_W - 14)
    r.dot:SetColorTexture(row.online and GOOD[1] or 0.4, row.online and GOOD[2] or 0.4, row.online and GOOD[3] or 0.4, 1)
    r.dot:SetPoint("LEFT", -4, 0)
    r.dot:Hide()
    local cx = NAME_W
    for k, col in ipairs(cols) do
      local c = self:Cell(r, k)
      c:SetPoint("LEFT", cx, 0)
      c:SetWidth(col.w)
      c:Show()
      local canSee = C.Policy:CanSee(officer, row.me, col.def.id)
      fillCell(c, col.def, row, not canSee, row.me)
      if not row.addon then c.label:SetText(""); for _, p in ipairs(c.pips) do p:Hide() end; c.bar:Hide() end
      cx = cx + col.w
    end
    for k = #cols + 1, #r.cells do r.cells[k]:Hide() end
    y = y + ROW
  end
  self.rows:HideRest()
  if y0 == 0 then self.labels:Reset() end
  if hidden > 0 then
    local l = self.labels:Get()
    l:SetPoint("TOPLEFT", 6, -y - 6)
    l:SetWidth(sf:Width() - 12)
    l:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
    l:SetText(string.format("%d more column%s do not fit: widen the window or untick some in Settings.", hidden, hidden == 1 and "" or "s"))
    y = y + 24
  end
  if #rows <= 1 then
    local l = self.labels:Get()
    l:SetPoint("TOPLEFT", 6, -y - 6)
    l:SetWidth(sf:Width() - 12)
    l:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
    l:SetText(C.Roster:InGuild() and "Nobody else has reported yet. Members appear as their Cute addon says hello." or "You are not in a guild: only your own record shows.")
    y = y + 24
  end
  self.labels:HideRest()
  sf:SetContentHeight(y + 8)
end

-- the hall of shame: a card per funny stat
function UI:MakeCard(parent)
  local c = CreateFrame("Button", nil, parent, BD)
  c:SetSize(236, 64)
  backdrop(c, FLAT, nil, 0, 0)
  c:SetBackdropColor(SLATE2[1], SLATE2[2], SLATE2[3], 1)
  c.title = text(c, "GameFontNormalSmall", 11, GOLD, "LEFT", 220)
  c.title:SetPoint("TOPLEFT", 8, -7)
  c.leader = text(c, "GameFontNormal", 13, INK, "LEFT", 220)
  c.leader:SetPoint("TOPLEFT", 8, -25)
  c.mine = text(c, "GameFontNormalSmall", 10, INK_SOFT, "LEFT", 220)
  c.mine:SetPoint("BOTTOMLEFT", 8, 7)
  tooltip(c, function(tip, self)
    if not self.def then return end
    tip:AddLine(self.def.label, 1, 1, 1)
    if self.def.hint then tip:AddLine(self.def.hint, 0.6, 0.6, 0.6, true) end
    for _, e in ipairs(self.top or {}) do tip:AddDoubleLine(e.short, UI.Format(self.def, e.v), 0.8, 0.8, 0.8, 1, 1, 1) end
  end)
  return c
end

function UI:DrawShame()
  local sf = self.scroll
  local officer = C.Roster:MeOfficer()
  local rows = C.Roster:Rows()
  local ticked = UI.Ticked("shame")
  self.header:Hide()
  self.rows:Reset(); self.rows:HideRest()
  self.cards:Reset()
  self.labels:Reset()
  local perRow = math.max(1, math.floor((sf:Width() + 8) / 244))
  local i, y = 0, 0
  for _, def in ipairs(C.Stats.byCat.funny) do
    if ticked[def.id] then
      local top = {}
      for _, row in ipairs(rows) do
        local v = row.stats[def.id]
        if row.addon and type(v) == "number" and C.Policy:CanSee(officer, row.me, def.id) then top[#top + 1] = { short = row.short, v = v, me = row.me } end
      end
      table.sort(top, function(a, b) if a.v == b.v then return a.short < b.short end return a.v > b.v end)
      local card = self.cards:Get()
      card.def, card.top = def, { top[1], top[2], top[3] }
      card:SetPoint("TOPLEFT", (i % perRow) * 244, -math.floor(i / perRow) * 72)
      card.title:SetText(def.label)
      if top[1] and top[1].v > 0 then
        card.leader:SetText(string.format("%s%s|r  %s", hex(top[1].me and GOLD or INK), top[1].short, UI.Format(def, top[1].v)))
      else card.leader:SetText(hex(INK_SOFT) .. "nobody yet|r") end
      local mine = C.Sample:Value(def.id)
      card.mine:SetText("You: " .. UI.Format(def, mine))
      i = i + 1
    end
  end
  self.cards:HideRest()
  y = math.ceil(i / perRow) * 72
  if i == 0 then
    local l = self.labels:Get()
    l:SetPoint("TOPLEFT", 6, -6)
    l:SetWidth(sf:Width() - 12)
    l:SetText("No funny stats ticked. Settings has the list.")
    y = 30
  end
  self.labels:HideRest()
  sf:SetContentHeight(y + 8)
end

-- the officers' page: summaries, then the officer stats as a table, then the controls
function UI:DrawOfficers()
  local sf = self.scroll
  local rows = C.Roster:Rows()
  local total, withAddon, online, levels, unseen, noAddon = 0, 0, 0, {}, 0, {}
  for _, r in ipairs(rows) do
    total = total + 1
    if r.addon then withAddon = withAddon + 1 else noAddon[#noAddon + 1] = r.short end
    if r.online then online = online + 1 end
    if type(r.level) == "number" then levels[#levels + 1] = r.level end
    if r.addon and not r.me and r.seen and C.Now() - r.seen > 7 * 86400 then unseen = unseen + 1 end
  end
  table.sort(levels)
  local median = levels[math.max(1, math.ceil(#levels / 2))]
  local below = 0
  for _, l in ipairs(levels) do if median and l < median then below = below + 1 end end
  self.labels:Reset()
  local y = 4
  local function line(s, color)
    local l = self.labels:Get()
    l:SetPoint("TOPLEFT", 6, -y)
    l:SetWidth(sf:Width() - 12)
    l:SetTextColor((color or INK)[1], (color or INK)[2], (color or INK)[3])
    fitText(l, s, sf:Width() - 16)
    y = y + 18
  end
  line(string.format("%d members, %d with the addon, %d online. Median level %s, %d below it, %d not seen for a week.",
    total, withAddon, online, median and tostring(median) or "?", below, unseen))
  if #noAddon > 0 then
    table.sort(noAddon)
    line("Without the addon: " .. table.concat(noAddon, ", "), INK_SOFT)
  end
  line(C.Policy:Describe(), INK_SOFT)
  -- the controls
  self.buttons:Reset()
  local b1 = self.buttons:Get()
  b1:SetPoint("TOPLEFT", 6, -y - 2)
  b1:SetWidth(160)
  b1:SetText("Visibility settings")
  b1:SetScript("OnClick", function() UI:Open("settings") end)
  local b2 = self.buttons:Get()
  b2:SetPoint("TOPLEFT", 172, -y - 2)
  b2:SetWidth(160)
  b2:SetText("Ask everyone to resend")
  b2:SetScript("OnClick", function() C.Comm:Ask(); C.Print("asked the guild to send their records again.") end)
  local b3 = self.buttons:Get()
  b3:SetPoint("TOPLEFT", 338, -y - 2)
  b3:SetWidth(160)
  b3:SetText("Broadcast policy now")
  b3:SetScript("OnClick", function() C.Comm:SendPolicy(); C.Print("sent the visibility policy to the guild.") end)
  self.buttons:HideRest()
  y = y + 30
  -- the table below the lines
  self:DrawTable("officers", y)
end

-- your whole record, two columns, every stat; the toggle greys what members cannot see
function UI:DrawMe()
  local sf = self.scroll
  self.header:Hide()
  self.rows:Reset(); self.rows:HideRest()
  self.cards:Reset(); self.cards:HideRest()
  self.labels:Reset()
  self.checks:Reset()
  local me = C.Roster:Rows()[1]
  local w = sf:Width()
  local colW = math.floor((w - 12) / 2)
  local cb = self.checks:Get()
  cb:SetPoint("TOPLEFT", 6, -4)
  cb.label:SetText("Show what members see of me")
  cb:SetChecked(self.meView and true or false)
  cb:SetEnabled(true)
  cb:SetScript("OnClick", function(self) UI.meView = self:GetChecked(); UI:Draw() end)
  self.checks:HideRest()
  local y = 30
  local i = 0
  for _, cat in ipairs(C.Stats.CATS) do
    local l = self.labels:Get()
    l:SetPoint("TOPLEFT", 6, -y)
    l:SetWidth(w - 12)
    l:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    l:SetText(C.Stats.CAT_LABEL[cat])
    y = y + 20
    local n = 0
    for _, def in ipairs(C.Stats.byCat[cat]) do
      local col = n % 2
      local ly = y + math.floor(n / 2) * 18
      local a = self.labels:Get()
      a:SetPoint("TOPLEFT", 6 + col * colW, -ly)
      a:SetWidth(colW - 130)
      local hidden = self.meView and C.Policy:Vis(def.id) == "self"
      local dim = hidden and INK_SOFT or INK
      a:SetTextColor(dim[1] * 0.9, dim[2] * 0.9, dim[3] * 0.9)
      fitText(a, def.label, colW - 136)
      local b = self.labels:Get()
      b:SetPoint("TOPLEFT", 6 + col * colW + (colW - 130), -ly)
      b:SetWidth(124)
      b:SetJustifyH("RIGHT")
      local v = me and me.stats[def.id]
      if hidden then b:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3]); b:SetText("(only you)")
      else
        b:SetTextColor(v == nil and INK_SOFT[1] or INK[1], v == nil and INK_SOFT[2] or INK[2], v == nil and INK_SOFT[3] or INK[3])
        fitText(b, C.Sample:Error(def.id) and "?" or UI.Format(def, v), 120)
      end
      n = n + 1
    end
    y = y + math.ceil(n / 2) * 18 + 8
  end
  self.labels:HideRest()
  sf:SetContentHeight(y + 8)
end

function UI:MakeCheck(parent)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(22, 22)
  cb.label = text(cb, "GameFontNormalSmall", 11, INK, "LEFT", 240)
  cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  return cb
end

function UI:Draw()
  self.drawing = true
  local page = self.page
  if page == "officers" and not C.Roster:MeOfficer() then page = "race"; self.page = page end
  for id, b in pairs(self.tabs) do
    b:SetShown(id ~= "officers" or C.Roster:MeOfficer())
    if b.GetFontString and b:GetFontString() then
      if id == page then b:GetFontString():SetTextColor(1, 1, 1) else b:GetFontString():SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
    end
  end
  -- the Officers tab leaves a gap when hidden: lay the tabs out again
  local x = 0
  for _, id in ipairs({ "race", "prog", "shame", "officers", "me", "settings" }) do
    local b = self.tabs[id]
    if b:IsShown() then b:SetPoint("LEFT", x, 0); x = x + (b:GetWidth() or 80) + 4 end
  end
  self.scroll.bar:SetValue(0)
  self.header:ClearAllPoints()
  self.header:SetPoint("TOPLEFT")
  self.cards:Reset(); self.cards:HideRest()
  self.buttons:Reset(); self.buttons:HideRest()
  self.checks:Reset(); self.checks:HideRest()
  if C.Settings_Draw and page ~= "settings" then C.Settings_Hide() end
  if page == "race" or page == "prog" then self:DrawTable(page)
  elseif page == "shame" then self:DrawShame()
  elseif page == "officers" then self:DrawOfficers()
  elseif page == "me" then self:DrawMe()
  elseif page == "settings" then
    self.header:Hide(); self.rows:Reset(); self.rows:HideRest(); self.labels:Reset(); self.labels:HideRest()
    C.Settings_Draw(self.scroll)
  end
  local rows = C.Roster:Rows()
  local online = 0
  for _, r in ipairs(rows) do if r.online and r.addon then online = online + 1 end end
  self.status:SetText(string.format("%d with the addon online  |  %s", online, C.Roster:MeOfficer() and "officer view" or "member view"))
  self.drawing = false
end

----------------------------------------------------------------------------
-- the minimap button: the emblem in a ring, dragged around the minimap's edge
----------------------------------------------------------------------------
function UI:OnWorld()
  if not C.Settings().minimap then if self.mini then self.mini:Hide() end return end
  if self.mini then self.mini:Show(); return end
  if not Minimap then return end
  local b = CreateFrame("Button", "CuteMinimapButton", Minimap)
  self.mini = b
  b:SetSize(32, 32)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetMovable(true)
  local icon = tex(b, "ARTWORK", LOGO, 20, 20)
  icon:SetPoint("CENTER", -1, 1)
  if b.CreateMaskTexture then
    local mask = b:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
  end
  local ring = tex(b, "OVERLAY", "Interface\\Minimap\\MiniMap-TrackingBorder", 54, 54)
  ring:SetPoint("TOPLEFT")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
  local function place()
    local angle = math.rad(C.Settings().minimapPos or 220)
    local r = (Minimap:GetWidth() or 140) / 2 + 5
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
  end
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      if not (mx and cx) then return end
      cx, cy = cx / scale, cy / scale
      C.Settings().minimapPos = math.deg(math.atan2(cy - my, cx - mx))
      place()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnClick", function(_, which)
    if which == "RightButton" then UI:Open("settings") else UI:Toggle() end
  end)
  tooltip(b, function(tip)
    tip:AddLine("Cute", 1, 1, 1)
    tip:AddLine("Click: the dashboard. Right-click: settings. Drag to move.", 0.7, 0.7, 0.7, true)
  end)
  place()
end
