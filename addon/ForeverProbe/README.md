# ForeverProbe

Reads your character for [foreverrank.com](https://foreverrank.com). Quiet,
read-only, nothing automated, nothing sent anywhere on its own.

## Install, three steps

1. Download and unzip. You get this `ForeverProbe` folder, plus an
   optional `Companion` folder (Windows auto-sync for the guild).
2. Drop `ForeverProbe` into `World of Warcraft/_beta_/Interface/AddOns/`.
3. Restart the game. Done. A small pace bar appears at the top of the screen.
   Guild contributors: see `Companion/README.txt` for the two-click auto-sync.

## What you get

- A pace bar: level, percent, XP per hour, time to level. The estimate is
  rested-aware and blends this level with your past levels; hover it for a
  mobs-to-level range and how confident the number is. Drag it anywhere,
  right-click hides it, `/probe bar` brings it back.

## What it does underneath

- Takes a snapshot at login and level-up: level, spells, gear, zone,
  professions and money.
- Quietly keeps the record future site features will need: PvP kills you
  land and take (your nemesis list), and one guild roster snapshot per
  session. Dormant until foreverrank.com grows the pages for them.
- Notes what class trainers offer when you open one.
- Everything stays in your SavedVariables until you type `/probe export`
  and paste the text at foreverrank.com yourself.

No combat automation, no chat messages, no network calls. Just reading and
one copy box.
