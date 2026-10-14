#!/usr/bin/env python3
"""Where each dungeon boss stands on Blizzard's floor art, for the Dungeon Journal's map (DungeonMap.lua).

The Forever client ships the old dungeon floor art (Interface/WorldMap/<folder>/<folder><floor>_<tile>.blp) but no
map rows for instances, so the game can't place anything on it. MoP Classic's client still uses the very same files
(matched here by file id through UiMapArtTile -> UiMapXMapArt) and its UiMapAssignment says which world rectangle
each floor covers. The bosses' spawn points come from the CMaNGOS Classic database (GPL-3.0, research/cmangos), by
name. A boss Forever added has no spawn there and gets no pin.

  python3 tools/questbank/boss_spots.py    # -> research/questbank/boss_spots.json

{"spots": {dmap key: {boss name: [floor, x, y]}}, "models": {boss name: creature display id}}: x and y are 0-1 across
the floor art (left to right, top to bottom); the display id lets the client draw the boss's own portrait
(SetPortraitTextureFromCreatureDisplayID), summoned bosses included. Needs research/wago/5.5.4.70268/UiMap*.csv
(wago.tools db2 csv, build 5.5.4.70268) and research/questbank/manifest.json.
"""
import csv, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import cmangos  # noqa: E402

MOP = os.path.join(REPO, "research", "wago", "5.5.4.70268")
MAN = json.load(open(os.path.join(REPO, "research", "questbank", "manifest.json")))
OUT = os.path.join(REPO, "research", "questbank", "boss_spots.json")
FOLDERS = {"d1581": "TheDeadmines", "d717": "TheStockade", "d718": "WailingCaverns", "d719": "BlackFathomDeeps",
           "d209": "ShadowfangKeep", "d796": "ScarletMonastery", "d491": "RazorfenKraul", "d1337": "Uldaman",
           "d721": "Gnomeregan", "d2437": "Ragefire", "d722": "RazorfenDowns", "d1417": "TheTempleofAtalhakkar",
           "d1584": "BlackrockDepths", "d1583": "BlackrockSpire", "d2057": "Scholomance", "d2017": "Stratholme",
           "d2557": "DireMaul", "d2100": "Maraudon"}
LOOT_KEYS = {"The Deadmines": "d1581", "The Stockade": "d717", "Wailing Caverns": "d718", "Blackfathom Deeps": "d719",
             "Shadowfang Keep": "d209", "Scarlet Monastery: Graveyard": "d796", "Scarlet Monastery: Library": "d796",
             "Scarlet Monastery: Armory": "d796", "Scarlet Monastery: Cathedral": "d796", "Razorfen Kraul": "d491",
             "Uldaman": "d1337", "Gnomeregan": "d721", "Ragefire Chasm": "d2437", "Razorfen Downs": "d722",
             "The Temple of Atal'Hakkar": "d1417", "Blackrock Depths": "d1584", "Blackrock Spire: Lower": "d1583",
             "Blackrock Spire: Upper": "d1583", "Scholomance": "d2057", "Stratholme": "d2017", "Dire Maul: East": "d2557",
             "Dire Maul: North": "d2557", "Dire Maul: West": "d2557", "Maraudon": "d2100"}
# loot names the Classic database spells another way: the Ring of Law's fighters go by their own names, the client
# spells Gelihast "Geilhast", a pair is named by its first, and the Sunken Temple's balcony minibosses are six trolls
# (Gasher the first). For the model only: a spawn of the stand-in would put a second pin on the one it stands for
RING = "Ring of Law: "
ALIAS = {"Geilhast": "Gelihast", "Fel Steed / Shadow Charger": "Fel Steed", "Balcony Minibosses": "Gasher"}


def db_name(name, alias=False):
    """The Classic database's name (lower case) for a loot entry's name."""
    name = name[len(RING):] if name.startswith(RING) else name
    return (ALIAS.get(name, name) if alias else name).lower()


def rd(t):
    return list(csv.DictReader(open(os.path.join(MOP, t + ".csv"))))


def floor_rects():
    """{dmap key: [(floor, [rects])]}: each rect {map, lo (x, y, z), hi (x, y, z), umin (u, v), umax (u, v)}."""
    art_of_file, maps_of_art, by_map = {}, {}, {}
    for t in rd("UiMapArtTile"):
        art_of_file.setdefault(int(t["FileDataID"]), set()).add(t["UiMapArtID"])
    for x in rd("UiMapXMapArt"):
        maps_of_art.setdefault(x["UiMapArtID"], set()).add(x["UiMapID"])
    for a in rd("UiMapAssignment"):
        r = [float(a["Region_%d" % i]) for i in range(6)]
        by_map.setdefault(a["UiMapID"], []).append({"map": int(a["MapID"]), "lo": r[0:3], "hi": r[3:6],
            "umin": [float(a["UiMin_0"]), float(a["UiMin_1"])], "umax": [float(a["UiMax_0"]), float(a["UiMax_1"])]})
    out = {}
    for key, folder in FOLDERS.items():
        f = 1
        while True:
            k = "interface/worldmap/%s/%s%d_1.blp" % (folder.lower(), folder.lower(), f)
            if k not in MAN:
                break
            ui = set()
            for art in art_of_file.get(int(MAN[k]), ()):
                ui |= maps_of_art.get(art, set())
            rects = [r for u in sorted(ui, key=int)[:1] for r in by_map.get(u, [])]
            out.setdefault(key, []).append((f, rects))
            f += 1
    return out


