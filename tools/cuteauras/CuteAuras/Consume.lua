-- SPDX-License-Identifier: GPL-3.0-or-later
-- Consumables (the owner, 2026-11-24: "i have elixir in my bags it dosnt notify me that im missing", "options in settings
-- to pick all potions etc for scenarios raid dungeon"): what you carry and use that puts a lasting buff on you, a potion,
-- an elixir, a flask, a scroll, a juju; Well Fed; your weapon's oil or stone. One decision says whether one is asked for
-- where you stand (Cn.AsksIn): Never, then its own choice for here (the Consumables tab's chips, the icon's right-click),
-- then a habit (two uses with a lasting aura), then a 0.2.2 ready check's Never (pull:<id>: that version asked such an
-- item out of a fight only as a habit), then its kind's default for here (Flasks, Scrolls and Other in raids,
-- Elixirs in 5-man dungeons and raids, Potions and Weapon nowhere, Well Fed in the open world, 5-man dungeons and raids),
-- then whether it fits your role (a role only guessed from your class hides nothing). Shared by all your characters.
--   consume   yours on the bar out of town and out of a fight: Well Fed, then at most 3, one of each group of items
--             that replace each other (a learned pair, a kin of the same stat and kind, every flask), a countdown under
--             a minute, waiting while the potions' shared cooldown runs. One shown 30 minutes on screen and not used
--             goes quiet until you use it or choose for it (a habit loses its habit then, as before)
--   pull      Before the pull (a ready check): food, then at most 4, flasks first: every fitting flask, elixir and scroll,
--             every habit, whatever is chosen for here, and what a kind's default asks here when it fits you; never one
--             whose buff, or its group's, is on you for 3 minutes or more. One of a group: the one whose own buff ends,
--             else your choice, your habit, a fit, as yours. Yours waits while it shows
local _, A = ...
local Cn = A.Part("Consume", {})
local B, S, L, D, Bf = A.Bar, A.Spells, A.Look, A.Data, A.Buffs
local plain, call = A.Plain, A.Call
local wakeFor, roomFor, itemAura, lastUse = Bf.WakeFor, Bf.RoomFor, Bf.ItemAura, Bf.LastUse
local countdown = Bf.Countdown
local function stamp() return type(time) == "function" and time() or 0 end
local function wipe(t) for k in pairs(t) do t[k] = nil end end

-- where you stand (Gear.lua's G.Context): its key, the chip's word, the words a tooltip says
Cn.PLACES = { { "solo", "World", "the open world" }, { "pvp", "PvP", "battlegrounds and arenas" },
  { "dungeon", "5-man", "5-man dungeons" }, { "raid", "Raid", "raids" } }
local PLACE_WORD, PLACE_TEXT = {}, {}
for _, p in ipairs(Cn.PLACES) do PLACE_WORD[p[1]], PLACE_TEXT[p[1]] = p[2], p[3] end
Cn.PLACE_WORD, Cn.PLACE_TEXT = PLACE_WORD, PLACE_TEXT
function Cn.Where() return A.Gear and A.Gear.Context() or "solo" end

-- the kinds, in the tab's and the bar's order: the bar's word, where each is on by default
Cn.KINDS = { "fed", "flask", "elixir", "potion", "scroll", "other", "weapon" }
local KIND_WORD = { fed = "Eat", flask = "Drink", elixir = "Drink", potion = "Drink", scroll = "Read", other = "Use", weapon = "Apply" }
local KIND_ON = { fed = { solo = true, dungeon = true, raid = true }, flask = { raid = true }, elixir = { dungeon = true, raid = true },
  potion = {}, scroll = { raid = true }, other = { raid = true }, weapon = {} }
Cn.KIND_WORD = KIND_WORD
local SUB_KIND = { [1] = "potion", [2] = "elixir", [3] = "flask", [4] = "scroll" }

----------------------------------------------------------------------------
-- the saved choices: A.Settings().consumables, the account's (built here when missing: never in A.DEFAULTS, whose copy
-- would share one table). kinds: an explicit true or false for every kind and place; items[id or "fed"][place]: nil
-- (no choice) or a boolean; habits: where a habit is asked, "inst" (battlegrounds, 5-man dungeons, raids), "world"
-- (the open world too) or "pull" (only before the pull)
----------------------------------------------------------------------------
local checked
function Cn.Settings()
  local s = A.Settings()
  local t = s.consumables
  if t == checked and type(t) == "table" then return t end
  if type(t) ~= "table" then t = {}; s.consumables = t end
  if type(t.on) ~= "boolean" then t.on = true end
  if t.habits ~= "inst" and t.habits ~= "world" and t.habits ~= "pull" then t.habits = "inst" end
  if type(t.kinds) ~= "table" then t.kinds = {} end
  for _, k in ipairs(Cn.KINDS) do
    local row = t.kinds[k]
    if type(row) ~= "table" then row = {}; t.kinds[k] = row end
    for _, p in ipairs(Cn.PLACES) do
      if type(row[p[1]]) ~= "boolean" then row[p[1]] = KIND_ON[k][p[1]] == true end
    end
  end
  if type(t.items) ~= "table" then t.items = {} end
  checked = t
  return t
end
function Cn.On() return Cn.Settings().on ~= false end
function Cn.KindDefault(kind, where)
  local row = Cn.Settings().kinds[kind or "other"]
  return row ~= nil and row[where] == true
