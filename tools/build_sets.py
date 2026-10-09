#!/usr/bin/env python3
"""Rebuild codex/sets.json (the Database's item sets) from one Forever client build.

  python3 tools/build_sets.py            # write codex/sets.json at BUILD
  python3 tools/build_sets.py --dry      # report only
  python3 tools/build_sets.py --build 1.60.1.70291

From research/wago/<build>/:
  sets      ItemSet, in the client's order; id is the ItemSet id
  bonuses   ItemSetSpell: {p: pieces needed, spell: the spell's internal name, id: spell id, era, fx: its tooltip}
            fx is the spell's description filled by tools/spelltext.py from the same build's tables; a bonus whose
            text cannot be filled (a token left over) keeps no fx, and the Database shows the internal name instead.
            fx0: 1 marks a bonus that has text in the client, left out because the client fills one of its numbers
            with 0 (a spell this build lacks, a per-combo-point value)
  era       per bonus, from spell id bands: 1.2M+ Forever-authored, 400k-470k a SoD spell reused, 470k-1.2M
            retail-era, below that Classic
  pieces    {id, n, q, slot, lvl, icon, band} from plan/items-db.json; the client's item table where the database has
            no row; "Item N - ..." where neither names it (server-sent pieces nobody has shown yet). band is the id band:
            classic < 200000 <= sod < 239000 <= forever. A piece whose database row is a WoW Classic estimate (est
            "classic": Forever has the id but nobody has shown its numbers) carries est "classic" and lvl 0
  cls       the classes every class-locked piece allows ([] when no piece is locked); estimate pieces do not count
  reqLevel  the highest level a piece requires; estimate pieces do not count, so a Classic level is never shown as Forever's

Carried from the file this rewrites, by set id (they need a WoW Classic comparison our data does not hold): cat
(Raid tier 1, Dungeon set (Tier 0), PvP set...), touched (reworked for Forever) and era "sod" (a Season of Discovery
copy of a Classic set). A set the old file lacks gets cat "New set", touched when a bonus is Forever-authored, and
era "sod" when its id is in 1570-1918.

tools/build_spellbook.py counts sets and setsHidden from this file; codex/codex.js renders it.
"""
import collections, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spelltext import Client, _rows

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "codex", "sets.json")
DB = os.path.join(ROOT, "plan", "items-db.json")
BUILD = "1.60.1.70291"
QUAL = ["poor", "common", "uncommon", "rare", "epic", "legendary", "artifact", "heirloom"]
SLOT = {"1": "head", "2": "neck", "3": "shoulder", "4": "shirt", "5": "chest", "6": "waist", "7": "legs",
        "8": "feet", "9": "wrist", "10": "hands", "11": "finger", "12": "trinket", "13": "one-hand",
        "14": "off-hand", "15": "ranged", "16": "back", "17": "two-hand", "19": "tabard", "20": "chest",
        "21": "main-hand", "22": "off-hand", "23": "off-hand", "25": "thrown", "26": "ranged", "28": "relic"}
BROKEN = re.compile(r"\$|\d+\.\d+\.\d+|\{|\}")  # a token left over, or "0.5.1%" from a half-filled template
ZERO = re.compile(r"(?<![\d.])0(?:\.0+)?(?![\d.])")
TOKEN = re.compile(r"\$\{[^}]*\}(?:\.\d)?|\$[^\s%.,;:)]+")


def zero_from_token(template, text):
    """A token the client fills with 0 (a spell this build lacks, a per-combo-point value): more zeros in the text than
    the template writes out."""
    return len(ZERO.findall(text)) > len(ZERO.findall(TOKEN.sub("", template)))


def era(sid):
    sid = int(sid)
    return "forever" if sid >= 1200000 else "retail" if sid >= 470000 else "sod" if sid >= 400000 else "classic"


def band(iid):
    iid = int(iid)
    return "forever" if iid >= 239000 else "sod" if iid >= 200000 else "classic"


