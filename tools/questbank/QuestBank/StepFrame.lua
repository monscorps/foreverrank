-- SPDX-License-Identifier: GPL-3.0-or-later
-- The step frame (6.0): the Guide's current step in one line, the next two greyed beneath, a quest-item button when the
-- step needs one, "about 14 min to level 6", the trainer reminder, and the party's steps. Small, movable (a drag;
-- locked in Settings or its menu), in the window's slate. A click on a step opens it in the window; a right-click is
-- its menu: Not now (an hour), Drop (for good), Lock, Scale, Hide, Settings. The welcome (a fresh install) and the
-- 5.x question are cards in the same frame (SF.Ask). Redrawn when the Guide's version, the time line, the
-- reminder or the party's steps changed, twice a second at most; nothing is made per tick. Secure parts (the item
-- button) change only out of a fight. No chat line comes from here.
local _, QB = ...
local SF = {}
QB.StepFrame = SF

local G = QB.Guide
local WIDTH, PAD, ROW = 260, 12, 18 -- (PAD: the text sits inside the 12 px border art)
local SLATE = { 0.055, 0.07, 0.095 }
local INK, INK_SOFT, GOLD = { 0.93, 0.88, 0.78 }, { 0.62, 0.60, 0.54 }, { 1, 0.82, 0.3 }
local TICK = 0.5
local SCALES = { 0.8, 1, 1.2 }
SF.SCALES = SCALES

local function settings() return QB:Settings().guide end
local function fighting() return InCombatLockdown and InCombatLockdown() or false end

local function fs(parent, size, color, width)
  local t = parent:CreateFontString(nil, "OVERLAY")
  local fo = GameFontNormal
  if fo then
    t:SetFontObject(fo)
    local path, _, flags = fo:GetFont()
    if path then t:SetFont(path, size, flags) end
  end
  t:SetTextColor(color[1], color[2], color[3])
  t:SetJustifyH("LEFT")
  t:SetWordWrap(false)
  t:SetWidth(width)
  return t
end

-- a row's words: whole when they fit, else the step's shorter form ("Accept X" without the giver, G.Short), else cut
-- with "..." (Arrow.lua's A.Fit measures the string). A row that does not say it all gets the whole line in its
-- tooltip, so the giver's name is a hover away
local function rowText(t, text, short)
  if QB.Arrow and QB.Arrow.Fit then QB.Arrow.Fit(t, text, short, t:GetWidth() or WIDTH) else t:SetText(text) end
end
local function rowEnter(self)
  local s = G.Steps()[self.i]
  local full = s and G.Text(s) or ""
  if full == "" or self.text:GetText() == full then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(full, INK[1], INK[2], INK[3], true)
  GameTooltip:Show()
end
local function rowLeave() if GameTooltip:GetOwner() then GameTooltip:Hide() end end

local function build()
  local f = CreateFrame("Frame", "QuestBankStep", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(WIDTH, PAD * 2 + ROW * 4)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(SLATE[1], SLATE[2], SLATE[3], 0.92)
    f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.5)
  end
  f:SetScript("OnDragStart", function(self) if not settings().locked then self:StartMoving() end end)
  f:SetScript("OnDragStop", QB.Safe(function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint(1)
    if type(x) == "number" and type(y) == "number" then settings().x, settings().y = x, y end
  end, "step frame"))
  -- three rows: the step now, the two next; each a button for its click and menu
  f.rows = {}
  for i = 1, 3 do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(WIDTH - PAD * 2, ROW)
    b:SetPoint("TOPLEFT", PAD, -PAD - (i - 1) * ROW)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.text = fs(b, i == 1 and 12 or 11, i == 1 and INK or INK_SOFT, WIDTH - PAD * 2)
    b.text:SetPoint("LEFT", 0, 0)
    b.i = i
    b:SetScript("OnClick", QB.Safe(function(self, button)
      local s = G.Steps()[self.i]
      if button == "RightButton" then SF:Menu(s) return end
      if not (s and QB.UI) then return end
      if s.qid then
        QB.UI.scrollToQuest = s.qid
        QB.UI:Open(1)
      else
        QB.UI:Open(3) -- (a travel, train, grind or corpse step: the Route page shows the way)
      end
    end, "step frame"))
    b:SetScript("OnEnter", QB.Safe(rowEnter, "step frame"))
    b:SetScript("OnLeave", rowLeave)
    f.rows[i] = b
  end
  f.now, f.next1, f.next2 = f.rows[1].text, f.rows[2].text, f.rows[3].text
  f.time = fs(f, 10, INK_SOFT, WIDTH - PAD * 2)
  f.time:SetPoint("TOPLEFT", PAD, -PAD - ROW * 3)
  f.remind = fs(f, 10, GOLD, WIDTH - PAD * 2)
  f.remind:SetPoint("TOPLEFT", PAD, -PAD - ROW * 4)
  f.remind:Hide()
  f.members = {}
  f.elapsed = 0
  f:SetScript("OnUpdate", QB.Safe(function(self, dt)
    self.elapsed = self.elapsed + (dt or 0)
    if self.elapsed < TICK then return end
    self.elapsed = 0
    SF.Refresh()
  end, "step frame"))
  f:Hide()
  return f
end

local function place(f)
  local s = settings()
  f:ClearAllPoints()
  if type(s.x) == "number" and type(s.y) == "number" then f:SetPoint("CENTER", UIParent, "CENTER", s.x, s.y)
  else f:SetPoint("TOP", UIParent, "TOP", 0, -140) end
  f:SetScale(s.scale or 1)
end

-- the quest-item button: the game's secure button for the first step's quest item (type item, item:<id>), as
-- Camp.lua's icons; made, set, shown and hidden out of a fight only, else the change waits (SF.pendingItem) for the
-- next refresh out of it. Under UIParent, anchored to the frame's corner: a frame holding a secure button is
-- protected with it, and the step frame must still grow, move and hide in a fight
local function itemButton(f)
  local b = CreateFrame("Button", "QuestBankStepItem", UIParent, "SecureActionButtonTemplate")
  b:SetSize(22, 22)
  b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -PAD + 2)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel((f:GetFrameLevel() or 0) + 5)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b:Hide()
  return b
