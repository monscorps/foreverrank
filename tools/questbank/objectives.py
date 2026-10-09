"""Where to do each quest, from the CMaNGOS Classic database (GPL-3.0): the creatures and objects a quest
asks you to kill or use, the creatures and chests that drop the items it asks for, and where all of them
spawn, clustered into a few areas per quest.

Two files come out of one read of the database:
- objectives.json: up to three areas per objective, which gen_data.py folds into D.OBJ (the Available tab's
  "done in the same spot"). Its rules are unchanged.
- spots.json: the world map's objective icons, objective by objective: what you do there (kill, collect, use,
  buy, explore, fish/pickpocket/skin), the quest-log slot it fills, how many it takes, and up to five areas
  each, nearest the quest's giver and ender first; plus where the items that start quests drop. Spawns that
  resolve through creature_spawn_entry / gameobject_spawn_entry count, spawns that only come with a game event
  (the Darkmoon Faire, the elemental invasions) only for that event's own quests, reference loot is
  followed, vendors (of the quest's side or neutral) and fishing, pickpocketing and skinning stand in when
  nothing drops the item, an item the quest hands you or one you carry from the step before (as many as it
  asks for) gets no spot, and the quest's own POI outlines (quest_poi, centre and radius) fill objectives no
  spawn places, the source items an objective's item is made from, and explore and event objectives. Outlines
  some rows give in an instance's own coordinates under a continent's map id are left out. Also, for every
  quest: what each quest-log slot is (creature, object, spell cast or item, and which item), and whether the
  quest log may show an event or a reputation line beside them, so gen_data.py can name item slots and pair
  players' objective spots with the slots; and which quests need a profession or a reputation the giver checks
  before offering them.

Classic data is a starting guess for Forever (the addon labels it); players' own objective progress,
noted by QuestBank's discoveries, replaces it as it comes in.

  python3 tools/questbank/objectives.py   # research/cmangos/ClassicDB.sql.gz -> research/questbank/objectives.json, spots.json
"""
import collections, json, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cmangos  # noqa: E402

OUT = os.path.join(cmangos.REPO, "research", "questbank", "objectives.json")
CELL = 120.0        # yards: spawns within a cell or its neighbours count as one area
MAX_AREAS = 3       # per objective
MIN_SHARE = 0.15    # an area must hold this share of the objective's spawns to be shown
NEAR = 2500.0       # yards: areas this close to the quest's giver or turn-in come first; far ones only if nothing is near

# the map icons (spots.json)
SPOTS = os.path.join(cmangos.REPO, "research", "questbank", "spots.json")
SPOT_AREAS = 5      # per objective
SPOT_SHARE = 0.05   # an area must hold this share of the objective's spawns; when none does, the busiest stand in
NODE = 300          # a source with more spawns than this is a resource node (ore, herbs) or a critter: only its areas near the quest
MIN_DROP = 5        # percent: ordinary drops below this count only when nothing else gives the item
MIN_R = 20          # yards: the smallest area around a spawn
# quest_poi objIndex: -1 the turn-in, 0-3 the creature or object objectives, 4-7 the item objectives, 9-15 the source
# items an objective's item is made from (ReqSourceId, not in a fixed order: Pamela's Doll's head and sides), 16 an
# explore or event spot
POI_SOURCE = range(9, 16)
POI_EVENT = 16
POI_SNAP = 25       # yards: an outline centred this close to one of its objective's spawns inside an instance ...
POI_REAL = 300      # ... with none of them this close on the continent may be in that instance's coordinates
POI_BOX = 100       # yards around an instance's spawns: its own coordinates, for the outlines of its quests
ENTRANCE = 1000     # yards: such an outline stands for the instance when it lies this close to its entrance
BUILD = "1.60.1.70291"  # the client tables gen_data.py reads (research/wago/<build>)
ALLIANCE, HORDE = 1 | 4 | 8 | 64, 2 | 16 | 32 | 128  # RequiredRaces: Human, Dwarf, Night Elf, Gnome; Orc, Undead, Tauren, Troll
SEASONAL = {-22, -364, -365, -366, -368, -369}  # ZoneOrSort: Seasonal, Darkmoon Faire, Ahn'Qiraj War, Lunar Festival, Invasion, Midsummer


