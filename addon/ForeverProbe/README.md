# ForeverProbe

Reads your character for [foreverrank.com](https://foreverrank.com). Quiet,
read-only, nothing automated, nothing sent anywhere on its own.

## Install, three steps

1. Download and unzip. You get this `ForeverProbe` folder, plus an
   optional `Companion` folder (Windows auto-upload to foreverrank.com).
2. Drop `ForeverProbe` into the Forever beta's `Interface/AddOns/` folder, the same one QuestBank goes in
   (usually `World of Warcraft/_classic_beta_/Interface/AddOns/`), so you end up with
   `Interface/AddOns/ForeverProbe/ForeverProbe.toc`. If the character screen calls it out of date, tick
   **Load out of date AddOns**.
3. Restart the game. Done. A small pace bar appears at the top of the screen.
   Want the uploads automatic? Double-click `Companion/Install.bat`; details
   in `Companion/README.txt`.

## What you get

- A pace bar: level, percent, XP per hour, time to level. The estimate is
  rested-aware and blends this level with your past levels; hover it for a
  mobs-to-level range and how confident the number is. Drag it anywhere,
  right-click hides it, `/probe bar` brings it back.

## What it does underneath

- Takes a snapshot at login and level-up: level, spells, gear, zone,
  professions and money.
- Quietly keeps the record future site features will need: one guild roster
  snapshot per session, and PvP kills you land and take (your nemesis list)
  on clients that still let addons read the combat log. Forever doesn't, so
  there the nemesis list stays empty. Dormant until foreverrank.com grows
  the pages for them.
- Notes what class trainers offer when you open one.
- Everything stays in your SavedVariables until you type `/probe export`
  and copy the text yourself, then paste it in the upload box at
  https://foreverrank.com/questbank/ (or drop the `ForeverProbe.lua` file
  there). The Windows companion in the download does that for you.
- If QuestBank runs too, its discoveries (quests, the NPCs who give and take
  them, the XP they pay) ride along in the same export. QuestBank never needs
  ForeverProbe, and ForeverProbe never needs QuestBank.
- `/probe debug` lists anything that went wrong, with where, so a report
  comes with the reason.

No combat automation, no chat messages, no network calls. Just reading and
one copy box.
