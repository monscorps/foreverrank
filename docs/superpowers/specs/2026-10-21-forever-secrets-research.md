# Books, secret chains and keys in WoW Forever (research, 2026-10-21)

Input for the Secrets & collections part of the Cute/QuestBank design. Owner: "let's not forget the books, parts from
the secret quest chain etc". Read-only research over the client tables (research/wago/1.60.1.70338: ItemSparse, Item,
ItemEffect, ItemXItemEffect, Lock, QuestV2, SpellName, Spell, SpellEffect, Vignette, CurrencyTypes, Achievement,
Criteria), the API docs (research/wow-ui-source, forever branch), QuestBank's data and the web. Icy Veins, metaforge,
mobalytics and massivelyop answered 403 and were not worked around: their facts below come from search snippets.

Decision (owner delegated, 2026-10-21): Known.lua may carry bare ids (the 40 books and their quests, the secret items,
the locks) so finds are recognised and counted; a name or a spot is never shown until the player or a guildmate has
found it (spoiler-free by default, one-click reveal levels). One exception, because the owner asked for it: the
Cozy Sleeping Bag chain is shown one step at a time from level 14 (never its length or later places), as the
reminders design says (2026-10-21-reminders-design.md, Sleeping bag).

## Headlines
- 40 library books in the client: class 5 (Reagent), bind on pickup, unique, no vendor price; description ends
  "...addition to any library's collection". Each is handed in through its own quest; rewards at 10, 20 and 25
  books. No currency, statistic, achievement or Legacy criterion: progress = each book's quest flag + copies in bags
  and bank.
- The Keystone chain is objects only, no quests. Items: Torn Page 281347, Burnt Page 281356, Stone Key 281358,
  Keystone Fragment 281350 (green); two unfound Fragments 284092 (blue, unique 2) and 284093 (purple, unique 3); and
  unreported Parchment of Chaos 281348, Parchment of Darkness 281349, Ancient Runestone 281352, Dormant Runestone
  281359. Lock.csv: 4572 (Fragment 281350), 4580 (Stone Key), 4581 (blue Fragment 284092), 4579 (Dormant Runestone);
  the objects with those locks are server-spawned.
- The hidden legendary is encrypted; readable clue spells: 1299303 Stormcharged ("Charges the branch of Nordrassil
  with the power of Stormwraith"), 1231588 / 1234253 Heating the Blade, 1299243 "(DNT) Legendary Ritual Success".
- Data-only collectibles: Putress' Diary (hidden off-hand growing with pages: "Add page" spells 1232345-1232356,
  hidden items 242427-242436, finished 241020); Evenshade's journal ("Barely Legible Journal Entry, Page I".."X",
  items 260348-260358, spell 1266339); Library Shelf camp spell 1302502 (no item uses it).
- An addon sees all of it live without a list: looting an object (GetLootSourceInfo worked in 480 of 765 loot
  windows in upload 00191, none hidden), reading a page (ITEM_TEXT_*), using a key (UNIT_SPELLCAST_SUCCEEDED,
  spell 3366 "Opening", for "player"), new quest flags (GetAllCompletedQuestIDs), the items. No secrecy marker for
  the player's own actions; NPC/object GUIDs ("softinteract", "npc") can be secret.

## 1. Library books
Hand-in: Garion Wendell (Alliance, NPC 211033) Stormwind 48.8, 87.0 on Forever's map (Warcraft Tavern's 38, 81 is
the old Classic map); Owen Thadd (Horde, NPC 211022) Undercity 73.4, 33.0. The eight level-60 books (quests
84395-84402) are routed in QuestBank's data (Wowhead/SoD) to Jennea Cannon (Stormwind 49.6, 85.8) and Oran
Snakewrithe (Undercity 73.1, 32.8); Warcraft Tavern names only Garion and Owen: check in game.

