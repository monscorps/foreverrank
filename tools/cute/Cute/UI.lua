-- SPDX-License-Identifier: GPL-3.0-or-later
-- The windows: Guild (J, CuteFrame, this file's own pages), Quests (L, CuteQuestFrame, the pages of a module addon that
-- says window = "quests") and Settings (CuteSettingsFrame, Settings.lua), all made by one builder (UI.BuildWindow): a
-- 30 px header (the round logo, the title, the button to the game's own window, the cog, the close; it drags the window),
-- a row of tabs under it where the window has pages, the content panel with its band, scroll area and footer, and the
-- game's size grabber in the bottom-right corner. Drawn flat and dark the way ElvUI and Shadowed Unit Frames draw
-- theirs: one-pixel black borders, near-black panels, white and grey text in the client's narrow font, class colours on
-- names and nothing else coloured unless it means something (green ready, red low). Numbers sit on the right of their
-- columns, text on the left; a two-pixel class-coloured bar marks every member's row, yours by its lighter background.
-- A window's tabs are the modules that are on and say that window (Modules.lua), in their order; the guild's pages,
-- drawn here, are the core's and always on:
--   Race           every member as a row: level, XP, zone, pace, the leveling stats
--   Prog           readiness, item level, empty slots, the enchants you lack, consumables, what
--                  you have met in play, the gaps only you see
--   Hall of Shame  a card per funny stat with its leader
--   Statistics     what the guild discovered in play (bosses by instance, dungeons, raids, reputations) and the
--                  game's own statistics as a leaderboard: categories left, you and the leader right, a click ranks
--                  every member (an empty state where there is neither)
--   Officers       summaries, what the guild has learned, the officers' stats, the controls (officer ranks only)
--   Me             your whole record, with what members see
-- A module's page draws with the same pieces into its window's scroll area. The guild window is this table itself
-- (C.UI): the other windows are tables that read its methods and keep their own state (UI.Window).
-- Columns and cards come from the registry (Stats.lua); the policy (Policy.lua) decides which cells a member sees.
-- Built on first open; nothing updates while it is hidden. A guild of a few hundred stays light: the tables and the
-- Statistics ranking draw only the rows in view (a virtual list, filled as you scroll, the sorted list kept between
-- scrolls), a redraw comes at most once a second and only for a value the open page shows, and a label's cut is
-- measured once per text and width.
local _, C = ...
local UI = { page = "race", sort = {}, gameOpen = {}, key = "guild", home = "race" }
C.UI = UI

local W, H = 1040, 640
local MIN_W, MIN_H = 760, 420
local HEAD = 30          -- the header: logo, title, the game's window, cog, close
local TABS = 26          -- the tab row
local ROW = 20           -- a member row (compact: 17)
local ROW_COMPACT = 17
local FOOT = 24          -- the footer inside the content panel, under its hairline
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
  -- (an error in a click's path is recorded, never left with the window half drawn: Core.lua C.Safe)
  cb:SetScript("OnClick", C.Safe(function(self, ...)
    self.fill:SetShown(self:GetChecked())
    if self.fn then self.fn(self, ...) end
  end, "check"))
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
  r:SetScript("OnClick", C.Safe(function(self, ...)
    self:Set(not self.on)
    if self.fn then self.fn(self, ...) end
  end, "check"))
  function r:Set(on) self.on = on and true or false; self.fill:SetShown(self.on) end
  function r:GetChecked() return self.on == true end
  function r:SetOn(on) self:SetEnabled(on); color(self.label, on and INK or MUTE); self.fill:SetVertexColor(1, 1, 1, on and 1 or 0.4) end
  return r
end
UI.Check, UI.CheckRow, UI.Button, UI.Text, UI.Skin, UI.Flat = check, checkRow, button, text, skin, flat
-- (for Guide.lua, which draws its page with the window's own pieces)
-- (the windows round, Look.lua) the categories' colours, for the 2 px bars and progress bars only, never text: QUEST the
-- game's quest gold, GROUP a teal no game colour set uses, NEW for what was seen in play and QuestBank's data lacks; EDGE
-- for boxes and the route's rail
UI.COLORS = { WHITE = WHITE, INK = INK, DIM = DIM, MUTE = MUTE, GOOD = GOOD, WARN = WARN, BAD = BAD, LINE = LINE, PANEL2 = PANEL2,
  EDGE = { 0.42, 0.42, 0.42 }, NEW = { 0.47, 0.69, 1 }, QUEST = { 1, 0.82, 0 }, GROUP = { 0.31, 0.82, 0.77 } }
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
-- A label that was cut says so (fs.cuteCut): Settings and the setup card never cut, and the harness fails one shown there
local fitCache, fitCount = {}, 0
local function fitText(fs, s, room)
  room = math.floor(room or ((fs:GetWidth() or 0) - 4))
  s = s == nil and "" or tostring(s)
  fs.cuteCut = nil
  if s == "" then fs:SetText(s); return true end
  local key = (fs.cuteSize or 12) .. ":" .. room
  local byText = fitCache[key]
  if not byText then
    if fitCount > 4000 then fitCache, fitCount = {}, 0 end
    byText = {}
    fitCache[key] = byText
  end
  local done = byText[s]
  if done then fs:SetText(done); fs.cuteCut = done ~= s or nil; return done == s end
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
  fs.cuteCut = result ~= s or nil
  return result == s
end
UI.FitText = fitText

local pool
function pool(parent, make)
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

UI.Pool = function(parent, make) return pool(parent, make) end

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

-- ScrollFrame with a child and a thin flat bar, above the footer (bottom: the room the footer takes, 0 for a window
-- without one); win is the window it scrolls, whose virtual lists a scroll fills
local function scrollArea(parent, win, bottom)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  sf:SetPoint("TOPLEFT", 8, -8)
  sf:SetPoint("BOTTOMRIGHT", -18, bottom + 6)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(100, 10)
  sf:SetScrollChild(child)
  local bar = CreateFrame("Slider", nil, parent)
  bar:SetOrientation("VERTICAL")
  bar:SetPoint("TOPRIGHT", -7, -8)
  bar:SetPoint("BOTTOMRIGHT", -7, bottom + 6)
  bar:SetWidth(6)
  local track = flat(bar, "BACKGROUND", PANEL2, 1)
  track:SetAllPoints()
  local knob = flat(bar, "OVERLAY", DIM, 1)
  knob:SetSize(6, 40)
  bar:SetThumbTexture(knob)
  bar:SetMinMaxValues(0, 0)
  bar:SetValueStep(1)
  bar:SetValue(0)
  -- a scroll draws the rows that come into view and nothing else (UI:OnScroll); an error in a page's fill is recorded,
  -- never raised every scroll tick
  bar:SetScript("OnValueChanged", C.Safe(function(_, v) sf:SetVerticalScroll(v); win:OnScroll() end, "scroll"))
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", C.Safe(function(_, delta)
    local lo, hi = bar:GetMinMaxValues()
    bar:SetValue(math.max(lo, math.min(hi, bar:GetValue() - delta * 44)))
  end, "scroll: wheel"))
  sf:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then child:SetWidth(w) end end)
  sf.child, sf.bar = child, bar
  -- the height in view
  function sf:View()
    local view = self:GetHeight() or 0
    if view < 50 then view = (win.frame:GetHeight() or H) - HEAD - (win.tabRow and (TABS + 4) or 0) - bottom - 32 end
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
    if w < 100 then w = (win.frame:GetWidth() or W) - 2 - 8 - 18 - (win.insetX or 0) - (win.sideW and (win.sideW + 12) or 0) - (win.leftW and (win.leftW + 12) or 0) end
    return w
  end
  return sf
