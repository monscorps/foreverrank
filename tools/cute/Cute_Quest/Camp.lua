-- SPDX-License-Identifier: GPL-3.0-or-later
-- Camp: what the camp, your food, the sleeping bag and your buffs are, and the reminders that come from them, as
-- providers of Remind.lua (which draws them: Reminders and Buffs, one quiet place; a click is the game's secure button,
-- set out of a fight only). Each gives XP on Forever (Welcoming Campfire, Well Fed XP Boost, Well-Rested):
--   sit      a fire near you (the game's Campfire Nearby, any fire) and neither Welcoming Campfire nor Camp Benefits on
--            you, not mounted: "Sit", a /sit (sitting is restricted to secure code); sitting, the Welcoming aura's
--            countdown. A Cooking Fire object under your Interact key without the aura: "Sit" for 15 s, and an object
--            that gives nothing after a /sit is left alone for the session
--   place    your own kit's fire lit within 300 s, a camp feature you carry whose buff you lack, the shared hour up
--   fire     one icon at Fire's moment (standing still 20 s out of town and instances, no fire near, no Camp Benefits),
--            the first of: Light (a kit you carry), Make (wood and flint and the recipe), Wood (a cook who has used a kit
--            and has none: the nearest seller within 10 min, waiting, its minutes), Cook (not a cook: the cooking
--            trainer, once). Wood and Cook also in town within 2 minutes of where their click leads
--   eat      not Well Fed (the 30 Well Fed auras, by id or the client's own name) out of towns and instances: the
--            cheapest food you carry that gives it (D.FOOD, and meals learned: one followed by Well Fed is kept, one
--            that ends without it dropped)
--   sleep    the Cozy Sleeping Bag held, Well-Rested under 3 stacks, its cooldown up, out of town, still 20 s
--   bagchain the step frame's line from level 14 with no bag: the bag's quest chain, one step at a time
--   self     Buffs: each buff of your class you know and lack (Camp.SELF), and the ones learned from your habits
--   party    Buffs' second row, in a party and not a raid: each member in sight lacking a buff of yours for others
-- Sellers (5.4.4): each merchant you open who sells camp goods is noted with where it stands (QuestBankDB.disc.sell, in
-- the uploads); for Simple Wood and Flint and Tinder also the Classic database's general goods vendors (D.CAMP_SELL),
-- said to be Classic data that may have moved until a player's game has seen the seller.
-- What the game tells: your professions (GetProfessions), your bags (Remind's scan), your auras (C_UnitAuras, read
-- out of a fight), the spells you know (C_SpellBook.IsSpellKnown), the spell a kit casts (D.CAMP[id].sp, seen on
-- UNIT_SPELLCAST_SUCCEEDED), the object under your Interact key, and your rested state (IsResting).
local _, QB = ...
if QB.dormant then return end
local Camp = {}
QB.Camp = Camp

local CAMP_CD = 3600      -- the shared camp cooldown, without Field Guide
Camp.CAMP_CD = CAMP_CD
-- the shared camp cooldown in seconds: the hour, less Field Guide's 288 / 612 / 900 (QB.Legacy)
function Camp.CampCD() return QB.Legacy and QB.Legacy.CampCooldown() or CAMP_CD end
-- a food's text with Gourmand's longer Well Fed ("15 min" reads 20 / 25 / 30)
local function foodText(s) return QB.Legacy and QB.Legacy.FoodText(s) or s end
Camp.FoodText = foodText

local plain = QB.Plain
local function now() return GetTime and GetTime() or 0 end
-- Basic Campfire (spell 818, Cooking) lights a fire from one Simple Wood (4470) and has a 5-minute cooldown (the
-- client's SpellReagents and SpellCooldowns). Classic Era's cooks learn it with the skill; Forever's tables
-- (1.60.1.70338) mark it never learned, and Forever's own Basic Campfire (1229737) is a recipe that makes the Basic
-- Campfire Kit (279981) from the same wood, with Flint and Tinder (4471) as its tool, learned at Cooking 1: there the
-- kit is the fire. No vendor sells a kit (cooks make them)
Camp.FIRE_SPELL, Camp.FIRE_ICON, Camp.WOOD, Camp.BASIC_KIT = 818, 135805, 4470, 279981
Camp.FLINT, Camp.KIT_RECIPE = 4471, 1229737
Camp.BAG = 211527 -- the Cozy Sleeping Bag
Camp.BAG_LEVEL = 14 -- its quest chain's first step asks for level 14
-- the game's own camp auras (1.60.1.70338): "Campfire Nearby" while a fire burns within about 100 yards of you (yours,
-- another player's, a quest giver's); "Welcoming Campfire", the minute you sit by one counting down (its newer form
-- counts crafting too, as long as you don't move); then "Camp Benefits" for an hour, with the buffs of that fire's camp
-- features. Read out of a fight only: the client hides auras in one
Camp.NEARBY, Camp.BENEFITS = 1283391, 1229741
Camp.WELCOME = { [1229739] = true, [1289723] = true }
Camp.KIT_BURN = 900 -- seconds a kit's fire burns

-- the long buffs each class keeps on itself, Classic's: the class's rows in the client's SkillLineAbility, the same ids
-- on Forever (1.60.1.70338) and Classic Era (1.15.9). Each entry is one buff to have: the spells that give it (the one
-- last seen on you first, then in this order), each with its icon and its ranks, lowest first. The highest rank you
-- know is cast; any rank counts as on, and so do alsoIds (a group version, another aspect, blessing or aura, by id: the
-- class's rows in SkillLineAbility.csv under those names, so a localised client matches) and the names in also (a
-- talent's, which those rows lack). Battle Shout and the other short ones are left out, and so are the tanking
-- toggles (Righteous Fury: a wrong cast hurts). other: every spell of the entry can be cast on another player
-- (SpellMisc's RangeIndex 4, Medium Range, 30 yards, on 1.60.1.70338; the armors, Inner Fire, Lightning Shield and
-- Aspect of the Hawk are RangeIndex 1, Self Only), offered for party members; tank: only on the member the game marks
-- as tank (Thorns), and on yourself
Camp.SELF = {
  MAGE = {
    { { "Arcane Intellect", 135932, { 1459, 1460, 1461, 10156, 10157 } }, alsoIds = { 23028 }, also = { "Arcane Brilliance" }, other = true },
    { { "Ice Armor", 135843, { 7302, 7320, 10219, 10220 } }, { "Frost Armor", 135843, { 168, 7300, 7301 } },
      { "Mage Armor", 135991, { 6117, 22782, 22783 } } },
  },
  PRIEST = {
    { { "Power Word: Fortitude", 135987, { 1243, 1244, 1245, 2791, 10937, 10938 } }, alsoIds = { 21562, 21564 }, also = { "Prayer of Fortitude" }, other = true },
    { { "Inner Fire", 135926, { 588, 7128, 602, 1006, 10951, 10952 } } },
  },
  DRUID = {
    { { "Mark of the Wild", 136078, { 1126, 5232, 6756, 5234, 8907, 9884, 9885 } }, alsoIds = { 21849, 21850 }, also = { "Gift of the Wild" }, other = true },
    { { "Thorns", 136104, { 467, 782, 1075, 8914, 9756, 9910 } }, other = true, tank = true },
  },
  WARLOCK = {
    { { "Demon Armor", 136185, { 706, 1086, 11733, 11734, 11735 } }, { "Demon Skin", 136185, { 687, 696 } } },
  },
  SHAMAN = {
    { { "Lightning Shield", 136051, { 324, 325, 905, 945, 8134, 10431, 10432 } } },
  },
  HUNTER = {
    { { "Aspect of the Hawk", 136076, { 13165, 14318, 14319, 14320, 14321, 14322, 25296 } }, { "Aspect of the Monkey", 132159, { 13163 } },
      alsoIds = { 5118, 13159, 20043, 20190, 13161, 1299445, 1299446, 1299447 },
      also = { "Aspect of the Cheetah", "Aspect of the Pack", "Aspect of the Wild", "Aspect of the Beast" } },
  },
  PALADIN = {
    { { "Blessing of Might", 135906, { 19740, 19834, 19835, 19836, 19837, 19838, 25291 } },
      { "Blessing of Wisdom", 135970, { 19742, 19850, 19852, 19853, 19854, 25290 } },
      alsoIds = { 20217, 1038, 19977, 19978, 19979, 25782, 25916, 25894, 25918, 25898, 25895, 25890 },
      also = { "Blessing of Kings", "Blessing of Salvation", "Blessing of Light", "Blessing of Sanctuary", "Greater Blessing of Might",
               "Greater Blessing of Wisdom", "Greater Blessing of Kings", "Greater Blessing of Salvation", "Greater Blessing of Light" }, other = true },
    -- (an aura: Devotion Aura is the one cast, any aura of yours counts)
    { { "Devotion Aura", 135893, { 465, 10290, 643, 10291, 1032, 10292, 10293 } },
      alsoIds = { 7294, 10298, 10299, 10300, 10301, 19746, 19876, 19895, 19896, 19888, 19897, 19898, 19891, 19899, 19900 },
      also = { "Sanctity Aura" } },
  },
}

-- a spell you know: C_SpellBook.IsSpellKnown, or IsPlayerSpell on a client without it
local function knows(id)
  if C_SpellBook and type(C_SpellBook.IsSpellKnown) == "function" then
    local ok, v = pcall(C_SpellBook.IsSpellKnown, id)
    if ok then return plain(v) == true end
  end
  if type(IsPlayerSpell) == "function" then
    local ok, v = pcall(IsPlayerSpell, id)
    return ok and plain(v) == true
  end
  return false
end
Camp.Knows = knows
-- (the C_Spell calls, or the old globals of a client without them)
local function spellIcon(id, fallback)
  local get = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
  if type(get) == "function" then
    local ok, tex = pcall(get, id)
    tex = ok and plain(tex) or nil
    if tex then return tex end
  end
  return fallback
end
-- its name in the player's language, for the aura it puts on you
local function spellName(id, fallback)
  local get = C_Spell and C_Spell.GetSpellName or GetSpellInfo
  if type(get) == "function" then
    local ok, n = pcall(get, id)
    n = ok and plain(n) or nil
    if type(n) == "string" and n ~= "" then return n end
  end
  return fallback
end
-- a spell's cooldown, start and duration; 0, 0 when ready, on the global cooldown or unreadable
local function spellCD(id)
  local start, dur
  if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
    local ok, cd = pcall(C_Spell.GetSpellCooldown, id)
    cd = ok and plain(cd) or nil
    if type(cd) == "table" then start, dur = plain(cd.startTime), plain(cd.duration) end
  elseif type(GetSpellCooldown) == "function" then
    local ok, a, b = pcall(GetSpellCooldown, id)
    if ok then start, dur = plain(a), plain(b) end
  end
  if type(start) ~= "number" or type(dur) ~= "number" or start <= 0 or dur <= 1.5 then return 0, 0 end
  return start, dur
end

-- your professions by name, with the skill
-- (into: a table kept, emptied first)
function Camp.Professions(into)
  local out = into or {}
  for k in pairs(out) do out[k] = nil end
  if not (GetProfessions and GetProfessionInfo) then return out end
  local ok, a, b, _, fish, cook, aid = pcall(GetProfessions)
  if not ok then return out end
  local function one(i)
    if not i then return end
    local okI, name, _, skill = pcall(GetProfessionInfo, i)
    name, skill = plain(name), plain(skill)
    if okI and type(name) == "string" and type(skill) == "number" then out[name] = skill end
  end
  one(a); one(b); one(fish); one(cook); one(aid)
  return out
end
-- a cook: Cooking among your professions, or its Basic Campfire Kit recipe known (learned at Cooking 1)
function Camp.Cook(profs)
  return (profs or Camp.Professions()).Cooking ~= nil or knows(Camp.KIT_RECIPE)
end

-- your helpful auras by name: the stacks of one (Camp.Buffs), or what the game says of it (Camp.Auras: stacks, when
-- it runs out on GetTime's clock, its icon); Camp.Auras also gives their spell ids, each with what the game says of it
-- (true for one with no name). unit: "player" when nil; a third answer is true when the game hid an aura's name (a
-- secret value), so what is missing can't be told
-- (Camp.AurasInto: the same into tables kept, out and ids emptied by the caller, each aura's record from pool)
function Camp.AurasInto(unit, out, ids, pool)
  local hidden, used = false, 0
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if get then
    for i = 1, 60 do
      local ok, a = pcall(get, unit or "player", i, "HELPFUL")
      if not ok or type(a) ~= "table" then break end
      local n, id = plain(a.name), plain(a.spellId)
      if n == nil and issecretvalue and issecretvalue(a.name) then hidden = true end
      if type(id) == "number" and id > 0 then ids[id] = true end
      if type(n) == "string" then
        local exp = plain(a.expirationTime)
        local e
        if pool then used = used + 1; e = pool[used]; if not e then e = {}; pool[used] = e end else e = {} end
        e.n, e.exp, e.icon = plain(a.applications) or 1, type(exp) == "number" and exp > 0 and exp or nil, plain(a.icon)
        if type(id) == "number" and id > 0 then ids[id] = e end
        -- the Cozy Sleeping Bag's buff is 429959 "Well-Rested" (1.60.1.70338), with a hyphen; the Legacy perk's hidden
        -- passive 1225478 is "Well Rested" and is never the bag's. Either name counts when the id isn't the perk's
        local L = QB.Legacy
        local perk, bag = L and L.PERK_WELL_RESTED or 1225478, L and L.BAG_WELL_RESTED or 429959
        if id ~= perk then
          out[n] = e
          if id == bag or n == "Well-Rested" then out["Well Rested"] = e end
        end
      end
    end
  end
  return out, ids, hidden
end
function Camp.Auras(unit) return Camp.AurasInto(unit, {}, {}, nil) end
function Camp.Buffs()
  local out = {}
  for n, a in pairs(Camp.Auras()) do out[n] = a.n end
  return out
end

-- (asked from outside a refresh: the bags read now; a reminder's own read passes Remind's scan of this refresh)
local function carried() QB.Remind.BagsChanged(); return QB.Remind.Bags() end

-- the camp features you carry and can place: your profession's skill meets the item's
function Camp.Placeable(bags, profs)
  bags, profs = bags or carried(), profs or Camp.Professions()
  local out = {}
  for id, e in pairs(QB.Data.CAMP or {}) do
    if e.t == "feature" and bags[id] and e.p and (profs[e.p] or 0) >= (e.s or 0) then out[#out + 1] = { id = id, e = e } end
  end
  table.sort(out, function(a, b) return (a.e.s or 0) > (b.e.s or 0) or ((a.e.s or 0) == (b.e.s or 0) and a.e.n < b.e.n) end)
  -- a higher tier makes its base pointless: keep the best of each profession
  local best, seen = {}, {}
  for _, x in ipairs(out) do if not seen[x.e.p] then seen[x.e.p] = true; best[#best + 1] = x end end
  return best
end

-- the campfire kits you carry, the best first
function Camp.Kits(bags)
  bags = bags or carried()
  local out = {}
  for id, e in pairs(QB.Data.CAMP or {}) do if e.t == "kit" and bags[id] then out[#out + 1] = { id = id, e = e } end end
  table.sort(out, function(a, b) return (a.e.s or 0) > (b.e.s or 0) end)
  return out
end

-- the foods you carry that make you Well Fed
function Camp.Foods(bags)
  bags = bags or carried()
  local out = {}
  for id, e in pairs(QB.Data.FOOD or {}) do if bags[id] then out[#out + 1] = { id = id, e = e } end end
  table.sort(out, function(a, b) return a.e.n < b.e.n end)
  return out
end

-- how you can light a campfire now: { kit = Camp.Kits' first } or { spell = Basic Campfire }, or nil. A kit you carry
-- comes first, feature waiting or not: its fire is the one that holds camp features, and on Forever the kit is the
-- fire (Basic Campfire there is the recipe that makes it). The spell only when you carry no kit
function Camp.Fire(bags)
  local kit = Camp.Kits(bags)[1]
  if kit then return { kit = kit } end
  if knows(Camp.FIRE_SPELL) then return { spell = Camp.FIRE_SPELL } end
  return nil
end

----------------------------------------------------------------------------
-- sellers of camp goods, learned as you open merchants (QuestBankDB.disc.sell[npc key] = { n = its name, p = "uiMap:x,y",
-- c, wx, wy = where it stands, i = { the camp goods it sells }, at }): at most MAX_SELLERS, the longest unseen let go
----------------------------------------------------------------------------
local MAX_SELLERS = 60
Camp.MAX_SELLERS = MAX_SELLERS
-- a camp good: a campfire kit, Simple Wood, Flint and Tinder, the Cozy Sleeping Bag, a food that makes you Well Fed
-- (D.CAMP, D.FOOD)
local function campGood(id)
  if id == Camp.WOOD or id == Camp.FLINT or id == Camp.BAG then return true end
  local e = (QB.Data.CAMP or {})[id]
  if e and e.t == "kit" then return true end
  return (QB.Data.FOOD or {})[id] ~= nil
end
Camp.CampGood = campGood

local function sellDB(make)
  local Disc = QB.Discover
  local d = Disc and Disc.DB and Disc.DB()
  if not d then return nil end
  if make and type(d.sell) ~= "table" then d.sell = {} end
  return type(d.sell) == "table" and d.sell or nil
end
Camp.SellDB = sellDB

-- the merchant window open (MERCHANT_SHOW, and MERCHANT_UPDATE as its wares come in): its NPC, where it stands and the
-- camp goods it sells, noted; one that sells none (any more) let go
function Camp.NoteMerchant()
  if type(GetMerchantNumItems) ~= "function" or type(GetMerchantItemID) ~= "function" then return end
  local Disc = QB.Discover
  local key = Disc and Disc.Who and Disc.Who("npc")
  if not key then return end
  local ok, n = pcall(GetMerchantNumItems)
  n = ok and plain(n) or nil
  if type(n) ~= "number" then return end
  local items = {}
  for i = 1, math.min(n, 200) do
    local okI, id = pcall(GetMerchantItemID, i)
    id = okI and plain(id) or nil
    if type(id) == "number" and campGood(id) then items[#items + 1] = id end
  end
  local db = sellDB(#items > 0)
  if not db then return end
  if #items == 0 then db[key] = nil; return end
  table.sort(items)
  local me = QB.API.WorldPosition()
  if not me then return end
  local okN, name = pcall(UnitName, "npc")
  name = okN and plain(name) or nil
  db[key] = { n = type(name) == "string" and name ~= "" and name or nil, p = Disc.Here and Disc.Here() or nil,
              c = me.c, wx = math.floor(me.wx + 0.5), wy = math.floor(me.wy + 0.5), i = items, at = time and time() or 0 }
  local count, oldest = 0, nil
  for k, e in pairs(db) do
    count = count + 1
    if type(e) ~= "table" then db[k] = nil
    elseif not oldest or (e.at or 0) < (db[oldest].at or 0) then oldest = k end
  end
  if count > MAX_SELLERS and oldest then db[oldest] = nil end
end

-- the seed: D.CAMP_SELL's general goods vendors of your side, as sellers are kept ({ n, c, wx, wy, i, seed = true, key =
-- the NPC's key, m, x, y = its map and place on it }), made once a session
local seedList, seedFac
local function seed()
  local fac = QB.faction or (QB.API.Faction and QB.API.Faction())
  if seedList and seedFac == fac then return seedList end
  seedList, seedFac = {}, fac
  local side = fac == "A" and 1 or fac == "H" and 2 or 0
  for _, r in ipairs(QB.Data.CAMP_SELL or {}) do
    if side > 0 and r[10] % (side * 2) >= side then
      local i = {}
      if r[9] % 2 == 1 then i[#i + 1] = Camp.WOOD end
      if r[9] >= 2 then i[#i + 1] = Camp.FLINT end
      seedList[#seedList + 1] = { n = r[2], c = r[3], wx = r[4], wy = r[5], m = r[6], x = r[7], y = r[8], i = i, seed = true, key = "c" .. r[1] }
    end
  end
  return seedList
end
Camp.Seed = seed

-- The nearest seller of the items in want (a set) on your land: the seller and its minutes away (by your flight paths
-- and boats where the arrow's router knows the way, else on foot as the crow flies), or nil. A seller of every item
-- in all (a list, optional) comes before one of some of them. Sellers your games have seen; with seeded also the seed's
-- (D.CAMP_SELL), each counting its minutes half again and one more (Classic data: it may have moved), so a seller seen
-- in play wins at about the same distance; a seed seller a game has seen is the one seen
function Camp.NearestSeller(want, all, seeded)
  local db = sellDB(false)
  if not (db or seeded) then return nil end
  local me = QB.API.WorldPosition()
  if not me then return nil end
  local TV, R = QB.Travel, nil
  local walk = QB.Model.DETOUR / QB.Model.RUN / 60
  local best, bm, bScore, bMiss
  local function look(e)
    if type(e) ~= "table" or e.c ~= me.c or type(e.wx) ~= "number" or type(e.wy) ~= "number" then return end
    local sells, miss = false, 0
    for _, id in ipairs(e.i or {}) do if want[id] then sells = true end end
    if not sells then return end
    for _, id in ipairs(all or {}) do
      local has = false
      for _, x in ipairs(e.i or {}) do if x == id then has = true end end
      if not has then miss = miss + 1 end
    end
    local m
    if TV and TV.Reach and TV.Via then
      if R == nil then local okR, r = pcall(TV.Reach, me, TV.Opts("pin")); R = okR and r or false end
      if R then local okV, v = pcall(TV.Via, R, e); if okV then m = v end end
    end
    if not m or m == math.huge then m = math.sqrt((e.wx - me.wx) ^ 2 + (e.wy - me.wy) ^ 2) * walk end
    local score = e.seed and (m * 1.5 + 1) or m
    if not best or miss < bMiss or (miss == bMiss and score < bScore) then best, bm, bScore, bMiss = e, m, score, miss end
  end
  for _, e in pairs(db or {}) do look(e) end
  if seeded then
    for _, e in ipairs(seed()) do
      if not (db and db[e.key]) then look(e) end
    end
  end
  return best, bm
end

Camp.SEED_NOTE = "Classic data, may have moved."

-- a seller shown on the arrow for now, an optional detour: it ends once the item is in your bags (every one of a list
-- of items) or you get there, and the arrow is back on your route (Arrow.lua's A:Show)
function Camp.GoTo(e, item)
  if not (e and QB.Arrow) then return false end
  local about = type(item) == "table" and { items = item } or { item = item }
  return QB.Arrow:Show(e.n or "A merchant", { c = e.c, wx = e.wx, wy = e.wy }, about)
end

-- the class's own buffs (Camp.SELF): the spell of an entry that is on you (true for one of its also names), or nil
local EMPTY = {}
local function selfOn(entry, names, ids)
  for _, sp in ipairs(entry) do
    if names[sp[1]] or names[spellName(sp[3][1], sp[1])] then return sp end
    for _, id in ipairs(sp[3]) do if ids[id] then return sp end end
  end
  for _, id in ipairs(entry.alsoIds or EMPTY) do if ids[id] then return true end end
  for _, n in ipairs(entry.also or EMPTY) do if names[n] then return true end end
  return nil
end
local seen = {} -- [class .. entry] = the spell last seen on you of an entry with a choice (this session)
local function myClass()
  local ok, _, class = pcall(UnitClass, "player")
  class = ok and plain(class) or nil
  return type(class) == "string" and class or nil
end
local function noteSelf(names, ids)
  local class = myClass()
  for i, entry in ipairs(Camp.SELF[class] or {}) do
    if #entry > 1 then
      local sp = selfOn(entry, names, ids)
      if type(sp) == "table" then seen[class .. i] = sp[1] end
    end
  end
end
-- the spell to cast for an entry: the one last seen on you first, then in Camp.SELF's order, the highest rank you know;
-- { id, name, icon } or nil
local castBuf = {} -- (one answer an entry, kept: the same spell for you and a party member)
local function castFor(class, i, entry)
  local last = seen[class .. i]
  for pass = 1, 2 do
    for _, sp in ipairs(entry) do
      if (pass == 1) == (sp[1] == last) then
        for r = #sp[3], 1, -1 do
          local id = sp[3][r]
          if knows(id) then
            local c = castBuf[i]
            if not c then c = {}; castBuf[i] = c end
            c.id, c.name, c.icon, c.first = id, spellName(id, sp[1]), sp[2], sp[3][1]
            return c
          end
        end
      end
    end
  end
  return nil
end
-- the class's buffs you know and don't have on: { id = the highest rank you know, name, icon, first = its first rank },
-- in Camp.SELF's order. other: only those that can be cast on another player (for a party member's auras); tank: that
-- member is the tank (Thorns is offered to the tank alone)
function Camp.SelfMissing(names, ids, other, tank, into)
  local class, out = myClass(), into or {}
  for k = #out, 1, -1 do out[k] = nil end
  for i, entry in ipairs(Camp.SELF[class] or {}) do
    if (entry.other or not other) and not (other and entry.tank and not tank) and not selfOn(entry, names, ids) then
      local sp = castFor(class, i, entry)
      if sp then out[#out + 1] = sp end
    end
  end
  return out
end


----------------------------------------------------------------------------
-- the reminders: providers of Remind.lua
----------------------------------------------------------------------------
local R = QB.Remind
local ART = QB.ART or "Interface\\AddOns\\QuestBank\\art\\" -- (a host holding a copy of the engine names its own folder: QB.ART)
Camp.SNOOZE = R.SNOOZE
Camp.STILL = R.STILL
-- the Well Fed auras (SpellName.csv, 1.60.1.70338: the thirty named "Well Fed", and Forever's Well Fed XP Boost); a
-- localised client is matched by the client's own name of one (C_Spell.GetSpellName(1248422))
Camp.WELL_FED = { [19705] = true, [19706] = true, [19708] = true, [19709] = true, [19710] = true, [19711] = true, [24799] = true,
  [24870] = true, [25694] = true, [25941] = true, [1225778] = true, [1225779] = true, [1225780] = true, [1225782] = true,
  [1248406] = true, [1248420] = true, [1248421] = true, [1248422] = true, [1248688] = true, [1249519] = true, [1249520] = true,
  [1249521] = true, [1249523] = true, [1249907] = true, [1249926] = true, [1249927] = true, [1283082] = true, [1294007] = true,
  [1302064] = true, [1319310] = true, [1243969] = true }
Camp.FED_NAME_SPELL = 1248422
Camp.BAG_BUFF = 429959 -- Well-Rested, the Cozy Sleeping Bag's (the Legacy perk's hidden 1225478 is never it)
Camp.COOKING = { 18260, 3413, 3102, 2550 } -- Cooking's ranks, the highest first: its spell opens the game's crafting window

-- your auras read once a refresh into tables kept (names, ids): no table made per look
local myNames, myIds, myPool = {}, {}, {}
local function readMine()
  for k in pairs(myNames) do myNames[k] = nil end
  for k in pairs(myIds) do myIds[k] = nil end
  return Camp.AurasInto("player", myNames, myIds, myPool)
end
local function fed(names, ids)
  for id in pairs(Camp.WELL_FED) do if ids[id] then return true end end
  if names["Well Fed"] then return true end
  local n = spellName(Camp.FED_NAME_SPELL, nil)
  return n ~= nil and names[n] ~= nil
end
Camp.Fed = fed
local function isMounted() return R.Yes(IsMounted) end
local function charDB()
  QuestBankDB = QuestBankDB or {}
  QuestBankDB.chars = QuestBankDB.chars or {}
  local key = QB:CharKey()
  local c = QuestBankDB.chars[key]
  if type(c) ~= "table" then c = {}; QuestBankDB.chars[key] = c end
  if type(c.remind) ~= "table" then c.remind = {} end
  return c.remind
end
Camp.CharDB = charDB
-- what the account learned (meals that gave Well Fed or did not): QuestBankDB.remind, kept on this computer
local function acctDB()
  QuestBankDB = QuestBankDB or {}
  if type(QuestBankDB.remind) ~= "table" then QuestBankDB.remind = {} end
  return QuestBankDB.remind
end
Camp.AcctDB = acctDB
local function count(id)
  local get = C_Item and C_Item.GetItemCount or GetItemCount
  if type(get) ~= "function" then return 0 end
  local ok, n = pcall(get, id)
  n = ok and plain(n) or 0
  return type(n) == "number" and n or 0
end
Camp.Count = count
local function itemCD(id)
  local get = C_Container and C_Container.GetItemCooldown
  if not (get and id) then return 0, 0 end
  local ok, start, dur = pcall(get, id)
  start, dur = ok and plain(start) or 0, ok and plain(dur) or 0
  if type(start) ~= "number" or type(dur) ~= "number" or dur <= 1.5 then return 0, 0 end
  return start, dur
end
Camp.ItemCD = itemCD
local function itemTex(e, fallback) return (e and e.i) and ("Interface\\Icons\\" .. e.i) or fallback end
local function level() return QB.state and QB.state.level or 1 end

----------------------------------------------------------------------------
-- the fire you lit, and the camp features' hour
----------------------------------------------------------------------------
local litAt, campAt -- your kit's fire lit (GetTime), a feature placed
-- the spells a kit or a camp feature casts, to know one was used (UNIT_SPELLCAST_SUCCEEDED); Basic Campfire too
local KIT, FEATURE = {}, {}
function Camp.CampCooldown(best, t)
  local start, dur = itemCD(best.id)
  local cd = Camp.CampCD()
  if dur == 0 and campAt and t - campAt < cd then start, dur = campAt, cd end
  if dur > 0 and start + dur - t <= 0 then return 0, 0 end
  return start, dur
end
function Camp.CooldownLeft()
  if not campAt then return 0 end
  return math.max(0, Camp.CampCD() - (now() - campAt))
end
-- "All camp features share an hour's cooldown.", shorter with Field Guide
function Camp.CooldownText()
  local cd = Camp.CampCD()
  if cd >= CAMP_CD then return "All camp features share an hour's cooldown." end
  return string.format("All camp features share a %d-minute cooldown (Field Guide).", math.floor(cd / 60 + 0.5))
end
function Camp.LitAt() return litAt end
function Camp.IsCampBuff(name)
  for _, e in pairs(QB.Data.CAMP or {}) do if e.t == "feature" and e.n == name then return true end end
  return false
end

----------------------------------------------------------------------------
-- the Cooking Fire objects (CMaNGOS Classic's gameobject_template, GPL-3.0: type 8, a spell focus, focus 4 "Cooking
-- Fire" of the client's SpellFocusObject.csv; those with a spawn on the two continents), as runs of entries
----------------------------------------------------------------------------
local FIRE_RUNS = "1766,1798-1799,1801-1822,1824-1860,1864-1895,1898,1901-1906,1908-1909,1911-1912,1914-1917,1922-1923,1926,1928,1930-1932,1936-1941,1943-1954,1957-1962,1964,1967,1969-1973,1975-1977,1979,1981,1984-2007,2056-2057,2062,2334-2336,2658,2661,2663-2667,2719,2732,3084-3085,3089,3200,3220,3246,3249,3251-3254,3256,3258,3260,3262,3264,3266,3270,3286,3296,3298,3301,3303,3306-3308,3310-3311,3315,3636-3639,3656,3716-3718,3722-3723,3760-3761,3769-3770,3772,3797-3804,3815-3819,3839-3845,3847-3853,3855-3857,3888,3890-3911,3937,3943,3945,3951,3960,3962-3964,3967-3968,6286-6292,9847,10388,12665,15068-15069,17284"
Camp.FIRE_RUNS = FIRE_RUNS
local fireLo, fireHi
local function isCookingFire(entry)
  if not fireLo then
    fireLo, fireHi = {}, {}
    for a, b in FIRE_RUNS:gmatch("(%d+)%-?(%d*)") do
      fireLo[#fireLo + 1] = tonumber(a)
      fireHi[#fireHi + 1] = tonumber(b ~= "" and b or a)
    end
  end
  local lo, hi = 1, #fireLo
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    if entry < fireLo[mid] then hi = mid - 1 elseif entry > fireHi[mid] then lo = mid + 1 else return true end
  end
  return false
end
Camp.IsCookingFire = isCookingFire
-- the object under your Interact key, a Cooking Fire, its entry (from its GUID, any language), while the client lets
-- its identity be read (C_Secrets.ShouldUnitIdentityBeSecret, SecretPredicateAPIDocumentation.lua:305)
local softFire = { entry = nil, at = nil }
local givesNothing = {} -- (this session: an entry a /sit by gave no Welcoming Campfire)
local sitAt
local function readSoft()
  softFire.entry, softFire.at = nil, nil
  local S = C_Secrets
  if S and type(S.ShouldUnitIdentityBeSecret) == "function" and R.Yes(S.ShouldUnitIdentityBeSecret, "softinteract") then return end
  local ok, guid = pcall(UnitGUID, "softinteract")
  guid = ok and plain(guid) or nil
  if type(guid) ~= "string" or not guid:find("^GameObject") then return end
  local entry = tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
  if entry and isCookingFire(entry) and not givesNothing[entry] then softFire.entry, softFire.at = entry, now() end
end
Camp.SoftFire = softFire
-- (a diagnostic for the live client, section 11: what a fire under your Interact key puts on you, kept in
-- QuestBankDB.diag.remind.fire: its entry, whether Campfire Nearby was on, and Welcoming Campfire after a /sit)
local function diagFire(key, v)
  QuestBankDB = QuestBankDB or {}
  QuestBankDB.diag = type(QuestBankDB.diag) == "table" and QuestBankDB.diag or {}
  local d = type(QuestBankDB.diag.remind) == "table" and QuestBankDB.diag.remind or {}
  QuestBankDB.diag.remind = d
  local f = type(d.fire) == "table" and d.fire or {}
  d.fire = f
  f[key] = v
end
Camp.Diag = diagFire

----------------------------------------------------------------------------
-- meals: which foods give Well Fed (D.FOOD, generated from the items' own Use lines), and the ones learned in play: a
-- meal from your bags followed by Well Fed keeps that food (acctDB().food[id] = true), one that ends without it drops it
-- (false); 200 kept at most
----------------------------------------------------------------------------
local MEAL = { Food = true, Drink = true, ["Food & Drink"] = true, Refreshment = true }
local meal -- { id, at }: the food you started on (its spell cast)
local itemSpell = {} -- [item id] = its spell id, or false (C_Item.GetItemSpell, read once)
local function spellOf(id)
  local v = itemSpell[id]
  if v ~= nil then return v or nil end
  v = false
  if C_Item and type(C_Item.GetItemSpell) == "function" then
    local ok, _, sp = pcall(C_Item.GetItemSpell, id)
    sp = ok and plain(sp) or nil
    if type(sp) == "number" then v = sp end
  end
  itemSpell[id] = v
  return v or nil
end
Camp.ItemSpell = spellOf
local function eating(names)
  for n in pairs(MEAL) do if names[n] then return true end end
  return false
end
Camp.Eating = eating
local function foodOK(id)
  local learned = acctDB().food
  local v = type(learned) == "table" and learned[id] or nil
  if v ~= nil then return v end
  return (QB.Data.FOOD or {})[id] ~= nil
end
local function sellPrice(id)
  local get = C_Item and C_Item.GetItemInfo or GetItemInfo
  if type(get) ~= "function" then return 0 end
  local ok, _, _, _, _, _, _, _, _, _, _, price = pcall(get, id)
  price = ok and plain(price) or nil
  return type(price) == "number" and price or 0
end
-- the food to eat now: the cheapest you carry that gives Well Fed (before a pull the best, by item level)
function Camp.BestFood(best)
  local bags = R.Bags()
  local pick, pv
  for id in pairs(bags) do
    if foodOK(id) then
      local v
      if best then
        local _, _, _, ilvl = (C_Item and C_Item.GetItemInfo or GetItemInfo)(id)
        v = -(tonumber(plain(ilvl)) or 0)
      else
        v = sellPrice(id)
      end
      if not pv or v < pv or (v == pv and id < pick) then pick, pv = id, v end
    end
  end
  return pick
end
local function learnFood(id, gave)
  local db = acctDB()
  if type(db.food) ~= "table" then db.food = {} end
  local n = 0
  for _ in pairs(db.food) do n = n + 1 end
  if n >= 200 and db.food[id] == nil then return end
  db.food[id] = gave
end
-- a meal started (its spell from a food you carry), and how it ended: Well Fed while it lasted, or the meal over
local function onCast(_, unit, _, spell)
  if plain(unit) ~= "player" then return end
  local sp = plain(spell)
  if type(sp) ~= "number" then return end
  local e = KIT[sp]
  if e and e ~= true then
    litAt = now()
    charDB().kitUsed = true
  end
  if FEATURE[sp] then campAt = now() end
  if sp == Camp.FIRE_SPELL then litAt = litAt or now() end
  for id in pairs(R.Bags()) do
    if spellOf(id) == sp then
      local okI, _, _, _, _, _, classID, subID = pcall(C_Item.GetItemInfoInstant, id)
      if okI and plain(classID) == 0 and plain(subID) == 5 then meal = { id = id, at = now() } end
      break
    end
  end
end
local function watchMeal(names, ids)
  if not meal then return end
  -- (the live client's word, section 11: which meals give Forever's Well Fed XP Boost, applied by the server)
  if ids[1243969] then R.Diag("fedBoost", meal.id) end
  if fed(names, ids) then learnFood(meal.id, true); meal = nil return end
  if not eating(names) and now() - meal.at > 3 then learnFood(meal.id, false); meal = nil end
end

----------------------------------------------------------------------------
-- learned buffs, by habit (per character, 8 at most): an aura you cast on yourself (sourceUnit "player") lasting 10
-- minutes or more, a spell you know, not of Camp.SELF, joins once you recast it within 2 minutes of it running out
-- on two separate occasions, and is forgotten after two lapses you did not recast. One swim never teaches Water
-- Breathing. Never the tanking toggles (Righteous Fury: a wrong cast hurts)
----------------------------------------------------------------------------
Camp.NEVER_LEARN = { [25780] = true, [407627] = true }
local HABIT_MIN, HABIT_WINDOW, HABIT_MAX = 600, 120, 8
local onMine = {} -- [spell id] = its expiry, while on you (this session)
local ranOut = {} -- [spell id] = when it ran out
local selfIds -- every rank and group version of Camp.SELF's, by id
local function selfIdSet()
  if selfIds then return selfIds end
  selfIds = {}
  for _, list in pairs(Camp.SELF) do
    for _, entry in ipairs(list) do
      for _, sp in ipairs(entry) do for _, id in ipairs(sp[3]) do selfIds[id] = true end end
      for _, id in ipairs(entry.alsoIds or {}) do selfIds[id] = true end
    end
  end
  return selfIds
end
local function habits()
  local db = charDB()
  if type(db.habit) ~= "table" then db.habit = {} end
  return db.habit
end
Camp.Habits = habits
-- what your own long auras did since the last look: one that ran out, one cast again within the 2 minutes
local function watchHabits(mine)
  local t = now()
  local h = habits()
  for id, exp in pairs(onMine) do
    if not mine[id] then
      onMine[id] = nil
      ranOut[id] = t
    end
  end
  for id, exp in pairs(mine) do
    if not onMine[id] then
      onMine[id] = exp
      local out = ranOut[id]
      ranOut[id] = nil
      if out and t - out <= HABIT_WINDOW then
        local e = h[id]
        if type(e) ~= "table" then
          local n = 0
          for _ in pairs(h) do n = n + 1 end
          if n < HABIT_MAX * 2 then e = { hits = 0, miss = 0 }; h[id] = e end
        end
        if e then e.hits, e.miss = (e.hits or 0) + 1, 0 end
      end
    end
  end
  -- (two lapses not cast again: forgotten)
  for id, out in pairs(ranOut) do
    if t - out > HABIT_WINDOW then
      ranOut[id] = nil
      local e = h[id]
      if type(e) == "table" then
        e.miss = (e.miss or 0) + 1
        if e.miss >= 2 then h[id] = nil end
      end
    end
  end
end
Camp.WatchHabits = watchHabits
local myLong = {} -- [spell id] = expiry: your own auras of 10 minutes or more now, a spell you know (the habit's candidates)
local function readLong()
  for k in pairs(myLong) do myLong[k] = nil end
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not get then return myLong end
  local ids = selfIdSet()
  for i = 1, 60 do
    local ok, a = pcall(get, "player", i, "HELPFUL")
    if not ok or type(a) ~= "table" then break end
    local id, src, dur, exp = plain(a.spellId), plain(a.sourceUnit), plain(a.duration), plain(a.expirationTime)
    if type(id) == "number" and src == "player" and type(dur) == "number" and dur >= HABIT_MIN and dur <= 7200
      and not ids[id] and not Camp.NEVER_LEARN[id] and knows(id) then
      myLong[id] = type(exp) == "number" and exp or 0
    end
  end
  return myLong
end
-- the buffs your habits taught: { id, name, icon } each, those you know and lack now
local learnedBuf, learnedPool = {}, {}
function Camp.Learned(ids)
  local out = learnedBuf
  for k = #out, 1, -1 do out[k] = nil end
  for id, e in pairs(habits()) do
    if type(e) == "table" and (e.hits or 0) >= 2 and not ids[id] and knows(id) and #out < HABIT_MAX then
      local r = learnedPool[#out + 1]
      if not r then r = {}; learnedPool[#out + 1] = r end
      r.id, r.name, r.icon = id, spellName(id, "Buff"), spellIcon(id, 134400)
      out[#out + 1] = r
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- the sleeping bag's quest chain (D.SLEEP_CHAIN) for your side, made once a session: the first step is one quest a
-- side (id, alt: either counts), at your side's place
local sleepSteps, sleepFac
function Camp.SleepSteps()
  local fac = QB.faction or (QB.API.Faction and QB.API.Faction())
  if sleepSteps and sleepFac == fac then return sleepSteps end
  sleepSteps, sleepFac = {}, fac
  for i, step in ipairs(QB.Data.SLEEP_CHAIN or {}) do
    local p = (fac and step[fac]) or step
    sleepSteps[i] = { id = step.id, alt = step.alt, name = step.name, where = p.where, m = p.m, x = p.x, y = p.y }
  end
  return sleepSteps
end
-- a step done (or a later step of its chain held or done), and in your log
function Camp.StepDone(step)
  local API, Q = QB.API, QB.Quest
  if API.IsDone(step.id) or (step.alt and API.IsDone(step.alt)) then return true end
  return Q.Behind(step.id) ~= nil or (step.alt ~= nil and Q.Behind(step.alt) ~= nil)
end
function Camp.StepHeld(step, log)
  log = log or (QB.state and QB.state.log) or {}
  return log[step.id] ~= nil or (step.alt ~= nil and log[step.alt] ~= nil)
end
-- the chain's next step: the first one in your log, else the first not done (nil once all are), whether you hold it,
-- how many are done, and of how many
function Camp.SleepNext()
  local steps = Camp.SleepSteps()
  local nextStep, held, done = nil, false, 0
  for _, step in ipairs(steps) do
    local d = Camp.StepDone(step)
    if d then done = done + 1 end
    if not nextStep or not held then
      if Camp.StepHeld(step) then nextStep, held = step, true
      elseif not d and not nextStep then nextStep = step end
    end
  end
  return nextStep, held, done, #steps
end

----------------------------------------------------------------------------
-- the providers
----------------------------------------------------------------------------
local KIT_GOODS = { [4470] = true, [4471] = true }
local WOOD_ONLY, FLINT_ONLY, BOTH = { 4470 }, { 4471 }, { 4470, 4471 }
local RIX = "Rix Xizzix, Booty Bay"
Camp.RIX = RIX
local readMineAt -- (the auras read once a refresh: the first provider reads them, the rest reuse them)
local mineHidden = false
local function mine(ctx)
  if readMineAt ~= R.refreshes then
    readMineAt = R.refreshes
    local _, _, hidden = readMine()
    mineHidden = hidden
    watchMeal(myNames, myIds)
    watchHabits(readLong())
    noteSelf(myNames, myIds)
    R.WatchFlasks(myIds)
  end
  return myNames, myIds, mineHidden
end
Camp.Mine = mine
local function outside(ctx) return not ctx.town and not ctx.inst end

-- sit: by a fire, sit a minute (Welcoming Campfire), then Camp Benefits for an hour
R.Add({ key = "sit", neverName = "Sit", piece = "reminders", order = 10, row = "camp", cat = "xp", groups = { "buffs", "camp" }, timed = true,
  read = function(add, ctx)
    local names, ids = mine(ctx)
    if ids[Camp.BENEFITS] or isMounted() then return end
    local wel
    for id in pairs(Camp.WELCOME) do if ids[id] then wel = ids[id] end end
    local near = ids[Camp.NEARBY]
    if wel then
      if sitAt and softFire.entry then diagFire("welcome", softFire.entry) end
      sitAt = nil
      local left = type(wel) == "table" and wel.exp and math.max(0, wel.exp - ctx.t) or nil
      local rec = add()
      rec.tex, rec.lit = (type(wel) == "table" and wel.icon) or (type(near) == "table" and near.icon) or itemTex((QB.Data.CAMP or {})[Camp.BASIC_KIT], 135805), true
      rec.word = left and string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60)) or "Sit"
      rec.timed = left ~= nil
      R.Click(rec, "macro", "/sit")
      rec.name, rec.why, rec.clickWord = "Welcoming Campfire", "Stay put: Camp Benefits once the minute is up.", "sit down again"
      return
    end
    local soft = not near and softFire.entry and softFire.at and ctx.t - softFire.at < 15
    if sitAt and softFire.entry and ctx.t - sitAt >= 10 then
      -- (a /sit by that object brought no Welcoming Campfire: it gives nothing, for the session)
      givesNothing[softFire.entry] = true
      diagFire("nothing", softFire.entry)
      softFire.entry, sitAt, soft = nil, nil, false
    end
    if not (near or soft) then return end
    local rec = add()
    rec.tex = (type(near) == "table" and near.icon) or itemTex((QB.Data.CAMP or {})[Camp.BASIC_KIT], 135805)
    rec.lit, rec.word = true, "Sit"
    R.Click(rec, "macro", "/sit") -- (the game's own slash command, as a macro of yours: SitStandOrDescendStart is restricted, PlayerScriptDocumentation.lua:1772)
    rec.name, rec.why, rec.clickWord = "Sit by the fire", "A minute sitting by it gives Camp Benefits for an hour: the buffs of its camp features.", "sit down"
  end,
  used = function() if softFire.entry then sitAt = now() end end,
})

-- place: a camp feature by your own kit's fire (a kit's fire is the one that holds camp features)
R.Add({ key = "place", neverName = "Place", piece = "reminders", order = 20, row = "camp", cat = "xp", groups = { "buffs", "camp" },
  read = function(add, ctx)
    if not (litAt and ctx.t - litAt < 300) then return end
    local names, ids = mine(ctx)
    local best
    for _, x in ipairs(Camp.Placeable(R.Bags())) do
      if x.e.b and not (ids[x.e.b] or names[x.e.bn or ""] or names[spellName(x.e.b, x.e.bn or "")]) then best = x; break end
    end
    if not best then return end
    local st, du = Camp.CampCooldown(best, ctx.t)
    if du > 0 then return end
    local rec = add()
    rec.tex, rec.lit, rec.word = itemTex(best.e, 134400), true, "Place"
    R.Click(rec, "item", best.id)
    rec.name, rec.why, rec.clickWord = best.e.n, (best.e.g or "Its buff") .. " while you sit by it. " .. Camp.CooldownText(), "place it"
  end,
})

-- the fire slot: Light, Make, Wood or Cook
local profBuf = {}
local function cookSpell()
  for _, id in ipairs(Camp.COOKING) do if knows(id) then return id end end
  return nil
end
local function kitCarried()
  local bags = R.Bags()
  local best, be
  for id, e in pairs(QB.Data.CAMP or {}) do
    if e.t == "kit" and bags[id] and (not be or (e.s or 0) > (be.s or 0)) then best, be = id, e end
  end
  return best, be
end
Camp.KitCarried = kitCarried
local function cookTrainer(me)
  local disc = QB.Discover and QB.Discover.DB and QB.Discover.DB()
  local best, bm
  for _, t in pairs(disc and disc.trainer or EMPTY) do
    if type(t) == "table" and t.p == "Cooking" and t.m and t.x and t.y then
      local w = QB.Model.World(t.m, t.x, t.y)
      local m = w and R.Minutes(me, w)
      if m and (not bm or m < bm) then best, bm = { name = t.n or "Cooking trainer", c = w.c, wx = w.wx, wy = w.wy }, m end
    end
  end
  return best, bm
end
Camp.CookTrainer = cookTrainer
R.Add({ key = "fire", neverName = "Campfire", piece = "reminders", order = 30, row = "camp", cat = "xp", groups = { "buffs", "camp" }, timed = true,
  read = function(add, ctx)
    local names, ids = mine(ctx)
    if ids[Camp.BENEFITS] or ids[Camp.NEARBY] or ctx.inst then return end
    local moment = R.still and not ctx.town
    local kit, ke = kitCarried()
    local profs = Camp.Professions(profBuf)
    local cook = Camp.Cook(profs)
    local wood, flint = count(Camp.WOOD) > 0, count(Camp.FLINT) > 0
    local rec
    if moment and kit then
      rec = add()
      rec.tex, rec.lit, rec.word, rec.count = itemTex(ke, 134400), true, "Light", count(kit)
      R.Click(rec, "item", kit)
      rec.name, rec.why, rec.clickWord = ke.n, string.format("Holds %d camp feature%s, and its fire gives Camp Benefits.", ke.cap or 3, (ke.cap or 3) == 1 and "" or "s"), "light it"
    elseif moment and knows(Camp.FIRE_SPELL) and wood and select(2, spellCD(Camp.FIRE_SPELL)) == 0 then
      -- (Classic Era's cooks: Basic Campfire from Simple Wood)
      rec = add()
      rec.tex, rec.lit, rec.word, rec.count = spellIcon(Camp.FIRE_SPELL, Camp.FIRE_ICON), true, "Light", count(Camp.WOOD)
      R.Click(rec, "spell", Camp.FIRE_SPELL)
      rec.name, rec.why, rec.clickWord = spellName(Camp.FIRE_SPELL, "Basic Campfire"), "Lights a campfire from one Simple Wood.", "light it"
    elseif moment and wood and flint and knows(Camp.KIT_RECIPE) and cookSpell() then
      local e = (QB.Data.CAMP or {})[Camp.BASIC_KIT]
      rec = add()
      rec.tex, rec.lit, rec.word = itemTex(e, 134400), true, "Make"
      R.Click(rec, "spell", cookSpell())
      rec.name, rec.why, rec.clickWord = "Basic Campfire Kit", "You carry Simple Wood and Flint and Tinder: make one in your Cooking window.", "open Cooking"
    elseif cook and charDB().kitUsed and not kit and not (wood and flint) then
      local need = (not wood and not flint) and BOTH or (wood and FLINT_ONLY or WOOD_ONLY)
      local e, m = Camp.NearestSeller(KIT_GOODS, need, true)
      if e and m <= 10 and (moment or (ctx.town and m <= 2)) then
        rec = add()
        rec.key, rec.never, rec.neverName = "fire", "wood", "Wood"
        rec.tex, rec.lit, rec.word, rec.timed = "Interface\\Icons\\inv_tradeskillitem_01", false, R.MinWord(m), true
        rec.go = function() Camp.GoTo(e, need) end
        rec.name = "Simple Wood"
        rec.why = ((not wood and not flint) and "A Basic Campfire Kit takes Simple Wood and Flint and Tinder: you have neither. "
          or (wood and "You have no Flint and Tinder. " or "You have no Simple Wood. "))
          .. string.format("%s sells %s, %s.", e.n or "A merchant you have seen", #need == 2 and "both" or "it", R.MinWord(m)) .. (e.seed and (" " .. Camp.SEED_NOTE) or "")
        rec.clickWord = "show the seller on the arrow"
      end
    elseif not cook and level() >= 5 then
      local db = charDB()
      local first = db.cookAt
      if first and (time and time() or 0) - first > 600 then return end
      local t, m = cookTrainer(ctx.me)
      if not (moment or (ctx.town and m and m <= 2)) then return end
      if not first then db.cookAt = time and time() or 0 end
      local e = (QB.Data.CAMP or {})[Camp.BASIC_KIT]
      rec = add()
      rec.key, rec.never, rec.neverName = "fire", "cook", "Cook"
      rec.tex, rec.lit, rec.word = itemTex(e, 134400), false, "Cook"
      if t then rec.go = { name = t.name, c = t.c, wx = t.wx, wy = t.wy }; rec.clickWord = "show the cooking trainer on the arrow" end
      rec.name, rec.why = "Campfire kits", "Cooks make campfire kits: Basic Campfire Kit at Cooking 1."
    end
    if rec and moment then rec.pause = true end
  end,
})

-- eat: not Well Fed, out of towns and instances: the cheapest food you carry that gives it
local lastMeal
R.Add({ key = "eat", neverName = "Eat", piece = "reminders", order = 40, row = "camp", cat = "xp", groups = { "buffs", "camp" },
  read = function(add, ctx)
    local names, ids = mine(ctx)
    if fed(names, ids) or not outside(ctx) then lastMeal = nil return end
    local id = Camp.BestFood(false)
    -- (the last piece eaten: its icon stays through the meal, until Well Fed)
    if not id and lastMeal and eating(names) then id = lastMeal end
    if not id then return end
    local e = (QB.Data.FOOD or {})[id]
    local rec = add()
    rec.tex = itemTex(e, (C_Item and C_Item.GetItemIconByID and plain(select(2, pcall(C_Item.GetItemIconByID, id)))) or 133945)
    rec.lit, rec.word, rec.count = true, "Eat", count(id)
    R.Click(rec, "item", id)
    rec.name = e and e.n or "Food"
    rec.why = (e and foodText(e.g or "Well Fed") or "Well Fed") .. ": Well Fed adds XP on Forever."
    rec.clickWord = "eat it"
  end,
  used = function(rec) lastMeal = rec.click and rec.click.item end,
})

-- sleep: the Cozy Sleeping Bag, standing still out of town, under three stacks of Well-Rested
R.Add({ key = "sleep", neverName = "Sleeping bag", piece = "reminders", order = 50, row = "camp", cat = "xp", groups = { "buffs", "camp" },
  read = function(add, ctx)
    if not (R.Bags()[Camp.BAG] and R.still and outside(ctx)) then return end
    local names, ids = mine(ctx)
    local r = ids[Camp.BAG_BUFF]
    local stacks = (type(r) == "table" and r.n) or (names["Well Rested"] and names["Well Rested"].n) or 0
    if stacks >= 3 then return end
    local st, du = itemCD(Camp.BAG)
    if du > 0 and st + du > ctx.t then return end
    local rec = add()
    rec.tex, rec.lit, rec.word, rec.count = itemTex((QB.Data.CAMP or {})[Camp.BAG], 133662), true, "Sleep", stacks
    R.Click(rec, "item", Camp.BAG)
    rec.name, rec.why, rec.clickWord = "Cozy Sleeping Bag", string.format("Well-Rested %d/3: a minute in the bag adds a stack of bonus XP.", stacks), "unfurl it"
    rec.pause = true
  end,
})

-- the bag's quest chain: the step frame's line from level 14, one step at a time (the written exception to the
-- secrets research's "never shown until found", 2026-10-21-forever-secrets-research.md:10-11: the owner asked for it)
-- (the chain's step as last worked out: its place, words and the arrow's spot, made again only for another step)
Camp.ChainPlace = function(step, held)
  local qid = step.id
  if step.alt then
    local log, q = QB.state and QB.state.log or {}, QB.Quest.Get(step.id)
    if log[step.alt] or (not log[step.id] and not (q and QB.Quest.ForMe(q))) then qid = step.alt end
  end
  local m, x, y, where = step.m, step.x, step.y, step.where
  local q = held and QB.Quest.Get(qid)
  if q and q.turn and q.turn.m and q.turn.m > 0 and not q.turn.inside then m, x, y, where = q.turn.m, q.turn.x, q.turn.y, q.turn.n end
  local p = m and QB.Model.World(m, x, y)
  local place = (where or step.name):match("^([^,]+)") or step.name
  return { qid = qid, where = where, place = place, m = m, x = x, y = y,
           go = p and { name = place, c = p.c, wx = p.wx, wy = p.wy, about = { qid = qid, what = held and "turn" or "give" } } or nil,
           text = p and ("Sleeping bag: " .. place) or ("Sleeping bag: " .. RIX), -- (the line's words fit the step frame; the tooltip names the Cozy Sleeping Bag)
           why = (p and (held and (step.name .. " is in your log.") or (step.name .. " starts here.")) or "Its last step: where the bag's note points.")
             .. " A minute in the bag: +1% XP from kills and quests, up to 3%." }
end
local chainFor, chainHeld, chainLog, chainAt
R.Add({ key = "bagchain", neverName = "Sleeping bag quests", piece = "step", order = 230, row = "camp", cat = "xp", groups = { "camp", "class" }, timed = true,
  read = function(add, ctx)
    if ctx.level < Camp.BAG_LEVEL or ctx.inst then return end
    if R.Bags()[Camp.BAG] or (tonumber(plain(QB.API.ItemCount(Camp.BAG, true))) or 0) > 0 then return end
    local step, held = Camp.SleepNext()
    if not step then return end
    local logVer = QB.changed -- (the log as the last re-plan read it)
    if chainFor ~= step or chainHeld ~= held or chainLog ~= logVer then
      chainFor, chainHeld, chainLog = step, held, logVer
      chainAt = Camp.ChainPlace(step, held)
    end
    local c = chainAt
    local rec
    if c.go then
      local mins = R.Minutes(ctx.me, c.go)
      if not (mins and mins <= 10) then return end
      rec = add()
      rec.mins, rec.word, rec.timed = mins, R.MinWord(mins), true
      rec.go, rec.clickWord = c.go, "show it on the arrow"
    else
      rec = add()
    end
    rec.text, rec.why = c.text, c.why
    rec.tex, rec.lit = itemTex((QB.Data.CAMP or {})[Camp.BAG], 133662), false
    rec.name = "Cozy Sleeping Bag"
  end,
})

-- your buffs: each of your class's you know and lack, then the ones your habits taught
local selfBuf = {}
local function selfIcon(add, sp, first)
  local rec = add()
  rec.key = "self" .. first
  rec.tex, rec.lit = spellIcon(sp.id, sp.icon), true
  R.Click(rec, "spell", sp.id, "player")
  rec.never, rec.neverName = "buff:" .. first, sp.name
  rec.name, rec.clickWord = sp.name, "cast it on you"
end
R.Add({ key = "self", piece = "buffs", order = 100, row = "buffs", cat = "buffs", groups = { "buffs" },
  read = function(add, ctx)
    local names, ids, hidden = mine(ctx)
    if hidden then return end
    for _, sp in ipairs(Camp.SelfMissing(names, ids, nil, nil, selfBuf)) do selfIcon(add, sp, sp.first or sp.id) end
    for _, sp in ipairs(Camp.Learned(ids)) do selfIcon(add, sp, sp.id) end
  end,
})

-- your party's: in a party and not a raid, each member connected, alive and in sight (UnitIsVisible, plain,
-- UnitDocumentation.lua:2428; one out of sight gets no icon), whose auras the client lets you read, lacking a buff of
-- yours for others (Camp.SELF's other, any rank or group version); Thorns only on the member marked tank
-- (UnitGroupRolesAssigned). Out of the spell's range (C_Spell.IsSpellInRange false; UnitInRange's answers are secret)
-- dimmed; the game can't tell (nil): an ordinary icon
local partyNames, partyIds, partyPool = {}, {}, {}
local partyOut, partyRows, partySelf = {}, {}, {}
function Camp.PartyMissing()
  local out = partyOut
  for k = #out, 1, -1 do out[k] = nil end
  if R.Yes(IsInRaid) or not R.Yes(IsInGroup) then return out end
  if R.AurasSecret() then return out end
  local n = 0
  if type(GetNumSubgroupMembers) == "function" then
    local ok, v = pcall(GetNumSubgroupMembers)
    v = ok and plain(v) or nil
    n = type(v) == "number" and math.min(v, 4) or 0
  end
  for p = 1, n do
    local unit = "party" .. p
    if R.Yes(UnitIsConnected, unit) and not R.Yes(UnitIsDeadOrGhost, unit) and (type(UnitIsVisible) ~= "function" or R.Yes(UnitIsVisible, unit)) then
      for k in pairs(partyNames) do partyNames[k] = nil end
      for k in pairs(partyIds) do partyIds[k] = nil end
      local _, _, hidden = Camp.AurasInto(unit, partyNames, partyIds, partyPool)
      local role = nil
      if type(UnitGroupRolesAssigned) == "function" then
        local okR, v = pcall(UnitGroupRolesAssigned, unit)
        role = okR and plain(v) or nil
      end
      -- (the live client's word, section 11: whether a party made by hand has a tank at all)
      if role == "TANK" then R.Diag("tank", true) end
      local sp = not hidden and Camp.SelfMissing(partyNames, partyIds, true, role == "TANK", partySelf)[1]
      if sp then
        local okN, who = pcall(UnitName, unit)
        who = okN and plain(who) or nil
        local okC, _, class = pcall(UnitClass, unit)
        class = okC and plain(class) or nil
        local far = false
        if C_Spell and type(C_Spell.IsSpellInRange) == "function" then
          local okR, r = pcall(C_Spell.IsSpellInRange, sp.id, unit)
          far = okR and plain(r) == false
        end
        local row = partyRows[#out + 1]
        if not row then row = {}; partyRows[#out + 1] = row end
        row.unit, row.who, row.class = unit, type(who) == "string" and who or nil, type(class) == "string" and class or nil
        row.id, row.name, row.icon, row.far = sp.id, sp.name, sp.icon, far
        out[#out + 1] = row
      end
    end
  end
  return out
end
R.Add({ key = "party", piece = "party", order = 150, row = "party", cat = "group", groups = { "party" }, timed = true,
  read = function(add, ctx)
    if not ctx.party then return end
    for _, m in ipairs(Camp.PartyMissing()) do
      local rec = add()
      rec.key = "party" .. m.unit
      rec.tex, rec.lit = spellIcon(m.id, m.icon), true
      R.Click(rec, "spell", m.id, m.unit)
      rec.who, rec.class, rec.far = m.who or "Party member", m.class, m.far
      rec.never, rec.neverName = "party", "party buffs"
      rec.name, rec.clickWord = m.name, "cast it on " .. (m.who or "them")
    end
  end,
})

----------------------------------------------------------------------------
-- events: a kit lit or a feature placed, a meal started, the object under your Interact key, merchants, a cooking
-- trainer's window
----------------------------------------------------------------------------
-- a cooking trainer's window (IsTradeskillTrainer, and a service of Cooking: GetTrainerServiceSkillLine,
-- Blizzard_TrainerUI.lua:43) is noted with where it stands, for Cook's click (Glow.ReadTrainer stops at profession
-- trainers: Glow.lua's own rule)
local function onTrainer()
  if type(IsTradeskillTrainer) ~= "function" or not R.Yes(IsTradeskillTrainer) then return end
  if type(GetNumTrainerServices) ~= "function" or type(GetTrainerServiceSkillLine) ~= "function" then return end
  local ok, n = pcall(GetNumTrainerServices)
  n = ok and plain(n) or 0
  local cooking = false
  for i = 1, math.min(type(n) == "number" and n or 0, 60) do
    local okS, line = pcall(GetTrainerServiceSkillLine, i)
    line = okS and plain(line) or nil
    if line == "Cooking" or (line and line == (GetSpellInfo and plain(GetSpellInfo(2550)))) then cooking = true break end
  end
  if not cooking then return end
  local Disc = QB.Discover
  local key = Disc and Disc.Who and Disc.Who("npc")
  local db = Disc and Disc.DB and Disc.DB()
  if not (key and db) then return end
  local m = plain(QB.API.MapID())
  local pos = type(m) == "number" and C_Map and C_Map.GetPlayerMapPosition and select(2, pcall(C_Map.GetPlayerMapPosition, m, "player"))
  pos = plain(pos)
  local x, y = type(pos) == "table" and plain(pos.x), type(pos) == "table" and plain(pos.y)
  if type(x) ~= "number" or type(y) ~= "number" then return end
  local okN, name = pcall(UnitName, "npc")
  db.trainer = db.trainer or {}
  db.trainer[key] = { n = okN and plain(name) or nil, p = "Cooking", m = m, x = x * 100, y = y * 100 }
end

local function index()
  for id, e in pairs(QB.Data.CAMP or {}) do
    if e.sp then
      if e.t == "kit" then KIT[e.sp] = id elseif e.t == "feature" then FEATURE[e.sp] = id end
    end
  end
  KIT[Camp.FIRE_SPELL] = true
end

function Camp:Init()
  if self.ready then return end
  self.ready = true
  index()
  R.Hear("UNIT_SPELLCAST_SUCCEEDED", onCast)
  R.Hear("PLAYER_SOFT_INTERACT_CHANGED", function() readSoft() end)
  R.Hear("MERCHANT_SHOW", function() Camp.NoteMerchant() end)
  R.Hear("MERCHANT_UPDATE", function() Camp.NoteMerchant() end)
  R.Hear("TRAINER_SHOW", function() onTrainer() end)
  R:Init()
  self.frame = R.frame
end

-- the old names, for what still calls them: the pieces now, Settings, /qb buffs, the bar's top for the arrow
function Camp.Refresh() R.Refresh() end
Camp.Settings = function() return R.Settings() end
Camp.Command = function() R.Command() end
Camp.BarTop = function() return R.BarTop() end
