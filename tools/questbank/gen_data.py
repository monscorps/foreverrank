"""Generate QuestBank/Data.lua: the plan's quests, route stops, travel model, activities,
texture and icon file IDs (all checked against the Forever 1.60.1.70009 client manifest)
and an XP catalog for every quest we read from Wowhead."""
import json, os, re
from xpmodel import load, full_xp

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "QuestBank", "Data.lua")
RAW = os.path.join(os.path.dirname(os.path.dirname(HERE)), "research", "questbank")
Q = load()
LOC = json.load(open(os.path.join(RAW, "npcloc.json")))
MAN = json.load(open(os.path.join(RAW, "manifest.json")))
ICONS = {}
for line in open(os.path.join(os.path.dirname(HERE), "icon-listfile.csv")):
    fid, path = line.strip().split(";", 1)
    ICONS[path.split("/")[-1].replace(".blp", "")] = int(fid)

ZONE_MAP = {1519: 1453, 1537: 1455, 40: 1436, 44: 1433, 10: 1431, 1: 1426, 148: 1439, 1657: 1457, 141: 1438,
            17: 1413, 12: 1429, 38: 1432, 11: 1437, 406: 1442, 331: 1440, 85: 1420, 267: 1424, 45: 1417}


def icon(name):
    if name not in ICONS:
        raise SystemExit("missing icon " + name)
    return ICONS[name]


def tex(path):
    k = path.lower().replace("\\", "/")
    if not k.endswith(".blp"):
        k += ".blp"
    if k not in MAN:
        raise SystemExit("missing texture " + path)
    return int(MAN[k])


def npc(i):
    n = LOC.get("npc/%s" % i) or {}
    if not n.get("name") or not n.get("zone") or not n.get("coords"):
        return None
    m = ZONE_MAP.get(n["zone"])
    if not m:
        return None
    x, y = n["coords"][0]
    return {"n": n["name"], "m": m, "x": x, "y": y}


