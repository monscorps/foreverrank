-- ForeverProbe :: Ledger (LevelPace's parser, essential subset)
--
-- The only module allowed to parse text. Patterns are built at load from the
-- live _G globals so other locales work unchanged; most specific first, and
-- that ordering is load-bearing. A reconciliation pass on PLAYER_XP_UPDATE
-- catches anything the patterns miss on this new client (or can't read: the
-- restricted-combat rules may hand addons the chat line as a secret value), so
-- baseXP stays complete even where the message formats changed.
local ADDON, NS = ...
local util = NS.util

local Ledger = {}
NS.Ledger = Ledger

local NUMERIC = { total = true, bonusAmount = true, penaltyAmount = true, group = true, raidPenalty = true }

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
  add("COMBATLOG_XPGAIN_EXHAUSTION1_RAID", { "mobName", "total", "bonusAmount", "bonusType", "raidPenalty" }, "kill")
  add("COMBATLOG_XPGAIN_EXHAUSTION4_GROUP", { "mobName", "total", "penaltyAmount", "penaltyType", "group" }, "kill")
  add("COMBATLOG_XPGAIN_EXHAUSTION4_RAID", { "mobName", "total", "penaltyAmount", "penaltyType", "raidPenalty" }, "kill")
  add("COMBATLOG_XPGAIN_FIRSTPERSON_GROUP", { "mobName", "total", "group" }, "kill")
  add("COMBATLOG_XPGAIN_FIRSTPERSON_RAID", { "mobName", "total", "raidPenalty" }, "kill")
  add("COMBATLOG_XPGAIN_EXHAUSTION1", { "mobName", "total", "bonusAmount", "bonusType" }, "kill")
  add("COMBATLOG_XPGAIN_EXHAUSTION4", { "mobName", "total", "penaltyAmount", "penaltyType" }, "kill")
  add("COMBATLOG_XPGAIN_FIRSTPERSON", { "mobName", "total" }, "kill")
  add("COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP", { "total", "group" }, "unknown")
  add("COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_RAID", { "total", "raidPenalty" }, "unknown")
  add("COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED", { "total" }, "unknown")
end

local accounted = 0        -- total XP explained by parsed events since last reconcile
local explainedRested = 0  -- the rested bonus inside it
local poolSeen             -- the rested pool when last looked at
local poolUsed = 0         -- how far it has dropped since the last reconcile (resting refills it: rises don't count)
local lastXP, lastMax, lastLevel

local function pool() return (GetXPExhaustion and GetXPExhaustion()) or 0 end

-- once a session: a loading screen must not throw away XP the reconcile hasn't settled yet
function Ledger:Prime(force)
  if lastXP and not force then return end
  lastXP = UnitXP("player")
  lastMax = UnitXPMax("player")
  lastLevel = UnitLevel("player")
  accounted, explainedRested = 0, 0
  poolSeen, poolUsed = pool(), 0
end

-- follow the pool: drops are rested bonus paid out, rises are resting
local function watchPool()
  local now = pool()
  if poolSeen and now < poolSeen then poolUsed = poolUsed + (poolSeen - now) end
  poolSeen = now
end
Ledger.WatchPool = watchPool

Ledger.debug = { parsed = 0, quests = 0, unknown = 0, unknownXP = 0, secret = 0 }
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
  -- a line the client won't let addons read: the reconcile books it from the XP bar instead
  if util.Secret(msg) or type(msg) ~= "string" then
    self.debug.secret = self.debug.secret + 1
    return
  end
  if #patterns == 0 then self:BuildPatterns() end
  for _, p in ipairs(patterns) do
    local caps = { string.match(msg, p.pattern) }
    if caps[1] ~= nil then
      local e = { t = GetTime(), source = p.kind }
      for i, f in ipairs(p.fields) do
        local v = caps[i]
        if NUMERIC[f] then e[f] = util.Num(v) else e[f] = v end
      end
      e.rested = e.bonusAmount or 0
      -- base = what the server would have paid unrested and ungrouped
      e.base = math.max(0, (e.total or 0) - e.rested - (e.group or 0) + (e.raidPenalty or 0))
      explainedRested = explainedRested + e.rested
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
-- second later, giving the parser first claim on it. Rested bonus shrinks the
-- rested pool by exactly what it pays, so the part of the unexplained XP the
-- pool paid for is bonus, and the rest is base.
local pendingDelta = 0
local settleTimer

local function settle()
  settleTimer = nil
  watchPool()
  local missing = pendingDelta - accounted
  if missing > 0 then
    local bonus = math.max(0, math.min(missing, poolUsed - explainedRested))
    emit({ t = GetTime(), source = "unknown", total = missing, base = missing - bonus, rested = bonus })
  end
  pendingDelta, accounted, explainedRested, poolUsed = 0, 0, 0, 0
end

function Ledger:OnXPUpdate()
  local xp, xpMax, lvl = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
  if not xp or not lastXP then self:Prime(true) return end
  local delta
  if lvl > (lastLevel or lvl) then
    -- Undercounts a multi-level jump (no xpMax for the skipped levels); rare.
    delta = ((lastMax or 0) - lastXP) + xp
  else
    delta = xp - lastXP
  end
  lastXP, lastMax, lastLevel = xp, xpMax, lvl
  watchPool()
  if delta and delta > 0 then
    pendingDelta = pendingDelta + delta
    if settleTimer then settleTimer:Cancel() end
    settleTimer = C_Timer.NewTimer(1, function() util.Try("xp reconcile", settle) end)
  end
end
