# Cute guild dashboard: design

A guild addon for <Cute>, the guild that progs Forever's November release. Every member's
client reads about 150 stats about its own character, shares them with the guild over the
game's addon channel, and shows the whole guild in one Cute-styled window: a race board, a
progression board, a hall of shame, an officers' tab and your own full record. Officers and the
guild master see everything; they decide, stat by stat, whether members see each other's.

Proof of concept, built in the open. Published at foreverrank.com/addons/cute. Not QuestBank:
QuestBank stays the public addon; the two can run side by side and share no code at runtime.

Out of scope for the POC: uploads, a Cute companion exe, a web mirror of the dashboard. Those
follow on the QuestBank Uploader pattern once the in-game addon has been used by the guild.

## Decisions

- Where: in game, a new addon `Cute`, no server, no uploader.
- Transport: GUILD addon-message channel only. Nothing leaves the guild channel.
- Data: about 100 leveling and progression stats, 10 to 30 funny ones, 20 to 30 for officers.
  The owner supplies the real list later; the starter list is below. Adding a stat is one line.
- Visibility: two levels per stat, **Everyone** or **Only you**. Officers decide which. Officers
  and the GM see everything regardless. Your own row is always complete.
- Every stat is sent (officers need all of them); the policy decides only whether members see
  each other's values. An Only-you stat is hidden in the UI of members' clients, not encrypted;
  a member who reads the SavedVariables file can see it. Acceptable for a guild POC, stated.

## Architecture

```
Stats.lua      the registry: one S.def per stat (id, label, category, read, on, kind, fmt)
Sample.lua     reads stats on their events and a 5-minute heartbeat; counters for addon-counted stats
Comm.lua       GUILD addon messages: deltas, full state, resend requests, the officers' policy
Roster.lua     CuteDB.roster[name] = { seen, online, rank, stats }; guild roster ranks; pruning
Policy.lua     CuteDB.policy = { vis = { id = "all" | "self" }, by, rank, at, threshold }
UI.lua         the window: Race, Prog, Hall of Shame, Officers, Me; generated from the registry
Settings.lua   everyone's display choices; the officers' visibility list and threshold
Core.lua       slash command, key binding, minimap button, saved variables, Safe() wrapper
```

Files live in `tools/cute/Cute/`, the harness in `tools/cute/harness.lua`, the page in
`addons/cute/index.html` with `Cute.zip` beside it.

### Stat registry

```lua
S.def("level",   "Level",   "leveling", { read = function() return UnitLevel("player") end,
                                           on = "PLAYER_LEVEL_UP", kind = "int" })
S.def("deaths",  "Deaths",  "funny",    { count = "PLAYER_DEAD", kind = "int" })
S.def("gold",    "Gold",    "officer",  { read = function() return math.floor(GetMoney() / 10000) end,
                                           on = "PLAYER_MONEY", kind = "int" })
S.def("attune_ony", "Onyxia attunement", "prog", { read = steps({ 6502, 6602, 6622, 6623, 6624, 6482 }),
                                           on = "QUEST_LOG_UPDATE", kind = "pips", fmt = pipsOf(6) })
```

Fields:

- `id` short ASCII, stable for life; the wire key.
- `label` shown as a column header or card title.
- `category` one of `leveling`, `prog`, `funny`, `officer`. Decides the default tab and default visibility.
- `read` a function returning the value, or `count = "EVENT"` for a counter the addon keeps per character.
- `on` an event or list of events after which the stat is re-read; absent means the heartbeat reads it.
- `kind` `int`, `flag`, `text` (ASCII, at most 24 chars), `list` (bitmap over a fixed ID list given in `of`), `pips` (small list of step states).
- `fmt` optional display formatter (hours and minutes, "12/16 slots", percentages).
- `default` optional: `"all"` or `"self"`; the category's default applies otherwise
  (leveling all, prog all except the gear-gap stats, funny all except the social ones, officer self).

Every `read` runs under `pcall` and `issecretvalue` guards. A stat that errors stores `nil`,
shows "?" and puts the error text in the tooltip. A stat whose source is a secret value on this
client stores `nil` and shows "n/a".

### Sampling

- Event-driven stats re-read on their event, coalesced to at most once a second per stat.
- Everything else is read on a heartbeat every 5 minutes; the heartbeat walks the registry in
  slices so a client never reads 150 stats in one frame.
- A full read at `PLAYER_ENTERING_WORLD` (after the guild roster is known) and at `PLAYER_LOGOUT`.
- Counters (`count =`) increment on their event and persist in `CuteDB.chars[name].counters`.
  They start at zero the day the addon is installed.

### Comm