# id: (stop, activity, default_on, icon, how, extra)
PLAN = [
    (1491, "RATCHET", "wc", True, "spell_nature_corrosivebreath", "6 Wailing Essence from the ectoplasms in Wailing Caverns.", {"pre": [865]}),
    (959, "RATCHET", "wc", True, "inv_drink_10", "The 99-Year-Old Port from Mad Magglish in Wailing Caverns.", {}),
    (1486, "WCMOUND", "wc", True, "inv_misc_pelt_wolf_ruin_03", "Deviate Hides from the Wailing Caverns raptors.", {"turn": ["Nalpak", 1413, 46.6, 35.4], "give": ["Nalpak", 1413, 46.6, 35.4]}),
    (1487, "WCMOUND", "wc", True, "ability_hunter_pet_raptor", "Deviate beasts in Wailing Caverns.", {"turn": ["Ebru", 1413, 46.6, 35.4], "give": ["Ebru", 1413, 46.6, 35.4]}),
    (1221, "RATCHET", "rfk", True, "inv_misc_herb_07", "Crate, manual and command stick from Mebok, then the gopher digs 6 tubers in Razorfen Kraul.", {}),
    (97005, "RATCHET", "barrens", True, "inv_misc_monsterfang_01", "Forever elite in the Barrens. Bring a friend.", {}),
    (1069, "RATCHET", "barrens", True, "inv_egg_02", "15 Deepmoss Eggs from the spider nests in Stonetalon.", {}),
    (896, "RATCHET", "barrens", True, "inv_misc_gem_emerald_03", "Cats Eye Emerald from Venture Co. Overseers or Enforcers.", {}),
    (863, "RATCHET", "barrens", False, "inv_gizmo_03", "Escort Wizzlecrank's shredder out of the Venture Co. drill site.", {"pre": [858]}),
    (1806, "IF", "paladin", True, "spell_holy_sealofmight", "Hand the four items to Jordan, wait for the forge, keep this step.", {"pre": [1654], "turnAt": "gate"}),
    (971, "IF", "bfd", True, "inv_misc_note_01", "The Lorgalis Manuscript from Blackfathom Deeps.", {}),
    (2922, "IF", "gnomer", True, "inv_battery_01", "Techbot's Memory Core, Gnomeregan.", {}),
    (2926, "KH", "gnomer", True, "inv_drink_01", "Fill the phial on irradiated troggs in Gnomeregan.", {"pre": [2927]}),
    (2928, "SW", "gnomer", True, "inv_gizmo_02", "24 Robo-mechanical Guts in Gnomeregan.", {}),
    (166, "WF", "dm", True, "inv_misc_head_human_01", "VanCleef's head. Gryan's chain through the traitor escort first.", {"pre": [65, 132, 135, 141, 142, 155]}),
    (214, "WF", "dm", True, "inv_misc_bandana_03", "10 Red Silk Bandanas from the Defias in the Deadmines.", {"pre": [155]}),
    (2040, "SW", "dm", True, "inv_gizmo_01", "Gnoam Sprecklesprocket from Sneed's Shredder.", {}),
    (92753, "WFS", "dm", True, "inv_misc_bomb_05", "Plant the explosives at the forge. Alba Fairmoon's Westfall chain first.", {"pre": [92745]}),
    (167, "SW", "dm", True, "inv_jewelry_amulet_03", "Foreman Thistlenettle's badge.", {}),
    (168, "SW", "dm", False, "inv_letter_13", "Miners' Union Cards. Level 18, weak by the time you turn it in.", {}),
    (95189, "SW", "rol", True, "inv_misc_note_02", "Crest of Lordaeron from the Ruins.", {}),
    (92415, "SW", "rol", True, "inv_letter_06", "Keep the Blood-Stained Letter in your bags. Don't accept it.", {"bag": [251522, 1]}),
    (95195, "SW", "rol", True, "inv_jewelry_necklace_37", "Keep 10 Bloodied Insignias in your bags. Don't accept them.", {"bag": [268540, 10]}),
    (391, "SW", "stock", True, "inv_misc_head_human_01", "Bazil Thredd's head.", {}),
    (1275, "AUB", "bfd", True, "inv_misc_organ_03", "8 Corrupted Brain Stems in Blackfathom Deeps.", {}),
    (1199, "DARN", "bfd", True, "inv_jewelry_amulet_06", "10 Twilight Pendants in Blackfathom Deeps.", {}),
    (1200, "DARN", "bfd", True, "inv_misc_head_orc_01", "Kelris's head. In Search of Thaelrid first.", {"pre": [1198]}),
    (169, "RR", "redridge", True, "inv_misc_head_orc_01", "Gath'Ilzogg's head.", {}),
    (180, "RR", "redridge", True, "inv_misc_monsterclaw_04", "Fangore's paw.", {}),
    (95999, "RR", "redridge", True, "inv_staff_08", "Incinerator Gar'im's broken staff.", {}),
    (128, "RR", "redridge", True, "inv_misc_head_orc_01", "15 Blackrock Champions.", {}),
    (34, "RR", "redridge", True, "inv_misc_horn_01", "Bellygrub's tusk.", {}),
    (91, "RR", "redridge", True, "inv_jewelry_necklace_04", "10 Shadowhide Pendants.", {}),
    (98387, "RR", "redridge", True, "inv_banner_03", "Done. Holding it blocks Tharil'zun, which comes next in the chain.", {}),
    (150, "RR", "redridge", True, "inv_misc_fish_02", "Murloc fins.", {}),
    (219, "RR", "redridge", True, "inv_misc_note_02", "Escort Corporal Keeshan back from Render's Rock.", {}),
    (115, "RR", "redridge", True, "inv_misc_orb_01", "3 Midnight Orbs from Blackrock Shadowcasters.", {}),
    (126, "RR", "redridge", True, "inv_misc_monsterclaw_02", "Yowler's paw. A Baying of Gnolls first.", {"pre": [124]}),
    (19, "RR", "redridge", False, "inv_misc_head_orc_01", "Only instead of Blackrock Blockade: hand that in first, then kill Tharil'zun.", {"pre": [20, 98386, 98387]}),
    (92, "RR", "redridge", False, "inv_misc_food_14", "Level 18: cut it for a Duskwood slot.", {}),
    (127, "RR", "redridge", False, "inv_misc_fish_05", "Level 21: cut it for a Duskwood slot.", {}),
    (116, "RR", "redridge", False, "inv_drink_05", "Level 15: pays 40% on the day. Cut it.", {}),
    (101, "DW", "duskwood", True, "spell_nature_stoneclawtotem", "10 Ghoul Fangs, 10 Skeleton Fingers, 5 Vials of Spider Venom.", {}),
    (58, "DW", "duskwood", True, "inv_misc_bone_humanskull_01", "20 Plague Spreaders at Raven Hill. Parts 1 and 2 first.", {"pre": [56, 57]}),
    (98447, "DW", "duskwood", True, "spell_shadow_haunting", "The Valor family ghosts at Raven Hill. Part 1 first.", {"pre": [96139], "give": ["Sirra Von'Indi", 1431, 72.4, 47.4], "turn": ["Sirra Von'Indi", 1431, 72.4, 47.4]}),
    (174, "DW", "duskwood", True, "trade_engineering", "A Bronze Tube for Viktori: buy one or ask an engineer.", {"bag": [4371, 1, "need"]}),
    (90, "DW", "duskwood", True, "inv_misc_food_48", "10 Lean Wolf Flanks.", {}),
    (96137, "DW", "duskwood", True, "inv_weapon_shortblade_05", "10 Young Black Ravagers and 7 Black Ravagers.", {"give": ["Sirra Von'Indi", 1431, 72.4, 47.4], "turn": ["Sirra Von'Indi", 1431, 72.4, 47.4]}),
    (401, "DW", "duskwood", False, "inv_letter_06", "The end of Abercrombie's long chain.", {"pre": [148, 149, 154, 157, 158, 156, 159, 133, 134, 160, 251]}),
    (95161, "DW", "rol", True, "inv_letter_06", "Given when you hand in Remember That I Love You. Deliver to Avette Fellwood.", {"follow": 92415}),
]

