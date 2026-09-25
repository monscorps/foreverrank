#!/usr/bin/env python3
"""Carry spellbook tooltips (codex/spellbook.json "spells") to a new build.

  python3 tools/apply_spellbook.py 1.60.1.69876 1.60.1.70009          # dry run
  python3 tools/apply_spellbook.py 1.60.1.69876 1.60.1.70009 --write

Entries carry no spell id, so an entry is tied to the spell whose OLD text
reproduces the site text exactly (name first, then text). Those get the new
build's text. Entries the resolver cannot reproduce (level-scaled damage,
ranges) are left alone; if any same-named class spell changed data between
the builds, the entry gains a one-line note saying so, instead of a guess.
"""
import collections, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spelltext import Client, _rows
from verify_spelltext import norm
from diff_builds import diff

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOOK = os.path.join(ROOT, "codex", "spellbook.json")
TABLES = ("SpellEffect", "SpellMisc", "SpellCooldowns", "SpellPower", "SpellAuraOptions", "Spell")
FAMILY = {"Mage": "3", "Warrior": "4", "Warlock": "5", "Priest": "6", "Druid": "7", "Rogue": "8", "Hunter": "9", "Paladin": "10", "Shaman": "11"}


def changed_spells(o, n):
    out = set()
    for t in TABLES:
        d = diff(o, n, t)
        rows = {}
        for part in ("changed",):
            for ch in d[part]:
                cols = [c for c in ch["cols"] if c != "EffectBonusCoefficient" and not c.startswith("Attributes")]
                if cols:
                    out.add(ch["id"] if t == "Spell" else None)
        if t != "Spell":
            new_rows = {r["ID"]: r for r in _rows(n, t)}
            for ch in d["changed"]:
                cols = [c for c in ch["cols"] if c != "EffectBonusCoefficient" and not c.startswith("Attributes")]
                if cols and ch["id"] in new_rows:
                    out.add(new_rows[ch["id"]].get("SpellID"))
    out.discard(None)
    return out


def run(o, n, write=False):
    old, new = Client(o), Client(n)
    fam = {r["SpellID"]: r["SpellClassSet"] for r in _rows(n, "SpellClassOptions")}
    by_name = collections.defaultdict(list)
    for sid, nm in old.name.items():
        by_name[nm].append(sid)
    moved = changed_spells(o, n)
    b = json.load(open(BOOK))
    log = []
    for s in b["spells"]:
        if not s.get("d"):
            continue
        ids = by_name.get(s["n"], [])
        match = None
        for sid in ids:
            try:
                if norm(old.text(sid)) == norm(s["d"]):
                    match = sid
                    break
            except Exception:
                pass
        if match:
            try:
                fresh = new.text(match)
            except Exception as e:
                log.append(("error", s, str(e)))
                continue
            if norm(fresh) != norm(s["d"]) and fresh:
                log.append(("text", s, norm(s["d"])[:80] + "  ->  " + norm(fresh)[:80]))
                s["d"] = fresh
                s["b"] = n
            continue
        fam_id = FAMILY.get(s["c"])
        hit = [sid for sid in ids if sid in moved and fam.get(sid) == fam_id]
        if hit:
            note = "Beta build %s changed this spell's data; the numbers shown are from the previous build." % n
            if note not in (s.get("note") or ""):
                s["note"] = (s["note"] + ". " if s.get("note") else "") + note
                log.append(("note", s, "flagged (%d changed rank%s)" % (len(hit), "" if len(hit) == 1 else "s")))
    if write:
        with open(BOOK, "w") as f:
            json.dump(b, f, ensure_ascii=False, separators=(",", ":"))
    return log


if __name__ == "__main__":
    log = run(sys.argv[1], sys.argv[2], "--write" in sys.argv)
    for kind, s, msg in log:
        print("%-5s %-8s %-26s %s" % (kind, s["c"], s["n"][:26], msg))
    print("%d changes%s" % (len(log), " written" if "--write" in sys.argv else " (dry run)"))
