-- SPDX-License-Identifier: GPL-3.0-or-later
-- Biome gear (the owner, 2026-11-23): Forever's biomes give some pieces more where you stand ("doubled in Snowy areas",
-- "in Forest and Grassland areas"). Cute Auras keeps track of your biome pieces, equipped and in your bags, their
-- cooldowns, and whether swapping makes sense here, like a trinket manager for every slot:
--   in       a piece in your bags that works here, for a slot whose piece does not: swap it in
--   back     you left the biome: the piece you wore before it, back on
--   ready    your biome piece here is on cooldown, another for here is ready in your bags: swap to it
-- We don't know which sets people want, so each piece has its own "Show it in: World, PvP, 5-man, Raid" and Never (the
-- bar's Never, one key a piece, "gear:<id>"), on the icon's right-click and in the window's Biome gear tab. Swapping is
-- out of a fight only (the game's rule for armor and trinkets); "Swap for me" does it without a click, and leaves alone
-- a slot you changed by hand until the biomes where you stand change.
-- Where you stand: the client's area groups (D.BIOMES), matched by name to the zone texts in your language
-- (C_Map.GetAreaInfo): a zone by the zone's text, a subzone by the subzone's text inside its own zone only; Water while
-- you swim; and learned: a biome-gated aura of a worn piece, once the place has stayed the same a few seconds, proves
-- the biome there (kept by zone and subzone). Volcanic has no area group in the client: it can't be told, so its pieces
-- are never offered and never swapped off. A piece's biomes: D.BIOME_ITEMS, else its own Equip and Use lines against the
-- biome spells' own texts (C_Spell.GetSpellDescription), else the English words; a set bonus or flavour text never counts.
local _, A = ...
local G = A.Part("Gear", { here = {}, pieces = {}, suggestions = {} })
local B, S, L, D = A.Bar, A.Spells, A.Look, A.Data
local C = L.C
local plain, call = A.Plain, A.Call

G.CONTEXTS = { { "solo", "World" }, { "pvp", "PvP" }, { "dungeon", "5-man" }, { "raid", "Raid" } }
local BIOME = {}
for _, b in ipairs(D.BIOMES) do BIOME[b.key] = b end
G.BIOME = BIOME
-- the biomes the client can't place (no area group, not Water): today Volcanic
local UNTOLD = {}
for _, b in ipairs(D.BIOMES) do if not b.areas and b.key ~= "water" then UNTOLD[b.key] = true end end
G.UNTOLD = UNTOLD
-- each biome's colour, for its name in the Biome gear tab and in tooltips (the bar keeps the gear part's pink: a bar's
-- colour there means its part). Spread so no two read alike: earth tones apart by lightness and warmth, Mountainous a
-- cool grey stone, Underground a dark umber, Wasteland a dry olive
G.COLOR = {
  forest = { 0.36, 0.80, 0.40 }, swamp = { 0.42, 0.56, 0.30 }, wasteland = { 0.70, 0.70, 0.30 }, desert = { 0.96, 0.76, 0.42 },
  volcanic = { 1.00, 0.42, 0.26 }, underground = { 0.62, 0.44, 0.30 }, mountainous = { 0.66, 0.70, 0.78 }, snowy = { 0.74, 0.92, 1.00 },
  water = { 0.30, 0.56, 1.00 }, haunted = { 0.72, 0.56, 0.98 },
}
-- a biome's name in its colour, for a line of text
function G.Colored(key)
  local b, c = BIOME[key], G.COLOR[key] or C.INK
  return string.format("|cff%02x%02x%02x%s|r", c[1] * 255, c[2] * 255, c[3] * 255, b and b.name or key)
