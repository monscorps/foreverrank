#!/usr/bin/env python3
"""The Atlas overlays: zone levels, flight paths, towns and dungeon doors.

Everything comes from the beta client's own tables (research/wago/<BUILD>,
fetched from wago.tools when missing), so map/atlas.json can say "client
data" on every number it shows:

  zone levels    AreaTable.ExplorationLevel of every area inside the zone,
                 min to max, with one or two far-off areas left out (a gap of
                 6+ levels to the rest, e.g. Dun Morogh's submarine at 56).
                 The dropped areas are kept in the file so the page can name them.
  faction        AreaTable.FactionGroupMask (2 Alliance, 4 Horde, 0 contested)
  flight masters TaxiNodes (faction from Flags bit 1/2, else from the flight
                 mount, which the page labels) and TaxiPath (routes, base cost)
  towns          AreaPOI rows the client puts on the continent map (Flags & 1)
  dungeon doors  Map.Corpse: where the client sends your ghost to run back in.
                 Naxxramas has no corpse point; its door is the client's
                 AreaTrigger that CMaNGOS (Classic data) names as Naxxramas.
                 Each door's own zone: the client's place on the continent named
                 as the dungeon, else Classic's zone (DOOR_ZONE), so a zone map
                 can tell its own doors from a neighbour's that fall in its frame.

World positions become percentages of the continent art (map/img/cont-*.jpg,
cut to the windows in CROP) and of each zone map (map/img/<AreaID>.jpg, the
zone's full UiMap frame), through UiMapAssignment.

  python3 tools/build_atlas.py               # newest build in research/wago
  python3 tools/build_atlas.py 1.60.1.70291  # a given build
"""
import collections, csv, gzip, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from fetch_wago import fetch  # noqa: E402

OUT = os.path.join(ROOT, "map", "atlas.json")
LOOT = os.path.join(ROOT, "codex", "loot.json")
CMANGOS = os.path.join(ROOT, "research", "cmangos", "ClassicDB.sql.gz")
DISC = os.path.join(ROOT, "research", "questbank", "disc.json")  # players' uploads, merged by tools/probe_pull.py
# Doors the client has no point for yet, placed where players' games put the dungeon's own quest giver
# (QuestBank notes NPC positions as uiMap:x,y): the giver stands at the entrance, which is inferred, and the door says so
PLAYER_DOORS = {"City of Dalaran": ("c269127", "Image of Archmage Modera")}
TABLES = ["AreaTable", "UiMap", "UiMapAssignment", "TaxiNodes", "TaxiPath", "AreaPOI",
          "Map", "AreaTrigger", "ContentTuning", "LFGDungeons"]

# The windows cont-ek.jpg and cont-kal.jpg were cut to, in continent map units
# (0..1 across UiMap 1415 / 1414). Fitted from map.js GEO hotspots against
# UiMapAssignment; the worst zone corner is off by 0.03% of the image.
CONT = {"0": ("ek", "1415"), "1": ("kal", "1414")}
CROP = {"ek": (0.334522, 0.668074, 0.132582, 0.997436),
        "kal": (0.293907, 0.712594, 0.017455, 0.970720)}

# Map names that differ from codex/loot.json's dungeon names.
LOOT_ALIAS = {"Stormwind Stockade": ["The Stockade"], "Deadmines": ["The Deadmines"],
              "Sunken Temple": ["The Temple of Atal'Hakkar"]}
# Where Classic puts the doors the client names no place for on the continent
# (Blackrock Mountain sits across Searing Gorge and Burning Steppes).
DOOR_ZONE = {"Deadmines": "Westfall", "Wailing Caverns": "The Barrens",
             "Stormwind Stockade": "Stormwind City", "Scarlet Monastery": "Tirisfal Glades",
             "Scholomance": "Western Plaguelands", "Naxxramas": "Eastern Plaguelands",
             "Onyxia's Lair": "Dustwallow Marsh", "Blackrock Depths": "Blackrock Mountain",
             "Blackrock Spire": "Blackrock Mountain", "Molten Core": "Blackrock Mountain",
             "Blackwing Lair": "Blackrock Mountain"}
