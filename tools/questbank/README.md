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
- `Game.lua`: on the Forever client only (interface 16xxx), and while Settings' "Note items, spells and loot" is ticked: per class and race the spells learned and the items worn and carried, and the tooltips of the weapons, armor and recipes you loot, carry or see: every item a loot window shows (through `Loot.lua`) or the game announces to the group as a boss drop, everything worn and carried (looked through at login and a few seconds after the bags change), vendors' wares and anything hovered, read two every half second out of combat; a server-sent item the client hasn't loaded is asked for (`C_Item.RequestLoadItemDataByID`, read on `ITEM_DATA_LOAD_RESULT`) and nothing half-read is kept: a tooltip the server hasn't filled in, one the client returns nothing or no lines for, or one with a line or a line's text hidden is read again a few times and otherwise left for the next sweep (at most 1,000 kept, read again after six hours), in `QuestBankDB.game`. No names. Unticking the box clears what was noted, since `QuestBank.lua` is uploaded whole. It also takes over, once, the notes of the addon it replaces, and once they are in, tells players still running that one that its folder can go.
- `Loot.lua`: on the Forever client only, under the same box: which creature or chest dropped which items, by id, with the dungeon, difficulty and boss fight (or the map outdoors; neither when the client hides the place); at most 400 sources and 40 items each, in `QuestBankDB.disc.loot`. It only reads the loot window (never takes, closes or rolls), and keeps no name: the site names the ids through the client's encounter table and the Classic database. Unticking the box clears these too.
- `Model.lua`: Forever quest XP, travel over the flight network, and the route planner (planned a few milliseconds a frame).
- `Pins.lua`, `Pins.xml`: numbered pins on the world map, drawn as QuestBank's own frames on the map canvas (not the canvas's pins, whose AcquirePin runs a call the game blocks in combat), and the switch that lets Ctrl+clicks through to the game's own map pin.
- `QuestMap.lua`: the quest icons on each zone's map (where quests start and end, objective areas, quest items), on the same layer.
- `Arrow.lua`: the direction arrow. Waypoints are QuestBank's arrow, or the real TomTom's; QuestBank never sets the game's own waypoint, it prints a link that does when the player clicks it (`Core.lua`, `API.SetWaypoint`).
- `Auto.lua`: accepting and handing in quests at NPCs when Settings say so. The game's escort prompt is left to the player.
- `Sync.lua`: sharing banks, plans, runs and reported XP with QuestBank users in the party and guild.
- `UI.lua`: the window with its five pages (Quest Log, Plan, Hand-in Route, Party, Settings), the post box, and the minimap button.

The data, all raw inputs in `research/` (gitignored):

