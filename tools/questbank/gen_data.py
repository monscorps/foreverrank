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
Travel: travel.py over the client's own taxi tables (build below).
World map icons: where each objective is done, per objective, from the CMaNGOS spawns and quest POIs
(objectives.py -> spots.json), else Wowhead Forever's quest-page mapper (mapper.py -> mapper.json, read when
present), each spot stored on the one map it is drawn on.
Icons and textures: file IDs from the Forever client's interface manifest; a missing one stops the build.

  python3 tools/questbank/gen_data.py            # write Data.lua
  python3 tools/questbank/gen_data.py --fetch    # first fetch the NPC tooltips we lack (nether.wowhead.com)
  python3 tools/questbank/gen_data.py --selftest-os  # check players' objective spots, probe_pull.py's merge to D.SPOT
                                                     # (its own fixture and made-up uploads; writes nothing)
"""
import collections, csv, json, math, os, re, sys
from travel import Travel, DETOUR, RUN

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "QuestBank", "Data.lua")
REPO = os.path.dirname(os.path.dirname(HERE))
RAW = os.path.join(REPO, "research", "questbank")
BUILD = "1.60.1.70170"
READ = "2026-09-29"
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
    16611: ("ruinsoflordaeron", "Tirisfal Glades", None), 16919: ("dungeon", "", None),
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
# Forever's client descends from Season of Discovery and carries its leftovers: Wowhead lists quests
# whose NPCs were never put into Forever. Players' reports settle it quest by quest:
NOT_IN_FOREVER = {78132, 78133, 78134}  # Alonso's Dragonslayer quests: no Alonso in Ashenvale (owner, 2026-09-30)
# City of Dalaran (Wowhead area 16544): its quests are in the data, the dungeon is not open yet (Blizzard, 2026-10-01:
# "will come in a future beta update"); drop this line when it opens
NOT_IN_FOREVER |= {92456, 92489, 96986, 96987, 96988}
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
    if not (1 <= (_lvl or 0) <= MAXLVL) or (_c["min"] or 0) > MAXLVL or _sort in EVENTS or (_c.get("special") or 0) & 1:
        continue
    if _c.get("type") in (41, 62, 88, 89) or not _c.get("starts") or not _c.get("ends"):
        continue
    _rec = classic_record(_qid, _c)
    if _rec["category2"] in (3, 6) or _rec["xp"] <= 0 or not (_c["level"] and _c["level"] > 0):
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


for _k, _dq in _DISC_Q.items():
    if not isinstance(_dq, dict) or not str(_k).isdigit():
        continue
    _qid = int(_k)
    if _qid in LIST or _qid in NOT_IN_FOREVER or not _dq.get("lv") or not (1 <= int(_dq["lv"]) <= MAXLVL):
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
        continue  # a retired Classic ID (The Glowing Shard is 6981, not 3366): nobody gives or takes it
    if not (1 <= qlevel(qid) <= MAXLVL) or (q.get("reqlevel") or 0) > MAXLVL:
        continue
    if qlevel(qid) >= MAXLVL and not base_xp(qid):
        continue  # client leftovers Wowhead lists at level 60 with no XP (Craftsman's Writs and the like)
    IDS.append(qid)
IDS.sort()


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
# Open maps off the two continents (Zephras Isle, the Darkspear Islands): an NPC there keeps its map and place for
# the world map's icons, but no continent and no flight hub (continent -1, as inside an instance), so the route
# leaves it out as before
ISLANDS = {2521, 2524}


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
TEXT_NAMED = []


def npc_by_text(qid, zone):
    """Wowhead links no NPC, but the objective names one: "bring them to Captain Stoutfist in Menethil"."""
    import re
    d = DET.get(qid) or {}
    text = d.get("obj") or ""
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
CATS, CAT_AT = [], {}
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
    if not d and mult is None or mult is None:
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
    if isinstance(v, dict): return "{" + ",".join("%s=%s" % (k, lua(x)) for k, x in v.items() if x is not None) + "}"
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
         "-- chains, quest givers and spawn points. QuestBank is free software under the GPL-3.0 (LICENSE.txt).",
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
}.items()}
T.update({"hearth": icon("inv_misc_rune_01"), "mount": icon("ability_mount_ridinghorse"), "foot": icon("ability_rogue_sprint"),
          "sleep": 133662, "hourglass": icon("inv_misc_pocketwatch_01"), "gryphon": icon("ability_mount_gryphon_01"),
          "wyvern": icon("ability_mount_wyvern_01"), "boat": icon("inv_misc_anchor"), "tram": icon("inv_gizmo_02"),
          "zeppelin": icon("inv_zeppelinmount"), "portal": icon("spell_arcane_portaldarnassus"),
          "unknown": icon("inv_misc_questionmark"), "questGeneric": icon("inv_misc_note_01"), "map": icon("inv_misc_map_01"),
          "party": icon("inv_misc_groupneedmore"), "rally": icon("ability_warrior_rallyingcry"), "letter": icon("inv_letter_15"),
          "note": icon("inv_misc_note_06"), "start": icon("inv_misc_coin_01")})
lines.append("D.TEX = " + lua(T))
lines.append("D.CAT = {\n" + "\n".join("  " + lua(c) + "," for c in CATS) + "\n}")
lines.append("-- [id] = {quest level, required level, side (1 Alliance, 2 Horde, 0 both), Classic base XP, Forever multiplier,")
lines.append("--         turn-in NPC, quest giver, category, class mask, flags (1 dungeon, 2 group, 4 starts from an item, 8 multiplier not read,")
lines.append("--         16 Classic only: not in Wowhead Forever's data yet, 32 multiplier taken from its dungeon's other quests,")
lines.append("--         64 XP not known yet, 128 a Season of Discovery leftover: its NPC hasn't been met in Forever,")
lines.append("--         256 multiplier computed from the pre-2026-10-01 read: the extra above x1 halved, not yet re-read,")
lines.append("--         512 XP as the game paid it after the cut: a hand-in or quest window on build 70170 or later,")
lines.append("--         1024 a wanted poster, 2048 an escort, 4096 repeatable (never suggested), 8192 kept as read: the game paid within a few percent of it after the cut,")
lines.append("--         16384 known only from players' notes: level, NPCs and XP as their games showed them; needs = the lowest level anyone took it at)}")
lines.append("D.Q = {\n" + ",\n".join("[%d]=%s" % (k, lua(v)) for k, v in sorted(Q.items())) + "\n}")
lines.append("D.QN = " + keyed(QN))
lines.append("D.STEPNAME = " + keyed(STEPNAME))
lines.append("D.QITEM = " + keyed(QITEM))
lines.append("D.QICON = " + keyed(QICON))
lines.append("D.TIPS = " + keyed(TIPS))
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

# what a quest rewards, for the finder: the best item level among its reward items, what kinds they are
# (1 gear, 2 trinket, 4 ring or neck, 8 recipe, 16 bag, 32 consumable, 64 cloth, 128 leather, 256 mail, 512 plate offered), and the id of the best piece
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
REWARD_FROM_LOOT = []
REWARD = {}
for qid in IDS:
    q = LIST[qid]
    ids = [x[0] for x in (q.get("itemrewards") or []) + (q.get("itemchoices") or []) if isinstance(x, list) and x]
    _nm = str(q.get("name") or "").strip().lower()
    if not ids and _nm in _LOOT_Q and _NAME_COUNT.get(_nm) == 1:
        ids = sorted(_LOOT_Q[_nm])
        REWARD_FROM_LOOT.append(qid)
    best, kinds, bestId = 0, 0, 0
    for iid in ids:
        it = _ITEMS.get(str(iid))
        if not it or it.get("est"):
            continue  # unknown, or a Classic estimate nobody has seen in Forever: no item level to promise
        cat, slot = str(it.get("cat") or ""), str(it.get("slot") or "")
        ilvl = int(it.get("itemLevel") or 0)
        if cat in ("armor", "weapon", "accessory", "offhand"):
            kinds |= 1
            if ilvl > best:
                best, bestId = ilvl, int(iid)
        # the armour class of the pieces offered, so the finder can leave out what you can't wear
        kinds |= {"Cloth": 64, "Leather": 128, "Mail": 256, "Plate": 512}.get(str(it.get("type") or ""), 0)
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
    if kinds:
        REWARD[qid] = [best, kinds, bestId]
lines.append("-- [id] = { best item level among the rewards, kinds (1 gear, 2 trinket, 4 ring or neck, 8 recipe, 16 bag, 32 consumable, 64 cloth, 128 leather, 256 mail, 512 plate), best item }")
lines.append("D.REWARD = " + keyed(REWARD))
# Every reward item a quest gives, for the tooltip and for linking in chat: what players' quest windows showed
# (QuestBank 3.5.7+, newest upload), else Wowhead's quest list (it always carries both lists, so an empty pair means
# no items), else the dungeon loot pages by quest name. c = choose one, r = always given. D.RUNK: nobody knows yet.
RITEMS, RUNK, RSRC = {}, {}, collections.Counter()
for qid in IDS:
    q = LIST[qid]
    rw = ((DISC.get("q") or {}).get(str(qid)) or {}).get("rw")
    c = r = None
    u = []
    if isinstance(rw, dict) and (isinstance(rw.get("c"), list) or isinstance(rw.get("r"), list)):
        c = [int(x) for x in rw.get("c") or [] if str(x).isdigit()]
        r = [int(x) for x in rw.get("r") or [] if str(x).isdigit()]
        RSRC["game"] += 1
    elif qid not in DISC_ONLY and ("itemrewards" in q or "itemchoices" in q):
        c = [x[0] for x in q.get("itemchoices") or [] if isinstance(x, list) and x]
        r = [x[0] for x in q.get("itemrewards") or [] if isinstance(x, list) and x and x[0] not in c]  # Wowhead repeats some
        RSRC["wowhead"] += 1
    else:
        _nm = str(q.get("name") or "").strip().lower()
        if _nm in _LOOT_Q and _NAME_COUNT.get(_nm) == 1:
            u = sorted(_LOOT_Q[_nm])  # the page lists them without saying which are a choice
            c, r = [], []
            RSRC["loot pages"] += 1
    if c is None:
        RUNK[qid] = True
        RSRC["unknown"] += 1
    elif c or r or u:
        RITEMS[qid] = {"c": c or None, "r": r or None, "u": u or None}
lines.append("-- [id] = { c = { choose one of these }, r = { always given }, u = { given, split unknown } }; quests in D.RUNK: rewards not known yet")
lines.append("D.RITEMS = " + keyed(RITEMS))
lines.append("D.RUNK = " + keyed(RUNK))
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
lines.append("-- {name, uiMap, x, y, continent (-1 inside an instance, or on an island off the continents: Zephras Isle keeps its uiMap), world x, world y, Alliance hub, minutes on foot from it, Horde hub, minutes, place}")
lines.append("D.NPC = {\n" + ",\n".join(lua(n) for n in NPCS) + "\n}")
# hand-placed NPCs (CURATED) have no SOURCE: they read as Classic data, the cautious claim
lines.append("-- where each D.NPC place comes from, one letter per NPC: w Wowhead Forever, c the CMaNGOS spawn (Classic data), g players' games")
lines.append('D.NSRC = "%s"' % "".join({"wowhead": "w", "cmangos": "c", "game": "g"}.get(SOURCE.get(i), "c") for i in range(1, len(NPCS) + 1)))
lines.append("D.MAPNAME = " + keyed({m: UIMAP.get(m, "") for m in USED_MAPS}))
hubs, dist = {}, {}
for fac in ("A", "H"):
    order = TR.order[fac]
    hubs[fac] = [[TR.hubs[fac][h]["town"], TR.hubs[fac][h]["cont"], round(TR.hubs[fac][h]["x"]), round(TR.hubs[fac][h]["y"]),
                  1 if TR.hubs[fac][h]["inn"] else 0] for h in order]
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
lines.append("-- {town, continent, world x, world y, has an inn}")
lines.append("D.HUB = {A=" + lua(hubs["A"]) + ",\nH=" + lua(hubs["H"]) + "}")
lines.append("-- hub to hub: fixed minutes (flights, boats) and minutes on foot, two characters each (tenths of a minute, base 64), and the main way")
lines.append("D.DIST = {A=" + lua(dist["A"]) + ",\nH=" + lua(dist["H"]) + "}")
lines.append('D.ALPHA = "%s"' % ALPHA)
lines.append('D.CUT_NOTES = {[1654]="Hand it to Jordan now and keep the forge step instead",[79192]="Carry on up the chain for the Cozy Sleeping Bag",[97894]="Pays 0 XP: abandon it"}')
lines.append("D.TRACKED_ITEMS = " + lua([
    {"id": 211527, "name": "Cozy Sleeping Bag", "need": 1, "icon": 133662},
    {"id": 251522, "name": "Blood-Stained Letter", "need": 1, "quest": 92415, "icon": 133471, "side": 1},
    {"id": 268540, "name": "Bloodied Insignia", "need": 10, "quest": 95195, "icon": 133328, "side": 1},
    {"id": 4371, "name": "Bronze Tube", "need": 1, "quest": 174, "icon": 133024, "side": 1},
]))
lines.append("D.SLEEP_CHAIN = " + lua([
    {"id": 79192, "name": "Stepping Stones", "where": "Pocket Litter, Stonetalon Mountains", "m": 1442, "x": 40.7, "y": 52.4},
    {"id": 79980, "name": "Scramble", "where": "Mound of Dirt, Stonetalon Mountains", "m": 1442, "x": 39.6, "y": 49.9},
    {"id": 79974, "name": "Wet Job", "where": "Carved Figurine on the Stonewrought Dam, Loch Modan", "m": 1432, "x": 49.4, "y": 12.9},
    {"id": 79975, "name": "Eagle's Fist", "where": "Messenger Bag on Thoradin's Wall, Arathi Highlands", "m": 1417, "x": 22.4, "y": 24.2},
    {"id": 79976, "name": "This Must Be The Place", "where": "Rolled-Up Satchel, where the bag's note points", "m": None, "x": None, "y": None},
]))
lines.append("")
os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, "w").write("\n".join(lines))
# ---------------------------------------------------------------------------
# GAPS.md: everything still missing, so nobody has to take the numbers on trust
# ---------------------------------------------------------------------------
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
            "inside": [q for q in lst if Q[q][5] and NPCS[Q[q][5] - 1][4] < 0],
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
           "holidays, repeatable turn-ins, raids and battlegrounds are left out.",
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
                                "too little to place: no NPC with a position" if q in DISC_UNPLACED else "left out on purpose by the catalog's filters")
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
print("map icons: objective spots for %d quests (%d from CMaNGOS spawns, %d from its quest POIs only, %d from Wowhead Forever, "
      "%d from players' games alone, %d more with players' spots; %d players' areas inside a Classic or Wowhead one left out), "
      "%d spots on %d maps; %d quests that start from an item show where it drops; %d names; islands: %d givers and %d turn-ins on their map" % (
          len(SPOT), SPOT_FROM["c"], SPOT_FROM["p"], SPOT_FROM["w"], SPOT_FROM["G"], SPOT_FROM["g"], len(GAME_FOLDED),
          sum(v.count(";") + 1 for v in SPOT.values()),
          len({p.split(",")[2] for v in SPOT.values() for p in v.split(";")}), len(START), len(SN),
          sum(1 for v in Q.values() if v[6] and NPCS[v[6] - 1][1] in ISLANDS), sum(1 for v in Q.values() if v[5] and NPCS[v[5] - 1][1] in ISLANDS)))
