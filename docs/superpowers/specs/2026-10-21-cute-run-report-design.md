# Cute cards: run reports, halls, records and achievements (design)

Date: 2026-10-21. Builds on Cute 0.7.0 and the windows design (`2026-10-21-cute-windows-design.md`: the J window,
the setup card, the visual system). Repository `foreverrank`: `tools/cute` (Cute), `addons/cute` (the page). Client:
WoW Forever 1.60.1 (70338), game type camelot, launch 4 November. API truth: `research/wow-ui-source` at HEAD
(`git -C research/wow-ui-source grep -n ... HEAD`); file ids: `research/wago/1.60.1.70338/ManifestInterfaceData.csv`.

One card system: a card is a guild member with a label, a title, a line and a value; the run report, the halls of
fame and shame, the guild records and the achievement announcements are all cards, drawn by one frame, and everything
the officers publish goes through one queue and one publish flow. Four sub-projects, each shippable alone (section 20).

## 1. Why

The owner (2026-10-20/21):

- An end-of-run report "like the screenshot": a header (DUNGEON REPORT, the dungeon, bosses down, time, wipes,
  deaths), five tall cards, each with the member's 3D model, a label (AWARD / TOP HONOR / ROAST), a title, a one-line
  quip and the stat; a "left early" line; Send to party, as plain text for those without the addon; a test screen;
  after dungeons, raids, and parties over 15 minutes.
- "officers and guild master etc can pick different stats and then queue and publish / update hall of fames and hall
  of shames in same way this image does".
- "later we can even turn it on for stuff that is very hard to beat of stats in guild and then it's a guild wide
  announcement when they do happen".
- An achievements part: officers publish announcements, shown as in-game visual cards of the players.
- "modular, with settings within the modular of it".

The screenshot is Podium by Dalorrian (CurseForge, All Rights Reserved). Cute takes the idea and nothing else: no code,
no art, no award name, no quip, no label or header word. Every award, label and header below is Cute's own (section 6
has the check before R1 ships). Podium works
without the combat log, from the game's damage meter and events each client counts and syncs over addon messages; so
does Cute, because on this client it has to (`COMBAT_LOG_EVENT_UNFILTERED` is secure-only). Cute's take is guild-first:
what a run or an achievement proves feeds the guild's news, halls and records, and the officers curate.

The owner's shot of Cute's Statistics tab (`research/owner-shots/2026-10-21/3-cute-statistics.jpg`) shows the live
client's achievement and statistic categories (Character with Wealth, Consumables, Reputation, Gear; Player vs.
Player; Combat; Dungeons & Raids with Boss Kills; Kills; Deaths; Quests; Skills; "Times camped" a statistic). Those are
real data Cute can rank and announce.

Standing rules this design obeys: less is more; game-native icons and art; Cute's black and white flat look with
colour only where it means something (windows design, section 8); no text that catalogues what the addon tracks; the
privacy model (an Only-you value never on GUILD, never on a public card, never in party or guild chat; the officers'
policy in the Guild Info line; two voices to learn; untrusted members in no ranking); Forever is learned in play, never
listed (no dungeon, boss, raid or achievement names in code); no text outside Windows-1252 in game; a feature shows
something the first time it is on.

## 2. The shape

### 2.1 How a card reaches a screen

| Source | Becomes cards | Who sees them | How |
|---|---|---|---|
| A run ends (section 3) | the run report: up to five award cards | the group | automatic, on each member's client |
| A fastest clear the officers turned on falls (section 11) | one record card | the guild | automatic, each client decides alone from the values it receives |
| An achievement earned (section 5), a guild first (5.4), another record that is on, a run's cards, a hall, a card by hand | queue rows | officers | the officers' queue (section 9) |
| An officer publishes from the queue | a set of one to five cards | the guild | `1C` on GUILD (section 13) |

### 2.2 Where the pieces live

| Piece | Where | Why there |
|---|---|---|
| The card and the card screen (`CuteCardFrame`), the model, the race model and the icons | Cute core, `Cards.lua` | a published card shows on every member's client, whatever modules they run |
| The queue, the composer, publishing, halls, News | Cute core, `Halls.lua` | the guild base; officers curate, members receive |
| Achievement earns, the server's lines, guild news, the firsts ledger | **Achievements**, a built-in module (on by default): `Achievements.lua` | a member's client sends its own earns; officers' clients keep the ledger; a member or the officers may switch it off (14) |
| Guild records | **Records**, a built-in module (on by default): `Records.lua` | every client keeps the table from the deltas it receives; switched off the same way |
| The run, its data, the group messages, the awards, Send to party, the Runs tab | **Runs**, a built-in module (on by default): `Runs.lua`, `RunComm.lua`, `Awards.lua`, `RunsUI.lua` | only a member who runs it counts and sends its own values; a member may switch it off |
| The run stats (runs, honors, roasts, personal bests, fastest clears) | Cute core, `Stats.lua` (category `runs`) | every client must decode a guild mate's values, Runs on or off |

`Cute.toc` loads `Cards.lua`, `Halls.lua` after `UI.lua`, then the module files (Achievements, Records, Runs), before
`Settings.lua`. Changed: `Stats.lua` (new stats and codes, `c` as a dynamic prefix), `Sample.lua` (one hook point,
4.2), `Comm.lua` (new guild kinds, section 13), `UI.lua` (the Halls tab takes in `UI:DrawShame`), `Settings.lua` (two
sections).

### 2.3 Units and their interfaces

- `Cards`: `Cards:Show(set, mode)` where a set is `{ kind, label, title, sub, facts, cards, buttons }` and a card is
  `{ guid, name, class, race, sex, label, title, line, value, valueLabel, icon }`; `Cards.Find(guid)` (the unit to draw,
  8.2). Reads nothing of runs, halls or achievements.
- `Achievements`: `Achievements:Earned(id, time)` (own), the readers of `1A`, the server's guild line and guild news;
  `Achievements.First(id)` (the ledger, officers). Feeds `Halls:Queue(item)`.
- `Halls`: `Halls:Queue(item)`, `Halls:Compose(items)`, `Halls:Publish(set, chatLine)`, `Halls:Withdraw(at)`,
  `Halls:ComputeHall(def)`, `Halls.News()`, `Halls.PickStat(period, onPick)` (the stat picker, 9.5).
- `Records`: `Records:Seen(statId, guid, value, live)`, `Records.Table()`.
- `Runs`: `Runs.Current()`, `Runs:End(reason)`, `Runs:Snapshot()`. `RunComm:Send(kind, body, opts)`.
- `Awards`: `Awards.Pick(members, facts, route) -> cards, mentions`, `Awards.Text(report) -> lines`,
  `Awards.Sample(kind, units)`. No client calls: the harness drives it with tables.
- `RunsUI`: the Runs tab, Send to party, the test report's data; draws through `Cards`.

## 3. The run

### 3.1 Kinds and starts

| Kind | Header label | Starts | Gets a report when |
|---|---|---|---|
| Dungeon | DUNGEON RECAP | a loading screen into an instance `GetInstanceInfo` calls `party`, in a group; or `GROUP_JOINED` inside one | 2 or more in the group at a 30-second sample while you are inside, 5 minutes or more, at least one fight (`PLAYER_REGEN_DISABLED`) |
| Raid | RAID RECAP | the same with `raid` | the same |
| Group | GROUP RECAP | outside instances, in a group, at least 1 group mate on your map at a 30-second sample | 15 minutes or more, 2 together at the start sample |

"On your map" is `C_Map.GetBestMapForUnit` of `partyN` equal to yours. The client documents it for the player and
party members only, so in a raid only your own subgroup (`partyN`) is read; a `raidN` member outside it has an unknown
map, which never counts toward "together", "left early" by map, or a wipe (4.4).

