-- SPDX-License-Identifier: GPL-3.0-or-later
-- The step frame (6.0): the Guide's current step in one line, the next two greyed beneath, a quest-item button when the
-- step needs one, "about 14 min to level 6", the trainer reminder, and the party's steps. Small, movable (a drag;
-- locked in Settings or its menu), in the window's slate. A click on a step opens it in the window; a right-click is
-- its menu: Not now (an hour), Drop (for good), Lock, Scale, Hide, Settings. The welcome (a fresh install) and the
-- 5.x question are cards in the same frame (SF.Ask, later). Redrawn when the Guide's version, the time line, the
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

-- a row's words: whole when they fit, else cut with "..." (Arrow.lua's A.Fit measures the string)
local function rowText(t, text)
  if QB.Arrow and QB.Arrow.Fit then QB.Arrow.Fit(t, text, nil, t:GetWidth() or WIDTH) else t:SetText(text) end
end

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
    b.text = fs(b, i == 1 and 12 or 11, i == 1 and INK or INK_SOFT, WIDTH - PAD * 2 - (i == 1 and 30 or 0))
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

local lastVer, lastTime, lastRemind, lastMembers = -1, nil, false, ""
-- the lines, when something changed
function SF.Refresh()
  local f = SF.frame
  if not (f and f:IsShown()) then return end
  if f.card and f.card:IsShown() then return end
  local steps = G.Steps()
  local text = G.TimeToLevel()
  local remind = (G.reminder and GetTime and GetTime() < G.reminder) and true or false
  local members = G.MemberSteps()
  local mkey = ""
  for _, m in ipairs(members) do mkey = mkey .. m.name .. "=" .. m.text .. ";" end
  if G.ver == lastVer and text == lastTime and remind == lastRemind and mkey == lastMembers then return end
  lastVer, lastTime, lastRemind, lastMembers = G.ver, text, remind, mkey
  for i = 1, 3 do
    local s = steps[i]
    rowText(f.rows[i].text, s and G.Text(s) or (i == 1 and "Nothing to do: /qb" or ""))
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
  if SF.RefreshItem then SF.RefreshItem(steps[1]) end
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
  if want then SF.Refresh() end
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
