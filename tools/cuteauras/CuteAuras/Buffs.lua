-- SPDX-License-Identifier: GPL-3.0-or-later
-- Buffs on the bar:
--   self       yours alone (an armor, an aspect, an aura, a shield, Inner Fire), any of its kind counting as on
--   habit      the long buffs you recast on yourself (learned: two recasts within 2 minutes of it running out; forgotten
--              after two lapses), 8 at most; never Righteous Fury
--   weapon     your weapon's poison, oil, stone or imbue, by habit per weapon item (QuestBank's, ported)
--   duty       the group's part: one icon a buff you owe (Assign.lua), its count the members missing it, its word the
--              next one's name; a click buffs them (the group version for three or more of a subgroup or class, with its
--              reagent); a hover lists them all, each a click
--   soulstone  a warlock carrying a soulstone, no healer with one: on the first healer (the k-th warlock the k-th)
--   pull       Before the pull: food, the flasks and elixirs you carry and lack, your weapon
local _, A = ...
local Bf = A.Part("Buffs", {})
local B, S, L, D = A.Bar, A.Spells, A.Look, A.Data
local plain, call = A.Plain, A.Call

local function myClass()
  local ok, _, class = pcall(UnitClass, "player")
  return ok and plain(class) or nil
end

----------------------------------------------------------------------------
-- yours: the class's self buffs, and the ones your habits taught
----------------------------------------------------------------------------
local seen = {} -- [entry key] = the one of its kind last seen on you (it is cast again first)
local function castOne(e)
  local last = seen[e.key]
  for pass = 1, 2 do
    for _, sp in ipairs(e.one) do
      if (pass == 1) == (sp.name == last) then
        for r = #sp.ranks, 1, -1 do if S.Knows(sp.ranks[r]) then return sp.ranks[r], sp end end
      end
    end
  end
  return nil
end
B.Add({ key = "self", part = "mine", order = 100, groups = { "mine" },
  read = function(add, ctx)
    local names, ids, hidden = A.Camp.Mine()
    if hidden then return end
    for _, e in ipairs(D.BUFFS[myClass() or ""] or {}) do
      if e.one then
        local on, sp = S.On(e, names, ids)
        if on then
          if sp then seen[e.key] = sp.name end
        else
          local id, sp2 = castOne(e)
          if id then
            local rec = add()
            rec.key = "self:" .. e.key
            rec.tex, rec.lit = L.SpellIcon(id, sp2.icon), true
            B.Click(rec, "spell", id, "player")
            rec.never, rec.neverName = "buff:" .. e.key, sp2.name
            rec.name, rec.word, rec.clickWord = L.SpellName(id, sp2.name), "Buff", "cast it"
          end
        end
      end
    end
  end,
})

