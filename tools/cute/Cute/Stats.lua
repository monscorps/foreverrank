-- SPDX-License-Identifier: GPL-3.0-or-later
-- The stat registry: one S.def per stat. Everything else (sampling, the wire format, the dashboard's columns, the
-- Settings checklists) is generated from this table, so a new stat is one line here.
--   id        short ASCII, stable for life; the wire key
--   label     the column header or card title
--   cat       leveling | prog | funny | officer | game | found: the default tab and the default visibility (game is
--             filled at login from the client's own statistics, found by what the guild discovers in play; see the
--             end of the file)
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
--   gear, bag true: re-read with the gear (or the bags) 2 s and 10 s after every loading screen (Sample.lua)
--   game      for a statistics stat: the game's category id, which the visibility policy is set by ("gc" .. id)
--   learned   for a discovered stat: bosses | dungeons | raids | rep, its category on the Statistics page and in the
--             policy ("gc_" .. learned)
-- Learned, not listed: Forever is an exploring game whose content is revealed over time, so no content is fixed here.
-- Only the game's structure is (the equipment slots, the classes, the damage schools, the item class enums), and the
-- few ids no documented call can tell apart, each named where it is used (README, "Adding a stat"). What the guild
-- meets in play (what it enchants, by slot and kind of item, the bosses it kills, the instances it enters, the
-- factions its characters know, the raid buffs guild mates cast) is data, found by each client, shared on the guild
-- channel and kept in CuteDB.known, so the dashboard grows without a new version. (0.3.x listed Classic's: Molten
-- Core and Onyxia attunements, Classic keys, world buffs, raid factions and potions by item id. Forever has no Classic
-- raid, has neck enchants Classic never had, and no head or shoulder enchant yet; those lists are gone.) What research
-- and the beta showed ships beside it as a seed (Known.lua), which Rules.lua weighs against the guild's play: an
-- enchant slot the seed names counts here once Rule 0 has found the seed fresh (EnchantKnown, below).
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
local S = { list = {}, byId = {}, byCat = { leveling = {}, prog = {}, funny = {}, officer = {}, game = {}, found = {} } }
C.Stats = S

-- game is the dynamic fifth category: the game's own statistics, defined at login from what the client reports. found
-- is the sixth, kept out of S.CATS (no column, checklist or the web page lists it): what the guild discovers in play
S.CATS = { "leveling", "prog", "funny", "officer", "game" }
S.CAT_LABEL = { leveling = "Race", prog = "Prog", funny = "Hall of Shame", officer = "Officers", game = "Statistics", found = "Discovered" }
S.CAT_DEFAULT = { leveling = "all", prog = "all", funny = "all", officer = "self", game = "all", found = "all" }
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

