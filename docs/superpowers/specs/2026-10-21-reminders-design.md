# Reminders: one quiet place, a click that acts (design)

Date: 2026-10-21. Builds on **QuestBank 6.1.1 and Cute 0.7.1 as shipped** (main @ 475c4e2): the camp bar and the
missing-buffs banner with its party row (`tools/questbank/QuestBank/Camp.lua`, byte-identical in
`tools/cute/Cute_Quest`), the step frame (`StepFrame.lua`), the Guide's Train step (`Guide.lua`), learned flights
(`Travel.lua`). Fits into `2026-10-21-cute-windows-design.md` (the visual system of section 8, Settings of section 7,
layout mode of section 6, the first-run card of section 3; what this changes there is listed at the end of section 2)
and `2026-10-20-questbank-guide-design.md` (the step frame). API truth: `research/wow-ui-source` at HEAD (forever
branch, 1.60.1); client tables `research/wago/1.60.1.70338`. Every API below was checked there; what only the live
client can answer is section 11.

## 0. Summary

1. Two pieces in one place, named for players **Reminders** (camp, upkeep, class, items) and **Buffs** (yours, your
   party's, "Before the pull") stacked on it. Both gone in a fight and back 2 s after it. No chat, no sounds, ever.
2. Every reminder is a 32 px game icon with one word under it; full colour means a click acts now, desaturated means
   a click shows the way on the arrow. A 2 px category bar only for buffs (WHITE), XP (QUEST) and group (GROUP).
3. Launch set: the owner's twelve plus ammo. Buffs, party buffs, before the pull, sit, place, the fire slot, eat,
   sleep, repair, bags, hearth, talents, items to use on screen; train, flight path and the bag's quest chain as one
   line in the step frame.
4. Each reminder appears in exactly one place (today food and the camp feature show twice).
5. Shown when acting is cheap: upkeep in town or near the place that fixes it, elsewhere only at its worst; a pause
   reminder you walk away from snoozes itself.
6. Learned from habits, not single casts: a buff joins after you recast it twice, and leaves after two lapses.
7. Off: one Settings section "Reminders" of 8 rows; right-click anywhere on a piece: "Not now" (the piece, 10 minutes)
   or "Never: <that reminder>" (undone under its row).
8. One engine: reminders are providers registered with a new `Remind.lua`; Cute gets them through its Reminders
   module, on by default (today Cute players get none by default).
9. Event-driven: no OnUpdate unless a timer, a minutes word or a party row is showing; no table or string made per
   refresh that did not change.
10. Fixes folded in: Train that never clears, untrained spells forgotten a level later, Thorns on every member, a
    bright icon for an out-of-sight member, no flight-path prompt on a new continent, no seller for a walk-away fire,
    Eat on water and bread, Eat lit after a meal.

## 1. The owner's words, and what this design does with each

| Words (2026-10-20/21) | Here |
|---|---|
| "I did not get the notification bar about missing buffs and options to click them on me" | Buffs: one icon per missing buff of yours, a click casts it on you (shipped in 6.1.1; Cute players need the Reminders module, on by default, section 7) |
| "same options to click on missing buffs I can do on party members if I'm not in a raid" | The party row: in a party, not a raid, one icon per member who lacks a buff you can give (section 4) |
| "didn't suggest me to /sit on a nearby camp in Redridge" | "Sit" from the game's Campfire Nearby aura, plus the soft-interact cooking fire as a learned fallback; the static fires need one look in the live client (section 11) |
| "when fire disappeared it didn't suggest NPC that sells fire and wood" | The fire slot (3.2): out of kits when you stop outside a town, or in town near the seller: a cook gets the seller's minutes, a non-cook the cooking trainer once |
| "still haven't suggested me sleeping bag either" | The bag's chain becomes a step-frame line from level 14, one step at a time, never a grey icon with its words in a tooltip (3.3) |
| "less is more on guidance as long as it's modular and easy to change and clear" | One icon per thing, one word each, one line in the step frame, one provider per reminder, one Settings section |
| "colours to categorise, in-game icons" | The 2 px category bar in the windows palette where it cannot be mistaken; game art only (section 2) |
| "fully ready triple-A for the guild ... real quality of life when starting to play" | On by default in QuestBank and through Cute's Reminders module; quiet in a fight, in chat and in town |

## 2. How reminders look and behave

**Two pieces, one place.** **Reminders** (`QuestBankCampBar`, saved at `remind.pos`, default CENTER 0,-190) carries
the camp, upkeep, class and item reminders. **Buffs** (`QuestBankBuffBanner`, saved at `remind.bannerPos`, nil = 8 px
above Reminders, as today) carries buffs: yours, then your party's; its title "Missing buffs" becomes "Before the
pull" on a ready check or raid entry. These two names are the only ones a player sees (movers, Settings, the Lock
note). Nothing else draws reminders: no toasts, no raid warnings, no chat lines, no sounds. Both sit in one holder that
the game's state driver hides in a fight (`RegisterStateDriver(holder, "visibility", "[combat] hide; show")`, as the
banner's holder does today, `Camp.lua:1085`). Code never hides the holder (the driver would show it again): "Nothing",
`remind.on` off and Not now hide the pieces. At `PLAYER_REGEN_ENABLED` the pieces wait 2 s (a new fight cancels it)
and fade in over 0.2 s; Reminders no longer dims to 0.45.

