-- SPDX-License-Identifier: GPL-3.0-or-later
-- The camp (QuestBank's Camp.lua, ported): what a fire, your food, the sleeping bag and the camp items you carry give,
-- each an icon on the bar's camp part. Each adds XP or stats on Forever:
--   sit        a fire near you (the game's Campfire Nearby) and neither Welcoming Campfire nor Camp Benefits on you:
--              "Sit" (a /sit); sitting, the Welcoming aura's countdown. A Cooking Fire object under your Interact key
--              without the aura: "Sit" for 15 s; one that gives nothing after a /sit is left alone for the session
--   place      a fire near you: the camp features you carry and may place (your profession's skill, the item's own red
--              lines) whose buff you lack, the shared hour's cooldown up; the best of each profession, two at most
--   cookfire   a fire near you and no feature waiting to place: an Iron Oven or Cookie's Feast you carry and may use
--              (they need a Cooking Fire, and they spend the features' shared hour: last on the camp part, after Sleep)
--   blueprint  at a fire or in town: the blueprints you carry and may use now; never one for a profession or level
--              you lack (the owner, 2026-11-23)
--   fire       standing still 20 s out of town, no fire near: Light (a kit you may use now) or Make (wood, flint,
--              recipe); else Buy (a cook who has lit a kit and lacks wood or flint: the nearest seller within 10 min, on
--              the game's map pin; in town too within 2 min) or Cook (not a cook, level 5: kits are a cook's, once)
--   eat        not Well Fed, out of towns and instances: the cheapest food you carry and may eat that gives it (with
--              the consumables on, only while the Consumables tab asks for Well Fed in the open world)
--   sleep      the Cozy Sleeping Bag held, Well-Rested under 3 stacks, its cooldown up, out of town, still 20 s
local _, A = ...
local Camp = A.Part("Camp", {})
local B, S, L, D = A.Bar, A.Spells, A.Look, A.Data
local plain, call = A.Plain, A.Call

Camp.FIRE_SPELL, Camp.WOOD, Camp.FLINT, Camp.BASIC_KIT, Camp.KIT_RECIPE = 818, 4470, 4471, 279981, 1229737
Camp.BAG, Camp.BAG_BUFF = 211527, 429959
Camp.NEARBY, Camp.BENEFITS = 1283391, 1229741
Camp.WELCOME = { [1229739] = true, [1289723] = true }
Camp.CAMP_CD = 3600 -- the camp features' shared hour, without Field Guide (Camp.CampCD)
Camp.COOKING = { 18260, 3413, 3102, 2550 }
-- the Well Fed auras (SpellName.csv, 1.60.1.70338: the thirty named "Well Fed", and Forever's Well Fed XP Boost); a
-- localised client is matched by the client's own name of one
Camp.WELL_FED = { [19705] = true, [19706] = true, [19708] = true, [19709] = true, [19710] = true, [19711] = true, [24799] = true,
  [24870] = true, [25694] = true, [25941] = true, [1225778] = true, [1225779] = true, [1225780] = true, [1225782] = true,
  [1248406] = true, [1248420] = true, [1248421] = true, [1248422] = true, [1248688] = true, [1249519] = true, [1249520] = true,
  [1249521] = true, [1249523] = true, [1249907] = true, [1249926] = true, [1249927] = true, [1283082] = true, [1294007] = true,
  [1302064] = true, [1319310] = true, [1243969] = true }
Camp.FED_NAME_SPELL = 1248422

----------------------------------------------------------------------------
-- Legacy (Forever's account perks; QuestBank's Legacy.lua, ported): two change the camp's numbers
--   Field Guide  node 110304 (tree 1188, Adventure)    the features' shared hour less 288 / 612 / 900 s
--   Gourmand     node 110313 (tree 1189, Progression)  Well Fed lasts 33 / 67 / 100% longer: "15 min" reads 20 / 25 / 30
-- Read as the game's own menus read a trait tree: C_Traits.GetConfigIDByTreeID(tree), then GetNodeInfo(config,
-- node).activeRank (what is applied, not what is staged). Kept, and read again after a trait event or a loading screen;
-- a client without Legacy, or a secret answer, reads rank 0: the plain hour, 15 min
----------------------------------------------------------------------------
local PERKS = { fieldGuide = { tree = 1188, node = 110304 }, gourmand = { tree = 1189, node = 110313 } }
local CAMP_LESS, FOOD_MORE = { 288, 612, 900 }, { 1.33, 1.67, 2.0 }
local perkRank
local function readPerks()
  perkRank = {}
  local T = C_Traits
  if not (T and type(T.GetConfigIDByTreeID) == "function" and type(T.GetNodeInfo) == "function") then return end
  for key, p in pairs(PERKS) do
    local cfg = plain(call(T.GetConfigIDByTreeID, p.tree))
    local info = type(cfg) == "number" and plain(call(T.GetNodeInfo, cfg, p.node)) or nil
    local r = type(info) == "table" and plain(info.activeRank) or nil
    if type(r) == "number" and r > 0 then perkRank[key] = math.floor(r) end
  end
end
function Camp.Perk(key)
  if not perkRank then readPerks() end
  return perkRank[key] or 0
end
-- the features' shared cooldown in seconds, and the line that says it
function Camp.CampCD() return Camp.CAMP_CD - (CAMP_LESS[Camp.Perk("fieldGuide")] or 0) end
function Camp.ShareText()
  local cd = Camp.CampCD()
  if cd >= Camp.CAMP_CD then return "All camp features share an hour's cooldown." end
  return string.format("All camp features share a %d-minute cooldown.", math.floor(cd / 60 + 0.5))
end
-- a food's text with Gourmand's minutes: "+3 Strength, 15 min" reads "+3 Strength, 20 min" at rank 1
function Camp.FoodText(s)
  local f = FOOD_MORE[Camp.Perk("gourmand")]
  if type(s) ~= "string" or not f then return s end
  return (s:gsub("(%d+) min", function(m) return math.floor(tonumber(m) * f + 0.5) .. " min" end))
end

----------------------------------------------------------------------------
-- your auras, read once a refresh into kept tables (Buffs.lua reads them too)
----------------------------------------------------------------------------
local myNames, myIds, myPool, readAt, hidden = {}, {}, {}, nil, false
local watchers = {}
function Camp.Watch(fn) watchers[#watchers + 1] = fn end
function Camp.Mine()
  if readAt ~= B.refreshes then
    readAt = B.refreshes
    local _, _, h = S.ReadAuras("player", myNames, myIds, myPool)
    hidden = h
    for _, fn in ipairs(watchers) do fn(myNames, myIds, hidden) end
  end
  return myNames, myIds, hidden
end
-- Well Fed on you: its aura's record (stacks, expiry), else nil
local function fedRec(names, ids)
  for id in pairs(Camp.WELL_FED) do if ids[id] then return ids[id] end end
  if names["Well Fed"] then return names["Well Fed"] end
  local n = L.SpellName(Camp.FED_NAME_SPELL, nil)
  return n and names[n] or nil
end
Camp.FedRec = fedRec
local function fed(names, ids) return fedRec(names, ids) ~= nil end
Camp.Fed = fed
local function itemTex(e, fallback) return e and L.IconPath(e.i, fallback) or fallback end
local function outside(ctx) return not ctx.town and not ctx.inst end

----------------------------------------------------------------------------
-- the fire you lit and the camp features' hour (a kit's or a feature's spell seen on UNIT_SPELLCAST_SUCCEEDED)
----------------------------------------------------------------------------
local litAt, campAt
local KIT, FEATURE = {}, {}
function Camp.CampCooldown(id, t)
  local start, dur = S.ItemCD(id)
  local cd = Camp.CampCD()
  if dur == 0 and campAt and t - campAt < cd then start, dur = campAt, cd end
  if dur > 0 and start + dur - t <= 0 then return 0, 0 end
  return start, dur
end
local profBuf = {}
function Camp.Placeable(bags, profs)
  local out = {}
  for id, e in pairs(D.CAMP or {}) do
    if e.t == "feature" and bags[id] and e.p and (profs[e.p] or 0) >= (e.s or 0) then
      local where = bags[id]
      if S.Usable(id, where.bag, where.slot) then out[#out + 1] = { id = id, e = e } end
    end
  end
  table.sort(out, function(a, b) return (a.e.s or 0) > (b.e.s or 0) or ((a.e.s or 0) == (b.e.s or 0) and a.e.n < b.e.n) end)
  local best, seen = {}, {}
  for _, x in ipairs(out) do if not seen[x.e.p] then seen[x.e.p] = true; best[#best + 1] = x end end
  return best
end
local function fireNear(ids, ctx)
  return ids[Camp.NEARBY] ~= nil or (litAt ~= nil and ctx.t - litAt < 300)
end
-- the features to place at the fire near you, read once a refresh: Placeable's whose buff you lack and that Never does
-- not name, two at most; none while the shared hour runs (one feature on cooldown means all are). Place shows them, and
-- the Cooking Fire items wait while any does: they would spend the hour a feature's buff needs
local waitAt, waitList = nil, {}
local function toPlace(ctx)
  if waitAt == B.refreshes then return waitList end
  waitAt = B.refreshes
  for i = #waitList, 1, -1 do waitList[i] = nil end
  if A.Settings().features == false then return waitList end
  local names, ids = Camp.Mine()
  if not fireNear(ids, ctx) then return waitList end
  for _, x in ipairs(Camp.Placeable(B.Bags(), S.Professions(profBuf))) do
    local on = x.e.b and (ids[x.e.b] or names[x.e.bn or ""] or names[L.SpellName(x.e.b, x.e.bn or "") or ""])
    if not on and #waitList < 2 and not B.Never("place:" .. x.id) then
      local _, du = Camp.CampCooldown(x.id, ctx.t)
      if du > 0 then
        for i = #waitList, 1, -1 do waitList[i] = nil end
        return waitList
      end
      waitList[#waitList + 1] = x
    end
  end
  return waitList
end

----------------------------------------------------------------------------
-- the Cooking Fire objects (CMaNGOS Classic's gameobject_template, GPL-3.0: focus 4 "Cooking Fire"), as runs of entries
----------------------------------------------------------------------------
local FIRE_RUNS = "1766,1798-1799,1801-1822,1824-1860,1864-1895,1898,1901-1906,1908-1909,1911-1912,1914-1917,1922-1923,1926,1928,1930-1932,1936-1941,1943-1954,1957-1962,1964,1967,1969-1973,1975-1977,1979,1981,1984-2007,2056-2057,2062,2334-2336,2658,2661,2663-2667,2719,2732,3084-3085,3089,3200,3220,3246,3249,3251-3254,3256,3258,3260,3262,3264,3266,3270,3286,3296,3298,3301,3303,3306-3308,3310-3311,3315,3636-3639,3656,3716-3718,3722-3723,3760-3761,3769-3770,3772,3797-3804,3815-3819,3839-3845,3847-3853,3855-3857,3888,3890-3911,3937,3943,3945,3951,3960,3962-3964,3967-3968,6286-6292,9847,10388,12665,15068-15069,17284"
local fireLo, fireHi
function Camp.IsCookingFire(entry)
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
local softFire = { entry = nil, at = nil }
local givesNothing, sitAt = {}, nil
local function readSoft()
  softFire.entry, softFire.at = nil, nil
  local Sx = C_Secrets
  if Sx and type(Sx.ShouldUnitIdentityBeSecret) == "function" and A.Yes(Sx.ShouldUnitIdentityBeSecret, "softinteract") then return end
  local guid = plain(call(UnitGUID, "softinteract"))
  if type(guid) ~= "string" or not guid:find("^GameObject") then return end
  local entry = tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
  if entry and Camp.IsCookingFire(entry) and not givesNothing[entry] then
    local at = A.Now()
    softFire.entry, softFire.at = entry, at
    A.After(15.1, function() if softFire.at == at then B.Dirty("camp") end end, "camp: a fire")
  end
end
Camp.SoftFire = softFire

----------------------------------------------------------------------------
-- meals: which foods give Well Fed (D.FOOD, from the items' Use lines), and the ones learned in play: a meal from your
-- bags followed by Well Fed keeps that food, one that ends without it drops it (200 kept, the account's)
----------------------------------------------------------------------------
local MEAL = { Food = true, Drink = true, ["Food & Drink"] = true, Refreshment = true }
local meals, itemSpell = {}, {}
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
local function eating(names) for n in pairs(MEAL) do if names[n] then return true end end return false end
local function mealOn(id, names, ids)
  local sp = id and spellOf(id)
  return (sp ~= nil and ids[sp] ~= nil) or eating(names)
end
local MEAL_LONG = 15
local function foodOK(id)
  local learned = A.Acct().food
  local v = type(learned) == "table" and learned[id] or nil
  if v ~= nil then return v end
  return (D.FOOD or {})[id] ~= nil
end
local function sellPrice(id)
  local get = C_Item and C_Item.GetItemInfo or GetItemInfo
  local price = plain(select(11, call(get, id)))
  return type(price) == "number" and price or 0
end
-- a consumable by the client's own class (Item class 0); a recipe that teaches a food (class 9) is never eaten
local function edible(id)
  local okI, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, id)
  classID = okI and plain(classID) or nil
  return type(classID) ~= "number" or classID == 0
end
-- how well a food's Well Fed fits your role, by its words (D.FOOD[id].w, Buffs.lua's test): 3 it raises what your role
-- wants (or Stamina, Armor: anyone's), 2 the tables don't say (a plain "Well Fed", a meal learned in play), 1 it raises
-- another role's stat (Spell Damage for a warrior), 0 a profession's skill or a zone's speed alone (Spinefin Halibut's
-- Fishing, Sweetpaw Jam's Hyjal)
local function foodFit(id, role)
  local e = (D.FOOD or {})[id]
  local w = e and e.w
  if type(w) ~= "string" then return 2 end
  if w == "" then return 0 end
  local Bf = A.Buffs
  if not (Bf and Bf.FitsWords) then return 2 end
  return Bf.FitsWords(w, role) and 3 or 1
end
-- The food to eat: one you carry that gives Well Fed, a consumable, and that you may eat now (its required level, its
-- red lines: S.Usable). best (a dungeon's Well Fed, Before the pull): the one that fits your role best, then the highest
-- item level; else (the camp's Eat, where any Well Fed adds the XP) the cheapest. Ties: the lowest id
function Camp.BestFood(best)
  local pick, pf, pv
  local role = best and A.Roster and (A.Roster.MyRole()) or nil
  for id, where in pairs(B.Bags()) do
    if foodOK(id) and edible(id) and S.Usable(id, where.bag, where.slot) then
      local f, v = 0, nil
      if best then
        f = foodFit(id, role)
        local _, _, _, ilvl = call(C_Item and C_Item.GetItemInfo or GetItemInfo, id)
        v = -(tonumber(plain(ilvl)) or 0)
      else
        v = sellPrice(id)
      end
      if not pick or f > pf or (f == pf and (v < pv or (v == pv and id < pick))) then pick, pf, pv = id, f, v end
    end
  end
  return pick
end
local function learnFood(id, gave)
  local db = A.Acct()
  if type(db.food) ~= "table" then db.food = {} end
  local n = 0
  for _ in pairs(db.food) do n = n + 1 end
  if n >= 200 and db.food[id] == nil then return end
  db.food[id] = gave
end
local function onCast(_, unit, _, spell)
  if plain(unit) ~= "player" then return end
  local sp = plain(spell)
  if type(sp) ~= "number" then return end
  if KIT[sp] then litAt = A.Now(); A.Char().kitUsed = true end
  if FEATURE[sp] then campAt = A.Now() end
  if A.Fighting() then return end
  for id in pairs(B.Bags()) do
    if spellOf(id) == sp then
      local okI, _, _, _, _, _, classID, subID = pcall(C_Item.GetItemInfoInstant, id)
      if okI and plain(classID) == 0 and plain(subID) == 5 then meals[id] = { at = A.Now(), fed = fed(myNames, myIds) } end
      break
    end
  end
end
Camp.Watch(function(names, ids)
  if next(meals) == nil then return end
  if fed(names, ids) then
    local gave, n = nil, 0
    for id, m in pairs(meals) do if not m.fed then gave, n = id, n + 1 end end
    if n == 1 then learnFood(gave, true) end
    for id in pairs(meals) do meals[id] = nil end
    return
  end
  for id, m in pairs(meals) do
    if mealOn(id, names, ids) then m.on = true
    elseif m.on or A.Now() - m.at > 3 then
      if A.Now() - m.at >= MEAL_LONG then learnFood(id, false) end
      meals[id] = nil
    end
  end
end)

----------------------------------------------------------------------------
-- the providers
----------------------------------------------------------------------------
B.Add({ key = "sit", part = "camp", order = 10, groups = { "camp" }, timed = true,
  read = function(add, ctx)
    local names, ids = Camp.Mine()
    if ids[Camp.BENEFITS] or A.Yes(IsMounted) then return end
    local wel
    for id in pairs(Camp.WELCOME) do if ids[id] then wel = ids[id] end end
    local near = ids[Camp.NEARBY]
    if wel then
      sitAt = nil
      local left = wel.exp and math.max(0, wel.exp - ctx.t) or nil
      local rec = add()
      rec.tex, rec.lit = wel.icon or (near and near.icon) or itemTex(D.CAMP[Camp.BASIC_KIT], 135805), true
      rec.word = left and string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60)) or "Sit"
      rec.timed = left ~= nil
      B.Click(rec, "macro", "/sit")
      rec.name, rec.why, rec.clickWord = "Welcoming Campfire", "Stay put: Camp Benefits once the minute is up.", "sit down again"
      return
    end
    local soft = not near and softFire.entry and softFire.at and ctx.t - softFire.at < 15
    if sitAt and softFire.entry and ctx.t - sitAt >= 10 then
      givesNothing[softFire.entry] = true
      softFire.entry, sitAt, soft = nil, nil, false
    end
    if not (near or soft) then return end
    local rec = add()
    rec.tex = (near and near.icon) or itemTex(D.CAMP[Camp.BASIC_KIT], 135805)
    rec.lit, rec.word = true, "Sit"
    B.Click(rec, "macro", "/sit")
    rec.name, rec.why, rec.clickWord = "Sit by the fire", "A minute sitting by it gives Camp Benefits for an hour: the buffs of its camp features.", "sit down"
  end,
  used = function()
    if not softFire.entry then return end
    local at = A.Now()
    sitAt = at
    A.After(10.1, function() if sitAt == at then B.Dirty("camp") end end, "camp: a fire")
  end,
})

B.Add({ key = "place", part = "camp", order = 20, groups = { "camp" },
  read = function(add, ctx)
    for _, x in ipairs(toPlace(ctx)) do
      local rec = add()
      rec.key = "place" .. x.id
      rec.never, rec.neverName = "place:" .. x.id, x.e.n
      rec.tex, rec.lit, rec.word = itemTex(x.e, 134400), true, "Place"
      B.Click(rec, "item", x.id)
      rec.name = x.e.n
      rec.why = (x.e.g and (x.e.g .. " while you sit by it. ") or "") .. Camp.ShareText()
      rec.clickWord = "place it at this fire"
    end
  end,
})

-- (after Eat and Sleep, so the camp part's four keep them; and only with no feature waiting: the oven and the feast
-- spend the same shared hour, and the hour is a feature's buff)
B.Add({ key = "cookfire", part = "camp", order = 55, groups = { "camp" },
  read = function(add, ctx)
    if A.Settings().features == false then return end
    local _, ids = Camp.Mine()
    if not (ids[Camp.NEARBY] or (softFire.entry and softFire.at and ctx.t - softFire.at < 15)) then return end
    if #toPlace(ctx) > 0 then return end
    local bags = B.Bags()
    for id, e in pairs(D.COOKFIRE or {}) do
      local where = bags[id]
      if where and S.Usable(id, where.bag, where.slot) then
        local _, du = Camp.CampCooldown(id, ctx.t)
        if du == 0 then
          local rec = add()
          rec.key = "cookfire" .. id
          rec.never, rec.neverName = "cookfire:" .. id, e.n
          rec.tex, rec.lit, rec.word = itemTex(e, 134400), true, "Place"
          B.Click(rec, "item", id)
          rec.name, rec.clickWord = e.n, "place it at this fire"
          rec.why = (e.g and ("For " .. e.g .. ". ") or "") .. Camp.ShareText()
        end
      end
    end
  end,
})

-- blueprints: one icon for the ones you may use now, the first on its click, the rest in its tooltip
local bpList = {}
B.Add({ key = "blueprint", part = "camp", order = 28, groups = { "camp" },
  read = function(add, ctx)
    if A.Settings().blueprints == false or ctx.inst then return end
    local _, ids = Camp.Mine()
    if not (ids[Camp.NEARBY] or ctx.town) then return end
    for i = #bpList, 1, -1 do bpList[i] = nil end
    local bags, profs = B.Bags(), S.Professions(profBuf)
    for id, e in pairs(D.BLUEPRINT or {}) do
      local where = bags[id]
      if where and (not e.p or (profs[e.p] or 0) >= (e.s or 0)) and S.Usable(id, where.bag, where.slot) then bpList[#bpList + 1] = id end
    end
    if #bpList == 0 then return end
    table.sort(bpList)
    local first = bpList[1]
    local e = D.BLUEPRINT[first]
    local rec = add()
    rec.tex, rec.lit, rec.word, rec.count = L.ItemIcon(first, itemTex(e, 134400)), true, "Craft", #bpList
    B.Click(rec, "item", first)
    rec.never, rec.neverName = "blueprint", "Blueprints"
    rec.name = #bpList == 1 and ("Blueprint: " .. e.n) or (#bpList .. " blueprints you can use")
    rec.why = "Crafts a camp item for your profession."
    rec.clickWord = "use Blueprint: " .. e.n
  end,
  tip = function(tt)
    local INK = A.Look.C.INK
    for i = 1, math.min(6, #bpList) do
      local e = D.BLUEPRINT[bpList[i]]
      tt:AddLine(e.n .. (e.p and (" (" .. e.p .. " " .. (e.s or 0) .. ")") or ""), INK[1], INK[2], INK[3])
    end
  end,
})

local function cookSpell()
  for _, id in ipairs(Camp.COOKING) do if S.Knows(id) then return id end end
  return nil
end
-- the campfire kit to light: the best you carry and may use (its Cooking skill, the item's red line: S.Usable), none
-- while the kits' cooldown runs (the three kits' spells share one 5-minute category: one on cooldown means all are)
local function kitCarried()
  local bags = B.Bags()
  local best, be
  for id, e in pairs(D.CAMP or {}) do
    local where = e.t == "kit" and bags[id]
    if where and S.Usable(id, where.bag, where.slot) and (not be or (e.s or 0) > (be.s or 0)) then best, be = id, e end
  end
  if best then
    local st, du = S.ItemCD(best)
    if du > 0 and st + du > A.Now() then return nil end
  end
  return best, be
end
Camp.KitCarried = kitCarried
local function kitHeld()
  local bags = B.Bags()
  for id, e in pairs(D.CAMP or {}) do if e.t == "kit" and bags[id] then return true end end
  return false
end

----------------------------------------------------------------------------
-- Simple Wood and Flint and Tinder, for a cook who has lit a kit and now carries none and not both goods to make one
-- (QuestBank's Wood, ported): who sells them. The merchants you open that sell either are noted with where they stand
-- (CuteAurasDB.acct.sell[npc id] = { n = name, m = uiMap, x, y = the place on it (0 to 1), g = goods (1 wood, 2 flint,
-- 3 both), at }, 40 kept, the longest unseen let go); D.CAMP_SELL's sellers of your side fill in, said to be Classic
-- data until a game of yours has seen the seller. The client's own C_Map.GetWorldPosFromMapPos puts a seller and you in
-- one continent's yards; the minutes are on foot as the crow flies (7 yards a second, roads 1.3 times the line), a
-- Classic seller's counted half again and one more, so one seen in play wins at about the same distance. A seller of
-- all you need comes before one of some. Its click: the game's own map pin on the seller (C_Map.SetUserWaypoint),
-- tracked (C_SuperTrack.SetSuperTrackedUserWaypoint): the game's arrow and distance on your screen
----------------------------------------------------------------------------
local MAX_SELLERS, RUN, DETOUR = 40, 7, 1.3
Camp.SEED_NOTE = "Classic data, may have moved."
local function xyOf(v)
  v = plain(v)
  if type(v) ~= "table" then return nil end
  local x, y
  if type(v.GetXY) == "function" then
    local ok, a, b = pcall(v.GetXY, v)
    if ok then x, y = plain(a), plain(b) end
  else
    x, y = plain(v.x), plain(v.y)
  end
  if type(x) ~= "number" or type(y) ~= "number" then return nil end
  return x, y
end
-- a place on a map (0 to 1) in its continent's yards: continent, x, y; nil when the client can't say
local function worldOf(m, x, y)
  local M = C_Map
  if not (M and type(M.GetWorldPosFromMapPos) == "function" and type(CreateVector2D) == "function") then return nil end
  local ok, cont, pos = pcall(M.GetWorldPosFromMapPos, m, CreateVector2D(x, y))
  cont = ok and plain(cont) or nil
  if type(cont) ~= "number" then return nil end
  local wx, wy = xyOf(pos)
  if not wx then return nil end
  return cont, wx, wy
end
-- where you stand: your map and the place on it (0 to 1); nil in an instance or on a secret answer
local function myPlace()
  local M = C_Map
  if not (M and type(M.GetBestMapForUnit) == "function" and type(M.GetPlayerMapPosition) == "function") then return nil end
  local m = plain(call(M.GetBestMapForUnit, "player"))
  if type(m) ~= "number" then return nil end
  local x, y = xyOf(call(M.GetPlayerMapPosition, m, "player"))
  if not x then return nil end
  return m, x, y
end
local function sellDB()
  local acct = A.Acct()
  if type(acct.sell) ~= "table" then acct.sell = {} end
  return acct.sell
end
local worldAt = {} -- [seller's key] = { continent, x, y }, asked of the client once a session (false: it can't say)
-- the merchant window open (MERCHANT_SHOW, MERCHANT_UPDATE as its wares come in): one that sells Simple Wood or Flint and
-- Tinder is noted with where you stand; one that sells neither (any more) let go
function Camp.NoteMerchant()
  if type(GetMerchantNumItems) ~= "function" or type(GetMerchantItemID) ~= "function" then return end
  local guid = plain(call(UnitGUID, "npc"))
  local npc = type(guid) == "string" and guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") or nil
  if not npc then return end
  local n = plain(call(GetMerchantNumItems))
  if type(n) ~= "number" then return end
  local g = 0
  for i = 1, math.min(n, 200) do
    local id = plain(call(GetMerchantItemID, i))
    if id == Camp.WOOD and g % 2 == 0 then g = g + 1 elseif id == Camp.FLINT and g < 2 then g = g + 2 end
  end
  local db = sellDB()
  worldAt[npc] = nil
  if g == 0 then db[npc] = nil return end
  local m, x, y = myPlace()
  if not m then return end
  local name = plain(call(UnitName, "npc"))
  db[npc] = { n = type(name) == "string" and name ~= "" and name or nil, m = m, x = math.floor(x * 10000 + 0.5) / 10000,
              y = math.floor(y * 10000 + 0.5) / 10000, g = g, at = time and time() or 0 }
  local count, oldest = 0, nil
  for k, e in pairs(db) do
    if type(e) ~= "table" then db[k] = nil
    else
      count = count + 1
      if not oldest or (e.at or 0) < (db[oldest].at or 0) then oldest = k end
    end
  end
  if count > MAX_SELLERS and oldest then db[oldest] = nil end
end
-- D.CAMP_SELL's sellers of your side, as sellers are kept (made once a session; their key the NPC's id)
local seedList, seedSide
local function seed()
  local fac = plain(call(UnitFactionGroup, "player"))
  local side = fac == "Alliance" and 1 or fac == "Horde" and 2 or 0
  if seedList and seedSide == side then return seedList end
  seedList, seedSide = {}, side
  for _, r in ipairs(D.CAMP_SELL or {}) do
    if side > 0 and r[10] % (side * 2) >= side then
      seedList[#seedList + 1] = { key = tostring(r[1]), n = r[2], m = r[6], x = r[7] / 100, y = r[8] / 100, g = r[9], seed = true }
    end
  end
  return seedList
end
-- the nearest seller of what you need (goods: 1 Simple Wood, 2 Flint and Tinder, 3 both) on your continent: the seller
-- and its minutes away, or nil
function Camp.NearestSeller(need)
  local m, x, y = myPlace()
  if not m then return nil end
  local cont, wx, wy = worldOf(m, x, y)
  if not cont then return nil end
  local needWood, needFlint = need % 2 == 1, need >= 2
  local best, bm, bScore, bMiss
  local function look(key, e)
    if type(e) ~= "table" or type(e.g) ~= "number" or type(e.m) ~= "number" or type(e.x) ~= "number" or type(e.y) ~= "number" then return end
    local wood, flint = e.g % 2 == 1, e.g >= 2
    if not ((needWood and wood) or (needFlint and flint)) then return end
    local miss = ((needWood and not wood) and 1 or 0) + ((needFlint and not flint) and 1 or 0)
    local w = worldAt[key]
    if w == nil then
      local c, ex, ey = worldOf(e.m, e.x, e.y)
      w = c and { c, ex, ey } or false
      worldAt[key] = w
    end
    if not w or w[1] ~= cont then return end
    local mins = math.sqrt((w[2] - wx) ^ 2 + (w[3] - wy) ^ 2) * DETOUR / RUN / 60
    local score = e.seed and (mins * 1.5 + 1) or mins
    if not best or miss < bMiss or (miss == bMiss and score < bScore) then best, bm, bScore, bMiss = e, mins, score, miss end
  end
  local db = sellDB()
  for key, e in pairs(db) do look(key, e) end
  for _, e in ipairs(seed()) do if not db[e.key] then look(e.key, e) end end
  return best, bm
end
-- a seller on the game's own map pin, tracked: true when the game set it
function Camp.Pin(e)
  local M, ST = C_Map, C_SuperTrack
  if not (e and M and type(M.SetUserWaypoint) == "function" and UiMapPoint and type(UiMapPoint.CreateFromCoordinates) == "function") then return false end
  if type(M.CanSetUserWaypointOnMap) == "function" and not A.Yes(M.CanSetUserWaypointOnMap, e.m) then return false end
  local okP, point = pcall(UiMapPoint.CreateFromCoordinates, e.m, e.x, e.y)
  if not okP or not point then return false end
  local ok, set = pcall(M.SetUserWaypoint, point)
  if not ok or plain(set) == false then return false end
  if ST and type(ST.SetSuperTrackedUserWaypoint) == "function" then pcall(ST.SetSuperTrackedUserWaypoint, true) end
  return true
end
local function pinSeller(rec)
  local e = rec.seller
  if not Camp.Pin(e) then A.Say((e and e.n or "The seller") .. ": the game would not put a pin on that map.") end
end

B.Add({ key = "fire", part = "camp", order = 30, groups = { "camp" },
  read = function(add, ctx)
    local _, ids = Camp.Mine()
    if ids[Camp.BENEFITS] or ids[Camp.NEARBY] or ctx.inst then return end
    local moment = ctx.still and not ctx.town
    if not (moment or ctx.town) then return end
    local cook = cookSpell() ~= nil
    local wood, flint = S.Count(Camp.WOOD) > 0, S.Count(Camp.FLINT) > 0
    local kit, ke
    if moment then kit, ke = kitCarried() end
    local rec
    if kit then
      rec = add()
      rec.tex, rec.lit, rec.word, rec.count = itemTex(ke, 134400), true, "Light", S.Count(kit)
      B.Click(rec, "item", kit)
      rec.name = ke.n
      rec.why = string.format("Holds %d camp feature%s, and its fire gives Camp Benefits.", ke.cap or 3, (ke.cap or 3) == 1 and "" or "s")
      rec.clickWord = "light it"
    elseif moment and S.Knows(Camp.FIRE_SPELL) and wood and select(2, S.SpellCD(Camp.FIRE_SPELL)) == 0 then
      rec = add()
      rec.tex, rec.lit, rec.word, rec.count = L.SpellIcon(Camp.FIRE_SPELL, 135805), true, "Light", S.Count(Camp.WOOD)
      B.Click(rec, "spell", Camp.FIRE_SPELL)
      rec.name, rec.why, rec.clickWord = L.SpellName(Camp.FIRE_SPELL, "Basic Campfire"), "Lights a campfire from one Simple Wood.", "light it"
    elseif moment and wood and flint and S.Knows(Camp.KIT_RECIPE) and cook then
      rec = add()
      rec.tex, rec.lit, rec.word = itemTex(D.CAMP[Camp.BASIC_KIT], 134400), true, "Make"
      B.Click(rec, "spell", cookSpell())
      rec.name, rec.why, rec.clickWord = "Basic Campfire Kit", "You carry Simple Wood and Flint and Tinder: make one in your Cooking window.", "open Cooking"
    elseif cook and A.Char().kitUsed and not kitHeld() and not (wood and flint) then
      -- (Buy: the nearest seller within 10 minutes when you stop out of town; in town only within 2, where the pin is a
      -- short walk)
      local need = (not wood and not flint) and 3 or (wood and 2 or 1)
      local e, m = Camp.NearestSeller(need)
      if e and m <= 10 and (moment or m <= 2) then
        rec = add()
        rec.key, rec.never, rec.neverName = "wood", "wood", "Wood"
        rec.tex, rec.lit, rec.word = L.ItemIcon(need == 2 and Camp.FLINT or Camp.WOOD, "Interface\\Icons\\inv_tradeskillitem_01"), false, "Buy"
        rec.seller, rec.go = e, pinSeller
        rec.name = need == 2 and "Flint and Tinder" or "Simple Wood"
        local mins = math.max(1, math.floor(m + 0.5))
        -- (what the seller has of what you need: both, the one, or the one of two it sells)
        local what = need ~= 3 and "it" or (e.g == 3 and "both" or (e.g == 1 and "Simple Wood" or "Flint and Tinder"))
        rec.why = ((need == 3) and "A Basic Campfire Kit takes Simple Wood and Flint and Tinder: you have neither. "
          or (need == 2 and "You have no Flint and Tinder. " or "You have no Simple Wood. "))
          .. string.format("%s sells %s, about %d min away.", e.n or "A merchant you have seen", what, mins)
          .. (e.seed and (" " .. Camp.SEED_NOTE) or "")
        rec.clickWord = "pin the seller on your map"
      end
    elseif not cook and moment and (ctx.level or 1) >= 5 then
      -- (Cook: once, for ten minutes from the first time it shows; then never again on this character)
      local db = A.Char()
      local now = time and time() or 0
      if not db.cookAt or now - db.cookAt <= 600 then
        db.cookAt = db.cookAt or now
        rec = add()
        rec.key, rec.never, rec.neverName = "cook", "cook", "Cook"
        rec.tex, rec.lit, rec.word = itemTex(D.CAMP[Camp.BASIC_KIT], 134400), false, "Cook"
        rec.name, rec.why = "Campfire kits", "Cooks make campfire kits: Basic Campfire Kit at Cooking 1. A cooking trainer teaches Cooking."
      end
    end
    if rec and moment then rec.pause = true end
  end,
})

local lastMeal
-- (read again as Before the pull starts and ends: at a ready check its own Eat, your role's best food, is the one)
B.Add({ key = "eat", part = "camp", order = 40, groups = { "camp", "pull" },
  read = function(add, ctx)
    local names, ids = Camp.Mine()
    if fed(names, ids) or not outside(ctx) then lastMeal = nil return end
    -- (the consumables on, Well Fed off for the open world in their tab: no Eat; consumables off, this follows Camp)
    local Cn = A.Consume
    if Cn and Cn.On() and not Cn.Asks("fed", "solo") then return end
    -- (a ready check out in the world: Before the pull asks for food itself, so one Eat shows, not two)
    if ctx.pull and Cn and Cn.On() and A.Settings().pull ~= false and not B.Never("pullfood") and Camp.BestFood(true) then return end
    local id = Camp.BestFood(false)
    if not id and lastMeal and mealOn(lastMeal, names, ids) then id = lastMeal end
    if not id then return end
    local e = (D.FOOD or {})[id]
    local rec = add()
    rec.tex = itemTex(e, L.ItemIcon(id, 133945))
    rec.lit, rec.word, rec.count = true, "Eat", S.Count(id)
    B.Click(rec, "item", id)
    rec.name = e and e.n or L.ItemName(id, "Food")
    -- (its Never is Well Fed's, every food and place: the menu says so)
    rec.never, rec.neverName = "eat", "Well Fed"
    rec.why = Camp.FoodText(e and e.g or "Well Fed") .. ": Well Fed adds XP on Forever."
    rec.clickWord = "eat it"
  end,
  used = function(rec) lastMeal = rec.click and rec.click.item end,
})

B.Add({ key = "sleep", part = "camp", order = 50, groups = { "camp" },
  read = function(add, ctx)
    if not (B.Bags()[Camp.BAG] and ctx.still and outside(ctx)) then return end
    local names, ids = Camp.Mine()
    local r = ids[Camp.BAG_BUFF]
    local stacks = (r and r.n) or (names["Well-Rested"] and names["Well-Rested"].n) or 0
    if stacks >= 3 then return end
    local st, du = S.ItemCD(Camp.BAG)
    if du > 0 and st + du > ctx.t then return end
    local rec = add()
    rec.tex, rec.lit, rec.word, rec.count = itemTex(D.CAMP[Camp.BAG], 133662), true, "Sleep", stacks
    B.Click(rec, "item", Camp.BAG)
    rec.name, rec.why, rec.clickWord = "Cozy Sleeping Bag", string.format("Well-Rested %d/3: a minute in the bag adds a stack of bonus XP.", stacks), "unfurl it"
    rec.pause = true
  end,
})

function Camp:Init()
  for id, e in pairs(D.CAMP or {}) do
    if e.sp then if e.t == "kit" then KIT[e.sp] = id elseif e.t == "feature" then FEATURE[e.sp] = id end end
  end
  -- (an Iron Oven or Cookie's Feast placed spends the features' shared hour too)
  for id, e in pairs(D.COOKFIRE or {}) do if e.sp then FEATURE[e.sp] = id end end
  KIT[Camp.FIRE_SPELL] = true
  A.OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, onCast)
  A.On("PLAYER_SOFT_INTERACT_CHANGED", function() readSoft() end)
  A.On("MERCHANT_SHOW", function() Camp.NoteMerchant() end)
  A.On("MERCHANT_UPDATE", function() Camp.NoteMerchant() end)
  -- (Legacy's ranks read again after a trait change or a loading screen)
  for _, ev in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "TRAIT_NODE_CHANGED", "PLAYER_ENTERING_WORLD" }) do
    A.On(ev, function() perkRank = nil; B.Dirty("camp") end, "camp: legacy")
  end
end
