# QuestBank 6.0, the Guide on by default: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A fresh QuestBank install guides from the first login: a step frame with the current step and the next two, QuestBank's arrow on, auto accept and hand-in as the player chose in one welcome, the minimap's ! and ?, progress in mob tooltips, time to level, train and grind steps, party steps; existing 5.x saves are asked once.

**Architecture:** A step engine with no UI (`Guide.lua`) turns 5.4.4's shared target (`Target.lua`), the planned route (`Model.lua`) and the quest log into an ordered step list, fills the plan with the quests Now ranks best, and completes steps from game events. A small frame (`StepFrame.lua`) draws that list and asks the welcome questions. The map work (minimap givers, tooltip progress) sits in `Minimap.lua` and a new `Tips.lua`. Data for trainers and spell levels comes offline through `cmangos.py` and `gen_data.py` into `Data.lua`. Settings are regrouped in `UI.lua`; the page's stage shows the step frame.

**Tech Stack:** WoW Forever client Lua (Lua 5.1 semantics, Midnight secret values), the mock client in `tools/questbank/harness.lua` run with luajit, Python 3 generators (`cmangos.py`, `gen_data.py`, `build_page.py`, `render_layout.py`), the static page `questbank/index.html`.

Spec: `docs/superpowers/specs/2026-10-20-questbank-guide-design.md`. Repository: `/Users/mikalbot/foreverrank`. All paths below are relative to it unless absolute.

## Global Constraints

- Every call into the client goes through `pcall` where it can error, and every value read from the game goes through `QB.Plain` (nil for a secret value); never a string op or comparison on a raw event argument or `UnitGUID` (Core.lua's `onTurnIn`, Discover.lua's `key` are the models).
- Game text is Windows-1252 only: no `▸ ✓ →` or any Unicode symbol; use atlases or `|T...|t` textures. The harness's `checkLayout` fails such text.
- Icons are the game's own atlases and textures (`QB.Art`, `P.Atlas`, `QM.PaintKind`), never invented shapes.
- No secure change in combat: a `SecureActionButtonTemplate` button is created, its attributes set, shown or hidden only when `InCombatLockdown()` is false; otherwise the change is queued for `PLAYER_REGEN_ENABLED` (Camp.lua's `fighting()` and its pending pattern).
- No chat spam: 6.0 adds exactly one chat line (the welcome, once per character, after the welcome choice) and no other `QB:Print` from the Guide, the step frame, the tooltips or the minimap.
- Memory and garbage gates must hold on every run: kept after login under 11 MB (`KEEP_BUDGET = 11 * 1024`), garbage late in a session under 3 MB a minute, a re-plan under 1 MB, a refresh with nothing changed under 100 KB (harness.lua lines 16275-16800). The Guide makes no per-frame allocation: tick functions reuse tables.
- Nothing QuestBank sets in the game's own options is changed by the Guide; the interact light and the status text stay with their modules.
- Settings names on screen as the spec writes them: "Guide", "Map and minimap", "Data you share", "Banking".
- The 5.4.4 contracts stay: `T.Get(me)` keeps its target unless a real event; a click shows a place for now only (`A:Show`); a hand-in in reach first whatever its value.
- The Forever rules of this repo: free software GPL-3.0; CMaNGOS data is GPL-3.0 (say so where it is used); nothing uploaded by the addon itself.
- The welcome's auto choice words are Auto.lua's: `Auto.WORDS = { off = "Off", route = "Quests on my route", worth = "Quests worth taking" }`, `Auto.OTHER = { accept = "Accept them", leave = "Leave the window to me" }`.
- Version 6.0.0: `QB.version` in `tools/questbank/QuestBank/Core.lua:5` and `## Version` in `tools/questbank/QuestBank/QuestBank.toc`, bumped in the last task only (the harness compares versions in the sync scenario).

## Machine safety (every gate run)

Another job runs tests on this Mac. Before every `luajit harness.lua`:

```bash
pgrep -fl luajit && echo "WAIT: another luajit is running; try again in a minute" || echo "free"
memory_pressure | tail -1     # "System-wide memory free percentage: NN%": run only when NN >= 20
```

Run one luajit at a time, in the foreground, never two harness runs side by side. The full harness takes a few minutes; do not add a `--only` switch (the gates at the end must run every time).

## The gate (the same four commands, every task)

```bash
cd /Users/mikalbot/foreverrank/tools/questbank && luajit harness.lua
```
Expected tail, every time:
```
memory: kept after login and every page NNNN KB (budget 11264 KB); ...
a re-plan of both routes: NNN KB of garbage
a refresh, the window shut: NN KB of garbage
layout problems: 0
OK
```
`OK, with layout problems above` is a failure for this plan. The new cases print `6.0 guide: <case>: ok` each.

Package and page (the last task, and whenever a task changes `Data.lua` or the page):
```bash
cd /Users/mikalbot/foreverrank && (cd tools/questbank && rm -f ../../questbank/QuestBank.zip && zip -rq ../../questbank/QuestBank.zip QuestBank -x "*.DS_Store")
cd /Users/mikalbot/foreverrank && python3 tools/build_uploader.py
cd /Users/mikalbot/foreverrank && python3 -I tools/questbank/build_page.py
```

## Decisions the spec left open (settled here, not TBD)

| Question | Decision |
|---|---|
| Where the Guide's auto picks live | `QB:Plan().auto[id] = true`, a table beside `add` (the player's own list). `QB:InPlan` and `Auto.OnRoute` count `auto` while the Guide is on. The player's `add` always wins; a quest in `add` is never put in `auto`. |
| How many quests the Guide fills | `free = QB.LOG_SLOTS - logCount - 2`; at most `G.AUTO_MAX = 8` auto picks at once, never more than `free`. |
| "never a quest more than two levels above" | `q.lvl <= level + 2` (quest level, not required level). |
| "never grey unless its chain leads somewhere better" | grey = `QM.Grey(q, level)`; allowed when `QB:ChainLead(id) >= QB.Model.CHEAP * QB.Scale(level)`. |
| The ranking | `UI:Candidates(nil, level)`'s `c.rank` (XP plus half the chain, over trip and loop minutes, behind-you quarter), times the drop-rate weight Now uses: `drop < 25 and (0.5 + drop / 50) or 1`, times 1.5 when a party member holds or can take it (Sync). |
| Objective step clustering | spots of one stop's quests within 150 yards of each other form one step; text names the nearest quest's objective and "and N more" where several. |
| Skips | "Not now": `QuestBankDB.chars[key].guide.later[id] = time()`, honoured for 3600 s. "Drop": `QB:SetSkipped(id, true)` (for good, as 5.4.4's Skip). |
| Step completion | accept: `QB.state.log[id]` exists; objective: every objective of the step's spots is `done` or the quest is `complete`; hand-in: `QB.API.IsDone(id)`; travel: the arrow's step gone (`TV.Guide` state "walk") or landing; train: `TRAINER_SHOW` read with 0 available; level: `QB.state.level >= n`; corpse: `UnitIsDeadOrGhost("player")` false. |
| Trainer step | the player's level is in `D.SPELL_LV[classToken]` (a level the class learns a new spell or rank at, from `codex/spellbook.json`), the level's spells not yet trained (`QuestBankDB.chars[key].guide.trained < level`), and a trainer of the class (seed `D.TRAINER` or learned `QuestBankDB.disc.trainer`) within 3 minutes' walk (`M.Between`) of the route's next stop that has a town (`stop.town`). Then "Train at <name>" is inserted before that stop's hand-in step. No trainer known within reach: a grey line under the current step, "New spells at your class trainer", for 180 s, no chat. |
| Trainer learned in play | on `TRAINER_SHOW` with `IsTradeskillTrainer()` false: `QuestBankDB.disc.trainer[Disc.Key(UnitGUID("npc"))] = { n = UnitName("npc"), cl = classID, m, x, y }` (the player's own class; a class trainer's window opens only for its class). |
| Grind step | shown when the step list would otherwise be empty and no candidate ranks above `CHEAP * Scale(level)` within 20 minutes. `N` = the lowest `req` among `UI:Candidates(nil, level, level + 3)` entries with `req > level`; `Y` = that quest's `D.CAT[cat].name`; `X` = the nearest kill spot (`kind == "k"`) in `D.SPOT` of any quest for the player with `lvl` in `[level - 2, level + 1]`, named by `D.SN[sp.name]` or its zone. Text: `Kill around X until level N, then Y`. None found: `Kill around here until level N`. |
| Death | `C_DeathInfo.GetCorpseMapPosition(QB.API.MapID())` (DeathInfoDocumentation.lua:11, returns a Vector2D or nil) read once a second while `UnitIsDeadOrGhost("player")`; the arrow's route mode shows kind "corpse", "Run to your corpse"; back to the route on `PLAYER_UNGHOST` / `PLAYER_ALIVE` or the next look alive. |
| Party steps | a new Sync message `1G|<text>` (at most 120 bytes, Windows-1252), queued when the player's first step text changes, at most one every 10 s; received into `m.step`. The step frame lists `m.step` for each member under the player's step while `IsInGroup()`. |
| Time to level | minutes = the plan's minutes to the XP needed (`route.t` scaled by needed/route.xp) until `Timer.XPPerHour()` exists (ten minutes of play), then needed XP over that rate; text "about 14 min to level 6", "under a minute to level 6", "about 2 h 10 min to level 23". |
| Reward choice | `Auto.Complete` with `GetNumQuestChoices() > 1` sets `QB.Guide.reward = { qid, index }` where index is the choice whose item id is `UI.BestReward(qid, "gear", level)` (else the first trinket, else nil); the step frame says "Choose a reward: <name> is QuestBank's pick" and `StepFrame.MarkReward()` shows QuestBank's own gold glow frame (`P.Glow`) anchored over `QuestInfoFrame.rewardsFrame.RewardButtons[index]` (Mainline QuestInfo.lua:801), out of combat, never touching the button. Nothing is chosen. |
| Minimap ! | kind "give": `QM.GiversNear(mapID, level)` (ForMe, level in reach, not grey, prerequisites done, not in `D.QLOCK`, not done, not excluded), merged within 30 yards into one pin with a count, nearest-first cap `G.GIVER_MAX = 40`; the game's ! atlas as `QM.ART.give`. Setting `minimapGivers` (default true). |
| Minimap ? | the existing "turn" pins (Mini.List already adds one per NPC taking a complete quest); no change but the Settings row. |
| Tooltip progress | `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, fn)` and `(Enum.TooltipDataType.Object, fn)` (TooltipInfoSharedDocumentation.lua: Unit = 2, Object = 4). Name = `QB.Plain(data.lines[1].leftText)`; a log quest's objective line that starts with that name gives "Name: have/need (Quest)"; party members' `m.quests[id].prog` adds "Brann 2/8". Nothing when the name or the guid is secret. Setting `tipProgress` (default true). |
| Welcome for a fresh install | `QuestBankDB.settings` had no keys at `ADDON_LOADED`: `s.guide.on = true`, `s.arrow = true`, `s.welcome = "fresh"`. The step frame shows the welcome card (auto choice, hand-in, outside the route) with a Done button; Done prints the one chat line and clears `s.welcome`. |
| Existing saves | `s.v600 == nil` and not fresh: `s.welcome = "ask"`, `s.guide.on = false`. The step frame shows "Let QuestBank guide you?" Yes / Not now. Yes: `guide.on = true`, `arrow = true`, the welcome card next. Not now: the frame hides, `guide.on` stays false, nothing else changes. |
| Welcome line | `QuestBank is guiding you. /qb opens the full window; right-click the step frame for its options.` |
| Step frame style | the window's slate (`UI.lua`'s SLATE backdrop, INK and GOLD inks); width 260 at scale 1; scales 0.8, 1.0, 1.2 from the menu; `s.guide.x, y` kept; `s.guide.locked` stops drags. Right-click menu: Not now, Drop <quest>, Lock / Unlock, Scale: 80% / 100% / 120%, Hide (Settings brings it back), Settings. |
| Click on a step | opens the window on the Quest Log (tab 1) and scrolls its row into view (`UI:Open(1)`, `UI.scrollToQuest = id`); a travel step opens the Route page (tab 3). |
| Quest-item button | from `GetQuestLogSpecialItemInfo(logIndex)` (Blizzard_ObjectiveTrackerShared.lua:53 gives `link, item, charges, showItemWhenComplete`); a `SecureActionButtonTemplate` with `type = "item"`, `item = "item:<id>"` as Camp.lua's icons, set only out of combat. |
| Where Guide events come from | Core.lua's event frame forwards to `QB.Guide.OnEvent(event, a1, a2)` as it does for `QB.Auto`; Guide.lua creates no frames. |
| Harness block | one new block `G6CASES` in `harness.lua`, placed right before the comment line `-- 5.4.2: memory, and the lag that grew through a session` (line 16275 today), modelled on `B3CASES` (line 14115): helpers, cases in order, `for _, case in ipairs(G6CASES) do case[2](); print("6.0 guide: " .. case[1] .. ": ok") end`. |

## File structure

| File | Responsibility |
|---|---|
| `tools/questbank/QuestBank/Guide.lua` (new) | the step engine, no UI: steps from the target and the route, the auto fill, completion, skips, train, grind, corpse, time to level, party steps, the reward pick |
| `tools/questbank/QuestBank/StepFrame.lua` (new) | the frame: steps, the item button, the time line, the welcome and the 5.x question, the menu, scale and lock, the reward mark |
| `tools/questbank/QuestBank/Tips.lua` (new) | mob and object tooltip progress |
| `tools/questbank/QuestBank/Core.lua` | defaults, `QB.Migrate600`, `QB:Plan().auto`, `QB:InPlan`, event forwarding, init order, `/qb guide` |
| `tools/questbank/QuestBank/Auto.lua` | `Auto.OnRoute` counts auto picks; the reward choice stop hands to the Guide |
| `tools/questbank/QuestBank/Arrow.lua` | the corpse target in route mode |
| `tools/questbank/QuestBank/Minimap.lua` | the ! pins |
| `tools/questbank/QuestBank/QuestMap.lua` | `QM.GiversNear` |
| `tools/questbank/QuestBank/Sync.lua` | the `1G` step message |
| `tools/questbank/QuestBank/UI.lua` | Settings regrouped, the Guide section, scroll-to-quest |
| `tools/questbank/QuestBank/QuestBank.toc` | load order: `Guide.lua` after `Auto.lua`, `StepFrame.lua` and `Tips.lua` after `UI.lua` |
| `tools/questbank/cmangos.py`, `tools/questbank/gen_data.py` | class trainers into `D.TRAINER`, spell levels into `D.SPELL_LV` |
| `tools/questbank/harness.lua` | mocks for the new client calls, the `G6CASES` block, Guide garbage checks |
| `questbank/index.html`, `tools/questbank/build_page.py` | the stage's step-frame mock, the 6.0 line, the checks |
| `tools/questbank/README.md` | the Guide paragraph, the 6.0 line |

## Harness conventions used by every case below

- A client: `newClient({ name, level, cap = 60, faction = "Alliance", className = "Mage", class = "MAGE", classID = 8, race = "Human", log = { { id, complete 0|1 }, ... }, done = { [id] = true }, world = { continent, wx, wy }, map = uiMapID, bagSlots = {}, bind = "Goldshire" })`, then `login(c)`. `c.env` is its globals, `c.QB` the addon, `c.chat` the chat lines, `c.auto` the quest-window calls, `c.objectives[id]` the game's objective lines, `c.ghost` dead, `c.combat` in a fight, `c.ev(frame, event, ...)` fires an event on Core's frame.
- One frame of play and a settle, copied from `B3CASES` (harness.lua lines 14126-14140):

```lua
local function frame(c, dt)
  c.clock = c.clock + dt
  table.sort(c.timers, function(a, b) return a.t < b.t end)
  while c.timers[1] and c.timers[1].t <= c.clock do table.remove(c.timers, 1).f() end
  for _, f in ipairs(c.frames) do
    local u = f.__scripts.OnUpdate
    if u and f:IsVisible() then u(f, dt) end
  end
end
local function settle(c)
  c.ev(c.QB.eventFrame, "QUEST_LOG_UPDATE")
  for _ = 1, 5 do frame(c, 0.1) end
  c.QB.Model.Finish()
  c.QB:Recompute(true)
  c.QB.Model.Finish()
  for _ = 1, 3 do frame(c, 0.1) end
  if c.QB.Guide then c.QB.Guide.Replan() end
end
```

