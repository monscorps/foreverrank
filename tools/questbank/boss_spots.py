#!/usr/bin/env python3
"""Where each dungeon boss stands on Blizzard's floor art, for the Dungeon Journal's map (DungeonMap.lua).

The Forever client ships the old dungeon floor art (Interface/WorldMap/<folder>/<folder><floor>_<tile>.blp) but no
map rows for instances, so the game can't place anything on it. MoP Classic's client still uses the very same files
(matched here by file id through UiMapArtTile -> UiMapXMapArt) and its UiMapAssignment says which world rectangle
each floor covers and, since every floor of a keep shares one rectangle, which WMO groups (rooms of the building) each
floor is: a boss's floor is the group it stands in (wmo_floors.py reads the buildings), the rectangle then gives the
spot on the art. The bosses' spawn points come from the CMaNGOS Classic database (GPL-3.0, research/cmangos), by
name. A boss Forever added has no spawn there and gets no pin; one an event summons stands in for the room it
appears in (STAND_IN).

  python3 tools/questbank/boss_spots.py    # -> research/questbank/boss_spots.json

{"spots": {dmap key: {boss name: [floor, x, y]}}, "models": {boss name: creature display id}}: x and y are 0-1 across
the floor art (left to right, top to bottom); the display id lets the client draw the boss's own portrait
(SetPortraitTextureFromCreatureDisplayID), summoned bosses included. Needs research/wago/5.5.4.70268/UiMap*.csv
(wago.tools db2 csv, build 5.5.4.70268), research/questbank/manifest.json and research/questbank/wmo_floors.json
(wmo_floors.py). Prints every boss it could not put in a room (placed by the rectangle alone: the first floor
holding its spot) so a wrong floor is never silent.
"""
import csv, json, math, os, sys

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


MID = 17066.666  # half the world's width: the map files' origin, in yards from the game's