TRIM_GAP = 6   # levels between an end area and the rest before it counts as far off
TRIM_MAX = 2   # never drop more than this many areas at either end (or a fifth of the zone)


def newest_build():
    have = [b for b in os.listdir(os.path.join(ROOT, "research", "wago")) if b.startswith("1.60.")]
    return sorted(have, key=lambda b: [int(x) for x in b.split(".")])[-1]


def load(build, table):
    path, note = fetch(build, table)
    if not path:
        sys.exit("%s: %s" % (table, note))
    with open(path, encoding="utf-8-sig") as fh:
        return list(csv.DictReader(fh))


def region(r):
    # Region_0..2 = min x, y, z; Region_3..5 = max. World x runs north, y runs west.
    return [float(r["Region_%d" % i]) for i in range(6)]


def to_frame(reg, x, y):
    """World (x, y) to (across, down) in 0..1 of a UiMap frame."""
    return (reg[4] - y) / (reg[4] - reg[1]), (reg[3] - x) / (reg[3] - reg[0])


def trim(levels):
    """Sorted levels -> (kept, dropped): drop far-off areas at either end."""
    vals = sorted(levels)
    cap = min(TRIM_MAX, max(1, len(vals) // 5))
    lo, hi = 0, len(vals)
    for k in range(1, cap + 1):          # top end
        if hi - k >= 1 and vals[hi - k] - vals[hi - k - 1] >= TRIM_GAP:
            hi -= k
            break
    for k in range(1, cap + 1):          # bottom end
        if lo + k < hi and vals[lo + k] - vals[lo + k - 1] >= TRIM_GAP:
            lo += k
            break
    return vals[lo:hi], vals[:lo] + vals[hi:]


def pct(v):
    return round(v * 100, 2)


def main():
    build = sys.argv[1] if len(sys.argv) > 1 else newest_build()
    T = {t: load(build, t) for t in TABLES}
    area = {r["ID"]: r for r in T["AreaTable"]}
    kids = collections.defaultdict(list)
    for r in T["AreaTable"]:
        kids[r["ParentAreaID"]].append(r)
    uimap = {r["ID"]: r for r in T["UiMap"]}

    # Frames: continent regions and every zone map the Atlas shows (one per AreaID).
    cont_reg, zone_reg = {}, {}
    for a in T["UiMapAssignment"]:
        um = uimap.get(a["UiMapID"])
        if not um:
            continue
        if a["UiMapID"] in ("1414", "1415"):
            cont_reg[a["MapID"]] = region(a)
        elif um["System"] == "0" and um["Type"] in ("3", "6") and a["AreaID"] != "0":
            zone_reg.setdefault(a["AreaID"], (a["MapID"], region(a)))

    def place(mapid, x, y):
        """A world point -> continent key, crop %, and % on every zone map whose frame holds it."""
        out = {}
        if mapid in CONT:
            key = CONT[mapid][0]
            u, v = to_frame(cont_reg[mapid], x, y)
            u0, u1, v0, v1 = CROP[key]
            out["c"] = key
            out["p"] = [pct((u - u0) / (u1 - u0)), pct((v - v0) / (v1 - v0))]
        zp = {}
        for aid, (zmap, reg) in zone_reg.items():
            if zmap != mapid:
                continue
            zu, zv = to_frame(reg, x, y)
            if 0.01 <= zu <= 0.99 and 0.01 <= zv <= 0.99:
                zp[aid] = [pct(zu), pct(zv)]
        if zp:
            out["zp"] = zp
        return out

    # ---- zone levels ----
    def descendants(aid):
        out = []
        for k in kids[aid]:
            out.append(k)
            out += descendants(k["ID"])
        return out

    zones = {}
    for aid in sorted(zone_reg, key=int):
        sub = descendants(aid)
        lv = [(int(k["ExplorationLevel"]), k["AreaName_lang"]) for k in sub if int(k["ExplorationLevel"]) > 0]
        z = {"n": len(sub)}
        fm = area[aid]["FactionGroupMask"]
        if fm in ("2", "4"):
            z["f"] = "A" if fm == "2" else "H"
        if lv and aid not in CITY:
            kept, dropped = trim([l for l, _ in lv])
            z["lv"] = [kept[0], kept[-1]]
            z["of"] = len(lv)
            if dropped:
                names = sorted(lv)
                out = []
                for l in dropped:
                    hit = next(p for p in names if p[0] == l)
                    names.remove(hit)
                    out.append([hit[1], l])
                z["out"] = out
        zones[aid] = z

    # ---- flight masters and routes ----
    # A route ships when it is priced or flies both ways (Rut'theran to Auberdine is
    # free both ways). Free one-way hops are special flights, not a flight master's
    # list: Nighthaven's class flights and the Eastern Plaguelands towers.
    nodes = {r["ID"]: r for r in T["TaxiNodes"]}
    cost = {(r["FromTaxiNode"], r["ToTaxiNode"]): int(r["Cost"]) for r in T["TaxiPath"]
            if r["FromTaxiNode"] != r["ToTaxiNode"]}
    pairs = {tuple(sorted(k, key=int)) for k, c in cost.items() if c > 0 or k[::-1] in cost}
    routed = {n for p in pairs for n in p}
    taxi, keep = [], set()
    for nid, r in sorted(nodes.items(), key=lambda kv: int(kv[0])):
        name = r["Name_lang"]
        if r["ContinentID"] not in CONT or re.match(r"(zzOLD|Quest Path|Transport|Generic|Programmer)", name):
            continue
        # Forever's own nodes (ID 3000+) stay even before they get a route
        if nid not in routed and int(nid) < 3000:
            continue
        flags = int(r["Flags"])
        if flags & 128:          # hidden from the map UI on purpose (Tidegear Coast)
            continue
        f = ("A" if flags & 1 else "") + ("H" if flags & 2 else "")
        inferred = not f
        if inferred:             # no faction bit: the flight mount says who flies from here
            f = ("A" if r["MountCreatureID_1"] != "0" else "") + ("H" if r["MountCreatureID_0"] != "0" else "")
        if not f:
            continue
        n, _, where = name.partition(", ")
        node = {"id": int(nid), "n": n, "w": where, "f": f}
        if inferred:
            node["inf"] = 1
        node.update(place(r["ContinentID"], float(r["Pos_0"]), float(r["Pos_1"])))
        taxi.append(node)
        keep.add(nid)
    # [a, b, cost a->b, cost b->a] in copper; null where the client has no flight that way
    routes = [[int(a), int(b), cost.get((a, b)), cost.get((b, a))]
              for a, b in sorted(pairs, key=lambda p: (int(p[0]), int(p[1]))) if a in keep and b in keep]

    # ---- towns on the continent maps ----
    towns = []
    for r in T["AreaPOI"]:
        flags = int(r["Flags"])
        if r["ContinentID"] in CONT and flags & 1 and not flags & 128 and r["Icon"] in ("4", "6") and r["PlayerConditionID"] == "0":
            t = {"n": r["Name_lang"], "k": 1 if r["Icon"] == "4" else 0}
            t.update(place(r["ContinentID"], float(r["Pos_0"]), float(r["Pos_1"])))
            towns.append(t)
    towns.sort(key=lambda t: (t["c"], t["n"]))

    # ---- dungeon and raid doors ----
    tuning = {r["ID"]: r for r in T["ContentTuning"]}
    tuned = {}
    for r in T["AreaTable"]:
        if r["ParentAreaID"] == "0" and r["ContentTuningID"] != "0":
            ct = tuning.get(r["ContentTuningID"])
            if ct and int(ct["MinLevelSquish"]) > 0:
                tuned.setdefault(r["ContinentID"], int(ct["MinLevelSquish"]))
    # Dungeons with no tuned area row (Blackrock Depths, the raids): the Group Finder's tuning.
    lfg_alias = {"Stormwind Stockades": "Stormwind Stockade", "Zul'Farak": "Zul'Farrak",
                 "Onyxia": "Onyxia's Lair", "Lower Blackrock Spire": "Blackrock Spire"}
    lfg_level = {}
    for r in T["LFGDungeons"]:
        ct = tuning.get(r["ContentTuningID"])
        if r["TypeID"] == "0" and ct and int(ct["MinLevelSquish"]) > 0:
            lfg_level.setdefault(lfg_alias.get(r["Name_lang"], r["Name_lang"]), int(ct["MinLevelSquish"]))
    loot_names = []
    if os.path.exists(LOOT):
        loot_names = [d["name"] for d in json.load(open(LOOT, encoding="utf-8"))["dungeons"]]

    def loot_for(name):
        want = LOOT_ALIAS.get(name, [name])
        hit = [n for n in loot_names if n in want or n.split(": ")[0] == name]
        return hit

    dungeons, placed_maps = [], set()
    for m in T["Map"]:
        name = m["MapName_lang"]
        if m["InstanceType"] not in ("1", "2") or name.startswith("<") or m["CorpseMapID"] not in CONT:
            continue
        x, y = float(m["Corpse_0"]), float(m["Corpse_1"])
        if not x and not y:
            continue
        d = {"n": name, "src": "client"}
        if m["InstanceType"] == "2":
            d["raid"] = 1
        if m["ID"] in tuned or name in lfg_level:
            d["lv"] = tuned.get(m["ID"], lfg_level.get(name))
        lo = loot_for(name)
        if lo:
            d["loot"] = lo
        d.update(place(m["CorpseMapID"], x, y))
        dungeons.append(d)
        placed_maps.add(m["ID"])
    # Doors the client only has as a bare AreaTrigger: CMaNGOS names where they lead.
    if os.path.exists(CMANGOS):
        sql = gzip.open(CMANGOS, "rt", encoding="utf-8", errors="replace").read()
        block = re.search(r"INSERT INTO `areatrigger_teleport` VALUES (.*?);\n", sql, re.S).group(1)
        trig = {r["ID"]: r for r in T["AreaTrigger"]}
        maps = {r["ID"]: r for r in T["Map"]}
        for tid, tmap in re.findall(r"\((\d+),'(?:[^'\\]|\\.)*',\d+,\d+,\d+,\d+,(\d+),", block):
            t = trig.get(tid)
            m = maps.get(tmap)
            if not t or not m or tmap in placed_maps or t["ContinentID"] not in CONT or m["InstanceType"] not in ("1", "2"):
                continue
            d = {"n": m["MapName_lang"], "src": "cmangos"}
            if m["InstanceType"] == "2":
                d["raid"] = 1
            if tmap in tuned or m["MapName_lang"] in lfg_level:
                d["lv"] = tuned.get(tmap, lfg_level.get(m["MapName_lang"]))
            d.update(place(t["ContinentID"], float(t["Pos_0"]), float(t["Pos_1"])))
            dungeons.append(d)
            placed_maps.add(tmap)
    # Doors from players' games: the dungeon's quest giver's spot (PLAYER_DOORS), turned from zone percent back into a
    # world point through the zone's own frame, so it lands on the continent map too
    if os.path.exists(DISC):
        npcs = json.load(open(DISC, encoding="utf-8")).get("npc") or {}
        by_uimap = {}
        for a in T["UiMapAssignment"]:
            if a["AreaID"] in zone_reg and a["UiMapID"] not in by_uimap:
                by_uimap[a["UiMapID"]] = a["AreaID"]
        maps_by_name = {m["MapName_lang"]: m for m in T["Map"]}
        for dname, (key, who) in PLAYER_DOORS.items():
            spots = (npcs.get(key) or {}).get("p") or {}
            if not spots or maps_by_name.get(dname, {}).get("ID") in placed_maps:
                continue
            best = max(spots, key=spots.get)  # the position most uploads agree on
            um, xy = best.split(":")
            aid = by_uimap.get(um)
            if not aid:
                continue
            zmap, reg = zone_reg[aid]
            u, v = (float(c) / 100 for c in xy.split(","))
            x = reg[3] - v * (reg[3] - reg[0])
            y = reg[4] - u * (reg[4] - reg[1])
            d = {"n": dname, "src": "players", "who": who}
            m = maps_by_name.get(dname)
            if m and (m["ID"] in tuned or dname in lfg_level):
                d["lv"] = tuned.get(m["ID"], lfg_level.get(dname))
            lo = loot_for(dname)
            if lo:
                d["loot"] = lo
            d.update(place(zmap, x, y))
            dungeons.append(d)
            if m:
                placed_maps.add(m["ID"])
    dungeons.sort(key=lambda d: (d.get("raid", 0), d.get("lv", 99), d["n"]))

    # Each door's own zone: 'w' its name, 'z' its AreaID when the Atlas has that map.
    zone_name = {area[a]["AreaName_lang"]: a for a in zone_reg}
    named = collections.defaultdict(list)
    for r in T["AreaTable"]:
        named[r["AreaName_lang"].lower()].append(r)

    def zone_above(aid):
        while aid in area and aid != "0":
            if aid in zone_reg:
                return aid
            aid = area[aid]["ParentAreaID"]
        return None

    for d in dungeons:
        n = d["n"]
        z = next((zone_above(r["ID"]) for k in {n, "The " + n, n.replace("The ", "", 1)}
                  for r in named[k.lower()] if r["ContinentID"] in CONT and zone_above(r["ID"])), None)
        w = area[z]["AreaName_lang"] if z else DOOR_ZONE.get(n)
        if not w and len(d.get("zp", {})) == 1:
            z = next(iter(d["zp"]))
            w = area[z]["AreaName_lang"]
        if not w:
            print("  no zone for the door of", n)
            continue
        d["w"] = w
        z = z or zone_name.get(w)
        if z:
            d["z"] = z

    # Forever's own dungeons (LFGDungeons rows past the Classic list) have no door in the client yet.
    unplaced = [r["Name_lang"] for r in T["LFGDungeons"] if r["TypeID"] == "0" and int(r["ID"]) >= 3000
                and r["Name_lang"] not in {d["n"] for d in dungeons}]
    # New dungeons our loot tables carry that the client has no dungeon map for at all yet.
    bare = lambda s: re.sub(r"^the ", "", s.lower())
    in_client = {bare(m["MapName_lang"]) for m in T["Map"] if m["InstanceType"] in ("1", "2")}
    in_client |= {bare(n) for n in unplaced}
    notyet = []
    if os.path.exists(LOOT):
        notyet = [d["name"] for d in json.load(open(LOOT, encoding="utf-8"))["dungeons"]
                  if d.get("new") and bare(d["name"]) not in in_client]

    out = {
        "build": build,
        "note": "Read from the beta client's tables by tools/build_atlas.py. Zone levels: AreaTable "
                "exploration levels (far-off areas in 'out'); flights: TaxiNodes/TaxiPath (cost in copper, "
                "'inf' = faction read from the flight mount); towns: AreaPOI; doors: Map corpse points "
                "('cmangos' = a client AreaTrigger that CMaNGOS names; 'players' = where players' games put the "
                "dungeon's quest giver, the entrance inferred; 'w' = the door's zone, from the "
                "client's place names, else Classic's zone); 'notyet' = new dungeons in codex/loot.json "
                "with no dungeon map in the client.",
        "zones": zones, "taxi": taxi, "routes": routes, "towns": towns,
        "dungeons": dungeons, "unplaced": unplaced, "notyet": notyet,
    }
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, separators=(",", ":"))
        fh.write("\n")
    lv = sum(1 for z in zones.values() if "lv" in z)
    print("build", build, "->", os.path.relpath(OUT, ROOT), "%d bytes" % os.path.getsize(OUT))
    print("  zones %d (%d with levels), flight masters %d, routes %d, towns %d, doors %d, unplaced %s"
          % (len(zones), lv, len(taxi), len(routes), len(towns), len(dungeons), ", ".join(unplaced)))
    print("  not in the client yet:", ", ".join(notyet) or "none")
    for d in dungeons:
        far = sorted(area[a]["AreaName_lang"] for a in d.get("zp", {}) if a != d.get("z"))
        print("  door %-20s in %-20s also on %s" % (d["n"], d.get("w", "?"), ", ".join(far) or "-"))
    for aid, z in zones.items():
        if z.get("out"):
            print("  trimmed %-22s %s -> %d-%d" % (area[aid]["AreaName_lang"], z["out"], z["lv"][0], z["lv"][1]))


# Capitals: one exploration level for the whole city, no range worth showing.
CITY = {"1519", "1537", "1497", "1637", "1638", "1657"}

if __name__ == "__main__":
    main()
