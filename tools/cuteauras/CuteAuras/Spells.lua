-- SPDX-License-Identifier: GPL-3.0-or-later
-- Spells and auras: what you know, the rank to cast on a target, whose auras say a buff is on, your bags' counts and
-- cooldowns. Every client answer goes through A.Plain: a secret value reads as nothing.
local _, A = ...
local S = {}
A.Spells = S
local plain, call = A.Plain, A.Call
local L = A.Look

-- a spell you know: C_SpellBook.IsSpellKnown, or IsPlayerSpell on a client without it
function S.Knows(id)
  if not id then return false end
  if C_SpellBook and type(C_SpellBook.IsSpellKnown) == "function" then
    local ok, v = pcall(C_SpellBook.IsSpellKnown, id)
    if ok then return plain(v) == true end
  end
  return A.Yes(IsPlayerSpell, id)
end

-- the rank to cast: the highest you know; with a target's level, the highest that level may take (Classic's rule: a
-- buff's rank lands on a target no more than ten levels under the rank's own level)
local function bestOf(ids, levels, targetLevel)
  if not ids then return nil end
  for i = #ids, 1, -1 do
    local id = ids[i]
    local lv = levels and levels[i] or 0
    if (not targetLevel or lv <= targetLevel + 10) and S.Knows(id) then return id end
  end
  return nil
end
function S.Best(entry, targetLevel) return bestOf(entry.ranks, entry.levels, targetLevel) end
function S.BestGroup(entry, targetLevel) return bestOf(entry.group, entry.groupLevels, targetLevel) end
-- a rank's place in its list (1 = the first rank), 0 when none is known: what a buffer announces
function S.RankKnown(entry)
  for i = #(entry.ranks or {}), 1, -1 do if S.Knows(entry.ranks[i]) then return i end end
  return 0
end

-- a rank's power: its aura's main amount (Data.lua's power and groupPower: Fortitude's Stamina, Might's attack power), a
-- single rank's or a group rank's; nil when the data has none for it (Kings, Earth Shield, an id not of this entry)
function S.Power(entry, id)
  if not (entry and id) then return nil end
  for i, x in ipairs(entry.ranks or {}) do if x == id then return entry.power and entry.power[i] or nil end end
  for i, x in ipairs(entry.group or {}) do if x == id then return entry.groupPower and entry.groupPower[i] or nil end end
  return nil
end
-- an aura of the entry's kind (its spell id) is low: under the power of the rank you would cast on that target (S.Best
-- at their level; best, that rank, when the caller has it already). A power not known, either side, is never low: a
-- Prayer or a Greater as strong as your rank is fine
function S.Low(entry, id, targetLevel, best)
  local have = S.Power(entry, id)
  if not have then return false end
  best = best or S.Best(entry, targetLevel)
  local give = best and S.Power(entry, best)
  return give ~= nil and have < give
end
-- a rank's number as the game counts it (Rank 4), and true for a rank of the group version; nil for neither. Its place
-- in its list, a level counted once: a shield's proc spell shares its rank's name and level (Lightning Shield 324, 26364)
local function numberIn(ids, levels, id)
  local n, last = 0, nil
  for i, x in ipairs(ids or {}) do
    local lv = levels and levels[i]
    if lv == nil or lv ~= last then n = n + 1 end
    last = lv
    if x == id then return n end
  end
  return nil
end
function S.RankOf(entry, id)
  local n = numberIn(entry.ranks, entry.levels, id)
  if n then return n, false end
  n = numberIn(entry.group, entry.groupLevels, id)
  if n then return n, true end
  return nil
end
-- your highest rank of a spell by its name, the one the game casts by that name (C_Spell.GetSpellIDForSpellIdentifier
-- looks the name up in your spellbook), when you know it; nil else
function S.ByName(name)
  local f = C_Spell and C_Spell.GetSpellIDForSpellIdentifier
  if type(name) ~= "string" or type(f) ~= "function" then return nil end
  local id = plain(call(f, name))
  if type(id) == "number" and S.Knows(id) then return id end
  return nil
end
-- one rank under another by the levels the game says they are learned at (C_Spell.GetSpellLevelLearned): a level not
-- told (none, or 0: an elixir's aura, a rune's) is never lower, nor higher (and a lower rank need not be in Forever's
-- spellbook: never asked whether you know it)
function S.Lower(id, than)
  if type(id) ~= "number" or type(than) ~= "number" or id == than then return false end
  local f = C_Spell and C_Spell.GetSpellLevelLearned
  if type(f) ~= "function" then return false end
  local a, b = plain(call(f, id)), plain(call(f, than))
  return type(a) == "number" and a > 0 and type(b) == "number" and b > 0 and a < b
end

