# ForeverProbe

Reads your character for [foreverrank.com](https://foreverrank.com). Quiet,
read-only, nothing automated, nothing sent anywhere on its own.

## Install, three steps

1. Download and unzip. You get one folder called `ForeverProbe`.
2. Drop it into `World of Warcraft/_beta_/Interface/AddOns/`.
3. Restart the game. Done. A small pace bar appears at the top of the screen.

## What you get

- A pace bar: level, percent, XP per hour, time to level. Drag it anywhere,
  right-click hides it, `/probe bar` brings it back.

## What it does underneath

- Takes a snapshot at login and level-up: level, spells, gear, zone.
- Notes what class trainers offer when you open one.
- Everything stays in your SavedVariables until you type `/probe export`
  and paste the text at foreverrank.com yourself.

No combat automation, no chat messages, no network calls. Just reading and
one copy box.
