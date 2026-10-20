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
  the values they hold for others on receipt of the policy. A change an officer makes goes to the guild on its own, a
  few seconds on; the officer ranks never go below the officer's own rank.
- Officers who log in later get Only-you values in the answer to their resend request (`1R`), whispered; a member made
  an officer later gets them from every client whose roster names them one, whichever roster saw it first; an
  officer's repeated ask gets the whispered part alone.
- Cost: one extra copy of each Only-you delta per online officer. With three officers online and the Only-you
  defaults (gear gaps, gold, bank, whispers), well inside the message budget; the harness measures it. The copies
  never hold up the guild's deltas: a delta to a way that has one waiting goes into it, so each way holds one at most,
  and the guild's messages go ahead of the whispers (a whisper that has waited ten seconds goes in its turn).
- What remains true and is said on the page: an officer's client holds members' Only-you values, and its saved file
  contains them.
- **The policy lives in Guild Info** (the owner's choice, 2026-10-20, after three review rounds kept finding timing
  gaps in members passing the officers' policy on to each other). A client that was offline when the officers changed
  the policy holds an older one, and must not route by it. So an officer who changes it in Settings saves it, with a
  click, as one short line at the end of the guild's Guild Info text (`C_GuildInfo.SetInfoText`; the guild's own text
  kept, Cute's line replaced): `Cute 1 <stamp> <officer ranks> <fingerprint> <what differs from the defaults>`, each
  stat and category by a short code it keeps for life. Where the guild's text leaves no room for the whole line (Guild
  Info takes 499 letters) nothing is saved and Settings say how much shorter it must be: a line with the fingerprint
  alone, its policy taken from any copy that matched it, was a forgery's way in (a 64-bit hash is no signature), and is
  read by nobody. Nor is anything saved inside an instance, where Guild Info may read empty. The server keeps it and
  only the ranks allowed to edit Guild Info can change it; an officer without that right sees why, and their change
  stays on their own client, and only while the line's ranks name them an officer. Nothing is changed before Guild
  Info has been read, and nothing saved while it is to be read again (another officer's save heard, or one's own not
  read back yet), so no save writes over one made seconds before; a change is its author's, kept for them while another character of the account plays; and
  Addon version, which says who takes whispers and what Ready counts, is nobody's to set.
