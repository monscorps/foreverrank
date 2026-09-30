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
Icons and textures: file IDs from the Forever client's interface manifest; a missing one stops the build.

  python3 tools/questbank/gen_data.py            # write Data.lua
  python3 tools/questbank/gen_data.py --fetch    # first fetch the NPC tooltips we lack (nether.wowhead.com)
"""
import csv, json, os, sys
from travel import Travel, DETOUR, RUN

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "QuestBank", "Data.lua")
REPO = os.path.dirname(os.path.dirname(HERE))
RAW = os.path.join(REPO, "research", "questbank")
BUILD = "1.60.1.70058"
READ = "2026-09-29"


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
    19: ("inv_misc_head_orc_01", "Hand in Blackrock Blockade first, then kill Tharil'zun.", {"pre": [20, 98386, 98387]}),
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
    717: ("stormwindstockades", "Stormwind", None), 721: ("gnomeregan", "Dun Morogh", (1426, 24.4, 39.8)),
    491: ("razorfenkraul", "The Barrens", (1413, 42.3, 89.9)), 796: ("scarletmonastery", "Tirisfal Glades", None),
    722: ("razorfendowns", "The Barrens", None), 1337: ("uldaman", "Badlands", None), 2437: ("ragefirechasm", "Orgrimmar", None),
    16611: ("ruinsoflordaeron", "Tirisfal Glades", None), 16919: ("dungeon", "", None),
    1176: ("zulfarak", "Tanaris", None), 2100: ("maraudon", "Desolace", None), 1477: ("sunkentemple", "Swamp of Sorrows", None),
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
def qlevel(qid):
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

IDS = []
for qid, q in LIST.items():
    if qid in NOT_IN_FOREVER:
        continue
    if qid in CURATED:
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
    else:
        rec[1] = 0
    if place:
        rec.append(place)
    NPCS.append(rec)
    NPC_AT[key] = len(NPCS)
    return len(NPCS)


SOURCE = {}  # npc record index -> "wowhead" | "cmangos"


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
            idx = add_npc(n["name"], m, x, y)
            SOURCE.setdefault(idx, "wowhead")
            return idx
    for k in kinds:
        spawns = CM_SPAWNS.get(k, {}).get(i)
        name = CM_NAMES.get(k, {}).get(i) or (LOC.get(npc_key(k, i)) or {}).get("name")
        if spawns and name:
            cont, wx, wy = spawns[0]
            hint = (TR.area_map.get(zone),) if zone else None
            loc = TR.locate(cont, wx, wy, hint)
            if loc:
                idx = add_npc(name, loc[0], loc[1], loc[2])
                SOURCE.setdefault(idx, "cmangos")
                return idx
    if dungeon:  # a dungeon quest's NPC with no place on the two continents stands inside
        for k in kinds:
            name = CM_NAMES.get(k, {}).get(i) or (LOC.get(npc_key(k, i)) or {}).get("name")
            if name:
                idx = add_npc(name, 0, 0, 0)
                SOURCE.setdefault(idx, "cmangos")
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
    return qid in CM or bool((DET.get(qid) or {}).get("chain"))


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


def cat_for(qid):
    q = LIST[qid]
    c2, area = q.get("category2"), q.get("category")
    if c2 == 2 or (q.get("type") == 81 and area in DUNGEON):
        key = "d%d" % area
        if key not in CAT_AT:
            lfg, where, ent = DUNGEON.get(area, ("dungeon", "", None))
            bgname = "interface/lfgframe/ui-lfg-background-%s" % lfg
            CATS.append({"key": key, "name": AREAS.get(area, "Dungeon"), "where": where, "dungeon": True,
                         "icon": tex("interface/lfgframe/lfgicon-%s" % lfg),
                         "bg": tex(bgname) if (bgname + ".blp") in MAN else None,
                         "entrance": {"m": ent[0], "x": ent[1], "y": ent[2]} if ent else None})
            CAT_AT[key] = len(CATS)
        return CAT_AT[key]
    if c2 in (0, 1) and area in AREAS:
        key = "z%d" % area
        if key not in CAT_AT:
            CATS.append({"key": key, "name": AREAS[area], "where": "Kalimdor" if c2 == 1 else "Eastern Kingdoms",
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
_seen_mult = {}
for _qid in IDS:
    _q, _d = LIST[_qid], DET.get(_qid) or {}
    if (_q.get("category2") == 2 or _q.get("type") == 81) and _d.get("mult") is not None:
        _seen_mult.setdefault(cat_for(_qid), []).append(_d["mult"])
for _cat, _ms in _seen_mult.items():
    _top = max(set(_ms), key=_ms.count)
    if len(_ms) >= 2 and _ms.count(_top) >= 0.6 * len(_ms) and _top != 1:
        DMULT[_cat] = _top
FROM_FC, DISAGREE = [], []
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
        f = round(base * mult)
        t = 10 if f < 1000 else 50
        if abs(round(f / t) * t - FC[qid]) > max(60, FC[qid] * 0.02):
            DISAGREE.append((qid, round(f / t) * t, FC[qid]))
    if not d and mult is None or mult is None:
        flags |= 8
        mult = 1
        unconfirmed += 1
        if (flags & 1) and DMULT.get(cat_for(qid)):
            mult = DMULT[cat_for(qid)]
            flags |= 32
    if qid in CLASSIC:
        flags |= 16
    if not base:
        flags |= 64
    if sod_leftover(qid):
        flags |= 128
    side = {1: 1, 2: 2}.get(q.get("side"), 0)
    Q[qid] = [qlevel(qid), q.get("reqlevel") or 1, side, base, mult, turn, give, cat_for(qid), q.get("reqclass") or 0, flags]
    QN[qid] = q["name"]
    items = [x[0] for x in (q.get("itemrewards") or []) + (q.get("itemchoices") or []) if isinstance(x, list)]
    if items:
        QITEM[qid] = items[0]
    if cur:
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
        return str(int(v)) if v == int(v) else ("%.2f" % v).rstrip("0").rstrip(".")
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
lines.append("--         64 XP not known yet, 128 a Season of Discovery leftover: its NPC hasn't been met in Forever)}")
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
lines.append("-- [id] = {{item, how many, name}, ...}: what the quest asks you to bring")
lines.append("D.REQ = " + keyed(REQ))
lines.append("D.RACE = " + keyed(RACE))
lines.append("D.EXCL = " + keyed(EXCL))
lines.append("-- {name, uiMap, x, y, continent (-1 inside an instance), world x, world y, Alliance hub, minutes on foot from it, Horde hub, minutes, place}")
lines.append("D.NPC = {\n" + ",\n".join(lua(n) for n in NPCS) + "\n}")
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
routable = sum(1 for v in Q.values() if v[5] and NPCS[v[5] - 1][4] >= 0)
by_side = {s: sum(1 for v in Q.values() if v[2] == s) for s in (0, 1, 2)}
print("wrote %s: %d bytes, %d quests (both %d, Alliance %d, Horde %d), %d routable, %d without a read multiplier, %d NPCs, %d categories"
      % (OUT, os.path.getsize(OUT), len(Q), by_side[0], by_side[1], by_side[2], routable, unconfirmed, len(NPCS), len(CATS)))
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
           "", "Dungeon quests nobody has read take their dungeon's multiplier when the read ones agree: %s." % (
               ", ".join("%s x%s" % (CATS[c - 1]["name"], m) for c, m in sorted(DMULT.items(), key=lambda kv: CATS[kv[0] - 1]["name"])) or "none"),
           "", "Every quest in the catalog is one the game offers: placeholders (<UNUSED>, <NYI>, test quests), war efforts, invasions,",
           "holidays, repeatable turn-ins, raids and battlegrounds are left out.",
           "", "NPC positions: %d from Wowhead Forever, %d from the CMaNGOS spawn table where Wowhead has none." % (
               sum(1 for v in SOURCE.values() if v == "wowhead"), len(from_cm)),
           "Forever redrew Mulgore, Eastern Plaguelands, Redridge and Stormwind: %d Wowhead coordinates there were in the old" % FRAME.fixed,
           "Classic frame and were moved to Forever's; %d were already in Forever's." % FRAME.kept,
           "Instant follow-ups planned on the day: %d. Race-limited quests: %d. Quests in mutually exclusive groups: %d." % (
               len(FOLLOW), len(RACE), len(EXCL)),
           "Turn-in NPCs found by the name in the quest's objective, where Wowhead links none: %d." % len(TEXT_NAMED), ""]
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
print("gaps over %d Forever quests: %d multipliers, %d turn-ins, %d inside dungeons, %d givers, %d chains; %d Classic-only quests (GAPS.md)" % g)
print("redrawn maps: %d Wowhead coordinates moved from the Classic frame to Forever's, %d already in Forever's" % (FRAME.fixed, FRAME.kept))
