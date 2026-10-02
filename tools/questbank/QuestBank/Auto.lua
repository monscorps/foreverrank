-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank Auto: the two conveniences Questie users know, off until you switch them on in Settings.
--   Accept for me: at a quest giver, take the quests offered that are for you (faction, class, race),
--     the ones a party member shares, and an escort a party member starts. Not repeatable or grey ones,
--     not in a place you skipped, not when the log is full, and while you bank not a quest the Plan page
--     would cut (next to nothing on the day, leading nowhere). Hold Shift and QuestBank keeps its hands off.
--   Hand in for me: at the quest taker, hand in what is finished when there is nothing to choose (one
--     reward or none) and nothing to pay. Smart about banking: while you bank, only what the Plan page
--     says to hand in now (quests you cut, ones that pay next to nothing on the day, and the step you hand
--     in to bank a better one); a quest QuestBank can't value waits for you. Questing and the rush hand
--     in everything.
-- Every decision and click runs a moment after the game's own window opens, after Core has read the XP
-- the window shows, so the number the game reports is the one the decision uses.
local _, QB = ...
local Auto = {}
QB.Auto = Auto
local Q = QB.Quest

local function on(key) return QB:Settings()[key] == true end
-- the quest the window shows: 0 when there is none, or when the client hides the id (a secret value)
local function qid()
  local id = GetQuestID and GetQuestID()
  if not id or (issecretvalue and issecretvalue(id)) then return 0 end
  return id
end

local function byHand() return (IsShiftKeyDown and IsShiftKeyDown()) and true or false end
local function later(where, fn) C_Timer.After(0.05, QB.Safe(fn, "auto: " .. where)) end
local function banking() return QB:Mode() == "lock" end
local function level() return QB.state.level or 1 end
local function logFull() return (QB.state.logCount or 0) >= QB.LOG_SLOTS end

-- take this quest? A quest QuestBank knows nothing about is new to Forever: yes. Known: for you, not in a
-- place you skipped, and while you bank not one the Plan page would cut.
function Auto.MayAccept(id, trivial, repeatable)
  if trivial or repeatable or logFull() then return false end
  local q = id and id ~= 0 and Q.Get(id)
  if not q then return true end
  if not Q.ForMe(q) or QB:SkipsQuest(q) then return false end
  if banking() and QB.Model.XpAt(q, level()) < 500 * QB.Scale(level()) and not QB:Upgrade(q) then return false end
  return true
end

-- hand this one in now? Questing and the rush: yes. Banking: only what the Plan page says to hand in now.
function Auto.MayTurnIn(id)
  if not on("autoTurnIn") then return false end
  if not banking() then return true end
  if not id or id == 0 then return false end
  if QB:IsCut(id) then return true end
  local q = Q.Get(id)
  if not q then return false end -- unknown to QuestBank: it stays banked, you decide
  if q.xpUnknown and not q.liveFull then return false end -- no number to judge by: the same
  if QB.Model.XpAt(q, level()) < 500 * QB.Scale(level()) then return true end -- next to nothing on the day
  if QB:Upgrade(q) then return true end -- hand in now, bank the later step
  return false
end

