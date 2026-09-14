# Beta day: the twenty-minute harvest

One session in the client answers everything The Forge and the addon are
waiting on. Do this first, before playing.

## 1. Find where addons go
Look inside the beta's install folder for `Interface\AddOns` (the beta
usually installs beside retail as its own folder; whichever it is, it has
`Interface` and `WTF` inside once you have logged in once).

## 2. Install the probe
Unzip so you have `Interface\AddOns\ForeverProbe\ForeverProbe.toc` at exactly
that depth. At the character screen, open AddOns and tick **Load out of date
AddOns** (our Interface number is a guess until the client tells us).

## 3. In game
- Log in. The probe dumps automatically and prints the client version.
- Open your **talent pane** and **spellbook**, then type `/probe` once more
  (some data only populates after the UI touches it).
- Hit a training dummy or any mob for ten seconds (teaches us the combat log).
- If you can enter a battleground, do, and `/probe` inside it.

## 4. Get the file out
Log out (or `/reload`). Then send:

    <beta folder>\WTF\Account\<ACCOUNT>\SavedVariables\ForeverProbe.lua

That one file carries: client build and interface number, every C_*
namespace, an API-existence map, the GUID format, the full talent trees with
live tooltip text, the whole spellbook (racials included), your equipped
gear links, and the combat log's argument shape.

## 5. What happens with it
- The Forge's talents get corrected from the client itself (estimates become
  facts; gear datamining starts from real item links).
- The addon port begins against a test harness built from the dump, the same
  way the 3.3.5 addon was built.

Twenty minutes. Then go play.