ACTS = [
    ("rol", "Ruins of Lordaeron", "Tirisfal Glades", "interface/lfgframe/lfgicon-ruinsoflordaeron", None, None),
    ("dm", "The Deadmines", "Westfall", "interface/lfgframe/lfgicon-deadmines", "interface/lfgframe/ui-lfg-background-deadmines", (1436, 42.5, 71.7)),
    ("bfd", "Blackfathom Deeps", "Ashenvale", "interface/lfgframe/lfgicon-blackfathomdeeps", "interface/lfgframe/ui-lfg-background-blackfathomdeeps", (1440, 14.2, 14.0)),
    ("gnomer", "Gnomeregan", "Dun Morogh", "interface/lfgframe/lfgicon-gnomeregan", "interface/lfgframe/ui-lfg-background-gnomeregan", (1426, 24.4, 39.8)),
    ("wc", "Wailing Caverns", "The Barrens", "interface/lfgframe/lfgicon-wailingcaverns", "interface/lfgframe/ui-lfg-background-wailingcaverns", (1413, 46.0, 36.4)),
    ("rfk", "Razorfen Kraul", "The Barrens", "interface/lfgframe/lfgicon-razorfenkraul", "interface/lfgframe/ui-lfg-background-razorfenkraul", (1413, 42.3, 89.9)),
    ("stock", "The Stockade", "Stormwind", "interface/lfgframe/lfgicon-stormwindstockades", "interface/lfgframe/ui-lfg-background-stormwindstockades", None),
    ("barrens", "The Barrens", "Ratchet and around", "icon:inv_misc_gem_emerald_03", None, None),
    ("redridge", "Redridge Mountains", "Lakeshire", "icon:inv_misc_head_orc_01", None, None),
    ("duskwood", "Duskwood", "Darkshire", "icon:spell_shadow_haunting", None, None),
    ("paladin", "The Test of Righteousness", "Ironforge gates", "icon:spell_holy_sealofmight", None, None),
]