end
function G.ColoredList(keys)
  local out = {}
  for _, k in ipairs(keys or {}) do out[#out + 1] = G.Colored(k) end
  return table.concat(out, ", ")
end

-- the slots a kind of item goes in (C_Item.GetItemInfoInstant's equipLoc)
local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
  INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
  INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
  INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
G.SLOTS = SLOTS
local SLOT_NAME = { [1] = "head", [2] = "neck", [3] = "shoulders", [5] = "chest", [6] = "waist", [7] = "legs", [8] = "feet",
  [9] = "wrists", [10] = "hands", [11] = "ring", [12] = "ring", [13] = "trinket", [14] = "trinket", [15] = "back",
  [16] = "main hand", [17] = "off hand", [18] = "ranged" }
G.SLOT_NAME = SLOT_NAME

function G.Settings()
  local s = A.Settings()
  if type(s.gear) ~= "table" then s.gear = {} end
  local g = s.gear
  if g.on == nil then g.on = true end
  if type(g.show) ~= "table" then g.show = { solo = true, pvp = true, dungeon = true, raid = true } end
  if type(g.items) ~= "table" then g.items = {} end
  -- (Swap for me is each character's now, A.Char().gearAuto: the old account-wide switch is let go, so no alt
  -- equips on another character's word)
  g.auto = nil
  -- (a piece's Never was once its own flag here, and a "back" icon's its own key: both move to the bar's one key a
  -- piece, "gear:<id>", once, so the icon's right-click and the tab agree)
  -- (the keys to move are listed first and moved after: a key added to a table while pairs walks it can end the walk
  -- with "invalid key to 'next'"; the flag is set once the move is done, so a move cut short runs again)
  if not g.neverOne then
    local never = s.never
    for id, it in pairs(g.items) do
      if type(it) == "table" and it.never then it.never = nil; never["gear:" .. id] = never["gear:" .. id] or tostring(id) end
    end
    local moving = {}
    for key, name in pairs(never) do
      local id = type(key) == "string" and key:match("^gear:back:(%d+)$")
      if id then moving[#moving + 1] = { key, id, name } end
    end
    for _, m in ipairs(moving) do
      never[m[1]] = nil
      never["gear:" .. m[2]] = never["gear:" .. m[2]] or m[3]
    end
    g.neverOne = true
  end
  return g
end
local function homeDB()
  local c = A.Char()
  if type(c.gearHome) ~= "table" then c.gearHome = {} end
  return c.gearHome
end
local function learnedDB()
  local a = A.Acct()
  if type(a.biomePlaces) ~= "table" then a.biomePlaces = {} end
  -- (places were kept by a bare name before, saved the moment the zone text changed and often with the last zone's
  -- aura still on: those are let go once; places are kept by "zone|subzone" now)
  if not a.biomePlacesKeyed then
    a.biomePlacesKeyed = true
    for k in pairs(a.biomePlaces) do if type(k) ~= "string" or not k:find("|", 1, true) then a.biomePlaces[k] = nil end end
  end
  return a.biomePlaces
end
-- how many places are learned, and forget them all (the Biome gear tab's button)
function G.LearnedCount()
  local n = 0
  for _ in pairs(learnedDB()) do n = n + 1 end
  return n
end
function G.ForgetPlaces()
  local db = learnedDB()
  for k in pairs(db) do db[k] = nil end
  B.Dirty("gear")
end

-- the content you are in: raid, dungeon (a 5-man), pvp (a battleground or arena), else solo (the open world)
function G.Context()
  if type(IsInInstance) == "function" then
    local ok, inside, kind = pcall(IsInInstance)
    kind = ok and plain(inside) == true and plain(kind) or nil
    if kind == "raid" then return "raid" elseif kind == "party" then return "dungeon" elseif kind == "pvp" or kind == "arena" then return "pvp" end
  end
  return "solo"
end
-- a piece's Never: the bar's own list, one key a piece (its "in", "ready" and "back" icons alike)
function G.Never(id) return B.Never("gear:" .. id) end
-- (false when the bar's Nevers are full: nothing was set)
function G.SetNever(id, on)
  local ok = B.SetNever("gear:" .. id, L.ItemName(id, "Item " .. id), on and true or false)
  B.Dirty("gear")
  return ok
end
-- whether a piece's suggestions show in a content: never with Never, else its own choice, else the defaults
function G.ShowsIn(id, ctxKey)
  if G.Never(id) then return false end
  local g = G.Settings()
  local it = g.items[id]
  if type(it) == "table" and type(it.show) == "table" and it.show[ctxKey] ~= nil then return it.show[ctxKey] end
  return g.show[ctxKey] ~= false
end
function G.SetShow(id, ctxKey, on)
  local g = G.Settings()
  local it = type(g.items[id]) == "table" and g.items[id] or {}
  it.show = type(it.show) == "table" and it.show or {}
  it.show[ctxKey] = on and true or false
  g.items[id] = it
  B.Dirty("gear")
end

----------------------------------------------------------------------------
-- where you stand
----------------------------------------------------------------------------
local function text(fn)
  local n = type(fn) == "function" and plain(call(fn)) or nil
  return type(n) == "string" and n ~= "" and n or nil
end
-- the areas' names in your language, made at login: [biome] = { [zone name] = true } for zones (and instances), and
-- [biome] = { [subzone name] = { [its zone's name] = true } } for subzones, which count inside their own zone only
local areaTop, areaSub
local function names()
  if areaTop then return areaTop, areaSub end
  local get = C_Map and C_Map.GetAreaInfo
  local function nameOf(id)
    local n = type(get) == "function" and plain(call(get, id)) or nil
    return type(n) == "string" and n ~= "" and n or nil
  end
  areaTop, areaSub = {}, {}
  for _, b in ipairs(D.BIOMES) do
    local top, sub = {}, {}
    for _, id in ipairs(b.areas or {}) do
      local n, z = nameOf(id), b.zones and b.zones[id]
      if n and not z then top[n] = true
      elseif n then
        local zn = nameOf(z)
        if zn then sub[n] = sub[n] or {}; sub[n][zn] = true end
      end
    end
    areaTop[b.key], areaSub[b.key] = top, sub
  end
  return areaTop, areaSub
end
-- the place, for what is learned: "zone|subzone" (the subzone empty in the open zone), nil while the client has none
local function placeKey()
  local zone = text(GetRealZoneText) or text(GetZoneText)
  if not zone then return nil end
  return zone .. "|" .. (text(GetSubZoneText) or "")
end
G.PlaceKey = placeKey
function G.Here()
  local here = G.here
  for k in pairs(here) do here[k] = nil end
  local top, sub = names()
  local zone, real = text(GetZoneText), text(GetRealZoneText)
  local subz, mini = text(GetSubZoneText), text(GetMinimapZoneText)
  local function inZone(zones) return zones and ((zone and zones[zone]) or (real and zones[real])) end
  for key, set in pairs(top) do
    local p = (zone and set[zone] and zone) or (real and set[real] and real) or nil
    local s = sub[key]
    if not p and subz and inZone(s[subz]) then p = subz end
    if not p and mini and inZone(s[mini]) then p = mini end
    if p then here[key] = p end
  end
  local k = placeKey()
  local learned = k and learnedDB()[k]
  if type(learned) == "table" then
    for key in pairs(learned) do here[key] = here[key] or subz or zone or real end
  end
  if A.Yes(IsSwimming) or A.Yes(IsSubmerged) then here.water = "water" end
  return here
end
-- the biomes here as one string (D.BIOMES' order): a slot changed by hand is left alone while it stays the same
local function hereSig(here)
  local s = ""
  for _, b in ipairs(D.BIOMES) do if here[b.key] then s = s .. b.key .. "," end end
  return s
end
-- a biome-gated aura on you proves the biome where you stand, kept for that place. Only once the place has stayed the
-- same SETTLE seconds: at a border the zone text changes at once, while the server takes the last zone's aura off (or
-- puts the new one on) a moment later
local SETTLE = 3
local settled = { key = nil, at = 0 }
local function placeMoved()
  local k = placeKey()
  if k ~= settled.key then settled.key, settled.at = k, A.Now() end
  -- (a look again once it has settled: the gear part reads your auras, Camp.Mine, which runs learnFromAuras)
  A.After(SETTLE + 0.1, function() B.Dirty("gear") end, "gear: the place settled")
end
local function learnFromAuras(_, ids)
  local k = placeKey()
  if not k then return end
  if k ~= settled.key then settled.key, settled.at = k, A.Now() return end
  if A.Now() - settled.at < SETTLE then return end
  for id in pairs(ids) do
    local key = D.BIOME_GATED[id]
    if key then
      local db = learnedDB()
      if type(db[k]) ~= "table" then
        local n = 0
        for _ in pairs(db) do n = n + 1 end
        if n < 200 then db[k] = {} end
      end
      if type(db[k]) == "table" and not db[k][key] then db[k][key] = true; B.Dirty("gear") end
    end
  end
end

----------------------------------------------------------------------------
-- a piece's biomes: the data's, else its tooltip's (each item read once)
----------------------------------------------------------------------------
-- a line as its words alone: the numbers (a rank's, an item level's) set aside, the spaces one, lower case
local function shape(t)
  return (t:gsub("%d+[%.,]?%d*", "#"):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):lower())
end
G.Shape = shape
-- the biome spells' whole texts in your language, by their shape: a tooltip line is theirs only when all of it is
-- (2026-11-23: a 48-letter beginning took every "+spell damage", "mana per 5 sec" and "all resistances" item for a
-- biome piece, since Briarwood Reed's and Enriched Seal's texts begin that way)
local descs
local function descriptions()
  if descs then return descs end
  descs = {}
  local get = C_Spell and C_Spell.GetSpellDescription or GetSpellDescription
  for id, keys in pairs(D.BIOME_SPELLS) do
    local t = type(get) == "function" and plain(call(get, id)) or nil
    if type(t) == "string" and #t > 12 then descs[shape(t)] = keys end
  end
  return descs
end
-- a set bonus line, as the client writes it in your language: "(4) Set: ..." (ITEM_SET_BONUS_GRAY, not yet worn) and
-- "Set: ..." (ITEM_SET_BONUS). Every piece of a set shows its set's bonuses, so a bonus that names a biome would make
-- each lone piece a biome piece (Rotmender's Raiment, 2026-11-23): those lines never count
local function setPattern(fmt)
  if type(fmt) ~= "string" or not fmt:find("%s", 1, true) then return nil end
  local p = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")
  p = p:gsub("%%%%d", "%%d+"):gsub("%%%%s", ".*")
  return "^" .. p
end
local SET_LINES = { "^%(%d+%) ", "^Set: " }
for _, fmt in ipairs({ ITEM_SET_BONUS_GRAY, ITEM_SET_BONUS }) do
  local p = setPattern(fmt)
  if p then SET_LINES[#SET_LINES + 1] = p end
end
local function setLine(t)
  for _, p in ipairs(SET_LINES) do if t:find(p) then return true end end
  return false
end
local WORDS = { Forest = "forest", Grassland = "forest", Snowy = "snowy", Haunted = "haunted", Mountainous = "mountainous", Desert = "desert",
  Wasteland = "wasteland", Swamp = "swamp", Marsh = "swamp", Volcanic = "volcanic", Cavernous = "underground", Underground = "underground" }
local known = {} -- [item id] = { biome keys } or false
local knownN = 0
local function fromTooltip(id, bag, slot, inv)
  local TI = C_TooltipInfo
  if not TI then return nil end
  local ok, data
  if inv and type(TI.GetInventoryItem) == "function" then ok, data = pcall(TI.GetInventoryItem, "player", inv)
  elseif bag and type(TI.GetBagItem) == "function" then ok, data = pcall(TI.GetBagItem, bag, slot)
  elseif type(TI.GetItemByID) == "function" then ok, data = pcall(TI.GetItemByID, id) end
  local lines = ok and type(data) == "table" and data.lines or nil
  if type(lines) ~= "table" then return nil end
  local out, set = {}, {}
  local ds = descriptions()
  local LT = Enum and Enum.TooltipDataLineType or {}
  for _, l in ipairs(lines) do
    local t, ty = plain(l.leftText), plain(l.type)
    local flavour = ty ~= nil and LT.FlavorText ~= nil and ty == LT.FlavorText
    if type(t) == "string" and not flavour and not setLine(t) then
      -- (the line after its "Equip: " or "Use: ", its cooldown's brackets off)
      local body = t:gsub("^[^:]+: ", ""):gsub("%s*%([^%)]*%)%s*$", "")
      local keys = ds[shape(body)]
      for _, k in ipairs(keys or {}) do set[k] = true end
      -- (the English words, a biome's own: "in Snowy areas", "in Forest and Grassland areas", "in or on Water")
      for a, b in t:gmatch("in (%u%l+) and (%u%l+) areas") do if WORDS[a] then set[WORDS[a]] = true end; if WORDS[b] then set[WORDS[b]] = true end end
      for a, b in t:gmatch("in (%u%l+) or (%u%l+) areas") do if WORDS[a] then set[WORDS[a]] = true end; if WORDS[b] then set[WORDS[b]] = true end end
      for w in t:gmatch("in (%u%l+) areas") do if WORDS[w] then set[WORDS[w]] = true end end
      for w in t:gmatch("[Ii]n (%u%l+) areas") do if WORDS[w] then set[WORDS[w]] = true end end
      if t:find("in or on Water", 1, true) then set.water = true end
    end
  end
  for k in pairs(set) do out[#out + 1] = k end
  table.sort(out)
  return out
end
function G.BiomesOf(id, bag, slot, inv)
  local v = known[id]
  if v ~= nil then return v or nil end
  v = D.BIOME_ITEMS[id] or fromTooltip(id, bag, slot, inv)
  if v and #v == 0 then v = nil end
  if knownN >= 400 then for k in pairs(known) do known[k] = nil end; knownN = 0 end
  knownN = knownN + 1
  known[id] = v or false
  return v
end
function G.Forget() for k in pairs(known) do known[k] = nil end; knownN = 0 end
local function isBiome(id, inv) return G.BiomesOf(id, nil, nil, inv) ~= nil end
local function hasUse(id)
  if not (C_Item and type(C_Item.GetItemSpell) == "function") then return false end
  local ok, _, sp = pcall(C_Item.GetItemSpell, id)
  return ok and type(plain(sp)) == "number"
end
local function works(biomes, here)
  for _, k in ipairs(biomes or {}) do if here[k] then return k end end
  return nil
end
local function untold(biomes)
  for _, k in ipairs(biomes or {}) do if UNTOLD[k] then return true end end
  return false
end
-- a worn piece kept on: it works here, or one of its biomes can't be told (it may work here: never swapped off)
local function keeps(w, here) return works(w.biomes, here) ~= nil or untold(w.biomes) end
G.Keeps = keeps
-- an item's Unique-Equipped limit (C_Item.GetItemUniquenessByID): { cat, max } or false. The seals share "Seal of
-- Battle (1)", the runes "Rune of Battle (1)"; a plain Unique-Equipped piece is its own category of one. Not kept while
-- the client has no answer yet
local uniq, uniqN = {}, 0
local function limitOf(id)
  local u = uniq[id]
  if u ~= nil then return u end
  if not (C_Item and type(C_Item.GetItemUniquenessByID) == "function") then return false end
  local ok, isUnique, _, count, cat = pcall(C_Item.GetItemUniquenessByID, id)
  if not ok then return false end
  isUnique, count, cat = plain(isUnique), plain(count), plain(cat)
  if isUnique == nil and cat == nil then return false end
  u = false
  if type(cat) == "number" and cat > 0 and type(count) == "number" and count > 0 then u = { cat = "c" .. cat, max = count }
  elseif isUnique == true then u = { cat = "i" .. id, max = 1 } end
  if uniqN >= 400 then for k in pairs(uniq) do uniq[k] = nil end; uniqN = 0 end
  uniqN = uniqN + 1
  uniq[id] = u
  return u
end
local function instant(id)
  local _, _, _, loc, _, cls = call(C_Item.GetItemInfoInstant, id)
  return plain(loc), plain(cls)
end
-- your bags' free slots (nil: the client can't say)
local function freeSlots()
  local f = C_Container and C_Container.GetContainerNumFreeSlots
  if type(f) ~= "function" then return nil end
  local n = 0
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local free = plain(call(f, bag))
    if type(free) == "number" then n = n + free end
  end
  return n
end

----------------------------------------------------------------------------
-- the pieces now: equipped and in your bags, their biomes, slots, cooldowns
----------------------------------------------------------------------------
local piecePool = {}
function G.Scan()
  local list = G.pieces
  for i = #list, 1, -1 do list[i] = nil end
  local n = 0
  local function addPiece(id, where, bag, slot, inv)
    local biomes = G.BiomesOf(id, bag, slot, inv)
    if not biomes then return nil end
    n = n + 1
    local p = piecePool[n]
    if not p then p = {}; piecePool[n] = p end
    p.id, p.where, p.bag, p.slot, p.inv, p.biomes = id, where, bag, slot, inv, biomes
    p.loc = instant(id)
    p.slots = SLOTS[p.loc or ""]
    p.use = hasUse(id)
    p.limit = limitOf(id)
    local lv = plain(call(C_Item.GetDetailedItemLevelInfo, id))
    p.ilvl = type(lv) == "number" and lv or 0
    local st, du
    if inv then st, du = call(GetInventoryItemCooldown, "player", inv)
    elseif bag and C_Container and C_Container.GetContainerItemCooldown then st, du = call(C_Container.GetContainerItemCooldown, bag, slot) end
    st, du = plain(st) or 0, plain(du) or 0
    p.cdLeft = (type(st) == "number" and type(du) == "number" and du > 1.5) and math.max(0, st + du - A.Now()) or 0
    p.usable = where == "worn" or S.Usable(id, bag, slot)
    -- (a piece not yet bound to you: putting it on asks the game's "bind it to you?", so it is never put on for you)
    local bound
    if where == "bag" and type(C_Item.IsBound) == "function" and ItemLocation and type(ItemLocation.CreateFromBagAndSlot) == "function" then
      local okL, loc = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
      if okL and loc then bound = plain(call(C_Item.IsBound, loc)) end
    end
    p.unbound = bound == false
    list[#list + 1] = p
    return p
  end
  for inv = 1, 18 do
    local id = plain(call(GetInventoryItemID, "player", inv))
    if type(id) == "number" then addPiece(id, "worn", nil, nil, inv) end
  end
  local bags = B.Bags()
  for id, e in pairs(bags) do
    local eq = C_Item and C_Item.IsEquippableItem and A.Yes(C_Item.IsEquippableItem, id)
    if eq then addPiece(id, "bag", e.bag, e.slot) end
  end
  return list
end
local function worn(inv) return plain(call(GetInventoryItemID, "player", inv)) end

-- whether a piece may go in a slot as the game allows it, with nothing pushed off unseen: the off hand never under a
-- two-hander, a one-hander there only for one who can dual wield and only over another weapon (never a shield or a
-- held-in-off-hand), a two-hander over an off-hand piece only with a free bag slot for it
local function slotOK(p, inv)
  if inv == 17 then
    local mh = worn(16)
    if mh and instant(mh) == "INVTYPE_2HWEAPON" then return false end
    if p.loc == "INVTYPE_WEAPON" then
      if not A.Yes(CanDualWield) then return false end
      local oh = worn(17)
      if oh and select(2, instant(oh)) ~= 2 then return false end
    end
  end
  if inv == 16 and p.loc == "INVTYPE_2HWEAPON" and worn(17) and freeSlots() == 0 then return false end
  return true
end
-- of a pair's slots, the one that loses least: an empty one, then another biome's piece, then a plain piece with no
-- Use or on cooldown, a ready on-use piece last
local function cost(inv, w)
  local id = worn(inv)
  if not id then return 0 end
  if w then return 1 end
  if not hasUse(id) then return 2 end
  local st, du = call(GetInventoryItemCooldown, "player", inv)
  st, du = plain(st) or 0, plain(du) or 0
  if type(st) == "number" and type(du) == "number" and du > 1.5 and st + du - A.Now() > 0 then return 2 end
  return 3
end

----------------------------------------------------------------------------
-- the suggestions
----------------------------------------------------------------------------
local function swapRec(add, p, inv, kind, biome)
  local rec = add()
  rec.key = "gear:" .. kind .. ":" .. inv
  rec.never, rec.neverName = "gear:" .. p.id, L.ItemName(p.id, "this piece")
  rec.item, rec.equipId, rec.unbound = p.id, p.id, p.unbound
  rec.tex, rec.lit = L.ItemIcon(p.id, 134400), true
  rec.word = "Swap"
  B.Click(rec, "macro", "/equipslot " .. inv .. " item:" .. p.id)
  local name = L.ItemName(p.id, "A piece")
  local old = worn(inv)
  local slotName = SLOT_NAME[inv] or "slot"
  local oldName = old and L.ItemName(old, "your " .. slotName) or nil
  local b = biome and BIOME[biome]
  if kind == "in" then
    rec.name = name
    rec.why = (b and (G.Colored(biome) .. " here") or "Here") .. ": it works here, "
      .. (oldName and (oldName .. " doesn't.") or ("your " .. slotName .. " slot is empty."))
  else
    rec.name = name .. " is ready"
    rec.why = (oldName or "Your piece") .. " is on cooldown; this one works here too."
  end
  rec.clickWord = oldName and ("swap it in for " .. oldName) or "put it on"
  rec.inv, rec.kind, rec.old = inv, kind, old
  -- (a two-hander over an off-hand piece: that piece comes off too, kept for "back")
  if inv == 16 and p.loc == "INVTYPE_2HWEAPON" and worn(17) then rec.old17 = worn(17) end
  rec.biome = biome
  return rec
end
local pickBuf, wornBy, wornCat, catCount = {}, {}, {}, {}
-- Swap for me's own notes: the swaps it (or a click) started, [slot] = { id = the piece expected there (false: the slot
-- emptied), t, kind, old }; slots changed by hand, [slot] = the biomes then (hereSig); swaps the game refused,
-- ["id:slot"] = when
local pending, held, failed = {}, {}, {}
G.held, G.failed = held, failed
-- Water: no event says you swam in or out, so while a water piece is on you or in your bags, a look once a second
-- (out of a fight) marks the gear part when it changes
local wet, wetOn = false, false
local function hasWater()
  for _, p in ipairs(G.pieces) do for _, k in ipairs(p.biomes) do if k == "water" then return true end end end
  return false
end
local function wetLook()
  if not hasWater() then wetOn = false return end
  if not A.Fighting() then
    local now = A.Yes(IsSwimming) or A.Yes(IsSubmerged)
    if now ~= wet then wet = now; B.Dirty("gear") end
  end
  A.After(1, wetLook, "gear: water")
end
B.Add({ key = "gear", part = "gear", order = 400, groups = { "gear" },
  read = function(add, ctx)
    local g = G.Settings()
    if g.on == false then return end
    -- (your auras this refresh: a biome-gated one teaches the place, learnFromAuras)
    if A.Camp and A.Camp.Mine then A.Camp.Mine() end
    local ctxKey = G.Context()
    local here = G.Here()
    wet = here.water ~= nil
    local sig = hereSig(here)
    for slot, s in pairs(held) do if s ~= sig then held[slot] = nil end end
    local pieces = G.Scan()
    if not wetOn and hasWater() then wetOn = true; A.After(1, wetLook, "gear: water") end
    local home = homeDB()
    local taken = pickBuf
    for k in pairs(taken) do taken[k] = nil end
    for k in pairs(wornBy) do wornBy[k] = nil end
    for k in pairs(catCount) do catCount[k] = nil end
    for _, p in ipairs(pieces) do if p.where == "worn" then wornBy[p.inv] = p end end
    -- (what is worn by Unique-Equipped category: every slot, the plain pieces too)
    for inv = 1, 18 do
      local id = worn(inv)
      local u = id and limitOf(id)
      wornCat[inv] = u and u.cat or nil
      if u then catCount[u.cat] = (catCount[u.cat] or 0) + 1 end
    end
    -- in, and ready: the bag's pieces for here, best first (ready before on cooldown, then the higher item level)
    table.sort(pieces, function(a, b)
      local ca, cb = a.cdLeft or 0, b.cdLeft or 0
      if ca ~= cb then return ca < cb end
      if (a.ilvl or 0) ~= (b.ilvl or 0) then return (a.ilvl or 0) > (b.ilvl or 0) end
      return a.id < b.id
    end)
    for _, p in ipairs(pieces) do
      local biome = works(p.biomes, here)
      if p.where == "bag" and biome and p.usable and p.slots and not taken[p.id] and G.ShowsIn(p.id, ctxKey) then
        -- (the slot: one whose piece doesn't work here, the pair's cheapest; else, for an on-use piece, one whose
        -- piece works here but waits on its cooldown. Never past a Unique-Equipped limit: a second seal only over
        -- the first)
        local u = p.limit
        local target, kind, best
        for _, inv in ipairs(p.slots) do
          local over = false
          if u then
            local n = catCount[u.cat] or 0
            if wornCat[inv] == u.cat then n = n - 1 end
            over = n >= u.max
          end
          if not taken["slot" .. inv] and not over and slotOK(p, inv) then
            local w = wornBy[inv]
            if not (w and keeps(w, here)) then
              local c = cost(inv, w)
              if not best or c < best then target, kind, best = inv, "in", c end
            elseif not target and w.use and p.use and (w.cdLeft or 0) > 35 and (p.cdLeft or 0) == 0 then
              target, kind = inv, "ready"
            end
          end
        end
        if target then
          taken[p.id], taken["slot" .. target] = true, true
          local was = wornCat[target]
          if was then catCount[was] = catCount[was] - 1 end
          wornCat[target] = u and u.cat or nil
          if u then catCount[u.cat] = (catCount[u.cat] or 0) + 1 end
          swapRec(add, p, target, kind, biome)
        end
      end
    end
    -- back: a worn biome piece that works nowhere here (and can be told), with the piece you wore before it in your
    -- bags; a two-hander's off-hand piece back on with it
    local bags = B.Bags()
    for inv, w in pairs(wornBy) do
      local was = home[inv]
      if not keeps(w, here) and was and was ~= w.id and bags[was] and not taken["slot" .. inv] and G.ShowsIn(w.id, ctxKey) then
        local rec = add()
        rec.key = "gear:back:" .. inv
        rec.never, rec.neverName = "gear:" .. w.id, L.ItemName(w.id, "this piece")
        rec.item, rec.equipId = w.id, was
        rec.tex, rec.lit, rec.word = L.ItemIcon(was, 134400), true, "Swap"
        local macro = "/equipslot " .. inv .. " item:" .. was
        local was17 = inv == 16 and w.loc == "INVTYPE_2HWEAPON" and home[17] or nil
        if was17 and bags[was17] and not worn(17) then
          rec.equip17 = was17
          macro = macro .. "\n/equipslot 17 item:" .. was17
        end
        B.Click(rec, "macro", macro)
        rec.name = L.ItemName(was, "Your piece") .. " back on"
        rec.why = "No biome here for " .. L.ItemName(w.id, "your biome piece") .. "."
        rec.clickWord = "swap back"
        rec.inv, rec.kind, rec.old = inv, "back", w.id
      end
    end
  end,
  -- (a swap clicked or done for you: what it should put where, so its PLAYER_EQUIPMENT_CHANGED is known as ours. The
  -- piece it replaced is kept for "back" only once the game has made the swap)
  used = function(rec)
    local t = A.Now()
    pending[rec.inv] = { id = rec.equipId, t = t, kind = rec.kind, old = rec.old }
    if rec.old17 then pending[17] = { id = false, t = t, kind = rec.kind, old = rec.old17 } end
    if rec.equip17 then pending[17] = { id = rec.equip17, t = t, kind = "back" } end
    A.After(0.8, function() B.Dirty("gear") end, "gear: after a swap")
    -- (no change in 1.5 s: the game refused it, a Unique-Equipped limit, full bags; not tried again for a minute or
    -- until you move to another place)
    A.After(1.6, function()
      local now = A.Now()
      for slot, e in pairs(pending) do
        if now - e.t >= 1.5 then
          pending[slot] = nil
          if e.id and worn(slot) ~= e.id then failed[e.id .. ":" .. slot] = now end
        end
      end
      B.Dirty("gear")
    end, "gear: a swap refused")
  end,
  tip = function(tt, rec)
    local p
    for _, x in ipairs(G.pieces) do if x.id == rec.item then p = x end end
    if p and p.biomes then
      tt:AddLine("Biomes: " .. G.ColoredList(p.biomes), C.DIM[1], C.DIM[2], C.DIM[3], true)
      if p.cdLeft and p.cdLeft > 0 then tt:AddLine(string.format("Cooldown: %d:%02d", math.floor(p.cdLeft / 60), math.floor(p.cdLeft % 60)), C.WARN[1], C.WARN[2], C.WARN[3]) end
    end
    if p and p.use and (rec.inv == 13 or rec.inv == 14) and rec.kind ~= "back" then
      tt:AddLine("An on-use trinket waits 30 s after it is put on.", C.DIM[1], C.DIM[2], C.DIM[3], true)
    end
    if rec.unbound and rec.kind ~= "back" then
      tt:AddLine("Putting it on binds it to you, so Swap for me leaves this one to you.", C.WARN[1], C.WARN[2], C.WARN[3], true)
    end
  end,
  -- (the right-click: where this piece's swaps show; the bar's own Never above it is this piece's Never)
  menu = function(root, rec)
    local id = rec.item
    if not id then return end
    if root.CreateTitle then root:CreateTitle("Show it in") end
    for _, c in ipairs(G.CONTEXTS) do
      local key = c[1]
      root:CreateCheckbox(c[2], function() return G.ShowsIn(id, key) end,
        A.Safe(function() G.SetShow(id, key, not G.ShowsIn(id, key)) end, "biome gear: show it in"))
    end
  end,
})

-- a slot's piece changed (PLAYER_EQUIPMENT_CHANGED's slot): ours when it is what a swap of ours expected, within 2 s;
-- else changed by hand. Ours: the piece it replaced is kept for "back" (a plain one), a swap back forgets it. By hand:
-- Swap for me leaves that slot alone while the biomes here stay the same, and a plain piece put on is the one "back"
-- brings back from now on
local function equipChanged(_, slot)
  slot = plain(slot)
  if type(slot) ~= "number" then B.Dirty("gear") return end
  local now = worn(slot)
  local e = pending[slot]
  if e and A.Now() - e.t <= 2 then
    if (now or false) == e.id then
      pending[slot] = nil
      if e.kind == "back" then homeDB()[slot] = nil
      elseif e.old and not isBiome(e.old) then homeDB()[slot] = e.old end
    end
  else
    pending[slot] = nil
    held[slot] = hereSig(G.Here())
    if now and not isBiome(now, slot) then homeDB()[slot] = now end
    for k in pairs(failed) do failed[k] = nil end
  end
  B.Dirty("gear")
end

----------------------------------------------------------------------------
-- Swap for me: out of a fight, the bar's gear suggestions done without a click (off by default)
----------------------------------------------------------------------------
local lastAuto, queued = 0, false
local auto
-- (one look again later, never two queued)
local function later(seconds)
  if queued then return end
  queued = true
  A.After(seconds, function() queued = false; auto() end, "gear: swap for me")
end
-- (a cast or channel: any answer at all, a secret one too, is one going on)
local function busy(fn)
  local v = call(fn, "player")
  if issecretvalue and issecretvalue(v) then return true end
  return v ~= nil
end
function auto()
  if A.Char().gearAuto ~= true or A.Fighting() then return end
  -- (never while dead, a ghost, on a taxi, in a vehicle or a cinematic: the bar is hidden then, and the game refuses)
  if B.Away and B.Away() then return end
  if busy(UnitCastingInfo) or busy(UnitChannelInfo) then later(1) return end
  local wait = 3 - (A.Now() - lastAuto)
  if wait > 0 then later(wait) return end
  local sig = hereSig(G.Here())
  local now = A.Now()
  for _, rec in ipairs(B.Shown("gear") or {}) do
    local id = rec.equipId
    local refused = id and failed[id .. ":" .. rec.inv]
    if refused and now - refused >= 60 then failed[id .. ":" .. rec.inv] = nil; refused = nil end
    -- (left to you: a slot you changed by hand here, a piece not yet bound to you, a swap the game refused)
    if id and held[rec.inv] ~= sig and not refused and not (rec.unbound and rec.kind ~= "back")
      and C_Item and C_Item.EquipItemByName and not pending[rec.inv] then
      lastAuto = now
      if pcall(C_Item.EquipItemByName, id, rec.inv) then
        if rec.equip17 then pcall(C_Item.EquipItemByName, rec.equip17, 17) end
        if rec.p and rec.p.used then rec.p.used(rec) end
      end
      return
    end
  end
end
G.Auto = auto

function G:Init()
  A.Camp.Watch(learnFromAuras)
  for _, ev in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
    A.On(ev, function()
      placeMoved()
      for k in pairs(failed) do failed[k] = nil end
      B.Dirty("gear")
    end)
  end
  A.On("PLAYER_EQUIPMENT_CHANGED", equipChanged)
  for _, ev in ipairs({ "BAG_UPDATE_COOLDOWN", "MIRROR_TIMER_START", "MIRROR_TIMER_STOP", "BAG_UPDATE_DELAYED" }) do
    A.On(ev, function() B.Dirty("gear") end)
  end
  A.On("PLAYER_LEVEL_UP", function() G.Forget(); B.Dirty("gear") end)
  A.On("PLAYER_REGEN_ENABLED", function() A.After(1.5, auto, "gear: swap for me") end)
end
