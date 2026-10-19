# Cute: the guild dashboard

The in-game addon of <Cute>, the guild progging Forever's November release. Every member's client reads about a
hundred and twenty facts about its own character, plus the game's own statistics where the client reports them,
shares them with the guild over the game's addon channel, and shows the whole guild in one window. Officers decide
per stat whether members see each other's. No server, no uploader.

Design: `docs/superpowers/specs/2026-10-18-cute-guild-dashboard-design.md`. Plan: `docs/superpowers/plans/2026-10-18-cute-guild-dashboard.md`.

## Files

```
Cute/Core.lua       errors, Safe, Plain, Get (every result, plain; a missing function says so), Callable, who you are (names, GUID, Canon), saved variables, /cute, /cute api, /cute diag, key bindings
Cute/Stats.lua      the registry: one S.def per stat (id, label, category, read or count or track, events, kind); the Legacy walk; the statistics probe
Cute/Sample.lua     reads stats on their events and a five-minute heartbeat; counters; the ticker; hooks; the statistics pass
Cute/Roster.lua     the guild as C_Club lists it, joined with what each member's addon sent by GUID; you, once
Cute/Policy.lua     the officers' visibility list (Everyone or Only you per stat, per category for statistics), who may send it
Cute/Comm.lua       the guild channel: deltas, full records in chunks, the statistics pass, resend requests, the policy
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
is a value Sample.lua sets. `on` lists the events that re-read it; without it the heartbeat does. `kind` is int, flag,
text, list (bitmap over `of`) or pips. `fmt` formats the cell (hours, percent, gold from copper). `slow = true` marks a
stat that changes every few seconds (time played, XP into the level): it travels on Comm's two-minute flush, not as it
ticks. `default = "self"` hides it from members unless the officers open it.

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
it is a plain string: on the live client `GetInventoryItemLink` gave nothing readable for most slots, which 0.3.0 showed
as 15 of 17 slots empty, 0 of 17 unenchanted and item level "?" on a character in full gear. Where a worn slot that
takes an enchant has no readable link, Unenchanted reads nil with that reason in its tooltip rather than a count; the
readiness verdict then leaves enchants out. One scan of the slots serves every gear stat read in the same frame.

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
checklist, policy pair or the web page shows it), as does the ask (`1R|guid`; a bare 0.3.0 `1R` is still answered).
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
`CHAT_MSG_ADDON`, and for slots 1, 5 and 16 `GetInventoryItemID`, what `GetInventoryItemLink` returned (string,
secret or nil) and `GetInventoryItemQuality`.

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

On the wire the statistics are not in the full record: they go in a pass of their own a minute and a half after the
hello, and 60 to 90 s after a resend request, so a login's first minute stays under twenty messages whatever the count
(311 in the gate). A receiver that has not defined a `g<id>` still decodes and keeps it as an int: the labels are the
client's own, so a client that learns its statistics later shows the others' at once. The visibility policy is per
statistics category, id `gc<categoryID>`: a statistic takes its category's choice, a child category its parent's, then
"all"; Settings shows one Everyone / Only-you pair per category. The Statistics page is a leaderboard: the categories
as the game groups them on the left (click to open), the open category's statistics on the right as name, your value
and the guild's leader, and a click on one ranks every member (a dash where the policy keeps a value from you). Where
the client reported none the page says why and that the addon's own counters stay on the other pages; the Me page
says how many statistics there are instead of listing them.

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

Must end `layout problems: 0` and `OK`. Twenty-one scenarios. The mock hands every guild message back to its sender,
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
17 empty, 3 greens, Unenchanted nil with its reason, an uncached item's level from `GetItemInfo`, a client without
`GetInventoryItemID`), and a 400-member guild with 150 records (Race, Prog and a ranking of 151 opened: widgets for the
rows in view only, the first screen costing the same as in a guild of a hundred, the first screen, a redraw, a jump
to the middle, a wheel step and the end each held to the rows in view, scrolling neither builds the rows nor draws, your level refilled in place, ten sampler ticks drawing nothing,
thirty records drawing once and nothing while hidden). `--layout out.json` also writes
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
