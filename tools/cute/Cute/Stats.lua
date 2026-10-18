-- SPDX-License-Identifier: GPL-3.0-or-later
-- The stat registry: one S.def per stat. Everything else (sampling, the wire format, the dashboard's columns, the
-- Settings checklists) is generated from this table, so a new stat is one line here.
--   id        short ASCII, stable for life; the wire key
--   label     the column header or card title
--   cat       leveling | prog | funny | officer: the default tab and the default visibility
--   read      a function returning the value (under pcall; a secret value reads as nil)
--   count     an event the addon counts for this stat (kept per character in CuteDB)
--   track     true: a value Sample.lua's ticker or hooks set (kept per character too)
--   on        an event, or a list, after which the stat is re-read; none means the heartbeat reads it
--   kind      int | flag | text | list | pips
--   of        for a list: the fixed set of things it is a bitmap over ({ { key, label }, ... }, at most 30)
--   fmt       optional display formatter
--   default   "all" or "self"; the category's default applies otherwise
--   hint      a line for the tooltip saying how it is measured
local _, C = ...
local S = { list = {}, byId = {}, byCat = { leveling = {}, prog = {}, funny = {}, officer = {} } }
C.Stats = S

S.CATS = { "leveling", "prog", "funny", "officer" }
S.CAT_LABEL = { leveling = "Race", prog = "Prog", funny = "Hall of Shame", officer = "Officers" }
S.CAT_DEFAULT = { leveling = "all", prog = "all", funny = "all", officer = "self" }
local KINDS = { int = true, flag = true, text = true, list = true, pips = true }