- `travel.py` builds each faction's travel network from the Forever client's taxi tables (`research/wago/<build>/`, fetched by `tools/fetch_wago.py`) and knows where Forever redrew a map (`research/wago/era/UiMapAssignment.csv`).
- `cmangos.py` extracts chains, quest givers, spawn points and item starts from `research/cmangos/ClassicDB.sql.gz` (github.com/cmangos/classic-db, Full_DB) into `research/questbank/cmangos.json`.
- `gen_data.py` writes `QuestBank/Data.lua` from those, the Wowhead Forever quest data (`all3.json`, `det2.json`, `det3.json`, `wowhead.json`, `extra.json`) and NPC tooltips (`npcloc.json`; `--fetch` reads the missing ones through `npcloc.py`). Every icon and texture is checked against the client manifest. It also writes `GAPS.md`, the list of quests it can't fully plan yet. From the client's quest table (QuestV2) it takes the completion bits: quests that share one are done together, so they rule each other out (D.EXCL). Quests no list has yet are written by hand in `HAND`, and what Blizzard's notes changed that nobody has read since gets a tooltip line (D.NOTE), each with its source beside it in the code.
- `npcloc.py --quests=ID,...` reads Wowhead Forever's quest tooltips into `qtips.json` (name, text and what the quest asks for: no level, XP or NPC id). `lookfor.json` holds the ids of quests we went looking for; GAPS.md says for each one still missing why. Wowhead's quest pages (`mapper.py`) have turned scripts away since 2026-10-04 (CloudFront "Request blocked", again on 2026-10-08), while nether.wowhead.com's tooltips answer. Every Wowhead request, from both scripts, keeps 3.2 s from the last.
- `../probe_pull.py` pulls players' uploads from the Worker (QuestBank.lua SavedVariables, and the older formats old installs still send) and merges every discovery into `research/questbank/disc.json`, votes kept, with `QuestBankDB.game` in its "probe" part for `apply_probe_spells.py` and `scavenge_items.py`, and who dropped what (`disc.loot`) into its "loot" part, votes per upload, for `apply_loot.py`; `gen_data.py` reads it: a quest anyone met in Forever is no longer "Classic only", and quests seen in game but missing from the catalog are listed in `GAPS.md`. `--merge FILE` takes a file by hand, `--selftest` checks the parser against `tools/fixtures/probe/`.
- `harness.lua` loads the addon into mocked clients (an Alliance paladin with a full bank, a friend at 18, a Horde shaman, a level-3 priest, a night elf mage with older notes to take over, a priest who left the notes box unticked, a dwarf hunter looting in Elwynn and the City of Dalaran, and a dwarf on Classic Era), drives every page, syncs the party between them, lays the window out like the game and reports clipped or overlapping text, fails on any widget method outside a whitelist of real API methods, and scans the addon's code for calls the game would block (the loot window's actions among them). The Forever client's spellbook, item, tooltip, loot (slots, sources, encounters), instance and vendor APIs are mocked, and so are the values it hides from addons and the fight (`InCombatLockdown`, the addon restrictions).

Rebuild and publish:

```
python3 tools/probe_pull.py            # admin key in worker/.probe-admin-key
python3 tools/questbank/cmangos.py
python3 tools/questbank/objectives.py  # objective and quest-item spots (map icons) from the Classic data
python3 tools/questbank/gen_data.py --fetch
python3 tools/questbank/gen_data.py --selftest-os   # players' objective spots: merge, slots, encoding
python3 tools/apply_loot.py   # players' loot sources into codex/loot.json, after scavenge_loot.py
(cd tools/questbank && luajit harness.lua)

(cd tools/questbank && rm -f ../../questbank/QuestBank.zip && zip -rq ../../questbank/QuestBank.zip QuestBank -x "*.DS_Store")
python3 tools/build_uploader.py       # questbank/QuestBank-Uploader.zip: the Windows uploader with this QuestBank folder
python3 tools/build_uploader.py --test   # its checks in Docker (mcr.microsoft.com/dotnet/sdk:8.0)
```

XP model: Forever quest XP = the base from the game's QuestXP table (identical to Classic) x the quest's multiplier (from each Wowhead Forever quest page), then the Classic grey rule (full to 5 levels above, 80/60/40/20%, 10% from 10 above), rounded the way the server does (to 5 up to 100, to 10 up to 500, to 25 up to 1,000, to 50 above). When the game reports a quest's XP (quest log below the cap, the quest window, a hand-in), that number wins. Since 2026-10-01 (the level-30 build) dungeon quests pay "50% less extra experience beyond normal quest values"; gen_data.py applies 1 + (mult - 1) x NERF (0.5) to every multiplier above 1 read before that date and sets flag 256, until Wowhead Forever's pages are re-read (then NERF = 1, READ = that date). What the game paid after the cut (players' hand-ins and own quest-window readings, merged by probe_pull.py into disc.json's "seen" votes, build >= NERF_BUILD) confirms or overrides each number: flag 512, and GAPS.md lists the corrections. The 2026-10-08 build raised the XP of dungeon kills by about 20% and works out party XP from each player's own level again (Blizzard's notes); neither touches quest XP, and QuestBank models quest XP only. That build did change Elixir of Pain's XP and raise the level of the quests around Bandarion Keep; until players' quest logs show the new numbers, D.NOTE says so in their tooltips.
