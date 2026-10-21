-- SPDX-License-Identifier: GPL-3.0-or-later
-- The camp bar: a row of icons, the way a WeakAura shows a buff, up whenever one of them has something to say. Each
-- icon is the game's secure button for its item or spell, so a click is yours: QuestBank only sets what it uses, and
-- only out of a fight. Each has its own switch in Settings:
--   sit    (5.4.4) a fire near you, any fire (yours, another player's, a quest giver's: the game's "Campfire Nearby"),
--          and no Camp Benefits on you: lit, "Sit by the fire for a minute", a click sits you down (a /sit macro: the
--          game keeps sitting itself from addons); sitting, "Stay put" and the seconds of the game's own countdown;
--          then Camp Benefits with its hour
--   food   Well Fed with its minutes; gone: the food you carry that gives it, lit, a click eats it; none: grey
--   fire   a campfire: the campfire kit you carry and how many (a kit's fire is the one that holds camp features, and
--          on Forever the kit is the fire), else Cooking's Basic Campfire when you know the spell (the Simple Wood you
--          carry, its cooldown); one icon, never both. Lit while a feature waits and no fire is near; a click lights
--          it. A feature to place and no way to light a fire: grey, saying where a kit comes from. 5.4.4: the fire you
--          sat by burned out (its aura gone while you stood still, or your kit's 15 minutes up) and you have no kit:
--          a cook short of Simple Wood or Flint and Tinder is shown the nearest general goods vendor with its minutes
--          (its own switch, wood); nobody sells a kit, and one who doesn't cook is told nothing
--   camp   the best camp feature you can place: the shared one-hour cooldown as a sweep, lit when a campfire is near
--          and the cooldown is up; a click places it
--   bag    the Cozy Sleeping Bag with your Well Rested stacks, lit when you stand still under three outside a rested
--          place and its cooldown is up; a click unfurls it. 5.4.4: none from level 14, grey, where its quest chain goes
--          on (it starts at the Nailed Plank in Westfall, or the Burned-Out Remains in the Barrens; its own switch,
--          bagChain); once the chain is done, a seller you have seen
-- Alt-drag moves the bar. In a fight it dims and keeps its buttons as they are; in dungeons it hides if asked.
-- A buff you can give yourself missing puts a banner above the bar in the same style: "Missing buffs" and an icon
-- each, a click casts it or eats the food. 6.1.1: it is up whenever one is missing, out of a fight, alive and not on a
-- flight (6.1.0 showed it once as you left an inn or a city, for 12 seconds: "I did not get the notification bar about
-- missing buffs"); its X hides it for ten minutes; in a dungeon it hides with the bar if asked; in a fight the game's
-- own state driver hides it (it holds the game's secure buttons, which an addon may not hide then); /qb buffs shows it
-- any time. An icon goes once its buff is on you. In a party (not a raid), a second row: each member alive, online and
-- not wearing a buff of yours that can be cast on another (Camp.SELF's other), an icon with the name in the class's
-- colour, a click casts it on them; out of the spell's range (C_Spell.IsSpellInRange: UnitInRange's answers are
-- secret on Forever) the icon is dimmed. Their auras are read out of a fight; a member whose auras the game hides is
-- left out. Its own switch, party.
-- Sellers (5.4.4): each merchant you open who sells camp goods (a campfire kit, Simple Wood, the Cozy Sleeping Bag, a
-- food that makes you Well Fed) is noted with where it stands (QuestBankDB.disc.sell, in the uploads). A grey fire (no
-- kit, no wood) or no sleeping bag: the icon names the nearest known seller and how far, and a click shows it on the
-- arrow for now (an optional detour: it ends once the item is in your bags or you get there, and the arrow is back on
-- your route). Sellers someone has seen first; for Simple Wood and Flint and Tinder also the Classic database's general
-- goods vendors (D.CAMP_SELL), said to be Classic data that may have moved until a player's game has seen the seller.
-- Nothing is said in chat: the bar and its tooltips say it.
-- What the game tells: your professions (GetProfessions), your bags (Game.ScanItems), your buffs (C_UnitAuras, read out
-- of a fight, and again on UNIT_AURA), the spells you know (C_SpellBook.IsSpellKnown), the spell a kit casts
-- (D.CAMP[id].sp, seen on UNIT_SPELLCAST_SUCCEEDED), the campfire under your Interact key, and your rested state
-- (IsResting, PLAYER_UPDATE_RESTING).
local _, QB = ...
if QB.dormant then return end
local Camp = {}
QB.Camp = Camp

local STILL = 20          -- seconds standing still before the sleeping bag lights
local CAMP_CD = 3600      -- the shared camp cooldown, without Field Guide
local TICK = 2            -- seconds between looks
Camp.STILL, Camp.CAMP_CD = STILL, CAMP_CD
-- the shared camp cooldown in seconds: the hour, less Field Guide's 288 / 612 / 900 (QB.Legacy)
function Camp.CampCD() return QB.Legacy and QB.Legacy.CampCooldown() or CAMP_CD end
-- a food's text with Gourmand's longer Well Fed ("15 min" reads 20 / 25 / 30)
local function foodText(s) return QB.Legacy and QB.Legacy.FoodText(s) or s end
Camp.FoodText = foodText

local plain = QB.Plain
local function now() return GetTime and GetTime() or 0 end
-- (each suggestion of 5.4.4 has a switch of its own, on until you untick it: sit, wood, bagChain; 6.1.1's party)
local ON = { "fire", "buffs", "sit", "wood", "bagChain", "party" }
local function settings()
  local s = QB:Settings()
  if type(s.remind) ~= "table" then s.remind = { camp = true, food = true, bag = true, fire = true, quietInstance = true, buffs = true } end
  for _, k in ipairs(ON) do if s.remind[k] == nil then s.remind[k] = true end end
  return s.remind
end
Camp.Settings = settings

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
-- the fire gone out: shown this long, while you stay within this many yards of where it went out; it went out when
-- its aura left you within STILL_YD of where you had it last (walking away from a fire is not its going out)
local OUT_S, OUT_YD, STILL_YD = 600, 200, 10
Camp.OUT_S, Camp.OUT_YD = OUT_S, OUT_YD

-- the long buffs each class keeps on itself, Classic's: the class's rows in the client's SkillLineAbility, the same ids
-- on Forever (1.60.1.70338) and Classic Era (1.15.9). Each entry is one buff to have: the spells that give it (the one
-- last seen on you first, then in this order), each with its icon and its ranks, lowest first. The highest rank you
-- know is cast; any rank counts as on, and so do the names in also (a group version, another aspect or blessing).
-- Battle Shout and the other short ones are left out. other: every spell of the entry can be cast on another player
-- (SpellMisc's RangeIndex 4, Medium Range, 30 yards, on 1.60.1.70338; the armors, Inner Fire, Lightning Shield and
-- Aspect of the Hawk are RangeIndex 1, Self Only), offered for party members
Camp.SELF = {
  MAGE = {
    { { "Arcane Intellect", 135932, { 1459, 1460, 1461, 10156, 10157 } }, also = { "Arcane Brilliance" }, other = true },
    { { "Ice Armor", 135843, { 7302, 7320, 10219, 10220 } }, { "Frost Armor", 135843, { 168, 7300, 7301 } },
      { "Mage Armor", 135991, { 6117, 22782, 22783 } } },
  },
  PRIEST = {
    { { "Power Word: Fortitude", 135987, { 1243, 1244, 1245, 2791, 10937, 10938 } }, also = { "Prayer of Fortitude" }, other = true },
    { { "Inner Fire", 135926, { 588, 7128, 602, 1006, 10951, 10952 } } },
  },
  DRUID = {
    { { "Mark of the Wild", 136078, { 1126, 5232, 6756, 5234, 8907, 9884, 9885 } }, also = { "Gift of the Wild" }, other = true },
    { { "Thorns", 136104, { 467, 782, 1075, 8914, 9756, 9910 } }, other = true },
  },
  WARLOCK = {
    { { "Demon Armor", 136185, { 706, 1086, 11733, 11734, 11735 } }, { "Demon Skin", 136185, { 687, 696 } } },
  },
  SHAMAN = {
    { { "Lightning Shield", 136051, { 324, 325, 905, 945, 8134, 10431, 10432 } } },
  },
  HUNTER = {
    { { "Aspect of the Hawk", 136076, { 13165, 14318, 14319, 14320, 14321, 14322, 25296 } }, { "Aspect of the Monkey", 132159, { 13163 } },
      also = { "Aspect of the Cheetah", "Aspect of the Pack", "Aspect of the Wild", "Aspect of the Beast" } },
  },
  PALADIN = {
    { { "Blessing of Might", 135906, { 19740, 19834, 19835, 19836, 19837, 19838, 25291 } },
      { "Blessing of Wisdom", 135970, { 19742, 19850, 19852, 19853, 19854, 25290 } },
      also = { "Blessing of Kings", "Blessing of Salvation", "Blessing of Light", "Blessing of Sanctuary", "Greater Blessing of Might",
               "Greater Blessing of Wisdom", "Greater Blessing of Kings", "Greater Blessing of Salvation", "Greater Blessing of Light" }, other = true },
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
function Camp.Professions()
  local out = {}
  if not (GetProfessions and GetProfessionInfo) then return out end
  local ok, a, b, _, fish, cook, aid = pcall(GetProfessions)
  if not ok then return out end
  for _, i in ipairs({ a, b, fish, cook, aid }) do
    if i then
      local okI, name, _, skill = pcall(GetProfessionInfo, i)
      name, skill = plain(name), plain(skill)
      if okI and type(name) == "string" and type(skill) == "number" then out[name] = skill end
    end
  end
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
function Camp.Auras(unit)
  local out, ids, hidden = {}, {}, false
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
        local e = { n = plain(a.applications) or 1, exp = type(exp) == "number" and exp > 0 and exp or nil, icon = plain(a.icon) }
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
function Camp.Buffs()
  local out = {}
  for n, a in pairs(Camp.Auras()) do out[n] = a.n end
  return out
end

local function carried()
  local set = {}
  for _, id in ipairs(QB.Game and QB.Game.ScanItems and QB.Game.ScanItems() or {}) do set[id] = true end
  return set
end

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

-- the seller's line in an icon's tooltip: "Sold by X, 4 min away. Click: show it on the arrow."
-- what: what the seller sells, named where the icon's own item is not what it sells ("Lindsay Ashlock sells both, ...")
local function sellerLine(e, m, what)
  local far = m < 1 and "here" or string.format("%d min away", math.floor(m + 0.5))
  if what then return string.format("%s sells %s, %s. Click: show it on the arrow.", e.n or "A merchant you have seen", what, far) end
  return string.format("Sold by %s, %s. Click: show it on the arrow.", e.n or "a merchant you have seen", far)
end
-- a seller of a campfire kit (a seller someone's game has seen: no vendor of the Classic database sells one)
local function sellsKit(e)
  for _, id in ipairs(e.i or {}) do
    local c = (QB.Data.CAMP or {})[id]
    if c and c.t == "kit" then return id end
  end
  return nil
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
local function selfOn(entry, names, ids)
  for _, sp in ipairs(entry) do
    if names[sp[1]] or names[spellName(sp[3][1], sp[1])] then return sp end
    for _, id in ipairs(sp[3]) do if ids[id] then return sp end end
  end
  for _, n in ipairs(entry.also or {}) do if names[n] then return true end end
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
local function castFor(class, i, entry)
  local last = seen[class .. i]
  for pass = 1, 2 do
    for _, sp in ipairs(entry) do
      if (pass == 1) == (sp[1] == last) then
        for r = #sp[3], 1, -1 do
          local id = sp[3][r]
          if knows(id) then return { id = id, name = spellName(id, sp[1]), icon = sp[2] } end
        end
      end
    end
  end
  return nil
end
-- the class's buffs you know and don't have on: { id = the highest rank you know, name, icon }, in Camp.SELF's order.
-- other: only those that can be cast on another player (for a party member's auras)
function Camp.SelfMissing(names, ids, other)
  local class, out = myClass(), {}
  for i, entry in ipairs(Camp.SELF[class] or {}) do
    if (entry.other or not other) and not selfOn(entry, names, ids) then
      local sp = castFor(class, i, entry)
      if sp then out[#out + 1] = sp end
    end
  end
  return out
end

----------------------------------------------------------------------------
-- the bar
----------------------------------------------------------------------------
local ART = QB.ART or "Interface\\AddOns\\QuestBank\\art\\" -- (a host holding a copy of the engine names its own folder: QB.ART)
local SIZE, GAP = 40, 6
local ORDER = { "sit", "food", "fire", "camp", "bag" }
local bar, icons = nil, {}
local campAt, fireAt, lastMove, lastPos
local herePos = {} -- where you stand, read into this one table at each look

local function quiet()
  if settings().quietInstance ~= false and IsInInstance then
    local ok, inside = pcall(IsInInstance)
    if ok and plain(inside) == true then return true end
  end
  return false
end
local function fighting() return InCombatLockdown and InCombatLockdown() or false end

-- (the review round) the bar's top at its own place (CENTER 0 -190), down from the screen's top in UIParent's units,
-- for the arrow, which keeps above it (Arrow.lua, A.Place); nil once the bar was dragged elsewhere
function Camp.BarTop()
  local pos = settings().pos
  if type(pos) == "table" and pos.x then return nil end
  return (UIParent:GetHeight() or 768) / 2 + 190 - SIZE / 2
end

local function barFrame()
  if bar then return bar end
  bar = CreateFrame("Frame", "QuestBankCampBar", UIParent)
  bar:SetSize(SIZE, SIZE)
  bar:SetFrameStrata("MEDIUM")
  bar:SetMovable(true)
  bar:SetClampedToScreen(true)
  local pos = settings().pos
  if type(pos) == "table" and pos.x then bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x, pos.y) else bar:SetPoint("CENTER", UIParent, "CENTER", 0, -190) end
  bar.elapsed = 0
  return bar
end

local function moveStart(_, button)
  if button == "LeftButton" and IsAltKeyDown and IsAltKeyDown() and not fighting() then bar:StartMoving(); bar.moving = true end
end
local function moveStop()
  if not bar.moving then return end
  bar.moving = nil
  bar:StopMovingOrSizing()
  local x, y = bar:GetCenter()
  if x then settings().pos = { x = x, y = y } end
end

-- one icon: the game's secure button with the item's or spell's art, a black edge (gold when lit), the cooldown's
-- sweep, minutes at the bottom, a count at the top. hint: a grey last line for its tooltip
local function newIcon(name, parent, hint)
  local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
  b:SetSize(SIZE, SIZE)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b.hint = hint
  b.edge = b:CreateTexture(nil, "BACKGROUND")
  b.edge:SetPoint("TOPLEFT", -1, 1); b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  b.edge:SetColorTexture(0, 0, 0, 1)
  b.glow = b:CreateTexture(nil, "BACKGROUND", nil, -1)
  b.glow:SetTexture(ART .. "glow")
  b.glow:SetBlendMode("ADD")
  b.glow:SetPoint("CENTER")
  b.glow:SetSize(SIZE * 1.9, SIZE * 1.9)
  b.glow:Hide()
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints()
  if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
  b.time = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.time:SetPoint("BOTTOM", 0, 2)
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  b.count:SetPoint("TOPRIGHT", -2, -2)
  b.hi = b:CreateTexture(nil, "HIGHLIGHT")
  b.hi:SetAllPoints()
  b.hi:SetColorTexture(1, 1, 1, 0.12)
  b:SetScript("OnEnter", function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self.tip[1], 1, 0.82, 0.3)
    for i = 2, #self.tip do GameTooltip:AddLine(self.tip[i], 1, 1, 1, true) end
    if self.hint then GameTooltip:AddLine(self.hint, 0.5, 0.5, 0.5) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  return b
end

-- the click of a grey icon, or one with nothing of the game's to use, with a place to go (Camp.State's seller, or dest:
-- the sleeping bag's quest chain): that place on the arrow for now. The game's own click does nothing there (no item
-- or wood), and this runs beside it, once a click
local lastGo = -10
local function goSeller(self)
  local d = self.state
  if not (d and (d.seller or d.dest)) or (IsAltKeyDown and IsAltKeyDown()) then return end
  if not d.grey and (d.item or d.spell or d.macro) then return end
  local t = now()
  if t - lastGo < 0.3 then return end -- (a click's down and up)
  lastGo = t
  if d.dest then
    if QB.Arrow then QB.Arrow:Show(d.dest.name, d.dest, d.dest.about) end
  else
    Camp.GoTo(d.seller, d.sellItem)
  end
end
Camp.GoSeller = goSeller

local function icon(key)
  local b = icons[key]
  if b then return b end
  b = newIcon("QuestBankCamp_" .. key, barFrame(), "Alt-drag moves the bar.")
  b:HookScript("OnMouseDown", moveStart)
  b:HookScript("OnMouseUp", moveStop)
  b:HookScript("OnClick", QB.Safe(goSeller, "camp bar: seller"))
  icons[key] = b
  return b
end

local function mins(sec)
  if not sec or sec <= 0 then return "" end
  if sec >= 3600 then return string.format("%dh", math.floor(sec / 3600 + 0.5)) end
  if sec >= 60 then return string.format("%dm", math.ceil(sec / 60)) end
  return string.format("%ds", math.ceil(sec))
end

local function itemCD(id)
  local get = C_Container and C_Container.GetItemCooldown
  if not (get and id) then return 0, 0 end
  local ok, start, dur = pcall(get, id)
  start, dur = ok and plain(start) or 0, ok and plain(dur) or 0
  if type(start) ~= "number" or type(dur) ~= "number" or dur <= 1.5 then return 0, 0 end
  return start, dur
end

local function count(id)
  local get = C_Item and C_Item.GetItemCount or GetItemCount
  local ok, n = pcall(get, id)
  n = ok and plain(n) or 0
  return type(n) == "number" and n or 0
end

-- the best camp feature's shared cooldown, start and duration (0, 0: ready): the item's own, else the hour since you
-- placed one
local function campCD(best, t)
  local start, dur = itemCD(best.id)
  local cd = Camp.CampCD()
  if dur == 0 and campAt and t - campAt < cd then start, dur = campAt, cd end
  if dur > 0 and start + dur - t <= 0 then return 0, 0 end
  return start, dur
end
local function fireNear(t) return fireAt ~= nil and t - fireAt < 300 end
-- "All camp features share an hour's cooldown.", shorter with Field Guide
function Camp.CooldownText()
  local cd = Camp.CampCD()
  if cd >= CAMP_CD then return "All camp features share an hour's cooldown." end
  return string.format("All camp features share a %d-minute cooldown (Field Guide).", math.floor(cd / 60 + 0.5))
end

-- what a grey fire's seller may sell: a kit or Simple Wood; the bag's: the bag
local fireSet
local function fireGoods()
  if fireSet then return fireSet end
  fireSet = { [Camp.WOOD] = true }
  for id, e in pairs(QB.Data.CAMP or {}) do if e.t == "kit" then fireSet[id] = true end end
  return fireSet
end
local BAG_GOODS = { [211527] = true }
local KIT_GOODS = { [4470] = true, [4471] = true }
local WOOD_ONLY, FLINT_ONLY, BOTH = { 4470 }, { 4471 }, { 4470, 4471 }
local RIX = "Rix Xizzix, the lost and found in Booty Bay, may sell it once the chain is done."
Camp.RIX = RIX

local function level()
  if type(UnitLevel) ~= "function" then return 0 end
  local ok, l = pcall(UnitLevel, "player")
  l = ok and plain(l) or nil
  return type(l) == "number" and l or 0
end
local function isResting()
  if type(IsResting) ~= "function" then return false end
  local ok, v = pcall(IsResting)
  return ok and plain(v) == true
end
local function near(a, b, yd)
  return a ~= nil and b ~= nil and a.c == b.c and (a.wx - b.wx) * (a.wx - b.wx) + (a.wy - b.wy) * (a.wy - b.wy) <= yd * yd
end
-- a place kept: where you stand copied into a table of its own (the bar reads where you stand into one table each look)
local function keep(into, p)
  if not p then return nil end
  into = into or {}
  into.c, into.wx, into.wy = p.c, p.wx, p.wy
  return into
end
-- minutes from you to a place ({c, wx, wy}): by your flight paths and boats where the arrow's router knows the way,
-- else on foot as the crow flies; nil off your land
local function away(me, p)
  if not (me and p and p.c == me.c) then return nil end
  local TV, m = QB.Travel, nil
  if TV and TV.Reach and TV.Via then
    local okR, R = pcall(TV.Reach, me, TV.Opts("pin"))
    if okR and R then local okV, v = pcall(TV.Via, R, p); if okV then m = v end end
  end
  if not m or m == math.huge then m = math.sqrt((p.wx - me.wx) ^ 2 + (p.wy - me.wy) ^ 2) * QB.Model.DETOUR / QB.Model.RUN / 60 end
  return m
end
local function awayText(m) return (not m) and "" or (m < 1 and ", here" or string.format(", %d min away", math.floor(m + 0.5))) end

----------------------------------------------------------------------------
-- the fire you are by, watched out of a fight (the client hides auras in one). Its aura on you and then gone while
-- you stood still (within STILL_YD of one spot for STILL_S seconds) is a fire burned out; so is your kit's fire, 15
-- minutes after you lit it, with you still by it. When and where it went out are kept a while (OUT_S, OUT_YD) for the
-- fire icon's offer. Walking away from a fire is not its going out
----------------------------------------------------------------------------
local STILL_S = 4
local nearOn, anchor, stillSince, litAt, litPos, outAt, outPos
local function watchFire(ids, t, me)
  if me and not near(me, anchor, STILL_YD) then anchor, stillSince = keep(anchor, me), t end
  local still = me ~= nil and stillSince ~= nil and t - stillSince >= STILL_S
  if ids[Camp.NEARBY] then
    fireAt, outAt, nearOn = t, nil, true
  elseif nearOn then
    nearOn = false
    if still then outAt, outPos, fireAt = t, keep(outPos, me), nil end
  end
  if litAt and t - litAt >= Camp.KIT_BURN then
    if near(me, litPos, 100) and not ids[Camp.NEARBY] then outAt, outPos, fireAt = litAt + Camp.KIT_BURN, litPos, nil end
    litAt, litPos = nil, nil
  end
end
-- (a fire gone out, for the tests: its time and place, or nil)
function Camp.FireOut() return outAt, outPos end
function Camp.ForgetFire() nearOn, litAt, litPos, outAt, outPos = nil, nil, nil, nil, nil end

-- the fire burned out and you carry no kit: a cook short of Simple Wood or Flint and Tinder (Cooking's Basic Campfire
-- Kit is made from the one with the other) is shown the nearest general goods vendor, a click puts it on the arrow
-- until you have bought them; with both in your bags, the kit is yours to make. Nothing for one who doesn't cook
local function woodOffer(bags, profs, t, me)
  if not (outAt and t - outAt < OUT_S and near(me, outPos, OUT_YD)) then return nil end
  if Camp.Kits(bags)[1] or not Camp.Cook(profs) then return nil end
  local wood, flint = count(Camp.WOOD) > 0, count(Camp.FLINT) > 0
  local kit = (QB.Data.CAMP or {})[Camp.BASIC_KIT] or {}
  local d = { tex = "Interface\\Icons\\" .. (kit.i or "inv_camelot_camping_welcomingcampfire") }
  if wood and flint then
    d.tip = { "The fire burned out", "You carry Simple Wood and Flint and Tinder: make a Basic Campfire Kit in your Cooking window." }
    return d
  end
  local need = (not wood and not flint) and BOTH or (wood and FLINT_ONLY or WOOD_ONLY)
  d.lit = true
  d.tip = { "The fire burned out", "A Basic Campfire Kit (Cooking) takes Simple Wood and Flint and Tinder: "
    .. ((not wood and not flint) and "you have neither." or (wood and "you have no Flint and Tinder." or "you have no Simple Wood.")) }
  local e, m = Camp.NearestSeller(KIT_GOODS, need, true)
  if e then
    d.seller, d.sellItem = e, need
    d.tip[3] = sellerLine(e, m, #need == 2 and "both" or "it")
    if e.seed then d.tip[4] = Camp.SEED_NOTE end
  else
    d.tip[3] = "A general goods vendor sells both."
  end
  return d
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

-- the grey bag's way to the chain's next step: where it starts (or, held, where it is handed in, as the catalog places
-- it), with the minutes, and the place to show on the arrow until the step is taken (or handed in). Worked out again
-- for another step, every 30 seconds or 30 yards on (the bar looks every 2 seconds)
local hint = {}
local function chainHint(step, held, done, total, me)
  local t = now()
  if hint.d and hint.step == step and hint.held == held and t - hint.at < 30 and (not me or near(me, hint.me, 30)) then return hint.d end
  hint.step, hint.held, hint.at, hint.me = step, held, t, keep(hint.me, me)
  hint.d = nil
  local qid = step.id
  if step.alt then
    -- (the first step's quest of your side: the one in your log, else the catalog's)
    local log, q = QB.state and QB.state.log or {}, QB.Quest.Get(step.id)
    if log[step.alt] or (not log[step.id] and not (q and QB.Quest.ForMe(q))) then qid = step.alt end
  end
  local m, x, y, where = step.m, step.x, step.y, step.where
  local q = held and QB.Quest.Get(qid)
  if q and q.turn and q.turn.m and q.turn.m > 0 and not q.turn.inside then m, x, y, where = q.turn.m, q.turn.x, q.turn.y, q.turn.n end
  local p = m and QB.Model.World(m, x, y)
  local mins = away(me, p)
  local d = { tex = "Interface\\Icons\\" .. ((QB.Data.CAMP[Camp.BAG] or {}).i or "inv_misc_bag_bigbagofenchantments"), grey = true }
  local place = where and (m and string.format("%s (%.1f, %.1f)", where, x, y) or where) or "where the bag's note points"
  if done == 0 and not held then
    d.tip = { "Cozy Sleeping Bag", string.format("You have none: a quest chain from level %d gives it. It starts at %s%s.", Camp.BAG_LEVEL, place, awayText(mins)) }
  elseif held then
    d.tip = { "Cozy Sleeping Bag", string.format("Its quest chain, step %d of %d: %s is in your log, handed in at %s%s.", done + 1, total, step.name, place, awayText(mins)) }
  else
    d.tip = { "Cozy Sleeping Bag", string.format("Its quest chain, step %d of %d: %s, at %s%s.", done + 1, total, step.name, place, awayText(mins)) }
  end
  if p then
    d.dest = { name = (where or step.name):match("^([^,]+)") or step.name, c = p.c, wx = p.wx, wy = p.wy, about = { qid = qid, what = held and "turn" or "give" } }
    d.tip[#d.tip + 1] = "Click: show it on the arrow."
  end
  d.tip[#d.tip + 1] = "A minute in the bag: +1% XP from kills and quests, up to 3%. " .. RIX
  hint.d = d
  return d
end

-- what each icon shows now: nil to hide it, else { tex, time, count, lit, grey, item or spell or macro, cd = { start,
-- dur }, tip, seller = a seller of what it lacks (a click shows it on the arrow), dest = a place a click shows }
function Camp.State()
  local s = settings()
  local out = {}
  local auras, ids = Camp.Auras()
  local bags, t, profs = carried(), now(), Camp.Professions()
  local me = QB.API.WorldPosition(nil, herePos)
  noteSelf(auras, ids)
  if not fighting() then watchFire(ids, t, me) end
  if s.sit then
    -- by a fire: sit a minute for Camp Benefits; sitting, its countdown; then the hour of Camp Benefits
    local nearA, ben, wel = ids[Camp.NEARBY], ids[Camp.BENEFITS], nil
    for id in pairs(Camp.WELCOME) do if ids[id] then wel = ids[id] end end
    local kit = (QB.Data.CAMP or {})[Camp.BASIC_KIT] or {}
    local fireTex = type(nearA) == "table" and nearA.icon or ("Interface\\Icons\\" .. (kit.i or "inv_camelot_camping_welcomingcampfire"))
    if wel then
      local left = type(wel) == "table" and wel.exp and math.max(0, wel.exp - t) or nil
      out.sit = { tex = type(wel) == "table" and wel.icon or fireTex, lit = true, macro = "/sit", time = left and mins(left) or "",
                  tip = { left and string.format("Stay put: %d s", math.ceil(left)) or "Stay put", "Sitting by the fire: Camp Benefits once the minute is up." } }
    elseif nearA and not ben then
      out.sit = { tex = fireTex, lit = true, macro = "/sit",
                  tip = { "Sit by the fire for a minute", "A minute sitting by it gives Camp Benefits for an hour: the buffs of its camp features. Click to sit down." } }
    elseif ben then
      local left = type(ben) == "table" and ben.exp and ben.exp - t or nil
      out.sit = { tex = type(ben) == "table" and ben.icon or fireTex, time = left and mins(left) or "",
                  tip = { "Camp Benefits", left and ("Runs out in " .. mins(left) .. ".") or "On you." } }
    end
  end
  if s.food then
    local fed = auras["Well Fed"]
    if fed then
      out.food = { tex = fed.icon or 136000, time = fed.exp and mins(fed.exp - t) or "", tip = { "Well Fed", fed.exp and ("Runs out in " .. mins(fed.exp - t) .. ".") or "" } }
    else
      local foods = Camp.Foods(bags)
      local f = foods[1]
      if f then
        out.food = { tex = "Interface\\Icons\\" .. f.e.i, count = count(f.id), lit = true, item = f.id,
                     tip = { "Not Well Fed", f.e.n .. ": " .. foodText(f.e.g or "Well Fed") .. ". Click to eat." } }
      else
        out.food = { tex = 133945, grey = true, tip = { "Not Well Fed", "No food in your bags that gives Well Fed." } }
      end
    end
  end
  local list = Camp.Placeable(bags, profs)
  if s.camp then
    local best = list[1]
    if best then
      local cdStart, cdDur = campCD(best, t)
      local up = cdDur == 0
      local near = fireNear(t)
      local names = {}
      for i = 1, math.min(4, #list) do names[#names + 1] = list[i].e.n .. (list[i].e.g and (": " .. list[i].e.g) or "") end
      out.camp = { tex = "Interface\\Icons\\" .. best.e.i, lit = up and near, grey = not up, item = best.id, cd = (not up) and { cdStart, cdDur } or nil,
                   time = (not up) and mins(cdStart + cdDur - t) or "",
                   tip = { up and (near and "Place a camp feature" or "Camp features ready") or ("Camp cooldown: " .. mins(cdStart + cdDur - t)),
                           table.concat(names, "\n"), up and (near and "Click to place the first." or "Light a campfire, then click to place the first.") or Camp.CooldownText() } }
    end
  end
  local fire = Camp.Fire(bags)
  -- the fire you sat by burned out and you have no kit (nor Classic Era's Basic Campfire): the wood offer in the fire's
  -- place, under its own switch
  local offer = s.wood and not fire and woodOffer(bags, profs, t, me) or nil
  if offer then
    out.fire = offer
  elseif s.fire then
    local waits = out.camp and not out.camp.grey and not fireNear(t)
    if fire and fire.spell then
      local st, du = spellCD(fire.spell)
      local up = du == 0 or st + du - t <= 0
      local wood = count(Camp.WOOD)
      out.fire = { tex = spellIcon(fire.spell, Camp.FIRE_ICON), spell = fire.spell, count = wood, grey = wood == 0,
                   lit = wood > 0 and up and waits and true or false, cd = (not up) and { st, du } or nil, time = (not up) and mins(st + du - t) or "",
                   tip = { spellName(fire.spell, "Basic Campfire"), wood > 0 and "Click to light a campfire." or "Needs Simple Wood." } }
      if wood == 0 then
        -- no wood: the nearest seller of it (or of a kit), a click shows it on the arrow
        local e, m = Camp.NearestSeller(fireGoods())
        if e then out.fire.seller, out.fire.sellItem, out.fire.tip[3] = e, Camp.WOOD, sellerLine(e, m) end
      end
    elseif fire and fire.kit then
      local k = fire.kit
      local st, du = itemCD(k.id)
      local up = du == 0 or st + du - t <= 0
      out.fire = { tex = "Interface\\Icons\\" .. k.e.i, count = count(k.id), item = k.id, lit = up and waits and true or false,
                   cd = (not up) and { st, du } or nil, time = (not up) and mins(st + du - t) or "",
                   tip = { k.e.n, string.format("Holds %d camp feature%s. Click to light it.", k.e.cap or 3, (k.e.cap or 3) == 1 and "" or "s") } }
    elseif out.camp then
      -- a feature to place and nothing to light its fire with: where a kit comes from. A seller named says what it sells
      -- (nobody is known to sell a kit: one your games saw selling one, else, for a cook, Simple Wood's)
      local kit = (QB.Data.CAMP or {})[Camp.BASIC_KIT] or {}
      local cook = Camp.Cook(profs)
      out.fire = { tex = "Interface\\Icons\\" .. (kit.i or "inv_camelot_camping_welcomingcampfire"), grey = true,
                   tip = { "No campfire kit", cook and "Cooking's Basic Campfire makes one from Simple Wood, with Flint and Tinder." or "A cook makes them from Simple Wood." } }
      local e, m = Camp.NearestSeller(fireGoods())
      local k = e and sellsKit(e)
      if e and (k or cook) then
        out.fire.seller, out.fire.sellItem = e, k or Camp.WOOD
        out.fire.tip[3] = sellerLine(e, m, k and "campfire kits" or "Simple Wood")
      end
    end
  end
  local bagTex = "Interface\\Icons\\" .. ((QB.Data.CAMP[Camp.BAG] or {}).i or "inv_misc_bag_bigbagofenchantments")
  if bags[Camp.BAG] then
    if s.bag then
      if me and lastPos and math.abs(me.wx - lastPos.wx) + math.abs(me.wy - lastPos.wy) > 2 then lastMove = t end
      if me then lastPos = keep(lastPos, me) end
      lastMove = lastMove or t
      local rested = auras["Well Rested"]
      local stacks = rested and rested.n or 0
      local still = t - lastMove >= STILL and not (UnitOnTaxi and plain(UnitOnTaxi("player")) == true)
      -- (never in a rested place, where the game won't unfurl it; its own cooldown, an hour on this client)
      local st, du = itemCD(Camp.BAG)
      local up = du == 0 or st + du - t <= 0
      local town = isResting()
      out.bag = { tex = bagTex, count = stacks > 0 and stacks or nil, cd = (not up) and { st, du } or nil,
                  time = rested and rested.exp and mins(rested.exp - t) or ((not up) and mins(st + du - t) or ""),
                  lit = stacks < 3 and still and up and not town, grey = stacks == 0 and not still, item = Camp.BAG,
                  tip = { "Well Rested " .. stacks .. "/3", "A minute in the Cozy Sleeping Bag adds a stack of bonus XP. Click to unfurl it.",
                          town and "You are in a rested place, a town or an inn: the game won't unfurl it here." or ((not up) and ("Ready in " .. mins(st + du - t) .. ".") or nil) } }
    end
  elseif not ((tonumber(plain(QB.API.ItemCount(Camp.BAG, true))) or 0) > 0) then
    -- (none in your bags or your bank)
    local step, held, done, total = Camp.SleepNext()
    if step and s.bagChain and level() >= Camp.BAG_LEVEL then
      -- none, the chain not done: where it goes on, a click shows it on the arrow
      out.bag = chainHint(step, held, done, total, me)
    elseif not step and s.bag then
      -- the chain done and no bag in your bags: a seller you have seen, its nearest named; a click shows it on the arrow
      local e, m = Camp.NearestSeller(BAG_GOODS)
      if e then
        out.bag = { tex = bagTex, grey = true, seller = e, sellItem = Camp.BAG,
                    tip = { "Cozy Sleeping Bag", string.format("You have none: sold by %s, %s.", e.n or "a merchant you have seen",
                            m < 1 and "here" or string.format("%d min away", math.floor(m + 0.5))), "Click: show it on the arrow. A minute in it adds a stack of bonus XP." } }
      else
        out.bag = { tex = bagTex, grey = true, tip = { "Cozy Sleeping Bag", "You have none. " .. RIX } }
      end
    end
  end
  return out
end

----------------------------------------------------------------------------
-- the missing-buffs banner: your class's own buffs, Well Fed and a camp feature's, and your party's, while one is
-- missing
----------------------------------------------------------------------------
local SNOOZE = 600         -- its X hides it this long
local TOP = 34             -- the title's strip above the icons
local COL = 76             -- a party member's column: the icon, the name under it
local NAME_H = 14          -- the name's line
Camp.SNOOZE = SNOOZE
Camp.shows = 0             -- banners shown, for the tests
local holder, banner, bicons, picons = nil, nil, {}, {}
local snoozeUntil, driven, fightStarted
local eating -- the food you clicked to eat ({ id, e }), while you eat

local function yes(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, v = pcall(fn, ...)
  return ok and plain(v) == true
end
-- a cast or a channel of yours under way, or a meal (the game's Food or Drink buff on you)
local MEAL = { Food = true, Drink = true, ["Food & Drink"] = true, Refreshment = true }
local function busy(names)
  local function casting(fn)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, "player")
    return ok and plain(v) ~= nil
  end
  if casting(UnitCastingInfo) or casting(UnitChannelInfo) then return true end
  names = names or Camp.Auras()
  for n in pairs(MEAL) do if names[n] then return true end end
  return false
end
Camp.Busy = busy

-- what you could have on and don't, each with what a click does: { tex, item or spell (self: cast on you), count, tip }
function Camp.Missing()
  local s = settings()
  local out = {}
  local names, ids = Camp.Auras()
  local bags, t = carried(), now()
  if s.food and not names["Well Fed"] then
    local f = Camp.Foods(bags)[1]
    -- (the last piece eaten: its icon stays while you eat it, until Well Fed is on you)
    if not f and eating and busy(names) then f = eating end
    if f then
      out[#out + 1] = { key = "food", tex = "Interface\\Icons\\" .. f.e.i, item = f.id, count = count(f.id),
                        tip = { "Well Fed", f.e.n .. ": " .. foodText(f.e.g or "Well Fed") .. ".", "Click to eat it." } }
    end
  elseif eating then
    eating = nil
  end
  for i, sp in ipairs(Camp.SelfMissing(names, ids)) do
    out[#out + 1] = { key = "self" .. i, tex = spellIcon(sp.id, sp.icon), spell = sp.id, self = true, tip = { sp.name, "Click to cast it on yourself." } }
  end
  -- the best feature you can place that gives a buff (D.CAMP's b: a tent, a bot or a workbench gives none), unless its
  -- buff is on you. The aura is the buff's own spell, not the feature's name (the Sharpening Wheel's is Extra Strength)
  local best
  if s.camp then for _, x in ipairs(Camp.Placeable(bags)) do if x.e.b then best = x; break end end end
  if best and select(2, campCD(best, t)) == 0 then
    local on = ids[best.e.b] or names[best.e.bn or ""] or names[spellName(best.e.b, best.e.bn or "")]
    if not on then
      local feat = { key = "camp", tex = "Interface\\Icons\\" .. best.e.i, item = best.id,
                     tip = { best.e.n, (best.e.g or "Its buff") .. " while you sit by it.", "Click to place it." } }
      if not fireNear(t) then
        -- the feature needs a campfire first: the click lights one
        local fire = Camp.Fire(bags)
        feat.item, feat.tip[2], feat.tip[3] = nil, "Needs a campfire first.", "Click to light one."
        if fire and fire.kit then
          feat.tex, feat.item, feat.count = "Interface\\Icons\\" .. fire.kit.e.i, fire.kit.id, count(fire.kit.id)
        elseif fire and fire.spell and count(Camp.WOOD) > 0 then
          feat.tex, feat.spell = spellIcon(fire.spell, Camp.FIRE_ICON), fire.spell
        else
          feat = nil
        end
      end
      out[#out + 1] = feat
    end
  end
  return out
end

-- your party's: in a party and not a raid, each member alive, online and with auras the game lets you read, lacking a
-- buff of yours that can be cast on another (Camp.SELF's other): the first such, { unit, who, class, id, name, icon,
-- far }. far: out of the spell's range (C_Spell.IsSpellInRange, a plain answer; UnitInRange's are secret on Forever:
-- UnitDocumentation.lua's SecretReturns), shown dimmed; nil when the game can't tell
function Camp.PartyMissing()
  local out = {}
  if settings().party == false or yes(IsInRaid) or not yes(IsInGroup) then return out end
  local n = 0
  if type(GetNumSubgroupMembers) == "function" then
    local ok, v = pcall(GetNumSubgroupMembers)
    v = ok and plain(v) or nil
    n = type(v) == "number" and math.min(v, 4) or 0
  end
  for p = 1, n do
    local unit = "party" .. p
    if yes(UnitIsConnected, unit) and not yes(UnitIsDeadOrGhost, unit) then
      local names, ids, hidden = Camp.Auras(unit)
      local sp = not hidden and Camp.SelfMissing(names, ids, true)[1]
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
        out[#out + 1] = { unit = unit, who = type(who) == "string" and who or nil, class = type(class) == "string" and class or nil,
                          id = sp.id, name = sp.name, icon = sp.icon, far = far }
      end
    end
  end
  return out
end

-- the banner sits in a holder the game's state driver hides in a fight and shows after it (an addon may not hide a
-- frame holding the game's secure buttons in a fight: Blizzard_RestrictedAddOnEnvironment/SecureStateDriver.lua's
-- RegisterStateDriver, "visibility"); without one, the banner goes clear in a fight
local function bannerFrame()
  if banner then return banner end
  holder = CreateFrame("Frame", "QuestBankBuffHolder", UIParent)
  holder:SetSize(1, 1)
  holder:SetPoint("CENTER")
  if type(RegisterStateDriver) == "function" then
    driven = pcall(RegisterStateDriver, holder, "visibility", "[combat] hide; show")
  end
  banner = CreateFrame("Frame", "QuestBankBuffBanner", holder)
  banner:SetFrameStrata("MEDIUM")
  banner:SetClampedToScreen(true)
  banner:SetSize(160, TOP + SIZE + 12)
  banner:SetPoint("BOTTOM", barFrame(), "TOP", 0, 14) -- above the camp bar, wherever it was dragged
  -- a dark plate with a black edge, as a WeakAura's
  banner.edge = banner:CreateTexture(nil, "BACKGROUND", nil, -2)
  banner.edge:SetAllPoints()
  banner.edge:SetColorTexture(0, 0, 0, 0.9)
  banner.plate = banner:CreateTexture(nil, "BACKGROUND", nil, -1)
  banner.plate:SetPoint("TOPLEFT", 1, -1)
  banner.plate:SetPoint("BOTTOMRIGHT", -1, 1)
  banner.plate:SetColorTexture(0.08, 0.08, 0.09, 0.9)
  banner.title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  banner.title:SetPoint("TOPLEFT", 12, -11)
  banner.title:SetText("Missing buffs")
  banner.close = CreateFrame("Button", nil, banner, "UIPanelCloseButton")
  banner.close:SetPoint("TOPRIGHT", -4, -4)
  banner.close:SetScript("OnClick", QB.Safe(function() Camp.Snooze() end, "buff banner: close"))
  -- a gold line along the bottom, as the bar's lit icons
  banner.left = banner:CreateTexture(nil, "ARTWORK")
  banner.left:SetPoint("BOTTOMLEFT", 1, 1)
  banner.left:SetPoint("BOTTOMRIGHT", -1, 1)
  banner.left:SetHeight(2)
  banner.left:SetColorTexture(1, 0.75, 0.2, 0.85)
  banner:Hide()
  return banner
end
Camp.BannerFrame = bannerFrame

-- one icon's look, the same for every row
local function paint(b, d)
  b.icon:SetTexture(d.tex)
  b.icon:SetDesaturated(false)
  b.icon:SetAlpha(1)
  b.time:SetText("")
  b.count:SetText(d.count and d.count > 1 and tostring(d.count) or "")
  b.glow:Hide()
  b.edge:SetColorTexture(1, 0.75, 0.2, 1)
  b.cd:SetCooldown(0, 0)
  b.tip, b.state = d.tip, d
end

-- the icons, centred under the title: yours, then your party's with their names under them. The game's secure
-- buttons, set out of a fight only
local function layBanner(list, party)
  local f = bannerFrame()
  local n, m = #list, #party
  local row1 = n > 0 and n * SIZE + (n - 1) * GAP or 0
  local row2 = m > 0 and m * COL or 0
  local w = math.max(row1 + 24, row2 + 24, 160)
  local h = TOP + (n > 0 and SIZE + 10 or 0) + (m > 0 and SIZE + NAME_H + 12 or 0) + 2
  f:SetSize(w, h)
  local x = math.floor((w - row1) / 2)
  for i, d in ipairs(list) do
    local b = bicons[i]
    if not b then
      b = newIcon("QuestBankBuff_" .. i, f)
      -- (the food you click to eat is kept in mind: its icon stays while you eat the last piece)
      b:HookScript("OnClick", function(self) Camp.Used(self.state) end)
      bicons[i] = b
    end
    paint(b, d)
    b:SetAlpha(1)
    b:SetAttribute("type", d.item and "item" or "spell")
    b:SetAttribute("item", d.item and ("item:" .. d.item) or nil)
    b:SetAttribute("spell", d.spell)
    b:SetAttribute("unit", d.self and "player" or nil)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -TOP)
    b:Show()
    x = x + SIZE + GAP
  end
  for i = n + 1, #bicons do bicons[i]:Hide() end
  local y = -(TOP + (n > 0 and SIZE + 10 or 0))
  x = math.floor((w - row2) / 2)
  for i, d in ipairs(party) do
    local b = picons[i]
    if not b then
      b = newIcon("QuestBankBuffParty_" .. i, f)
      b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      b.label:SetPoint("TOP", b, "BOTTOM", 0, -3)
      b.label:SetWidth(COL - 4)
      b.label:SetWordWrap(false)
      picons[i] = b
    end
    local who = d.who or "Party member"
    paint(b, { tex = spellIcon(d.id, d.icon), tip = { d.name, "Click to cast it on " .. who .. "." } })
    if d.far then b.tip[3] = "Out of range." end
    b.label:SetText(who)
    local col = d.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[d.class]
    if col then b.label:SetTextColor(col.r, col.g, col.b) else b.label:SetTextColor(1, 1, 1) end
    b:SetAlpha(d.far and 0.4 or 1)
    b:SetAttribute("type", "spell")
    b:SetAttribute("spell", d.id)
    b:SetAttribute("unit", d.unit)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f, "TOPLEFT", x + math.floor((COL - SIZE) / 2), y)
    b:Show()
    x = x + COL
  end
  for i = m + 1, #picons do picons[i]:Hide() end
end

-- one of the banner's icons clicked: the food you eat is kept in mind (its icon stays while you eat the last piece)
function Camp.Used(d)
  if d and d.key == "food" and d.item then
    local e = (QB.Data.FOOD or {})[d.item]
    if e then eating = { id = d.item, e = e } end
  end
end

-- its X: hidden for ten minutes
function Camp.Snooze()
  if fighting() then return end
  snoozeUntil = now() + SNOOZE
  if banner then banner:Hide() end
end

-- up whenever something is missing (Camp.Missing, Camp.PartyMissing), out of a fight, alive, not on a flight, its
-- switch on, not hidden by its X, and not in a dungeon while the bar hides there. ask (/qb buffs): whatever the switch,
-- the X, a flight or a dungeon. Laid out out of a fight only. True when up, else false and why not: fight, off, away,
-- instance, none
function Camp.UpdateBanner(ask)
  if fighting() or fightStarted then
    -- (the state driver hides it; without one it goes clear, its buttons as they are)
    if banner and not driven then banner:SetAlpha(0) end
    return false, "fight"
  end
  local why
  if not ask then
    if not settings().buffs then why = "off"
    elseif snoozeUntil and now() < snoozeUntil then why = "off"
    elseif yes(UnitOnTaxi, "player") or yes(UnitIsDeadOrGhost, "player") then why = "away"
    elseif quiet() then why = "instance" end
  end
  local list, party
  if not why then
    list, party = Camp.Missing(), Camp.PartyMissing()
    if #list == 0 and #party == 0 then why = "none" end
  end
  if why then
    if banner and banner:IsShown() then banner:Hide() end
    return false, why
  end
  layBanner(list, party)
  banner:SetAlpha(1)
  if not banner:IsShown() then
    banner:Show()
    Camp.shows = Camp.shows + 1
  end
  return true
end

-- /qb buffs: the banner now, the X's ten minutes forgotten
function Camp.Command()
  if not fighting() then snoozeUntil = nil end
  local ok, why = Camp.UpdateBanner(true)
  if ok then return end
  QB:Print(why == "fight" and "Not in a fight: type /qb buffs after it." or "No buffs missing.")
end

function Camp.Refresh()
  Camp.UpdateBanner()
  local f = barFrame()
  if quiet() then
    if not fighting() then f:Hide() end
    Camp.visible = 0
    return
  end
  local fight = fighting()
  local st = Camp.State()
  local x, n = 0, 0
  for _, key in ipairs(ORDER) do
    -- (a secure button is never made in a fight)
    local d, b = st[key], icons[key] or (not fight and icon(key)) or nil
    if d and b then
      n = n + 1
      b.icon:SetTexture(d.tex)
      b.icon:SetDesaturated(d.grey and true or false)
      b.icon:SetAlpha(d.grey and 0.55 or 1)
      b.time:SetText(d.time or "")
      b.count:SetText(d.count and d.count > 1 and tostring(d.count) or (key == "bag" and d.count and tostring(d.count) or ""))
      b.glow:SetShown(d.lit and true or false)
      b.edge:SetColorTexture(d.lit and 1 or 0, d.lit and 0.75 or 0, d.lit and 0.2 or 0, 1)
      if d.cd then b.cd:SetCooldown(d.cd[1], d.cd[2]) else b.cd:SetCooldown(0, 0) end
      b.tip = d.tip
      b.state = d
      if not fight then
        if b:GetAttribute("alt-type1") ~= "noop" then b:SetAttribute("alt-type1", "noop") end -- Alt-click moves the bar, never uses it
        b:SetAttribute("type", d.item and "item" or (d.spell and "spell") or (d.macro and "macro") or nil)
        b:SetAttribute("item", d.item and ("item:" .. d.item) or nil)
        b:SetAttribute("spell", d.spell)
        b:SetAttribute("macrotext", d.macro) -- (the sit icon's /sit: the game's own slash command, as a macro of yours)
        b:ClearAllPoints()
        b:SetPoint("LEFT", f, "LEFT", x, 0)
        b:Show()
      end
      x = x + SIZE + GAP
    elseif b and not fight then
      b:Hide()
    end
  end
  if not fight then
    f:SetSize(math.max(SIZE, x - GAP), SIZE)
    f:SetShown(n > 0 and QB:Settings().campBar ~= false)
  end
  f:SetAlpha(fight and 0.45 or 1)
  Camp.visible = (QB:Settings().campBar ~= false) and n or 0
end

function Camp.CooldownLeft()
  if not campAt then return 0 end
  return math.max(0, Camp.CampCD() - (now() - campAt))
end

-- a campfire is here: yours lit, or one under your Interact key
function Camp.OnFire()
  fireAt = now()
  Camp.Refresh()
end

-- the camp buffs carry their feature's name, as far as players' games have shown
function Camp.IsCampBuff(name)
  for _, e in pairs(QB.Data.CAMP or {}) do if e.t == "feature" and e.n == name then return true end end
  return false
end

local KIT, FEATURE = {}, {}
local function index()
  for id, e in pairs(QB.Data.CAMP or {}) do
    if e.sp then
      if e.t == "kit" then KIT[e.sp] = id elseif e.t == "feature" then FEATURE[e.sp] = id end
    end
  end
  KIT[Camp.FIRE_SPELL] = true -- Basic Campfire, cast
end

function Camp.OnEvent(event, a1, a2, a3)
  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    if plain(a1) ~= "player" then return end
    local sp = plain(a3)
    -- (a kit's fire: when and where, for its 15 minutes)
    if KIT[sp] and KIT[sp] ~= true then litAt, litPos = now(), QB.API.WorldPosition() end
    if KIT[sp] then Camp.OnFire() end
    if FEATURE[sp] then campAt = now(); Camp.Refresh() end
  elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
    local name = plain(UnitName and UnitName("softinteract"))
    local guid = plain(UnitGUID and UnitGUID("softinteract"))
    if type(name) == "string" and type(guid) == "string" and guid:find("^GameObject") and name:lower():find("campfire", 1, true) then
      if not fireAt or now() - fireAt > 60 then Camp.OnFire() end
    end
  elseif event == "PLAYER_UPDATE_RESTING" or event == "GROUP_ROSTER_UPDATE" then
    Camp.UpdateBanner()
  elseif event == "UNIT_AURA" then
    if plain(a1) ~= "player" then return end
    Camp.UpdateBanner()
    -- out of a fight, the bar looks again within a moment: a fire near, the minute by it, Camp Benefits (one look for
    -- a burst of these)
    local f = Camp.frame
    if f and not fighting() then f.elapsed = math.max(f.elapsed or 0, TICK - 0.3) end
  elseif event == "PLAYER_REGEN_ENABLED" then
    -- (the banner's buttons made again, now they may be)
    fightStarted = false
    Camp.Refresh()
  elseif event == "PLAYER_REGEN_DISABLED" then
    -- a fight starts: the game sends this before its lockdown, so the banner can still go now (the state driver
    -- hides it if the lockdown came first)
    fightStarted = true
    if banner and banner:IsShown() and not fighting() then banner:Hide() end
    Camp.Refresh()
  elseif event == "BAG_UPDATE_DELAYED" then
    Camp.Refresh()
  elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
    Camp.NoteMerchant()
  elseif event == "PLAYER_ENTERING_WORLD" then
    lastMove = now()
    Camp.Refresh()
  end
end

function Camp:Init()
  if self.frame then return end
  index()
  local f = CreateFrame("Frame")
  self.frame = f
  f.elapsed = 0
  f:SetScript("OnEvent", QB.Safe(function(_, event, ...) Camp.OnEvent(event, ...) end, "reminders"))
  f:SetScript("OnUpdate", QB.Safe(function(self, dt)
    self.elapsed = self.elapsed + (dt or 0)
    if self.elapsed < TICK then return end
    self.elapsed = 0
    Camp.Refresh()
  end, "camp bar"))
  for _, e in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_SOFT_INTERACT_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                       "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_UPDATE_RESTING", "MERCHANT_SHOW", "MERCHANT_UPDATE",
                       "GROUP_ROSTER_UPDATE" }) do
    pcall(f.RegisterEvent, f, e)
  end
  if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, "UNIT_AURA", "player") else pcall(f.RegisterEvent, f, "UNIT_AURA") end
end
