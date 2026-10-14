#!/usr/bin/env python3
"""The dungeons' building blocks, for boss_spots.py: which WMO group each spot of a dungeon lies in.

MoP Classic's UiMapAssignment puts a floor of the Dungeon Journal's map on WMO groups (WMOGroupID: a group's own id,
WMOAreaTable's), not on world rectangles: every floor of a keep shares one rectangle, so a boss's floor can only be
read off the building. This pulls MoP Classic's map files from wago.tools (the WDT, the object ADTs of a map with
terrain, the placed WMOs' roots and their group files) and writes each placed WMO with its groups' ids and bounding
boxes, in the WMO's own frame:

  python3 tools/questbank/wmo_floors.py    # -> research/questbank/wmo_floors.json

{"maps": {map id: [{"fid", "wmoID", "pos" (ADT frame), "rot" (degrees), "groups": [{"i", "uid", "name" (the file's),
"area" (WMOAreaTable's, the subzone the game names), "lo", "hi"}]}]}}. Only WMOs whose groups a floor names get their groups read. Files are cached under
research/wago/5.5.4.70268/world/<file id>.bin (any client file by id, one request at least a second after the last).
Needs research/wago/5.5.4.70268/UiMapAssignment.csv and WMOAreaTable.csv (fetch_wago.py).
"""
import csv, json, os, struct, sys, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
BUILD = "5.5.4.70268"
MOP = os.path.join(REPO, "research", "wago", BUILD)
CACHE = os.path.join(MOP, "world")
OUT = os.path.join(REPO, "research", "questbank", "wmo_floors.json")
UA = {"User-Agent": "foreverrank.com datamine (github.com/monscorps/foreverrank)"}
# the dungeons' maps and their WDT files (Map.csv's WdtFileDataID, the same file id in every client) and the UiMaps
# of their floors (UiMap.csv, by name and MapID), in floor order
MAPS = {36: ("The Deadmines", 780605, [291, 292]), 34: ("The Stockade", 791060, [225]), 43: ("Wailing Caverns", 791429, [279]),
        48: ("Blackfathom Deeps", 780169, [221, 222, 223]), 33: ("Shadowfang Keep", 790796, list(range(310, 317))),
        189: ("Scarlet Monastery", 788662, [302, 303, 304, 305]), 47: ("Razorfen Kraul", 790640, [301]),
        70: ("Uldaman", 791372, [230, 231]), 90: ("Gnomeregan", 782773, [226, 227, 228, 229]), 389: ("Ragefire Chasm", 789981, [213]),
        129: ("Razorfen Downs", 790517, [300]), 109: ("The Temple of Atal'Hakkar", 791166, [220]),
        230: ("Blackrock Depths", 780172, [242, 243]), 229: ("Blackrock Spire", 780175, list(range(250, 256))),
        289: ("Scholomance", 790713, [306, 307, 308, 309]), 329: ("Stratholme", 791063, [317, 318]),
        429: ("Dire Maul", 780814, list(range(235, 241))), 349: ("Maraudon", 788656, [280, 281])}
_last = [0.0]


def fetch(fid):
    """A client file by id, from the cache or wago.tools (at least 1.2 s after the last request)."""
    path = os.path.join(CACHE, "%d.bin" % fid)
    if os.path.exists(path):
        return open(path, "rb").read()
    os.makedirs(CACHE, exist_ok=True)
    wait = _last[0] + 1.2 - time.time()
    if wait > 0:
        time.sleep(wait)
    url = "https://wago.tools/api/casc/%d?version=%s&download" % (fid, BUILD)
    body = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=90).read()
    _last[0] = time.time()
    open(path, "wb").write(body)
    print("  fetched %d (%d bytes)" % (fid, len(body)))
    return body


def chunks(b):
    i = 0
    while i + 8 <= len(b):
        tag = b[i:i + 4][::-1].decode("ascii", "replace")
        n = struct.unpack_from("<I", b, i + 4)[0]
        yield tag, b[i + 8:i + 8 + n]
        i += 8 + n


