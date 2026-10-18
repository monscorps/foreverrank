-- SPDX-License-Identifier: GPL-3.0-or-later
-- The window: one frame with five pages and Settings, drawn flat and dark the way ElvUI and Shadowed Unit Frames
-- draw theirs: one-pixel black borders, near-black panels, white and grey text in the client's narrow font, class
-- colours on names and nothing else coloured unless it means something (green ready, red low). Numbers sit on the
-- right of their columns, text on the left; a two-pixel class-coloured bar marks every member's row, white for you.
--   Race           every member as a row: level, XP, zone, pace, the leveling stats
--   Prog           readiness, attunements, item level, consumables, buffs, the gaps only you see
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
local HEAD = 56          -- the header strip
local TABS = 26          -- the tab row
local ROW = 20           -- a member row (compact: 17)
local ROW_COMPACT = 17
local FOOT = 18          -- the footer line inside the content panel
local NAME_W = 150
local WHITE = { 0.96, 0.96, 0.96 }
local INK = { 0.86, 0.86, 0.86 }
local DIM = { 0.58, 0.58, 0.58 }
local MUTE = { 0.38, 0.38, 0.38 }
local GOOD = { 0.45, 0.83, 0.47 }
local WARN = { 0.93, 0.74, 0.35 }
local BAD = { 0.88, 0.36, 0.33 }
local BG = { 0.035, 0.035, 0.035 }
local PANEL = { 0.07, 0.07, 0.07 }
local PANEL2 = { 0.11, 0.11, 0.11 }
local LINE = { 0.2, 0.2, 0.2 }
local BLACK = { 0, 0, 0 }
local FLAT = "Interface\\Buttons\\WHITE8x8"
local LOGO = "Interface\\AddOns\\Cute\\art\\logo.png"
local LOGO_WIDE = "Interface\\AddOns\\Cute\\art\\logo_wide.png"
local BD = BackdropTemplateMixin and "BackdropTemplate" or nil

-- the client's narrow sans, taken from a font object that uses it (NumberFontNormal is ARIALN on Blizzard's clients),
-- so a client without the file named here still draws every label
local function narrowFont()
  for _, fo in ipairs({ NumberFontNormal, ChatFontNormal, GameFontNormal }) do
    if type(fo) == "table" and fo.GetFont then
      local ok, path = pcall(fo.GetFont, fo)
      if ok and type(path) == "string" and path ~= "" then return path end
    end
  end
  return "Fonts\\ARIALN.TTF"
end
local FONT = narrowFont()
UI.FONT = FONT