Prefix `Cute`. Channel `GUILD`. Lifted from QuestBank's Sync.lua: a queue that sends at most one
message a second, waits 3 s and retries on the game's throttle codes, drops on bad channel.

```
1D|<regver>|k=v;k=v;...        deltas: stats whose value changed since the last send
1F|<part>|<parts>|<regver>|... full state in chunks (login, on request)
1R                             please send your full state
1P|<at>|<threshold>|id=all;id=self;...   the officers' visibility policy
```

- Values: ints in base 36, flags as `1`/`0`, text as is (ASCII, no `|` `;` `=`), lists as
  base-36 bitmaps over the stat's `of` list, pips as a digit string.
- A message holds at most 250 bytes; deltas that do not fit wait for the next message.
- `1R` at login; every online member answers with a `1F` after a random 1 to 20 s delay, so
  twenty clients do not fire together. Worst case about 20 messages per member, under a minute.
- Senders are realm-qualified names, as the game reports them on `CHAT_MSG_ADDON`.
- A client ignores stat IDs it does not know and shows the ones it does. `regver` is informational.

### Roster

`CuteDB.roster[name] = { seen = <epoch>, online = bool, rank = <index>, stats = { id = value },
at = { id = <epoch> } }`. Persisted, so offline members keep last-known values with a "seen 3
days ago" marker. Ranks come from `GetGuildRosterInfo`, re-read on `GUILD_ROSTER_UPDATE`;
`C_GuildInfo.GuildRoster()` is requested at login and the roster is not trusted until the first
update arrives. A name is pruned after two consecutive roster reads without it, and anyone unseen
for 90 days; the table is capped at 200 names. Members in the guild roster without the addon
appear greyed with "no Cute addon".

### Policy

`CuteDB.policy = { vis = { id = "all" | "self" }, by = name, rank = index, at = epoch,
threshold = index }`. The threshold is the lowest rank index counted as officer (default 1: GM
and the rank below). A `1P` is applied only when the sender's rank, looked up in the local guild
roster at receipt, is at or above the threshold, and its `at` is newer than the stored one.
Unknown IDs in a policy are stored and applied to the known subset. Without a policy the
registry defaults apply, so the dashboard is never empty before the officers touch it.

Visibility rule for a cell (viewer V, row R, stat s): shown if V is an officer, or R is V, or
`vis[s] == "all"`.

## The window

Opened by `/cute`, a minimap button carrying the Cute logo, and a key binding (Bindings.xml).
One window, resizable, remembered position and size. Cute colours (the banner's red hair and
teal, parchment text) on the game's own fonts and button textures. The logo top-left.

Tabs:

1. **Race**: one row per member, class colour, level with an XP bar, zone, XP an hour, time
   played, last seen, grouped with. Sort by any column, online first by default; a pinned "Me"
   row on top; small gold, silver and bronze marks on the top three levels.
2. **Prog**: attunements as pips, item level, resist totals, consumables and flasks on hand,
   world buffs, professions and skills, raid recipes known, and a readiness column computed from
   the officers' chosen readiness stats (red, amber, green).
3. **Hall of Shame**: one card per funny stat with the leader's name and number.
4. **Officers** (officer rank only): gold, bank activity, attendance, the summaries, and the
   controls: the visibility list, the threshold, "broadcast now", "ask everyone to resend".
5. **Me**: your own record, every stat, with a "what members see" toggle that greys the cells
   the policy hides from members.

Columns and cards come from the registry: a stat's `kind` picks the renderer (int: number,
flag: tick, list and pips: pips, text: text). Tooltip on every cell: raw value, when it was
reported, the full list for list stats. Empty states: "nobody else is online yet", "no policy
set, defaults apply", "not in a guild".

## Settings

`/cute settings` or the cog on the window.

- Everyone: columns per tab (checklist from the registry, all on by default), row density, show
  offline members, sort memory, minimap button on and off, the key binding.
- Officers only (greyed for members): per stat, Everyone or Only you; the officer threshold;
  "broadcast now"; a line saying who last changed the policy and when.

## Starter stat list (the owner's list replaces it)

Leveling (~45, default Everyone): level · XP into level · XP an hour last hour · XP an hour
session · time played total · time played this level · time to 60 at current pace · rested XP ·
zone · subzone · grouped with · online · last seen · logins this week · sessions this week ·
average session length · quests completed total · quests completed today · quests in log · quests
ready to turn in · dungeons completed by instance · dungeon runs today · elite kills · mobs killed
total · mobs killed this hour · discoveries · flight paths known · flight paths taken · hearthstone
set to · hearthstone uses · boat and zeppelin rides · deaths while leveling · gold earned total ·
gold from quests · vendor sales value · mount owned · riding skill · talents spent · talent spec ·
first aid, cooking, fishing skill · unspent talent points · Legacy perks active · time lost to
death runs · longest session · level-ups today · pace against the guild median.

