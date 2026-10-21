-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank window: a quest-log-styled toolbox with four pages.
--   Quest Log  - your 40 slots as a bank, your bags, and swaps that gain XP
--   Plan       - the best quests for your level, by dungeon and zone, for your faction, class and race
--   Settings   - mode (auto, questing, banking), next cap, updates, chat, sharing, map, discoveries
--   Hand-in    - the turn-in route with a clock and your level at every stop, and the run as you go
--   Party      - QuestBank users in your group and guild: banks, runs, dungeons worth running together
-- Built on first open, rows are pooled, and nothing updates while it is hidden.
local _, QB = ...
local UI = QB.UI

local SIDE = 184                 -- the sidebar's width
local W, H = SIDE + 8 + 828 + 14, 620
local INK = { 0.93, 0.88, 0.78 }
local INK_SOFT = { 0.66, 0.60, 0.50 }
local GOOD = { 0.42, 0.86, 0.45 }
local BAD = { 0.90, 0.38, 0.32 }
local GOLD = { 1, 0.82, 0 }
local GOLD_SOFT = { 0.78, 0.62, 0.3 }
local WHITE = { 0.95, 0.93, 0.88 }
local SLATE = { 0.055, 0.07, 0.095 }
local SLATE2 = { 0.09, 0.11, 0.15 }
local EDGE = "Interface\\DialogFrame\\UI-DialogBox-Border"
local FLAT = "Interface\\Buttons\\WHITE8x8"
local QUALITY = {
  { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 },
}
local STATUS = {
  done = { 0.5, 0.5, 0.5 }, banked = GOOD, active = { 0.95, 0.72, 0.3 }, partial = { 0.95, 0.72, 0.3 },
  bagstart = { 0.95, 0.72, 0.3 }, item = INK_SOFT, locked = BAD, prereq = BAD, todo = INK_SOFT, follow = { 0.55, 0.65, 0.95 },
  wrong = { 0.5, 0.5, 0.5 },
}
local BD = BackdropTemplateMixin and "BackdropTemplate" or nil
local T -- QB.Data.TEX
local Q = QB.Quest
local fitText, itemName = UI.FitText, UI.ItemName -- (Lists.lua)

local function tier(xp)
  if not xp then return 1 end
  xp = xp / QB.Scale(QB.state.level) -- the colours were set at level 20; a level 3's quests pay less
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
  owner:SetScript("OnEnter", QB.Safe(function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    fill(GameTooltip, self)
    GameTooltip:Show()
  end, "tooltip"))
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

-- the dressing room's line under an item's tooltip, where the room can put the item on you
local function dressHint(tip, id)
  if id and QB.API.Dressable(id) then tip:AddLine("Ctrl-click: try it on.", 0.5, 0.5, 0.5) end
end

-- a reward item's icon as a button: the item's own tooltip, Ctrl-click tries it on in the dressing room, any other
-- click is the row's (the icon sits on the row and must not swallow its click)
local function rewardButton(parent, size, row)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.icon = tex(b, "ARTWORK", nil, size, size)
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", QB.Safe(function(self, which)
    if self.id and which ~= "RightButton" and QB.DressClick() then QB.API.DressUp(self.id) return end
    local f = row and row:GetScript("OnClick")
    if f then f(row, which) end
  end, "reward icon"))
  b:SetScript("OnEnter", function(self)
    if not self.id then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then pcall(GameTooltip.SetItemByID, GameTooltip, self.id) end
    dressHint(GameTooltip, self.id)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
    -- (a row's selection box shows while the mouse is on the row: off its icon and off the row, it goes)
    if row and row.sel and UI.ShowSelect and not (row.IsMouseOver and row:IsMouseOver()) then UI.ShowSelect(row, false) end
  end)
  return b
end

local function button(parent, label, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 110, 22)
  b:SetText(label)
  return b
end

local function setIcon(t, icon) t:SetTexture(icon or T.questGeneric) end

-- open or closed, drawn as the game's own campaign and reputation headers draw it; never a text glyph: the game's
-- font (Friz Quadrata) has no triangles or arrows and draws a hollow box for each
local function caret(t, open)
  QB.Art(t, open and "campaign_headericon_open" or "campaign_headericon_closed",
    open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
end
UI.Caret = caret -- (the Map page's sections, MapPage.lua)

-- an item's icon: the client's when it has one, asked of the server when not (nil until it comes)
local function itemIcon(id)
  local CI = C_Item
  if CI and CI.GetItemIconByID then local ok, i = pcall(CI.GetItemIconByID, id); if ok and i then return i end end
  if GetItemInfoInstant then local ok, _, _, _, _, i = pcall(GetItemInfoInstant, id); if ok and i then return i end end
  if CI and CI.RequestLoadItemDataByID then pcall(CI.RequestLoadItemDataByID, id) end
  return nil
end

-- the bags' green upgrade arrow (atlas bags-greenarrow in Interface\ContainerFrame\Bags)
local UPGRADE_TC = { 66 / 512, 86 / 512, 93 / 256, 115 / 256 }
local function upgradeMark(parent, w, h)
  local t = tex(parent, "OVERLAY", T.upgrade, w, h)
  t:SetTexCoord(UPGRADE_TC[1], UPGRADE_TC[2], UPGRADE_TC[3], UPGRADE_TC[4])
  t:Hide()
  return t
end

-- UI-WorldMap-QuestIcon holds three question marks; the yellow one sits in the top-left quarter
-- (its pixels: 11 to 23 across, 7 to 24 down, of 64), cropped square around it
local PIN_TC = { 0.1172, 0.4141, 0.0938, 0.3906 }
-- a waypoint button: the game's own waypoint pin (a quest's ? would read as a hand-in); the old map icon where the
-- client has no such atlas
local function pinButton(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.t = tex(b, "ARTWORK")
  b.t:SetAllPoints()
  if not QB.Art(b.t, "Waypoint-MapPin-Untracked", T.mapPin) then b.t:SetTexCoord(PIN_TC[1], PIN_TC[2], PIN_TC[3], PIN_TC[4]) end
  b.hi = tex(b, "HIGHLIGHT")
  b.hi:SetAllPoints()
  if not QB.Art(b.hi, "Waypoint-MapPin-Highlight", T.mapPin) then b.hi:SetTexCoord(PIN_TC[1], PIN_TC[2], PIN_TC[3], PIN_TC[4]) end
  b.hi:SetBlendMode("ADD")
  return b
end

-- what a route row is about, at a glance: a green check for a quest to hand in, the game's yellow ! for one to pick
-- up first, the quest's own icon while it is still being done
local function routeMark(rr, q, st)
  rr.icon:Show()
  rr.tick:Hide()
  rr.icon:SetDesaturated(false)
  if st and st.code == "banked" then
    rr.icon:Hide()
    rr.tick:Show()
  elseif not QB.state.log[q.id] and not (st and st.bag) then
    QB.Art(rr.icon, "QuestNormal", T.questAvail)
  else
    setIcon(rr.icon, q.icon)
    rr.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  end
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

-- ScrollFrame, content child and a knob slider, no templates needed. What scrolls sits 7 px inside the panel's
-- border and the knob as far in on the right (its 18 px art hangs 2 px past the 14 px bar on each side)
local SCROLL_L, SCROLL_R, BAR_R = 10, 30, 12
local function scrollArea(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  sf:SetPoint("TOPLEFT", SCROLL_L, -6)
  sf:SetPoint("BOTTOMRIGHT", -SCROLL_R, 6)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize((W - SIDE - 22) - SCROLL_L - SCROLL_R, 10)
  sf:SetScrollChild(child)
  local bar = CreateFrame("Slider", nil, parent)
  bar:SetOrientation("VERTICAL")
  bar:SetPoint("TOPRIGHT", -BAR_R, -10)
  bar:SetPoint("BOTTOMRIGHT", -BAR_R, 10)
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
  -- room under the list for a bar of the page's own (the selection's on Now and Available): the list and its knob
  -- end above it
  function sf:SetBottom(px)
    if (self.bottom or 6) == px then return end
    self.bottom = px
    self:SetPoint("BOTTOMRIGHT", -SCROLL_R, px)
    bar:SetPoint("BOTTOMRIGHT", -BAR_R, px + 4)
  end
  function sf:SetContentHeight(h)
    child:SetHeight(math.max(h, 1))
    local view = self:GetHeight() or 0
    if view < 100 then view = (H - 138 - 14) - 6 - (self.bottom or 6) end -- not laid out yet: the content area less the insets
    local max = math.max(0, h - view)
    bar:SetMinMaxValues(0, max)
    bar:SetShown(max > 0)
    if bar:GetValue() > max then bar:SetValue(max) end
  end
  function sf:Width()
    local w = self:GetWidth() or 0
    if w < 200 then w = (W - SIDE - 22) - SCROLL_L - SCROLL_R end
    return w
  end
  return sf
end


----------------------------------------------------------------------------
-- right-click menu: what you can do with a quest
----------------------------------------------------------------------------
local menu
local function menuFrame()
  if menu then return menu end
  T = T or QB.Data.TEX
  menu = CreateFrame("Frame", "QuestBankMenu", UIParent, BD)
  menu:SetFrameStrata("DIALOG")
  menu:SetFrameLevel(20)
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  backdrop(menu, T.tipBg, T.tipBorder, 12, 3)
  if menu.SetBackdropColor then menu:SetBackdropColor(0.06, 0.05, 0.04, 0.96) end
  menu.title = text(menu, "GameFontNormal", 12, GOLD, "LEFT", 224)
  menu.title:SetPoint("TOPLEFT", 10, -9)
  menu.items = {}
  -- a click anywhere else closes it
  menu.catcher = CreateFrame("Button", nil, UIParent)
  menu.catcher:SetAllPoints(UIParent)
  menu.catcher:SetFrameStrata("DIALOG")
  menu.catcher:SetFrameLevel(10)
  menu.catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  menu.catcher:SetScript("OnClick", function() menu:Hide() end)
  menu.catcher:Hide()
  menu:SetScript("OnHide", function() menu.catcher:Hide() end)
  if UISpecialFrames then table.insert(UISpecialFrames, "QuestBankMenu") end
  menu:Hide()
  return menu
end

function UI:ShowMenu(title, items)
  UI.lastMenu = items
  local m = menuFrame()
  m.title:SetText(title)
  local y = -30
  for i, it in ipairs(items) do
    local b = m.items[i]
    if not b then
      b = CreateFrame("Button", nil, m)
      b:SetSize(228, 20) -- (5 px inside the menu's border on each side; it sat 3 px from it)
      b.hi = tex(b, "HIGHLIGHT", T.rowHi)
      b.hi:SetAllPoints()
      b.hi:SetBlendMode("ADD")

      b.hi:SetAlpha(0.6)
      b.label = text(b, "GameFontHighlightSmall", 12, WHITE, "LEFT", 220)
      b.label:SetPoint("LEFT", 8, 0)
      b:SetScript("OnClick", function(self)
        m:Hide()
        if self.func then self.func() end
      end)
      m.items[i] = b
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 8, y)
    b.label:SetText(it[1])
    b.func = it[2]
    b:Show()
    y = y - 20
  end
  for i = #items + 1, #m.items do m.items[i]:Hide() end
  m:SetSize(244, -y + 10)
  local x, cy = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  m:ClearAllPoints()
  m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 6, cy / scale - 6)
  m.catcher:Show()
  m:Show()
end

-- the game's red close X, well inside a dialog border (24 px, 7 px in): 20 px, its edges 14 px from the frame's right and
-- 13 from its top. Forever's art fills its 24 px box edge to edge; Classic Era's old 32 px art has 6 px of air all round,
-- so that one keeps its size and its X lands in the same place
function UI.CloseButton(f)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  local air = (close:GetWidth() or 24) >= 30 and 6 or 0
  close:SetSize(20 + 2 * air, 20 + 2 * air)
  close:SetPoint("TOPRIGHT", -14 + air, -13 + air)
  return close
end

-- a box with the link selected, ready for Ctrl+C
function UI:CopyLink(title, url)
  T = T or QB.Data.TEX
  local f = self.linkFrame
  if not f then
    f = CreateFrame("Frame", "QuestBankLink", UIParent, BD)
    self.linkFrame = f
    f:SetSize(380, 84)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(30)
    f:EnableMouse(true)
    backdrop(f, T.bg, T.border, 24, 7, true)
    f.title = text(f, "GameFontNormal", 12, GOLD, "LEFT", 320)
    f.title:SetPoint("TOPLEFT", 16, -16)
    f.hint = text(f, "GameFontHighlightSmall", 10, WHITE, "LEFT", 320)
    f.hint:SetPoint("TOPLEFT", 16, -60)
    f.hint:SetText("Ctrl+C copies it. Esc closes.")
    f.eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.eb:SetSize(340, 20)
    f.eb:SetPoint("TOPLEFT", 20, -34)
    f.eb:SetAutoFocus(false)
    f.eb:SetScript("OnEscapePressed", function() f:Hide() end)
    f.eb:SetScript("OnEnterPressed", function() f:Hide() end)
    UI.CloseButton(f)
    if UISpecialFrames then table.insert(UISpecialFrames, "QuestBankLink") end
  end
  f.title:SetText(title)
  f.eb:SetText(url)
  f:Show()
  f.eb:SetFocus()
  f.eb:HighlightText()
end

-- posting in party and guild chat: the message as people will read it (yours to edit), where it goes,
-- and nothing is sent until you press Post
local GREY = { 0.62, 0.6, 0.56 }
function UI:PostDialog(msg, why, offered)
  T = T or QB.Data.TEX
  local f = self.postFrame
  -- an offer never replaces a message you're writing
  if f and offered and f:IsShown() and (f.edited or f.eb:HasFocus()) then return end
  if not f then
    f = CreateFrame("Frame", "QuestBankPost", UIParent, BD)
    self.postFrame = f
    f:SetSize(420, 256)
    local pos = QB:Settings().post.pos
    if pos then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else f:SetPoint("TOP", 0, -120) end
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(30)
    f:EnableMouse(true)
    -- drag it out of your way; it opens there next time
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      local p, _, _, x, y = self:GetPoint()
      QB:Settings().post.pos = { p, x, y }
    end)
    backdrop(f, T.bg, T.border, 24, 7, true)
    f.title = text(f, "GameFontNormal", 13, GOLD, "LEFT", 380)
    f.title:SetPoint("TOPLEFT", 20, -18)
    f.title:SetText("Post in chat")
    f.why = text(f, "GameFontHighlightSmall", 11, WHITE, "LEFT", 380)
    f.why:SetPoint("TOPLEFT", 20, -36)
    f.box = CreateFrame("Frame", nil, f, BD)
    f.box:SetPoint("TOPLEFT", 16, -54)
    f.box:SetSize(388, 96)
    backdrop(f.box, T.tipBg, T.tipBorder, 12, 3)
    if f.box.SetBackdropColor then f.box:SetBackdropColor(0, 0, 0, 0.6) end
    f.box:EnableMouse(true)
    f.eb = CreateFrame("EditBox", nil, f.box)
    f.eb:SetFontObject(ChatFontNormal)
    f.eb:SetPoint("TOPLEFT", 10, -8)
    f.eb:SetSize(368, 80)
    f.eb:SetMultiLine(true)
    f.eb:SetMaxLetters(255)
    f.eb:SetAutoFocus(false)
    f.eb:EnableMouse(true)
    f.eb:SetTextColor(1, 1, 1)
    f.box:SetScript("OnMouseDown", function() f.eb:SetFocus() end)
    f.eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    f.eb:SetScript("OnTextChanged", function(self, typed)
      if not typed then return end
      -- one line, no escape codes: the chat box doesn't take them
      local t = self:GetText()
      local one = t:gsub("[\r\n|]", "")
      if one ~= t then self:SetText(one) end
      f.edited = true
      UI:PostState()
    end)
    local function check(x, key)
      local c = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
      c:SetSize(24, 24)
      c:SetPoint("TOPLEFT", x, -156)
      c.label = text(f, "GameFontNormal", 12, WHITE, "LEFT", 150)
      c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
      c.key = key
      c:SetScript("OnClick", function() UI:PostState() end)
      return c
    end
    f.party = check(16, "party")
    f.guild = check(210, "guild")
    f.auto = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.auto:SetSize(20, 20)
    f.auto:SetPoint("TOPLEFT", 18, -184)
    f.autoLabel = text(f, "GameFontHighlightSmall", 11, GREY, "LEFT", 356)
    f.autoLabel:SetPoint("LEFT", f.auto, "RIGHT", 2, 0)
    f.autoLabel:SetText("Offer a post during hand-in runs: each level, the hour, the end")
    f.auto:SetScript("OnClick", function(self) QB:Settings().post.auto = self:GetChecked() and true or false end)
    f.post = button(f, "Post", 110)
    f.post:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 18)
    f.post:SetScript("OnClick", QB.Safe(function() UI:PostSend() end, "posting in chat"))
    f.cancel = button(f, "Cancel", 110)
    f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 18)
    f.cancel:SetScript("OnClick", function() f:Hide() end)
    f:SetScript("OnHide", function() f.eb:ClearFocus() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "QuestBankPost") end
  end
  f.why:SetText(why or "")
  f.eb:SetText(msg or "")
  f.edited = false
  -- ticked the way you left them, where you can post right now
  local set = QB:Settings().post
  local ch = QB.Sync and QB.Sync.PostChannels() or {}
  for _, c in ipairs({ f.party, f.guild }) do
    local where = ch[c.key]
    c:SetEnabled(where ~= nil)
    c:SetChecked((where ~= nil and set[c.key]) and true or false)
    if where then
      c.label:SetText(where.label)
      c.label:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
    else
      c.label:SetText(c.key == "party" and "Party (not in a group)" or "Guild (not in one)")
      c.label:SetTextColor(GREY[1], GREY[2], GREY[3])
    end
  end
  f.auto:SetChecked(set.auto and true or false)
  self:PostState()
  f:Show()
end

-- Post works when a ticked channel can take it and there's something to say
function UI:PostState()
  local f = self.postFrame
  local on = (f.party:GetChecked() and f.party:IsEnabled()) or (f.guild:GetChecked() and f.guild:IsEnabled())
  f.post:SetEnabled((on and QB.Sync.CleanPost(f.eb:GetText()) ~= "") and true or false)
end

function UI:PostSend()
  local f = self.postFrame
  local want = { party = f.party:GetChecked() and true or false, guild = f.guild:GetChecked() and true or false }
  -- next time it's ticked the way you left it
  local set, ch = QB:Settings().post, QB.Sync.PostChannels()
  for key, on in pairs(want) do if ch[key] then set[key] = on end end
  local n = QB.Sync:Post(f.eb:GetText(), want)
  f:Hide()
  if n == 0 then QB:Print("Nothing was posted: you're not in that group or guild any more.") end
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
  backdrop(f, FLAT, EDGE, 24, 7)
  if f.SetBackdropColor then f:SetBackdropColor(SLATE[1], SLATE[2], SLATE[3], 0.97) end
  if UISpecialFrames then table.insert(UISpecialFrames, "QuestBankFrame") end
  -- the top strip: the name in Blizzard's own face, a gold hairline under it, the close X at its end
  local strip = tex(f, "BACKGROUND", FLAT)
  strip:SetPoint("TOPLEFT", 8, -8)
  strip:SetPoint("TOPRIGHT", -8, -8)
  strip:SetHeight(30)
  strip:SetVertexColor(0.12, 0.15, 0.2, 0.9)
  local hair = tex(f, "BACKGROUND", FLAT)
  hair:SetPoint("TOPLEFT", 8, -38)
  hair:SetPoint("TOPRIGHT", -8, -38)
  hair:SetHeight(1)
  hair:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.35)
  local title = text(f, "GameFontNormalLarge", 15, GOLD, "LEFT", 200)
  title:SetPoint("TOPLEFT", 20, -15)
  title:SetText("QUESTBANK")
  UI.CloseButton(f)

  self:CreateHeader(f)
  self:CreateContent(f)
  self:CreateTabs(f)
  self:ShowTab((set.tab == 8 and not UI.MapPageOn()) and 1 or set.tab or 1)
  return f
end

