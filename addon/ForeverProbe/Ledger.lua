-- ForeverProbe :: Ledger (LevelPace's parser, essential subset)
--
-- The only module allowed to parse text. Patterns are built at load from the
-- live _G globals so other locales work unchanged; most specific first, and
-- that ordering is load-bearing. A reconciliation pass on PLAYER_XP_UPDATE
-- catches anything the patterns miss on this new client, so baseXP stays
-- complete even where the message formats changed.
local ADDON, NS = ...
local util = NS.util

local Ledger = {}
NS.Ledger = Ledger

local patterns = {}
local function add(globalName, fields, kind)
  local fmt = _G[globalName]
  if type(fmt) ~= "string" then return end
  local pat = util.ConvertGlobalString(fmt)
  if not pat then return end
  for i = 1, #patterns do if patterns[i].pattern == pat then return end end
  patterns[#patterns + 1] = { pattern = pat, fields = fields, kind = kind }
end

function Ledger:BuildPatterns()
  patterns = {}
  add("COMBATLOG_XPGAIN_EXHAUSTION1_GROUP", { "mobName", "total", "bonusAmount", "bonusType", "group" }, "kill")
  add("COMBATLOG_XPGAIN_EXHAUSTION4_GROUP", { "mobName", "total", "penaltyAmount", "penaltyType", "group" }, "kill")
  add("COMBATLOG_XPGAIN_FIRSTPERSON_GROUP", { "mobName", "total", "group" }, "kill")
  add("COMBATLOG_XPGAIN_EXHAUSTION1", { "mobName", "total", "bonusAmount", "bonusType" }, "kill")
  add("COMBATLOG_XPGAIN_EXHAUSTION4", { "mobName", "total", "penaltyAmount", "penaltyType" }, "kill")
  add("COMBATLOG_XPGAIN_FIRSTPERSON", { "mobName", "total" }, "kill")
  add("COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED", { "total" }, "unknown")
end

local accounted = 0   -- total XP explained by parsed events since last reconcile
local lastXP, lastMax, lastLevel

function Ledger:Prime()
  lastXP = UnitXP("player")
  lastMax = UnitXPMax("player")
  lastLevel = UnitLevel("player")
  accounted = 0
end

Ledger.debug = { parsed = 0, quests = 0, unknown = 0, unknownXP = 0 }
local function emit(e)
  accounted = accounted + (e.total or 0)
  local dbg = Ledger.debug
  if e.source == "kill" then dbg.parsed = dbg.parsed + 1
  elseif e.source == "quest" then dbg.quests = dbg.quests + 1
  else dbg.unknown = dbg.unknown + 1; dbg.unknownXP = dbg.unknownXP + (e.total or 0) end
  NS.History:AddEvent(e)
  if NS.onXPEvent then NS.onXPEvent(e) end
end

function Ledger:PatternCount()
  if #patterns == 0 then self:BuildPatterns() end
  return #patterns
end

function Ledger:OnChatXP(msg)
  if #patterns == 0 then self:BuildPatterns() end
  for _, p in ipairs(patterns) do
    local caps = { string.match(msg, p.pattern) }
    if caps[1] ~= nil then
      local e = { t = GetTime(), source = p.kind }
      for i, f in ipairs(p.fields) do
        local v = caps[i]
        if f == "total" or f == "bonusAmount" or f == "penaltyAmount" or f == "group" then
          e[f] = tonumber(v)
        else
          e[f] = v
        end
      end
      e.rested = e.bonusAmount or 0
      -- base = what the server would have paid unrested and ungrouped
      e.base = math.max(0, (e.total or 0) - e.rested - (e.group or 0))
      emit(e)
      return true
    end
  end
end

function Ledger:OnQuestTurnIn(questID, xpReward)
  if not xpReward or xpReward <= 0 then return end
  emit({ t = GetTime(), source = "quest", questID = questID, total = xpReward, base = xpReward, rested = 0 })
end

-- Reconciliation: whatever the parser did not explain still happened.
-- PLAYER_XP_UPDATE and the chat line can arrive in either order on this
-- client, so the reconcile is debounced: the delta is banked and settled a
-- second later, giving the parser first claim on it. A straggler after the
-- settle would double-count once and be clamped back out on the next pass.
local pendingDelta = 0
local settleTimer

local function settle()
  settleTimer = nil
  local missing = pendingDelta - accounted
  if missing > 0 then
    emit({ t = GetTime(), source = "unknown", total = missing, base = missing, rested = 0 })
  end
  pendingDelta = 0
  accounted = 0
end

function Ledger:OnXPUpdate()
  local xp, xpMax, lvl = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
  if not xp or not lastXP then self:Prime() return end
  local delta
  if lvl > (lastLevel or lvl) then
    -- Undercounts a multi-level jump (no xpMax for the skipped levels); rare.
    delta = ((lastMax or 0) - lastXP) + xp
  else
    delta = xp - lastXP
  end
  lastXP, lastMax, lastLevel = xp, xpMax, lvl
  if delta and delta > 0 then
    pendingDelta = pendingDelta + delta
    if settleTimer then settleTimer:Cancel() end
    settleTimer = C_Timer.NewTimer(1, settle)
  end
end