STOPS = [
    ("RATCHET", "Ratchet", 1413, 63.1, 37.2, 4, "icon:inv_misc_coin_01", "Mebok, Bigglefuzz, Dizzywig, Sputtervalve, and Bainham just south of town. Flight master on the docks."),
    ("WCMOUND", "Wailing Caverns", 1413, 46.5, 35.5, 1.5, "interface/lfgframe/lfgicon-wailingcaverns", "Nalpak and Ebru in the cave above the dungeon entrance."),
    ("SW", "Stormwind", 1453, 66.3, 62.1, 7, "icon:inv_misc_coin_01", "Shoni and Wilder in the Dwarven District, Lady Dena Kennedy, Orphan Matron Nightingale, Warden Thelwater, General Marcus Jonathan."),
    ("WF", "Sentinel Hill", 1436, 56.6, 52.6, 1.5, "icon:inv_misc_bandana_03", "Gryan Stoutmantle and Scout Riell."),
    ("WFS", "Westfall shore", 1436, 38.4, 83.6, 1, "icon:inv_misc_bomb_05", "Alba Fairmoon at the Deadmines exit."),
    ("DW", "Darkshire", 1431, 77.5, 44.3, 3, "icon:spell_shadow_haunting", "Madame Eva, Commander Althea, Viktori, Chef Grual and Sirra, all by the flight master."),
    ("RR", "Lakeshire", 1433, 30.6, 59.4, 5, "icon:inv_misc_head_orc_01", "Solomon, Conacher, Marris, Verner Osgood, Guard Howe, Martie Jainrose, Dockmaster Baren."),
    ("IF", "Ironforge", 1455, 55.5, 47.8, 6, "icon:inv_hammer_05", "Gerrig in the Forlorn Cavern, Tinkmaster in Tinker Town, Jordan Stilwell outside the gates."),
    ("KH", "Kharanos", 1426, 46.8, 52.3, 1, "icon:inv_drink_05", "Ozzie Togglevolt."),
    ("AUB", "Auberdine", 1439, 36.3, 45.6, 1, "icon:inv_misc_organ_03", "Gershala Nightwhisper."),
    ("DARN", "Darnassus", 1457, 55.2, 23.5, 3, "icon:inv_jewelry_amulet_06", "Argent Guard Manados and Dawnwatcher Selgorm."),
]

# travel between stops: (minutes flying, riding a tram or on a boat, minutes on foot)
EDGE = {
    ("IF", "KH"): (0, 5), ("IF", "SW"): (1.5, 2.5), ("SW", "WF"): (2.5, 1), ("SW", "RR"): (2.5, 1), ("SW", "DW"): (3, 1),
    ("WF", "WFS"): (0, 3), ("WF", "RR"): (4, 1), ("WF", "DW"): (3.5, 1), ("RR", "DW"): (2, 1), ("IF", "WF"): (6, 2),
    ("IF", "RR"): (6, 2), ("IF", "DW"): (7, 2), ("SW", "AUB"): (5.5, 2.5), ("IF", "AUB"): (10, 2), ("RR", "AUB"): (8, 3.5),
    ("DW", "AUB"): (8.5, 3.5), ("WF", "AUB"): (8, 3.5), ("AUB", "DARN"): (4, 2), ("RATCHET", "WCMOUND"): (0, 5), ("RATCHET", "AUB"): (8.5, 1),
}


