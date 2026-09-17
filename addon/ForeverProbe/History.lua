-- ForeverProbe :: History (LevelPace's model, trimmed)
--
-- Per-level records, per character. No sanitising: deaths count, downtime
-- counts. A number that quietly deletes your downtime is not measuring
-- your levelling.
local ADDON, NS = ...
local util = NS.util

local History = {}
NS.History = History

local KILL_XP_WINDOW = 120

local function charKey()
  local realm = GetRealmName and GetRealmName() or "?"
  return (UnitName("player") or "?") .. "-" .. realm
end

local function newRecord(level, now)
  return { level = level, startedAt = now, elapsed = 0,
    xpBySource = { kill = 0, quest = 0, unknown = 0 },
    killCount = 0, questCount = 0, deaths = 0,
    baseXP = 0, killBaseXP = 0, restedConsumed = 0,
    largestGap = 0, lastEventAt = now }
end

function History:Store()
  local d = NS.db()
  d.chars = d.chars or {}
  d.chars[charKey()] = d.chars[charKey()] or { history = {} }
  return d.chars[charKey()]
end

function History:Init()
  local now = GetTime()
  local level = UnitLevel("player") or 1
  local s = self:Store()
  if not s.current or s.current.level ~= level then
    s.current = newRecord(level, now)
  else
    -- GetTime restarts every session; rebase stored elapsed onto now.
    s.current.startedAt = now - (s.current.elapsed or 0)
    s.current.lastEventAt = now
  end
  self.record = s.current
  self.killXPSamples = {}
end

function History:Current()
  if not self.record then self:Init() end
  return self.record
end

function History:AddEvent(e)
  local r = self:Current()
  local now = e.t or GetTime()
  -- The gap is RECORDED, not filtered; the tooltip says why numbers look odd.
  local gap = now - (r.lastEventAt or now)
  if gap > (r.largestGap or 0) then r.largestGap = gap end
  r.lastEventAt = now
  r.elapsed = now - r.startedAt
  local bucket = e.source or "unknown"
  if r.xpBySource[bucket] == nil then bucket = "unknown" end
  r.xpBySource[bucket] = r.xpBySource[bucket] + (e.total or 0)
  r.baseXP = r.baseXP + (e.base or 0)
  r.restedConsumed = r.restedConsumed + (e.rested or 0)
  if e.source == "kill" then
    r.killCount = r.killCount + 1
    r.killBaseXP = r.killBaseXP + (e.base or 0)
    util.PushBounded(self.killXPSamples, e.base or 0, KILL_XP_WINDOW)
  elseif e.source == "quest" then
    r.questCount = r.questCount + 1
  end
end

function History:OnLevelUp(newLevel)
  local now = GetTime()
  local s = self:Store()
  local r = self:Current()
  if r then
    r.elapsed = now - r.startedAt
    table.insert(s.history, r)
  end
  s.current = newRecord(newLevel, now)
  self.record = s.current
  self.killXPSamples = {}
end

function History:OnDeath()
  local r = self:Current()
  if r then r.deaths = r.deaths + 1 end
end

function History:Elapsed()
  local r = self:Current()
  return math.max(0, GetTime() - (r.startedAt or GetTime()))
end

function History:LiveBaseRate()
  local r = self:Current()
  local elapsed = self:Elapsed()
  if not r or r.baseXP <= 0 or elapsed <= 0 then return nil end
  return r.baseXP / elapsed
end

function History:LiveKillRate()
  local r = self:Current()
  local elapsed = self:Elapsed()
  if not r or (r.killBaseXP or 0) <= 0 or elapsed <= 0 then return nil end
  return r.killBaseXP / elapsed
end

function History:BaseRateSamples()
  local rate = self:LiveBaseRate()
  return rate and { rate } or {}
end

function History:KillXPSamples() return self.killXPSamples or {} end

function History:MedianBaseRate()
  local rates = {}
  for _, r in ipairs(self:Store().history or {}) do
    if (r.elapsed or 0) > 60 and (r.baseXP or 0) > 0 then
      rates[#rates + 1] = r.baseXP / r.elapsed
    end
  end
  return util.Median(rates)
end

function History:ObservedFraction()
  local r = self:Current()
  local xpMax = UnitXPMax("player") or 0
  if not r or xpMax <= 0 then return 0 end
  local seen = (r.xpBySource.kill or 0) + (r.xpBySource.quest or 0) + (r.xpBySource.unknown or 0)
  local f = seen / xpMax
  return f > 1 and 1 or f
end