**The reminder icon** (pattern D, added to the windows design's section 8):

- 32 px game icon on both pieces (today 40 on the bar), cropped 0.08-0.92, 1 px black edge, 6 px apart; the game's
  Cooldown sweep where a cooldown runs; a count at its bottom right in 10 px WHITE outlined.
- Under it a 2 px bar, the icon's width, in its category colour, for buffs, XP and group only.
- Under the bar one word at 11 px INK, outlined and shadowed (it stands on the world): the verb or the minutes. Only a
  status word takes a status colour: "Low" or "2 free" in WARN, "Broken", "Full" or "None" in BAD.
- **Lit**: full colour; a left-click acts now (secure button). **Waiting**: desaturated at 0.55; a left-click puts
  its place on the arrow (an ordinary hook, as `goSeller` does, `Camp.lua:573`). No glow behind either.
- Tooltip: name in WHITE, one line saying why, "Click: <what happens>.", "Right-click: not now, or never." Nothing
  about a reminder lives only in its tooltip.
- Buffs icons carry no word (the title says it); party icons carry the member's name under them in class colour,
  11 px, as today. Buffs loses today's dark plate, black edge, gold line and X (`Camp.lua:1094-1112`).

**Categories** (the windows palette; status colours stay status words):

| Category | Bar | Reminders | Why |
|---|---|---|---|
| Buffs | WHITE #F5F5F5 | your class buffs, weapon imbues and poisons | your own state, the base colour |
| XP | QUEST #FFD100 | sit, place, the fire slot, eat, sleep, the bag's quest line | each gives XP on Forever (Welcoming Campfire, Well Fed XP Boost 1243969, Well-Rested 429959) |
| Group | GROUP #4FD1C4 | party members' buffs, Before the pull | the windows design's dungeons-and-raids colour |
| Upkeep | none | repair, bags, ammo, hearth, use, buy | the status word carries WARN or BAD |
| Class and travel | none | talents, train, flight path | the class icon carries the class; a class-colour bar would collide (Priest #FFFFFF is WHITE, Rogue near QUEST, Mage near GROUP) |

**Rules for all of them.**

- **A click acts when the game allows it.** Casting, using an item, `/sit`, opening talents or bags: secure
  attributes, set out of a fight only, as `type1`, which is an unmodified left click alone (`SecureTemplates.lua:8-9,
  28`), so a right-click never casts and Alt-drag stays free (today's plain `type`, `Camp.lua:1152, 1181, 1278`, is
  why a right-click casts now). Items always as `item:<id>`, never bag and slot: `SECURE_ACTIONS.item` equips an
  equippable item (`SecureTemplates.lua:433-434`), so a slot gone stale after a sort could equip and bind a BoE. What
  the game does not let an addon do is a waiting icon that shows the way instead.
- **Nothing in a fight.** Hidden by the state driver; no reads while `InCombatLockdown()`, while
  `C_Secrets.ShouldAurasBeSecret()` is true (`SecretPredicateAPIDocumentation.lua:119`), or while
  `C_RestrictedActions.IsAddOnRestrictionActive` says Combat or Encounter. Every aura field, `sourceUnit` included,
  still passes through `QB.Plain` (single spells can be always secret, `SecretPredicatesDocumentation.lua:80-82`). The
  last laid-out state stays; `PLAYER_REGEN_ENABLED`, and `ADDON_RESTRICTION_STATE_CHANGED` whose payload says Inactive
  (looked at on the next frame, since the check reads false during that event, `RestrictedActionsDocumentation.lua:58`;
  as `Pins.lua:170-171`), mark everything for one fresh look.
- **Never chat.** The only line any reminder prints is the reply to `/qb buffs` typed by the player (`Camp.lua:1247`).
- **Not while away**: dead or a ghost, on a taxi, in a vehicle, in a cinematic. Inside a dungeon or raid, what the
  Settings choice says (section 6).
- **When acting is cheap.** A reminder shown at a pause (the fire slot, Sleep) that you walk away from without
  clicking snoozes itself like Not now. Upkeep shows in town or within 2 minutes of the place that fixes it, elsewhere
  only at its worst (3.2).
- **At most six on Reminders**, in a fixed order so nothing jumps: sit, place, fire slot, eat, sleep | repair, bags,
  ammo, hearth, use, buy | talents, then the step-frame line's fallback (3.3). Past six the last ones wait, except a
  status in BAD, which always takes a slot: the last camp icon gives way. Buffs: six of yours, four party members.

**What this changes in the windows design** (amended there when it is next edited): section 3's card row "Camp bar
and missing buffs" reads "Reminders"; section 6's movers are "Reminders" and "Buffs" and the Lock note says "the step
frame, the arrow, Reminders and Buffs"; section 7's Camp section becomes the Reminders section of section 6 here, and
the Modules row's "Camp" reads "Reminders"; section 9 (line 645): Buffs icons are 32 px like Reminders' (22 px is
small to click at screen centre), and right-click opens the menu of section 6, whose Not now is that ten minutes.

## 3. What ships for launch

Common to every row: out of a fight, auras readable, alive, not on a taxi; "Not now" is 10 minutes (`Camp.SNOOZE`)
unless the row says otherwise, and comes back early if a reminder on the piece gets worse.

### 3.1 Buffs

| Reminder | Shows when | Icon | Click |
|---|---|---|---|
| **Your buffs** | A buff of `Camp.SELF[class]` whose spell you know (any rank, `C_SpellBook.IsSpellKnown`) is not on you, by spell id. `also` becomes ids (built from `SkillLineAbility.csv` by `gen_data.py`), so a localised client matches. Adds: the Paladin auras (Devotion as the cast, any aura counts); **learned buffs**, by habit: an aura you cast (`sourceUnit` "player"), 10 minutes or more, a spell you know, not in `Camp.SELF`, joins once you recast it within 2 minutes of it running out on two separate occasions, and is forgotten after two lapses you did not recast (per character, up to 8). One swim never teaches Water Breathing | the spell's icon | `type1=spell`, highest known rank, `unit=player` |
| **Your weapon** (rogue, shaman, anyone who oils) | The same habit rule per weapon item (not per hand, so a fishing lure is never offered for a sword): no temporary enchant on it (`C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot)`, 0/1/2, a list, `timeLeft` in ms; `C_PaperDollInfo.GetTemporaryEnchantmentInfo(INVSLOT)`), and you still carry or know what you last put there: the spell cast or item used in the second before the enchant appeared. Items: the stones and oils (SpellEffect 54) and poisons (SpellEffect 360) that `gen_data.py` reads from ItemEffect → SpellEffect (all class 0 subclass 8 or class 7 subclass 12), plus learned | the poison's, oil's or imbue's icon | item: `type1=item`, `item:<id>`, `target-slot` 16 or 17 (`SecureTemplates.lua:771`); imbue: `type1=spell` |
| **Party members' buffs** | Section 4 | the spell's icon, the name under it | `type1=spell`, `unit=partyN` |

Never offered or learned: Righteous Fury and the other tanking toggles (a wrong cast hurts), short buffs (Battle
Shout), pets (after launch, section 3.4).

### 3.2 Reminders

| Reminder | Shows when | Icon · word | Click |
|---|---|---|---|
| **Sit** | Campfire Nearby (1283391) on you, neither Welcoming Campfire (1229739, 1289723) nor Camp Benefits (1229741), not mounted. Fallback, while `C_Secrets.ShouldUnitIdentityBeSecret("softinteract")` is false: the soft-interact GameObject's entry (from its GUID, any language) is a Cooking Fire spell-focus object (focus 4, from CMaNGOS `gameobject_template` by `cmangos.py`) and the aura is missing: shown 15 s; if 10 s still after your /sit click brings no Welcoming aura, that entry is kept as "gives nothing" | the campfire icon · "Sit"; while you sit, the Welcoming aura's countdown "0:42" | `type1=macro`, `macrotext=/sit` (sitting is restricted to secure code, `SitStandOrDescendStart`, `PlayerScriptDocumentation.lua:1772`) |
| **Place** (camp feature) | Your own kit's fire lit within 300 s (a kit's fire is the one that holds camp features, `Camp.lua:10`; other fires wait for section 11), a feature you carry whose buff you lack, the shared hour up (`Camp.CampCD`). On Reminders only: Buffs no longer repeats it | the feature's icon · "Place" | `type1=item` |
| **Fire slot**: one icon, the first that applies of Light, Make, Wood, Cook | At Fire's moment: standing still 20 s (`PLAYER_STOPPED_MOVING` arms it, `PLAYER_STARTED_MOVING` disarms) outside a town (`IsResting` false) and an instance, no fire near, no Camp Benefits. Wood and Cook also in town within 2 minutes of where their click leads. **Light**: you carry a kit (279981, 279961, 279974; or Basic Campfire 818 and Simple Wood on Era). **Make**: wood and flint carried, the kit recipe known (1229737), no kit. **Wood**: a cook who has used a kit (learned per character), none left and no way to make one, a seller within 10 min (learned at `MERCHANT_SHOW`, `Camp.NoteMerchant`, else the Classic seed, its tooltip saying it may have moved). **Cook**: not a cook, level 5 or more; one showing (up to 10 minutes) per character; tooltip "Cooks make campfire kits: Basic Campfire Kit at Cooking 1." | Light: the kit, lit, count · "Light". Make: the kit, lit · "Make". Wood: Simple Wood, waiting · "4 min". Cook: the kit, waiting · "Cook" | Light: `type1=item` (or `spell` 818). Make: `type1=spell`, your Cooking spell, which opens the game's crafting window (section 11). Wood: the seller on the arrow as a detour (`Camp.GoTo`). Cook: the nearest known cooking trainer (learned at `TRAINER_SHOW` when `IsTradeskillTrainer()` and a service's `GetTrainerServiceSkillLine` is Cooking, into `disc.trainer`; `Glow.ReadTrainer` stops at profession trainers, `Glow.lua:791-794`); none known, no click |
| **Eat** | Outside towns and instances (Before the pull aside), not Well Fed: none of the 30 "Well Fed" auras of `SpellName.csv` nor 1243969 (seeded by `gen_data.py`) on you, by id or by the client's own name (`C_Spell.GetSpellName(1248422)`, so a localised client matches). Foods: `D.FOOD`, generated from ItemEffect → SpellEffect trigger chains that end in a Well Fed aura (so no water and no plain bread), plus learned: any meal, from the bags too (the Food aura of a carried item's spell, `C_Item.GetItemSpell`), followed by Well Fed keeps that food; a meal that ends without it drops the item (up to 200). While levelling the cheapest by sell price; Before the pull the best by item level | the food · "Eat", count on it | `type1=item`, `item:<id>` (the icon stays through the meal, `Camp.Used`) |
| **Sleep** | You hold the Cozy Sleeping Bag (211527), Well-Rested (429959) under 3 stacks, its cooldown up, outside a town and an instance, standing still 20 s | the bag · "Sleep", stacks on it | `type1=item` |
| **Repair** | Any slot at the game's alert: `GetInventoryAlertStatus(index)`, index 1-11 of `INVENTORY_ALERT_STATUS_SLOTS` (1 low, 2 broken, `DurabilityFrame.lua:1-12, 73, 87`), read on `UPDATE_INVENTORY_ALERTS`; never while `C_GameRules.IsGameRuleActive(Enum.GameRule.RepairArmorDisabled)` (`:52`). In town or within 2 minutes of a known repairer; elsewhere only when broken. Hidden while a merchant window is open (its Repair All is the game's) | anvil 136241, waiting · the minutes; with no repairer known "Low" in WARN; broken "Broken" in BAD | the nearest repairer learned at `MERCHANT_SHOW` (account-wide, up to 60) on the arrow |
| **Bags** | General slots free (`C_Container.GetContainerNumFreeSlots`, bagFamily 0, bags 0 to `NUM_BAG_SLOTS`; the reagent bag not counted) at 2 or fewer, or `BAG_OVERFLOW_WITH_FULL_INVENTORY` in the last 30 s. In town or within 2 minutes of a known merchant; elsewhere only when full. Hidden while a merchant window is open (its Sell All Junk asks first, `MerchantFrame.lua:1124-1131`; nothing here sells) | backpack 133633 · the minutes, else "2 free" in WARN; "Full" in BAD | near a merchant: it on the arrow; else opens your bags: `type1=click`, `clickbutton=MainMenuBarBackpackButton` (`Camelot/MainMenuBarBagButtons.xml:70`) |
| **Ammo** | You use ammo (`UnitUsesAmmo("player")`, `Camelot/PaperDollFrame.lua:1499`) and the ammo slot (`GetInventorySlotInfo("AmmoSlot")`, `GetInventoryItemCount`) holds under 200: in town or within 2 minutes of a known seller of it; elsewhere only when empty | the ammo's icon · the minutes, else "Low" in WARN; empty "None" in BAD | the nearest seller learned at `MERCHANT_SHOW` on the arrow |
| **Hearth** | Only beside "Broken" or "Full" away from town, outside an instance, and not while the route has a hearth step planned within the stone's cooldown; a hearthstone carried and ready by its item cooldown (`C_Container.GetItemCooldown`, read on `BAG_UPDATE_COOLDOWN`; never `C_Spell.GetSpellCooldown(8690)`, secret in a fight): items 6948, 243229 (Hearthstone of the Dawn), 284163 (Hearthstone), then the single-use 282006. `API.HearthLeft` and `API.HasHearth` (`Core.lua:491-510`, 6948 only today) read the one carried | hearth 134414 · "Hearth"; tooltip "To <GetBindLocation()>: repair and sell there." | `type1=item`, `item:<id>` |
| **Use** | In your bags, by `BAG_UPDATE_DELAYED`, per item id read once and cached: a quest starter (`ItemSparse.StartQuestID`, generated) whose quest is neither in your log nor done; something to open (an Open line in `C_TooltipInfo.GetBagItem` and no ErrorLine, so a locked box is left out; `ItemSparse.LockID` generated); a recipe or blueprint you can learn (a Learn line, `IsUsableItem`). One icon, the first in that order | the item, count = how many · "Use"; tooltip lists up to five | `type1=item`, `item:<id>`; Never applies to that item id |
| **Buy** | In town, a kind of consumable you used on this character (flask or elixir, healing potion, mana potion for a mana class) and carry none, with a seller of it learned at `MERCHANT_SHOW`; none known, nothing | the item, waiting · the minutes | the seller on the arrow |
| **Talents** | `C_ClassTalents.HasUnspentTalentPoints()`, outside an instance, only while `TalentMicroButton` is not visible (a UI addon replaced the bar; otherwise the game's own tip and pulse say it, `MainMenuBarMicroButtons.lua:799`) | your class icon, points on it · "Talents" | `type1=click`, `clickbutton=TalentMicroButton` (`Camelot/MicroMenuContainerOverrides.lua:7`). Not now: until the next level |

Dropped from today's bar: Well Fed and Camp Benefits with their minutes once they are on you (the game's buff bar
shows them), the grey "No campfire kit", and the bag's grey chain icon (moved to the step frame).

