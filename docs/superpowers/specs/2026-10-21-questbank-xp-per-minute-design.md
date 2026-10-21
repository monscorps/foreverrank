<!-- Owner, 2026-10-21: "quests + time walking & time to do quest comparatively to XP it gives. I would rather go in a zone with 3 quests for 5k each than one with 15 for 15k total." Numbers below are awk replicas of Lists.lua over Data.lua, not harness runs. -->
# QuestBank: rank by XP per minute (design, 2026-10-21)

Cute_Quest's engine files are byte-identical copies (cute/build.py:42), so every change below reaches Cute.

## 1. How it ranks today
- **Quest** (Lists.lua:722-727): `(XP + ½ chain) × 1/(1 + (trip + giver→turn-in + 3)/10)`.
  - The 3 dates from 3.4.1 (04df85e): "so one at your feet isn't infinite". It guards against dividing by zero; it does not measure anything.
  - A giver the catalog can't place counts a flat 10 min.
  - Nothing counts the objectives.
- **Waste** (732): fewer than 60×Scale XP a minute.
- **Now places** (936): `(left + avail)/(1 + nearest/20)`.
  - `avail` (891) sums XP × drop weight × time factor over every quest you don't hold, including chain steps you can't take yet.
  - `nearest` (894) is the closest giver of any of them, even a locked one.
- **Available**: places in level-band order; rows by raw XP (UI.lua:2604).
- **Guide fill** (Guide.lua:309-361): rank × drop weight (counted a second time) × party bonus; reach min(20, 3+level) minutes.
- **Planner**: questing forces goal "route" (Core.lua:2494, 2509), so `better()` (Model.lua:558) compares final level, then minutes.
  - With a fixed set of stops that is just "fewest minutes".
  - A stop worth under 400×Scale goes last (409, 505-516).
- **Cute** (PageQuests.lua:34-58): the top three of PlaceGroups(nil,true) by `fetch+left`; "Highest XP" is Candidates(8).
- **Time to level** (Guide.lua:555) assumes "a minute a quest of doing".

