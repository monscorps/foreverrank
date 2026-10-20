"""Extract quest chains, quest givers, spawn points, item starts, innkeepers and starting spots from the
CMaNGOS Classic database (github.com/cmangos/classic-db, GPL-3.0) for QuestBank.

Wowhead Forever lacks many prerequisites (Morganth needs Looking Further, and starts from the Old
Lion Statue). The Classic server database has them all: PrevQuestId, NextQuestId, ExclusiveGroup,
RequiredRaces, who starts and ends each quest, where every creature and object stands, and which
items start quests. gen_data.py prefers Wowhead Forever wherever Forever changed something.

  python3 tools/questbank/cmangos.py     # research/cmangos/ClassicDB.sql.gz -> research/questbank/cmangos.json
  python3 tools/questbank/cmangos.py --sellers  # only the sellers of Simple Wood and Flint and Tinder, into it

objectives.py reads the same dump through read() and spawn_points() for the objective areas and map icons.
"""
import gzip, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(REPO, "research", "cmangos", "ClassicDB.sql.gz")
OUT = os.path.join(REPO, "research", "questbank", "cmangos.json")

WANT = {"quest_template", "creature_questrelation", "creature_involvedrelation", "gameobject_questrelation",
        "gameobject_involvedrelation", "creature", "gameobject", "creature_template", "gameobject_template", "item_template",
        # for objectives.py: spawns that stand for one of several entries, spawns and quests that only come with a
        # game event, and the quests' own POI outlines
        "creature_spawn_entry", "gameobject_spawn_entry", "game_event_creature", "game_event_gameobject",
        "game_event_quest", "quest_poi", "quest_poi_points",
        # for gen_data.py's D.BIND: where each race starts, which is where a new character's hearthstone is bound
        "playercreateinfo",
        # for gen_data.py's D.CAMP_SELL: who sells Simple Wood and Flint and Tinder (sellers())
        "npc_vendor", "npc_vendor_template"}
# the camp bar's goods a general goods vendor sells: Simple Wood and Flint and Tinder, what Cooking's Basic Campfire Kit
# (1229737) is made from and with
CAMP_GOODS = (4470, 4471)
FIELD = re.compile(r"'((?:[^'\\]|\\.)*)'|(NULL)|(-?[\d.eE+-]+)")


