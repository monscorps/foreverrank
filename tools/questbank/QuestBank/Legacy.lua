-- SPDX-License-Identifier: GPL-3.0-or-later
-- Legacy perks and live measurement: what this character's Legacy points change in QuestBank's numbers, and what the
-- game itself shows of your pace, so the model is yours and not a table's.
-- Legacy (Forever's account perks, Blizzard_LegacySystem): three trait trees, 1187 Professions, 1188 Adventure and
-- 1189 Progression, read the way the game's own micro menu reads Talented (MainMenuBarMicroButtonsOverrides.lua):
--   C_Traits.GetConfigIDByTreeID(tree), then C_Traits.GetNodeInfo(config, node).activeRank
-- The ranks are read once, kept, and read again on TRAIT_CONFIG_UPDATED, TRAIT_NODE_CHANGED, TRAIT_CONFIG_LIST_UPDATED
-- and PLAYER_ENTERING_WORLD. The perks' passives are hidden auras (SpellMisc 0x1c0), so auras never tell.
-- What QuestBank counts with (build 1.60.1.70338's curves):
--   Frequent Flier 110300  the flight path mount flies 20% faster: the air part of a flight / 1.2
--   Field Guide    110304  camp features' shared hour - 288 / 612 / 900 s
--   Gourmand       110313  Well Fed lasts 33 / 67 / 100% longer: "15 min" reads 20 / 25 / 30
--   Permanence     110316  class buffs and a camp's rest benefits last 50 / 100% longer
--   Well Rested    110301  rested XP builds 4% a rank faster, to 20% (the perk; the sleeping bag's buff is another)
--   Talented       110298  talents start a level earlier a rank: 9, 8, 7, 6, 5
-- No live perk changes run speed, mount speed, quest XP or the hearthstone.
-- Measured (QB.Measure), per character in QuestBankDB.chars[key].measure: your run speed on foot and mounted, from
-- GetUnitSpeed("player") on Walk's tick, outdoors, off a taxi, alive, without a speed buff on (Cheetah, Travel Form,
-- Ghost Wolf, Sprint, Dash, Aspect of the Pack, a swiftness potion, Westfall Stew), split by IsMounted(), the median of
-- the last samples. The model's pace (QB.Model.Speed) is the measured one when there is one.
--   measure = { foot = { yd/s, ... }, mount = { ... }, run = median on foot, ride = median mounted, at = time() }
-- QuestBankDB.diag.legacy = { reads, events, trees = { [tree] = config id or false }, ranks = { [node] = rank }, at }:
-- what this client answered, so the uploads show it.
local _, QB = ...
local L = {}
QB.Legacy = L

local plain = QB.Plain
local floor = math.floor

L.TREE = { PROFESSIONS = 1187, ADVENTURE = 1188, PROGRESSION = 1189 }
L.TREE_NAME = { [1187] = "Professions", [1188] = "Adventure", [1189] = "Progression" }
-- every live perk: its node, tree, name and ranks (TraitNode, TraitNodeXTraitNodeEntry, 1.60.1.70338)
L.PERKS = {
  { node = 110289, tree = 1187, name = "Master Chef", ranks = 5 },
  { node = 110290, tree = 1187, name = "Working Overtime", ranks = 5 },
  { node = 110286, tree = 1187, name = "Bartering", ranks = 2 },
  { node = 110284, tree = 1187, name = "Dedicated Study", ranks = 1 },
  { node = 110291, tree = 1187, name = "Bountiful Harvest", ranks = 5 },
  { node = 110292, tree = 1187, name = "Performance Bonus", ranks = 3 },
  { node = 110293, tree = 1187, name = "Luremaster", ranks = 2 },
  { node = 110305, tree = 1188, name = "High Alert", ranks = 2 },
  { node = 110301, tree = 1188, name = "Well Rested", ranks = 5 },
  { node = 110298, tree = 1188, name = "Talented", ranks = 5 },
  { node = 110296, tree = 1188, name = "Thrill of Adventure", ranks = 5 },
  { node = 110304, tree = 1188, name = "Field Guide", ranks = 3 },
  { node = 110300, tree = 1188, name = "Frequent Flier", ranks = 1 },
  { node = 110303, tree = 1188, name = "Field Medicine", ranks = 2 },
  { node = 110319, tree = 1189, name = "For Great Honor", ranks = 5 },
  { node = 110313, tree = 1189, name = "Gourmand", ranks = 3 },
  { node = 110316, tree = 1189, name = "Permanence", ranks = 2 },
  { node = 110315, tree = 1189, name = "The Quick and the Dead", ranks = 2 },
  { node = 110309, tree = 1189, name = "Reagent Economy", ranks = 1 },
  { node = 110318, tree = 1189, name = "Reinforce", ranks = 5 },
  { node = 110314, tree = 1189, name = "Diplomat", ranks = 5 },
}
L.NODE = { FLIER = 110300, FIELD_GUIDE = 110304, GOURMAND = 110313, PERMANENCE = 110316, WELL_RESTED = 110301, TALENTED = 110298 }
L.PERK_WELL_RESTED, L.BAG_WELL_RESTED = 1225478, 429959 -- the perk's hidden passive; the Cozy Sleeping Bag's "Well-Rested"
local FLY_FASTER = 1.2                       -- Frequent Flier: the flight path mount's speed
local CAMP_LESS = { 288, 612, 900 }          -- Field Guide: seconds off the camp features' hour
local FOOD_MORE = { 1.33, 1.67, 2.0 }        -- Gourmand
local BUFF_MORE = { 1.5, 2.0 }               -- Permanence
local RESTED_MORE = 0.04                     -- Well Rested, a rank
local TALENT_LEVEL = 10                      -- talents start here without Talented
L.CAMP_CD = 3600

local ranks, readAt = nil, nil
local flier = nil -- Frequent Flier's rank at the last read: the flights' minutes move only when it does
local function diag()
  QuestBankDB = QuestBankDB or {}
  QuestBankDB.diag = type(QuestBankDB.diag) == "table" and QuestBankDB.diag or {}
  local d = type(QuestBankDB.diag.legacy) == "table" and QuestBankDB.diag.legacy or {}
  QuestBankDB.diag.legacy = d
  d.reads, d.events = d.reads or 0, d.events or 0
  return d
end

-- read every tree's config and every perk's committed rank (activeRank: what is applied, not what is staged)
function L.Read()
  local out, trees = {}, {}
  local T = C_Traits
  if type(T) == "table" and type(T.GetConfigIDByTreeID) == "function" and type(T.GetNodeInfo) == "function" then
    local cfg = {}
    for _, tree in pairs(L.TREE) do
      local ok, id = pcall(T.GetConfigIDByTreeID, tree)
      id = ok and plain(id) or nil
      cfg[tree] = type(id) == "number" and id or nil
      trees[tree] = cfg[tree] or false
    end
    for _, p in ipairs(L.PERKS) do
      local id = cfg[p.tree]
      if id then
        local ok, info = pcall(T.GetNodeInfo, id, p.node)
        local r = ok and type(info) == "table" and plain(info.activeRank) or nil
        if type(r) == "number" and r >= 0 then out[p.node] = floor(r) end
      end
    end
  end
  ranks, readAt = out, (GetTime and GetTime() or 0)
  local d = diag()
  d.reads, d.trees, d.ranks, d.at = d.reads + 1, trees, out, (time and time() or 0)
  L.ver = (L.ver or 0) + 1
  -- (only Frequent Flier changes a flight's minutes: the route and the arrow's way are planned again for it, not for
  -- every trait event, which comes with each talent and Legacy point)
  local fl = out[L.NODE.FLIER] or 0
  if fl ~= flier then
    local was = flier
    flier = fl
    if QB.Travel and QB.Travel.Refly then QB.Travel.Refly(was ~= nil) end
  end
  return out
end

-- a perk's committed rank, 0 when the client has none (no Legacy yet, Classic Era, a secret value)
function L.Rank(node)
  if not ranks then L.Read() end
  return ranks[node] or 0
end
function L.Has(node) return L.Rank(node) > 0 end

-- the air part of a flight against the tables' (1 / 1.2 with Frequent Flier)
function L.FlightFactor() return L.Has(L.NODE.FLIER) and (1 / FLY_FASTER) or 1 end
-- the camp features' shared cooldown in seconds
function L.CampCooldown() return L.CAMP_CD - (CAMP_LESS[L.Rank(L.NODE.FIELD_GUIDE)] or 0) end
-- how much longer Well Fed lasts
function L.FoodFactor() return FOOD_MORE[L.Rank(L.NODE.GOURMAND)] or 1 end
-- how much longer class buffs and a camp's rest benefits last
function L.BuffFactor() return BUFF_MORE[L.Rank(L.NODE.PERMANENCE)] or 1 end
-- how much faster rested XP builds (0.08: 8% faster)
function L.Rested() return L.Rank(L.NODE.WELL_RESTED) * RESTED_MORE end
-- the level talents start at, and the rank
function L.Talented() local r = L.Rank(L.NODE.TALENTED); return math.max(1, TALENT_LEVEL - r), r end

-- a food's text with Gourmand's minutes: "+3 Strength, 15 min" reads "+3 Strength, 20 min"
function L.FoodText(s)
  if type(s) ~= "string" then return s end
  local f = L.FoodFactor()
  if f == 1 then return s end
  return (s:gsub("(%d+) min", function(m) return floor(tonumber(m) * f + 0.5) .. " min" end))
end

-- the flight minutes of the tables (a takeoff, then the air) with Frequent Flier
function L.FlightMinutes(m)
  local f = L.FlightFactor()
  if f == 1 or type(m) ~= "number" then return m end
  local T = QB.Model and QB.Model.TAKEOFF or 0.25
  if m <= T then return m end
  return T + (m - T) * f
end

-- /qb legacy: every perk's rank by tree, then what QuestBank counts with
function L.Report()
  if not ranks then L.Read() end
  local out = {}
  local any = false
  for _, tree in ipairs({ 1187, 1188, 1189 }) do
    local parts = {}
    for _, p in ipairs(L.PERKS) do
      if p.tree == tree then
        local r = ranks[p.node]
        if r == nil then parts[#parts + 1] = p.name .. " ?" else parts[#parts + 1] = string.format("%s %d/%d", p.name, r, p.ranks) end
        if r and r > 0 then any = true end
      end
    end
    out[#out + 1] = string.format("Legacy, %s: %s.", L.TREE_NAME[tree], table.concat(parts, ", "))
  end
  local d = diag()
  if not next(ranks) then
    out[#out + 1] = (type(C_Traits) == "table") and "No Legacy read yet on this character: every perk counts as rank 0." or "No Legacy on this client: every perk counts as rank 0."
  elseif not any then
    out[#out + 1] = "No Legacy points spent yet: the tables' own numbers."
  end
  local fly = L.FlightMinutes(6.25)
  local camp = L.CampCooldown()
  local food = floor(15 * L.FoodFactor() + 0.5)
  local lvl = L.Talented()
  out[#out + 1] = string.format("QuestBank counts: a 6-minute flight as %.1f min, the camp cooldown %d min, Well Fed %d min, class buffs x%.1f, rested XP +%d%%, talents at level %d.",
    fly, floor(camp / 60 + 0.5), food, L.BuffFactor(), floor(L.Rested() * 100 + 0.5), lvl)
  local M = QB.Model
  if M and M.Speed then
    local run, mount, measured = M.Speed()
    out[#out + 1] = string.format("Pace: %.1f yards a second on foot, mounted x%.2f (%s).", run, 1 / mount, measured or "the tables' guess")
  end
  out[#out + 1] = string.format("Read %d times, %d trait events.", d.reads, d.events)
  return out
end

function L.OnEvent(event)
  if event == "PLAYER_ENTERING_WORLD" then
    L.Read()
  else
    diag().events = diag().events + 1
    L.Read()
  end
end

function L:Init()
  if self.frame then return end
  local f = CreateFrame("Frame")
  self.frame = f
  f:SetScript("OnEvent", QB.Safe(function(_, event, ...) L.OnEvent(event, ...) end, "legacy"))
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "TRAIT_CONFIG_LIST_UPDATED" }) do
    pcall(f.RegisterEvent, f, e)
  end
end

----------------------------------------------------------------------------
-- measured: your pace, on foot and mounted
----------------------------------------------------------------------------
local Ms = {}
QB.Measure = Ms

local KEEP = 15            -- samples kept a state
local ENOUGH = 5           -- samples before a median counts
local FOOT = { 4, 12 }     -- yards a second on foot that can be real (7 runs; a speed enchant 7.56)
local RIDE = { 8, 20 }     -- mounted (11.2 on a 60% mount, 14 on a 100%)
-- speed buffs that would skew a sample: by spell id, and by name (Westfall Stew's is Forever's own)
-- (SpellName 1.60.1.70338: 5118 Aspect of the Cheetah, 783 Travel Form, 2645 Ghost Wolf, 2983 Sprint, 1850 Dash, 13159 Aspect of
-- the Pack, 2379 Speed (the Swiftness Potion), 8892 Goblin Rocket Boots)
Ms.SKIP_ID = { [5118] = true, [783] = true, [2645] = true, [2983] = true, [1850] = true, [13159] = true, [2379] = true, [8892] = true }
Ms.SKIP_NAME = { ["Westfall Stew"] = true, ["Aspect of the Cheetah"] = true, ["Travel Form"] = true, ["Ghost Wolf"] = true, ["Sprint"] = true,
                 ["Dash"] = true, ["Aspect of the Pack"] = true, ["Goblin Rocket Boots"] = true }
Ms.KEEP, Ms.ENOUGH = KEEP, ENOUGH

local function db()
  QuestBankDB = QuestBankDB or {}
  QuestBankDB.chars = QuestBankDB.chars or {}
  local key = QB:CharKey()
  local c = QuestBankDB.chars[key]
  if type(c) ~= "table" then c = {}; QuestBankDB.chars[key] = c end
  local m = c.measure
  if type(m) ~= "table" then m = {}; c.measure = m end
  if type(m.foot) ~= "table" then m.foot = {} end
  if type(m.mount) ~= "table" then m.mount = {} end
  return m
end
Ms.DB = db

local function median(list)
  local n = #list
  if n < ENOUGH then return nil end
  local s = {}
  for i = 1, n do s[i] = list[i] end
  table.sort(s)
  if n % 2 == 1 then return s[(n + 1) / 2] end
  return (s[n / 2] + s[n / 2 + 1]) / 2
end

local function yes(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, v = pcall(fn, ...)
  return ok and plain(v) == true
end

-- a speed buff on you: no sample now
local function buffed()
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not get then return false end
  for i = 1, 40 do
    local ok, a = pcall(get, "player", i, "HELPFUL")
    if not ok or type(a) ~= "table" then break end
    local id, n = plain(a.spellId), plain(a.name)
    if (type(id) == "number" and Ms.SKIP_ID[id]) or (type(n) == "string" and Ms.SKIP_NAME[n]) then return true end
  end
  return false
end

-- one look at GetUnitSpeed: the run speed the game gives you now, kept under foot or mount. True when a sample was taken
function Ms.Sample()
  if type(GetUnitSpeed) ~= "function" then return false end
  if IsInInstance then
    local ok, inside = pcall(IsInInstance)
    if not ok or plain(inside) ~= false then return false end
  end
  if yes(UnitOnTaxi, "player") or yes(UnitIsDeadOrGhost, "player") or yes(UnitInVehicle, "player") then return false end
  local ok, cur, run = pcall(GetUnitSpeed, "player")
  if not ok then return false end
  cur, run = plain(cur), plain(run)
  if type(run) ~= "number" or run <= 0 then return false end
  if type(cur) ~= "number" or cur <= 0 then return false end -- standing still: the stat is yours, but a moving sample is the one that counts
  if buffed() then return false end
  local mounted = yes(IsMounted)
  local range = mounted and RIDE or FOOT
  if run < range[1] or run > range[2] then return false end
  local m = db()
  local list = mounted and m.mount or m.foot
  list[#list + 1] = floor(run * 100 + 0.5) / 100
  while #list > KEEP do table.remove(list, 1) end
  m.run, m.ride = median(m.foot), median(m.mount)
  m.at = time and time() or 0
  Ms.ver = (Ms.ver or 0) + 1
  return true
end

-- what was measured: yards a second on foot and mounted (nil until enough samples)
function Ms.Speeds()
  local m = db()
  return m.run, m.ride
end

function Ms.Reset()
  local m = db()
  m.foot, m.mount, m.run, m.ride = {}, {}, nil, nil
  Ms.ver = (Ms.ver or 0) + 1
end