Progression (~55, default Everyone unless noted): item level average · item level per slot ·
empty slots (Only you) · unenchanted slots (Only you) · slots with gear more than 10 levels old
(Only you) · green items worn (Only you) · attunements and keys as pips: Onyxia, Molten Core,
Blackwing Lair, UBRS key, Scholomance key, Dire Maul key, Shadowforge key · pre-raid BiS count
(our rankings) · resist totals: fire, nature, shadow, frost, arcane · professions · profession
skills · raid recipes known · raid recipes missing · free bag slots · bag size total · consumables
on hand: health potions, mana potions, flasks, elixirs, food buffs, bandages, ammo · world buffs
active · raid buffs missing (Only you) · durability · repair cost · reputation with raid factions ·
PvP rank · honor this week · raid lockouts held · raids attended (counted) · dungeon lockouts ·
soulstones or healthstones carried · class resources (totems, soul shards, ammo, poisons) · weapon
skill, main weapon · weapon skill maxed · spell ranks at max for level · key items for prog · gold
(officer) · guild bank deposits (officer, counted) · guild bank withdrawals (officer, counted) · raid
attendance (officer) · on time for raid (officer, counted) · consumables used per raid night
(officer, counted) · readiness score.

Funny (~25): deaths total · deaths today · fall deaths · drownings · fatigue deaths · same mob
twice in a row · hearthstones wasted · longest time standing still · AFK flags · /dance · /sit ·
emotes total · whispers per hour (Only you) · guild chat lines · caps-lock guild lines · times
inspected others · times inspected by others · gold spent on grey items · fish caught · critters
killed · jumps · longest flight · ghost run distance · time as ghost · "where are you" typed in
party.

Officers (~25, default Only you): gold · bank activity · attendance · signed up but offline at
raid start · consumables brought against required · attunement completion across the guild ·
members below median level · members without the addon · members unseen 7 days · raid recipes
nobody knows · declared main (member sets it) · role (member sets it) · raid spec against leveling
spec · profession coverage · no mount at 40 · hearth not near the raid · policy last changed by ·
addon version per member · data age per member.

Anything that depends on the combat log is out: the Forever client restricts
COMBAT_LOG_EVENT_UNFILTERED. Chat-derived counters guard `issecretvalue` and show "n/a" when the
client makes the text secret.

## Edge cases

- Channel budget: deltas only, base-36 ints, bitmaps for lists, heartbeat spread over its five
  minutes, staggered `1F` replies. Throttle code: wait 3 s and retry, as Sync.lua.
- Rank and trust: policy applied only from a sender whose roster rank is at or above the
  threshold at receipt and whose `at` is newer. Forged `1P` from a member is ignored.
- Roster lag: ranks untrusted until `GUILD_ROSTER_UPDATE`; prune needs two misses.
- Not in a guild: Me tab only, a line saying why, nothing sent. Rejoining resumes.
- Forever client: `pcall` on every read, `issecretvalue` guards, no combat log, no secure frame
  changes in combat; the window is insecure and may open in combat.
- Versions: unknown IDs ignored on receipt; policies applied to the known subset.
- Storage: roster capped at 200 names and 90 days; counters per character; no alt linking
  (declared main is a text stat).

## Testing

`tools/cute/harness.lua` on luajit, mocking the Forever client as QuestBank's harness does:
secret values, restricted events, a fake guild of 20 with one officer and one GM.

Cases: every registry entry round-trips through the encoder; a 150-stat full state fits in
chunks of 250 bytes; a non-officer `1P` is rejected; an officer `1P` hides a column for a member
and not for an officer; the Me tab shows every stat under every policy; roster prune needs two
misses; a login storm stays at one message a second; every `read` survives a secret value and a
thrown error; counters persist across a reload; layout check on all five tabs and Settings
(nothing past the window edge, no overlaps, no Unicode in game text, text at least 10 px).
Harness ends "layout problems: 0" and "OK". Page renders through the existing render_layout.py
pipeline for screenshots.

## Deliverables

- `tools/cute/Cute/` the addon (TOC Interface 16001, SavedVariables `CuteDB`, GPL-3.0-or-later).
- `tools/cute/harness.lua`.
- `addons/cute/index.html` with `Cute.zip`, the Cute logo, install steps, what is shared and
  the visibility rule, and a changelog. Linked from the deck's slide 9 footer later.
- A deck slide for the Cute addon, later.