## 2. What there is to estimate time with
- **Objective data:** D.SPOT covers 37% of quests (1,457 of 3,934). Another 874 have only D.REQ items; 1,603 have neither (deliveries, talk quests, or Forever's own quests with no data).
- **Counts and drops:** D.SREQ gives counts per slot; D.DROP is the worst item's drop %.
- **Density:** objectives.json already stores spawn counts per area (Solomon's Law: 101 Shadowhide within 209 yd). gen_data.py:1932-1945 drops them from D.OBJ.
- **Flags:** group (237 quests), dungeon (418), escort (141), started from an item.
- **Pace:** RUN 7 yd/s and DETOUR 1.3 (Model.lua:22). M.Factor uses Legacy's measured speed.
- **Players' data:** Timer.lua already keeps `{a=accept, d=hand-in}` per quest (Timer.lua:5-6, 132-142).
  - These are wall-clock times that include travel, other quests and logouts.
  - The 11 uploads in research/probe that carry a timer table have **zero** quest rows.
  - **Nothing records time spent at objectives.**

## 3. Model
**Quest minutes:** `T = away + walk·mf + work·kf + 0.5`
- **away**: today's trip to the giver; 0 if held or the item is in your bags. If the giver can't be placed, use the trip to its turn-in, and fall back to 10 only when that is unknown too.
- **walk**: giver → objective areas (nearest first) → turn-in, at 1.3 × straight line / 7 yd/s. Legs that cross water use travel.py's minutes.
- **work**:
  - kill N: N × (25 s + gap), gap = √(πr²/n)·1.3/7 s. Kills beyond the n spawns cost at least 300 s / n each.
  - collect N at p%: N/p kills (p = 50 when unknown).
  - use or object N: N × (6 s + gap).
  - explore or buy: 30 s. Escort or event: 6 min. A named single spawn: +60 s.
  - delivery: 0.
  - group quest: ×3 when solo.
  - unknown: the zone's median, shown as "est.".
- **Storage:** gen_data writes D.DO[id] = walk tenths × 4096 + work tenths. A players' median replaces the estimate at 3 or more samples.
- **kf** (this character's speed): median of measured/estimated over the last 20 completions, clamped to 0.5-2.

**Recording** (Timer.lua, called from Discover.lua's look). On every look where objectives tick:
1. Call `Timer.Tick(id)`. dt = min(now − last tick, 90 s), split equally among the quests that ticked in that look; add the share to `w`, and 1 to `k`.
2. On the first complete, set `c` and `lv`.
3. The table stays bounded at 300 quests and holds ids and numbers only.
4. probe_pull.py merges `w` (when k ≥ 3) into disc.json `dur` with no character key; gen_data takes the median.

**Rate:** `(XP + bundle)/T`.
- A chain head bundles its next ≤3 open steps when that raises the rate. This replaces "+½ chain" (the 965 delivery, worth 680 XP, carries 966).
- Locked steps count only inside their head's bundle.

**Floor:** `F = max(60×Scale, 0.6 × measured XP/min)` (Timer.XPPerHour).

**Place value:** `V = ΣXP / (trip to the set's first giver + ΣT − shared)`.
- **The set:** quests takeable now, plus the ones you hold, whose own XP/min excluding the trip is at least F.
- **Shared:**
  - Quests whose D.OBJ areas lie within 300 yd of each other (UI.Together's rule) pay the walk once.
  - Quests that kill the same creature need the max of their kills, not the sum.

**Where it is used:**
- **Now:** places ordered by V.
- **Available:** rows ordered by rate; the minutes column shows T.
- **Fill:** the best place's set first, in rate order. The drop weight goes (it is inside T now); waste = rate < F.
- **Planner**, questing goal "rate":
  - `better()` compares levels per hour, `(af−start)·60/(at+W)` with W the route's remaining work, then minutes.
  - Cheap = `worth < F × (2 × minutes to its nearest stop + its work)`. REACH and PASS are unchanged.
- **Time to level:** ΣT.

## 4. Numbers
Assumptions: level-21 Alliance mage on foot, nothing done in these zones. The awk replicas are in this scratchpad (today.awk, qtime.awk).

**Today from Southshore:** Darkshore 18,233 > Redridge 14,835 > Loch Modan 12,048 > Wetlands 10,518 > Westfall 8,505 > Duskwood 8,406.
- Of Darkshore's 55 candidates, 33 are later chain steps, supplying 12,202 of its 20,239 avail.
- Its "2.2 min" is The Absent Minded Prospector (943), a locked fifth step given in Menethil.

**Today from Lakeshire:** Redridge 30,532 > Duskwood 16,330 > Darkshore 14,972. Darkshore's "nearest" here is "Making Do", given in Stormwind.

**Hillsbrad** has no Alliance quest at 21: the lowest is Down the Coast, quest level 30, required level 25.

**New, per quest** (giver → objectives → turn-in):

| Quest | XP | min | XP/min |
|---|---|---|---|
| An Unwelcome Guest | 1,950 | 2.9 | 670 |
| Blackrock Bounty | 2,000 | 12.8 | 156 |
| Murloc Poachers + Selling Fish | 2,800 | 18.4 | 152 |
| Solomon's Law | 1,850 | 13.8 | 134 |
| Blackrock Menace | 1,650 | 15.3 | 107 |
| Digging Through the Ooze | 2,400 | 14.3 | 168 |
| Claws from the Deep | 1,750 | 13.2 | 132 |
| Tower of Althalaxx 965+966 | 2,030 | 10.6 | 192 |
| Fruit of the Sea | 1,250 | 18.1 | 69 |
| Dusky Crab Cakes | 780 | 15.5 | 50 (left out) |

**Places from Southshore** (quests that are open and have spawn data):
- Redridge: 10,250 / (8.2 + 59.9) = **150 XP/min**
- Wetlands: 7,850 / (2.2 + 67.3) = **113**
- Darkshore: 6,230 / (10.1 + 51.0) = **102**
- Duskwood: 8,500 / (9.1 + 92.7) = **83**

Darkshore drops from first to third.

**Single quests, trip included:**
- Today the ranks sit within 1.7×: An Unwelcome Guest 907, Selling Fish 590, Fruit of the Sea 541.
- New, the spread is 3.9×: 171, 47 and 44 XP/min.

**Toy check:** every giver is 10 minutes away.
- **Today:** each quest's time factor is 0.435, so both places score **6,522**, a tie. A 16th small quest would win it for the many-quest place.
- **New:** three 5k quests in 24 min score 15,000/34 = **441 XP/min**. Fifteen 1k quests in 72 min score 15,000/82 = **183**.

## 5. Risks
- **63% of quests have no spots.** Deliveries are rightly 0; unknown quests show "est." until players' times arrive.
- **The 25 s kill time is a guess.** kf corrects it per character, and it is a tunable.
- **Chains:** bundles look at most 3 steps ahead. A step done outside its category's zone (943) is timed from its own giver.
- **Group quests:** ×3 solo, ×1 when a party member holds it.
- **Grey quests:** XpAt's penalty already pushes them under F. Keep the Fill's rule that a grey quest needs its chain to pay.
- **Dungeons:** treat each as one place, with 35 min per run until Timer measures instance enter-to-leave. Held dungeon quests stay "Do" steps (pendingRow).
- **Jitter:** keep Now's order unless a challenger is 5% better (the SWITCH rule).
- **Memory and garbage:** D.DO is one number per quest, and T is pure arithmetic.
  - Cache T in one reused table, cleared on QB.changed (Core.lua:2690), level, mount or kf.
  - Memoise PlaceGroups, since Cute calls it twice per redraw.
  - Nothing runs per frame, and `evaluate` gains only numbers.

## 6. Changes and harness
**Files:**
- **gen_data.py:** keep the count in D.OBJ (1927-1947); emit D.DO.
- **probe_pull.py:** merge `dur`.
- **Timer.lua:** add Tick and SpeedFactor. **Discover.lua** look() calls Timer.Tick.
- **Model.lua:** add QuestMinutes and Floor; change the cheap rule (403-410) and `better()`/`clearly()` (558, 797).
- **Core.lua:** 2494 and 2509 use goal "rate" when questing.
- **Lists.lua:** Candidates (710-733); PlaceGroups (865, 891, 894, 929-937).
- **Guide.lua:** G.Rank, G.Fill, line 555.
- **UI.lua:** 2283 (minutes) and 2604 (row order).
- **PageQuests.lua:** placeRow and "Highest XP".

**Existing asserts to update** in harness.lua: 8899 and 8902. Banking at 7584 stays unchanged.

**New F62CASES** (level 21, char() as at 17607):
1. The toy: today ties; new, A ≥ 2×B.
2. Minutes by kind: 34 < 5; 127 > 15; 146 = 0 work; 945 ≥ 6; 98197 shows "est.".
3. Southshore (map 1424): Redridge comes before Darkshore, and Darkshore's trip is not 2.2.
4. Lakeshire: the Fill takes Redridge quests in rate order.
5. Bundles: 965 ranks with 966; 943 counts only after 942.
6. Recording: a 10-minute gap counts 90 s; two quests in one look split the time; the table trims at 300; it holds no strings.
7. kf 0.5 after five fast completions.
8. Planner: a 450-XP stop 6 min off the route goes last; within PASS it stays.
9. Garbage: 100 PlaceGroups calls with QB.changed fixed stay under a set bound.

**Cute:** in tools/cute/harness.lua, PageQuests' first place is the engine's Now order[1].
