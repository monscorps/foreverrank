-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank's timers: how long each level took, how long each quest took, and a small strip that shows the time at
-- this level, the oldest quest in your log and the hand-in run while one is on. Kept per character in
-- QuestBankDB.chars[key].timer:
--   levels[lvl] = { at = time() you reached it, played = seconds logged in at that level }
--   quests[qid] = { a = accepted (time()), d = handed in,    (the newest 300; the oldest handed-in go first)
--                   w = seconds of work at its objectives, k = looks it moved in, c = first complete (time()), lv = level then }
--   The work is measured from Discover.lua's look of the log (Timer.Tick): what the quest minutes estimate (Model.lua,
--   D.DO) is checked against it for this character's pace (Timer.SpeedFactor), and players' uploads bring it to the
--   next release's estimates (probe_pull.py's disc.json "dur"). Ids and numbers only
-- Only reads and its own frame: nothing of the game's is touched. The strip is off until Settings turns it on
-- (settings.clock.show, or a context profile's clockShow: QB:Opt), and its ticker only runs while it is shown.
local _, QB = ...
if QB.dormant then return end
local Timer = {}
QB.Timer = Timer

local QUESTS = 300
Timer.QUESTS = QUESTS

local plain = QB.Plain
local function now() return GetTime and GetTime() or 0 end
local function clock() return time and time() or 0 end

local function db()
  QuestBankDB = QuestBankDB or {}
  QuestBankDB.chars = QuestBankDB.chars or {}
  local key = QB:CharKey()
  local c = QuestBankDB.chars[key]
  if type(c) ~= "table" then c = {}; QuestBankDB.chars[key] = c end
  local t = c.timer
  if type(t) ~= "table" then t = { levels = {}, quests = {} }; c.timer = t end
  if type(t.levels) ~= "table" then t.levels = {} end
  if type(t.quests) ~= "table" then t.quests = {} end
  return t
end
Timer.DB = db

-- "1h 12m", "8m", "45s"
function Timer.Span(sec)
  sec = math.max(0, math.floor((sec or 0) + 0.5))
  if sec < 60 then return sec .. "s" end
  local m = math.floor(sec / 60)
  if m < 60 then return m .. "m" end
  return string.format("%dh %02dm", math.floor(m / 60), m % 60)
end

-- the seconds logged in at this level so far: what was saved plus this session's run
local sessionStart, sessionLevel
local function level()
  local l = plain(QB.state and QB.state.level)
  if type(l) ~= "number" and UnitLevel then l = plain(UnitLevel("player")) end
  return type(l) == "number" and l or 1
end

local function flush()
  if not sessionStart or not sessionLevel then return end
  local t = db()
  local L = t.levels[sessionLevel]
  if type(L) ~= "table" then L = { at = clock() }; t.levels[sessionLevel] = L end
  L.played = (L.played or 0) + (now() - sessionStart)
  sessionStart = now()
end

function Timer.LevelTime(lvl)
  lvl = lvl or level()
  local L = db().levels[lvl]
  local played = L and L.played or 0
  if sessionStart and sessionLevel == lvl then played = played + (now() - sessionStart) end
  return played
end

-- seconds a quest took (handed in), or has taken so far (still in the log); nil when nothing was noted
function Timer.QuestTime(qid)
  local q = db().quests[qid]
  if not q or not q.a then return nil end
  return (q.d or clock()) - q.a, q.d ~= nil
end

-- (keep: the quest just noted, never the one to go)
local function trim(t, keep)
  local n = 0
  for _ in pairs(t.quests) do n = n + 1 end
  while n > QUESTS do
    local oldest, at
    for id, q in pairs(t.quests) do
      local when = q.d or q.a or 0
      if q.d and id ~= keep and (not at or when < at) then oldest, at = id, when end
    end
    if not oldest then -- nothing handed in to drop: the oldest accepted goes
      for id, q in pairs(t.quests) do if id ~= keep and (not at or (q.a or 0) < at) then oldest, at = id, q.a or 0 end end
    end
    t.quests[oldest] = nil
    n = n - 1
  end
end

-- the work at a quest's objectives: each look of the log where objectives moved (Discover.lua) brings the seconds since
-- the last such look, TICK_MAX at most (a walk, a break or a logout between two counts no more), shared equally among
-- the quests that moved in it (ids[1..n]): w on each one's row, and 1 to k
local TICK_MAX = 90
Timer.TICK_MAX = TICK_MAX
local lastTick
function Timer.Tick(ids, n)
  n = n or #ids
  if n <= 0 then return end
  local t = now()
  local dt = lastTick and math.max(0, math.min(t - lastTick, TICK_MAX)) or 0
  lastTick = t
  local share, rows, added = dt / n, db().quests, false
  for i = 1, n do
    local id = ids[i]
    local q = rows[id]
    if type(q) ~= "table" then q = {}; rows[id] = q; added = id end
    q.w = (q.w or 0) + share
    q.k = (q.k or 0) + 1
  end
  if added then trim(db(), added) end
  -- (/qb trace: whether the work is measured in play, for a report)
  if QB.tracing and QB.Trace then QB.Trace("timer: %d quest(s) moved, %.0f s of work each", n, share) end
end

-- the first time a quest is complete: when, and at what level (its work is whole: the pace below counts it)
local paceVer = 0
function Timer.Done(id)
  local t = db()
  local q = t.quests[id]
  if type(q) == "table" and q.c then return end
  if type(q) ~= "table" then q = {}; t.quests[id] = q; trim(t, id) end
  q.c, q.lv = clock(), level()
  paceVer = paceVer + 1
  if QB.tracing and QB.Trace then QB.Trace("timer: quest %d complete, %.0f s of work in %d looks", id, q.w or 0, q.k or 0) end
end

-- this character's pace: the median of the work measured against the work estimated (D.DO, not an estimate from the
-- zone) over the last PACE_N quests completed with work measured, from 0.5 to 2; 1 with fewer than PACE_MIN. Not a
-- dungeon's quest (its estimate is the run, the work measured its objectives' ticks) nor a group quest (the estimate
-- is a party's, the work may be one player's). Worked out again after a completion, into tables kept for it
local PACE_N, PACE_MIN = 20, 3
Timer.PACE_N, Timer.PACE_MIN = PACE_N, PACE_MIN
local paceAt, paceKey, pace = -1, nil, 1
local paceRows, paceRatio = {}, {}
local function byNewest(a, b) return a[1] > b[1] end
function Timer.SpeedFactor()
  local key = QB:CharKey()
  if paceAt == paceVer and paceKey == key then return pace end
  paceAt, paceKey, pace = paceVer, key, 1
  local M = QB.Model
  local n = 0
  local Qs = QB.Data and QB.Data.Q
  for id, q in pairs(db().quests) do
    local r = Qs and Qs[id]
    if type(q) == "table" and q.c and q.w and q.w > 0 and M and M.Do and r and r[10] % 4 == 0 then
      local _, work, est = M.Do(id)
      if work and work > 0 and not est then
        n = n + 1
        local r = paceRows[n]
        if not r then r = {}; paceRows[n] = r end
        r[1], r[2] = q.c, (q.w / 60) / work
      end
    end
  end
  for k = #paceRows, n + 1, -1 do paceRows[k] = nil end
  if n < PACE_MIN then return pace end
  table.sort(paceRows, byNewest)
  local m = math.min(n, PACE_N)
  for k = 1, m do paceRatio[k] = paceRows[k][2] end
  for k = #paceRatio, m + 1, -1 do paceRatio[k] = nil end
  table.sort(paceRatio)
  local mid = m % 2 == 1 and paceRatio[(m + 1) / 2] or (paceRatio[m / 2] + paceRatio[m / 2 + 1]) / 2
  pace = math.max(0.5, math.min(2, mid))
  return pace
