#!/usr/bin/env python3
"""Classic's rare spawns, placed on Forever's maps: codex/rares.json for the Database's Rare spawns list.

Every rare and rare elite (creature_template.Rank 4 and 2) the CMaNGOS Classic database (research/cmangos,
GPL-3.0) spawns in the open world, with its level, type, Classic respawn time and spawn points. The points are
Classic world coordinates, drawn on the Forever client's own zone maps (UiMapAssignment, tools/questbank/travel.py)
in map percent. Zone rectangles overlap at the borders (Durotar's map reaches into the Barrens), so where a point lies
on several maps the zone whose levels fit the rare wins: AreaTable.ExplorationLevel of the zone's areas, middle 80%. This is Classic data: Forever may have moved, changed or removed any of these rares, and the
Database says so on every row. Rares seen in Forever's dungeons come from codex/loot.json at page load, not from here.

  python3 tools/build_rares.py                 # build below
  python3 tools/build_rares.py 1.60.1.70291
"""
import collections, csv, datetime, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "questbank"))
BUILD = sys.argv[1] if len(sys.argv) > 1 else "1.60.1.70291"
OUT = os.path.join(ROOT, "codex", "rares.json")
OVERLAY = {2482, 2548, 2652}  # Mount Hyjal, the Riverglades, Shen'dralas: Forever maps drawn over Classic zones
TYPES = {1: "Beast", 2: "Dragonkin", 3: "Demon", 4: "Elemental", 5: "Giant", 6: "Undead", 7: "Humanoid", 8: "Critter", 9: "Mechanical"}
# a row's icon: the client's own icon for a beast's pet family, else one for its creature type
TYPE_ICON = {"Beast": "ability_hunter_beasttaming", "Dragonkin": "inv_misc_head_dragon_01", "Demon": "spell_shadow_summonfelhunter",
             "Elemental": "spell_nature_earthelemental_totem", "Giant": "ability_warrior_bloodbath", "Undead": "spell_shadow_raisedead",
             "Humanoid": "inv_misc_head_human_01", "Critter": "ability_hunter_pet_wolf", "Mechanical": "inv_gizmo_02"}
SKIP = re.compile(r"\[|\bDND\b|\bDNT\b|Trigger|\(test\)|Test ", re.I)
MAX_POINTS = 12


