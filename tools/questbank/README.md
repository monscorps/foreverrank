# QuestBank

The in-game quest bank planner behind https://foreverrank.com/questbank/ (an unlisted page).

- `QuestBank/` is the addon: `Data.lua` (generated), `Core.lua` (game state, events, export), `Model.lua` (Forever quest XP and the route planner), `UI.lua` (the window).
- `gen_data.py` writes `QuestBank/Data.lua` from the raw inputs in `research/questbank/` (gitignored): Wowhead Forever quest data (`wowhead.json`, `extra.json`, `det2.json`), NPC locations (`npcloc.json`, refreshed by `npcloc.py`), and the client texture manifest (`manifest.json`, build 1.60.1.70009). Every icon and texture it references is checked against the client files.
- `harness.lua` loads the addon into a mocked client, drives every page, and fails on any widget method outside a whitelist of real API methods: `luajit tools/questbank/harness.lua`.

Rebuild and publish:

```
python3 tools/questbank/gen_data.py
luajit tools/questbank/harness.lua
(cd tools/questbank && rm -f ../../questbank/QuestBank.zip && zip -rq ../../questbank/QuestBank.zip QuestBank)
```

XP model: Forever quest XP = Classic base x the quest's multiplier (from each Wowhead Forever quest page), then the Classic grey rule (full to 5 levels above, 80/60/40/20%, 10% from 10 above), rounded to 10 below 1,000 and 50 above.