local function hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end
local function classColor(class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return { c.r, c.g, c.b } end
  return INK
end
local function color(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end
local function dimmed(c) return { c[1] * 0.55, c[2] * 0.55, c[3] * 0.55 } end

----------------------------------------------------------------------------
-- small builders, flat
----------------------------------------------------------------------------
local function tex(parent, layer, file, w, h)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  if file then t:SetTexture(file) end
  if w then t:SetSize(w, h or w) end
  return t
end
local function flat(parent, layer, c, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  return t
end
-- a frame with a near-black fill and a one-pixel black border
local function skin(frame, fill, a)
  if not frame.SetBackdrop then return end
  frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, tile = false, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  frame:SetBackdropColor(fill[1], fill[2], fill[3], a or 1)
  frame:SetBackdropBorderColor(0, 0, 0, 1)
end
-- a one-pixel line
local function line(parent, c)
  local t = flat(parent, "ARTWORK", c or LINE, 1)
  t:SetHeight(1)
  return t
end
local function text(parent, size, c, justify, width)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(GameFontNormal)
  -- SetFont says whether the file was found; the font object's own face stays otherwise
  if fs:SetFont(FONT, size or 12, "") == false then fs:SetFontObject(GameFontNormal) end
  color(fs, c or INK)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  if width then fs:SetWidth(width) end
  return fs
end
-- a flat button with a label: dark fill, black edge, a touch lighter when the mouse is on it
local function button(parent, label, w, h)
  local b = CreateFrame("Button", nil, parent, BD)
  b:SetSize(w or 110, h or 22)
  skin(b, PANEL2)
  b.label = text(b, 12, INK, "CENTER")
  b.label:SetPoint("TOPLEFT", 4, 0)
  b.label:SetPoint("BOTTOMRIGHT", -4, 0)
  b.label:SetText(label or "")
  b:SetHighlightTexture(FLAT, "ADD")
  b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
  function b:SetLabel(s) UI.FitText(self.label, s, (self:GetWidth() or w or 110) - 10) end
  function b:SetOn(on) self.__off = not on; color(self.label, on and INK or MUTE); self:SetEnabled(on) end
  return b
end
-- a flat check box: a small square, filled white when checked. Callers set cb.fn rather than the OnClick script,
-- so the fill always follows the click
local function check(parent)
  local cb = CreateFrame("CheckButton", nil, parent, BD)
  cb:SetSize(14, 14)
  skin(cb, PANEL2)
  cb.fill = flat(cb, "ARTWORK", WHITE, 1)
  cb.fill:SetPoint("TOPLEFT", 3, -3)
  cb.fill:SetPoint("BOTTOMRIGHT", -3, 3)
  cb.fill:Hide()
  cb.label = text(cb, 12, INK, "LEFT", 220)
  cb.label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
  cb:SetHighlightTexture(FLAT, "ADD")
  cb:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
  cb:SetScript("OnClick", function(self, ...)
    self.fill:SetShown(self:GetChecked())
    if self.fn then self.fn(self, ...) end
  end)
  function cb:Set(on) self:SetChecked(on); self.fill:SetShown(on and true or false) end
  function cb:SetOn(on) self:SetEnabled(on); color(self.label, on and INK or MUTE); self.fill:SetVertexColor(1, 1, 1, on and 1 or 0.4) end
  return cb
end
UI.Check, UI.Button, UI.Text, UI.Skin = check, button, text, skin
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

-- ScrollFrame with a child and a thin flat bar, above the footer line
local function scrollArea(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  sf:SetPoint("TOPLEFT", 8, -8)
  sf:SetPoint("BOTTOMRIGHT", -18, FOOT + 6)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(100, 10)
  sf:SetScrollChild(child)
  local bar = CreateFrame("Slider", nil, parent)
  bar:SetOrientation("VERTICAL")
  bar:SetPoint("TOPRIGHT", -7, -8)
  bar:SetPoint("BOTTOMRIGHT", -7, FOOT + 6)
  bar:SetWidth(6)
  local track = flat(bar, "BACKGROUND", PANEL2, 1)
  track:SetAllPoints()
  local knob = flat(bar, "OVERLAY", DIM, 1)
  knob:SetSize(6, 40)
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
    if view < 50 then view = (UI.frame:GetHeight() or H) - HEAD - TABS - FOOT - 32 end
    local max = math.max(0, h - view)
    bar:SetMinMaxValues(0, max)
    bar:SetShown(max > 0)
    if bar:GetValue() > max then bar:SetValue(max) end
  end
  function sf:Width()
    local w = self:GetWidth() or 0
    if w < 100 then w = (UI.frame:GetWidth() or W) - 2 - 8 - 18 end
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
-- pips: not started dark, in the log grey, done white; reputations climb from grey to white
local PIP = { [0] = { 0.16, 0.16, 0.16 }, [1] = { 0.5, 0.5, 0.5 }, [2] = WHITE, [3] = { 0.3, 0.3, 0.3 }, [4] = { 0.45, 0.45, 0.45 }, [5] = { 0.6, 0.6, 0.6 }, [6] = { 0.75, 0.75, 0.75 }, [7] = { 0.9, 0.9, 0.9 }, [8] = WHITE }

-- a column header's short form, where the label would not fit a column
local SHORT = { xp = "XP %", xp_hour = "XP/h", xp_session = "XP/h today", to60 = "To 60", played = "Played", played_lvl = "This lvl", rested = "Rested",
  group = "Group", quests_done = "Quests", quests_today = "Today", quests_log = "In log", quests_ready = "Ready", deaths_lvl = "Deaths", legacy = "Legacy",
  flights_known = "Flights", longest_flight = "Flight", hearth = "Hearth", hearths = "Hearths", ghost_time = "Ghost", gold_earned = "Earned", gold_quests = "Quest gold",
  vendor_sales = "Sold", talents_free = "Talents", zones_seen = "Zones", logins = "Logins", longest = "Longest", levelups = "Lvl-ups", still = "Stood still",
  ilvl = "iLvl", ilvl_slots = "Slots", empty_slots = "Empty", unenchanted = "No ench", old_gear = "Old gear", greens = "Greens", attune_mc = "MC", attune_ony_a = "Ony (A)",
  attune_ony_h = "Ony (H)", resist_fire = "FR", resist_nature = "NR", resist_frost = "FrR", resist_shadow = "SR", resist_arcane = "AR", raid_recipes = "Raid rec.",
  bags_free = "Bags free", bags_size = "Bags", pot_health = "HP pots", pot_mana = "MP pots", protpots = "Prot pots", world_buffs = "World", flask_on = "Flask",
  buffs_missing = "Missing", durability = "Dura", rep = "Rep", pvp_rank = "PvP", pvp_pts = "Rank pts", raids = "Raids", stones = "Stones",
  bank_in = "Bank in", bank_out = "Bank out", consumed = "Consumed", addon_ver = "Version", main = "Main", last_login = "Last login", raid_spec = "Raid spec",
  weekly_raids = "Raids/wk", deaths_today = "Today", hearth_waste = "Wasted HS", whispers = "Whispers/h", gchat = "Guild lines", inspected = "Inspected",
  ghost_yards = "Ghost yds", where = "Where r u", grey_gold = "Grey gold" }
UI.SHORT = SHORT
local function shortLabel(def) return SHORT[def.id] or def.label end

-- the width a column takes
local function colWidth(def)
  if def.kind == "flag" then return 44 end
  if def.kind == "text" then return 110 end
  if def.kind == "list" then return 62 end
  if def.kind == "pips" then return math.max(36, 8 + 7 * (def.pips or 8)) end
  if def.fmt == C.Stats.FmtHours then return 70 end
  return math.max(56, 12 + #shortLabel(def) * 7)
end
-- numbers on the right of their column, text (and pips, drawn from the left) on the left
local function alignOf(def) return (def.kind == "text" or def.kind == "pips") and "LEFT" or "RIGHT" end

----------------------------------------------------------------------------
-- which columns a page shows
----------------------------------------------------------------------------
local DEFAULT_COLS = {
  race = { "level", "xp", "xp_hour", "to60", "zone", "played", "quests_done", "deaths_lvl", "group", "rested", "legacy" },
  prog = { "ready", "ilvl", "attune_mc", "attune_ony_a", "attune_ony_h", "keys", "flasks", "pot_health", "world_buffs", "durability", "rep", "unenchanted", "empty_slots" },
  officers = { "gold", "bank_in", "bank_out", "raids", "weekly_raids", "consumed", "main", "role", "last_login", "addon_ver" },
}
UI.DEFAULT_COLS = DEFAULT_COLS
local CAT_OF_PAGE = { race = "leveling", prog = "prog", officers = "officer", shame = "funny" }
UI.CAT_OF_PAGE = CAT_OF_PAGE

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
    -- the first change copies the defaults, then edits the copy
    local copy = {}
    for k, v in pairs(UI.Ticked(page)) do copy[k] = v end
    s.columns[page] = copy
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
-- the window
----------------------------------------------------------------------------
local TAB_DEFS = { { "race", "Race", 64 }, { "prog", "Prog", 64 }, { "shame", "Hall of Shame", 110 }, { "officers", "Officers", 80 }, { "me", "Me", 48 }, { "settings", "Settings", 80 } }

function UI:Build()
  if self.frame then return end
  self.sort = C.Settings().sort -- header clicks are remembered across sessions
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
  skin(f, BG, 0.94)
  -- the shadow the clean UIs draw: a soft dark edge just outside the border
  local shadow = CreateFrame("Frame", nil, f, BD)
  shadow:SetPoint("TOPLEFT", -4, 4)
  shadow:SetPoint("BOTTOMRIGHT", 4, -4)
  shadow:SetFrameLevel(math.max(0, (f:GetFrameLevel() or 2) - 1))
  if shadow.SetBackdrop then
    shadow:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    shadow:SetBackdropBorderColor(0, 0, 0, 0.7)
  end
  f:Hide()
  tinsert(UISpecialFrames, "CuteFrame")
  f:SetScript("OnShow", function() UI:Draw() end)
  -- a resize redraws once the grip has rested for a tenth of a second, not on every pixel
  f:SetScript("OnSizeChanged", function()
    if UI.resizing then return end
    UI.resizing = true
    C_Timer.After(0.1, C.Safe(function() UI.resizing = false; if UI.frame:IsShown() then UI:Draw() end end, "resize"))
  end)

  -- header: the logo, the status line, the close X
  local head = CreateFrame("Frame", nil, f)
  head:SetPoint("TOPLEFT", 1, -1)
  head:SetPoint("TOPRIGHT", -1, -1)
  head:SetHeight(HEAD)
  self.head = head
  local logo = tex(head, "ARTWORK", LOGO_WIDE, 104, 52)
  logo:SetPoint("LEFT", 8, 0)
  local headLine = line(head)
  headLine:SetPoint("BOTTOMLEFT")
  headLine:SetPoint("BOTTOMRIGHT")
  self.status = text(head, 11, DIM, "RIGHT", 420)
  self.status:SetPoint("RIGHT", -40, 0)
  local close = button(f, "x", 22, 22)
  close:SetPoint("TOPRIGHT", -9, -9)
  close:SetScript("OnClick", function() f:Hide() end)

  -- tabs: flat, the open one white with a line under it; a hairline under the row
  local tabs = CreateFrame("Frame", nil, f)
  tabs:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 8, -4)
  tabs:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", -8, -4)
  tabs:SetHeight(TABS)
  self.tabs = {}
  for _, d in ipairs(TAB_DEFS) do
    local b = button(tabs, d[2], d[3], TABS)
    b.page = d[1]
    b.under = flat(b, "OVERLAY", WHITE, 1)
    b.under:SetPoint("BOTTOMLEFT", 1, 1)
    b.under:SetPoint("BOTTOMRIGHT", -1, 1)
    b.under:SetHeight(2)
    b.under:Hide()
    b:SetScript("OnClick", function() UI:Open(d[1]) end)
    self.tabs[d[1]] = b
  end
  local tabLine = line(f)
  tabLine:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -1)
  tabLine:SetPoint("TOPRIGHT", tabs, "BOTTOMRIGHT", 0, -1)

  -- the content panel, with the footer along its bottom edge
  local content = CreateFrame("Frame", nil, f, BD)
  content:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -4)
  content:SetPoint("BOTTOMRIGHT", -9, 9)
  skin(content, PANEL, 1)
  self.content = content
  self.scroll = scrollArea(content)
  self.footer = text(content, 11, MUTE, "LEFT")
  self.footer:SetPoint("BOTTOMLEFT", 10, 6)
  self.footer:SetPoint("BOTTOMRIGHT", -40, 6)
  self.footer:SetHeight(12)
  self.rows = pool(self.scroll.child, function(parent) return UI:MakeRow(parent) end)
  self.cards = pool(self.scroll.child, function(parent) return UI:MakeCard(parent) end)
  self.labels = pool(self.scroll.child, function(parent) return text(parent, 12, INK) end)
  self.buttons = pool(self.scroll.child, function(parent) return button(parent, "", 160) end)
  self.checks = pool(self.scroll.child, function(parent) return check(parent) end)
  self.header = CreateFrame("Frame", nil, self.scroll.child)
  self.header:SetPoint("TOPLEFT")
  self.header:SetHeight(ROW)
  self.headerLine = line(self.header)
  self.headerLine:SetPoint("BOTTOMLEFT")
  self.headerLine:SetPoint("BOTTOMRIGHT")
  self.headerCells = pool(self.header, function(parent) return UI:MakeHeaderCell(parent) end)
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(12, 12)
  grip:SetPoint("BOTTOMRIGHT", -10, 10)
  grip.t = flat(grip, "ARTWORK", MUTE, 1)
  grip.t:SetAllPoints()
  grip:SetHighlightTexture(FLAT, "ADD")
  grip:SetScript("OnMouseDown", function() if f.StartSizing then f:StartSizing("BOTTOMRIGHT") end end)
  grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); UI:SavePos() end)
  tooltip(grip, function(tip) tip:AddLine("Drag to resize", 1, 1, 1) end)
  self:RestorePos()
  -- the footer's "2 min ago" keeps up while the window is open
  local function footTick()
    C_Timer.After(30, C.Safe(footTick, "footer"))
    if f:IsShown() then UI:DrawFooter() end
  end
  C_Timer.After(30, C.Safe(footTick, "footer"))
