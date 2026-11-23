-- SPDX-License-Identifier: GPL-3.0-or-later
-- Biome gear (the owner, 2026-11-23): Forever's biomes give some pieces more where you stand ("doubled in Snowy areas",
-- "in Forest and Grassland areas"). Cute Auras keeps track of your biome pieces, equipped and in your bags, their
-- cooldowns, and whether swapping makes sense here, like a trinket manager for every slot:
--   in       a piece in your bags that works here, for a slot whose piece does not: swap it in
--   back     you left the biome: the piece you wore before it, back on
--   ready    your biome piece here is on cooldown, another for here is ready in your bags: swap to it
-- We don't know which sets people want, so each piece has its own "Show it in: Solo, PvP, 5-man, Raid" and Never, on the
-- icon's right-click and in the window's Biome gear tab. Swapping is out of a fight only (the game's rule for armor and
-- trinkets); "Swap for me" does it without a click.
-- Where you stand: the client's area groups (D.BIOMES), matched by name to the zone, subzone and minimap texts in your
-- language (C_Map.GetAreaInfo); Water while you swim; and learned: a biome-gated aura of a worn piece showing proves the
-- biome where you are (kept for that place). A piece's biomes: D.BIOME_ITEMS, else its tooltip's lines against the
-- biome spells' own texts (C_Spell.GetSpellDescription), else the English words.
local _, A = ...
local G = A.Part("Gear", { here = {}, pieces = {}, suggestions = {} })
local B, S, L, D = A.Bar, A.Spells, A.Look, A.Data
local C = L.C
local plain, call = A.Plain, A.Call

G.CONTEXTS = { { "solo", "Solo content" }, { "pvp", "PvP content" }, { "dungeon", "5-man content" }, { "raid", "Raiding content" } }
local BIOME = {}
for _, b in ipairs(D.BIOMES) do BIOME[b.key] = b end
G.BIOME = BIOME

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
  return a.biomePlaces
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
-- whether a piece's suggestions show in a content: its own choice, else the defaults
function G.ShowsIn(id, ctxKey)
  local g = G.Settings()
  local it = g.items[id]
  if type(it) == "table" then
    if it.never then return false end
    if type(it.show) == "table" and it.show[ctxKey] ~= nil then return it.show[ctxKey] end
  end
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
function G.SetNever(id, on)
  local g = G.Settings()
  local it = type(g.items[id]) == "table" and g.items[id] or {}
  it.never = on and true or nil
  g.items[id] = it
  B.Dirty("gear")
end

----------------------------------------------------------------------------
-- where you stand
----------------------------------------------------------------------------
local areaNames -- [biome key] = { [name] = true }, the areas' names in your language, made at login
local function names()
  if areaNames then return areaNames end
  areaNames = {}
  local get = C_Map and C_Map.GetAreaInfo
  for _, b in ipairs(D.BIOMES) do
    local set = {}
    for _, id in ipairs(b.areas or {}) do
      local n = type(get) == "function" and plain(call(get, id)) or nil
      if type(n) == "string" and n ~= "" then set[n] = true end
    end
    areaNames[b.key] = set
  end
  return areaNames