| Tier | Quest | Books | Reward choice |
|---|---|---|---|
| 1 | Friend of the Library 78150 | 10 | Scholarly Pendant 277203 / Erudite's Amulet 277204 |
| 2 | Greater Friend of the Library 79536 (level 20) | 20 | Field Researcher's Loop 281634 / Philanthropist's Ring 281635 |
| 3 | same name, level 30, quest id unknown | 25 | Truthseeker's Bow 277254 / Crest of Elucidation 277258 / Researcher's Night Light 277260 |

Hand-ins add up across tiers, one book at a time. Unnamed quest ids that probably hold tier 3 and the missing book
quests: 78144, 79090, 79096, 79098, 79099, 79945, 79946, 79953, 81951, 81960, 84394, 84405 (learn in play).

| Item | Book | Spot (Warcraft Tavern, SoD-based) | Quest | iLvl |
|---|---|---|---|---|
| 203755 | Archmage Theocritus' Research Journal | Elwynn, Tower of Azora 65.4, 70.1 | 79092 | 10 |
| 203754 | Archmage Antonidas: The Unabridged Autobiography | Ironforge 76.1, 10.2 | 79091 | 10 |
| 207972 | The Lessons of Ta'zo | Orgrimmar 38.5, 78.2 | 79094 | 10 |
| 208185 | The Apothecary's Metaphysical Primer | Brill 59.5, 52.3 | 79095 | 10 |
| 210177 | Ataeric: On Arcane Curiosities | Silverpine, Sepulcher 43.4, 41.2 | ~79096 | 10 |
| 208800 | Baxtan: On Destructive Magics | Ratchet 62.7, 36.3 | 79097 | 10 |
| 208860 | Rumi of Gnomeregan: The Collected Works | Loch Modan 35.6, 48.9 or Westfall 52.7, 53.7 | 79093 | 10 |
| 209844 | The Dalaran Digest, Vol. 23 | Ambermill 63.5, 63.1 | ? | 25 |
| 209843 | Nar'thalas Almanac, Vol. 74 | Darkshore 59.6, 22.2 | ?(78144) | 25 |
| 209850 | Runes of the Sorcerer-Kings | Loch Modan, Mo'grosh 74.5, 19.6 | 78148 | 25 |
| 209845 | Bewitchments and Glamours | Westfall, Moonbrook 45.4, 70.4 | 78142 | 25 |
| 209847 | Arcanic Systems Manual | Barrens, Sludge Fen 56.3, 8.8 | 78145 | 25 |
| 209846 | Secrets of the Dreamers | Barrens, Cavern of Mists 52.8, 54.7 | 78143 | 25 |
| 209851 | Fury of the Land | Stonetalon 74.4, 85.7 | 78149 | 25 |
| 209849 | Crimes Against Anatomy | Duskwood catacombs 6.7, 28.5 | 78147 | 25 |
| 209848 | Goaz Scrolls | Wetlands 33.6, 47.9 | 78146 | 25 |
| 215683 | Geomancy: The Stone-Cold Truth | Thousand Needles 34, 40 | 79947 | 25 |
| 215815 | Defensive Magics 101 | Alterac Mountains 48.5, 57.6 | 79948 | 25 |
| 215816 | A Web of Lies: Debunking Myths and Legends | Arathi, Witherbark 73, 65 | 79949 | 25 |
| 215817 | Demons and You | Desolace 55, 28 | 79950 | 25 |
| 213165 | Basilisks: Should Petrification be Feared? | Stranglethorn cave 41.5, 50.8 | 79535 | 25 |
| 215820 | Mummies: A Guide to the Unsavory Undead | Badlands 57, 39 | 79951 | 25 |
| 215822 | RwlRwlRwlRwl! | Dustwallow 57, 21 | 79952 | 25 |
| 215824 | A Luddite's Guide to Caring for Your Demonic Pet | Swamp of Sorrows cage 61, 22 (Rusted Cage Key 216523) | ~79953 | 25 |
| 220345 | Sanguine Sorcery | Sunken Temple 70, 51 | 81947 | 50 |
| 220347 | The Liminal and the Arcane | Feralas 50.6, 15.7 (SoD spot) | ~81951 | 50 |
| 220346 | Legends of the Tidesages | Tanaris 72.7, 47.8 | 81949 | 50 |
| 220350 | Venomous Journeys | Hinterlands 36.0, 72.7 | 81954 | 50 |
| 220352 | A Mind of Metal | Searing Gorge 37, 49 | 81955 | 50 |
| 220353 | Conjurer's Codex | Blasted Lands 55.3, 32.2 | 81956 | 50 |
| 220348 | Everyday Etiquette | Azshara 20, 61 | 81952 | 50 |
| 220349 | Stonewrought Design | Blackrock Depths, Franclorn's altar | 81953 | 50 |
| 228134 | Northern Kalimdor - A Comprehensive Guide | Felwood, Timbermaw 65.2, 3.2 | 84397 | 60 |
| 228133 | Magma or Lava? | Blackrock Mountain near the BRD door | 84396 | 60 |
| 228141 | Necromancy 101 | Caer Darrow 52.7, 26.3 | 84402 | 60 |
| 228132 | Undead Potatoes | Felstone Field 38, 54 | 84395 | 60 |
| 228135 | A Study of the Light | Light's Hope 73, 65 | 84398 | 60 |
| 228140 | Scourge: Undead Menace or Misunderstood? | Stratholme bridge 31.3, 21.0 | 84401 | 60 |
| 228138 | The Knight and the Lady | Eastern Plaguelands lake 55, 51 | 84400 | 60 |
| 228136 | Ka-Boom! | Everlook 61, 38 | 84399 | 60 |

