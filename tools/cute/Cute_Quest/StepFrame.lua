-- SPDX-License-Identifier: GPL-3.0-or-later
-- The step frame (6.0): the Guide's current step, the next two greyed beneath, a quest-item button when the step needs
-- one, "about 14 min to level 6", the trainer reminder, and the party's steps. Each step says where (the launch round):
-- the kind's game icon, its name, who and where ("Mathrengyl Bearwalker - Darnassus") and the minutes to get there for
-- the step now; the next two, name and place on one line with the minutes where a new trip starts; every row's tooltip
-- the whole step, the NPC and place, minutes and XP. Small, movable (a drag;
-- locked in Settings or its menu), in the window's slate. A click on a step opens it in the window; a right-click is
-- its menu: Not now (an hour), Drop (for good), Lock, Scale, Hide, Settings. The welcome (a fresh install) and the
-- 5.x question are cards in the same frame (SF.Ask). Redrawn when the Guide's version, the time line, the
-- reminder or the party's steps changed, twice a second at most; nothing is made per tick. Secure parts (the item
-- button) change only out of a fight. No chat line comes from here.
local _, QB = ...
if QB.dormant then return end
local SF = {}
QB.StepFrame = SF

local G = QB.Guide
local WIDTH, PAD, ROW = 260, 12, 18 -- (PAD: the text sits inside the 12 px border art)
-- the step now's row: its name, then who and where 20 px down (clear of the item button at the frame's top right);
-- the text starts after the icon (TEXT_X) and leaves the minutes their column (MINS_W)
local ROW1, TEXT_X, MINS_W = 34, 20, 44
local INNER = WIDTH - PAD * 2
local SLATE = { 0.055, 0.07, 0.095 }
local LOOK = { INK = { 0.93, 0.88, 0.78 }, SOFT = { 0.62, 0.60, 0.54 }, GOLD = { 1, 0.82, 0.3 } }
-- a host's skin (QB.Skin: Cute_Quest sets one before the login; QuestBank none): its font and its colours for
-- the frame's INK, SOFT and GOLD (the skin's ACCENT), and its backdrop
local function tone(key)
  local sk = QB.Skin
  if sk then return (key == "GOLD" and sk.ACCENT) or sk[key] or LOOK[key] end
  return LOOK[key]
end
local TICK = 0.5
local SCALES = { 0.8, 1, 1.2 }
SF.SCALES = SCALES

