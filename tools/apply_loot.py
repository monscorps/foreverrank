#!/usr/bin/env python3
"""Players' own loot records into codex/loot.json, next to the fansites': who dropped what, as QuestBank users'
loot windows showed it. The third source, labelled "players' games".

  python3 tools/apply_loot.py              # merge research/questbank/disc.json "loot" into codex/loot.json, report
  python3 tools/apply_loot.py --dry        # report only
  python3 tools/apply_loot.py --selftest   # the naming and the merge, in memory, no files touched

Run order: tools/scavenge_loot.py (the fansites) -> this -> tools/scavenge_items.py (the items' tooltips and the
absent check, which collects every id loot.json names). scavenge_loot.py calls merge() itself just before it writes,
so a refresh of the sites never drops what players added; run alone, this re-merges into the existing file and
fetches nothing.

QuestBank 3.6.2 notes, on the Forever client, which creature or chest each loot window came from: its id, the item
ids and how often, the instance map and difficulty, and the boss fight the kill ended (QuestBankDB.disc.loot; never
a name, the player's or the creature's). tools/probe_pull.py keeps the votes under "loot" in disc.json. The Forever
client has no Dungeon Journal and the addon stores no names, so this names the ids:
  - the dungeon from the client's Map table (research/wago/<newest build>/Map.csv) by the instance map id;
  - a boss from the client's DungeonEncounter table through the encounter id the record carries: the game's own
    creature list of the kill when it had one; else the first corpse looted within two minutes of the kill, a guess
    the addon marks as such (no ex), which counts only when two uploads made it and no game-made list named another
    creature for that fight, and is then marked games.link "time" (the site says "linked by time");
  - a Classic creature or chest from the CMaNGOS Classic database (research/cmangos, GPL-3.0: creature_template and
    gameobject_template; Classic ids stop at 18199, Forever's start far above, so an id names one or the other);
  - a Forever creature from the hand list tools/creature_names.json ({"c<id>": name} or {"<id>": name}), when there is one.
What stays unnamed is pooled into the dungeon's "Trash mobs" entry with its ids kept (npcs, objects), and listed in
the run's report with its items, GAPS-style; so are sources outdoors (recorded for later: codex/loot.json is dungeon
loot), on maps the client has but the fansites don't list (they become a new dungeon with players as its only
source), and on maps the fansites split into wings (Scarlet Monastery, Blackrock Spire, Dire Maul are one map each
in the client: only a boss whose name heads a wing's table can be placed).

Items: weapons, armor, recipes and quest items by the client's item class (Item.csv), and every item no table knows
(a Dalaran drop nobody has a tooltip for yet: the leads the report lists). Skinning leather and pickpocketed junk
show their creature as the source in game; the class filter keeps them out here. Nothing a fansite lists is ever
removed. What players add is marked so the next run can strip and redo it: "players' games" in the boss's and the
dungeon's src, the boss's games {kills, seen, npc, build, link} and gamesOnly (ids no site lists), the pooled entry's
ids. Two runs on the same inputs give the same file.
"""
import csv, gzip, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from scavenge_loot import dkey, norm  # noqa: E402  the fansite step's own name keys, so a boss lands on the same entry

LOOT = os.path.join(ROOT, "codex", "loot.json")
DISC = os.path.join(ROOT, "research", "questbank", "disc.json")
WAGO = os.path.join(ROOT, "research", "wago")
CMANGOS = os.path.join(ROOT, "research", "cmangos", "ClassicDB.sql.gz")
HAND = os.path.join(ROOT, "tools", "creature_names.json")
SIGHTINGS = os.path.join(ROOT, "tools", "item_sightings.json")
PG = "players' games"
# item classes kept: 2 weapon, 4 armor, 9 recipe, 12 quest; an id no table knows is kept too
KEEP_CLASS = {2, 4, 9, 12}
# the client's map name where the fansites say it otherwise (scavenge_loot's ALIAS does Sunken Temple; norm strips "the")
MAPNAME = {"stormwind stockade": "stockade"}
# one map in the client, several wings on the site: a boss is placed by the wing whose table names it
WINGS = {189: "scarlet monastery", 229: "blackrock spire", 429: "dire maul"}
FOREVER_MAP = 2000  # Forever-era maps start here (City of Dalaran is 2959): a dungeon no site lists yet is "new" from this id
# a boss link the addon made by time (the first corpse looted within two minutes of a kill that named no creature) is a
# guess: a trash mob looted first takes the boss's place. It names a source only once this many uploads made the same
# one (votes are per upload, so one player's file sent twice after more loot counts twice: a floor, not proof)
TIME_LINK_VOTES = 2
TIME_HOW = "encounter (time link)"
CLAUSE = (" and, since October 2026, what QuestBank users' own loot windows showed (players' games): creature and item ids"
          " only, named here through the client's encounter table and the Classic database.")
