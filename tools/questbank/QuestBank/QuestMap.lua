-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank map icons: on each zone's world map, a ! where a quest you can take now starts, a ? where a finished
-- quest in your log is handed in, and for the quests in your log a mark (with its area) on every objective not
-- finished yet, plus where the item that starts a quest drops. The Forever client only. Settings' "Map icons" and
-- /qb icons switch them; the numbered route pins (Pins.lua) are a layer of their own with their own switch.
-- Every spot is stored in the frame of the map it is drawn on (Data.lua: D.SPOT, D.START, D.SN and D.SREQ; givers
-- and hand-ins from D.Q and D.NPC, with D.NSRC saying where each NPC's place comes from, and D.QLOCK the quests that
-- need a profession or a reputation), so nothing is projected from world yards here, and every tooltip says where
-- its spot comes from. With an older Data.lua (no D.SPOT) the ! and ? still show. NPCs standing at the same spot
-- share one icon that lists each of them; where a numbered route pin stands on an NPC, that pin's tooltip lists what
-- the NPC has besides.
local _, QB = ...
local QM = {}
QB.QuestMap = QM

local D = QB.Data
local Q = QB.Quest
local floor = math.floor

local ICON, AREA = "QuestBankQuestPinTemplate", "QuestBankAreaPinTemplate"
local MAX_PINS = 200 -- at most this many pins on one map: every ! and ? first, then the marks in turns, then areas
local NEAR = 0.6     -- map percent: a route pin this close, or a second record of the NPC, is the same NPC
local MIN_AREA = 0.005 -- an area narrower than 1% of the map is drawn as its mark alone

