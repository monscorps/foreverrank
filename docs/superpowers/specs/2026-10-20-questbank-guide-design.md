# QuestBank 6.0: the Guide, on by default

Date: 2026-10-20. Owner's words: "I still don't feel we give an out-of-the-box option that is better than RestedXP and
Questie for people who want to level based on all the data we have." Approved direction: "sure go at it".

Builds on QuestBank 5.4.4, which gives every part of the addon one shared target that is kept unless a new one is
clearly better, re-plans only on real events, plans with the flight paths the character knows, and guides on Zephras
Isle. 6.0 starts when 5.4.4 is committed.

## Why

Research on 2026-10-20 (competitor defaults read from their source, CurseForge pages, Blizzard forums, GitHub
issues):

- RestedXP, Zygor and Guidelime are hand-written step lists. Forever's beta has been capped at level 30 since
  1 October, so nobody could write a Forever route for 30-60: RestedXP covers 1-35 (paid past 20) and falls back to
  Classic Era routes for 35-60 until after launch; Guidelime's free Forever guide covers 12-30. Their top complaint is
  rigidity: start at level 1 and follow, or the guide breaks.
- Questie is a map of quests, not a guide: no route, no arrow without TomTom, auto accept and hand-in off, party-chat
  progress spam on by default, 80 MB of memory, Forever data from a 10 October snapshot.
- The closest free rival is BuddiesQuestForever (beta, 2.5K downloads): an arrow through flights and boats, time to
  the next level, buddy progress, opt-in data uploads.
- QuestBank today is a planner you open, not a guide that runs: a fresh install opens no window, the arrow is off,
  auto accept and hand-in are off, the arrow's route covers only finished quests, nothing joins pick-up, objectives
  and hand-in into one next step, the minimap shows only the player's own pick-up list, and Settings open on banking.

QuestBank computes its route from data, so it can guide 1-60 on launch day and re-plan from whatever the player has
done. That is the pitch nobody else can make. 6.0 makes it the default experience.

## What the player sees on first login

- **A step frame**, small, movable, in QuestBank's slate style: the current step in one line ("Accept Kobold Camp
  Cleanup from Marshal McBride", "Kill Kobold Vermin 3/8", "Hand in Kobold Camp Cleanup"), the next two steps
  greyed beneath, a quest-item button when the step needs one, and a small "about 14 min to level 6" line. A click
  on a step opens it in the window; right-click skips it ("not now") or drops the quest from the plan.
- **The arrow on**, pointing at the step's spot. When the player is dead it points at the corpse
  (C_DeathInfo.GetCorpseMapPosition, DeathInfoDocumentation.lua:11) and says so.
