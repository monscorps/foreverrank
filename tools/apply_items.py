#!/usr/bin/env python3
"""Carry the item database (plan/items-db.json) from one beta build to the next.

  python3 tools/apply_items.py 1.60.1.70170 1.60.1.70291          # dry run
  python3 tools/apply_items.py 1.60.1.70170 1.60.1.70291 --write
  python3 tools/apply_items.py --check 1.60.1.70245                # the decoder against ForeverChanges' cached tooltips

For every row whose ItemSparse or Item row changed between OLD and NEW, the client's new value replaces the stored one:
  removed   rows gone from ItemSparse leave the database
  renamed   Display_lang
  quality   OverallQualityID
  ilvl      ItemLevel (and RequiredLevel moves reqLevel)
  binding   Bonding; flavor Description_lang; classes AllowableClass
  type      the armor type (Item.SubclassID of armor: starter boots that were Misc)
  stats     the item budget (RandPropPoints x StatPercentEditor, budget column per inventory type) decoded for every
            stat id Forever uses, and the "Equip: +N ..." lines that name them rewritten in Forever's wording
  armor, damage, speed  re-derived when item level, quality, speed or armor type move, from the client's armor and
            weapon damage tables (exact where the stored value is the table's own; else the stored value is scaled
            by the tables' ratio and the line says armor~ or damage~)
  sell      sell price moves are listed, not stored: the database carries no prices
  added     new rows join with name, quality, slot, levels, icon, stats, armor, damage, their Use/Equip lines in the
            client's own words and the category most items of the same client class/subclass carry

Idempotent: a field already at NEW's value is left alone and not listed, so a second run lists nothing. Stats move
only where the stored numbers are the OLD row's own (or already NEW's); where another source wrote them, the line says
stats? and leaves them. tools/scavenge_items.py runs the same carry on top of ForeverChanges' tooltips when the client
is newer than their build.

Only ItemSparse rows are covered: server-sent items (most quest rewards) never appear in client tables at all.
"""
import collections, json, math, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from diff_builds import diff, load
from spelltext import _rows

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "plan", "items-db.json")
QCOL = {"2": "Good", "3": "Superior", "4": "Epic"}
QUAL = ["poor", "common", "uncommon", "rare", "epic", "legendary", "artifact", "heirloom"]
BIND = {"1": "BoP", "2": "BoE", "3": "BoU", "4": "Quest"}
# budget column per InventoryType, fitted against the whole database (97-100% exact
# for armor, jewelry and melee; ranged slots run a point off more often)
COL = {"1": 0, "2": 2, "3": 1, "5": 0, "6": 1, "7": 0, "8": 1, "9": 2, "10": 1, "11": 2, "12": 1,
       "13": 3, "14": 2, "15": 4, "16": 2, "17": 0, "20": 0, "21": 3, "22": 3, "23": 2, "25": 4, "26": 4}
SLOT = {"1": "head", "2": "neck", "3": "shoulder", "4": "shirt", "5": "chest", "6": "waist", "7": "legs",
        "8": "feet", "9": "wrist", "10": "hands", "11": "finger", "12": "trinket", "13": "one-hand",
        "14": "off-hand", "15": "ranged", "16": "back", "17": "two-hand", "19": "tabard", "20": "chest",
        "21": "main-hand", "22": "off-hand", "23": "off-hand", "25": "thrown", "26": "ranged", "28": "relic"}
ARMOR_TYPE = {"1": "Cloth", "2": "Leather", "3": "Mail", "4": "Plate"}
ARMOR_MOD = {"1": "Clothmodifier", "2": "Leathermodifier", "3": "Chainmodifier", "4": "Platemodifier"}
DAMAGE_TABLE = {"13": "ItemDamageOneHand", "21": "ItemDamageOneHand", "22": "ItemDamageOneHand", "17": "ItemDamageTwoHand"}

# ItemSparse stat ids, keyed the way tools/scavenge_items.py reads Forever's tooltip line for each (checked with --check
# against ForeverChanges' tooltips: the same budget gives their number for every id below)
PRIMARY = {"3": "agility", "4": "strength", "5": "intellect", "6": "spirit", "7": "stamina"}
WHITE = {"50": "bonusArmor", "51": "fireResist", "52": "frostResist", "53": "holyResist", "54": "shadowResist",
         "55": "natureResist", "56": "arcaneResist"}  # white lines: "+120 Armor", "+7 Fire Resistance"
