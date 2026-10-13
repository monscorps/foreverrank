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
  t.hub_extra("A"), t.flights_for("A"), t.links(), t.lands()   # the step-by-step arrow's data
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
DRUID_ONLY = {62, 63}       # Nighthaven: flights out only, for druids
TOWERS = {84, 85, 86, 87}   # the Eastern Plaguelands world-PvP towers: their flights hang on who holds them
# the rides the step-by-step arrow can take: (factions, kind b boat / z zeppelin / t tram / p portal, minutes of the
# ride with the average wait and no walking at the ends, source, town at end 1, town at end 2, map hint for the ends).
# A ("path", TaxiPath id) source has its two stops in TaxiPathNode (Flags 2); a ("trigger", id, id) source is the
# tram's doors or the portal in AreaTrigger. The Feathermoon ferry's 3 minutes is an estimate.
LINKS = [("A", "b", 6.0, ("path", 292), "Menethil Harbor", "Theramore", None),
         ("A", "b", 7.0, ("path", 295), "Menethil Harbor", "Auberdine", None),
         ("A", "b", 5.0, ("path", 293), "Rut'theran Village", "Auberdine", None),
         ("AH", "b", 6.0, ("path", 241), "Booty Bay", "Ratchet", None),
         ("AH", "b", 3.0, ("path", 303), "Feathermoon", "the Forgotten Coast", None),
         ("A", "t", 2.0, ("trigger", 2173, 2175), "Stormwind", "Ironforge", None),
         ("A", "p", 0.3, ("trigger", 542, 527), "Rut'theran Village", "Darnassus", None),
         ("H", "z", 6.5, ("path", 285), "Orgrimmar", "Grom'gol", 1411),
         ("H", "z", 6.5, ("path", 302), "Orgrimmar", "Undercity", 1411),
         ("H", "z", 6.5, ("path", 301), "Undercity", "Grom'gol", None)]