-- what the guild has found out in play (CuteDB.known; Core.lua's defaults make the tables). Nil before the saved
-- variables load
function S.Known()
  local k = CuteDB and CuteDB.known
  return type(k) == "table" and k or nil
end

----------------------------------------------------------------------------
-- readers. Each returns a plain value or nil. The client's namespaced APIs are looked up at call time.
----------------------------------------------------------------------------
local Get, Num, api = C.Get, C.Num, C.Api
local function money() return Num("GetMoney") end
local function gtime() return (GetTime and GetTime()) or 0 end
-- an enum value by name, as the client has it; the documented value where the table is missing
local function enum(name, field, documented)
  local e = type(Enum) == "table" and Enum[name] or nil
  local v = type(e) == "table" and C.Plain(e[field]) or nil
  return type(v) == "number" and v or documented
end

local function itemCount(id) return Num(api("C_Item", "GetItemCount"), id) or 0 end
-- the seventeen gear slots the game shows (no shirt, tabard, ammo): the game's structure, fixed
local GEAR = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
local SLOT = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrist",
  [10] = "Hands", [11] = "Ring 1", [12] = "Ring 2", [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back", [16] = "Main hand",
  [17] = "Off hand", [18] = "Ranged" }
local SLOT_OF = {}
for _, s in ipairs(GEAR) do SLOT_OF[#SLOT_OF + 1] = { s, SLOT[s] } end
S.SLOT, S.GEAR = SLOT, GEAR

-- the gear you wear, slot by slot, read the way Forever's own character sheet reads it (Camelot/PaperDollFrame.lua,
-- PaperDollItemSlotButton_Update): GetInventoryItemID says what is in a slot, GetInventoryItemQuality its quality.
-- The item level comes from the id, C_Item.GetDetailedItemLevelInfo (documented; its ItemInfo argument takes an id, a
-- name or a link), else C_Item.GetItemInfo's fourth return (an item the client has not cached yet reads nothing from
-- the first). The link is read for the enchant alone, and only when it is a plain string; a stat that needs it says
-- so where the client gives none instead of counting wrong. One scan serves every gear stat read in the same frame;
-- GearClear starts a fresh one. (The sheet refreshes a slot on UNIT_INVENTORY_CHANGED as well as
-- PLAYER_EQUIPMENT_CHANGED, Camelot/PaperDollFrame.lua:2055-2063, and so do these stats: the inventory can arrive after
-- the loading screen, and an enchant changes the link with no equipment change at all. 0.3.x listened to the second
-- alone, so a login's empty slots and an enchant stood until the five-minute heartbeat or a /reload.)
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
-- the permanent enchant a link carries: its second field (item:id:enchant:...), 0 for none
local function linkEnchant(link) return tonumber(link:match("item:%d+:(%d*)")) or 0 end
-- an item's kind as the game classes it, "class.subclass" by the game's own item class enums: C_Item.GetItemInfoInstant's
-- sixth and seventh returns (a bow is 2.2, a gun 2.3, a wand 2.19, a dagger 2.15, a shield 4.6, an off-hand item held
-- in the hand 4.0), else C_Item.GetItemInfo's twelfth and thirteenth once the item is cached (an item the server sends
-- that the client's own data lacks); nil while neither reads. The enchants are learned per slot and kind (below)
local function itemKind(id, instant, info)
  local class, sub
  if instant then local _, _, _, _, _, c, s = Get(instant, id); class, sub = c, s end
  if type(class) ~= "number" and info then local r = { Get(info, id) }; class, sub = r[12], r[13] end
  if type(class) == "number" and type(sub) == "number" then return math.floor(class) .. "." .. math.floor(sub) end
end
S.ItemKind = itemKind
-- the item ids the last gear and bag scans met: GET_ITEM_INFO_RECEIVED re-reads the gear and bag stats only for one of
-- them (Sample.lua), not for every item a chat link, another addon or the Legacy window asks the client about
local gearIds, bagIds = {}, {}
function S.ItemWanted(id) return type(id) == "number" and (gearIds[id] == true or bagIds[id] == true) end
local function gear()
  local now = gtime()
  if gearCache and gearAt == now then return gearCache end
  local out = { slot = {}, worn = 0, unreadable = 0, noLevel = 0, noQuality = 0 }
  local detailed, info, qualityById = api("C_Item", "GetDetailedItemLevelInfo"), api("C_Item", "GetItemInfo"), api("C_Item", "GetItemQualityByID")
  local instant = api("C_Item", "GetItemInfoInstant")
  local ids = {}
  for _, s in ipairs(GEAR) do
    local id, there, err = slotCall("GetInventoryItemID", s)
    if err then C.lastErr = err; return nil end
    if there then
      local e = { id = type(id) == "number" and id or nil }
      out.worn = out.worn + 1
      if e.id then
        ids[e.id] = true
        e.level = detailed and Num(detailed, e.id) or nil
        if not e.level and info then local r = { Get(info, e.id) }; e.level = type(r[4]) == "number" and r[4] or nil end
        e.kind = itemKind(e.id, instant, info)
      end
      if not e.level then out.noLevel = out.noLevel + 1 end
      local q = slotCall("GetInventoryItemQuality", s)
      if type(q) ~= "number" and e.id and qualityById then q = Num(qualityById, e.id) end
      e.quality = type(q) == "number" and q or nil
      if not e.quality then out.noQuality = out.noQuality + 1 end
      local link = slotCall("GetInventoryItemLink", s)
      e.link = (type(link) == "string" and link ~= "" and not C.IsKstring(link)) and link or nil
      if e.link then e.enchant = linkEnchant(e.link) else out.unreadable = out.unreadable + 1 end
      out.slot[s] = e
    end
  end
  gearCache, gearAt, gearIds = out, now, ids
  return out
end
S.Gear = gear
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

-- what the guild enchants, learned per slot and kind of item: CuteDB.known.enchant[slot] = { n = members seen with an
-- enchant there, at = when first, who = their GUIDs, kinds = { ["2.2"] = { n, at, who }, ... } } (kind: itemKind's
-- "class.subclass"). A slot alone says too little: a scope on one hunter's bow would ask every wand for one, a shield
-- enchant every caster's off-hand book, and nothing can enchant those. So an item is asked for an enchant where the
-- guild has seen the same kind of item enchanted in the same slot, or, for a character at the rules' enchant level
-- (Rules.lua rule 5), where the seed has an enchant for that slot and kind and the rules let it count. Built from your
-- own read, from every member record that arrives with its GUID (Roster:Apply) and from the records saved
-- (LoadKnown), counting a member once by GUID; kept apart from the records (the seed is a prior beside it, never
-- copied in), so it outlives a member leaving and the roster's pruning. A slot or kind neither the guild nor the seed
-- has an enchant for is never asked for: a head or shoulder enchant, which Forever has none of yet, only once someone
-- wears one. (0.4.0's first build learned slots alone; such a record, with no kinds, teaches nothing.) n only grows:
-- it says how many members the guild has seen with one, not how many have one now. kinds: { [slot] = kind }. True when
-- a slot or kind is new to the guild's knowledge
local WHO_CAP = 1000
local function seenOn(rec, who)
  if type(rec.who) ~= "table" then rec.who = {} end
  if type(who) == "string" and who ~= "" and not rec.who[who] and (rec.n or 0) < WHO_CAP then rec.who[who] = true; rec.n = (rec.n or 0) + 1 end
end
-- enchs: { [slot] = the enchant's id as the link carries it }, where the record says (0.5.0 sends it; the Guide marks
-- the seed's enchants the guild has on an item as seen). rec.ench = { [id] = { n, at, who } }
function S.LearnEnchants(kinds, who, enchs)
  local k = S.Known()
  if not k or type(kinds) ~= "table" then return false end
  k.enchant = type(k.enchant) == "table" and k.enchant or {}
  local new = false
  for _, e in ipairs(SLOT_OF) do
    local slot, kind = e[1], kinds[e[1]]
    if type(kind) == "string" and kind:match("^%d+%.%d+$") then
      local rec = k.enchant[slot]
      if type(rec) ~= "table" then rec = { n = 0, at = C.Now(), who = {} }; k.enchant[slot] = rec end
      rec.kinds = type(rec.kinds) == "table" and rec.kinds or {}
      local kr = rec.kinds[kind]
      if type(kr) ~= "table" then kr = { n = 0, at = C.Now(), who = {} }; rec.kinds[kind] = kr; new = true end
      seenOn(rec, who)
      seenOn(kr, who)
      local id = type(enchs) == "table" and tonumber(enchs[slot]) or nil
      if id and id > 0 then
        rec.ench = type(rec.ench) == "table" and rec.ench or {}
        local er = rec.ench[id]
        if type(er) ~= "table" then er = { n = 0, at = C.Now(), who = {} }; rec.ench[id] = er end
        seenOn(er, who)
      end
    end
  end
  if new and C.Rules then C.Rules:Dirty() end
  if new then
    -- your own Missing enchants (and the verdict) are asked again, and the window learns of it
    if C.Sample and C.Sample.started then C.Sample:Schedule("unenchanted"); C.Sample:Schedule("ready") end
    if C.UI and C.UI.Refresh then C.UI:Refresh() end
  end
  return new
end
-- has the guild seen an enchant in this slot: on this kind of item, or (kind nil) on any
function S.EnchantLearned(slot, kind)
  local k = S.Known()
  local rec = k and type(k.enchant) == "table" and k.enchant[slot]
  local kinds = type(rec) == "table" and rec.kinds
  if type(kinds) ~= "table" then return false end
  if kind ~= nil then return type(kinds[kind]) == "table" end
  return next(kinds) ~= nil
end
-- does the slot take an enchant, on this kind of item or (kind nil) on any: the guild has seen one there, or the seed
-- says so and the rules let it count (Rules.lua rule 5: a fresh seed, the slot neither doubted nor absent, and, where
-- a level is given, a character at the rules' enchant level)
function S.EnchantKnown(slot, kind, level)
  if S.EnchantLearned(slot, kind) then return true end
  return C.Rules ~= nil and C.Rules.SeedEnchantable(slot, kind, level)
end
-- how many members the guild has seen with this enchant (by the id the link carries) in this slot
function S.EnchantIdSeen(slot, id)
  local k = S.Known()
  local rec = k and type(k.enchant) == "table" and k.enchant[slot]
  local er = type(rec) == "table" and type(rec.ench) == "table" and rec.ench[id]
  return type(er) == "table" and type(er.n) == "number" and er.n or 0
end
-- where the word that a slot takes an enchant comes from, for a tooltip: "seen on 3 members", else the seed's own
-- word on the slot, however many members the guild has seen with one on other kinds of item there
function S.EnchantSource(slot, kind)
  local n = S.EnchantSeen(slot, kind)
  if n > 0 then return n == 1 and "seen on 1 member" or ("seen on " .. n .. " members") end
  local st = C.Rules and C.Rules.SeedSlotState(slot)
  if st == "beta" then return "seen in the beta" end
  return "from research"
end
-- how many members the guild has seen with an enchant in this slot (on this kind of item, where kind is given)
function S.EnchantSeen(slot, kind)
  if not S.EnchantLearned(slot, kind) then return 0 end
  local rec = S.Known().enchant[slot]
  local r = kind ~= nil and rec.kinds[kind] or rec
  return type(r.n) == "number" and r.n or 0
end
-- a kind's name as the client gives it (C_Item.GetItemSubClassInfo: "Bows", "Shields"), the class.subclass where none
function S.KindName(kind)
  local class, sub = tostring(kind or ""):match("^(%d+)%.(%d+)$")
  if not class then return "?" end
  local name = Get(api("C_Item", "GetItemSubClassInfo"), tonumber(class), tonumber(sub))
  return (type(name) == "string" and name ~= "") and name or kind
end
-- the slots learned, in the slots' order, with how many members were seen with one and the kinds of item:
-- { { slot, label, n, { { kind, n }, ... } }, ... }
function S.EnchantSlots()
  local out = {}
  for _, e in ipairs(SLOT_OF) do
    if S.EnchantLearned(e[1]) then
      local kinds = {}
      for kind, r in pairs(S.Known().enchant[e[1]].kinds) do if type(r) == "table" then kinds[#kinds + 1] = { kind, type(r.n) == "number" and r.n or 0 } end end
      table.sort(kinds, function(a, b) return a[1] < b[1] end)
      out[#out + 1] = { e[1], e[2], S.EnchantSeen(e[1]), kinds }
    end
  end
  return out
end
-- the kinds of the enchanted items a record lists, as the wire carries them: "slot:class.subclass:enchant" for each
-- worn item whose readable link carries an enchant and whose kind reads, space-separated in the slots' order
-- ("2:4.0:2564 18:2.2:30"); whole entries up to the stat's 200 bytes. (0.4.0 sent "slot:class.subclass" and reads
-- these the same: its pattern stops at the second colon)
local KINDS_MAX = 200
function S.EnchantKindsText(g)
  local parts, len = {}, 0
  for _, s in ipairs(GEAR) do
    local e = g.slot[s]
    if e and e.link and (e.enchant or 0) > 0 and e.kind then
      local part = s .. ":" .. e.kind .. ":" .. math.floor(e.enchant)
      if len + #part + (#parts > 0 and 1 or 0) > KINDS_MAX then break end
      parts[#parts + 1] = part
      len = len + #part + (#parts > 1 and 1 or 0)
    end
  end
  return table.concat(parts, " ")
end
-- and back: { [slot] = kind } for the gear slots, anything else dropped, and { [slot] = enchant id } where it came
function S.EnchantKinds(text)
  local out, enchs = {}, {}
  if type(text) ~= "string" then return out, enchs end
  for slot, kind, rest in text:gmatch("(%d+):(%d+%.%d+)(:?%d*)") do
    slot = tonumber(slot)
    if SLOT[slot] and #kind <= 9 then
      out[slot] = kind
      local id = tonumber(rest:sub(2))
      if id and id > 0 and id < 2 ^ 31 then enchs[slot] = id end
    end
  end
  return out, enchs
end
-- your own read teaches the guild's knowledge too, and goes to the guild as the hidden ench_kinds (end of the file)
local function learnOwn(g)
  local text = S.EnchantKindsText(g)
  local kinds, enchs = S.EnchantKinds(text)
  S.LearnEnchants(kinds, C.MyGUID() or "me", enchs)
  if C.Sample and C.Sample.Set then C.Sample:Set("ench_kinds", text) end
end

-- consumables in your bags, by the game's own item classes (Enum.ItemClass.Consumable and its subclasses,
-- ItemConstantsDocumentation.lua), not by item ids: whatever potion or flask Forever adds counts the day it drops.
-- One scan of the backpack and the four bags (C_Container) serves every bag stat read in the same frame; BagClear
-- starts a fresh one. An item C_Item.GetItemInfoInstant cannot place (one the server sends that the client's own data
-- lacks) is asked of C_Item.GetItemInfo, whose twelfth and thirteenth returns are the class and subclass once cached
local CONSUMABLE = { potions = { "Potion", 1 }, elixirs = { "Elixir", 2 }, flasks = { "Flasksphials", 3 }, food = { "Fooddrink", 5 }, bandages = { "Bandage", 7 } }
local bagCache, bagAt
function S.BagClear() bagCache = nil end
local function bags()
  local now = gtime()
  if bagCache and bagAt == now then return bagCache end
  local numSlots, info, instant = api("C_Container", "GetContainerNumSlots"), api("C_Container", "GetContainerItemInfo"), api("C_Item", "GetItemInfoInstant")
  if not (numSlots and info and instant) then return nil end
  local itemInfo = api("C_Item", "GetItemInfo")
  local consumable = enum("ItemClass", "Consumable", 0)
  local sub, out, ids = {}, { items = 0 }, {}
  for key, e in pairs(CONSUMABLE) do sub[enum("ItemConsumableSubclass", e[1], e[2])] = key; out[key] = 0 end
  for b = enum("BagIndex", "Backpack", 0), enum("BagIndex", "Bag_4", 4) do
    local n = Num(numSlots, b)
    -- (a bag the client cannot count is a read that failed, with its reason; not a bag of nothing)
    if n == nil then return nil end
    for slot = 1, n do
      local it = Get(info, b, slot)
      if type(it) == "table" then
        local id, count = C.Plain(it.itemID), C.Plain(it.stackCount)
        if type(id) == "number" then
          out.items = out.items + 1
          ids[id] = true
          local _, _, _, _, _, class, subclass = Get(instant, id)
          if class == nil and itemInfo then local r = { Get(itemInfo, id) }; class, subclass = r[12], r[13] end
          local key = class == consumable and sub[subclass] or nil
          if key then out[key] = out[key] + (type(count) == "number" and count or 1) end
        end
      end
    end
  end
  bagCache, bagAt, bagIds = out, now, ids
  return out
end
local function consumables(key) return function() local b = bags(); return b and b[key] or nil end end

-- buffs on you, by spell id and name, read once a second at most. A long buff (five minutes or more) that a guild mate
-- cast on you is remembered by name (CuteDB.known.buffs[name] = { id, at, last, times, from = { [GUID] = true }, nfrom,
-- on }): the raid buffs are learned from who buffs you in play, not listed. Remembered is not yet a raid buff: one
-- counts once two different guild mates have cast it on you, or one has on three separate occasions (an occasion is
-- the buff coming on you while it was not; on is kept in the saved variables, so a /reload is none); one not cast on
-- you by a guild mate for two weeks is forgotten. And a missing one is counted only in a group or an instance. So a
-- Soulstone or a Thorns while leveling is no raid buff, and nothing is missing while you quest alone. (0.3.x listed
-- Classic's six; QuestBank's uploads show four of them on Forever characters, Fortitude, Mark of the Wild, Arcane
-- Intellect and Kings, and none of the other two, so a list would be wrong either way)
local BUFF_MIN, BUFF_FROM, BUFF_TIMES, BUFF_FORGET = 300, 2, 3, 14 * 86400
S.BUFF_FROM, S.BUFF_TIMES, S.BUFF_FORGET = BUFF_FROM, BUFF_TIMES, BUFF_FORGET
local auraCache, auraAt = nil, -1
local function learnBuff(name, sid, src)
  local k = S.Known()
  if not k then return end
  k.buffs = type(k.buffs) == "table" and k.buffs or {}
  local b, t = k.buffs[name], C.Now()
  if type(b) ~= "table" then b = { id = sid, at = t }; k.buffs[name] = b end
  b.last = t
  if not b.on then b.on = true; b.times = (tonumber(b.times) or 0) + 1 end
  b.from = type(b.from) == "table" and b.from or {}
  local g = Get("UnitGUID", src)
  if type(g) == "string" and g ~= "" and not b.from[g] and (tonumber(b.nfrom) or 0) < 40 then b.from[g] = true; b.nfrom = (tonumber(b.nfrom) or 0) + 1 end
end
-- a remembered buff the guild gives: from two guild mates, or three times from one
local function raidBuff(b) return type(b) == "table" and ((tonumber(b.nfrom) or 0) >= BUFF_FROM or (tonumber(b.times) or 0) >= BUFF_TIMES) end
S.RaidBuff = raidBuff
local function auras()
  local now = gtime()
  if auraCache and now - auraAt < 1 then return auraCache end
  local ids, names = {}, {}
  local byIndex = api("C_UnitAuras", "GetAuraDataByIndex")
  for i = 1, 60 do
    local a = Get(byIndex, "player", i, "HELPFUL")
    if type(a) ~= "table" then break end
    local sid, nm, src, dur = C.Plain(a.spellId), C.Plain(a.name), C.Plain(a.sourceUnit), C.Plain(a.duration)
    if type(sid) == "number" then ids[sid] = true end
    if type(nm) == "string" and nm ~= "" then
      names[nm] = true
      -- cast by a guild mate, not by you, and long: remembered
      if type(src) == "string" and src ~= "player" and type(dur) == "number" and dur >= BUFF_MIN
        and Get("UnitIsUnit", "player", src) ~= true and Get("UnitIsInMyGuild", src) == true then learnBuff(nm, sid, src) end
    end
  end
  -- what fell off is off (the next time it comes is another occasion); what no guild mate cast for two weeks goes
  local k = S.Known()
  if k and type(k.buffs) == "table" then
    local t = C.Now()
    for name, b in pairs(k.buffs) do
      if type(b) ~= "table" then k.buffs[name] = nil
      elseif not names[name] then
        b.on = nil
        if type(b.last) ~= "number" or t - b.last > BUFF_FORGET then k.buffs[name] = nil end
      end
    end
  end
  auraCache, auraAt = { ids = ids, names = names }, now
  return auraCache
end
-- in a group or an instance, by the documented calls: a party member (UnitExists), a raid index for you (UnitInRaid)
-- or IsInInstance
function S.Grouped()
  return Get("UnitExists", "party1") == true or type(Get("UnitInRaid", "player")) == "number" or Get("IsInInstance") == true
end
-- the raid buffs the guild gives that are not on you now, by name, sorted; none outside a group or an instance
function S.MissingBuffs()
  local k = S.Known()
  if not k or type(k.buffs) ~= "table" then return {} end
  local a = auras()
  if not S.Grouped() then return {} end
  local out = {}
  for name, b in pairs(k.buffs) do if raidBuff(b) and not a.names[name] then out[#out + 1] = name end end
  table.sort(out)
  return out
end
-- a remembered buff, for the tooltip: how many guild mates cast it on you and how many times
function S.Buff(name) local k = S.Known(); return k and type(k.buffs) == "table" and type(k.buffs[name]) == "table" and k.buffs[name] or nil end

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
  local now = gtime()
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
-- a skill line's name as the skills window gives it (Sample.lua knows a Fishing cast by it), nil where you have none
function S.SkillName(id) local sk = skills(); local l = sk and sk[id]; return (l and l.name ~= "") and l.name or nil end
S.FISHING = FISHING

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
  local now = gtime()
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
D("to60", "Hours to 60", "leveling", { track = true, slow = true, fmt = orDash, hint = "at the last hour's pace, over the XP each level ahead takes as the guild has learned it" })
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
D("dungeons", "Dungeons run", "leveling", { track = true, hint = "dungeon instances entered, not counting reloads; the same dungeon again only after another or a new session" })
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
-- readiness: the gaps a record shows, by name; nil until the gear and bags have been read. An empty slot, a missing
-- enchant (Missing enchants, below), durability under half, no potion in the bags
local READY_INPUTS = { "empty_slots", "unenchanted", "durability", "potions" }
local function listCount(v) local k = 0; if type(v) == "table" then for _, e in ipairs(SLOT_OF) do if v[e[1]] then k = k + 1 end end end return k end
function S.ReadyGaps(v)
  if type(v) ~= "table" or (v.durability == nil and v.potions == nil and type(v.empty_slots) ~= "table") then return nil end
  local gaps = {}
  local empty, missing = listCount(v.empty_slots), listCount(v.unenchanted)
  if empty > 0 then gaps[#gaps + 1] = empty == 1 and "an empty slot" or (empty .. " empty slots") end
  if missing > 0 then gaps[#gaps + 1] = missing == 1 and "a missing enchant" or (missing .. " missing enchants") end
  if type(v.durability) == "number" and v.durability < 50 then gaps[#gaps + 1] = "durability under 50%" end
  if v.potions == 0 then gaps[#gaps + 1] = "no potions" end
  return gaps
end
local GEAR_ON = { "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "GET_ITEM_INFO_RECEIVED" }
local BAG_ON = { "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "GET_ITEM_INFO_RECEIVED" }
D("ready", "Ready", "prog", { fmt = readyOf, gear = true, bag = true, on = { "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "GET_ITEM_INFO_RECEIVED", "UPDATE_INVENTORY_DURABILITY", "BAG_UPDATE_DELAYED" },
  hint = "ready with no gap, gaps with one or two, no with more: an empty slot, a missing enchant (as Missing enchants counts them), durability under 50%, no potions",
  read = function()
    -- from the inputs' live reads, so it never depends on which stat happened to be read first
    local v = {}
    for _, id in ipairs(READY_INPUTS) do local ok, x = pcall(S.byId[id].read); if ok then v[id] = C.Plain(x) end end
    local gaps = S.ReadyGaps(v)
    if not gaps then return nil end
    return #gaps == 0 and 2 or (#gaps <= 2 and 1 or 0)
  end })
D("ilvl", "Item level", "prog", { read = function() local avg = avgItemLevel(); return avg and math.floor(avg) or nil end, on = GEAR_ON, gear = true,
  hint = "the average over the items you wear" })
D("ilvl_slots", "Item level per slot", "prog", { kind = "list", of = SLOT_OF, on = GEAR_ON, gear = true, hint = "slots at or above your average", read = function()
  local avg = avgItemLevel()
  if not avg then return nil end
  return slotSet(function(_, e) return e ~= nil and e.level ~= nil and e.level >= avg end)
end })
D("empty_slots", "Empty slots", "prog", { kind = "list", of = SLOT_OF, default = "self", on = GEAR_ON, gear = true,
  read = function() return slotSet(function(s, e) return e == nil and s ~= 17 and s ~= 18 end) end })
-- the enchants, from the links alone: where a worn slot gives no readable link the stat reads nil and its tooltip says
-- why, rather than a count that would be wrong. Enchanted is the slots (everyone sees it; no column); the guild learns
-- from it with the kind of each enchanted item, which travels beside it as the hidden ench_kinds (end of the file).
-- Missing enchants is the worn items without one where the guild has enchanted the same kind of item in that slot,
-- or, from the rules' enchant level, where the seed has an enchant for that slot and kind (Rules.lua rule 5)
D("enchanted", "Enchanted slots", "prog", { kind = "list", of = SLOT_OF, default = "all", on = GEAR_ON, gear = true,
  hint = "worn slots whose item carries an enchant; the guild learns from these, with the kind of item, what takes one", read = function()
  local g = gear()
  if not g then return nil end
  learnOwn(g)
  local out, blind = {}, 0
  for s, e in pairs(g.slot) do
    if not e.link then blind = blind + 1 elseif (e.enchant or 0) > 0 then out[s] = true end
  end
  if blind > 0 then
    C.lastErr = string.format("the client gives no readable item link for %d worn slot%s, so enchants cannot be read", blind, blind == 1 and "" or "s")
    return nil
  end
  return out
end })
D("unenchanted", "Missing enchants", "prog", { kind = "list", of = SLOT_OF, default = "self", on = GEAR_ON, gear = true, countOnly = true,
  hint = "worn items without an enchant where the guild has seen the same kind of item enchanted in that slot, or, from the rules' enchant level (30 unless the officers set another), where Forever has one for that slot and kind by the research, unless the guild doubts it",
  -- (a member's list as this client knows the guild and the seed: a slot neither has an enchant for is left out, so
  -- an older client's head and shoulder never show. Their own client cut it by their level)
  filter = function(v) local out = {}; for slot in pairs(v) do if S.EnchantKnown(slot) then out[slot] = true end end return out end,
  read = function()
    local g = gear()
    if not g then return nil end
    learnOwn(g)
    -- (a level that does not read counts as under the enchant level: only what the guild has enchanted is asked for)
    local lvl = Num("UnitLevel", "player") or 0
    local out, blind, kindless = {}, 0, 0
    for s, e in pairs(g.slot) do
      -- (an item whose kind reads and takes no enchant here is never asked for, link or none)
      if S.EnchantKnown(s, nil, lvl) and not (e.kind and not S.EnchantKnown(s, e.kind, lvl)) then
        if not e.link then blind = blind + 1
        elseif (e.enchant or 0) == 0 then
          -- (a wand where the guild has scoped bows, a book held in the off hand where it has enchanted shields: not
          -- asked for. An item whose kind does not read yet cannot be told apart, so the count waits for it)
          if not e.kind then kindless = kindless + 1 elseif S.EnchantKnown(s, e.kind, lvl) then out[s] = true end
        end
      end
    end
    if blind > 0 then
      C.lastErr = string.format("the client gives no readable item link for %d worn slot%s that take%s an enchant, so enchants cannot be read", blind, blind == 1 and "" or "s", blind == 1 and "s" or "")
      return nil
    end
    if kindless > 0 then
      C.lastErr = string.format("the kind of %d worn item%s does not read yet (the client has not cached %s)", kindless, kindless == 1 and "" or "s", kindless == 1 and "it" or "them")
      return nil
    end
    return out
  end })
D("old_gear", "Gear 10+ levels old", "prog", { kind = "list", of = SLOT_OF, default = "self", gear = true,
  on = { "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "PLAYER_LEVEL_UP", "GET_ITEM_INFO_RECEIVED" }, read = function()
  local lvl = Num("UnitLevel", "player") or 1
  return slotSet(function(_, e) return e ~= nil and e.level ~= nil and e.level < lvl - 10 end)
end })
D("greens", "Green items worn", "prog", { default = "self", on = GEAR_ON, gear = true, read = function()
  local g = gear()
  if not g then return nil end
  if g.worn > 0 and g.noQuality == g.worn then C.lastErr = "no item quality reads for the items worn"; return nil end
  local n = 0
  for _, e in pairs(g.slot) do if e.quality ~= nil and e.quality <= 2 then n = n + 1 end end
  return n
end })
D("durability", "Durability", "prog", { fmt = pct, gear = true, on = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED" }, read = function()
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
-- consumables by the game's item classes (bags, above)
D("potions", "Potions", "prog", { read = consumables("potions"), on = BAG_ON, bag = true, hint = "in your bags, every potion the game calls one" })
D("elixirs", "Elixirs", "prog", { read = consumables("elixirs"), on = BAG_ON, bag = true, hint = "in your bags" })
D("flasks", "Flasks", "prog", { read = consumables("flasks"), on = BAG_ON, bag = true, hint = "in your bags, flasks and phials" })
D("food", "Food and drink", "prog", { read = consumables("food"), on = BAG_ON, bag = true, hint = "in your bags" })
D("bandages", "Bandages", "prog", { read = consumables("bandages"), on = BAG_ON, bag = true, hint = "in your bags" })
-- healthstones by item id: the one class reagent with evidence on Forever (QuestBank's uploads find Minor and Lesser
-- Healthstones, 5512 and 5511, in Forever characters' bags); soul shards, shaman totems and rogue poisons had none. The
-- ids are Forever's own item list (plan/items-db.json, the beta build 1.60.1.70291): Minor to Major, 5512, 5511, 5509,
-- 5510 and 9421, and the improved ranks a talented warlock conjures, 19004 to 19013. Nothing in the documented API
-- tells a healthstone from another conjured item (a mana gem is the same class and subclass), so these stay listed
local HEALTHSTONES = { 5512, 5511, 5509, 5510, 9421, 19004, 19005, 19006, 19007, 19008, 19009, 19010, 19011, 19012, 19013 }
D("stones", "Healthstones", "prog", { read = function() local n = 0; for _, id in ipairs(HEALTHSTONES) do n = n + itemCount(id) end; return n end,
  on = BAG_ON, bag = true })
D("ammo", "Ammo", "prog", { read = function() return Num("GetInventoryItemCount", "player", 0) end, on = BAG_ON, bag = true, hint = "in the ammo slot" })
D("bags_free", "Free bag slots", "prog", { read = function() return bagTotal("GetContainerNumFreeSlots") end, on = BAG_ON, bag = true })
D("bags_size", "Bag slots", "prog", { read = function() return bagTotal("GetContainerNumSlots") end, on = BAG_ON, bag = true })
-- the raid buffs guild mates give you (learned, above) that are not on you now, in a group or an instance
D("buffs_missing", "Raid buffs missing", "prog", { default = "self", on = { "UNIT_AURA", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" },
  hint = "long buffs two guild mates (or one, three times) have cast on you in the last two weeks that you have not got now; counted in a group or an instance",
  read = function() local k = S.Known(); if not k then return nil end return #S.MissingBuffs() end })
-- what this character has met in play, counted from the discovered stats (Sample.lua keeps them)
D("bosses", "Bosses killed", "prog", { track = true, hint = "different bosses this character has killed, as the game reports encounters" })
D("dungeons_seen", "Dungeons seen", "prog", { track = true, hint = "different dungeons this character has entered" })
D("raids", "Raids attended", "prog", { track = true, hint = "raid instances entered, counted" })
-- the effective resistance (third return), the one the character sheet shows; the damage schools are the game's structure
local function resist(n) return function() local _, _, v = Get("UnitResistance", "player", n); return type(v) == "number" and v or nil end end
D("resist_fire", "Fire resist", "prog", { read = resist(2), on = GEAR_ON, gear = true })
D("resist_nature", "Nature resist", "prog", { read = resist(3), on = GEAR_ON, gear = true })
D("resist_frost", "Frost resist", "prog", { read = resist(4), on = GEAR_ON, gear = true })
D("resist_shadow", "Shadow resist", "prog", { read = resist(5), on = GEAR_ON, gear = true })
D("resist_arcane", "Arcane resist", "prog", { read = resist(6), on = GEAR_ON, gear = true })
D("pvp_rank", "PvP rank", "prog", { read = function() local rank = pvp(); return type(rank) == "number" and rank or nil end, on = PVP_ON, hint = "0 is unranked, as the PvP tab shows" })
D("pvp_pts", "Rank points", "prog", { read = function() local _, pts = pvp(); return type(pts) == "number" and pts or nil end, on = PVP_ON, hint = "toward the next PvP rank, as the PvP tab shows" })
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
D("gold", "Gold", "officer", { read = money, fmt = goldOf, on = "PLAYER_MONEY" })
D("bank_in", "Guild bank deposits", "officer", { track = true, fmt = goldOf, hint = "while the guild bank was open" })
D("bank_out", "Guild bank withdrawals", "officer", { track = true, fmt = goldOf, hint = "while the guild bank was open" })
D("consumed", "Consumables used in raids", "officer", { track = true, hint = "potions, elixirs, flasks and food that left your bags in a raid" })
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
D("where", "\"where are you\" typed", "funny", { track = true, hint = "in any chat you type in; wya, where r u and the guild's languages count" })
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
-- hidden: what a record carries for the addon, never shown. Kept out of S.list and the categories, so no page, column,
-- checklist, policy pair or the web page lists them; Comm sends them with the full record (in this order), a receiver
-- decodes them like any text stat.
--   guid        your character's GUID. It goes first in every full record so a receiver can join the record to the
--               guild roster's member with the same GUID (names are no key on Forever: two words, a Kstring at times;
--               Core.lua) and drop a record whose GUID is its own (the game hands a guild addon message back to its
--               sender too). Sample sets it at login; up to 40 characters
--   ench_kinds  the kind of each enchanted item you wear and the enchant on it, "slot:class.subclass:enchant"
--               (EnchantKindsText, above), which the guild learns its enchants from; set by your own gear reads, sent
--               as a delta when it changes too. 200 bytes at most, whole entries
--   xpmax       the XP your level takes, "level:max" (UnitXPMax at the level you are), which the guild learns its XP
--               curve from (Rules.lua rule 6). The level travels in it, so a receiver never pairs a new level with
--               the last one's XP. Slow: it changes once a level
----------------------------------------------------------------------------
S.HIDDEN = { guid = { id = "guid", label = "Character GUID", cat = "hidden", kind = "text", max = 40, default = "all", hidden = true },
  ench_kinds = { id = "ench_kinds", label = "Enchanted item kinds", cat = "hidden", kind = "text", max = KINDS_MAX, default = "all", hidden = true },
  xpmax = { id = "xpmax", label = "XP this level takes", cat = "hidden", kind = "text", max = 16, default = "all", hidden = true, slow = true } }
S.HIDDEN_ORDER = { "guid", "ench_kinds", "xpmax" }
S.byId.guid = S.HIDDEN.guid
S.byId.ench_kinds = S.HIDDEN.ench_kinds
S.byId.xpmax = S.HIDDEN.xpmax

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

----------------------------------------------------------------------------
-- discovered: what the guild meets in play, defined at run time (the sixth category, found)
----------------------------------------------------------------------------
-- Three kinds of stat, each defined the first time a label for it is known, from your own play or from the guild
-- channel, and kept by receivers like the game's statistics (any client keeps the values of an id it has not defined):
--   e<encounterID>  kills of a boss by this character (ENCOUNTER_END with success, BOSS_KILL where none came; Sample.lua),
--                   labelled with the encounter's name, grouped by the instance it was killed in
--   i<instanceID>   times this character entered an instance, labelled with its name, a dungeon or a raid as the
--                   game's instanceType says
--   f<factionID>    this character's standing with a faction its reputation list holds, labelled with its name
-- CuteDB.known keeps what was learned: labels[id] (60 bytes at most, UTF-8 kept), mine[id] (this client found it, so
-- its label wins over another locale's), inst[encounterID] (the instance a boss was killed in), kind[instanceID]
-- ("party", "raid", or "world" for the continent an open-world boss stood on, which is what GetInstanceInfo names
-- outside an instance) and reactions[r] (the standing range of a reaction,
-- learned from your own factions, so a member's standing can be named). A label from the channel fills a gap and never
-- replaces one this client found. Comm.lua carries them in "1L" messages.
S.FOUND_CAP = 1000 -- discovered stats defined at most
S.LABEL_CAP = 4000 -- labels kept at most from the channel (a client's own always are), so no sender can fill the saved variables
S.FOUND = { { "bosses", "Bosses" }, { "dungeons", "Dungeons" }, { "raids", "Raids" }, { "rep", "Reputation" } }
S.foundVersion = 0
S.LABEL_MAX = 60
local KIND_OF = { party = "party", raid = "raid", p = "party", r = "raid", w = "world" }

-- client text as it may travel and be shown: the separators | ; = and control characters gone, valid UTF-8 kept (a
-- Norwegian or German client's names, an accent in a name), a broken sequence dropped, cut to max bytes without
-- splitting a character. Comm.lua cleans its text stats the same way
local function utf8Clean(s)
  local out, i, n = {}, 1, #s
  while i <= n do
    local c = s:byte(i)
    local len = c < 0x80 and 1 or (c >= 0xC2 and c <= 0xDF and 2) or (c >= 0xE0 and c <= 0xEF and 3) or (c >= 0xF0 and c <= 0xF4 and 4) or 0
    local ok = len > 0 and i + len - 1 <= n
    for j = i + 1, i + len - 1 do if ok then local b = s:byte(j); ok = b >= 0x80 and b <= 0xBF end end
    if ok then out[#out + 1] = s:sub(i, i + len - 1); i = i + len else i = i + 1 end
  end
  return table.concat(out)
end
function S.CleanText(s, max)
  if s == nil then return "" end
  s = utf8Clean((tostring(s):gsub("[|;=]", ""):gsub("%c", "")))
  max = max or S.LABEL_MAX
  if #s > max then
    local cut = max
    while cut > 0 do local b = s:byte(cut + 1); if not b or b < 0x80 or b > 0xBF then break end cut = cut - 1 end
    s = s:sub(1, cut)
  end
  return s
end
function S.CleanLabel(s) return (S.CleanText(s, S.LABEL_MAX):gsub("^%s+", ""):gsub("%s+$", "")) end
-- an id the wire carries as a bare int whether or not this client defined it: a statistic, a boss, an instance, a
-- faction, and the level a member had at a boss's first kill (k<encounterID>: no stat, Rules.lua's evidence; a 0.4.0
-- client drops it)
function S.IsDynamic(id) return type(id) == "string" and id:match("^[gefik]%d+$") ~= nil and #id <= 12 end

-- the reaction a standing falls in, from the ranges your own factions showed (nil where none covers it), and its name
-- (the game's FACTION_STANDING_LABEL1..8, the number where the client has none)
function S.Reaction(v)
  local k = S.Known()
  if not k or type(v) ~= "number" or type(k.reactions) ~= "table" then return nil end
  for r, t in pairs(k.reactions) do
    if type(r) == "number" and type(t) == "table" and type(t.lo) == "number" and type(t.hi) == "number" and v >= t.lo and (v < t.hi or t.hi <= t.lo) then return r end
  end
end
function S.ReactionName(r)
  if type(r) ~= "number" then return nil end
  local s = C.Plain(_G["FACTION_STANDING_LABEL" .. r])
  return (type(s) == "string" and s ~= "") and s or tostring(r)
end
local function learnReaction(r, lo, hi)
  local k = S.Known()
  if not k or type(r) ~= "number" or type(lo) ~= "number" or type(hi) ~= "number" then return end
  k.reactions = type(k.reactions) == "table" and k.reactions or {}
  -- the first range seen stays (a faction with its own scale never moves the common one)
  if k.reactions[r] == nil then k.reactions[r] = { lo = lo, hi = hi } end
end

-- your reputation list as Forever's reputation window reads it (C_Reputation.GetNumFactions and GetFactionDataByIndex,
-- ReputationInfoDocumentation.lua): every row with a standing (not a plain header; a header with rep counts), once a
-- second at most. A section folded in the window lists no rows; the factions this character listed before are asked by
-- id instead (GetFactionDataByID), so folding a header loses none. { [factionID] = { standing, reaction, name } }
local facCache, facAt = nil, -1
function S.FactionsClear() facCache = nil end
function S.Factions()
  local now = gtime()
  if facCache and now - facAt < 1 then return facCache end
  local n = Num(api("C_Reputation", "GetNumFactions"))
  local byIndex, byId = api("C_Reputation", "GetFactionDataByIndex"), api("C_Reputation", "GetFactionDataByID")
  if not (n and byIndex) then return nil end
  local out = {}
  local function take(d)
    if type(d) ~= "table" then return end
    local id, name, standing, reaction = C.Plain(d.factionID), C.Plain(d.name), C.Plain(d.currentStanding), C.Plain(d.reaction)
    local header, withRep = C.Plain(d.isHeader), C.Plain(d.isHeaderWithRep)
    if type(id) ~= "number" or id <= 0 or type(standing) ~= "number" then return end
    if header == true and withRep ~= true then return end
    out[id] = { standing = standing, reaction = type(reaction) == "number" and reaction or nil, name = type(name) == "string" and name or nil }
    learnReaction(reaction, C.Plain(d.currentReactionThreshold), C.Plain(d.nextReactionThreshold))
  end
  for i = 1, math.min(n, 400) do take(Get(byIndex, i)) end
  local ch = C.Char()
  ch.factions = type(ch.factions) == "table" and ch.factions or {}
  if byId then for id in pairs(ch.factions) do if not out[id] then take(Get(byId, id)) end end end
  for id in pairs(out) do ch.factions[id] = true end
  facCache, facAt = out, now
  return out
end

-- the group a discovered id belongs in, and its number; nil for an instance whose kind is not known yet
local function groupOf(id)
  local prefix, num = id:match("^([efi])(%d+)$")
  num = tonumber(num)
  if not (prefix and num) then return nil end
  local k = S.Known()
  if prefix == "e" then return "bosses", num end
  if prefix == "f" then return "rep", num end
  local kind = k and k.kind and k.kind[num]
  if kind == "party" then return "dungeons", num elseif kind == "raid" then return "raids", num end
  return nil, num
end

-- define (or relabel) a discovered stat from what is known of it; the def, or nil when it cannot be shown yet
function S.Found(id)
  local k = S.Known()
  local label = k and k.labels and k.labels[id]
  if type(label) ~= "string" or label == "" then return nil end
  local group, num = groupOf(id)
  if not group then return nil end
  local def = S.byId[id]
  if def then
    if def.cat ~= "found" then return nil end
    if def.label ~= label or def.learned ~= group then def.label, def.learned = label, group; S.foundVersion = S.foundVersion + 1 end
    return def
  end
  if #S.byCat.found >= S.FOUND_CAP then return nil end
  local o = { learned = group, default = "all", num = num }
  if group == "rep" then
    -- the standing is read from the list; it moves with every kill of the faction's foes, so it travels on the flush
    o.read = function() local f = S.Factions(); local e = f and f[num]; return e and e.standing or nil end
    o.slow = true
    o.fmt = function(v) return S.ReactionName(S.Reaction(v)) or (type(v) == "number" and tostring(v) or "?") end
    o.hint = "standing with this faction, as your reputation list shows it"
  else
    -- a count Sample.lua keeps per character; a character that never met it has no value (not a 0 on the wire)
    o.track = true
    o.hint = group == "bosses" and "kills by this character" or "entries by this character, not counting reloads"
  end
  def = S.def(id, label, "found", o)
  S.foundVersion = S.foundVersion + 1
  -- (a page that lists the discoveries draws again; a hidden window draws nothing)
  if C.UI and C.UI.Refresh then C.UI:Refresh() end
  return def
end

-- a label learned: own (this client met it) or from the guild channel. For a boss the instance it was killed in, for an
-- instance its kind. Returns true when this client found something new to tell the guild (an own discovery, or an own
-- label that differs from the one it had)
function S.Label(id, label, own, inst, kind)
  local k = S.Known()
  if not k or type(id) ~= "string" or not id:match("^[efi]%d+$") then return false end
  label = S.CleanLabel(label)
  if label == "" then return false end
  k.labels, k.mine, k.inst, k.kind = k.labels or {}, k.mine or {}, k.inst or {}, k.kind or {}
  if not S.labelCount then S.labelCount = 0; for _ in pairs(k.labels) do S.labelCount = S.labelCount + 1 end end
  local tell = false
  if own then
    tell = not k.mine[id] or k.labels[id] ~= label
    if k.labels[id] == nil then S.labelCount = S.labelCount + 1 end
    k.labels[id], k.mine[id] = label, true
  elseif k.labels[id] == nil then
    if S.labelCount >= S.LABEL_CAP then return false end
    k.labels[id] = label
    S.labelCount = S.labelCount + 1
  end
  local num = tonumber(id:sub(2))
  if id:sub(1, 1) == "e" and type(inst) == "number" and inst >= 0 and (own or k.inst[num] == nil) then
    if k.inst[num] ~= inst then k.inst[num] = inst; S.foundVersion = S.foundVersion + 1 end
  end
  kind = KIND_OF[kind or ""]
  if id:sub(1, 1) == "i" and kind and (own or k.kind[num] == nil) then
    if k.kind[num] ~= kind then k.kind[num] = kind; S.foundVersion = S.foundVersion + 1 end
  end
  S.Found(id)
  return tell
end

-- at login: every label saved defines its stat again, and the records saved teach the enchants (a member who has left
-- since still taught them), each by the GUID it carries; a record without one teaches nothing (it would count a member
-- a second time once the GUID comes)
function S.LoadKnown()
  local k = S.Known()
  if not k then return end
  for id in pairs(k.labels or {}) do if type(id) == "string" then S.Found(id) end end
  for _, e in pairs(CuteDB.roster or {}) do
    local st = type(e) == "table" and e.stats
    if type(st) == "table" and type(st.ench_kinds) == "string" and type(st.guid) == "string" and st.guid ~= "" then
      local kinds, enchs = S.EnchantKinds(st.ench_kinds)
      S.LearnEnchants(kinds, st.guid, enchs)
    end
  end
end

-- the Statistics page's categories: the discovered first (Bosses with a child per instance, Dungeons, Raids,
-- Reputation; an empty one left out), then the game's own as ProbeGame grouped them. { cats, byCat }: a category is
-- { id, name, parent (-1 or the parent's id), path, stats, count (a parent's: its children's), learned }. Built again
-- only when a discovered stat or the game's list changed
local boardCache, boardKey
local function byLabel(a, b) if a.label == b.label then return a.id < b.id end return a.label < b.label end
function S.Board()
  local key = S.foundVersion .. ":" .. tostring(S.game)
  if boardCache and boardKey == key then return boardCache end
  local k = S.Known() or {}
  local cats, byCat = {}, {}
  local groups, inst = { dungeons = {}, raids = {}, rep = {} }, {}
  for _, def in ipairs(S.byCat.found) do
    if def.learned == "bosses" then
      local i = (k.inst and k.inst[def.num]) or -1
      inst[i] = inst[i] or {}
      table.insert(inst[i], def)
    elseif groups[def.learned] then
      table.insert(groups[def.learned], def)
    end
  end
  local function add(c) cats[#cats + 1] = c; byCat[c.id] = c.stats end
  if next(inst) then
    local parent = { id = "bosses", name = "Bosses", parent = -1, path = "Bosses", stats = {}, count = 0, learned = "bosses" }
    local children = {}
    for i, list in pairs(inst) do
      table.sort(list, byLabel)
      local name = (i >= 0 and k.labels and k.labels["i" .. i]) or "Instance not named yet"
      local child = { id = "b" .. i, name = name, parent = "bosses", path = "Bosses > " .. name, stats = list, learned = "bosses" }
      for _, def in ipairs(list) do def.hint = "kills by this character, in " .. name end
      children[#children + 1] = child
      parent.count = parent.count + #list
    end
    table.sort(children, function(a, b) if a.name == b.name then return a.id < b.id end return a.name < b.name end)
    parent.first = children[1].id
    add(parent)
    for _, c in ipairs(children) do add(c) end
  end
  for _, g in ipairs(S.FOUND) do
    local list = groups[g[1]]
    if list and #list > 0 then table.sort(list, byLabel); add({ id = g[1], name = g[2], parent = -1, path = g[2], stats = list, learned = g[1] }) end
  end
  for _, c in ipairs(S.game.cats or {}) do add(c) end
  boardCache, boardKey = { cats = cats, byCat = byCat }, key
  return boardCache
end

-- one line for /cute diag: the enchants learned (slot, members seen with one, the kinds of item), the labels, the buffs
function S.KnownReport()
  local k = S.Known()
  if not k then return "known: nothing yet (no saved variables)" end
  local slots = {}
  for _, e in ipairs(S.EnchantSlots()) do
    local kinds = {}
    for _, kd in ipairs(e[4]) do kinds[#kinds + 1] = S.KindName(kd[1]) .. " " .. kd[2] end
    slots[#slots + 1] = e[2] .. " (" .. e[3] .. ": " .. table.concat(kinds, ", ") .. ")"
  end
  local n = { e = 0, i = 0, f = 0 }
  for id in pairs(k.labels or {}) do local p = type(id) == "string" and id:sub(1, 1); if n[p] then n[p] = n[p] + 1 end end
  local buffs, raid = 0, 0
  for _, b in pairs(k.buffs or {}) do buffs = buffs + 1; if raidBuff(b) then raid = raid + 1 end end
  return string.format("known: enchant slots %s | labels %d (bosses %d, instances %d, factions %d) | raid buffs %d of %d remembered",
    #slots > 0 and table.concat(slots, ", ") or "none", n.e + n.i + n.f, n.e, n.i, n.f, raid, buffs)
end

-- what a category contains, in order
function S.Cat(cat) return S.byCat[cat] end
function S.Get(id) return S.byId[id] end