# ratings: (word, rating key, percent key, rating per 1%), as tools/scavenge_items.py RATING
RATING = {"12": ("Defense", "defenseRating", "defense", 1), "13": ("Dodge", "dodgeRating", "dodge", 12),
          "14": ("Parry", "parryRating", "parry", 15), "15": ("Block", "blockRating", "blockChance", 5),
          "31": ("Hit", "hitRating", "hit", 10), "32": ("Critical Strike", "critRating", "crit", 14),
          "36": ("Haste", "hasteRating", None, 0), "37": ("Expertise", "expertiseRating", None, 0)}
# green "Equip: +N <words>" lines; None: a line the site shows but does not count
EQUIP = {"38": ("Attack Power", "attackPower"), "39": ("Ranged Attack Power", "rangedAttackPower"),
         "41": ("Healing", "healing"), "42": ("Spell Damage", "spellDamage"), "43": ("Mana Regeneration", "mp5"),
         "45": ("Spell Power", "spellPower"), "46": ("Health Regeneration", "hp5"), "47": ("Spell Penetration", "spellPiercing"),
         "48": ("Block Value", "blockValue"), "83": ("Weapon Damage", "weaponDamage"),
         "84": ("Holy Spell Damage", "holySpellDamage"), "85": ("Fire Spell Damage", "fireSpellDamage"),
         "86": ("Nature Spell Damage", "natureSpellDamage"), "87": ("Frost Spell Damage", "frostSpellDamage"),
         "88": ("Shadow Spell Damage", "shadowSpellDamage"), "89": ("Arcane Spell Damage", "arcaneSpellDamage"),
         "90": ("Two-Handed Axes Skill", "axeSkill"), "91": ("Two-Handed Maces Skill", "maceSkill"),
         "92": ("Two-Handed Swords Skill", "swordSkill"), "96": ("Daggers Skill", "daggerSkill"),
         "98": ("Fist Weapons Skill", "unarmedSkill"), "101": ("Polearms Skill", "weaponSkill"), "117": ("Fishing", "fishing"),
         "112": ("Herbalism Skill", None), "113": ("Mining Skill", None), "114": ("Skinning Skill", None),
         "115": ("Cooking Skill", None), "124": ("Spell Resistance", None),
         "125": ("Attack Power Vs Humanoids", None), "126": ("Attack Power Vs Elementals", None),
         "127": ("Attack Power Vs Demons", None), "128": ("Attack Power Vs Undead", None),
         "129": ("Attack Power Vs Dragonkin", None), "131": ("Attack Power Vs Beasts", None),
         "132": ("Attack Power Vs Mechanical", None), "134": ("Spell Damage Vs Elementals", None),
         "135": ("Spell Damage Vs Demons", None), "136": ("Spell Damage Vs Undead", None), "139": ("Spell Damage Vs Beasts", None)}
STAT_KEYS = set(PRIMARY.values()) | set(WHITE.values()) | {k for _, k, _, _ in RATING.values()} | \
    {k for _, _, k, _ in RATING.values() if k} | {k for _, k in EQUIP.values() if k}


def half_up(x):
    """The client rounds half up (22.5 -> 23); the float is rounded first so 22.4999999 does not drop a point."""
    return int(math.floor(round(x, 4) + 0.5))


def decode(r, rpp):
    """(stats, Equip lines, unknown stat ids) for one ItemSparse row, or None when the row spends a budget the tables
    cannot price (a quality or slot without a budget column, an item level the table lacks)."""
    raw = collections.OrderedDict()
    for k in range(10):
        t, p = r.get("StatModifier_bonusStat_%d" % k), r.get("StatPercentEditor_%d" % k)
        if t and t not in ("-1", "0") and p and p != "0":
            raw[t] = raw.get(t, 0) + int(p)
    if not raw:
        return {}, [], []
    q, inv = QCOL.get(r.get("OverallQualityID")), r.get("InventoryType")
    if not q or inv not in COL or r.get("ItemLevel") not in rpp:
        return None
    budget = float(rpp[r["ItemLevel"]]["%sF_%d" % (q, COL[inv])])
    st, lines, unknown = {}, [], []

    def add(k, v):
        st[k] = round(st.get(k, 0) + v, 2)
    for t, p in raw.items():
        v = half_up(budget * p / 10000.0)
        if not v:
            continue
        if t in PRIMARY:
            add(PRIMARY[t], v)
        elif t in WHITE:
            add(WHITE[t], v)
        elif t in RATING:
            word, k1, k2, per = RATING[t]
            add(k1, v)
            if k2:
                add(k2, v / float(per))
            lines.append("Equip: %+d %s Rating" % (v, word))
        elif t in EQUIP:
            word, k = EQUIP[t]
            if k:
                add(k, v)
            lines.append("Equip: %+d %s" % (v, word))
        else:
            unknown.append(t)
    return st, lines, unknown


