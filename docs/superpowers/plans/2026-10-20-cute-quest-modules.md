# Cute_Quest: QuestBank's guiding as Cute modules. Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cute 0.7.0 ships a second folder, `Cute_Quest`, whose Lua is QuestBank's engine copied at build time; its six modules (Quests, Route, Map, Journal, Gear, Camp) and the Guide's step band draw QuestBank's guiding in Cute's look, each a switch in Settings > Modules; with QuestBank loaded the copy sleeps and the pages read QuestBank's engine.

**Architecture:** QuestBank's side gets small, mechanical changes (a dormant guard line per file, `QuestBankAPI`, `QB:Login()`, `QB.ART`, a `QB.Skin` hook, and the window-free half of `UI.lua` split into `Lists.lua`). Cute's side gets a registry that lets one addon register several modules, a `Cute_Quest` folder with nine own files (`Shim.lua`, `Bridge.lua`, `Band.lua`, six `Page*.lua`), a build step that copies and checks the engine, and a harness that can load the engine. Spec: `docs/superpowers/specs/2026-10-20-cute-quest-modules-design.md`; read it first.

**Tech Stack:** WoW addon Lua (the Forever client, Lua 5.1 semantics), LuaJIT for the harnesses, Python 3 standard library for `build.py`, perl for one in-place edit.

## Global Constraints

- Cute's version becomes `0.7.0` in `tools/cute/Cute/Cute.toc` and `C.version` in `tools/cute/Cute/Core.lua`; the page's changelog newest entry must be `0.7.0` (the build checks).
- Cute's harness gate: `cd /Users/mikalbot/foreverrank/tools/cute && luajit harness.lua` must end with the line `layout problems: 0` followed by `OK`.
- The build gate: `python3 /Users/mikalbot/foreverrank/tools/cute/build.py` must end with `problems: 0` followed by `OK`.
- QuestBank's harness gate: `cd /Users/mikalbot/foreverrank/tools/questbank && luajit harness.lua` must end with the line `OK` (not `OK, with layout problems above`) and exit 0.
- Machine safety: run one `luajit` at a time, never the two harnesses together; before QuestBank's harness run `memory_pressure | tail -1` and only start it when the line says `normal`. QuestBank's harness takes minutes: run it in the foreground with a 600000 ms timeout.
- No file in `tools/cute/Cute_Quest/` other than the nine own files is edited by hand: `build.py` writes the copies and the toc.
- Every Lua source must be ASCII (the harness refuses a byte at or above 0x80: the game's font draws it as a box).
- The owner's rules: game-native icons, always-visible state, no catalogues (the page leads with the window; one changelog line), no chat spam (the engine's one hand-in line only), learn-don't-list, modules as toggles.
- Cute's look: `UI.FONT`, `UI.COLORS`, flat rows (`UI:MakeLine`), `UI.ROW` = 20, no new colours.
- Commit after each task with the message given; never push.
- Do not invent engine functions: every engine call in this plan names a function that exists in `tools/questbank/QuestBank/*.lua` today or that an earlier task of this plan defines.

---

## File map