function S.def(id, label, cat, o)
  assert(type(id) == "string" and id:match("^[%l%d_]+$") and #id <= 16, "stat id: " .. tostring(id))
  assert(not S.byId[id], "stat defined twice: " .. id)
  assert(S.byCat[cat], "stat category: " .. tostring(cat))
  o = o or {}
  o.kind = o.kind or (o.count and "int") or "int"
  assert(KINDS[o.kind], "stat kind: " .. tostring(o.kind))
  assert(o.kind ~= "list" or (type(o.of) == "table" and #o.of >= 1 and #o.of <= 30), "a list stat needs 1 to 30 things: " .. id)
  assert(o.read or o.count or o.track, "a stat reads, counts or tracks: " .. id)
  if type(o.on) == "string" then o.on = { o.on } end
  o.id, o.label, o.cat = id, label, cat
  o.default = o.default or S.CAT_DEFAULT[cat]
  S.list[#S.list + 1] = o
  S.byId[id] = o
  S.byCat[cat][#S.byCat[cat] + 1] = o
  return o
end

----------------------------------------------------------------------------
-- readers. Each returns a plain value or nil. The client's optional APIs are looked up at call time.
----------------------------------------------------------------------------
local Get, Num = C.Get, C.Num
local function api(ns, name)
  local t = _G[ns]
  return type(t) == "table" and t[name] or nil
end
local function money() return Num(GetMoney) end
local function gold() local m = money(); return m and math.floor(m / 10000) or nil end

local function itemCount(id)
  local n = Num(api("C_Item", "GetItemCount"), id)
  if n == nil then n = Num(GetItemCount, id) end
  return n or 0
end

local function invLink(slot) local l = Get(GetInventoryItemLink, "player", slot); return type(l) == "string" and l or nil end
local function linkId(link) return link and tonumber(link:match("item:(%d+)")) end
local function linkEnchant(link) return link and tonumber(link:match("item:%d+:(%d*)")) or 0 end
local function itemLevelOf(link)
  if not link then return nil end
  local lvl = Num(api("C_Item", "GetDetailedItemLevelInfo"), link)
  if lvl == nil then local _, _, _, il = Get(GetItemInfo, link); lvl = type(il) == "number" and il or nil end
  return lvl
end
local function itemQuality(link)
  if not link then return nil end
  local q = Num(api("C_Item", "GetItemQualityByID"), link)
  if q == nil then local _, _, qq = Get(GetItemInfo, link); q = type(qq) == "number" and qq or nil end
  return q
end
-- the sixteen gear slots the game shows (no shirt, tabard, ammo)
local GEAR = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local SLOT = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrist",
  [10] = "Hands", [11] = "Ring 1", [12] = "Ring 2", [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back", [16] = "Main hand",
  [17] = "Off hand", [18] = "Ranged" }
local SLOT_OF = {}
for _, s in ipairs(GEAR) do SLOT_OF[#SLOT_OF + 1] = { s, SLOT[s] } end
-- the slots an enchant goes on at 60
local ENCHANTABLE = { [1] = true, [3] = true, [5] = true, [7] = true, [8] = true, [9] = true, [10] = true, [15] = true, [16] = true, [17] = true }
local function slotSet(test)
  local out = {}
  for _, s in ipairs(GEAR) do if test(s, invLink(s)) then out[s] = true end end
  return out
end

-- buffs on you, by spell id and name, read once a second at most
local auraCache, auraAt = nil, -1
local function auras()
  local now = (GetTime and GetTime()) or 0
  if auraCache and now - auraAt < 1 then return auraCache end
  local ids, names = {}, {}
  local byIndex = api("C_UnitAuras", "GetAuraDataByIndex")
  for i = 1, 60 do
    local a
    if byIndex then
      a = Get(byIndex, "player", i, "HELPFUL")
      if type(a) ~= "table" then break end
      local sid, nm = C.Plain(a.spellId), C.Plain(a.name)
      if type(sid) == "number" then ids[sid] = true end
      if type(nm) == "string" then names[nm] = true end
    else
      local nm, _, _, _, _, _, _, _, _, sid = Get(UnitAura, "player", i, "HELPFUL")
      if nm == nil then break end
      if type(nm) == "string" then names[nm] = true end
      if type(sid) == "number" then ids[sid] = true end
    end
  end
  auraCache, auraAt = { ids = ids, names = names }, now
  return auraCache
end

-- a quest's state as a pip: 2 done, 1 in the log, 0 not started
local function questPip(id)
  if Get(api("C_QuestLog", "IsQuestFlaggedCompleted"), id) == true then return 2 end
  local idx = Num(api("C_QuestLog", "GetLogIndexForQuestID"), id)
  if idx and idx > 0 then return 1 end
  return 0
end
local function steps(ids) return function() local s = {}; for i, q in ipairs(ids) do s[i] = questPip(q) end; return table.concat(s) end end

local function bagFree()
  local total = 0
  local free = api("C_Container", "GetContainerNumFreeSlots") or GetContainerNumFreeSlots
  if not free then return nil end
  for b = 0, 4 do local n = Num(free, b); total = total + (n or 0) end
  return total
end
local function bagSize()
  local total = 0
  local slots = api("C_Container", "GetContainerNumSlots") or GetContainerNumSlots
  if not slots then return nil end
  for b = 0, 4 do local n = Num(slots, b); total = total + (n or 0) end
  return total
end

local function profession(i)
  local idx = { Get(GetProfessions) }
  local p = idx[i]
  if type(p) ~= "number" then return nil end
  local name, _, skill, max = Get(GetProfessionInfo, p)
  if type(name) ~= "string" then return nil end
  return name, skill, max
end

local function legacyRank(node)
  local cfgOf, info = api("C_Traits", "GetConfigIDByTreeID"), api("C_Traits", "GetNodeInfo")
  if not (cfgOf and info) then return nil end
  for _, tree in ipairs({ 1187, 1188, 1189 }) do
    local cfg = Num(cfgOf, tree)
    if cfg then
      local n = Get(info, cfg, node)
      if type(n) == "table" and type(C.Plain(n.activeRank)) == "number" and n.activeRank > 0 then return n.activeRank end
    end
  end
  return 0
end

local function listOf(of, test)
  local out = {}
  for _, e in ipairs(of) do if test(e[1]) then out[e[1]] = true end end
  return out
end

local function hours(sec) if not sec then return "?" end local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60); return h > 0 and string.format("%dh %02dm", h, m) or string.format("%dm", m) end
S.FmtHours = hours
local function pct(v) return v and string.format("%d%%", v) or "?" end
S.FmtPct = pct

----------------------------------------------------------------------------
-- leveling
----------------------------------------------------------------------------
local D = S.def
D("level", "Level", "leveling", { read = function() return Num(UnitLevel, "player") end, on = "PLAYER_LEVEL_UP" })
D("xp", "XP into level", "leveling", { read = function() local x, m = Num(UnitXP, "player"), Num(UnitXPMax, "player"); if x and m and m > 0 then return math.floor(x * 100 / m) end end,
  on = { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP" }, fmt = pct, hint = "percent of the level" })
D("xp_hour", "XP/hour", "leveling", { track = true, hint = "XP gained in the last hour of play" })
D("xp_session", "XP/hour today", "leveling", { track = true, hint = "XP an hour since you logged in" })
D("played", "Time played", "leveling", { track = true, fmt = hours })
D("played_lvl", "Played this level", "leveling", { track = true, fmt = hours })
D("to60", "Hours to 60", "leveling", { track = true, hint = "at the last hour's pace" })
D("rested", "Rested XP", "leveling", { read = function() local r = Num(GetXPExhaustion); return r or 0 end, on = "UPDATE_EXHAUSTION" })
D("zone", "Zone", "leveling", { read = function() local z = Get(GetZoneText); return type(z) == "string" and z or nil end, kind = "text",
  on = { "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "PLAYER_ENTERING_WORLD" } })
D("subzone", "Subzone", "leveling", { read = function() local z = Get(GetSubZoneText); return type(z) == "string" and z or nil end, kind = "text",
  on = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" } })
D("group", "Grouped with", "leveling", { kind = "text", on = "GROUP_ROSTER_UPDATE", read = function()
  local names = {}
  for i = 1, 4 do local n = Get(UnitName, "party" .. i); if type(n) == "string" then names[#names + 1] = n end end
  return #names > 0 and table.concat(names, ", ") or ""
end })
D("logins", "Logins this week", "leveling", { track = true })
D("session", "Session", "leveling", { track = true, fmt = hours, hint = "this login so far" })
D("longest", "Longest session", "leveling", { track = true, fmt = hours })
D("quests_done", "Quests done", "leveling", { read = function()
  local all = Get(api("C_QuestLog", "GetAllCompletedQuestIDs"))
  if type(all) == "table" then return #all end
end, on = "QUEST_TURNED_IN" })
D("quests_today", "Quests today", "leveling", { count = "QUEST_TURNED_IN", hint = "counted since the addon was installed, reset daily" })
D("quests_log", "Quests in log", "leveling", { read = function() local _, n = Get(api("C_QuestLog", "GetNumQuestLogEntries")); return type(n) == "number" and n or nil end,
  on = { "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED" } })
D("quests_ready", "Ready to hand in", "leveling", { on = "QUEST_LOG_UPDATE", read = function()
  local getInfo, isComplete = api("C_QuestLog", "GetInfo"), api("C_QuestLog", "IsComplete")
  local n = Num(api("C_QuestLog", "GetNumQuestLogEntries"))
  if not (getInfo and isComplete and n) then return nil end
  local ready = 0
  for i = 1, n do
    local q = Get(getInfo, i)
    if type(q) == "table" and not C.Plain(q.isHeader) and type(C.Plain(q.questID)) == "number" and Get(isComplete, q.questID) == true then ready = ready + 1 end
  end
  return ready
end })
D("dungeons", "Dungeons run", "leveling", { count = "DUNGEON_ENTERED", hint = "dungeon instances entered" })
D("kills", "Kills (XP)", "leveling", { count = "CHAT_MSG_COMBAT_XP_GAIN", hint = "XP gains from kills, counted" })
D("zones_seen", "Zones visited", "leveling", { track = true })
D("flights_known", "Flight paths", "leveling", { track = true, hint = "known, as the taxi map last showed" })
D("flights", "Flights taken", "leveling", { track = true })
D("longest_flight", "Longest flight", "leveling", { track = true, fmt = hours })
D("hearth", "Hearth set to", "leveling", { read = function() local b = Get(GetBindLocation); return type(b) == "string" and b or nil end, kind = "text", on = "HEARTHSTONE_BOUND" })
D("hearths", "Hearthstones used", "leveling", { track = true })
D("deaths_lvl", "Deaths while leveling", "leveling", { track = true })
D("ghost_time", "Time as a ghost", "leveling", { track = true, fmt = hours })
D("gold_earned", "Gold earned", "leveling", { track = true, hint = "every rise of your purse, summed" })
D("gold_quests", "Gold from quests", "leveling", { track = true })
D("vendor_sales", "Sold to vendors", "leveling", { track = true, hint = "gold, while a merchant was open" })
D("mount", "Mount", "leveling", { kind = "flag", read = function()
  local ids = Get(api("C_MountJournal", "GetMountIDs"))
  if type(ids) ~= "table" then return nil end
  local info = api("C_MountJournal", "GetMountInfoByID")
  for _, id in ipairs(ids) do
    local _, _, _, _, _, _, _, _, _, _, collected = Get(info, id)
    local r = { Get(info, id) }
    if r[11] == true then return true end
  end
  return false
end })
D("talents_free", "Unspent talents", "leveling", { read = function() return Num(GetNumUnspentTalents) end, on = { "PLAYER_TALENT_UPDATE", "PLAYER_LEVEL_UP" } })
D("spec", "Spec", "leveling", { kind = "text", on = "PLAYER_TALENT_UPDATE", read = function()
  local i = Num(GetSpecialization)
  if not i then return nil end
  local _, name = Get(GetSpecializationInfo, i)
  return type(name) == "string" and name or nil
end })
D("prof1", "Profession 1", "leveling", { kind = "text", on = "SKILL_LINES_CHANGED", read = function() local n, s = profession(1); return n and (n .. " " .. tostring(s or "")) or "" end })
D("prof2", "Profession 2", "leveling", { kind = "text", on = "SKILL_LINES_CHANGED", read = function() local n, s = profession(2); return n and (n .. " " .. tostring(s or "")) or "" end })
D("fishing", "Fishing", "leveling", { on = "SKILL_LINES_CHANGED", read = function() local _, s = profession(4); return s end })
D("cooking", "Cooking", "leveling", { on = "SKILL_LINES_CHANGED", read = function() local _, s = profession(5); return s end })
D("first_aid", "First Aid", "leveling", { on = "SKILL_LINES_CHANGED", read = function() local _, s = profession(6); return s end })
local LEGACY = { { 110300, "Frequent Flier" }, { 110304, "Field Guide" }, { 110313, "Gourmand" }, { 110316, "Permanence" }, { 110301, "Well Rested" } }
D("legacy", "Legacy perks", "leveling", { kind = "list", of = LEGACY, on = "TRAIT_CONFIG_UPDATED", read = function()
  return listOf(LEGACY, function(node) local r = legacyRank(node); return r ~= nil and r > 0 end)
end })
D("levelups", "Level-ups today", "leveling", { count = "PLAYER_LEVEL_UP" })
D("still", "Longest stood still", "leveling", { track = true, fmt = hours, default = "all" })

----------------------------------------------------------------------------
-- progression
----------------------------------------------------------------------------
D("ilvl", "Item level", "prog", { read = function() local _, equipped = Get(GetAverageItemLevel); return type(equipped) == "number" and math.floor(equipped) or nil end,
  on = "PLAYER_EQUIPMENT_CHANGED" })
D("ilvl_slots", "Item level per slot", "prog", { kind = "list", of = SLOT_OF, on = "PLAYER_EQUIPMENT_CHANGED", hint = "slots at or above your average", read = function()
  local _, avg = Get(GetAverageItemLevel)
  avg = type(avg) == "number" and avg or 0
  return slotSet(function(_, link) local l = itemLevelOf(link); return l ~= nil and l >= avg end)
end })
D("empty_slots", "Empty slots", "prog", { kind = "list", of = SLOT_OF, default = "self", on = "PLAYER_EQUIPMENT_CHANGED",
  read = function() return slotSet(function(s, link) return link == nil and s ~= 17 and s ~= 18 end) end })
D("unenchanted", "Unenchanted", "prog", { kind = "list", of = SLOT_OF, default = "self", on = "PLAYER_EQUIPMENT_CHANGED",
  read = function() return slotSet(function(s, link) return ENCHANTABLE[s] and link ~= nil and linkEnchant(link) == 0 end) end })
D("old_gear", "Gear 10+ levels old", "prog", { kind = "list", of = SLOT_OF, default = "self", on = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP" }, read = function()
  local lvl = Num(UnitLevel, "player") or 1
  return slotSet(function(_, link) local l = itemLevelOf(link); return l ~= nil and l < lvl - 10 end)
end })
D("greens", "Green items worn", "prog", { default = "self", on = "PLAYER_EQUIPMENT_CHANGED", read = function()
  local n = 0
  for _, s in ipairs(GEAR) do local q = itemQuality(invLink(s)); if q ~= nil and q <= 2 then n = n + 1 end end
  return n
end })
-- attunements and keys. Quest ids are Classic's; Forever's uploads will correct them
D("attune_mc", "Molten Core", "prog", { kind = "pips", pips = 1, read = steps({ 7848 }), on = "QUEST_LOG_UPDATE", hint = "Attunement to the Core" })
D("attune_ony_a", "Onyxia (Alliance)", "prog", { kind = "pips", pips = 13, on = "QUEST_LOG_UPDATE",
  read = steps({ 4182, 4183, 4184, 4185, 4186, 4224, 4264, 4282, 4322, 4321, 4341, 4342, 6502 }), hint = "Dragonkin Menace to Drakefire Amulet" })
D("attune_ony_h", "Onyxia (Horde)", "prog", { kind = "pips", pips = 11, on = "QUEST_LOG_UPDATE",
  read = steps({ 4903, 4941, 4974, 6566, 6567, 6568, 6569, 6570, 6601, 6602, 6702 }), hint = "Warlord's Command to Drakefire Amulet" })
local KEYS = { { 12344, "Seal of Ascension" }, { 13704, "Skeleton Key" }, { 18249, "Crescent Key" }, { 11000, "Shadowforge Key" },
  { 12382, "Key to the City" }, { 9240, "Mallet of Zul'Farrak" }, { 17191, "Scepter of Celebras" } }
D("keys", "Keys", "prog", { kind = "list", of = KEYS, on = "BAG_UPDATE_DELAYED", read = function() return listOf(KEYS, function(id) return itemCount(id) > 0 end) end })
D("resist_fire", "Fire resist", "prog", { read = function() local _, v = Get(UnitResistance, "player", 2); return type(v) == "number" and v or nil end, on = "PLAYER_EQUIPMENT_CHANGED" })
D("resist_nature", "Nature resist", "prog", { read = function() local _, v = Get(UnitResistance, "player", 3); return type(v) == "number" and v or nil end, on = "PLAYER_EQUIPMENT_CHANGED" })
D("resist_frost", "Frost resist", "prog", { read = function() local _, v = Get(UnitResistance, "player", 4); return type(v) == "number" and v or nil end, on = "PLAYER_EQUIPMENT_CHANGED" })
D("resist_shadow", "Shadow resist", "prog", { read = function() local _, v = Get(UnitResistance, "player", 5); return type(v) == "number" and v or nil end, on = "PLAYER_EQUIPMENT_CHANGED" })
D("resist_arcane", "Arcane resist", "prog", { read = function() local _, v = Get(UnitResistance, "player", 6); return type(v) == "number" and v or nil end, on = "PLAYER_EQUIPMENT_CHANGED" })
D("recipes", "Recipes known", "prog", { track = true, hint = "as your last opened trade skill window listed them" })
local RAID_RECIPES = { { 17635, "Flask of the Titans" }, { 17636, "Flask of Distilled Wisdom" }, { 17637, "Flask of Supreme Power" },
  { 17638, "Flask of Chromatic Resistance" }, { 17556, "Major Healing Potion" }, { 17580, "Major Mana Potion" },
  { 17574, "Greater Fire Protection" }, { 17576, "Greater Nature Protection" }, { 17578, "Greater Shadow Protection" },
  { 17575, "Greater Frost Protection" }, { 18560, "Mooncloth" }, { 16729, "Lionheart Helm" }, { 16994, "Arcanite Reaper" } }
D("raid_recipes", "Raid recipes", "prog", { kind = "list", of = RAID_RECIPES, track = true, hint = "learned, as your trade skill window last showed" })
D("bags_free", "Free bag slots", "prog", { read = bagFree, on = "BAG_UPDATE_DELAYED" })
D("bags_size", "Bag slots", "prog", { read = bagSize, on = "BAG_UPDATE_DELAYED" })
local function counts(ids) return function() local n = 0; for _, id in ipairs(ids) do n = n + itemCount(id) end; return n end end
D("pot_health", "Health potions", "prog", { read = counts({ 13446, 3928, 1710 }), on = "BAG_UPDATE_DELAYED", hint = "Major, Superior, Greater" })
D("pot_mana", "Mana potions", "prog", { read = counts({ 13444, 6149, 3827 }), on = "BAG_UPDATE_DELAYED", hint = "Major, Superior, Greater" })
D("flasks", "Flasks", "prog", { read = counts({ 13510, 13511, 13512, 13513 }), on = "BAG_UPDATE_DELAYED" })
D("elixirs", "Elixirs", "prog", { read = counts({ 13452, 13454, 3825, 9187, 13453, 9206 }), on = "BAG_UPDATE_DELAYED" })
D("food", "Buff food", "prog", { read = counts({ 13931, 13928, 20452, 21023, 18045, 13813 }), on = "BAG_UPDATE_DELAYED" })
D("bandages", "Bandages", "prog", { read = counts({ 14530, 14529, 8545, 8544 }), on = "BAG_UPDATE_DELAYED" })
D("protpots", "Protection potions", "prog", { read = counts({ 13457, 13458, 13459, 13456, 13461 }), on = "BAG_UPDATE_DELAYED" })
local WORLD = { { 22888, "Rallying Cry" }, { 16609, "Warchief's Blessing" }, { 24425, "Spirit of Zandalar" }, { 15366, "Songflower" },
  { 22817, "Fengus' Ferocity" }, { 22818, "Mol'dar's Moxie" }, { 22820, "Slip'kik's Savvy" }, { 23768, "Sayge's Damage" }, { 23769, "Sayge's Resistance" } }
D("world_buffs", "World buffs", "prog", { kind = "list", of = WORLD, on = "UNIT_AURA", read = function() local a = auras(); return listOf(WORLD, function(id) return a.ids[id] end) end })
D("flask_on", "Flask active", "prog", { kind = "flag", on = "UNIT_AURA", read = function()
  local a = auras()
  return (a.ids[17626] or a.ids[17627] or a.ids[17628] or a.ids[17629]) and true or false
end })
local RAIDBUFFS = { { "Power Word: Fortitude", "Fortitude" }, { "Mark of the Wild", "Mark of the Wild" }, { "Arcane Intellect", "Arcane Intellect" },
  { "Blessing of Kings", "Kings" }, { "Divine Spirit", "Divine Spirit" }, { "Shadow Protection", "Shadow Protection" } }
D("buffs_missing", "Raid buffs missing", "prog", { kind = "list", of = RAIDBUFFS, default = "self", on = "UNIT_AURA",
  read = function() local a = auras(); return listOf(RAIDBUFFS, function(name) return not a.names[name] end) end })
D("durability", "Durability", "prog", { fmt = pct, on = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED" }, read = function()
  local worst
  for _, s in ipairs(GEAR) do
    local cur, max = Get(GetInventoryItemDurability, s)
    if type(cur) == "number" and type(max) == "number" and max > 0 then
      local p = math.floor(cur * 100 / max)
      if not worst or p < worst then worst = p end
    end
  end
  return worst
end })
local FACTIONS = { { 529, "Argent Dawn" }, { 59, "Thorium Brotherhood" }, { 749, "Hydraxian Waterlords" }, { 910, "Brood of Nozdormu" },
  { 609, "Cenarion Circle" }, { 270, "Zandalar Tribe" }, { 576, "Timbermaw Hold" } }
D("rep", "Reputation", "prog", { kind = "pips", pips = 7, on = "UPDATE_FACTION", hint = "standing 1 to 8 with the raid factions, in order", read = function()
  local byId = api("C_Reputation", "GetFactionDataByID")
  local s = {}
  for i, f in ipairs(FACTIONS) do
    local standing
    if byId then local d = Get(byId, f[1]); if type(d) == "table" then standing = C.Plain(d.reaction) end
    else local _, _, st = Get(GetFactionInfoByID, f[1]); standing = st end
    s[i] = type(standing) == "number" and math.min(8, math.max(0, standing)) or 0
  end
  return table.concat(s)
end })
S.FACTIONS = FACTIONS
D("pvp_rank", "PvP rank", "prog", { read = function() local r = Num(UnitPVPRank, "player"); if r and r >= 5 then return r - 4 end return 0 end, on = "PLAYER_PVP_RANK_CHANGED" })
D("honor_week", "Honor this week", "prog", { read = function() local _, h = Get(GetPVPThisWeekStats); return type(h) == "number" and h or nil end, on = "PLAYER_PVP_KILLS_CHANGED" })
D("lockouts", "Raid lockouts", "prog", { on = "UPDATE_INSTANCE_INFO", read = function()
  local n = Num(GetNumSavedInstances)
  if not n then return nil end
  local raids = 0
  for i = 1, n do
    local _, _, _, _, locked, _, _, isRaid = Get(GetSavedInstanceInfo, i)
    local r = { Get(GetSavedInstanceInfo, i) }
    if r[5] == true then raids = raids + 1 end
  end
  return raids
end })
D("raids", "Raids attended", "prog", { count = "RAID_ENTERED", hint = "raid instances entered, counted" })
D("stones", "Healthstones", "prog", { read = counts({ 9421, 5510, 5509, 5511, 5512, 19013, 19012, 19011 }), on = "BAG_UPDATE_DELAYED" })
D("shards", "Soul shards", "prog", { read = counts({ 6265 }), on = "BAG_UPDATE_DELAYED" })
D("totems", "Totems", "prog", { read = function() local n = 0; for _, id in ipairs({ 5175, 5176, 5177, 5178 }) do if itemCount(id) > 0 then n = n + 1 end end; return n end, on = "BAG_UPDATE_DELAYED", hint = "of the four" })
D("ammo", "Ammo", "prog", { read = function() return Num(GetInventoryItemCount, "player", 0) end, on = "BAG_UPDATE_DELAYED" })
D("poisons", "Poisons", "prog", { read = counts({ 8985, 20844, 3776, 10922, 8928 }), on = "BAG_UPDATE_DELAYED" })
D("gold", "Gold", "officer", { read = gold, on = "PLAYER_MONEY" })
D("bank_in", "Guild bank deposits", "officer", { track = true, hint = "gold, while the guild bank was open" })
D("bank_out", "Guild bank withdrawals", "officer", { track = true, hint = "gold, while the guild bank was open" })
D("consumed", "Consumables used in raids", "officer", { track = true, hint = "potions, flasks and food that left your bags in a raid" })
D("addon_ver", "Addon version", "officer", { kind = "text", read = function() return C.version end, default = "all" })

----------------------------------------------------------------------------
-- the hall of shame
----------------------------------------------------------------------------
D("deaths", "Deaths", "funny", { count = "PLAYER_DEAD" })
D("deaths_today", "Deaths today", "funny", { count = "PLAYER_DEAD" })
D("falls", "Fall deaths", "funny", { track = true, hint = "died within two seconds of falling" })
D("drownings", "Drownings", "funny", { track = true, hint = "died with the breath bar empty" })
D("fatigue", "Fatigue deaths", "funny", { track = true, hint = "died with the fatigue bar empty" })
D("hearth_waste", "Hearthstones wasted", "funny", { track = true, hint = "a hearth within two minutes of a flight" })
D("afk", "AFK flags", "funny", { track = true })
D("dance", "/dance", "funny", { track = true })
D("sit", "/sit", "funny", { track = true })
D("emotes", "Emotes", "funny", { track = true })
D("whispers", "Whispers an hour", "funny", { track = true, default = "self", hint = "received, counted, never read" })
D("gchat", "Guild chat lines", "funny", { track = true, hint = "your own lines, counted" })
D("inspected", "Inspected others", "funny", { count = "INSPECT_READY" })
D("fish", "Fish caught", "funny", { track = true, hint = "loot windows after a Fishing cast" })
D("jumps", "Jumps", "funny", { track = true })
D("ghost_yards", "Ghost run yards", "funny", { track = true })
D("where", "\"where are you\" typed", "funny", { track = true, hint = "in party or raid chat; wya counts" })
D("grey_gold", "Gold from greys", "funny", { track = true, hint = "vendor sales of grey items" })

----------------------------------------------------------------------------
-- officers'
----------------------------------------------------------------------------
D("main", "Declared main", "officer", { kind = "text", read = function() return C.Settings().main or "" end, default = "all" })
D("role", "Role", "officer", { kind = "text", read = function() return C.Settings().role or "" end, default = "all" })
D("last_login", "Last login", "officer", { track = true, hint = "epoch seconds", default = "all" })
D("raid_spec", "Raid spec set", "officer", { kind = "flag", read = function() return (C.Settings().raidspec and true) or false end })
D("weekly_raids", "Raids this week", "officer", { track = true })
D("ontime", "On time for raid", "officer", { track = true, hint = "in a raid group at the raid's start, counted" })

-- what a category contains, in order
function S.Cat(cat) return S.byCat[cat] end
function S.Get(id) return S.byId[id] end
