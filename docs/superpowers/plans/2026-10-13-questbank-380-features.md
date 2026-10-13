# QuestBank 3.8.0 features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship timers, clickable QuestBank links, item-to-quest tooltip lines, a configurable decide-yourself key and context profiles in QuestBank 3.8.0.

**Architecture:** Two new files, Clock.lua and Link.lua, each with `:Init()` called from Core's login sequence after Loot; a resolver `QB:Opt(key)` in Core.lua that Auto.lua and the clock read; settings rows added to `UI:CreateSettingsView`. Every client read passes `QB.Plain`; every handler is `QB.Safe`; every RegisterEvent is pcall'd.

**Tech Stack:** WoW Lua 5.1 on Forever (Interface 16001) and Classic Era (11507); `luajit harness.lua` in tools/questbank.

## Global Constraints

- Spec: docs/superpowers/specs/2026-10-13-questbank-380-features-design.md. Names and defaults as written there.
- Never store player, guild or realm names beyond the existing per-character key.
- Harness ends with `layout problems: 0` and `OK`; `python3 tools/build_uploader.py --test` passes.
- Version 3.8.0 in Core.lua, QuestBank.toc, questbank/index.html (four places).

---

### Task 1: QB:Opt and the decide-yourself key
Files: Core.lua (DEFAULTS: `autoKey = "shift"`, `profiles = { dungeon = {}, pvp = {}, party = {}, cap = {} }`, `clock = { show = false }`, `clockLevelMsg = true`; new `QB.Contexts()` and `QB:Opt(key)`), Auto.lua (`byHand()` reads `QB:Settings().autoKey`; `on(key)` becomes `QB:Opt(key) == true`), harness test block.
Test: a client in a party with base autoAccept false and `profiles.party.autoAccept = true` -> `QB:Opt("autoAccept") == true`; in a dungeon with `profiles.dungeon.autoAccept = false` -> false even with party true (order); `autoKey = "ctrl"` -> `Auto.ByHand()` follows IsControlKeyDown; `"none"` -> never. Secret IsInInstance -> contexts empty.

### Task 2: Timer.lua (the spec said Clock.lua; QB.Clock is already the time formatter, so the module is QB.Timer)
Files: Timer.lua (new, after Loot.lua in the TOC), Core.lua (Init call; level-up message), harness.
Functions: `Clock.Record(event, ...)`, `Clock.LevelTime(lvl)`, `Clock.QuestTime(qid)`, `Clock.Text()`, `Clock:Show(on)`, `Clock:Init()`.
Test: PLAYER_LEVEL_UP 31 writes `levels[31].at`; tick 600 s and `Clock.LevelTime(31) == 600`; QUEST_ACCEPTED 7 then tick 480 then QUEST_TURNED_IN 7 -> `QuestTime(7) == 480`; secret id skipped; cap 300; `Clock.Text()` carries "Lvl 31" and "8m"; strip hidden by default, shown when `settings.clock.show` (or `profiles.*.clockShow`).

### Task 3: Link.lua
Files: Link.lua (new), UI.lua (`UI.QuestLinkLocal(q)` returns the addon link; `UI.QuestMenu` reused), Game.lua or Link.lua (item tooltip post-call with `D.RITEMS` reverse index), Core.lua (level-up and `/qb next` messages use the local link), harness (EventRegistry mock added: `RegisterCallback(event, fn, owner)` + `TriggerEvent`).
Test: `Link.Format(q)` == `|cffc6af8d|Haddon:QuestBank:quest:7|h[Investigate Echo Ridge]|h|r`; triggering SetItemRef with that link opens the menu (menuFrame shown with the quest's name); an item tooltip for an item in `D.RITEMS` gains "Reward of" line; an item with no quest gains nothing.

### Task 4: Settings rows
Files: UI.lua `CreateSettingsView` + its refresh: Timers heading (two check rows), the key cycle button under auto rows, the "When you are..." tri-state block with the active-context line.
Test: harness layout pass stays at 0 problems; clicking the key button cycles shift -> ctrl -> alt -> none -> shift; a tri-state button cycles nil -> true -> false -> nil in `settings.profiles.party.autoAccept`.

### Task 5: Release 3.8.0
Version bumps, release notes, zips, uploader test, commit.
