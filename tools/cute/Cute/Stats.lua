-- SPDX-License-Identifier: GPL-3.0-or-later
-- The stat registry: one S.def per stat. Everything else (sampling, the wire format, the dashboard's columns, the
-- Settings checklists) is generated from this table, so a new stat is one line here.
--   id        short ASCII, stable for life; the wire key
--   label     the column header or card title
--   cat       leveling | prog | funny | officer | game: the default tab and the default visibility (game is filled at
--             login from the client's own statistics; see the end of the file)
--   read      a function returning the value (under pcall; a secret value reads as nil)
--   count     an event the addon counts for this stat (kept per character in CuteDB)
--   track     true: a value Sample.lua's ticker or hooks set (kept per character too)
--   on        an event, or a list, after which the stat is re-read; none means the heartbeat reads it
--   kind      int | flag | text | list | pips
--   of        for a list: the fixed set of things it is a bitmap over ({ { key, label }, ... }, at most 30)
--   fmt       optional display formatter
--   slow      true: changes every few seconds (time played, XP into the level); sent on Comm's two-minute flush,
--             not as they happen, so twenty clients do not fill the guild channel with ticks
--   default   "all" or "self"; the category's default applies otherwise
--   hint      a line for the tooltip saying how it is measured
--   game      for a statistics stat: the game's category id, which the visibility policy is set by ("gc" .. id)
-- Every client API here is in Forever's generated API docs, is read by QuestBank on this client (GetInventoryItemLink),
-- or is called by Blizzard's own Camelot UI code: GetInventoryItemID and GetInventoryItemQuality by Forever's own
-- character sheet (Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua:2219-2221, PaperDollItemSlotButton_Update),
-- GetInventoryItemDurability and GetInventoryItemCount by the Camelot
-- equipment flyout through EquipmentManager_GetItemInfoByLocation (Blizzard_FrameXML/Camelot/EquipmentFlyout.lua:544),
-- GetNumUnspentTalents by the mainline TalentFrameBase.lua the camelot game type loads, GetCategoryList, GetCategoryInfo,
-- GetCategoryNumAchievements and GetAchievementInfo by Blizzard_LegacySystem (Forever's achievement UI, which loads on
-- camelot: Blizzard_LegacyChallenges.lua:128-168), GetTotalAchievementPoints by Blizzard_Communities/GuildRewards.lua:256.
-- The statistics API (GetStatisticsCategoryList, GetStatistic) and GetLatestCompletedAchievements are in the same binary
-- but only the mainline achievement panel calls them, which camelot never loads: they are probed at login (ProbeGame,
-- below) and read only where they exist. /cute api prints which of the undocumented functions the live client has,
-- and a read of a missing one says so in its tooltip. The globals the older clients had (GetItemInfo, UnitAura,
-- GetAverageItemLevel...) are not here, so nothing falls back to them. A global is passed to Get and Num by name
-- ("UnitLevel"), so a missing one reads as a reason, not as nothing.
local _, C = ...
local S = { list = {}, byId = {}, byCat = { leveling = {}, prog = {}, funny = {}, officer = {}, game = {} } }
C.Stats = S

-- game is the dynamic fifth category: the game's own statistics, defined at login from what the client reports
S.CATS = { "leveling", "prog", "funny", "officer", "game" }
S.CAT_LABEL = { leveling = "Race", prog = "Prog", funny = "Hall of Shame", officer = "Officers", game = "Statistics" }
S.CAT_DEFAULT = { leveling = "all", prog = "all", funny = "all", officer = "self", game = "all" }
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
-- readers. Each returns a plain value or nil. The client's namespaced APIs are looked up at call time.
----------------------------------------------------------------------------
local Get, Num, api = C.Get, C.Num, C.Api
local function money() return Num("GetMoney") end

local function itemCount(id) return Num(api("C_Item", "GetItemCount"), id) or 0 end
-- the seventeen gear slots the game shows (no shirt, tabard, ammo)
local GEAR = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local SLOT = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrist",
  [10] = "Hands", [11] = "Ring 1", [12] = "Ring 2", [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back", [16] = "Main hand",
  [17] = "Off hand", [18] = "Ranged" }
local SLOT_OF = {}
for _, s in ipairs(GEAR) do SLOT_OF[#SLOT_OF + 1] = { s, SLOT[s] } end
-- the slots an enchant goes on at 60
local ENCHANTABLE = { [1] = true, [3] = true, [5] = true, [7] = true, [8] = true, [9] = true, [10] = true, [15] = true, [16] = true, [17] = true }

-- the gear you wear, slot by slot, read the way Forever's own character sheet reads it (Camelot/PaperDollFrame.lua,
-- PaperDollItemSlotButton_Update): GetInventoryItemID says what is in a slot, GetInventoryItemQuality its quality.
-- The item level comes from the id, C_Item.GetDetailedItemLevelInfo (documented; its ItemInfo argument takes an id, a
-- name or a link), else C_Item.GetItemInfo's fourth return (an item the client has not cached yet reads nothing from
-- the first). The link is read for the enchant alone, and only when it is a plain string: on this client
-- GetInventoryItemLink gives nothing readable for most slots (0.3.0 showed 15 of 17 slots empty and no item level on
-- a character in full gear), so a stat that needs it says so instead of counting wrong. One scan serves every gear
-- stat read in the same frame; ReadAll starts a fresh one.
local gearCache, gearAt
function S.GearClear() gearCache = nil end
-- a call about a slot of yours: its value made plain, whether the client gave anything (a secret counts), the error.
-- The secret is asked about first: a value that may be one is never compared, not even with nil (Core.lua)
local function slotCall(name, slot)
  local fn = _G[name]
  if type(fn) ~= "function" then C.Missing(name); return nil, false, C.lastErr end
  local ok, v = pcall(fn, "player", slot)
  if not ok then return nil, false, tostring(v) end
  if issecretvalue and issecretvalue(v) then return nil, true end
  return v, v ~= nil
