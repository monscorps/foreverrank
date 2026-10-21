-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank's finds: what the world holds beyond quests, noted as you play, for foreverrank.com (and, under Cute, the
-- guild later). The client data holds no world books, chests or rares (GameObjects.csv is signposts, Vignette.csv two
-- rows), so every one of these is learned in play, never listed:
--   disc.find[key]   key "o<object id>", "c<creature id>" or "i<item id>", as disc.loot's (Discover.Key):
--                    p = { { uiMap, x, y, n }, ... } where you stood (thousandths of the map, about 5 yards out; at most
--                    POINTS a map, merged within Discover's OS_NEAR), outdoors only; n = times noted; v = build;
--                    h = { ["class.subclass"] = items } an object looted, its kind learned from the items it gave;
--                    k = { item ids } the key-class items in your bags when you opened it with a key, most likely first
--                    (the site joins them with the client's Lock.csv to say which key it was); b = a book's title (ItemTextGetItem, never the text);
--                    r = a rare's level (its nameplate said "rare" or "rareelite")
--   disc.findN       a counter, bumped on every note; disc.findAt[key] its value when the key was last touched
--   disc.rides["x:<map>:<x>,<y>><map>:<x>,<y>"] = { b = { c, wx, wy }, l = { c, wx, wy }, t = seconds (the mean of the
--                    last few), n = crossings, at = minutes, f = "A" or "H" the faction that took it } a jump in place
--                    that is no flight, hearth, death, summons or instance door: a portal, the way to Zephras Isle
--                    (Travel.lua keeps D.LINK's boat legs there). The faction, so a release never routes the other
--                    side through a city's portal
--   disc.flown["<TaxiNodes id>><TaxiNodes id>"] = { n, secs, ff = Frequent Flier's rank }: Travel's measured flights,
--                    every character's, with no character in them
--   disc.token       a random token made once per saved file: the site counts files, not re-uploads of a growing one
--   disc.qtime       the work each quest took, every character's, name-free (Timer.lua keeps it per character)
-- Every value is read through QB.Plain, nothing is noted while the game holds addons back (ADDON_RESTRICTION_STATE_CHANGED)
-- or outside the Forever client, and all of it sits under Settings' "Note items, spells and loot" box (unticking clears
-- it, as it clears the loot notes). Never a player's name: a book's title is the only text kept.
-- Also here: QuestBank_Finds, the uploader's data addon, read into D.FIND at login where Data.lua has no row.
-- Only reads: nothing is looted, opened, targeted or cast.
local _, QB = ...
if QB.dormant then return end
local Finds = {}
QB.Finds = Finds

local POINTS = 4        -- points kept a map for one find
local OBJECTS = 400     -- objects and items read kept; over that, the one touched longest ago goes
local RARES = 200       -- rares kept, the same way
local CROSSINGS = 100   -- crossings kept in disc.rides beyond D.LINK's legs, the oldest out
local KEYS = 8          -- key candidates kept for a locked object
local KINDS = 6         -- item kinds (class.subclass) kept for a looted object
local OPEN_S = 10       -- seconds after an opening cast in which the next object looted is the one opened
local SOFT_S = 5        -- seconds a game object the Interact key pointed at stays the one you read
local STILL_YD, STILL_S = 5, 10 -- a stand: within this many yards for this many seconds (the pier, the tower)
local BEFORE_S = 180    -- seconds before a jump a stand still counts as where the crossing started
local BEFORE_YD = 200   -- yards from the last place before the jump within which that stand is its start
local JUMP = 300        -- yards within a look: a jump in place (Target.lua's)
local LINK_YD = 300     -- yards from a D.LINK end, or from its track where the far side loads: that leg, Travel's to learn
local CAST_S = 5        -- seconds from a hearth or a class teleport to its loading screen (or, with none, its jump)
local SUMMON_S = 120    -- seconds a summons offered stays one you can take
local MEAN = 5          -- crossings and flights a learned time averages over
local TICK = 1          -- seconds between looks
Finds.POINTS, Finds.OBJECTS, Finds.RARES, Finds.CROSSINGS, Finds.KEYS = POINTS, OBJECTS, RARES, CROSSINGS, KEYS
Finds.STILL_S, Finds.BEFORE_S, Finds.JUMP = STILL_S, BEFORE_S, JUMP

local plain = QB.Plain
local floor, sqrt, max = math.floor, math.sqrt, math.max
local function now() return GetTime and GetTime() or 0 end
local function num(v) v = plain(v); return type(v) == "number" and v or nil end
local function minutes() return type(time) == "function" and floor(time() / 60) or nil end

-- noting: the Forever client with the Settings box ticked (the loot notes' box: these are foreverrank.com's data of
-- the same kind)
function Finds.On() return (QB.Game and QB.Game.On()) and true or false end

-- the game holding addons back (a fight, an encounter, a map or a match that restricts them): nothing is noted then.
-- The event comes before a restriction starts and after one ends (RestrictedActionsDocumentation.lua); the state is
-- Enum.AddOnRestrictionState: 0 Inactive, 1 Activating, 2 Active. IsAddOnRestrictionActive answers false during that
-- event's dispatch, so both are asked
local held = {}
function Finds.Held()
  if next(held) then return true end
  local R = C_RestrictedActions
  if R and type(R.IsAddOnRestrictionActive) == "function" then
    for t = 0, 5 do
      local ok, on = pcall(R.IsAddOnRestrictionActive, t)
      if ok and plain(on) == true then return true end
    end
  end
  return false
end
local function noting() return Finds.On() and not Finds.Held() end

local function build()
  if not GetBuildInfo then return nil end
  local ok, _, b = pcall(GetBuildInfo)
  return ok and tonumber(plain(b)) or nil
end

-- counts of what the client showed, so the uploads settle what it hands addons here: loot windows with an object
-- outdoors (lo), opening casts (op), those with a key (ok) and the object they named (oo by the Interact key, ol by the
-- next loot window), books read (bk) by object (bo), by item (bi) or neither (bn), a text someone wrote left alone (bw),
-- rare plates (rp), crossings kept (xk), jumps left out as a D.LINK leg (xl) or a teleport (xt), items whose class the
-- client didn't know (iu)
local function diag(k)
  if not QuestBankDB then return end
  QuestBankDB.diag = QuestBankDB.diag or {}
  local d = QuestBankDB.diag.finds
  if type(d) ~= "table" then
    d = {}
    QuestBankDB.diag.finds = d
  end
  d[k] = (tonumber(d[k]) or 0) + 1
end
Finds.Diag = diag

----------------------------------------------------------------------------
-- the saved notes
----------------------------------------------------------------------------
local function db()
  local d = QB.Discover.DB()
  if type(d.find) ~= "table" then d.find = {} end
  if type(d.findAt) ~= "table" then d.findAt = {} end
  return d
end

-- the file's token: 16 hex characters, made once. (The client's math.random can't be seeded by an addon; the clock
-- mixed in keeps two files made the same second apart)
function Finds.Token()
  local d = QB.Discover.DB()
  if type(d.token) == "string" and d.token:find("^%x+$") and #d.token == 16 then return d.token end
  local seed = floor(((time and time()) or 0) + now() * 1000)
  local parts = {}
  for i = 1, 4 do
    local r = math.random and math.random(0, 65535) or 0
    parts[i] = string.format("%04x", (r + seed * (i * 7919)) % 65536)
  end
  d.token = table.concat(parts)
  return d.token
end

-- how many objects (and items read) or rares a key counts against
local function capOf(key) return key:sub(1, 1) == "c" and RARES or OBJECTS end

-- the record of key, made when new (the one touched longest ago of its kind goes past the cap)
local function record(key)
  local d = db()
  local all, at = d.find, d.findAt
  local rec = all[key]
  if type(rec) ~= "table" then
    rec = { n = 0 }
    all[key] = rec
    local rare = key:sub(1, 1) == "c"
    local n = 0
    for k in pairs(all) do if (k:sub(1, 1) == "c") == rare then n = n + 1 end end
    while n > capOf(key) do
      local old, when
      for k in pairs(all) do
        if (k:sub(1, 1) == "c") == rare and k ~= key then
          local w = tonumber(at[k]) or 0
          if not when or w < when or (w == when and k < old) then old, when = k, w end
        end
      end
      if not old then break end
      all[old], at[old] = nil, nil
      n = n - 1
    end
  end
  d.findN = (tonumber(d.findN) or 0) + 1
  at[key] = d.findN
  rec.n = (tonumber(rec.n) or 0) + 1
  rec.v = build() or rec.v
  return rec
end
Finds.Record = record

-- a point where you stood, merged into the nearest within OS_NEAR on that map (which moves to the mean of its
-- sightings), else one of its own; past POINTS on that map the one seen fewest times goes, and a new point is left out
-- when every kept one was seen more than once
local function addPoint(rec, m, x, y)
  if type(rec.p) ~= "table" then rec.p = {} end
  local near = QB.Discover.OS_NEAR
  local best, bestD, onMap, low, li = nil, nil, 0, nil, nil
  for i, p in ipairs(rec.p) do
    if p[1] == m then
      onMap = onMap + 1
      local dx, dy = p[2] - x, p[3] - y
      local d2 = dx * dx + dy * dy
      if d2 <= near * near and (not bestD or d2 < bestD) then best, bestD = p, d2 end
      local n = p[4] or 1
      if not low or n < low then low, li = n, i end
    end
  end
  if best then
    local n = best[4] or 1
    best[2], best[3], best[4] = floor((best[2] * n + x) / (n + 1) + 0.5), floor((best[3] * n + y) / (n + 1) + 0.5), n + 1
    return best
  end
  if onMap >= POINTS then
    if low > 1 then return nil end
    table.remove(rec.p, li)
  end
  local p = { m, x, y, 1 }
  rec.p[#rec.p + 1] = p
  return p
end
Finds.AddPoint = addPoint

----------------------------------------------------------------------------
-- objects: looted outdoors, opened with a key, read
----------------------------------------------------------------------------
-- an item's class and subclass as the client knows it (C_Item.GetItemInfoInstant: itemID, type, subType, equipLoc,
-- icon, classID, subClassID, ItemDocumentation.lua), or nil for an item the client has no row for
local function classOf(id)
  local f = C_Item and C_Item.GetItemInfoInstant
  if type(f) ~= "function" then return nil end
  local ok, _, _, _, _, _, cls, sub = pcall(f, id)
  cls, sub = ok and num(cls) or nil, ok and num(sub) or nil
  if not cls then return nil end
  return cls, sub or 0
end

-- the key-class items in your bags (Enum.ItemClass.Key, 13), the items the client's Lock.csv names as a lock's key
-- whatever their class (D.LOCKKEY: the Keystone Fragment is a miscellaneous item, the Black Tome a quest item), and
-- the ones the client has no row for (a server-sent key has none): the candidates, at most KEYS, most likely first.
-- Those with no row, then the highest ids: Forever's own keys (the Brooch of the Wardens 277136) are newer than every
-- Classic key a keyring carries (5396 to 18249)
local KEY_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Key) or 13
local function keyCandidates()
  local C = C_Container
  if not (C and C.GetContainerNumSlots and C.GetContainerItemID and C_Item and type(C_Item.GetItemInfoInstant) == "function") then return {} end
  local lockKey = type(QB.Data.LOCKKEY) == "table" and QB.Data.LOCKKEY or {}
  local seen, out, rowless = {}, {}, {}
  local bags = { -1 } -- (Enum.BagIndex.Keyring, where the client has one)
  for b = 0, (NUM_BAG_SLOTS or 4) do bags[#bags + 1] = b end
  for _, bag in ipairs(bags) do
    local okN, n = pcall(C.GetContainerNumSlots, bag)
    n = okN and num(n) or 0
    for slot = 1, n do
      local okI, id = pcall(C.GetContainerItemID, bag, slot)
      id = okI and num(id) or nil
      if id and not seen[id] then
        seen[id] = true
        local cls = classOf(id)
        if cls == nil then diag("iu"); rowless[id] = true end
        if cls == nil or cls == KEY_CLASS or lockKey[id] then out[#out + 1] = id end
      end
    end
  end
  table.sort(out, function(a, b)
    if rowless[a] ~= rowless[b] then return rowless[a] == true end
    return a > b
  end)
  while #out > KEYS do table.remove(out) end
  return out
end
Finds.KeyCandidates = keyCandidates

-- a looted object's items: one count a window for each class.subclass pair; past KINDS pairs the least seen goes
local function noteKinds(rec, items)
  if type(rec.h) ~= "table" then rec.h = {} end
  local h = rec.h
  local had = {}
  for _, id in ipairs(items) do
    local cls, sub = classOf(id)
    if cls then
      local k = cls .. "." .. sub
      if not had[k] then
        had[k] = true
        if h[k] then
          h[k] = (tonumber(h[k]) or 0) + 1
        else
          local n, low, lowK = 0, nil, nil
          for kk, c in pairs(h) do
            n = n + 1
            c = tonumber(c) or 0
            if not low or c < low or (c == low and kk < lowK) then low, lowK = c, kk end
          end
          if n >= KINDS then
            if low > 1 then k = nil else h[lowK] = nil end
          end
          if k then h[k] = 1 end
        end
      end
    end
  end
end

-- the object you opened with a cast of one of the client's opening spells (D.OPEN), waiting for its loot window when
-- the Interact key didn't name it: { at, keys }
local opening
-- the game object the Interact key last pointed at: { key, at } (PLAYER_SOFT_INTERACT_CHANGED)
local soft

-- the object the Interact key points at now, or did a moment ago
local function softObject()
  if UnitGUID then
    local ok, g = pcall(UnitGUID, "softinteract")
    local key = ok and QB.Discover.Key(plain(g)) or nil
    if key and key:sub(1, 1) == "o" then return key end
  end
  if soft and now() - soft.at <= SOFT_S then return soft.key end
  return nil
end

-- an object opened with a key: its key candidates, at the spot. A key that opens it is in the bags each time, so a
-- second opening keeps what both keyrings held (in this opening's order), or this opening's alone when they share none
local function noteLocked(key, keys, m, x, y)
  local rec = record(key)
  addPoint(rec, m, x, y)
  local had = {}
  for _, id in ipairs(type(rec.k) == "table" and rec.k or {}) do had[id] = true end
  local both = {}
  for _, id in ipairs(keys) do if had[id] then both[#both + 1] = id end end
  local k = {}
  for _, id in ipairs(#both > 0 and both or keys) do if #k < KEYS then k[#k + 1] = id end end
  rec.k = k
end

-- a loot window (LOOT_OPENED, not from an item or fishing): each game object behind an item, looted outdoors, keeps
-- the spot and the kinds of the items it gave; the one an opening cast just named keeps its key candidates too.
-- Creatures are Loot.lua's (by map, never by spot)
function Finds.LootOpened(isFromItem)
  if not noting() or plain(isFromItem) == true then return end
  if IsFishingLoot then
    local ok, fishing = pcall(IsFishingLoot)
    if ok and plain(fishing) == true then return end
  end
  if not (GetNumLootItems and GetLootSourceInfo and GetLootSlotLink) then return end
  local okN, n = pcall(GetNumLootItems)
  n = okN and num(n) or 0
  local ITEM = (Enum and Enum.LootSlotType and Enum.LootSlotType.Item) or 1
  local objs, order = {}, {}
  for slot = 1, n do
    local kind = ITEM
    if GetLootSlotType then
      local okK, k = pcall(GetLootSlotType, slot)
      kind = okK and plain(k) or nil
    end
    if kind == ITEM then
      local okL, link = pcall(GetLootSlotLink, slot)
      link = okL and plain(link) or nil
      local id = type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) or nil
      if id then
        local ok, a, _, b, _, c, _, d = pcall(GetLootSourceInfo, slot)
        if ok then
          for _, g in ipairs({ a, b, c, d }) do
            local key = QB.Discover.Key(plain(g))
            if key and key:sub(1, 1) == "o" then
              if not objs[key] then objs[key] = {}; order[#order + 1] = key end
              local list = objs[key]
              list[#list + 1] = id
            end
          end
        end
      end
    end
  end
  if #order == 0 then return end
  local m, x, y = QB.Discover.Spot()
  if not m then return end
  diag("lo")
  local op = opening
  if op and now() - op.at > OPEN_S then op, opening = nil, nil end
  for _, key in ipairs(order) do
    local rec = record(key)
    addPoint(rec, m, x, y)
    noteKinds(rec, objs[key])
  end
  if op then
    opening = nil
    diag("ol")
    if #op.keys > 0 then noteLocked(order[1], op.keys, m, x, y) end
  end
end

-- a cast of yours went off: one of the client's opening spells (D.OPEN: an open-lock effect of a lock type that is no
-- gathering skill, gen_data.py from SpellEffect.csv) on a game object is an object opened. One that opens no lock type
-- (0: Opening 3366 and the named ones, Opening Cage and the like) opens with a key, the lock's item (a spell of a lock
-- type opens that type's locks, with no key: a plain chest's Opening 3365 is type 5), and only then are the keys in
-- the bags noted. The object is the one the Interact key points at, else the next object looted within OPEN_S
function Finds.Cast(spell)
  spell = num(spell)
  local open = QB.Data.OPEN
  if not (spell and type(open) == "table" and open[spell]) or not noting() then return end
  diag("op")
  if open[spell] ~= 0 then return end
  diag("ok")
  local keys = keyCandidates()
  local key = softObject()
  if key then
    local m, x, y = QB.Discover.Spot()
    diag("oo")
    if m and #keys > 0 then noteLocked(key, keys, m, x, y) end
    opening = nil
    return
  end
  opening = { at = now(), keys = keys }
end

-- the bag item named as the text's title (an item read from the bags), or nil
local function bagItemNamed(title)
  local C = C_Container
  local nameOf = C_Item and C_Item.GetItemNameByID
  if not (C and C.GetContainerNumSlots and C.GetContainerItemID and type(nameOf) == "function") then return nil end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local okN, n = pcall(C.GetContainerNumSlots, bag)
    n = okN and num(n) or 0
    for slot = 1, n do
      local okI, id = pcall(C.GetContainerItemID, bag, slot)
      id = okI and num(id) or nil
      if id then
        local okT, name = pcall(nameOf, id)
        if okT and plain(name) == title then return id end
      end
    end
  end
  return nil
end

-- a title as it may be kept: one line, no escape codes or separators, at most 60 bytes on a whole character (Cute's
-- S.LABEL_MAX cleaning); nil when nothing is left
local function cleanTitle(s)
  s = plain(s)
  if type(s) ~= "string" then return nil end
  s = s:gsub("[|;=]", ""):gsub("%c", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  if #s > 60 then
    local cut = 60
    while cut > 0 do local b = s:byte(cut + 1); if not b or b < 0x80 or b > 0xBF then break end cut = cut - 1 end
    s = s:sub(1, cut):gsub(" $", "")
  end
  return s ~= "" and s or nil
end
Finds.CleanTitle = cleanTitle

-- a text opened (ITEM_TEXT_BEGIN): its title and the game object the Interact key points at, kept until its page is
-- shown (ITEM_TEXT_READY), where the writer is known: the client's own ItemTextFrame reads ItemTextGetItem at BEGIN and
-- ItemTextGetCreator only at READY (Blizzard_UIPanels_Game/Mainline/ItemTextFrame.lua; the events in
-- ItemTextDocumentation.lua). Then an item in your bags of that name is one read (no place: it could be read
-- anywhere); else the object is a book where you stand. The title only, never the text. A text someone wrote
-- (ItemTextGetCreator names its writer: a letter kept from the mail) is never noted, nor anything read at the mailbox
local reading -- { title, key } from ITEM_TEXT_BEGIN to its first ITEM_TEXT_READY
function Finds.TextBegin()
  reading = nil
  if not noting() or type(ItemTextGetItem) ~= "function" then return end
  local mail = _G and _G.MailFrame
  if type(mail) == "table" and mail.IsShown then
    local okM, open = pcall(mail.IsShown, mail)
    if okM and open == true then diag("bw"); return end
  end
  local ok, t = pcall(ItemTextGetItem)
  local title = ok and cleanTitle(t) or nil
  if not title then return end
  reading = { title = title, key = softObject() }
end

-- the page shown (ITEM_TEXT_READY): the text ITEM_TEXT_BEGIN opened noted, once (a page turned sends READY again)
function Finds.TextReady()
  local r = reading
  reading = nil
  if not r or not noting() then return end
  if type(ItemTextGetCreator) == "function" then
    local okC, who = pcall(ItemTextGetCreator)
    if not okC or who ~= nil then diag("bw"); return end
  end
  diag("bk")
  local item = bagItemNamed(r.title)
  if item then
    diag("bi")
    record("i" .. item).b = r.title
    return
  end
  if r.key then
    local m, x, y = QB.Discover.Spot()
    if not m then return end
    diag("bo")
    local rec = record(r.key)
    addPoint(rec, m, x, y)
    rec.b = r.title
    return
  end
  diag("bn")
end

----------------------------------------------------------------------------
-- rares: a nameplate that says "rare" or "rareelite" (plates show within about 40 yards), one point per creature per
-- map cell; a plate shown again in a cell already noted this session notes nothing
----------------------------------------------------------------------------
local rareSeen = {} -- ["<key>:<map>:<cell x>,<cell y>"] = true, this session
local RARE = { rare = true, rareelite = true }
function Finds.Plate(unit)
  unit = plain(unit)
  if type(unit) ~= "string" or not UnitClassification then return end
  local ok, cls = pcall(UnitClassification, unit)
  if not (ok and RARE[plain(cls)]) or not noting() then return end
  local okG, g = pcall(UnitGUID, unit)
  local key = okG and QB.Discover.Key(plain(g)) or nil
  if not (key and key:sub(1, 1) == "c") then return end
  diag("rp")
  local m, x, y = QB.Discover.Spot()
  if not m then return end
  local near = QB.Discover.OS_NEAR
  local cell = key .. ":" .. m .. ":" .. floor(x / near) .. "," .. floor(y / near)
  if rareSeen[cell] then return end
  rareSeen[cell] = true
  local rec = record(key)
  addPoint(rec, m, x, y)
  local okL, lvl = pcall(UnitLevel, unit)
  lvl = okL and num(lvl) or nil
  if lvl and lvl > 0 then rec.r = lvl end
end

----------------------------------------------------------------------------
-- crossings: a jump in place (300 yards within a look, another continent, or past a loading screen) that is none of a
-- flight, a hearth or a class teleport, a summons, a death or an instance door, from where you last stood still for
-- STILL_S seconds in the BEFORE_S before it (the pier, the tower, the portal), else the last place before it, to where
-- you came out. Kept in disc.rides under an "x:" key, merged with one whose two ends lie within OS_NEAR of these
----------------------------------------------------------------------------
-- cross.tele: a loading screen began within CAST_S of a hearth or a teleport of yours, within SUMMON_S of a summons,
-- or while Travel saw the hearth cast: the jump past it is that, however long the screen lasts (the looks stop
-- through it while the clock runs on); kept until a jump, or the first look with a position once you are back in the
-- world (cross.back: PLAYER_ENTERING_WORLD)
local cross = { anchor = nil, still = nil, last = nil, castAt = -1000, summonAt = -1000, tele = false, back = false }
Finds.cross = cross

local function yd(a, b)
  if not (a and b) or a.c ~= b.c then return math.huge end
  local dx, dy = a.wx - b.wx, a.wy - b.wy
  return sqrt(dx * dx + dy * dy)
end

local function dead() return UnitIsDeadOrGhost and plain(UnitIsDeadOrGhost("player")) == true end
local function onTaxi() return UnitOnTaxi and plain(UnitOnTaxi("player")) == true end
local function inside()
  if not IsInInstance then return false end
  local ok, i = pcall(IsInInstance)
  return not ok or plain(i) ~= false
end

-- a hearth, Astral Recall or one of your own spells (a class teleport) went off: a jump in the next seconds is that
function Finds.Teleported() cross.castAt = now() end
-- the game offered you a summons
function Finds.Summoned() cross.summonAt = now() end
-- whether a jump now would be a teleport, a hearth or a summons
local function teleporting(t)
  return t - cross.castAt <= CAST_S or t - cross.summonAt <= SUMMON_S or (QB.Travel and QB.Travel.cast ~= nil) or false
end
-- a loading screen began (LOADING_SCREEN_ENABLED, PLAYER_LEAVING_WORLD: LoadingScreenDocumentation.lua,
-- SystemDocumentation.lua): whether what follows is a teleport is told now, by when it began
function Finds.Loading()
  if teleporting(now()) then cross.tele, cross.back = true, false end
end

-- a D.LINK row's track as numbers, { c, wx, wy, c, wx, wy, ... }, read once a row (only at a jump)
local tracks = setmetatable({}, { __mode = "k" })
local function trackOf(l)
  local tr = tracks[l]
  if tr then return tr end
  tr = {}
  for c, x, y in tostring(l[6] or ""):gmatch("(%-?%d+),(%-?[%d.]+),(%-?[%d.]+)") do
    tr[#tr + 1], tr[#tr + 2], tr[#tr + 3] = tonumber(c), tonumber(x), tonumber(y)
  end
  tracks[l] = tr
  return tr
end

-- yards from p to the track's stretch from point i to point j (1-based points, j >= i), on p's continent only
local function nearStretch(p, tr, i, j)
  local best = math.huge
  for k = max(i, 1), j do
    local o = (k - 1) * 3
    if tr[o + 1] == p.c then
      local ax, ay = tr[o + 2], tr[o + 3]
      local d = sqrt((ax - p.wx) ^ 2 + (ay - p.wy) ^ 2)
      if d < best then best = d end
      if k < j and tr[o + 4] == p.c then
        local sx, sy = tr[o + 5] - ax, tr[o + 6] - ay
        local len = sx * sx + sy * sy
        local f = len > 0 and ((p.wx - ax) * sx + (p.wy - ay) * sy) / len or -1
        if f > 0 and f < 1 then
          d = sqrt((ax + f * sx - p.wx) ^ 2 + (ay + f * sy - p.wy) ^ 2)
          if d < best then best = d end
        end
      end
    end
  end
  return best
end

-- the boat, zeppelin or portal leg of D.LINK this jump is (Travel.lua learns those under their own keys): from one of
-- its ends to the other (the portal's), or, on a ride, where the client loads the far side. That is out at sea, 770 to
-- 1,100 yards from either pier (Data.lua's tracks), where the track changes continent or jumps SWITCH_YD or more: the
-- jump starts within LINK_YD of the track's last two stretches into that point and ends within LINK_YD of its first two
-- out of it (the boat sails on while the far side loads)
local SWITCH_YD = 2000
local function linkLeg(a, b)
  for _, l in ipairs(QB.Data.LINK or {}) do
    for from = 1, 2 do
      local e1, e2 = l[from == 1 and 4 or 5], l[from == 1 and 5 or 4]
      if a.c == e1[1] and b.c == e2[1] and yd(a, { c = e1[1], wx = e1[2], wy = e1[3] }) <= LINK_YD
        and yd(b, { c = e2[1], wx = e2[2], wy = e2[3] }) <= LINK_YD then return l end
    end
    local tr = trackOf(l)
    local n = #tr / 3
    for i = 1, n - 1 do
      local o = (i - 1) * 3
      if tr[o + 1] ~= tr[o + 4] or (tr[o + 2] - tr[o + 5]) ^ 2 + (tr[o + 3] - tr[o + 6]) ^ 2 >= SWITCH_YD * SWITCH_YD then
        if nearStretch(a, tr, i - 2, i) <= LINK_YD and nearStretch(b, tr, i + 1, math.min(i + 3, n)) <= LINK_YD then return l end
      end
    end
  end
  return nil
end
Finds.LinkLeg = linkLeg

local function crossKey(a, b) return string.format("x:%d:%d,%d>%d:%d,%d", a.m, a.x, a.y, b.m, b.x, b.y) end
local function parseCross(k)
  local m1, x1, y1, m2, x2, y2 = k:match("^x:(%d+):(%d+),(%d+)>(%d+):(%d+),(%d+)$")
  if not m1 then return nil end
  return tonumber(m1), tonumber(x1), tonumber(y1), tonumber(m2), tonumber(x2), tonumber(y2)
end
Finds.ParseCross = parseCross

-- disc.rides, made when missing
local function rides()
  local d = QB.Discover.DB()
  if type(d.rides) ~= "table" then d.rides = {} end
  return d.rides
end

-- the crossings kept, oldest out past CROSSINGS (Travel's D.LINK legs never count)
local function capCrossings(all)
  local n = 0
  for k in pairs(all) do if k:sub(1, 2) == "x:" then n = n + 1 end end
  while n > CROSSINGS do
    local old, when
    for k, e in pairs(all) do
      if k:sub(1, 2) == "x:" then
        local w = type(e) == "table" and tonumber(e.at) or 0
        if not when or w < when or (w == when and k < old) then old, when = k, w end
      end
    end
    all[old] = nil
    n = n - 1
  end
end
Finds.CapCrossings = capCrossings

-- one crossing, a = { m, x, y, c, wx, wy } where it started, b where you came out, secs between
function Finds.NoteCrossing(a, b, secs)
  local all = rides()
  local near = QB.Discover.OS_NEAR
  local key
  for k in pairs(all) do
    local m1, x1, y1, m2, x2, y2 = parseCross(k)
    if m1 and m1 == a.m and m2 == b.m and (x1 - a.x) ^ 2 + (y1 - a.y) ^ 2 <= near * near
      and (x2 - b.x) ^ 2 + (y2 - b.y) ^ 2 <= near * near then key = k; break end
  end
  key = key or crossKey(a, b)
  local e = all[key]
  if type(e) ~= "table" or type(e.n) ~= "number" or type(e.t) ~= "number" then e = { n = 0 }; all[key] = e end
  local n = math.min(e.n, MEAN - 1)
  e.t = floor(((e.t or secs) * n + secs) / (n + 1) + 0.5)
  e.n = e.n + 1
  e.b = { a.c, floor(a.wx + 0.5), floor(a.wy + 0.5) }
  e.l = { b.c, floor(b.wx + 0.5), floor(b.wy + 0.5) }
  e.at = minutes()
  local fac = QB.faction or (QB.API and QB.API.Faction and QB.API.Faction())
  if fac == "A" or fac == "H" then e.f = fac end
  capCrossings(all)
  diag("xk")
  return key
end

-- where you stand as the crossings read it: { m, x, y, c, wx, wy } (into the table given, or a new one), or nil
local function spotOf(me, into)
  local m, x, y = QB.Discover.Spot()
  if not m then return nil end
  local s = into or {}
  s.m, s.x, s.y, s.c, s.wx, s.wy = m, x, y, me.c, me.wx, me.wy
  return s
end

-- one look (a second apart): the stand you are in, and a jump from the last look. (Its tables are kept and filled
-- again, look after look: a table a stand is all it makes)
local here, anchor, lastAt, lastSpot = {}, { t = -1 }, {}, {}
function Finds.Look()
  local t = now()
  if dead() or onTaxi() or inside() or not Finds.On() then
    cross.last, cross.anchor, cross.still, cross.tele = nil, nil, nil, false
    return
  end
  local me = QB.API.WorldPosition(nil, here)
  if not me then return end -- (no position: the tram, a loading screen; the next look with one decides)
  local last = cross.last
  if last and (me.c ~= last.c or yd(me, last) > JUMP) then
    local st = cross.still
    local teleport = cross.tele or teleporting(t)
    cross.last, cross.anchor, cross.still, cross.tele = nil, nil, nil, false
    if teleport then diag("xt"); return end
    local from
    if st and t - st.to <= BEFORE_S and yd(st, last) <= BEFORE_YD then from = st else from = last.spot end
    local to = spotOf(me)
    if not (from and to) or Finds.Held() then return end
    if linkLeg(from, to) then diag("xl"); return end
    Finds.NoteCrossing(from, to, max(1, floor(t - (from == st and st.to or last.t) + 0.5)))
    return
  end
  if cross.back then cross.tele, cross.back = false, false end -- (back in the world, and no jump: no teleport)
  -- the stand: within STILL_YD of where it began for STILL_S seconds; its spot read once, when it becomes one
  local an = cross.anchor
  if an and yd(me, an) <= STILL_YD then
    if t - an.t >= STILL_S then
      local st = cross.still
      if st and st.from == an.t then
        st.to = t
      else
        local s = spotOf(me)
        if s then s.from, s.to = an.t, t; cross.still = s end
      end
    end
  else
    anchor.c, anchor.wx, anchor.wy, anchor.t = me.c, me.wx, me.wy, t
    cross.anchor = anchor
  end
  -- the last place, and its spot (read again once you moved from it), for a crossing with no stand before it
  lastAt.c, lastAt.wx, lastAt.wy, lastAt.t = me.c, me.wx, me.wy, t
  if not (last and last.spot and yd(last.spot, me) <= STILL_YD) then lastAt.spot = spotOf(me, lastSpot) end
  cross.last = lastAt
end

----------------------------------------------------------------------------
-- flights: Travel.lua's measured flight, for every character's file (Travel keeps the character's own)
----------------------------------------------------------------------------
function Finds.Flown(key, secs)
  secs = num(secs)
  if type(key) ~= "string" or not key:find("^%d+>%d+$") or not secs or secs <= 0 or not Finds.On() then return end
  local d = QB.Discover.DB()
  if type(d.flown) ~= "table" then d.flown = {} end
  local L = QB.Legacy
  local ff = (L and L.Rank and L.NODE) and L.Rank(L.NODE.FLIER) or 0
  local e = d.flown[key]
  -- a flight at another Frequent Flier rank starts the mean over
  if type(e) ~= "table" or type(e.n) ~= "number" or type(e.secs) ~= "number" or e.ff ~= ff then e = { n = 0, ff = ff }; d.flown[key] = e end
  local n = math.min(e.n, MEAN - 1)
  e.secs = floor(((e.n > 0 and e.secs or secs) * n + secs) / (n + 1) + 0.5)
  e.n = e.n + 1
end

----------------------------------------------------------------------------
-- the work a quest took: Timer.lua keeps it per character (chars[key].timer.quests, never uploaded: the allow-list
-- leaves chars out), so each completion measured in QSAMPLE_K looks or more is copied here with no character and no
-- time of day: disc.qtime[questId] = { w, k, lv, w, k, lv, ... }, three numbers a completion (seconds of work in
-- tenths, looks, level; QSAMPLES a quest, the newest kept; QTIMES quests, the one completed longest ago out), flat so
-- 600 quests cost one table each. probe_pull.py merges them as disc.json "dur"
----------------------------------------------------------------------------
local QSAMPLE_K, QSAMPLE_MAX, QSAMPLES, QTIMES = 3, 4 * 3600, 4, 600
Finds.QTIMES = QTIMES
function Finds.QuestDone(id)
  id = num(id)
  local T = QB.Timer
  if not (id and T and T.DB) then return end
  local q = T.DB().quests[id]
  local w, k = type(q) == "table" and num(q.w), type(q) == "table" and num(q.k)
  if not (w and k) or k < QSAMPLE_K or w <= 0 or w > QSAMPLE_MAX then return end
  -- (complete just now: Timer.Done keeps the first completion, and a quest complete again later is no new sample)
  local c = num(q.c)
  if not (c and type(time) == "function" and math.abs(time() - c) <= 2) then return end
  local d = QB.Discover.DB()
  if type(d.qtime) ~= "table" then d.qtime = {} end
  if type(d.qtimeAt) ~= "table" then d.qtimeAt = {} end
  local all = d.qtime
  local list = all[id]
  if type(list) ~= "table" then
    list = {}
    all[id] = list
    local n = 0
    for _ in pairs(all) do n = n + 1 end
    while n > QTIMES do
      local old, when
      for qid in pairs(all) do
        local t = tonumber(d.qtimeAt[qid]) or 0
        if qid ~= id and (not when or t < when or (t == when and qid < old)) then old, when = qid, t end
      end
      all[old], d.qtimeAt[old] = nil, nil
      n = n - 1
    end
  end
  local n = #list
  list[n + 1], list[n + 2], list[n + 3] = floor(w * 10 + 0.5) / 10, k, num(q.lv) or 0
  while #list > QSAMPLES * 3 do for _ = 1, 3 do table.remove(list, 1) end end
  d.qtimeN = (tonumber(d.qtimeN) or 0) + 1
  d.qtimeAt[id] = d.qtimeN
end

----------------------------------------------------------------------------
-- QuestBank_Finds, the uploader's data addon: rows the site merged (two files that agree), written by the uploader as
-- numbers and short titles only. Added under D.FIND at login where Data.lua has no row for the same find
----------------------------------------------------------------------------
local KIND = { b = true, k = true, h = true, r = true }
-- a find's identity on its map: the object or creature, or for a guide's place with no object (id 0) its title or key
local function identity(kind, id, extra) return kind .. ":" .. (id ~= 0 and tostring(id) or tostring(extra)) end
Finds.Identity = identity
-- a book's title or a locked object's key: what a guide's place (id 0) of it is known by, or nil
local function named(kind, extra) return (kind == "b" or kind == "k") and kind .. ":" .. tostring(extra) or nil end

-- one row of the data file, checked: { map, kind, id, spots "x,y;x,y", votes, extra } with every field in range;
-- false for anything else
local function goodRow(r)
  if type(r) ~= "table" then return false end
  local m, kind, id, spots, votes, extra = r[1], r[2], r[3], r[4], r[5], r[6]
  if type(m) ~= "number" or m < 1 or m > 99999 or m ~= floor(m) then return false end
  if not KIND[kind] or type(id) ~= "number" or id < 0 or id > 99999999 or id ~= floor(id) then return false end
  if type(votes) ~= "number" or votes < 0 or votes > 9999 then return false end
  if type(spots) ~= "string" or #spots > 64 or not spots:find("^%d+,%d+[;%d,]*$") then return false end
  if kind == "b" then return type(extra) == "string" and #extra > 0 and #extra <= 60 and not extra:find("[|%c]") end
  if kind == "h" then return type(extra) == "string" and extra:find("^%d+%.%d+$") ~= nil end
  return type(extra) == "number" and extra >= 0 and extra <= 99999999
end
Finds.GoodRow = goodRow

-- the data file's rows into D.FIND (source "f"), never over a row Data.lua has (the same object, or the guides' place
-- of the same book or key); its stamp is Finds.dataAt. Returns the rows added
function Finds.LoadData()
  local F = _G and _G.QuestBank_Finds or QuestBank_Finds
  local D = QB.Data
  if type(F) ~= "table" or F.v ~= 1 or type(F.rows) ~= "table" then return 0 end
  D.FIND = type(D.FIND) == "table" and D.FIND or {}
  -- (Data.lua's rows by their object, and its guides' places by title or key too, as gen_data.py's find_rows: a file
  -- row of the same book or the same key's lock is that find, never a second row beside it)
  local have, guide = {}, {}
  for m, rows in pairs(D.FIND) do
    for _, r in ipairs(rows) do
      have[m .. ":" .. identity(r[1], r[2], r[5])] = true
      local n = r[2] == 0 and named(r[1], r[5])
      if n then guide[m .. ":" .. n] = true end
    end
  end
  local added = 0
  for i = 1, math.min(#F.rows, 5000) do
    local r = F.rows[i]
    if goodRow(r) then
      local k, n = r[1] .. ":" .. identity(r[2], r[3], r[6]), named(r[2], r[6])
      if not have[k] and not (n and guide[r[1] .. ":" .. n]) then
        have[k] = true
        D.FIND[r[1]] = D.FIND[r[1]] or {}
        local list = D.FIND[r[1]]
        list[#list + 1] = { r[2], r[3], r[4], r[5], r[6], "f" }
        added = added + 1
      end
    end
  end
  Finds.dataAt = type(F.at) == "number" and F.at or 0
  return added
end

----------------------------------------------------------------------------
-- the Settings box unticked (Game.SetOn): what was noted goes, since the saved file is uploaded whole
----------------------------------------------------------------------------
function Finds.Clear()
  local d = QuestBankDB and QuestBankDB.disc
  if type(d) ~= "table" then return end
  d.find, d.findAt, d.findN, d.flown = nil, nil, nil, nil
  if type(d.rides) == "table" then
    for k in pairs(d.rides) do if k:sub(1, 2) == "x:" then d.rides[k] = nil end end
  end
  rareSeen = {}
end

-- how much is noted, for /qb discoveries: objects (and items read), rares, crossings
function Finds.Count()
  local d = QuestBankDB and QuestBankDB.disc
  local no, nr, nx = 0, 0, 0
  for k in pairs(type(d) == "table" and type(d.find) == "table" and d.find or {}) do
    if k:sub(1, 1) == "c" then nr = nr + 1 else no = no + 1 end
  end
  for k in pairs(type(d) == "table" and type(d.rides) == "table" and d.rides or {}) do
    if k:sub(1, 2) == "x:" then nx = nx + 1 end
  end
  return no, nr, nx
end

function Finds.OnEvent(event, a1, a2, a3)
  if event == "ADDON_RESTRICTION_STATE_CHANGED" then
    local t, state = num(a1), num(a2)
    if t then held[t] = (state and state ~= 0) or nil end
  elseif event == "LOOT_OPENED" then
    Finds.LootOpened(a2)
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    if plain(a1) ~= "player" then return end
    local spell = num(a3)
    if spell == 8690 or spell == 556 or (spell and IsPlayerSpell and plain(IsPlayerSpell(spell)) == true) then Finds.Teleported() end
    Finds.Cast(spell)
  elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
    local key = QB.Discover.Key(plain(a2))
    if key and key:sub(1, 1) == "o" then soft = { key = key, at = now() } end
  elseif event == "ITEM_TEXT_BEGIN" then
    Finds.TextBegin()
  elseif event == "ITEM_TEXT_READY" then
    Finds.TextReady()
  elseif event == "ITEM_TEXT_CLOSED" then
    reading = nil
  elseif event == "NAME_PLATE_UNIT_ADDED" then
    Finds.Plate(a1)
  elseif event == "CONFIRM_SUMMON" then
    Finds.Summoned()
  elseif event == "LOADING_SCREEN_ENABLED" or event == "PLAYER_LEAVING_WORLD" then
    Finds.Loading()
  elseif event == "PLAYER_ENTERING_WORLD" then
    opening, soft = nil, nil
    if cross.tele then cross.back = true end
  end
end

-- (from Discover's Init, at login or when a host loads the engine after it): the token, the data file, and on the
-- Forever client the events and a look a second
function Finds:Init()
  if self.frame then return end
  local f = CreateFrame("Frame")
  self.frame = f
  QB.Try("finds: token", Finds.Token)
  QB.Try("finds: data file", Finds.LoadData)
  -- the Settings box unticked clears these with the loot notes
  local G = QB.Game
  if G and type(G.SetOn) == "function" and not G.findsHooked then
    G.findsHooked = true
    local setOn = G.SetOn
    G.SetOn = function(yes, ...)
      local r = setOn(yes, ...)
      if not yes and G.Forever() then Finds.Clear() end
      return r
    end
  end
  if not (G and G.Forever()) then return end -- Classic Era: nothing to note, as Loot.lua
  f:SetScript("OnEvent", QB.Safe(function(_, event, ...) Finds.OnEvent(event, ...) end, "finds"))
  for _, e in ipairs({ "ADDON_RESTRICTION_STATE_CHANGED", "LOOT_OPENED", "PLAYER_SOFT_INTERACT_CHANGED", "ITEM_TEXT_BEGIN",
                       "ITEM_TEXT_READY", "ITEM_TEXT_CLOSED",
                       "NAME_PLATE_UNIT_ADDED", "CONFIRM_SUMMON", "PLAYER_ENTERING_WORLD", "LOADING_SCREEN_ENABLED",
                       "PLAYER_LEAVING_WORLD" }) do
    pcall(f.RegisterEvent, f, e)
  end
  if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_SUCCEEDED", "player") else pcall(f.RegisterEvent, f, "UNIT_SPELLCAST_SUCCEEDED") end
  f.elapsed = 0
  f:SetScript("OnUpdate", QB.Safe(function(self, dt)
    self.elapsed = self.elapsed + (dt or 0)
    if self.elapsed < TICK then return end
    self.elapsed = 0
    Finds.Look()
  end, "finds: crossings"))
end