- Northshire: Kobold Camp Cleanup is quest 7 (giver and taker Marshal McBride, NPC index found by name in `D.NPC`), its objective line `Kobold Vermin slain: 3/8`; the harness already uses it (lines 12526, 12586). A level-1 human stands at `world = { 0, -8914, -133 }, map = 1429` (Elwynn's Northshire, harness.lua:2265).
- Hillsbrad and Alterac: copy `hillsClient` and `walkTo` from `RCASES` (harness.lua lines 13311-13375).
- Zephras Isle: copy `isleClient` from `RCASES` (harness.lua lines 13887-13915).
- A party of two: the two clients get `group = true`; `deliver()` (harness.lua:1174) moves addon messages between them.

---

### Task 1: Settings, migration and the `auto` plan table (Core.lua)

**Files:**
- Modify: `tools/questbank/QuestBank/Core.lua:1250-1365` (DEFAULTS, `QB:Settings`, migrations), `:1457-1476` (`QB:Plan`), `:2121-2127` (`QB:InPlan`)
- Modify: `tools/questbank/QuestBank/Auto.lua:35-55` (`Auto.OnRoute`)
- Test: `tools/questbank/harness.lua` (new block `G6CASES`, first case)

**Interfaces:**
- Produces: `QB:Settings().guide = { on, frame, locked, scale, x, y }`, `QB:Settings().minimapGivers`, `QB:Settings().tipProgress`, `QB:Settings().welcome` ("fresh" | "ask" | nil), `QB:Settings().v600`; `QB.Migrate600(s, fresh)`; `QB:Plan().auto` (a table `[id] = true`); `QB:IsAuto(id)`; `QB:GuideOn()` (`guide.on` and `QB:Mode() == "quest"`).

- [ ] **Step 1: Write the failing case (the block's skeleton and the settings case)**

Insert before the line `-- 5.4.2: memory, and the lag that grew through a session` in `tools/questbank/harness.lua`:

```lua
----------------------------------------------------------------------------
-- 6.0: the Guide, on by default (docs/superpowers/specs/2026-10-20-questbank-guide-design.md). Each case below is in
-- G6CASES, in order, after the harness's helpers
----------------------------------------------------------------------------
;(function()
  local G6CASES = {}
  local function frame(c, dt)
    c.clock = c.clock + dt
    table.sort(c.timers, function(a, b) return a.t < b.t end)
    while c.timers[1] and c.timers[1].t <= c.clock do table.remove(c.timers, 1).f() end
    for _, f in ipairs(c.frames) do
      local u = f.__scripts.OnUpdate
      if u and f:IsVisible() then u(f, dt) end
    end
  end
  local function settle(c)
    c.ev(c.QB.eventFrame, "QUEST_LOG_UPDATE")
    for _ = 1, 5 do frame(c, 0.1) end
    c.QB.Model.Finish()
    c.QB:Recompute(true)
    c.QB.Model.Finish()
    for _ = 1, 3 do frame(c, 0.1) end
    if c.QB.Guide then c.QB.Guide.Replan() end
  end
  -- a level-1 human in Northshire, questing; saved: a QuestBankDB to start from (nil: a fresh install)
  local function human(name, log, done, saved, level)
    local c = newClient({ name = name, level = level or 1, cap = 60, faction = "Alliance", className = "Warrior", class = "WARRIOR", classID = 1,
      race = "Human", log = log or {}, done = done or {}, world = { 0, -8914, -133 }, map = 1429, bagSlots = {}, bind = "Goldshire" })
    if saved then c.env.QuestBankDB = saved end
    login(c)
    return c
  end
  local function npcIndex(c, name, map)
    for i, n in ipairs(c.QB.Data.NPC) do if n[1] == name and (not map or n[2] == map) then return i, n end end
  end

  G6CASES[#G6CASES + 1] = { "settings: a fresh install guides, a 5.x save is asked, auto picks are a table of their own", function()
    local fresh = human("Newcomer")
    local s = fresh.QB:Settings()
    assert(s.guide and s.guide.on == true and s.guide.frame == true and s.guide.scale == 1 and s.arrow == true and s.welcome == "fresh" and s.v600 == true,
      "a fresh install: the Guide on, the frame on, the arrow on, the welcome to ask")
    assert(s.minimapGivers == true and s.tipProgress == true, "the ! on the minimap and the tooltip progress on")
    assert(s.autoAccept == "off" and s.autoTurnIn == false, "auto still off until the welcome asks")
    local old = human("Veteran", nil, nil, { settings = { v544 = true, autoAccept = "route", arrow = false, tab = 6 } })
    local o = old.QB:Settings()
    assert(o.guide.on == false and o.welcome == "ask" and o.arrow == false and o.autoAccept == "route" and o.v600 == true,
      "a 5.x save: nothing changed, one question pending: " .. tostring(o.welcome))
    local p = old.QB:Plan()
    assert(type(p.auto) == "table", "the plan has an auto table")
    p.auto[7] = true
    assert(old.QB:IsAuto(7) and not old.QB:IsAdded(7), "an auto pick is not the player's own pick")
    o.guide.on = true
    old.QB:ReadState()
    assert(old.QB:InPlan(old.QB.Quest.Get(7)) == true, "with the Guide on an auto pick is in the plan")
    assert(old.QB.Auto.OnRoute(7) == true, "and on the route for Accept for me")
    o.guide.on = false
    assert(old.QB:InPlan(old.QB.Quest.Get(7)) == false, "with the Guide off it is not")
    assert(#fresh.chat == 0 or not fresh.chat[#fresh.chat]:find("guiding you", 1, true), "no welcome line before the choice")
  end }

  for _, case in ipairs(G6CASES) do
    case[2]()
    print("6.0 guide: " .. case[1] .. ": ok")
  end
end)()

```

- [ ] **Step 2: Run the harness to see it fail**

Run: `cd /Users/mikalbot/foreverrank/tools/questbank && luajit harness.lua 2>&1 | tail -5`
Expected: an assertion from the new case, "a fresh install: the Guide on..." (`s.guide` is nil).

- [ ] **Step 3: Defaults and the migration**

In `Core.lua`'s `DEFAULTS` (after `finderAhead = false,`):

```lua
  -- the Guide (6.0, Guide.lua and StepFrame.lua): on, the step frame shown, unlocked, at scale 1 where it was dragged.
  -- welcome: "fresh" asks the auto choice in the step frame once; "ask" asks a 5.x save whether to guide (QB.Migrate600)
  guide = { on = true, frame = true, locked = false, scale = 1 },
  minimapGivers = true, -- a ! on the minimap for every quest you can take now (Minimap.lua)
  tipProgress = true,   -- "Kobold Vermin: 3/8 (Kobold Camp Cleanup)" in mob and object tooltips (Tips.lua)
```

In `QB:Settings()`, before the defaults are filled (right after `local s = db.settings`), note a fresh install:

```lua
  local fresh = next(s) == nil
```

and after `if s.v544 == nil then QB.Migrate544(s) end`:

```lua
  if s.v600 == nil then QB.Migrate600(s, fresh) end
```

Then after `QB.Migrate544`:

```lua
-- 6.0: the Guide. A fresh install guides from the first login: the step frame, QuestBank's arrow, and the welcome
-- card that asks the auto choice (s.welcome "fresh"). A save from 5.x is asked once in the step frame instead
-- ("ask"); until it says yes the Guide is off and nothing else of its settings moves
function QB.Migrate600(s, fresh)
  s.v600 = true
  if fresh then
    s.guide.on, s.guide.frame, s.arrow, s.welcome = true, true, true, "fresh"
  else
    s.guide.on, s.welcome = false, "ask"
  end
end
```

In `QB:Plan()`, after `p.skip = p.skip or {}`:

```lua
  p.auto = p.auto or {} -- the Guide's own picks (Guide.lua, G.Fill): [id] = true; never one of p.add
```

Add after `QB:IsAdded`:

```lua
function QB:IsAuto(id) return id ~= nil and self:Plan().auto[id] == true end
-- the Guide runs while questing (banking keeps 5.x's planner as it is)
function QB:GuideOn() return self:Settings().guide.on == true and self:Mode() == "quest" end
```

In `QB:InPlan`, the last line becomes:

```lua
  return self:IsAdded(q.id) or (self:IsAuto(q.id) and self:GuideOn())
```

In `Auto.OnRoute`, after `if plan.add[id] then return true end`:

```lua
  if plan.auto[id] and QB:GuideOn() then return true end
```

- [ ] **Step 4: Run the harness; the case passes and every older case still does**

Run: `cd /Users/mikalbot/foreverrank/tools/questbank && luajit harness.lua 2>&1 | tail -6`
Expected: `6.0 guide: settings: ...: ok`, then the memory lines, `layout problems: 0`, `OK`.

- [ ] **Step 5: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/QuestBank/Core.lua tools/questbank/QuestBank/Auto.lua tools/questbank/harness.lua && git commit -q -m "feat(questbank): 6.0 settings: the Guide's defaults, the 5.x question, auto picks of their own" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 2: Guide.lua: steps from the target and the route

**Files:**
- Create: `tools/questbank/QuestBank/Guide.lua`
- Modify: `tools/questbank/QuestBank/QuestBank.toc` (add `Guide.lua` after `Auto.lua`)
- Modify: `tools/questbank/QuestBank/Core.lua` (`QB:Changed` calls `QB.Guide.Replan`; the event frame forwards to `QB.Guide.OnEvent`)
- Test: `harness.lua` `G6CASES` (second case)

**Interfaces:**
- Produces: `QB.Guide` (`G`): `G.steps` (list), `G.ver` (goes up on change), `G.Replan()`, `G.Current()`, `G.Steps()`, `G.Text(step)`, `G.OnEvent(event, a1, a2)`. A step: `{ kind = "accept"|"objective"|"handin"|"travel"|"train"|"grind"|"corpse"|"reward", text, qid, ids (set), npc, c, wx, wy, m, x, y, n (how many more), item (item id or nil) }`.
- Consumes: `QB.Target.Get(me)`, `QB.Target.Route()`, `QB.QuestMap.OpenSpots(e)`, `QB.Model.World(m, x, y, into)`, `QB.Arrow.ListFor("pickup")`, `QB.API.WorldPosition()`.

- [ ] **Step 1: Write the failing case**

Append to `G6CASES` (before the runner loop):

```lua
  -- a level-1 human in Northshire holding Kobold Camp Cleanup (3/8) with A Threat Within (783) handed in: the first
  -- step is the kobolds (the target's objective spot), then the hand-in at Marshal McBride, then the pick-up the plan
  -- holds; each completes by itself as the game reports it
  G6CASES[#G6CASES + 1] = { "steps from the target: kill, hand in, pick up; each completes by itself", function()
    local c = human("Rone", { { 7, 0 } }, { [783] = true })
    local QB, G = c.QB, c.QB.Guide
    c.objectives = { [7] = { { text = "Kobold Vermin slain: 3/8", type = "monster", finished = false, numFulfilled = 3, numRequired = 8 } } }
    QB:Settings().guide.on = true
    QB:SetAdded(15, true) -- Investigate Echo Ridge, from Marshal McBride too
    settle(c)
    local s1, s2, s3 = G.steps[1], G.steps[2], G.steps[3]
    assert(s1 and s1.kind == "objective" and s1.qid == 7 and G.Text(s1) == "Kill Kobold Vermin 3/8", "the first step: " .. tostring(s1 and G.Text(s1)))
    assert(s2 and s2.kind == "handin" and s2.qid == 7 and G.Text(s2) == "Hand in Kobold Camp Cleanup", "then the hand-in: " .. tostring(s2 and G.Text(s2)))
    assert(s3 and s3.kind == "accept" and s3.qid == 15 and G.Text(s3):find("^Accept Investigate Echo Ridge from "), "then the pick-up: " .. tostring(s3 and G.Text(s3)))
    assert(s1.c == 0 and s1.wx and s1.m == 1429, "a step has a place: continent yards and its map")
    local v = G.ver
    -- the count grows: the step stays the first, its text follows
    c.objectives[7][1].numFulfilled = 5; c.objectives[7][1].text = "Kobold Vermin slain: 5/8"
    settle(c)
    assert(G.steps[1].kind == "objective" and G.Text(G.steps[1]) == "Kill Kobold Vermin 5/8", "the count follows: " .. G.Text(G.steps[1]))
    -- done: the game says the quest is complete, and the hand-in is the first step
    c.objectives[7][1].finished, c.objectives[7][1].numFulfilled = true, 8
    c.log[1][2] = 1
    settle(c)
    assert(G.steps[1].kind == "handin" and G.steps[1].qid == 7, "complete: the hand-in first: " .. G.Text(G.steps[1]))
    assert(G.ver > v, "the version went up")
    -- handed in: gone; the pick-up leads
    c.log = {}; c.done[7] = true
    c.ev(QB.eventFrame, "QUEST_TURNED_IN", 7, 85)
    settle(c)
    assert(G.steps[1].kind == "accept" and G.steps[1].qid == 15, "handed in: the pick-up first: " .. G.Text(G.steps[1]))
    -- accepted: gone, its objective next
    c.log = { { 15, 0 } }
    c.objectives = { [15] = { { text = "Investigate Echo Ridge: 0/1", type = "event", finished = false, numFulfilled = 0, numRequired = 1 } } }
    c.ev(QB.eventFrame, "QUEST_ACCEPTED", 1, 15)
    settle(c)
    assert(G.steps[1].qid == 15 and G.steps[1].kind == "objective", "accepted: its objective: " .. G.Text(G.steps[1]))
    assert(#c.chat == 0 or not c.chat[#c.chat]:find("step", 1, true), "nothing said in chat")
  end }
```

- [ ] **Step 2: Run the harness to see it fail**

Run: `cd /Users/mikalbot/foreverrank/tools/questbank && luajit harness.lua 2>&1 | tail -4`
Expected: `attempt to index field 'Guide' (a nil value)`.

- [ ] **Step 3: Write Guide.lua**

```lua
-- SPDX-License-Identifier: GPL-3.0-or-later
-- The Guide (6.0): what to do next, as a list of steps, from the one target (Target.lua), the planned route
-- (Model.lua) and your quest log. No frames here: StepFrame.lua draws the list, and Cute's leveling module may read it.
--   steps     accept A from X; kill/collect/use for A (the objective spots of the route's quests, clustered within
--             CLUSTER yards, the nearest first); hand in A at X; travel steps the arrow's way gives (Travel.lua);
--             Train at X; Kill around X until level N; Run to your corpse; Choose a reward
--   first     the target of 5.4.4: the route's first stop, its kept objective spot or a hand-in in reach, so the arrow,
--             the minimap, the Map page and the step frame agree, and the first step changes only on a real event
--   done      a step completes when the game says so: the quest accepted, every objective of its spots done or the
--             quest complete, the quest handed in, the flight landed, the level reached
--   skipped   "Not now" for an hour (QuestBankDB.chars[key].guide.later), "Drop" for good (QB:SetSkipped)
-- Replan runs after each re-plan (Core.lua, QB:Changed) and on the Guide's own events; it reuses its tables, so a
-- re-plan makes a few kilobytes and a tick none.
local _, QB = ...
local G = { steps = {}, ver = 0, later = nil }
QB.Guide = G

local CLUSTER = 150        -- yards: objective spots this close are one step
local LATER = 3600         -- seconds "Not now" holds
local AUTO_MAX = 8         -- auto picks at once (Task 3)
G.CLUSTER, G.LATER, G.AUTO_MAX = CLUSTER, LATER, AUTO_MAX

local plain = QB.Plain
local sqrt, huge = math.sqrt, math.huge
local pool, used = {}, 0   -- step tables reused from one Replan to the next
local wbuf = {}

local function step(kind)
  used = used + 1
  local s = pool[used]
  if not s then s = {}; pool[used] = s end
  for k in pairs(s) do s[k] = nil end
  s.kind = kind
  return s
end

local function npcName(idx)
  local n = idx and QB.Data.NPC[idx]
  return n and n[1] or "?"
end
local function questName(id)
  local q = QB.Quest.Get(id)
  return q and q.name or plain(QB.state.log[id] and QB.state.log[id].title) or ("Quest " .. tostring(id))
end

-- "Kobold Vermin slain: 3/8" -> "Kobold Vermin", 3, 8; "Investigate Echo Ridge: 0/1" -> "Investigate Echo Ridge", 0, 1
local function parseLine(text)
  text = plain(text)
  if type(text) ~= "string" then return nil end
  local name, have, need = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)")
  if not name then return text, nil, nil end
  name = name:gsub(" slain$", ""):gsub(" killed$", "")
  return name, tonumber(have), tonumber(need)
end
G.ParseLine = parseLine

-- the verb for a spot kind (Data.lua's D.SPOT kinds)
local VERB = { k = "Kill", c = "Collect", u = "Use", b = "Buy", e = "Go to", f = "Gather", s = "Find" }

-- the words of a step, made when asked (the frame asks each refresh; no string is kept on the step)
function G.Text(s)
  if not s then return "" end
  local k = s.kind
  if k == "accept" then return "Accept " .. questName(s.qid) .. " from " .. npcName(s.npc)
  elseif k == "handin" then
    if s.near then return "Hand in " .. questName(s.qid) .. " here" end
    return s.n and s.n > 1 and string.format("Hand in %d quests at %s", s.n, npcName(s.npc)) or ("Hand in " .. questName(s.qid))
  elseif k == "objective" then
    local e = QB.state.log[s.qid]
    local o = e and e.objectives and e.objectives[s.slot or 1]
    local name, have, need = parseLine(o and o.text)
    local verb = VERB[s.obj] or "Do"
    local what = name or questName(s.qid)
    local t = (have and need) and string.format("%s %s %d/%d", verb, what, have, need) or (verb .. " " .. what)
    if s.n and s.n > 1 then t = t .. string.format(", and %d more here", s.n - 1) end
    return t
  elseif k == "travel" then return s.text or "Travel"
  elseif k == "train" then return "Train at " .. (s.name or "your class trainer")
  elseif k == "grind" then return s.text or "Kill around here"
  elseif k == "corpse" then return "Run to your corpse"
  elseif k == "reward" then return "Choose a reward: " .. (s.name or "QuestBank's pick") .. " is QuestBank's pick"
  end
  return s.text or ""
end

-- the place of a stop's NPC, in continent yards and on its map
local function placeNpc(s, idx)
  local n = idx and QB.Data.NPC[idx]
  if not n then return end
  s.npc, s.m, s.x, s.y = idx, n[2], n[3], n[4]
  s.c, s.wx, s.wy = n[5], n[6], n[7]
end

-- the objective steps of one quest: its open spots (QuestMap.OpenSpots: finished objectives left out) clustered within
-- CLUSTER yards, nearest to `me` first; the kept spot (Target.lua's cur) leads when it is this quest's
local spotsOf = {}
local function objectiveSteps(e, me, lead)
  local QM, M = QB.QuestMap, QB.Model
  if not (QM and QM.OpenSpots) or e.complete then return end
  for k = #spotsOf, 1, -1 do spotsOf[k] = nil end
  for _, sp in ipairs(QM.OpenSpots(e)) do
    local w = M.World(sp.m, sp.x * 100, sp.y * 100, wbuf)
    if w then spotsOf[#spotsOf + 1] = { sp = sp, c = w.c, wx = w.wx, wy = w.wy, d = (me and me.c == w.c) and ((w.wx - me.wx) ^ 2 + (w.wy - me.wy) ^ 2) or huge } end
  end
  table.sort(spotsOf, function(a, b)
    if lead and (a.sp == lead) ~= (b.sp == lead) then return a.sp == lead end
    return a.d < b.d
  end)
  local taken = {}
  for i, a in ipairs(spotsOf) do
    if not taken[i] then
      local s = step("objective")
      s.qid, s.obj, s.slot = e.id, a.sp.kind, a.sp.slot > 0 and a.sp.slot or nil
      s.c, s.wx, s.wy, s.m, s.x, s.y = a.c, a.wx, a.wy, a.sp.m, a.sp.x * 100, a.sp.y * 100
      s.n = 1
      for j = i + 1, #spotsOf do
        local b = spotsOf[j]
        if not taken[j] and b.c == a.c and (b.wx - a.wx) ^ 2 + (b.wy - a.wy) ^ 2 <= CLUSTER * CLUSTER then taken[j] = true; s.n = s.n + 1 end
      end
      G.steps[#G.steps + 1] = s
    end
  end
end

-- "Not now": the quests put off, by character, for LATER seconds
local function laterDB()
  QuestBankDB = QuestBankDB or {}
  QuestBankDB.chars = QuestBankDB.chars or {}
  local key = QB:CharKey()
  local c = QuestBankDB.chars[key]
  if type(c) ~= "table" then c = {}; QuestBankDB.chars[key] = c end
  if type(c.guide) ~= "table" then c.guide = {} end
  if type(c.guide.later) ~= "table" then c.guide.later = {} end
  return c.guide
end
G.DB = laterDB
local function putOff(id)
  local at = laterDB().later[id]
  if not at then return false end
  if (time and time() or 0) - at < LATER then return true end
  laterDB().later[id] = nil
  return false
end
G.PutOff = putOff

-- the steps, anew: the target first (its quest's objective spot, or its stop's hand-ins), then the rest of the route
-- stop by stop (each stop: the pick-ups there, the objectives of its quests on the way, its hand-ins). Pick-ups come
-- from the arrow's pick-up list (Arrow.ListFor("pickup"): the plan's first open step of each quest you don't hold)
function G.Replan()
  if not (QB:Settings().guide and QB:Settings().guide.on) then
    if #G.steps > 0 then for k = #G.steps, 1, -1 do G.steps[k] = nil end; G.ver = G.ver + 1 end
    return
  end
  local was1 = G.steps[1]
  local wasKey = was1 and (was1.kind .. ":" .. tostring(was1.qid) .. ":" .. tostring(was1.npc) .. ":" .. tostring(was1.wx))
  for k = #G.steps, 1, -1 do G.steps[k] = nil end
  used = 0
  local T, A = QB.Target, QB.Arrow
  local me = QB.API.WorldPosition(nil, wbuf)
  me = me and { c = me.c, wx = me.wx, wy = me.wy } or nil
  local log = QB.state.log or {}
  local cur = T and T.Get(me)
  local r = T and T.Route()
  local legs = r and r.legs or {}
  -- a hand-in in reach: first, whatever its value (Target.lua)
  if cur and cur.name and cur.near then
    local s = step("handin")
    s.qid, s.n, s.near = cur.qid, cur.quests, true
    placeNpc(s, cur.near)
    G.steps[1] = s
  end
  local doneQ = {}
  local pickups = A and A.ListFor and A.ListFor("pickup") or {}
  local function pickupsAt(stop)
    for _, d in ipairs(pickups) do
      if d.qid and not doneQ[d.qid] and not putOff(d.qid) and d.npc and stop.seen and stop.seen[d.npc] then
        local s = step("accept")
        s.qid = d.qid
        placeNpc(s, d.npc)
        G.steps[#G.steps + 1] = s
        doneQ[d.qid] = true
      end
    end
  end
  for li, leg in ipairs(legs) do
    local stop = leg.stop
    if stop then
      pickupsAt(stop)
      -- the objectives of this stop's quests still open (the first stop: the kept spot leads)
      for _, row in ipairs(leg.rows or {}) do
        local e = log[row.q.id]
        if e and not e.complete and not putOff(e.id) then
          objectiveSteps(e, me, nil) -- (the target's quest is moved first below; lead stays for a later kept-spot order)
        end
      end
      -- its hand-ins, one step per NPC
      local byNpc = {}
      for _, row in ipairs(leg.rows or {}) do
        local e = log[row.q.id]
        if e and e.complete and not doneQ[e.id] and not putOff(e.id) then
          local idx = row.q.turnIdx
          local s = byNpc[idx]
          if not s then
            s = step("handin")
            s.qid, s.n = e.id, 0
            placeNpc(s, idx)
            byNpc[idx] = s
            G.steps[#G.steps + 1] = s
          end
          s.n = s.n + 1
          if e.id < s.qid then s.qid = e.id end
          doneQ[e.id] = true
        end
      end
    end
  end
  -- pick-ups at no stop of the route (a giver away from every hand-in): after the route, nearest first
  for _, d in ipairs(pickups) do
    if d.qid and not doneQ[d.qid] and not putOff(d.qid) then
      local s = step("accept")
      s.qid = d.qid
      placeNpc(s, d.npc)
      G.steps[#G.steps + 1] = s
      doneQ[d.qid] = true
    end
  end
  -- the first step is the target's: when the target leads to an objective spot of a quest, that quest's nearest
  -- objective step goes first (Target.lua keeps the quest and the spot; the list follows it, never the other way)
  if cur and cur.name and cur.obj and cur.qid and not (G.steps[1] and G.steps[1].near) then
    for i, s in ipairs(G.steps) do
      if s.kind == "objective" and s.qid == cur.qid then
        if i > 1 then table.remove(G.steps, i); table.insert(G.steps, 1, s) end
        s.c, s.wx, s.wy, s.m, s.x, s.y = cur.c, cur.wx, cur.wy, cur.m, cur.x, cur.y
        break
      end
    end
  end
  local now1 = G.steps[1]
  local nowKey = now1 and (now1.kind .. ":" .. tostring(now1.qid) .. ":" .. tostring(now1.npc) .. ":" .. tostring(now1.wx))
  G.ver = G.ver + 1 -- (the texts may have changed: the frame redraws on any Replan; the key feeds the trace)
  if QB.tracing and nowKey ~= wasKey then QB.Trace("guide: first step %s -> %s", tostring(wasKey or "none"), tostring(nowKey or "none")) end
end

function G.Current() return G.steps[1] end
function G.Steps() return G.steps end

-- "Not now" (an hour) or "Drop" (for good); the list is made again
function G.Skip(id, how)
  if not id then return end
  if how == "drop" then QB:SetSkipped(id, true)
  else laterDB().later[id] = time and time() or 0 end
  QB:MarkDirty()
end

-- the game's events, from Core.lua's frame (Task 4 adds the rest)
function G.OnEvent(event, a1, a2)
  if event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" or event == "PLAYER_LEVEL_UP" then
    QB:MarkDirty() -- (Core.lua marks it too: the list is made again after the re-plan)
  end
end
```

Note the `objectiveSteps` call passes `nil` as `lead` (the first-step rule is applied after the list is built); keep the parameter for Task 4's kept-spot ordering.

Add `Guide.lua` to `QuestBank.toc` after `Auto.lua`. In `Core.lua`'s `QB:Changed()`, after `QB.Try("plan", QB.Recompute, QB)`:

```lua
  if QB.Guide then QB.Try("guide", QB.Guide.Replan) end
```

and in the event handler, before the final `QB:MarkDirty()` (inside the branches for `QUEST_ACCEPTED`, `QUEST_TURNED_IN`, `PLAYER_LEVEL_UP` is enough: add one line at the top of the handler after the `ADDON_LOADED` branch):

```lua
  if QB.Guide and QB.Guide.OnEvent then QB.Try("guide", QB.Guide.OnEvent, event, a1, a2) end
```

- [ ] **Step 4: Run the harness**

Run: `cd /Users/mikalbot/foreverrank/tools/questbank && luajit harness.lua 2>&1 | tail -6`
Expected: `6.0 guide: steps from the target: ...: ok` and the gates. If "the first step" fails because the catalog's D.SPOT for quest 7 is absent on this Data.lua, check `grep -c "^\[7\]=" ` in `Data.lua`'s `D.SPOT` block; the case relies on the Northshire kobold spot (gen_data's CMaNGOS spawns) which 5.4.4 ships.

- [ ] **Step 5: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/QuestBank/Guide.lua tools/questbank/QuestBank/QuestBank.toc tools/questbank/QuestBank/Core.lua tools/questbank/harness.lua && git commit -q -m "feat(questbank): Guide.lua: steps from the one target and the route, done by themselves" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 3: The auto fill: the quests Now ranks best, into the plan

**Files:**
- Modify: `tools/questbank/QuestBank/Guide.lua` (add `G.Fill`, called at the start of `G.Replan`)
- Modify: `tools/questbank/QuestBank/Core.lua` (`QB:RouteEntries("plan")` considers `auto`)
- Test: `harness.lua` `G6CASES`

**Interfaces:**
- Produces: `G.Fill(level)` returns how many auto picks the plan holds after the fill; `G.Rank(c, level)` the number a candidate is ranked by.
- Consumes: `UI:Candidates(nil, level)` rows `{ id, lvl, req, cat, rank, mins, behind, value }` (UI.lua:2011), `QB.QuestMap.Grey(q, level)`, `QB:ChainLead(id)`, `QB.Data.DROP`, `QB.Sync.members[*].quests`.

- [ ] **Step 1: Write the failing case**

```lua
  -- a level-23 human mid-chain (Redridge's chain, Duskwood and Wetlands quests in the log): the fill takes the best
  -- by XP a minute, never a quest more than two levels above, never grey, never the player's own pick twice, up to the
  -- free slots minus two and at most AUTO_MAX; a sensible first step, no step for a quest it cannot take
  G6CASES[#G6CASES + 1] = { "the fill: Now's best, within two levels, never grey, the player's list wins", function()
    local c = newClient({ name = "Trio", level = 23, cap = 60, faction = "Alliance", className = "Paladin", class = "PALADIN", classID = 2,
      race = "Human", log = { { 92, 0 }, { 221, 0 }, { 305, 0 } }, done = { [89] = true, [91] = true }, world = { 0, -9200, -2150 }, map = 1433, bagSlots = {}, bind = "Lakeshire" })
    login(c)
    local QB, G, D = c.QB, c.QB.Guide, c.QB.Data
    QB:Settings().guide.on = true
    QB:SetAdded(109, true) -- the player's own pick: Report to Gryan Stoutmantle (Westfall)
    settle(c)
    local p = QB:Plan()
    local n = 0
    for id in pairs(p.auto) do
      n = n + 1
      local q = QB.Quest.Get(id)
      assert(q and q.lvl <= 25 and QB.Quest.ForMe(q) and not QB.API.IsDone(id) and not QB.state.log[id], "an auto pick is for you, not held, within two levels: " .. tostring(id))
      assert(not p.add[id], "never the player's own pick twice")
      assert(not QB.QuestMap.Grey(q, 23) or QB:ChainLead(id) >= QB.Model.CHEAP * QB.Scale(23), "never grey unless its chain pays: " .. q.name)
      assert((q.req or 1) <= 23, "nothing it cannot take yet: " .. q.name)
    end
    assert(n > 0 and n <= G.AUTO_MAX and n <= QB.LOG_SLOTS - QB.state.logCount - 2, "picks within the limits: " .. n)
    assert(p.add[109] and QB:InPlan(QB.Quest.Get(109)), "the player's own pick stays in the plan")
    local first = G.steps[1]
    assert(first and (first.kind == "objective" or first.kind == "handin" or first.kind == "accept"), "a first step: " .. tostring(first and G.Text(first)))
    for _, s in ipairs(G.steps) do
      if s.kind == "accept" then
        local q = QB.Quest.Get(s.qid)
        assert(QB:Status(q).code == "todo" or QB:Status(q).code == "item", "no step for a quest you cannot take: " .. G.Text(s))
      end
    end
    -- the Guide off: the auto picks are not in the plan, the player's are
    QB:Settings().guide.on = false
    settle(c)
    local inPlan = 0
    for id in pairs(p.auto) do if QB:InPlan(QB.Quest.Get(id)) then inPlan = inPlan + 1 end end
    assert(inPlan == 0 and QB:InPlan(QB.Quest.Get(109)), "off: the fill is out of the plan, your pick is in")
  end }
```

- [ ] **Step 2: Run the harness to see it fail**

Run: `cd /Users/mikalbot/foreverrank/tools/questbank && luajit harness.lua 2>&1 | tail -4`
Expected: `picks within the limits: 0`.

- [ ] **Step 3: Write `G.Fill`**

In `Guide.lua`, before `G.Replan`:

```lua
-- the fill: the quests Now ranks best (UI:Candidates' rank: XP plus half the chain over trip and loop minutes, a
-- quarter when probably behind you), weighed by the drop rate as Now weighs it, half again as much when a party
-- member holds or can take it (Sync); never grey unless its chain pays the planner's low-value line, never more
-- than two levels above you, never one you put off or skipped, never one on your own list; up to the log's free
-- slots minus two, at most AUTO_MAX. Picks already made stay while they still qualify, so the plan holds still
local function partyHas(id)
  local S = QB.Sync
  if not (S and S.members) then return false end
  for _, m in pairs(S.members) do if m.quests and m.quests[id] then return true end end
  return false
end
function G.Rank(c, level)
  local drop = QB.Data.DROP and QB.Data.DROP[c.id]
  local weight = (drop and drop < 25) and (0.5 + drop / 50) or 1
  return (c.rank or 0) * weight * (partyHas(c.id) and 1.5 or 1)
end
local ranked = {}
function G.Fill(level)
  local p = QB:Plan()
  local s = QB.state
  local free = QB.LOG_SLOTS - (s.logCount or 0) - 2
  local line = QB.Model.CHEAP * QB.Scale(level)
  local function qualifies(id)
    local q = QB.Quest.Get(id)
    if not q or q.lvl > level + 2 or (q.req or 1) > level then return false end
    if p.add[id] or putOff(id) or QB:IsSkipped(id) or s.log[id] or QB.API.IsDone(id) then return false end
    local st = QB:Status(q)
    if st.code ~= "todo" and st.code ~= "item" then return false end
    if QB.QuestMap and QB.QuestMap.Grey(q, level) and QB:ChainLead(id) < line then return false end
    return true
  end
  -- what is held already: dropped once it no longer qualifies
  local n = 0
  for id in pairs(p.auto) do
    if qualifies(id) then n = n + 1 else p.auto[id] = nil end
  end
  if free <= n or n >= AUTO_MAX then return n end
  for k = #ranked, 1, -1 do ranked[k] = nil end
  for _, c in ipairs(QB.UI and QB.UI.Candidates and QB.UI:Candidates(nil, level) or {}) do
    if not p.auto[c.id] and not c.waste and (c.mins == nil or c.mins <= 20) and qualifies(c.id) then
      c.grank = G.Rank(c, level)
      if c.value and c.value >= line then ranked[#ranked + 1] = c end
    end
  end
  table.sort(ranked, function(a, b) if a.grank ~= b.grank then return a.grank > b.grank end return a.id < b.id end)
  for _, c in ipairs(ranked) do
    if n >= free or n >= AUTO_MAX then break end
    p.auto[c.id] = true
    n = n + 1
  end
  return n
end
```

At the top of `G.Replan`, after the `guide.on` check:

```lua
  if QB:GuideOn() then
    local before = QB:Plan().auto
    local n0 = 0
    for _ in pairs(before) do n0 = n0 + 1 end
    local n1 = G.Fill(QB.state.level or 1)
    if n1 ~= n0 and not G.filling then
      -- new picks: the route is planned again with them, and Replan runs again from QB:Changed
      G.filling = true
      QB.sigPlan, QB.sigNow = nil, nil
      QB:Recompute(true)
      G.filling = false
    end
  end
```

(`QB:Recompute(true)` plans synchronously, as `/qb start` does; the fill happens once per `Changed`, and the signature of `RouteEntries("plan")` carries the new quests, so the next `Changed` with nothing new plans nothing.)

In `Core.lua`'s `QB:RouteEntries(mode)`, after `if mode == "plan" then for id in pairs(self:Plan().add) do consider(id) end end`:

```lua
  if mode == "plan" and QB:GuideOn() then for id in pairs(self:Plan().auto) do consider(id) end end
```

- [ ] **Step 4: Run the harness**

Run: `cd /Users/mikalbot/foreverrank/tools/questbank && luajit harness.lua 2>&1 | tail -6`
Expected: the new case `ok`, the re-plan garbage line still under 1 MB (the fill adds a `Candidates` pass, which is memoised a second: if "a re-plan made NNN KB" exceeds 1024 KB, move the `ranked` sort to reuse one comparator closure as above and make sure `G.Fill` runs only when `QB:GuideOn()`; the owner's twin in that block banks, so the Guide is off there).

- [ ] **Step 5: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/QuestBank/Guide.lua tools/questbank/QuestBank/Core.lua tools/questbank/harness.lua && git commit -q -m "feat(questbank): the Guide fills the plan with Now's best quests, within two levels, never grey" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 4: Stable steps: out of order, the walk, skips, Zephras Isle

**Files:**
- Modify: `tools/questbank/QuestBank/Guide.lua`
- Test: `harness.lua` `G6CASES` (three cases)

**Interfaces:**
- Produces: `G.FirstKey()` (the stable key of the first step: kind, quest, NPC, place), `G.Skip(id, "later" | "drop")` (Task 2) proven; `G.later` honoured in `G.Fill` and `G.Replan`.

- [ ] **Step 1: Write the failing cases**

```lua
  -- out of order: an objective finished before its pick-up step (the quest taken by hand first), and a quest handed
  -- in that the plan had later: the engine plans from the state, never from a list
  G6CASES[#G6CASES + 1] = { "out of order: planned from the state, never a fixed list", function()
    local c = human("Oona", { { 7, 0 } }, { [783] = true })
    local QB, G = c.QB, c.QB.Guide
    c.objectives = { [7] = { { text = "Kobold Vermin slain: 0/8", type = "monster", finished = false, numFulfilled = 0, numRequired = 8 } } }
    QB:Settings().guide.on = true
    QB:SetAdded(15, true); QB:SetAdded(18, true) -- Investigate Echo Ridge, Brotherhood of Thieves
    settle(c)
    local function has(kind, qid) for _, s in ipairs(G.steps) do if s.kind == kind and s.qid == qid then return true end end return false end
    assert(has("accept", 15) and has("accept", 18), "the two pick-ups are steps")
    -- Brotherhood of Thieves taken by hand and already 12/12: no accept step, no kill step, a hand-in step
    c.log = { { 7, 0 }, { 18, 1 } }
    c.objectives[18] = { { text = "Kobold Worker slain: 12/12", type = "monster", finished = true, numFulfilled = 12, numRequired = 12 } }
    c.ev(QB.eventFrame, "QUEST_ACCEPTED", 2, 18)
    settle(c)
    assert(not has("accept", 18) and not has("objective", 18) and has("handin", 18), "finished before its step: only the hand-in is left")
    -- Investigate Echo Ridge handed in while the plan had it later: nothing of it remains
    c.log = { { 7, 0 } }; c.done[15] = true
    c.ev(QB.eventFrame, "QUEST_TURNED_IN", 15, 40)
    settle(c)
    assert(not has("accept", 15) and not has("objective", 15) and not has("handin", 15), "handed in early: gone")
    assert(not QB:Plan().auto[15] and not QB:Plan().add[15] or QB.API.IsDone(15), "and not picked again")
  end }

  -- the owner's walk from Southshore into Alterac (RCASES' client and walk): the first step does not change without a
  -- real event; Not now puts a quest off for an hour, Drop for good
  G6CASES[#G6CASES + 1] = { "the walk: the first step changes only on a real event; Not now and Drop", function()
    local HILLS = {
      [1424] = { wy0 = 1066.91, wyx = -32.0059, wx0 = 400.10, wxy = -21.3354 },
      [1416] = { wy0 = 783.55, wyx = -28.0005, wx0 = 1499.91, wxy = -18.6646 },
    }
    local c = newClient({ name = "Walker", level = 30, cap = 60, faction = "Alliance", className = "Warrior", class = "WARRIOR", classID = 1,
      race = "Human", log = { { 500, 0 }, { 504, 0 } }, done = {}, world = { 0, -852, -517 }, map = 1424, bagSlots = {}, bind = "Southshore" })
    local env = c.env
    c.me = { wx = -852, wy = -517 }
    local function toMap(m, wx, wy) local t = HILLS[m]; if not t then return nil end; return (wy - t.wy0) / t.wyx / 100, (wx - t.wx0) / t.wxy / 100 end
    local function mapAt(wx, wy) local _, y = toMap(1424, wx, wy); return y < 0.14 and 1416 or 1424 end
    env.C_Map.GetBestMapForUnit = function() return mapAt(c.me.wx, c.me.wy) end
    env.MapUtil.GetDisplayableMapForPlayer = function() return mapAt(c.me.wx, c.me.wy) end
    env.C_Map.GetPlayerMapPosition = function(m) local x, y = toMap(m, c.me.wx, c.me.wy); if not x then return nil end; return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
    local wpos = env.C_Map.GetWorldPosFromMapPos
    env.C_Map.GetWorldPosFromMapPos = function(m, v) local t = HILLS[m]; if not t then return wpos(m, v) end; return 0, { x = t.wx0 + t.wxy * v.y * 100, y = t.wy0 + t.wyx * v.x * 100, GetXY = function(self) return self.x, self.y end } end
    env.C_Map.GetMapPosFromWorldPos = function(cont, pos, m) local x, y = toMap(m, pos.x, pos.y); if cont ~= 0 or not x then return nil end; return m, env.CreateVector2D(x, y) end
    env.C_Map.GetMapRectOnMap = function() return nil end
    env.IsInInstance = function() return false, "none" end
    login(c)
    local QB, G = c.QB, c.QB.Guide
    QB:Settings().guide.on = true
    c.objectives = { [500] = { { text = "Crushridge Ogre slain: 0/10", type = "monster", finished = false, numFulfilled = 0, numRequired = 10 } },
                     [504] = { { text = "Crushridge Mage slain: 0/5", type = "monster", finished = false, numFulfilled = 0, numRequired = 5 } } }
    QB.Arrow:Set(true)
    settle(c)
    local key = G.FirstKey()
    assert(key and key ~= "", "a first step on the walk: " .. tostring(key))
    -- the walk north, 60 yards a look, 25 looks: no event, the first step stays
    for i = 1, 25 do
      c.me.wx = -852 + i * 60
      c.o.world = { 0, c.me.wx, c.me.wy }
      if mapAt(c.me.wx, c.me.wy) ~= mapAt(c.me.wx - 60, c.me.wy) then c.ev(QB.eventFrame, "ZONE_CHANGED_NEW_AREA") end
      for _ = 1, 12 do frame(c, 0.1) end
      QB.Model.Finish()
      assert(G.FirstKey() == key, string.format("look %d: the first step changed with nothing done: %s -> %s", i, key, G.FirstKey()))
    end
    -- Not now: the quest's steps go for an hour; Drop: for good
    local qid = G.steps[1].qid
    G.Skip(qid, "later")
    settle(c)
    for _, s in ipairs(G.steps) do assert(s.qid ~= qid, "put off: no step of it") end
    assert(G.PutOff(qid), "put off for an hour")
    G.DB().later[qid] = (c.env.time() - 3601)
    settle(c)
    assert(not G.PutOff(qid), "an hour on: back")
    local other = G.steps[1].qid
    G.Skip(other, "drop")
    settle(c)
    assert(QB:IsSkipped(other), "dropped for good")
    for _, s in ipairs(G.steps) do assert(s.qid ~= other, "dropped: no step of it") end
  end }

  -- Zephras Isle at level 5 (RCASES' isle client): the steps are the isle's, with places on its own world
  G6CASES[#G6CASES + 1] = { "Zephras Isle at level 5", function()
    local ISLE = { minx = 1247.917, maxx = 4956.25, miny = -1331.25, maxy = 4231.25 }
    local c = newClient({ name = "Isla", level = 5, cap = 60, faction = "Alliance", className = "Mage", class = "MAGE", classID = 8,
      race = "Human", log = { { 92470, 1 }, { 92544, 0 } }, done = {}, world = { 2991, 3200, 1650 }, map = 2521, bagSlots = {}, bind = "Shen'dar Village" })
    local env = c.env
    c.me = { wx = 3200, wy = 1650 }
    local function toMap(wx, wy) return (ISLE.maxy - wy) / (ISLE.maxy - ISLE.miny), (ISLE.maxx - wx) / (ISLE.maxx - ISLE.minx) end
    env.C_Map.GetBestMapForUnit = function() return 2521 end
    env.MapUtil.GetDisplayableMapForPlayer = function() return 2521 end
    env.C_Map.GetPlayerMapPosition = function(m) if m ~= 2521 then return nil end; local x, y = toMap(c.me.wx, c.me.wy); return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
    env.C_Map.GetMapPosFromWorldPos = function(cont, pos, m) if cont ~= 2991 or m ~= 2521 then return nil end; return m, env.CreateVector2D(toMap(pos.x, pos.y)) end
    env.C_Map.GetMapRectOnMap = function() return nil end
    env.IsInInstance = function() return false, "none" end
    login(c)
    local QB, G = c.QB, c.QB.Guide
    QB:Settings().guide.on = true
    settle(c)
    local s1 = G.steps[1]
    assert(s1 and s1.c == 2991 and s1.m == 2521, "the first step is on the isle: " .. tostring(s1 and G.Text(s1)))
    local isle = 0
    for id in pairs(QB:Plan().auto) do local q = QB.Quest.Get(id); if q and q.cat and q.cat.name == "Zephras Isle" then isle = isle + 1 end end
    assert(isle > 0, "the fill picks the isle's quests")
    for _, s in ipairs(G.steps) do assert(s.c == 2991 or s.kind == "travel", "every step on the isle or a way off it: " .. G.Text(s)) end
  end }
```

- [ ] **Step 2: Run the harness to see them fail**

Run: `cd /Users/mikalbot/foreverrank/tools/questbank && luajit harness.lua 2>&1 | tail -4`
Expected: `attempt to call field 'FirstKey' (a nil value)` or the out-of-order assertion.

- [ ] **Step 3: Write `G.FirstKey`, honour `putOff` in the fill (done in Task 3) and the stable order**

In `Guide.lua`, after `G.Steps`:

```lua
-- the first step told apart as the target tells stops: its kind, its quest, its NPC and its place
function G.FirstKey()
  local s = G.steps[1]
  if not s then return "" end
  return s.kind .. ":" .. tostring(s.qid) .. ":" .. tostring(s.npc) .. ":" .. tostring(s.wx and math.floor(s.wx) or "")
end
```

Replace the two `wasKey`/`nowKey` computations in `G.Replan` with `local wasKey = G.FirstKey()` (before clearing; drop the `was1` local) and `local nowKey = G.FirstKey()` (after building). The walk case passes because `G.Replan` runs only from `QB:Changed()` (a re-plan happens only on the signature's parts, Core.lua:2418) and takes its first step from `T.Get(me)`, which 5.4.4 keeps. If a look still flips the key, the culprit is `objectiveSteps` sorting by distance for the first quest: in that function sort by `d` only for quests other than `cur.qid`; for `cur.qid` the kept spot (`cur.wx, cur.wy`) is placed first by the block at the end of `Replan` (already written). Make sure that block runs before `nowKey` is read.

- [ ] **Step 4: Run the harness**

Run: `cd /Users/mikalbot/foreverrank/tools/questbank && luajit harness.lua 2>&1 | tail -8`
Expected: the three cases `ok`, gates hold.

- [ ] **Step 5: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/QuestBank/Guide.lua tools/questbank/harness.lua && git commit -q -m "feat(questbank): the Guide plans from the state: out of order, the walk, Not now and Drop, the isle" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 5: Travel steps and the corpse

**Files:**
- Modify: `tools/questbank/QuestBank/Guide.lua` (travel steps from the arrow's way; `G.Corpse`, `G.dead`)
- Modify: `tools/questbank/QuestBank/Arrow.lua:190-202` (`A.Target`: the corpse in route mode), `:206` (`HEAD.corpse`)
- Modify: `tools/questbank/QuestBank/Core.lua` (register `PLAYER_DEAD`, `PLAYER_UNGHOST`, `PLAYER_ALIVE`)
- Modify: `tools/questbank/harness.lua` (mock `C_DeathInfo`)
- Test: `harness.lua` `G6CASES`

**Interfaces:**
- Produces: `G.Corpse()` returns `{ kind = "corpse", name = "Your corpse", c, wx, wy, m, x, y }` (one table reused) or nil; travel steps `{ kind = "travel", text = <TV step line>, c, wx, wy, m, x, y }` inserted before the first step they lead to.
- Consumes: `C_DeathInfo.GetCorpseMapPosition(uiMapID)` -> Vector2D or nil (`DeathInfoDocumentation.lua:11`); `QB.Travel.PlanTo(place, mode)` -> `{ legs = { { kind, text/step words, from = {c,wx,wy}, ... } }, min }` (Travel.lua:1044; a leg's words come from `TV.STEP[kind]`, read the table at Travel.lua:53 for the field names before coding: the leg's `start` place and its `line`).

- [ ] **Step 1: Mock the client's corpse call and write the failing case**

In `harness.lua`'s `newClient`, after `env.UnitIsDeadOrGhost = function() return c.ghost or false end` (line 962):

```lua
  -- where your corpse lies on a map, while you are a ghost: c.corpse = { m, x, y } (map percent 0-1)
  env.C_DeathInfo = { GetCorpseMapPosition = function(m)
    local k = c.corpse
    if not (k and c.ghost and k[1] == m) then return nil end
    return { x = k[2], y = k[3], GetXY = function(self) return self.x, self.y end }
  end }
```

Case:

```lua
  -- dead: the arrow and the first step lead to the corpse and say so; alive again, back to the route with the same
  -- first step (a release is no jump: Target.lua)
  G6CASES[#G6CASES + 1] = { "death: the arrow to the corpse and back", function()
    local c = human("Ghost", { { 7, 0 } }, { [783] = true })
    local QB, G, A = c.QB, c.QB.Guide, c.QB.Arrow
    c.objectives = { [7] = { { text = "Kobold Vermin slain: 2/8", type = "monster", finished = false, numFulfilled = 2, numRequired = 8 } } }
    QB:Settings().guide.on = true
    A:Set(true)
    settle(c)
    local key = G.FirstKey()
    c.ghost = true
    c.corpse = { 1429, 0.48, 0.42 }
    c.ev(QB.eventFrame, "PLAYER_DEAD")
    for _ = 1, 15 do frame(c, 0.1) end
    local s1 = G.steps[1]
    assert(s1 and s1.kind == "corpse" and G.Text(s1) == "Run to your corpse" and s1.m == 1429 and math.abs(s1.x - 48) < 0.01, "the first step: the corpse: " .. tostring(s1 and G.Text(s1)))
    assert(A.t and A.t.kind == "corpse" and A.t.wx == s1.wx and A.t.wy == s1.wy, "the arrow points at it: " .. tostring(A.t and A.t.kind))
    assert(c.env.QuestBankArrow.name:GetText():find("corpse", 1, true), "and says so: " .. tostring(c.env.QuestBankArrow.name:GetText()))
    c.ghost = false; c.corpse = nil
    c.ev(QB.eventFrame, "PLAYER_UNGHOST")
    for _ = 1, 15 do frame(c, 0.1) end
    assert(G.FirstKey() == key, "alive: the same first step as before: " .. key .. " / " .. G.FirstKey())
    assert(A.t and A.t.kind == "route", "the arrow back on the route")
  end }

  -- travel: a hand-in across a flight the character knows: the step before it is the arrow's ("Fly to Stormwind")
  G6CASES[#G6CASES + 1] = { "travel steps come from the arrow's way", function()
    local c = human("Flyer", {}, {}, nil, 12)
    local QB, G, D = c.QB, c.QB.Guide, c.QB.Data
    -- a quest handed in in Stormwind City while standing in Northshire: the route flies or walks; a travel step precedes it
    local function stormwindQuest()
      local ids = {}
      for id in pairs(D.Q) do ids[#ids + 1] = id end
      table.sort(ids)
      for _, id in ipairs(ids) do
        local q = QB.Quest.Get(id)
        local n = q and q.turnIdx and q.turnIdx > 0 and D.NPC[q.turnIdx]
        if n and n[2] == 1453 and q.lvl <= 14 and QB.Quest.ForMe(q) and not q.repeatable then return id end
      end
    end
    local sw = stormwindQuest()
    assert(sw, "a Stormwind hand-in for a level-12 human")
    c.log = { { sw, 1 } }
    QB:Settings().guide.on = true
    QB.Arrow:Set(true)
    settle(c)
    for _ = 1, 10 do frame(c, 0.1) end
    local travel, handin
    for i, s in ipairs(G.steps) do
      if s.kind == "travel" and not travel then travel = i end
      if s.kind == "handin" and s.qid == sw then handin = i end
    end
    assert(handin, "the hand-in is a step")
    if QB.Arrow.MiniStep() then assert(travel and travel < handin, "a travel step before the hand-in it leads to") end
  end }
```

- [ ] **Step 2: Run the harness to see it fail**

Run: `cd /Users/mikalbot/foreverrank/tools/questbank && luajit harness.lua 2>&1 | tail -4`
Expected: `the first step: the corpse: Kill Kobold Vermin 2/8`.

- [ ] **Step 3: The corpse in Guide.lua and Arrow.lua; the travel step**

Guide.lua, after `G.PutOff`:

```lua
-- dead: where your corpse lies (C_DeathInfo.GetCorpseMapPosition, on the map you are on), in continent yards; nil alive
-- or where the client won't say. One table, filled anew each look
local corpse = { kind = "corpse", name = "Your corpse" }
local function ghost()
  if type(UnitIsDeadOrGhost) ~= "function" then return false end
  local ok, v = pcall(UnitIsDeadOrGhost, "player")
  return ok and plain(v) == true
end
function G.Corpse()
  if not ghost() or not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition) then G.dead = false; return nil end
  local m = QB.API.MapID()
  if type(m) ~= "number" then return nil end
  local ok, pos = pcall(C_DeathInfo.GetCorpseMapPosition, m)
  pos = ok and plain(pos) or nil
  local x, y = pos and plain(pos.x), pos and plain(pos.y)
  if type(x) ~= "number" or type(y) ~= "number" then return nil end
  local w = QB.Model.World(m, x * 100, y * 100, wbuf)
  if not w then return nil end
  corpse.m, corpse.x, corpse.y, corpse.c, corpse.wx, corpse.wy = m, x * 100, y * 100, w.c, w.wx, w.wy
  G.dead = true
  return corpse
end
```

In `G.Replan`, right after the `guide.on` check and the fill, before building from the target:

```lua
  local k = G.Corpse()
  if k then
    local s = step("corpse")
    s.c, s.wx, s.wy, s.m, s.x, s.y = k.c, k.wx, k.wy, k.m, k.x, k.y
    G.steps[1] = s
    -- (the route's steps follow, so the frame still shows what comes after)
  end
```

and make the "hand-in in reach" and the "first step is the target's" blocks skip when `G.steps[1]` is the corpse (`if cur and ... and not (G.steps[1] and G.steps[1].kind == "corpse")`). The travel step, after the list is built and before `nowKey`:

```lua
  -- the arrow's step on the way to the first step (a flight master, a pier, the tram: Target.lua's T.Step) goes before it
  local ts, onWay = QB.Target and QB.Target.Step and QB.Target.Step()
  if ts and onWay and G.steps[1] and G.steps[1].kind ~= "corpse" then
    local s = step("travel")
    s.text, s.c, s.wx, s.wy = ts.name, ts.c, ts.wx, ts.wy
    s.atlas, s.icon = ts.atlas, ts.icon
    table.insert(G.steps, 1, s)
  end
```

`G.OnEvent` adds:

```lua
  if event == "PLAYER_DEAD" or event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then
    G.Replan()
    if QB.Arrow and QB.Arrow.Invalidate then QB.Arrow.Invalidate() end
    G.ver = G.ver + 1
    return
  end
```

Core.lua: add `"PLAYER_DEAD", "PLAYER_UNGHOST", "PLAYER_ALIVE"` to the event list at line 2776 (they reach `QB.Guide.OnEvent` through the forwarding line of Task 2; make the handler `return` after forwarding for these three so no `MarkDirty` follows a release).

Arrow.lua `A.Target(here)`, first lines:

```lua
  if A.temp then return A.temp end
  local k = QB.Guide and QB.Guide.Corpse and QB.Guide.Corpse()
  if k then return k end
```

and `HEAD.corpse = "Run to %s"`, `VERB.corpse = "Run to"`, `NOTHING.corpse = { "Your corpse", nil }` next to the other tables (lines 204-206, 498). `A:Draw` names the target by `t.name` already; check `A.TintFor`'s `GREY.ghost` keeps the arrow lit for a corpse target: add `if t.kind == "corpse" then return A.TINT_MIX end` guard before the ghost grey, or whatever that function returns for a lit arrow (read `A.TintFor` at Arrow.lua:524 first).

The ghost look: `Target.lua`'s `T.Look` runs once a second; add to it, after the dead branch: `if QB.Guide and QB.Guide.dead ~= nil and QB.Guide.dead ~= yes(UnitIsDeadOrGhost, "player") then QB.Guide.OnEvent(QB.Guide.dead and "PLAYER_ALIVE" or "PLAYER_DEAD") end` so a client that fires none of the three events still turns.

- [ ] **Step 4: Run the harness**

Run: `cd /Users/mikalbot/foreverrank/tools/questbank && luajit harness.lua 2>&1 | tail -8`
Expected: both cases `ok`; the arrow's existing cases (`RCASES`, `B3CASES`) still `ok`.

- [ ] **Step 5: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/QuestBank/Guide.lua tools/questbank/QuestBank/Arrow.lua tools/questbank/QuestBank/Core.lua tools/questbank/QuestBank/Target.lua tools/questbank/harness.lua && git commit -q -m "feat(questbank): the Guide's travel steps, and the corpse when you are dead" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 6: The grind step

**Files:**
- Modify: `tools/questbank/QuestBank/Guide.lua` (`G.Grind`)
- Test: `harness.lua` `G6CASES`

**Interfaces:**
- Produces: `G.Grind(level, me)` returns a step `{ kind = "grind", text, c, wx, wy, m, x, y, until = N }` or nil; appended as the only step when the list is empty and nothing worth taking is in reach.
- Consumes: `UI:Candidates(nil, level, level + 3)` (the third argument `reqMax` widens the required level), `QB.QuestMap.Spots(str)` (QuestMap.lua:94: parses `D.SPOT[id]` into `{ kind, slot, m, x, y, r, src, name }`), `D.SN`, `D.CAT[cat].name`.

- [ ] **Step 1: Write the failing case**

```lua
  -- nothing worth taking in reach: a level-22 human in Northshire with every Elwynn quest done (the catalog's quests
  -- for the level band marked done, the rest too high): one step says to grind, where, until which level, and where
  -- the plan goes on
  G6CASES[#G6CASES + 1] = { "nothing worth taking in reach: the grind step", function()
    local c = human("Grinder", {}, {}, nil, 22)
    local QB, G, D = c.QB, c.QB.Guide, c.QB.Data
    for id, r in pairs(D.Q) do if r[2] <= 22 then c.done[id] = true end end -- everything you could take: done
    QB.API.RefreshDone()
    QB:Settings().guide.on = true
    settle(c)
    local s = G.steps[1]
    assert(s and s.kind == "grind", "a grind step: " .. tostring(s and G.Text(s)))
    assert(G.Text(s):match("^Kill around .+ until level (%d+)") and s["until"] and s["until"] > 22, "it names the level: " .. G.Text(s))
    assert(#G.steps == 1, "the only step")
    assert(G.Text(s):find(", then ", 1, true), "and where the plan goes on: " .. G.Text(s))
  end }
```

- [ ] **Step 2: Run the harness to see it fail**

Expected: `a grind step: ` (nil).

- [ ] **Step 3: Write `G.Grind`**

```lua
-- nothing worth taking in reach: where to kill until the next level that opens quests, and where they are
local grind = { kind = "grind" }
function G.Grind(level, me)
  local UI, D, M = QB.UI, QB.Data, QB.Model
  if not (UI and UI.Candidates) then return nil end
  local nextReq, nextCat
  for _, cand in ipairs(UI:Candidates(nil, level, level + 3)) do
    if cand.req and cand.req > level and (not nextReq or cand.req < nextReq or (cand.req == nextReq and (cand.mins or huge) < (nextCat and nextCat.mins or huge))) then
      nextReq, nextCat = cand.req, cand
    end
  end
  if not nextReq then return nil end
  -- the nearest kill spot of a quest around your level, for you
  local best, bd, bname
  local bit, rbit = QB.API.ClassBit(), QB.API.RaceBit()
  if me and D.SPOT and QB.QuestMap and QB.QuestMap.Spots then
    for id, r in pairs(D.Q) do
      if r[1] >= level - 2 and r[1] <= level + 1 and D.SPOT[id] then
        local side, cls = r[3], r[9]
        if (side == 0 or (side == 1 and QB.faction == "A") or (side == 2 and QB.faction == "H")) and (cls == 0 or bit == 0 or math.floor(cls / bit) % 2 == 1) then
          for _, sp in ipairs(QB.QuestMap.Spots(D.SPOT[id]) or {}) do
            if sp.kind == "k" then
              local w = M.World(sp.m, sp.x * 100, sp.y * 100, wbuf)
              if w and w.c == me.c then
                local d = (w.wx - me.wx) ^ 2 + (w.wy - me.wy) ^ 2
                if not bd or d < bd then
                  best, bd = sp, d
                  bname = (sp.name and D.SN and D.SN[sp.name]) or (D.MAPNAME and D.MAPNAME[sp.m]) or nil
                  grind.c, grind.wx, grind.wy, grind.m, grind.x, grind.y = w.c, w.wx, w.wy, sp.m, sp.x * 100, sp.y * 100
                end
              end
            end
          end
        end
      end
    end
  end
  local cat = D.CAT[nextCat.cat]
  local where = cat and cat.name or "the next zone"
  grind["until"] = nextReq
  if best then
    grind.text = string.format("Kill around %s until level %d, then %s", bname or "here", nextReq, where)
  else
    grind.text = string.format("Kill around here until level %d, then %s", nextReq, where)
    grind.c, grind.wx, grind.wy, grind.m, grind.x, grind.y = nil, nil, nil, nil, nil, nil
  end
  return grind
end
```

In `G.Replan`, after the travel step and before `nowKey`:

```lua
  if #G.steps == 0 then
    local g = G.Grind(QB.state.level or 1, me)
    if g then
      local s = step("grind")
      s.text, s["until"], s.c, s.wx, s.wy, s.m, s.x, s.y = g.text, g["until"], g.c, g.wx, g.wy, g.m, g.x, g.y
      G.steps[1] = s
    end
  end
```

The whole-catalog scan in `G.Grind` runs only when the list is empty, which is rare; it allocates nothing but `wbuf`'s reuse. If the memory block's "garbage a minute" rises, memoise `G.Grind` by `(level, QB.doneVer, math.floor(me.wx / 200), math.floor(me.wy / 200))`.

- [ ] **Step 4: Run the harness**

Expected: `6.0 guide: nothing worth taking in reach: the grind step: ok`, gates hold.

- [ ] **Step 5: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/QuestBank/Guide.lua tools/questbank/harness.lua && git commit -q -m "feat(questbank): the grind step: where to kill until the next level, and where the plan goes on" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 7: The trainer seed and the spell levels (offline data)

**Files:**
- Modify: `tools/questbank/cmangos.py:135-215` (`class_trainers(data)`, written as `out["trainers"]`)
- Modify: `tools/questbank/gen_data.py` (after the `D.CAMP_SELL` block at line 2889-2940: `D.TRAINER`; `D.SPELL_LV` from `codex/spellbook.json`; the header comment lines)
- Modify: `tools/questbank/QuestBank/Data.lua` (generated)
- Test: `harness.lua` (a data case in `G6CASES`: the tables have the shape the Guide reads)

**Interfaces:**
- Produces: `D.TRAINER = { { npc id, name, class id (CMaNGOS TrainerClass: 1 Warrior, 2 Paladin, 3 Hunter, 4 Rogue, 5 Priest, 7 Shaman, 8 Mage, 9 Warlock, 11 Druid), continent, world x, world y, uiMap, x, y }, ... }`; `D.SPELL_LV = { WARRIOR = { 1, 4, 6, 8, ... }, ... }` (class tokens as `UnitClass` returns them, each level at which `codex/spellbook.json` lists a spell with `src == "client"` and that `lvl`).
- The generator function names: `cmangos.py` `class_trainers(data)`; `gen_data.py` reads `_cm.get("trainers")` into `TRAINERS` and writes `D.TRAINER`; `spell_levels()` reads `os.path.join(REPO, "codex", "spellbook.json")` and writes `D.SPELL_LV`.

- [ ] **Step 1: Write the failing harness case**

```lua
  G6CASES[#G6CASES + 1] = { "data: class trainers and spell levels are in Data.lua", function()
    local c = human("Datum")
    local D = c.QB.Data
    assert(type(D.TRAINER) == "table" and #D.TRAINER > 50, "D.TRAINER rows: " .. tostring(D.TRAINER and #D.TRAINER))
    local mage, placed = 0, 0
    for _, t in ipairs(D.TRAINER) do
      assert(type(t[1]) == "number" and type(t[2]) == "string" and type(t[3]) == "number" and t[3] >= 1 and t[3] <= 11, "a row: id, name, class id")
      if t[3] == 8 then mage = mage + 1 end
      if t[4] == 0 or t[4] == 1 then placed = placed + 1 end
    end
    assert(mage >= 10 and placed > #D.TRAINER * 0.8, "mage trainers and most placed on the two continents: " .. mage .. ", " .. placed)
    assert(type(D.SPELL_LV) == "table" and type(D.SPELL_LV.WARRIOR) == "table" and #D.SPELL_LV.WARRIOR >= 15 and D.SPELL_LV.WARRIOR[1] == 1, "spell levels per class token")
    for _, tok in ipairs({ "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
      assert(D.SPELL_LV[tok] and #D.SPELL_LV[tok] >= 10, tok .. " has levels")
    end
  end }
```

- [ ] **Step 2: Run the harness to see it fail**

Expected: `D.TRAINER rows: nil`.

- [ ] **Step 3: cmangos.py: the class trainers**

Add before `def main():`:

```python
def class_trainers(data):
    """Every class trainer (creature_template NpcFlags & 16, TrainerType 0 = class, TrainerClass the class id) with its
    spawn points on the two continents: [[entry, name, class id, [[map, x, y], ...]], ...]. CMaNGOS Classic data, GPL-3.0."""
    stands = spawn_points(data, "npc")
    out = []
    for idx, r in data["creature_template"]:
        flags = r[idx["npcflags"]] or 0
        if flags & 16 and (r[idx["trainertype"]] or 0) == 0 and (r[idx["trainerclass"]] or 0) > 0:
            e = r[idx["entry"]]
            spots = [[m, round(x, 1), round(y, 1)] for m, x, y in stands.get(e, ())]
            if spots:
                out.append([e, r[idx["name"]], r[idx["trainerclass"]], spots])
    return sorted(out)
```

(`spawn_points` already lower-cases the column names in `idx`; check `rows_of`/`read` at cmangos.py:37-88 and use the same key spelling it produces, `trainertype` and `trainerclass`.) In `main()`, add `"trainers": class_trainers(data)` to `out` and `len(out["trainers"])` to the print. Then:

```bash
cd /Users/mikalbot/foreverrank && python3 tools/questbank/cmangos.py
```
Expected: `wrote .../cmangos.json: ... N class trainers` with N between 150 and 400.

- [ ] **Step 4: gen_data.py: `D.TRAINER` and `D.SPELL_LV`**

After the `D.CAMP_SELL` block (line 2936 `lines.append("D.CAMP_SELL = ...`):

```python
# D.TRAINER: the class trainers, for the Guide's "Train at <name>" step (Guide.lua). CMaNGOS Classic spawns (GPL-3.0),
# each placed as a camp seller is (TR.locate, overlays through spot_map, the game's place where players saw the NPC
# more than GAME_MOVE_YD away): {npc id, name, class id (1 Warrior, 2 Paladin, 3 Hunter, 4 Rogue, 5 Priest, 7 Shaman,
# 8 Mage, 9 Warlock, 11 Druid), continent, world x, world y, uiMap, x, y}. One row per spawn on the two continents
TRAINERS, _TRAIN_OUT = [], 0
for _e, _name, _cls, _spots in (_cm.get("trainers") or []):
    for _c, _wx, _wy in _spots:
        if _c not in (0, 1):
            continue
        _loc = TR.locate(_c, _wx, _wy)
        if _loc and _loc[0] in OVERLAY:
            _at = spot_map(_c, _wx, _wy)
            _loc = (_at[0], round(_at[1], 1), round(_at[2], 1)) if _at else _loc
        if not _loc:
            _TRAIN_OUT += 1
            continue
        _m, _x, _y, _moved = game_place("npc", _e, _loc[0], _loc[1], _loc[2])
        if _moved:
            _c, _wx, _wy = TR.world(_m, _x, _y)
        TRAINERS.append([_e, _name, _cls, _c, int(round(_wx)), int(round(_wy)), _m, round(_x, 1), round(_y, 1)])
assert len(TRAINERS) > 50, "cmangos.json has no class trainers: run cmangos.py"
lines.append("-- the class trainers (CMaNGOS Classic spawns, GPL-3.0): {npc id, name, class id (1 Warrior, 2 Paladin, 3 Hunter, 4 Rogue,")
lines.append("-- 5 Priest, 7 Shaman, 8 Mage, 9 Warlock, 11 Druid), continent, world x, world y, uiMap, x, y}; the Guide's Train step (Guide.lua)")
lines.append("D.TRAINER = {\n" + ",\n".join(lua(r) for r in TRAINERS) + "\n}")
print("class trainers: %d placed, %d not on a map" % (len(TRAINERS), _TRAIN_OUT))
lines.append("")

# D.SPELL_LV: the levels each class learns a new spell or rank at, from the site's spellbook (codex/spellbook.json,
# built by tools/build_spellbook.py from the Forever client's tables): the Guide adds a Train step at those levels
def spell_levels():
    book = load_json(os.path.join(REPO, "codex", "spellbook.json"), {}) or {}
    tok = {"Warrior": "WARRIOR", "Paladin": "PALADIN", "Hunter": "HUNTER", "Rogue": "ROGUE", "Priest": "PRIEST",
           "Shaman": "SHAMAN", "Mage": "MAGE", "Warlock": "WARLOCK", "Druid": "DRUID"}
    out = {}
    for sp in book.get("spells") or []:
        t = tok.get(sp.get("c"))
        lv = sp.get("lvl")
        if t and sp.get("src") == "client" and isinstance(lv, int) and 1 <= lv <= MAXLVL and not sp.get("classiconly") and not sp.get("basic"):
            out.setdefault(t, set()).add(lv)
    return {t: sorted(v) for t, v in out.items()}
SPELL_LV = spell_levels()
assert len(SPELL_LV) == 9 and all(len(v) >= 10 for v in SPELL_LV.values()), "spellbook.json gives too few learn levels: %r" % {k: len(v) for k, v in SPELL_LV.items()}
lines.append("-- [class token] = the levels the class learns a new spell or rank at (codex/spellbook.json, the Forever client's tables)")
lines.append("D.SPELL_LV = {\n" + ",\n".join("%s = {%s}" % (t, ",".join(str(l) for l in SPELL_LV[t])) for t in sorted(SPELL_LV)) + "\n}")
lines.append("")
```

Check `load_json`'s signature at gen_data.py:75 (`load_json(path, default=None)`) and that `OVERLAY`, `spot_map`, `game_place`, `TR` are defined above line 2889 (they are: 899, 914, 855, 121). Then:

```bash
cd /Users/mikalbot/foreverrank && python3 tools/questbank/gen_data.py
```
Expected: `class trainers: N placed, M not on a map` and the usual summary; `Data.lua` grows by roughly 300 rows and nine short lists. Run `python3 tools/questbank/gen_data.py --selftest-os` too (the objective-spot self test must still pass). Do not run `--fetch` (Wowhead).

- [ ] **Step 5: Run the harness**

Expected: the data case `ok`; the memory line "kept after login" still under 11264 KB (the new tables are about 40 KB).

- [ ] **Step 6: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/cmangos.py tools/questbank/gen_data.py tools/questbank/QuestBank/Data.lua tools/questbank/harness.lua && git commit -q -m "data(questbank): class trainers from the Classic spawns (D.TRAINER) and each class's learn levels (D.SPELL_LV)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 8: The train step

**Files:**
- Modify: `tools/questbank/QuestBank/Guide.lua` (`G.Trainer`, `G.TrainStep`, `TRAINER_SHOW` handling)
- Modify: `tools/questbank/QuestBank/Core.lua` (register `TRAINER_SHOW` on the event frame; it already forwards to the Guide)
- Modify: `tools/questbank/QuestBank/Discover.lua` (nothing: the Guide writes `QuestBankDB.disc.trainer` through `Disc.DB()` and `Disc.Key`)
- Test: `harness.lua` `G6CASES`

**Interfaces:**
- Produces: `G.Trainer(me, stop)` -> `{ name, c, wx, wy, m, x, y }` or nil (the nearest trainer of the player's class within `G.TRAIN_MIN = 3` minutes of the stop); `G.NeedsTraining(level)` -> true when the level is in `D.SPELL_LV[class]` and `laterDB().trained < level`; `G.reminder` (a `GetTime()` deadline while "New spells at your class trainer" shows); `QuestBankDB.disc.trainer[key] = { n, cl, m, x, y }`.
- Consumes: `D.TRAINER`, `D.SPELL_LV`, `QB.Model.Between(a, b, fac, mf)` (Model.lua:156: minutes between two places `{c, wx, wy}`; `mf = M.Factor(QB:Mounted())`), `QB.Discover.DB()`, `QB.Discover.Key(guid)`, `IsTradeskillTrainer()`, `GetNumTrainerServices()`, `GetTrainerServiceInfo(i)` (Mainline order: name, serviceType, texture, reqLevel).

- [ ] **Step 1: Write the failing case**

```lua
  -- a level-10 human warrior in Northshire (10 is a warrior learn level) with a hand-in in Goldshire: "Train at
  -- Lyria Du Lac" (Goldshire's warrior trainer) comes before the Goldshire hand-in; the window read with nothing
  -- left to learn completes it; no trainer known near the route gives a reminder line, not a step; TRAINER_SHOW at
  -- an unknown trainer learns it
  G6CASES[#G6CASES + 1] = { "the train step before the next town hand-in; a trainer learned in play", function()
    local c = human("Trainee", { { 62, 1 } }, {}, nil, 10) -- The Fargodeep Mine, handed in to Marshal Dughan in Goldshire
    local QB, G, D = c.QB, c.QB.Guide, c.QB.Data
    QB:Settings().guide.on = true
    assert(G.NeedsTraining(10), "level 10 is a warrior learn level and nothing trained yet")
    settle(c)
    local train, handin
    for i, s in ipairs(G.steps) do
      if s.kind == "train" then train = i end
      if s.kind == "handin" and s.qid == 62 and not handin then handin = i end
    end
    assert(train and handin and train < handin, "Train before the Goldshire hand-in: " .. tostring(train) .. " / " .. tostring(handin))
    assert(G.Text(G.steps[train]) == "Train at Lyria Du Lac", G.Text(G.steps[train]))
    -- the window: everything learned
    c.env.IsTradeskillTrainer = function() return false end
    c.env.GetNumTrainerServices = function() return 1 end
    c.env.GetTrainerServiceInfo = function() return "Heroic Strike", "used", 0, 10 end
    c.env.UnitName = function(u) if u == "npc" then return "Lyria Du Lac" end return c.o.name end
    c.npcGUID = "Creature-0-4455-0-12-914-0000A1B2C3"
    c.ev(QB.eventFrame, "TRAINER_SHOW")
    settle(c)
    for _, s in ipairs(G.steps) do assert(s.kind ~= "train", "trained: no train step") end
    assert(G.DB().trained == 10, "noted as trained at 10")
    -- a class with no known trainer near the route: a reminder, no step
    local keep = D.TRAINER
    D.TRAINER = {}
    G.DB().trained = 0
    settle(c)
    for _, s in ipairs(G.steps) do assert(s.kind ~= "train", "no trainer known: no step") end
    assert(G.reminder and G.reminder > c.clock, "a reminder line instead")
    -- learned in play: the window at an unknown trainer notes it, and the step is back
    c.npcGUID = "Creature-0-4455-0-12-999999-0000A1B2C3"
    c.env.GetTrainerServiceInfo = function() return "Rend", "available", 0, 10 end
    c.ev(QB.eventFrame, "TRAINER_SHOW")
    local t = QB.Discover.DB().trainer and QB.Discover.DB().trainer["c999999"]
    assert(t and t.n == "Lyria Du Lac" and t.cl == 1 and t.m == 1429, "the trainer learned: name, class, place")
    settle(c)
    local back = false
    for _, s in ipairs(G.steps) do if s.kind == "train" then back = true end end
    assert(back, "a learned trainer gives the step")
    D.TRAINER = keep
  end }
```

- [ ] **Step 2: Run the harness to see it fail**

Expected: `attempt to call field 'NeedsTraining' (a nil value)`.

- [ ] **Step 3: Write the trainer logic**

Guide.lua:

```lua
local TRAIN_MIN, REMIND_S = 3, 180
G.TRAIN_MIN = TRAIN_MIN

local function classID()
  local ok, _, tok, id = pcall(UnitClass, "player")
  return ok and plain(id) or nil, ok and plain(tok) or nil
end

-- this level teaches something (D.SPELL_LV) and it has not been trained yet
function G.NeedsTraining(level)
  local _, tok = classID()
  local levels = tok and QB.Data.SPELL_LV and QB.Data.SPELL_LV[tok]
  if not levels then return false end
  if (laterDB().trained or 0) >= level then return false end
  for _, l in ipairs(levels) do if l == level then return true end end
  return false
end

-- the trainers of your class: the seed's rows and those learned in play, as places
local trainerBuf = {}
local function trainers()
  local id = classID()
  for k = #trainerBuf, 1, -1 do trainerBuf[k] = nil end
  for _, t in ipairs(QB.Data.TRAINER or {}) do
    if t[3] == id then trainerBuf[#trainerBuf + 1] = { name = t[2], c = t[4], wx = t[5], wy = t[6], m = t[7], x = t[8], y = t[9] } end
  end
  local disc = QB.Discover and QB.Discover.DB and QB.Discover.DB()
  for _, t in pairs(disc and disc.trainer or {}) do
    if t.cl == id and t.m then
      local w = QB.Model.World(t.m, t.x, t.y, wbuf)
      if w then trainerBuf[#trainerBuf + 1] = { name = t.n, c = w.c, wx = w.wx, wy = w.wy, m = t.m, x = t.x, y = t.y } end
    end
  end
  return trainerBuf
end

-- the nearest trainer of your class within TRAIN_MIN minutes of a stop
function G.Trainer(stop)
  if not (stop and stop.c) then return nil end
  local M = QB.Model
  local mf = M.Factor(QB:Mounted())
  local best, bm
  for _, t in ipairs(trainers()) do
    if t.c == stop.c then
      local m = M.Between(stop, t, QB.faction, mf)
      if m and m <= TRAIN_MIN and (not bm or m < bm) then best, bm = t, m end
    end
  end
  return best
end
```

(The `trainers()` list makes small tables once per Replan; keep the count low by caching on `QB.Data.TRAINER` and the `disc.trainer` count: `if trainerFor == QB.Data.TRAINER and trainerN == n then return trainerBuf end`. Write that cache; the memory block measures a re-plan.)

In `G.Replan`, after the hand-in steps are built and before the travel step:

```lua
  if G.NeedsTraining(QB.state.level or 1) then
    local placed = false
    for i, s in ipairs(G.steps) do
      if s.kind == "handin" and not s.near then
        local stop
        for _, leg in ipairs(legs) do if leg.stop and leg.stop.seen and leg.stop.seen[s.npc] then stop = leg.stop break end end
        local t = stop and stop.town and G.Trainer(stop)
        if t then
          local ts = step("train")
          ts.name, ts.c, ts.wx, ts.wy, ts.m, ts.x, ts.y = t.name, t.c, t.wx, t.wy, t.m, t.x, t.y
          table.insert(G.steps, i, ts)
          placed = true
          break
        end
      end
    end
    if not placed then G.reminder = (GetTime and GetTime() or 0) + REMIND_S else G.reminder = nil end
  else
    G.reminder = nil
  end
```

`G.OnEvent` adds:

```lua
  if event == "TRAINER_SHOW" then
    if type(IsTradeskillTrainer) == "function" then
      local ok, trade = pcall(IsTradeskillTrainer)
      if ok and plain(trade) == true then return end
    end
    -- the trainer, learned (its class is yours: a class trainer's window opens for its class alone)
    local okG, guid = pcall(UnitGUID, "npc")
    local key = okG and QB.Discover and QB.Discover.Key(guid)
    local okN, name = pcall(UnitName, "npc")
    name = okN and plain(name) or nil
    local id = classID()
    local disc = key and name and id and QB.Discover.DB()
    if disc then
      disc.trainer = disc.trainer or {}
      local m = QB.API.MapID()
      local pos = m and C_Map and C_Map.GetPlayerMapPosition and select(2, pcall(C_Map.GetPlayerMapPosition, m, "player"))
      local x, y = pos and plain(pos.x), pos and plain(pos.y)
      if type(x) == "number" and type(y) == "number" then disc.trainer[key] = { n = name, cl = id, m = m, x = x * 100, y = y * 100 } end
    end
    -- nothing left to learn: this level is trained
    local okS, n = pcall(GetNumTrainerServices)
    n = okS and plain(n) or 0
    local avail = 0
    for i = 1, (type(n) == "number" and n or 0) do
      local okI, _, kind = pcall(GetTrainerServiceInfo, i)
      if okI and plain(kind) == "available" then avail = avail + 1 end
    end
    if avail == 0 then laterDB().trained = QB.state.level or 1 end
    QB:MarkDirty()
    return
  end
```

Core.lua: add `"TRAINER_SHOW"` to the event list (line 2776); in the handler, `return` after forwarding for it. The harness's `C_Map.GetPlayerMapPosition` mock exists (newClient, used by `API.WorldPosition`); check it returns a table with `x, y` for the Northshire client; if it needs `"player"` as a second argument it ignores it.

- [ ] **Step 4: Run the harness**

Expected: the train case `ok`. If "Train at Lyria Du Lac" fails on the name, read the row with `grep -n '"Lyria Du Lac"' tools/questbank/QuestBank/Data.lua` and check `D.TRAINER` carries class 1 for her; if Goldshire's stop has no `town` in this client's route (`stop.town` is the hub index only in a hub town), relax the condition to `stop.town or stop.hub > 0` in the insertion loop and the decisions table above.

- [ ] **Step 5: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/QuestBank/Guide.lua tools/questbank/QuestBank/Core.lua tools/questbank/harness.lua && git commit -q -m "feat(questbank): Train at your class trainer before the next town hand-in; trainers learned at their window" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 9: Time to level

**Files:**
- Modify: `tools/questbank/QuestBank/Guide.lua` (`G.TimeToLevel`)
- Test: `harness.lua` `G6CASES`

**Interfaces:**
- Produces: `G.TimeToLevel()` -> `text, minutes, measured` where text is "about 14 min to level 6" / "under a minute to level 6" / "about 2 h 10 min to level 23" / nil at the cap; `measured` true once `Timer.XPPerHour()` exists.
- Consumes: `QB.routePlan.t` and `.xp` (Model.lua route: minutes and XP of the planned route), `QB.Data.TO_NEXT[level]`, `QB.state.xp`, `QB.Timer.XPPerHour()` (nil for the first ten minutes), `QB.Timer.SessionXP()`.

- [ ] **Step 1: Write the failing case**

```lua
  G6CASES[#G6CASES + 1] = { "time to level: from the plan, then from the XP an hour", function()
    local c = human("Clock", { { 7, 0 }, { 15, 0 }, { 18, 0 } }, { [783] = true }, nil, 5)
    local QB, G, Timer = c.QB, c.QB.Guide, c.QB.Timer
    QB:Settings().guide.on = true
    c.o.xp = 200
    settle(c)
    local text, mins, measured = G.TimeToLevel()
    assert(text and text:find(" to level 6$") and mins and mins > 0 and not measured, "from the plan: " .. tostring(text))
    assert(text:match("^about %d+ min") or text:match("^under a minute") or text:match("^about %d+ h"), "the words: " .. text)
    -- ten minutes of play with 600 XP gained: 3,600 an hour; 700 to go at level 5 (900 - 200): about 12 min
    local x = 200
    c.env.UnitXP = function() return x end
    c.env.UnitXPMax = function() return 900 end
    Timer.NoteXP()
    for _ = 1, 10 do c.clock = c.clock + 60; x = x + 60; Timer.NoteXP() end
    c.o.xp = x
    c.QB:ReadState()
    local t2, m2, meas2 = G.TimeToLevel()
    assert(meas2 and m2 and math.abs(m2 - (900 - x) / 3600 * 60) < 0.5 and t2:find("^about %d+ min to level 6"), "measured: " .. tostring(t2) .. " " .. tostring(m2))
    -- at the cap: nothing
    c.o.level = 60; c.QB.state.level = 60
    assert(G.TimeToLevel() == nil, "nothing at 60")
    c.o.level = 5
  end }
```

- [ ] **Step 2: Run the harness to see it fail**

Expected: `attempt to call field 'TimeToLevel' (a nil value)`.

- [ ] **Step 3: Write `G.TimeToLevel`**

```lua
-- "about 14 min to level 6": the XP still needed over the plan's XP a minute until ten minutes of play have been
-- measured (Timer.XPPerHour), then over the measured rate; nil at the cap or with nothing to go on
local function spanText(mins)
  if mins < 1 then return "under a minute" end
  if mins < 90 then return string.format("about %d min", math.floor(mins + 0.5)) end
  local h = math.floor(mins / 60)
  local m = math.floor((mins - h * 60) / 10 + 0.5) * 10
  if m == 60 then h, m = h + 1, 0 end
  return m > 0 and string.format("about %d h %d min", h, m) or string.format("about %d h", h)
end
G.SpanText = spanText
function G.TimeToLevel()
  local s = QB.state
  local level = s.level or 1
  if level >= QB.MAXLEVEL or level >= (QB.CAP or QB.MAXLEVEL) then return nil end
  local need = (QB.Data.TO_NEXT[level] or 0) - (s.xp or 0)
  if need <= 0 then return nil end
  local rate = QB.Timer and QB.Timer.XPPerHour and QB.Timer.XPPerHour()
  local mins, measured
  if rate and rate > 0 then
    mins, measured = need / rate * 60, true
  else
    local r = QB.routePlan
    if not (r and r.xp and r.xp > 0 and r.t and r.t > 0) then return nil end
    -- the plan's XP a minute, with a minute a quest of doing (the planner counts travel and hand-ins, not the kills)
    local perMin = r.xp / (r.t + (r.count or 0) * 1)
    mins, measured = need / perMin, false
  end
  return spanText(mins) .. " to level " .. (level + 1), mins, measured
end
```

- [ ] **Step 4: Run the harness**

Expected: the case `ok`.

- [ ] **Step 5: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/QuestBank/Guide.lua tools/questbank/harness.lua && git commit -q -m "feat(questbank): time to level from the plan, then from the measured XP an hour" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 10: Party awareness: shared quests first, each member's step

**Files:**
- Modify: `tools/questbank/QuestBank/Sync.lua` (the `1G` message: send on a step change, receive into `m.step`)
- Modify: `tools/questbank/QuestBank/Guide.lua` (`G.MemberSteps()`, the party weight in `G.Rank` is done in Task 3)
- Test: `harness.lua` `G6CASES`

**Interfaces:**
- Produces: `S:Step(text)` queues `1G|text` (text cut to 120 bytes, `|` removed) to the group channel at most once every `STEP_GAP = 10` s and only when the text changed; `m.step` on each member; `G.MemberSteps()` -> list of `{ name, class, text }` for members with a step, sorted by name (one list reused).
- Consumes: Sync.lua's `queue(msg, channel, target)`, `groupChannel()`, `S:Receive` (`kind == "1G"` branch), `S:Members()`.

- [ ] **Step 1: Write the failing case**

```lua
  -- a party of two: Rone holds Kobold Camp Cleanup, Brann holds it too and Investigate Echo Ridge; the fill prefers
  -- what the party holds, and each sees the other's step
  G6CASES[#G6CASES + 1] = { "a party of two: shared quests first, each member's step shown", function()
    local a = newClient({ name = "Rone", level = 3, cap = 60, faction = "Alliance", className = "Warrior", class = "WARRIOR", classID = 1, race = "Human",
      log = { { 7, 0 } }, done = { [783] = true }, group = true, world = { 0, -8914, -133 }, map = 1429, bagSlots = {}, bind = "Goldshire" })
    local b = newClient({ name = "Brann", level = 3, cap = 60, faction = "Alliance", className = "Paladin", class = "PALADIN", classID = 2, race = "Human",
      log = { { 7, 0 }, { 15, 0 } }, done = { [783] = true }, group = true, world = { 0, -8914, -133 }, map = 1429, bagSlots = {}, bind = "Goldshire" })
    login(a); login(b)
    a.objectives = { [7] = { { text = "Kobold Vermin slain: 1/8", type = "monster", finished = false, numFulfilled = 1, numRequired = 8 } } }
    b.objectives = { [7] = { { text = "Kobold Vermin slain: 4/8", type = "monster", finished = false, numFulfilled = 4, numRequired = 8 } },
                     [15] = { { text = "Investigate Echo Ridge: 0/1", type = "event", finished = false, numFulfilled = 0, numRequired = 1 } } }
    for _, c in ipairs({ a, b }) do c.QB:Settings().guide.on = true end
    settle(a); settle(b)
    a.QB.Sync:Broadcast(true); b.QB.Sync:Broadcast(true)
    for _ = 1, 3 do tick(a, 2); tick(b, 2); deliver() end
    settle(a); settle(b)
    for _ = 1, 3 do tick(a, 2); tick(b, 2); deliver() end
    -- the fill: Rone's plan holds Investigate Echo Ridge (Brann has it) ahead of other picks of the same worth
    assert(a.QB:Plan().auto[15] or a.QB:Plan().add[15], "Rone's plan takes the quest Brann holds")
    -- each other's step
    local ms = a.QB.Guide.MemberSteps()
    assert(#ms == 1 and ms[1].name == "Brann" and ms[1].text == b.QB.Guide.Text(b.QB.Guide.steps[1]), "Rone sees Brann's step: " .. tostring(ms[1] and ms[1].text))
    local mb = b.QB.Guide.MemberSteps()
    assert(#mb == 1 and mb[1].name == "Rone", "Brann sees Rone's")
    -- the message sent is the first step's text (one line, under 255 bytes, no escape codes: the harness's
    -- SendAddonMessage mock checks the channel)
    assert(a.QB.Sync.lastStep and a.QB.Sync.lastStep == a.QB.Guide.Text(a.QB.Guide.steps[1]), "the step text sent is the first step's")
  end }
```

- [ ] **Step 2: Run the harness to see it fail**

Expected: `attempt to call field 'MemberSteps' (a nil value)`.

- [ ] **Step 3: Sync and Guide**

Sync.lua, with the other message functions:

```lua
-- 1G|text: your Guide's first step, for the others' step frames (6.0). Sent when it changes, at most once every
-- STEP_GAP seconds, cut to STEP_LEN bytes, no escape codes (Guide.lua's texts are plain)
local STEP_GAP, STEP_LEN = 10, 120
function S:Step(text)
  if not self.ready or type(text) ~= "string" then return end
  text = text:gsub("|", ""):sub(1, STEP_LEN)
  if text == self.lastStep then return end
  local t = now()
  if self.stepAt and t - self.stepAt < STEP_GAP then
    if not self.stepSoon then
      self.stepSoon = true
      C_Timer.After(STEP_GAP, QB.Safe(function() self.stepSoon = false; self:Step(QB.Guide and QB.Guide.Text(QB.Guide.Current()) or "") end, "party sync: step"))
    end
    return
  end
  local chan = groupChannel()
  if not chan or not QB:Settings().share.party then return end
  self.lastStep, self.stepAt = text, t
  queue("1G|" .. text, chan)
end
```

In `S:Receive`, before `elseif kind == "1L"`:

```lua
  elseif kind == "1G" then
    local text = msg:match("^1G|(.*)$")
    m.step = (text and text ~= "") and text:sub(1, STEP_LEN) or nil
    if QB.StepFrame and QB.StepFrame.Refresh then QB.StepFrame.Refresh() end
```

In `S:Changed()` (called from `QB:Changed`), add `if QB.Guide and QB.Guide.Current then self:Step(QB.Guide.Text(QB.Guide.Current())) end`. Check `S.ready` is set in `S:Init` (Sync.lua:507) and that `self.ready` is what `Broadcast` tests.

Guide.lua:

```lua
-- the party's steps (Sync's 1G), by name
local memberSteps = {}
function G.MemberSteps()
  for k = #memberSteps, 1, -1 do memberSteps[k] = nil end
  local S = QB.Sync
  if not (S and S.Members and IsInGroup and IsInGroup()) then return memberSteps end
  for _, m in ipairs(S:Members()) do
    if m.step then memberSteps[#memberSteps + 1] = { name = m.name or m.key, class = m.class, text = m.step } end
  end
  table.sort(memberSteps, function(x, y) return x.name < y.name end)
  return memberSteps
end
```

(`S:Members()` makes a list each call; the frame calls `G.MemberSteps` only on refresh, not per tick.)

- [ ] **Step 4: Run the harness**

Expected: the party case `ok`; scenario 2 (the friend's sync) unchanged.

- [ ] **Step 5: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/QuestBank/Sync.lua tools/questbank/QuestBank/Guide.lua tools/questbank/harness.lua && git commit -q -m "feat(questbank): the Guide prefers the party's quests and shares each member's step" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 11: StepFrame.lua: the frame

**Files:**
- Create: `tools/questbank/QuestBank/StepFrame.lua`
- Modify: `tools/questbank/QuestBank/QuestBank.toc` (`StepFrame.lua` after `UI.lua`)
- Modify: `tools/questbank/QuestBank/Core.lua` (init order: `if QB.StepFrame then QB.StepFrame:Init() end` after `QB.Target:Init()`; `/qb guide` toggles `guide.on`, `/qb step` toggles the frame)
- Modify: `tools/questbank/QuestBank/UI.lua` (`UI.scrollToQuest` honoured by `RefreshLogView`)
- Modify: `tools/questbank/harness.lua` (the layout dump adds the step frame: a `layouts["step-frame"]` sheet at scales 0.8, 1, 1.2 in the owner's layout pass)
- Test: `harness.lua` `G6CASES`

**Interfaces:**
- Produces: `QB.StepFrame` (`SF`): `SF:Init()`, `SF.Apply()` (shown per `guide.frame` and `guide.on`, or a pending welcome), `SF.Refresh()` (cheap: redraws when `G.ver` or the time line changed), `SF:Menu()`, `SF.SetScale(s)`, `SF.frame` named `QuestBankStep` with `.now` (FontString), `.next1`, `.next2`, `.time`, `.remind`, `.members[i]`, `.item` (Task 12), `.card` (Task 13).
- Consumes: `G.Steps()`, `G.Text(s)`, `G.TimeToLevel()`, `G.reminder`, `G.MemberSteps()`, `G.Skip(id, how)`, `UI:ShowMenu(title, items)` (UI.lua:651, items `{ label, fn }`), `UI.Short(name, n)` (UI.lua:908), `UI:Open(tab)`, `QB.Sync.ColorName(name, class, dark)`.

- [ ] **Step 1: Write the failing case**

```lua
  G6CASES[#G6CASES + 1] = { "the step frame: one line now, two greyed, the time line, click and right-click", function()
    local c = human("Framer", { { 7, 0 } }, { [783] = true }, nil, 5)
    local QB, G, SF, UI = c.QB, c.QB.Guide, c.QB.StepFrame, c.QB.UI
    c.objectives = { [7] = { { text = "Kobold Vermin slain: 3/8", type = "monster", finished = false, numFulfilled = 3, numRequired = 8 } } }
    QB:Settings().guide.on = true; QB:Settings().welcome = nil
    QB:SetAdded(15, true); QB:SetAdded(18, true)
    settle(c)
    SF.Apply(); SF.Refresh()
    local f = c.env.QuestBankStep
    assert(f and f:IsShown(), "the frame is up")
    assert(f.now:GetText() == G.Text(G.steps[1]) and f.next1:GetText() == G.Text(G.steps[2]) and f.next2:GetText() == G.Text(G.steps[3]), "the three lines: " .. tostring(f.now:GetText()))
    local r, g, b = f.next1:GetTextColor()
    assert(r < 0.8 and g < 0.8, "the next steps greyed")
    assert(f.time:GetText():find(" to level 6$"), "the time line: " .. tostring(f.time:GetText()))
    -- a click: the window on the Quest Log
    f.rows[1].__scripts.OnClick(f.rows[1], "LeftButton")
    assert(UI.frame and UI.frame:IsShown() and UI.tab == 1, "a click opens the Quest Log")
    UI.frame:Hide()
    -- the right-click menu: Not now, Drop, Lock, scales, Hide, Settings
    f.rows[1].__scripts.OnClick(f.rows[1], "RightButton")
    local labels = {}
    for _, it in ipairs(UI.lastMenu or {}) do labels[#labels + 1] = it[1] end
    local joined = table.concat(labels, " | ")
    assert(joined:find("Not now", 1, true) and joined:find("Drop ", 1, true) and joined:find("Lock", 1, true) and joined:find("Scale: 80%", 1, true)
      and joined:find("Hide", 1, true) and joined:find("Settings", 1, true), "the menu: " .. joined)
    -- Not now from the menu puts the first step's quest off
    for _, it in ipairs(UI.lastMenu) do if it[1] == "Not now" then it[2]() end end
    settle(c); SF.Refresh()
    assert(G.PutOff(7), "Not now put the quest off")
    -- scale and lock are kept
    SF.SetScale(1.2)
    assert(QB:Settings().guide.scale == 1.2 and math.abs(f:GetScale() - 1.2) < 0.001, "scale kept")
    QB:Settings().guide.locked = true; SF.Apply()
    assert(not f.__movable or f.__dragOff, "locked: no drag")
    -- off: hidden
    QB:Settings().guide.frame = false; SF.Apply()
    assert(not f:IsShown(), "hidden by the setting")
    QB:Settings().guide.frame = true; QB:Settings().guide.locked = false; SF.SetScale(1); SF.Apply()
    -- the layout: nothing clipped at any scale
    for _, sc in ipairs({ 0.8, 1, 1.2 }) do
      SF.SetScale(sc); SF.Refresh()
      checkLayout(f, "step frame at " .. sc)
    end
    SF.SetScale(1)
    assert(#c.chat == 0 or not c.chat[#c.chat]:find("step", 1, true), "nothing said in chat")
  end }
```

`UI.lastMenu`: `UI:ShowMenu` must keep its `items` in `UI.lastMenu` (one assignment; read UI.lua:651 and add `UI.lastMenu = items` as its first line). `checkLayout(root, label)` is the harness's own (line 1396); it appends to `problems`, which fail the run at the end.

- [ ] **Step 2: Run the harness to see it fail**

Expected: `attempt to index field 'StepFrame' (a nil value)`.

- [ ] **Step 3: Write StepFrame.lua**

```lua
-- SPDX-License-Identifier: GPL-3.0-or-later
-- The step frame (6.0): the Guide's current step in one line, the next two greyed beneath, a quest-item button when the
-- step needs one, and "about 14 min to level 6". Small, movable (Alt-drag or a drag; locked in Settings or its menu),
-- in the window's slate. A click on a step opens it in the window; a right-click is its menu: Not now (an hour), Drop
-- (for good), Lock, Scale, Hide, Settings. The welcome (a fresh install) and the 5.x question are cards in the same
-- frame (SF.Ask). Redrawn when the Guide's version or the time line changed, 2 times a second at most; nothing is made
-- per tick. Secure parts (the item button) change only out of a fight.
local _, QB = ...
local SF = {}
QB.StepFrame = SF

local G = QB.Guide
local WIDTH, PAD, ROW = 260, 8, 18
local SLATE = { 0.055, 0.07, 0.095 }
local INK, INK_SOFT, GOLD = { 0.95, 0.93, 0.88 }, { 0.62, 0.62, 0.6 }, { 1, 0.82, 0.3 }
local TICK = 0.5
local SCALES = { 0.8, 1, 1.2 }
SF.SCALES = SCALES

local function settings() return QB:Settings().guide end
local function fighting() return InCombatLockdown and InCombatLockdown() or false end

local function fs(parent, size, color, width)
  local t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetFont(t:GetFont(), size)
  t:SetTextColor(color[1], color[2], color[3])
  t:SetJustifyH("LEFT")
  t:SetWordWrap(false)
  t:SetWidth(width)
  return t
end

local function build()
  local f = CreateFrame("Frame", "QuestBankStep", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(WIDTH, PAD * 2 + ROW * 4)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(SLATE[1], SLATE[2], SLATE[3], 0.92)
    f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.5)
  end
  f:SetScript("OnDragStart", function(self) if not settings().locked then self:StartMoving() end end)
  f:SetScript("OnDragStop", QB.Safe(function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint(1)
    settings().x, settings().y = x, y
  end, "step frame"))
  -- three rows: the step now, the two next; each a button for its click and menu
  f.rows = {}
  for i = 1, 3 do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(WIDTH - PAD * 2, ROW)
    b:SetPoint("TOPLEFT", PAD, -PAD - (i - 1) * ROW)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.text = fs(b, i == 1 and 12 or 11, i == 1 and INK or INK_SOFT, WIDTH - PAD * 2 - (i == 1 and 30 or 0))
    b.text:SetPoint("LEFT", 0, 0)
    b.i = i
    b:SetScript("OnClick", QB.Safe(function(self, button)
      local s = G.Steps()[self.i]
      if button == "RightButton" then SF:Menu(s) return end
      if not s then return end
      if s.kind == "travel" then QB.UI:Open(3)
      elseif s.qid then QB.UI.scrollToQuest = s.qid; QB.UI:Open(1)
      else QB.UI:Open(6) end
    end, "step frame"))
    f.rows[i] = b
  end
  f.now, f.next1, f.next2 = f.rows[1].text, f.rows[2].text, f.rows[3].text
  f.time = fs(f, 10, INK_SOFT, WIDTH - PAD * 2)
  f.time:SetPoint("TOPLEFT", PAD, -PAD - ROW * 3)
  f.remind = fs(f, 10, GOLD, WIDTH - PAD * 2)
  f.remind:SetPoint("TOPLEFT", PAD, -PAD - ROW * 4)
  f.remind:Hide()
  f.members = {}
  f.elapsed = 0
  f:SetScript("OnUpdate", QB.Safe(function(self, dt)
    self.elapsed = self.elapsed + (dt or 0)
    if self.elapsed < TICK then return end
    self.elapsed = 0
    SF.Refresh()
  end, "step frame"))
  f:Hide()
  return f
end

local function place(f)
  local s = settings()
  f:ClearAllPoints()
  if s.x and s.y then f:SetPoint("CENTER", UIParent, "CENTER", s.x, s.y) else f:SetPoint("TOP", UIParent, "TOP", 0, -140) end
  f:SetScale(s.scale or 1)
end

local lastVer, lastTime, lastRemind, lastMembers = -1, nil, false, ""
-- the lines, when something changed
function SF.Refresh()
  local f = SF.frame
  if not (f and f:IsShown()) then return end
  if f.card and f.card:IsShown() then return end
  local steps = G.Steps()
  local text, mins = G.TimeToLevel()
  local remind = G.reminder and GetTime and GetTime() < G.reminder
  local members = G.MemberSteps()
  local mkey = ""
  for i, m in ipairs(members) do mkey = mkey .. m.name .. "=" .. m.text .. ";" end
  if G.ver == lastVer and text == lastTime and remind == lastRemind and mkey == lastMembers then return end
  lastVer, lastTime, lastRemind, lastMembers = G.ver, text, remind, mkey
  for i = 1, 3 do
    local s = steps[i]
    f.rows[i].text:SetText(s and G.Text(s) or (i == 1 and "Nothing to do: open /qb" or ""))
    f.rows[i]:SetShown(i == 1 or s ~= nil)
  end
  f.time:SetText(text or "")
  f.remind:SetText(remind and "New spells at your class trainer" or "")
  f.remind:SetShown(remind and true or false)
  local y = PAD + ROW * 3 + (text and ROW or 0) + (remind and ROW or 0)
  for i, m in ipairs(members) do
    local t = f.members[i]
    if not t then t = fs(f, 10, INK_SOFT, WIDTH - PAD * 2); f.members[i] = t end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", PAD, -y)
    t:SetText((QB.Sync and QB.Sync.ColorName and QB.Sync.ColorName(m.name, m.class) or m.name) .. ": " .. m.text)
    t:Show()
    y = y + ROW
  end
  for i = #members + 1, #f.members do f.members[i]:Hide() end
  f:SetHeight(y + PAD)
  if SF.RefreshItem then SF.RefreshItem(steps[1]) end
end

-- shown while the Guide and the frame are on, or a welcome waits (Task 13)
function SF.Apply()
  local s = settings()
  local want = (s.on and s.frame) or QB:Settings().welcome ~= nil
  if want and not SF.frame then SF.frame = build() end
  local f = SF.frame
  if not f then return end
  place(f)
  f.__dragOff = s.locked and true or nil -- (the drag script checks the setting; the harness reads this flag)
  f:SetShown(want and true or false)
  lastVer = -1
  if want then SF.Refresh() end
  if SF.AskPending then SF.AskPending() end
end

function SF.SetScale(sc)
  settings().scale = sc
  if SF.frame then SF.frame:SetScale(sc) end
end

function SF:Menu(s)
  if not QB.UI then return end
  local items = {}
  local set = settings()
  if s and s.qid then
    local q = QB.Quest.Get(s.qid)
    local name = q and QB.UI.Short(q.name, 24) or ("quest " .. s.qid)
    items[#items + 1] = { "Not now", function() G.Skip(s.qid, "later") end }
    items[#items + 1] = { "Drop " .. name, function() G.Skip(s.qid, "drop") end }
  end
  items[#items + 1] = { set.locked and "Unlock" or "Lock", function() set.locked = not set.locked; SF.Apply() end }
  for _, sc in ipairs(SCALES) do
    items[#items + 1] = { string.format("Scale: %d%%%s", sc * 100, (set.scale or 1) == sc and "  (now)" or ""), function() SF.SetScale(sc) end }
  end
  items[#items + 1] = { "Hide (Settings brings it back)", function() set.frame = false; SF.Apply() end }
  items[#items + 1] = { "Settings", function() QB.UI:Open(5) end }
  QB.UI:ShowMenu("The next step", items)
end

function SF:Init()
  SF.Apply()
end
```

Core.lua: in the `PLAYER_LOGIN` branch after `QB.Target:Init()`: `if QB.StepFrame then QB.StepFrame:Init() end`; in `QB:Changed()` after the Guide's Replan: `if QB.StepFrame and QB.StepFrame.frame then QB.Try("step frame", QB.StepFrame.Refresh) end`. Slash: before the final `else`:

```lua
  elseif cmd == "guide" then
    local s = QB:Settings().guide
    s.on = not s.on
    QB:MarkDirty()
    if QB.StepFrame then QB.StepFrame.Apply() end
    QB:Print(s.on and "QuestBank is guiding you: the step frame and the arrow lead; /qb guide turns it off." or "The Guide is off. /qb guide turns it on; the window and its pages work as before.")
  elseif cmd == "step" then
    local s = QB:Settings().guide
    s.frame = not s.frame
    if QB.StepFrame then QB.StepFrame.Apply() end
```

(`/qb guide` is the player asking: one line is allowed.) UI.lua: in `RefreshLogView` (UI.lua:2228), when `UI.scrollToQuest` is set, after the rows are laid out, scroll `v.scroll` so that quest's row is in view and clear the field; read how the Quest Log page scrolls (`v.scroll:SetVerticalScroll`) and the rows' `row.q.id`.

Harness layout sheet: in the owner's layout pass (where `layouts[...]` sheets are collected; grep `layouts%[` in harness.lua), add after the window's pages:

```lua
  if QB.StepFrame then
    QB:Settings().guide.on, QB:Settings().guide.frame, QB:Settings().welcome = true, true, nil
    QB.Guide.Replan(); QB.StepFrame.Apply(); QB.StepFrame.Refresh()
    for _, sc in ipairs({ 0.8, 1, 1.2 }) do
      QB.StepFrame.SetScale(sc); QB.StepFrame.Refresh()
      checkLayout(env.QuestBankStep, "step frame " .. sc)
      layouts["step-frame-" .. sc] = dumpLayout(env.QuestBankStep, "step frame " .. sc)
    end
    QB.StepFrame.SetScale(1)
  end
```

(`dumpLayout(root, label)` is at harness.lua:1503; match the shape the other sheets use where `layouts` is filled.) Then `luajit harness.lua --layout /private/tmp/claude-501/-Users-mikalbot-DAN-WOW-ADDON/2fab406c-8e90-498a-b6fc-190b5b8d2501/scratchpad/layout.json` and `python3 -I tools/questbank/render_layout.py <that>/layout.json <that>/layout.html step-frame-1` draws the sheet to look at; the gate itself stays `luajit harness.lua`.

- [ ] **Step 4: Run the harness**

Expected: the frame case `ok`, `layout problems: 0`. A clipped line means `WIDTH - PAD * 2` is too narrow for a long quest name: `A.Fit`'s approach (Arrow.lua:230) shortens with `UI.Short`; use `QB.UI.Short(G.Text(s), 40)` for the rows if the check reports clipping.

- [ ] **Step 5: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/QuestBank/StepFrame.lua tools/questbank/QuestBank/QuestBank.toc tools/questbank/QuestBank/Core.lua tools/questbank/QuestBank/UI.lua tools/questbank/harness.lua && git commit -q -m "feat(questbank): the step frame: the step now, two next, the time to level, its menu" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 12: The quest-item button and the reward mark

**Files:**
- Modify: `tools/questbank/QuestBank/StepFrame.lua` (`SF.RefreshItem`, `SF.MarkReward`)
- Modify: `tools/questbank/QuestBank/Guide.lua` (`G.ItemFor(step)`, `G.reward`, `QUEST_COMPLETE`/`QUEST_FINISHED` handling)
- Modify: `tools/questbank/QuestBank/Auto.lua:185-196` (`Auto.Complete`: several choices hand to the Guide)
- Modify: `tools/questbank/harness.lua` (mock `GetQuestLogSpecialItemInfo`, `QuestInfoFrame.rewardsFrame.RewardButtons`, `GetQuestItemLink("choice", i)`)
- Test: `harness.lua` `G6CASES`

**Interfaces:**
- Produces: `G.ItemFor(step)` -> `itemID, link, icon` or nil (the quest's special item from `GetQuestLogSpecialItemInfo(logIndex)`); `SF.frame.item` a `SecureActionButtonTemplate` button with `type = "item"`, `item = "item:<id>"`, shown only when the first step's quest has one, set only out of combat (queued on `PLAYER_REGEN_ENABLED`); `G.reward = { qid, index, name }` while the reward window with a choice is open; `SF.MarkReward()` shows `SF.mark` (a frame with `P.Glow`) over `QuestInfoFrame.rewardsFrame.RewardButtons[index]`, hidden on `QUEST_FINISHED`.
- Consumes: `GetQuestLogSpecialItemInfo(questLogIndex)` -> `link, item (texture), charges, showItemWhenComplete`; `QB.state.log[id].index`; `GetNumQuestChoices()`, `GetQuestItemLink("choice", i)`; `UI.BestReward(qid, "gear", level)` -> `itemID, ilvl` (UI.lua:1659); `QB.Pins.Glow(f, col)` (Pins.lua:453).

- [ ] **Step 1: Mocks and the failing case**

Harness, in `newClient` next to the quest window mocks (line 631-667):

```lua
  -- a quest's usable item in the log: c.questItems[questID] = { itemID, texture }
  c.questItems = {}
  env.GetQuestLogSpecialItemInfo = function(index)
    local e = c.log[index - 2]
    local it = e and c.questItems[e[1]]
    if not it then return nil end
    return "|cffffffff|Hitem:" .. it[1] .. "::::::::1:::::|h[Quest Item]|h|r", it[2], 0, false
  end
  env.GetQuestItemLink = function(kind, i)
    local list = c.window and (kind == "choice" and c.window.rc or c.window.rr)
    local id = list and list[i]
    return id and ("|cffffffff|Hitem:" .. id .. "::::::::1:::::|h[Reward]|h|r") or nil
  end
  -- the game's reward window: its choice buttons, as QuestInfo.lua lays them out
  env.QuestInfoFrame = { rewardsFrame = { RewardButtons = {} } }
  for i = 1, 4 do env.QuestInfoFrame.rewardsFrame.RewardButtons[i] = newObj("Button", nil, env.UIParent); env.QuestInfoFrame.rewardsFrame.RewardButtons[i]:SetSize(140, 40) end
```

Case:

```lua
  G6CASES[#G6CASES + 1] = { "the quest-item button out of a fight; a reward choice stops, marks, does not choose", function()
    local c = human("Itemer", { { 7, 0 } }, { [783] = true }, nil, 5)
    local QB, G, SF, Au = c.QB, c.QB.Guide, c.QB.StepFrame, c.QB.Auto
    c.objectives = { [7] = { { text = "Kobold Vermin slain: 3/8", type = "monster", finished = false, numFulfilled = 3, numRequired = 8 } } }
    c.questItems[7] = { 6948, 134414 }
    QB:Settings().guide.on = true; QB:Settings().welcome = nil
    settle(c); SF.Apply(); SF.Refresh()
    local f = c.env.QuestBankStep
    assert(f.item and f.item:IsShown() and f.item:GetAttribute("type") == "item" and f.item:GetAttribute("item") == "item:6948", "the item button set: " .. tostring(f.item and f.item:GetAttribute("item")))
    -- in a fight the button stays as it is; the change waits
    c.combat = true
    c.questItems[7] = nil
    settle(c); SF.Refresh()
    assert(f.item:IsShown() and f.item:GetAttribute("item") == "item:6948", "in a fight: nothing changes")
    c.combat = false
    c.ev(QB.eventFrame, "PLAYER_REGEN_ENABLED")
    SF.Refresh()
    assert(not f.item:IsShown(), "out of it: the button goes")
    -- a reward window with two choices: Hand in for me stops, the Gear finder's pick is marked, nothing chosen
    QB:Settings().autoTurnIn = true
    c.window = { id = 7, xp = 85, title = "Kobold Camp Cleanup", rc = { 2362, 2361 } } -- a shield and a hammer
    c.auto = {}
    c.ev(QB.eventFrame, "QUEST_COMPLETE")
    tick(c, 1)
    for _, a in ipairs(c.auto) do assert(not a:find("^GetQuestReward"), "nothing chosen: " .. a) end
    assert(G.reward and G.reward.qid == 7 and (G.reward.index == 1 or G.reward.index == 2), "the Guide holds the choice: " .. tostring(G.reward and G.reward.index))
    SF.Refresh()
    assert(f.now:GetText():find("^Choose a reward: "), "the step says so: " .. f.now:GetText())
    assert(SF.mark and SF.mark:IsShown(), "the pick is marked")
    c.ev(QB.eventFrame, "QUEST_FINISHED")
    assert(not SF.mark:IsShown() and G.reward == nil, "the window shut: the mark goes")
  end }
```

- [ ] **Step 2: Run the harness to see it fail**

Expected: `the item button set: nil`.

- [ ] **Step 3: Implement**

Guide.lua:

```lua
-- the quest's usable item, for the frame's button: id, link, texture; nil without one
function G.ItemFor(s)
  if not (s and s.qid and type(GetQuestLogSpecialItemInfo) == "function") then return nil end
  local e = QB.state.log[s.qid]
  if not (e and e.index) then return nil end
  local ok, link, tex = pcall(GetQuestLogSpecialItemInfo, e.index)
  link, tex = ok and plain(link) or nil, ok and plain(tex) or nil
  local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
  if not id then return nil end
  return id, link, tex
end

-- a hand-in with a reward to choose: the Guide holds the pick (UI.BestReward's gear, else the first trinket, else
-- the first) and the frame marks it; nothing is chosen for you
function G.HoldReward(qid, n)
  local level = QB.state.level or 1
  local best = QB.UI and QB.UI.BestReward and QB.UI.BestReward(qid, "gear", level) or (QB.UI and QB.UI.BestReward(qid, "trinket", level))
  local index, name = 1, nil
  for i = 1, n do
    local ok, link = pcall(GetQuestItemLink, "choice", i)
    link = ok and plain(link) or nil
    local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
    if id and id == best then index = i end
    if i == index and type(link) == "string" then name = link:match("%[(.-)%]") end
  end
  G.reward = { qid = qid, index = index, name = name }
  G.ver = G.ver + 1
end
function G.DropReward()
  if G.reward then G.reward = nil; G.ver = G.ver + 1 end
end
```

In `G.Replan`, before the travel step: `if G.reward then local s = step("reward"); s.qid, s.name = G.reward.qid, G.reward.name; table.insert(G.steps, 1, s) end`. In `G.OnEvent`: `if event == "QUEST_FINISHED" then G.DropReward(); return end`. Core.lua: add `"QUEST_FINISHED"` to the event list, `return` after forwarding.

Auto.lua `Auto.Complete`, the `later` body: replace `if choices <= 1 then GetQuestReward(choices) end` with

```lua
    if choices <= 1 then GetQuestReward(choices) return end
    if QB.Guide and QB.Guide.HoldReward then QB.Guide.HoldReward(id, choices) end -- several: yours to pick, the best marked
```

and make `Auto.Complete` run the hold even with `autoTurnIn` off when the Guide is on: at its top, `if byHand() or not (on("autoTurnIn") or QB:GuideOn()) then return end`, and inside `later`, `if byHand() or qid() ~= id then return end; if on("autoTurnIn") and not Auto.MayTurnIn(id) then return end; if not on("autoTurnIn") then local choices = ...; if choices > 1 then hold end; return end`. Keep the money and one-reward branches for `autoTurnIn` only.

StepFrame.lua:

```lua
-- the quest-item button: the game's secure button for the first step's item; set, shown and hidden out of a fight
-- only, else the change waits for the fight's end (SF.pendingItem)
local function itemButton(f)
  local b = CreateFrame("Button", "QuestBankStepItem", f, "SecureActionButtonTemplate")
  b:SetSize(22, 22)
  b:SetPoint("TOPRIGHT", -PAD, -PAD - 2)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b:Hide()
  return b
end
function SF.RefreshItem(s)
  local f = SF.frame
  if not f then return end
  local id, _, tex = G.ItemFor(s)
  local want = id and ("item:" .. id) or nil
  if fighting() then SF.pendingItem = true return end
  SF.pendingItem = nil
  if want and not f.item then f.item = itemButton(f) end
  local b = f.item
  if not b then return end
  if want then
    if b:GetAttribute("item") ~= want then b:SetAttribute("type", "item"); b:SetAttribute("item", want) end
    if tex then b.icon:SetTexture(tex) end
    if not b:IsShown() then b:Show() end
  elseif b:IsShown() then
    b:Hide()
  end
end

-- the reward window's pick, marked with QuestBank's own glow over the game's button (never the button itself)
function SF.MarkReward()
  local r = G.reward
  local buttons = QuestInfoFrame and QuestInfoFrame.rewardsFrame and QuestInfoFrame.rewardsFrame.RewardButtons
  local b = r and buttons and buttons[r.index]
  if not b or fighting() then if SF.mark and not fighting() then SF.mark:Hide() end return end
  if not SF.mark then
    SF.mark = CreateFrame("Frame", nil, UIParent)
    SF.mark:SetFrameStrata("HIGH")
    if QB.Pins and QB.Pins.Glow then QB.Pins.Glow(SF.mark, GOLD) end
  end
  SF.mark:ClearAllPoints()
  SF.mark:SetPoint("TOPLEFT", b, "TOPLEFT", -4, 4)
  SF.mark:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 4, -4)
  SF.mark:Show()
end
```

Call `SF.MarkReward()` at the end of `SF.Refresh` (after `RefreshItem`). The `PLAYER_REGEN_ENABLED` hook: the step frame's own event frame (one `CreateFrame("Frame")` in `SF:Init`, `RegisterEvent("PLAYER_REGEN_ENABLED")`) runs `if SF.pendingItem then lastVer = -1; SF.Refresh() end`. Check `P.Glow(f, col)`'s signature at Pins.lua:453 before calling it; if it expects a colour table of three numbers, `GOLD` fits.

- [ ] **Step 4: Run the harness**

Expected: the case `ok`; the harness's secure-frame rule (a `SecureActionButtonTemplate` made in a fight errors, harness.lua:493) never trips because `itemButton` runs only when `fighting()` is false.

- [ ] **Step 5: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/QuestBank/StepFrame.lua tools/questbank/QuestBank/Guide.lua tools/questbank/QuestBank/Auto.lua tools/questbank/QuestBank/Core.lua tools/questbank/harness.lua && git commit -q -m "feat(questbank): the step frame's quest-item button; a reward choice stops and marks QuestBank's pick" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 13: The welcome and the 5.x question

**Files:**
- Modify: `tools/questbank/QuestBank/StepFrame.lua` (`SF.Ask`, `SF.AskPending`, the card)
- Modify: `tools/questbank/QuestBank/Core.lua` (`QB.WELCOME` line; nothing else prints)
- Test: `harness.lua` `G6CASES` (two cases)

**Interfaces:**
- Produces: `SF.card` (a child frame of `SF.frame` with `.title`, `.accept` (a button cycling Off / Quests on my route / Quests worth taking), `.other` (Accept them / Leave the window to me, enabled with "worth"), `.turnIn` (a CheckButton "Hand in finished quests for me"), `.done` (button), and for the 5.x question `.yes`, `.no`); `SF.Ask(kind)`; `QB.WELCOME = "QuestBank is guiding you. /qb opens the full window; right-click the step frame for its options."`.
- Consumes: `QB:Settings().welcome`, `Auto.WORDS`, `Auto.OTHER`, `QB:Settings().autoAccept / autoAcceptOther / autoTurnIn`, `QB.Arrow:Set(true)`.

- [ ] **Step 1: Write the failing cases**

```lua
  G6CASES[#G6CASES + 1] = { "a fresh install: the welcome card asks the auto choice; one line in chat, nothing else", function()
    local c = human("Newbie", { { 7, 0 } }, { [783] = true }, nil, 2)
    local QB, SF, A = c.QB, c.QB.StepFrame, c.QB.Arrow
    settle(c); SF.Apply()
    local f = c.env.QuestBankStep
    assert(f and f:IsShown() and f.card and f.card:IsShown(), "the frame with the welcome card")
    assert(f.card.accept:GetText() == "Accept for me: Off" and f.card.turnIn:GetChecked() == false and not f.card.other:IsEnabled(), "the choices start at Off: " .. tostring(f.card.accept:GetText()))
    assert(A.frame and A.frame:IsShown(), "QuestBank's arrow is on")
    assert(QB:Settings().arrowStyle == "questbank", "QuestBank's own arrow, not the compass")
    local before = #c.chat
    f.card.accept.__scripts.OnClick(f.card.accept, "LeftButton")
    f.card.accept.__scripts.OnClick(f.card.accept, "LeftButton")
    assert(f.card.accept:GetText() == "Accept for me: Quests worth taking" and f.card.other:IsEnabled(), "two clicks: Quests worth taking, the outside choice opens")
    f.card.other.__scripts.OnClick(f.card.other, "LeftButton")
    assert(f.card.other:GetText() == "Outside my route: Leave the window to me", f.card.other:GetText())
    f.card.turnIn:SetChecked(true); f.card.turnIn.__scripts.OnClick(f.card.turnIn)
    assert(#c.chat == before, "nothing said while choosing")
    f.card.done.__scripts.OnClick(f.card.done, "LeftButton")
    local s = QB:Settings()
    assert(s.autoAccept == "worth" and s.autoAcceptOther == "leave" and s.autoTurnIn == true and s.welcome == nil, "the choices kept")
    assert(#c.chat == before + 1 and c.chat[#c.chat]:find("QuestBank is guiding you. /qb opens the full window; right%-click the step frame for its options%."), "the one line: " .. tostring(c.chat[#c.chat]))
    assert(not f.card:IsShown() and f.now:GetText() ~= "", "the card gives way to the steps")
    settle(c); SF.Refresh()
    assert(#c.chat == before + 1, "and nothing more")
    checkLayout(f, "welcome card")
  end }

  G6CASES[#G6CASES + 1] = { "a 5.x save: one question, both answers", function()
    local saved = function() return { settings = { v544 = true, autoAccept = "route", autoTurnIn = true, arrow = false, arrowStyle = "compass", tab = 6 } } end
    -- Not now
    local c = human("Oldhand", { { 7, 0 } }, { [783] = true }, saved(), 8)
    local QB, SF = c.QB, c.QB.StepFrame
    settle(c); SF.Apply()
    local f = c.env.QuestBankStep
    assert(f:IsShown() and f.card:IsShown() and f.card.title:GetText() == "Let QuestBank guide you?", "the question: " .. tostring(f.card.title:GetText()))
    local before = #c.chat
    f.card.no.__scripts.OnClick(f.card.no, "LeftButton")
    local s = QB:Settings()
    assert(s.guide.on == false and s.welcome == nil and s.arrow == false and s.arrowStyle == "compass" and s.autoAccept == "route" and s.autoTurnIn == true, "Not now: nothing changed")
    assert(not f:IsShown() and #c.chat == before, "the frame hides, nothing said")
    s.guide.on = true; SF.Apply()
    assert(f:IsShown() and not f.card:IsShown(), "Settings turns the Guide on later: the frame is back with steps")
    -- Yes
    local d = human("Convert", { { 7, 0 } }, { [783] = true }, saved(), 8)
    local QD, SD = d.QB, d.QB.StepFrame
    settle(d); SD.Apply()
    local g = d.env.QuestBankStep
    local n0 = #d.chat
    g.card.yes.__scripts.OnClick(g.card.yes, "LeftButton")
    local t = QD:Settings()
    assert(t.guide.on == true and t.arrow == true and t.autoAccept == "route" and t.autoTurnIn == true and t.arrowStyle == "compass", "Yes: the Guide and the arrow on, the rest as it was")
    assert(g.card:IsShown() and g.card.accept and g.card.accept:GetText() == "Accept for me: Quests on my route", "then the welcome card, starting from their own choice")
    g.card.done.__scripts.OnClick(g.card.done, "LeftButton")
    assert(#d.chat == n0 + 1 and d.chat[#d.chat]:find("guiding you", 1, true), "the one line after Done")
  end }
```

- [ ] **Step 2: Run the harness to see them fail**

Expected: `the frame with the welcome card` (no `f.card`).

- [ ] **Step 3: The card**

Core.lua, next to `QB.SAY`: `QB.WELCOME = "QuestBank is guiding you. /qb opens the full window; right-click the step frame for its options."`

StepFrame.lua:

```lua
-- the welcome (a fresh install: the auto choice) and the 5.x question, as a card in the frame. Done or Yes/Not now
-- is the only way out; the one chat line comes after Done
local ACCEPT_ORDER = { "off", "route", "worth" }
local function cardButton(parent, label, width)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(label)
  return b
end
local function buildCard(f)
  local card = CreateFrame("Frame", nil, f)
  card:SetPoint("TOPLEFT", PAD, -PAD)
  card:SetSize(WIDTH - PAD * 2, ROW * 8)
  card.title = fs(card, 12, INK, WIDTH - PAD * 2)
  card.title:SetPoint("TOPLEFT", 0, 0)
  card.title:SetWordWrap(true)
  card.accept = cardButton(card, "", WIDTH - PAD * 2)
  card.accept:SetPoint("TOPLEFT", 0, -ROW * 1.5)
  card.other = cardButton(card, "", WIDTH - PAD * 2)
  card.other:SetPoint("TOPLEFT", 0, -ROW * 2.9)
  card.turnIn = CreateFrame("CheckButton", nil, card, "UICheckButtonTemplate")
  card.turnIn:SetSize(24, 24)
  card.turnIn:SetPoint("TOPLEFT", -4, -ROW * 4.2)
  card.turnIn.label = fs(card, 11, INK, WIDTH - PAD * 2 - 28)
  card.turnIn.label:SetPoint("LEFT", card.turnIn, "RIGHT", 2, 0)
  card.turnIn.label:SetText("Hand in finished quests for me")
  card.done = cardButton(card, "Done", 90)
  card.done:SetPoint("TOPLEFT", 0, -ROW * 5.8)
  card.yes = cardButton(card, "Yes", 90)
  card.yes:SetPoint("TOPLEFT", 0, -ROW * 1.8)
  card.no = cardButton(card, "Not now", 110)
  card.no:SetPoint("TOPLEFT", 100, -ROW * 1.8)
  local function words()
    local s = QB:Settings()
    card.accept:SetText("Accept for me: " .. (QB.Auto.WORDS[s.autoAccept] or QB.Auto.WORDS.off))
    card.other:SetText("Outside my route: " .. (QB.Auto.OTHER[s.autoAcceptOther] or QB.Auto.OTHER.accept))
    card.other:SetEnabled(s.autoAccept == "worth")
    card.turnIn:SetChecked(s.autoTurnIn == true)
  end
  card.Words = words
  card.accept:SetScript("OnClick", QB.Safe(function()
    local s = QB:Settings()
    local i = 1
    for k, v in ipairs(ACCEPT_ORDER) do if v == s.autoAccept then i = k end end
    s.autoAccept = ACCEPT_ORDER[i % #ACCEPT_ORDER + 1]
    words()
  end, "welcome"))
  card.other:SetScript("OnClick", QB.Safe(function()
    local s = QB:Settings()
    s.autoAcceptOther = s.autoAcceptOther == "leave" and "accept" or "leave"
    words()
  end, "welcome"))
  card.turnIn:SetScript("OnClick", QB.Safe(function(self) QB:Settings().autoTurnIn = self:GetChecked() and true or false end, "welcome"))
  card.done:SetScript("OnClick", QB.Safe(function()
    QB:Settings().welcome = nil
    card:Hide()
    QB:Print(QB.WELCOME)
    lastVer = -1
    SF.Apply()
  end, "welcome"))
  card.yes:SetScript("OnClick", QB.Safe(function()
    local s = QB:Settings()
    s.guide.on, s.guide.frame, s.arrow = true, true, true
    if QB.Arrow then QB.Arrow:Set(true) end
    s.welcome = "fresh"
    QB:MarkDirty()
    SF.Ask("fresh")
  end, "welcome"))
  card.no:SetScript("OnClick", QB.Safe(function()
    local s = QB:Settings()
    s.welcome = nil
    card:Hide()
    SF.Apply() -- (the Guide is off: the frame hides)
  end, "welcome"))
  card:Hide()
  return card
end

-- kind: "fresh" (the auto choice) or "ask" (Let QuestBank guide you?)
function SF.Ask(kind)
  local f = SF.frame
  if not f then return end
  f.card = f.card or buildCard(f)
  local card = f.card
  for i = 1, 3 do f.rows[i]:Hide() end
  f.time:Hide(); f.remind:Hide()
  for _, t in ipairs(f.members) do t:Hide() end
  if f.item then f.item:Hide() end
  if kind == "ask" then
    card.title:SetText("Let QuestBank guide you?")
    card.accept:Hide(); card.other:Hide(); card.turnIn:Hide(); card.turnIn.label:Hide(); card.done:Hide()
    card.yes:Show(); card.no:Show()
    f:SetHeight(PAD * 2 + ROW * 3.5)
  else
    card.title:SetText("QuestBank guides you from here. At quest givers:")
    card.yes:Hide(); card.no:Hide()
    card.accept:Show(); card.other:Show(); card.turnIn:Show(); card.turnIn.label:Show(); card.done:Show()
    card.Words()
    f:SetHeight(PAD * 2 + ROW * 7.5)
  end
  card:Show()
  f:Show()
end

-- a welcome waiting (QB:Settings().welcome), shown as the frame is applied; the rows come back when it is answered
function SF.AskPending()
  local w = QB:Settings().welcome
  local f = SF.frame
  if not f then return end
  if w == "fresh" or w == "ask" then
    SF.Ask(w)
  elseif f.card and f.card:IsShown() then
    f.card:Hide()
    for i = 1, 3 do f.rows[i]:Show() end
    f.time:Show()
    lastVer = -1
    SF.Refresh()
  end
end
```

The arrow on a fresh install: `QB.Migrate600` sets `s.arrow = true`; `Arrow:Init()` (Core's `PLAYER_LOGIN`) shows it when the setting is true, and Core's init order puts `QB.Arrow:Init()` before `QB.StepFrame:Init()`. Also in `SF.Apply`'s `want`: already counts `welcome ~= nil`. `Not now` leaves `guide.on = false`, so `want` is false after the card hides. The `fs(card, 12, INK, ...)` helper is Task 11's; `UIPanelButtonTemplate` and `UICheckButtonTemplate` are in the harness's allowed templates (Settings uses both).

- [ ] **Step 4: Run the harness**

Expected: both cases `ok`, `layout problems: 0` (the card's title wraps: it has `SetWordWrap(true)` and the frame's height covers two lines).

- [ ] **Step 5: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/QuestBank/StepFrame.lua tools/questbank/QuestBank/Core.lua tools/questbank/harness.lua && git commit -q -m "feat(questbank): the welcome asks the auto choice once; a 5.x save is asked whether to be guided" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 14: The minimap's ! for every quest you can take

**Files:**
- Modify: `tools/questbank/QuestBank/QuestMap.lua` (`QM.GiversNear(m, level)`, `QM.ART.give`)
- Modify: `tools/questbank/QuestBank/Minimap.lua:202-286` (`Mini.List`: "give" pins; `styleGame`/`styleQT`: the ! for kind "give"; the tooltip)
- Modify: `tools/questbank/QuestBank/Guide.lua` (`G.GIVER_MAX = 40`, `G.GIVER_MERGE = 30`)
- Test: `harness.lua` `G6CASES`

**Interfaces:**
- Produces: `QM.GiversNear(mapID, level)` -> list of `{ npc = idx, ids = { questID, ... }, m, x, y }` for the givers on that map whose quests the player can take now (the filter `givers(m)` at QuestMap.lua:409 already applies: ForMe, level, not grey, prerequisites, D.QLOCK, not done, not excluded; export it); `Mini.List` entries `{ kind = "give", m, x, y, name, ids, n }` merged within 30 yards, at most 40, nearest first; the pin draws the game's ! (`QM.ART.give`, the atlas QuestMap's `!` uses: read `QM.ART` at QuestMap.lua:40-55 for its name) in both marker styles; its tooltip lists the quests (`QM.QuestLines(tip, quests, labels)`).
- Consumes: `QB:Settings().minimapGivers`, `QB.API.MapID()`, `QB.Model.World`.

- [ ] **Step 1: Write the failing case**

```lua
  G6CASES[#G6CASES + 1] = { "the minimap: a ! for every quest you can take now, merged, forty at most, a ? where to hand in", function()
    local c = human("Pinner", { { 7, 1 } }, { [783] = true }, nil, 3)
    local QB, Mini, QM, D = c.QB, c.QB.Mini, c.QB.QuestMap, c.QB.Data
    QB:Settings().guide.on = true; QB:Settings().welcome = nil
    settle(c)
    local gives = QM.GiversNear(1429, 3)
    assert(#gives > 0, "givers with quests for a level-3 human on Elwynn's map")
    for _, g in ipairs(gives) do
      for _, id in ipairs(g.ids) do
        local q = QB.Quest.Get(id)
        local st = QB:Status(q)
        assert(st.code == "todo" or st.code == "item", "every quest listed is one you can take: " .. q.name .. " " .. st.code)
        assert(not QM.Grey(q, 3), "never a grey one: " .. q.name)
      end
    end
    local list = Mini.List()
    local give, turn, n = 0, 0, 0
    for _, d in ipairs(list) do
      if d.kind == "give" then give = give + 1; n = n + (d.n or 1) end
      if d.kind == "turn" then turn = turn + 1 end
    end
    assert(give > 0 and give <= 40 and n >= give, "! pins, merged, forty at most: " .. give .. " for " .. n .. " givers")
    assert(turn >= 1, "a ? for Kobold Camp Cleanup's hand-in")
    -- two givers within 30 yards are one pin with a count
    local merged = false
    for _, d in ipairs(list) do if d.kind == "give" and (d.n or 1) > 1 then merged = true end end
    assert(merged, "Northshire's givers at the abbey merge")
    -- the switch
    QB:Settings().minimapGivers = false
    for _, d in ipairs(Mini.List()) do assert(d.kind ~= "give", "off: no !") end
    QB:Settings().minimapGivers = true
    -- placed: the pin draws the game's ! atlas
    Mini.Place()
    local drawn = false
    for _, p in ipairs(Mini.pins or {}) do if p:IsShown() and p.item and p.item.kind == "give" then drawn = true end end
    assert(drawn or #list == 0, "a ! drawn on the minimap")
  end }
```

(`Mini.pins` and `p.item`: read `newPin` and `Mini.Place` at Minimap.lua:423 and 715 for the real names of the pin pool and the entry a pin carries, and use those.)

- [ ] **Step 2: Run the harness to see it fail**

Expected: `attempt to call field 'GiversNear' (a nil value)`.

- [ ] **Step 3: Implement**

QuestMap.lua, after the local `givers(m)` (line 409):

```lua
-- the givers on a map with quests you can take now, for the minimap's ! (6.0): the same filter the world map's !
-- uses. Each: the NPC's index, its quest ids, its place on the map
function QM.GiversNear(m, level)
  local out = {}
  for _, g in ipairs(givers(m) or {}) do
    local n = D.NPC[g.npc]
    if n and #g.ids > 0 then out[#out + 1] = { npc = g.npc, ids = g.ids, m = n[2], x = n[3], y = n[4] } end
  end
  return out
end
```

Read `givers(m)` first: it returns the giver groups already filtered for the player (check it takes the level from `QB.state.level` and honours `mapGive`; if it returns raw groups and the filtering happens in the layer's draw, move that filter into a local `takeable(g, level)` and apply it here and there). Export the `!` art name as `QM.ART.give` if `ART` lacks it (the offer pin's atlas is `P.StyleOffer`'s; the minimap draws `QM.ART.give` through `QM.PaintKind(tex, "give")`).

Minimap.lua `Mini.List`, after the pick-up block:

```lua
  -- a ! for every quest you can take now on this map (6.0), merged within GIVER_MERGE yards, GIVER_MAX nearest first
  if QB:Settings().minimapGivers ~= false and QB.QuestMap and QB.QuestMap.GiversNear then
    local m = QB.state.mapID or QB.API.MapID()
    local me = QB.API.WorldPosition()
    local G = QB.Guide
    local MERGE, MAX = (G and G.GIVER_MERGE or 30), (G and G.GIVER_MAX or 40)
    local gl = {}
    for _, g in ipairs(QB.QuestMap.GiversNear(m, QB.state.level)) do
      local w = QB.Model.World(g.m, g.x, g.y)
      if w then
        local d = { m = g.m, x = g.x, y = g.y, name = QB.Data.NPC[g.npc][1], kind = "give", ids = g.ids, n = 1, wx = w.wx, wy = w.wy, c = w.c }
        d.far = (me and me.c == w.c) and ((w.wx - me.wx) ^ 2 + (w.wy - me.wy) ^ 2) or math.huge
        local home
        for _, o in ipairs(gl) do
          if o.c == w.c and (o.wx - w.wx) ^ 2 + (o.wy - w.wy) ^ 2 <= MERGE * MERGE then home = o break end
        end
        if home then
          home.n = home.n + 1
          for _, id in ipairs(g.ids) do home.ids[#home.ids + 1] = id end
        else
          d.ids = { unpack(g.ids) } -- (its own list: a merge appends)
          gl[#gl + 1] = d
        end
      end
    end
    table.sort(gl, nearFirst)
    for i = 1, math.min(MAX, #gl) do out[#out + 1] = gl[i]; keys[#keys + 1] = -1000000 - i end
  end
```

(`d.ids` is a copy so a merge can append. `nearFirst` is the local at Minimap.lua:196 and sorts by `far`.) In `styleGame`/`styleQT` (Minimap.lua:498, 533): kind "give" paints `QM.PaintKind(p.icon, "give")` at `SIZE.pickup`, with a count text when `it.n > 1` (the pins have a count FontString for stops: reuse it). The tooltip (`Mini.QuestTooltip` or the pin's OnEnter): for kind "give", `QM.QuestLines(tip, quests)` with the quests of `d.ids`. `Mini.ListCached`'s key must include `s.minimapGivers` and `QB.state.mapID`.

- [ ] **Step 4: Run the harness**

Expected: the case `ok`; the memory block's "garbage a minute" stays under 3 MB (the list is cached for `LIST_EVERY` seconds and remade on `QB.changed`; the `gl` tables are made per list, a few KB).

- [ ] **Step 5: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/QuestBank/QuestMap.lua tools/questbank/QuestBank/Minimap.lua tools/questbank/QuestBank/Guide.lua tools/questbank/harness.lua && git commit -q -m "feat(questbank): a ! on the minimap for every quest you can take now, merged, forty at most" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 15: Tooltip progress (Tips.lua)

**Files:**
- Create: `tools/questbank/QuestBank/Tips.lua`
- Modify: `tools/questbank/QuestBank/QuestBank.toc` (`Tips.lua` after `StepFrame.lua`)
- Modify: `tools/questbank/QuestBank/Core.lua` (init: `if QB.Tips then QB.Tips:Init() end`)
- Modify: `tools/questbank/harness.lua:759` (the `TooltipDataProcessor` mock keeps hooks per kind: `c.tipHooksByKind[kind]`)
- Test: `harness.lua` `G6CASES`

**Interfaces:**
- Produces: `QB.Tips`: `Tips:Init()` registers `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, fn)` and `(Enum.TooltipDataType.Object, fn)`; `Tips.Lines(name)` -> list of `{ text, party }` lines for a creature or object name (one list reused); `Tips.Add(tip, data)` the hook body.
- Consumes: `QB.state.logOrder`, `e.objectives[i].text` (`"Kobold Vermin slain: 3/8"`), `G.ParseLine(text)` (Task 2) -> name, have, need; `QB.Sync.members[*].quests[id].prog` ("3/8"); `QB:Settings().tipProgress`.

- [ ] **Step 1: Mock and the failing case**

Harness line 759 becomes:

```lua
  c.tipHooks, c.tipHooksByKind = {}, {}
  env.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn)
    if kind == 0 then c.tipHooks[#c.tipHooks + 1] = fn end
    c.tipHooksByKind[kind] = c.tipHooksByKind[kind] or {}
    table.insert(c.tipHooksByKind[kind], fn)
  end }
  env.Enum.TooltipDataType = env.Enum.TooltipDataType or { Item = 0, Spell = 1, Unit = 2, Corpse = 3, Object = 4 }
```

(`env.Enum` exists at line 459; keep `c.tipHooks` as the item hooks the older tests use.) Case:

```lua
  G6CASES[#G6CASES + 1] = { "tooltips: Kobold Vermin: 3/8 (Kobold Camp Cleanup), and the party's count", function()
    local a = newClient({ name = "Tipper", level = 3, cap = 60, faction = "Alliance", className = "Warrior", class = "WARRIOR", classID = 1, race = "Human",
      log = { { 7, 0 } }, done = { [783] = true }, group = true, world = { 0, -8914, -133 }, map = 1429, bagSlots = {}, bind = "Goldshire" })
    local b = newClient({ name = "Brann", level = 3, cap = 60, faction = "Alliance", className = "Paladin", class = "PALADIN", classID = 2, race = "Human",
      log = { { 7, 0 } }, done = { [783] = true }, group = true, world = { 0, -8914, -133 }, map = 1429, bagSlots = {}, bind = "Goldshire" })
    login(a); login(b)
    a.objectives = { [7] = { { text = "Kobold Vermin slain: 3/8", type = "monster", finished = false, numFulfilled = 3, numRequired = 8 } } }
    b.objectives = { [7] = { { text = "Kobold Vermin slain: 6/8", type = "monster", finished = false, numFulfilled = 6, numRequired = 8 } } }
    settle(a); settle(b)
    a.QB.Sync:Broadcast(true); b.QB.Sync:Broadcast(true)
    for _ = 1, 3 do tick(a, 2); tick(b, 2); deliver() end
    local hooks = a.tipHooksByKind[2]
    assert(hooks and #hooks == 1 and a.tipHooksByKind[4] and #a.tipHooksByKind[4] == 1, "one hook each for units and objects")
    lines = {}
    hooks[1](a.env.GameTooltip, { type = 2, guid = "Creature-0-4455-0-12-6-0000A1B2C3", lines = { { leftText = "Kobold Vermin" }, { leftText = "Level 1" } } })
    local joined = table.concat(lines, " | ")
    assert(joined:find("Kobold Vermin: 3/8 (Kobold Camp Cleanup)", 1, true), "the line: " .. joined)
    assert(joined:find("Brann 6/8", 1, true), "the party's count: " .. joined)
    -- a secret guid or name: nothing
    lines = {}
    hooks[1](a.env.GameTooltip, { type = 2, guid = SECRET.str(), lines = { { leftText = SECRET.str() } } })
    assert(#lines == 0, "secret: nothing shown")
    -- a mob of no quest: nothing
    lines = {}
    hooks[1](a.env.GameTooltip, { type = 2, guid = "Creature-0-4455-0-12-99-0000A1B2C3", lines = { { leftText = "Stormwind Guard" } } })
    assert(#lines == 0, "no quest: nothing")
    -- the switch
    a.QB:Settings().tipProgress = false
    lines = {}
    hooks[1](a.env.GameTooltip, { type = 2, guid = "Creature-0-4455-0-12-6-0000A1B2C3", lines = { { leftText = "Kobold Vermin" } } })
    assert(#lines == 0, "off: nothing")
  end }
```

(`lines` is the harness's global the mock `GameTooltip:AddLine` writes to, as `poke` uses it at harness.lua:1207; `SECRET.str()` makes a secret value, line 586.)

- [ ] **Step 2: Run the harness to see it fail**

Expected: `one hook each for units and objects`.

- [ ] **Step 3: Write Tips.lua**

```lua
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Tooltip progress (6.0): a mob or object you hover that counts for a quest in your log gets a line, "Kobold Vermin:
-- 3/8 (Kobold Camp Cleanup)", and the party's counts where Sync knows them ("Brann 6/8"). Through the game's own
-- tooltip hooks (TooltipDataProcessor.AddTooltipPostCall, unit and object types), reading the tooltip's data: the
-- name on its first line, matched against each objective's text; the guid read through QB.Plain, and nothing shown
-- when the name or the guid is a secret value. Only reads, only its lines.
local _, QB = ...
local Tips = {}
QB.Tips = Tips

local plain = QB.Plain
local out = {}
local function on() return QB:Settings().tipProgress ~= false end

-- the lines for a name: one per quest in your log whose objective names it, with the party's counts
function Tips.Lines(name)
  for k = #out, 1, -1 do out[k] = nil end
  if type(name) ~= "string" or name == "" then return out end
  local G = QB.Guide
  local S = QB.Sync
  local lname = name:lower()
  for _, e in ipairs(QB.state.logOrder or {}) do
    if not e.complete then
      for _, o in ipairs(e.objectives or {}) do
        local oname, have, need = G.ParseLine(o.text)
        if oname and have and need and oname:lower() == lname then
          local q = QB.Quest.Get(e.id)
          local line = { text = string.format("%s: %d/%d (%s)", name, have, need, q and q.name or plain(e.title) or ("Quest " .. e.id)) }
          if S and S.members and IsInGroup and IsInGroup() then
            local parts
            for _, m in pairs(S.members) do
              local mq = m.quests and m.quests[e.id]
              if mq and mq.prog then parts = parts or {}; parts[#parts + 1] = (m.name or m.key) .. " " .. mq.prog end
            end
            if parts then table.sort(parts); line.party = table.concat(parts, ", ") end
          end
          out[#out + 1] = line
        end
      end
    end
  end
  return out
end

-- the hook: data is the tooltip's TooltipData (type, guid, lines)
function Tips.Add(tip, data)
  if not on() or type(data) ~= "table" then return end
  local guid = plain(data.guid)
  if data.guid ~= nil and guid == nil then return end -- (a secret guid: the unit is hidden from addons)
  local lines = plain(data.lines)
  local first = type(lines) == "table" and plain(lines[1]) or nil
  local name = type(first) == "table" and plain(first.leftText) or nil
  if type(name) ~= "string" then return end
  for _, l in ipairs(Tips.Lines(name)) do
    tip:AddLine(l.text, 1, 0.82, 0.3, true)
    if l.party then tip:AddLine(l.party, 0.6, 0.6, 0.6, true) end
  end
end

function Tips:Init()
  if self.ready then return end
  local TDP, E = TooltipDataProcessor, Enum and Enum.TooltipDataType
  if not (TDP and TDP.AddTooltipPostCall and E) then return end
  local fn = QB.Safe(function(tip, data) Tips.Add(tip, data) end, "tooltip progress")
  if E.Unit then pcall(TDP.AddTooltipPostCall, E.Unit, fn) end
  if E.Object then pcall(TDP.AddTooltipPostCall, E.Object, fn) end
  self.ready = true
end
```

The `line` tables are made per hover (a few bytes); if the memory block's "garbage a minute" complains, pool them as `Guide.lua` pools steps. Core.lua init: after `QB.StepFrame:Init()`: `if QB.Tips then QB.Tips:Init() end`. Add `Tips.lua` to the toc after `StepFrame.lua`.

- [ ] **Step 4: Run the harness**

Expected: the case `ok`; Game.lua's item hook case (harness.lua:10237 `hover`) still passes with `c.tipHooks`.

- [ ] **Step 5: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/QuestBank/Tips.lua tools/questbank/QuestBank/QuestBank.toc tools/questbank/QuestBank/Core.lua tools/questbank/harness.lua && git commit -q -m "feat(questbank): quest progress in mob and object tooltips, with the party's counts" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 16: Settings regrouped: Guide first, Banking last

**Files:**
- Modify: `tools/questbank/QuestBank/UI.lua:4548-5174` (`UI:CreateSettingsView`, `UI:RefreshSettingsView`)
- Test: `harness.lua` `G6CASES`

**Interfaces:**
- Produces: `v.headings` (the page's heading FontStrings in order), `v.guideOn`, `v.guideFrame`, `v.guideLocked`, `v.guideScale` (button cycling 80% / 100% / 120%), `v.arrow` (moved here), `v.minimapGivers`, `v.tipProgress`, and the existing `v.autoAccept`, `v.autoOther`, `v.autoTurnIn` moved under Guide; the order of headings: "Guide", "Map and minimap", then one per module ("Interact light", "Camp bar", "Timers", "Far zoom", "Golden path"), "Data you share", "Banking" last (the old "Mode" block with the cap buttons, renamed).
- Consumes: `checkRow(parent, x, y, label, width)` and `heading(parent, x, y, label, width)` (UI.lua:4531-4546), `button(parent, label, width)`, `QB.StepFrame.Apply()`, `QB.StepFrame.SetScale(sc)`, `QB.Arrow:Set(on)`.

- [ ] **Step 1: Write the failing case**

```lua
  G6CASES[#G6CASES + 1] = { "Settings open on Guide; Banking last; every row drives its setting", function()
    local c = human("Setter", { { 7, 0 } }, { [783] = true }, nil, 5)
    local QB, UI, SF = c.QB, c.QB.UI, c.QB.StepFrame
    QB:Settings().welcome = nil
    settle(c)
    UI:Open(5); UI:Refresh()
    local v = UI.views[5]
    local order = {}
    for _, h in ipairs(v.headings) do order[#order + 1] = h:GetText() end
    assert(order[1] == "Guide" and order[2] == "Map and minimap" and order[#order] == "Banking", "the order: " .. table.concat(order, " > "))
    local seen = {}
    for _, h in ipairs(order) do seen[h] = true end
    assert(seen["Data you share"] and seen["Interact light"] and seen["Camp bar"], "the module and data sections are there")
    local iData, iBank = 0, 0
    for i, h in ipairs(order) do if h == "Data you share" then iData = i end if h == "Banking" then iBank = i end end
    assert(iData < iBank and iData > 2, "Data you share before Banking, after the modules")
    -- the Guide's rows
    assert(v.guideOn:GetChecked() == true and v.guideFrame:GetChecked() == true and v.arrow:GetChecked() == true, "the rows show the settings")
    v.guideOn:SetChecked(false); v.guideOn.__scripts.OnClick(v.guideOn)
    assert(QB:Settings().guide.on == false and not c.env.QuestBankStep:IsShown(), "Guide off: the frame hides")
    v.guideOn:SetChecked(true); v.guideOn.__scripts.OnClick(v.guideOn)
    assert(QB:Settings().guide.on == true and c.env.QuestBankStep:IsShown(), "on again")
    v.guideScale.__scripts.OnClick(v.guideScale, "LeftButton")
    assert(QB:Settings().guide.scale ~= 1 and v.guideScale:GetText():find("%%"), "the scale cycles: " .. v.guideScale:GetText())
    assert(v.autoAccept:GetText():find("^Accept for me: ") and v.minimapGivers and v.tipProgress, "auto, the ! and the tooltips sit under Guide")
    v.minimapGivers:SetChecked(false); v.minimapGivers.__scripts.OnClick(v.minimapGivers)
    assert(QB:Settings().minimapGivers == false, "the ! switch")
    -- the page is laid out with nothing clipped (the harness's layout pass covers Settings; this checks it here too)
    checkLayout(UI.frame, "settings after the regroup")
    -- the key bindings' names and the sidebar are untouched
    assert(UI.SIDEBAR[#UI.SIDEBAR].name == "Settings", "the sidebar as it was")
  end }
```

- [ ] **Step 2: Run the harness to see it fail**

Expected: `attempt to index field 'headings' (a nil value)`.

- [ ] **Step 3: Regroup**

In `UI:CreateSettingsView`, wrap `heading` so each call records itself:

```lua
  v.headings = {}
  local function head(x, y, label, width)
    local t = heading(p, x, y, label, width)
    v.headings[#v.headings + 1] = t
    return t
  end
```

and replace every `heading(p, ...)` in the function with `head(...)`. Then reorder the blocks by moving code, not rewriting it: the page is two columns (`LEFT`, `RIGHT`) at fixed y offsets; lay the new order out top to bottom and recompute each block's y as you go (a running `local y = -12` per column, each block `y = y - <its height>`), so no row overlaps. The order and the new rows:

1. `head(LEFT, y, "Guide", 370)`:
   - `v.guideOn = checkRow(p, LEFT, y, "Guide me: the step frame, the arrow, the route from where I stand", 340)` -> `QB:Settings().guide.on = checked; QB:MarkDirty(); QB.StepFrame.Apply()`.
   - `v.guideFrame = checkRow(p, LEFT + 24, y, "The step frame", 316)` -> `guide.frame`; `v.guideLocked = checkRow(..., "Locked in place", ...)` -> `guide.locked`; `v.guideScale = button(p, "100%", 70)` cycling `QB.StepFrame.SCALES` through `QB.StepFrame.SetScale`.
   - `v.arrow` (the existing row, moved here, label "Direction arrow (right-click it for what it points at)") and `v.arrowStyle` (the existing QuestBank's / Compass button).
   - the existing "At the quest giver" rows (`v.autoAccept`, `v.autoOther`, `v.autoTurnIn`, `v.autoKey`) moved here, the heading dropped (its rows sit under Guide).
   - `v.minimapGivers = checkRow(..., "A ! on the minimap for every quest I can take", ...)` -> `QB:Settings().minimapGivers`; `QB.Mini.Invalidate()` if it exists.
   - `v.tipProgress = checkRow(..., "Quest progress in mob tooltips", ...)` -> `tipProgress`.
2. `head(LEFT, y, "Map and minimap", 370)`: the existing "Map", "Map icons" and "Minimap and map" rows (`v.pins`, `v.minimap`, the `MAP_ICONS` loop, `v.mmExtended`, `v.walkShow`, the marker style, the icon size).
3. The modules, one heading each with its rows inside, in this order: "Interact light" (the existing block), "Camp bar" (the existing block), "Timers" (the existing block), "Health and mana numbers" (the existing block), "Party chat" and "When you are..." (the existing context table).
4. `head(RIGHT, y, "Data you share")`: the existing "Discoveries" and "Sharing and chat" rows (`v.survey`, `v.noteGame`, `v.shareParty`, `v.shareGuild`), the "Updates" rows.
5. `head(LEFT, y, "Banking", 370)` last: the old "Mode" block (`v.modeBtns`, `v.modeText`, the cap buttons) and "Suggestions" (`v.rangeAuto` and the range rows).

`UI:RefreshSettingsView` sets the new rows: `v.guideOn:SetChecked(s.guide.on)`, `v.guideFrame:SetChecked(s.guide.frame)`, `v.guideLocked:SetChecked(s.guide.locked)`, `v.guideScale:SetText(string.format("%d%%", (s.guide.scale or 1) * 100))`, `v.minimapGivers:SetChecked(s.minimapGivers ~= false)`, `v.tipProgress:SetChecked(s.tipProgress ~= false)`. Set the scroll child's height to the larger column's final `-y + 20`.

The page is read by the harness's layout pass at login and dumped to the layout sheets; `checkLayout` reports any row over another. The Settings scenario in the older harness blocks reads `v.autoAccept:GetText()` (B3CASES "Accept for me is a choice"): keep the texts "Accept for me: ..." and "Outside my route: ...".

- [ ] **Step 4: Run the harness**

Expected: the case `ok`, `layout problems: 0`, the B3 "Accept for me is a choice" case still `ok`. Then draw the sheet to look at it once: `luajit harness.lua --layout <scratchpad>/layout.json` and `python3 -I tools/questbank/render_layout.py <scratchpad>/layout.json <scratchpad>/layout.html settings` (the sheet name is whatever the layout pass calls the Settings page; `grep -n '"settings' harness.lua` finds it).

- [ ] **Step 5: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/QuestBank/UI.lua tools/questbank/harness.lua && git commit -q -m "feat(questbank): Settings open on Guide, then Map and minimap, the modules, Data you share, Banking last" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 17: The page: the stage shows the step frame, the 6.0 line

**Files:**
- Modify: `questbank/index.html` (the hero copy, the stage: a `#qb-step` beside the arrow, the `qb-mock` JSON's `step`, the stage script, the changelog line, the FAQ line on auto accept)
- Modify: `tools/questbank/build_page.py` (`check_mock`: the step block's texts are drawn; `NODE_CHECK`: `#qb-step` drawn with `mock.step.now`; `STALE` list: "off on a new install" for auto is stale now; `check_length` fixed heights)
- Test: `python3 -I tools/questbank/build_page.py` (its own checks), plus a stale-text check for the old auto-off sentence

**Interfaces:**
- Produces: `mock.step = { now, next = [a, b], time, item (an icon name or null), members = [] }` in the `qb-mock` JSON; `<div class="qb-step" id="qb-step" aria-label="QuestBank's step frame"></div>` inside `.qb-scene` next to `#qb-arrow`; CSS classes `qb-step`, `qb-s-now`, `qb-s-next`, `qb-s-time`, `qb-s-item` in the page's `<style>`; a `#changelog` first row `6.0.0`.

- [ ] **Step 1: Make the page checks fail first**

In `build_page.py` `check_mock`, after the cards' check add:

```python
    step = mock.get("step")
    if not (isinstance(step, dict) and step.get("now") and isinstance(step.get("next"), list) and len(step["next"]) == 2 and step.get("time")):
        problem("the mock has no step frame (step: now, next[2], time)"); return
    ok("the mock's step frame: %s" % step["now"])
```

In `NODE_CHECK` (the JavaScript string), after the arrow check:

```javascript
const stepEl = byId["qb-step"];
if (!stepEl || !stepEl.innerHTML || stepEl.innerHTML.indexOf(mock.step.now) < 0) fail("the step frame is not drawn with its step");
balanced(stepEl.innerHTML, "the step frame");
```

(`byId` is the stub DOM's map of ids in that script; add `"qb-step"` to the ids it creates, next to `"qb-arrow"`.) In `STALE`, add `("off on a new install", "6.0 asks the auto choice in the welcome")` in the same shape the list uses (read lines 303-317). Run:

```bash
cd /Users/mikalbot/foreverrank && python3 -I tools/questbank/build_page.py
```
Expected: `problems: 2` (no step in the mock; the stale sentence in the FAQ).

- [ ] **Step 2: The page**

`questbank/index.html`:

- The hero keeps its kicker, `<h1>QuestBank</h1>`, the pitch "1 to 60 on launch day, computed from Forever's own data." and the lede "Your next step, an arrow to it, and every quest priced as Forever pays it." (both already there).
- The stage section `#window`: the lede becomes `The first five minutes: the step frame, the arrow, and the window behind them. A level 20 paladin in Stormwind.`; inside `.qb-scene` add `<div class="qb-step" id="qb-step" aria-label="QuestBank's step frame"></div>` before `#qb-arrow`.
- CSS, next to `.qb-arrow`'s rules: `.qb-step { position: absolute; left: 24px; top: 24px; width: 260px; padding: 8px; background: rgba(14,18,24,.92); border: 1px solid rgba(255,210,77,.5); border-radius: 4px; color: var(--qb-ink); font: 12px/18px var(--qb-font, inherit); }`, `.qb-s-now { color: #f2ead9; }`, `.qb-s-next { color: #9ea5a8; font-size: 11px; }`, `.qb-s-time { color: #9ea5a8; font-size: 10px; margin-top: 4px; }`, `.qb-s-item { position: absolute; right: 8px; top: 8px; width: 22px; height: 22px; }`. On phone widths (`@media (max-width: 720px)`) the step frame sits above the arrow, not over the window's title: `left: 12px; top: 12px; width: 220px`.
- The mock JSON gains, after `"arrow"`:

```json
  "step": {"now": "Kill Defias Trapper 4/10", "next": ["Hand in The People's Militia", "Accept The Defias Brotherhood from Gryan Stoutmantle"],
           "time": "about 14 min to level 21", "item": null, "members": []}
```

(the names must be catalog quests at the mock's level: "The People's Militia" and "The Defias Brotherhood" are Westfall quests in `D.QN`; `check_mock` checks only the cards, so this is for honesty.)
- The stage script, after the arrow block:

```javascript
  var stepEl = document.getElementById("qb-step");
  if (M && M.step && stepEl) {
    var st = M.step;
    stepEl.innerHTML = '<div class="qb-s-now">' + esc(st.now) + '</div>' +
      st.next.map(function (n) { return '<div class="qb-s-next">' + esc(n) + '</div>'; }).join("") +
      '<div class="qb-s-time">' + esc(st.time) + '</div>' + (st.item ? icon(st.item, "qb-s-item") : "");
  }
```

- The FAQ's "Does it accept or hand in for me?" answer becomes: `Only as you chose in the welcome: Off, quests on your route, or quests worth taking, and whether finished quests are handed in for you. Settings' Guide section changes it; hold Shift at an NPC and it keeps its hands off.`
- The changelog's first row: `<li><b>6.0.0</b><span>QuestBank guides from the first login: a step frame, the arrow on, auto accept as you choose it. 1 to 60, computed from Forever's data.</span></li>`; 5.4.4's row moves under it.
- `check_length`'s fixed heights (build_page.py:624): add the step frame's 90 px to the stage's figure.

- [ ] **Step 3: Run the page build**

```bash
cd /Users/mikalbot/foreverrank && python3 -I tools/questbank/build_page.py
```
Expected: `the mock's step frame: Kill Defias Trapper 4/10`, `problems: 0`, `OK`. (It stamps the version from the toc: still 5.4.4 until Task 18; the download's size is stamped from the zip, rebuilt in Task 18.)

- [ ] **Step 4: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add questbank/index.html tools/questbank/build_page.py && git commit -q -m "docs(questbank): the page's stage shows the step frame beside the arrow; the 6.0 line" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 18: The 6.0.0 release: version, README, the Guide's garbage gates, package

**Files:**
- Modify: `tools/questbank/QuestBank/Core.lua:5` (`QB.version = "6.0.0"`), `tools/questbank/QuestBank/QuestBank.toc` (`## Version: 6.0.0`, the `## Notes` line gains "guides from the first login")
- Modify: `tools/questbank/README.md` (a `Guide.lua`, `StepFrame.lua`, `Tips.lua` bullet each in the file list; one line in the harness paragraph for `G6CASES`; the "Rebuild and publish" block unchanged)
- Modify: `tools/questbank/harness.lua` (the 5.4.2 memory block: the Guide on for the owner's twin, a Replan garbage assertion, a step-frame tick assertion)
- Modify: `tools/questbank/QuestBank/Legacy.lua` or wherever `QB.version` is compared for the "newer version" notice: nothing to change (the compare is `QB.Newer(a, b)` on dotted numbers)
- Test: the full gate, the package, the page

**Interfaces:**
- Produces: `questbank/QuestBank.zip`, `questbank/QuestBank-Uploader.zip`, the stamped `questbank/index.html`.

- [ ] **Step 1: The Guide's own garbage checks in the memory block**

In the 5.4.2 memory block (harness.lua, after "6. a re-plan" and before "7. a refresh"), add:

```lua
  -- 6.0: the Guide. A Replan with nothing changed makes under 64 KB (its steps are pooled, its texts made on demand);
  -- a tick of the step frame with nothing changed makes nothing; the Guide on for the twin changes neither of the two
  -- gates above by more than their budgets allow (they run with it on from here)
  QB:Settings().guide.on, QB:Settings().guide.frame, QB:Settings().welcome = true, true, nil
  QB.Guide.Replan()
  QB.StepFrame.Apply(); QB.StepFrame.Refresh()
  local replan = ownBytes(function() QB.Guide.Replan() end)
  print(string.format("the Guide: a re-plan of the steps %.0f KB of garbage", replan / 1024))
  assert(replan < 64 * 1024, string.format("the Guide's Replan made %.0f KB (at most 64)", replan / 1024))
  local f = QB.StepFrame.frame
  local ticks = ownBytes(function() for _ = 1, 100 do f.elapsed = 1; f.__scripts.OnUpdate(f, 0.016) end end)
  print(string.format("the step frame: 100 ticks with nothing changed %.0f bytes", ticks))
  assert(ticks < 2048, string.format("the step frame's tick allocates: %.0f bytes over 100 ticks", ticks))
```

Run the gate: the three existing assertions ("garbage a minute" under 3 MB, the re-plan under 1 MB, the refresh under 100 KB) must still hold with the Guide on. If the refresh's 100 KB is exceeded, `G.Replan` is running on a `QB:Changed()` with nothing changed: gate it on `QB.changed ~= G.at` (keep `G.at = QB.changed` after a Replan) and on `G.ver` of the target (`QB.Target.ver`), Replan only when either moved.

- [ ] **Step 2: Version and README**

`Core.lua:5`: `QB.version = "6.0.0"`. The toc: `## Version: 6.0.0`, Notes: `Free questing for every level, guided from the first login: the next step, the arrow, what each quest pays, the hand-in route, party sync, banking at level caps. /qb`. README file list, after the `Auto.lua` entry (grep `Auto.lua` in README.md):

```
- `Guide.lua` (6.0): the step engine, no UI: the next steps from the one target and the route (accept, objectives clustered within 150 yards, hand in, travel, Train at your class trainer, the grind step, your corpse), filled with the quests Now ranks best (`QB:Plan().auto`, up to the log's free slots minus two, never more than two levels above you, never grey unless its chain pays), each step done when the game says so; "Not now" an hour, "Drop" for good; time to level from the plan, then from the measured XP an hour; the party's steps (Sync's `1G`).
- `StepFrame.lua` (6.0): the step frame: the step now, the next two greyed, the quest-item button (a secure button, set out of a fight), the time line, a click into the window, a right-click menu; the welcome card (the auto choice, once) and the 5.x question; the reward window's pick marked with QuestBank's own glow, never chosen.
- `Tips.lua` (6.0): "Kobold Vermin: 3/8 (Kobold Camp Cleanup)" in mob and object tooltips, with the party's counts; nothing when the game hides the unit.
```

and in the harness paragraph, after the B4 sentence: `Then 6.0's Guide (G6CASES): a fresh install's welcome and a 5.x save's question, a level-1 human through Northshire's first hand-ins, a level-23 character mid-chain, out of order, the Southshore walk with the first step kept, the corpse, travel, the grind step, the train step and a trainer learned, time to level, a party of two, the step frame at three scales, the item button in and out of a fight, a reward choice stopped and marked, the minimap's !, the tooltips, Settings opening on Guide.`

- [ ] **Step 3: The full gate, then the package and the page**

```bash
cd /Users/mikalbot/foreverrank/tools/questbank && luajit harness.lua 2>&1 | tail -12
```
Expected: every `6.0 guide: ...: ok`, the Guide's two new lines, `layout problems: 0`, `OK`.

```bash
cd /Users/mikalbot/foreverrank && (cd tools/questbank && rm -f ../../questbank/QuestBank.zip && zip -rq ../../questbank/QuestBank.zip QuestBank -x "*.DS_Store")
cd /Users/mikalbot/foreverrank && python3 tools/build_uploader.py
cd /Users/mikalbot/foreverrank && python3 -I tools/questbank/build_page.py
```
Expected: `version 6.0.0, QuestBank.zip NNN KB, Uploader NNN KB carrying QuestBank 6.0.0`, `problems: 0`, `OK`. (`build_uploader.py --test` needs Docker; run it when Docker is up: `python3 tools/build_uploader.py --test`.)

- [ ] **Step 4: Commit**

```bash
cd /Users/mikalbot/foreverrank && git add tools/questbank/QuestBank/Core.lua tools/questbank/QuestBank/QuestBank.toc tools/questbank/README.md tools/questbank/harness.lua questbank/QuestBank.zip questbank/QuestBank-Uploader.zip questbank/index.html && git commit -q -m "QuestBank 6.0.0: the Guide, on by default: a step frame, the arrow on, auto accept your choice, the minimap's !, progress in tooltips, time to level, train and grind steps, the party's steps; 1 to 60 computed from Forever's data" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

The owner pushes (pushes to main from this machine are blocked).

---

## Self-review (done while writing; the fixes are in the tasks above)

**Spec coverage**, section by section:

- *What the player sees on first login*: the step frame (Task 11), the arrow on and QuestBank's own by default (Task 13 asserts `arrowStyle == "questbank"`, the 5.4.4 default), the corpse (Task 5), the clicked waypoint rule (5.4.4, untouched), auto as the player's choice with the outside-route choice and hand-in asked together (Task 13), Shift pauses both (Auto.lua's `byHand`, untouched), a reward choice stops and marks (Task 12), one welcome line and nothing else in chat (Tasks 2, 11, 13 assert it), hand-ins in reach first (5.4.4's `Target.cur.near`, first step in Task 2), existing players asked once with both answers (Task 13).
- *The step engine*: input (Task 2's Replan reads the log, done, level and XP through Target and the route; flights and the hearth through Travel's steps in Task 5; bag space through `LOG_SLOTS - logCount` in Task 3; the party in Task 10), picking quests (Task 3), steps and clustering (Task 2), travel (Task 5), train (Tasks 7-8), done by itself (Tasks 2, 4), stable (Task 4), skips (Task 4), grinding (Task 6), budget (Task 18's gates, pooled steps).
- *The map*: ! and ? (Task 14), objective areas and finished objectives dropped (5.4.4), tooltips with party progress and the secret guard (Task 15), the world map layer (5.4.1, untouched).
- *Only QuestBank*: Forever XP (untouched), time to level (Task 9), party (Task 10), day one 1-60 (the catalog; "about" marking for unknown multipliers is the existing `xpUnknown` text, untouched).
- *Settings*: the order and the Guide section (Task 16); the game's own options untouched (no task touches Glow's CVars).
- *Testing*: every listed scenario has a case: fresh install (13), 5.x (13), level-1 human (2), level-23 three zones (3), out of order (4), death (5), party of two (10), Zephras (4), Southshore walk (4), grind (6), reward (12); layout checks at the scales (11) and the render_layout sheets (11, 16).
- *The page*: Task 17; the release line in Task 17, the version in Task 18.

**Placeholder scan**: no TBD/TODO; every step has code or an exact command. Four places tell the implementer to read a signature before calling (`TV.STEP` fields in Task 5, `P.Glow` in Task 12, `givers(m)` in Task 14, the pin pool names in Task 14): those are reads of existing code, not gaps.

**Type consistency**: `G.Text(step)`, `G.Steps()`, `G.Current()`, `G.ver`, `G.FirstKey()`, `G.Skip(id, "later"|"drop")`, `G.PutOff(id)`, `G.DB()`, `G.Fill(level)`, `G.Rank(c, level)`, `G.Corpse()`, `G.Grind(level, me)`, `G.NeedsTraining(level)`, `G.Trainer(stop)`, `G.TimeToLevel()`, `G.MemberSteps()`, `G.ItemFor(step)`, `G.HoldReward(qid, n)`, `G.DropReward()`, `G.reward`, `G.reminder`, `G.ParseLine(text)` are used with the same names and arguments in every task; `SF.Apply()`, `SF.Refresh()`, `SF.SetScale(sc)`, `SF:Menu(step)`, `SF.Ask(kind)`, `SF.AskPending()`, `SF.RefreshItem(step)`, `SF.MarkReward()`, `SF.frame` fields `.now .next1 .next2 .time .remind .rows .members .item .card` likewise; `QM.GiversNear(m, level)`; `S:Step(text)`, `m.step`; `QB:IsAuto(id)`, `QB:GuideOn()`, `QB.Migrate600(s, fresh)`, `QB.WELCOME`; the settings keys `guide.{on, frame, locked, scale, x, y}`, `minimapGivers`, `tipProgress`, `welcome`, `v600`; the data tables `D.TRAINER` (9 columns) and `D.SPELL_LV[token]`.

Fixed while reviewing: Task 2's `objectiveSteps` call passed a long `nil` expression as `lead` (now a plain `nil`; the block at the end of `Replan` moves the target's quest first, Task 4 confirms with `G.FirstKey`); `G.Replan` bumped `G.ver` twice (once now); Task 13's `card.accept` text had `..` binding before `or` (parenthesised); Task 14's merge block carried a no-op line (removed); Task 5's travel case and Task 10's party case carried a stray fixture and a loop over a field the harness lacks (removed).
