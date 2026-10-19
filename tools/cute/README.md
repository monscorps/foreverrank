# Cute: the guild dashboard

The in-game addon of <Cute>, the guild progging Forever's November release. Every member's client reads about a
hundred facts about its own character, plus what it meets in play (the bosses it kills, the instances it enters, its
factions, what it enchants) and the game's own statistics where the client reports them, shares them with the
guild over the game's addon channel, and shows the whole guild in one window. Officers decide per stat whether members
see each other's. No server, no uploader.

Learned, not listed. Forever is an exploring game whose content is revealed over time, so the addon fixes no content
in code: what the guild meets in play is data each client finds, shares on the guild channel and keeps in the saved
variables (`CuteDB.known`), and the dashboard grows with it without a new version. Only the game's structure is fixed:
the equipment slots, the classes, the damage schools, the item class enums (a few ids stay where no documented call can
tell the thing apart; "Adding a stat" names them). 0.3.x listed Classic's content (Molten Core
and Onyxia attunements, Classic keys, world buffs, the raid factions, potions and flasks by Classic item id, raid
recipes, soul shards, totems, poisons) and a fixed set of enchantable slots that asked for head and shoulder enchants
Forever does not have yet and never for the neck enchants it does. All of that is gone in 0.4.0.

Design: `docs/superpowers/specs/2026-10-18-cute-guild-dashboard-design.md`. Plan: `docs/superpowers/plans/2026-10-18-cute-guild-dashboard.md`.

## Files

```
Cute/Core.lua       errors, Safe, Plain, Get (every result, plain; a missing function says so), Callable, who you are (names, GUID, Canon), saved variables (CuteDB.known included), /cute, /cute api, /cute diag, key bindings
Cute/Stats.lua      the registry: one S.def per stat (id, label, category, read or count or track, events, kind); the gear and bag scans; the enchants learned per slot and kind of item, the raid buffs; the Legacy walk; the statistics probe; the discovered stats (bosses, instances, factions), their labels and the Statistics page's board
Cute/Sample.lua     reads stats on their events and a one-minute heartbeat; the gear and bags again after every loading screen; counters; the ticker; hooks; instance entries, boss kills and the reputation list; the statistics pass
Cute/Roster.lua     the guild as C_Club lists it, joined with what each member's addon sent by GUID; you, once; the kinds of every member's enchanted items teach the guild's knowledge, by GUID
Cute/Policy.lua     the officers' visibility list (Everyone or Only you per stat, per category for statistics and discoveries), who may send it
Cute/Comm.lua       the guild channel: deltas, full records in chunks, the statistics and discoveries pass, the labels (1L), resend requests, the policy
Cute/UI.lua         the window: Race, Prog, Hall of Shame, Statistics, Officers, Me, Settings (tables and rankings virtual); the minimap button
Cute/Settings.lua   columns per page, display, main, role and raid spec; the officers' visibility list
Cute/art/           logo.png (the emblem, for the minimap), logo_wide.png (the header)
harness.lua         the mock client and every scenario
page_stats.lua      writes addons/cute/stats.js from the registry and UI.lua's defaults
build.py            builds, stamps and checks the page (see Ship)
```

## Adding a stat

One line in `Stats.lua`:

```lua
D("fish", "Fish caught", "funny", { track = true, hint = "loot windows after a Fishing cast" })
D("gold", "Gold", "officer", { read = money, fmt = goldOf, on = "PLAYER_MONEY" })
```

