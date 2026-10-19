# Cute: privacy that holds, data that can be trusted, and modules

Three follow-ups to 0.5.0, from the owner's questions on 2026-10-19: can a member see data they are not supposed to,
can a modded addon feed the guild false data, and how QuestBank's features join Cute as modules in Cute's look.

## 1. Only-you data never reaches members

Today an Only-you stat travels on the GUILD addon channel like every other stat and is hidden in members' windows.
Anyone in the guild can read it: another addon listening to the "Cute" prefix, or the saved-variables file. Hiding is
not privacy.

Encryption does not fix this. Any key Cute could use ships inside the addon, so every member has it.

The fix is routing: **Only-you values are sent only to the officers**, as WHISPER addon messages to each officer who is
online (`C_ChatInfo.SendAddonMessage(prefix, msg, "WHISPER", officer)`), never on GUILD. The sender's own client
decides who is an officer from the game's guild roster (C_Club rank order against the policy's threshold), which a
member cannot fake. A member's client never receives another member's Only-you values, so there is nothing to bypass.

- When officers open a stat to Everyone, it flows on GUILD from then on; when they close it, members' clients delete
  the values they hold for others on receipt of the policy.
- Officers who log in later get Only-you values in the answer to their resend request (`1R`), whispered.
- Cost: one extra copy of each Only-you delta per online officer. With three officers online and the Only-you
  defaults (gear gaps, gold, bank, whispers), well inside the message budget; the harness measures it.
- What remains true and is said on the page: an officer's client holds members' Only-you values, and its saved file
  contains them.

## 2. A modded addon cannot steer the guild

Anyone can edit their copy of Cute and send any number they like. That cannot be prevented on the client. What Cute can
do is make false data harmless and visible:

- **The server's facts win.** Level, class, zone, rank and online state come from the game's guild roster (C_Club), not
  from the member's addon. An addon whose reported level disagrees with the roster is marked for officers.
- **Plausibility on receipt.** Every stat has bounds (level at most the cap, percentages 0-100, rates and counts within
  what play allows, lifetime counts never going down). A value outside them is dropped, and the sender is marked
  "suspect" with the reason, visible to officers only.
- **Learning needs more than one voice.** Rule thresholds count distinct members, at least two for anything that
  changes the guild's knowledge (an enchant slot, a level range, an XP value). A boss kill counts toward learning when
  it is corroborated by another member in the same group who saw the same encounter within a minute.
- **Officers can distrust a member.** A member marked untrusted (Settings, officers only; travels with the policy)
  is left out of learning and rankings; their row says so to officers.

## 3. Modules: Cute as the shell, QuestBank's features as modules in Cute's look

Cute becomes the guild's one addon. Its core is the shell: the window, tabs, flat skin, settings, the guild channel,
the roster, the policy, the registry and the knowledge model. Every page becomes a module that registers itself:

```lua
Cute:RegisterModule({
  id = "guide", title = "Guide", order = 20,
  page = function(ui, scroll) ... end,      -- draws into the shared scroll area and band
  settings = function(ui, column) ... end,  -- optional, its own Settings section
  stats = function(D) ... end,              -- optional, registry entries
  events = { PLAYER_LEVEL_UP = fn, ... },   -- optional
  officer = false,                          -- officer ranks only
})
```

Skin primitives (`UI.Button`, `UI.Check`, `UI.Text`, `UI.Skin`, the virtual list, the band, `UI.FitText`) are the only
way modules draw, so everything looks like one addon.

**Cute starts with only the statistics.** A fresh install is the core dashboard and nothing else. Every module ships
as a LoadOnDemand addon folder (`## LoadOnDemand: 1`, `## Dependencies: Cute`) and is switched on in Cute's Settings
under Modules, which loads it at once with `C_AddOns.LoadAddOn` (documented on this client): no reload, no AddOns-list
fiddling. Switched off, it is not loaded at the next login. The choice is per character.

**Settings, clean and modular.** Settings becomes a list of sections down the left (General, Who sees what, Rules for
officers, Modules, then one section per module that is on) and the chosen section on the right, one column, the same
spacing everywhere; a module brings its own section and nothing else changes when it is added.

**QuestBank's bugs are not carried over.** Each port starts from the known issues (the memory notes, the owner's
reports, the harness's gaps: e.g. QuestBank 5.4's unverified Map page taint, the dungeon floor view never built, six
bosses without an honest spot); nodes and quest items never lighting up (QuestBank's Glow.lua sets only
SoftTargetIconInteract; the game's own "Interact Icons: Show All" also sets SoftTargetIconGameObject and
SoftTargetLowPriorityIcons, which is what puts icons on herbs, ore and quest objects), with an easy undo: the sparkle section lists
each game setting it changes with the game's value and its own, a "Restore the game's settings" button and a slash
command put the saved values back, switching it off and logging out restore them as today, a value the player
changes in the game's own Settings is taken as the new baseline rather than fought, and a crash before logout is
repaired at the next login; the late-session lag at about
80 MB (measured and fixed in QuestBank 5.4.2 first) and fixes them in the module, with a harness case each; where the same bug sits in
QuestBank, it is fixed there too in the same round.

QuestBank's features come over as **separate addon folders in the same zip** (`Cute_Quests`, `Cute_Route`,
`Cute_Journal`, ...), each with `## Dependencies: Cute`, bringing their own data. A guild can turn a module off in the
AddOns list; the core stays small. Proposed order, one module per round, each through the harness and a reviewer:

1. **Quests**: QuestBank's Now and Available pages (best places for your level, XP an hour) in Cute's skin, fed by
   QuestBank's quest data and Cute's learned knowledge.
2. **Route**: the hand-in route and the arrow (QuestTrail's MIT art, licence kept).
3. **Journal**: the dungeon journal, merged with Cute's seeded and learned bosses.
4. **Gear**: upgrades per slot, merged with Missing enchants.
5. **Map**: the map page.
6. **Camp**: the camp bar and the missing-buffs banner.

QuestBank stays available on its own for players outside the guild; the shared code is copied into the modules with
its licence (GPL-3.0-or-later; QuestTrail's parts MIT).

## 4. Fresh starting point

Before modules land, a polish round: the logo on a transparent background (done: the grey box is keyed out), every
page checked at both sizes for spacing, alignment and empty states, `/cute` commands consistent, the version notice
and "what's new" in game, and a clean first run (no stale records, a welcome line naming `/cute`).

## 5. The Guide, made a guide (0.6.0)

0.5.0's Guide is a plain list of text lines: correct, but it does not guide. The owner called it lacklustre. 0.6.0
redraws it around one question, "what should I do next, and with whom":

- **The next best thing**, one line at the top, the rules' pick for you: "Run The Deadmines: 3 guild mates online in
  range, 7 bosses you have not killed, 5 quests", with the reason in its tooltip. Officers get the guild's version:
  "most members are 28-33: Scarlet Monastery".
- **Dungeon cards** instead of lines: the name, a level bar with the range drawn against your level (green in range,
  grey above, dim below), the bosses as pips (killed, not killed, doubted), the quests for it from what we know, how
  sure we are in one word, and the guild mates online in range as class-coloured names with an Invite button each
  (`C_PartyInfo.InviteUnit`, out of combat; never opening the chat box).
- **Next up** as a short timeline of the dungeons opening in the next levels.
- **Gear and pace** as compact strips under the cards, not paragraphs.
- When QuestBank's leveling module is on, its best places for your level join the same next-best pick.
- The same flat look, the band for headings, virtual where long, layout-checked at both sizes.
