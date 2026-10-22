-- SPDX-License-Identifier: GPL-3.0-or-later
-- Settings: its own window (CuteSettingsFrame, made by UI.lua's builder), the sections down the left under three group
-- heads, the chosen one on the right in one column, drawn flat like the rest. Every section draws with the column below
-- (a heading, a note, a check row, a step down and up, a row of buttons, a text box, a choice of one) and starts with a
-- heading, so the spacing is the same everywhere and a module's section looks like the core's. Nothing in it is cut:
-- labels and notes wrap, a choice measures its options, and the list of sections scrolls rather than shrink its rows.
--   Cute    General (display; about you), Keys (Keys.lua: the keys that open Cute's windows), Layout (Layout.lua: the
--           pieces on screen moved, locked and reset), Modules (switched on and off for this character; the change
--           waits for a reload, Modules.lua), and what a module addon adds there (Data you share: Cute_Quest's)
--   Guild   Columns (Race, Prog, Hall of Shame and, for officers, Officers), Who sees what (per stat, Everyone or Only
--           you, the officer ranks, Save to Guild Info, Broadcast now, Reset; a member reads one line of it), Rules
--           (the officers': the thresholds the guild learns by, and the dungeons and gear ones), then the guild
--           window's modules' own (Runs)
--   Quests  the quest window's modules' own (Quests, Route, Map, Dungeons and gear, Camp)
-- Each window's cog opens its group's first section (the guild's General, the quests' Quests).
local _, C = ...
local ST = { extra = {} }
C.SettingsPage = ST

local WHITE = { 0.96, 0.96, 0.96 }
local INK = { 0.86, 0.86, 0.86 }
local DIM = { 0.58, 0.58, 0.58 }
local MUTE = { 0.52, 0.52, 0.52 }

local NAV_W = 168   -- the list of sections
local NAV_GAP = 12  -- between it and the column
local COL_MAX = 560 -- the column: wider, a label and its boxes read as two things far apart
-- the column's spacing, the same in every section. Nothing in Settings is cut: a label or a note wraps and its row grows
-- to the lines it needs (from 22 px), a choice measures its options and wraps them under its label, and the list of
-- sections never shrinks its rows (it scrolls)
local HEAD, NOTE, ROWH, STEP, BTNS, GAP, BTN_GAP = 20, 18, 22, 24, 28, 10, 6
local LABEL_W = 120  -- a choice's label column
local STEPPER = 74   -- a step's buttons and value: 20 + 34 + 20
local RIGHT_W = 176  -- the words on a check row's right
local NAV_ROW, NAV_HEAD = 22, 20

local widgets = {}
local nav

local function pool(parent, make)
  local p = { items = {}, used = 0 }
  function p:Get()
    self.used = self.used + 1
    local it = self.items[self.used]
    -- (everything Settings draws is never cut: the harness fails a cut label under a frame marked so)
    if not it then it = make(parent); it.cuteNoCut = true; self.items[self.used] = it end
    it:Show()
    return it
  end
  function p:Reset() self.used = 0 end
  function p:HideRest() for i = self.used + 1, #self.items do self.items[i]:Hide() end end
  return p
end
local POOLS = { "checks", "boxes", "labels", "values", "buttons", "edits", "keys", "navLines", "navHeads" }

local function ensure(ui)
  if widgets.checks then return end
  local parent = ui.scroll.child
  ui.frame.cuteNoCut = true
  -- (a check with a label is a row button, ticked by a click anywhere on it: UI.lua checkRow; a box alone, the
  -- Everyone / Only-you pairs, is a check box)
  widgets.checks = pool(parent, function(p) return C.UI.CheckRow(p) end)
  widgets.boxes = pool(parent, function(p) return C.UI.Check(p) end)
  widgets.labels = pool(parent, function(p) return C.UI.Text(p, 12, INK, "LEFT", 300) end)
  -- (a step's value, between its buttons, apart from its label so the label wraps and the number never moves)
  widgets.values = pool(parent, function(p) return C.UI.Text(p, 12, INK, "CENTER", 34) end)
  widgets.buttons = pool(parent, function(p) return C.UI.Button(p, "", 140) end)
  widgets.edits = pool(parent, function(p)
    local e = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    e:SetSize(140, 20)
    e:SetAutoFocus(false)
    e:SetMaxLetters(24)
    e:SetFont(C.UI.FONT, 12, "")
    return e
  end)
  -- (the key boxes of Settings > Keys: Keys.lua's, a click and then a key)
  widgets.keys = pool(parent, function(p) return C.Keys.Box(p) end)
  -- (a choice's options and a button's label are measured on this one, never shown)
  widgets.measure = C.UI.Text(parent, 13, INK, "LEFT")
  widgets.measure:Hide()
  -- the list of sections: a scroll list of its own beside the column, so it stays while a long section scrolls, its
  -- rows 22 px and its group heads 20 px at any size (past the window's height it scrolls)
  local box = CreateFrame("Frame", nil, ui.content)
  box:SetPoint("TOPLEFT", 8, -8)
  box:SetPoint("BOTTOMLEFT", 8, 8)
  box:SetWidth(NAV_W + 8)
  local sf = C.UI.ScrollArea(box, { frame = ui.frame, OnScroll = function() end }, 0)
  sf:ClearAllPoints(); sf:SetPoint("TOPLEFT"); sf:SetPoint("BOTTOMRIGHT", -8, 0)
  sf.bar:ClearAllPoints(); sf.bar:SetPoint("TOPRIGHT"); sf.bar:SetPoint("BOTTOMRIGHT")
  nav = box
  nav.list = sf
  widgets.navLines = pool(sf.child, function(p) return ui:MakeLine(p) end)
  widgets.navHeads = pool(sf.child, function(p) return C.UI.Text(p, 11, DIM, "LEFT") end)
end
local function color(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end
local function tipOn(owner, fill)
  if not fill then owner:SetScript("OnEnter", nil); owner:SetScript("OnLeave", nil); return end
  owner:SetScript("OnEnter", C.Safe(function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    fill(GameTooltip)
    GameTooltip:Show()
  end, "settings: tooltip"))
  owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

----------------------------------------------------------------------------
-- the column: every section draws with these, top to bottom. x and w are the column's; y grows as it draws. A
-- column in the band (the visibility list's controls) takes the band's labels and buttons
----------------------------------------------------------------------------
local Col = {}
Col.__index = Col
ST.Col = Col
local function column(x, w, band, ui)
  ui = ui or C.UI.Window("settings")
  local p = band and { labels = ui.bandLabels, values = ui.bandLabels, buttons = ui.bandButtons }
    or { labels = widgets.labels, values = widgets.values, buttons = widgets.buttons }
  return setmetatable({ x = x, w = w, y = 4, fresh = true, p = p, ui = ui }, Col)
end
-- a FontString at a size of its own (a pooled one may come from a smaller use)
local function sized(fs, n)
  if fs.cuteSize ~= n then
    if fs:SetFont(C.UI.FONT, n, "") == false then fs:SetFontObject(GameFontNormal) end
    fs.cuteSize = n
  end
end
-- the height a wrapped label takes: the game lays it out at its width (GetStringHeight), one line at least
local function heightOf(fs, n) return math.max(n + 2, math.ceil(fs:GetStringHeight() or 0)) end
-- a label, never cut: it wraps to its width, and the caller takes the height it returns
local function label(col, x, y, w, s, c, justify, size)
  local l = col.p.labels:Get()
  l:ClearAllPoints()
  l:SetPoint("TOPLEFT", x, -y)
  l:SetWidth(w)
  l:SetJustifyH(justify or "LEFT")
  l:SetWordWrap(true)
  sized(l, size or 13)
  color(l, c)
  l:SetText(s or "")
  l.cuteCut, l.cuteStepValue = nil, nil
  return l, heightOf(l, size or 13)
end
-- the width a text takes at a size, measured on a hidden FontString of the column's own
local function measure(s, size)
  local m = widgets.measure
  sized(m, size)
  m:SetText(s or "")
  return math.ceil(((m.GetUnboundedStringWidth or m.GetStringWidth)(m)) or 0)
end
-- after a click that changes what the section shows (a choice, a pair): the section drawn again
local function redraw() if C.SettingsPage.Redraw then C.SettingsPage.Redraw() end end

-- a heading, white; a gap above it unless it is the first thing in the column
function Col:Head(s)
  if not self.fresh then self.y = self.y + GAP end
  self.fresh = false
  local _, h = label(self, self.x, self.y, self.w, s, WHITE, nil, 13)
  self.y = self.y + math.max(HEAD, h + 5)
end
-- a line of explanation, dim, wrapping to the column
function Col:Note(s)
  self.fresh = false
  local _, h = label(self, self.x, self.y + 1, self.w, s, DIM, nil, 12)
  self.y = self.y + math.max(NOTE, h + 4)
end
-- a check row: the box with its label, one button the width of the column (up to the right-hand words), so a click
-- anywhere on the row ticks it; the label wraps and the row grows with it. right: a few dim words at the row's end
-- (176 px, wrapping too); tip: function(tooltip) for its tooltip; indent: room on the left (a module's tab under its
-- window)
function Col:Check(text, on, enabled, fn, right, tip, indent)
  self.fresh = false
  indent = indent or 0
  local cb = widgets.checks:Get()
  local room = self.w - indent - (right and (RIGHT_W + 8) or 0)
  sized(cb.label, 13)
  cb.label:ClearAllPoints()
  cb.label:SetPoint("TOPLEFT", 20, -4)
  cb.label:SetWidth(room - 24)
  cb.label:SetWordWrap(true)
  cb.label:SetText(text or "")
  cb.label.cuteCut = nil
  local h = heightOf(cb.label, 13)
  local rh
  if right then
    local _, rh2 = label(self, self.x + self.w - RIGHT_W, self.y + 5, RIGHT_W, right, MUTE, "RIGHT", 11)
    rh = rh2
  end
  local rowH = math.max(ROWH, h + 7, (rh or 0) + 9)
  cb:ClearAllPoints()
  cb:SetPoint("TOPLEFT", self.x + indent, -self.y)
  cb:SetSize(room, rowH)
  cb:Set(on and true or false)
  cb:SetOn(enabled ~= false)
  cb.statId, cb.vis = nil, nil
  cb.fn = function(b)
    if enabled == false then b:Set(on and true or false) return end
    fn(b:GetChecked())
  end
  tipOn(cb, tip)
  self.y = self.y + rowH
  return cb
end
-- (the hud review) under a row, what it keeps hidden: one DIM line at 12 px, indented as the row's label and wrapping
-- ("Hidden: Eat, Frost Armor"), its Show button on the right, fn the click (Reminders' rows, Cute_Quest's PageCamp.lua)
function Col:Hidden(text, fn)
  self.fresh = false
  local bw = 58
  local _, h = label(self, self.x + 20, self.y + 4, self.w - 20 - bw - 8, text, DIM, nil, 12)
  local b = self.p.buttons:Get()
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", self.x + self.w - bw, -self.y - 1)
  b:SetSize(bw, 20)
  b:SetLabel("Show")
  b:SetOn(fn ~= nil)
  b:SetScript("OnClick", C.Safe(function() if fn then fn(); redraw() end end, "settings: show hidden"))
  tipOn(b, nil)
  self.y = self.y + math.max(ROWH, h + 8)
end
-- a choice of one among a few: the label in a column of its own, then each option as a box and its word, measured (a
-- cell is the box, 6 px, the word and 12 px), wrapping under the label where the row is full. A click on the chosen one
-- keeps it (none: it chooses none, for a choice that may have none, as Role); the section draws again either way
function Col:Choice(text, options, current, fn, none)
  self.fresh = false
  local _, lh = label(self, self.x, self.y + 4, LABEL_W - 4, text, INK, nil, 13)
  local x0, right = self.x + LABEL_W, self.x + self.w
  local cx, line = x0, 0
  for _, opt in ipairs(options) do
    local cell = 14 + 6 + measure(opt, 13) + 12
    if cx > x0 and cx + cell > right then cx = x0; line = line + 1 end
    local cb = widgets.checks:Get()
    sized(cb.label, 13)
    cb.label:ClearAllPoints()
    cb.label:SetPoint("TOPLEFT", 20, -4)
    cb.label:SetWidth(cell - 20)
    cb.label:SetWordWrap(true)
    cb.label:SetText(opt)
    cb.label.cuteCut = nil
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", cx, -(self.y + line * ROWH))
    cb:SetSize(math.min(cell, right - cx), ROWH)
    cb:Set(current == opt)
    cb:SetOn(true)
    cb.statId, cb.vis = nil, nil
    cb.fn = function(b)
      if not b:GetChecked() and not none then b:Set(true) return end
      fn(b:GetChecked() and opt or "")
      redraw()
    end
    tipOn(cb, nil)
    cx = cx + cell
  end
  self.y = self.y + math.max((line + 1) * ROWH, lh + 7)
end
-- several boxes in one row after its label, each on or off on its own (the journal's kinds), measured and wrapped as
-- a choice's options: on(i) says whether option i is on, set(i, on) takes a click
function Col:Checks(text, options, on, set)
  self.fresh = false
  local _, lh = label(self, self.x, self.y + 4, LABEL_W - 4, text, INK, nil, 13)
  local x0, right = self.x + LABEL_W, self.x + self.w
  local cx, line = x0, 0
  for i, opt in ipairs(options) do
    local cell = 14 + 6 + measure(opt, 13) + 12
    if cx > x0 and cx + cell > right then cx = x0; line = line + 1 end
    local cb = widgets.checks:Get()
    sized(cb.label, 13)
    cb.label:ClearAllPoints()
    cb.label:SetPoint("TOPLEFT", 20, -4)
    cb.label:SetWidth(cell - 20)
    cb.label:SetWordWrap(true)
    cb.label:SetText(opt)
    cb.label.cuteCut = nil
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", cx, -(self.y + line * ROWH))
    cb:SetSize(math.min(cell, right - cx), ROWH)
    cb:Set(on(i) and true or false)
    cb:SetOn(true)
    cb.statId, cb.vis = nil, nil
    cb.fn = function(b) set(i, b:GetChecked()); redraw() end
    tipOn(cb, nil)
    cx = cx + cell
  end
  self.y = self.y + math.max((line + 1) * ROWH, lh + 7)
end
-- a text box after its label: get gives what it shows, set takes what was typed (Enter, or leaving the box); a redraw
-- while you type leaves your typing alone
function Col:Edit(text, get, set)
  self.fresh = false
  local _, lh = label(self, self.x, self.y + 4, LABEL_W - 4, text, INK, nil, 13)
  local e = widgets.edits:Get()
  e:ClearAllPoints()
  e:SetPoint("TOPLEFT", self.x + LABEL_W + 6, -self.y - 1)
  e:SetWidth(math.min(160, self.w - LABEL_W - 10))
  if not e:HasFocus() then e:SetText(get() or "") end
  e:SetScript("OnEnterPressed", C.Safe(function(b) set(b:GetText() or ""); b:ClearFocus() end, "settings: a text box"))
  e:SetScript("OnEscapePressed", C.Safe(function(b) b:SetText(get() or ""); b:ClearFocus() end, "settings: a text box"))
  e:SetScript("OnEditFocusLost", C.Safe(function(b) set(b:GetText() or "") end, "settings: a text box"))
  self.y = self.y + math.max(STEP, lh + 7)
end
-- a value with a step down and up: the label in the rest of the width (wrapping), the stepper on the right, 74 px (20 px
-- buttons, the value between), both white where white is true; down and up nil where that step is shut (greyed); tip,
-- the buttons' tooltip
function Col:Step(text, value, white, down, up, tip)
  self.fresh = false
  local x, w = self.x, self.w
  local _, lh = label(self, x, self.y + 4, w - STEPPER - 8, text, white and WHITE or INK, nil, 13)
  local val = self.p.values:Get()
  val:ClearAllPoints()
  val:SetPoint("TOPLEFT", x + w - STEPPER + 20, -self.y - 5)
  val:SetWidth(STEPPER - 40)
  val:SetJustifyH("CENTER")
  val:SetWordWrap(false)
  sized(val, 12)
  color(val, white and WHITE or INK)
  C.UI.FitText(val, value, STEPPER - 40)
  val.cuteStepValue = true -- (the harness reads a step's value by it)
  for i, d in ipairs({ { "-", down }, { "+", up } }) do
    local b = self.p.buttons:Get()
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", x + w - STEPPER + (i - 1) * (STEPPER - 20), -self.y - 1)
    b:SetSize(20, 20)
    b:SetLabel(d[1])
    b:SetOn(d[2] ~= nil)
    b:SetScript("OnClick", C.Safe(function() if d[2] then d[2]() end end, "settings: step"))
    tipOn(b, tip)
  end
  self.y = self.y + math.max(STEP, lh + 7)
end
-- a row of buttons, { label, enabled, fn, tip } each, as wide as its label (90 px at least), left to right and onto a
-- second row where the column is full, a little apart from the rows above; tip: function(tooltip) for its tooltip
function Col:Buttons(list)
  if not self.fresh then self.y = self.y + BTN_GAP end
  self.fresh = false
  local bx, line = self.x, 0
  for _, d in ipairs(list) do
    local bw = math.max(90, measure(d[1], 12) + 24)
    if bx > self.x and bx + bw > self.x + self.w then bx = self.x; line = line + 1 end
    local b = self.p.buttons:Get()
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", bx, -self.y - 2 - line * BTNS)
    b:SetSize(bw, 22)
    b:SetLabel(d[1])
    b:SetOn(d[2] and true or false)
    b:SetScript("OnClick", C.Safe(function() if d[2] then d[3]() end end, "settings: " .. tostring(d[1])))
    tipOn(b, d[4])
    bx = bx + bw + 6
  end
  self.y = self.y + BTNS * (line + 1)
end

-- a rule's threshold (Rules.lua): its value and a step down and up, the officers' to set and greyed for members, sent
-- with Broadcast now and applied by the guild like the visibility. White where an officer set it; the buttons'
-- tooltip says what it does, its default and who set it
local function round(v, step) return math.floor(v / step + 0.5) * step end
-- (text and hint: Settings' own words for a rule, where the registry's, Rules.lua's, name a part that has moved)
function Col:Rule(name, text, hint)
  local R = C.Rules
  local t = R.TUNE_BY[name]
  if not t then return end
  local lo, hi, step = t[3], t[4], t[5]
  local officer = C.Roster:MeOfficer()
  local function set(v)
    v = round(v, step)
    if v < lo - 1e-9 or v > hi + 1e-9 then return end
    -- back at the default clears the officers' setting (an "x and nil or v" would always give v)
    if math.abs(v - R.RULES[name]) < 1e-9 then C.Policy:SetRule(name, nil) else C.Policy:SetRule(name, v) end
    C.Comm:PolicySoon()
    redraw()
  end
  local v = R.Get(name)
  self:Step(text or t[2], R.Show(name), R.SetBy(name) ~= nil,
    (officer and v > lo + 1e-9) and function() set(R.Get(name) - step) end or nil,
    (officer and v < hi - 1e-9) and function() set(R.Get(name) + step) end or nil,
    function(tip)
      tip:AddLine(text or t[2], 1, 1, 1)
      tip:AddLine(hint or t[7], 0.85, 0.85, 0.85, true)
      local by = R.SetBy(name)
      tip:AddLine("Default " .. R.Show(name, R.RULES[name]) .. (by and (". Set to " .. R.Show(name) .. " by " .. R.WhoName(by) .. ".") or "."), 0.7, 0.7, 0.7, true)
    end)
end
-- the officers' Broadcast now: the policy again, stamped now (Comm.lua M:Broadcast). A change goes on its own a few
-- seconds after it is made (M:PolicySoon)
local function broadcast() C.Comm:Broadcast() end
function Col:Broadcast() self:Buttons({ { "Broadcast now", C.Roster:MeOfficer(), broadcast } }) end
-- Save to Guild Info (Policy.lua P:Save, a click): the officers' policy where every client reads it and only the ranks
-- allowed to edit Guild Info can change it. Shown while there is a change to save or the guild has no line; the line
-- that would be written, and its length, in the band; why where it cannot be
local function save() C.Comm:SaveLine(); redraw() end
local function saveNote(officer, st, unsaved)
  local kept = type(C.Policy.line) == "table"
  if not officer then return kept and "Only officers can change it. Guild Info keeps it." or "Only officers can change it." end
  if unsaved then return st.ok and string.format("Unsaved. Cute's line: %d letters, Guild Info %d of %d bytes.", #st.line, #st.text, C.Policy.INFO_MAX) or st.why end
  return kept and "Kept in Guild Info: only ranks allowed to edit it can change it (keep Modify Guild Info to the officer ranks)." or "Saving waits for Guild Info to be read."
end
local function saveTip(st)
  return function(tip)
    tip:AddLine("Save to Guild Info", 1, 1, 1)
    tip:AddLine("Writes the policy as one line at the end of the guild's Guild Info, the guild's own text kept. Every client routes by it, and only ranks allowed to edit Guild Info can change it.", 0.85, 0.85, 0.85, true)
    if st.line then tip:AddLine(st.line, 0.7, 0.7, 0.7, true) end
    if st.why then tip:AddLine(st.why, 0.7, 0.7, 0.7, true) end
  end
end

-- one Everyone / Only-you pair; id is a stat's, or a category's ("gc" .. its id, "gc_" .. a discovered kind). A stat
-- the officers leave to Everyone that would tell members one they keep (Policy.lua P:KeptWith: Enchanted slots while
-- Missing enchants is theirs) shows Only you, greyed, with the one it goes with; it opens with that one. The label wraps
function Col:Pair(id, text, indent)
  self.fresh = false
  -- (an officer sets it once Guild Info has been read: Policy.lua P.Editable)
  local officer = C.Roster:MeOfficer() and C.Policy.Editable()
  indent = indent or 0
  local with = C.Policy:KeptWith(id)
  local fixed = C.Policy.Fixed(id)
  local lw = self.w - 136 - indent
  local s = text
  if with then s = text .. "  |cff8a8a8awith " .. C.Policy:Label(with) .. "|r"
  elseif fixed then s = text .. "  |cff8a8a8aalways|r" end
  local _, lh = label(self, self.x + indent, self.y + 4, lw, s, INK, nil, 13)
  local vis = with and "self" or C.Policy:Vis(id)
  local tip = with and function(t)
    t:AddLine(text, 1, 1, 1)
    t:AddLine("Kept to the officers while " .. C.Policy:Label(with) .. " is: a member could work it out from this.", 0.85, 0.85, 0.85, true)
  end or fixed and function(t)
    t:AddLine(text, 1, 1, 1)
    t:AddLine("Everyone, always: it says which officers take the Only-you values and what each member's Ready counts.", 0.85, 0.85, 0.85, true)
  end or nil
  with = with or (fixed and id) or nil
  -- (each box under the middle of its heading; a box alone, no row: the label is the stat's, left of both)
  for _, d in ipairs({ { "all", 96 }, { "self", 27 } }) do
    local cb = widgets.boxes:Get()
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", self.x + self.w - d[2], -self.y - 4)
    cb.label:SetText("")
    cb.statId, cb.vis = id, d[1]
    cb:Set(vis == d[1])
    cb:SetOn(officer and not with)
    cb.fn = function(b) if officer and not with then C.Policy:Set(id, d[1]); C.Comm:PolicySoon(); redraw() else b:Set(vis == d[1]) end end
    tipOn(cb, tip)
  end
  self.y = self.y + math.max(ROWH, lh + 7)
end
-- the two headings over the pairs, against the column's right edge
function Col:PairHeads()
  self.fresh = false
  label(self, self.x + self.w - 126, self.y, 60, "Everyone", DIM, "RIGHT", 11)
  label(self, self.x + self.w - 60, self.y, 60, "Only you", DIM, "RIGHT", 11)
  self.y = self.y + NOTE
end

-- a window's key: its label, the key box (a click, then a key: Keys.lua), "Follow the game's ... key" and Clear; under
-- it, in one dim line, what a hand-picked key did before (the game's Key Bindings name it) and a key the player gave
-- Cute's own binding in the game's Key Bindings
function Col:Key(w)
  self.fresh = false
  local K = C.Keys
  local _, lh = label(self, self.x, self.y + 4, 106, w.label, INK, nil, 13)
  local box = widgets.keys:Get()
  box:ClearAllPoints()
  box:SetPoint("TOPLEFT", self.x + 110, -self.y - 1)
  box:Bind(w.id)
  local follow = K.Get(w.id) == "follow"
  local text = "Follow the game's " .. w.game .. " key"
  local cw = math.min(self.w - 110 - box:GetWidth() - 8 - 64, 24 + measure(text, 13) + 4)
  local cb = widgets.checks:Get()
  sized(cb.label, 13)
  cb.label:ClearAllPoints()
  cb.label:SetPoint("TOPLEFT", 20, -4)
  cb.label:SetWidth(cw - 24)
  cb.label:SetWordWrap(true)
  cb.label:SetText(text)
  cb.label.cuteCut = nil
  local ch = heightOf(cb.label, 13)
  cb:ClearAllPoints()
  cb:SetPoint("TOPLEFT", self.x + 110 + box:GetWidth() + 8, -self.y)
  cb:SetSize(cw, math.max(ROWH, ch + 7))
  cb:Set(follow)
  cb:SetOn(true)
  cb.statId, cb.vis = nil, nil
  cb.fn = function(b) K.Set(w.id, b:GetChecked() and "follow" or false); redraw() end
  tipOn(cb, function(tip)
    tip:AddLine(text, 1, 1, 1)
    tip:AddLine("Ticked, the key the game has for its " .. w.game .. " opens Cute's window, and moves with it when you rebind the game's.", 0.85, 0.85, 0.85, true)
  end)
  local b = self.p.buttons:Get()
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", self.x + 110 + box:GetWidth() + 8 + cw + 6, -self.y - 1)
  b:SetSize(58, 20)
  b:SetLabel("Clear")
  b:SetOn(K.Get(w.id) ~= false and K.Get(w.id) ~= nil)
  b:SetScript("OnClick", C.Safe(function() K.Set(w.id, false); redraw() end, "settings: clear a key"))
  tipOn(b, function(tip) tip:AddLine("Clear", 1, 1, 1); tip:AddLine("No key opens Cute's window; the game's own key opens the game's window again.", 0.85, 0.85, 0.85, true) end)
  self.y = self.y + math.max(ROWH + 4, lh + 8, ch + 9)
  local under = K.Words(w.id)
  if under then
    local _, nh = label(self, self.x + 110, self.y - 2, self.w - 110, under, DIM, nil, 11)
    self.y = self.y + nh + 2
  end
end
-- a key set in the game's Key Bindings alone (Settings, Move frames): its name, the key the game reports, and where
-- it is set
function Col:KeyNote(text, key)
  self.fresh = false
  local _, lh = label(self, self.x, self.y + 4, 106, text, INK, nil, 13)
  local v = self.p.values:Get()
  v:ClearAllPoints()
  v:SetPoint("TOPLEFT", self.x + 110, -self.y - 5)
  sized(v, 12)
  v:SetWidth(76)
  v:SetJustifyH("LEFT")
  v:SetWordWrap(false)
  color(v, MUTE)
  C.UI.FitText(v, key or "-", 76)
  local _, nh = label(self, self.x + 190, self.y + 5, self.w - 190, "set in the game's Key Bindings, Cute", DIM, nil, 11)
  self.y = self.y + math.max(ROWH, lh + 7, nh + 9)
end

----------------------------------------------------------------------------
-- the core's sections
----------------------------------------------------------------------------
local function drawGeneral(col)
  local s, ch = C.Settings(), C.Char()
  col:Head("Display")
  col:Check("Show offline members", s.offline, true, function(on) s.offline = on; C.UI:Refresh() end)
  col:Check("Minimap button", s.minimap, true, function(on) s.minimap = on; C.UI:OnWorld() end)
  col:Check("Compact rows", s.density == "compact", true, function(on) s.density = on and "compact" or "normal"; C.UI:Refresh() end)
  col:Head("About you")
  -- (a main's name may be two words on Forever; letters of any language kept, Stats.lua's CleanText)
  local function main(v) s.main = (C.Stats.CleanText and C.Stats.CleanText(v, 24)) or (v:gsub("[^%w%- ]", "")):sub(1, 24); C.Sample:Read("main") end
  col:Edit("Main character", function() return s.main end, main)
  -- (a role may be none: its ticked option clicked again clears it)
  col:Choice("Role", { "Tank", "Heal", "Melee", "Ranged" }, ch.role, function(role) ch.role = role; C.Sample:Read("role") end, true)
  col:Check("Raid spec set (this character)", ch.raidspec == true, true, function(on) ch.raidspec = on and true or nil; C.Sample:Read("raid_spec") end)
end

-- the keys that open Cute's windows, per character, by override bindings that follow the game's own (Keys.lua)
local function drawKeys(col)
  col:Head("Keys")
  for _, w in ipairs(C.Keys.Windows()) do col:Key(w) end
  col:KeyNote("Settings", C.Keys.BindingText("CUTE_SETTINGS"))
  col:KeyNote("Move frames", C.Keys.BindingText("CUTE_LAYOUT"))
  col:Note("Cleared, the game's own key opens the game's window again.")
end

-- the pieces on screen: their one lock, the grid, layout mode and the resets (Layout.lua)
local function drawLayout(col) C.Layout.Draw(col) end

-- who sees what: the policy, the threshold, the buttons and the two headings in the band, the list under them. A
-- member reads one line of it: the officers decide, and how many values go to everyone
local function drawVisibility(col, officer, ui)
  if not officer then
    local all, kept = 0, 0
    for _, cat in ipairs(C.Stats.CATS) do
      if cat ~= "game" then
        for _, def in ipairs(C.Stats.byCat[cat]) do if C.Policy:Route(def.id) == "self" then kept = kept + 1 else all = all + 1 end end
      end
    end
    col:Head("Who sees what")
    col:Note(string.format("The officers decide who sees what: %d values go to everyone, %d to the officers alone. The Me page shows yours as members see them.", all, kept))
    col:Note(C.Policy:Describe())
    return
  end
  local band = column(col.x, col.w, true, ui)
  band:Head("Policy")
  band:Note(C.Policy:Describe())
  local unsaved = officer and C.Policy:Unsaved()
  local st = unsaved and C.Policy:SaveState() or {}
  band:Note(saveNote(officer, st, unsaved))
  band:Note("Only you: whispered to the officers online, never sent to members.")
  local thr = C.Policy:Threshold()
  -- (never above your own rank: only the guild master takes them down to the guild master alone; and only once Guild
  -- Info has been read)
  local mine = C.Roster:MyRank() or 99
  local editor = officer and C.Policy.Editable()
  band:Step("Officer ranks: the ranks that see every value and set this list", "0 to " .. thr, false,
    (editor and thr > 0 and thr - 1 >= mine) and function() C.Policy:SetThreshold(thr - 1); C.Comm:PolicySoon(); redraw() end or nil,
    (editor and thr < 9) and function() C.Policy:SetThreshold(thr + 1); C.Comm:PolicySoon(); redraw() end or nil,
    function(tip)
      tip:AddLine("Officer ranks", 1, 1, 1)
      tip:AddLine("The guild's ranks, from the guild master down, that see every value and set this list and the rules.", 0.85, 0.85, 0.85, true)
      if officer and thr - 1 < mine and thr > 0 then tip:AddLine("It cannot leave your own rank out: an officer of a higher rank can lower it.", 0.7, 0.7, 0.7, true) end
    end)
  band:Buttons({ { "Save to Guild Info", unsaved and st.ok, save, saveTip(st) }, { "Broadcast now", officer, broadcast }, { "Reset to defaults", editor, function()
    -- (the visibility only: the rules' thresholds go back to theirs in their own sections, the untrusted on the
    -- Officers page)
    C.Policy:Reset()
    C.Comm:PolicySoon()
    redraw()
  end } })
  band:PairHeads()
  ui:SetBand(band.y)
  for _, cat in ipairs(C.Stats.CATS) do
    col:Head(C.Stats.CAT_LABEL[cat])
    if cat == "game" then
      -- what the guild discovers, per category, set before anything is found in it as well as after
      col:Note("Discovered in play; a category's choice covers what is found in it.")
      for _, f in ipairs(C.Stats.FOUND) do col:Pair("gc_" .. f[1], f[2]) end
      -- the game's statistics are set per category: a category's choice covers every statistic in it, a child's
      -- its parent's unless set
      if #C.Stats.byCat.game == 0 then col:Note(C.Stats.gameNote or "No statistics on this client.")
      else
        col:Note("Per category; a category's choice covers its statistics.")
        col:Note("A statistic may count what a stat of Cute's own counts (deaths, quests): set both.")
        for _, g in ipairs(C.Stats.game.cats) do
          if #g.stats > 0 then col:Pair("gc" .. g.id, g.name, g.parent ~= -1 and 14 or 0) end
        end
      end
    else
      for _, def in ipairs(C.Stats.byCat[cat]) do col:Pair(def.id, def.label) end
    end
  end
end

-- the rules the guild learns by, and the two the dungeon pick reads (the Guide's, before the quests window had it)
local function drawRules(col, officer)
  local R = C.Rules
  col:Head("What the guild learns")
  col:Note(officer and "White: set by an officer. A change goes to the guild on its own." or "White: set by an officer. Only officers can change them.")
  for _, t in ipairs(R.TUNE) do if not t[8] then col:Rule(t[1]) end end
  -- (the retired Guide's two, read now by the Quests tab's dungeon pick: their words here, the registry's as the core has
  -- them)
  col:Head("Dungeons and gear")
  col:Rule("guideWindow", "Members near your level (levels)", "The dungeon pick names the guild mates online in a dungeon's range within this many levels of yours; for officers, where most members are, over twice as many.")
  col:Rule("guideAhead", "Dungeons ahead (levels)", "The dungeon pick names the next dungeon to open within this many levels of yours.")
  col:Buttons({ { "Broadcast now", officer, broadcast }, { "Rules to defaults", officer, function()
    for _, t in ipairs(R.TUNE) do if R.SetBy(t[1]) then C.Policy:SetRule(t[1], nil) end end
    C.Comm:PolicySoon()
    redraw()
  end } })
end

-- the guild window's columns and cards: each page's list under its name (Officers for officers alone)
local function drawColumns(col, officer, ui)
  for _, def in ipairs(C.Modules.list) do
    if def.core and def.settings and (not def.officer or officer) then C.Safe(function() def.settings(ui, col) end, "settings: " .. def.id)() end
  end
end

-- the modules this character runs: the always-on base (the guild window; a module addon's base, the quests window
-- with its Route tab) greyed, then a box each for the rest, a quests window's tabs indented under it. A change waits:
-- the boxes show it at once, the band line says it applies on reload (Reload now, Undo), and closing Settings asks
-- (Setup.lua); a few words on the right where something is not as the box says, its notes in the tooltip
local function drawModules(col, officer)
  local M = C.Modules
  col:Head("Modules")
  if M.Staged() then
    col:Note("Applies on reload.")
    col:Buttons({ { "Reload now", not M.InCombat(), function() M.Commit() end, function(tip) tip:AddLine("Reload now", 1, 1, 1); tip:AddLine(M.InCombat() and "After combat." or "Reloads the interface with your changes.", 0.85, 0.85, 0.85, true) end },
      { "Undo", true, function() M.Undo(); redraw() end } })
  end
  col:Check("Guild", true, false, function() end, "always")
  local list = M.Available(officer)
  local base, rest = {}, {}
  for _, e in ipairs(list) do if e.base then base[#base + 1] = e else rest[#rest + 1] = e end end
  if #base > 0 then
    local names = {}
    for _, e in ipairs(base) do names[#names + 1] = e.title end
    col:Check(table.concat(names, " and "), true, false, function() end, "always")
  end
  for _, e in ipairs(rest) do
    local tab = e.def and e.def.page and e.def.window == "quests"
    local on = M.StagedOn(e.key, e.on)
    col:Check(e.title .. (tab and " tab" or ""), on, true, function(v) M.Stage(e.key, v); redraw() end, e.status, function(tip)
      tip:AddLine(e.title, 1, 1, 1)
      if e.notes then tip:AddLine(e.notes, 0.85, 0.85, 0.85, true) end
      if e.status then tip:AddLine(e.status, 0.7, 0.7, 0.7, true) end
      tip:AddLine("A change applies on reload.", 0.5, 0.5, 0.5, true)
    end, tab and 20 or 0)
  end
  col:Note("Window and tab changes apply on reload.")
end

-- the sections, by group: { id, title, group, order, draw(col, officer, ui), officers (officers alone), module }
local CORE = {
  { id = "general", title = "General", group = "cute", order = 1, draw = drawGeneral },
  { id = "keys", title = "Keys", group = "cute", order = 2, draw = drawKeys },
  { id = "layout", title = "Layout", group = "cute", order = 3, draw = drawLayout },
  { id = "modules", title = "Modules", group = "cute", order = 4, draw = drawModules },
  { id = "columns", title = "Columns", group = "guild", order = 10, draw = drawColumns },
  { id = "vis", title = "Who sees what", group = "guild", order = 11, draw = drawVisibility },
  { id = "rules", title = "Rules", group = "guild", order = 12, officers = true, draw = drawRules },
}
local GROUPS = { { "cute", "Cute" }, { "guild", "Guild" }, { "quests", "Quests" } }
-- a section a module addon adds without a module of its own (Cute.AddSection): { id, title, group, order,
-- draw = function(ui, col), shown = function() return bool end }
function ST.Add(def)
  if type(def) ~= "table" or type(def.id) ~= "string" or type(def.draw) ~= "function" then return false end
  for i, d in ipairs(ST.extra) do if d.id == def.id then table.remove(ST.extra, i) end end
  ST.extra[#ST.extra + 1] = def
  return true
end
-- the sections for this viewer, each with its group, in the groups' order and then their own
function ST.Sections(officer)
  local out = {}
  for _, s in ipairs(CORE) do if not s.officers or officer then out[#out + 1] = s end end
  for _, m in ipairs(C.Modules.Sections(officer)) do
    if not m.core then
      out[#out + 1] = { id = m.id, title = m.title, module = m, order = m.order or 100,
        group = m.group or ((m.window == "quests") and "quests") or "guild" }
    end
  end
  for _, d in ipairs(ST.extra) do
    if not d.shown or d.shown() then out[#out + 1] = { id = d.id, title = d.title, extra = d, order = d.order or 100, group = d.group or "cute" } end
  end
  local rank = {}
  for i, g in ipairs(GROUPS) do rank[g[1]] = i end
  table.sort(out, function(a, b)
    local ga, gb = rank[a.group] or 9, rank[b.group] or 9
    if ga ~= gb then return ga < gb end
    if a.order ~= b.order then return a.order < b.order end
    return a.id < b.id
  end)
  return out
end

local function resetAll() for _, k in ipairs(POOLS) do widgets[k]:Reset() end end
local function hideRest() for _, k in ipairs(POOLS) do widgets[k]:HideRest() end end

-- a click that changes what the section shows draws it again
function ST.Redraw()
  local win = C.UI.windows.settings
  if win and win.frame and win.frame:IsShown() then win:Draw() end
end

-- the open section's 2 px bar in its category's colour (the design's section 7): QUEST for the quest sections, GROUP for
-- Dungeons and gear, NEW for Data you share, WHITE for the rest (UI.COLORS: bars only, never text)
local function barColor(sec)
  local K = C.UI.COLORS
  if sec.id == "dungeons" then return K.GROUP end
  if sec.id == "share" then return K.NEW end
  if sec.group == "quests" then return K.QUEST end
  return K.WHITE
end
function C.Settings_Draw(ui)
  ensure(ui)
  resetAll()
  local sf = ui.scroll
  local officer = C.Roster:MeOfficer()
  local sections = ST.Sections(officer)
  local sel
  for _, s in ipairs(sections) do if s.id == ui.section then sel = s end end
  sel = sel or sections[1]
  ui.section = sel.id
  ui:SetInset(NAV_W + NAV_GAP)
  -- the list of sections under their group heads, the open one white with the bar beside it; rows 22 px and heads
  -- 20 px at any size, scrolling past the window's height
  nav:Show()
  local y, group = 0, nil
  for _, s in ipairs(sections) do
    if s.group ~= group then
      group = s.group
      local name
      for _, g in ipairs(GROUPS) do if g[1] == group then name = g[2] end end
      local h = widgets.navHeads:Get()
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", 10, -(y + 5))
      h:SetWidth(NAV_W - 14)
      h:SetText(name or "")
      y = y + NAV_HEAD
    end
    local r = widgets.navLines:Get()
    local open = s == sel
    r.cat, r.def, r.member = nil, nil, nil
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, -y)
    r:SetWidth(NAV_W)
    r:SetHeight(NAV_ROW)
    r.bg:SetColorTexture(1, 1, 1, open and 0.06 or 0)
    r.bar:SetShown(open)
    local bc = barColor(s)
    r.bar:SetColorTexture(bc[1], bc[2], bc[3], 1)
    r.name:ClearAllPoints()
    r.name:SetPoint("LEFT", 12, 0)
    r.name:SetWidth(NAV_W - 16)
    color(r.name, open and WHITE or INK)
    C.UI.FitText(r.name, s.title, NAV_W - 20)
    r.val:Hide()
    r.who:Hide()
    r.section = s.id
    r.fn = function() C.UI.OpenSettings(s.id) end
    r.tip = function(tip)
      tip:AddLine(s.title, 1, 1, 1)
      if s.officers then tip:AddLine("Set by the officers for the guild.", 0.7, 0.7, 0.7, true)
      elseif s.module and s.module.notes then tip:AddLine(s.module.notes, 0.7, 0.7, 0.7, true) end
    end
    y = y + NAV_ROW
  end
  nav.list:SetContentHeight(y + 4)
  nav.rows = y
  -- the chosen section, in one column
  local w = math.min(COL_MAX, sf:Width() - 12)
  local col = column(6, w, false, ui)
  C.Safe(function()
    if sel.module then sel.module.settings(ui, col)
    elseif sel.extra then sel.extra.draw(ui, col)
    else sel.draw(col, officer, ui) end
  end, "settings: " .. sel.id)()
  hideRest()
  sf:SetContentHeight(col.y + 8)
end
