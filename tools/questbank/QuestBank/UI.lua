-- QuestBank window: a quest-log-styled toolbox with three pages.
--   Quest Log  - your 40 slots as a bank, what is in your bags, swaps that gain XP
--   Prep       - what to fetch before the cap, grouped by dungeon and zone
--   Hand-in    - the planned turn-in route with a clock and your level at every stop
-- Built once on first open, rows are pooled, and nothing updates while it is hidden.
local _, QB = ...
local UI = {}
QB.UI = UI

local W, H = 780, 600
local INK = { 0.20, 0.12, 0.05 }
local INK_SOFT = { 0.42, 0.31, 0.17 }
local GOLD = { 1, 0.82, 0 }
local WHITE = { 0.95, 0.93, 0.88 }
local QUALITY = {
  { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 },
}
local STATUS = {
  done = { 0.45, 0.42, 0.38 }, banked = { 0.05, 0.42, 0.08 }, active = { 0.62, 0.38, 0.0 },
  partial = { 0.62, 0.38, 0.0 }, locked = { 0.55, 0.12, 0.05 }, prereq = { 0.55, 0.12, 0.05 },
  todo = { 0.55, 0.12, 0.05 }, follow = { 0.25, 0.25, 0.45 },
}
local BD = BackdropTemplateMixin and "BackdropTemplate" or nil
local T -- QB.Data.TEX

local function tier(xp)
  if not xp then return 1 end
  if xp >= 12000 then return 6 elseif xp >= 9000 then return 5 elseif xp >= 6000 then return 4
  elseif xp >= 3000 then return 3 elseif xp >= 1500 then return 2 end
  return 1
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

local function text(parent, obj, size, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  local fo = _G[obj] or GameFontNormal
  fs:SetFontObject(fo)
  if size then
    local path, _, flags = fo:GetFont()
    if path then fs:SetFont(path, size, flags) end
  end
  if color then fs:SetTextColor(color[1], color[2], color[3]) end
  if justify then fs:SetJustifyH(justify) end
  fs:SetWordWrap(false)
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

-- A scroll area: ScrollFrame, content child and a knob slider, no templates needed.
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
  sf:SetScript("OnSizeChanged", function(self, w) if w and w > 0 then child:SetWidth(w) end end)
  sf.child, sf.bar = child, bar
  function sf:SetContentHeight(h)
    child:SetHeight(math.max(h, 1))
    local view = self:GetHeight() or 0
    local max = math.max(0, h - view)
    bar:SetMinMaxValues(0, max)
    bar:SetShown(max > 0)
    if bar:GetValue() > max then bar:SetValue(max) end
  end
  return sf
end

local function questTooltip(tip, q, st, xp, pct, plvl)
  tip:AddLine(q.name, GOLD[1], GOLD[2], GOLD[3])
  tip:AddDoubleLine("Quest level " .. q.lvl, q.mult ~= 1 and ("Forever x" .. q.mult) or "Classic XP", 0.8, 0.8, 0.8, 0.4, 0.8, 1)
  local full = QB.Model.Full(q)
  if xp then
    local line = QB.Comma(xp) .. " XP on the day"
    if pct and pct < 100 then line = line .. string.format(" (%d%% at level %d)", pct, plvl) end
    tip:AddLine(line, 1, 1, 1)
  else
    tip:AddLine(QB.Comma(full) .. " XP at full value", 1, 1, 1)
  end
  if st then
    local c = STATUS[st.code] or WHITE
    tip:AddLine(st.text, math.min(1, c[1] * 1.6 + 0.2), math.min(1, c[2] * 1.6 + 0.2), math.min(1, c[3] * 1.6 + 0.2))
  end
  if q.how then tip:AddLine(q.how, 0.85, 0.8, 0.7, true) end
  if q.give then tip:AddDoubleLine("From", string.format("%s (%.0f, %.0f)", q.give.n, q.give.x, q.give.y), 0.6, 0.6, 0.6, 1, 1, 1) end
  if q.turn then tip:AddDoubleLine("Hand in", string.format("%s (%.0f, %.0f)", q.turn.n, q.turn.x, q.turn.y), 0.6, 0.6, 0.6, 1, 1, 1) end
  tip:AddLine("Click: map pin.  Shift-click: in or out of the plan.", 0.5, 0.5, 0.5)
end

local function questClick(q, st, button)
  if IsShiftKeyDown and IsShiftKeyDown() then
    local plan = QB:Settings().plan
    plan[q.id] = not QB:IsPlanned(q)
    QB:MarkDirty()
    UI:Refresh()
    return
  end
  local target = q.turn
  if st and (st.code == "todo" or st.code == "locked" or st.code == "prereq") and q.give then target = q.give end
  if target then QB.API.SetWaypoint(target.m, target.x, target.y, target.n) end
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
  f:SetFrameStrata("HIGH")
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
  local title = text(f, "GameFontNormalLarge", 15, GOLD)
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

function UI:CreateHeader(f)
  local h = {}
  self.header = h
  h.portrait = tex(f, "ARTWORK", nil, 58, 58)
  h.portrait:SetPoint("TOPLEFT", 22, -34)
  h.name = text(f, "GameFontNormalLarge", 16, GOLD, "LEFT")
  h.name:SetPoint("TOPLEFT", 92, -32)
  h.sub = text(f, "GameFontHighlightSmall", 11, WHITE, "LEFT")
  h.sub:SetPoint("TOPLEFT", h.name, "BOTTOMLEFT", 0, -3)

  -- XP bar from level 20 to 30, styled like the classic experience bar
  local barW = W - 92 - 262
  local bar = CreateFrame("Frame", nil, f, BD)
  bar:SetPoint("TOPLEFT", 88, -84)
  bar:SetSize(barW + 8, 22)
  backdrop(bar, T.tipBg, T.tipBorder, 10, 2)
  if bar.SetBackdropColor then bar:SetBackdropColor(0, 0, 0, 0.75) end
  h.barW = barW
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
    tick:SetPoint("TOPLEFT", 4 + barW * i / 10, -4)
  end
  for i = 0, 10 do
    local lab = text(f, "GameFontHighlightSmall", 10, { 0.75, 0.72, 0.65 })
    lab:SetPoint("TOP", bar, "BOTTOMLEFT", 4 + barW * i / 10, -1)
    lab:SetText(20 + i)
  end
  h.legend = text(f, "GameFontHighlightSmall", 11, WHITE, "LEFT")
  h.legend:SetPoint("TOPLEFT", 92, -68)
  h.legend:SetWidth(barW)
  tooltip(bar, function(tip)
    tip:AddLine("Level 20 to 30", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Blue: where you are now.", 0.5, 0.7, 1)
    tip:AddLine("Purple: after handing in everything banked now.", 0.8, 0.4, 0.8)
    tip:AddLine("Pale: after the whole plan.", 0.85, 0.75, 1)
    tip:AddLine("Level 20 to 30 takes 331,800 XP.", 0.8, 0.8, 0.8)
  end)

  -- toggles
  h.toggles = {}
  local defs = {
    { key = "mounted", icon = T.mount, label = "Mount" },
    { key = "bag", icon = T.sleep, label = "Sleeping bag" },
    { key = "goal", icon = T.hourglass, label = "Plan for" },
    { key = "pin", icon = T.map, label = "Next stop" },
  }
  for i, d in ipairs(defs) do
    local b = iconButton(f, 32, d.icon)
    b:SetPoint("TOPRIGHT", -(24 + (4 - i) * 58), -44)
    b.caption = text(f, "GameFontHighlightSmall", 10, WHITE)
    b.caption:SetPoint("TOP", b, "BOTTOM", 0, -9)
    b.key = d.key
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button) UI:Toggle_(self.key, button) end)
    tooltip(b, function(tip, self) UI:ToggleTooltip(tip, self.key) end)
    h.toggles[d.key] = b
  end