-- a unit's helpful auras into kept tables: names[name] and ids[spellId] = { n = stacks, exp = expiry (GetTime), icon,
-- mine = cast by you }; the third answer true when the client hid an aura (secret): what is missing can't be told then
function S.ReadAuras(unit, names, ids, pool)
  for k in pairs(names) do names[k] = nil end
  for k in pairs(ids) do ids[k] = nil end
  local hidden, used = false, 0
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not get then return names, ids, false end
  for i = 1, 60 do
    local ok, a = pcall(get, unit or "player", i, "HELPFUL")
    if not ok or type(a) ~= "table" then break end
    local n, id = plain(a.name), plain(a.spellId)
    if n == nil and a.name ~= nil then hidden = true end
    if type(n) == "string" or type(id) == "number" then
      used = used + 1
      local e = pool[used]
      if not e then e = {}; pool[used] = e end
      local exp = plain(a.expirationTime)
      e.n, e.exp, e.icon = plain(a.applications) or 1, type(exp) == "number" and exp > 0 and exp or nil, plain(a.icon)
      local src = plain(a.sourceUnit)
      e.mine = src == "player"
      e.id = type(id) == "number" and id or nil
      -- (the same aura twice, yours and another's: yours is kept, so a self buff reads as yours)
      if type(n) == "string" and not (names[n] and names[n].mine) then names[n] = e end
      if type(id) == "number" and id > 0 and not (ids[id] and ids[id].mine) then ids[id] = e end
    end
  end
  return names, ids, hidden
end

-- an entry on a unit (its auras as ReadAuras left them): any rank, any rank of its group version, an aura it counts
-- (alsoIds), or the entry's name in the client's language. The aura's record, else nil. A self buff of one kind (an
-- aura, an aspect, an armor) counts only when you cast it: another paladin's Devotion Aura on you is theirs, and yours
-- is still to put up
local function nameOn(names, id, fallback)
  local n = L.SpellName(id, fallback)
  return n and names[n] or nil
end
local function mine(r) return r and r.mine and r or nil end
-- one kind of a self buff on you by anyone: its record, else nil (another's aura of that kind: a second one adds nothing)
function S.KindOn(sp, names, ids)
  for _, id in ipairs(sp.ranks) do if ids[id] then return ids[id] end end
  return nameOn(names, sp.ranks[1], sp.name)
end
function S.On(entry, names, ids)
  if entry.one then
    for _, sp in ipairs(entry.one) do
      for _, id in ipairs(sp.ranks) do if mine(ids[id]) then return ids[id], sp end end
      local r = mine(nameOn(names, sp.ranks[1], sp.name))
      if r then return r, sp end
    end
    for _, id in ipairs(entry.alsoIds or {}) do if mine(ids[id]) then return ids[id] end end
    return nil
  end
  for _, id in ipairs(entry.ranks or {}) do if ids[id] then return ids[id] end end
  for _, id in ipairs(entry.group or {}) do if ids[id] then return ids[id] end end
  local r = nameOn(names, entry.ranks[1], entry.name)
  if r then return r end
  if entry.group then return nameOn(names, entry.group[1], entry.groupName) end
  return nil
end

-- in a fight the client hides most auras; a spell whose aura it keeps plain can still be read
-- (C_Secrets.ShouldSpellAuraBeSecret, C_UnitAuras.GetUnitAuraBySpellID: RequiresNonSecretAura)
function S.AuraPlainInFight(id)
  local Sx = C_Secrets
  if not (Sx and type(Sx.ShouldSpellAuraBeSecret) == "function") then return false end
  local ok, v = pcall(Sx.ShouldSpellAuraBeSecret, id)
  return ok and plain(v) == false
end
function S.AurasSecret()
  local Sx = C_Secrets
  return Sx ~= nil and type(Sx.ShouldAurasBeSecret) == "function" and A.Yes(Sx.ShouldAurasBeSecret)
end
-- one spell's aura on a unit in a fight, where the client allows it: true, false, or nil (can't be told)
function S.OnInFight(unit, entry)
  local get = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
  if type(get) ~= "function" then return nil end
  local told = false
  for _, list in ipairs({ entry.ranks or {}, entry.group or {} }) do
    for _, id in ipairs(list) do
      if S.AuraPlainInFight(id) then
        told = true
        local ok, a = pcall(get, unit, id)
        if ok and type(plain(a)) == "table" then return true end
      end
    end
  end
  if told then return false end
  return nil
end