def zone_levels():
    """uiMap -> (low, high) exploration level of the zone's own areas, the middle 80%."""
    base = os.path.join(ROOT, "research", "wago", BUILD)
    at = {r["ID"]: r for r in csv.DictReader(open(os.path.join(base, "AreaTable.csv"), encoding="utf-8"))}
    kids = collections.defaultdict(list)
    for r in at.values():
        kids[r["ParentAreaID"]].append(int(r["ExplorationLevel"] or 0))
    out = {}
    for r in csv.DictReader(open(os.path.join(base, "UiMapAssignment.csv"), encoding="utf-8")):
        if r["OrderIndex"] != "0" or r["AreaID"] in ("", "0"):
            continue
        lv = sorted(x for x in kids[r["AreaID"]] + [int(at.get(r["AreaID"], {}).get("ExplorationLevel") or 0)] if x > 0)
        if lv:
            out[int(r["UiMapID"])] = (lv[len(lv) // 10], lv[(len(lv) * 9) // 10 - (1 if len(lv) >= 10 else 0)])
    return out


def place(tr, bands, cont, wx, wy, level):
    """(uiMap, x, y): of the maps holding the point, the deepest one whose levels fit, else travel.py's pick."""
    fit = []
    for mid, m in tr.maps.items():
        if m["cont"] != cont or mid in (947, 1414, 1415, 1945) or not m["area"] or mid not in bands:
            continue
        if m["minx"] <= wx <= m["maxx"] and m["miny"] <= wy <= m["maxy"]:
            x, y = tr._pct(m, wx, wy)
            lo, hi = bands[mid]
            if lo - 4 <= level <= hi + 4:
                fit.append((min(x, 100 - x, y, 100 - y), mid, x, y))
    if fit:
        d, mid, x, y = max(fit)
        return mid, x, y
    return tr.locate(cont, wx, wy)


def main():
    import cmangos
    from travel import Travel
    tr = Travel(BUILD)
    for m in OVERLAY:
        tr.maps.pop(m, None)
    uimap = {int(r["ID"]): r["Name_lang"] for r in csv.DictReader(open(os.path.join(ROOT, "research", "wago", BUILD, "UiMap.csv"), encoding="utf-8"))}
    icons = {}
    for line in open(os.path.join(ROOT, "tools", "icon-listfile.csv"), encoding="utf-8"):
        fid, _, path = line.strip().partition(";")
        if path.startswith("interface/icons/"):
            icons[fid] = path[16:].rsplit(".", 1)[0]
    family, fam_icon = {}, {}
    fam_path = os.path.join(ROOT, "research", "wago", BUILD, "CreatureFamily.csv")
    if os.path.exists(fam_path):
        for r in csv.DictReader(open(fam_path, encoding="utf-8")):
            family[int(r["ID"])] = r["Name_lang"]
            fam_icon[int(r["ID"])] = icons.get(r["IconFileID"])

    bands = zone_levels()
    data = cmangos.read()
    rares = {}
    for idx, r in data["creature_template"]:
        if r[idx["rank"]] in (2, 4) and not SKIP.search(r[idx["name"]] or ""):
            rares[r[idx["entry"]]] = (idx, r)
    # spawn rows (and pooled spawns: a row with id 0 stands for each entry in creature_spawn_entry)
    pooled = collections.defaultdict(list)
    for idx, r in data["creature_spawn_entry"]:
        pooled[r[idx["guid"]]].append(r[idx["entry"]])
    seasonal = {r[idx["guid"]] for idx, r in data["game_event_creature"] if (r[idx["event"]] or 0) > 0}
    spawns = collections.defaultdict(list)
    for idx, r in data["creature"]:
        if r[idx["map"]] not in (0, 1) or r[idx["guid"]] in seasonal:
            continue
        for e in [r[idx["id"]]] if r[idx["id"]] else pooled.get(r[idx["guid"]], []):
            if e in rares:
                spawns[e].append((r[idx["map"]], r[idx["position_x"]], r[idx["position_y"]],
                                  r[idx["spawntimesecsmin"]] or 0, r[idx["spawntimesecsmax"]] or 0))

    out, nowhere = [], 0
    for e, pts in spawns.items():
        idx, r = rares[e]
        placed = []
        level = (r[idx["minlevel"]] + r[idx["maxlevel"]]) / 2.0
        for cont, x, y, t0, t1 in pts:
            at = place(tr, bands, cont, x, y, level)
            if at:
                placed.append((at[0], round(at[1], 1), round(at[2], 1), t0, t1))
        if not placed:
            nowhere += 1
            continue
        zone = collections.Counter(p[0] for p in placed).most_common(1)[0][0]
        seen, pts_out = set(), []
        for m, x, y, _, _ in sorted(placed, key=lambda p: (p[0] != zone, p[0], p[1], p[2])):
            k = (m, round(x), round(y))  # one point per map percent square
            if k in seen:
                continue
            seen.add(k)
            pts_out.append([m, x, y])
        t0 = min(p[3] for p in placed)
        t1 = max(p[4] for p in placed)
        lo, hi = r[idx["minlevel"]], r[idx["maxlevel"]]
        row = {"id": e, "n": r[idx["name"]], "lv": [lo, hi] if hi != lo else lo, "rk": "rare elite" if r[idx["rank"]] == 2 else "rare",
               "z": zone, "pts": pts_out[:MAX_POINTS]}
        if len(pts_out) > MAX_POINTS:
            row["more"] = len(pts_out) - MAX_POINTS
        if r[idx["subname"]]:
            row["sub"] = r[idx["subname"]]
        ty = TYPES.get(r[idx["creaturetype"]])
        if ty:
            row["ty"] = ty
        if r[idx["family"]] and family.get(r[idx["family"]]):
            row["fam"] = family[r[idx["family"]]]
            if (r[idx["creaturetypeflags"]] or 0) & 1:
                row["tame"] = 1
        ic = fam_icon.get(r[idx["family"]]) or TYPE_ICON.get(ty)
        if ic:
            row["i"] = ic
        if t1:
            row["rs"] = [t0, t1]
        out.append(row)
    out.sort(key=lambda x: (uimap.get(x["z"], ""), x["lv"] if isinstance(x["lv"], int) else x["lv"][0], x["n"]))
    zones = {str(z): [uimap.get(z, ""), "Kalimdor" if tr.maps[z]["cont"] == 1 else "Eastern Kingdoms"]
             for z in sorted({p[0] for x in out for p in x["pts"]})}
    note = ("Rare spawns from the CMaNGOS Classic database (github.com/cmangos/classic-db, GPL-3.0): Classic data, so "
            "Forever may have moved, changed or removed any of them. Spawn points are Classic world positions drawn on the "
            "Forever beta client's zone maps, build %s (tools/build_rares.py). Respawn times are Classic's." % BUILD)
    json.dump({"note": note, "build": BUILD, "generated": datetime.date.today().isoformat(), "zones": zones, "rares": out},
              open(OUT, "w"), ensure_ascii=False, separators=(",", ":"))
    print("wrote %s: %d rares in %d zones (%d with no open-world spawn left out)" % (
        os.path.relpath(OUT, ROOT), len(out), len({x["z"] for x in out}), len(rares) - len(out)))
    print("  by zone:", collections.Counter(uimap.get(x["z"]) for x in out).most_common(12))
    print("  rank:", collections.Counter(x["rk"] for x in out), "tameable:", sum(1 for x in out if x.get("tame")), "off-map:", nowhere)


if __name__ == "__main__":
    main()
