-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank Auto: the two conveniences Questie users know, off until you switch them on in Settings.
--   Accept for me: a choice (5.4.4; it was a switch that took every quest that wasn't grey): Off; Quests on my route
--     (your pick-up list, and the next steps of the chains you are on or picked); or Quests worth taking (those, and any
--     other the planner thinks worth it: never grey, never under its low-value line, Model.lua's CHEAP). With Quests
--     worth taking, one outside your route is taken or left in the game's quest window for you, as you choose
--     (autoAcceptOther). For you only (faction, class, race), not repeatable, not a quest you skipped or one in a place
--     you skipped, not when the log is full, and while you bank not a quest the Plan page would cut (next to nothing on
--     the day, leading nowhere). Hold Shift and QuestBank keeps its hands off. An escort a party member starts is yours
--     to join, in the game's own prompt (Auto.Escort says why).
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

local function on(key) return QB:Opt(key) == true end -- (where you are can override the setting: QB:Opt)

-- Accept for me as it applies now: "off", "route" or "worth". A context row (QB:Opt) says on or off: on is your own
-- choice, or Quests worth taking where that is Off; an older save's true is Quests worth taking
local ACCEPT = { off = true, route = true, worth = true }
function Auto.AcceptMode()
  local v = QB:Opt("autoAccept")
  if v == true then
    local own = QB:Settings().autoAccept
    return (own == "route" or own == "worth") and own or "worth"
  end
  if v == false or v == nil then return "off" end
  return ACCEPT[v] and v or "off"
end
local function accepting() return Auto.AcceptMode() ~= "off" end
Auto.WORDS = { off = "Off", route = "Quests on my route", worth = "Quests worth taking" }
Auto.OTHER = { accept = "Accept them", leave = "Leave the window to me" }

-- on your route: on your pick-up list, or a step of a chain you picked (its first open step), or the next step of a
-- quest you hold or just handed in (the chain you are on)
function Auto.OnRoute(id)
  if not id or id == 0 then return false end
  local plan = QB:Plan()
  if plan.add[id] then return true end
  if plan.auto[id] and QB:GuideOn() then return true end
  local q = Q.Get(id)
  if not q then return false end
  for pid in pairs(plan.add) do
    local pq = Q.Get(pid)
    if pq and pq.pre then for _, p in ipairs(pq.pre) do if p == id then return true end end end
  end
  for _, p in ipairs(q.pre or {}) do
    if QB.state.log[p] or QB.API.IsDone(p) then
      -- the step straight before this one is yours: carrying the chain on
      if q.pre[#q.pre] == p then return true end
    end
  end
  return false
end

-- the quest the window shows: 0 when there is none, or when the client hides the id (a secret value)
local function qid()
  local id = GetQuestID and GetQuestID()
  if not id or (issecretvalue and issecretvalue(id)) then return 0 end
  return id
end

-- the decide-yourself key (Settings: shift, ctrl, alt, or none): held at the NPC, QuestBank leaves the quest to you
local KEYS = { shift = "IsShiftKeyDown", ctrl = "IsControlKeyDown", alt = "IsAltKeyDown" }
local function byHand()
  local name = KEYS[QB:Settings().autoKey or "shift"]
  local fn = name and _G[name]
  return (fn and fn()) and true or false
end
Auto.ByHand = byHand
local function later(where, fn) C_Timer.After(0.05, QB.Safe(fn, "auto: " .. where)) end
local function banking() return QB:Mode() == "lock" end
local function level() return QB.state.level or 1 end
local function logFull() return (QB.state.logCount or 0) >= QB.LOG_SLOTS end

-- worth taking, as the planner judges a stop: not grey (the game's trivial), and paying at least the planner's
-- low-value line at your level (Model.lua's CHEAP, which grey quests' tenth of their XP never reaches)
function Auto.Worth(id, trivial)
  if trivial then return false end
  local q = id and id ~= 0 and Q.Get(id)
  if not q then return true end -- (new to Forever: no number to judge by, as before)
  local lvl = level()
  return QB.Model.XpAt(q, lvl) >= (QB.Model.CHEAP or 400) * QB.Scale(lvl)
end

-- take this quest? Off: no. For you, not repeatable, not skipped (the quest or its place), the log not full; on your
-- route: yes; else with Quests worth taking, worth taking and your choice for quests outside the route. A quest
-- QuestBank knows nothing about is new to Forever: on no route, and worth taking. While you bank, not one the Plan page
-- would cut
function Auto.MayAccept(id, trivial, repeatable)
  local mode = Auto.AcceptMode()
  if mode == "off" or repeatable or logFull() then return false end
  local q = id and id ~= 0 and Q.Get(id)
  if q and (q.repeatable or not Q.ForMe(q) or QB:SkipsQuest(q)) then return false end
  if q and banking() and QB.Model.XpAt(q, level()) < 500 * QB.Scale(level()) and not QB:Upgrade(q) then return false end
  if q and Auto.OnRoute(id) then return not trivial end
  if mode ~= "worth" or QB:Settings().autoAcceptOther == "leave" then return false end
  return Auto.Worth(id, trivial)
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
  local accept, turnIn = accepting(), on("autoTurnIn")
  if not accept and not turnIn then return end
  later("greeting", function()
    if byHand() then return end
    if event == "GOSSIP_SHOW" and C_GossipInfo then
      if turnIn and C_GossipInfo.GetActiveQuests and C_GossipInfo.SelectActiveQuest then
        for _, info in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
          local id = QB.Plain(info.questID)
          if QB.Plain(info.isComplete) and id and Auto.MayTurnIn(id) then C_GossipInfo.SelectActiveQuest(id) return end
        end
      end
      if accept and C_GossipInfo.GetAvailableQuests and C_GossipInfo.SelectAvailableQuest then
        for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
          local id = QB.Plain(info.questID)
          if id and Auto.MayAccept(id, QB.Plain(info.isTrivial), QB.Plain(info.repeatable)) then C_GossipInfo.SelectAvailableQuest(id) return end
        end
      end
    elseif event == "QUEST_GREETING" then
      if turnIn and GetNumActiveQuests and GetActiveTitle and SelectActiveQuest then
        for i = 1, GetNumActiveQuests() or 0 do
          local _, complete = GetActiveTitle(i)
          local id = QB.Plain(GetActiveQuestID and GetActiveQuestID(i))
          if QB.Plain(complete) and id and Auto.MayTurnIn(id) then SelectActiveQuest(i) return end
        end
      end
      if accept and GetNumAvailableQuests and GetAvailableQuestInfo and SelectAvailableQuest then
        for i = 1, GetNumAvailableQuests() or 0 do
          local trivial, _, repeatable, _, id = GetAvailableQuestInfo(i)
          id = QB.Plain(id)
          if Auto.MayAccept(id, QB.Plain(trivial), QB.Plain(repeatable)) then SelectAvailableQuest(i) return end
        end
      end
    end
  end)
end

-- the quest window: take it, unless the game would first ask you about PvP
function Auto.Detail()
  if not accepting() or byHand() then return end
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

-- a party member started a quest (an escort, mostly). Up to 3.6.0 QuestBank said yes for you: ConfirmAcceptQuest
-- from a timer, then StaticPopup_Hide on the game's prompt. Hiding a Blizzard popup from QuestBank's code runs the
-- popup system's bookkeeping as QuestBank (StaticPopup_OnHide, StaticPopup_CollapseTable: table.remove on the list
-- of popups on screen). Another popup still open keeps a slot written by QuestBank, and the game's next popup (the
-- one that asks before deleting an item, say) can then run its Yes as QuestBank and be blocked. And ConfirmAcceptQuest
-- with no click behind it may be refused. So the prompt is the game's and the Yes is yours: QuestBank presses nothing
-- and hides nothing, and says so once a session to whoever has Accept for me on.
local toldEscort = false
function Auto.Escort(who, title)
  if not accepting() or toldEscort then return end
  toldEscort = true
  QB:Print(string.format("%s started %s: say yes in the game's prompt to join. Accept for me leaves escorts to you.",
    who or "A party member", title or "a quest"))
end

function Auto.OnEvent(event, a1, a2)
  if event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then Auto.Greeting(event)
  elseif event == "QUEST_DETAIL" then Auto.Detail()
  elseif event == "QUEST_PROGRESS" then Auto.Progress()
  elseif event == "QUEST_COMPLETE" then Auto.Complete()
  elseif event == "QUEST_ACCEPT_CONFIRM" then Auto.Escort(QB.Plain(a1), QB.Plain(a2)) end
end