-- habits (QuestBank's Camp.lua learned buffs, per character)
local NEVER_LEARN = { [25780] = true, [407627] = true }
local HABIT_MIN, HABIT_WINDOW, HABIT_MAX = 600, 120, 8
local onMine, ranOut = {}, {}
local classIds
local function classIdSet()
  if classIds then return classIds end
  classIds = {}
  for _, list in pairs(D.BUFFS) do
    for _, e in ipairs(list) do
      for _, sp in ipairs(e.one or { e }) do for _, id in ipairs(sp.ranks or {}) do classIds[id] = true end end
      for _, id in ipairs(e.group or {}) do classIds[id] = true end
      for _, id in ipairs(e.alsoIds or {}) do classIds[id] = true end
    end
  end
  for _, e in pairs(D.BLESS) do for _, id in ipairs(e.ranks) do classIds[id] = true end; for _, id in ipairs(e.group or {}) do classIds[id] = true end end
  return classIds
end
local function habits()
  local c = A.Char()
  if type(c.habit) ~= "table" then c.habit = {} end
  return c.habit
end
local myLong = {}
local function readLong()
  for k in pairs(myLong) do myLong[k] = nil end
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not get then return myLong end
  local ids = classIdSet()
  for i = 1, 60 do
    local ok, a = pcall(get, "player", i, "HELPFUL")
    if not ok or type(a) ~= "table" then break end
    local id, src, dur, exp = plain(a.spellId), plain(a.sourceUnit), plain(a.duration), plain(a.expirationTime)
    if type(id) == "number" and src == "player" and type(dur) == "number" and dur >= HABIT_MIN and dur <= 7200
      and not ids[id] and not NEVER_LEARN[id] and S.Knows(id) then
      myLong[id] = type(exp) == "number" and exp or 0
    end
  end
  return myLong
end
local function watchHabits()
  local mine = readLong()
  local t = A.Now()
  local h = habits()
  for id in pairs(onMine) do if not mine[id] then onMine[id] = nil; ranOut[id] = t end end
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
  for id, out in pairs(ranOut) do
    if t - out > HABIT_WINDOW then
      ranOut[id] = nil
      local e = h[id]
      if type(e) == "table" then e.miss = (e.miss or 0) + 1; if e.miss >= 2 then h[id] = nil end end
    end
  end
end
A.Camp.Watch(function() watchHabits() end)
B.Add({ key = "habit", part = "mine", order = 105, groups = { "mine" },
  read = function(add, ctx)
    local _, ids, hidden = A.Camp.Mine()
    if hidden then return end
    local n = 0
    for id, e in pairs(habits()) do
      if type(e) == "table" and (e.hits or 0) >= 2 and not ids[id] and S.Knows(id) and n < HABIT_MAX then
        n = n + 1
        local rec = add()
        rec.key = "habit:" .. id
        rec.tex, rec.lit = L.SpellIcon(id, 134400), true
        B.Click(rec, "spell", id, "player")
        rec.never, rec.neverName = "buff:" .. id, L.SpellName(id, "Buff")
        rec.name, rec.word, rec.why, rec.clickWord = rec.neverName, "Buff", "You keep this one up.", "cast it"
      end
    end
  end,
})

----------------------------------------------------------------------------
-- your weapon, by habit per weapon item
----------------------------------------------------------------------------
local lastUse = { at = 0 }
local HANDS = { 16, 17 }
local enchanted = {}
local function weaponDB()
  local c = A.Char()
  if type(c.weapon) ~= "table" then c.weapon = {} end
  return c.weapon
end
local function tempEnchant(slot)
  if C_Item and type(C_Item.GetWeaponEnchantInfo) == "function" and Enum and Enum.WeaponSlot then
    local ws = slot == 16 and Enum.WeaponSlot.MainHand or Enum.WeaponSlot.OffHand
    local ok, list = pcall(C_Item.GetWeaponEnchantInfo, ws)
    if ok and type(list) == "table" then
      for _, e in ipairs(list) do if type(e) == "table" and plain(e.hasEnchant) == true then return true end end
      return false
    end
  end
  if type(GetWeaponEnchantInfo) == "function" then
    local ok, mh, _, _, _, oh = pcall(GetWeaponEnchantInfo)
    if ok then return plain(slot == 16 and mh or oh) == true end
  end
  return nil
end
local function weaponIn(slot)
  local id = plain(call(GetInventoryItemID, "player", slot))
  return type(id) == "number" and id or nil
end
local itemAuraOf = {}
local function itemAura(id)
  local v = itemAuraOf[id]
  if v ~= nil then return v or nil end
  v = false
  if C_Item and type(C_Item.GetItemSpell) == "function" then
    local ok, _, sp = pcall(C_Item.GetItemSpell, id)
    sp = ok and plain(sp) or nil
    if type(sp) == "number" then v = sp end
  end
  itemAuraOf[id] = v
  return v or nil
end
local function watchWeapons()
  local db = weaponDB()
  for _, slot in ipairs(HANDS) do
    local on = tempEnchant(slot)
    if on and not enchanted[slot] then
      local w = weaponIn(slot)
      if w and A.Now() - lastUse.at <= 1.5 and (lastUse.item or lastUse.spell) then
        local e = db[w]
        local item, spell = lastUse.item, (not lastUse.item) and lastUse.spell or nil
        if type(e) ~= "table" or e.item ~= item or e.spell ~= spell then e = { item = item, spell = spell, hits = 0 }; db[w] = e end
        e.hits = (e.hits or 0) + 1
      end
    end
    enchanted[slot] = on and true or false
  end
end
B.Add({ key = "weapon", part = "mine", order = 110, groups = { "mine" },
  read = function(add, ctx)
    local db = weaponDB()
    local bags = B.Bags()
    for _, slot in ipairs(HANDS) do
      local w = weaponIn(slot)
      local e = w and db[w]
      if type(e) == "table" and (e.hits or 0) >= 2 and tempEnchant(slot) == false
        and ((e.item and bags[e.item]) or (e.spell and S.Knows(e.spell))) then
        local rec = add()
        rec.key = "weapon" .. slot
        rec.never, rec.neverName = "weapon", "your weapon"
        if e.item then rec.tex = L.ItemIcon(e.item, 134400); B.Click(rec, "item", e.item, nil, slot)
        else rec.tex = L.SpellIcon(e.spell, 134400); B.Click(rec, "spell", e.spell) end
        rec.lit, rec.word = true, "Apply"
        rec.name = slot == 16 and "Your weapon" or "Your off-hand"
        rec.why, rec.clickWord = "Nothing on it: you usually put this on.", "put it on"
      end
    end
  end,
})

----------------------------------------------------------------------------
-- the group's part: the buffs you owe, read out of a fight from each member's auras
----------------------------------------------------------------------------
local unitNames, unitIds, unitPools, unitHidden, unitReadAt = {}, {}, {}, {}, {}
local function auras(unit)
  if unitReadAt[unit] ~= B.refreshes then
    unitReadAt[unit] = B.refreshes
    unitNames[unit] = unitNames[unit] or {}
    unitIds[unit] = unitIds[unit] or {}
    unitPools[unit] = unitPools[unit] or {}
    local _, _, h = S.ReadAuras(unit, unitNames[unit], unitIds[unit], unitPools[unit])
    unitHidden[unit] = h
  end
  return unitNames[unit], unitIds[unit], unitHidden[unit]
end
Bf.Auras = auras
-- a member's state for a duty: has (the buff on them, anyone's), dead, offline, out of sight, out of range
local function state(d, m, spellId)
  local st = {}
  st.off = not A.Yes(UnitIsConnected, m.unit)
  st.dead = A.Yes(UnitIsDeadOrGhost, m.unit)
  st.seen = type(UnitIsVisible) ~= "function" or A.Yes(UnitIsVisible, m.unit)
  if st.off or st.dead or not st.seen then return st end
  local names, ids, hidden = auras(m.unit)
  if hidden then st.unknown = true return st end
  st.has = S.On(d.entry, names, ids) ~= nil
  st.far = spellId and S.InRange(spellId, m.unit) == false or false
  return st
