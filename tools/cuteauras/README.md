# Cute Auras

A standalone addon on Cute's page (addons/cute/, the #auras section): the camp, your buffs, the group's buffs and
blessings and your biome gear on one bar, and alerts for what to put back after a death or a Hand. Built from
QuestBank's Camp.lua and Remind.lua. Design: docs/superpowers/specs/2026-11-23-cute-auras-design.md.

| Command | Does |
| --- | --- |
| `python3 -I tools/cuteauras/gen_data.py` | writes CuteAuras/Data.lua from the client's tables (research/wago/<build>, fetched with tools/fetch_wago.py), the site's item database and QuestBank's camp tables |
| `luajit tools/cuteauras/harness.lua` | the mock client's scenarios; must end with OK |
| `python3 -I tools/cuteauras/render.py` | the page's picture, mock.html to addons/cute/img/auras.webp (headless Chrome) |
| `python3 -I tools/cute/build.py` | packs addons/cute/CuteAuras.zip beside Cute.zip, stamps its version and size, checks the zip is the tree |

The version lives in CuteAuras.toc and Core.lua's A.version (build.py checks they agree).

In the game: `/cauras` (the window: Settings, Consumables, Blessings, Biome gear), `/cauras consumables`, `/cauras test`,
`/cauras move`, `/cauras diag`, `/cauras errors`. QuestBank 6.4.9 and Cute 0.9.10 step their camp and buff reminders
aside while it is loaded.
