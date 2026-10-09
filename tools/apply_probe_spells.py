#!/usr/bin/env python3
"""Mark the site's spellbook entries that players' games have shown learned, and add what trainers asked.

  python3 tools/apply_probe_spells.py            # dry run: what would be marked
  python3 tools/apply_probe_spells.py --write    # write codex/spellbook.json and the books in plan/plan-data.json

Run it after tools/build_spellbook.py, which builds codex/spellbook.json afresh from plan-data.json.

QuestBank (QuestBankDB.game, 3.6.0+) and, from older installs, ForeverProbe note the spell ids a
character knows, with its class, race and level (tools/probe_pull.py keeps that, without any
name, under "probe" in research/questbank/disc.json). An entry is matched by class (or race, for
racials) and spell name through the client's SpellName table, and gains "seen": the lowest level
a character was seen with it. The entry's text and level are not touched: a reading says a
character had the spell by that level, not when it was learned.

Trainer windows (ForeverProbe noted them; probe_pull.py keeps each service's rank, level and cost and tells class
trainers apart by the spellbooks) give an entry "train": [[rank, level, cost in copper], ...], the most-voted reading
of each rank. They go to codex/spellbook.json and to the class's book in plan/plan-data.json (book.train), where the
Forge reads them, and every rank is checked against the client's own learn level (SpellLevels): a disagreement is
printed, and the trainer's number is the one shown, since it is what the game asked. A price is what that character
paid, so a reputation discount may be in it: each class's readings are checked against the same trainer's Classic price
(CMaNGOS), and the class gets a sentence saying how they compare (book.trainPrice, and spellbook.json "trainPrice").
"""
import csv, gzip, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOOK = os.path.join(ROOT, "codex", "spellbook.json")
DISC = os.path.join(ROOT, "research", "questbank", "disc.json")
PLAN = os.path.join(ROOT, "plan", "plan-data.json")
TRAIN_NOTE = (" Entries with train: the level and cost of each rank as trainer windows in players' games showed them, which is"
              " what those characters paid; trainPrice says per class how that compares with the same trainer's Classic price.")
CLASSMASK = {"WARRIOR": 1, "PALADIN": 2, "HUNTER": 4, "ROGUE": 8, "PRIEST": 16, "SHAMAN": 64, "MAGE": 128, "WARLOCK": 256, "DRUID": 1024}
WAGO = os.path.join(ROOT, "research", "wago")
CMANGOS = os.path.join(ROOT, "research", "cmangos", "ClassicDB.sql.gz")
CLASSIC = "1.15.9.70003"   # the Classic Era client build the Classic spell names and ranks come from
PRICE = "Prices are what those characters paid; reputation discounts may apply."
NOTE = " Entries marked seen: a character in players' games had the spell by that level."
# UnitRace's second return, which the game notes, where the spellbook names the race otherwise. Skyborne is one race in
# game and two books here: a racial both books list goes to the books the race's own racials point at (see racial_books).
RACES = {"NightElf": ["Night Elf"], "Scourge": ["Undead"], "Skyborne": ["Skyborne (High Order)", "Skyborne (Windshaper)"]}


def latest_build():
    builds = [b for b in os.listdir(WAGO) if b.startswith("1.60.") and os.path.exists(os.path.join(WAGO, b, "SpellName.csv"))]
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


def top(votes):
    """The most-voted reading (ties: the lower number), or None."""
    if not votes:
        return None
    return int(sorted(votes.items(), key=lambda kv: (-kv[1], int(kv[0])))[0][0])


def trainer_book(probe):
    """{(CLASS, spell name): {rank: (level, cost)}} from the class trainers' windows; rank 0 is an unranked service.
    Votes add up across trainers (two Paladin trainers showing the same rank are two readings of it)."""
    votes = {}
    for rec in (probe.get("trainers") or {}).values():
        for sv in rec.get("s", {}).values():
            if not sv.get("cls"):
                continue
            m = re.match(r"Rank (\d+)$", sv.get("r") or "")
            v = votes.setdefault((sv["cls"], sv["n"]), {}).setdefault(int(m.group(1)) if m else 0, ({}, {}))
            for i, k in ((0, "lvl"), (1, "c")):
                for x, n in (sv.get(k) or {}).items():
                    v[i][x] = v[i].get(x, 0) + n
    out = {}
    for key, ranks in votes.items():
        for r, (lv, c) in ranks.items():
            if top(lv) is not None and top(c) is not None:
                out.setdefault(key, {})[r] = (top(lv), top(c))
    return out


