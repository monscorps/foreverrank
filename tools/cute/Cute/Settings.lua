-- SPDX-License-Identifier: GPL-3.0-or-later
-- Settings, drawn inside the window's scroll area.
--   Everyone:  which columns each page shows, density, offline members, the minimap button, your main and role
--   Officers:  per stat, Everyone or Only you; the officer rank threshold; Broadcast now (greyed for members)
local _, C = ...
local ST = {}
C.SettingsPage = ST

local INK = { 0.93, 0.88, 0.78 }
local INK_SOFT = { 0.62, 0.58, 0.50 }
local GOLD = { 0.91, 0.70, 0.29 }
local ROWH = 20

local widgets = { checks = nil, labels = nil, buttons = nil, edits = nil }

local function text(parent, size, color, width)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(GameFontNormalSmall)
  local path, _, flags = GameFontNormalSmall:GetFont()
  if path then fs:SetFont(path, size or 11, flags) end
  fs:SetTextColor(color[1], color[2], color[3])
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  if width then fs:SetWidth(width) end
  return fs
end

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
  widgets.checks = pool(parent, function(p)
    local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb.label = text(cb, 11, INK, 200)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    return cb
  end)
  widgets.labels = pool(parent, function(p) return text(p, 11, INK, 300) end)
  widgets.buttons = pool(parent, function(p)
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(140, 22)
    return b
  end)
  widgets.edits = pool(parent, function(p)
    local e = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    e:SetSize(140, 20)
    e:SetAutoFocus(false)
    e:SetMaxLetters(24)
    return e
  end)
end

local PAGES = { { "race", "Race columns" }, { "prog", "Prog columns" }, { "shame", "Hall of Shame cards" }, { "officers", "Officers columns" } }

