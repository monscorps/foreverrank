-- SPDX-License-Identifier: GPL-3.0-or-later
-- The group: each member's unit, GUID, name, class, level, raid subgroup and role. A role is, first, what the member's
-- own Cute Auras announced (their talents or their choice in Settings), then the role the group set
-- (UnitGroupRolesAssigned: a role check, the raid's main tank), then the class's. Only what every client sees the same,
-- so every client shares the buffs out the same (an inspect would differ by range and timing). Forever has one
-- ChrSpecialization row a class: the spec is the talent tree's point group with the most spent (C_Traits, its skill
-- line), read on your own client and announced. Names: UnitName gives the first name and, second, the surname
-- (Camelot's NameUtil.lua); a chat sender carries both, and perhaps a realm (R.SenderMember).
local _, A = ...
local R = A.Part("Roster", { members = {}, byGUID = {}, byUnit = {}, gen = 0, unsure = 0 })
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

-- your own role: this character's choice in Settings, else your talents, else the group's word, else your class's.
-- Its spec, and where it came from: "choice", "group" (a tank or healer mark, or a damage mark), "talents", "class"
-- (only the class's guess: a paladin reads as a healer; the consumables let such a guess hide nothing)
function R.MyRole()
  local s = A.Char().role
  if s and s ~= "auto" then return s, nil, "choice" end
  local spec = R.MySpec()
  local assigned = roleAssigned("player")
  if assigned == "tank" or assigned == "healer" then return assigned, spec, "group" end
  if spec and R.SPEC_ROLE[spec] then return R.SPEC_ROLE[spec], spec, "talents" end
  local class = classOf("player")
  if assigned == "dps" then return DPS[class or ""] or "melee", spec, "group" end
  return R.CLASS_ROLE[class or ""] or "melee", spec, "class"
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
      local okName, name, surname = pcall(UnitName, unit)
      name, surname = okName and plain(name) or nil, okName and plain(surname) or nil
      m.name = type(name) == "string" and name or "?"
      m.surname = type(surname) == "string" and surname ~= "" and surname or nil
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
  -- (a name with a surname, "Ysolde Ashbrook": the one member it can be, as a chat sender is read)
  if short:find(" ", 1, true) or short:find("_", 1, true) then return R.SenderMember(name) end
  return nil
end
function R.Me() return R.byGUID[A.MyGUID() or ""] end
-- the member a chat sender names. Forever writes the surname after the first name ("Ysolde Ashbrook"), perhaps a realm
-- after a dash, and PallyPower a "_" for the space; UnitName gives the first name alone. The members of that first name:
-- one, that one; more, the one whose second UnitName answer is the sender's second word (a surname, or perhaps a realm:
-- the second word only breaks a tie, so a member from another realm still resolves); still not one, nobody, and
-- R.unsure counts it. A member whose name is the whole of it (both words) is that member
function R.SenderMember(sender)
  if type(sender) ~= "string" or sender == "" then return nil end
  local s = (sender:gsub("_", " "))
  s = s:match("^([^%-]+)") or s
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  local first, second = s:match("^(%S+)%s*(%S*)")
  if not first then return nil end
  local hit, n
  n = 0
  for _, m in ipairs(R.members) do
    if second ~= "" and m.name == s then return m end
    if m.name == first then n = n + 1; hit = m end
  end
  if n <= 1 then return hit end
  hit, n = nil, 0
  for _, m in ipairs(R.members) do
    if m.name == first and second ~= "" and m.surname == second then n = n + 1; hit = m end
  end
  if n == 1 then return hit end
  R.unsure = R.unsure + 1
  return nil
end
-- /cauras diag's line on the forms the client gives (words, never a name): our sender (the echo of our hello) and
-- UnitName("player")
function R.NamesLine()
  local s = R.mySender
  local sender = "not heard yet"
  if type(s) == "string" then
    local name, realm = s:match("^([^%-]+)%-?(.*)$")
    local words = select(2, (name or s):gsub("%S+", ""))
    sender = (words == 1 and "one word" or words == 2 and "two words" or (words .. " words")) .. (realm ~= "" and " and realm" or "")
  end
  local ok, first, second = pcall(UnitName, "player")
  first, second = ok and plain(first) or nil, ok and plain(second) or nil
  local words = type(first) == "string" and select(2, first:gsub("%S+", "")) or 0
  return "Names: sender " .. sender .. "; UnitName " .. (words == 1 and "one word" or (words .. " words")) .. ", surname "
    .. ((type(second) == "string" and second ~= "") and "yes" or "no")
end

----------------------------------------------------------------------------
-- your casts' targets (Hands, and the bar's marks in a fight): UNIT_SPELLCAST_SENT names the target (your own name is
-- you; a name that is no member's, or none, is no one), a name the client may hide: then the member a left click on a
-- button of ours casts on (R.NoteClick: the bar's icons and rows, the rebuff and restore cards), else a guess, your
-- friendly target or mouseover who is a member. Kept by the cast's GUID for its UNIT_SPELLCAST_SUCCEEDED, with how it
-- was told ("named", "clicked", "guess": the bar's marks never take a guess, Hands does). The last 16 casts: one sent
-- and never landed is let go with no clean-up of its own
----------------------------------------------------------------------------
local LOOK_AT = { "target", "mouseover" }
-- (a click of ours: the member its unit is now and the spell it casts. Its SENT comes within the click, or, a click the
-- game queued behind the global cooldown, as that ends: within the spell queue window, 0.1 s more for the frame. The
-- next SENT takes it, whatever its spell; one past the window, or of another spell, is someone else's cast)
local click = { guid = nil, spell = nil, at = nil }
local function queueWindow()
  local f = C_Spell and C_Spell.GetSpellQueueWindow
  local ms = type(f) == "function" and plain(call(f)) or nil
  if type(ms) ~= "number" then ms = 400 end
  return math.min(math.max(ms, 0), 400) / 1000 + 0.1
end
function R.Clicking(unit, spell)
  local g = type(unit) == "string" and plain(call(UnitGUID, unit)) or nil
  click.guid, click.spell, click.at = R.byGUID[g or ""] and g or nil, spell, A.Now()
end
-- a button of ours about to act (its PreClick, before the secure OnClick): a left click is the one that casts
R.NoteClick = A.Safe(function(self, button)
  if button ~= "LeftButton" then return end
  R.Clicking(self:GetAttribute("unit"), self:GetAttribute("spell"))
end, "roster: a click's member")
-- (the spell a click casts, its id or its name, and the spell a SENT tells: one id, or one name (a rank the client
-- casts for a name, an id it tells for another of the spell's))
local function sameSpell(noted, sp)
  if noted == nil or type(sp) ~= "number" then return false end
  if noted == sp then return true end
  local name = A.Look.SpellName(sp, nil)
  if name == nil then return false end
  if type(noted) == "number" then noted = A.Look.SpellName(noted, nil) end
  return noted == name
end
-- the member a cast of spell sp went to, and how it was told (a name told that is no member's: none, "named")
function R.MemberFor(targetName, sp)
  if targetName ~= nil then return R.ByName(targetName), "named" end
  if click.guid and click.at and A.Now() - click.at <= queueWindow() and sameSpell(click.spell, sp) and R.byGUID[click.guid] then
    return R.byGUID[click.guid], "clicked"
  end
  for _, u in ipairs(LOOK_AT) do
    local g = plain(call(UnitGUID, u))
    if g and R.byGUID[g] and A.Yes(UnitIsFriend, "player", u) then return R.byGUID[g], "guess" end
  end
  return nil
end
local SENT_KEEP = 16
-- [castGUID] = the member's GUID (false: none told), how it was told; the casts in order
local sentTo, sentHow, sentRing, sentAt = {}, {}, {}, 0
local function onSent(_, unit, target, castGUID, spell)
  if plain(unit) ~= "player" then return end
  local m, how = R.MemberFor(plain(target), plain(spell))
  click.at = nil
  local cg = plain(castGUID)
  if type(cg) ~= "string" then return end
  sentAt = sentAt % SENT_KEEP + 1
  local old = sentRing[sentAt]
  if old ~= nil then sentTo[old], sentHow[old] = nil, nil end
  sentRing[sentAt] = cg
  sentTo[cg], sentHow[cg] = m and m.guid or false, how
end
-- the GUID of the member a cast of yours went to (nil: no member, or it can't be told), and how it was told: "named"
-- (by its name: a member, or no one), "clicked", "guess"; nil, not told (a hidden name, no click of ours, no guess; no
-- SENT)
function R.SentTo(castGUID)
  if castGUID == nil then return nil end
  return sentTo[castGUID] or nil, sentHow[castGUID]
end

----------------------------------------------------------------------------
-- a change to the group: one scan for a burst, then the assignment and the bar
----------------------------------------------------------------------------
local soon = false
local myRoleWas -- (your role and where it came from at the last change: your consumables fit by it, Consume.lua)
function R.Changed()
  if soon then return end
  soon = true
  A.After(0.3, function()
    soon = false
    local gen = R.gen
    R.Scan()
    if R.gen ~= gen and A.Assign then A.Assign.Changed() end
    -- (the units moved under a Hand's restore: its click icon set to the member's unit now)
    if A.Hands then A.Hands.Rostered() end
    local role, _, from = R.MyRole()
    local now = tostring(role) .. ":" .. tostring(from)
    if A.Bar then
      A.Bar.Dirty("group")
      -- (your role from Settings, the group's mark or your talents: your own part read again at once)
      if now ~= myRoleWas then A.Bar.Dirty("mine") end
    end
    myRoleWas = now
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
  A.OnUnit("UNIT_SPELLCAST_SENT", { "player" }, onSent, "roster: a cast sent")
  -- (a dual spec switch: your role and spec again, and your hello says so)
  for _, ev in ipairs({ "ACTIVE_TALENT_GROUP_CHANGED", "ACTIVE_COMBAT_CONFIG_CHANGED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" }) do
    A.On(ev, function() R.Changed(); if A.Bar then A.Bar.Dirty("all") end end)
  end
end
