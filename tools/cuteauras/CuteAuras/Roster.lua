-- SPDX-License-Identifier: GPL-3.0-or-later
-- The group: each member's unit, GUID, name, class, level, raid subgroup and role. A role is, first, what the member's
-- own Cute Auras announced (their talents or their choice in Settings), then the role the group set
-- (UnitGroupRolesAssigned: a role check, the raid's main tank), then the class's. Only what every client sees the same,
-- so every client shares the buffs out the same (an inspect would differ by range and timing). Forever has one
-- ChrSpecialization row a class: the spec is the talent tree's point group with the most spent (C_Traits, its skill
-- line), read on your own client and announced.
local _, A = ...
local R = A.Part("Roster", { members = {}, byGUID = {}, byUnit = {}, gen = 0 })
local plain, call = A.Plain, A.Call

-- the talent trees' skill lines (SkillLine.csv, category 7) and the role each says
R.SPEC_ROLE = {
  [26] = "melee", [256] = "melee", [257] = "tank",            -- warrior: Arms, Fury, Protection
  [594] = "healer", [267] = "tank", [184] = "melee",          -- paladin: Holy, Protection, Retribution
  [50] = "ranged", [163] = "ranged", [51] = "ranged",         -- hunter
  [253] = "melee", [38] = "melee", [39] = "melee",            -- rogue
  [613] = "healer", [56] = "healer", [78] = "caster",         -- priest: Discipline, Holy, Shadow
  [375] = "caster", [373] = "melee", [374] = "healer",        -- shaman: Elemental, Enhancement, Restoration
  [237] = "caster", [8] = "caster", [6] = "caster",           -- mage
  [355] = "caster", [354] = "caster", [593] = "caster",       -- warlock
  [574] = "caster", [134] = "melee", [573] = "healer",        -- druid: Balance, Feral, Restoration
}
-- a class's role when nothing else says (a hybrid as the healer it most often is in a group)
R.CLASS_ROLE = { WARRIOR = "melee", ROGUE = "melee", HUNTER = "ranged", MAGE = "caster", WARLOCK = "caster",
  PRIEST = "healer", PALADIN = "healer", SHAMAN = "healer", DRUID = "healer" }
-- the classes with a mana bar
R.MANA = { MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true, PALADIN = true, SHAMAN = true, HUNTER = true }
R.ROLES = { "tank", "healer", "melee", "ranged", "caster" }