A /reload is never a start (`PLAYER_ENTERING_WORLD`'s `isReloadingUi`, as `Sample.lua` `S:InstanceCheck` treats it).
Entering an instance during a Group run ends that run (its report if it lasted 15 minutes) and starts a Dungeon or Raid
run. A ghost's loading screens (a corpse run out of the instance and back) change nothing: the run is the instance's
(`CuteDB.chars[me].lastInst`, kept across loading screens as today). `UnitInRange` is not used for "together": its
returns are secret on this client.

### 3.2 Run id, hello, scribe

- **Hello.** At its start each client sends `2H` on the group channel (section 13) after 0 to 3 s at random, with a
  provisional run id: its start in server time (`GetServerTime`) in base 36, a dash, and the last part of its GUID
  ("Player-4242-0A000001" gives "0A000001"). Every client adopts the earliest id it hears for this group, kind and
  instance whose time is within 30 s of its own start (the smaller time, then the smaller suffix); an id outside that
  window is ignored, so nobody can back-date one. A member who joins later sends `2H`; the scribe answers it, any other
  holder only after 2 to 6 s at random and only where no answer was heard meanwhile, and the newcomer adopts the
  answer's id. Where the game holds addon messages for the whole stay in the instance (13.1), the hellos go when the
  group comes out, and the id settles then by the same rule.
- **Scribe.** One client does the group's end: the group leader's client where the leader said hello with Runs on;
  otherwise the client with the smallest GUID among the members whose hello this client holds and who are still in
  the group. Each client works it out alone from the same facts; it changes on `PARTY_LEADER_CHANGED`, when the scribe
  leaves the group, and when the scribe's final values say it is out (3.3). A group where nobody else runs Cute has
  this client as its scribe. A client sends `2Q` or `2A` only while it is the scribe by the hellos it holds at that
  moment; a held one whose sender is no longer scribe is dropped.
- **What every client observes**, so any of them can be scribe or build a report alone: its own counts (4.1), every
  group member's deaths by `UNIT_DIED` (GUID where it is plain) in the order they come, every boss kill and wipe, the
  damage meter's rows for every group member (4.3), the loot history (4.4), each member's name, class, race and sex
  (`UnitName`, `UnitClass`, `UnitRace`, `UnitSex`) as the group gives them during the run.

### 3.3 Ends

| What happens | What ends | Report |
|---|---|---|
| The leader's End run (Runs tab band, `/cute run end`; `2E`, taken only from the unit `UnitIsGroupLeader` names) | everyone's run | yes, through the scribe |
| A full clear and the scribe leaves the instance alive | the group's run | yes, at once |
| The scribe outside the instance alive (not a ghost) for 3 minutes (dungeon) or 10 minutes (raid) | the group's run | yes |
| Open world: no mate on the scribe's map for 5 minutes, the group under 2, or an instance entered | the group's run | yes, where it lasted 15 minutes |
| The group disbands, or you leave the group within 10 minutes of the run's last boss kill | your run | yes, built on your client |
| You leave the group at another time | your run | no: you left early |
| You outside the instance alive past the grace while the scribe is inside | your counting stops (your final values say "out") | you see the scribe's report if you are still in the group, yourself on the gone-early line |
| A ghost outside the instance (corpse run) | nothing | |

A **full clear** is every boss the guild knows in that instance killed in this run, at least one: the bosses whose
labels say that instance (`e<encounter>:<instance>`, `S.InstOf`), the seed's included. The guild learns the rest as it
kills them; a dungeon whose known bosses fall short of a later full clear simply ends on the grace that time.

**The group's end.** When the scribe's run ends, it sends `2Q`, waits until every member it holds a hello from has
answered or 15 s have passed, builds the report (section 7) and sends it as `2A`. Every client in the group ends its run
on `2Q` from the client it works out as scribe, sends its final `2V` (0 to 5 s at random), and shows the report when
that scribe's `2A` comes; a client with no `2A` 20 s after its `2Q` builds the report itself from what it holds.

**Left early.** A member who was in the run 5 minutes or more and whose run stopped (left the group, said "out", or was
seen on another known map by the scribe's 30-second sample, 3.1) more than 2 minutes before the report's end. Listed by
name on the report's gone-early line; no card.

### 3.4 Checkpoints

Groups often disband the second the last boss dies. So each client sends its values as a checkpoint (`2V`, whole, with
a rising sequence number) out of combat after every boss kill (5 to 20 s after `ENCOUNTER_END` with success, once
`PLAYER_REGEN_ENABLED` has come) and again at its end. A receiver keeps each member's highest sequence. Every client
therefore holds everyone's values as of the last boss at worst, and a report built after a disband matches the others'.
Where the game holds addon messages for the whole stay in the instance (13.1), the checkpoints go only when the group
comes out, so a group that disbands inside gets reports each client built alone, which may differ.

### 3.5 When the report shows

Never in combat or during a loading screen: a report ready then waits for `PLAYER_REGEN_ENABLED` and 2 s after
`PLAYER_ENTERING_WORLD`. With Settings > Runs "Show the report when a run ends" unticked it goes to the history alone.
A report is saved to the history the moment it is built or received, shown or not.

### 3.6 Recovery after a reload or a disconnect

- The run's state lives in `CuteDB.chars[me].run` (id, kind, instance, start, members with name, class, race, sex and
  GUID, own counts, the meter sessions read, the observations, every member's last `2V`). The game writes saved
  variables at a /reload and at a logout, a disconnect included.
- **/reload:** read back at `ADDON_LOADED`; `PLAYER_ENTERING_WORLD` with `isReloadingUi` resumes it. No new hello.
  Inside an instance the policy is then in doubt until Guild Info reads again (the privacy spec), and the run sends
  only what 12 allows while it is.
- **Login with a saved run:** it resumes where all three hold: saved less than 30 minutes ago, two or more of its
  members in your group now, and (Dungeon, Raid) `GetInstanceInfo`'s instance id the saved one. The client sends `2H`
  with the saved id. Otherwise the saved run is dropped without a report and the start rules apply.
- **A crash** (the client died before writing): the client sends `2R`; the scribe answers on the group channel with
  `2W`, that member's own last checkpoint, and the member counts on from it. A `2W` is taken only from the scribe and
  only after this client's own `2R`. What happened between the checkpoint and the crash is lost for that member alone.
- The damage meter's sessions after a reload or relog may be gone: the sessions already read are in the saved state.

## 4. The run's data

### 4.1 Each client's own values

Each client counts its own and sends them, as `key=value` in base 36 (Comm's `b36`), in `2V`. A key is sent only where
the officers' policy routes its code Everyone (section 12); an absent key is "no data", never zero.

| Key | Value | Source | Routed by |
|---|---|---|---|
| `t` | seconds in the run | the run clock | always (it reveals nothing) |
| `o` | seconds into the run when this client stopped ("out"), 0 while in | 3.3 | always |
| `de` | deaths | `PLAYER_DEAD` | `de` (Deaths) |
| `dt` | seconds dead | `PLAYER_DEAD` until `UnitIsDeadOrGhost("player")` is false (on `PLAYER_ALIVE`, `PLAYER_UNGHOST` and the 5-second tick) | `de` |
| `fd` | seconds into the run of the first death | `PLAYER_DEAD` | `de` |
| `dm` `hl` `ab` `tk` `av` `in` `dp` | damage done, healing done, absorbs, damage taken, avoidable damage taken, interrupts, dispels: this client's own row | `C_DamageMeter`, 4.3 | `rm` (Meter in runs) |
| `mt` | 1 where this client's meter gave data in the run | 4.3 | `rm` |
| `q` | quests handed in, ids in base 36 joined by `.`, 16 at most | `QUEST_TURNED_IN` | `rq` (Quests in runs) |
| `ch` | chat lines you typed, any chat; counted, never read | the `C_ChatInfo.SendChatMessage` hook (`Sample.lua`) | `rc` (Chat lines in runs) |
| `wy` | "where are you" typed | the same hook's phrase match (`Sample.lua` `WHERE`) | `we` |
| `yd` | yards moved alive, not on a taxi | `GetUnitSpeed("player")` times the second, at Sample's 1-second poll; a secret reading counts nothing | `yw` (Yards in runs) |
| `ju` | jumps | the `JumpOrAscendStart` hook | `ju` |
| `cn` | consumables used | Sample's bag-drop count by item class | `cn` |
| `lv` | levels gained | `PLAYER_LEVEL_UP` | `le` |
| `gd` | copper looted: purse rises with no merchant, mail, trade or bank open, less `QUEST_TURNED_IN`'s `moneyReward` | `PLAYER_MONEY` | `ge` |
| `lq` `ln` | best item quality received; items received of quality 2 or better | `CHAT_MSG_LOOT` whose GUID argument is yours (not secret in lockdown), quality by `C_Item.GetItemQualityByID` | `rl` (Loot in runs) |

Every key has bounds (`Awards.BOUNDS`: seconds within the run, counts within what a run allows); the harness fails a
key without them, and a receiver drops a value outside them (13.1).

### 4.2 What changes in Sample.lua

One hook point, `S:OnBump(fn)`: every counter bump calls it with the id and the amount, so Runs mirrors jumps and
"where are you" without a second set of hooks. The chat hook calls `S.OnChat` listeners with the chat type for every
line (Runs and Halls set a flag while they post, so their own lines never count). The bag-drop count behind
"Consumables used in raids" runs in a raid as today and also while a run is on; the registry stat keeps counting raids
only. The 1-second poll adds one `GetUnitSpeed` read while a run is on, into a
number kept in place (no table per poll).

### 4.3 The damage meter

- `C_DamageMeter.IsDamageMeterAvailable()` at the run's start; where it says no, every meter field is absent for the
  run and `/cute diag runs` says why (`failureReason`).
- Read only out of combat: `GetCombatSessionFromID` is `SecretWhenInCombat`. One second after `PLAYER_REGEN_ENABLED`,
  and at the run's end, `GetAvailableCombatSessions()` lists the sessions; each id not read yet that has a
  `durationSeconds` is read once per type: DamageDone 0, HealingDone 2, Absorbs 4, Interrupts 5, Dispels 6, DamageTaken
  7, AvoidableDamageTaken 8, Deaths 9 (`DamageMeterConstantsDocumentation.lua`). Eight calls per fight, out of combat.
- In each `combatSources` row, the one whose `isLocalPlayer` is true (NeverSecret) is this client's own; the others are
  matched to group members by `sourceGUID` where it is plain (`ConditionalSecret`), skipped where it is not. Sums are
  kept per session id, so reading a session twice changes nothing.
- `DAMAGE_METER_RESET`: the sums read so far are banked and the per-session marks cleared, since ids may start again.
  Cute never resets the meter and never sets its CVars.
- A member's meter values on the report: from their own `2V` where they run Cute; otherwise the observing client's own
  rows for their GUID (the scribe's, in the report it sends). Where both exist and are more than a tenth apart, the
  observed row wins (13.1).

### 4.4 Loot, deaths, wipes, bosses seen by every client

- **Loot history:** at the run's end, `C_LootHistory.GetAllEncounterInfos()` and `GetSortedDropsForEncounter(id)` for
  encounters killed in the run whose `startTime` is at or after the run's start on the loot history's own clock
  (`C_LootHistory.GetLootHistoryTime()`, kept at the start and at each resume; never `GetServerTime`, as the game's own
  `LootHistory.lua:508` subtracts the two): each drop's `winner` (`playerGUID`) and each
  `rollInfos` entry's `roll` and `state`. Per member: items won and their best quality, the highest and lowest roll,
  need rolls (`state` NeedMainSpec). Merged with `lq`/`ln`: the best of both. Routed by `rl`.
- **Deaths of members whose `2V` lacks them** (no Cute, or the key left out, 12): `UNIT_DIED` with a plain GUID,
  counted per member; their seconds dead from `UnitIsDeadOrGhost(unit)` at the 5-second tick, for those members only.
- **First death:** the smallest `fd`, ties (same second) broken by the observing client's own order of `UNIT_DIED` and
  `PLAYER_DEAD`, then by GUID.
- **Wipes:** `ENCOUNTER_END` with success 0; and outside an encounter, every member known to be on the scribe's map
  (3.1: in a raid, the scribe's subgroup) dead or a ghost at once (checked half a second after each death), counted
  once until one of them is alive again.
- **Bosses:** distinct encounter ids with `ENCOUNTER_END` success 1 (the `BOSS_KILL` fallback as `Sample.lua` has it);
  the header's "of N" is the guild's known bosses in that instance where more than the kills, else the kills.

### 4.5 What is impossible without the combat log, so no award reads it

Who pulled, threat, taunts; killing blows, the biggest hit, crits; overhealing (no meter type); friendly fire, crowd
control broken or applied; what killed someone; resurrections and soulstones (a cast has no target here, and listing
spells breaks "learn, don't list"); mana against health potions (the bag count cannot tell); pets apart from owners;
who looted or skinned which corpse; each member's own time in combat; who entered a fight first (one-second server
time and clock drift make the order a guess). And by choice, not by API: what anyone typed.

## 5. Achievements

### 5.1 What Forever has, from the source

| Fact | Evidence |
|---|---|
| Achievements on camelot are Legacy Challenges: the achievement key opens `Blizzard_LegacySystem` while `Enum.GameRule.AchievementsPanelDisabled` is off and the Legacy renown is above 0 | `Blizzard_AchievementUI/Camelot/Blizzard_AchievementUI.lua:3-16` |
| They are read with the achievement API: `GetAchievementInfo(id)` or `(category, index)` returns id, name, points, completed, month, day, year, description, flags, icon, rewardText, isGuild, wasEarnedByMe, earnedBy | `Blizzard_FrameXML/Mainline/AlertFrames.lua:526`, `Blizzard_LegacyChallengeButton.lua:284` |
| Forever has its own statistics window: `GetStatisticsCategoryList`, `GetCategoryInfo`, `GetCategoryNumAchievements`, `GetStatistic(categoryID, index)` returning quantity, skip, statID, names by `GetAchievementInfo(statID)`, refreshed on `CRITERIA_UPDATE` | `Blizzard_Statistics/Camelot/StatisticsFrame.lua:113-125` (the toc allows camelot only) |
| `ACHIEVEMENT_EARNED (achievementID, alreadyEarned)`, `CRITERIA_EARNED (achievementID, description, achievementAlreadyEarnedOnAccount)`, `CRITERIA_UPDATE`, `CRITERIA_COMPLETE (criteriaID)` | `AchievementInfoDocumentation.lua` |
| The game toasts your own earn already (`AchievementAlertSystem`), except one earned before on the account | `AlertFrames.lua:525-549` |
| Guild achievements: `C_AchievementInfo.AreGuildAchievementsEnabled()`, `IsGuildAchievement(id)` | `AchievementInfoDocumentation.lua` |
| The server tells the guild: `CHAT_MSG_GUILD_ACHIEVEMENT` (text, playerName, ..., guid); like all guild chat it goes secret in chat lockdown (dungeons, raids, encounters) | `ChatInfoDocumentation.lua:1649-1672` |
| Guild news: `QueryGuildNews()`, `GetNumGuildNews()`, `C_GuildInfo.GetGuildNewsInfo(index)` (newsType 1 player achievement, 0 guild achievement, `whoText` the member, `newsDataID` the achievement, the day with month and day zero-based), `GUILD_NEWS_UPDATE` | `Blizzard_Communities/GuildNews.lua:43-88`, `Blizzard_FrameXML/GuildUtil.lua:2-3, 57-84` |
| Another player's achievements: `SetAchievementComparisonUnit(unit)`, `INSPECT_ACHIEVEMENT_READY (guid)`, `GetAchievementComparisonInfo`, `GetComparisonStatistic`: called only by the mainline achievement panel, which camelot never loads, and only for an inspectable unit in range | `Blizzard_AchievementUI/Mainline/Blizzard_AchievementUI.lua:2908, 3028, 3148`; `CanInspect` |
| Every member's achievement points, server side: `C_Club` member info `achievementPoints`, with `race`, `classID`, `level`, `guildRankOrder` | `ClubDocumentation.lua:1808-1843` |

Whether Forever's server sends the guild achievement line and fills guild news for Legacy Challenges is not in the
source; section 17 says what the code does either way.

### 5.2 An earn, from the member to the officers

1. **The member's own client** hears `ACHIEVEMENT_EARNED (id, alreadyEarned)`. It skips `alreadyEarned` true (earned
   before by another character of the account) and guild achievements (`isGuild`, shown from guild news instead). It
   sends `1A|<id>|<server time>` (base 36), within the existing routing: on GUILD where the policy routes code `ac`
   (Achievements, a new row in Who sees what, default Everyone) Everyone; whispered to each officer online where it
   routes Only you, as Comm whispers `1D` (`1A` joins Comm's whispered kinds). An Only-you earn never reaches a member.
   Most Legacy Challenges come at a boss, inside an instance, where addon messages may be held: an earn waits in
   `CuteDB.chars[me].pending` with its time until the Chat restriction is inactive out of the instance, and a result
   11 spends no try and never drops it.
2. **A hidden value `ach_recent`**: up to 20 achievements earned in the last 14 days as `id:day` (day = server days
   since 2026-01-01, base 36). It goes whispered to the officers alone, never in the guild's full record (members have
   no use for it), its entries locked where `ac` routes Only you. An officer who was offline learns from it at the next
   hello's answers, taking at most 20 new entries from one sender a day and no day later than its own.
3. **The server's guild line**, where it comes plain: the achievement id from the link in its text
   (`|Hachievement:<id>:`) and the member by its `guid` argument, checked against the roster. It covers members without
   Cute; a line that is secret is skipped.
4. **Guild news**, on an officer's client: `QueryGuildNews()` 30 s after login and once an hour; on
   `GUILD_NEWS_UPDATE`, or 10 s after the query where none came (17), every player-achievement entry (member by
   `whoText` matched to the roster, achievement by `newsDataID`, day by its date). Guild-achievement entries become
   guild cards (no member: the guild's name and emblem colour, the achievement's icon). Cute never calls
   `GuildNewsSort` or sets the news filters: the game's own view stays as the player left it. That list follows the
   officer's own news filters, so Cute reads
   `GetGuildNewsFilters()` (read only, as the game's news frame does); where the achievements filter is off, guild news
   counts as unavailable for seeding and dating, and `/cute diag cards` and the "Guild first?" tooltip say so.

Members' clients ignore `1A` (nothing for them to do); officers' clients add every earn to the day's achievements row
in the queue (9.1), de-duplicated by member and achievement.

`ac` is declared to reveal `lc_last`, `lc_done`, `lc_pts` and `lc_cats`, and each of them to reveal `ac`: a live earn
tells the latest challenge, its step in Challenges done and its points, so an earn and those stats go the strictest way
of any of them. The harness's registry walk covers `ac` and `ach_recent`.

**Trust.** An earn from a member the officers marked untrusted is dropped. A `1A` for an id `GetAchievementInfo` does
not know on this client is dropped. At most 20 `1A` per sender in ten minutes are taken (a login never fires earns; a
burst past that is an edited copy). A live `1A` is dated by its own time only where that is within 6 hours before it
arrived (an earn held through an instance), else by the officer's `GetServerTime` at arrival. An earn the server's line
or guild news also shows is marked "server" in the queue.

### 5.3 Statistics in halls and records

The game's statistics Cute already defines as dynamic stats (`g<statID>`, per category `gc<categoryID>`, the Statistics
page) are registry stats with a value per member: a hall can pick any of them routed Everyone, and an officer can turn a
record on for any of them ("most", all time). "Times camped" can have a guild record.

### 5.4 Guild firsts

A guild first is the first member of the guild to do something Cute can date. Three kinds, each a suggestion in the
officers' queue, never published by itself:

| First | Known from | Dated by |
|---|---|---|
| An achievement | 5.2's four sources | server time (the server's line; a live `1A` as 5.2 dates it) or the day (`ach_recent`, guild news) |
| A boss killed by the guild | a boss's first corroborated kill (`Rules.lua` rule 9) with no earlier kill of it in the knowledge model | the kill claim's server time |
| The level cap reached | a member's `level` reaching `C.Rules.Cap()` with no member there before | the delta's arrival |

The **ledger** lives on officers' clients only, per guild, in `CuteDB.halls[club].firsts`: per achievement, boss or the
cap, the earliest member, when, and the source; at most 2000 entries (the game's list is finite). It is seeded at an
officer's first login with this version from guild news, every member's `ach_recent` and the knowledge model's kills.
An earn becomes a "Guild first?" item where the ledger is seeded (guild news read this session where the server keeps
it and the filter allows, and 90 s past login so the hello's answers are in) and the ledger had no entry, or had only
one resting on a single member's Cute (that one is shown beside it; the officers choose). Its tooltip says what it
rests on: "No earlier earn in guild news or from any member's Cute." Earns from before anyone ran Cute and older than
guild news keeps are unknown, which is why a first is a question for the officers and never automatic.

### 5.5 What Cute cannot read about another player

Their achievements and statistics, except what their own Cute sends (comparison needs an inspectable unit in range and
the mainline panel); when they earned something, except from their Cute, the server's line or guild news; their own
appearance, gear and portrait without a unit (8.2).

## 6. The awards

Cute's own 26: seven GOLD STAR, nine SHOUT-OUT, eight BLOOPER, and two THANKS cards that only go to a member with
nothing else. Each has a two-letter code for life (uppercase, in `2A` and `1W`; a retired code is never given again,
`Awards.RETIRED`). `n` is the members in the run at its end, a fair share is `1/n`, a median is over the members with a
value. "Rank 1" means the highest value; ties go to fewer deaths, then the smaller GUID. Thresholds in brackets are a
raid's where they differ.

| Code | Kind | Title | Quip | Reads | Holder and threshold | Shows |
|---|---|---|---|---|---|---|
| HD | GOLD STAR | Headliner | Top of the meter, and humble about it. Almost. | `dm` share | rank 1, share at least 1.25 fair shares | "38%" of the group's damage |
| LF | GOLD STAR | Lifeline | Kept everyone upright, some of us twice. | `hl` share | rank 1, share at least 1.25 fair shares | "61%" of the group's healing |
| OS | GOLD STAR | Off Switch | No enemy finished a spell while they were near. | `in` | rank 1, at least 5 (8) | "14" interrupts |
| CW | GOLD STAR | Clean Sweep | Whatever stuck to us, they took off. | `dp` | rank 1, at least 5 (10) | "11" dispels |
| IW | GOLD STAR | Iron Wall | Took the most hits and never hit the floor. | `tk` | rank 1, no deaths, 2 or more bosses down | "212k" damage taken |
| BW | GOLD STAR | Bubble Wrap | Wrapped us in shields like fragile post. | `ab` share | rank 1, more than 0, at least 1.25 fair shares | "44%" of the absorbs |
| TJ | GOLD STAR | Two Jobs | Did their job, then quietly did yours. | `dm` rank, `hl` share | damage rank 1 or 2, healing share at least 15%, not healing rank 1 | "2nd" damage, "22%" healing |
| NS | SHOUT-OUT | Not a Scratch | Zero deaths while the floor filled up. | `de` | no deaths, 3 or more deaths in the group; among several, the most `tk`, then the most `dm` | "0" deaths |
| PW | SHOUT-OUT | Paperwork | Turned the run into a tidy quest log. | `q` together | rank 1, at least 3 quests also handed in by another member of the run | "6" quests handed in together |
| LB | SHOUT-OUT | Lucky Bags | The loot table just likes them more. | `lq`, `ln` | best quality at least 3 (rare); ties by items won | the quality's name, in its colour |
| FH | SHOUT-OUT | Full Hundred | Rolled a hundred. We all saw it. | highest roll | a roll of 100 | "100" |
| TB | SHOUT-OUT | Trailblazer | Walked every corner so the map didn't have to. | `yd` | rank 1, at least 1.2 times the median | "2,140" yards |
| NR | SHOUT-OUT | Narrator | Gave us live commentary, free of charge. | `ch` | rank 1, at least 15 | "23" lines typed |
| DG | SHOUT-OUT | Ding! | Walked in one level, walked out the next. | `lv` | at least 1; the most | "+1" level |
| CM | SHOUT-OUT | Coin Magnet | Every corpse paid them first. | `gd` | rank 1, more than 0 | gold, as `S.FmtGold` |
| WL | SHOUT-OUT | Well Stocked | Came prepared and drank the evidence. | `cn` | rank 1, at least 3 | "7" consumables |
| FI | BLOOPER | Floor Inspector | Checked every floor tile personally. Thorough. | `de` | rank 1, at least 3 | "5" deaths |
| OA | BLOOPER | Opening Act | Went first so we knew what not to do. | first death | the run's first death (4.4) | "3:12" into the run |
| SP | BLOOPER | Spectator | Saw most of the run from the floor. Great view. | `dt` | rank 1, at least 180 s | "7:40" dead |
| WF | BLOOPER | Warm Feet | If it glowed on the ground, they stood in it. | `av` | rank 1, at least 1.5 times the median | "18k" avoidable damage |
| LO | BLOOPER | Lost and Found | Asked where we were. We were right here. | `wy` | rank 1, at least 1 | "3" times asked |
| PG | BLOOPER | Pogo Stick | Jumped so much the boss checked for a dance. | `ju` | rank 1, at least 100 | "341" jumps |
| NA | BLOOPER | Need It All | Needed every drop. Every single one. | need rolls | rank 1, at least 4 | "6" need rolls |
| BD | BLOOPER | Bad Dice | Rolled almost nothing. The dice are sorry. | lowest roll | the lowest roll in the run, at most 5 | "2" |
| GC | THANKS | Good Company | Made the run better just by being in it. | `t` | none | "42:10" in the run |
| SH | THANKS | Steady Hands | Kept calm and kept going. | `de` | none; offered first where the member's deaths are at most the median | deaths |

Quips are at most 56 characters (two lines on a card), in the guild's own friendly voice; the harness fails a longer
one. Warm Feet stays off Send to party: it is the meter's verdict on someone's play, and strangers read the party
line; the other bloopers are antics. An award is **eligible** only where every field it reads is routed Everyone by
this client's policy (section 12) and that policy is settled (`C.Policy:Settled()`), so a closed field takes its awards
off every card, screen and chat line alike.

**The check against Podium.** Before R1 ships, the owner reads every string the card screen shows (these 26 titles and
quips, the labels, the headers, the buttons and the gone-early line) beside Podium's screen in game; one that matches
Podium's is rewritten and its code kept. Podium's own words never enter the repository, so the check is the owner's
eye, once.

## 7. Choosing the run's cards

1. **Who.** Members in the group at the report's end who were in the run 5 minutes or more and did not leave early.
2. **Pairs.** For every eligible award, every member who meets its threshold makes a pair (member, award) with a score:
   the kind's weight (GOLD STAR 3, SHOUT-OUT 2, BLOOPER 2) plus its strength: for "at least X" the value over X, for
   "the lowest" X over the value, capped at 3 either way; fixed for one-off events: Full Hundred 2.5, Bad Dice 2.5 for
   a 1 and 2 otherwise, Ding! 2, Opening Act 1.2. A pair scores 1.5 less where the scribe's history gives the same
   member the same award in either of its last two reports with them, so a regular group's sole healer is not the
   headline every night.
3. **Headline.** The best-scoring GOLD STAR pair is card 1; with none, the best SHOUT-OUT pair.
4. **The rest**, in score order: a member gets one card, an award goes once, at most two BLOOPER cards; where any
   BLOOPER pair exists, the best one is placed before the SHOUT-OUT pairs fill the last cards, so a report with
   something to tease has one blooper. Ties in score go to the kind order (GOLD STAR, SHOUT-OUT, BLOOPER), then to an
   order drawn from the run id (a hash of the id and the award code), so ties fall differently from run to run.
5. **Every member a card** (groups of 2 to 5): a member left without a pair gets a THANKS card: Steady Hands where
   their deaths are at most the median and it is free, else Good Company (a THANKS card may repeat). A report of two
   has no BLOOPER. With 2 to 4 members there are 2 to 4 cards, centred.
6. **Raids** (6 or more members): five cards by the same steps, no THANKS cards; then up to ten **honourable
   mentions**, the next pairs by score, each with a member and an award not on a card.
7. **Same everywhere.** Given the same values and history the choice is the same on every client (no randomness: the
   variety comes from the run id and the history). The scribe's `2A` carries the result, so clients whose values or
   history differ a little still show one report.

## 8. The card and the card screen

### 8.1 Colours for card kinds

Colour by meaning only (the windows design's "one channel, one meaning"). Two tokens beside its palette, used only on
cards, their 3 px bars and their label text, chosen to match no category, item quality or status colour:

| Token | Hex | Contrast on black / PANEL2 | Kind |
|---|---|---|---|
| STAR | #F28AD0 (Cute's pink) | 8.8 / 7.6 | GOLD STAR, GUILD FIRST and RECORD cards; the GUILD FIRST, NEW RECORD and HALL OF FAME headers |
| BLOOPER | #F07C5A | 7.3 / 6.3 | BLOOPER cards; the HALL OF SHAME header |

Every other card (SHOUT-OUT, THANKS, ACHIEVEMENT) has an EDGE bar and its label in WHITE. The DUNGEON and RAID RECAP
headers take GROUP, the dungeons-and-raids category's own colour; GROUP RECAP and GUILD NEWS are WHITE. An item's
quality colour stays on the item's name and value alone.

### 8.2 A card (180 x 372 UI units)

| y | What | Type |
|---|---|---|
| 0-3 | the kind bar, full width | kind colour |
| 10 | the label: GOLD STAR, SHOUT-OUT, BLOOPER, THANKS, GUILD FIRST, ACHIEVEMENT or RECORD, centred | 11, kind colour |
| 28-228 | the picture, 172 x 200 at x 4, PANEL fill: the model, the race model or the icons | |
| 234 | the member's name, centred, cut to 168 (`UI.FitText`) | 15, class colour |
| 254 | the title (an award's, an achievement's name, a stat's label) | 13, WHITE |
| 274-306 | the line (a quip, an achievement's description, an officer's words), word-wrapped to 168, two lines at most | 12, INK |
| 316 | a 1 px LINE from x 12 to 168 | |
| 326 | the value ("14", "38%", "Earned 21 Oct") | 15, WHITE |
| 346 | what the value is ("interrupts", the achievement's category name) | 11, DIM |

A headline or a first has a 1 px WHITE edge instead of black. An achievement card shows the achievement's icon (from
`GetAchievementInfo`, by id: the client holds every achievement's name, icon and description) at 36 units in the
picture's top-right corner, 1 px black edge, over the model or the icons. A guild card (a guild achievement) has no
member: the guild's name in WHITE, the achievement's icon at 96 units in the picture. The tooltip: the card's rule or
source in one line ("Most interrupts, at least 5", "Earned 21 Oct, from guild news") and, for a run card, the member's
other values this client may show.

**The picture.** `Cards.Find(guid)` looks for a unit whose `UnitGUID` is the member's, in this order: `player`,
`partyN` or `raidN`, `target`, `focus`, `mouseover`, `nameplate1` to `nameplate40` (friendly nameplates where the
player shows them). A unit is used only where `UnitIsVisible(unit)` is true and
`C_Secrets.ShouldUnitIdentityBeSecret(unit)` is false (`SetUnit` is `RequiresDeclassifiedUnitIdentity`). With one, a
`PlayerModel` frame (the frame type Blizzard_Communities' GuildNews uses on this client) takes `SetUnit(unit)`,
`SetPortraitZoom(0)`, `SetCamDistanceScale(1.1)`, `SetFacing(-0.35)`, `SetAnimation(0)`. Your own card always has a
model (`player`). There is no model by GUID on this client (no API takes one), so without a unit, or where `SetUnit`
returns false, the **race model**: the same frame takes `SetDisplayInfo` (as GuildNews draws its boss models) with the
base model of the member's race and sex, posed the same, under the class colour at 0.15 alpha. The 20 display ids
(Human male 57899) are the game's structure, like the class list: `build.py` writes them from the client's
`ChrRaceXChrModel` and `ChrModel` tables. It ships only once seen to draw in game (17). Where race or sex is unknown,
or it does not draw, the **icons**:

- the class colour over the picture at 0.15 alpha;
- the race portrait, `Interface\ICONS\Achievement_Character_<Race>_<Sex>` (files 236439-236458 in the client: Human,
  Dwarf, Nightelf, Gnome, Orc, Undead, Tauren, Troll, Bloodelf, Draenei, each Male and Female), 96 units, centred at y
  70, with a 1 px black edge; the race from `C_CreatureInfo.GetRaceInfo(race).clientFileString` (the roster's `race`)
  or `GetPlayerInfoByGUID`'s `englishRace`, written as the file names it (`Scourge` is `Undead`, `NightElf` is
  `Nightelf`, `BloodElf` is `Bloodelf`: the game's file names, fixed like the class list); the sex from
  `GetPlayerInfoByGUID` (2 male, 3 female) or the member's own Cute record (a hidden `sex` value beside `guid`); where
  either is unknown, or the texture does not load (`SetTexture` returns false), no race portrait;
- the class icon, `Interface\ICONS\ClassIcon_<Class>` (625998-626008, 1260827), 32 units at the portrait's lower
  right, or 72 units centred where there is no portrait.

**What a card can show for a guild member out of range:** the name, class, race, level, rank and zone (the guild roster,
`C_Club`), the sex once their GUID is cached or their Cute has said it, the achievement points the server gives every
member, any value their Cute sent within the policy, an achievement's name, icon, description and points (client data
by id), and the date they earned it where their Cute, the server's line or guild news gave it. **What it cannot show:**
their own appearance (no unit: the race model is the race's, not theirs), their gear, their portrait
(`SetPortraitTexture` takes a unit), their achievements or statistics beyond what their Cute sends (comparison needs
inspect range), anything an Only-you value holds.

### 8.3 The card screen (`CuteCardFrame`)

A plain frame (not a UI panel), strata DIALOG, dragged by its header, closed by Esc (`UISpecialFrames`) or Close; the
windows design's tokens and type, BG fill, 1 px black edge, PANEL2 cards. Its modes:

| Mode | Header label | Opens | Where | Buttons |
|---|---|---|---|---|
| Report | DUNGEON / RAID / GROUP RECAP, or TEST RECAP | at a run's end (3.5); from the Runs tab | centred, scale 1 | Send to party, History, Close (a test: Print to chat, Next, Close) |
| Announcement | GUILD NEWS, GUILD FIRST, NEW RECORD, HALL OF FAME, HALL OF SHAME | a click on its toast (9.6); a News row | centred, scale 1 | News, Close |
| Preview | the set's own label, with "PREVIEW" after it | the composer (9.2) | centred, scale 1 | Publish, Back |

Width: 32 + n x 180 + (n - 1) x 12 units for n cards, at least 420 (one card centred); 980 for five. Height 560; a
raid report adds 102 for the mentions (662). Where `UIParent` is narrower than the frame plus 40, it scales to fit.

```
0    16                                                                              964  980
+------------------------------------------------------------------------------------------+ 0
| [cover 130x72] DUNGEON RECAP  (11, GROUP)      Bosses    Time     Wipes    Deaths     [x] |
|                The Deadmines   (20, WHITE)      5/5      42:10      1        7           |  values 15 WHITE, y 18
|                Tuesday 21:40 · 5 members  (11, DIM)                                      |  labels 11 DIM, y 40
+------------------------------------------------------------------------------------------+ 72  (1 px LINE)
| [card 180] 12 [card 180] 12 [card 180] 12 [card 180] 12 [card 180]                         | 88 .. 460
| Gone before the end: Kaz, Pell  (11, DIM)                                                 | 472
|                                                       [Send to party] [History] [Close]  | 502 .. 526, 8 apart
+------------------------------------------------------------------------------------------+ 560
```

- Header: the label at x 16, y 12; the title at y 30 (a report: the instance's name from `GetInstanceInfo`, for a Group
  run the map the group spent the most samples on, `C_Map.GetMapInfo`; a set: its title); the line at y 54 (a report:
  the day, time and members; a set: "Published by Brann · 2 min ago"). Facts on the right, 76 units each, right-aligned
  ending at x 940 (a report: Bosses, Time, Wipes, Deaths; a hall: Members ranked; others none). The 20-unit title is
  the one size above the windows design's 15 and appears only here.
- A dungeon or raid report's header has the instance's cover on its left, 130 x 72 (the EJ art cropped as the windows
  design's pattern C crops it, at 0.75), and the label, title and line move to x 146. Cute_Quest gives it through a
  door beside `Cute.QuestBand`: `Cute.QuestCover(instanceID)` returns the texture and its texcoords. Without
  Cute_Quest or a cover, the `Dungeon` or `Raid` atlas at 20 beside the label.
- Gone-early line: only where there is one; names in class colour, up to 8, then "and N more".
- A raid report's mentions at y 472 in two columns of 474 units, five rows of 18: the title in its kind colour, the
  name in class colour, the value in DIM ("Clean Sweep · Thistle · 14 dispels"); the rest moves down 102.
- Buttons 24 high: Send to party 120 wide, Print to chat 120, History and News 90, Close 80, Publish 90, Back 80.

### 8.4 Send to party (report mode)

Plain text for members without the addon, sent by `C_ChatInfo.SendChatMessage` inside the button's click, all lines in
that one call stack. Channel: RAID in a raid, INSTANCE_CHAT in an instance group (`IsInGroup(2)`), else PARTY. Each
line at most 255 bytes, Windows-1252 text plus the members' names as the game gives them. A blocked post fails
silently: the function returns nothing, and its `HasRestrictions` precondition fails by returning nothing
(`ActionDocumentation.lua`), so Cute cannot tell a post that went from one that did not. It therefore does not post
where it knows the game blocks chat: the button is greyed "After the fight" in combat or while
`C_InstanceEncounter.IsEncounterInProgress()`, and "Outside the instance" while `C_ChatInfo.InChatMessagingLockdown()`
is true; `/cute diag runs` records that state at each post.

```
Cute recap · The Deadmines · 5/5 bosses · 42:10 · 1 wipe · 7 deaths
GOLD STAR · Headliner: Brann, 38% of the group's damage. Top of the meter, and humble about it. Almost.
SHOUT-OUT · Paperwork: Mira, 6 quests handed in together. Turned the run into a tidy quest log.
BLOOPER · Floor Inspector: Kaz, 5 deaths. Checked every floor tile personally. Thorough.
SHOUT-OUT · Trailblazer: Pell, 2,140 yards. Walked every corner so the map didn't have to.
THANKS · Good Company: Thistle, 42:10 in the run. Made the run better just by being in it.
Gone before the end: Rook
```

A raid adds one line, "Also: Clean Sweep Thistle (14 dispels), ..." with as many mentions as fit in 255 bytes. Warm
Feet's line is left out (6). After posting the client sends `2P`; every client that hears it shows "Brann posted"
beside its button, which stays live, since nobody can confirm the post went out. The button is also greyed "Not in a
group" without one, "Sent" after this client posted, and "Waiting for Guild Info" while the policy is in doubt (12). On
a test it is Print to chat: the same lines in your own chat frame (`DEFAULT_CHAT_FRAME:AddMessage`), nothing sent.

### 8.5 The Runs tab and the report history

- Every built or received report is kept in `CuteDB.chars[me].runs.list`, newest first: id, kind, place, instance id,
  start, duration, bosses down and known, wipes, deaths, each member's GUID suffix, name, class, race and sex, the cards
  (suffix, award code, value), the mentions, the gone-early names, your own card. About 600 bytes each; 20 kept by
  default (Settings: 10, 20 or 50).
- The **Runs tab** in J (the Runs module's page, order 45, after Halls): rows in the windows design's pattern A, 20
  units: the 2 px GROUP bar; the `Dungeon` or `Raid` atlas at 16, or `Ability_Rogue_Sprint` (132307) for a Group run;
  the day and time in DIM; the place in INK; on the right the time and "5/5", and your own card's title in its kind
  colour. Click opens the report; right-click offers "Delete from history".
- The band, while a run is on: "Now: The Deadmines · 12:30 · 3 bosses · scribe Brann", and for the leader an End run
  button (70 x 18). With no history: "No runs yet." and a Show a test report button.
- A history report opened later shows models only for members still in the group and in sight; the rest the race
  model or the icons.

## 9. The officers' queue and publishing

### 9.1 The queue

Each officer's client keeps its own queue, `CuteDB.halls[club].queue`: a row for what an officer is likely to publish,
and one digest row a day per source for the rest. At most 100 rows and at most 10 from one sender; a row older than 30
days is dropped; when full the oldest goes first, never a draft.

| Source | Arrives by | Row | Suggested label | The card it makes |
|---|---|---|---|---|
| A guild first | 5.4 | its own, marked "Guild first?"; past 10 in a day, the day's digest | GUILD FIRST | "First in the guild: " and the achievement, boss or level |
| An achievement earned | 5.2 | the day's digest: "12 achievements today" | ACHIEVEMENT | the achievement's name, its description, "Earned 21 Oct", its category's name |
| A run's cards | `1W` (9.3) | its own where a card is a GOLD STAR, else the day's digest | each card's own | the award's title and quip, the value |
| A record that is on, taken by one member's value | 11.3 | its own, marked "Record?" | RECORD, or BLOOPER for a stat of the funny category | the stat's label, "Guild record", the value |
| A hall | the officer's New hall (9.5) | its own | per hall | per stat |
| By hand | New card: a member from the roster, a label, a title, a line | its own | chosen | as typed |
| A draft | Save draft (9.2), up to 6 | its own | the set's | the set's |

A digest row opens in place to its entries, each with a tick box. A record that is off is never queued (the Records
chip shows it). An item marked Only you (its value or earn routes Only you) shows the lock icon and cannot be
published. An item another officer published (a `1C` card with the same source, 13.2) greys "Published by Brann" in
every officer's queue, so the officers share one list's work without a shared queue.

### 9.2 Compose, preview, publish

In J > Halls, the **Queue** chip (officers only) lists the rows in pattern A: a tick box, the source's icon (the
achievement's icon, `INV_Misc_Trophy_Argent` 311945 for a record, the `Dungeon` atlas for a run, `Achievement_General`
236544 for a hall, a card by hand or a digest), the member in class colour, what, when, and "server" or "Guild first?"
marks in DIM. The band: Compose (greyed until 1 to 5 items are ticked), New hall, New card.

**Compose** fills the scroll area, drawn with the Settings column's pieces: the set's title (Edit, 24 bytes, default
from the first item: "Guild first", "Achievements", "Records", "From the runs"); per card its label (Choice), title
(Edit, 24 bytes) and line (Edit, 56 bytes), prefilled from the item; "Also post a line in guild chat" (Check, the last
choice remembered); Preview, Save draft, Clear. **Preview** shows the set in `CuteCardFrame`'s Preview mode with the
guild chat line it would post under the cards, and Publish and Back. **Save draft** keeps the composed set as a row.

**Publish** sends the set on GUILD as `1C` (section 13) and shows it on the officer's own screen as everyone sees it.
Where the check is ticked, the same click posts one guild chat line by `C_ChatInfo.SendChatMessage(text, "GUILD")`, at
most 255 bytes: "Cute · Guild first: Brann earned Legacy of the Wilds." or, for several cards, "Cute · From the runs:
Brann (Headliner), Kaz (Floor Inspector)". A blocked line fails silently (8.4), so the check is greyed "Outside the
instance" while `C_ChatInfo.InChatMessagingLockdown()` is true. Published items leave the queue.

**Withdraw** (officers, on a published set in News): sends `1C` with the set's stamp and `x`; members' clients remove it
from News and close it if shown. **Update** (officers, on a published hall): recomputes its leaders for the same stats
and publishes it again under a new stamp; a This-week hall takes the current week's title ("Week of 27 Oct"), so a
weekly hall is one click a week.

Publish is greyed for an officer who logged in under 3 minutes ago and has not heard an answer to its `1G`, so a set
another officer published while this one was away is seen first.

### 9.3 A run's cards to the officers

When a run with guild members ends, the guild member with the smallest GUID among those with Runs on whispers `1W` to
each officer online (`R:OfficerTargets`, as Only-you values go): it says who grouped with whom and where, which only
the officers' queue uses. The body: the run's kind, instance or map id, start, duration, bosses, and its cards (GUID
suffix, award code, value) for guild members only, about 80 bytes. Who is in the guild comes from the roster as this
client last read it outside the instance (`C_Club` member info goes secret inside). Like `1A`, it waits until the Chat
restriction is inactive out of the instance, and a result 11 never drops it. An officer's client names the place
itself (`GetRealZoneText`, or `C_Map.GetMapInfo` for a Group run), takes a `1W` only from a sender among its members, at
most 4 from one sender an hour, and de-duplicates by instance, members and a start within 10 minutes (clients that
heard no hellos inside may each send one). The cards carry only fields routed Everyone, which for run fields means the
guild and the group (section 12).

### 9.4 What members see

- A published set arrives (`1C`, taken only from a sender `R:OfficerVoice` passes: an officer by the roster, not
  marked untrusted) and is kept in `CuteDB.halls[club].sets` (the last 30). It shows once as a toast (9.6).
- J's **Halls** tab (the core's `shame` page, retitled "Halls"; its id keeps its key), chips: **Hall of Shame** (0.7's
  live cards, drawn as today; their checklist is in Settings > Columns, as the windows design has it), **News** (every
  published set, halls included, and every record that fell, newest first, with a filter: All, Halls, Records; rows
  with the label's colour bar, the set's title, the names, the day; click opens it), **Records** (section 11), and
  **Queue** for officers. The tab opens on News where something came since you last looked, else on the Hall of Shame,
  so a member who upgrades finds the cards they had.
- News with nothing published: "Nothing published yet." in MUTE with Show a test announcement, and for officers
  "Publish the first set from Queue." with Open Queue.

### 9.5 Halls of fame and shame

A hall is a published set whose cards come from stats instead of queue items. The guild has one hall of shame: the
live one on the Hall of Shame chip, and the snapshots of it the officers publish. **New hall** in the Queue chip fills
the composer with: Kind (Choice: Fame, Shame), Period (Choice: All time, This week, Last week), Title (default "All
time", or "Week of 20 Oct", the week's Monday), and five card rows, each a stat from the stat picker ("none" leaves the
card out) with its title and line. A Shame hall starts from the live Hall of Shame's ticked stats, in their order.

- **Periods:** All time takes any stat routed Everyone, its value as it stands; This week only weekly stats (Runs,
  Shout-outs and Bloopers this week, Deaths this week, Quests this week, Raids this week, Logins this week); Last week
  the same stats, each member's value as it stood when it reset on Monday (the officer's roster keeps the value a reset
  replaced, until the next).
- **The stat picker** (`Halls.PickStat`), one menu for New hall and for the Records chip's Add (11.1):
  `MenuUtil.CreateContextMenu` as the windows design's menu uses it, built from `S.byCat` and the game's statistics by
  the client's own categories, a submenu per category, listing only stats routed Everyone that the period allows (or,
  for Add, that can hold a record):

```
Choose a statistic                  (title)
Leveling          > Quests done, Quests this week, Logins this week, ...
Progress          > Bosses killed, Dungeons seen, Raids attended, ...
Hall of Shame     > Deaths, Deaths this week, Fall deaths, Jumps, ...
Runs              > Runs, Shout-outs, Bloopers, Most interrupts in a run, ...
Game statistics   > Combat >, Deaths >, Kills >, Quests >, ...   (the client's categories)
```

- **Leaders:** from the officer's roster: members with Cute, not untrusted, a value the policy routes Everyone, within
  `S.Implausible`'s bounds; highest first (lowest for a fastest clear); ties to the smaller GUID. No member holds two
  cards in one hall: a stat whose leader already has a card goes to its next.
- **Labels:** a Fame hall's first card GOLD STAR and the rest SHOUT-OUT; a Shame hall's cards all BLOOPER.
- **Default text:** a card's title is the stat's label; its line one of five per kind, one for each place ("The guild
  salutes you." and four more for Fame, "We will never let this go." and four more for Shame), so no hall repeats one.
- Preview and Publish as 9.2; the announcement's label HALL OF FAME or HALL OF SHAME, the facts "Members ranked".

### 9.6 Rate limits

- **Publishing:** an officer's Publish is greyed for 60 s after a set from any officer `R:OfficerVoice` passes (heard on
  GUILD; answers to `1G` excluded, 13.2), and after 10 sets in an hour from that officer.
- **Showing:** a set shows first as a toast: one row, 420 x 48 at top centre, 100 units below the screen's top, with the
  label in its colour, the title and up to three names in class colour; a click opens the set in `CuteCardFrame`; it
  fades after 10 s unless the mouse is over it. One toast at a time, three waiting, at most two an hour; the rest go to
  News quietly. Never in combat, an encounter, a loading screen or inside a dungeon or raid instance: waiting toasts
  show after `PLAYER_REGEN_ENABLED` and out of the instance. A sender past 10 sets in an hour, and an answer to `1G`:
  News only.
- **The guild line:** a client with Cute hides it (`ChatFrameUtil.AddMessageEventFilter` on `CHAT_MSG_GUILD`: a plain
  line beginning "Cute · " from the officer whose set came in the last minute), so members with Cute see a set once;
  a secret line is left alone.
- **Records:** a NEW RECORD toast for the same instance once a day at most; a change within the day updates News
  quietly.
- **Settings > Halls "Announcements on my screen"** unticked: News only, no toast.

### 9.7 The test screens

- **Report:** Settings > Runs "Show a test report", the empty Runs tab, `/cute run test` (`/cute run test raid` for 40).
  In a group, your real group members (so the models show) with made-up values; alone, you and four made-up names
  ("Mossbottom", "Kettlewick", "Pell", "Thistle") with race models. Each test draws a new set of five awards from the
  26 (`Awards.Sample`); the label reads TEST RECAP, Print to chat (8.4) and Next sit beside Close, and nothing is sent,
  saved or counted.
- **Announcement:** Settings > Halls "Show a test announcement" and `/cute card test`: the toast, then a set of three
  cards: you with your newest earned Legacy Challenge (your own `GetAchievementInfo` data; a made-up line where you have
  none), "Kettlewick", a made-up member with a race model, under GUILD FIRST, and a NEW RECORD card for a made-up
  clear. `/cute card test hall` shows a Hall of Shame from the live cards. Nothing is sent or kept.
- **An officer's set:** Preview is the test of the real set, its guild line included; nothing goes until Publish. Each
  record row on the Records chip has Preview: the card its holder would get now.

## 10. The stats cards read

New registry stats, core (`Stats.lua`), counted only where Runs is on (except the two weekly ones Sample counts), so a
client with Runs off still decodes, ranks and shows them. All but `sex` are `slow` (Comm's slow flush), so a report
adds no delta of its own:

| Id | Label | Code | Category | Kind | Record |
|---|---|---|---|---|---|
| `runs` | Runs | `ru` | runs | int, grows; reveals `runs_week` | most, all time |
| `runs_week` | Runs this week | `rw` | runs | int, weekly | most in a week |
| `honors` | Shout-outs | `ho` | runs | int, grows: GOLD STAR and SHOUT-OUT cards, THANKS excluded; reveals `honors_week` | most, all time |
| `honors_week` | Shout-outs this week | `hk` | runs | int, weekly | most in a week |
| `roasts` | Bloopers | `rx` | runs | int, grows; reveals `roasts_week` | most, all time |
| `roasts_week` | Bloopers this week | `rk` | runs | int, weekly | most in a week |
| `pb_ints` | Most interrupts in a run | `ip` | runs | int, a personal best, `hi` 2000 | most in one run |
| `pb_dispels` | Most dispels in a run | `dp` | runs | int, a personal best, `hi` 2000 | most in one run |
| `pb_deaths` | Most deaths in a run | `dq` | runs | int, a personal best, `hi` 200 | most in one run |
| `deaths_week` | Deaths this week | `dw` | funny | int, weekly (Sample, `PLAYER_DEAD`) | most in a week |
| `quests_week` | Quests this week | `qw` | leveling | int, weekly (Sample, `QUEST_TURNED_IN`) | most in a week |
| `c<instanceID>` | Fastest clear: the instance's label | category code `cc`, routed the strictest of `cc` and the instance's own `i<instanceID>` | clears (a discovered category, as `S.FOUND`) | int seconds, dynamic, `lo` 120 | fastest, per instance |
| `ach_recent` | (hidden) recent earns, 5.2 | whispered to officers; locked by `ac` | hidden | text, 200 bytes | none |
| `sex` | (hidden) 2 or 3, beside `guid` | always | hidden | int | none |

`deaths` is declared to reveal `deaths_week` and `quests_done` `quests_week`, as each lifetime count already reveals
its daily one, so no weekly value opens what its lifetime count keeps closed; the harness's registry walk checks every
pair. Weekly stats reset on Monday as Logins this week does. A report bumps `runs`, `runs_week`; a GOLD STAR or
SHOUT-OUT card `honors`, `honors_week`; a BLOOPER card `roasts`, `roasts_week`, each from the card this client's own
build gives you (a `2A` only shows); the personal bests take this run's own `in`, `dp`, `de` where higher; a full
clear sets `c<instance>` where faster (`S.IsDynamic` accepts `c` beside `g e f i k`). Test reports bump nothing.
Existing stats also eligible for a record: Deaths, Bosses killed, Quests done, Dungeons run, Raids attended, Jumps,
"where are you" typed, Fish caught, Ghost run yards, Gold earned, and every game statistic (`g<statID>`); all "most",
all time. A stat is eligible where `Stats.lua` marks it `record = "max"` or `"min"` (statistics by their kind).

## 11. Guild records

### 11.1 Which records are on

Every record ships off. Officers turn one on where they look at records, on the Records chip (11.3): each row has an
on/off switch for officers and Preview (the card its holder would get now); the chip's band has Add (the stat picker,
9.5) for a game statistic; Fastest clears is one row for every instance at once. The list travels in `1O` (section 13),
taken only from a sender `R:OfficerVoice` passes; a change goes at once, coalesced to one message a minute. Turning a
record on fills it with today's best silently.

A **fastest clear** that is on is announced by itself when it falls, since two members' values back it (11.3): the
owner's "guild wide announcement when they do happen", for something hard to beat. Any other record rests on one
member's Cute alone, and one voice does not make a guild-wide claim (the privacy spec), so when a different member
takes one that is on, the officers' queue gets it as "Record?" and the announcement is an officer's Publish. A record
that is **off** changes quietly on the chip; nothing is queued.

### 11.2 The table

Every client keeps the guild's records it may see in `CuteDB.halls[club].records`: per eligible stat, per instance for
clears, and per game statistic added, the value, the holder's GUID and name, and when; at most 400 entries.
`Records:Seen` runs on every value the roster takes and on your own.

### 11.3 When a record falls

- **Beats:** a higher value for "most", a lower one for "fastest". A value from a member the officers marked
  untrusted, or outside the stat's bounds (`S.Implausible`), is not one.
- **A fastest clear needs two voices:** two guild members' values for that instance within 5 seconds of each other
  (everyone in a run sets the same time); the second voice makes it a record.
- **Live only:** the value came in a delta (`1D`), not a full record (`1F`) answering a login's ask, and 90 seconds
  after this client's login; or it is your own value changing. What changed while you were away updates the table
  quietly.
- **Announced** (a fastest clear that is on): where it beats the record by 5% or more and every voice's level (the
  roster's) is at most the top of the instance's level range (`Rules.lua` rule 3, learned in play; no range known, not
  announced), so a group far above a dungeon takes the record quietly. Announced means a NEW RECORD toast on every
  client, within 9.6's limits, opening one card (the holder, RECORD, the instance's name as the title, the line "With 4
  guild mates." where `gr` routes Everyone, else "New guild record.", the time) and a News row. A holder raising their
  own record, and any record that is off, update it quietly. No message is sent: every client sees the same deltas and
  decides alone (an officer's client makes the "Record?" row).

**The Records chip** in J > Halls: rows in pattern A grouped "In one run", "In a week", "All time", "Fastest clears":
the trophy icon at 16, the stat's label, the holder in class colour, the value on the right, the day in DIM; for
officers, the switch and Preview at the right. Fastest clears list the instance's name and, where `gr` routes
Everyone, "Brann and 4". Empty: "No records yet: they fill in as the guild plays." in MUTE.

## 12. Privacy

- **What never leaves your client:** what you type (lines are counted; the "where are you" match runs on your own line
  as you send it, and only the count is kept), whispers, positions and paths (yards only), the meter's per-spell and
  per-target detail, your report history, the officers' queue and ledger (each officer's own).
- **Only-you routing holds.** Every `2V` key has a policy code (4.1). New codes, two letters for life in `Stats.lua`,
  each a row in Settings > Who sees what, default Everyone: under a "Runs" heading `rm` Meter in runs, `rq` Quests in
  runs, `rc` Chat lines in runs, `yw` Yards in runs, `rl` Loot in runs (as `S.RUNFIELDS`); and `ac` Achievements. The
  other `2V` keys reuse the stat they are the same thing as (`de`, `we`, `ju`, `cn`, `le`, `ge`). A key whose code
  routes Only you is **not sent on the group channel at all**, so no card, mention or chat line can carry it; its
  awards are not eligible. The harness fails a key without a code.
- **Everyone, for run fields, means the guild and the group you run with.** Settings > Who sees what says so in the
  Runs heading's note. The reused codes were set for the guild alone, so their keys go in `2V` only while every member
  of the group is in the guild (the roster as last read outside the instance); with anyone else in the group they are
  left out, and that member's deaths come from `UNIT_DIED` as for a member without Cute. A member outside the guild in
  your group sees the cards; their own client sends what its own guild's policy allows. `1W` carries guild members'
  cards only, to the officers alone.
- **A policy in doubt sends nothing new.** While `C.Policy:Settled()` is false (a reload or relog inside the instance:
  the privacy spec's doubt), RunComm sends `2H` and the keys `t` and `o` only, no award is eligible so this client's
  own report waits until the policy settles, Send to party is greyed, and a scribe in doubt sends no `2A` (the others
  build their own after 20 s).
- **Achievements:** an earn routed Only you is whispered to officers and appears in their queue with the lock; it can
  never be published. `ach_recent` goes to the officers alone; `ac` and the Legacy Challenge stats reveal each other
  (5.2).
- **Other members' values you observe** (the meter's rows, deaths, loot rolls: what the game's own meter and loot
  window show the whole group; the server's guild line and guild news, which the game shows the whole guild) are used
  for members whose `2V` lacks them; never sent anywhere except in the scribe's `2A` and the cards of `1W`.
- **A scribe of another guild** whose `2A` carries an award this client's policy does not allow: this client shows its
  own build instead.
- **Run stats in the dashboard** follow their codes like any stat: Only-you ones go to the officers by whisper.
- **Published sets and records** carry only values routed Everyone at publish time; a member's client drops a card
  whose source (13.2) its policy now routes Only you, and `Policy:Purge` deletes records it may no longer hold.
- **The site:** Cute's saved file never goes to foreverrank.com (the uploader refuses `Cute.lua`, windows design 11.2).

## 13. Messages and budget

### 13.1 The group channel

Prefix `CuteRun` (`C_ChatInfo.RegisterAddonMessagePrefix`), channel RAID, INSTANCE_CHAT or PARTY as 8.4 chooses. Comm's
receive takes GUILD and WHISPER only, so nothing of this reaches it; RunComm takes a message only from a sender whose
name is a group unit's, and a GUID suffix in a message only where that unit's GUID ends with it.

| Kind | Body | Sent |
|---|---|---|
| `2H` | `2H|<run>|<version>|<flags>` | at start; on resume; the scribe's answer to a newcomer (another holder's only after 2 to 6 s with none heard) |
| `2V` | `2V|<run>|<seq>|<i>/<n>|k=v;...` | at each checkpoint (3.4) and at the end; whole, the highest seq kept |
| `2Q` | `2Q|<run>` | the scribe, at the group's end |
| `2A` | `2A|<run>|<i>/<n>|k=v;...`: kind, instance or map id, start, duration, bosses down and known, wipes, deaths, members; cards and mentions as `suffix.CODE.value`; gone early as suffixes | the scribe, after `2Q` |
| `2E` | `2E|<run>` | the leader's End run |
| `2P` | `2P|<run>` | after Send to party |
| `2R` | `2R|<run>|<suffix>` | a member back from a crash |
| `2W` | `2W|<run>|<suffix>|i/n|k=v;...` | the scribe: that member's last checkpoint, back |

**Who is heard.** A group member with an edited copy can send anything, so: `2Q`, `2A` and `2W` are taken only from the
unit this client works out as scribe (3.2), `2W` only after this client's own `2R`, `2E` only from the leader, a `2H`
only as 3.2 bounds its id. From a `2A` a client takes codes, suffixes and numbers alone: it names the place itself and
each member from its own observations (an unknown suffix is dropped). A `2V` value outside its key's bounds (4.1) is
dropped; where this client observed a member's value itself (a meter row, a `UNIT_DIED` count) and the two are more
than a tenth apart, the observed one wins and a guild member's record is marked suspect for the officers. A member the
officers marked untrusted is ranked on observed values alone.

**The queue** (RunComm's own; Comm's is the guild's): one message a second; hellos, `2E`, `2Q`, `2A` ahead of `2V`; a
newer `2V` replaces a waiting one; checkpoints go out of combat. Results as Comm reads them
(`Enum.SendAddonMessageResult`): 3 and 8 (throttle) try again in 3 s, five times; 5 (`NotInGroup`) empties the queue;
11 (`AddOnMessageLockdown`) spends no try and drops nothing: the queue waits for `ADDON_RESTRICTION_STATE_CHANGED` with
type `Chat` and state `Inactive` (`Enum.AddOnRestrictionState`, as `Cute_Quest/Pins.lua` waits for `Inactive`). The
event also fires with `Activating` just before a restriction starts, and `IsAddOnRestrictionActive` reads false during
any of its dispatches, so that function is read only on a 5-second timer, never inside the event.

**A lockdown for the whole stay.** The game makes chat secret on a dungeon or raid map
(`SecretPredicatesDocumentation.lua`: `SecretInChatMessagingLockdown`), and whether addon messages to PARTY and RAID
follow it is not in the source (17). If they do, nothing of the run's leaves inside: the hellos, checkpoints and end go
when the group comes out, the run id and the scribe settle then (3.2), and a group that disbands inside gets reports
each client built alone. `/cute diag runs` records each result 11 with whether an encounter was on, and shows
`C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()`.

**Sizes**, from a full `2V` (23 keys, 6 quests, every value non-zero): about 170 bytes, one message; absent and zero
keys make most smaller. `2A`: about 140 bytes for five members (one message), about 420 for a raid's five cards, ten
mentions and gone-early suffixes (two).

| Run | Messages on the group channel | Bytes | Per client |
|---|---|---|---|
| 5 members, all with Cute, 5 bosses | 5 hellos + 25 checkpoints + 5 final + 1 `2Q` + 1 `2A` = 37 | about 5 KB over the run | about 7, at most one a second |
| 40 members, all with Cute, 8 bosses | 40 + 320 + 40 + 1 + 2 = 403, and one answer (two at most) per member who joins late | about 55 KB over a 3-hour raid | about 10; after a kill the raid's 40 checkpoints spread over 15 s, about 3 a second on RAID |

### 13.2 The guild channel

New kinds on Comm's prefix and queue. A Cute older than this ignores them (Comm's dispatch has no branch for them).
`1R`'s format is left alone: 0.7's parse of it is anchored at the end, and a new field would break it.

| Kind | Body | From | Taken by | Size and count |
|---|---|---|---|---|
| `1A` | `1A|<id>|<time>` | a member's client at an earn, held while inside (5.2) | officers' clients (members ignore it); whispered to officers where `ac` is Only you | about 20 bytes; one per earn (one per officer online, whispered) |
| `1W` | `1W|<run>|k=v;...`: kind, instance or map id, start, duration, bosses, cards `suffix.CODE.value` | the run's guild member with the smallest GUID, whispered, held while inside (9.3) | officers' clients | about 80 bytes; one per officer online per run |
| `1C` | `1C|<at>|<i>/<n>|h=<kind>,<title>,<by>,<period>;c=<suffix>,<name>,<class>,<race>,<sex>,<label>,<icon>,<source>,<title>,<line>,<value>,<value label>;...`; `1C|<at>|a|...` for an answer to `1G`; `1C|<at>|x` to withdraw | an officer's Publish | every client, from a sender `R:OfficerVoice` passes | about 150 bytes a card: up to 5 messages a set |
| `1O` | `1O|<at>|<code>.<code>...` | an officer's change of the records on | every client, from a sender `R:OfficerVoice` passes | one message |
| `1G` | `1G|<newest set at>|<records at>` | every client, once, 60 s after its hello | officers' clients | one message |

- Text in `1C` loses `| ; = ,` (`Stats.CleanText`, a comma made a space); `icon` is a file id (a number) or empty;
  `name` 12 bytes at most, for a member the receiver's roster lacks. `source` says where a card came from: `a<id>` an
  achievement, `r<run>.<CODE>` a run's award, `s<stat id>` a record or a hall's stat, empty for a card by hand. By it a
  member's client drops a card whose stat or award its policy now routes Only you (12), and every officer's client
  greys the queue item it matches (9.1).
- **Answering `1G`:** an officer whose sets or records list are newer answers with the sets newer than the asker's (the
  last five at most, so 25 messages at most) and `1O`: the officer with the smallest GUID after about a second, the
  others after 4 to 8 seconds and only where nothing as new was heard meanwhile. One answer covers every asker
  waiting, as Comm does for `1R`, and one asker is answered once in half an hour. Marked `a`, an answer goes to News
  without a toast (it is old news), greys no officer's Publish and counts toward no sender's hourly limit.
- **Run stats and records:** values of the registry like any other, merged into the delta waiting (Comm's rule): a
  report adds at most one `1D` per member, usually none (the run stats are slow); a record sends nothing. The new
  stats add about 150 bytes to every full record (Comm keys it by id: "runs_week=" and the rest), under one more `1F`
  chunk per member answering an ask; `ach_recent` is not in it.
- **Guild chat lines** (9.2) and **Send to party** (8.4) are chat, not addon messages: one line per publish where the
  officer ticked it, up to eight per report where a member clicks.

| Day of a guild of 300, 60 online | GUILD addon messages |
|---|---|
| 40 achievement earns | 40 `1A` (and whispers where `ac` is Only you) |
| 15 runs with guild members | none on GUILD; 15 `1W` to each officer online, whispered |
| 3 published sets | up to 15 `1C` |
| 60 logins | 60 `1G`; an answer only where an officer holds a newer set, up to 25 `1C` for every asker waiting; each answering member's full record about 150 bytes larger |

## 14. Module and settings

**Runs** is a built-in module (`id = "runs"`, `title = "Runs"`, `order = 45`, `default = true`), its page the Runs tab
in J, its events heard only while it is on. The windows design's setup card gains a row "Run reports after dungeons,
raids and long groups", ticked. Since Runs starts sending values to the group, the card comes back once with this row
alone for a character that answered it already, as that design does for a new window's row. Switching it on or off
follows that design's reload rule.

**Achievements** (`id = "ach"`) and **Records** (`id = "records"`) are built-in modules too, on by default with the
guild base, in Settings > Modules. A member may switch either off (Achievements: no `1A`, no `ach_recent`; Records: no
table, no Records chip, no record toast); officers switch either off for the whole guild beside it, carried in the
officers' policy line as Who sees what is. Cards, the queue, halls and News are not modules: they are the guild base,
so every member sees what the officers publish whatever modules they run.

Settings > Runs, four rows:

| Row | Control | Default |
|---|---|---|
| Show the report when a run ends | Check | on (off: collected, sent, kept in history) |
| Long groups outside instances (2 or more, 15 minutes) | Check | on |
| Keep | Choice: 10, 20, 50 reports | 20 |
| | Buttons: Show a test report, Last report | |

Settings > Halls, two rows: Announcements on my screen (on), and Show a test announcement. The live Hall of Shame's
card checklist stays in Settings > Columns (windows design); the records' switches are on the Records chip (11.1).

Slash words: `/cute run` (the last report), `/cute run end`, `/cute run test [raid]`, `/cute halls`, `/cute card test
[hall]`, `/cute diag runs` (the meter's availability and reason, sessions read, the run's id, kind and scribe, this
client's message counts in the last run, the restriction state, each result 11 and whether an encounter was on, the
chat lockdown state at each post), `/cute diag cards` (guild news entries read and the news filters, the server's lines
seen, the ledger's size, sets held, records on).

## 15. Testing

Cute's harness (`cd tools/cute && luajit harness.lua`, ending `layout problems: 0` then `OK`), one `luajit` at a time.
Each case fails on the files before it. The mock gains only documented or Camelot-called APIs, each where the harness's
rule says (an undocumented one in `UNDOCUMENTED` with its evidence): `C_DamageMeter` (sessions, sources,
`isLocalPlayer`, secret in combat, a `sourceGUID` made secret on request, `DAMAGE_METER_RESET`, unavailable with a
reason), `C_LootHistory` (with `GetLootHistoryTime` on its own clock), `PlayerModel` frames (`SetUnit` recording its
unit and returning false for an out-of-sight unit; `SetDisplayInfo`), `UnitIsVisible`,
`C_Secrets.ShouldUnitIdentityBeSecret`, `C_Map.GetBestMapForUnit` (nil for a `raidN`), `GetUnitSpeed`,
`C_RestrictedActions.IsAddOnRestrictionActive` (false during the event) and `ADDON_RESTRICTION_STATE_CHANGED` (type
and state, `Activating` before a restriction), `C_ChatInfo.InChatMessagingLockdown`,
`C_ChatInfo.AreOutgoingAddonChatMessagesRestricted`, `C_InstanceEncounter.IsEncounterInProgress`, `UNIT_DIED`,
`UnitRace`, `UnitSex`, `GetPlayerInfoByGUID`, `C_CreatureInfo.GetRaceInfo`, `C_Club` member `race`,
`ACHIEVEMENT_EARNED`, `CHAT_MSG_GUILD_ACHIEVEMENT` (plain and secret), `QueryGuildNews`, `GetNumGuildNews`,
`GetGuildNewsFilters` (all called by Blizzard_Communities' GuildNews on this client), `C_GuildInfo.GetGuildNewsInfo`,
`GUILD_NEWS_UPDATE`, `ChatFrameUtil.AddMessageEventFilter`, a group bus for PARTY and RAID addon messages (with a
lockdown for a whole instance on request) and for `SendChatMessage` to PARTY, RAID, INSTANCE_CHAT and GUILD (a blocked
call returning nothing).

| # | Scenario | Holds |
|---|---|---|
| 1 | Five clients run a dungeon to a full clear and zone out | one report on every client within 20 s; the same five cards everywhere; the leader is the scribe; one `2A`; no client sends more than one message a second |
| 2 | Three with Cute, two without | the two get cards from the scribe's meter rows and `UNIT_DIED`; a member with no data at all gets a THANKS card; every member one card |
| 3 | The group disbands at the last boss's death | every client builds from the checkpoints; the five reports are identical |
| 4 | Lockdown | a `2V` answered 11 waits for the Chat restriction's `Inactive` event, not the `Activating` one, spends no try and goes once; a lockdown for the whole instance: nothing goes inside, the run id and scribe settle after the group comes out, a disband inside gives each client its own report, `1A` and `1W` go once outside with their times; the meter read only after `PLAYER_REGEN_ENABLED`; a secret `sourceGUID` leaves only the own row; secret chat events and a secret guild achievement line read nowhere |
| 5 | Pictures | `SetUnit` only on a visible unit with plain identity, found in the order of 8.2 (a target and a nameplate included); without one the race model by display id; the icons with a race portrait for a known race and sex, the class icon alone where either is unknown or the file does not load; no reason line; your own card always a model |
| 6 | Reload, relog and crash mid-run | a reload resumes with no new run and deaths counting on; a relog within 30 minutes resumes; a crash restores from the scribe's `2W`; a reload inside with a stale policy that opens `rm` or `de` sends only `2H`, `t` and `o` and builds no report until the policy settles |
| 7 | Corpse runs and leaving | a ghost leaving the instance changes nothing; the scribe alive outside ends after 3 minutes (10 in a raid); a full clear ends at once; a member out mid-run is on the gone-early line |
| 8 | A raid of 40 | five cards and up to ten mentions, no member twice; the frame 662 high; each client at most 3 messages at the end; each member joining late draws one `2H` answer, two at most; a `raidN` outside your subgroup is never "on another map" |
| 9 | Open world | 2 together 15 minutes give a report with two cards and no blooper, 14 minutes none, 1 none; entering a dungeon ends it and starts a Dungeon run |
| 10 | Privacy | the officers close `rm`: no meter key in any `2V`, no meter award, no meter value in Send to party, `1W` or a set; a key without a code or bounds fails; a member outside the guild in the group: no reused-code key in any `2V`; `ac` Only you: `1A` whispered to officers, never on GUILD, its queue item locked and unpublishable; `ac` and `lc_*`, and each lifetime count and its weekly one, go the strictest way; `1W` only whispered |
| 11 | Chat lines | Send to party and the guild line at most 255 bytes, no text outside Windows-1252 but names; sent only inside the click; Send to party greyed in an encounter, in chat lockdown, without a group, while the policy is in doubt; another member's `2P` shows "Brann posted" and leaves the button live; on a test, Print to chat sends nothing; Warm Feet never on the party line; the posting addon's own lines never counted as typed |
| 12 | The choice | no repeats; at most two bloopers and one where any is eligible, none in a report of two; the headline a GOLD STAR where one is eligible; each of the 26 awards reachable from a fixture; thresholds at their edges; a repeat in the scribe's last two reports scores lower; ties fall by the run id; the same cards from the same input and history on every client; every quip at most 56 characters |
| 13 | Achievements | an earn sends one `1A`; `alreadyEarned` and guild achievements send none; officers add it to the day's digest, members ignore it; an unknown id, an untrusted sender and a 21st `1A` in ten minutes are dropped; a `1A` dated more than 6 hours before it came is dated by its arrival; the server line and guild news make queue entries for a member without Cute, marked server; `ach_recent` at most 20 entries and 200 bytes, never in the guild's full record |
| 14 | Firsts | an earn with no ledger entry after seeding is "Guild first?"; one with an earlier entry in guild news is not; one whose earlier entry rests on one member's Cute is, with that entry beside it; guild news with the achievements filter off seeds nothing; a boss's first corroborated kill and the first member at the cap are suggested; nothing is published without an officer's click |
| 15 | Queue and publishing | compose 1 to 5 items, preview with the guild line, publish: every member shows the set once; a `1C` from a member, or from an officer marked untrusted, is ignored; a published item greys in the other officers' queues; withdraw removes it; Publish greyed for 60 s after any set and after 10 in an hour, not after an answer; 10 rows per sender; drafts never evicted; halls computed with no member twice and only Everyone stats; Update rolls a weekly title on; Last week from the values before the reset; `1G` answered once in half an hour with at most five sets, shown in News without a toast |
| 16 | Showing | one toast at a time, three waiting, two an hour, the rest to News; none in combat, an encounter or an instance until after; the setting off gives News only; Cute's own guild line hidden on Cute clients; the test announcement sends and keeps nothing |
| 17 | Records | every record off at first; a second voice within 5 s makes a clear record and one toast on every client; a clear by members above the instance's range is quiet; a login's full records announce nothing; an untrusted or implausible value is no record; a holder's own improvement is quiet; a "most" record that is on becomes a "Record?" row, one that is off nothing; a statistic record |
| 18 | Layout | `CuteCardFrame` in report (with and without a cover), raid, announcement (1 to 5 cards) and preview mode, the toast, the stat picker, the Halls tab's chips, empty News and composer, the Runs tab, at J's default and minimum sizes: no clipped or overlapping text, nothing on an edge, lines in two lines at most; render pass pictures read before each release |
| 19 | Memory | a raid run's saved state bounded (40 members, 16 quests each); history, sets, queue, drafts, ledger, pending earns and records at their caps; a stored member record's growth from the new stats counted; no table made per poll; the meter read only out of combat |
| 20 | An edited copy in the group | a `2Q`, `2A` or `2W` from a member who is not the scribe is ignored; a `2A`'s names and place are not shown; a `2V` value out of bounds is dropped, and one an observed value contradicts loses; a `2H` id older than 30 s before this client's start is ignored |

**In game** (the owner's testers, Norwegian Windows clients), each with `/cute diag runs` and `/cute diag cards`
pasted: section 17's open questions; a five-person run with the report on all five screens; Send to party after a boss,
checked in another member's chat; a Legacy Challenge earned with an officer online; a published set seen by a member
far away (the race model) and one in the group (the model); a raid's message counts.

## 16. The page line

`addons/cute/index.html`: one changelog line per version (R1 "Run reports: after a dungeon, a raid or a long group,
a card for each of you, with Send to party.", R2 "Guild news, halls of fame and shame: the officers publish cards
everyone sees.", R3 "Achievements and guild firsts reach the officers' queue.", R4 "Guild records, and a toast when a
fastest clear falls."). The page's window mock gains the report screen drawn from the test report's sample run and one
announcement card, phone-first. No list of awards, achievements or what a run counts on the page.

## 17. Unverified in game, and what the code does either way

| Question | Either way |
|---|---|
| Does the meter record with its window switched off (`damageMeterEnabled` 0)? | Sessions empty after a fight: `mt` 0, meter fields absent, meter awards ineligible for that member; another client's rows still fill members without Cute. `/cute diag runs` shows it. |
| Is `sourceGUID` plain out of combat inside a dungeon? | Plain: every member's rows read. Secret: own rows only; members without Cute have no meter values. |
| Does `SetUnit` draw a party member at a dungeon's end, a target, a nameplate unit? | It returns false or the unit is out of sight: the race model. |
| Does `SetDisplayInfo` of a race's base display id draw a character? | No: the race model is left out and the icons stand. |
| Does `SendChatMessage` from a click post to PARTY, RAID or GUILD inside an instance outside an encounter? | Nothing tells: a blocked call returns nothing. The button and the guild-line check are greyed while `C_ChatInfo.InChatMessagingLockdown()` is true or an encounter is on; `/cute diag runs` records that state at each post, and the testers check the lines arrived. |
| Does `AddOnMessageLockdown` apply to PARTY and RAID only in encounters, or for the whole stay in a dungeon or raid? | Encounters only: the queue waits them out. The whole stay: nothing of the run's goes until the group comes out (13.1); the run id and scribe settle then, a disband inside gives each client its own report, `1A` and `1W` go outside. `/cute diag runs` records each 11 with whether an encounter was on. |
| Is `C_Map.GetBestMapForUnit` of a `raidN` outside your subgroup readable? | Treated as unknown either way (3.1): no gone-early by map and no wipe by map for those members. |
| Does `QueryGuildNews` alone fire `GUILD_NEWS_UPDATE`? (The game's frame calls `GuildNewsSort` after it, which Cute does not.) | No: Cute reads the list 10 s after its query (5.2). |
| Is `GetUnitSpeed("player")` secret anywhere? | Secret readings count nothing; `yd` may be low, its awards rarer. |
| Does `CHAT_MSG_LOOT` carry the looter's GUID? | Absent: `lq` and `ln` come from the loot history alone. |
| Does Forever's server send the guild achievement line, and fill guild news, for Legacy Challenges? | No: earns reach officers by `1A` and `ach_recent` only, members without Cute are not seen, and firsts rest on Cute's sources alone, which the "Guild first?" tooltip says. |
| Do the race portrait files load on this client? | `SetTexture` returns false: the class icon alone. |

## 18. Decisions taken here

| Where the brief left room | Decision | Section |
|---|---|---|
| One card system | One frame, `CuteCardFrame`, with report, announcement and preview modes; one queue; one `1C` publish | 2, 8, 9 |
| One prefix or two | `CuteRun` for the group; Comm's `Cute` stays the guild's | 13 |
| Who builds the report | Every client can; the scribe (leader, else smallest GUID) sends one so all agree, and only its end messages are heard | 3.2, 3.3, 13.1 |
| Disband before anything is sent | Checkpoints after every boss kill; where the game holds addon messages for the whole instance, each client's own report | 3.4, 13.1 |
| Corpse runs and repair trips | A ghost outside changes nothing; alive outside ends after 3 minutes (dungeon) or 10 (raid), at once on a full clear | 3.3 |
| "Together" in the open world | The same map by `C_Map.GetBestMapForUnit`, for the player and party members (in a raid, your subgroup); `UnitInRange` returns secrets | 3.1 |
| Groups of 2 | Reported, with two cards and no blooper (the owner's "parties") | 3.1, 7 |
| Members without Cute | Cards from what the game shows the group or guild (meter, deaths, loot, the server's line, guild news); a THANKS card where there is nothing | 4, 5, 7 |
| Labels | Cute's own, not the screenshot's: DUNGEON / RAID / GROUP RECAP; GOLD STAR, SHOUT-OUT, BLOOPER, THANKS; ACHIEVEMENT, GUILD FIRST, RECORD. The owner checks every string of the card screen beside Podium's | 6, 8 |
| Awards | 26, one per angle; variety from the run id and the scribe's history, never randomness | 6, 7 |
| Card order | Headline first, then by score, left to right | 7 |
| Bloopers | At most two in five, one where any is eligible, none in two | 7 |
| Everyone for run fields | The guild and the group you run with; Only-you never on the group channel; the reused codes' keys only in an all-guild group | 12 |
| Send to party | All lines in the click; quips included; not where the game blocks chat; `2P` says who posted and leaves the button live, since a blocked post fails silently | 8.4 |
| The model out of range | The race's base model by display id, then the game's race and class icons; no reason line | 8.2 |
| Where cards, halls, records and achievements live | Cards, the queue, halls and News are the guild base; Runs, Achievements and Records are modules a member or the officers can switch off | 2, 14 |
| How an earn reaches officers | `1A` on GUILD or whispered by the `ac` code, held while inside; `ach_recent` whispered for those offline; the server's line and guild news where Forever gives them | 5.2 |
| Firsts | Three kinds (achievement, boss, level cap), a ledger on officers' clients, always a suggestion, never automatic | 5.4 |
| Records | Every record off at first. A fastest clear that is on is announced by itself (two voices, within the instance's level range, 5% better): the owner's "very hard to beat". Any other record one member's value takes goes to the queue as "Record?", since one voice makes no guild-wide claim. Off: the Records chip only | 11 |
| A run's cards to the officers | One `1W` per run, whispered to the officers by the run's guild member with the smallest GUID | 9.3 |
| Hall periods | All time, This week and Last week; new weekly stats for deaths and quests | 9.5, 10 |
| One hall of shame | The live cards on their chip; a published Shame hall is a snapshot of them | 9.4, 9.5 |
| "queue and publish" | Each officer's own queue and drafts: rows for what is likely published, a daily digest for the rest; a published item greys in every officer's queue; no scheduled publishing | 9 |
| Guild chat on publish | One line, only where the officer ticks it in the composer, shown in Preview; hidden on Cute clients | 9.2, 9.6 |
| Where published sets travel | `1C` per set (additive, stamped), `1O` for records on, `1G` to ask; not in Guild Info, which is the policy's | 13.2 |
| Announcements | A toast, two an hour, the set on a click; held until out of combat and out of the instance; off means News only | 9.6 |
| Runs on by default | Yes, as a ticked row on the setup card, which comes back once for it because it sends data | 14 |

## 19. Out of scope

- Anything that needs the combat log (4.5); a per-boss report.
- Reading another player's achievements by inspection (5.5); a member's own appearance with no unit.
- Exporting runs or cards to OXM or WarcraftLogs; a web page of news, halls and records; sending them to the site.
- Scheduled publishing; officers editing award titles or quips (they write a set's cards only); a shared queue between
  officers (each officer's queue is their own; a published item greys in all of them).
- Sounds; translations (the text is English on every client, Norwegian included).

## 20. Sub-projects, in order

| # | Sub-project | Ships | Depends on |
|---|---|---|---|
| R1 | **The run report** (Cute's next free version after the windows round's C) | the Runs module: starts, ends, scribe, checkpoints, recovery; the own counts and Sample's hook point; the meter and loot readers; `CuteRun` and its queue; the 26 awards and the choice; `Cards.lua` with the card, the picture, the race model and the icons, `CuteCardFrame` in report mode with the cover; Send to party; the history and the Runs tab; the test report; the run field codes in Who sees what; `runs`, `honors`, `roasts` and their weekly stats, `sex`; scenarios 1-12, 18, 19 and 20 for what it ships; the check against Podium | the windows design's C (J and its tabs; before C ships, the Runs tab is a tab of 0.7's window) |
| R2 | **Cards and publishing** | the Halls tab and its chips; the queue with its digest rows, New card, compose, preview, publish, withdraw, the guild chat line and its filter; halls with Update and the stat picker; `1C` with sources, `1G`, `1W`; the toast and announcement mode with their rate limits; the test announcement; `deaths_week`, `quests_week`; scenarios 15, 16 | R1 |
| R3 | **Achievements and firsts** | the Achievements module: `1A` and the `ac` code with its reveals, the pending earns, `ach_recent`, the server's guild line, guild news and its filters, the ledger and its seeding, the three kinds of first, achievement and first cards in the queue, statistics in halls; scenarios 13, 14 | R2 |
| R4 | **Records** | the Records module: the personal bests and fastest clears (`c` dynamic, category `cc`); `1O`; `Records:Seen` with its rules; the clear toast and "Record?" rows; the Records chip with its switches and Preview; statistic records; scenario 17 | R1, R2 |
