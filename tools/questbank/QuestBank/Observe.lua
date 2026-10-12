-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank's event probe, the observer's first step. Forever's client is a Midnight client: the combat log is closed
-- to addons and many values arrive as secret values. Before QuestBank records what creatures cast, when, and what
-- vendors sell, it has to know which events hand it readable values on this client. So this counts, per event,
-- how often every read was plain (ok), how often one was secret (sec), how often one was nil (nl), and keeps one
-- sample of the field names with the kind of value each held: never the value, never a name.
--   QuestBankDB.diag.ev[event] = { n, ok, sec, nl, s = { field = "string"|"number"|"boolean"|"table"|"secret"|"nil"|"none" } }
-- ("none": nothing there and that is normal, as a unit not casting; "nil": the call gave nothing or is missing)
-- Only on the Forever client, under the same Settings box as the item notes (unticking clears it). Only reads:
-- nothing is cast, moved or targeted, so the game has nothing of QuestBank's to block. /qb events lists the counts.
local _, QB = ...
local Observe = {}
QB.Observe = Observe

local MAX_KEYS = 60 -- events kept; a new one past that is not counted
Observe.MAX_KEYS = MAX_KEYS
Observe.NIL = {}    -- a handler's way to say "this read was nil" (a nil in a table has no key): the API gave nothing
Observe.NONE = {}   -- "nothing there, and that is normal": no cast going on, no wares; never counted as missing

local plain = QB.Plain

-- counting: the Forever client, with the Settings box ticked (the same box as the item, spell and loot notes)
function Observe.On() return (QB.Game and QB.Game.On()) and true or false end

local function kindOf(v)
  if v == Observe.NIL then return "nil" end
  if v == Observe.NONE then return "none" end
  if issecretvalue and issecretvalue(v) then return "secret" end
  if v == nil then return "nil" end
  return type(v)
end

-- one event's counts; nil when the table is full and the event is new
local function slot(event)
  if not QuestBankDB then return end
  QuestBankDB.diag = QuestBankDB.diag or {}
  local all = QuestBankDB.diag.ev
  if type(all) ~= "table" then
    all = {}
    QuestBankDB.diag.ev = all
  end
  local r = all[event]
  if type(r) ~= "table" then
    local n = 0
    for _ in pairs(all) do n = n + 1 end
    if n >= MAX_KEYS then return end
    r = { n = 0, ok = 0, sec = 0, nl = 0, s = {} }
    all[event] = r
  end
  return r
end

-- count one event's reads. reads = { field = value }: what the handler read, as the client gave it (Observe.NIL
-- for a nil). The first call's field kinds are the sample; values are never kept
function Observe.Note(event, reads)
  local r = slot(event)
  if not r then return end
  r.n = r.n + 1
  local secret, missing = false, false
  local sample = next(r.s) == nil
  for field, v in pairs(reads) do
    local k = kindOf(v)
    if k == "secret" then secret = true elseif k == "nil" then missing = true end
    if sample then r.s[field] = k end
  end
  if secret then r.sec = r.sec + 1 end
  if missing then r.nl = r.nl + 1 end
  if not secret and not missing then r.ok = r.ok + 1 end
end

function Observe.Clear()
  if QuestBankDB and type(QuestBankDB.diag) == "table" then QuestBankDB.diag.ev = nil end
end

