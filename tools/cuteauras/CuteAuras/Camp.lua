-- SPDX-License-Identifier: GPL-3.0-or-later
-- The camp (QuestBank's Camp.lua, ported): what a fire, your food, the sleeping bag and the camp items you carry give,
-- each an icon on the bar's camp part. Each adds XP or stats on Forever:
--   sit        a fire near you (the game's Campfire Nearby) and neither Welcoming Campfire nor Camp Benefits on you:
--              "Sit" (a /sit); sitting, the Welcoming aura's countdown. A Cooking Fire object under your Interact key
--              without the aura: "Sit" for 15 s; one that gives nothing after a /sit is left alone for the session
--   place      a fire near you: the camp features you carry and may place (your profession's skill, the item's own red
--              lines) whose buff you lack, the shared hour's cooldown up; the best of each profession, two at most
--   cookfire   a fire near you: an Iron Oven or Cookie's Feast you carry and may use (they need a Cooking Fire)
--   blueprint  at a fire or in town: the blueprints you carry and may use now; never one for a profession or level
--              you lack (the owner, 2026-11-23)
--   fire       standing still 20 s out of town, no fire near: Light (a kit you carry) or Make (wood, flint, recipe)
--   eat        not Well Fed, out of towns and instances: the cheapest food you carry that gives it
--   sleep      the Cozy Sleeping Bag held, Well-Rested under 3 stacks, its cooldown up, out of town, still 20 s
local _, A = ...
local Camp = A.Part("Camp", {})
local B, S, L, D = A.Bar, A.Spells, A.Look, A.Data
local plain, call = A.Plain, A.Call

Camp.FIRE_SPELL, Camp.WOOD, Camp.FLINT, Camp.BASIC_KIT, Camp.KIT_RECIPE = 818, 4470, 4471, 279981, 1229737
Camp.BAG, Camp.BAG_BUFF = 211527, 429959
Camp.NEARBY, Camp.BENEFITS = 1283391, 1229741
Camp.WELCOME = { [1229739] = true, [1289723] = true }
Camp.CAMP_CD = 3600
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
    for _, fn in ipairs(watchers) do fn(myNames, myIds) end
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
  if dur == 0 and campAt and t - campAt < Camp.CAMP_CD then start, dur = campAt, Camp.CAMP_CD end
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
function Camp.BestFood(best)
  local pick, pv
  for id in pairs(B.Bags()) do
    if foodOK(id) then
      local v
      if best then
        local _, _, _, ilvl = call(C_Item and C_Item.GetItemInfo or GetItemInfo, id)
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
    if A.Settings().features == false then return end
    local names, ids = Camp.Mine()
    if not fireNear(ids, ctx) then return end
    local shownN = 0
    for _, x in ipairs(Camp.Placeable(B.Bags(), S.Professions(profBuf))) do
      local on = x.e.b and (ids[x.e.b] or names[x.e.bn or ""] or names[L.SpellName(x.e.b, x.e.bn or "") or ""])
      if not on and shownN < 2 then
        local _, du = Camp.CampCooldown(x.id, ctx.t)
        if du > 0 then return end -- (the shared hour: one feature on cooldown means all are)
        shownN = shownN + 1
        local rec = add()
        rec.key = "place" .. x.id
        rec.never, rec.neverName = "place:" .. x.id, x.e.n
        rec.tex, rec.lit, rec.word = itemTex(x.e, 134400), true, "Place"
        B.Click(rec, "item", x.id)
        rec.name = x.e.n
        rec.why = (x.e.g and (x.e.g .. " while you sit by it. ") or "") .. "All camp features share an hour's cooldown."
        rec.clickWord = "place it at this fire"
      end
    end
  end,
})