-- in range of a spell: true, false, or nil when the client can't tell (C_Spell.IsSpellInRange)
-- (a lower rank the spellbook doesn't list answers nil by its id: asked again by the spell's name; still nothing, out of
-- a fight, the follow distance, 28 yards, a little inside a buff's 30)
function S.InRange(id, unit)
  local f = C_Spell and C_Spell.IsSpellInRange or IsSpellInRange
  if type(f) == "function" then
    for pass = 1, 2 do
      local what = pass == 1 and id or L.SpellName(id, nil)
      if what then
        local ok, v = pcall(f, what, unit)
        if ok then v = plain(v) else v = nil end -- (never "ok and plain(v) or nil": that turns the game's false into nil)
        if v == 1 or v == true then return true elseif v == 0 or v == false then return false end
      end
    end
  end
  if not A.Fighting() and type(CheckInteractDistance) == "function" then
    local ok, v = pcall(CheckInteractDistance, unit, 4)
    if ok then v = plain(v) else v = nil end
    if v ~= nil then return v and true or false end
  end
  return nil
end

-- your bags' counts and an item's cooldown
function S.Count(id)
  local get = C_Item and C_Item.GetItemCount or GetItemCount
  local n = plain(call(get, id))
  return type(n) == "number" and n or 0
end
function S.ItemCD(id)
  local get = C_Container and C_Container.GetItemCooldown
  if not (get and id) then return 0, 0 end
  local ok, start, dur = pcall(get, id)
  start, dur = ok and plain(start) or 0, ok and plain(dur) or 0
  if type(start) ~= "number" or type(dur) ~= "number" or dur <= 1.5 then return 0, 0 end
  return start, dur
end
function S.SpellCD(id)
  local start, dur
  if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
    local cd = plain(call(C_Spell.GetSpellCooldown, id))
    if type(cd) == "table" then start, dur = plain(cd.startTime), plain(cd.duration) end
  elseif type(GetSpellCooldown) == "function" then
    local ok, a, b = pcall(GetSpellCooldown, id)
    if ok then start, dur = plain(a), plain(b) end
  end
  if type(start) ~= "number" or type(dur) ~= "number" or start <= 0 or dur <= 1.5 then return 0, 0 end
  return start, dur
end

-- your professions by name, with the skill (into: a kept table)
function S.Professions(into)
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

----------------------------------------------------------------------------
-- an item you can use now, by its tooltip: no red line (the game paints "Requires Level 30", "Classes: Mage", "Races:
-- ...", "Requires Alchemy (140)" red when they are not yours), no error line, and its required level yours or lower.
-- The owner, 2026-11-23: "It tells me to use items outside my level or not for my class or race, that can't happen".
-- Each item asked once until your level, skills or spells change (S.ForgetUsable)
----------------------------------------------------------------------------
local usable, usableN = {}, 0
local function red(c)
  if type(c) ~= "table" then return false end
  local r, g, b = plain(c.r), plain(c.g), plain(c.b)
  return type(r) == "number" and type(g) == "number" and type(b) == "number" and r > 0.9 and g < 0.2 and b < 0.2
end
S.IsRed = red
-- (the game's own word now: IsUsableItem false while a fire or a reagent is missing, never kept)
local function liveUsable(id)
  if C_Item and type(C_Item.IsUsableItem) == "function" then
    local ok, u = pcall(C_Item.IsUsableItem, id)
    if ok and plain(u) == false then return false end
  end
  return true
end
function S.Usable(id, bag, slot)
  local v = usable[id]
  if v ~= nil then return v and liveUsable(id) end
  if usableN >= 200 then for k in pairs(usable) do usable[k] = nil end; usableN = 0 end
  v = true
  local get = C_Item and C_Item.GetItemInfo or GetItemInfo
  local name, _, _, _, minLevel = call(get, id)
  -- (the client's cache not loaded yet: no answer kept, asked again next time, and nothing offered meanwhile)
  if plain(name) == nil then return false end
  minLevel = plain(minLevel)
  local level = plain(call(UnitLevel, "player")) or 1
  if type(minLevel) == "number" and minLevel > level then v = false end
  local TI = C_TooltipInfo
  if v and TI then
    local ok, data
    if bag and slot and type(TI.GetBagItem) == "function" then ok, data = pcall(TI.GetBagItem, bag, slot)
    elseif type(TI.GetItemByID) == "function" then ok, data = pcall(TI.GetItemByID, id) end
    local lines = ok and type(data) == "table" and data.lines or nil
    if type(lines) ~= "table" or #lines < 2 then return false end -- (a tooltip not loaded yet: not kept)
    local LT = Enum and Enum.TooltipDataLineType or {}
    for _, l in ipairs(lines) do
      local ty = plain(l.type)
      if (ty ~= nil and LT.ErrorLine ~= nil and ty == LT.ErrorLine) or red(l.leftColor) or red(l.rightColor) then v = false; break end
    end
  end
  usableN = usableN + 1
  usable[id] = v
  return v and liveUsable(id)
end
function S.ForgetUsable() for k in pairs(usable) do usable[k] = nil end; usableN = 0 end