def edge(a, b):
    if (a, b) in EDGE: return EDGE[(a, b)]
    if (b, a) in EDGE: return EDGE[(b, a)]
    for hub, leaf, extra in (("IF", "KH", 5), ("WF", "WFS", 3), ("RATCHET", "WCMOUND", 5)):
        if a == leaf: f, w = edge(hub, b); return (f, w + extra)
        if b == leaf: f, w = edge(a, hub); return (f, w + extra)
    if a == "DARN": f, w = edge("AUB", b); return (f + 4, w + 2)
    if b == "DARN": f, w = edge(a, "AUB"); return (f + 4, w + 2)
    raise KeyError((a, b))


def lua(v):
    if v is None: return "nil"
    if v is True: return "true"
    if v is False: return "false"
    if isinstance(v, (int,)): return str(v)
    if isinstance(v, float): return ("%.2f" % v).rstrip("0").rstrip(".")
    if isinstance(v, str): return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, list): return "{" + ",".join(lua(x) for x in v) + "}"
    if isinstance(v, dict): return "{" + ",".join("%s=%s" % (k, lua(x)) for k, x in v.items() if x is not None) + "}"
    raise TypeError(v)


def texref(s):
    return icon(s[5:]) if s.startswith("icon:") else tex(s)


lines = ["-- Generated by gen_data.py from Wowhead Forever quest data (read 2026-09-29) and the",
         "-- Forever beta client build 1.60.1.70009. Edit the generator, not this file.",
         "local _, QB = ...", "local D = {}", "QB.Data = D", ""]
lines.append("D.TO_NEXT = " + lua([400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700]))
T = {k: tex(v) for k, v in {
    "bg": "interface/dialogframe/ui-dialogbox-background-dark", "border": "interface/dialogframe/ui-dialogbox-gold-border",
    "header": "interface/dialogframe/ui-dialogbox-gold-header", "parch": "interface/questframe/questbackgroundclassic",
    "parchH": "interface/achievementframe/ui-achievement-parchment-horizontal", "tipBorder": "interface/tooltips/ui-tooltip-border",
    "tipBg": "interface/tooltips/ui-tooltip-background", "divider": "interface/dialogframe/ui-dialogbox-divider",
    "tabOn": "interface/paperdollinfoframe/ui-character-activetab", "tabOff": "interface/paperdollinfoframe/ui-character-inactivetab",
    "tabHi": "interface/paperdollinfoframe/ui-character-tab-highlight", "slot": "interface/buttons/ui-quickslot2",
    "slotEmpty": "interface/buttons/ui-emptyslot-disabled", "iconFrame": "interface/common/whiteiconframe",
    "hilite": "interface/buttons/buttonhilight-square", "bar": "interface/targetingframe/ui-statusbar",
    "ready": "interface/raidframe/readycheck-ready", "notready": "interface/raidframe/readycheck-notready",
    "waiting": "interface/raidframe/readycheck-waiting", "ring": "interface/minimap/minimap-trackingborder",
    "flight": "interface/minimap/tracking/flightmaster", "questAvail": "interface/gossipframe/availablequesticon",
    "questActive": "interface/gossipframe/activequesticon", "taxiY": "interface/taxiframe/ui-taxi-icon-yellow",
    "taxiG": "interface/taxiframe/ui-taxi-icon-green", "taxiGray": "interface/taxiframe/ui-taxi-icon-gray",
    "bullet": "interface/questframe/ui-quest-bulletpoint", "titleHi": "interface/questframe/ui-questlogtitlehighlight",
    "mapPin": "interface/worldmap/ui-worldmap-questicon", "book": "interface/questframe/ui-questlog-bookicon",
    "checkbox": "interface/buttons/ui-checkbox-check", "rowHi": "interface/questframe/ui-questitemhighlight",
    "minimapBg": "interface/minimap/ui-minimap-background", "minimapHi": "interface/minimap/ui-minimap-zoombutton-highlight",
    "knob": "interface/buttons/ui-scrollbar-knob", "skillBar": "interface/paperdollinfoframe/ui-character-skills-bar",
    "skillBorder": "interface/paperdollinfoframe/ui-character-skills-barborder", "dotGray": "interface/common/indicator-gray",
    "dotYellow": "interface/common/indicator-yellow", "dotGreen": "interface/common/indicator-green",
}.items()}
T.update({"hearth": icon("inv_misc_rune_01"), "mount": icon("ability_mount_ridinghorse"), "foot": icon("ability_rogue_sprint"),
          "sleep": 133662, "hourglass": icon("inv_misc_pocketwatch_01"), "gryphon": icon("ability_mount_gryphon_01"),
          "boat": icon("inv_misc_anchor"), "tram": icon("inv_gizmo_02"), "unknown": icon("inv_misc_questionmark"),
          "questGeneric": icon("inv_misc_note_01"), "map": icon("inv_misc_map_01"), "barrensStart": icon("inv_misc_coin_01")})