- **Auto accept and hand-in on**, for the plan's quests only; Shift held pauses it; a hand-in with a reward choice
  stops and marks the best choice (the Gear finder's pick) without choosing it.
- **One welcome line**: "QuestBank is guiding you. /qb opens the full window; right-click the step frame for its
  options." No other chat lines from QuestBank unless the player asks.
- **Existing players** (a 5.x saved file) see one question in the step frame instead: "Let QuestBank guide you?
  Yes / Not now". "Not now" leaves their settings as they were; the step frame then stays hidden until they switch
  the Guide on in Settings.

## The step engine (Guide.lua, no UI)

One engine, separate from every frame, so Cute's leveling module can reuse it later.

- **Input:** the quest log (objectives and their progress), completed quests, level and XP, known flight paths, the
  hearth's place and cooldown, bag space, the party, and the catalog (Data.lua) with live readings.
- **Picking quests:** the quests Now already ranks best by XP per minute (UI.lua's questing score: XP plus half the
  chain, over trip and hand-in minutes, weighed by drop rates) fill the plan automatically, up to the log's free
  slots minus two, never a quest more than two levels above the player, never grey unless its chain leads somewhere
  better. The pick-up list the player builds by hand still works and always wins.
- **Steps:** each planned quest yields pick-up, its objectives (grouped by spot: D.SPOT and D.OBJ centres, clustered
  within 150 yards as the Route page's "Do now" does), and hand-in. The planner (Model.lua) orders the stops; the
  engine interleaves objective spots on the way, so a step list reads "accept A, accept B, kill for A, loot for B,
  hand in A and B". Travel steps come from Travel.lua (known flights, boats, the hearth).
- **Train steps:** when the player levels to a level where the class has new spells (codex spellbook levels) and a
  trainer of the class is known near the route, a "Train at <name>" step is added before the next town hand-in.
  Trainer places come from a new seed (class trainers from the CMaNGOS spawns gen_data.py already reads, offline) and
  are learned in play from TRAINER_SHOW (NPC, place, class), as Discover.lua learns NPCs today. No trainer known: a
  one-line reminder instead of a step.
- **Done by itself:** a step completes when the game says so (quest accepted, objective count reached, quest handed
  in, flight taken, level reached). A quest done out of order, a chain started elsewhere, a character starting at
  level 23: the engine plans from the state, never from a fixed list.
- **Stable:** the engine's first step is 5.4.4's shared target; it changes only on a real event and only when the
  new plan is clearly better. Skips are remembered per character for an hour ("not now") or for good ("drop").
- **Grinding:** when nothing worth taking is left within reach, one step says so plainly with the nearest place where
  the plan resumes ("Kill around Brightwood Grove until level 23, then Darkshire").
- **Budget:** bounded work per re-plan, no per-frame allocation, the same memory and garbage gates as 5.4.2.

## The map, matched with Questie

- Every quest the player can take now (faction, class, race, level, prerequisites done, not excluded) shows a ! on
  the minimap within its range, and a ? where a quest in the log is handed in. Pins within 30 yards of each other
  merge into one with a count; at most 40 on the minimap, nearest first.
- Objective areas for quests in the log (the game's blue blob, as today), finished objectives dropped (5.4.4).
- Mob and object tooltips show "Kobold Vermin: 3/8 (Kobold Camp Cleanup)" for quests in the log, and party members'
  progress where Sync knows it (TooltipDataProcessor.AddTooltipPostCall, unit and object types; the unit's GUID read
  through C.Plain, nothing shown when it is secret).
- The world map keeps 5.4.1's layer (game POI pins, ! and ?).

## Only QuestBank

- **Forever-correct XP:** per-quest multipliers, the 1 October dungeon cut, the server's rounding, live readings.
- **Time to level:** "about 14 min to level 23" from the plan's XP and minutes and the player's measured XP an hour
  (Timer.lua) once there are ten minutes of play; before that, from the plan alone and marked "about".
- **Party:** the engine prefers quests party members hold or can take (Sync), and the step frame shows each member's
  step under the player's when grouped. Pacing the plan to the slowest member is out of scope for 6.0.
- **Day one 1-60:** every level band has candidates (518 quests at 1-9 ... 524 at 50-59 in Data.lua); 1,441 Classic
  rows have no Forever multiplier yet: their XP shows "about" and live readings replace it.

## Settings

- The Settings page opens with "Guide": on/off, auto accept/hand-in, the step frame (shown, locked, scale), the arrow,
  minimap quest givers.
- Then "Map and minimap", then one switch per module with its details inside (interact light, camp bar, far zoom,
  golden path), then "Data you share", then "Banking" last.
- Nothing QuestBank sets in the game's own options (interact icons, status text) is changed by the Guide; those stay
  with their modules.

## Not in 6.0

Nameplate icons, a pace comparison with other players (needs aggregated timings from uploads first), crowding
warnings, death-spot warnings, choosing dungeons into the route (dungeon quests already rank; dungeon runs are
Cute's report), pacing to the slowest party member.

## Testing

Harness scenarios (tools/questbank/harness.lua), each with the memory and garbage gates:
- a fresh install: welcome line, step frame on, arrow on, auto on for planned quests only, nothing else in chat;
- a 5.x saved file: the one question, both answers;
- a level-1 human in Northshire through the first hand-ins: steps in order, each completing by itself;
- a level-23 character mid-chain with quests from three zones: a sensible first step, no step for a quest it cannot
  take;
- out of order: an objective finished before its pick-up step, a quest handed in that the plan had later;
- death: the arrow to the corpse and back;
- a party of two: shared quests first, each member's step shown;
- Zephras Isle at level 5;
- the Southshore-to-Alterac walk: the step does not change without a real event;
- nothing worth taking in reach: the grind step;
- a reward choice: stops, marks, does not choose.
Layout checks for the step frame at its scales, render_layout sheets for the page.

## The page

The QuestBank page leads with the first five minutes: the step frame, the arrow, "1-60 on launch day, computed from
Forever's own data". One release-notes line for 6.0. No catalogue of features.