----------------------------------------------------------------------------
-- the spec from a talent config: the point group with the most spent, its skill line, and the points
----------------------------------------------------------------------------
local function specOf(configID, treeID)
  local T = C_Traits
  if not (T and treeID) then return nil end
  local disp = call(T.GetGroupDisplayInfoByTreeID, treeID)
  if type(disp) ~= "table" then return nil end
  local ids, line = {}, {}
  for _, d in ipairs(disp) do
    local g, sl = plain(d.groupID), plain(d.skillLineID)
    if type(g) == "number" then ids[#ids + 1] = g; line[g] = sl end
  end
  if #ids == 0 then return nil end
  local cur = call(T.GetGroupCurrencyInfo, configID, ids)
  if type(cur) ~= "table" then return nil end
  local best, bestN = nil, 0
  for _, g in ipairs(cur) do
    local spent = 0
    for _, c in ipairs(type(g.currencyInfos) == "table" and g.currencyInfos or {}) do
      spent = spent + (plain(c.spent) or plain(c.spentInTree) or 0)
    end
    local gid = plain(g.traitNodeGroupID)
    if spent > bestN and gid and line[gid] then best, bestN = line[gid], spent end
  end
  return best, bestN
end
R.SpecOf = specOf
function R.MySpec()
  local CT, T, SI = C_ClassTalents, C_Traits, C_SpecializationInfo
  if not (CT and T) then return nil end
  -- (dual spec: the talents of the spec group you are in, as the game's talent frame reads them; else the active one)
  local cfg
  if SI and type(SI.GetActiveSpecGroup) == "function" and type(SI.GetCombatConfigIDForSpecGroup) == "function" then
    local g = plain(call(SI.GetActiveSpecGroup))
    if type(g) == "number" then cfg = plain(call(SI.GetCombatConfigIDForSpecGroup, g)) end
  end
  cfg = cfg or plain(call(CT.GetActiveConfigID))
  if type(cfg) ~= "number" then return nil end
  local info = call(T.GetConfigInfo, cfg)
  local tree = type(info) == "table" and type(info.treeIDs) == "table" and plain(info.treeIDs[1]) or nil
  return specOf(cfg, tree)
end

local function classOf(unit)
  local ok, _, class = pcall(UnitClass, unit)
  class = ok and plain(class) or nil
  return type(class) == "string" and class or nil
end
local function roleAssigned(unit)
  local v = plain(call(UnitGroupRolesAssigned, unit))
  if v == "TANK" then return "tank" elseif v == "HEALER" then return "healer" elseif v == "DAMAGER" then return "dps" end
  if type(GetPartyAssignment) == "function" and A.Yes(GetPartyAssignment, "MAINTANK", unit) then return "tank" end
  return nil
end
-- a damage dealer's role by class (a hybrid set to damage: its talents decide, else the caster it most often is)
local DPS = { WARRIOR = "melee", ROGUE = "melee", HUNTER = "ranged", MAGE = "caster", WARLOCK = "caster", PRIEST = "caster",
  PALADIN = "melee", SHAMAN = "caster", DRUID = "caster" }

-- your own role: this character's choice in Settings, else your talents, else the group's word, else your class's
function R.MyRole()
  local s = A.Char().role
  if s and s ~= "auto" then return s, nil end
  local spec = R.MySpec()
  local assigned = roleAssigned("player")
  if assigned == "tank" or assigned == "healer" then return assigned, spec end
  if spec and R.SPEC_ROLE[spec] then return R.SPEC_ROLE[spec], spec end
  local class = classOf("player")
  if assigned == "dps" then return DPS[class or ""] or "melee", spec end
  return R.CLASS_ROLE[class or ""] or "melee", spec
end

----------------------------------------------------------------------------
-- the roster
----------------------------------------------------------------------------
local function roleOf(m)
  if m.me then return (R.MyRole()) end
  local peer = A.Comm and A.Comm.peers[m.guid]
  if peer and peer.role and peer.role ~= "" then return peer.role end
  local assigned = roleAssigned(m.unit)
  if assigned == "tank" or assigned == "healer" then return assigned end
  -- (the share-out reads only what every client has: a member's own word, the group's roles, the class; an inspect
  -- here would differ by range and timing from client to client, and the clients would split the buffs differently)
  local spec = peer and peer.spec
  if spec and R.SPEC_ROLE[spec] then return R.SPEC_ROLE[spec] end
  if assigned == "dps" then return DPS[m.class or ""] or "melee" end
  return R.CLASS_ROLE[m.class or ""] or "melee"
end
R.RoleOf = roleOf

-- the group's units in order: the raid's, else you and your party
local unitsBuf = {}
function R.Units()
  for i = #unitsBuf, 1, -1 do unitsBuf[i] = nil end
  if A.Yes(IsInRaid) then
    local n = plain(call(GetNumGroupMembers)) or 0
    for i = 1, math.min(n, 40) do unitsBuf[#unitsBuf + 1] = "raid" .. i end
  else
    unitsBuf[1] = "player"
    local n = plain(call(GetNumSubgroupMembers)) or 0
    for i = 1, math.min(n, 4) do unitsBuf[#unitsBuf + 1] = "party" .. i end
  end
  return unitsBuf
end
function R.InGroup() return A.Yes(IsInGroup) end
function R.InRaid() return A.Yes(IsInRaid) end

local pool = {}
function R.Scan()
  local me = A.MyGUID()
  local members, byGUID, byUnit = R.members, R.byGUID, R.byUnit
  for i = #members, 1, -1 do members[i] = nil end
  for k in pairs(byGUID) do byGUID[k] = nil end
  for k in pairs(byUnit) do byUnit[k] = nil end
  local raid = R.InRaid()
  local sig = {}
  for i, unit in ipairs(R.Units()) do
    local guid = plain(call(UnitGUID, unit))
    if type(guid) == "string" and guid ~= "" then
      local m = pool[#members + 1]
      if not m then m = {}; pool[#members + 1] = m end
      for k in pairs(m) do m[k] = nil end
      m.unit, m.guid, m.index = unit, guid, i
      m.me = guid == me
      local name = plain(call(UnitName, unit))
      m.name = type(name) == "string" and name or "?"
      m.class = classOf(unit)
      m.level = plain(call(UnitLevel, unit)) or 1
      if type(m.level) ~= "number" or m.level < 1 then m.level = 60 end -- (a ?? level: as high as the game goes)
      m.sub = 1
      if raid and type(GetRaidRosterInfo) == "function" then
        local ok, _, _, sub = pcall(GetRaidRosterInfo, i)
        sub = ok and plain(sub) or nil
        if type(sub) == "number" then m.sub = sub end
      end
      m.online = A.Yes(UnitIsConnected, unit)
      m.mana = R.MANA[m.class or ""] == true
      members[#members + 1] = m
      byGUID[guid] = m
      byUnit[unit] = m
      sig[#sig + 1] = guid .. m.sub .. m.level .. (m.online and 1 or 0)
    end
  end
  for _, m in ipairs(members) do m.role = roleOf(m) end
  for _, m in ipairs(members) do sig[#sig + 1] = m.role end
  local s = table.concat(sig, ",")
  if s ~= R.sig then R.sig = s; R.gen = R.gen + 1 end
  return members
end
-- the member a unit token is now, a GUID, or a name (with or without its realm)
function R.ByUnit(unit) return R.byUnit[unit] end
function R.ByGUID(guid) return R.byGUID[guid] end
function R.ByName(name)
  if type(name) ~= "string" then return nil end
  local short = name:match("^([^%-]+)") or name
  for _, m in ipairs(R.members) do if m.name == short or m.name == name then return m end end
  return nil
end
function R.Me() return R.byGUID[A.MyGUID() or ""] end

----------------------------------------------------------------------------
-- a change to the group: one scan for a burst, then the assignment and the bar
----------------------------------------------------------------------------
local soon = false
function R.Changed()
  if soon then return end
  soon = true
  A.After(0.3, function()
    soon = false
    local gen = R.gen
    R.Scan()
    if R.gen ~= gen and A.Assign then A.Assign.Changed() end
    if A.Bar then A.Bar.Dirty("group") end
  end, "roster")
end

function R:Init()
  R.Scan()
  A.On("GROUP_ROSTER_UPDATE", R.Changed)
  A.On("PLAYER_ENTERING_WORLD", R.Changed)
  A.On("PLAYER_ROLES_ASSIGNED", R.Changed)
  A.On("UNIT_LEVEL", R.Changed)
  A.On("PLAYER_LEVEL_UP", R.Changed)
  A.On("TRAIT_CONFIG_UPDATED", R.Changed)
  A.On("PLAYER_TALENT_UPDATE", R.Changed)
  -- (a dual spec switch: your role and spec again, and your hello says so)
  for _, ev in ipairs({ "ACTIVE_TALENT_GROUP_CHANGED", "ACTIVE_COMBAT_CONFIG_CHANGED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" }) do
    A.On(ev, function() R.Changed(); if A.Bar then A.Bar.Dirty("all") end end)
  end
end