-- /qb events: every event counted, with its sample's fields and kinds
function Observe.Report(say)
  local all = QuestBankDB and type(QuestBankDB.diag) == "table" and QuestBankDB.diag.ev
  if type(all) ~= "table" or next(all) == nil then say("Event probe: nothing counted yet."); return end
  local keys = {}
  for k in pairs(all) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local r = all[k]
    local fields = {}
    for f, kind in pairs(r.s) do fields[#fields + 1] = f .. "=" .. kind end
    table.sort(fields)
    say(string.format("%s: %d seen, %d ok, %d secret, %d missing (%s)", k, r.n, r.ok, r.sec, r.nl, table.concat(fields, " ")))
  end
end

-- a creature unit: what the player is looking at or fighting. Never the player, the party or a pet themselves:
-- their names are theirs, and the observer wants creatures
local function creatureUnit(unit)
  unit = plain(unit)
  if type(unit) ~= "string" then return nil end
  if unit == "target" or unit == "focus" or unit == "mouseover" or unit == "pettarget" or unit:find("^boss%d$")
    or unit:find("^nameplate%d+$") or unit:find("^party%dtarget$") then return unit end
  return nil
end

local function ourUnit(unit)
  unit = plain(unit)
  return unit == "player" or (type(unit) == "string" and unit:find("^party%d$") ~= nil)
end

local NIL, NONE = Observe.NIL, Observe.NONE
local function val(v) if v == nil then return NIL end return v end
local function opt(v) if v == nil then return NONE end return v end -- (a value that is often, rightly, not there)

-- a function's first result, or NIL when the function is missing, errors or returns nil
local function call(fn, ...)
  if not fn then return NIL end
  local ok, v = pcall(fn, ...)
  if not ok or v == nil then return NIL end
  return v
end

-- what the observer would read off a creature unit: who it is, how it is, what it casts
function Observe.ReadUnit(unit)
  local t = { unit = unit }
  t.guid = call(UnitGUID, unit)
  t.name = call(UnitName, unit)
  t.level = call(UnitLevel, unit)
  t.cls = call(UnitClassification, unit)
  t.hp = call(UnitHealth, unit)
  t.hpmax = call(UnitHealthMax, unit)
  if UnitCastingInfo then
    local ok, name, _, _, startMs, _, _, _, _, spellId = pcall(UnitCastingInfo, unit)
    t.cast = ok and opt(name) or NIL
    if ok and name ~= nil then t.castStart, t.castSpell = val(startMs), val(spellId) end
  else t.cast = NIL end
  if UnitChannelInfo then
    local ok, name = pcall(UnitChannelInfo, unit)
    t.chan = ok and opt(name) or NIL
  else t.chan = NIL end
  return t
end

-- the harmful auras on one of us: how many, and the first one's name, spell, source unit and school
function Observe.ReadAuras(unit)
  local t = { unit = unit, n = 0 }
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not get then t.api = NIL; return t end
  for i = 1, 40 do
    local ok, a = pcall(get, unit, i, "HARMFUL")
    if not ok or type(a) ~= "table" then break end
    t.n = t.n + 1
    if t.n == 1 then
      t.name, t.spellId, t.source, t.kind = val(a.name), val(a.spellId), val(a.sourceUnit), val(a.dispelName)
    end
  end
  return t
end

-- a rare's map marker
local function readVignette(id)
  local t = { id = val(id) }
  if not (C_VignetteInfo and C_VignetteInfo.GetVignetteInfo) then t.api = NIL; return t end
  local ok, v = pcall(C_VignetteInfo.GetVignetteInfo, id)
  if not ok or type(v) ~= "table" then t.info = NIL; return t end
  t.objectGUID, t.atlas, t.name = val(v.objectGUID), val(v.atlasName), val(v.name)
  return t
end

-- a vendor: who, how many wares, and the first one's id, price and link
local function readMerchant()
  local t = { guid = call(UnitGUID, "npc") }
  local n = call(GetMerchantNumItems)
  t.items = n
  if type(plain(n)) == "number" and n > 0 then
    t.id = call(GetMerchantItemID, 1)
    if GetMerchantItemInfo then
      local ok, _, _, price = pcall(GetMerchantItemInfo, 1)
      t.price = ok and val(price) or NIL
    else t.price = NIL end
    t.link = call(GetMerchantItemLink, 1)
  end
  return t
end

-- a loot window: how many slots, and the first slot's source (a creature or a chest)
local function readLoot()
  local n = call(GetNumLootItems)
  local t = { slots = n }
  if GetLootSourceInfo and type(plain(n)) == "number" and n > 0 then t.src = call(GetLootSourceInfo, 1) else t.src = NIL end
  return t
end

local function clock() return GetTime and GetTime() or NIL end

Observe.UNIT_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_INTERRUPTED",
                        "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_STOP", "UNIT_HEALTH" }
Observe.EVENTS = { "PLAYER_TARGET_CHANGED", "UNIT_AURA", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "VIGNETTE_MINIMAP_UPDATED",
                   "MERCHANT_SHOW", "LOOT_OPENED", "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

function Observe.OnEvent(event, a1, a2, a3, ...)
  if event == "PLAYER_TARGET_CHANGED" then
    Observe.Note(event, Observe.ReadUnit("target"))
  elseif event == "UNIT_AURA" then
    if ourUnit(a1) then Observe.Note(event, Observe.ReadAuras(plain(a1))) end
  elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
    local unit = creatureUnit(a1)
    if unit then Observe.Note(event, Observe.ReadUnit(unit)) end
  elseif event == "VIGNETTE_MINIMAP_UPDATED" then
    Observe.Note(event, readVignette(a1))
  elseif event == "MERCHANT_SHOW" then
    Observe.Note(event, readMerchant())
  elseif event == "LOOT_OPENED" then
    Observe.Note(event, readLoot())
  elseif event == "ENCOUNTER_START" or event == "ENCOUNTER_END" then
    Observe.Note(event, { id = val(a1), diff = val(a3), t = clock() })
  elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    Observe.Note(event, { t = clock() })
  elseif event:find("^UNIT_") then
    local unit = creatureUnit(a1)
    if not unit then return end
    local t = Observe.ReadUnit(unit)
    if event:find("^UNIT_SPELLCAST") then t.castId, t.spellId = val(a2), val(a3) end
    Observe.Note(event, t)
  else
    Observe.Note(event, { nargs = select("#", a1, a2, a3, ...) })
  end
end

function Observe:Init()
  if self.frame then return end
  local f = CreateFrame("Frame")
  self.frame = f
  if not (QB.Game and QB.Game.Forever()) then return end
  f:SetScript("OnEvent", QB.Safe(function(_, event, ...) if Observe.On() then Observe.OnEvent(event, ...) end end, "event probe"))
  for _, list in ipairs({ Observe.UNIT_EVENTS, Observe.EVENTS }) do
    for _, e in ipairs(list) do pcall(f.RegisterEvent, f, e) end -- (a client without one says no, and nothing more)
  end
end