`read` returns the value (under pcall; secret values read as nil), `count = "EVENT"` counts an event, `track = true`
is a value Sample.lua sets. `on` lists the events that re-read it; without it the heartbeat (every minute) does. `kind`
is int, flag, text, list (bitmap over `of`) or pips. `fmt` formats the cell (hours, percent, gold from copper).
`slow = true` marks a stat that changes every few seconds (time played, XP into the level): it travels on Comm's
two-minute flush, not as it ticks. `default = "self"` hides it from members unless the officers open it. `gear = true`
or `bag = true` reads it again with the gear or the bags 2 s and 10 s after every loading screen. A stat names no
content of the game that the game can tell it: what Forever has is learned in play (below). A few ids stay fixed,
each where no documented call tells the thing apart, and each named where it is used: the Healthstones by item id
(Forever's own item list, `plan/items-db.json`; a mana gem is the same item class and subclass), the Hearthstone spell
(8690, for hearths and wasted hearths), the skill line ids of the primary professions, Fishing, Cooking and First Aid,
the five Legacy perks by trait node, Forever's PvP rank track (Major Faction 2800), and the Legacy ids
`Constants.LegacyConsts` gives (its documented values the fallback). Hours to 60 still scales Classic's XP per level
by your own `UnitXPMax` at the level you are: Forever's curve is the next thing to learn. A Fishing cast is known by
name (`C_Spell.GetSpellName` of the spell is the Fishing skill line's name), not by Classic's four rank ids.

A `read` may only call what Forever's generated API docs list (`research/wow-ui-source-forever/.../Blizzard_APIDocumentationGenerated`),
what QuestBank reads on this client (`GetInventoryItemLink`, the taxi nodes) or what Blizzard's own Camelot UI code
calls. The globals no doc lists are read on that last ground: `GetInventoryItemID` and `GetInventoryItemQuality`
(Forever's own character sheet, `Camelot/PaperDollFrame.lua` `PaperDollItemSlotButton_Update`),
`GetInventoryItemDurability` and `GetInventoryItemCount`
(Camelot's equipment flyout reaches them through `EquipmentManager_GetItemInfoByLocation`), `GetNumUnspentTalents`
(the mainline `TalentFrameBase.lua` the camelot game type loads), `GetCategoryList`, `GetCategoryInfo`,
`GetCategoryNumAchievements` and `GetAchievementInfo` (Blizzard_LegacySystem, Forever's achievement window, which loads
on camelot) and `GetTotalAchievementPoints` (Blizzard_Communities, whose toc limits no game type). Three more are in the
same binary but called only by the mainline achievement panel, which camelot never loads: `GetStatisticsCategoryList`,
`GetStatistic` and `GetLatestCompletedAchievements`. Cute probes for them at login (`C.Callable`) and reads them only
where they exist. The harness mocks the documented set, the QuestBank set and every undocumented one, each named in
its `UNDOCUMENTED` table with its evidence, the three probed ones for `withStats` clients only, so every scenario runs
with and without them; a mock without an entry there is refused, and the first scenario fails on any stat that reads
nil. `/cute api` prints how many statistics this client defined (or why none) and which of the undocumented functions
it has (`DoEmote` and the never-mocked `GetAverageItemLevel` included), lines to paste; a stat that reads a missing one
shows "?" with "X is missing on this client" in its tooltip, on the Me page and under `/cute errors`. Pass a global to
`Get` and `Num` by name (`Num("UnitLevel", "player")`) so that holds for it too. Gold stats keep copper and show gold.
Role and raid spec are per character; the main is account-wide.

### Gear

The gear stats read your slots the way Forever's character sheet does: `GetInventoryItemID` says what is in a slot,
`GetInventoryItemQuality` its quality, the item level comes from the id (`C_Item.GetDetailedItemLevelInfo`, whose
ItemInfo argument takes an id; `C_Item.GetItemInfo`'s fourth return where an uncached item reads nothing there), and the
item level is the average over the worn slots whose level reads. The link is read for the enchant alone and only when
it is a plain string. One scan of the slots serves every gear stat read in the same frame.

They refresh without a reload. 0.3.1's gear stats listened to `PLAYER_EQUIPMENT_CHANGED` alone, and the window learns
of a value of yours only when a read changes it. At login the inventory can arrive after the loading screen, with
`UNIT_INVENTORY_CHANGED` and no `PLAYER_EQUIPMENT_CHANGED`; an enchant changes an item's link and fires only
`UNIT_INVENTORY_CHANGED` too. So nothing read the slots again until the heartbeat, five minutes on: the owner had to
reload. (0.3.0's "15 of 17 slots empty, item level ?" on a character in full gear looks the same.) Forever's own
character sheet refreshes a slot on `UNIT_INVENTORY_CHANGED` for the player
(`Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua:2055-2063`). Now every gear and bag stat listens to
`PLAYER_EQUIPMENT_CHANGED`, `UNIT_INVENTORY_CHANGED` (yours only: `RegisterUnitEvent`, and a unit check for a client
without it; where `RegisterUnitEvent` fails, every unit's with the same check) and `GET_ITEM_INFO_RECEIVED` (only for
an item the last gear or bag scan met: a chat link, another addon or the Legacy window asks the client about items all
the time, and each would have scanned the slots and the bags again); the gear and the bags are read afresh 2 s and
10 s after every `PLAYER_ENTERING_WORLD`; the heartbeat runs every minute, not five (Comm still sends only what
changed, so a quiet minute sends nothing). On a table page your row, the first, is filled again in place when one of
its cells changes.

### Enchants: learned per slot and kind of item

No slot is listed as enchantable. Each client reads, per worn slot, whether the item's link carries a permanent
enchant (its second field) and the item's kind as the game classes it, `class.subclass` from
`C_Item.GetItemInfoInstant`'s sixth and seventh returns (`C_Item.GetItemInfo`'s twelfth and thirteenth for an item the
client's data lacks): a bow is 2.2, a gun 2.3, a wand 2.19, a shield 4.6, a book held in the off hand 4.0. It sends
`enchanted` (a list over the slots; everyone sees it; no column) and, beside it, `ench_kinds`, a hidden text stat
(`"2:4.0 18:2.2"`, the slot and kind of each enchanted item; in the full record after the GUID, and as a delta when it
changes). The guild's knowledge is per slot and kind: `CuteDB.known.enchant[slot] = { n, at, who, kinds = { [kind] =
{ n, at, who } } }`, built from your own read, from every member record that arrives with its GUID (`Roster:Apply`)
and from the records already saved, counting each member once by GUID (a delta that comes before any full record has
brought the GUID teaches nothing yet, so a member is never counted under a sender string and again under the GUID). It
is kept apart from the records, so it survives a /reload, the roster's pruning and the member leaving.

Missing enchants (`unenchanted`, its id kept) is the worn items without an enchant where the guild has seen the same
kind of item enchanted in that slot. A slot alone said too little: Forever has scopes (Crude, Accurate, Deadly) and
shield enchants, so one hunter's scoped bow would have asked every wand for a scope, and a tank's enchanted shield
every caster's off-hand book for an enchant, neither of which can have one. Now a wand, a gun nobody has scoped yet
and a book in the off hand are never asked for; an unscoped bow is once a scoped one is seen. Neck shows once anyone
wears a neck enchant, head and shoulder only once someone has one, a slot or kind nobody has enchanted never. Where a
worn slot the guild enchants gives no readable link, or an unenchanted item's kind does not read yet, it reads nil with
that reason in its tooltip. A new slot or kind learned asks your own Missing enchants again at once, so members show
it on their next read and the officers on receipt. The tooltip names each missing slot, with the kind on your own row
("Ranged (Bows)"), and on how many members the guild has seen one there: seen, since the count never falls as members
leave or change their gear. A member's list is shown through this client's knowledge, so an older client's head and
shoulder never appear. The cell shows the count alone. (0.4.0's first build learned slots alone; such a saved record
has no kinds and asks for nothing.)

### Consumables, reagents, buffs

Potions, elixirs, flasks, food and drink and bandages are counted by the game's own item classes
(`Enum.ItemClass.Consumable` and `Enum.ItemConsumableSubclass`, looked up by name with the documented values as the
fallback) from one cached scan of the backpack and the four bags (`C_Container.GetContainerNumSlots` and
`GetContainerItemInfo`, `C_Item.GetItemInfoInstant`, and `C_Item.GetItemInfo`'s class and subclass for an item the
client's own data lacks), so whatever potion Forever adds counts the day it drops. Healthstones stay by item id: they
are the one class reagent with evidence on Forever (QuestBank's uploads find Minor and Lesser Healthstones in Forever
characters' bags), and no documented call tells one from a mana gem, the same class and subclass. The ids are Forever's
own item list (`plan/items-db.json`, beta build 1.60.1.70291): 5512, 5511, 5509, 5510 and 9421, Minor to Major, and the
improved ranks a talented warlock conjures, 19004 to 19013. Soul shards, shaman totems and rogue poisons had no
evidence and are gone. Readiness (`ready`) weighs four gaps: an empty slot, an item without the enchant the guild has
on its kind, durability under 50%, no potions; its tooltip lists them.

Raid buffs missing is learned too. A buff of five minutes or more that a guild mate (`UnitIsInMyGuild` of the aura's
`sourceUnit`, not you) cast on you is remembered by name (`CuteDB.known.buffs`: when, the GUIDs of the guild mates who
cast it, how many times it came on). Remembered is not yet a raid buff: one counts once two different guild mates have
cast it on you, or one has on three separate occasions (an occasion is the buff coming on while it was not; that is
kept in the saved variables, so a /reload is none), and one no guild mate has cast on you for two weeks is forgotten.
The stat counts the raid buffs you have not got, and only in a group or an instance (`UnitExists("party1")`,
`UnitInRaid("player")`, `IsInInstance`); alone outside one it is 0, and your own tooltip says so. So a Soulstone, a
Thorns or a Water Walking while leveling is no raid buff, and nothing is missing while you quest alone. Your own
tooltip names each missing one, from how many guild mates and how many times. (QuestBank's uploads show four of
0.3.x's six on Forever characters, Fortitude, Mark of the Wild, Arcane Intellect and Kings, and none of Divine Spirit
or Shadow Protection: a list would have been wrong either way.)

### Discovered: bosses, instances, factions

Three kinds of stat are defined at run time, like the game's statistics, the first time a label for one is known (from
your own play or from the guild channel), and kept by every receiver as ints whether or not it has defined them; the
1000-a-member cap covers them and the statistics together:

- `e<encounterID>`: kills of that boss by this character: `ENCOUNTER_END` with success 1, or `BOSS_KILL` where no
  `ENCOUNTER_END` for the same encounter came within five seconds either side, never both. The first kill's time stays
  in your own saved variables. Labelled with the encounter's name, grouped by the instance it was killed in
  (`GetInstanceInfo` at the kill: its name and instanceID). Outside an instance that is the continent, "Eastern
  Kingdoms" (0) or "Kalimdor" (1), so a world boss is filed under its continent, not its zone: a zone has no instance
  id of its own, and zones sharing the continent's would rename it with every kill.
- `i<instanceID>`: times this character entered that instance: a new entry when the instance differs from the last
  one this character was in, or on the first loading screen of a login (the character left the world); the last one
  is kept across loading screens, so a run back after a wipe is no entry, and a /reload never is one. Labelled with
  the instance's name, a dungeon or a raid as `GetInstanceInfo`'s instanceType says. The summary ints fold into this:
  Dungeons run and Raids attended are entries into party and raid instances, Raids this week the same since Monday,
  Bosses killed the different bosses killed, Dungeons seen the different dungeons entered.
- `f<factionID>`: this character's standing (`currentStanding`) with every faction its reputation list holds, the rows
  with a standing and the headers with rep (`C_Reputation.GetNumFactions` and `GetFactionDataByIndex`), read again on
  `UPDATE_FACTION` at most once a second; a faction listed before is asked by id (`GetFactionDataByID`) while its
  header is folded. Shown by its reaction (`FACTION_STANDING_LABEL1..8`, the number where the client has none): yours
  as your list gives it, a member's from the standing ranges your own list showed (`CuteDB.known.reactions`).

The labels travel in their own message, `1L|key=label;...` (`e<id>:<instanceID>` for a boss and its instance,
`i<id>:<p|r|w>` for an instance and its kind, `w` the continent of an open-world boss, `f<id>` for a faction), for a
new discovery a second after it and in a
labels pass after the statistics pass, at the hello (only what this session has not sent) and in answer to an ask
(all), each pass the ids of the sender's own record, every boss with its instance, chunked to 255 bytes. A label is
UTF-8: bytes over 127 are kept (an accented name, a German client's dungeon), `|`, `;`, `=` and control characters go,
a broken sequence goes, and it is cut at 60 bytes without splitting a character. A receiver keeps it in
`CuteDB.known.labels` (with the instance of each boss and the kind of each instance) and defines the stat, so a member
who never met a boss shows it under its instance with the guild's values already kept; a label the client found itself
is never replaced by another's. At login a 300-statistic, 40-boss, 18-instance, 60-faction character sends 13
messages in its first minute (the harness measures it), the rest after the statistics pass.

### Who is who

Forever names a character with two words ("Helga Bluntforce"). On camelot `UnitName`'s second return is the surname,
not a realm (`Blizzard_FrameXMLUtil/Camelot/NameUtil.lua`, which loads on camelot only, joins the two with
`Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR`); the guild roster lists both words; the
channel names a sender its own way; and `ClubMemberInfo.name` "may be encoded as a Kstring", a `|K...|k` escape the
font draws as the name, never compared with `==`. And the game hands a guild addon message back to its sender too.
0.3.0 keyed you by a name it built from `UnitFullName` ("Helga" and its second return) and the roster by its names
with a realm added, so it showed the owner three times: "Helga (you)", "Helga Bluntforce (no addon)" from the roster,
and a grey "Helga Bluntforce" of question marks: her own messages come back under the channel's name for her, which
matched neither, kept as a member's record. The roster's prune dropped that record every two refreshes, as a name not
in the guild, and her next message made it again with that message's ids alone (a statistics delta carries none of
the columns), hence the question marks.

So no name is a key. A roster member is its GUID, else its club member id; you are the member marked `isSelf`
(NeverSecret) or carrying your GUID. Records stay under the sender string the channel gives, and every full record
starts with the sender's GUID (`guid`, a hidden text stat: in `Stats.byId`, not in the list, so no page, column,
checklist, policy pair or the web page shows it; `ench_kinds`, above, is the other), as does the ask (`1R|guid`; a
bare 0.3.0 `1R` is still answered).
A receiver joins a record to the member with the same GUID, by a loose name match (`C.Canon`: your realm cut, spaces
and hyphens one, lower case; never a Kstring) only while no GUID has come with it, and folds two records of one GUID
into one. Whether a message is your own, handed back, goes the same way (`Roster:FromMe`): the GUID decides wherever
the message (a full record, an ask) or the record under its sender carries one, so a namesake's record is never taken
for yours by its name; a delta or a policy, which carry none, count as yours under a sender string your GUID came
under, else by your names. Your own is dropped and its sender remembered as you for the session. The hello is said
only in a guild: a character that joins one after login says it then, its ask first, before any delta goes out (the
ghost row would come back otherwise). `Rows()` gives you exactly one row, the first, named as the roster names you;
ranks and the officers' check go through the same join, and a policy you set is marked yours rather than matched by
name. `C.Me()` stays 0.3.0's key for your saved counters (`CuteDB.chars`), so nothing moves. Your emote lines count by
the event's GUID. A value the client may make secret is asked `issecretvalue` (or made plain) before anything compares
it, `nil` included.
Records are kept for up to a thousand members, a guild's most (0.3.0 kept two hundred).

`/cute diag` prints what this client gives, lines to paste: `UnitName` and `UnitFullName` (both returns),
`GetNormalizedRealmName`, `GetRealmName`, the first 16 characters of `UnitGUID`, the roster's member for you
(`C_Club.GetMemberInfoForSelf`: the name raw with its `|` doubled, whether it is a Kstring, the member id, the GUID's
start), what Cute matched (your rows, records, senders known as you), the first three senders seen on
`CHAT_MSG_ADDON`, for slots 1, 5 and 16 `GetInventoryItemID`, what `GetInventoryItemLink` returned (string, secret or
nil) and `GetInventoryItemQuality`, and what the guild has learned: the enchant slots with how many members were seen
with one there and the kinds of item, by the client's names (`Ranged (2: Bows 2)`), how many labels are known (bosses,
instances, factions) and how many raid buffs count of those remembered.

### Legacy Challenges

Forever's achievements are Legacy Challenges, and the Prog category reads them the way the Legacy window does: one
cached walk over `GetCategoryList`, `GetCategoryInfo`, `GetCategoryNumAchievements` and `GetAchievementInfo` gives
challenges done (completed by this character: the 13th return, `wasEarnedByMe`, as the Legacy UI counts) and listed,
the Legacy points (`GetTotalAchievementPoints` where the client has it, else each done challenge's own Legacy points
from `C_Traits.GetTraitCurrencyForAchievement`), and a pip per category (the top-level categories with their children
folded in, your class's category last; the tooltip names them, exact counts on your own row, quarters on a member's).
The renown level comes from `C_MajorFactions.GetCurrentRenownLevel` of the Legacy reward track, unspent points and the
points spent per tree (Professions, Adventure, Progression) from `C_Traits.GetTreeCurrencyInfo`, the ids from
`Constants.LegacyConsts` with the documented values as the fallback. The latest challenge is a tracked text: the
client's latest at login where `GetLatestCompletedAchievements` exists, then whatever `ACHIEVEMENT_EARNED` names.
`ACHIEVEMENT_EARNED` clears the walk; `CRITERIA_UPDATE`, which fires on every kill, re-reads nothing here. Where the
`AchievementsPanelDisabled` game rule is active (looked up by name, as the Camelot stub does) the challenge stats read
as that reason.

### The dynamic category: Statistics

The Statistics panel never loads on camelot, but the C functions behind it may be there, so `Stats.ProbeGame` asks at
login (after the roster, before the first read): when `GetStatisticsCategoryList` is a function returning a non-empty
list, it walks the categories (`GetCategoryInfo` for the name and parent) and `GetStatistic(category, i)` for each
entry, skips the ones the game marks skip, and defines one int stat per statistic: id `g` and the achievement id,
label from `GetAchievementInfo`, hint the category path ("Kills > Creatures"), `game` the category id, slow, heartbeat
read. The quantity string loses its separators ("1,234", "1 234"); the game's "--" (never recorded) reads as 0, since a
count that never happened is nought and a nil would send nothing. If the function is missing nothing is defined and
`C.Stats.gameNote` says so; an empty list is asked again at 30 s and 2 min (the data can still be loading), then noted.
`ACHIEVEMENT_EARNED` and `CRITERIA_UPDATE` start one re-read pass of every statistic, at most once in thirty seconds.

On the wire the statistics and the discoveries are not in the full record: they go in a pass of their own a minute
and a half after the hello, and 60 to 90 s after a resend request, the labels after them, so a login's first minute
stays under twenty messages whatever the count (311 statistics in the gate, and 300 with 40 bosses, 18 instances and
60 factions). A receiver that has not defined a `g<id>` still decodes and keeps it as an int: the labels are the
client's own, so a client that learns its statistics later shows the others' at once. The visibility policy is per
category, id `gc<categoryID>` for the game's (a statistic takes its category's choice, a child category its parent's,
then "all") and `gc_bosses`, `gc_dungeons`, `gc_raids`, `gc_rep` for the discovered (every instance's bosses take
Bosses'); Settings shows one Everyone / Only-you pair per category, the discovered four first. The Statistics page is a
leaderboard: on the left the discovered categories above the game's own (Bosses with a child per instance, Dungeons,
Raids, Reputation, an empty one left out; a click opens one, a parent its first child), the open category's stats on
the right as name, your value (a dash for a discovery you have not met) and the guild's leader, and a click on one
ranks every member (a dash where the policy keeps a value from you). A boss's tooltip has your first kill, a
standing's its reaction and number. Where the client reports no statistics a note under the categories says why;
where there is nothing at all the page says so and that the addon's own counters stay on the other pages. The Me page
counts what you discovered and the statistics instead of listing them; the Officers page says what the guild has
learned (the discoveries, the enchant slots and on how many members).

### The window, at a few hundred members

What must stay in view while the rows scroll sits in a band above the scroll area (`UI:SetBand`): a table's column
header, the officers' summary and buttons, the Statistics page's headings. The rows start at the top of the scroll area.

The guild has a few hundred members and most have no addon; 0.3.0 laid out every one of them on every draw, and drew
on every roster event and every record that came in. Now the Race, Prog and Officers tables and the Statistics page's
columns (the categories, and the statistics with their rankings) are virtual lists: only the rows in view, with four
more either side, have widgets; a scroll fills the rows coming into view from the list the last draw sorted, so it
neither sorts nor reads. A row's cells are placed only when the columns, the width or the row height change. The
sort puts you first, then the members with the addon by the sorted column, then those without it online, then those
without it offline. A redraw comes at most once a second while the window shows and never while it is hidden; a value
from the guild draws only when the open page shows it, and one of your own only when its text changes (on a table
page only your row is filled again: it is the first, which no sort moves), so the five-second sampler draws nothing.
`fitText` keeps each cut per font size, width and text, and the Officers page names the first dozen members without
the addon and how many more.

## Test

```
cd tools/cute && luajit harness.lua
```

Must end `layout problems: 0` and `OK`. Twenty-seven scenarios. The mock hands every guild message back to its sender,
as the game does, and counts `SetPoint` and `SetText` calls. They cover the registry on the documented client (the item level
averaged over the items worn, eleven statistics from the client's list), secret and throwing reads and a client missing
a function (the reason in the tooltip, on the Me page, under `/cute errors` and in `/cute api`), the encoder and what
comes in, the hello, deltas, the slow flush and the statistics pass, the policy (including before the roster and on a
fresh install), counters across a reload and a week turning between sessions, the roster through C_Club, every page
at 1040x640 and 760x420 for an officer and a member, settings clicks, a twenty-client login storm, the throttle and a
dropped message, a guildless client, the trackers (XP pace across a ding, copper gold, grey sales, recipes, the day
and the week, emotes with and without DoEmote, guild lines counted as sent), the calls Cute never makes, the Legacy
Challenges (counts, points both ways, renown, the trees, the category pips and their tooltip, the latest at login and
on `ACHIEVEMENT_EARNED`, the game rule, a missing function) and the statistics (defined only where the API exists, the
"--" and the separators, their own pass kept by a receiver without the API, a change on the flush, a storm of
`CRITERIA_UPDATE` re-reading once in thirty seconds, the policy per category and its Settings pairs, the page for both
views at both sizes with a statistic opened and a child category, the empty state, a login with 311 statistics under
twenty messages in its first minute, an empty list at login defined on the retry), a long policy in chunks, Forever's
names (two-word characters, `UnitFullName` giving the surname on one client and the realm on another, a sender string
that is a Kstring and a roster name that is one, 0.3.0's ghost record in the saved variables: one row for you named as
the roster names you, no record of yourself, every record joined by GUID, ranks and emotes the same way, your own ask
not answered and a bare one answered, a namesake under your saved key and another's GUID under your own sender string
kept as theirs, your own policy named as yours, a wide Kstring the same on every draw, `/cute diag`), a guild joined
after login under a Kstring sender (the hello then, the ask first; no record of yourself; said again on a rejoin),
gear on a client whose links are all secret (item level 46, 11 of
17 empty, 3 greens, Enchanted nil with its reason and Missing enchants too once the guild has learned a slot, an
uncached item's level from `GetItemInfo`, a client without `GetInventoryItemID`), a 400-member guild with 150 records (Race, Prog and a ranking of 151 opened: widgets for the
rows in view only, the first screen costing the same as in a guild of a hundred, the first screen, a redraw, a jump
to the middle, a wheel step and the end each held to the rows in view, scrolling neither builds the rows nor draws, your level refilled in place, ten sampler ticks drawing nothing,
thirty records drawing once and nothing while hidden), and the six of 0.4.0: gear without a reload (slots that read
nothing until `UNIT_INVENTORY_CHANGED` three seconds after login, the empty-slot and item-level cells filling in on the
open Prog page, another unit's event ignored, an enchant clearing Missing enchants with no `PLAYER_EQUIPMENT_CHANGED`,
the one-minute heartbeat; without the new events the cells stay "15/17" and "?"), learned enchants (a guild of an
officer and three, nobody with a head or shoulder enchant; one neck enchant makes the other two show the neck missing on
their next read and the officer on receipt, head never; each member counted once; kept across a /reload and after the
members leave; taught by saved records, not by one without a GUID; a delta before the GUID teaching nothing and the
full record after it counting the member once), discoveries (dungeon entries with a /reload, a run back and another dungeon,
a raid; bosses by `ENCOUNTER_END`, by `BOSS_KILL` alone and by both, a wipe not; the reputation list with plain
headers, a header with rep, a storm of `UPDATE_FACTION` read once and folded headers read by id; the labels reaching a
member who never met them, a UTF-8 name whole, one with `;` and `|` cleaned, the bosses under their instance, labels
that do not parse skipped; the policy per discovered category; raid buffs remembered from a guild mate and not from a
stranger, a short buff or your own, a raid buff only from two guild mates or three times from one (a Soulstone cast
once never), counted in a group or an instance and 0 alone with the tooltip saying why, forgotten after two weeks
unseen; a saved record and settings full of 0.3.x's removed ids, ignored and never shown; the Statistics page's new
categories at both sizes for both views; the Me and Officers pages' counts), the budget (300 statistics, 40 bosses in
18 instances and 60 factions: 13 messages in the first minute, everything across), enchants by kind (a guild of seven
in full gear: a scoped bow teaches Ranged for bows and an enchanted shield Off hand for shields; a wand, a gun nobody
has scoped and a book held in the off hand are never asked for and their wearers are ready, as 0.4.0's first build's
slot-only rule would have them at "gaps"; an unscoped bow and a bare shield are asked for, on receipt for the officer,
the tooltip by slot there and by kind on your own row; the kinds travel hidden) and the smaller rules
(`GET_ITEM_INFO_RECEIVED` re-reading only for an item you wear or carry, a client whose `RegisterUnitEvent` throws
still hearing your `UNIT_INVENTORY_CHANGED` and ignoring another unit's, a Fishing cast known by name under two spell
ids and a Fireball not, nor anything without the skill, the improved healthstones counted). The
default columns are measured too: at 1040 wide Prog's eleven take 671 of 838 px, the Officers' ten 789.
`--layout out.json` also writes
every page's layout for `tools/questbank/render_layout.py` (python3 -I tools/questbank/render_layout.py out.json out.html).

## Ship

```
python3 tools/cute/build.py
```

One command, nothing typed by hand: it zips the addon (the same `zip -rq ... Cute -x "*.DS_Store"` as before; `--no-zip`
keeps the zip you have), regenerates `addons/cute/stats.js` from the registry and the window's defaults
(`page_stats.lua`), stamps the version from `Cute.toc`, the zip's size in KB and the stat counts into
`addons/cute/index.html` between `<!--@name-->` markers, then checks the page: every link and image exists, every class
is `cu-` and none collides with `forever.css`, no hand-typed version or placeholder is left, the changelog's newest
entry is the toc's version, the greys pass 4.5:1, and the Download button is dark text on a light button through the
whole cascade. It ends `problems: 0` and `OK`, or lists the problems and exits 1. `--online` also fetches the external
links. The page is `addons/cute/index.html`; `#prog`, `#officers` or `#settings-officer` on its URL opens the mock on
that page.
