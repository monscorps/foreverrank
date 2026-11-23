-- SPDX-License-Identifier: GPL-3.0-or-later
-- Buffs on the bar:
--   self       yours alone (an armor, an aspect, an aura, a shield, Inner Fire), any of its kind counting as on
--   habit      the long buffs you recast on yourself, by the spell's name (any rank; learned: two recasts within 2
--              minutes of it running out; forgotten once asked for twice ten minutes and not cast), 8 at most; never
--              Righteous Fury
--   weapon     your weapon's poison, oil, stone or imbue, by habit per weapon item (QuestBank's, ported)
--   from       a buff a member gives that you lack or carry at a lower rank: greyed, the giver's name, no click
--   duty       the group's part: one icon a buff you owe (Assign.lua), its count the members missing it or with it about
--              to end, its word the next one's name (the shortest time left when it is only ending); a click buffs them
--              (the group version for three or more of a subgroup or class it gives full power, with that rank's
--              reagent); a hover lists them all, each a click
--   soulstone  a warlock carrying a soulstone, no healer with one: on the first healer online and in sight (the k-th
--              warlock the k-th), greyed while out of range
--   pull       Before the pull: food, the flasks, elixirs and scrolls you carry and lack, your habits
local _, A = ...
local Bf = A.Part("Buffs", {})
local B, S, L, D = A.Bar, A.Spells, A.Look, A.Data
local plain, call = A.Plain, A.Call

local function myClass()
  local ok, _, class = pcall(UnitClass, "player")
  return ok and plain(class) or nil