def classic_prices():
    """{trainer name: {(spell name, rank text): price in copper}}: what each class trainer charged in Classic, from the
    CMaNGOS Classic database (research/cmangos, GPL-3.0; creature_template's trainer template plus the trainer's own
    npc_trainer rows), with spell names and ranks from the Classic Era client (tools/fetch_wago.py 1.15.9.70003 --classic)."""
    era = os.path.join(WAGO, CLASSIC)
    if not (os.path.exists(CMANGOS) and os.path.exists(os.path.join(era, "Spell.csv"))):
        return {}
    names = {r["ID"]: r["Name_lang"] for r in csv.DictReader(open(os.path.join(era, "SpellName.csv"), encoding="utf-8"))}
    sub = {r["ID"]: r.get("NameSubtext_lang") or "" for r in csv.DictReader(open(os.path.join(era, "Spell.csv"), encoding="utf-8"))}
    sys.path.insert(0, os.path.join(ROOT, "tools", "questbank"))
    from cmangos import rows_of
    want = ("creature_template", "npc_trainer", "npc_trainer_template")
    cols, data, table = {}, {t: [] for t in want}, None
    with gzip.open(CMANGOS, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("CREATE TABLE `"):
                table = line.split("`")[1]
                cols[table] = []
            elif table and line.startswith("  `"):
                cols[table].append(line.split("`")[1].lower())
            elif line.startswith("INSERT INTO `") and line.split("`")[1] in want:
                t = line.split("`")[1]
                data[t] += [dict(zip(cols[t], r)) for r in rows_of(line[line.index("VALUES") + 6:].strip().rstrip(";"))]
    lists = {}
    for t in ("npc_trainer", "npc_trainer_template"):
        for r in data[t]:
            sid = str(r["spell"])
            if sid in names:
                lists.setdefault((t, r["entry"]), {})[(names[sid], sub.get(sid, ""))] = r["spellcost"]
    out = {}
    for c in data["creature_template"]:
        if not c.get("trainerclass") or c.get("trainertype"):
            continue  # class trainers only (type 0 with a class)
        got = out.setdefault(c["name"], {})
        for key in (("npc_trainer_template", c.get("trainertemplateid")), ("npc_trainer", c.get("entry"))):
            got.update(lists.get(key) or {})
    return out


def price_check(probe, prices):
    """{CLASS: {"full" / "tenth_off" / "other": readings}}: each class service a trainer showed against the same trainer's
    Classic price for the same spell and rank."""
    out = {}
    for rec in (probe.get("trainers") or {}).values():
        cp = prices.get(rec.get("npc")) or {}
        for sv in rec.get("s", {}).values():
            was = cp.get((sv.get("n"), sv.get("r") or ""))
            cost = top(sv.get("c"))
            if not sv.get("cls") or not was or cost is None:
                continue
            k = "full" if cost == was else "tenth_off" if abs(cost - 0.9 * was) < 1 else "other"
            tally = out.setdefault(sv["cls"], {})
            tally[k] = tally.get(k, 0) + 1
    return out


def price_note(tally):
    """The sentence a class's trainer prices get: a clear majority decides (spells Classic taught as talent ranks, or
    that Forever moved to the trainer, have prices of their own and make up the rest); PRICE when nothing is clear."""
    n = sum(tally.values())
    if n < 10:
        return PRICE
    if tally.get("tenth_off", 0) >= 0.75 * n:
        return ("Prices are what those characters paid. %d of %d readings are exactly 10%% under the same trainer's "
                "Classic price for that spell (CMaNGOS): those characters may have had a 10%% discount (Honored "
                "reputation gives one), or Forever lowered the prices." % (tally["tenth_off"], n))
    if tally.get("full", 0) >= 0.75 * n:
        return ("Prices are what those characters paid; %d of %d readings match the same trainer's Classic price for that "
                "spell (CMaNGOS)." % (tally["full"], n))
    return PRICE


def client_levels(build):
    """{(CLASS, spell name, rank): learn level} from the client: SpellLevels of the spells on the class's skill lines.
    A row with no ClassMask of its own takes its skill line's (SkillRaceClassInfo): talent spells such as Holy Shock
    sit on the class's line that way."""
    rows = lambda t: csv.DictReader(open(os.path.join(WAGO, build, t + ".csv"), encoding="utf-8"))
    names = {r["ID"]: r["Name_lang"] for r in rows("SpellName")}
    sub = {r["ID"]: r.get("NameSubtext_lang") or "" for r in rows("Spell")}
    lv = {r["SpellID"]: int(r["BaseLevel"] or 0) for r in rows("SpellLevels") if r.get("DifficultyID", "0") in ("0", "")}
    line_cls = {}
    if os.path.exists(os.path.join(WAGO, build, "SkillRaceClassInfo.csv")):
        for r in rows("SkillRaceClassInfo"):
            m = int(r.get("ClassMask") or 0)
            if m > 0:
                line_cls[r["SkillID"]] = line_cls.get(r["SkillID"], 0) | m
    out = {}
    for r in rows("SkillLineAbility"):
        cm, sid = int(r.get("ClassMask") or 0) or line_cls.get(r["SkillLine"], 0), r["Spell"]
        m = re.match(r"Rank (\d+)$", sub.get(sid, ""))
        if not cm or sid not in names or r.get("AcquireMethod") == "3":
            continue
        for cls, bit in CLASSMASK.items():
            if cm & bit and lv.get(sid):
                key = (cls, names[sid], int(m.group(1)) if m else 0)
                out[key] = min(out.get(key, 99), lv[sid])
    return out


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
    # what trainers asked, rank by rank; checked against the client's learn levels
    trained = trainer_book(probe)
    plan = json.load(open(PLAN)) if os.path.exists(PLAN) else {"classes": []}
    books = {c["cls"].upper(): c.setdefault("book", {}) for c in plan.get("classes") or []}
    client = client_levels(latest_build())
    disagree, unknown, compared, given, plan_changed = [], [], 0, 0, False
    for (cls, n), ranks in sorted(trained.items()):
        rows = [[r, lvl, cost] for r, (lvl, cost) in sorted(ranks.items())]
        for r, lvl, cost in rows:
            want = client.get((cls, n, r))
            if want is None:
                unknown.append("%s %s%s" % (cls.capitalize(), n, " rank %d" % r if r else ""))
                continue
            compared += 1
            if want != lvl:
                disagree.append("%s %s%s: trainer level %d, client %d" % (cls.capitalize(), n, " rank %d" % r if r else "", lvl, want))
        bk = books.get(cls)
        if bk is not None and (n in (bk.get("desc") or {}) or n in (bk.get("hdr") or {})) and (bk.get("train") or {}).get(n) != rows:
            bk.setdefault("train", {})[n] = rows
            plan_changed = True
        for e in book.get("spells") or []:
            if str(e.get("c") or "").upper() == cls and e.get("n") == n and e.get("train") != rows:
                e["train"] = rows
                given += 1
    # what the prices are: the same trainers' Classic prices say whether those characters paid full price
    tallies = price_check(probe, classic_prices())
    for cls, tally in sorted(tallies.items()):
        print("prices, %s: %s against the same trainers' Classic prices" % (
            cls.capitalize(), ", ".join("%d %s" % (v, k.replace("_", " ")) for k, v in sorted(tally.items()))))
    prices = {cls.capitalize(): price_note(tallies.get(cls, {})) for cls in sorted({c for c, _ in trained})}
    for cls, bk in books.items():
        if bk.get("trainPrice") != prices.get(cls.capitalize()):
            bk.pop("trainPrice", None)
            if prices.get(cls.capitalize()):
                bk["trainPrice"] = prices[cls.capitalize()]
            plan_changed = True
    priced = book.get("trainPrice") != (prices or None)
    book.pop("trainPrice", None)
    if prices:
        book["trainPrice"] = prices
    # the note says what "seen" and "train" mean once any entry has them; an earlier wording goes first, so it is never doubled
    note = re.sub(r"\s*Entries (marked seen|with train)[^.]*\.", "", book.get("note") or "")
    if any(e.get("seen") for k in ("spells", "talents", "racials") for e in book.get(k) or []):
        note += NOTE
    if any(e.get("train") for e in book.get("spells") or []):
        note += TRAIN_NOTE
    reworded = note != (book.get("note") or "")
    book["note"] = note
    for line in marked:
        print("  " + line)
    print("%d entries %s%s" % (changed, "marked" if write else "would be marked (dry run; --write to save)",
                               "; the note is reworded" if reworded else ""))
    print("trainer windows: %d ranks of %d spells, class(es) %s; %d spellbook entries %s" % (
        sum(len(v) for v in trained.values()), len(trained), ", ".join(sorted({c.capitalize() for c, _ in trained})) or "none",
        given, "given their ranks" if write else "would get their ranks"))
    for line in disagree:
        print("  level differs: " + line)
    print("%d of %d ranks compared with the client's learn level (SpellLevels): %d differ; %d have no level in the client%s" % (
        compared, compared + len(unknown), len(disagree), len(unknown), " (" + ", ".join(unknown) + ")" if unknown else ""))
    if write and (changed or reworded or given or priced):
        with open(BOOK, "w", encoding="utf-8") as f:
            json.dump(book, f, ensure_ascii=False, separators=(",", ":"))
    if write and plan_changed:
        with open(PLAN, "w", encoding="utf-8") as f:
            json.dump(plan, f, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()