class Build:
    """One build's item tables, read the way the database reads them."""

    def __init__(self, build):
        self.build = build
        self.sparse = load(build, "ItemSparse")[0] or {}
        self.item = {r["ID"]: r for r in _rows(build, "Item")}
        self.rpp = {r["ID"]: r for r in _rows(build, "RandPropPoints")}
        self.classes = {r["ID"]: r["Name_lang"] for r in _rows(build, "ChrClasses")}
        self.aq = {r["ID"]: r for r in _rows(build, "ItemArmorQuality")}
        self.at = {r["ItemLevel"]: r for r in _rows(build, "ItemArmorTotal")}
        self.ash = {r["ItemLevel"]: r for r in _rows(build, "ItemArmorShield")}
        self.al = {r["ID"]: r for r in _rows(build, "ArmorLocation")}
        self.dmg = {t: {r["ItemLevel"]: r for r in _rows(build, t)} for t in set(DAMAGE_TABLE.values())}

    def class_names(self, mask):
        """AllowableClass as the tooltip's "Classes:" list; None when every class may use it."""
        m = int(mask or 0)
        if m <= 0:
            return None
        names = [n for cid, n in sorted(self.classes.items(), key=lambda x: int(x[0])) if m & (1 << (int(cid) - 1))]
        return names if names and len(names) < len(self.classes) else None

    def armor(self, r, ir):
        """The armor value the client's tables give the row (unrounded), or None."""
        if ir.get("ClassID") != "4":
            return None
        q, il, sub = r.get("OverallQualityID"), r.get("ItemLevel"), ir.get("SubclassID")
        if sub == "6":
            row = self.ash.get(il)
            return float(row["Quality_%s" % q]) if row and row.get("Quality_%s" % q) else None
        loc = self.al.get("5" if r.get("InventoryType") == "20" else r.get("InventoryType"))  # robes take the chest's share
        if sub not in ARMOR_TYPE or not loc or il not in self.at or il not in self.aq:
            return None
        v = float(self.at[il][ARMOR_TYPE[sub]]) * float(loc[ARMOR_MOD[sub]]) * float(self.aq[il]["Qualitymod_%s" % q])
        return v or None

    def damage(self, r, ir):
        """(low, high, speed) the client's weapon damage tables give a melee weapon (unrounded), or None."""
        t = DAMAGE_TABLE.get(r.get("InventoryType"))
        if ir.get("ClassID") != "2" or not t or r.get("ItemLevel") not in self.dmg[t]:
            return None
        dps = float(self.dmg[t][r["ItemLevel"]]["Quality_%s" % r["OverallQualityID"]])
        spd = int(r.get("ItemDelay") or 0) / 1000.0
        var = float(r.get("DmgVariance") or 0)
        if not dps or not spd:
            return None
        return dps * spd * (1 - var / 2), dps * spd * (1 + var / 2), spd

    def view(self, iid):
        """What this build's client says about one item, in the database's fields; None without an ItemSparse row."""
        r = self.sparse.get(str(iid))
        if not r:
            return None
        ir = self.item.get(str(iid), {})
        dec = decode(r, self.rpp)
        sub = ir.get("SubclassID") if ir.get("ClassID") == "4" else None
        return {"name": r["Display_lang"], "quality": QUAL[int(r["OverallQualityID"] or 1)],
                "itemLevel": int(r["ItemLevel"] or 0), "reqLevel": int(r["RequiredLevel"] or 0) or None,
                "binding": BIND.get(r["Bonding"]), "flavor": r["Description_lang"] or None,
                "cls": self.class_names(r["AllowableClass"]), "armorType": ARMOR_TYPE.get(sub) or ("Shield" if sub == "6" else None),
                "stats": dec[0] if dec else None, "lines": dec[1] if dec else None, "unknown": dec[2] if dec else None,
                "armorM": self.armor(r, ir), "dmgM": self.damage(r, ir), "sell": int(r["SellPrice"] or 0)}


