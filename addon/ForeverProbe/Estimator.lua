-- ForeverProbe :: Estimator (LevelPace's, ported intact)
--
-- Deliberately reads NO WoW globals in Update(); Refresh() is the thin
-- adapter. The rested subtlety is load-bearing: a pool of P supplies 2P XP
-- in exchange for P XP worth of BASE killing.
local ADDON, NS = ...
local util = NS.util

local Estimator = {}
NS.Estimator = Estimator

local MIN_KILLS_FOR_RANGE = 10
Estimator.result = {}

function Estimator:Update(state)
  local r = {}
  self.result = r
  local xpMax = state.xpMax or 0
  local xp = state.xp or 0
  if xpMax <= 0 then
    r.maxLevel = true; r.confidence = "none"; r.percent = 0; r.xpRemaining = 0
    return r
  end
  r.xpRemaining = math.max(0, xpMax - xp)
  r.percent = xp / xpMax * 100

  local liveRate = util.Median(state.baseRateSamples or {})
  local histRate = state.historyRate
  local f = state.observedFraction or 0
  if f < 0 then f = 0 elseif f > 1 then f = 1 end

  local baseRate
  if liveRate and histRate then
    baseRate = liveRate * f + histRate * (1 - f); r.rateSource = "blended"
  elseif liveRate then baseRate = liveRate; r.rateSource = "this level"
  elseif histRate then baseRate = histRate; r.rateSource = "your past levels"
  end
  r.baseRate = baseRate
  r.baseRatePerHour = baseRate and (baseRate * 3600) or nil
  r.killRate = state.killRate
  r.killRatePerHour = state.killRate and (state.killRate * 3600) or nil

  local pool = state.restedPool or 0
  local xpCoveredByRested = math.min(2 * pool, r.xpRemaining)
  local baseNeeded = (xpCoveredByRested / 2) + (r.xpRemaining - xpCoveredByRested)
  r.baseNeeded = baseNeeded
  r.restedCovered = xpCoveredByRested

  if baseRate and baseRate > 0 then r.timeToLevel = baseNeeded / baseRate end

  local kills = state.killXPSamples or {}
  r.killSampleCount = #kills
  if #kills >= MIN_KILLS_FOR_RANGE and baseNeeded > 0 then
    local p25, p75 = util.Percentile(kills, 0.25), util.Percentile(kills, 0.75)
    if p25 and p25 > 0 and p75 and p75 > 0 then
      r.mobsLow = math.ceil(baseNeeded / p75)
      r.mobsHigh = math.ceil(baseNeeded / p25)
    end
  end

  if not baseRate then r.confidence = "none"
  elseif f >= 0.25 and r.killSampleCount >= MIN_KILLS_FOR_RANGE then r.confidence = "good"
  else r.confidence = "low" end
  return r
end

function Estimator:Refresh()
  local H = NS.History
  local rested = GetXPExhaustion and GetXPExhaustion() or 0
  return self:Update({
    xp = UnitXP("player"), xpMax = UnitXPMax("player"),
    restedPool = rested or 0,
    baseRateSamples = H:BaseRateSamples(),
    killRate = H:LiveKillRate(),
    killXPSamples = H:KillXPSamples(),
    historyRate = H:MedianBaseRate(),
    observedFraction = H:ObservedFraction(),
  })
end