end
UI.ScrollArea = scrollArea

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
  if def.id == "xp" then return 84 end -- (the track and the percent)
  if def.kind == "text" then return 110 end
  if def.kind == "list" then return 62 end
  if def.kind == "pips" then return math.max(36, 8 + 7 * (def.pips or 8)) end
  if def.fmt == C.Stats.FmtHours then return 70 end
  return math.max(56, 12 + #shortLabel(def) * 7)
end
-- numbers on the right of their column, text (and pips, drawn from the left) on the left
-- (the XP column's track and percent start at its left: the windows round)
local function alignOf(def) return (def.kind == "text" or def.kind == "pips" or def.id == "xp") and "LEFT" or "RIGHT" end

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
-- the windows: one builder
----------------------------------------------------------------------------
-- the windows Cute has, by key: their frame's global name, title, default and smallest size, whether they have tabs
-- (pages of modules that say window = key) and a footer, the page they open on, and what the cog opens in Settings.
-- J and L are 1040 x 640 down to 760 x 420; Settings 800 x 560 down to 760 x 420
local SPEC = {
  guild = { name = "CuteFrame", title = "Guild", w = W, h = H, minW = MIN_W, minH = MIN_H, tabs = true, foot = true, home = "race", cog = "general" },
  quests = { name = "CuteQuestFrame", title = "Quests", w = W, h = H, minW = MIN_W, minH = MIN_H, tabs = true, foot = false, home = "quests", cog = "quests" },
  settings = { name = "CuteSettingsFrame", title = "Settings", w = 800, h = 560, minW = 760, minH = 420, tabs = false, foot = false, home = "general" },
}
UI.SPEC = SPEC
UI.windows = { guild = UI }
-- a window by key, made (not built) the first time it is asked for: the guild window is UI itself, the others read its
-- methods and the few constants a page reads (ui.COLORS, ui.ROW, ui.FONT) and keep their own state: nothing of the
-- guild window's own (its frame, page, scroll and lists) shows through
local STATICS = { COLORS = true, ROW = true, FONT = true, SHORT = true, SPEC = true, windows = true, Look = true }
local winMeta = { __index = function(_, k)
  local v = UI[k]
  if type(v) == "function" or STATICS[k] then return v end
  return nil
end }
function UI.Window(key)
  local win = UI.windows[key]
  if win then return win end
  local spec = SPEC[key]
  if not spec then return nil end
  win = setmetatable({ key = key, home = spec.home, page = spec.home, lists = {}, hosts = {}, kits = {} }, winMeta)
  UI.windows[key] = win
  return win
end
-- the window a page draws in: its module's (window = "quests"), the guild's otherwise
function UI.WindowOf(page)
  local def = C.Modules.byId[page]
  return UI.Window(def and def.window or "guild")
end

-- the tabs: one per module whose page shows in this window (Modules.lua). A module's tab is as wide as it says, or fits
-- its title
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
  b:SetScript("OnClick", C.Safe(function() UI:Open(m.id) end, "tab"))
  self.tabs[m.id] = b
  return b
end
function UI:DrawTabs(page, officer)
  local x = 0
  local list = C.Modules.Pages(officer, self.key)
  for _, b in pairs(self.tabs) do b.keep = false end
  -- more tabs than the row holds (every module on, the window narrow): each narrower by the same share, its title cut
  -- after a word where it must be, so the row never runs past the window
  local total = 0
  for _, m in ipairs(list) do total = total + self:Tab(m).w + 2 end
  local room = (self.frame:GetWidth() or W) - 16
  local share = total > room and room / total or 1
  for _, m in ipairs(list) do
    local b = self:Tab(m)
    b.keep = true
    if not b:IsShown() then b:Show() end
    b:SetPoint("LEFT", x, 0)
    local bw = share < 1 and math.floor(b.w * share) or b.w
    b:SetWidth(bw)
    UI.FitText(b.label, m.title, bw - 8)
    x = x + bw + 2
    color(b.label, m.id == page and WHITE or DIM)
    b.under:SetShown(m.id == page)
  end
  for _, b in pairs(self.tabs) do if not b.keep and b:IsShown() then b:Hide() end end
end

-- an atlas where the client has it, else the file (QuestBank's QB.Art pattern), so a missing atlas still draws
local function art(t, atlas, file)
  local info = atlas and type(C_Texture) == "table" and type(C_Texture.GetAtlasInfo) == "function" and C.Get(C_Texture.GetAtlasInfo, atlas)
  if type(info) == "table" and t.SetAtlas then t:SetAtlas(atlas) else t:SetTexture(file) end
end
UI.Art = art
-- the header's small square buttons: the cog and the close, 20 px, the game's art in a flat box
local function headButton(parent, w)
  local b = CreateFrame("Button", nil, parent, BD)
  b:SetSize(w or 20, 20)
  skin(b, PANEL2)
  b:SetHighlightTexture(FLAT, "ADD")
  b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
  return b
end

-- the builder: the frame, its header, tabs, content panel (band, scroll area, pools, footer) and the size grabber
function UI.BuildWindow(win, key)
  if win.frame then return end
  local spec = SPEC[key]
  win.key, win.spec = key, spec
  win.home = win.home or spec.home
  local f = CreateFrame("Frame", spec.name, UIParent, BD)
  win.frame = f
  f:SetSize(spec.w, spec.h)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  if f.SetResizable then f:SetResizable(true) end
  if f.SetResizeBounds then f:SetResizeBounds(spec.minW, spec.minH) end
  -- opaque: a frame under the window never shows through its edge
  skin(f, BG, 1)
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
  -- (a plain frame, never a UI panel: it opens and closes in a fight; Esc closes it)
  tinsert(UISpecialFrames, spec.name)
  f:SetScript("OnShow", C.Safe(function() win:Draw() end, "window: show"))
  f:SetScript("OnHide", C.Safe(function() if win.OnClose then win:OnClose() end end, "window: hide"))
  -- a resize redraws once the grip has rested for a tenth of a second, not on every pixel
  f:SetScript("OnSizeChanged", function()
    if win.resizing then return end
    win.resizing = true
    C_Timer.After(0.1, C.Safe(function() win.resizing = false; if win.frame:IsShown() then win:Draw() end end, "resize"))
  end)

  -- the header, 30 px: it drags the window (always: a window has no lock). The round logo and the title on the left;
  -- the cog and the close on the right, and left of them the button to the game's own window where it has one
  local head = CreateFrame("Frame", nil, f)
  head:SetPoint("TOPLEFT", 1, -1)
  head:SetPoint("TOPRIGHT", -1, -1)
  head:SetHeight(HEAD)
  head:EnableMouse(true)
  head:RegisterForDrag("LeftButton")
  head:SetScript("OnDragStart", function() f:StartMoving() end)
  head:SetScript("OnDragStop", C.Safe(function() f:StopMovingOrSizing(); win:SavePos() end, "window: drag"))
  win.head = head
  local logo = tex(head, "ARTWORK", LOGO, 24, 24)
  logo:SetPoint("LEFT", 5, 0)
  if head.CreateMaskTexture and logo.AddMaskTexture then
    local mask = head:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(logo)
    pcall(logo.AddMaskTexture, logo, mask)
  end
  win.title = text(head, 15, WHITE, "LEFT")
  win.title:SetPoint("LEFT", 37, 0)
  win.title:SetText(spec.title)
  local headLine = line(head)
  headLine:SetPoint("BOTTOMLEFT")
  headLine:SetPoint("BOTTOMRIGHT")
  -- the close: the game's minimise art, grey (UI-Panel-MinimizeButton-Up, 130832)
  local close = headButton(f)
  close:SetPoint("TOPRIGHT", -6, -6)
  close.t = tex(close, "ARTWORK", "Interface\\Buttons\\UI-Panel-MinimizeButton-Up", 16, 16)
  close.t:SetPoint("CENTER")
  close.t:SetTexCoord(0.2, 0.8, 0.2, 0.8)
  close.t:SetDesaturated(true)
  close:SetScript("OnClick", C.Safe(function() f:Hide() end, "window: close"))
  tooltip(close, function(tip) tip:AddLine("Close", 1, 1, 1) end)
  win.close = close
  local right = 6 + 20 + 4
  if spec.cog then
    -- the cog: Settings, at this window's first section (the questlog-icon-setting atlas, SharedUIPanelTemplates.xml:2316;
    -- its file UI-OptionsButton, 851903)
    local cog = headButton(f)
    cog:SetPoint("TOPRIGHT", -right, -6)
    cog.t = cog:CreateTexture(nil, "ARTWORK")
    cog.t:SetSize(14, 14)
    cog.t:SetPoint("CENTER")
    art(cog.t, "questlog-icon-setting", "Interface\\Buttons\\UI-OptionsButton")
    cog:SetScript("OnClick", C.Safe(function() UI.OpenSettings(spec.cog, win) end, "window: cog"))
    tooltip(cog, function(tip) tip:AddLine("Settings", 1, 1, 1) end)
    win.cog = cog
    right = right + 24
  end
  -- (the game's window button: UI.lua's GameButton, the secure click on the game's micro button, sits here)
  win.headRight = right

  -- tabs: flat, the open one white with a line under it; a hairline under the row
  local top = head
  if spec.tabs then
    local tabs = CreateFrame("Frame", nil, f)
    tabs:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 7, -3)
    tabs:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", -7, -3)
    tabs:SetHeight(TABS)
    win.tabRow, win.tabs = tabs, {}
    -- a tab for every module there is, shown or not (one that registers later gets its own as it first shows)
    for _, m in ipairs(C.Modules.list) do if m.page and (m.window or "guild") == key then win:Tab(m) end end
    local tabLine = line(f)
    tabLine:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -1)
    tabLine:SetPoint("TOPRIGHT", tabs, "BOTTOMRIGHT", 0, -1)
    top = tabs
  end

  -- the content panel, with the footer along its bottom edge under a hairline
  local content = CreateFrame("Frame", nil, f, BD)
  if spec.tabs then content:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -4) else content:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 7, -3) end
  content:SetPoint("BOTTOMRIGHT", -9, 9)
  skin(content, PANEL, 1)
  win.content = content
  local foot = spec.foot and FOOT or 0
  win.foot = foot
  win.scroll = scrollArea(content, win, foot)
  if spec.foot then
    local footLine = line(content)
    footLine:SetPoint("BOTTOMLEFT", 1, FOOT)
    footLine:SetPoint("BOTTOMRIGHT", -1, FOOT)
    win.footer = text(content, 11, MUTE, "LEFT")
    win.footer:SetPoint("BOTTOMLEFT", 10, 6)
    win.footer:SetHeight(12)
    -- the status on the right of the footer: who is online with Cute, and which Cute this is
    win.status = text(content, 11, MUTE, "RIGHT")
    win.status:SetPoint("BOTTOMRIGHT", -10, 6)
    win.status:SetHeight(12)
  end
  local child = win.scroll.child
  -- the members' rows and the Statistics page's two columns are virtual lists: widgets for what is in view only
  win.rows = virtual(child, function(parent) return UI:MakeRow(parent) end)
  win.cards = pool(child, function(parent) return UI:MakeCard(parent) end)
  win.labels = pool(child, function(parent) return text(parent, 12, INK) end)
  win.buttons = pool(child, function(parent) return button(parent, "", 160) end)
  win.checks = pool(child, function(parent) return check(parent) end)
  win.lines = virtual(child, function(parent) return UI:MakeLine(parent) end)
  -- the Statistics page's categories: a column of their own left of the list, with their own scroll bar, so a long
  -- ranking never scrolls them away (shown by that page alone)
  local catBox = CreateFrame("Frame", nil, content)
  catBox:SetPoint("TOPLEFT", 8, -8)
  catBox:SetPoint("BOTTOMLEFT", 8, foot + 6)
  catBox:SetWidth(200)
  catBox:Hide()
  catBox.head = text(catBox, 11, DIM, "LEFT")
  catBox.head:SetPoint("TOPLEFT", 4, -4)
  catBox.head:SetText("Category")
  win.catBox = catBox
  win.catScroll = scrollArea(catBox, win, 0)
  win.catScroll:ClearAllPoints(); win.catScroll:SetPoint("TOPLEFT", 0, -(ROW + 2)); win.catScroll:SetPoint("BOTTOMRIGHT", -10, 0)
  win.catScroll.bar:ClearAllPoints(); win.catScroll.bar:SetPoint("TOPRIGHT", 0, -(ROW + 2)); win.catScroll.bar:SetPoint("BOTTOMRIGHT", 0, 0)
  win.catLines = virtual(win.catScroll.child, function(parent) return UI:MakeLine(parent) end)
  -- the band: a strip above the scroll area for what stays in view while the rows scroll (a table's column header,
  -- the officers' summary, the Statistics page's headings); UI:SetBand gives it its height and moves the scroll area
  win.band = CreateFrame("Frame", nil, content)
  win.band:SetPoint("TOPLEFT", 8, -8)
  win.band:SetPoint("TOPRIGHT", -18, -8)
  win.band:SetHeight(1)
  win.band:Hide()
  win.bandLabels = pool(win.band, function(parent) return text(parent, 12, INK) end)
  win.bandButtons = pool(win.band, function(parent) return button(parent, "", 160) end)
  -- (a line in the band with a tooltip and a click: the Quests tab's step and where the pick's knowledge comes from)
  win.bandLines = pool(win.band, function(parent) return UI:MakeLine(parent) end)
  win.header = CreateFrame("Frame", nil, win.band)
  win.header:SetPoint("TOPLEFT")
  win.header:SetHeight(ROW)
  win.headerLine = line(win.header)
  win.headerLine:SetPoint("BOTTOMLEFT")
  win.headerLine:SetPoint("BOTTOMRIGHT")
  win.headerCells = pool(win.header, function(parent) return UI:MakeHeaderCell(parent) end)
  -- the size grabber: the game's own (UI-ChatIM-SizeGrabber, 386862-386864), in the window's corner
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -1, 1)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip.cuteEdge = true -- (it belongs in the corner: the harness's edge rule leaves it there)
  grip:SetScript("OnMouseDown", C.Safe(function() if f.StartSizing then f:StartSizing("BOTTOMRIGHT") end end, "window: size"))
  grip:SetScript("OnMouseUp", C.Safe(function() f:StopMovingOrSizing(); win:SavePos() end, "window: size"))
  tooltip(grip, function(tip) tip:AddLine("Drag to resize", 1, 1, 1) end)
  win.grip = grip
  win:RestorePos()
  if win.OnBuilt then win:OnBuilt() end
end
function UI:Build()
  if self.frame then return end
  -- (the guild window's header clicks are remembered across sessions)
  if self == UI then self.sort = C.Settings().sort end
  UI.BuildWindow(self, self.key or "guild")
  if self ~= UI then return end
  -- the footer's "2 min ago" keeps up while the window is open
  local f = self.frame
  local function footTick()
    C_Timer.After(30, C.Safe(footTick, "footer"))
    if f:IsShown() then UI:DrawFooter() end
  end
  C_Timer.After(30, C.Safe(footTick, "footer"))
end

-- where a window was left, and its size: the guild window's in CuteDB.pos (as since 0.1), the others' by key
local function posOf(win, set)
  if win == UI then if set ~= nil then CuteDB.pos = set end return CuteDB.pos end
  if type(CuteDB.winPos) ~= "table" then CuteDB.winPos = {} end
  if set ~= nil then CuteDB.winPos[win.key] = set end
  return CuteDB.winPos[win.key]
end
function UI:SavePos()
  local f = self.frame
  posOf(self, { w = f:GetWidth(), h = f:GetHeight(), left = f:GetLeft(), top = f:GetTop() })
end
-- the saved place, kept on screen: another resolution or UI scale may have saved it beyond this screen's edge
function UI:RestorePos()
  local p = posOf(self)
  if type(p) ~= "table" then return end
  local f, spec = self.frame, SPEC[self.key] or SPEC.guild
  if type(p.w) == "number" and type(p.h) == "number" then f:SetSize(math.max(spec.minW, p.w), math.max(spec.minH, p.h)) end
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

-- the guild window (J) shown or hidden; UI.ToggleWindow for any window by key
function UI:Toggle() UI.ToggleWindow("guild") end
function UI.ToggleWindow(key)
  local win = UI.Window(key)
  if not win then return end
  if key ~= "guild" and key ~= "settings" and not C.Modules.Page(win.home, C.Roster:MeOfficer()) then return end
  win:Build()
  if win.frame:IsShown() then win.frame:Hide() else win:Open(win.page or win.home) end
end
-- Settings at a section (general, keys, modules, columns, vis, rules, or a module's): its own window
-- Opened by a window's cog (from): beside that window, on its right where the screen has room, else on its left, until
-- Settings is moved (it keeps its own place then: posOf); no room either side, centred
function UI.OpenSettings(section, from)
  local win = UI.Window("settings")
  win:Build()
  if section and section ~= win.section then win.section = section; win.scrollTo = 0 end
  if from and from ~= win and rawget(from, "frame") and from.frame:IsShown() and not win.frame:IsShown() and posOf(win) == nil then
    local f, o = win.frame, from.frame
    local l, t, w, sw, uw = o:GetLeft(), o:GetTop(), o:GetWidth(), f:GetWidth(), UIParent:GetWidth()
    f:ClearAllPoints()
    if l and t and w and sw and uw and l + w + 8 + sw <= uw then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l + w + 8, t)
    elseif l and t and sw and l - 8 - sw >= 0 then f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l - 8 - sw, t)
    else f:SetPoint("CENTER") end
  elseif not win.frame:IsShown() and posOf(win) ~= nil then
    win:RestorePos()
  end
  if not win.frame:IsShown() then win.frame:Show() else win:Draw() end
end
-- a page by its module's id, in the window that page is in, or "settings" (at a section). A page whose module is off, or
-- an officer's for a member, opens its window's first page (Race; Quests)
function UI:Open(page, section)
  if page == "settings" then return UI.OpenSettings(section) end
  local win = page and UI.WindowOf(page) or self
  win:Build()
  page = page or win.page
  local officer = C.Roster:MeOfficer()
  if not C.Modules.Page(page, officer) or (C.Modules.byId[page].window or "guild") ~= win.key then page = win.home end
  if not C.Modules.Page(page, officer) and win ~= UI then return end
  if page ~= win.page then win.scrollTo = 0 end -- a new page starts at the top; a redraw keeps the place
  win.page = page
  if not win.frame:IsShown() then win.frame:Show() else win:Draw() end
end
-- a redraw, at most one a second while the window shows and none while it is hidden (it draws as it opens), so a
-- burst of guild messages or roster events draws once
local function clock() return (GetTime and GetTime()) or 0 end
function UI:Refresh()
  if not (self.frame and self.frame:IsShown()) or self.drawing then return end
  if self.refreshing then return end
  self.refreshing = true
  local wait = math.min(1, math.max(0.05, 1 - (clock() - (self.drawnAt or -10))))
  local win = self
  C_Timer.After(wait, C.Safe(function() win.refreshing = false; if win.frame:IsShown() then win:Draw() end end, "refresh"))
end
-- every window that is open draws again (a module addon's Cute.Refresh: its page may be in any of them); DrawAll at once,
-- for a click
function UI.RefreshAll()
  for key, win in pairs(UI.windows) do
    -- (the guild window only where a module's page is open in it: its own pages draw on the guild's news)
    local def = key == "guild" and C.Modules.byId[UI.page]
    if key ~= "guild" or (def and not def.core) then win:Refresh() end
  end
end
function UI.DrawAll() for _, win in pairs(UI.windows) do if rawget(win, "frame") and win.frame:IsShown() then win:Draw() end end end
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
-- a frame of a page's own under the scroll child (a module that attaches a view it draws itself: the quest engine's
-- journal and gear pages); hidden by the next draw that does not ask for it, as the virtual lists are cleared
UI.hosts = {}
-- a band kit: a frame of a page's own on the band, made once by make(frame) and kept by key; hidden by every draw
-- until the page that uses it shows it again
UI.kits = {}
function UI:Kit(key, make)
  local k = self.kits[key]
  if not k then
    k = CreateFrame("Frame", nil, self.band)
    k:SetPoint("TOPLEFT")
    k:SetPoint("TOPRIGHT")
    k:SetHeight(10)
    self.kits[key] = k
    if make then make(k) end
  end
  k:Show()
  return k
end
-- (side: a host in the side column's scroll area, UI:Side)
function UI:Host(key, side)
  local f = self.hosts[key]
  if not f then f = CreateFrame("Frame", nil, side and self.sideScroll.child or self.scroll.child); self.hosts[key] = f end
  f.gen = self.drawGen
  f:Show()
  return f
end
-- the scroll area and its bar between the band (bandH), the room on the left (insetX) and the side column (sideW)
function UI:PlaceScroll()
  local h, side = self.bandH or 0, self.sideW and (self.sideW + 12) or 0
  self.scroll:SetPoint("TOPLEFT", 8 + (self.insetX or 0) + (self.leftW and (self.leftW + 12) or 0), -8 - h)
  self.scroll:SetPoint("BOTTOMRIGHT", -18 - side, (self.foot or 0) + 6)
  self.scroll.bar:SetPoint("TOPRIGHT", -7 - side, -8 - h)
  self.scroll.bar:SetPoint("BOTTOMRIGHT", -7 - side, (self.foot or 0) + 6)
end
-- the band's height (0 hides it); the scroll area and its bar start under it
function UI:SetBand(h)
  if self.bandH == h then return end
  self.bandH = h
  self.band:SetHeight(math.max(h, 1))
  self.band:SetShown(h > 0)
  self:PlaceScroll()
  if self.side and self.side:IsShown() then self.side:SetPoint("TOPRIGHT", -7, -8 - h) end
  if self.leftBox and self.leftBox:IsShown() then self.leftBox:SetPoint("TOPLEFT", 8 + (self.insetX or 0), -8 - h) end
end
-- room kept on the left of the scroll area and the band (Settings' list of sections); 0 gives it back
function UI:SetInset(x)
  if (self.insetX or 0) == x then return end
  self.insetX = x
  self.band:SetPoint("TOPLEFT", 8 + x, -8)
  self:PlaceScroll()
end
-- (the windows round) a column of its own on the right of the scroll area, under the band, with its own scroll bar
-- (the Quests tab's Dungeon, Gear and Party beside the questing at 1000 px and more): w wide, the scroll area keeps the
-- rest. Its pieces are hosts (UI:Host(key, true)); a draw that asks for no column gives the room back. Returns its
-- scroll area
function UI:Side(w)
  if not self.side then
    local side = CreateFrame("Frame", nil, self.content)
    self.side = side
    self.sideScroll = UI.ScrollArea(side, self, 0)
    self.sideScroll:ClearAllPoints(); self.sideScroll:SetPoint("TOPLEFT", 0, 0); self.sideScroll:SetPoint("BOTTOMRIGHT", -12, 0)
    self.sideScroll.bar:ClearAllPoints(); self.sideScroll.bar:SetPoint("TOPRIGHT", 0, 0); self.sideScroll.bar:SetPoint("BOTTOMRIGHT", 0, 0)
  end
  self.sideGen = self.drawGen
  self.side:ClearAllPoints()
  self.side:SetPoint("TOPRIGHT", -7, -8 - (self.bandH or 0))
  self.side:SetPoint("BOTTOMRIGHT", -7, (self.foot or 0) + 6)
  self.side:SetWidth(w)
  self.side:Show()
  if self.sideW ~= w then self.sideW = w; self:PlaceScroll() end
  return self.sideScroll
end
-- (the windows round) a box of its own on the left of the scroll area, under the band, that does not scroll (the Route
-- tab's map): w wide, the scroll area keeps the rest; a draw that asks for none gives the room back. Returns the box
function UI:LeftBox(w)
  if not self.leftBox then self.leftBox = CreateFrame("Frame", nil, self.content) end
  self.leftGen = self.drawGen
  local b = self.leftBox
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", 8 + (self.insetX or 0), -8 - (self.bandH or 0))
  b:SetPoint("BOTTOMLEFT", 8 + (self.insetX or 0), (self.foot or 0) + 6)
  b:SetWidth(w)
  b:Show()
  if self.leftW ~= w then self.leftW = w; self:PlaceScroll() end
  return b
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
  b:SetScript("OnClick", C.Safe(function(self)
    if not self.id then return end
    -- (the race sorts by level, highest first, until a header is clicked)
    local s = UI.sort[UI.page] or (UI.page == "race" and { id = "level", desc = true }) or {}
    if s.id == self.id then s.desc = not s.desc else s = { id = self.id, desc = true } end
    UI.sort[UI.page] = s
    UI:Draw()
  end, "header: sort"))
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
  -- the class bar: two pixels at the left edge, in the class's colour (you: your row's lighter background)
  r.bar = flat(r, "ARTWORK", WHITE, 1)
  r.bar:SetPoint("TOPLEFT", 0, 0)
  r.bar:SetPoint("BOTTOMLEFT", 0, 0)
  r.bar:SetWidth(2)
  r:SetHighlightTexture(FLAT, "ADD")
  r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)
  r.name = text(r, 12, INK, "LEFT", NAME_W - 12)
  r.name:SetPoint("LEFT", 8, 0)
  r.nx = 8 -- (the name's left: after the rank's mark where there is one, DrawTable)
  r.cells = {}
  -- on the Officers page a click picks the member, for the band's Mark untrusted (DrawOfficers)
  r:SetScript("OnClick", C.Safe(function(self)
    local row = self.row
    if UI.page ~= "officers" or not row or row.me or not row.guid or not row.addon then return end
    UI.picked = UI.picked ~= row.guid and row.guid or nil
    UI:Draw()
  end, "row: pick"))
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
    c.lx = 4 -- (its label's left: fillCell moves it for the XP column)
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
        -- (merge3) your own row: what Reminders' Before the pull shows now, which your verdict here waits on
        local pull = row.me and C.Stats.ReadyPull() or nil
        if pull then tip:AddLine("Before the pull: " .. table.concat(pull, ", ") .. ".", 0.9, 0.9, 0.9, true) end
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
local LOCK = "|T130944:10:10|t " -- (UI-ChatFrame-LockIcon: a value only the officers and its member see)
local function fillCell(c, def, row, hidden, w, onlyYou)
  c.def, c.row, c.hidden = def, row, hidden
  c.label:SetJustifyH(alignOf(def))
  if c.lx ~= 4 then c.label:SetPoint("LEFT", 4, 0); c.lx = 4 end -- (placed again only when it moved: a redraw places nothing)
  for _, p in ipairs(c.pips) do p:Hide() end
  if c.track then c.bar:Hide(); c.track:Hide() end
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
  -- (merge3) your own Ready agrees with Reminders' Before the pull: "gaps" at best while it shows something (Stats.lua)
  if def.id == "ready" and row.me and type(v) == "number" then v = C.Stats.ReadyOwn(v) end
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
    -- (the windows round) the XP column: a 40 px track, 3 px tall, your share of the level on it, the percent after;
    -- made for the cells that show it
    if not c.track then
      c.track = flat(c, "ARTWORK", { 0.16, 0.16, 0.16 }, 1)
      c.track:SetSize(40, 3)
      c.track:SetPoint("LEFT", 4, 0)
      c.bar = flat(c, "OVERLAY", WHITE, 0.75)
      c.bar:SetHeight(3)
      c.bar:SetPoint("LEFT", 4, 0)
    end
    c.track:Show()
    c.bar:SetWidth(math.max(1, 40 * math.max(0, math.min(100, v)) / 100))
    c.bar:Show()
    c.label:SetJustifyH("LEFT")
    if c.lx ~= 49 then c.label:SetPoint("LEFT", 49, 0); c.lx = 49 end
    if not s:find("%%$") then s = s .. "%" end
  end
  if def.id == "durability" and type(v) == "number" and v < 50 then color(c.label, BAD) end
  if def.id == "ready" and type(v) == "number" then color(c.label, v == 2 and GOOD or (v == 1 and WARN or BAD)) end
  if def.kind == "flag" then color(c.label, v and INK or MUTE) end
  if v == nil then color(c.label, MUTE) end
  -- (an officer seeing a member's Only-you value: muted, with the lock)
  if onlyYou and v ~= nil then color(c.label, MUTE); s = LOCK .. s end
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
-- sorts it). sortedRows keeps a page's sorted list until the roster changes (R.version), the sort or the offline
-- switch does: a draw with nothing new sorts nothing (a guild of hundreds sorted every draw, once a second)
local sortCache = {}
local rowsShown
local function sortedRows(page)
  local s = UI.sort[page]
  local key = string.format("%s:%s:%s:%s", tostring(C.Roster.version), tostring(s and s.id), tostring(s and s.desc), tostring(C.Settings().offline))
  local hit = sortCache[page]
  if hit and hit.key == key then return hit.rows end
  local rows = rowsShown()
  sortRows(rows, page)
  sortCache[page] = { key = key, rows = rows }
  return rows
end
function rowsShown()
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
  local rows = sortedRows(page)
  -- (worked out once a draw: an officer's view of the Only-you columns, the line's officer ranks for the marks)
  for _, col in ipairs(cols) do col.onlyYou = officer and C.Policy:Route(col.def.id) == "self" or nil end
  local officerRanks = C.Policy:LineThreshold()
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
    -- (you by your row's 0.06 background, never a white bar: white is the priest's colour)
    r.bg:SetColorTexture(1, 1, 1, picked and 0.1 or (row.me and 0.06) or (i % 2 == 0 and 0.03 or 0))
    local cc = row.class and classColor(row.class) or MUTE
    if not row.online then cc = dimmed(cc) end
    r.bar:SetColorTexture(cc[1], cc[2], cc[3], 1)
    color(r.name, row.addon and cc or MUTE)
    -- the guild master's mark, an officer's (the line's officer ranks), before the name
    local rank = row.guild and row.guild.rank
    local mark = rank == 0 and 132062 or ((type(rank) == "number" and rank <= officerRanks) and 132061 or nil)
    local nx = mark and 20 or 8
    if mark then
      -- (the guild master's or an officer's mark before the name, 12 px: UI-Group-LeaderIcon, UI-GROUP-ASSISTANTICON;
      -- made for the rows that show one)
      if not r.rank then r.rank = tex(r, "ARTWORK", nil, 12, 12); r.rank:SetPoint("LEFT", 6, 0) end
      r.rank:SetTexture(mark); r.rank:Show()
    elseif r.rank then r.rank:Hide() end
    if r.nx ~= nx then r.name:SetPoint("LEFT", nx, 0); r.nx = nx end
    local nameRoom = NAME_W - 16 - (mark and 12 or 0)
    -- "(you)" and "(no addon)" only where they fit whole: a two-word name keeps its words, and the grey of a member
    -- without the addon says it already. An officer sees a member they marked untrusted, or whose addon sent what
    -- cannot be, marked so (the row's tooltip says why)
    local suffix = row.me and "  (you)" or (not row.addon and "  (no addon)" or nil)
    if not suffix and officer then suffix = row.untrusted and "  (untrusted)" or (row.suspect and "  (suspect)" or nil) end
    if suffix then
      -- (fitText says whether the text fit whole: no label text is read back and compared)
      if not fitText(r.name, row.short .. suffix, nameRoom) then fitText(r.name, row.short, nameRoom) end
    else fitText(r.name, row.short, nameRoom) end
    for k, col in ipairs(cols) do
      local c = r.cells[k]
      if not c:IsShown() then c:Show() end
      fillCell(c, col.def, row, not C.Policy:CanSee(officer, row.me, col.def.id), col.w, col.onlyYou and not row.me)
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
        if row.addon and not row.untrusted and type(v) == "number" and C.Policy:CanSee(officer, row.me, def.id) then top[#top + 1] = { short = row.short, v = v, me = row.me, class = row.class } end
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
        -- (the leader's name in their class's colour, as every member's name is: the windows round)
        card.leader:SetText(string.format("%s%s|r  %s%s|r", hex(top[1].class and classColor(top[1].class) or WHITE), top[1].short, hex(DIM), UI.Format(def, top[1].v)))
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
  -- (named as Settings names them: Who sees what, Broadcast now)
  local labels = { { "Who sees what", function() UI.OpenSettings("vis") end },
    { "Ask everyone to resend", function() C.Comm:Ask(); C.Print("asked the guild to send their records again.") end },
    { "Broadcast now", function() C.Comm:Broadcast() end },
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
    b:SetScript("OnClick", C.Safe(d[2], "officers: " .. d[1]))
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
  -- (both buttons: a row's fn hears which, the Guide's band row opens a step's menu on the right one)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  -- (a page's click, a module's code among them: an error recorded, never raised)
  r:SetScript("OnClick", C.Safe(function(self, which) if self.fn then self.fn(self, which) end end, "row: click"))
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
    self.catBox:Hide(); self:SetInset(0)
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
  -- the categories in a column of their own (the list beside it scrolls alone): the inset gives the list the rest
  self:SetInset(leftW + 12)
  local box = self.catBox
  box:SetWidth(leftW + 10)
  box:Show()
  w = math.max(100, w - leftW - 12)
  local rightX, rightW = 0, w
  -- the tree folded as the game's own Statistics tab folds it: the top categories, and the children of the open one's
  -- family; a parent counts its children's statistics with its own and lists them under their names
  local byId, kids = {}, {}
  for _, cat in ipairs(board.cats) do byId[cat.id] = cat end
  for _, cat in ipairs(board.cats) do
    if cat.parent ~= -1 and byId[cat.parent] then kids[cat.parent] = kids[cat.parent] or {}; table.insert(kids[cat.parent], cat) end
  end
  local function countOf(cat)
    if cat.count then return cat.count end
    local n = #cat.stats
    for _, k in ipairs(kids[cat.id] or {}) do n = n + #k.stats end
    return n
  end
  local function topOf(cat) local c = cat; while c and c.parent ~= -1 and byId[c.parent] do c = byId[c.parent] end return c end
  -- the open category: the one clicked, else the first with anything in it
  local sel = self.gameCat
  if not (sel ~= nil and byId[sel] and countOf(byId[sel]) > 0) then
    sel = nil
    for _, cat in ipairs(board.cats) do if countOf(cat) > 0 then sel = cat.id; break end end
    self.gameCat = sel
  end
  local family = sel and topOf(byId[sel]) or nil
  local shownCats = {}
  for _, cat in ipairs(board.cats) do
    if cat.parent == -1 or not byId[cat.parent] or (family and topOf(cat) == family) then shownCats[#shownCats + 1] = cat end
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
  local top = 0
  local cw = leftW
  self.catLines:Set(#shownCats, top, ROW, function(r, i, y)
    local cat = shownCats[i]
    local n = countOf(cat)
    local opens = cat.id
    local open = cat.id == sel
    r.cat, r.def, r.member = cat, nil, nil
    r:SetPoint("TOPLEFT", 0, -y)
    r:SetWidth(cw)
    r:SetHeight(ROW)
    r.bg:SetColorTexture(1, 1, 1, open and 0.06 or (i % 2 == 0 and 0.03 or 0))
    r.bar:SetShown(open)
    r.bar:SetColorTexture(WHITE[1], WHITE[2], WHITE[3], 1)
    local indent = (cat.parent ~= -1 and byId[cat.parent]) and 14 or 0
    r.name:SetPoint("LEFT", 8 + indent, 0)
    r.name:SetWidth(cw - 8 - indent - 40)
    color(r.name, open and WHITE or (n > 0 and INK or MUTE))
    fitText(r.name, cat.name, cw - 12 - indent - 40)
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
  local leftY = top + #shownCats * ROW
  -- a client without the game's statistics says so under the categories, wrapped to the column
  if S.gameNote and #S.byCat.game == 0 then
    if not self.gameNoteLabel then self.gameNoteLabel = text(self.catScroll.child, 11, MUTE, "LEFT") end
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
  -- the open category's own statistics, then each child's under the child's name
  local defs = {}
  local heads = {}
  for _, def in ipairs((sel ~= nil and board.byCat[sel]) or {}) do defs[#defs + 1] = def end
  for _, k in ipairs(sel and kids[sel] or {}) do
    if #k.stats > 0 then
      heads[#defs + 1] = k
      for _, def in ipairs(k.stats) do defs[#defs + 1] = def end
    end
  end
  local items = {}
  for i, def in ipairs(defs) do
    if heads[i] then items[#items + 1] = { head = heads[i] } end
    self.shownIds[def.id] = true
    -- who sees it, asked once a stat (the policy's route, not once a member and stat: a guild of hundreds drew a
    -- category's thousands of routes a draw); the leader among the values this viewer may see, found without a table
    -- a member, and above 0 (a leader at 0 named the first in the roster for what nobody has done; a standing is a value
    -- below 0 too). A member the officers marked untrusted is in no ranking
    local everyone = officer or C.Policy:Route(def.id) == "all"
    local leads0 = def.learned == "rep"
    local open = self.gameOpen[def.id] == true
    local best, bestV
    for _, row in ipairs(rows) do
      if row.addon and not row.untrusted and (everyone or row.me) then
        local v = row.stats[def.id]
        if type(v) == "number" and (v > 0 or leads0) and (not bestV or v > bestV or (v == bestV and row.sort < best.sort)) then best, bestV = row, v end
      end
    end
    -- (a stat the officers keep: a member sees their own value alone, so names no leader, themselves included)
    local kept = not everyone
    if kept then best = nil end
    items[#items + 1] = { def = def, i = i, best = best and { row = best, v = bestV } or nil, open = open, kept = kept }
    if open then
      -- every member's value as this viewer may see it, for the open stat alone
      local ranked = {}
      for _, row in ipairs(rows) do
        if row.addon and not row.untrusted then
          local hidden = not (everyone or row.me)
          local v = row.stats[def.id]
          ranked[#ranked + 1] = { row = row, v = (not hidden and type(v) == "number") and v or nil, hidden = hidden, at = row.at and row.at[def.id] }
        end
      end
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
    if it.head then
      -- a child category's name over its statistics: no value, no click
      r.cat, r.def, r.member = nil, nil, nil
      r:SetHeight(ROW)
      r:SetPoint("TOPLEFT", rightX, -y)
      r:SetWidth(rightW)
      r.bg:SetColorTexture(1, 1, 1, 0.035)
      r.bar:Hide()
      r.name:SetPoint("LEFT", 8, 0)
      r.name:SetWidth(rightW - 16)
      color(r.name, DIM)
      fitText(r.name, it.head.name, rightW - 20)
      r.val:Hide(); r.who:Hide()
      r.fn = nil
      r.tip = function(tip) tip:AddLine(it.head.path or it.head.name, 1, 1, 1) end
      return
    end
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
      -- (you by the 0.06 background and your class's bar, never a white bar: white is the priest's)
      r.bg:SetColorTexture(1, 1, 1, e.row.me and 0.06 or 0.015)
      local cc = e.row.class and classColor(e.row.class) or MUTE
      if not e.row.online then cc = dimmed(cc) end
      r.bar:Show()
      r.bar:SetColorTexture(cc[1], cc[2], cc[3], 1)
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
  local win = self
  self.virtual = function()
    win.catLines:Show(win.catScroll.bar:GetValue() or 0, win.catScroll:View())
    win.lines:Show(win.scroll.bar:GetValue() or 0, win.scroll:View())
  end
  local y = top + #items * ROW
  if #defs == 0 then say(rightX + 8, y, rightW - 16, "Nothing in this category.", MUTE); y = y + 20 end
  self.labels:HideRest()
  self.catScroll:SetContentHeight(leftY + 8)
  sf:SetContentHeight(y + 8)
end

-- the footer: when the roster last changed (the guild window's; another window has none, or its own)
function UI:DrawFooter()
  if self ~= UI or not self.footer then return end
  local s
  if not C.Roster:InGuild() then s = "Not in a guild"
  elseif not C.Roster.updatedAt then s = "No reports yet"
  else s = "Updated " .. (ago(C.Roster.updatedAt) or "") end
  self.footer:SetText(s)
end

-- the whole draw runs under C.Safe: an error anywhere in it (the client swallows one with scriptErrors off) lands in
-- /cute errors as "draw", and drawing is reset on every path, so the next Refresh, ValueChanged or scroll draws
-- again instead of returning early for the rest of the session (0.6.0 left the flag set). Each window draws its own:
-- Settings its sections (Settings.lua), the others the open page of a module that says that window
local function drawBody(self)
  self.drawnAt = clock()
  self.draws = (self.draws or 0) + 1
  -- the page says which stats it shows (a change to another draws nothing) and, for a virtual list, how to scroll
  self.shownIds, self.virtual = {}, nil
  local settings = self.key == "settings"
  local page = self.page
  local officer = C.Roster:MeOfficer()
  -- a page whose module went off (or an officer's, for a member) gives way to its window's first page
  local mod
  if not settings then
    mod = C.Modules.Page(page, officer)
    if not mod or (mod.window or "guild") ~= self.key then page = self.home; self.page = page; mod = C.Modules.Page(page, officer) end
    if self.tabRow then self:DrawTabs(page, officer) end
  end
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
  if page ~= "game" and self.catBox and self.catBox:IsShown() then self.catBox:Hide(); self:SetInset(0) end
  -- the virtual lists a page does not fill are cleared after it, so a page change hides the last page's rows
  local rowsGen, linesGen, catGen = self.rows.gen, self.lines.gen, self.catLines.gen
  local gens = {}
  for key, v in pairs(self.lists) do gens[key] = v.gen end
  self.drawGen = (self.drawGen or 0) + 1
  -- (a page's band kit, its own pieces and not pooled ones, the Quests tab's and the Route tab's: hidden before any
  -- page draws, shown by the page that uses it: UI:Kit)
  for _, k in pairs(self.kits) do k:Hide() end
  -- (the side column and the left box are the page's that asks for them this draw: the scroll area whole until then)
  if self.sideW or self.leftW then self.sideW, self.leftW = nil, nil; self:PlaceScroll() end
  if settings then C.Settings_Draw(self)
  elseif mod then C.Safe(function() mod.page(self, self.scroll) end, "page: " .. page)() end
  if self.rows.gen == rowsGen then self.rows:Clear() end
  if self.lines.gen == linesGen then self.lines:Clear() end
  if self.catLines.gen == catGen then self.catLines:Clear() end
  for key, v in pairs(self.lists) do if v.gen == gens[key] then v:Clear() end end
  for _, f in pairs(self.hosts) do if f.gen ~= self.drawGen and f:IsShown() then f:Hide() end end
  -- (a page that asked for no side column: its room back to the scroll area)
  if self.side and self.sideGen ~= self.drawGen and self.side:IsShown() then self.side:Hide(); self.sideW = nil; self:PlaceScroll() end
  if self.leftBox and self.leftGen ~= self.drawGen and self.leftBox:IsShown() then self.leftBox:Hide(); self.leftW = nil; self:PlaceScroll() end
  self.labels:HideRest()
  self.bandLabels:HideRest(); self.bandButtons:HideRest(); self.bandLines:HideRest()
  local _, maxv = bar:GetMinMaxValues()
  bar:SetValue(math.max(0, math.min(keep, maxv or 0)))
  -- the rows in view, at the place kept (the scroll's own redraw waits while drawing)
  if self.virtual then self.virtual() end
  self:DrawStatus(officer)
  self:DrawFooter()
end
local function drawDone(win) win.drawing = false end
function UI:Draw()
  if not rawget(self, "frame") then return end -- (a window never opened has nothing to draw)
  self.drawing = true
  local win = self
  C.Safe(drawBody, "draw", function() drawDone(win) end)(self)
end
-- the status, at the footer's right: who is online with the addon and which Cute this is (a screenshot names its
-- build), and "update available" while a guild mate runs a newer Cute than yours (Core.lua C.SawVersion, which draws it
-- again when one arrives)
local DOT = "  \194\183  "
function UI:DrawStatus(officer)
  if self ~= UI or not self.status then return end
  local online = 0
  for _, r in ipairs(C.Roster:Rows()) do if r.online and r.addon then online = online + 1 end end
  local s = string.format("%d online with Cute%sCute %s", online, DOT, tostring(C.version))
  if C.newer then s = s .. DOT .. C.COLOR .. "update available|r" end
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
  -- (the keys this character chose, once a session: Keys.lua)
  if C.Keys then C.Keys.Start() end
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
  -- around the minimap's edge: a circle on the round minimap, the square's edge where a minimap addon made it square
  -- (GetMinimapShape is theirs to define, as LibDBIcon reads it; the game has none, and its minimap is round)
  local function place()
    local angle = math.rad(C.Settings().minimapPos or 220)
    local r = (Minimap:GetWidth() or 140) / 2 + 10
    local x, y = math.cos(angle) * r, math.sin(angle) * r
    local shape = type(GetMinimapShape) == "function" and C.Plain(select(2, pcall(GetMinimapShape))) or "ROUND"
    if shape ~= "ROUND" and type(shape) == "string" then
      local d = r * 1.4142
      x = math.max(-r, math.min(r, math.cos(angle) * d))
      y = math.max(-r, math.min(r, math.sin(angle) * d))
    end
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", x, y)
  end
  -- (every frame while dragged: an error is recorded once a frame at most, never raised)
  local drag = C.Safe(function()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    if not (mx and cx) then return end
    cx, cy = cx / scale, cy / scale
    C.Settings().minimapPos = math.deg(math.atan2(cy - my, cx - mx))
    place()
  end, "minimap button: drag")
  b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", drag) end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  -- a click: the guild window; a right-click: the menu of every window, tab and Settings section (Windows.lua)
  b:SetScript("OnClick", C.Safe(function(self, which)
    if which == "RightButton" then C.Windows.Menu(self) else UI:Toggle() end
  end, "minimap button"))
  tooltip(b, function(tip)
    tip:AddLine("Cute", 1, 1, 1)
    tip:AddLine("Click: guild. Right-click: menu. Drag: move.", 0.7, 0.7, 0.7, true)
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
-- (each page's list under its own name in Settings > Columns)
C:RegisterModule({ id = "race", title = "Race", order = 10, core = true, tab = 64, page = function(ui) ui:DrawTable("race") end, settings = columns("race", "Race") })
C:RegisterModule({ id = "prog", title = "Prog", order = 30, core = true, tab = 64, page = function(ui) ui:DrawTable("prog") end, settings = columns("prog", "Prog") })
C:RegisterModule({ id = "shame", title = "Hall of Shame", order = 40, core = true, tab = 110, page = function(ui) ui:DrawShame() end, settings = columns("shame", "Hall of Shame cards") })
C:RegisterModule({ id = "game", title = "Statistics", order = 50, core = true, tab = 80, page = function(ui) ui:DrawGame() end })
C:RegisterModule({ id = "officers", title = "Officers", order = 60, core = true, officer = true, tab = 80, page = function(ui) ui:DrawOfficers() end, settings = columns("officers", "Officers") })
C:RegisterModule({ id = "me", title = "Me", order = 70, core = true, tab = 48, page = function(ui) ui:DrawMe() end })
