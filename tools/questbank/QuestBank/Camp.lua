-- SPDX-License-Identifier: GPL-3.0-or-later
-- The camp bar: a row of icons, the way a WeakAura shows a buff, up whenever one of them has something to say. Each
-- icon is the game's secure button for its item or spell, so a click is yours: QuestBank only sets what it uses, and
-- only out of a fight. Each has its own switch in Settings:
--   food   Well Fed with its minutes; gone: the food you carry that gives it, lit, a click eats it; none: grey
--   fire   a campfire: the campfire kit you carry and how many (a kit's fire is the one that holds camp features, and
--          on Forever the kit is the fire), else Cooking's Basic Campfire when you know the spell (the Simple Wood you
--          carry, its cooldown); one icon, never both. Lit while a feature waits and no fire is near; a click lights
--          it. A feature to place and no way to light a fire: grey, saying where a kit comes from
--   camp   the best camp feature you can place: the shared one-hour cooldown as a sweep, lit when a campfire is near
--          and the cooldown is up; a click places it
--   bag    the Cozy Sleeping Bag with your Well Rested stacks, lit when you stand still under three; a click unfurls it
-- Alt-drag moves the bar. In a fight it dims and keeps its buttons as they are; in dungeons it hides if asked.
-- Leaving a town without your buffs (an inn or a city: the game's rested state ends) puts a banner above the bar in
-- the same style: "Missing buffs" and an icon each, a click casts it or eats the food. Never in a fight or a dungeon,
-- once per departure, gone after 12 seconds or with its X; /qb buffs shows it any time.
-- What the game tells: your professions (GetProfessions), your bags (Game.ScanItems), your buffs (C_UnitAuras), the
-- spells you know (C_SpellBook.IsSpellKnown), the spell a kit casts (D.CAMP[id].sp, seen on UNIT_SPELLCAST_SUCCEEDED),
-- the campfire under your Interact key, and your rested state (IsResting, PLAYER_UPDATE_RESTING).
local _, QB = ...
local Camp = {}
QB.Camp = Camp

local STILL = 20          -- seconds standing still before the sleeping bag lights
local CAMP_CD = 3600      -- the shared camp cooldown
local TICK = 2            -- seconds between looks
Camp.STILL, Camp.CAMP_CD = STILL, CAMP_CD

local plain = QB.Plain
local function now() return GetTime and GetTime() or 0 end
local function settings()
  local s = QB:Settings()
  if type(s.remind) ~= "table" then s.remind = { camp = true, food = true, bag = true, fire = true, quietInstance = true, buffs = true } end
  if s.remind.fire == nil then s.remind.fire = true end
  if s.remind.buffs == nil then s.remind.buffs = true end
  return s.remind
end
Camp.Settings = settings

-- Basic Campfire (spell 818, Cooking) lights a fire from one Simple Wood (4470) and has a 5-minute cooldown (the
-- client's SpellReagents and SpellCooldowns). Classic Era's cooks learn it with the skill; Forever's tables
-- (1.60.1.70338) mark it never learned, and Forever's own Basic Campfire (1229737) is a recipe that makes the Basic
-- Campfire Kit (279981) from the same wood: there the kit is the fire
Camp.FIRE_SPELL, Camp.FIRE_ICON, Camp.WOOD, Camp.BASIC_KIT = 818, 135805, 4470, 279981

-- the long buffs each class keeps on itself, Classic's: the class's rows in the client's SkillLineAbility, the same ids
-- on Forever (1.60.1.70338) and Classic Era (1.15.9). Each entry is one buff to have: the spells that give it (the one
-- last seen on you first, then in this order), each with its icon and its ranks, lowest first. The highest rank you
-- know is cast; any rank counts as on, and so do the names in also (a group version, another aspect or blessing).
-- Battle Shout and the other short ones are left out
Camp.SELF = {
  MAGE = {
    { { "Arcane Intellect", 135932, { 1459, 1460, 1461, 10156, 10157 } }, also = { "Arcane Brilliance" } },
    { { "Ice Armor", 135843, { 7302, 7320, 10219, 10220 } }, { "Frost Armor", 135843, { 168, 7300, 7301 } },
      { "Mage Armor", 135991, { 6117, 22782, 22783 } } },
  },
  PRIEST = {
    { { "Power Word: Fortitude", 135987, { 1243, 1244, 1245, 2791, 10937, 10938 } }, also = { "Prayer of Fortitude" } },
    { { "Inner Fire", 135926, { 588, 7128, 602, 1006, 10951, 10952 } } },
  },
  DRUID = {
    { { "Mark of the Wild", 136078, { 1126, 5232, 6756, 5234, 8907, 9884, 9885 } }, also = { "Gift of the Wild" } },
    { { "Thorns", 136104, { 467, 782, 1075, 8914, 9756, 9910 } } },
  },
  WARLOCK = {
    { { "Demon Armor", 136185, { 706, 1086, 11733, 11734, 11735 } }, { "Demon Skin", 136185, { 687, 696 } } },
  },
  SHAMAN = {
    { { "Lightning Shield", 136051, { 324, 325, 905, 945, 8134, 10431, 10432 } } },
  },
  HUNTER = {
    { { "Aspect of the Hawk", 136076, { 13165, 14318, 14319, 14320, 14321, 14322, 25296 } }, { "Aspect of the Monkey", 132159, { 13163 } },
      also = { "Aspect of the Cheetah", "Aspect of the Pack", "Aspect of the Wild", "Aspect of the Beast" } },
  },
  PALADIN = {
    { { "Blessing of Might", 135906, { 19740, 19834, 19835, 19836, 19837, 19838, 25291 } },
      { "Blessing of Wisdom", 135970, { 19742, 19850, 19852, 19853, 19854, 25290 } },
      also = { "Blessing of Kings", "Blessing of Salvation", "Blessing of Light", "Blessing of Sanctuary", "Greater Blessing of Might",
               "Greater Blessing of Wisdom", "Greater Blessing of Kings", "Greater Blessing of Salvation", "Greater Blessing of Light" } },
  },
}

-- a spell you know: C_SpellBook.IsSpellKnown, or IsPlayerSpell on a client without it
local function knows(id)
  if C_SpellBook and type(C_SpellBook.IsSpellKnown) == "function" then
    local ok, v = pcall(C_SpellBook.IsSpellKnown, id)
    if ok then return plain(v) == true end
  end
  if type(IsPlayerSpell) == "function" then
    local ok, v = pcall(IsPlayerSpell, id)
    return ok and plain(v) == true
  end
  return false
end
Camp.Knows = knows
-- (the C_Spell calls, or the old globals of a client without them)
local function spellIcon(id, fallback)
  local get = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
  if type(get) == "function" then
    local ok, tex = pcall(get, id)
    tex = ok and plain(tex) or nil
    if tex then return tex end
  end
  return fallback
end
-- its name in the player's language, for the aura it puts on you
local function spellName(id, fallback)
  local get = C_Spell and C_Spell.GetSpellName or GetSpellInfo
  if type(get) == "function" then
    local ok, n = pcall(get, id)
    n = ok and plain(n) or nil
    if type(n) == "string" and n ~= "" then return n end
  end
  return fallback
end
-- a spell's cooldown, start and duration; 0, 0 when ready, on the global cooldown or unreadable
local function spellCD(id)
  local start, dur
  if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
    local ok, cd = pcall(C_Spell.GetSpellCooldown, id)
    cd = ok and plain(cd) or nil
    if type(cd) == "table" then start, dur = plain(cd.startTime), plain(cd.duration) end
  elseif type(GetSpellCooldown) == "function" then
    local ok, a, b = pcall(GetSpellCooldown, id)
    if ok then start, dur = plain(a), plain(b) end
  end
  if type(start) ~= "number" or type(dur) ~= "number" or start <= 0 or dur <= 1.5 then return 0, 0 end
  return start, dur
end

-- your professions by name, with the skill
function Camp.Professions()
  local out = {}
  if not (GetProfessions and GetProfessionInfo) then return out end
  local ok, a, b, _, fish, cook, aid = pcall(GetProfessions)
  if not ok then return out end
  for _, i in ipairs({ a, b, fish, cook, aid }) do
    if i then
      local okI, name, _, skill = pcall(GetProfessionInfo, i)
      name, skill = plain(name), plain(skill)
      if okI and type(name) == "string" and type(skill) == "number" then out[name] = skill end
    end
  end
  return out
end

-- your helpful auras by name: the stacks of one (Camp.Buffs), or what the game says of it (Camp.Auras: stacks, when
-- it runs out on GetTime's clock, its icon); Camp.Auras also gives the set of their spell ids
function Camp.Auras()
  local out, ids = {}, {}
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if get then
    for i = 1, 60 do
      local ok, a = pcall(get, "player", i, "HELPFUL")
      if not ok or type(a) ~= "table" then break end
      local n, id = plain(a.name), plain(a.spellId)
      if type(id) == "number" and id > 0 then ids[id] = true end
      if type(n) == "string" then
        local exp = plain(a.expirationTime)
        out[n] = { n = plain(a.applications) or 1, exp = type(exp) == "number" and exp > 0 and exp or nil, icon = plain(a.icon) }
      end
    end
  end
  return out, ids
end
function Camp.Buffs()
  local out = {}
  for n, a in pairs(Camp.Auras()) do out[n] = a.n end
  return out
end

local function carried()
  local set = {}
  for _, id in ipairs(QB.Game and QB.Game.ScanItems and QB.Game.ScanItems() or {}) do set[id] = true end
  return set
end

-- the camp features you carry and can place: your profession's skill meets the item's
function Camp.Placeable(bags, profs)
  bags, profs = bags or carried(), profs or Camp.Professions()
  local out = {}
  for id, e in pairs(QB.Data.CAMP or {}) do
    if e.t == "feature" and bags[id] and e.p and (profs[e.p] or 0) >= (e.s or 0) then out[#out + 1] = { id = id, e = e } end
  end
  table.sort(out, function(a, b) return (a.e.s or 0) > (b.e.s or 0) or ((a.e.s or 0) == (b.e.s or 0) and a.e.n < b.e.n) end)
  -- a higher tier makes its base pointless: keep the best of each profession
  local best, seen = {}, {}
  for _, x in ipairs(out) do if not seen[x.e.p] then seen[x.e.p] = true; best[#best + 1] = x end end
  return best
end

-- the campfire kits you carry, the best first
function Camp.Kits(bags)
  bags = bags or carried()
  local out = {}
  for id, e in pairs(QB.Data.CAMP or {}) do if e.t == "kit" and bags[id] then out[#out + 1] = { id = id, e = e } end end
  table.sort(out, function(a, b) return (a.e.s or 0) > (b.e.s or 0) end)
  return out
end

-- the foods you carry that make you Well Fed
function Camp.Foods(bags)
  bags = bags or carried()
  local out = {}
  for id, e in pairs(QB.Data.FOOD or {}) do if bags[id] then out[#out + 1] = { id = id, e = e } end end
  table.sort(out, function(a, b) return a.e.n < b.e.n end)
  return out
end

-- how you can light a campfire now: { kit = Camp.Kits' first } or { spell = Basic Campfire }, or nil. A kit you carry
-- comes first, feature waiting or not: its fire is the one that holds camp features, and on Forever the kit is the
-- fire (Basic Campfire there is the recipe that makes it). The spell only when you carry no kit
function Camp.Fire(bags)
  local kit = Camp.Kits(bags)[1]
  if kit then return { kit = kit } end
  if knows(Camp.FIRE_SPELL) then return { spell = Camp.FIRE_SPELL } end
  return nil
end

-- the class's own buffs (Camp.SELF): the spell of an entry that is on you (true for one of its also names), or nil
local function selfOn(entry, names, ids)
  for _, sp in ipairs(entry) do
    if names[sp[1]] or names[spellName(sp[3][1], sp[1])] then return sp end
    for _, id in ipairs(sp[3]) do if ids[id] then return sp end end
  end
  for _, n in ipairs(entry.also or {}) do if names[n] then return true end end
  return nil
end
local seen = {} -- [class .. entry] = the spell last seen on you of an entry with a choice (this session)
local function myClass()
  local ok, _, class = pcall(UnitClass, "player")
  class = ok and plain(class) or nil
  return type(class) == "string" and class or nil
end
local function noteSelf(names, ids)
  local class = myClass()
  for i, entry in ipairs(Camp.SELF[class] or {}) do
    if #entry > 1 then
      local sp = selfOn(entry, names, ids)
      if type(sp) == "table" then seen[class .. i] = sp[1] end
    end
  end
end
-- the class's buffs you know and don't have on: { id = the highest rank you know, name, icon }, in Camp.SELF's order
function Camp.SelfMissing(names, ids)
  local class, out = myClass(), {}
  for i, entry in ipairs(Camp.SELF[class] or {}) do
    if not selfOn(entry, names, ids) then
      local order = {}
      for _, sp in ipairs(entry) do if sp[1] == seen[class .. i] then table.insert(order, 1, sp) else order[#order + 1] = sp end end
      for _, sp in ipairs(order) do
        local id
        for r = #sp[3], 1, -1 do if knows(sp[3][r]) then id = sp[3][r]; break end end
        if id then out[#out + 1] = { id = id, name = spellName(id, sp[1]), icon = sp[2] }; break end
      end
    end
  end
  return out
end

----------------------------------------------------------------------------
-- the bar
----------------------------------------------------------------------------
local ART = "Interface\\AddOns\\QuestBank\\art\\"
local SIZE, GAP = 40, 6
local ORDER = { "food", "fire", "camp", "bag" }
local bar, icons = nil, {}
local campAt, fireAt, lastMove, lastPos

local function quiet()
  if settings().quietInstance ~= false and IsInInstance then
    local ok, inside = pcall(IsInInstance)
    if ok and plain(inside) == true then return true end
  end
  return false
end
local function fighting() return InCombatLockdown and InCombatLockdown() or false end

local function barFrame()
  if bar then return bar end
  bar = CreateFrame("Frame", "QuestBankCampBar", UIParent)
  bar:SetSize(SIZE, SIZE)
  bar:SetFrameStrata("MEDIUM")
  bar:SetMovable(true)
  bar:SetClampedToScreen(true)
  local pos = settings().pos
  if type(pos) == "table" and pos.x then bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x, pos.y) else bar:SetPoint("CENTER", UIParent, "CENTER", 0, -190) end
  bar.elapsed = 0
  return bar
end

local function moveStart(_, button)
  if button == "LeftButton" and IsAltKeyDown and IsAltKeyDown() and not fighting() then bar:StartMoving(); bar.moving = true end
end
local function moveStop()
  if not bar.moving then return end
  bar.moving = nil
  bar:StopMovingOrSizing()
  local x, y = bar:GetCenter()
  if x then settings().pos = { x = x, y = y } end
end

-- one icon: the game's secure button with the item's or spell's art, a black edge (gold when lit), the cooldown's
-- sweep, minutes at the bottom, a count at the top. hint: a grey last line for its tooltip
local function newIcon(name, parent, hint)
  local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
  b:SetSize(SIZE, SIZE)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b.hint = hint
  b.edge = b:CreateTexture(nil, "BACKGROUND")
  b.edge:SetPoint("TOPLEFT", -1, 1); b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  b.edge:SetColorTexture(0, 0, 0, 1)
  b.glow = b:CreateTexture(nil, "BACKGROUND", nil, -1)
  b.glow:SetTexture(ART .. "glow")
  b.glow:SetBlendMode("ADD")
  b.glow:SetPoint("CENTER")
  b.glow:SetSize(SIZE * 1.9, SIZE * 1.9)
  b.glow:Hide()
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints()
  if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
  b.time = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.time:SetPoint("BOTTOM", 0, 2)
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  b.count:SetPoint("TOPRIGHT", -2, -2)
  b.hi = b:CreateTexture(nil, "HIGHLIGHT")
  b.hi:SetAllPoints()
  b.hi:SetColorTexture(1, 1, 1, 0.12)
  b:SetScript("OnEnter", function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self.tip[1], 1, 0.82, 0.3)
    for i = 2, #self.tip do GameTooltip:AddLine(self.tip[i], 1, 1, 1, true) end
    if self.hint then GameTooltip:AddLine(self.hint, 0.5, 0.5, 0.5) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  return b
end

local function icon(key)
  local b = icons[key]
  if b then return b end
  b = newIcon("QuestBankCamp_" .. key, barFrame(), "Alt-drag moves the bar.")
  b:HookScript("OnMouseDown", moveStart)
  b:HookScript("OnMouseUp", moveStop)
  icons[key] = b
  return b
end

local function mins(sec)
  if not sec or sec <= 0 then return "" end
  if sec >= 3600 then return string.format("%dh", math.floor(sec / 3600 + 0.5)) end
  if sec >= 60 then return string.format("%dm", math.ceil(sec / 60)) end
  return string.format("%ds", math.ceil(sec))
end

local function itemCD(id)
  local get = C_Container and C_Container.GetItemCooldown
  if not (get and id) then return 0, 0 end
  local ok, start, dur = pcall(get, id)
  start, dur = ok and plain(start) or 0, ok and plain(dur) or 0
  if type(start) ~= "number" or type(dur) ~= "number" or dur <= 1.5 then return 0, 0 end
  return start, dur
end

local function count(id)
  local get = C_Item and C_Item.GetItemCount or GetItemCount
  local ok, n = pcall(get, id)
  n = ok and plain(n) or 0
  return type(n) == "number" and n or 0
end

-- the best camp feature's shared cooldown, start and duration (0, 0: ready): the item's own, else the hour since you
-- placed one
local function campCD(best, t)
  local start, dur = itemCD(best.id)
  if dur == 0 and campAt and t - campAt < CAMP_CD then start, dur = campAt, CAMP_CD end
  if dur > 0 and start + dur - t <= 0 then return 0, 0 end
  return start, dur
end
local function fireNear(t) return fireAt ~= nil and t - fireAt < 300 end

-- what each icon shows now: nil to hide it, else { tex, time, count, lit, grey, item or spell, cd = { start, dur }, tip }
function Camp.State()
  local s = settings()
  local out = {}
  local auras, ids = Camp.Auras()
  local bags, t, profs = carried(), now(), Camp.Professions()
  noteSelf(auras, ids)
  if s.food then
    local fed = auras["Well Fed"]
    if fed then
      out.food = { tex = fed.icon or 136000, time = fed.exp and mins(fed.exp - t) or "", tip = { "Well Fed", fed.exp and ("Runs out in " .. mins(fed.exp - t) .. ".") or "" } }
    else
      local foods = Camp.Foods(bags)
      local f = foods[1]
      if f then
        out.food = { tex = "Interface\\Icons\\" .. f.e.i, count = count(f.id), lit = true, item = f.id,
                     tip = { "Not Well Fed", f.e.n .. ": " .. (f.e.g or "Well Fed") .. ". Click to eat." } }
      else
        out.food = { tex = 133945, grey = true, tip = { "Not Well Fed", "No food in your bags that gives Well Fed." } }
      end
    end
  end
  local list = Camp.Placeable(bags, profs)
  if s.camp then
    local best = list[1]
    if best then
      local cdStart, cdDur = campCD(best, t)
      local up = cdDur == 0
      local near = fireNear(t)
      local names = {}
      for i = 1, math.min(4, #list) do names[#names + 1] = list[i].e.n .. (list[i].e.g and (": " .. list[i].e.g) or "") end
      out.camp = { tex = "Interface\\Icons\\" .. best.e.i, lit = up and near, grey = not up, item = best.id, cd = (not up) and { cdStart, cdDur } or nil,
                   time = (not up) and mins(cdStart + cdDur - t) or "",
                   tip = { up and (near and "Place a camp feature" or "Camp features ready") or ("Camp cooldown: " .. mins(cdStart + cdDur - t)),
                           table.concat(names, "\n"), up and (near and "Click to place the first." or "Light a campfire, then click to place the first.") or "All camp features share an hour's cooldown." } }
    end
  end
  if s.fire then
    local waits = out.camp and not out.camp.grey and not fireNear(t)
    local fire = Camp.Fire(bags)
    if fire and fire.spell then
      local st, du = spellCD(fire.spell)
      local up = du == 0 or st + du - t <= 0
      local wood = count(Camp.WOOD)
      out.fire = { tex = spellIcon(fire.spell, Camp.FIRE_ICON), spell = fire.spell, count = wood, grey = wood == 0,
                   lit = wood > 0 and up and waits and true or false, cd = (not up) and { st, du } or nil, time = (not up) and mins(st + du - t) or "",
                   tip = { spellName(fire.spell, "Basic Campfire"), wood > 0 and "Click to light a campfire." or "Needs Simple Wood." } }
    elseif fire and fire.kit then
      local k = fire.kit
      local st, du = itemCD(k.id)
      local up = du == 0 or st + du - t <= 0
      out.fire = { tex = "Interface\\Icons\\" .. k.e.i, count = count(k.id), item = k.id, lit = up and waits and true or false,
                   cd = (not up) and { st, du } or nil, time = (not up) and mins(st + du - t) or "",
                   tip = { k.e.n, string.format("Holds %d camp feature%s. Click to light it.", k.e.cap or 3, (k.e.cap or 3) == 1 and "" or "s") } }
    elseif out.camp then
      -- a feature to place and nothing to light its fire with: where a kit comes from
      local kit = (QB.Data.CAMP or {})[Camp.BASIC_KIT] or {}
      out.fire = { tex = "Interface\\Icons\\" .. (kit.i or "inv_camelot_camping_welcomingcampfire"), grey = true,
                   tip = { "No campfire kit", profs.Cooking and "Cooking's Basic Campfire makes one from Simple Wood." or "A cook makes them from Simple Wood." } }
    end
  end
  if s.bag and bags[211527] then
    local me = QB.API.WorldPosition()
    if me and lastPos and math.abs(me.wx - lastPos.wx) + math.abs(me.wy - lastPos.wy) > 2 then lastMove = t end
    if me then lastPos = me end
    lastMove = lastMove or t
    local rested = auras["Well Rested"]
    local stacks = rested and rested.n or 0
    local still = t - lastMove >= STILL and not (UnitOnTaxi and plain(UnitOnTaxi("player")) == true)
    out.bag = { tex = "Interface\\Icons\\" .. ((QB.Data.CAMP[211527] or {}).i or "inv_misc_bag_bigbagofenchantments"), count = stacks > 0 and stacks or nil,
                time = rested and rested.exp and mins(rested.exp - t) or "", lit = stacks < 3 and still, grey = stacks == 0 and not still, item = 211527,
                tip = { "Well Rested " .. stacks .. "/3", "A minute in the Cozy Sleeping Bag adds a stack of bonus XP. Click to unfurl it." } }
  end
  return out
end

----------------------------------------------------------------------------
-- the missing-buffs banner: your class's own buffs, Well Fed and a camp feature's, when you leave a town without them
----------------------------------------------------------------------------
local BANNER_SECS = 12     -- on screen this long
local QUIET = 60           -- at least this long between two banners of their own accord (a town's edge crossed twice)
local TOP = 34             -- the title's strip above the icons
Camp.BANNER_SECS, Camp.QUIET = BANNER_SECS, QUIET
Camp.shows = 0             -- banners shown, for the tests
local banner, bicons = nil, {}
local shownAt, hideLater, wasRested, pendingAt, lastAuto

local function yes(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, v = pcall(fn, ...)
  return ok and plain(v) == true
end
local function resting() return yes(IsResting) end
local function inInstance() return yes(IsInInstance) end

-- what you could have on and don't, each with what a click does: { tex, item or spell (self: cast on you), count, tip }
function Camp.Missing()
  local s = settings()
  local out = {}
  local names, ids = Camp.Auras()
  local bags, t = carried(), now()
  if s.food and not names["Well Fed"] then
    local f = Camp.Foods(bags)[1]
    if f then
      out[#out + 1] = { key = "food", tex = "Interface\\Icons\\" .. f.e.i, item = f.id, count = count(f.id),
                        tip = { "Well Fed", f.e.n .. ": " .. (f.e.g or "Well Fed") .. ".", "Click to eat it." } }
    end
  end
  for i, sp in ipairs(Camp.SelfMissing(names, ids)) do
    out[#out + 1] = { key = "self" .. i, tex = spellIcon(sp.id, sp.icon), spell = sp.id, self = true, tip = { sp.name, "Click to cast it on yourself." } }
  end
  -- the best feature you can place that gives a buff (D.CAMP's b: a tent, a bot or a workbench gives none), unless its
  -- buff is on you. The aura is the buff's own spell, not the feature's name (the Sharpening Wheel's is Extra Strength)
  local best
  if s.camp then for _, x in ipairs(Camp.Placeable(bags)) do if x.e.b then best = x; break end end end
  if best and select(2, campCD(best, t)) == 0 then
    local on = ids[best.e.b] or names[best.e.bn or ""] or names[spellName(best.e.b, best.e.bn or "")]
    if not on then
      local feat = { key = "camp", tex = "Interface\\Icons\\" .. best.e.i, item = best.id,
                     tip = { best.e.n, (best.e.g or "Its buff") .. " while you sit by it.", "Click to place it." } }
      if not fireNear(t) then
        -- the feature needs a campfire first: the click lights one
        local fire = Camp.Fire(bags)
        feat.item, feat.tip[2], feat.tip[3] = nil, "Needs a campfire first.", "Click to light one."
        if fire and fire.kit then
          feat.tex, feat.item, feat.count = "Interface\\Icons\\" .. fire.kit.e.i, fire.kit.id, count(fire.kit.id)
        elseif fire and fire.spell and count(Camp.WOOD) > 0 then
          feat.tex, feat.spell = spellIcon(fire.spell, Camp.FIRE_ICON), fire.spell
        else
          feat = nil
        end
      end
      out[#out + 1] = feat
    end
  end
  return out
end

local function bannerFrame()
  if banner then return banner end
  banner = CreateFrame("Frame", "QuestBankBuffBanner", UIParent)
  banner:SetFrameStrata("MEDIUM")
  banner:SetClampedToScreen(true)
  banner:SetSize(160, TOP + SIZE + 12)
  banner:SetPoint("BOTTOM", barFrame(), "TOP", 0, 14) -- above the camp bar, wherever it was dragged
  -- a dark plate with a black edge, as a WeakAura's
  banner.edge = banner:CreateTexture(nil, "BACKGROUND", nil, -2)
  banner.edge:SetAllPoints()
  banner.edge:SetColorTexture(0, 0, 0, 0.9)
  banner.plate = banner:CreateTexture(nil, "BACKGROUND", nil, -1)
  banner.plate:SetPoint("TOPLEFT", 1, -1)
  banner.plate:SetPoint("BOTTOMRIGHT", -1, 1)
  banner.plate:SetColorTexture(0.08, 0.08, 0.09, 0.9)
  banner.title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  banner.title:SetPoint("TOPLEFT", 12, -11)
  banner.title:SetText("Missing buffs")
  banner.close = CreateFrame("Button", nil, banner, "UIPanelCloseButton")
  banner.close:SetPoint("TOPRIGHT", -4, -4)
  banner.close:SetScript("OnClick", QB.Safe(function() Camp.HideBanner() end, "buff banner: close"))
  -- the time left, a gold line along the bottom that runs out
  banner.left = banner:CreateTexture(nil, "ARTWORK")
  banner.left:SetPoint("BOTTOMLEFT", 1, 1)
  banner.left:SetSize(158, 2)
  banner.left:SetColorTexture(1, 0.75, 0.2, 0.85)
  banner:SetScript("OnUpdate", QB.Safe(function(self)
    if not shownAt then return end
    local left = BANNER_SECS - (now() - shownAt)
    self.left:SetWidth(math.max(1, (self:GetWidth() - 2) * math.max(0, left) / BANNER_SECS))
    if left <= 0 then Camp.HideBanner() end
  end, "buff banner"))
  banner:Hide()
  return banner
end
Camp.BannerFrame = bannerFrame

-- the icons, centred under the title: the game's secure buttons, set out of a fight only
local function layBanner(list)
  local f = bannerFrame()
  local n = #list
  local row = n * SIZE + (n - 1) * GAP
  local w = math.max(row + 24, 160)
  f:SetSize(w, TOP + SIZE + 12)
  local x = math.floor((w - row) / 2)
  for i, d in ipairs(list) do
    local b = bicons[i]
    if not b then b = newIcon("QuestBankBuff_" .. i, f); bicons[i] = b end
    b.icon:SetTexture(d.tex)
    b.icon:SetDesaturated(false)
    b.icon:SetAlpha(1)
    b.time:SetText("")
    b.count:SetText(d.count and d.count > 1 and tostring(d.count) or "")
    b.glow:Hide()
    b.edge:SetColorTexture(1, 0.75, 0.2, 1)
    b.cd:SetCooldown(0, 0)
    b.tip, b.state = d.tip, d
    b:SetAttribute("type", d.item and "item" or "spell")
    b:SetAttribute("item", d.item and ("item:" .. d.item) or nil)
    b:SetAttribute("spell", d.spell)
    b:SetAttribute("unit", d.self and "player" or nil)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -TOP)
    b:Show()
    x = x + SIZE + GAP
  end
  for i = n + 1, #bicons do bicons[i]:Hide() end
end

function Camp.HideBanner()
  if not banner then return end
  if fighting() then hideLater = true; return end -- its buttons are the game's: they go when the fight is over
  shownAt, hideLater = nil, nil
  banner:Hide()
end

-- why: "rest" (you left a town) or "ask" (/qb buffs). True when it shows, else false and why not: fight, instance, none
function Camp.Announce(why)
  if fighting() then return false, "fight" end
  if why ~= "ask" and inInstance() then return false, "instance" end
  local list = Camp.Missing()
  if #list == 0 then return false, "none" end
  layBanner(list)
  shownAt, hideLater = now(), nil
  banner:SetAlpha(1)
  banner:Show()
  Camp.shows = Camp.shows + 1
  return true
end

-- on screen: what is still missing (a buff cast, the food eaten, a fire lit), dimmed in a fight
function Camp.RefreshBanner()
  if not (banner and banner:IsShown()) then return end
  if fighting() then banner:SetAlpha(0.45); return end
  banner:SetAlpha(1)
  if hideLater then Camp.HideBanner(); return end
  local list = Camp.Missing()
  if #list == 0 then Camp.HideBanner() else layBanner(list) end
end

-- you left a town: the banner once, not in a fight (then when it ends, within a minute), on a flight or dead
local function departed()
  pendingAt = nil
  if not settings().buffs then return end
  if lastAuto and now() - lastAuto < QUIET then return end
  if fighting() then pendingAt = now(); return end
  if yes(UnitOnTaxi, "player") or yes(UnitIsDeadOrGhost, "player") then return end
  if Camp.Announce("rest") then lastAuto = now() end
end

-- /qb buffs
function Camp.Command()
  local ok, why = Camp.Announce("ask")
  if ok then return end
  QB:Print(why == "fight" and "Not in a fight: type /qb buffs after it." or "No buffs missing.")
end

function Camp.Refresh()
  Camp.RefreshBanner()
  local f = barFrame()
  if quiet() then
    if not fighting() then f:Hide() end
    Camp.visible = 0
    return
  end
  local fight = fighting()
  local st = Camp.State()
  local x, n = 0, 0
  for _, key in ipairs(ORDER) do
    -- (a secure button is never made in a fight)
    local d, b = st[key], icons[key] or (not fight and icon(key)) or nil
    if d and b then
      n = n + 1
      b.icon:SetTexture(d.tex)
      b.icon:SetDesaturated(d.grey and true or false)
      b.icon:SetAlpha(d.grey and 0.55 or 1)
      b.time:SetText(d.time or "")
      b.count:SetText(d.count and d.count > 1 and tostring(d.count) or (key == "bag" and d.count and tostring(d.count) or ""))
      b.glow:SetShown(d.lit and true or false)
      b.edge:SetColorTexture(d.lit and 1 or 0, d.lit and 0.75 or 0, d.lit and 0.2 or 0, 1)
      if d.cd then b.cd:SetCooldown(d.cd[1], d.cd[2]) else b.cd:SetCooldown(0, 0) end
      b.tip = d.tip
      b.state = d
      if not fight then
        if b:GetAttribute("alt-type1") ~= "noop" then b:SetAttribute("alt-type1", "noop") end -- Alt-click moves the bar, never uses it
        b:SetAttribute("type", d.item and "item" or (d.spell and "spell") or nil)
        b:SetAttribute("item", d.item and ("item:" .. d.item) or nil)
        b:SetAttribute("spell", d.spell)
        b:ClearAllPoints()
        b:SetPoint("LEFT", f, "LEFT", x, 0)
        b:Show()
      end
      x = x + SIZE + GAP
    elseif b and not fight then
      b:Hide()
    end
  end
  if not fight then
    f:SetSize(math.max(SIZE, x - GAP), SIZE)
    f:SetShown(n > 0 and QB:Settings().campBar ~= false)
  end
  f:SetAlpha(fight and 0.45 or 1)
  Camp.visible = (QB:Settings().campBar ~= false) and n or 0
end

function Camp.CooldownLeft()
  if not campAt then return 0 end
  return math.max(0, CAMP_CD - (now() - campAt))
end

-- a campfire is here: yours lit, or one under your Interact key
function Camp.OnFire()
  fireAt = now()
  Camp.Refresh()
end

-- the camp buffs carry their feature's name, as far as players' games have shown
function Camp.IsCampBuff(name)
  for _, e in pairs(QB.Data.CAMP or {}) do if e.t == "feature" and e.n == name then return true end end
  return false
end

local KIT, FEATURE = {}, {}
local function index()
  for id, e in pairs(QB.Data.CAMP or {}) do
    if e.sp then
      if e.t == "kit" then KIT[e.sp] = id elseif e.t == "feature" then FEATURE[e.sp] = id end
    end
  end
  KIT[Camp.FIRE_SPELL] = true -- Basic Campfire, cast
end

function Camp.OnEvent(event, a1, a2, a3)
  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    if plain(a1) ~= "player" then return end
    local sp = plain(a3)
    if KIT[sp] then Camp.OnFire() end
    if FEATURE[sp] then campAt = now(); Camp.Refresh() end
  elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
    local name = plain(UnitName and UnitName("softinteract"))
    local guid = plain(UnitGUID and UnitGUID("softinteract"))
    if type(name) == "string" and type(guid) == "string" and guid:find("^GameObject") and name:lower():find("campfire", 1, true) then
      if not fireAt or now() - fireAt > 60 then Camp.OnFire() end
    end
  elseif event == "PLAYER_UPDATE_RESTING" then
    local r = resting()
    if wasRested and not r then departed() end
    wasRested = r
  elseif event == "UNIT_AURA" then
    if plain(a1) == "player" then Camp.RefreshBanner() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    Camp.Refresh()
    -- you left town in a fight: the banner now, if it was within the minute and you're still out
    if pendingAt and now() - pendingAt <= QUIET and not resting() then departed() else pendingAt = nil end
  elseif event == "PLAYER_REGEN_DISABLED" or event == "BAG_UPDATE_DELAYED" then
    Camp.Refresh()
  elseif event == "PLAYER_ENTERING_WORLD" then
    lastMove = now()
    wasRested, pendingAt = resting(), nil
    if inInstance() then Camp.HideBanner() end
    Camp.Refresh()
  end
end

function Camp:Init()
  if self.frame then return end
  index()
  local f = CreateFrame("Frame")
  self.frame = f
  f.elapsed = 0
  f:SetScript("OnEvent", QB.Safe(function(_, event, ...) Camp.OnEvent(event, ...) end, "reminders"))
  f:SetScript("OnUpdate", QB.Safe(function(self, dt)
    self.elapsed = self.elapsed + (dt or 0)
    if self.elapsed < TICK then return end
    self.elapsed = 0
    Camp.Refresh()
  end, "camp bar"))
  for _, e in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_SOFT_INTERACT_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                       "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_UPDATE_RESTING" }) do
    pcall(f.RegisterEvent, f, e)
  end
  if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, "UNIT_AURA", "player") else pcall(f.RegisterEvent, f, "UNIT_AURA") end
end