def build(b, old):
    c = Client(b)
    db = {str(i["id"]): i for i in json.load(open(DB))["items"]}
    sparse = {r["ID"]: r for r in _rows(b, "ItemSparse")}
    item = {r["ID"]: r for r in _rows(b, "Item")}
    icons = {}
    for r in _rows(b, "ManifestInterfaceData"):
        if r.get("FilePath", "").replace("\\", "/").lower().startswith("interface/icons/"):
            icons[r["ID"]] = os.path.splitext(r["FileName"])[0].lower()
    classes = {r["ID"]: r["Name_lang"] for r in _rows(b, "ChrClasses")}
    spells = collections.defaultdict(list)
    for r in _rows(b, "ItemSetSpell"):
        spells[r["ItemSetID"]].append(r)
    by_id = {str(s["id"]): s for s in old.get("sets") or [] if s.get("id") is not None}
    rep = collections.Counter()
    broken = []
    out = []
    for i, r in enumerate(_rows(b, "ItemSet")):
        sid = r["ID"]
        prev = by_id.get(sid)
        if prev is None and not by_id and i < len(old.get("sets") or []) and old["sets"][i]["n"] == r["Name_lang"]:
            prev = old["sets"][i]  # a file from before set ids: same client order
        pieces, locks, lvls = [], [], []
        for k in range(17):
            iid = r.get("ItemID_%d" % k)
            if not iid or iid == "0":
                continue
            it, sp = db.get(iid), sparse.get(iid)
            if it:
                guess = it.get("est") == "classic"  # Classic's level and classes, not Forever's: kept off the set
                pc = {"id": int(iid), "n": it["name"], "q": it.get("quality") or "unknown", "slot": "" if it.get("slot") == "unknown" else it.get("slot") or "",
                      "lvl": 0 if guess else it.get("reqLevel") or 0, "icon": it.get("icon") or ""}
                if guess:
                    pc["est"] = "classic"
                    rep["piece from a Classic estimate (level and classes left out)"] += 1
                else:
                    rep["piece from the database"] += 1
                if it.get("cls") and not guess:
                    locks.append(set(it["cls"]))
            elif sp:
                pc = {"id": int(iid), "n": sp["Display_lang"], "q": QUAL[int(sp["OverallQualityID"] or 1)], "slot": SLOT.get(sp["InventoryType"], ""),
                      "lvl": int(sp["RequiredLevel"] or 0), "icon": icons.get((item.get(iid) or {}).get("IconFileDataID", ""), "")}
                m = int(sp["AllowableClass"] or 0)
                names = {n for cid, n in classes.items() if m > 0 and m & (1 << (int(cid) - 1))}
                if names and len(names) < len(classes):
                    locks.append(names)
                rep["piece from the client"] += 1
            else:
                pc = {"id": int(iid), "n": "Item %s – no name in the client data yet" % iid, "q": "unknown", "slot": "", "lvl": 0, "icon": ""}
                rep["piece unnamed"] += 1
            pc["band"] = band(iid)
            lvls.append(pc["lvl"])
            pieces.append(pc)
        bonuses = []
        for s in sorted(spells.get(sid, []), key=lambda x: (int(x["Threshold"]), int(x["ID"]))):
            b2 = {"p": int(s["Threshold"]), "spell": c.name.get(s["SpellID"], ""), "id": int(s["SpellID"]), "era": era(s["SpellID"])}
            try:
                fx = c.item_text(s["SpellID"])
            except Exception:
                fx = None
            fx = re.sub(r"\s+", " ", fx or "").strip()
            if fx and zero_from_token((c.spell.get(s["SpellID"]) or {}).get("Description_lang", ""), fx):
                broken.append((r["Name_lang"], s["SpellID"], fx))
                b2["fx0"] = 1
                rep["bonus text left out (a number the client fills with 0)"] += 1
            elif fx and not BROKEN.search(fx):
                b2["fx"] = fx
                rep["bonus text"] += 1
            elif fx:
                broken.append((r["Name_lang"], s["SpellID"], fx))
                rep["bonus text left out (a token the resolver cannot fill)"] += 1
            else:
                rep["bonus without text in the client"] += 1
            bonuses.append(b2)
        cls = sorted(set.intersection(*locks), key=lambda n: [v for k, v in sorted(classes.items(), key=lambda x: int(x[0]))].index(n)) if locks else []
        e = {"id": int(sid), "n": r["Name_lang"], "cat": prev["cat"] if prev else "New set", "pieces": pieces,
             "bonuses": bonuses, "cls": cls, "touched": prev["touched"] if prev else any(x["era"] == "forever" for x in bonuses),
             "reqLevel": max(lvls) if lvls else 0}
        sod = prev.get("era") if prev else ("sod" if 1570 <= int(sid) <= 1918 else None)
        if sod:
            e["era"] = sod
        if not prev:
            rep["set new to this file"] += 1
        out.append(e)
    return out, rep, broken


def main():
    b = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--build=")), None) or \
        (sys.argv[sys.argv.index("--build") + 1] if "--build" in sys.argv else BUILD)
    old = json.load(open(OUT)) if os.path.exists(OUT) else {}
    sets, rep, broken = build(b, old)
    before = {s.get("id") or s["n"]: s for s in old.get("sets") or []}
    changed = 0
    for s in sets:
        p = before.get(s["id"]) or before.get(s["n"])
        if p and [(x["p"], x["id"], x.get("fx")) for x in p["bonuses"]] != [(x["p"], x["id"], x.get("fx")) for x in s["bonuses"]]:
            changed += 1
    print("sets %d (%s); bonus lists or texts that moved: %d" % (len(sets), b, changed))
    for k, v in sorted(rep.items()):
        print("  %-55s %d" % (k, v))
    for n, sid, fx in broken:
        print("  left out: %s, spell %s: %s" % (n, sid, fx))
    if "--dry" in sys.argv:
        return
    doc = {"note": "ItemSet and ItemSetSpell from beta client %s (tools/build_sets.py). Bonus text is each spell's tooltip, "
                   "filled from the same build's spell tables; where the client has no text, the internal spell name is "
                   "shown as-is; fx0 marks a bonus whose client text has a number the client fills with 0, left out. Pieces: name, quality, slot and level from plan/items-db.json, or the client's item table "
                   "where the database has no row; est 'classic' marks a piece only WoW Classic's numbers describe so far, and "
                   "the set's level and classes leave those pieces out. Era per bonus from spell ID bands: 1.2M+ Forever-authored, 400-470k SoD "
                   "spell reused, 470k-1.2M retail-era, below classic. Set categories, the SoD tag and touched (reworked for "
                   "Forever) come from the first compile, which compared the sets against WoW Classic." % b,
           "build": b, "sets": sets}
    with open(OUT, "w") as f:
        json.dump(doc, f, ensure_ascii=False, separators=(",", ":"))
    print("wrote codex/sets.json")


if __name__ == "__main__":
    main()
