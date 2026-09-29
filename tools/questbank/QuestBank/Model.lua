-- QuestBank model: Forever quest XP and the hand-in route planner.
-- XP: Classic base x the quest's Forever multiplier, the Classic grey penalty, rounded
-- to 10 below 1,000 and 50 above (Wowhead's Forever formula).
-- Route: every order of the stops within each continent, the hearthstone as the jump
-- between Kalimdor and the Eastern Kingdoms, searched in two stages so it stays cheap.
local _, QB = ...
local M = {}
QB.Model = M

local floor = math.floor
local function round(x) return floor(x + 0.5) end
local function roundQuestXp(e)
  local t = e < 1000 and 10 or 50
  return round(e / t) * t
end

function M.XpAt(base, mult, qlvl, plvl)
  local f = round((base or 0) * (mult or 1))
  local m = plvl - qlvl
  if m >= 10 then f = f * 0.1 elseif m >= 6 then f = f * (1 - (m - 5) * 0.2) end
  return roundQuestXp(f)
end

function M.Pct(qlvl, plvl)
  local m = plvl - qlvl
  if m >= 10 then return 10 elseif m >= 6 then return 100 - (m - 5) * 20 end
  return 100
end

function M.Full(q) return roundQuestXp(round(q.base * (q.mult or 1))) end

local function gain(c, x)
  local T = QB.Data.TO_NEXT
  c.xp = c.xp + x
  while c.level < QB.CAP and T[c.level] and c.xp >= T[c.level] do
    c.xp = c.xp - T[c.level]
    c.level = c.level + 1
  end
end
M.Gain = gain

function M.Frac(level, xp)
  if level >= QB.CAP then return QB.CAP end
  return level + xp / QB.Data.TO_NEXT[level]
end

----------------------------------------------------------------------------
-- travel
----------------------------------------------------------------------------
local function edge(a, b)
  if a == b then return 0, 0 end
  local E = QB.Data.EDGES
  local e = E[a < b and (a .. ">" .. b) or (b .. ">" .. a)]
  if e then return e[1], e[2] end
  return 10, 5
end

function M.Travel(a, b, mf)
  local f, w = edge(a, b)
  return f + w * mf
end

function M.LegKind(a, b)
  local f = edge(a, b)
  if f == 0 then return "foot" end
  local K = QB.Data.KALIMDOR
  if (a == "SW" and (b == "IF" or b == "KH")) or (b == "SW" and (a == "IF" or a == "KH")) then return "tram" end
  if (K[a] and true or false) ~= (K[b] and true or false) then return "boat" end
  return "flight"
end

----------------------------------------------------------------------------
-- orders
----------------------------------------------------------------------------
local function permute(list, n, out)
  n = n or #list
  out = out or {}
  if n <= 1 then
    local copy = {}
    for i = 1, #list do copy[i] = list[i] end
    out[#out + 1] = copy
    return out
  end
  for i = 1, n do
    list[i], list[n] = list[n], list[i]
    permute(list, n - 1, out)
    list[i], list[n] = list[n], list[i]
  end
  return out
end

local function blockOrders(blocks)
  local out = {}
  if #blocks == 0 then return { {} } end
  for _, perm in ipairs(permute(blocks)) do
    local acc = { {} }
    for _, b in ipairs(perm) do
      local variants = { b }
      if #b > 1 then
        local r = {}
        for i = #b, 1, -1 do r[#r + 1] = b[i] end
        variants[2] = r
      end
      local nextAcc = {}
      for _, a in ipairs(acc) do
        for _, v in ipairs(variants) do
          local s = {}
          for i = 1, #a do s[i] = a[i] end
          for i = 1, #v do s[#s + 1] = v[i] end
          nextAcc[#nextAcc + 1] = s
        end
      end
      acc = nextAcc
    end
    for _, s in ipairs(acc) do out[#out + 1] = s end
  end
  return out
end

----------------------------------------------------------------------------
-- simulation of one part of the route
----------------------------------------------------------------------------
-- start: { level, xp, t, at60, prev } ; firstKind: "start" or "hearth"
local function runPart(seq, byStop, opts, start, firstKind, keepLegs)
  local mf = opts.mounted and 0.625 or 1
  local c = { level = start.level, xp = start.xp }
  local t, at60, prev = start.t, start.at60, start.prev
  local total = 0
  local legs = keepLegs and {} or nil
  local STOP = QB.Data.STOP
  local INN_STOP = QB.Data.INN_STOP
  for i = 1, #seq do
    local stop = seq[i]
    local travel, kind = 0, "start"
    if i == 1 and firstKind == "hearth" then
      travel = 0.3 + M.Travel(INN_STOP[stop] or stop, stop, mf)
      kind = "hearth"
    elseif prev then
      travel = M.Travel(prev, stop, mf)
      kind = M.LegKind(prev, stop)
    end
    t = t + travel + STOP[stop].work * mf
    local arrive = M.Frac(c.level, c.xp)
    local rows = keepLegs and {} or nil
    for _, e in ipairs(byStop[stop]) do
      local q = e.q
      local lv = c.level
      local x = M.XpAt(q.base, q.mult, q.lvl, lv)
      if opts.bonus then x = round(x * 1.03) end
      gain(c, x)
      total = total + x
      if rows then rows[#rows + 1] = { e = e, q = q, xp = x, pct = M.Pct(q.lvl, lv), plvl = lv } end
    end
    if t <= 60 then at60 = M.Frac(c.level, c.xp) end
    if legs then
      legs[#legs + 1] = { stop = stop, travel = travel, kind = kind, t = t, arrive = arrive, leave = M.Frac(c.level, c.xp), rows = rows }
    end
    prev = stop
  end
  return { level = c.level, xp = c.xp, t = t, at60 = at60, prev = prev, total = total, legs = legs }
end

local function better(goal, a, b)
  if not b then return true end
  local fa, fb = M.Frac(a.level, a.xp), M.Frac(b.level, b.xp)
  if goal == "hour" then
    if math.abs(a.at60 - b.at60) > 1e-6 then return a.at60 > b.at60 end
    if math.abs(fa - fb) > 1e-6 then return fa > fb end
    return a.t < b.t
  end
  if math.abs(fa - fb) > 1e-6 then return fa > fb end
  return a.t < b.t
end

----------------------------------------------------------------------------
-- build: quests = { {q=..., st=...}, ... }, opts = {level, xp, mounted, bonus, goal}
----------------------------------------------------------------------------
function M.Build(quests, opts)
  local D = QB.Data
  if not D.STOP then
    D.STOP = {}
    for _, s in ipairs(D.STOPS) do D.STOP[s.key] = s end
  end
  local byStop, count = {}, 0
  for _, e in ipairs(quests) do
    local s = e.q.stop
    if D.STOP[s] then
      byStop[s] = byStop[s] or {}
      table.insert(byStop[s], e)
      count = count + 1
    end
  end
  for _, list in pairs(byStop) do
    table.sort(list, function(a, b)
      if a.q.lvl ~= b.q.lvl then return a.q.lvl < b.q.lvl end
      return M.Full(a.q) > M.Full(b.q)
    end)
  end
  local function present(blocks)
    local out = {}
    for _, b in ipairs(blocks) do
      local nb = {}
      for _, s in ipairs(b) do if byStop[s] then nb[#nb + 1] = s end end
      if #nb > 0 then out[#out + 1] = nb end
    end
    return out
  end
  local kal = present(D.BLOCKS_KAL)
  local ek = present(D.BLOCKS_EK)
  local start = { level = opts.level, xp = opts.xp, t = 0, at60 = M.Frac(opts.level, opts.xp) }
  local best, bestSeq, bestHearth

  local function tryOrder(firstBlocks, secondBlocks)
    local firstOrders = blockOrders(firstBlocks)
    local scored = {}
    for _, seq in ipairs(firstOrders) do
      if #seq > 0 then scored[#scored + 1] = { seq = seq, r = runPart(seq, byStop, opts, start, "start") } end
    end
    table.sort(scored, function(a, b) return better(opts.goal, a.r, b.r) end)
    local secondOrders = blockOrders(secondBlocks)
    for i = 1, math.min(3, #scored) do
      local a = scored[i]
      for _, seq in ipairs(secondOrders) do
        local r = a.r
        if #seq > 0 then r = runPart(seq, byStop, opts, a.r, "hearth") end
        if better(opts.goal, r, best) then
          best = r
          bestSeq = {}
          for _, s in ipairs(a.seq) do bestSeq[#bestSeq + 1] = s end
          bestHearth = #seq > 0 and (#a.seq + 1) or nil
          for _, s in ipairs(seq) do bestSeq[#bestSeq + 1] = s end
        end
      end
    end
  end

  if #kal > 0 and #ek > 0 then
    tryOrder(kal, ek)
    tryOrder(ek, kal)
  elseif #kal > 0 then
    tryOrder(kal, {})
  elseif #ek > 0 then
    tryOrder(ek, {})
  end

  local route = { legs = {}, t = 0, xp = 0, level = start.at60, at60 = start.at60, count = count, byQuest = {} }
  if bestSeq then
    -- replay the winner with legs kept
    local partA, partB = {}, {}
    for i, s in ipairs(bestSeq) do
      if bestHearth and i >= bestHearth then partB[#partB + 1] = s else partA[#partA + 1] = s end
    end
    local a = runPart(partA, byStop, opts, start, "start", true)
    local final = a
    local legs = a.legs
    if #partB > 0 then
      final = runPart(partB, byStop, opts, a, "hearth", true)
      for _, l in ipairs(final.legs) do legs[#legs + 1] = l end
      final.total = a.total + final.total
    end
    route.legs = legs
    route.t = final.t
    route.xp = final.total
    route.level = M.Frac(final.level, final.xp)
    route.at60 = final.at60
    route.hearthAt = bestHearth
    route.startStop = bestSeq[1]
    route.bindStop = bestHearth and bestSeq[bestHearth] or nil
    for _, l in ipairs(legs) do
      for _, row in ipairs(l.rows) do route.byQuest[row.q.id] = row.xp end
    end
  end
  return route
end
