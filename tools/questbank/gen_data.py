"""Generate QuestBank/Data.lua for both factions.

Catalog: every quest from level 1 to 60, with its Forever XP: the Classic base times the multiplier
on its Wowhead Forever page (WH.Wow.Quest.setupScalingRewards). A quest whose page we have not read
keeps a multiplier of 1 (a dungeon quest takes its dungeon's, when the others agree) and a flag, and
the addon says so. Wowhead Forever only knows the quests its players have met, which ends near the
beta's level cap; above that the CMaNGOS Classic database seeds the catalog, flagged "Classic only"
until players see the quest in Forever. Its base XP is Classic's money-at-60 / 0.6, snapped to the
Forever client's QuestXP table (that rebuilds Wowhead's base exactly for 1,562 of 1,597 quests).
NPCs: where each quest starts and ends (Wowhead Forever tooltips, npcloc.py), placed on the
continent and tied to the nearest flight master of each faction. Where Wowhead has no position,
the CMaNGOS Classic database's spawn point stands in.
Chains, mutually exclusive quests, race limits, quests that start from items and the deliveries
you are handed on the day: the CMaNGOS Classic database (GPL-3.0, cmangos.py), with Wowhead
Forever's series winning wherever Forever put a new step into a chain.
Every run writes GAPS.md: what is still missing, quest by quest.
Rewards: players' quest windows, else Wowhead Forever's quest list, else the game's answer to players' QuestBank (the
quest survey), else the dungeon loot pages, else the Classic database (only items the Forever client's item table has;
D.RCLASSIC marks those quests). What each reward item is
(D.RIT) and what each class may wear and wield (D.WEAPONS, D.ARMOR): the client's Item, SkillLine, SkillRaceClassInfo,
SkillLineAbility and SpellEquippedItems tables (ITEMS_BUILD).
Travel: travel.py over the client's own taxi tables (build below).
World map icons: where each objective is done, per objective, from the CMaNGOS spawns and quest POIs
(objectives.py -> spots.json), else Wowhead Forever's quest-page mapper (mapper.py -> mapper.json, read when
present), each spot stored on the one map it is drawn on.
Icons and textures: file IDs from the Forever client's interface manifest; a missing one stops the build.

  python3 tools/questbank/gen_data.py            # write Data.lua
  python3 tools/questbank/gen_data.py --fetch    # first fetch the NPC tooltips we lack (nether.wowhead.com)
  python3 tools/questbank/gen_data.py --selftest-os  # check players' objective spots, probe_pull.py's merge to D.SPOT
                                                     # (its own fixture and made-up uploads; writes nothing)
  python3 tools/questbank/gen_data.py --selftest-survey  # check the quest survey's answers (probe_pull.py's merge of its
                                                         # fixture) as the build reads them; writes nothing
"""
import collections, csv, html, json, math, os, re, sys
from travel import Travel, DETOUR, RUN

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "QuestBank", "Data.lua")
REPO = os.path.dirname(os.path.dirname(HERE))
RAW = os.path.join(REPO, "research", "questbank")
BUILD = "1.60.1.70291"
READ = "2026-09-29"


def newest_forever_build():
    """The newest Forever client build datamined with its quest table (research/wago/1.60.x.<build>/QuestV2.csv): the
    survey asks the game about that client's quests."""
    found = []
    for d in os.listdir(os.path.join(REPO, "research", "wago")):
        m = re.match(r"^1\.60\.\d+\.(\d+)$", d)
        if m and os.path.exists(os.path.join(REPO, "research", "wago", d, "QuestV2.csv")):
            found.append((int(m.group(1)), d))
    return max(found)[1] if found else BUILD


SURVEY_BUILD = newest_forever_build()
# Blizzard, 2026-10-01 (the level-30 build): "Dungeon quests now reward 50% less extra experience beyond normal
# quest values." Wowhead Forever's pages still show the old multipliers, so every multiplier above 1 read before
# that date is cut here: 1 + (mult - 1) * NERF. Set NERF to 1 (and READ to the new date) once the pages are re-read.
NERF = 0.5
NERF_DATE = "2026-10-01"
NERF_BUILD = 70170  # the client build that carried the cut; what the game paid on it or later is post-cut


def nerfed(m):
    """A multiplier after the 2026-10-01 cut: the extra above x1 halves; x1 stays x1."""
    if m is None or m <= 1:
        return m
    return round(1 + (m - 1) * NERF, 4)




def load_json(path, default=None):
    if not os.path.exists(path):
        return default
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def load(name, default=None):
    p = os.path.join(RAW, name)
    return json.load(open(p)) if os.path.exists(p) else default


MAN = load("manifest.json")
AREAS = {int(k): v for k, v in load("areas.json").items()}
LIST = {}
for q in load("all3.json", []):
    LIST[q["id"]] = q
for src in (load("wowhead.json", {}) or {}).values():
    for q in src if isinstance(src, list) else []:
        LIST.setdefault(q["id"], q)
for src in (load("extra.json", {}) or {}).values():
    for q in src:
        LIST.setdefault(q["id"], q)
LIST_WOWHEAD = set(LIST)  # what Wowhead Forever lists, before the Classic seed below
DET = {}
for name in ("det2.json", "det3.json"):
    for k, d in (load(name, {}) or {}).items():
        if d.get("status") == 200:
            DET[int(k)] = d
# a page with two enders or givers (the library books go to Owen Thadd or Garion Wendell) links them
# only in its info box; take the first of each
import re as _re
for _d in DET.values():
    _info = _d.get("info") or ""
    for _which in ("end", "start"):
        found = []
        for _seg in _re.finditer(r"quest-%s\]\s*(?:End|Start):\s*(.*?)(?:\[/li\]|\[br\])" % _which, _info):
            _body = _seg.group(1)
            _m = _re.search(r"\[url=/forever/(npc|object|item)=(\d+)", _body)
            if _m:
                _fac = "H" if "icon-horde" in _body else ("A" if "icon-alliance" in _body else None)
                found.append((_fac, _m.group(1), int(_m.group(2))))
        if found:
            _d[_which + "s"] = found  # every one, with the faction it serves when the page says
            if not _d.get(_which + "Id"):
                _d[_which + "Type"], _d[_which + "Id"] = found[0][1], found[0][2]
TR = Travel(BUILD)
# ForeverChanges lists Forever XP next to Classic XP for dungeon quests: a second opinion on the multiplier
FC = {}
_fc = load(os.path.join("fc", "fc_quests.json"), {}) or {}
for _q in _fc.values():
    if _q.get("xpf"):
        FC[_q["id"]] = _q["xpf"]
UIMAP = {int(r["ID"]): r["Name_lang"] for r in csv.DictReader(open(os.path.join(REPO, "research", "wago", BUILD, "UiMap.csv")))}


def icon(name):
    k = "interface/icons/%s.blp" % name.lower()
    if k not in MAN:
        raise SystemExit("missing icon " + name)
    return int(MAN[k])


def has_icon(name):
    return ("interface/icons/%s.blp" % name.lower()) in MAN


def tex(path):
    k = path.lower().replace("\\", "/")
    if not k.endswith(".blp"):
        k += ".blp"
    if k not in MAN:
        raise SystemExit("missing texture " + path)
    return int(MAN[k])


# ---------------------------------------------------------------------------
# hand-written knowledge: tips, icons, NPC spots Wowhead places inside a cave, chain steps
# ---------------------------------------------------------------------------
# id: (icon, tip, extra)  extra: pre, bag (item, count[, "tool"]), turn/give (name, uiMap, x, y, place), follow
CURATED = {
    1491: ("spell_nature_corrosivebreath", "6 Wailing Essence from the ectoplasms in Wailing Caverns.", {"pre": [865]}),
    959: ("inv_drink_10", "The 99-Year-Old Port from Mad Magglish in Wailing Caverns.", {}),
    1486: ("inv_misc_pelt_wolf_ruin_03", "Deviate Hides from the Wailing Caverns raptors.", {"turn": ("Nalpak", 1413, 46.6, 35.4, "Wailing Caverns mound"), "give": ("Nalpak", 1413, 46.6, 35.4, "Wailing Caverns mound")}),
    1487: ("ability_hunter_pet_raptor", "Deviate beasts in Wailing Caverns.", {"turn": ("Ebru", 1413, 46.6, 35.4, "Wailing Caverns mound"), "give": ("Ebru", 1413, 46.6, 35.4, "Wailing Caverns mound")}),
    1221: ("inv_misc_herb_07", "Crate, manual and command stick from Mebok, then the gopher digs 6 tubers in Razorfen Kraul.", {}),
    97005: ("inv_misc_monsterfang_01", "Forever elite in the Barrens. Bring a friend.", {}),
    1069: ("inv_egg_02", "15 Deepmoss Eggs from the spider nests in Stonetalon.", {}),
    896: ("inv_misc_gem_emerald_03", "Cats Eye Emerald from Venture Co. Overseers or Enforcers.", {}),
    863: ("inv_gizmo_03", "Escort Wizzlecrank's shredder out of the Venture Co. drill site.", {"pre": [858]}),
    1806: ("spell_holy_sealofmight", "Hand the four items to Jordan, wait for the forge, keep this step.", {"pre": [1654], "turn": ("Jordan Stilwell", 1426, 52.4, 36.8, "Ironforge gates")}),
    971: ("inv_misc_note_01", "The Lorgalis Manuscript from Blackfathom Deeps.", {}),
    2922: ("inv_battery_01", "Techbot's Memory Core, Gnomeregan.", {}),
    2926: ("inv_drink_01", "Fill the phial on irradiated troggs in Gnomeregan.", {"pre": [2927]}),
    2928: ("inv_gizmo_02", "24 Robo-mechanical Guts in Gnomeregan.", {}),
    166: ("inv_misc_head_human_01", "VanCleef's head. Gryan's chain through the traitor escort first.", {"pre": [65, 132, 135, 141, 142, 155]}),
    214: ("inv_misc_bandana_03", "10 Red Silk Bandanas from the Defias in the Deadmines.", {"pre": [155]}),
    2040: ("inv_gizmo_01", "Gnoam Sprecklesprocket from Sneed's Shredder.", {}),
    92753: ("inv_misc_bomb_05", "Plant the explosives at the forge. Alba Fairmoon's Westfall chain first.", {"pre": [92745], "turn": ("Alba Fairmoon", 1436, 38.4, 83.6, "Westfall shore")}),
    167: ("inv_jewelry_amulet_03", "Foreman Thistlenettle's badge.", {}),
    168: ("inv_letter_13", "Miners' Union Cards.", {}),
    95189: ("inv_misc_note_02", "Crest of Lordaeron from the Ruins.", {}),
    92415: ("inv_letter_06", "Keep the Blood-Stained Letter in your bags. Don't accept it.", {"bag": [251522, 1]}),
    95195: ("inv_jewelry_necklace_37", "Keep 10 Bloodied Insignias in your bags. Don't accept them.", {"bag": [268540, 10]}),
    391: ("inv_misc_head_human_01", "Bazil Thredd's head.", {}),
    1275: ("inv_misc_organ_03", "8 Corrupted Brain Stems in Blackfathom Deeps.", {}),
    1199: ("inv_jewelry_amulet_06", "10 Twilight Pendants in Blackfathom Deeps.", {}),
    1200: ("inv_misc_head_orc_01", "Kelris's head. In Search of Thaelrid first.", {"pre": [1198]}),
    169: ("inv_misc_head_orc_01", "Gath'Ilzogg's head.", {}),
    180: ("inv_misc_monsterclaw_04", "Fangore's paw.", {}),
    95999: ("inv_staff_08", "Incinerator Gar'im's broken staff.", {}),
    128: ("inv_misc_head_orc_01", "15 Blackrock Champions.", {}),
    34: ("inv_misc_horn_01", "Bellygrub's tusk.", {}),
    91: ("inv_jewelry_necklace_04", "10 Shadowhide Pendants.", {}),
    98387: ("inv_banner_03", "Holding it blocks Tharil'zun, the next step of the chain.", {}),
    150: ("inv_misc_fish_02", "Murloc fins.", {}),
    219: ("inv_misc_note_02", "Escort Corporal Keeshan back from Render's Rock.", {}),
    115: ("inv_misc_orb_01", "3 Midnight Orbs from Blackrock Shadowcasters.", {}),
    126: ("inv_misc_monsterclaw_02", "Yowler's paw. A Baying of Gnolls first.", {"pre": [124]}),
    19: ("inv_misc_head_orc_01", "Hand in Blackrock Blockade first, then kill Tharil'zun.", {"pre": [20, 98387]}),
    98386: (None, None, {"pre": [20]}),
    98387: (None, None, {"pre": [20]}),
    101: ("spell_nature_stoneclawtotem", "10 Ghoul Fangs, 10 Skeleton Fingers, 5 Vials of Spider Venom.", {}),
    58: ("inv_misc_bone_humanskull_01", "20 Plague Spreaders at Raven Hill. Parts 1 and 2 first.", {"pre": [56, 57]}),
    98447: ("spell_shadow_haunting", "The Valor family ghosts at Raven Hill. Part 1 first.", {"pre": [96139], "give": ("Sirra Von'Indi", 1431, 72.4, 47.4, None), "turn": ("Sirra Von'Indi", 1431, 72.4, 47.4, None)}),
    174: ("trade_engineering", "A Bronze Tube for Viktori: buy one or ask an engineer.", {"bag": [4371, 1, "tool"]}),
    90: ("inv_misc_food_48", "10 Lean Wolf Flanks.", {}),
    96137: ("inv_weapon_shortblade_05", "10 Young Black Ravagers and 7 Black Ravagers.", {"give": ("Sirra Von'Indi", 1431, 72.4, 47.4, None), "turn": ("Sirra Von'Indi", 1431, 72.4, 47.4, None)}),
    401: ("inv_letter_06", "The end of Abercrombie's long chain.", {"pre": [148, 149, 154, 157, 158, 156, 159, 133, 134, 160, 251]}),
    95161: ("inv_letter_06", "Given when you hand in Remember That I Love You. Deliver to Avette Fellwood.", {"follow": 92415}),
    373: ("inv_letter_06", "An Unsent Letter from Edwin VanCleef in the Deadmines. Keep the letter in your bags.", {"bag": [2874, 1]}),
    98423: ("inv_scroll_03", "Keep the Treaty in your bags. Don't accept it.", {"bag": [281030, 1]}),
}
STEPNAME = {1654: "the item step of The Test of Righteousness", 155: "The Defias Brotherhood, the traitor escort",
            65: "The Defias Brotherhood, Gryan's first step", 132: "The Defias Brotherhood, Wiley's note",
            135: "The Defias Brotherhood, the note to Shaw", 141: "The Defias Brotherhood, Shaw's reply",
            142: "The Defias Brotherhood, the Defias thugs", 56: "The Night Watch, part 1", 57: "The Night Watch, part 2",
            96139: "The Valor Family, part 1"}

DUNGEON = {  # area: (lfg icon, zone, entrance)
    1581: ("deadmines", "Westfall", (1436, 42.5, 71.7)), 718: ("wailingcaverns", "The Barrens", (1413, 46.0, 36.4)),
    209: ("shadowfangkeep", "Silverpine Forest", (1421, 44.8, 67.8)), 719: ("blackfathomdeeps", "Ashenvale", (1440, 14.2, 14.0)),
    717: ("stormwindstockades", "Stormwind City", None), 721: ("gnomeregan", "Dun Morogh", (1426, 24.4, 39.8)),
    491: ("razorfenkraul", "The Barrens", (1413, 42.3, 89.9)), 796: ("scarletmonastery", "Tirisfal Glades", None),
    722: ("razorfendowns", "The Barrens", None), 1337: ("uldaman", "Badlands", None), 2437: ("ragefirechasm", "Orgrimmar", None),
    16611: ("ruinsoflordaeron", "Tirisfal Glades", None),
    # The Hall of Thanes: "Inside Ironforge: the way in is from the High Seat, as beta players describe it"
    # (research/questbank/fc/hall-of-thanes.html); the spot is King Magni's at the High Seat as the catalog places him
    # (D.NPC), no coordinate of its own yet
    16919: ("dungeon", "Ironforge", (1455, 39.4, 55.4)),
    1176: ("zulfarak", "Tanaris", None), 2100: ("maraudon", "Desolace", None),
    # Wowhead files the Sunken Temple quests under area 1417; 1477 is the instance's own row
    1417: ("sunkentemple", "Swamp of Sorrows", None), 1477: ("sunkentemple", "Swamp of Sorrows", None),
    1584: ("blackrockdepths", "Searing Gorge", None), 1583: ("blackrockspire", "Burning Steppes", None),
    2557: ("diremaul", "Feralas", None), 2017: ("stratholme", "Eastern Plaguelands", None),
    2057: ("scholomance", "Western Plaguelands", None),
}
ZONE_ICON = {"Stranglethorn Vale": "achievement_zone_stranglethorn_01", "Swamp of Sorrows": "achievement_zone_swampsorrows_01",
             "Stonetalon Mountains": "achievement_zone_stonetalon_01", "Silverpine Forest": "achievement_zone_silverpine_01",
             "Stormwind City": "spell_arcane_teleportstormwind", "Orgrimmar": "spell_arcane_teleportorgrimmar",
             "Undercity": "spell_arcane_teleportundercity", "Thunder Bluff": "spell_arcane_teleportthunderbluff",
             "Deeprun Tram": "inv_gizmo_02", "Kharanos": "achievement_zone_dunmorogh"}


def zone_icon(name):
    if name in ZONE_ICON:
        return icon(ZONE_ICON[name])
    base = name.lower().replace("the ", "").replace(" ", "").replace("'", "")
    for cand in ("achievement_zone_" + base, "achievement_zone_%s_01" % base):
        if has_icon(cand):
            return icon(cand)
    return icon("inv_misc_map_01")


# ---------------------------------------------------------------------------
# the catalog
# ---------------------------------------------------------------------------
GAME_LV = {}  # quest -> the level the game's quest log showed players, where it differs from the catalog's (filled below)


def qlevel(qid):
    if qid in GAME_LV:
        return GAME_LV[qid]
    d = DET.get(qid)
    if d and d.get("ql"):
        return int(d["ql"])
    return LIST[qid]["level"]


def base_xp(qid):
    d = DET.get(qid) or {}
    c = ((load_cm_quests() or {}).get(str(qid))) or {}
    return d.get("base") or LIST[qid].get("xp") or classic_base(c) if c else (d.get("base") or LIST[qid].get("xp") or 0)


_CMQ_CACHE = None


def load_cm_quests():
    global _CMQ_CACHE
    if _CMQ_CACHE is None:
        _CMQ_CACHE = (load("cmangos.json", {}) or {}).get("quests") or {}
    return _CMQ_CACHE


_CMQ_IDS = {int(k) for k in ((load("cmangos.json", {}) or {}).get("quests") or {})}
MAXLVL = 60
# the client's quest XP table: the XP of each difficulty at each quest level
XPT = {int(r["ID"]): [int(r["Difficulty_%d" % i]) for i in range(10)]
       for r in csv.DictReader(open(os.path.join(REPO, "research", "wago", BUILD, "QuestXP.csv")))}
AREA_ROW = {int(r["ID"]): r for r in csv.DictReader(open(os.path.join(REPO, "research", "wago", BUILD, "AreaTable.csv")))}
RAID_AREAS = {2159, 2717, 1977, 2677, 3429, 3428, 3456}
CLASS_SORT = {-61, -81, -82, -141, -161, -162, -261, -262, -263}
PROF_SORT = {-24, -101, -121, -181, -182, -201, -264, -304, -324}


def classic_base(c):
    """Classic pays money at level 60 instead of XP: money / 0.6 is the XP, snapped to the client's table."""
    mm = c.get("moneymax") or 0
    if mm <= 0:
        return 0
    guess = mm / 0.6
    lvl = c["level"] if c["level"] and c["level"] > 0 else c["min"]
    row = XPT.get(lvl)
    if row:
        best = min((v for v in row if v > 0), key=lambda v: abs(v - guess), default=None)
        if best and abs(best - guess) <= max(10, guess * 0.05):
            return best
    return int(round(guess / 5.0) * 5)


CLASSIC = set()
# The crafting writs: an item named "Craftsman's Writ" starts a quest that asks you to deliver what it names (the client's
# ItemSparse StartQuestID). The Argent Dawn's (22600-22626, quests 9178-9206, from Naxxramas' trash) and Forever's own
# (264011 and on, quests 94004 and 94212-94360, from the Sealed Apprentice's, Journeyman's, Expert's, Artisan's and
# Craftsman's Writs: "a pending crafting order intercepted in transit"). No XP and no giver, so nothing plans them; the
# catalog keeps them (flag 131072, a turn-in) for the reward finders alone. WRIT[quest id] = (writ item, its name)
ITEMS_BUILD = "1.60.1.70338"
WRIT = {}
for _r in csv.DictReader(open(os.path.join(REPO, "research", "wago", ITEMS_BUILD, "ItemSparse.csv"), encoding="utf-8")):
    if (_r.get("Display_lang") or "").startswith("Craftsman's Writ") and int(_r.get("StartQuestID") or 0) > 0:
        WRIT[int(_r["StartQuestID"])] = (int(_r["ID"]), _r["Display_lang"])
CRAFTING_AREA = 16941  # Wowhead's area of Forever's writ quests (the client's AreaTable: "Crafting")
# Forever's client descends from Season of Discovery and carries its leftovers: Wowhead lists quests
# whose NPCs were never put into Forever. Players' reports settle it quest by quest:
NOT_IN_FOREVER = {78132, 78133, 78134}  # Alonso's Dragonslayer quests: no Alonso in Ashenvale (owner, 2026-09-30)
# (City of Dalaran's quests, Wowhead area 16544, were left out here until the dungeon opened for testing: Blizzard's
# notes of 2026-10-08)
SOD_NPC_OK = {211033, 211022}            # Garion Wendell and Owen Thadd take library books in Forever (owner)


def sod_leftover(qid):
    """A giver or ender from Season of Discovery's NPC range that nobody has met in Forever."""
    d = DET.get(qid) or {}
    for i, t in ((d.get("startId"), d.get("startType")), (d.get("endId"), d.get("endType"))):
        if i and t in ("npc", None) and 200000 <= i < 240000 and i not in SOD_NPC_OK:
            return True
    return False


def classic_record(qid, c):
    """A LIST-shaped record from the Classic database, for a quest Wowhead Forever doesn't list."""
    lvl = c["level"] if c["level"] and c["level"] > 0 else c["min"]
    sort = c.get("sort") if c.get("sort") is not None else c.get("zone")
    cat2 = 7
    if sort and sort > 0:
        if sort in RAID_AREAS:
            cat2 = 3
        elif sort in DUNGEON:
            cat2 = 2
        else:
            row = AREA_ROW.get(sort)
            cont = int(row["ContinentID"]) if row else None
            cat2 = cont if cont in (0, 1) else (2 if cont is not None else 7)
    elif sort in CLASS_SORT:
        cat2 = 4
    elif sort in PROF_SORT:
        cat2 = 5
    r = c.get("races") or 0
    side = 1 if (r & 77 and not r & 178) else (2 if (r & 178 and not r & 77) else 0)
    return {"id": qid, "name": c["title"], "level": lvl, "reqlevel": c["min"] or 1, "side": side, "category": sort,
            "category2": cat2, "type": c.get("type") or 0, "xp": classic_base(c), "reqclass": c.get("classes") or 0}
JUNK = ("<", "[", "UNUSED", "NYI", "REUSE", "test quest", "Test Quest")
EVENTS = {-22, -364, -365, -366, -367, -368, -369, -370, -1001, -1002, -1003, -1005}


def junk(q):
    """Placeholder quests the game never offers, and war efforts, invasions and holidays."""
    return any(t in q["name"] for t in JUNK) or q.get("category") in EVENTS or q.get("category2") == 9


# the Classic seed: quests Wowhead Forever hasn't met yet
for _k, _c in ((load("cmangos.json", {}) or {}).get("quests") or {}).items():
    _qid = int(_k)
    if _qid in LIST or not _c.get("title") or any(t in _c["title"] for t in JUNK):
        continue
    _lvl = _c["level"] if _c["level"] and _c["level"] > 0 else _c["min"]
    _sort = _c.get("sort") if _c.get("sort") is not None else _c.get("zone")
    _writ = _qid in WRIT  # a writ's turn-in: repeatable and no XP, kept for the reward finders
    if not (1 <= (_lvl or 0) <= MAXLVL) or (_c["min"] or 0) > MAXLVL or _sort in EVENTS or ((_c.get("special") or 0) & 1 and not _writ):
        continue
    if _c.get("type") in (41, 62, 88, 89) or not _c.get("starts") or not _c.get("ends"):
        continue
    _rec = classic_record(_qid, _c)
    if _rec["category2"] in (3, 6) or (_rec["xp"] <= 0 and not _writ) or not (_c["level"] and _c["level"] > 0):
        continue  # raids, battlegrounds, and quests with no level or no XP to plan
    LIST[_qid] = _rec
    CLASSIC.add(_qid)

# What players' addons saw in game: tools/probe_pull.py merges every upload into disc.json (votes,
# not winners). A quest anyone met in Forever is no longer "Classic only", whatever Wowhead has read.
DISC = load("disc.json", {}) or {}
SEEN = set()
for _k, _q in (DISC.get("q") or {}).items():
    if isinstance(_q, dict) and (_q.get("xp") or _q.get("from") or _q.get("to") or (_q.get("n") or 0) > 0):
        SEEN.add(int(_k))
for _offers in (DISC.get("offer") or {}).values():
    SEEN.update(int(_k) for _k in _offers)
CLASSIC -= SEEN
# What the game paid, from players' hand-ins (QuestBankDB.turnins) and their own quest-window readings
# (probe_pull.py merge_seen): votes keyed "xp:level:build:src:era". A hand-in on the cut's build or later,
# at a level where the quest still pays in full, is the truth; a window reading counts only from a table
# the addon has purged of pre-cut numbers (liveEra >= 2).
SEEN_XP = DISC.get("seen") or {}


def lua_round(x):
    return int(math.floor(x + 0.5))


