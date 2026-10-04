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
- `Discover.lua`: what the game shows while you quest (quests, the NPCs who give and take them and where they stand, offers, chains, XP, reward items), in `QuestBankDB.disc`, stamped with the client's build and interface number.
- `Game.lua`: on the Forever client only (interface 16xxx), and while Settings' "Note items and spells you see" is ticked: per class and race the spells learned and the items worn and carried, and the tooltips of the weapons, armor and recipes the game shows (at most 1,000, read again after six hours), in `QuestBankDB.game`. No names. Unticking the box clears what was noted, since `QuestBank.lua` is uploaded whole. It also takes over, once, the notes of the addon it replaces, and once they are in, tells players still running that one that its folder can go.
- `Model.lua`: Forever quest XP, travel over the flight network, and the route planner (planned a few milliseconds a frame).
- `Pins.lua`, `Pins.xml`: numbered pins on the world map and the waypoint that follows the route.
- `Sync.lua`: sharing banks, plans, runs and reported XP with QuestBank users in the party and guild.
- `UI.lua`: the window with its five pages (Quest Log, Plan, Hand-in Route, Party, Settings), the post box, and the minimap button.

The data, all raw inputs in `research/` (gitignored):

- `travel.py` builds each faction's travel network from the Forever client's taxi tables (`research/wago/<build>/`, fetched by `tools/fetch_wago.py`) and knows where Forever redrew a map (`research/wago/era/UiMapAssignment.csv`).
- `cmangos.py` extracts chains, quest givers, spawn points and item starts from `research/cmangos/ClassicDB.sql.gz` (github.com/cmangos/classic-db, Full_DB) into `research/questbank/cmangos.json`.
- `gen_data.py` writes `QuestBank/Data.lua` from those, the Wowhead Forever quest data (`all3.json`, `det2.json`, `det3.json`, `wowhead.json`, `extra.json`) and NPC tooltips (`npcloc.json`; `--fetch` reads the missing ones through `npcloc.py`). Every icon and texture is checked against the client manifest. It also writes `GAPS.md`, the list of quests it can't fully plan yet.
- `../probe_pull.py` pulls players' uploads from the Worker (QuestBank.lua SavedVariables, and the older formats old installs still send) and merges every discovery into `research/questbank/disc.json`, votes kept, with `QuestBankDB.game` in its "probe" part for `apply_probe_spells.py` and `scavenge_items.py`; `gen_data.py` reads it: a quest anyone met in Forever is no longer "Classic only", and quests seen in game but missing from the catalog are listed in `GAPS.md`. `--merge FILE` takes a file by hand, `--selftest` checks the parser against `tools/fixtures/probe/`.
- `harness.lua` loads the addon into mocked clients (an Alliance paladin with a full bank, a friend at 18, a Horde shaman, a level-3 priest, a night elf mage with older notes to take over, a priest who left the notes box unticked, and a dwarf on Classic Era), drives every page, syncs the party between them, lays the window out like the game and reports clipped or overlapping text, and fails on any widget method outside a whitelist of real API methods. The Forever client's spellbook, item, tooltip, loot and vendor APIs are mocked, and so are the values it hides from addons.

Rebuild and publish:

```
python3 tools/probe_pull.py            # admin key in worker/.probe-admin-key
python3 tools/questbank/cmangos.py
python3 tools/questbank/objectives.py  # objective and quest-item spots (map icons) from the Classic data
python3 tools/questbank/gen_data.py --fetch
python3 tools/questbank/gen_data.py --selftest-os   # players' objective spots: merge, slots, encoding
(cd tools/questbank && luajit harness.lua)
(cd tools/questbank && rm -f ../../questbank/QuestBank.zip && zip -rq ../../questbank/QuestBank.zip QuestBank)
python3 tools/build_uploader.py       # questbank/QuestBank-Uploader.zip: the Windows uploader with this QuestBank folder
```

XP model: Forever quest XP = the base from the game's QuestXP table (identical to Classic) x the quest's multiplier (from each Wowhead Forever quest page), then the Classic grey rule (full to 5 levels above, 80/60/40/20%, 10% from 10 above), rounded the way the server does (to 5 up to 100, to 10 up to 500, to 25 up to 1,000, to 50 above). When the game reports a quest's XP (quest log below the cap, the quest window, a hand-in), that number wins. Since 2026-10-01 (the level-30 build) dungeon quests pay "50% less extra experience beyond normal quest values"; gen_data.py applies 1 + (mult - 1) x NERF (0.5) to every multiplier above 1 read before that date and sets flag 256, until Wowhead Forever's pages are re-read (then NERF = 1, READ = that date). What the game paid after the cut (players' hand-ins and own quest-window readings, merged by probe_pull.py into disc.json's "seen" votes, build >= NERF_BUILD) confirms or overrides each number: flag 512, and GAPS.md lists the corrections.