def place(floors, m, x, y, z):
    """(floor, u, v) for a world point, from the smallest rect that holds it; None when no floor does."""
    best = None
    for f, rects in floors:
        for r in rects:
            if r["map"] != m:
                continue
            (x0, y0, z0), (x1, y1, z1) = r["lo"], r["hi"]
            if not (x0 <= x <= x1 and y0 <= y <= y1 and z0 - 5 <= z <= z1 + 5):
                continue
            area = (x1 - x0) * (y1 - y0)
            u = r["umin"][0] + (y1 - y) / (y1 - y0) * (r["umax"][0] - r["umin"][0])
            v = r["umin"][1] + (x1 - x) / (x1 - x0) * (r["umax"][1] - r["umin"][1])
            if best is None or area < best[0]:
                best = (area, f, round(u, 4), round(v, 4))
    return best and best[1:]


def main():
    floors = floor_rects()
    cmangos.WANT |= {"spawn_group", "spawn_group_entry", "spawn_group_spawn"}
    data = cmangos.read()
    # spawn groups: a row with id 0 in a group stands for any of the group's entries (Lady Anacondra, Gyth, ...)
    gkind = {r[idx["id"]]: ("gameobject" if r[idx["type"]] == 1 else "creature") for idx, r in data["spawn_group"]}
    gentries = {}
    for idx, r in data["spawn_group_entry"]:
        gentries.setdefault(r[idx["id"]], []).append(r[idx["entry"]])
    by_guid = {}
    for idx, r in data["spawn_group_spawn"]:
        g = r[idx["id"]]
        by_guid.setdefault((gkind.get(g, "creature"), r[idx["guid"]]), []).extend(gentries.get(g, []))
    # creatures by name, then objects (a chest such as the Dark Coffer stands for its "boss"); a spawn row with id 0
    # stands for one of several entries (creature_spawn_entry / gameobject_spawn_entry)
    names, spawns, model = {}, {}, {}
    for kind in ("creature", "gameobject"):
        for idx, r in data[kind + "_template"]:
            names.setdefault(r[idx["name"]].lower(), []).append((kind, r[idx["entry"]]))
            if kind == "creature" and r[idx["modelid1"]]:
                model.setdefault(r[idx["name"]].lower(), r[idx["modelid1"]])
        alt = {}
        for idx, r in data[kind + "_spawn_entry"]:
            alt.setdefault(r[idx["guid"]], []).append(r[idx["entry"]])
        for idx, r in data[kind]:
            for e in [r[idx["id"]]] if r[idx["id"]] else alt.get(r[idx["guid"]], []) + by_guid.get((kind, r[idx["guid"]]), []):
                spawns.setdefault((kind, e), []).append((r[idx["map"]], r[idx["position_x"]], r[idx["position_y"]], r[idx["position_z"]]))
    loot = json.load(open(os.path.join(REPO, "codex", "loot.json")))
    out, missed, models = {}, [], {}
    for d in loot.get("dungeons", []):
        key = LOOT_KEYS.get(d.get("name"))
        if key not in floors:
            continue
        maps = {r["map"] for _, rects in floors[key] for r in rects}
        for b in d.get("bosses", []):
            if model.get(db_name(b["name"], True)):
                models[b["name"]] = model[db_name(b["name"], True)]
            spot = None
            for entry in names.get(db_name(b["name"]), []):
                for m, x, y, z in spawns.get(entry, []):
                    if m in maps:
                        spot = place(floors[key], m, x, y, z)
                        if spot:
                            break
                if spot:
                    break
            if spot:
                out.setdefault(key, {})[b["name"]] = list(spot)
            elif b.get("kind", "boss") == "boss":
                missed.append("%s: %s" % (d["name"], b["name"]))
    json.dump({"spots": out, "models": models}, open(OUT, "w"), indent=1, sort_keys=True)
    print("models for %d bosses" % len(models))
    print("placed %d bosses in %d dungeons -> %s" % (sum(len(v) for v in out.values()), len(out), os.path.relpath(OUT, REPO)))
    print("no spawn on the floor art for %d bosses (Forever's own or renamed):" % len(missed))
    for m in missed:
        print("  " + m)


if __name__ == "__main__":
    main()
