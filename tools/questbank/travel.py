"""Travel model for QuestBank from the Forever client's own tables.

Hubs are the flight masters each faction can use (TaxiNodes flags: 0x1 Alliance, 0x2 Horde),
plus Darnassus, which has none (the portal in Rut'theran leads up). Flights follow TaxiPath
edges timed by their TaxiPathNode path length. Boats and zeppelins are the client's own
transports (TaxiNodes "Transport, ..." rows: Menethil ships, Rut'theran - Auberdine, Booty Bay -
Ratchet, the Orgrimmar and Grom'gol zeppelins; there is no Stormwind boat in Classic), plus the
Deeprun Tram. Walking between two hubs on the same continent is allowed when it is short.
All-pairs shortest travel is kept as (fixed minutes, walking minutes, main kind) so a mount can
scale only the walking part.

  from travel import Travel
  t = Travel("1.60.1.70058")
  t.hubs["A"], t.pair("A", a, b), t.world(uiMap, x, y), t.nearest_hub("A", continent, wx, wy)
"""
import csv, heapq, math, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FLIGHT_SPEED = 32.0     # yards per second on a flight path
TAKEOFF = 0.25          # minutes to talk to the flight master, mount up and land
RUN = 7.0               # yards per second on foot
DETOUR = 1.3            # roads and hills against a straight line
WALK_LINK = 900.0       # hubs closer than this (yards) are also linked on foot

# Transports as (hub name fragment, hub name fragment, minutes including the average wait, minutes on foot at the ends)
TRANSPORT = {
    "A": [("Menethil", "Theramore", 6.0, 1.0, "boat"), ("Menethil", "Auberdine", 7.0, 1.0, "boat"),
          ("Rut'theran", "Auberdine", 5.0, 0.5, "boat"), ("Booty Bay", "Ratchet", 6.0, 1.0, "boat"),
          ("Ironforge", "Stormwind", 1.5, 2.5, "tram"), ("Rut'theran", "Darnassus", 0.3, 0.7, "portal")],
    "H": [("Orgrimmar", "Undercity", 6.0, 2.0, "zeppelin"), ("Orgrimmar", "Grom'gol", 6.0, 2.0, "zeppelin"),
          ("Undercity", "Grom'gol", 6.0, 2.0, "zeppelin"), ("Booty Bay", "Ratchet", 6.0, 1.0, "boat")],
}
# towns without a flight master that still count as hubs: (name, continent, uiMap, x, y)
EXTRA = {"A": [("Darnassus", 1, 1457, 40.0, 50.0)], "H": []}
# flight towns with an innkeeper, where a hearthstone can be bound
INNS = {"Stormwind", "Goldshire", "Sentinel Hill", "Lakeshire", "Darkshire", "Ironforge", "Kharanos", "Thelsamar",
        "Menethil Harbor", "Southshore", "Aerie Peak", "Booty Bay", "Darnassus", "Dolanaar", "Auberdine", "Astranaar",
        "Stonetalon Peak", "Theramore", "Nijel's Point", "Feathermoon", "Ratchet", "Gadgetzan", "Everlook",
        "Morgan's Vigil", "Orgrimmar", "Razor Hill", "Crossroads", "Camp Taurajo", "Thunder Bluff", "Bloodhoof Village",
        "Undercity", "Brill", "The Sepulcher", "Tarren Mill", "Hammerfall", "Kargath", "Stonard", "Grom'gol",
        "Splintertree Post", "Sun Rock Retreat", "Freewind Post", "Shadowprey Village", "Camp Mojache",
        "Brackenwall Village", "Revantusk Village"}
RANK = {"zeppelin": 5, "boat": 4, "tram": 3, "flight": 2, "portal": 1, "foot": 0}
SKIP = ("zzOLD", "Quest Path", "Transport", "Generic", "Programmer", "Northshire Abbey", "Naxxramas", "Alterac Valley")


def rows(build, table):
    return list(csv.DictReader(open(os.path.join(ROOT, "research", "wago", build, table + ".csv"))))


