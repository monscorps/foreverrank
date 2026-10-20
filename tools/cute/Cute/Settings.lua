-- SPDX-License-Identifier: GPL-3.0-or-later
-- Settings: the sections down the left, the chosen one on the right in one column, drawn flat like the rest. Every
-- section draws with the column below (a heading, a note, a check box, a step down and up, a row of buttons, a text
-- box, a choice of one) and starts with a heading, so the spacing is the same everywhere and a module's section looks
-- like the core's.
--   General        display (offline members, the minimap button, compact rows); about you (your main, account-wide;
--                  role and raid spec, this character's)
--   Who sees what  per stat, Everyone or Only you (per category for the game's statistics and for what the guild
--                  discovers), the officer rank threshold, Save to Guild Info, Broadcast now and Reset to defaults: the
--                  officers' to set, greyed for members. The policy, the threshold, the buttons and the two headings
--                  stay in the band while the list scrolls
--   Rules          the thresholds of the rules the guild learns by (Rules.lua), each a step down or up: the officers'
--   Modules        the built-in modules and the module addons the client lists, switched on and off for this
--                  character (Modules.lua)
--   then one section per module that is on and has settings, in the modules' order: the dashboard's pages (their
--   columns and cards; the Officers page's for officers only), the Guide's thresholds, a module addon's own
local _, C = ...
local ST = {}
C.SettingsPage = ST

local WHITE = { 0.96, 0.96, 0.96 }
local INK = { 0.86, 0.86, 0.86 }
local DIM = { 0.58, 0.58, 0.58 }
local MUTE = { 0.52, 0.52, 0.52 }

local NAV_W = 168   -- the list of sections
local NAV_GAP = 12  -- between it and the column
local COL_MAX = 540 -- the column: wider, a label and its boxes read as two things far apart
-- the column's spacing, the same in every section
local HEAD, NOTE, ROWH, STEP, BTNS, GAP, BTN_GAP = 20, 18, 20, 24, 28, 10, 6

local widgets = {}
local nav

local function pool(parent, make)
  local p = { items = {}, used = 0 }
  function p:Get()
    self.used = self.used + 1
    local it = self.items[self.used]
    if not it then it = make(parent); self.items[self.used] = it end
    it:Show()
    return it
  end
  function p:Reset() self.used = 0 end
  function p:HideRest() for i = self.used + 1, #self.items do self.items[i]:Hide() end end
  return p
end
local POOLS = { "checks", "boxes", "labels", "values", "buttons", "edits", "navLines" }

local function ensure(ui)
  if widgets.checks then return end
  local parent = ui.scroll.child
  -- (a check with a label is a row button, ticked by a click anywhere on it: UI.lua checkRow; a box alone, the
  -- Everyone / Only-you pairs, is a check box)
  widgets.checks = pool(parent, function(p) return C.UI.CheckRow(p) end)
  widgets.boxes = pool(parent, function(p) return C.UI.Check(p) end)
  widgets.labels = pool(parent, function(p) return C.UI.Text(p, 12, INK, "LEFT", 300) end)
  -- (a step's value, right-aligned against its buttons, apart from its label so a narrow window cuts the label and
  -- never the number)
  widgets.values = pool(parent, function(p) return C.UI.Text(p, 12, INK, "RIGHT", 44) end)
  widgets.buttons = pool(parent, function(p) return C.UI.Button(p, "", 140) end)
  widgets.edits = pool(parent, function(p)
    local e = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    e:SetSize(140, 20)
    e:SetAutoFocus(false)
    e:SetMaxLetters(24)
    e:SetFont(C.UI.FONT, 12, "")
    return e
  end)
  -- the list of sections: a frame of its own beside the scroll area, so it stays while a long section scrolls
  nav = CreateFrame("Frame", nil, ui.content)
  nav:SetPoint("TOPLEFT", 8, -8)
  nav:SetPoint("BOTTOMLEFT", 8, 24)
  nav:SetWidth(NAV_W)
  widgets.navLines = pool(nav, function(p) return ui:MakeLine(p) end)
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
local function column(x, w, band)
  local ui = C.UI
  local p = band and { labels = ui.bandLabels, values = ui.bandLabels, buttons = ui.bandButtons }
    or { labels = widgets.labels, values = widgets.values, buttons = widgets.buttons }
  return setmetatable({ x = x, w = w, y = 4, fresh = true, p = p }, Col)
end
local function label(col, x, y, w, s, c, justify)
  local l = col.p.labels:Get()
  l:ClearAllPoints()
  l:SetPoint("TOPLEFT", x, -y)
  l:SetWidth(w)
  l:SetJustifyH(justify or "LEFT")
  color(l, c)
  C.UI.FitText(l, s, w - 4)
  return l
end
-- a heading, white; a gap above it unless it is the first thing in the column
function Col:Head(s)
  if not self.fresh then self.y = self.y + GAP end
  self.fresh = false
  label(self, self.x, self.y, self.w, s, WHITE)
  self.y = self.y + HEAD
end
-- a line of explanation, dim
function Col:Note(s)
  self.fresh = false
  label(self, self.x, self.y, self.w, s, DIM)
  self.y = self.y + NOTE
end
-- a check row: the box with its label, one button the width of the column (up to the right-hand words), so a click
-- anywhere on the row ticks it; right: a few dim words at the row's end; tip: function(tooltip) for its tooltip
function Col:Check(text, on, enabled, fn, right, tip)
  self.fresh = false
  local cb = widgets.checks:Get()
  cb:ClearAllPoints()
  cb:SetPoint("TOPLEFT", self.x, -self.y)
  local room = self.w - (right and 186 or 0)
  cb:SetWidth(room)
  cb.label:SetWidth(room - 24)
  C.UI.FitText(cb.label, text, room - 28)
  cb:Set(on and true or false)
  cb:SetOn(enabled ~= false)
  cb.statId, cb.vis = nil, nil
  cb.fn = function(b)
    if enabled == false then b:Set(on and true or false) return end
    fn(b:GetChecked())
  end
  tipOn(cb, tip)
  if right then label(self, self.x + self.w - 180, self.y + 3, 180, right, MUTE, "RIGHT") end
  self.y = self.y + ROWH
  return cb
end
-- a choice of one among a few, in a row after its label (unticking the chosen one chooses none): each option a short
-- check row, box and word
function Col:Choice(text, options, current, fn)
  self.fresh = false
  label(self, self.x, self.y + 2, 90, text, DIM)
  local cx = self.x + 92
  for _, opt in ipairs(options) do
    local cb = widgets.checks:Get()
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", cx, -self.y)
    cb:SetWidth(64)
    cb.label:SetWidth(44)
    C.UI.FitText(cb.label, opt, 42)
    cb:Set(current == opt)
    cb:SetOn(true)
    cb.statId, cb.vis = nil, nil
    cb.fn = function(b) fn(b:GetChecked() and opt or "") end
    tipOn(cb, nil)
    cx = cx + 66
  end
  self.y = self.y + ROWH
end
-- a text box after its label: get gives what it shows, set takes what was typed (Enter, or leaving the box); a redraw
-- while you type leaves your typing alone
function Col:Edit(text, get, set)
  self.fresh = false
  label(self, self.x, self.y + 3, 90, text, DIM)
  local e = widgets.edits:Get()
  e:ClearAllPoints()
  e:SetPoint("TOPLEFT", self.x + 100, -self.y)
  e:SetWidth(math.min(160, self.w - 104))
  if not e:HasFocus() then e:SetText(get() or "") end
  e:SetScript("OnEnterPressed", function(b) set(b:GetText() or ""); b:ClearFocus() end)
  e:SetScript("OnEscapePressed", function(b) b:SetText(get() or ""); b:ClearFocus() end)
  e:SetScript("OnEditFocusLost", function(b) set(b:GetText() or "") end)
  self.y = self.y + STEP
end
-- a value with a step down and up: the label, the value right-aligned against the buttons at the column's right edge,
-- both white where white is true; down and up nil where that step is shut (greyed); tip, the buttons' tooltip
function Col:Step(text, value, white, down, up, tip)
  self.fresh = false
  local x, w = self.x, self.w
  label(self, x, self.y + 3, w - 140, text, white and WHITE or INK)
  local val = self.p.values:Get()
  val:ClearAllPoints()
  val:SetPoint("TOPLEFT", x + w - 134, -self.y - 3)
  val:SetWidth(44)
  val:SetJustifyH("RIGHT")
  color(val, white and WHITE or INK)
  C.UI.FitText(val, value, 42)
  for i, d in ipairs({ { "-", down }, { "+", up } }) do
    local b = self.p.buttons:Get()
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", x + w - 84 + (i - 1) * 44, -self.y)
    b:SetWidth(40)
    b:SetLabel(d[1])
    b:SetOn(d[2] ~= nil)
    b:SetScript("OnClick", function() if d[2] then d[2]() end end)
    tipOn(b, tip)
  end
  self.y = self.y + STEP
end
-- a row of buttons, { label, enabled, fn, tip } each, 150 px, left to right, a little apart from the rows above; tip:
-- function(tooltip) for its tooltip
function Col:Buttons(list)
  if not self.fresh then self.y = self.y + BTN_GAP end
  self.fresh = false
  local bx = self.x
  for _, d in ipairs(list) do
    local b = self.p.buttons:Get()
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", bx, -self.y - 2)
    b:SetWidth(150)
    b:SetLabel(d[1])
    b:SetOn(d[2] and true or false)
    b:SetScript("OnClick", function() if d[2] then d[3]() end end)
    tipOn(b, d[4])
    bx = bx + 156
  end
  self.y = self.y + BTNS
end

-- a rule's threshold (Rules.lua): its value and a step down and up, the officers' to set and greyed for members, sent
-- with Broadcast now and applied by the guild like the visibility. White where an officer set it; the buttons'
-- tooltip says what it does, its default and who set it
local function round(v, step) return math.floor(v / step + 0.5) * step end
function Col:Rule(name, text)
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
    C.UI:Draw()
  end
  local v = R.Get(name)
  self:Step(text or t[2], R.Show(name), R.SetBy(name) ~= nil,
    (officer and v > lo + 1e-9) and function() set(R.Get(name) - step) end or nil,
    (officer and v < hi - 1e-9) and function() set(R.Get(name) + step) end or nil,
    function(tip)
      tip:AddLine(t[2], 1, 1, 1)
      tip:AddLine(t[7], 0.85, 0.85, 0.85, true)
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
local function save() C.Comm:SaveLine(); C.UI:Draw() end
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
-- Missing enchants is theirs) shows Only you, greyed, with the one it goes with; it opens with that one
function Col:Pair(id, text, indent)
  self.fresh = false
  -- (an officer sets it once Guild Info has been read: Policy.lua P.Editable)
  local officer = C.Roster:MeOfficer() and C.Policy.Editable()
  indent = indent or 0
  local with = C.Policy:KeptWith(id)
  local fixed = C.Policy.Fixed(id)
  local lw = self.w - 136 - indent
  if with then
    label(self, self.x + indent, self.y + 3, lw, text .. "  |cff8a8a8awith " .. C.Policy:Label(with) .. "|r", INK)
  elseif fixed then
    label(self, self.x + indent, self.y + 3, lw, text .. "  |cff8a8a8aalways|r", INK)
  else
    label(self, self.x + indent, self.y + 3, lw, text, INK)
  end
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
    cb:SetPoint("TOPLEFT", self.x + self.w - d[2], -self.y - 3)
    cb.label:SetText("")
    cb.statId, cb.vis = id, d[1]
    cb:Set(vis == d[1])
    cb:SetOn(officer and not with)
    cb.fn = function(b) if officer and not with then C.Policy:Set(id, d[1]); C.Comm:PolicySoon(); C.UI:Draw() else b:Set(vis == d[1]) end end
    tipOn(cb, tip)
  end
  self.y = self.y + ROWH
end
-- the two headings over the pairs, against the column's right edge
function Col:PairHeads()
  self.fresh = false
  label(self, self.x + self.w - 126, self.y, 60, "Everyone", DIM, "RIGHT")
  label(self, self.x + self.w - 60, self.y, 60, "Only you", DIM, "RIGHT")
  self.y = self.y + NOTE
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
  -- (a main's name may be two words on Forever)
  local function main(v) s.main = (v:gsub("[^%w%- ]", "")):sub(1, 24); C.Sample:Read("main") end
  col:Edit("Main character", function() return s.main end, main)
  col:Choice("Role", { "Tank", "Heal", "Melee", "Ranged" }, ch.role, function(role) ch.role = role; C.Sample:Read("role"); C.UI:Draw() end)
  col:Check("Raid spec set (this character)", ch.raidspec == true, true, function(on) ch.raidspec = on and true or nil; C.Sample:Read("raid_spec") end)
end

-- who sees what: the policy, the threshold, the buttons and the two headings in the band, the list under them
local function drawVisibility(col, officer, ui)
  local band = column(col.x, col.w, true)
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
  band:Step("Officer ranks", "0 to " .. thr, false,
    (editor and thr > 0 and thr - 1 >= mine) and function() C.Policy:SetThreshold(thr - 1); C.Comm:PolicySoon(); C.UI:Draw() end or nil,
    (editor and thr < 9) and function() C.Policy:SetThreshold(thr + 1); C.Comm:PolicySoon(); C.UI:Draw() end or nil,
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
    C.UI:Draw()
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

-- the rules the guild learns by (a module's own, the Guide's, are in its section)
local function drawRules(col, officer)
  local R = C.Rules
  col:Head("Thresholds")
  col:Note(officer and "White: set by an officer. A change goes to the guild on its own." or "White: set by an officer. Only officers can change them.")
  for _, t in ipairs(R.TUNE) do if not t[8] then col:Rule(t[1]) end end
  col:Buttons({ { "Broadcast now", officer, broadcast }, { "Rules to defaults", officer, function()
    for _, t in ipairs(R.TUNE) do if not t[8] and R.SetBy(t[1]) then C.Policy:SetRule(t[1], nil) end end
    C.Comm:PolicySoon()
    C.UI:Draw()
  end } })
end

-- the modules this character runs: a box each, a few words where it is not as the box says, its notes in the tooltip
local function drawModules(col, officer)
  col:Head("On for this character")
  col:Note("Each adds its page and its own section here.")
  for _, e in ipairs(C.Modules.Available(officer)) do
    col:Check(e.title, e.on, true, function(on) C.Modules.Set(e.key, on) end, e.status, function(tip)
      tip:AddLine(e.title, 1, 1, 1)
      if e.notes then tip:AddLine(e.notes, 0.85, 0.85, 0.85, true) end
      if e.status then tip:AddLine(e.status, 0.7, 0.7, 0.7, true) end
      if e.addon then tip:AddLine("The addon " .. e.key .. (e.addon.lod and ", loaded when switched on." or "."), 0.5, 0.5, 0.5, true) end
    end)
  end
end

-- (officers: set by the officers, greyed for members)
local CORE = {
  { id = "general", title = "General", draw = drawGeneral },
  { id = "vis", title = "Who sees what", officers = true, draw = drawVisibility },
  { id = "rules", title = "Rules", officers = true, draw = drawRules },
  { id = "modules", title = "Modules", draw = drawModules },
}
-- the sections for this viewer: the core's, then each module's that is on, in the modules' order
function ST.Sections(officer)
  local out = {}
  for _, s in ipairs(CORE) do out[#out + 1] = s end
  for _, m in ipairs(C.Modules.Sections(officer)) do out[#out + 1] = { id = m.id, title = m.title, module = m } end
  return out
end

local function resetAll() for _, k in ipairs(POOLS) do widgets[k]:Reset() end end
local function hideRest() for _, k in ipairs(POOLS) do widgets[k]:HideRest() end end

function C.Settings_Draw(ui)
  ensure(ui)
  widgets.shown = true
  resetAll()
  local sf = ui.scroll
  local officer = C.Roster:MeOfficer()
  local sections = ST.Sections(officer)
  local sel
  for _, s in ipairs(sections) do if s.id == ui.section then sel = s end end
  sel = sel or sections[1]
  ui.section = sel.id
  ui:SetInset(NAV_W + NAV_GAP)
  -- the list of sections, the open one white with the bar beside it, as the Statistics page's categories
  nav:Show()
  local NROW = C.UI.ROW
  for i, s in ipairs(sections) do
    local r = widgets.navLines:Get()
    local open = s == sel
    r.cat, r.def, r.member = nil, nil, nil
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, -(i - 1) * NROW)
    r:SetWidth(NAV_W)
    r:SetHeight(NROW)
    r.bg:SetColorTexture(1, 1, 1, open and 0.06 or (i % 2 == 0 and 0.03 or 0))
    r.bar:SetShown(open)
    r.bar:SetColorTexture(WHITE[1], WHITE[2], WHITE[3], 1)
    r.name:SetPoint("LEFT", 8, 0)
    r.name:SetWidth(NAV_W - 70)
    color(r.name, open and WHITE or INK)
    C.UI.FitText(r.name, s.title, NAV_W - 74)
    if s.officers then
      r.val:Show()
      r.val:SetPoint("RIGHT", -6, 0)
      r.val:SetWidth(56)
      color(r.val, MUTE)
      r.val:SetText("officers")
    else r.val:Hide() end
    r.who:Hide()
    r.section = s.id
    r.fn = function() C.UI:Open("settings", s.id) end
    r.tip = function(tip)
      tip:AddLine(s.title, 1, 1, 1)
      if s.officers then tip:AddLine(officer and "Set by the officers for the guild." or "Set by the officers; only they can change it.", 0.7, 0.7, 0.7, true)
      elseif s.module and s.module.notes then tip:AddLine(s.module.notes, 0.7, 0.7, 0.7, true) end
    end
  end
  -- the chosen section, in one column
  local w = math.min(COL_MAX, sf:Width() - 12)
  local col = column(6, w)
  C.Safe(function()
    if sel.module then sel.module.settings(ui, col) else sel.draw(col, officer, ui) end
  end, "settings: " .. sel.id)()
  hideRest()
  sf:SetContentHeight(col.y + 8)
end

function C.Settings_Hide(ui)
  if not widgets.shown then return end
  widgets.shown = false
  resetAll()
  hideRest()
  nav:Hide()
  if ui then ui:SetInset(0) end
end
