#!/usr/bin/env python3
"""Carry the Forge talents (plan/plan-data.json) from one beta build to the next.

  python3 tools/apply_talents.py 1.60.1.69876 1.60.1.70009          # dry run: report
  python3 tools/apply_talents.py 1.60.1.69876 1.60.1.70009 --write  # update the file

Needs both builds' trait, spell and curve tables (tools/fetch_wago.py BUILD):
without Curve/CurvePoint and the description-variable tables the resolver
falls back to base x rank and multi-rank texts come out wrong.

What moves, and the rule for each:
  text     rank texts are rewritten only for talents whose text the resolver
           reproduces exactly from OLD; everything else is reported, untouched
  rename   the talent takes its spell's new name when the old name matched
           (was=<old name>); prerequisites that pointed at the old name follow
  icon     follows SpellMisc's icon file when the old icon matched the site's
  gone     a talent whose node left the class tree gets gone=<build>: it keeps
           its slot so shared build links (?b=, positional) still decode, but
           it takes no points (and the Forge hides it when a live talent now
           sits in its square)
  row/col  follow TraitNode PosX/PosY (600 per row and per column)
  moved    a talent whose node now sits in another spec: the old slot gets
           gone=<build> and moved=<tree>, and a copy with from=<old tree> and
           added=<build> is appended to that tree
  req      follows TraitEdge prerequisites
  new      a node on the class tree whose spell the site lacks is appended to
           its tree (appending never shifts the positions old links use), with
           the client's rank texts, c.s "new" and added=<build>; "text~" flags a
           rank value the client stores without a curve (the resolver then
           guesses base x rank, which the game does not always do)

Each site tree is tied to its spec by where its talents sit in OLD: one class
tree holds all three specs side by side, four columns each.
"""
import collections, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spelltext import Client, _rows
from verify_spelltext import norm

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAN = os.path.join(ROOT, "plan", "plan-data.json")
STEP = 600


class Tree:
    """Node positions, edges and which node carries which talent spell."""
    def __init__(self, build):
        nodes = _rows(build, "TraitNode")
        self.pos = {r["ID"]: (int(r["PosX"]), int(r["PosY"])) for r in nodes}
        self.tree_of = {r["ID"]: r["TraitTreeID"] for r in nodes}
        size = collections.Counter(self.tree_of.values())
        defs = {r["ID"]: r for r in _rows(build, "TraitDefinition")}
        entries = {r["ID"]: r for r in _rows(build, "TraitNodeEntry")}
        # a spell can sit in a stub tree and in the real class tree (Elemental
        # Fury: 16-node 1081 and 50-node 1082); the real one is the big one
        self.node_of, self.ranks, self.override = {}, {}, {}
        self.spells_on = collections.defaultdict(list)
        for r in _rows(build, "TraitNodeXTraitNodeEntry"):
            e = entries.get(r["TraitNodeEntryID"]) or {}
            d = defs.get(e.get("TraitDefinitionID", "")) or {}
            sp, n = d.get("SpellID", ""), r["TraitNodeID"]
            if not sp or n not in self.pos:
                continue
            self.spells_on[n].append(sp)
            self.ranks[(n, sp)] = int(e.get("MaxRanks") or 1)
            if d.get("OverrideName_lang"):
                self.override[sp] = d["OverrideName_lang"]
            cur = self.node_of.get(sp)
            if cur is None or (size[self.tree_of[n]], self.tree_of[n]) > (size[self.tree_of[cur]], self.tree_of[cur]):
                self.node_of[sp] = n
        self.parents = {}
        for r in _rows(build, "TraitEdge"):
            self.parents.setdefault(r["RightTraitNodeID"], set()).add(r["LeftTraitNodeID"])

    def parent_spells(self, node):
        return {sp for sp, n in self.node_of.items() if n in self.parents.get(node, set())}


def icon_names(build):
    out = {}
    for r in _rows(build, "ManifestInterfaceData"):
        if r.get("FilePath", "").replace("\\", "/").lower().startswith("interface/icons/"):
            out[r["ID"]] = os.path.splitext(r["FileName"])[0].lower()
    return out


def bands(c, to):
    """Per site tree: (class TraitTree, PosX of column 1, PosY of row 1), the most common
    reading over its talents in OLD; and the class TraitTree itself."""
    out, trees = [], collections.Counter()
    for tr in c["trees"]:
        votes = collections.Counter()
        for t in tr["talents"]:
            n = to.node_of.get(str(t.get("sp") or ""))
            if n and not t.get("gone"):
                x, y = to.pos[n]
                votes[(to.tree_of[n], x - (t["col"] - 1) * STEP, y - (t["row"] - 1) * STEP)] += 1
        out.append(votes.most_common(1)[0][0] if votes else None)
        if votes:
            trees[out[-1][0]] += sum(votes.values())
    return out, (trees.most_common(1)[0][0] if trees else None)