class Travel:
    def __init__(self, build="1.60.1.70058"):
        self.build = build
        self.maps = {}
        for r in rows(build, "UiMapAssignment"):
            if r["OrderIndex"] != "0" or r["UiMapID"] in ("947",):
                continue
            self.maps[int(r["UiMapID"])] = dict(cont=int(r["MapID"]), minx=float(r["Region_0"]), miny=float(r["Region_1"]),
                                                maxx=float(r["Region_3"]), maxy=float(r["Region_4"]),
                                                u0=float(r["UiMin_0"]), v0=float(r["UiMin_1"]), u1=float(r["UiMax_0"]), v1=float(r["UiMax_1"]),
                                                area=int(r["AreaID"]))
        self.area_map = {m["area"]: k for k, m in self.maps.items() if m["area"] and k not in (1414, 1415, 1463, 1464, 2665)}
        # Forever redrew some maps (Mulgore, Eastern Plaguelands, Redridge, Stormwind); Wowhead still
        # gives some coordinates in the old Classic frame, so keep that frame for comparison
        self.era = {}
        era_path = os.path.join(ROOT, "research", "wago", "era", "UiMapAssignment.csv")
        if os.path.exists(era_path):
            for r in csv.DictReader(open(era_path)):
                if r["OrderIndex"] != "0":
                    continue
                self.era[int(r["UiMapID"])] = dict(cont=int(r["MapID"]), minx=float(r["Region_0"]), miny=float(r["Region_1"]),
                                                   maxx=float(r["Region_3"]), maxy=float(r["Region_4"]), u0=float(r["UiMin_0"]),
                                                   v0=float(r["UiMin_1"]), u1=float(r["UiMax_0"]), v1=float(r["UiMax_1"]))
        keys = ("minx", "miny", "maxx", "maxy", "u0", "v0", "u1", "v1")
        self.redrawn = {mid for mid, m in self.maps.items() if mid in self.era and any(abs(m[k] - self.era[mid][k]) > 1e-3 for k in keys)}
        nodes = {}
        for r in rows(build, "TaxiNodes"):
            name = r["Name_lang"]
            cont = int(r["ContinentID"])
            if cont not in (0, 1) or any(s in name for s in SKIP):
                continue
            flags = int(r["Flags"])
            fac = set()
            if flags & 1 or r["MountCreatureID_1"] != "0": fac.add("A")
            if flags & 2 or r["MountCreatureID_0"] != "0": fac.add("H")
            if not fac:
                continue
            nodes[int(r["ID"])] = dict(id=int(r["ID"]), name=name, cont=cont, x=float(r["Pos_0"]), y=float(r["Pos_1"]), fac=fac)
        self.nodes = nodes
        pts = {}
        for r in rows(build, "TaxiPathNode"):
            pts.setdefault(int(r["PathID"]), []).append((int(r["NodeIndex"]), float(r["Loc_0"]), float(r["Loc_1"]), int(r["ContinentID"])))
        self.flights = []
        for r in rows(build, "TaxiPath"):
            a, b, pid = int(r["FromTaxiNode"]), int(r["ToTaxiNode"]), int(r["ID"])
            if a not in nodes or b not in nodes:
                continue
            p = sorted(pts.get(pid, []))
            length = sum(math.hypot(p[i][1] - p[i - 1][1], p[i][2] - p[i - 1][2]) for i in range(1, len(p)) if p[i][3] == p[i - 1][3])
            if not length:
                length = math.hypot(nodes[a]["x"] - nodes[b]["x"], nodes[a]["y"] - nodes[b]["y"]) * 1.2
            self.flights.append((a, b, TAKEOFF + length / FLIGHT_SPEED / 60.0))
        for fac, extra in EXTRA.items():
            for k, (name, cont, m, x, y) in enumerate(extra):
                _, wx, wy = self.world(m, x, y)
                nid = -1 - k - (0 if fac == "A" else 100)
                self.nodes[nid] = dict(id=nid, name=name, cont=cont, x=wx, y=wy, fac={fac})
        for n in self.nodes.values():
            n["town"] = n["name"].split(",")[0].replace(" City", "")
            n["inn"] = n["town"] in INNS or n["town"].replace("The ", "") in INNS
        self.hubs, self.dist, self.order = {}, {}, {}
        for fac in ("A", "H"):
            self._build(fac)

    def _find(self, fac, frag):
        for n in sorted(self.nodes.values(), key=lambda n: n["id"] < 0):
            if fac in n["fac"] and n["name"].startswith(frag):
                return n["id"]
        raise KeyError(frag)

    def _build(self, fac):
        hubs = sorted((n for n in self.nodes.values() if fac in n["fac"]), key=lambda n: (n["cont"], n["town"]))
        ids = [n["id"] for n in hubs]
        adj = {i: [] for i in ids}
        for a, b, m in self.flights:
            if a in adj and b in adj:
                adj[a].append((b, m, 0.0, "flight"))
        for x in hubs:
            for y in hubs:
                if x["id"] < y["id"] and x["cont"] == y["cont"]:
                    d = math.hypot(x["x"] - y["x"], x["y"] - y["y"])
                    if d < WALK_LINK:
                        w = d * DETOUR / RUN / 60.0
                        adj[x["id"]].append((y["id"], 0.0, w, "foot"))
                        adj[y["id"]].append((x["id"], 0.0, w, "foot"))
        for fa, fb, m, walk, kind in TRANSPORT[fac]:
            a, b = self._find(fac, fa), self._find(fac, fb)
            adj[a].append((b, m, walk, kind))
            adj[b].append((a, m, walk, kind))
        dist = {}
        for s in ids:
            best = {s: (0.0, 0.0, 0.0, None)}
            heap = [(0.0, s, 0.0, 0.0, None)]
            while heap:
                cost, u, f, w, first = heapq.heappop(heap)
                if best.get(u, (1e9,))[0] < cost:
                    continue
                for v, m, walk, kind in adj[u]:
                    nc = cost + m + walk
                    if nc < best.get(v, (1e9,))[0]:
                        k = kind if first is None or RANK[kind] > RANK[first] else first
                        best[v] = (nc, f + m, w + walk, k)
                        heapq.heappush(heap, (nc, v, f + m, w + walk, k))
            for t, (c, f, w, k) in best.items():
                dist[(s, t)] = (round(f, 2), round(w, 2), k)
        self.hubs[fac] = {n["id"]: n for n in hubs}
        self.order[fac] = [n["id"] for n in hubs]
        self.dist[fac] = dist

    def pair(self, fac, a, b):
        return self.dist[fac].get((a, b))

    def world(self, ui_map, x, y, era=False):
        m = (self.era if era else self.maps).get(ui_map)
        if not m:
            return None
        u = (x / 100.0 - m["u0"]) / (m["u1"] - m["u0"])
        v = (y / 100.0 - m["v0"]) / (m["v1"] - m["v0"])
        return m["cont"], m["maxx"] - v * (m["maxx"] - m["minx"]), m["maxy"] - u * (m["maxy"] - m["miny"])

    def to_map(self, ui_map, wx, wy):
        """A world point in a map's Forever frame, in map percent."""
        m = self.maps[ui_map]
        v = (m["maxx"] - wx) / (m["maxx"] - m["minx"])
        u = (m["maxy"] - wy) / (m["maxy"] - m["miny"])
        return round((m["u0"] + u * (m["u1"] - m["u0"])) * 100, 1), round((m["v0"] + v * (m["v1"] - m["v0"])) * 100, 1)

    def _pct(self, m, wx, wy):
        v = (m["maxx"] - wx) / (m["maxx"] - m["minx"])
        u = (m["maxy"] - wy) / (m["maxy"] - m["miny"])
        return (m["u0"] + u * (m["u1"] - m["u0"])) * 100, (m["v0"] + v * (m["v1"] - m["v0"])) * 100

    def locate(self, cont, wx, wy, prefer=None):
        """The zone or city map a world point lies on: (uiMap, x, y) in map percent. Map rectangles
        overlap (Ratchet lies inside Durotar's, the Hinterlands' south edge inside Arathi's), so a
        hinted map wins when it holds the point; a map lying well inside a bigger one (a city in its
        zone) wins next; otherwise the map the point sits deepest in, away from its edges."""
        cands = []
        for mid, m in self.maps.items():
            if m["cont"] != cont or mid in (947, 1414, 1415, 1945) or not m["area"]:
                continue
            if m["minx"] <= wx <= m["maxx"] and m["miny"] <= wy <= m["maxy"]:
                if mid in (prefer or ()):
                    x, y = self._pct(m, wx, wy)
                    return mid, round(x, 1), round(y, 1)
                size = (m["maxx"] - m["minx"]) * (m["maxy"] - m["miny"])
                x, y = self._pct(m, wx, wy)
                cands.append((size, mid, x, y, min(x, 100 - x, y, 100 - y)))
        if not cands:
            return None
        cands.sort()
        if len(cands) == 1 or cands[0][0] <= 0.4 * cands[1][0]:
            _, mid, x, y, _ = cands[0]
        else:
            _, mid, x, y, _ = max(cands, key=lambda c: c[4])
        return mid, round(x, 1), round(y, 1)

    def nearest_hub(self, fac, cont, wx, wy):
        best = None
        for n in self.hubs[fac].values():
            if n["cont"] != cont:
                continue
            d = math.hypot(n["x"] - wx, n["y"] - wy)
            if best is None or d < best[1]:
                best = (n["id"], d)
        return best