end

-- the XP gained since login, counted on every XP update (a level-up carries the rest of the old bar)
local gain, lastXP, lastMax, since = 0, nil, nil, nil
local function xpNow()
  local x = UnitXP and plain(UnitXP("player")) or nil
  local m = UnitXPMax and plain(UnitXPMax("player")) or nil
  return type(x) == "number" and x or nil, type(m) == "number" and m or nil
end
function Timer.NoteXP()
  local x, m = xpNow()
  if not x then return end
  if lastXP then
    if x >= lastXP then gain = gain + (x - lastXP) else gain = gain + ((lastMax or lastXP) - lastXP) + x end
  end
  lastXP, lastMax = x, m
  since = since or now()
end
-- XP an hour this session: nil until ten minutes have passed (a first quest would read as thousands an hour)
function Timer.XPPerHour()
  if not since then return nil end
  local secs = now() - since
  if secs < 600 then return nil end
  return gain / (secs / 3600)
end
function Timer.SessionXP() return gain end

-- the quests' XP this session (their rewards at the hand-in; the catalog's figure where the game hides it) an hour, as
-- it stood at the last hand-in ten minutes into the session or later: the floor of XP a minute reads it (Model.lua's
-- Floor), so the floor moves at a hand-in, a real event, and never with a kill or the clock. nil until then
local questGain, questRate = 0, nil
function Timer.QuestXPPerHour() return questRate end

