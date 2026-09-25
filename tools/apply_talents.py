#!/usr/bin/env python3
"""Carry the Forge talents (plan/plan-data.json) from one beta build to the next.

  python3 tools/apply_talents.py 1.60.1.69876 1.60.1.70009          # dry run: report
  python3 tools/apply_talents.py 1.60.1.69876 1.60.1.70009 --write  # update the file

What moves, and the rule for each:
  text     rank texts are rewritten only for talents whose text the resolver
           reproduces exactly from OLD; everything else is reported, untouched
  rename   the talent takes its spell's new name when the old name matched;
           prerequisites that pointed at the old name follow
  icon     follows SpellMisc's icon file when the old icon matched the site's
  gone     a talent whose tree node vanished gets gone=<build>: it keeps its
           slot so shared build links (?b=, positional) still decode, but it
           takes no points and renders struck out
  row/req  follow TraitNode PosY (600 per row) and TraitEdge prerequisites
"""
import csv, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spelltext import Client, _rows
from verify_spelltext import norm

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAN = os.path.join(ROOT, "plan", "plan-data.json")


class Tree:
    """Node positions, edges and which node carries which talent spell."""
    def __init__(self, build):
        nodes = _rows(build, "TraitNode")
        self.pos = {r["ID"]: (int(r["PosX"]), int(r["PosY"])) for r in nodes}
        tree_of = {r["ID"]: r["TraitTreeID"] for r in nodes}
        size = {}
        for t in tree_of.values():
            size[t] = size.get(t, 0) + 1
        defs = {r["ID"]: r["SpellID"] for r in _rows(build, "TraitDefinition")}
        entry_def = {r["ID"]: r["TraitDefinitionID"] for r in _rows(build, "TraitNodeEntry")}
        # a spell can sit in a stub tree and in the real class tree (Elemental
        # Fury: 16-node 1081 and 50-node 1082); the real one is the big one
        self.node_of = {}
        for r in _rows(build, "TraitNodeXTraitNodeEntry"):
            sp = defs.get(entry_def.get(r["TraitNodeEntryID"], ""), "")
            n = r["TraitNodeID"]
            if not sp or n not in self.pos:
                continue
            cur = self.node_of.get(sp)
            if cur is None or (size[tree_of[n]], tree_of[n]) > (size[tree_of[cur]], tree_of[cur]):
                self.node_of[sp] = n
        self.parents = {}
        for r in _rows(build, "TraitEdge"):
            self.parents.setdefault(r["RightTraitNodeID"], set()).add(r["LeftTraitNodeID"])


def icon_names(build):
    out = {}
    for r in _rows(build, "ManifestInterfaceData"):
        if r.get("FilePath", "").replace("\\", "/").lower().startswith("interface/icons/"):
            out[r["ID"]] = os.path.splitext(r["FileName"])[0].lower()
    return out


def run(old_b, new_b, write=False):
    p = json.load(open(PLAN))
    old, new = Client(old_b), Client(new_b)
    to, tn = Tree(old_b), Tree(new_b)
    icons = icon_names(new_b)
    log = []
    for c in p["classes"]:
        cname = c["cls"] if isinstance(c.get("cls"), str) else (c.get("cls") or {}).get("name", "?")
        for tr in c["trees"]:
            by_sp = {str(t.get("sp")): t for t in tr["talents"]}
            for t in tr["talents"]:
                sp = str(t.get("sp") or "")
                if not sp:
                    continue
                tag = "%s / %s / %s" % (cname, tr.get("name"), t["n"])
                # gone
                if sp in to.node_of and sp not in tn.node_of and not t.get("gone"):
                    t["gone"] = new_b
                    log.append(("gone", tag, "node %s removed from the tree" % to.node_of[sp]))
                    continue
                # text
                maxr = t.get("r", 1)
                descs = t.get("desc") or []
                try:
                    exact = all(norm(old.talent_text(sp, r, maxr)) == norm(d) for r, d in enumerate(descs, 1) if d)
                except Exception:
                    exact = False
                if exact and descs:
                    fresh = []
                    for r, d in enumerate(descs, 1):
                        fresh.append(new.talent_text(sp, r, maxr) if d else d)
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
                    t["n"] = nn
                # icon
                mo, mn = old.misc.get(sp), new.misc.get(sp)
                if mo and mn and mo["SpellIconFileDataID"] != mn["SpellIconFileDataID"]:
                    was, now = icons.get(mo["SpellIconFileDataID"]), icons.get(mn["SpellIconFileDataID"])
                    if now and t.get("icon") == was:
                        log.append(("icon", tag, "%s -> %s" % (was, now)))
                        t["icon"] = now
                # row / req
                no, nw = to.node_of.get(sp), tn.node_of.get(sp)
                if no and nw and no in to.pos and nw in tn.pos:
                    dy = tn.pos[nw][1] - to.pos[no][1]
                    if dy and dy % 600 == 0:
                        log.append(("row", tag, "row %d -> %d" % (t["row"], t["row"] + dy // 600)))
                        t["row"] += dy // 600
                    po = {sp2 for sp2, n2 in to.node_of.items() if n2 in to.parents.get(no, set())}
                    pn = {sp2 for sp2, n2 in tn.node_of.items() if n2 in tn.parents.get(nw, set())}
                    if po != pn:
                        names = [by_sp[s]["n"] for s in pn if s in by_sp]
                        if len(names) <= 1:
                            before = t.get("req")
                            if names:
                                t["req"] = names[0]
                            else:
                                t.pop("req", None)
                            log.append(("req", tag, "%s -> %s" % (before, t.get("req"))))
                        else:
                            log.append(("req?", tag, "several prerequisites now: %s" % names))
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