end
local function gear()
  local now = (GetTime and GetTime()) or 0
  if gearCache and gearAt == now then return gearCache end
  local out = { slot = {}, worn = 0, unreadable = 0, noLevel = 0, noQuality = 0 }
  local detailed, info, qualityById = api("C_Item", "GetDetailedItemLevelInfo"), api("C_Item", "GetItemInfo"), api("C_Item", "GetItemQualityByID")
  for _, s in ipairs(GEAR) do
    local id, there, err = slotCall("GetInventoryItemID", s)
    if err then C.lastErr = err; return nil end
    if there then
      local e = { id = type(id) == "number" and id or nil }
      out.worn = out.worn + 1
      if e.id then
        e.level = detailed and Num(detailed, e.id) or nil
        if not e.level and info then local r = { Get(info, e.id) }; e.level = type(r[4]) == "number" and r[4] or nil end
      end
      if not e.level then out.noLevel = out.noLevel + 1 end
      local q = slotCall("GetInventoryItemQuality", s)
      if type(q) ~= "number" and e.id and qualityById then q = Num(qualityById, e.id) end
      e.quality = type(q) == "number" and q or nil
      if not e.quality then out.noQuality = out.noQuality + 1 end
      local link = slotCall("GetInventoryItemLink", s)
      e.link = (type(link) == "string" and link ~= "" and not C.IsKstring(link)) and link or nil
      if not e.link then out.unreadable = out.unreadable + 1 end
      out.slot[s] = e
    end
  end
  gearCache, gearAt = out, now
  return out
end
local function linkEnchant(link) return tonumber(link:match("item:%d+:(%d*)")) or 0 end
-- the slots for which test(slot, item) holds (item nil for an empty slot); nil, with the reason, when the scan failed
local function slotSet(test)
  local g = gear()
  if not g then return nil end
  local out = {}
  for _, s in ipairs(GEAR) do if test(s, g.slot[s]) then out[s] = true end end
  return out
end
-- the item level of what you wear, averaged over the worn slots whose level reads (this client has no
-- GetAverageItemLevel); nil with nothing worn, or with the reason when no worn item's level reads
local function avgItemLevel()
  local g = gear()
  if not g then return nil end
  local sum, n = 0, 0
  for _, e in pairs(g.slot) do if e.level then sum, n = sum + e.level, n + 1 end end
  if n == 0 then
    if g.worn > 0 then C.lastErr = string.format("no item level reads for the %d items worn", g.worn) end
    return nil
  end
  return sum / n
end

-- buffs on you, by spell id and name, read once a second at most
local auraCache, auraAt = nil, -1
local function auras()
  local now = (GetTime and GetTime()) or 0
  if auraCache and now - auraAt < 1 then return auraCache end
  local ids, names = {}, {}
  local byIndex = api("C_UnitAuras", "GetAuraDataByIndex")
  for i = 1, 60 do
    local a = Get(byIndex, "player", i, "HELPFUL")
    if type(a) ~= "table" then break end
    local sid, nm = C.Plain(a.spellId), C.Plain(a.name)
    if type(sid) == "number" then ids[sid] = true end
    if type(nm) == "string" then names[nm] = true end
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

local function bagTotal(name)
  local fn = api("C_Container", name)
  if not fn then return nil end
  local total = 0
  for b = 0, 4 do total = total + (Num(fn, b) or 0) end
  return total
end

-- your skill lines as Forever's own skills window reads them (C_SkillInfo), once a second at most: the primary
-- professions in the window's order, and every line by its skill id
local PRIMARY = { [171] = true, [164] = true, [333] = true, [202] = true, [182] = true, [165] = true, [186] = true, [393] = true, [197] = true }
local FISHING, COOKING, FIRST_AID = 356, 185, 129
local skillCache, skillAt = nil, -1
local function skills()
  local now = (GetTime and GetTime()) or 0
  if skillCache and now - skillAt < 1 then return skillCache end
  local n, info = Num(api("C_SkillInfo", "GetNumSkillLines")), api("C_SkillInfo", "GetSkillLineInfo")
  if not (n and info) then return nil end
  local out = { primary = {} }
  for i = 1, n do
    local s = Get(info, i)
    if type(s) == "table" and C.Plain(s.isHeader) ~= true then
      local id, name, rank, max = C.Plain(s.skillID), C.Plain(s.name), C.Plain(s.rank), C.Plain(s.maxRank)
      if type(id) == "number" then
        local line = { name = type(name) == "string" and name or "", rank = type(rank) == "number" and rank or 0, max = type(max) == "number" and max or 0 }
        out[id] = line
        if PRIMARY[id] then out.primary[#out.primary + 1] = line end
      end
    end
  end
  skillCache, skillAt = out, now
  return out
end
local function primary(i) local sk = skills(); if not sk then return nil end local p = sk.primary[i]; return p and (p.name .. " " .. p.rank) or "" end
local function skillRank(id) local sk = skills(); if not sk then return nil end local l = sk[id]; return l and l.rank or 0 end

-- Forever's Legacy ids as Constants.LegacyConsts names them (Blizzard_APIDocumentationGenerated/LegacyConstantsDocumentation.lua);
-- the documented values stand in where the table is missing. The class categories are the ones LegacyChallengeDefaultCategories
-- opens the Legacy window to (Blizzard_LegacySystemConstants.lua)
local LC_DOC = { LEGACY_REWARD_TRACK_FACTION_ID = 2802, LEGACY_POINTS_TRAIT_CURRENCY_ID = 4225, LEGACY_TREE_PROFESSIONS_ID = 1187,
  LEGACY_TREE_ADVENTURE_ID = 1188, LEGACY_TREE_PROGRESSION_ID = 1189, LEGACY_DEFAULT_CATEGORY_WARRIOR = 15585, LEGACY_DEFAULT_CATEGORY_PALADIN = 15580,
  LEGACY_DEFAULT_CATEGORY_HUNTER = 15578, LEGACY_DEFAULT_CATEGORY_ROGUE = 15582, LEGACY_DEFAULT_CATEGORY_PRIEST = 15581, LEGACY_DEFAULT_CATEGORY_SHAMAN = 15583,
  LEGACY_DEFAULT_CATEGORY_MAGE = 15579, LEGACY_DEFAULT_CATEGORY_WARLOCK = 15584, LEGACY_DEFAULT_CATEGORY_DRUID = 15577 }
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local function lc(name)
  local t = type(Constants) == "table" and Constants.LegacyConsts
  local v = type(t) == "table" and C.Plain(t[name]) or nil
  return type(v) == "number" and v or LC_DOC[name]
end
local LEGACY_TREES = { "LEGACY_TREE_PROFESSIONS_ID", "LEGACY_TREE_ADVENTURE_ID", "LEGACY_TREE_PROGRESSION_ID" }

local function legacyRank(node)
  local cfgOf, info = api("C_Traits", "GetConfigIDByTreeID"), api("C_Traits", "GetNodeInfo")
  if not (cfgOf and info) then return nil end
  for _, treeName in ipairs(LEGACY_TREES) do
    local cfg = Num(cfgOf, lc(treeName))
    if cfg then
      local n = Get(info, cfg, node)
      if type(n) == "table" and type(C.Plain(n.activeRank)) == "number" and n.activeRank > 0 then return n.activeRank end
    end
  end
  return 0
end

-- a Legacy tree's currency, as the Legacy UI reads it (Blizzard_LegacySystemUtil.lua RefreshCachedCurrencyInfo: the
-- first TreeCurrencyInfo of the tree): points spent in this tree, spent in all, unspent, the seasonal cap
local function treeCurrency(treeName)
  local cfgOf, info = api("C_Traits", "GetConfigIDByTreeID"), api("C_Traits", "GetTreeCurrencyInfo")
  if not (cfgOf and info) then return nil end
  local tree = lc(treeName)
  local cfg = Num(cfgOf, tree)
  if not cfg then return nil end
  local list = Get(info, cfg, tree, false)
  local ci = type(list) == "table" and list[1] or nil
  if type(ci) ~= "table" then return nil end
  return C.Plain(ci.spentInTree), C.Plain(ci.spent), C.Plain(ci.quantity), C.Plain(ci.maxQuantity)
