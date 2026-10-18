-- SPDX-License-Identifier: GPL-3.0-or-later
-- Settings, drawn inside the window's scroll area, flat like the rest.
--   Everyone:  which columns each page shows, density, offline members, the minimap button, your main, role and
--              raid spec (role and raid spec per character, the main account-wide)
--   Officers:  per stat, Everyone or Only you; the officer rank threshold; Broadcast now (greyed for members)
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
  -- a redraw while you type leaves your typing alone
  if not e:HasFocus() then e:SetText(s.main or "") end
  e:SetScript("OnEnterPressed", function(self) s.main = (self:GetText() or ""):gsub("[^%w%-]", ""):sub(1, 24); self:ClearFocus(); C.Sample:Read("main") end)
  e:SetScript("OnEscapePressed", function(self) self:SetText(s.main or ""); self:ClearFocus() end)
  e:SetScript("OnEditFocusLost", function(self) s.main = (self:GetText() or ""):gsub("[^%w%-]", ""):sub(1, 24); C.Sample:Read("main") end)
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
      for _, def in ipairs(C.Stats.byCat[C.UI.CAT_OF_PAGE[p[1]]]) do
        check(def.label, ticked[def.id], true, function(on) C.UI.SetTicked(p[1], def.id, on) end)
      end
      y = y + 6
    end
  end
  return y
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
    CuteDB.policy = { vis = {}, by = C.Me(), rank = C.Roster:Rank((C.Me())), at = C.Now(), threshold = C.Policy:Threshold() }
    C.UI:Draw()
  end)
  y = y + 30
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
  for _, cat in ipairs(C.Stats.CATS) do
    local cl = widgets.labels:Get()
    cl:SetPoint("TOPLEFT", x, -y)
    cl:SetWidth(w)
    color(cl, WHITE)
    cl:SetText(C.Stats.CAT_LABEL[cat])
    y = y + 18
    for _, def in ipairs(C.Stats.byCat[cat]) do
      local lab = widgets.labels:Get()
      lab:SetPoint("TOPLEFT", x, -y - 3)
      lab:SetWidth(w - 140)
      color(lab, INK)
      C.UI.FitText(lab, def.label, w - 144)
      local vis = C.Policy:Vis(def.id)
      local a = widgets.checks:Get()
      a:SetPoint("TOPLEFT", x + w - 118, -y - 3)
      a.label:SetText("")
      a.statId, a.vis = def.id, "all"
      a:Set(vis == "all")
      a:SetOn(officer)
      a.fn = function(self) if officer then C.Policy:Set(def.id, "all"); C.UI:Draw() else self:Set(vis == "all") end end
      local s = widgets.checks:Get()
      s:SetPoint("TOPLEFT", x + w - 52, -y - 3)
      s.label:SetText("")
      s.statId, s.vis = def.id, "self"
      s:Set(vis == "self")
      s:SetOn(officer)
      s.fn = function(self) if officer then C.Policy:Set(def.id, "self"); C.UI:Draw() else self:Set(vis == "self") end end
      y = y + ROWH
    end
    y = y + 6
  end
  return y
end

function C.Settings_Draw(sf)
  ensure(sf.child)
  widgets.checks:Reset(); widgets.labels:Reset(); widgets.buttons:Reset(); widgets.edits:Reset()
  local w = sf:Width()
  local half = math.floor((w - 24) / 2)
  local y1 = drawEveryone(6, half)
  local y2 = drawOfficers(6 + half + 12, half)
  widgets.checks:HideRest(); widgets.labels:HideRest(); widgets.buttons:HideRest(); widgets.edits:HideRest()
  sf:SetContentHeight(math.max(y1, y2) + 8)
end

function C.Settings_Hide()
  if not widgets.checks then return end
  widgets.checks:Reset(); widgets.labels:Reset(); widgets.buttons:Reset(); widgets.edits:Reset()
  widgets.checks:HideRest(); widgets.labels:HideRest(); widgets.buttons:HideRest(); widgets.edits:HideRest()
end
