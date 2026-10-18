# Cute: the guild dashboard

The in-game addon of <Cute>, the guild progging Forever's November release. Every member's client reads about a
hundred and ten facts about its own character, shares them with the guild over the game's addon channel, and shows the
whole guild in one window. Officers decide per stat whether members see each other's. No server, no uploader.

Design: `docs/superpowers/specs/2026-10-18-cute-guild-dashboard-design.md`. Plan: `docs/superpowers/plans/2026-10-18-cute-guild-dashboard.md`.

## Files

```
Cute/Core.lua       errors, Safe, Plain, saved variables, /cute, key bindings
Cute/Stats.lua      the registry: one S.def per stat (id, label, category, read or count or track, events, kind)
Cute/Sample.lua     reads stats on their events and a five-minute heartbeat; counters; the ticker; hooks
Cute/Roster.lua     the guild as the game lists it, joined with what each member's addon sent
Cute/Policy.lua     the officers' visibility list (Everyone or Only you per stat), who may send it
Cute/Comm.lua       the guild channel: deltas, full records in chunks, resend requests, the policy
Cute/UI.lua         the window: Race, Prog, Hall of Shame, Officers, Me; the minimap button
Cute/Settings.lua   columns per page, display, main and role; the officers' visibility list
Cute/art/           logo.png (the emblem, for the minimap), logo_wide.png (the header)
harness.lua         the mock client and every scenario
```

## Adding a stat

One line in `Stats.lua`:

```lua
D("fish", "Fish caught", "funny", { track = true, hint = "loot windows after a Fishing cast" })
D("gold", "Gold", "officer", { read = gold, on = "PLAYER_MONEY" })
```

`read` returns the value (under pcall; secret values read as nil), `count = "EVENT"` counts an event, `track = true`
is a value Sample.lua sets. `on` lists the events that re-read it; without it the heartbeat does. `kind` is int, flag,
text, list (bitmap over `of`) or pips. `default = "self"` hides it from members unless the officers open it.

## Test

```
cd tools/cute && luajit harness.lua
```

Must end `layout problems: 0` and `OK`. `--layout out.json` also writes every page's layout for render_layout.py.

## Ship

```
(cd tools/cute && rm -f ../../addons/cute/Cute.zip && zip -rq ../../addons/cute/Cute.zip Cute -x "*.DS_Store")
```

The page is `addons/cute/index.html`.