def main():
    cmangos.WANT |= {"creature_loot_template", "gameobject_loot_template", "reference_loot_template",
                     "pickpocketing_loot_template", "skinning_loot_template", "npc_vendor", "npc_vendor_template"}
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
    spots(rows, data)


def near_dist(p, near):
    """Yards from a (continent, x, y, ...) point to the nearest of near's points on its continent."""
    ds = [math.hypot(p[1] - n[1], p[2] - n[2]) for n in near if n[0] == p[0]]
    return min(ds) if ds else 1e9


def cluster(pts, near):
    """Up to SPOT_AREAS areas over [(continent, x, y, source)] points, each [continent, x, y, radius, points, the
    busiest source]: cells of CELL yards merged with their neighbours, as for objectives.json. Only the points
    within NEAR yards of the quest's giver and ender (near: [(continent, x, y)]) when there are any; an area must
    hold SPOT_SHARE of them (when none does, the busiest stand in); the nearest the quest come first.
    gen_data.py clusters Wowhead's points with it too."""
    close = [p for p in pts if near_dist(p, near) <= NEAR] if near else []
    pts = close or pts  # far areas only when nothing is near the quest
    if not pts:
        return []
    cells = {}
    for p in pts:
        cells.setdefault((p[0], int(p[1] // CELL), int(p[2] // CELL)), []).append(p)
    found, used = [], set()
    for key in sorted(cells, key=lambda k: (-len(cells[k]), k)):
        if key in used:
            continue
        c, cx, cy = key
        mine = []
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                k = (c, cx + dx, cy + dy)
                if k in cells and k not in used:
                    mine += cells[k]
                    used.add(k)
        mx = sum(p[1] for p in mine) / len(mine)
        my = sum(p[2] for p in mine) / len(mine)
        r = max(math.hypot(p[1] - mx, p[2] - my) for p in mine)
        count = {}
        for p in mine:
            count[p[3]] = count.get(p[3], 0) + 1
        top = max(sorted(count), key=lambda s: count[s])
        found.append([c, round(mx), round(my), max(MIN_R, round(r)), len(mine), top])
    keep = [a for a in found if a[4] >= SPOT_SHARE * len(pts)] or found[:SPOT_AREAS]
    if near:
        keep.sort(key=lambda a: (round(near_dist(a, near)), -a[4], a[1], a[2]))
    return keep[:SPOT_AREAS]


def hostility():
    """FactionTemplate id -> the sides ("A", "H") a creature of that template is hostile to, from the newest client
    table under research/wago that has FactionTemplate.csv (the ids are Classic's); {} when none has it."""
    import csv, glob
    found = sorted(glob.glob(os.path.join(cmangos.REPO, "research", "wago", "*", "FactionTemplate.csv")))
    if not found:
        return {}
    tpl = {}
    for r in csv.DictReader(open(found[-1])):
        tpl[int(r["ID"])] = {"faction": int(r["Faction"]), "group": int(r["FactionGroup"]), "enemy": int(r["EnemyGroup"]),
                             "enemies": {int(r["Enemies_%d" % k]) for k in range(8)} - {0},
                             "friends": {int(r["Friend_%d" % k]) for k in range(8)} - {0}}
    players = {"A": tpl.get(1), "H": tpl.get(2)}  # Human's and Orc's templates stand for each side

    def hostile(v, p):
        if p["faction"] in v["enemies"]:
            return True
        if p["faction"] in v["friends"]:
            return False
        return bool(v["enemy"] & p["group"] or p["enemy"] & v["group"])
    return {i: {side for side, p in players.items() if p and hostile(v, p)} for i, v in tpl.items()}


def spots(rows, data):
    """spots.json: per quest, per objective, up to SPOT_AREAS areas in world yards for the map icons:
    {"q": {quest: {"req": {slot: count}, "obj": [{"k": kind, "slot": slot, "spots": [[continent, x, y, radius,
    src, name, wma], ...], "wma": [...]}]}}, "start": {item: {"quest": quest, "spots": [...]}}}. kind: k kill, u use
    an object (or cast on a creature), c collect (a creature's drop or a chest's loot), b buy from a vendor, f fishing,
    pickpocketing or skinning, e explore or event, s where an item that starts a quest drops. slot: 1-4 the
    creature or object objective, 5-8 the item objective (ReqItem slot + 4), 0 none. src: c a spawn, p a POI.
    name: what the spot is named after: the creature, chest or fishing hole for c, f, k and u, the item for b and s.
    wma: the WorldMapArea a POI is drawn on in Blizzard's data (0 for a spawn); an objective's "wma" lists those of
    its POIs, the map gen_data.py prefers for its spawns too.
    Two more keys cover every quest, placed or not. "need": {quest: {"req": {slot: count}, "ty": {slot: "npc" |
    "object" | "cast" | "item"}, "names": {slot: the creature's or object's name}, "items": {slot: item},
    "event": 1, "rep": 1}}: what each slot is, for naming item slots and for pairing the game's objective lines
    (players' spots) with them; event (SpecialFlags 2: an escort, a place to reach, a script) and rep
    (RepObjectiveFaction: a standing to reach) mark the lines the game may list beside the slots, which move the
    slots' places in its list. "lock": {quest: "skill" | "rep" | "skill,rep"}: the quest needs a profession (RequiredSkill)
    or a standing with a faction (RequiredMinRep..., RequiredMaxRep...) that QuestBank can't check from its data."""
    import travel
    TR = travel.Travel(BUILD)
    # a dungeon's or battleground's area (a quest's ZoneOrSort) -> its map, and each instance's entrance on its
    # continent (the client's Map table: where a ghost walks back in; Naxxramas and the battlegrounds have none)
    instance_of = {int(r["ID"]): int(r["ContinentID"]) for r in travel.rows(BUILD, "AreaTable") if int(r["ContinentID"]) not in (0, 1)}
    entrance = {int(r["ID"]): (int(r["CorpseMapID"]), float(r["Corpse_0"]), float(r["Corpse_1"]))
                for r in travel.rows(BUILD, "Map") if int(r["CorpseMapID"]) in (0, 1) and (float(r["Corpse_0"]) or float(r["Corpse_1"]))}
    hostile_to = hostility()
    names = {"npc": {}, "object": {}, "item": {}}
    loot_of = {}    # creature entry -> {"loot": id, "pick": id, "skin": id, "vendor": template id, "faction": template}
    for g in rows("creature_template"):
        e = g("Entry")
        names["npc"][e] = g("Name")
        loot_of[e] = {"loot": g("LootId") or 0, "pick": g("PickpocketLootId") or 0, "skin": g("SkinningLootId") or 0,
                      "vendor": g("VendorTemplateId") or 0, "faction": g("Faction") or 0}
    go_loot = {}    # gameobject entry -> ("c" chest | "f" fishing hole, loot id)
    for g in rows("gameobject_template"):
        e = g("entry")
        names["object"][e] = g("name")
        if g("type") in (3, 25) and (g("data1") or 0) > 0:
            go_loot[e] = ("c" if g("type") == 3 else "f", g("data1"))
    starts = {}     # item -> the quest it starts
    for g in rows("item_template"):
        names["item"][g("entry")] = g("name")
        if g("startquest"):
            starts[g("entry")] = g("startquest")

    # every quest's objectives, and the items it hands you or that you carry in from the step before, with how many
    quests, given_by, before, lock = {}, {}, {}, {}
    for g in rows("quest_template"):
        qid = g("entry")
        q = {"targets": [], "items": [], "sources": [], "req": {}, "event": bool((g("SpecialFlags") or 0) & 2),
             "src": g("SrcItemId") or 0, "src_n": g("SrcItemCount") or 0, "zone": g("ZoneOrSort") or 0,
             "races": g("RequiredRaces") or 0, "ty": {}, "names": {},
             "rep": bool(g("RepObjectiveFaction"))}  # a standing to reach, which the quest log may list as a line
        # what the giver checks beyond level, side, class and the chain: a profession, a standing with a faction (at
        # least, or at most: Avast Ye, Scallywag only for those Booty Bay no longer likes)
        why = [w for w, on in (("skill", g("RequiredSkill")), ("rep", g("RequiredMinRepFaction") or g("RequiredMaxRepFaction"))) if on]
        if why:
            lock[qid] = ",".join(why)
        for k in range(1, 5):
            t, n = g("ReqCreatureOrGOId%d" % k) or 0, g("ReqCreatureOrGOCount%d" % k) or 0
            if t and n > 0:
                kind = "u" if t < 0 or g("ReqSpellCast%d" % k) else "k"
                q["targets"].append((k, kind, "object" if t < 0 else "npc", abs(t)))
                q["req"][k] = n
                q["ty"][k] = "object" if t < 0 else ("cast" if g("ReqSpellCast%d" % k) else "npc")
                q["names"][k] = names["object" if t < 0 else "npc"].get(abs(t)) or ""
            it, n = g("ReqItemId%d" % k) or 0, g("ReqItemCount%d" % k) or 0
            if it and n > 0:
                q["items"].append((k + 4, it))
                q["req"][k + 4] = n
                q["ty"][k + 4] = "item"
            it, n = g("ReqSourceId%d" % k) or 0, g("ReqSourceCount%d" % k) or 0
            if it and n > 0 and all(it != s for s, _ in q["sources"]):  # The Angry Scytheclaws lists its feather three times
                q["sources"].append((it, n))
        quests[qid] = q
        hands = {}
        for it, n in [(g("SrcItemId"), g("SrcItemCount"))] + [(g("RewItemId%d" % k), g("RewItemCount%d" % k)) for k in range(1, 5)] + \
                [(g("RewChoiceItemId%d" % k), g("RewChoiceItemCount%d" % k)) for k in range(1, 7)]:
            if it:
                hands[it] = max(hands.get(it, 0), n or 1)
        given_by[qid] = hands
        for nxt in (g("NextQuestId") or 0, g("NextQuestInChain") or 0):
            if nxt > 0:
                before.setdefault(nxt, set()).add(qid)
        if (g("PrevQuestId") or 0) > 0:
            before.setdefault(qid, set()).add(g("PrevQuestId"))
    for it, qid in starts.items():
        if qid in quests:
            quests[qid].setdefault("start_items", set()).add(it)

    def carried(qid):
        """{item: how many you hold on taking the quest}: what it hands you, the item that starts it, and what the
        steps before it reward."""
        q = quests[qid]
        out = {}
        for it, n in [(q["src"], q["src_n"])] + [(it, 1) for it in q.get("start_items", ())] + \
                [kv for p in before.get(qid, ()) for kv in given_by.get(p, {}).items()]:
            if it:
                out[it] = max(out.get(it, 0), n or 1)
        return out

    wanted = {it for q in quests.values() for _, it in q["items"]} | {it for q in quests.values() for it, _ in q["sources"]} | set(starts)

    # loot tables, references followed: entry -> {item: (chance in percent, quest drop)}
    def chances(table):
        groups = {}
        for g in rows(table):
            groups.setdefault(g("entry"), []).append((g("item"), g("ChanceOrQuestChance") or 0, g("groupid") or 0,
                                                       g("mincountOrRef") or 0))
        return groups
    refs = chances("reference_loot_template")
    ref_memo = {}

    def expand(entries, entry, depth=0):
        """{item: (chance, quest)} for one loot entry. Rows of chance 0 in a group share what the group's
        explicit chances leave."""
        out = {}
        rows_ = entries.get(entry, [])
        left, zeros = {}, {}
        for it, ch, grp, mc in rows_:
            if ch:
                left[grp] = left.get(grp, 100.0) - abs(ch)
            else:
                zeros[grp] = zeros.get(grp, 0) + 1
        for it, ch, grp, mc in rows_:
            share = abs(ch) if ch else max(0.0, left.get(grp, 100.0)) / zeros[grp]
            if mc < 0:  # a reference: everything in it, scaled by this row's chance
                if depth > 4:
                    continue
                if -mc not in ref_memo:
                    ref_memo[-mc] = expand(refs, -mc, depth + 1)
                for rit, (rch, rq) in ref_memo[-mc].items():
                    c = share * rch / 100.0
                    if rit not in out or c > out[rit][0]:
                        out[rit] = (c, rq or ch < 0)
            elif it in wanted:
                if it not in out or share > out[it][0]:
                    out[it] = (share, ch < 0)
        return out

    sources = {}    # item -> [(how, "npc"|"object", entry, chance, quest drop)]
    for table, field, how in (("creature_loot_template", "loot", "c"), ("pickpocketing_loot_template", "pick", "f"),
                              ("skinning_loot_template", "skin", "f")):
        entries = chances(table)
        by_id = {}
        for e, lo in loot_of.items():
            if lo[field]:
                by_id.setdefault(lo[field], []).append(e)
        for lid in entries:
            if lid not in by_id:
                continue
            for it, (ch, qd) in expand(entries, lid).items():
                for e in by_id[lid]:
                    sources.setdefault(it, []).append((how, "npc", e, ch, qd))
    entries = chances("gameobject_loot_template")
    for e, (how, lid) in go_loot.items():
        if lid in entries:
            for it, (ch, qd) in expand(entries, lid).items():
                sources.setdefault(it, []).append((how, "object", e, ch, qd))
    vend_tpl = {}
    for g in rows("npc_vendor_template"):
        if g("item") in wanted:
            vend_tpl.setdefault(g("entry"), []).append(g("item"))
    for g in rows("npc_vendor"):
        if g("item") in wanted:
            sources.setdefault(g("item"), []).append(("b", "npc", g("entry"), 100.0, False))
    for e, lo in loot_of.items():
        for it in vend_tpl.get(lo["vendor"], []):
            sources.setdefault(it, []).append(("b", "npc", e, 100.0, False))

    # where everything spawns on the two continents, spawns of id 0 resolved through their spawn entries; the spawns
    # that only come with a game event (the Darkmoon Faire's vendors, the elemental invasions) count for that event's
    # own quests only; and on every map, instances too, to tell an outline in an instance's coordinates
    spawns = {kind: cmangos.spawn_points(data, kind) for kind in ("npc", "object")}
    festive = {}
    for kind in ("npc", "object"):
        festive[kind] = {e: list(sp) for e, sp in spawns[kind].items()}
        for e, sp in cmangos.spawn_points(data, kind, event=True).items():
            festive[kind].setdefault(e, []).extend(sp)
    every, box = {}, {}
    for kind in ("npc", "object"):
        every[kind] = cmangos.spawn_points(data, kind, maps=None)
        for e, sp in cmangos.spawn_points(data, kind, maps=None, event=True).items():
            every[kind].setdefault(e, []).extend(sp)
        for sp in every[kind].values():
            for m, x, y in sp:
                if m not in (0, 1):
                    b = box.get(m)
                    box[m] = (min(b[0], x), min(b[1], y), max(b[2], x), max(b[3], y)) if b else (x, y, x, y)

    # who gives and takes each quest: the areas nearest them come first; the side a quest is for. A quest of a game
    # event (game_event_quest, a seasonal quest sort, or given or taken by someone who only comes with one) also counts
    # the event's spawns
    anchor, enders = {}, {}
    event_quests = {r[idx["quest"]] for idx, r in data["game_event_quest"]} | {qid for qid, q in quests.items() if q["zone"] in SEASONAL}
    for table, kind in (("creature_questrelation", "npc"), ("creature_involvedrelation", "npc"),
                        ("gameobject_questrelation", "object"), ("gameobject_involvedrelation", "object")):
        for idx, r in data[table]:
            qid, i = r[idx["quest"]], r[idx["id"]]
            if i not in spawns[kind] and i in festive[kind]:
                event_quests.add(qid)
            anchor.setdefault(qid, []).extend(festive[kind].get(i, [])[:3])
            if kind == "npc":
                enders.setdefault(qid, []).append(i)

    def side_of(qid):
        """"A" or "H" for a quest of one side (its races, else the side none of its givers and enders is hostile to),
        else None."""
        races = quests[qid]["races"]
        if races:
            return "A" if not races & HORDE else "H" if not races & ALLIANCE else None
        hos = [hostile_to.get(loot_of.get(e, {}).get("faction"), set()) for e in enders.get(qid, [])]
        for side, other in (("A", "H"), ("H", "A")):
            if hos and all(other in h and side not in h for h in hos):
                return side
        return None

    def maps_of(qid):
        """The zone or city maps the quest's giver and ender stand on."""
        return {m[0] for m in (TR.locate(c, x, y) for c, x, y in anchor.get(qid, [])) if m}

    # the quests' own POI outlines (Blizzard-style areas, world yards): (objIndex, continent, centre, radius, the
    # WorldMapArea it is drawn on)
    poi_pts = {}
    for g in rows("quest_poi_points"):
        poi_pts.setdefault((g("questId"), g("poiId")), []).append((g("x"), g("y")))
    pois = {}
    for g in rows("quest_poi"):
        pts = poi_pts.get((g("questId"), g("poiId")))
        if not pts or g("mapId") not in (0, 1) or g("objIndex") < 0:
            continue
        mx = sum(p[0] for p in pts) / len(pts)
        my = sum(p[1] for p in pts) / len(pts)
        r = max(math.hypot(p[0] - mx, p[1] - my) for p in pts) if len(pts) > 1 else 0
        pois.setdefault(g("questId"), []).append((g("objIndex"), g("mapId"), mx, my, r, g("mapAreaId") or 0))

    def poi_sources(q, oi):
        """The creatures and objects an outline's objective is about, to test its coordinates against."""
        if 0 <= oi <= 3:
            return [(what, i) for slot, _, what, i in q["targets"] if slot == oi + 1]
        if 4 <= oi <= 7:
            its = [it for slot, it in q["items"] if slot == oi + 1]
        elif oi in POI_SOURCE:
            its = [it for _, it in q["items"]] + [it for it, _ in q["sources"]]
        else:
            its = []
        return sorted({(s[1], s[2]) for it in its for s in sources.get(it, [])})

    def instances_under(q, poi):
        """The instances whose own coordinates an outline may be given in, under a continent's map id: one of its
        objective's spawns inside an instance lies under its centre while none stands near it on the continent, or it
        lies within the range of the quest's own instance. Some CMaNGOS rows do that: The Madness Within's bosses in
        Dire Maul land in Silverpine."""
        oi, c, x, y, r, _ = poi
        out = set()
        for kind, e in poi_sources(q, oi):
            for m, sx, sy in every[kind].get(e, ()):
                d = math.hypot(sx - x, sy - y)
                if m in (0, 1):
                    if m == c and d <= POI_REAL:
                        return set()
                elif d <= POI_SNAP + r:
                    out.add(m)
        m = instance_of.get(q["zone"])
        b = box.get(m)
        if b and b[0] - POI_BOX <= x <= b[2] + POI_BOX and b[1] - POI_BOX <= y <= b[3] + POI_BOX:
            out.add(m)
        return out

    def stands_for(qid, m, poi):
        """Whether an outline in instance m's coordinates still marks that instance on the continent: it lies near the
        entrance (Stratholme, Zul'Gurub and Ahn'Qiraj are built on the world's own coordinates), or, for an instance
        with no entrance known (Naxxramas, Alterac Valley), it lands where the quest is given or taken."""
        e = entrance.get(m)
        if e:
            return e[0] == poi[1] and math.hypot(e[1] - poi[2], e[2] - poi[3]) <= ENTRANCE
        at = TR.locate(poi[1], poi[2], poi[3])
        return bool(at) and at[0] in maps_of(qid)

    dropped_poi = set()
    for qid, lst in pois.items():
        q = quests.get(qid)
        if not q:
            continue
        keep = []
        for poi in lst:
            insts = instances_under(q, poi)
            if not insts or any(stands_for(qid, m, poi) for m in insts):
                keep.append(poi)
        if len(keep) < len(lst):
            dropped_poi.add(qid)
        pois[qid] = keep

    def name_of(kind, i):
        return names[kind].get(i) or ""

    def place(srcs, near, pool):
        """Up to SPOT_AREAS areas over (kind, entry) sources: [continent, x, y, radius, "c", the busiest source's
        name, 0], from pool's spawns (spawns, or festive for an event's quest)."""
        pts = []
        for kind, e in srcs:
            sp = pool[kind].get(e, [])
            if len(sp) > NODE:  # ore, herbs, critters: only what lies near the quest, and nothing without a giver to be near
                sp = [p for p in sp if near_dist(p, near) <= NEAR]
            pts += [(c, x, y, (kind, e)) for c, x, y in sp]
        return [[a[0], a[1], a[2], a[3], "c", name_of(*a[5]), 0] for a in cluster(pts, near)]

    def item_spots(it, near, side, pool):
        """The kind and areas of an item, from its best kind of source: quest drops (or drops of MIN_DROP percent
        and up) and chests; else vendors (none hostile to the quest's side); else pickpocketing and skinning; else
        rare drops; else fishing holes. A vendor's areas are named after the item."""
        srcs = sources.get(it, [])
        drops = [s for s in srcs if s[0] == "c" and s[1] == "npc"]
        chests = [s for s in srcs if s[0] == "c" and s[1] == "object"]
        tiers = (("c", ([s for s in drops if s[4]] or [s for s in drops if s[3] >= MIN_DROP]) + chests),
                 ("b", [s for s in srcs if s[0] == "b" and side not in hostile_to.get(loot_of.get(s[2], {}).get("faction"), ())]),
                 ("f", [s for s in srcs if s[0] == "f" and s[1] == "npc"]),
                 ("c", [s for s in drops if not s[4] and s[3] < MIN_DROP]),
                 ("f", [s for s in srcs if s[0] == "f" and s[1] == "object"]))
        for how, lst in tiers:
            a = place(sorted({(s[1], s[2]) for s in lst}), near, pool)
            if a:
                if how == "b":
                    for sp in a:
                        sp[5] = name_of("item", it)
                return how, a
        return None, []

    def related(o, oi):
        """The outlines that belong to an objective: its own, its item's source items', an event's."""
        if o["k"] == "e":
            return oi == POI_EVENT or oi in POI_SOURCE
        return oi == o["slot"] - 1 or (o["slot"] >= 5 or not o["slot"]) and oi in POI_SOURCE

    out_q, n_obj, n_src = {}, 0, {"c": 0, "p": 0}
    for qid, q in sorted(quests.items()):
        near = anchor.get(qid, [])
        side, pool = side_of(qid), festive if qid in event_quests else spawns
        objs, done = [], set()
        for slot, kind, what, i in q["targets"]:
            a = place([(what, i)], near, pool)
            if a:
                objs.append({"k": kind, "slot": slot, "spots": a})
                done.add(slot)
        held = carried(qid)
        for slot, it in q["items"]:
            if held.get(it, 0) >= q["req"][slot]:
                done.add(slot)  # handed to you, or carried in from the step before: nowhere to go for it
                continue
            how, a = item_spots(it, near, side, pool)
            if a:
                objs.append({"k": how, "slot": slot, "spots": a})
                done.add(slot)
        # the quest's own outlines where nothing spawns: the objective's, the source items', and the explore and
        # event spots
        poi = pois.get(qid, [])

        def outlines(test, name):
            a = sorted((round(near_dist((c, x, y), near)), round(x), round(y), c, round(r), w) for oi, c, x, y, r, w in poi if test(oi))
            return [[c, x, y, r, "p", name, w] for _, x, y, c, r, w in a[:SPOT_AREAS]]
        for slot, kind, what, i in q["targets"]:
            a = outlines(lambda oi: oi == slot - 1, name_of(what, i))
            if a and slot not in done:
                objs.append({"k": kind, "slot": slot, "spots": a})
                done.add(slot)
        for slot, it in q["items"]:
            a = outlines(lambda oi: oi == slot - 1, name_of("item", it))
            if a and slot not in done:
                objs.append({"k": "c", "slot": slot, "spots": a})
                done.add(slot)
        # the one item objective nothing places, made from others (Pamela's Doll from its head and two sides), or what an
        # event with no other objective needs (the Witherbark skull for Grim Message): where those are found. Not for
        # slot 0 beside other objectives: the addon matches a slot-0 collect spot to the game's object lines
        open_items = [(slot, it) for slot, it in q["items"] if slot not in done]
        made = open_items[0][0] if len(open_items) == 1 else 0
        if made or (q["sources"] and not q["items"] and not q["targets"]):
            left = []
            for it, n in q["sources"]:
                if held.get(it, 0) >= n:
                    continue
                how, a = item_spots(it, near, side, pool)
                if a:
                    objs.append({"k": how, "slot": made, "spots": a})
                else:
                    left.append(it)
            if left or not q["sources"]:
                # their outlines, objIndex 9-15 in no fixed order: named only when one item is left to find
                one = left if q["sources"] else [it for _, it in open_items]
                a = outlines(lambda oi: oi in POI_SOURCE, name_of("item", one[0]) if len(one) == 1 else "")
                if a:
                    objs.append({"k": "c", "slot": made, "spots": a})
        if q["event"] or not objs:
            a = outlines(lambda oi: oi == POI_EVENT, "")
            if not a and not objs:  # nothing else at all: whatever outline the quest has
                a = outlines(lambda oi: oi in POI_SOURCE, "")
            if a:
                objs.append({"k": "e", "slot": 0, "spots": a})
        for o in objs:
            wma = collections.Counter(w for oi, _, _, _, _, w in poi if w and related(o, oi))
            if wma:
                o["wma"] = [w for w, _ in wma.most_common()]
        if objs:
            out_q[qid] = {"req": q["req"], "obj": objs}
            n_obj += len(objs)
            for o in objs:
                n_src[o["spots"][0][4]] += 1
    out_s = {}
    for it, qid in sorted(starts.items()):
        if it not in sources:
            continue
        _, a = item_spots(it, anchor.get(qid, []), side_of(qid) if qid in quests else None,
                          festive if qid in event_quests else spawns)
        if a:
            for sp in a:
                sp[5] = name_of("item", it)  # the item that drops here
            out_s[it] = {"quest": qid, "spots": a}
    need = {}
    for qid, q in sorted(quests.items()):
        if q["req"] or q["event"] or q["rep"]:
            need[qid] = {"req": q["req"], "ty": q["ty"]}
            if any(q["names"].values()):
                need[qid]["names"] = {k: v for k, v in q["names"].items() if v}
            if q["items"]:
                need[qid]["items"] = dict(q["items"])
            if q["event"]:
                need[qid]["event"] = 1
            if q["rep"]:
                need[qid]["rep"] = 1
    json.dump({"q": out_q, "start": out_s, "need": need, "lock": lock}, open(SPOTS, "w"), separators=(",", ":"))
    print("wrote %s: %d quests with %d objectives placed (%d from spawns, %d from POI outlines only), %d quest-starting items; "
          "%d quests lost outlines given in an instance's coordinates; %d quests' slots; %d quests need a profession or a "
          "reputation" % (SPOTS, len(out_q), n_obj, n_src["c"], n_src["p"], len(out_s), len(dropped_poi), len(need), len(lock)))
    for qid in (7, 33, 2, 905, 2932, 1648):
        print(qid, json.dumps(out_q.get(qid))[:300])


if __name__ == "__main__":
    main()
