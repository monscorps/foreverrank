-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank window: a quest-log-styled toolbox with four pages.
--   Quest Log  - your 40 slots as a bank, your bags, and swaps that gain XP
--   Prep       - what to fetch before the cap, by dungeon and zone, for your faction and class
--   Hand-in    - the turn-in route with a clock and your level at every stop, and the run as you go
--   Party      - QuestBank users in your group and guild: banks, runs, dungeons worth running together
-- Built on first open, rows are pooled, and nothing updates while it is hidden.
local _, QB = ...
local UI = {}
QB.UI = UI

local W, H = 800, 620
local INK = { 0.20, 0.12, 0.05 }
local INK_SOFT = { 0.40, 0.29, 0.16 }
local GOOD = { 0.05, 0.40, 0.08 }
local BAD = { 0.55, 0.12, 0.05 }
local GOLD = { 1, 0.82, 0 }
local WHITE = { 0.95, 0.93, 0.88 }
local QUALITY = {
  { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 },
}
local STATUS = {
  done = { 0.45, 0.42, 0.38 }, banked = GOOD, active = { 0.60, 0.36, 0.0 }, partial = { 0.60, 0.36, 0.0 },
  bagstart = { 0.60, 0.36, 0.0 }, locked = BAD, prereq = BAD, todo = INK_SOFT, follow = { 0.25, 0.25, 0.45 },
  wrong = { 0.45, 0.42, 0.38 },
}
local BD = BackdropTemplateMixin and "BackdropTemplate" or nil
local T -- QB.Data.TEX
local Q = QB.Quest

local function tier(xp)
  if not xp then return 1 end
  if xp >= 12000 then return 6 elseif xp >= 9000 then return 5 elseif xp >= 6000 then return 4
  elseif xp >= 3000 then return 3 elseif xp >= 1500 then return 2 end
  return 1
end

local function hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

----------------------------------------------------------------------------
-- small builders
----------------------------------------------------------------------------
local function tex(parent, layer, file, w, h)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  if file then t:SetTexture(file) end
  if w then t:SetSize(w, h or w) end
  return t
end

-- a one-line label; with a width it truncates instead of running into its neighbours
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

local function para(parent, obj, size, color, width)
  local fs = text(parent, obj, size, color, "LEFT", width)
  fs:SetWordWrap(true)
  fs:SetJustifyV("TOP")
  return fs
end

local function backdrop(frame, bg, edge, edgeSize, inset, tile)
  if not frame.SetBackdrop then return end
  frame:SetBackdrop({
    bgFile = bg, edgeFile = edge, tile = tile and true or false, tileSize = 32, edgeSize = edgeSize,
    insets = { left = inset, right = inset, top = inset, bottom = inset },
  })
end

local function tooltip(owner, fill)
  owner:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    fill(GameTooltip, self)
    GameTooltip:Show()
  end)
  owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function iconButton(parent, size, icon)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.icon = tex(b, "ARTWORK", icon)
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.border = tex(b, "OVERLAY", T.slot, size * 1.83, size * 1.83)
  b.border:SetPoint("CENTER")
  b:SetHighlightTexture(T.hilite, "ADD")
  return b
end

local function button(parent, label, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 110, 22)
  b:SetText(label)
  return b
end

local function setIcon(t, icon) t:SetTexture(icon or T.questGeneric) end

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

-- ScrollFrame, content child and a knob slider, no templates needed
local function scrollArea(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  sf:SetPoint("TOPLEFT", 6, -6)
  sf:SetPoint("BOTTOMRIGHT", -24, 6)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(W - 90, 10)
  sf:SetScrollChild(child)
  local bar = CreateFrame("Slider", nil, parent)
  bar:SetOrientation("VERTICAL")
  bar:SetPoint("TOPRIGHT", -8, -10)
  bar:SetPoint("BOTTOMRIGHT", -8, 10)
  bar:SetWidth(14)
  local track = tex(bar, "BACKGROUND")
  track:SetColorTexture(0.25, 0.17, 0.08, 0.25)
  track:SetPoint("TOPLEFT", 4, 0)
  track:SetPoint("BOTTOMRIGHT", -4, 0)
  local knob = tex(bar, "OVERLAY", T.knob, 18, 24)
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
    local max = math.max(0, h - view)
    bar:SetMinMaxValues(0, max)
    bar:SetShown(max > 0)
    if bar:GetValue() > max then bar:SetValue(max) end
  end
  function sf:Width()
    local w = self:GetWidth() or 0
    if w < 200 then w = W - 32 - 36 end
    return w
  end
  return sf
end

----------------------------------------------------------------------------
-- quests: tooltip and clicks shared by every page
----------------------------------------------------------------------------
local function npcLine(tip, label, n)
  if not n then return end
  local where
  if n.inside then
    where = n.n .. ", inside the dungeon"
  else
    local zone = QB.Data.MAPNAME[n.m] or ""
    where = string.format("%s, %s %.0f, %.0f", n.n, n.place or zone, n.x, n.y)
  end
  tip:AddDoubleLine(label, where, 0.6, 0.6, 0.6, 1, 1, 1)
end

function UI.QuestTooltip(tip, q, st, xp, pct, plvl)
  tip:AddLine(q.name, GOLD[1], GOLD[2], GOLD[3])
  local cat = q.cat and q.cat.name or ""
  tip:AddDoubleLine(string.format("Level %d, needs %d", q.lvl, q.req or 1), cat, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
  local full = Q.Full(q)
  local src
  if q.liveFull then
    src = QB.Live.Source(q) or "the game's own number"
  elseif q.unconfirmed then
    src = string.format("Classic %s, Forever multiplier not read yet", QB.Comma(q.base))
  elseif q.mult ~= 1 then
    src = string.format("%s x %s", QB.Comma(q.base), (tostring(q.mult):gsub("%.?0+$", "")))
  else
    src = QB.Comma(q.base) .. " x 1"
  end
  tip:AddDoubleLine("Forever XP " .. QB.Comma(full), src, 1, 1, 1, 0.55, 0.75, 1)
  if q.liveFull and math.abs(q.liveFull - QB.Model.Listed(q)) > 25 then
    tip:AddLine(string.format("Wowhead lists %s. QuestBank uses the game's number.", QB.Comma(QB.Model.Listed(q))), 1, 0.6, 0.3, true)
  end
  if xp then
    local line = QB.Comma(xp) .. " XP on the day"
    if pct and pct < 100 then line = line .. string.format(" (%d%% at level %d)", pct, plvl) end
    tip:AddLine(line, pct and pct < 100 and 1 or 0.6, pct and pct < 100 and 0.6 or 1, pct and pct < 100 and 0.3 or 0.6)
  end
  if st then
    local c = STATUS[st.code] or WHITE
    tip:AddLine(st.text, math.min(1, c[1] * 1.6 + 0.25), math.min(1, c[2] * 1.6 + 0.25), math.min(1, c[3] * 1.6 + 0.25), true)
  end
  if q.tip then tip:AddLine(q.tip, 0.85, 0.8, 0.7, true) end
  if q.group then tip:AddLine("Group quest.", 1, 0.5, 0.3) end
  local chain = Q.ChainText(q)
  if chain then tip:AddLine("Chain: " .. chain, 0.75, 0.75, 1, true) end
  if q.nextSteps then
    local names = {}
    for _, n in ipairs(q.nextSteps) do
      local nq = Q.Get(n)
      if nq and Q.ForMe(nq) then names[#names + 1] = string.format("%s (%s)", nq.name, QB.Short(QB.Model.XpAt(nq, math.max(QB.state.level, 20)))) end
    end
    if #names > 0 then tip:AddLine("Leads on to: " .. table.concat(names, ", "), 0.75, 0.75, 1, true) end
  end
  npcLine(tip, "From", q.give)
  npcLine(tip, "Hand in", q.turn)
  local inLog = QB.state.log[q.id]
  if inLog or (st and st.bag) then
    tip:AddLine(QB:IsCut(q.id) and "Cut from the plan. Shift-click to keep it." or "Click: map pin.  Shift-click: cut it from the plan.", 0.5, 0.5, 0.5)
  else
    tip:AddLine(QB:IsAdded(q.id) and "In the plan. Shift-click to drop it." or "Click: map pin.  Shift-click: add it to the plan.", 0.5, 0.5, 0.5)
  end
end

function UI.QuestClick(q, st)
  if IsShiftKeyDown and IsShiftKeyDown() then
    QB:ToggleAdd(q.id)
    UI:Refresh()
    return
  end
  local target = q.turn
  if st and (st.code == "todo" or st.code == "locked" or st.code == "prereq") and q.give then target = q.give end
  if target and not target.inside then QB.API.SetWaypoint(target.m, target.x, target.y, target.n) end
end

----------------------------------------------------------------------------
-- frame
----------------------------------------------------------------------------
function UI:Create()
  if self.frame then return self.frame end
  T = QB.Data.TEX
  local set = QB:Settings()
  local f = CreateFrame("Frame", "QuestBankFrame", UIParent, BD)
  self.frame = f
  f:SetSize(W, H)
  if set.pos then
    f:SetPoint(set.pos[1], UIParent, set.pos[1], set.pos[2], set.pos[3])
  else
    f:SetPoint("CENTER")
  end
  f:SetFrameStrata("MEDIUM")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, _, x, y = self:GetPoint()
    QB:Settings().pos = { p, x, y }
  end)
  f:SetScript("OnShow", function() UI:Refresh() end)
  f:Hide()
  backdrop(f, T.bg, T.border, 32, 11, true)
  if UISpecialFrames then table.insert(UISpecialFrames, "QuestBankFrame") end

  local plate = tex(f, "ARTWORK", T.header, 320, 64)
  plate:SetPoint("TOP", 0, 12)
  local title = text(f, "GameFontNormalLarge", 15, GOLD, "CENTER", 200)
  title:SetPoint("TOP", plate, "TOP", 0, -14)
  title:SetText("QuestBank")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -5, -5)

  self:CreateHeader(f)
  self:CreateContent(f)
  self:CreateTabs(f)
  self:ShowTab(set.tab or 1)
  return f
end

-- header: portrait, name, the XP bar from 20 to 30, four switches
local BAR_X, BAR_W = 92, 400
function UI:CreateHeader(f)
  local h = {}
  self.header = h
  h.portrait = tex(f, "ARTWORK", nil, 58, 58)
  h.portrait:SetPoint("TOPLEFT", 22, -34)
  h.name = text(f, "GameFontNormalLarge", 16, GOLD, "LEFT", BAR_W)
  h.name:SetPoint("TOPLEFT", BAR_X, -34)
  h.sub = text(f, "GameFontHighlightSmall", 11, WHITE, "LEFT", BAR_W)
  h.sub:SetPoint("TOPLEFT", BAR_X, -54)
  h.legend = text(f, "GameFontHighlightSmall", 11, WHITE, "LEFT", BAR_W)
  h.legend:SetPoint("TOPLEFT", BAR_X, -70)

  local bar = CreateFrame("Frame", nil, f, BD)
  bar:SetPoint("TOPLEFT", BAR_X - 4, -86)
  bar:SetSize(BAR_W + 8, 22)
  backdrop(bar, T.tipBg, T.tipBorder, 10, 2)
  if bar.SetBackdropColor then bar:SetBackdropColor(0, 0, 0, 0.75) end
  local function fill(layer, r, g, b, a)
    local t = tex(bar, layer, T.bar)
    t:SetPoint("TOPLEFT", 4, -4)
    t:SetHeight(14)
    t:SetVertexColor(r, g, b, a)
    t:SetWidth(1)
    return t
  end
  h.fillPlan = fill("BORDER", 0.75, 0.55, 1, 0.35)
  h.fillNow = fill("ARTWORK", 0.58, 0.0, 0.55, 0.85)
  h.fillCur = fill("OVERLAY", 0.25, 0.5, 1, 1)
  for i = 1, 9 do
    local tick = tex(bar, "OVERLAY")
    tick:SetColorTexture(0, 0, 0, 0.8)
    tick:SetSize(1, 14)
    tick:SetPoint("TOPLEFT", 4 + BAR_W * i / 10, -4)
  end
  for i = 0, 10, 2 do
    local lab = text(f, "GameFontHighlightSmall", 10, { 0.75, 0.72, 0.65 }, "CENTER", 24)
    lab:SetPoint("TOP", bar, "BOTTOMLEFT", 4 + BAR_W * i / 10, 0)
    lab:SetText(20 + i)
  end
  tooltip(bar, function(tip)
    tip:AddLine("Level 20 to 30", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Blue: where you are now.", 0.5, 0.7, 1)
    tip:AddLine("Purple: after handing in everything banked now.", 0.8, 0.4, 0.8)
    tip:AddLine("Pale: after the whole plan.", 0.85, 0.75, 1)
    tip:AddLine("Level 20 to 30 takes 331,800 XP.", 0.8, 0.8, 0.8)
    local D, st = QB.Data, QB.Data.STATS
    if st then
      tip:AddLine(" ")
      tip:AddLine(string.format("Quest data read %s, Forever client %s.", D.READ or "", D.BUILD or ""), 0.6, 0.6, 0.6, true)
      tip:AddLine(string.format("Of %d quests worth banking: %d without a read multiplier, %d without a known turn-in spot, %d handed in inside a dungeon.",
        st.quests, st.noMult, st.noTurn, st.inside), 0.6, 0.6, 0.6, true)
    end
  end)

  h.toggles = {}
  local defs = {
    { key = "mounted", icon = T.mount }, { key = "bag", icon = T.sleep },
    { key = "goal", icon = T.hourglass }, { key = "pins", icon = T.map },
  }
  for i, d in ipairs(defs) do
    local b = iconButton(f, 30, d.icon)
    b:SetPoint("TOPRIGHT", -(34 + (4 - i) * 66), -46)
    b.caption = text(f, "GameFontHighlightSmall", 10, WHITE, "CENTER", 64)
    b.caption:SetPoint("TOP", b, "BOTTOM", 0, -8)
    b.key = d.key
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, which) UI:Switch(self.key, which) end)
    tooltip(b, function(tip, self) UI:SwitchTooltip(tip, self.key) end)
    h.toggles[d.key] = b
  end