lines.append("D.TEX = " + lua(T))

qlines = []
for qid, stop, act, on, ic, how, extra in PLAN:
    q = Q[qid]; d = q.get("det") or {}
    mult = d.get("mult") if d.get("mult") is not None else 1
    give = None
    if extra.get("give"):
        g = extra["give"]; give = {"n": g[0], "m": g[1], "x": g[2], "y": g[3]}
    elif d.get("startType") == "npc" and d.get("startId"):
        give = npc(d["startId"])
    turn = None
    if extra.get("turn"):
        t = extra["turn"]; turn = {"n": t[0], "m": t[1], "x": t[2], "y": t[3]}
    elif d.get("endId"):
        turn = npc(d["endId"])
    if extra.get("turnAt") == "gate":
        turn = {"n": "Jordan Stilwell", "m": 1426, "x": 52.4, "y": 36.8}
    rec = {"id": qid, "name": q["name"], "lvl": q["level"], "req": q["reqlevel"], "base": q["xp"], "mult": mult,
           "stop": stop, "act": act, "on": on, "icon": icon(ic), "how": how, "give": give, "turn": turn,
           "pre": extra.get("pre"), "follow": extra.get("follow")}
    if extra.get("bag"):
        b = extra["bag"]
        rec["bagItem"], rec["bagNeed"] = b[0], b[1]
        if len(b) > 2: rec["bagIsTool"] = True
    qlines.append("  " + lua(rec) + ",")
lines.append("D.QUESTS = {\n" + "\n".join(qlines) + "\n}")

names = {1654: "the item step of The Test of Righteousness", 155: "The Defias Brotherhood, the traitor escort",
         65: "The Defias Brotherhood, Gryan's first step", 132: "The Defias Brotherhood, Wiley's note",
         135: "The Defias Brotherhood, the note to Shaw", 141: "The Defias Brotherhood, Shaw's reply",
         142: "The Defias Brotherhood, the Defias thugs", 56: "The Night Watch, part 1", 57: "The Night Watch, part 2",
         96139: "The Valor Family, part 1"}
for qid in {p for _, _, _, _, _, _, e in PLAN for p in (e.get("pre") or [])} | {1654, 858}:
    if qid in Q and qid not in names: names[qid] = Q[qid]["name"]
lines.append("D.QUEST_NAMES = {" + ",".join("[%d]=%s" % (k, lua(v)) for k, v in sorted(names.items())) + "}")

alines = []
for key, name, where, ico, bg, ent in ACTS:
    alines.append("  " + lua({"key": key, "name": name, "where": where, "icon": texref(ico), "bg": tex(bg) if bg else None,
                               "entrance": {"m": ent[0], "x": ent[1], "y": ent[2]} if ent else None}) + ",")
lines.append("D.ACTS = {\n" + "\n".join(alines) + "\n}")

slines = []
for key, name, m, x, y, work, ico, note in STOPS:
    slines.append("  " + lua({"key": key, "name": name, "m": m, "x": x, "y": y, "work": work, "icon": texref(ico), "note": note}) + ",")
