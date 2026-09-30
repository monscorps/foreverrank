"""Where to do each quest, from the CMaNGOS Classic database (GPL-3.0): the creatures and objects a quest
asks you to kill or use, the creatures and chests that drop the items it asks for, and where all of them
spawn, clustered into a few areas per quest.

Classic data is a starting guess for Forever (the addon labels it); players' own objective progress,
noted by QuestBank's discoveries, replaces it as it comes in.

  python3 tools/questbank/objectives.py   # research/cmangos/ClassicDB.sql.gz -> research/questbank/objectives.json
"""
import json, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cmangos  # noqa: E402

OUT = os.path.join(cmangos.REPO, "research", "questbank", "objectives.json")
CELL = 120.0        # yards: spawns within a cell or its neighbours count as one area
MAX_AREAS = 3       # per objective
MIN_SHARE = 0.15    # an area must hold this share of the objective's spawns to be shown
NEAR = 2500.0       # yards: areas this close to the quest's giver or turn-in come first; far ones only if nothing is near


def main():
    cmangos.WANT |= {"creature_loot_template", "gameobject_loot_template"}
    data = cmangos.read()

    def rows(table):
        for idx, r in data[table]:
            yield (lambda c, idx=idx, r=r: r[idx[c.lower()]])

    # what each quest needs
    need = {}
    wanted_items = set()
    for g in rows("quest_template"):
        qid = g("entry")
        targets = []
        for k in range(1, 5):
            t = g("ReqCreatureOrGOId%d" % k) or 0
            n = g("ReqCreatureOrGOCount%d" % k) or 0
            if t > 0 and n > 0:
                targets.append(("kill", "npc", t))
            elif t < 0 and n > 0:
                targets.append(("use", "object", -t))
        items = []
        for k in range(1, 5):
            it, n = g("ReqItemId%d" % k) or 0, g("ReqItemCount%d" % k) or 0
            if it and n:
                items.append(it)
                wanted_items.add(it)
        if targets or items:
            need[qid] = {"targets": targets, "items": items}

    # who drops the items (quest drops and ordinary ones; quest drops come first)
    loot_npc, loot_obj = {}, {}
    for table, dest in (("creature_loot_template", loot_npc), ("gameobject_loot_template", loot_obj)):
        for g in rows(table):
            it = g("item")
            if it in wanted_items:
                chance = g("ChanceOrQuestChance") or 0
                dest.setdefault(g("entry"), []).append((it, abs(chance), chance < 0))
    by_loot_npc = {}
    for g in rows("creature_template"):
        lid = g("LootId") or 0
        if lid in loot_npc:
            for it, chance, quest in loot_npc[lid]:
                by_loot_npc.setdefault(it, []).append((g("Entry"), chance, quest))
    by_loot_obj = {}
    for g in rows("gameobject_template"):
        if g("type") == 3 and (g("data1") or 0) in loot_obj:  # chests: data1 is the loot id
            for it, chance, quest in loot_obj[g("data1")]:
                by_loot_obj.setdefault(it, []).append((g("entry"), chance, quest))

    # who gives and takes each quest, for "near the quest" ranking
    ends_of = {}
    for table, kind in (("creature_questrelation", "npc"), ("creature_involvedrelation", "npc"),
                        ("gameobject_questrelation", "object"), ("gameobject_involvedrelation", "object")):
        for idx, r in data[table]:
            ends_of.setdefault(r[idx["quest"]], []).append((kind, r[idx["id"]]))

    # every creature and object involved, and where they spawn on the two continents
    ids = {"npc": set(), "object": set()}
    for lst in ends_of.values():
        for kind, i in lst:
            ids[kind].add(i)
    for q in need.values():
        for _, kind, i in q["targets"]:
            ids[kind].add(i)
        for it in q["items"]:
            for e, _, _ in by_loot_npc.get(it, []):
                ids["npc"].add(e)
            for e, _, _ in by_loot_obj.get(it, []):
                ids["object"].add(e)
    spawns = {"npc": {}, "object": {}}
    for kind, table in (("npc", "creature"), ("object", "gameobject")):
        for idx, r in data[table]:
            i = r[idx["id"]]
            if i in ids[kind] and r[idx["map"]] in (0, 1):
                spawns[kind].setdefault(i, []).append((r[idx["map"]], r[idx["position_x"]], r[idx["position_y"]]))

    def anchors(qid):
        pts = []
        for kind, i in ends_of.get(qid, []):
            pts += spawns[kind].get(i, [])[:3]
        return pts

    def areas(points, near=None):
        """The busiest few areas: cells of CELL yards, merged with their neighbours; near the quest first."""
        if not points:
            return []
        if near:
            close = [p for p in points if any(p[0] == a[0] and math.hypot(p[1] - a[1], p[2] - a[2]) <= NEAR for a in near)]
            if close:
                points = close
        cells = {}
        for c, x, y in points:
            cells.setdefault((c, int(x // CELL), int(y // CELL)), []).append((x, y))
        out, used = [], set()
        for key in sorted(cells, key=lambda k: -len(cells[k])):
            if key in used:
                continue
            c, cx, cy = key
            pts = []
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    k = (c, cx + dx, cy + dy)
                    if k in cells and k not in used:
                        pts += cells[k]
                        used.add(k)
            if len(pts) < max(1, MIN_SHARE * len(points)):
                continue
            mx = sum(p[0] for p in pts) / len(pts)
            my = sum(p[1] for p in pts) / len(pts)
            r = max(math.hypot(p[0] - mx, p[1] - my) for p in pts)
            out.append([c, round(mx), round(my), max(20, round(r)), len(pts)])
            if len(out) >= MAX_AREAS:
                break
        return out

    result = {}
    for qid, q in need.items():
        objs = []
        near = anchors(qid)
        for how, kind, i in q["targets"]:
            a = areas(spawns[kind].get(i, []), near)
            if a:
                objs.append({"how": how, "kind": kind, "id": i, "areas": a})
        for it in q["items"]:
            # quest-only drops if there are any, else every source that drops it at 5% or more
            srcs = [(e, ch, qd) for e, ch, qd in by_loot_npc.get(it, [])]
            quest_only = [s for s in srcs if s[2]]
            use = quest_only or [s for s in srcs if s[1] >= 5]
            pts = []
            for e, _, _ in use[:40]:
                pts += spawns["npc"].get(e, [])
            for e, ch, qd in by_loot_obj.get(it, []):
                pts += spawns["object"].get(e, [])
            a = areas(pts, near)
            if a:
                objs.append({"how": "loot", "item": it, "areas": a})
        if objs:
            result[qid] = objs
    json.dump(result, open(OUT, "w"), separators=(",", ":"))
    n_areas = sum(len(o["areas"]) for v in result.values() for o in v)
    print("wrote %s: %d quests with objective areas (%d areas) of %d quests with objectives" % (OUT, len(result), n_areas, len(need)))
    for qid in (7, 33, 18, 166, 1200, 91):
        print(qid, json.dumps(result.get(qid))[:300])


if __name__ == "__main__":
    main()