end
Bf.State = state
local function groupCount(d, m, list)
  local n = 0
  for _, x in ipairs(list) do
    if (A.Roster.InRaid() and x.m.sub == m.sub) or not A.Roster.InRaid() then n = n + 1 end
  end
  return n
end
local flyPools = {} -- [duty key] = its flyout's rows, kept
B.Add({ key = "duty", part = "group", order = 200, groups = { "group", "mine" },
  read = function(add, ctx)
    local me = A.MyGUID()
    for _, d in ipairs(A.Assign.duties) do
      if not B.Never("duty:" .. d.key) then
        local missing = {}
        local next
        local flyPool = flyPools[d.key]
        if not flyPool then flyPool = {}; flyPools[d.key] = flyPool end
        local fly = flyPool.list or {}
        flyPool.list = fly
        for i = #fly, 1, -1 do fly[i] = nil end
        for _, m in ipairs(d.targets) do
          local id = S.Best(d.entry, m.level)
          if id then
            local st = state(d, m, id)
            local row = flyPool[#fly + 1]
            if not row then row = {}; flyPool[#fly + 1] = row end
            row.unit, row.guid, row.name, row.class, row.spell, row.tex = m.unit, m.guid, m.me and "You" or m.name, m.class, id, nil
            row.has, row.dead, row.off, row.far, row.glow = st.has, st.dead, st.off, st.far or not st.seen, A.Hands and A.Hands.Glowing(m.guid) or nil
            fly[#fly + 1] = row
            if not (st.has or st.dead or st.off or st.unknown or not st.seen) then
              missing[#missing + 1] = { m = m, id = id, far = st.far }
              if not st.far and not next then next = missing[#missing] end
            end
          end
        end
        -- (in a group a paladin's blessings stay on the bar with none missing, dimmed: their list opens in a fight, where a
        -- Hand's restore is a click on its row)
        if #missing == 0 and d.bless and ctx.group and #fly > 0 then
          local rec = add()
          rec.key = "duty:" .. d.key
          rec.never, rec.neverName = "duty:" .. d.key, d.entry.name
          rec.tex, rec.lit, rec.word = L.SpellIcon(d.entry.ranks[1], d.entry.icon), false, "All on"
          rec.flyout = fly
          rec.name = L.SpellName(d.entry.ranks[1], d.entry.name)
          rec.why = "Everyone you give it to has it. Hover for the list; click a name to bless them again."
        end
        if #missing > 0 then
          local pick = next or missing[1]
          local m = pick.m
          local rec = add()
          rec.key = "duty:" .. d.key
          rec.never, rec.neverName = "duty:" .. d.key, d.entry.name
          rec.tex, rec.lit = L.SpellIcon(d.entry.ranks[1], d.entry.icon), true
          rec.count = #missing
          rec.word, rec.class = m.me and "You" or m.name, m.class
          rec.far = next == nil
          rec.flyout = fly
          rec.name = L.SpellName(d.entry.ranks[1], d.entry.name)
          -- (the group version: Greater for a class whose every member takes this from you, Prayer, Brilliance or Gift
          -- for three or more of a subgroup, its reagent carried)
          local gid = d.entry.group and S.BestGroup(d.entry, m.level)
          local useGroup = false
          if gid and d.entry.reagent and S.Count(d.entry.reagent) > 0 then
            if d.bless then
              local n = 0
              for _, x in ipairs(missing) do if x.m.class == m.class then n = n + 1 end end
              useGroup = A.Settings().greater ~= false and d.greater[m.class or ""] and n >= 3
            else
              useGroup = groupCount(d, m, missing) >= 3
            end
          end
          if useGroup then
            B.Click(rec, "spell", gid, m.unit)
            rec.name = L.SpellName(gid, d.entry.groupName or rec.name)
            rec.clickWord = "cast " .. rec.name .. " on " .. (m.me and "yourself" or m.name)
          else
            B.Click(rec, "spell", pick.id, m.unit)
            rec.clickWord = "buff " .. (m.me and "yourself" or m.name)
          end
          local why = #missing == 1 and "1 member is missing it." or (#missing .. " members are missing it.")
          if d.bless then why = why .. " Cute Auras shares the blessings out among the group's paladins." end
          rec.why = why
        end
      end
    end
  end,
})

-- the warlock's soulstone: one on a healer who has none, the k-th warlock with Cute Auras the k-th healer
local STONE_AURA = { 20707, 20762, 20763, 20764, 20765 }
B.Add({ key = "soulstone", part = "group", order = 210, groups = { "group" },
  read = function(add, ctx)
    if myClass() ~= "WARLOCK" or not ctx.group then return end
    local bags = B.Bags()
    local stone
    for i = #D.SOULSTONE, 1, -1 do if bags[D.SOULSTONE[i]] then stone = D.SOULSTONE[i]; break end end
    if not stone or select(2, S.ItemCD(stone)) > 0 then return end
    local healers, locks = {}, {}
    for _, m in ipairs(A.Roster.members) do
      if m.role == "healer" then healers[#healers + 1] = m end
      if m.class == "WARLOCK" and A.Comm.Running(m.guid) then locks[#locks + 1] = m end
    end
    table.sort(healers, function(a, b) return a.guid < b.guid end)
    table.sort(locks, function(a, b) return a.guid < b.guid end)
    local k
    for i, m in ipairs(locks) do if m.me then k = i end end
    for _, h in ipairs(healers) do
      local _, ids = auras(h.unit)
      for _, id in ipairs(STONE_AURA) do if ids[id] then return end end
    end
    local h = k and healers[k] or healers[1]
    if not h or A.Yes(UnitIsDeadOrGhost, h.unit) then return end
    local rec = add()
    rec.key = "soulstone"
    rec.tex, rec.lit, rec.word, rec.class = L.ItemIcon(stone, 136210), true, h.me and "You" or h.name, h.class
    B.Click(rec, "item", stone, h.unit)
    rec.never, rec.neverName = "soulstone", "Soulstone"
    rec.name, rec.why, rec.clickWord = L.ItemName(stone, "Soulstone"), "No healer has a soulstone.", "put it on " .. h.name
  end,
})

----------------------------------------------------------------------------
-- consumables (the owner, 2026-11-23: "don't forget the Well Fed and potion buffs"). A consumable whose use puts a
-- buff on you for a minute or more (an elixir, a flask, a potion, a scroll, a juju: its C_Item.GetItemSpell aura) is
-- learned as you use it, and kept up by habit once used twice; three times run out and not used again within ten
-- minutes, it is forgotten (30 kept, this character's). Two that take each other's place (B's aura came in the second
-- A's went, as you used B) are one group: the one used last is asked for. Where Settings says (dungeons and raids by
-- default, everywhere, the ready check only, off), out of a fight: a habit missing from you that you carry ("Use"), one
-- under a minute from its end (its countdown); Well Fed inside dungeons and raids (the camp's Eat has the open world)
-- and, anywhere out of town, under two minutes left. Before the pull asks for every one you carry, habit or not
----------------------------------------------------------------------------
local KINDS = { [1] = "Drink", [2] = "Drink", [3] = "Drink", [4] = "Read", [8] = "Use", [0] = "Use" } -- (potion, elixir, flask, scroll, other)
local function kindOf(id)
  local ok, _, _, _, _, _, classID, subID = pcall(C_Item.GetItemInfoInstant, id)
  if not ok or plain(classID) ~= 0 then return nil end
  return KINDS[plain(subID) or -1]
end
Bf.KindOf = kindOf
local function habitsDB()
  local c = A.Char()
  if type(c.consume) ~= "table" then c.consume = {} end
  return c.consume
end
local function pairsDB()
  local a = A.Acct()
  if type(a.pairs) ~= "table" then a.pairs = {} end
  return a.pairs
end
local function groupOf(id)
  local p, g, n = pairsDB(), id, 0
  while p[g] and p[g] < g and n < 64 do g = p[g]; n = n + 1 end
  return g
end
Bf.GroupOf = groupOf
local function learnPair(a, b)
  local p = pairsDB()
  local n = 0
  for _ in pairs(p) do n = n + 1 end
  if n >= 64 then return end
  local ga, gb = groupOf(a), groupOf(b)
  if ga == gb then return end
  p[math.max(ga, gb)] = math.min(ga, gb)
end
-- a consumable's aura on you: by its spell, else its name in your language
local function auraOn(id, names, ids)
  local sp = itemAura(id)
  if not sp then return nil end
  return ids[sp] or names[L.SpellName(sp, "") or ""]
end
Bf.AuraOn = auraOn
local pending = {}  -- [item id] = when you used it (its aura not seen yet)
local onSince = {}  -- [item id] = its aura on at the last look
local offAt = {}    -- [item id] = when its aura ran out
local function watchConsumables(names, ids)
  local t = A.Now()
  local h = habitsDB()
  local came, went
  -- (a use whose aura came, a minute or more long: one more hit)
  for id, at in pairs(pending) do
    local a = auraOn(id, names, ids)
    if a then
      pending[id] = nil
      if not a.exp or a.exp - t >= 50 then
        local e = h[id]
        if type(e) ~= "table" then
          local n = 0
          for _ in pairs(h) do n = n + 1 end
          if n < 30 then e = { hits = 0, miss = 0 }; h[id] = e end
        end
        if e then e.hits, e.miss, e.spell = (e.hits or 0) + 1, 0, itemAura(id) end
      end
    elseif t - at > 6 then pending[id] = nil end
  end
  for id, e in pairs(h) do
    if type(e) ~= "table" then h[id] = nil
    else
      local on = auraOn(id, names, ids) ~= nil
      if on and not onSince[id] then onSince[id] = t; offAt[id] = nil; came = id end
      if not on and onSince[id] then onSince[id] = nil; offAt[id] = t; went = id end
      -- (run out and not used again within ten minutes: a miss; three, forgotten)
      if not on and offAt[id] and t - offAt[id] > 600 then
        offAt[id] = nil
        e.miss = (e.miss or 0) + 1
        if e.miss >= 3 then h[id] = nil end
      end
    end
  end
  if came and went and came ~= went and t - lastUse.at <= 1.5 and lastUse.item == came then learnPair(came, went) end
end
A.Camp.Watch(watchConsumables)
local function consumeHere(ctx)
  local mode = A.Settings().consume or "instance"
  if mode == "off" or ctx.town then return false end
  return mode == "always" or (mode == "instance" and ctx.inst ~= nil)
end
local function countdown(left) return string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60)) end
-- (a buff crossing its last minute fires no event: one look then, the soonest one scheduled)
local wakeAt
local function wakeFor(at, t)
  if not at or at <= t then return end
  if wakeAt and wakeAt > t and wakeAt <= at then return end
  wakeAt = at
  A.After(at - t + 0.1, function() if wakeAt == at then wakeAt = nil end; B.Dirty("mine") end, "consumables: a countdown")
end
local groupSeen = {}
B.Add({ key = "consume", part = "mine", order = 120, groups = { "mine" }, timed = true,
  read = function(add, ctx)
    if A.Settings().consume == "off" or ctx.pull or ctx.town then return end
    local Camp = A.Camp
    local names, ids, hidden = Camp.Mine()
    if hidden then return end
    -- Well Fed: missing inside a dungeon or raid, or about to end anywhere out of town
    local fedRec = Camp.FedRec(names, ids)
    if type(fedRec) == "table" and fedRec.exp then wakeFor(fedRec.exp - 120, ctx.t) end
    local food = Camp.BestFood(ctx.inst ~= nil)
    if food and not B.Never("eat") then
      local left = type(fedRec) == "table" and fedRec.exp and fedRec.exp - ctx.t or nil
      if (not fedRec and ctx.inst and consumeHere(ctx)) or (left and left > 0 and left < 120) then
        local rec = add()
        rec.key = "food"
        rec.tex, rec.lit, rec.count = L.ItemIcon(food, 133945), true, S.Count(food)
        rec.word = left and countdown(left) or "Eat"
        if left then rec.status, rec.timed = "warn", true end
        B.Click(rec, "item", food)
        rec.never, rec.neverName = "eat", "Eat"
        rec.name = L.ItemName(food, "Food")
        rec.why = left and "Well Fed ends soon: eat again to keep it." or "Not Well Fed."
        rec.clickWord = "eat it"
      end
    end
    if not consumeHere(ctx) then return end
    for k in pairs(groupSeen) do groupSeen[k] = nil end
    local bags = B.Bags()
    -- (a group with one of its auras on asks nothing more than that one's countdown)
    for id in pairs(habitsDB()) do if auraOn(id, names, ids) then groupSeen[groupOf(id)] = id end end
    local n = 0
    for id, e in pairs(habitsDB()) do
      if type(e) == "table" and (e.hits or 0) >= 2 and bags[id] and n < 3 then
        local g = groupOf(id)
        local a = auraOn(id, names, ids)
        local left = a and a.exp and a.exp - ctx.t or nil
        if a and a.exp then wakeFor(a.exp - 60, ctx.t) end
        local show = (not a and not groupSeen[g]) or (left and left > 0 and left < 60)
        if show and not B.Never("consume:" .. g) then
          n = n + 1
          if not a then groupSeen[g] = id end
          local rec = add()
          rec.key = "consume" .. id
          rec.tex, rec.lit, rec.count = L.ItemIcon(id, 134400), true, S.Count(id)
          rec.word = left and countdown(left) or (kindOf(id) or "Use")
          if left then rec.status, rec.timed = "warn", true end
          B.Click(rec, "item", id)
          rec.never, rec.neverName = "consume:" .. g, L.ItemName(id, "this one")
          rec.name = L.ItemName(id, "A consumable")
          rec.why = left and "Its buff ends soon." or "You keep this one up."
          rec.clickWord = "use it"
        end
      end
    end
  end,
})

-- Before the pull: food, and every potion, elixir, flask or scroll you carry whose buff you lack (one of each group)
local flaskBuf = {}
B.Add({ key = "pull", part = "pull", order = 300, groups = { "mine", "pull" },
  read = function(add, ctx)
    if not ctx.pull then return end
    local Camp = A.Camp
    local names, ids = Camp.Mine()
    if not Camp.Fed(names, ids) then
      local id = Camp.BestFood(true)
      if id then
        local rec = add()
        rec.key = "pullfood"
        rec.tex, rec.lit, rec.count, rec.word = L.ItemIcon(id, 133945), true, S.Count(id), "Eat"
        B.Click(rec, "item", id)
        rec.never, rec.neverName, rec.name, rec.clickWord = "pullfood", "Food before the pull", L.ItemName(id, "Well Fed"), "eat it"
      end
    end
    for i = #flaskBuf, 1, -1 do flaskBuf[i] = nil end
    for id in pairs(B.Bags()) do
      local k = kindOf(id)
      if k and k ~= "Use" and itemAura(id) then flaskBuf[#flaskBuf + 1] = id end
    end
    table.sort(flaskBuf)
    for k in pairs(groupSeen) do groupSeen[k] = nil end
    for _, id in ipairs(flaskBuf) do if auraOn(id, names, ids) then groupSeen[groupOf(id)] = true end end
    local shownN = 0
    for _, id in ipairs(flaskBuf) do
      local g = groupOf(id)
      if not groupSeen[g] and shownN < 4 then
        groupSeen[g] = true
        shownN = shownN + 1
        local rec = add()
        rec.key = "flask" .. id
        rec.tex, rec.lit, rec.count, rec.word = L.ItemIcon(id, 134400), true, S.Count(id), kindOf(id)
        B.Click(rec, "item", id)
        rec.never = "flask:" .. g
        rec.name = L.ItemName(id, "Elixir")
        rec.neverName, rec.clickWord = rec.name, "use it"
      end
    end
  end,
})

local function onCast(_, unit, _, spell)
  if plain(unit) ~= "player" then return end
  local sp = plain(spell)
  if type(sp) ~= "number" then return end
  lastUse.at, lastUse.spell, lastUse.item = A.Now(), sp, nil
  if A.Fighting() then return end
  for id in pairs(B.Bags()) do
    if itemAura(id) == sp then
      lastUse.item = id
      if kindOf(id) then pending[id] = A.Now(); A.After(1, function() B.Dirty("mine") end, "consumables: a use") end
      break
    end
  end
end
-- (who walks into range: a look at the group's part every 3 s while you owe something, out of a fight)
local ticker
function Bf:Init()
  ticker = CreateFrame("Frame")
  local acc = 0
  ticker:SetScript("OnUpdate", function(_, dt)
    acc = acc + (dt or 0)
    if acc < 3 then return end
    acc = 0
    if #A.Assign.duties > 0 and not A.Fighting() then B.Dirty("group") end
  end)
  A.OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, onCast)
  A.OnUnit("UNIT_INVENTORY_CHANGED", { "player" }, function() watchWeapons(); B.Dirty("mine") end)
  A.Camp.Watch(function() watchWeapons() end)
end