def _stat_lines(effects, a):
    """The effect lines that state the stats in `a` (Forever's "Equip: +N Attack Power" or Wowhead's wording)."""
    from scavenge_items import equip_stats  # late: scavenge_items imports this file
    out = []
    for line in effects or []:
        st = {}
        if line.startswith("Equip:"):
            equip_stats(line, st)
        if line in a["lines"] or line.rstrip(".") in a["lines"] or (st and all(a["stats"].get(k) == v for k, v in st.items())):
            out.append(line)
    return out


def _dmg_rounding(m, lo, hi):
    """The rounding that turns the table's (low, high) into the stored damage, or None."""
    for f in (lambda x, y: (half_up(x), half_up(y)), lambda x, y: (int(math.floor(x)), int(math.ceil(y))),
              lambda x, y: (int(math.floor(x)), half_up(y))):
        if f(m[0], m[1]) == (lo, hi):
            return f
    return None


def carry(it, a, b, again=False):
    """Move one database row from the client's OLD view a to its NEW view b. Returns [(kind, message)].
    again: the database is already at NEW, so nothing is scaled a second time."""
    out = []
    name = it.get("name")

    def moved(k):
        return a.get(k) != b.get(k)

    def put(k, v):
        if v is None:
            it.pop(k, None)
        else:
            it[k] = v
    if b["name"] and moved("name") and it.get("name") != b["name"]:
        out.append(("renamed", "%s -> %s" % (it.get("name"), b["name"])))
        it["name"] = b["name"]
    for k, kind in (("quality", "quality"), ("itemLevel", "ilvl"), ("reqLevel", "reqlvl"), ("binding", "binding"),
                    ("flavor", "flavor"), ("cls", "classes")):
        if moved(k) and it.get(k) != b[k] and not (k == "itemLevel" and it.get(k) is None):
            out.append((kind, "%s: %s -> %s" % (name, it.get(k), b[k])))
            put(k, b[k])
    if moved("armorType") and b["armorType"]:
        if it.get("cat") == "armor" and (it.get("sub") != b["armorType"] or it.get("type") != b["armorType"]):
            out.append(("type", "%s: %s -> %s" % (name, it.get("type") or it.get("sub"), b["armorType"])))
            it["sub"] = it["type"] = b["armorType"]
        elif it.get("cat") != "armor" and it.get("slot") not in (None, "unknown") and it.get("type") != b["armorType"]:
            out.append(("type", "%s: %s -> %s" % (name, it.get("type"), b["armorType"])))
            it["type"] = b["armorType"]
    # stats and the lines that name them
    if moved("stats") or moved("lines"):
        if b["stats"] is None or a["stats"] is None:
            out.append(("stats?", "%s: the client's budget tables cannot price this row; stats left as they are" % name))
        else:
            keys = set(a["stats"]) | set(b["stats"])
            cur = {k: v for k, v in (it.get("stats") or {}).items() if k in keys}
            if cur == b["stats"] and all(l in (it.get("effects") or []) for l in b["lines"]):
                pass  # already there
            elif cur == a["stats"]:
                gone = _stat_lines(it.get("effects"), a)
                rest = {k: v for k, v in (it.get("stats") or {}).items() if k not in keys}
                rest.update(b["stats"])
                out.append(("stats", "%s: %s -> %s" % (name, cur, b["stats"])))
                put("stats", rest or None)
                put("effects", (b["lines"] + [l for l in (it.get("effects") or []) if l not in gone]) or None)
            else:
                out.append(("stats?", "%s: client stats moved %s -> %s, but the stored %s came from elsewhere; left as is" % (
                    name, a["stats"], b["stats"], cur)))
    if b["unknown"] and moved("unknown"):
        out.append(("stats?", "%s: stat ids %s are not decoded" % (name, ",".join(b["unknown"]))))
    # armor follows item level, quality and armor type (Misc boots that became Mail get the table's armor)
    if not a["armorM"] and b["armorM"] and not it.get("armor") and it.get("cat") == "armor":
        out.append(("armor", "%s: none -> %s" % (name, half_up(b["armorM"]))))
        it["armor"] = half_up(b["armorM"])
    if a["armorM"] and b["armorM"] and moved("armorM") and it.get("armor"):
        now, was = half_up(b["armorM"]), half_up(a["armorM"])
        if it["armor"] == now:
            pass
        elif it["armor"] == was:
            out.append(("armor", "%s: %s -> %s" % (name, it["armor"], now)))
            it["armor"] = now
        elif not again:
            v = half_up(it["armor"] * b["armorM"] / a["armorM"])
            out.append(("armor~", "%s: %s -> %s (scaled by the client's armor tables)" % (name, it["armor"], v)))
            it["armor"] = v
    # damage and speed follow item level, quality and speed
    if a["dmgM"] and b["dmgM"] and moved("dmgM") and it.get("damage"):
        try:
            lo, hi = [int(x) for x in str(it["damage"]).split("-")]
        except ValueError:
            lo = hi = None
        if lo is not None:
            f, new, kind = _dmg_rounding(a["dmgM"], lo, hi), None, "damage"
            if f:
                new = f(b["dmgM"][0], b["dmgM"][1])
            elif not again and _dmg_rounding(b["dmgM"], lo, hi) is None:
                ra = (b["dmgM"][0] + b["dmgM"][1]) / (a["dmgM"][0] + a["dmgM"][1])
                new, kind = (half_up(lo * ra), half_up(hi * ra)), "damage~"
            if new and (new != (lo, hi) or it.get("speed") != b["dmgM"][2]):
                spd = b["dmgM"][2]
                out.append((kind, "%s: %s-%s @%s -> %s-%s @%s" % (name, lo, hi, it.get("speed"), new[0], new[1], spd)))
                it["damage"] = "%d-%d" % new
                it["speed"] = spd
                it["dps"] = round((new[0] + new[1]) / 2.0 / spd, 1)
    return out


