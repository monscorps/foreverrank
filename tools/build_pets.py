#!/usr/bin/env python3
"""Rebuild the Pets tabs of the Hunter and Warlock spellbooks (plan/plan-data.json) from one client build.

  python3 tools/build_pets.py 1.60.1.70291            # dry run: what would change
  python3 tools/build_pets.py 1.60.1.70291 --write    # update plan/plan-data.json
  python3 tools/build_spellbook.py                     # then rebuild codex/spellbook.json

Every pet family is a CreatureFamily row with its own skill line ("Pet - Wolf"); what all pets share sits on
"Pet - Generic". A family line that carries Hunter Pet Scaling is a hunter's beast, one with Warlock Pet Scaling a
demon. Each ability lists which families learn it ("Every pet" for the shared line), how many ranks it has, the pet
level of its first rank (SpellLevels), cast and cooldown, and the tooltip of its highest rank as tools/spelltext.py
renders it (game_text: damage ranges as the game prints them). Internal passives (scaling, DND auras, attack-speed steps) and the hunter talents that hang on the shared
line are left out. Needs the build's Spell*, SkillLine*, CreatureFamily and ManifestInterfaceData tables
(tools/fetch_wago.py BUILD).
"""
import collections, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spelltext import Client, _rows, fmt_duration
from apply_talents import icon_names
from apply_spellbook import GENERIC as BUILD_FLAG

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAN = os.path.join(ROOT, "plan", "plan-data.json")
GENERIC = "Pet - Generic"
SKIP = re.compile(r"\(DND\)|Scaling$|^Summoning$|^(Faster|Slower) Attack|^Pet (Aggression|Hardiness|Recovery|Resistance)$|"
                  r"^Intimidation$|Effect$|^Intercept Stun$")
NO_TEXT = "No tooltip text in the beta client yet."


def cast_row(c, sid, cd):
    m = c.misc.get(sid) or {}
    base = float((c.cast.get(m.get("CastingTimeIndex", "")) or {}).get("Base") or 0)
    cast = "Instant" if base <= 0 else fmt_duration(base) + " cast"
    if c.spell.get(sid, {}).get("Description_lang", "").lower().startswith("channel"):
        cast = "Channeled"
    r = cd.get(sid) or {}
    rec = max(float(r.get("RecoveryTime") or 0), float(r.get("CategoryRecoveryTime") or 0))
    return [cast, fmt_duration(rec) + " cooldown" if rec else ""]


def build(b):
    c = Client(b)
    lines = {r["ID"]: r["DisplayName_lang"] for r in _rows(b, "SkillLine")}
    by_line = collections.defaultdict(list)
    for r in _rows(b, "SkillLineAbility"):
        if lines.get(r["SkillLine"], "").startswith("Pet - "):
            by_line[r["SkillLine"]].append(r["Spell"])
    lv = {r["SpellID"]: int(r["BaseLevel"] or 0) for r in _rows(b, "SpellLevels") if r.get("DifficultyID", "0") in ("0", "")}
    cd = {r["SpellID"]: r for r in _rows(b, "SpellCooldowns") if r.get("DifficultyID", "0") in ("0", "")}
    icons = icon_names(b)
    # which line is whose: the families' own lines, sorted by the pet's owner
    owner, generic = {}, None
    for line, sids in by_line.items():
        names = {c.name.get(s) for s in sids}
        if lines[line] == GENERIC:
            generic = line
        elif "Hunter Pet Scaling" in names:
            owner[line] = "HUNTER"
        elif "Warlock Pet Scaling" in names:
            owner[line] = "WARLOCK"
    fams = {}
    for r in _rows(b, "CreatureFamily"):
        for col in ("SkillLine_0", "SkillLine_1"):
            if r.get(col) in owner:
                fams.setdefault(r[col], lines[r[col]][len("Pet - "):])
    out = {"HUNTER": {}, "WARLOCK": {}}
    for cls in out:
        abil = collections.defaultdict(lambda: {"fam": set(), "ids": set()})
        for line in [l for l, o in owner.items() if o == cls and l in fams] + ([generic] if generic else []):
            for sid in by_line[line]:
                n = c.name.get(sid)
                if not n or SKIP.search(n):
                    continue
                abil[n]["fam"].add("Every pet" if line == generic else fams[line])
                abil[n]["ids"].add(sid)
        for n, a in abil.items():
            ranks = {}
            for sid in a["ids"]:
                m = re.match(r"Rank (\d+)$", c.spell.get(sid, {}).get("NameSubtext_lang") or "")
                ranks.setdefault(int(m.group(1)) if m else 0, []).append(sid)
            top_rank = max(ranks)
            top = sorted(ranks[top_rank], key=lambda s: (-lv.get(s, 0), int(s)))[0]
            first = sorted(ranks[min(ranks)], key=lambda s: (lv.get(s, 0) or 99, int(s)))[0]
            passive = int((c.misc.get(top) or {}).get("Attributes_0") or 0) & 0x40
            hdr = [["Pets", "Every pet" if "Every pet" in a["fam"] else ", ".join(sorted(a["fam"]))]]
            if len([r for r in ranks if r]) > 1:
                hdr.append(["Ranks", str(len([r for r in ranks if r]))])
            if lv.get(first):
                hdr.append(["Pet level %d" % lv[first], ""])
            if not passive:
                hdr.append(cast_row(c, top, cd))
            try:
                d = c.game_text(top)   # damage ranges as the game prints them
            except Exception:
                d = None   # the resolver cannot render it: the old text stays (see write)
            icon = icons.get((c.misc.get(top) or {}).get("SpellIconFileDataID", ""))
            out[cls][n] = {"tag": "Passive" if passive else "", "icon": icon, "hdr": hdr, "d": d if d is None else (d or NO_TEXT),
                           "generic": "Every pet" in a["fam"]}
    return out


