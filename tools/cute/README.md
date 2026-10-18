# Cute: the guild dashboard

The in-game addon of <Cute>, the guild progging Forever's November release. Every member's client reads about a
hundred facts about its own character, shares them with the guild over the game's addon channel, and shows the
whole guild in one window. Officers decide per stat whether members see each other's. No server, no uploader.

Design: `docs/superpowers/specs/2026-10-18-cute-guild-dashboard-design.md`. Plan: `docs/superpowers/plans/2026-10-18-cute-guild-dashboard.md`.

## Files

```
Cute/Core.lua       errors, Safe, Plain, Get (every result, plain; a missing function says so), saved variables, /cute, /cute api, key bindings
Cute/Stats.lua      the registry: one S.def per stat (id, label, category, read or count or track, events, kind)
Cute/Sample.lua     reads stats on their events and a five-minute heartbeat; counters; the ticker; hooks
Cute/Roster.lua     the guild as C_Club lists it, joined with what each member's addon sent
Cute/Policy.lua     the officers' visibility list (Everyone or Only you per stat), who may send it
Cute/Comm.lua       the guild channel: deltas, full records in chunks, resend requests, the policy
Cute/UI.lua         the window: Race, Prog, Hall of Shame, Officers, Me, Settings; the minimap button
Cute/Settings.lua   columns per page, display, main, role and raid spec; the officers' visibility list
Cute/art/           logo.png (the emblem, for the minimap), logo_wide.png (the header)
harness.lua         the mock client and every scenario
page_stats.lua      writes addons/cute/stats.js from the registry and UI.lua's defaults
build.py            builds, stamps and checks the page (see Ship)
```

## Adding a stat

One line in `Stats.lua`:

```lua
D("fish", "Fish caught", "funny", { track = true, hint = "loot windows after a Fishing cast" })
D("gold", "Gold", "officer", { read = money, fmt = goldOf, on = "PLAYER_MONEY" })
```

`read` returns the value (under pcall; secret values read as nil), `count = "EVENT"` counts an event, `track = true`
is a value Sample.lua sets. `on` lists the events that re-read it; without it the heartbeat does. `kind` is int, flag,
text, list (bitmap over `of`) or pips. `fmt` formats the cell (hours, percent, gold from copper). `slow = true` marks a
stat that changes every few seconds (time played, XP into the level): it travels on Comm's two-minute flush, not as it
ticks. `default = "self"` hides it from members unless the officers open it.

A `read` may only call what Forever's generated API docs list (`research/wow-ui-source-forever/.../Blizzard_APIDocumentationGenerated`),
what QuestBank reads on this client (`GetInventoryItemLink`, the taxi nodes) or what Blizzard's own Camelot UI code
calls. Three globals no doc lists are read on that last ground: `GetInventoryItemDurability` and `GetInventoryItemCount`
(Camelot's equipment flyout reaches them through `EquipmentManager_GetItemInfoByLocation`) and `GetNumUnspentTalents`
(the mainline `TalentFrameBase.lua` the camelot game type loads). The harness mocks the documented set, the QuestBank
set and those three, each named in its `UNDOCUMENTED` table with its evidence; a mock without an entry there is
refused, and the first scenario fails on any stat that reads nil. `/cute api` prints which of the undocumented
functions the live client has (`DoEmote` and the never-mocked `GetAverageItemLevel` included), a line to paste; a
stat that reads a missing one shows "?" with "X is missing on this client" in its tooltip, on the Me page and under
`/cute errors`. Pass a global to `Get` and `Num` by name (`Num("UnitLevel", "player")`) so that holds for it too. Gold
stats keep copper and show gold. Role and raid spec are per character; the main is account-wide.

## Test

```
cd tools/cute && luajit harness.lua
```

Must end `layout problems: 0` and `OK`. Fifteen scenarios: the registry on the documented client (the item level
averaged over the items worn), secret and throwing reads and a client missing a function (the reason in the tooltip,
on the Me page, under `/cute errors` and in `/cute api`), the encoder and what comes in, the hello, deltas and the slow
flush, the policy (including before the roster and on a fresh install), counters across a reload and a week turning
between sessions, the roster through C_Club, every page at 1040x640 and 760x420 for an officer and
a member, settings clicks, a twenty-client login storm, the throttle and a dropped message, a guildless client, the
trackers (XP pace across a ding, copper gold, grey sales, recipes, the day and the week, emotes with and without
DoEmote, guild lines counted as sent), and the calls Cute never makes. `--layout out.json` also writes every page's
layout for `tools/questbank/render_layout.py` (python3 -I tools/questbank/render_layout.py out.json out.html).

## Ship

```
python3 tools/cute/build.py
```

One command, nothing typed by hand: it zips the addon (the same `zip -rq ... Cute -x "*.DS_Store"` as before; `--no-zip`
keeps the zip you have), regenerates `addons/cute/stats.js` from the registry and the window's defaults
(`page_stats.lua`), stamps the version from `Cute.toc`, the zip's size in KB and the stat counts into
`addons/cute/index.html` between `<!--@name-->` markers, then checks the page: every link and image exists, every class
is `cu-` and none collides with `forever.css`, no hand-typed version or placeholder is left, the changelog's newest
entry is the toc's version, the greys pass 4.5:1, and the Download button is dark text on a light button through the
whole cascade. It ends `problems: 0` and `OK`, or lists the problems and exits 1. `--online` also fetches the external
links. The page is `addons/cute/index.html`; `#prog`, `#officers` or `#settings-officer` on its URL opens the mock on
that page.