-- at an NPC: a finished quest to hand in first, else the first quest offered that you should take
function Auto.Greeting(event)
  if byHand() then return end
  local accept, turnIn = on("autoAccept"), on("autoTurnIn")
  if not accept and not turnIn then return end
  later("greeting", function()
    if byHand() then return end
    if event == "GOSSIP_SHOW" and C_GossipInfo then
      if turnIn and C_GossipInfo.GetActiveQuests and C_GossipInfo.SelectActiveQuest then
        for _, info in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
          if info.isComplete and info.questID and Auto.MayTurnIn(info.questID) then C_GossipInfo.SelectActiveQuest(info.questID) return end
        end
      end
      if accept and C_GossipInfo.GetAvailableQuests and C_GossipInfo.SelectAvailableQuest then
        for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
          if info.questID and Auto.MayAccept(info.questID, info.isTrivial, info.repeatable) then C_GossipInfo.SelectAvailableQuest(info.questID) return end
        end
      end
    elseif event == "QUEST_GREETING" then
      if turnIn and GetNumActiveQuests and GetActiveTitle and SelectActiveQuest then
        for i = 1, GetNumActiveQuests() or 0 do
          local _, complete = GetActiveTitle(i)
          local id = GetActiveQuestID and GetActiveQuestID(i)
          if complete and Auto.MayTurnIn(id) then SelectActiveQuest(i) return end
        end
      end
      if accept and GetNumAvailableQuests and GetAvailableQuestInfo and SelectAvailableQuest then
        for i = 1, GetNumAvailableQuests() or 0 do
          local trivial, _, repeatable, _, id = GetAvailableQuestInfo(i)
          if Auto.MayAccept(id, trivial, repeatable) then SelectAvailableQuest(i) return end
        end
      end
    end
  end)
end

-- the quest window: take it, unless the game would first ask you about PvP
function Auto.Detail()
  if not on("autoAccept") or byHand() then return end
  local id = qid()
  if id == 0 then return end
  later("accept", function()
    if byHand() or qid() ~= id then return end
    if QuestGetAutoAccept and QuestGetAutoAccept() then return end -- the game took it already
    if QuestFlagsPVP and QuestFlagsPVP() then return end -- the game asks first; so should you
    local repeatable = C_QuestLog and C_QuestLog.IsRepeatableQuest and C_QuestLog.IsRepeatableQuest(id)
    local trivial = C_QuestLog and C_QuestLog.IsQuestTrivial and C_QuestLog.IsQuestTrivial(id)
    if Auto.MayAccept(id, trivial, repeatable) then AcceptQuest() end
  end)
end

-- the progress window: hand it in when it is finished and QuestBank agrees, judged once the window is read
function Auto.Progress()
  if byHand() or not on("autoTurnIn") then return end
  local id = qid()
  later("hand in", function()
    if byHand() or qid() ~= id or not Auto.MayTurnIn(id) then return end
    if IsQuestCompletable and IsQuestCompletable() then CompleteQuest() end
  end)
end

-- the reward window: finish when there is nothing to choose and nothing to pay
function Auto.Complete()
  if byHand() or not on("autoTurnIn") then return end
  local id = qid()
  later("reward", function()
    if byHand() or qid() ~= id or not Auto.MayTurnIn(id) then return end
    if GetQuestMoneyToGet and (GetQuestMoneyToGet() or 0) > 0 then return end -- it costs money: the game asks
    local choices = (GetNumQuestChoices and GetNumQuestChoices()) or 0
    if choices <= 1 then GetQuestReward(choices) end -- one reward: take it; none: finish; several: yours to pick
  end)
end

-- a party member started a quest (an escort, mostly): say yes while the log has room. The server decides.
function Auto.Confirm(who, title)
  if not on("autoAccept") or byHand() or logFull() then return end
  later("join", function()
    if byHand() or logFull() then return end
    if ConfirmAcceptQuest then ConfirmAcceptQuest() end
    if StaticPopup_Hide then StaticPopup_Hide("QUEST_ACCEPT"); StaticPopup_Hide("QUEST_ACCEPT_LOG_FULL") end
    QB:Print(string.format("Said yes to %s, which %s started.", title or "a quest", who or "a party member"))
  end)
end

-- true when Auto will answer the prompt itself
function Auto.WillJoin()
  return on("autoAccept") and not byHand() and not logFull()
end

function Auto.OnEvent(event, a1, a2)
  if event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then Auto.Greeting(event)
  elseif event == "QUEST_DETAIL" then Auto.Detail()
  elseif event == "QUEST_PROGRESS" then Auto.Progress()
  elseif event == "QUEST_COMPLETE" then Auto.Complete()
  elseif event == "QUEST_ACCEPT_CONFIRM" then Auto.Confirm(a1, a2) end
end