end
local function spentIn(treeName)
  return function()
    local inTree, spent = treeCurrency(treeName)
    if type(inTree) == "number" then return inTree end
    return type(spent) == "number" and spent or nil
  end
end
local TREE_ON = { "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED" }

-- the game rule that hides the Legacy window (Blizzard_AchievementUI/Camelot/Blizzard_AchievementUI.lua reads it by
-- this name; no doc gives its value, so it is looked up, and a client without the enum has no such rule)
local function legacyDisabled()
  local rule = type(Enum) == "table" and type(Enum.GameRule) == "table" and C.Plain(Enum.GameRule.AchievementsPanelDisabled) or nil
  if rule == nil then return false end
  local ns = C_GameRules
  local fn = type(ns) == "table" and ns.IsGameRuleActive or nil
  if type(fn) ~= "function" then return false end
  return Get(fn, rule) == true
end

-- the Legacy Challenges, walked the way the Legacy window lists them (Blizzard_LegacyChallenges.lua GenerateDataProvider:
-- GetCategoryList, GetCategoryInfo for the name and parent, GetCategoryNumAchievements and GetAchievementInfo by index)
-- and cached five seconds: six stats read it, and ACHIEVEMENT_EARNED clears it. A challenge counts as done when it is
-- completed by this character (the 13th return, wasEarnedByMe: the Legacy UI shows other characters' as incomplete);
-- its points are the Legacy points the UI shows for it (C_Traits.GetTraitCurrencyForAchievement, the override in
-- Blizzard_LegacyAchievementOverrides.lua), the achievement's own points where that reads nothing. Statistics
-- (the 15th return) are not challenges.
local legacyCache, legacyAt = nil, -1
local function legacy()
  local now = (GetTime and GetTime()) or 0
  if legacyCache and now - legacyAt < 5 then return legacyCache end
  if legacyDisabled() then C.lastErr = "Legacy Challenges are disabled on this realm"; return nil end
  local cats = Get("GetCategoryList")
  if type(cats) ~= "table" then return nil end
  local pointsOf, currency = api("C_Traits", "GetTraitCurrencyForAchievement"), lc("LEGACY_POINTS_TRAIT_CURRENCY_ID")
  local classOf = {}
  for _, class in ipairs(CLASSES) do classOf[lc("LEGACY_DEFAULT_CATEGORY_" .. class)] = class end
  local out = { done = 0, total = 0, pts = 0, cats = {}, byId = {} }
  for _, cat in ipairs(cats) do
    cat = C.Plain(cat)
    if type(cat) == "number" then
      local name, parent = Get("GetCategoryInfo", cat)
      local n = Num("GetCategoryNumAchievements", cat) or 0
      local e = { id = cat, name = type(name) == "string" and name or ("Category " .. cat), parent = type(parent) == "number" and parent or -1, done = 0, total = 0, class = classOf[cat] }
      for i = 1, n do
        local r = { Get("GetAchievementInfo", cat, i) }
        local id, points, completed, mine, isStat = r[1], r[3], r[4], r[13], r[15]
        if type(id) == "number" and isStat ~= true then
          e.total = e.total + 1
          if completed == true and mine ~= false then
            e.done = e.done + 1
            local p = pointsOf and Num(pointsOf, currency, id) or nil
            out.pts = out.pts + (p or (type(points) == "number" and points or 0))
          end
        end
      end
      out.total, out.done = out.total + e.total, out.done + e.done
      out.cats[#out.cats + 1] = e
      out.byId[cat] = e
    end
  end
  legacyCache, legacyAt = out, now
  return out
end
function S.LegacyClear() legacyCache = nil end
S.Legacy = legacy

-- the categories the pips stand for, in order: every top-level category that is not a class's, its children folded
-- in, then the one class category of the class given (yours when you read, the row's when you look); thirteen at most
function S.LegacyCategories(l, class)
  local out = {}
  if type(l) ~= "table" then return out end
  for _, e in ipairs(l.cats) do
    if e.parent == -1 and not e.class then
      local done, total = e.done, e.total
      for _, child in ipairs(l.cats) do if child.parent == e.id and not child.class then done, total = done + child.done, total + child.total end end
      if total > 0 then out[#out + 1] = { id = e.id, name = e.name, done = done, total = total } end
    end
  end
  local mine = class and l.byId[lc("LEGACY_DEFAULT_CATEGORY_" .. class)]
  -- thirteen pips fit a cell: the class category always has the last one
  while #out > (mine and mine.total > 0 and 12 or 13) do table.remove(out) end
  if mine and mine.total > 0 then out[#out + 1] = { id = mine.id, name = mine.name, done = mine.done, total = mine.total, class = class } end
  return out
end
-- a category's completion as one pip digit: 0 none, 3 to 6 climbing by quarters, 8 all (the pip colours climb from 3 to 8)
local function pipOf(done, total)
  if total <= 0 or done <= 0 then return 0 end
  if done >= total then return 8 end
  return 3 + math.floor(done * 4 / total)
end
S.PIP_WORDS = { [0] = "none", [3] = "under a quarter", [4] = "a quarter or more", [5] = "half or more", [6] = "three quarters or more", [8] = "all" }
local function myClass() local _, file = Get("UnitClass", "player"); return type(file) == "string" and file or nil end
-- a global that exists on this client, without the note a Get by name leaves when it does not
local function callable(name) return type(_G[name]) == "function" end

-- Forever's PvP rank is a Major Faction renown track (faction 2800), as its own PvP tab reads it
local PVP_RANK_FACTION = 2800
local function pvp()
  local info = Get(api("C_MajorFactions", "GetMajorFactionProgressionInfo"), PVP_RANK_FACTION)
  if type(info) ~= "table" then return nil end
  return C.Plain(info.renownLevel), C.Plain(info.renownReputationEarned)
end
local PVP_ON = { "UPDATE_FACTION", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "PLAYER_PVP_RANK_CHANGED" }

local function listOf(of, test)
  local out = {}
  for _, e in ipairs(of) do if test(e[1]) then out[e[1]] = true end end
  return out
end

local function hours(sec) if type(sec) ~= "number" then return "?" end local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60); return h > 0 and string.format("%dh %02dm", h, m) or string.format("%dm", m) end
S.FmtHours = hours
local function pct(v) return type(v) == "number" and string.format("%d%%", v) or "?" end
S.FmtPct = pct
-- copper as the game shows money: whole gold once there is some, silver or copper below that
local function goldOf(c)
  if type(c) ~= "number" then return "?" end
  if c >= 10000 then return string.format("%dg", math.floor(c / 10000)) end
  if c >= 100 then return string.format("%ds", math.floor(c / 100)) end
  return string.format("%dc", c)
end
S.FmtGold = goldOf
local function readyOf(v) return v == 2 and "ready" or (v == 1 and "gaps" or "no") end
S.FmtReady = readyOf
-- a count that is "-" at zero (hours to 60 before there is a pace)
local function orDash(v) return (type(v) == "number" and v > 0) and tostring(v) or "-" end
S.FmtOrDash = orDash

----------------------------------------------------------------------------
-- leveling
----------------------------------------------------------------------------
local D = S.def
D("level", "Level", "leveling", { read = function() return Num("UnitLevel", "player") end, on = "PLAYER_LEVEL_UP" })
D("xp", "XP into level", "leveling", { read = function() local x, m = Num("UnitXP", "player"), Num("UnitXPMax", "player"); if x and m and m > 0 then return math.floor(x * 100 / m) end end,
  on = { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP" }, fmt = pct, slow = true, hint = "percent of the level" })
D("xp_hour", "XP/hour", "leveling", { track = true, slow = true, hint = "XP gained in the last hour of play" })
D("xp_session", "XP/hour today", "leveling", { track = true, slow = true, hint = "XP an hour since you logged in" })
D("played", "Time played", "leveling", { track = true, slow = true, fmt = hours })
D("played_lvl", "Played this level", "leveling", { track = true, slow = true, fmt = hours })
D("to60", "Hours to 60", "leveling", { track = true, slow = true, fmt = orDash, hint = "at the last hour's pace, over the XP each level ahead takes" })
D("rested", "Rested XP", "leveling", { read = function() local r = Num("GetXPExhaustion"); return r or 0 end, on = "UPDATE_EXHAUSTION" })
D("zone", "Zone", "leveling", { read = function() local z = Get("GetZoneText"); return type(z) == "string" and z or nil end, kind = "text",
  on = { "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "PLAYER_ENTERING_WORLD" } })
D("subzone", "Subzone", "leveling", { read = function() local z = Get("GetSubZoneText"); return type(z) == "string" and z or nil end, kind = "text",
  on = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" } })
D("group", "Grouped with", "leveling", { kind = "text", on = "GROUP_ROSTER_UPDATE", read = function()
  local names = {}
  for i = 1, 4 do local n = Get("UnitName", "party" .. i); if type(n) == "string" then names[#names + 1] = n end end
  return #names > 0 and table.concat(names, ", ") or ""
end })
D("logins", "Logins this week", "leveling", { track = true, hint = "logins, not reloads; the week starts on Monday" })
D("session", "Session", "leveling", { track = true, slow = true, fmt = hours, hint = "this login so far" })
D("longest", "Longest session", "leveling", { track = true, slow = true, fmt = hours })
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
D("kills", "XP gains", "leveling", { count = "CHAT_MSG_COMBAT_XP_GAIN", slow = true, hint = "XP messages, counted: kills, quests and discoveries alike (the text is secret on this client)" })
D("zones_seen", "Zones visited", "leveling", { track = true })
D("flights_known", "Flight paths", "leveling", { track = true, hint = "known, as the taxi map last showed" })
D("flights", "Flights taken", "leveling", { track = true })
D("longest_flight", "Longest flight", "leveling", { track = true, fmt = hours })
D("hearth", "Hearth set to", "leveling", { read = function() local b = Get("GetBindLocation"); return type(b) == "string" and b or nil end, kind = "text", on = "HEARTHSTONE_BOUND" })
D("hearths", "Hearthstones used", "leveling", { track = true })
D("deaths_lvl", "Deaths while leveling", "leveling", { track = true })
D("ghost_time", "Time as a ghost", "leveling", { track = true, slow = true, fmt = hours })
D("gold_earned", "Gold earned", "leveling", { track = true, slow = true, fmt = goldOf, hint = "every rise of your purse, summed" })
D("gold_quests", "Gold from quests", "leveling", { track = true, fmt = goldOf })
D("vendor_sales", "Sold to vendors", "leveling", { track = true, fmt = goldOf, hint = "while a merchant was open" })
D("mount", "Mount", "leveling", { kind = "flag", read = function()
  local ids = Get(api("C_MountJournal", "GetMountIDs"))
  if type(ids) ~= "table" then return nil end
  local info = api("C_MountJournal", "GetMountInfoByID")
  for _, id in ipairs(ids) do
    -- isCollected is the eleventh return
    local r = { Get(info, id) }
    if r[11] == true then return true end
  end
  return false
end })
D("talents_free", "Unspent talents", "leveling", { read = function() return Num("GetNumUnspentTalents") end, on = { "PLAYER_TALENT_UPDATE", "PLAYER_LEVEL_UP" } })
D("spec", "Spec", "leveling", { kind = "text", on = "PLAYER_TALENT_UPDATE", read = function()
  local i = Num(api("C_SpecializationInfo", "GetSpecialization"))
  if not i then return nil end
  local _, name = Get(api("C_SpecializationInfo", "GetSpecializationInfo"), i)
  return type(name) == "string" and name or nil
end })
D("prof1", "Profession 1", "leveling", { kind = "text", on = "SKILL_LINES_CHANGED", read = function() return primary(1) end })
D("prof2", "Profession 2", "leveling", { kind = "text", on = "SKILL_LINES_CHANGED", read = function() return primary(2) end })
D("fishing", "Fishing", "leveling", { on = "SKILL_LINES_CHANGED", read = function() return skillRank(FISHING) end })
D("cooking", "Cooking", "leveling", { on = "SKILL_LINES_CHANGED", read = function() return skillRank(COOKING) end })
D("first_aid", "First Aid", "leveling", { on = "SKILL_LINES_CHANGED", read = function() return skillRank(FIRST_AID) end })
local LEGACY = { { 110300, "Frequent Flier" }, { 110304, "Field Guide" }, { 110313, "Gourmand" }, { 110316, "Permanence" }, { 110301, "Well Rested" } }
D("legacy", "Legacy perks", "leveling", { kind = "list", of = LEGACY, on = "TRAIT_CONFIG_UPDATED", read = function()
  return listOf(LEGACY, function(node) local r = legacyRank(node); return r ~= nil and r > 0 end)
end })
D("levelups", "Level-ups today", "leveling", { count = "PLAYER_LEVEL_UP" })
D("still", "Longest stood still", "leveling", { track = true, slow = true, fmt = hours, default = "all" })

----------------------------------------------------------------------------
-- progression
----------------------------------------------------------------------------
-- readiness: the gaps a record shows, by name; nil until the gear and bags have been read
local READY_INPUTS = { "empty_slots", "unenchanted", "durability", "flasks", "flask_on", "pot_health" }
function S.ReadyGaps(v)
  if type(v) ~= "table" or (v.durability == nil and v.pot_health == nil and type(v.empty_slots) ~= "table") then return nil end
  local function count(id)
    local t = v[id]
    if type(t) ~= "table" then return 0 end
    local k = 0
    for _, e in ipairs(S.byId[id].of) do if t[e[1]] then k = k + 1 end end
    return k
  end
  local gaps = {}
  if count("empty_slots") > 0 then gaps[#gaps + 1] = "an empty slot" end
  if count("unenchanted") > 3 then gaps[#gaps + 1] = "4 or more slots unenchanted" end
  if type(v.durability) == "number" and v.durability < 50 then gaps[#gaps + 1] = "durability under 50%" end
  if v.flasks == 0 and v.flask_on == false then gaps[#gaps + 1] = "no flask on or in the bags" end
  if type(v.pot_health) == "number" and v.pot_health < 5 then gaps[#gaps + 1] = "under 5 health potions" end
  return gaps
end
D("ready", "Ready", "prog", { fmt = readyOf, on = { "PLAYER_EQUIPMENT_CHANGED", "UPDATE_INVENTORY_DURABILITY", "BAG_UPDATE_DELAYED", "UNIT_AURA" },
  hint = "ready with no gap, gaps with one or two, no with more: an empty slot, 4+ unenchanted, durability under 50%, no flask, under 5 health potions",
  read = function()
    -- from the inputs' live reads, so it never depends on which stat happened to be read first
    local v = {}
    for _, id in ipairs(READY_INPUTS) do local ok, x = pcall(S.byId[id].read); if ok then v[id] = C.Plain(x) end end
    local gaps = S.ReadyGaps(v)
    if not gaps then return nil end
    return #gaps == 0 and 2 or (#gaps <= 2 and 1 or 0)
  end })
local GEAR_ON = { "PLAYER_EQUIPMENT_CHANGED", "GET_ITEM_INFO_RECEIVED" }
D("ilvl", "Item level", "prog", { read = function() local avg = avgItemLevel(); return avg and math.floor(avg) or nil end, on = GEAR_ON,
  hint = "the average over the items you wear" })
D("ilvl_slots", "Item level per slot", "prog", { kind = "list", of = SLOT_OF, on = GEAR_ON, hint = "slots at or above your average", read = function()
  local avg = avgItemLevel()
  if not avg then return nil end
  return slotSet(function(_, e) return e ~= nil and e.level ~= nil and e.level >= avg end)
end })
D("empty_slots", "Empty slots", "prog", { kind = "list", of = SLOT_OF, default = "self", on = "PLAYER_EQUIPMENT_CHANGED",
  read = function() return slotSet(function(s, e) return e == nil and s ~= 17 and s ~= 18 end) end })
-- the enchant is in the link alone: where a worn slot that takes one gives no readable link, the count would be wrong,
-- so the stat reads nil and its tooltip says why
D("unenchanted", "Unenchanted", "prog", { kind = "list", of = SLOT_OF, default = "self", on = GEAR_ON, read = function()
  local g = gear()
  if not g then return nil end
  local blind = 0
  for s in pairs(ENCHANTABLE) do local e = g.slot[s]; if e and not e.link then blind = blind + 1 end end
  if blind > 0 then
    C.lastErr = string.format("the client gives no readable item link for %d worn slot%s that take%s an enchant, so enchants cannot be read", blind, blind == 1 and "" or "s", blind == 1 and "s" or "")
    return nil
  end
  return slotSet(function(s, e) return ENCHANTABLE[s] and e ~= nil and linkEnchant(e.link) == 0 end)
end })
D("old_gear", "Gear 10+ levels old", "prog", { kind = "list", of = SLOT_OF, default = "self", on = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "GET_ITEM_INFO_RECEIVED" }, read = function()
  local lvl = Num("UnitLevel", "player") or 1
  return slotSet(function(_, e) return e ~= nil and e.level ~= nil and e.level < lvl - 10 end)
end })
D("greens", "Green items worn", "prog", { default = "self", on = GEAR_ON, read = function()
  local g = gear()
  if not g then return nil end
  if g.worn > 0 and g.noQuality == g.worn then C.lastErr = "no item quality reads for the items worn"; return nil end
  local n = 0
  for _, e in pairs(g.slot) do if e.quality ~= nil and e.quality <= 2 then n = n + 1 end end
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
-- the effective resistance (third return), the one the character sheet shows
local function resist(n) return function() local _, _, v = Get("UnitResistance", "player", n); return type(v) == "number" and v or nil end end
D("resist_fire", "Fire resist", "prog", { read = resist(2), on = "PLAYER_EQUIPMENT_CHANGED" })
D("resist_nature", "Nature resist", "prog", { read = resist(3), on = "PLAYER_EQUIPMENT_CHANGED" })
D("resist_frost", "Frost resist", "prog", { read = resist(4), on = "PLAYER_EQUIPMENT_CHANGED" })
D("resist_shadow", "Shadow resist", "prog", { read = resist(5), on = "PLAYER_EQUIPMENT_CHANGED" })
D("resist_arcane", "Arcane resist", "prog", { read = resist(6), on = "PLAYER_EQUIPMENT_CHANGED" })
local RAID_RECIPES = { { 17635, "Flask of the Titans" }, { 17636, "Flask of Distilled Wisdom" }, { 17637, "Flask of Supreme Power" },
  { 17638, "Flask of Chromatic Resistance" }, { 17556, "Major Healing Potion" }, { 17580, "Major Mana Potion" },
  { 17574, "Greater Fire Protection" }, { 17576, "Greater Nature Protection" }, { 17578, "Greater Shadow Protection" },
  { 17575, "Greater Frost Protection" }, { 18560, "Mooncloth" }, { 16729, "Lionheart Helm" }, { 16994, "Arcanite Reaper" } }
D("raid_recipes", "Raid recipes", "prog", { kind = "list", of = RAID_RECIPES, track = true, hint = "learned, as your trade skill windows showed them" })
D("bags_free", "Free bag slots", "prog", { read = function() return bagTotal("GetContainerNumFreeSlots") end, on = "BAG_UPDATE_DELAYED" })
D("bags_size", "Bag slots", "prog", { read = function() return bagTotal("GetContainerNumSlots") end, on = "BAG_UPDATE_DELAYED" })
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
    local cur, max = Get("GetInventoryItemDurability", s)
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
  if not byId then return nil end
  local s = {}
  for i, f in ipairs(FACTIONS) do
    local d = Get(byId, f[1])
    local standing = type(d) == "table" and C.Plain(d.reaction) or nil
    s[i] = type(standing) == "number" and math.min(8, math.max(0, standing)) or 0
  end
  return table.concat(s)
end })
S.FACTIONS = FACTIONS
D("pvp_rank", "PvP rank", "prog", { read = function() local rank = pvp(); return type(rank) == "number" and rank or nil end, on = PVP_ON, hint = "0 is unranked, as the PvP tab shows" })
D("pvp_pts", "Rank points", "prog", { read = function() local _, pts = pvp(); return type(pts) == "number" and pts or nil end, on = PVP_ON, hint = "toward the next PvP rank, as the PvP tab shows" })
D("raids", "Raids attended", "prog", { count = "RAID_ENTERED", hint = "raid instances entered, counted" })
-- Legacy Challenges: Forever's achievements. The counts, the points and the categories share one walk (legacy, above),
-- cleared and re-read on ACHIEVEMENT_EARNED and on the heartbeat; CRITERIA_UPDATE changes no count, so it does not
-- re-read them (it drives the statistics pass in Sample.lua instead)
D("lc_done", "Challenges done", "prog", { on = "ACHIEVEMENT_EARNED", hint = "Legacy Challenges this character has earned",
  read = function() local l = legacy(); return l and l.done or nil end })
D("lc_total", "Challenges listed", "prog", { on = "ACHIEVEMENT_EARNED", hint = "Legacy Challenges the client lists, done or not",
  read = function() local l = legacy(); return l and l.total or nil end })
D("lc_pts", "Legacy points", "prog", { on = "ACHIEVEMENT_EARNED", hint = "the Legacy points the challenges you have done gave, counted the same way on every client",
  read = function() local l = legacy(); return l and l.pts or nil end })
D("lc_free", "Legacy unspent", "prog", { on = TREE_ON, hint = "Legacy points not yet spent in a tree",
  read = function() local _, _, free = treeCurrency("LEGACY_TREE_PROFESSIONS_ID"); return type(free) == "number" and free or nil end })
D("lc_renown", "Legacy renown", "prog", { on = "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", hint = "the Legacy reward track's level",
  read = function() return Num(api("C_MajorFactions", "GetCurrentRenownLevel"), lc("LEGACY_REWARD_TRACK_FACTION_ID")) end })
D("lc_prof", "Professions tree", "prog", { on = TREE_ON, read = spentIn("LEGACY_TREE_PROFESSIONS_ID"), hint = "Legacy points spent in it" })
D("lc_adv", "Adventure tree", "prog", { on = TREE_ON, read = spentIn("LEGACY_TREE_ADVENTURE_ID"), hint = "Legacy points spent in it" })
D("lc_prog", "Progression tree", "prog", { on = TREE_ON, read = spentIn("LEGACY_TREE_PROGRESSION_ID"), hint = "Legacy points spent in it" })
D("lc_last", "Latest challenge", "prog", { kind = "text", track = true, hint = "the last Legacy Challenge earned while the addon ran, or the client's latest at login" })
D("lc_cats", "Challenge categories", "prog", { kind = "pips", pips = 13, on = "ACHIEVEMENT_EARNED", hint = "a pip per Legacy category, your class's last: dark none, brighter by quarters, white all",
  read = function()
    local l = legacy()
    if not l then return nil end
    local s = {}
    for i, e in ipairs(S.LegacyCategories(l, myClass())) do s[i] = pipOf(e.done, e.total) end
    return table.concat(s)
  end })
D("stones", "Healthstones", "prog", { read = counts({ 9421, 5510, 5509, 5511, 5512, 19013, 19012, 19011 }), on = "BAG_UPDATE_DELAYED" })
D("shards", "Soul shards", "prog", { read = counts({ 6265 }), on = "BAG_UPDATE_DELAYED" })
D("totems", "Totems", "prog", { read = function() local n = 0; for _, id in ipairs({ 5175, 5176, 5177, 5178 }) do if itemCount(id) > 0 then n = n + 1 end end; return n end, on = "BAG_UPDATE_DELAYED", hint = "of the four" })
D("ammo", "Ammo", "prog", { read = function() return Num("GetInventoryItemCount", "player", 0) end, on = "BAG_UPDATE_DELAYED", hint = "in the ammo slot" })
D("poisons", "Poisons", "prog", { read = counts({ 8985, 20844, 3776, 10922, 8928 }), on = "BAG_UPDATE_DELAYED" })
D("gold", "Gold", "officer", { read = money, fmt = goldOf, on = "PLAYER_MONEY" })
D("bank_in", "Guild bank deposits", "officer", { track = true, fmt = goldOf, hint = "while the guild bank was open" })
D("bank_out", "Guild bank withdrawals", "officer", { track = true, fmt = goldOf, hint = "while the guild bank was open" })
D("consumed", "Consumables used in raids", "officer", { track = true, hint = "potions, flasks and food that left your bags in a raid" })
D("addon_ver", "Addon version", "officer", { kind = "text", read = function() return C.version end, default = "all" })

----------------------------------------------------------------------------
-- the hall of shame
----------------------------------------------------------------------------
D("deaths", "Deaths", "funny", { count = "PLAYER_DEAD" })
D("deaths_today", "Deaths today", "funny", { count = "PLAYER_DEAD" })
D("falls", "Fall deaths", "funny", { track = true, hint = "died within three seconds of falling" })
D("drownings", "Drownings", "funny", { track = true, hint = "died with the breath bar empty" })
D("fatigue", "Fatigue deaths", "funny", { track = true, hint = "died with the fatigue bar empty" })
D("hearth_waste", "Hearthstones wasted", "funny", { track = true, hint = "a hearth within two minutes of a flight" })
D("afk", "AFK flags", "funny", { track = true })
D("dance", "/dance", "funny", { track = true, slow = true })
D("sit", "/sit", "funny", { track = true, slow = true })
D("emotes", "Emotes", "funny", { track = true, slow = true })
D("whispers", "Whispers an hour", "funny", { track = true, slow = true, default = "self", hint = "received, counted, never read" })
D("gchat", "Guild chat lines", "funny", { track = true, slow = true, hint = "your own lines, counted as you send them" })
D("inspected", "Inspected others", "funny", { count = "INSPECT_READY" })
D("fish", "Fish caught", "funny", { track = true, slow = true, hint = "loot windows after a Fishing cast" })
D("jumps", "Jumps", "funny", { track = true, slow = true })
D("ghost_yards", "Ghost run yards", "funny", { track = true, slow = true })
D("where", "\"where are you\" typed", "funny", { track = true, hint = "in party or raid chat; wya counts" })
D("grey_gold", "Gold from greys", "funny", { track = true, fmt = goldOf, hint = "grey items sold to vendors, at their vendor price" })

----------------------------------------------------------------------------
-- officers'
----------------------------------------------------------------------------
D("main", "Declared main", "officer", { kind = "text", read = function() return C.Settings().main or "" end, default = "all" })
D("role", "Role", "officer", { kind = "text", read = function() return C.Char().role or "" end, default = "all" })
D("last_login", "Last login", "officer", { track = true, hint = "epoch seconds", default = "all" })
D("raid_spec", "Raid spec set", "officer", { kind = "flag", read = function() return C.Char().raidspec == true end, hint = "ticked by you in Settings, per character" })
D("weekly_raids", "Raids this week", "officer", { track = true, hint = "raid instances entered since Monday" })

----------------------------------------------------------------------------
-- hidden: your character's GUID, never shown. It goes first in every full record so a receiver can join the record to
-- the guild roster's member with the same GUID (names are no key on Forever: two words, a Kstring at times; Core.lua)
-- and drop a record whose GUID is its own (the game hands a guild addon message back to its sender too). Kept out of
-- S.list and the categories, so no page, column, checklist, policy pair or the web page lists it; Sample sets it at
-- login, Comm sends it with the full record, a receiver decodes it like any text stat (up to 40 characters)
----------------------------------------------------------------------------
S.HIDDEN = { guid = { id = "guid", label = "Character GUID", cat = "hidden", kind = "text", max = 40, default = "all", hidden = true } }
S.byId.guid = S.HIDDEN.guid

----------------------------------------------------------------------------
-- the game's statistics: a dynamic category, defined at login from what the client reports
----------------------------------------------------------------------------
-- The Statistics panel never loads on camelot, but the C functions behind it are in the binary (the mainline panel
-- reads GetStatisticsCategoryList, GetCategoryInfo for the name and parent, GetCategoryNumAchievements, and
-- GetStatistic(category, index) -> quantity, skip, achievementID; GetStatistic(achievementID) -> the quantity as a
-- string, Blizzard_AchievementUI/Mainline/Blizzard_AchievementUI.lua:2385-2456). Whether camelot exposes them and the
-- server fills them is unknown, so ProbeGame asks at login and defines one int stat per statistic only where the list
-- is there and not empty. S.game keeps the categories as the game groups them (parents, then their children) for the
-- Statistics page and the policy; S.gameNote says why nothing was defined. Stats are "g" .. achievementID, labelled by
-- GetAchievementInfo, hinted with the category path, slow (they travel on the two-minute flush and their own
-- full-record pass, never as they tick), read on the heartbeat and by Sample's coalesced pass.
S.game = { cats = {}, byCat = {}, byId = {}, defined = false }
S.gameNote = nil
S.GAME_CAP = 1000 -- statistics defined at most, so a client cannot fill the registry or the channel past reason

-- the quantity string as a number: separators of any locale dropped ("1,234", "1 234", "1.234"); "--" is the game's
-- "never recorded", which reads as 0 here (a count that never happened is nought, and a nil would send nothing, so
-- the guild would see "?" where the game shows a dash)
function S.Quantity(s)
  if type(s) == "number" then return math.floor(s) end
  if type(s) ~= "string" then return nil end
  if s:match("^%s*%-+%s*$") then return 0 end
  local digits = s:gsub("[^%d]", "")
  if digits == "" then return nil end
  return tonumber(digits)
end

-- the probe: true and the count when statistics were defined; false, the reason and whether asking again could help
-- otherwise (an empty list may still be loading at login; a missing function will not appear). Defines once.
function S.ProbeGame()
  if S.game.defined then return true, #S.byCat.game end
  if not callable("GetStatisticsCategoryList") then
    S.gameNote = "GetStatisticsCategoryList is missing on this client"
    return false, S.gameNote, false
  end
  local list = Get("GetStatisticsCategoryList")
  if type(list) ~= "table" or #list == 0 then
    S.gameNote = "This client reports no statistics"
    return false, S.gameNote, true
  end
  -- the categories: name and parent for each, then parents in the game's order with their children after them
  local cats, byId = {}, {}
  for _, id in ipairs(list) do
    id = C.Plain(id)
    if type(id) == "number" and not byId[id] then
      local name, parent = Get("GetCategoryInfo", id)
      local e = { id = id, name = type(name) == "string" and name or ("Category " .. id), parent = type(parent) == "number" and parent or -1, stats = {} }
      cats[#cats + 1] = e
      byId[id] = e
    end
  end
  local ordered = {}
  for _, e in ipairs(cats) do
    if e.parent == -1 or not byId[e.parent] then
      e.parent = -1
      e.path = e.name
      ordered[#ordered + 1] = e
      for _, child in ipairs(cats) do
        if child.parent == e.id then child.path = e.name .. " > " .. child.name; ordered[#ordered + 1] = child end
      end
    end
  end
  for _, e in ipairs(cats) do if not e.path then e.path = e.name; e.parent = -1; ordered[#ordered + 1] = e end end
  -- the statistics: one int stat each, the ones the game marks skip left out
  local n = 0
  for _, e in ipairs(ordered) do
    local count = Num("GetCategoryNumAchievements", e.id) or 0
    for i = 1, count do
      local _, skip, id = Get("GetStatistic", e.id, i)
      if type(id) == "number" and skip ~= true and n < S.GAME_CAP then
        local sid = "g" .. math.floor(id)
        if not S.byId[sid] then
          local _, label = Get("GetAchievementInfo", id)
          local statId = id
          local def = S.def(sid, type(label) == "string" and label or ("Statistic " .. sid:sub(2)), "game",
            { read = function() return S.Quantity(Get("GetStatistic", statId)) end, slow = true, hint = e.path, game = e.id, default = "all" })
          e.stats[#e.stats + 1] = def
          n = n + 1
        end
      end
    end
  end
  S.game = { cats = ordered, byCat = {}, byId = byId, defined = true }
  for _, e in ipairs(ordered) do S.game.byCat[e.id] = e.stats end
  if n > 0 then S.gameNote = nil; return true, n end
  S.gameNote = "This client lists statistics categories but no statistic in them"
  return false, S.gameNote, false
end

-- one line for /cute api
function S.GameReport()
  if #S.byCat.game > 0 then return string.format("statistics: %d defined in %d categories", #S.byCat.game, #S.game.cats) end
  return "statistics: none (" .. (S.gameNote or "not probed yet") .. ")"
end

-- what a category contains, in order
function S.Cat(cat) return S.byCat[cat] end
function S.Get(id) return S.byId[id] end
