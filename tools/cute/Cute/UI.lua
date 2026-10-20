-- SPDX-License-Identifier: GPL-3.0-or-later
-- The window: one frame with its pages and Settings, drawn flat and dark the way ElvUI and Shadowed Unit Frames
-- draw theirs: one-pixel black borders, near-black panels, white and grey text in the client's narrow font, class
-- colours on names and nothing else coloured unless it means something (green ready, red low). Numbers sit on the
-- right of their columns, text on the left; a two-pixel class-coloured bar marks every member's row, white for you.
-- The tabs are the modules that are on (Modules.lua), in their order, then Settings; the dashboard's pages, drawn
-- here, are the core's and always on:
--   Race           every member as a row: level, XP, zone, pace, the leveling stats
--   Prog           readiness, item level, empty slots, the enchants you lack, consumables, what
--                  you have met in play, the gaps only you see
--   Hall of Shame  a card per funny stat with its leader
--   Statistics     what the guild discovered in play (bosses by instance, dungeons, raids, reputations) and the
--                  game's own statistics as a leaderboard: categories left, you and the leader right, a click ranks
--                  every member (an empty state where there is neither)
--   Officers       summaries, what the guild has learned, the officers' stats, the controls (officer ranks only)
--   Me             your whole record, with what members see
-- A module's page (the Guide, Guide.lua; a module addon's) draws with the same pieces into the same scroll area.
-- Columns and cards come from the registry (Stats.lua); the policy (Policy.lua) decides which cells a member sees.
-- Built on first open; nothing updates while it is hidden. A guild of a few hundred stays light: the tables and the
-- Statistics ranking draw only the rows in view (a virtual list, filled as you scroll, the sorted list kept between
-- scrolls), a redraw comes at most once a second and only for a value the open page shows, and a label's cut is
-- measured once per text and width.
local _, C = ...
local UI = { page = "race", sort = {}, gameOpen = {} }
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
local MUTE = { 0.52, 0.52, 0.52 } -- (text: 4.5:1 on PANEL2)
local GOOD = { 0.45, 0.83, 0.47 }
local WARN = { 0.93, 0.74, 0.35 }
local BAD = { 0.88, 0.36, 0.33 }
local BG = { 0.035, 0.035, 0.035 }
local PANEL = { 0.07, 0.07, 0.07 }
local PANEL2 = { 0.11, 0.11, 0.11 }
local LINE = { 0.2, 0.2, 0.2 }
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
  fs.cuteSize = size or 12 -- (fitText's cache is per size)
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
-- a flat check box: a small square, filled white when checked, its edge a mid grey (3.5:1 on the window's panels, so
-- an unticked box shows: a black edge was 1.1:1). Callers set cb.fn rather than the OnClick script, so the fill always
-- follows the click. A box alone (the Everyone / Only-you pairs); a box with a label is a check row, below
local EDGE = 0.42
local function check(parent)
  local cb = CreateFrame("CheckButton", nil, parent, BD)
  cb:SetSize(14, 14)
  skin(cb, PANEL2)
  if cb.SetBackdropBorderColor then cb:SetBackdropBorderColor(EDGE, EDGE, EDGE, 1) end
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
-- a check row: one full-width button, as the Settings sections and the Statistics categories are rows (UI:MakeLine),
-- with the box drawn inside it as a visual (a plain frame, which takes no mouse) and the label beside. A click
-- anywhere on the row ticks it: the row is the button, so nothing depends on a hit rect widened over the label
-- (0.6.0 did that with SetHitRectInsets, and on the live client the Modules boxes took no click). Callers set r.fn,
-- called after the fill follows the click; Set, SetOn and GetChecked as the check box's
local function checkRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(ROW)
  r.checkRow = true
  r.box = CreateFrame("Frame", nil, r, BD)
  r.box:SetSize(14, 14)
  r.box:SetPoint("LEFT", 0, 0)
  skin(r.box, PANEL2)
  if r.box.SetBackdropBorderColor then r.box:SetBackdropBorderColor(EDGE, EDGE, EDGE, 1) end
  r.fill = flat(r.box, "ARTWORK", WHITE, 1)
  r.fill:SetPoint("TOPLEFT", 3, -3)
  r.fill:SetPoint("BOTTOMRIGHT", -3, 3)
  r.fill:Hide()
  r.label = text(r, 12, INK, "LEFT", 220)
  r.label:SetPoint("LEFT", r.box, "RIGHT", 6, 0)
  r:SetHighlightTexture(FLAT, "ADD")
  r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)
  r:SetScript("OnClick", function(self, ...)
    self:Set(not self.on)
    if self.fn then self.fn(self, ...) end
  end)
  function r:Set(on) self.on = on and true or false; self.fill:SetShown(self.on) end
  function r:GetChecked() return self.on == true end
  function r:SetOn(on) self:SetEnabled(on); color(self.label, on and INK or MUTE); self.fill:SetVertexColor(1, 1, 1, on and 1 or 0.4) end
  return r
