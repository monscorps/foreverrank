# Cute: what we know, and the rules that learn the rest

Nobody knows what is in WoW Forever at launch (November 2026). Cute ships with what research and the beta told us,
marks how sure each fact is, and from there builds and guides on its own: a fixed set of rules turns what guild
members meet in play into knowledge, shares it on the guild channel and keeps it. Past level 30 (the beta's cap) and
wherever the game turns out different, the rules take over from the seed. No addon update is needed for the guild to
learn a dungeon, a boss, an enchant slot or a level range.

Builds on 0.4.0 ("learned, not listed": learned enchant slots, discovered bosses, instances and reputations, the 1L
labels message, consumables by item class).

## The seed: `Cute/Known.lua`, generated

`tools/cute/gen_known.py` writes it from the repo's research data; never edited by hand. Every fact carries its
source and confidence.

| Fact | Source in the repo | Confidence |
|---|---|---|
| Dungeons: name, instance (map) id, level range, new-in-Forever flag, faction | `codex/loot.json` (34 dungeons), `research/wago/<latest>/Map.csv`, `LFGDungeons.csv` | `beta` where the range starts at or below 30 and players' loot records exist, else `data` |
| Bosses per dungeon: name, encounter id, order | `codex/loot.json` bosses, `DungeonEncounter.csv` (name and map id join) | `beta` / `data` as above; dungeons with no known bosses (Krol'dok Stronghold, Alcaz Prison, Blackmaw Hold, Shaper's Terrace) seed none |
| Boss loot: item ids per boss | `codex/loot.json` | as the boss |
| Enchantable slots and the enchants for each | `codex/recipes.json` Enchanting recipes (not flagged `sod`), `SpellEquippedItems`/`SpellEffect`/`SpellItemEnchantment.csv` for the slot | `data`; today: wrist, chest, cloak, hands, feet, main hand, two-hand, shield, neck. No head, shoulder or legs |
| XP to the next level, 1-59 | QuestBank's `D.TO_NEXT` (read from the client) | `beta` to 30, `data` above |
| Factions | `Faction.csv` joined with what reputation rewards `QuestFactionReward.csv` names | `data` |

The generator picks the newest Forever build under `research/wago/`, prints counts per table and confidence, fails on
a dungeon whose map id it cannot join, and is idempotent. `build.py` runs it before zipping.

## Launch may be a different game

We might log on on 4 November and find an entirely different game. So the seed is a guess the addon can throw away,
never something it depends on:

- **Rule 0, the seed is checked against the live client at login.** The ids it names are asked of the client
  (items with `C_Item.GetItemInfoInstant`, enchant spells with `C_Spell`, factions with
  `C_Reputation.GetFactionDataByID`, the build with `GetBuildInfo`). A fact whose id the client does not have is
  dropped as `absent`. If more than a set share of the seed is absent (default 30 %), or the build's major version
  differs from the seed's, the whole seed is marked `stale`: nothing from it counts as missing or recommended, the
  Guide says "the game differs from what we knew; learning from the guild" and runs on observations alone.
- **`beta` is not trusted past the beta.** On a build other than the seed's, every `beta` fact starts as `data` until
  the guild sees it.
- **Every page works with no seed at all.** The harness runs every scenario a second time with an empty seed.
- **Officers can retune the rules in game.** Every threshold (members needed to learn a range, runs before a boss is
  doubted, days before an enchant slot is doubted, the stale share, the guide's level windows) is in Settings for
  officer ranks and travels with the visibility policy, so the guild adapts the rules on launch day without an addon
  update. `/cute rules` prints them and their source (default or set by whom).

## The rules

Each rule is one function in `Cute/Rules.lua`, named, documented in place and in the README, with its thresholds in one
table at the top so they can be tuned in one place. A fact's state is `data` (believed), `beta` (seen in the beta),
`seen` (seen by this guild in play) or `doubted` (the guild's play contradicts it). Observations come from members'
records and the `1L` message; knowledge lives in `CuteDB.known` and is rebuilt from saved records at login.

1. **Seen beats believed.** Any guild observation of a fact makes it `seen` with its count and first time; tooltips
   say "seen by N members" or "from research" / "from the beta".
2. **New things join.** An instance entered or a boss killed that the seed lacks is added as `seen`, under the
   instance it was met in.
3. **Level ranges learn.** A dungeon's range becomes the 10th to 90th percentile of the levels members had when they
   killed its bosses, once 5 distinct members have; until then the seed's range stands. Each boss kill record carries
   the killer's level.
4. **Doubt, never delete.** A seeded boss that 3 distinct members' full runs of its dungeon never met is `doubted`:
   shown dim with "not seen in 3 runs". A seeded enchant slot nobody has after 14 days of members at 30 or more
   wearing items there is `doubted` and stops counting as missing.
5. **Enchant slots.** A slot counts as enchantable when the seed says so (recipe exists in Forever) or one member has a
   permanent enchant there. "Missing enchants" = worn slots that count, not enchanted.
6. **XP curve learns.** Each member reports `UnitXPMax` at each level they reach; once 3 members agree on a level,
   that value replaces the seed's. Hours to 60 uses the learned curve.
7. **Level cap.** The cap is the game's (`GetMaxPlayerLevel`, else `GetMaxLevelForPlayerExpansion`, as QuestBank
   reads it); the highest level any member reaches never exceeds it; the seed's 60 is the fallback.
8. **Loot learns.** Items from a boss's corpse loot window (LOOT_OPENED after that encounter) are added to the boss's
   loot as `seen`; seeded loot not seen in 5 kills stays `data`.

## Guiding: a Guide page

Rules drive a Guide tab (after Race), for you and, for officers, the guild:

- **Dungeons for your level**: the dungeons whose (learned or seeded) range holds your level, the bosses you have not
  killed in each, and the guild members online within three levels who have the addon (a group to ask).
- **Next up**: the dungeons opening in the next five levels.
- **Gear**: missing enchants (rule 5) with the enchants Forever has for that slot.
- **Pace**: hours to the next level and to the cap at your pace and at the guild's median.
- **Officers**: for each dungeon, how many members are in range, how many have killed each boss, and the facts the
  guild changed from the seed (new bosses, learned ranges, doubted entries): the diff a guild can share with the
  site later.

## Wire

- Boss kills already travel as `e<encounterID>` counts with labels in `1L`; the first-kill level travels with the
  label pass (`1L|e<id>=name~instance~i<instanceID>~L<level>`).
- XP at a level travels as a slow stat `xpmax` with `level`; receivers keep the per-level samples.
- No new message type. The login budget stays under 20 messages in the first minute.

## Testing

Harness scenarios: the seed loads and its tooltips say its source; rule by rule with the thresholds at their edges;
a new dungeon past 30 with no seeded bosses filling in from kills; a seeded boss doubted after 3 runs; a range learned
from 5 members; the XP curve corrected by 3 members; the Guide page for a member and an officer at both window sizes.
`gen_known.py --selftest` checks the joins and the counts.

## Page

One sentence: Cute starts with what research and the beta showed and learns the rest as the guild plays. Changelog
line for 0.5.0. No catalogue.