end
function SF.RefreshItem(s)
  local f = SF.frame
  if not f then return end
  local id, _, tex = G.ItemFor(s)
  local want = id and ("item:" .. id) or nil
  if not f:IsShown() or (f.card and f.card:IsShown()) then want = nil end -- (the frame away or on a card: no button)
  if fighting() then SF.pendingItem = true return end
  SF.pendingItem = nil
  if want and not f.item then f.item = itemButton(f) end
  local b = f.item
  if not b then return end
  if want then
    if b:GetAttribute("item") ~= want then b:SetAttribute("type", "item"); b:SetAttribute("item", want) end
    if tex then b.icon:SetTexture(tex) end
    if not b:IsShown() then b:Show() end
  elseif b:IsShown() then
    b:Hide()
  end
end

-- the fight over (PLAYER_REGEN_ENABLED, from Core.lua's frame): a change that waited goes through now. The frame
-- shown: its next refresh does it all; hidden (Hide in a fight, the Guide turned off): its OnUpdate never runs, so the
-- button would stand on screen for good without this
function SF.OnRegen()
  if not SF.pendingItem or fighting() then return end
  local f = SF.frame
  if f and f:IsShown() and not (f.card and f.card:IsShown()) then
    lastVer = -1
    SF.Refresh()
  else
    SF.RefreshItem(nil)
  end
end

-- the reward window's pick (G.reward), marked with QuestBank's own glow (Pins.Glow, the game's quest-POI glow) over
-- the game's button (QuestInfoFrame.rewardsFrame.RewardButtons[index], QuestInfo.lua); never the button itself
function SF.MarkReward()
  local r = G.reward
  local rf = QuestInfoFrame and QuestInfoFrame.rewardsFrame
  local buttons = rf and rf.RewardButtons
  local b = r and buttons and buttons[r.index]
  if not b then
    if SF.mark and SF.mark:IsShown() then SF.mark:Hide() end
    return
  end
  if not SF.mark then
    SF.mark = CreateFrame("Frame", nil, UIParent)
    SF.mark:SetFrameStrata("HIGH")
    SF.mark.kind = { glow = 170 }
    if QB.Pins and QB.Pins.Glow then QB.Pins.Glow(SF.mark, GOLD) end
  end
  SF.mark:ClearAllPoints()
  SF.mark:SetPoint("TOPLEFT", b, "TOPLEFT", -4, 4)
  SF.mark:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 4, -4)
  SF.mark:Show()
end

local lastVer, lastTime, lastRemind, lastMembers = -1, nil, false, ""
-- the lines, when something changed (and the item button, once a fight is over)
function SF.Refresh()
  local f = SF.frame
  if not (f and f:IsShown()) then return end
  if f.card and f.card:IsShown() then SF.RefreshItem(nil) return end
  if SF.pendingItem and not fighting() then lastVer = -1 end
  local steps = G.Steps()
  local text = G.TimeToLevel()
  local remind = (G.reminder and GetTime and GetTime() < G.reminder) and true or false
  local members = G.MemberSteps()
  local mkey = ""
  for _, m in ipairs(members) do mkey = mkey .. m.name .. "=" .. m.text .. ";" end
  if G.ver == lastVer and text == lastTime and remind == lastRemind and mkey == lastMembers then return end
  lastVer, lastTime, lastRemind, lastMembers = G.ver, text, remind, mkey
  -- the first row makes room for the item button only while one shows (in a fight, as the button stands)
  local itemUp = fighting() and (f.item ~= nil and f.item:IsShown()) or (not fighting() and G.ItemFor(steps[1]) ~= nil)
  f.rows[1].text:SetWidth(WIDTH - PAD * 2 - (itemUp and 30 or 0))
  f.rows[1].text.qbText = nil -- (fitted again at the new width)
  for i = 1, 3 do
    local s = steps[i]
    rowText(f.rows[i].text, s and G.Text(s) or (i == 1 and "Nothing to do: /qb" or ""), s and G.Short(s) or nil)
    f.rows[i]:SetShown(i == 1 or s ~= nil)
  end
  f.time:SetText(text or "")
  f.remind:SetText(remind and "New spells at your class trainer" or "")
  f.remind:SetShown(remind)
  local y = PAD + ROW * 3 + (text and ROW or 0)
  if remind then
    f.remind:ClearAllPoints()
    f.remind:SetPoint("TOPLEFT", PAD, -y)
    y = y + ROW
  end
  for i, m in ipairs(members) do
    local t = f.members[i]
    if not t then t = fs(f, 10, INK_SOFT, WIDTH - PAD * 2); f.members[i] = t end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", PAD, -y)
    local name = (QB.Sync and QB.Sync.ColorName) and QB.Sync.ColorName(m.name, m.class) or m.name
    t:SetText(name .. ": " .. m.text)
    t:Show()
    y = y + ROW
  end
  for i = #members + 1, #f.members do f.members[i]:Hide() end
  f:SetHeight(y + PAD)
  SF.RefreshItem(steps[1])
  SF.MarkReward()
end

-- the welcome (a fresh install: the auto choice, the outside-route choice, hand in for me) and the 5.x question
-- ("Let QuestBank guide you?"), as a card in the frame over the rows. Done, Yes or Not now is the only way out; the
-- one chat line (QB.WELCOME) comes after Done, and nothing is said while choosing
local ACCEPT_ORDER = { "off", "route", "worth" }
local CARD_W = WIDTH - PAD * 2
local function cardButton(parent, label, width)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(label)
  return b
end
local function buildCard(f)
  local card = CreateFrame("Frame", nil, f)
  card:SetPoint("TOPLEFT", PAD, -PAD)
  card:SetSize(CARD_W, 140)
  card.title = fs(card, 12, INK, CARD_W)
  card.title:SetPoint("TOPLEFT", 0, 0)
  card.title:SetWordWrap(true)
  -- the welcome's rows: the title's two lines, then a button, a button, the check, Done
  card.accept = cardButton(card, "", CARD_W)
  card.accept:SetPoint("TOPLEFT", 0, -36)
  card.other = cardButton(card, "", CARD_W)
  card.other:SetPoint("TOPLEFT", 0, -62)
  card.turnIn = CreateFrame("CheckButton", nil, card, "UICheckButtonTemplate")
  card.turnIn:SetSize(24, 24)
  card.turnIn:SetPoint("TOPLEFT", -4, -88)
  card.turnIn.label = fs(card, 11, INK, CARD_W - 28)
  card.turnIn.label:SetPoint("LEFT", card.turnIn, "RIGHT", 2, 0)
  card.turnIn.label:SetText("Hand in finished quests for me")
  card.done = cardButton(card, "Done", 90)
  card.done:SetPoint("TOPLEFT", 0, -118)
  -- the question's: the title's one line, then Yes and Not now
  card.yes = cardButton(card, "Yes", 90)
  card.yes:SetPoint("TOPLEFT", 0, -24)
  card.no = cardButton(card, "Not now", 110)
  card.no:SetPoint("TOPLEFT", 100, -24)
  local function words()
    local s = QB:Settings()
    card.accept:SetText("Accept for me: " .. (QB.Auto.WORDS[s.autoAccept] or QB.Auto.WORDS.off))
    card.other:SetText("Outside my route: " .. (QB.Auto.OTHER[s.autoAcceptOther] or QB.Auto.OTHER.accept))
    card.other:SetEnabled(s.autoAccept == "worth")
    card.turnIn:SetChecked(s.autoTurnIn == true)
  end
  card.Words = words
  card.accept:SetScript("OnClick", QB.Safe(function()
    local s = QB:Settings()
    local i = 1
    for k, v in ipairs(ACCEPT_ORDER) do if v == s.autoAccept then i = k end end
    s.autoAccept = ACCEPT_ORDER[i % #ACCEPT_ORDER + 1]
    words()
  end, "welcome"))
  card.other:SetScript("OnClick", QB.Safe(function()
    local s = QB:Settings()
    s.autoAcceptOther = s.autoAcceptOther == "leave" and "accept" or "leave"
    words()
  end, "welcome"))
  card.turnIn:SetScript("OnClick", QB.Safe(function(self) QB:Settings().autoTurnIn = self:GetChecked() and true or false end, "welcome"))
  card.done:SetScript("OnClick", QB.Safe(function()
    QB:Settings().welcome = nil
    QB:Print(QB.WELCOME)
    SF.Apply() -- (no welcome waits: the card gives way to the rows)
  end, "welcome"))
  card.yes:SetScript("OnClick", QB.Safe(function()
    local s = QB:Settings()
    s.guide.on, s.guide.frame, s.arrow = true, true, true
    s.minimapGivers, s.tipProgress = true, true -- (6.0's two switches, kept off for a 5.x save until now: QB.Migrate600)
    if QB.Arrow then QB.Arrow:Set(true) end
    if QB.Mini and QB.Mini.Invalidate then QB.Mini.Invalidate() end
    s.welcome = "fresh"
    QB:MarkDirty()
    SF.Ask("fresh")
  end, "welcome"))
  card.no:SetScript("OnClick", QB.Safe(function()
    QB:Settings().welcome = nil
    SF.Apply() -- (the Guide stays off: the frame hides)
  end, "welcome"))
  card:Hide()
  return card
end

-- kind: "fresh" (the auto choice) or "ask" (Let QuestBank guide you?); the rows step aside while the card shows
function SF.Ask(kind)
  local f = SF.frame
  if not f then return end
  f.card = f.card or buildCard(f)
  local card = f.card
  for i = 1, 3 do f.rows[i]:Hide() end
  f.time:Hide(); f.remind:Hide()
  for _, t in ipairs(f.members) do t:Hide() end
  if kind == "ask" then
    card.title:SetText("Let QuestBank guide you?")
    card.accept:Hide(); card.other:Hide(); card.turnIn:Hide(); card.turnIn.label:Hide(); card.done:Hide()
    card.yes:Show(); card.no:Show()
    f:SetHeight(PAD * 2 + 48)
  else
    card.title:SetText("QuestBank guides you from here. At quest givers:")
    card.yes:Hide(); card.no:Hide()
    card.accept:Show(); card.other:Show(); card.turnIn:Show(); card.turnIn.label:Show(); card.done:Show()
    card.Words()
    f:SetHeight(PAD * 2 + 140)
  end
  card:Show()
  f:Show()
  SF.RefreshItem(nil) -- (no item button over a card)
end

-- a welcome waiting (QB:Settings().welcome) is asked as the frame is applied; answered, the rows come back
function SF.AskPending()
  local w = QB:Settings().welcome
  local f = SF.frame
  if not f then return end
  if w == "fresh" or w == "ask" then
    SF.Ask(w)
  elseif f.card and f.card:IsShown() then
    f.card:Hide()
    for i = 1, 3 do f.rows[i]:Show() end
    f.time:Show()
    lastVer = -1
    SF.Refresh()
  end
end

-- shown while the Guide and the frame are on, or a welcome waits
function SF.Apply()
  local s = settings()
  local want = (s.on and s.frame) or QB:Settings().welcome ~= nil
  if want and not SF.frame then SF.frame = build() end
  local f = SF.frame
  if not f then return end
  place(f)
  f.__dragOff = s.locked and true or nil -- (the drag script reads the setting; the harness reads this flag)
  f:SetShown(want and true or false)
  lastVer = -1
  if want then SF.Refresh() else SF.RefreshItem(nil) end
  if SF.AskPending then SF.AskPending() end
end

function SF.SetScale(sc)
  settings().scale = sc
  if SF.frame then SF.frame:SetScale(sc) end
end

function SF:Menu(s)
  if not QB.UI then return end
  local items = {}
  local set = settings()
  if s and s.qid then
    local q = QB.Quest.Get(s.qid)
    local name = q and QB.UI.Short(q.name, 24) or ("quest " .. s.qid)
    items[#items + 1] = { "Not now", function() G.Skip(s.qid, "later") end }
    items[#items + 1] = { "Drop " .. name, function() G.Skip(s.qid, "drop") end }
  end
  items[#items + 1] = { set.locked and "Unlock" or "Lock", function() set.locked = not set.locked; SF.Apply() end }
  for _, sc in ipairs(SCALES) do
    items[#items + 1] = { string.format("Scale: %d%%%s", sc * 100, (set.scale or 1) == sc and "  (now)" or ""), function() SF.SetScale(sc) end }
  end
  items[#items + 1] = { "Hide (Settings brings it back)", function() set.frame = false; SF.Apply() end }
  items[#items + 1] = { "Settings", function() QB.UI:Open(5) end }
  QB.UI:ShowMenu("The next step", items)
end

function SF:Init()
  SF.Apply()
end