Forever redrew Stormwind and Eastern Plaguelands: guide coordinates there can be off. Signals: held =
C_Item.GetItemCount(id, true) + BAG_UPDATE_DELAYED; handed in = IsQuestFlaggedCompleted / GetAllCompletedQuestIDs /
QUEST_TURNED_IN (per character or account unknown; IsQuestFlaggedCompletedOnAccount exists); tiers = 78150, 79536 and
the tier-3 id once learned. "Is this a book?" without a list: each hand-in quest's title equals the book's name (35 of
35 named): works in every language.

## 2. Secret chains
**Cozy Sleeping Bag (real quests):** 1. "...and that note you found" 79008 Alliance / 79007 Horde (level 22, needs 14):
Alliance starts at the Nailed Plank, Westfall 37.4, 50.9, hands in at the Burned-Out Remains, Barrens 46.4, 73.8
(Horde reversed); rewards Swiftness Potion 2459, Lesser Troll's Blood Potion 3388. 2. Stepping Stones 79192 at Pocket
Litter, Stonetalon 40.7, 52.4 (Old Toolbox 221498 A / Sturdy Lunchbox 1652 H). 3. Scramble 79980, Mound of Dirt 39.6,
49.9. 4. Wet Job 79974, Carved Figurine on the Stonewrought Dam ledge 49.4, 12.9. 5. Eagle's Fist 79975, Messenger Bag
on Thoradin's Wall (Arathi 22.4, 24.2). 6. This Must Be The Place 79976, Hastily Rolled-Up Satchel below: Cozy Sleeping
Bag 211527 (spell 429961, Well-Rested 429959, +1% XP per stack, up to 3).

**Keystone chain (objects, partly solved):** 0. Burnt Page 281356 (page 10948) in a metal bucket above a burnt tapestry
at the sleeping-bag spot: hints "under the undead", the sewers. 1. Undercity sewers back entrance: a barrel with a Torn
Page 281347 (page 9258) and a Knife (added 24 Sep); the knife gives Keystone Fragment 281350 (green, BoP, unique;
"Opening" on lock 4572). 2. The Torn Page: an orc warrior's gaze on a map reveals the key, "page 155" (debated).
3. The satchel guarded by a passive Scarshield Grunt off the Upper Blackrock Spire ramp; the Fragment opens it: Stone
Key 281358 (lock 4580). Inven (16 Oct) says the bag moved to the Riverglades behind a sleeping Twilight's Hammer
worker (same object id). 4. (Inven only) a Blasted Lands fortress burnt page needing the Stone Key: three riddles, the
key in three parts (ogre-guarded place, central tomb, careful crossing): fits the three Fragments. 5. Un'Goro, Ringo's
cave: a Hidden Stash visible only with the Night Watchman's Torch lit (item 280612, spell 1309410). Possibly linked
(Inven, speculation): a Stonetalon cache with a "Fragile Key" 40.71, 52.75; Stranglethorn traveller's supplies with a
torn page 14.43, 27.15; a Stormwind note 67.20, 82.53; Uldaman.