function Timer.Record(event, a1, a2)
  if event == "PLAYER_XP_UPDATE" then Timer.NoteXP(); return end
  if event == "PLAYER_LEVEL_UP" then
    local lvl = plain(a1)
    if type(lvl) ~= "number" then return end
    flush()
    local t = db()
    if type(t.levels[lvl]) ~= "table" then t.levels[lvl] = { at = clock(), played = 0 } end
    local took = sessionLevel and Timer.LevelTime(sessionLevel) or nil
    sessionLevel, sessionStart = lvl, now()
    if QB.state then QB.state.level = lvl end
    if took and took > 0 and QB:Settings().clockLevelMsg ~= false then
      QB:Print(string.format("Level %d in %s of play at level %d.", lvl, Timer.Span(took), lvl - 1))
    end
  elseif event == "QUEST_ACCEPTED" then
    local id = plain(a2 or a1)
    if type(id) ~= "number" then return end
    local t = db()
    t.quests[id] = { a = clock() }
    trim(t, id)
  elseif event == "QUEST_TURNED_IN" then
    local id = plain(a1)
    if type(id) ~= "number" then return end
    local q = db().quests[id]
    if q and not q.d then q.d = clock() end
    -- (the payload: questID, xpReward, moneyReward; QuestLogDocumentation.lua's QuestTurnedIn)
    local x = plain(a2)
    if type(x) ~= "number" then
      local v = QB.Quest and QB.Quest.Get(id)
      x = v and QB.Model and QB.Model.XpAt and QB.Model.XpAt(v, level()) or 0
    end
    questGain = questGain + x
    since = since or now()
    local secs = now() - since
    if secs >= 600 then questRate = questGain / (secs / 3600) end
  elseif event == "PLAYER_ENTERING_WORLD" then
    sessionLevel, sessionStart = level(), now()
    if not since then Timer.NoteXP() end
    local t = db()
    if type(t.levels[sessionLevel]) ~= "table" then t.levels[sessionLevel] = { at = clock(), played = 0 } end
  elseif event == "PLAYER_LOGOUT" then
    flush()
  elseif event == "ZONE_CHANGED_NEW_AREA" or event == "GROUP_ROSTER_UPDATE" then
    Timer.Apply() -- a context profile may switch the strip on or off here
  end
  if Timer.frame and Timer.frame:IsShown() then Timer.Update() end
end

-- the oldest quest still in the log that this character accepted since the timers began (a row the work alone made,
-- Timer.Tick for a quest held before the timers began, has no accept time: not one of them)
local function oldestOpen()
  local best, at
  local log = QB.state and QB.state.log or {}
  for id, q in pairs(db().quests) do
    if type(q) == "table" and q.a and not q.d and log[id] and (not at or q.a < at) then best, at = id, q.a end
  end
  return best, at
end

function Timer.Text()
  local parts = { string.format("Lvl %d \194\183 %s", level(), Timer.Span(Timer.LevelTime())) }
  local id, at = oldestOpen()
  if id then parts[#parts + 1] = string.format("quest %s", Timer.Span(clock() - at)) end
  local run = QB.Run and QB.Run.Get()
  if run and run.started then
    local n = 0
    for _ in pairs(run.done or {}) do n = n + 1 end
    parts[#parts + 1] = string.format("run %s, %d q", Timer.Span(clock() - run.started), n)
  end
  return table.concat(parts, " \194\183 ")
end

function Timer.Update()
  local f = Timer.frame
  if not f then return end
  f.text:SetText(Timer.Text())
  f:SetWidth(math.max(120, (f.text:GetStringWidth() or 100) + 20))
end

local function schedule()
  C_Timer.After(1, QB.Safe(function()
    local f = Timer.frame
    if not (f and f:IsShown()) then return end
    Timer.Update()
    schedule()
  end, "timer strip"))
end

local function build()
  local f = CreateFrame("Frame", "QuestBankTimer", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(220, 24)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0, 0, 0, 0.7)
  end
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.text:SetPoint("CENTER")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", QB.Safe(function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint(1)
    local c = QB:Settings().clock
    c.x, c.y = x, y
  end, "timer strip"))
  f:SetScript("OnMouseUp", QB.Safe(function(_, button)
    if button == "RightButton" then Timer.Set(false) end
  end, "timer strip"))
  f:SetScript("OnShow", function() Timer.Update(); schedule() end)
  local c = QB:Settings().clock
  f:ClearAllPoints()
  if c.x and c.y then f:SetPoint("CENTER", UIParent, "CENTER", c.x, c.y) else f:SetPoint("TOP", UIParent, "TOP", 0, -80) end
  f:Hide()
  return f
end

-- the strip follows the setting as it applies where you are (QB:Opt("clockShow")); Set writes the plain setting
function Timer.Apply()
  local want = QB:Opt("clockShow") == true
  if want and not Timer.frame then Timer.frame = build() end
  if Timer.frame then Timer.frame:SetShown(want) end
end

function Timer.Set(on)
  QB:Settings().clock.show = on and true or false
  Timer.Apply()
end

function Timer:Init()
  if self.eventFrame then return end
  local f = CreateFrame("Frame")
  self.eventFrame = f
  f:SetScript("OnEvent", QB.Safe(function(_, event, a1, a2) Timer.Record(event, a1, a2) end, "timers"))
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "PLAYER_LOGOUT", "PLAYER_XP_UPDATE",
                       "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE" }) do
    pcall(f.RegisterEvent, f, e)
  end
  Timer.Apply()
end