end
UI.Check, UI.CheckRow, UI.Button, UI.Text, UI.Skin, UI.Flat = check, checkRow, button, text, skin, flat
-- (for Guide.lua, which draws its page with the window's own pieces)
UI.COLORS = { WHITE = WHITE, INK = INK, DIM = DIM, MUTE = MUTE, GOOD = GOOD, WARN = WARN, BAD = BAD }
UI.Color, UI.Hex, UI.Dimmed, UI.ROW = color, hex, dimmed, ROW
UI.ClassColor = function(class) return classColor(class) end
local function tooltip(owner, fill)
  owner:SetScript("OnEnter", C.Safe(function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    fill(GameTooltip, self)
    GameTooltip:Show()
  end, "tooltip"))
  owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
-- a label cut after a whole word with "..." when it is wider than its box; true when it fit whole. The cut is kept per font size, width and
-- text, so a redraw sets each label once and measures nothing it measured before. Text with a Kstring in it (a name
-- the client encodes, Core.lua) is cut at words only, never inside the escape; the box clips the rest
local fitCache, fitCount = {}, 0
local function fitText(fs, s, room)
  room = math.floor(room or ((fs:GetWidth() or 0) - 4))
  s = s == nil and "" or tostring(s)
  if s == "" then fs:SetText(s); return true end
  local key = (fs.cuteSize or 12) .. ":" .. room
  local byText = fitCache[key]
  if not byText then
    if fitCount > 4000 then fitCache, fitCount = {}, 0 end
    byText = {}
    fitCache[key] = byText
  end
  local done = byText[s]
  if done then fs:SetText(done); return done == s end
  fitCount = fitCount + 1
  local width = fs.GetUnboundedStringWidth or fs.GetStringWidth
  local result, shown = s, s
  fs:SetText(s)
  if width(fs) > room then
    -- (no glyph is under two pixels wide, so a long text starts from what could fit at most)
    local cut = (#s > room / 2 + 8 and not C.IsKstring(s)) and s:sub(1, math.floor(room / 2) + 8) or s
    result = nil
    while true do
      local shorter = cut:match("^(.*%S)%s+%S+$")
      if not shorter then break end
      cut = shorter
      shown = cut .. "..."
      fs:SetText(shown)
      if width(fs) <= room then result = shown; break end
    end
    while not result and #cut > 1 and not C.IsKstring(cut) do
      cut = cut:sub(1, -2)
      shown = cut .. "..."
      fs:SetText(shown)
      if width(fs) <= room then result = shown end
    end
    -- a Kstring no word cut fits stays whole and the box clips it; the label shows what is kept, first draw or later
    if not result then result = (C.IsKstring(cut) and cut == s) and s or (cut .. "...") end
    if result ~= shown then fs:SetText(result) end
  end
  byText[s] = result
  return result == s
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

-- a list drawn only where it shows: of n items, item i sits at top + (i - 1) * h in the scroll child, and only the
-- ones in view, with MARGIN more either side, get a widget. Widget k holds the items i with (i - 1) % size == k - 1, so
-- a scroll of a row or two fills a row or two, not the screen. Set gives new contents (every widget fills again as it
-- shows); Show draws the window at a scroll offset; Refill draws one item again where it shows
local MARGIN = 4
local function virtual(parent, make)
  local v = { items = {}, n = 0, size = 0, gen = 0 }
  function v:Set(n, top, h, fill) self.n, self.top, self.h, self.fill = n, top, h, fill; self.gen = self.gen + 1 end
  function v:Clear()
    self.n = 0
    for _, w in ipairs(self.items) do if w:IsShown() then w:Hide() end end
  end
  function v:Show(offset, view)
    local h = self.h
    if self.n == 0 or not h or h <= 0 then self:Clear(); return 0 end
    local size = math.ceil(view / h) + 2 * MARGIN + 1
    if size ~= self.size then
      for _, w in ipairs(self.items) do w.idx = nil; if w:IsShown() then w:Hide() end end
      self.size = size
    end
    local first = math.max(1, math.floor((offset - self.top) / h) + 1 - MARGIN)
    local last = math.min(self.n, first + size - 1)
    local filled = 0
    for i = first, last do
      local k = (i - 1) % size + 1
      local w = self.items[k]
      if not w then w = make(parent); self.items[k] = w end
      if w.idx ~= i or w.gen ~= self.gen then
        self.fill(w, i, self.top + (i - 1) * h)
        w.idx, w.gen = i, self.gen
        filled = filled + 1
      end
      if not w:IsShown() then w:Show() end
    end
    for k = 1, size do
      local w = self.items[k]
      if w and (w.idx == nil or w.idx < first or w.idx > last) and w:IsShown() then w:Hide() end
    end
    self.first, self.last = first, last
    return filled
  end
  function v:Refill(i)
    if not self.size or self.size == 0 or i > self.n then return end
    local w = self.items[(i - 1) % self.size + 1]
    if not w or w.idx ~= i then return end
    -- in view: filled now; out of it: filled when it comes back
    if w.gen == self.gen and w:IsShown() then self.fill(w, i, self.top + (i - 1) * self.h) else w.idx = nil end
  end
  return v
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
  -- a scroll draws the rows that come into view and nothing else (UI:OnScroll)
  bar:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v); UI:OnScroll() end)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(_, delta)
    local lo, hi = bar:GetMinMaxValues()
    bar:SetValue(math.max(lo, math.min(hi, bar:GetValue() - delta * 44)))
  end)
  sf:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then child:SetWidth(w) end end)
  sf.child, sf.bar = child, bar
  -- the height in view
  function sf:View()
    local view = self:GetHeight() or 0
    if view < 50 then view = (UI.frame:GetHeight() or H) - HEAD - TABS - FOOT - 32 end
    return view
  end
  function sf:SetContentHeight(h)
    child:SetHeight(math.max(h, 1))
    local view = self:View()
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
-- a row's value of a stat as this client shows it: a member's level and zone as the guild roster gives them (the
-- server's word, not their addon's: Roster.lua), and a member's Missing enchants keeping only the slots this client
-- knows the guild enchants (Stats.lua's filter), so an older client's list never names a slot nobody can enchant
local function valueOf(def, row)
  if row.guild and not row.me then
    if def.id == "level" and type(row.level) == "number" then return row.level end
    if def.id == "zone" and type(row.zone) == "string" then return row.zone end
  end
  local v = row.stats[def.id]
  if def.filter and type(v) == "table" and not row.me then return def.filter(v) end
  return v
end
UI.ValueOf = valueOf
local function listNames(def, v)
  local names = {}
  if type(v) ~= "table" then return names end
  for _, e in ipairs(def.of) do if v[e[1]] then names[#names + 1] = e[2] end end
  return names
end
-- who sees a stat, for a tooltip: everyone, or you and the officers (and why, where the officers' Everyone is kept
-- with a stat it would tell a member: Policy.lua P:KeptWith)
-- On an officer's client with a change not saved, what the members go by (the line) comes first, and the change is
-- marked not saved yet
function UI.WhoSees(id)
  local P = C.Policy
  local pending = P:EditPending()
  local route = pending and P:LineRoute(id) or P:Route(id)
  local s
  if route == "all" then s = "Everyone sees this."
  else
    local with = pending and P:LineKeptWith(id) or P:KeptWith(id)
    s = with and ("Only you and the officers see this: it would tell members " .. P:Label(with) .. ", which the officers keep.") or "Only you and the officers see this."
  end
  if pending and P:Route(id) ~= route then
    s = s .. (route == "all" and " Your change, not saved yet, would keep it to you and the officers." or " Your change, not saved yet, would show it to everyone.")
  end
  return s
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
  elseif def.kind == "list" then
    local n = listCount(def, v)
    if not n then return "?" end
    -- (a count of what is missing has no "out of": the slots it is out of are learned)
    return def.countOnly and tostring(n) or string.format("%d/%d", n, #def.of)
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
-- pips: none dark, then brighter by quarters to white (the Legacy categories); 1 and 2 are a step started and done
local PIP = { [0] = { 0.16, 0.16, 0.16 }, [1] = { 0.5, 0.5, 0.5 }, [2] = WHITE, [3] = { 0.3, 0.3, 0.3 }, [4] = { 0.45, 0.45, 0.45 }, [5] = { 0.6, 0.6, 0.6 }, [6] = { 0.75, 0.75, 0.75 }, [7] = { 0.9, 0.9, 0.9 }, [8] = WHITE }

-- a column header's short form, where the label would not fit a column
local SHORT = { xp = "XP %", xp_hour = "XP/h", xp_session = "XP/h today", to60 = "To 60", played = "Played", played_lvl = "This lvl", rested = "Rested",
  group = "Group", quests_done = "Quests", quests_today = "Today", quests_log = "In log", quests_ready = "Ready", deaths_lvl = "Deaths", legacy = "Legacy",
  flights_known = "Flights", longest_flight = "Flight", hearth = "Hearth", hearths = "Hearths", ghost_time = "Ghost", gold_earned = "Earned", gold_quests = "Quest gold",
  vendor_sales = "Sold", talents_free = "Talents", zones_seen = "Zones", logins = "Logins", longest = "Longest", levelups = "Lvl-ups", still = "Stood still",
  ilvl = "iLvl", ilvl_slots = "Slots", empty_slots = "Empty", enchanted = "Enchanted", unenchanted = "No ench", old_gear = "Old gear", greens = "Greens",
  resist_fire = "FR", resist_nature = "NR", resist_frost = "FrR", resist_shadow = "SR", resist_arcane = "AR", food = "Food", bosses = "Bosses", dungeons_seen = "Dungeons",
  bags_free = "Bags free", bags_size = "Bags", buffs_missing = "Buffs", durability = "Dura", pvp_pts = "Rank pts", pvp_rank = "PvP", raids = "Raids", stones = "Stones",
  bank_in = "Bank in", bank_out = "Bank out", consumed = "Consumed", addon_ver = "Version", main = "Main", last_login = "Last login", raid_spec = "Raid spec",
  weekly_raids = "Raids/wk", deaths_today = "Today", hearth_waste = "Wasted HS", whispers = "Whispers/h", gchat = "Guild lines", inspected = "Inspected",
  ghost_yards = "Ghost yds", where = "Where r u", grey_gold = "Grey gold", lc_done = "Challenges", lc_total = "Listed", lc_pts = "Legacy pts",
  lc_free = "Unspent", lc_renown = "Renown", lc_prof = "Prof. tree", lc_adv = "Adv. tree", lc_prog = "Prog. tree", lc_last = "Latest", lc_cats = "Categories" }
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
  prog = { "ready", "ilvl", "empty_slots", "unenchanted", "durability", "potions", "flasks", "food", "bosses", "dungeons_seen", "lc_done" },
  -- (838 px of columns at 1040 wide, measured by the harness: Prog's eleven take 671, these ten 782. Raids and Raids
  -- this week stay in the checklist; Forever has shown no raid yet)
  officers = { "gold", "bank_in", "bank_out", "bosses", "dungeons_seen", "potions", "main", "role", "last_login", "addon_ver" },
}
UI.DEFAULT_COLS = DEFAULT_COLS
local CAT_OF_PAGE = { race = "leveling", prog = "prog", officers = "officer", shame = "funny" }
UI.CAT_OF_PAGE = CAT_OF_PAGE
-- the stats of other categories an officer may want beside the officers' own: what members met in play and carry
local PAGE_EXTRA = { officers = { "raids", "bosses", "dungeons_seen", "potions", "flasks", "food" } } -- (consumed is the officer category's own: it reads 0 until Forever has raids, so it is not a default)
UI.PAGE_EXTRA = PAGE_EXTRA
-- every stat a page can show as a column, in order: its category's, then its extras
function UI.Candidates(page)
  local out = {}
  for _, def in ipairs(C.Stats.byCat[CAT_OF_PAGE[page]] or {}) do out[#out + 1] = def end
  for _, id in ipairs(PAGE_EXTRA[page] or {}) do local def = C.Stats.byId[id]; if def then out[#out + 1] = def end end
  return out
end

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
  for _, def in ipairs(UI.Candidates(page)) do
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
-- the tabs: one per module whose page shows (Modules.lua), then Settings, the shell's own. A module's tab is as wide as
-- it says, or fits its title
local SETTINGS_TAB = { id = "settings", title = "Settings", tab = 80 }
function UI:Tab(m)
  local b = self.tabs[m.id]
  if b then return b end
  b = button(self.tabRow, m.title, m.tab or 64, TABS)
  b.w = m.tab
  if not b.w then
    local measure = b.label.GetUnboundedStringWidth or b.label.GetStringWidth
    b.w = math.max(64, math.ceil(measure(b.label) or 0) + 28)
    b:SetWidth(b.w)
  end
  b.page = m.id
  b.under = flat(b, "OVERLAY", WHITE, 1)
  b.under:SetPoint("BOTTOMLEFT", 1, 1)
  b.under:SetPoint("BOTTOMRIGHT", -1, 1)
  b.under:SetHeight(2)
  b.under:Hide()
  b:SetScript("OnClick", function() UI:Open(m.id) end)
  self.tabs[m.id] = b
  return b
end
function UI:DrawTabs(page, officer)
  local x = 0
  local list = C.Modules.Pages(officer)
  list[#list + 1] = SETTINGS_TAB
  for _, b in pairs(self.tabs) do b.keep = false end
  for _, m in ipairs(list) do
    local b = self:Tab(m)
    b.keep = true
    if not b:IsShown() then b:Show() end
    b:SetPoint("LEFT", x, 0)
    x = x + b.w + 2
    color(b.label, m.id == page and WHITE or DIM)
    b.under:SetShown(m.id == page)
  end
  for _, b in pairs(self.tabs) do if not b.keep and b:IsShown() then b:Hide() end end
end

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
  -- a tab for every module there is, shown or not (one that registers later gets its own as it first shows)
  self.tabRow, self.tabs = tabs, {}
  for _, m in ipairs(C.Modules.list) do if m.page then self:Tab(m) end end
  self:Tab(SETTINGS_TAB)
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
  -- the members' rows and the Statistics page's two columns are virtual lists: widgets for what is in view only
  self.rows = virtual(self.scroll.child, function(parent) return UI:MakeRow(parent) end)
  self.cards = pool(self.scroll.child, function(parent) return UI:MakeCard(parent) end)
  self.labels = pool(self.scroll.child, function(parent) return text(parent, 12, INK) end)
  self.buttons = pool(self.scroll.child, function(parent) return button(parent, "", 160) end)
  self.checks = pool(self.scroll.child, function(parent) return check(parent) end)
  self.catLines = virtual(self.scroll.child, function(parent) return UI:MakeLine(parent) end)
  self.lines = virtual(self.scroll.child, function(parent) return UI:MakeLine(parent) end)
  -- the band: a strip above the scroll area for what stays in view while the rows scroll (a table's column header,
  -- the officers' summary, the Statistics page's headings); UI:SetBand gives it its height and moves the scroll area
  self.band = CreateFrame("Frame", nil, self.content)
  self.band:SetPoint("TOPLEFT", 8, -8)
  self.band:SetPoint("TOPRIGHT", -18, -8)
  self.band:SetHeight(1)
  self.band:Hide()
  self.bandLabels = pool(self.band, function(parent) return text(parent, 12, INK) end)
  self.bandButtons = pool(self.band, function(parent) return button(parent, "", 160) end)
  -- (a line in the band with a tooltip and a click: the Guide's next best thing and where its knowledge comes from)
  self.bandLines = pool(self.band, function(parent) return UI:MakeLine(parent) end)
  self.header = CreateFrame("Frame", nil, self.band)
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
-- a page by its module's id, or Settings (at a section: "general", "vis", "rules", "modules" or a module's id). A page
-- whose module is off, or an officer's for a member, opens Race
function UI:Open(page, section)
  self:Build()
  page = page or self.page
  if page ~= "settings" and not C.Modules.Page(page, C.Roster:MeOfficer()) then page = "race" end
  if section and section ~= self.section then self.section = section; self.scrollTo = 0 end
  if page ~= self.page then self.scrollTo = 0 end -- a new page starts at the top; a redraw keeps the place
  self.page = page
  if not self.frame:IsShown() then self.frame:Show() else self:Draw() end
end
-- a redraw, at most one a second while the window shows and none while it is hidden (it draws as it opens), so a
-- burst of guild messages or roster events draws once
local function clock() return (GetTime and GetTime()) or 0 end
function UI:Refresh()
  if not (self.frame and self.frame:IsShown()) or self.drawing then return end
  if self.refreshing then return end
  self.refreshing = true
  local wait = math.min(1, math.max(0.05, 1 - (clock() - (self.drawnAt or -10))))
  C_Timer.After(wait, C.Safe(function() UI.refreshing = false; if UI.frame:IsShown() then UI:Draw() end end, "refresh"))
end
-- one of your own values changed (Sample.lua): nothing to do unless the open page shows it and its text changed. On a
-- table page your row is the first and moves nowhere, so only it is filled again, once a second at most
function UI:ValueChanged(id, old, new)
  if not (self.frame and self.frame:IsShown()) or self.drawing then return end
  if not (self.shownIds and self.shownIds[id]) then return end
  local def = C.Stats.byId[id]
  if def and UI.Format(def, old) == UI.Format(def, new) then return end
  if self.page == "race" or self.page == "prog" or self.page == "officers" then
    if self.mineDue or self.refreshing then return end
    self.mineDue = true
    C_Timer.After(1, C.Safe(function()
      UI.mineDue = false
      if UI.frame:IsShown() and UI.rows.n > 0 then UI.rows:Refill(1) end
    end, "refresh: your row"))
  else self:Refresh() end
end
-- values from a member's addon (Roster.lua): a new member (the status line counts them), or a value the open page
-- shows of the members (the Me page shows only yours), draws again
function UI:Arrived(kv, created)
  if not (self.frame and self.frame:IsShown()) or self.refreshing then return end
  if created then self:Refresh() return end
  if self.page == "me" then return end
  local ids = self.shownIds
  if not ids then return end
  for id in pairs(kv) do if ids[id] then self:Refresh() return end end
end
-- the scroll moved: the virtual lists draw the rows that came into view, from the lists the last Draw sorted
-- a module's own virtual list, by a key of its own: made once on the scroll area with the row make(parent) builds (on
-- the window's pieces: UI:MakeLine, UI.Text, UI.Button, UI.Flat), widgets for the rows in view only, and cleared by
-- the draw of a page that does not fill it, as the window's own lists are
UI.lists = {}
function UI:List(key, make)
  local v = self.lists[key]
  if not v then v = virtual(self.scroll.child, make); self.lists[key] = v end
  return v
end
-- the band's height (0 hides it); the scroll area and its bar start under it
function UI:SetBand(h)
  if self.bandH == h then return end
  self.bandH = h
  self.band:SetHeight(math.max(h, 1))
  self.band:SetShown(h > 0)
  self.scroll:SetPoint("TOPLEFT", 8 + (self.insetX or 0), -8 - h)
  self.scroll.bar:SetPoint("TOPRIGHT", -7, -8 - h)
end
-- room kept on the left of the scroll area and the band (Settings' list of sections); 0 gives it back
function UI:SetInset(x)
  if (self.insetX or 0) == x then return end
  self.insetX = x
  self.band:SetPoint("TOPLEFT", 8 + x, -8)
  self.scroll:SetPoint("TOPLEFT", 8 + x, -8 - (self.bandH or 0))
end

function UI:OnScroll()
  if self.drawing or not self.virtual then return end
  self.virtual()
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
    if self.def.id == "ready" then
      -- (what the members' clients count, the officer's change not saved set aside, and that change marked)
      local line = C.Stats.ReadyCountsText(C.Policy:LineReadyCounts())
      tip:AddLine("Counts now: " .. line .. ".", 0.7, 0.7, 0.7, true)
      local own = C.Stats.ReadyCountsText()
      if C.Policy:EditPending() and own ~= line then tip:AddLine("Your change, not saved yet, would count " .. own .. ".", 0.7, 0.7, 0.7, true) end
    end
    tip:AddLine(UI.WhoSees(self.def.id), 0.6, 0.6, 0.6, true)
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
  -- on the Officers page a click picks the member, for the band's Mark untrusted (DrawOfficers)
  r:SetScript("OnClick", function(self)
    local row = self.row
    if UI.page ~= "officers" or not row or row.me or not row.guid or not row.addon then return end
    UI.picked = UI.picked ~= row.guid and row.guid or nil
    UI:Draw()
  end)
  tooltip(r, function(tip, self)
    local row = self.row
    if not row then return end
    tip:AddLine(row.short, 1, 1, 1)
    if row.guild then tip:AddLine(row.guild.rankName or "", 0.7, 0.7, 0.7) end
    if not row.addon then tip:AddLine("No Cute addon yet.", 0.6, 0.6, 0.6)
    elseif row.me then tip:AddLine("You.", 0.6, 0.6, 0.6)
    else tip:AddLine(row.online and "Online" or ("Last seen " .. (ago(row.seen) or "?")), 0.6, 0.6, 0.6) end
    -- what the officers alone see: why a member's addon is doubted, and their word on it
    if not row.me and C.Roster:MeOfficer() then
      if row.suspect then tip:AddLine("Suspect: " .. tostring(row.suspect.why) .. ", " .. (ago(row.suspect.at) or "") .. ".", 0.9, 0.45, 0.4, true) end
      if row.untrusted then tip:AddLine("Untrusted: left out of what the guild learns and of the rankings.", 0.9, 0.6, 0.3, true) end
      if UI.page == "officers" and row.guid and row.addon then tip:AddLine("Click to select, then Mark untrusted above.", 0.45, 0.45, 0.45) end
    end
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
      local v = valueOf(def, row)
      if def.id == "unenchanted" and type(v) == "table" then
        -- each slot missing, with how many members the guild has seen with an enchant there: on your own row the kind
        -- of item you wear there ("Ranged (Bows)"), whose count it is; on a member's the slot's (their kinds are theirs).
        -- Seen, not have: the count never falls, as members leave or change their gear
        local any = false
        local g = row.me and C.Stats.Gear and C.Stats.Gear() or nil
        for _, e in ipairs(def.of) do
          if v[e[1]] then
            any = true
            local worn = g and g.slot[e[1]]
            local kind = worn and worn.kind and C.Stats.EnchantKnown(e[1], worn.kind) and worn.kind or nil
            -- (seen on how many, or the seed's word where the guild has seen none yet)
            tip:AddDoubleLine(kind and (e[2] .. " (" .. C.Stats.KindName(kind) .. ")") or e[2], C.Stats.EnchantSource(e[1], kind), 0.8, 0.8, 0.8, 1, 1, 1)
          end
        end
        if not any then tip:AddLine("none", 0.9, 0.9, 0.9) end
      elseif def.kind == "list" then
        local names = listNames(def, v)
        tip:AddLine(#names > 0 and table.concat(names, ", ") or "none", 0.9, 0.9, 0.9, true)
      elseif def.id == "buffs_missing" and row.me and type(v) == "number" then
        -- each one missing, with why it counts as one the guild gives (two guild mates, or one three times)
        local names = C.Stats.MissingBuffs()
        for _, name in ipairs(names) do
          local b = C.Stats.Buff(name) or {}
          local from, times = tonumber(b.nfrom) or 0, tonumber(b.times) or 0
          tip:AddDoubleLine(name, string.format("from %d guild mate%s, %d time%s", from, from == 1 and "" or "s", times, times == 1 and "" or "s"), 0.8, 0.8, 0.8, 1, 1, 1)
        end
        if #names == 0 then tip:AddLine(C.Stats.Grouped() and "none missing" or "Counted in a group or an instance; you are in neither.", 0.9, 0.9, 0.9, true) end
      elseif def.kind == "pips" and def.id == "lc_cats" and type(v) == "string" then
        -- the Legacy categories by name from this client's own walk, the row's class category last; your own
        -- pips say the exact count, a member's the quarter the pip stands for
        local cats = C.Stats.LegacyCategories(C.Stats.Legacy(), row.class)
        for k = 1, #v do
          local e = cats[k]
          local d = tonumber(v:sub(k, k)) or 0
          local what = (row.me and e) and (e.done .. " of " .. e.total) or (C.Stats.PIP_WORDS[d] or "?")
          tip:AddDoubleLine(e and e.name or ("Category " .. k), what, 0.8, 0.8, 0.8, 1, 1, 1)
        end
      elseif def.kind == "pips" and type(v) == "string" then
        local done, started = select(2, v:gsub("2", "")), select(2, v:gsub("1", ""))
        tip:AddLine(string.format("%d of %d steps done, %d in the log", done, #v, started), 0.9, 0.9, 0.9)
      elseif def.id == "ready" and type(v) == "number" then
        -- the gaps behind the verdict: the ones it counts, which everyone may see; an officer is told the others are
        -- in their own columns
        if not row.me and not C.Policy.CurrentReady(row.stats.addon_ver) then
          -- (a 0.5.x Cute counted every gap: its verdict, not this client's count)
          tip:AddLine("Counted by Cute " .. tostring(row.stats.addon_ver or "0.5") .. ", every gap: an empty slot, a missing enchant, durability under 50% and no potions.", 0.9, 0.9, 0.9, true)
        end
        -- (a member's verdict was counted by the line's policy, which their client routes by: an officer's own change
        -- not saved counts their own row alone. One counted before a change the member has not reported since says so)
        local counts = row.me and C.Stats.ReadyCounts() or C.Policy:LineReadyCounts()
        local n = 0
        for _ in pairs(counts) do n = n + 1 end
        if row.me or C.Policy.CurrentReady(row.stats.addon_ver) then
          local gaps = C.Stats.ReadyGaps(row.stats, counts) or {}
          tip:AddLine(#gaps == 0 and "No gaps." or table.concat(gaps, ", "), 0.9, 0.9, 0.9, true)
          tip:AddLine("Counts " .. C.Stats.ReadyCountsText(counts) .. ".", 0.7, 0.7, 0.7, true)
          if not row.me and v ~= (#gaps == 0 and 2 or (#gaps * 2 <= n and 1 or 0)) then
            tip:AddLine("Counted before the officers' last change: the member's next report counts it again.", 0.6, 0.6, 0.6, true)
          end
        end
        if C.Roster:MeOfficer() and n < #C.Stats.READY_INPUTS then
          tip:AddLine("The gaps the officers keep are in their own columns, not counted here.", 0.6, 0.6, 0.6, true)
        end
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

local INVERSE = { empty_slots = true, unenchanted = true, old_gear = true }
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
  local v = valueOf(def, row)
  color(c.label, INK)
  if def.kind == "pips" and type(v) == "string" and v ~= "" then
    c.label:SetText("")
    for k = 1, math.min(#v, def.pips or 13) do
      local p = c.pips[k]
      if not p then p = flat(c, "ARTWORK", WHITE, 1); p:SetSize(5, 10); p:SetPoint("LEFT", 4 + (k - 1) * 7, 0); c.pips[k] = p end
      local d = tonumber(v:sub(k, k)) or 0
      local col = PIP[d] or PIP[0]
      p:SetColorTexture(col[1], col[2], col[3], 1)
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
-- the members in a page's order: you, then those with the addon by the sorted column (unreported values last), then
-- those without it online, then those without it offline, so a big guild's first screen is the members who report.
-- Each row's sort value is worked out once, not in every comparison
local function sortRows(rows, page)
  local s = UI.sort[page]
  -- (a sort saved on a stat the registry no longer has, 0.3.x's attunements say, sorts by nothing)
  if not s or not s.id or not C.Stats.byId[s.id] then s = page == "race" and { id = "level", desc = true } or nil end
  local def = s and C.Stats.byId[s.id]
  for _, r in ipairs(rows) do
    r.tier = r.me and 0 or (r.addon and 1 or (r.online and 2 or 3))
    local v
    if s then
      -- (the guild roster still knows the level and zone of a member without the addon)
      if r.addon then v = def and valueOf(def, r) or r.stats[s.id] else v = (s.id == "level" and r.level) or (s.id == "zone" and r.zone) or nil end
      if def and def.kind == "list" then v = listCount(def, v)
      elseif def and def.kind == "pips" then v = type(v) == "string" and select(2, v:gsub("2", "")) or nil end
      if type(v) == "boolean" then v = v and 1 or 0 end
      if type(v) ~= "number" and type(v) ~= "string" then v = nil end
    end
    r.sv = v
    r.sx = (s and s.id == "level" and r.addon and type(r.stats.xp) == "number") and r.stats.xp or nil
  end
  local desc = s and s.desc
  table.sort(rows, function(a, b)
    if a.tier ~= b.tier then return a.tier < b.tier end
    local va, vb = a.sv, b.sv
    if va == nil or vb == nil then
      if va ~= nil then return true end
      if vb ~= nil then return false end
      if not s and a.online ~= b.online then return a.online end
      return a.sort < b.sort
    end
    if type(va) ~= type(vb) then va, vb = tostring(va), tostring(vb) end
    if va == vb then
      local xa, xb = a.sx, b.sx
      if xa and xb and xa ~= xb then if desc then return xa > xb else return xa < xb end end
      return a.sort < b.sort
    end
    if desc then return va > vb else return va < vb end
  end)
end

-- the members a page lists: everyone, or the online ones and you when offline members are hidden (a copy: the page
-- sorts it)
local function rowsShown()
  local all, out = C.Roster:Rows(), {}
  local offline = C.Settings().offline
  for _, r in ipairs(all) do if offline or r.online or r.me then out[#out + 1] = r end end
  return out
end

-- a table page: the header row and one row per member, virtual (only the rows in view have widgets; Draw and the
-- scroll call self.virtual). y0: room above it the page used already (the officers' lines)
function UI:DrawTable(page, y0)
  y0 = y0 or 0
  local sf = self.scroll
  local width = sf:Width()
  local room = width - NAME_W - 8
  local cols, hidden = columnsFor(page, room)
  local officer = C.Roster:MeOfficer()
  local rows = rowsShown()
  sortRows(rows, page)
  -- header: grey labels, the sorted one white, a hairline under the row
  self.header:Show()
  self.header:ClearAllPoints()
  self.header:SetPoint("TOPLEFT", 0, -y0)
  self.header:SetWidth(width)
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
  local sig = {}
  for _, col in ipairs(cols) do
    local h = self.headerCells:Get()
    h:SetPoint("LEFT", x, 0)
    h:SetWidth(col.w)
    h.id, h.def = col.def.id, col.def
    h.label:SetJustifyH(alignOf(col.def))
    fitText(h.label, shortLabel(col.def), col.w - 8)
    color(h.label, sorted.id == col.def.id and WHITE or DIM)
    x = x + col.w
    sig[#sig + 1] = col.def.id
    self.shownIds[col.def.id] = true
  end
  if sorted.id then self.shownIds[sorted.id] = true end
  self.headerCells:HideRest()
  -- rows: the cells are placed again only when the columns, the width or the row height change
  local rowH = C.Settings().density == "compact" and ROW_COMPACT or ROW
  local layout = width .. ":" .. rowH .. ":" .. table.concat(sig, ",")
  if layout ~= self.tableLayout then self.tableLayout = layout; self.layoutGen = (self.layoutGen or 0) + 1 end
  local layoutGen = self.layoutGen
  self:SetBand(y0 + ROW + 2)
  local top = 0
  self.rows:Set(#rows, top, rowH, function(r, i, y)
    local row = rows[i]
    r.row = row
    r:SetPoint("TOPLEFT", 0, -y)
    if r.layoutGen ~= layoutGen then
      r:SetWidth(width)
      r:SetHeight(rowH)
      local cx = NAME_W
      for k, col in ipairs(cols) do
        local c = self:Cell(r, k)
        c:SetPoint("LEFT", cx, 0)
        c:SetWidth(col.w)
        c:SetHeight(rowH)
        cx = cx + col.w
      end
      for k = #cols + 1, #r.cells do r.cells[k]:Hide() end
      r.layoutGen = layoutGen
    end
    local picked = page == "officers" and row.guid ~= nil and row.guid == self.picked
    r.bg:SetColorTexture(1, 1, 1, picked and 0.1 or (i % 2 == 0 and 0.03 or 0))
    local cc = row.class and classColor(row.class) or MUTE
    if not row.online then cc = dimmed(cc) end
    local bc = row.me and WHITE or cc
    r.bar:SetColorTexture(bc[1], bc[2], bc[3], 1)
    color(r.name, row.addon and cc or MUTE)
    -- "(you)" and "(no addon)" only where they fit whole: a two-word name keeps its words, and the grey of a member
    -- without the addon says it already. An officer sees a member they marked untrusted, or whose addon sent what
    -- cannot be, marked so (the row's tooltip says why)
    local suffix = row.me and "  (you)" or (not row.addon and "  (no addon)" or nil)
    if not suffix and officer then suffix = row.untrusted and "  (untrusted)" or (row.suspect and "  (suspect)" or nil) end
    if suffix then
      -- (fitText says whether the text fit whole: no label text is read back and compared)
      if not fitText(r.name, row.short .. suffix, NAME_W - 16) then fitText(r.name, row.short, NAME_W - 16) end
    else fitText(r.name, row.short, NAME_W - 16) end
    for k, col in ipairs(cols) do
      local c = r.cells[k]
      if not c:IsShown() then c:Show() end
      fillCell(c, col.def, row, not C.Policy:CanSee(officer, row.me, col.def.id), col.w)
    end
  end)
  self.virtual = function() UI.rows:Show(UI.scroll.bar:GetValue() or 0, UI.scroll:View()) end
  local y = top + #rows * rowH
  self.labels:Reset()
  if hidden > 0 then
    local l = self.labels:Get()
    l:SetJustifyH("LEFT")
    l:SetPoint("TOPLEFT", 6, -y - 6)
    l:SetWidth(width - 12)
    color(l, MUTE)
    l:SetText(string.format("%d more column%s do not fit: widen the window or untick some in Settings, %s.", hidden, hidden == 1 and "" or "s", C.Modules.byId[page].title))
    y = y + 24
  end
  local reported = 0
  for _, r in ipairs(rows) do if r.addon then reported = reported + 1 end end
  if reported <= 1 then
    local l = self.labels:Get()
    l:SetJustifyH("LEFT")
    l:SetPoint("TOPLEFT", 6, -y - 6)
    l:SetWidth(width - 12)
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
    if self.kept then tip:AddLine("Only the officers see who leads: the officers keep it to themselves.", 0.85, 0.85, 0.85, true) end
  end)
  return c
end

function UI:DrawShame()
  local sf = self.scroll
  local officer = C.Roster:MeOfficer()
  local rows = C.Roster:Rows()
  local ticked = UI.Ticked("shame")
  self.header:Hide()
  self.rows:Clear()
  self.cards:Reset()
  self.labels:Reset()
  local perRow = math.max(1, math.floor((sf:Width() + 8) / 244))
  local i, y = 0, 0
  for _, def in ipairs(C.Stats.byCat.funny) do
    if ticked[def.id] then
      self.shownIds[def.id] = true
      local top = {}
      -- (a member the officers marked untrusted is in no ranking)
      for _, row in ipairs(rows) do
        local v = row.stats[def.id]
        if row.addon and not row.untrusted and type(v) == "number" and C.Policy:CanSee(officer, row.me, def.id) then top[#top + 1] = { short = row.short, v = v, me = row.me } end
      end
      table.sort(top, function(a, b) if a.v == b.v then return a.short < b.short end return a.v > b.v end)
      local card = self.cards:Get()
      -- (a stat the officers keep: a member sees their own value alone, so names no leader, themselves included)
      local kept = not officer and C.Policy:Route(def.id) == "self"
      card.def, card.top, card.kept = def, kept and {} or { top[1], top[2], top[3] }, kept
      card:SetPoint("TOPLEFT", (i % perRow) * 244, -math.floor(i / perRow) * 72)
      card.title:SetText(def.label)
      if kept then card.leader:SetText(hex(MUTE) .. "only the officers see who leads|r")
      elseif top[1] and top[1].v > 0 then
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
    l:SetJustifyH("LEFT")
    l:SetPoint("TOPLEFT", 6, -6)
    l:SetWidth(sf:Width() - 12)
    color(l, MUTE)
    l:SetText("No cards ticked. Settings, Hall of Shame has the list.")
    y = 30
  end
  self.labels:HideRest()
  sf:SetContentHeight(y + 8)
end

-- what is discovered, counted: the bosses (and the instances they are in), dungeons, raids and factions; the guild's
-- (every one defined here) or, with mine, the ones your own record has a value for
local function foundCounts(mine)
  local n, insts = { bosses = 0, dungeons = 0, raids = 0, rep = 0, instances = 0 }, {}
  for _, def in ipairs(C.Stats.byCat.found) do
    local v = C.Sample:Value(def.id)
    if n[def.learned] and (not mine or (type(v) == "number" and (v > 0 or def.learned == "rep"))) then
      n[def.learned] = n[def.learned] + 1
      local inst = def.learned == "bosses" and C.Stats.InstOf(def.num)
      if inst and not insts[inst] then insts[inst] = true; n.instances = n.instances + 1 end
    end
  end
  return n
end
local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end
local function foundLine(n)
  return string.format("%s in %s, %s, %s, %s", plural(n.bosses, "boss", "bosses"), plural(n.instances, "instance", "instances"),
    plural(n.dungeons, "dungeon", "dungeons"), plural(n.raids, "raid", "raids"), plural(n.rep, "faction", "factions"))
end
UI.FoundCounts = foundCounts

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
  -- the summary and the controls stay in the band above the table, so they and the column header stay in view
  local y = 4
  local function say(s, c)
    local l = self.bandLabels:Get()
    l:SetPoint("TOPLEFT", 6, -y)
    l:SetJustifyH("LEFT") -- (a pooled label may come from the Statistics page's right-aligned headings)
    l:SetWidth(sf:Width() - 12)
    color(l, c or INK)
    fitText(l, s, sf:Width() - 16)
    y = y + 18
  end
  say(string.format("%d members, %d with the addon, %d online. Median level %s, %d below it, %d not seen for a week.",
    total, withAddon, online, median and tostring(median) or "?", below, unseen))
  if #noAddon > 0 then
    -- the first dozen by name and how many more: a guild of hundreds would make one line of thousands of characters
    table.sort(noAddon)
    local first = {}
    for i = 1, math.min(12, #noAddon) do first[i] = noAddon[i] end
    say(string.format("Without the addon (%d): %s%s", #noAddon, table.concat(first, ", "), #noAddon > 12 and string.format(" and %d more", #noAddon - 12) or ""), DIM)
  end
  -- what the guild has learned in play: the slots it enchants (on how many members, any kind), what it has discovered
  local slots = {}
  for _, e in ipairs(C.Stats.EnchantSlots()) do slots[#slots + 1] = e[2] .. " " .. e[3] end
  say("Learned in play: " .. foundLine(foundCounts(false)) .. ". Enchants seen on " .. (#slots > 0 and table.concat(slots, ", ") or "no slot yet") .. ".", DIM)
  say(C.Policy:Describe(), DIM)
  -- trust: the member picked (a click on their row) and what is known of them, else who is suspect or untrusted. Mark
  -- untrusted is the officers' word, kept in the policy and sent with Broadcast like the rest of it
  local picked
  for _, r in ipairs(rows) do if self.picked and r.guid == self.picked and not r.me and r.addon then picked = r end end
  if not picked then self.picked = nil end
  if picked then
    local state = picked.untrusted and "untrusted, left out of what the guild learns and of the rankings"
      or (picked.suspect and ("suspect: " .. tostring(picked.suspect.why)) or "trusted")
    say(picked.short .. ": " .. state .. ".", picked.untrusted and WARN or (picked.suspect and BAD or INK))
  else
    local suspect, distrusted = {}, {}
    for _, r in ipairs(rows) do
      if not r.me and r.untrusted then distrusted[#distrusted + 1] = r.short
      elseif not r.me and r.suspect then suspect[#suspect + 1] = r.short end
    end
    if #suspect > 0 or #distrusted > 0 then
      local function few(list) table.sort(list); local s = table.concat(list, ", ", 1, math.min(5, #list)); return #list > 5 and (s .. " and " .. (#list - 5) .. " more") or s end
      local parts = {}
      if #suspect > 0 then parts[#parts + 1] = "Suspect: " .. few(suspect) .. "." end
      if #distrusted > 0 then parts[#parts + 1] = "Untrusted: " .. few(distrusted) .. "." end
      say(table.concat(parts, " ") .. " Click a row for why.", DIM)
    end
  end
  local labels = { { "Visibility settings", function() UI:Open("settings", "vis") end },
    { "Ask everyone to resend", function() C.Comm:Ask(); C.Print("asked the guild to send their records again.") end },
    { "Broadcast policy now", function() C.Comm:Broadcast() end },
    { picked and picked.untrusted and "Trust again" or "Mark untrusted", function()
      if not picked then return end
      C.Policy:SetUntrusted(picked.guid, not picked.untrusted)
      C.Comm:PolicySoon()
      C.Print((picked.untrusted and "trusted again: " or "marked untrusted: ") .. picked.short .. ". The guild hears it with the policy in a few seconds.")
      UI:Draw()
    end, picked ~= nil, function(tip)
      tip:AddLine(picked and picked.untrusted and "Trust again" or "Mark untrusted", 1, 1, 1)
      tip:AddLine("An untrusted member is left out of what the guild learns and of the rankings; their row says so to the officers. It travels with the policy.", 0.85, 0.85, 0.85, true)
      if not picked then tip:AddLine("Click a member's row first.", 0.6, 0.6, 0.6) end
    end } }
  local bx = 6
  for _, d in ipairs(labels) do
    local b = self.bandButtons:Get()
    b:SetPoint("TOPLEFT", bx, -y - 2)
    b:SetWidth(160)
    b:SetLabel(d[1])
    b:SetOn(d[3] ~= false)
    b:SetScript("OnClick", d[2])
    -- (a pooled band button may come from Settings' steps, with their tooltip)
    b:SetScript("OnEnter", nil); b:SetScript("OnLeave", nil)
    if d[4] then tooltip(b, d[4]) end
    bx = bx + 166
  end
  y = y + 30
  self:DrawTable("officers", y)
end

-- your whole record, two columns, every stat; the toggle greys what members cannot see
function UI:DrawMe()
  local sf = self.scroll
  self.header:Hide()
  self.rows:Clear()
  self.cards:Reset(); self.cards:HideRest()
  self.labels:Reset()
  self.checks:Reset()
  local me = C.Roster:MeRow()
  local w = sf:Width()
  local colW = math.floor((w - 12) / 2)
  local cb = self.checks:Get()
  cb:SetPoint("TOPLEFT", 6, -6)
  -- (an officer's change not saved routes on their client alone: the members go by Guild Info, so the box waits for
  -- the save rather than show a value their clients drop)
  local pending = C.Policy:EditPending()
  if pending then self.meView = false end
  cb.label:SetWidth(w - 40)
  cb.label:SetText(pending and "Show what members see of me: members go by Guild Info, save your change first" or "Show what members see of me")
  cb:Set(self.meView and true or false)
  cb:SetOn(not pending)
  cb.fn = function(self) UI.meView = self:GetChecked(); UI:Draw() end
  self.checks:HideRest()
  local y = 30
  for _, cat in ipairs(C.Stats.CATS) do
    -- (the game's statistics have a page of their own; one line below says how many)
    if cat ~= "game" then
      local l = self.labels:Get()
      l:SetPoint("TOPLEFT", 6, -y)
      l:SetWidth(w - 12)
      l:SetJustifyH("LEFT")
      color(l, WHITE)
      l:SetText(C.Stats.CAT_LABEL[cat])
      y = y + 20
      local n = 0
      for _, def in ipairs(C.Stats.byCat[cat]) do
        self.shownIds[def.id] = true
        local col = n % 2
        local ly = y + math.floor(n / 2) * 18
        local a = self.labels:Get()
        a:SetPoint("TOPLEFT", 6 + col * colW, -ly)
        a:SetWidth(colW - 130)
        a:SetJustifyH("LEFT")
        local hidden = self.meView and C.Policy:Route(def.id) == "self"
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
  end
  -- what you discovered and the game's statistics: counts, not every id (the Statistics page lists them)
  local f = self.labels:Get()
  f:SetPoint("TOPLEFT", 6, -y)
  f:SetWidth(w - 12)
  f:SetJustifyH("LEFT")
  color(f, DIM)
  fitText(f, "Discovered: " .. foundLine(foundCounts(true)) .. ", on the Statistics page.", w - 16)
  y = y + 18
  local g = self.labels:Get()
  g:SetPoint("TOPLEFT", 6, -y)
  g:SetWidth(w - 12)
  g:SetJustifyH("LEFT")
  color(g, DIM)
  local nGame = #C.Stats.byCat.game
  fitText(g, nGame > 0 and string.format("Statistics: %d, on the Statistics page.", nGame) or ("Statistics: none. " .. (C.Stats.gameNote or "")), w - 16)
  y = y + 26
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

-- a line of the Statistics page: a name on the left, a value and a "who" on the right, a class bar for a member;
-- callers set fn (the click) and tip (the tooltip) rather than the scripts
function UI:MakeLine(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(ROW)
  r.bg = flat(r, "BACKGROUND", WHITE, 0.03)
  r.bg:SetAllPoints()
  r.bar = flat(r, "ARTWORK", WHITE, 1)
  r.bar:SetPoint("TOPLEFT", 0, 0)
  r.bar:SetPoint("BOTTOMLEFT", 0, 0)
  r.bar:SetWidth(2)
  r:SetHighlightTexture(FLAT, "ADD")
  r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)
  r.name = text(r, 12, INK, "LEFT")
  r.name:SetPoint("LEFT", 8, 0)
  r.val = text(r, 12, INK, "RIGHT")
  r.val:SetPoint("RIGHT", -4, 0)
  r.who = text(r, 12, INK, "RIGHT")
  r.who:SetPoint("RIGHT", -4, 0)
  r:SetScript("OnClick", function(self) if self.fn then self.fn(self) end end)
  tooltip(r, function(tip, self) if self.tip then self.tip(tip, self) end end)
  return r
end

-- the Statistics page: what the guild discovered and the game's own statistics as a leaderboard, not a wide table. Left,
-- the categories (Bosses with a child per instance, Dungeons, Raids, Reputation, then the game's as it groups them; a
-- click opens one); right, the open category's stats as rows of name, your value and the guild's leader; a click on a
-- row ranks every member under it, a dash where the policy keeps a member's value from you. Where the client reports
-- no statistics a note under the categories says why; the empty state, where there is nothing at all, says so too.
-- Both columns are virtual lists: a ranking of a few hundred members draws the rows in view, and a scroll draws the
-- ones coming into view
function UI:DrawGame()
  local sf = self.scroll
  local S = C.Stats
  self.header:Hide()
  self.rows:Clear()
  self.labels:Reset()
  local w = sf:Width()
  local function say(x, y, width, s, c, justify)
    local l = self.labels:Get()
    l:SetPoint("TOPLEFT", x, -y)
    l:SetWidth(width)
    l:SetJustifyH(justify or "LEFT")
    color(l, c or INK)
    fitText(l, s, width - 4)
    return l
  end
  local board = S.Board()
  if #board.cats == 0 then
    self.catLines:Clear(); self.lines:Clear()
    if self.gameNoteLabel then self.gameNoteLabel:Hide() end
    say(6, 6, w - 12, "Nothing discovered yet. " .. (S.gameNote or "No statistics yet."), INK)
    say(6, 26, w - 12, "Bosses, dungeons, raids and reputations show here as the guild meets them; the counters stay on the other pages.", MUTE)
    self.labels:HideRest()
    sf:SetContentHeight(50)
    return
  end
  local officer = C.Roster:MeOfficer()
  local rows = rowsShown()
  local leftW = math.max(160, math.floor(w * 0.25))
  local rightX = leftW + 12
  local rightW = w - rightX
  -- the open category: the one clicked, else the first with stats in it
  local sel = self.gameCat
  if not (sel ~= nil and board.byCat[sel] and #board.byCat[sel] > 0) then
    sel = nil
    for _, cat in ipairs(board.cats) do if #cat.stats > 0 then sel = cat.id; break end end
    self.gameCat = sel
  end
  -- the headings stay in the band; the two lists scroll under them
  local function head(x, width, s, justify)
    local l = self.bandLabels:Get()
    l:SetPoint("TOPLEFT", x, -4)
    l:SetWidth(width)
    l:SetJustifyH(justify or "LEFT")
    color(l, DIM)
    fitText(l, s, width - 4)
  end
  self:SetBand(ROW + 2)
  -- left: the categories
  head(4, leftW - 8, "Category")
  local top = 0
  self.catLines:Set(#board.cats, top, ROW, function(r, i, y)
    local cat = board.cats[i]
    -- (a parent with children counts theirs and opens the first)
    local n = cat.count or #cat.stats
    local opens = #cat.stats > 0 and cat.id or cat.first
    local open = cat.id == sel
    r.cat, r.def, r.member = cat, nil, nil
    r:SetPoint("TOPLEFT", 0, -y)
    r:SetWidth(leftW)
    r:SetHeight(ROW)
    r.bg:SetColorTexture(1, 1, 1, open and 0.06 or (i % 2 == 0 and 0.03 or 0))
    r.bar:SetShown(open)
    r.bar:SetColorTexture(WHITE[1], WHITE[2], WHITE[3], 1)
    local indent = cat.parent ~= -1 and 14 or 0
    r.name:SetPoint("LEFT", 8 + indent, 0)
    r.name:SetWidth(leftW - 8 - indent - 40)
    color(r.name, open and WHITE or (n > 0 and INK or MUTE))
    fitText(r.name, cat.name, leftW - 12 - indent - 40)
    r.val:Show()
    r.val:SetPoint("RIGHT", -4, 0)
    r.val:SetWidth(34)
    color(r.val, MUTE)
    r.val:SetText(tostring(n))
    r.who:Hide()
    r.fn = function() if n > 0 and opens then UI.gameCat = opens; UI:Draw() end end
    r.tip = function(tip)
      tip:AddLine(cat.path, 1, 1, 1)
      if cat.learned then tip:AddLine("Discovered in play by the guild.", 0.7, 0.7, 0.7) end
      tip:AddLine(n == 1 and "1 entry" or (n .. " entries"), 0.7, 0.7, 0.7)
      if n > 0 then tip:AddLine("Click to open.", 0.45, 0.45, 0.45) end
    end
  end)
  local leftY = top + #board.cats * ROW
  -- a client without the game's statistics says so under the categories, wrapped to the column
  if S.gameNote and #S.byCat.game == 0 then
    if not self.gameNoteLabel then self.gameNoteLabel = text(sf.child, 11, MUTE, "LEFT") end
    local note = self.gameNoteLabel
    note:ClearAllPoints()
    note:SetPoint("TOPLEFT", 6, -(leftY + 8))
    note:SetWidth(leftW - 12)
    note:SetWordWrap(true)
    note:SetJustifyV("TOP")
    note:SetText("No game statistics here: " .. S.gameNote .. ".")
    note:Show()
    -- (as many lines as the text is wide, and one more for where the words break)
    local h = (math.ceil(((note.GetUnboundedStringWidth or note.GetStringWidth)(note) or 0) / math.max(1, leftW - 12)) + 1) * 13
    note:SetHeight(h)
    leftY = leftY + 8 + h
  elseif self.gameNoteLabel then self.gameNoteLabel:Hide() end
  -- right: the open category's stats, each followed by its ranking where it is open. The list is worked out here,
  -- once a draw; the scroll only places it
  local vw, ww = 90, math.min(190, math.floor(rightW * 0.36))
  local nw = rightW - vw - ww - 8
  head(rightX + 8, nw - 8, "Name")
  head(rightX + rightW - ww - vw - 4, vw, "You", "RIGHT")
  head(rightX + rightW - ww - 4, ww, "Leader", "RIGHT")
  local defs = (sel ~= nil and board.byCat[sel]) or {}
  local items = {}
  for i, def in ipairs(defs) do
    self.shownIds[def.id] = true
    -- every member's value as this viewer may see it; the leader among those (a member the officers marked untrusted
    -- is in no ranking)
    local ranked, best = {}, nil
    for _, row in ipairs(rows) do
      if row.addon and not row.untrusted then
        local hidden = not C.Policy:CanSee(officer, row.me, def.id)
        local v = row.stats[def.id]
        local e = { row = row, v = (not hidden and type(v) == "number") and v or nil, hidden = hidden, at = row.at and row.at[def.id] }
        ranked[#ranked + 1] = e
        if e.v and (not best or e.v > best.v or (e.v == best.v and row.sort < best.row.sort)) then best = e end
      end
    end
    local open = self.gameOpen[def.id] == true
    -- (a stat the officers keep: a member sees their own value alone, so names no leader, themselves included)
    local kept = not officer and C.Policy:Route(def.id) == "self"
    if kept then best = nil end
    items[#items + 1] = { def = def, i = i, best = best, open = open, kept = kept }
    if open then
      -- values first, highest on top; then the members whose value is kept from you; then the unreported
      table.sort(ranked, function(a, b)
        if (a.v ~= nil) ~= (b.v ~= nil) then return a.v ~= nil end
        if a.v ~= nil and a.v ~= b.v then return a.v > b.v end
        if a.hidden ~= b.hidden then return a.hidden end
        return a.row.sort < b.row.sort
      end)
      -- (no places where the officers keep it: a member's own value would stand first, alone, "1.")
      for k, e in ipairs(ranked) do items[#items + 1] = { def = def, member = e, k = not kept and k or nil } end
    end
  end
  -- a discovered value's tooltip: a boss's first kill (yours, kept here), a standing's reaction and number
  local function extra(tip, def, v, me)
    if def.learned == "bosses" and me then
      local first = (C.Char().firstKill or {})[def.num]
      if first and date then tip:AddLine("First kill " .. date("%Y-%m-%d", first), 0.7, 0.7, 0.7) end
    elseif def.learned == "rep" and type(v) == "number" then
      -- your own reaction as your list gives it; a member's from the standing ranges your list showed
      local mineNow = me and C.Stats.Factions()
      local r = (mineNow and mineNow[def.num] and mineNow[def.num].reaction) or C.Stats.Reaction(v)
      tip:AddLine((r and (C.Stats.ReactionName(r) .. ", ") or "") .. "standing " .. v, 0.7, 0.7, 0.7)
    end
  end
  self.lines:Set(#items, top, ROW, function(r, i, y)
    local it = items[i]
    local def = it.def
    r.cat, r.def = nil, def
    r:SetHeight(ROW)
    if not it.member then
      -- a stat: its name, your value, the leader
      local mine, best, open = C.Sample:Value(def.id), it.best, it.open
      r.member = nil
      r:SetPoint("TOPLEFT", rightX, -y)
      r:SetWidth(rightW)
      r.bg:SetColorTexture(1, 1, 1, open and 0.06 or (it.i % 2 == 0 and 0.03 or 0))
      r.bar:Hide()
      r.name:SetPoint("LEFT", 8, 0)
      r.name:SetWidth(nw - 8)
      color(r.name, open and WHITE or INK)
      fitText(r.name, def.label, nw - 12)
      r.val:Show()
      r.val:SetPoint("RIGHT", -(ww + 4), 0)
      r.val:SetWidth(vw)
      color(r.val, mine == nil and MUTE or INK)
      -- (a discovery you have not met is a dash, not a question)
      r.val:SetText((mine == nil and def.learned) and "-" or UI.Format(def, mine))
      r.who:Show()
      r.who:SetPoint("RIGHT", -4, 0)
      r.who:SetWidth(ww)
      if best then
        color(r.who, INK)
        r.who:SetText(hex(best.row.class and classColor(best.row.class) or INK) .. best.row.short .. "|r  " .. UI.Format(def, best.v))
      else
        color(r.who, MUTE)
        r.who:SetText("-")
      end
      local kept = it.kept
      r.fn = function() UI.gameOpen[def.id] = not UI.gameOpen[def.id]; UI:Draw() end
      r.tip = function(tip)
        tip:AddLine(def.label, 1, 1, 1)
        if def.hint then tip:AddLine(def.hint, 0.7, 0.7, 0.7, true) end
        if kept then tip:AddLine("Only the officers see who leads.", 0.85, 0.85, 0.85, true) end
        extra(tip, def, mine, true)
        tip:AddLine(UI.WhoSees(def.id), 0.6, 0.6, 0.6, true)
        if C.Sample:Error(def.id) then tip:AddLine("Could not read: " .. C.Sample:Error(def.id), 0.9, 0.4, 0.4, true) end
        tip:AddLine(open and "Click to fold." or "Click to rank every member.", 0.45, 0.45, 0.45)
      end
    else
      -- a member under an open stat: the place, the name, the value or a dash
      local e, k = it.member, it.k
      r.member = e
      r:SetPoint("TOPLEFT", rightX + 16, -y)
      r:SetWidth(rightW - 16)
      r.bg:SetColorTexture(1, 1, 1, 0.015)
      local cc = e.row.class and classColor(e.row.class) or MUTE
      if not e.row.online then cc = dimmed(cc) end
      local bc = e.row.me and WHITE or cc
      r.bar:Show()
      r.bar:SetColorTexture(bc[1], bc[2], bc[3], 1)
      r.name:SetPoint("LEFT", 8, 0)
      r.name:SetWidth(nw - 24)
      color(r.name, cc)
      fitText(r.name, ((e.v and k) and (k .. ".  ") or "") .. e.row.short .. (e.row.me and "  (you)" or ""), nw - 28)
      r.val:Hide()
      r.who:Show()
      r.who:SetPoint("RIGHT", -4, 0)
      r.who:SetWidth(ww + vw)
      if e.hidden then color(r.who, MUTE); r.who:SetText("-")
      elseif e.v == nil then color(r.who, MUTE); r.who:SetText(def.learned and "-" or "?")
      else color(r.who, INK); r.who:SetText(UI.Format(def, e.v)) end
      r.fn = nil
      r.tip = function(tip)
        tip:AddLine(e.row.short, 1, 1, 1)
        if e.hidden then tip:AddLine("Only " .. e.row.short .. " and the officers see this.", 0.6, 0.6, 0.6, true)
        elseif e.v == nil then tip:AddLine(def.learned and "Not met yet." or "Not reported yet.", 0.6, 0.6, 0.6)
        else tip:AddLine(UI.Format(def, e.v), 0.9, 0.9, 0.9); extra(tip, def, e.v, e.row.me) end
        if e.at then tip:AddLine("Reported " .. (ago(e.at) or ""), 0.45, 0.45, 0.45) end
      end
    end
  end)
  self.virtual = function()
    local off, view = UI.scroll.bar:GetValue() or 0, UI.scroll:View()
    UI.catLines:Show(off, view)
    UI.lines:Show(off, view)
  end
  local y = top + #items * ROW
  if #defs == 0 then say(rightX + 8, y, rightW - 16, "Nothing in this category.", MUTE); y = y + 20 end
  self.labels:HideRest()
  sf:SetContentHeight(math.max(leftY, y) + 8)
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
  self.drawnAt = clock()
  self.draws = (self.draws or 0) + 1
  -- the page says which stats it shows (a change to another draws nothing) and, for a virtual list, how to scroll
  self.shownIds, self.virtual = {}, nil
  local page = self.page
  local officer = C.Roster:MeOfficer()
  -- a page whose module went off (or an officer's, for a member) gives way to Race
  local mod = page ~= "settings" and C.Modules.Page(page, officer) or nil
  if page ~= "settings" and not mod then page = "race"; self.page = page; mod = C.Modules.Page(page, officer) end
  self:DrawTabs(page, officer)
  -- the scroll place survives a redraw; a page change starts at the top
  local bar = self.scroll.bar
  local keep = self.scrollTo or bar:GetValue() or 0
  self.scrollTo = nil
  self.header:ClearAllPoints()
  self.header:SetPoint("TOPLEFT")
  self.header:Hide()
  self:SetBand(0)
  self.bandLabels:Reset(); self.bandButtons:Reset(); self.bandLines:Reset()
  self.cards:Reset(); self.cards:HideRest()
  self.buttons:Reset(); self.buttons:HideRest()
  self.checks:Reset(); self.checks:HideRest()
  self.labels:Reset()
  if page ~= "game" and self.gameNoteLabel then self.gameNoteLabel:Hide() end
  if page ~= "settings" and C.Settings_Hide then C.Settings_Hide(self) end
  -- the virtual lists a page does not fill are cleared after it, so a page change hides the last page's rows
  local rowsGen, linesGen, catGen = self.rows.gen, self.lines.gen, self.catLines.gen
  local gens = {}
  for key, v in pairs(self.lists) do gens[key] = v.gen end
  if page == "settings" then C.Settings_Draw(self)
  else C.Safe(function() mod.page(self, self.scroll) end, "page: " .. page)() end
  if self.rows.gen == rowsGen then self.rows:Clear() end
  if self.lines.gen == linesGen then self.lines:Clear() end
  if self.catLines.gen == catGen then self.catLines:Clear() end
  for key, v in pairs(self.lists) do if v.gen == gens[key] then v:Clear() end end
  self.labels:HideRest()
  self.bandLabels:HideRest(); self.bandButtons:HideRest(); self.bandLines:HideRest()
  local _, maxv = bar:GetMinMaxValues()
  bar:SetValue(math.max(0, math.min(keep, maxv or 0)))
  -- the rows in view, at the place kept (the scroll's own redraw waits while drawing)
  if self.virtual then self.virtual() end
  self:DrawStatus(officer)
  self:DrawFooter()
  self.drawing = false
end
-- the status line: who is online with the addon, your view, and "update available" while a guild mate runs a newer
-- Cute than yours (Core.lua C.SawVersion, which draws it again when one arrives)
function UI:DrawStatus(officer)
  if not self.status then return end
  if officer == nil then officer = C.Roster:MeOfficer() end
  local online = 0
  for _, r in ipairs(C.Roster:Rows()) do if r.online and r.addon then online = online + 1 end end
  local s = string.format("%d online with the addon  |  %s view", online, officer and "officer" or "member")
  if C.newer then s = s .. "  |  " .. C.COLOR .. "update available|r" end
  self.status:SetText(s)
end

----------------------------------------------------------------------------
-- the minimap button: the round one every addon has (LibDBIcon's, QuestBank's), 32 px: the emblem cut round by the
-- portrait mask on the minimap's dark disc, under the tracking ring, dragged around the minimap's edge. (The window
-- stays flat; this sits among the game's own round buttons)
----------------------------------------------------------------------------
local RING = "Interface\\Minimap\\MiniMap-TrackingBorder"
local DISC = "Interface\\Minimap\\UI-Minimap-Background"
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GLOW = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
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
  -- the ring's art sits in the top left of its texture, so it is drawn from the corner at 54 px and the disc and the
  -- emblem centre on its hole
  local disc = tex(b, "BACKGROUND", DISC, 20, 20)
  disc:SetPoint("TOPLEFT", 7, -5)
  local icon = tex(b, "ARTWORK", LOGO, 20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  if b.CreateMaskTexture and icon.AddMaskTexture then
    local mask = b:CreateMaskTexture()
    mask:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    pcall(icon.AddMaskTexture, icon, mask)
    b.mask = mask
  else
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
  local ring = tex(b, "OVERLAY", RING, 54, 54)
  ring:SetPoint("TOPLEFT")
  b.icon, b.ring = icon, ring
  b:SetHighlightTexture(GLOW, "ADD")
  local function place()
    local angle = math.rad(C.Settings().minimapPos or 220)
    local r = (Minimap:GetWidth() or 140) / 2 + 10
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

----------------------------------------------------------------------------
-- the dashboard: the core's pages, registered like any module (Modules.lua) and always on. A page with columns or
-- cards brings its own Settings section, the checklist of them
----------------------------------------------------------------------------
local function columns(page, head)
  return function(_, col)
    col:Head(head)
    local ticked = UI.Ticked(page)
    for _, def in ipairs(UI.Candidates(page)) do
      col:Check(def.label, ticked[def.id], true, function(on) UI.SetTicked(page, def.id, on) end)
    end
  end
end
C:RegisterModule({ id = "race", title = "Race", order = 10, core = true, tab = 64, page = function(ui) ui:DrawTable("race") end, settings = columns("race", "Columns") })
C:RegisterModule({ id = "prog", title = "Prog", order = 30, core = true, tab = 64, page = function(ui) ui:DrawTable("prog") end, settings = columns("prog", "Columns") })
C:RegisterModule({ id = "shame", title = "Hall of Shame", order = 40, core = true, tab = 110, page = function(ui) ui:DrawShame() end, settings = columns("shame", "Cards") })
C:RegisterModule({ id = "game", title = "Statistics", order = 50, core = true, tab = 80, page = function(ui) ui:DrawGame() end })
C:RegisterModule({ id = "officers", title = "Officers", order = 60, core = true, officer = true, tab = 80, page = function(ui) ui:DrawOfficers() end, settings = columns("officers", "Columns") })
C:RegisterModule({ id = "me", title = "Me", order = 70, core = true, tab = 48, page = function(ui) ui:DrawMe() end })