end

function UI:SavePos()
  local f = self.frame
  CuteDB.pos = { w = f:GetWidth(), h = f:GetHeight(), left = f:GetLeft(), top = f:GetTop() }
end
-- the saved place, kept on screen: another resolution or UI scale may have saved it beyond this screen's edge
function UI:RestorePos()
  local p = CuteDB.pos
  if not p then return end
  local f = self.frame
  if type(p.w) == "number" and type(p.h) == "number" then f:SetSize(math.max(MIN_W, p.w), math.max(MIN_H, p.h)) end
  if type(p.left) ~= "number" or type(p.top) ~= "number" then return end
  local uw, uh = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
  local w, h = f:GetWidth() or W, f:GetHeight() or H
  local left, top = p.left, p.top
  if uw > w and uh > h then
    left = math.max(0, math.min(left, uw - w))
    top = math.max(h, math.min(top, uh))
  end
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

function UI:Toggle()
  self:Build()
  if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() end
end
function UI:Open(page)
  self:Build()
  if page == "officers" and not C.Roster:MeOfficer() then page = "race" end
  page = page or self.page
  if page ~= self.page then self.scrollTo = 0 end -- a new page starts at the top; a redraw keeps the place
  self.page = page
  if not self.frame:IsShown() then self.frame:Show() else self:Draw() end