ANCHOR = "(each boss and quest lists its sites)."


# ----------------------------------------------------------------------------------------------- inputs
def latest_build():
    builds = [b for b in os.listdir(WAGO) if b.startswith("1.60.")
              and all(os.path.exists(os.path.join(WAGO, b, t + ".csv")) for t in ("DungeonEncounter", "Map", "Item"))]
    return max(builds, key=lambda b: [int(x) for x in b.split(".")]) if builds else None


def classic_names():
    """({creature entry: (name, rank)}, {chest entry: name}) from the CMaNGOS Classic database. Rank: 0 normal, 1 elite,
    2 rare elite, 3 world boss, 4 rare. Chests are gameobject_template type 3 (herb and ore nodes too: their items are
    trade goods and fall to the class filter)."""
    if not os.path.exists(CMANGOS):
        return {}, {}
    sys.path.insert(0, os.path.join(ROOT, "tools", "questbank"))
    from cmangos import rows_of
    want = ("creature_template", "gameobject_template")
    cols, table, creatures, chests = {}, None, {}, {}
    with gzip.open(CMANGOS, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("CREATE TABLE `"):
                table = line.split("`")[1]
                cols[table] = []
            elif table and line.startswith("  `"):
                cols[table].append(line.split("`")[1].lower())
            elif line.startswith("INSERT INTO `") and line.split("`")[1] in want:
                t = line.split("`")[1]
                idx = {c: k for k, c in enumerate(cols[t])}
                for r in rows_of(line[line.index("VALUES") + 6:].strip().rstrip(";")):
                    if t == "creature_template":
                        creatures[int(r[idx["entry"]])] = (r[idx["name"]], int(r[idx["rank"]] or 0))
                    elif int(r[idx["type"]] or 0) == 3:
                        chests[int(r[idx["entry"]])] = r[idx["name"]]
    return creatures, chests


def hand_names(path=HAND):
    """{disc key: name} from the hand list: keys "c<id>"/"o<id>" or a bare creature id; a "note" key is skipped."""
    if not os.path.exists(path):
        return {}
    out = {}
    for k, v in json.load(open(path, encoding="utf-8")).items():
        name = v.get("n") if isinstance(v, dict) else v
        if re.fullmatch(r"[co]?\d+", str(k)) and isinstance(name, str) and name.strip():
            out[k if k[0] in "co" else "c" + k] = name.strip()
    return out


def load_inputs():
    build = latest_build()
    if not build:
        sys.exit("no client tables: run tools/fetch_wago.py first (DungeonEncounter, Map and Item are needed)")
    rows = lambda t: csv.DictReader(open(os.path.join(WAGO, build, t + ".csv"), encoding="utf-8"))
    enc = {int(r["ID"]): (r["Name_lang"], int(r["MapID"] or 0)) for r in rows("DungeonEncounter")}
    maps = {int(r["ID"]): r["MapName_lang"] for r in rows("Map") if r.get("InstanceType") in ("1", "2")}
    cls = {int(r["ID"]): int(r["ClassID"] or 0) for r in rows("Item")}
    disc = json.load(open(DISC)) if os.path.exists(DISC) else {}
    # an item the client's table lacks may still have a class from a tooltip players' games showed, or a sighting
    for src in (((disc.get("probe") or {}).get("tips") or {}), json.load(open(SIGHTINGS)) if os.path.exists(SIGHTINGS) else {}):
        for k, v in src.items():
            if str(k).isdigit() and int(k) not in cls and isinstance(v, dict) and isinstance(v.get("c"), int):
                cls[int(k)] = v["c"]
    creatures, chests = classic_names()
    return {"loot": disc.get("loot") or {}, "uploads": (disc.get("meta") or {}).get("with_loot", 0), "enc": enc, "maps": maps,
            "cls": cls, "creatures": creatures, "chests": chests, "hand": hand_names(), "build": build}


# ----------------------------------------------------------------------------------------------- naming
def top(votes):
    """The most-voted value (ties: the lower number), or None."""
    if not votes:
        return None
    return int(sorted(votes.items(), key=lambda kv: (-kv[1], int(kv[0])))[0][0])


def time_linked(key, s, exact, rep):
    """The encounter a time link names this creature after, when the link holds; else None, with the reason in the
    report. It holds when TIME_LINK_VOTES uploads made it and no upload's game-made list named another creature for
    that fight (then the fight's boss is known and this corpse was something else)."""
    e = top(s.get("ei"))
    if not e:
        return None
    votes = (s.get("ei") or {}).get(str(e), 0)
    if e in exact:
        why = "the game's own list named creature %s for fight %d" % (", ".join(str(c) for c in sorted(exact[e])), e)
    elif votes < TIME_LINK_VOTES:
        why = "fight %d from %d upload%s, %d wanted" % (e, votes, "" if votes == 1 else "s", TIME_LINK_VOTES)
    else:
        return e
    if rep is not None:
        rep["time_link"].append("%s: %s" % (key, why))
    return None


def name_source(key, s, im, inp, exact=None, rep=None):
    """(name, kind, how) for one source, or (None, kind, "unnamed"). Order: the kill's encounter (the game's own list,
    else a time link that holds), the Classic database, the hand list. `exact` is {encounter: {creature ids}} as the
    game's own lists gave them over every source; `rep` takes the links set aside."""
    nid = int(key[1:])
    if key[0] == "o":
        if nid in inp["chests"]:
            return inp["chests"][nid], "object", "chest"
        if key in inp["hand"]:
            return inp["hand"][key], "object", "hand"
        return None, "object", "unnamed"
    e, how = top(s.get("e")), "encounter"
    if not e:
        e, how = time_linked(key, s, exact or {}, rep), TIME_HOW
    if e and e in inp["enc"]:
        name, emap = inp["enc"][e]
        if emap == im:
            return name, "boss", how
        if rep is not None:
            rep["dropped_link"].append("%s: encounter %d is on map %d, looted on %d" % (key, e, emap, im))
    if nid in inp["creatures"]:
        name, rank = inp["creatures"][nid]
        return name, "boss" if rank == 3 else "rare" if rank in (2, 4) else "trash", "classic"
    if key in inp["hand"]:
        v = inp["hand"][key]
        return v, "trash", "hand"
    return None, "trash", "unnamed"


def kept_items(s, cls):
    """[(item id, windows)] of a source, gear, weapons, recipes and quest items by the client's class, and ids no table
    knows; most seen first."""
    out = []
    for iid, it in (s.get("i") or {}).items():
        iid = int(iid)
        if (it.get("v") or 0) < 1:
            continue
        c = cls.get(iid)
        if c is None or c in KEEP_CLASS:
            out.append((iid, it.get("n") or 1, c is None))
    return sorted(out, key=lambda x: (-x[1], x[0]))


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


# ----------------------------------------------------------------------------------------------- the merge
def strip(doc):
    """Undo an earlier run: what players added goes, what the sites listed stays, so the merge starts from the sites."""
    for d in doc["dungeons"]:
        keep = []
        for b in d["bosses"]:
            gone = set(b.get("gamesOnly") or [])
            b["items"] = [i for i in b["items"] if i not in gone]
            b["src"] = [x for x in (b.get("src") or []) if x != PG]
            for k in ("games", "gamesOnly", "npcs", "objects"):
                b.pop(k, None)
            if b["src"]:
                keep.append(b)
        d["bosses"] = keep
        d["src"] = [x for x in (d.get("src") or []) if x != PG]
    doc["dungeons"] = [d for d in doc["dungeons"] if d["src"] or d["bosses"] or d.get("quests")]
    doc["note"] = re.sub(r"( and, since October 2026,| Since October 2026 the tables also hold)[^.]*\.",
                         lambda m: "." if m.group(1).startswith(" and") else "", doc.get("note") or "")


def with_clause(note):
    """The note saying where the third source comes from, in the sentence that names the first two."""
    if ANCHOR in note:
        return note.replace(ANCHOR, ANCHOR[:-1] + CLAUSE, 1)
    sentence = " Since October 2026 the tables also hold" + CLAUSE[len(" and, since October 2026,"):]
    i = note.find(" Items under absent")
    return note + sentence if i < 0 else note[:i] + sentence + note[i:]


def merge(doc, inp):
    """Players' loot sources into a loot.json document (in place). Returns the report: counts and the GAPS-style lists."""
    strip(doc)
    rep = {"sources": len(inp["loot"]), "uploads": inp.get("uploads", 0), "placed": 0, "items": 0, "leads": set(), "how": {},
           "new_dungeons": [], "unnamed": [], "outdoors": [], "no_place": [], "unknown_map": [], "wing": [], "no_item": [],
           "dropped_link": [], "time_link": []}
    by_key = {dkey(d["name"]): d for d in doc["dungeons"]}
    added = {}
    keys = sorted(k for k, s in inp["loot"].items() if isinstance(s, dict) and re.fullmatch(r"[co]\d+", k))
    # the fights the game's own creature lists settled, {encounter: {creature ids}}: a time link to one of them by another
    # creature is set aside (time_linked). Those sources go first, so a boss entry that a time link also lands on keeps
    # the game-named creature as its npc and no "time" mark
    exact = {}
    for k in keys:
        for e in (inp["loot"][k].get("e") or {}) if k[0] == "c" else ():
            exact.setdefault(int(e), set()).add(int(k[1:]))

    def settled(k):
        s = inp["loot"][k]
        e = top(s.get("e"))
        return 0 if e and e in inp["enc"] and inp["enc"][e][1] == top(s.get("im")) else 1

    keys.sort(key=lambda k: (settled(k), k[0], int(k[1:])))
    by_game = set()  # entries a game-made link placed (by id())

    def dungeon(im, mapname):
        k = dkey(mapname)
        k = MAPNAME.get(k, k)
        if k in by_key:
            return by_key[k]
        if k not in added:
            added[k] = {"name": mapname, "slug": slug(mapname), "levels": None, "new": im >= FOREVER_MAP, "bosses": [], "quests": [], "src": []}
            rep["new_dungeons"].append(mapname)
        return added[k]

    def entry(d, name, kind):
        for b in d["bosses"]:
            if norm(b["name"]) == norm(name):
                return b  # the sites' entry, its kind as they have it (Classic marks some dungeon bosses rare elite)
        b = {"name": name, "kind": kind, "level": None, "items": [], "src": []}
        d["bosses"].append(b)
        return b

    for key in keys:
        s = inp["loot"][key]
        nid = int(key[1:])
        im = top(s.get("im"))
        items = kept_items(s, inp["cls"])
        said = "%s: %d window(s), items %s" % (key, s.get("n") or 0, ", ".join(str(i) for i, _, _ in items) or "none kept")
        if not im:
            # outdoors (a uiMap), or no place at all: the client hid where, or the record was made in a battleground
            m = top(s.get("m"))
            rep["outdoors" if m else "no_place"].append(said + (" (map %d)" % m if m else ""))
            continue
        if not items:
            rep["no_item"].append(said)
            continue
        mapname = inp["maps"].get(im)
        if not mapname:
            rep["unknown_map"].append(said + " (instance map %d)" % im)
            continue
        name, kind, how = name_source(key, s, im, inp, exact, rep)
        if im in WINGS:
            wings = [d for d in doc["dungeons"] if dkey(d["name"]).startswith(WINGS[im])]
            d = next((w for w in wings if name and kind != "trash" and any(norm(b["name"]) == norm(name) for b in w["bosses"])), None)
            if not d:
                rep["wing"].append(said + " on %s%s" % (mapname, ", " + name if name else ""))
                continue
        else:
            d = dungeon(im, mapname)
        if name:
            b = entry(d, name, kind)
        else:
            b = entry(d, "Trash mobs", "trash")
            ids = b.setdefault("npcs" if key[0] == "c" else "objects", [])
            if nid not in ids:
                ids.append(nid)
            rep["unnamed"].append(said + " in " + d["name"])
        new = [i for i, _, _ in items if i not in b["items"]]
        b["items"] += new
        b["gamesOnly"] = sorted(set(b.get("gamesOnly") or []) | set(new))
        for lst in (b["src"], d["src"]):
            if PG not in lst:
                lst.append(PG)
        g = b.setdefault("games", {"kills": 0, "seen": {}, "build": 0})
        n = s.get("n") or 0
        g["kills"] = g["kills"] + n if not name else max(g["kills"], n)  # a pooled entry adds its creatures up; a boss and its adds are one kill
        g["build"] = max(g["build"], s.get("b") or 0)
        for i, seen, lead in items:
            g["seen"][str(i)] = max(g["seen"].get(str(i), 0), seen)
            if lead:
                rep["leads"].add(i)
        if name:
            if "npc" not in g:
                g["npc"] = nid
            elif g["npc"] != nid:
                g["npcs"] = sorted(set(g.get("npcs") or [g["npc"]]) | {nid})
        if how == "encounter":
            by_game.add(id(b))
        elif how == TIME_HOW and id(b) not in by_game:
            g["link"] = "time"  # the boss's name is a guess from the kill's timing; npc is what was looted, a fact
        rep["placed"] += 1
        rep["items"] += len(new)
        rep["how"][how] = rep["how"].get(how, 0) + 1
    doc["dungeons"] += [added[k] for k in sorted(added)]
    doc["note"] = with_clause(doc["note"])
    rep["leads"] = sorted(rep["leads"])
    return rep


def report(rep, build=None):
    how = ", ".join("%d by %s" % (n, k) for k, n in sorted(rep["how"].items(), key=lambda kv: -kv[1]))
    print("players' games: %d loot source(s) from %d upload(s); %d placed in codex/loot.json (%s), %d item(s) added%s" % (
        rep["sources"], rep["uploads"], rep["placed"], how or "none", rep["items"],
        "; client tables " + build if build else ""))
    if rep["leads"]:
        print("  leads, items no table knows (a tooltip is wanted): %s" % ", ".join(str(i) for i in rep["leads"]))
    if rep["new_dungeons"]:
        print("  dungeons no site lists yet, added with players as the only source: %s" % ", ".join(rep["new_dungeons"]))
    for key, label in (("unnamed", "unnamed, pooled as Trash mobs (name them in tools/creature_names.json)"),
                       ("time_link", "boss link by time set aside, named some other way (it takes %d uploads and no game-made list naming another creature)" % TIME_LINK_VOTES),
                       ("wing", "on a map the sites split into wings, not placed"), ("unknown_map", "on a map the client's table lacks"),
                       ("dropped_link", "encounter link dropped, another map's"), ("no_item", "no weapon, armor, recipe or quest item, left out"),
                       ("outdoors", "outdoors, kept for later"), ("no_place", "no place (the client hid where), kept for later")):
        if rep[key]:
            print("  %s:" % label)
            for line in rep[key]:
                print("    " + line)


# ----------------------------------------------------------------------------------------------- selftest
def selftest():
    inp = {
        "loot": {
            "c246020": {"u": 2, "n": 2, "b": 70291, "m": {}, "im": {"2959": 2}, "d": {"1": 2}, "e": {"3303": 2}, "ei": {},
                        "i": {"273031": {"v": 2, "n": 2}, "273032": {"v": 1, "n": 1}, "2589": {"v": 1, "n": 1}}, "last": 2},
            "c197": {"u": 1, "n": 1, "b": 70291, "m": {"1429": 1}, "im": {}, "d": {}, "e": {}, "ei": {}, "i": {"2589": {"v": 1, "n": 1}}, "last": 1},
            "c1234": {"u": 1, "n": 3, "b": 70291, "m": {}, "im": {"2959": 1}, "d": {"1": 1}, "e": {}, "ei": {}, "i": {"273040": {"v": 1, "n": 1}}, "last": 1},
            "c1235": {"u": 1, "n": 1, "b": 70291, "m": {}, "im": {"2959": 1}, "d": {}, "e": {}, "ei": {}, "i": {"273040": {"v": 1, "n": 1}}, "last": 1},
            "c1236": {"u": 1, "n": 5, "b": 70291, "m": {}, "im": {"2959": 1}, "d": {}, "e": {}, "ei": {}, "i": {"5440": {"v": 1, "n": 5}}, "last": 1},
            "o2843": {"u": 1, "n": 2, "b": 70291, "m": {}, "im": {"36": 1}, "d": {"1": 1}, "e": {}, "ei": {}, "i": {"5440": {"v": 1, "n": 2}}, "last": 1},
            "c644": {"u": 2, "n": 4, "b": 70291, "m": {}, "im": {"36": 2}, "d": {}, "e": {}, "ei": {"2741": 2}, "i": {"5443": {"v": 2, "n": 1}}, "last": 2},
            "c3586": {"u": 1, "n": 1, "b": 70291, "m": {}, "im": {"36": 1}, "d": {}, "e": {}, "ei": {}, "i": {"5444": {"v": 1, "n": 1}}, "last": 1},
            "c3975": {"u": 1, "n": 1, "b": 70291, "m": {}, "im": {"189": 1}, "d": {}, "e": {"448": 1}, "ei": {}, "i": {"7719": {"v": 1, "n": 1}}, "last": 1},
            "c4000": {"u": 1, "n": 1, "b": 70291, "m": {}, "im": {"189": 1}, "d": {}, "e": {}, "ei": {}, "i": {"7720": {"v": 1, "n": 1}}, "last": 1},
            "c5000": {"u": 1, "n": 1, "b": 70291, "m": {}, "im": {"3109": 1}, "d": {}, "e": {"3900": 1}, "ei": {}, "i": {"280001": {"v": 1, "n": 1}}, "last": 1},
            "c5001": {"u": 1, "n": 1, "b": 70291, "m": {}, "im": {"2959": 1}, "d": {}, "e": {"448": 1}, "ei": {}, "i": {"273041": {"v": 1, "n": 1}}, "last": 1},
            "c5002": {"u": 1, "n": 1, "b": 70291, "m": {}, "im": {"7777": 1}, "d": {}, "e": {}, "ei": {}, "i": {"273042": {"v": 1, "n": 1}}, "last": 1},
            # a time link from one upload (a trash corpse looted first after Atrexis fell, as far as anyone knows)
            "c246030": {"u": 1, "n": 1, "b": 70291, "m": {}, "im": {"2959": 1}, "d": {"1": 1}, "e": {}, "ei": {"3311": 1}, "i": {"273045": {"v": 1, "n": 1}}, "last": 1},
            # a time link from two uploads to the Shade's fight, whose creature the game's own list named (246020)
            "c246031": {"u": 2, "n": 1, "b": 70291, "m": {}, "im": {"2959": 2}, "d": {"1": 2}, "e": {}, "ei": {"3303": 2}, "i": {"273046": {"v": 2, "n": 1}}, "last": 2},
            # no place at all: the client hid it, or a battleground
            "c9": {"u": 1, "n": 1, "b": 70291, "m": {}, "im": {}, "d": {}, "e": {}, "ei": {}, "i": {"5447": {"v": 1, "n": 1}}, "last": 1},
        },
        "uploads": 2,
        "enc": {3303: ("Shade of the Archmage", 2959), 3311: ("Atrexis the Grave Knight", 2959), 2741: ("Rhahk'Zor", 36), 448: ("Herod", 189),
                3900: ("Lord Mistmantle", 3109)},
        "maps": {2959: "City of Dalaran", 36: "Deadmines", 189: "Scarlet Monastery", 3109: "Manor Mistmantle", 34: "Stormwind Stockade"},
        "cls": {273031: 4, 273032: 2, 2589: 7, 5440: 12, 5443: 4, 5444: 4, 7719: 4, 7720: 4, 280001: 4, 273041: 4, 273042: 4, 273045: 4,
                273046: 2, 5447: 4},
        "creatures": {644: ("Rhahk'Zor", 1), 3586: ("Miner Johnson", 2), 3975: ("Herod", 1), 4000: ("Scarlet Gallant", 1), 197: ("Marshal McBride", 0)},
        "chests": {2843: "Defias Cannon"},
        "hand": {"c1236": "Mana Wraith"},
    }
    doc = {"note": "Who drops what in WoW: Forever. The client has no Dungeon Journal, so these are players' loot records as published "
                   "by foreverchanges.pro and wowtbc.gg (each boss and quest lists its sites). Beta data. Items under absent are in a site's loot table.",
           "generated": "2026-10-09",
           "dungeons": [
               {"name": "City of Dalaran", "slug": "city-of-dalaran", "levels": [28, 33], "new": True, "src": ["foreverchanges.pro", "wowtbc.gg"],
                "bosses": [{"name": "Shade of the Archmage", "kind": "boss", "level": None, "items": [], "src": ["wowtbc.gg"]}],
                "quests": [{"name": "The Grave Knight", "level": 33, "items": [251963], "src": ["wowtbc.gg"]}]},
               {"name": "The Deadmines", "slug": "the-deadmines", "levels": [17, 24], "new": False, "src": ["foreverchanges.pro", "wowtbc.gg"],
                "bosses": [{"name": "Rhahk'Zor", "kind": "boss", "level": 19, "items": [5443, 5187], "src": ["foreverchanges.pro", "wowtbc.gg"]},
                           {"name": "Miner Johnson", "kind": "rare", "level": None, "items": [5444], "src": ["foreverchanges.pro"]},
                           {"name": "Trash mobs", "kind": "trash", "level": None, "items": [1000], "src": ["foreverchanges.pro"]}],
                "quests": []},
               {"name": "Scarlet Monastery: Graveyard", "slug": "scarlet-monastery-graveyard", "levels": [26, 36], "new": False, "src": ["wowtbc.gg"],
                "bosses": [{"name": "Interrogator Vishas", "kind": "boss", "level": None, "items": [7683], "src": ["wowtbc.gg"]}], "quests": []},
               {"name": "Scarlet Monastery: Armory", "slug": "scarlet-monastery-armory", "levels": [26, 36], "new": False, "src": ["wowtbc.gg"],
                "bosses": [{"name": "Herod", "kind": "boss", "level": None, "items": [7718], "src": ["wowtbc.gg"]}], "quests": []},
           ], "absent": {}}
    before = json.dumps(doc, sort_keys=True)
    rep = merge(doc, inp)
    dal = doc["dungeons"][0]
    shade = dal["bosses"][0]
    # the Shade, named by the encounter the game's own list gave: its two items (the leather, class 7, is skinning loot
    # and stays out), the third source on it and on the dungeon, the kills and the items as players' games showed them
    assert shade["items"] == [273031, 273032] and shade["gamesOnly"] == [273031, 273032], shade
    assert shade["src"] == ["wowtbc.gg", PG] and dal["src"] == ["foreverchanges.pro", "wowtbc.gg", PG], (shade["src"], dal["src"])
    assert shade["games"] == {"kills": 2, "seen": {"273031": 2, "273032": 1}, "build": 70291, "npc": 246020}, shade["games"]
    assert shade["kind"] == "boss" and shade["level"] is None
    # the unnamed Dalaran creatures pool into Trash mobs with their ids, their kills added up; the hand-named one is its own
    # entry. c5001's encounter is on another map, so that link is dropped and it pools as unnamed too; so do the two time
    # links that do not hold: c246030's came from one upload (two wanted), c246031's names a fight whose creature the
    # game's own list settled as 246020. Neither is placed under a boss, and the pool carries no "time" mark
    trash = next(b for b in dal["bosses"] if b["name"] == "Trash mobs")
    assert trash["kind"] == "trash" and trash["npcs"] == [1234, 1235, 5001, 246030, 246031] and trash["src"] == [PG], trash
    assert trash["items"] == [273040, 273041, 273045, 273046] and trash["gamesOnly"] == [273040, 273041, 273045, 273046], trash
    assert trash["games"] == {"kills": 7, "seen": {"273040": 1, "273041": 1, "273045": 1, "273046": 1}, "build": 70291}, trash["games"]
    assert len(rep["dropped_link"]) == 1 and rep["dropped_link"][0].startswith("c5001: encounter 448 is on map 189"), rep["dropped_link"]
    assert len(rep["time_link"]) == 2 and rep["time_link"][0] == "c246030: fight 3311 from 1 upload, 2 wanted", rep["time_link"]
    assert rep["time_link"][1] == "c246031: the game's own list named creature 246020 for fight 3303", rep["time_link"]
    assert not any(b["name"] == "Atrexis the Grave Knight" for b in dal["bosses"]), "a one-upload time link names no boss"
    wraith = next(b for b in dal["bosses"] if b["name"] == "Mana Wraith")
    assert wraith["kind"] == "trash" and wraith["items"] == [5440] and wraith["games"]["npc"] == 1236
    assert rep["leads"] == [273040], rep["leads"]
    # The Deadmines: the chest is a new object entry; Rhahk'Zor, linked by time from two uploads, is marked so (link "time",
    # the looted id kept as npc) and gains nothing new (5443 was listed), keeping the sites' two; Miner Johnson (Classic
    # rank 2) stays the sites' rare and gains nothing new (5444 was listed)
    dm = doc["dungeons"][1]
    chest = next(b for b in dm["bosses"] if b["name"] == "Defias Cannon")
    assert chest["kind"] == "object" and chest["items"] == [5440] and chest["src"] == [PG] and chest["games"]["npc"] == 2843, chest
    rz = dm["bosses"][0]
    assert rz["items"] == [5443, 5187] and rz["gamesOnly"] == [] and rz["src"] == ["foreverchanges.pro", "wowtbc.gg", PG], rz
    assert rz["games"] == {"kills": 4, "seen": {"5443": 1}, "build": 70291, "npc": 644, "link": "time"}, rz["games"]
    mj = dm["bosses"][1]
    assert mj["kind"] == "rare" and mj["items"] == [5444] and PG in mj["src"], mj
    assert dm["bosses"][2]["items"] == [1000] and "games" not in dm["bosses"][2], "the sites' Trash mobs entry is untouched"
    # Scarlet Monastery is one map: Herod is placed in the wing that names him, a trash creature is only reported
    arm = doc["dungeons"][3]
    assert arm["bosses"][0]["items"] == [7718, 7719] and PG in arm["src"] and PG not in doc["dungeons"][2]["src"], arm
    assert len(rep["wing"]) == 1 and rep["wing"][0].startswith("c4000"), rep["wing"]
    # a map no site lists becomes a new dungeon with players as its only source; an unknown map and the outdoors are reported
    manor = doc["dungeons"][-1]
    assert manor["name"] == "Manor Mistmantle" and manor["new"] is True and manor["levels"] is None and manor["src"] == [PG], manor
    assert manor["bosses"][0]["name"] == "Lord Mistmantle" and manor["bosses"][0]["kind"] == "boss" and manor["slug"] == "manor-mistmantle"
    assert rep["new_dungeons"] == ["Manor Mistmantle"] and len(rep["unknown_map"]) == 1 and rep["unknown_map"][0].startswith("c5002")
    assert len(rep["outdoors"]) == 1 and rep["outdoors"][0].startswith("c197") and "1429" in rep["outdoors"][0]
    assert len(rep["no_place"]) == 1 and rep["no_place"][0].startswith("c9:") and "map" not in rep["no_place"][0], rep["no_place"]
    assert rep["placed"] == 12 and rep["items"] == 10 and rep["sources"] == 16, (rep["placed"], rep["items"], rep["sources"])
    assert rep["how"] == {"encounter": 3, TIME_HOW: 1, "classic": 1, "hand": 1, "unnamed": 5, "chest": 1}, rep["how"]
    assert "link" not in shade["games"] and "link" not in wraith["games"] and "link" not in chest["games"], "only a time link is marked"
    assert CLAUSE in doc["note"] and doc["note"].count("October 2026") == 1 and doc["note"].endswith("Items under absent are in a site's loot table."), doc["note"]
    assert all(q["src"] == ["wowtbc.gg"] for q in dal["quests"]), "quests are the sites' alone"
    # the same again is the same file; stripped, it is the sites' file again
    once = json.dumps(doc, sort_keys=True)
    rep2 = merge(doc, inp)
    assert json.dumps(doc, sort_keys=True) == once and rep2["placed"] == rep["placed"], "two runs, one result"
    strip(doc)
    assert json.dumps(doc, sort_keys=True) == before, "strip() gives the sites' file back"
    # with no record at all the file is the sites' plus the note's clause; a note already carrying it keeps one copy
    empty = {"loot": {}, "uploads": 0, "enc": {}, "maps": {}, "cls": {}, "creatures": {}, "chests": {}, "hand": {}}
    rep3 = merge(doc, empty)
    assert rep3["placed"] == 0 and json.dumps(dict(doc, note=""), sort_keys=True) == json.dumps(dict(json.loads(before), note=""), sort_keys=True)
    merge(doc, empty)
    assert doc["note"].count("October 2026") == 1
    odd = {"note": "A note of its own. Items under absent are listed.", "dungeons": [], "absent": {}}
    merge(odd, empty)
    assert odd["note"] == "A note of its own. Since October 2026 the tables also hold what QuestBank users' own loot windows showed (players' games): " \
                          "creature and item ids only, named here through the client's encounter table and the Classic database. Items under absent are listed.", odd["note"]
    merge(odd, empty)
    assert odd["note"].count("October 2026") == 1
    # the hand list reads keys of both shapes and skips its note
    tmp = os.path.join(HERE, ".creature_names.selftest.json")
    json.dump({"note": "x", "246021": "Arcane Guardian", "c246022": {"n": "Fel Watcher"}, "o5": "Mana Cache", "bad": "y"}, open(tmp, "w"))
    try:
        assert hand_names(tmp) == {"c246021": "Arcane Guardian", "c246022": "Fel Watcher", "o5": "Mana Cache"}, hand_names(tmp)
    finally:
        os.remove(tmp)
    print("selftest OK")


def main():
    if "--selftest" in sys.argv:
        return selftest()
    inp = load_inputs()
    doc = json.load(open(LOOT, encoding="utf-8"))
    was = json.dumps(doc, ensure_ascii=False, separators=(",", ":"))
    rep = merge(doc, inp)
    report(rep, inp.get("build"))
    out = json.dumps(doc, ensure_ascii=False, separators=(",", ":"))
    if "--dry" in sys.argv:
        print("(dry run) codex/loot.json %s" % ("would change" if out != was else "is unchanged"))
        return
    if out != was:
        with open(LOOT, "w", encoding="utf-8") as f:
            f.write(out)
    print("%s codex/loot.json: %d dungeons, %d bosses, %d with players' games" % (
        "wrote" if out != was else "unchanged", len(doc["dungeons"]), sum(len(d["bosses"]) for d in doc["dungeons"]),
        sum(1 for d in doc["dungeons"] for b in d["bosses"] if PG in b["src"])))


if __name__ == "__main__":
    main()