DOCK_NEAR = 600.0           # yards: a dock lies this close to a hub of its town
# Rut'theran Village at the foot of Teldrassil (land 4): its flight master, pier, the portal's lower end and Fishing
# Village, every spawn there at z 19-32 and x 8,636-8,808. The canopy above (z 1,250 and up) starts past x 9,070
RUTTHERAN = (1, 8400, 600, 8950, 1300, 4)
ISLE_PAD = 100              # yards round Sardor Isle's box: more than a boat's arrival (80) and its deck
RIDE_POINTS = 16            # points kept of a ride's track


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
        self.names = {int(r["ID"]): r["Name_lang"] for r in rows(build, "UiMap")}
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
            pts.setdefault(int(r["PathID"]), []).append((int(r["NodeIndex"]), float(r["Loc_0"]), float(r["Loc_1"]), int(r["ContinentID"]),
                                                         int(r["Flags"])))
        self.paths = {pid: sorted(p) for pid, p in pts.items()}
        self.flights = []
        for r in rows(build, "TaxiPath"):
            a, b, pid = int(r["FromTaxiNode"]), int(r["ToTaxiNode"]), int(r["ID"])
            if a not in nodes or b not in nodes:
                continue
            p = self.paths.get(pid, [])
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

    # --- the step-by-step arrow's data (gen_data.py: D.HUB fields 6-10, D.FLY, D.LINK, D.LAND) ---

    def hub_map(self, n):
        """A hub's map (uiMap, x, y): the map named for its town (Stormwind City), else the zone its TaxiNodes name
        gives (Ratchet, The Barrens: Ratchet also lies in Durotar's rectangle), else the map it lies in."""
        town, _, zone = n["name"].partition(", ")
        for name in (town, zone):
            named = tuple(mid for mid, nm in self.names.items() if name and nm.startswith(name))
            loc = named and self.locate(n["cont"], n["x"], n["y"], named)
            if loc and loc[0] in named:
                return loc
        return self.locate(n["cont"], n["x"], n["y"])

    def hub_extra(self, fac):
        """Per hub of order[fac]: (TaxiNodes id or 0, uiMap, map x, map y, flags). Flags: 1 no flight in or out among
        the faction's hubs (the second Alliance Booty Bay, Darnassus), 2 druids only, 4 a world-PvP tower."""
        ids = set(self.order[fac])
        flown = {h for a, b, _ in self.flights if a in ids and b in ids for h in (a, b)}
        out = []
        for h in self.order[fac]:
            m, x, y = self.hub_map(self.hubs[fac][h]) or (0, 0, 0)
            flags = (1 if h < 0 or h not in flown else 0) | (2 if h in DRUID_ONLY else 0) | (4 if h in TOWERS else 0)
            out.append((max(h, 0), m, x, y, flags))
        return out

    def flights_for(self, fac):
        """The flights between the faction's hubs, each way on its own: [(from, to, minutes)], 1-based in order[fac]."""
        at = {h: k + 1 for k, h in enumerate(self.order[fac])}
        assert len(at) < 64, "a hub index must fit one D.ALPHA character"
        return [(at[a], at[b], m) for a, b, m in self.flights if a in at and b in at]

    def town_yards(self, town, c, wx, wy):
        """Yards from a point to the nearest hub of that town (any faction), None when the town has no hub there."""
        ds = [math.hypot(n["x"] - wx, n["y"] - wy) for n in self.nodes.values() if n["town"] == town and n["cont"] == c]
        return min(ds) if ds else None

    def links(self):
        """LINKS with their ends placed: [(factions, kind, minutes, end 1, end 2, track)]. An end is (continent, world x,
        world y, uiMap, x, y, town). The track is the ride's whole loop, end 1 to end 2 and back (the way back runs up to
        1,250 yd from the way out), as at most RIDE_POINTS points (continent, world x, world y); the tram and the portal
        have none."""
        at = {int(r["ID"]): (int(r["ContinentID"]), float(r["Pos_0"]), float(r["Pos_1"])) for r in rows(self.build, "AreaTrigger")}
        same = lambda a, b: a[0] == b[0] and math.hypot(a[1] - b[1], a[2] - b[2]) < 30
        near = lambda town, e: self.town_yards(town, *e)
        miss = lambda yd: 1e9 if yd is None else yd
        out = []
        for fac, kind, minutes, src, town1, town2, hint in LINKS:
            track = []
            if src[0] == "trigger":
                ends = [at[src[1]], at[src[2]]]
            else:
                p = [(c, x, y) for _, x, y, c, _ in self.paths[src[1]]]
                stops = [k for k, r in enumerate(self.paths[src[1]]) if r[4] & 2]
                # a ride that turns back at the far end stops at its first pier twice (the Feathermoon ferry)
                ends = []
                for k in stops:
                    if not any(same(p[k], e) for e in ends):
                        ends.append(p[k])
                assert len(ends) == 2, "TaxiPath %d should stop at 2 places, not %d" % (src[1], len(ends))
            # end 1 lies at town1: the pair of ends that sits nearer the two towns' hubs
            if miss(near(town1, ends[1])) + miss(near(town2, ends[0])) < miss(near(town1, ends[0])) + miss(near(town2, ends[1])):
                ends.reverse()
            for town, e in zip((town1, town2), ends):
                yd = near(town, e)
                # a town with no hub (the Forgotten Coast) is checked against AreaTable by gen_data.py
                assert yd is None or yd < DOCK_NEAR, "the %s end of %s lies %d yd from its hub" % (town, src, yd)
            if src[0] == "path":
                first = next(k for k in stops if same(p[k], ends[0]))
                track = self.track(p[first:] + p[:first + 1], [(k - first) % len(p) for k in stops])
            placed = []
            for town, (c, wx, wy) in zip((town1, town2), ends):
                m, x, y = self.locate(c, wx, wy, (hint,) if hint else None)
                placed.append((c, round(wx), round(wy), m, x, y, town))
            pts = [(c, round(x), round(y)) for c, x, y in track]
            # the ferry's loop ends at the pier it also stops at on the way back
            out.append((fac, kind, minutes, placed[0], placed[1], [q for k, q in enumerate(pts) if not k or q != pts[k - 1]]))
        return out

    @staticmethod
    def track(p, keep):
        """At most RIDE_POINTS of the points p (continent, x, y), the ones the line bends at most: always the ends,
        the stops (indices in keep), and both sides of a change of continent or a jump (the Undercity zeppelin is
        moved across the Eastern Kingdoms out of sight)."""
        def off(q, a, b):
            if a[0] != q[0] or b[0] != q[0]:
                return 1e9
            dx, dy = b[1] - a[1], b[2] - a[2]
            t = max(0.0, min(1.0, ((q[1] - a[1]) * dx + (q[2] - a[2]) * dy) / (dx * dx + dy * dy))) if dx or dy else 0.0
            return math.hypot(q[1] - a[1] - t * dx, q[2] - a[2] - t * dy)
        kept = {0, len(p) - 1} | set(keep)
        for k in range(1, len(p)):
            if p[k][0] != p[k - 1][0] or math.hypot(p[k][1] - p[k - 1][1], p[k][2] - p[k - 1][2]) > 2000:
                kept |= {k - 1, k}
        while len(kept) < min(RIDE_POINTS, len(p)):
            line = sorted(kept)
            worst, k = max((min(off(p[k], p[a], p[b]) for a, b in zip(line, line[1:])), k) for k in range(len(p)) if k not in kept)
            if worst < 20:
                break
            kept.add(k)
        assert len(kept) <= RIDE_POINTS, "a ride's track keeps %d points" % len(kept)
        return [p[k] for k in sorted(kept)]

    def lands(self):
        """Islands on a continent you cannot walk to: [(continent, min x, min y, max x, max y, land)]; a point's land is
        the first box that holds it. Land 4 is Rut'theran Village at Teldrassil's foot (RUTTHERAN), 1,300 yd below the
        canopy: the portal is the only way up. Land 2 is the canopy with Darnassus, the rest of UiMap 1438's world
        rectangle. Land 3 is Sardor Isle with Feathermoon: the box its ferry sails round, leaving out the run to the
        Feralas coast's pier (400 yd round the flight master would leave out the Ruins of Solarsal), ISLE_PAD more each
        side, so the pier and a docked boat's deck lie well inside it. Outside every box a point's land is its
        continent's number."""
        m = self.maps[1438]
        fm = self.nodes[self._find("A", "Feathermoon")]
        p = self.paths[next(src[1] for _, _, _, src, town, _, _ in LINKS if town == "Feathermoon")]
        coast = max((r for r in p if r[4] & 2), key=lambda r: math.hypot(r[1] - fm["x"], r[2] - fm["y"]))
        isle = [r for r in p if math.hypot(r[1] - coast[1], r[2] - coast[2]) > DOCK_NEAR]
        return [RUTTHERAN,
                (1, math.floor(m["minx"]), math.floor(m["miny"]), math.ceil(m["maxx"]), math.ceil(m["maxy"]), 2),
                (1, math.floor(min(r[1] for r in isle)) - ISLE_PAD, math.floor(min(r[2] for r in isle)) - ISLE_PAD,
                 math.ceil(max(r[1] for r in isle)) + ISLE_PAD, math.ceil(max(r[2] for r in isle)) + ISLE_PAD, 3)]

    def land(self, c, wx, wy):
        for lc, x0, y0, x1, y1, n in self.lands():
            if lc == c and x0 <= wx <= x1 and y0 <= wy <= y1:
                return n
        return c


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
