# QuestBank

The free questing addon behind https://foreverrank.com/questbank/ (an unlisted page). Both factions, levels 1 to 60:
what every quest pays at your level, which chains to carry on, the best quests near you, the hand-in route with map
pins, party sync, and banking with a hand-in run when the game holds your level at a cap (QB:Mode() "lock", "rush",
"quest"). Wowhead Forever's quests seed the catalog up to the beta's cap; above it the CMaNGOS Classic database does,
flagged "Classic only" until players see the quests in Forever.
Free software under the GPL-3.0 (`QuestBank/LICENSE.txt`): its quest chains and spawn points come from the
CMaNGOS Classic database, which is GPL-3.0.

The addon, `QuestBank/`:

- `Data.lua` (generated): the quest catalog, NPCs, flight network, categories, textures and icons.
- `Core.lua`: game state, quest status, the plan, the hand-in run, the XP the game reports, settings, events, export.
- `Model.lua`: Forever quest XP, travel over the flight network, and the route planner (planned a few milliseconds a frame).
- `Pins.lua`, `Pins.xml`: numbered pins on the world map and the waypoint that follows the route.
- `Sync.lua`: sharing banks, plans, runs and reported XP with QuestBank users in the party and guild.
- `UI.lua`: the window with its five pages (Quest Log, Plan, Hand-in Route, Party, Settings), the post box, and the minimap button.

The data, all raw inputs in `research/` (gitignored):

- `travel.py` builds each faction's travel network from the Forever client's taxi tables (`research/wago/<build>/`, fetched by `tools/fetch_wago.py`) and knows where Forever redrew a map (`research/wago/era/UiMapAssignment.csv`).
- `cmangos.py` extracts chains, quest givers, spawn points and item starts from `research/cmangos/ClassicDB.sql.gz` (github.com/cmangos/classic-db, Full_DB) into `research/questbank/cmangos.json`.
- `gen_data.py` writes `QuestBank/Data.lua` from those, the Wowhead Forever quest data (`all3.json`, `det2.json`, `det3.json`, `wowhead.json`, `extra.json`) and NPC tooltips (`npcloc.json`; `--fetch` reads the missing ones through `npcloc.py`). Every icon and texture is checked against the client manifest. It also writes `GAPS.md`, the list of quests it can't fully plan yet.
- `../probe_pull.py` pulls players' uploads from the Worker (ForeverProbe exports, ForeverProbe.lua and QuestBank.lua SavedVariables, all carrying QuestBankDB.disc) and merges every discovery into `research/questbank/disc.json`, votes kept; `gen_data.py` reads it: a quest anyone met in Forever is no longer "Classic only", and quests seen in game but missing from the catalog are listed in `GAPS.md`. `--merge FILE` takes a file by hand, `--selftest` checks the parser against `tools/fixtures/probe/`.
- `harness.lua` loads the addon into three mocked clients (an Alliance paladin with a full bank, a friend at 18, a Horde shaman), drives every page, syncs the party between them, lays the window out like the game and reports clipped or overlapping text, and fails on any widget method outside a whitelist of real API methods.

Rebuild and publish:

```
python3 tools/probe_pull.py            # admin key in worker/.probe-admin-key
python3 tools/questbank/cmangos.py
python3 tools/questbank/gen_data.py --fetch
luajit tools/questbank/harness.lua
(cd tools/questbank && rm -f ../../questbank/QuestBank.zip && zip -rq ../../questbank/QuestBank.zip QuestBank)
```

XP model: Forever quest XP = the base from the game's QuestXP table (identical to Classic) x the quest's multiplier (from each Wowhead Forever quest page), then the Classic grey rule (full to 5 levels above, 80/60/40/20%, 10% from 10 above), rounded to 10 below 1,000 and 50 above. When the game reports a quest's XP (quest log below the cap, the quest window, a hand-in), that number wins.