end
-- (Well Fed's choices: the open world's is the camp's Eat, read again with them)
local function changedFor(id)
  B.Dirty("mine")
  if id == "fed" then B.Dirty("camp") end
end
function Cn.SetKindDefault(kind, where, v)
  local row = Cn.Settings().kinds[kind]
  if not row then return end
  row[where] = v and true or false
  changedFor(kind)
end

----------------------------------------------------------------------------
-- this character's habits and quiet, the account's pairs and stacks
----------------------------------------------------------------------------
local function habitsDB()
  local c = A.Char()
  if type(c.consume) ~= "table" then c.consume = {} end
  return c.consume
end
Cn.Habits = habitsDB
local function quietDB()
  local c = A.Char()
  if type(c.consumeQuiet) ~= "table" then c.consumeQuiet = {} end
  return c.consumeQuiet
end
local function pairsDB()
  local a = A.Acct()
  if type(a.pairs) ~= "table" then a.pairs = {} end
  return a.pairs
end
local function kinStacks()
  local a = A.Acct()
  if type(a.kinStacks) ~= "table" then a.kinStacks = {} end
  return a.kinStacks
end
local function hitsOf(id)
  local e = habitsDB()[id]
  return type(e) == "table" and (e.hits or 0) or 0
end
local function isHabit(id) return hitsOf(id) >= 2 end

----------------------------------------------------------------------------
-- what an item raises: the client's tables (D.CONSUME, by its use spell), else the English words of its spell's text
-- for a server-sent one the tables lack, read only when the text names a duration of a minute or more (a healing
-- potion's "Restores 1050 health" is no lasting buff). Words in the tables' order: "agi crit"
----------------------------------------------------------------------------
local TEXT_WORDS = {
  { "all stats", "all" }, { "ranged attack power", "rap" }, { "attack power", "ap" }, { "strength", "str" }, { "agility", "agi" },
  { "stamina", "sta" }, { "intellect", "int" }, { "spirit", "spi" }, { "spell damage", "spell" }, { "spell power", "spell" },
  { "healing", "heal" }, { "critical", "crit" }, { "haste", "haste" }, { "to hit", "hit" }, { "defense", "def" },
  { "armor", "armor" }, { "resistance", "res" }, { "absorb", "absorb" }, { "mana", "mana" }, { "health", "hp" },
}
local function lasting(t)
  if t:find("for %d+ min") or t:find("for %d+ hour") or t:find("for %d+ hr") then return true end
  local s = tonumber(t:match("for (%d+) sec"))
  return s ~= nil and s >= 60
end
local found, foundAt = {}, {}
local function byAt(a, b) return foundAt[a] < foundAt[b] end
local function textWords(t)
  if not lasting(t) then return "" end
  wipe(found); wipe(foundAt)
  for _, x in ipairs(TEXT_WORDS) do
    local s, e = t:find(x[1], 1, true)
    if s then
      -- (the span blanked, so "attack power" is not found again inside "ranged attack power")
      t = t:sub(1, s - 1) .. string.rep(" ", e - s + 1) .. t:sub(e + 1)
      if not foundAt[x[2]] then found[#found + 1] = x[2]; foundAt[x[2]] = s end
    end
  end
  table.sort(found, byAt)
  return table.concat(found, " ")
end
local wordsOf = {} -- [item id] = its words (kept once the tables or a loaded text gave them)
local textWaits = {} -- [use spell] = true: its text not loaded yet (SPELL_TEXT_UPDATE reads its items again)
local SUB_FOOD = 5
function Cn.Words(id)
  if id == "fed" then return "" end
  local w = wordsOf[id]
  if w then return w end
  local sp = itemAura(id)
  if not sp then return "" end
  w = D.CONSUME and D.CONSUME[sp]
  if type(w) == "string" then wordsOf[id] = w return w end
  -- (a food or drink's text says what its Well Fed gives, no buff of the item's own: the tables alone, there)
  local ok, _, _, _, _, _, classID, subID = pcall(C_Item.GetItemInfoInstant, id)
  if ok and plain(classID) == 0 and plain(subID) == SUB_FOOD then wordsOf[id] = "" return "" end
  -- (its text not loaded yet: none kept, asked again as it comes)
  local text = Bf.TextOf and Bf.TextOf(id)
  if type(text) ~= "string" or text == "" then textWaits[sp] = true return "" end
  w = textWords(text)
  wordsOf[id] = w
  return w
end
local function firstWord(s) return type(s) == "string" and s:match("^(%a+)") or nil end
local function hasWord(s, w)
  for x in (s or ""):gmatch("%a+") do if x == w then return true end end
  return false
end

----------------------------------------------------------------------------
-- an item's kind: an oil, a stone or a poison (its use spell in D.IMBUE) first, then the client's class and subclass
-- (flask, elixir, potion, scroll), then "other" (class 12, or class 0 subclass 0, 5 or 8, with words: a juju, Spirit
-- of Zanza, Rumsey Rum), never a Well Fed food. Its use spell must be known: nil until then
----------------------------------------------------------------------------
local kindOf = {} -- [item id] = its kind, or false: never one (kept once sure)
function Cn.KindOf(id)
  if id == "fed" then return "fed", KIND_WORD.fed end
  local k = kindOf[id]
  if k then return k, KIND_WORD[k] end
  if k == false then return nil end
  local sp = itemAura(id)
  if not sp then return nil end
  if D.IMBUE and D.IMBUE[sp] then kindOf[id] = "weapon" return "weapon", KIND_WORD.weapon end
  local ok, _, _, _, _, _, classID, subID = pcall(C_Item.GetItemInfoInstant, id)
  if not ok then return nil end
  classID, subID = plain(classID), plain(subID)
  if type(classID) ~= "number" then return nil end
  if classID == 0 and SUB_KIND[subID] then
    k = SUB_KIND[subID]
    kindOf[id] = k
    return k, KIND_WORD[k]
  end
  local otherClass = classID == 12 or (classID == 0 and (subID == 0 or subID == 5 or subID == 8))
  if not otherClass or (D.FOOD and D.FOOD[id]) then kindOf[id] = false return nil end
  if Cn.Words(id) ~= "" then kindOf[id] = "other" return "other", KIND_WORD.other end
  -- (its words known to be none: never one; its text not loaded yet: asked again)
  if wordsOf[id] ~= nil then kindOf[id] = false end
  return nil
end
-- an item 0.2.2 learned as a habit with no stat words (a class 0 item of subclass 0 or 8, Swiftness of Zanza; a class
-- 12 one with words): no kind of its own, its uses still learned and counted as Other's
local function usedKind(id)
  return Cn.KindOf(id) == nil and itemAura(id) ~= nil and Bf.KindOf(id) ~= nil
end
-- an item that counts: its kind known, and words, or used once with a lasting aura (Water Breathing, Swiftness of
-- Zanza). A weapon's oil or stone leaves no aura on you: its kind is enough
function Cn.Counts(id)
  local kind = Cn.KindOf(id)
  if not kind then return usedKind(id) and hitsOf(id) >= 1 end
  if kind == "weapon" or kind == "fed" or Cn.Words(id) ~= "" then return true end
  return hitsOf(id) >= 1
end

-- 0.2.2's answer for an item, kept for its callers: the bar's word and the subclass; a class 12 item only with words
local LEGACY = { [1] = "Drink", [2] = "Drink", [3] = "Drink", [4] = "Read", [8] = "Use", [0] = "Use" }
function Bf.KindOf(id)
  local ok, _, _, _, _, _, classID, subID = pcall(C_Item.GetItemInfoInstant, id)
  if not ok then return nil end
  classID, subID = plain(classID), plain(subID)
  if classID == 0 then return LEGACY[subID or -1], subID end
  if classID == 12 then
    local sp = itemAura(id)
    local w = sp and D.CONSUME and D.CONSUME[sp]
    if type(w) == "string" and w ~= "" then return "Use", nil end
  end
  return nil
end

----------------------------------------------------------------------------
-- groups: items that take each other's place. A learned pair (B's aura came as A's went, as you used B; the account's,
-- by a root id), a kin (the same kind and first word: the Mongoose and Greater Agility are elixir:agi), every flask (the
-- client's own text: one flask at a time). Two of a group's auras seen on you at once let that group go
----------------------------------------------------------------------------
local function groupOf(id)
  local p, g, n = pairsDB(), id, 0
  while p[g] and p[g] < g and n < 64 do g = p[g]; n = n + 1 end
  return g
end
Bf.GroupOf = groupOf
Cn.GroupOf = groupOf
local function learnPair(a, b)
  local p = pairsDB()
  local n = 0
  for _ in pairs(p) do n = n + 1 end
  if n >= 64 then return end
  local ga, gb = groupOf(a), groupOf(b)
  if ga == gb then return end
  p[math.max(ga, gb)] = math.min(ga, gb)
end
function Cn.KinKey(id)
  if id == "fed" then return nil end
  local kind, w = Cn.KindOf(id), firstWord(Cn.Words(id))
  if kind and kind ~= "weapon" and w then return kind .. ":" .. w end
  return nil
end
local keyPool = {}
local function groupKeys(id)
  local out = keyPool[id]
  if not out then out = {}; keyPool[id] = out end
  for i = #out, 1, -1 do out[i] = nil end
  out[1] = "L" .. groupOf(id)
  local kk = Cn.KinKey(id)
  if kk and not kinStacks()[kk] then out[#out + 1] = "K" .. kk end
  if Cn.KindOf(id) == "flask" and A.Acct().flasksStack ~= true then out[#out + 1] = "F" end
  return out
end
Cn.GroupKeys = groupKeys

-- a consumable's aura on you: by its spell, else its name in your language
local function auraOn(id, names, ids)
  local sp = itemAura(id)
  if not sp then return nil end
  return ids[sp] or names[L.SpellName(sp, "") or ""]
end
Bf.AuraOn = auraOn
Cn.AuraOn = auraOn

-- the items the groups are read over: what you carry that counts, and what you have used (a habit's last bottle gone,
-- its aura still on), never a weapon's
local knownList, knownSeen = {}, {}
local function known()
  wipe(knownList); wipe(knownSeen)
  for id in pairs(B.Bags()) do
    if Cn.KindOf(id) ~= "weapon" and Cn.Counts(id) then knownList[#knownList + 1] = id; knownSeen[id] = true end
  end
  for id, e in pairs(habitsDB()) do
    if type(id) == "number" and type(e) == "table" and not knownSeen[id] and Cn.KindOf(id) ~= "weapon" then
      knownList[#knownList + 1] = id; knownSeen[id] = true
    end
  end
  table.sort(knownList)
  return knownList
end
Cn.Known = known

----------------------------------------------------------------------------
-- your role, and whether an item fits it. A role only guessed from your class (no choice, no talents read, no group
-- mark: a paladin reads as a healer) hides nothing; an "other" item with Stamina fits everyone (Spirit of Zanza); one
-- with no stat words fits no one
----------------------------------------------------------------------------
-- (read once a moment: a refresh asks it for every item; a role chosen in Settings is read again at once)
local roleT, roleChoice, roleV, roleFrom
local function myRole()
  local t, choice = A.Now(), A.Char().role
  if roleT ~= t or roleChoice ~= choice then
    local r, _, f = A.Roster.MyRole()
    roleT, roleChoice, roleV, roleFrom = t, choice, r, f
  end
  return roleV, roleFrom
end
function Cn.Fits(id)
  local role, from = myRole()
  local w = Cn.Words(id)
  -- (no stat words: nothing in it fits a role; a habit or a choice asks for it)
  if w == "" then return false end
  if from == "class" then return true end
  if Cn.KindOf(id) == "other" and hasWord(w, "sta") then return true end
  return Bf.Fits(id, role) and true or false
end

----------------------------------------------------------------------------
-- the one decision: asked for here, and why. The bar, Before the pull, the tab's chips and the diag ask it; the master
-- switch (Cn.On) is the providers' to read
----------------------------------------------------------------------------
local HABIT_PLACES = { inst = { pvp = true, dungeon = true, raid = true }, world = { solo = true, pvp = true, dungeon = true, raid = true }, pull = {} }
local function neverKey(id) return id == "fed" and "eat" or ("consume:" .. id) end
Cn.NeverKey = neverKey
function Cn.AsksIn(id, where)
  where = where or Cn.Where()
  if B.Never(neverKey(id)) then return false, "never" end
  local t = Cn.Settings()
  local own = t.items[id]
  if type(own) == "table" and type(own[where]) == "boolean" then
    if own[where] then return true, "chosen" end
    return false, "off"
  end
  if id ~= "fed" and isHabit(id) and HABIT_PLACES[t.habits][where] then return true, "habit" end
  local kind = id == "fed" and "fed" or (Cn.KindOf(id) or "other")
  -- (a 0.2.2 ready check's Never, pull:<id>: 0.2.2 asked a flask, elixir or scroll out of a fight only as a habit
  -- (above), so no fit or kind default of 0.2.3 brings back one the player hid. Its weapon reminder was its own)
  if kind ~= "fed" and kind ~= "weapon" and B.Never("pull:" .. id) then return false, "never" end
  if not Cn.KindDefault(kind, where) then return false, "off" end
  if kind == "fed" or kind == "weapon" then return true, "default" end
  if quietDB()[id] then return false, "unused" end
  -- (no stat words, Water Breathing: it fits no role because it raises nothing, not because of yours. Off, as its
  -- chips show; a chip or a habit asks it)
  if Cn.Words(id) == "" then return false, "off" end
  if Cn.Fits(id) then return true, "fit" end
  return false, "role"
end
function Cn.Asks(id, where) return (Cn.AsksIn(id, where)) == true end
-- an item's own choice for a place (the tab's chips, the icon's right-click): it speaks again (quiet let go)
function Cn.SetChoice(id, where, v)
  local items = Cn.Settings().items
  local own = items[id]
  if type(own) ~= "table" then own = {}; items[id] = own end
  own[where] = v and true or false
  if id ~= "fed" then quietDB()[id] = nil end
  changedFor(id)
  if A.Window then A.Window.Refresh() end
end
-- back to the defaults: no choice of its own, and no 0.2.2 Never of a ready check
function Cn.ClearChoice(id)
  Cn.Settings().items[id] = nil
  if id ~= "fed" and B.Never("pull:" .. id) then B.SetNever("pull:" .. id, nil, false) end
  changedFor(id)
  if A.Window then A.Window.Refresh() end
end
function Cn.HasChoice(id)
  local own = Cn.Settings().items[id]
  if type(own) ~= "table" then return false end
  for _, p in ipairs(Cn.PLACES) do if own[p[1]] ~= nil then return true end end
  return false
end
function Cn.Quiet(id) return quietDB()[id] ~= nil end
function Cn.Unquiet(id) if id ~= "fed" then quietDB()[id] = nil end end

----------------------------------------------------------------------------
-- learning: a use whose aura came, a minute or more long, is one more hit (a use in a fight too: it waits for the first
-- read that can see your auras, its length counted from the use; its aura gone by then, it counts when the client's
-- tables give it stat words, which they give only a buff of a minute or more); B's aura coming as A's went, as you
-- used B, a pair; two of a group's auras on you at once, that group let go (collected first, set after the walk)
----------------------------------------------------------------------------
local pending = {}  -- [item id] = when you used it (its aura not seen yet)
local inFight = {}  -- [item id] = uses made in a fight, waiting for a read that can see (pending: the last one's time)
local onSince = {}  -- [item id] = its aura on at the last look
local missFrom, missN = {}, {} -- [item id] = its ShownFor at the last miss or use; a fitting item's misses (this session)
local HABIT_CAP, QUIET_CAP = 30, 60
function Cn.OnUse(id)
  local kind = Cn.KindOf(id)
  if not kind then
    if not usedKind(id) then return end
    kind = "other"
  end
  quietDB()[id] = nil
  missN[id] = nil
  missFrom[id] = B.ShownFor("consume" .. id)
  if kind == "weapon" then
    -- (an oil leaves no aura on you: its use is kept for "the one used last")
    local h = habitsDB()
    local e = h[id]
    if type(e) ~= "table" then e = nil; if roomFor(h, HABIT_CAP) then e = { hits = 0, miss = 0 }; h[id] = e end end
    if e then e.at = stamp() end
    return
  end
  pending[id] = A.Now()
  if A.Fighting() then inFight[id] = (inFight[id] or 0) + 1 else inFight[id] = nil end
  A.After(1, function() B.Dirty("mine") end, "consumables: a use")
end
local stackSeen, stackHit = {}, {}
-- (n more uses of an item with a lasting aura: its habit's hits)
local function hit(h, id, n)
  local e = h[id]
  if type(e) ~= "table" then
    e = nil
    if roomFor(h, HABIT_CAP) then e = { hits = 0, miss = 0 }; h[id] = e end
  end
  if e then e.hits, e.miss, e.spell, e.at = (e.hits or 0) + n, 0, itemAura(id), stamp() end
end
local function watch(names, ids, hidden)
  if hidden then return end
  local t = A.Now()
  local h = habitsDB()
  local came, went
  for id, at in pairs(pending) do
    local a = auraOn(id, names, ids)
    local fought = inFight[id]
    if a then
      pending[id], inFight[id] = nil, nil
      -- (a use in a fight is first seen after it: its aura's length from the drink, not what the rest of the fight
      -- left of it; a 2-minute potion drunk 80 s before a boss died still counts)
      if not a.exp or a.exp - (fought and at or t) >= 50 then hit(h, id, fought or 1) end
    elseif fought then
      -- (its aura gone by the first read that sees, the fight longer than it: the client's tables say whether it lasts
      -- a minute or more, words only then (Cn.Words); a few seconds first, should its aura still be coming)
      if t - at > 6 then
        pending[id], inFight[id] = nil, nil
        if Cn.Words(id) ~= "" then hit(h, id, fought) end
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
  -- two of a group on you at once (two different auras: one aura two items' spells share a name with is one): that
  -- group is no group
  wipe(stackSeen); wipe(stackHit)
  for _, id in ipairs(known()) do
    local a = auraOn(id, names, ids)
    if a then
      for _, k in ipairs(groupKeys(id)) do
        local was = stackSeen[k]
        if was and was ~= a then stackHit[k] = true elseif not was then stackSeen[k] = a end
      end
    end
  end
  if next(stackHit) then
    local p = pairsDB()
    for k in pairs(stackHit) do
      local kind, rest = k:sub(1, 1), k:sub(2)
      if kind == "K" then kinStacks()[rest] = true
      elseif kind == "F" then A.Acct().flasksStack = true
      elseif kind == "L" then
        local root = tonumber(rest)
        -- (every member of that learned group let go: collected, then cleared)
        wipe(stackSeen)
        for m in pairs(p) do if groupOf(m) == root then stackSeen[m] = true end end
        for m in pairs(stackSeen) do p[m] = nil end
      end
    end
    B.Dirty("mine")
  end
end
A.Camp.Watch(watch)

----------------------------------------------------------------------------
-- quiet: an item asked for by habit or because it fits, shown 600 s on screen (Bar's ShownFor: never in a fight, the
-- bar away or off, nor greyed on the potions' shared cooldown) and not used, is one miss; three, it goes quiet (a
-- habit loses its habit too). 60 kept, the oldest let go first. A use, or a chip clicked on its row, lets it speak
-- again
----------------------------------------------------------------------------
local ASK_FOR = 600
local function quietIt(id)
  local q = quietDB()
  local n, oldK, oldT = 0, nil, nil
  for k, at in pairs(q) do
    n = n + 1
    local v = tonumber(at) or 0
    if not oldT or v < oldT then oldK, oldT = k, v end
  end
  if n >= QUIET_CAP and oldK ~= nil then q[oldK] = nil end
  q[id] = stamp()
end
function Cn.MissCount(id)
  local e = habitsDB()[id]
  if type(e) == "table" and (e.hits or 0) >= 2 then return e.miss or 0 end
  return missN[id] or 0
end
-- (asked and missing: its time on screen read; a miss, three and quiet. true: it stays on the bar)
local function keepAsking(id, reason, ctx)
  if reason ~= "habit" and reason ~= "fit" then return true end
  local seen = B.ShownFor("consume" .. id)
  local from = missFrom[id]
  if from == nil or from > seen then from = seen; missFrom[id] = seen end
  if seen - from >= ASK_FOR then
    missFrom[id], from = seen, seen
    local n
    local e = habitsDB()[id]
    if reason == "habit" and type(e) == "table" then
      e.miss = (e.miss or 0) + 1
      n = e.miss
    else
      missN[id] = (missN[id] or 0) + 1
      n = missN[id]
    end
    if n >= 3 then
      quietIt(id)
      if reason == "habit" then habitsDB()[id] = nil end
      missN[id], missFrom[id] = nil, nil
      return false
    end
  end
  wakeFor(ctx.t + ASK_FOR - (seen - from), ctx.t)
  return true
end

----------------------------------------------------------------------------
-- the bar: yours (consume) and Before the pull (pull)
----------------------------------------------------------------------------
local SOON, FED_SOON, PULL_SOON = 60, 120, 180
local WHY = { habit = "You keep this one up.", chosen = "You chose it for here.", fit = "It fits your role.", default = "It fits your role." }
local REASON_RANK = { chosen = 1, habit = 2, fit = 3, default = 3 }
local KIND_RANK = { flask = 1, elixir = 2, scroll = 3, potion = 4, other = 5 }
local PULL_RANK = { flask = 1, elixir = 2, scroll = 3 }
local cand, reasonOf, atOf, covered, taken, soonLeft, done = {}, {}, {}, {}, {}, {}, {}
local function barOrder(a, b)
  local ra, rb = REASON_RANK[reasonOf[a]] or 4, REASON_RANK[reasonOf[b]] or 4
  if ra ~= rb then return ra < rb end
  local ta, tb = atOf[a] or 0, atOf[b] or 0
  if ta ~= tb then return ta > tb end
  local ka, kb = KIND_RANK[Cn.KindOf(a) or "other"] or 6, KIND_RANK[Cn.KindOf(b) or "other"] or 6
  if ka ~= kb then return ka < kb end
  return a < b
end
-- (Before the pull: flasks, elixirs, scrolls, the rest; then the bar's order, so a group's member is your choice, your
-- habit, then a fit, the one used last first: never the lowest id over the flask you use)
local function pullOrder(a, b)
  local ra, rb = PULL_RANK[Cn.KindOf(a) or ""] or 4, PULL_RANK[Cn.KindOf(b) or ""] or 4
  if ra ~= rb then return ra < rb end
  return barOrder(a, b)
end
-- the groups covered by a member's aura on you with soon or more left (the item itself too: never asked while its own
-- buff is up); under that, the shortest time left a group's. Over what counts and your habits, and the candidates
-- asked here (extra: one there by a choice alone, never used, its own buff still covers it)
local function coverOne(id, names, ids, t, soon)
  local a = auraOn(id, names, ids)
  if not a then return end
  local left = a.exp and a.exp - t or nil
  for _, k in ipairs(groupKeys(id)) do
    if not left or left >= soon then covered[k] = id
    elseif left > 0 and (not soonLeft[k] or left < soonLeft[k]) then soonLeft[k] = left end
  end
  if left and left >= soon then wakeFor(a.exp - soon, t) elseif left and left > 0 then wakeFor(a.exp, t) end
end
local function cover(names, ids, t, soon, extra)
  wipe(covered); wipe(soonLeft)
  for _, id in ipairs(known()) do coverOne(id, names, ids, t, soon) end
  for _, id in ipairs(extra or {}) do if not knownSeen[id] then coverOne(id, names, ids, t, soon) end end
end
local function free(id)
  for _, k in ipairs(groupKeys(id)) do
    if covered[k] or taken[k] then return false end
  end
  return true
end
local function take(id) for _, k in ipairs(groupKeys(id)) do taken[k] = true end end
-- an item's cooldown on its record (every potion shares one): waiting, its sweep, a look again at its end
local function cooling(rec, id, t)
  local st, du = S.ItemCD(id)
  if du > 0 and st + du > t then
    rec.cdStart, rec.cdDur, rec.lit = st, du, false
    -- (no click to promise while it waits: the tooltip says when)
    rec.clickWord = nil
    rec.why = (rec.why and (rec.why .. " ") or "") .. "Ready when its cooldown ends."
    wakeFor(st + du, t)
    return true
  end
  return false
end
-- (one you can't use now, by S.Usable: its required level above yours, a red line on it (a class, a race), the game's
-- own no; one the client has no data for yet waits. The owner, 2026-11-23: "It tells me to use items outside my
-- level or not for my class or race, that can't happen")
local function unusable(id)
  local at = B.Bags()[id]
  return at ~= nil and S.Usable(id, at.bag, at.slot) == false
end
-- (a candidate: what you carry that counts, not a weapon's, your habits you carry, and one of a known kind you chose
-- for a place: its use count gone, quieted or let go, the choice still asks. Never one you can't use)
local function candidate(id)
  local kind = Cn.KindOf(id)
  if kind == "weapon" then return false end
  if not (isHabit(id) or Cn.Counts(id) or (kind ~= nil and Cn.HasChoice(id))) then return false end
  return not unusable(id)
end
-- the right-click's own entries (Bar.lua's menu, after a divider): where it is asked, the same words as the gear's. On
-- a Before the pull icon, where the pull asks for it (its kinds and quiet do not limit a ready check), so one click
-- turns off what the box shows
local function menu(root, rec)
  local id = rec.item
  if id == nil then return end
  local asks = Cn.Asks
  if rec.p and rec.p.key == "pull" and id ~= "fed" then asks = Cn.PullWants end
  if root.CreateTitle then root:CreateTitle("Ask for it in") end
  for _, p in ipairs(Cn.PLACES) do
    local where = p[1]
    root:CreateCheckbox(p[2], function() return asks(id, where) end,
      A.Safe(function() Cn.SetChoice(id, where, not asks(id, where)) end, "consumables: ask for it in"))
  end
end
local TAB = { "consume", "Consumables..." }
Cn.Menu, Cn.TAB = menu, TAB -- (the weapon's oil the tab chose: Buffs.lua)
Cn.lastAsked = 0
-- (read again as Before the pull starts and ends: it shows nothing while the pull asks, and comes back after)
B.Add({ key = "consume", part = "mine", order = 120, groups = { "mine", "consume", "pull" }, timed = true, menu = menu, window = TAB,
  read = function(add, ctx)
    Cn.lastAsked = 0
    -- (at a ready check Before the pull asks instead)
    if ctx.pull or not Cn.On() or ctx.town then return end
    local Camp = A.Camp
    local names, ids, hidden = Camp.Mine()
    if hidden then return end
    local where = ctx.where or Cn.Where()
    -- Well Fed: missing where its chips say (the open world is the camp's Eat), or under two minutes left anywhere
    local fr = Camp.FedRec(names, ids)
    local fedLeft = type(fr) == "table" and fr.exp and fr.exp - ctx.t or nil
    if fedLeft then wakeFor(fr.exp - FED_SOON, ctx.t) end
    local soon = fedLeft and fedLeft > 0 and fedLeft < FED_SOON
    if not B.Never("eat") and (soon or (not fr and where ~= "solo" and Cn.Asks("fed", where))) then
      local food = Camp.BestFood(where ~= "solo")
      if food then
        local rec = add()
        rec.key, rec.item = "food", "fed"
        rec.tex, rec.lit, rec.count = L.ItemIcon(food, 133945), true, S.Count(food)
        rec.word = soon and countdown(fedLeft) or "Eat"
        if soon then rec.status, rec.timed = "warn", true end
        B.Click(rec, "item", food)
        rec.never, rec.neverName = "eat", "Well Fed"
        rec.name = L.ItemName(food, "Food")
        rec.why = soon and "Well Fed ends soon: eat again to keep it." or "Not Well Fed."
        rec.clickWord = "eat it"
      end
    end
    -- the items: asked here, missing or under a minute left; one of each group, three at most
    wipe(cand); wipe(reasonOf); wipe(atOf); wipe(taken); wipe(done)
    local h = habitsDB()
    for id in pairs(B.Bags()) do
      if candidate(id) then
        local asks, reason = Cn.AsksIn(id, where)
        if asks then
          cand[#cand + 1] = id
          reasonOf[id] = reason
          local e = h[id]
          atOf[id] = type(e) == "table" and tonumber(e.at) or 0
        end
      end
    end
    table.sort(cand, barOrder)
    cover(names, ids, ctx.t, SOON, cand)
    local n = 0
    -- (a countdown first: the one ending keeps its group's place)
    for pass = 1, 2 do
      for _, id in ipairs(cand) do
        if n < 3 and not done[id] then
          local a = auraOn(id, names, ids)
          local left = a and a.exp and a.exp - ctx.t or nil
          local ending = a ~= nil and left ~= nil and left > 0 and left < SOON
          if ((pass == 1 and ending) or (pass == 2 and not a)) and free(id) then
            done[id] = true
            if ending or keepAsking(id, reasonOf[id], ctx) then
              n = n + 1
              take(id)
              local rec = add()
              rec.key, rec.item = "consume" .. id, id
              rec.tex, rec.lit, rec.count = L.ItemIcon(id, 134400), true, S.Count(id)
              local _, word = Cn.KindOf(id)
              rec.word = ending and countdown(left) or (word or "Use")
              if ending then rec.status, rec.timed = "warn", true end
              -- (on you: a juju takes a target, and you are it)
              B.Click(rec, "item", id, "player")
              rec.never, rec.neverName = "consume:" .. id, L.ItemName(id, "this one")
              rec.name = L.ItemName(id, "A consumable")
              rec.why = ending and "Its buff ends soon." or WHY[reasonOf[id]]
              rec.clickWord = "use it"
              cooling(rec, id, ctx.t)
            end
          end
        end
      end
    end
    Cn.lastAsked = n
  end,
})

-- whether Before the pull asks for an item where you stand: Never (its own, or a 0.2.2 ready check's) never; its own
-- choice for here; else a habit, or one that fits you and is a flask, an elixir or a scroll, or a kind on here by
-- default (Other in raids: Spirit of Zanza, a juju). Kind defaults, quiet and where habits are asked never hide one
function Cn.PullWants(id, where)
  if B.Never("consume:" .. id) or B.Never("pull:" .. id) then return false end
  where = where or Cn.Where()
  local own = Cn.Settings().items[id]
  -- (a choice of false is a choice: read as it is, never through "and ... or nil")
  local choice
  if type(own) == "table" then choice = own[where] end
  if choice == true or choice == false then return choice end
  if isHabit(id) then return true end
  local kind = Cn.KindOf(id)
  if kind == "weapon" or not Cn.Fits(id) then return false end
  return PULL_RANK[kind or ""] ~= nil or Cn.KindDefault(kind or "other", where)
end
local pullBuf = {}
B.Add({ key = "pull", part = "pull", order = 300, groups = { "mine", "pull", "consume" }, timed = true, menu = menu, window = TAB,
  read = function(add, ctx)
    if not ctx.pull or not Cn.On() then return end
    local Camp = A.Camp
    local names, ids, hidden = Camp.Mine()
    if hidden then return end
    local where = ctx.where or Cn.Where()
    -- food: not Well Fed, or under three minutes left (Well Fed's Never: not even here)
    local fr = Camp.FedRec(names, ids)
    local fedLeft = type(fr) == "table" and fr.exp and fr.exp - ctx.t or nil
    if fedLeft then wakeFor(fr.exp - PULL_SOON, ctx.t) end
    if (not fr or (fedLeft and fedLeft > 0 and fedLeft < PULL_SOON)) and not B.Never("eat") then
      local id = Camp.BestFood(true)
      if id then
        local rec = add()
        rec.key, rec.item = "pullfood", "fed"
        rec.tex, rec.lit, rec.count, rec.word = L.ItemIcon(id, 133945), true, S.Count(id), "Eat"
        if fedLeft then rec.word, rec.status, rec.timed = countdown(fedLeft), "warn", true end
        B.Click(rec, "item", id)
        rec.never, rec.neverName, rec.name, rec.clickWord = "pullfood", "Food before the pull", L.ItemName(id, "Well Fed"), "eat it"
        -- (no Ask for it in: Well Fed's places do not ask it here, its Never does)
        rec.menu = false
      end
    end
    -- the items: Cn.PullWants (its own choice for here first; else every habit, every flask, elixir and scroll that
    -- fits you, and what a kind's default asks here)
    wipe(pullBuf); wipe(taken); wipe(reasonOf); wipe(atOf); wipe(done)
    local h = habitsDB()
    local items = Cn.Settings().items
    for id in pairs(B.Bags()) do
      if candidate(id) and Cn.PullWants(id, where) then
        pullBuf[#pullBuf + 1] = id
        -- (why it is wanted here, in 1.4's words: its own choice, a habit, else a fit)
        local own = items[id]
        reasonOf[id] = (type(own) == "table" and own[where] == true) and "chosen" or (isHabit(id) and "habit") or "fit"
        local e = h[id]
        atOf[id] = type(e) == "table" and tonumber(e.at) or 0
      end
    end
    table.sort(pullBuf, pullOrder)
    cover(names, ids, ctx.t, PULL_SOON, pullBuf)
    local shownN = 0
    -- (one whose own buff ends first: it keeps its group's place and shows its own countdown; then the rest, plain)
    for pass = 1, 2 do
      for _, id in ipairs(pullBuf) do
        local a = not done[id] and auraOn(id, names, ids) or nil
        local left = a and a.exp and a.exp - ctx.t or nil
        if left and left <= 0 then left = nil end
        if shownN < 4 and not done[id] and (pass == 2 or left) and free(id) then
          done[id] = true
          shownN = shownN + 1
          take(id)
          local rec = add()
          rec.key, rec.item = "flask" .. id, id
          local _, word = Cn.KindOf(id)
          rec.tex, rec.lit, rec.count, rec.word = L.ItemIcon(id, 134400), true, S.Count(id), word or "Use"
          if left then rec.word, rec.status, rec.timed = countdown(left), "warn", true end
          B.Click(rec, "item", id, "player")
          rec.never = "consume:" .. id
          rec.name = L.ItemName(id, "Elixir")
          rec.neverName, rec.clickWord = rec.name, "use it"
          if left then rec.why = "Its buff ends soon." end
          cooling(rec, id, ctx.t)
        end
      end
    end
  end,
})

----------------------------------------------------------------------------
-- the weapon's: of the oils, stones and poisons you carry and can use asked for here that go on the main hand's kind
-- of weapon, the one chosen for here; of those alike, the one the main hand's weapon usually has (own: Buffs.lua's
-- per-weapon habit), else the one used last (on either hand), else the lowest id (Buffs.lua's weapon provider asks it
-- for a bare main hand; none that goes on it, the weapon's own habit as in 0.2.2)
----------------------------------------------------------------------------
-- (the main hand's weapon subclass, nil for none or not told yet)
function Cn.MainHandKind()
  local w = plain(call(GetInventoryItemID, "player", 16))
  if type(w) ~= "number" then return nil end
  local ok, _, _, _, _, _, classID, subID = pcall(C_Item.GetItemInfoInstant, w)
  if not ok or plain(classID) ~= 2 then return nil end
  subID = plain(subID)
  return type(subID) == "number" and subID or nil
end
-- (an oil, stone or poison goes on a weapon of that subclass: D.IMBUE's mask of subclasses; true for any, or a kind
-- not told: a Dense Sharpening Stone never on a mace, the game refuses it)
function Cn.GoesOn(id, sub)
  local sp = itemAura(id)
  local m = sp and D.IMBUE and D.IMBUE[sp]
  if type(m) ~= "number" or type(sub) ~= "number" then return true end
  return math.floor(m / 2 ^ sub) % 2 == 1
end
function Cn.WeaponFor(where, own, sub)
  local pick, pr, pat
  local h = habitsDB()
  for id in pairs(B.Bags()) do
    if Cn.KindOf(id) == "weapon" and not unusable(id) and Cn.GoesOn(id, sub) then
      local asks, reason = Cn.AsksIn(id, where)
      if asks then
        local r = (reason == "chosen" and 1 or 3) - (id == own and 1 or 0)
        local e = h[id]
        local at = type(e) == "table" and tonumber(e.at) or 0
        if not pick or r < pr or (r == pr and (at > pat or (at == pat and id < pick))) then pick, pr, pat = id, r, at end
      end
    end
  end
  return pick
end

----------------------------------------------------------------------------
-- the tab's rows and states
----------------------------------------------------------------------------
-- the rows: Well Fed; then each kind's items you carry, have used or chose for, carried first, then by name
local rowList, rowKind, rowSeen, rowCarried, rowName = {}, {}, {}, {}, {}
local function rowOrder(a, b)
  if rowCarried[a] ~= rowCarried[b] then return rowCarried[a] end
  if rowName[a] ~= rowName[b] then return rowName[a] < rowName[b] end
  return a < b
end
local byKind = {}
function Cn.Rows()
  wipe(rowList); wipe(rowKind); wipe(rowSeen); wipe(rowCarried); wipe(rowName)
  for _, k in ipairs(Cn.KINDS) do byKind[k] = byKind[k] or {}; wipe(byKind[k]) end
  local bags = B.Bags()
  local function addRow(id)
    if rowSeen[id] then return end
    local kind = Cn.KindOf(id)
    if not kind and hitsOf(id) >= 1 then kind = "other" end
    if not kind or kind == "fed" then return end
    rowSeen[id] = true
    rowKind[id] = kind
    rowCarried[id] = bags[id] ~= nil
    rowName[id] = L.ItemName(id, "Item " .. id)
    local list = byKind[kind]
    list[#list + 1] = id
  end
  for id in pairs(bags) do if Cn.Counts(id) then addRow(id) end end
  for id, e in pairs(habitsDB()) do
    if type(id) == "number" and type(e) == "table" and ((e.hits or 0) >= 1 or bags[id]) and Cn.Counts(id) then addRow(id) end
  end
  for id, own in pairs(Cn.Settings().items) do if type(id) == "number" and type(own) == "table" then addRow(id) end end
  for _, k in ipairs(Cn.KINDS) do table.sort(byKind[k], rowOrder) end
  return byKind
end
function Cn.Carried(id) return B.Bags()[id] ~= nil end

-- a row's state where you stand: its word and its colour's name (Look's L.C)
local function onWord(a, t)
  if a and a.exp and a.exp > t then return "On you " .. countdown(a.exp - t) end
  return "On you"
end
-- (an aura past its end the client still lists, the server's removal not in yet: gone. No end, exp 0: on)
local function ended(a, t) return type(a) == "table" and type(a.exp) == "number" and a.exp > 0 and a.exp <= t end
-- why the bar shows none of the consumables where you stand (nil: nothing stops it): "bar", Show the bar off; "none",
-- Nothing in this dungeon or raid (Before the pull too); "mine", Your buffs and weapon off (their part: Before the pull
-- and the camp's Eat still ask)
function Cn.Blocked()
  local s = A.Settings()
  if s.on == false then return "bar" end
  if s.instance == "none" and B.InstanceKind and B.InstanceKind() then return "none" end
  if s.mine == false then return "mine" end
  return nil
end
-- (an item's own: the part that would show it here off. Well Fed in the open world is the camp's Eat)
local function blocked(id, where)
  local why = Cn.Blocked()
  if why == "bar" or why == "none" then return true end
  if id == "fed" and where == "solo" then return A.Settings().camp == false end
  return why == "mine"
end
-- (one you carry and can't use: its required level, else the game's no)
local function cantUse(id)
  if not unusable(id) then return nil end
  local get = C_Item and C_Item.GetItemInfo or GetItemInfo
  local name, _, _, _, minLevel = call(get, id)
  minLevel = plain(minLevel)
  local level = plain(call(UnitLevel, "player")) or 1
  if plain(name) ~= nil and type(minLevel) == "number" and minLevel > level then return "Level " .. minLevel end
  return "Can't use"
end
function Cn.State(id, where, names, ids, t)
  t = t or A.Now()
  local asks, reason = Cn.AsksIn(id, where)
  if not asks then
    if reason == "never" then return "Never", "DIM" end
    if reason == "role" then return "Not your role", "DIM" end
    if reason == "unused" then return "Unused", "DIM" end
    for _, p in ipairs(Cn.PLACES) do if p[1] ~= where and Cn.Asks(id, p[1]) then return "Not here", "DIM" end end
    return "Off", "DIM"
  end
  if A.Fighting() or not names then return "In a fight", "DIM" end
  if A.Yes(IsResting) then return "In town", "DIM" end
  if id == "fed" then
    local fr = A.Camp.FedRec(names, ids)
    if fr and not ended(fr, t) then return onWord(fr, t), "GOOD" end
    if not A.Camp.BestFood(where ~= "solo") then return "None left", "DIM" end
    if blocked(id, where) then return "Off in Settings", "DIM" end
    return "Missing", "WARN"
  end
  -- (its buff on you first: a potion's lasts as long as the potions' cooldown, a last flask's two hours past its bottle)
  if Cn.KindOf(id) == "weapon" then
    -- (the bar's Never on its icon is the oil's own, consume:<id>: AsksIn said Never above)
    if Bf.TempEnchant and Bf.TempEnchant(16) then return "On you", "GOOD" end
    -- (the weapon in your main hand takes none of this kind: the bar never asks it for that one)
    if not Cn.GoesOn(id, Cn.MainHandKind()) then return "Wrong weapon", "DIM" end
  else
    local a = auraOn(id, names, ids)
    if a and not ended(a, t) then return onWord(a, t), "GOOD" end
    for _, other in ipairs(known()) do
      local oa = other ~= id and auraOn(other, names, ids)
      if oa and not ended(oa, t) then
        local ka = groupKeys(other)
        for _, k in ipairs(groupKeys(id)) do
          for _, k2 in ipairs(ka) do if k == k2 then return "One like it on", "DIM" end end
        end
      end
    end
  end
  if S.Count(id) <= 0 then return "None left", "DIM" end
  local st, du = S.ItemCD(id)
  if du > 0 and st + du > t then return "Cooldown " .. countdown(st + du - t), "DIM" end
  local no = cantUse(id)
  if no then return no, "DIM" end
  if blocked(id, where) then return "Off in Settings", "DIM" end
  return "Missing", "WARN"
end
-- the members of an item's group you have seen (learned or kin), by name, for its tooltip
function Cn.Replaces(id)
  local out = {}
  local mine = {}
  for _, k in ipairs(groupKeys(id)) do if k ~= "F" then mine[k] = true end end
  for _, other in ipairs(known()) do
    if other ~= id then
      for _, k in ipairs(groupKeys(other)) do
        if mine[k] then out[#out + 1] = L.ItemName(other, "Item " .. other); break end
      end
    end
  end
  return out
end

-- what an item raises, in a row's words: its first two ("Agility, crit"), Ranged attack power dropped beside Attack
-- power; then how many you carry
local LABEL = { str = "Strength", agi = "Agility", sta = "Stamina", int = "Intellect", spi = "Spirit", all = "All stats",
  ap = "Attack power", rap = "Ranged attack power", phys = "Physical damage", spell = "Spell damage", dmg = "Damage",
  fire = "Fire damage", frost = "Frost damage", shadow = "Shadow damage", nature = "Nature damage", arcane = "Arcane damage",
  holy = "Holy damage",
  heal = "Healing", crit = "Crit", haste = "Haste", hit = "Hit", exp = "Expertise", mp5 = "Mana regen", mana = "Mana",
  hp = "Health", armor = "Armor", res = "Resistance", absorb = "Absorb", def = "Defense" }
Cn.LABEL = LABEL
function Cn.SubLine(words, count)
  local list = {}
  local ap = hasWord(words, "ap")
  -- (whole words, digits too: mp5 is one)
  for w in (words or ""):gmatch("%w+") do
    if LABEL[w] and not (w == "rap" and ap) and #list < 2 then list[#list + 1] = w end
  end
  local out = ""
  for i, w in ipairs(list) do
    local s = LABEL[w]
    if i == 1 then out = s else out = out .. ", " .. s:lower() end
  end
  local carried = count and count > 0 and (count .. " in your bags") or nil
  if out ~= "" and carried then return out .. ". " .. carried end
  if out ~= "" then return out .. "." end
  return carried or ""
end

----------------------------------------------------------------------------
-- /cauras diag's line (numbers and words, no names)
----------------------------------------------------------------------------
function Cn.DiagLine()
  local t = Cn.Settings()
  local where = Cn.Where()
  local role, spec, from = A.Roster.MyRole()
  local nCarried, nFit, nChosen, nHabit, nQuiet, nCool = 0, 0, 0, 0, 0, 0
  local now = A.Now()
  for id in pairs(B.Bags()) do
    if Cn.Counts(id) then
      nCarried = nCarried + 1
      local _, reason = Cn.AsksIn(id, where)
      if reason == "fit" then nFit = nFit + 1 elseif reason == "chosen" then nChosen = nChosen + 1 end
      local st, du = S.ItemCD(id)
      if du > 0 and st + du > now then nCool = nCool + 1 end
    end
  end
  for _, e in pairs(habitsDB()) do if type(e) == "table" and (e.hits or 0) >= 2 then nHabit = nHabit + 1 end end
  for _ in pairs(quietDB()) do nQuiet = nQuiet + 1 end
  local nNever, nPull = 0, 0
  for k in pairs(A.Settings().never) do
    if type(k) == "string" then
      if k == "eat" or k:find("^consume:") then nNever = nNever + 1 elseif k:find("^pull:") then nPull = nPull + 1 end
    end
  end
  local src = from == "choice" and "your choice" or from == "group" and "the group" or from == "talents" and "talents" or "class"
  return string.format("Consumables %s, habits %s; here %s; role %s (%s%s); carried %d, fit %d, chosen %d, habits %d, quiet %d, cooling %d; asked %d; never %d, pull-only %d",
    t.on ~= false and "on" or "off", tostring(t.habits), PLACE_WORD[where] or where, tostring(role), src,
    spec and (", spec " .. tostring(spec)) or "", nCarried, nFit, nChosen, nHabit, nQuiet, nCool, Cn.lastAsked or 0, nNever, nPull)
end

function Cn:Init()
  -- (a use in a fight waits for the first read that can see; that read is after it)
  A.On("PLAYER_UPDATE_RESTING", function() B.Dirty("mine") end, "consumables: resting")
  -- (a potion drunk starts every potion's cooldown: the waiting icons drawn)
  A.On("BAG_UPDATE_COOLDOWN", function() B.Dirty("consume") end, "consumables: a cooldown")
  -- (an item's data come in from the server: one in your bags is read again, with no bag change)
  A.On("GET_ITEM_INFO_RECEIVED", function(_, id)
    id = plain(id)
    if type(id) == "number" and B.Bags()[id] then wordsOf[id] = nil; kindOf[id] = nil; B.Dirty("mine") end
  end, "consumables: an item's data")
  -- (a use spell's text in, one an item of yours waited for: its items read again, with no bag change; the open
  -- Consumables tab too, one read a half second, as its rows are the items whose words it knows)
  local tabWait = false
  A.On("SPELL_TEXT_UPDATE", function(_, sp)
    sp = plain(sp)
    if type(sp) ~= "number" or not textWaits[sp] then return end
    textWaits[sp] = nil
    for id in pairs(B.Bags()) do
      if itemAura(id) == sp then wordsOf[id] = nil; kindOf[id] = nil end
    end
    B.Dirty("mine")
    if A.Window and not tabWait then
      tabWait = true
      A.After(0.5, function() tabWait = false; A.Window.Refresh() end, "consumables: the tab after a spell's text")
    end
  end, "consumables: a spell's text")
  -- (the role's words fit again after a talent change)
  for _, ev in ipairs({ "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED" }) do
    A.On(ev, function() B.Dirty("consume") end, "consumables: talents")
  end
end
