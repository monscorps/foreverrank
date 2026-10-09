#!/usr/bin/env python3
"""Carry the class spellbooks' tooltips (plan/plan-data.json, each class's "book") to a new build.

  python3 tools/apply_spellbook.py 1.60.1.70009 1.60.1.70291          # dry run
  python3 tools/apply_spellbook.py 1.60.1.70009 1.60.1.70291 --write  # update plan/plan-data.json
  python3 tools/build_spellbook.py                                     # then rebuild codex/spellbook.json

The books in plan-data.json are the source: the Forge's spellbook reads them and
tools/build_spellbook.py builds the Database's codex/spellbook.json from them, so a
change written here reaches both. Book entries carry no spell id, so an entry is
tied to the spell whose OLD text reproduces the site text exactly (name first, then
text). Those get the new build's text as the game prints it, damage ranges and all
(book.desc), and book.bld[name] = the build.
Entries the resolver cannot reproduce (level-scaled damage, ranges) are left alone;
if any same-named spell of the class changed data between the builds, the entry
gains book.chg[name], a one-line note saying so instead of a guess. A hand-written
chg note (what actually changed) replaces that flag after a look at the data, and a
re-run never overwrites one: it only reports it. Entries already carried to the new
build (book.bld[name] == NEW, by this tool, by hand or by tools/build_pets.py) are
left alone, and an old build's flag on them is dropped, since their numbers are NEW's.
book.chk[name] = NEW records a flag looked at by hand and found not to touch the text
shown (a targeting change, an NPC copy's punctuation), so a re-run does not raise it again.

  python3 tools/apply_spellbook.py --classic 1.60.1.70291 1.15.9.70003          # dry run
  python3 tools/apply_spellbook.py --classic 1.60.1.70291 1.15.9.70003 --write

--classic compares book entries with Classic at the same rank: the Forever spell id
whose text is the one shown, rendered in the Classic Era client (fetch its tables with
tools/fetch_wago.py 1.15.9.70003 --classic). It touches entries whose verdict is
"unverified" and the ones an earlier --classic run wrote (book.cmp[name].cb); the
older Wowhead comparisons, made against Classic's rank at level 38, stay as they are.
"""
import collections, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spelltext import Client, _rows
from verify_spelltext import norm
from diff_builds import diff

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAN = os.path.join(ROOT, "plan", "plan-data.json")
TABLES = ("SpellEffect", "SpellMisc", "SpellCooldowns", "SpellPower", "SpellAuraOptions", "Spell")
# the flag this tool writes; anything else in book.chg is a hand-written note
GENERIC = re.compile(r"^Beta build [\d.]+ changed this spell's data; the numbers shown are from the previous build\.$")
FAMILY = {"MAGE": "3", "WARRIOR": "4", "WARLOCK": "5", "PRIEST": "6", "DRUID": "7", "ROGUE": "8", "HUNTER": "9", "PALADIN": "10", "SHAMAN": "11"}


def changed_spells(o, n):
    out = set()
    for t in TABLES:
        d = diff(o, n, t)
        new_rows = {r["ID"]: r for r in _rows(n, t)} if t != "Spell" else {}
        for ch in d["changed"]:
            cols = [c for c in ch["cols"] if c != "EffectBonusCoefficient" and not c.startswith("Attributes")]
            if not cols:
                continue
            if t == "Spell":
                out.add(ch["id"])
            elif ch["id"] in new_rows:
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
    p = json.load(open(PLAN))
    flag = "Beta build %s changed this spell's data; the numbers shown are from the previous build." % n
    log = []
    for c in p["classes"]:
        bk = c.get("book") or {}
        cname = c["cls"].capitalize()
        for name, d in sorted((bk.get("desc") or {}).items()):
            if not d:
                continue
            chg = (bk.get("chg") or {}).get(name)
            if (bk.get("bld") or {}).get(name) == n:
                if chg and GENERIC.match(chg):
                    del bk["chg"][name]
                    log.append(("note", cname, name, "flag dropped: the text shown is already %s's" % n))
                continue
            ids = by_name.get(name, [])
            match = None
            for sid in ids:
                try:
                    # the site shows the game's ranges ("151 to 175"); older texts showed the middle ("163")
                    if norm(d) in (norm(old.game_text(sid)), norm(old.text(sid))):
                        match = sid
                        break
                except Exception:
                    pass
            if match:
                try:
                    fresh = new.game_text(match)
                except Exception as e:
                    log.append(("error", cname, name, str(e)))
                    continue
                if fresh and norm(fresh) != norm(d):
                    log.append(("text", cname, name, norm(d)[:80] + "  ->  " + norm(fresh)[:80]))
                    bk["desc"][name] = fresh
                    bk.setdefault("bld", {})[name] = n
                if chg and GENERIC.match(chg):
                    # the text shown now reproduces in the new build, so an older build's flag no longer holds
                    del bk["chg"][name]
                    log.append(("note", cname, name, "flag dropped: the text reproduces in %s" % n))
                continue
            hit = [sid for sid in ids if sid in moved and fam.get(sid) == FAMILY.get(c["cls"])]
            if hit and (bk.get("chk") or {}).get(name) == n:
                continue  # looked at by hand: the change does not touch the text shown (book.chk)
            if hit and chg and not GENERIC.match(chg):
                log.append(("check", cname, name, "hand-written note kept; %d rank%s changed data: %s" % (len(hit), "" if len(hit) == 1 else "s", chg[:60])))
            elif hit and chg != flag:
                bk.setdefault("chg", {})[name] = flag
                log.append(("note", cname, name, "flagged (%d changed rank%s)" % (len(hit), "" if len(hit) == 1 else "s")))
    if write:
        with open(PLAN, "w") as f:
            json.dump(p, f, ensure_ascii=False, separators=(",", ":"))
    return log