end

function UI:Switch(key, which)
  local set = QB:Settings()
  if key == "mounted" or key == "bag" then
    if which == "RightButton" then
      set[key] = "auto"
    else
      local on = (key == "mounted") and QB:Mounted() or QB:BagBonus()
      set[key] = not on
    end
  elseif key == "goal" then
    set.goal = set.goal == "hour" and "route" or "hour"
  elseif key == "pins" then
    if which == "RightButton" then
      if QB.Pins then QB.Pins:PinNext(true) end
      return
    end
    if QB.Pins then QB.Pins:Toggle() else set.pins = not set.pins end
  end
  QB:MarkDirty()
  self:Refresh()
end

function UI:SwitchTooltip(tip, key)
  local set = QB:Settings()
  if key == "mounted" then
    local on, auto = QB:Mounted()
    tip:AddLine(on and "Mounted" or "On foot", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("A mount cuts every stretch on foot to 62%. Flights, boats and zeppelins take as long as they take.", 1, 1, 1, true)
    tip:AddLine(auto and "Set from your riding skill. Right-click keeps it on auto." or "Set by you. Right-click goes back to auto.", 0.6, 0.6, 0.6, true)
  elseif key == "bag" then
    local on, auto = QB:BagBonus()
    tip:AddLine(on and "Cozy Sleeping Bag: +3%" or "No sleeping bag bonus", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Lie in the bag for three minutes before the first hand-in: +3% XP from quests for two hours.", 1, 1, 1, true)
    tip:AddLine(auto and "Follows the Well Rested buff. Right-click keeps it on auto." or "Set by you. Right-click goes back to auto.", 0.6, 0.6, 0.6, true)
  elseif key == "goal" then
    tip:AddLine(set.goal == "hour" and "Plan for the first hour" or "Plan for the whole route", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("First hour: the highest level at the 60-minute mark, whatever comes after. Whole route: the highest level at the end, in the least time.", 1, 1, 1, true)
  elseif key == "pins" then
    tip:AddLine(set.pins and "Map pins on" or "Map pins off", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Numbered pins on the world map for every stop on the route, and ! pins where planned quests start.", 1, 1, 1, true)
    tip:AddLine("Right-click: waypoint on the next stop.", 0.6, 0.6, 0.6)
  end
end

function UI:CreateContent(f)
  local c = CreateFrame("Frame", nil, f, BD)
  c:SetPoint("TOPLEFT", 16, -128)
  c:SetPoint("BOTTOMRIGHT", -16, 42)
  backdrop(c, nil, T.tipBorder, 14, 3)
  local parch = tex(c, "BACKGROUND", T.parchH)
  parch:SetPoint("TOPLEFT", 4, -4)
  parch:SetPoint("BOTTOMRIGHT", -4, 4)
  self.content = c
  self.views = {
    self:CreateLogView(c),
    self:CreatePrepView(c),
    self:CreateRouteView(c),
    self:CreatePartyView(c),
  }
end

function UI:CreateTabs(f)
  self.tabs = {}
  local names = { "Quest Log", "Prep", "Hand-in Route", "Party" }
  local x = 20
  for i, name in ipairs(names) do
    local b = CreateFrame("Button", nil, f)
    local w = 118
    b:SetSize(w, 32)
    b:SetPoint("TOPLEFT", self.content, "BOTTOMLEFT", x, 2)
    x = x + w + 2
    local function piece(file, w2, l, r, bottom, h2)
      local t = tex(b, "BACKGROUND", file)
      t:SetSize(w2, h2)
      t:SetTexCoord(l, r, 0, bottom)
      return t
    end
    b.onL = piece(T.tabOn, 20, 0, 0.15625, 0.546875, 35)
    b.onR = piece(T.tabOn, 20, 0.84375, 1, 0.546875, 35)
    b.onM = piece(T.tabOn, w - 40, 0.15625, 0.84375, 0.546875, 35)
    b.offL = piece(T.tabOff, 20, 0, 0.15625, 1, 32)
    b.offR = piece(T.tabOff, 20, 0.84375, 1, 1, 32)
    b.offM = piece(T.tabOff, w - 40, 0.15625, 0.84375, 1, 32)
    for _, set in ipairs({ { b.onL, b.onM, b.onR, 3 }, { b.offL, b.offM, b.offR, 0 } }) do
      set[1]:SetPoint("TOPLEFT", 0, set[4])
      set[2]:SetPoint("TOPLEFT", set[1], "TOPRIGHT")
      set[3]:SetPoint("TOPLEFT", set[2], "TOPRIGHT")
    end
    local hi = tex(b, "HIGHLIGHT", T.tabHi)
    hi:SetPoint("TOPLEFT", 6, -2)
    hi:SetPoint("BOTTOMRIGHT", -6, 6)
    hi:SetBlendMode("ADD")
    b.label = text(b, "GameFontNormalSmall", 12, GOLD, "CENTER", w - 16)
    b.label:SetPoint("CENTER", 0, 2)
    b.label:SetText(name)
    b:SetScript("OnClick", function() UI:ShowTab(i) end)
    self.tabs[i] = b
  end
end

function UI:ShowTab(i)
  QB:Settings().tab = i
  self.tab = i
  for k, v in ipairs(self.views) do v:SetShown(k == i) end
  for k, b in ipairs(self.tabs) do
    local on = k == i
    for _, t in ipairs({ b.onL, b.onM, b.onR }) do t:SetShown(on) end
    for _, t in ipairs({ b.offL, b.offM, b.offR }) do t:SetShown(not on) end
    b.label:SetTextColor(on and 1 or GOLD[1], on and 1 or GOLD[2], on and 1 or GOLD[3])
  end
  if self.frame and self.frame:IsShown() then self:Refresh() end
end

function UI:Open(tab)
  self:Create()
  self.frame:Show()
  if tab then self:ShowTab(tab) end
end

function UI:Toggle()
  self:Create()
  self.frame:SetShown(not self.frame:IsShown())
end

----------------------------------------------------------------------------
-- refresh
----------------------------------------------------------------------------
function UI:Refresh()
  if not (self.frame and self.frame:IsShown()) then return end
  QB:Recompute()
  self:RefreshHeader()
  local v = self.views[self.tab or 1]
  if v and v.Refresh then v:Refresh() end
end

function UI:RefreshHeader()
  local h, s = self.header, QB.state
  if SetPortraitTexture then SetPortraitTexture(h.portrait, "player") end
  h.name:SetText(s.name or "")
  local cls = UnitClass and (UnitClass("player")) or ""
  local bind = QB.API.BindName()
  h.sub:SetText(string.format("Level %d %s, %s.  Hearthstone: %s", s.level, cls or "", QB.faction == "H" and "Horde" or "Alliance",
    bind ~= "" and bind or "not set"))
  local cur = QB.Model.Frac(s.level, s.xp)
  local now, plan = QB.routeNow, QB.routePlan
  local function w(level) return math.max(1, math.min(BAR_W, BAR_W * (level - 20) / 10)) end
  h.fillCur:SetWidth(w(cur))
  local nowL = (now and not now.empty) and now.level or cur
  local planL = (plan and not plan.empty) and plan.level or cur
  local plan60 = (plan and not plan.empty) and plan.at60 or cur
  h.fillNow:SetWidth(w(nowL))
  h.fillPlan:SetWidth(w(planL))
  h.legend:SetText(string.format("|cff6f9fffNow %.1f|r    |cffc080c0Banked %.1f|r    |cffd8c8ffPlan %.1f|r    |cffaaaaaaPlan at 60 min %.1f|r",
    cur, nowL, planL, plan60))
  local set = QB:Settings()
  local tg = h.toggles
  local mounted = QB:Mounted()
  setIcon(tg.mounted.icon, mounted and T.mount or T.foot)
  tg.mounted.caption:SetText(mounted and "Mounted" or "On foot")
  local bag = QB:BagBonus()
  tg.bag.icon:SetDesaturated(not bag)
  tg.bag.caption:SetText(bag and "+3% XP" or "No bag")
  tg.goal.caption:SetText(set.goal == "hour" and "First hour" or "Whole route")
  tg.pins.icon:SetDesaturated(not set.pins)
  tg.pins.caption:SetText(set.pins and "Pins on" or "Pins off")
end

----------------------------------------------------------------------------
-- page 1: the quest log as a bank
----------------------------------------------------------------------------
local LEFT, RIGHT = 16, 420

function UI:CreateLogView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()
  v.title = text(v, "GameFontNormalLarge", 15, INK, "LEFT", 150)
  v.title:SetPoint("TOPLEFT", LEFT, -12)
  v.worth = text(v, "GameFontNormal", 12, INK_SOFT, "LEFT", 230)
  v.worth:SetPoint("TOPLEFT", LEFT + 150, -14)
  v.slots = {}
  for i = 1, 40 do
    local b = iconButton(v, 36, nil)
    local col, row = (i - 1) % 8, math.floor((i - 1) / 8)
    b:SetPoint("TOPLEFT", LEFT + 4 + col * 46, -42 - row * 46)
    b.frame = tex(b, "OVERLAY", T.iconFrame)
    b.frame:SetAllPoints()
    b.xp = text(b, "NumberFontNormal", 11, WHITE, "RIGHT", 40)
    b.xp:SetPoint("BOTTOMRIGHT", 0, 2)
    b.mark = tex(b, "OVERLAY", nil, 14, 14)
    b.mark:SetPoint("TOPLEFT", 1, -1)
    b:SetScript("OnClick", function(self) if self.q then UI.QuestClick(self.q, self.st) end end)
    tooltip(b, function(tip, self)
      if self.q then
        UI.QuestTooltip(tip, self.q, self.st, self.value, self.pct, self.plvl)
      elseif self.entry then
        tip:AddLine(self.entry.title, GOLD[1], GOLD[2], GOLD[3])
        tip:AddLine("Not in QuestBank's catalog, so the route can't place it.", 1, 1, 1, true)
        tip:AddLine(self.entry.complete and "Complete" or "Not complete", 0.8, 0.8, 0.8)
      else
        tip:AddLine("Free slot", GOLD[1], GOLD[2], GOLD[3])
        tip:AddLine("Fill it with the best quest from the swaps on the right.", 1, 1, 1, true)
      end
    end)
    v.slots[i] = b
  end
  v.bagLabel = text(v, "GameFontNormal", 13, INK, "LEFT", 380)
  v.bagLabel:SetPoint("TOPLEFT", LEFT, -278)
  v.bagLabel:SetText("In your bags, no log slot needed")
  v.bagSlots = {}
  for i = 1, 8 do
    local b = iconButton(v, 32, nil)
    b:SetPoint("TOPLEFT", LEFT + 4 + (i - 1) * 46, -300)
    b.count = text(b, "NumberFontNormal", 11, WHITE, "RIGHT", 40)
    b.count:SetPoint("BOTTOMRIGHT", 0, 2)
    tooltip(b, function(tip, self)
      local it = self.item
      if not it then return end
      tip:AddLine(it.name or "", GOLD[1], GOLD[2], GOLD[3])
      if it.need then tip:AddLine(string.format("%d of %d in your bags", QB.API.ItemCount(it.id), it.need), 1, 1, 1) end
      if it.q then UI.QuestTooltip(tip, it.q, QB:Status(it.q), (QB:Value(it.q.id))) end
      if it.id == 211527 then tip:AddLine("Lie in it three minutes before the first hand-in: +3% for two hours.", 0.8, 0.8, 0.8, true) end
    end)
    b:SetScript("OnClick", function(self) if self.item and self.item.q then UI.QuestClick(self.item.q, QB:Status(self.item.q)) end end)
    v.bagSlots[i] = b
  end
  v.dropTitle = text(v, "GameFontNormal", 12, BAD, "LEFT", 300)
  v.dropTitle:SetPoint("TOPLEFT", LEFT, -346)
  v.dropClear = button(v, "Clear", 64)
  v.dropClear:SetPoint("TOPLEFT", LEFT + 316, -342)
  v.dropClear:SetScript("OnClick", function()
    local p = QB:Plan()
    for k in pairs(p.removed) do p.removed[k] = nil end
    UI:Refresh()
  end)
  v.drops = para(v, "GameFontNormalSmall", 11, INK_SOFT, 380)
  v.drops:SetPoint("TOPLEFT", LEFT, -366)
  v.drops:SetHeight(50)

  -- swaps
  local st = text(v, "GameFontNormalLarge", 15, INK, "LEFT", 320)
  st:SetPoint("TOPLEFT", RIGHT, -12)
  st:SetText("Better use of a slot")
  v.swapHint = text(v, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", 330)
  v.swapHint:SetPoint("TOPLEFT", RIGHT, -32)
  v.swapHint:SetText("Advance a chain, fill a free slot, or swap a weak quest.")
  v.swaps = {}
  for i = 1, 8 do
    local r = CreateFrame("Button", nil, v)
    r:SetSize(334, 38)
    r:SetPoint("TOPLEFT", RIGHT, -52 - (i - 1) * 40)
    r.hi = tex(r, "HIGHLIGHT", T.rowHi)
    r.hi:SetAllPoints()
    r.hi:SetBlendMode("ADD")
    r.addIcon = tex(r, "ARTWORK", nil, 30, 30)
    r.addIcon:SetPoint("LEFT", 2, 0)
    r.addIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.addName = text(r, "GameFontNormal", 12, INK, "LEFT", 240)
    r.addName:SetPoint("TOPLEFT", 40, -4)
    r.cutName = text(r, "GameFontNormalSmall", 10, INK_SOFT, "LEFT", 240)
    r.cutName:SetPoint("TOPLEFT", 40, -21)
    r.gain = text(r, "GameFontNormal", 13, GOOD, "RIGHT", 52)
    r.gain:SetPoint("RIGHT", -4, 0)
    r:SetScript("OnClick", function(self)
      local q = self.add
      if not q then return end
      if IsShiftKeyDown and IsShiftKeyDown() then UI.QuestClick(q, QB:Status(q)) return end
      if q.give and not q.give.inside then QB.API.SetWaypoint(q.give.m, q.give.x, q.give.y, q.give.n) end
    end)
    tooltip(r, function(tip, self)
      if self.cutTitle then
        tip:AddLine("Drop: " .. self.cutTitle, 1, 0.5, 0.4)
        tip:AddLine(QB.Comma(self.cutValue or 0) .. " XP on the day", 0.8, 0.8, 0.8)
        tip:AddLine(" ")
      end
      if self.add then UI.QuestTooltip(tip, self.add, QB:Status(self.add), self.addValue) end
      tip:AddLine("Click: pin the quest giver.  Shift-click: add it to the plan.", 0.5, 0.5, 0.5)
    end)
    v.swaps[i] = r
  end
  v.noSwaps = para(v, "GameFontNormal", 12, INK_SOFT, 320)
  v.noSwaps:SetPoint("TOPLEFT", RIGHT, -58)
  v.legend = text(v, "GameFontNormalSmall", 10, INK_SOFT, "LEFT", 334)
  v.legend:SetPoint("TOPLEFT", RIGHT, -376)
  v.legend:SetText("|cffff8000Orange|r 12k+  |cffa335eePurple|r 9k+  |cff0070ddBlue|r 6k+  |cff1eff00Green|r 3k+  White 1.5k+")
  v.Refresh = function() UI:RefreshLogView(v) end
  return v
end

-- the best quests to fetch: for your faction and class, not done, not held, most XP on the day first
function UI:Candidates(limit, level)
  local D = QB.Data
  local s = QB.state
  level = math.max(level or s.level, 20)
  local fac = QB.faction
  local bit = QB.API.ClassBit()
  local out = {}
  for id, r in pairs(D.Q) do
    local side, cls = r[3], r[9]
    if (side == 0 or (side == 1 and fac == "A") or (side == 2 and fac == "H"))
      and (cls == 0 or bit == 0 or math.floor(cls / bit) % 2 == 1)
      and r[2] <= math.max(s.level, 20) and r[1] >= level - 7 and not s.log[id] and not D.FOLLOW[id] then
      local live = QuestBankDB.live and QuestBankDB.live[id]
      out[#out + 1] = { id = id, full = live and live.full or math.floor(r[4] * r[5] + 0.5), lvl = r[1], cat = r[8] }
    end
  end
  for _, c in ipairs(out) do
    local m = level - c.lvl
    local f = c.full
    if m >= 10 then f = f * 0.1 elseif m >= 6 then f = f * (1 - (m - 5) * 0.2) end
    c.value = f
  end
  table.sort(out, function(a, b) return a.value > b.value end)
  local kept = {}
  for _, c in ipairs(out) do
    if not QB.API.IsDone(c.id) then
      kept[#kept + 1] = c
      if limit and #kept >= limit then break end
    end
  end
  return kept
end

function UI:RefreshLogView(v)
  local s = QB.state
  local entries, total = {}, 0
  for _, e in ipairs(s.logOrder) do
    local q = Q.Get(e.id)
    local value = q and QB:Value(e.id) or nil
    local it = { e = e, q = q, value = value }
    if q then
      it.st = QB:Status(q)
      it.cut = QB:IsCut(e.id)
      if not it.cut then total = total + (value or 0) end
    end
    entries[#entries + 1] = it
  end
  table.sort(entries, function(a, b)
    if (a.cut or false) ~= (b.cut or false) then return not a.cut end
    return (a.value or -1) > (b.value or -1)
  end)
  v.title:SetText(string.format("Quest log  %d/40", #entries))
  v.worth:SetText(string.format("worth about %s XP on the day", QB.Comma(total)))
  for i, b in ipairs(v.slots) do
    local it = entries[i]
    b.q, b.st, b.entry, b.value, b.pct, b.plvl = nil, nil, nil, nil, nil, nil
    if it then
      b.entry, b.value = it.e, it.value
      if it.q then b.q, b.st = it.q, it.st end
      setIcon(b.icon, it.q and it.q.icon or (it.e.complete and T.questActive or T.questAvail))
      b.icon:SetDesaturated(it.cut or false)
      local c = QUALITY[tier(it.value)]
      b.frame:SetVertexColor(c[1], c[2], c[3])
      b.frame:SetShown(not it.cut)
      b.xp:SetText(it.value and QB.Short(it.value) or "?")
      if it.cut or not it.q then
        b.mark:SetTexture(T.notready)
      elseif it.e.complete then
        b.mark:SetTexture(T.ready)
      else
        b.mark:SetTexture(T.waiting)
      end
      b.mark:Show()
    else
      b.icon:SetTexture(nil)
      b.frame:Hide()
      b.xp:SetText("")
      b.mark:Hide()
    end
  end

  -- bags: the sleeping bag, and quests that wait in your bags
  local bagItems = {}
  for _, it in ipairs(QB.Data.TRACKED_ITEMS) do
    if not it.side or (it.side == 1 and QB.faction == "A") or (it.side == 2 and QB.faction == "H") then
      local q = it.quest and Q.Get(it.quest)
      if not (q and QB.API.IsDone(q.id)) then
        bagItems[#bagItems + 1] = { id = it.id, name = it.name, need = it.need, icon = it.icon, q = q }
      end
    end
  end
  for id in pairs(s.bagStarts) do
    local q = Q.Get(id)
    local dup = false
    for _, b in ipairs(bagItems) do if b.q and b.q.id == id then dup = true end end
    if q and not dup then bagItems[#bagItems + 1] = { id = q.bag and q.bag[1], name = q.name, q = q, icon = q.icon } end
  end
  for i, b in ipairs(v.bagSlots) do
    local it = bagItems[i]
    b.item = it
    if it then
      local n = it.id and QB.API.ItemCount(it.id) or 1
      setIcon(b.icon, QB.API.ItemIcon(it.id, it.icon))
      b.icon:SetDesaturated(n == 0)
      b.count:SetText((it.need and it.need > 1) and (n .. "/" .. it.need) or "")
      b:Show()
    else
      b:Hide()
    end
  end

  -- quests that left the log without a hand-in, and quests the catalog can't place
  local p = QB:Plan()
  local lines = {}
  for _, r in pairs(p.removed) do
    lines[#lines + 1] = r.title .. (r.value and ("  " .. QB.Short(r.value)) or "")
  end
  table.sort(lines)
  local unknown = QB:Unknown()
  v.dropTitle:SetShown(#lines > 0 or #unknown > 0)
  v.dropClear:SetShown(#lines > 0)
  if #lines > 0 then
    v.dropTitle:SetText("Left your log without a hand-in")
    local shown = {}
    for i = 1, math.min(3, #lines) do shown[i] = lines[i] end
    local extra = #lines > 3 and string.format("  and %d more", #lines - 3) or ""
    v.drops:SetText(table.concat(shown, ",  ") .. extra)
  elseif #unknown > 0 then
    v.dropTitle:SetText("Not in QuestBank's catalog")
    local names = {}
    for i = 1, math.min(4, #unknown) do names[i] = unknown[i].title end
    v.drops:SetText(table.concat(names, ",  ") .. ". The route can't place them.")
  else
    v.drops:SetText("")
  end

  -- swaps: advance a chain you hold, fill a free slot, or swap a weak quest for a better one
  local lvl = math.max(s.level, 20)
  local rows, used = {}, {}
  -- a chain you hold: the best later step you could bank instead
  for _, it in ipairs(entries) do
    if it.q and it.q.nextSteps and not it.cut then
      local best, bestV, bestDepth
      local function walk(q, depth)
        if depth > 3 or not q.nextSteps then return end
        for _, nid in ipairs(q.nextSteps) do
          local nq = Q.Get(nid)
          if nq and Q.ForMe(nq) and not QB.API.IsDone(nid) and not s.log[nid] and (nq.req or 1) <= lvl then
            local v = QB.Model.XpAt(nq, lvl)
            if not bestV or v > bestV then best, bestV, bestDepth = nq, v, depth end
            walk(nq, depth + 1)
          end
        end
      end
      walk(it.q, 1)
      if best and bestV > (it.value or 0) + 300 then
        rows[#rows + 1] = { add = { q = best, value = bestV }, cut = it, cutValue = it.value or 0, gain = bestV - (it.value or 0),
                            chain = bestDepth }
        used[best.id] = true
      end
    end
  end
  local cuts = {}
  for _, it in ipairs(entries) do
    if it.cut or not it.q or (it.value or 0) < 1500 then cuts[#cuts + 1] = it end
  end
  table.sort(cuts, function(a, b)
    if (a.cut or false) ~= (b.cut or false) then return a.cut end
    return (a.value or 0) < (b.value or 0)
  end)
  local adds = {}
  for _, c in ipairs(self:Candidates(40)) do
    local q = Q.Get(c.id)
    local st = q and QB:Status(q)
    -- quests you can pick up now and that need a log slot; chains and bag quests live on the Prep page
    if q and not used[q.id] and st.code == "todo" and not (q.bag and q.bag[3] == 1) then
      adds[#adds + 1] = { q = q, value = QB.Model.XpAt(q, lvl), st = st }
    end
  end
  local ai = 1
  for _ = 1, 40 - #entries do
    if adds[ai] then rows[#rows + 1] = { add = adds[ai], cutValue = 0, gain = adds[ai].value }; ai = ai + 1 end
  end
  for _, c in ipairs(cuts) do
    local a = adds[ai]
    if not a then break end
    local cv = c.cut and 0 or (c.value or 0)
    if a.value > cv + 300 then
      rows[#rows + 1] = { cut = c, add = a, cutValue = cv, gain = a.value - cv }
      ai = ai + 1
    end
  end
  table.sort(rows, function(a, b) return a.gain > b.gain end)
  for i, r in ipairs(v.swaps) do
    local d = rows[i]
    if d then
      r:Show()
      r.add, r.addValue = d.add.q, d.add.value
      r.cutTitle = d.cut and d.cut.e.title or nil
      r.cutValue = d.cutValue
      if d.chain then
        r.cutName:SetText("hand in " .. d.cut.e.title .. " now, " .. (d.chain > 1 and string.format("%d steps on", d.chain) or "bank the next step"))
      else
        r.cutName:SetText(d.cut and ("instead of " .. d.cut.e.title .. (d.cutValue > 0 and ("  " .. QB.Short(d.cutValue)) or "")) or "into a free slot")
      end
      setIcon(r.addIcon, d.add.q.icon)
      r.addName:SetText(d.add.q.name)
      r.gain:SetText("+" .. QB.Short(d.gain))
    else
      r:Hide()
    end
  end
  v.noSwaps:SetShown(#rows == 0)
  v.noSwaps:SetText("No swap gains XP right now. Everything in your log earns its slot.")
end

----------------------------------------------------------------------------
-- page 2: prep
----------------------------------------------------------------------------
local function makeRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(22)
  r.hi = tex(r, "HIGHLIGHT", T.rowHi)
  r.hi:SetAllPoints()
  r.hi:SetBlendMode("ADD")
  r.mark = tex(r, "ARTWORK", nil, 14, 14)
  r.mark:SetPoint("LEFT", 4, 0)
  r.icon = tex(r, "ARTWORK", nil, 18, 18)
  r.icon:SetPoint("LEFT", 22, 0)
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.name = text(r, "GameFontNormal", 12, INK, "LEFT", 262)
  r.name:SetPoint("LEFT", 46, 0)
  r.lvl = text(r, "GameFontNormalSmall", 10, INK_SOFT, "LEFT", 30)
  r.lvl:SetPoint("LEFT", 314, 0)
  r.status = text(r, "GameFontNormalSmall", 11, INK, "LEFT", 250)
  r.status:SetPoint("LEFT", 348, 0)
  r.xp = text(r, "GameFontNormal", 12, INK, "RIGHT", 60)
  r.xp:SetPoint("RIGHT", -8, 0)
  r:SetScript("OnClick", function(self)
    if self.q then UI.QuestClick(self.q, self.st)
    elseif self.step and self.step.m then QB.API.SetWaypoint(self.step.m, self.step.x, self.step.y, self.step.name) end
  end)
  tooltip(r, function(tip, self)
    if self.q then
      UI.QuestTooltip(tip, self.q, self.st, self.value)
    elseif self.entry then
      tip:AddLine(self.entry.title, GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine(self.advice or "", 1, 0.55, 0.45, true)
    elseif self.step then
      tip:AddLine(self.step.name, GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine(self.step.where, 1, 1, 1, true)
      if self.step.m then tip:AddLine("Click: map pin.", 0.5, 0.5, 0.5) end
    end
  end)
  return r
end

local function makeCard(parent)
  local c = CreateFrame("Frame", nil, parent, BD)
  backdrop(c, nil, T.tipBorder, 12, 3)
  if c.SetBackdropBorderColor then c:SetBackdropBorderColor(0.45, 0.33, 0.16, 0.9) end
  c.art = tex(c, "BACKGROUND")
  c.art:SetPoint("TOPLEFT", 3, -3)
  c.art:SetPoint("TOPRIGHT", -3, -3)
  c.art:SetHeight(42)
  c.shade = tex(c, "BORDER")
  c.shade:SetColorTexture(0.06, 0.04, 0.02, 0.55)
  c.shade:SetAllPoints(c.art)
  c.icon = tex(c, "ARTWORK", nil, 32, 32)
  c.icon:SetPoint("TOPLEFT", 10, -8)
  c.title = text(c, "GameFontNormalLarge", 15, GOLD, "LEFT", 380)
  c.title:SetPoint("TOPLEFT", 50, -9)
  c.where = text(c, "GameFontHighlightSmall", 11, WHITE, "LEFT", 420)
  c.where:SetPoint("TOPLEFT", 50, -28)
  c.gain = text(c, "GameFontNormalLarge", 15, GOLD, "RIGHT", 150)
  c.gain:SetPoint("TOPRIGHT", -40, -9)
  c.count = text(c, "GameFontHighlightSmall", 11, WHITE, "RIGHT", 150)
  c.count:SetPoint("TOPRIGHT", -40, -28)
  c.pin = CreateFrame("Button", nil, c)
  c.pin:SetSize(20, 20)
  c.pin:SetPoint("TOPRIGHT", -12, -12)
  c.pin.t = tex(c.pin, "ARTWORK", T.mapPin)
  c.pin.t:SetAllPoints()
  c.pin:SetHighlightTexture(T.hilite, "ADD")
  c.pin:SetScript("OnClick", function(self)
    local e = self.entrance
    if e then QB.API.SetWaypoint(e.m, e.x, e.y, self.label) end
  end)
  tooltip(c.pin, function(tip, self) tip:AddLine("Map pin: " .. (self.label or ""), GOLD[1], GOLD[2], GOLD[3]) end)
  c.rows = pool(c, makeRow)
  c.more = CreateFrame("Button", nil, c)
  c.more:SetSize(400, 18)
  c.more.label = text(c.more, "GameFontNormalSmall", 11, { 0.45, 0.25, 0.05 }, "LEFT", 400)
  c.more.label:SetPoint("LEFT", 0, 0)
  c.more:SetScript("OnClick", function(self)
    UI.expanded = UI.expanded or {}
    UI.expanded[self.key] = not UI.expanded[self.key] or nil
    UI:Refresh()
  end)
  return c
end

local MARK = { done = "notready", banked = "ready", active = "waiting", partial = "waiting", bagstart = "waiting", follow = "ready" }

local function fillRow(r, q, st, width, value)
  r.q, r.st, r.entry, r.step, r.value = q, st, nil, nil, value
  r:SetWidth(width)
  local planned = QB:InPlan(q, st)
  r.mark:SetTexture(MARK[st.code] and T[MARK[st.code]] or (planned and T.questActive or T.questAvail))
  setIcon(r.icon, q.icon)
  r.icon:SetDesaturated(st.code == "done" or st.code == "locked")
  r.name:SetText(q.name)
  local c = planned and INK or INK_SOFT
  r.name:SetTextColor(c[1], c[2], c[3])
  r.lvl:SetText("L" .. q.lvl)
  r.status:SetWidth(math.max(120, width - 348 - 76))
  r.status:SetText((planned and st.code ~= "banked" and st.code ~= "active") and ("In the plan. " .. st.text) or st.text)
  local sc = STATUS[st.code] or INK
  r.status:SetTextColor(sc[1], sc[2], sc[3])
  r.xp:SetText(QB.Comma(value or Q.Full(q)))
end

function UI:CreatePrepView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()
  v.scroll = scrollArea(v)
  v.cards = pool(v.scroll.child, makeCard)
  v.Refresh = function() UI:RefreshPrepView(v) end
  return v
end

local PER_CARD = 8
function UI:RefreshPrepView(v)
  local D = QB.Data
  local s = QB.state
  local level = math.max(s.level, 20)
  local width = v.scroll:Width() - 6
  v.cards:Reset()

  -- quests by category: what you hold or planned, then the best you could fetch
  local groups, order = {}, {}
  local function group(cat)
    local g = groups[cat]
    if not g then
      g = { cat = D.CAT[cat], quests = {}, left = 0, score = 0, banked = 0, total = 0, planned = 0 }
      groups[cat] = g
      order[#order + 1] = g
    end
    return g
  end
  local seen = {}
  local function add(q, mine)
    if seen[q.id] then return end
    seen[q.id] = true
    local st = QB:Status(q)
    if st.code == "wrong" then return end
    local value = QB.Model.XpAt(q, level)
    local g = group(D.Q[q.id][8])
    local planned = QB:InPlan(q, st)
    g.quests[#g.quests + 1] = { q = q, st = st, value = value, planned = planned }
    if planned then
      g.total = g.total + 1
      if st.code == "banked" then g.banked = g.banked + 1 else g.left = g.left + value; g.planned = g.planned + 1 end
      g.score = g.score + value
    elseif st.code ~= "done" and not mine then
      g.score = g.score + value * 0.25
    end
  end
  for _, e in ipairs(s.logOrder) do local q = Q.Get(e.id); if q then add(q, true) end end
  for id in pairs(QB:Plan().add) do local q = Q.Get(id); if q then add(q, true) end end
  for id in pairs(D.BAGQ) do
    local q = Q.Get(id)
    if q and Q.ForMe(q) and (q.bag[3] ~= 1 or QB.API.ItemCount(q.bag[1]) > 0) then add(q, true) end
  end
  local extra = {}
  for _, c in ipairs(self:Candidates(nil, level)) do
    extra[c.cat] = (extra[c.cat] or 0) + 1
    local open = UI.expanded and D.CAT[c.cat] and UI.expanded[D.CAT[c.cat].key]
    if open or extra[c.cat] <= PER_CARD + 6 then add(Q.Get(c.id)) end
  end
  table.sort(order, function(a, b) return a.score > b.score end)

  local y = 0
  local function place(card, h)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", v.scroll.child, "TOPLEFT", 0, -y)
    card:SetSize(width, h)
    y = y + h + 8
  end
  local function header(c, art, icon, title, where, gain, count)
    c.rows:Reset()
    if type(art) == "table" then c.art:SetColorTexture(art[1], art[2], art[3], 1); c.art:SetTexCoord(0, 1, 0, 1)
    else c.art:SetTexture(art); c.art:SetTexCoord(0, 1, 0.18, 0.5) end
    c.icon:SetTexture(icon)
    c.title:SetText(title)
    c.where:SetText(where)
    c.gain:SetText(gain)
    c.gain:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    c.count:SetText(count or "")
    c.pin:Hide()
    c.more:Hide()
    c:SetAlpha(1)
  end

  -- make room: quests you cut, and quests that pay next to nothing on the day
  local cutList = {}
  for _, e in ipairs(s.logOrder) do
    local q = Q.Get(e.id)
    local value = q and QB.Model.XpAt(q, level)
    if not q or QB:IsCut(e.id) or (value and value < 500) then cutList[#cutList + 1] = { e = e, q = q, value = value } end
  end
  if #cutList > 0 then
    local c = v.cards:Get()
    header(c, { 0.30, 0.08, 0.05 }, T.notready, "Make room", "Cut from the plan, unknown, or next to no XP on the day. Hand in or abandon them.",
      #cutList .. (#cutList == 1 and " slot" or " slots"))
    local ry = 50
    for _, it in ipairs(cutList) do
      local r = c.rows:Get()
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 4, -ry)
      r:SetWidth(width - 8)
      r.q, r.st, r.step = nil, nil, nil
      r.entry = it.e
      local note = D.CUT_NOTES[it.e.id]
      r.advice = note or (not it.q and "Not in QuestBank's catalog." or QB:IsCut(it.e.id) and "You cut it from the plan."
        or "Pays next to nothing at level " .. level .. ".")
      r.mark:SetTexture(it.e.complete and T.ready or T.notready)
      setIcon(r.icon, it.q and it.q.icon or T.questAvail)
      r.icon:SetDesaturated(true)
      r.name:SetText(it.e.title)
      r.name:SetTextColor(INK[1], INK[2], INK[3])
      r.lvl:SetText(it.e.level and ("L" .. it.e.level) or "")
      r.status:SetWidth(math.max(120, width - 348 - 76))
      r.status:SetText(note or (it.e.complete and "Complete: hand it in now" or "Open: abandon it"))
      r.status:SetTextColor(BAD[1], BAD[2], BAD[3])
      r.xp:SetText(it.value and QB.Comma(it.value) or "?")
      ry = ry + 22
    end
    c.rows:HideRest()
    place(c, ry + 8)
  end

  -- the sleeping bag chain
  do
    local c = v.cards:Get()
    local have = QB.API.ItemCount(211527) > 0
    header(c, { 0.10, 0.12, 0.22 }, T.sleep, "Cozy Sleeping Bag",
      have and "You have it. Lie in it three minutes before the first hand-in." or "Finish the Stepping Stones chain: +3% XP from quests for two hours.",
      have and "Done" or "+3%")
    local nextStep
    for _, step in ipairs(D.SLEEP_CHAIN) do
      if not QB.API.IsDone(step.id) then nextStep = step break end
    end
    c.pin:SetShown(nextStep and nextStep.m and true or false)
    if nextStep then c.pin.entrance = nextStep.m and { m = nextStep.m, x = nextStep.x, y = nextStep.y } or nil; c.pin.label = nextStep.where end
    local ry = 50
    if not have then
      for _, step in ipairs(D.SLEEP_CHAIN) do
        local r = c.rows:Get()
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 4, -ry)
        r:SetWidth(width - 8)
        r.q, r.st, r.entry = nil, nil, nil
        r.step = step
        local done = QB.API.IsDone(step.id)
        r.mark:SetTexture(done and T.ready or (s.log[step.id] and T.waiting or T.questAvail))
        setIcon(r.icon, T.map)
        r.icon:SetDesaturated(done)
        r.name:SetText(step.name)
        r.name:SetTextColor(INK[1], INK[2], INK[3])
        r.lvl:SetText("")
        r.status:SetWidth(math.max(120, width - 348 - 76))
        r.status:SetText(done and "Done" or step.where)
        local sc = done and GOOD or INK_SOFT
        r.status:SetTextColor(sc[1], sc[2], sc[3])
        r.xp:SetText("")
        ry = ry + 22
      end
    end
    c.rows:HideRest()
    place(c, ry + 8)
  end

  for n, g in ipairs(order) do
    if n > 14 and g.total == 0 then break end
    local c = v.cards:Get()
    local a = g.cat
    header(c, a.bg or { 0.16, 0.12, 0.08 }, a.icon, a.name, a.dungeon and ((a.where ~= "" and (a.where .. ". ") or "") .. "Dungeon quests: bring a group.") or a.where,
      g.planned > 0 and ("+" .. QB.Comma(math.floor(g.left / 10 + 0.5) * 10)) or (g.total > 0 and "All banked" or ""),
      g.total > 0 and string.format("%d of %d banked", g.banked, g.total) or "Nothing planned here yet")
    if g.total > 0 and g.planned == 0 then c.gain:SetTextColor(0.4, 0.9, 0.4) end
    c.pin:SetShown(a.entrance and true or false)
    c.pin.entrance, c.pin.label = a.entrance, a.name .. " entrance"
    table.sort(g.quests, function(x, z)
      if x.planned ~= z.planned then return x.planned end
      return x.value > z.value
    end)
    local ry = 50
    local shown, extra, hidden = 0, 0, 0
    local open = UI.expanded and UI.expanded[a.key]
    for _, it in ipairs(g.quests) do
      local show = it.planned
      if not show and it.st.code ~= "done" then
        show = open or extra < PER_CARD
        if show then extra = extra + 1 else hidden = hidden + 1 end
      end
      if show then
        local r = c.rows:Get()
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 4, -ry)
        fillRow(r, it.q, it.st, width - 8, it.value)
        ry = ry + 22
        shown = shown + 1
      end
    end
    if hidden > 0 or open then
      c.more:ClearAllPoints()
      c.more:SetPoint("TOPLEFT", 46, -ry - 2)
      c.more.key = a.key
      c.more.label:SetText(open and "Show only the best" or string.format("Show %d more here (they pay less)", hidden))
      c.more:Show()
      ry = ry + 20
    end
    c.rows:HideRest()
    place(c, ry + 8)
  end
  v.cards:HideRest()
  v.scroll:SetContentHeight(y)
end

----------------------------------------------------------------------------
-- page 3: hand-in route
----------------------------------------------------------------------------
local KIND = {
  start = "Start here", hearth = "Hearthstone", flight = "Flight", foot = "On foot", tram = "Deeprun Tram", boat = "Boat",
  zeppelin = "Zeppelin", portal = "Portal", done = "Handed in",
}

local function makeLeg(parent)
  local l = CreateFrame("Frame", nil, parent)
  l.line = tex(l, "BACKGROUND")
  l.line:SetColorTexture(0.55, 0.42, 0.2, 0.6)
  l.line:SetWidth(2)
  l.line:SetPoint("TOPLEFT", 51, 0)
  l.line:SetPoint("BOTTOMLEFT", 51, 0)
  l.divider = text(l, "GameFontNormal", 12, BAD, "LEFT", 400)
  l.divider:SetPoint("TOPLEFT", 70, -4)
  l.node = tex(l, "ARTWORK", T.taxiGray, 18, 18)
  l.clock = text(l, "GameFontNormal", 12, INK, "RIGHT", 40)
  l.travelIcon = tex(l, "ARTWORK", nil, 16, 16)
  l.travel = text(l, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", 300)
  l.name = text(l, "GameFontNormalLarge", 15, INK, "LEFT", 330)
  l.level = text(l, "GameFontNormal", 12, INK_SOFT, "RIGHT", 150)
  l.pin = CreateFrame("Button", nil, l)
  l.pin:SetSize(18, 18)
  l.pin.t = tex(l.pin, "ARTWORK", T.mapPin)
  l.pin.t:SetAllPoints()
  l.pin:SetHighlightTexture(T.hilite, "ADD")
  l.pin:SetScript("OnClick", function(self)
    local s = self.stop
    if s and s.m and s.m > 0 then QB.API.SetWaypoint(s.m, s.x, s.y, s.name) end
  end)
  tooltip(l.pin, function(tip, self) tip:AddLine("Waypoint: " .. (self.stop and self.stop.name or ""), GOLD[1], GOLD[2], GOLD[3]) end)
  l.note = text(l, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", 500)
  l.rows = {}
  return l
end

local function legRow(l, i)
  local r = l.rows[i]
  if r then r:Show() return r end
  r = CreateFrame("Button", nil, l)
  r:SetHeight(20)
  r.hi = tex(r, "HIGHLIGHT", T.rowHi)
  r.hi:SetAllPoints()
  r.hi:SetBlendMode("ADD")
  r.icon = tex(r, "ARTWORK", nil, 16, 16)
  r.icon:SetPoint("LEFT", 2, 0)
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.tick = tex(r, "OVERLAY", T.ready, 14, 14)
  r.tick:SetPoint("LEFT", 4, 0)
  r.name = text(r, "GameFontNormal", 12, INK, "LEFT", 290)
  r.name:SetPoint("LEFT", 24, 0)
  r.npc = text(r, "GameFontNormalSmall", 10, INK_SOFT, "LEFT", 170)
  r.npc:SetPoint("LEFT", 320, 0)
  r.xp = text(r, "GameFontNormal", 12, INK, "RIGHT", 110)
  r.xp:SetPoint("RIGHT", -6, 0)
  r:SetScript("OnClick", function(self) if self.q then UI.QuestClick(self.q, self.st) end end)
  tooltip(r, function(tip, self)
    if self.q then UI.QuestTooltip(tip, self.q, self.st, self.xpv, self.pct, self.plvl) end
    if self.doneXP then tip:AddLine(string.format("Handed in: +%s XP", QB.Comma(self.doneXP)), 0.4, 1, 0.4) end
  end)
  l.rows[i] = r
  return r
end

function UI:CreateRouteView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()
  v.modeNow = button(v, "Banked now", 110)
  v.modeNow:SetPoint("TOPLEFT", 14, -10)
  v.modePlan = button(v, "Full plan", 110)
  v.modePlan:SetPoint("TOPLEFT", 128, -10)
  v.modeNow:SetScript("OnClick", function() QB:Settings().routeMode = "now"; UI:Refresh() end)
  v.modePlan:SetScript("OnClick", function() QB:Settings().routeMode = "plan"; UI:Refresh() end)
  v.run = button(v, "Start run", 96)
  v.run:SetPoint("TOPRIGHT", -14, -10)
  v.run:SetScript("OnClick", function()
    if QB.Run.Get() then QB.Run.Stop() else QB:Recompute(true); QB.Run.Start() end
    UI:Refresh()
  end)
  tooltip(v.run, function(tip)
    if QB.Run.Get() then
      tip:AddLine("End the run", GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine("Saves it with its times and XP.", 1, 1, 1)
    else
      tip:AddLine("Start the hand-in run", GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine("Starts a clock, ticks each quest off with the XP it paid, and re-plans the rest from where you stand. The first hand-in above the old cap starts it by itself.", 1, 1, 1, true)
    end
  end)
  v.summary = text(v, "GameFontNormal", 12, INK, "RIGHT", 400)
  v.summary:SetPoint("TOPRIGHT", -118, -14)
  v.setup = para(v, "GameFontNormal", 12, INK, W - 64)
  v.setup:SetPoint("TOPLEFT", 16, -40)
  v.setup:SetHeight(30)
  local holder = CreateFrame("Frame", nil, v)
  holder:SetPoint("TOPLEFT", 0, -70)
  holder:SetPoint("BOTTOMRIGHT", 0, 0)
  v.scroll = scrollArea(holder)
  v.legs = pool(v.scroll.child, makeLeg)
  v.empty = para(v.scroll.child, "GameFontNormal", 13, INK_SOFT, 560)
  v.empty:SetPoint("TOPLEFT", 60, -20)
  v.Refresh = function() UI:RefreshRouteView(v) end
  return v
end

local function travelIcon(kind)
  if kind == "hearth" then return T.hearth elseif kind == "flight" then return QB.faction == "H" and T.wyvern or T.gryphon
  elseif kind == "boat" then return T.boat elseif kind == "tram" then return T.tram elseif kind == "zeppelin" then return T.zeppelin
  elseif kind == "portal" then return T.portal elseif kind == "start" then return T.book elseif kind == "done" then return T.ready end
  return QB:Mounted() and T.mount or T.foot
end

-- one leg: the clock, how you get there, the stop, and the quests handed in there
local function layLeg(l, width, y, parent)
  l:ClearAllPoints()
  l:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
  l:SetWidth(width)
  local top = l.divider:IsShown() and 22 or 0
  l.node:ClearAllPoints(); l.node:SetPoint("TOPLEFT", 43, -8 - top)
  l.clock:ClearAllPoints(); l.clock:SetPoint("TOPLEFT", 0, -10 - top)
  l.travelIcon:ClearAllPoints(); l.travelIcon:SetPoint("TOPLEFT", 70, -6 - top)
  l.travel:ClearAllPoints(); l.travel:SetPoint("TOPLEFT", 92, -7 - top)
  l.name:ClearAllPoints(); l.name:SetPoint("TOPLEFT", 70, -24 - top)
  l.level:ClearAllPoints(); l.level:SetPoint("TOPRIGHT", -34, -27 - top)
  l.pin:ClearAllPoints(); l.pin:SetPoint("TOPRIGHT", -8, -25 - top)
  l.note:ClearAllPoints(); l.note:SetPoint("TOPLEFT", 70, -44 - top)
  l.note:SetWidth(width - 110)
  return top
end

function UI:RefreshRouteView(v)
  local set = QB:Settings()
  local run = QB.Run.Get()
  local mode = run and "now" or (set.routeMode == "plan" and "plan" or "now")
  local r = mode == "plan" and QB.routePlan or QB.routeNow
  v.modeNow:SetEnabled(mode ~= "now")
  v.modePlan:SetEnabled(mode ~= "plan" and not run)
  v.run:SetText(run and "End run" or "Start run")
  local width = v.scroll:Width() - 6
  local busy = QB.Model.Busy() and "  |cff8a6a3aplanning...|r" or ""
  v.summary:SetText(string.format("%s XP  |  level %.2f  |  %d min  |  at 60 min %.2f%s",
    QB.Comma(r.xp or 0), r.level or 0, math.floor((r.t or 0) + 0.5), r.at60 or 0, busy))
  v.legs:Reset()

  -- the setup line: where to log out and where to bind, or how the run is going
  local line
  if run then
    local got, n = QB.Run.Totals()
    local pace = QB.Run.Pace()
    line = string.format("Run %s.  %d handed in, |cff0a6a0a+%s XP|r.", QB.Clock(QB.Run.Elapsed()), n, QB.Comma(got))
    if pace then
      if math.abs(pace) < 1 then line = line .. "  On pace."
      elseif pace > 0 then line = line .. string.format("  %.0f min ahead of the plan.", pace)
      else line = line .. string.format("  |cffa0400a%.0f min behind the plan.|r", -pace) end
    end
    if r.legs[1] then line = line .. "  Next: |cff7a2e0a" .. r.legs[1].stop.name .. "|r." end
  elseif r.legs and r.legs[1] then
    line = "Log out at |cff7a2e0a" .. r.legs[1].stop.name .. "|r."
    if r.bind then
      local bind = QB.API.BindName()
      line = line .. " Bind your hearthstone in |cff7a2e0a" .. r.bind.town .. "|r"
      if bind ~= "" and not (bind:find(r.bind.town, 1, true) or r.bind.town:find(bind, 1, true)) then line = line .. " (it is set to " .. bind .. ")" end
      line = line .. "."
    end
    if r.lateFrom and set.goal == "hour" then line = line .. " Stops after the first hour come last." end
  end
  v.setup:SetText(line or "")

  local y = 0
  local mapID = QB.state.mapID
  -- handed in during the run
  if run then
    local done = {}
    for id, d in pairs(run.done) do done[#done + 1] = { id = id, d = d } end
    table.sort(done, function(a, b) return (a.d.n or 0) < (b.d.n or 0) end)
    if #done > 0 then
      local l = v.legs:Get()
      l.divider:Hide()
      layLeg(l, width, y, v.scroll.child)
      l.node:SetTexture(T.taxiG)
      l.clock:SetText(QB.Clock(done[#done].d.t))
      l.travelIcon:SetTexture(T.ready)
      l.travel:SetText("Handed in so far")
      l.name:SetText(#done == 1 and "1 quest" or string.format("%d quests", #done))
      l.level:SetText("")
      l.pin:Hide()
      l.note:SetText("")
      local ry = 48
      for k, it in ipairs(done) do
        local rr = legRow(l, k)
        rr:ClearAllPoints()
        rr:SetPoint("TOPLEFT", 66, -ry)
        rr:SetWidth(width - 74)
        local q = Q.Get(it.id)
        rr.q, rr.st, rr.xpv, rr.pct, rr.plvl, rr.doneXP = q, q and { code = "done", text = "Handed in" }, nil, nil, nil, it.d.xp
        rr.icon:Hide()
        rr.tick:Show()
        rr.name:SetText(q and q.name or it.d.name or ("Quest " .. it.id))
        rr.name:SetTextColor(GOOD[1], GOOD[2], GOOD[3])
        rr.npc:SetText(QB.Clock(it.d.t))
        rr.xp:SetText("+" .. QB.Comma(it.d.xp or 0))
        ry = ry + 20
      end
      for k = #done + 1, #l.rows do l.rows[k]:Hide() end
      l:SetHeight(ry + 8)
      y = y + ry + 8
    end
  end

  if not r.legs or #r.legs == 0 then
    v.empty:SetText(run and "Everything banked is handed in. End the run to save it." or
      (mode == "now" and "Nothing is banked yet. Finished quests and quest items in your bags show up here in hand-in order. Full plan shows the route you're building towards." or
        "The plan is empty. Shift-click quests on the Prep page to add them."))
    v.empty:ClearAllPoints()
    v.empty:SetPoint("TOPLEFT", 60, -y - 20)
    v.empty:Show()
  else
    v.empty:Hide()
  end

  for i, leg in ipairs(r.legs or {}) do
    local l = v.legs:Get()
    local s = leg.stop
    local lateStart = leg.late and not (r.legs[i - 1] and r.legs[i - 1].late) and set.goal == "hour" and not run
    l.divider:SetShown(lateStart)
    l.divider:SetText("After the first hour")
    layLeg(l, width, y, v.scroll.child)
    l.node:SetTexture(i == 1 and T.taxiY or T.taxiGray)
    l.clock:SetText(QB.Clock(leg.t))
    local kind = leg.kind
    l.travelIcon:SetTexture(travelIcon(kind))
    local label = KIND[kind] or kind
    if kind == "start" then
      label = "Log in here"
    else
      label = label .. string.format(", about %d min", math.max(1, math.floor(leg.travel + 0.5)))
      if kind == "hearth" and leg.inn then label = label .. " to " .. QB.Data.HUB[r.fac][leg.inn][1] end
    end
    l.travel:SetText(label)
    local here = mapID and mapID == s.m and "  |cff0a6a0ayou are here|r" or ""
    l.name:SetText(s.name .. here)
    l.level:SetText(string.format("level %.1f > %.1f", leg.arrive, leg.leave))
    l.pin.stop = s
    l.pin:SetShown(s.m and s.m > 0)
    l.note:SetText("")
    local top = l.divider:IsShown() and 22 or 0
    local ry = 46 + top
    for k, row in ipairs(leg.rows) do
      local rr = legRow(l, k)
      rr:ClearAllPoints()
      rr:SetPoint("TOPLEFT", 66, -ry)
      rr:SetWidth(width - 74)
      rr.q, rr.st, rr.xpv, rr.pct, rr.plvl, rr.doneXP = row.q, row.e.st, row.xp, row.pct, row.plvl, nil
      rr.icon:Show()
      rr.tick:Hide()
      setIcon(rr.icon, row.q.icon)
      rr.name:SetText(row.q.name)
      local c = row.blocked and INK_SOFT or INK
      rr.name:SetTextColor(c[1], c[2], c[3])
      rr.npc:SetText(row.q.turn and row.q.turn.n or "")
      local xpText = QB.Comma(row.xp)
      if row.blocked then xpText = "|cffa0400aafter its first step|r"
      elseif row.pct < 100 then xpText = string.format("|cffa0400a%d%%|r  %s", row.pct, xpText) end
      rr.xp:SetText(xpText)
      ry = ry + 20
    end
    for k = #leg.rows + 1, #l.rows do l.rows[k]:Hide() end
    l:SetAlpha(leg.late and set.goal == "hour" and not run and 0.75 or 1)
    l:SetHeight(ry + 10)
    y = y + ry + 10
  end

  -- what the route could not place
  if r.unplaced and #r.unplaced > 0 then
    local l = v.legs:Get()
    l.divider:Hide()
    layLeg(l, width, y, v.scroll.child)
    l.node:SetTexture(T.taxiGray)
    l.clock:SetText("")
    l.travelIcon:SetTexture(T.unknown)
    l.travel:SetText("Not on the route")
    l.name:SetText(#r.unplaced .. (#r.unplaced == 1 and " quest" or " quests"))
    l.level:SetText("")
    l.pin:Hide()
    l.note:SetText("Handed in inside a dungeon, or where QuestBank has no position for the NPC. Hand them in on the way.")
    local ry = 64
    for k, e in ipairs(r.unplaced) do
      local rr = legRow(l, k)
      rr:ClearAllPoints()
      rr:SetPoint("TOPLEFT", 66, -ry)
      rr:SetWidth(width - 74)
      rr.q, rr.st, rr.xpv, rr.pct, rr.plvl, rr.doneXP = e.q, e.st, QB:Value(e.q.id), nil, nil, nil
      rr.icon:Show()
      rr.tick:Hide()
      setIcon(rr.icon, e.q.icon)
      rr.name:SetText(e.q.name)
      rr.name:SetTextColor(INK[1], INK[2], INK[3])
      rr.npc:SetText(e.q.turn and (e.q.turn.inside and (e.q.turn.n .. ", inside") or e.q.turn.n) or "NPC unknown")
      rr.xp:SetText(QB.Comma(rr.xpv or 0))
      ry = ry + 20
    end
    for k = #r.unplaced + 1, #l.rows do l.rows[k]:Hide() end
    l:SetAlpha(1)
    l:SetHeight(ry + 10)
    y = y + ry + 10
  end
  v.legs:HideRest()
  v.scroll:SetContentHeight(y + 10)
end

----------------------------------------------------------------------------
-- page 4: party
----------------------------------------------------------------------------
local function makeMember(parent)
  local m = CreateFrame("Button", nil, parent)
  m:SetHeight(40)
  m.hi = tex(m, "HIGHLIGHT", T.rowHi)
  m.hi:SetAllPoints()
  m.hi:SetBlendMode("ADD")
  m.class = tex(m, "ARTWORK", T.classes, 30, 30)
  m.class:SetPoint("LEFT", 6, 0)
  m.dot = tex(m, "OVERLAY", T.dotGreen, 12, 12)
  m.dot:SetPoint("BOTTOMRIGHT", m.class, "BOTTOMRIGHT", 3, -3)
  m.name = text(m, "GameFontNormal", 13, INK, "LEFT", 150)
  m.name:SetPoint("TOPLEFT", 44, -5)
  m.sub = text(m, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", 150)
  m.sub:SetPoint("TOPLEFT", 44, -22)
  m.bank = text(m, "GameFontNormal", 12, INK, "LEFT", 150)
  m.bank:SetPoint("TOPLEFT", 196, -5)
  m.run = text(m, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", 150)
  m.run:SetPoint("TOPLEFT", 196, -22)
  m.copy = iconButton(m, 24, T.letter)
  m.copy:SetPoint("RIGHT", -10, 0)
  m.copy:SetScript("OnClick", function(self)
    local n = QB.Sync and QB.Sync:CopyPlan(self:GetParent().who) or 0
    QB:Print(n > 0 and string.format("Added %d of their quests to your plan.", n) or "Nothing of theirs fits your plan.")
    UI:Refresh()
  end)
  tooltip(m.copy, function(tip)
    tip:AddLine("Copy their plan", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Adds the quests they are banking that you can do too.", 1, 1, 1, true)
  end)
  tooltip(m, function(tip, self) if QB.Sync then QB.Sync:MemberTooltip(tip, self.who) end end)
  return m
end

local function makeRun(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(46)
  r.hi = tex(r, "HIGHLIGHT", T.rowHi)
  r.hi:SetAllPoints()
  r.hi:SetBlendMode("ADD")
  r.icon = tex(r, "ARTWORK", nil, 32, 32)
  r.icon:SetPoint("TOPLEFT", 4, -6)
  r.name = text(r, "GameFontNormal", 13, INK, "LEFT", 220)
  r.name:SetPoint("TOPLEFT", 42, -6)
  r.gain = text(r, "GameFontNormal", 12, GOOD, "RIGHT", 90)
  r.gain:SetPoint("TOPRIGHT", -6, -6)
  r.who = text(r, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", 290)
  r.who:SetPoint("TOPLEFT", 42, -24)
  r:SetScript("OnClick", function(self)
    local e = self.cat and self.cat.entrance
    if e then QB.API.SetWaypoint(e.m, e.x, e.y, self.cat.name .. " entrance") end
  end)
  tooltip(r, function(tip, self)
    if not self.data then return end
    tip:AddLine(self.cat.name, GOLD[1], GOLD[2], GOLD[3])
    for _, p in ipairs(self.data.people) do
      tip:AddDoubleLine(p.name, string.format("%d quests, %s XP", p.n, QB.Comma(p.xp)), 1, 1, 1, 0.6, 1, 0.6)
    end
    if self.cat.entrance then tip:AddLine("Click: pin the entrance.", 0.5, 0.5, 0.5) end
  end)
  return r
end

function UI:CreatePartyView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()
  v.title = text(v, "GameFontNormalLarge", 15, INK, "LEFT", 380)
  v.title:SetPoint("TOPLEFT", LEFT, -12)
  v.hint = para(v, "GameFontNormalSmall", 11, INK_SOFT, 380)
  v.hint:SetPoint("TOPLEFT", LEFT, -32)
  v.hint:SetHeight(30)
  v.members = pool(v, makeMember)
  v.empty = para(v, "GameFontNormal", 12, INK_SOFT, 380)
  v.empty:SetPoint("TOPLEFT", LEFT, -72)
  v.sharePartyBtn = button(v, "Party: on", 96)
  v.sharePartyBtn:SetPoint("BOTTOMLEFT", LEFT, 12)
  v.sharePartyBtn:SetScript("OnClick", function() local s = QB:Settings().share; s.party = not s.party; UI:Refresh() end)
  v.shareGuildBtn = button(v, "Guild: on", 96)
  v.shareGuildBtn:SetPoint("BOTTOMLEFT", LEFT + 102, 12)
  v.shareGuildBtn:SetScript("OnClick", function() local s = QB:Settings().share; s.guild = not s.guild; UI:Refresh() end)
  v.syncBtn = button(v, "Send now", 96)
  v.syncBtn:SetPoint("BOTTOMLEFT", LEFT + 204, 12)
  v.syncBtn:SetScript("OnClick", function() if QB.Sync then QB.Sync:Broadcast(true) end end)
  tooltip(v.syncBtn, function(tip)
    tip:AddLine("Share your bank now", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Sends your level, banked XP and plan to QuestBank users in your party and guild. /qb sync Name whispers one friend.", 1, 1, 1, true)
  end)

  v.runTitle = text(v, "GameFontNormalLarge", 15, INK, "LEFT", 330)
  v.runTitle:SetPoint("TOPLEFT", RIGHT, -12)
  v.runTitle:SetText("Run together")
  v.runHint = para(v, "GameFontNormalSmall", 11, INK_SOFT, 330)
  v.runHint:SetPoint("TOPLEFT", RIGHT, -32)
  v.runHint:SetHeight(30)
  v.runHint:SetText("Dungeons where you and the people below still have quests to bank.")
  v.runs = pool(v, makeRun)
  v.noRuns = para(v, "GameFontNormal", 12, INK_SOFT, 330)
  v.noRuns:SetPoint("TOPLEFT", RIGHT, -72)
  v.Refresh = function() UI:RefreshPartyView(v) end
  return v
end

function UI:RefreshPartyView(v)
  local S = QB.Sync
  local share = QB:Settings().share
  v.sharePartyBtn:SetText(share.party and "Party: on" or "Party: off")
  v.shareGuildBtn:SetText(share.guild and "Guild: on" or "Guild: off")
  local members = S and S:Members() or {}
  v.title:SetText(#members > 0 and string.format("QuestBank users  %d", #members) or "QuestBank users")
  v.hint:SetText("Everyone here shares their level, banked XP and plan. Hover a name for their bank.")
  v.members:Reset()
  for i, m in ipairs(members) do
    if i > 8 then break end
    local row = v.members:Get()
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", LEFT - 4, -66 - (i - 1) * 42)
    row:SetWidth(390)
    row.who = m.key
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[m.class or ""]
    if coords then row.class:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) else row.class:SetTexCoord(0, 0.25, 0, 0.25) end
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.class or ""]
    row.name:SetText(m.name or m.key)
    if cc then row.name:SetTextColor(cc.r * 0.7, cc.g * 0.7, cc.b * 0.7) else row.name:SetTextColor(INK[1], INK[2], INK[3]) end
    row.sub:SetText(string.format("Level %s %s", m.level or "?", m.fac == "H" and "Horde" or "Alliance"))
    row.bank:SetText(string.format("Banked %.1f, plan %.1f", m.banked or 0, m.plan or 0))
    if m.runStart then
      row.run:SetText(string.format("Running %s, %d in, +%s", QB.Clock(m.runMin or 0), m.runN or 0, QB.Short(m.runXP or 0)))
      row.run:SetTextColor(GOOD[1], GOOD[2], GOOD[3])
    else
      row.run:SetText(m.age and m.age > 90 and string.format("Seen %d min ago", math.floor(m.age / 60)) or "Online")
      row.run:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
    end
    row.dot:SetTexture(m.age and m.age > 600 and T.dotGray or (m.runStart and T.dotYellow or T.dotGreen))
    row.copy:SetShown(m.fac == QB.faction and m.quests ~= nil)
  end
  v.members:HideRest()
  v.empty:SetShown(#members == 0)
  v.empty:SetText("Nobody with QuestBank in your party or guild yet. When friends install it and group up, their banks show here and you can plan dungeon runs together. To share with one friend outside your group: /qb sync Name")

  local runs = S and S:GroupRuns() or {}
  v.runs:Reset()
  for i, d in ipairs(runs) do
    if i > 7 then break end
    local r = v.runs:Get()
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", RIGHT - 4, -66 - (i - 1) * 48)
    r:SetWidth(340)
    r.cat, r.data = d.cat, d
    r.icon:SetTexture(d.cat.icon)
    r.name:SetText(d.cat.name)
    r.gain:SetText("+" .. QB.Short(d.xp))
    local names = {}
    for _, p in ipairs(d.people) do names[#names + 1] = string.format("%s %d", p.name, p.n) end
    r.who:SetText(table.concat(names, ",  "))
  end
  v.runs:HideRest()
  v.noRuns:SetShown(#runs == 0)
  v.noRuns:SetText(#members == 0 and "Group runs show up when other QuestBank users share their plans." or "No dungeon has quests for two of you yet.")
end

----------------------------------------------------------------------------
-- minimap button
----------------------------------------------------------------------------
local MB = {}
QB.Minimap = MB

function MB:Create()
  if self.button or not Minimap then return end
  T = T or QB.Data.TEX
  local b = CreateFrame("Button", "QuestBankMinimapButton", Minimap)
  self.button = b
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture(T.minimapHi)
  local bg = tex(b, "BACKGROUND", T.minimapBg, 20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = tex(b, "ARTWORK", T.book, 17, 17)
  icon:SetPoint("TOPLEFT", 7, -6)
  local ring = tex(b, "OVERLAY", T.ring, 53, 53)
  ring:SetPoint("TOPLEFT")
  b:SetScript("OnClick", function(_, which)
    if which == "RightButton" then UI:Open(3) else UI:Toggle() end
  end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      QB:Settings().minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
      MB:Update()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  tooltip(b, function(tip)
    tip:AddLine("QuestBank", GOLD[1], GOLD[2], GOLD[3])
    local r = QB.routeNow
    if r and r.legs and r.legs[1] then
      tip:AddLine(string.format("Banked: %s XP, level %.1f", QB.Comma(r.xp), r.level), 1, 1, 1)
      tip:AddLine("Next stop: " .. r.legs[1].stop.name, 0.8, 0.8, 0.8)
    end
    if QB.Run.Get() then
      local got, n = QB.Run.Totals()
      tip:AddLine(string.format("Run %s: %d in, +%s XP", QB.Clock(QB.Run.Elapsed()), n, QB.Comma(got)), 0.4, 1, 0.4)
    end
    tip:AddLine("Click: open.  Right-click: hand-in route.  Drag: move.", 0.6, 0.6, 0.6)
  end)
  self:Update()
end

function MB:Update()
  local b = self.button
  if not b then return end
  local m = QB:Settings().minimap
  b:SetShown(not m.hide)
  local a = math.rad(m.angle or 205)
  local radius = (Minimap:GetWidth() or 140) / 2 + 10
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * radius, math.sin(a) * radius)
end