-- header: portrait, name, the XP bar from 20 to 30, four switches
local BAR_X, BAR_W = SIDE + 88, 400
function UI:CreateHeader(f)
  local h = {}
  self.header = h
  h.portrait = tex(f, "ARTWORK", nil, 58, 58)
  h.portrait:SetPoint("TOPLEFT", SIDE + 18, -44)
  h.name = text(f, "GameFontNormalLarge", 16, GOLD, "LEFT", BAR_W)
  h.name:SetPoint("TOPLEFT", BAR_X, -44)
  h.sub = text(f, "GameFontHighlightSmall", 11, WHITE, "LEFT", BAR_W)
  h.sub:SetPoint("TOPLEFT", BAR_X, -64)
  h.legend = text(f, "GameFontHighlightSmall", 11, WHITE, "LEFT", BAR_W)
  h.legend:SetPoint("TOPLEFT", BAR_X, -80)

  local bar = CreateFrame("Frame", nil, f, BD)
  bar:SetPoint("TOPLEFT", BAR_X - 4, -96)
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
  h.bar = bar
  h.ticks, h.labels = {}, {}
  for i = 1, 20 do
    local tick = tex(bar, "OVERLAY")
    tick:SetColorTexture(0, 0, 0, 0.8)
    tick:SetSize(1, 14)
    h.ticks[i] = tick
  end
  for i = 1, 11 do h.labels[i] = text(f, "GameFontHighlightSmall", 10, { 0.75, 0.72, 0.65 }, "CENTER", 24) end
  tooltip(bar, function(tip)
    local lo, hi = UI.barLo or 1, UI.barHi or 2
    tip:AddLine(string.format("Level %d to %d", lo, hi), GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Blue: where you are now.", 0.5, 0.7, 1)
    tip:AddLine(QB:Banking() and "Purple: after handing in everything banked now." or "Purple: after handing in the quests that are ready.", 0.8, 0.4, 0.8)
    tip:AddLine("Pale: after the whole plan.", 0.85, 0.75, 1)
    local need = 0
    for l = lo, hi - 1 do need = need + (QB.Data.TO_NEXT[l] or 0) end
    tip:AddLine(string.format("Level %d to %d takes %s XP.", lo, hi, QB.Comma(need)), 0.8, 0.8, 0.8)
    local held, nextCap = QB:Lock()
    if held then
      tip:AddLine(string.format("The game holds you at level %d for now. QuestBank banks your log for the cap going up to %d.", held, nextCap), 1, 0.82, 0, true)
    elseif QB:Mode() == "rush" then
      tip:AddLine("The level cap went up: time to cash your bank in.", 1, 0.82, 0, true)
    else
      tip:AddLine(string.format("Questing: the game lets you level to %d, so hand quests in as you go.", QB.CAP), 0.8, 0.8, 0.8, true)
    end
    local D, st = QB.Data, QB.Data.STATS
    if st then
      tip:AddLine(" ")
      tip:AddLine(string.format("Quest data read %s, Forever client %s.", D.READ or "", D.BUILD or ""), 0.6, 0.6, 0.6, true)
      tip:AddLine(string.format("Of %d quests players have met in Forever: %d without a read multiplier, %d without a known turn-in spot, %d handed in inside a dungeon.",
        st.quests, st.noMult, st.noTurn, st.inside), 0.6, 0.6, 0.6, true)
      if st.classic and st.classic > 0 then
        tip:AddLine(string.format("%d more come from the Classic database and are marked until someone sees them in Forever.", st.classic), 0.6, 0.6, 0.6, true)
      end
    end
  end)

  h.toggles = {}
  local defs = {
    { key = "mounted", icon = T.mount }, { key = "goal", icon = T.hourglass }, { key = "pins", icon = T.map },
  }
  for i, d in ipairs(defs) do
    local b = iconButton(f, 30, d.icon)
    b:SetPoint("TOPRIGHT", -(34 + (#defs - i) * 66), -46)
    b.caption = text(f, "GameFontHighlightSmall", 10, WHITE, "CENTER", 64)
    b.caption:SetPoint("TOP", b, "BOTTOM", 0, -8)
    b.key = d.key
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", QB.Safe(function(self, which) UI:Switch(self.key, which) end, "header switch"))
    tooltip(b, function(tip, self) UI:SwitchTooltip(tip, self.key) end)
    h.toggles[d.key] = b
    b:Hide(); b.caption:Hide()
  end
  -- what matters while questing, at a glance: quests ready and their XP, rested XP, XP an hour, time at this level
  h.stats = {}
  local STATS = { { "ready", "Ready" }, { "rested", "Rested" }, { "rate", "XP an hour" }, { "atlevel", "At this level" } }
  for i, st in ipairs(STATS) do
    local t = CreateFrame("Frame", nil, f, BD)
    t:SetSize(96, 50)
    t:SetPoint("TOPRIGHT", -(18 + (#STATS - i) * 102), -44)
    backdrop(t, FLAT, T.tipBorder, 10, 2)
    if t.SetBackdropColor then t:SetBackdropColor(0.07, 0.09, 0.12, 0.95) end
    if t.SetBackdropBorderColor then t:SetBackdropBorderColor(0.45, 0.36, 0.2, 0.9) end
    t.value = text(t, "GameFontNormalLarge", 15, GOLD, "CENTER", 88)
    t.value:SetPoint("TOP", 0, -8)
    t.caption = text(t, "GameFontNormalSmall", 10, INK_SOFT, "CENTER", 88)
    t.caption:SetPoint("BOTTOM", 0, 7)
    t.caption:SetText(st[2])
    t.key = st[1]
    tooltip(t, function(tip, self) UI:StatTooltip(tip, self.key) end)
    h.stats[st[1]] = t
  end
end

function UI:StatTooltip(tip, key)
  if key == "ready" then
    tip:AddLine("Ready to hand in", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Finished quests in your log, and the XP they pay at your level.", 1, 1, 1, true)
  elseif key == "rested" then
    tip:AddLine("Rested XP", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Kills pay double until it runs out. Inns, cities and a camp tent build it; the Cozy Sleeping Bag's bonus is a buff of its own.", 1, 1, 1, true)
  elseif key == "rate" then
    tip:AddLine("XP an hour", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Since you logged in, kills and quests together. Shown after ten minutes.", 1, 1, 1, true)
  elseif key == "atlevel" then
    tip:AddLine("Time at this level", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Played at this level so far. At each level-up QuestBank says how long the last one took.", 1, 1, 1, true)
  end
end

function UI:Switch(key, which)
  local set = QB:Settings()
  if key == "mounted" then
    if which == "RightButton" then
      set[key] = "auto"
    else
      set[key] = not QB:Mounted()
    end
  elseif key == "goal" then
    if which == "RightButton" then
      -- stop banking: back to looking for a lock if you forced one, else questing from here
      QB:SetLock(QB:LockChoice() == "on" and "auto" or "off")
    else
      set.goal = set.goal == "hour" and "route" or "hour"
    end
  elseif key == "lock" then
    QB:SetLock(QB:LockChoice() == "off" and "auto" or "on")
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
  elseif key == "goal" then
    tip:AddLine(set.goal == "hour" and "Plan for the first hour" or "Plan for the whole route", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("First hour: the highest level at the 60-minute mark, whatever comes after. Whole route: the highest level at the end, in the least time.", 1, 1, 1, true)
    local held, nextCap = QB:Lock()
    if held then
      tip:AddLine(string.format("Banking: the game holds you at level %d, and the plan is for the cap going up to %d.", held, nextCap), 0.8, 0.8, 0.8, true)
    end
    tip:AddLine("Right-click: stop banking and plan for questing.", 0.6, 0.6, 0.6, true)
  elseif key == "lock" then
    tip:AddLine("Questing", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("No level lock: the game lets you level, so hand quests in as you go. The route plans the quickest way to hand in what's ready, and the green arrows mark chains worth carrying on.", 1, 1, 1, true)
    tip:AddLine(QB:LockChoice() == "off" and "You turned banking off. Click to let QuestBank look for a level lock again."
      or "Banking only pays off while the game holds your level at a cap. Click to bank anyway.", 0.6, 0.6, 0.6, true)
  elseif key == "pins" then
    tip:AddLine(set.pins and "Map pins on" or "Map pins off", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Numbered pins on the world map for every stop on the route, and ! pins where planned quests start.", 1, 1, 1, true)
    tip:AddLine("Right-click: waypoint on the next stop.", 0.6, 0.6, 0.6)
  end
end

function UI:CreateContent(f)
  local c = CreateFrame("Frame", nil, f, BD)
  c:SetPoint("TOPLEFT", SIDE + 8, -138)
  c:SetPoint("BOTTOMRIGHT", -14, 14)
  backdrop(c, FLAT, T.tipBorder, 12, 3)
  if c.SetBackdropColor then c:SetBackdropColor(SLATE2[1], SLATE2[2], SLATE2[3], 0.92) end
  if c.SetBackdropBorderColor then c:SetBackdropBorderColor(0.45, 0.36, 0.2, 0.9) end
  self.content = c
  self.views = {
    self:CreateLogView(c),
    self:CreatePrepView(c),
    self:CreateRouteView(c),
    self:CreatePartyView(c),
    self:CreateSettingsView(c),
    self:CreatePrepView(c, true), -- Now: the three places worth going to from where you stand
    self:CreateJournalView(c),    -- the Dungeon Journal (DungeonMap.lua), built the first time it shows
    self:CreateMapView(c),        -- the Map (MapPage.lua), the same way
    self:CreateGearView(c),       -- Gear (Gear.lua): what you wear, and the best upgrade to get for every slot
  }
end

-- a page another file builds the first time it shows, to the page's size: mod.Attach(page, w, h), then mod.Refresh()
local function attachedView(parent, key)
  local v = CreateFrame("Frame", nil, parent)
  v:SetPoint("TOPLEFT", 8, -8)
  v:SetPoint("BOTTOMRIGHT", -8, 8)
  v.Refresh = function()
    local mod = QB[key]
    if not mod then return end
    -- the content frame is the window less the sidebar, the header and the margins
    mod.Attach(v, W - SIDE - 8 - 14 - 16, H - 138 - 14 - 16)
    mod.Refresh()
  end
  return v
end
function UI:CreateJournalView(parent) return attachedView(parent, "DMap") end
function UI:CreateMapView(parent) return attachedView(parent, "MapPage") end
function UI:CreateGearView(parent) return attachedView(parent, "Gear") end

-- the sidebar: the pages in groups, each with its icon and a count where one helps. The Map is QuestBank's map page,
-- or its action where that is off or missing (act: the game's world map, UI.OpenMap). UI.tabs[i] is page i's button,
-- as the tab bar had them. key: its key binding's name (Bindings.xml, QUESTBANK_<key>), which the Key Bindings list
-- shows with the entry's name
local SIDEBAR = {
  { group = "Questing" },
  { tab = 6, name = "Now", icon = "sideNow", key = "NOW" },
  { tab = 1, name = "Quest Log", icon = "sideLog", key = "LOG", count = function() return QB.state.logCount or 0 end },
  { tab = 2, name = "Available", icon = "sideAvail", key = "AVAILABLE" },
  { tab = 3, name = "Route", icon = "sideRoute", key = "ROUTE" },
  { tab = 9, name = "Gear", icon = "sideGear", key = "GEAR" },
  { group = "Together" },
  { tab = 4, name = "Party", icon = "sideParty", key = "PARTY", count = function() return QB.Sync and #(QB.Sync:Members() or {}) or 0 end },
  { group = "World" },
  { tab = 7, name = "Dungeon Journal", icon = "sideJournal", key = "JOURNAL" },
  { tab = 8, act = function() UI.OpenMap() end, name = "Map", icon = "sideMap", key = "MAP" },
  { group = "QuestBank" },
  { tab = 5, name = "Settings", icon = "sideSettings", key = "SETTINGS" },
}
UI.SIDEBAR = SIDEBAR
function UI:CreateTabs(f)
  self.tabs = {}
  local side = CreateFrame("Frame", nil, f)
  side:SetPoint("TOPLEFT", 10, -40)
  side:SetPoint("BOTTOMLEFT", 10, 14)
  side:SetWidth(SIDE - 8)
  local rule = tex(side, "BACKGROUND", FLAT)
  rule:SetPoint("TOPRIGHT", 0, 0)
  rule:SetPoint("BOTTOMRIGHT", 0, 0)
  rule:SetWidth(1)
  rule:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.25)
  self.sidebar = side
  self.sideButtons = {}
  local y = 4
  for _, e in ipairs(SIDEBAR) do
    if e.group then
      local g = text(side, "GameFontNormalSmall", 10, GOLD_SOFT, "LEFT", SIDE - 30)
      g:SetPoint("TOPLEFT", 10, -y - 6)
      g:SetText(string.upper(e.group))
      y = y + 22
    else
      local b = CreateFrame("Button", nil, side)
      b:SetSize(SIDE - 20, 30)
      b:SetPoint("TOPLEFT", 4, -y)
      b.on = tex(b, "BACKGROUND", FLAT)
      b.on:SetAllPoints()
      b.on:SetVertexColor(0.25, 0.2, 0.1, 0.9)
      b.on:Hide()
      b.bar = tex(b, "ARTWORK", FLAT)
      b.bar:SetPoint("TOPLEFT", 0, 0)
      b.bar:SetPoint("BOTTOMLEFT", 0, 0)
      b.bar:SetWidth(3)
      b.bar:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
      b.bar:Hide()
      local hi = tex(b, "HIGHLIGHT", FLAT)
      hi:SetAllPoints()
      hi:SetVertexColor(1, 0.82, 0.3, 0.08)
      b.icon = tex(b, "ARTWORK", T[e.icon], 20, 20)
      b.icon:SetPoint("LEFT", 8, 0)
      b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      b.label = text(b, "GameFontNormal", 12, INK, "LEFT", SIDE - 76)
      b.label:SetPoint("LEFT", 36, 0)
      b.label:SetText(e.name)
      b.count = text(b, "GameFontNormalSmall", 10, INK_SOFT, "RIGHT", 28)
      b.count:SetPoint("RIGHT", -8, 0)
      b.entry = e
      if e.tab then
        b:SetScript("OnClick", QB.Safe(function() if e.act and not UI.MapPageOn() then e.act() else UI:ShowTab(e.tab) end end, "sidebar"))
        self.tabs[e.tab] = b
      else
        b:SetScript("OnClick", QB.Safe(function() e.act() end, "sidebar"))
      end
      self.sideButtons[#self.sideButtons + 1] = b
      y = y + 32
    end
  end
end

function UI:ShowErrors()
  T = T or QB.Data.TEX
  local list = QuestBankDB.errors or {}
  -- calls the game blocked and blamed on QuestBank (Core.lua, Err.Blocked), newest first
  local blocked = type(QuestBankDB.diag) == "table" and type(QuestBankDB.diag.blocked) == "table" and QuestBankDB.diag.blocked or {}
  local n = #list + #blocked
  local out = { string.format("QuestBank %s, %d problem%s recorded (Ctrl+A then Ctrl+C copies all):", QB.version, n, n == 1 and "" or "s"), "" }
  for i = #blocked, 1, -1 do
    local b = blocked[i]
    out[#out + 1] = string.format("[%s] %sx, the game %s %s%s, version %s", date and b.at and date("%Y-%m-%d %H:%M:%S", b.at) or "", b.n or 1,
      b.kind == "forbidden" and "forbade" or "blocked", tostring(b.fn or "?"), b.combat and " in combat" or "", b.qb or "?")
    out[#out + 1] = b.stack or ""
    out[#out + 1] = ""
  end
  for _, e in ipairs(list) do
    out[#out + 1] = string.format("[%s] %sx, %s, version %s", e.last or "", e.count or 1, e.where or "?", e.version or "?")
    out[#out + 1] = e.msg or ""
    out[#out + 1] = e.stack or ""
    out[#out + 1] = ""
  end
  if n == 0 then out[#out + 1] = "Nothing recorded. If Blizzard's error window showed one, copy its text instead." end
  local f = self.errFrame
  if not f then
    f = CreateFrame("Frame", "QuestBankErrors", UIParent, BD)
    self.errFrame = f
    f:SetSize(560, 360)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(30)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    backdrop(f, T.bg, T.border, 24, 7, true)
    f.title = text(f, "GameFontNormal", 13, GOLD, "LEFT", 480)
    f.title:SetPoint("TOPLEFT", 18, -16)
    f.title:SetText("QuestBank problems")
    UI.CloseButton(f)
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 18, -40)
    sf:SetPoint("BOTTOMRIGHT", -36, 18)
    f.eb = CreateFrame("EditBox", nil, sf)
    f.eb:SetMultiLine(true)
    f.eb:SetAutoFocus(false)
    f.eb:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    f.eb:SetWidth(490)
    f.eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(f.eb)
    if UISpecialFrames then table.insert(UISpecialFrames, "QuestBankErrors") end
  end
  f.eb:SetText(table.concat(out, "\n"))
  f:Show()
  f.eb:SetFocus()
  f.eb:HighlightText()
end

function UI:ShowTab(i)
  if self.tab and self.tab ~= i and self.tab ~= 7 and self.tab ~= 8 then self.lastTab = self.tab end
  QB:Settings().tab = i
  self.tab = i
  for k, v in ipairs(self.views) do v:SetShown(k == i) end
  for k, b in pairs(self.tabs) do
    local on = k == i
    b.on:SetShown(on); b.bar:SetShown(on)
    b.label:SetTextColor(on and GOLD[1] or INK[1], on and GOLD[2] or INK[2], on and GOLD[3] or INK[3])
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

-- QuestBank's own map (MapPage.lua): on Forever with the game's map canvas, unless Settings gave the Map key back
function UI.MapPageOn() return QB.MapPage ~= nil and QB.MapPage.On() end

-- a page's key: the window open on that page, or shut when it is open on that page already
function UI:TogglePage(tab)
  self:Create()
  if self.frame:IsShown() and self.tab == tab then self.frame:Hide(); return false end
  self:Open(tab)
  return true
end

-- the Map: the game's own world map, on your zone, with QuestBank's map icons and route pins on it as layers of their
-- own (QuestMap.lua, Pins.lua). OpenWorldMap opens it and HideUIPanel shuts it: both hand the panel to the game's own
-- secure panel code, so the map lays itself out and draws its pins as the game. Never ToggleWorldMap: that sizes the
-- map and fills its quest log as QuestBank, and the game later blames QuestBank for what it blocks there. The game
-- lets an addon open a panel only out of a fight (its own map key works in one). toggle: shut it when it is open
function UI.OpenMap(toggle)
  local wm = WorldMapFrame
  if not (wm and OpenWorldMap and HideUIPanel) then return false end
  if (QB.Pins and QB.Pins.InCombat and QB.Pins.InCombat()) or (InCombatLockdown and InCombatLockdown()) then
    QB:Print("In a fight only the game's own map key opens the map.")
    return false
  end
  if wm:IsShown() then
    if toggle then pcall(HideUIPanel, wm); return false end
    -- open on another map: shut and opened again, where the game puts it on your zone
    local ok, here = pcall(function() return MapUtil.GetDisplayableMapForPlayer() end)
    here = ok and QB.Plain(here) or nil
    if not here or here == QB.Plain(wm:GetMapID()) then return true end
    pcall(HideUIPanel, wm)
  end
  pcall(OpenWorldMap)
  return wm:IsShown() and true or false
end

-- the key bindings (Bindings.xml): the game's Key Bindings, a QuestBank section with a line each, named as the
-- sidebar names them. A page's key opens the window on that page or shuts it there; so does the Map key, on the Map
-- page, or with that off the game's world map
BINDING_HEADER_QUESTBANK = "QuestBank"
BINDING_NAME_QUESTBANK_WINDOW = "Open or close QuestBank"
BINDING_NAME_QUESTBANK_MINIMAP_BIGGER = "Minimap bigger"
BINDING_NAME_QUESTBANK_MINIMAP_SMALLER = "Minimap smaller"
UI.PAGE_KEYS = {}
for _, e in ipairs(SIDEBAR) do
  if e.key then
    _G["BINDING_NAME_QUESTBANK_" .. e.key] = e.name
    if e.tab and not e.act then UI.PAGE_KEYS[e.key] = e.tab end
  end
end
QuestBankKeys = {
  Window = QB.Safe(function() UI:Toggle() end, "key: window"),
  Page = QB.Safe(function(key) local tab = UI.PAGE_KEYS[key]; if tab then UI:TogglePage(tab) end end, "key: page"),
  Map = QB.Safe(function() if UI.MapPageOn() then UI:TogglePage(8) else UI.OpenMap(true) end end, "key: map"),
  Bigger = QB.Safe(function() if QB.Mini then QB.Mini.Size(1.15) end end, "key: minimap bigger"),
  Smaller = QB.Safe(function() if QB.Mini then QB.Mini.Size(1 / 1.15) end end, "key: minimap smaller"),
}

----------------------------------------------------------------------------
-- refresh
----------------------------------------------------------------------------
local refresh
function UI:Refresh() QB.Try("window", refresh, self) end
refresh = function(self)
  if not (self.frame and self.frame:IsShown()) then return end
  for _, b in ipairs(self.sideButtons or {}) do
    local n = b.entry.count and b.entry.count() or 0
    b.count:SetText(n > 0 and tostring(n) or "")
  end
  if not QB.fresh then QB:Recompute() end
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
  local banking = QB:Banking()
  -- the bar's window: from the lock to the next cap when banking, else your next ten levels
  local lo, hi
  if banking then
    local held = QB:Lock()
    local was = QB:Held()
    lo = held or (was and was.level) or math.floor(cur)
    hi = QB.CAP
  else
    lo = math.floor(cur)
    hi = math.min(lo + 10, QB.CAP)
  end
  if lo >= QB.MAXLEVEL then lo = QB.MAXLEVEL - 1 end
  if hi <= lo then hi = lo + 1 end
  UI.barLo, UI.barHi = lo, hi
  local span = hi - lo
  local function w(level) return math.max(1, math.min(BAR_W, BAR_W * (level - lo) / span)) end
  local tstep = span <= 20 and 1 or 5
  local ti = 0
  for l = lo + tstep, hi - 1, tstep do
    ti = ti + 1
    local t = h.ticks[ti]
    if not t then break end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", 4 + BAR_W * (l - lo) / span, -4)
    t:Show()
  end
  for i = ti + 1, #h.ticks do h.ticks[i]:Hide() end
  local step = span <= 5 and 1 or (span <= 10 and 2 or 5)
  local k = 0
  for l = lo, hi, step do
    k = k + 1
    local lab = h.labels[k]
    if not lab then break end
    lab:ClearAllPoints()
    lab:SetPoint("TOP", h.bar, "BOTTOMLEFT", 4 + BAR_W * (l - lo) / span, 0)
    lab:SetText(l)
    lab:Show()
  end
  for i = k + 1, #h.labels do h.labels[i]:Hide() end
  h.fillCur:SetWidth(w(cur))
  local nowL = (now and not now.empty) and now.level or cur
  local planL = (plan and not plan.empty) and plan.level or cur
  local plan60 = (plan and not plan.empty) and plan.at60 or cur
  h.fillNow:SetWidth(w(nowL))
  h.fillPlan:SetWidth(w(planL))
  if banking then
    h.legend:SetText(string.format("|cff6f9fffNow %.1f|r    |cffc080c0Banked %.1f|r    |cffd8c8ffLog and pick-ups %.1f|r    |cffaaaaaaAt 60 min %.1f|r",
      cur, nowL, planL, plan60))
  else
    -- questing: where the log takes you, in one short line; the bar says the rest
    h.legend:SetText(planL > cur + 0.05 and string.format("|cffd8c8ffYour log is worth level %.1f|r", planL) or "")
  end
  local st = h.stats
  if st then
    local nReady, xpReady = 0, 0
    for id, e in pairs(s.log or {}) do if e.complete then nReady = nReady + 1; xpReady = xpReady + (QB:Value(id) or 0) end end
    st.ready.value:SetText(nReady > 0 and string.format("%d \194\183 %s", nReady, QB.Short(xpReady)) or "0")
    local rest = GetXPExhaustion and QB.Plain(GetXPExhaustion()) or nil
    local max = UnitXPMax and QB.Plain(UnitXPMax("player")) or nil
    st.rested.value:SetText((type(rest) == "number" and type(max) == "number" and max > 0) and string.format("%d%%", math.floor(rest / max * 100 + 0.5)) or "0%")
    local rate = QB.Timer and QB.Timer.XPPerHour()
    st.rate.value:SetText(rate and QB.Short(math.floor(rate + 0.5)) or "\226\128\148")
    st.atlevel.value:SetText(QB.Timer and QB.Timer.Span(QB.Timer.LevelTime()) or "")
  end
  local set = QB:Settings()
  local tg = h.toggles
  local mounted = QB:Mounted()
  setIcon(tg.mounted.icon, mounted and T.mount or T.foot)
  tg.mounted.caption:SetText(mounted and "Mounted" or "On foot")
  -- the third switch: the hour's goal when banking, the lock itself when questing
  local g = tg.goal
  g:Hide() -- (the switches live on in Settings: the header shows the stat tiles)
  if g.caption then g.caption:Hide() end
  if banking then
    g.key = "goal"
    setIcon(g.icon, T.hourglass)
    g.caption:SetText(set.goal == "hour" and "First hour" or "Whole route")
  else
    g.key = "lock"
    setIcon(g.icon, T.questGeneric)
    g.caption:SetText("Questing")
  end
  tg.pins.icon:SetDesaturated(not set.pins)
  tg.pins.caption:SetText(set.pins and "Pins on" or "Pins off")
end

----------------------------------------------------------------------------
-- page 1: the quest log as a bank
----------------------------------------------------------------------------
local LEFT, RIGHT = 16, 420
-- the Quest Log's grid, 8 across: each slot shows its quest's place, and the gap between slots lets each place's band
-- read as one group
local LOG_ICON, LOG_STEP, LOG_TOP = 36, 49, 48


local modWatch = CreateFrame("Frame")
modWatch:RegisterEvent("MODIFIER_STATE_CHANGED")
modWatch:SetScript("OnEvent", function()
  local r = UI.hoverRow
  if r and r.rewardId and r:IsVisible() and r.IsMouseOver and r:IsMouseOver() then
    local f = r:GetScript("OnEnter")
    if f then f(r) end
  end
end)

function UI:CreateLogView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()
  v.title = text(v, "GameFontNormalLarge", 15, INK, "LEFT", 150)
  v.title:SetPoint("TOPLEFT", LEFT, -12)
  v.worth = text(v, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", RIGHT - LEFT - 20)
  v.worth:SetPoint("TOPLEFT", LEFT, -30)
  v.slots = {}
  for i = 1, QB.LOG_SLOTS do
    -- the picture is the quest's place: a zone's own icon, a dungeon's (UI.LogPicture)
    local b = iconButton(v, LOG_ICON, nil)
    local col, row = (i - 1) % 8, math.floor((i - 1) / 8)
    b:SetPoint("TOPLEFT", LEFT + 4 + col * LOG_STEP, -LOG_TOP - row * LOG_STEP)
    -- the band behind a run of quests in one place: it runs on under the gap to the next slot of the same place
    b.band = tex(v, "BACKGROUND", FLAT)
    b.band:SetPoint("TOPLEFT", b, "TOPLEFT", -3, 3)
    b.band:SetSize(LOG_ICON + 6, LOG_ICON + 6)
    b.band:Hide()
    b.frame = b:CreateTexture(nil, "OVERLAY", nil, 0)
    b.frame:SetTexture(T.iconFrame)
    b.frame:SetAllPoints()
    -- ready to hand in: the bags' green glow round the slot (the action buttons' border, tinted, where the client has
    -- no such atlas), and the ready check in the corner
    b.glow = b:CreateTexture(nil, "OVERLAY", nil, 1)
    if QB.Art(b.glow, "bags-glow-green", "Interface\\Buttons\\UI-ActionButton-Border") then
      b.glow:SetSize(LOG_ICON + 3, LOG_ICON + 3)
    else
      b.glow:SetSize(LOG_ICON * 1.72, LOG_ICON * 1.72)
      b.glow:SetVertexColor(0.3, 1, 0.3)
    end
    b.glow:SetPoint("CENTER")
    b.glow:SetBlendMode("ADD")
    b.glow:Hide()
    -- a follow-up: the chain's link from the quest before it
    b.link = tex(b, "OVERLAY", T.upgrade, 12, 13)
    b.link:SetTexCoord(66 / 512, 86 / 512, 93 / 256, 115 / 256)
    b.link:SetPoint("RIGHT", b, "LEFT", 3, 0)
    if b.link.SetRotation then b.link:SetRotation(-math.pi / 2) end
    b.link:Hide()
    b.xp = text(b, "NumberFontNormal", 11, WHITE, "RIGHT", 40)
    b.xp:SetPoint("BOTTOMRIGHT", 0, 2)
    -- top left: the ready check, the red X of a quest you cut, the ! of one still to pick up; nothing while you work on it
    b.mark = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.mark:SetSize(15, 15)
    b.mark:SetPoint("TOPLEFT", 1, -1)
    -- bottom left: the green arrow of a chain worth carrying on; bottom right the XP
    b.up = upgradeMark(b, 13, 14)
    b.up:SetPoint("BOTTOMLEFT", 1, 2)
    -- top right: the item it rewards, small on a dark square
    b.rwBack = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.rwBack:SetColorTexture(0, 0, 0, 0.85)
    b.rwBack:SetSize(16, 16)
    b.rwBack:SetPoint("TOPRIGHT", -1, -1)
    b.rw = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.rw:SetSize(14, 14)
    b.rw:SetPoint("CENTER", b.rwBack, "CENTER", 0, 0)
    b.rw:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, which)
      if not self.q then return end
      -- Ctrl-click: the reward in its corner, on you in the dressing room
      if self.rwId and which ~= "RightButton" and QB.DressClick() then QB.API.DressUp(self.rwId) return end
      UI.QuestClick(self.q, self.st, which)
    end)
    tooltip(b, function(tip, self)
      if self.q then
        if self.pick then tip:AddLine("To pick up: not in your log yet. Click for a waypoint to whoever gives it; right-click to take it off the list.", 1, 0.82, 0, true) end
        if self.follow then tip:AddLine("Follow-up of " .. self.follow.name .. ": " .. (self.q.give and self.q.give.n and ("from " .. self.q.give.n .. ", ") or "") .. "do it while you're here.", 0.5, 1, 0.5, true) end
        UI.QuestTooltip(tip, self.q, self.st, self.value, self.pct, self.plvl)
        if self.advice then tip:AddLine(self.advice, 1, 0.55, 0.45, true) end
        if self.rwId and QB.API.Dressable(self.rwId) then
          local name = QB.API.ItemInfo(self.rwId)
          tip:AddLine("Ctrl-click: try on " .. (name or "the reward") .. ".", 0.5, 0.5, 0.5, true)
        end
      elseif self.entry then
        tip:AddLine(self.entry.title, GOLD[1], GOLD[2], GOLD[3])
        tip:AddLine("Not in QuestBank's catalog, so the route can't place it.", 1, 1, 1, true)
        tip:AddLine(self.entry.complete and "Complete" or "Not complete", 0.8, 0.8, 0.8)
        tip:AddLine("Hand it in or abandon it to free the slot.", 1, 0.55, 0.45, true)
      else
        tip:AddLine("Free slot", GOLD[1], GOLD[2], GOLD[3])
        tip:AddLine("Fill it with the best quest from the swaps on the right.", 1, 1, 1, true)
      end
    end)
    v.slots[i] = b
  end
  -- under the grid: your bags, a row of slots in the grid's columns, then what left the log
  local foot = LOG_TOP + (math.ceil(QB.LOG_SLOTS / 8) - 1) * LOG_STEP + LOG_ICON
  v.bagLabel = text(v, "GameFontNormal", 13, INK, "LEFT", 380)
  v.bagLabel:SetPoint("TOPLEFT", LEFT, -(foot + 16))
  v.bagLabel:SetText("In your bags, no log slot needed")
  v.bagSlots = {}
  for i = 1, 8 do
    local b = iconButton(v, 32, nil)
    b:SetPoint("TOPLEFT", LEFT + 6 + (i - 1) * LOG_STEP, -(foot + 38))
    b.count = text(b, "NumberFontNormal", 11, WHITE, "RIGHT", 40)
    b.count:SetPoint("BOTTOMRIGHT", 0, 2)
    tooltip(b, function(tip, self)
      local it = self.item
      if not it then return end
      tip:AddLine(it.name or "", GOLD[1], GOLD[2], GOLD[3])
      if it.need then tip:AddLine(string.format("%d of %d in your bags", QB.API.ItemCount(it.id), it.need), 1, 1, 1) end
      if it.q then UI.QuestTooltip(tip, it.q, QB:Status(it.q), (QB:Value(it.q.id))) end
      if it.id == 211527 then tip:AddLine("Camp in it: your rested XP builds faster.", 0.8, 0.8, 0.8, true) end
      dressHint(tip, it.id)
    end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", QB.Safe(function(self, which)
      local it = self.item
      if not it then return end
      if it.id and which ~= "RightButton" and QB.DressClick() then QB.API.DressUp(it.id) return end
      if IsShiftKeyDown and IsShiftKeyDown() and UI.LinkItem(it.id, it.name) then return end
      if it.q then UI.QuestClick(it.q, QB:Status(it.q), which) end
    end, "bag slot"))
    v.bagSlots[i] = b
  end
  v.dropTitle = text(v, "GameFontNormal", 12, BAD, "LEFT", 300)
  v.dropTitle:SetPoint("TOPLEFT", LEFT, -(foot + 84))
  v.dropClear = button(v, "Clear", 64)
  v.dropClear:SetPoint("TOPLEFT", LEFT + 316, -(foot + 80))
  v.dropClear:SetScript("OnClick", function()
    local p = QB:Plan()
    for k in pairs(p.removed) do p.removed[k] = nil end
    UI:Refresh()
  end)
  v.drops = para(v, "GameFontNormalSmall", 11, INK_SOFT, 380)
  v.drops:SetPoint("TOPLEFT", LEFT, -(foot + 104))
  v.drops:SetHeight(50)

  -- the finder: what to look for in the quests you could still take
  local st = text(v, "GameFontNormalLarge", 15, INK, "LEFT", 320)
  st:SetPoint("TOPLEFT", RIGHT, -12)
  st:SetText("Find quests")
  v.finds = {}
  for i, m in ipairs(UI.FINDS) do
    local b = CreateFrame("Button", nil, v)
    b:SetSize(80, 18)
    b:SetPoint("TOPLEFT", RIGHT + (i - 1) * 84, -34)
    b.hi = tex(b, "HIGHLIGHT", T.rowHi)
    b.hi:SetAllPoints()
    b.hi:SetBlendMode("ADD")
    b.label = text(b, "GameFontNormalSmall", 10, INK_SOFT, "CENTER", 80)
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetText(m.name)
    b.label.base = m.name
    b.key = m.key
    b:SetScript("OnClick", function(self) UI.findMode = self.key; UI:Refresh() end)
    tooltip(b, function(tip, self)
      tip:AddLine(m.name, GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine(m.tip, 1, 1, 1, true)
    end)
    v.finds[i] = b
  end
  -- the reward finders reach two levels further when asked (off until ticked): quests you can take within 2 levels
  v.ahead = CreateFrame("CheckButton", nil, v, "UICheckButtonTemplate")
  v.ahead:SetSize(20, 20)
  v.ahead:SetPoint("TOPLEFT", RIGHT + 112, -10)
  v.ahead.label = text(v, "GameFontNormalSmall", 10, INK_SOFT, "LEFT", 100)
  v.ahead.label:SetPoint("LEFT", v.ahead, "RIGHT", 1, 0)
  v.ahead.label:SetText("2 levels ahead")
  v.ahead:SetScript("OnClick", QB.Safe(function(self)
    QB:Settings().finderAhead = self:GetChecked() and true or false
    UI:Refresh()
  end, "finder: 2 levels ahead"))
  tooltip(v.ahead, function(tip)
    tip:AddLine("Show quests I can take within 2 levels", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Best gear, Trinkets and Recipes list the quests you can take now. Ticked, they also list those you can take within 2 levels; their row says the level each needs.", 1, 1, 1, true)
  end)
  v.slotBtn = button(v, "Any slot", 90)
  v.slotBtn:SetPoint("TOPLEFT", RIGHT + 334 - 90, -10)
  v.slotBtn:SetScript("OnClick", QB.Safe(function()
    local items = { { "Any slot", function() UI.gearSlot = nil; UI:Refresh() end } }
    for _, g in ipairs(UI.GEAR_SLOTS) do items[#items + 1] = { g[1], function() UI.gearSlot = g[1]; UI:Refresh() end } end
    UI:ShowMenu("Best gear for", items)
  end, "gear slot"))
  v.swaps = {}
  for i = 1, 8 do
    local r = CreateFrame("Button", nil, v)
    r:SetSize(334, 38)
    r:SetPoint("TOPLEFT", RIGHT, -58 - (i - 1) * 40)
    r.hi = tex(r, "HIGHLIGHT", T.rowHi)
    r.hi:SetAllPoints()
    r.hi:SetBlendMode("ADD")

    r.hi:SetAlpha(0.6)
    r.addIcon = tex(r, "ARTWORK", nil, 30, 30)
    r.addIcon:SetPoint("LEFT", 2, 0)
    r.addIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.addName = text(r, "GameFontNormal", 12, INK, "LEFT", 240)
    r.addName:SetPoint("TOPLEFT", 40, -4)
    r.cutName = text(r, "GameFontNormalSmall", 10, INK_SOFT, "LEFT", 240)
    r.cutName:SetPoint("TOPLEFT", 40, -21)
    r.gain = text(r, "GameFontNormal", 13, GOOD, "RIGHT", 52)
    r.gain:SetPoint("RIGHT", -4, 0)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, which)
      local q = self.add
      if not q then return end
      -- on a reward row (Best gear, Trinkets, Recipes), Ctrl-click tries the reward on and Shift-click links it, not the quest
      if self.rewardId and which ~= "RightButton" and QB.DressClick() then QB.API.DressUp(self.rewardId) return end
      if self.rewardId and which ~= "RightButton" and IsShiftKeyDown and IsShiftKeyDown() then UI.LinkItemAlways(self.rewardId) return end
      -- one path decides where a click sends you: the giver, a chain's first step, a held step's turn-in
      UI.QuestClick(q, QB:Status(q), which)
    end)
    tooltip(r, function(tip, self)
      UI.hoverRow = self
      if self.rewardId and IsShiftKeyDown and IsShiftKeyDown() and tip.SetItemByID then
        tip:SetItemByID(self.rewardId) -- the item itself, as the game shows it
        dressHint(tip, self.rewardId)
        return
      end
      if self.cutTitle then
        tip:AddLine("Drop: " .. self.cutTitle, 1, 0.5, 0.4)
        tip:AddLine(QB.Comma(self.cutValue or 0) .. " XP " .. QB:OnTheDay(), 0.8, 0.8, 0.8)
        tip:AddLine(" ")
      end
      if self.via then
        tip:AddLine(string.format("Take %s now and hand it in inside %s. That gives you %s" .. (QB:Banking() and " to bank." or "."), self.via.name,
          self.via.cat and self.via.cat.name or "the dungeon", self.add.name), 1, 0.82, 0, true)
        tip:AddLine(" ")
      end
      if self.add then UI.QuestTooltip(tip, self.add, QB:Status(self.add), self.addValue, nil, nil, self.rewardId) end
      if self.reward then tip:AddLine(self.reward, 0.75, 0.75, 1, true) end
      dressHint(tip, self.rewardId)
      if self.rewardId then tip:AddLine("Hold Shift to see the item. To put the quest on your pick-up list, right-click it.", 0.6, 0.6, 0.6, true) end
    end)
    v.swaps[i] = r
  end
  v.noSwaps = para(v, "GameFontNormal", 12, INK_SOFT, 320)
  v.noSwaps:SetPoint("TOPLEFT", RIGHT, -64)
  v.noSwaps:SetHeight(44)
  v.legend = text(v, "GameFontNormalSmall", 10, INK_SOFT, "LEFT", 334)
  v.legend:SetPoint("TOPLEFT", RIGHT, -384)

  v.Refresh = function() UI:RefreshLogView(v) end
  return v
end


-- the Quest Log's slots in order: the quests by place, the nearest place first; in each, the ones ready to hand in
-- first, then the most XP; a quest's follow-up right after it (faded: you take it where you hand the first in, so
-- both get done on one visit); the quests you chose to pick up in their place too; quests left out of the route last.
-- { kind = "entry", it } | { kind = "follow", q, value, from } | { kind = "pick", q, value }, each with its group's number
function UI.LogCells(entries, picks)
  local s = QB.state
  local me = QB.API.WorldPosition()
  local groups, byKey = {}, {}
  local function group(key, name)
    local g = byKey[key]
    if not g then g = { key = key, name = name, items = {}, near = math.huge, value = 0 }; byKey[key] = g; groups[#groups + 1] = g end
    return g
  end
  local function nearTo(g, q)
    for _, n in ipairs({ q.turn, q.give }) do
      if me and n and n.m and not n.inside then
        local w = QB.Model.World(n.m, n.x, n.y)
        if w and w.c == me.c then
          local d = math.sqrt((w.wx - me.wx) ^ 2 + (w.wy - me.wy) ^ 2)
          if d < g.near then g.near = d end
        end
      end
    end
  end
  local cut = {}
  for _, it in ipairs(entries) do
    if it.cut or not it.q then cut[#cut + 1] = it
    else
      local cat = it.q.cat
      local g = group(cat and cat.key or "?", cat and cat.name or "")
      g.items[#g.items + 1] = it
      g.value = g.value + (it.value or 0)
      nearTo(g, it.q)
    end
  end
  for _, pk in ipairs(picks) do
    local cat = pk.q.cat
    local g = group(cat and cat.key or "?", cat and cat.name or "")
    g.picks = g.picks or {}
    g.picks[#g.picks + 1] = pk
    nearTo(g, pk.q)
  end
  table.sort(groups, function(a, b)
    if a.near ~= b.near then return a.near < b.near end
    return a.value > b.value
  end)
  local out, room = {}, QB.LOG_SLOTS
  -- the log's own quests always get a slot; then the quests you chose to pick up; follow-ups fill what is left
  local spare = room - #entries
  local pickRoom = math.min(#picks, math.max(0, spare))
  local followRoom = math.max(0, spare - pickRoom)
  local seen = {}
  for gi, g in ipairs(groups) do
    table.sort(g.items, function(a, b)
      if (a.e.complete or false) ~= (b.e.complete or false) then return a.e.complete or false end
      return (a.value or 0) > (b.value or 0)
    end)
    for _, it in ipairs(g.items) do
      out[#out + 1] = { kind = "entry", it = it, group = gi }
      local nq = UI.FollowUp(it.q)
      if nq and followRoom > 0 and not seen[nq.id] and not QB:Plan().add[nq.id] then
        seen[nq.id] = true
        followRoom = followRoom - 1
        out[#out + 1] = { kind = "follow", q = nq, value = QB.Model.XpAt(nq, s.level), from = it.q, group = gi }
      end
    end
    for _, pk in ipairs(g.picks or {}) do
      if pickRoom > 0 and not seen[pk.q.id] then
        seen[pk.q.id] = true
        pickRoom = pickRoom - 1
        out[#out + 1] = { kind = "pick", q = pk.q, value = pk.value, group = gi }
      end
    end
  end
  for _, it in ipairs(cut) do out[#out + 1] = { kind = "entry", it = it, group = #groups + 1 } end
  UI.logGroups = groups
  return out
end

-- a Quest Log slot's picture: the quest's place, a zone's own icon or a dungeon's; the quest's icon only when it has no place
function UI.LogPicture(q)
  local cat = q and q.cat
  return cat and (cat.zi or cat.icon) or (q and q.icon)
end

-- the item a quest rewards, for the slot's corner: the first to choose from, else the first it gives; its icon, or a bag
-- until the game sends the icon. nil when it rewards no item, or nobody knows yet
function UI.LogReward(q)
  local rw = q and Q.Rewards(q)
  if type(rw) ~= "table" then return nil end
  for _, key in ipairs({ "c", "r", "u" }) do
    local id = type(rw[key]) == "table" and rw[key][1]
    if id then return id, itemIcon(id) or T.bag end
  end
  return nil
end

local function showReward(b, q, alpha, grey)
  local id, icon = UI.LogReward(q)
  b.rwId = id
  if id then b.rw:SetTexture(icon); b.rw:SetDesaturated(grey or false) end
  b.rw:SetShown(id ~= nil); b.rwBack:SetShown(id ~= nil)
  b.rw:SetAlpha(alpha); b.rwBack:SetAlpha(alpha)
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
  v.title:SetText(string.format("Quest log  %d/%d", #entries, QB.LOG_SLOTS))
  -- the quests you chose to pick up fill the free slots, faded, with the pick-up mark: still yours to fetch
  local picks = {}
  for id in pairs(QB:Plan().add) do
    local q = Q.Get(id)
    if q and not s.log[id] then
      local st = QB:Status(q)
      if st.code ~= "done" and st.code ~= "wrong" then picks[#picks + 1] = { q = q, st = st, value = QB.Model.XpAt(q, s.level) } end
    end
  end
  table.sort(picks, function(a, b) return a.value > b.value end)
  -- the colour steps, at your level
  local k = QB.Scale(s.level)
  local function step(x)
    x = x * k
    if x >= 1000 then return QB.Short(math.floor(x / 100 + 0.5) * 100) end
    return tostring(math.floor(x / 10 + 0.5) * 10)
  end
  v.legend:SetText("") -- (the colours speak for themselves)
  local overflow = #picks - (QB.LOG_SLOTS - #entries)
  local ek, kal, dng = 0, 0, 0
  for _, it in ipairs(entries) do
    local cat = it.q and it.q.cat
    if cat then
      if cat.dungeon then dng = dng + 1 elseif cat.cont == 0 then ek = ek + 1 elseif cat.cont == 1 then kal = kal + 1 end
    end
  end
  local where = {}
  if ek > 0 then where[#where + 1] = "EK " .. ek end
  if kal > 0 then where[#where + 1] = "Kalimdor " .. kal end
  if dng > 0 then where[#where + 1] = dng .. " dungeon" end
  local xpText = QB:Banking() and string.format("%s XP on the day", QB.Short(total)) or string.format("%s XP", QB.Short(total))
  v.worth:SetText(xpText .. (#where > 0 and ("  \194\183  " .. table.concat(where, "  \194\183  ")) or "") .. (overflow > 0 and string.format("  \194\183  %d more to pick up", overflow) or ""))
  local cells = UI.LogCells(entries, picks)
  for i, b in ipairs(v.slots) do
    local cell = cells[i]
    local it = cell and cell.kind == "entry" and cell.it or nil
    b.q, b.st, b.entry, b.value, b.pct, b.plvl, b.pick, b.advice, b.follow, b.group = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil
    b.icon:SetAlpha(1)
    b.frame:SetAlpha(1)
    b.mark:SetAlpha(1)
    b.glow:Hide()
    b.link:Hide()
    -- the band: this place's colour, joined across the gap to the next slot on the row and to the slot under it when
    -- they are the same place, so a place reads as one block and the gaps part the places
    if cell then
      local nxt, under = cells[i + 1], cells[i + 8]
      local joined = nxt and nxt.group == cell.group and i % 8 ~= 0
      local down = under and under.group == cell.group
      local col = UI.BAND[(cell.group - 1) % #UI.BAND + 1]
      b.band:SetVertexColor(col[1], col[2], col[3], 0.9)
      b.band:SetWidth(joined and LOG_STEP + 1 or LOG_ICON + 6)
      b.band:SetHeight(down and LOG_STEP + 1 or LOG_ICON + 6)
      b.band:Show()
      b.group = cell.group
    else
      b.band:Hide()
    end
    if it then
      b.entry, b.value = it.e, it.value
      -- what to do about a slot that earns nothing: the advice the old Make room card gave
      if it.q then
        local low = (it.value or 0) < 500 * QB.Scale(s.level)
        if it.cut then b.advice = QB:IsSkipped(it.e.id) and "Skipped: out of the route for good. Right-click: Route it again."
          or QB.Data.CUT_NOTES[it.e.id] or "Left out of the route: hand it in or abandon it to free the slot."
        elseif low then b.advice = QB.Data.CUT_NOTES[it.e.id] or string.format(it.e.complete and "Pays next to nothing at level %d: hand it in now for the rewards." or "Pays next to nothing at level %d: abandon it to free the slot.", s.level) end
      end
      if it.q then b.q, b.st = it.q, it.st end
      setIcon(b.icon, it.q and UI.LogPicture(it.q) or (it.e.complete and T.questActive or T.questAvail))
      b.icon:SetDesaturated(it.cut or false)
      local c = QUALITY[tier(it.value)]
      b.frame:SetVertexColor(c[1], c[2], c[3])
      b.frame:SetShown(not it.cut)
      b.xp:SetText((it.value and not (it.q and it.q.xpUnknown and not it.q.liveFull)) and QB.Short(it.value) or "?")
      -- cut or unknown: greyed with the red X; ready: the green glow and the check; in progress: no mark
      local done = it.e.complete and not it.cut and it.q ~= nil
      if it.cut or not it.q then b.mark:SetTexture(T.notready); b.mark:Show()
      elseif done then b.mark:SetTexture(T.ready); b.mark:Show()
      else b.mark:Hide() end
      b.glow:SetShown(done)
      showReward(b, it.q, 1, it.cut)
      b.up:SetShown(it.q ~= nil and not it.cut and QB:Upgrade(it.q) ~= nil)
    elseif cell then
      -- a quest not in the log yet: a follow-up of the one before it, or one you chose to pick up; faded
      local q, value = cell.q, cell.value
      b.q, b.st, b.value = q, QB:Status(q), value
      b.pick = cell.kind == "pick" or nil
      b.follow = cell.kind == "follow" and cell.from or nil
      setIcon(b.icon, UI.LogPicture(q))
      b.icon:SetDesaturated(false)
      b.icon:SetAlpha(0.55)
      local c = QUALITY[tier(value)]
      b.frame:SetVertexColor(c[1], c[2], c[3])
      b.frame:SetAlpha(0.55)
      b.frame:Show()
      b.xp:SetText(QB.Short(value))
      b.mark:SetTexture(T.questAvail)
      b.mark:SetAlpha(0.8)
      b.mark:Show()
      showReward(b, q, 0.55)
      b.up:Hide()
      b.link:SetShown(cell.kind == "follow" and (i - 1) % 8 ~= 0)
    else
      b.icon:SetTexture(nil)
      b.frame:Hide()
      b.xp:SetText("")
      b.mark:Hide()
      showReward(b, nil, 1)
      b.up:Hide()
    end
  end
  v.cells = cells
  -- the step frame's click (StepFrame.lua): that quest's slot framed in gold, this once
  if UI.scrollToQuest then
    for _, b in ipairs(v.slots) do
      if b.q and b.q.id == UI.scrollToQuest then b.frame:SetVertexColor(GOLD[1], GOLD[2], GOLD[3]); b.frame:SetAlpha(1); b.frame:Show() end
    end
    UI.scrollToQuest = nil
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
    -- an item for a quest you already handed in starts nothing any more
    if q and not dup and not QB.API.IsDone(id) then bagItems[#bagItems + 1] = { id = q.bag and q.bag[1], name = q.name, q = q, icon = q.icon } end
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

  -- the finder's mode buttons
  v.slotBtn:SetShown(UI.findMode == "gear")
  v.slotBtn:SetText(UI.gearSlot or "Any slot")
  local ahead = QB:Settings().finderAhead and true or false
  v.ahead:SetShown(UI.findMode ~= "xp")
  v.ahead.label:SetShown(UI.findMode ~= "xp")
  v.ahead:SetChecked(ahead)
  for _, b in ipairs(v.finds) do
    local on = b.key == UI.findMode
    local col = on and INK or INK_SOFT
    b.label:SetTextColor(col[1], col[2], col[3])
    b.label:SetText(on and ("[" .. b.label.base .. "]") or b.label.base)
  end
  if UI.findMode ~= "xp" then
    local recipe = UI.findMode == "recipe"
    local found = self:FindRewards(UI.findMode, s.level)
    for i, r in ipairs(v.swaps) do
      local d = found[i]
      if d then
        r:Show()
        r.add, r.addValue, r.via, r.cutTitle, r.cutValue = d.q, d.value, nil, nil, nil
        local id = d.item
        local name = itemName(id) or ("item " .. id)
        setIcon(r.addIcon, QB.API.ItemIcon(id, d.q.icon) or d.q.icon)
        r.addName:SetText(d.q.name)
        local place = d.q.cat and d.q.cat.name or ""
        local mins = d.mins and string.format(", %d min", math.floor(d.mins + 0.5)) or ""
        -- a quest you can't take yet (2 levels ahead): the level it needs, kept as long as the line has room; a writ's
        -- turn-in (it pays no XP) or a repeatable says so before its place
        local at = (d.req or 0) > s.level and string.format("at %d", d.req) or nil
        local kind = d.q.turnIn and "Turn-in" or d.q.repeatable and "Repeatable" or nil
        local head = name .. (at and (" · " .. at) or "") .. (kind and (" · " .. kind) or "")
        local room = r.cutName:GetWidth() - 2
        local fits = { head .. " · " .. place .. mins, head .. " · " .. place, head, name .. (kind and (" · " .. kind) or ""), name }
        for _, line in ipairs(fits) do
          r.cutName:SetText(line)
          if r.cutName:GetStringWidth() <= room then break end
        end
        local showL = not recipe and d.ilvl > 0
        r.gain:SetText(showL and ("iL " .. d.ilvl) or QB.Short(d.value))
        local pay = d.q.turnIn and "No XP: a turn-in." or (QB.Comma(d.value) .. " XP " .. QB:OnTheDay() .. "." .. (d.q.repeatable and " Repeatable." or ""))
        r.reward = string.format("Rewards %s%s. %s", name, showL and string.format(" (item level %d)", d.ilvl) or "", pay)
          .. (at and string.format(" You can take it at level %d.", d.req) or "")
        r.rewardId = id
      else
        r:Hide()
      end
    end
    v.noSwaps:SetShown(#found == 0)
    local reach = ahead and "No quest you can take within 2 levels" or "No quest you can take now"
    v.noSwaps:SetText(UI.findMode == "gear" and (reach .. " rewards a piece you can wear" .. (UI.gearSlot and (" (" .. UI.gearSlot .. ")") or "") .. ".")
      or UI.findMode == "trinket" and (reach .. " rewards a trinket, ring or necklace.")
      or (reach .. " rewards a recipe."))
    return
  end
  for _, r in ipairs(v.swaps) do r.reward, r.rewardId = nil, nil end

  -- swaps: advance a chain you hold, fill a free slot, or swap a weak quest for a better one
  local lvl = s.level
  local rows, used = {}, {}
  -- a chain you hold: the best later step you could bank instead (questing, the arrows show chains)
  for _, it in ipairs(entries) do
    if QB:Banking() and it.q and it.q.nextSteps and not it.cut then
      local best, bestV, bestDepth
      local function walk(q, depth)
        if depth > 3 or not q.nextSteps then return end
        for _, nid in ipairs(q.nextSteps) do
          local nq = Q.Get(nid)
          if nq and Q.ForMe(nq) and not QB.API.IsDone(nid) and not s.log[nid] and (nq.req or 1) <= lvl
            and not nq.sodLeftover and not nq.repeatable and not QB.Quest.Behind(nq.id) and not QB:SkipsQuest(nq) then
            local v = QB.Model.XpAt(nq, lvl)
            -- a step handed in inside a dungeon can't be banked; the one after it can
            if not (nq.turn and nq.turn.inside) and (not bestV or v > bestV) then best, bestV, bestDepth = nq, v, depth end
            walk(nq, depth + 1)
          end
        end
      end
      walk(it.q, 1)
      if best and bestV > (it.value or 0) + 300 * QB.Scale(lvl) then
        rows[#rows + 1] = { add = { q = best, value = bestV }, cut = it, cutValue = it.value or 0, gain = bestV - (it.value or 0),
                            chain = bestDepth }
        used[best.id] = true
      end
    end
  end
  local cuts = {}
  for _, it in ipairs(entries) do
    if it.cut or not it.q or (it.value or 0) < 1500 * QB.Scale(lvl) then cuts[#cuts + 1] = it end
  end
  table.sort(cuts, function(a, b)
    if (a.cut or false) ~= (b.cut or false) then return a.cut end
    return (a.value or 0) < (b.value or 0)
  end)
  -- the Highest XP finder is sorted by XP alone. The candidates come ranked for the time (questing, nearby first), so
  -- the richest are taken from the whole list, sixty at most; the trip shows on each line instead
  local adds = {}
  local cands = {}
  for i, c in ipairs(self:Candidates(nil)) do cands[i] = c end
  table.sort(cands, function(a, b) if a.value ~= b.value then return a.value > b.value end return a.id < b.id end)
  for _, c in ipairs(cands) do
    if #adds >= 60 then break end
    if c.waste or c.behind then c = nil end -- questing: a long run for little is no suggestion
    if c then
    local q = Q.Get(c.id)
    local st = q and QB:Status(q)
    -- quests you can pick up now and that need a log slot, and the ones a single step handed in inside
    -- the dungeon stands before (Blackfathom Villainy after In Search of Thaelrid): take that step, finish
    -- it in there, bank what it gives you. Longer chains and bag quests live on the Plan page.
    local via
    if q and st.code == "prereq" and type(st.pre) == "number" then
      local p = Q.Get(st.pre)
      if p and p.turn and p.turn.inside and QB:Status(p).code == "todo" then via = p end
    end
    local chain
    if q and st.code == "prereq" and not via then chain = QB:ChainCost(q) end
    if q and not used[q.id] and not QB:IsAdded(q.id) and (st.code == "todo" or via or chain) and not (q.bag and q.bag[3] == 1) then
      adds[#adds + 1] = { q = q, value = QB.Model.XpAt(q, lvl), st = st, via = via, chain = chain, lead = c.lead, mins = c.mins }
    end
    end
  end
  table.sort(adds, function(a, b) if a.value ~= b.value then return a.value > b.value end return a.q.id < b.q.id end)
  local ai = 1
  for _ = 1, QB.LOG_SLOTS - #entries do
    if adds[ai] then rows[#rows + 1] = { add = adds[ai], cutValue = 0, gain = adds[ai].value }; ai = ai + 1 end
  end
  for _, c in ipairs(cuts) do
    local a = adds[ai]
    if not a then break end
    local cv = c.cut and 0 or (c.value or 0)
    if a.value > cv + 300 * QB.Scale(lvl) then
      rows[#rows + 1] = { cut = c, add = a, cutValue = cv, gain = a.value - cv }
      ai = ai + 1
    end
  end
  -- the biggest gain first, banking or questing: Highest XP is sorted by XP, and the trip on the line says how far
  table.sort(rows, function(a, b) if a.gain ~= b.gain then return a.gain > b.gain end return a.add.q.id < b.add.q.id end)
  for i, r in ipairs(v.swaps) do
    local d = rows[i]
    if d then
      r:Show()
      r.add, r.addValue, r.via = d.add.q, d.add.value, d.add.via
      r.cutTitle = d.cut and d.cut.e.title or nil
      r.cutValue = d.cutValue
      if d.chain then
        r.cutName:SetText("hand in " .. d.cut.e.title .. " now, " .. (d.chain > 1 and string.format("%d steps on", d.chain) or "bank the next step"))
      else
        -- the line under the name: what it replaces, then what it costs or leads to, as far as the room allows
        local base = d.cut and ("instead of " .. d.cut.e.title .. (d.cutValue > 0 and ("  " .. QB.Short(d.cutValue)) or "")) or "into a free slot"
        local ch = d.add.chain
        local mins = ch and ch.minutes and ch.minutes > 0 and string.format(", ~%d min", ch.minutes) or ""
        local long = ch and string.format(" · %d step%s first%s", ch.n, ch.n == 1 and "" or "s", mins) or ""
        local short = ch and string.format(" · %d step%s%s", ch.n, ch.n == 1 and "" or "s", mins) or ""
        -- questing: what the quest leads on to is part of why it's here
        local lead = (not QB:Banking() and d.add.lead and d.add.lead > 0 and not ch) and (" · leads to +" .. QB.Short(d.add.lead)) or ""
        local classic = (d.add.q.classic and not d.add.q.liveFull) and " · Classic only" or ""
        -- the trip to its giver (a chain's own minutes cover it)
        local trip = (not ch and d.add.mins) and (" · " .. (d.add.mins < 1 and "here" or string.format("%d min", math.floor(d.add.mins + 0.5)))) or ""
        local room = r.cutName:GetWidth() - 2
        for _, line in ipairs({ base .. trip .. long .. lead .. classic, base .. trip .. short .. classic, base .. trip .. short .. lead, base .. trip .. short,
                                base .. trip .. lead, base .. trip, base }) do
          r.cutName:SetText(line)
          if r.cutName:GetStringWidth() <= room then break end
        end
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
local SELBAR_H = 34 -- the selection's bar under Now and Available
local function makeRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(22)
  -- picked out for Pick up all / Remove all: a gold wash under the row
  r.selBg = tex(r, "BACKGROUND", FLAT)
  r.selBg:SetAllPoints()
  r.selBg:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.12)
  r.selBg:Hide()
  r.hi = tex(r, "HIGHLIGHT", T.rowHi)
  r.hi:SetAllPoints()
  r.hi:SetBlendMode("ADD")

  r.hi:SetAlpha(0.6)
  -- the mark sits on a small button: on a quest you can pick up, a click puts it on your pick-up list
  r.pick = CreateFrame("Button", nil, r)
  r.pick:SetSize(20, 20)
  r.pick:SetPoint("LEFT", 1, 0)
  r.mark = tex(r.pick, "ARTWORK", nil, 14, 14)
  r.mark:SetPoint("CENTER", 0, 0)
  r.pick:SetScript("OnClick", QB.Safe(function(self)
    local row = self:GetParent()
    if self.pickable and row.q then QB:ToggleAdd(row.q.id); UI:Refresh() end
  end, "pick up"))
  tooltip(r.pick, function(tip, self)
    local row = self:GetParent()
    if self.pickable and row.q then
      if QB:IsAdded(row.q.id) then
        tip:AddLine("To pick up", GOLD[1], GOLD[2], GOLD[3])
        tip:AddLine("Click: take it off your pick-up list.", 1, 1, 1, true)
      else
        tip:AddLine("Pick it up", GOLD[1], GOLD[2], GOLD[3])
        tip:AddLine("Click: put it on your pick-up list. It shows in your Quest Log as To pick up, with a ! on its giver on the map.", 1, 1, 1, true)
      end
    elseif row.q then
      UI.QuestTooltip(tip, row.q, row.st, row.value)
    else
      tip:AddLine(row.step and row.step.name or (row.entry and row.entry.title) or "", GOLD[1], GOLD[2], GOLD[3])
    end
  end)
  r.icon = tex(r, "ARTWORK", nil, 18, 18)
  r.icon:SetPoint("LEFT", 22, 0)
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.name = text(r, "GameFontNormal", 12, INK, "LEFT", 270)
  r.name:SetPoint("LEFT", 46, 0)
  -- the box that picks several quests at once (Ctrl-click the row does the same): the game's own check box, on the
  -- quest's icon while the mouse is on the row, and kept there while it is ticked
  r.sel = CreateFrame("Button", nil, r)
  r.sel:SetSize(18, 18)
  r.sel:SetPoint("LEFT", 22, 0)
  r.sel.box = tex(r.sel, "ARTWORK")
  r.sel.box:SetAllPoints()
  QB.Art(r.sel.box, "checkbox-minimal", "Interface\\Buttons\\UI-CheckBox-Up")
  r.sel.check = tex(r.sel, "OVERLAY")
  r.sel.check:SetAllPoints()
  QB.Art(r.sel.check, "checkmark-minimal", "Interface\\Buttons\\UI-CheckBox-Check")
  r.sel:Hide()
  r.sel:SetScript("OnClick", QB.Safe(function(self) UI.Select(self:GetParent()) end, "select"))
  tooltip(r.sel, function(tip, self)
    local row = self:GetParent()
    local on = row.view and row.q and row.view.sel[row.q.id]
    tip:AddLine(on and "Selected" or "Select", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Pick up or remove several quests at once, from the bar below. Ctrl-click a row does the same.", 1, 1, 1, true)
  end)
  r.sel:HookScript("OnLeave", function(self)
    local row = self:GetParent()
    if not (row.IsMouseOver and row:IsMouseOver()) then UI.ShowSelect(row, false) end
  end)
  -- what the quest gives, as the journal shows it: up to three item icons, each with the item's tooltip; Ctrl-click one
  -- and the dressing room puts it on you (any other click is the row's)
  r.rw = {}
  for i = 1, 3 do
    local b = rewardButton(r, 16, r)
    b:SetPoint("LEFT", 318 + (i - 1) * 18, 0)
    b:Hide()
    r.rw[i] = b
  end
  r.up = upgradeMark(r, 10, 11)
  r.up:SetPoint("LEFT", 376, 0)
  r.lvl = text(r, "GameFontNormalSmall", 10, INK_SOFT, "LEFT", 30)
  r.lvl:SetPoint("LEFT", 396, 0)
  r.status = text(r, "GameFontNormalSmall", 11, INK, "LEFT", 250)
  r.status:SetPoint("LEFT", 450, 0)
  r.away = text(r, "GameFontNormalSmall", 11, INK_SOFT, "RIGHT", 40)
  r.away:SetPoint("RIGHT", -72, 0)
  r.xp = text(r, "GameFontNormal", 12, INK, "RIGHT", 60)
  r.xp:SetPoint("RIGHT", -8, 0)
  -- a chain: open it to see every step, done, held, next and later
  r.chain = CreateFrame("Button", nil, r)
  r.chain:SetSize(16, 16)
  r.chain:SetPoint("LEFT", 430, 0)
  r.chain.icon = tex(r.chain, "ARTWORK", nil, 14, 14)
  r.chain.icon:SetPoint("CENTER", 0, 0)
  r.chain:SetScript("OnClick", QB.Safe(function(self)
    local row = self:GetParent()
    if not row.q then return end
    UI.chainOpen = UI.chainOpen or {}
    UI.chainOpen[row.q.id] = not UI.chainOpen[row.q.id] or nil
    UI:Refresh()
  end, "chain"))
  tooltip(r.chain, function(tip, self)
    local row = self:GetParent()
    tip:AddLine("The chain", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine((UI.chainOpen and row.q and UI.chainOpen[row.q.id]) and "Click: fold it away." or "Click: every step of it, done, in your log, next and later, under this row.", 1, 1, 1, true)
  end)
  r.chain:Hide()
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self, which)
    if self.selectable and which ~= "RightButton" and IsControlKeyDown and IsControlKeyDown() then UI.Select(self) return end
    if self.q and self.detailable and which ~= "RightButton" and not (IsShiftKeyDown and IsShiftKeyDown()) then
      UI.detailOpen = UI.detailOpen or {}
      UI.detailOpen[self.q.id] = not UI.detailOpen[self.q.id] or nil
      UI:Refresh()
      return
    end
    if self.q then UI.QuestClick(self.q, self.st, which)
    elseif self.entry then
      local q = Q.Get(self.entry.id)
      if q then UI.QuestClick(q, QB:Status(q), which) end
    elseif self.step and self.step.m then QB.API.SetWaypoint(self.step.m, self.step.x, self.step.y, self.step.name) end
  end)
  tooltip(r, function(tip, self)
    if self.q then
      UI.QuestTooltip(tip, self.q, self.st, self.value)
      if self.together then tip:AddLine("Done in the same spot as: " .. table.concat(self.together, ", ") .. ". Do them together.", 0.75, 0.75, 1, true) end
      if self.selectable then tip:AddLine("Ctrl-click: select it, to pick up or remove several at once.", 0.5, 0.5, 0.5, true) end
    elseif self.entry then
      tip:AddLine(self.entry.title, GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine(self.advice or "", 1, 0.55, 0.45, true)
    elseif self.step then
      tip:AddLine(self.step.name, GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine(self.step.where, 1, 1, 1, true)
      if self.step.m then tip:AddLine("Click: waypoint.", 0.5, 0.5, 0.5) end
    end
  end)
  -- the box shows while the mouse is on the row (leaving the row for its own box or a reward icon keeps it: both sit
  -- on the row, and the icon's own leave takes the box off)
  r:HookScript("OnEnter", function(self) UI.ShowSelect(self, true) end)
  r:HookScript("OnLeave", function(self)
    if not ((self.sel.IsMouseOver and self.sel:IsMouseOver()) or (self.IsMouseOver and self:IsMouseOver())) then UI.ShowSelect(self, false) end
  end)
  return r
end

local makeDetail
local function makeCard(parent)
  local c = CreateFrame("Frame", nil, parent, BD)
  backdrop(c, nil, T.tipBorder, 12, 3)
  if c.SetBackdropBorderColor then c:SetBackdropBorderColor(0.45, 0.33, 0.16, 0.9) end
  c.art = tex(c, "BACKGROUND")
  c.art:SetPoint("TOPLEFT", 3, -3)
  c.art:SetPoint("TOPRIGHT", -3, -3)
  c.art:SetHeight(42)
  c.shade = tex(c, "BORDER")
  c.shade:SetTexture(FLAT)
  -- dark on the left where the name sits, the picture showing through on the right
  if c.shade.SetGradient and CreateColor then
    c.shade:SetGradient("HORIZONTAL", CreateColor(0.03, 0.03, 0.04, 0.92), CreateColor(0.03, 0.03, 0.04, 0.2))
  else
    c.shade:SetVertexColor(0.03, 0.03, 0.04, 0.6)
  end
  c.shade:SetAllPoints(c.art)
  -- the banner opens and closes the place
  c.head = CreateFrame("Button", nil, c)
  c.head:SetPoint("TOPLEFT", 3, -3)
  c.head:SetPoint("TOPRIGHT", -92, -3)
  c.head:SetHeight(42)
  c.head:SetScript("OnClick", QB.Safe(function(self)
    local key = self.key
    if not key then return end
    UI.cardOpen = UI.cardOpen or {}
    UI.cardOpen[key] = not UI.cardOpen[key] or nil
    UI:Refresh()
  end, "open a place"))
  c.caret = tex(c, "OVERLAY", nil, 16, 16)
  c.caret:SetPoint("TOPLEFT", 4, -16)
  c.details = pool(c, function(p) return makeDetail(p) end)
  c.icon = tex(c, "ARTWORK", nil, 32, 32)
  c.icon:SetPoint("TOPLEFT", 22, -8)
  c.title = text(c, "GameFontNormalLarge", 15, GOLD, "LEFT", 380)
  c.title:SetPoint("TOPLEFT", 62, -9)
  c.where = text(c, "GameFontHighlightSmall", 11, WHITE, "LEFT", 420)
  c.where:SetPoint("TOPLEFT", 62, -28)
  c.gain = text(c, "GameFontNormalLarge", 15, GOLD, "RIGHT", 150)
  c.gain:SetPoint("TOPRIGHT", -96, -9)
  c.count = text(c, "GameFontHighlightSmall", 11, WHITE, "RIGHT", 150)
  c.count:SetPoint("TOPRIGHT", -96, -28)
  c.pin = pinButton(c, 22)
  c.pin:SetPoint("TOPRIGHT", -12, -7)
  c.pin:SetScript("OnClick", function(self)
    local e = self.entrance
    if e then QB.API.SetWaypoint(e.m, e.x, e.y, self.label) end
  end)
  tooltip(c.pin, function(tip, self) tip:AddLine("Waypoint: " .. (self.label or ""), GOLD[1], GOLD[2], GOLD[3]) end)
  -- skip this place: nothing here is suggested until you click again (Settings lists the skipped ones)
  c.skip = CreateFrame("Button", nil, c)
  c.skip:SetSize(34, 14)
  c.skip:SetPoint("TOPRIGHT", -8, -31)
  c.skip.label = text(c.skip, "GameFontNormalSmall", 11, WHITE, "RIGHT", 34)
  c.skip.label:SetPoint("RIGHT", 0, 0)
  c.skip:SetScript("OnClick", QB.Safe(function(self)
    if self.key then QB:SetSkip(self.key, not QB:Settings().skipCat[self.key]) end
  end, "plan: skip"))
  tooltip(c.skip, function(tip, self)
    local on = self.key and QB:Settings().skipCat[self.key]
    tip:AddLine(on and "Skipped: nothing here is suggested." or "Skip this place: QuestBank stops suggesting quests here.", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine(on and "Click to bring it back." or "Click again to bring it back; Settings and /qb skip list them.", 0.8, 0.8, 0.8, true)
  end)
  -- every quest the place shows that you could pick up, onto your pick-up list in one click
  c.addAll = CreateFrame("Button", nil, c)
  c.addAll:SetSize(40, 14)
  c.addAll:SetPoint("TOPRIGHT", -48, -31)
  c.addAll.label = text(c.addAll, "GameFontNormalSmall", 11, GOLD, "RIGHT", 40)
  c.addAll.label:SetPoint("RIGHT", 0, 0)
  c.addAll.label:SetText("+ all")
  c.addAll:SetHighlightTexture(T.rowHi, "ADD")
  c.addAll:SetScript("OnClick", QB.Safe(function(self)
    for _, id in ipairs(self.ids or {}) do QB:SetAdded(id, true) end
    UI:Refresh()
  end, "pick up all here"))
  tooltip(c.addAll, function(tip, self)
    local ids = self.ids or {}
    tip:AddLine(string.format("Pick up all %d here", #ids), GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Puts every quest this place shows that you can pick up on your pick-up list:", 1, 1, 1, true)
    for i, id in ipairs(ids) do
      if i > 10 then tip:AddLine(string.format("and %d more", #ids - 10), 0.8, 0.8, 0.8) break end
      local q = Q.Get(id)
      if q then tip:AddLine(q.name, 0.8, 0.8, 0.8) end
    end
  end)
  c.addAll:Hide()
  c.rows = pool(c, makeRow)
  c.more = CreateFrame("Button", nil, c)
  c.more:SetSize(400, 18)
  c.more.label = text(c.more, "GameFontNormalSmall", 11, GOLD_SOFT, "LEFT", 400)
  c.more.label:SetPoint("LEFT", 0, 0)
  c.more:SetScript("OnClick", function(self)
    UI.expanded = UI.expanded or {}
    UI.expanded[self.key] = not UI.expanded[self.key] or nil
    UI:Refresh()
  end)
  return c
end

-- a quest, opened: what it gives, who gives it and takes it, what it asks, and what you can do
local DETAIL_H = 96
makeDetail = function(parent)
  local d = CreateFrame("Frame", nil, parent, BD)
  d:SetHeight(DETAIL_H)
  backdrop(d, FLAT, T.tipBorder, 8, 2)
  if d.SetBackdropColor then d:SetBackdropColor(0.04, 0.05, 0.07, 0.95) end
  if d.SetBackdropBorderColor then d:SetBackdropBorderColor(0.35, 0.28, 0.16, 0.9) end
  d.rwHead = text(d, "GameFontNormalSmall", 10, GOLD_SOFT, "LEFT", 120)
  d.rwHead:SetPoint("TOPLEFT", 10, -8)
  -- its rewards, each with the item's tooltip; Ctrl-click one and the dressing room puts it on you
  d.rw = {}
  for i = 1, 6 do
    local b = rewardButton(d, 26)
    b:SetPoint("TOPLEFT", 10 + (i - 1) * 30, -22)
    d.rw[i] = b
  end
  d.from = text(d, "GameFontHighlightSmall", 11, INK, "LEFT", 300)
  d.from:SetPoint("TOPLEFT", 200, -10)
  d.to = text(d, "GameFontHighlightSmall", 11, INK, "LEFT", 300)
  d.to:SetPoint("TOPLEFT", 200, -28)
  d.obj = text(d, "GameFontHighlightSmall", 11, INK_SOFT, "LEFT", 300)
  d.obj:SetPoint("TOPLEFT", 200, -46)
  local function btn(label, w, x, fn)
    local b = button(d, label, w)
    b:SetPoint("BOTTOMLEFT", x, 8)
    b:SetScript("OnClick", QB.Safe(function() fn(d) end, "quest detail"))
    return b
  end
  d.goGive = btn("Giver", 70, 10, function(self) local n = self.q and self.q.give; if n and not n.inside then QB.API.SetWaypoint(n.m, n.x, n.y, n.n, nil, nil, { qid = self.q.id, what = "give" }) end end)
  d.goTurn = btn("Hand-in", 80, 84, function(self) local n = self.q and self.q.turn; if n and not n.inside then QB.API.SetWaypoint(n.m, n.x, n.y, n.n, nil, nil, { qid = self.q.id, what = "turn" }) end end)
  d.goObj = btn("Objective", 86, 168, function(self) UI.WaypointObjective(self.q) end)
  d.pick = btn("Pick up", 76, 258, function(self) if self.q then QB:ToggleAdd(self.q.id); UI:Refresh() end end)
  d.report = btn("Report", 70, 338, function(self) if self.q then UI.ReportMenu(self.q) end end)
  return d
end

-- the nearest place a quest's objectives are done, as a waypoint
function UI.WaypointObjective(q)
  if not (q and QB.Data.SPOT and QB.QuestMap and QB.QuestMap.Spots) then return end
  local here = QB.API.WorldPosition()
  local best, bd
  for _, sp in ipairs(QB.QuestMap.Spots(QB.Data.SPOT[q.id]) or {}) do
    local w = QB.Model.World(sp.m, sp.x * 100, sp.y * 100)
    local dd = (here and w and here.c == w.c) and ((w.wx - here.wx) ^ 2 + (w.wy - here.wy) ^ 2) or 1e12
    if not bd or dd < bd then best, bd = sp, dd end
  end
  if best then QB.API.SetWaypoint(best.m, best.x * 100, best.y * 100, q.name, nil, nil, { qid = q.id, what = "obj" }) else QB:Print("No objective place known for " .. q.name .. " yet.") end
end

-- a problem with a quest, noted for foreverrank.com: it goes up with your next upload
UI.REPORTS = { "The giver is not where QuestBank says", "The hand-in is somewhere else", "The XP is wrong",
               "The quest does not exist in Forever", "The objectives are somewhere else", "The rewards are wrong" }
function UI.Report(q, reason)
  QuestBankDB.reports = QuestBankDB.reports or {}
  local list = QuestBankDB.reports
  local me = QB.API.WorldPosition()
  list[#list + 1] = { id = q.id, r = reason, at = time and time() or 0, b = QB.Data.BUILD, lvl = QB.state.level,
                      m = QB.Plain(QB.API.MapID()), wx = me and math.floor(me.wx) or nil, wy = me and math.floor(me.wy) or nil }
  while #list > 100 do table.remove(list, 1) end
  QB:Print(string.format("Noted for %s: %s. It goes to foreverrank.com with your next upload.", q.name, reason:lower()))
end
function UI.ReportMenu(q)
  local items = {}
  for _, r in ipairs(UI.REPORTS) do items[#items + 1] = { r, function() UI.Report(q, r) end } end
  UI:ShowMenu("Report: " .. q.name, items)
end

local function fillDetail(d, q, width)
  d.q = q
  d:SetWidth(width)
  local R = QB.Data.RITEMS and QB.Data.RITEMS[q.id]
  local ids, choose = {}, R and R.c and #R.c > 0
  for _, key in ipairs({ "c", "r", "u" }) do for _, id in ipairs(R and R[key] or {}) do ids[#ids + 1] = id end end
  d.rwHead:SetText(#ids == 0 and "Rewards not known yet" or (choose and "Choose one" or "Rewards"))
  for i, b in ipairs(d.rw) do
    local id = ids[i]
    b.id = id
    if id then
      local icon = C_Item and C_Item.GetItemIconByID and select(2, pcall(C_Item.GetItemIconByID, id))
      b.icon:SetTexture(type(icon) == "number" and icon or 134400)
      b:Show()
    else b:Hide() end
  end
  d.from:SetText(q.give and ("|cff9a8a70From|r  " .. q.give.n .. (q.give.place and ("  \194\183  " .. q.give.place) or "")) or "|cff9a8a70From|r  not known yet")
  d.to:SetText(q.turn and ("|cff9a8a70To|r  " .. q.turn.n .. (q.turn.place and ("  \194\183  " .. q.turn.place) or "")) or "|cff9a8a70To|r  not known yet")
  local objs = QB.state.log[q.id] and QB.API.Objectives(q.id) or {}
  local parts = {}
  for i, o in ipairs(objs) do if i <= 3 then parts[#parts + 1] = (o.done and "|cff6cdc74" or "") .. (QB.Plain(o.text) or "") .. (o.done and "|r" or "") end end
  local nspots = (QB.Data.SPOT and QB.QuestMap and #(QB.QuestMap.Spots(QB.Data.SPOT[q.id]) or {})) or 0
  d.obj:SetText(#parts > 0 and table.concat(parts, "  \194\183  ") or (nspots > 0 and string.format("Done at %d place%s on the map", nspots, nspots == 1 and "" or "s") or ""))
  d.goGive:SetEnabled(q.give ~= nil and not q.give.inside)
  d.goTurn:SetEnabled(q.turn ~= nil and not q.turn.inside)
  d.goObj:SetEnabled(nspots > 0)
  d.pick:SetText(QB:IsAdded(q.id) and "Unpick" or "Pick up")
  d.pick:SetShown(not QB.state.log[q.id])
end

-- the marks are the game's own language: a green check for a quest ready to hand in, the waiting disc for
-- one in your log, the yellow ! for one you can pick up (chosen or not), a red X for one you cut
local MARK = { banked = "ready", active = "waiting", partial = "waiting", bagstart = "waiting" }
STATUS.pickup = { 0.25, 0.25, 0.45 }

-- the quest's reward items as icons (D.RITEMS: choose one of c, always r, u unknown), the client's icon when it has
-- one, asked of the server when not
function UI.RewardIcons(r, q)
  if not r.rw then return end
  local R = QB.Data.RITEMS and QB.Data.RITEMS[q.id]
  local ids = {}
  for _, key in ipairs({ "c", "r", "u" }) do for _, id in ipairs(R and R[key] or {}) do ids[#ids + 1] = id end end
  for i = 1, 3 do
    local id = ids[i]
    local icon = id and itemIcon(id)
    local b = r.rw[i]
    b.id = icon and id or nil
    if icon then b.icon:SetTexture(icon); b:Show() else b:Hide() end
  end
end

-- a chain's step sits under its quest's row, its icon and name 12 px further in; rows are pooled, so every fill sets it
local function indent(r, sub)
  local dx = sub and 12 or 0
  r.icon:ClearAllPoints(); r.icon:SetPoint("LEFT", 22 + dx, 0)
  r.sel:ClearAllPoints(); r.sel:SetPoint("LEFT", 22 + dx, 0)
  r.name:ClearAllPoints(); r.name:SetPoint("LEFT", 46 + dx, 0)
  r.name:SetWidth(270 - dx)
end

-- the box on a row: shown while the mouse is on the row or while it is ticked, on rows that can go on the pick-up
-- list (not in your log or bags, not done); a ticked row is washed gold
function UI.ShowSelect(r, hover)
  local on = (r.selectable and r.view and r.q and r.view.sel[r.q.id]) and true or false
  r.sel:SetShown((r.selectable and (hover or on)) and true or false)
  r.sel.check:SetShown(on)
  r.selBg:SetShown(on)
end

-- Ctrl-click or the box: the quest into the page's selection, or out of it
function UI.Select(r)
  local v, q = r.view, r.q
  if not (v and v.sel and q and r.selectable) then return end
  v.sel[q.id] = (not v.sel[q.id]) or nil
  UI:Refresh()
end

-- it = { q, st, value, held, chosen, cut, mins, sub (a step shown under its chain), together (names) }; v: the page
-- whose selection the row joins (Now and Available), nil where rows are not picked
local function fillRow(r, it, width, v)
  local q, st = it.q, it.st
  r.q, r.st, r.entry, r.step, r.value, r.together = q, st, nil, nil, it.value, it.together
  r.detailable = it.detailable or nil
  r:SetWidth(width)
  local held, chosen = it.held, it.chosen
  r.view = v
  r.selectable = (v and v.sel and not held and st.code ~= "done") and true or nil
  UI.ShowSelect(r, r.IsMouseOver and r:IsMouseOver() or false)
  local pickable = not held and st.code ~= "done" and not st.behind and (st.code == "todo" or st.code == "item")
  local mark
  if it.cut then mark = T.notready
  elseif held and MARK[st.code] then mark = T[MARK[st.code]]
  elseif pickable then mark = T.questAvail end
  if mark then r.mark:SetTexture(mark); r.mark:Show() else r.mark:Hide() end
  r.pick.pickable = pickable or nil
  r.pick:EnableMouse(pickable and true or false)
  setIcon(r.icon, q.icon)
  r.icon:SetDesaturated(st.code == "done" or st.code == "locked" or st.behind or false)
  indent(r, it.sub)
  local c = (held or chosen) and INK or INK_SOFT
  r.name:SetTextColor(c[1], c[2], c[3])
  r.up:SetShown(held and not it.cut and QB:Upgrade(q) ~= nil)
  r.lvl:SetText("L" .. q.lvl)
  local mins = (not held and st.code ~= "done" and not st.behind) and it.mins or nil
  local awayText = mins and (mins < 1 and "here" or string.format("%d min", math.floor(mins + 0.5))) or ""
  -- a chain opens under its row; a step shown under one carries no toggle of its own
  local chained = not it.sub and ((q.pre ~= nil) or (q.nextSteps ~= nil and #q.nextSteps > 0))
  if chained then
    caret(r.chain.icon, UI.chainOpen and UI.chainOpen[q.id])
    r.chain:Show()
  else
    r.chain:Hide()
  end
  -- a chain's row says what its steps cost; the minutes to its giver would only crowd that out
  if st.code == "prereq" then awayText = "" end
  -- the minutes column takes room from the status only when it has something to say
  r.status:SetWidth(math.max(100, width - 450 - 76 - (awayText ~= "" and 48 or 0)))
  UI.RewardIcons(r, q)
  -- the name runs on into the reward icons' room when the quest shows none (and the green arrow's when it has none)
  local anyRw = r.rw[1]:IsShown() or r.rw[2]:IsShown() or r.rw[3]:IsShown()
  r.name:SetWidth((anyRw and 314 or (r.up:IsShown() and 372 or 392)) - 46 - (it.sub and 12 or 0))
  r.name:SetText(fitText(r.name, q.name))
  local status, color = st.text, STATUS[st.code] or INK
  local drop = QB.Data.DROP and QB.Data.DROP[q.id]
  if drop and drop < 30 and not held and st.code ~= "done" then
    local pct = math.floor(drop + 0.5)
    if st.code == "item" then
      status = string.format("Item at %d%%: %s", pct, (st.text or ""):gsub("^Starts from an item: ", ""))
    else
      local rest = (st.text and st.text ~= "" and st.code ~= "todo") and (" \194\183 " .. st.text) or ""
      status = string.format("drop %d%%", pct) .. rest
    end
    if drop < 15 then color = BAD end
  end
  if chosen and not st.behind then
    if st.code == "todo" or st.code == "item" then status, color = "To pick up", STATUS.pickup
    else status = "To pick up. " .. st.text end
  end
  -- from the Classic database, not seen in Forever yet: said in the row, not only the tooltip
  if q.classic and not q.liveFull and st.code ~= "done" and st.code ~= "banked" and st.code ~= "active" and st.code ~= "partial" then status = status .. " · Classic only" end
  if st.code == "prereq" then
    local cc = QB:ChainCost(q)
    if cc and cc.minutes and cc.minutes > 0 then
      local room = r.status:GetWidth() - 4
      for _, suffix in ipairs({ string.format(", ~%d min on the move", cc.minutes), string.format(", ~%d min", cc.minutes) }) do
        r.status:SetText(status .. suffix)
        if r.status:GetStringWidth() <= room then status = status .. suffix break end
      end
    end
  end
  if st.code == "todo" and status == st.text then status = "" end
  -- a long item name: the item's own name is what counts, "Item:" says the rest
  if st.code == "item" then
    r.status:SetText(status)
    if r.status:GetStringWidth() > r.status:GetWidth() - 4 then status = status:gsub("^Starts from an item: ", "Item: ") end
  end
  if it.together and #it.together > 0 then
    local room = r.status:GetWidth() - 4
    local suffix = string.format(status ~= "" and " · %d in the same spot" or "%d in the same spot", #it.together)
    r.status:SetText(status .. suffix)
    if r.status:GetStringWidth() <= room then status = status .. suffix end
  end
  -- too long for its column: a chain's step count goes first, then the end of the line, cut at a word
  r.status:SetText(status)
  if r.status:GetStringWidth() > r.status:GetWidth() - 4 then status = status:gsub(" %(%d+ steps%)", "") end
  r.status:SetText(fitText(r.status, status))
  r.status:SetTextColor(color[1], color[2], color[3])
  r.away:SetText(awayText)
  r.xp:SetText(QB.Comma(it.value or Q.Full(q)))
end


function UI:CreatePrepView(parent, now)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()
  v.now = now or false
  v.scroll = scrollArea(v)
  local child = v.scroll.child
  v.intro = text(child, "GameFontNormal", 12, INK_SOFT, "LEFT", 470)
  v.intro:SetPoint("TOPLEFT", 4, -4)
  v.introR = text(child, "GameFontNormal", 12, INK_SOFT, "RIGHT", 200)
  v.introR:SetPoint("TOPLEFT", 486, -4)
  if not now then
    v.sections = pool(child, function(p)
      local h = CreateFrame("Button", nil, p, BD)
      backdrop(h, FLAT, nil, 0, 0)
      if h.SetBackdropColor then h:SetBackdropColor(0.13, 0.11, 0.08, 0.9) end
      h.caret = tex(h, "OVERLAY", nil, 16, 16)
      h.caret:SetPoint("LEFT", 8, 0)
      h.label = text(h, "GameFontNormalLarge", 14, GOLD, "LEFT", 200)
      h.label:SetPoint("LEFT", 30, 0)
      h.sum = text(h, "GameFontNormalSmall", 11, INK_SOFT, "RIGHT", 360)
      h.sum:SetPoint("RIGHT", -12, 0)
      h:SetScript("OnClick", QB.Safe(function(self)
        UI.secClosed = UI.secClosed or {}
        UI.secClosed[self.key] = not UI.secClosed[self.key] or nil
        UI:Refresh()
      end, "fold a section"))
      return h
    end)
  end
  if false then
    -- (the chips gave way to the sections)
    v.chips = {}
    local CHIPS = { { nil, "All" }, { "dungeon", "Dungeons" }, { "chain", "Chains" }, { "gear", "Gear" }, { "near", "Near me" } }
    local x = 4
    for i, ch in ipairs(CHIPS) do
      local b = CreateFrame("Button", nil, child, BD)
      local w = 20 + #ch[2] * 7
      b:SetSize(w, 20)
      b:SetPoint("TOPLEFT", x, -24)
      backdrop(b, FLAT, T.tipBorder, 8, 2)
      b.label = text(b, "GameFontNormalSmall", 11, INK, "CENTER", w - 8)
      b.label:SetPoint("CENTER")
      b.label:SetText(ch[2])
      b.key = ch[1]
      b:SetScript("OnClick", function(self) UI.availFilter = self.key; UI:Refresh() end)
      v.chips[i] = b
      x = x + w + 6
    end
  end
  v.cards = pool(child, makeCard)
  -- several quests at once: Ctrl-click rows (or tick their box), then pick them all up or take them all off
  v.sel = {}
  local bar = CreateFrame("Frame", nil, v, BD)
  bar:SetPoint("BOTTOMLEFT", 10, 10)
  bar:SetPoint("BOTTOMRIGHT", -10, 10)
  bar:SetHeight(SELBAR_H)
  bar:EnableMouse(true)
  backdrop(bar, FLAT, T.tipBorder, 12, 3)
  if bar.SetBackdropColor then bar:SetBackdropColor(0.12, 0.09, 0.05, 0.97) end
  if bar.SetBackdropBorderColor then bar:SetBackdropBorderColor(GOLD_SOFT[1], GOLD_SOFT[2], GOLD_SOFT[3], 0.9) end
  bar.count = text(bar, "GameFontNormal", 13, GOLD, "LEFT", 300)
  bar.count:SetPoint("LEFT", 14, 0)
  local function act(label, w, fn, tipTitle, tipText)
    local b = button(bar, label, w)
    b:SetScript("OnClick", QB.Safe(function() fn(); UI:Refresh() end, "selection"))
    tooltip(b, function(tip) tip:AddLine(tipTitle, GOLD[1], GOLD[2], GOLD[3]); tip:AddLine(tipText, 1, 1, 1, true) end)
    return b
  end
  bar.clear = act("Clear", 70, function() v.sel = {} end, "Clear", "Untick them all.")
  bar.clear:SetPoint("RIGHT", -10, 0)
  bar.remove = act("Remove all", 100, function()
    for id in pairs(v.sel) do QB:SetAdded(id, false) end
    v.sel = {}
  end, "Remove all", "Takes the selected quests that are on your pick-up list off it.")
  bar.remove:SetPoint("RIGHT", bar.clear, "LEFT", -6, 0)
  bar.pick = act("Pick up all", 100, function()
    for id in pairs(v.sel) do QB:SetAdded(id, true) end
    v.sel = {}
  end, "Pick up all", "Puts the selected quests on your pick-up list: they show in your Quest Log as To pick up, with a ! on their givers on the map.")
  bar.pick:SetPoint("RIGHT", bar.remove, "LEFT", -6, 0)
  bar:Hide()
  v.selBar = bar
  v.foot = text(child, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", 660)
  v.foot:Hide()
  v.empty = para(child, "GameFontNormal", 13, INK_SOFT, 560)
  v.empty:SetPoint("TOPLEFT", 60, -40)
  v.empty:SetHeight(40)
  v.empty:Hide()
  v.Refresh = function() UI:RefreshPrepView(v) end
  return v
end

local PER_CARD = 8
-- every quest for you by place: what you hold, what you chose to pick up, what you could pick up now, what
-- comes later, and what a later step says you have already done
function UI:RefreshPrepView(v)
  local D = QB.Data
  local s = QB.state
  local level = s.level
  local fac = QB.faction
  local banking = QB:Banking()
  local M = QB.Model
  local width = v.scroll:Width() - 6
  v.cards:Reset()
  -- the selection keeps what can still go on the list: a quest taken or done since drops out of it
  local selN, selOn = 0, 0
  for id in pairs(v.sel) do
    local q = Q.Get(id)
    local st = q and QB:Status(q)
    if not q or s.log[id] or st.code == "done" or st.bag then v.sel[id] = nil
    else
      selN = selN + 1
      if QB:IsAdded(id) then selOn = selOn + 1 end
    end
  end
  v.selBar:SetShown(selN > 0)
  v.scroll:SetBottom(selN > 0 and (10 + SELBAR_H + 4) or 6)
  v.selBar.count:SetText(string.format("%d selected", selN))
  v.selBar.pick:SetEnabled(selN > selOn)
  v.selBar.remove:SetEnabled(selOn > 0)

  local order, groups, here, mf, hubName = UI.PlaceGroups(level, v.now)

  -- the intro: the window and where the minutes count from
  local above, below = QB:Range()
  local picksAll, openAll = 0, 0
  for _, g in ipairs(order) do picksAll, openAll = picksAll + g.picks, openAll + g.open end
  local order_word = banking and "richest place first" or "zone by zone from the lowest"
  if v.now then
    v.intro:SetText(hubName and string.format("Where next, from %s: the three places worth your time.", hubName) or "Where next: the three places worth your time.")
    v.introR:SetText(string.format("%d available", openAll))
  else
    v.intro:SetText(string.format("Level %d to %d", math.max(1, level - below), math.min(QB.MAXLEVEL or 60, level + above)))
    v.introR:SetText(string.format("%d available" .. (picksAll > 0 and " · %d to pick up" or ""), openAll, picksAll))
  end

  local y = 24
  local filter = (not v.now) and UI.availFilter or nil
  for _, b in ipairs(v.chips or {}) do
    local on = b.key == filter
    if b.SetBackdropColor then b:SetBackdropColor(on and 0.6 or 0.12, on and 0.45 or 0.14, on and 0.15 or 0.19, 0.95) end
    b.label:SetTextColor(on and 1 or INK[1], on and 0.95 or INK[2], on and 0.7 or INK[3])
  end
  local R = QB.Data.REWARD or {}
  local function rowPasses(it)
    if filter == "chain" then return it.q.pre ~= nil or (it.q.nextSteps ~= nil and #it.q.nextSteps > 0) end
    if filter == "gear" then local r = R[it.q.id]; return r ~= nil and (r[1] or 0) > 0 end
    return true
  end
  local function groupPasses(g)
    if filter == "dungeon" and not g.cat.dungeon then return false end
    if filter == "near" and not (g.nearest and g.nearest <= 12) then return false end
    if filter == "chain" or filter == "gear" then
      for _, it in ipairs(g.quests) do if it.grp ~= 6 and rowPasses(it) then return true end end
      return false
    end
    return true
  end
  local function place(card, h)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", v.scroll.child, "TOPLEFT", 0, -y)
    card:SetSize(width, h)
    y = y + h + 8
  end
  local artH = v.now and 78 or 54
  local function header(c, art, icon, title, where, gain, count)
    c.rows:Reset()
    c.art:SetHeight(artH)
    if type(art) == "table" then c.art:SetColorTexture(art[1], art[2], art[3], 1); c.art:SetTexCoord(0, 1, 0, 1)
    elseif c.art.__img then c.art:SetTexture(art); local band = math.min(0.9, artH / math.max(1, width) * 2); c.art:SetTexCoord(0, 1, 0.5 - band / 2, 0.5 + band / 2)
    elseif c.art.__tile then c.art:SetTexture(art); c.art:SetTexCoord(0, 1, 0.25, v.now and 0.75 or 0.5)
    else c.art:SetTexture(art); c.art:SetTexCoord(0, 1, 0.18, v.now and 0.7 or 0.5) end
    c.icon:SetTexture(icon)
    c.title:SetText(title)
    c.where:SetText(where)
    c.gain:SetText(gain)
    c.gain:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    c.count:SetText(count or "")
    c.pin:Hide()
    c.more:Hide()
    c.skip:Hide()
    c.skip.key = nil
    c.addAll:Hide()
    c.addAll.ids = nil
    c:SetAlpha(1)
  end
  -- the card's count line, as much of it as fits: available, to pick up, in your log (ready), not yet, done
  local function countLine(c, g)
    local parts = {}
    if g.open > 0 then parts[#parts + 1] = g.open .. " available" end
    if g.picks > 0 then parts[#parts + 1] = g.picks .. " to pick up" end
    if g.held > 0 then
      parts[#parts + 1] = g.held .. " in your log" .. (g.ready > 0 and string.format(" (%d %s)", g.ready, banking and "banked" or "ready") or "")
    end
    if g.notyet > 0 then parts[#parts + 1] = g.notyet .. " not yet" end
    if g.done > 0 then parts[#parts + 1] = g.done .. " done" end
    if #parts == 0 then return g.behind > 0 and "probably behind you" or "" end
    local room = c.count:GetWidth() - 2
    for n = #parts, 1, -1 do
      local line = table.concat(parts, " · ", 1, n)
      c.count:SetText(line)
      if c.count:GetStringWidth() <= room or n == 1 then return line end
    end
    return parts[1]
  end

  local shownCards = 0
  UI.cardOpen = UI.cardOpen or {}
  UI.detailOpen = UI.detailOpen or {}
  UI.secClosed = UI.secClosed or {}
  -- one place: its banner (the zone's painted picture, its icon, its XP), and when open its quests, each of which
  -- opens on a click to what it gives and where
  local function drawGroup(g, openByDefault)
    local c = v.cards:Get()
    shownCards = shownCards + 1
    local a = g.cat
    local worth = math.floor((g.left + g.fetch) / 10 + 0.5) * 10
    local minsText = ""
    if g.nearest then
      minsText = g.nearest < 1 and " \194\183 you're here" or string.format(a.dungeon and " \194\183 %d min to the entrance" or " \194\183 %d min away", math.floor(g.nearest + 0.5))
    end
    local lv = g.lvlN > 0 and string.format("L%d", math.floor(g.lvlSum / g.lvlN + 0.5)) or ""
    local zone = a.dungeon and (a.where ~= "" and a.where or "Dungeon") or (a.where or "")
    -- (a place with no zone of its own, the class quests: no empty part between two dots)
    local where = zone ~= "" and (zone .. minsText) or minsText:gsub("^ \194\183 ", "")
    if lv ~= "" then where = lv .. (where ~= "" and ("  \194\183  " .. where) or "") end
    local pic = a.img or a.bg or a.art
    c.art.__tile = (not a.img and not a.bg and a.art) and true or false
    c.art.__img = a.img and true or false
    header(c, pic or { 0.16, 0.12, 0.08 }, a.zi or a.icon, a.name, where,
      worth > 0 and ("+" .. QB.Comma(worth)) or (g.held > 0 and (banking and "All banked" or "All ready") or ""), "")
    c.count:SetText(countLine(c, g))
    if g.held > 0 and g.left == 0 and g.fetch == 0 and g.picks == 0 then c.gain:SetTextColor(0.4, 0.9, 0.4) end
    if a.key ~= "class" and a.key ~= "misc" then
      local set = QB:Settings()
      local viaCat = set.skipCat[a.key] == true
      local viaCont = a.cont ~= nil and set.skipCont[a.cont] == true
      c.skip.key = a.key
      c.skip.label:SetText(viaCat and "Back" or "Skip")
      c.skip:SetShown(viaCat or not viaCont)
      if viaCat or viaCont then c.gain:SetText("Skipped"); c.gain:SetTextColor(0.75, 0.75, 0.75); c:SetAlpha(0.8) end
      if viaCont and not viaCat then c.where:SetText((a.dungeon and a.where ~= "" and (a.where .. ". ") or "") .. QB.CONTINENTS[a.cont] .. " is skipped in Settings.") end
    end
    c.pin:SetShown(a.entrance and true or false)
    c.pin.entrance, c.pin.label = a.entrance, a.name .. " entrance"
    local isOpen
    if UI.cardOpen[a.key] ~= nil then isOpen = UI.cardOpen[a.key] else isOpen = openByDefault or UI.allOpen or false end
    c.head.key = a.key
    c.head:SetHeight(artH)
    caret(c.caret, isOpen)
    c.caret:Show()
    c.details:Reset()
    table.sort(g.quests, function(x, z)
      if x.grp ~= z.grp then return x.grp < z.grp end
      if x.grp == 3 and (x.st.code == "banked") ~= (z.st.code == "banked") then return x.st.code == "banked" end
      return x.value > z.value
    end)
    UI.Together(g.quests)
    c.band = g.band
    local ry = artH + 8
    local extra, hidden = 0, 0
    local open = UI.expanded and UI.expanded[a.key]
    -- + all: what the place shows (open, or when it opens) that you could pick up now
    local addable, shownN = {}, 0
    for _, it in ipairs(g.quests) do
      if it.grp ~= 6 and it.grp ~= 1 and it.grp ~= 3 and rowPasses(it) and (open or shownN < (v.now and 4 or PER_CARD)) then
        shownN = shownN + 1
        if it.grp == 2 then addable[#addable + 1] = it.q.id end
      end
    end
    c.addAll.ids = addable
    c.addAll:SetShown(#addable > 0)
    c.addAll:ClearAllPoints()
    c.addAll:SetPoint("TOPRIGHT", c.skip:IsShown() and -48 or -8, -31) -- (Skip's place where the place has no Skip)
    if isOpen then
      for _, it in ipairs(g.quests) do
        local show = false
        if it.grp == 6 or not rowPasses(it) then show = false
        elseif it.grp == 1 or it.grp == 3 then show = true
        else
          show = open or extra < (v.now and 4 or PER_CARD)
          if show then extra = extra + 1 else hidden = hidden + 1 end
        end
        if show then
          local r = c.rows:Get()
          r:ClearAllPoints()
          r:SetPoint("TOPLEFT", 4, -ry)
          it.detailable = true
          fillRow(r, it, width - 8, v)
          ry = ry + 22
          if UI.detailOpen[it.q.id] then
            local d = c.details:Get()
            d:ClearAllPoints()
            d:SetPoint("TOPLEFT", 20, -ry)
            fillDetail(d, it.q, width - 36)
            ry = ry + DETAIL_H + 4
          end
          if UI.chainOpen and UI.chainOpen[it.q.id] then
            for _, sit in ipairs(UI.ChainLine(it.q, here, mf)) do
              local r2 = c.rows:Get()
              r2:ClearAllPoints()
              r2:SetPoint("TOPLEFT", 4, -ry)
              fillRow(r2, sit, width - 8, v)
              ry = ry + 22
            end
          end
        end
      end
      if (hidden > 0 or open) and not v.now then
        c.more:ClearAllPoints()
        c.more:SetPoint("TOPLEFT", 46, -ry - 2)
        c.more.key = a.key
        c.more.label:SetText(open and "Show fewer" or string.format("Show %d more here", hidden))
        c.more:Show()
        ry = ry + 20
      end
    else
      ry = artH + 2
    end
    c.details:HideRest()
    c.rows:HideRest()
    place(c, ry + 4)
  end

  if v.now then
    -- now: the three places worth your time, open
    for _, g in ipairs(order) do if shownCards < 3 and groupPasses(g) then drawGroup(g, true) end end
  else
    -- available: zones, then dungeons, each a section that folds; a place opens when you click its banner
    v.sections:Reset()
    local SECTIONS = { { key = "zones", name = "Zones", test = function(g) return not g.cat.dungeon end },
                       { key = "dungeons", name = "Dungeons", test = function(g) return g.cat.dungeon end } }
    for _, sec in ipairs(SECTIONS) do
      local list, xp, quests = {}, 0, 0
      local fetchOnly = 0
      for _, g in ipairs(order) do
        if sec.test(g) then
          local mine = g.held + g.picks > 0
          if not mine then fetchOnly = fetchOnly + 1 end
          if mine or fetchOnly <= 30 then
            list[#list + 1] = g
            xp = xp + g.left + g.fetch
            quests = quests + g.open + g.held + g.picks
          end
        end
      end
      if #list > 0 then
        local h = v.sections:Get()
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", v.scroll.child, "TOPLEFT", 0, -y)
        h:SetSize(width, 26)
        h.key = sec.key
        local closed = UI.secClosed[sec.key]
        caret(h.caret, not closed)
        h.label:SetText(sec.name)
        h.sum:SetText(string.format("%d places  \194\183  %d quests  \194\183  +%s XP", #list, quests, QB.Short(xp)))
        y = y + 30
        if not closed then for _, g in ipairs(list) do drawGroup(g, false) end end
      end
    end
    v.sections:HideRest()
  end
  -- the sleeping bag chain, last, while you don't have the bag (not under a filter, not on Now). 5.4.4: from its first
  -- step, "... and that note you found" (one quest a side, at your side's place: Camp.SleepSteps); before, it started at
  -- Stepping Stones and its line described the Legacy perk, not the bag
  if QB.API.ItemCount(211527) == 0 and not filter and not v.now then
    local c = v.cards:Get()
    shownCards = shownCards + 1
    local chain = QB.Camp.SleepSteps()
    local nextStep, heldStep, doneSteps, steps = QB.Camp.SleepNext()
    header(c, { 0.10, 0.12, 0.22 }, T.sleep, "Cozy Sleeping Bag", "From level 14. A minute in the bag: +1% XP, up to 3%.", "Bag",
      string.format("%d of %d steps done", doneSteps, steps))
    c.head.key = nil
    c.caret:Hide()
    c.details:Reset(); c.details:HideRest()
    local hq = heldStep and QB.Quest.Get((s.log[nextStep.id] or not nextStep.alt) and nextStep.id or nextStep.alt)
    if hq and hq.turn and hq.turn.m and hq.turn.m > 0 and not hq.turn.inside then
      c.pin:SetShown(true)
      c.pin.entrance = { m = hq.turn.m, x = hq.turn.x, y = hq.turn.y }; c.pin.label = hq.turn.n
    else
      c.pin:SetShown(nextStep and nextStep.m and true or false)
      if nextStep then c.pin.entrance = nextStep.m and { m = nextStep.m, x = nextStep.x, y = nextStep.y } or nil; c.pin.label = nextStep.where end
    end
    local ry = 50
    for _, step in ipairs(chain) do
      local r = c.rows:Get()
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 4, -ry)
      r:SetWidth(width - 8)
      r.q, r.st, r.entry = nil, nil, nil
      r.step = step
      local done, held = QB.Camp.StepDone(step), QB.Camp.StepHeld(step, s.log)
      r.mark:SetTexture(done and T.ready or (held and T.waiting or T.questAvail))
      r.mark:Show()
      r.pick.pickable = nil
      r.pick:EnableMouse(false)
      r.chain:Hide()
      r.together = nil
      r.view, r.selectable = nil, nil
      UI.ShowSelect(r, false)
      indent(r, false)
      for _, t in ipairs(r.rw) do t:Hide() end -- (a pooled row keeps the last quest's reward icons otherwise)
      setIcon(r.icon, T.map)
      r.icon:SetDesaturated(done)
      r.name:SetText(step.name)
      r.name:SetTextColor(INK[1], INK[2], INK[3])
      r.up:Hide()
      r.lvl:SetText("")
      r.status:SetWidth(math.max(120, width - 392 - 76)) -- no minutes column on these rows: the whole width for where the step is
      local where = step.where or ""
      r.status:SetText(where)
      if r.status:GetStringWidth() > r.status:GetWidth() - 4 then where = (where:gsub(",[^,]*$", "")) end -- without the zone when it is tight
      r.status:SetText(done and "Done" or (held and "In your log" or where))
      local sc = done and GOOD or INK_SOFT
      r.status:SetTextColor(sc[1], sc[2], sc[3])
      r.away:SetText("")
      r.xp:SetText("")
      ry = ry + 22
    end
    c.rows:HideRest()
    place(c, ry + 8)
  end
  v.cards:HideRest()

  -- the footer: what you skip
  local skipped = QB:SkipList()
  if #skipped > 0 then
    local names
    if #skipped <= 3 then
      names = #skipped == 1 and skipped[1] or (table.concat(skipped, ", ", 1, #skipped - 1) .. " and " .. skipped[#skipped])
    else
      names = table.concat(skipped, ", ", 1, 3) .. string.format(" and %d more", #skipped - 3)
    end
    v.foot:ClearAllPoints()
    v.foot:SetPoint("TOPLEFT", v.scroll.child, "TOPLEFT", 4, -y)
    v.foot:SetText(string.format("Skipping %s: nothing there is suggested. Settings or /qb skip brings them back.", names))
    v.foot:Show()
    y = y + 20
  else
    v.foot:Hide()
  end
  -- nothing at all
  if shownCards == 0 then
    local set = QB:Settings()
    v.empty:SetText((set.skipCont[0] and set.skipCont[1]) and "You skip Kalimdor and Eastern Kingdoms, so nothing is suggested. Settings brings them back."
      or string.format("Nothing for you between level %d and %d. Settings widens the levels; /qb skip lists the places you skip.", level - below, level + above))
    v.empty:Show()
    y = math.max(y, 90)
  else
    v.empty:Hide()
  end
  v.scroll:SetContentHeight(y)
end

----------------------------------------------------------------------------
-- page 3: hand-in route
----------------------------------------------------------------------------
local KIND = {
  start = "Start here", hearth = "Hearthstone", flight = "Flight", foot = "On foot", tram = "Deeprun Tram", boat = "Boat",
  zeppelin = "Zeppelin", portal = "Portal", done = "Handed in", none = "No known way there",
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
  l.pin = pinButton(l, 20)
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

  r.hi:SetAlpha(0.6)
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
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self, which) if self.q then UI.QuestClick(self.q, self.st, which) end end)
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
  v.modePlan = button(v, "Log and pick-ups", 130)
  v.modePlan:SetPoint("TOPLEFT", 128, -10)
  -- (questing and banking each keep their own choice, Target.lua's T.Mode; the route on screen changes with it, so the
  -- map's pins, the minimap and the arrow follow at once)
  local function setMode(m)
    local set = QB:Settings()
    if QB:Banking() then set.routeMode = m else set.routeQuest = m end
    QB:MarkDirty()
    UI:Refresh()
  end
  v.modeNow:SetScript("OnClick", function() setMode("now") end)
  v.modePlan:SetScript("OnClick", function() setMode("plan") end)
  v.run = button(v, "Start run", 96)
  v.run:SetPoint("TOPRIGHT", -14, -10)
  v.run:SetScript("OnClick", QB.Safe(function()
    if QB.Run.Get() then QB.Run.Stop() else QB:Recompute(true); QB.Run.Start() end
    UI:Refresh()
  end, "run button"))
  tooltip(v.run, function(tip)
    if QB.Run.Get() then
      tip:AddLine("End the run", GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine("Saves it with its times and XP.", 1, 1, 1)
    else
      tip:AddLine("Start the hand-in run", GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine("Starts a clock, ticks each quest off with the XP it paid, and re-plans the rest from where you stand.", 1, 1, 1, true)
      if QB:Banking() then tip:AddLine("When the level cap goes up, your first hand-in starts it by itself.", 1, 1, 1, true) end
    end
  end)
  v.post = button(v, "Post", 64)
  v.post:SetPoint("TOPRIGHT", -114, -10)
  v.post:SetScript("OnClick", function() UI:PostDialog(QB.Run.PostText("status")) end)
  tooltip(v.post, function(tip)
    tip:AddLine("Post in party or guild chat", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine(QB.Run.Get() and "How your hand-in run is going: minutes, level, quests and XP."
      or (QB:Banking() and "The level your banked quests take you to, and your plan's." or "The level the quests ready in your log take you to, and your plan's."), 1, 1, 1, true)
    tip:AddLine("You see the message first. Nothing is posted until you press Post.", 0.6, 0.6, 0.6, true)
  end)
  v.summary = text(v, "GameFontNormal", 12, INK, "RIGHT", 336)
  v.summary:SetPoint("TOPRIGHT", -184, -14)
  v.setup = para(v, "GameFontNormal", 12, INK, (W - SIDE - 22) - 48)
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
  elseif kind == "portal" then return T.portal elseif kind == "start" then return T.book elseif kind == "done" then return T.ready
  elseif kind == "none" then return T.unknown end
  return QB:Mounted() and T.mount or T.foot
end

-- one leg: the clock, how you get there, the stop, and the quests handed in there
-- the Route page's blocks after the legs: what the route could not place, and what waits on a dungeon run (one table,
-- read each refresh; icon: D.TEX's key)
local SIDE_BLOCKS = {
  { key = "unplaced", travel = "Not on the route", icon = "unknown",
    note = "Handed in inside a dungeon, or where QuestBank has no position for the NPC. Hand them in on the way." },
  { key = "waiting", travel = "After a dungeon run", icon = "questGeneric",
    note = "Done inside first; the plan counts nothing for these until they are." },
}

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

-- where to do the quests in your log that are not finished, nearest first from where you stand: each stop is the
-- nearest place one of them is done, with every other quest done within 150 yards of it; at most five stops.
-- { { sp, name, yards, mins, quests = { q, ... } }, ... }
function UI.ObjectiveLegs(maxLegs)
  local D = QB.Data
  local QM = QB.QuestMap
  local here = QB.API.WorldPosition()
  if not (here and D.SPOT and QM and QM.Spots) then return {} end
  local pending = {}
  for _, e in ipairs(QB.state.logOrder or {}) do
    if not e.complete then
      local q = Q.Get(e.id)
      local pts = {}
      for _, sp in ipairs(QM.Spots(D.SPOT[e.id]) or {}) do
        local w = QB.Model.World(sp.m, sp.x * 100, sp.y * 100)
        if w and w.c == here.c then pts[#pts + 1] = { sp = sp, w = w } end
      end
      if q and #pts > 0 then pending[#pending + 1] = { q = q, pts = pts } end
    end
  end
  local legs, pos = {}, here
  local M = QB.Model
  local perYard = M.DETOUR / M.RUN / 60 * M.Factor(QB:Mounted()) -- minutes a yard, at your pace
  local function dist(a, b) return math.sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2) end
  while #pending > 0 and #legs < (maxLegs or 5) do
    local bestI, bestP, bestD
    for i, it in ipairs(pending) do
      for _, p in ipairs(it.pts) do
        local d = dist(pos, p.w)
        if not bestD or d < bestD then bestI, bestP, bestD = i, p, d end
      end
    end
    local leg = { sp = bestP.sp, w = bestP.w, yards = bestD, mins = bestD * perYard, quests = { pending[bestI].q } }
    local name = bestP.sp.name and D.SN and D.SN[bestP.sp.name]
    leg.name = name or pending[bestI].q.name
    table.remove(pending, bestI)
    for i = #pending, 1, -1 do
      for _, p in ipairs(pending[i].pts) do
        if dist(bestP.w, p.w) <= 150 then table.insert(leg.quests, pending[i].q); table.remove(pending, i); break end
      end
    end
    legs[#legs + 1] = leg
    pos = bestP.w
  end
  return legs
end

function UI:RefreshRouteView(v)
  local set = QB:Settings()
  local run = QB.Run.Get()
  local mode = QB.Target.Mode()
  -- the route on screen (Target.lua's T.Route): with Ready now (Banked now) chosen and nothing ready, the plan, which
  -- the arrow, the minimap and the pins follow, said so in the setup line (5.4.4 as first built showed an empty list)
  local r = QB.Target.Route() or (mode == "plan" and QB.routePlan or QB.routeNow)
  local fallback = mode == "now" and r ~= QB.routeNow
  v.modeNow:SetEnabled(mode ~= "now")
  v.modePlan:SetEnabled(mode ~= "plan" and not run)
  local banking = QB:Banking()
  v.modeNow:SetText(banking and "Banked now" or "Ready now")
  v.run:SetText(run and "End run" or "Start run")
  local width = v.scroll:Width() - 6
  local busy = QB.Model.Busy() and "  |cffc9a24aplanning...|r" or ""
  if banking then
    v.summary:SetText(string.format("%s XP  |  level %.2f  |  %d min  |  at 60 min %.2f%s",
      QB.Comma(r.xp or 0), r.level or 0, math.floor((r.t or 0) + 0.5), r.at60 or 0, busy))
  else
    v.summary:SetText(string.format("%s XP  |  level %.2f  |  %d min%s", QB.Comma(r.xp or 0), r.level or 0, math.floor((r.t or 0) + 0.5), busy))
  end
  v.legs:Reset()

  -- the setup line: where to log out and where to bind, or how the run is going
  local line
  if run then
    local got, n = QB.Run.Totals()
    local pace = QB.Run.Pace()
    line = string.format("Run %s.  %d handed in, |cff6cdc74+%s XP|r.", QB.Clock(QB.Run.Elapsed()), n, QB.Comma(got))
    if pace then
      if math.abs(pace) < 1 then line = line .. "  On pace."
      elseif pace > 0 then line = line .. string.format("  %.0f min ahead of the plan.", pace)
      else line = line .. string.format("  |cffe05a4a%.0f min behind the plan.|r", -pace) end
    end
    if r.legs[1] then line = line .. "  Next: |cffe8c35a" .. r.legs[1].stop.name .. "|r." end
  elseif not banking then
    line = r.legs and r.legs[1] and ("From where you stand. First stop: |cffe8c35a" .. r.legs[1].stop.name .. "|r.")
      or (mode == "now" and "Nothing in your log is ready to hand in yet." or "Nothing on your pick-up list yet. The ! on a quest on Available puts it there, and the route takes it in.")
  elseif r.legs and r.legs[1] then
    line = (QB.mode == "rush" and "Start at |cffe8c35a" or "Log out at |cffe8c35a") .. r.legs[1].stop.name .. "|r."
    if r.bind then
      local bind = QB.API.BindName()
      line = line .. " Bind your hearthstone in |cffe8c35a" .. r.bind.town .. "|r"
      if bind ~= "" and not (bind:find(r.bind.town, 1, true) or r.bind.town:find(bind, 1, true)) then line = line .. " (it is set to " .. bind .. ")" end
      line = line .. "."
    end
    if r.lateFrom and r.goal == "hour" then line = line .. " Stops after the first hour come last." end
  end
  if fallback and not run then
    local first = r.legs and r.legs[1] and r.legs[1].stop.name
    line = (banking and "Nothing is banked yet" or "Nothing is ready to hand in yet") .. ": the arrow and the map follow Log and pick-ups."
      .. (first and ("  First stop: |cffe8c35a" .. first .. "|r.") or "")
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
      l.node:SetTexture(T.taxiG); l.node:SetTexCoord(0, 1, 0, 1)
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

  -- questing: first where to do what your log still asks, then the hand-ins
  local doLegs = (not banking and not run and mode == "now") and UI.ObjectiveLegs(5) or {}
  local tDo = 0
  for i, dl in ipairs(doLegs) do
    local l = v.legs:Get()
    l.divider:SetShown(i == 1)
    l.divider:SetText("Do now")
    l.divider:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    layLeg(l, width, y, v.scroll.child)
    -- the game's cursor for what is done here: sword, bag, cogwheel
    l.node:SetVertexColor(1, 1, 1, 1)
    if QB.QuestMap and QB.QuestMap.PaintKind then QB.QuestMap.PaintKind(l.node, dl.sp.kind) else l.node:SetTexture(131021) end
    tDo = tDo + dl.mins
    l.clock:SetText(QB.Clock(tDo))
    l.travelIcon:SetTexture(travelIcon("foot"))
    l.travel:SetText(string.format("On foot, about %d min, %d yd", math.max(1, math.floor(dl.mins + 0.5)), math.floor(dl.yards / 10 + 0.5) * 10))
    l.name:SetText(dl.name)
    l.level:SetText("")
    l.pin.stop = { m = dl.sp.m, x = dl.sp.x * 100, y = dl.sp.y * 100, name = dl.name }
    l.pin:Show()
    l.note:SetText("")
    local top = l.divider:IsShown() and 22 or 0
    local ry = 46 + top
    for k, q in ipairs(dl.quests) do
      local rr = legRow(l, k)
      rr:ClearAllPoints()
      rr:SetPoint("TOPLEFT", 66, -ry)
      rr:SetWidth(width - 74)
      rr.q, rr.st, rr.xpv, rr.pct, rr.plvl, rr.doneXP = q, QB:Status(q), nil, nil, nil, nil
      rr.icon:Show()
      rr.tick:Hide()
      setIcon(rr.icon, q.icon)
      rr.name:SetText(q.name)
      rr.name:SetTextColor(INK[1], INK[2], INK[3])
      local objs = QB.API.Objectives(q.id) or {}
      local left = {}
      for _, o in ipairs(objs) do if not o.done and #left < 1 then left[#left + 1] = QB.Plain(o.text) or "" end end
      rr.npc:SetText(left[1] or "")
      rr.xp:SetText(QB.Comma(QB:Value(q.id) or 0))
      ry = ry + 20
    end
    for k = #dl.quests + 1, #l.rows do l.rows[k]:Hide() end
    l:SetAlpha(1)
    l:SetHeight(ry + 10)
    y = y + ry + 10
  end
  v.thenHandIn = #doLegs > 0

  if (not r.legs or #r.legs == 0) and #doLegs == 0 then
    v.empty:SetText(run and "Everything that was ready is handed in. End the run to save it." or
      (mode == "now" and ((QB:Banking() and "Nothing is banked yet." or "Nothing is ready to hand in yet.") .. " Finished quests and quest items in your bags show up here in hand-in order. Log and pick-ups shows the route you're building towards.") or
        "Nothing in your log or on your pick-up list yet. The ! on a quest on Available puts it there."))
    v.empty:ClearAllPoints()
    v.empty:SetPoint("TOPLEFT", 60, -y - 20)
    v.empty:Show()
  else
    v.empty:Hide()
  end

  for i, leg in ipairs(r.legs or {}) do
    local l = v.legs:Get()
    local s = leg.stop
    local lateStart = leg.late and not (r.legs[i - 1] and r.legs[i - 1].late) and r.goal == "hour" and not run
    l.divider:SetShown(lateStart or (i == 1 and v.thenHandIn))
    l.divider:SetText(lateStart and "After the first hour" or "Then hand in")
    l.divider:SetTextColor(BAD[1], BAD[2], BAD[3])
    if not lateStart then l.divider:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
    l.node:SetVertexColor(1, 1, 1, 1)
    layLeg(l, width, y, v.scroll.child)
    l.node:SetTexture(i == 1 and T.taxiY or T.taxiGray); l.node:SetTexCoord(0, 1, 0, 1)
    l.clock:SetText(QB.Clock(leg.t))
    local kind = leg.kind
    l.travelIcon:SetTexture(travelIcon(kind))
    local label = KIND[kind] or kind
    if kind == "start" then
      label = QB.mode == "lock" and "Log in here" or "Start here"
    else
      -- (no known way: to or from an open map off the two continents, Zephras Isle, the planner knows no boat or
      -- portal; the arrow's way below may, by the hearthstone)
      if kind ~= "none" then label = label .. string.format(", about %d min", math.max(1, math.floor(leg.travel + 0.5))) end
      if kind == "hearth" and leg.inn then label = label .. " to " .. QB.Data.HUB[r.fac][leg.inn][1] end
      -- the next stop from where you stand: the way the arrow shows it, by the flight paths you know (Travel.lua)
      local plan = i == 1 and mode == "now" and QB.Arrow.Guided() and QB.Travel.PlanTo(s, "route")
      if plan then
        label = QB.Travel.Summary(plan)
        local first
        for _, tl in ipairs(plan.legs) do if tl.kind ~= "walk" then first = tl break end end
        l.travelIcon:SetTexture(first and first.icon.file or travelIcon("foot"))
      end
    end
    l.travel:SetText(label)
    local here = mapID and mapID == s.m and "  |cff6cdc74you are here|r" or ""
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
      routeMark(rr, row.q, row.e.st)
      rr.name:SetText(row.q.name)
      local c = row.blocked and INK_SOFT or INK
      rr.name:SetTextColor(c[1], c[2], c[3])
      rr.npc:SetText(row.q.turn and row.q.turn.n or "")
      local xpText = QB.Comma(row.xp)
      if row.blocked then xpText = "|cffe05a4aafter its first step|r"
      elseif row.pct < 100 then xpText = string.format("|cffe05a4a%d%%|r  %s", row.pct, xpText) end
      rr.xp:SetText(xpText)
      ry = ry + 20
    end
    for k = #leg.rows + 1, #l.rows do l.rows[k]:Hide() end
    l:SetAlpha(leg.late and r.goal == "hour" and not run and 0.75 or 1)
    l:SetHeight(ry + 10)
    y = y + ry + 10
  end

  -- what the route could not place, and what waits on a dungeon run (Model.lua's route.waiting: held, not done, no
  -- spot to lead to; the plan counts nothing for it until it is done)
  for _, blk in ipairs(SIDE_BLOCKS) do
    local list = r[blk.key]
    if list and #list > 0 then
      local l = v.legs:Get()
      l.divider:Hide()
      layLeg(l, width, y, v.scroll.child)
      l.node:SetTexture(T.taxiGray); l.node:SetTexCoord(0, 1, 0, 1)
      l.clock:SetText("")
      l.travelIcon:SetTexture(T[blk.icon])
      l.travel:SetText(blk.travel)
      l.name:SetText(#list .. (#list == 1 and " quest" or " quests"))
      l.level:SetText("")
      l.pin:Hide()
      l.note:SetText(blk.note)
      local ry = 64
      for k, e in ipairs(list) do
        local rr = legRow(l, k)
        rr:ClearAllPoints()
        rr:SetPoint("TOPLEFT", 66, -ry)
        rr:SetWidth(width - 74)
        rr.q, rr.st, rr.xpv, rr.pct, rr.plvl, rr.doneXP = e.q, e.st, QB:Value(e.q.id), nil, nil, nil
        routeMark(rr, e.q, e.st)
        rr.name:SetText(e.q.name)
        rr.name:SetTextColor(INK[1], INK[2], INK[3])
        rr.npc:SetText(e.q.turn and (e.q.turn.inside and (e.q.turn.n .. ", inside") or e.q.turn.n) or "NPC unknown")
        rr.xp:SetText(QB.Comma(rr.xpv or 0))
        ry = ry + 20
      end
      for k = #list + 1, #l.rows do l.rows[k]:Hide() end
      l:SetAlpha(1)
      l:SetHeight(ry + 10)
      y = y + ry + 10
    end
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

  m.hi:SetAlpha(0.6)
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
  m.lack = text(m, "GameFontNormalSmall", 11, GOLD_SOFT, "RIGHT", 120)
  m.lack:SetPoint("RIGHT", -40, 0)
  m.copy = iconButton(m, 24, T.letter)
  m.copy:SetPoint("RIGHT", -10, 0)
  m.copy:SetScript("OnClick", function(self)
    local n = QB.Sync and QB.Sync:CopyPlan(self:GetParent().who) or 0
    QB:Print(n > 0 and string.format("Added %d of their quests to your plan.", n) or "Nothing of theirs fits your plan.")
    UI:Refresh()
  end)
  tooltip(m.copy, function(tip)
    tip:AddLine("Copy their plan", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine(QB:Banking() and "Adds the quests they are banking that you can do too." or "Adds the quests they hold or plan to fetch that you can do too.", 1, 1, 1, true)
  end)
  tooltip(m, function(tip, self) if QB.Sync then QB.Sync:MemberTooltip(tip, self.who) end end)
  return m
end

-- a party member's quest, in the mode you are in: banking speaks of banked quests, questing of ready ones
local function stateWord(code)
  if code == "b" then return QB:Banking() and "banked" or "ready to hand in" end
  if code == "p" then return "to pick up" end
  if code == "a" then return "in log" end
  return ""
end

local function whoText(e)
  local parts = {}
  for _, w in ipairs(e.who) do
    local state = w.code == "a" and (w.prog or "in log") or stateWord(w.code)
    local name = QB.Sync and QB.Sync.ColorName(w.name, w.class, true) or w.name -- the dark cut: this sits on parchment
    if w.me then state = "|cff0a4a8a" .. state .. "|r" elseif w.code == "b" then state = "|cff6f6a61" .. state .. "|r" end
    parts[#parts + 1] = name .. " " .. state
  end
  return table.concat(parts, ",  ")
end

-- "A, B and C", as many as fit in room bytes, then "and 2 more"
local function nameList(names, room)
  for n = #names, 1, -1 do
    local shown = {}
    for i = 1, n do shown[i] = names[i] end
    local s
    if n == #names then
      s = #shown > 1 and (table.concat(shown, ", ", 1, n - 1) .. " and " .. shown[n]) or shown[1]
    else
      s = table.concat(shown, ", ") .. string.format(" and %d more", #names - n)
    end
    if #s <= room then return s end
  end
  return string.format("%d quests", #names)
end

-- a post asking for a group: the quests you still need in there, or the group's if you have none left
function UI.DungeonPost(d)
  local mine, theirs = {}, {}
  for _, e in ipairs(d.quests) do
    if e.need > 0 and e.q then
      local me = false
      for _, w in ipairs(e.who) do if w.me and w.code ~= "b" then me = true end end
      if me then mine[#mine + 1] = e.q.name else theirs[#theirs + 1] = e.q.name end
    end
  end
  local head = "Anyone up for " .. d.cat.name:gsub("^The ", "") .. "? "
  if #mine > 0 then
    local lead = "I still need "
    return head .. lead .. nameList(mine, 254 - #head - #lead) .. ".", d.cat.name .. ": the quests you still need in there."
  end
  local lead = "Quests still to do: "
  return head .. lead .. nameList(theirs, 254 - #head - #lead) .. ".", d.cat.name .. ": the quests your group still needs in there."
end

local function makeDungeonRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(32)
  r.hi = tex(r, "HIGHLIGHT", T.rowHi)
  r.hi:SetAllPoints()
  r.hi:SetBlendMode("ADD")

  r.hi:SetAlpha(0.6)
  r.icon = tex(r, "ARTWORK", nil, 18, 18)
  r.icon:SetPoint("TOPLEFT", 4, -3)
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.name = text(r, "GameFontNormal", 12, INK, "LEFT", 240)
  r.name:SetPoint("TOPLEFT", 28, -4)
  r.who = text(r, "GameFontNormalSmall", 10, INK_SOFT, "LEFT", 256)
  r.who:SetPoint("TOPLEFT", 28, -18)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self, which) if self.q then UI.QuestClick(self.q, QB:Status(self.q), which) end end)
  tooltip(r, function(tip, self)
    if not self.q then return end
    UI.QuestTooltip(tip, self.q, QB:Status(self.q))
    tip:AddLine(" ")
    for _, w in ipairs(self.e.who) do
      local state = w.code == "a" and ("in their log" .. (w.prog and (", " .. w.prog) or "")) or stateWord(w.code)
      if w.me then state = w.code == "a" and ("in your log" .. (w.prog and (", " .. w.prog) or "")) or (w.code == "p" and "yours to pick up" or state) end
      tip:AddDoubleLine(w.name, state, 1, 1, 1, w.code == "b" and 0.6 or 0.4, w.code == "b" and 0.6 or 1, w.code == "b" and 0.6 or 0.4)
    end
  end)
  return r
end

local function makeDungeonCard(parent)
  local c = CreateFrame("Frame", nil, parent, BD)
  backdrop(c, nil, T.tipBorder, 12, 3)
  if c.SetBackdropBorderColor then c:SetBackdropBorderColor(0.45, 0.33, 0.16, 0.9) end
  c.head = CreateFrame("Button", nil, c)
  c.head:SetPoint("TOPLEFT", 3, -3)
  c.head:SetPoint("TOPRIGHT", -3, -3)
  c.head:SetHeight(36)
  c.art = tex(c.head, "BACKGROUND")
  c.art:SetAllPoints()
  c.shade = tex(c.head, "BORDER")
  c.shade:SetColorTexture(0.06, 0.04, 0.02, 0.6)
  c.shade:SetAllPoints()
  c.icon = tex(c.head, "ARTWORK", nil, 26, 26)
  c.icon:SetPoint("LEFT", 6, 0)
  c.title = text(c.head, "GameFontNormal", 13, GOLD, "LEFT", 170)
  c.title:SetPoint("TOPLEFT", 38, -4)
  c.people = text(c.head, "GameFontHighlightSmall", 10, WHITE, "LEFT", 170)
  c.people:SetPoint("TOPLEFT", 38, -20)
  c.gain = text(c.head, "GameFontNormal", 12, GOLD, "RIGHT", 70)
  c.gain:SetPoint("TOPRIGHT", -8, -4)
  c.left = text(c.head, "GameFontHighlightSmall", 10, WHITE, "RIGHT", 90)
  c.left:SetPoint("TOPRIGHT", -8, -20)
  -- the dungeon's map (DungeonMap.lua): Blizzard's floor art with the bosses, their loot and the quests
  c.map = button(c, "Map", 44)
  c.map:SetPoint("TOPRIGHT", c.head, "TOPRIGHT", -84, -8)
  c.map:SetScript("OnClick", QB.Safe(function() if c.head.cat and QB.DMap then QB.DMap.Toggle(c.head.cat) end end, "dungeon map"))
  c.head:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  c.head:SetScript("OnClick", function(self, which)
    if which == "RightButton" then
      if self.data then UI:PostDialog(UI.DungeonPost(self.data)) end
      return
    end
    local e = self.cat and self.cat.entrance
    if e then QB.API.SetWaypoint(e.m, e.x, e.y, self.cat.name .. " entrance") end
  end)
  tooltip(c.head, function(tip, self)
    if not self.cat then return end
    tip:AddLine(self.cat.name, GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine(string.format("%d quests still to do among %s, worth about %s XP together.", self.data.left, table.concat(self.data.people, ", "), QB.Comma(self.data.xp)), 1, 1, 1, true)
    tip:AddLine((self.cat.entrance and "Click: waypoint on the entrance.  " or "") .. "Right-click: ask your party or guild to come along.", 0.5, 0.5, 0.5, true)
  end)
  c.rows = pool(c, makeDungeonRow)
  return c
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
  -- the share: the game's own push of what the party lacks, one quest at a time
  v.shareBtn = button(v, "Share", 120)
  v.shareBtn:SetPoint("BOTTOMLEFT", LEFT, 12)
  v.shareBtn:SetScript("OnClick", QB.Safe(function(self)
    local n = QB.Sync and QB.Sync:Share(self.ids or {}) or 0
    QB:Print(n > 0 and string.format("Sharing %d quest%s with the party, one every second and a half.", n, n == 1 and "" or "s") or "Nothing to share.")
  end, "share quests"))
  tooltip(v.shareBtn, function(tip, self)
    tip:AddLine("Share with the party", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("The game's own share, for every quest a member lacks (all your shareable ones when a member runs no QuestBank). Each gets the usual prompt.", 1, 1, 1, true)
    for _, id in ipairs(self.ids or {}) do local q = Q.Get(id); if q then tip:AddLine(q.name, 0.8, 0.8, 0.8) end end
  end)
  v.postBtn = button(v, "Post next step", 120)
  v.postBtn:SetPoint("BOTTOMLEFT", LEFT + 126, 12)
  v.postBtn:SetScript("OnClick", QB.Safe(function()
    local line = QB.Sync and QB.Sync.NextStepText()
    if line then UI:PostDialog(line, "The next step, for party chat.") else QB:Print("No next step yet: plan a route or pick quests first.") end
  end, "post next step"))
  tooltip(v.postBtn, function(tip)
    tip:AddLine("Post the next step", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Your route's first stop and its quests, as one line you check before it goes to party chat.", 1, 1, 1, true)
  end)
  v.syncBtn = button(v, "Send now", 96)
  v.syncBtn:SetPoint("BOTTOMLEFT", LEFT + 252, 12)
  v.syncBtn:SetScript("OnClick", QB.Safe(function() if QB.Sync then QB.Sync:Broadcast(true) end end, "send now"))
  tooltip(v.syncBtn, function(tip)
    tip:AddLine("Send your quests to QuestBank users now", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Party and guild sharing is set in Settings. /qb sync Name whispers one friend.", 1, 1, 1, true)
  end)

  v.runTitle = text(v, "GameFontNormalLarge", 15, INK, "LEFT", 330)
  v.runTitle:SetPoint("TOPLEFT", RIGHT, -12)
  v.runTitle:SetText("Together next")
  v.runHint = para(v, "GameFontNormalSmall", 11, INK_SOFT, 330)
  v.runHint:SetPoint("TOPLEFT", RIGHT, -32)
  v.runHint:SetHeight(28)
  v.runHint:SetText("Quests you all hold, then the dungeons with quests left for any of you.")
  local holder = CreateFrame("Frame", nil, v)
  holder:SetPoint("TOPLEFT", RIGHT - 10, -58)
  holder:SetPoint("BOTTOMRIGHT", 0, 0)
  v.dscroll = scrollArea(holder)
  v.together = pool(v.dscroll.child, makeRow)
  v.togetherHead = text(v.dscroll.child, "GameFontNormal", 12, GOLD, "LEFT", 300)
  v.dcards = pool(v.dscroll.child, makeDungeonCard)
  v.noRuns = para(v.dscroll.child, "GameFontNormal", 12, INK_SOFT, 300)
  v.noRuns:SetPoint("TOPLEFT", 8, -8)
  v.Refresh = function() UI:RefreshPartyView(v) end
  return v
end

function UI:RefreshPartyView(v)
  local S = QB.Sync
  local units = S and S.GroupUnits() or {}
  local inGroup = #units > 1
  local synced = S and S:Members() or {}
  -- the group first, QuestBank or not; QuestBank users outside it (the guild) after
  local list, seen = {}, {}
  local mine = S and S:MemberByName(QB.state.name or "")
  for _, u in ipairs(units) do
    if not u.me then
      local m = S and S:MemberByName(u.name)
      if m then seen[m.key] = true end
      list[#list + 1] = { unit = u, m = m }
    end
  end
  for _, m in ipairs(synced) do if not seen[m.key] and m ~= mine then list[#list + 1] = { m = m } end end
  v.title:SetText(inGroup and string.format("Party of %d", #units) or (#synced > 0 and "QuestBank users" or "Party"))
  v.hint:SetText(inGroup and "Members with QuestBank share their quests; the others get yours through you: share what they lack, post the next step."
    or "Group up and the party shows here, QuestBank or not. Guild members with QuestBank show below.")
  local shareable = S and S.Shareable() or {}
  local lackAll, lackSet = {}, {}
  v.members:Reset()
  for i, e in ipairs(list) do
    if i > 8 then break end
    local row = v.members:Get()
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", LEFT - 4, -66 - (i - 1) * 42)
    row:SetWidth(390)
    local m, u = e.m, e.unit
    row.who = m and m.key or nil
    local class = (m and m.class) or (u and u.class) or ""
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then row.class:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) else row.class:SetTexCoord(0, 0.25, 0, 0.25) end
    local cc = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS) and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
    row.name:SetText((u and u.name) or (m and m.name) or "?")
    if cc then row.name:SetTextColor(cc.r, cc.g, cc.b) else row.name:SetTextColor(INK[1], INK[2], INK[3]) end
    local level = (u and u.level) or (m and m.level)
    local yards = u and S.YardsTo(u)
    row.sub:SetText(string.format("Level %s%s", level or "?", yards and (" \194\183 " .. yards .. " yd") or (u and "" or " \194\183 guild")))
    if m then
      row.bank:SetText(string.format(QB:Banking() and "QuestBank \194\183 banked %.1f" or "QuestBank \194\183 ready %.1f", m.banked or 0))
      if m.runStart then
        row.run:SetText(string.format("Running %s, %d in, +%s", QB.Clock(m.runMin or 0), m.runN or 0, QB.Short(m.runXP or 0)))
        row.run:SetTextColor(GOOD[1], GOOD[2], GOOD[3])
      else
        row.run:SetText(m.age and m.age > 90 and string.format("Seen %d min ago", math.floor(m.age / 60)) or "Online")
        row.run:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
      end
      row.dot:SetTexture(m.age and m.age > 600 and T.dotGray or (m.runStart and T.dotYellow or T.dotGreen))
    else
      row.bank:SetText("No QuestBank")
      row.run:SetText("gets your plan through you")
      row.run:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
      row.dot:SetTexture(T.dotGray)
    end
    if u then
      local lack, known = S:Lacking(u, shareable)
      for _, id in ipairs(lack) do if not lackSet[id] then lackSet[id] = true; lackAll[#lackAll + 1] = id end end
      row.lack:SetText(#lack > 0 and string.format(known and "lacks %d of yours" or "share %d", #lack) or (known and "has your quests" or ""))
    else
      row.lack:SetText("")
    end
    row.copy:SetShown(m ~= nil and m.fac == QB.faction and m.quests ~= nil)
  end
  v.members:HideRest()
  v.empty:SetShown(#list == 0)
  -- the hint above already says how the party fills: the empty line only says it is empty
  v.empty:SetText("Nobody with you yet.")
  v.shareBtn.ids = lackAll
  v.shareBtn:SetText(#lackAll > 0 and string.format("Share %d", #lackAll) or "Share")
  v.shareBtn:SetEnabled(#lackAll > 0)
  v.postBtn:SetEnabled(inGroup)
  -- together next: the quests in your log that QuestBank members hold too, the richest first
  local width = v.dscroll:Width() - 4
  if width > 330 then width = 316 end
  v.together:Reset()
  local tog = {}
  if inGroup then
    for _, e in ipairs(QB.state.logOrder or {}) do
      local q = Q.Get(e.id)
      if q then
        local holders = 0
        for _, x in ipairs(list) do if x.unit and x.m and x.m.quests and x.m.quests[e.id] then holders = holders + 1 end end
        if holders > 0 then tog[#tog + 1] = { q = q, st = QB:Status(q), value = QB:Value(e.id), held = true, holders = holders } end
      end
    end
    table.sort(tog, function(a, b) if a.holders ~= b.holders then return a.holders > b.holders end return (a.value or 0) > (b.value or 0) end)
  end
  local y = 0
  if #tog > 0 then
    v.togetherHead:ClearAllPoints(); v.togetherHead:SetPoint("TOPLEFT", 4, -y)
    v.togetherHead:SetText(string.format("%d quest%s you hold together", #tog, #tog == 1 and "" or "s"))
    v.togetherHead:Show()
    y = y + 20
    for i, it in ipairs(tog) do
      if i > 6 then break end
      local r = v.together:Get()
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y)
      fillRow(r, it, width)
      r.status:SetText(string.format("%d of you", it.holders + 1))
      y = y + 22
    end
    y = y + 10
  else
    v.togetherHead:Hide()
  end
  v.together:HideRest()
  local dungeons = S and S:Dungeons() or {}
  v.dcards:Reset()
  for _, d in ipairs(dungeons) do
    local c = v.dcards:Get()
    c.rows:Reset()
    c.head.cat, c.head.data = d.cat, d
    if d.cat.bg then c.art:SetTexture(d.cat.bg); c.art:SetTexCoord(0, 1, 0.2, 0.45) else c.art:SetColorTexture(0.16, 0.12, 0.08, 1) end
    c.icon:SetTexture(d.cat.icon)
    c.title:SetText(d.cat.name)
    local people = {}
    for i, n in ipairs(d.people) do people[i] = QB.Sync and QB.Sync.ColorName(n, d.classOf and d.classOf[n]) or n end
    c.people:SetText(table.concat(people, ", "))
    c.gain:SetText("+" .. QB.Short(d.xp))
    c.left:SetText(d.left == 1 and "1 still to do" or string.format("%d still to do", d.left))
    local ry = 42
    for _, e in ipairs(d.quests) do
      if e.need > 0 and e.q then
        local r = c.rows:Get()
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 4, -ry)
        r:SetWidth(width - 8)
        r.name:SetWidth(width - 44)
        r.who:SetWidth(width - 36)
        r.q, r.e = e.q, e
        setIcon(r.icon, e.q.icon)
        r.name:SetText(string.format("%s  |cff9a8a70L%d|r", e.q.name, e.q.lvl))
        r.who:SetText(whoText(e))
        ry = ry + 32
      end
    end
    c.rows:HideRest()
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", v.dscroll.child, "TOPLEFT", 0, -y)
    c:SetSize(width, ry + 6)
    y = y + ry + 14
  end
  v.dcards:HideRest()
  v.noRuns:SetShown(#dungeons == 0)
  v.noRuns:SetText("No dungeon quests in your log or on your pick-up list yet. Choose some on Available; your party's show here too.")
  v.dscroll:SetContentHeight(math.max(y, 40))
end

----------------------------------------------------------------------------
-- page 5: settings
----------------------------------------------------------------------------
local function checkRow(parent, x, y, label, width)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(24, 24)
  c:SetPoint("TOPLEFT", x, y)
  c.label = text(parent, "GameFontNormal", 12, INK, "LEFT", width or 320)
  c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
  c.label:SetText(label)
  return c
end

local function heading(parent, x, y, label, width)
  local t = text(parent, "GameFontNormalLarge", 15, INK, "LEFT", width or 330)
  t:SetPoint("TOPLEFT", x, y)
  t:SetText(label)
  return t
end

function UI:CreateSettingsView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()
  -- more than one screen of switches: the page scrolls
  v.scroll = scrollArea(v)
  local p = v.scroll.child
  local LEFT, RIGHT = 12, 390
  -- 6.0: the sections in the order the player meets them: Guide, Map and minimap, the modules, Data you share, Banking
  -- last. Two columns, each laid top to bottom with a running y (yl, yr): a block starts at the column's y and moves
  -- it down by its own height, so no row stands on another. v.headings keeps the headings in their order
  v.headings = {}
  local function head(x, y, label, width)
    local t = heading(p, x, y, label, width)
    v.headings[#v.headings + 1] = t
    return t
  end
  local function subhead(x, y, label, width)
    local t = text(p, "GameFontNormal", 12, GOLD_SOFT, "LEFT", width or 330)
    t:SetPoint("TOPLEFT", x, y)
    t:SetText(label)
    return t
  end
  local yl, yr = -12, -12

  ----------------------------------------------------------------------------------------------------------------
  -- Guide (Guide.lua, StepFrame.lua, Arrow.lua, Auto.lua): the step frame, the arrow, what is done for you at the
  -- quest giver, the minimap's ! and the tooltips' progress
  ----------------------------------------------------------------------------------------------------------------
  local y0 = yl
  head(LEFT, y0, "Guide", 370)
  v.guideOn = checkRow(p, LEFT, y0 - 24, "Guide me: the step frame, the arrow, the route from here", 340)
  v.guideOn:SetScript("OnClick", function(self)
    QB:Settings().guide.on = self:GetChecked() and true or false
    QB:MarkDirty()
    if QB.StepFrame then QB.StepFrame.Apply() end
    UI:Refresh()
  end)
  tooltip(v.guideOn, function(tip)
    tip:AddLine("Guide me", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("The step frame says what to do next, the arrow points there, and the plan takes the quests worth taking around you. Off, QuestBank plans only what you put on your route.", 1, 1, 1, true)
  end)
  v.guideFrame = checkRow(p, LEFT + 24, y0 - 52, "The step frame", 316)
  v.guideFrame:SetScript("OnClick", function(self)
    QB:Settings().guide.frame = self:GetChecked() and true or false
    if QB.StepFrame then QB.StepFrame.Apply() end
  end)
  v.guideLocked = checkRow(p, LEFT + 24, y0 - 80, "Locked in place", 316)
  v.guideLocked:SetScript("OnClick", function(self)
    QB:Settings().guide.locked = self:GetChecked() and true or false
    if QB.StepFrame then QB.StepFrame.Apply() end
  end)
  -- (6.1.1) the game's quest tracker out of sight while the step frame shows (StepFrame.lua's SF.Tracker): "it's hidden
  -- by default there in game, Blizzard's one, if they use ours"
  v.guideTracker = checkRow(p, LEFT + 24, y0 - 108, "Hide the game's quest tracker", 316)
  v.guideTracker:SetScript("OnClick", function(self)
    QB:Settings().guide.hideTracker = self:GetChecked() and true or false
    if QB.StepFrame then QB.StepFrame.Apply() end
  end)
  tooltip(v.guideTracker, function(tip)
    tip:AddLine("Hide the game's quest tracker", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("While the step frame shows, the game's own quest list at the right of the screen is out of sight. It comes back as soon as you untick this or the step frame goes. Never changed in a fight.", 1, 1, 1, true)
  end)
  v.guideScale = button(p, "100%", 70)
  v.guideScale:SetPoint("TOPLEFT", LEFT + 28, y0 - 136)
  v.guideScale:SetScript("OnClick", QB.Safe(function()
    local SF = QB.StepFrame
    local scales = SF and SF.SCALES or { 0.8, 1, 1.2 }
    local cur = QB:Settings().guide.scale or 1
    local i = 2
    for k, sc in ipairs(scales) do if math.abs(sc - cur) < 0.001 then i = k end end
    local sc = scales[i % #scales + 1]
    if SF and SF.SetScale then SF.SetScale(sc) else QB:Settings().guide.scale = sc end
    UI:Refresh()
  end, "settings: step frame size"))
  v.guideScaleLabel = text(p, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", 250)
  v.guideScaleLabel:SetPoint("LEFT", v.guideScale, "RIGHT", 8, 0)
  v.guideScaleLabel:SetText("The step frame's size")
  v.arrow = checkRow(p, LEFT, y0 - 164, "Direction arrow (right-click it for what it points at)")
  v.arrow:SetScript("OnClick", function(self) if QB.Arrow then QB.Arrow:Set(self:GetChecked() and true or false) end end)
  -- the arrow's look (Arrow.lua, arrowStyle): QuestBank's own arrow, or QuestTrail's compass; the button cycles
  UI.ARROW_STYLES = { questbank = "QuestBank's", compass = "Compass" }
  v.arrowStyle = button(p, "QuestBank's", 90)
  v.arrowStyle:SetPoint("TOPLEFT", LEFT + 28, y0 - 192)
  v.arrowStyle:SetScript("OnClick", QB.Safe(function()
    local set = QB:Settings()
    set.arrowStyle = set.arrowStyle == "compass" and "questbank" or "compass"
    if QB.Arrow and QB.Arrow.Restyle then QB.Arrow:Restyle() end
    UI:Refresh()
  end, "settings: arrow look"))
  tooltip(v.arrowStyle, function(tip)
    tip:AddLine("The arrow's look", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("QuestBank's: its own arrow, green ahead, gold to the side, red behind, glowing as it points ahead and pinging as you arrive. Compass: QuestTrail's dial and needle, by Krom.", 1, 1, 1, true)
  end)
  v.arrowHint = text(p, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", 250)
  v.arrowHint:SetPoint("LEFT", v.arrowStyle, "RIGHT", 8, 0)
  v.arrowHint:SetText("Arrow look. Its right-click menu has it too.")
  -- at the quest giver: accept and hand in for you (Auto.lua), as the welcome asked. Accept for me: a choice (5.4.4):
  -- Off, Quests on my route, Quests worth taking; the button cycles, its text says the choice in one line. Then, for
  -- Quests worth taking, what one outside your route gets
  local ACCEPT_ORDER = { "off", "route", "worth" }
  v.autoAccept = button(p, "Accept for me: Off", 300)
  v.autoAccept:SetPoint("TOPLEFT", LEFT + 4, y0 - 224)
  v.autoAccept:SetScript("OnClick", QB.Safe(function()
    local set = QB:Settings()
    local i = 1
    for k, m in ipairs(ACCEPT_ORDER) do if m == set.autoAccept then i = k end end
    set.autoAccept = ACCEPT_ORDER[i % #ACCEPT_ORDER + 1]
    UI:Refresh()
  end, "settings: accept for me"))
  tooltip(v.autoAccept, function(tip)
    tip:AddLine("Accept for me", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Off: you take every quest yourself.", 1, 1, 1, true)
    tip:AddLine("Quests on my route: your pick-up list, the Guide's picks, and the next steps of the chains you are on.", 1, 1, 1, true)
    tip:AddLine("Quests worth taking: those, and any other the route planner thinks worth it (never grey, never one that pays next to nothing).", 1, 1, 1, true)
  end)
  v.autoOther = button(p, "Outside my route: Accept them", 300)
  v.autoOther:SetPoint("TOPLEFT", LEFT + 4, y0 - 250)
  v.autoOther:SetScript("OnClick", QB.Safe(function()
    local set = QB:Settings()
    set.autoAcceptOther = set.autoAcceptOther == "leave" and "accept" or "leave"
    UI:Refresh()
  end, "settings: outside my route"))
  tooltip(v.autoOther, function(tip)
    tip:AddLine("Quests outside my route", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("With Quests worth taking: a quest worth it that is not on your route is taken for you, or its quest window is left open for you to decide.", 1, 1, 1, true)
  end)
  v.acceptHint = para(p, "GameFontNormalSmall", 11, INK_SOFT, 370)
  v.acceptHint:SetPoint("TOPLEFT", LEFT, y0 - 276)
  v.acceptHint:SetHeight(44)
  v.acceptHint:SetText("At an NPC and when a party member shares one; escorts are yours to join in the game's prompt. Hold Shift to do it by hand. Not repeatable or grey quests, nor places you skip.")
  v.autoTurnIn = checkRow(p, LEFT, y0 - 324, "Hand in finished quests for me", 340)
  v.autoTurnIn:SetScript("OnClick", function(self) QB:Settings().autoTurnIn = self:GetChecked() and true or false end)
  v.turnInHint = para(p, "GameFontNormalSmall", 11, INK_SOFT, 370)
  v.turnInHint:SetPoint("TOPLEFT", LEFT, y0 - 350)
  v.turnInHint:SetHeight(58)
  v.turnInHint:SetText("Questing and the rush: everything. While you bank: only quests you left out of the route, ones that pay next to nothing on the day, and a step you hand in to bank a better one. A reward to choose, or a quest QuestBank can't value, waits for you.")
  -- the decide-yourself key: held at the NPC, the auto actions above leave the quest to you
  v.autoKey = button(p, "Shift", 70)
  v.autoKey:SetPoint("TOPLEFT", LEFT + 4, y0 - 416)
  v.autoKeyLabel = text(p, "GameFontNormal", 12, INK, "LEFT", 290)
  v.autoKeyLabel:SetPoint("LEFT", v.autoKey, "RIGHT", 8, 0)
  v.autoKeyLabel:SetText("held at the NPC: decide the quest yourself")
  local KEYS = { "shift", "ctrl", "alt", "none" }
  UI.KEY_NAMES = { shift = "Shift", ctrl = "Ctrl", alt = "Alt", none = "No key" }
  v.autoKey:SetScript("OnClick", QB.Safe(function()
    local set = QB:Settings()
    local i = 1
    for k, name in ipairs(KEYS) do if name == set.autoKey then i = k end end
    set.autoKey = KEYS[i % #KEYS + 1]
    UI:Refresh()
  end, "settings: key"))
  -- the minimap's ! (Minimap.lua) and the tooltips' progress (Tips.lua)
  v.minimapGivers = checkRow(p, LEFT, y0 - 448, "A ! on the minimap for every quest I can take", 340)
  v.minimapGivers:SetScript("OnClick", function(self)
    QB:Settings().minimapGivers = self:GetChecked() and true or false
    if QB.Mini and QB.Mini.Invalidate then QB.Mini.Invalidate() end
    if QB.Mini and QB.Mini.Place then QB.Mini.Place() end
  end)
  tooltip(v.minimapGivers, function(tip)
    tip:AddLine("The minimap's !", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("The quests you can take now on your map, as the world map shows them: not grey, nothing you hold or have done. Givers a few steps apart share a pin with a count.", 1, 1, 1, true)
  end)
  v.tipProgress = checkRow(p, LEFT, y0 - 476, "Quest progress in mob tooltips", 340)
  v.tipProgress:SetScript("OnClick", function(self) QB:Settings().tipProgress = self:GetChecked() and true or false end)
  tooltip(v.tipProgress, function(tip)
    tip:AddLine("Quest progress in tooltips", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("A mob or object that counts for a quest in your log gets its count in its tooltip, \"Kobold Vermin: 3/8\", and your party's counts.", 1, 1, 1, true)
  end)
  yl = y0 - 524

  ----------------------------------------------------------------------------------------------------------------
  -- Map and minimap: the route's pins, the minimap button, the quest icons on the world map (QuestMap.lua), the
  -- minimap (Minimap.lua, MinimapView.lua, Walk.lua), QuestBank's map page (MapPage.lua), the icons' size
  ----------------------------------------------------------------------------------------------------------------
  y0 = yl
  head(LEFT, y0, "Map and minimap", 370)
  v.pins = checkRow(p, LEFT, y0 - 24, "The route's pins on the world map")
  v.pins:SetScript("OnClick", function(self)
    if QB.Pins then
      if (self:GetChecked() and true or false) ~= (QB:Settings().pins and true or false) then QB.Pins:Toggle() end
    else
      QB:Settings().pins = self:GetChecked() and true or false
    end
    UI:Refresh()
  end)
  v.minimap = checkRow(p, LEFT, y0 - 52, "Button on the minimap")
  v.minimap:SetScript("OnClick", function(self)
    QB:Settings().minimap.hide = not self:GetChecked()
    if QB.Minimap then QB.Minimap:Update() end
  end)
  -- quest icons on each zone's map (QuestMap.lua), the Forever client only: one switch for all, one for each kind
  local MAP_ICONS = {
    { "mapIcons", LEFT, y0 - 80, "Quest icons on the world map", 340,
      "On each zone's map, drawn as the game draws its own pins: a ! where quests you can take start, the game's quest pin with its turn-in mark where finished ones are handed in and in progress where to do the ones in your log, and each dungeon's entrance with how many of its quests you have done. Click one for a waypoint; Shift-click a ! to put its quests on your pick-up list. The route's pins have their own switch above." },
    { "mapGive", LEFT + 24, y0 - 108, "Quests you can pick up", 316,
      "A yellow ! on the NPCs with quests for your faction, class and level that you haven't done. Grey (low-level) quests are left off, as the game does, unless Low-level quests is ticked; so are quests that need a profession or an item first. Where a route pin stands on the NPC, that pin's tooltip lists the NPC's quests instead." },
    { "mapTurn", LEFT + 24, y0 - 164, "Hand-ins", 316,
      "The game's quest pin, with its turn-in mark, on the NPC each finished quest in your log goes to." },
    { "mapObj", LEFT + 24, y0 - 192, "Objectives and quest items", 316,
      "For the quests in your log, the game's in-progress pin where to do each objective you haven't finished; for quests that start from an item, a red ! where it drops. Each tooltip says where the spot comes from: Wowhead Forever, Classic data or players' games." },
  }
  for _, r in ipairs(MAP_ICONS) do
    local key, title, about = r[1], r[4], r[6]
    local row = checkRow(p, r[2], r[3], title, r[5])
    row:SetScript("OnClick", function(self)
      if QB.QuestMap then QB.QuestMap.Set(key, self:GetChecked()) else QB:Settings()[key] = self:GetChecked() and true or false end
      UI:Refresh()
    end)
    row:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(title, 1, 1, 1)
      GameTooltip:AddLine(about, nil, nil, nil, true)
      if not (QB.QuestMap and QB.QuestMap.Available()) then GameTooltip:AddLine("Only on the Forever client.", 1, 0.5, 0.3, true) end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    v[key] = row
  end
  -- (6.1.1) the quests the game counts as trivial (grey): their ! off unless asked ("we also show low level quests as
  -- default?"), on the world map, the Map page and the minimap's (QuestMap.lua givers)
  v.mapLow = checkRow(p, LEFT + 48, y0 - 136, "Low-level quests", 292)
  v.mapLow:SetScript("OnClick", function(self)
    QB:Settings().mapLowLevel = self:GetChecked() and true or false
    if QB.QuestMap and QB.QuestMap.Update then QB.QuestMap:Update() end
    if QB.Mini then QB.Mini.Invalidate(); QB.Mini.Place() end
    UI:Refresh()
  end)
  tooltip(v.mapLow, function(tip)
    tip:AddLine("Low-level quests", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Quests the game counts as trivial (grey) for your level: their ! on the world map, the Map page and the minimap, half bright as the game draws them. Off, they are left out, as the game leaves them out.", 1, 1, 1, true)
  end)
  -- the route on the minimap (Minimap.lua)
  v.minimapPins = checkRow(p, LEFT, y0 - 220, "Route stops, pick-ups and dungeon entrances on the minimap", 340)
  v.minimapPins:SetScript("OnClick", function(self) QB:Settings().minimapPins = self:GetChecked() and true or false; if QB.Mini then QB.Mini.Place() end end)
  tooltip(v.minimapPins, function(tip)
    tip:AddLine("The minimap", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Alt-drag moves it, Ctrl and the wheel size it, the wheel zooms it.", 1, 1, 1, true)
    tip:AddLine("/qb minimap reset puts it back as the game had it.", 0.6, 0.6, 0.6, true)
  end)
  -- its far zoom and drag (MinimapView.lua), your trails on it (Walk.lua); the other switches are on its own menu
  v.mmExtended = checkRow(p, LEFT, y0 - 248, "Far zoom and drag", 340)
  v.mmExtended:SetScript("OnClick", function(self) QB:Settings().mmExtended = self:GetChecked() and true or false; if QB.Mini then QB.Mini.Update(0) end end)
  tooltip(v.mmExtended, function(tip)
    tip:AddLine("Far zoom and drag", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Wheel out past the game's widest, over the game's own minimap tiles. Drag to look around; it comes back to you.", 1, 1, 1, true)
  end)
  v.walkShow = checkRow(p, LEFT, y0 - 276, "Your walked trails", 340)
  v.walkShow:SetScript("OnClick", function(self) QB:Settings().walkShow = self:GetChecked() and true or false; if QB.Mini then QB.Mini.Place() end end)
  -- how the markers are drawn (Minimap.lua, Arrow.lua): QuestTrail's look, or the game's own icons; the button cycles
  v.markerStyle = button(p, "QuestTrail", 90)
  v.markerStyle:SetPoint("TOPLEFT", LEFT + 4, y0 - 304)
  UI.MARKER_STYLES = { questtrail = "QuestTrail", game = "Game icons" }
  v.markerStyle:SetScript("OnClick", QB.Safe(function()
    local set = QB:Settings()
    set.markerStyle = set.markerStyle == "game" and "questtrail" or "game"
    if QB.Mini then QB.Mini.Invalidate(); QB.Mini.Place() end
    if QB.Arrow and QB.Arrow.Restyle then QB.Arrow:Restyle() end
    UI:Refresh()
  end, "settings: marker style"))
  tooltip(v.markerStyle, function(tip)
    tip:AddLine("Marker style", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("QuestTrail: its coloured diamonds with a glyph for the work, step circles, coloured strokes and compass dial, by Krom. Game icons: the game's own numbered pins and cursor icons.", 1, 1, 1, true)
  end)
  v.minimapHint = text(p, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", 270)
  v.minimapHint:SetPoint("LEFT", v.markerStyle, "RIGHT", 8, 0)
  v.minimapHint:SetText("Marker style. Right-click the minimap for the rest.")
  -- the Map: QuestBank's map page on the Map key and the sidebar (MapPage.lua), or the game's world map (UI.OpenMap)
  v.mapPage = checkRow(p, LEFT, y0 - 332, "Map key opens QuestBank's map", 340)
  v.mapPage:SetScript("OnClick", function(self) QB:Settings().mapPage = self:GetChecked() and true or false; UI:Refresh() end)
  tooltip(v.mapPage, function(tip)
    tip:AddLine("QuestBank's map", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("QuestBank's Map key and the sidebar's Map open QuestBank's own map page: the game's map with the game's own pins and QuestBank's route on it, and the zone's quests beside it. Off, they open the game's world map.", 1, 1, 1, true)
    tip:AddLine("QuestBank's Map key is its own binding (Key Bindings, QuestBank). The game's own map key (M, unless you changed it) always opens the game's map, whatever this says.", 0.6, 0.6, 0.6, true)
    if not (QB.MapPage and QB.MapPage.Available()) then tip:AddLine("Only on the Forever client.", 1, 0.5, 0.3, true) end
  end)
  v.map = button(p, "Game's map", 110)
  v.map:SetPoint("TOPLEFT", LEFT + 4, y0 - 360)
  v.map:SetScript("OnClick", QB.Safe(function() UI.OpenMap() end, "settings: map"))
  v.mapLabel = text(p, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", 250)
  v.mapLabel:SetPoint("LEFT", v.map, "RIGHT", 8, 0)
  v.mapLabel:SetText("Your zone on the game's world map")
  -- QuestBank's quest icons on the maps (Pins.lua, mapIconPct): half the game's size by default; the button cycles
  UI.ICON_SIZES = { { 50, "Half size" }, { 75, "Three quarters" }, { 100, "Game's size" } }
  v.iconSize = button(p, "Half size", 110)
  v.iconSize:SetPoint("TOPLEFT", LEFT + 4, y0 - 388)
  v.iconSize:SetScript("OnClick", QB.Safe(function()
    local set = QB:Settings()
    local i = 1
    for k, o in ipairs(UI.ICON_SIZES) do if o[1] == tonumber(set.mapIconPct) then i = k end end
    set.mapIconPct = UI.ICON_SIZES[i % #UI.ICON_SIZES + 1][1]
    if QB.Pins then QB.Pins:Update() end
    UI:Refresh()
  end, "settings: map icon size"))
  tooltip(v.iconSize, function(tip)
    tip:AddLine("Quest icons' size", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("QuestBank's !, ? and route stops on the world map and the Map page, against the game's own pins. Where a click lands stays the game's size.", 1, 1, 1, true)
  end)
  v.iconLabel = text(p, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", 250)
  v.iconLabel:SetPoint("LEFT", v.iconSize, "RIGHT", 8, 0)
  v.iconLabel:SetText("Quest icons on the maps")
  tooltip(v.map, function(tip)
    tip:AddLine("Game's map", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("The game's own world map on your zone, with QuestBank's route and icons on it.", 1, 1, 1, true)
    tip:AddLine(QB.MapPage and QB.MapPage.KEYS or "Keys for it and for each page: Key Bindings, QuestBank.", 0.6, 0.6, 0.6, true)
  end)
  yl = y0 - 428

  ----------------------------------------------------------------------------------------------------------------
  -- the modules, one heading each: the interact light (left), the camp bar, the timers, the health and mana
  -- numbers, party chat and the contexts (right)
  ----------------------------------------------------------------------------------------------------------------
  -- the light on what your Interact key would use (Glow.lua): its style, and what it lights
  y0 = yl
  head(LEFT, y0, "Interact light", 370)
  v.glowOn = checkRow(p, LEFT, y0 - 24, "Light what my Interact key would use", 340)
  v.glowOn:SetScript("OnClick", function(self) if QB.Glow then QB.Glow.Set(self:GetChecked() and true or false) end; UI:Refresh() end)
  -- the style: QuestBank's sparkles, its soft light, or the game's own highlight alone; the one in use is greyed
  v.glowStyle = {}
  for i, o in ipairs(UI.GLOW_STYLES) do
    local b = button(p, o[2], 84)
    b:SetPoint("TOPLEFT", LEFT + 4 + (i - 1) * 90, y0 - 52)
    b.value = o[1]
    b:SetScript("OnClick", QB.Safe(function(self)
      if QB.Glow then QB.Glow.SetStyle(self.value) else QB:Settings().glow.style = self.value end
      UI:Refresh()
    end, "settings: light style"))
    tooltip(b, function(tip)
      tip:AddLine(o[2], GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine(o[3], 1, 1, 1, true)
    end)
    v.glowStyle[i] = b
  end
  v.glowNpcs = checkRow(p, LEFT + 24, y0 - 80, "NPCs too: quest givers, trainers you can use", 316)
  v.glowNpcs:SetScript("OnClick", function(self) QB:Settings().glow.npcs = self:GetChecked() and true or false; if QB.Glow then QB.Glow.Update() end end)
  v.glowEvery = checkRow(p, LEFT + 24, y0 - 108, "Every other NPC too, in white", 316)
  v.glowEvery:SetScript("OnClick", function(self) QB:Settings().glow.everyNpc = self:GetChecked() and true or false; if QB.Glow then QB.Glow.Update() end end)
  v.glowOther = checkRow(p, LEFT + 24, y0 - 136, "Plain objects too, in white", 316)
  v.glowOther:SetScript("OnClick", function(self) QB:Settings().glow.other = self:GetChecked() and true or false; if QB.Glow then QB.Glow.Update() end end)
  v.glowCombat = checkRow(p, LEFT + 24, y0 - 164, "Keep it on in a fight", 316)
  v.glowCombat:SetScript("OnClick", function(self) QB:Settings().glow.combat = self:GetChecked() and true or false; if QB.Glow then QB.Glow.Update() end end)
  -- the game's health bar over what it lights (the soft-interact nameplate): off unless asked for (Glow.lua)
  v.glowPlates = checkRow(p, LEFT + 24, y0 - 192, "Health bars over what it lights", 316)
  v.glowPlates:SetScript("OnClick", function(self) if QB.Glow then QB.Glow.SetPlates(self:GetChecked() and true or false) end; UI:Refresh() end)
  tooltip(v.glowPlates, function(tip)
    tip:AddLine("Health bars over what it lights", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("The game's full nameplate, with its health bar, on the NPC or object under your Interact key. Off, the light sits on the game's interact icon alone. Switched off, the game's setting goes back as you had it.", 1, 1, 1, true)
  end)
  v.glowHint = para(p, "GameFontNormalSmall", 11, INK_SOFT, 370)
  v.glowHint:SetPoint("TOPLEFT", LEFT, y0 - 220)
  v.glowHint:SetHeight(28)
  v.glowHint:SetText("Gold for a quest object or NPC, green for an herb, orange for ore, blue for a chest. Game's own draws nothing of QuestBank's.")
  -- the game's settings the light changes (Glow.LIST), one row each under a line naming the columns: its name, the
  -- game's own value the light found and the light's. One you set yourself is left as you set it, and its row says
  -- so; one the game would not take back says the game kept its value. The rows this client has, from the top; the
  -- button puts them all back. (The columns: the names to 164 px, the longest 147; the game's own 118 px, for
  -- "Keyboard and mouse", 103; the light's 80 px, for "As you set it", 70; "The game kept its value", 119, spans the
  -- last two)
  v.glowSetHead = text(p, "GameFontNormal", 12, GOLD_SOFT, "LEFT", 370)
  v.glowSetHead:SetPoint("TOPLEFT", LEFT, y0 - 254)
  v.glowSetHead:SetText("The game's settings it changes")
  local GAME_X, GAME_W, LIGHT_X, LIGHT_W = 168, 118, 290, 80
  v.glowRowX, v.glowRowY = LEFT, y0 - 290
  local h1 = text(p, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", GAME_W)
  h1:SetPoint("TOPLEFT", LEFT + GAME_X, y0 - 272)
  h1:SetText("Game's own")
  local h2 = text(p, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", LIGHT_W)
  h2:SetPoint("TOPLEFT", LEFT + LIGHT_X, y0 - 272)
  h2:SetText("The light's")
  -- how a setting became yours, in its tooltip (Glow.State)
  local YOURS = {
    changed = "You changed it while the light was on, so the light leaves it as you set it.",
    login = "It was at a value of yours at login (set while QuestBank was not running, or before the light set its settings), so the light leaves it as you set it.",
    on = "It was at a value of yours when you switched the light on, so the light leaves it as you set it.",
  }
  v.glowRows = {}
  for i, s in ipairs(QB.Glow and QB.Glow.LIST or {}) do
    local r = CreateFrame("Frame", nil, p)
    r:SetSize(370, 18)
    r:SetPoint("TOPLEFT", LEFT, y0 - 290 - (i - 1) * 18)
    r:EnableMouse(true)
    r.s = s
    r.name = text(r, "GameFontNormal", 12, INK, "LEFT", GAME_X - 4)
    r.name:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.name:SetText(s.label)
    r.game = text(r, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", GAME_W)
    r.game:SetPoint("LEFT", r, "LEFT", GAME_X, 0)
    r.light = text(r, "GameFontNormalSmall", 11, INK, "LEFT", LIGHT_W)
    r.light:SetPoint("LEFT", r, "LEFT", LIGHT_X, 0)
    r.note = text(r, "GameFontNormalSmall", 11, { 1, 0.62, 0.3 }, "LEFT", 370 - GAME_X)
    r.note:SetPoint("LEFT", r, "LEFT", GAME_X, 0)
    r.note:SetText("The game kept its value")
    r.note:Hide()
    tooltip(r, function(tip, self)
      local G = QB.Glow
      tip:AddLine(self.s.label, GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine(self.s.where, 1, 1, 1, true)
      if self.kept and G then
        tip:AddLine(string.format("The game kept its value (%s) and would not take back %s, its own before the light. QuestBank tries again at your next login; Restore the game's settings tries now.",
          G.Words(self.s, self.now), G.Words(self.s, self.was)), 1, 0.62, 0.3, true)
      end
      -- what the game's dropdown reads now, from its four settings (Glow.IconsReading): its Default writes nothing
      -- while it reads Default already
      local reads = self.s.icons and G and G.IconsReading and G.IconsReading()
      if reads then
        local on = G.Settings().on == true
        local line = "The game's Interact Icons reads " .. reads .. " now."
        if reads == "Default" then
          line = line .. " Picking Default there changes nothing; None, then Default, sets the game's Default."
            .. (on and " Pick Show All or None and the light leaves the interact icons as you pick them." or "")
        elseif on then
          line = line .. " Pick there and the light leaves the interact icons as you pick them."
        end
        tip:AddLine(line, 0.6, 0.85, 0.6, true)
      end
      if self.yours then
        tip:AddLine((YOURS[self.yours] or YOURS.changed) .. " Switch the light off and on to let it set this again.", 0.6, 0.85, 0.6, true)
      end
      tip:AddLine("The game's setting " .. self.s.cvar .. ".", 0.6, 0.6, 0.6, true)
    end)
    v.glowRows[i] = r
  end
  v.glowRestore = button(p, "Restore the game's settings", 200)
  v.glowRestore:SetPoint("TOPLEFT", LEFT + 4, y0 - 422)
  v.glowRestore:SetScript("OnClick", QB.Safe(function()
    if QB.Glow then QB.Glow.Restore("button") end
    UI:Refresh()
  end, "settings: restore the game's settings"))
  tooltip(v.glowRestore, function(tip)
    tip:AddLine("Restore the game's settings", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Puts each setting above back to the game's own value and switches the interact light off; one you have set yourself stays as you set it. Chat says what went back.", 1, 1, 1, true)
    tip:AddLine("/qb sparkle reset does the same.", 0.6, 0.6, 0.6, true)
  end)
  v.glowSetHint = para(p, "GameFontNormalSmall", 11, INK_SOFT, 370)
  v.glowSetHint:SetPoint("TOPLEFT", LEFT, y0 - 450)
  v.glowSetHint:SetHeight(40)
  yl = y0 - 502

  -- the camp bar (Camp.lua): icons under your character, a switch each; and the banner while a buff is missing
  y0 = yr
  head(RIGHT, y0, "Camp bar")
  local REMIND = { { "food", "Well Fed, and the food that gives it" }, { "fire", "Campfire: Basic Campfire or a kit" }, { "camp", "Camp features I can place, with the cooldown" },
                   { "bag", "Sleeping bag and Well Rested" }, { "quietInstance", "Hidden in dungeons" }, { "buffs", "Missing buffs, a click to cast them" },
                   { "party", "Party members' buffs" },
                   -- (5.4.4: each suggestion of its own)
                   { "sit", "Sit by a campfire near me" }, { "wood", "Fire burned out: where to buy wood" }, { "bagChain", "Where the sleeping bag's quests are" } }
  v.remind = {}
  for i, r in ipairs(REMIND) do
    local row = checkRow(p, RIGHT, y0 - 24 - (i - 1) * 26, r[2], 300)
    row.key = r[1]
    row:SetScript("OnClick", function(self)
      local rm = QB.Camp and QB.Camp.Settings and QB.Camp.Settings() or QB:Settings().remind
      rm[self.key] = self:GetChecked() and true or false
      if QB.Camp then QB.Camp.Refresh() end
    end)
    v.remind[r[1]] = row
  end
  tooltip(v.remind.sit, function(tip)
    tip:AddLine("Sit by a campfire", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Near any fire (yours, another player's, a quest giver's) without Camp Benefits: an icon that sits you down. A minute by it gives Camp Benefits for an hour.", 1, 1, 1, true)
  end)
  tooltip(v.remind.wood, function(tip)
    tip:AddLine("When the fire burns out", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("With no campfire kit, a cook short of Simple Wood or Flint and Tinder is shown the nearest general goods vendor and its minutes. A click puts it on the arrow until you have bought them, then back to your route.", 1, 1, 1, true)
  end)
  tooltip(v.remind.bagChain, function(tip)
    tip:AddLine("The Cozy Sleeping Bag", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("From level 14, with no bag: where its quest chain starts or goes on. A click puts it on the arrow.", 1, 1, 1, true)
  end)
  tooltip(v.remind.buffs, function(tip)
    tip:AddLine("Missing buffs", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("While a buff you can give yourself is missing, a banner above the camp bar shows it: your class's own, Well Fed, a camp feature's. A click casts one or eats the food. Never in a fight; its X hides it for ten minutes.", 1, 1, 1, true)
    tip:AddLine("/qb buffs shows it any time.", 0.6, 0.6, 0.6, true)
  end)
  tooltip(v.remind.party, function(tip)
    tip:AddLine("Party members' buffs", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("In a party (not a raid), the banner also shows each member missing a buff of yours that can be cast on others, with their name. A click casts it on them; out of range it is dimmed.", 1, 1, 1, true)
  end)
  yr = y0 - 24 - #REMIND * 26 - 16

  -- timers (Timer.lua)
  y0 = yr
  head(RIGHT, y0, "Timers")
  v.clockShow = checkRow(p, RIGHT, y0 - 24, "Show the timer strip (drag it; right-click hides it)", 300)
  v.clockShow:SetScript("OnClick", function(self) if QB.Timer then QB.Timer.Set(self:GetChecked() and true or false) end; UI:Refresh() end)
  v.clockLevelMsg = checkRow(p, RIGHT, y0 - 52, "Say how long each level took, at level-up", 300)
  v.clockLevelMsg:SetScript("OnClick", function(self) QB:Settings().clockLevelMsg = self:GetChecked() and true or false end)
  v.clockHint = para(p, "GameFontNormalSmall", 11, INK_SOFT, 330)
  v.clockHint:SetPoint("TOPLEFT", RIGHT, y0 - 78)
  v.clockHint:SetHeight(44)
  v.clockHint:SetText("The strip shows your time at this level, the oldest quest in your log and the hand-in run. Quest tooltips say how long a quest took.")
  yr = y0 - 134

  -- health and mana on the portraits: the game's own Status Text (Options, Interface), always shown, so it works in
  -- a fight where an addon may not read an enemy's health
  y0 = yr
  head(RIGHT, y0, "Health and mana numbers")
  v.statusBtns = {}
  for i, o in ipairs(UI.STATUS_TEXT) do
    local b = button(p, o[2], 84)
    b:SetPoint("TOPLEFT", RIGHT + 4 + (i - 1) * 90, y0 - 26)
    b.value = o[1]
    b:SetScript("OnClick", QB.Safe(function(self) UI.SetStatusText(self.value); UI:Refresh() end, "settings: status text"))
    v.statusBtns[i] = b
  end
  v.statusHint = para(p, "GameFontNormalSmall", 11, INK_SOFT, 330)
  v.statusHint:SetPoint("TOPLEFT", RIGHT, y0 - 56)
  v.statusHint:SetHeight(30)
  v.statusHint:SetText("On your portrait, your target's and your focus's, always shown. The game's own Status Text option.")
  yr = y0 - 98

  -- party chat: two plain lines, off until asked for
  y0 = yr
  head(RIGHT, y0, "Party chat")
  v.sayAccept = checkRow(p, RIGHT, y0 - 24, "Say which quests I pick up", 300)
  v.sayAccept:SetScript("OnClick", function(self) QB:Settings().sayAccept = self:GetChecked() and true or false end)
  v.sayComplete = checkRow(p, RIGHT, y0 - 50, "Say when a quest is complete", 300)
  v.sayComplete:SetScript("OnClick", function(self) QB:Settings().sayComplete = self:GetChecked() and true or false end)
  for key, b in pairs({ accept = v.sayAccept, complete = v.sayComplete }) do
    tooltip(b, function(tip)
      tip:AddLine(key == "accept" and "When you pick a quest up" or "When a quest's objectives are done", GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine("One line in party chat (raid chat in a raid), only while grouped:", 1, 1, 1, true)
      tip:AddLine(string.format(QB.SAY[key], "Kobold Camp Cleanup"), 0.67, 0.67, 1)
    end)
  end
  v.sayHint = para(p, "GameFontNormalSmall", 11, INK_SOFT, 330)
  v.sayHint:SetPoint("TOPLEFT", RIGHT, y0 - 78)
  v.sayHint:SetHeight(30)
  v.sayHint:SetText("Only while you are in a party or raid, as plain lines. Nothing else goes to chat without Post.")
  yr = y0 - 124

  -- where you are decides (QB:Opt): each row is a context, each column a setting; a button cycles inherit, on, off
  y0 = yr
  head(RIGHT, y0, "When you are...")
  local COLS = { { "autoAccept", "Accept" }, { "autoTurnIn", "Hand in" }, { "sayAccept", "Say got" }, { "sayComplete", "Say done" }, { "clockShow", "Strip" } }
  local ROWS = { { "dungeon", "In a dungeon" }, { "pvp", "In a PvP zone" }, { "party", "In a party" }, { "cap", "At a level cap" } }
  v.tri = {}
  for ci, col in ipairs(COLS) do
    local h = text(p, "GameFontNormalSmall", 10, INK_SOFT, "CENTER", 48)
    h:SetPoint("TOPLEFT", RIGHT + 120 + (ci - 1) * 44 - 12, y0 - 24)
    h:SetText(col[2])
  end
  for ri, row in ipairs(ROWS) do
    local y = y0 - 42 - (ri - 1) * 26
    local l = text(p, "GameFontNormal", 12, INK, "LEFT", 118)
    l:SetPoint("TOPLEFT", RIGHT, y - 4)
    l:SetText(row[2])
    for ci, col in ipairs(COLS) do
      local b = button(p, "\226\128\147", 24)
      b:SetPoint("TOPLEFT", RIGHT + 120 + (ci - 1) * 44, y)
      b.ctx, b.key = row[1], col[1]
      b:SetScript("OnClick", QB.Safe(function(self)
        local prof = QB:Settings().profiles
        prof[self.ctx] = prof[self.ctx] or {}
        local cur, nxt = prof[self.ctx][self.key], nil
        if cur == nil then nxt = true elseif cur == true then nxt = false end -- inherit -> on -> off -> inherit
        prof[self.ctx][self.key] = nxt
        if QB.Timer then QB.Timer.Apply() end
        UI:Refresh()
      end, "settings: context"))
      v.tri[row[1] .. "." .. col[1]] = b
    end
  end
  v.ctxText = para(p, "GameFontNormalSmall", 11, INK_SOFT, 330)
  v.ctxText:SetPoint("TOPLEFT", RIGHT, y0 - 152)
  v.ctxText:SetHeight(44)
  yr = y0 - 206

  ----------------------------------------------------------------------------------------------------------------
  -- Data you share: what is noted in play (Game.lua, Loot.lua, Survey.lua), what goes to your party and guild
  -- (Sync.lua), and the version notice
  ----------------------------------------------------------------------------------------------------------------
  y0 = yr
  head(RIGHT, y0, "Data you share")
  subhead(RIGHT, y0 - 26, "Discoveries")
  -- the spells and item tooltips of the Forever client (Game.lua) and who drops what (Loot.lua); quests and NPCs are
  -- always noted. The label names all three: this box is the player's one say over them. Unticking clears what was
  -- noted, ticking takes over ForeverProbe's notes if it is still there
  v.noteGame = checkRow(p, RIGHT, y0 - 46, "Note items, spells and loot, for foreverrank.com", 300)
  v.noteGame:SetScript("OnClick", function(self)
    if QB.Game then QB.Game.SetOn(self:GetChecked() and true or false) end
    UI:Refresh()
  end)
  v.noteGame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Note items, spells and loot", 1, 1, 1)
    GameTooltip:AddLine("Tooltips of the items you loot, carry or see, the spells you know, and which creatures and chests dropped what you loot (by id), with no names in them, so foreverrank.com can list them. Unticking forgets what was noted.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  v.noteGame:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- the quest survey (Survey.lua): QuestBank asks the game about the quests it has no rewards for
  v.survey = checkRow(p, RIGHT, y0 - 72, "Learn quests from the game", 300)
  v.survey:SetScript("OnClick", function(self)
    if QB.Survey then QB.Survey.SetOn(self:GetChecked() and true or false) else QB:Settings().survey = self:GetChecked() and true or false end
    UI:Refresh()
  end)
  v.survey:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Learn quests from the game", 1, 1, 1)
    GameTooltip:AddLine("Out of combat and outside dungeons, QuestBank asks the game about the quests it has no rewards for, two a second, and shows their rewards in the finders and tooltips at once. Once per game build for the account.", nil, nil, nil, true)
    if QB.Survey and QB.Survey.Able() then
      local pr = QB.Survey.Progress()
      GameTooltip:AddLine(string.format("%s of %s quests done on this build, %s with item rewards. /qb survey says more.", QB.Comma(pr.done), QB.Comma(pr.total), QB.Comma(pr.rewards)), 0.6, 0.8, 1, true)
    end
    GameTooltip:Show()
  end)
  v.survey:SetScript("OnLeave", function() GameTooltip:Hide() end)
  v.discText = para(p, "GameFontNormal", 12, INK_SOFT, 330)
  v.discText:SetPoint("TOPLEFT", RIGHT, y0 - 100)
  v.discText:SetHeight(72)
  subhead(RIGHT, y0 - 182, "Sharing and chat")
  v.shareParty = checkRow(p, RIGHT, y0 - 202, "Share my quests with my party", 300)
  v.shareParty:SetScript("OnClick", function(self) QB:Settings().share.party = self:GetChecked() and true or false; UI:Refresh() end)
  v.shareGuild = checkRow(p, RIGHT, y0 - 228, "Share them with my guild", 300)
  v.shareGuild:SetScript("OnClick", function(self) QB:Settings().share.guild = self:GetChecked() and true or false; UI:Refresh() end)
  v.offers = checkRow(p, RIGHT, y0 - 254, "Offer a post during hand-in runs", 300)
  v.offers:SetScript("OnClick", function(self) QB:Settings().post.auto = self:GetChecked() and true or false end)
  v.shareHint = para(p, "GameFontNormalSmall", 11, INK_SOFT, 330)
  v.shareHint:SetPoint("TOPLEFT", RIGHT, y0 - 282)
  v.shareHint:SetHeight(30)
  v.shareHint:SetText("Over the game's addon channel, to QuestBank users only; nothing shows in chat. Posts go out only when you press Post.")
  -- updates: what others on the realm run
  subhead(RIGHT, y0 - 322, "Updates")
  v.verText = para(p, "GameFontNormal", 12, INK_SOFT, 330)
  v.verText:SetPoint("TOPLEFT", RIGHT, y0 - 342)
  v.verText:SetHeight(46)
  v.updates = checkRow(p, RIGHT, y0 - 392, "Tell me when anyone on the realm runs a newer one", 300)
  v.updates:SetScript("OnClick", function(self)
    QB:Settings().updates = self:GetChecked() and true or false
    if QB.Sync and QB.Sync.ApplyVersionSetting then QB.Sync:ApplyVersionSetting() end
  end)
  v.link = button(p, "Copy the download link", 190)
  v.link:SetPoint("TOPLEFT", RIGHT + 4, y0 - 422)
  v.link:SetScript("OnClick", function() UI:CopyLink("QuestBank download page", QB.DOWNLOAD) end)
  yr = y0 - 460

  ----------------------------------------------------------------------------------------------------------------
  -- Banking, last: the mode (found for you, or set by you), the next cap, and how far the suggestions look
  ----------------------------------------------------------------------------------------------------------------
  y0 = yl
  head(LEFT, y0, "Banking", 370)
  v.modeBtns = {}
  for i, m in ipairs({ { "auto", "Auto" }, { "off", "Questing" }, { "on", "Banking" } }) do
    local b = button(p, m[2], 110)
    b:SetPoint("TOPLEFT", LEFT + (i - 1) * 116, y0 - 26)
    b.val = m[1]
    b:SetScript("OnClick", QB.Safe(function(self)
      QB:SetLock(self.val)
      UI:Refresh()
    end, "settings: mode"))
    v.modeBtns[i] = b
  end
  v.modeText = para(p, "GameFontNormal", 12, INK_SOFT, 370)
  v.modeText:SetPoint("TOPLEFT", LEFT, y0 - 56)
  v.modeText:SetHeight(64)
  v.capLabel = text(p, "GameFontNormal", 12, INK, "LEFT", 250)
  v.capLabel:SetPoint("TOPLEFT", LEFT, y0 - 132)
  v.capDown = button(p, "-", 26)
  v.capDown:SetPoint("TOPLEFT", LEFT + 262, y0 - 128)
  v.capUp = button(p, "+", 26)
  v.capUp:SetPoint("TOPLEFT", LEFT + 292, y0 - 128)
  local function moveCap(d)
    local _, p = QB:LockChoice()
    local held, nextCap = QB:Lock()
    local was = QB:Held()
    local base = held or (was and was.level) or QB.state.level
    local cur = nextCap or (was and was.next) or math.min(base + 10, QB.MAXLEVEL)
    local new = math.max(base + 1, math.min(QB.MAXLEVEL, cur + d))
    p.nextCap = new
    if was and not held then was.next = new end -- the rush: the cap it went to
    QB:MarkDirty()
    UI:Refresh()
  end
  v.capDown:SetScript("OnClick", function() moveCap(-1) end)
  v.capUp:SetScript("OnClick", function() moveCap(1) end)
  -- suggestions: how far the Plan page and the swaps look, and where they never look
  subhead(LEFT, y0 - 166, "Suggestions", 370)
  v.rangeAboveLabel = text(p, "GameFontNormal", 12, INK, "LEFT", 210)
  v.rangeAboveLabel:SetPoint("TOPLEFT", LEFT, y0 - 192)
  v.rangeAboveDown = button(p, "-", 26)
  v.rangeAboveDown:SetPoint("TOPLEFT", LEFT + 214, y0 - 188)
  v.rangeAboveUp = button(p, "+", 26)
  v.rangeAboveUp:SetPoint("TOPLEFT", LEFT + 244, y0 - 188)
  v.rangeAuto = button(p, "Auto", 48)
  v.rangeAuto:SetPoint("TOPLEFT", LEFT + 276, y0 - 188)
  v.rangeBelowLabel = text(p, "GameFontNormal", 12, INK, "LEFT", 210)
  v.rangeBelowLabel:SetPoint("TOPLEFT", LEFT, y0 - 218)
  v.rangeBelowDown = button(p, "-", 26)
  v.rangeBelowDown:SetPoint("TOPLEFT", LEFT + 214, y0 - 214)
  v.rangeBelowUp = button(p, "+", 26)
  v.rangeBelowUp:SetPoint("TOPLEFT", LEFT + 244, y0 - 214)
  local function moveRange(key, d)
    local above, below = QB:Range()
    local cur = key == "rangeAbove" and above or below
    QB:Settings()[key] = math.max(0, math.min(40, cur + d))
    UI:Refresh()
  end
  v.rangeAboveDown:SetScript("OnClick", function() moveRange("rangeAbove", -1) end)
  v.rangeAboveUp:SetScript("OnClick", function() moveRange("rangeAbove", 1) end)
  v.rangeBelowDown:SetScript("OnClick", function() moveRange("rangeBelow", -1) end)
  v.rangeBelowUp:SetScript("OnClick", function() moveRange("rangeBelow", 1) end)
  v.rangeAuto:SetScript("OnClick", function()
    local set = QB:Settings()
    set.rangeAbove, set.rangeBelow = "auto", "auto"
    UI:Refresh()
  end)
  tooltip(v.rangeAuto, function(tip)
    tip:AddLine("Auto", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("QuestBank's own window: 12 levels above you while banking (dungeon quests well above you are the big payers), 4 while questing, 7 below.", 0.8, 0.8, 0.8, true)
  end)
  v.skipKal = checkRow(p, LEFT, y0 - 240, "Skip Kalimdor", 110)
  v.skipKal:SetScript("OnClick", function(self) QB:SetSkip(1, self:GetChecked() and true or false) end)
  v.skipEK = checkRow(p, LEFT + 146, y0 - 240, "Skip Eastern Kingdoms", 170)
  v.skipEK:SetScript("OnClick", function(self) QB:SetSkip(0, self:GetChecked() and true or false) end)
  v.skipText = para(p, "GameFontNormalSmall", 11, INK_SOFT, 370)
  v.skipText:SetPoint("TOPLEFT", LEFT, y0 - 268)
  v.skipText:SetHeight(44)
  yl = y0 - 324

  v.contentH = math.max(-yl, -yr) + 20
  v.Refresh = function() UI:RefreshSettingsView(v) end
  return v
end

-- the game's Status Text: off, numbers, percent or both on the unit frames (statusText, statusTextDisplay)
UI.STATUS_TEXT = { { "NONE", "Off" }, { "NUMERIC", "Numbers" }, { "PERCENT", "Percent" }, { "BOTH", "Both" } }
-- the interact light's styles (Glow.lua): the setting, the button, what the tooltip says
UI.GLOW_STYLES = {
  { "sparkle", "Sparkles", "QuestBank's sparkles: a soft glow with small sparkles twinkling and circling round it, in the kind's colour." },
  { "light", "Light", "QuestBank's soft light: a glow under a breathing ring and a slow-turning sparkle." },
  { "game", "Game's own", "Nothing drawn by QuestBank: the game's own highlight on the nameplate, with its health bar and interact icon." },
}
function UI.StatusText()
  local get = C_CVar and C_CVar.GetCVar or GetCVar
  local okA, on = pcall(get, "statusText")
  local okB, how = pcall(get, "statusTextDisplay")
  on, how = okA and QB.Plain(on), okB and QB.Plain(how)
  if on ~= "1" or how == nil or how == "" then return "NONE" end
  return how
end
-- set as the game's Options does: the kind first, then the switch. The bars redraw when the switch changes
-- (CVAR_UPDATE for statusText, TextStatusBar.lua), never for the kind alone, so from one kind shown to another the
-- switch goes off and on again: the same redraw as from Off. Not in a fight, where the bars would redraw as
-- QuestBank on health the game keeps secret
function UI.SetStatusText(value)
  if (QB.Pins and QB.Pins.InCombat and QB.Pins.InCombat()) or (InCombatLockdown and InCombatLockdown()) then
    QB:Print("Not in a fight: set the health and mana numbers after it.")
    return false
  end
  local set = C_CVar and C_CVar.SetCVar or SetCVar
  local get = C_CVar and C_CVar.GetCVar or GetCVar
  pcall(set, "statusTextDisplay", value)
  if value == "NONE" then pcall(set, "statusText", "0"); return true end
  local ok, was = pcall(get, "statusText")
  if ok and QB.Plain(was) == "1" then pcall(set, "statusText", "0") end
  pcall(set, "statusText", "1")
  return true
end

function UI:RefreshSettingsView(v)
  local set = QB:Settings()
  local st = UI.StatusText()
  for _, b in ipairs(v.statusBtns or {}) do
    local on = b.value == st
    b:SetEnabled(not on) -- the one in use is greyed, as the game's own choosers do
    b.on = on
  end
  local choice = QB:LockChoice()
  local vals = { auto = 1, off = 2, on = 3 }
  for i, b in ipairs(v.modeBtns) do b:SetEnabled(vals[choice] ~= i) end
  local mode = QB:Mode()
  local held, nextCap = QB:Lock()
  local was = QB:Held()
  local line
  if mode == "lock" then
    line = string.format("Banking: the game holds you at level %d. Keep finished quests in your log and hand them all in when the cap goes up to %d; the Hand-in Route plans that hour.", held, nextCap)
  elseif mode == "rush" then
    line = "The cap went up: cash your bank in. Your first hand-in starts the run and the route re-plans as you go."
  elseif choice == "off" then
    line = "Questing, chosen by you: hand quests in as you go. No banking, no hand-in hour."
  else
    line = string.format("Questing: the game lets you level to %d, so hand quests in as you go. QuestBank switches to banking by itself when the game holds your level at a cap.", QB.CAP)
  end
  if choice == "auto" then line = "Auto. " .. line end
  v.modeText:SetText(line)
  local banking = mode ~= "quest"
  local capNow = nextCap or (was and was.next)
  v.capLabel:SetText(banking and capNow and string.format("When the cap goes up, it goes to %d", capNow) or "Next cap: only used while banking")
  v.capDown:SetEnabled(banking)
  v.capUp:SetEnabled(banking)
  v.pins:SetChecked(set.pins and true or false)
  v.minimap:SetChecked(not (set.minimap and set.minimap.hide))
  v.arrow:SetChecked(set.arrow and true or false)
  -- the Guide's rows (6.0)
  local gd = type(set.guide) == "table" and set.guide or {}
  v.guideOn:SetChecked(gd.on == true)
  v.guideFrame:SetChecked(gd.frame ~= false)
  v.guideLocked:SetChecked(gd.locked == true)
  v.guideTracker:SetChecked(gd.hideTracker ~= false)
  v.guideScale:SetText(string.format("%d%%", math.floor((tonumber(gd.scale) or 1) * 100 + 0.5)))
  v.guideFrame:SetEnabled(gd.on == true); v.guideLocked:SetEnabled(gd.on == true); v.guideScale:SetEnabled(gd.on == true)
  v.guideTracker:SetEnabled(gd.on == true)
  v.minimapGivers:SetChecked(set.minimapGivers ~= false)
  v.mapLow:SetChecked(set.mapLowLevel == true)
  v.tipProgress:SetChecked(set.tipProgress ~= false)
  local newest = QB.newest
  v.verText:SetText(newest and string.format("You run QuestBank %s. |cff6cdc74%s runs %s: time to update.|r", QB.version, newest.who or "Someone", newest.version)
    or string.format("You run QuestBank %s, the newest anyone on the realm has shown.", QB.version))
  v.updates:SetChecked(set.updates and true or false)
  local nq, nn, nc = QB.Discover.Count()
  -- the box only means something on the Forever client: elsewhere it is greyed out and says so
  local G = QB.Game -- missing only when the files were swapped under a running game
  local forever = G and G.Forever() or false
  v.noteGame:SetEnabled(forever)
  v.noteGame:SetChecked(forever and set.noteGame ~= false)
  v.noteGame.label:SetText(forever and "Note items, spells and loot, for foreverrank.com" or "Note items, spells and loot (Forever client only)")
  local ink = forever and INK or INK_SOFT
  v.noteGame.label:SetTextColor(ink[1], ink[2], ink[3])
  -- the quest survey: the same client only
  local S = QB.Survey
  local asks = S ~= nil and S.Able()
  v.survey:SetEnabled(asks)
  v.survey:SetChecked(asks and set.survey ~= false)
  v.survey.label:SetText(asks and "Learn quests from the game" or "Learn quests from the game (Forever client only)")
  local sink = asks and INK or INK_SOFT
  v.survey.label:SetTextColor(sink[1], sink[2], sink[3])
  -- the map icons: greyed out off Forever, the three kinds greyed out while the icons are off
  local icons = forever and QB.QuestMap ~= nil
  v.mapIcons:SetEnabled(icons)
  v.mapIcons:SetChecked(icons and set.mapIcons ~= false)
  v.mapIcons.label:SetText(icons and "Quest icons on the world map" or "Quest icons on the world map (Forever client only)")
  v.mapIcons.label:SetTextColor(ink[1], ink[2], ink[3])
  for _, key in ipairs({ "mapGive", "mapTurn", "mapObj" }) do
    local live = icons and set.mapIcons ~= false
    local c = live and INK or INK_SOFT
    v[key]:SetEnabled(live)
    v[key]:SetChecked(icons and set[key] ~= false)
    v[key].label:SetTextColor(c[1], c[2], c[3])
  end
  local items = ""
  if G and G.On() then
    items = string.format(", %d items", (G.Count()))
    if QB.Loot then items = items .. string.format(", %d drop sources", (QB.Loot.Count())) end
  end

  v.discText:SetText(string.format("Noted in game so far: %d quests, %d quest NPCs, %d chain steps%s. Forever is still being discovered: upload your QuestBank.lua at foreverrank.com/questbank/ and it goes into the next release for everyone.", nq, nn, nc, items))
  v.offers:SetChecked(set.post.auto and true or false)
  v.shareParty:SetChecked(set.share.party and true or false)
  v.shareGuild:SetChecked(set.share.guild and true or false)
  local above, below, autoA, autoB = QB:Range()
  v.rangeAboveLabel:SetText(string.format("Up to %d levels above me%s", above, autoA and " (auto)" or ""))
  v.rangeBelowLabel:SetText(string.format("Down to %d below%s", below, autoB and " (auto)" or ""))
  v.skipKal:SetChecked(set.skipCont[1] == true)
  v.skipEK:SetChecked(set.skipCont[0] == true)
  local AW = QB.Auto and QB.Auto.WORDS or {}
  local am = QB.Auto and QB.Auto.AcceptMode and (set.autoAccept == true and "worth" or set.autoAccept) or "off"
  v.autoAccept:SetText("Accept for me: " .. (AW[am] or "Off"))
  v.autoOther:SetText("Outside my route: " .. ((QB.Auto and QB.Auto.OTHER or {})[set.autoAcceptOther == "leave" and "leave" or "accept"] or "Accept them"))
  v.autoOther:SetEnabled(am == "worth")
  v.autoTurnIn:SetChecked(set.autoTurnIn == true)
  v.sayAccept:SetChecked(set.sayAccept == true)
  v.sayComplete:SetChecked(set.sayComplete == true)
  local keyName = UI.KEY_NAMES[set.autoKey] or "Shift"
  v.autoKey:SetText(keyName)
  v.acceptHint:SetText(string.format("At an NPC and when a party member shares one; escorts are yours to join in the game's prompt. %s Not trivial or repeatable quests, and not with a full log.",
    set.autoKey == "none" and "No key skips it." or ("Hold " .. keyName .. " to do it by hand.")))
  v.clockShow:SetChecked(set.clock and set.clock.show == true)
  v.minimapPins:SetChecked(set.minimapPins ~= false)
  v.mmExtended:SetChecked(set.mmExtended ~= false)
  v.walkShow:SetChecked(set.walkShow ~= false)
  v.markerStyle:SetText(UI.MARKER_STYLES[set.markerStyle] or UI.MARKER_STYLES.questtrail)
  v.arrowStyle:SetText(UI.ARROW_STYLES[set.arrowStyle] or UI.ARROW_STYLES.questbank)
  local sizeWord = "Half size"
  for _, o in ipairs(UI.ICON_SIZES) do if o[1] == tonumber(set.mapIconPct) then sizeWord = o[2] end end
  v.iconSize:SetText(sizeWord)
  -- QuestBank's map page: greyed out where the client has none (Classic Era)
  local page = QB.MapPage and QB.MapPage.Available()
  v.mapPage:SetEnabled(page)
  v.mapPage:SetChecked(page and set.mapPage ~= false)
  v.mapPage.label:SetText(page and "Map key opens QuestBank's map" or "Map key opens QuestBank's map (Forever client only)")
  local pageInk = page and INK or INK_SOFT
  v.mapPage.label:SetTextColor(pageInk[1], pageInk[2], pageInk[3])
  local gl = QB.Glow and QB.Glow.Settings() or (type(set.glow) == "table" and set.glow or {})
  local style = gl.style or "sparkle"
  v.glowOn:SetChecked(gl.on == true)
  -- the style buttons: the one in use greyed, as the game's own choosers do; all of them while the light is off
  for _, b in ipairs(v.glowStyle) do b:SetEnabled(gl.on == true and b.value ~= style) end
  -- what it lights and when: nothing to choose while the game's own highlight is in use
  local draws = gl.on == true and style ~= "game"
  v.glowNpcs:SetChecked(gl.npcs ~= false)
  v.glowEvery:SetChecked(gl.everyNpc == true)
  v.glowOther:SetChecked(gl.other == true)
  v.glowCombat:SetChecked(gl.combat == true)
  v.glowPlates:SetChecked(gl.plates == true)
  v.glowNpcs:SetEnabled(draws); v.glowEvery:SetEnabled(draws); v.glowOther:SetEnabled(draws); v.glowCombat:SetEnabled(draws)
  v.glowPlates:SetEnabled(gl.on == true)
  -- the game's settings it changes: the game's own value it keeps (the value now while it keeps none) and the light's,
  -- greyed while the light is off; a row of yours says so, and one the game would not take back says it kept its
  -- value. Only the rows this client has, from the top
  local G = QB.Glow
  local held = G and G.Held and G.Held() or false
  local y, nYours, nKept = v.glowRowY, 0, 0
  for _, r in ipairs(v.glowRows or {}) do
    local now, was, how, kept
    if G then now, was, how, kept = G.State(r.s) end
    r:SetShown(now ~= nil)
    r.yours, r.kept, r.now, r.was = how, kept == true, now, was
    if now ~= nil then
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", v.glowRowX, y)
      y = y - 18
      r.note:SetShown(r.kept)
      r.game:SetShown(not r.kept)
      r.light:SetShown(not r.kept)
      r.game:SetText(G.Words(r.s, was or now))
      if r.kept then
        nKept = nKept + 1
      elseif r.yours then
        nYours = nYours + 1
        r.light:SetText("As you set it")
        r.light:SetTextColor(0.6, 0.85, 0.6)
      else
        local ink = gl.on == true and G.Sets(r.s) and INK or INK_SOFT
        r.light:SetText(G.Sets(r.s) and G.Words(r.s, r.s.want) or "Left alone")
        r.light:SetTextColor(ink[1], ink[2], ink[3])
      end
    end
  end
  v.glowRestore:SetEnabled(gl.on == true or held)
  if gl.on == true or held then
    v.glowSetHint:SetText("Restore puts each back to the game's own value and switches the light off; /qb sparkle reset does the same. "
      .. (nKept > 0 and "Where the game kept its value, QuestBank tries again at your next login."
        or nYours > 0 and "The ones marked As you set it are yours: the light leaves them."
        or "One you change in the game's own Settings while the light is on stays as you set it."))
  else
    v.glowSetHint:SetText("The light is off: these are the game's own. Switched on, it sets them and keeps the game's own values to put back.")
  end
  local rm = QB.Camp and QB.Camp.Settings and QB.Camp.Settings() or (type(set.remind) == "table" and set.remind or {})
  for key, row in pairs(v.remind) do row:SetChecked(rm[key] == true) end
  v.clockLevelMsg:SetChecked(set.clockLevelMsg ~= false)
  -- the ready-check's tick and cross, drawn inline: the game's font has no check or cross of its own
  local MARK = { [true] = "|T" .. T.ready .. ":14|t", [false] = "|T" .. T.notready .. ":14|t" }
  for key, b in pairs(v.tri) do
    local ctx, k = key:match("^(%a+)%.(%w+)$")
    local p = set.profiles and set.profiles[ctx]
    local val = p and p[k]
    b:SetText(val == nil and "\226\128\147" or MARK[val])
  end
  local active = QB.Contexts()
  local names = { dungeon = "in a dungeon", pvp = "in a PvP zone", party = "in a party", cap = "at a level cap" }
  local words = {}
  for _, c in ipairs(active) do words[#words + 1] = names[c] end
  v.ctxText:SetText(#words > 0 and ("Right now you are " .. table.concat(words, ", ") .. ": the first row that sets a switch wins, dungeon first.")
    or "Right now none of these applies: the switches above are what counts. The first row that sets a switch wins, dungeon first.")
  local zones = {}
  for _, c in ipairs(QB.Data.CAT) do if set.skipCat[c.key] then zones[#zones + 1] = c.name end end
  table.sort(zones)
  local first = {}
  for i = 1, math.min(3, #zones) do first[i] = zones[i] end
  local more = #zones - #first
  v.skipText:SetText(#zones > 0 and ("Skipped: " .. table.concat(first, ", ") .. (more > 0 and string.format(" and %d more", more) or "")
      .. ". Back on its card on Available, or /qb skip and the name, brings one back; /qb skip lists them all.")
    or "Skip a zone or dungeon with the Skip button on its Plan card, or /qb skip and its name. Skipped places are never suggested; what you already hold there stays.")
  v.scroll:SetContentHeight(v.contentH or 1700) -- here, once the view has its height, so the knob runs exactly what doesn't fit
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
  b:SetScript("OnClick", QB.Safe(function(_, which)
    if which == "RightButton" then UI:Open(3) else UI:Toggle() end
  end, "minimap button"))
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
      tip:AddLine(string.format("%s: %s XP, level %.1f", QB:Banking() and "Banked" or "Ready to hand in", QB.Comma(r.xp), r.level), 1, 1, 1)
    end
    -- (the next stop of the route on screen, the one the arrow and the minimap follow: Target.lua)
    local on = QB.Target and QB.Target.Route() or r
    if on and on.legs and on.legs[1] then tip:AddLine("Next stop: " .. on.legs[1].stop.name, 0.8, 0.8, 0.8) end
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