local function settings() return QB:Settings().guide end
local function fighting() return InCombatLockdown and InCombatLockdown() or false end
local trackerOut, trackerHooked, trackerWait = false, false, false -- (the game's quest tracker: SF.Tracker)
-- the first time the tracker goes out of sight the frame says where it went, for NOTE_S seconds, once for good
-- (guide.trackerTold); its menu brings the tracker back
local NOTE_S, NOTE_H = 60, 24
local TRACKER_NOTE = "The game's quest tracker is hidden while this frame shows. Right-click here to show it."
SF.noteUntil, SF.notePending = nil, nil -- (pending: told when the steps next show, not under a welcome card)

local function fs(parent, size, key, width)
  local t = parent:CreateFontString(nil, "OVERLAY")
  local fo = GameFontNormal
  local sk = QB.Skin
  if sk and sk.font then
    if fo then t:SetFontObject(fo) end
    t:SetFont(sk.font, size, "")
  elseif fo then
    t:SetFontObject(fo)
    local path, _, flags = fo:GetFont()
    if path then t:SetFont(path, size, flags) end
  end
  local color = tone(key)
  t:SetTextColor(color[1], color[2], color[3])
  t:SetJustifyH("LEFT")
  t:SetWordWrap(false)
  t:SetWidth(width)
  return t
end

-- a row's words: whole when they fit, else the step's shorter form, else cut with "..." (Arrow.lua's A.Fit measures
-- the string)
local function rowText(t, text, short)
  t.qbA, t.qbB = nil, nil
  if QB.Arrow and QB.Arrow.Fit then QB.Arrow.Fit(t, text, short, t:GetWidth() or WIDTH) else t:SetText(text) end
end
-- a next step's two parts on one line, "name - place": whole when they fit, else the name cut with "..." so the place
-- stays (it tells apart the steps of a chain that share one name), else both cut. Set again only when they change
local function rowTwo(t, a, b)
  if not b or b == "" then return rowText(t, a, nil) end
  if t.qbA == a and t.qbB == b then return end
  t.qbA, t.qbB, t.qbText, t.qbShort = a, b, nil, nil
  local width = t:GetWidth() or WIDTH
  local tail = " - " .. b
  t:SetText(a .. tail)
  if (t:GetStringWidth() or 0) <= width then return end
  t:SetText(tail)
  if width - (t:GetStringWidth() or 0) < 40 then
    -- (a place out in a zone, "Stonetalon Mountains (59, 62)": the zone alone here; the tooltip has the spot)
    local zone = b:gsub(" %(%d+, %d+%)$", "")
    if zone ~= b then tail = " - " .. zone; t:SetText(tail) end
  end
  if width - (t:GetStringWidth() or 0) < 40 then
    local whole = a .. tail
    t.qbText = nil
    if QB.Arrow and QB.Arrow.Fit then QB.Arrow.Fit(t, whole, nil, width) else t:SetText(whole) end
    t.qbA, t.qbB = a, b
    return
  end
  local cut, dots = a, ""
  repeat
    t:SetText(cut .. dots .. tail)
    if (t:GetStringWidth() or 0) <= width then return end
    cut, dots = cut:gsub("[%z\1-\127\194-\244][\128-\191]*$", ""), "..." -- one letter off the end (a whole UTF-8 one)
  until #cut <= 1
end

-- the kind's game icon (the atlas where the client has it, else a file): the pick-up's !, the hand-in's ?, the
-- objective's cursor (QuestMap.lua's QM.ART), the travel step's own (the arrow's), a tombstone for your corpse
local ICON = { accept = { "QuestNormal", "questAvail" }, handin = { "QuestTurnin", "questActive" }, reward = { "QuestTurnin", "questActive" },
               corpse = { "Navigation-Tombstone-Icon", "unknown" }, train = { nil, "book" }, travel = { "FlightPath", "map" } }
local function stepIcon(tex, s)
  local atlas, file
  local QM = QB.QuestMap
  if s.kind == "objective" then
    local art = QM and QM.ART and (s.obj == "d" and s.dungeon and QM.ART.dungeon or QM.ART[s.obj] or QM.ART.u)
    if art then atlas, file = art.atlas, art.file end
  elseif s.kind == "grind" then
    local art = QM and QM.ART and QM.ART.k
    if art then atlas, file = art.atlas, art.file end
  elseif s.kind == "travel" and (s.atlas or s.icon) then
    atlas, file = s.atlas, s.icon
  else
    local ic = ICON[s.kind]
    if ic then atlas, file = ic[1], QB.Data.TEX[ic[2]] end
  end
  if tex.qbAtlas ~= atlas or tex.qbFile ~= file then
    tex.qbAtlas, tex.qbFile = atlas, file
    QB.Art(tex, atlas, file or QB.Data.TEX.questGeneric)
  end
  tex:Show()
end

-- the minutes to the step now: the arrow's own count while it leads to the same place (from where you stand, as you
-- go), else the plan's for the step's leg (G.Mins)
local function minsNow(s)
  local A = QB.Arrow
  local g, t, f = A and A.g, A and A.t, A and A.frame
  if g and g.eta and t and f and f:IsShown() and s.wx and t.wx and t.c == s.c and (t.wx - s.wx) ^ 2 + (t.wy - s.wy) ^ 2 < 900 then
    return math.floor(g.eta + 0.5)
  end
  return G.Mins(s)
