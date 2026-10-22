-- SPDX-License-Identifier: GPL-3.0-or-later
-- The step frame (6.0): the Guide's current step, the next two greyed beneath, a quest-item button when the step needs
-- one, "about 14 min to level 6", the one line of guidance that means going somewhere (the hud round: Train, Flight
-- path, Sleeping bag, Remind.Step), and the party's steps. Each step says where (the launch round):
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
local LINE_MINS = 38 -- (the reminder line's minutes: "12 min" at 11 px)
local LINE_TWO = 14 -- (the reminder line's second row, where its words need one: 12 px)
local INNER = WIDTH - PAD * 2
-- (the windows round) a host's look, QB.Skin.stop (Cute_Quest's): the frame as a stop of the route, standing on the
-- world with no backdrop (the setting guide.backdrop brings the host's flat one back) and its text outlined and
-- shadowed: the step's icon at 24 px, its words at 15 px with its quest's name (or who and where) under them, the count
-- on the right and a 2 px bar of its progress in the quest gold, the next two at 14 px; no time line (the host's window
-- and the game's own bar show the XP). Its geometry is set as the frame is built (STOP); QuestBank's own look is as it
-- was. Either look can list the quests you hold under the steps (guide.quests: SF.Quests)
local STOP = false
local BAR_Y = 0 -- (the progress bar's top, under the step now's row)
local QUEST = { 1, 0.82, 0 } -- (the quest gold: the game's quest colour, the bar's)
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
-- (the layout round) the frame's lock: a host's one lock for the on-screen pieces where it sets one (QB.LayoutLocked:
-- Cute's, which its Bridge.lua sets), else QuestBank's own, guide.locked (Settings and the frame's menu)
local function locked()
  local h = QB.LayoutLocked
  if type(h) == "function" then return h("step") == true end
  return settings().locked == true
end
local trackerOut, trackerHooked, trackerWait = false, false, false -- (the game's quest tracker: SF.Tracker)
-- (the windows round) its scale while out of sight, the one it had (kept for the session), and Edit Mode open
local OUT_SCALE = 0.01
local trackerScale, trackerEditing = nil, false
-- the first time the tracker goes out of sight the frame says where it went, for NOTE_S seconds, once for good
-- (guide.trackerTold, set as the note shows: a /reload under the welcome card still has it to tell); its menu brings
-- the tracker back
local NOTE_S, NOTE_H = 60, 24
local MEMBER_LINES = 4 -- (the group's steps: SF.Refresh)
local TRACKER_NOTE = "The game's quest tracker is hidden while this frame shows. Right-click here to show it."
SF.noteUntil, SF.notePending = nil, nil -- (pending: told when the steps next show, not under a welcome card)

local function fs(parent, size, key, width)
  local t = parent:CreateFontString(nil, "OVERLAY")
  local fo = GameFontNormal
  local sk = QB.Skin
  if sk and sk.font then
    if fo then t:SetFontObject(fo) end
    -- (over the world with no backdrop: the font's outline and a 1 px shadow, as the host asks)
    t:SetFont(sk.font, size, sk.outline and "OUTLINE" or "")
    if sk.outline and t.SetShadowOffset then t:SetShadowOffset(1, -1); t:SetShadowColor(0, 0, 0, 1) end
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

-- the minutes to the step now, as you go: the arrow's own count while it leads there (to the same place, or to the stop
-- the step is at: the route's target is its stop's first NPC, and the step may be at another); else, on your continent
-- and on foot (a leg the plan walks, or an objective's spot), the yards from where you stand at the planner's pace
-- (Model.lua's M.Between: DETOUR, RUN, M.Factor mounted or not), read again once you have moved 20 yards; else the
-- plan's for the step's leg (G.Mins). (The launch round kept the plan's figure whenever the arrow led elsewhere, off,
-- or away in a dungeon: "11 min" as you walked.) A number, no table and no string a tick
local hereBuf, walkX, walkY, walkSX, walkSY, walkMins = {}, nil, nil, nil, nil, nil
local function leadsThere(s, t)
  if s.wx and t.wx and t.c == s.c and (t.wx - s.wx) ^ 2 + (t.wy - s.wy) ^ 2 < 900 then return true end
  if not (s.leg and s.npc and t.stop and not t.obj) then return false end
  local r = QB.Target and QB.Target.Route and QB.Target.Route()
  local leg = r and r.legs and r.legs[s.leg]
  local stop = leg and leg.stop
  return stop ~= nil and stop.name == t.stop and stop.seen ~= nil and stop.seen[s.npc] == true
end
local function onFoot(s)
  if not (s.wx and (s.way == "foot" or not s.leg)) then return nil end
  local me = QB.API.WorldPosition(nil, hereBuf)
  if not (me and me.c == s.c) then return nil end
  if walkSX == s.wx and walkSY == s.wy and walkX and (me.wx - walkX) ^ 2 + (me.wy - walkY) ^ 2 < 400 then return walkMins end
  local M = QB.Model
  local yards = math.sqrt((s.wx - me.wx) ^ 2 + (s.wy - me.wy) ^ 2)
  local mins = yards * (M.DETOUR or 1.3) / (M.RUN or 7) / 60 * (M.Factor and M.Factor((QB:Mounted())) or 1)
  walkX, walkY, walkSX, walkSY, walkMins = me.wx, me.wy, s.wx, s.wy, math.floor(mins + 0.5)
  return walkMins
end
local function minsNow(s)
  local A = QB.Arrow
  local g, t, f = A and A.g, A and A.t, A and A.frame
  if g and g.eta and t and f and f:IsShown() and leadsThere(s, t) then return math.floor(g.eta + 0.5) end
  return onFoot(s) or G.Mins(s)
end
SF.MinsNow = minsNow

-- the minutes to a step from now, for its tooltip: the step now's (minsNow), and for a next one those and each new
-- trip's on the way to it (G.Mins: the rows' "+N min") while every step between is on a leg of the route; nil past an
-- objective (how long one takes is nobody's guess). (The launch round said "about 11 min there" from the leg's
-- minutes, counted from the stop before: 11 for the second NPC at the stop the row above put 3 min away)
local function minsFromNow(steps, i)
  local total = minsNow(steps[1])
  if i == 1 or not (total and steps[1].leg) then return i == 1 and total or nil end
  for j = 2, i do
    local s = steps[j]
    if not s.leg then return nil end
    total = total + (G.Mins(s, steps[j - 1]) or 0)
  end
  return total
end

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
  local mins = minsFromNow(steps, self.i)
  local trip = not (mins and mins > 0) and self.i > 1 and G.Mins(s, steps[self.i - 1]) or nil
  local when = (mins and mins > 0) and string.format("about %d min there", mins) or (trip and string.format("a trip of about %d min", trip)) or nil
  -- (the XP of every quest a hand-in of several takes, Replan's s.xp; the launch round gave the lowest id's alone)
  local xp
  if (s.n or 1) > 1 and s.xp then xp = s.xp > 0 and s.xp or nil else xp = s.qid and QB:Value(s.qid) end
  if when or xp then
    GameTooltip:AddDoubleLine(when or " ", xp and (QB.Comma(xp) .. " XP") or "", SOFT[1], SOFT[2], SOFT[3], SOFT[1], SOFT[2], SOFT[3])
  end
  -- (a step with no quest opens the Route page, or a host's page for it: UI.PageName, Cute's Quests while its Route
  -- module is off; the launch round said "the way there" whatever opened)
  GameTooltip:AddLine(s.qid and "Click: the quest. Right-click: Not now, Drop, the game's quest tracker and more."
    or ("Click: the " .. ((QB.UI and QB.UI.PageName and QB.UI.PageName(3)) or "Route") .. " page. Right-click: the game's quest tracker and more."),
    SOFT[1], SOFT[2], SOFT[3], true)
  GameTooltip:Show()
end
local function rowLeave() if GameTooltip:GetOwner() then GameTooltip:Hide() end end

local place, arrowFollows -- (below: where the frame stands, and the arrow under it)

local function build()
  local sk = QB.Skin
  STOP = sk ~= nil and sk.stop == true
  if STOP then
    -- (no border art: 10 px round the text keep its outline off the frame's edge)
    WIDTH, PAD, ROW, ROW1, TEXT_X = 280, 10, 17, 36, 30
    INNER, BAR_Y = WIDTH - PAD * 2, 37
    if sk.QUEST then QUEST = sk.QUEST end
  end
  local f = CreateFrame("Frame", "QuestBankStep", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(WIDTH, PAD * 2 + ROW1 + ROW * 3)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  if STOP then
    f.qbBackdrop = false -- (none until guide.backdrop asks for the host's: SF.Apply)
  elseif sk and sk.Backdrop then
    sk.Backdrop(f)
  elseif f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(SLATE[1], SLATE[2], SLATE[3], 0.92)
    local gold = tone("GOLD")
    f:SetBackdropBorderColor(gold[1], gold[2], gold[3], 0.5)
  end
  f:SetScript("OnDragStart", function(self) if not locked() then self.qbDragging = true; self:StartMoving() end end)
  -- (the review round) a right-click anywhere on the frame is its menu, as on a step: the tracker's note under the steps
  -- says "Right-click here", and only the steps took one (a welcome card's own buttons answer for it)
  f:SetScript("OnMouseUp", QB.Safe(function(self, button)
    if button == "RightButton" and not (self.card and self.card:IsShown()) then SF:Menu(G.Steps()[1]) end
  end, "step frame"))
  -- (the review round) kept by its middle against the screen's, where the drag left it, whatever point the game
  -- anchors a moved frame by (place() anchors it so again); the arrow follows it at once
  f:SetScript("OnDragStop", QB.Safe(function(self)
    if not self.qbDragging then return end -- (a drag the lock refused: its place left alone)
    self.qbDragging = nil
    self:StopMovingOrSizing()
    local cx, cy = self:GetCenter()
    local fs, us = self:GetEffectiveScale() or 1, UIParent:GetEffectiveScale() or 1
    if type(cx) == "number" and type(cy) == "number" and fs > 0 then
      settings().x = cx - (UIParent:GetWidth() or 0) * us / (2 * fs)
      settings().y = cy - (UIParent:GetHeight() or 0) * us / (2 * fs)
      place(self)
    end
    arrowFollows()
  end, "step frame"))
  -- three rows: the step now (its name, then who and where with the minutes), the two next (name and place, the
  -- minutes where a new trip starts); each a button for its click and menu, with the kind's icon. The host's stop look:
  -- the step now's icon 24 px, its words at 15 px in the accent with who and where under them at 11 px, the count (or
  -- the minutes) at its right, its progress bar under it; the next two at 14 px and 12 px, after the bar
  f.rows = {}
  for i = 1, 3 do
    local b = CreateFrame("Button", nil, f)
    local now = i == 1
    b:SetSize(INNER, now and ROW1 or ROW)
    b:SetPoint("TOPLEFT", PAD, -PAD - (now and 0 or ROW1 + (STOP and 6 or 0) + (i - 2) * ROW))
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    local isz = STOP and (now and 24 or 14) or (now and 16 or 14)
    b.icon:SetSize(isz, isz)
    if STOP then b.icon:SetPoint("TOPLEFT", now and 0 or 5, now and -2 or -1) else b.icon:SetPoint("TOPLEFT", now and 0 or 1, now and 0 or -2) end
    b.icon:Hide()
    if STOP then
      b.text = fs(b, now and 15 or 12, now and "GOLD" or "INK", INNER - TEXT_X - MINS_W)
      b.text:SetPoint("TOPLEFT", TEXT_X, -1)
      b.mins = fs(b, now and 12 or 11, "INK", MINS_W)
      b.mins:SetJustifyH("RIGHT")
      b.mins:SetPoint("TOPRIGHT", 0, -2)
      if now then
        b.where = fs(b, 11, "INK", INNER - TEXT_X)
        b.where:SetPoint("TOPLEFT", TEXT_X, -19)
      end
    else
      b.text = fs(b, now and 12 or 11, now and "INK" or "SOFT", now and (INNER - TEXT_X) or (INNER - TEXT_X - MINS_W))
      b.text:SetPoint("TOPLEFT", TEXT_X, now and -1 or -2)
      b.mins = fs(b, 10, "SOFT", MINS_W)
      b.mins:SetJustifyH("RIGHT")
      b.mins:SetPoint("TOPRIGHT", 0, now and -21 or -3)
      if now then
        b.where = fs(b, 10, "SOFT", INNER - TEXT_X - MINS_W)
        b.where:SetPoint("TOPLEFT", TEXT_X, -21)
      end
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
  if STOP then
    -- the step now's progress: a 2 px track and its share in the quest gold (an objective's count)
    f.track = f:CreateTexture(nil, "ARTWORK")
    f.track:SetColorTexture(0.16, 0.16, 0.16, 0.9)
    f.track:SetPoint("TOPLEFT", PAD, -PAD - BAR_Y)
    f.track:SetSize(INNER, 2)
    f.fill = f:CreateTexture(nil, "OVERLAY")
    f.fill:SetColorTexture(QUEST[1], QUEST[2], QUEST[3], 1)
    f.fill:SetPoint("TOPLEFT", PAD, -PAD - BAR_Y)
    f.fill:SetSize(1, 2)
    f.track:Hide(); f.fill:Hide()
  end
  f.quests, f.qitems = {}, {}
  -- (the stop look's small lines at 11 px in the ink: over the world, the soft grey reads too faint)
  local small, soft = STOP and 11 or 10, STOP and "INK" or "SOFT"
  f.time = fs(f, small, soft, WIDTH - PAD * 2)
  f.time:SetPoint("TOPLEFT", PAD, -PAD - ROW1 - ROW * 2)
  if STOP then f.time:Hide() end
  -- (the hud round) the line: a 14 px icon, its words at 12 px in the ink, the minutes at 11 px on the right; a 2 px bar
  -- at its left in its category's colour (the sleeping bag's quest gold); a click shows its place on the arrow, a
  -- right-click is Remind's menu (Not now, Never: the line's, the step frame's own menu stays the steps')
  local line = CreateFrame("Button", nil, f)
  line:SetSize(INNER, ROW)
  line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  line.icon = line:CreateTexture(nil, "ARTWORK")
  line.icon:SetSize(14, 14)
  line.icon:SetPoint("TOPLEFT", STOP and 5 or 1, -2)
  line.bar = line:CreateTexture(nil, "ARTWORK")
  line.bar:SetSize(2, 14)
  line.bar:SetPoint("TOPLEFT", STOP and 1 or -4, -2)
  line.bar:Hide()
  line.text = fs(line, 12, "INK", INNER - TEXT_X - LINE_MINS)
  line.text:SetPoint("TOPLEFT", TEXT_X, -2)
  line.mins = fs(line, 11, "INK", LINE_MINS)
  line.mins:SetJustifyH("RIGHT")
  line.mins:SetPoint("TOPRIGHT", 0, -3)
  line:SetScript("OnClick", QB.Safe(function(self, button)
    local rec = self.rec
    if not rec then return end
    if button == "RightButton" then if QB.Remind and QB.Remind.Menu then QB.Remind.Menu(self) end return end
    if QB.Remind and QB.Remind.Go then QB.Remind.Go(rec) end
  end, "step frame: line"))
  line:SetScript("OnEnter", QB.Safe(function(self) if self.rec and QB.Remind and QB.Remind.Tip then QB.Remind.Tip(self, self.rec) end end, "step frame: line"))
  line:SetScript("OnLeave", rowLeave)
  line:Hide()
  f.remind = line
  -- the once-ever note where the game's quest tracker went (SF.Tracker): two lines, wrapped
  f.note = fs(f, small, soft, WIDTH - PAD * 2)
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

-- (the windows round) the tracker's top right corner, in UIParent's units: across from the screen's left, down from its
-- top. Read at the tracker's own size and kept as it goes out of sight (SF.Tracker: at a hundredth of its size it stands
-- elsewhere); nil where the client has no tracker to read
local trackerCut -- { from the screen's right, down from its top }, at its own size
local function trackerCorner(W)
  if trackerOut and trackerCut then return W - trackerCut[1], trackerCut[2] end
  local t = ObjectiveTrackerFrame
  local h = type(t) == "table" and t.Header or nil
  if not (type(h) == "table" and type(h.GetTop) == "function" and type(h.GetWidth) == "function") then return nil end
  local ok, top = pcall(h.GetTop, h)
  local ok2, w = pcall(h.GetWidth, h)
  local ok3, k = pcall(h.GetEffectiveScale, h)
  top, w, k = ok and QB.Plain(top), ok2 and QB.Plain(w), ok3 and QB.Plain(k) or 1
  if type(top) ~= "number" or type(w) ~= "number" or type(k) ~= "number" then return nil end
  local u = UIParent:GetEffectiveScale() or 1
  return trackerLeft(W) + w * k / u, (UIParent:GetHeight() or 768) - top * k / u
end

-- where the frame stands: where it was dragged to, else the top's middle, TOP_Y down whatever its scale, moved left as
-- far as it takes to stay 16 px clear of the tracker's header (6.1.1: "it won't let me minimise my quest list": on a
-- narrow screen of UI or with right action bars, the frame there, in a strata above the tracker's, reached over the
-- minimise button). TOP_Y: the game's error text (UIErrorsFrame, Blizzard_UIErrorsFrame: TOP 0 -122, 512 x 60) ends
-- 182 px down, so "Not enough rage" never lands on the steps; 6.1 stood at 140 (at its scale), under that text and under
-- the arrow. The arrow stands under the frame (Arrow.lua, A.Place: SF.Below)
-- (the windows round) a host that asks (QB.cornerPlace: Cute) has it where the game's quest tracker stands, its top right
-- corner on the tracker's while the tracker is out of sight, 8 px left of the tracker while it is kept; the arrow goes
-- to the top's middle then (Arrow.lua, A.Place)
local TOP_Y = 190
SF.TOP_Y = TOP_Y
function place(f)
  local s = settings()
  local sc = s.scale or 1
  f:ClearAllPoints()
  f:SetScale(sc)
  f.qbTop = nil
  if type(s.x) == "number" and type(s.y) == "number" then f:SetPoint("CENTER", UIParent, "CENTER", s.x, s.y) return end
  local W = UIParent:GetWidth() or 1920
  if QB.cornerPlace then
    local right, top = trackerCorner(W)
    if right then
      if s.hideTracker == false then right = trackerLeft(W) - 8 end
      f.qbX, f.qbTop = right - W / 2 - WIDTH * sc / 2, top -- (its middle across, its top down: SF.Box)
      f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", (right - W) / sc, -top / sc)
      return
    end
  end
  local over = W / 2 + WIDTH * sc / 2 - (trackerLeft(W) - 16)
  f.qbX = over > 0 and -over or 0 -- (its middle across from the screen's, in UIParent's units: SF.Box)
  f:SetPoint("TOP", UIParent, "TOP", f.qbX / sc, -TOP_Y / sc)
end

-- where the frame stands, for the arrow (Arrow.lua, A.Place): its middle across from the screen's middle, its top and
-- its bottom down from the screen's top and its half width, in UIParent's units; nil while it is away. At its default
-- place or where it was dragged to (place(): its middle against the screen's, at its scale). (Until the review round
-- a dragged frame said nothing, and the arrow stood at the frame's default place: on the frame nudged a little)
function SF.Box()
  local f = SF.frame
  if not (f and f:IsShown()) then return nil end
  local s = settings()
  local sc = f:GetScale() or 1
  local h = (f:GetHeight() or 0) * sc
  if type(s.x) == "number" and type(s.y) == "number" then
    local mid = (UIParent:GetHeight() or 768) / 2 - s.y * sc
    return s.x * sc, mid - h / 2, mid + h / 2, WIDTH * sc / 2
  end
  local top = f.qbTop or TOP_Y
  return f.qbX or 0, top, top + h, WIDTH * sc / 2
end
-- its middle across and its bottom (SF.Box)
function SF.Below()
  local x, _, bottom = SF.Box()
  if not x then return nil end
  return x, bottom
end
-- the arrow placed again (its default place follows the frame's place, height, scale and showing)
function arrowFollows() if QB.Arrow and QB.Arrow.Place then QB.Arrow.Place() end end

-- the quest-item button: the game's secure button for the first step's quest item (type item, item:<id>), as
-- Camp.lua's icons; made, set, shown and hidden out of a fight only, else the change waits (SF.pendingItem) for the
-- next refresh out of it. Under UIParent, anchored to the frame's corner: a frame holding a secure button is
-- protected with it, and the step frame must still grow, move and hide in a fight
local function itemButton(f)
  local b = CreateFrame("Button", "QuestBankStepItem", UIParent, "SecureActionButtonTemplate")
  b:SetSize(22, 22)
  -- (the stop look: at the frame's left, beside the step's icon, where the quests' own buttons stand)
  if STOP then b:SetPoint("TOPRIGHT", f, "TOPLEFT", PAD - 4, -PAD) else b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -PAD + 2) end
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
-- (the hud round) the step's item: its quest's usable item, else, while the route's first leg is your hearthstone, the
-- hearthstone you carry (Remind.Hearth: 6948, 243229, 284163, then the single-use 282006), ready: "Use your Hearthstone"
-- had no button
local function hearthItem()
  local r = (QB.Target and QB.Target.Route and QB.Target.Route()) or QB.routeNow
  local leg = r and r.legs and r.legs[1]
  if not (leg and leg.kind == "hearth" and QB.Remind and QB.Remind.Hearth) then return nil end
  local id, left = QB.Remind.Hearth()
  if not id or left > 0 then return nil end
  return id, nil, (QB.Data.TEX and QB.Data.TEX.hearth) or 134414
end
local function itemFor(s)
  local id, link, tex = G.ItemFor(s)
  if id then return id, link, tex end
  return hearthItem()
end
SF.ItemFor = itemFor
function SF.RefreshItem(s)
  local f = SF.frame
  if not f then return end
  local id, _, tex = itemFor(s)
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
-- (the hud round) the line's record, its words and its minutes as last drawn: Remind tells after each refresh
local lineRec, lineText, lineWord
function SF.RemindChanged(rec)
  local text, word = rec and rec.text, rec and rec.word
  if rec == lineRec and text == lineText and word == lineWord then return end
  lineRec, lineText, lineWord = rec, text, word
  lastVer = -1
  if SF.frame and SF.frame:IsShown() then SF.Refresh() end
end
-- the line drawn from its record: its icon (an atlas where the client has it, else the file, at its corners; the
-- corners never set after an atlas, whose own part of its sheet they would replace), desaturated where its record says
-- (Flight path's), words, minutes and bar
local function drawLine(line, rec)
  line.rec = rec
  if line.qbTex ~= rec.tex or line.qbAtlas ~= rec.atlas then
    line.qbTex, line.qbAtlas = rec.tex, rec.atlas
    if not QB.Art(line.icon, rec.atlas, rec.tex or QB.Data.TEX.questGeneric) and rec.tc then
      line.icon:SetTexCoord(rec.tc[1], rec.tc[2], rec.tc[3], rec.tc[4])
    end
  end
  local grey = rec.desat == true
  if line.qbGrey ~= grey then line.qbGrey = grey; line.icon:SetDesaturated(grey) end
  -- (the words take the minutes' room where there are none. The hud review: never cut, since the trainer's or the
  -- town's name is the line's point and one row is too narrow for many, "Learn the flight path: Sentinel Hill" 181 px
  -- of the 178: a second row where the words need it, the frame that much taller. The line changes out of a fight only,
  -- Remind's refresh, so the frame's height with it)
  local tw = INNER - TEXT_X - (rec.mins and LINE_MINS or 0)
  local text, t = rec.text or "", line.text
  if t.qbLine ~= text or t.qbW ~= tw then
    t.qbLine, t.qbW = text, tw
    t:SetWidth(tw)
    t:SetWordWrap(false)
    t:SetText(text)
    local two = ((t.GetUnboundedStringWidth or t.GetStringWidth)(t) or 0) > tw
    t:SetWordWrap(two)
    t:SetHeight(two and 14 + LINE_TWO or 14)
    line.rows = two and 2 or 1
  end
  line.mins:SetText(rec.mins and rec.word or "")
  local col = rec.cat == "xp" and QUEST or nil
  if col then line.bar:SetColorTexture(col[1], col[2], col[3], 1); line.bar:Show() else line.bar:Hide() end
  local h = ROW + (line.rows == 2 and LINE_TWO or 0)
  if line:GetHeight() ~= h then line:SetHeight(h) end
  return h
end

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
    SF.RefreshQuestItems()
  end
end

-- the reward window's pick (G.reward), marked as QuestBank's own and never as the game's: a thin outline round the
-- item's icon, inside the window's reward frame (it scrolls and clips with it), nothing over the item's name and nothing
-- gold or additive (the game's own choice is a gold glow over the whole button, QuestInfoItemHighlight); and one line
-- beside the Complete Quest button, whose pick it is and why: "QuestBank's pick: +4 Intellect, +2 Stamina" (the item's
-- stats, the class's own first: C_Item.GetItemStats), else its item level. The outline (the review round): 2 px near
-- black, which reads on the window's parchment (QuestFramePanelTemplate's QuestBG-Parchment, a light tan) as on a dark
-- frame, with a 1 px line of the frame's ink inside it against the item's dark icon (the launch round's ink alone, a
-- cream, all but vanished on the parchment). A first choice for want of a pick (G.reward.pick false: nothing known fits)
-- is 1 px of the same dark at a third, no inner line, and says so; while the window's items are still coming
-- (G.reward.reading) nothing is marked and the line says that. (6.1 drew the map pins' round additive glow, 170 px of
-- gold on a HIGH frame: it read as the game's own selection and washed the name out.) The button itself is never
-- touched
local RING = { 0.08, 0.06, 0.04 }
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
  if r.reading then return "Reading the rewards..." end
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
  local b = r and r.index and buttons and buttons[r.index]
  local m = SF.mark
  local anchor = QuestFrameCompleteQuestButton
  if not b and not (r and r.reading and buttons and anchor) then
    if m and m:IsShown() then m:Hide() end
    if SF.why and SF.why:IsShown() then SF.why:Hide() end
    return
  end
  if b then
    local parent = b:GetParent() or UIParent -- (the window's reward frame: QuestInfo.lua swaps the map's and the window's)
    if not m then
      m = CreateFrame("Frame", nil, parent)
      SF.mark = m
      m.edges, m.inner = {}, {}
      for i = 1, 4 do m.edges[i] = m:CreateTexture(nil, "OVERLAY"); m.inner[i] = m:CreateTexture(nil, "OVERLAY") end
    end
    if m:GetParent() ~= parent then m:SetParent(parent) end
    m:SetFrameLevel((b:GetFrameLevel() or 1) + 2)
    local icon = rawget(b, "Icon") or rawget(b, "icon") -- (the template's parentKey; a plain field)
    local edge = r.pick and 2 or 1
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", icon or b, "TOPLEFT", -edge, edge)
    m:SetPoint("BOTTOMRIGHT", icon or b, icon and "BOTTOMRIGHT" or "BOTTOMLEFT", edge, -edge)
    if not icon then m:SetWidth((b:GetHeight() or 40) + edge * 2) end -- (a button with no icon of its name: its square end)
    -- four sides of `width` px, `inset` px in from the mark's edges
    local function ring(e, width, inset)
      e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT", inset, -inset); e[1]:SetPoint("TOPRIGHT", -inset, -inset); e[1]:SetHeight(width)
      e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT", inset, inset); e[2]:SetPoint("BOTTOMRIGHT", -inset, inset); e[2]:SetHeight(width)
      e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT", inset, -inset); e[3]:SetPoint("BOTTOMLEFT", inset, inset); e[3]:SetWidth(width)
      e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT", -inset, -inset); e[4]:SetPoint("BOTTOMRIGHT", -inset, inset); e[4]:SetWidth(width)
    end
    ring(m.edges, edge, 0)
    for i = 1, 4 do m.edges[i]:SetColorTexture(RING[1], RING[2], RING[3], r.pick and 1 or 0.33) end
    if r.pick then
      ring(m.inner, 1, edge)
      local c = tone("INK")
      for i = 1, 4 do m.inner[i]:SetColorTexture(c[1], c[2], c[3], 1); m.inner[i]:Show() end
    else
      for i = 1, 4 do m.inner[i]:Hide() end
    end
    m:Show()
  elseif m and m:IsShown() then
    m:Hide()
  end
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
  holder:SetFrameLevel(((anchor and anchor:GetFrameLevel()) or (b and b:GetFrameLevel()) or 1) + 1)
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

-- (the windows round) the quests you hold under the steps: guide.quests of them (QuestBank's default 0: none; Cute's first
-- run 3, its Settings row "Quests under the step"), those the step now and the next two do not already name, the
-- route's first (in the order its steps come to them), then the log's. Each: its level in the game's colour for it
-- (GetQuestDifficultyColor), its name, "ready" at its right once finished, its open objectives under it with the
-- game's cursor for their kind (two at most), and its usable item as the game's secure button at its left (type item,
-- as the step's own, set out of a fight only). "+N more quests" when the log holds more; a click there opens the quest
-- window. A quest's click shows its next spot on the arrow (its nearest open objective, else its hand-in); a right-click
-- is its menu. In a fight the words change and nothing moves: the order, the places and the item buttons wait for its end
local QUESTS_MAX, OBJ_MAX = 10, 2
local Q_NAME, Q_OBJ, Q_GAP = 17, 15, 3 -- (a quest's line, an objective's, and the room after a quest, in px)
local GOOD = { 0.45, 0.83, 0.47 }
local qNamed, qSeen, qList = {}, {}, {}
SF.QUESTS_MAX = QUESTS_MAX
function SF.QuestList(steps, n)
  steps = steps or G.Steps()
  n = math.min(QUESTS_MAX, n or settings().quests or 0)
  for k in pairs(qNamed) do qNamed[k] = nil end
  for k in pairs(qSeen) do qSeen[k] = nil end
  for k = #qList, 1, -1 do qList[k] = nil end
  if n <= 0 then return qList, 0 end
  local state = QB.state
  local log = state.log or {}
  for i = 1, math.min(3, #steps) do
    local s = steps[i]
    if s.qid then qNamed[s.qid] = true end
    -- (a hand-in of several quests at one NPC names each of them)
    if s.kind == "handin" and (s.n or 1) > 1 and s.npc then
      for _, e in ipairs(state.logOrder or {}) do
        local q = QB.Quest.Get(e.id)
        if q and q.turnIdx == s.npc then qNamed[e.id] = true end
      end
    end
  end
  local total = 0
  local function add(id)
    if not id or qNamed[id] or qSeen[id] or not log[id] then return end
    qSeen[id] = true
    total = total + 1
    if #qList < n then qList[#qList + 1] = id end
  end
  for i = 4, #steps do add(steps[i].qid) end
  for _, e in ipairs(state.logOrder or {}) do add(e.id) end
  return qList, total
end

-- the game's colour for a quest's level against yours (QuestDifficultyColors, Constants.lua:195), the ink where the
-- client has none
local function levelColor(lvl)
  if type(GetQuestDifficultyColor) == "function" and type(lvl) == "number" then
    local ok, c = pcall(GetQuestDifficultyColor, lvl)
    if ok and type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
  end
  local ink = tone("INK")
  return ink[1], ink[2], ink[3]
end
-- an objective's kind letter for its cursor (QuestMap.lua's QM.ART): its spot's in the catalog, else "slain" a kill,
-- a count a collect, else a use
local function objKind(id, slot, text)
  local QM, D = QB.QuestMap, QB.Data
  if QM and QM.Spots and D.SPOT then
    for _, sp in ipairs(QM.Spots(D.SPOT[id]) or {}) do if sp.slot == slot then return sp.kind end end
  end
  if type(text) == "string" and (text:find(" slain", 1, true) or text:find(" killed", 1, true)) then return "k" end
  if type(text) == "string" and text:find("%d+%s*/%s*%d+") then return "c" end
  return "u"
end
-- a quest's next spot on the arrow: its nearest open objective, else where it is handed in
local spotBuf = {}
function SF.QuestSpot(id)
  local e = QB.state.log[id]
  local q = QB.Quest.Get(id)
  if not (e and q) then return false end
  local QM, M = QB.QuestMap, QB.Model
  if not e.complete and QM and QM.OpenSpots then
    local me = QB.API.WorldPosition(nil, hereBuf)
    local best, bd
    for _, sp in ipairs(QM.OpenSpots(e)) do
      local w = M.World(sp.m, sp.x * 100, sp.y * 100, spotBuf)
      local d = (me and w and me.c == w.c) and ((w.wx - me.wx) ^ 2 + (w.wy - me.wy) ^ 2) or 1e12
      if not bd or d < bd then best, bd = sp, d end
    end
    if best then QB.API.SetWaypoint(best.m, best.x * 100, best.y * 100, q.name, nil, nil, { qid = id, what = "obj" }) return true end
  end
  local n = q.turn
  if n and not n.inside and n.m and n.m > 0 then QB.API.SetWaypoint(n.m, n.x, n.y, n.n, nil, nil, { qid = id, what = "turn" }) return true end
  return false
end

local function questBlock(f, i)
  local b = f.quests[i]
  if b then return b end
  b = CreateFrame("Button", nil, f)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.lvl = fs(b, 12, "INK", 18)
  b.lvl:SetJustifyH("RIGHT")
  b.lvl:SetPoint("TOPLEFT", 0, -2)
  b.name = fs(b, 12, "INK", INNER - 24 - 44)
  b.name:SetPoint("TOPLEFT", 24, -2)
  b.word = fs(b, 11, "INK", 40)
  b.word:SetJustifyH("RIGHT")
  b.word:SetPoint("TOPRIGHT", 0, -3)
  b.objs, b.glyphs = {}, {}
  for k = 1, OBJ_MAX do
    local g = b:CreateTexture(nil, "ARTWORK")
    g:SetSize(12, 12)
    g:SetPoint("TOPLEFT", 24, -(Q_NAME + (k - 1) * Q_OBJ) - 1)
    b.glyphs[k] = g
    local t = fs(b, 11, "INK", INNER - 40)
    t:SetPoint("TOPLEFT", 40, -(Q_NAME + (k - 1) * Q_OBJ))
    b.objs[k] = t
  end
  b:SetScript("OnClick", QB.Safe(function(self, button)
    local q = self.id and QB.Quest.Get(self.id)
    if not q then return end
    if button == "RightButton" then if QB.UI and QB.UI.QuestClick then QB.UI.QuestClick(q, QB:Status(q), "RightButton") end return end
    SF.QuestSpot(self.id)
  end, "step frame: quest"))
  b:SetScript("OnEnter", QB.Safe(function(self)
    local q = self.id and QB.Quest.Get(self.id)
    if not q then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if QB.UI and QB.UI.QuestTooltip then QB.UI.QuestTooltip(GameTooltip, q, QB:Status(q), QB:Value(q.id)) else GameTooltip:AddLine(q.name, 1, 1, 1) end
    local soft = tone("SOFT")
    GameTooltip:AddLine("Click: its next spot on the arrow. Right-click: its menu.", soft[1], soft[2], soft[3], true)
    GameTooltip:Show()
  end, "step frame: quest"))
  b:SetScript("OnLeave", rowLeave)
  f.quests[i] = b
  return b
end
-- a quest's words in its block: its level, name and word, and its open objectives (finished ones dropped), two at most;
-- slots: the objectives the block shows (in a fight, the ones laid out before it, a finished one left in its place so
-- nothing moves). Returns the slots it shows
local function fillBlock(b, id, slots)
  local e, q = QB.state.log[id], QB.Quest.Get(id)
  local lvl = (q and q.lvl) or (e and QB.Plain(e.level)) or nil
  b.lvl:SetText(type(lvl) == "number" and tostring(lvl) or "")
  b.lvl:SetTextColor(levelColor(lvl))
  rowText(b.name, (q and q.name) or QB.Plain(e and e.title) or ("Quest " .. id), nil)
  local ready = e and e.complete
  b.word:SetText(ready and "ready" or "")
  local good = (QB.Skin and QB.Skin.GOOD) or GOOD
  b.word:SetTextColor(good[1], good[2], good[3])
  local objs = (e and e.objectives) or {}
  if not slots then
    slots = {}
    if not ready then
      for slot, o in ipairs(objs) do
        if #slots < OBJ_MAX and QB.Plain(o.done) ~= true then slots[#slots + 1] = slot end
      end
    end
  end
  for k = 1, OBJ_MAX do
    local slot = slots[k]
    local o = slot and objs[slot]
    local t, g = b.objs[k], b.glyphs[k]
    if o then
      local done = QB.Plain(o.done) == true
      local name, have, need = G.ParseLine(o.text)
      rowText(t, (have and need) and string.format("%s %d/%d", name, have, need) or (name or ""), nil)
      if done then
        QB.Art(g, "ReadyCheck-Ready", QB.Data.TEX.ready)
        local soft = tone("SOFT"); t:SetTextColor(soft[1], soft[2], soft[3])
      else
        if QB.QuestMap and QB.QuestMap.PaintKind then QB.QuestMap.PaintKind(g, objKind(id, slot, QB.Plain(o.text))) end
        local ink = tone("INK"); t:SetTextColor(ink[1], ink[2], ink[3])
      end
      t:Show(); g:Show()
    elseif slot then
      t:Show(); g:Show() -- (a fight: a line laid out before it keeps its place)
    else
      t:Hide(); g:Hide()
    end
  end
  return slots
end
-- the quests drawn from y down; returns the y under them. Out of a fight they are laid out (f.qLayout); in one the
-- layout stands and only the words change
function SF.DrawQuests(f, y, steps, n)
  local lay = f.qLayout
  if fighting() and lay then
    for i, it in ipairs(lay) do fillBlock(f.quests[i], it.id, it.slots) end
    SF.pendingItem = true -- (the order is made again as the fight ends: SF.OnRegen)
    return lay.bottom
  end
  local list, total = SF.QuestList(steps, n)
  lay = { y = y }
  local top = y
  if #list > 0 then y = y + 4 end
  for i, id in ipairs(list) do
    local b = questBlock(f, i)
    b.id = id
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", PAD, -y)
    local slots = fillBlock(b, id)
    local h = Q_NAME + #slots * Q_OBJ
    b:SetSize(INNER, h)
    b:Show()
    lay[i] = { id = id, y = y, slots = slots }
    y = y + h + Q_GAP
  end
  for i = #list + 1, #f.quests do f.quests[i]:Hide(); f.quests[i].id = nil end
  local more = total - #list
  if more > 0 then
    if not f.more then
      f.more = CreateFrame("Button", nil, f)
      f.more.text = fs(f.more, STOP and 11 or 10, "INK", INNER - 24)
      f.more.text:SetPoint("LEFT", 24, 0)
      f.more:SetScript("OnClick", QB.Safe(function() if QB.UI then QB.UI:Open(1) end end, "step frame: more quests"))
    end
    f.more:ClearAllPoints()
    f.more:SetPoint("TOPLEFT", PAD, -y)
    f.more:SetSize(INNER, Q_OBJ)
    f.more.text:SetText(string.format("+%d more %s", more, more == 1 and "quest" or "quests"))
    f.more:Show()
    y = y + Q_OBJ
  elseif f.more then
    f.more:Hide()
  end
  if y == top then lay.bottom = y; f.qLayout = lay; return y end
  lay.bottom = y + 2
  f.qLayout = lay
  return lay.bottom
end

-- the quests' item buttons: the game's secure button for a quest's usable item at its block's left, set, shown and
-- hidden out of a fight only (as the step's own, SF.RefreshItem); in one the change waits for its end (SF.pendingItem)
local function questItemButton(i)
  local b = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
  b:SetSize(20, 20)
  b:SetFrameStrata("MEDIUM")
  b:RegisterForClicks("AnyUp", "AnyDown")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b:Hide()
  return b
end
function SF.RefreshQuestItems()
  local f = SF.frame
  if not f then return end
  local lay = f.qLayout or {}
  local showing = f:IsShown() and not (f.card and f.card:IsShown())
  if fighting() then SF.pendingItem = true return end
  local sc = settings().scale or 1
  for i = 1, math.max(#lay, #f.qitems) do
    local it = showing and lay[i] or nil
    local id, _, tex
    if it then id, _, tex = G.ItemFor({ qid = it.id }) end
    local b = f.qitems[i]
    if id and not b then b = questItemButton(i); f.qitems[i] = b end
    if b then
      if id then
        if b:GetScale() ~= sc then b:SetScale(sc) end
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", f, "TOPLEFT", PAD - 4, -it.y)
        b:SetFrameLevel((f:GetFrameLevel() or 0) + 5)
        local want = "item:" .. id
        if b:GetAttribute("item") ~= want then b:SetAttribute("type", "item"); b:SetAttribute("item", want) end
        if tex then b.icon:SetTexture(tex) end
        if not b:IsShown() then b:Show() end
      elseif b:IsShown() then
        b:Hide()
      end
    end
  end
end

-- the lines, when something changed (and the item button, once a fight is over)
function SF.Refresh()
  local f = SF.frame
  if not (f and f:IsShown()) then return end
  if f.card and f.card:IsShown() then SF.RefreshItem(nil) return end
  if SF.pendingItem and not fighting() then lastVer = -1 end
  local steps = G.Steps()
  local text = G.TimeToLevel()
  local rl = G.Reminder and G.Reminder() or nil
  local remind = rl ~= nil
  local members = G.MemberSteps() -- (the list stands until G.memberVer moves: no table and no string a tick)
  if SF.notePending then
    SF.notePending, SF.noteUntil = nil, (GetTime and GetTime() or 0) + NOTE_S
    settings().trackerTold = true
  end
  local note = (SF.noteUntil and GetTime and GetTime() < SF.noteUntil) and true or false
  local mins = steps[1] and minsNow(steps[1]) or nil -- (the step now's minutes, as you go: a number, no string a tick)
  if G.ver == lastVer and text == lastTime and remind == lastRemind and G.memberVer == lastMembers and note == lastNote and mins == lastMins then return end
  lastVer, lastTime, lastRemind, lastMembers, lastNote, lastMins = G.ver, text, remind, G.memberVer, note, mins
  -- the first row makes room for the item button only while one shows (in a fight, as the button stands); the stop
  -- look's button stands left of the frame
  local itemUp = not STOP and (fighting() and (f.item ~= nil and f.item:IsShown()) or (not fighting() and itemFor(steps[1]) ~= nil))
  f.rows[1].text:SetWidth(INNER - TEXT_X - (STOP and MINS_W or 0) - (itemUp and 30 or 0))
  f.rows[1].text.qbText, f.rows[1].text.qbA = nil, nil -- (fitted again at the new width)
  for i = 1, 3 do
    local s, r = steps[i], f.rows[i]
    if i == 1 and STOP then
      -- the step's words with its count apart (G.Parts), the count at the right and its share on the bar; who and
      -- where under them; the minutes at the right where there is no count
      local words, have, need
      if s then words, have, need = G.Parts(s) end
      local right = ""
      if have and need and need > 0 then
        right = have .. "/" .. need
        f.fill:SetWidth(math.max(1, INNER * math.min(1, have / need)))
        f.track:Show(); f.fill:SetShown(have > 0)
      else
        right = (mins and mins > 0) and (mins .. " min") or ""
        f.track:Hide(); f.fill:Hide()
      end
      r.mins:SetText(right)
      -- (the words take the count's room where there is none; too long, the shorter form: a hand-in's quest alone,
      -- its icon saying what to do)
      local tw = INNER - TEXT_X - (right ~= "" and MINS_W or 0)
      if r.text:GetWidth() ~= tw then r.text:SetWidth(tw); r.text.qbText, r.text.qbA = nil, nil end
      rowText(r.text, s and words or ("Nothing to do: " .. (QB.CMD or "/qb")), s and (G.Short(s) or (s.kind == "handin" and G.Title(s))) or nil)
      local who, place = s and G.Who(s), s and G.Place(s)
      if who and place and who ~= place then rowTwo(r.where, who, place) else rowText(r.where, who or place or "", nil) end
    elseif i == 1 then
      rowText(r.text, s and G.Title(s) or ("Nothing to do: " .. (QB.CMD or "/qb")), nil)
      -- (who and where cut as the next steps' rows are, the name before the place: "Chief Archaeologist Greywhisker
      -- - Da..." lost the place)
      local who, place = s and G.Who(s), s and G.Place(s)
      if who and place and who ~= place then rowTwo(r.where, who, place) else rowText(r.where, who or place or "", nil) end
      r.mins:SetText((mins and mins > 0) and (mins .. " min") or "")
    elseif s and STOP then
      -- (the stop look: the step's own words, "Hand in A Baying of Gnolls"; its place is in its tooltip)
      rowText(r.text, G.Text(s), G.Short(s))
      local m = G.Mins(s, steps[i - 1])
      r.mins:SetText(m and ("+" .. m .. " min") or "")
    elseif s then
      -- (the place once a trip: a step at the place of the one before it, or on its leg, gives its name alone)
      local place, prev = G.Place(s), steps[i - 1]
      if prev and ((s.leg and prev.leg == s.leg) or (place and place == G.Place(prev))) then place = nil end
      rowTwo(r.text, G.Title(s), place)
      local m = G.Mins(s, steps[i - 1])
      r.mins:SetText(m and ("+" .. m .. " min") or "")
    end
    if s then stepIcon(r.icon, s) else r.icon:Hide() end
    r:SetShown(i == 1 or s ~= nil)
  end
  f.time:SetText((not STOP and text) or "")
  -- (the quests under the steps start where nothing above them moves: the time line's row kept for them; the line of
  -- guidance after the next two steps, before the quests you hold)
  local nq = settings().quests or 0
  local y
  if STOP then y = PAD + ROW1 + 6 + ROW * 2 + 4
  else y = PAD + ROW1 + ROW * 2 + ((text or nq > 0) and ROW or 0) end
  if remind then
    local lh = drawLine(f.remind, rl)
    f.remind:ClearAllPoints()
    f.remind:SetPoint("TOPLEFT", PAD, -y)
    f.remind:Show()
    y = y + lh
  else
    f.remind:Hide()
    f.remind.rec = nil
  end
  y = SF.DrawQuests(f, y, steps, nq)
  f.note:SetShown(note)
  if note then
    f.note:ClearAllPoints()
    f.note:SetPoint("TOPLEFT", PAD, -y)
    y = y + NOTE_H + 4
  end
  -- the group's steps, MEMBER_LINES at most: a party's four, else three and a line for the rest (the review round: a
  -- raid of QuestBank players grew the frame a line each, past the camp bar's place and off a short screen)
  local lines = #members > MEMBER_LINES and MEMBER_LINES or #members
  for i = 1, lines do
    local m = members[i]
    local t = f.members[i]
    if not t then t = fs(f, STOP and 11 or 10, STOP and "INK" or "SOFT", WIDTH - PAD * 2); f.members[i] = t end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", PAD, -y)
    if i == MEMBER_LINES and #members > MEMBER_LINES then
      t:SetText(string.format("and %d more in your group", #members - MEMBER_LINES + 1))
    else
      local name = (QB.Sync and QB.Sync.ColorName) and QB.Sync.ColorName(m.name, m.class) or m.name
      t:SetText(name .. ": " .. m.text)
    end
    t:Show()
    y = y + ROW
  end
  for i = lines + 1, #f.members do f.members[i]:Hide() end
  -- (the hud round) a secure button anchored to the frame (the step's item, a quest's) makes the frame's size anchoring-
  -- restricted in a fight: it holds still, laid out again at the fight's end (SF.OnRegen)
  local anchored = fighting() and f.item ~= nil and f.item:IsShown()
  if fighting() and not anchored then for _, b in ipairs(f.qitems) do if b:IsShown() then anchored = true end end end
  if anchored then SF.pendingItem = true
  elseif f:GetHeight() ~= y + PAD then f:SetHeight(y + PAD); arrowFollows() end
  SF.RefreshItem(steps[1])
  SF.RefreshQuestItems()
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
    f.time:SetShown(not STOP)
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
-- the fight if in one. Back at once when the setting or the step frame goes off.
-- (the windows round) Out of sight its lines still took a click where they stood, as the game's own fade leaves them;
-- so its scale goes to a hundredth beside the alpha: a C-side property that writes nothing into the frame's tables, and
-- that no OnSizeChanged or OnShow (ObjectiveTrackerContainer.lua:29-37) nor the managed frame's OnHide
-- (ManagedFrameSystem.lua:21-23) hears, so the container's layout never runs for it. The frame stays shown: the game's
-- logic, its item buttons and autoQuestWatch are untouched. The scale it had is kept for the session and put back with
-- the alpha; Edit Mode's enter ("EditMode.Enter", EditModeManager.lua:105) puts both back so the player can place it,
-- its exit (:124) and EDIT_MODE_LAYOUTS_UPDATED take it out of sight again. Alpha and scale are all it is asked
local function tracker()
  local t = ObjectiveTrackerFrame
  return type(t) == "table" and type(t.SetAlpha) == "function" and type(t.GetAlpha) == "function" and t or nil
end
local function scaleOf(t)
  if type(t.GetScale) ~= "function" then return nil end
  local ok, sc = pcall(t.GetScale, t)
  sc = ok and QB.Plain(sc) or nil
  return type(sc) == "number" and sc or nil
end
-- (the review of the windows round) the frame type's own SetScale, never a Lua override over it: ObjectiveTrackerFrame is
-- an Edit Mode system (Blizzard_ObjectiveTracker.xml:3) whose OnSystemLoad keeps the C method as SetScaleBase and puts
-- SetScaleOverride in SetScale (EditModeSystemTemplates.lua:9-11), which moves its points, runs ManageFramePositions and
-- the tracker's Update (:117-145) as its caller: the tracker's item buttons would carry QuestBank's taint. nil where no
-- C method can be told apart (then the alpha alone)
local function baseSetScale(t)
  local own = rawget(t, "SetScale")
  if own == nil then return type(t.SetScale) == "function" and t.SetScale or nil end
  local base = rawget(t, "SetScaleBase")
  if type(base) == "function" then return base end
  local mt = getmetatable(t)
  local idx = type(mt) == "table" and mt.__index or nil
  if type(idx) == "table" and type(idx.SetScale) == "function" and idx.SetScale ~= own then return idx.SetScale end
  return nil
end
-- the hundredth, as the client reads it back: a frame's scale is a 32-bit float there (0.01 is 0.0099999998)
local function isOut(sc) return type(sc) == "number" and math.abs(sc - OUT_SCALE) < 0.001 end
function SF.Tracker()
  local t = tracker()
  if not t then return end
  local f = SF.frame
  local want = settings().hideTracker ~= false and f ~= nil and f:IsShown() and not trackerEditing and true or false
  if fighting() then trackerWait = true return end
  trackerWait = false
  local setScale = baseSetScale(t)
  if want then
    if not trackerHooked and type(hooksecurefunc) == "function" then
      trackerHooked = true
      hooksecurefunc(t, "SetAlpha", function(self, a)
        if not trackerOut or a == 0 then return end
        if fighting() then trackerWait = true else self:SetAlpha(0) end
      end)
    end
    if not trackerOut and not settings().trackerTold then SF.notePending = true end
    if not trackerOut then
      -- (its corner at its own size, before it shrinks: the step frame's default place stays on it)
      local W = UIParent:GetWidth() or 1920
      local right, top = trackerCorner(W)
      if right then trackerCut = { W - right, top } end
    end
    trackerOut = true
    if t:GetAlpha() ~= 0 then t:SetAlpha(0) end
    -- (the scale it has kept, never the hundredth it already is: every SF.Apply while it is out asks again)
    local sc = setScale and scaleOf(t)
    if sc and not isOut(sc) then trackerScale = sc; pcall(setScale, t, OUT_SCALE) end
  elseif trackerOut then
    trackerOut = false
    t:SetAlpha(1)
    if setScale and trackerScale and isOut(scaleOf(t)) then pcall(setScale, t, trackerScale) end
  end
end
SF.TrackerOut = function() return trackerOut end
-- /cute diag's words for the game's tracker: out of sight or not, its alpha and scale as the client reads them now,
-- the scale kept to put back, and whether Edit Mode has it
function SF.TrackerDiag()
  local t = tracker()
  if not t then return "tracker: none" end
  local okA, a = pcall(t.GetAlpha, t)
  a = okA and QB.Plain(a) or nil
  local sc = scaleOf(t)
  return string.format("tracker: %s, alpha %s, scale %s, kept %s%s%s", trackerOut and "out of sight" or "shown",
    type(a) == "number" and string.format("%.2f", a) or "?", sc and string.format("%.2f", sc) or "?",
    trackerScale and string.format("%.2f", trackerScale) or "none", trackerEditing and ", in Edit Mode" or "",
    trackerWait and ", waiting for the fight's end" or "")
end
-- Edit Mode, and the layouts it applies (SF.Init registers them)
local function editMode(on)
  trackerEditing = on
  SF.Tracker()
end

-- shown while the Guide and the frame are on, or a welcome waits
function SF.Apply()
  local s = settings()
  local want = (s.on and s.frame) or QB:Settings().welcome ~= nil
  if want and not SF.frame then SF.frame = build() end
  local f = SF.frame
  if not f then return end
  place(f)
  f.__dragOff = locked() or nil -- (the drag script reads the lock; the harness reads this flag)
  if STOP and f.qbBackdrop ~= (s.backdrop == true) then
    -- (the stop look stands on the world; "Backdrop behind the step frame" brings the host's flat one back)
    f.qbBackdrop = s.backdrop == true
    local sk = QB.Skin
    if f.qbBackdrop and sk and sk.Backdrop then sk.Backdrop(f) elseif f.SetBackdrop then f:SetBackdrop(nil) end
  end
  f:SetShown(want and true or false)
  lastVer = -1
  if not fighting() then f.qLayout = nil end -- (laid out again, out of a fight)
  if want then SF.Refresh() else SF.RefreshItem(nil); SF.RefreshQuestItems() end
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
  for _, b in ipairs(f.qitems or {}) do
    if fighting() then SF.pendingItem = true else b:SetScale(sc) end
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
  -- (the layout round) a host's one lock where it has one (QB.SetLayoutLocked: Cute's, for every piece on screen)
  if type(QB.SetLayoutLocked) == "function" then
    items[#items + 1] = { locked() and "Unlock frames" or "Lock frames", function() QB.SetLayoutLocked(not locked()); SF.Apply() end }
  else
    items[#items + 1] = { set.locked and "Unlock" or "Lock", function() set.locked = not set.locked; SF.Apply() end }
  end
  for _, sc in ipairs(SCALES) do
    items[#items + 1] = { string.format("Scale: %d%%%s", sc * 100, (set.scale or 1) == sc and "  (now)" or ""), function() SF.SetScale(sc) end }
  end
  items[#items + 1] = { "Hide (Settings brings it back)", function() set.frame = false; SF.Apply() end }
  if STOP then items[#items + 1] = { set.backdrop and "No backdrop" or "Backdrop behind this frame", function() set.backdrop = not set.backdrop or nil; SF.Apply() end } end
  -- the game's quest tracker: back, or out of sight again while the frame shows (Settings has the same row)
  if SF.noteUntil or SF.notePending then set.trackerTold = true end
  SF.noteUntil, SF.notePending = nil, nil -- (the menu found: the note has done its work)
  if trackerOut then
    items[#items + 1] = { "Show the game's quest tracker", function() set.hideTracker = false; SF.Tracker(); lastVer = -1; SF.Refresh() end }
  elseif tracker() and set.hideTracker == false then
    items[#items + 1] = { "Hide the game's quest tracker while this shows", function() set.hideTracker = true; SF.Tracker(); lastVer = -1; SF.Refresh() end }
  end
  -- (the launch round) a line in chat for each hand-in, and (the review round) for a quest complete or dropped, only
  -- when asked for: Core.lua reads sayXP. Named as Settings names it (QuestBank's Guide section, Cute's Quests)
  local qs = QB:Settings()
  items[#items + 1] = { "Say XP after each hand-in: " .. (qs.sayXP == true and "on" or "off"), function() qs.sayXP = qs.sayXP ~= true end }
  items[#items + 1] = { "Settings", function() QB.UI:Open(5) end }
  QB.UI:ShowMenu("The next step", items)
end

function SF:Init()
  -- (the windows round) Edit Mode's enter and exit, as camelot's MainMenuBarEndCaps.lua:7-11 hears them, and its
  -- layouts applied: the game's quest tracker back while it is open, out of sight again after (SF.Tracker)
  if type(EventRegistry) == "table" and type(EventRegistry.RegisterCallback) == "function" then
    pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Enter", QB.Safe(function() editMode(true) end, "step frame: edit mode"), SF)
    pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit", QB.Safe(function() editMode(false) end, "step frame: edit mode"), SF)
  end
  if not SF.events then
    SF.events = CreateFrame("Frame")
    pcall(SF.events.RegisterEvent, SF.events, "EDIT_MODE_LAYOUTS_UPDATED")
    SF.events:SetScript("OnEvent", QB.Safe(function() if trackerOut then SF.Tracker() end end, "step frame: edit mode"))
  end
  SF.Apply()
end

-- (the layout round) the frame as a host's layout mode moves it (QB.Movers: Remind.lua says what each part does): kept
-- by its centre (guide.x/y, in its own units: its scale times them is UIParent's); its scale is SF.SetScale's, its
-- centre kept; secure, for the quests' item buttons anchored to it
QB.Movers = QB.Movers or {}
local function screen() return UIParent:GetWidth() or 1920, UIParent:GetHeight() or 1080 end
local function frameSize()
  local f, sc = SF.frame, settings().scale or 1
  return WIDTH * sc, ((f and f:GetHeight()) or (PAD * 2 + ROW1 + ROW * 3)) * sc
end
local function validScale(k)
  k = tonumber(k) or 1
  return math.max(0.5, math.min(2, k))
end
local function placed()
  local f = SF.frame
  if not f then return end
  place(f)
  arrowFollows()
end
QB.Movers.step = {
  key = "step", name = "Step frame", order = 1, secure = true,
  frame = function() return SF.frame end,
  on = function() local s = settings(); return s.on == true and s.frame == true end,
  switch = function(on) settings().frame = on and true or false; SF.Apply() end,
  rect = function()
    local s, f = settings(), SF.frame
    local W, H = screen()
    local w, h = frameSize()
    local sc = s.scale or 1
    if type(s.x) == "number" and type(s.y) == "number" then
      local cx, cy = W / 2 + s.x * sc, H / 2 + s.y * sc
      return cx - w / 2, cy + h / 2, w, h
    end
    -- (its default place, as place() last put it: its middle across, its top down from the screen's top)
    local mid, top = (f and f.qbX) or 0, (f and f.qbTop) or TOP_Y
    return W / 2 + mid - w / 2, H - top, w, h
  end,
  move = function(left, top)
    local s = settings()
    local W, H = screen()
    local w, h = frameSize()
    local sc = s.scale or 1
    s.x, s.y = (left + w / 2 - W / 2) / sc, (top - h / 2 - H / 2) / sc
    placed()
  end,
  scale = function(k)
    local s = settings()
    k = validScale(k)
    local old = s.scale or 1
    if type(s.x) == "number" and type(s.y) == "number" then s.x, s.y = s.x * old / k, s.y * old / k end
    SF.SetScale(k)
    placed()
  end,
  get = function()
    local s = settings()
    local sc = s.scale or 1
    if type(s.x) == "number" and type(s.y) == "number" then return { point = "CENTER", x = s.x * sc, y = s.y * sc, scale = sc } end
    return { scale = sc }
  end,
  set = function(p)
    local s = settings()
    local sc = validScale(type(p) == "table" and p.scale or 1)
    local ok = type(p) == "table" and p.point == "CENTER" and tonumber(p.x) and tonumber(p.y)
    s.x, s.y = ok and p.x / sc or nil, ok and p.y / sc or nil
    SF.SetScale(sc)
    placed()
  end,
}
