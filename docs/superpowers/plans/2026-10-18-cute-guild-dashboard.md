# Cute guild dashboard: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A guild addon `Cute` that shares ~120 per-character stats over the guild addon channel and shows the whole guild in one Cute-styled in-game window, with officers deciding per stat whether members see each other's.

**Architecture:** A stat registry (`Stats.lua`) drives sampling, the wire format, the dashboard columns and the Settings checklists. `Comm.lua` sends deltas on GUILD; `Roster.lua` keeps every member's last-known values in `CuteDB`; `Policy.lua` holds the officers' visibility list. `UI.lua` renders five tabs from the registry. A luajit harness with a mocked Forever client is the test gate.

**Tech Stack:** WoW Lua (Forever client 1.60, Interface 16001), luajit harness, static HTML page on foreverrank.com.

Spec: `docs/superpowers/specs/2026-10-18-cute-guild-dashboard-design.md`.

## Global constraints

- Every client read under `pcall`; `C.Plain()` turns a secret value into nil before any string op or comparison.
- Never register COMBAT_LOG_EVENT_UNFILTERED. No secure frame changes in combat. No `C_SuperTrack`, no chat box opening.
- Game text is ASCII only (Friz Quadrata draws boxes for anything else). The harness fails on Unicode.
- Harness must end `layout problems: 0` and `OK`: `cd ~/foreverrank/tools/cute && luajit harness.lua`.
- Nothing leaves the GUILD addon channel. No server, no uploader in this plan.
- Names in test fixtures are made up; never real character names from uploads.

---

### Task 1: Addon skeleton, Core, and the harness bootstrap

**Files:** Create `tools/cute/Cute/Cute.toc`, `tools/cute/Cute/Core.lua`, `tools/cute/Cute/Bindings.xml`, `tools/cute/harness.lua` (widget mock, client factory, layout check, scenario runner).

- [ ] Write `Cute.toc` (Interface 16001, SavedVariables CuteDB, files in load order: Core, Stats, Sample, Roster, Policy, Comm, UI, Settings).
- [ ] Write `Core.lua`: `C.version`, `C.Safe`, `C.Plain`, `C.Print`, `C.Me()`, `C.Now()`, CuteDB defaults, event frame (ADDON_LOADED, PLAYER_ENTERING_WORLD, PLAYER_LOGOUT, PLAYER_GUILD_UPDATE), `/cute` slash (open, settings, errors, resend, me).
- [ ] Write `harness.lua` bootstrap: method whitelist, `newObj`, text width, BASE env (fonts, GameTooltip, secrets, C_Timer, CHAT_MSG_ADDON routing between clients, guild roster API), `newClient{name, realm, rank, class, level, ...}`, `tick(seconds)`, `fire(client, event, ...)`, `checkLayout`, ends with the layout count and OK.
- [ ] Harness test: loading the addon in two clients prints no error; `/cute` opens the window (asserted in Task 5).

### Task 2: Stat registry

**Files:** Create `tools/cute/Cute/Stats.lua`.

- [ ] `S.def(id, label, cat, o)` with validation (ASCII id ≤ 16, unique, cat in the four, kind in int/flag/text/list/pips, list needs `of`).
- [ ] Helpers: `counter(event)`, `money()`, `itemCount(id)`, `aura(spellIDs)`, `invLink(slot)`, `questSteps(ids)`, `legacyNodes`.
- [ ] The starter list (~120 stats) across leveling, prog, funny, officer, with `default = "self"` on the gear-gap, social and officer stats.
- [ ] Harness test: every entry validates; counts per category printed; every `read` survives (a) a client whose APIs all return secret values and (b) a client whose APIs all throw (stat reads nil, no error escapes).

### Task 3: Sampling and counters

**Files:** Create `tools/cute/Cute/Sample.lua`.