end
-- a time left as the bar writes it: 4:05
local function countdown(left) return string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60)) end
Bf.Countdown = countdown
-- (a buff crossing a mark (its last minute, a reminder's ten minutes) fires no event: one look then, the soonest one
-- scheduled)
local wakeAt
local function wakeFor(at, t)
  if not at or at <= t then return end
  if wakeAt and wakeAt > t and wakeAt <= at then return end
  wakeAt = at
  A.After(at - t + 0.1, function() if wakeAt == at then wakeAt = nil end; B.Dirty("mine") end, "buffs: a mark in time")
end
-- a reminder on the bar this long, the habit not kept up: one miss
local ASK_FOR = 600
-- room for one more learned entry in a kept list: under its cap, or the oldest one used only once let go (so one-offs
-- never fill the list and stop the learning)
local function roomFor(db, cap)
  local n, old, oldAt = 0, nil, nil
  for k, e in pairs(db) do
    n = n + 1
    if type(e) ~= "table" or (e.hits or 0) < 2 then
      local at = type(e) == "table" and tonumber(e.at) or 0
      if not oldAt or at < oldAt then old, oldAt = k, at end
    end
  end
  if n < cap then return true end
  if old == nil then return false end
  db[old] = nil
  return true
end
local function stamp() return type(time) == "function" and time() or 0 end

----------------------------------------------------------------------------
-- yours: the class's self buffs, and the ones your habits taught
----------------------------------------------------------------------------
local seen = {} -- [entry key] = the one of its kind last seen on you (it is cast again first)
-- (a kind already on you from another caster is passed over: another paladin's Devotion Aura asks you for a Retribution
-- Aura, and when every kind you know is someone else's, nothing is asked)
local function castOne(e, names, ids)
  local last = seen[e.key]
  for pass = 1, 2 do
    for _, sp in ipairs(e.one) do
      if (pass == 1) == (sp.name == last) and not (names and S.KindOn(sp, names, ids)) then
        for r = #sp.ranks, 1, -1 do if S.Knows(sp.ranks[r]) then return sp.ranks[r], sp end end
      end
    end
  end
  return nil
end
-- yours on you at a lower rank than you know of that kind (Inner Fire 5, rank 6 learned): the highest rank you know,
-- else nil. By the aura's spell id: one the client hid is never a lower rank
local function upgradeOf(sp, on)
  local id = on and on.id
  if type(id) ~= "number" then return nil end
  local at
  for i, x in ipairs(sp.ranks) do if x == id then at = i end end
  if not at then return nil end
  for r = #sp.ranks, at + 1, -1 do if S.Knows(sp.ranks[r]) then return sp.ranks[r] end end
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
          -- (its own Never, "Never: Upgrade Lightning Shield": a lower rank kept on purpose, the Buff when it is gone
          -- still asked; Never on the Buff hides both. Keyed by the spell its words name, not the kind: Frost Armor's
          -- leaves Ice Armor's, and the account's warlock's Demon Armor, asked)
          local up = sp and not B.Never("buff:" .. e.key) and upgradeOf(sp, on)
          if up then
            local rec = add()
            rec.key = "self:" .. e.key
            rec.tex, rec.lit = L.SpellIcon(up, sp.icon), true
            B.Click(rec, "spell", up, "player")
            rec.never, rec.neverName = "up:" .. sp.name, "Upgrade " .. sp.name
            rec.name, rec.word, rec.clickWord = L.SpellName(up, sp.name), "Upgrade", "cast it"
            rec.why = "Rank " .. S.RankOf(sp, on.id) .. " on you; you know rank " .. S.RankOf(sp, up) .. "."
          end
        else
          local id, sp2 = castOne(e, names, ids)
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

-- habits (QuestBank's Camp.lua learned buffs, per character), kept by the spell's name in the client's language: a rank
-- learned later is the same habit, any rank on you counts, and the click casts the name (the game's highest rank)
local NEVER_LEARN = { [25780] = true, [407627] = true }
local HABIT_MIN, HABIT_WINDOW, HABIT_MAX = 600, 120, 8
local onMine, ranOut, habitAsked = {}, {}, {} -- [spell name]: its rank on you, when it ran out, since when it is asked
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
-- { [spell name] = { id = the rank last seen on you, hits, miss, at = time() of the last hit } }
local movedTo = {}
local function habits()
  local c = A.Char()
  if type(c.habit) ~= "table" then c.habit = {} end
  local h = c.habit
  -- (kept by one rank's id before 0.1.2: moved to its spell's name once)
  if not c.habitByName then
    for k in pairs(movedTo) do movedTo[k] = nil end
    for k, e in pairs(h) do if type(k) == "number" then movedTo[k] = e end end
    for k, e in pairs(movedTo) do
      h[k] = nil
      local n = L.SpellName(k, nil)
      if n and type(e) == "table" and type(h[n]) ~= "table" then e.id = k; h[n] = e end
    end
    -- (and a Never on one by its id, the account's: by the name now)
    local never = A.Settings().never
    for k in pairs(movedTo) do movedTo[k] = nil end
    for k in pairs(never) do
      local id = type(k) == "string" and tonumber(k:match("^buff:(%d+)$"))
      if id then movedTo[k] = id end
    end
    for k, id in pairs(movedTo) do
      local n = L.SpellName(id, nil)
      if n then never["buff:" .. n] = never[k]; never[k] = nil end
    end
    for k in pairs(movedTo) do movedTo[k] = nil end
    c.habitByName = true
  end
  return h
end
local myLong = {} -- [spell name] = its rank on you
local function readLong()
  for k in pairs(myLong) do myLong[k] = nil end
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not get then return myLong end
  local ids = classIdSet()
  for i = 1, 60 do
    local ok, a = pcall(get, "player", i, "HELPFUL")
    if not ok or type(a) ~= "table" then break end
    local id, src, dur = plain(a.spellId), plain(a.sourceUnit), plain(a.duration)
    if type(id) == "number" and src == "player" and type(dur) == "number" and dur >= HABIT_MIN and dur <= 7200
      and not ids[id] and not NEVER_LEARN[id] and S.Knows(id) then
      local n = L.SpellName(id, nil)
      if n then myLong[n] = id end
    end
  end
  return myLong
end
local function watchHabits()
  local mine = readLong()
  local t = A.Now()
  local h = habits()
  for n in pairs(onMine) do if not mine[n] then onMine[n] = nil; ranOut[n] = t end end
  for n, id in pairs(mine) do
    if not onMine[n] then
      onMine[n] = id
      local out = ranOut[n]
      ranOut[n] = nil
      local e = h[n]
      -- (cast while the bar asked for it: the habit is kept up)
      if habitAsked[n] and type(e) == "table" then e.miss = 0 end
      habitAsked[n] = nil
      if out and t - out <= HABIT_WINDOW then
        if type(e) ~= "table" then
          e = nil
          if roomFor(h, HABIT_MAX * 2) then e = { hits = 0, miss = 0 }; h[n] = e end
        end
        if e then e.hits, e.miss, e.at = (e.hits or 0) + 1, 0, stamp() end
      end
      if type(e) == "table" then e.id = id end
    elseif onMine[n] ~= id then
      -- (another rank cast over it while on, an Upgrade's click: the habit's rank is the one on you now)
      onMine[n] = id
      if type(h[n]) == "table" then h[n].id = id end
    end
  end
  -- (not cast again within two minutes of running out: no hit, and no miss either; a miss is a reminder ignored)
  for n, out in pairs(ranOut) do if t - out > HABIT_WINDOW then ranOut[n] = nil end end
end
A.Camp.Watch(function() watchHabits() end)
local askedNow = {}
B.Add({ key = "habit", part = "mine", order = 105, groups = { "mine" },
  read = function(add, ctx)
    local names, ids, hidden = A.Camp.Mine()
    if hidden then return end
    for k in pairs(askedNow) do askedNow[k] = nil end
    local h = habits()
    local n = 0
    for name, e in pairs(h) do
      local id = type(e) == "table" and e.id or nil
      local on = type(id) == "number" and (names[name] or ids[id]) or nil
      -- (yours on you at a lower rank than you know: Upgrade, by the name, which the game casts at its highest rank. The
      -- habit's own rank alone, the one last seen on you (e.id): an elixir's or a piece of gear's aura of the same name,
      -- Water Breathing, is no rank of it)
      -- (its own Never, as yours: "Never: Upgrade Dampen Magic" keeps the Buff when it is gone)
      local own = type(id) == "number" and ids[id] or nil
      local best = own and own.mine and (e.hits or 0) >= 2 and n < HABIT_MAX and not B.Never("buff:" .. name) and S.ByName(name) or nil
      if best and S.Lower(id, best) then
        n = n + 1
        local rec = add()
        rec.key = "habit:" .. name
        rec.tex, rec.lit = L.SpellIcon(best, 134400), true
        B.Click(rec, "spell", name, "player")
        rec.never, rec.neverName = "up:" .. name, "Upgrade " .. name
        rec.name, rec.word, rec.why, rec.clickWord = name, "Upgrade", "On you at a lower rank than you know.", "cast it"
      elseif type(id) == "number" and (e.hits or 0) >= 2 and not on and S.Knows(id) and n < HABIT_MAX then
        -- (asked for ten minutes out of town and not cast: a miss; two, forgotten. In town the clock waits)
        local at = habitAsked[name]
        if ctx.town then at = nil
        elseif not at then at = ctx.t
        elseif ctx.t - at >= ASK_FOR then e.miss = (e.miss or 0) + 1; at = ctx.t end
        habitAsked[name], askedNow[name] = at, true
        if (e.miss or 0) >= 2 then
          h[name], habitAsked[name] = nil, nil
        else
          if at then wakeFor(at + ASK_FOR, ctx.t) end
          n = n + 1
          local rec = add()
          rec.key = "habit:" .. name
          rec.tex, rec.lit = L.SpellIcon(id, 134400), true
          -- (by name: the secure button's spell attribute casts the highest rank you know)
          B.Click(rec, "spell", name, "player")
          rec.never, rec.neverName = "buff:" .. name, name
          rec.name, rec.word, rec.why, rec.clickWord = name, "Buff", "You keep this one up.", "cast it"
        end
      end
    end
    for k in pairs(habitAsked) do if not askedNow[k] then habitAsked[k] = nil end end
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
-- each unit's auras, kept until that unit's own UNIT_AURA (Bf.Stale), a roster change, a fight's end or 15 s: a raid's
-- forty are read again only as they change, not on every refresh (a read hidden by the client is never kept). The
-- group's part reads its members here, and the buffs others give you read yours here: a group refresh never reads
-- yours again (Camp.Mine reads them, and runs its watchers, on every refresh)
----------------------------------------------------------------------------
local AURA_KEEP = 15
local unitNames, unitIds, unitPools, unitHidden, unitReadAt = {}, {}, {}, {}, {}
local function auras(unit)
  local at, t = unitReadAt[unit], A.Now()
  if not at or t - at > AURA_KEEP then
    unitNames[unit] = unitNames[unit] or {}
    unitIds[unit] = unitIds[unit] or {}
    unitPools[unit] = unitPools[unit] or {}
    local _, _, h = S.ReadAuras(unit, unitNames[unit], unitIds[unit], unitPools[unit])
    unitHidden[unit] = h
    unitReadAt[unit] = (not h) and t or nil
  end
  return unitNames[unit], unitIds[unit], unitHidden[unit]
end
Bf.Auras = auras
-- a unit's kept auras out of date (nil: everyone's). You are "player" and your party or raid token both
function Bf.Stale(unit)
  if unit == nil then for k in pairs(unitReadAt) do unitReadAt[k] = nil end return end
  unitReadAt[unit] = nil
  if unit == "player" then
    local me = A.Roster.Me()
    if me and me.unit then unitReadAt[me.unit] = nil end
  elseif A.Yes(UnitIsUnit, unit, "player") then
    unitReadAt.player = nil
  end
end

----------------------------------------------------------------------------
-- buffs others give you (the owner, 2026-11-23: "notified when u are missing buff from others"): one a member of your
-- group gives that is not on you, or is on you at less power than they give at your level, for 30 s out of a fight (at
-- once at a ready check), while that member is online, alive and in sight. In yours, after your own buffs and the
-- consumables (the bar's six cut these first: they have no click), 3 at most: its icon greyed, the giver's name under it
-- in their class colour, no click (it is theirs to cast).
--   who gives it  the buffer the share-out gives you to (Assign.lua: every client's same answer, no message). A buff
--                 no buffer running Cute Auras gives: a member of its class not running it, online, alive and in sight,
--                 whose level has learned a rank you lack, the one whose rank is the strongest, the first by GUID of
--                 those (a rank learned by level only: never a rune's Earth Shield; never Shadow Protection, given only
--                 by a priest running Cute Auras who switched it on; Divine Spirit and Kings are trained in Forever, by
--                 level, not talents as in Classic)
--   blessings     the paladin the share-out gives your class and role each blessing; with none from the share-out and
--                 no blessing on you at all, one "Blessing" naming a paladin not running Cute Auras
--   who wants it  the share-out's own rules: As.Wants (a mana bar for Arcane Intellect and Divine Spirit, a tank for
--                 Thorns) and the blessings' wishes (never Wisdom without a mana bar)
----------------------------------------------------------------------------
local FROM_WAIT, FROM_MAX, FROM_LOOK = 30, 3, 5
local fromSince = {}       -- [key] = since when it is missing with someone to give it (out of a fight, not away)
local fromSeen = {}        -- [key] = true: missing at this read (the other waits are let go)
local fromAsked = {}       -- [key] = true: its wait ended by a ready check
local fromReady = false    -- a ready check since the last read: every wait ends there
local fromList, fromPool = {}, {}
local otherKeys
-- the rank a giver casts on you: the highest of theirs your level takes (Classic's rule: no more than ten levels under
-- the rank's own). Theirs: up to the rank they announced (upto), else each rank their level has learned, by level only.
-- Its id and its place in the ranks (the higher, the stronger)
local function rankFor(entry, upto, giverLevel, myLevel)
  for i = math.min(upto or #entry.ranks, #entry.ranks), 1, -1 do
    local lv = entry.levels and entry.levels[i] or 0
    if (upto or (lv > 0 and lv <= giverLevel)) and lv <= myLevel + 10 then return entry.ranks[i], i end
  end
  return nil
end
-- a member who can give you a buff now: not you, online, alive, in sight. The second answer true for one who could but
-- for sight (coming back into sight fires no event: the 5 s look goes on while they are away)
local function canGive(m)
  if m == nil or m.me or not A.Yes(UnitIsConnected, m.unit) or A.Yes(UnitIsDeadOrGhost, m.unit) then return false, false end
  if type(UnitIsVisible) ~= "function" or A.Yes(UnitIsVisible, m.unit) then return true, false end
  return false, true
end
-- (the next look: at the 30 s mark of the soonest wait, and every 5 s while one waits or shows, or its giver is out of
-- sight, for a giver walking out of sight or back into it; only this provider is read again)
local fromWakeAt
local function fromWake(at, t)
  if fromWakeAt and fromWakeAt > t and fromWakeAt <= at then return end
  fromWakeAt = at
  A.After(at - t + 0.1, function() if fromWakeAt == at then fromWakeAt = nil end; B.Dirty("from") end, "buffs: from others")
end
local function fromWipe()
  for k in pairs(fromSince) do fromSince[k] = nil end
  for k in pairs(fromAsked) do fromAsked[k] = nil end
end
-- its tooltip's line: "Missing. Bprie gives it (shared out by Cute Auras)." (no time: the wait starts again after each
-- fight and while the giver is away, so it is never how long the buff has been gone)
local function fromText(rec)
  local who, e = rec.giverName or "?", rec.entry
  if rec.low then
    local r, isGroup = S.RankOf(e, rec.onId)
    local theirs = isGroup and (L.SpellName(rec.onId, e.groupName) .. " rank " .. r) or ("Rank " .. tostring(r))
    return theirs .. " on you; " .. who .. (rec.shared and " gives rank " or " can give rank ") .. tostring(S.RankOf(e, rec.best))
      .. (rec.shared and " (shared out by Cute Auras)." or ".")
  end
  local miss = rec.any and "No blessing on you." or "Missing."
  if rec.any then return miss .. " " .. who .. " can give one." end
  return miss .. " " .. who .. (rec.shared and " gives it (shared out by Cute Auras)." or " can give it.")
end
Bf.FromText = fromText
-- (quiet: one whose wait ends after Not now on yours stays quiet with it, never bringing back what you put off)
B.Add({ key = "from", part = "mine", order = 125, groups = { "mine", "group", "from" }, quiet = true,
  read = function(add, ctx)
    local As = A.Assign
    local me = A.Roster.Me()
    local ready = fromReady
    fromReady = false
    if A.Settings().others == false or not ctx.group or not me or B.Away() then fromWipe() return end
    -- (yours as kept until your own UNIT_AURA: a group refresh, a member's aura or the 3 s look, reads none again)
    local names, ids, hidden = auras("player")
    -- (an aura the client hid: what is missing can't be told, the waits kept as they are)
    if hidden then return end
    for k in pairs(fromSeen) do fromSeen[k] = nil end
    for i = #fromList, 1, -1 do fromList[i] = nil end
    local nextAt, sight = nil, false
    -- (missing or at less power than best, the rank the giver casts on you: on the list once its wait is over; its giver
    -- out of sight (unseen): no wait, the 5 s look kept going)
    local function consider(key, entry, m, best, shared, any, unseen)
      if B.Never("from:" .. key) then return end
      local on = not any and S.On(entry, names, ids) or nil
      local low = on ~= nil and S.Low(entry, on.id, me.level, best)
      if on and not low then return end
      if unseen then sight = true return end
      fromSeen[key] = true
      local since = fromSince[key] or ctx.t
      fromSince[key] = since
      if ready then fromAsked[key] = true end
      if not fromAsked[key] and ctx.t - since < FROM_WAIT then
        if not nextAt or since + FROM_WAIT < nextAt then nextAt = since + FROM_WAIT end
        return
      end
      local x = fromPool[#fromList + 1]
      if not x then x = {}; fromPool[#fromList + 1] = x end
      x.key, x.entry, x.m, x.best, x.shared, x.any, x.i = key, entry, m, best, shared, any, #fromList + 1
      x.low, x.onId = low or nil, low and on.id or nil
      fromList[#fromList + 1] = x
    end
    -- the buffs given to others, in a fixed order
    if not otherKeys then
      otherKeys = {}
      for key in pairs(As.OTHER) do otherKeys[#otherKeys + 1] = key end
      table.sort(otherKeys)
    end
    for _, key in ipairs(otherKeys) do
      local e = As.OTHER[key]
      if As.Wants(e, me) then
        if As.Shared(key) then
          local g = As.GiverOf(key, me.guid)
          local m = g and A.Roster.ByGUID(g) or nil
          local can, unseen = canGive(m)
          local k = (can or unseen) and As.KnownOf(m)
          local best = k and (k[key] or 0) > 0 and rankFor(e, k[key], nil, me.level) or nil
          if best then consider(key, e, m, best, true, nil, unseen) end
        elseif not e.opt then
          -- (the one whose rank is the strongest, then the first by GUID: a level 30 priest is never named over a 60)
          local on = S.On(e, names, ids)
          local pick, pickBest, pickAt, away, awayBest
          for _, m in ipairs(A.Roster.members) do
            if m.class == e.class and not A.Comm.Running(m.guid) then
              local best, at = rankFor(e, nil, m.level, me.level)
              if best and (not on or S.Low(e, on.id, me.level, best)) then
                local can, unseen = canGive(m)
                if can and (not pick or at > pickAt or (at == pickAt and m.guid < pick.guid)) then pick, pickBest, pickAt = m, best, at
                elseif unseen then away, awayBest = m, best end
              end
            end
          end
          if pick then consider(key, e, pick, pickBest, false)
          elseif away then consider(key, e, away, awayBest, false, nil, true) end
        end
      end
    end
    -- the blessings: the share-out's for your class and role, else one from a paladin not running Cute Auras
    local bucket, given = As.Bucket(me), false
    for _, bk in ipairs(As.BLESS_KEYS) do
      local pg = As.BlesserOf(bucket, bk)
      if pg then
        given = true
        local m = A.Roster.ByGUID(pg)
        local can, unseen = false, false
        if m and (bk ~= "wisdom" or me.mana) then can, unseen = canGive(m) end
        local k = (can or unseen) and As.KnownOf(m)
        local best = k and (k[bk] or 0) > 0 and rankFor(D.BLESS[bk], k[bk], nil, me.level) or nil
        if best then consider("bless:" .. bk, D.BLESS[bk], m, best, true, nil, unseen) end
      end
    end
    if not given then
      local any, lowest = false, nil
      for _, bk in ipairs(As.BLESS_KEYS) do
        local e = D.BLESS[bk]
        if S.On(e, names, ids) then any = true end
        if e.levels[1] > 0 and (not lowest or e.levels[1] < lowest) then lowest = e.levels[1] end
      end
      if not any and lowest then
        local pick, away
        for _, m in ipairs(A.Roster.members) do
          if m.class == "PALADIN" and not A.Comm.Running(m.guid) and m.level >= lowest then
            local can, unseen = canGive(m)
            if can and (not pick or m.guid < pick.guid) then pick = m elseif unseen then away = m end
          end
        end
        -- (its art: your first wish their level has learned (Kings at 20, trained in Forever), else Might, the first a
        -- paladin learns)
        local who = pick or away
        local wish = D.BLESS.might
        for _, w in ipairs(who and As.Wishes(me) or {}) do
          local e = D.BLESS[w]
          if e and e.levels[1] <= who.level then wish = e break end
        end
        if pick then consider("bless", wish, pick, nil, false, true)
        elseif away then consider("bless", wish, away, nil, false, true, true) end
      end
    end
    for k in pairs(fromSince) do if not fromSeen[k] then fromSince[k], fromAsked[k] = nil, nil end end
    -- (missing before a lower rank, then the order looked at)
    table.sort(fromList, function(a, b)
      if (a.low == true) ~= (b.low == true) then return not a.low end
      return a.i < b.i
    end)
    for i = 1, math.min(#fromList, FROM_MAX) do
      local x = fromList[i]
      local rec = add()
      rec.key = "from:" .. x.key
      rec.tex, rec.lit = L.SpellIcon(x.entry.ranks[1], x.entry.icon), false
      rec.word, rec.class = x.m.name, x.m.class
      rec.name = x.any and "Blessing" or L.SpellName(x.entry.ranks[1], x.entry.name)
      rec.never, rec.neverName = "from:" .. x.key, rec.name
      rec.entry, rec.best, rec.shared, rec.any, rec.low, rec.onId = x.entry, x.best, x.shared, x.any, x.low, x.onId
      rec.giverName = x.m.name
      -- (its wait ended by a ready check: shown through Not now on yours, the rest of yours kept quiet)
      rec.loud = fromAsked[x.key] or nil
    end
    if nextAt or sight or #fromList > 0 then fromWake(math.min(nextAt or math.huge, ctx.t + FROM_LOOK), ctx.t) end
  end,
  -- (yours or the bar switched off: the waits and a ready check let go, as when away; back on, 30 s again)
  off = function() fromWipe(); fromReady = false end,
  tip = function(tt, rec)
    local INK = L.C.INK
    tt:AddLine(fromText(rec), INK[1], INK[2], INK[3], true)
  end,
})

----------------------------------------------------------------------------
-- the group's part: the buffs you owe, read out of a fight from each member's auras
----------------------------------------------------------------------------
-- a member's state for a duty: has (the buff on them, anyone's) and left (its seconds, when it ends), dead, offline,
-- out of sight, out of range; weak: on them at less power than spellId, the rank you would cast on them (low, its spell
-- id in onId). Into st when given (a kept table), else a new one
local function state(d, m, spellId, st)
  st = st or {}
  st.unknown, st.has, st.left, st.far, st.weak, st.onId = nil, false, nil, false, false, nil
  st.off = not A.Yes(UnitIsConnected, m.unit)
  st.dead = A.Yes(UnitIsDeadOrGhost, m.unit)
  st.seen = type(UnitIsVisible) ~= "function" or A.Yes(UnitIsVisible, m.unit)
  if st.off or st.dead or not st.seen then return st end
  local names, ids, hidden = auras(m.unit)
  if hidden then st.unknown = true return st end
  local on = S.On(d.entry, names, ids)
  st.has = on ~= nil
  -- (by the aura's spell id: one the client hid is never low; a Prayer or a Greater as strong as your rank is fine)
  st.weak = on ~= nil and S.Low(d.entry, on.id, m.level, spellId) or false
  st.onId = st.weak and on.id or nil
  st.left = on and on.exp and on.exp - A.Now() or nil
  st.far = spellId and S.InRange(spellId, m.unit) == false or false
  return st
end
Bf.State = state
-- the group version and the one to cast it on, for those missing it (Greater: the class of pick, the next one, when its
-- every member takes this from you; Prayer, Brilliance or Gift: pick's subgroup, a party all of it). The highest rank
-- you know whose own reagent you carry (Prayer of Fortitude 1 a Holy Candle, 2 a Sacred Candle) that three or more of
-- them take at full power, each at their own level: a rank that lands on them (no more than ten levels under it) and
-- never weaker than the single rank they would get (Prayer 1 under a 60's Fortitude 6 would land as a lower rank, and
-- be cast again). On the first of those three in range; nil when no rank serves three
local function groupFor(d, pick, missing)
  local e, m = d.entry, pick.m
  local g = e.group
  if not g then return nil end
  if d.bless and not (A.Settings().greater ~= false and d.greater[m.class or ""]) then return nil end
  local raid = A.Roster.InRaid()
  for i = #g, 1, -1 do
    local id = g[i]
    local lv = e.groupLevels and e.groupLevels[i] or 0
    local rg = e.groupReagents and e.groupReagents[i] or e.reagent
    if S.Knows(id) and rg and rg ~= 0 and S.Count(rg) > 0 then
      local n, at = 0, nil
      for _, x in ipairs(missing) do
        local covered
        if d.bless then covered = x.m.class == m.class else covered = not raid or x.m.sub == m.sub end
        local level = x.m.level or 60
        if covered and lv <= level + 10 and not S.Low(e, id, level, x.id) then
          n = n + 1
          if not at and not x.far then at = x end
        end
      end
      if n >= 3 and at then return id, at end
    end
  end
  return nil
end
Bf.GroupFor = groupFor
-- the flyout's order: missing in range, then far, then dead or offline, then those who have it (one about to end, or
-- at a lower rank than you give, counts as missing)
local function flyRank(x) if x.dead or x.off then return 3 elseif x.has and not x.low and not x.weak then return 4 elseif x.far then return 2 end return 1 end
local function flyOrder(a, b)
  local ra, rb = flyRank(a), flyRank(b)
  if ra ~= rb then return ra < rb end
  return (a.name or "") < (b.name or "")
end
-- two sentences of a tooltip, the first nil for none
local function join(a, b) return a and (a .. " " .. b) or b end
-- who to buff first: no buff, then a lower rank (as the buffs from others list theirs), then a buff about to end (the
-- sooner first), then the duty's own order
local function missOrder(a, b)
  if (a.left == nil) ~= (b.left == nil) then return a.left == nil end
  if a.left and b.left and a.left ~= b.left then return a.left < b.left end
  if (a.weak == true) ~= (b.weak == true) then return not a.weak end
  return a.i < b.i
end
-- (who walks into range or whose buff crosses its last minutes: a look at the group's part every 3 s while you owe
-- something, out of a fight; the auras come from the cache, so a look costs a range check a member)
local looking = false
local function lookSoon()
  if looking then return end
  looking = true
  A.After(3, function()
    looking = false
    if #A.Assign.duties == 0 or A.Fighting() then return end
    B.Dirty("group")
    lookSoon()
  end, "buffs: the 3 s look")
end
local flyPools, missPools, stScratch = {}, {}, {} -- [duty key] = its flyout's rows, its missing list (kept); a state
B.Add({ key = "duty", part = "group", order = 200, groups = { "group", "mine" }, timed = "own",
  read = function(add, ctx)
    if #A.Assign.duties > 0 then lookSoon() end
    for _, d in ipairs(A.Assign.duties) do
      if not B.Never("duty:" .. d.key) then
        local missing = missPools[d.key]
        if not missing then missing = { pool = {} }; missPools[d.key] = missing end
        for i = #missing, 1, -1 do missing[i] = nil end
        local flyPool = flyPools[d.key]
        if not flyPool then flyPool = {}; flyPools[d.key] = flyPool end
        local fly = flyPool.list or {}
        flyPool.list = fly
        for i = #fly, 1, -1 do fly[i] = nil end
        -- (a buff under five minutes from its end counts as missing, ten at a ready check, a quarter of it at most:
        -- Thorns' ten minutes waits for its last 2:30)
        local limit = math.min(ctx.pull and 600 or 300, (d.entry.dur or 3600) / 4)
        local nLow, nWeak, soonest = 0, 0, nil
        for i, m in ipairs(d.targets) do
          local id = S.Best(d.entry, m.level)
          if id then
            local st = state(d, m, id, stScratch)
            -- (a lower rank than you give counts as missing, its row "Low rank": its end coming no longer matters)
            local weak = st.weak
            local low = not weak and st.has and st.left ~= nil and st.left < limit or false
            local row = flyPool[#fly + 1]
            if not row then row = {}; flyPool[#fly + 1] = row end
            row.unit, row.guid, row.name, row.class, row.spell, row.tex = m.unit, m.guid, m.me and "You" or m.name, m.class, id, nil
            row.has, row.dead, row.off, row.far, row.glow = st.has, st.dead, st.off, st.far or not st.seen, A.Hands and A.Hands.Glowing(m.guid) or nil
            row.low, row.left, row.weak = low, low and st.left or nil, weak
            fly[#fly + 1] = row
            if (low or weak or not st.has) and not (st.dead or st.off or st.unknown or not st.seen) then
              local x = missing.pool[#missing + 1]
              if not x then x = {}; missing.pool[#missing + 1] = x end
              x.m, x.id, x.far, x.left, x.i = m, id, st.far, low and st.left or nil, i
              x.weak, x.have = weak, st.onId
              missing[#missing + 1] = x
              if weak then nWeak = nWeak + 1 end
              if low then
                nLow = nLow + 1
                if not soonest or st.left < soonest then soonest = st.left end
              end
            end
          end
        end
        table.sort(missing, missOrder)
        local next
        for _, x in ipairs(missing) do if not x.far then next = x; break end end
        -- (in a group a paladin's blessings stay on the bar with none missing, dimmed: their list opens in a fight, where a
        -- Hand's restore is a click on its row)
        table.sort(fly, flyOrder)
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
          -- (the group version for three or more it gives full power: cast on one of them, named in pick's place)
          local gid, at = groupFor(d, pick, missing)
          if at then pick = at end
          local m = pick.m
          local rec = add()
          rec.key = "duty:" .. d.key
          rec.never, rec.neverName = "duty:" .. d.key, d.entry.name
          rec.tex, rec.lit = L.SpellIcon(d.entry.ranks[1], d.entry.icon), true
          rec.count = #missing
          rec.word, rec.class = m.me and "You" or m.name, m.class
          -- (the next one has it, about to end: their time left, ticking; the one a click buffs, not someone out of range)
          if pick.left then rec.word, rec.class, rec.status, rec.timed = countdown(math.max(0, pick.left)), nil, "warn", true end
          rec.far = next == nil
          -- (nobody missing it in range: the icon waits, greyed, and a click casts nothing)
          if rec.far then rec.lit, rec.word, rec.status, rec.timed = false, "Far", "warn", nil end
          rec.flyout = fly
          rec.name = L.SpellName(d.entry.ranks[1], d.entry.name)
          if gid then
            B.Click(rec, "spell", gid, m.unit)
            rec.name = L.SpellName(gid, d.entry.groupName or rec.name)
            rec.clickWord = "cast " .. rec.name .. " on " .. (m.me and "yourself" or m.name)
          else
            B.Click(rec, "spell", pick.id, m.unit)
            rec.clickWord = "buff " .. (m.me and "yourself" or m.name)
          end
          local nMiss = #missing - nLow - nWeak
          local why
          -- (the one named has a lower rank: theirs and the one you give, "Rank 4 on them; you give rank 6.")
          if pick.weak then
            local r, isGroup = S.RankOf(d.entry, pick.have)
            local theirs = isGroup and (L.SpellName(pick.have, d.entry.groupName) .. " rank " .. r) or ("Rank " .. r)
            why = theirs .. " on " .. (m.me and "you" or "them") .. "; you give rank " .. S.RankOf(d.entry, pick.id) .. "."
          end
          if nMiss > 0 then why = join(why, nMiss == 1 and "1 member is missing it." or (nMiss .. " members are missing it.")) end
          if nWeak > (pick.weak and 1 or 0) then why = join(why, nWeak == 1 and "1 member has a lower rank." or (nWeak .. " members have a lower rank.")) end
          if nLow > 0 then
            local ends = nLow == 1 and "1 member has it ending within " or (nLow .. " members have it ending within ")
            why = join(why, ends .. (limit % 60 == 0 and (math.floor(limit / 60) .. " minutes.") or (countdown(limit) .. ".")))
          end
          if d.bless then why = why .. " Cute Auras shares the blessings out among the group's paladins." end
          if rec.far then why = why .. " None of them is in range." ; rec.clickWord = nil end
          rec.why = why
        end
      end
    end
  end,
})

-- the warlock's soulstone: one on a healer who has none, the k-th warlock with Cute Auras the k-th healer who can take
-- it now (online, alive, in sight). A healer offline or out of sight shows no auras: never read as one without a stone,
-- never chosen. Out of range (the stone's own range, C_Item.IsItemInRange, out of a fight): the icon waits, greyed
local STONE_AURA = { 20707, 20762, 20763, 20764, 20765 }
local stoneHealers, stoneLocks, stoneReady = {}, {}, {}
local function byGUID(a, b) return a.guid < b.guid end
local function stoneInRange(stone, unit)
  local v
  if C_Item and type(C_Item.IsItemInRange) == "function" then
    local ok, r = pcall(C_Item.IsItemInRange, stone, unit)
    if ok then v = plain(r) end
  end
  if v == true or v == false then return v end
  return S.InRange(STONE_AURA[1], unit)
end
B.Add({ key = "soulstone", part = "group", order = 210, groups = { "group" },
  read = function(add, ctx)
    if myClass() ~= "WARLOCK" or not ctx.group then return end
    local bags = B.Bags()
    local stone
    for i = #D.SOULSTONE, 1, -1 do if bags[D.SOULSTONE[i]] then stone = D.SOULSTONE[i]; break end end
    if not stone or select(2, S.ItemCD(stone)) > 0 then return end
    local healers, locks, ready = stoneHealers, stoneLocks, stoneReady
    for i = #healers, 1, -1 do healers[i] = nil end
    for i = #locks, 1, -1 do locks[i] = nil end
    for i = #ready, 1, -1 do ready[i] = nil end
    for _, m in ipairs(A.Roster.members) do
      if m.role == "healer" then healers[#healers + 1] = m end
      if m.class == "WARLOCK" and A.Comm.Running(m.guid) then locks[#locks + 1] = m end
    end
    table.sort(healers, byGUID)
    table.sort(locks, byGUID)
    local k
    for i, m in ipairs(locks) do if m.me then k = i end end
    for _, h in ipairs(healers) do
      local seen = A.Yes(UnitIsConnected, h.unit) and (type(UnitIsVisible) ~= "function" or A.Yes(UnitIsVisible, h.unit))
      if seen then
        local _, ids, hidden = auras(h.unit)
        for _, id in ipairs(STONE_AURA) do if ids[id] then return end end
        if not hidden and not A.Yes(UnitIsDeadOrGhost, h.unit) then ready[#ready + 1] = h end
      end
    end
    local h = k and ready[k] or ready[1]
    if not h then return end
    local rec = add()
    rec.key = "soulstone"
    rec.tex, rec.lit, rec.word, rec.class = L.ItemIcon(stone, 136210), true, h.me and "You" or h.name, h.class
    B.Click(rec, "item", stone, h.unit)
    rec.never, rec.neverName = "soulstone", "Soulstone"
    rec.name, rec.why, rec.clickWord = L.ItemName(stone, "Soulstone"), "No healer has a soulstone.", "put it on " .. h.name
    if not h.me and stoneInRange(stone, h.unit) == false then
      rec.far, rec.lit, rec.word, rec.status, rec.clickWord = true, false, "Far", "warn", nil
      rec.why = rec.why .. " " .. h.name .. " is out of range."
    end
  end,
})

----------------------------------------------------------------------------
-- consumables (the owner, 2026-11-23: "don't forget the Well Fed and potion buffs"). A consumable whose use puts a
-- buff on you for a minute or more (an elixir, a flask, a potion, a scroll, a juju: its C_Item.GetItemSpell aura) is
-- learned as you use it, and kept up by habit once used twice; asked for three times ten minutes and not used, it is
-- forgotten (30 kept, this character's; one used once makes room when the list is full). Two that take each other's
-- place (B's aura came in the second A's went, as you used B) are one group: the one used last is asked for. Where
-- Settings says (dungeons and raids by default, everywhere, the ready check only, off), out of a fight: a habit missing
-- from you that you carry ("Use"), one under a minute from its end (its countdown); Well Fed inside dungeons and raids
-- (the camp's Eat has the open world) and, anywhere out of town, under two minutes left. Before the pull asks for
-- your habits and the elixirs, flasks and scrolls you carry that fit your role
----------------------------------------------------------------------------
local KINDS = { [1] = "Drink", [2] = "Drink", [3] = "Drink", [4] = "Read", [8] = "Use", [0] = "Use" } -- (potion, elixir, flask, scroll, other)
-- an item's kind (the bar's word) and its subclass: class 0 (consumable) by subclass; class 12 (a juju and the like)
-- only when the client's tables say its use leaves a lasting stat buff (D.CONSUME), never a quest's disguise
local function kindOf(id)
  local ok, _, _, _, _, _, classID, subID = pcall(C_Item.GetItemInfoInstant, id)
  if not ok then return nil end
  classID, subID = plain(classID), plain(subID)
  if classID == 0 then return KINDS[subID or -1], subID end
  if classID == 12 then
    local sp = itemAura(id)
    local w = sp and D.CONSUME and D.CONSUME[sp]
    if type(w) == "string" and w ~= "" then return "Use", nil end
  end
  return nil
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
local asked = {}    -- [item id] = since when the bar asks for it (this session)
local function watchConsumables(names, ids)
  local t = A.Now()
  local h = habitsDB()
  local came, went
  -- (a use whose aura came, a minute or more long: one more hit)
  for id, at in pairs(pending) do
    local a = auraOn(id, names, ids)
    if a then
      pending[id] = nil
      asked[id] = nil
      if not a.exp or a.exp - t >= 50 then
        local e = h[id]
        if type(e) ~= "table" then
          e = nil
          if roomFor(h, 30) then e = { hits = 0, miss = 0 }; h[id] = e end
        end
        if e then e.hits, e.miss, e.spell, e.at = (e.hits or 0) + 1, 0, itemAura(id), stamp() end
      end
    elseif t - at > 6 then pending[id] = nil end
  end
  for id, e in pairs(h) do
    if type(e) ~= "table" then h[id] = nil
    else
      local on = auraOn(id, names, ids) ~= nil
      if on and not onSince[id] then onSince[id] = t; came = id end
      if not on and onSince[id] then onSince[id] = nil; went = id end
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
local function wipe(t) for k in pairs(t) do t[k] = nil end end
local groupSeen, askedHere = {}, {}
B.Add({ key = "consume", part = "mine", order = 120, groups = { "mine" }, timed = true,
  read = function(add, ctx)
    -- (at a ready check Before the pull asks instead, and the reminders' clocks wait)
    if ctx.pull then return end
    if A.Settings().consume == "off" or ctx.town then wipe(asked) return end
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
    if not consumeHere(ctx) then wipe(asked) return end
    wipe(groupSeen); wipe(askedHere)
    local bags = B.Bags()
    local h = habitsDB()
    -- (a group with one of its auras on asks nothing more than that one's countdown)
    for id in pairs(h) do if auraOn(id, names, ids) then groupSeen[groupOf(id)] = id end end
    local n = 0
    for id, e in pairs(h) do
      if type(e) == "table" and (e.hits or 0) >= 2 and bags[id] and n < 3 then
        local g = groupOf(id)
        local a = auraOn(id, names, ids)
        local left = a and a.exp and a.exp - ctx.t or nil
        if a and a.exp then wakeFor(a.exp - 60, ctx.t) end
        local show = (not a and not groupSeen[g]) or (left and left > 0 and left < 60)
        if show and not B.Never("consume:" .. g) then
          -- (asked for ten minutes and not used: a miss; three, forgotten)
          if not a then
            local at = asked[id]
            if not at then at = ctx.t
            elseif ctx.t - at >= ASK_FOR then e.miss = (e.miss or 0) + 1; at = ctx.t end
            asked[id], askedHere[id] = at, true
            wakeFor(at + ASK_FOR, ctx.t)
            if (e.miss or 0) >= 3 then h[id], asked[id], show = nil, nil, false end
          end
        end
        if show and not B.Never("consume:" .. g) then
          n = n + 1
          if not a then groupSeen[g] = id end
          local rec = add()
          rec.key = "consume" .. id
          rec.tex, rec.lit, rec.count = L.ItemIcon(id, 134400), true, S.Count(id)
          rec.word = left and countdown(left) or (kindOf(id) or "Use")
          if left then rec.status, rec.timed = "warn", true end
          -- (on you: a juju takes a target, and you are it)
          B.Click(rec, "item", id, "player")
          rec.never, rec.neverName = "consume:" .. g, L.ItemName(id, "this one")
          rec.name = L.ItemName(id, "A consumable")
          rec.why = left and "Its buff ends soon." or "You keep this one up."
          rec.clickWord = "use it"
        end
      end
    end
    for id in pairs(asked) do if not askedHere[id] then asked[id] = nil end end
  end,
})

-- Before the pull: food, your habits (any kind: a potion, Spirit of Zanza, a juju) and every elixir, flask or scroll you
-- carry whose buff you lack (one of each group) and that fits your role. What a buff raises comes from the client's
-- tables (D.CONSUME, the same in every language); a server-sent one they lack, from the words of its spell's text. A
-- caster or healer is never asked for Strength or Agility, a melee never for Intellect or spell damage; Stamina, health,
-- armor, a resistance or an absorb alone fits everyone; a potion that only heals or a utility elixir (Water Breathing)
-- is never asked unless it is your habit. A buff with under three minutes left is asked again, its countdown. Flasks
-- first, then elixirs, then scrolls: four at most
local function set(s) local t = {}; for w in s:gmatch("%a+") do t[w] = true end; return t end
local ROLE_WANTS = {
  melee = set("str agi ap phys dmg crit haste hit exp"),
  ranged = set("agi rap phys dmg crit haste hit"),
  tank = set("str agi ap phys dmg crit haste hit exp def"),
  caster = set("int spi spell dmg crit haste hit mp5 mana"),
  healer = set("int spi heal crit haste mp5 mana"),
}
-- (a main stat decides; crit, haste, hit or all damage only when there is none: the Mongoose's crit is no healer's)
local PRIMARY = set("str agi int spi ap rap phys spell heal mp5 mana def exp")
local NEUTRAL = set("sta all hp armor res absorb")
local function fitsWords(words, role)
  local want = ROLE_WANTS[role or ""] or ROLE_WANTS.melee
  local main, mainWanted, other, otherWanted, neutral = false, false, false, false, false
  for w in words:gmatch("%a+") do
    if NEUTRAL[w] then neutral = true
    elseif PRIMARY[w] then main = true; if want[w] then mainWanted = true end
    else other = true; if want[w] then otherWanted = true end end
  end
  if main then return mainWanted end
  if other then return otherWanted end
  return neutral
end
-- (Camp.BestFood fits a food's Well Fed by the same words, D.FOOD[id].w)
Bf.FitsWords = fitsWords
-- the old way, for an item the tables lack: English words in its spell's text (C_Spell.GetSpellDescription, its tooltip else)
local WANTS = {
  caster = { intellect = true, spirit = true, spell = true, mana = true, healing = true },
  healer = { intellect = true, spirit = true, spell = true, mana = true, healing = true },
  melee = { strength = true, agility = true, ["attack power"] = true, critical = true },
  ranged = { agility = true, ["attack power"] = true, critical = true, ranged = true },
  tank = { strength = true, agility = true, defense = true, armor = true, stamina = true, ["attack power"] = true },
}
local STATS = { "intellect", "spirit", "spell", "mana", "healing", "strength", "agility", "attack power", "critical", "ranged", "defense" }
local fits = {} -- [item id .. role] = true or false
local function textOf(id)
  local sp = itemAura(id)
  local get = C_Spell and C_Spell.GetSpellDescription
  local t = sp and type(get) == "function" and plain(call(get, sp)) or nil
  if type(t) == "string" and t ~= "" then return t:lower() end
  local TI = C_TooltipInfo
  local data = TI and type(TI.GetItemByID) == "function" and call(TI.GetItemByID, id) or nil
  local out = {}
  for _, l in ipairs(type(data) == "table" and type(data.lines) == "table" and data.lines or {}) do
    local x = plain(l.leftText)
    if type(x) == "string" then out[#out + 1] = x end
  end
  return #out > 1 and table.concat(out, " "):lower() or nil
end
function Bf.Fits(id, role)
  local key = id .. (role or "")
  if fits[key] ~= nil then return fits[key] end
  local sp = itemAura(id)
  local words = sp and D.CONSUME and D.CONSUME[sp]
  local v
  if type(words) == "string" then v = fitsWords(words, role)
  else
    local t = textOf(id)
    if not t then return true end -- (not loaded: asked, not kept)
    local want = WANTS[role or ""] or WANTS.melee
    local named, wanted = false, false
    for _, w in ipairs(STATS) do
      if t:find(w, 1, true) then named = true; if want[w] then wanted = true end end
    end
    v = (not named) or wanted
  end
  fits[key] = v
  return v
end
local PULL_SOON = 180
local PULL_SUB = { [3] = 1, [2] = 2, [4] = 3 } -- (flask, elixir, scroll: the order on the bar; anything else after)
local flaskBuf, subOf, soonLeft = {}, {}, {}
local function pullOrder(a, b)
  local ra, rb = PULL_SUB[subOf[a] or -1] or 4, PULL_SUB[subOf[b] or -1] or 4
  if ra ~= rb then return ra < rb end
  return a < b
end
B.Add({ key = "pull", part = "pull", order = 300, groups = { "mine", "pull" }, timed = true,
  read = function(add, ctx)
    -- (Settings' consumables Off is off here too)
    if not ctx.pull or A.Settings().consume == "off" then return end
    local Camp = A.Camp
    local names, ids, hidden = Camp.Mine()
    if hidden then return end
    -- food: not Well Fed, or under three minutes left
    local fr = Camp.FedRec(names, ids)
    local fedLeft = type(fr) == "table" and fr.exp and fr.exp - ctx.t or nil
    if fedLeft then wakeFor(fr.exp - PULL_SOON, ctx.t) end
    if not fr or (fedLeft and fedLeft > 0 and fedLeft < PULL_SOON) then
      local id = Camp.BestFood(true)
      if id then
        local rec = add()
        rec.key = "pullfood"
        rec.tex, rec.lit, rec.count, rec.word = L.ItemIcon(id, 133945), true, S.Count(id), "Eat"
        if fedLeft then rec.word, rec.status, rec.timed = countdown(fedLeft), "warn", true end
        B.Click(rec, "item", id)
        rec.never, rec.neverName, rec.name, rec.clickWord = "pullfood", "Food before the pull", L.ItemName(id, "Well Fed"), "eat it"
      end
    end
    wipe(flaskBuf); wipe(subOf); wipe(groupSeen); wipe(soonLeft)
    local role = A.Roster.MyRole()
    local h = habitsDB()
    for id in pairs(B.Bags()) do
      local k, sub = kindOf(id)
      local habit = type(h[id]) == "table" and (h[id].hits or 0) >= 2
      if k and itemAura(id) and (habit or (PULL_SUB[sub or -1] and Bf.Fits(id, role))) then
        flaskBuf[#flaskBuf + 1] = id
        subOf[id] = sub
      end
    end
    table.sort(flaskBuf, pullOrder)
    -- (a group is covered by any of its auras on you, from a bottle carried or one learned (your last one used up), with
    -- three minutes or more left; under that, its countdown)
    local function cover(id)
      local a = auraOn(id, names, ids)
      if not a then return end
      local g = groupOf(id)
      local left = a.exp and a.exp - ctx.t or nil
      if not left or left >= PULL_SOON then groupSeen[g] = true
      else
        wakeFor(a.exp, ctx.t)
        if not soonLeft[g] or left < soonLeft[g] then soonLeft[g] = left end
      end
      if left and left >= PULL_SOON then wakeFor(a.exp - PULL_SOON, ctx.t) end
    end
    for id in pairs(h) do cover(id) end
    for _, id in ipairs(flaskBuf) do cover(id) end
    local shownN = 0
    for _, id in ipairs(flaskBuf) do
      local g = groupOf(id)
      if not groupSeen[g] and shownN < 4 then
        groupSeen[g] = true
        shownN = shownN + 1
        local rec = add()
        rec.key = "flask" .. id
        rec.tex, rec.lit, rec.count, rec.word = L.ItemIcon(id, 134400), true, S.Count(id), kindOf(id)
        local left = soonLeft[g]
        if left then rec.word, rec.status, rec.timed = countdown(math.max(0, left)), "warn", true end
        B.Click(rec, "item", id, "player")
        rec.never = "flask:" .. g
        rec.name = L.ItemName(id, "Elixir")
        rec.neverName, rec.clickWord = rec.name, "use it"
        if left then rec.why = "Its buff ends soon." end
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
function Bf:Init()
  for _, ev in ipairs({ "ACTIVE_TALENT_GROUP_CHANGED", "ACTIVE_COMBAT_CONFIG_CHANGED", "TRAIT_CONFIG_UPDATED" }) do
    A.On(ev, function() for k in pairs(fits) do fits[k] = nil end end)
  end
  -- (the kept auras: a unit's own change, a roster change (the tokens move), a new world, a fight's end)
  A.On("UNIT_AURA", function(_, unit)
    unit = plain(unit)
    if type(unit) == "string" and (unit == "player" or unit:find("^party%d") or unit:find("^raid%d")) then Bf.Stale(unit) end
  end)
  for _, ev in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
    A.On(ev, function() Bf.Stale(nil) end)
  end
  A.OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, onCast)
  -- (a fight starts the buffs from others' waits again: 30 s out of it; a ready check ends them)
  A.On("PLAYER_REGEN_DISABLED", function() fromWipe(); fromReady = false end)
  A.On("READY_CHECK", function() fromReady = true; B.Dirty("from") end)
  A.OnUnit("UNIT_INVENTORY_CHANGED", { "player" }, function() watchWeapons(); B.Dirty("mine") end)
  A.Camp.Watch(function() watchWeapons() end)
end