if __name__ == "__main__":
    t = Travel()
    for fac in ("A", "H"):
        print(fac, len(t.hubs[fac]), "hubs")
    A = {n["name"].split(",")[0]: i for i, n in t.hubs["A"].items()}
    for a, b in [("Stormwind", "Sentinel Hill"), ("Stormwind", "Ironforge"), ("Stormwind", "Lakeshire"), ("Lakeshire", "Darkshire"),
                 ("Stormwind", "Auberdine"), ("Auberdine", "Rut'theran Village"), ("Ratchet", "Auberdine"), ("Ironforge", "Menethil Harbor"),
                 ("Stormwind", "Darnassus"), ("Sentinel Hill", "Darnassus"), ("Ratchet", "Darnassus"), ("Stormwind", "Theramore"),
                 ("Sentinel Hill", "Ironforge"), ("Thelsamar", "Stormwind")]:
        print("A %-18s -> %-18s" % (a, b), t.pair("A", A[a], A[b]))
    H = {n["name"].split(",")[0]: i for i, n in t.hubs["H"].items()}
    for a, b in [("Orgrimmar", "Crossroads"), ("Crossroads", "Undercity"), ("Undercity", "Tarren Mill"), ("Orgrimmar", "Thunder Bluff")]:
        print("H %-18s -> %-18s" % (a, b), t.pair("H", H[a], H[b]))
    print("SW flight master check", t.world(1453, 66.3, 62.1), t.nodes[2]["x"], t.nodes[2]["y"])
