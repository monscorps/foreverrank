-- SPDX-License-Identifier: GPL-3.0-or-later
-- Settings, drawn inside the window's scroll area, flat like the rest.
--   Everyone:  which columns each page shows, density, offline members, the minimap button, your main, role and
--              raid spec (role and raid spec per character, the main account-wide)
--   Officers:  per stat, Everyone or Only you (per category for the game's statistics and for what the guild
--              discovers: bosses, dungeons, raids, reputation); the officer rank threshold; the thresholds of the
--              rules the Guide learns by (Rules.lua), each a step down or up; Broadcast now (greyed for members)
local _, C = ...
local ST = {}
C.SettingsPage = ST

local WHITE = { 0.96, 0.96, 0.96 }
local INK = { 0.86, 0.86, 0.86 }
local DIM = { 0.58, 0.58, 0.58 }
local MUTE = { 0.38, 0.38, 0.38 }
local ROWH = 20

local widgets = {}

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

local function ensure(parent)
  if widgets.checks then return end
  widgets.checks = pool(parent, function(p) return C.UI.Check(p) end)
  widgets.labels = pool(parent, function(p) return C.UI.Text(p, 12, INK, "LEFT", 300) end)
  -- (a rule's value, right-aligned against its step buttons, apart from its label so a narrow window cuts the label
  -- and never the number)
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
end
local function color(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

local PAGES = { { "race", "Race columns" }, { "prog", "Prog columns" }, { "shame", "Hall of Shame cards" }, { "officers", "Officers columns" } }

-- the left half: everyone's choices
local function drawEveryone(x, w)
  local s, ch = C.Settings(), C.Char()
  local y = 4
  local function head(label)
    local l = widgets.labels:Get()
    l:SetPoint("TOPLEFT", x, -y)
    l:SetWidth(w)
    color(l, WHITE)
    l:SetText(label)
    y = y + 20
  end
  local function check(label, on, enabled, fn)
    local cb = widgets.checks:Get()
    cb:SetPoint("TOPLEFT", x, -y - 3)
    cb.label:SetWidth(w - 26)
    C.UI.FitText(cb.label, label, w - 30)
    cb:Set(on and true or false)
    cb:SetOn(enabled ~= false)
    cb.fn = function(self) fn(self:GetChecked()) end
    y = y + ROWH
  end
  head("Display")
  check("Show offline members", s.offline, true, function(on) s.offline = on; C.UI:Refresh() end)
  check("Minimap button", s.minimap, true, function(on) s.minimap = on; C.UI:OnWorld() end)
  check("Compact rows", s.density == "compact", true, function(on) s.density = on and "compact" or "normal"; C.UI:Refresh() end)
  y = y + 6
  head("About you")
  local l = widgets.labels:Get()
  l:SetPoint("TOPLEFT", x, -y - 3)
  l:SetWidth(90)
  color(l, DIM)
  l:SetText("Main character")
  local e = widgets.edits:Get()
  e:SetPoint("TOPLEFT", x + 100, -y)
  e:SetWidth(math.min(160, w - 104))
  -- a redraw while you type leaves your typing alone; a main's name may be two words on Forever
  if not e:HasFocus() then e:SetText(s.main or "") end
  e:SetScript("OnEnterPressed", function(self) s.main = (self:GetText() or ""):gsub("[^%w%- ]", ""):sub(1, 24); self:ClearFocus(); C.Sample:Read("main") end)
  e:SetScript("OnEscapePressed", function(self) self:SetText(s.main or ""); self:ClearFocus() end)
  e:SetScript("OnEditFocusLost", function(self) s.main = (self:GetText() or ""):gsub("[^%w%- ]", ""):sub(1, 24); C.Sample:Read("main") end)
  y = y + 26
  local l2 = widgets.labels:Get()
  l2:SetPoint("TOPLEFT", x, -y - 2)
  l2:SetWidth(90)
  color(l2, DIM)
  l2:SetText("Role")
  local rx = x + 92
  for _, role in ipairs({ "Tank", "Heal", "Melee", "Ranged" }) do
    local cb = widgets.checks:Get()
    cb:SetPoint("TOPLEFT", rx, -y - 3)
    cb.label:SetWidth(44)
    C.UI.FitText(cb.label, role, 42)
    cb:Set(ch.role == role)
    cb:SetOn(true)
    cb.fn = function(self) ch.role = self:GetChecked() and role or ""; C.Sample:Read("role"); C.UI:Draw() end
    rx = rx + 66
  end
  y = y + 28
  check("Raid spec set (this character)", ch.raidspec == true, true, function(on) ch.raidspec = on and true or nil; C.Sample:Read("raid_spec") end)
  y = y + 6
  for _, p in ipairs(PAGES) do
    if p[1] ~= "officers" or C.Roster:MeOfficer() then
      head(p[2])
      local ticked = C.UI.Ticked(p[1])
      for _, def in ipairs(C.UI.Candidates(p[1])) do
        check(def.label, ticked[def.id], true, function(on) C.UI.SetTicked(p[1], def.id, on) end)
      end
      y = y + 6
    end
  end
  return y
end

-- the rules the Guide learns by (Rules.lua): every threshold with its value and a step down and up, the officers' to
-- set (greyed for members), sent with Broadcast now and applied by the guild like the visibility. White where an
-- officer set it; the buttons' tooltip says what it does, who set it, and the default
local function round(v, step) return math.floor(v / step + 0.5) * step end
local function drawRules(x, w, y, officer)
  local R = C.Rules
  local head = widgets.labels:Get()
  head:SetPoint("TOPLEFT", x, -y)
  head:SetWidth(w)
  color(head, WHITE)
  head:SetText("Rules the Guide learns by")
  y = y + 20
  local note = widgets.labels:Get()
  note:SetPoint("TOPLEFT", x, -y)
  note:SetWidth(w)
  color(note, DIM)
  C.UI.FitText(note, officer and "White: set by an officer. Broadcast now sends them." or "White: set by an officer. Only officers can change them.", w - 4)
  y = y + 18
  for _, t in ipairs(R.TUNE) do
    local name, lo, hi, step = t[1], t[3], t[4], t[5]
    local l = widgets.labels:Get()
    l:SetPoint("TOPLEFT", x, -y - 3)
    l:SetWidth(w - 196)
    color(l, R.SetBy(name) and WHITE or INK)
    C.UI.FitText(l, t[2], w - 200)
    local val = widgets.values:Get()
    val:SetPoint("TOPLEFT", x + w - 190, -y - 3)
    val:SetWidth(44)
    color(val, R.SetBy(name) and WHITE or INK)
    C.UI.FitText(val, R.Show(name), 42)
    local function set(v)
      if not officer then return end
      v = round(v, step)
      if v < lo - 1e-9 or v > hi + 1e-9 then return end
      -- back at the default clears the officers' setting (an "x and nil or v" would always give v)
      if math.abs(v - R.RULES[name]) < 1e-9 then C.Policy:SetRule(name, nil) else C.Policy:SetRule(name, v) end
      C.UI:Draw()
    end
    local function tip(b)
      b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(t[2], 1, 1, 1)
        GameTooltip:AddLine(t[7], 0.85, 0.85, 0.85, true)
        local by = R.SetBy(name)
        GameTooltip:AddLine("Default " .. R.Show(name, R.RULES[name]) .. (by and (". Set to " .. R.Show(name) .. " by " .. R.WhoName(by) .. ".") or "."), 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local minus = widgets.buttons:Get()
    minus:SetPoint("TOPLEFT", x + w - 140, -y)
    minus:SetWidth(40)
    minus:SetLabel("-")
    minus:SetOn(officer and R.Get(name) > lo + 1e-9)
    minus:SetScript("OnClick", function() set(R.Get(name) - step) end)
    tip(minus)
    local plus = widgets.buttons:Get()
    plus:SetPoint("TOPLEFT", x + w - 96, -y)
    plus:SetWidth(40)
    plus:SetLabel("+")
    plus:SetOn(officer and R.Get(name) < hi - 1e-9)
    plus:SetScript("OnClick", function() set(R.Get(name) + step) end)
    tip(plus)
    y = y + 24
  end
  local reset = widgets.buttons:Get()
  reset:SetPoint("TOPLEFT", x, -y)
  reset:SetWidth(150)
  reset:SetLabel("Rules to defaults")
  reset:SetOn(officer)
  reset:SetScript("OnClick", function()
    if not officer then return end
    for _, t in ipairs(R.TUNE) do if R.SetBy(t[1]) then C.Policy:SetRule(t[1], nil) end end
    C.UI:Draw()
  end)
  reset:SetScript("OnEnter", nil)
  return y + 32
end

-- the right half: the officers' visibility list
local function drawOfficers(x, w)
  local officer = C.Roster:MeOfficer()
  local y = 4
  local l = widgets.labels:Get()
  l:SetPoint("TOPLEFT", x, -y)
  l:SetWidth(w)
  color(l, WHITE)
  l:SetText("Who sees what")
  y = y + 20
  local d = widgets.labels:Get()
  d:SetPoint("TOPLEFT", x, -y)
  d:SetWidth(w)
  color(d, DIM)
  C.UI.FitText(d, C.Policy:Describe() .. (officer and "" or " Only officers can change it."), w - 4)
  y = y + 18
  local t = widgets.labels:Get()
  t:SetPoint("TOPLEFT", x, -y - 3)
  t:SetWidth(w - 150)
  color(t, INK)
  C.UI.FitText(t, string.format("Officer ranks: 0 to %d", C.Policy:Threshold()), w - 154)
  local minus = widgets.buttons:Get()
  minus:SetPoint("TOPLEFT", x + w - 140, -y)
  minus:SetWidth(40)
  minus:SetLabel("-")
  minus:SetOn(officer)
  minus:SetScript("OnClick", function() if officer then C.Policy:SetThreshold(math.max(0, C.Policy:Threshold() - 1)); C.UI:Draw() end end)
  local plus = widgets.buttons:Get()
  plus:SetPoint("TOPLEFT", x + w - 96, -y)
  plus:SetWidth(40)
  plus:SetLabel("+")
  plus:SetOn(officer)
  plus:SetScript("OnClick", function() if officer then C.Policy:SetThreshold(math.min(9, C.Policy:Threshold() + 1)); C.UI:Draw() end end)
  y = y + 26
  local bc = widgets.buttons:Get()
  bc:SetPoint("TOPLEFT", x, -y)
  bc:SetWidth(150)
  bc:SetLabel("Broadcast now")
  bc:SetOn(officer)
  bc:SetScript("OnClick", function() if officer then C.Comm:SendPolicy(); C.Print("sent the visibility policy to the guild.") end end)
  local ra = widgets.buttons:Get()
  ra:SetPoint("TOPLEFT", x + 156, -y)
  ra:SetWidth(150)
  ra:SetLabel("Reset to defaults")
  ra:SetOn(officer)
  ra:SetScript("OnClick", function()
    if not officer then return end
    -- (the visibility only: the rules' thresholds below are reset on their own)
    local old = CuteDB.policy or {}
    CuteDB.policy = { vis = {}, rules = old.rules, ruleBy = old.ruleBy, by = C.Me(), mine = true, rank = C.Roster:MyRank(), at = C.Now(), threshold = C.Policy:Threshold() }
    C.UI:Draw()
  end)
  y = y + 30
  y = drawRules(x, w, y, officer)
  local h1 = widgets.labels:Get()
  h1:SetPoint("TOPLEFT", x + w - 130, -y)
  h1:SetWidth(60)
  color(h1, DIM)
  h1:SetText("Everyone")
  local h2 = widgets.labels:Get()
  h2:SetPoint("TOPLEFT", x + w - 64, -y)
  h2:SetWidth(60)
  color(h2, DIM)
  h2:SetText("Only you")
  y = y + 18
  -- one Everyone / Only-you pair; id is a stat's, or a statistics category's ("gc" .. its id)
  local function pair(id, label, indent)
    local lab = widgets.labels:Get()
    lab:SetPoint("TOPLEFT", x + (indent or 0), -y - 3)
    lab:SetWidth(w - 140 - (indent or 0))
    color(lab, INK)
    C.UI.FitText(lab, label, w - 144 - (indent or 0))
    local vis = C.Policy:Vis(id)
    local a = widgets.checks:Get()
    a:SetPoint("TOPLEFT", x + w - 118, -y - 3)
    a.label:SetText("")
    a.statId, a.vis = id, "all"
    a:Set(vis == "all")
    a:SetOn(officer)
    a.fn = function(self) if officer then C.Policy:Set(id, "all"); C.UI:Draw() else self:Set(vis == "all") end end
    local s = widgets.checks:Get()
    s:SetPoint("TOPLEFT", x + w - 52, -y - 3)
    s.label:SetText("")
    s.statId, s.vis = id, "self"
    s:Set(vis == "self")
    s:SetOn(officer)
    s.fn = function(self) if officer then C.Policy:Set(id, "self"); C.UI:Draw() else self:Set(vis == "self") end end
    y = y + ROWH
  end
  local function note(s)
    local n = widgets.labels:Get()
    n:SetPoint("TOPLEFT", x, -y - 3)
    n:SetWidth(w - 4)
    color(n, DIM)
    C.UI.FitText(n, s, w - 8)
    y = y + ROWH
  end
  for _, cat in ipairs(C.Stats.CATS) do
    local cl = widgets.labels:Get()
    cl:SetPoint("TOPLEFT", x, -y)
    cl:SetWidth(w)
    color(cl, WHITE)
    cl:SetText(C.Stats.CAT_LABEL[cat])
    y = y + 18
    if cat == "game" then
      -- what the guild discovers, per category, set before anything is found in it as well as after
      note("Discovered in play; a category's choice covers what is found in it.")
      for _, f in ipairs(C.Stats.FOUND) do pair("gc_" .. f[1], f[2]) end
      -- the game's statistics are set per category: a category's choice covers every statistic in it, a child's
      -- its parent's unless set
      local game = C.Stats.game
      if #C.Stats.byCat.game == 0 then note(C.Stats.gameNote or "No statistics on this client.")
      else
        note("Per category; a category's choice covers its statistics.")
        for _, g in ipairs(game.cats) do
          if #g.stats > 0 then pair("gc" .. g.id, g.name, g.parent ~= -1 and 14 or 0) end
        end
      end
    else
      for _, def in ipairs(C.Stats.byCat[cat]) do pair(def.id, def.label) end
    end
    y = y + 6
  end
  return y
end

function C.Settings_Draw(sf)
  ensure(sf.child)
  widgets.checks:Reset(); widgets.labels:Reset(); widgets.buttons:Reset(); widgets.edits:Reset(); widgets.values:Reset()
  local w = sf:Width()
  local half = math.floor((w - 24) / 2)
  local y1 = drawEveryone(6, half)
  local y2 = drawOfficers(6 + half + 12, half)
  widgets.checks:HideRest(); widgets.labels:HideRest(); widgets.buttons:HideRest(); widgets.edits:HideRest(); widgets.values:HideRest()
  sf:SetContentHeight(math.max(y1, y2) + 8)
end

function C.Settings_Hide()
  if not widgets.checks then return end
  widgets.checks:Reset(); widgets.labels:Reset(); widgets.buttons:Reset(); widgets.edits:Reset(); widgets.values:Reset()
  widgets.checks:HideRest(); widgets.labels:HideRest(); widgets.buttons:HideRest(); widgets.edits:HideRest(); widgets.values:HideRest()
end
