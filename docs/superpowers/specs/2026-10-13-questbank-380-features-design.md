# QuestBank 3.8.0: timers, links, the decide-yourself key, context profiles

Roadmap step 5 (docs/superpowers/specs/2026-10-12-observer-and-roadmap-design.md). Pure addon work with no
dependency on the observer. Everything here is tested in tools/questbank/harness.lua.

## 1. Timers (Clock.lua)

What is kept, per character, in `QuestBankDB.chars[key].clock`:
- `levels[lvl] = { at = time(), played = seconds logged in at that level }`: `at` is written on PLAYER_LEVEL_UP for
  the new level (and at first login for the current one when missing); `played` accumulates on logout, level-up and
  every minute while logged in, from GetTime() deltas.
- `quests[qid] = { a = accepted time(), d = done time() }`: QUEST_ACCEPTED sets `a` (the id when the client gives
  it plainly; secret ids are skipped), QUEST_TURNED_IN sets `d`. Capped at 300 quests, oldest `d` dropped first.

What is shown:
- A small movable strip, off by default (`settings.clock = { show = false, x, y }`), one line:
  `Lvl 31 · 1h 12m` (time logged in at this level) `· quest 8m` (the oldest quest in the log accepted this session,
  or the one being tracked) `· run 23m, 9 q` (only during a hand-in run). Updates once a second from a ticker
  that only runs while the strip is shown. Right-click: hide. Drag: move. Saved position survives /reload.
- Quest tooltips in QuestBank's own window gain one grey line when known: "Took 12 min" after a hand-in, or
  "Accepted 8 min ago" while in the log.
- Settings, under a new "Timers" heading: "Show the timer strip" and "Time per level in the level-up message"
  (`settings.clockLevelMsg`, on by default: at level-up QuestBank prints "Level 31 in 1h 12m of play.").

Not in scope: XP per hour forecasts (the Route page has its own pace), /played totals.

## 2. Links (Link.lua)

- QuestBank's own chat links: `|Haddon:QuestBank:quest:<id>|h[Name]|h` coloured gold. Printed wherever QuestBank
  names a quest in chat (the level-up and run messages, `/qb next`, discoveries). On the Forever client
  the click comes through `EventRegistry:RegisterCallback("SetItemRef", ...)`; on Classic Era through
  `hooksecurefunc("SetItemRef", ...)`; both guarded by existence. These links are local: the client never sends
  addon links to other players, so party and guild posts keep using the game's own quest links as today.
- Click: the quest's context menu (`UI.QuestMenu`), the same one the window shows on right-click: waypoint, pick-up
  list, link in chat. Shift-click with a chat box focused: the game's quest link goes into the box.
- Item links: a post-call on item tooltips (the processor Game.lua already uses) adds "Reward of: Quest (L31)"
  lines for items in `D.RITEMS`, up to three quests, with the quest's zone. A reverse index item -> quests is built
  once on first use. Works on bag items, chat links and the ItemRef window alike. Classic Era: no post-call API,
  so nothing is added there.

## 3. The decide-yourself key

- `settings.autoKey = "shift"` (shift, ctrl, alt, none). Auto.lua's `byHand()` reads it instead of hard-coding
  Shift. "none" means the auto actions can never be skipped by a key.
- Settings, under the existing auto-accept rows: "Hold [Shift v] to decide a quest yourself" as a cycle button.

## 4. Context profiles

- `settings.profiles = { dungeon = {}, pvp = {}, party = {}, cap = {} }`. Each may hold overrides for
  `autoAccept`, `autoTurnIn`, `sayAccept`, `sayComplete`, `clockShow`; a missing key inherits the base setting.
- `QB:Opt(key)` resolves: the first active context in the order dungeon, pvp, party, cap that has the key, else
  `QB:Settings()[key]` (for `clockShow`: `settings.clock.show`). Contexts: dungeon = IsInInstance() with kind
  party or raid; pvp = kind pvp or arena, or GetZonePVPInfo() in {combat, hostile}; party = IsInGroup(); cap =
  QB:Lock() (held at a level cap). Every read goes through QB.Plain.
- Auto.lua, the say-lines and the clock strip read `QB:Opt` instead of `Settings()[key]`.
- Settings: a "When you are..." block with four rows (In a dungeon, In a PvP zone, In a party, At a level cap);
  each row has five tri-state buttons (Accept, Hand in, Say accept, Say done, Timer strip) cycling
  inherit -> on -> off, drawn as "–", a tick, a cross. A line under the block says which context is active now.

## Versions and release

3.8.0. Harness tests per module. Zips rebuilt, uploader test run, questbank/index.html release notes as lead
plus bullets, SOURCES.md untouched (no new data source).