def place(band, pos, tid):
    """The site tree a node position falls in, with its row and column there."""
    x, y = pos
    for ti, b in enumerate(band):
        if b and b[0] == tid and 0 <= x - b[1] < 4 * STEP and (x - b[1]) % STEP == 0 and (y - b[2]) % STEP == 0:
            return ti, (y - b[2]) // STEP + 1, (x - b[1]) // STEP + 1
    return None


def run(old_b, new_b, write=False):
    p = json.load(open(PLAN))
    old, new = Client(old_b), Client(new_b)
    to, tn = Tree(old_b), Tree(new_b)
    icons = icon_names(new_b)
    log = []
    for c in p["classes"]:
        cname = c["cls"] if isinstance(c.get("cls"), str) else (c.get("cls") or {}).get("name", "?")
        band, tid = bands(c, to)
        on_site = {str(t.get("sp")) for tr in c["trees"] for t in tr["talents"] if t.get("sp")}
        appended, edges = [], []   # appended after the walk, so no slot index moves
        for ti, tr in enumerate(c["trees"]):
            for t in tr["talents"]:
                sp = str(t.get("sp") or "")
                if not sp or t.get("gone"):
                    continue
                tag = "%s / %s / %s" % (cname, tr.get("name"), t["n"])
                no, nw = to.node_of.get(sp), tn.node_of.get(sp)
                # gone: no node left, or only one in a stub tree (King of the Jungle in 70170)
                if no and (not nw or tn.tree_of.get(nw) != tid):
                    t["gone"] = new_b
                    log.append(("gone", tag, "node %s left the class tree" % no))
                    continue
                # text
                maxr = t.get("r", 1)
                descs = t.get("desc") or []
                try:
                    # the site shows a one-rank talent's spell as the game prints it (ranges); older texts showed the middle
                    exact = all(norm(d) in (norm(old.talent_game_text(sp, r, maxr)), norm(old.talent_text(sp, r, maxr)))
                                for r, d in enumerate(descs, 1) if d)
                except Exception:
                    exact = False
                if exact and descs:
                    fresh = []
                    for r, d in enumerate(descs, 1):
                        fresh.append(new.talent_game_text(sp, r, maxr) if d else d)
                    if [norm(x) for x in fresh] != [norm(x) for x in descs]:
                        log.append(("text", tag, "r1: " + norm(descs[0])[:90] + "  ->  " + norm(fresh[0])[:90]))
                        t["desc"] = fresh
                elif descs and new.spell.get(sp, {}).get("Description_lang") != old.spell.get(sp, {}).get("Description_lang"):
                    log.append(("text?", tag, "client text changed but the old text does not reproduce; left as is"))
                # rename
                on, nn = old.name.get(sp), new.name.get(sp)
                if on and nn and on != nn and t["n"] == on:
                    for other in tr["talents"]:
                        if other.get("req") == on:
                            other["req"] = nn
                    log.append(("rename", tag, "%s -> %s" % (on, nn)))
                    t["n"], t["was"] = nn, on
                # icon
                mo, mn = old.misc.get(sp), new.misc.get(sp)
                if mo and mn and mo["SpellIconFileDataID"] != mn["SpellIconFileDataID"]:
                    was, now = icons.get(mo["SpellIconFileDataID"]), icons.get(mn["SpellIconFileDataID"])
                    if now and t.get("icon") == was:
                        log.append(("icon", tag, "%s -> %s" % (was, now)))
                        t["icon"] = now
                if not (no and nw and no in to.pos and nw in tn.pos):
                    continue
                # row / col, or moved to another spec
                at = place(band, tn.pos[nw], tid)
                if at and at[0] != ti:
                    dest = c["trees"][at[0]]
                    copy = {k: v for k, v in t.items() if k not in ("req", "gone", "moved", "from")}
                    copy.update({"row": at[1], "col": at[2], "from": tr["name"], "added": new_b})
                    t["gone"], t["moved"] = new_b, dest["name"]
                    appended.append((at[0], copy, nw, True))
                    log.append(("moved", tag, "to %s row %d col %d (old slot kept for links, takes no points)" % (dest["name"], at[1], at[2])))
                    continue
                if at and (at[1], at[2]) != (t["row"], t["col"]):
                    kind = "row" if at[2] == t["col"] else "col" if at[1] == t["row"] else "pos"
                    log.append((kind, tag, "row %d col %d -> row %d col %d" % (t["row"], t["col"], at[1], at[2])))
                    t["row"], t["col"] = at[1], at[2]
                elif not at:
                    dy = tn.pos[nw][1] - to.pos[no][1]
                    if dy and dy % STEP == 0:
                        log.append(("row", tag, "row %d -> %d (off the spec grid: row only)" % (t["row"], t["row"] + dy // STEP)))
                        t["row"] += dy // STEP
                if to.parent_spells(no) != tn.parent_spells(nw):
                    edges.append((ti, t, nw, False))
        # new nodes on the class tree whose spell the site lacks
        for n, sps in sorted(tn.spells_on.items(), key=lambda kv: tn.pos[kv[0]]):
            fresh = [s for s in sps if s not in on_site]
            if tn.tree_of.get(n) != tid or not fresh:
                continue
            at = place(band, tn.pos[n], tid)
            if not at or len(sps) > 1:
                log.append(("new?", "%s / ? / %s" % (cname, ", ".join(new.name.get(s, s) for s in fresh)),
                            "node %s at %s: off the spec grids or a choice node; add by hand" % (n, tn.pos[n])))
                continue
            sp = fresh[0]
            r = tn.ranks.get((n, sp), 1)
            name = tn.override.get(sp) or new.name.get(sp, sp)
            try:
                desc = [new.talent_text(sp, k, r) for k in range(1, r + 1)]
            except Exception as e:
                desc = [""] * r
                log.append(("text?", "%s / %s / %s" % (cname, c["trees"][at[0]]["name"], name), "resolver cannot render it (%s); write the text by hand" % e))
            # a rank value with no curve behind it is a guess: the game shows some as base x rank, some as the
            # base at every rank, some as base x rank / ranks (Moonglow's -25 reads 8% at rank 1 of 3)
            pts = new.def_points.get(new.talent_def(sp)) or {}
            loose = sorted(i + 1 for i in new.eff.get(sp, {}) if i not in pts and re.search(r"\$[smMSo]%d" % (i + 1), new.spell.get(sp, {}).get("Description_lang", "")))
            if r > 1 and loose:
                log.append(("text~", "%s / %s / %s" % (cname, c["trees"][at[0]]["name"], name),
                            "effect %s has no rank curve: check the rank values against Blizzard's notes" % ", ".join(map(str, loose))))
            mn = new.misc.get(sp) or {}
            t = {"n": name, "r": r, "row": at[1], "col": at[2],
                 "icon": icons.get(mn.get("SpellIconFileDataID", ""), "inv_misc_questionmark"),
                 "desc": desc, "sp": int(sp), "c": {"s": "new"}, "added": new_b}
            appended.append((at[0], t, n, True))
            log.append(("new", "%s / %s / %s" % (cname, c["trees"][at[0]]["name"], name),
                        "row %d col %d, %d rank%s" % (at[1], at[2], r, "" if r == 1 else "s")))
        for ti, t, n, _ in appended:
            c["trees"][ti]["talents"].append(t)
        # prerequisites once every talent is in place: changed edges, and all appended talents
        for ti, t, n, always in edges + appended:
            tr = c["trees"][ti]
            live = {str(x.get("sp")): x["n"] for x in tr["talents"] if not x.get("gone")}
            names = sorted(live[s] for s in tn.parent_spells(n) if s in live)
            before = t.get("req")
            if len(names) > 1:
                log.append(("req?", "%s / %s / %s" % (cname, tr["name"], t["n"]), "several prerequisites now: %s" % names))
                continue
            if names:
                t["req"] = names[0]
            else:
                t.pop("req", None)
            if before != t.get("req"):
                log.append(("req", "%s / %s / %s" % (cname, tr["name"], t["n"]), "%s -> %s" % (before, t.get("req"))))
    if write:
        p["source"] = re.sub(r"1\.60\.1\.\d+", new_b, p.get("source", "")) if isinstance(p.get("source"), str) else p.get("source")
        with open(PLAN, "w") as f:
            json.dump(p, f, ensure_ascii=False, separators=(",", ":"))
    return log


if __name__ == "__main__":
    o, n = sys.argv[1], sys.argv[2]
    log = run(o, n, "--write" in sys.argv)
    for kind, tag, msg in log:
        print("%-7s %-52s %s" % (kind, tag[:52], msg))
    print("%d changes%s" % (len(log), " written" if "--write" in sys.argv else " (dry run)"))
