# Event probe (QuestBank 3.7.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A hidden diagnostic in QuestBank that counts, per unit event, whether the Forever client hands addons readable values, secret values or nothing, so Part B (the observer) is designed on facts.

**Architecture:** One new file `Observe.lua` (the observer's future home) registers the candidate events on a frame, reads the fields Part B would need, and writes counts plus one type-only sample per event to `QuestBankDB.diag.ev`. No names of players ever; creature names are game data but even those are reduced to their type in samples. The harness drives every event with plain and secret values.

**Tech Stack:** WoW Lua 5.1 (Forever client 1.60.1, Interface 16001), `luajit harness.lua` in tools/questbank, zips built by hand, uploader test via Docker.

## Global Constraints

- Only on the Forever client (`QB.Game.Forever()`), and only under the same Settings box as the item notes (`QB.Game.On()`).
- Every `RegisterEvent` is `pcall`'d; every handler is wrapped in `QB.Safe`; never register `COMBAT_LOG_EVENT_UNFILTERED`.
- Every value from the client passes `QB.Plain` (returns nil for a secret value) before any string op or comparison.
- `QuestBankDB.diag.ev` holds at most 60 event keys; one sample per key; the sample stores field names and value kinds only (`"string"`, `"number"`, `"secret"`, `"nil"`, `"table"`, `"boolean"`).
- Nothing in diag.ev may contain a player, character, guild or realm name. Creature names are not stored either (kinds only).
- Harness must end with `layout problems: 0` and `OK`; uploader tests `python3 tools/build_uploader.py --test` must pass.
- Version bump to 3.7.0 in Core.lua, QuestBank.toc, questbank/index.html (three places: dl-meta, the "Brann runs" line, the footer).

---

### Task 1: Observe.lua skeleton and the diag writer

**Files:**
- Create: `tools/questbank/QuestBank/Observe.lua`
- Modify: `tools/questbank/QuestBank/QuestBank.toc` (add `Observe.lua` after `Loot.lua`)
- Modify: `tools/questbank/QuestBank/Core.lua:2179` (add `if QB.Observe then QB.Observe:Init() end` after Loot's Init)
- Test: `tools/questbank/harness.lua` (new block after the 3.6.2 tooltip block, before the "calls QuestBank never makes" block)

**Interfaces:**
- Produces: `QB.Observe`, with `Observe:Init()`, `Observe.On()`, `Observe.Note(event, reads)` where `reads` is a table `{ field = value, ... }` of what the handler read; `Observe.OnEvent(event, ...)`; `Observe.MAX_KEYS = 60`.
- `QuestBankDB.diag.ev[event] = { n, ok, sec, nl, s = { field = kind } }`.

- [ ] **Step 1: Write the failing harness test**

Append after the 3.6.2 tooltip block (search for `-- 3.6.2: tooltips without a hover`; add before the `calls QuestBank never makes` section):

```lua
----------------------------------------------------------------------------
-- 3.7.0: the event probe (Observe.lua). On the Forever client QuestBank counts, per unit event, whether the game
-- handed it readable values, secret values or nothing, in QuestBankDB.diag.ev, so the observer can be designed on
-- what this client really gives addons. Kinds only: never a name, never a player
----------------------------------------------------------------------------
do
  local c, Q2 = torvald, torvald.QB
  local Ob = Q2.Observe
  local DB = c.env.QuestBankDB
  assert(Ob and Ob.frame and Ob.On() and Ob.frame.__scripts.OnEvent, "the Forever client with the box ticked: the probe is on")
  assert(Ob.MAX_KEYS == 60, "the cap")
  local function ev() return DB.diag and DB.diag.ev or {} end
  Ob.Note("TEST_EVENT", { a = 1, b = "x" })
  local r = ev().TEST_EVENT
  assert(r and r.n == 1 and r.ok == 1 and r.sec == 0 and r.nl == 0 and r.s.a == "number" and r.s.b == "string", "a plain read: counted ok, kinds kept, values not")
  Ob.Note("TEST_EVENT", { a = SECRET.num(), b = "x" })
  r = ev().TEST_EVENT
  assert(r.n == 2 and r.ok == 1 and r.sec == 1 and r.s.a == "number", "a secret read: counted, the first sample stays")
  Ob.Note("TEST_EVENT2", { a = nil, b = SECRET.str() })
  r = ev().TEST_EVENT2
  assert(r.n == 1 and r.ok == 0 and r.sec == 1 and r.nl == 1 and r.s.a == "nil" and r.s.b == "secret", "nil and secret both noted in the sample")
  for i = 1, 70 do Ob.Note("FILL_" .. i, { a = i }) end
  assert(countOf(ev()) <= 60, "no more than 60 event keys")
  local dump = {}
  for k, v in pairs(ev()) do for f, kind in pairs(v.s) do dump[#dump + 1] = k .. f .. kind end end
  assert(not table.concat(dump):find("Torvald", 1, true), "never a player's name")
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd ~/foreverrank/tools/questbank && luajit harness.lua 2>&1 | tail -3`
Expected: an assertion error at "the Forever client with the box ticked: the probe is on" (Q2.Observe is nil).

- [ ] **Step 3: Write Observe.lua**

```lua
-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank's event probe, the observer's first step. Forever's client is a Midnight client: the combat log is closed
-- to addons and many values arrive as secret values. Before QuestBank records what creatures cast, when, and what
-- vendors sell, it has to know which events hand it readable values on this client. So this counts, per event,
-- how often every read was plain (ok), how often one was secret (sec), how often one was nil (nl), and keeps one
-- sample of the field names with the kind of value each held: never the value, never a name.
--   QuestBankDB.diag.ev[event] = { n, ok, sec, nl, s = { field = "string"|"number"|"boolean"|"table"|"secret"|"nil" } }
-- Only on the Forever client, under the same Settings box as the item notes. Only reads: nothing is cast, moved
-- or targeted, so the game has nothing of QuestBank's to block.
local _, QB = ...
local Observe = {}
QB.Observe = Observe

local MAX_KEYS = 60
Observe.MAX_KEYS = MAX_KEYS

local plain = QB.Plain

function Observe.On() return (QB.Game and QB.Game.On()) and true or false end

local function kindOf(v)
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

-- count one event's reads. reads = { field = value }: fields read by the handler, values as the client gave them
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
```

Note: `pairs(reads)` never sees a nil value, so a handler that wants a nil counted stores the kind string itself: pass `{ a = Observe.NIL }`. Add after `kindOf`:

```lua
Observe.NIL = {} -- a handler's way to say "this read was nil" (a nil in a table has no key)
```
and in `kindOf`, first line: `if v == Observe.NIL then return "nil" end`. The test's `{ a = nil, b = SECRET.str() }` must therefore become `{ a = Ob.NIL, b = SECRET.str() }`; change the test.

Then the frame and Init at the end of the file:

```lua
function Observe.OnEvent(event, ...)
  -- (handlers come in Tasks 2 to 4; until then every registered event is counted with its argument count)
  Observe.Note(event, { nargs = select("#", ...) })
end

function Observe:Init()
  if self.frame then return end
  local f = CreateFrame("Frame")
  self.frame = f
  if not (QB.Game and QB.Game.Forever()) then return end
  f:SetScript("OnEvent", QB.Safe(function(_, event, ...) if Observe.On() then Observe.OnEvent(event, ...) end end, "event probe"))
end
```

- [ ] **Step 4: Wire the TOC and Core**

In `QuestBank.toc` add a line `Observe.lua` right after `Loot.lua`. In Core.lua after `if QB.Loot then QB.Loot:Init() end` add `if QB.Observe then QB.Observe:Init() end`.

- [ ] **Step 5: Run the harness**

Run: `cd ~/foreverrank/tools/questbank && luajit harness.lua 2>&1 | tail -3`
Expected: `layout problems: 0` and `OK`.

- [ ] **Step 6: Commit**

```bash
cd ~/foreverrank && git add tools/questbank && git commit -m "QuestBank: event probe skeleton (Observe.lua) counting readable, secret and missing values per event"
```

### Task 2: Unit cast events, unit reads, target changes

**Files:**
- Modify: `tools/questbank/QuestBank/Observe.lua` (replace `Observe.OnEvent`, extend `Init`)
- Test: `tools/questbank/harness.lua` (extend the 3.7.0 block)

**Interfaces:**
- Consumes: `Observe.Note(event, reads)`, `Observe.NIL`.
- Produces: `Observe.UNIT_EVENTS` list; `Observe.ReadUnit(unit)` returning the reads table `{ guid, name, level, cls, hp, hpmax, cast, castId, chan }`.

- [ ] **Step 1: Extend the test**

```lua
  -- the unit cast events: a target casting with everything readable, then a nameplate whose GUID is hidden
  local f = Ob.frame
  local function fire(event, ...) f.__scripts.OnEvent(f, event, ...) end
  c.env.UnitLevel = function(u) if u == "target" or u:find("^nameplate") then return 31 end return c.level or 29 end
  c.env.UnitClassification = function() return "elite" end
  c.env.UnitHealth = function() return 1200 end
  c.env.UnitHealthMax = function() return 4000 end
  c.env.UnitCastingInfo = function() return "Arcane Bolt", "Arcane Bolt", "", 1000, 2500, false, nil, false, 1234 end
  c.env.UnitChannelInfo = function() return nil end
  local guidOf = c.env.UnitGUID
  c.env.UnitGUID = function(u) if u == "target" then return "Creature-0-4455-0-12-245999-0000A1B2C3" end if u:find("^nameplate") then return SECRET.str() end return guidOf(u) end
  fire("UNIT_SPELLCAST_START", "target", "cast-1", 1234)
  r = ev().UNIT_SPELLCAST_START
  assert(r and r.n == 1 and r.ok == 1 and r.s.guid == "string" and r.s.cast == "string" and r.s.castId == "number" and r.s.spellId == "number" and r.s.unit == "string", "a readable cast on the target")
  fire("UNIT_SPELLCAST_START", "nameplate3", "cast-2", 1234)
  r = ev().UNIT_SPELLCAST_START
  assert(r.n == 2 and r.sec == 1, "a nameplate with a hidden GUID counts as secret")
  fire("UNIT_SPELLCAST_START", "player", "cast-3", 1)
  assert(ev().UNIT_SPELLCAST_START.n == 2, "the player's own casts are not the probe's business")
  fire("PLAYER_TARGET_CHANGED")
  assert(ev().PLAYER_TARGET_CHANGED.n == 1 and ev().PLAYER_TARGET_CHANGED.s.guid == "string", "a target change reads the target")
  c.env.UnitGUID = guidOf
```

- [ ] **Step 2: Run to see it fail** (`fire("UNIT_SPELLCAST_START"...)` leaves `ev().UNIT_SPELLCAST_START` nil because Init registered nothing).

- [ ] **Step 3: Implement**

Replace the placeholder `Observe.OnEvent` and `Init` with:

```lua
-- the units worth reading: never the player or the party themselves (their names are theirs)
local function creatureUnit(unit)
  unit = plain(unit)
  if type(unit) ~= "string" then return nil end
  if unit == "target" or unit == "focus" or unit == "mouseover" or unit:find("^boss%d$") or unit:find("^nameplate%d+$")
    or unit:find("^party%dtarget$") or unit == "pettarget" then return unit end
  return nil
end

function Observe.ReadUnit(unit)
  local t = { unit = unit }
  local function get(key, fn, ...)
    if not fn then t[key] = Observe.NIL; return end
    local ok, v = pcall(fn, ...)
    if not ok or v == nil then t[key] = Observe.NIL else t[key] = v end
  end
  get("guid", UnitGUID, unit)
  get("name", UnitName, unit)
  get("level", UnitLevel, unit)
  get("cls", UnitClassification, unit)
  get("hp", UnitHealth, unit)
  get("hpmax", UnitHealthMax, unit)
  if UnitCastingInfo then
    local ok, name, _, _, startMs, endMs, _, _, _, spellId = pcall(UnitCastingInfo, unit)
    t.cast = ok and name ~= nil and name or Observe.NIL
    t.castStart = ok and startMs ~= nil and startMs or Observe.NIL
    t.castSpell = ok and spellId ~= nil and spellId or Observe.NIL
  else t.cast = Observe.NIL end
  if UnitChannelInfo then
    local ok, name = pcall(UnitChannelInfo, unit)
    t.chan = ok and name ~= nil and name or Observe.NIL
  else t.chan = Observe.NIL end
  return t
end

Observe.UNIT_EVENTS = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_INTERRUPTED",
                        "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_STOP", "UNIT_HEALTH" }

function Observe.OnEvent(event, a1, a2, a3, ...)
  if event == "PLAYER_TARGET_CHANGED" then
    Observe.Note(event, Observe.ReadUnit("target"))
  elseif event:find("^UNIT_") then
    local unit = creatureUnit(a1)
    if not unit then return end
    local t = Observe.ReadUnit(unit)
    if event:find("^UNIT_SPELLCAST") then
      t.castId = a2 == nil and Observe.NIL or a2
      t.spellId = a3 == nil and Observe.NIL or a3
    end
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
  for _, e in ipairs(Observe.UNIT_EVENTS) do pcall(f.RegisterEvent, f, e) end
  pcall(f.RegisterEvent, f, "PLAYER_TARGET_CHANGED")
end
```

Careful: the test's `UnitCastingInfo` mock returns `spellId` as the 9th value; Classic's order is name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, spellId. The pcall shifts by one: `local ok, name, text, tex, startMs, endMs, trade, castID, noInt, spellId = pcall(...)`. Use that full list.

The test expects `r.s.cast == "string"` for a target with a readable cast and `spellId` from the event's third argument: the test fires `fire("UNIT_SPELLCAST_START", "target", "cast-1", 1234)`.

- [ ] **Step 4: Run the harness**: `layout problems: 0`, `OK`.

- [ ] **Step 5: Commit** `git commit -m "QuestBank probe: unit cast events and target reads"`.

### Task 3: Auras, nameplates, vignettes

**Files:**
- Modify: `tools/questbank/QuestBank/Observe.lua`
- Test: `tools/questbank/harness.lua`

**Interfaces:**
- Produces: `Observe.ReadAuras(unit)` returning `{ unit, n, name, spellId, source, kind }` from the first harmful aura on the unit.

- [ ] **Step 1: Extend the test**

```lua
  -- auras on the player and party: the first harmful one, by C_UnitAuras
  c.env.C_UnitAuras.GetAuraDataByIndex = function(unit, i, filter)
    if i == 1 then return { name = "Mana Burn", spellId = 1300001, sourceUnit = "target", isHarmful = true, dispelName = "Magic" } end
  end
  fire("UNIT_AURA", "player", { isFullUpdate = true })
  r = ev().UNIT_AURA
  assert(r and r.n == 1 and r.s.name == "string" and r.s.spellId == "number" and r.s.source == "string" and r.s.kind == "string", "a harmful aura on the player, its source unit and school")
  fire("UNIT_AURA", "target")
  assert(ev().UNIT_AURA.n == 1, "auras on creatures are not read (only what lands on us)")
  -- nameplates and rare vignettes
  fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
  assert(ev().NAME_PLATE_UNIT_ADDED.n == 1 and ev().NAME_PLATE_UNIT_ADDED.s.level == "number", "a nameplate added reads the unit")
  c.env.C_VignetteInfo = { GetVignettes = function() return { "v-1" } end,
    GetVignetteInfo = function(id) return { vignetteGUID = id, objectGUID = "Creature-0-4455-0-12-7777-0000A1B2C3", name = "Grizzled Rare", atlasName = "VignetteKill", onWorldMap = true, onMinimap = true } end }
  fire("VIGNETTE_MINIMAP_UPDATED", "v-1", true)
  r = ev().VIGNETTE_MINIMAP_UPDATED
  assert(r and r.n == 1 and r.s.objectGUID == "string" and r.s.atlas == "string", "a vignette: its object GUID and atlas")
```

- [ ] **Step 2: Run to see it fail.**

- [ ] **Step 3: Implement** in Observe.lua, before `Observe.OnEvent`:

```lua
local function ourUnit(unit)
  unit = plain(unit)
  return unit == "player" or (type(unit) == "string" and unit:find("^party%d$") ~= nil)
end

function Observe.ReadAuras(unit)
  local t = { unit = unit, n = 0 }
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not get then t.api = Observe.NIL; return t end
  for i = 1, 40 do
    local ok, a = pcall(get, unit, i, "HARMFUL")
    if not ok or type(a) ~= "table" then break end
    t.n = t.n + 1
    if t.n == 1 then
      t.name = a.name == nil and Observe.NIL or a.name
      t.spellId = a.spellId == nil and Observe.NIL or a.spellId
      t.source = a.sourceUnit == nil and Observe.NIL or a.sourceUnit
      t.kind = a.dispelName == nil and Observe.NIL or a.dispelName
    end
  end
  return t
end

local function readVignette(id)
  local t = { id = id == nil and Observe.NIL or id }
  if not (C_VignetteInfo and C_VignetteInfo.GetVignetteInfo) then t.api = Observe.NIL; return t end
  local ok, v = pcall(C_VignetteInfo.GetVignetteInfo, id)
  if not ok or type(v) ~= "table" then t.info = Observe.NIL; return t end
  t.objectGUID = v.objectGUID == nil and Observe.NIL or v.objectGUID
  t.atlas = v.atlasName == nil and Observe.NIL or v.atlasName
  t.name = v.name == nil and Observe.NIL or v.name
  return t
end
```

In `Observe.OnEvent` add branches before the generic `^UNIT_` one:

```lua
  elseif event == "UNIT_AURA" then
    if ourUnit(a1) then Observe.Note(event, Observe.ReadAuras(plain(a1))) end
  elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
    local unit = creatureUnit(a1)
    if unit then Observe.Note(event, Observe.ReadUnit(unit)) end
  elseif event == "VIGNETTE_MINIMAP_UPDATED" then
    Observe.Note(event, readVignette(a1))
```

Register in Init: `"UNIT_AURA", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "VIGNETTE_MINIMAP_UPDATED"`.

- [ ] **Step 4: Harness passes. Step 5: Commit** `"QuestBank probe: auras on us, nameplates, rare vignettes"`.

### Task 4: Merchants, object loot, combat and encounter timing

**Files:**
- Modify: `tools/questbank/QuestBank/Observe.lua`
- Test: `tools/questbank/harness.lua`

- [ ] **Step 1: Extend the test**

```lua
  -- a merchant: the npc's GUID, the first item's id, price and link
  c.npcGUID = "Creature-0-4455-0-12-1234-0000A1B2C3"
  c.merchant = { 2589, 2592 }
  c.env.GetMerchantItemInfo = function(i) return "Linen Cloth", "", 13, 1, 0, true, nil end
  c.env.GetMerchantItemLink = function(i) return "|cffffffff|Hitem:2589::::::::29:::::|h[Linen Cloth]|h|r" end
  fire("MERCHANT_SHOW")
  r = ev().MERCHANT_SHOW
  assert(r and r.n == 1 and r.s.guid == "string" and r.s.items == "number" and r.s.id == "number" and r.s.price == "number" and r.s.link == "string", "a merchant: who, how many, the first item's id, price and link")
  -- a chest: loot from a game object
  c.loot = { { id = 2589, src = { { "GameObject-0-4455-0-12-2843-0000A1B2C3", 1 } } } }
  fire("LOOT_OPENED", false, false)
  r = ev().LOOT_OPENED
  assert(r and r.n == 1 and r.s.src == "string" and r.s.slots == "number", "a loot window: the first slot's source GUID")
  -- combat and encounter timing
  fire("PLAYER_REGEN_DISABLED"); fire("ENCOUNTER_START", 3303, "Shade of the Archmage", 1, 5); fire("PLAYER_REGEN_ENABLED")
  assert(ev().PLAYER_REGEN_DISABLED.n == 1 and ev().PLAYER_REGEN_ENABLED.n == 1 and ev().ENCOUNTER_START.s.id == "number" and ev().ENCOUNTER_START.s.t == "number", "combat edges and the encounter id with a time")
```

- [ ] **Step 2: Run to see it fail.**

- [ ] **Step 3: Implement** reads in Observe.lua:

```lua
local function readMerchant()
  local t = {}
  local ok, guid = pcall(UnitGUID, "npc")
  t.guid = (ok and guid ~= nil) and guid or Observe.NIL
  local n = GetMerchantNumItems and select(2, pcall(GetMerchantNumItems)) or nil
  t.items = n == nil and Observe.NIL or n
  if type(plain(n)) == "number" and n > 0 then
    local okId, id = pcall(GetMerchantItemID, 1)
    t.id = (okId and id ~= nil) and id or Observe.NIL
    if GetMerchantItemInfo then
      local okI, _, _, price = pcall(GetMerchantItemInfo, 1)
      t.price = (okI and price ~= nil) and price or Observe.NIL
    else t.price = Observe.NIL end
    if GetMerchantItemLink then
      local okL, link = pcall(GetMerchantItemLink, 1)
      t.link = (okL and link ~= nil) and link or Observe.NIL
    else t.link = Observe.NIL end
  end
  return t
end

local function readLoot()
  local t = {}
  local ok, n = pcall(GetNumLootItems)
  t.slots = (ok and n ~= nil) and n or Observe.NIL
  if GetLootSourceInfo and type(plain(n)) == "number" and n > 0 then
    local okS, guid = pcall(GetLootSourceInfo, 1)
    t.src = (okS and guid ~= nil) and guid or Observe.NIL
  else t.src = Observe.NIL end
  return t
end
```

Branches in `Observe.OnEvent`:

```lua
  elseif event == "MERCHANT_SHOW" then
    Observe.Note(event, readMerchant())
  elseif event == "LOOT_OPENED" then
    Observe.Note(event, readLoot())
  elseif event == "ENCOUNTER_START" or event == "ENCOUNTER_END" then
    Observe.Note(event, { id = a1 == nil and Observe.NIL or a1, t = GetTime and GetTime() or Observe.NIL, diff = a3 == nil and Observe.NIL or a3 })
  elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    Observe.Note(event, { t = GetTime and GetTime() or Observe.NIL })
```

Register: `"MERCHANT_SHOW", "LOOT_OPENED", "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED"`.

- [ ] **Step 4: Harness passes. Step 5: Commit** `"QuestBank probe: merchants, chests, combat and encounter timing"`.

### Task 5: Off switch, clear on untick, and the hidden /qb probe readout

**Files:**
- Modify: `tools/questbank/QuestBank/Observe.lua` (`Observe.Clear()`)
- Modify: `tools/questbank/QuestBank/Core.lua` (where unticking "Note items, spells and loot" calls `QB.Loot.Clear()`: also call `QB.Observe.Clear()`; slash `/qb probe` prints the per-event table to chat, counts only)
- Test: `tools/questbank/harness.lua`

- [ ] **Step 1: Test**

```lua
  Ob.Clear()
  assert(DB.diag.ev == nil, "clear drops the probe's counts")
  Ob.Note("X", { a = 1 })
  local chat0 = #c.chat
  c.env.SlashCmdList.QUESTBANK("probe")
  assert(#c.chat > chat0 and table.concat(c.chat, "\n", chat0 + 1):find("X", 1, true) and table.concat(c.chat, "\n", chat0 + 1):find("1 ok", 1, true), "/qb probe lists the events with their counts")
```

(Check the slash handler's name with `grep -n "SlashCmdList" QuestBank/Core.lua`; use that name.)

- [ ] **Step 2: Fail, Step 3: Implement**

```lua
function Observe.Clear()
  if QuestBankDB and type(QuestBankDB.diag) == "table" then QuestBankDB.diag.ev = nil end
end

function Observe.Report(say)
  local all = QuestBankDB and type(QuestBankDB.diag) == "table" and QuestBankDB.diag.ev
  if type(all) ~= "table" or next(all) == nil then say("QuestBank probe: nothing counted yet."); return end
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
```

In Core.lua's slash handler add `elseif cmd == "probe" then QB.Observe.Report(QB.Say)` (use whatever chat print function Core already uses for `/qb errors`; grep `"errors"`). Where the settings untick clears Loot, add `if QB.Observe then QB.Observe.Clear() end`.

- [ ] **Step 4: Harness passes. Step 5: Commit** `"QuestBank probe: /qb probe readout, cleared with the notes box"`.

### Task 6: Release 3.7.0

**Files:**
- Modify: `tools/questbank/QuestBank/Core.lua:5`, `tools/questbank/QuestBank/QuestBank.toc:5`, `questbank/index.html` (version lines, release notes lead + bullets, zip sizes), `SOURCES.md` (one ledger line), `tools/questbank/OBSERVER-EVENTS.md` (create: the table to be filled from the next upload, with the event list and columns works / secret / absent)
- Rebuild: `questbank/QuestBank.zip`, `questbank/QuestBank-Uploader.zip`

- [ ] **Step 1: Bump the version** in Core.lua and the TOC to `3.7.0`; in questbank/index.html replace every `3.6.2` with `3.7.0`, the date with `12 October 2026`, and add the release note lead "3.7.0 asks the game what it will tell addons" with bullets: "Counts, per event, whether the client hands QuestBank readable values, secret values or nothing: the groundwork for recording what bosses cast and what vendors sell." / "`/qb probe` shows the counts; the notes box clears them." / "Nothing new is uploaded about you: field names and value kinds only."

- [ ] **Step 2: Rebuild the zips and run the uploader test**

```bash
cd ~/foreverrank/tools/questbank && luajit harness.lua 2>&1 | tail -2 && rm -f ../../questbank/QuestBank.zip && zip -rq ../../questbank/QuestBank.zip QuestBank -x "*.DS_Store" && cd ~/foreverrank && python3 tools/build_uploader.py | tail -1 && python3 tools/build_uploader.py --test | tail -1 && python3 -c "import os;print(round(os.path.getsize('questbank/QuestBank.zip')/1024),'KB', round(os.path.getsize('questbank/QuestBank-Uploader.zip')/1024),'KB')"
```
Put the printed sizes into questbank/index.html's dl-meta lines.

- [ ] **Step 3: Write tools/questbank/OBSERVER-EVENTS.md** with the list of every registered event and three empty columns, and a line saying it is filled by `python3 tools/probe_pull.py` output once the owner's 3.7.0 upload arrives (reading `diag.ev` from the upload's QuestBank.lua).

- [ ] **Step 4: Run the SEO head builder** `python3 tools/seo.py | tail -1`, then `git add -A questbank tools/questbank SOURCES.md && git commit -m "QuestBank 3.7.0: the event probe"`. The owner pushes.

## Self-review

- Spec coverage: every event family in Part A has a task (casts/units: 2; auras, nameplates, vignettes: 3; merchants, objects, timing: 4); recording shape, cap, privacy: 1; clear and readout: 5; the harness test, the next-upload table: 6. UNIT_HEALTH for deaths is in Task 2's event list.
- Placeholders: none; each step carries its code.
- Names: `Observe.Note`, `Observe.NIL`, `Observe.ReadUnit`, `Observe.ReadAuras`, `Observe.Clear`, `Observe.Report`, `Observe.UNIT_EVENTS`, `Observe.MAX_KEYS` are used consistently.