def rows_of(values):
    """The tuples of one INSERT ... VALUES line."""
    i, n = 0, len(values)
    while i < n:
        if values[i] != "(":
            i += 1
            continue
        i += 1
        row = []
        while True:
            m = FIELD.match(values, i)
            if not m:
                raise ValueError("bad value at %d: %r" % (i, values[i:i + 40]))
            s, null, num = m.groups()
            if s is not None:
                row.append(s.replace("\\'", "'").replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\"))
            elif null:
                row.append(None)
            else:
                row.append(float(num) if ("." in num or "e" in num.lower()) else int(num))
            i = m.end()
            if values[i] == ",":
                i += 1
                continue
            if values[i] == ")":
                i += 1
                break
            raise ValueError("unexpected %r at %d" % (values[i], i))
        yield row


def read(want=WANT):
    cols, data, table = {}, {t: [] for t in want}, None
    with gzip.open(SRC, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("CREATE TABLE `"):
                table = line.split("`")[1]
                cols[table] = []
                continue
            if table and line.startswith("  `"):
                cols[table].append(line.split("`")[1])
                continue
            if line.startswith("INSERT INTO `"):
                t = line.split("`")[1]
                if t in want:
                    body = line[line.index("VALUES") + 6:].strip().rstrip(";")
                    idx = {c.lower(): k for k, c in enumerate(cols[t])}
                    for r in rows_of(body):
                        data[t].append((idx, r))
    return data


def spawn_points(data, kind, maps=(0, 1), event=False):
    """Where every creature (kind "npc") or object spawns on the given maps (None: every map, instances too):
    {entry: [(map, x, y), ...]}. A spawn row whose id is 0 stands for one of several entries
    (creature_spawn_entry / gameobject_spawn_entry), so it counts for each of them. A spawn that only comes with
    a game event (game_event_creature / game_event_gameobject, event above 0: the Darkmoon Faire, the elemental
    invasions, the holidays) is left out, or with event=True is all that is given."""
    table = "creature" if kind == "npc" else "gameobject"
    entries = {}
    for idx, r in data[table + "_spawn_entry"]:
        entries.setdefault(r[idx["guid"]], []).append(r[idx["entry"]])
    seasonal = {r[idx["guid"]] for idx, r in data["game_event_" + table] if (r[idx["event"]] or 0) > 0}
    out = {}
    for idx, r in data[table]:
        if (maps is not None and r[idx["map"]] not in maps) or (r[idx["guid"]] in seasonal) != event:
            continue
        for i in [r[idx["id"]]] if r[idx["id"]] else entries.get(r[idx["guid"]], []):
            out.setdefault(i, []).append((r[idx["map"]], r[idx["position_x"]], r[idx["position_y"]]))
    return out


def sellers(data):
    """Every creature that sells Simple Wood or Flint and Tinder (npc_vendor, or the npc_vendor_template its
    VendorTemplateId names): [entry, name, subname, faction template, [the goods it sells], [[map, x, y], ...] on the
    two continents], and the flight masters' faction templates with where they stand (NpcFlags 8), which gen_data.py
    matches to the client's flight points to tell whose side a template is on."""
    goods = {}
    for idx, r in data["npc_vendor"]:
        if r[idx["item"]] in CAMP_GOODS:
            goods.setdefault(r[idx["entry"]], set()).add(r[idx["item"]])
    tmpl = {}
    for idx, r in data["npc_vendor_template"]:
        if r[idx["item"]] in CAMP_GOODS:
            tmpl.setdefault(r[idx["entry"]], set()).add(r[idx["item"]])
    stands = spawn_points(data, "npc")
    out, masters = [], []
    for idx, r in data["creature_template"]:
        e = r[idx["entry"]]
        have = set(goods.get(e, ())) | set(tmpl.get(r[idx["vendortemplateid"]], ()) if r[idx["vendortemplateid"]] else ())
        spots = [[m, round(x, 1), round(y, 1)] for m, x, y in stands.get(e, ()) if m in (0, 1)]
        if have and spots:
            out.append([e, r[idx["name"]], r[idx["subname"]], r[idx["faction"]], sorted(have), spots])
        if (r[idx["npcflags"]] or 0) & 8 and spots:
            masters.append([e, r[idx["faction"]], spots])
    return {"vendors": sorted(out), "masters": sorted(masters)}


def main():
    if "--sellers" in sys.argv:
        # only the sellers, into the cmangos.json there is (the rest of it as it was)
        data = read({"npc_vendor", "npc_vendor_template", "creature_template", "creature", "creature_spawn_entry", "game_event_creature"})
        out = json.load(open(OUT))
        out["sellers"] = sellers(data)
        json.dump(out, open(OUT, "w"), separators=(",", ":"))
        print("wrote %s: %d sellers of Simple Wood or Flint and Tinder, %d flight masters" % (OUT, len(out["sellers"]["vendors"]), len(out["sellers"]["masters"])))
        return
    data = read()
    quests = {}
    for idx, r in data["quest_template"]:
        g = lambda c: r[idx[c.lower()]]
        reqs = sum(1 for k in range(1, 5) if g("ReqItemCount%d" % k) or g("ReqCreatureOrGOCount%d" % k) or g("ReqSpellCast%d" % k))
        quests[g("entry")] = {
            "title": g("Title"), "min": g("MinLevel"), "level": g("QuestLevel"), "zone": g("ZoneOrSort"), "type": g("Type"),
            "classes": g("RequiredClasses"), "races": g("RequiredRaces"), "prev": g("PrevQuestId"), "next": g("NextQuestId"),
            "excl": g("ExclusiveGroup"), "breadcrumb": g("BreadcrumbForQuestId"), "chain": g("NextQuestInChain"),
            "src": g("SrcItemId"), "flags": g("QuestFlags"), "special": g("SpecialFlags"), "objectives": reqs,
            "rep": g("RepObjectiveFaction"), "text": (g("Objectives") or "")[:200], "starts": [], "ends": [],
            "moneymax": g("RewMoneyMaxLevel"), "sort": g("ZoneOrSort"),
            "items": [[g("ReqItemId%d" % k), g("ReqItemCount%d" % k)] for k in range(1, 5) if g("ReqItemId%d" % k) and g("ReqItemCount%d" % k)],
        }
    for key, table, kind in (("starts", "creature_questrelation", "npc"), ("ends", "creature_involvedrelation", "npc"),
                             ("starts", "gameobject_questrelation", "object"), ("ends", "gameobject_involvedrelation", "object")):
        for idx, r in data[table]:
            q = quests.get(r[idx["quest"]])
            if q:
                q[key].append([kind, r[idx["id"]]])
    items, itemnames = {}, {}
    needed = {i for q in quests.values() for i, _ in q["items"]}
    for idx, r in data["item_template"]:
        sq = r[idx["startquest"]]
        if sq:
            items[r[idx["entry"]]] = {"name": r[idx["name"]], "quest": sq}
            if sq in quests:
                quests[sq]["starts"].append(["item", r[idx["entry"]]])
        if r[idx["entry"]] in needed:
            itemnames[r[idx["entry"]]] = r[idx["name"]]
    names = {"npc": {}, "object": {}}
    questgivers = set()
    for idx, r in data["creature_template"]:
        names["npc"][r[idx["entry"]]] = r[idx["name"]]
        if "npcflags" in idx and (r[idx["npcflags"]] or 0) & 2:
            questgivers.add(r[idx["entry"]])
    for idx, r in data["gameobject_template"]:
        names["object"][r[idx["entry"]]] = r[idx["name"]]
    # spawn points of every quest giver and ender, on the two continents
    wanted = {"npc": set(questgivers), "object": set()}
    for q in quests.values():
        for kind, i in q["starts"] + q["ends"]:
            if kind in wanted:
                wanted[kind].add(i)
    spawns = {"npc": {}, "object": {}}
    for kind, table in (("npc", "creature"), ("object", "gameobject")):
        for idx, r in data[table]:
            i = r[idx["id"]]
            if i in wanted[kind] and r[idx["map"]] in (0, 1):
                spawns[kind].setdefault(i, []).append([r[idx["map"]], round(r[idx["position_x"]], 1), round(r[idx["position_y"]], 1)])
    # where a hearthstone can land: every innkeeper (NpcFlags 128, SubName Innkeeper: eight mount sellers and Bashana
    # Runetotem carry the flag too, away from the inns of Darnassus and Thunder Bluff) that stands at one place on the
    # two continents, and each race's starting spot (one row per class, all at the same place)
    stands = spawn_points(data, "npc")
    innkeepers = []
    for idx, r in data["creature_template"]:
        e = r[idx["entry"]]
        if (r[idx["npcflags"]] or 0) & 128 and r[idx["subname"]] == "Innkeeper" and len(stands.get(e, ())) == 1:
            m, x, y = stands[e][0]
            innkeepers.append([e, r[idx["name"]], m, round(x, 1), round(y, 1)])
    starts = {}
    for idx, r in data["playercreateinfo"]:
        starts.setdefault(r[idx["race"]], [r[idx["race"]], r[idx["map"]], round(r[idx["position_x"]], 1), round(r[idx["position_y"]], 1)])
    out = {"quests": quests, "items": items, "itemnames": itemnames,
           "names": {k: {i: names[k].get(i) for i in wanted[k]} for k in names},
           "spawns": spawns, "innkeepers": sorted(innkeepers), "starts": [starts[k] for k in sorted(starts)], "sellers": sellers(data)}
    json.dump(out, open(OUT, "w"), separators=(",", ":"))
    print("wrote %s: %d quests, %d item starts, %d NPC and %d object spawn sets, %d innkeepers, %d starting spots" % (
        OUT, len(quests), len(items), len(spawns["npc"]), len(spawns["object"]), len(innkeepers), len(starts)))
    for qid in (249, 248, 94, 19, 219, 166, 155, 1200):
        q = quests.get(qid)
        print(qid, q and {k: q[k] for k in ("title", "min", "level", "prev", "next", "excl", "chain", "objectives", "starts", "ends")})


if __name__ == "__main__":
    main()