def floor_rects():
    """{dmap key: [(floor, [rects])]}: each rect {map, group (WMOGroupID), lo (x, y, z), hi (x, y, z), umin (u, v),
    umax (u, v)}, every UiMap drawn with the floor's art (Scholomance's old map and its new one share theirs)."""
    art_of_file, maps_of_art, by_map = {}, {}, {}
    for t in rd("UiMapArtTile"):
        art_of_file.setdefault(int(t["FileDataID"]), set()).add(t["UiMapArtID"])
    for x in rd("UiMapXMapArt"):
        maps_of_art.setdefault(x["UiMapArtID"], set()).add(x["UiMapID"])
    for a in rd("UiMapAssignment"):
        r = [float(a["Region_%d" % i]) for i in range(6)]
        by_map.setdefault(a["UiMapID"], []).append({"map": int(a["MapID"]), "group": int(a["WMOGroupID"]), "lo": r[0:3], "hi": r[3:6],
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
            rects = [r for u in sorted(ui, key=int) for r in by_map.get(u, [])]
            out.setdefault(key, []).append((f, rects))
            f += 1
    return out


def rotation(rot):
    """The placement's rotation (degrees about the map files' x, y and z) as the game applies it: yaw about the up axis
    first, then pitch and roll (Rz(y) Ry(x) Rx(z), the vmap extractor's order), as a 3x3 matrix over the internal frame."""
    a, b, c = (math.radians(v) for v in (rot[1], rot[0], rot[2]))
    rz = [[math.cos(a), -math.sin(a), 0], [math.sin(a), math.cos(a), 0], [0, 0, 1]]
    ry = [[math.cos(b), 0, math.sin(b)], [0, 1, 0], [-math.sin(b), 0, math.cos(b)]]
    rx = [[1, 0, 0], [0, math.cos(c), -math.sin(c)], [0, math.sin(c), math.cos(c)]]
    mul = lambda p, q: [[sum(p[i][k] * q[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    return mul(mul(rz, ry), rx)


def to_local(gx, gy, gz, pos, rot):
    """A game point in a placed WMO's own frame. The map files keep a WMO's place as (x, height, z) from the world's
    corner; the game's x and y run the other way from the middle. A WMO placed at the origin stands at the middle."""
    px, py, pz = pos
    if px == 0 and pz == 0:
        px = pz = MID
    v = (MID - gx - pz, MID - gy - px, gz - py)
    m = rotation(rot)  # local = m^-1 v, and m^-1 is m transposed
    return tuple(sum(m[k][i] * v[k] for k in range(3)) for i in range(3))


class Rooms:
    """Which WMO group (room) of a dungeon map a game point lies in: the smallest one around it, with a floor."""

    def __init__(self, path):
        self.maps = json.load(open(path))["maps"] if os.path.exists(path) else {}

    def find(self, m, x, y, z, assigned, reach=60):
        """(group id, group name) of the smallest assigned group whose box holds the point, else the nearest one at the
        point's height within reach yards (a stair or doorway the floors' rows leave out, a room they forgot: the
        Beast's); None beyond."""
        best = None
        for w in self.maps.get(str(m), []):
            if not w["groups"]:
                continue
            lx, ly, lz = to_local(x, y, z, w["pos"], w["rot"])
            for g in w["groups"]:
                if g["uid"] not in assigned:
                    continue
                (x0, y0, z0), (x1, y1, z1) = g["lo"], g["hi"]
                dz = max(z0 - lz, 0, lz - z1)
                d = math.sqrt(max(x0 - lx, 0, lx - x1) ** 2 + max(y0 - ly, 0, ly - y1) ** 2 + dz ** 2)
                if d > reach or dz > 3:
                    continue
                rank = (round(d, 1), (x1 - x0) * (y1 - y0) * (z1 - z0))
                if best is None or rank < best[0]:
                    best = (rank, g["uid"], g["name"])
        return best and best[1:]

    def centre(self, m, name, assigned):
        """The middle of the floor of the biggest assigned group called name (the subzone WMOAreaTable names, or the
        file's own name for the group), in game coordinates; None when the map has no such room."""
        best = None
        for w in self.maps.get(str(m), []):
            for g in w["groups"]:
                if g["uid"] in assigned and name.lower() in (g.get("area", "").lower(), g["name"].lower()):
                    # the subzone's name over the file's (the file calls a hall of the lower spire the Stadium)
                    rank = (name.lower() == g.get("area", "").lower(), (g["hi"][0] - g["lo"][0]) * (g["hi"][1] - g["lo"][1]) * (g["hi"][2] - g["lo"][2]))
                    if best is None or rank > best[0]:
                        best = (rank, w, g)
        if not best:
            return None
        _, w, g = best
        lx, ly, lz = ((a + b) / 2 for a, b in zip(g["lo"], g["hi"]))
        px, py, pz = w["pos"]
        if px == 0 and pz == 0:
            px = pz = MID
        r = rotation(w["rot"])
        vx, vy, vz = (sum(r[i][k] * (lx, ly, g["lo"][2])[k] for k in range(3)) for i in range(3))
        return MID - vx - pz, MID - vy - px, vz + py


def uv(r, x, y):
    (x0, y0, _), (x1, y1, _) = r["lo"], r["hi"]
    u = r["umin"][0] + (y1 - y) / (y1 - y0) * (r["umax"][0] - r["umin"][0])
    v = r["umin"][1] + (x1 - x) / (x1 - x0) * (r["umax"][1] - r["umin"][1])
    return round(u, 4), round(v, 4)


def place(floors, rooms, m, x, y, z):
    """(floor, u, v, how) for a world point: the floor whose room (WMO group) it stands in, else ("rect") the floor
    whose rectangle holds it; None when no floor's does."""
    assigned = {}
    for f, rects in floors:
        for r in rects:
            if r["map"] == m and r["group"]:
                assigned.setdefault(r["group"], []).append((f, r))
    room = rooms.find(m, x, y, z, assigned)
    if room:
        # a group on several floors (Dragonspire Hall, the whole spire) has a row a floor, each with its own height:
        # the floor whose row starts highest under the point
        rows = sorted(assigned[room[0]], key=lambda fr: fr[1]["lo"][2])
        f, r = rows[0]
        for f2, r2 in rows:
            if r2["lo"][2] <= z:
                f, r = f2, r2
        (x0, y0, _), (x1, y1, _) = r["lo"], r["hi"]
        if x0 <= x <= x1 and y0 <= y <= y1:
            return (f,) + uv(r, x, y) + ("room %s" % (room[1] or room[0]),)
    # no room: the rectangles, and of those holding the point the one whose floor starts highest under it (a floor's
    # row with a height of its own, over the rows that span the whole keep)
    best = None
    for f, rects in floors:
        for r in rects:
            (x0, y0, z0), (x1, y1, z1) = r["lo"], r["hi"]
            if r["map"] == m and x0 <= x <= x1 and y0 <= y <= y1 and z0 <= z <= z1 and (best is None or z0 > best[0]):
                best = (z0, f, r)
    if best:
        return (best[1],) + uv(best[2], x, y) + ("rect",)
    return None


# a floor the client's tables never place anything on: Blackrock Spire's seventh art is the old map of the upper
# spire (the tables stop at the lower spire's six floors and put the upper spire's rooms on the sixth, where its
# art only sketches them). Its rectangle was fitted to the rooms the art draws (the Stadium, the Furnace, the Spire
# Throne, the Hall of Blackhand): (floor, map, (x0, y0), (x1, y1), the rooms on it by WMOAreaTable's names)
EXTRA = {"d1583": [(7, 229, (-235, -816), (285, -36),
                    ("Hall of Blackhand", "Hall of Binding", "The Rookery", "Blackrock Stadium", "The Furnace", "Spire Throne"))]}


def with_extra(floors, rooms):
    """The floors with EXTRA's rooms moved onto their own floor."""
    for key, extras in EXTRA.items():
        for f, m, (x0, y0), (x1, y1), areas in extras:
            uids = {g["uid"] for w in rooms.maps.get(str(m), []) for g in w["groups"] if g.get("area") in areas}
            kept = [(fl, [r for r in rects if r["group"] not in uids]) for fl, rects in floors[key] if fl != f]
            rects = [{"map": m, "group": u, "lo": [x0, y0, -10000.0], "hi": [x1, y1, 1000000.0], "umin": [0.0, 0.0], "umax": [1.0, 1.0]} for u in sorted(uids)]
            floors[key] = sorted(kept + [(f, rects)])
    return floors


# where a floor's art is blank parchment: MoP Classic's Wailing Caverns end where the old caverns go on east (Lord
# Pythas, Skum), so its art draws nothing right of three quarters across. A spot there gets no pin: (u0, u1, v0, v1)
DRAWN = {"d718": (0.0, 0.77, 0.0, 1.0)}


# bosses an event summons, which have no spawn of their own: the spawn they appear at (another name in the database:
# the brazier or trigger that calls them, the chest or NPC they stand by) or, failing that, the room they appear in
# (a WMO group's name, as WMOAreaTable has it; the biggest group of the name, which is the hall and not its stairs)
STAND_IN = {"Sneed": "Sneed's Shredder", "Fel Steed / Shadow Charger": "Fel Steed", "Arugal's Voidwalker": "Archmage Arugal",
            "Jordan's Smithing Hammer": "Jordan's Hammer", "Baron Aquanis": "Fathom Stone", "Geilhast": "Gelihast",
            "Grubbis": "Blastmaster Emi Shortfuse", "Ironaya": "Keystone", "Tuten'kash": "Gong",
            "Plaguemaw the Rotting": "Belnistrasz's Brazier", "Balcony Minibosses": "Gasher", "Avatar of Hakkar": "Altar of Hakkar",
            "Shade of Hakkar": "Altar of Hakkar", "Watchman Doomgrip": "Dark Coffer", "Guzzler": "Grim Guzzler Boar",
            "Hurley Blackbreath": "Grim Guzzler Boar", "Urok Doomhowl": "Urok's Tribute Pile", "Gizrul the Slavener": "Halycon",
            "Mor Grayhoof": "Mor Grayhoof Trigger", "Lord Valthalak": "Lord Valthalak Trigger", "Isalien": "Isalien Trigger",
            "Kormok": "Kormok Trigger", "Solakar Flamewreath": "The Rookery", "Gyth": "Blackrock Stadium",
            "Warchief Rend Blackhand": "Blackrock Stadium", "Mizzle the Crafty": "King Gordok", "Kirtonos the Herald": "Chamber of Summoning",
            "Darkmaster Gandling": "Headmaster's Study", "Death Knight Darkreaver": "The Great Ossuary", "Balnazzar": "Grand Crusader Dathrohan",
            "Ramstein the Gorger": "Baron Rivendare", "Atal'alarion": "The Pit of Refuse", "Dreamscythe": "Hazzas", "Weaver": "Morphaz",
            "Mutanus the Devourer": "Naralex",
            **dict.fromkeys(("Anub'shiah", "Eviscerator", "Gorosh the Dervish", "Grizzle", "Hedrum the Creeper", "Ok'thor the Breaker"), "Theldren Trigger")}


def main():
    rooms = Rooms(os.path.join(REPO, "research", "questbank", "wmo_floors.json"))
    floors = with_extra(floor_rects(), rooms)
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

    def points(name, maps):
        """The spawns of a name on the dungeon's maps."""
        for entry in names.get(name, []):
            for m, x, y, z in spawns.get(entry, []):
                if m in maps:
                    yield m, x, y, z

    loot = json.load(open(os.path.join(REPO, "codex", "loot.json")))
    out, missed, by_rect, blank, models = {}, [], [], [], {}
    for d in loot.get("dungeons", []):
        key = LOOT_KEYS.get(d.get("name"))
        if key not in floors:
            continue
        maps = {r["map"] for _, rects in floors[key] for r in rects}
        assigned = {r["group"] for _, rects in floors[key] for r in rects if r["group"]}
        for b in d.get("bosses", []):
            if model.get(db_name(b["name"], True)):
                models[b["name"]] = model[db_name(b["name"], True)]
            pts = list(points(db_name(b["name"]), maps))
            stand = STAND_IN.get(b["name"]) or STAND_IN.get(b["name"][len(RING):] if b["name"].startswith(RING) else "")
            if not pts and stand:
                pts = list(points(stand.lower(), maps))[:1]
                if not pts:
                    for m in maps:
                        c = rooms.centre(m, stand, assigned)
                        if c:
                            pts.append((m,) + c)
            spot = None
            for m, x, y, z in pts:
                spot = place(floors[key], rooms, m, x, y, z)
                if spot:
                    break
            u0, u1, v0, v1 = DRAWN.get(key, (0.0, 1.0, 0.0, 1.0))
            if spot and not (u0 <= spot[1] <= u1 and v0 <= spot[2] <= v1):
                blank.append("%s: %s (floor %d, %.2f across, %.2f down)" % (d["name"], b["name"], spot[0], spot[1], spot[2]))
            elif spot:
                out.setdefault(key, {})[b["name"]] = list(spot[:3])
                if spot[3] == "rect":
                    by_rect.append("%s: %s (floor %d)" % (d["name"], b["name"], spot[0]))
            elif b.get("kind", "boss") == "boss":
                missed.append("%s: %s" % (d["name"], b["name"]))
    json.dump({"spots": out, "models": models}, open(OUT, "w"), indent=1, sort_keys=True)
    print("models for %d bosses" % len(models))
    print("placed %d bosses in %d dungeons -> %s" % (sum(len(v) for v in out.values()), len(out), os.path.relpath(OUT, REPO)))
    print("placed by the rectangle alone, no room known for them (check their floor): %d" % len(by_rect))
    for m in by_rect:
        print("  " + m)
    print("standing where the art is blank, no pin: %d" % len(blank))
    for m in blank:
        print("  " + m)
    print("no spawn on the floor art for %d bosses (Forever's own or renamed):" % len(missed))
    for m in missed:
        print("  " + m)


if __name__ == "__main__":
    main()