def item_spells(build):
    """A function giving an item's Use/Equip/Chance on hit lines from the client's own spell text (ItemXItemEffect ->
    ItemEffect -> Spell), filled by tools/spelltext.py; lines with a token it cannot fill are left out."""
    from spelltext import Client
    st = Client(build)
    ie = {r["ID"]: r for r in _rows(build, "ItemEffect")}
    by = collections.defaultdict(list)
    for r in _rows(build, "ItemXItemEffect"):
        if r["ItemEffectID"] in ie:
            by[r["ItemID"]].append(ie[r["ItemEffectID"]])
    word = {"0": "Use", "1": "Equip", "2": "Chance on hit"}

    def lines(iid):
        out = []
        for e in by.get(str(iid), []):
            try:
                t = " ".join((st.item_text(e["SpellID"]) or "").split())
            except Exception:
                t = ""
            if t and "$" not in t and e.get("TriggerType") in word:
                out.append("%s: %s" % (word[e["TriggerType"]], t))
        return out
    return lines


def view_changes(o, n):
    """Ids whose ItemSparse or Item row moved between two builds (icon and sound ids aside)."""
    ids = set()
    for t in ("ItemSparse", "Item"):
        d = diff(o, n, t) or {"changed": []}
        ids |= {ch["id"] for ch in d["changed"] if [c for c in ch["cols"] if c not in ("IconFileDataID", "ItemGroupSoundsID")]}
    return ids