def round_xp(e):
    """The game's rounding of quest XP (the server's RoundXPValue; Model.lua roundQuestXp): to 5 up to 100, to 10 up
    to 500, to 25 up to 1,000, to 50 above. Hand-ins on 2026-10-02 showed it: 590 paid 600, 870 paid 875."""
    e = int(math.floor(e))
    if e <= 100:
        return 5 * ((e + 2) // 5)
    if e <= 500:
        return 10 * ((e + 5) // 10)
    if e <= 1000:
        return 25 * ((e + 12) // 25)
    return 50 * ((e + 25) // 50)


BUFF = 1.03  # a temporary +3% XP buff on the player (Well Rested from the sleeping bag, it seems): it comes and goes
UNBUFFED = []  # (qid, read, game's number) for GAPS.md


def unbuff(xp):
    """The game's number behind a reading taken under the +3% buff. The game rounds quest XP to its grid (round_xp) and
    the buff then pays the grid value * 1.03, give or take one: 390 shows 401, 1,250 shows 1,288, 5,500 shows 5,665.
    A reading on the grid is taken as it is. Some buffed values land on the grid themselves (850 shows 875, 340 shows
    350, 5,000 shows 5,150) and arithmetic alone can't tell them from a real number; QuestBank 3.5.4 notes the auras
    up at each reading so the buff can be named and those cases settled."""
    if xp <= 0 or round_xp(xp) == xp:
        return xp
    g = round_xp(xp / BUFF)
    for cand in (g, round_xp(g - 1), round_xp(g + 60)):
        if cand > 0 and abs(cand * BUFF - xp) <= 1:  # the game floors or rounds the boosted value: 1,250 shows 1,288
            return cand
    return xp


# The quest survey (Survey.lua): players' QuestBank asks the game, by id and a couple a second, about the quests no
# list has read (QuestBankDB.disc.survey: the title, the reward items, the XP at the player's level then, the money, the
# quest's level and the client build), and probe_pull.py keeps every upload's reading as votes in disc.json's "sv".
# One reading per quest is taken: the newest build's reward list, then the one most uploads had. The survey never
# touches DISC["q"]: the server answering about a quest is no sighting in the world, so it clears no "Classic only" flag
# and places no quest. gen_data.py --selftest-survey reads made-up uploads instead of disc.json's (see the end).
SELFTEST_SURVEY = "--selftest-survey" in sys.argv


def survey_pick(a):
    """One quest's survey votes -> {"t": title, "lv": quest level, "c": choose one, "r": always given, "xp": XP at full
    value (0 not known), "m": copper, "b": newest build, "u": uploads}. c and r are None when no reading had the rewards
    whole; empty lists mean the game said the quest gives no items."""
    def top(votes):
        votes = {k: v for k, v in (votes or {}).items() if isinstance(v, int) and v > 0}
        return max(votes.items(), key=lambda kv: (kv[1], kv[0]))[0] if votes else None
    out = {"t": None, "lv": 0, "c": None, "r": None, "xp": 0, "m": None, "b": int(a.get("b") or 0), "u": int(a.get("u") or 0)}
    t = top(a.get("t"))
    if isinstance(t, str) and t.strip():
        out["t"] = " ".join(t.split())
    lv = top(a.get("lv"))
    out["lv"] = int(lv) if lv and str(lv).isdigit() else 0
    rw = {k: v for k, v in (a.get("rw") or {}).items() if isinstance(v, list) and len(v) == 2}
    if rw:
        key = max(rw.items(), key=lambda kv: (kv[1][1], kv[1][0], kv[0]))[0]  # newest build, then most uploads
        c, _, r = key.partition("|")
        out["c"] = [int(x) for x in c.split(",") if x.isdigit()]
        out["r"] = [int(x) for x in r.split(",") if x.isdigit() and int(x) not in out["c"]]
    # XP read at a level where the quest pays in full (not grey: at most five levels above it), the buff undone
    xps = {}
    for k, n in (a.get("xp") or {}).items():
        xp, _, pl = str(k).partition("@")
        if xp.isdigit() and pl.isdigit() and out["lv"] and int(pl) <= out["lv"] + 5:
            g = unbuff(int(xp))
            xps[g] = xps.get(g, 0) + n
    if xps:
        out["xp"] = max(xps.items(), key=lambda kv: (kv[1], kv[0]))[0]
    m = top(a.get("m"))
    out["m"] = int(m) if m is not None and str(m).isdigit() else None
    return out


def survey_selftest_input():
    """--selftest-survey: disc.json's "sv" and "sv_no" as probe_pull.py's own merge makes them from its survey fixture
    and a made-up later upload, instead of the real ones."""
    sys.path.insert(0, os.path.dirname(HERE))
    import probe_pull
    acc = probe_pull.empty()
    fixture = os.path.join(os.path.dirname(HERE), "fixtures", "probe", "QuestBank-survey.lua")
    kind, _ = probe_pull.merge_upload(acc, open(fixture, encoding="utf-8").read(), "fixture")
    assert kind == "questbank-savedvars" and acc.get("sv"), "the fixture's survey reaches disc.json"
    # a later build: the reward list of 704 changed; it wins although the old one has more uploads
    probe_pull.merge_survey(acc, {704: {"t": "Agmond's Fate", "lvl": 38, "c": [9535, 9536], "r": [], "b": 70400}})
    return json.loads(json.dumps(acc["sv"])), json.loads(json.dumps(acc.get("sv_no") or {}))


if SELFTEST_SURVEY:
    DISC = dict(DISC)
    DISC["sv"], DISC["sv_no"] = survey_selftest_input()
SURVEY_PICK = {int(k): survey_pick(a) for k, a in (DISC.get("sv") or {}).items() if str(k).isdigit() and isinstance(a, dict)}
# the game said nothing about these, three times, to anyone (a quest another upload read, its title at least, was answered)
SURVEY_NO = {int(k) for k in (DISC.get("sv_no") or {}) if str(k).isdigit()} - {q for q, p in SURVEY_PICK.items() if p["t"] or p["c"] is not None}


def seen_full(qid, ql):
    """The XP the game paid for a quest after the cut, at full value, or None. Buffed readings count as the game's number."""
    best = {}
    for key, n in (SEEN_XP.get(str(qid)) or {}).items():
        parts = key.split(":")
        if len(parts) < 5:
            continue
        xp, lvl, build, src, era = int(parts[0]), int(parts[1]), int(parts[2]), parts[3], int(parts[4])
        plain = unbuff(xp)
        if plain != xp:
            UNBUFFED.append((qid, xp, plain))
            xp = plain
        if build < NERF_BUILD or lvl > ql + 5 or xp <= 0:
            continue
        if src != "turnin" and era < 2:
            continue
        best[xp] = best.get(xp, 0) + n * (2 if src == "turnin" else 1)
    if not best:
        return None
    return max(best.items(), key=lambda kv: (kv[1], kv[0]))[0]

# Where players' games saw an NPC (disc.json npc: "uiMap:x,y" spots, where the player stood while talking to it, a
# few yards off). Already in Forever's frame. Every upload so far is one account's growing file, so a spot's vote
# count says how often it was re-uploaded, not how many saw it: each spot is one observation, and the one closest
# to the others (the medoid) stands for the NPC. Spots inside instances are left to the dungeon path.
GAME_POS = {}  # ("npc"|"object", id) -> (name, uiMap, x, y)
GAME_SPLIT = []
for _key, _rec in (DISC.get("npc") or {}).items():
    if not isinstance(_rec, dict) or _key[:1] not in ("c", "o") or not _key[1:].isdigit():
        continue
    _pts = []
    for _spot in (_rec.get("p") or {}):
        try:
            _m, _xy = _spot.split(":")
            _x, _y = (float(v) for v in _xy.split(","))
        except ValueError:
            continue
        _w = TR.world(int(_m), _x, _y)
        if _w and _w[0] in (0, 1):
            _pts.append((int(_m), _w))
    if not _pts:
        continue
    _cont = max({w[0] for _, w in _pts}, key=lambda c: sum(1 for _, w in _pts if w[0] == c))
    _pts = [p for p in _pts if p[1][0] == _cont]
    _best = min(_pts, key=lambda p: sum(math.hypot(p[1][1] - o[1][1], p[1][2] - o[1][2]) for o in _pts))
    if max(math.hypot(a[1][1] - b[1][1], a[1][2] - b[1][2]) for a in _pts for b in _pts) > 40:
        GAME_SPLIT.append(_key)
    _loc = TR.locate(_cont, _best[1][1], _best[1][2], (_best[0],))
    if _loc:
        GAME_POS[("npc" if _key[0] == "c" else "object", int(_key[1:]))] = (_rec.get("n") or "", _loc[0], _loc[1], _loc[2])

# Quests players met in game that neither Wowhead Forever nor the Classic database has: a record from their notes
# (flag 16384). Level as the quest log showed it; required level the lowest anyone took it at (an upper bound);
# XP the game's number (buffed readings undone) when the reading was at full value; zone from where its giver
# or ender stands; the side shared by every other quest of that NPC, else both. Nothing to place it: left out.
DISC_ONLY, DISC_UNPLACED = set(), []
_DISC_Q = DISC.get("q") or {}
_NPC_SIDES = {}
for _qid, _q in LIST.items():
    _d = DET.get(_qid) or {}
    for _which in ("startId", "endId"):
        if _d.get(_which):
            _NPC_SIDES.setdefault(_d[_which], set()).add({1: 1, 2: 2}.get(_q.get("side"), 0))


def disc_xp(dq, lv):
    votes = {}
    for k, row in (dq.get("xp") or {}).items():
        try:
            lvl = int(str(k).rstrip("b"))
        except ValueError:
            continue
        if lvl > lv + 5:
            continue  # grey for that player: not the full value
        for v, n in (row or {}).items():
            try:
                g = unbuff(int(v))
            except ValueError:
                continue
            if g > 0:
                votes[g] = votes.get(g, 0) + 1  # one observation, however often re-uploaded
    return max(votes.items(), key=lambda kv: (kv[1], kv[0]))[0] if votes else 0


# NPCs that give nothing but PvP quests in the Classic data (the battlemasters' Call to Arms): a new quest of theirs is a
# battleground one (Darkspear Islands Clash), which the catalog leaves out as it does every battleground quest
_PVP_GIVERS = {}
for _c in ((load("cmangos.json", {}) or {}).get("quests") or {}).values():
    for _kind, _i in _c.get("starts") or []:
        if _kind == "npc":
            _PVP_GIVERS[_i] = _PVP_GIVERS.get(_i, True) and _c.get("type") == 41
_PVP_GIVERS = {i for i, only in _PVP_GIVERS.items() if only}
DISC_PVP = []
for _k, _dq in _DISC_Q.items():
    if not isinstance(_dq, dict) or not str(_k).isdigit():
        continue
    _qid = int(_k)
    if _qid in LIST or _qid in NOT_IN_FOREVER or not _dq.get("lv") or not (1 <= int(_dq["lv"]) <= MAXLVL):
        continue
    _givers = [int(g[1:]) for g in (_dq.get("from") or []) if g[:1] == "c" and g[1:].isdigit()]
    if _givers and all(g in _PVP_GIVERS for g in _givers):
        DISC_PVP.append(_qid)
        continue
    _lv = int(_dq["lv"])
    _where, _ids = None, []
    for _nk in list(_dq.get("from") or []) + list(_dq.get("to") or []):
        if _nk[:1] in ("c", "o") and _nk[1:].isdigit():
            _gp = GAME_POS.get(("npc" if _nk[0] == "c" else "object", int(_nk[1:])))
            _ids.append(int(_nk[1:]))
            if _gp and not _where:
                _where = _gp
    if not _where:
        DISC_UNPLACED.append(_qid)
        continue
    _area = TR.maps.get(_where[1], {}).get("area")
    _row = AREA_ROW.get(_area) if _area else None
    _sides = set().union(*[_NPC_SIDES.get(i, set()) for i in _ids]) if _ids else set()
    LIST[_qid] = {"id": _qid, "name": _dq.get("t") or ("Quest %d" % _qid), "level": _lv,
                  "reqlevel": min(int(_dq.get("min") or _lv), _lv), "side": _sides.pop() if len(_sides) == 1 else 0,
                  "category": _area, "category2": int(_row["ContinentID"]) if _row and int(_row["ContinentID"]) in (0, 1) else 7,
                  "type": 0, "xp": disc_xp(_dq, _lv), "reqclass": 0}
    DISC_ONLY.add(_qid)

# What one Alliance account's game showed against the catalog's side: 79362 was handed in at Darkshire (c268) for
# 2,060 XP although Wowhead lists it Horde-only with c6176 in Alterac; 92706 was offered from o3972. Both sides take
# them; 79362's Alliance ender is c268, the Horde one stays Wowhead's.
GAME_SIDE = {79362: 0, 92706: 0}
GAME_ENDER_A = {79362: ("npc", 268)}
# Grant's Shield is a Shaman quest for the Horde in Wowhead's data, and a Dwarf Paladin completed it in game
GAME_CLASS = {79362: 64 | 2}
for _qid, _side in GAME_SIDE.items():
    if _qid in LIST:
        LIST[_qid]["side"] = _side
for _qid, _cls in GAME_CLASS.items():
    if _qid in LIST:
        LIST[_qid]["reqclass"] = _cls
# The level the game's quest log shows, where players saw one different from the catalog's (Fall of Dun Modr is 30
# in game, 25 on Wowhead): it decides the grey-quest XP cut and which readings count at full value
GAME_LEVEL_FIX = []
for _k, _dq in (DISC.get("q") or {}).items():
    if isinstance(_dq, dict) and str(_k).isdigit() and int(_k) in LIST and int(_k) not in DISC_ONLY:
        _lv = _dq.get("lv")
        if isinstance(_lv, int) and 1 <= _lv <= MAXLVL:
            _was = qlevel(int(_k))
            if _lv != _was:
                GAME_LV[int(_k)] = _lv
                GAME_LEVEL_FIX.append((int(_k), _was, _lv))

# A line the quest tooltip adds about where a number comes from, or what Blizzard changed since (D.NOTE)
NOTE = {}
# Quests none of the lists above has yet, written here from what is known, each fact with its source. 99411 is in the
# client's quest table since build 70170, and Blizzard's notes of 2026-10-01 add it to Mulgore. Wowhead's tooltip
# (qtips.json): "Ahab Wheathoof at Bloodhoof Village in Mulgore wants you to feed his prized puppy, Kyle the Frenzied
# ... return to Ahab Wheathoof". Level and required level from ForeverChanges' quest list: Wowhead's quest pages turn
# scripts away and no player has uploaded its quest window yet. Horde, as Bloodhoof Village is. XP not known. Ahab's
# NPC id isn't known (Wowhead's NPC tooltip for his old id, 23618, answered 404 on 2026-10-08), so neither is his spot:
# set AHAB once a player's QuestBank has met him or Wowhead shows him.
AHAB = None
HAND = {99411: ({"name": "Kyle's Gone Missing!", "level": 7, "reqlevel": 5, "side": 2, "category": 215, "category2": 1,
                 "type": 0, "xp": 0, "reqclass": 0},
                {"startType": "npc", "startId": AHAB, "endType": "npc", "endId": AHAB} if AHAB else {},
                "New in the 1 October build (Blizzard's notes). Ahab Wheathoof gives it in Bloodhoof Village (Wowhead); "
                "QuestBank doesn't have his spot yet. Level and required level from ForeverChanges' quest list until a "
                "player's QuestBank sees it.")}
for _qid, (_rec, _det, _note) in HAND.items():
    if _qid not in LIST:
        LIST[_qid] = dict(_rec, id=_qid)
        if _det:
            DET.setdefault(_qid, dict(_det, id=_qid, status=200))
        NOTE[_qid] = _note

# Blizzard's notes, 2026-10-08: "The new quests for the Gelkis and the Magram beginning with "Valley of Bones" now
# require a minimum level of 35 (was 30)." Valley of Bones, the steps players' games opened right after it, and what
# the new NPCs it leads to give (Orgrul, who takes it, Hagiak after him). The catalog had the lowest level anyone took
# them at, 30, from before that build. Flag 32768: the required level is Blizzard's, not that.
VALLEY_OF_BONES, VOB_REQ = 92841, 35
REQ_STATED = {}  # quest -> its required level as Blizzard's notes give it
if VALLEY_OF_BONES in LIST:
    _next = {}
    for _pair in (DISC.get("chain") or {}):
        _a, _, _b = _pair.partition(">")
        if _a.isdigit() and _b.isdigit():
            _next.setdefault(int(_a), set()).add(int(_b))
    _side = lambda q, w: {k for k in ((_DISC_Q.get(str(q)) or {}).get(w) or []) if k[:1] == "c" and k[1:].isdigit()}  # noqa: E731
    _got, _npcs = {VALLEY_OF_BONES}, set()
    while True:
        _npcs |= {k for q in _got for k in _side(q, "to") if int(k[1:]) >= 200000}  # new Forever NPCs only
        _more = {b for a in _got for b in _next.get(a, ())} | {int(k) for k in _DISC_Q if str(k).isdigit() and _side(k, "from") & _npcs}
        _more = {q for q in _more if q in LIST} - _got
        if not _more:
            break
        _got |= _more
    for _qid in sorted(_got):
        if (LIST[_qid].get("reqlevel") or 0) < VOB_REQ:
            REQ_STATED[_qid] = VOB_REQ
            LIST[_qid]["reqlevel"] = VOB_REQ
            NOTE[_qid] = "Needs level 35 since the 8 October build (Blizzard's notes; it was 30)."

# Blizzard's notes, 2026-10-08, on quests whose numbers nobody has read since: Elixir of Pain now pays the XP Stanley
# gave when killed, and the quests around Shadowvale and Bandarion Keep (Tirisfal, Forever's new quests there: their
# NPCs stand around 22, 45) went up in level. Until players' quest logs show the new numbers, the tooltip says so.
CHANGED_1008 = {502: ("Changed in the 8 October build (Blizzard's notes): it now also pays the XP Stanley gave. The number "
                      "here is from before; once you hold the quest, QuestBank uses the game's own.")}
BANDARION = (1420, 22.0, 45.0, 4.0)  # Tirisfal Glades, x, y and how far (map percent) counts as around
TIRISFAL_NOTE = ("Blizzard raised the level of the quests around Shadowvale and Bandarion Keep in the 8 October build. "
                 "The level here is from before; your quest log shows the new one.")

IDS = []
for qid, q in LIST.items():
    if qid in NOT_IN_FOREVER:
        continue
    if qid in CURATED or qid in DISC_ONLY:
        IDS.append(qid)
        continue
    if q.get("type") in (41, 62) or q.get("category2") in (3, 6) or junk(q):
        continue
    _d = DET.get(qid) or {}
    if qid < 20000 and qid not in _CMQ_IDS and not _d.get("startId") and not _d.get("endId"):
        continue  # nobody gives or takes it, by Wowhead or the Classic database: a retired Classic ID (The Glowing
        # Shard is 6981, not 3366) or a Forever one Wowhead lists bare (999, 1005, 1500: no giver, ender or XP)
    if not (1 <= qlevel(qid) <= MAXLVL) or (q.get("reqlevel") or 0) > MAXLVL:
        continue
    if qlevel(qid) >= MAXLVL and not base_xp(qid) and qid not in WRIT:
        continue  # client leftovers Wowhead lists at level 60 with no XP (the writs' turn-ins stay: WRIT)
    IDS.append(qid)
IDS.sort()

# The client's completion bits (QuestV2.UniqueBitFlag): quests that share one are done together, so only one of them is
# ever handed in, and they rule each other out (D.EXCL). Since build 70291 each step of the shaman's Call of Earth shares
# one across Durotar, Mulgore, Zephras Isle and the Alliance's version. A quest with no class of its own takes the one
# its same-named twins share (Wowhead lists the Zephras Isle steps with none).
BIT = {int(r["ID"]): int(r["UniqueBitFlag"]) for r in csv.DictReader(open(os.path.join(REPO, "research", "wago", BUILD, "QuestV2.csv")))}
BIT_GROUPS = {}
for _qid in IDS:
    if _qid in BIT:
        BIT_GROUPS.setdefault(BIT[_qid], []).append(_qid)
BIT_GROUPS = {b: g for b, g in BIT_GROUPS.items() if len(g) > 1}
BIT_CLASS = []
for _g in BIT_GROUPS.values():
    for _qid in _g:
        if not LIST[_qid].get("reqclass"):
            _cls = {LIST[o].get("reqclass") for o in _g if o != _qid and LIST[o].get("name") == LIST[_qid].get("name") and LIST[o].get("reqclass")}
            if len(_cls) == 1:
                LIST[_qid]["reqclass"] = _cls.pop()
                BIT_CLASS.append(_qid)
# the groups the build before had too, for GAPS.md (none when that build's table isn't here)
_prev = os.path.join(REPO, "research", "wago", "1.60.1.70170", "QuestV2.csv")
BIT_PREV = {int(r["ID"]): int(r["UniqueBitFlag"]) for r in csv.DictReader(open(_prev))} if os.path.exists(_prev) else {}


def npc_key(kind, i):
    return "%s/%s" % (kind or "npc", i)


_CMQ = (load("cmangos.json", {}) or {}).get("quests", {})


def needed_npcs():
    keys = set()
    for qid in IDS:
        d = DET.get(qid) or {}
        for _f, kind, i in (d.get("ends") or []) + (d.get("starts") or []):
            if kind in ("npc", "object"):
                keys.add(npc_key(kind, i))
        for kind, i in ((d.get("endType"), d.get("endId")), (d.get("startType"), d.get("startId"))):
            if not i or kind == "item":
                continue
            if kind in ("npc", "object"):
                keys.add(npc_key(kind, i))
            else:  # older reads don't say; the Classic database does for Classic quests
                q = _CMQ.get(str(qid), {})
                cm = [k for k, x in q.get("ends", []) + q.get("starts", []) if x == i]
                keys.add(npc_key(cm[0] if cm else "npc", i))
    return keys


if "--fetch" in sys.argv or "--fetch-all" in sys.argv:
    import npcloc
    _spawned = {"%s/%s" % (k, i) for k, v in (load("cmangos.json", {}) or {}).get("spawns", {}).items() for i in v}  # once, at fetch time
    missing = sorted(k for k in needed_npcs() if k not in npcloc.cache)
    if "--fetch-all" not in sys.argv:
        # Classic NPCs already have the Classic database's spawn point; ask Wowhead for the rest
        missing = [k for k in missing if k not in _spawned]
    print("fetching", len(missing), "tooltips")
    for n, k in enumerate(missing):
        kind, i = k.split("/")
        npcloc.get(kind, int(i))
        if n % 50 == 0:
            print(" ", n, flush=True)
LOC = load("npcloc.json", {})
_cm = load("cmangos.json", {"quests": {}, "items": {}, "names": {"npc": {}, "object": {}}, "spawns": {"npc": {}, "object": {}}})
CM = {int(k): v for k, v in _cm["quests"].items()}
CM_NAMES = {k: {int(i): n for i, n in v.items()} for k, v in _cm["names"].items()}
CM_SPAWNS = {k: {int(i): n for i, n in v.items()} for k, v in _cm["spawns"].items()}
CM_ITEMS = {int(k): v for k, v in _cm["items"].items()}
CM_ITEMNAMES = {int(k): v for k, v in (_cm.get("itemnames") or {}).items()}
CM_NEXT = {}
for _qid, _q in CM.items():
    if _q["next"] and _q["next"] > 0:
        CM_NEXT.setdefault(_q["next"], []).append(_qid)

# ---------------------------------------------------------------------------
# NPCs on the map, each tied to the nearest flight master of each faction
# ---------------------------------------------------------------------------
HUB_INDEX = {fac: {hid: k + 1 for k, hid in enumerate(TR.order[fac])} for fac in ("A", "H")}
NPCS, NPC_AT, USED_MAPS = [], {}, set()
# Maps off the two continents an NPC keeps its map and place on, for the world map's icons (Zephras Isle, the Darkspear
# Islands)
ISLANDS = {2521, 2524}
# Of those, the open ones: a world map of its own that is no instance (Map.csv's InstanceType 0) and that a zone map
# (UiMap Type 3) is drawn over, as Zephras Isle (map 2991, uiMap 2521) is. The client places a point there as on a
# continent (C_Map.GetWorldPosFromMapPos gives 2991 and yards, by the same UiMapAssignment), so an NPC there gets that
# continent and its yards: no flight master stands there, so no hub, and the route walks there as on one land. Before
# 5.4.4 it got continent -1, as inside an instance, and the route, the arrow and the minutes left the isle out. The
# Darkspear Islands are a battleground (InstanceType 3) and keep -1
_UI_TYPE = {int(r["ID"]): int(r["Type"]) for r in csv.DictReader(open(os.path.join(REPO, "research", "wago", BUILD, "UiMap.csv")))}
_INSTANCE_TYPE = {int(r["ID"]): int(r["InstanceType"]) for r in csv.DictReader(open(os.path.join(REPO, "research", "wago", BUILD, "Map.csv")))}
OPEN_MAPS = {m["cont"] for uid, m in TR.maps.items() if m["cont"] not in (0, 1) and _UI_TYPE.get(uid) == 3 and _INSTANCE_TYPE.get(m["cont"]) == 0}


def add_npc(name, m, x, y, place=None):
    key = (name, m, round(x, 1), round(y, 1))
    if key in NPC_AT:
        rec = NPCS[NPC_AT[key] - 1]
        if place and len(rec) < 12:
            rec.append(place)
        return NPC_AT[key]
    rec = [name, m or 0, round(x, 1), round(y, 1), -1, 0, 0, 0, 0, 0, 0]
    w = TR.world(m, x, y) if m else None
    if w and w[0] in (0, 1):
        c, wx, wy = w
        rec[4:7] = [c, round(wx), round(wy)]
        for k, fac in ((7, "A"), (9, "H")):
            near = TR.nearest_hub(fac, c, wx, wy)
            if near:
                rec[k] = HUB_INDEX[fac][near[0]]
                rec[k + 1] = round(near[1] * DETOUR / RUN / 60.0, 1)
        USED_MAPS.add(m)
    elif w and w[0] in OPEN_MAPS:
        rec[4:7] = [w[0], round(w[1]), round(w[2])]
        USED_MAPS.add(m)
    elif m in ISLANDS:
        USED_MAPS.add(m)
    else:
        rec[1] = 0
    if place:
        rec.append(place)
    NPCS.append(rec)
    NPC_AT[key] = len(NPCS)
    return len(NPCS)


SOURCE = {}  # npc record index -> "wowhead" | "cmangos" | "game"
GAME_MOVED, GAME_FILLED, DISC_LINKED = [], [], []
GAME_AGREE = {}  # (kind, id) -> yards between the catalog's place and the game's
GAME_MOVE_YD = 25  # the player stands a few yards from the NPC (median 3.7 on 107 NPCs); farther than this, the catalog is off


def game_place(kind, i, m, x, y):
    """The catalog's place for an NPC, or the game's when players saw it more than GAME_MOVE_YD away."""
    gp = GAME_POS.get((kind, i))
    if not gp or not m:
        return m, x, y, False
    a, b = TR.world(m, x, y), TR.world(gp[1], gp[2], gp[3])
    if not a or not b:
        return m, x, y, False
    d = math.hypot(a[1] - b[1], a[2] - b[2]) if a[0] == b[0] else 99999
    if d <= GAME_MOVE_YD:
        GAME_AGREE[(kind, i)] = d
        return m, x, y, False
    GAME_MOVED.append((kind, i, int(round(d))))
    return gp[1], gp[2], gp[3], True


class FrameFix:
    """Forever redrew Mulgore, Eastern Plaguelands, Redridge and Stormwind. Wowhead gives some of
    their coordinates in the new frame and some in the old Classic one (every Stormwind NPC, Marshal
    Marris in Lakeshire). Read both ways; the reading that lands on the Classic database's spawn point
    wins; without a spawn, Stormwind reads Classic and the rest Forever. Stored in Forever's frame."""
    def __init__(self):
        self.fixed, self.kept = 0, 0

    def fix(self, kind, i, m, x, y):
        import math
        c, fx, fy = TR.world(m, x, y)
        _, ex, ey = TR.world(m, x, y, era=True)
        sp = CM_SPAWNS.get(kind, {}).get(i) or []
        classic = m == 1453
        if sp:
            df = min(math.hypot(s[1] - fx, s[2] - fy) for s in sp)
            de = min(math.hypot(s[1] - ex, s[2] - ey) for s in sp)
            if min(df, de) < 60:
                classic = de < df
        if not classic:
            self.kept += 1
            return x, y
        self.fixed += 1
        return TR.to_map(m, ex, ey)


FRAME = FrameFix()

OVERLAY = {2482, 2548, 2652}  # Mount Hyjal, the Riverglades, Shen'dralas: new in Forever, drawn over Classic zones
# Zone rectangles reach far into each other, so how deep a point lies inside one (its distance to the nearest edge,
# in percent of the map) decides. Checked against the CMaNGOS quest outlines, whose map Blizzard's data names: of the
# 2,488 that lie in more than one rectangle, these rules put 2,214 on Blizzard's map (89%); taking the quest's zone,
# giver's or ender's map whenever it holds the point, 2,176 (87%); the deepest map alone, 1,985 (80%)
EDGE = 3        # a preferred map takes a point at least this deep ...
DEPTH = 0.33    # ... and at least this share as deep as in the map it lies deepest in
CITY_EDGE = 10  # a city (a map well inside a bigger one) takes a point this deep
# the Classic WorldMapArea a CMaNGOS quest outline is drawn on (quest_poi.mapAreaId) -> uiMap (1411-1458 came in the
# same order; each area's outlines lie mostly on its map)
WMA_UIMAP = dict(zip((4, 9, 11, 15, 16, 17, 19, 20, 21, 22, 23, 24, 26, 27, 28, 29, 30, 32, 34, 35, 36, 37, 38, 39, 40, 41, 42,
                      43, 61, 81, 101, 121, 141, 161, 181, 182, 201, 241, 261, 281, 301, 321, 341, 362, 381, 382),
                     [1411, 1412, 1413] + list(range(1416, 1459))))


def spot_map(cont, wx, wy, prefer=(), overlay=(), sure=()):
    """The one map a world point is drawn on: (uiMap, x, y in percent). A map in sure that holds it (Blizzard's for a
    quest outline); else the first map in prefer that holds it deep enough (EDGE, DEPTH); else a city holding it
    CITY_EDGE deep; else the map it lies deepest in. The Forever-only maps over Classic zones take a point only when
    overlay names them."""
    cands = []
    for mid, m in TR.maps.items():
        if m["cont"] != cont or mid in (947, 1414, 1415, 1945) or not m["area"] or (mid in OVERLAY and mid not in overlay):
            continue
        if m["minx"] <= wx <= m["maxx"] and m["miny"] <= wy <= m["maxy"]:
            x, y = TR._pct(m, wx, wy)
            cands.append(((m["maxx"] - m["minx"]) * (m["maxy"] - m["miny"]), mid, x, y, min(x, 100 - x, y, 100 - y)))
    if not cands:
        return None
    for c in cands:
        if c[1] in sure:
            return c[1], c[2], c[3]
    for p in prefer:
        for c in cands:
            if c[1] == p:
                if c[4] >= EDGE and c[4] >= DEPTH * max([d[4] for d in cands if d is not c] or [0]):
                    return c[1], c[2], c[3]
    cands.sort()
    city = cands[0] if len(cands) > 1 and cands[0][0] <= 0.4 * cands[1][0] else None
    if city and city[4] >= CITY_EDGE:
        return city[1], city[2], city[3]
    best = max((c for c in cands if c is not city), key=lambda c: c[4])
    return best[1], best[2], best[3]


def npc_from(kind, i, zone=None, dungeon=False):
    """Wowhead Forever's position first, else the CMaNGOS spawn point. kind None tries an NPC, then an
    object (older reads didn't record which one ends a quest)."""
    if not i or kind not in ("npc", "object", None):
        return 0
    kinds = [kind] if kind else ["npc", "object"]
    for k in kinds:
        n = LOC.get(npc_key(k, i)) or {}
        if n.get("name") and n.get("coords"):
            m = TR.area_map.get(n.get("zone"))
            x, y = n["coords"][0][:2]
            if m in TR.redrawn:
                x, y = FRAME.fix(k, i, m, x, y)
            m, x, y, moved = game_place(k, i, m, x, y)
            idx = add_npc(n["name"], m, x, y)
            SOURCE.setdefault(idx, "game" if moved else "wowhead")
            return idx
    for k in kinds:
        spawns = CM_SPAWNS.get(k, {}).get(i)
        name = CM_NAMES.get(k, {}).get(i) or (LOC.get(npc_key(k, i)) or {}).get("name")
        if spawns and name:
            cont, wx, wy = spawns[0]
            hint = (TR.area_map.get(zone),) if zone else None
            loc = TR.locate(cont, wx, wy, hint)
            if loc and loc[0] in OVERLAY and loc[0] not in (hint or ()):
                # a Classic spawn never stands on a Forever-only map over Classic zones (Eridan Bluewind is in Felwood)
                at = spot_map(cont, wx, wy)
                loc = (at[0], round(at[1], 1), round(at[2], 1)) if at else loc
            if loc:
                m, x, y, moved = game_place(k, i, loc[0], loc[1], loc[2])
                idx = add_npc(name, m, x, y)
                SOURCE.setdefault(idx, "game" if moved else "cmangos")
                return idx
    for k in kinds:  # only players' games have seen it: a new Forever NPC
        gp = GAME_POS.get((k, i))
        if gp:
            name = CM_NAMES.get(k, {}).get(i) or (LOC.get(npc_key(k, i)) or {}).get("name") or gp[0]
            if name:
                idx = add_npc(name, gp[1], gp[2], gp[3])
                SOURCE.setdefault(idx, "game")
                GAME_FILLED.append((k, i))
                return idx
    if dungeon:  # a dungeon quest's NPC with no place on the two continents stands inside
        for k in kinds:
            name = CM_NAMES.get(k, {}).get(i) or (LOC.get(npc_key(k, i)) or {}).get("name")
            if name:
                idx = add_npc(name, 0, 0, 0)
                SOURCE.setdefault(idx, "cmangos")
                return idx
    return 0


def disc_npc(qid, which, zone=None, dungeon=False):
    """The giver ("from") or ender ("to") players' games showed for a quest the catalog has no NPC for."""
    for key in ((DISC.get("q") or {}).get(str(qid)) or {}).get(which) or []:
        if key[:1] in ("c", "o") and key[1:].isdigit():
            idx = npc_from("npc" if key[0] == "c" else "object", int(key[1:]), zone, dungeon)
            if idx:
                DISC_LINKED.append((qid, which, key))
                return idx
    return 0


NAME_INDEX = {}
for _kind in ("npc", "object"):
    for _i, _n in CM_NAMES.get(_kind, {}).items():
        if _n and CM_SPAWNS.get(_kind, {}).get(_i):
            NAME_INDEX.setdefault(_n.lower(), []).append((_kind, _i))
for _key, _v in LOC.items():
    if _v.get("name") and _v.get("coords"):
        _kind, _i = _key.split("/")
        NAME_INDEX.setdefault(_v["name"].lower(), []).append((_kind, int(_i)))
QTIPS = load("qtips.json", {}) or {}  # Wowhead's quest tooltips (npcloc.py --quests): names and text, no level or XP
TEXT_NAMED = []


def npc_by_text(qid, zone):
    """Wowhead links no NPC, but the objective names one: "bring them to Captain Stoutfist in Menethil"."""
    import re
    d = DET.get(qid) or {}
    # the page read's objective text, else Wowhead's tooltip for the quest (npcloc.py --quests), which carries the
    # same "... for Melisara in Tarren Mill" sentence
    text = d.get("obj") or (QTIPS.get(str(qid)) or {}).get("text") or ""
    title = LIST[qid]["name"]
    if text.startswith(title):
        text = text[len(title):]
    for m in re.finditer(r"\b(?:to|with|for|find|see|visit)\s+((?:[A-Z][\w'\-]*|of|the|de)(?:\s+(?:[A-Z][\w'\-]*|of|the|de)){0,5})", text):
        words = m.group(1).split()
        for n in range(len(words), 0, -1):
            cands = NAME_INDEX.get(" ".join(words[:n]).lower())
            if cands:
                hint = TR.area_map.get(zone) if zone else None
                for kind, i in cands:
                    idx = npc_from(kind, i, zone)
                    if idx:
                        TEXT_NAMED.append(qid)
                        return idx
    return 0


def kind_of(qid, i, which):
    """Is the quest's ender (or giver) with this id an NPC or an object? Wowhead's newer reads say;
    the Classic database says for Classic quests; None means try both."""
    d = DET.get(qid) or {}
    k = d.get("endType" if which == "ends" else "startType")
    if k in ("npc", "object", "item"):
        return k
    for kind, x in (CM.get(qid) or {}).get(which, []):
        if x == i:
            return kind
    return None


# ---------------------------------------------------------------------------
# chains: Wowhead's series box lists the other steps in order, the quest itself left out
# ---------------------------------------------------------------------------
def series(qid):
    mine = (DET.get(qid) or {}).get("chain") or []
    if not mine:
        return None
    for other in mine:
        theirs = (DET.get(other) or {}).get("chain") or []
        if qid not in theirs:
            continue
        fits = []
        for pos in range(len(mine) + 1):
            s = mine[:pos] + [qid] + mine[pos:]
            if [x for x in s if x != other] == theirs:
                fits.append(s)
        if len(fits) == 1:
            return fits[0]
        if fits:  # a two-step series fits both ways: the lower level goes first
            return min(fits, key=lambda s: [qlevel(x) if x in LIST else 99 for x in s])
    return None


def immediate_pre(qid):
    """Requirement groups: every group must be met, by any one quest in it."""
    s = series(qid)
    wh = s[s.index(qid) - 1] if s and s.index(qid) > 0 else None
    if qid in CM:
        if wh and wh not in CM:  # Forever put a new step in front of this one
            return [[wh]]
        q = CM[qid]
        groups = [[q["prev"]]] if q["prev"] and q["prev"] > 0 else []
        excl = {}
        for a in CM_NEXT.get(qid, []):
            x = CM[a]["excl"]
            if x and x > 0:
                excl.setdefault(x, []).append(a)
            elif [a] not in groups:
                groups.append([a])
        groups += [sorted(g) for g in excl.values()]
        return groups
    if not wh and qid in DISC_ONLY:
        # a quest only players' notes know: the step whose window opened the moment they handed in the one before,
        # when that one is in the catalog and no later in level (a reopened, already-offered quest fails this)
        groups = []
        for pair in (DISC.get("chain") or {}):
            a, _, b = pair.partition(">")
            if b == str(qid) and a.isdigit() and int(a) in LIST and int(a) != qid and qlevel(int(a)) <= LIST[qid]["level"] \
                    and (LIST[int(a)].get("reqlevel") or 1) <= (LIST[qid].get("reqlevel") or 1):
                groups.append([int(a)])
        return groups
    return [[wh]] if wh else []


def prereqs(qid, seen=None, depth=0):
    """Every step before this one, earliest first; a list inside is 'any one of these'."""
    if depth == 0 and qid in CURATED and CURATED[qid][2].get("pre"):
        return CURATED[qid][2]["pre"]
    seen = seen if seen is not None else {qid}
    out = []
    for g in immediate_pre(qid):
        if len(g) == 1:
            p = g[0]
            if p in seen or depth > 12:
                continue
            seen.add(p)
            out += prereqs(p, seen, depth + 1) + [p]
        else:
            out.append(g)
    if depth == 0:
        return out[-10:] or None
    return out


def chain_known(qid):
    """Do we know this quest's chain at all (a series box, or the Classic database)?"""
    return qid in CM or bool((DET.get(qid) or {}).get("chain")) or (qid in DISC_ONLY and bool(immediate_pre(qid)))


RACE_BIT = {1: 1, 2: 2, 3: 4, 4: 8, 5: 16, 6: 32, 7: 64, 8: 128}


def races(qid):
    """A race-limited quest's race mask, or None. Wowhead Forever first, the Classic database second."""
    info = (DET.get(qid) or {}).get("info") or ""
    ids = [int(x) for x in __import__("re").findall(r"\[race=(\d+)\]", info)]
    mask = 0
    for r in ids:
        mask |= RACE_BIT.get(r, 0)
    if not ids and qid in CM:
        mask = CM[qid]["races"] or 0
    if not mask or mask in (77, 178, 255):
        return None
    return mask


# ---------------------------------------------------------------------------
# categories: a dungeon, a zone, class quests or the rest
# ---------------------------------------------------------------------------
CATS, CAT_AT, OPEN_CAT = [], {}, {}
# a zone name back to its area, for the continent of a dungeon's parent zone (0 Eastern Kingdoms, 1 Kalimdor)
_AREA_BY_NAME = {}
for _aid, _name in AREAS.items():
    _row = AREA_ROW.get(_aid)
    if _row and int(_row["ContinentID"]) in (0, 1):
        _AREA_BY_NAME.setdefault(_name, int(_row["ContinentID"]))


def continent_of(where):
    """0 or 1 for a zone name on either continent; None for instances and the rest."""
    return _AREA_BY_NAME.get(where)


def cat_for(qid):
    q = LIST[qid]
    c2, area = q.get("category2"), q.get("category")
    if area == CRAFTING_AREA:
        # Forever's writ quests: handed in to whoever placed the order, nowhere on a map yet
        if "crafting" not in CAT_AT:
            CATS.append({"key": "crafting", "name": "Crafting orders", "where": "", "icon": icon("inv_misc_note_02")})
            CAT_AT["crafting"] = len(CATS)
        return CAT_AT["crafting"]
    if c2 == 2 or (q.get("type") == 81 and area in DUNGEON):
        key = "d%d" % area
        if key not in CAT_AT:
            lfg, where, ent = DUNGEON.get(area, ("dungeon", "", None))
            bgname = "interface/lfgframe/ui-lfg-background-%s" % lfg
            CATS.append({"key": key, "name": AREAS.get(area, "Dungeon"), "where": where, "dungeon": True, "cont": continent_of(where),
                         "icon": tex("interface/lfgframe/lfgicon-%s" % lfg),
                         "bg": tex(bgname) if (bgname + ".blp") in MAN else None,
                         "entrance": {"m": ent[0], "x": ent[1], "y": ent[2]} if ent else None})
            CAT_AT[key] = len(CATS)
        return CAT_AT[key]
    if c2 in (0, 1) and area in AREAS:
        key = "z%d" % area
        if key not in CAT_AT:
            CATS.append({"key": key, "name": AREAS[area], "where": "Kalimdor" if c2 == 1 else "Eastern Kingdoms", "cont": c2,
                         "icon": zone_icon(AREAS[area])})
            CAT_AT[key] = len(CATS)
        return CAT_AT[key]
    # a zone on an open map off the two continents (Zephras Isle: Wowhead files its quests under -2, no continent): a
    # zone card of its own, as a zone's, not "Other quests". Numbered after every other card (OPEN_CAT, below the
    # records), so the cards before keep their numbers
    row = AREA_ROW.get(area) if area in AREAS else None
    if c2 != 4 and row and int(row["ContinentID"]) in OPEN_MAPS:
        key = "z%d" % area
        if key in CAT_AT:
            return CAT_AT[key]
        OPEN_CAT[key] = area
        return key
    key = "class" if c2 == 4 or q.get("reqclass") else "misc"
    if key not in CAT_AT:
        CATS.append({"key": key, "name": "Class quests" if key == "class" else "Other quests", "where": "",
                     "icon": icon("inv_misc_book_09" if key == "class" else "inv_misc_note_06")})
        CAT_AT[key] = len(CATS)
    return CAT_AT[key]


# ---------------------------------------------------------------------------
# records
# ---------------------------------------------------------------------------
Q, QN, QITEM, QICON, TIPS, PRE, BAGQ, FOLLOW, RACE, EXCL_GROUPS = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
DMULT = {}
DMULT_POST = {}  # the category's reads were all made on or after the cut: the value is already post-cut
_seen_mult, _seen_post = {}, {}
for _qid in IDS:
    _q, _d = LIST[_qid], DET.get(_qid) or {}
    if (_q.get("category2") == 2 or _q.get("type") == 81) and _d.get("mult") is not None:
        _seen_mult.setdefault(cat_for(_qid), []).append(_d["mult"])
        _seen_post.setdefault(cat_for(_qid), []).append((_d.get("read") or "") >= NERF_DATE)
for _cat, _ms in _seen_mult.items():
    _top = max(set(_ms), key=_ms.count)
    if len(_ms) >= 2 and _ms.count(_top) >= 0.6 * len(_ms) and _top != 1:
        DMULT[_cat] = _top
        DMULT_POST[_cat] = all(_seen_post[_cat])
FROM_FC, DISAGREE, SEEN_OK, SEEN_FIX, SEEN_FILL, SEEN_NEAR = [], [], [], [], [], []
REQ = {}
TURNH = {}
unconfirmed = 0
for qid in IDS:
    q, d = LIST[qid], DET.get(qid) or {}
    cur = CURATED.get(qid)
    extra = cur[2] if cur else {}
    zone = q.get("category") if q.get("category2") in (0, 1) else None
    cmq = CM.get(qid) or {}
    dungeon = q.get("category2") == 2 or q.get("type") == 81
    turn = add_npc(*extra["turn"]) if extra.get("turn") else npc_from(kind_of(qid, d.get("endId"), "ends"), d.get("endId"), zone, dungeon)
    if not turn:
        for kind, i in cmq.get("ends", []):
            turn = npc_from(kind, i, zone, dungeon)
            if turn:
                break
    if not turn:
        turn = npc_by_text(qid, zone)
    if not turn:
        turn = disc_npc(qid, "to", zone, dungeon)
    if qid in GAME_ENDER_A:  # the game showed the Alliance a different ender; Wowhead's stays the Horde one
        ta = npc_from(GAME_ENDER_A[qid][0], GAME_ENDER_A[qid][1], zone, dungeon)
        if ta:
            if turn and turn != ta:
                TURNH[qid] = turn
            turn = ta
    ends = d.get("ends") or []
    by_fac = {f: (k, i) for f, k, i in ends if f}
    if "A" in by_fac and "H" in by_fac and by_fac["A"] != by_fac["H"]:
        ta = npc_from(by_fac["A"][0], by_fac["A"][1], zone, dungeon)
        th = npc_from(by_fac["H"][0], by_fac["H"][1], zone, dungeon)
        if ta:
            turn = ta
        if th:
            TURNH[qid] = th
    sk = kind_of(qid, d.get("startId"), "starts")
    give = add_npc(*extra["give"]) if extra.get("give") else (npc_from(sk, d.get("startId"), zone, dungeon) if sk != "item" else 0)
    if not give:
        for kind, i in cmq.get("starts", []):
            if kind != "item":
                give = npc_from(kind, i, zone, dungeon)
                if give:
                    break
    if not give and sk != "item" and not any(k == "item" for k, _ in cmq.get("starts", [])):
        give = disc_npc(qid, "from", zone, dungeon)
    flags = 0
    if q.get("category2") == 2 or q.get("type") == 81:
        flags |= 1
    if q.get("type") == 1:
        flags |= 2
    if d.get("startType") == "item" or any(k == "item" for k, _ in cmq.get("starts", [])) or (extra.get("bag") and len(extra["bag"]) == 2):
        flags |= 4
    if qid in WRIT:
        flags |= 4 | 131072  # a writ's turn-in: starts from the writ, for the reward finders alone
    mult = d.get("mult")
    base = base_xp(qid)
    if (not d or mult is None) and FC.get(qid) and base:
        mult = round(FC[qid] / base, 2)  # ForeverChanges' Forever XP over the Classic base
        FROM_FC.append(qid)
    elif mult is not None and FC.get(qid) and base:
        f = round_xp(lua_round(base * mult))
        if abs(f - FC[qid]) > max(60, FC[qid] * 0.02):
            DISAGREE.append((qid, f, FC[qid]))
    postcut = (d.get("read") or "") >= NERF_DATE  # a page read after the cut already shows the new multiplier
    if (not d and mult is None or mult is None) and qid in WRIT:
        mult = 1  # (no XP to multiply)
    elif not d and mult is None or mult is None:
        flags |= 8
        mult = 1
        unconfirmed += 1
        if (flags & 1) and DMULT.get(cat_for(qid)):
            mult = DMULT[cat_for(qid)]
            postcut = DMULT_POST.get(cat_for(qid), False)
            flags |= 32
    if qid in CLASSIC:
        flags |= 16
    if not base:
        flags |= 64
    if sod_leftover(qid):
        flags |= 128
    if re.match(r"^(WANTED|Wanted)\b", q.get("name") or ""):
        flags |= 1024  # a wanted poster
    if ((CM.get(qid) or {}).get("flags") or 0) & 2:
        flags |= 2048  # an escort (the Classic database's party-accept flag)
    if ((CM.get(qid) or {}).get("special") or 0) & 1:
        flags |= 4096  # repeatable: never suggested (the Classic seed drops these; Wowhead-listed ones slipped through)
    if NERF != 1 and mult and mult > 1 and not postcut:
        # the 2026-10-01 cut, computed until Wowhead's pages show the new numbers. Hand-ins on 2026-10-02 paid the
        # cut value on every multiplied quest, dungeon-typed or not (The Test of Righteousness, Chol'aruk the Ravener).
        # A page read on or after the cut (det "read" date) already shows the new multiplier: the Excavation Site
        # quests read 1.95 and 2.2 on 2026-10-02 while the old pages still said 2.9 and 3.4.
        mult = nerfed(mult)
        flags |= 256
    seen = seen_full(qid, qlevel(qid))
    if seen:
        if base:
            computed = round_xp(lua_round(base * mult))
            # within 5% (or 15 XP) the game agrees (an odd bonus on the player's side); only a real difference
            # replaces the number, and a near miss is kept as read but marked (flag 1024) so the tooltip is honest
            if abs(seen - computed) <= max(15, computed * 0.05):
                SEEN_OK.append(qid)
                if seen != computed:
                    SEEN_NEAR.append((qid, computed, seen))
                    flags |= 8192
            else:
                SEEN_FIX.append((qid, computed, seen))
                mult = round(seen / base, 4)
                if flags & 8:
                    unconfirmed -= 1
                flags &= ~(8 | 32)
            flags |= 512
        else:
            base, mult = seen, 1  # XP the catalog never had: the game's number is the base
            flags = (flags | 512) & ~64
            SEEN_FILL.append(qid)
    if qid in DISC_ONLY:
        # from players' notes alone: the game's own number when they read it, otherwise unknown
        mult = 1
        flags = (flags | 16384) & ~(16 | 32 | 256)
        if base:
            if flags & 8:
                unconfirmed -= 1
            flags = (flags | 512) & ~(8 | 64)
    if qid in REQ_STATED:
        flags |= 32768  # the required level is Blizzard's, not the lowest anyone took it at
    side = {1: 1, 2: 2}.get(q.get("side"), 0)
    Q[qid] = [qlevel(qid), q.get("reqlevel") or 1, side, base, mult, turn, give, cat_for(qid), q.get("reqclass") or 0, flags]
    QN[qid] = q["name"]
    items = [x[0] for x in (q.get("itemrewards") or []) + (q.get("itemchoices") or []) if isinstance(x, list)]
    if items:
        QITEM[qid] = items[0]
    if cur and cur[0]:
        QICON[qid] = icon(cur[0])
        TIPS[qid] = cur[1]
    p = prereqs(qid)
    if p:
        PRE[qid] = p
    if extra.get("bag"):
        b = extra["bag"]
        BAGQ[qid] = [b[0], b[1], 2 if len(b) > 2 else 1]
    elif d.get("startType") == "item" and d.get("startId"):
        BAGQ[qid] = [d["startId"], 1, 0, d.get("start") or (CM_ITEMS.get(d["startId"]) or {}).get("name")]
    elif qid in WRIT:
        BAGQ[qid] = [WRIT[qid][0], 1, 0, WRIT[qid][1]]
    else:
        for kind, i in cmq.get("starts", []):
            if kind == "item":
                BAGQ[qid] = [i, 1, 0, (CM_ITEMS.get(i) or {}).get("name")]
                break
    rm = races(qid)
    if rm:
        RACE[qid] = rm
    if cmq.get("items"):  # what it asks you to bring: counted in bags and bank
        REQ[qid] = [[i, n, CM_ITEMNAMES.get(i) or ""] for i, n in cmq["items"]]
    if cmq.get("excl") and cmq["excl"] > 0:
        EXCL_GROUPS.setdefault(cmq["excl"], []).append(qid)
    if extra.get("follow"):
        FOLLOW[qid] = extra["follow"]
# the zone cards of open maps off the two continents (cat_for), last: no continent of the two, no "where"
for _key in sorted(OPEN_CAT):
    _area = OPEN_CAT[_key]
    CATS.append({"key": _key, "name": AREAS[_area], "where": "", "icon": zone_icon(AREAS[_area])})
    CAT_AT[_key] = len(CATS)
for _qid, _rec in Q.items():
    if isinstance(_rec[7], str):
        _rec[7] = CAT_AT[_rec[7]]
# the steps that come after a quest (for "advance the chain")
NEXT = {}
for qid in IDS:
    for g in immediate_pre(qid):
        for p in g:
            if p in Q:
                NEXT.setdefault(p, []).append(qid)
for qid, cur in CURATED.items():
    pre = cur[2].get("pre") if cur and cur[2] else None
    if pre and qid in Q:
        last = pre[-1]
        for p in (last if isinstance(last, list) else [last]):
            if p in Q and qid not in NEXT.get(p, []):
                NEXT.setdefault(p, []).append(qid)


# a delivery you are handed when you hand in its first step, done on the spot: part of the route
def instant(qid):
    c = CM.get(qid)
    return bool(c) and c["objectives"] == 0 and not (c["special"] & 2) and not any(k == "item" for k, _ in c["starts"]) \
        and not c.get("rep") and qid not in BAGQ


def ender_ids(qid):
    d = DET.get(qid) or {}
    out = {(d.get("endType") or "npc", d.get("endId"))} if d.get("endId") else set()
    out |= {tuple(x) for x in (CM.get(qid) or {}).get("ends", [])}
    return out


def starter_ids(qid):
    d = DET.get(qid) or {}
    out = {(d.get("startType") or "npc", d.get("startId"))} if d.get("startId") else set()
    out |= {tuple(x) for x in (CM.get(qid) or {}).get("starts", [])}
    return out


for qid in IDS:
    if qid in FOLLOW or not instant(qid) or not Q[qid][5]:
        continue
    groups = immediate_pre(qid)
    if len(groups) != 1 or len(groups[0]) != 1:
        continue
    parent = groups[0][0]
    if parent in Q and ender_ids(parent) & starter_ids(qid):
        FOLLOW[qid] = parent
EXCL = {}
for members in EXCL_GROUPS.values():
    if len(members) > 1:
        for m in members:
            EXCL[m] = [x for x in members if x != m]
BIT_EXCL = []  # quests the shared completion bits rule out against quests the Classic database didn't
for members in BIT_GROUPS.values():
    for m in members:
        have = EXCL.get(m, [])
        add = [x for x in members if x != m and x not in have]
        if add:
            EXCL[m] = have + add
            BIT_EXCL.append(m)
# what Blizzard's 8 October notes changed that nobody has read since: Elixir of Pain's XP, and the level of Forever's
# new quests whose giver or ender stands around Bandarion Keep and Shadowvale
for qid in IDS:
    if qid in CHANGED_1008:
        NOTE.setdefault(qid, CHANGED_1008[qid])
    if qid in CM:
        continue
    for i in (Q[qid][5], Q[qid][6]):
        n = NPCS[i - 1] if i else None
        if n and n[1] == BANDARION[0] and math.hypot(n[2] - BANDARION[1], n[3] - BANDARION[2]) <= BANDARION[3]:
            NOTE.setdefault(qid, TIRISFAL_NOTE)
for qid in list(STEPNAME) + [p for ps in PRE.values() for p in ps for p in (p if isinstance(p, list) else [p])] + \
        [x for xs in EXCL.values() for x in xs] + [x for xs in NEXT.values() for x in xs]:
    if qid not in QN and qid in LIST:
        QN[qid] = LIST[qid]["name"]


# ---------------------------------------------------------------------------
# Lua
# ---------------------------------------------------------------------------
def lua(v):
    if v is None: return "nil"
    if v is True: return "true"
    if v is False: return "false"
    if isinstance(v, int): return str(v)
    if isinstance(v, float):
        return str(int(v)) if v == int(v) else ("%.4f" % v).rstrip("0").rstrip(".")  # 4 decimals, as nerfed() rounds
    if isinstance(v, str): return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, list): return "{" + ",".join(lua(x) for x in v) + "}"
    if isinstance(v, dict):
        def key(k):
            if isinstance(k, int): return "[%d]" % k
            return k if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k) else "[" + lua(k) + "]"
        return "{" + ",".join("%s=%s" % (key(k), lua(x)) for k, x in v.items() if x is not None) + "}"
    raise TypeError(v)


def keyed(d):
    return "{" + ",".join("[%d]=%s" % (k, lua(v)) for k, v in sorted(d.items())) + "}"


ALPHA = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+/"


def enc(v):
    n = max(0, min(4095, int(round(v * 10))))
    return ALPHA[n // 64] + ALPHA[n % 64]


KIND = {"flight": "f", "boat": "b", "tram": "t", "zeppelin": "z", "portal": "p", "foot": "w"}

lines = ["-- Generated by gen_data.py from Wowhead Forever quest data (read %s), the Forever beta client" % READ,
         "-- build %s, and the CMaNGOS Classic database (github.com/cmangos/classic-db, GPL-3.0) for quest" % BUILD,
         "-- chains, quest givers, spawn points and the rewards no Forever source lists yet. QuestBank is free",
         "-- software under the GPL-3.0 (LICENSE.txt).",
         "-- Edit the generator, not this file.",
         "local _, QB = ...", "local D = {}", "QB.Data = D", ""]
lines.append('D.BUILD = "%s"' % BUILD)
lines.append('D.READ = "%s"' % READ)
if NERF != 1:
    lines.append('D.NERF = { factor = %s, date = "%s", build = %d }  -- dungeon-quest extra XP cut by Blizzard on this date (first on this client build); multipliers above 1 are computed from the pre-cut reads unless flag 512 says the game confirmed the number' % (NERF, NERF_DATE, NERF_BUILD))
TO_NEXT = [400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400,
           21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800, 54500, 58600, 62800,
           67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200,
           147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800]
assert len(TO_NEXT) == 59 and sum(TO_NEXT) == 4084700, "the Classic curve, 1 to 60 (the Forever client's GameTable)"
lines.append("D.TO_NEXT = " + lua(TO_NEXT))
T = {k: tex(v) for k, v in {
    "bg": "interface/dialogframe/ui-dialogbox-background-dark", "border": "interface/dialogframe/ui-dialogbox-gold-border",
    "header": "interface/dialogframe/ui-dialogbox-gold-header", "parchH": "interface/achievementframe/ui-achievement-parchment-horizontal",
    "tipBorder": "interface/tooltips/ui-tooltip-border", "tipBg": "interface/tooltips/ui-tooltip-background",
    "tabOn": "interface/paperdollinfoframe/ui-character-activetab", "tabOff": "interface/paperdollinfoframe/ui-character-inactivetab",
    "tabHi": "interface/paperdollinfoframe/ui-character-tab-highlight", "slot": "interface/buttons/ui-quickslot2",
    "iconFrame": "interface/common/whiteiconframe", "hilite": "interface/buttons/buttonhilight-square",
    "bar": "interface/targetingframe/ui-statusbar", "ready": "interface/raidframe/readycheck-ready",
    "notready": "interface/raidframe/readycheck-notready", "waiting": "interface/raidframe/readycheck-waiting",
    "ring": "interface/minimap/minimap-trackingborder", "questAvail": "interface/gossipframe/availablequesticon",
    "sideNow": "interface/icons/inv_misc_map_01", "sideLog": "interface/icons/inv_misc_book_09", "sideAvail": "interface/icons/inv_scroll_03",
    "sideRoute": "interface/icons/inv_misc_map02", "sideParty": "interface/icons/inv_misc_groupneedmore", "sideJournal": "interface/icons/inv_misc_key_11",
    "sideSettings": "interface/icons/inv_misc_gear_01", "sideMap": "interface/icons/inv_misc_map09", "sideTimers": "interface/icons/inv_misc_pocketwatch_01",
    "questActive": "interface/gossipframe/activequesticon", "taxiY": "interface/taxiframe/ui-taxi-icon-yellow",
    "taxiG": "interface/taxiframe/ui-taxi-icon-green", "taxiGray": "interface/taxiframe/ui-taxi-icon-gray",
    "mapPin": "interface/worldmap/ui-worldmap-questicon", "book": "interface/questframe/ui-questlog-bookicon",
    "rowHi": "interface/questframe/ui-questtitlehighlight", "minimapBg": "interface/minimap/ui-minimap-background",
    "minimapHi": "interface/minimap/ui-minimap-zoombutton-highlight", "knob": "interface/buttons/ui-scrollbar-knob",
    "classes": "interface/glues/charactercreate/ui-charactercreate-classes", "leader": "interface/groupframe/ui-group-leadericon",
    "ping": "interface/minimap/ui-minimap-ping-center", "dotGreen": "interface/common/indicator-green",
    "dotGray": "interface/common/indicator-gray", "dotYellow": "interface/common/indicator-yellow",
    "dotRed": "interface/common/indicator-red",
    "upgrade": "interface/containerframe/bags",  # the bags' green upgrade arrow (atlas bags-greenarrow)
    "questArrow": "interface/minimap/minimap-questarrow",
    "taxiHi": "interface/taxiframe/ui-taxi-icon-highlight",  # the taxi map's glow on the flight master to pick
}.items()}
T.update({"hearth": icon("inv_misc_rune_01"), "mount": icon("ability_mount_ridinghorse"), "foot": icon("ability_rogue_sprint"),
          "sleep": 133662, "hourglass": icon("inv_misc_pocketwatch_01"), "gryphon": icon("ability_mount_gryphon_01"),
          "wyvern": icon("ability_mount_wyvern_01"), "boat": icon("inv_misc_anchor"), "tram": icon("inv_gizmo_02"),
          "zeppelin": icon("inv_zeppelinmount"), "portal": icon("spell_arcane_portaldarnassus"),
          "unknown": icon("inv_misc_questionmark"), "questGeneric": icon("inv_misc_note_01"), "map": icon("inv_misc_map_01"),
          "party": icon("inv_misc_groupneedmore"), "rally": icon("ability_warrior_rallyingcry"), "letter": icon("inv_letter_15"),
          "note": icon("inv_misc_note_06"), "start": icon("inv_misc_coin_01"),
          "bag": icon("inv_misc_bag_08")})  # the Quest Log slot's reward mark until the game sends the item's icon
# the Gear page: its sidebar icon, and the character pane's own slot backgrounds (the paper doll's art; the back
# slot shares the chest's, as the game's paper doll has it)
T.update({"sideGear": icon("inv_chest_plate04"), "slotHead": tex("Interface/PaperDoll/UI-PaperDoll-Slot-Head"),
          "slotNeck": tex("Interface/PaperDoll/UI-PaperDoll-Slot-Neck"), "slotShoulder": tex("Interface/PaperDoll/UI-PaperDoll-Slot-Shoulder"),
          "slotChest": tex("Interface/PaperDoll/UI-PaperDoll-Slot-Chest"), "slotWaist": tex("Interface/PaperDoll/UI-PaperDoll-Slot-Waist"),
          "slotLegs": tex("Interface/PaperDoll/UI-PaperDoll-Slot-Legs"), "slotFeet": tex("Interface/PaperDoll/UI-PaperDoll-Slot-Feet"),
          "slotWrist": tex("Interface/PaperDoll/UI-PaperDoll-Slot-Wrists"), "slotHands": tex("Interface/PaperDoll/UI-PaperDoll-Slot-Hands"),
          "slotFinger": tex("Interface/PaperDoll/UI-PaperDoll-Slot-Finger"), "slotTrinket": tex("Interface/PaperDoll/UI-PaperDoll-Slot-Trinket"),
          "slotMainHand": tex("Interface/PaperDoll/UI-PaperDoll-Slot-MainHand"), "slotOffHand": tex("Interface/PaperDoll/UI-PaperDoll-Slot-SecondaryHand"),
          "slotRanged": tex("Interface/PaperDoll/UI-PaperDoll-Slot-Ranged")})
lines.append("D.TEX = " + lua(T))
# a zone card's art: the middle tile of the zone's own map (UiMapAssignment: area -> map; UiMapXMapArt and
# UiMapArtTile: the map's tiles by row and column), as the dungeon cards carry the LFG background
_AREA_MAP = {}
for r in csv.DictReader(open(os.path.join(REPO, "research", "wago", BUILD, "UiMapAssignment.csv"))):
    if r["OrderIndex"] == "0" and r["AreaID"] not in ("0", ""): _AREA_MAP.setdefault(int(r["AreaID"]), int(r["UiMapID"]))
_MAP_ART = {int(r["UiMapID"]): r["UiMapArtID"] for r in csv.DictReader(open(os.path.join(REPO, "research", "wago", BUILD, "UiMapXMapArt.csv")))}
_TILES = {}
for r in csv.DictReader(open(os.path.join(REPO, "research", "wago", BUILD, "UiMapArtTile.csv"))):
    if r["LayerIndex"] == "0": _TILES[(r["UiMapArtID"], int(r["RowIndex"]), int(r["ColIndex"]))] = int(r["FileDataID"])
# a zone's picture: the painted art of the zone-choice board ("answer-warboard-classic-<zone>"), and its
# achievement icon; cities and small places have the icon only
_WB = {k[len("interface/questionframe/answer-warboard-classic-"):-4]: int(v) for k, v in MAN.items() if k.startswith("interface/questionframe/answer-warboard-classic-")}
_ZI = {k[len("interface/icons/achievement_zone_"):-4]: int(v) for k, v in MAN.items() if k.startswith("interface/icons/achievement_zone_")}
_WB_ALIAS = {"thebarrens": "northernbarrens", "stranglethornvale": "northernstranglethorn", "thehinterlands": "hinterlands"}
_ZI_ALIAS = {"thebarrens": "barrens", "stranglethornvale": "stranglethorn", "thehinterlands": "hinterlands", "stormwindcity": "stormwind",
             "ungorocrater": "ungorocrater", "alteracmountains": "alteracmountains"}
def _norm(n): return re.sub(r"[^a-z]", "", n.lower())
for c in CATS:
    if c["key"].startswith("z"):
        n = _norm(c["name"])
        wb = _WB.get(_WB_ALIAS.get(n, n))
        if wb: c["img"] = wb
        zi = None
        for cand in (_ZI_ALIAS.get(n, n), n.replace("the", "", 1)):
            zi = _ZI.get(cand) or _ZI.get(cand + "_01")
            if zi: break
        if zi: c["zi"] = zi
for c in CATS:
    if c["key"].startswith("z"):
        m = _AREA_MAP.get(int(c["key"][1:]))
        art = m and _MAP_ART.get(m)
        tile = art and (_TILES.get((art, 1, 1)) or _TILES.get((art, 1, 2)) or _TILES.get((art, 0, 1)))
        if tile: c["art"] = tile
lines.append("D.CAT = {\n" + "\n".join("  " + lua(c) + "," for c in CATS) + "\n}")


# The dungeons' maps (DungeonMap.lua): Blizzard's own floor art, which the client ships for every Classic dungeon and
# the City of Dalaran under Interface/WorldMap/<folder>/<folder><floor>_<tile>.blp, twelve 256-px tiles a floor in
# four columns of three; and the bosses with the loot the site records for them (codex/loot.json: ForeverChanges,
# wowtbc.gg and players' games), by item id: the client names the items. D.DMAP[cat key] = { art, floors = { {12
# file ids}, ... }, mid = map id, cover, coverKind, defaultFace, bosses = { { n = name, k = boss|rare|trash|object|quest,
# w = wing or nil, i = { item ids }, o = encounter order, p = journal art, d = display id, a = achievement icon,
# c = NPC id, l = level, f, x, y = where it stands }, ... } }
DMAP_ART = {"d1581": "TheDeadmines", "d717": "TheStockade", "d718": "WailingCaverns", "d719": "BlackFathomDeeps",
            "d209": "ShadowfangKeep", "d796": "ScarletMonastery", "d491": "RazorfenKraul", "d1337": "Uldaman",
            "d721": "Gnomeregan", "d2437": "Ragefire", "d722": "RazorfenDowns", "d16611": "RuinsofLordaeronScenario",
            "d1417": "TheTempleofAtalhakkar", "d1584": "BlackrockDepths", "d1583": "BlackrockSpire", "d2057": "Scholomance",
            "d2017": "Stratholme", "d2557": "DireMaul", "d2100": "Maraudon", "d16544": "DalaranCity"}
DMAP_LOOT = {"The Deadmines": "d1581", "The Stockade": "d717", "Wailing Caverns": "d718", "Blackfathom Deeps": "d719",
             "Shadowfang Keep": "d209", "Scarlet Monastery: Graveyard": "d796", "Scarlet Monastery: Library": "d796",
             "Scarlet Monastery: Armory": "d796", "Scarlet Monastery: Cathedral": "d796", "Razorfen Kraul": "d491",
             "Uldaman": "d1337", "Gnomeregan": "d721", "Ragefire Chasm": "d2437", "Razorfen Downs": "d722",
             "Ruins of Lordaeron": "d16611", "The Temple of Atal'Hakkar": "d1417", "Blackrock Depths": "d1584",
             "Blackrock Spire: Lower": "d1583", "Blackrock Spire: Upper": "d1583", "Scholomance": "d2057", "Stratholme": "d2017",
             "Dire Maul: East": "d2557", "Dire Maul: North": "d2557", "Dire Maul: West": "d2557", "Maraudon": "d2100",
             "City of Dalaran": "d16544", "Excavation Site: Wetlands": "d16732", "Hall of Thanes": "d16919"}
_LOOT_EARLY = load_json(os.path.join(REPO, "codex", "loot.json")) or {}
DMAP = {}
for key, folder in DMAP_ART.items():
    floors = []
    f = 1
    while True:
        ids = []
        for t in range(1, 13):
            k = "interface/worldmap/%s/%s%d_%d.blp" % (folder.lower(), folder.lower(), f, t)
            if k not in MAN:
                break
            ids.append(int(MAN[k]))
        if len(ids) < 12:
            break
        floors.append(ids)
        f += 1
    if floors:
        DMAP[key] = {"art": folder, "floors": floors, "bosses": []}
# the Encounter Journal's own art, which the client still ships: a cover for each dungeon
# (UI-EJ-DUNGEONBUTTON-<name>, else UI-EJ-LOREBG-<name>, else UI-EJ-BACKGROUND-<name>) and a portrait for each boss
# the journal once knew (UI-EJ-BOSS-<name>). Forever's new dungeons and bosses have neither: the addon shows the
# dungeon's LFG background and the journal's default boss face instead
EJ_COVER = {"d1581": "Deadmines", "d717": "TheStockade", "d718": "WailingCaverns", "d719": "BlackfathomDeeps",
            "d209": "ShadowFangKeep", "d796": "ScarletMonastery", "d491": "RazorfenKraul", "d1337": "Uldaman",
            "d721": "Gnomeregan", "d2437": "RagefireChasm", "d722": "RazorfenDowns", "d1417": "SunkenTemple",
            "d1584": "BlackrockDepths", "d1583": "BlackrockSpire", "d2057": "Scholomance", "d2017": "Stratholme",
            "d2557": "DireMaul", "d2100": "Maraudon", "d1176": "ZulFarrak"}
def ej_cover(name):
    for kind in ("DUNGEONBUTTON", "LOREBG", "BACKGROUND"):
        k = ("interface/encounterjournal/ui-ej-%s-%s.blp" % (kind, name)).lower()
        if k in MAN:
            return int(MAN[k]), kind
    return None, None
# a boss's name as the journal's art and the client's encounters spell it: letters and digits alone ("Rhahk'Zor" is
# RhahkZor), the Ring of Law's prefix off (its six fighters are listed as "Ring of Law: <name>")
RING = "Ring of Law: "
def _unring(n): return n[len(RING):] if n.startswith(RING) else n
def _bn(n): return re.sub(r"[^a-z0-9]", "", _unring(n).lower())
EJ_BOSS = {}
for k in MAN:
    if k.startswith("interface/encounterjournal/ui-ej-boss-"):
        EJ_BOSS[k[len("interface/encounterjournal/ui-ej-boss-"):-4]] = int(MAN[k])
EJ_BOSS_DEFAULT = EJ_BOSS.get("default")
EJ_NORM = {}
for k, v in EJ_BOSS.items():
    EJ_NORM.setdefault(_bn(k), v)
# bosses the journal's art knows by a later name
EJ_ALIAS = {"Emperor Dagran Thaurissan": "emperorthaurissan", "Baron Rivendare": "lordauriusrivendare",
            "Archivist Galford": "instructorgalford", "Cannon Master Willey": "willeyhopebreaker", "Malor the Zealous": "commandermalor"}
def ej_portrait(name):
    """The journal's art for a boss: by its exact name, else by letters and digits alone (or its later name)."""
    return EJ_BOSS.get(name.lower()) or EJ_NORM.get(EJ_ALIAS.get(name) or _bn(name))
# an achievement's boss icon (Achievement_Boss_<name>), for an entry with neither the journal's art nor a model
ACH_BOSS = {}
for k in MAN:
    if k.startswith("interface/icons/achievement_boss_"):
        ACH_BOSS.setdefault(_bn(k[len("interface/icons/achievement_boss_"):-4]), int(MAN[k]))
# kinds the loot file has wrong: two chests filed as bosses, and the Guzzler (the Grim Guzzler's event; no creature
# has the name), which the journal calls an event as it does the bosses a quest summons
KIND_FIX = {"Dark Coffer": "object", "Chest of The Seven": "object", "Guzzler": "quest"}
for d in _LOOT_EARLY.get("dungeons", []):
    key = DMAP_LOOT.get(d.get("name"))
    if not key:
        continue
    entry = DMAP.setdefault(key, {"art": None, "floors": [], "bosses": []})
    wing = d["name"].split(": ", 1)[1] if ": " in d["name"] and key in ("d796", "d1583", "d2557") else None
    lv = d.get("levels")
    if isinstance(lv, list) and len(lv) == 2 and all(isinstance(x, int) for x in lv):
        cur = entry.get("lv")
        entry["lv"] = [min(lv[0], cur[0]), max(lv[1], cur[1])] if cur else lv
    for b in d.get("bosses", []):
        items = [int(i) for i in (b.get("items") or []) if str(i).isdigit()][:12]
        boss = {"n": b["name"], "k": KIND_FIX.get(b["name"]) or b.get("kind") or "boss", "w": wing, "i": items}
        pt = ej_portrait(b["name"])
        if pt: boss["p"] = pt
        if b.get("level"): boss["l"] = b["level"]
        entry["bosses"].append(boss)
# where each boss stands on the floor art (boss_spots.py: MoP Classic's map rectangles for the very same art files and
# the Classic database's spawns): b.f the floor, b.x and b.y 0-1 across the art; summoned and event bosses have none.
# b.d: the boss's creature display id, for the client's own rendered portrait
_SPOTS = load("boss_spots.json", {}) or {}
for key, entry in DMAP.items():
    for boss in entry["bosses"]:
        if (_SPOTS.get("models") or {}).get(boss["n"]):
            boss["d"] = _SPOTS["models"][boss["n"]]
        sp = ((_SPOTS.get("spots") or {}).get(key) or {}).get(boss["n"])
        if sp and 0.02 <= sp[1] <= 0.98 and 0.04 <= sp[2] <= 0.98 and sp[0] <= len(entry["floors"]):
            boss["f"], boss["x"], boss["y"] = sp[0], round(sp[1], 3), round(sp[2], 3)
# Forever's own dungeons, which the Classic database has never heard of: each boss's NPC id (b.c, for the loot panel's
# model) and display id (b.d, in place of a Classic model of the same name) from Wowhead Forever (forever_npcs.py).
# A display id the client's CreatureDisplayInfo lacks can't be drawn and is left out. ForeverChanges' boss pictures,
# named by display id, are a cross-check only: printed where they differ, never copied (the 2026-10-08 terms decision)
FOREVER_DMAP = {"d16544": "city-of-dalaran", "d16732": "excavation-site", "d16611": "ruins-of-lordaeron", "d16919": "hall-of-thanes"}
_FNPC = load("forever_npcs.json", {}) or {}
_CDI = {int(r["ID"]) for r in csv.DictReader(open(os.path.join(REPO, "research", "wago", BUILD, "CreatureDisplayInfo.csv")))}
_FC_FACE, _fnpc_off, _fc_differs, _fc_agrees = {}, [], [], 0
for key, slug in FOREVER_DMAP.items():
    p = os.path.join(RAW, "fc", slug + ".html")
    for did, name in re.findall(r'/wow-ui/bosses/(\d+)\.webp\)" aria-hidden="true"></span><span>([^<]+)</span>', open(p).read() if os.path.exists(p) else ""):
        _FC_FACE[(key, html.unescape(name))] = int(did)
for key in FOREVER_DMAP:
    for boss in DMAP.get(key, {}).get("bosses", []):
        wh = _FNPC.get(boss["n"])
        if not wh:
            continue
        boss["c"] = wh["npc"]
        if wh["display"] not in _CDI:
            _fnpc_off.append("%s %d" % (boss["n"], wh["display"]))
            continue
        boss["d"] = wh["display"]
        fc = _FC_FACE.get((key, boss["n"]))
        if fc == boss["d"]:
            _fc_agrees += 1
        elif fc:
            _fc_differs.append("%s: Wowhead %d, ForeverChanges %d" % (boss["n"], boss["d"], fc))
print("Forever's own bosses: %d with Wowhead Forever's NPC and display ids; ForeverChanges' pictures agree on %d, differ on %d%s"
      % (sum(1 for k in FOREVER_DMAP for b in DMAP.get(k, {}).get("bosses", []) if b.get("c")), _fc_agrees, len(_fc_differs),
         "".join("\n  " + s for s in _fc_differs)))
if _fnpc_off:
    print("  display ids not in the client's CreatureDisplayInfo, left out: " + ", ".join(_fnpc_off))
# the client's encounters by the dungeon's map (DungeonEncounter; difficulties 0 and 1, the rest are Season of
# Discovery's raids): b.o, a boss's place in the game's order (the journal lists a boss the client doesn't know right
# after the entry before it), and a rare the game counts as an encounter is a boss. D.DMAP[key].mid is the map
DMAP_MID = {"d1581": 36, "d717": 34, "d718": 43, "d719": 48, "d209": 33, "d796": 189, "d491": 47, "d1337": 70, "d721": 90,
            "d2437": 389, "d722": 129, "d1417": 109, "d1584": 230, "d1583": 229, "d2057": 289, "d2017": 329, "d2557": 429,
            "d2100": 349, "d16544": 2959, "d16732": 2998, "d16611": 2999, "d16919": 3065}
# loot names of a boss whose encounter the client names otherwise: its spelling, or the group it fights in
DE_ALIAS = {"Kirtonos the Herald": "Kirtonos", "Ras Frostwhisper": "Ras Frostwhisperer", "Gelihast": "Geilhast",
            "Doom'rel": "The Seven", "Anger'rel": "The Seven",
            **dict.fromkeys(('Eric "The Swift"', "Baelog", "Olaf"), "The Lost Dwarves"),
            **dict.fromkeys(("Anub'shiah", "Eviscerator", "Gorosh the Dervish", "Grizzle", "Hedrum the Creeper", "Ok'thor the Breaker"), "Ring of Law")}
_DE = {}
for r in csv.DictReader(open(os.path.join(REPO, "research", "wago", BUILD, "DungeonEncounter.csv"))):
    if r["DifficultyID"] in ("0", "1"):
        k = (int(r["MapID"]), _bn(r["Name_lang"]))
        _DE[k] = min(int(r["OrderIndex"]), _DE.get(k, int(r["OrderIndex"])))
# Forever's own dungeons have no journal art: their loading screen (Map -> LoadingScreens' main image, 16:9), which
# the journal crops to a band (coverKind LOADING)
_MAP_LOAD = {int(r["ID"]): r["LoadingScreenID"] for r in csv.DictReader(open(os.path.join(REPO, "research", "wago", BUILD, "Map.csv")))}
_LOAD_IMG = {r["ID"]: int(r["MainImageFileDataID"]) for r in csv.DictReader(open(os.path.join(REPO, "research", "wago", BUILD, "LoadingScreens.csv")))}
_FILES = {int(v) for v in MAN.values()}
_promoted = []
for key, entry in DMAP.items():
    entry["mid"] = DMAP_MID[key]
    for boss in entry["bosses"]:
        n = _unring(boss["n"])
        o = _DE.get((entry["mid"], _bn(DE_ALIAS.get(n, n))))
        if o is not None:
            boss["o"] = o
            if boss["k"] == "rare":
                boss["k"] = "boss"
                _promoted.append(boss["n"])
        if not (boss.get("p") or boss.get("d")):
            a = ACH_BOSS.get(_bn(boss["n"])) or ACH_BOSS.get(EJ_ALIAS.get(boss["n"], ""))
            if a: boss["a"] = a
    cover, kind = ej_cover(EJ_COVER.get(key, ""))
    if not cover and _LOAD_IMG.get(_MAP_LOAD.get(entry["mid"])) in _FILES:
        cover, kind = _LOAD_IMG[_MAP_LOAD[entry["mid"]]], "LOADING"
    if cover:
        entry["cover"] = cover
        entry["coverKind"] = kind
    entry["defaultFace"] = EJ_BOSS_DEFAULT
print("journal order: %d entries placed in the game's encounter order; rares the game counts as encounters, now bosses: %s"
      % (sum(1 for e in DMAP.values() for b in e["bosses"] if "o" in b), ", ".join(_promoted)))
# the census: how each entry's face is drawn (DungeonMap.lua's DM.Face: the journal's art, the model's portrait, an
# achievement's icon, the kind's icon, and the default face for a boss with none). FACELESS_BOSS_MAX may only go down
FACELESS_BOSS_MAX = 0
_faces = collections.Counter()
_faceless = []
for key, entry in DMAP.items():
    for boss in entry["bosses"]:
        face = next((f for f in ("p", "d", "a") if boss.get(f)), "default" if boss["k"] == "boss" else "kind icon")
        _faces[face] += 1
        if face == "default":
            _faceless.append(boss["n"])
print("journal faces: %d art, %d model, %d achievement icon, %d kind icon, %d bosses with no face (at most %d)%s" % (
    _faces["p"], _faces["d"], _faces["a"], _faces["kind icon"], len(_faceless), FACELESS_BOSS_MAX,
    (": " + ", ".join(_faceless)) if _faceless else ""))
if len(_faceless) > FACELESS_BOSS_MAX:
    sys.exit("more bosses with no face than FACELESS_BOSS_MAX: find each one an image, don't raise the number")
lines.append("D.DMAP = " + lua(DMAP))

# Herb and ore nodes by name (Glow.lua lights the object your Interact key would use: green for an herb, orange for
# ore). The names come from the Classic database's object templates whose lock asks for Herbalism or Mining
# (research/questbank/gather.json, built from research/cmangos); Forever keeps Classic's node names.
_GATHER = load("gather.json", {}) or {}
GATHER = {}
for n in _GATHER.get("herb", []): GATHER[n.replace("\\'", "'")] = "herb"
for n in _GATHER.get("ore", []): GATHER[n.replace("\\'", "'")] = "ore"
lines.append("D.GATHER = " + lua(GATHER))

# Forever's camps (Camp.lua reminders): the campfire kits (Cooking), one feature per profession at skill 20, 140 and
# 300 (a sit-down buff; the higher tiers carry the lower one's buff), and the Cozy Sleeping Bag; plus the foods that
# make you Well Fed. From the site's item database (plan/items-db.json: the client's own Use lines) and the client's
# item-effect tables (which spell a kit casts, so a campfire being lit is seen on UNIT_SPELLCAST_SUCCEEDED).
#   D.CAMP[item id] = { n = name, p = profession, s = skill, t = "kit"|"feature"|"bag", g = what it gives, i = icon,
#                       base = the item whose benefit it also gives, sp = the spell the item casts, cap = features a kit allows,
#                       b, bn = the buff a feature gives as an aura, its spell and its name }
#   D.FOOD[item id] = { n = name, g = what it gives, i = icon }
_ITEMS = load_json(os.path.join(REPO, "plan", "items-db.json")) or {"items": []}
_IE = {r["ID"]: r for r in csv.DictReader(open(os.path.join(REPO, "research", "wago", BUILD, "ItemEffect.csv")))}
_IXE = {}
for r in csv.DictReader(open(os.path.join(REPO, "research", "wago", BUILD, "ItemXItemEffect.csv"))):
    e = _IE.get(r["ItemEffectID"])
    if e and e["TriggerType"] == "0": _IXE.setdefault(int(r["ItemID"]), int(e["SpellID"]))
CAMP, FOOD = {}, {}
def _gives(use):
    m = re.search(r"(?:gain|nearby) (\d+%?) (?:increased )?(?:melee )?([A-Za-z ]+?)(?:,| for| with| every|\.)", use)
    if m and m.group(2).strip().lower() not in ("stats",): return "+%s %s" % (m.group(1), m.group(2).strip())
    if m: return "+%s all stats" % m.group(1)
    m = re.search(r"regenerate (\d+) Mana every 5 sec", use)
    if m: return "%s mana per 5 sec" % m.group(1)
    if "Rested experience" in use: return "rested XP to 5% of a level"
    if "bonus to experience" in use: return "+XP in the bag, stacks to 3"
    m = re.search(r"grants the ability to (catch [a-z]+ fish)", use)
    if m: return m.group(1)
    for k, v in (("Repair", "repairs and reagents"), ("purchase reagents", "a reagent vendor"), ("grow herbs", "grows herbs"), ("spawns a common mining node", "a mining node"),
                 ("Track Beasts", "Track Beasts"), ("healing potions", "healing potions"), ("disenchanting", "better disenchanting"), ("traps", "traps")):
        if k in use: return v
    return None
_camp_by_name = {}
for it in _ITEMS["items"]:
    use = " ".join(e for e in (it.get("effects") or []) if e.startswith("Use:"))
    if not use: continue
    iid = int(it["id"])
    if re.search(r"Requires a Campfire nearby|Builds an? (basic|journeyman|expert) campfire|Unfurl a sleeping bag", use) and not it["name"].startswith("Blueprint"):
        sk = it.get("reqSkill")
        prof, lvl = (sk.rsplit(" ", 1) if sk else (None, "0"))
        kind = "kit" if "campfire that allows" in use else ("bag" if "sleeping bag" in use else "feature")
        entry = {"n": it["name"], "p": prof, "s": int(lvl) if lvl.isdigit() else 0, "t": kind, "g": _gives(use), "i": it.get("icon")}
        base = re.search(r"benefits of an? ([A-Z][A-Za-z' ]+?)(?:\.| Requires)", use)
        if base: entry["baseName"] = base.group(1).strip()
        cap = re.search(r"up to (\d+) additional camp features", use)
        if cap: entry["cap"] = int(cap.group(1))
        if iid in _IXE: entry["sp"] = _IXE[iid]
        CAMP[iid] = entry
        _camp_by_name.setdefault(it["name"], iid)
    elif re.search(r"well fed", use, re.I):
        m = re.search(r"well fed and gain (\d+%?) ([A-Za-z ]+?)(?: and ([A-Za-z ]+?))? for (\d+) min", use, re.I)
        g = m and ("+%s %s%s, %s min" % (m.group(1), m.group(2), (" and " + m.group(3)) if m.group(3) else "", m.group(4))) or "Well Fed"
        FOOD[iid] = {"n": it["name"], "g": g, "i": it.get("icon")}
# the buff a feature gives while you sit by it, as the aura's own spell (the missing-buffs banner looks for it on you):
# the first spell the cast's tooltip names for its number ($1230172s1: Extra Strength), never the shared cooldown
# (Camping, 1308027). The aura's name is not the feature's (the Sharpening Wheel's is Extra Strength); a feature that
# carries a lower tier's benefits has its buff. Tents, bots and workbenches give no aura: no b
_SPELL_DESC = {r["ID"]: r["Description_lang"] or "" for r in csv.DictReader(open(os.path.join(REPO, "research", "wago", BUILD, "Spell.csv")))}
_SPELL_NAME = {r["ID"]: r["Name_lang"] for r in csv.DictReader(open(os.path.join(REPO, "research", "wago", BUILD, "SpellName.csv")))}
for iid, e in CAMP.items():
    if e["t"] != "feature" or not e.get("sp"): continue
    for ref in re.findall(r"\$(\d{5,})s1", _SPELL_DESC.get(str(e["sp"]), "")):
        if ref != "1308027" and _SPELL_NAME.get(ref):
            e["b"], e["bn"] = int(ref), _SPELL_NAME[ref]
            break
for iid, e in CAMP.items():
    bn = e.pop("baseName", None)
    if bn and _camp_by_name.get(bn):
        e["base"] = _camp_by_name[bn]
        if not e.get("g"): e["g"] = CAMP[_camp_by_name[bn]].get("g")
        if not e.get("b") and CAMP[_camp_by_name[bn]].get("b"): e["b"], e["bn"] = CAMP[_camp_by_name[bn]]["b"], CAMP[_camp_by_name[bn]]["bn"]
# the drop chance a quest's items carry (objectives.py -> drops.json): D.DROP[quest id] = percent, the worst item
_DROPS = load("drops.json", {}) or {}
DROP = {int(k): v for k, v in _DROPS.items() if int(k) in LIST}
lines.append("D.DROP = " + keyed(DROP))
lines.append("D.CAMP = " + keyed(CAMP))
lines.append("D.FOOD = " + keyed(FOOD))
lines.append("-- [id] = {quest level, required level, side (1 Alliance, 2 Horde, 0 both), Classic base XP, Forever multiplier,")
lines.append("--         turn-in NPC, quest giver, category, class mask, flags (1 dungeon, 2 group, 4 starts from an item, 8 multiplier not read,")
lines.append("--         16 Classic only: not in Wowhead Forever's data yet, 32 multiplier taken from its dungeon's other quests,")
lines.append("--         64 XP not known yet, 128 a Season of Discovery leftover: its NPC hasn't been met in Forever,")
lines.append("--         256 multiplier computed from the pre-2026-10-01 read: the extra above x1 halved, not yet re-read,")
lines.append("--         512 XP as the game paid it after the cut: a hand-in or quest window on build 70170 or later,")
lines.append("--         1024 a wanted poster, 2048 an escort, 4096 repeatable (in the reward finders alone), 8192 kept as read: the game paid within a few percent of it after the cut,")
lines.append("--         16384 known only from players' notes: level, NPCs and XP as their games showed them; needs = the lowest level anyone took it at,")
lines.append("--         32768 the required level as Blizzard's notes give it;")
lines.append("--         65536 never here: QuestBank gives it to the quests of D.SURVEYED, which it shows in its finders alone,")
lines.append("--         131072 a turn-in: a Craftsman's Writ's delivery, no XP, in the reward finders alone)}")
lines.append("D.Q = {\n" + ",\n".join("[%d]=%s" % (k, lua(v)) for k, v in sorted(Q.items())) + "\n}")
lines.append("D.QN = " + keyed(QN))
lines.append("D.STEPNAME = " + keyed(STEPNAME))
lines.append("D.QITEM = " + keyed(QITEM))
lines.append("D.QICON = " + keyed(QICON))
lines.append("D.TIPS = " + keyed(TIPS))
lines.append("-- [id] = a line for the quest tooltip: where a number comes from, or what Blizzard changed that nobody has read since")
lines.append("D.NOTE = " + keyed(NOTE))
lines.append("D.PRE = " + keyed(PRE))
lines.append("-- [id] = {item, count, 1 banked with the item in your bags | 2 the item is needed to finish | 0 starts from the item, item name}")
lines.append("D.BAGQ = " + keyed(BAGQ))
lines.append("D.FOLLOW = " + keyed(FOLLOW))
lines.append("-- quests both factions take, handed in to a different NPC by the Horde")
lines.append("D.TURNH = " + keyed(TURNH))
lines.append("-- steps that follow a quest in its chain, races that may take a race-limited quest (1 Human, 2 Orc, 4 Dwarf, 8 Night Elf,")
lines.append("-- 16 Undead, 32 Tauren, 64 Gnome, 128 Troll), and quests that rule each other out")
lines.append("D.NEXT = " + keyed(NEXT))

# where each quest is done: up to three spawn areas per quest from the Classic database (objectives.py),
# {continent, world x, world y, radius in yards}, the busiest first. The Available tab uses them to say which
# quests are done in the same spot.
_OBJ_SRC = load("objectives.json", {}) or {}
OBJ = {}
for qid in IDS:
    areas = []
    for e in _OBJ_SRC.get(str(qid)) or []:
        for a in e.get("areas") or []:
            if len(a) >= 5 and a[0] in (0, 1):
                areas.append((a[4], [int(a[0]), int(round(a[1])), int(round(a[2])), int(round(a[3]))]))
    if areas:
        areas.sort(key=lambda t: -t[0])
        seen_a, out_a = set(), []
        for _, a in areas:
            k = (a[0], a[1] // 60, a[2] // 60)
            if k not in seen_a:
                seen_a.add(k)
                out_a.append(a)
            if len(out_a) == 3:
                break
        OBJ[qid] = out_a
lines.append("-- [id] = { {continent, world x, world y, radius}, ... }: where the quest is done, from the Classic database")
lines.append("D.OBJ = " + keyed(OBJ))

# ---------------------------------------------------------------------------
# map icons: where each objective is done and where a quest's starting item drops, each spot in the percent frame
# of the one map it is drawn on (never projected at runtime: the Forever-only maps lie over Classic zones)
# ---------------------------------------------------------------------------
import objectives as OBJECTIVES  # noqa: E402  (the clustering rules, shared with objectives.py)
_SPOTS = load("spots.json", {}) or {}            # objectives.py: CMaNGOS spawns and quest POIs, in world yards
_MAPPER = load("mapper.json", {}) or {}          # mapper.py: Wowhead Forever's quest-page mapper; skipped until fetched
_SPOT_Q = _SPOTS.get("q") or {}
_SPOT_START = _SPOTS.get("start") or {}
MAPFIX = FrameFix()  # its own count: GAPS.md's FrameFix numbers stay the NPC tooltips'


def map_width(mid):
    m = TR.maps[mid]
    return (m["maxy"] - m["miny"]) / ((m["u1"] - m["u0"]) or 1)


def permille(v):
    return max(0, min(1000, int(round(v * 10))))


def spot(kind, slot, mid, x, y, r, src, name):
    """One spot: x and y (map percent) to permille of the map, r (yards) to permille of its width. Written out as
    "kind,slot,map,x,y,r,src[,name]" once D.SN is known."""
    return (kind, slot, mid, permille(x), permille(y), int(round(r / map_width(mid) * 1000)), src, name or "")


def quest_zone_map(qid):
    q = LIST[qid]
    return TR.area_map.get(q.get("category")) if q.get("category2") in (0, 1) else None


def npc_world(i):
    """A placed giver or ender as (continent, world x, world y), islands included, for "nearest the quest"."""
    n = NPCS[i - 1] if i else None
    return TR.world(n[1], n[2], n[3]) if n and n[1] else None


def tag_world(qid, kind, slot, src, areas, wma=()):
    """World areas [continent, x, y, radius, name, the WorldMapArea of a quest outline (0 for spawns)] -> spots, each
    on the one map spot_map picks: Blizzard's for an outline; else, preferred, the maps of the objective's outlines
    (wma), the quest's own zone, the giver's and the ender's maps."""
    zone = quest_zone_map(qid)
    give, turn = Q[qid][6], Q[qid][5]
    prefer = [m for m in [WMA_UIMAP.get(w) for w in wma] + [zone, give and NPCS[give - 1][1], turn and NPCS[turn - 1][1]] if m]
    out = []
    for c, wx, wy, r, name, w in areas:
        at = spot_map(c, wx, wy, prefer, (zone,) if zone in OVERLAY else (), (WMA_UIMAP.get(w),) if w else ())
        if at:
            out.append(spot(kind, slot, at[0], at[1], at[2], r, src, name))
    return out


def wowhead_areas(qid, groups):
    """Wowhead's points ([{uiMap, coords, type, id, name}], 0-100 of each map) -> clustered spot positions
    [(uiMap, x, y in percent, radius in yards, name)]. Points on the redrawn maps go through FrameFix (against the
    creature's CMaNGOS spawns when it has some); only zone maps and the islands count."""
    near = [w for w in (npc_world(Q[qid][6]), npc_world(Q[qid][5])) if w]
    # Wowhead names every creature that ever dropped an item: a source with under a tenth of the busiest one's
    # points is left out
    size = collections.Counter()
    for g in groups:
        size[(g.get("type"), g.get("id"), g.get("name"))] += len(g.get("coords") or [])
    top = max(size.values()) if size else 0
    pts = []
    for g in groups:
        if size[(g.get("type"), g.get("id"), g.get("name"))] < 0.1 * top:
            continue
        m = g.get("uiMap")
        if m not in TR.maps or (TR.maps[m]["cont"] not in (0, 1) and m not in ISLANDS) or not TR.maps[m]["area"]:
            continue
        mine = []
        for xy in g.get("coords") or []:
            if not isinstance(xy, list) or len(xy) < 2:
                continue
            x, y = xy[0], xy[1]
            if m in TR.redrawn:
                x, y = MAPFIX.fix(g.get("type") if g.get("type") in ("npc", "object") else "npc", g.get("id") or 0, m, x, y)
            w = TR.world(m, x, y)
            if w:
                mine.append((w[0], w[1], w[2], (m, g.get("name") or "")))
        if len(mine) > OBJECTIVES.NODE:  # ore, herbs, critters: near the quest only
            mine = [p for p in mine if OBJECTIVES.near_dist(p, near) <= OBJECTIVES.NEAR]
        pts += mine
    out = []
    for c, wx, wy, r, _, (m, name) in OBJECTIVES.cluster(pts, near):
        x, y = TR._pct(TR.maps[m], wx, wy)
        out.append((m, x, y, r, name))
    return out


# Where players' games saw an objective tick (disc.json "os": QuestBank's discoveries on the Forever client, merged by
# probe_pull.py): {quest: {the game's objective index: {"t": its type, "p": [[uiMap, x, y, n, votes, last], ...]}}},
# x and y in permille of the map the player stood on, already in Forever's frame; n the most sightings one upload had
# there, votes how many uploads had it, last the upload that last had it. Only the first four are read. The same
# growing file comes back upload after upload, so votes say how often it was re-sent more than how many players saw
# it: n weighs the points, clustered as the Classic spawns are. gen_data.py --selftest-os runs probe_pull.py's merge
# on its Forever fixture and made-up uploads through this reader, so a change to that shape shows there.
SELFTEST_OS = "--selftest-os" in sys.argv
_OS = DISC.get("os") or {}
_NEED = _SPOTS.get("need") or {}  # objectives.py: what each of a Classic quest's slots is, placed or not
GAME_KIND = {"monster": "k", "item": "c", "object": "u", "event": "e", "areatrigger": "e", "log": "e", "progressbar": "e"}
SLOT_TYPES = {"npc": ("monster",), "cast": ("monster", "object"), "object": ("object",), "item": ("item",)}
SLOT_KIND = {"npc": "k", "cast": "u", "object": "u", "item": "c"}
WH_TYPES = {"k": ("monster",), "u": ("object", "monster")}  # a Wowhead slot's kind -> the game's (c: item or object)
# lines the game may show beside a quest's slots: an event (an escort, a place to reach, a script; the game may count
# an escort or a talk as a monster line, a scripted object as an object line) and a reputation to reach
EVENT_LINE = ("event", "areatrigger", "log", "progressbar", "monster", "object")
REP_LINE = ("reputation",)
WH_EXTRA = {"e": EVENT_LINE, "k": ("monster",), "u": ("object", "monster"), "c": ("item",)}  # a Wowhead row with no slot
GAME_R = 15   # permille of the map's width: the smallest players' area (the addon merges sightings this close)
GAME_W = 20   # sightings one point weighs at most, so one busy camp doesn't push every other area out
GAME_FOLDED = []  # (quest, slot) of players' areas left out: inside a Classic or Wowhead area of the same objective


def os_objectives(qid):
    """[(the game's objective index, its type or None, [(uiMap, x, y in permille, sightings)])] for one quest."""
    rec = _OS.get(str(qid))
    pairs = rec.items() if isinstance(rec, dict) else enumerate(rec, 1) if isinstance(rec, list) else ()
    out = []
    for k, ob in pairs:
        try:
            idx = int(k)
        except (TypeError, ValueError):
            continue
        if not isinstance(ob, dict):
            continue
        pts = []
        for p in ob.get("p") or []:
            if isinstance(p, dict):
                p = [p.get(c) for c in "mxyn"]
            if not isinstance(p, list) or len(p) < 3:
                continue
            try:
                m, x, y, n = int(p[0]), float(p[1]), float(p[2]), int(p[3] or 1) if len(p) > 3 else 1
            except (TypeError, ValueError):
                continue
            if 0 <= x <= 1000 and 0 <= y <= 1000:
                pts.append((m, x, y, max(1, n)))
        if pts:
            out.append((idx, ob.get("t") if isinstance(ob.get("t"), str) else None, pts))
    return sorted(out)


def game_orders(slots, extra=()):
    """Every order the game may list a quest's lines in (the client's order isn't checked yet): the slots as given,
    the creature and object slots before the item slots or after them, the object slots before the creature ones,
    or each objective number's creature or object line beside its item line; and each extra line (an event, a
    reputation: the types it may come as) left out or at any place among them. An extra line is (None, its types,
    None, None)."""
    cre, items = [s for s in slots if s[0] < 5], [s for s in slots if s[0] >= 5]
    objects = [s for s in cre if "monster" not in s[1]] + [s for s in cre if "monster" in s[1]]
    bases = {tuple(slots)}
    for c in (cre, objects):
        bases |= {tuple(c + items), tuple(items + c)}
    for item_first in (False, True):
        bases.add(tuple(sorted(slots, key=lambda s: ((s[0] - 1) % 4, (s[0] < 5) == item_first))))
    out = set()
    for base in bases:
        orders = {base}
        for x in extra:
            orders |= {L[:k] + ((None, tuple(x), None, None),) + L[k:] for L in orders for k in range(len(L) + 1)}
        out |= orders
    return out


def game_slots(slots, objs, extra=()):
    """Which catalog slot each of the game's objective lines is: slots [(slot, the game's types it can be, kind,
    name)], objs [(index, type or None)], extra the lines the game may show that no slot is (an event, a reputation:
    the types each may come as) -> {index: slot}. The lines of one type take that type's slots in order when as many
    of them were seen and no extra line can be of that type. Else a line's place in the game's list says which, in
    every order of game_orders that all the seen lines fit (each line's type one its place can be; an untyped line
    any), when they all agree: an event or reputation line seen pins where the extra lines are. A line nothing is
    found for (or one two lines took) is no slot: slot 0, shown until the quest is done."""
    if any(i > len(slots) + len(extra) for i, _ in objs):
        return {}  # the game lists more lines than the catalog knows: it isn't the game's list, so no line is paired
    orders = [L for L in game_orders(slots, extra) if all(i <= len(L) and (not t or t in L[i - 1][1]) for i, t in objs)]
    out = {}
    for t in sorted({t for _, t in objs if t}):
        mine = sorted(i for i, tt in objs if tt == t)
        fit = [s for s in slots if t in s[1]]
        if len(mine) == len(fit) and not any(t in x for x in extra):
            out.update(zip(mine, fit))
        elif len(mine) <= len(fit):
            for i in mine:
                at = {L[i - 1] for L in orders}
                if len(at) == 1 and next(iter(at))[0] is not None:
                    out[i] = at.pop()
    took = collections.Counter(s[0] for s in out.values())
    return {i: s for i, s in out.items() if took[s[0]] == 1}


def game_areas(qid, pts):
    """One objective's points [(uiMap, x, y in permille, sightings)] -> up to five areas [(uiMap, x, y in percent,
    radius in yards)] on zone maps and the islands, the busiest five, nearest the giver and ender first. Every area
    counts, near the quest or not: players were there."""
    near = [w for w in (npc_world(Q[qid][6]), npc_world(Q[qid][5])) if w]
    world = []
    for m, x, y, n in pts:
        tm = TR.maps.get(m)
        if not tm or not tm["area"] or m in (947, 1414, 1415, 1945) or (tm["cont"] not in (0, 1) and m not in ISLANDS):
            continue
        w = TR.world(m, x / 10.0, y / 10.0)
        world += [(w[0], w[1], w[2], m)] * min(n, GAME_W)
    areas = OBJECTIVES.cluster(world, [])
    areas.sort(key=lambda a: (round(OBJECTIVES.near_dist(a, near)), -a[4], a[1], a[2]))
    out = []
    for c, wx, wy, r, _, m in areas:
        x, y = TR._pct(TR.maps[m], wx, wy)
        out.append((m, x, y, max(r, GAME_R / 1000.0 * map_width(m))))
    return out


def covers(a, b):
    """Spot b's centre lies inside spot a's circle, on the same map."""
    if a[2] != b[2]:
        return False
    wa, wb = TR.world(a[2], a[3] / 10.0, a[4] / 10.0), TR.world(b[2], b[3] / 10.0, b[4] / 10.0)
    return math.hypot(wa[1] - wb[1], wa[2] - wb[2]) <= a[5] / 1000.0 * map_width(a[2])


# gen_data.py --selftest-os: disc.json's "os" made by probe_pull.py's own merge (its Forever fixture, then made-up
# uploads) instead of the real one, read by the reader above; os_selftest() below checks what came out and the build
# stops before writing anything. The made-up points sit on Elwynn (1429), for quests done on other maps (7 and 33 are
# the fixture's), so no Classic area takes them in.
# far apart, 9 down to 3 sightings: the least seen are the ones clustering would list first by place alone
OS_TEST_FAR = [[1429, 100 + 130 * k, 120 + 110 * k, 9 - k] for k in range(7)]
OS_TEST_BUSY = [[1429, 200, 650, 999], [1429, 800, 650, 30]]  # one camp seen 999 times weighs as much as one seen 30
OS_TEST_FO = next((q for q in IDS if q >= 60000 and str(q) not in _NEED and str(q) not in _MAPPER and str(q) not in _SPOT_Q), None)


def os_selftest_input():
    sys.path.insert(0, os.path.dirname(HERE))
    import probe_pull
    acc = probe_pull.empty()
    fixture = os.path.join(os.path.dirname(HERE), "fixtures", "probe", "QuestBank-forever.lua")
    kind, _ = probe_pull.merge_upload(acc, open(fixture, encoding="utf-8").read(), "fixture")
    assert kind == "questbank-savedvars" and acc["os"].get("7") and acc["os"].get("33"), "the fixture's spots reach disc.json"
    pt = lambda k: [[1429, 150 + 100 * k, 850, 2]]  # noqa: E731
    fo = OS_TEST_FO
    probe_pull.merge_spots(acc, {
        604: {1: {"t": "monster", "p": pt(1)}, 2: {"t": "item", "p": pt(2)}, 3: {"t": "item", "p": pt(3)}},
        38: {2: {"t": "item", "p": pt(1)}},                                     # one line of four item lines
        5088: {2: {"t": "item", "p": pt(1)}},                                   # an event quest: is line 2 slot 5 or 6?
        1386: {2: {"t": "monster", "p": pt(1)}, 3: {"t": "monster", "p": pt(2)}},  # a reputation one: 1 and 2, or 2 and 3?
        434: {1: {"t": "event", "p": pt(1)}, 3: {"t": "monster", "p": pt(2)}},  # the event line seen first: line 3 is slot 2
        fo: {1: {"t": "monster", "p": OS_TEST_FAR},
             2: {"t": "item", "p": [[1414, 500, 500, 5], [1459, 500, 500, 5], [9999, 500, 500, 5], [2548, 400, 400, 2]]},
             3: {"t": "object", "p": [[2521, 300, 300, 2]]}, 4: {"t": "event", "p": pt(4)},
             5: {"t": "reputation", "p": pt(5)}, 6: {"p": pt(6)}, 7: {"t": "spell", "p": pt(7)}, 8: {"t": "monster", "p": OS_TEST_BUSY}}})
    for _ in range(4):  # the least-sighted far point comes again in four uploads: five votes, still three sightings
        probe_pull.merge_spots(acc, {fo: {1: {"t": "monster", "p": OS_TEST_FAR[-1:]}}})
    got = json.loads(json.dumps(acc["os"]))  # as disc.json keeps it
    again = [p for p in got[str(fo)]["1"]["p"] if p[4] == 5]
    assert len(again) == 1 and again[0][:4] == OS_TEST_FAR[-1], "probe_pull keeps a point as [uiMap, x, y, n, votes, ...]: %s" % again
    return got


if SELFTEST_OS:
    assert OS_TEST_FO, "a Forever-only quest the Classic data and Wowhead know nothing of"
    _OS = os_selftest_input()

SPOT, START, SREQ = {}, {}, {}
# quests by source: c spawns, p POI outlines only, w Wowhead; players' games: g beside those, G alone
SPOT_FROM = collections.Counter()
for qid in IDS:
    sq = _SPOT_Q.get(str(qid))
    need = _NEED.get(str(qid)) or {}
    # each slot: (slot, the game's types it can be, kind, name); and what it asks for: {slot: (count, item name)}
    cm_slots = [(int(s), SLOT_TYPES[t], SLOT_KIND[t], (need.get("names") or {}).get(s))
                for s, t in sorted((need.get("ty") or {}).items(), key=lambda kv: int(kv[0])) if t in SLOT_TYPES]
    cm_req = {int(k): (v, CM_ITEMNAMES.get((need.get("items") or {}).get(k)) if int(k) >= 5 else None)
              for k, v in (need.get("req") or {}).items()}
    # the lines the game may show that no slot is: the quest's event, the reputation it asks for
    cm_extra = [EVENT_LINE] * bool(need.get("event")) + [REP_LINE] * bool(need.get("rep"))
    parts, req, slots, extra = [], {}, cm_slots, cm_extra
    if sq:
        got = set()
        for o in sq.get("obj") or []:
            tagged = tag_world(qid, o["k"], o["slot"], o["spots"][0][4], [a[:4] + [a[5], (a[6:] or [0])[0]] for a in o["spots"]],
                               o.get("wma") or ())
            if tagged:
                parts += tagged
                got.add(o["spots"][0][4])
        req = {int(k): (v, cm_req.get(int(k), (0, None))[1]) for k, v in (sq.get("req") or {}).items()}
        if parts:
            SPOT_FROM["c" if "c" in got else "p"] += 1
    wq = _MAPPER.get(str(qid)) or {}
    # nothing in the Classic database: Wowhead Forever's quest page, once mapper.py has read it
    if not parts and wq.get("objectives"):
        req, slots, extra = {}, [], []
        for o in wq.get("objectives") or []:
            if o.get("kind") not in ("k", "c", "u", "e"):
                continue
            if o.get("index") and not ((o.get("slot") or 0) and o["kind"] in ("k", "u", "c")):
                extra.append(WH_EXTRA[o["kind"]])  # a row of the page's that is no slot: an event, one past four
            slot = o.get("slot") or 0
            for m, x, y, r, name in wowhead_areas(qid, o.get("spots") or []):
                parts.append(spot(o["kind"], slot, m, x, y, r, "w", name or o.get("name")))
            if slot and o.get("count"):
                item = o.get("name") if o["kind"] == "c" and slot >= 5 else None
                req[slot] = (max(req.get(slot, (0,))[0], o["count"]), item or req.get(slot, (0, None))[1])
            if slot and o["kind"] in ("k", "u", "c"):
                slots.append((slot, ("item",) if slot >= 5 else WH_TYPES.get(o["kind"], ("object",)), o["kind"],
                              None if slot >= 5 else o.get("name")))
        if parts:
            SPOT_FROM["w"] += 1
    if not parts and need:  # players' spots alone: the Classic database's slots (else Wowhead's, if its page has any)
        req, slots, extra = dict(cm_req), cm_slots, cm_extra
    # players' games: after the Classic and Wowhead spots of the same objective, filling what those have nothing for
    objs = os_objectives(qid)
    if objs:
        pick = game_slots(slots, [(i, t) for i, t, _ in objs], extra)
        kind_at = {}
        for p in parts:
            kind_at.setdefault(p[1], p[0])
        seen = 0
        for i, t, pts in objs:
            s = pick.get(i)
            slot, kind = (s[0], kind_at.get(s[0], s[2])) if s else (0, GAME_KIND.get(t))
            if not kind:
                continue  # a reputation, money or player-kill line: no place to it
            name = (s[3] if kind in ("k", "u") else (req.get(slot) or (0, None))[1] if kind == "b" else None) if s else None
            for m, x, y, r in game_areas(qid, pts):
                sp = spot(kind, slot, m, x, y, r, "g", name)
                if any(o[1] == slot and o[0] == kind and covers(o, sp) for o in parts if o[6] != "g"):
                    GAME_FOLDED.append((qid, slot))
                    continue
                parts.append(sp)
                seen += 1
        if seen:
            SPOT_FROM["g" if len(parts) > seen else "G"] += 1
    if parts:
        SPOT[qid] = parts
        if req:
            SREQ[qid] = req
    if Q[qid][9] & 4:  # starts from an item: where it drops
        item = BAGQ.get(qid, [0])[0]
        rec = _SPOT_START.get(str(item)) or next((v for v in _SPOT_START.values() if v.get("quest") == qid), None)
        st = tag_world(qid, "s", 0, "c", [a[:4] + [a[5], (a[6:] or [0])[0]] for a in rec["spots"]]) if rec else []
        if not st:
            # Wowhead's "start" holds the giver's points too: only the points where the item drops count, named after it
            drops = [dict(g, name=g["item"]) for g in (_MAPPER.get(str(qid)) or {}).get("start") or [] if g.get("item")]
            for m, x, y, r, name in wowhead_areas(qid, drops):
                st.append(spot("s", 0, m, x, y, r, "w", name))
        if st:
            START[qid] = st
# names by how often they are used (spots, and the item each item slot asks for), so the busiest get the shortest index
_uses = collections.Counter(p[7] for v in list(SPOT.values()) + list(START.values()) for p in v if p[7])
_uses.update(name for v in SREQ.values() for _, name in v.values() if name)
SN = [n for n, _ in sorted(_uses.items(), key=lambda kv: (-kv[1], kv[0]))]
SN_AT = {n: k + 1 for k, n in enumerate(SN)}


def spots_str(parts):
    return ";".join("%s,%d,%d,%d,%d,%d,%s%s" % (p[:7] + ((",%d" % SN_AT[p[7]]) if p[7] else "",)) for p in parts)


def os_selftest():
    """--selftest-os: what os_selftest_input's spots became, and game_slots over every Classic quest's slots."""
    def g(q):
        return sorted((p[0], p[1]) for p in SPOT.get(q, []) if p[6] == "g")

    def near(p, xy):
        return abs(p[3] - xy[1]) <= 2 and abs(p[4] - xy[2]) <= 2

    folded = collections.Counter(GAME_FOLDED)
    # the fixture: 7's point inside its Classic area is left out, the other one is a named kill spot of slot 1; 33's
    # wolf meat lies inside the Classic wolf areas; 60005's line has no type the probe keeps
    assert folded[(7, 1)] and g(7) == [("k", 1)], (g(7), GAME_FOLDED)
    assert [p[7] for p in SPOT[7] if p[6] == "g"] == [(_NEED["7"].get("names") or {}).get("1")], SPOT[7]
    assert folded[(33, 5)] or g(33) == [("c", 5)], (g(33), GAME_FOLDED)
    assert not g(60005)
    # slots: every line of a type seen; one of four; an extra line that may come first; one that is seen first
    assert g(604) == [("c", 6), ("c", 7), ("k", 1)], g(604)
    assert g(38) == [("c", 6)], g(38)
    assert g(5088) == [("c", 0)], g(5088)
    assert g(1386) == [("k", 0), ("k", 0)], g(1386)
    assert sorted(s for _, s in g(434)) == [0, 2] and ("e", 0) in g(434), g(434)
    assert not any(q in (604, 38, 5088, 1386, 434) for q, _ in GAME_FOLDED), GAME_FOLDED
    # a Forever-only quest: slot 0 and the kind from the type; continents (1414), a battleground (1459) and maps the
    # client hasn't (9999) left out, the new maps (2548, 2521) kept; reputation, untyped and spell lines no spot; at
    # most five areas a line, the busiest by sightings (not by votes: the five-vote point has the fewest sightings),
    # a point weighing at most GAME_W sightings
    fo = [p for p in SPOT[OS_TEST_FO] if p[6] == "g"]
    assert sorted(set(g(OS_TEST_FO))) == [("c", 0), ("e", 0), ("k", 0), ("u", 0)], g(OS_TEST_FO)
    kills = [p for p in fo if p[0] == "k"]
    assert len(kills) == 7 and all(any(near(p, xy) for p in kills) for xy in OS_TEST_FAR[:5] + OS_TEST_BUSY), kills
    assert [p[2] for p in fo if p[0] == "c"] == [2548] and [p[2] for p in fo if p[0] == "u"] == [2521], fo
    for v in SPOT.values():
        for part in spots_str(v).split(";"):
            assert re.match(r"^[a-z],\d+,\d+,\d+,\d+,\d+,[a-z](,\d+)?$", part), part
    # game_slots over every Classic quest's slots, the game listing them in any order game_orders knows, its extra
    # lines left out, first, between the creature and item lines or last (an event line as an event or as a monster
    # line), any one or two lines seen and all of them: never the wrong slot
    seen_as = {"npc": "monster", "cast": "monster", "object": "object", "item": "item"}
    checked = 0
    for need in _NEED.values():
        slots = [(int(k), SLOT_TYPES[t], SLOT_KIND[t], None) for k, t in sorted((need.get("ty") or {}).items(), key=lambda kv: int(kv[0]))
                 if t in SLOT_TYPES]
        cre = [(int(k), seen_as[t]) for k, t in sorted(need["ty"].items(), key=lambda kv: int(kv[0])) if int(k) < 5]
        its = [(int(k), "item") for k, t in sorted(need["ty"].items(), key=lambda kv: int(kv[0])) if int(k) >= 5]
        extra = [EVENT_LINE] * bool(need.get("event")) + [REP_LINE] * bool(need.get("rep"))
        inter = sorted(cre + its, key=lambda e: ((e[0] - 1) % 4, e[0]))
        objects = [e for e in cre if e[1] == "object"] + [e for e in cre if e[1] != "object"]
        for a, b, ev in [(a, b, ev) for a, b in ((cre, its), (its, cre), (inter, []), (objects, its))
                         for ev in (("event", "monster") if need.get("event") else ("event",))]:
            ex = [(0, ev)] * bool(need.get("event")) + [(0, "reputation")] * bool(need.get("rep"))
            for lines in {tuple(a + b), tuple(ex + a + b), tuple(a + ex + b), tuple(a + b + ex)}:
                n = len(lines)
                for seen in [(i,) for i in range(1, n + 1)] + [(i, j) for i in range(1, n + 1) for j in range(i + 1, n + 1)] + [tuple(range(1, n + 1))]:
                    for i, s in game_slots(slots, [(i, lines[i - 1][1]) for i in seen], extra).items():
                        assert s[0] == lines[i - 1][0], (need, lines, seen, i, s)
                        checked += 1
    print("selftest-os: OK (%d quests' players' spots as expected, %d slot picks over %d Classic quests all right)" % (
        sum(1 for v in SPOT.values() if any(p[6] == "g" for p in v)), checked, len(_NEED)))


if SELFTEST_OS:
    os_selftest()
    raise SystemExit(0)


# dungeon quests the route cannot lead to: flagged a dungeon's (flag 1), no objective spot, and a category with no
# entrance. The addon words their step "(<dungeon>: entrance not known yet)" (Guide.lua) and the arrow says "Finish
# <quest>" (Target.lua): a warning each build, so the gap stays in sight
_no_way = {}
for _qid, _v in Q.items():
    _cat = CATS[_v[7] - 1] if _v[7] else None
    if _v[9] & 1 and _qid not in SPOT and not (_cat and _cat.get("entrance")):
        _no_way.setdefault(_cat["name"] if _cat else "no category", []).append(_qid)
if _no_way:
    print("WARNING: %d dungeon quests with neither an objective spot nor a category entrance (\"entrance not known yet\" in the addon): %s" % (
        sum(len(x) for x in _no_way.values()),
        "; ".join("%s %d: %s" % (name, len(ids), ", ".join(str(i) for i in sorted(ids))) for name, ids in sorted(_no_way.items()))))

SPOT = {q: spots_str(v) for q, v in SPOT.items()}
START = {q: spots_str(v) for q, v in START.items()}
SREQ = {q: ",".join("%d:%d" % (k, n) + (":%d" % SN_AT[name] if name else "") for k, (n, name) in sorted(v.items()))
        for q, v in SREQ.items()}
lines.append("-- map icons, read when the world map needs them. D.SPOT[id] = where its objectives are done, D.START[id] = where the")
lines.append("-- item that starts it drops: spots \"kind,slot,map,x,y,r,src[,name]\" joined by \";\". kind: k kill, c collect (a creature's")
lines.append("-- drop or a chest's loot), u use an object (or cast on a creature), b buy from a vendor, e explore or an event, f fishing,")
lines.append("-- pickpocketing or skinning, s where the item that starts the quest drops; slot: 1-4 the creature or object objective,")
lines.append("-- 5-8 the item objective (its ReqItem slot + 4), 0 none; map: the uiMap it is drawn on; x, y: permille of that map;")
lines.append("-- r: radius in permille of the map's width (0 a point); src: c CMaNGOS spawns, p a CMaNGOS quest POI (both Classic data),")
lines.append("-- w Wowhead Forever, g players' games (slot 0 where no slot of the catalog's was found for it); name: an index into")
lines.append("-- D.SN, the creature, chest or fishing hole the spot is named after (the item for b and s). D.SREQ[id] =")
lines.append("-- \"slot:count[:item],...\", what each slot asks for, and for an item slot the item's name (an index into D.SN).")
lines.append("D.SPOT = " + keyed(SPOT))
lines.append("D.START = " + keyed(START))
lines.append("D.SN = " + lua(SN))
lines.append("D.SREQ = " + keyed(SREQ))

# ---------------------------------------------------------------------------
# reward items
# ---------------------------------------------------------------------------
# What a quest rewards: every reward item (D.RITEMS, for the tooltips and chat links), each item's facts (D.RIT) and, for
# the finder, the best item level among them and what kinds they are (D.REWARD).
# The client's own item table, the datamine plan/items-db.json is built from: each item's class, subclass and equip
# slot (what C_Item.GetItemInfoInstant answers in game), and the classes ItemSparse lets use it
_WI = os.path.join(REPO, "research", "wago", ITEMS_BUILD)
CLIENT_ITEM = {int(r["ID"]): (int(r["ClassID"]), int(r["SubclassID"]), int(r["InventoryType"]))
               for r in csv.DictReader(open(os.path.join(_WI, "Item.csv")))}
_ALLOW = {int(r["ID"]): int(r["AllowableClass"]) for r in csv.DictReader(open(os.path.join(_WI, "ItemSparse.csv")))}
_ITEMS = (load_json(os.path.join(REPO, "plan", "items-db.json")) or {})
_ITEMS = _ITEMS.get("items") or _ITEMS
if isinstance(_ITEMS, list):
    _ITEMS = {str(i.get("id")): i for i in _ITEMS}
# Where Wowhead lists no rewards (new Forever quests), the dungeon loot pages do, by quest name (codex/loot.json, from
# foreverchanges.pro and wowtbc.gg): taken when the name belongs to one catalog quest only
_LOOT = load_json(os.path.join(REPO, "codex", "loot.json")) or {}
_LOOT_Q = {}
for _dg in (_LOOT.get("dungeons") or {}).values() if isinstance(_LOOT.get("dungeons"), dict) else (_LOOT.get("dungeons") or []):
    for _lq in _dg.get("quests") or []:
        if _lq.get("name") and _lq.get("items"):
            _LOOT_Q.setdefault(_lq["name"].strip().lower(), set()).update(int(i) for i in _lq["items"])
_NAME_COUNT = {}
for _qid in IDS:
    _NAME_COUNT[str(LIST[_qid].get("name") or "").strip().lower()] = _NAME_COUNT.get(str(LIST[_qid].get("name") or "").strip().lower(), 0) + 1
# The Classic database's rewards (quest_template RewChoiceItemId1-6, choose one, and RewItemId1-4, always given), for the
# quests no Forever source knows the rewards of: mostly the Classic seed, which Wowhead Forever doesn't list
import cmangos  # noqa: E402
CM_REWARDS = {}
for _idx, _row in cmangos.read()["quest_template"]:
    _ch = [_row[_idx["rewchoiceitemid%d" % k]] for k in range(1, 7)]
    _rw = [_row[_idx["rewitemid%d" % k]] for k in range(1, 5)]
    _ch, _rw = [i for i in _ch if i], [i for i in _rw if i]
    if _ch or _rw:
        CM_REWARDS[_row[_idx["entry"]]] = (_ch, _rw)

# Every reward item a quest gives, for the tooltip, for linking in chat and for the finder, from the first source that
# has it: what players' quest windows showed (QuestBank 3.5.7+, newest upload), else Wowhead Forever's quest list (it
# always carries both lists, so an empty pair means no items), else what the game told players' QuestBank when it asked
# by id (the survey, newest build), else the dungeon loot pages by quest name, else the Classic database's, each item
# kept only when the Forever client's item table has it (D.RCLASSIC marks those quests: the tooltip says so, and the
# survey asks the game about them). c = choose one, r = always given. D.RUNK: nobody knows yet.
RITEMS, RUNK, RCLASSIC, RSRC = {}, {}, {}, collections.Counter()
REWARD_FROM_LOOT, REWARD_FROM_SURVEY, REWARD_FROM_WOWHEAD = [], [], []
for qid in IDS:
    q = LIST[qid]
    rw = ((DISC.get("q") or {}).get(str(qid)) or {}).get("rw")
    sv = SURVEY_PICK.get(qid)
    c = r = None
    u = []
    if isinstance(rw, dict) and (isinstance(rw.get("c"), list) or isinstance(rw.get("r"), list)):
        c = [int(x) for x in rw.get("c") or [] if str(x).isdigit()]
        r = [int(x) for x in rw.get("r") or [] if str(x).isdigit()]
        RSRC["game"] += 1
    elif qid not in DISC_ONLY and ("itemrewards" in q or "itemchoices" in q) and not (
            qid in WRIT and not DET.get(qid) and not (q.get("itemrewards") or q.get("itemchoices"))):
        # (a writ's quest Wowhead lists bare, no page read: its empty lists say nothing, so the survey asks the game)
        c = [x[0] for x in q.get("itemchoices") or [] if isinstance(x, list) and x]
        r = [x[0] for x in q.get("itemrewards") or [] if isinstance(x, list) and x and x[0] not in c]  # Wowhead repeats some
        RSRC["wowhead"] += 1
        REWARD_FROM_WOWHEAD.append(qid)
    elif sv and sv["c"] is not None:
        c, r = list(sv["c"]), list(sv["r"])
        RSRC["game survey"] += 1
        REWARD_FROM_SURVEY.append(qid)
    else:
        _nm = str(q.get("name") or "").strip().lower()
        if _nm in _LOOT_Q and _NAME_COUNT.get(_nm) == 1:
            u = sorted(_LOOT_Q[_nm])  # the page lists them without saying which are a choice
            c, r = [], []
            RSRC["loot pages"] += 1
            REWARD_FROM_LOOT.append(qid)
    if c is None and qid in CM_REWARDS:
        _ch, _rw = CM_REWARDS[qid]
        _ch = [i for i in _ch if i in CLIENT_ITEM]
        _rw = [i for i in _rw if i in CLIENT_ITEM and i not in _ch]
        if _ch or _rw:
            c, r = _ch, _rw
            RCLASSIC[qid] = True
            RSRC["classic"] += 1
    if c is None:
        RUNK[qid] = True
        RSRC["unknown"] += 1
    elif c or r or u:
        RITEMS[qid] = {"c": c or None, "r": r or None, "u": u or None}
# Quests the survey read that the catalog doesn't have and no list knows (a quest a list knows and the catalog leaves out
# was left out on purpose: a battleground's, a holiday's, a placeholder): with reward items, a level and a real title they
# go to the finders as "Seen in game", with no giver, place or side (D.SURVEYED); every one is listed in GAPS.md
SURVEYED, SURVEY_OUT = {}, {}  # qid -> [level, XP at full value (0 not known), title]; qid -> why it isn't in the finders
for qid, sv in sorted(SURVEY_PICK.items()):
    if qid in Q or qid in LIST:
        continue
    why = None
    if not sv["t"]:
        why = "no title"
    elif any(t in sv["t"] for t in JUNK):
        why = "a placeholder"
    elif not (1 <= sv["lv"] <= MAXLVL):
        why = "level %d" % sv["lv"] if sv["lv"] else "no level"
    elif sv["c"] is None:
        why = "rewards not read whole"
    elif not (sv["c"] or sv["r"]):
        why = "no item rewards"
    SURVEY_OUT[qid] = why
    if why:
        continue
    RITEMS[qid] = {"c": sv["c"] or None, "r": sv["r"] or None, "u": None}
    SURVEYED[qid] = [sv["lv"], sv["xp"] or 0, sv["t"]]

# the item facts the finder needs: the item database's (plan/items-db.json), else the client's own tables for an item
# it lacks (Item and ItemSparse of the survey's build: class, subclass, slot, item level), as the same cat/slot/type words
_CLIENT_ITEMS = None
INV_SLOT = {2: "neck", 4: "shirt", 11: "finger", 12: "trinket", 16: "back", 18: "bag", 19: "tabard"}


def item_facts(iid):
    """(cat, slot, type, item level) of a reward item, or None when nothing reliable is known (a Classic estimate)."""
    global _CLIENT_ITEMS
    it = _ITEMS.get(str(iid))
    if it:
        if it.get("est"):
            return None  # a Classic estimate nobody has seen in Forever: no item level to promise
        return str(it.get("cat") or ""), str(it.get("slot") or ""), str(it.get("type") or ""), int(it.get("itemLevel") or 0)
    if _CLIENT_ITEMS is None:
        _CLIENT_ITEMS = {}
        _dir = os.path.join(REPO, "research", "wago", SURVEY_BUILD)
        _lvl = {}
        if os.path.exists(os.path.join(_dir, "ItemSparse.csv")):
            for _r in csv.DictReader(open(os.path.join(_dir, "ItemSparse.csv"), encoding="utf-8")):
                _lvl[int(_r["ID"])] = int(_r["ItemLevel"] or 0)
        if os.path.exists(os.path.join(_dir, "Item.csv")):
            for _r in csv.DictReader(open(os.path.join(_dir, "Item.csv"), encoding="utf-8")):
                _i = int(_r["ID"])
                if _i in _lvl:
                    _CLIENT_ITEMS[_i] = (int(_r["ClassID"]), int(_r["SubclassID"]), int(_r["InventoryType"]), _lvl[_i])
    row = _CLIENT_ITEMS.get(int(iid))
    if not row:
        return None
    cls, sub, inv, ilvl = row
    cat = {2: "weapon", 9: "recipe", 0: "consumable"}.get(cls) or ("armor" if cls == 4 and inv not in (0, 4, 19) else "misc")
    return cat, INV_SLOT.get(inv, ""), {1: "Cloth", 2: "Leather", 3: "Mail", 4: "Plate"}.get(sub, "") if cls == 4 else "", ilvl


def reward_of(ids):
    """[best item level among the gear, kinds, the best piece] of a quest's reward items, or None when no kind is known."""
    best, kinds, bestId = 0, 0, 0
    for iid in ids:
        f = item_facts(iid)
        if not f:
            continue
        cat, slot, typ, ilvl = f
        if cat in ("armor", "weapon", "accessory", "offhand"):
            kinds |= 1
            if ilvl > best:
                best, bestId = ilvl, int(iid)
        # the armour class of the pieces offered, so the finder can leave out what you can't wear
        kinds |= {"Cloth": 64, "Leather": 128, "Mail": 256, "Plate": 512}.get(typ, 0)
        if slot == "trinket":
            kinds |= 2
        if slot in ("finger", "neck"):
            kinds |= 4
        if cat == "recipe":
            kinds |= 8
        if slot == "bag":
            kinds |= 16
        if cat == "consumable":
            kinds |= 32
    return [best, kinds, bestId] if kinds else None


# what a quest rewards, for the finder: the best item level among its reward items, what kinds they are
# (1 gear, 2 trinket, 4 ring or neck, 8 recipe, 16 bag, 32 consumable, 64 cloth, 128 leather, 256 mail, 512 plate offered), and the id of the best piece
REWARD = {}
for qid, lists in RITEMS.items():
    rr = reward_of((lists.get("r") or []) + (lists.get("c") or []) + (lists.get("u") or []))  # (the given first: a tie names it)
    if rr:
        REWARD[qid] = rr
lines.append("-- [id] = { best item level among the rewards, kinds (1 gear, 2 trinket, 4 ring or neck, 8 recipe, 16 bag, 32 consumable, 64 cloth, 128 leather, 256 mail, 512 plate), best item }")
lines.append("D.REWARD = " + keyed(REWARD))
lines.append("-- [id] = { c = { choose one of these }, r = { always given }, u = { given, split unknown } }; quests in D.RUNK: rewards not known yet")
lines.append("D.RITEMS = " + keyed(RITEMS))
lines.append("D.RUNK = " + keyed(RUNK))
lines.append("-- quests whose D.RITEMS come from the Classic database (no Forever source lists them yet)")
lines.append("D.RCLASSIC = " + keyed(RCLASSIC))
lines.append("-- [id] = { quest level, XP at full value (0 not known), title }: quests not in the catalog that players' QuestBank asked")
lines.append("-- the game about (the survey) and that reward items (D.RITEMS); QuestBank shows them in its finders as \"Seen in game\"")
lines.append("D.SURVEYED = " + keyed(SURVEYED))

# Each reward item, for the finder to judge one by one (UI.lua's UI.ItemFacts asks C_Item.GetItemInfoInstant first and
# falls back on this): { item level (0 where no source has shown Forever's numbers yet), equip slot (the client's
# InventoryType), item class, subclass[, the classes that may use it, as a class bitmask, where the item limits them] }.
# Every list above counts, the survey's quests too
_CLASS_BIT = {"Warrior": 1, "Paladin": 2, "Hunter": 4, "Rogue": 8, "Priest": 16, "Shaman": 64, "Mage": 128, "Warlock": 256, "Druid": 1024}
ALL_CLASSES = sum(_CLASS_BIT.values())
RIT = {}
for _lists in RITEMS.values():
    for _key in ("c", "r", "u"):
        for iid in _lists[_key] or []:
            if iid in RIT or iid not in CLIENT_ITEM:
                continue
            cls, sub, inv = CLIENT_ITEM[iid]
            it = _ITEMS.get(str(iid)) or {}
            _f = item_facts(iid)  # as D.REWARD reads it: the item database's, else the client's own tables; 0 for an estimate
            ilvl = _f[3] if _f else 0
            mask = _ALLOW.get(iid, -1)
            if mask == -1 and it.get("cls"):
                mask = sum(_CLASS_BIT.get(n, 0) for n in it["cls"])
            mask = mask & ALL_CLASSES if mask > 0 else 0
            RIT[iid] = [ilvl, inv, cls, sub] + ([mask] if mask and mask != ALL_CLASSES else [])
lines.append("-- [item] = { item level (0: Forever's numbers not shown yet), InventoryType, class, subclass[, class bitmask that may use it] }")
lines.append("D.RIT = " + keyed(RIT))

# What each class can wear and wield, from the client's skill tables: the weapon and armour skill lines (SkillLine
# categories 6 and 8), the classes that have each (SkillRaceClassInfo, and its MinLevel: mail and plate open at 40), and
# the item subclasses each opens (its proficiency spells, SkillLineAbility -> SpellEquippedItems). Defense (95) is left
# out: its Parry and Block spells name what you parry and block with, not what you may use.
# D.WEAPONS[class] = bitmask of weapon subclasses (2^subclass); D.ARMOR[class] = { [armour subclass] = level it opens }
_CLASSES = {int(r["ID"]): r["Filename"] for r in csv.DictReader(open(os.path.join(_WI, "ChrClasses.csv"))) if r["Filename"]}
_SL = {int(r["ID"]): r for r in csv.DictReader(open(os.path.join(_WI, "SkillLine.csv")))}
_PROF = {i for i, r in _SL.items() if r["CategoryID"] in ("6", "8") and i != 95}
_SRCI = collections.defaultdict(list)
for r in csv.DictReader(open(os.path.join(_WI, "SkillRaceClassInfo.csv"))):
    if int(r["SkillID"]) in _PROF:
        _SRCI[int(r["SkillID"])].append((int(r["ClassMask"]), int(r["MinLevel"] or 0)))
_SEI = collections.defaultdict(list)
for r in csv.DictReader(open(os.path.join(_WI, "SpellEquippedItems.csv"))):
    _SEI[int(r["SpellID"])].append((int(r["EquippedItemClass"]), int(r["EquippedItemSubclass"])))
WEAPONS, ARMOR = {}, {}
for r in csv.DictReader(open(os.path.join(_WI, "SkillLineAbility.csv"))):
    sk, abil = int(r["SkillLine"]), int(r["ClassMask"] or 0)
    if sk not in _PROF or abil == 0 or r["AcquireMethod"] == "0":
        continue
    for icls, smask in _SEI.get(int(r["Spell"]), ()):
        if icls not in (2, 4):
            continue
        for cid, cfile in _CLASSES.items():
            bit = 1 << (cid - 1)
            if not abil & bit:
                continue
            levels = [lv for m, lv in _SRCI.get(sk, ()) if m == -1 or m & bit]
            if not levels:
                continue
            if icls == 2:
                WEAPONS[cfile] = WEAPONS.get(cfile, 0) | smask
            else:
                a = ARMOR.setdefault(cfile, {})
                for sub in range(0, 16):
                    if smask & (1 << sub):
                        a[sub] = min(a.get(sub, 99), min(levels))
# Classic's own, only for a class the client's tables leave without any (they list all nine today)
CLASSIC_WEAPONS = {"WARRIOR": [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18], "PALADIN": [0, 1, 4, 5, 6, 7, 8],
                   "HUNTER": [0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18], "ROGUE": [2, 3, 4, 7, 13, 15, 16, 18],
                   "PRIEST": [4, 10, 15, 19], "SHAMAN": [0, 1, 4, 5, 10, 13, 15], "MAGE": [7, 10, 15, 19],
                   "WARLOCK": [7, 10, 15, 19], "DRUID": [4, 5, 10, 13, 15]}
CLASSIC_ARMOR = {"WARRIOR": {1: 0, 2: 0, 3: 0, 4: 40, 6: 0}, "PALADIN": {1: 0, 2: 0, 3: 0, 4: 40, 6: 0},
                 "HUNTER": {1: 0, 2: 0, 3: 40}, "SHAMAN": {1: 0, 2: 0, 3: 40, 6: 0}, "ROGUE": {1: 0, 2: 0},
                 "DRUID": {1: 0, 2: 0}, "PRIEST": {1: 0}, "MAGE": {1: 0}, "WARLOCK": {1: 0}}
for cfile in CLASSIC_WEAPONS:
    if not WEAPONS.get(cfile):
        WEAPONS[cfile] = sum(1 << s for s in CLASSIC_WEAPONS[cfile])
        print("weapons: the client's tables give %s none, Classic's stand in" % cfile)
    if not ARMOR.get(cfile):
        ARMOR[cfile] = dict(CLASSIC_ARMOR[cfile])
        print("armour: the client's tables give %s none, Classic's stand in" % cfile)
    _have = set(s for s in range(21) if WEAPONS[cfile] & (1 << s))
    _more, _less = sorted(_have - set(CLASSIC_WEAPONS[cfile])), sorted(set(CLASSIC_WEAPONS[cfile]) - _have)
    _arm = {k: v for k, v in ARMOR[cfile].items() if k in (1, 2, 3, 4, 6)}
    if _more or _less or _arm != CLASSIC_ARMOR[cfile]:
        print("proficiencies: the client gives %s%s%s%s (Classic differs; the client's tables win)" % (
            cfile, " weapon subclasses +%s" % _more if _more else "", " -%s" % _less if _less else "",
            " armour %s" % _arm if _arm != CLASSIC_ARMOR[cfile] else ""))
lines.append("-- [class] = bitmask of the weapon subclasses it may wield (2^subclass), from the client's skill tables")
lines.append("D.WEAPONS = " + lua({k: WEAPONS[k] for k in sorted(WEAPONS)}))
lines.append("-- [class] = { [armour subclass: 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield] = the level it opens at }")
lines.append("D.ARMOR = " + lua({k: {i: ARMOR[k][i] for i in sorted(ARMOR[k])} for k in sorted(ARMOR)}))
print("reward items: %d quests with items (%d from the survey, %d seen in game only, %d from the Classic database), "
      "%d still unknown; %d items described" % (
          len(RITEMS), len(REWARD_FROM_SURVEY), len(SURVEYED), len(RCLASSIC), len(RUNK), len(RIT)))

# The quests QuestBank asks the game about (Survey.lua): every id in the client's quest table (QuestV2 of the newest
# datamined build) that neither the catalog nor any list has, and the catalog's quests whose rewards no Forever source
# knows yet (nobody's, or only the Classic database's: the game's answer replaces those).
# Three runs of ids, asked in this order: the new Forever range (90000 and above), the catalog's, the rest; and a fourth,
# asked before them, the check: three Forever quests whose items Wowhead lists, so that the addon takes the game's word
# that a quest gives no items only once the game has shown it the items of quests that do. Each run is ascending and
# written as the steps between ids, base 32, a digit from D.ALPHA's second half when more digits follow.
_QV2 = sorted(int(r["ID"]) for r in csv.DictReader(open(os.path.join(REPO, "research", "wago", SURVEY_BUILD, "QuestV2.csv"))))
_NEW = [q for q in _QV2 if q not in Q and q not in LIST]
_QV2_SET = set(_QV2)
SURVEY_CHECK = sorted(q for q in REWARD_FROM_WOWHEAD if q in Q and q in RITEMS and q not in CLASSIC and q in _QV2_SET
                      and (RITEMS[q]["c"] or RITEMS[q]["r"]))[:3]
SURVEY_RUNS = [[q for q in _NEW if q >= 90000], sorted(q for q in Q if q in RUNK or q in RCLASSIC), [q for q in _NEW if q < 90000],
               SURVEY_CHECK]


def survey_enc(ids):
    out, prev = [], 0
    for q in ids:
        step, digits = q - prev, []
        assert step > 0, "ascending ids"
        while True:
            digits.append(step % 32)
            step //= 32
            if not step:
                break
        digits.reverse()
        out.append("".join(ALPHA[d + 32] for d in digits[:-1]) + ALPHA[digits[-1]])
        prev = q
    return "".join(out)


def survey_dec(s):
    out, prev, acc = [], 0, 0
    for ch in s:
        d = ALPHA.index(ch)
        if d >= 32:
            acc = acc * 32 + d - 32
        else:
            prev += acc * 32 + d
            out.append(prev)
            acc = 0
    return out


SURVEY_STR = [survey_enc(run) for run in SURVEY_RUNS]
assert [survey_dec(s) for s in SURVEY_STR] == SURVEY_RUNS, "the survey's ids read back"
lines.append("-- the quests QuestBank asks the game about, in three runs (the new Forever range, the catalog's quests with no Forever")
lines.append("-- rewards known, the client's other ids) and the check asked first (three quests whose items Wowhead lists): each ascending,")
lines.append("-- written as the steps between ids in base 32 over D.ALPHA, a digit from its second half when more digits of the same")
lines.append("-- step follow (Survey.lua reads it)")
lines.append("D.SURVEY = " + lua(SURVEY_STR))
print("survey: %d quest ids to ask the game (%d new Forever ids, %d catalog quests with no Forever rewards known, %d other client ids, %d to check), "
      "%d characters; %d quests read by players (%d catalog quests' rewards from it, %d not in the catalog in the finders)" % (
          sum(len(r) for r in SURVEY_RUNS), len(SURVEY_RUNS[0]), len(SURVEY_RUNS[1]), len(SURVEY_RUNS[2]), len(SURVEY_RUNS[3]),
          sum(len(s) for s in SURVEY_STR), len(SURVEY_PICK), len(REWARD_FROM_SURVEY), len(SURVEYED)))


def survey_selftest():
    """--selftest-survey: the made-up uploads' survey (survey_selftest_input) as the build reads it."""
    assert "Brann" not in json.dumps(DISC["sv"]) and "Hidden" not in json.dumps(DISC["sv"]), "no name, no escape code reaches disc.json"
    assert SURVEY_NO == {99001}, "three unanswered tries count; one doesn't: %s" % SURVEY_NO
    # a catalog quest nobody knew the rewards of takes the survey's lists, split as the game said
    assert 10 in Q and 10 not in RUNK and RITEMS[10] == {"c": [2470, 2435], "r": [2471], "u": None}, RITEMS.get(10)
    assert REWARD[10][1] & 1 and REWARD[10][1] & 64 and REWARD[10][1] & 128 and REWARD[10][0] == 50, REWARD.get(10)
    assert SURVEY_PICK[10]["xp"] == 0, "a reading ten levels above the quest is grey: no XP to take from it"
    # the game's answer stands over the Classic database's
    assert 10 not in RCLASSIC and 10 in REWARD_FROM_SURVEY
    assert all(q not in RCLASSIC for q in REWARD_FROM_SURVEY + REWARD_FROM_WOWHEAD + REWARD_FROM_LOOT)
    # Wowhead Forever's list stands over the survey's
    assert RITEMS[6] == {"c": [6076, 60, 3070], "r": None, "u": None}, RITEMS.get(6)
    # the survey's split beats a loot page's list, and the newest build's list beats an older one with as many votes
    assert RITEMS[704] == {"c": [9535, 9536], "r": None, "u": None} and 704 in REWARD_FROM_SURVEY and 704 not in REWARD_FROM_LOOT, RITEMS.get(704)
    # a quest no list has: in the finders as seen in game, its reward's facts from the item database
    assert 99999 not in Q and SURVEYED[99999] == [51, 6150, "Shimmerwine Shakedown"], SURVEYED.get(99999)
    assert RITEMS[99999] == {"c": [276903], "r": None, "u": None} and REWARD[99999] == [52, 1, 276903], (RITEMS.get(99999), REWARD.get(99999))
    assert SURVEY_OUT == {99995: "no title", 99996: "rewards not read whole", 99997: "no item rewards", 99998: "a placeholder", 99999: None}, SURVEY_OUT
    # an item the item database lacks takes the client's own tables
    _ITEMS.pop("276903", None)
    assert reward_of([276903]) == [52, 1, 276903], reward_of([276903])
    # the ids to ask: three ascending runs, none twice, the catalog's run exactly the quests with no Forever rewards known
    # (none known, or only the Classic database's)
    allq = [q for run in SURVEY_RUNS for q in run]
    assert len(allq) == len(set(allq)) and all(run == sorted(run) for run in SURVEY_RUNS)
    assert len(SURVEY_RUNS[3]) == 3 and all(q in REWARD_FROM_WOWHEAD and (RITEMS[q]["c"] or RITEMS[q]["r"]) for q in SURVEY_RUNS[3]), SURVEY_RUNS[3]
    assert set(SURVEY_RUNS[1]) == {q for q in Q if q in RUNK or q in RCLASSIC} and not (set(SURVEY_RUNS[0]) | set(SURVEY_RUNS[2])) & (set(Q) | set(LIST))
    assert all(q >= 90000 for q in SURVEY_RUNS[0]) and all(q < 90000 for q in SURVEY_RUNS[2])
    assert survey_dec(survey_enc([1, 2, 33, 1057, 99999])) == [1, 2, 33, 1057, 99999]
    print("selftest-survey: OK (%d quests read, %d ids to ask in %d characters)" % (len(SURVEY_PICK), len(allq), sum(len(s) for s in SURVEY_STR)))


if SELFTEST_SURVEY:
    survey_selftest()
    raise SystemExit(0)
lines.append("-- [id] = {{item, how many, name}, ...}: what the quest asks you to bring")
lines.append("D.REQ = " + keyed(REQ))
lines.append("D.RACE = " + keyed(RACE))
lines.append("D.EXCL = " + keyed(EXCL))
# quests the giver offers only to those with a profession or a standing with a faction (the Classic database's
# RequiredSkill, RequiredMinRep and RequiredMaxRep), which nothing here can check yet
QLOCK = {q: v for q, v in ((q, (_SPOTS.get("lock") or {}).get(str(q))) for q in IDS) if v}
lines.append("-- [id] = what the giver checks beyond level, side, class and the chain: \"skill\" a profession, \"rep\" a standing")
lines.append("-- with a faction (at least or at most), \"skill,rep\" both; from the Classic database")
lines.append("D.QLOCK = " + keyed(QLOCK))
lines.append("-- {name, uiMap, x, y, continent (0, 1, an open map's own off them as Zephras Isle's 2991, or -1 inside an instance or on a battleground's island, which keeps its uiMap), world x, world y, Alliance hub, minutes on foot from it, Horde hub, minutes, place}")
lines.append("D.NPC = {\n" + ",\n".join(lua(n) for n in NPCS) + "\n}")
# hand-placed NPCs (CURATED) have no SOURCE: they read as Classic data, the cautious claim
lines.append("-- where each D.NPC place comes from, one letter per NPC: w Wowhead Forever, c the CMaNGOS spawn (Classic data), g players' games")
lines.append('D.NSRC = "%s"' % "".join({"wowhead": "w", "cmangos": "c", "game": "g"}.get(SOURCE.get(i), "c") for i in range(1, len(NPCS) + 1)))
lines.append("D.MAPNAME = " + keyed({m: UIMAP.get(m, "") for m in USED_MAPS}))

hubs, dist = {}, {}
for fac in ("A", "H"):
    order = TR.order[fac]
    # the route planner reads the first five fields (D.NPC's hub fields index these rows); the arrow the rest
    hubs[fac] = [[TR.hubs[fac][h]["town"], TR.hubs[fac][h]["cont"], round(TR.hubs[fac][h]["x"]), round(TR.hubs[fac][h]["y"]),
                  1 if TR.hubs[fac][h]["inn"] else 0] + list(extra) for h, extra in zip(order, TR.hub_extra(fac))]
    for row in hubs[fac]:
        assert row[9] & 1 or (row[5] > 0 and row[6] > 0), "%s %s: a hub with flights needs its TaxiNodes id and map" % (fac, row[0])
    f, w, k = [], [], []
    for a in order:
        for b in order:
            p = TR.pair(fac, a, b)
            if a == b:
                f.append(enc(0)); w.append(enc(0)); k.append("-")
            elif p is None:
                f.append(enc(409.5)); w.append(enc(0)); k.append("-")
            else:
                f.append(enc(p[0])); w.append(enc(p[1])); k.append(KIND.get(p[2], "f"))
    dist[fac] = {"n": len(order), "f": "".join(f), "w": "".join(w), "k": "".join(k)}
lines.append("-- {town, continent, world x, world y, has an inn, TaxiNodes id (0 none), uiMap, map x, map y, flags (1 no flights, 2 druids only, 4 world-PvP tower)}")
lines.append("D.HUB = {A=" + lua(hubs["A"]) + ",\nH=" + lua(hubs["H"]) + "}")
lines.append("-- hub to hub: fixed minutes (flights, boats) and minutes on foot, two characters each (tenths of a minute, base 64), and the main way")
lines.append("D.DIST = {A=" + lua(dist["A"]) + ",\nH=" + lua(dist["H"]) + "}")
lines.append('D.ALPHA = "%s"' % ALPHA)

# the step-by-step arrow (Travel.lua): every flight on its own, the rides between docks, the islands you cannot walk to,
# and where a hearthstone lands
FLY = {fac: "".join(ALPHA[a - 1] + ALPHA[b - 1] + enc(m) for a, b, m in TR.flights_for(fac)) for fac in ("A", "H")}
assert len(FLY["A"]) == 588 and len(FLY["H"]) == 612, "flights changed: A %d, H %d" % (len(FLY["A"]) // 4, len(FLY["H"]) // 4)
lines.append("-- flights, 4 characters each: from and to (the D.HUB index i as D.ALPHA:sub(i, i)), minutes (tenths, base 64, as D.DIST)")
lines.append("D.FLY = " + lua(FLY))
LINK = TR.links()
AREA_NAMES = {r["AreaName_lang"].lower() for r in AREA_ROW.values()}
# the docks on an island: Rut'theran's pier and the portal's lower end at Teldrassil's foot (4), its upper end on the
# canopy (2), Feathermoon's pier on Sardor Isle (3)
DOCK_LAND = {("Rut'theran Village", "b"): 4, ("Rut'theran Village", "p"): 4, ("Darnassus", "p"): 2, ("Auberdine", "b"): 1,
             ("the Forgotten Coast", "b"): 1, ("Feathermoon", "b"): 3}
assert len(LINK) == 10, "rides changed: %d" % len(LINK)
for fac, kind, minutes, a, b, track in LINK:
    for e in (a, b):
        assert e[0] in (0, 1) and e[3], "a %s dock of %s off the continents' maps: %s" % (kind, fac, e)
        assert TR.town_yards(e[6], *e[:3]) is not None or e[6].lower() in AREA_NAMES, "%s is neither a hub nor an area" % e[6]
        want = DOCK_LAND.get((e[6], kind))
        assert want is None or TR.land(*e[:3]) == want, "the %s %s dock is on land %d, not %d" % (e[6], kind, TR.land(*e[:3]), want)
lines.append("-- boats, zeppelins, the tram and the portal: {factions, kind (b boat, z zeppelin, t tram, p portal), minutes of the ride with")
lines.append("-- the wait, end 1, end 2, track}; an end is {continent, world x, world y, uiMap, x, y, its town}, and from end 1 the step reads")
lines.append("-- \"<Kind> to <end 2's town>\". The track is the ride's loop, end 1 to end 2 and back, as \"c,wx,wy;...\" (\"\" for the tram and the portal)")
lines.append("D.LINK = {\n" + ",\n".join(lua([fac, kind, minutes, list(a), list(b), ";".join("%d,%d,%d" % q for q in track)])
                                         for fac, kind, minutes, a, b, track in LINK) + "\n}")
LAND = TR.lands()
for n in NPCS:
    if n[1] in (1438, 1457):
        # Rut'theran Village at the tree's foot (land 4, west of x 9,000: the canopy starts past 9,070), the canopy (2)
        want = 4 if n[5] < 9000 else 2
        assert TR.land(n[4], n[5], n[6]) == want, "%s on Teldrassil is on land %s, not %d" % (n[0], TR.land(n[4], n[5], n[6]), want)
print("on Sardor Isle (land 3, Feathermoon), for review: " + ", ".join(
    "%s (%d %.1f,%.1f)" % tuple(n[:4]) for n in NPCS if n[4] in (0, 1) and TR.land(n[4], n[5], n[6]) == 3))
lines.append("-- islands you cannot walk to: {continent, min x, min y, max x, max y, land}, the first box holding a point its land (4 Rut'theran")
lines.append("-- at Teldrassil's foot, 2 the canopy, 3 Sardor Isle); outside every box a point's land is its continent")
lines.append("D.LAND = " + lua([list(r) for r in LAND]))
# a hearthstone lands at the inn: each innkeeper is named for the hub town with an inn within 400 yd, or by entry where
# the town has no flight master; a new character's lands at its race's starting spot
BIND_BY_ENTRY = {295: "Goldshire", 1247: "Kharanos", 6736: "Dolanaar", 6928: "Razor Hill", 5688: "Brill", 6747: "Bloodhoof Village",
                 15174: "Cenarion Hold", 16256: "Light's Hope Chapel"}
START_AREA = {1: "Northshire Abbey", 2: "Valley of Trials", 3: "Coldridge Valley", 4: "Shadowglen", 5: "Deathknell", 6: "Camp Narache",
              7: "Coldridge Valley", 8: "Valley of Trials"}
BIND = {}
assert _cm.get("innkeepers") and _cm.get("starts"), "cmangos.json has no innkeepers or starting spots: run cmangos.py"
for e, name, c, x, y in _cm["innkeepers"]:
    town = BIND_BY_ENTRY.get(e)
    if not town:
        near = min(((math.hypot(n["x"] - x, n["y"] - y), n["town"]) for n in TR.nodes.values() if n["inn"] and n["cont"] == c), default=None)
        town = near[1] if near and near[0] < 400 else None
    if not town:
        print("innkeeper %d %s (%d, %d, %d) is near no inn town: left out of D.BIND" % (e, name, c, x, y))
        continue
    assert town not in BIND, "two inns named %s" % town
    BIND[town] = [town, c, round(x), round(y)]
for race, c, x, y in _cm["starts"]:
    BIND.setdefault(START_AREA[race], [START_AREA[race], c, round(x), round(y)])
assert all(t.lower() in AREA_NAMES for t in START_AREA.values()), "a starting area's name is not in AreaTable"
lines.append("-- where a hearthstone lands, by town: {town, continent, world x, world y}")
lines.append("D.BIND = " + lua([BIND[t] for t in sorted(BIND)]))
# the names GetBindLocation gives for inns whose area is not named for the town (subzones as AreaTable has them)
BIND_ALIAS = {"thunderbrew distillery": "Kharanos", "gallows' end tavern": "Brill", "deepwater tavern": "Menethil Harbor",
              "stoutlager inn": "Thelsamar", "craftsmen's terrace": "Darnassus", "theramore isle": "Theramore",
              "grom'gol base camp": "Grom'gol", "feathermoon stronghold": "Feathermoon"}
for k, v in BIND_ALIAS.items():
    assert k in AREA_NAMES and v in BIND, "D.BIND_ALIAS %s -> %s: no such area or bind" % (k, v)
lines.append("D.BIND_ALIAS = " + lua(BIND_ALIAS))
lines.append('D.CUT_NOTES = {[1654]="Hand it to Jordan now and keep the forge step instead",[79192]="Carry on up the chain for the Cozy Sleeping Bag",[97894]="Pays 0 XP: abandon it"}')
lines.append("D.TRACKED_ITEMS = " + lua([
    {"id": 211527, "name": "Cozy Sleeping Bag", "need": 1, "icon": 133662},
    {"id": 251522, "name": "Blood-Stained Letter", "need": 1, "quest": 92415, "icon": 133471, "side": 1},
    {"id": 268540, "name": "Bloodied Insignia", "need": 10, "quest": 95195, "icon": 133328, "side": 1},
    {"id": 4371, "name": "Bronze Tube", "need": 1, "quest": 174, "icon": 133024, "side": 1},
]))
# the Cozy Sleeping Bag's quest chain, from level 14 (Wowhead Forever's quest pages, research/questbank/det2.json and
# det3.json). It starts with "... and that note you found", one quest a side, at the Nailed Plank in Westfall (Alliance)
# and the Burned-Out Remains in the Barrens (Horde): 79007 and 79008, either counting as the step done (Wowhead
# Forever's pages give 79008 to the Alliance and 79007 to the Horde; the camp research the other way round). Before
# 5.4.4 the chain started at Stepping Stones and the bag's card never said where to begin
lines.append("D.SLEEP_CHAIN = " + lua([
    {"id": 79007, "alt": 79008, "name": "... and that note you found",
     "A": {"where": "the Nailed Plank, Westfall", "m": 1436, "x": 37.4, "y": 50.9},
     "H": {"where": "the Burned-Out Remains, The Barrens", "m": 1413, "x": 46.4, "y": 73.8}},
    {"id": 79192, "name": "Stepping Stones", "where": "Pocket Litter, Stonetalon Mountains", "m": 1442, "x": 40.7, "y": 52.4},
    {"id": 79980, "name": "Scramble", "where": "Mound of Dirt, Stonetalon Mountains", "m": 1442, "x": 39.6, "y": 49.9},
    {"id": 79974, "name": "Wet Job", "where": "Carved Figurine on the Stonewrought Dam, Loch Modan", "m": 1432, "x": 49.4, "y": 12.9},
    {"id": 79975, "name": "Eagle's Fist", "where": "Messenger Bag on Thoradin's Wall, Arathi Highlands", "m": 1417, "x": 22.4, "y": 24.2},
    {"id": 79976, "name": "This Must Be The Place", "where": "Rolled-Up Satchel, where the bag's note points", "m": None, "x": None, "y": None},
]))
# D.CAMP_SELL: who sells Simple Wood (4470) and Flint and Tinder (4471), what Cooking's Basic Campfire Kit (1229737) is
# made from and with, for the camp bar's burned-out fire (Camp.lua). No vendor sells a campfire kit. The CMaNGOS Classic
# database's sellers (cmangos.py's sellers(): npc_vendor and npc_vendor_template, GPL-3.0), each placed as npc_from
# places a Classic spawn (the map it lies on, a Forever-only map only where hinted; the game's place where players saw
# it more than GAME_MOVE_YD away), for the side whose flight masters wear its faction template, or, a template no flight
# master wears, the side of the flight point nearest it within 1,000 yards. Classic data: Forever may have moved some,
# and the camp bar says so until a player's game has seen the seller.
#   {npc id, name, continent, world x, world y, uiMap, x, y, goods (1 Simple Wood, 2 Flint and Tinder), side (1 Alliance,
#    2 Horde, 3 both)}
_SELL = (_cm.get("sellers") or {})
assert _SELL.get("vendors"), "cmangos.json has no sellers: run cmangos.py --sellers"


def _near_sides(c, wx, wy, within, more=0):
    """The sides of the flight point nearest a spot within some yards, and of any other within `more` yards more of it
    (a town's two flight masters, one a side: Light's Hope, Cenarion Hold, Thorium Point); None with none."""
    near = sorted((math.hypot(n["x"] - wx, n["y"] - wy), n["id"], n) for n in TR.nodes.values() if n["cont"] == c and n["id"] > 0)
    near = [x for x in near if x[0] <= within]
    if not near:
        return None
    return set().union(*(n["fac"] for d, _, n in near if d <= near[0][0] + more))


_TEMPLATE_SIDE = {}
for _e, _faction, _spots in _SELL.get("masters") or []:
    for _c, _x, _y in _spots:
        _sides = _near_sides(_c, _x, _y, 80)  # (a flight master stands at its own side's flight point)
        if _sides:
            _TEMPLATE_SIDE.setdefault(_faction, set()).update(_sides)
CAMP_SELL, _SELL_OUT = [], []
for _e, _name, _sub, _faction, _goods, _spots in _SELL["vendors"]:
    _c, _wx, _wy = _spots[0]
    _side = _TEMPLATE_SIDE.get(_faction)
    if not _side:
        _side = _near_sides(_c, _wx, _wy, 1000, 150)
    _loc = TR.locate(_c, _wx, _wy)
    if _loc and _loc[0] in OVERLAY:
        _at = spot_map(_c, _wx, _wy)
        _loc = (_at[0], round(_at[1], 1), round(_at[2], 1)) if _at else _loc
    if not (_side and _loc):
        _SELL_OUT.append(_name)
        continue
    _m, _x, _y, _moved = game_place("npc", _e, _loc[0], _loc[1], _loc[2])
    if _moved:
        _c, _wx, _wy = TR.world(_m, _x, _y)
    CAMP_SELL.append([_e, _name, _c, int(round(_wx)), int(round(_wy)), _m, round(_x, 1), round(_y, 1),
                      (1 if 4470 in _goods else 0) + (2 if 4471 in _goods else 0), (1 if "A" in _side else 0) + (2 if "H" in _side else 0)])
lines.append("D.CAMP_SELL = {\n" + ",\n".join(lua(r) for r in CAMP_SELL) + "\n}")
print("camp sellers: %d of %d placed (%d Alliance, %d Horde, %d both)%s" % (
    len(CAMP_SELL), len(_SELL["vendors"]), sum(1 for r in CAMP_SELL if r[9] == 1), sum(1 for r in CAMP_SELL if r[9] == 2),
    sum(1 for r in CAMP_SELL if r[9] == 3), ("; no side or map: " + ", ".join(_SELL_OUT)) if _SELL_OUT else ""))
lines.append("")
# D.TRAINER: the class trainers, for the Guide's "Train at <name>" step (Guide.lua). CMaNGOS Classic spawns (GPL-3.0),
# each placed as a camp seller is (TR.locate, overlays through spot_map, the game's place where players saw the NPC
# more than GAME_MOVE_YD away): {npc id, name, class id (1 Warrior, 2 Paladin, 3 Hunter, 4 Rogue, 5 Priest, 7 Shaman,
# 8 Mage, 9 Warlock, 11 Druid), continent, world x, world y, uiMap, x, y}. One row per spawn on the two continents
TRAINERS, _TRAIN_OUT = [], 0
for _e, _name, _cls, _spots in (_cm.get("trainers") or []):
    for _c, _wx, _wy in _spots:
        if _c not in (0, 1):
            continue
        _loc = TR.locate(_c, _wx, _wy)
        if _loc and _loc[0] in OVERLAY:
            _at = spot_map(_c, _wx, _wy)
            _loc = (_at[0], round(_at[1], 1), round(_at[2], 1)) if _at else _loc
        if not _loc:
            _TRAIN_OUT += 1
            continue
        _m, _x, _y, _moved = game_place("npc", _e, _loc[0], _loc[1], _loc[2])
        if _moved:
            _c, _wx, _wy = TR.world(_m, _x, _y)
        TRAINERS.append([_e, _name, _cls, _c, int(round(_wx)), int(round(_wy)), _m, round(_x, 1), round(_y, 1)])
assert len(TRAINERS) > 50, "cmangos.json has no class trainers: run cmangos.py --trainers"
lines.append("-- the class trainers (CMaNGOS Classic spawns, GPL-3.0): {npc id, name, class id (1 Warrior, 2 Paladin, 3 Hunter, 4 Rogue,")
lines.append("-- 5 Priest, 7 Shaman, 8 Mage, 9 Warlock, 11 Druid), continent, world x, world y, uiMap, x, y}; the Guide's Train step (Guide.lua)")
lines.append("D.TRAINER = {\n" + ",\n".join(lua(r) for r in TRAINERS) + "\n}")
print("class trainers: %d placed, %d not on a map" % (len(TRAINERS), _TRAIN_OUT))
lines.append("")


# D.SPELL_LV: the levels each class learns a new spell at, from the site's spellbook (codex/spellbook.json, built by
# tools/build_spellbook.py from the Forever client's tables; first ranks only, so a Train step comes at those levels):
# the Guide adds a Train step at those levels
def spell_levels():
    book = load_json(os.path.join(REPO, "codex", "spellbook.json"), {}) or {}
    tok = {"Warrior": "WARRIOR", "Paladin": "PALADIN", "Hunter": "HUNTER", "Rogue": "ROGUE", "Priest": "PRIEST",
           "Shaman": "SHAMAN", "Mage": "MAGE", "Warlock": "WARLOCK", "Druid": "DRUID"}
    out = {}
    for sp in book.get("spells") or []:
        t = tok.get(sp.get("c"))
        lv = sp.get("lvl")
        if t and sp.get("src") == "client" and isinstance(lv, int) and 1 <= lv <= MAXLVL:
            out.setdefault(t, set()).add(lv)
    return {t: sorted(v) for t, v in out.items()}


SPELL_LV = spell_levels()
assert len(SPELL_LV) == 9 and all(len(v) >= 10 for v in SPELL_LV.values()), "spellbook.json gives too few learn levels: %r" % {k: len(v) for k, v in SPELL_LV.items()}
lines.append("-- [class token] = the levels the class learns a new spell at (codex/spellbook.json, the Forever client's tables)")
lines.append("D.SPELL_LV = {\n" + ",\n".join("%s = {%s}" % (t, ",".join(str(l) for l in SPELL_LV[t])) for t in sorted(SPELL_LV)) + "\n}")
lines.append("")
os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, "w").write("\n".join(lines))
# ---------------------------------------------------------------------------
# GAPS.md: everything still missing, so nobody has to take the numbers on trust
# ---------------------------------------------------------------------------


def quest_name(qid):
    return (QN.get(qid) or (LIST.get(qid) or {}).get("name") or (QTIPS.get(str(qid)) or {}).get("name")
            or ((DISC.get("q") or {}).get(str(qid)) or {}).get("t") or "?")


def why_out(qid):
    """Why a quest we looked for isn't in the catalog, from what the inputs say about it."""
    why = []
    twins = [o for o in IDS if qid in BIT and o != qid and BIT.get(o) == BIT[qid]]
    if twins:
        why.append("shares its completion bit with %s, which the catalog has (the game marks both done together)" % (
            ", ".join("%d %s" % (o, quest_name(o)) for o in twins)))
    if qid in NOT_IN_FOREVER:
        why.append("players report it isn't in Forever")
    elif qid in LIST:
        d, q = DET.get(qid) or {}, LIST[qid]
        if not d.get("startId") and not d.get("endId") and qid not in SEEN:
            what = ", ".join(x for x in ("level %d" % q["level"] if q.get("level") else "",
                                         "needs %d" % q["reqlevel"] if q.get("reqlevel") else "",
                                         AREAS.get(q.get("category"), "")) if x)
            why.append("Wowhead Forever lists it%s with no giver%s, and no player has met it" % (
                " (%s)" % what if what else "", " or ender" if d.get("base") or q.get("xp") else ", ender or XP"))
        else:
            why.append("left out by the catalog's filters")
    else:
        where = " and ".join(x for x in ("in the client" if qid in BIT else "",
                                         "on Wowhead's tooltips" if (QTIPS.get(str(qid)) or {}).get("name") else "") if x)
        why.append((where + ", " if where else "") + "no level, side or NPC yet")
    if qid not in BIT:
        # QuestV2 has no row for some quests the game does offer: players have met catalog quests that lack one
        why.append("the client's quest table (QuestV2, build %s) has no row for it, which alone doesn't rule it out "
                   "(%d quests in the catalog have none either)" % (BUILD, sum(1 for o in Q if o not in BIT)))
    return "; ".join(why)


def build_notes():
    """GAPS.md lines on what the newest build and Blizzard's notes changed, and the quests we looked for."""
    out = []
    if HAND:
        out.append("Written by hand where no list we read has the quest yet (each fact's source is in gen_data.py): %s." % ", ".join(
            "%d %s (level %d and needs %d from ForeverChanges' quest list, giver %s, XP %s)" % (
                q, quest_name(q), Q[q][0], Q[q][1], "unknown" if not Q[q][6] else "from Wowhead", "unknown" if Q[q][9] & 64 else "known")
            for q in sorted(HAND) if q in Q))
    if REQ_STATED:
        out.append("Blizzard's notes of 2026-10-08: the new Gelkis and Magram quests \"beginning with Valley of Bones\" need level 35 (was 30), "
                   "where the catalog had the level players took them at before that build (flag 32768): %s." % (
                       ", ".join("%d %s" % (q, quest_name(q)) for q in sorted(REQ_STATED))))
    changed = sorted(q for q in NOTE if q in Q and (q in CHANGED_1008 or NOTE[q] == TIRISFAL_NOTE))
    if changed:
        out.append("Changed in the 8 October build and not read since, which the tooltip says (Blizzard's notes): %s." % ", ".join(
            "%d %s (%s)" % (q, quest_name(q), "its XP" if q in CHANGED_1008 else "its level") for q in changed))
    groups = sorted(BIT_GROUPS.values())
    new = [g for g in groups if BIT_PREV and len({BIT_PREV.get(q) for q in g}) > 1]
    out.append(("Quests that share one completion bit in the client (QuestV2, build %s: doing one marks the others done), ruled out "
                "against each other: %d groups, %d quests; %d of them weren't paired by the Classic database.%s%s") % (
        BUILD, len(groups), sum(len(g) for g in groups), len(BIT_EXCL),
        (" Shared since this build: %s." % "; ".join(", ".join("%d %s" % (q, quest_name(q)) for q in g) for g in new)) if new else "",
        (" Class taken from same-named twins: %s." % ", ".join("%d %s" % (q, quest_name(q)) for q in sorted(BIT_CLASS))) if BIT_CLASS else ""))
    look = (load("lookfor.json", {}) or {}).get("ids") or []
    if look:
        have = [q for q in look if q in Q]
        out.append(("Forever quests looked for on 2026-10-08 (lookfor.json, %d): %d in the catalog (%s); %d not yet. A quest's level, "
                    "side, NPCs and XP come from its Wowhead Forever page, which turns scripts away since 2026-10-04, or from players' "
                    "games: these come in as soon as someone's QuestBank sees them.") % (
            len(look), len(have), ", ".join("%d %s" % (q, quest_name(q)) for q in have), len(look) - len(have)))
        out.append("")
        for q in look:
            if q not in Q:
                out.append("- %d %s: %s" % (q, quest_name(q), why_out(q)))
    out.append("")
    return out


def gap_report():
    def name(q):
        return "%d %s" % (q, LIST[q]["name"])
    side_name = {0: "both", 1: "Alliance", 2: "Horde"}
    with_xp = [q for q in IDS if Q[q][3] > 0]
    forever = [q for q in with_xp if q not in CLASSIC]
    classic = [q for q in with_xp if q in CLASSIC]

    def checks(lst):
        return {
            "no_page": [q for q in lst if Q[q][9] & 8],
            "no_turn": [q for q in lst if not Q[q][5]],
            # (an NPC on a battleground's island off the continents has no continent either, but isn't inside a dungeon)
            "inside": [q for q in lst if Q[q][5] and NPCS[Q[q][5] - 1][4] < 0 and NPCS[Q[q][5] - 1][1] not in ISLANDS],
            "no_give": [q for q in lst if not Q[q][6] and not (Q[q][9] & 4)],
            "no_chain": [q for q in lst if not chain_known(q)],
        }
    F, C = checks(forever), checks(classic)
    from_cm = sorted({i for i, src in SOURCE.items() if src == "cmangos"})
    out = ["# QuestBank data gaps", "",
           "Written by `gen_data.py` on every run from the inputs it had (Wowhead Forever read %s, Forever client %s," % (READ, BUILD),
           "CMaNGOS Classic database). The catalog covers levels 1 to %d. Wowhead Forever only knows the quests its players have met," % MAXLVL,
           "which stops near the beta's level cap; the Classic database seeds the rest, labelled \"Classic only\" in the addon until",
           "players see those quests in Forever. Anything listed here is a quest the addon can't fully plan yet.", "",
           "| Check | Forever data | Missing | Classic seed | Missing |", "|---|---|---|---|---|",
           "| Forever XP multiplier read from its Wowhead Forever page | %d | %d | %d | %d |" % (len(forever), len(F["no_page"]), len(classic), len(C["no_page"])),
           "| Turn-in NPC with a position | %d | %d | %d | %d |" % (len(forever), len(F["no_turn"]), len(classic), len(C["no_turn"])),
           "| Turn-in inside a dungeon (hand in on the way, not on the route) | %d | %d | %d | %d |" % (len(forever), len(F["inside"]), len(classic), len(C["inside"])),
           "| Quest giver with a position (quests that start from an item don't need one) | %d | %d | %d | %d |" % (len(forever), len(F["no_give"]), len(classic), len(C["no_give"])),
           "| Chain known (Wowhead Forever series or the Classic database) | %d | %d | %d | %d |" % (len(forever), len(F["no_chain"]), len(classic), len(C["no_chain"])),
           "", ("On %s Blizzard cut dungeon-quest XP: \"50%% less extra experience beyond normal quest values\". Wowhead Forever's pages "
                "still show the old multipliers, so every multiplier above x1 is computed as 1 + (read - 1) x %s until they are re-read; "
                "the addon says so in the quest tooltip. Hand-ins on 2026-10-02 paid exactly that on every multiplied quest, dungeon-typed "
                "or not.") % (NERF_DATE, NERF) if NERF != 1 else "",
           ("What the game paid after the cut (players' hand-ins and quest windows on build %d or later, flag 512): %d quests confirmed "
            "(within 5%% counts as agreement%s), %d corrected to the game's number%s, %d with no XP in the catalog filled in%s.") % (
               NERF_BUILD, len(SEEN_OK),
               ("; small differences kept as read: " + ", ".join("%d %s %s, paid %s" % (q, QN[q], c, g) for q, c, g in SEEN_NEAR)) if SEEN_NEAR else "",
               len(SEEN_FIX), (": " + ", ".join("%d %s %s -> %s" % (q, QN[q], c, g) for q, c, g in SEEN_FIX)) if SEEN_FIX else "",
               len(SEEN_FILL), (": " + ", ".join("%d %s" % (q, QN[q]) for q in SEEN_FILL)) if SEEN_FILL else ""),
           "", ("Readings taken under a temporary +3%% XP buff on the player (the game's number times 1.03, give or take one: 390 shows 401) "
                "count as the game's number: %d readings on %d quests.") % (len(UNBUFFED), len({q for q, _, _ in UNBUFFED})),
           "", "Dungeon quests nobody has read take their dungeon's multiplier when the read ones agree (as read; before the cut unless marked): %s." % (
               ", ".join("%s x%s%s" % (CATS[c - 1]["name"], m, " (read after the cut)" if DMULT_POST.get(c) else "") for c, m in sorted(DMULT.items(), key=lambda kv: CATS[kv[0] - 1]["name"])) or "none"),
           "", "Every quest in the catalog is one the game offers: placeholders (<UNUSED>, <NYI>, test quests), war efforts, invasions,",
           "holidays, repeatable turn-ins, raids and battlegrounds are left out. The crafting writs' deliveries stay for the reward finders",
           "alone (%d quests: %d of Forever's crafting orders, %d of the Argent Dawn's; no XP, never suggested)." % (
               len([q for q in Q if Q[q][9] & 131072]), len([q for q in Q if Q[q][9] & 131072 and q >= 90000]),
               len([q for q in Q if Q[q][9] & 131072 and q < 90000])),
           "", "NPC positions: %d from Wowhead Forever, %d from the CMaNGOS spawn table where Wowhead has none." % (
               sum(1 for v in SOURCE.values() if v == "wowhead"), len(from_cm)),
           "Forever redrew Mulgore, Eastern Plaguelands, Redridge and Stormwind: %d Wowhead coordinates there were in the old" % FRAME.fixed,
           "Classic frame and were moved to Forever's; %d were already in Forever's." % FRAME.kept,
           "Instant follow-ups planned on the day: %d. Race-limited quests: %d. Quests in mutually exclusive groups: %d." % (
               len(FOLLOW), len(RACE), len(EXCL)),
           "Turn-in NPCs found by the name in the quest's objective, where Wowhead links none: %d." % len(TEXT_NAMED),
           ("World map icons: objective spots for %d quests (%d from CMaNGOS spawns, %d from its quest outlines only, %d from "
            "Wowhead Forever's quest pages, %d from players' games alone; %d more have players' spots beside those); %d quests "
            "that start from an item show where it drops. %d quests need a profession or a reputation the addon can't check.") % (
               len(SPOT), SPOT_FROM["c"], SPOT_FROM["p"], SPOT_FROM["w"], SPOT_FROM["G"], SPOT_FROM["g"], len(START), len(QLOCK)), ""]
    if DISC:
        _in = set(IDS)
        _unknown = sorted(q for q in SEEN if q not in _in)
        out.append("Seen in Forever by players (%d uploads merged by probe_pull.py, %s): %d quests, %d of them Classic seeds now confirmed." % (
            (DISC.get("meta") or {}).get("uploads") or 0, (DISC.get("meta") or {}).get("pulled") or "?", len(SEEN),
            sum(1 for q in SEEN if q in _CMQ_IDS and q not in LIST_WOWHEAD)))
        if _unknown:
            out.append("Seen in game but not in the catalog (%d): %s." % (len(_unknown), ", ".join(
                "%d %s (%s)" % (q, (DISC["q"].get(str(q)) or {}).get("t") or "?",
                                "too little to place: no NPC with a position" if q in DISC_UNPLACED else
                                "a battleground quest: its giver gives only PvP quests" if q in DISC_PVP else
                                "left out on purpose by the catalog's filters")
                for q in _unknown[:60])))
        out.append("")
        out.append("Every upload so far is one account's growing QuestBank.lua: what follows rests on one witness.")
        if DISC_ONLY:
            out.append("Added from players' notes alone (flag 16384; required level is the lowest anyone took it at): %s." % ", ".join(
                "%d %s (level %d, %s, %s)" % (q, QN.get(q, "?"), Q[q][0], ("%d XP" % round_xp(lua_round(Q[q][3] * Q[q][4]))) if Q[q][3] else "XP unknown",
                                               "ender unknown" if not Q[q][5] else "ender known") for q in sorted(DISC_ONLY) if q in Q))
        if DISC_LINKED:
            out.append("Givers and enders filled in from what players' games showed: %s." % ", ".join(
                "%d %s %s" % (q, "giver" if w == "from" else "ender", k) for q, w, k in DISC_LINKED))
        out.append("NPC positions from players' games (the spot where they stood, a few yards off): %d agree with the catalog within %d yd "
                   "(median %.1f yd); %d moved to where the game saw them%s; %d placed from the game alone%s." % (
                       len(GAME_AGREE), GAME_MOVE_YD, sorted(GAME_AGREE.values())[len(GAME_AGREE) // 2] if GAME_AGREE else 0, len(set(GAME_MOVED)),
                       (": " + ", ".join("%s %d by %d yd" % (k, i, d) for k, i, d in sorted(set(GAME_MOVED)))) if GAME_MOVED else "",
                       len(set(GAME_FILLED)), (": " + ", ".join("%s %d" % (k, i) for k, i in sorted(set(GAME_FILLED)))) if GAME_FILLED else ""))
        out.append("Quest reward items: %s." % ", ".join("%s %d" % (k, v) for k, v in RSRC.most_common()))
        out.append(("Quest survey (QuestBank asks the game by quest id, out of combat, a couple a second): %d ids on the list "
                    "(%d new Forever ids, %d catalog quests with no Forever rewards known, %d other ids in the client's quest table, and %s to "
                    "check the game's answers against Wowhead's lists); "
                    "%d quests read by players, %d of the catalog's took their rewards from it, %d not in the catalog are in the "
                    "finders as \"Seen in game\" (listed at the end); the game never answered about %d ids.") % (
                       sum(len(r) for r in SURVEY_RUNS), len(SURVEY_RUNS[0]), len(SURVEY_RUNS[1]), len(SURVEY_RUNS[2]),
                       ", ".join("%d %s" % (q, QN.get(q, "?")) for q in SURVEY_RUNS[3]),
                       len(SURVEY_PICK), len(REWARD_FROM_SURVEY), len(SURVEYED), len(SURVEY_NO)))
        if REWARD_FROM_LOOT:
            out.append("Rewards taken from the dungeon loot pages where Wowhead lists none (%d): %s." % (
                len(REWARD_FROM_LOOT), ", ".join("%d %s" % (q, QN.get(q, "?")) for q in REWARD_FROM_LOOT)))
        if GAME_LEVEL_FIX:
            out.append("Quest levels as the game's quest log shows them, where the catalog had another: %s." % ", ".join(
                "%d %s %d -> %d" % (q, QN.get(q, "?"), a, b) for q, a, b in GAME_LEVEL_FIX))
        if GAME_SIDE:
            out.append("Sides corrected by what the game showed an Alliance character: %s; 79362's Alliance ender is c268 (Darkshire), the Horde one stays Wowhead's, and Paladins take it as Shamans do." % (
                ", ".join("%d %s" % (q, QN.get(q, "?")) for q in sorted(GAME_SIDE))))
        _pre_of = {q: {p for g in immediate_pre(q) for p in g} for q in Q}
        _review = []
        for _pair in sorted(DISC.get("chain") or {}):
            _a, _, _b = _pair.partition(">")
            if not (_a.isdigit() and _b.isdigit()):
                continue
            _a, _b = int(_a), int(_b)
            if _a in Q and _b in Q and _b not in DISC_ONLY and _a not in _pre_of.get(_b, set()) and not chain_known(_b):
                _review.append("%d>%d" % (_a, _b))
        if _review:
            out.append("Chain steps players' games suggest for quests with no known chain, not taken (the window of the next quest opened at the same NPC "
                       "within 8 s of a hand-in, which a reopened quest also does): %s." % ", ".join(_review))
        out.append("")
    out += build_notes()
    out.append("Multipliers from ForeverChanges where Wowhead's page wasn't read: %d. Where both have a number, they disagree on %d:" % (
        len(FROM_FC), len(DISAGREE)))
    out.append("")
    for qid, wh, fc in DISAGREE:
        out.append("- %s: Wowhead %d, ForeverChanges %d" % (name(qid), wh, fc))
    out.append("")
    sections = (("Forever data: multiplier not read", F["no_page"]), ("Forever data: no turn-in position", F["no_turn"]),
                ("Forever data: turned in inside a dungeon", F["inside"]), ("Forever data: no quest giver position", F["no_give"]),
                ("Forever data: new in Forever with no chain on Wowhead, planned as a quest on its own", F["no_chain"]),
                ("Classic seed: no turn-in position", C["no_turn"]), ("Classic seed: turned in inside a dungeon", C["inside"]))
    for title, lst in sections:
        out.append("## %s (%d)" % (title, len(lst)))
        out.append("")
        for q in lst[:400]:
            out.append("- %s (level %d, %s)" % (name(q), Q[q][0], side_name[Q[q][2]]))
        if len(lst) > 400:
            out.append("- and %d more" % (len(lst) - 400))
        out.append("")
    # what the survey read about quests the catalog doesn't have, each with why it is or isn't in the finders
    out.append("## Surveyed in game, not in the catalog (%d)" % len(SURVEY_OUT))
    out.append("")
    for q, why in sorted(SURVEY_OUT.items()):
        sv = SURVEY_PICK[q]
        items = [i for i in (sv["c"] or []) + (sv["r"] or [])]
        what = ", ".join("%s %d" % ((_ITEMS.get(str(i)) or {}).get("name") or "item", i) for i in items[:6])
        out.append("- %d %s (%s%s): %s" % (q, sv["t"] or "?", "level %d" % sv["lv"] if sv["lv"] else "no level",
                                           "; " + what if what else "", why or "in the finders as seen in game"))
    out.append("")
    open(os.path.join(HERE, "GAPS.md"), "w").write("\n".join(out))
    return len(forever), len(F["no_page"]), len(F["no_turn"]), len(F["inside"]), len(F["no_give"]), len(F["no_chain"]), len(classic)


g = gap_report()
# how complete the data is, for the addon's own tooltip
with open(OUT, "a") as f:
    f.write("D.STATS = %s\n" % lua({"quests": g[0], "noMult": g[1], "noTurn": g[2], "inside": g[3], "noChain": g[5], "classic": g[6]}))
routable = sum(1 for v in Q.values() if v[5] and NPCS[v[5] - 1][4] >= 0)
by_side = {s: sum(1 for v in Q.values() if v[2] == s) for s in (0, 1, 2)}
print("wrote %s: %d bytes, %d quests (both %d, Alliance %d, Horde %d), %d routable, %d without a read multiplier, %d NPCs, %d categories"
      % (OUT, os.path.getsize(OUT), len(Q), by_side[0], by_side[1], by_side[2], routable, unconfirmed, len(NPCS), len(CATS)))
print("gaps over %d Forever quests: %d multipliers, %d turn-ins, %d inside dungeons, %d givers, %d chains; %d Classic-only quests (GAPS.md)" % g)
print("redrawn maps: %d Wowhead coordinates moved from the Classic frame to Forever's, %d already in Forever's" % (FRAME.fixed, FRAME.kept))
print("open maps off the two continents: %s; %d NPCs placed there, %d zone cards" % (sorted(OPEN_MAPS), sum(1 for n in NPCS if n[4] in OPEN_MAPS), len(OPEN_CAT)))
print("map icons: objective spots for %d quests (%d from CMaNGOS spawns, %d from its quest POIs only, %d from Wowhead Forever, "
      "%d from players' games alone, %d more with players' spots; %d players' areas inside a Classic or Wowhead one left out), "
      "%d spots on %d maps; %d quests that start from an item show where it drops; %d names; islands: %d givers and %d turn-ins on their map" % (
          len(SPOT), SPOT_FROM["c"], SPOT_FROM["p"], SPOT_FROM["w"], SPOT_FROM["G"], SPOT_FROM["g"], len(GAME_FOLDED),
          sum(v.count(";") + 1 for v in SPOT.values()),
          len({p.split(",")[2] for v in SPOT.values() for p in v.split(";")}), len(START), len(SN),
          sum(1 for v in Q.values() if v[6] and NPCS[v[6] - 1][1] in ISLANDS), sum(1 for v in Q.values() if v[5] and NPCS[v[5] - 1][1] in ISLANDS)))