**Nibbled-On Book (Northshire, Alliance):** 91741 from item 247834 (rare drop from Kobold Vermin/Workers/Laborers),
hand-in Brother Paxton 49.4, 40.4; 91743 Rascally Rodents (Mining for Dummies 247840 / Wild Harvest 247841 / Pelt
Collecting for Beginners 247846; eight Stolen Books 247839); 91745 Mining Consultant; 91752 The Big Picture (McBride);
91758 Follow That Kobold!; 91772 Shhh! We're Hunting Kobolds (Dughan); 91775 Book Return (Book Bag 279936, group);
91777 Rare Books (Paxton; weapons 248005-248008 or 276685). Book Inventory 92124: role unknown.

**Hidden legendary:** confirmed plan (codex.json): a legendary questline in Spring 2027 and a legendary off the launch
raids. Data only: the clue spells above, Elune's Grace on Stormwraith and Sylvestris (1272804 / 1272794), statistic 336
"Legendary items acquired", Ashbringer 13262, PLACEHOLDER_ASHBRINGER_QUESTITEM_01 226421.

**Others:** Night Watchman's Torch: quest 98372 "An Unfortunate End" from a dead Night Watch Guard, Raven Hill,
Duskwood 18.1, 55.2, at night; lasts 5 min, out in combat, water and cities. Tome of Dalaran: Black Tome 276561 from
Shadowfang Keep behind Arugal, used at the Ambermill Leyline Focus 63.4, 64.3 for Tome of Dalaran 275989, used at the
City of Dalaran's summoning circle. Ruins of Lordaeron hidden bosses (Viktor the Vile; a glowing-eyed statue). Mage
Comprehension scrolls 281015-281018. Scroll of the Saber 277490.

## 3. Keys
Secret-chain keys: the three Fragments, the Stone Key, the Dormant Runestone, the "Fragile Key". Forever access keys:
Dalaran Sewer Key 277507, Brooch of the Wardens 277136 (Vord'anaar Prison, Barrow Deeps), Krol'dok Ogre Key 271721,
Krol'dok Compound Key 267089, Overseer's Keyring 263992, Fenris Isle Key 267412, Old Key 287992, Clearcutter Key
281048/282285, hidden 282406 and 282635. 147 key-class items, 34 hidden, include the Classic dungeon keys: never list
them; show only what members hold.

## 4. What an addon can observe
| Signal | API / event | Secrecy |
|---|---|---|
| Looting an object, its id | LOOT_OPENED, GetLootSourceInfo (old global), GetLootSlotLink | none seen (765 windows, 0 hidden) |
| Getting an item | CHAT_MSG_LOOT, ITEM_PUSH, BAG_UPDATE_DELAYED, C_Item.GetItemCount | no lockdown marker on CHAT_MSG_LOOT |
| Hidden item names | C_Item.RequestLoadItemDataByID -> ITEM_DATA_LOAD_RESULT | 12,599 items have no name row; the server sends them |
| Reading a page | ITEM_TEXT_BEGIN/READY/CLOSED, ItemTextGetItem, ItemTextGetText | none |
| Using a key | UNIT_SPELLCAST_SUCCEEDED("player", 3366); UNIT_SPELLCAST_SENT target name | target name can be secret |
| Quest flags | GetAllCompletedQuestIDs, IsQuestFlaggedCompleted, QUEST_ACCEPTED/TURNED_IN/DETAIL | plain ids fine |
| Targeted object | PLAYER_SOFT_INTERACT_CHANGED, UnitGUID("softinteract"), C_TooltipInfo.GetWorldCursor | SecretWhenUnitIdentityRestricted: guard |
| Vignettes | C_VignetteInfo | useless: 2 rows in the client |

## 5. Recommendation
- A find = kind, id, place, build, when, who. Kinds: an item looted from an object; a key; a readable page (title +
  hash of the text, never the text); a new hidden quest flag within 10 s of a loot, read or key use; a book (by quest
  title). Steps link themselves from what players do (page -> next find, key -> lock, item -> quest), so a chain draws
  itself.
- Collections -> Books: "You 12, handed in 9, guild knows 23 spots"; slots only for books someone has seen; tier bars
  10/20/25. Secrets cards: your steps shown; a guildmate's at your reveal level (zone, then pin, then whether you read
  the same page), one click each, default zone only; "Show everything" per category off by default. Map pins: yours
  always; guild finds per reveal level; a pin fades when nobody confirmed it on the current build (the Stone Key bag
  moved). Books may open one level further by default (guides publish them). Game icons only, no catalogue text.