end
SF.MinsNow = minsNow

-- every row's tooltip: the whole step, who and where (the NPC's spot on its map), the minutes and the XP, the clicks
local function rowEnter(self)
  local steps = G.Steps()
  local s = steps[self.i]
  if not s then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  local INK, SOFT = tone("INK"), tone("SOFT")
  GameTooltip:AddLine(G.Text(s), INK[1], INK[2], INK[3], true)
  local where = G.Where(s)
  if where then
    GameTooltip:AddLine(where .. ((s.npc and s.x and s.y) and string.format(" (%.0f, %.0f)", s.x, s.y) or ""), INK[1], INK[2], INK[3], true)
  end
  local mins = self.i == 1 and minsNow(s) or (s.mins and s.mins >= 0.5 and math.floor(s.mins + 0.5)) or nil
  local xp = s.qid and QB:Value(s.qid)
  if mins or xp then
    GameTooltip:AddDoubleLine(mins and string.format("about %d min there", mins) or " ", xp and (QB.Comma(xp) .. " XP") or "", SOFT[1], SOFT[2], SOFT[3], SOFT[1], SOFT[2], SOFT[3])
  end
  GameTooltip:AddLine(s.qid and "Click: the quest. Right-click: Not now, Drop, the game's quest tracker and more."
    or "Click: the way there. Right-click: the game's quest tracker and more.", SOFT[1], SOFT[2], SOFT[3], true)
  GameTooltip:Show()
end
local function rowLeave() if GameTooltip:GetOwner() then GameTooltip:Hide() end end

