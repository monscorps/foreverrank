#!/usr/bin/env python3
"""Carry the item database (plan/items-db.json) from one beta build to the next.

  python3 tools/apply_items.py 1.60.1.69876 1.60.1.70009          # dry run
  python3 tools/apply_items.py 1.60.1.69876 1.60.1.70009 --write

  removed   rows gone from ItemSparse leave the database
  renamed   names follow Display_lang
  levels    item and required level follow the client
  stats     re-decoded from the item budget (RandPropPoints x StatPercentEditor,
            budget column per inventory type) - only for items whose stored
            stats the decoder reproduces exactly from OLD; others are reported
  added     new rows join with name, quality, slot, levels, icon and the
            category most items of the same client class/subclass carry;
            stats are decoded when the item has any

Only ItemSparse rows are covered: server-sent items (most quest rewards)
never appear in client tables at all.
"""
import collections, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from diff_builds import diff, load
from spelltext import _rows

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "plan", "items-db.json")
STAT = {"3": "agility", "4": "strength", "5": "intellect", "6": "spirit", "7": "stamina",
        "45": "spellPower", "38": "attackPower"}
QCOL = {"2": "Good", "3": "Superior", "4": "Epic"}
QUAL = ["poor", "common", "uncommon", "rare", "epic", "legendary", "artifact", "heirloom"]
# budget column per InventoryType, fitted against the whole database (97-100% exact
# for armor, jewelry and melee; ranged slots run a point off more often)
COL = {"1": 0, "2": 2, "3": 1, "5": 0, "6": 1, "7": 0, "8": 1, "9": 2, "10": 1, "11": 2, "12": 1,
       "13": 3, "14": 2, "15": 4, "16": 2, "17": 0, "20": 0, "21": 3, "22": 3, "23": 2, "25": 4, "26": 4}
SLOT = {"1": "head", "2": "neck", "3": "shoulder", "4": "shirt", "5": "chest", "6": "waist", "7": "legs",
        "8": "feet", "9": "wrist", "10": "hands", "11": "finger", "12": "trinket", "13": "one-hand",
        "14": "off-hand", "15": "ranged", "16": "back", "17": "two-hand", "19": "tabard", "20": "chest",
        "21": "main-hand", "22": "off-hand", "23": "off-hand", "25": "thrown", "26": "ranged", "28": "relic"}


def decode(r, rpp):
    q, inv = QCOL.get(r["OverallQualityID"]), r["InventoryType"]
    if not q or inv not in COL or r["ItemLevel"] not in rpp:
        return None
    budget = float(rpp[r["ItemLevel"]]["%sF_%d" % (q, COL[inv])])
    out = {}
    for k in range(10):
        t, p = r.get("StatModifier_bonusStat_%d" % k), r.get("StatPercentEditor_%d" % k)
        if t in STAT and p and p != "0":
            out[STAT[t]] = out.get(STAT[t], 0) + int(round(budget * int(p) / 10000.0))
    return out


def primaries(stats):
    return {k: v for k, v in (stats or {}).items() if k in STAT.values()}