end
-- a redraw, once a second at most, so a burst of guild messages does not draw twenty times
function UI:Refresh()
  if not (self.frame and self.frame:IsShown()) or self.drawing then return end
  if self.refreshing then return end
  self.refreshing = true
  C_Timer.After(1, C.Safe(function() UI.refreshing = false; if UI.frame:IsShown() then UI:Draw() end end, "refresh"))
end

----------------------------------------------------------------------------
-- rows and cells
----------------------------------------------------------------------------
function UI:MakeHeaderCell(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(ROW)
  b.label = text(b, 11, DIM, "LEFT")
  b.label:SetPoint("LEFT", 4, 0)
  b.label:SetPoint("RIGHT", -4, 0)
  b:SetHighlightTexture(FLAT, "ADD")
  b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)
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
    tip:AddLine(C.Policy:Vis(self.def.id) == "all" and "Everyone sees this." or "Only you and the officers see this.", 0.6, 0.6, 0.6)
    tip:AddLine("Click to sort.", 0.45, 0.45, 0.45)
  end)
  return b
end

function UI:MakeRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(ROW)
  r.bg = flat(r, "BACKGROUND", WHITE, 0.03)
  r.bg:SetAllPoints()
  -- the class bar: two pixels at the left edge, white for you
  r.bar = flat(r, "ARTWORK", WHITE, 1)
  r.bar:SetPoint("TOPLEFT", 0, 0)
  r.bar:SetPoint("BOTTOMLEFT", 0, 0)
  r.bar:SetWidth(2)
  r:SetHighlightTexture(FLAT, "ADD")
  r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)
  r.name = text(r, 12, INK, "LEFT", NAME_W - 12)
  r.name:SetPoint("LEFT", 8, 0)
  r.cells = {}
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