-- the left half: everyone's choices
local function drawEveryone(x, w)
  local s = C.Settings()
  local y = 4
  local function head(label)
    local l = widgets.labels:Get()
    l:SetPoint("TOPLEFT", x, -y)
    l:SetWidth(w)
    l:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    l:SetText(label)
    y = y + 20
  end
  local function check(label, on, enabled, fn)
    local cb = widgets.checks:Get()
    cb:SetPoint("TOPLEFT", x, -y)
    cb.label:SetWidth(w - 26)
    C.UI.FitText(cb.label, label, w - 30)
    cb:SetChecked(on and true or false)
    cb:SetEnabled(enabled ~= false)
    cb.label:SetTextColor(enabled == false and INK_SOFT[1] or INK[1], enabled == false and INK_SOFT[2] or INK[2], enabled == false and INK_SOFT[3] or INK[3])
    cb:SetScript("OnClick", function(self) fn(self:GetChecked()) end)
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
  l:SetTextColor(INK[1], INK[2], INK[3])
  l:SetText("Main character")
  local e = widgets.edits:Get()
  e:SetPoint("TOPLEFT", x + 100, -y)
  e:SetWidth(math.min(160, w - 104))
  e:SetText(s.main or "")
  e:SetScript("OnEnterPressed", function(self) s.main = (self:GetText() or ""):gsub("[^%w%-]", ""):sub(1, 24); self:ClearFocus(); C.Sample:Read("main") end)
  e:SetScript("OnEscapePressed", function(self) self:SetText(s.main or ""); self:ClearFocus() end)
  e:SetScript("OnEditFocusLost", function(self) s.main = (self:GetText() or ""):gsub("[^%w%-]", ""):sub(1, 24); C.Sample:Read("main") end)
  y = y + 26
  local l2 = widgets.labels:Get()
  l2:SetPoint("TOPLEFT", x, -y - 2)
  l2:SetWidth(90)
  l2:SetTextColor(INK[1], INK[2], INK[3])
  l2:SetText("Role")
  local rx = x + 92
  for _, role in ipairs({ "Tank", "Heal", "Melee", "Ranged" }) do
    local cb = widgets.checks:Get()
    cb:SetPoint("TOPLEFT", rx, -y)
    cb.label:SetWidth(40)
    C.UI.FitText(cb.label, role, 38)
    cb.label:SetTextColor(INK[1], INK[2], INK[3])
    cb:SetChecked(s.role == role)
    cb:SetEnabled(true)
    cb:SetScript("OnClick", function(self) s.role = self:GetChecked() and role or ""; C.Sample:Read("role"); C.UI:Draw() end)
    rx = rx + 62
  end
  y = y + 28
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
  l:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  l:SetText("Who sees what (officers set this)")
  y = y + 20
  local d = widgets.labels:Get()
  d:SetPoint("TOPLEFT", x, -y)
  d:SetWidth(w)
  d:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
  C.UI.FitText(d, C.Policy:Describe() .. (officer and "" or " Only officers can change it."), w - 4)
  y = y + 18
  -- the threshold
  local t = widgets.labels:Get()
  t:SetPoint("TOPLEFT", x, -y - 3)
  t:SetWidth(w - 150)
  t:SetTextColor(INK[1], INK[2], INK[3])
  C.UI.FitText(t, string.format("Officer ranks: 0 to %d", C.Policy:Threshold()), w - 154)
  local minus = widgets.buttons:Get()
  minus:SetPoint("TOPLEFT", x + w - 140, -y)
  minus:SetWidth(40)
  minus:SetText("-")
  minus:SetEnabled(officer)
  minus:SetScript("OnClick", function() C.Policy:SetThreshold(math.max(0, C.Policy:Threshold() - 1)); C.UI:Draw() end)
  local plus = widgets.buttons:Get()
  plus:SetPoint("TOPLEFT", x + w - 96, -y)
  plus:SetWidth(40)
  plus:SetText("+")
  plus:SetEnabled(officer)
  plus:SetScript("OnClick", function() C.Policy:SetThreshold(math.min(9, C.Policy:Threshold() + 1)); C.UI:Draw() end)
  y = y + 26
  local bc = widgets.buttons:Get()
  bc:SetPoint("TOPLEFT", x, -y)
  bc:SetWidth(150)
  bc:SetText("Broadcast now")
  bc:SetEnabled(officer)
  bc:SetScript("OnClick", function() C.Comm:SendPolicy(); C.Print("sent the visibility policy to the guild.") end)
  local ra = widgets.buttons:Get()
  ra:SetPoint("TOPLEFT", x + 156, -y)
  ra:SetWidth(150)
  ra:SetText("Reset to defaults")
  ra:SetEnabled(officer)
  ra:SetScript("OnClick", function()
    CuteDB.policy = { vis = {}, by = C.Me(), rank = C.Roster:Rank((C.Me())), at = C.Now(), threshold = C.Policy:Threshold() }
    C.UI:Draw()
  end)
  y = y + 30
  -- headings for the two columns of check buttons
  local h1 = widgets.labels:Get()
  h1:SetPoint("TOPLEFT", x + w - 130, -y)
  h1:SetWidth(60)
  h1:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  h1:SetText("Everyone")
  local h2 = widgets.labels:Get()
  h2:SetPoint("TOPLEFT", x + w - 64, -y)
  h2:SetWidth(60)
  h2:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  h2:SetText("Only you")
  y = y + 18
  for _, cat in ipairs(C.Stats.CATS) do
    local cl = widgets.labels:Get()
    cl:SetPoint("TOPLEFT", x, -y)
    cl:SetWidth(w)
    cl:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    cl:SetText(C.Stats.CAT_LABEL[cat])
    y = y + 18
    for _, def in ipairs(C.Stats.byCat[cat]) do
      local lab = widgets.labels:Get()
      lab:SetPoint("TOPLEFT", x, -y - 3)
      lab:SetWidth(w - 140)
      lab:SetTextColor(INK[1], INK[2], INK[3])
      C.UI.FitText(lab, def.label, w - 144)
      local vis = C.Policy:Vis(def.id)
      local a = widgets.checks:Get()
      a:SetPoint("TOPLEFT", x + w - 122, -y)
      a.label:SetText("")
      a:SetChecked(vis == "all")
      a:SetEnabled(officer)
      a:SetScript("OnClick", function(self) if officer then C.Policy:Set(def.id, "all"); C.UI:Draw() else self:SetChecked(vis == "all") end end)
      local s = widgets.checks:Get()
      s:SetPoint("TOPLEFT", x + w - 56, -y)
      s.label:SetText("")
      s:SetChecked(vis == "self")
      s:SetEnabled(officer)
      s:SetScript("OnClick", function(self) if officer then C.Policy:Set(def.id, "self"); C.UI:Draw() else self:SetChecked(vis == "self") end end)
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