end

function UI:Toggle_(key, button)
  local set = QB:Settings()
  if key == "mounted" or key == "bag" then
    if button == "RightButton" then
      set[key] = "auto"
    else
      local on = (key == "mounted") and QB:Mounted() or QB:BagBonus()
      set[key] = not on
    end
  elseif key == "goal" then
    set.goal = set.goal == "hour" and "route" or "hour"
  elseif key == "pin" then
    local r = QB.routeNow
    if not (r and r.legs[1]) then r = QB.routePlan end
    local leg = r and r.legs[1]
    if leg then
      local s = QB.Data.STOP[leg.stop]
      QB.API.SetWaypoint(s.m, s.x, s.y, s.name)
    end
    return
  end
  QB:MarkDirty()
  self:Refresh()
end

function UI:ToggleTooltip(tip, key)
  local set = QB:Settings()
  if key == "mounted" then
    local on, auto = QB:Mounted()
    tip:AddLine(on and "Mounted" or "On foot", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("A mount cuts every run between NPCs to 62%. Flights and boats don't change.", 1, 1, 1, true)
    tip:AddLine(auto and "Set from your riding skill. Right-click to keep it on auto." or "Set by you. Right-click to go back to auto.", 0.6, 0.6, 0.6, true)
  elseif key == "bag" then
    local on, auto = QB:BagBonus()
    tip:AddLine(on and "Cozy Sleeping Bag: +3%" or "No sleeping bag bonus", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Lie in the bag for three minutes before your first turn-in: +3% XP from quests for two hours.", 1, 1, 1, true)
    tip:AddLine(auto and "Follows the Well Rested buff. Right-click for auto." or "Set by you. Right-click to go back to auto.", 0.6, 0.6, 0.6, true)
  elseif key == "goal" then
    tip:AddLine(set.goal == "hour" and "Plan for the first hour" or "Plan for the whole route", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("First hour: the highest level at the 60-minute mark. Whole route: the highest level at the end.", 1, 1, 1, true)
  elseif key == "pin" then
    local r = QB.routeNow and QB.routeNow.legs[1] and QB.routeNow or QB.routePlan
    local leg = r and r.legs[1]
    tip:AddLine("Map pin on the next stop", GOLD[1], GOLD[2], GOLD[3])
    if leg then tip:AddLine(QB.Data.STOP[leg.stop].name, 1, 1, 1) end
  end
end

function UI:CreateContent(f)
  local c = CreateFrame("Frame", nil, f, BD)
  c:SetPoint("TOPLEFT", 16, -126)
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
  }
end

function UI:CreateTabs(f)
  self.tabs = {}
  local names = { "Quest Log", "Prep", "Hand-in Route" }
  local x = 20
  for i, name in ipairs(names) do
    local b = CreateFrame("Button", nil, f)
    local w = 112
    b:SetSize(w, 32)
    b:SetPoint("TOPLEFT", self.content, "BOTTOMLEFT", x, 2)
    x = x + w + 2
    local function piece(file, point, rel, w2, l, r, bottom, h2)
      local t = tex(b, "BACKGROUND", file)
      t:SetSize(w2, h2)
      t:SetTexCoord(l, r, 0, bottom)
      return t
    end
    b.onL = piece(T.tabOn, nil, nil, 20, 0, 0.15625, 0.546875, 35)
    b.onR = piece(T.tabOn, nil, nil, 20, 0.84375, 1, 0.546875, 35)
    b.onM = piece(T.tabOn, nil, nil, w - 40, 0.15625, 0.84375, 0.546875, 35)
    b.offL = piece(T.tabOff, nil, nil, 20, 0, 0.15625, 1, 32)
    b.offR = piece(T.tabOff, nil, nil, 20, 0.84375, 1, 1, 32)
    b.offM = piece(T.tabOff, nil, nil, w - 40, 0.15625, 0.84375, 1, 32)
    for _, set in ipairs({ { b.onL, b.onM, b.onR, 3 }, { b.offL, b.offM, b.offR, 0 } }) do
      set[1]:SetPoint("TOPLEFT", 0, set[4])
      set[2]:SetPoint("TOPLEFT", set[1], "TOPRIGHT")
      set[3]:SetPoint("TOPLEFT", set[2], "TOPRIGHT")
    end
    local hi = tex(b, "HIGHLIGHT", T.tabHi)
    hi:SetPoint("TOPLEFT", 6, -2)
    hi:SetPoint("BOTTOMRIGHT", -6, 6)
    hi:SetBlendMode("ADD")
    b.label = text(b, "GameFontNormalSmall", 12, GOLD)
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
  local bind, _, where = QB:Bind()
  local cls = UnitClass and (UnitClass("player")) or ""
  h.sub:SetText(string.format("Level %d %s  ·  Hearthstone: %s", s.level, cls or "", (where and where ~= "") and where or "not set"))
  local cur = QB.Model.Frac(s.level, s.xp)
  local now, plan = QB.routeNow, QB.routePlan
  local function w(level) return math.max(1, math.min(h.barW, h.barW * (level - 20) / 10)) end
  h.fillCur:SetWidth(w(cur))
  h.fillNow:SetWidth(w(now and now.level or cur))
  h.fillPlan:SetWidth(w(plan and plan.level or cur))
  h.legend:SetText(string.format("|cff6f9fffNow %.1f|r   |cffc080c0Banked %.1f|r   |cffd8c8ffPlan %.1f|r   |cffaaaaaaPlan at 60 min %.1f|r",
    cur, now and now.level or cur, plan and plan.level or cur, plan and plan.at60 or cur))
  local set = QB:Settings()
  local tg = h.toggles
  local mounted = QB:Mounted()
  setIcon(tg.mounted.icon, mounted and T.mount or T.foot)
  tg.mounted.caption:SetText(mounted and "Mounted" or "On foot")
  local bag = QB:BagBonus()
  tg.bag.icon:SetDesaturated(not bag)
  tg.bag.caption:SetText(bag and "+3% XP" or "No bag")
  tg.goal.caption:SetText(set.goal == "hour" and "First hour" or "Whole route")
  tg.pin.caption:SetText("Next stop")
end

----------------------------------------------------------------------------
-- page 1: the quest log as a bank
----------------------------------------------------------------------------
function UI:CreateLogView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()
  v.title = text(v, "GameFontNormalLarge", 15, INK, "LEFT")
  v.title:SetPoint("TOPLEFT", 16, -12)
  v.worth = text(v, "GameFontNormal", 12, INK_SOFT, "LEFT")
  v.worth:SetPoint("LEFT", v.title, "RIGHT", 10, -1)
  v.slots = {}
  for i = 1, 40 do
    local b = iconButton(v, 36, nil)
    local col, row = (i - 1) % 8, math.floor((i - 1) / 8)
    b:SetPoint("TOPLEFT", 20 + col * 46, -42 - row * 46)
    b.frame = tex(b, "OVERLAY", T.iconFrame)
    b.frame:SetAllPoints()
    b.frame:SetBlendMode("ADD")
    b.xp = text(b, "NumberFontNormal", 11, WHITE, "RIGHT")
    b.xp:SetPoint("BOTTOMRIGHT", -1, 2)
    b.mark = tex(b, "OVERLAY", nil, 14, 14)
    b.mark:SetPoint("TOPLEFT", -3, 3)
    b:SetScript("OnClick", function(self, button) if self.q then questClick(self.q, self.st, button) end end)
    tooltip(b, function(tip, self)
      if self.q then
        questTooltip(tip, self.q, self.st, self.value)
      elseif self.entry then
        tip:AddLine(self.entry.title, GOLD[1], GOLD[2], GOLD[3])
        tip:AddLine(self.value and (QB.Comma(self.value) .. " XP on the day") or "Not in the plan's data", 1, 1, 1)
        tip:AddLine(self.entry.complete and "Complete" or "Not complete", 0.8, 0.8, 0.8)
        tip:AddLine("Not part of the plan. See the swaps on the right.", 0.6, 0.6, 0.6, true)
      else
        tip:AddLine("Free slot", GOLD[1], GOLD[2], GOLD[3])
        tip:AddLine("Fill it with the best quest from the swap list.", 1, 1, 1, true)
      end
    end)
    v.slots[i] = b
  end
  local bagLabel = text(v, "GameFontNormal", 13, INK, "LEFT")
  bagLabel:SetPoint("TOPLEFT", 16, -282)
  bagLabel:SetText("In your bags, no log slot needed")
  v.bagSlots = {}
  for i = 1, #QB.Data.TRACKED_ITEMS do
    local b = iconButton(v, 36, nil)
    b:SetPoint("TOPLEFT", 20 + (i - 1) * 92, -306)
    b.count = text(b, "NumberFontNormal", 11, WHITE, "RIGHT")
    b.count:SetPoint("BOTTOMRIGHT", -1, 2)
    b.label = text(v, "GameFontNormalSmall", 10, INK, "LEFT")
    b.label:SetPoint("LEFT", b, "RIGHT", 6, 0)
    b.label:SetWidth(44)
    b.label:SetWordWrap(true)
    b.item = QB.Data.TRACKED_ITEMS[i]
    tooltip(b, function(tip, self)
      local it = self.item
      tip:AddLine(it.name, GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine(string.format("%d of %d in your bags", QB.API.ItemCount(it.id), it.need), 1, 1, 1)
      local q = it.quest and QB:QuestByID(it.quest)
      if q then tip:AddLine("For " .. q.name .. ". Keep it in your bags until the cap goes up.", 0.8, 0.8, 0.8, true) end
      if it.id == 211527 then tip:AddLine("Lie in it three minutes before the first turn-in: +3% for two hours.", 0.8, 0.8, 0.8, true) end
    end)
    v.bagSlots[i] = b
  end
  local legend = text(v, "GameFontNormalSmall", 10, INK_SOFT, "LEFT")
  legend:SetPoint("TOPLEFT", 16, -356)
  legend:SetText("|cffa335eePurple|r 9k+   |cff0070ddBlue|r 6k+   |cff1eff00Green|r 3k+   |cffffffffWhite|r 1.5k+   |cff9d9d9dGrey|r less.  |cffff8000Orange|r 12k+")

  -- swaps
  local sx = 408
  local st = text(v, "GameFontNormalLarge", 15, INK, "LEFT")
  st:SetPoint("TOPLEFT", sx, -12)
  st:SetText("Swaps that gain XP")
  v.swapHint = text(v, "GameFontNormalSmall", 11, INK_SOFT, "LEFT")
  v.swapHint:SetPoint("TOPLEFT", sx, -32)
  v.swapHint:SetText("Drop the left one, fetch the right one.")
  v.swaps = {}
  for i = 1, 9 do
    local r = CreateFrame("Button", nil, v)
    r:SetSize(330, 32)
    r:SetPoint("TOPLEFT", sx, -52 - (i - 1) * 34)
    r.hi = tex(r, "HIGHLIGHT", T.rowHi)
    r.hi:SetAllPoints()
    r.hi:SetBlendMode("ADD")
    r.cutIcon = tex(r, "ARTWORK", nil, 22, 22)
    r.cutIcon:SetPoint("LEFT", 2, 0)
    r.cutName = text(r, "GameFontNormalSmall", 11, INK_SOFT, "LEFT")
    r.cutName:SetPoint("LEFT", r.cutIcon, "RIGHT", 4, 0)
    r.cutName:SetWidth(96)
    r.arrow = text(r, "GameFontNormal", 13, INK, "CENTER")
    r.arrow:SetPoint("LEFT", 130, 0)
    r.arrow:SetText(">")
    r.addIcon = tex(r, "ARTWORK", nil, 22, 22)
    r.addIcon:SetPoint("LEFT", 146, 0)
    r.addName = text(r, "GameFontNormalSmall", 11, INK, "LEFT")
    r.addName:SetPoint("LEFT", r.addIcon, "RIGHT", 4, 0)
    r.addName:SetWidth(118)
    r.gain = text(r, "GameFontNormal", 12, { 0.05, 0.42, 0.08 }, "RIGHT")
    r.gain:SetPoint("RIGHT", -2, 0)
    r:SetScript("OnClick", function(self)
      local q = self.add
      if q and q.give then QB.API.SetWaypoint(q.give.m, q.give.x, q.give.y, q.give.n) end
    end)
    tooltip(r, function(tip, self)
      if self.cutTitle then tip:AddLine("Drop: " .. self.cutTitle, 1, 0.5, 0.4) tip:AddLine(QB.Comma(self.cutValue or 0) .. " XP on the day", 0.8, 0.8, 0.8) end
      if self.add then tip:AddLine(" ") questTooltip(tip, self.add, QB:Status(self.add)) end
    end)
    v.swaps[i] = r
  end
  v.noSwaps = text(v, "GameFontNormal", 12, INK_SOFT, "LEFT")
  v.noSwaps:SetPoint("TOPLEFT", sx, -58)
  v.noSwaps:SetWidth(320)
  v.noSwaps:SetWordWrap(true)
  v.Refresh = function() UI:RefreshLogView(v) end
  return v
end

function UI:RefreshLogView(v)
  local s = QB.state
  local entries = {}
  local total = 0
  for _, e in ipairs(s.logOrder) do
    local q = QB:QuestByID(e.id)
    local value = QB:LogValue(e.id)
    entries[#entries + 1] = { e = e, q = q, value = value }
    total = total + (value or 0)
  end
  table.sort(entries, function(a, b) return (a.value or -1) > (b.value or -1) end)
  v.title:SetText(string.format("Quest log  %d / 40", #entries))
  v.worth:SetText(string.format("worth about %s XP on the day", QB.Comma(total)))
  for i, b in ipairs(v.slots) do
    local it = entries[i]
    b.q, b.st, b.entry, b.value = nil, nil, nil, nil
    if it then
      b.entry, b.value = it.e, it.value
      if it.q then b.q, b.st = it.q, QB:Status(it.q) end
      setIcon(b.icon, it.q and it.q.icon or (it.e.complete and T.questActive or T.questAvail))
      b.icon:SetDesaturated(false)
      b.icon:SetAlpha(1)
      local c = QUALITY[tier(it.value)]
      b.frame:SetVertexColor(c[1], c[2], c[3])
      b.frame:Show()
      b.xp:SetText(it.value and QB.Short(it.value) or "?")
      local planned = it.q and QB:IsPlanned(it.q)
      if it.e.complete and planned then
        b.mark:SetTexture(T.ready)
      elseif not planned then
        b.mark:SetTexture(T.notready)
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
  for _, b in ipairs(v.bagSlots) do
    local it = b.item
    local n = QB.API.ItemCount(it.id)
    setIcon(b.icon, QB.API.ItemIcon(it.id, it.icon))
    b.icon:SetDesaturated(n == 0)
    b.count:SetText(it.need > 1 and (n .. "/" .. it.need) or "")
    b.label:SetText(it.name)
    local done = n >= it.need
    b.label:SetTextColor(done and 0.05 or INK_SOFT[1], done and 0.42 or INK_SOFT[2], done and 0.08 or INK_SOFT[3])
  end

  -- swaps: the weakest quests in your log against the best planned quests you don't have yet
  local cuts, adds = {}, {}
  for _, it in ipairs(entries) do
    if not (it.q and QB:IsPlanned(it.q)) then cuts[#cuts + 1] = it end
  end
  table.sort(cuts, function(a, b) return (a.value or 0) < (b.value or 0) end)
  for _, q in ipairs(QB.Data.QUESTS) do
    if QB:IsPlanned(q) and not q.follow and not (q.bagItem and not q.bagIsTool) and not s.log[q.id] then
      local st = QB:Status(q)
      if st.code ~= "done" and st.code ~= "banked" then adds[#adds + 1] = q end
    end
  end
  table.sort(adds, function(a, b) return QB.Model.Full(a) > QB.Model.Full(b) end)
  local rows = {}
  local taken = {}
  for i = #adds, 1, -1 do
    local q = adds[i]
    for _, p in ipairs(q.pre or {}) do
      if s.log[p] then
        local cutEntry
        for _, it in ipairs(entries) do if it.e.id == p then cutEntry = it end end
        if cutEntry then
          table.insert(rows, 1, { cut = cutEntry, add = q, cutValue = cutEntry.value or 0 })
          taken[cutEntry] = true
          table.remove(adds, i)
        end
        break
      end
    end
  end
  for i = #cuts, 1, -1 do if taken[cuts[i]] then table.remove(cuts, i) end end
  local free = 40 - #entries
  local ai = 1
  for _ = 1, free do
    if adds[ai] then rows[#rows + 1] = { add = adds[ai], cutValue = 0 }; ai = ai + 1 end
  end
  for _, c in ipairs(cuts) do
    local a = adds[ai]
    if not a then break end
    if QB.Model.Full(a) > (c.value or 0) + 300 then
      rows[#rows + 1] = { cut = c, add = a, cutValue = c.value or 0 }
      ai = ai + 1
    end
  end
  for i, r in ipairs(v.swaps) do
    local d = rows[i]
    if d then
      r:Show()
      r.add = d.add
      r.cutTitle = d.cut and d.cut.e.title or nil
      r.cutValue = d.cutValue
      setIcon(r.cutIcon, d.cut and (d.cut.q and d.cut.q.icon or T.questAvail) or T.slot)
      r.cutIcon:SetDesaturated(true)
      r.cutName:SetText(d.cut and d.cut.e.title or "Free slot")
      setIcon(r.addIcon, d.add.icon)
      r.addName:SetText(d.add.name)
      r.gain:SetText("+" .. QB.Short(QB.Model.Full(d.add) - d.cutValue))
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
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.hi = tex(r, "HIGHLIGHT", T.rowHi)
  r.hi:SetAllPoints()
  r.hi:SetBlendMode("ADD")
  r.mark = tex(r, "ARTWORK", nil, 14, 14)
  r.mark:SetPoint("LEFT", 4, 0)
  r.icon = tex(r, "ARTWORK", nil, 18, 18)
  r.icon:SetPoint("LEFT", 22, 0)
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.name = text(r, "GameFontNormal", 12, INK, "LEFT")
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.name:SetWidth(230)
  r.lvl = text(r, "GameFontNormalSmall", 10, INK_SOFT, "LEFT")
  r.lvl:SetPoint("LEFT", 282, 0)
  r.status = text(r, "GameFontNormalSmall", 11, INK, "LEFT")
  r.status:SetPoint("LEFT", 318, 0)
  r.status:SetWidth(250)
  r.xp = text(r, "GameFontNormal", 12, INK, "RIGHT")
  r.xp:SetPoint("RIGHT", -8, 0)
  r:SetScript("OnClick", function(self, button)
    if self.q then questClick(self.q, self.st, button)
    elseif self.step and self.step.m then QB.API.SetWaypoint(self.step.m, self.step.x, self.step.y, self.step.name) end
  end)
  tooltip(r, function(tip, self)
    if self.q then
      questTooltip(tip, self.q, self.st)
    elseif self.entry then
      tip:AddLine(self.entry.title, GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine(self.value and (QB.Comma(self.value) .. " XP if you kept it to the day") or "Not in the plan's data", 1, 1, 1)
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
  c.title = text(c, "GameFontNormalLarge", 15, GOLD, "LEFT")
  c.title:SetPoint("TOPLEFT", 50, -9)
  c.where = text(c, "GameFontHighlightSmall", 11, WHITE, "LEFT")
  c.where:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -2)
  c.gain = text(c, "GameFontNormalLarge", 16, GOLD, "RIGHT")
  c.gain:SetPoint("TOPRIGHT", -40, -9)
  c.count = text(c, "GameFontHighlightSmall", 11, WHITE, "RIGHT")
  c.count:SetPoint("TOPRIGHT", c.gain, "BOTTOMRIGHT", 0, -2)
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
  c.note = text(c, "GameFontNormalSmall", 11, INK_SOFT, "LEFT")
  c.note:SetWordWrap(true)
  return c
end

local MARK = { done = "notready", banked = "ready", active = "waiting", partial = "waiting", follow = "ready" }

local function fillRow(r, q, st, width)
  r.q, r.st, r.entry, r.step = q, st, nil, nil
  r:SetWidth(width)
  local planned = QB:IsPlanned(q)
  r.mark:SetTexture(MARK[st.code] and T[MARK[st.code]] or T.questAvail)
  setIcon(r.icon, q.icon)
  r.icon:SetDesaturated(st.code == "done" or not planned)
  r.name:SetText(planned and q.name or (q.name .. "  (not in plan)"))
  local c = planned and INK or INK_SOFT
  r.name:SetTextColor(c[1], c[2], c[3])
  r.lvl:SetText("L" .. q.lvl)
  r.status:SetText(st.text)
  local sc = STATUS[st.code] or INK
  r.status:SetTextColor(sc[1], sc[2], sc[3])
  r.xp:SetText(QB.Comma(QB.Model.Full(q)))
end

function UI:CreatePrepView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()
  v.scroll = scrollArea(v)
  v.cards = pool(v.scroll.child, makeCard)
  v.Refresh = function() UI:RefreshPrepView(v) end
  return v
end

function UI:RefreshPrepView(v)
  local D = QB.Data
  local width = (v.scroll:GetWidth() or (W - 70)) - 6
  if width < 200 then width = W - 76 end
  v.cards:Reset()
  local groups = {}
  for _, a in ipairs(D.ACTS) do groups[a.key] = { act = a, quests = {}, left = 0, banked = 0, total = 0 } end
  for _, q in ipairs(D.QUESTS) do
    local g = groups[q.act]
    if g and not q.follow then
      local st = QB:Status(q)
      g.quests[#g.quests + 1] = { q = q, st = st }
      if QB:IsPlanned(q) and st.code ~= "done" then
        g.total = g.total + 1
        if st.code == "banked" then g.banked = g.banked + 1 else g.left = g.left + QB.Model.Full(q) end
      end
    end
  end
  local list = {}
  for _, a in ipairs(D.ACTS) do list[#list + 1] = groups[a.key] end
  table.sort(list, function(a, b) return a.left > b.left end)

  -- make room: quests in your log that are not part of the plan
  local cutList = {}
  for _, e in ipairs(QB.state.logOrder) do
    local q = QB:QuestByID(e.id)
    if not (q and QB:IsPlanned(q)) then cutList[#cutList + 1] = { e = e, value = QB:LogValue(e.id) } end
  end
  table.sort(cutList, function(a, b) return (a.value or 0) < (b.value or 0) end)

  local y = 0
  local function place(card, h)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", v.scroll.child, "TOPLEFT", 0, -y)
    card:SetSize(width, h)
    y = y + h + 8
  end

  if #cutList > 0 then
    local c = v.cards:Get()
    c.rows:Reset()
    c.art:SetTexture(nil)
    c.art:SetColorTexture(0.30, 0.08, 0.05, 1)
    c.icon:SetTexture(T.notready)
    c.title:SetText("Make room")
    c.where:SetText("In your log but not in the plan. Hand in the finished ones now, abandon the rest.")
    c.gain:SetText(#cutList .. " slots")
    c.count:SetText("")
    c.pin:Hide()
    local ry = 50
    for _, it in ipairs(cutList) do
      local r = c.rows:Get()
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 4, -ry)
      r:SetWidth(width - 8)
      r.q, r.st, r.step = nil, nil, nil
      r.entry, r.value = it.e, it.value
      local note = QB.Data.CUT_NOTES[it.e.id]
      r.advice = note or (it.e.complete and "Complete: hand it in now for the rewards. The cap gives no XP anyway." or "Open: abandon it to free the slot.")
      r.mark:SetTexture(it.e.complete and T.ready or T.notready)
      setIcon(r.icon, T.questAvail)
      r.icon:SetDesaturated(true)
      r.name:SetText(it.e.title)
      r.name:SetTextColor(INK[1], INK[2], INK[3])
      r.lvl:SetText(it.e.level and ("L" .. it.e.level) or "")
      r.status:SetText(note or (it.e.complete and "Complete: hand it in now" or "Open: abandon it"))
      r.status:SetTextColor(STATUS.locked[1], STATUS.locked[2], STATUS.locked[3])
      r.xp:SetText(it.value and QB.Comma(it.value) or "?")
      ry = ry + 22
    end
    c.rows:HideRest()
    c.note:Hide()
    place(c, ry + 8)
  end

  -- the sleeping bag chain
  do
    local c = v.cards:Get()
    c.rows:Reset()
    c.art:SetColorTexture(0.10, 0.12, 0.22, 1)
    c.icon:SetTexture(T.sleep)
    c.title:SetText("Cozy Sleeping Bag")
    local have = QB.API.ItemCount(211527) > 0
    c.where:SetText(have and "You have it. Lie in it three minutes before the first turn-in." or "Finish the Stepping Stones chain: +3% XP from quests for two hours.")
    c.gain:SetText(have and "Done" or "+3%")
    c.count:SetText("")
    local nextStep
    for _, step in ipairs(D.SLEEP_CHAIN) do
      if not QB.API.IsDone(step.id) then nextStep = step break end
    end
    c.pin:SetShown(nextStep and nextStep.m and true or false)
    if nextStep then c.pin.entrance = nextStep.m and { m = nextStep.m, x = nextStep.x, y = nextStep.y } or nil; c.pin.label = nextStep.where end
    local ry = 50
    for _, step in ipairs(D.SLEEP_CHAIN) do
      local r = c.rows:Get()
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 4, -ry)
      r:SetWidth(width - 8)
      r.q, r.st, r.entry = nil, nil, nil
      r.step = step
      local done = QB.API.IsDone(step.id)
      local inLog = QB.state.log[step.id]
      r.mark:SetTexture(done and T.ready or (inLog and T.waiting or T.questAvail))
      setIcon(r.icon, T.map)
      r.icon:SetDesaturated(done)
      r.name:SetText(step.name)
      r.name:SetTextColor(INK[1], INK[2], INK[3])
      r.lvl:SetText("")
      r.status:SetText(done and "Done" or step.where)
      local sc = done and STATUS.banked or INK_SOFT
      r.status:SetTextColor(sc[1], sc[2], sc[3])
      r.xp:SetText("")
      ry = ry + 22
    end
    c.rows:HideRest()
    c.note:Hide()
    place(c, ry + 8)
  end

  for _, g in ipairs(list) do
    local c = v.cards:Get()
    c.rows:Reset()
    local a = g.act
    if a.bg then c.art:SetTexture(a.bg); c.art:SetTexCoord(0, 1, 0.18, 0.5) else c.art:SetColorTexture(0.16, 0.12, 0.08, 1) end
    c.icon:SetTexture(a.icon)
    c.title:SetText(a.name)
    c.where:SetText(a.where)
    c.gain:SetText(g.left > 0 and ("+" .. QB.Comma(g.left)) or "All banked")
    c.gain:SetTextColor(g.left > 0 and GOLD[1] or 0.4, g.left > 0 and GOLD[2] or 0.9, g.left > 0 and GOLD[3] or 0.4)
    c.count:SetText(string.format("%d of %d banked", g.banked, g.total))
    c.pin:SetShown(a.entrance and true or false)
    c.pin.entrance, c.pin.label = a.entrance, a.name .. " entrance"
    table.sort(g.quests, function(x, z)
      local px, pz = QB:IsPlanned(x.q) and 1 or 0, QB:IsPlanned(z.q) and 1 or 0
      if px ~= pz then return px > pz end
      return QB.Model.Full(x.q) > QB.Model.Full(z.q)
    end)
    local ry = 50
    for _, it in ipairs(g.quests) do
      local r = c.rows:Get()
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 4, -ry)
      fillRow(r, it.q, it.st, width - 8)
      ry = ry + 22
    end
    c.rows:HideRest()
    c:SetAlpha(g.left > 0 and 1 or 0.7)
    c.note:Hide()
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
}

local function makeLeg(parent)
  local l = CreateFrame("Button", nil, parent)
  l.line = tex(l, "BACKGROUND")
  l.line:SetColorTexture(0.55, 0.42, 0.2, 0.6)
  l.line:SetWidth(2)
  l.line:SetPoint("TOPLEFT", 43, 0)
  l.line:SetPoint("BOTTOMLEFT", 43, 0)
  l.node = tex(l, "ARTWORK", T.taxiGray, 18, 18)
  l.node:SetPoint("TOPLEFT", 35, -8)
  l.clock = text(l, "GameFontNormal", 12, INK, "RIGHT")
  l.clock:SetPoint("TOPRIGHT", l, "TOPLEFT", 30, -10)
  l.travelIcon = tex(l, "ARTWORK", nil, 16, 16)
  l.travelIcon:SetPoint("TOPLEFT", 62, -6)
  l.travel = text(l, "GameFontNormalSmall", 11, INK_SOFT, "LEFT")
  l.travel:SetPoint("LEFT", l.travelIcon, "RIGHT", 5, 0)
  l.name = text(l, "GameFontNormalLarge", 16, INK, "LEFT")
  l.name:SetPoint("TOPLEFT", 62, -26)
  l.here = text(l, "GameFontNormalSmall", 11, { 0.05, 0.42, 0.08 }, "LEFT")
  l.here:SetPoint("LEFT", l.name, "RIGHT", 8, 0)
  l.level = text(l, "GameFontNormal", 12, INK_SOFT, "RIGHT")
  l.level:SetPoint("TOPRIGHT", -34, -28)
  l.pin = CreateFrame("Button", nil, l)
  l.pin:SetSize(18, 18)
  l.pin:SetPoint("TOPRIGHT", -8, -26)
  l.pin.t = tex(l.pin, "ARTWORK", T.mapPin)
  l.pin.t:SetAllPoints()
  l.pin:SetHighlightTexture(T.hilite, "ADD")
  l.pin:SetScript("OnClick", function(self)
    local s = self.stop
    if s then QB.API.SetWaypoint(s.m, s.x, s.y, s.name) end
  end)
  tooltip(l.pin, function(tip, self) tip:AddLine("Map pin: " .. (self.stop and self.stop.name or ""), GOLD[1], GOLD[2], GOLD[3]) end)
  l.note = text(l, "GameFontNormalSmall", 11, INK_SOFT, "LEFT")
  l.note:SetPoint("TOPLEFT", 62, -46)
  l.note:SetWordWrap(true)
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
  r.name = text(r, "GameFontNormal", 12, INK, "LEFT")
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.name:SetWidth(300)
  r.npc = text(r, "GameFontNormalSmall", 10, INK_SOFT, "LEFT")
  r.npc:SetPoint("LEFT", 330, 0)
  r.npc:SetWidth(170)
  r.xp = text(r, "GameFontNormal", 12, INK, "RIGHT")
  r.xp:SetPoint("RIGHT", -6, 0)
  r:SetScript("OnClick", function(self, button) if self.q then questClick(self.q, self.st, button) end end)
  tooltip(r, function(tip, self) if self.q then questTooltip(tip, self.q, self.st, self.xpv, self.pct, self.plvl) end end)
  l.rows[i] = r
  return r
end

function UI:CreateRouteView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()
  v.modeNow = CreateFrame("Button", nil, v, "UIPanelButtonTemplate")
  v.modeNow:SetSize(120, 22)
  v.modeNow:SetPoint("TOPLEFT", 14, -10)
  v.modeNow:SetText("Banked now")
  v.modePlan = CreateFrame("Button", nil, v, "UIPanelButtonTemplate")
  v.modePlan:SetSize(120, 22)
  v.modePlan:SetPoint("LEFT", v.modeNow, "RIGHT", 4, 0)
  v.modePlan:SetText("Full plan")
  v.modeNow:SetScript("OnClick", function() QB:Settings().routeMode = "now"; UI:Refresh() end)
  v.modePlan:SetScript("OnClick", function() QB:Settings().routeMode = "plan"; UI:Refresh() end)
  v.summary = text(v, "GameFontNormal", 12, INK, "RIGHT")
  v.summary:SetPoint("TOPRIGHT", -16, -14)
  v.setup = text(v, "GameFontNormal", 12, INK, "LEFT")
  v.setup:SetPoint("TOPLEFT", 16, -40)
  v.setup:SetPoint("TOPRIGHT", -16, -40)
  v.setup:SetWordWrap(true)
  local holder = CreateFrame("Frame", nil, v)
  holder:SetPoint("TOPLEFT", 0, -60)
  holder:SetPoint("BOTTOMRIGHT", 0, 0)
  v.scroll = scrollArea(holder)
  v.legs = pool(v.scroll.child, makeLeg)
  v.empty = text(v.scroll.child, "GameFontNormal", 13, INK_SOFT, "LEFT")
  v.empty:SetPoint("TOPLEFT", 60, -20)
  v.empty:SetWidth(560)
  v.empty:SetWordWrap(true)
  v.Refresh = function() UI:RefreshRouteView(v) end
  return v
end

function UI:RefreshRouteView(v)
  local D = QB.Data
  local set = QB:Settings()
  local mode = set.routeMode == "plan" and "plan" or "now"
  local r = mode == "plan" and QB.routePlan or QB.routeNow
  v.modeNow:SetEnabled(mode ~= "now")
  v.modePlan:SetEnabled(mode ~= "plan")
  v.summary:SetText(string.format("%s XP  ·  level %.2f  ·  about %d min  ·  at 60 min: %.2f",
    QB.Comma(r.xp or 0), r.level or 0, math.floor((r.t or 0) + 0.5), r.at60 or 0))
  local width = (v.scroll:GetWidth() or (W - 70)) - 6
  if width < 200 then width = W - 76 end
  v.legs:Reset()
  if not r.legs or #r.legs == 0 then
    v.setup:SetText("")
    v.empty:SetText(mode == "now" and "Nothing is banked yet. Finished quests and quest-start items in your bags show up here, in hand-in order. Switch to Full plan to see the route you're building towards." or "The plan is empty. Shift-click quests on the Prep page to add them.")
    v.empty:Show()
    v.legs:HideRest()
    v.scroll:SetContentHeight(60)
    return
  end
  v.empty:Hide()
  local startName = D.STOP[r.startStop].name
  local line = "Log out at |cff7a2e0a" .. startName .. "|r."
  if r.bindStop then
    local inn = D.INN[r.bindStop]
    local bind = QB:Bind()
    local _, _, where = QB:Bind()
    line = line .. " Bind your hearthstone in |cff7a2e0a" .. inn .. "|r"
    if where and where ~= "" and not where:find(inn) then line = line .. " (it is set to " .. where .. " now)" end
    line = line .. "."
  end
  v.setup:SetText(line)

  local y = 0
  local mapID = QB.state.mapID
  for i, leg in ipairs(r.legs) do
    local l = v.legs:Get()
    local s = D.STOP[leg.stop]
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", v.scroll.child, "TOPLEFT", 0, -y)
    l:SetWidth(width)
    l.node:SetTexture(i == 1 and T.taxiY or T.taxiGray)
    local m = math.floor(leg.t + 0.5)
    l.clock:SetText(string.format("%d:%02d", math.floor(m / 60), m % 60))
    local kind = leg.kind
    l.travelIcon:SetTexture((kind == "hearth" and T.hearth) or (kind == "flight" and T.gryphon) or (kind == "boat" and T.boat)
      or (kind == "tram" and T.tram) or (kind == "start" and T.book) or (QB:Mounted() and T.mount or T.foot))
    local label = KIND[kind] or kind
    if kind ~= "start" then label = label .. string.format(", about %d min", math.max(1, math.floor(leg.travel + 0.5))) end
    l.travel:SetText(label)
    l.name:SetText(s.name)
    l.here:SetText(mapID and mapID == s.m and "You are here" or "")
    l.level:SetText(string.format("level %.1f  >  %.1f", leg.arrive, leg.leave))
    l.pin.stop = s
    l.note:SetWidth(width - 80)
    l.note:SetText(s.note)
    local noteH = math.max(14, (l.note:GetStringHeight() or 14))
    local ry = 50 + noteH + 4
    for k, row in ipairs(leg.rows) do
      local rr = legRow(l, k)
      rr:ClearAllPoints()
      rr:SetPoint("TOPLEFT", 58, -ry)
      rr:SetWidth(width - 66)
      rr.q, rr.st, rr.xpv, rr.pct, rr.plvl = row.q, row.e.st, row.xp, row.pct, row.plvl
      setIcon(rr.icon, row.q.icon)
      rr.name:SetText(row.q.name)
      local turn = row.q.turn
      rr.npc:SetText(turn and turn.n or "")
      local xpText = QB.Comma(row.xp)
      if row.pct < 100 then xpText = string.format("|cffa0400a%d%%|r  %s", row.pct, xpText) end
      rr.xp:SetText(xpText)
      ry = ry + 20
    end
    for k = #leg.rows + 1, #l.rows do l.rows[k]:Hide() end
    local h = ry + 10
    l:SetHeight(h)
    y = y + h
  end
  v.legs:HideRest()
  v.scroll:SetContentHeight(y + 10)
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
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then UI:Open(3) else UI:Toggle() end
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
    QB:Recompute()
    local r = QB.routeNow
    if r and r.legs and r.legs[1] then
      tip:AddLine(string.format("Banked: %s XP, level %.1f", QB.Comma(r.xp), r.level), 1, 1, 1)
      tip:AddLine("Next stop: " .. QB.Data.STOP[r.legs[1].stop].name, 0.8, 0.8, 0.8)
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