- Guild: one message per find (kind, id, map, x/y to 0.1, build, time; never page text); first finder credited; two
  voices confirm (second member, same id, within 30 yards, same build; dashed until then); officers can distrust a
  sender; logs capped.
- Uploads: ids, places, build, count of distinct reporters; no names, no page text; sharing off by default; the site
  can build a blurred-until-revealed Secrets map. Build on Loot.lua's loot["o<objectId>"] and Core.lua's
  completed-quest diff.
- Licences: ForeverSecrets (Loyftwa), ForeverBooks, Forever Library Scout (Kushen) are All Rights Reserved: ideas
  only. Credit Warcraft Tavern, Icy Veins and Inven on the site.

## 6. QuestBank data bugs found
1. NPC entry 1509 "Burned-Out Remains" is placed at Westfall 37.4, 50.6 (Data.lua ~5629: that is the Nailed Plank);
   the Burned-Out Remains is in the Barrens 46.4, 73.8. Quests 79007/79008 use 1509 for start and hand-in (~3249-3250),
   so Camp.chainHint sends an Alliance player holding 79008 back to Westfall instead of the Barrens.
2. Quest 79093 (Rumi, Alliance) hands in to Owen Thadd in Undercity; probably Garion Wendell.
3. Check in game: the level-60 books' hand-in NPCs; the tier-3 quest id.

## Sources
Warcraft Tavern: https://www.warcrafttavern.com/forever/guides/library-books/ ,
https://www.warcrafttavern.com/forever/guides/cozy-sleeping-bag/ ,
https://www.warcrafttavern.com/forever/news/secret-finders-are-investigating-a-keystone-fragment-in-wow-forever/ ,
https://www.warcrafttavern.com/forever/news/tome-of-dalaran-mystery-solved-in-wow-forever/ . Icy Veins (snippets):
https://www.icy-veins.com/wow-forever/news/wow-forever-players-are-chasing-a-secret-nobody-has-solved-yet/ ,
https://www.icy-veins.com/wow-forever/news/wow-forever-hid-over-12500-items-from-dataminers-heres-whats-still-secret/ ,
https://www.icy-veins.com/wow-forever/news/blizzard-hid-wow-forevers-first-legendary-but-dataminers-already-found-clues/ .
Inven (16 Oct): https://www.inven.co.kr/board/wow/6567/7236 . raidforever:
https://raidforever.com/blog/articles/wow-forever/keystone-fragment-secret-quest . allthings.how:
https://allthings.how/nibbled-on-book-in-wow-forever-how-to-start-and-complete-the-quest/ . wowforever.be:
https://wowforever.be/guides/night-watchmans-torch/ . method.gg:
https://www.method.gg/wow-forever/how-to-get-a-torch-in-wow-forever-night-watchmans-torch ,
https://www.method.gg/wow-forever/dungeons/city-of-dalaran ,
https://www.method.gg/wow-forever/mage-comprehension-and-study-guide-in-wow-forever-how-scrolls-work-and-all-scroll-effects .
Addons: https://www.curseforge.com/wow/addons/foreversecrets , https://www.curseforge.com/wow/addons/foreverbooks ,
https://www.curseforge.com/wow/addons/forever-library-scout .
