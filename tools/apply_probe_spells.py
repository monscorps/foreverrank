#!/usr/bin/env python3
"""Mark the site's spellbook entries that players' games have shown learned.

  python3 tools/apply_probe_spells.py            # dry run: what would be marked
  python3 tools/apply_probe_spells.py --write    # write codex/spellbook.json

ForeverProbe's snapshots list the spell ids a character knows, with its class, race and level
(tools/probe_pull.py keeps that, without any name, under "probe" in research/questbank/disc.json).
An entry is matched by class (or race, for racials) and spell name through the client's SpellName
table, and gains "seen": the lowest level a character was seen with it. The entry's text and
level are not touched: a snapshot says a character had the spell by that level, not when it was
learned.
"""
import csv, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOOK = os.path.join(ROOT, "codex", "spellbook.json")
DISC = os.path.join(ROOT, "research", "questbank", "disc.json")
WAGO = os.path.join(ROOT, "research", "wago")


def latest_build():
    builds = [b for b in os.listdir(WAGO) if b.startswith("1.") and os.path.exists(os.path.join(WAGO, b, "SpellName.csv"))]
    return max(builds, key=lambda b: [int(x) for x in b.split(".")])


def main():
    write = "--write" in sys.argv
    probe = (json.load(open(DISC)).get("probe") or {}) if os.path.exists(DISC) else {}
    if not probe.get("spells"):
        sys.exit("no ForeverProbe snapshots merged yet: run tools/probe_pull.py first")
    names = {}
    for r in csv.DictReader(open(os.path.join(WAGO, latest_build(), "SpellName.csv"), encoding="utf-8")):
        names[r["ID"]] = r["Name_lang"]
    by_class = {}
    for cls, ids in probe["spells"].items():
        for sid, lvl in ids.items():
            n = names.get(str(sid))
            if n:
                k = (cls.lower(), n)
                by_class[k] = min(by_class.get(k, 99), int(lvl))
    by_race = {}
    for race, ids in (probe.get("racials") or {}).items():
        for sid in ids:
            n = names.get(str(sid))
            if n:
                by_race[(race.lower(), n)] = True
    book = json.load(open(BOOK))
    marked, changed = [], 0
    for kind, rows, key in (("spell", book.get("spells") or [], "c"), ("talent", book.get("talents") or [], "c")):
        for e in rows:
            lvl = by_class.get((str(e.get(key) or "").lower(), e.get("n")))
            if lvl and e.get("seen") != lvl:
                e["seen"] = lvl
                changed += 1
                marked.append("%s %s: %s (%s%s)" % (kind, e.get(key), e["n"], e.get("src") or "", "/" + e["s"] if e.get("s") else ""))
    for e in book.get("racials") or []:
        if by_race.get((str(e.get("race") or "").lower(), e.get("n"))) and not e.get("seen"):
            e["seen"] = 1
            changed += 1
            marked.append("racial %s: %s" % (e.get("race"), e["n"]))
    note = " Entries marked seen: a character in players' ForeverProbe snapshots had the spell by that level."
    if changed and note.strip() not in (book.get("note") or ""):
        book["note"] = (book.get("note") or "") + note
    for line in marked:
        print("  " + line)
    print("%d entries %s" % (changed, "marked" if write else "would be marked (dry run; --write to save)"))
    if write and changed:
        with open(BOOK, "w", encoding="utf-8") as f:
            json.dump(book, f, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()
