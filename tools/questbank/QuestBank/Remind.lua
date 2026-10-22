-- SPDX-License-Identifier: GPL-3.0-or-later
-- Reminders (the hud round): one quiet place for what is worth a moment out of a fight, the same engine for QuestBank
-- and Cute (Cute_Quest's copy, through the flags its Bridge.lua sets). Two pieces in one holder:
--   Reminders  QuestBankCampBar (remind.pos, default CENTER 0 -190): the camp (sit, place, the fire slot, eat, sleep),
--              upkeep (repair, bags, ammo, hearth, use, buy), class (talents), and the step frame's line while the
--              step frame is off. Six at most, in a fixed order; a status in BAD always takes a slot
--   Buffs      QuestBankBuffBanner (remind.bannerPos; nil: 8 px above Reminders): your buffs, your party's, and
--              "Before the pull" on a ready check or entering a raid
-- and the step frame's one line (Remind.Step: Train, Flight path, Sleeping bag), which StepFrame.lua draws.
-- Every reminder is a provider: { key, piece, order, row, cat, groups, read = function(add, ctx) }, read calling add()
-- for each icon it shows and filling the reused record add() hands it. Camp.lua registers the camp and buff ones,
-- Guide.lua Train and Flight path, this file upkeep, talents and Before the pull. Adding a reminder is one provider and
-- its row in Remind.ROWS.
-- The look (pattern D): a 32 px game icon, cropped, a 1 px black edge, the cooldown's sweep, a count at its bottom right;
-- under it a 2 px bar in its category's colour (buffs WHITE, XP QUEST, group GROUP; none for upkeep and class) and one
-- word (the verb, or the minutes; a status word in WARN or BAD). Lit: a left-click acts now, through the game's secure
-- button (type1: an unmodified left click alone, SecureTemplates.lua:8-9, so a right-click never casts and Alt-drag
-- stays free). Waiting: desaturated; a left-click puts its place on the arrow. Right-click anywhere: Not now (the piece,
-- ten minutes), Never: <the reminder> (account-wide, undone under its row in Settings), Settings.
-- The rules: nothing in a fight (the game's state driver hides the holder; no read while InCombatLockdown, while the
-- client keeps auras secret, C_Secrets.ShouldAurasBeSecret, SecretPredicateAPIDocumentation.lua:119, or while
-- C_RestrictedActions says Combat or Encounter), back 2 s after it; never a chat line (the only one is the reply to
-- /qb buffs); not while dead, on a taxi, in a vehicle or a cinematic; inside a dungeon or raid what remind.instance says.
-- Event-driven: events set a group's dirty bit, one refresh on the next frame reads the dirty groups' providers. A 1 s
-- clock runs only while a word changes as time or you go (a countdown, minutes away) or a party row can show.
local _, QB = ...
if QB.dormant then return end
local R = { list = {}, byKey = {}, refreshes = 0, layouts = 0 }
QB.Remind = R

local plain = QB.Plain
local function now() return GetTime and GetTime() or 0 end
local function yes(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, v = pcall(fn, ...)
  return ok and plain(v) == true
end
R.Yes = yes

local SIZE, GAP = 32, 6            -- an icon, and the room between two
local COL = SIZE + GAP             -- a word's width: an icon and its gap, so a word never reaches its neighbour's
local PADX, PADT, PADB = 14, 4, 9  -- the pieces' room round their icons (no backdrop: the words keep inside it)
local WORD_Y = SIZE + 6            -- the word's top under the icon: 2 px, the bar, 2 px
local ROW_H = WORD_Y + 13          -- an icon with its bar and word
local MEMBER = 76                  -- a party member's column: the icon, the name under it
local TITLE_H = 18                 -- Buffs' title
local MAX, MAX_BUFFS, MAX_MEMBERS = 6, 6, 4
local SNOOZE = 600                 -- Not now
local AFTER = 2                    -- seconds after a fight before the pieces come back
local FADE = 0.2
R.SIZE, R.GAP, R.MAX, R.MAX_BUFFS, R.MAX_MEMBERS, R.SNOOZE, R.AFTER = SIZE, GAP, MAX, MAX_BUFFS, MAX_MEMBERS, SNOOZE, AFTER

-- the windows palette (the windows design's section 8): text greys, the status words' colours, the category bars'
local C = {
  WHITE = { 0.96, 0.96, 0.96 }, INK = { 0.86, 0.86, 0.86 }, DIM = { 0.58, 0.58, 0.58 },
  WARN = { 0.93, 0.74, 0.35 }, BAD = { 0.88, 0.36, 0.33 },
  QUEST = { 1, 0.82, 0 }, GROUP = { 0.31, 0.82, 0.77 },
}
R.COLORS = C
local BAR = { buffs = C.WHITE, xp = C.QUEST, group = C.GROUP }

----------------------------------------------------------------------------
-- settings: QB:Settings().remind, account-wide. 6.1.1's per-icon switches become Nevers, the bar's switch remind.on
----------------------------------------------------------------------------
local DEFAULT = { on = true, buffs = true, party = true, camp = true, upkeep = true, class = true, instance = "buffs" }
local OLD_NEVER = { food = "eat", fire = "fire", camp = "place", bag = "sleep", sit = "sit", wood = "wood", bagChain = "bagchain" }
local OLD_NAME = { eat = "Eat", fire = "Fire", place = "Place", sleep = "Sleep", sit = "Sit", wood = "Wood", bagchain = "Sleeping bag quests" }
local NEVER_MAX = 32
-- 6.1.1's settings, once: campBar false is remind.on false; each per-icon switch left false is its Never; quietInstance
-- false is "Everything" in dungeons and raids. Never is account-wide like the switches it replaces
function R.Migrate(s, r)
  r.v = 2
  if type(r.never) ~= "table" then r.never = {} end
  if s.campBar == false then r.on = false end
  for old, key in pairs(OLD_NEVER) do
    if r[old] == false then r.never[key] = OLD_NAME[key] end
  end
  if r.instance == nil then r.instance = r.quietInstance == false and "all" or "buffs" end
  r.food, r.fire, r.bag, r.sit, r.wood, r.bagChain, r.quietInstance = nil, nil, nil, nil, nil, nil, nil
  r.camp = true -- (6.1.1's camp was the features' icon; now the row: camp, food and the sleeping bag)
end
function R.Settings()
  local s = QB:Settings()
  local r = s.remind
  if type(r) ~= "table" then r = {}; s.remind = r end
  if r.v ~= 2 then R.Migrate(s, r) end
  for k, v in pairs(DEFAULT) do if r[k] == nil then r[k] = v end end
  if type(r.never) ~= "table" then r.never = {} end
  -- (6.x's name for remind.on, kept equal for whatever reads it: Cute's first-run card)
  if s.campBar ~= r.on then s.campBar = r.on end
  return r
end
local set -- (the settings for one refresh)

-- the rows of Settings > Reminders, the same in QuestBank and in Cute (each draws its own): key, words, a note; the
-- sixth a choice. The interact light's two rows follow in each host's section (Glow.lua)
R.ROWS = {
  { key = "buffs", label = "Your buffs and weapon" },
  { key = "party", label = "Party members' buffs", note = "In a party, not a raid. Thorns only on the tank." },
  { key = "camp", label = "Camp, food and sleeping bag", note = "Each adds XP on Forever. The sleeping bag's quest line too." },
  { key = "upkeep", label = "Repair, bags and items to use", note = "Ammo and the hearthstone with them." },
  { key = "class", label = "Training, talents and flight paths" },
  { key = "instance", label = "In dungeons and raids", note = "Buffs and consumables: between pulls and on a ready check.",
    choice = { { "Buffs and consumables", "buffs" }, { "Everything", "all" }, { "Nothing", "none" } } },
}
R.ON_LABEL, R.ON_NOTE = "Reminders on screen", "Reminders and Buffs. Hidden in a fight."
-- a row's switch, from Settings: on or off, or the choice's value; the pieces again
function R.SetRow(key, v)
  local r = R.Settings()
  r[key] = v
  R.Dirty("all")
end
-- the row a Never key belongs to: its provider's, else by its kind (buff:<id> and an elixir's group, flask:<id>, your
-- buffs, the row Before the pull reads; use:<id> upkeep), so the row's Show brings every one back
local ROW_OF = { weapon = "buffs", party = "party", wood = "camp", cook = "camp", bagchain = "camp" }
function R.RowOf(key)
  if type(key) ~= "string" then return nil end
  if key:find("^buff:") or key:find("^flask:") then return "buffs" end
  if key:find("^use:") then return "upkeep" end
  local p = R.byKey[key]
  return (p and p.row) or ROW_OF[key]
end
-- what a row keeps hidden for good: { { key, name }, ... }, a list made when Settings asks
function R.Hidden(row)
  local out = {}
  for key, name in pairs(R.Settings().never) do
    if R.RowOf(key) == row then out[#out + 1] = { key, type(name) == "string" and name or key } end
  end
  table.sort(out, function(a, b) return a[2] < b[2] end)
  return out
end
function R.Never(key) return set and set.never[key] ~= nil or R.Settings().never[key] ~= nil end
-- Never for a reminder (name: its words, "Frost Armor"), or shown again (on false); 32 kept at most
function R.SetNever(key, name, on)
  if key == "party" then R.SetRow("party", on == false) return true end -- (Never on a member's icon: the party row off)
  local never = R.Settings().never
  if on == false then never[key] = nil
  else
    local n = 0
    for _ in pairs(never) do n = n + 1 end
    if n >= NEVER_MAX and never[key] == nil then return false end
    never[key] = name or key
  end
  R.Dirty("all")
  return true
end

----------------------------------------------------------------------------
-- providers and their records
----------------------------------------------------------------------------
R.GROUPS = { "buffs", "party", "camp", "upkeep", "class", "away", "pull" }
local dirty, pending = {}, false
local all = { all = true }
local flushNow
-- a provider (see the head of this file); order: its place within its piece; groups: the event groups whose events
-- make it read again; row: its Settings row (off: never read); cat: its bar ("buffs", "xp", "group" or none)
function R.Add(p)
  assert(type(p) == "table" and type(p.key) == "string" and type(p.read) == "function", "a provider: key and read")
  if R.byKey[p.key] then return R.byKey[p.key] end
  p.recs, p.n, p.order = {}, 0, p.order or 1000
  p.safeRead = QB.Safe(p.read, "reminders: " .. p.key) -- (one wrapper, no garbage a call; a provider's error stops it alone)
  R.byKey[p.key] = p
  R.list[#R.list + 1] = p
  table.sort(R.list, function(a, b) return a.order < b.order end)
  for _, g in ipairs(p.groups or {}) do dirty[g] = true end
  return p
end
-- events set their group's bit; the refresh runs on the next frame, once for a burst
local flushNext = QB.Safe(function() pending = false; flushNow() end, "reminders") -- (one wrapper: no garbage a call)
function R.Dirty(group)
  dirty[group or "all"] = true
  if pending then return end
  pending = true
  if C_Timer and C_Timer.After then C_Timer.After(0, flushNext)
  else pending = false; flushNow() end
end
-- a record for the provider being read: the next of its own, wiped
local reading
local function add()
  local p = reading
  p.n = p.n + 1
  local rec = p.recs[p.n]
  if not rec then rec = {}; p.recs[p.n] = rec end
  for k in pairs(rec) do if k ~= "clickBuf" then rec[k] = nil end end
  rec.p = p
  rec.key = p.key
  rec.cat = p.cat
  return rec
end
R.NewRecord = add
-- a record's click: the secure type and what it reads (a spell, an item by id, a macro's text, a button to click),
-- the unit and the target slot; one table a record, kept
function R.Click(rec, kind, value, unit, slot)
  local c = rec.clickBuf
  if not c then c = {}; rec.clickBuf = c end
  c.type, c.spell, c.item, c.macro, c.button, c.unit, c.slot = kind, nil, nil, nil, nil, unit, slot
  if kind == "spell" then c.spell = value elseif kind == "item" then c.item = value elseif kind == "macro" then c.macro = value else c.button = value end
  rec.click = c
  return c
end

----------------------------------------------------------------------------
-- what the game says of you, read once a refresh
----------------------------------------------------------------------------
local ctx = { me = nil }
local hereBuf = {}
local function fighting() return InCombatLockdown and InCombatLockdown() or false end
-- the client's restrictions as in a fight (C_RestrictedActions, Combat and Encounter: Pins.lua's own check)
local RESTRICT = { "Combat", "Encounter" }
local function restricted()
  local RA, kinds = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
  if not (RA and type(RA.IsAddOnRestrictionActive) == "function" and kinds) then return false end
  for _, name in ipairs(RESTRICT) do
    local kind = kinds[name]
    if kind ~= nil and yes(RA.IsAddOnRestrictionActive, kind) then return true end
  end
  return false
end
local function aurasSecret()
  local S = C_Secrets
  return S ~= nil and type(S.ShouldAurasBeSecret) == "function" and yes(S.ShouldAurasBeSecret)
end
R.AurasSecret = aurasSecret
-- no read at all: a fight, the client's restrictions, auras kept secret
function R.Blocked() return fighting() or restricted() or aurasSecret() end
local inCinematic = false
local function away()
  return yes(UnitIsDeadOrGhost, "player") or yes(UnitOnTaxi, "player") or yes(UnitInVehicle, "player")
    or yes(UnitHasVehicleUI, "player") or inCinematic
end
-- the instance you are in: "party", "raid" or nil
local function instanceKind()
  if type(IsInInstance) ~= "function" then return nil end
  local ok, inside, kind = pcall(IsInInstance)
  if not ok or plain(inside) ~= true then return nil end
  kind = plain(kind)
  return kind == "raid" and "raid" or "party"
end
R.InstanceKind = instanceKind
local function resting() return yes(IsResting) end
-- the minutes from you to a place ({ c, wx, wy }): by your flight paths and boats where the arrow's router knows the way,
-- else on foot as the crow flies; nil off your land
local reachFor, reachR = nil, nil -- (the router's reach from you, once a refresh)
local optsBuf, optsAt = nil, 0
function R.Minutes(me, p)
  if not (me and p and p.c == me.c and type(p.wx) == "number" and type(p.wy) == "number") then return nil end
  local TV, m = QB.Travel, nil
  if TV and TV.Reach and TV.Via then
    if reachFor ~= R.refreshes or reachR == nil then
      -- (the router's options, made again every 10 s: mounted or not, the hearthstone's readiness)
      local t = now()
      if not optsBuf or t - optsAt > 10 then optsBuf, optsAt = TV.Opts("pin"), t end
      local okR, Rt = pcall(TV.Reach, me, optsBuf)
      reachFor, reachR = R.refreshes, okR and Rt or false
    end
    if reachR then local okV, v = pcall(TV.Via, reachR, p); if okV then m = v end end
  end
  if not m or m == math.huge then m = math.sqrt((p.wx - me.wx) ^ 2 + (p.wy - me.wy) ^ 2) * QB.Model.DETOUR / QB.Model.RUN / 60 end
  return m
end
-- "4 min" for minutes (at least 1), the same string while the number stands: one string a number, kept
local minWords = {}
function R.MinWord(m)
  local n = math.max(1, math.floor((m or 0) + 0.5))
  local w = minWords[n]
  if not w then w = n .. " min"; if n <= 60 then minWords[n] = w end end
  return w
end
ctx.Minutes = R.Minutes
R.ctx = ctx

-- your bags: { [item id] = true } of what bags 0 to NUM_BAG_SLOTS hold, by C_Container.GetContainerItemID (no table a
-- slot), scanned again 0.5 s after BAG_UPDATE_DELAYED (one scan for a burst) and at every full refresh. An item met for
-- the first time is looked at once for Use (R.UseKind, its tooltip read once: 200 kept)
local bags, bagsStale, bagSoon = {}, true, false
local useKind, useN = {}, 0
local function classify(bag, slot, id)
  if useKind[id] ~= nil then return end
  if useN >= 200 then for k in pairs(useKind) do useKind[k] = nil end; useN = 0 end
  useN = useN + 1
  local kind = false
  local CC = C_Container
  if CC and type(CC.GetContainerItemQuestInfo) == "function" then
    -- (a quest starter: the client's own word on the item in that slot, ContainerDocumentation.lua's ItemQuestInfo)
    local ok, q = pcall(CC.GetContainerItemQuestInfo, bag, slot)
    local qid = ok and type(q) == "table" and plain(q.questID) or nil
    if type(qid) == "number" and qid > 0 then kind = "quest:" .. qid end
  end
  local TI = C_TooltipInfo
  if not kind and TI and type(TI.GetBagItem) == "function" then
    local ok, data = pcall(TI.GetBagItem, bag, slot)
    local lines = ok and type(data) == "table" and data.lines or nil
    local LT = Enum and Enum.TooltipDataLineType or {}
    local open, learn, err = false, false, false
    local OPEN = type(ITEM_OPENABLE) == "string" and ITEM_OPENABLE or "<Right Click to Open>"
    for _, l in ipairs(type(lines) == "table" and lines or {}) do
      local t, ty = plain(l.leftText), plain(l.type)
      if ty ~= nil and ty == LT.ErrorLine then err = true; R.Diag("errorLine", true) end
      if ty ~= nil and ty == LT.ItemSpellTriggerLearn then learn = true end
      if t == OPEN then open = true end
    end
    if err then kind = false
    elseif open then kind = "open"
    elseif learn and C_Item and type(C_Item.IsUsableItem) == "function" and yes(C_Item.IsUsableItem, id) then kind = "learn" end
  end
  useKind[id] = kind
end
function R.UseKind(id) return useKind[id] end
-- (a spell learned or a box unlocked: what Use knows is looked at again)
function R.ForgetUse() for k in pairs(useKind) do useKind[k] = nil end; useN = 0; bagsStale = true end
function R.Bags()
  if not bagsStale then return bags end
  bagsStale = false
  for k in pairs(bags) do bags[k] = nil end
  local CC = C_Container
  if not (CC and type(CC.GetContainerNumSlots) == "function" and type(CC.GetContainerItemID) == "function") then return bags end
  for bag = 0, (type(NUM_BAG_SLOTS) == "number" and NUM_BAG_SLOTS or 4) do
    local ok, n = pcall(CC.GetContainerNumSlots, bag)
    n = ok and plain(n) or 0
    for slot = 1, math.min(type(n) == "number" and n or 0, 40) do
      local okI, id = pcall(CC.GetContainerItemID, bag, slot)
      id = okI and plain(id) or nil
      if type(id) == "number" then
        bags[id] = true
        classify(bag, slot, id)
      end
    end
  end
  return bags
end
function R.BagsChanged() bagsStale = true end

----------------------------------------------------------------------------
-- stillness: standing still 20 s (PLAYER_STOPPED_MOVING arms it, PLAYER_STARTED_MOVING disarms), for the pause
-- reminders (the fire slot, Sleep). One that showed and that you walk away from without clicking snoozes itself
----------------------------------------------------------------------------
local STILL = 20
R.STILL = STILL
local stillGen, stillAt = 0, nil
R.still = false
local paused = {} -- [key] = shown while still, waiting to snooze if you walk off
function R.Stopped()
  stillGen = stillGen + 1
  local gen = stillGen
  stillAt = now()
  if C_Timer and C_Timer.After then
    C_Timer.After(STILL, QB.Safe(function()
      if gen ~= stillGen then return end
      R.still = true
      R.Dirty("camp")
    end, "reminders: still"))
  end
end
local keySnooze = {} -- [key] = until (GetTime)
-- (the hud review) Talents' and Train's Not now: until a level, kept on this character across a reload and a login
-- (QuestBankDB.chars[me].remind.untilLevel[key] = the level it ends at); the table read once a session
local levelNap
local function untilLevelDB()
  if levelNap then return levelNap end
  local c = QB.Camp and QB.Camp.CharDB and QB.Camp.CharDB()
  if not c then return nil end
  if type(c.untilLevel) ~= "table" then c.untilLevel = {} end
  levelNap = c.untilLevel
  return levelNap
end
function R.Started()
  stillGen = stillGen + 1
  stillAt = nil
  if R.still then
    R.still = false
    local t = now()
    for key in pairs(paused) do keySnooze[key] = t + SNOOZE; paused[key] = nil end
    R.Dirty("camp")
  end
end
function R.StillFor() return stillAt and (now() - stillAt) or 0 end
-- a reminder snoozed by itself or by Not now on its own (Talents: until the next level)
function R.Snoozed(key)
  local v = keySnooze[key]
  if v ~= nil then
    if now() < v then return true end
    keySnooze[key] = nil
  end
  local nap = levelNap or untilLevelDB()
  local lv = nap and nap[key]
  if lv == nil then return false end
  if type(lv) == "number" and (QB.state and QB.state.level or 0) < lv then return true end
  nap[key] = nil
  return false
end
function R.SnoozeKey(key, untilLevel)
  local nap = untilLevel and untilLevelDB()
  if nap then nap[key] = untilLevel else keySnooze[key] = now() + SNOOZE end
  R.Dirty("all")
end
-- a pause reminder (its record's pause): shown now, it snoozes when you walk off without its click (collect marks it)
function R.Clicked(key) paused[key] = nil end

----------------------------------------------------------------------------
-- the frames: the holder the game's state driver hides in a fight, and the two pieces in it
----------------------------------------------------------------------------
local holder, bar, banner
local driven = false
local icons, bicons, picons = {}, {}, {}
local FONT, FONT_FLAGS
local function font()
  if FONT then return FONT, FONT_FLAGS end
  local sk = QB.Skin
  if sk and sk.font then FONT = sk.font
  else
    local fo = GameFontNormal
    local path = fo and fo.GetFont and fo:GetFont()
    FONT = path or "Fonts\\FRIZQT__.TTF"
  end
  FONT_FLAGS = "OUTLINE"
  return FONT, FONT_FLAGS
end
local function text(parent, size, col, width)
  local t = parent:CreateFontString(nil, "OVERLAY")
  if GameFontNormal then t:SetFontObject(GameFontNormal) end
  local f, flags = font()
  t:SetFont(f, size, flags)
  if t.SetShadowOffset then t:SetShadowOffset(1, -1); t:SetShadowColor(0, 0, 0, 1) end
  t:SetTextColor(col[1], col[2], col[3])
  t:SetJustifyH("CENTER")
  t:SetWordWrap(false)
  if width then t:SetWidth(width) end
  return t
end

local function holderFrame()
  if holder then return holder end
  holder = CreateFrame("Frame", "QuestBankRemindHolder", UIParent)
  holder:SetSize(1, 1)
  holder:SetPoint("CENTER")
  -- (an addon may not hide a frame holding the game's secure buttons in a fight: the game's own state driver does,
  -- Blizzard_RestrictedAddOnEnvironment/SecureStateDriver.lua's RegisterStateDriver, "visibility")
  if type(RegisterStateDriver) == "function" then
    driven = pcall(RegisterStateDriver, holder, "visibility", "[combat] hide; show")
  end
  return holder
end
R.Holder = holderFrame

local function piece(name)
  local f = CreateFrame("Frame", name, holderFrame())
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetSize(SIZE + PADX * 2, PADT + ROW_H + PADB)
  f:Hide()
  return f
end
-- (the layout round) a piece's scale (remind.scale for Reminders, remind.bannerScale for Buffs: 0.5 to 2; none is
-- 100%, as before). The places are kept in UIParent's units, so a scale leaves the piece where it stands: its points
-- are set in its own units, the place divided by its scale
local function scaleOf(key)
  local v = tonumber(R.Settings()[key])
  if v and v >= 0.5 and v <= 2 then return v end
  return 1
end
local function ownScale(f, k) if f:GetScale() ~= k then f:SetScale(k) end end
-- where the pieces stand: Reminders by its centre (remind.pos, else CENTER 0 -190), growing both ways; Buffs by its
-- bottom (remind.bannerPos, else 8 px above Reminders), growing upward
local function placeBar()
  local f = bar
  local pos = R.Settings().pos
  local k = scaleOf("scale")
  ownScale(f, k)
  f:ClearAllPoints()
  if type(pos) == "table" and pos.x then f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x / k, pos.y / k) else f:SetPoint("CENTER", UIParent, "CENTER", 0, -190 / k) end
end
local function placeBanner()
  local f = banner
  local pos = R.Settings().bannerPos
  local k = scaleOf("bannerScale")
  ownScale(f, k)
  f:ClearAllPoints()
  if type(pos) == "table" and pos.x then f:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", pos.x / k, pos.y / k) else f:SetPoint("BOTTOM", bar, "TOP", 0, 8 / k) end
end
function R.Place()
  if fighting() then return end
  if bar then placeBar() end
  if banner then placeBanner() end
end
-- (the review round) the bar's top at its own place, down from the screen's top in UIParent's units, for the arrow,
-- which keeps above it (Arrow.lua, A.Place); nil once the bar was dragged elsewhere
function R.BarTop()
  local pos = R.Settings().pos
  if type(pos) == "table" and pos.x then return nil end
  -- (its icons' top: the piece is centred at 190 below the middle, its icons PADT under its own top, at its scale)
  local k = scaleOf("scale")
  return (UIParent:GetHeight() or 768) / 2 + 190 - (PADT + ROW_H + PADB) * k / 2 + PADT * k
end

-- (the layout round) a host's one lock for the on-screen pieces (QB.LayoutLocked(key): Cute's, which its Bridge.lua
-- sets); QuestBank alone has none for these two, which Alt-drag as they did. (QB.Locked, the windows design's name for
-- it, is taken: Core.lua's QB:Locked(q), a quest behind a step of its chain)
local function layoutLocked(key)
  local h = QB.LayoutLocked
  return type(h) == "function" and h(key) == true
end
-- Alt-drag moves a piece (layout mode's movers are a host's: QB.Movers below), never in a fight, never while the
-- host's lock says no
local function movable(which)
  if fighting() then return false end
  if layoutLocked(which) then return false end
  return IsAltKeyDown and IsAltKeyDown() and true or false
end
local function moveStart(self, button)
  local f = self.piece
  if button == "LeftButton" and movable(f == banner and "buffs" or "camp") then f:StartMoving(); f.moving = true end
end
-- a frame's coordinate in UIParent's units (its own, at its scale against UIParent's)
local function inParent(f, v)
  local fs, us = f:GetEffectiveScale() or 1, UIParent:GetEffectiveScale() or 1
  return us > 0 and v * fs / us or v
end
local function moveStop(self)
  local f = self.piece
  if not (f and f.moving) then return end
  f.moving = nil
  if fighting() then return end -- (a fight began on the way: the piece stays where it was)
  f:StopMovingOrSizing()
  local x, y = f:GetCenter()
  if not x then return end
  if f == banner then
    local h = (f:GetHeight() or 0) / 2
    R.Settings().bannerPos = { x = inParent(f, x), y = inParent(f, y - h) }
    placeBanner()
  else
    R.Settings().pos = { x = inParent(f, x), y = inParent(f, y) }
    placeBar()
  end
end

----------------------------------------------------------------------------
-- (the layout round) the on-screen pieces for a host's layout mode (Cute's, Cute/Layout.lua; QuestBank has none, and
-- its players see no change). QB.Movers[key] = { key, name, order, secure, frame(), on(), switch(on), rect(),
-- move(left, top), scale(k), get(), set(pos) }:
--   rect     left, top, width, height in UIParent's units from its bottom left: where the piece stands, or would stand
--            while hidden or not made yet (Reminders and Buffs at their largest, six icons and six and four members:
--            placed against the step frame, a piece never grows onto it later)
--   move     its top left there, written to the engine's own place and placed at once
--   scale    0.5 to 2, the piece kept where its own point stands
--   get      { point, x, y, scale }: its point against UIParent's same point, in UIParent's units; no point at its
--            default place
--   set      a kept one back (nil: the default place at 100%)
-- secure: it holds the game's secure buttons, so it is moved and scaled out of a fight only. Reminders ("camp") and
-- Buffs ("buffs") here; the arrow in Arrow.lua, the step frame in StepFrame.lua
----------------------------------------------------------------------------
QB.Movers = QB.Movers or {}
local MOVER_H = PADT + ROW_H + PADB
-- (the pieces at their largest: six icons with their words; six of yours and four members under them, layBanner's sums)
local BAR_MAX_W = PADX * 2 + MAX * SIZE + (MAX - 1) * GAP
local BANNER_MAX_W = PADX * 2 + math.max(MAX_BUFFS * SIZE + (MAX_BUFFS - 1) * GAP, MAX_MEMBERS * MEMBER, 120)
local BANNER_MAX_H = PADT + TITLE_H + SIZE + 8 + ROW_H + 2 + PADB
local function screen() return UIParent:GetWidth() or 1920, UIParent:GetHeight() or 1080 end
local function scaleIn(k)
  k = tonumber(k)
  if not k or math.abs(k - 1) < 0.001 then return nil end
  return math.max(0.5, math.min(2, k))
end
local function placeNow(which)
  if fighting() then return end
  if which == "bar" and bar then placeBar() end
  if banner then placeBanner() end -- (Buffs stands on Reminders by default: placed again with it)
end
local function barSize()
  local k = scaleOf("scale")
  return BAR_MAX_W * k, MOVER_H * k
end
local function barCentre()
  local pos = R.Settings().pos
  local W, H = screen()
  if type(pos) == "table" and pos.x then return pos.x, pos.y end
  return W / 2, H / 2 - 190
end
local function bannerSize()
  local k = scaleOf("bannerScale")
  return BANNER_MAX_W * k, BANNER_MAX_H * k
end
local function bannerBottom()
  local pos = R.Settings().bannerPos
  if type(pos) == "table" and pos.x then return pos.x, pos.y end
  local cx, cy = barCentre()
  return cx, cy + MOVER_H * scaleOf("scale") / 2 + 8
end
QB.Movers.camp = {
  key = "camp", name = "Reminders", order = 3, secure = true,
  frame = function() return bar end,
  on = function() return R.Settings().on ~= false end,
  switch = function(on) local r = R.Settings(); r.on = on and true or false; QB:Settings().campBar = r.on; R.Dirty("all") end,
  rect = function()
    local w, h = barSize()
    local cx, cy = barCentre()
    return cx - w / 2, cy + h / 2, w, h
  end,
  move = function(left, top)
    local w, h = barSize()
    R.Settings().pos = { x = left + w / 2, y = top - h / 2 }
    placeNow("bar")
  end,
  scale = function(k) R.Settings().scale = scaleIn(k); placeNow("bar") end,
  get = function()
    local pos, k = R.Settings().pos, scaleOf("scale")
    if not (type(pos) == "table" and pos.x) then return { scale = k } end
    local W, H = screen()
    return { point = "CENTER", x = pos.x - W / 2, y = pos.y - H / 2, scale = k }
  end,
  set = function(p)
    local r = R.Settings()
    local W, H = screen()
    r.pos = (type(p) == "table" and p.point == "CENTER" and tonumber(p.x) and tonumber(p.y)) and { x = W / 2 + p.x, y = H / 2 + p.y } or nil
    r.scale = type(p) == "table" and scaleIn(p.scale) or nil
    placeNow("bar")
  end,
}
QB.Movers.buffs = {
  key = "buffs", name = "Buffs", order = 4, secure = true,
  frame = function() return banner end,
  on = function() local r = R.Settings(); return r.on ~= false and (r.buffs ~= false or r.party ~= false) end,
  -- (its own switch: your buffs' row and your party's, the two it shows out of a ready check)
  switch = function(on)
    local r = R.Settings()
    on = on and true or false
    r.buffs, r.party = on, on
    if on and r.on == false then r.on = true; QB:Settings().campBar = true end
    R.Dirty("all")
  end,
  rect = function()
    local w, h = bannerSize()
    local bx, by = bannerBottom()
    return bx - w / 2, by + h, w, h
  end,
  move = function(left, top)
    local w, h = bannerSize()
    R.Settings().bannerPos = { x = left + w / 2, y = top - h }
    placeNow("banner")
  end,
  scale = function(k) R.Settings().bannerScale = scaleIn(k); placeNow("banner") end,
  get = function()
    local pos, k = R.Settings().bannerPos, scaleOf("bannerScale")
    if not (type(pos) == "table" and pos.x) then return { scale = k } end
    local W = screen()
    return { point = "BOTTOM", x = pos.x - W / 2, y = pos.y, scale = k }
  end,
  set = function(p)
    local r = R.Settings()
    local W = screen()
    r.bannerPos = (type(p) == "table" and p.point == "BOTTOM" and tonumber(p.x) and tonumber(p.y)) and { x = W / 2 + p.x, y = p.y } or nil
    r.bannerScale = type(p) == "table" and scaleIn(p.scale) or nil
    placeNow("banner")
  end,
}

----------------------------------------------------------------------------
-- an icon: the game's secure button with the reminder's art; a left-click as its record says, set out of a fight only
----------------------------------------------------------------------------
local function attr(b, k, v)
  if b:GetAttribute(k) ~= v then b:SetAttribute(k, v) end
end
local ATTRS = { "spell", "item", "macrotext", "clickbutton", "unit", "target-slot" }
-- its secure click: type1 (an unmodified left click alone) and what that type reads; every other one cleared. Waiting
-- (no click): no type at all, so the game's click does nothing and the hook below shows the way
local function setClick(b, rec)
  local c = rec.click
  local kind = (c and rec.lit) and c.type or nil
  attr(b, "type1", kind)
  for _, k in ipairs(ATTRS) do
    local v = nil
    if kind then
      if k == "spell" then v = c.spell
      elseif k == "item" then v = c.item and ("item:" .. c.item) or nil
      elseif k == "macrotext" then v = c.macro
      elseif k == "clickbutton" then v = c.button
      elseif k == "unit" then v = c.unit
      elseif k == "target-slot" then v = c.slot end
    end
    attr(b, k, v)
  end
end

local lastGo = -10
local menuFor
-- the click beside the game's: a waiting icon's place on the arrow (once a click: its down and up), a lit one noted
-- (Camp's Eat keeps its food in mind; a pause reminder clicked does not snooze); right-click, the menu
local function onClick(self, button, down)
  if down then return end
  local rec = self.rec
  if not rec then return end
  if button == "RightButton" then menuFor(self) return end
  if button ~= "LeftButton" or (IsAltKeyDown and IsAltKeyDown()) then return end
  local t = now()
  if t - lastGo < 0.3 then return end
  lastGo = t
  R.Clicked(rec.key)
  if rec.lit and rec.click then
    if rec.p and rec.p.used then rec.p.used(rec) end
    return
  end
  R.Go(rec)
end
-- a waiting reminder's place on the arrow (a seller, a trainer, a flight master, the bag's next step), for now
function R.Go(rec)
  local go = rec and rec.go
  if not go then return false end
  if type(go) == "function" then go(rec) return true end
  if QB.Arrow then QB.Arrow:Show(go.name, go, go.about) return true end
  return false
end
local function tipLine(tt, s, col, wrap) tt:AddLine(s, col[1], col[2], col[3], wrap) end
-- a reminder's tooltip: its name in WHITE, why, what a click does, and the right-click's two
function R.Tip(owner, rec)
  if not rec then return end
  GameTooltip:SetOwner(owner, "ANCHOR_TOP")
  GameTooltip:SetText(rec.name or "", C.WHITE[1], C.WHITE[2], C.WHITE[3])
  if rec.why then tipLine(GameTooltip, rec.why, C.INK, true) end
  if rec.p and rec.p.tip then rec.p.tip(GameTooltip, rec) end
  if rec.far then tipLine(GameTooltip, "Out of range.", C.INK, true) end
  if rec.clickWord then tipLine(GameTooltip, "Click: " .. rec.clickWord .. ".", C.INK, true) end
  tipLine(GameTooltip, "Right-click: not now, or never.", C.DIM, true)
  GameTooltip:Show()
end
local function onEnter(self) R.Tip(self, self.rec) end
local function onLeave() if GameTooltip:GetOwner() then GameTooltip:Hide() end end

local function newIcon(name, parent, withWord)
  local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
  b:SetSize(SIZE, SIZE)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b.piece = parent
  b.edge = b:CreateTexture(nil, "BACKGROUND")
  b.edge:SetPoint("TOPLEFT", -1, 1); b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  b.edge:SetColorTexture(0, 0, 0, 1)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints()
  if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
  b.count = text(b, 10, C.WHITE)
  b.count:SetJustifyH("RIGHT")
  b.count:SetPoint("BOTTOMRIGHT", -1, 2)
  b.bar = b:CreateTexture(nil, "ARTWORK")
  b.bar:SetSize(SIZE, 2)
  b.bar:SetPoint("TOP", b, "BOTTOM", 0, -2)
  b.bar:Hide()
  if withWord then
    b.word = text(b, 11, C.INK, COL)
    b.word:SetPoint("TOP", b, "BOTTOM", 0, -6)
  end
  b.hi = b:CreateTexture(nil, "HIGHLIGHT")
  b.hi:SetAllPoints()
  b.hi:SetColorTexture(1, 1, 1, 0.12)
  b:SetScript("OnEnter", onEnter)
  b:SetScript("OnLeave", onLeave)
  b:HookScript("OnClick", QB.Safe(onClick, "reminders: click"))
  b:HookScript("OnMouseDown", moveStart)
  b:HookScript("OnMouseUp", moveStop)
  b:Hide()
  return b
end

-- one icon's look from its record: its art (a file, an atlas, its corners), lit or waiting, the sweep, the count, the
-- bar and the word. Nothing written that has not changed
local function paint(b, rec)
  local tex = rec.tex or 134400
  if b.qbTex ~= tex or b.qbAtlas ~= rec.atlas then
    b.qbTex, b.qbAtlas = tex, rec.atlas
    -- (an atlas as the game cuts it: no corners after it, whose own part of its sheet they would replace; a file cropped)
    if not (rec.atlas and QB.Art(b.icon, rec.atlas, tex)) then
      b.icon:SetTexture(tex)
      if rec.tc then b.icon:SetTexCoord(rec.tc[1], rec.tc[2], rec.tc[3], rec.tc[4]) else b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end
  end
  local waiting = not rec.lit
  b.icon:SetDesaturated(waiting)
  b.icon:SetAlpha(waiting and 0.55 or 1)
  b:SetAlpha(rec.far and 0.4 or 1)
  local count = rec.count and rec.count > 1 and rec.count or nil
  if b.qbCount ~= count then b.qbCount = count; b.count:SetText(count and tostring(count) or "") end
  if rec.cdDur and rec.cdDur > 0 then
    if b.qbCD ~= rec.cdStart then b.qbCD = rec.cdStart; b.cd:SetCooldown(rec.cdStart, rec.cdDur) end
  elseif b.qbCD then b.qbCD = nil; b.cd:SetCooldown(0, 0) end
  local col = BAR[rec.cat or ""]
  if col then b.bar:SetColorTexture(col[1], col[2], col[3], 1); b.bar:Show() else b.bar:Hide() end
  if b.word then
    local w = rec.word or ""
    if b.word:GetText() ~= w then b.word:SetText(w) end
    local wc = rec.status == "bad" and C.BAD or rec.status == "warn" and C.WARN or C.INK
    b.word:SetTextColor(wc[1], wc[2], wc[3])
  end
  b.rec = rec
end

----------------------------------------------------------------------------
-- Not now and Never: the menu of a piece (the game's, MenuUtil.CreateContextMenu, Blizzard_Menu/MenuUtil.lua:151)
----------------------------------------------------------------------------
local pieceSnooze = { reminders = nil, buffs = nil, step = nil } -- until (GetTime)
local snoozedKeys = { reminders = {}, buffs = {}, step = {} }    -- what showed when it was snoozed, and how bad
local function pieceOf(rec)
  local p = rec and rec.p
  local where = p and p.piece or "reminders"
  if where == "party" or where == "pull" then return "buffs" end
  if where == "step" and not rec.onBar then return "step" end
  if where == "step" then return "reminders" end
  return where
end
R.PieceOf = pieceOf
local snoozeGen = 0
function R.SnoozePiece(which)
  pieceSnooze[which] = now() + SNOOZE
  local kept = snoozedKeys[which]
  for k in pairs(kept) do kept[k] = nil end
  for _, p in ipairs(R.list) do
    for i = 1, p.n do
      local rec = p.recs[i]
      if pieceOf(rec) == which then kept[rec.never or rec.key] = rec.status or "ok" end
    end
  end
  snoozeGen = snoozeGen + 1
  local gen = snoozeGen
  if C_Timer and C_Timer.After then
    C_Timer.After(SNOOZE + 0.1, QB.Safe(function() if gen == snoozeGen then R.Dirty("all") end end, "reminders: not now"))
  end
  R.Dirty("all")
end
-- a snoozed piece comes back early when something on it got worse: a reminder it did not show, or one now BAD
local function pieceQuiet(which, rec)
  local untilT = pieceSnooze[which]
  if not untilT then return false end
  if now() >= untilT then pieceSnooze[which] = nil return false end
  local was = snoozedKeys[which][rec.never or rec.key]
  if was == nil or (rec.status == "bad" and was ~= "bad") then pieceSnooze[which] = nil return false end
  return true
end
function menuFor(b)
  if fighting() then return end
  local rec = b.rec
  if not rec then return end
  local which = pieceOf(rec)
  local key, name = rec.never or rec.key, rec.neverName or (rec.p and rec.p.neverName) or rec.name or rec.key
  -- (Talents and Train: Not now until the next level, the reminder alone; any other the whole piece ten minutes)
  local snoozeFn = function()
    if rec.p and rec.p.untilLevel then R.SnoozeKey(rec.key, (QB.state and QB.state.level or 0) + 1) else R.SnoozePiece(which) end
  end
  local neverWord = key == "party" and "Never: party buffs" or ("Never: " .. name)
  -- (Settings: a host's own Reminders section where it has one, Cute's; QuestBank's Settings page holds it)
  local settings = function()
    if QB.UI and QB.UI.OpenReminders then QB.UI.OpenReminders() elseif QB.UI and QB.UI.Open then QB.UI:Open(5) end
  end
  if type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function" then
    MenuUtil.CreateContextMenu(b, function(_, root)
      root:CreateButton("Not now", snoozeFn)
      root:CreateButton(neverWord, function() R.SetNever(key, name) end)
      root:CreateButton("Settings...", settings)
    end)
  elseif QB.UI and QB.UI.ShowMenu then
    QB.UI:ShowMenu(name, { { "Not now", snoozeFn }, { neverWord, function() R.SetNever(key, name) end }, { "Settings...", settings } })
  end
end
R.Menu = function(b) menuFor(b) end

----------------------------------------------------------------------------
-- the refresh: the dirty groups' providers read, the pieces laid out (out of a fight only)
----------------------------------------------------------------------------
local shown = { reminders = {}, buffs = {}, party = {}, pull = {} } -- the records each piece shows now
local pull = { untilT = nil, gen = 0 } -- Before the pull: until when (below)
local stepRec -- the step frame's line now
local after = { gen = 0, waiting = false }
R.after = after
local clock -- (the 1 s clock's frame)
local needClock = false
local fade = 1

local function offRow(p)
  local row = p.row
  if not row then return false end
  if set[row] == false then return true end
  return false
end
-- whether a record may show: its row on, not Never, not snoozed by itself
local function allowed(rec)
  local key = rec.never or rec.key
  if set.never[key] ~= nil then return false end
  if R.Snoozed(rec.key) then return false end
  return true
end

local function readAll()
  ctx.me = QB.API.WorldPosition(nil, hereBuf)
  ctx.t = now()
  ctx.town = resting()
  ctx.inst = instanceKind()
  ctx.party = yes(IsInGroup) and not yes(IsInRaid)
  ctx.stepFrame = QB.StepFrame and QB.StepFrame.frame and QB.StepFrame.frame:IsShown() and not (QB.StepFrame.frame.card and QB.StepFrame.frame.card:IsShown())
  ctx.level = QB.state and QB.state.level or 1
  ctx.pull = R.PullOn()
  local any = dirty.all
  for _, p in ipairs(R.list) do
    local want = any
    if not want then for _, g in ipairs(p.groups or {}) do if dirty[g] then want = true break end end end
    if p.timed and needClock then want = true end
    if want then
      p.n = 0
      if not offRow(p) then
        reading = p
        p.safeRead(add, ctx)
        reading = nil
      end
    end
  end
  for k in pairs(dirty) do dirty[k] = nil end
end

-- which records each piece shows, in order; Reminders' six (a BAD status always in: the last camp icon gives way)
local QUIET = { { "reminders", "reminders" }, { "buffs", "buffs" }, { "buffs", "party" }, { "buffs", "pull" } }
local badBuf = {}
local function collect()
  for _, l in pairs(shown) do for i = #l, 1, -1 do l[i] = nil end end
  stepRec = nil
  local inst = ctx.inst
  local mode = set.instance
  local quietInside = inst ~= nil and mode ~= "all"
  if inst and mode == "none" then return end
  for _, p in ipairs(R.list) do
    for i = 1, p.n do
      local rec = p.recs[i]
      rec.onBar = nil
      if allowed(rec) then
        local where = p.piece or "reminders"
        if where == "step" then
          -- (the first is the line, G.Reminder's; with the step frame off it is Reminders' last icon too)
          if not stepRec and not inst then
            stepRec = rec
            if not ctx.stepFrame then rec.onBar = true; rec.lit = false; table.insert(shown.reminders, rec) end
          end
        elseif where == "reminders" then
          if not quietInside then table.insert(shown.reminders, rec) end
        elseif where == "buffs" or where == "party" or where == "pull" then
          table.insert(shown[where], rec)
        end
      end
    end
  end
  -- (Reminders: past six the last wait, but a BAD status takes the place of the last camp icon)
  local list = shown.reminders
  if #list > MAX then
    local bad = badBuf
    for i = #bad, 1, -1 do bad[i] = nil end
    for i = MAX + 1, #list do if list[i].status == "bad" then bad[#bad + 1] = list[i] end end
    for i = #list, MAX + 1, -1 do list[i] = nil end
    for _, rec in ipairs(bad) do
      local drop
      for i = #list, 1, -1 do if list[i].status ~= "bad" and (list[i].p.row == "camp" or not drop) then drop = i; if list[i].p.row == "camp" then break end end end
      if drop then table.remove(list, drop); list[#list + 1] = rec end
    end
  end
  for i = #shown.buffs, MAX_BUFFS + 1, -1 do shown.buffs[i] = nil end
  for i = #shown.party, MAX_MEMBERS + 1, -1 do shown.party[i] = nil end
  -- the pieces' own Not now
  for _, pair in ipairs(QUIET) do
    local l = shown[pair[2]]
    for i = #l, 1, -1 do if pieceQuiet(pair[1], l[i]) then table.remove(l, i) end end
  end
  if stepRec and pieceQuiet("step", stepRec) then stepRec = nil end
  -- (the pause reminders shown now: walking off without a click snoozes them, R.Started)
  for k in pairs(paused) do paused[k] = nil end
  for _, rec in ipairs(shown.reminders) do if rec.pause then paused[rec.key] = true end end
  -- (Before the pull ends when nothing is left to do)
  if ctx.pull and #shown.pull == 0 and #shown.buffs == 0 then pull.untilT = nil; ctx.pull = false end
end

local usedBuf = {}
local function layBar()
  local list = shown.reminders
  local n = #list
  local f = bar
  local w = PADX * 2 + math.max(SIZE, n * SIZE + math.max(0, n - 1) * GAP)
  f:SetSize(w, PADT + ROW_H + PADB)
  local used = usedBuf
  for k in pairs(used) do used[k] = nil end
  for i, rec in ipairs(list) do
    local key = rec.key
    used[key] = true
    local b = icons[key]
    if not b then b = newIcon("QuestBankCamp_" .. key, f, true); icons[key] = b end
    paint(b, rec)
    setClick(b, rec)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f, "TOPLEFT", PADX + (i - 1) * (SIZE + GAP), -PADT)
    if not b:IsShown() then b:Show() end
  end
  for key, b in pairs(icons) do if not used[key] and b:IsShown() then b:Hide(); b.rec = nil end end
  f:SetShown(n > 0)
end

local function layBanner()
  local mine, party = shown.buffs, shown.party
  for _, rec in ipairs(shown.pull) do mine[#mine + 1] = rec end
  for i = #mine, MAX_BUFFS + 1, -1 do mine[i] = nil end
  local n, m = #mine, #party
  local f = banner
  local row1 = n > 0 and n * SIZE + (n - 1) * GAP or 0
  local row2 = m > 0 and m * MEMBER or 0
  local w = math.max(row1, row2, 120) + PADX * 2
  local h = PADT + TITLE_H + (n > 0 and SIZE + 8 or 0) + (m > 0 and ROW_H + 2 or 0) + PADB
  f:SetSize(w, h)
  f.title:SetText(ctx.pull and "Before the pull" or "Missing buffs")
  local x = math.floor((w - row1) / 2)
  for i, rec in ipairs(mine) do
    local b = bicons[i]
    if not b then b = newIcon("QuestBankBuff_" .. i, f, false); bicons[i] = b end
    paint(b, rec)
    setClick(b, rec)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(PADT + TITLE_H))
    if not b:IsShown() then b:Show() end
    x = x + SIZE + GAP
  end
  for i = n + 1, #bicons do if bicons[i]:IsShown() then bicons[i]:Hide() end; bicons[i].rec = nil end
  local y = -(PADT + TITLE_H + (n > 0 and SIZE + 8 or 0))
  x = math.floor((w - row2) / 2)
  for i, rec in ipairs(party) do
    local b = picons[i]
    if not b then
      b = newIcon("QuestBankBuffParty_" .. i, f, false)
      b.label = text(b, 11, C.INK, MEMBER - 6)
      b.label:SetPoint("TOP", b, "BOTTOM", 0, -6)
      picons[i] = b
    end
    paint(b, rec)
    setClick(b, rec)
    if b.label:GetText() ~= rec.who then b.label:SetText(rec.who or "") end
    local col = rec.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[rec.class]
    if col then b.label:SetTextColor(col.r, col.g, col.b) else b.label:SetTextColor(C.INK[1], C.INK[2], C.INK[3]) end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f, "TOPLEFT", x + math.floor((MEMBER - SIZE) / 2), y)
    if not b:IsShown() then b:Show() end
    x = x + MEMBER
  end
  for i = m + 1, #picons do if picons[i]:IsShown() then picons[i]:Hide() end; picons[i].rec = nil end
  if n + m > 0 and not f:IsShown() then f:Show(); R.bannerShows = (R.bannerShows or 0) + 1
  elseif n + m == 0 and f:IsShown() then f:Hide() end
end

local function frames()
  if bar then return end
  holderFrame()
  bar = piece("QuestBankCampBar")
  banner = piece("QuestBankBuffBanner")
  banner.title = text(banner, 12, C.WHITE)
  banner.title:SetPoint("TOP", banner, "TOP", 0, -PADT)
  placeBar(); placeBanner()
  R.bar, R.banner = bar, banner
end
R.Frames = function() frames(); return bar, banner end

local function hideAll()
  if bar and bar:IsShown() then bar:Hide() end
  if banner and banner:IsShown() then banner:Hide() end
end

-- the clock: one look a second while a word changes as time or you go, a party row can show, or the fade runs
local function wantClock()
  local t = false
  for _, l in pairs(shown) do for _, rec in ipairs(l) do if rec.timed then t = true end end end
  if stepRec and stepRec.timed then t = true end
  if ctx.party and set.party ~= false then t = true end
  return t
end
local tickAt = 0
local function onClock(self, dt)
  if fade < 1 then
    fade = math.min(1, fade + (dt or 0) / FADE)
    if holder then holder:SetAlpha(fade) end
  end
  tickAt = tickAt + (dt or 0)
  if tickAt >= 1 then
    tickAt = 0
    if needClock then dirty.party = true; R.Dirty("party") end
  end
  if not needClock and fade >= 1 then self:SetScript("OnUpdate", nil); self.running = false end
end
local function runClock()
  if not clock then clock = CreateFrame("Frame"); R.clock = clock end
  if clock.running then return end
  clock.running = true
  tickAt = 0
  clock:SetScript("OnUpdate", QB.Safe(onClock, "reminders: clock"))
end

function flushNow()
  if fighting() then after.waiting = true; return end
  if after.gen > 0 and after.waiting then return end -- (the 2 s after a fight: the pieces come back with it)
  if restricted() or aurasSecret() then after.waiting = true; return end
  set = R.Settings()
  R.refreshes = R.refreshes + 1
  readAll()
  collect()
  frames()
  -- (Reminders on screen off: the two pieces; the step frame's line stays its rows', unless the host's switch is the
  -- only master, QB.remindAll: Cute's module)
  local off = set.on == false
  if off or away() then
    hideAll()
    if away() or (off and QB.remindAll) then stepRec = nil end
  else
    layBar()
    layBanner()
  end
  R.layouts = R.layouts + 1
  needClock = wantClock()
  if needClock or fade < 1 then runClock() end
  if QB.StepFrame and QB.StepFrame.RemindChanged then QB.StepFrame.RemindChanged(stepRec) end
  set = nil
end
-- every provider read again and the pieces laid out now (Camp.Refresh, Settings, the tests)
function R.Refresh()
  dirty.all = true
  bagsStale = true
  pending = false
  flushNow()
end
-- the step frame's line now: its record (Guide's Train or Flight path, Camp's Sleeping bag), or nil
function R.Step() return stepRec end
-- the records a piece shows now ("reminders", "buffs", "party", "pull"), for the tests and Cute's dashboard
function R.Shown(which) return shown[which] end

----------------------------------------------------------------------------
-- a fight: the state driver hides the holder; after it, 2 s (a new fight cancels them), then one fresh look and a
-- 0.2 s fade in. Without a driver (an old client) the holder goes clear instead
----------------------------------------------------------------------------
local function fightOver()
  after.gen = after.gen + 1
  local gen = after.gen
  after.waiting = true
  hideAll()
  if C_Timer and C_Timer.After then
    C_Timer.After(AFTER, QB.Safe(function()
      if gen ~= after.gen or fighting() then return end
      after.gen, after.waiting = 0, false
      fade = 0
      if holder then holder:SetAlpha(0) end
      R.Refresh()
      runClock()
    end, "reminders: after the fight"))
  else
    after.gen, after.waiting = 0, false
    R.Refresh()
  end
end
R.FightOver = fightOver

----------------------------------------------------------------------------
-- Before the pull: a ready check (READY_CHECK; its initiator, secret on dungeon and raid maps,
-- PartyInfoDocumentation.lua:841, is never read) or entering a raid, 5 s after, out of a fight; ends 10 s after
-- READY_CHECK_FINISHED, 60 s after the entry, when nothing is left, or at the first fight
----------------------------------------------------------------------------
R.pullState = pull
function R.PullOn()
  if not pull.untilT then return false end
  if now() >= pull.untilT then pull.untilT = nil return false end
  return true
end
function R.Pull(seconds, delay)
  pull.gen = pull.gen + 1
  local gen = pull.gen
  local function start()
    if gen ~= pull.gen then return end
    pull.untilT = now() + seconds
    R.Dirty("pull")
    if C_Timer and C_Timer.After then C_Timer.After(seconds + 0.1, QB.Safe(function() if gen == pull.gen then R.Dirty("pull") end end, "reminders: pull")) end
  end
  if delay and delay > 0 and C_Timer and C_Timer.After then C_Timer.After(delay, QB.Safe(start, "reminders: pull")) else start() end
end
function R.PullEnd(delay)
  if not pull.untilT then return end
  if delay then pull.untilT = math.min(pull.untilT, now() + delay)
    if C_Timer and C_Timer.After then local gen = pull.gen; C_Timer.After(delay + 0.1, QB.Safe(function() if gen == pull.gen then R.Dirty("pull") end end, "reminders: pull")) end
  else pull.untilT = nil end
  R.Dirty("pull")
end

----------------------------------------------------------------------------
-- upkeep: repair, bags, ammo, hearth, use, buy; and talents. Each shows in town or within 2 minutes of the place that
-- fixes it, elsewhere only at its worst (broken, full, empty); never while a merchant's window is open, whose own
-- buttons (Repair All, Sell All Junk, which asks first, MerchantFrame.lua:1124-1131) are the game's: nothing here sells
----------------------------------------------------------------------------
local NEAR = 2 -- minutes
R.NEAR = NEAR
local merchantOpen = false
-- the merchants you opened, for upkeep: repairers (CanMerchantRepair) and sellers of ammo and of the consumables you
-- use, 60 of each, the longest unseen let go. QuestBankDB.remind: kept on this computer, never in the uploads
local function store(kind)
  QuestBankDB = QuestBankDB or {}
  if type(QuestBankDB.remind) ~= "table" then QuestBankDB.remind = {} end
  local t = QuestBankDB.remind[kind]
  if type(t) ~= "table" then t = {}; QuestBankDB.remind[kind] = t end
  return t
end
R.Store = store
local function keep(t, key, e)
  t[key] = e
  local n, oldest = 0, nil
  for k, v in pairs(t) do
    n = n + 1
    if type(v) ~= "table" then t[k] = nil
    elseif not oldest or (v.at or 0) < (t[oldest].at or 0) then oldest = k end
  end
  if n > 60 and oldest then t[oldest] = nil end
end
-- the healing and mana potions (consumable subclass 1 whose spell heals, SpellEffect 10, or gives mana, 30 with power 0:
-- the client's ItemXItemEffect, ItemEffect and SpellEffect, 1.60.1.70338), for Buy's kinds
R.POTION = {
  [118] = "heal", [858] = "heal", [929] = "heal", [1710] = "heal", [3928] = "heal", [4596] = "heal", [13446] = "heal", [17348] = "heal",
  [17349] = "heal", [23579] = "heal", [241650] = "heal", [247239] = "heal", [247240] = "heal", [247241] = "heal", [247242] = "heal",
  [268881] = "heal", [268882] = "heal", [268883] = "heal", [287966] = "heal", [287967] = "heal", [287977] = "heal",
  [2455] = "mana", [3087] = "mana", [3385] = "mana", [3827] = "mana", [6149] = "mana", [13443] = "mana", [13444] = "mana",
  [17351] = "mana", [17352] = "mana", [23578] = "mana", [287968] = "mana", [287969] = "mana",
}
-- what an item is to upkeep: "ammo2" arrows or "ammo3" bullets (class 6), "flask" a flask or an elixir (consumable 3
-- or 2), "heal" or "mana" a potion; nil for anything else (C_Item.GetItemInfoInstant, ItemDocumentation.lua:659)
local kindCache = {}
local function kindOf(id)
  local v = kindCache[id]
  if v ~= nil then return v or nil end
  v = R.POTION[id] or false
  if not v and C_Item and type(C_Item.GetItemInfoInstant) == "function" then
    local ok, _, _, _, _, _, classID, subID = pcall(C_Item.GetItemInfoInstant, id)
    classID, subID = ok and plain(classID), ok and plain(subID)
    if classID == 6 and (subID == 2 or subID == 3) then v = "ammo" .. subID
    elseif classID == 0 and (subID == 2 or subID == 3) then v = "flask" end
  end
  kindCache[id] = v
  return v or nil
end
R.KindOf = kindOf
function R.NoteMerchant()
  local Disc = QB.Discover
  local key = Disc and Disc.Who and Disc.Who("npc")
  local me = QB.API.WorldPosition()
  if not (key and me) then return end
  local okN, name = pcall(UnitName, "npc")
  name = okN and plain(name) or nil
  local at = time and time() or 0
  local where = { n = type(name) == "string" and name or nil, c = me.c, wx = math.floor(me.wx + 0.5), wy = math.floor(me.wy + 0.5), at = at }
  if yes(CanMerchantRepair) then keep(store("repair"), key, where) end
  if type(GetMerchantNumItems) ~= "function" or type(GetMerchantItemID) ~= "function" then return end
  local ok, n = pcall(GetMerchantNumItems)
  n = ok and plain(n) or 0
  local kinds
  for i = 1, math.min(type(n) == "number" and n or 0, 200) do
    local okI, id = pcall(GetMerchantItemID, i)
    id = okI and plain(id) or nil
    local k = type(id) == "number" and kindOf(id)
    if k then kinds = kinds or {}; kinds[k] = kinds[k] or id end
  end
  local vend = store("vend")
  if kinds then
    local e = { n = where.n, c = where.c, wx = where.wx, wy = where.wy, at = at, k = kinds }
    keep(vend, key, e)
  else
    vend[key] = nil
  end
  local shop = store("shop")
  keep(shop, key, { n = where.n, c = where.c, wx = where.wx, wy = where.wy, at = at })
end
-- the nearest of a store's (kind: one that sells it), and its minutes
local function nearest(me, which, kind)
  local best, bm
  for _, e in pairs(store(which)) do
    if type(e) == "table" and (not kind or (e.k and e.k[kind])) then
      local m = R.Minutes(me, e)
      if m and (not bm or m < bm) then best, bm = e, m end
    end
  end
  return best, bm
end
R.Nearest = nearest
local function goTo(e, item)
  return function()
    if QB.Camp and QB.Camp.GoTo then QB.Camp.GoTo(e, item) elseif QB.Arrow then QB.Arrow:Show(e.n or "A merchant", e) end
  end
end

R.Add({ key = "repair", neverName = "Repair", piece = "reminders", order = 60, row = "upkeep", groups = { "upkeep" }, timed = true,
  read = function(add, ctx)
    local d = QB.API.Durability()
    if not d or d == 0 or merchantOpen or ctx.inst then return end
    local e, m = nearest(ctx.me, "repair")
    local near = e and m and m <= NEAR
    if d < 2 and not (ctx.town or near) then return end
    local rec = add()
    rec.tex, rec.lit = 136241, false
    if d >= 2 then rec.word, rec.status = "Broken", "bad"
    elseif e then rec.word, rec.timed = R.MinWord(m), true
    else rec.word, rec.status = "Low", "warn" end
    rec.name = d >= 2 and "Broken gear" or "Repair"
    rec.why = d >= 2 and "Something you wear is broken: it gives nothing until it is repaired." or "Your gear is wearing out."
    if e then rec.go, rec.clickWord = goTo(e), "show " .. (e.n or "the repairer") .. " on the arrow, " .. R.MinWord(m) end
  end,
})

local FREE = { [0] = "Full", [1] = "1 free", [2] = "2 free" }
local overflowAt
R.Add({ key = "bags", neverName = "Bags", piece = "reminders", order = 70, row = "upkeep", groups = { "upkeep" }, timed = true,
  read = function(add, ctx)
    local free = QB.API.FreeSlots()
    local full = overflowAt and ctx.t - overflowAt < 30
    if not free or merchantOpen or ctx.inst then return end
    if free > 2 and not full then return end
    if full then free = 0 end
    local e, m = nearest(ctx.me, "shop")
    local near = e and m and m <= NEAR
    if free > 0 and not (ctx.town or near) then return end
    local rec = add()
    rec.tex = 133633
    if free == 0 then rec.word, rec.status = "Full", "bad"
    elseif near then rec.word, rec.timed = R.MinWord(m), true
    else rec.word, rec.status = FREE[free], "warn" end
    rec.name = free == 0 and "Bags full" or "Bags nearly full"
    rec.why = "Loot left on the ground is XP and gold left behind."
    if near then
      rec.lit, rec.go, rec.clickWord = false, goTo(e), "show " .. (e.n or "the merchant") .. " on the arrow"
    else
      -- (your bags opened: the game's own backpack button, Camelot/MainMenuBarBagButtons.xml:70)
      rec.lit = MainMenuBarBackpackButton ~= nil
      R.Click(rec, "click", MainMenuBarBackpackButton)
      rec.clickWord = "open your bags"
    end
  end,
})

-- the ammo kind you use: the one in the ammo slot, else your ranged weapon's (a gun bullets, a bow or crossbow arrows)
local INVSLOT_AMMO_ID = 0 -- (INVSLOT_AMMO, Blizzard_FrameXMLBase/Constants.lua:135)
local function ammoKind()
  local ok, id = pcall(GetInventoryItemID, "player", type(INVSLOT_AMMO) == "number" and INVSLOT_AMMO or INVSLOT_AMMO_ID)
  id = ok and plain(id) or nil
  local k = type(id) == "number" and kindOf(id)
  if k then return k, id end
  local okR, rid = pcall(GetInventoryItemID, "player", 18)
  rid = okR and plain(rid) or nil
  if type(rid) == "number" and C_Item and type(C_Item.GetItemInfoInstant) == "function" then
    local okI, _, _, _, _, _, classID, subID = pcall(C_Item.GetItemInfoInstant, rid)
    if okI and plain(classID) == 2 then
      subID = plain(subID)
      if subID == 3 then return "ammo3" end
      if subID == 2 or subID == 18 then return "ammo2" end
    end
  end
  return nil
end
R.Add({ key = "ammo", neverName = "Ammo", piece = "reminders", order = 80, row = "upkeep", groups = { "upkeep" }, timed = true,
  read = function(add, ctx)
    if ctx.inst or not yes(UnitUsesAmmo, "player") then return end -- (UnitUsesAmmo: Camelot/PaperDollFrame.lua:1499)
    local slot = type(INVSLOT_AMMO) == "number" and INVSLOT_AMMO or INVSLOT_AMMO_ID
    local ok, n = pcall(GetInventoryItemCount, "player", slot)
    n = ok and plain(n) or nil
    if type(n) ~= "number" or n >= 200 then return end
    local kind, id = ammoKind()
    local e, m = nearest(ctx.me, "vend", kind)
    local near = e and m and m <= NEAR
    if n > 0 and not (ctx.town or near) then return end
    local rec = add()
    local okT, tex = pcall(GetInventoryItemTexture, "player", slot)
    rec.tex, rec.lit = (okT and plain(tex)) or (kind == "ammo3" and 132384 or 132382), false
    if n == 0 then rec.word, rec.status = "None", "bad"
    elseif e then rec.word, rec.timed = R.MinWord(m), true
    else rec.word, rec.status = "Low", "warn" end
    rec.count = n
    rec.name, rec.why = "Ammo", n == 0 and "Your ammo is gone." or string.format("%d left.", n)
    if e then rec.go, rec.clickWord = goTo(e, e.k and e.k[kind]), "show " .. (e.n or "the seller") .. " on the arrow" end
  end,
})

-- your hearthstone: the ones Forever has (6948, 243229 Hearthstone of the Dawn, 284163), then the single-use 282006; ready by
-- its item cooldown (C_Container.GetItemCooldown, read on BAG_UPDATE_COOLDOWN; never C_Spell.GetSpellCooldown(8690),
-- secret in a fight)
R.HEARTHS = { 6948, 243229, 284163, 282006 }
function R.Hearth()
  local bagsNow = R.Bags()
  for _, id in ipairs(R.HEARTHS) do
    if bagsNow[id] then
      local get = C_Container and C_Container.GetItemCooldown
      local start, dur = 0, 0
      if type(get) == "function" then
        local ok, s, d = pcall(get, id)
        start, dur = ok and plain(s) or 0, ok and plain(d) or 0
      end
      local left = (type(start) == "number" and type(dur) == "number" and dur > 1.5) and math.max(0, start + dur - now()) or 0
      return id, left
    end
  end
  return nil
end
local BESIDE = { "repair", "bags" } -- (Hearth comes beside one of these at its worst)
R.Add({ key = "hearth", neverName = "Hearth", piece = "reminders", order = 90, row = "upkeep", groups = { "upkeep" },
  read = function(add, ctx)
    if ctx.town or ctx.inst then return end
    local bad = false
    for _, k in ipairs(BESIDE) do
      local p = R.byKey[k]
      for i = 1, p.n do if p.recs[i].status == "bad" then bad = true end end
    end
    if not bad then return end
    -- (the route has its own hearth step planned: one thing, one place)
    local route = (QB.Target and QB.Target.Route and QB.Target.Route()) or QB.routeNow
    if route and route.bind then return end
    local id, left = R.Hearth()
    if not id or left > 0 then return end
    local rec = add()
    rec.tex, rec.lit, rec.word = 134414, true, "Hearth"
    R.Click(rec, "item", id)
    local okB, bind = pcall(GetBindLocation)
    bind = okB and plain(bind) or nil
    rec.name = "Hearthstone"
    rec.why = (type(bind) == "string" and bind ~= "") and ("To " .. bind .. ": repair and sell there.") or "Home: repair and sell there."
    rec.clickWord = "use it"
  end,
})

-- Use: what in your bags wants a click (each item id looked at once, R.UseKind): a quest it starts that is neither in
-- your log nor done, a container to open (its tooltip's Open line, none locked: an ErrorLine leaves it out), a recipe
-- or blueprint you can learn (a Learn line, IsUsableItem). One icon, the first in that order; the tooltip lists five
local useList = {}
R.Add({ key = "use", piece = "reminders", order = 100, row = "upkeep", groups = { "upkeep" },
  read = function(add, ctx)
    if ctx.inst then return end
    for i = #useList, 1, -1 do useList[i] = nil end
    local first, firstRank
    local log = QB.state and QB.state.log or {}
    for id in pairs(R.Bags()) do
      local k = useKind[id]
      local rank
      if type(k) == "string" and k:find("^quest:") then
        local qid = tonumber(k:sub(7))
        if qid and not log[qid] and not (QB.API.IsDone and QB.API.IsDone(qid)) then rank = 1 end
      elseif k == "open" then rank = 2
      elseif k == "learn" then rank = 3 end
      if rank and not (set and set.never["use:" .. id]) then
        useList[#useList + 1] = id
        if not first or rank < firstRank or (rank == firstRank and id < first) then first, firstRank = id, rank end
      end
    end
    if not first then return end
    local rec = add()
    local okT, tex = pcall(C_Item.GetItemIconByID, first)
    rec.tex, rec.lit, rec.word, rec.count = (okT and plain(tex)) or 134400, true, "Use", #useList
    R.Click(rec, "item", first)
    rec.never = "use:" .. first
    local okN, name = pcall(C_Item.GetItemInfo or GetItemInfo, first)
    name = okN and plain(name) or nil
    rec.neverName = type(name) == "string" and name or "this item"
    rec.name = firstRank == 1 and "Starts a quest" or firstRank == 2 and "Something to open" or "Something to learn"
    rec.clickWord = "use " .. rec.neverName
  end,
  tip = function(tt)
    local INK = C.INK
    for i = 1, math.min(5, #useList) do
      local ok, name = pcall(C_Item.GetItemInfo or GetItemInfo, useList[i])
      name = ok and plain(name) or nil
      tt:AddLine(type(name) == "string" and name or ("Item " .. useList[i]), INK[1], INK[2], INK[3])
    end
  end,
})

-- Buy: in town, a kind of consumable you used on this character (a flask or elixir, a healing potion, a mana potion for
-- a mana class) that you carry none of, with a seller of it you opened; none known, nothing
local MANA_CLASS = { MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true, SHAMAN = true, PALADIN = true, HUNTER = true }
local function used()
  local c = QB.Camp and QB.Camp.CharDB and QB.Camp.CharDB()
  if not c then return {} end
  if type(c.used) ~= "table" then c.used = {} end
  return c.used
end
R.Used = used
R.Add({ key = "buy", neverName = "Buy", piece = "reminders", order = 110, row = "upkeep", groups = { "upkeep" }, timed = true,
  read = function(add, ctx)
    if not ctx.town then return end
    local u = used()
    local have = {}
    for id in pairs(R.Bags()) do local k = kindOf(id); if k then have[k] = true end end
    local okC, _, cls = pcall(UnitClass, "player")
    cls = okC and plain(cls) or nil
    for _, kind in ipairs({ "flask", "heal", "mana" }) do
      if u[kind] and not have[kind] and (kind ~= "mana" or MANA_CLASS[cls or ""]) then
        local e, m = nearest(ctx.me, "vend", kind)
        if e then
          local item = e.k[kind]
          local rec = add()
          local okT, tex = pcall(C_Item.GetItemIconByID, item)
          rec.tex, rec.lit, rec.word, rec.timed = (okT and plain(tex)) or 134400, false, R.MinWord(m), true
          rec.name = kind == "flask" and "Flasks and elixirs" or kind == "heal" and "Healing potions" or "Mana potions"
          rec.why = "You use these and carry none."
          rec.go, rec.clickWord = goTo(e, item), "show " .. (e.n or "the seller") .. " on the arrow"
          return
        end
      end
    end
  end,
})

-- Talents: points to spend (C_ClassTalents.HasUnspentTalentPoints), outside an instance, only while the game's own
-- talent button is not on screen (a UI addon replaced the bar: otherwise the game's tip and pulse say it,
-- MainMenuBarMicroButtons.lua:799); a click is that button's (TalentMicroButton, Camelot/MicroMenuContainerOverrides.lua:7).
-- Not now: until the next level
R.Add({ key = "talents", neverName = "Talents", piece = "reminders", order = 120, row = "class", groups = { "class" }, untilLevel = true,
  read = function(add, ctx)
    if ctx.inst then return end
    local has = QB.API.UnspentTalents()
    R.Diag("talent", has)
    if not has then return end
    local b = TalentMicroButton
    if b and b.IsVisible and b:IsVisible() then return end
    local rec = add()
    local cls = QB.state and QB.state.class
    local tc = type(CLASS_ICON_TCOORDS) == "table" and cls and CLASS_ICON_TCOORDS[cls] -- (SharedConstants.lua:27)
    rec.tex = (QB.Data.TEX and QB.Data.TEX.classes) or 131146
    if type(tc) == "table" and tc[4] then rec.tc = tc end
    rec.lit, rec.word = b ~= nil, "Talents"
    if type(GetNumUnspentTalents) == "function" then
      local ok, n = pcall(GetNumUnspentTalents)
      n = ok and plain(n) or nil
      if type(n) == "number" and n > 0 then rec.count = n end
    end
    if b then R.Click(rec, "click", b); rec.clickWord = "open your talents" end
    rec.name, rec.why = "Talent points to spend", "Your talents are your class's strength."
  end,
})

-- a diagnostic for the live client (section 11 of the design): what the game answers, kept in QuestBankDB.diag.remind
-- (numbers and ids only, never a name)
function R.Diag(key, v)
  QuestBankDB = QuestBankDB or {}
  QuestBankDB.diag = type(QuestBankDB.diag) == "table" and QuestBankDB.diag or {}
  local d = type(QuestBankDB.diag.remind) == "table" and QuestBankDB.diag.remind or {}
  QuestBankDB.diag.remind = d
  if d[key] ~= v then d[key] = v end
end

----------------------------------------------------------------------------
-- your weapon (the rogue's poisons, the shaman's imbues, anyone's stones and oils), by habit per weapon item: what you
-- put on it last (the item used or the spell cast in the second before a temporary enchant appeared on it), learned
-- once you have done it twice; then, its enchant gone and that item carried or that spell known: an icon, a click puts
-- it on (an item with target-slot 16 or 17, SecureTemplates.lua:771; an imbue its spell). Per weapon item, not per
-- hand, so a fishing lure is never offered for a sword
----------------------------------------------------------------------------
local lastUse = { at = 0 } -- the last item used or spell cast: { at, item, spell }
local HANDS = { 16, 17 } -- (the main hand, the off hand)
local enchanted = {}       -- [slot] = true while a temporary enchant is on it (16, 17)
local function weaponDB()
  local c = QB.Camp and QB.Camp.CharDB and QB.Camp.CharDB()
  if not c then return {} end
  if type(c.weapon) ~= "table" then c.weapon = {} end
  return c.weapon
end
-- a temporary enchant on a hand (16 main, 17 off): C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot), a list
-- (ItemDocumentation.lua:1141, 1968), else the old GetWeaponEnchantInfo
local function tempEnchant(slot)
  if C_Item and type(C_Item.GetWeaponEnchantInfo) == "function" and Enum and Enum.WeaponSlot then
    local ws = slot == 16 and Enum.WeaponSlot.MainHand or Enum.WeaponSlot.OffHand
    local ok, list = pcall(C_Item.GetWeaponEnchantInfo, ws)
    if ok and type(list) == "table" then
      for _, e in ipairs(list) do
        if type(e) == "table" and plain(e.hasEnchant) == true then
          R.Diag("weapon", plain(e.enchantType))
          return true, plain(e.timeLeft)
        end
      end
      return false
    end
  end
  if type(GetWeaponEnchantInfo) == "function" then
    local ok, mh, _, _, _, oh = pcall(GetWeaponEnchantInfo)
    if ok then return plain(slot == 16 and mh or oh) == true end
  end
  return nil
end
R.TempEnchant = tempEnchant
local function weaponIn(slot)
  local ok, id = pcall(GetInventoryItemID, "player", slot)
  id = ok and plain(id) or nil
  return type(id) == "number" and id or nil
end
-- an enchant that came on a hand now: what was used in the second before, a hit for that weapon
local function watchWeapons()
  local db = weaponDB()
  for _, slot in ipairs(HANDS) do
    local on = tempEnchant(slot)
    if on and not enchanted[slot] then
      local w = weaponIn(slot)
      if w and now() - lastUse.at <= 1.5 and (lastUse.item or lastUse.spell) then
        local e = db[w]
        local item, spell = lastUse.item, (not lastUse.item) and lastUse.spell or nil
        if type(e) ~= "table" or e.item ~= item or e.spell ~= spell then e = { item = item, spell = spell, hits = 0 }; db[w] = e end
        e.hits = (e.hits or 0) + 1
      end
    end
    enchanted[slot] = on and true or false
  end
end
R.WatchWeapons = watchWeapons
-- the bare weapons with a habit to put back: { slot, weapon, item or spell } each (a list reused)
local bare, barePool = {}, {}
function R.BareWeapons()
  for i = #bare, 1, -1 do bare[i] = nil end
  local db = weaponDB()
  local bagsNow = R.Bags()
  for _, slot in ipairs(HANDS) do
    local w = weaponIn(slot)
    local e = w and db[w]
    if type(e) == "table" and (e.hits or 0) >= 2 and tempEnchant(slot) == false then
      if (e.item and bagsNow[e.item]) or (e.spell and QB.Camp and QB.Camp.Knows(e.spell)) then
        local b = barePool[#bare + 1]
        if not b then b = {}; barePool[#bare + 1] = b end
        b.slot, b.weapon, b.item, b.spell = slot, w, e.item, e.spell
        bare[#bare + 1] = b
      end
    end
  end
  return bare
end
R.Add({ key = "weapon", neverName = "your weapon", piece = "buffs", order = 110, row = "buffs", cat = "buffs", groups = { "buffs" },
  read = function(add, ctx)
    for _, b in ipairs(R.BareWeapons()) do
      local rec = add()
      rec.key = "weapon" .. b.slot
      rec.never, rec.neverName = "weapon", "your weapon"
      if b.item then
        local okT, tex = pcall(C_Item.GetItemIconByID, b.item)
        rec.tex = (okT and plain(tex)) or 134400
        R.Click(rec, "item", b.item, nil, b.slot)
      else
        rec.tex = (C_Spell and C_Spell.GetSpellTexture and plain(select(2, pcall(C_Spell.GetSpellTexture, b.spell)))) or 134400
        R.Click(rec, "spell", b.spell)
      end
      rec.lit, rec.name = true, b.slot == 16 and "Your weapon" or "Your off-hand"
      rec.why, rec.clickWord = "Nothing on it: you usually put this on.", "put it on"
    end
  end,
})

----------------------------------------------------------------------------
-- Before the pull: food if not Well Fed (the best you carry), every flask or elixir you carry whose aura is not on you
-- (C_Item.GetItemSpell), one of a pair that take each other's place (learned: using elixir B took elixir A's aura away
-- within the same second; 64 pairs, account-wide), and your weapon's habit. Carried none: nothing here, where buying is
-- no longer possible; Buy on Reminders the next time you are in town
----------------------------------------------------------------------------
local function pairsDB()
  local a = QB.Camp and QB.Camp.AcctDB and QB.Camp.AcctDB()
  if not a then return {} end
  if type(a.pairs) ~= "table" then a.pairs = {} end
  return a.pairs
end
-- the elixirs' group (an elixir and every one it is known to replace share the lowest id among them)
local function groupOf(id)
  local p = pairsDB()
  local g, seen = id, 0
  while p[g] and p[g] < g and seen < 64 do g = p[g]; seen = seen + 1 end
  return g
end
R.ElixirGroup = groupOf
local function learnPair(a, b)
  local p = pairsDB()
  local n = 0
  for _ in pairs(p) do n = n + 1 end
  if n >= 64 then return end
  local ga, gb = groupOf(a), groupOf(b)
  if ga == gb then return end
  local lo, hi = math.min(ga, gb), math.max(ga, gb)
  p[hi] = lo
end
R.LearnPair = learnPair
local auraOf = {} -- [item id] = its aura's spell (GetItemSpell), read once
local function itemAura(id)
  local v = auraOf[id]
  if v ~= nil then return v or nil end
  v = false
  if C_Item and type(C_Item.GetItemSpell) == "function" then
    local ok, _, sp = pcall(C_Item.GetItemSpell, id)
    sp = ok and plain(sp) or nil
    if type(sp) == "number" then v = sp end
  end
  auraOf[id] = v
  return v or nil
end
R.ItemAura = itemAura
local onFlask = {} -- [aura spell] = true, the flasks' and elixirs' auras on you at the last look
local flaskBuf, groupSeen = {}, {}
R.Add({ key = "pull", piece = "pull", order = 140, row = "buffs", cat = "group", groups = { "buffs", "pull" },
  read = function(add, ctx)
    if not ctx.pull then return end
    local Camp = QB.Camp
    local names, ids = Camp.Mine(ctx)
    if not Camp.Fed(names, ids) then
      local id = Camp.BestFood(true)
      if id then
        local rec = add()
        rec.key = "pullfood"
        local okT, tex = pcall(C_Item.GetItemIconByID, id)
        rec.tex, rec.lit, rec.count = (okT and plain(tex)) or 133945, true, Camp.Count(id)
        R.Click(rec, "item", id)
        rec.never, rec.neverName, rec.name, rec.clickWord = "eat", "Eat", "Well Fed", "eat it"
      end
    end
    for i = #flaskBuf, 1, -1 do flaskBuf[i] = nil end
    for k in pairs(groupSeen) do groupSeen[k] = nil end
    for id in pairs(R.Bags()) do if kindOf(id) == "flask" then flaskBuf[#flaskBuf + 1] = id end end
    table.sort(flaskBuf)
    -- (a group already on you, by any of its auras, asks nothing; one icon for a group)
    for _, id in ipairs(flaskBuf) do
      local sp = itemAura(id)
      if sp and ids[sp] then groupSeen[groupOf(id)] = true end
    end
    for _, id in ipairs(flaskBuf) do
      local sp = itemAura(id)
      local g = groupOf(id)
      if sp and not ids[sp] and not groupSeen[g] then
        groupSeen[g] = true
        local rec = add()
        rec.key = "flask" .. id
        local okT, tex = pcall(C_Item.GetItemIconByID, id)
        rec.tex, rec.lit, rec.count = (okT and plain(tex)) or 134400, true, Camp.Count(id)
        R.Click(rec, "item", id)
        rec.never = "flask:" .. g
        local okN, name = pcall(C_Item.GetItemInfo or GetItemInfo, id)
        rec.name = (okN and plain(name)) or "Elixir"
        rec.neverName, rec.clickWord = rec.name, "drink it"
      end
    end
  end,
})
-- an elixir's aura gone in the same second another's came: the two take each other's place
local function watchFlasks(ids)
  local came, went
  for sp in pairs(onFlask) do if not ids[sp] then went = sp end end
  for id in pairs(R.Bags()) do
    local sp = kindOf(id) == "flask" and itemAura(id)
    if sp and ids[sp] and not onFlask[sp] then came = id end
  end
  if came and went and now() - lastUse.at <= 1.5 then
    for id in pairs(auraOf) do if auraOf[id] == went then learnPair(came, id) end end
  end
  for k in pairs(onFlask) do onFlask[k] = nil end
  for id in pairs(R.Bags()) do
    local sp = kindOf(id) == "flask" and itemAura(id)
    if sp and ids[sp] then onFlask[sp] = true end
  end
end
R.WatchFlasks = watchFlasks
-- your cast (UNIT_SPELLCAST_SUCCEEDED, yours alone): what it was, and the item it came from, for the weapon's habit, the
-- elixirs' pairs and Buy's kinds you use
function R.OnCast(unit, _, spell)
  if plain(unit) ~= "player" then return end
  local sp = plain(spell)
  if type(sp) ~= "number" then return end
  lastUse.at, lastUse.spell, lastUse.item = now(), sp, nil
  if fighting() then return end -- (the hud review: never a bag read in a fight; a cast in one is its spell alone)
  for id in pairs(R.Bags()) do
    if itemAura(id) == sp then
      lastUse.item = id
      local k = kindOf(id)
      if k == "flask" or k == "heal" or k == "mana" then used()[k] = true end
      break
    end
  end
end

----------------------------------------------------------------------------
-- events, by group (a payload that can be secret is never read)
----------------------------------------------------------------------------
R.EVENTS = {
  buffs = { "SPELLS_CHANGED", "WEAPON_ENCHANT_CHANGED" },
  party = { "GROUP_ROSTER_UPDATE", "UNIT_CONNECTION", "UNIT_IN_RANGE_UPDATE" },
  camp = { "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "PLAYER_UPDATE_RESTING", "PLAYER_MOUNT_DISPLAY_CHANGED",
           "PLAYER_SOFT_INTERACT_CHANGED", "BAG_UPDATE_DELAYED" },
  upkeep = { "UPDATE_INVENTORY_ALERTS", "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "MERCHANT_SHOW", "MERCHANT_CLOSED",
             "PLAYER_UPDATE_RESTING", "BAG_OVERFLOW_WITH_FULL_INVENTORY" },
  class = { "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "PLAYER_LEVEL_UP", "PLAYER_LEVEL_CHANGED", "SPELLS_CHANGED",
            "LEARNED_SPELL_IN_SKILL_LINE", "TRAINER_SHOW", "TRAINER_CLOSED", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
            "ZONE_CHANGED_NEW_AREA", "TAXI_NODE_STATUS_CHANGED", "UI_INFO_MESSAGE", "PLAYER_STOPPED_MOVING" },
  away = { "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
           "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "CINEMATIC_START", "CINEMATIC_STOP" },
  pull = { "READY_CHECK", "READY_CHECK_FINISHED" },
  all = { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "ADDON_RESTRICTION_STATE_CHANGED" },
}
-- each event's groups, and the providers that hear it (p.on[event] = function(...))
local groupsOf, hearers = {}, {}
local function index()
  for g, list in pairs(R.EVENTS) do
    for _, e in ipairs(list) do groupsOf[e] = groupsOf[e] or {}; table.insert(groupsOf[e], g) end
  end
end
-- (the unit events are on frames of their own, for you alone: never every unit's on the main frame)
local OWN_UNIT = { UNIT_AURA = true, UNIT_SPELLCAST_SUCCEEDED = true, UNIT_INVENTORY_CHANGED = true }
function R.Hear(event, fn)
  hearers[event] = hearers[event] or {}
  table.insert(hearers[event], fn)
  if R.frame and not groupsOf[event] and not OWN_UNIT[event] then pcall(R.frame.RegisterEvent, R.frame, event) end
end

local auraBits = { player = "buffs", party = "party" }
function R.OnEvent(event, a1, a2, ...)
  for _, fn in ipairs(hearers[event] or {}) do fn(event, a1, a2, ...) end
  if event == "PLAYER_REGEN_DISABLED" then
    if pull.untilT then pull.untilT = nil end
    after.gen = after.gen + 1 -- (a new fight: the wait after the last one is off)
    after.waiting = true
    if not driven and holder then holder:SetAlpha(0) end
    return
  elseif event == "PLAYER_REGEN_ENABLED" then
    fightOver()
    return
  elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
    -- (it comes before a restriction starts and after one ends; IsAddOnRestrictionActive reads false during it,
    -- RestrictedActionsDocumentation.lua:58: the end is looked at on the next frame, as Pins.lua does)
    local inactive = Enum and Enum.AddOnRestrictionState and Enum.AddOnRestrictionState.Inactive or 0
    if plain(a2) == inactive and not fighting() then
      -- (the hud review: one ending in the 2 s after a fight, the Encounter's or Combat's own end, is that wait's: the
      -- after-fight timer brings the pieces back with their fade, never a flash before it)
      if C_Timer and C_Timer.After then C_Timer.After(0, QB.Safe(function()
          if after.gen > 0 and after.waiting then return end
          if not R.Blocked() then after.waiting = false; R.Refresh() end
        end, "reminders"))
      end
    end
    return
  elseif event == "BAG_UPDATE_DELAYED" then
    -- (one scan for a burst, half a second on)
    if bagSoon then return end
    bagSoon = true
    if C_Timer and C_Timer.After then
      C_Timer.After(0.5, QB.Safe(function()
        bagSoon = false
        bagsStale = true
        dirty.camp, dirty.upkeep, dirty.buffs, dirty.pull = true, true, true, true
        R.Dirty("upkeep")
      end, "reminders: bags"))
      return
    end
    bagSoon, bagsStale = false, true
  elseif event == "LEARNED_SPELL_IN_SKILL_LINE" then R.ForgetUse()
  elseif event == "MERCHANT_SHOW" then merchantOpen = true; R.NoteMerchant()
  elseif event == "MERCHANT_CLOSED" then merchantOpen = false
  elseif event == "BAG_OVERFLOW_WITH_FULL_INVENTORY" then overflowAt = now()
  elseif event == "WEAPON_ENCHANT_CHANGED" then watchWeapons()
  elseif event == "PLAYER_STARTED_MOVING" then R.Started()
  elseif event == "PLAYER_STOPPED_MOVING" then R.Stopped()
  elseif event == "CINEMATIC_START" then inCinematic = true
  elseif event == "CINEMATIC_STOP" then inCinematic = false
  elseif event == "READY_CHECK" then
    R.Pull(600, 0)
  elseif event == "READY_CHECK_FINISHED" then R.PullEnd(10)
  elseif event == "PLAYER_ENTERING_WORLD" then
    if R.InstanceKind() == "raid" then R.Pull(60, 5) elseif pull.untilT then R.PullEnd() end
  end
  local gs = groupsOf[event]
  if gs then for _, g in ipairs(gs) do dirty[g] = true end end
  R.Dirty(gs and gs[1] or "all")
end

function R:Init()
  if self.frame then return end
  index()
  local f = CreateFrame("Frame")
  self.frame = f
  f:SetScript("OnEvent", QB.Safe(function(_, event, ...) R.OnEvent(event, ...) end, "reminders"))
  for e in pairs(groupsOf) do pcall(f.RegisterEvent, f, e) end
  for e in pairs(hearers) do if not groupsOf[e] and not OWN_UNIT[e] then pcall(f.RegisterEvent, f, e) end end
  -- your auras and your party's, each its own frame and bit, the payload never read (secret while auras are
  -- restricted, UnitAuraDocumentation.lua:643-645); your own casts alone (RegisterUnitEvent)
  local function unitFrame(bit, ...)
    local u = CreateFrame("Frame")
    u:SetScript("OnEvent", QB.Safe(function(_, event, ...)
      for _, fn in ipairs(hearers[event] or {}) do fn(event, ...) end
      dirty[bit] = true
      if bit == "buffs" then dirty.camp = true; dirty.pull = true end
      R.Dirty(bit)
    end, "reminders: auras"))
    if u.RegisterUnitEvent then pcall(u.RegisterUnitEvent, u, "UNIT_AURA", ...) else pcall(u.RegisterEvent, u, "UNIT_AURA") end
    return u
  end
  self.auraFrame = unitFrame("buffs", "player")
  self.partyFrame = unitFrame("party", "party1", "party2", "party3", "party4")
  local cast = CreateFrame("Frame")
  self.castFrame = cast
  cast:SetScript("OnEvent", QB.Safe(function(_, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then R.OnCast(...) else watchWeapons() end
    for _, fn in ipairs(hearers[event] or {}) do fn(event, ...) end
    dirty.camp, dirty.buffs, dirty.upkeep = true, true, true
    R.Dirty("camp")
  end, "reminders: casts"))
  for _, e in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_INVENTORY_CHANGED" }) do
    if cast.RegisterUnitEvent then pcall(cast.RegisterUnitEvent, cast, e, "player") else pcall(cast.RegisterEvent, cast, e) end
  end
  frames()
  R.Dirty("all")
end

----------------------------------------------------------------------------
-- /qb buffs: Buffs now, its Not now forgotten; the one line a reminder ever prints is its reply
----------------------------------------------------------------------------
function R.Command()
  if fighting() then QB:Print("Not in a fight: type /qb buffs after it.") return end
  pieceSnooze.buffs = nil
  R.Refresh()
  if #shown.buffs + #shown.party + #shown.pull == 0 then QB:Print("No buffs missing.") end
end

-- the shared reads Cute's dashboard takes too (one answer for both)
local API = QB.API
-- unspent talent points: the talent frame's own question on this client (C_ClassTalents.HasUnspentTalentPoints,
-- ClassTalentsDocumentation.lua:195, as MainMenuBarMicroButtons.lua:799 asks it); nil where the client cannot say
function API.UnspentTalents()
  local CT = C_ClassTalents
  if CT and type(CT.HasUnspentTalentPoints) == "function" then
    local ok, v = pcall(CT.HasUnspentTalentPoints)
    v = ok and plain(v) or nil
    if type(v) == "boolean" then return v end
  end
  if type(GetNumUnspentTalents) == "function" then
    local ok, n = pcall(GetNumUnspentTalents)
    n = ok and plain(n) or nil
    if type(n) == "number" then return n > 0 end
  end
  return nil
end
-- the worst of your gear's durability as the game's own figure shows it: 0 none, 1 low, 2 broken
-- (GetInventoryAlertStatus over INVENTORY_ALERT_STATUS_SLOTS' eleven, DurabilityFrame.lua:1-12, 73, 87); nil where the
-- game repairs nothing (Enum.GameRule.RepairArmorDisabled, :52)
function API.Durability()
  local GR = C_GameRules
  if GR and type(GR.IsGameRuleActive) == "function" and Enum and Enum.GameRule and Enum.GameRule.RepairArmorDisabled
    and yes(GR.IsGameRuleActive, Enum.GameRule.RepairArmorDisabled) then return nil end
  if type(GetInventoryAlertStatus) ~= "function" then return nil end
  local worst = 0
  for i = 1, 11 do
    local ok, v = pcall(GetInventoryAlertStatus, i)
    v = ok and plain(v) or nil
    if type(v) == "number" and v > worst then worst = v end
  end
  return worst
end
-- general bag slots free (bags 0 to NUM_BAG_SLOTS, bag family 0 only: the reagent bag and a profession's bag are not
-- counted; C_Container.GetContainerNumFreeSlots, ContainerDocumentation.lua:297); nil where the client cannot say
function API.FreeSlots()
  local CC = C_Container
  if not (CC and type(CC.GetContainerNumFreeSlots) == "function") then return nil end
  local free, any = 0, false
  for bag = 0, (type(NUM_BAG_SLOTS) == "number" and NUM_BAG_SLOTS or 4) do
    local ok, n, family = pcall(CC.GetContainerNumFreeSlots, bag)
    n, family = ok and plain(n) or nil, ok and plain(family) or nil
    if type(n) == "number" and (family == nil or family == 0) then free = free + n; any = true end
  end
  return any and free or nil
end