NOT_TIED = ("Not compared with Classic: the text shown is not one rank's text in the client "
            "(its numbers depend on level, or some are missing).")
NO_TWIN = "Not compared with Classic: Forever uses a spell of its own here, with no Classic spell of the same id."


def classic(f, cb, write=False):
    """Verdicts against Classic at the same rank (see the docstring)."""
    F, C = Client(f), Client(cb)
    clvl = {r["SpellID"]: int(r["SpellLevel"] or 0) for r in _rows(cb, "SpellLevels") if r.get("DifficultyID", "0") in ("0", "")}
    by_name = collections.defaultdict(list)
    for sid, nm in F.name.items():
        by_name[nm].append(sid)
    # Classic name -> the level its first rank is learned at: ranks on a skill line only, since NPC and item copies
    # carry "Rank 1" too (an NPC's Pummel at 6)
    taught = {r["Spell"] for r in _rows(cb, "SkillLineAbility")}
    first = {}
    for sid, nm in C.name.items():
        if sid in taught and (C.spell.get(sid) or {}).get("NameSubtext_lang", "").startswith("Rank") and clvl.get(sid):
            first[nm] = min(first.get(nm, 99), clvl[sid])

    def say(cl, sid, ranged):
        try:
            return cl.resolve((cl.spell.get(sid) or {}).get("Description_lang", ""), sid, {"ranges": True} if ranged else {})
        except Exception:
            return None

    p = json.load(open(PLAN))
    log = []
    for c in p["classes"]:
        bk = c.get("book") or {}
        cname = c["cls"].capitalize()
        for name, e in sorted((bk.get("cmp") or {}).items()):
            if e.get("s") != "unverified" and not e.get("cb"):
                continue
            d = (bk.get("desc") or {}).get(name)
            ids = [sid for sid in by_name.get(name, []) if d and norm(d) in (norm(say(F, sid, True)), norm(say(F, sid, False)))]
            # the same spell id in Classic: the one under the Classic name first, else any with a tooltip
            sid = next((x for x in ids if C.name.get(x) == (e.get("cn") or name)), None) or \
                next((x for x in ids if (C.spell.get(x) or {}).get("Description_lang")), None)
            fr, ct = (say(F, sid, True), say(C, sid, True)) if sid else (None, None)
            if ids and not sid and e.get("cb") and e.get("s") != "unverified":
                continue  # no twin to compare with, so this verdict was set by hand: it stays
            if not (fr and ct):
                new = dict(e, s="unverified", note=NO_TWIN if ids and not sid else NOT_TIED)
                new.pop("cb", None)
            else:
                rk = (C.spell.get(sid) or {}).get("NameSubtext_lang") or ""
                rk = rk if rk.startswith("Rank") else ""
                same = norm(fr).lower() == norm(ct).lower()   # capitals only ("aquatic form") count as the same
                new = {k: v for k, v in e.items() if k not in ("hd", "cl", "crl", "rk")}
                new.update(s="same" if same else "changed", ct=ct, cb=cb, cr=rk)
                if not rk:
                    new.pop("cr")
                # cl: where Classic starts teaching the spell (the Database says so), left out when Classic splits it
                # into differently named spells (Create Firestone (Lesser) ... (Major)); crl: the rank compared
                if first.get(name):
                    new["cl"] = first[name]
                elif not rk and C.name.get(sid) == name and clvl.get(sid):
                    new["cl"] = clvl[sid]
                if rk and clvl.get(sid):
                    new["crl"] = clvl[sid]
                if new.get("u"):
                    new["u"] = "https://www.wowhead.com/classic/spell=" + sid   # the rank compared
                cn = C.name.get(sid)
                if cn and cn != name:
                    new["cn"] = cn
                new["note"] = ("Same text as Classic%s." if same else "Compared with Classic%s, the same rank.") % (" " + rk if rk else "")
            if new != e:
                log.append(("cmp", cname, name, "%s -> %s%s" % (e.get("s"), new["s"], " (" + new["cr"] + ")" if new.get("cr") else "")))
                bk["cmp"][name] = new
    if write:
        with open(PLAN, "w") as fh:
            json.dump(p, fh, ensure_ascii=False, separators=(",", ":"))
    return log


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    write = "--write" in sys.argv
    log = (classic if "--classic" in sys.argv else run)(args[0], args[1], write)
    for kind, cname, name, msg in log:
        print("%-5s %-8s %-26s %s" % (kind, cname, name[:26], msg))
    n = sum(1 for x in log if x[0] != "check")
    print("%d changes%s" % (n, " written to plan/plan-data.json; run tools/build_spellbook.py next" if write else " (dry run)") +
          ("; %d hand-written notes to check" % (len(log) - n) if len(log) > n else ""))