-- the maps that get icons: zones and cities, and Zephras Isle; never a continent, the world or a dungeon
local ALSO = { [2521] = true, [2524] = true }
function QM.Draws(mapID)
  if type(mapID) ~= "number" then return false end
  if ALSO[mapID] then return true end
  if not (C_Map and C_Map.GetMapInfo) then return false end
  local ok, info = pcall(C_Map.GetMapInfo, mapID)
  local kind = ok and type(info) == "table" and QB.Plain(info.mapType)
  return kind == ((Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3)
end

-- Forever only (as Game.lua tells it); elsewhere the layer does nothing and Settings greys its rows out
function QM.Available() return QB.Game and QB.Game.Forever() or false end
local function on() return QM.Available() and QB:Settings().mapIcons ~= false end

----------------------------------------------------------------------------
-- art: the client's own atlases, file ids where one is missing
----------------------------------------------------------------------------
local ART = {
  give = { atlas = "QuestNormal", file = 132049, size = 20 },        -- the yellow !
  turn = { atlas = "QuestTurnin", file = 132048, size = 20 },        -- the yellow ?
  k = { atlas = "Crosshair_Attack_32", file = 131013, size = 16 },   -- kill: the attack cursor
  c = { atlas = "Crosshair_LootAll_32", file = 131023, size = 16 },  -- collect: the loot cursor
  u = { atlas = "Crosshair_Interact_32", file = 131021, size = 16 }, -- use or click an object
  b = { atlas = "Crosshair_Buy_32", file = 131014, size = 16 },      -- buy from the vendor here
  e = { atlas = "QuestObjective", file = 131017, size = 16 },        -- explore, an event
  f = { atlas = "Crosshair_Fishing_32", file = 303902, size = 16 },  -- fish, pick pockets or skin
  s = { atlas = "Crosshair_LootAll_32", file = 131023, size = 16 },  -- the item that starts a quest drops here
  bang = { atlas = "SmallQuestBang", file = 132049 },                -- on that mark: it starts a quest
  area = { atlas = "CircleMaskScalable", file = 130924 },            -- an objective's area
}
QM.ART = ART

local function paint(t, art)
  local ok, info = false, nil
  if C_Texture and C_Texture.GetAtlasInfo then ok, info = pcall(C_Texture.GetAtlasInfo, art.atlas) end
  if ok and info ~= nil and t.SetAtlas then t:SetAtlas(art.atlas, false) return end
  t:SetTexture(art.file)
  t:SetTexCoord(0, 1, 0, 1)
end

-- where a spot comes from, as every tooltip says
local CLASSIC = "Classic data (may have moved in Forever)"
local SOURCE = { c = CLASSIC, p = CLASSIC, w = "Wowhead Forever", g = "seen in players' games" }
QM.SOURCE = SOURCE

-- where an NPC's place comes from: the letter Data.lua keeps for it (D.NSRC, a table by D.NPC index or a string with
-- one letter per NPC: w Wowhead Forever, c the Classic database's spawn, g players' games), as gen_data placed it.
-- An older Data.lua has none. Then an NPC on a map new in Forever (Zephras Isle and the Darkspear Islands, Mount
-- Hyjal, the Riverglades, Shen'dralas) is Wowhead's, as no Classic spawn stands there; any other is said to be
-- Classic, the cautious claim (about one in five of those has Wowhead's place, and nothing here tells which)
local LETTER = { w = "w", c = "c", g = "g", wowhead = "w", cmangos = "c", game = "g" }
local NEW_MAPS = { [2521] = true, [2524] = true, [2482] = true, [2548] = true, [2652] = true }
local function npcSource(d)
  local all, src = D.NSRC, nil
  if d.npc and type(all) == "table" then src = LETTER[all[d.npc]]
  elseif d.npc and type(all) == "string" then src = LETTER[all:sub(d.npc, d.npc)] end
  if src then return src end
  return NEW_MAPS[d.m] and "w" or "c"
end
QM.NpcSource = npcSource

----------------------------------------------------------------------------
-- the data: spots read once each, and indexes by map built once
----------------------------------------------------------------------------
-- "kind,slot,map,x,y,r,src[,name]" with ";" between spots (the header of Data.lua has the letters); x, y and r in
-- thousandths of the map, kept here as fractions
local parsed = {}
local function spots(str)
  if type(str) ~= "string" then return nil end
  local list = parsed[str]
  if list then return list end
  list = {}
  for part in str:gmatch("[^;]+") do
    local kind, slot, m, x, y, r, src, rest = part:match("^%s*(%a),(%d+),(%d+),([%d%.]+),([%d%.]+),([%d%.]+),(%a)(.*)$")
    if kind then
      list[#list + 1] = { kind = kind, slot = tonumber(slot), m = tonumber(m), x = tonumber(x) / 1000, y = tonumber(y) / 1000,
                          r = tonumber(r) / 1000, src = src, name = tonumber(rest:match("^,(%d+)")) }
    end
  end
  parsed[str] = list
  return list
end
QM.Spots = spots

local function spotName(sp) return sp.name and D.SN and D.SN[sp.name] or nil end

-- what each slot asks for, "slot:count[:name]" with "," between slots: count[slot], and name[slot] an index into
-- D.SN (an item slot's own item, as the game's line names it; the spots there are named for what drops it)
local needs, NONE = {}, { count = {}, name = {} }
local function needOf(id)
  local str = D.SREQ and D.SREQ[id]
  if type(str) ~= "string" then return NONE end
  local t = needs[str]
  if not t then
    t = { count = {}, name = {} }
    for slot, n, name in str:gmatch("(%d+):(%d+):?(%d*)") do
      slot = tonumber(slot)
      t.count[slot], t.name[slot] = tonumber(n), tonumber(name)
    end
    needs[str] = t
  end
  return t
end

local function namesOf(need)
  local out = {}
  for slot, i in pairs(need.name) do out[slot] = D.SN and D.SN[i] or nil end
  return out
end

-- [uiMap] = { { npc = D.NPC index, ids = quest ids }, ... }: who gives what, by map
local giversOf, giversFor = {}, false
local function giversOn(m)
  if giversFor ~= D.Q then
    giversFor, giversOf = D.Q, {}
    local byNpc = {}
    for id, r in pairs(D.Q or {}) do
      local i = r[7]
      local n = i and i > 0 and D.NPC[i]
      if n and (n[2] or 0) > 0 then
        local g = byNpc[i]
        if not g then
          g = { npc = i, ids = {} }
          byNpc[i] = g
          giversOf[n[2]] = giversOf[n[2]] or {}
          table.insert(giversOf[n[2]], g)
        end
        g.ids[#g.ids + 1] = id
      end
    end
    for _, list in pairs(giversOf) do
      table.sort(list, function(a, b) return a.npc < b.npc end)
      for _, g in ipairs(list) do table.sort(g.ids) end
    end
  end
  return giversOf[m]
end

-- [uiMap] = { { id = quest, spot = where its item drops }, ... }
local startsOf, startsFor = {}, false
local function startsOn(m)
  if startsFor ~= D.START then
    startsFor, startsOf = D.START, {}
    local ids = {}
    for id in pairs(D.START or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
      for _, sp in ipairs(spots(D.START[id]) or {}) do
        startsOf[sp.m] = startsOf[sp.m] or {}
        table.insert(startsOf[sp.m], { id = id, spot = sp })
      end
    end
  end
  return startsOf[m]
end

----------------------------------------------------------------------------
-- which quests: what the game would show you
----------------------------------------------------------------------------
-- how far below your level a quest goes grey: the game hides its ! then, unless you track low-level quests
local function greyRange(level)
  local f = UnitQuestTrivialLevelRange or GetQuestGreenRange
  if f then
    local ok, r = pcall(f, "player")
    r = ok and QB.Plain(r)
    if type(r) == "number" then return r end
  end
  -- Classic's rule, as the server greys quests and mobs
  if level <= 5 then return 99 end
  if level < 40 then return 4 + floor(level / 10) end
  if level < 60 then return floor(level / 5) end
  return 8
end
local function grey(q, level, range) return (q.lvl or 0) > 0 and level - q.lvl > range end
function QM.Grey(q, level) return grey(q, level, greyRange(level)) end

local function num(v)
  v = QB.Plain(v)
  return type(v) == "number" and v or nil
end

-- a quest's objectives as the game has them now: text, kind, finished, have and need
local function objectivesOf(e)
  if C_QuestLog and C_QuestLog.GetQuestObjectives then
    local ok, list = pcall(C_QuestLog.GetQuestObjectives, e.id)
    if ok and type(list) == "table" then
      local out = {}
      for _, o in ipairs(list) do
        local text, kind = QB.Plain(o.text), QB.Plain(o.type)
        out[#out + 1] = { text = type(text) == "string" and text or nil, type = type(kind) == "string" and kind or nil,
                          done = QB.Plain(o.finished) and true or false, have = num(o.numFulfilled), need = num(o.numRequired) }
      end
      return out
    end
  end
  return e.objectives or {}
end

-- the kinds of the game's objective a catalog slot can be: slots 5-8 are items, 1-4 creatures and objects (a "use"
-- can be a spell cast on a creature, an explore an area trigger)
local ITEM = { item = true }
local GAME_TYPE = { k = { monster = true }, u = { object = true, monster = true }, c = { object = true },
                    e = { event = true, areatrigger = true, log = true } }
local function gameType(sp) if sp.slot >= 5 then return ITEM end return GAME_TYPE[sp.kind] end

local function says(o, name)
  return (name and type(o.text) == "string" and o.text:lower():find(name:lower(), 1, true)) and true or false
end

-- which of the game's objective lines each catalog slot is. A line fits a slot when its kind and count agree; a slot
-- takes the one fitting line that names it, or the only line that fits it when no other slot has nothing else left;
-- each pick can settle another, so this goes round until nothing more is settled. A slot whose count changed takes
-- the line that names it. A tie nothing settles (two slots of the same kind and count, on a client whose names aren't
-- the catalog's English ones) is never guessed by order: those slots stay unmatched, and their spots keep showing
-- until the quest is complete, as a slot no line fits does. A slot is named by names[slot] when Data.lua has its
-- item's name (D.SREQ's third field), else by its spot's name. Slot 0 is no objective of the catalog's (a spot of
-- players' games for a quest the catalog doesn't know, a spot no slot was found for): never matched here (QM.Loose
-- has those), it shows until the quest is complete.
function QM.Match(objs, list, need, names)
  local open, seen = {}, {}
  for _, sp in ipairs(list) do
    if sp.slot > 0 and not seen[sp.slot] then
      seen[sp.slot] = true
      open[#open + 1] = { slot = sp.slot, want = gameType(sp), count = need[sp.slot], name = names and names[sp.slot] or spotName(sp) }
    end
  end
  table.sort(open, function(a, b) return a.slot < b.slot end)
  local taken, out = {}, {}
  local function typeOk(s, o) return not (s.want and o.type) or s.want[o.type] end
  local function fitsOf(s)
    local fits = {}
    for i, o in ipairs(objs) do
      if not taken[i] and typeOk(s, o) then
        local typeHit = s.want and o.type and s.want[o.type]
        local countHit = s.count and o.need == s.count
        if (not (s.count and o.need) or countHit) and (typeHit or countHit) then fits[#fits + 1] = i end
      end
    end
    return fits
  end
  local function take(k, i)
    taken[i] = true
    out[open[k].slot] = objs[i]
    table.remove(open, k)
  end
  local settled = true
  while settled and #open > 0 do
    settled = false
    local fits, only = {}, {}
    for k, s in ipairs(open) do
      fits[k] = fitsOf(s)
      if #fits[k] == 1 then only[fits[k][1]] = (only[fits[k][1]] or 0) + 1 end
    end
    for k, s in ipairs(open) do
      local named
      for _, i in ipairs(fits[k]) do
        if says(objs[i], s.name) then named = (named == nil) and i or false end
      end
      local pick = named or (#fits[k] == 1 and only[fits[k][1]] == 1 and fits[k][1]) or nil
      if pick then take(k, pick); settled = true; break end
    end
  end
  -- the count changed: the name alone
  for k = #open, 1, -1 do
    local s = open[k]
    if #fitsOf(s) == 0 then
      for i, o in ipairs(objs) do
        if not taken[i] and typeOk(s, o) and says(o, s.name) then take(k, i) break end
      end
    end
  end
  return out
end

-- slot 0's spots, by kind: gen_data gives a spot of players' games that no slot of the catalog's was found for (every
-- spot of a quest the catalog doesn't know) the kind of the game's line it was seen for, and a spot from the quest's
-- outline the kind of its objective. So where the game has one line of that kind, and no slot of the catalog's
-- could be that line, the spots are that line's: [kind] = line. Two lines of a kind, or a line whose kind the game
-- doesn't say, are never guessed: those spots stay matched to nothing, and show until the quest is complete
local LOOSE = { k = { monster = true }, c = { item = true }, u = { object = true },
                e = { event = true, areatrigger = true, log = true, progressbar = true } }
function QM.Loose(objs, list)
  local kinds, claimed = {}, {}
  for _, sp in ipairs(list) do
    if sp.slot == 0 then
      kinds[sp.kind] = true
    else
      local want = gameType(sp)
      if not want then return {} end -- a slot that could be any line
      for t in pairs(want) do claimed[t] = true end
    end
  end
  local out = {}
  for kind in pairs(kinds) do
    local want, one = LOOSE[kind], nil
    for _, o in ipairs(want and objs or {}) do
      if not o.type or (want[o.type] and (claimed[o.type] or one)) then one = false break end
      if want[o.type] then one = o end
    end
    if one then out[kind] = one end
  end
  return out
end

----------------------------------------------------------------------------
-- the icons for one map
----------------------------------------------------------------------------
-- quests whose ! the catalog can't vouch for: D.QLOCK holds the quests that need a profession's skill or a
-- reputation (gen_data, from the Classic database), which QuestBank doesn't check, and the game shows no ! to a
-- player without them. Read as { [questId] = what it needs }, a list of quest ids, or "id,id,...".
-- An older Data.lua has none: then the "Other quests" of the Classic and Season of Discovery databases stand in
-- (professions, library books, mount exchanges, battlegrounds); Forever's own (Zephras Isle and on, from 90000)
-- are ordinary quests the catalog files there for want of a zone.
local FOREVER_OWN = 90000
local lockSet, lockFrom = nil, false
local function locks()
  local t = D.QLOCK
  if t == nil then return nil end
  if type(t) == "table" and rawget(t, 1) == nil then return t end -- by quest id (no quest 1 in the catalog)
  if lockFrom ~= t then
    lockFrom, lockSet = t, {}
    if type(t) == "string" then
      for id in t:gmatch("%d+") do lockSet[tonumber(id)] = true end
    elseif type(t) == "table" then
      for _, id in ipairs(t) do lockSet[id] = true end
    end
  end
  return lockSet
end
local function unchecked(q)
  local set = locks()
  if set then local v = set[q.id]; return (v ~= nil and v ~= false) and true or false end
  return (q.cat and q.cat.key == "misc" and q.id < FOREVER_OWN) and true or false
end
QM.Unchecked = unchecked

-- what this layer would show at an NPC a numbered route pin stands on, for that pin's tooltip:
-- [route pin's data] = { { name = NPC, own = the pin stands on this NPC, turn = quests, give = quests }, ... }
-- (weak: the route's pins are made again with every plan)
local also = setmetatable({}, { __mode = "k" })
-- map percent: another NPC this close to a route pin, or to an NPC with an icon, would have its icon right under it
local UNDER = 0.2

function QM:Build(m)
  local list = {}
  for r in pairs(also) do if r.m == m then also[r] = nil end end
  if not (on() and QM.Draws(m)) then return list end
  local set, s = QB:Settings(), QB.state
  local level = s.level or 1
  local range = greyRange(level)

  -- the numbered route pins on this map (when they are on). The NPC a pin stands on (its own name, a step away at
  -- most) gets no icon of its own: what the pin doesn't list already goes on its tooltip. So does a quest of another
  -- NPC at the very same spot, whose icon would lie under the pin; an NPC a little way off keeps its own icon.
  local route = {}
  if set.pins and QB.Pins then
    for _, r in ipairs(QB.Pins.list or {}) do if r.m == m then route[#route + 1] = r end end
  end
  local function routeOn(n)
    local under, best
    for _, r in ipairs(route) do
      local dx, dy = r.x - n.x, r.y - n.y
      local d2 = dx * dx + dy * dy
      if (r.who or r.name) == n.n and d2 <= NEAR * NEAR then return r, true end
      if d2 <= UNDER * UNDER and (not best or d2 < best) then under, best = r, d2 end
    end
    return under, false
  end
  local function fold(r, own, n, kind, q)
    if r.ids and r.ids[q.id] then return end
    local groups = also[r] or {}
    also[r] = groups
    local g
    for _, x in ipairs(groups) do if x.name == n.n then g = x break end end
    if not g then
      g = { name = n.n, own = own, turn = {}, give = {} }
      groups[#groups + 1] = g
    end
    table.insert(g[kind], q)
  end

  -- one icon per NPC (the catalog can hold one NPC twice, a step apart), and one for NPCs at the same spot (UNDER:
  -- two icons there would lie on top of each other, and only the top one could be hovered). An icon is a ? when
  -- anyone there takes a hand-in, else a !; d.who lists each NPC with its own hand-ins and quests to pick up
  local npcs = {}
  local function atNpc(kind, n, q)
    local r, own = routeOn(n)
    if r then fold(r, own, n, kind, q) return end
    local d, w
    for _, x in ipairs(npcs) do
      for _, y in ipairs(x.who) do
        local dx, dy = y.x - n.x, y.y - n.y
        if y.title == n.n and dx * dx + dy * dy <= NEAR * NEAR then d, w = x, y break end
      end
      if d then break end
    end
    if not d then
      for _, x in ipairs(npcs) do
        for _, y in ipairs(x.who) do
          local dx, dy = y.x - n.x, y.y - n.y
          if dx * dx + dy * dy <= UNDER * UNDER then d = x break end
        end
        if d then break end
      end
    end
    if not d then
      d = { kind = kind, level = "PIN_FRAME_LEVEL_INVASION", m = m, x = n.x / 100, y = n.y / 100, title = n.n, npc = n.idx, who = {} }
      npcs[#npcs + 1] = d
    end
    if not w then
      w = { title = n.n, npc = n.idx, x = n.x, y = n.y, turn = {}, give = {} }
      d.who[#d.who + 1] = w
    end
    table.insert(w[kind], q)
  end

  -- ? where the finished quests in your log are handed in
  if set.mapTurn ~= false then
    for _, e in ipairs(s.logOrder or {}) do
      local q = e.complete and Q.Get(e.id)
      local n = q and q.turn
      if n and n.m == m then atNpc("turn", n, q) end
    end
  end
  -- ! where the quests you can take now start
  if set.mapGive ~= false then
    for _, g in ipairs(giversOn(m) or {}) do
      for _, id in ipairs(g.ids) do
        local q = Q.Get(id)
        local n = q and q.give
        if n and n.m == m and not q.repeatable and not q.sodLeftover and not unchecked(q) and not s.log[id] then
          local st = QB:Status(q)
          if st.code == "todo" and not st.behind and not grey(q, level, range) then atNpc("give", n, q) end
        end
      end
    end
  end
  -- what each icon shows: its hand-ins (quests), and the quests to pick up there (on a ?, offers)
  for _, d in ipairs(npcs) do
    d.kind = "give"
    for _, w in ipairs(d.who) do if #w.turn > 0 then d.kind = "turn" end end
    d.art, d.quests = ART[d.kind], {}
    if d.kind == "turn" then d.offers = {} end
    for _, w in ipairs(d.who) do
      for _, q in ipairs(w[d.kind]) do d.quests[#d.quests + 1] = q end
      if d.offers then for _, q in ipairs(w.give) do d.offers[#d.offers + 1] = q end end
    end
    if d.offers and #d.offers == 0 then d.offers = nil end
  end
  -- the ! and ? first: the cap below only ever trims marks and areas
  for _, d in ipairs(npcs) do
    if #list >= MAX_PINS then break end
    list[#list + 1] = d
  end

  if set.mapObj ~= false then
    -- a list of marks for each objective of the quests in your log that isn't finished, and for each quest you can
    -- take that starts from an item, in the catalog's order (nearest the giver or hand-in first)
    local groups = {}
    if D.SPOT then
      for _, e in ipairs(s.logOrder or {}) do
        local all = not e.complete and spots(D.SPOT[e.id])
        local here = false
        for _, sp in ipairs(all or {}) do if sp.m == m then here = true break end end
        if here then
          local need, objs = needOf(e.id), objectivesOf(e)
          local lines, loose = QM.Match(objs, all, need.count, namesOf(need)), QM.Loose(objs, all)
          local q = Q.Get(e.id)
          local qname = q and q.name or QB.Plain(e.title) or ("Quest " .. e.id)
          -- one list of marks for each slot, and for slot 0 one for each kind (a quest the catalog doesn't know has
          -- all its spots there, and each of its objectives should get its nearest mark first too)
          local bySlot = {}
          for _, sp in ipairs(all) do
            local line = (sp.slot > 0 and lines[sp.slot]) or (sp.slot == 0 and loose[sp.kind]) or nil
            if sp.m == m and not (line and line.done) then
              local key = sp.slot > 0 and sp.slot or ("0" .. sp.kind)
              local g = bySlot[key]
              if not g then
                g = {}
                bySlot[key] = g
                groups[#groups + 1] = g
              end
              local name = spotName(sp)
              g[#g + 1] = { kind = "obj", art = ART[sp.kind] or ART.c, level = "PIN_FRAME_LEVEL_DIG_SITE", m = m, x = sp.x, y = sp.y,
                            spot = sp, id = e.id, qname = qname, line = line, title = name and (qname .. ": " .. name) or qname }
            end
          end
        end
      end
    end
    -- where the item that starts a quest you can take drops
    local starts = {}
    for _, it in ipairs(startsOn(m) or {}) do
      local q = Q.Get(it.id)
      if q and not s.log[it.id] then
        if starts[it.id] == nil then
          local st = QB:Status(q)
          starts[it.id] = st.code == "item" and not grey(q, level, range) and {} or false
          if starts[it.id] then groups[#groups + 1] = starts[it.id] end
        end
        local g = starts[it.id]
        if g then
          local sp = it.spot
          local name = spotName(sp) or (q.bag and q.bag[4])
          g[#g + 1] = { kind = "start", art = ART.s, badge = ART.bang, level = "PIN_FRAME_LEVEL_DIG_SITE", m = m, x = sp.x, y = sp.y,
                        spot = sp, id = it.id, q = q, item = name, title = name or q.name }
        end
      end
    end
    -- in turns, so every objective has its nearest mark before any has a second; then the areas under them while
    -- there is room. A zone with a full log can hold more than the cap (Stranglethorn: some 280 with the areas)
    local marks, total, rank = {}, 0, 1
    for _, g in ipairs(groups) do total = total + #g end
    while #marks < total and #list + #marks < MAX_PINS do
      for _, g in ipairs(groups) do
        if g[rank] and #list + #marks < MAX_PINS then marks[#marks + 1] = g[rank] end
      end
      rank = rank + 1
    end
    for _, mark in ipairs(marks) do list[#list + 1] = mark end
    local cut = total - #marks
    for _, mark in ipairs(marks) do
      local sp = mark.spot
      if sp.r >= MIN_AREA then
        if #list < MAX_PINS then
          list[#list + 1] = { kind = "area", m = m, x = sp.x, y = sp.y, r = sp.r, start = mark.kind == "start" or nil }
        else
          cut = cut + 1
        end
      end
    end
    list.cut = cut -- what the cap left out (the harness reads it)
  end
  return list
end

function QM:Draw(map, m)
  for _, d in ipairs(self:Build(m)) do map:AcquirePin(d.kind == "area" and AREA or ICON, d) end
end

----------------------------------------------------------------------------
-- tooltips and clicks
----------------------------------------------------------------------------
-- a quest's level in the game's colours: red, orange, yellow, green, grey
local function levelColor(qlvl, level, range)
  local d = (qlvl or level) - level
  if d >= 5 then return 1, 0.1, 0.1 elseif d >= 3 then return 1, 0.5, 0.25 elseif d >= -2 then return 1, 0.82, 0
  elseif -d <= range then return 0.25, 0.75, 0.25 end
  return 0.6, 0.6, 0.6
end

local function xpText(q, level)
  if q.xpUnknown and not q.liveFull then return "? XP" end
  return QB.Comma(QB.Model.XpAt(q, level)) .. " XP"
end

local function questLines(tip, quests)
  local level = QB.state.level or 1
  local range = greyRange(level)
  for _, q in ipairs(quests) do
    local tags = {}
    if q.dungeon then tags[#tags + 1] = "dungeon" end
    if q.group then tags[#tags + 1] = "group" end
    if q.escort then tags[#tags + 1] = "escort" end
    if q.classic then tags[#tags + 1] = "Classic only" end
    local r, g, b = levelColor(q.lvl, level, range)
    tip:AddDoubleLine(string.format("[%d] %s%s", q.lvl or 0, q.name, #tags > 0 and (" (" .. table.concat(tags, ", ") .. ")") or ""),
      xpText(q, level), r, g, b, 0.6, 1, 0.6)
  end
end

local function source(tip, src) tip:AddLine("Position: " .. (SOURCE[src] or CLASSIC), 0.6, 0.6, 0.6, true) end
local function hint(tip, shift) tip:AddLine("Click: waypoint.  Shift-click: " .. shift .. ".", 0.5, 0.5, 0.5, true) end

local function allAdded(quests)
  for _, q in ipairs(quests) do if not QB:IsAdded(q.id) then return false end end
  return true
end

local LABEL = { k = "Kill %s", c = "Loot %s", u = "Use %s", b = "Buy %s from the vendor here", e = "Go to %s", f = "%s: fish, pick pockets or skin here" }
local BARE = { k = "Kill here", c = "Loot here", u = "Use what is here", b = "Buy it from the vendor here", e = "Go here", f = "Fish, pick pockets or skin here" }

-- NPCs sharing an icon: each with its hand-ins and its quests to pick up; where their places come from once when
-- they agree, else under each
local function people(tip, d)
  local src, same = {}, true
  for i, w in ipairs(d.who) do
    src[i] = npcSource({ npc = w.npc, m = d.m })
    if src[i] ~= src[1] then same = false end
  end
  for i, w in ipairs(d.who) do
    tip:AddLine(w.title, 1, 0.82, 0)
    if #w.turn > 0 then
      tip:AddLine("Hand in:", 0.8, 0.8, 0.8)
      questLines(tip, w.turn)
    end
    if #w.give > 0 then
      tip:AddLine(#w.turn > 0 and "Also to pick up:" or "To pick up:", 0.8, 0.8, 0.8)
      questLines(tip, w.give)
    end
    if not same then source(tip, src[i]) end
  end
  if same then source(tip, src[1]) end
end

local TIP = {}
function TIP.give(tip, d)
  if d.who and #d.who > 1 then
    people(tip, d)
  else
    tip:AddLine(d.title, 1, 0.82, 0)
    questLines(tip, d.quests)
    source(tip, npcSource(d))
  end
  local many = #d.quests > 1
  hint(tip, allAdded(d.quests) and (many and "take them off your pick-up list" or "take it off your pick-up list")
    or (many and "put them on your pick-up list" or "put it on your pick-up list"))
end
function TIP.turn(tip, d)
  if d.who and #d.who > 1 then
    people(tip, d)
  else
    tip:AddLine(d.title, 1, 0.82, 0)
    tip:AddLine("Hand in:", 0.8, 0.8, 0.8)
    questLines(tip, d.quests)
    if d.offers and #d.offers > 0 then
      tip:AddLine("Also to pick up:", 0.8, 0.8, 0.8)
      questLines(tip, d.offers)
    end
    source(tip, npcSource(d))
  end
  hint(tip, #d.quests > 1 and "track them" or "track it")
end
function TIP.obj(tip, d)
  local sp = d.spot
  local name = spotName(sp)
  tip:AddLine(d.qname, 1, 0.82, 0)
  tip:AddLine(name and string.format(LABEL[sp.kind] or "%s", name) or (BARE[sp.kind] or "Here"), 1, 1, 1, true)
  local line = d.line
  if line and line.text then
    if line.done then tip:AddLine(line.text, 0.4, 0.9, 0.4, true) else tip:AddLine(line.text, 0.9, 0.9, 0.9, true) end
  end
  source(tip, sp.src)
  hint(tip, "track the quest")
end
function TIP.start(tip, d)
  local q = d.q
  tip:AddLine(d.item or "A quest item", 1, 0.82, 0)
  tip:AddLine("Drops here, and starts:", 1, 1, 1, true)
  questLines(tip, { q })
  source(tip, d.spot.src)
  hint(tip, QB:IsAdded(q.id) and "take it off your pick-up list" or "put it on your pick-up list")
end
QM.TIP = TIP

-- on a numbered route pin's tooltip (Pins.lua): what this layer would show at the NPCs under that pin, on the pin's
-- own map (on a continent, where this layer draws nothing, the pin hides nothing)
function QM.AlsoHere(tip, r, shown)
  if shown and shown ~= r.m then return end
  for _, g in ipairs(also[r] or {}) do
    if #g.turn > 0 then
      tip:AddLine(g.own and "Also to hand in here:" or (g.name .. ", to hand in:"), 0.8, 0.8, 0.8)
      questLines(tip, g.turn)
    end
    if #g.give > 0 then
      tip:AddLine(g.own and "Also to pick up here:" or (g.name .. ", to pick up:"), 0.8, 0.8, 0.8)
      questLines(tip, g.give)
    end
  end
end

local function idsOf(d)
  local out = {}
  if d.quests then for _, q in ipairs(d.quests) do out[#out + 1] = q.id end else out[1] = d.id end
  return out
end

local function names(ids)
  local out = {}
  for _, id in ipairs(ids) do out[#out + 1] = Q.Label(id) end
  return table.concat(out, ", ")
end

-- the game's quest watch (the objective tracker), by quest id; the Classic client's by log index
local function watched(id)
  if C_QuestLog and C_QuestLog.GetQuestWatchType then
    local ok, w = pcall(C_QuestLog.GetQuestWatchType, id)
    return ok and QB.Plain(w) ~= nil
  end
  local e = QB.state.log[id]
  if e and IsQuestWatched then
    local ok, w = pcall(IsQuestWatched, e.index)
    return ok and w and true or false
  end
  return false
end

local function watch(id, want)
  if C_QuestLog and C_QuestLog.AddQuestWatch then
    pcall(want and C_QuestLog.AddQuestWatch or C_QuestLog.RemoveQuestWatch, id)
    return
  end
  local e, f = QB.state.log[id], want and AddQuestWatch or RemoveQuestWatch
  if e and f then pcall(f, e.index) end
end

-- Shift-click: a quest in your log goes on (or off) the game's tracker; one you haven't taken goes on (or off)
-- QuestBank's pick-up list, as the route's ! pins show it
function QM.Track(d)
  local ids = idsOf(d)
  if #ids == 0 then return end
  if d.kind == "give" or d.kind == "start" then
    local all = true
    for _, id in ipairs(ids) do if not QB:IsAdded(id) then all = false end end
    for _, id in ipairs(ids) do if QB:IsAdded(id) == all then QB:ToggleAdd(id) end end
    QB:Print((all and "Off your pick-up list: " or "On your pick-up list: ") .. names(ids) .. ".")
  else
    local all = true
    for _, id in ipairs(ids) do if not watched(id) then all = false end end
    for _, id in ipairs(ids) do watch(id, not all) end
    QB:Print((all and "No longer tracking " or "Tracking ") .. names(ids) .. ".")
  end
end

local function click(d, button)
  -- a right-click passes through to zoom the map out; one that reaches a pin (in combat) is left alone
  if not d or button == "RightButton" then return end
  if IsShiftKeyDown and IsShiftKeyDown() then QM.Track(d) return end
  QB.API.SetWaypoint(d.m, d.x * 100, d.y * 100, d.title)
end

----------------------------------------------------------------------------
-- the pins (templates in Pins.xml; the mixins are rebuilt on the map's own pin mixin once the map loads)
----------------------------------------------------------------------------
local Icon = {}
QuestBankQuestPinMixin = Icon
Icon.SetPassThroughButtons = QB.Pins.PassThrough

function Icon:OnLoad()
  if self.SetScalingLimits then self:SetScalingLimits(1, 1.0, 1.2) end
end

Icon.OnAcquired = QB.Safe(function(self, d)
  self.data = d
  -- under the numbered route pins (AREA_POI): ! and ? on INVASION, objectives below them on DIG_SITE
  if self.UseFrameLevelType then self:UseFrameLevelType(d.level) end
  local size = d.art.size or 16
  self:SetSize(size, size)
  paint(self.Icon, d.art)
  if d.badge then paint(self.Badge, d.badge); self.Badge:Show() else self.Badge:Hide() end
  self:SetPosition(d.x, d.y)
end, "map icon")

Icon.OnMouseEnter = QB.Safe(function(self)
  local d = self.data
  if not (d and TIP[d.kind]) then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  TIP[d.kind](GameTooltip, d)
  GameTooltip:Show()
end, "map icon tooltip")

function Icon:OnMouseLeave() GameTooltip:Hide() end

-- the map canvas calls this on a click (it owns the pin's mouse scripts)
function Icon:OnMouseClickAction(button) QB.Try("map icon click", click, self.data, button) end

local Area = {}
QuestBankAreaPinMixin = Area
Area.SetPassThroughButtons = QB.Pins.PassThrough

function Area:OnLoad()
  -- the size of the ground it covers, whatever the zoom; under every icon
  if self.SetIgnoreGlobalPinScale then self:SetIgnoreGlobalPinScale(true) end
  if self.SetScaleStyle and AM_PIN_SCALE_STYLE_WITH_TERRAIN then self:SetScaleStyle(AM_PIN_SCALE_STYLE_WITH_TERRAIN) end
  if self.UseFrameLevelType then self:UseFrameLevelType("PIN_FRAME_LEVEL_QUEST_BLOB") end
end

-- r is a fraction of the map's width, as the canvas is
function Area:Fit()
  local d, map = self.data, self:GetMap()
  local canvas = d and map and map.GetCanvas and map:GetCanvas()
  if not canvas then return end
  local size = math.max(4, 2 * d.r * (canvas:GetWidth() or 0))
  self:SetSize(size, size)
end

Area.OnAcquired = QB.Safe(function(self, d)
  self.data = d
  paint(self.Circle, ART.area)
  if d.start then self.Circle:SetVertexColor(0.7, 0.85, 1) else self.Circle:SetVertexColor(1, 0.82, 0) end
  self.Circle:SetAlpha(0.22)
  self:Fit()
  self:SetPosition(d.x, d.y)
end, "map area")

-- the map was made bigger or smaller: the area keeps its size on the ground
function Area:OnCanvasSizeChanged() QB.Try("map area", self.Fit, self) end

----------------------------------------------------------------------------
-- switching
----------------------------------------------------------------------------
function QM:Init()
  if self.provider or self.waiting or not QM.Available() then return end
  self.waiting = QB.Pins.WhenMap(function()
    if QM.provider then return end
    QuestBankQuestPinMixin = CreateFromMixins(MapCanvasPinMixin, Icon)
    QuestBankAreaPinMixin = CreateFromMixins(MapCanvasPinMixin, Area)
    QM.provider = QB.Pins.NewProvider({ ICON, AREA }, function(map, m) QM:Draw(map, m) end, "map icons")
  end, "map icons: waiting for the map")
end

-- after QB:Changed: the open map shows the plan and the log as they are now
function QM:Update()
  if self.provider and WorldMapFrame and WorldMapFrame:IsShown() then self.provider:RefreshAllData() end
end

-- Settings' rows: mapIcons (all of them), mapGive, mapTurn, mapObj
function QM.Set(key, value)
  QB:Settings()[key] = value and true or false
  QM:Update()
end

-- /qb icons
function QM:Toggle()
  if not QM.Available() then
    QB:Print("Quest icons on the world map need the Forever client.")
    return
  end
  local set = QB:Settings()
  set.mapIcons = set.mapIcons == false
  QB:Print(set.mapIcons and "Quest icons on the world map on: ! to pick up, ? to hand in, and the objectives of the quests in your log. Settings has a switch for each."
    or "Quest icons on the world map off. /qb icons brings them back.")
  self:Update()
end