local function build()
  local f = CreateFrame("Frame", "QuestBankStep", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(WIDTH, PAD * 2 + ROW1 + ROW * 3)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  local sk = QB.Skin
  if sk and sk.Backdrop then
    sk.Backdrop(f)
  elseif f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(SLATE[1], SLATE[2], SLATE[3], 0.92)
    local gold = tone("GOLD")
    f:SetBackdropBorderColor(gold[1], gold[2], gold[3], 0.5)
  end
  f:SetScript("OnDragStart", function(self) if not settings().locked then self:StartMoving() end end)
  f:SetScript("OnDragStop", QB.Safe(function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint(1)
    if type(x) == "number" and type(y) == "number" then settings().x, settings().y = x, y end
  end, "step frame"))
  -- three rows: the step now (its name, then who and where with the minutes), the two next (name and place, the
  -- minutes where a new trip starts); each a button for its click and menu, with the kind's icon
  f.rows = {}
  for i = 1, 3 do
    local b = CreateFrame("Button", nil, f)
    local now = i == 1
    b:SetSize(INNER, now and ROW1 or ROW)
    b:SetPoint("TOPLEFT", PAD, -PAD - (now and 0 or ROW1 + (i - 2) * ROW))
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(now and 16 or 14, now and 16 or 14)
    b.icon:SetPoint("TOPLEFT", now and 0 or 1, now and 0 or -2)
    b.icon:Hide()
    b.text = fs(b, now and 12 or 11, now and "INK" or "SOFT", now and (INNER - TEXT_X) or (INNER - TEXT_X - MINS_W))
    b.text:SetPoint("TOPLEFT", TEXT_X, now and -1 or -2)
    b.mins = fs(b, 10, "SOFT", MINS_W)
    b.mins:SetJustifyH("RIGHT")
    b.mins:SetPoint("TOPRIGHT", 0, now and -21 or -3)
    if now then
      b.where = fs(b, 10, "SOFT", INNER - TEXT_X - MINS_W)
      b.where:SetPoint("TOPLEFT", TEXT_X, -21)
    end
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
  f.time = fs(f, 10, "SOFT", WIDTH - PAD * 2)
  f.time:SetPoint("TOPLEFT", PAD, -PAD - ROW1 - ROW * 2)
  f.remind = fs(f, 10, "GOLD", WIDTH - PAD * 2)
  f.remind:SetPoint("TOPLEFT", PAD, -PAD - ROW * 4)
  f.remind:Hide()
  -- the once-ever note where the game's quest tracker went (SF.Tracker): two lines, wrapped
  f.note = fs(f, 10, "SOFT", WIDTH - PAD * 2)
  f.note:SetWordWrap(true)
  f.note:SetHeight(NOTE_H)
  f.note:SetText(TRACKER_NOTE)
  f.note:Hide()
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

-- the left edge of the game's quest tracker's header, in UIParent's units: its minimise button sits at the header's
-- right end. Not laid out yet: where the game puts it (EditModeUtil:GetRightContainerAnchor: the screen's right edge
-- less 5 px and the right action bars, here two of them; the header 260 px wide)
local function trackerLeft(W)
  local t = ObjectiveTrackerFrame
  local h = type(t) == "table" and t.Header or nil
  if type(h) == "table" and type(h.GetLeft) == "function" then
    local ok, l = pcall(h.GetLeft, h)
    l = ok and QB.Plain(l) or nil
    if type(l) == "number" then
      local ok2, k = pcall(h.GetEffectiveScale, h)
      k = ok2 and QB.Plain(k) or 1
      local u = UIParent:GetEffectiveScale() or 1
      return l * (type(k) == "number" and k or 1) / u
    end
  end
  return W - 5 - 90 - 260
end
SF.TrackerLeft = trackerLeft

-- where the frame stands: where it was dragged to, else the top's middle, TOP_Y down whatever its scale, moved left as
-- far as it takes to stay 16 px clear of the tracker's header (6.1.1: "it won't let me minimise my quest list": on a
-- narrow screen of UI or with right action bars, the frame there, in a strata above the tracker's, reached over the
-- minimise button). TOP_Y: the game's error text (UIErrorsFrame, Blizzard_UIErrorsFrame: TOP 0 -122, 512 x 60) ends
-- 182 px down, so "Not enough rage" never lands on the steps; 6.1 stood at 140 (at its scale), under that text and under
-- the arrow. The arrow stands under the frame (Arrow.lua, A.Place: SF.Below)
local TOP_Y = 190
SF.TOP_Y = TOP_Y
local function place(f)
  local s = settings()
  local sc = s.scale or 1
  f:ClearAllPoints()
  f:SetScale(sc)
  if type(s.x) == "number" and type(s.y) == "number" then f:SetPoint("CENTER", UIParent, "CENTER", s.x, s.y) return end
  local W = UIParent:GetWidth() or 1920
  local over = W / 2 + WIDTH * sc / 2 - (trackerLeft(W) - 16)
  f.qbX = over > 0 and -over or 0 -- (its middle across from the screen's, in UIParent's units: SF.Below)
  f:SetPoint("TOP", UIParent, "TOP", f.qbX / sc, -TOP_Y / sc)
end

-- where the frame ends at its default place, for the arrow under it: its middle across from the screen's middle and
-- its bottom down from the screen's top, in UIParent's units; nil while it is away or stands where it was dragged
function SF.Below()
  local f = SF.frame
  local s = settings()
  if not (f and f:IsShown()) or (type(s.x) == "number" and type(s.y) == "number") then return nil end
  return f.qbX or 0, TOP_Y + (f:GetHeight() or 0) * (f:GetScale() or 1)