-- a cell for a column: a label, pips for pip stats, a thin bar under the XP cell
function UI:Cell(r, i)
  local c = r.cells[i]
  if not c then
    c = CreateFrame("Button", nil, r)
    c:SetHeight(ROW)
    c.label = text(c, 12, INK, "LEFT")
    c.label:SetPoint("LEFT", 4, 0)
    c.label:SetPoint("RIGHT", -4, 0)
    c.bar = flat(c, "ARTWORK", WHITE, 0.7)
    c.bar:SetHeight(1)
    c.bar:SetPoint("BOTTOMLEFT", 4, 3)
    c.bar:Hide()
    c.pips = {}
    r.cells[i] = c
    tooltip(c, function(tip, self)
      local def, row = self.def, self.row
      if not (def and row) then return end
      tip:AddLine(def.label, 1, 1, 1)
      if self.hidden then tip:AddLine("Only " .. row.short .. " and the officers see this.", 0.6, 0.6, 0.6, true) return end
      local v = row.stats[def.id]
      if def.kind == "list" then
        local names = listNames(def, v)
        tip:AddLine(#names > 0 and table.concat(names, ", ") or "none", 0.9, 0.9, 0.9, true)
      elseif def.kind == "pips" and def.id == "rep" and type(v) == "string" then
        for k, f in ipairs(C.Stats.FACTIONS) do tip:AddDoubleLine(f[2], tostring(v:sub(k, k)), 0.8, 0.8, 0.8, 1, 1, 1) end
      elseif def.kind == "pips" and type(v) == "string" then
        local done, started = select(2, v:gsub("2", "")), select(2, v:gsub("1", ""))
        tip:AddLine(string.format("%d of %d steps done, %d in the log", done, #v, started), 0.9, 0.9, 0.9)
      elseif def.id == "ready" and type(v) == "number" and (row.me or C.Roster:MeOfficer()) then
        -- the gaps behind the verdict, for those who may see the inputs
        local gaps = C.Stats.ReadyGaps(row.stats) or {}
        tip:AddLine(#gaps == 0 and "No gaps." or table.concat(gaps, ", "), 0.9, 0.9, 0.9, true)
      else
        tip:AddLine(UI.Format(def, v), 0.9, 0.9, 0.9)
      end
      if def.hint then tip:AddLine(def.hint, 0.6, 0.6, 0.6, true) end
      local at = row.at and row.at[def.id]
      if row.me and C.Sample:Error(def.id) then tip:AddLine("Could not read: " .. C.Sample:Error(def.id), 0.9, 0.4, 0.4, true) end
      if at then tip:AddLine("Reported " .. (ago(at) or ""), 0.45, 0.45, 0.45) end
    end)
  end
  return c
end

local INVERSE = { empty_slots = true, unenchanted = true, old_gear = true, buffs_missing = true }
local function fillCell(c, def, row, hidden, w)
  c.def, c.row, c.hidden = def, row, hidden
  c.label:SetJustifyH(alignOf(def))
  for _, p in ipairs(c.pips) do p:Hide() end
  c.bar:Hide()
  if hidden then
    c.label:SetText("-")
    color(c.label, MUTE)
    return
  end
  if not row.addon then
    -- the guild roster still knows a member's level and zone
    color(c.label, MUTE)
    if def.id == "level" and type(row.level) == "number" then c.label:SetText(tostring(row.level))
    elseif def.id == "zone" and type(row.zone) == "string" then fitText(c.label, row.zone, w - 8)
    else c.label:SetText("") end
    return
  end
  local v = row.stats[def.id]
  color(c.label, INK)
  if def.kind == "pips" and type(v) == "string" and v ~= "" then
    c.label:SetText("")
    for k = 1, math.min(#v, 13) do
      local p = c.pips[k]
      if not p then p = flat(c, "ARTWORK", WHITE, 1); p:SetSize(5, 10); c.pips[k] = p end
      local d = tonumber(v:sub(k, k)) or 0
      local col = PIP[d] or PIP[0]
      p:SetColorTexture(col[1], col[2], col[3], 1)
      p:SetPoint("LEFT", 4 + (k - 1) * 7, 0)
      p:Show()
    end
    return
  end
  local s = UI.Format(def, v)
  if def.kind == "list" and type(v) == "table" then
    local n = listCount(def, v)
    if n == 0 then color(c.label, INVERSE[def.id] and GOOD or MUTE) elseif INVERSE[def.id] then color(c.label, WARN) end
  end
  if def.id == "xp" and type(v) == "number" then
    c.bar:SetWidth(math.max(1, (w - 8) * v / 100))
    c.bar:Show()
  end
  if def.id == "durability" and type(v) == "number" and v < 50 then color(c.label, BAD) end
  if def.id == "ready" and type(v) == "number" then color(c.label, v == 2 and GOOD or (v == 1 and WARN or BAD)) end
  if def.kind == "flag" then color(c.label, v and INK or MUTE) end
  if v == nil then color(c.label, MUTE) end
  if def.kind == "text" then fitText(c.label, s, w - 8) else c.label:SetText(s) end
end

----------------------------------------------------------------------------
-- pages
----------------------------------------------------------------------------
local function sortRows(rows, page)
  local s = UI.sort[page]
  if not s or not s.id then
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
  sortRows(rows, page)
  -- header: grey labels, the sorted one white, a hairline under the row
  self.header:Show()
  self.header:ClearAllPoints()
  self.header:SetPoint("TOPLEFT", 0, -y0)
  self.header:SetWidth(sf:Width())
  self.headerCells:Reset()
  local hc = self.headerCells:Get()
  hc:SetPoint("LEFT", 0, 0)
  hc:SetWidth(NAME_W)
  hc.id, hc.def = nil, nil
  hc.label:SetJustifyH("LEFT")
  hc.label:SetText("Member")
  color(hc.label, DIM)
  local sorted = self.sort[page] or (page == "race" and { id = "level" }) or {}
  local x = NAME_W
  for _, col in ipairs(cols) do
    local h = self.headerCells:Get()
    h:SetPoint("LEFT", x, 0)
    h:SetWidth(col.w)
    h.id, h.def = col.def.id, col.def
    h.label:SetJustifyH(alignOf(col.def))
    fitText(h.label, shortLabel(col.def), col.w - 8)
    color(h.label, sorted.id == col.def.id and WHITE or DIM)
    x = x + col.w
  end
  self.headerCells:HideRest()
  -- rows
  self.rows:Reset()
  local y = y0 + ROW + 2
  local rowH = C.Settings().density == "compact" and ROW_COMPACT or ROW
  for i, row in ipairs(rows) do
    local r = self.rows:Get()
    r.row = row
    r:SetPoint("TOPLEFT", 0, -y)
    r:SetWidth(sf:Width())
    r:SetHeight(rowH)
    r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
    local cc = row.class and classColor(row.class) or MUTE
    if not row.online then cc = dimmed(cc) end
    local bc = row.me and WHITE or cc
    r.bar:SetColorTexture(bc[1], bc[2], bc[3], 1)
    color(r.name, row.addon and cc or MUTE)
    local nameText = row.short
    if row.me then nameText = row.short .. "  (you)" end
    if not row.addon then nameText = row.short .. "  (no addon)" end
    fitText(r.name, nameText, NAME_W - 16)
    local cx = NAME_W
    for k, col in ipairs(cols) do
      local c = self:Cell(r, k)
      c:SetPoint("LEFT", cx, 0)
      c:SetWidth(col.w)
      c:SetHeight(rowH)
      c:Show()
      fillCell(c, col.def, row, not C.Policy:CanSee(officer, row.me, col.def.id), col.w)
      cx = cx + col.w
    end
    for k = #cols + 1, #r.cells do r.cells[k]:Hide() end
    y = y + rowH
  end
  self.rows:HideRest()
  if y0 == 0 then self.labels:Reset() end
  if hidden > 0 then
    local l = self.labels:Get()
    l:SetPoint("TOPLEFT", 6, -y - 6)
    l:SetWidth(sf:Width() - 12)
    color(l, MUTE)
    l:SetText(string.format("%d more column%s do not fit: widen the window or untick some in Settings.", hidden, hidden == 1 and "" or "s"))
    y = y + 24
  end
  local reported = 0
  for _, r in ipairs(rows) do if r.addon then reported = reported + 1 end end
  if reported <= 1 then
    local l = self.labels:Get()
    l:SetPoint("TOPLEFT", 6, -y - 6)
    l:SetWidth(sf:Width() - 12)
    color(l, MUTE)
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
  skin(c, PANEL2, 1)
  c:SetHighlightTexture(FLAT, "ADD")
  c:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.04)
  c.title = text(c, 11, DIM, "LEFT", 220)
  c.title:SetPoint("TOPLEFT", 8, -7)
  c.leader = text(c, 14, WHITE, "LEFT", 220)
  c.leader:SetPoint("TOPLEFT", 8, -24)
  c.mine = text(c, 11, MUTE, "LEFT", 220)
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
        card.leader:SetText(string.format("%s  %s%s|r", top[1].short, hex(DIM), UI.Format(def, top[1].v)))
      else card.leader:SetText(hex(MUTE) .. "nobody yet|r") end
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
    color(l, MUTE)
    l:SetText("No funny stats ticked. Settings has the list.")
    y = 30
  end
  self.labels:HideRest()
  sf:SetContentHeight(y + 8)
end

-- the officers' page: summaries, then the controls, then the officer stats as a table
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
  local function say(s, c)
    local l = self.labels:Get()
    l:SetPoint("TOPLEFT", 6, -y)
    l:SetWidth(sf:Width() - 12)
    color(l, c or INK)
    fitText(l, s, sf:Width() - 16)
    y = y + 18
  end
  say(string.format("%d members, %d with the addon, %d online. Median level %s, %d below it, %d not seen for a week.",
    total, withAddon, online, median and tostring(median) or "?", below, unseen))
  if #noAddon > 0 then
    table.sort(noAddon)
    say("Without the addon: " .. table.concat(noAddon, ", "), DIM)
  end
  say(C.Policy:Describe(), DIM)
  self.buttons:Reset()
  local labels = { { "Visibility settings", function() UI:Open("settings") end },
    { "Ask everyone to resend", function() C.Comm:Ask(); C.Print("asked the guild to send their records again.") end },
    { "Broadcast policy now", function() C.Comm:SendPolicy(); C.Print("sent the visibility policy to the guild.") end } }
  local bx = 6
  for _, d in ipairs(labels) do
    local b = self.buttons:Get()
    b:SetPoint("TOPLEFT", bx, -y - 2)
    b:SetWidth(160)
    b:SetLabel(d[1])
    b:SetOn(true)
    b:SetScript("OnClick", d[2])
    bx = bx + 166
  end
  self.buttons:HideRest()
  y = y + 30
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
  cb:SetPoint("TOPLEFT", 6, -6)
  cb.label:SetText("Show what members see of me")
  cb:Set(self.meView and true or false)
  cb:SetOn(true)
  cb.fn = function(self) UI.meView = self:GetChecked(); UI:Draw() end
  self.checks:HideRest()
  local y = 30
  for _, cat in ipairs(C.Stats.CATS) do
    local l = self.labels:Get()
    l:SetPoint("TOPLEFT", 6, -y)
    l:SetWidth(w - 12)
    color(l, WHITE)
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
      color(a, hidden and MUTE or DIM)
      fitText(a, def.label, colW - 136)
      local b = self.labels:Get()
      b:SetPoint("TOPLEFT", 6 + col * colW + (colW - 130), -ly)
      b:SetWidth(124)
      b:SetJustifyH("RIGHT")
      local v = me and me.stats[def.id]
      if hidden then color(b, MUTE); b:SetText("(only you)")
      else
        color(b, v == nil and MUTE or INK)
        fitText(b, C.Sample:Error(def.id) and "?" or UI.Format(def, v), 120)
      end
      n = n + 1
    end
    y = y + math.ceil(n / 2) * 18 + 8
  end
  -- what could not be read, and why (a client function missing, a call that threw), one line each, so no "?" above
  -- stands without its reason
  local errs = {}
  for _, def in ipairs(C.Stats.list) do
    local e = C.Sample:Error(def.id)
    if e then errs[#errs + 1] = def.label .. ": " .. tostring(e) end
  end
  if #errs > 0 then
    local l = self.labels:Get()
    l:SetPoint("TOPLEFT", 6, -y)
    l:SetWidth(w - 12)
    l:SetJustifyH("LEFT")
    color(l, WHITE)
    l:SetText("Could not read")
    y = y + 20
    for _, s in ipairs(errs) do
      local a = self.labels:Get()
      a:SetPoint("TOPLEFT", 6, -y)
      a:SetWidth(w - 12)
      a:SetJustifyH("LEFT")
      color(a, BAD)
      fitText(a, s, w - 16)
      y = y + 18
    end
    y = y + 8
  end
  self.labels:HideRest()
  sf:SetContentHeight(y + 8)
end

-- the footer: when the roster last changed
function UI:DrawFooter()
  local s
  if not C.Roster:InGuild() then s = "Not in a guild"
  elseif not C.Roster.updatedAt then s = "No reports yet"
  else s = "Updated " .. (ago(C.Roster.updatedAt) or "") end
  self.footer:SetText(s)
end

function UI:Draw()
  self.drawing = true
  local page = self.page
  local officer = C.Roster:MeOfficer()
  if page == "officers" and not officer then page = "race"; self.page = page end
  local x = 0
  for _, d in ipairs(TAB_DEFS) do
    local b = self.tabs[d[1]]
    b:SetShown(d[1] ~= "officers" or officer)
    if b:IsShown() then
      b:SetPoint("LEFT", x, 0)
      x = x + d[3] + 2
      color(b.label, d[1] == page and WHITE or DIM)
      b.under:SetShown(d[1] == page)
    end
  end
  -- the scroll place survives a redraw; a page change starts at the top
  local bar = self.scroll.bar
  local keep = self.scrollTo or bar:GetValue() or 0
  self.scrollTo = nil
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
  local _, maxv = bar:GetMinMaxValues()
  bar:SetValue(math.max(0, math.min(keep, maxv or 0)))
  local rows = C.Roster:Rows()
  local online = 0
  for _, r in ipairs(rows) do if r.online and r.addon then online = online + 1 end end
  self.status:SetText(string.format("%d online with the addon  |  %s view", online, officer and "officer" or "member"))
  self:DrawFooter()
  self.drawing = false
end

----------------------------------------------------------------------------
-- the minimap button: the emblem in a one-pixel frame, dragged around the minimap's edge
----------------------------------------------------------------------------
function UI:OnWorld()
  if not C.Settings().minimap then if self.mini then self.mini:Hide() end return end
  if self.mini then self.mini:Show(); return end
  if not Minimap then return end
  local b = CreateFrame("Button", "CuteMinimapButton", Minimap, BD)
  self.mini = b
  b:SetSize(24, 24)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetMovable(true)
  skin(b, BLACK, 1)
  local icon = tex(b, "ARTWORK", LOGO)
  icon:SetPoint("TOPLEFT", 1, -1)
  icon:SetPoint("BOTTOMRIGHT", -1, 1)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b:SetHighlightTexture(FLAT, "ADD")
  b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.1)
  local function place()
    local angle = math.rad(C.Settings().minimapPos or 220)
    local r = (Minimap:GetWidth() or 140) / 2 + 6
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