### 3.3 The step frame's line

Guidance that means going somewhere belongs where the route lives. After the step frame's next two steps and before
the quests you hold, **one line**, 14 px icon, 12 px INK text, minutes at 11 px INK on the right; the same line in
Cute's step band (one source, `G.Reminder()`, which today Cute's band does not carry). Click: its place on the arrow.
Right-click: the menu of section 6. When the route already holds the matching step ("Train at X" before a hand-in, a
flight from that master), the line is not drawn: one thing, one place. With the step frame off, the line's reminder
is the last icon on Reminders, waiting, its minutes as the word.

| Line (priority order) | Shows when | Text |
|---|---|---|
| **Train** (class icon, no bar; the Training row) | Spells that became trainable since your last trainer visit: a FutureSpell whose `GetSpellBookItemLevelLearned` is at or under your level (the client's own "trainable", `Blizzard_SpellBookItem.lua:234-247`) and that a class trainer sells (CMaNGOS `npc_trainer` through `cmangos.py`, corrected by the services trainers showed, `Glow.lua:796-803`; quest-taught spells such as Summon Voidwalker 697 or Bear Form 5487 never count, and `SkillLineAbility.AcquireMethod` cannot tell them). At `TRAINER_CLOSED` what stayed available is skipped: no longer counted, still named in the tooltip. Read again on `PLAYER_LEVEL_UP`, `SPELLS_CHANGED`, `LEARNED_SPELL_IN_SKILL_LINE`, `TRAINER_CLOSED`. Fallback if ranks are not FutureSpell (section 11): `SkillLineAbility.csv` plus `SpellLevels.csv` built by `gen_data.py`, `IsSpellKnown` per rank. Not now until the next level | "Train: 3 new spells · Wu Shen, 4 min" (no trainer known: "Train: 3 new spells at your class trainer", no click) |
| **Flight path** (`FlightPath` atlas, desaturated, no bar; the Training row) | A node of Travel's graph (`D.HUB`, world positions) within 300 yd (`UnitPosition`, same continent) that `TV.Usable` says you lack, on a continent whose map was read once (`TV.tells`), so an old character on a fresh install is never told to learn what it knows. Forever's map lists only the paths you found (`Travel.lua:492-496`), so `isUndiscovered` is never the source. Looked at on `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`, `PLAYER_STOPPED_MOVING`; gone on `TAXI_NODE_STATUS_CHANGED` or `UI_INFO_MESSAGE` `ERR_NEWTAXIPATH` (as `Travel.lua:1569-1575`) | "Learn the flight path: Lakeshire, 1 min" |
| **Sleeping bag** (QUEST bar, the bag's icon; the Camp row) | Level 14 or more (`Camp.BAG_LEVEL`), no bag in bags or bank, the chain's next step (`Camp.SleepNext`) placed within 10 min, outside an instance. One step at a time: the chain's length and later places are never shown, in the line or its tooltip. This is the written exception to the secrets research's "never shown until found" (`2026-10-21-forever-secrets-research.md:10-11`), because the owner asked for it | "Cozy Sleeping Bag: <step>, 6 min"; the last step without coordinates reads "Cozy Sleeping Bag: Rix Xizzix, Booty Bay" with no click |

Also in the step frame, from other rounds and named here so nothing is duplicated: the quest items (the windows
design's item buttons on the quests under the step), and a 20 px secure Hearthstone button on the route's hearth
step ("Use your Hearthstone", which has no button today). Secure buttons there are parented to UIParent and placed
out of a fight; while one is anchored to the step frame, the frame's size and rows hold still in a fight and are laid
out at `PLAYER_REGEN_ENABLED` (a frame a protected one depends on is anchoring-restricted). Today's
`QuestBankStepItem` is anchored to the frame (`StepFrame.lua:176-178`) while `f:SetHeight` runs in a fight (`:291`),
so it follows the same rule.

**Train fixes this carries.** Trained means "nothing newly trainable", not "0 at the last `TRAINER_SHOW`"
(`Guide.lua:476`); a level-10 spell never seen at a trainer still shows at 11 (`NeedsTraining` matched one level);
and Glow reads the same function, so the light on the trainer and the line agree (today `chars[].trainer` is a second
record, `Glow.lua:789-809`). The 180 s, once-a-level line goes.

### 3.4 Left out at launch

Pets (Call Pet and Revive Pet need the pet's state; next round), raid members' buffs (needs raidN reads between pulls
or addon messages, which can fail with `AddOnMessageLockdown`, `ChatConstantsDocumentation.lua:147-166`), drink and
mana, equipping upgrades (the Gear tab), Greater Blessings. Each would be one provider later (section 7).

## 4. Party members' buffs

- **When:** `IsInGroup()` and not `IsInRaid()`; the party row on. In a raid the row is gone (the owner's "if I'm not
  in a raid"); Before the pull covers you there.
- **Who:** each `partyN` that is connected, not dead, and **visible** (`UnitIsVisible`, no secret returns,
  `UnitDocumentation.lua:2428`); a member out of sight gets no icon at all. Auras read only while
  `C_Secrets.ShouldAurasBeSecret()` is false, so inside a dungeon between pulls it works.
- **What:** the first `other = true` buff of yours the member lacks, any rank or group version counting (Gift of the
  Wild from another druid counts as Mark). **Thorns** only on the member the game marks as tank
  (`UnitGroupRolesAssigned`, plain for party members) and on yourself; with no tank marked, on nobody else.
- **Range:** `C_Spell.IsSpellInRange` false dims the icon to 0.4 and adds "Out of range."; nil, with the member
  visible, is an ordinary icon (the game answers at the cast). Sight and range have no event of their own:
  `UNIT_IN_RANGE_UPDATE` (payload secret, `UnitDocumentation.lua:4330`, never read) marks the party dirty, and a 1 s
  clock runs while the row can show (in a party, out of a fight, the row on).
- **Events:** two frames, `RegisterUnitEvent("UNIT_AURA", "player")` and `RegisterUnitEvent("UNIT_AURA", "party1",
  "party2", "party3", "party4")`, each setting its own dirty bit without reading the payload (secret while auras are
  restricted, `UnitAuraDocumentation.lua:643-645`); `GROUP_ROSTER_UPDATE`, `UNIT_CONNECTION`, `PLAYER_REGEN_ENABLED`.
  Today party auras are seen only on the 2 s tick, because `UNIT_AURA` is registered for the player alone
  (`Camp.lua:1387`).
- **Right-click:** as on any icon (section 6); "Never: party buffs" on a member's icon turns the party row off.

## 5. Before the pull

- **Cues:** `READY_CHECK` (the initiator's name is secret on dungeon and raid maps, `PartyInfoDocumentation.lua:841`;
  the event is all this needs), and entering a raid instance (`PLAYER_ENTERING_WORLD`, `IsInInstance` → "raid"),
  5 s after, out of a fight. Ends at `READY_CHECK_FINISHED` + 10 s, 60 s after the entry, when nothing is left, or
  at the first fight. Shown while the instance choice is "Buffs and consumables" or "Everything".
- **Shows** under the title "Before the pull" (GROUP bar), only what one click fixes: your missing buffs (3.1), food
  if not Well Fed (the best you carry), every flask or elixir you carry (consumable subclass 3 and 2) whose aura
  (`C_Item.GetItemSpell`) is not on you, and a stone, oil or poison for a bare weapon (3.1's set, `target-slot`). In
  Classic flasks and elixirs stack, so nothing hides another but a learned pair.
- **Stacking is learned, not listed:** the tables have no battle and guardian groups. When using elixir B takes elixir
  A's aura away within the same second, A and B are kept as one group (up to 64 pairs, account-wide) and offered as
  one from then on.
- **Carried none:** nothing here, where buying is no longer possible; it becomes Buy on Reminders the next time you
  are in town (3.2).
- **Not read:** other members. Cute's dashboard keeps its Ready column for the officers (Stats.lua:899-945), which can
  read the same `Remind.Pull()` result for the player's own row so the two agree.

## 6. Switching off

**Settings > Reminders**, one section of 8 rows, one per category (rows 1-6 drawn from one engine table
`Remind.ROWS`, so QuestBank's page and Cute's section cannot drift; QuestBank's 10-row Camp bar section and the
windows design's Camp section both become this):

| Row | Key (default) | Note |
|---|---|---|
| Your buffs and weapon | `remind.buffs` (on) | |
| Party members' buffs | `remind.party` (on) | "In a party, not a raid. Thorns only on the tank." |
| Camp, food and sleeping bag | `remind.camp` (on) | "Each adds XP on Forever. The sleeping bag's quest line too." |
| Repair, bags and items to use | `remind.upkeep` (on) | "Ammo and the hearthstone with them." |
| Training, talents and flight paths | `remind.class` (on) | |
| In dungeons and raids: Buffs and consumables / Everything / Nothing | `remind.instance` ("buffs"; was `quietInstance`) | "Buffs and consumables: between pulls and on a ready check." |
| Interact light | `glow.on` | |
| Light style: Sparkle / Light / Game's | `glow.style` | |

In Cute the Reminders module is the only master switch and applies at once. QuestBank alone puts "Reminders on
screen" (`remind.on`, was `campBar`; note "Reminders and Buffs. Hidden in a fight.") above rows 1-6 and keeps the
light's two rows in its own Interact light section. Cute keeps 13 Settings sections and its Quests section at 8 rows.
Under a row, only while one of its reminders is hidden for good, one DIM line: "Hidden: Eat [Show]".

**Right-click anywhere on a piece or the line** opens the game's menu (`MenuUtil.CreateContextMenu`, out of a fight):
"Not now" hides the whole piece (Reminders, Buffs or the line) for 10 minutes; "Never: <the reminder under the
cursor>" ("Never: Frost Armor"; "Never: party buffs" on a member); "Settings...". Never writes `remind.never[key]` in
the account-wide settings, like every row (keys: `buff:<first rank id>`, `weapon`, `party`, `sit`, `place`, `fire`,
`wood`, `cook`, `eat`, `sleep`, `repair`, `bags`, `ammo`, `hearth`, `buy`, `talents`, `use:<itemID>`, `train`,
`flight`, `bagchain`; up to 32).

**From 6.1.1:** `campBar = false` becomes `remind.on = false`; each per-icon switch left false (`food`, `fire`, `camp`,
`bag`, `sit`, `wood`, `bagChain`) becomes its Never (`eat`, `fire`, `place`, `sleep`, `sit`, `wood`, `bagchain`);
`quietInstance = false` becomes "Everything". Never is account-wide like the switches it replaces, so every character
keeps the choice. In Cute the same step rewrites a kept `cuteOff.camp`: `campBar` becomes `remind.on`, and
`remind.buffs`, `remind.party` and `glow.on` go back to their rows as kept.

## 7. One engine: QuestBank alone and in Cute

- **Providers.** A new engine file `Remind.lua` owns the two frames, layout, the icon pool, menus, Not now and Never,
  the combat and secrecy rules and the dirty bits. Each reminder is a provider: `{ key, cat, place = "buffs" |
  "reminders" | "step", row, events, read = function(out) }`, where `read` fills a reused record and returns whether
  it shows. `Camp.lua` keeps the camp and buff knowledge and registers its providers; `Guide.lua` registers Train,
  `Travel.lua` Flight path; upkeep (repair, bags, ammo, hearth, buy), talents, use and Before the pull are new
  providers in `Remind.lua`. Adding or dropping a reminder is one provider and one line in `Remind.ROWS`.
- **QuestBank alone:** on for a new install and for 6.x saved files (migration above). Its Settings page shows the
  Reminders section where the Camp bar section was.
- **Cute:** `build.py` copies `Remind.lua` with the rest (byte-identical, checked). The Camp module keeps its id
  `camp` (saved state) and is titled "Reminders"; `Cp.Toggle` follows `remind.on` alone through `QB.Follow`, so the
  rows keep their own state, and `glow.on` leaves the module (today it is in the list, `PageCamp.lua:32`). Cute's
  section is drawn from `Remind.ROWS` plus the light's two rows. The first-run card's row "Camp bar and missing buffs"
  becomes "[x] Reminders" (row id `camp`, ticked by default); the interact light keeps its own row. Until the card
  ships, the camp module's `default = true` is honoured for a character with nothing saved (one exception in
  `Cute/Modules.lua:92-95`), for `remind.*` only: `glow.on` stays off until the card's Interact light row is answered,
  because the engine's default is on (`Core.lua:1305`) and the light changes the game's soft-target settings
  (`Glow.lua:39-53`).
- **With QuestBank loaded** Cute_Quest sleeps (the dormant rule): QuestBank's reminders run, Cute's Reminders section
  is greyed with "QuestBank is loaded: its reminders are its own." and Cute writes none of its settings.
- **Shared reads, one answer:** `QB.API.UnspentTalents()` (HasUnspentTalentPoints) replaces Cute's
  `GetNumUnspentTalents` read (`Stats.lua:876`, the old talent frame's call, which may read 0 on camelot);
  `QB.API.Durability()` and `QB.API.FreeSlots()` back both Reminders and Cute's `durability` and `bags_free` stats.

## 8. Layout mode

- Two movers, "Reminders" (`QuestBankCampBar`, `remind.pos`) and "Buffs" (`QuestBankBuffBanner`, `remind.bannerPos`).
  Both show in layout mode even when empty, sized at their maximum (six icons with their words; six icons and four
  members), so a piece placed against the step frame never overlaps it later.
- Reminders is anchored by its centre and grows both ways; Buffs by its bottom and grows upward, so the two never
  overlap while `remind.bannerPos` is nil. A moved Buffs keeps its own point.
- Scale 50 to 200 % by the wheel, as every piece. Moving and laying out happen out of a fight only (secure buttons).
- QuestBank alone keeps Alt-drag on Reminders (and gains it on Buffs), refused while `QB.Locked("camp")` or
  `QB.Locked("buffs")` says locked (`QB.Locked` comes with the windows design's part E; until then QuestBank's own
  lock).

## 9. Budgets

- **No OnUpdate by default.** Today the camp bar runs `Camp.Refresh` every 2 s whatever happened (`Camp.lua:1376`).
  Now events set dirty bits per provider group and one refresh runs on the next frame for the dirty groups only. A
  1 s clock runs only while a countdown shows (Welcoming Campfire, a cooldown word), a minutes word shows (it changes
  as you walk), the party row can show (section 4), or a Not now is about to end. Stillness (the fire slot, Sleep)
  and the 2 s after a fight are one-shot `C_Timer.After` timers.
- **Events per group** (a payload that can be secret is never read):

| Group | Events |
|---|---|
| buffs | `UNIT_AURA` (player frame), `SPELLS_CHANGED`, `WEAPON_ENCHANT_CHANGED`, `UNIT_INVENTORY_CHANGED` (player) |
| party | `UNIT_AURA` (party frame), `GROUP_ROSTER_UPDATE`, `UNIT_CONNECTION`, `UNIT_IN_RANGE_UPDATE` |
| camp | `UNIT_AURA` (player), `UNIT_SPELLCAST_SUCCEEDED` by `RegisterUnitEvent` for the player (today every unit's casts, `Camp.lua:1382`), `PLAYER_STARTED_MOVING`, `PLAYER_STOPPED_MOVING`, `PLAYER_UPDATE_RESTING`, `PLAYER_MOUNT_DISPLAY_CHANGED`, `PLAYER_SOFT_INTERACT_CHANGED`, `BAG_UPDATE_DELAYED` |
| upkeep | `UPDATE_INVENTORY_ALERTS`, `BAG_UPDATE_DELAYED`, `BAG_UPDATE_COOLDOWN`, `MERCHANT_SHOW`, `MERCHANT_CLOSED`, `PLAYER_UPDATE_RESTING`, `UNIT_INVENTORY_CHANGED` (ammo) |
| class and step | `PLAYER_TALENT_UPDATE`, `TRAIT_CONFIG_UPDATED`, `PLAYER_LEVEL_UP`, `PLAYER_LEVEL_CHANGED`, `SPELLS_CHANGED`, `LEARNED_SPELL_IN_SKILL_LINE`, `TRAINER_SHOW`, `TRAINER_CLOSED`, `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`, `TAXI_NODE_STATUS_CHANGED`, `UI_INFO_MESSAGE` |
| away | `PLAYER_DEAD`, `PLAYER_ALIVE`, `PLAYER_UNGHOST`, `PLAYER_CONTROL_LOST`, `PLAYER_CONTROL_GAINED`, `UNIT_ENTERED_VEHICLE`, `UNIT_EXITED_VEHICLE`, `CINEMATIC_START`, `CINEMATIC_STOP` |
| all | `PLAYER_ENTERING_WORLD`, `PLAYER_REGEN_ENABLED`, `ADDON_RESTRICTION_STATE_CHANGED` |

- **No allocation per refresh** that did not change: provider records and icon state are reused and wiped in place;
  a word is formatted only when its number changed (the step frame's `lastVer` pattern, `StepFrame.lua:258-262`);
  secure attributes are written only when their value differs.
- **Bags** are scanned on `BAG_UPDATE_DELAYED` only, coalesced to one scan in 0.5 s, by `C_Container.GetContainerItemID`
  (no table per slot); tooltip reads (`C_TooltipInfo.GetBagItem`) only for an item id not seen before, cached (200
  ids, cleared when a spell is learned or a box is unlocked).
- **Bounded saved data:** sellers and repairers 60 each (account), learned buffs 8, foods 200, elixir pairs 64,
  Never keys 32, "gives nothing" fire objects for the session only.
- **Gates** (the 5.4.2 ones): zero bytes and zero refreshes over a simulated idle minute out of a party with nothing
  timed; one refresh for a burst of 50 `UNIT_AURA` events; under 2 KB per full refresh; memory after load unchanged
  within 20 KB of 6.1.1.

## 10. Harness scenarios

In `tools/questbank/harness.lua` (each through `checkLayout`, no Unicode in game text, print count 0 unless named),
one luajit at a time:

1. A level-1 mage outside a town: Arcane Intellect and Frost Armor on Buffs, `type1=spell`, `unit=player`. Water
   Breathing cast once never joins; recast twice within 2 minutes of running out, it joins; two lapses, gone.
   Righteous Fury never.
2. A fight: the holder hidden by the state driver, no `SetAttribute` during lockdown, secret auras leave the layout
   as it was; after the fight the pieces back 2 s later (a new pull in between: still hidden), one refresh.
3. A party of three with a druid: Mark on all, Thorns only on the member marked TANK and none with no tank; a member
   `UnitIsVisible` false gets nothing; range nil bright, false dimmed; in a raid no party row.
4. A ready check in a dungeon with the initiator secret: "Before the pull" with a flask and two elixirs (all three),
   food and a stone (`item:<id>`, `target-slot` 16); finished, gone 10 s later; elixir B removing A, then one icon for
   the pair; a kind carried none: nothing there, Buy in town.
5. Raid entry: the row once after 5 s; dungeon entry: buffs and consumables only; "Nothing" hides Buffs too.
6. Campfire: Campfire Nearby on, "Sit" with `/sit`; Welcoming on, the countdown; Camp Benefits, the icon gone. A
   Cooking Fire object without the aura: "Sit" for 15 s, then that entry kept as giving nothing; identity secret: no
   fallback. Place lit at your own kit's fire only.
7. Redridge, the owner's case: a cook's last kit used, standing still 20 s out of town: "Wood" with the seller's
   minutes; walking on, snoozed; a non-cook at the same moment: "Cook" with the trainer, once; seller over 10 min
   away: nothing; a kit carried: "Light"; wood and flint: "Make".
8. Food: Refreshing Spring Water 159 and Tough Hunk of Bread 4540 carried: no Eat; Spiced Wolf Meat 2680: Eat; eaten
   from the bags, Well Fed 1248420 on: gone; a localised Well Fed name: gone; in a capital: nothing.
9. Sleeping bag: held, standing still 20 s out of town: "Sleep" lit; walking away: snoozed; in an inn: nothing. Not
   held at level 14: the step frame's line, one step only; step frame off: the last icon on Reminders.
10. Repair: alert 1 away from town: nothing; in town 1 min from a known repairer: waiting "1 min"; alert 2 away:
    "Broken" in BAD with Hearth beside it, and no Hearth with a hearth step planned; a merchant open: hidden.
11. Bags and ammo: 2 free in town; full away "Full" in BAD, `clickbutton=MainMenuBarBackpackButton`; the reagent bag
    ignored; a merchant open: hidden. A hunter with 150 arrows in town near a known seller, then none away.
12. Talents: a point at level 10 with `TalentMicroButton` shown: nothing; hidden by another addon: the class icon,
    `type1=click`; spent, gone; Cute's `talents_free` agrees.
13. Train: a level-10 warrior with FutureSpells, the line; spells learned (`SPELLS_CHANGED`), the line gone with no
    new `TRAINER_SHOW`; level 11 with a level-10 spell never seen at a trainer, still shown; one skipped at a trainer,
    not counted after `TRAINER_CLOSED`; Summon Voidwalker never counted; Glow lights the trainer from the same answer;
    a trainer near a hand-in, the route's step and no line.
14. Flight path: in Lakeshire and at Sentinel Hill (no rest area) beside a `D.HUB` node you lack, the line;
    `ERR_NEWTAXIPATH`, gone; a known node, nothing; a continent never read, nothing.
15. Use: a quest starter not taken, then a clam, then a blueprint; a locked box (ErrorLine) left out; Never on one
    id; a bag sort inside the 0.5 s window never equips anything.
16. Not now and Never: right-click on any icon of Buffs, Reminders and the line; Not now hides the piece, Never names
    the one; Never kept across a reload and on another character; "Hidden: Eat [Show]" under its row restores;
    6.1.1's false per-icon switches arrive as Nevers.
17. Cute (`tools/cute/harness.lua`): the card's Reminders row ticked on a fresh character, the module on with nothing
    saved and `glow.on` still off, `QB.Follow` keeps `remind.on`, an old `cuteOff.camp` restored with renamed keys,
    QuestBank loaded greys the section, engine files byte-identical; Reminders 8 rows, Quests 8, the section list
    unscrolled at 760 x 420.
18. Layout: Reminders with six icons and Buffs with six and four members at 80, 100 and 150 %, no overlap, movers at
    their maximum when empty, `remind.bannerPos` kept; a step frame holding a secure button resized in a fight never
    hits `IsAnchoringRestricted()`.
19. Budget: the gates of section 9.

## 11. What needs the live client

One look each, by the owner or a guild mate, before or in the first days of 4 November; a one-off diagnostic where a
look is not enough (never shipped as a feature):

- **Static world campfires** (Redridge): do they put Campfire Nearby (1283391) on you, and does sitting by one give
  Welcoming Campfire? Is the soft-interact GUID of a fire secret out of a fight? `/qb campdiag` (one-off) logs your
  aura ids while the soft-interact target is a fire.
- **Camp features at other fires:** does a feature hold at a static or another player's fire, or only at your own
  kit's? Until then Place lights at your own only.
- **Train:** are higher ranks of known spells FutureSpell in camelot's spellbook, and quest-taught ones too? If ranks
  are not, the generated rank table.
- **Clicks from addon code:** the Cooking spell opening the crafting window: no blocked-action message, nothing in
  the taint log.
- **Secure clicks:** `type1=click` on `TalentMicroButton` while another addon hides it, and on
  `MainMenuBarBackpackButton`; a hearthstone by `item:6948` and `item:243229`; a poison and an oil by `target-slot`
  (does a poison, SpellEffect 360, ask for a weapon at all, and does 17 reach the off-hand?).
- **Weapon enchants:** what `C_Item.GetWeaponEnchantInfo` returns for a poison and a shaman imbue on 1.60.1, and how
  long an imbue lasts.
- **Game answers:** `C_ClassTalents.HasUnspentTalentPoints` on camelot (beside Cute's `GetNumUnspentTalents`); a
  lockbox's tooltip carrying an ErrorLine; which meals give Well Fed XP Boost (1243969, applied by the server).
- **Roles:** whether a party formed by hand has a tank role at all (if never, Thorns stays on you alone).
- **Both pieces after a dungeon:** party clicks between pulls, the taint log clean, nothing shown in a boss fight.

## 12. Build order

| Part | What | Needs |
|---|---|---|
| R1 fixes (QuestBank 6.1.2, Cute 0.7.2) | Train counts trainer-sold spells from the spellbook and keeps earlier levels, Glow on the same answer; party `UnitIsVisible`, Thorns on the tank, party `UNIT_AURA`; flight path from Travel's graph; Cute's camp module on by default with `glow.on` left off | none |
| R2 one system | `Remind.lua` and providers; both pieces in pattern D with words and category bars; no duplicates; right-click Not now and Never; the 8-row section in both addons; migration; event-driven refresh | R1; the movers and `QB.Locked` with the windows design's part E |
| R3 new reminders | Repair, Bags, Ammo, Hearth, Use, Buy, Talents, the fire slot, Eat's food list, learned buffs by habit, the step frame's line (Train, Flight path, Sleeping bag), the hearth step's button | R2 |
| R4 before the pull | ready check and raid entry, elixir pairs learned, weapon enchants | R2 |

Release notes, one line each, no catalogue: "Reminders: one quiet place, click to fix, right-click to hide."