end
-- the arrow placed again (its default place follows the frame's height, scale and showing)
local function arrowFollows() if QB.Arrow and QB.Arrow.Place then QB.Arrow.Place() end end

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
  b:SetScale(settings().scale or 1) -- (under UIParent, the frame's scale does not reach it: SF.SetScale keeps them equal)
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
  local sc = settings().scale or 1
  if b:GetScale() ~= sc then b:SetScale(sc) end -- (a scale chosen in a fight waited here)
  if want then
    if b:GetAttribute("item") ~= want then b:SetAttribute("type", "item"); b:SetAttribute("item", want) end
    if tex then b.icon:SetTexture(tex) end
    if not b:IsShown() then b:Show() end
  elseif b:IsShown() then
    b:Hide()
  end
end

-- what the lines were last drawn from (SF.Refresh); -1: draw them again
local lastVer, lastTime, lastRemind, lastMembers, lastNote, lastMins = -1, nil, false, -1, false, nil

-- the fight over (PLAYER_REGEN_ENABLED, from Core.lua's frame): a change that waited goes through now. The frame
-- shown: its next refresh does it all; hidden (Hide in a fight, the Guide turned off): its OnUpdate never runs, so the
-- button would stand on screen for good without this
function SF.OnRegen()
  if trackerWait and not fighting() then SF.Tracker() end
  if not SF.pendingItem or fighting() then return end
  local f = SF.frame
  if f and f:IsShown() and not (f.card and f.card:IsShown()) then
    lastVer = -1
    SF.Refresh()
  else
    SF.RefreshItem(nil)
  end
end

-- the reward window's pick (G.reward), marked as QuestBank's own and never as the game's: a thin outline in the frame's
-- ink round the item's icon, inside the window's reward frame (it scrolls and clips with it), nothing over the item's
-- name and nothing gold or additive (the game's own choice is a gold glow over the whole button, QuestInfoItemHighlight);
-- and one line beside the Complete Quest button, whose pick it is and why: "QuestBank's pick: +4 Intellect, +2 Stamina"
-- (the item's stats, the class's own first: C_Item.GetItemStats), else its item level. A first choice for want of a
-- pick (G.reward.pick false: nothing known fits, or the game had not sent the items) is grey, thinner, and says so.
-- (6.1 drew the map pins' round additive glow, 170 px of gold on a HIGH frame: it read as the game's own selection
-- and washed the name out.) The button itself is never touched
local STAT_WORD = { STRENGTH = "Strength", AGILITY = "Agility", STAMINA = "Stamina", INTELLECT = "Intellect", SPIRIT = "Spirit" }
local STAT_FIRST = { WARRIOR = "STRENGTH", PALADIN = "STRENGTH", ROGUE = "AGILITY", HUNTER = "AGILITY", MAGE = "INTELLECT", WARLOCK = "INTELLECT",
                     PRIEST = "INTELLECT", DRUID = "INTELLECT", SHAMAN = "INTELLECT" }
local STAT_ORDER = { "STRENGTH", "AGILITY", "STAMINA", "INTELLECT", "SPIRIT" }
-- "+4 Intellect, +2 Stamina": the item's main stats as the client gives them (ITEM_MOD_<STAT>_SHORT), the class's own
-- first, then Stamina, two at most; nil when the client gives none
local function statsLine(link)
  local get = C_Item and C_Item.GetItemStats
  if type(get) ~= "function" or type(link) ~= "string" then return nil end
  local ok, t = pcall(get, link)
  if not (ok and type(t) == "table") then return nil end
  local have = {}
  for k, v in pairs(t) do
    local stat = type(k) == "string" and k:match("^ITEM_MOD_(%u+)_SHORT$")
    v = QB.Plain(v)
    if stat and STAT_WORD[stat] and type(v) == "number" and v > 0 then have[stat] = v end
  end
  local out, first = {}, STAT_FIRST[QB.state and QB.state.class or ""]
  local function add(stat) if have[stat] and #out < 2 then out[#out + 1] = "+" .. have[stat] .. " " .. STAT_WORD[stat]; have[stat] = nil end end
  if first then add(first) end
  add("STAMINA")
  for _, stat in ipairs(STAT_ORDER) do add(stat) end
  return #out > 0 and table.concat(out, ", ") or nil
end
local function whyLine(r)
  if not r.pick then return "First choice: no better pick known" end
  local why = statsLine(r.link)
  if not why and r.item and QB.UI and QB.UI.ItemFacts then
    local _, _, _, ilvl = QB.UI.ItemFacts(r.item)
    if type(ilvl) == "number" and ilvl > 0 then why = "item level " .. ilvl .. ", the best you can use here" end
  end
  return (QB.NAME or "QuestBank") .. "'s pick: " .. (why or "the best you can use here")
end
function SF.MarkReward()
  local r = G.reward
  local rf = QuestInfoFrame and QuestInfoFrame.rewardsFrame
  local buttons = rf and rf.RewardButtons
  local b = r and buttons and buttons[r.index]
  local m = SF.mark
  if not b then
    if m and m:IsShown() then m:Hide() end
    if SF.why and SF.why:IsShown() then SF.why:Hide() end
    return
  end
  local parent = b:GetParent() or UIParent -- (the window's reward frame: QuestInfo.lua swaps the map's and the window's)
  if not m then
    m = CreateFrame("Frame", nil, parent)
    SF.mark = m
    m.edges = {}
    for i = 1, 4 do m.edges[i] = m:CreateTexture(nil, "OVERLAY") end
  end
  if m:GetParent() ~= parent then m:SetParent(parent) end
  m:SetFrameLevel((b:GetFrameLevel() or 1) + 2)
  local icon = rawget(b, "Icon") or rawget(b, "icon") -- (the template's parentKey; a plain field)
  local edge = r.pick and 2 or 1
  m:ClearAllPoints()
  m:SetPoint("TOPLEFT", icon or b, "TOPLEFT", -edge, edge)
  m:SetPoint("BOTTOMRIGHT", icon or b, icon and "BOTTOMRIGHT" or "BOTTOMLEFT", edge, -edge)
  if not icon then m:SetWidth((b:GetHeight() or 40) + edge * 2) end -- (a button with no icon of its name: its square end)
  local e = m.edges
  e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(edge)
  e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(edge)
  e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(edge)
  e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(edge)
  local c = tone(r.pick and "INK" or "SOFT")
  for i = 1, 4 do e[i]:SetColorTexture(c[1], c[2], c[3], r.pick and 1 or 0.7) end
  m:Show()
  -- the line: beside the Complete Quest button (QuestFrame.xml: the reward panel's, at the window's bottom left), else
  -- under the marked button
  local w = SF.why
  local host = QuestFrame or UIParent
  if not w then
    local holder = CreateFrame("Frame", nil, host)
    holder:SetSize(1, 1)
    w = fs(holder, 10, "INK", 190) -- (two lines at most, beside the button: as tall as it is)
    w:SetWordWrap(true)
    w.holder = holder
    SF.why = w
  end
  local holder = w.holder
  if holder:GetParent() ~= host then holder:SetParent(host) end
  local anchor = QuestFrameCompleteQuestButton
  holder:SetFrameLevel(((anchor and anchor:GetFrameLevel()) or (b:GetFrameLevel() or 1)) + 1)
  holder:ClearAllPoints(); w:ClearAllPoints()
  if anchor then
    holder:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
    w:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
  else
    holder:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -4)
    w:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -4)
  end
  local wc = tone(r.pick and "INK" or "SOFT")
  w:SetTextColor(wc[1], wc[2], wc[3])
  w:SetText(whyLine(r))
  holder:Show(); w:Show()
end

-- the lines, when something changed (and the item button, once a fight is over)
function SF.Refresh()
  local f = SF.frame
  if not (f and f:IsShown()) then return end
  if f.card and f.card:IsShown() then SF.RefreshItem(nil) return end
  if SF.pendingItem and not fighting() then lastVer = -1 end
  local steps = G.Steps()
  local text = G.TimeToLevel()
  local remind = (G.reminder and GetTime and GetTime() < G.reminder) and true or false
  local members = G.MemberSteps() -- (the list stands until G.memberVer moves: no table and no string a tick)
  if SF.notePending then SF.notePending, SF.noteUntil = nil, (GetTime and GetTime() or 0) + NOTE_S end
  local note = (SF.noteUntil and GetTime and GetTime() < SF.noteUntil) and true or false
  local mins = steps[1] and minsNow(steps[1]) or nil -- (the step now's minutes, as you go: a number, no string a tick)
  if G.ver == lastVer and text == lastTime and remind == lastRemind and G.memberVer == lastMembers and note == lastNote and mins == lastMins then return end
  lastVer, lastTime, lastRemind, lastMembers, lastNote, lastMins = G.ver, text, remind, G.memberVer, note, mins
  -- the first row makes room for the item button only while one shows (in a fight, as the button stands)
  local itemUp = fighting() and (f.item ~= nil and f.item:IsShown()) or (not fighting() and G.ItemFor(steps[1]) ~= nil)
  f.rows[1].text:SetWidth(INNER - TEXT_X - (itemUp and 30 or 0))
  f.rows[1].text.qbText, f.rows[1].text.qbA = nil, nil -- (fitted again at the new width)
  for i = 1, 3 do
    local s, r = steps[i], f.rows[i]
    if i == 1 then
      rowText(r.text, s and G.Title(s) or ("Nothing to do: " .. (QB.CMD or "/qb")), nil)
      rowText(r.where, s and G.Where(s) or "", nil)
      r.mins:SetText(mins and (mins .. " min") or "")
    elseif s then
      rowTwo(r.text, G.Title(s), G.Place(s))
      local m = G.Mins(s, steps[i - 1])
      r.mins:SetText(m and ("+" .. m .. " min") or "")
    end
    if s then stepIcon(r.icon, s) else r.icon:Hide() end
    r:SetShown(i == 1 or s ~= nil)
  end
  f.time:SetText(text or "")
  f.remind:SetText(remind and "New spells at your class trainer" or "")
  f.remind:SetShown(remind)
  local y = PAD + ROW1 + ROW * 2 + (text and ROW or 0)
  if remind then
    f.remind:ClearAllPoints()
    f.remind:SetPoint("TOPLEFT", PAD, -y)
    y = y + ROW
  end
  f.note:SetShown(note)
  if note then
    f.note:ClearAllPoints()
    f.note:SetPoint("TOPLEFT", PAD, -y)
    y = y + NOTE_H + 4
  end
  for i, m in ipairs(members) do
    local t = f.members[i]
    if not t then t = fs(f, 10, "SOFT", WIDTH - PAD * 2); f.members[i] = t end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", PAD, -y)
    local name = (QB.Sync and QB.Sync.ColorName) and QB.Sync.ColorName(m.name, m.class) or m.name
    t:SetText(name .. ": " .. m.text)
    t:Show()
    y = y + ROW
  end
  for i = #members + 1, #f.members do f.members[i]:Hide() end
  if f:GetHeight() ~= y + PAD then f:SetHeight(y + PAD); arrowFollows() end
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
  card.title = fs(card, 12, "INK", CARD_W)
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
  card.turnIn.label = fs(card, 11, "INK", CARD_W - 28)
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
  f.time:Hide(); f.remind:Hide(); f.note:Hide()
  for _, t in ipairs(f.members) do t:Hide() end
  if kind == "ask" then
    card.title:SetText("Let " .. (QB.NAME or "QuestBank") .. " guide you?")
    card.accept:Hide(); card.other:Hide(); card.turnIn:Hide(); card.turnIn.label:Hide(); card.done:Hide()
    card.yes:Show(); card.no:Show()
    f:SetHeight(PAD * 2 + 48)
  else
    card.title:SetText((QB.NAME or "QuestBank") .. " guides you from here. At quest givers:")
    card.yes:Hide(); card.no:Hide()
    card.accept:Show(); card.other:Show(); card.turnIn:Show(); card.turnIn.label:Show(); card.done:Show()
    card.Words()
    f:SetHeight(PAD * 2 + 140)
  end
  card:Show()
  f:Show()
  arrowFollows()
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

-- (6.1.1) the game's quest tracker out of sight while the step frame shows and guide.hideTracker is on ("hidden by
-- default there in game, Blizzard's one, if they use ours"). Forever loads mainline's tracker, ObjectiveTrackerFrame
-- (Blizzard_ObjectiveTracker; the Camelot override changes only its timer bar and tags): an Edit Mode system whose
-- settings are height, background opacity and text size, and no CVar hides it. It is a right-hand managed frame: shown,
-- hidden, moved or reparented by an addon, the right-hand container's layout would run as the addon. So it goes out of
-- sight by its alpha, the way the game's own managed-frame system does it (ManagedFrameSystem.lua,
-- AnimOutManagedFrames), never in a fight; when the game puts the alpha back (AnimInManagedFrames) it goes again, after
-- the fight if in one. Back at once when the setting or the step frame goes off. (Out of sight, its lines still take a
-- click where they stand, as the game's own fade leaves them.)
local function tracker()
  local t = ObjectiveTrackerFrame
  return type(t) == "table" and type(t.SetAlpha) == "function" and type(t.GetAlpha) == "function" and t or nil
end
function SF.Tracker()
  local t = tracker()
  if not t then return end
  local f = SF.frame
  local want = settings().hideTracker ~= false and f ~= nil and f:IsShown() and true or false
  if fighting() then trackerWait = true return end
  trackerWait = false
  if want then
    if not trackerHooked and type(hooksecurefunc) == "function" then
      trackerHooked = true
      hooksecurefunc(t, "SetAlpha", function(self, a)
        if not trackerOut or a == 0 then return end
        if fighting() then trackerWait = true else self:SetAlpha(0) end
      end)
    end
    if not trackerOut and not settings().trackerTold then
      settings().trackerTold = true
      SF.notePending = true
    end
    trackerOut = true
    if t:GetAlpha() ~= 0 then t:SetAlpha(0) end
  elseif trackerOut then
    trackerOut = false
    t:SetAlpha(1)
  end
end
SF.TrackerOut = function() return trackerOut end

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
  SF.Tracker()
  arrowFollows()
end

-- the frame's scale, and the item button's with it (a child of UIParent: the frame's scale does not reach it); the
-- button is secure, so in a fight its scale waits for the fight's end (SF.pendingItem, SF.OnRegen)
function SF.SetScale(sc)
  settings().scale = sc
  local f = SF.frame
  if not f then return end
  f:SetScale(sc)
  if f.qbX then place(f) end -- (at its default place: kept clear of the tracker at the new size)
  if f.item then
    if fighting() then SF.pendingItem = true else f.item:SetScale(sc) end
  end
  arrowFollows()
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
  -- the game's quest tracker: back, or out of sight again while the frame shows (Settings has the same row)
  SF.noteUntil, SF.notePending = nil, nil -- (the menu found: the note has done its work)
  if trackerOut then
    items[#items + 1] = { "Show the game's quest tracker", function() set.hideTracker = false; SF.Tracker(); lastVer = -1; SF.Refresh() end }
  elseif tracker() and set.hideTracker == false then
    items[#items + 1] = { "Hide the game's quest tracker while this shows", function() set.hideTracker = true; SF.Tracker(); lastVer = -1; SF.Refresh() end }
  end
  -- (the launch round) a line in chat for each hand-in, only when asked for: Core.lua's onTurnIn reads sayXP
  local qs = QB:Settings()
  items[#items + 1] = { "Say XP after each hand-in: " .. (qs.sayXP == true and "on" or "off"), function() qs.sayXP = qs.sayXP ~= true end }
  items[#items + 1] = { "Settings", function() QB.UI:Open(5) end }
  QB.UI:ShowMenu("The next step", items)
end

function SF:Init()
  SF.Apply()
end