def run(o, n, write=False):
    db = json.load(open(DB))
    items = db["items"]
    by = {str(i["id"]): i for i in items}
    old_sp, _ = load(o, "ItemSparse")
    new_sp, _ = load(n, "ItemSparse")
    rpp_o = {r["ID"]: r for r in _rows(o, "RandPropPoints")}
    rpp_n = {r["ID"]: r for r in _rows(n, "RandPropPoints")}
    item_n = {r["ID"]: r for r in _rows(n, "Item")}
    icons = {}
    for r in _rows(n, "ManifestInterfaceData"):
        if r.get("FilePath", "").replace("\\", "/").lower().startswith("interface/icons/"):
            icons[r["ID"]] = os.path.splitext(r["FileName"])[0].lower()
    item_o = {r["ID"]: r for r in _rows(o, "Item")}
    vote = collections.defaultdict(collections.Counter)
    for iid, it in by.items():
        ir = item_o.get(iid)
        if ir:
            vote[(ir["ClassID"], ir["SubclassID"])][(it.get("cat"), it.get("sub"))] += 1
    d = diff(o, n, "ItemSparse")
    log = []
    gone = {r["ID"] for r in d["removed"]}
    for iid in sorted(gone & set(by), key=int):
        log.append(("removed", iid, by[iid]["name"]))
    for ch in d["changed"]:
        iid = ch["id"]
        it = by.get(iid)
        if not it:
            continue
        nr = new_sp[iid]
        if "Display_lang" in ch["cols"] and nr["Display_lang"] and it["name"] != nr["Display_lang"]:
            log.append(("renamed", iid, "%s -> %s" % (it["name"], nr["Display_lang"])))
            it["name"] = nr["Display_lang"]
        if "ItemLevel" in ch["cols"] and it.get("itemLevel") is not None:
            log.append(("ilvl", iid, "%s: %s -> %s" % (it["name"], it["itemLevel"], nr["ItemLevel"])))
            it["itemLevel"] = int(nr["ItemLevel"])
        if "RequiredLevel" in ch["cols"]:
            it["reqLevel"] = int(nr["RequiredLevel"]) or None
        if any(c.startswith(("StatModifier", "StatPercent")) or c == "ItemLevel" for c in ch["cols"]):
            before = decode(old_sp[iid], rpp_o)
            if before is not None and before == primaries(it.get("stats")):
                after = decode(nr, rpp_n) or {}
                rest = {k: v for k, v in (it.get("stats") or {}).items() if k not in STAT.values()}
                rest.update(after)
                log.append(("stats", iid, "%s: %s -> %s" % (it["name"], primaries(it.get("stats")), after)))
                it["stats"] = rest or None
            else:
                log.append(("stats?", iid, "%s: client stats changed, stored stats not reproducible; left as is" % it["name"]))
        if "ItemSet" in ch["cols"] and nr["ItemSet"] == "0" and it.get("setName"):
            log.append(("set", iid, "%s leaves %s" % (it["name"], it["setName"])))
            for k in ("setName", "setPieces", "setBonuses"):
                it.pop(k, None)
    added = []
    for r in d["added"]:
        iid = r["ID"]
        if iid in by:
            continue
        ir = item_n.get(iid, {})
        cat, sub = (vote.get((ir.get("ClassID"), ir.get("SubclassID"))) or collections.Counter({("misc", "Misc"): 1})).most_common(1)[0][0]
        e = {"id": iid, "name": r["Display_lang"], "quality": QUAL[int(r["OverallQualityID"] or 1)],
             "slot": SLOT.get(r["InventoryType"], "unknown"), "reqLevel": int(r["RequiredLevel"] or 0) or None,
             "itemLevel": int(r["ItemLevel"] or 1), "icon": icons.get(ir.get("IconFileDataID", ""), "inv_misc_questionmark"),
             "cat": cat, "sub": sub, "nw": 1 if int(iid) >= 239000 else None,
             "source": "Beta client %s" % n}
        if r.get("Bonding") in ("1", "4"):
            e["binding"] = "BoP"
        elif r.get("Bonding") == "2":
            e["binding"] = "BoE"
        st = decode(r, rpp_n)
        if st:
            e["stats"] = st
        if r.get("Description_lang"):
            e["flavor"] = r["Description_lang"]
        added.append({k: v for k, v in e.items() if v is not None})
        log.append(("added", iid, "%s [%s/%s]" % (r["Display_lang"], cat, sub)))
    if write:
        db["items"] = [i for i in items if str(i["id"]) not in gone] + added
        db["build"] = n
        db["note"] = db["note"].replace(o, n)
        with open(DB, "w") as f:
            json.dump(db, f, ensure_ascii=False, separators=(",", ":"))
    return log


if __name__ == "__main__":
    log = run(sys.argv[1], sys.argv[2], "--write" in sys.argv)
    for kind, iid, msg in log:
        print("%-8s %-7s %s" % (kind, iid, msg))
    print(collections.Counter(k for k, _, _ in log), "written" if "--write" in sys.argv else "(dry run)")