B.Add({ key = "cookfire", part = "camp", order = 25, groups = { "camp" },
  read = function(add, ctx)
    if A.Settings().features == false then return end
    local _, ids = Camp.Mine()
    if not (ids[Camp.NEARBY] or (softFire.entry and softFire.at and ctx.t - softFire.at < 15)) then return end
    local bags = B.Bags()
    for id, e in pairs(D.COOKFIRE or {}) do
      local where = bags[id]
      if where and S.Usable(id, where.bag, where.slot) then
        local _, du = S.ItemCD(id)
        if du == 0 then
          local rec = add()
          rec.key = "cookfire" .. id
          rec.never, rec.neverName = "cookfire:" .. id, e.n
          rec.tex, rec.lit, rec.word = itemTex(e, 134400), true, "Place"
          B.Click(rec, "item", id)
          rec.name, rec.why, rec.clickWord = e.n, e.g and ("For " .. e.g .. ".") or nil, "place it at this fire"
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
local function kitCarried()
  local bags = B.Bags()
  local best, be
  for id, e in pairs(D.CAMP or {}) do
    if e.t == "kit" and bags[id] and (not be or (e.s or 0) > (be.s or 0)) then best, be = id, e end
  end
  return best, be
end
B.Add({ key = "fire", part = "camp", order = 30, groups = { "camp" },
  read = function(add, ctx)
    local _, ids = Camp.Mine()
    if ids[Camp.BENEFITS] or ids[Camp.NEARBY] or ctx.inst or ctx.town or not ctx.still then return end
    local kit, ke = kitCarried()
    local rec
    if kit then
      rec = add()
      rec.tex, rec.lit, rec.word, rec.count = itemTex(ke, 134400), true, "Light", S.Count(kit)
      B.Click(rec, "item", kit)
      rec.name = ke.n
      rec.why = string.format("Holds %d camp feature%s, and its fire gives Camp Benefits.", ke.cap or 3, (ke.cap or 3) == 1 and "" or "s")
      rec.clickWord = "light it"
    elseif S.Knows(Camp.FIRE_SPELL) and S.Count(Camp.WOOD) > 0 and select(2, S.SpellCD(Camp.FIRE_SPELL)) == 0 then
      rec = add()
      rec.tex, rec.lit, rec.word, rec.count = L.SpellIcon(Camp.FIRE_SPELL, 135805), true, "Light", S.Count(Camp.WOOD)
      B.Click(rec, "spell", Camp.FIRE_SPELL)
      rec.name, rec.why, rec.clickWord = L.SpellName(Camp.FIRE_SPELL, "Basic Campfire"), "Lights a campfire from one Simple Wood.", "light it"
    elseif S.Count(Camp.WOOD) > 0 and S.Count(Camp.FLINT) > 0 and S.Knows(Camp.KIT_RECIPE) and cookSpell() then
      rec = add()
      rec.tex, rec.lit, rec.word = itemTex(D.CAMP[Camp.BASIC_KIT], 134400), true, "Make"
      B.Click(rec, "spell", cookSpell())
      rec.name, rec.why, rec.clickWord = "Basic Campfire Kit", "You carry Simple Wood and Flint and Tinder: make one in your Cooking window.", "open Cooking"
    end
    if rec then rec.pause = true end
  end,
})

local lastMeal
B.Add({ key = "eat", part = "camp", order = 40, groups = { "camp" },
  read = function(add, ctx)
    local names, ids = Camp.Mine()
    if fed(names, ids) or not outside(ctx) then lastMeal = nil return end
    local id = Camp.BestFood(false)
    if not id and lastMeal and mealOn(lastMeal, names, ids) then id = lastMeal end
    if not id then return end
    local e = (D.FOOD or {})[id]
    local rec = add()
    rec.tex = itemTex(e, L.ItemIcon(id, 133945))
    rec.lit, rec.word, rec.count = true, "Eat", S.Count(id)
    B.Click(rec, "item", id)
    rec.name = e and e.n or L.ItemName(id, "Food")
    rec.why = (e and e.g or "Well Fed") .. ": Well Fed adds XP on Forever."
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
  KIT[Camp.FIRE_SPELL] = true
  A.OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, onCast)
  A.On("PLAYER_SOFT_INTERACT_CHANGED", function() readSoft() end)
end