def run(b, write=False):
    p = json.load(open(PLAN))
    pets = build(b)
    log = []
    for cl in p["classes"]:
        if cl["cls"] not in pets:
            continue
        bk = cl["book"]
        tab = next((t for t in bk["tabs"] if t["name"] == "Pets"), None)
        if tab is None:
            tab = {"name": "Pets", "spells": []}
            bk["tabs"].append(tab)
        old = {s[0]: s for s in tab["spells"]}
        new = pets[cl["cls"]]
        for n in sorted(set(old) - set(new)):
            log.append(("gone", cl["cls"], n, "no longer on a pet line"))
            for k in ("desc", "hdr", "src", "bld"):
                (bk.get(k) or {}).pop(n, None)
        rows = []
        for n in sorted(new, key=lambda n: (not new[n]["generic"], n)):
            a = new[n]
            d = a["d"] if a["d"] is not None else (bk.get("desc") or {}).get(n) or NO_TEXT
            icon = a["icon"] or (old.get(n) or [None, None, None, None])[3]
            if n not in old:
                log.append(("new", cl["cls"], n, "%s: %s" % (a["hdr"][0][1], d[:80])))
            else:
                if bk["hdr"].get(n) != a["hdr"]:
                    log.append(("hdr", cl["cls"], n, "%s -> %s" % (bk["hdr"].get(n), a["hdr"])))
                if (bk.get("desc") or {}).get(n) != d:
                    log.append(("text", cl["cls"], n, "%s  ->  %s" % (((bk.get("desc") or {}).get(n) or "")[:70], d[:70])))
                    bk.setdefault("bld", {})[n] = b
            rows.append([n, a["tag"], None, icon])
            bk["hdr"][n], bk["src"][n] = a["hdr"], "client"
            bk.setdefault("desc", {})[n] = d
            if n not in old:
                bk.setdefault("bld", {})[n] = b
            if bk.get("bld", {}).get(n) == b and BUILD_FLAG.match((bk.get("chg") or {}).get(n, "")):
                del bk["chg"][n]   # the text is this build's now, so "numbers from the previous build" no longer holds
                log.append(("note", cl["cls"], n, "build-change flag dropped"))
        tab["spells"] = rows
    if write:
        with open(PLAN, "w") as f:
            json.dump(p, f, ensure_ascii=False, separators=(",", ":"))
    return log


if __name__ == "__main__":
    log = run(sys.argv[1], "--write" in sys.argv)
    for kind, cls, n, msg in log:
        print("%-5s %-8s %-22s %s" % (kind, cls, n[:22], msg))
    print("%d changes%s" % (len(log), " written" if "--write" in sys.argv else " (dry run)"))