end
local placeBuf = {}
local function places()
  for i = #placeBuf, 1, -1 do placeBuf[i] = nil end
  for _, fn in ipairs({ GetSubZoneText, GetMinimapZoneText, GetZoneText, GetRealZoneText }) do
    local n = type(fn) == "function" and plain(call(fn)) or nil
    if type(n) == "string" and n ~= "" then placeBuf[#placeBuf + 1] = n end
  end
  return placeBuf
end
G.Places = places
function G.Here()
  local here = G.here
  for k in pairs(here) do here[k] = nil end
  local all = names()
  local learned = learnedDB()
  for _, p in ipairs(places()) do
    for key, set in pairs(all) do if set[p] then here[key] = p end end
    for key in pairs(type(learned[p]) == "table" and learned[p] or {}) do here[key] = here[key] or p end
  end
  if A.Yes(IsSwimming) or A.Yes(IsSubmerged) then here.water = "water" end
  return here
end
-- a biome-gated aura on you proves the biome where you stand: kept for that place (its subzone, else its zone)
local function learnFromAuras(_, ids)
  local p = places()[1]
  if not p then return end
  for id in pairs(ids) do
    local key = D.BIOME_GATED[id]
    if key then
      local db = learnedDB()
      local n = 0
      for _ in pairs(db) do n = n + 1 end
      if type(db[p]) ~= "table" and n < 200 then db[p] = {} end
      if type(db[p]) == "table" and not db[p][key] then db[p][key] = true; B.Dirty("gear") end
    end
  end
end

----------------------------------------------------------------------------
-- a piece's biomes: the data's, else its tooltip's (each item read once)
----------------------------------------------------------------------------
local descs -- [biome spell's text in your language] = its biomes
local function descriptions()
  if descs then return descs end
  descs = {}
  local get = C_Spell and C_Spell.GetSpellDescription or GetSpellDescription
  for id, keys in pairs(D.BIOME_SPELLS) do
    local t = type(get) == "function" and plain(call(get, id)) or nil
    if type(t) == "string" and #t > 12 then descs[t:sub(1, 48)] = keys end
  end
  return descs
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
  for _, l in ipairs(lines) do
    local t = plain(l.leftText)
    if type(t) == "string" then
      local body = t:gsub("^[^:]+: ", "")
      local keys = ds[body:sub(1, 48)]
      for _, k in ipairs(keys or {}) do set[k] = true end
      for w in t:gmatch("(%u%l+) areas") do if WORDS[w] then set[WORDS[w]] = true end end
      for w in t:gmatch("(%u%l+) and %u%l+ areas") do if WORDS[w] then set[WORDS[w]] = true end end
      for w in t:gmatch("(%u%l+) or %u%l+ areas") do if WORDS[w] then set[WORDS[w]] = true end end
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
local function hasUse(id)
  if not (C_Item and type(C_Item.GetItemSpell) == "function") then return false end
  local ok, _, sp = pcall(C_Item.GetItemSpell, id)
  return ok and type(plain(sp)) == "number"
end
local function works(biomes, here)
  for _, k in ipairs(biomes or {}) do if here[k] then return k end end
  return nil
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
    local _, _, _, equipLoc = call(C_Item.GetItemInfoInstant, id)
    p.slots = SLOTS[plain(equipLoc) or ""]
    p.use = hasUse(id)
    local st, du
    if inv then st, du = call(GetInventoryItemCooldown, "player", inv)
    elseif bag and C_Container and C_Container.GetContainerItemCooldown then st, du = call(C_Container.GetContainerItemCooldown, bag, slot) end
    st, du = plain(st) or 0, plain(du) or 0
    p.cdLeft = (type(st) == "number" and type(du) == "number" and du > 1.5) and math.max(0, st + du - A.Now()) or 0
    p.usable = where == "worn" or S.Usable(id, bag, slot)
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

----------------------------------------------------------------------------
-- the suggestions
----------------------------------------------------------------------------
local function swapRec(add, p, inv, kind, here, ctxKey, biome)
  local rec = add()
  rec.key = "gear:" .. kind .. ":" .. inv
  rec.never, rec.neverName = "gear:" .. p.id, L.ItemName(p.id, "this piece")
  rec.item = p.id
  rec.tex, rec.lit = L.ItemIcon(p.id, 134400), true
  rec.word = "Swap"
  B.Click(rec, "macro", "/equipslot " .. inv .. " item:" .. p.id)
  local name = L.ItemName(p.id, "A piece")
  local old = worn(inv)
  local oldName = old and L.ItemName(old, "your " .. (SLOT_NAME[inv] or "piece")) or ("your " .. (SLOT_NAME[inv] or "slot"))
  local b = biome and BIOME[biome]
  if kind == "in" then
    rec.name = name
    rec.why = (b and (b.name .. " here") or "Here") .. ": it works here, " .. oldName .. " doesn't."
  elseif kind == "ready" then
    rec.name = name .. " is ready"
    rec.why = oldName .. " is on cooldown; this one works here too."
  else
    rec.name = name .. " back on"
    rec.why = "You left the biome of " .. oldName .. "."
  end
  rec.clickWord = "swap it in for " .. oldName
  rec.inv, rec.kind, rec.old = inv, kind, old
  return rec
end
local pickBuf = {}
B.Add({ key = "gear", part = "gear", order = 400, groups = { "gear" },
  read = function(add, ctx)
    local g = G.Settings()
    if g.on == false then return end
    local ctxKey = G.Context()
    local here = G.Here()
    local pieces = G.Scan()
    local home = homeDB()
    local taken = pickBuf
    for k in pairs(taken) do taken[k] = nil end
    local wornBy = {}
    for _, p in ipairs(pieces) do if p.where == "worn" then wornBy[p.inv] = p end end
    -- in, and ready: the bag's pieces for here, best first (ready before on cooldown)
    table.sort(pieces, function(a, b) return (a.cdLeft or 0) < (b.cdLeft or 0) or ((a.cdLeft or 0) == (b.cdLeft or 0) and a.id < b.id) end)
    for _, p in ipairs(pieces) do
      local biome = works(p.biomes, here)
      if p.where == "bag" and biome and p.usable and p.slots and not taken[p.id] and G.ShowsIn(p.id, ctxKey) and not B.Never("gear:" .. p.id) then
        -- (the slot: one whose piece doesn't work here; a ring or trinket pair, the one holding another biome's piece first)
        local target, kind
        for _, inv in ipairs(p.slots) do
          local w = wornBy[inv]
          if not taken["slot" .. inv] then
            if not (w and works(w.biomes, here)) then
              if not target or (w and not (wornBy[target] and wornBy[target].biomes)) then target, kind = inv, "in" end
            elseif w and w.use and p.use and (w.cdLeft or 0) > 35 and (p.cdLeft or 0) == 0 and not target then
              target, kind = inv, "ready"
            end
          end
        end
        if target then
          taken[p.id], taken["slot" .. target] = true, true
          swapRec(add, p, target, kind, here, ctxKey, biome)
        end
      end
    end
    -- back: a worn biome piece that works nowhere here, with the piece you wore before it in your bags
    local bags = B.Bags()
    for inv, w in pairs(wornBy) do
      local was = home[inv]
      if not works(w.biomes, here) and was and was ~= w.id and bags[was] and not taken["slot" .. inv] and G.ShowsIn(w.id, ctxKey) then
        local e = bags[was]
        local rec = add()
        rec.key = "gear:back:" .. inv
        rec.never, rec.neverName = "gear:back:" .. w.id, L.ItemName(w.id, "this piece")
        rec.item = w.id
        rec.tex, rec.lit, rec.word = L.ItemIcon(was, 134400), true, "Swap"
        B.Click(rec, "macro", "/equipslot " .. inv .. " item:" .. was)
        rec.name = L.ItemName(was, "Your piece") .. " back on"
        rec.why = "No biome here for " .. L.ItemName(w.id, "your biome piece") .. "."
        rec.clickWord = "swap back"
        rec.inv, rec.kind, rec.old = inv, "back", w.id
      end
    end
  end,
  -- (a swap clicked: the piece it replaced is remembered for "back"; a swap back forgets it)
  used = function(rec)
    if rec.kind == "back" then homeDB()[rec.inv] = nil
    elseif rec.old and not (D.BIOME_ITEMS[rec.old] or known[rec.old]) then homeDB()[rec.inv] = rec.old end
    A.After(0.8, function() B.Dirty("gear") end, "gear: after a swap")
  end,
  tip = function(tt, rec)
    local p
    for _, x in ipairs(G.pieces) do if x.id == rec.item then p = x end end
    if p and p.biomes then
      local words = {}
      for _, k in ipairs(p.biomes) do words[#words + 1] = BIOME[k] and BIOME[k].name or k end
      tt:AddLine("Biomes: " .. table.concat(words, ", "), C.DIM[1], C.DIM[2], C.DIM[3], true)
      if p.cdLeft and p.cdLeft > 0 then tt:AddLine(string.format("Cooldown: %d:%02d", math.floor(p.cdLeft / 60), math.floor(p.cdLeft % 60)), C.WARN[1], C.WARN[2], C.WARN[3]) end
    end
    if rec.p and rec.kind ~= "back" then tt:AddLine("An on-use trinket waits 30 s after it is put on.", C.DIM[1], C.DIM[2], C.DIM[3], true) end
  end,
  -- (the right-click: where this piece's swaps show, and Never)
  menu = function(root, rec)
    local id = rec.item
    if not id then return end
    if root.CreateTitle then root:CreateTitle("Show it in") end
    for _, c in ipairs(G.CONTEXTS) do
      local key = c[1]
      root:CreateCheckbox(c[2], function() return G.ShowsIn(id, key) end, function() G.SetShow(id, key, not G.ShowsIn(id, key)) end)
    end
  end,
})

----------------------------------------------------------------------------
-- Swap for me: out of a fight, the bar's gear suggestions done without a click (off by default)
----------------------------------------------------------------------------
local lastAuto = 0
local function auto()
  if G.Settings().auto ~= true or A.Fighting() then return end
  if A.Now() - lastAuto < 3 then return end
  if A.Yes(UnitCastingInfo, "player") or A.Yes(UnitChannelInfo, "player") then return end
  for _, rec in ipairs(B.Shown("gear") or {}) do
    local id = rec.kind == "back" and homeDB()[rec.inv] or rec.item
    if id and C_Item and C_Item.EquipItemByName then
      lastAuto = A.Now()
      if pcall(C_Item.EquipItemByName, id, rec.inv) and rec.p and rec.p.used then rec.p.used(rec) end
      return
    end
  end
end
G.Auto = auto

function G:Init()
  A.Camp.Watch(learnFromAuras)
  for _, ev in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_COOLDOWN", "MIRROR_TIMER_START", "MIRROR_TIMER_STOP" }) do
    A.On(ev, function() B.Dirty("gear") end)
  end
  A.On("BAG_UPDATE_DELAYED", function() B.Dirty("gear") end)
  A.On("PLAYER_LEVEL_UP", function() G.Forget(); B.Dirty("gear") end)
  A.On("PLAYER_REGEN_ENABLED", function() A.After(1.5, auto, "gear: swap for me") end)
end