lines.append("D.STOPS = {\n" + "\n".join(slines) + "\n}")
keys = [s[0] for s in STOPS]
elines = []
for a in keys:
    for b in keys:
        if a < b:
            try:
                f, w = edge(a, b)
            except KeyError:
                continue
            elines.append('["%s>%s"]={%s,%s}' % (a, b, lua(float(f)), lua(float(w))))
lines.append("D.EDGES = {" + ",".join(elines) + "}")
lines.append('D.KALIMDOR = {RATCHET=true,WCMOUND=true,AUB=true,DARN=true}')
lines.append('D.INN = {RATCHET="Ratchet",WCMOUND="Ratchet",AUB="Auberdine",DARN="Darnassus",SW="Stormwind",WF="Sentinel Hill",WFS="Sentinel Hill",DW="Darkshire",RR="Lakeshire",IF="Ironforge",KH="Kharanos"}')
lines.append('D.INN_STOP = {WCMOUND="RATCHET",WFS="WF"}')
lines.append('D.BLOCKS_KAL = {{"RATCHET","WCMOUND"},{"AUB","DARN"}}')
lines.append('D.BLOCKS_EK = {{"SW"},{"WF","WFS"},{"DW"},{"RR"},{"IF","KH"}}')

lines.append('D.CUT_NOTES = {[1654]="Hand it to Jordan now and keep the forge step instead",[79192]="Carry on up the chain for the Cozy Sleeping Bag",[97894]="Pays 0 XP: abandon it"}')
lines.append("D.TRACKED_ITEMS = " + lua([
    {"id": 251522, "name": "Blood-Stained Letter", "need": 1, "quest": 92415, "icon": 133471},
    {"id": 268540, "name": "Bloodied Insignia", "need": 10, "quest": 95195, "icon": 133328},
    {"id": 4371, "name": "Bronze Tube", "need": 1, "quest": 174, "icon": 133024},
    {"id": 211527, "name": "Cozy Sleeping Bag", "need": 1, "icon": 133662},
]))
lines.append("D.SLEEP_CHAIN = " + lua([
    {"id": 79192, "name": "Stepping Stones", "where": "Pocket Litter, Stonetalon Mountains", "m": 1442, "x": 40.7, "y": 52.4},
    {"id": 79980, "name": "Scramble", "where": "Mound of Dirt, Stonetalon Mountains", "m": 1442, "x": 39.6, "y": 49.9},
    {"id": 79974, "name": "Wet Job", "where": "Carved Figurine on the Stonewrought Dam, Loch Modan", "m": 1432, "x": 49.4, "y": 12.9},
    {"id": 79975, "name": "Eagle's Fist", "where": "Messenger Bag on Thoradin's Wall, Arathi Highlands", "m": 1417, "x": 22.4, "y": 24.2},
    {"id": 79976, "name": "This Must Be The Place", "where": "Hastily Rolled-Up Satchel, where the Messenger Bag's note points", "m": None, "x": None, "y": None},
]))

cat = []
for qid, q in sorted(Q.items()):
    d = q.get("det") or {}
    mult = d.get("mult") if d.get("mult") is not None else 1
    if not q.get("xp"):
        continue
    cat.append("[%d]={%d,%d%s}" % (qid, q["level"], q["xp"], "" if mult == 1 else "," + lua(float(mult))))
lines.append("D.XP = {" + ",".join(cat) + "}")
lines.append("")
os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, "w").write("\n".join(lines))
print("wrote", OUT, os.path.getsize(OUT), "bytes;", len(qlines), "quests;", len(cat), "catalog")
missing = [(r[0]) for r in PLAN if not (npc((Q[r[0]].get('det') or {}).get('endId')) or r[6].get('turn') or r[6].get('turnAt'))]
print("quests without turn-in coords:", missing)