def run(o, n, write=False):
    db = json.load(open(DB))
    again = db.get("build") == n
    items = db["items"]
    by = {str(i["id"]): i for i in items}
    A, B = Build(o), Build(n)
    icons = {}
    for r in _rows(n, "ManifestInterfaceData"):
        if r.get("FilePath", "").replace("\\", "/").lower().startswith("interface/icons/"):
            icons[r["ID"]] = os.path.splitext(r["FileName"])[0].lower()
    vote = collections.defaultdict(collections.Counter)
    for iid, it in by.items():
        ir = A.item.get(iid)
        if ir:
            vote[(ir["ClassID"], ir["SubclassID"])][(it.get("cat"), it.get("sub"))] += 1
    log = []
    gone = set(A.sparse) - set(B.sparse)
    for iid in sorted(gone & set(by), key=int):
        log.append(("removed", iid, by[iid]["name"]))
    for iid in sorted(view_changes(o, n) & set(by), key=int):
        a, b = A.view(iid), B.view(iid)
        if not a or not b:
            continue
        for kind, msg in carry(by[iid], a, b, again):
            log.append((kind, iid, msg))
        if a["sell"] != b["sell"] and not again:
            log.append(("sell", iid, "%s: %d -> %d copper (not stored)" % (by[iid]["name"], a["sell"], b["sell"])))
    added, uses = [], None
    for iid in sorted(set(B.sparse) - set(A.sparse), key=int):
        if iid in by:
            continue
        r, ir, v = B.sparse[iid], B.item.get(iid, {}), B.view(iid)
        cat, sub = (vote.get((ir.get("ClassID"), ir.get("SubclassID"))) or collections.Counter({("misc", "Misc"): 1})).most_common(1)[0][0]
        e = {"id": iid, "name": r["Display_lang"], "quality": v["quality"],
             "slot": SLOT.get(r["InventoryType"], "unknown"), "reqLevel": v["reqLevel"],
             "itemLevel": v["itemLevel"] or 1, "icon": icons.get(ir.get("IconFileDataID", ""), "inv_misc_questionmark"),
             "cat": cat, "sub": sub, "nw": 1 if int(iid) >= 239000 else None, "binding": v["binding"], "flavor": v["flavor"],
             "cls": v["cls"], "source": "Beta client %s" % n}
        if cat == "armor" and v["armorType"]:
            e["sub"] = e["type"] = v["armorType"]
        if v["stats"]:
            e["stats"] = v["stats"]
        if uses is None:
            uses = item_spells(n)
        lines = (v["lines"] or []) + uses(iid)
        if lines:
            e["effects"] = lines
        if v["armorM"]:
            e["armor"] = half_up(v["armorM"])
        if v["dmgM"]:
            lo, hi, spd = half_up(v["dmgM"][0]), half_up(v["dmgM"][1]), v["dmgM"][2]
            e["damage"], e["speed"], e["dps"] = "%d-%d" % (lo, hi), spd, round((lo + hi) / 2.0 / spd, 1)
        added.append({k: x for k, x in e.items() if x is not None})
        log.append(("added", iid, "%s [%s/%s]" % (r["Display_lang"], cat, sub)))
    if write:
        db["items"] = [i for i in items if str(i["id"]) not in gone] + added
        db["build"] = n
        db["note"] = db["note"].replace(o, n)
        with open(DB, "w") as f:
            json.dump(db, f, ensure_ascii=False, separators=(",", ":"))
    return log


def check(build):
    """The decoder and the armor and damage tables against ForeverChanges' cached tooltips (tools/.loot-cache), which
    must be of a build with the same item tables."""
    from scavenge_items import fc_items, fc_parse
    fc, meta = fc_items()
    print("ForeverChanges' files: build %s; decoding build %s" % (meta.get("forever_build"), build))
    B = Build(build)
    agree, differ, ex = collections.Counter(), collections.Counter(), collections.defaultdict(list)
    arm, dmg = collections.Counter(), collections.Counter()
    for iid, f in fc.items():
        r = B.sparse.get(iid)
        if not r or f.get("t") not in ("new", "changed", "same"):
            continue
        dec, p = decode(r, B.rpp), fc_parse(f, {})
        if dec:
            for k in set(dec[0]) | {k for k in p["stats"] if k in STAT_KEYS}:
                if dec[0].get(k) == p["stats"].get(k):
                    agree[k] += 1
                else:
                    differ[k] += 1
                    ex[k].append((iid, f["n"], dec[0].get(k), p["stats"].get(k)))
            for line in dec[1]:
                (agree if line in (f.get("x") or []) else differ)["(Equip line)"] += 1
        ir = B.item.get(iid, {})
        m = B.armor(r, ir)
        if m and p.get("armor"):
            arm["exact" if half_up(m) == p["armor"] else "off"] += 1
        d = B.damage(r, ir)
        if d and p.get("damage"):
            lo, hi = [int(x) for x in p["damage"].split("-")]
            dmg["exact" if _dmg_rounding(d, lo, hi) else "off"] += 1
    for k in sorted(set(agree) | set(differ)):
        print("  %-20s agree %5d  differ %4d  %s" % (k, agree[k], differ[k], ex[k][:2]))
    print("armor from the tables:", dict(arm), " melee damage:", dict(dmg))
    print("A stat that differs is one ForeverChanges also reads from an Equip spell (Classic's \"+1% hit\") or server data.")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--check"]:
        check(sys.argv[2])
        sys.exit(0)
    log = run(sys.argv[1], sys.argv[2], "--write" in sys.argv)
    for kind, iid, msg in log:
        print("%-8s %-7s %s" % (kind, iid, msg))
    print(collections.Counter(k for k, _, _ in log), "written" if "--write" in sys.argv else "(dry run)")