- [ ] Event registry from `on` fields; coalesce per stat to once a second; heartbeat every 300 s in slices of 20 stats per 0.5 s; full read at PLAYER_ENTERING_WORLD and PLAYER_LOGOUT.
- [ ] Counters persisted in `CuteDB.chars[me].counters`; 5-second ticker for standing still, ghost time and distance, taxi duration, AFK.
- [ ] Hooks: `hooksecurefunc("DoEmote")`, `hooksecurefunc("JumpOrAscendStart")`, `hooksecurefunc("SendChatMessage")`.
- [ ] Harness test: level-up event re-reads `level` within a second; heartbeat reads a heartbeat-only stat after 300 s and not before; PLAYER_DEAD increments `deaths` and persists across a reload of the client; DANCE emote increments `dance`.

### Task 4: Comm, Roster, Policy

**Files:** Create `tools/cute/Cute/Comm.lua`, `tools/cute/Cute/Roster.lua`, `tools/cute/Cute/Policy.lua`.

- [ ] Encoder: int base36 (sign), flag 1/0, text sanitized ASCII ≤ 24, list bitmap base36 over `of`, pips digits. Decoder inverse. Round-trip test over every registry entry with sample values.
- [ ] Messages `1D`, `1F` (chunked ≤ 250 bytes), `1R`, `1P`. Queue at one message a second; throttle codes wait 3 s.
- [ ] Roster: `CuteDB.roster[name]`, ranks from `GetGuildRosterInfo` after `GUILD_ROSTER_UPDATE`, two-miss prune, 200/90-day cap, "no addon" members from the guild roster.
- [ ] Policy: defaults from the registry; `1P` accepted only from officer rank at receipt and newer `at`; `Policy.CanSee(viewer, row, id)`.
- [ ] Harness tests: two clients exchange `1R`/`1F` and both rosters hold the other's level; a 120-stat full state fits in ≤ 6 chunks; a member's `1P` is ignored, an officer's applies; a login storm of 20 clients sends at most one message per client per second; prune needs two roster reads without the name.

### Task 5: The window

**Files:** Create `tools/cute/Cute/UI.lua`.

- [ ] Window: 1040×640, backdrop in slate with a gold edge, banner strip header with the logo, close button, resizable corner, remembered position; tabs Race, Prog, Hall of Shame, Officers (officers only), Me.
- [ ] Column renderer per `kind`; header sort; pinned Me row; class colours; XP bar; online/offline greying; "seen N days ago"; tooltip per cell.
- [ ] Hall of Shame cards (leader per stat); Officers tab summaries and controls; Me tab with the "what members see" toggle.
- [ ] Empty states.
- [ ] Harness tests: every tab opens for a member and for an officer with a 20-member roster; the Officers tab is absent for a member; an Only-you column is hidden for a member's view of others and present on their own row; layout check on each tab passes.

### Task 6: Settings

**Files:** Create `tools/cute/Cute/Settings.lua`.

- [ ] Everyone's: per-tab column checklist, density, show offline, minimap button, "my main", "my role".
- [ ] Officers': per-stat Everyone/Only you, threshold, Broadcast now, last changed line. Greyed for members.
- [ ] Harness tests: a member cannot toggle a visibility row; an officer's toggle plus Broadcast sends a `1P` the member applies; column checklist hides a column.

### Task 7: Minimap button, key binding, page and zip

**Files:** Modify `tools/cute/Cute/Core.lua` (minimap button), create `addons/cute/index.html`, `addons/cute/Cute.zip`, `tools/cute/README.md`.

- [ ] Minimap button with the logo, drag along the ring, click toggles the window; Bindings.xml `CUTE_TOGGLE`, `CUTE_SETTINGS`.
- [ ] Page: hero with the banner, download, three install steps, what is shared and the visibility rule, the stat categories, changelog; nav as the site's; noindex off (it is public).
- [ ] Zip: `(cd tools/cute && zip -rq ../../addons/cute/Cute.zip Cute -x "*.DS_Store")`.
- [ ] Harness: layout check on the window with the minimap button; render_layout screenshots for the page.
