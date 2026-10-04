#!/usr/bin/env python3
"""Mark the site's spellbook entries that players' games have shown learned.

  python3 tools/apply_probe_spells.py            # dry run: what would be marked
  python3 tools/apply_probe_spells.py --write    # write codex/spellbook.json

QuestBank (QuestBankDB.game, 3.6.0+) and, from older installs, ForeverProbe note the spell ids a
character knows, with its class, race and level (tools/probe_pull.py keeps that, without any
name, under "probe" in research/questbank/disc.json). An entry is matched by class (or race, for
racials) and spell name through the client's SpellName table, and gains "seen": the lowest level
a character was seen with it. The entry's text and level are not touched: a reading says a
character had the spell by that level, not when it was learned.
"""
import csv, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOOK = os.path.join(ROOT, "codex", "spellbook.json")
DISC = os.path.join(ROOT, "research", "questbank", "disc.json")
WAGO = os.path.join(ROOT, "research", "wago")
NOTE = " Entries marked seen: a character in players' games had the spell by that level."
# UnitRace's second return, which the game notes, where the spellbook names the race otherwise. Skyborne is one race in
# game and two books here: a racial both books list goes to the books the race's own racials point at (see racial_books).
RACES = {"NightElf": ["Night Elf"], "Scourge": ["Undead"], "Skyborne": ["Skyborne (High Order)", "Skyborne (Windshaper)"]}


def latest_build():
    builds = [b for b in os.listdir(WAGO) if b.startswith("1.") and os.path.exists(os.path.join(WAGO, b, "SpellName.csv"))]
    return max(builds, key=lambda b: [int(x) for x in b.split(".")])


def racial_books(token, seen, racials):
    """The spellbook races a race token stands for. When it stands for several (Skyborne), keep those whose own racials,
    the ones the others lack, were seen; when none can be told apart that way, all of them."""
    books = RACES.get(token) or [r for r in {e.get("race") for e in racials}
                                 if r and re.sub(r"\s+|\(.*?\)", "", r).lower() == token.lower()]
    if len(books) < 2:
        return books
    names = {b: {e.get("n") for e in racials if e.get("race") == b} for b in books}
    told = [b for b in books if (names[b] - set().union(*(names[o] for o in books if o != b))) & seen]
    return told or books


def main():
    write = "--write" in sys.argv
    probe = (json.load(open(DISC)).get("probe") or {}) if os.path.exists(DISC) else {}
    if not probe.get("spells"):
        sys.exit("no spells from players' games merged yet: run tools/probe_pull.py first")
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
    book = json.load(open(BOOK))
    by_race = {}
    for race, ids in (probe.get("racials") or {}).items():
        seen = {names[str(sid)] for sid in ids if names.get(str(sid))}
        for r in racial_books(race, seen, book.get("racials") or []):
            for n in seen:
                by_race[(r.lower(), n)] = True
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
    # the note says what "seen" means once any entry has it; an earlier wording of it goes first, so it is never doubled
    note = re.sub(r"\s*Entries marked seen[^.]*\.", "", book.get("note") or "")
    if any(e.get("seen") for k in ("spells", "talents", "racials") for e in book.get(k) or []):
        note += NOTE
    reworded = note != (book.get("note") or "")
    book["note"] = note
    for line in marked:
        print("  " + line)
    print("%d entries %s%s" % (changed, "marked" if write else "would be marked (dry run; --write to save)",
                               "; the note is reworded" if reworded else ""))
    if write and (changed or reworded):
        with open(BOOK, "w", encoding="utf-8") as f:
            json.dump(book, f, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()