Created:
- `tools/questbank/QuestBank/Lists.lua` (the window-free half of today's `UI.lua`; same `QB.UI` table)
- `tools/cute/Cute_Quest/Shim.lua`, `Bridge.lua`, `Band.lua`, `PageQuests.lua`, `PageRoute.lua`, `PageMap.lua`, `PageJournal.lua`, `PageGear.lua`, `PageCamp.lua` (own files)
- `tools/cute/Cute_Quest/*.lua`, `Pins.xml`, `art/*`, `Cute_Quest.toc` (written by the build; committed)
- `tools/cute/test/quest_mocks.lua` (the engine's mocks for Cute's harness)

Modified:
- `tools/questbank/QuestBank/Core.lua` (guard, `QuestBankAPI`, `QB:Login`), every other engine file (guard line), `Data.lua` and `tools/questbank/gen_data.py` (guard line), `UI.lua` (split), `QuestBank.toc` (`Lists.lua`), `Arrow.lua`, `Camp.lua`, `Glow.lua`, `DungeonMap.lua`, `Minimap.lua`, `Pins.lua`, `MinimapRoute.lua` (`QB.ART`), `StepFrame.lua`, `Arrow.lua`, `Gear.lua` (`QB.Skin`)
- `tools/cute/Cute/Modules.lua`, `UI.lua`, `Guide.lua`, `Core.lua`, `Cute.toc`, `tools/cute/build.py`, `tools/cute/harness.lua`, `tools/cute/test/Cute_Example/Example.lua`, `tools/cute/README.md`, `addons/cute/index.html`

---

### Task 1: The engine can sleep, be found and be logged in by a host (QuestBank side)

**Files:**
- Modify: `tools/questbank/QuestBank/Core.lua:4-5` (guard, `QuestBankAPI`), `:2730-2761` (`QB:Login`)
- Modify: every other `tools/questbank/QuestBank/*.lua` (the guard line), `tools/questbank/gen_data.py:1518`
- Modify: `tools/questbank/QuestBank/Arrow.lua:503`, `Camp.lua:466`, `Glow.lua:587`, `DungeonMap.lua:22`, `Minimap.lua:29`, `Pins.lua:452`, `MinimapRoute.lua:13` (`QB.ART`)
- Test: `tools/questbank/harness.lua` (existing scenarios; one assertion added at its head)

**Interfaces:**
- Produces: `QB.dormant` (read by every engine file's second line), the global `QuestBankAPI` (QuestBank's `QB`), `function QB:Login()` (the former `PLAYER_LOGIN` branch; idempotent), `QB.ART` (an art path prefix a host may set before the files load).

- [ ] **Step 1: Write the failing check**

Add to `tools/questbank/harness.lua` right after the `METHODS`/`FONT_SIZE` block (after line 44), a source scan that fails until every engine file carries the guard:

```lua
-- every engine file sleeps when a host sets QB.dormant before it runs (Cute_Quest holds a copy of the engine and
-- sleeps it while QuestBank itself is loaded): the guard is the first statement after the file's vararg line
do
  local toc = assert(io.open(HERE .. "/QuestBank/QuestBank.toc")):read("*a")
  for file in toc:gmatch("\n([%w_]+%.lua)") do
    if file ~= "UI.lua" then
      local src = assert(io.open(HERE .. "/QuestBank/" .. file)):read("*a")
      assert(src:find("local [%w_]+, QB = %.%.%.\n", 1), file .. " has no `local _, QB = ...` line")
      assert(src:find("local [%w_]+, QB = %.%.%.\nif QB%.dormant then return end\n", 1), file .. " lacks `if QB.dormant then return end` after its vararg line")
    end
  end
end
```

- [ ] **Step 2: Run the harness head to see it fail**

Run: `cd /Users/mikalbot/foreverrank/tools/questbank && luajit -e 'arg={[0]="harness.lua"}' harness.lua 2>&1 | head -5`
Expected: an assertion naming the first file without the guard (`Data.lua lacks ...`).

- [ ] **Step 3: Add the guard line to every engine file, Data.lua's generator included**

```bash
cd /Users/mikalbot/foreverrank/tools/questbank/QuestBank
for f in $(grep -l '^local [A-Za-z_]*, QB = \.\.\.$' *.lua); do
  [ "$f" = "UI.lua" ] && continue
  perl -0pi -e 's/\n(local [A-Za-z_]+, QB = \.\.\.)\n/\n$1\nif QB.dormant then return end\n/' "$f"
done
grep -L 'if QB.dormant then return end' *.lua   # must print only UI.lua
```

In `tools/questbank/gen_data.py:1518` change the list `["...", "local _, QB = ...", "local D = {}", "QB.Data = D", ""]` to `["...", "local _, QB = ...", "if QB.dormant then return end", "local D = {}", "QB.Data = D", ""]` so the next generated `Data.lua` carries the line too.

- [ ] **Step 4: Expose the engine and move the login into a function**

In `Core.lua`, after `QB.version = "6.0.1"` (line 5) add:

```lua
-- the engine, for a host that runs beside QuestBank and must not run a second one (Cute_Quest reads this table
-- instead of its own copy while QuestBank is loaded); QuestBank itself never reads it
QuestBankAPI = QB
```

Replace the `PLAYER_LOGIN` branch of the event handler (lines 2730-2761, from `elseif event == "PLAYER_LOGIN" then` to its `return`) with:

```lua
  elseif event == "PLAYER_LOGIN" then
    QB:Login()
    return
```

and add, just above `local frame = CreateFrame("Frame")` (line 2621):

```lua
-- the login: the character's key, the state read, every part's Init, the first plan a few seconds on. From the
-- PLAYER_LOGIN event; or from a host that loaded the engine on demand after it, which never sees that event
-- (Cute_Quest's Bridge.lua). Once a session
function QB:Login()
  if QB.loginDone then return end
  QB.loginDone = true
  local nr = GetNormalizedRealmName and GetNormalizedRealmName()
  if nr then QB.charKey = (UnitName("player") or "?") .. "-" .. nr; QB:MergeCharKeys() end
  QB:ReadState()
  if QB.Minimap then QB.Minimap:Create() end
  if QB.Pins then QB.Pins:Init() end
  if QB.QuestMap then QB.QuestMap:Init() end
  if QB.Sync then QB.Sync:Init() end
  if QB.Discover then QB.Discover:Init() end
  if QB.Survey then QB.Survey:Init() end
  if QB.Game then QB.Game:Init() end
  if QB.Loot then QB.Loot:Init() end
  if QB.Observe then QB.Observe:Init() end
  if QB.Timer then QB.Timer:Init() end
  if QB.Link then QB.Link:Init() end
  if QB.Mini then QB.Mini:Init() end
  if QB.MapPage then QB.MapPage:Init() end
  if QB.Glow then QB.Glow:Init() end
  if QB.Walk then QB.Walk:Init() end
  if QB.Legacy then QB.Legacy:Init() end
  if QB.Camp then QB.Camp:Init() end
  if QB.Travel then QB.Travel:Init() end
  if QB.Arrow then QB.Arrow:Init() end
  if QB.Target then QB.Target:Init() end
  if QB.StepFrame then QB.StepFrame:Init() end -- (the Guide's step frame, StepFrame.lua)
  if QB.Tips then QB.Tips:Init() end -- (quest progress in mob and object tooltips, Tips.lua)
  -- after the other addons have loaded and run their own login code
  C_Timer.After(12, QB.Safe(QB.NoteAddons, "addon note"))
  Run.ArmHour()
  C_Timer.After(8, QB.Safe(function() QB:Snapshot("login") end, "login snapshot"))
  C_Timer.After(4, QB.Safe(function() QB:Changed() end, "login"))
end
```

(The body is the old branch verbatim, with the `if QB.loginDone` gate in front.)

- [ ] **Step 5: The art path a host may set**

In each of the seven files replace the hard-coded prefix:

- `Arrow.lua:503`, `Camp.lua:466`, `Glow.lua:587`, `DungeonMap.lua:22`, `Minimap.lua:29`: `local ART = "Interface\\AddOns\\QuestBank\\art\\"` becomes `local ART = QB.ART or "Interface\\AddOns\\QuestBank\\art\\" -- (a host holding a copy of the engine names its own folder: QB.ART)`
- `Pins.lua:452`: `local GLOW = (QB.ART or "Interface\\AddOns\\QuestBank\\art\\") .. "glow.tga"`
- `MinimapRoute.lua:13`: `local TEX = (QB.ART or "Interface\\AddOns\\QuestBank\\art\\") .. "line_arrow.png"`

- [ ] **Step 6: Run QuestBank's harness**

Run: `memory_pressure | tail -1` (must say normal), then `cd /Users/mikalbot/foreverrank/tools/questbank && luajit harness.lua 2>&1 | tail -3`
Expected: the last line is `OK`.

- [ ] **Step 7: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/QuestBank tools/questbank/gen_data.py tools/questbank/harness.lua
git commit -m "questbank: the engine sleeps under a host (QB.dormant), is found (QuestBankAPI), logs in by call (QB:Login), names its art by QB.ART

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: The window-free half of UI.lua becomes Lists.lua (QuestBank side)

**Files:**
- Create: `tools/questbank/QuestBank/Lists.lua`
- Modify: `tools/questbank/QuestBank/UI.lua` (the moved ranges deleted; `local UI = QB.UI`; `UI.PlaceGroups` extracted from `RefreshPrepView`), `tools/questbank/QuestBank/QuestBank.toc` (`Lists.lua` after `Core.lua`)
- Test: `tools/questbank/harness.lua` (existing scenarios; one check added)

**Interfaces:**
- Consumes: `QB.Quest`, `QB.Data`, `QB.Model`, `QB.API`, `QB.Bank`, `QB.Timer`, `QB.Live`, `QB.Arrow.FirstStep` (all existing).
- Produces, on `QB.UI` from `Lists.lua`: `UI.FitText(fs, s, room)`, `UI.QuestTooltipShort(tip, q, st, xp)`, `UI.QuestTooltip(tip, q, st, xp, pct, plvl, rewardRow)`, `UI.QuestLink(q)`, `UI.LinkQuest(q)`, `UI.LinkItem(id, name)`, `UI.LinkItemAlways(id)`, `UI.RewardLines(tip, q)`, `UI.QuestClick(q, st, which)`, `UI.QuestMenu(q, st)`, `UI.Short(name, n)`, `UI.SkipQuest(q)`, `UI.RouteAgain(q)`, `UI.ConfirmAbandon(q)`, `UI.Abandon(q)`, `UI.FINDS`, `UI.findMode`, `UI.ItemFacts(id)`, `UI.MyArmor(level)`, `UI.ItemUse(id, level)`, `UI.BestReward(qid, kind, level, slot)`, `UI:FindRewards(kind, level, slot)`, `UI.GEAR_SLOTS`, `UI.RewardSlotFits(qid, slot, level)`, `UI.Here()`, `UI.MinutesTo(q, here, mf)`, `UI:Candidates(limit, level, reqMax, finder)`, `UI.BAND`, `UI.FollowUp(q)`, `UI.ChainLine(q, here, mf)`, `UI.Together(items)`, `UI.PlaceGroups(level)` -> `order, groups, here, mf, hubName`.
- `UI.lua` keeps everything else and starts from `QB.UI`.

- [ ] **Step 1: Write the failing check**

Add to `tools/questbank/harness.lua`, right after the guard scan of Task 1:

```lua
-- the window-free half of the window (Lists.lua) runs without UI.lua: a client that loads every file but UI.lua
-- still has the quest tooltip, the menu, the finders, the candidates and the places
do
  local toc = assert(io.open(HERE .. "/QuestBank/QuestBank.toc")):read("*a")
  assert(toc:find("\nCore.lua\nLists.lua\n", 1, true), "Lists.lua follows Core.lua in the toc")
  local src = assert(io.open(HERE .. "/QuestBank/Lists.lua")):read("*a")
  for _, name in ipairs({ "QuestTooltip", "QuestMenu", "Candidates", "PlaceGroups", "FindRewards", "Here", "MinutesTo", "ChainLine", "FitText", "Short", "QuestClick" }) do
    assert(src:find("function UI[.:]" .. name .. "%("), "Lists.lua defines UI." .. name)
  end
  local win = assert(io.open(HERE .. "/QuestBank/UI.lua")):read("*a")
  assert(win:find("\nlocal UI = QB.UI\n", 1, true) and not win:find("function UI:Candidates", 1, true), "UI.lua starts from QB.UI and no longer holds Candidates")
end
```

- [ ] **Step 2: See it fail**

Run: `cd /Users/mikalbot/foreverrank/tools/questbank && luajit harness.lua 2>&1 | head -3`
Expected: `Lists.lua follows Core.lua in the toc` (the toc has no Lists.lua yet).

- [ ] **Step 3: Create Lists.lua from UI.lua's ranges**

Create `tools/questbank/QuestBank/Lists.lua` with this head, then move the ranges below into it (cut from `UI.lua`, paste in this order, unchanged):

```lua
-- SPDX-License-Identifier: GPL-3.0-or-later
-- The window-free half of QuestBank's window, on the same QB.UI table UI.lua draws with: what every page and every
-- other part reads of a quest without a frame of its own: the quest tooltip and the reward lines, the chat links,
-- the right-click menu and its choices (skip, route again, abandon), a label cut after a word, the reward finders
-- (what an item is to you, the best reward of a quest, the finder's rows), where you stand and the minutes to a
-- giver, the candidates (every quest worth suggesting at your level, ranked), a chain's line, the quests done in one
-- spot, and the places with their quests as the Available page groups them (PlaceGroups). A host that draws its own
-- pages (Cute_Quest) copies this file and not UI.lua.
local _, QB = ...
if QB.dormant then return end
local UI = QB.UI or {}
QB.UI = UI

local INK = { 0.93, 0.88, 0.78 }
local INK_SOFT = { 0.66, 0.60, 0.50 }
local GOOD = { 0.42, 0.86, 0.45 }
local BAD = { 0.90, 0.38, 0.32 }
local GOLD = { 1, 0.82, 0 }
local WHITE = { 0.95, 0.93, 0.88 }
local STATUS = {
  done = { 0.5, 0.5, 0.5 }, banked = GOOD, active = { 0.95, 0.72, 0.3 }, partial = { 0.95, 0.72, 0.3 },
  bagstart = { 0.95, 0.72, 0.3 }, item = INK_SOFT, locked = BAD, prereq = BAD, todo = INK_SOFT, follow = { 0.55, 0.65, 0.95 },
  wrong = { 0.5, 0.5, 0.5 },
}
local Q = QB.Quest
```

Ranges to move (today's `UI.lua` line numbers; cut each whole):

1. 77-92: `local function fitText` and `UI.FitText = fitText`.
2. 308-335: `npcLine`, `chatFn`, `chatInsert`, `chatOpen`.
3. 337-618: `UI.QuestTooltipShort`, `UI.QuestTooltip`, `UI.QuestLink`, `UI.LinkQuest`, `UI.LinkItem`, `UI.LinkItemAlways`, `UI.RewardLines`, `local questClick`, `UI.QuestClick`, `questClick = function ... end`.
4. 865-965: `UI.QuestMenu`, `UI.Short`, `UI.SkipQuest`, `UI.RouteAgain`, `UI.ConfirmAbandon`, `UI.Abandon`.
5. 1573-1726: `UI.FINDS` through `UI.RewardSlotFits` (the `INVTYPE`, `ARMOR_SLOT`, `ANYONE`, `JEWEL`, `WEAPON_SLOT` tables, `UI.ItemFacts`, `UI.MyArmor`, `UI.ItemUse`, `REWARD_KEYS`/`NO_ITEMS`, `UI.BestReward`, `itemName`, `UI:FindRewards`, `UI.GEAR_SLOTS`, `UI.RewardSlotFits`). `modWatch` (1728-1734) stays in `UI.lua`.
6. 1977-2126: `UI.Here`, `UI.MinutesTo`, `UI:Candidates`, `UI.BAND`, `UI.FollowUp`.
7. 3086-3147: `UI.ChainLine`, `UI.Together`.

`UI.lua` line 10-11 `local UI = {}` / `QB.UI = UI` become `local UI = QB.UI` (one line). Anything in the moved code that named a `UI.lua` local not listed above (`T`, `text`, `tex`, `hex`, `tier`, `backdrop`) is a bug to surface by the harness: fix by moving that helper too, never by copying it twice.

- [ ] **Step 4: Extract UI.PlaceGroups from RefreshPrepView**

In `UI.lua`'s `UI:RefreshPrepView(v)` (today at 3244), the block from `local groups, order = {}, {}` (3269) through the statement that sorts `order` (the first `table.sort(order, ...)` after it; the "what you have done in each place" loop lies between) becomes, in `Lists.lua`:

```lua
-- every quest for you by place, as the Available page groups them: what you hold, what you chose to pick up, what
-- you could pick up now, what comes later, what a later step says you have done; each place with its counts and
-- score, the list in the page's order. level: yours by default. Returns order (the places), groups (by category
-- index), and where you stand (here, mf, hubName: UI.Here)
function UI.PlaceGroups(level)
  local D = QB.Data
  local s = QB.state
  level = level or s.level
  local fac = QB.faction
  local banking = QB:Banking()
  local M = QB.Model
  local here, mf, hubName = UI.Here()
  <the cut block, verbatim, with `self:Candidates(nil, level)` written `UI:Candidates(nil, level)`>
  return order, groups, here, mf, hubName
end
```

and `RefreshPrepView` calls `local order, groups, here, mf, hubName = UI.PlaceGroups(level)` where the block was (its earlier `local here, mf, hubName = UI.Here()` line is deleted; the locals `D, s, level, fac, banking, M, width` it still uses stay).

- [ ] **Step 5: The toc**

In `QuestBank.toc` insert `Lists.lua` on the line after `Core.lua`.

- [ ] **Step 6: Run QuestBank's harness**

Run: `memory_pressure | tail -1`, then `cd /Users/mikalbot/foreverrank/tools/questbank && luajit harness.lua 2>&1 | tail -3`
Expected: `OK`. A `nil` global or upvalue error names a helper that must move with its function (Step 3's last line).

- [ ] **Step 7: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/QuestBank/Lists.lua tools/questbank/QuestBank/UI.lua tools/questbank/QuestBank/QuestBank.toc tools/questbank/harness.lua
git commit -m "questbank: the window-free half of UI.lua is Lists.lua (tooltip, menu, finders, candidates, places), for a host with pages of its own

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: The step frame, the arrow and the Gear page take a skin (QuestBank side)

**Files:**
- Modify: `tools/questbank/QuestBank/StepFrame.lua:15-37, 55-67, 45-52, 232-235`, `Arrow.lua:731-780`, `Gear.lua:27-29, 290-299`
- Test: `tools/questbank/harness.lua` (one scenario added after the memory block's `;(function()` block, before the end)

**Interfaces:**
- Consumes: `QB.Skin`, nil in QuestBank; a host sets `{ font = "<path>", INK = {r,g,b}, SOFT = {r,g,b}, ACCENT = {r,g,b}, Backdrop = function(frame) end }` before `QB:Login()`.
- Produces: the step frame's rows, time line, reminder and member lines in the skin's font and colours; its backdrop from `Skin.Backdrop`; the arrow's five lines likewise; the Gear page's text likewise.

- [ ] **Step 1: Write the failing scenario**

Append to `tools/questbank/harness.lua` before its final `-- this pass's problems` section (just before `for _, l in ipairs(layouts)` or, if absent, before the last `print(#unique == 0 ...)` block):

```lua
-- a host's skin (Cute_Quest): set before the login, the step frame's text takes its font and colours and its frame
-- its backdrop; the arrow's lines and the Gear page's text too; QuestBank itself sets none and looks as before
do
  local c = newClient({ name = "Skinned", level = 5, cap = 60, faction = "Alliance", className = "Warrior", class = "WARRIOR", classID = 1, race = "Human",
    log = { { 7, 0 } }, done = {}, world = { 0, -8914, -133 }, map = 1429, bagSlots = {}, bind = "Goldshire" })
  local backdrops = 0
  c.QB.Skin = { font = "Fonts\\ARIALN.TTF", INK = { 0.86, 0.86, 0.86 }, SOFT = { 0.58, 0.58, 0.58 }, ACCENT = { 0.96, 0.96, 0.96 },
    Backdrop = function(f) backdrops = backdrops + 1; f.__flat = true end }
  login(c)
  c.QB:Settings().guide.on, c.QB:Settings().guide.frame, c.QB:Settings().welcome = true, true, nil
  c.QB.StepFrame.Apply(); c.QB.StepFrame.Refresh()
  local f = c.env.QuestBankStep
  assert(f and f.__flat and backdrops == 1 and not f.__backdrop, "the step frame took the host's backdrop and not its own")
  assert(f.now.__fontFile == "Fonts\\ARIALN.TTF", "the step now in the skin's font: " .. tostring(f.now.__fontFile))
  local r, g, b = f.now:GetTextColor()
  assert(math.abs(r - 0.86) < 0.01 and math.abs(g - 0.86) < 0.01, "the step now in the skin's ink")
  c.QB.Arrow:Set(true)
  local a = c.env.QuestBankArrow
  assert(a and a.name.__fontFile == "Fonts\\ARIALN.TTF", "the arrow's name line in the skin's font")
  leave(c)
end
```

If `newObj` keeps a font string's file under another field than `__fontFile` (check `fontObj` at harness.lua:217 and `SetFont` in `newObj`), use that field. If `SetBackdrop` is recorded under another name than `__backdrop`, use that.

- [ ] **Step 2: See it fail**

Run: `memory_pressure | tail -1`, then `cd /Users/mikalbot/foreverrank/tools/questbank && luajit harness.lua 2>&1 | tail -3`
Expected: `the step frame took the host's backdrop and not its own`.

- [ ] **Step 3: StepFrame.lua**

Replace the colour constants and `fs` (lines 15-37) with:

```lua
local SLATE = { 0.055, 0.07, 0.095 }
local LOOK = { INK = { 0.93, 0.88, 0.78 }, SOFT = { 0.62, 0.60, 0.54 }, GOLD = { 1, 0.82, 0.3 } }
-- a host's skin (QB.Skin: Cute_Quest sets one before the login; QuestBank none): its font and its colours for
-- the frame's INK, SOFT and GOLD (the skin's ACCENT), and its backdrop
local function tone(key)
  local sk = QB.Skin
  if sk then return (key == "GOLD" and sk.ACCENT) or sk[key] or LOOK[key] end
  return LOOK[key]
end
local TICK = 0.5
local SCALES = { 0.8, 1, 1.2 }
SF.SCALES = SCALES

local function settings() return QB:Settings().guide end
local function fighting() return InCombatLockdown and InCombatLockdown() or false end

local function fs(parent, size, key, width)
  local t = parent:CreateFontString(nil, "OVERLAY")
  local fo = GameFontNormal
  local sk = QB.Skin
  if sk and sk.font then
    if fo then t:SetFontObject(fo) end
    t:SetFont(sk.font, size, "")
  elseif fo then
    t:SetFontObject(fo)
    local path, _, flags = fo:GetFont()
    if path then t:SetFont(path, size, flags) end
  end
  local color = tone(key)
  t:SetTextColor(color[1], color[2], color[3])
  t:SetJustifyH("LEFT")
  t:SetWordWrap(false)
  t:SetWidth(width)
  return t
end
```

Then every caller passes a key instead of a table: `fs(b, i == 1 and 12 or 11, i == 1 and "INK" or "SOFT", ...)` (line 81), `f.time = fs(f, 10, "SOFT", ...)` (105), `f.remind = fs(f, 10, "GOLD", ...)` (107), the member lines `fs(f, 10, "SOFT", ...)` (233), and the welcome card's `fs` calls in `buildCard` (261-330: replace `INK` with `"INK"`, `INK_SOFT` with `"SOFT"`, `GOLD` with `"GOLD"`). `rowEnter` (45-52) uses `local INK = tone("INK")`. In `build()` replace the backdrop block (63-67) with:

```lua
  local sk = QB.Skin
  if sk and sk.Backdrop then
    sk.Backdrop(f)
  elseif f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(SLATE[1], SLATE[2], SLATE[3], 0.92)
    local gold = tone("GOLD")
    f:SetBackdropBorderColor(gold[1], gold[2], gold[3], 0.5)
  end
```

(`GOLD` the table is gone; `grep -n "GOLD\b\|INK_SOFT\b\|\bINK\b" StepFrame.lua` must show only `tone(...)` and string keys.)

- [ ] **Step 4: Arrow.lua**

At the end of `A:ApplyLook()` (after the `if qt ... else ... end` block, before `f.act:SetSize(A.actSize, A.actSize)` at line 770) add:

```lua
  -- a host's skin (QB.Skin: Cute_Quest): its font on every line, its colours; QuestBank sets none
  local sk = QB.Skin
  if sk then
    for _, t in ipairs({ f.name, f.step, f.kind, f.dist, f.hint }) do
      if sk.font then t:SetFont(sk.font, t == f.name and 13 or 11, "") end
    end
    local ink, soft, accent = sk.INK or { 1, 1, 1 }, sk.SOFT or { 0.85, 0.85, 0.85 }, sk.ACCENT or { 1, 0.82, 0 }
    f.name:SetTextColor(ink[1], ink[2], ink[3])
    f.step:SetTextColor(soft[1], soft[2], soft[3])
    f.dist:SetTextColor(soft[1], soft[2], soft[3])
    f.kind:SetTextColor(accent[1], accent[2], accent[3])
    f.hint:SetTextColor(soft[1], soft[2], soft[3])
  end
```

- [ ] **Step 5: Gear.lua**

After its colour constants (lines 27-29) add:

```lua
-- a host's skin (QB.Skin: Cute_Quest): its font, and its colours for INK, SOFT and GOLD (the skin's ACCENT)
local function tone(c)
  local sk = QB.Skin
  if not sk then return c end
  if c == INK then return sk.INK or c elseif c == SOFT then return sk.SOFT or c elseif c == GOLD then return sk.ACCENT or c end
  return c
end
```

and in `fs(parent, font, size, color, w, justify)` (290-299): after the font object is set, `if QB.Skin and QB.Skin.font then t:SetFont(QB.Skin.font, size, "") end`, and the colour line uses `tone(color)`.

- [ ] **Step 6: Run QuestBank's harness**

Run: `memory_pressure | tail -1`, then `cd /Users/mikalbot/foreverrank/tools/questbank && luajit harness.lua 2>&1 | tail -3`
Expected: `OK`.

- [ ] **Step 7: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/QuestBank/StepFrame.lua tools/questbank/QuestBank/Arrow.lua tools/questbank/QuestBank/Gear.lua tools/questbank/harness.lua
git commit -m "questbank: the step frame, the arrow and the Gear page take a host's skin (QB.Skin); none set, nothing changes

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: One addon, several modules; onToggle; hosts; the global Cute helpers (Cute core)

**Files:**
- Modify: `tools/cute/Cute/Modules.lua:50-84, 115-134, 254-309`, `tools/cute/Cute/UI.lua:763-771, 1764-1810`, `tools/cute/test/Cute_Example/Example.lua`
- Test: `tools/cute/harness.lua` (the modules scenario at 4418-4600 gains assertions)

**Interfaces:**
- Produces: `def.primary` (true for an addon's first registered module), `def.key` (`addon` for the primary, `addon .. ":" .. id` for the rest), `M.AddonWanted(name)`, `M.AddonOn(name)`, `def.onToggle(on)` called from `M.Apply` when `active` changes; `M.Available` lists a row per registered module of an addon; `Cute.Open(page, section)`, `Cute.Refresh()`, `Cute.Print(msg)`, `Cute.Page()`, `Cute.ModuleOn(id)`, `Cute.Safe(fn, where)`, `Cute.Font()`, `Cute.Host(ui, key)`; `UI:Host(key)` (a frame under the scroll child, hidden by the next draw that does not ask for it).

- [ ] **Step 1: Write the failing test**

In `tools/cute/test/Cute_Example/Example.lua` append a second module:

```lua
-- a second module from the same folder: its own row in Settings > Modules (keyed Cute_Example:example_two), its own
-- choice; the folder loads when either is on and is off in the AddOns list only when both are off
Cute:RegisterModule({
  id = "example_two", addon = ADDON, title = "Example two", order = 91,
  notes = "The example's second module.",
  page = function(ui, scroll)
    local l = ui.labels:Get()
    l:SetPoint("TOPLEFT", 6, -6)
    l:SetWidth(scroll:Width() - 12)
    ui.FitText(l, "Toggled " .. (E.toggled or 0) .. " times.", scroll:Width() - 16)
    scroll:SetContentHeight(30)
  end,
  settings = function(_, col) col:Head("Example two") end,
  onToggle = function(on) E.toggled = (E.toggled or 0) + 1; E.lastOn = on end,
})
```

In the harness's module scenario, after the assertion `assert(moda.addons[2].loaded ...` that follows `click(boxOf(moda, "Cute Example"))` (around line 4480; find the first assertion that the tab `example` is shown), add:

```lua
    -- the folder's second module: its own row, off; ticked, its tab and its onToggle; the first unticked alone keeps
    -- the folder on in the AddOns list, both off turns it off
    local M2 = moda.C.Modules
    assert(M2.byId.example_two and M2.byId.example_two.key == "Cute_Example:example_two" and M2.byId.example.primary == true and not M2.byId.example_two.primary, "the second module keyed under the folder")
    assert(boxOf(moda, "Example two") and not boxOf(moda, "Example two"):GetChecked() and not tabsShown(moda):find("example_two"), "listed off, no tab")
    click(boxOf(moda, "Example two"))
    assert(M2.byId.example_two.active and tabsShown(moda):find("example_two") and moda.addons[2].private.toggled == 1 and moda.addons[2].private.lastOn == true, "ticked: its tab, onToggle(true) once: " .. tabsShown(moda))
    click(boxOf(moda, "Cute Example"))
    assert(not M2.byId.example.active and M2.byId.example_two.active and state.Cute_Example[moda.o.guid] ~= false and M2.AddonOn("Cute_Example"), "the first off alone: the folder stays on in the AddOns list")
    click(boxOf(moda, "Example two"))
    assert(moda.addons[2].private.toggled == 2 and moda.addons[2].private.lastOn == false and state.Cute_Example[moda.o.guid] == false, "both off: onToggle(false), off in the AddOns list")
    click(boxOf(moda, "Cute Example")) -- (back where the scenario's next lines expect it: the first on)
    moda.C.UI:Open("example")
    local host = moda.C.UI:Host("example_host")
    assert(host:IsShown() and host:GetParent() == moda.C.UI.scroll.child, "a host frame under the scroll child")
    moda.C.UI:Open("race")
    assert(not host:IsShown(), "a draw that does not ask for the host hides it")
```

- [ ] **Step 2: See it fail**

Run: `cd /Users/mikalbot/foreverrank/tools/cute && luajit harness.lua 2>&1 | grep -m1 -B2 "second module keyed\|error"`
Expected: the assertion `the second module keyed under the folder` fails (today `def.key` is the folder for both and the second registration is refused or keyed the same).

- [ ] **Step 3: Modules.lua**

Replace line 68 `def.key = def.addon or id` with:

```lua
  if def.addon then
    -- an addon's first module is its primary, keyed by the folder (Settings > Modules names the folder by its toc
    -- until it registers); the rest are keyed under it, each its own row and choice
    local first = true
    for _, d in ipairs(M.list) do if d.addon == def.addon then first = false end end
    def.primary = first
    def.key = first and def.addon or (def.addon .. ":" .. id)
  else
    def.key = id
  end
  if def.onToggle ~= nil and type(def.onToggle) ~= "function" then note("module " .. id .. " was not registered: onToggle is no function"); return false end
```

In `M.Apply` after `def.active = on` add `if def.onToggle then C.Safe(def.onToggle, "module " .. def.id .. ": toggle")(on) end`.

After `M.On` add:

```lua
-- the folder of a key ("Cute_Quest:route" is Cute_Quest's)
local function folderOf(key) return key:match("^(.-):") or key end
-- is any of an addon's modules wanted by this character: the primary's key (the folder) or one keyed under it
function M.AddonWanted(name)
  for key, v in pairs(choices()) do if v == true and folderOf(key) == name then return true end end
  return false
end
-- is any of an addon's registered modules on
function M.AddonOn(name)
  for _, def in ipairs(M.list) do if def.addon == name and M.On(def) then return true end end
  return false
end
```

`M.Set(key, on)`: replace the `if M.Found(key) then ... end` block with:

```lua
  local name = folderOf(key)
  if M.Found(name) then
    if on then if not registered(name) then M.Load(name) else enable(name, true) end
    elseif not M.AddonWanted(name) then M.pending[name] = nil; enable(name, false) end
  end
```

`M.Available(officer)`: replace the loop over `M.found` with:

```lua
  for _, a in ipairs(M.found) do
    local primary = registered(a.name)
    if not (primary and primary.officer and not officer) then
      out[#out + 1] = { key = a.name, title = primary and primary.title or a.title, notes = (primary and primary.notes) or a.notes, def = primary, addon = a }
    end
    -- the rest of the folder's modules, each its own row, once it has registered them
    for _, def in ipairs(M.list) do
      if def.addon == a.name and not def.primary and (not def.officer or officer) then
        out[#out + 1] = { key = def.key, title = def.title, notes = def.notes, def = def, addon = a }
      end
    end
  end
```

`M.Start`: `if M.OnKey(a.name) and not registered(a.name) then` becomes `if M.AddonWanted(a.name) and not registered(a.name) then`, and in its `offInList` branch `choices()[a.name] = false` becomes `for key in pairs(choices()) do if folderOf(key) == a.name then choices()[key] = false end end`.

The global (lines 79-84) becomes:

```lua
-- the one global Cute makes for module addons: Cute:RegisterModule({ ... }) from their own files, external always; and
-- what a module's pages need of the window and the core without reaching into them
Cute = { version = C.version }
function Cute:RegisterModule(def)
  if type(def) == "table" then def.core, def.builtin, def.default = nil, nil, nil end
  return C:RegisterModule(def)
end
function Cute.Open(page, section) C.UI:Open(page, section) end
function Cute.Refresh() if C.UI and C.UI.frame and C.UI.frame:IsShown() then C.UI:Refresh() end end
function Cute.Print(msg) C.Print(msg) end
function Cute.Page() return C.UI and C.UI.page or nil end
function Cute.ModuleOn(id) local def = M.byId[id]; return def ~= nil and def.active == true end
function Cute.Safe(fn, where) return C.Safe(fn, where) end
function Cute.Font() return C.UI and C.UI.FONT or "Fonts\\ARIALN.TTF" end
function Cute.Host(ui, key) return ui:Host(key) end
```

- [ ] **Step 4: UI.lua hosts**

After `UI:List` (line 771) add:

```lua
-- a frame of a page's own under the scroll child (a module that attaches a view it draws itself: the quest engine's
-- journal and gear pages); hidden by the next draw that does not ask for it, as the virtual lists are cleared
UI.hosts = {}
function UI:Host(key)
  local f = self.hosts[key]
  if not f then f = CreateFrame("Frame", nil, self.scroll.child); self.hosts[key] = f end
  f.gen = self.drawGen
  f:Show()
  return f
end
```

In `drawBody`: before `if page == "settings" then C.Settings_Draw(self)` add `self.drawGen = (self.drawGen or 0) + 1`; after the `for key, v in pairs(self.lists)` clearing line add `for _, f in pairs(self.hosts) do if f.gen ~= self.drawGen and f:IsShown() then f:Hide() end end`.

- [ ] **Step 5: Run Cute's harness**

Run: `cd /Users/mikalbot/foreverrank/tools/cute && luajit harness.lua 2>&1 | tail -3`
Expected: `layout problems: 0` then `OK`.

- [ ] **Step 6: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/cute/Cute/Modules.lua tools/cute/Cute/UI.lua tools/cute/test/Cute_Example/Example.lua tools/cute/harness.lua
git commit -m "cute: one addon may register several modules (a row and a choice each), onToggle, page hosts, the global's helpers for module pages

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: The build copies the engine; Shim.lua and Bridge.lua

**Files:**
- Modify: `tools/cute/build.py` (constants after line 33; `build_quest`; `build_zip`; `main`)
- Create: `tools/cute/Cute_Quest/Shim.lua`, `tools/cute/Cute_Quest/Bridge.lua`
- Create (by the build): `tools/cute/Cute_Quest/<engine files>`, `Pins.xml`, `art/`, `Cute_Quest.toc`
- Test: the build's own checks (`python3 tools/cute/build.py`), plus the refusal checks in Step 6

**Interfaces:**
- Consumes: Task 1's guard lines and `QB:Login`, Task 2's `Lists.lua`.
- Produces: `tools/cute/Cute_Quest/` complete; `QB.Engine` (Bridge: this copy's `QB`, or `QuestBankAPI`), `QB.dormant`, `QB.ART`, `QB.UI`'s window verbs on the copy; the wrapped `/qb`.

- [ ] **Step 1: Shim.lua**

```lua
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Cute_Quest: QuestBank's engine as Cute modules. This file runs first. The engine files after it are QuestBank's own,
-- copied by tools/cute/build.py (never edited here); each starts with `if QB.dormant then return end`.
-- With the addon QuestBank loaded, this copy sleeps: Bridge.lua and the pages talk to QuestBankAPI, QuestBank's own
-- table, and nothing of the engine runs twice. Without it, this copy is the engine: its saved variables are
-- CuteQuestDB, which the copied Core.lua reads and writes under the engine's name, QuestBankDB (one table, aliased
-- here when the saved variables arrive).
local ADDON, QB = ...
local A = type(C_AddOns) == "table" and C_AddOns or nil
local function loaded(name)
  if not (A and type(A.IsAddOnLoaded) == "function") then return false end
  local ok, v = pcall(A.IsAddOnLoaded, name)
  return ok and v == true
end
QB.dormant = loaded("QuestBank")
QB.host = "Cute"
QB.ADDON = ADDON
QB.ART = "Interface\\AddOns\\" .. ADDON .. "\\art\\"
if QB.dormant then return end
-- the saved variables, once the game hands them over (ADDON_LOADED for this addon; this frame is made before the
-- engine's, so it hears first). An error recorded while the files loaded made a QuestBankDB of its own: its errors
-- are kept
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, _, name)
  if name ~= ADDON then return end
  self:UnregisterEvent("ADDON_LOADED")
  local early = QuestBankDB
  if type(CuteQuestDB) ~= "table" then CuteQuestDB = {} end
  if type(early) == "table" and early ~= CuteQuestDB and type(early.errors) == "table" then
    CuteQuestDB.errors = CuteQuestDB.errors or {}
    for _, e in ipairs(early.errors) do table.insert(CuteQuestDB.errors, e) end
  end
  QuestBankDB = CuteQuestDB
end)
```

- [ ] **Step 2: Bridge.lua**

```lua
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Bridge: after the engine's files. QB.Engine is the engine the pages read: this copy, or QuestBankAPI while QuestBank
-- is loaded (then nothing below runs: QuestBank's own window serves its engine). For the copy, what QuestBank's
-- UI.lua (the window, not copied) gave the engine files: the window verbs on QB.UI (Lists.lua made the table), mapped
-- onto Cute's window; the login the engine never sees (loaded on demand, after PLAYER_LOGIN); the module's first-run
-- defaults; /qb routed to Cute's pages and otherwise to the engine's own handler.
local ADDON, QB = ...
local Cute = Cute
QB.Engine = QB.dormant and QuestBankAPI or QB
if QB.dormant then
  -- (QuestBank older than 6.1 sets no QuestBankAPI: the pages say so and draw nothing)
  if not QB.Engine then QB.missing = "QuestBank 6.1 or newer" end
  return
end
local E = QB
local UI = E.UI

-- QuestBank's tab numbers (its UI.lua: 1 Quest Log, 2 Plan, 3 Route, 4 Party, 5 Settings, 6 Now, 7 Journal, 8 Map)
-- as Cute's pages
local PAGE = { [1] = "quests", [2] = "quests", [3] = "route", [4] = "guide", [5] = "settings", [6] = "quests", [7] = "journal", [8] = "quests" }
function UI:Open(tab) Cute.Open(PAGE[tab] or "quests", tab == 5 and "quests" or nil) end
function UI:ShowTab(tab) self:Open(tab) end
function UI:TogglePage(tab) self:Open(tab) end
function UI:Toggle() Cute.Open("quests") end
function UI:Refresh() Cute.Refresh() end
function UI.OpenMap() if type(ToggleWorldMap) == "function" then ToggleWorldMap() end end
function UI.MapPageOn() return false end
function UI.Caret() end
function UI:ShowMenu(title, items)
  if type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function" then
    MenuUtil.CreateContextMenu(UIParent, function(_, root)
      root:CreateTitle(title)
      for _, it in ipairs(items) do root:CreateButton(it[1], it[2]) end
    end)
    return
  end
  local names = {}
  for _, it in ipairs(items) do names[#names + 1] = it[1] end
  Cute.Print(title .. ": no menu on this client (" .. table.concat(names, ", ") .. ").")
end
function UI:CopyLink(title, url) Cute.Print(title .. ": " .. url) end
function UI:PostDialog() end -- (Cute posts nothing: post.auto is off)
function UI:ShowErrors()
  local list = QuestBankDB and QuestBankDB.errors or {}
  Cute.Print(#list .. " quest engine errors" .. (#list > 0 and ", the newest first:" or "."))
  for i = 1, math.min(5, #list) do Cute.Print((list[i].where or "?") .. ": " .. tostring(list[i].msg)) end
end
UI.frame, UI.tab, UI.lastTab, UI.postFrame, UI.scrollToQuest = nil, nil, nil, nil, nil

-- the module's defaults, once: no QuestBank map page (the Map key is the game's), no posting, no update nag, no
-- level-up line, no welcome card (the choices are Settings rows), no minimap button (Cute has one)
local function firstRun()
  local s = E:Settings()
  if s.cuteDefaults then return end
  s.cuteDefaults = true
  s.mapPage, s.post.auto, s.updates, s.clockLevelMsg, s.welcome = false, false, false, false, nil
  s.minimap.hide = true
end

-- the login: this addon is loaded on demand, after PLAYER_LOGIN; the engine's login runs from here once the saved
-- variables are in (ADDON_LOADED, after Shim.lua's alias and Core.lua's QB:Settings)
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", E.Safe(function(self, _, name)
  if name ~= ADDON then return end
  self:UnregisterEvent("ADDON_LOADED")
  firstRun()
  E:Login()
end, "cute quest: login"))

-- /qb and /questbank: the pages Cute has, by name; everything else is the engine's own command (skip, way, done,
-- arrow, trace...)
local engineSlash = SlashCmdList.QUESTBANK
local WORD = { [""] = "quests", route = "route", prep = "quests", plan = "quests", available = "quests", journal = "journal", gear = "gear", map = "quests", maps = "quests", settings = "settings", options = "settings" }
SlashCmdList.QUESTBANK = function(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd = msg:match("^(%S*)"):lower()
  local page = WORD[cmd]
  if page and (cmd == msg:lower() or cmd == "") then Cute.Open(page, page == "settings" and "quests" or nil) return end
  if engineSlash then engineSlash(msg) end
end
```

- [ ] **Step 3: build.py**

After `SITE_CSS = ...` (line 33) add:

```python
QB_DIR = os.path.join(ROOT, "tools", "questbank", "QuestBank")
QB_TOC = os.path.join(QB_DIR, "QuestBank.toc")
QUEST = os.path.join(HERE, "Cute_Quest")
QUEST_TOC = os.path.join(QUEST, "Cute_Quest.toc")
# QuestBank's engine, as Cute_Quest carries it: every file QuestBank.toc may list. UI.lua (the window) is never copied;
# a file not here stops the build until it has been checked in Cute's harness
ENGINE_KNOWN = {
    "Data.lua", "Core.lua", "Lists.lua", "Discover.lua", "Survey.lua", "Game.lua", "Loot.lua", "Observe.lua", "Timer.lua",
    "Link.lua", "MinimapTiles.lua", "MinimapView.lua", "MinimapRoute.lua", "Minimap.lua", "DungeonMap.lua", "Glow.lua",
    "Walk.lua", "Camp.lua", "Model.lua", "Legacy.lua", "Travel.lua", "Pins.lua", "QuestMap.lua", "Pins.xml", "Arrow.lua",
    "Target.lua", "Sync.lua", "Auto.lua", "Guide.lua", "MapPage.lua", "Gear.lua", "StepFrame.lua", "Tips.lua",
}
# Cute_Quest's own files, in the toc's order after the engine
OWN = ["Bridge.lua", "Band.lua", "PageQuests.lua", "PageRoute.lua", "PageMap.lua", "PageJournal.lua", "PageGear.lua", "PageCamp.lua"]
```

And the step (uses `shutil`: add it to the `import` line):

```python
def qb_version():
    m = re.search(r"^## Version:\s*(\S+)", open(QB_TOC, encoding="utf-8").read(), re.M)
    return m.group(1) if m else "?"


def build_quest(version):
    """Cute_Quest: QuestBank's engine files copied byte for byte (UI.lua left out), its art, and the toc this writes.
    Stops on a file QuestBank.toc lists that ENGINE_KNOWN does not, a copy that differs from its source after writing,
    a copied Lua file without its dormant guard, or a stray file in the folder"""
    listed = [l.strip() for l in open(QB_TOC, encoding="utf-8").read().splitlines() if re.match(r"^[\w]+\.(lua|xml)$", l.strip())]
    unknown = [f for f in listed if f not in ENGINE_KNOWN and f != "UI.lua"]
    if unknown:
        sys.exit("QuestBank.toc lists files build.py does not know: %s. Check each in Cute's harness, then add it to ENGINE_KNOWN." % ", ".join(unknown))
    engine = [f for f in listed if f != "UI.lua"]
    os.makedirs(os.path.join(QUEST, "art"), exist_ok=True)
    pairs = [(os.path.join(QB_DIR, f), os.path.join(QUEST, f)) for f in engine]
    for name in sorted(os.listdir(os.path.join(QB_DIR, "art"))):
        if not name.startswith("."):
            pairs.append((os.path.join(QB_DIR, "art", name), os.path.join(QUEST, "art", name)))
    written = 0
    for src, dst in pairs:
        data = open(src, "rb").read()
        if not os.path.isfile(dst) or open(dst, "rb").read() != data:
            shutil.copyfile(src, dst)
            written += 1
        if open(dst, "rb").read() != data:
            problem("Cute_Quest/%s differs from its source after the copy" % os.path.relpath(dst, QUEST))
    for f in engine:
        if f.endswith(".lua"):
            src = open(os.path.join(QUEST, f), encoding="ascii", errors="replace").read()
            if not re.search(r"^local \w+, QB = \.\.\.\nif QB\.dormant then return end\n", src, re.M):
                problem("Cute_Quest/%s has no `if QB.dormant then return end` after its vararg line" % f)
    own = {"Shim.lua"} | set(OWN)
    for name in sorted(os.listdir(QUEST)):
        if name.endswith((".lua", ".xml")) and name not in engine and name not in own:
            problem("Cute_Quest/%s is neither QuestBank's nor one of Cute_Quest's own files: remove it" % name)
    for name in own:
        if not os.path.isfile(os.path.join(QUEST, name)):
            problem("Cute_Quest/%s is missing" % name)
    toc = "\n".join([
        "## Interface: 16001",
        "## Title: |cffe8b24aCute|r Quest",
        "## Notes: QuestBank's guiding as Cute modules: the step now in the Guide, and Quests, Route, Map, Journal, Gear and Camp, each a switch in Settings, Modules. Loads only while one is on.",
        "## Author: Mikal",
        "## Version: %s" % version,
        "## X-License: GPL-3.0-or-later",
        "## X-QuestBank: %s" % qb_version(),
        "## Dependencies: Cute",
        "## LoadOnDemand: 1",
        "## X-Cute-Module: 1",
        "## SavedVariables: CuteQuestDB",
        "",
        "Shim.lua",
    ] + engine + OWN) + "\n"
    old = open(QUEST_TOC, encoding="ascii").read() if os.path.isfile(QUEST_TOC) else None
    if old != toc:
        open(QUEST_TOC, "w", encoding="ascii", newline="\n").write(toc)
    ok("Cute_Quest: %d engine files from QuestBank %s (%d written), toc %s" % (len(engine), qb_version(), written, "written" if old != toc else "unchanged"))
```

`build_zip` zips both folders: `subprocess.run(["zip", "-rq", ZIP, "Cute", "Cute_Quest", "-x", "*.DS_Store"], cwd=HERE, check=True)`, and its skip condition also checks `os.path.isdir(QUEST)`. In `main()` call `build_quest(version)` right after `build_changes(version)`, and move the `if problems:` report so that a problem from `build_quest` is printed before the zip (place `if problems: ... sys.exit(1)` right after `build_quest(version)` as well as at the end).

- [ ] **Step 4: Run the build**

Run: `cd /Users/mikalbot/foreverrank && python3 tools/cute/build.py 2>&1 | tail -12`
Expected: `Cute_Quest/Band.lua is missing` and the six Page files listed as problems, `problems: 7`. (The own files come in Tasks 7-11.) Create them now as one-line stubs so the build and the harness run: each `-- SPDX-License-Identifier: GPL-3.0-or-later` followed by `local ADDON, QB = ...` and nothing else. Run the build again.
Expected: `problems: 0` then `OK`, and `ls tools/cute/Cute_Quest` shows 33 engine files, `art/`, `Cute_Quest.toc`, `Shim.lua`, `Bridge.lua`, `Band.lua`, the six `Page*.lua`.

- [ ] **Step 5: Run Cute's harness (nothing loads the new folder yet)**

Run: `cd /Users/mikalbot/foreverrank/tools/cute && luajit harness.lua 2>&1 | tail -3`
Expected: `layout problems: 0` then `OK`.

- [ ] **Step 6: The build's refusals**

Each of these must end `problems: 1` and exit 1, then be undone:

```bash
cd /Users/mikalbot/foreverrank
echo "Extra.lua" >> tools/questbank/QuestBank/QuestBank.toc && python3 tools/cute/build.py | tail -2; git checkout tools/questbank/QuestBank/QuestBank.toc
echo "-- x" > tools/cute/Cute_Quest/Stray.lua && python3 tools/cute/build.py | tail -3; rm tools/cute/Cute_Quest/Stray.lua
```

(The first prints the unknown-file message and exits 1 before `problems:`; the second lists the stray file.)

- [ ] **Step 7: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/cute/build.py tools/cute/Cute_Quest addons/cute/Cute.zip addons/cute/index.html
git commit -m "cute: Cute_Quest, QuestBank's engine copied by the build with its shim and bridge; the zip ships both folders

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Cute's harness can load the engine

**Files:**
- Create: `tools/cute/test/quest_mocks.lua`
- Modify: `tools/cute/harness.lua:42-54` (the whitelist), `:928-935` (the module folder lookup), `:920` (install the mocks for `o.quest`)
- Test: a new scenario in `tools/cute/harness.lua` (after the modules scenario's `do ... end`, before the privacy block)

**Interfaces:**
- Produces: `quest_mocks.lua` returning `function(env, c, o, newObj, api, secret)`; a client made with `o.quest = true` has every global the engine reads at load, `Login` and a first `Changed`; `o.modules` may name `Cute_Quest`, found under `tools/cute/`.

- [ ] **Step 1: Write the failing scenario**

```lua
-- Cute_Quest, the quest engine as a module addon (tools/cute/Cute_Quest, written by build.py from QuestBank): listed
-- by its toc's title and not loaded; its folder's row ticked, it loads, the saved variables are one table under two
-- names, the engine logs in from the bridge (never from PLAYER_LOGIN, which is past), the catalog is built, the step
-- frame is up and flat; Data.lua is never loaded for a character that keeps every quest module off
do
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = rank <= 1 and "Officer" or "Raider", class = "WARRIOR", level = 5, online = true } end
  isolated({ member("Rone", 1), member("Pim", 3) }, function()
    local state = {}
    local rone = newClient(charOf({ "Rone", 1, "Officer", "WARRIOR", 5 }, { modules = { "Cute_Quest" }, addonState = state, quest = true }))
    login(rone)
    tickAll(5)
    local M = rone.C.Modules
    assert(#M.found == 1 and M.found[1].name == "Cute_Quest" and M.found[1].lod and M.found[1].title == "Cute Quest", "found by its toc: " .. tostring(M.found[1] and M.found[1].title))
    assert(not rone.addons[2].loaded and rone.addons[2].private.Data == nil, "not loaded: no catalog in memory")
    rone.C.UI:Open("settings", "modules")
    local box = checkBox(rone, function(cb) return cb.label and cb.label:GetText() == "Cute Quest" end)
    assert(box, "its row in Settings > Modules")
    click(box)
    tick(rone, 6) -- (the bridge's login, the engine's first plan four seconds on)
    local a = rone.addons[2]
    local QB = a.private
    assert(a.loaded and QB.Data and QB.Data.Q and QB.Engine == QB and not QB.dormant, "loaded: the catalog built, this copy the engine")
    assert(rone.env.CuteQuestDB and rone.env.QuestBankDB == rone.env.CuteQuestDB and rone.env.CuteQuestDB.settings, "one saved table under both names, the settings in it")
    assert(QB.loginDone and QB.state and QB.state.level == 5, "the engine logged in from the bridge: level " .. tostring(QB.state and QB.state.level))
    assert(rone.env.CuteQuestDB.settings.mapPage == false and rone.env.CuteQuestDB.settings.post.auto == false and rone.env.CuteQuestDB.settings.welcome == nil, "the module's defaults set once")
    assert(rone.env.SlashCmdList.QUESTBANK, "/qb is routed")
    leave(rone)
  end)
end
```

- [ ] **Step 2: See it fail**

Run: `cd /Users/mikalbot/foreverrank/tools/cute && luajit harness.lua 2>&1 | grep -m1 "Cute_Quest\|error" `
Expected: the toc is not found (`test/Cute_Quest/Cute_Quest.toc`), or a nil global the engine reads.

- [ ] **Step 3: The folder lookup, the whitelist, the mocks**

In `harness.lua:928-935` the module folder is `MODULES_DIR .. "/" .. name`; make it `local dir = MODULES_DIR .. "/" .. name; if not io.open(dir .. "/" .. name .. ".toc") then dir = HERE .. "/" .. name end; local a = { name = name, dir = dir, private = {} }` (a folder under `test/` first, else beside `Cute/`, where the build writes `Cute_Quest`).

Grow the `allow([[ ... ]])` list (line 44) by QuestBank's: `IsForbidden SetPushedTexture GetTextColor SetMultiLine HighlightText SetRotation SetAtlas SetPassThroughButtons SetCooldown SetHideCountdownNumbers SetUserPlaced GetZoom SetZoom GetZoomLevels SetStartPoint SetEndPoint SetThickness CreateLine SetTextInsets SetAttribute GetAttribute SetGradient SetClipsChildren PingLocation SetSnapToPixelGrid SetTexelSnappingBias` and, where `BACKDROP` is used, also accept QuestBank's `MODEL` (`SetDisplayInfo SetCreature SetPortraitZoom ClearModel SetKeepModelOnHide`) and `POI` (`DrawBlob DrawNone SetMapID SetFillTexture SetBorderTexture SetFillAlpha SetBorderAlpha SetBorderScalar`) sets (copy the two tables from `tools/questbank/harness.lua:25-30` and add them where `BACKDROP` is consulted in `newObj`).

Create `tools/cute/test/quest_mocks.lua`:

```lua
-- The quest engine's mocks for Cute's harness: what QuestBank's engine reads of the client that Cute's own mock does
-- not define, ported from tools/questbank/harness.lua's newClient (its lines are named at each block) and kept to the
-- shape the engine reads. Installed on a client made with o.quest = true, after Cute's mocks, never over them.
--   install(env, c, o, newObj, api, secret)
return function(env, c, o, newObj, api, secret)
  local function has(name) return env[name] ~= nil end
  -- the minimap in its cluster (questbank/harness.lua:415-424): the engine's Minimap.lua sizes and moves it
  env.MinimapCluster = newObj("Frame", nil, env.UIParent); env.MinimapCluster:SetSize(256, 256)
  env.MinimapCluster.MinimapContainer = newObj("Frame", nil, env.MinimapCluster); env.MinimapCluster.MinimapContainer:SetSize(215, 226)
  env.Minimap:SetParent(env.MinimapCluster.MinimapContainer)
  for _, key in ipairs({ "ZoomIn", "ZoomOut" }) do env.Minimap[key] = newObj("Button", nil, env.Minimap); env.Minimap[key]:Hide() end
  env.IsIndoors = function() return false end
  env.IsMouseButtonDown = function() return false end
  -- the context menus (431-447): entries recorded in c.contextMenus, as MenuUtil's root gets them
  c.contextMenus = {}
  env.MenuUtil = { CreateContextMenu = function(owner, gen)
    local entries, root = {}, {}
    function root:CreateCheckbox(text, get, set) entries[#entries + 1] = { kind = "check", text = text, get = get, set = set } end
    function root:CreateButton(text, fn) entries[#entries + 1] = { kind = "button", text = text, set = fn } end
    function root:CreateDivider() entries[#entries + 1] = { kind = "divider" } end
    function root:CreateTitle(text) entries[#entries + 1] = { kind = "title", text = text } end
    gen(owner, root)
    entries.owner = owner
    c.contextMenus[#c.contextMenus + 1] = entries
  end }
  <the blocks below, each copied from the questbank harness line range named, with `o.` fields defaulted so a Cute
   character (o.level, o.class, o.faction, o.done, o.log as Cute's charOf makes them) reads sensibly:>
  --   env.C_Minimap (449-454), env.C_CVar (455), env.C_NamePlate (475), env.GetBindLocation (558), env.UnitPosition (572-600:
  --   from o.world = { continent, wx, wy }, default { 0, -8914, -133 }, Northshire), env.C_UnitAuras's GetAuraDataByIndex
  --   kept Cute's, env.C_GossipInfo (629-651), env.GetQuestLogSpecialItemInfo (652), env.C_Container's GetContainerItemID,
  --   GetContainerItemLink, GetContainerItemQuestInfo added to Cute's table (729-736), env.C_Item's GetItemIconByID,
  --   GetItemCooldown, RequestLoadItemDataByID, GetItemByID added to Cute's (737-763), env.C_SpellBook (764-787),
  --   env.C_TooltipInfo (788-825), env.C_QuestLog's GetQuestObjectives, GetInfo (by o.log's ids), GetMaxNumQuestsCanAccept,
  --   IsPushableQuest, GetQuestTagInfo, AddQuestWatch, RemoveQuestWatch, GetQuestWatchType, RequestLoadQuestByID,
  --   GetAvailableQuests, GetActiveQuests added to Cute's (826-860), env.C_Map (861-948), env.C_Texture (949-953),
  --   env.C_TaxiMap (960-981), env.C_DeathInfo (991-999), env.WorldMapFrame (1055-...), and the map canvas family from
  --   the questbank harness's BASE (281-379: CreateFromMixins, MapCanvasDataProviderMixin, the five Blizzard providers,
  --   Mixin, secureexecuterange, GetQuestDifficultyColor, MapCanvasMixin, MapCanvasScrollControllerMixin, GAME_LEVELS)
  --   set on env where Cute's BASE lacks them.
end
```

Write each block in full in the file (the comment above is the index of what to port, not the code). In `harness.lua`'s `newClient`, after `for name in pairs(o.without or {}) do env[name] = nil end` (line 920), add `if o.quest then dofile(HERE .. "/test/quest_mocks.lua")(env, c, o, newObj, api, secret) end`. The `api` wrapper and `secret` are locals of `newClient`/the file; pass them as they are named there.

- [ ] **Step 4: Run until the scenario passes**

Run: `cd /Users/mikalbot/foreverrank/tools/cute && luajit harness.lua 2>&1 | grep -m3 "error\|Cute_Quest\|nil value"`
Each failure names a global or method the engine reads: add it to `quest_mocks.lua` from QuestBank's harness (never a stub that returns nothing where QuestBank's mock returns a shape). Repeat until the scenario's assertions pass; then the full gate:
Run: `luajit harness.lua 2>&1 | tail -3`
Expected: `layout problems: 0` then `OK`.

- [ ] **Step 5: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/cute/harness.lua tools/cute/test/quest_mocks.lua
git commit -m "cute harness: loads Cute_Quest (the engine's mocks ported from QuestBank's harness, a module folder beside Cute)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: The Guide: the step band and one dungeon (Cute core)

**Files:**
- Modify: `tools/cute/Cute/Guide.lua:674-864` (`C.Guide_Draw`, the registration's `settings`)
- Test: `tools/cute/harness.lua` (the Guide scenarios: every assertion that reads a strip, Next up, an officer's line or Learned in play as a row; scenario 9, 30 and the owner's-client block are the ones to search)

**Interfaces:**
- Consumes: `Cute.QuestBand` (Task 8; nil until then), `C.Modules.byId.quests` (nil until Task 8), `G.Items`, `G.Pick`, `G.Source`, `G.MakeRow`, `UI.bandLines`, `UI:List`.
- Produces: the band as the spec's table; the list = head + the pick's rows; officers' learned lines in the head's tooltip; `UI.bandBig` (a 15 px FontString on the band).

- [ ] **Step 1: Write the failing assertions**

In the harness, find the Guide scenario that opens the Guide for the officer Yezin and reads `texts(c)` (grep `openGuide(` and `Missing enchants`). Replace its assertions on the page's rows with:

```lua
    openGuide(yezin)
    local t = texts(yezin)
    assert(t:find("Tick Quests in Settings, Modules for the step now.", 1, true), "the band says the quest module is off:\n" .. t)
    assert(t:find("Run The Deadmines", 1, true) and t:find("Bosses", 1, true) and t:find("Online", 1, true), "the pick's card: name, bosses, mates:\n" .. t)
    assert(not t:find("Missing enchants", 1, true) and not t:find("Next up", 1, true) and not t:find("Pace", 1, true) and not t:find("Learned in play", 1, true), "nothing else on the page:\n" .. t)
    local n = 0
    for _, r in ipairs(yezin.C.UI.lists.guide.items) do if r:IsShown() and r.bar:IsShown() then n = n + 1 end end
    assert(n == 1, "one card, marked: " .. n)
    local head
    for _, r in ipairs(yezin.C.UI.lists.guide.items) do if r:IsShown() and r.name:GetText():find("^Run ") then head = r end end
    assert(head and tipOf(head):find("Learned in play", 1, true) and tipOf(head):find("From research", 1, true), "the officer's head tooltip: the reasons, the source, what the guild learned")
```

Every other Guide assertion that reads a strip, a timeline or an officer's row from `texts()` is rewritten the same way: the value it looked for is read from `tipOf(head)` where the spec keeps it (the learned lines) or deleted where the spec drops it (strips, Next up, other cards). Keep every assertion about the band's pick line, invites, combat and `G.Pick`'s choices: they still hold.

- [ ] **Step 2: See them fail**

Run: `cd /Users/mikalbot/foreverrank/tools/cute && luajit harness.lua 2>&1 | grep -m1 "band says the quest module"`
Expected: the assertion fails (the band holds the pick line today).

- [ ] **Step 3: Rewrite C.Guide_Draw**

Replace the band section (from `local first, detail = G.Source()` through `UI:SetBand(y + 4)`) with:

```lua
  local first, detail = G.Source()
  local y = 4
  -- a band row: the step now big and white, the rest as lines; each with its tooltip and click
  local function bandRow(s, c, big, tip, fn)
    local l = UI.bandLines:Get()
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", 0, -y)
    local h = big and (ROW + 6) or ROW
    l:SetSize(w, h)
    l.bg:SetColorTexture(1, 1, 1, big and 0.05 or 0)
    l.bar:SetShown(big)
    l.bar:SetColorTexture(K.WHITE[1], K.WHITE[2], K.WHITE[3], 1)
    l.val:Hide(); l.who:Hide()
    l.fn, l.tip = fn, tip
    if big then
      UI.bandBig = UI.bandBig or UI.Text(UI.band, 15, K.WHITE)
      UI.bandBig:ClearAllPoints(); UI.bandBig:SetPoint("LEFT", l, "LEFT", 8, 0); UI.bandBig:SetWidth(w - 16)
      fitText(UI.bandBig, s, w - 20)
      UI.bandBig:Show()
      l.name:Hide()
    else
      l.name:ClearAllPoints(); l.name:SetPoint("LEFT", 8, 0); l.name:SetWidth(w - 16); l.name:SetJustifyH("LEFT")
      color(l.name, c)
      fitText(l.name, s, w - 20)
      l.name:Show()
    end
    y = y + h
    return l
  end
  if UI.bandBig then UI.bandBig:Hide() end
  local Q = Cute.QuestBand
  local qm = C.Modules.byId.quests
  if qm and qm.active and Q and Q.On() then
    local steps = Q.Steps()
    local s1 = steps[1]
    local text1 = s1 and Q.Text(s1) or "Nothing to do yet: Quests says why."
    bandRow(text1, K.WHITE, true, function(tip) tip:AddLine(text1, 1, 1, 1, true); tip:AddLine("Click: the Quests page. Right-click: not now, drop, lock, scale, hide.", 0.5, 0.5, 0.5, true) end,
      function(_, which) if which == "RightButton" then Q.Menu(s1) else Q.Open() end end)
    for i = 2, 3 do
      local s = steps[i]
      if s then local t = Q.Text(s); bandRow(t, K.DIM, false, function(tip) tip:AddLine(t, 1, 1, 1, true) end) end
    end
    local ttl, _, measured = Q.TimeToLevel()
    if ttl then bandRow(ttl, K.MUTE, false, function(tip) tip:AddLine(measured and "From your XP an hour at this level." or "From the plan's XP a minute.", 1, 1, 1, true) end) end
    for _, m in ipairs(Q.Members()) do bandRow(m.name .. ": " .. m.text, UI.ClassColor(m.class)) end
  else
    bandRow("Tick Quests in Settings, Modules for the step now.", K.DIM, false,
      function(tip) tip:AddLine("The quest engine's step frame, in this band: what to do now, the next two steps, the time to level, your party's steps.", 1, 1, 1, true) end,
      function() C.UI:Open("settings", "modules") end)
  end
  UI:SetBand(y + 4)
```

`bandLines` rows take only the left click today (`UI:MakeLine`); in `UI:MakeLine` add `r:RegisterForClicks("LeftButtonUp", "RightButtonUp")` and pass the button on: `r:SetScript("OnClick", function(self, which) if self.fn then self.fn(self, which) end end)`.

Then the list: after `local items, plan = G.Items(officer)` keep `items` but draw a reduced list. Replace the `local list = UI:List("guide", G.MakeRow)` ... `list:Set(#items, ...)` call's source list with `shown`, built just before it:

```lua
  -- the page: the pick's line as its head (the officer's guild line at its right), then the picked dungeon's rows
  -- alone; everything else G.Items gathers (the other cards, the strips, Next up, the officers' lines) lives in the
  -- head's tooltip where the spec keeps it (the learned lines) or nowhere
  local top = plan.next
  local learned = {}
  local inLearned = false
  for _, it in ipairs(items) do
    if it.kind == "head" then inLearned = (it.name or ""):find("^Learned") ~= nil
    elseif inLearned and (it.kind == "item" or it.kind == "note") then learned[#learned + 1] = (it.name or "") .. (it.who and (" " .. it.who) or "") end
  end
  local shown = { { kind = "head", name = top.line, who = officer and plan.guild and plan.guild.line or nil, tip = function(tip)
    if top.tip then top.tip(tip) end
    tip:AddLine(" ")
    tip:AddLine(first, 1, 1, 1, true); tip:AddLine(detail, 0.7, 0.7, 0.7, true)
    if officer and plan.guild and plan.guild.tip then tip:AddLine(" "); plan.guild.tip(tip) end
    if officer and #learned > 0 then
      tip:AddLine(" "); tip:AddLine("Learned in play", 1, 1, 1)
      for _, l in ipairs(learned) do tip:AddLine(l, 0.8, 0.8, 0.8, true) end
    end
  end } }
  local take = false
  for _, it in ipairs(items) do
    if it.kind == "card" then take = it.pick == true
    elseif it.kind == "gap" or it.kind == "head" then take = false end
    if take then shown[#shown + 1] = it end
  end
```

and `list:Set(#shown, 0, ROW, function(r, i, ly) local it = shown[i] ...` with `sf:SetContentHeight(#shown * ROW + 8)`. The fill function body stays as it is (it reads `it.kind`). The `for _, id in ipairs({ "level", "unenchanted", "enchanted" })` line keeps only `"level"`.

The registration's `settings` gains, after `col:Rule("guideAhead", "Dungeons ahead")`:

```lua
    local Q, qm = Cute.QuestBand, C.Modules.byId.quests
    if qm and qm.active and Q and Q.Settings then Q.Settings(col) end
```

- [ ] **Step 4: Run Cute's harness, fix every Guide assertion the spec changed**

Run: `cd /Users/mikalbot/foreverrank/tools/cute && luajit harness.lua 2>&1 | tail -3`
Expected: `layout problems: 0` then `OK`. A failing assertion that reads a dropped row is rewritten per Step 1's rule; one that reads the pick line, an invite or a combat state is a bug in the draw.

- [ ] **Step 5: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/cute/Cute/Guide.lua tools/cute/Cute/UI.lua tools/cute/harness.lua
git commit -m "cute guide: the step band (from the quest module, or one line saying to switch it on) and one dungeon, the rest in the head's tooltip

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Band.lua and PageQuests.lua: the step band's source and the Quests module

**Files:**
- Create (replace the stubs): `tools/cute/Cute_Quest/Band.lua`, `tools/cute/Cute_Quest/PageQuests.lua`
- Test: `tools/cute/harness.lua` (the Cute_Quest scenario of Task 6 grows)

**Interfaces:**
- Consumes: `QB.Engine` (Bridge), `E.Guide.Steps/Text/TimeToLevel/MemberSteps`, `E.StepFrame.Menu/Apply`, `E.Arrow.Set`, `E.UI.PlaceGroups/Candidates/QuestClick/QuestTooltip`, `E.Quest.Get`, `E:Status`, `E.Short`, `E.state`, `E.logReady`, `E.Model.Busy`, `E:Settings()`, `E:MarkDirty()`, `Cute.*` (Task 4), `ui:List`, `ui:MakeLine`, `ui.labels`, `scroll:Width()`, `scroll:SetContentHeight`, `col:Head/Note/Check/Choice`.
- Produces: `Cute.QuestBand` (the spec's table), `QB.Skin` on the copy, the module `quests` (page, settings, onToggle, events).

- [ ] **Step 1: Grow the scenario**

After `assert(rone.env.SlashCmdList.QUESTBANK, ...)` in Task 6's scenario add:

```lua
    -- the Quests module registered as the folder's primary: its tab after the Guide, its section; the Guide's band
    -- shows the step now (the engine's first step for a level-5 warrior in Northshire with quest 7 in the log)
    assert(M.byId.quests and M.byId.quests.primary and M.byId.quests.active, "Quests on, the folder's primary")
    assert(tabsShown(rone):find("^race guide quests ") or tabsShown(rone):find(" guide quests "), "the Quests tab after the Guide: " .. tabsShown(rone))
    assert(rone.C.Modules.OnKey("guide") or (rone.C.Modules.Set("guide", true) == nil), "the Guide on for the band")
    rone.C.UI:Open("guide")
    local t = texts(rone)
    assert(not t:find("Tick Quests in Settings", 1, true), "the band no longer says to switch Quests on:\n" .. t)
    local steps = QB.Guide.Steps()
    assert(steps[1] and t:find(QB.Guide.Text(steps[1]), 1, true), "the step now in the band: " .. tostring(steps[1] and QB.Guide.Text(steps[1])) .. "\n" .. t)
    local sf = rone.env.QuestBankStep
    assert(sf and sf:IsShown() and sf.__flat, "the step frame up, in Cute's skin")
    check(rone.C.UI.frame, "guide with the quest band")
    rone.C.UI:Open("quests")
    local tq = texts(rone)
    assert(tq:find("Now", 1, true) and tq:find("Available", 1, true) and tq:find("Highest XP", 1, true), "the Quests page's three heads:\n" .. tq)
    check(rone.C.UI.frame, "quests page")
    rone.C.UI:Open("settings", "quests")
    local ts = texts(rone)
    assert(ts:find("Accept for me", 1, true) and ts:find("Progress in mob tooltips", 1, true), "the Quests section's rows:\n" .. ts)
    rone.C.UI:Open("settings", "guide")
    assert(texts(rone):find("Step frame", 1, true) and texts(rone):find("Direction arrow", 1, true), "the Guide's section gained the frame and arrow rows")
    -- unticked: the engine's guide off, the frame hidden, the band says so again
    click(boxOf(rone, "Quests"))
    assert(not M.byId.quests.active and rone.env.CuteQuestDB.settings.guide.on == false and not sf:IsShown(), "off: the engine's guide off, the frame hidden")
    rone.C.UI:Open("guide")
    assert(texts(rone):find("Tick Quests in Settings, Modules", 1, true), "the band says so again")
    click(boxOf(rone, "Quests"))
```

(`boxOf` as the modules scenario defines it; define it locally the same way here.)

- [ ] **Step 2: See it fail**

Run: `cd /Users/mikalbot/foreverrank/tools/cute && luajit harness.lua 2>&1 | grep -m1 "Quests on, the folder"`
Expected: fails (nothing registers `quests` yet).

- [ ] **Step 3: Band.lua**

```lua
-- SPDX-License-Identifier: GPL-3.0-or-later
-- The step band: what the Guide's band draws while the Quests module is on, read from the engine (Cute.QuestBand), and
-- the three Guide rows for the step frame and the arrow. Sets the engine's skin, so the step frame and the arrow the
-- copy draws are flat, in Cute's font and greys (QuestBank's own, while QuestBank is loaded, keep QuestBank's look).
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
if not E then return end

if not QB.dormant then
  local INK, SOFT, WHITE = { 0.86, 0.86, 0.86 }, { 0.58, 0.58, 0.58 }, { 0.96, 0.96, 0.96 }
  E.Skin = {
    font = Cute.Font(), INK = INK, SOFT = SOFT, ACCENT = WHITE,
    -- a flat fill and a 1 px edge, as Cute's window (UI.lua's skin)
    Backdrop = function(f)
      if not f.SetBackdrop then return end
      f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
      f:SetBackdropColor(0.035, 0.035, 0.035, 0.94)
      f:SetBackdropBorderColor(0, 0, 0, 1)
    end,
  }
end

Cute.QuestBand = {
  On = function() return Cute.ModuleOn("quests") and E.logReady == true end,
  Steps = function() return E.Guide.Steps() end,
  Text = function(s) return E.Guide.Text(s) end,
  TimeToLevel = function() return E.Guide.TimeToLevel() end,
  Members = function() return E.Guide.MemberSteps() end,
  Open = function() Cute.Open("quests") end,
  Menu = function(s) if E.StepFrame and E.StepFrame.Menu then E.StepFrame:Menu(s) end end,
  -- the Guide's rows for the frame and the arrow (the engine's settings; QuestBank's own while it is loaded)
  Settings = function(col)
    local s = E:Settings()
    col:Head("The step now")
    col:Check("Step frame", s.guide.frame == true, true, function(on) s.guide.frame = on; if E.StepFrame then E.StepFrame.Apply() end end)
    col:Check("Direction arrow", s.arrow == true, true, function(on) if E.Arrow then E.Arrow:Set(on) else s.arrow = on end end)
    col:Check("Lock the step frame", s.guide.locked == true, true, function(on) s.guide.locked = on; if E.StepFrame then E.StepFrame.Apply() end end)
  end,
}
```

- [ ] **Step 4: PageQuests.lua**

```lua
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Quests: the three places worth your time (the engine's Available view, its first three), the rest folded, and the
-- highest XP as a finder; a place opens to its quests. One list in Cute's rows. The module is the folder's primary:
-- its switch loads Cute_Quest, and switches the engine's guide (the step band, the frame) on with it.
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local P = { open = {}, more = false }
local function redraw() Cute.Refresh() end
local function minutes(m) return m and (math.floor(m + 0.5) .. " min") or nil end

local function placeRow(g, K)
  local open = g.open + g.picks + g.held
  return { kind = "place", g = g, name = g.cat and g.cat.name or "?", val = E.Short(g.fetch + g.left) .. " XP",
    who = open .. (open == 1 and " quest" or " quests") .. (g.nearest and (", " .. minutes(g.nearest)) or ""),
    c = P.open[g.idx] and K.WHITE or K.INK,
    fn = function() P.open[g.idx] = not P.open[g.idx] or nil; Cute.Refresh() end,
    tip = function(tip)
      tip:AddLine(g.cat and g.cat.name or "?", 1, 1, 1)
      for _, it in ipairs(g.quests) do if it.grp ~= 6 then tip:AddDoubleLine(it.q.name, it.st.text or "", 0.85, 0.85, 0.85, 0.6, 0.6, 0.6) end end
      tip:AddLine("Click: its quests.", 0.5, 0.5, 0.5)
    end }
end
local function questRow(q, st, value, who, K)
  return { kind = "quest", name = q.name, val = E.Short(value) .. " XP", who = who or st.text, c = (E.state.log[q.id] and K.INK) or K.DIM,
    fn = function(_, which) E.UI.QuestClick(q, st, which) end,
    tip = function(tip) E.UI.QuestTooltip(tip, q, st, value) end }
end

local function items(K)
  local out = {}
  if not E.logReady then out[1] = { kind = "note", name = "Reading your quest log.", c = K.MUTE }; return out end
  local order, _, _, _, hubName = E.UI.PlaceGroups()
  out[#out + 1] = { kind = "head", name = "Now", who = hubName and ("from " .. hubName) or nil }
  local function place(g)
    out[#out + 1] = placeRow(g, K)
    if P.open[g.idx] then
      for _, it in ipairs(g.quests) do
        if it.grp <= 4 then out[#out + 1] = questRow(it.q, it.st, it.value, nil, K) end
      end
    end
  end
  for i = 1, math.min(3, #order) do place(order[i]) end
  if #order == 0 then out[#out + 1] = { kind = "note", name = E.Model.Busy() and "Planning." or "Nothing to suggest here yet.", c = K.MUTE } end
  if #order > 3 then
    out[#out + 1] = { kind = "head", name = "Available", who = (#order - 3) .. " more places" }
    out[#out + 1] = { kind = "more", name = P.more and "Fewer" or "Show them", c = K.DIM, fn = function() P.more = not P.more; Cute.Refresh() end }
    if P.more then for i = 4, #order do place(order[i]) end end
  end
  out[#out + 1] = { kind = "head", name = "Highest XP" }
  local D = E.Data
  for _, c in ipairs(E.UI:Candidates(8, E.state.level)) do
    local q = E.Quest.Get(c.id)
    if q then
      local who = minutes(c.mins) or (D.CAT[c.cat] and D.CAT[c.cat].name) or nil
      out[#out + 1] = questRow(q, E:Status(q), c.full, who, K)
    end
  end
  return out
end

local function make(parent, ui)
  local r = ui:MakeLine(parent)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self, which) if self.fn then self.fn(self, which) end end)
  return r
end

function P.Draw(ui, scroll)
  local K, ROW = ui.COLORS, ui.ROW
  local w = scroll:Width()
  local list = items(K)
  local v = ui:List("quests", function(parent) return make(parent, ui) end)
  v:Set(#list, 0, ROW, function(r, i, ly)
    local it = list[i]
    r:SetHeight(ROW)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, -ly)
    r:SetWidth(w)
    r.bg:SetColorTexture(1, 1, 1, it.kind == "head" and 0.06 or (it.kind == "place" and 0.035) or 0)
    r.bar:Hide()
    r.fn, r.tip = it.fn, it.tip
    local x = it.kind == "quest" and 24 or 8
    local right = (it.val and 100 or 0) + (it.who and 150 or 0)
    r.name:ClearAllPoints(); r.name:SetPoint("LEFT", x, 0); r.name:SetWidth(w - x - right - 8); r.name:SetJustifyH("LEFT")
    ui.Color(r.name, it.c or (it.kind == "head" and K.WHITE) or K.INK)
    ui.FitText(r.name, it.name or "", w - x - right - 12)
    if it.who then r.who:ClearAllPoints(); r.who:SetPoint("RIGHT", -4, 0); r.who:SetWidth(146); r.who:SetJustifyH("RIGHT"); ui.Color(r.who, K.DIM); ui.FitText(r.who, it.who, 142); r.who:Show() else r.who:Hide() end
    if it.val then r.val:ClearAllPoints(); r.val:SetPoint("RIGHT", it.who and -154 or -4, 0); r.val:SetWidth(96); r.val:SetJustifyH("RIGHT"); ui.Color(r.val, K.INK); ui.FitText(r.val, it.val, 92); r.val:Show() else r.val:Hide() end
  end)
  ui.virtual = function() v:Show(ui.scroll.bar:GetValue() or 0, ui.scroll:View()) end
  scroll:SetContentHeight(#list * ROW + 8)
end

local ACCEPT = { { "Off", "off" }, { "On my route", "route" }, { "Worth taking", "worth" } }
function P.Settings(_, col)
  local s = E:Settings()
  col:Head("Quests")
  local names, current = {}, "Off"
  for _, a in ipairs(ACCEPT) do names[#names + 1] = a[1]; if s.autoAccept == a[2] then current = a[1] end end
  col:Choice("Accept for me", names, current, function(v) for _, a in ipairs(ACCEPT) do if a[1] == v then s.autoAccept = a[2] end end end)
  col:Check("Hand finished quests in for me", s.autoTurnIn == true, true, function(on) s.autoTurnIn = on end)
  col:Check("Progress in mob tooltips", s.tipProgress ~= false, true, function(on) s.tipProgress = on end)
  col:Check("Share with your party", s.share.party ~= false, true, function(on) s.share.party = on end)
  col:Check("Note what the game shows, for foreverrank.com", s.noteGame ~= false, true, function(on) s.noteGame = on end)
end

-- the switch: the engine's guide (the step band, the frame) with it; off, the arrow too (the Guide's row brings it
-- back). While QuestBank is loaded its settings are its own: nothing is set
function P.Toggle(on)
  if QB.dormant then Cute.Refresh() return end
  local s = E:Settings()
  s.guide.on, s.guide.frame = on, on
  if s.welcome then s.welcome = nil end
  if not on and E.Arrow then E.Arrow:Set(false) end
  if on and s.arrow and E.Arrow then E.Arrow:Set(true) end
  if E.StepFrame then E.StepFrame.Apply() end
  E:MarkDirty()
end

Cute:RegisterModule({
  id = "quests", addon = ADDON, title = "Quests", order = 21,
  notes = "The three places worth your time, the rest folded, the highest XP; the step now in the Guide.",
  page = P.Draw, settings = P.Settings, onToggle = P.Toggle,
  events = { QUEST_LOG_UPDATE = redraw, QUEST_ACCEPTED = redraw, QUEST_TURNED_IN = redraw, PLAYER_LEVEL_UP = redraw, ZONE_CHANGED_NEW_AREA = redraw },
})
```

If `E.missing` is set (QuestBank without `QuestBankAPI`), `P.Draw` draws one note row, `"Quests needs " .. QB.missing .. "."`, and returns; add that as the first lines of `items`.

- [ ] **Step 5: Build, then run Cute's harness**

Run: `cd /Users/mikalbot/foreverrank && python3 tools/cute/build.py | tail -2 && cd tools/cute && luajit harness.lua 2>&1 | tail -3`
Expected: `problems: 0`, `OK`; then `layout problems: 0`, `OK`. A layout problem on the quests page is fixed in `P.Draw`'s widths, never by widening the window.

- [ ] **Step 6: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/cute/Cute_Quest tools/cute/harness.lua addons/cute/Cute.zip addons/cute/index.html
git commit -m "cute quest: the step band and the Quests module (Now, Available folded, Highest XP), the engine's guide switched with it

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: PageRoute.lua

**Files:**
- Create (replace the stub): `tools/cute/Cute_Quest/PageRoute.lua`
- Test: `tools/cute/harness.lua` (the Cute_Quest scenario grows)

**Interfaces:**
- Consumes: `E.Target.Route()` (legs with `stop.name`, `t`, `rows[i].q`, `rows[i].xp`), `E.routeNow`, `E.Run.Get/Start/Stop`, `E.Comma`, `ui.bandLines`, `ui.bandButtons`, `ui:SetBand`.
- Produces: module `route`.

- [ ] **Step 1: Grow the scenario**

After the Quests assertions (before `click(boxOf(rone, "Quests"))` that switches it off) add:

```lua
    click(boxOf(rone, "Route"))
    assert(M.byId.route and M.byId.route.key == "Cute_Quest:route" and M.byId.route.active and tabsShown(rone):find("route", 1, true), "Route on, keyed under the folder: " .. tabsShown(rone))
    rone.C.UI:Open("route")
    local tr = texts(rone)
    assert(tr:find(" XP, level ", 1, true) and (tr:find("Start run", 1, true) or tr:find("End run", 1, true)), "the route's band: the summary and the run button:\n" .. tr)
    assert(tr:find("^1%. ") or tr:find("\n1%. ") or tr:find("Nothing to hand in yet.", 1, true), "the legs numbered, or the empty line:\n" .. tr)
    check(rone.C.UI.frame, "route page")
    rone.C.UI:Open("settings", "route")
    assert(texts(rone):find("Follow", 1, true) and texts(rone):find("hearthstone", 1, true), "the Route section's rows")
```

- [ ] **Step 2: See it fail**

Run: `cd /Users/mikalbot/foreverrank/tools/cute && luajit harness.lua 2>&1 | grep -m1 "Route on, keyed"`
Expected: fails.

- [ ] **Step 3: PageRoute.lua**

```lua
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Route: the hand-in stops in order with the minutes to each, the first marked (the one target the arrow and the
-- minimap follow); the band holds the route's sum and the run button. Nothing here is clicked but the button.
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local R = {}
local function redraw() Cute.Refresh() end

function R.Draw(ui, scroll)
  local K, ROW = ui.COLORS, ui.ROW
  local w = scroll:Width()
  local r = (E.Target and E.Target.Route()) or E.routeNow or { legs = {} }
  local run = E.Run and E.Run.Get()
  -- the band: one line and one button
  local l = ui.bandLines:Get()
  l:ClearAllPoints(); l:SetPoint("TOPLEFT", 0, -4); l:SetSize(w - 170, ROW)
  l.bg:SetColorTexture(1, 1, 1, 0); l.bar:Hide(); l.val:Hide(); l.who:Hide(); l.fn, l.tip = nil, nil
  l.name:ClearAllPoints(); l.name:SetPoint("LEFT", 8, 0); l.name:SetWidth(w - 186); l.name:SetJustifyH("LEFT")
  ui.Color(l.name, K.INK)
  ui.FitText(l.name, string.format("%s XP, level %.1f, %d min%s", E.Comma(r.xp or 0), r.level or 0, math.floor((r.t or 0) + 0.5), (E.Model and E.Model.Busy()) and ", planning" or ""), w - 190)
  local b = ui.bandButtons:Get()
  b:ClearAllPoints(); b:SetPoint("TOPRIGHT", 0, -3); b:SetWidth(160)
  b:SetLabel(run and "End run" or "Start run")
  b:SetOn(E.Run ~= nil)
  b:SetScript("OnClick", Cute.Safe(function() if E.Run.Get() then E.Run.Stop() else E:Recompute(true); E.Run.Start() end; Cute.Refresh() end, "route: run"))
  ui:SetBand(ROW + 8)
  -- the legs
  local items = {}
  for i, leg in ipairs(r.legs or {}) do
    items[#items + 1] = { name = i .. ". " .. (leg.stop and leg.stop.name or "?"), val = math.floor((leg.t or 0) + 0.5) .. " min",
      who = #(leg.rows or {}) .. (#(leg.rows or {}) == 1 and " quest" or " quests"), first = i == 1,
      tip = function(tip)
        tip:AddLine(leg.stop and leg.stop.name or "?", 1, 1, 1)
        for _, row in ipairs(leg.rows or {}) do tip:AddDoubleLine(row.q and row.q.name or "?", E.Comma(row.xp or 0) .. " XP", 0.85, 0.85, 0.85, 0.6, 0.6, 0.6) end
      end }
  end
  if #items == 0 then items[1] = { name = "Nothing to hand in yet.", c = K.MUTE } end
  local v = ui:List("route", function(parent) return ui:MakeLine(parent) end)
  v:Set(#items, 0, ROW, function(row, i, ly)
    local it = items[i]
    row:SetHeight(ROW); row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -ly); row:SetWidth(w)
    row.bg:SetColorTexture(1, 1, 1, it.first and 0.035 or 0)
    row.bar:SetShown(it.first == true); row.bar:SetColorTexture(K.WHITE[1], K.WHITE[2], K.WHITE[3], 1)
    row.fn, row.tip = nil, it.tip
    row.name:ClearAllPoints(); row.name:SetPoint("LEFT", 8, 0); row.name:SetWidth(w - 260); row.name:SetJustifyH("LEFT")
    ui.Color(row.name, it.c or (it.first and K.WHITE) or K.INK)
    ui.FitText(row.name, it.name, w - 264)
    if it.who then row.who:ClearAllPoints(); row.who:SetPoint("RIGHT", -4, 0); row.who:SetWidth(146); row.who:SetJustifyH("RIGHT"); ui.Color(row.who, K.DIM); ui.FitText(row.who, it.who, 142); row.who:Show() else row.who:Hide() end
    if it.val then row.val:ClearAllPoints(); row.val:SetPoint("RIGHT", -154, 0); row.val:SetWidth(96); row.val:SetJustifyH("RIGHT"); ui.Color(row.val, K.INK); ui.FitText(row.val, it.val, 92); row.val:Show() else row.val:Hide() end
  end)
  ui.virtual = function() v:Show(ui.scroll.bar:GetValue() or 0, ui.scroll:View()) end
  scroll:SetContentHeight(#items * ROW + 8)
end

function R.Settings(_, col)
  local s = E:Settings()
  col:Head("Route")
  col:Choice("Follow", { "The plan", "Ready now" }, s.routeQuest == "now" and "Ready now" or "The plan", function(v) s.routeQuest = v == "Ready now" and "now" or nil; E:MarkDirty() end)
  col:Check("Show the way step by step on the arrow", s.arrowTravel ~= false, true, function(on) s.arrowTravel = on; if E.Arrow and E.Arrow.Invalidate then E.Arrow.Invalidate() end end)
  col:Check("The hearthstone may be a step", s.arrowHearth ~= false, true, function(on) s.arrowHearth = on; if E.Arrow and E.Arrow.Invalidate then E.Arrow.Invalidate() end end)
end

Cute:RegisterModule({
  id = "route", addon = ADDON, title = "Route", order = 22,
  notes = "The hand-in stops in order with minutes; the first is where the arrow points.",
  page = R.Draw, settings = R.Settings,
  events = { QUEST_LOG_UPDATE = redraw, QUEST_TURNED_IN = redraw, ZONE_CHANGED_NEW_AREA = redraw },
})
```

- [ ] **Step 4: Build and run**

Run: `cd /Users/mikalbot/foreverrank && python3 tools/cute/build.py | tail -2 && cd tools/cute && luajit harness.lua 2>&1 | tail -3`
Expected: `problems: 0`, `OK`, `layout problems: 0`, `OK`.

- [ ] **Step 5: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/cute/Cute_Quest tools/cute/harness.lua addons/cute/Cute.zip addons/cute/index.html
git commit -m "cute quest: the Route module, the stops with minutes and the run button

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: PageJournal.lua and PageGear.lua

**Files:**
- Create (replace the stubs): `tools/cute/Cute_Quest/PageJournal.lua`, `tools/cute/Cute_Quest/PageGear.lua`
- Test: `tools/cute/harness.lua`

**Interfaces:**
- Consumes: `E.DMap.Attach(page, w, h)`, `E.DMap.Refresh()`, `E.Gear.Attach(page, w, h)`, `E.Gear.Refresh()`, `E.Gear.RefreshSoon()`, `Cute.Host(ui, key)`, `E:Settings().djShow`, `.finderAhead`.
- Produces: modules `journal`, `gear`.

- [ ] **Step 1: Grow the scenario**

```lua
    for _, name in ipairs({ "Journal", "Gear" }) do click(boxOf(rone, name)) end
    rone.C.UI:Open("journal")
    local host = rone.C.UI.hosts.journal
    assert(host and host:IsShown() and #host.__kids > 0, "the journal attached to its host")
    check(rone.C.UI.frame, "journal page")
    rone.C.UI:Open("gear")
    assert(not host:IsShown() and rone.C.UI.hosts.gear and rone.C.UI.hosts.gear:IsShown(), "the gear host shown, the journal's hidden")
    check(rone.C.UI.frame, "gear page")
    rone.C.UI:Open("settings", "journal")
    assert(texts(rone):find("Chests and events", 1, true), "the Journal section")
    rone.C.UI:Open("settings", "gear")
    assert(texts(rone):find("2 levels ahead", 1, true), "the Gear section")
```

(`host.__kids` is the harness's children list; if it is named otherwise in `adopt`, use that name.)

- [ ] **Step 2: See it fail**, then write the two files

PageJournal.lua:

```lua
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Journal: the engine's Dungeon Journal (DungeonMap.lua) on a host frame inside Cute's scroll area, its cover and floor
-- art as they are. Its four kinds as the section.
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local J = {}
local H = 468

function J.Draw(ui, scroll)
  local w = scroll:Width()
  local host = Cute.Host(ui, "journal")
  host:ClearAllPoints(); host:SetPoint("TOPLEFT", 0, 0); host:SetSize(w, H)
  if E.DMap then E.DMap.Attach(host, w, H); E.DMap.Refresh() end
  scroll:SetContentHeight(H + 8)
end

local KINDS = { { "boss", "Bosses" }, { "rare", "Rares" }, { "trash", "Trash" }, { "other", "Chests and events" } }
function J.Settings(_, col)
  local s = E:Settings()
  col:Head("Journal")
  for _, k in ipairs(KINDS) do
    col:Check(k[2], s.djShow[k[1]] == true, true, function(on) s.djShow[k[1]] = on; if E.DMap then E.DMap.Refresh() end end)
  end
end

Cute:RegisterModule({ id = "journal", addon = ADDON, title = "Journal", order = 24,
  notes = "Every dungeon: its bosses, their recorded loot, its quests, its floors.", page = J.Draw, settings = J.Settings })
```

PageGear.lua:

```lua
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Gear: the engine's Gear page (Gear.lua) on a host frame, its text in Cute's skin. One setting.
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local G = {}
local H = 440

function G.Draw(ui, scroll)
  local w = scroll:Width()
  local host = Cute.Host(ui, "gear")
  host:ClearAllPoints(); host:SetPoint("TOPLEFT", 0, 0); host:SetSize(w, H)
  if E.Gear then E.Gear.Attach(host, w, H); E.Gear.Refresh() end
  scroll:SetContentHeight(H + 8)
end

function G.Settings(_, col)
  local s = E:Settings()
  col:Head("Gear")
  col:Check("Quests up to 2 levels ahead", s.finderAhead == true, true, function(on) s.finderAhead = on; if E.Gear and E.Gear.RefreshSoon then E.Gear.RefreshSoon() end end)
  col:Note("An upgrade is a quest reward in reach or a dungeon drop at your level, judged for your class and skills.")
end

Cute:RegisterModule({ id = "gear", addon = ADDON, title = "Gear", order = 25,
  notes = "What you wear and the best upgrade for each slot: a quest reward in reach or a dungeon drop.", page = G.Draw, settings = G.Settings })
```

- [ ] **Step 3: Build and run**

Run: `cd /Users/mikalbot/foreverrank && python3 tools/cute/build.py | tail -2 && cd tools/cute && luajit harness.lua 2>&1 | tail -3`
Expected: `problems: 0`, `OK`, `layout problems: 0`, `OK`. A whitelist refusal names a method the journal or the gear page uses: add it to the harness's `allow` list from QuestBank's.

- [ ] **Step 4: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/cute/Cute_Quest tools/cute/harness.lua addons/cute/Cute.zip addons/cute/index.html
git commit -m "cute quest: the Journal and Gear modules, the engine's pages on hosts in Cute's window

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 11: PageMap.lua and PageCamp.lua (switches only)

**Files:**
- Create (replace the stubs): `tools/cute/Cute_Quest/PageMap.lua`, `tools/cute/Cute_Quest/PageCamp.lua`
- Test: `tools/cute/harness.lua`

**Interfaces:**
- Consumes: `E.QuestMap:Toggle()`, `E.Pins:Toggle()`, `E.Mini.Invalidate()`, `E.Glow.Set(on)`, `E.Glow.SetStyle(style)`, the settings keys named.
- Produces: modules `map`, `camp` (no page).

- [ ] **Step 1: Grow the scenario**

```lua
    for _, name in ipairs({ "Map", "Camp" }) do click(boxOf(rone, name)) end
    assert(not tabsShown(rone):find("map", 1, true) and not tabsShown(rone):find("camp", 1, true), "no tab for a module without a page: " .. tabsShown(rone))
    assert(sectionsShown(rone):find("map", 1, true) and sectionsShown(rone):find("camp", 1, true), "their sections: " .. sectionsShown(rone))
    local s = rone.env.CuteQuestDB.settings
    assert(s.mapIcons == true and s.pins == true and s.minimapGivers == true and s.campBar == true and s.glow.on == true, "on: the switches on")
    rone.C.UI:Open("settings", "map")
    click(checkBox(rone, function(cb) return cb.label and cb.label:GetText() == "Minimap far view" end))
    assert(s.mmExtended == false, "a row writes the engine's setting")
    click(boxOf(rone, "Map")); click(boxOf(rone, "Camp"))
    assert(s.mapIcons == false and s.pins == false and s.minimapPins == false and s.campBar == false and s.glow.on == false, "off: the switches off")
    for _, name in ipairs({ "Map", "Camp" }) do click(boxOf(rone, name)) end
    -- every page at both sizes for an officer with every quest module on, and for a member
    for _, page in ipairs({ "guide", "quests", "route", "journal", "gear", "settings" }) do rone.C.UI:Open(page); check(rone.C.UI.frame, "officer, every quest module on: " .. page) end
```

- [ ] **Step 2: See it fail**, then write the two files

PageMap.lua:

```lua
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Map: no page of its own. The switches of the engine's map files, which draw on the game's world map and minimap
-- (QuestMap.lua, Pins.lua, Minimap.lua, MinimapView.lua). Off, every switch is off; on, every one on.
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local M = {}

local function mini() if E.Mini and E.Mini.Invalidate then E.Mini.Invalidate() end end
function M.Settings(_, col)
  local s = E:Settings()
  col:Head("Map")
  col:Check("Quest icons on the world map", s.mapIcons ~= false, true, function(on) if (s.mapIcons ~= false) ~= on and E.QuestMap then E.QuestMap:Toggle() else s.mapIcons = on end end)
  col:Check("Route pins on the world map", s.pins ~= false, true, function(on) if (s.pins ~= false) ~= on and E.Pins then E.Pins:Toggle() else s.pins = on end end)
  col:Check("Route on the minimap", s.minimapPins ~= false and s.minimapLines ~= false, true, function(on) s.minimapPins, s.minimapLines = on, on; mini() end)
  col:Check("A ! on the minimap for quests you can take", s.minimapGivers == true, true, function(on) s.minimapGivers = on; mini() end)
  col:Check("Minimap far view", s.mmExtended ~= false, true, function(on) s.mmExtended = on; mini() end)
end

function M.Toggle(on)
  if QB.dormant then return end
  local s = E:Settings()
  if (s.mapIcons ~= false) ~= on and E.QuestMap then E.QuestMap:Toggle() else s.mapIcons = on end
  if (s.pins ~= false) ~= on and E.Pins then E.Pins:Toggle() else s.pins = on end
  s.minimapPins, s.minimapLines, s.minimapGivers, s.mmExtended = on, on, on, on
  mini()
  E:MarkDirty()
end

Cute:RegisterModule({ id = "map", addon = ADDON, title = "Map", order = 23,
  notes = "Quest icons and the route on the game's world map and minimap.", settings = M.Settings, onToggle = M.Toggle })
```

If `E.QuestMap:Toggle()` or `E.Pins:Toggle()` do not flip `s.mapIcons` / `s.pins` (read `QuestMap.lua:1063` and `Pins.lua:924` before writing), set the flag and call the file's refresh instead; the scenario's assertion on `s.mapIcons` is the judge.

PageCamp.lua:

```lua
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Camp: no page of its own. The camp bar, the missing-buffs banner, the sleeping bag and the sellers (Camp.lua), and
-- the interact light (Glow.lua), as switches. Off, the bar, the banner and the light are off; on, all three on.
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local Cp = {}
local STYLES = { { "Sparkle", "sparkle" }, { "Light", "light" }, { "Game's", "game" } }

function Cp.Settings(_, col)
  local s = E:Settings()
  col:Head("Camp")
  col:Check("Camp bar", s.campBar ~= false, true, function(on) s.campBar = on end)
  col:Check("Missing buffs when you leave town", s.remind.buffs ~= false, true, function(on) s.remind.buffs = on end)
  col:Check("Sleeping bag", s.remind.bag ~= false, true, function(on) s.remind.bag = on end)
  col:Check("Sellers of camp goods", s.remind.wood ~= false, true, function(on) s.remind.wood = on end)
  col:Check("Interact light", s.glow.on ~= false, true, function(on) if E.Glow then E.Glow.Set(on) else s.glow.on = on end end)
  local names, current = {}, "Sparkle"
  for _, st in ipairs(STYLES) do names[#names + 1] = st[1]; if s.glow.style == st[2] then current = st[1] end end
  col:Choice("Light style", names, current, function(v) for _, st in ipairs(STYLES) do if st[1] == v then if E.Glow then E.Glow.SetStyle(st[2]) else s.glow.style = st[2] end end end end)
end

function Cp.Toggle(on)
  if QB.dormant then return end
  local s = E:Settings()
  s.campBar, s.remind.buffs = on, on
  if E.Glow then E.Glow.Set(on) else s.glow.on = on end
end

Cute:RegisterModule({ id = "camp", addon = ADDON, title = "Camp", order = 26,
  notes = "The camp bar, the missing-buffs banner and the interact light.", settings = Cp.Settings, onToggle = Cp.Toggle })
```

(`Glow.Set(on)` is `Glow.lua:898`; read it: if it does not write `s.glow.on`, set the flag beside the call.)

- [ ] **Step 3: Build and run**

Run: `cd /Users/mikalbot/foreverrank && python3 tools/cute/build.py | tail -2 && cd tools/cute && luajit harness.lua 2>&1 | tail -3`
Expected: `problems: 0`, `OK`, `layout problems: 0`, `OK`.

- [ ] **Step 4: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/cute/Cute_Quest tools/cute/harness.lua addons/cute/Cute.zip addons/cute/index.html
git commit -m "cute quest: the Map and Camp modules, switches over the engine's map files, camp bar and light

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 12: With QuestBank loaded, nothing runs twice

**Files:**
- Test: `tools/cute/harness.lua` (a scenario after the Cute_Quest scenario)

**Interfaces:**
- Consumes: `Shim.lua`'s `QB.dormant`, `Bridge.lua`'s `QB.Engine = QuestBankAPI`, the pages' reads of `E`.

- [ ] **Step 1: Write the scenario**

```lua
-- QuestBank loaded beside Cute: Cute_Quest's copy sleeps. Its files return at their second line (no catalog built, no
-- event frame, no /qb of its own), the engine the pages read is QuestBankAPI (QuestBank's own table), the band draws
-- QuestBank's step, the module toggles set none of QuestBank's settings, and QuestBank's step frame is left as it is
do
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = "Raider", class = "WARRIOR", level = 5, online = true } end
  isolated({ member("Pim", 3) }, function()
    local pim = newClient(charOf({ "Pim", 3, "Raider", "WARRIOR", 5 }, { modules = { "Cute_Quest" }, addonState = {}, quest = true }))
    local isLoaded = pim.env.C_AddOns.IsAddOnLoaded
    pim.env.C_AddOns.IsAddOnLoaded = function(x) if x == "QuestBank" then return true, true end return isLoaded(x) end
    local settings = { guide = { on = true, frame = true }, arrow = true, mapIcons = true, pins = true, campBar = true, glow = { on = true, style = "sparkle" }, remind = { buffs = true, bag = true, wood = true }, share = { party = true }, djShow = { boss = true, rare = true, trash = false, other = true } }
    local step = { kind = "objective", qid = 7, text = "Kill Kobold Vermin 3/8" }
    pim.env.QuestBankAPI = {
      version = "6.1.0", logReady = true, state = { level = 5, log = {} }, routeNow = { legs = {}, xp = 0, level = 5, t = 0 },
      Settings = function() return settings end, MarkDirty = function() end, Comma = tostring, Short = tostring,
      Model = { Busy = function() return false end }, Data = { CAT = {} }, Quest = { Get = function() return nil end },
      Guide = { Steps = function() return { step } end, Text = function(s) return s.text end, TimeToLevel = function() return "about 9 min to level 6", 9, true end, MemberSteps = function() return {} end },
      StepFrame = { Menu = function() end, Apply = function() end }, Arrow = { Set = function(on) settings.arrow = on end },
      UI = { PlaceGroups = function() return {}, {}, nil, nil, nil end, Candidates = function() return {} end, QuestClick = function() end, QuestTooltip = function() end },
      Target = { Route = function() return { legs = {}, xp = 0, level = 5, t = 0 } end }, Run = { Get = function() return nil end },
      DMap = { Attach = function() end, Refresh = function() end }, Gear = { Attach = function() end, Refresh = function() end, RefreshSoon = function() end },
    }
    login(pim)
    tickAll(5)
    local framesBefore = #pim.frames
    pim.C.Modules.Set("Cute_Quest", true)
    tick(pim, 6)
    local a = pim.addons[2]
    local QB = a.private
    assert(a.loaded and QB.dormant == true and QB.Engine == pim.env.QuestBankAPI, "loaded, dormant, the engine QuestBank's")
    assert(QB.Data == nil and QB.Guide == nil and QB.eventFrame == nil and QB.loginDone == nil, "the copy's files returned at once: no catalog, no guide, no event frame")
    assert(pim.env.SLASH_QUESTBANK1 == nil and pim.env.SlashCmdList.QUESTBANK == nil, "no /qb from the copy")
    for i = framesBefore + 1, #pim.frames do
      local f = pim.frames[i]
      assert(not (f.__events and f.__events.QUEST_TURNED_IN), "no frame of the copy hears QUEST_TURNED_IN")
    end
    assert(pim.env.CuteQuestDB == nil, "no saved table of the copy's own while it sleeps")
    if not pim.C.Modules.OnKey("guide") then pim.C.Modules.Set("guide", true) end
    pim.C.UI:Open("guide")
    assert(texts(pim):find("Kill Kobold Vermin 3/8", 1, true) and texts(pim):find("about 9 min to level 6", 1, true), "the band draws QuestBank's step:\n" .. texts(pim))
    pim.C.Modules.Set("Cute_Quest", false)
    assert(settings.guide.on == true and settings.arrow == true, "the toggle set none of QuestBank's settings")
    leave(pim)
  end)
end
```

- [ ] **Step 2: Run**

Run: `cd /Users/mikalbot/foreverrank/tools/cute && luajit harness.lua 2>&1 | tail -3`
Expected: `layout problems: 0` then `OK`. A failure here is a path in `Shim.lua`, `Bridge.lua` or a page that reads the copy instead of `QB.Engine`, or an engine file whose guard is not its first statement; fix that file, never the scenario.

- [ ] **Step 3: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/cute/harness.lua tools/cute/Cute_Quest
git commit -m "cute harness: with QuestBank loaded the copy sleeps and the pages read QuestBankAPI; nothing runs twice

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 13: Memory and garbage gates for the module

**Files:**
- Test: `tools/cute/harness.lua` (a block after Task 12's scenario, run in the seeded pass only: `if SEEDED then ... end`)

**Interfaces:**
- Consumes: QuestBank's `kept` and `ownBytes` (harness.lua 17530-17600), ported with `Cute_Quest/` as the source match and `{ a.private, env.QuestBankDB }` as the roots.

- [ ] **Step 1: Write the gates**

```lua
-- memory: what the module keeps after login with every quest page opened (reachable from its private table and its
-- saved variables; LuaJIT's layout), and the garbage the engine's own code makes with nothing changed. The budgets are
-- QuestBank's (its harness, the memory block): 11 MB kept, a re-plan with the window shut under 100 KB, the Guide's
-- Replan under 64 KB. ownBytes charges an allocation to the file of the function that made it: Cute_Quest/ only
if SEEDED then
  local function ownBytes(fn)
    local getinfo, count = debug.getinfo, collectgarbage
    local acc, mine, last, mark = 0, false, 0, 0
    local function hook(ev)
      local now = count("count")
      if mine then acc = acc + (now - last) end
      local info = getinfo(ev == "call" and 2 or 3, "S")
      if info and info.what ~= "C" then mine = info.source:find("Cute_Quest/", 1, true) ~= nil end
      if count("count") - mark > 65536 then collectgarbage("collect"); collectgarbage("stop"); mark = count("count") end
      last = count("count")
    end
    if jit then jit.off(); jit.flush() end
    collectgarbage("collect"); collectgarbage("stop")
    last = count("count"); mark = last
    debug.sethook(hook, "cr")
    fn()
    debug.sethook()
    collectgarbage("restart")
    if jit then jit.on() end
    return acc * 1024
  end
  <kept(c, roots) copied from tools/questbank/harness.lua:17557-17603 with: `local total, queue, qi = 0, roots, 1`
   in place of `{ c.QB, c.env.QuestBankDB }`, `seen[c.C] = true` added, the widget test `rawget(v, "__kind") and
   rawget(v, "__scripts")` kept, and `info.source:find("Cute_Quest/", 1, true)` in place of "/QuestBank/">
  local function member(name, rank) return { name = name .. "-Forever", guid = guidOf(name), rank = rank, rankName = "Officer", class = "PALADIN", level = 20, online = true } end
  isolated({ member("Memo", 1) }, function()
    local mc = newClient(charOf({ "Memo", 1, "Officer", "PALADIN", 20 }, { modules = { "Cute_Quest" }, addonState = {}, quest = true }))
    login(mc)
    tickAll(5)
    for _, key in ipairs({ "Cute_Quest", "Cute_Quest:route", "Cute_Quest:map", "Cute_Quest:journal", "Cute_Quest:gear", "Cute_Quest:camp" }) do mc.C.Modules.Set(key, true) end
    if not mc.C.Modules.OnKey("guide") then mc.C.Modules.Set("guide", true) end
    tick(mc, 6)
    local QB = mc.addons[2].private
    QB.Model.Finish()
    for _, page in ipairs({ "guide", "quests", "route", "journal", "gear" }) do mc.C.UI:Open(page) end
    mc.C.UI.frame:Hide()
    local KEEP_BUDGET = 11 * 1024
    local keptKB = kept(mc, { QB, mc.env.QuestBankDB })
    print(string.format("cute quest memory: kept after login and every page %.0f KB (budget %d KB)", keptKB, KEEP_BUDGET))
    assert(keptKB < KEEP_BUDGET, string.format("the quest module keeps %.0f KB, over its budget of %d KB", keptKB, KEEP_BUDGET))
    QB:Changed()
    local refresh = ownBytes(function() QB:Changed(); QB:Changed() end) / 2
    print(string.format("cute quest: a refresh with the window shut %.0f KB of garbage", refresh / 1024))
    assert(refresh < 100 * 1024, string.format("a refresh with nothing changed made %.0f KB (at most 100)", refresh / 1024))
    QB.Guide.Replan()
    local replan = ownBytes(function() QB.Guide.Replan() end)
    print(string.format("cute quest: the Guide's Replan with nothing changed %.0f KB", replan / 1024))
    assert(replan < 64 * 1024, string.format("the Guide's Replan made %.0f KB (at most 64)", replan / 1024))
    leave(mc)
  end)
end
```

- [ ] **Step 2: Run**

Run: `cd /Users/mikalbot/foreverrank/tools/cute && luajit harness.lua 2>&1 | grep "cute quest" ; luajit harness.lua 2>&1 | tail -3`
Expected: the three measurement lines, then `layout problems: 0`, `OK`. Over budget means the copy keeps what QuestBank does not (a page's items table kept across draws, a host rebuilt per draw): find it with the `kept` walk, never by raising the budget.

- [ ] **Step 3: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/cute/harness.lua
git commit -m "cute harness: the quest module's memory and garbage gates, QuestBank's budgets

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 14: The page, the version, the README; every gate

**Files:**
- Modify: `addons/cute/index.html` (the Guide mock around line 1666, `sections()` at 2102, the modules branch of `settings()`, the tab list at 400-407, Install at 459-465, the changelog at 471), `tools/cute/Cute/Cute.toc` (Version, Notes), `tools/cute/Cute/Core.lua:13`, `tools/cute/README.md` (Files, Modules, the Guide, Test, Ship)
- Test: `python3 tools/cute/build.py`; both harnesses

- [ ] **Step 1: Version 0.7.0**

`Cute.toc`: `## Version: 0.7.0`; its `## Notes:` gains ", and QuestBank's guiding as modules (Cute_Quest)". `Core.lua:13`: `C.version = "0.7.0"`.

- [ ] **Step 2: The changelog line (one, no catalogue)**

In `index.html` before the `0.6.1` entry:

```html
      <li><b>0.7.0</b>The Guide shows your next step and one dungeon, the next best run; QuestBank's quest pages come as modules, Quests, Route, Map, Journal, Gear and Camp, each a switch in Settings, Modules, in a second folder that loads only while one is on.</li>
```

- [ ] **Step 3: Install**

Replace the first two Install steps with:

```html
      <li>Download <a href="Cute.zip">Cute.zip</a> and unzip it. You get two folders, <code>Cute</code> and <code>Cute_Quest</code>.</li>
      <li>Put both in <code>Interface\AddOns</code>, next to your other addons. <code>Cute_Quest</code> loads only while one of its modules is on.</li>
```

and in the third step replace "The Guide switches on in Settings, Modules." with "The Guide, Quests, Route, Map, Journal, Gear and Camp switch on in Settings, Modules; with Quests on, the Guide shows your next step."

- [ ] **Step 4: The mock**

In the mock's script: a `QUEST_MODULES` list `[["quests", "Quests", notes], ["route", "Route", notes], ["map", "Map", notes], ["journal", "Journal", notes], ["gear", "Gear", notes], ["camp", "Camp", notes]]` with the notes strings from the registry entries in the spec; `mods()` gains a flag per id (off by default); the modules branch of `settings()` draws a row per entry after the Guide's, with the notes in the `title` attribute; `sections(off)` adds `[id, title]` for each that is on and has a section (all six; after the Guide's); tabs: `<button ... data-tab="quests" hidden>Quests</button>`, the same for `route`, `journal`, `gear` after the Guide's tab, shown while on (the code at 2211-2213 for the Guide, repeated per id); `render` routes `st.tab === "quests"` to a `questsPage()` that draws the three heads with the fixture's rows (Northshire: Kobold Camp Cleanup, Investigate Echo Ridge; Elwynn: two more), `route` to a `routePage()` with one band line and two legs, `journal` and `gear` to a line "Drawn by the quest engine in game."; `guide()` draws the band as the spec's table when `mods().quests` (`QSTEPS = { Kaka: ["Kill Kobold Vermin 3/8", "Hand in Kobold Camp Cleanup", "Accept Investigate Echo Ridge from Marshal McBride"], Yezin: ["Hand in 2 quests at Innkeeper Farley", "Run to your corpse", "Train at your class trainer"] }`, time to level "about 14 min to level 38" / "about 2 h to level 43"), else the one dim line; under it the head row and the pick's card alone (today's `guide()` filtered as `Guide.lua` filters). Every new class is `cu-` and styled in the page's `<style>` (the build checks).

- [ ] **Step 5: README**

`tools/cute/README.md`: Files gains `Cute_Quest/` (one line: "QuestBank's engine, copied by build.py; its own nine files: Shim, Bridge, Band, six pages"), `test/quest_mocks.lua`; Modules gains two paragraphs: one addon may register several modules (primary and secondary keys, `onToggle`), and Cute_Quest with its six; The Guide's paragraph is rewritten to the spec's band and one card; Test names the new scenarios and the gates; Ship names `build_quest` and the two-folder zip.

- [ ] **Step 6: Every gate**

Run, one at a time:

1. `cd /Users/mikalbot/foreverrank && python3 tools/cute/build.py 2>&1 | tail -4` -> `problems: 0`, `OK`.
2. `cd /Users/mikalbot/foreverrank/tools/cute && luajit harness.lua 2>&1 | tail -3` -> `layout problems: 0`, `OK`.
3. `memory_pressure | tail -1` (normal), then `cd /Users/mikalbot/foreverrank/tools/questbank && luajit harness.lua 2>&1 | tail -3` -> `OK`.
4. `cd /Users/mikalbot/foreverrank && git status --short` -> only the files this plan names; `unzip -l addons/cute/Cute.zip | grep -c "Cute_Quest/"` -> at least 40.

- [ ] **Step 7: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add addons/cute/index.html addons/cute/Cute.zip addons/cute/stats.js tools/cute/Cute/Cute.toc tools/cute/Cute/Core.lua tools/cute/Cute/Changes.lua tools/cute/README.md tools/cute/Cute_Quest
git commit -m "cute 0.7.0: the step now in the Guide and QuestBank's pages as modules; the page shows the band, lists the modules, installs two folders

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Self-review

- Spec coverage: the decision (Tasks 1, 5, 12), the Guide (7, 8), Quests (8), Route (9), Map and Camp (11), Journal and Gear (10), chat routing (5), the registry entries (8-11), the shim (5), the build (5), settings kept/forced/defaults (5's `firstRun`, the pages' rows and toggles), testing (6, 12, 13; QuestBank's harness in 1-3), the page (14), out of scope untouched.
- Placeholders: none; the two "copy from the questbank harness, lines N-M" steps (6, 13) name the source ranges and the three substitutions, and the mock file's index comment is replaced by the ported code in Step 3 of Task 6.
- Names: `QB.dormant`, `QuestBankAPI`, `QB:Login`, `QB.ART`, `QB.Skin` (Tasks 1, 3) are what `Shim.lua`, `Bridge.lua` and `Band.lua` read (5, 8); `UI.PlaceGroups`, `UI:Candidates`, `UI.QuestClick`, `UI.QuestTooltip` (2) are what `PageQuests.lua` calls (8); `def.primary`, `def.key`, `M.AddonWanted`, `M.AddonOn`, `onToggle`, `UI:Host`, `Cute.Open/Refresh/Print/Page/ModuleOn/Safe/Font/Host` (4) are what the pages and the scenarios use (8-13); `Cute.QuestBand` fields `On, Steps, Text, TimeToLevel, Members, Open, Menu, Settings` (8) are what `Guide.lua` reads (7).
