"""Extract quest chains, quest givers, spawn points and item starts from the CMaNGOS Classic
database (github.com/cmangos/classic-db, GPL-3.0) for QuestBank.

Wowhead Forever lacks many prerequisites (Morganth needs Looking Further, and starts from the Old
Lion Statue). The Classic server database has them all: PrevQuestId, NextQuestId, ExclusiveGroup,
RequiredRaces, who starts and ends each quest, where every creature and object stands, and which
items start quests. gen_data.py prefers Wowhead Forever wherever Forever changed something.

  python3 tools/questbank/cmangos.py     # research/cmangos/ClassicDB.sql.gz -> research/questbank/cmangos.json
"""
import gzip, json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(REPO, "research", "cmangos", "ClassicDB.sql.gz")
OUT = os.path.join(REPO, "research", "questbank", "cmangos.json")

WANT = {"quest_template", "creature_questrelation", "creature_involvedrelation", "gameobject_questrelation",
        "gameobject_involvedrelation", "creature", "gameobject", "creature_template", "gameobject_template", "item_template"}
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


def read():
    cols, data, table = {}, {t: [] for t in WANT}, None
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
                if t in WANT:
                    body = line[line.index("VALUES") + 6:].strip().rstrip(";")
                    idx = {c.lower(): k for k, c in enumerate(cols[t])}
                    for r in rows_of(body):
                        data[t].append((idx, r))
    return data


def main():
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
    out = {"quests": quests, "items": items, "itemnames": itemnames,
           "names": {k: {i: names[k].get(i) for i in wanted[k]} for k in names},
           "spawns": spawns}
    json.dump(out, open(OUT, "w"), separators=(",", ":"))
    print("wrote %s: %d quests, %d item starts, %d NPC and %d object spawn sets" % (
        OUT, len(quests), len(items), len(spawns["npc"]), len(spawns["object"])))
    for qid in (249, 248, 94, 19, 219, 166, 155, 1200):
        q = quests.get(qid)
        print(qid, q and {k: q[k] for k in ("title", "min", "level", "prev", "next", "excl", "chain", "objectives", "starts", "ends")})


if __name__ == "__main__":
    main()