- Every client reads the line when the roster comes (`C_GuildInfo.GetInfoText`, on GUILD_ROSTER_UPDATE as Blizzard's
  panel reads it) and routes by the policy the line carries. Until a client holds that policy (Guild Info not read yet,
  a line it cannot read, or an officer's policy heard that is newer than the line and not its, until Guild Info is read
  again) it sends nothing but the ask and the policy, and whispers nothing, Ready included (counted again under the
  policy in force as the record leaves). A read that may be the game's copy from
  before (the line held when an officer's newer policy came, an empty text at login) is no answer until the roster
  asked for since has had time to answer (eleven seconds after an ask made since), and the wait and the doubt survive
  a /reload and a relog: the last line read, the doubt and the line awaited are kept with the guild in the saved
  variables, and a client in doubt stays in doubt until a read outside an instance confirms a line. The officer who
  just saved waits for the line from before to go, whatever another officer sends meanwhile, and hears that Guild Info
  does not hold the save only from a confirming read that truly lacks it. An officer's policy no stricter than the
  line (nothing closed the line opens, no officer rank fewer) raises no doubt: an officer who missed a save and clicks
  a rule sends the old line's routing. A read that finds no line in a guild that ever had one (saved, or read by this
  client) is not "no line": the line is missing, deleted by hand or wiped with the text; the client routes by the last
  line it read, sends nothing of its own, and the officers see "Cute's line is missing from Guild Info; Save to Guild
  Info to put it back" in Settings and once in chat. Only a guild that never had a line routes by the no-line rule, so
  a brand-new recruit cannot know one existed (irreducible). A member's client that dropped a value while in doubt (a
  stat the officers had just opened, sent once) asks once as the doubt ends. No line read in an earlier session stands
  for this one: a client that logs in or reloads where Guild Info reads empty (inside an instance) sends nothing of its
  own until a read says something. An officer whose client does not hold the line's policy sends no policy until it
  does; the tooltips on an officer's client with a change not saved say what the members go by, the change marked not
  saved yet. The rules' thresholds and the untrusted marks
  are not privacy: they travel in an officer's `1P` as before, by the sender's rank, each with when it was set, the
  newest of each taken, so an officer who was away undoes nothing another officer set meanwhile; who is an officer for
  what others send goes by the line's ranks, never by an officer's change not saved, and an officer the officers marked
  untrusted is heard by nobody: it teaches no word, silences no honest officer's and cancels no honest officer's answer
  to an ask. A member alt's purge of an officer's file waits for a roster read that lists the officer character with a
  rank (an incomplete read says nothing; two complete reads half a minute apart that lack it say it left). What the
  privacy promise rests on: the guild master keeps Modify Guild Info to the officer ranks, which the page says. A guild whose officers never saved
  a line routes by the newest policy an officer sent, as 0.6.0's first builds did, and Settings asks them to save it.
  Closing a category also takes the other members' GUIDs out of what a member's client learned from it (the kills, who
  saw a boss's loot and brought it first, who said each label, who wore an enchant), the counts kept, and a member's
  client takes no label or claim of a category the officers keep; a kill claim names its group, so it goes the way of
  Grouped with too. Irreducible: a member on 0.5.x sends everything on GUILD until they update, an officer on 0.5.x
  receives no whisper (officers update first), in a guild whose officers never saved the line a member who was
  away routes by the older policy it holds until an officer online sends a newer one, and a line deleted by hand is
  missing only to the clients that ever read it (a brand-new recruit routes by the no-line rule until an officer saves
  it again).
- **No Everyone value rebuilds an Only-you one.** 0.6.0's first build sent Enchanted slots on GUILD while Missing
  enchants went to the officers: with the slots the guild knows take an enchant, any member could list a character's
  missing enchants from it, and Ready counted them. A stat names in the registry what a member could work out from it
  (`reveals`), and goes the strictest way of its own and theirs: Enchanted slots and the kinds riding with it with
  Missing enchants and Empty slots, Item level per slot with Empty slots and old gear, the three paces (XP/hour, XP/hour today, Hours to 60) together, the bag counts with consumables
  used in raids, the discovered counts with their categories and back, the lifetime counts with their daily ones, a
  statistics parent with its children. Settings shows such a stat greyed, "with" the one it goes with. Ready counts
  only the gaps everyone may see (durability and potions with the defaults). Consumables used in raids and Raids this
  week become everyone's by default: the open counts give them away, so keeping them hid nothing. The harness walks the
  registry and fails on a stat that goes to the guild while one it reveals does not; the README lists what stays coarse
  and why (an average names no slot, purse rises give no purse, what the game's own roster shows is not Cute's to keep).
- **Members still learn.** With the defaults a member's client hears no member's enchants. Each officer's client says
  what the guild learned from what members do not receive (`1N`, the officers' word: the slots and kinds that take an
  enchant and the doubted slots; where Bosses, Grouped with or a kind of instance is the officers', the dungeons and
  bosses met, a range where learned), aggregate only (no GUID, no member's value, no count), when it changes and in
  answer to an ask whose word is older, once however many officers are online. A member's client takes it only from a sender the roster
  names an officer by, marked "from the officers"; an edited copy's word teaches nothing.

## 2. A modded addon cannot steer the guild

Anyone can edit their copy of Cute and send any number they like. That cannot be prevented on the client. What Cute can
do is make false data harmless and visible:

- **The server's facts win.** Level, class, zone, rank and online state come from the game's guild roster (C_Club), not
  from the member's addon. An addon whose reported level disagrees with the roster is marked for officers.
- **Who sent a message is the server's word.** The channel's sender string says who sent it, the roster which name
  each GUID has; a GUID in a message proves nothing. The sender string and the roster's name may be different forms of
  one name (a surname on one side only, a Kstring), so they are matched by first names, a second word counting only
  where both have one; a GUID is another's only where its member's first name differs or the sender string names
  another member, and where the roster cannot tell (namesakes, a member online whose name reads in no form), nobody
  is marked and nobody is taken for an officer. The game
  delivers a whisper from anyone and a guild message only from the guild, so a whisper is taken only from a sender
  string a guild message made a record for, and never makes a record, sets a GUID or folds records.
- **Plausibility on receipt.** Every stat has bounds (level at most the cap, percentages 0-100, rates and counts within
  what play allows, lifetime counts never going down). A value outside them is dropped, and the sender is marked
  "suspect" with the reason, visible to officers only.
- **Learning needs more than one voice.** Rule thresholds count distinct members, at least two for anything that
  changes the guild's knowledge (an enchant slot, a level range, an XP value, the instance a dungeon the research
  names by name alone turns out to be, an instance's kind, a name over the seed's). One member's label only names what
  nobody, the seed included, has named yet, and one copy's junk (labels, loot, kill claims, asks, policies) is capped per
  member so it crowds nothing out. A GUID is a voice only where the roster lists a member with it. A boss kill counts
  toward learning when it is corroborated by another member in the same group who saw the same encounter within a
  minute.
- **Officers can distrust a member.** A member marked untrusted (the Officers page: click a row, Mark untrusted;
  officers only; travels with the policy)
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

**Cute starts with only the statistics.** A fresh install is the core dashboard and nothing else, and so is a character
that ran 0.5.x, where the Guide was a fixed tab. A module is one of
two kinds, both switched on in Cute's Settings under Modules. A built-in module ships inside Cute's own folder and is
off until its box is ticked, which brings its tab and its section at once: the Guide is one, since it is drawn from
the rules and the knowledge model of the core. A module addon ships as a LoadOnDemand addon folder
(`## LoadOnDemand: 1`, `## Dependencies: Cute`), which ticking loads at once with `C_AddOns.LoadAddOn` (documented on
this client): no reload. Switched off, it is turned off for the character in the game's AddOns list, so the next
login does not load it; ticked again, it is turned back on there before it loads; switched off there by the player, its
box goes unticked at the next login. The choice is per character.

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
