-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank Auto: the two conveniences Questie users know, off until you switch them on in Settings.
--   Accept for me: at a quest giver, take the quests offered that are for you (faction, class, race), and
--     join an escort a party member starts. Hold Shift at the NPC and QuestBank keeps its hands off.
--   Hand in for me: at the quest taker, hand in what is finished when there is nothing to choose (one
--     reward or none); a reward you must pick waits for you. Smart about banking: while you bank, only
--     what the Plan page says to hand in now (quests you cut, ones that pay next to nothing on the day,
--     and the step you hand in to bank a better one). Questing and the rush hand in everything.
-- Everything runs a moment after the game's own window opens, so the XP it shows is read first.
local _, QB = ...
local Auto = {}
QB.Auto = Auto
local Q = QB.Quest

local function on(key) return QB:Settings()[key] == true end
local function byHand() return (IsShiftKeyDown and IsShiftKeyDown()) and true or false end
local function later(where, fn) C_Timer.After(0.05, QB.Safe(fn, "auto: " .. where)) end

-- a quest QuestBank knows nothing about is new to Forever: take it
local function forMe(id)
  local q = id and id ~= 0 and Q.Get(id)
  return q == nil or Q.ForMe(q)
end

-- hand this one in now? Questing and the rush: yes. Banking: only what the Plan page says to hand in now.
function Auto.MayTurnIn(id)
  if not on("autoTurnIn") then return false end
  if QB:Mode() ~= "lock" then return true end
  if not id or id == 0 then return false end
  if QB:IsCut(id) then return true end
  local q = Q.Get(id)
  if not q then return false end -- unknown to QuestBank: it stays banked, you decide
  local level = QB.state.level or 1
  if QB.Model.XpAt(q, level) < 500 * QB.Scale(level) then return true end -- next to nothing on the day
  if QB:Upgrade(q) then return true end -- hand in now, bank the later step
  return false
end

-- at an NPC: a finished quest to hand in first, else the first quest offered that is for you
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
          if info.questID and forMe(info.questID) then C_GossipInfo.SelectAvailableQuest(info.questID) return end
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
      if accept and GetNumAvailableQuests and SelectAvailableQuest then
        for i = 1, GetNumAvailableQuests() or 0 do
          local id = GetAvailableQuestInfo and select(5, GetAvailableQuestInfo(i))
          if forMe(id) then SelectAvailableQuest(i) return end
        end
      end
    end
  end)
end

-- the quest window: take it
function Auto.Detail()
  if not on("autoAccept") or byHand() then return end
  local id = GetQuestID and GetQuestID() or 0
  if id == 0 or not forMe(id) then return end
  if QuestGetAutoAccept and QuestGetAutoAccept() then return end -- the game took it already
  later("accept", function()
    if byHand() or (GetQuestID and GetQuestID()) ~= id then return end
    AcceptQuest()
  end)
end

-- the progress window: hand it in when it is finished and QuestBank agrees
function Auto.Progress()
  local id = GetQuestID and GetQuestID() or 0
  if byHand() or not Auto.MayTurnIn(id) then return end
  later("hand in", function()
    if byHand() or (GetQuestID and GetQuestID()) ~= id then return end
    if IsQuestCompletable and IsQuestCompletable() then CompleteQuest() end
  end)
end

-- the reward window: finish when there is nothing to choose
function Auto.Complete()
  local id = GetQuestID and GetQuestID() or 0
  if byHand() or not Auto.MayTurnIn(id) then return end
  later("reward", function()
    if byHand() or (GetQuestID and GetQuestID()) ~= id then return end
    local choices = (GetNumQuestChoices and GetNumQuestChoices()) or 0
    if choices <= 1 then GetQuestReward(choices) end -- one reward: take it; none: finish; several: yours to pick
  end)
end

-- a party member started a quest (an escort, mostly): join it while the log has room
function Auto.Confirm(who, title)
  if not on("autoAccept") or byHand() then return end
  if (QB.state.logCount or 0) >= QB.LOG_SLOTS then return end
  later("join", function()
    if byHand() then return end
    if ConfirmAcceptQuest then ConfirmAcceptQuest() end
    if StaticPopup_Hide then StaticPopup_Hide("QUEST_ACCEPT"); StaticPopup_Hide("QUEST_ACCEPT_LOG_FULL") end
    QB:Print(string.format("Joined %s, which %s started.", title or "a quest", who or "a party member"))
  end)
end

function Auto.OnEvent(event, a1, a2)
  if event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then Auto.Greeting(event)
  elseif event == "QUEST_DETAIL" then Auto.Detail()
  elseif event == "QUEST_PROGRESS" then Auto.Progress()
  elseif event == "QUEST_COMPLETE" then Auto.Complete()
  elseif event == "QUEST_ACCEPT_CONFIRM" then Auto.Confirm(a1, a2) end
end