def modf(b):
    """The WMO placements of a WDT or object ADT: [(root file id, pos, rot)]; the file ids are in the entry (MODF
    flag 8), as every client since 8.1 writes them."""
    out = []
    for tag, body in chunks(b):
        if tag == "MODF":
            for i in range(len(body) // 64):
                e = struct.unpack_from("<2I6f6f4H", body, i * 64)
                out.append((e[0], e[2:5], e[5:8]))
    return out


def tiles(b):
    """The object ADTs of a map with terrain: file ids (MAID) of the tiles the WDT has (MAIN)."""
    main = maid = None
    for tag, body in chunks(b):
        if tag == "MAIN":
            main = body
        elif tag == "MAID":
            maid = body
    out = []
    for i in range(64 * 64):
        if struct.unpack_from("<I", main, i * 8)[0] & 1 and maid:
            out.append(struct.unpack_from("<8I", maid, i * 32)[1])
    return out


def root(b):
    """A WMO root: its id (WMOAreaTable's WMOID), group names and bounding boxes (MOGI) and group file ids (GFID)."""
    out = {"groups": [], "gfid": [], "wmoID": None}
    names = b""
    for tag, body in chunks(b):
        if tag == "MOHD":
            out["wmoID"] = struct.unpack_from("<9I", body)[8]
        elif tag == "MOGN":
            names = body
        elif tag == "MOGI":
            for i in range(len(body) // 32):
                flags, x0, y0, z0, x1, y1, z1, ofs = struct.unpack_from("<I6fi", body, i * 32)
                name = names[ofs:names.find(b"\0", ofs)].decode("latin1") if ofs >= 0 else ""
                out["groups"].append({"i": i, "name": name, "lo": [round(x0, 2), round(y0, 2), round(z0, 2)], "hi": [round(x1, 2), round(y1, 2), round(z1, 2)]})
        elif tag == "GFID":
            out["gfid"] = list(struct.unpack_from("<%dI" % (len(body) // 4), body))
    return out


def group_uid(b):
    """A WMO group file's own id (MOGP's uniqueID: WMOAreaTable's WMOGroupID, UiMapAssignment's WMOGroupID)."""
    for tag, body in chunks(b):
        if tag == "MOGP":
            return struct.unpack_from("<I", body, 56)[0]


def main():
    wmo_of_group, area_of_group = {}, {}
    for r in csv.DictReader(open(os.path.join(MOP, "WMOAreaTable.csv"))):
        wmo_of_group[int(r["WMOGroupID"])] = int(r["WMOID"])
        area_of_group[int(r["WMOGroupID"])] = r["AreaName_lang"].strip()
    need = {}
    for a in csv.DictReader(open(os.path.join(MOP, "UiMapAssignment.csv"))):
        for m, (_, _, uis) in MAPS.items():
            if int(a["UiMapID"]) in uis and int(a["WMOGroupID"]) and int(a["WMOGroupID"]) in wmo_of_group:
                need.setdefault(m, set()).add(wmo_of_group[int(a["WMOGroupID"])])
    out = {}
    for m, (name, wdt, _) in MAPS.items():
        print(name)
        b = fetch(wdt)
        placed = modf(b)
        if not placed:
            for t in tiles(b):
                placed += modf(fetch(t))
        seen = set()
        for fid, pos, rot in placed:
            if (fid, pos) in seen:
                continue
            seen.add((fid, pos))
            r = root(fetch(fid))
            entry = {"fid": fid, "wmoID": r["wmoID"], "pos": [round(v, 3) for v in pos], "rot": [round(v, 3) for v in rot], "groups": []}
            if r["wmoID"] in need.get(m, set()):
                for g, gfid in zip(r["groups"], r["gfid"]):
                    g["uid"] = group_uid(fetch(gfid))
                    g["area"] = area_of_group.get(g["uid"], "")
                    entry["groups"].append(g)
            out.setdefault(str(m), []).append(entry)
        print("  %d WMOs, %d with the floors' groups (%d groups)" % (len(out[str(m)]), sum(1 for e in out[str(m)] if e["groups"]), sum(len(e["groups"]) for e in out[str(m)])))
    json.dump({"build": BUILD, "maps": out}, open(OUT, "w"), indent=1, sort_keys=True)
    print("->", os.path.relpath(OUT, REPO))


if __name__ == "__main__":
    main()
