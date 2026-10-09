#!/usr/bin/env python3
"""Every profession recipe in the Forever client: codex/recipes.json for the Database's Crafting list.

A recipe is a spell on a profession's skill line (SkillLineAbility) that uses reagents (SpellReagents).
From the client build (research/wago/<BUILD>/, pulled by tools/fetch_wago.py):
  product     SpellEffect 24 (create item): EffectItemType, count EffectBasePointsF
  enchant     SpellEffect 53 (enchant item): no product, the spell's own tooltip says what it does
  reagents    SpellReagents Reagent_0..7 / ReagentCount_0..7
  station     SpellCastingRequirements.RequiresSpellFocus -> SpellFocusObject (Anvil, Tanning Rack, Spinning Wheel ...)
  skill-ups   SkillLineAbility: yellow from TrivialSkillLineRankLow, grey from TrivialSkillLineRankHigh (green is not
              stored; the page works it out by Classic's rule and says so)
  taught by   items whose ItemEffect (trigger 6, learn spell) is the recipe; their ItemSparse.RequiredSkillRank is the
              skill needed to learn it. Server-sent recipe items the client has no effect row for are matched from
              plan/items-db.json by their "Teaches you how to craft X." text, with their recorded skill.
  class       SkillRaceClassInfo: Poisons and Comprehension belong to one class each
SkillLineAbility rows the client marks never learned (AcquireMethod 3) are left out: Alchemy's healing potions and
curatives and Basic Campfire are 3 in Forever but learned (0 or 1) in the Classic Era client, so Forever took them out.
Season of Discovery leftovers: a recipe whose spell the Classic Era/SoD client also has (spell ID 400,000 and up) is
SoD's, marked e "sod", unless an item new in Forever teaches or makes it (then it is Forever's, marked rs: SoD's spell
reused).
Recipes no item teaches: the skill a Classic trainer asks for, from the CMaNGOS Classic database
(research/cmangos, GPL-3.0; npc_trainer_template), labelled as Classic data. A trainer row names the trainer's
teaching spell, which only the Classic Era client still has: its SpellEffect 36 (learn spell) names the recipe.
Trainer lists, prices and Merchant's Favor costs are server data the client lacks.
Names, icons and quality come from plan/items-db.json, else from ItemSparse.

  python3 tools/build_professions.py                 # newest build below
  python3 tools/build_professions.py 1.60.1.70291    # a given build
Needs SpellCastingRequirements and SpellFocusObject: python3 tools/fetch_wago.py BUILD SpellCastingRequirements SpellFocusObject
and the Classic Era build's SpellEffect and SpellName: python3 tools/fetch_wago.py 1.15.9.70003 SpellEffect SpellName
"""
import collections, csv, datetime, gzip, json, os, re, sys

csv.field_size_limit(1 << 30)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, os.path.join(ROOT, "tools", "questbank"))
BUILD = sys.argv[1] if len(sys.argv) > 1 else "1.60.1.70291"
ERA = "1.15.9.70003"  # a Classic Era build, for the trainers' teaching spells
OUT = os.path.join(ROOT, "codex", "recipes.json")
CMANGOS = os.path.join(ROOT, "research", "cmangos", "ClassicDB.sql.gz")

# profession skill lines (SkillLine.ID -> the name the Database's profession filter uses)
PROFS = {164: "Blacksmithing", 165: "Leatherworking", 171: "Alchemy", 182: "Herbalism", 185: "Cooking", 186: "Mining",
         197: "Tailoring", 202: "Engineering", 333: "Enchanting", 356: "Fishing", 393: "Skinning", 129: "First Aid",
         40: "Poisons", 3012: "Comprehension"}
QUAL = ["poor", "common", "uncommon", "rare", "epic", "legendary", "artifact", "heirloom"]
# what a recipe item says it teaches: "Teaches you how to craft Prefect's Waistguard."
TEACH = re.compile(r"Teaches you how to (?:make|craft|create|cook|brew|mix|forge|sew|build|smelt|prepare|construct) (?:an? |the )?(.+?)\.(?:\s|$)", re.I)
CLASSBIT = {1: "Warrior", 2: "Paladin", 4: "Hunter", 8: "Rogue", 16: "Priest", 64: "Shaman", 128: "Mage", 256: "Warlock", 1024: "Druid"}
DEV = re.compile(r"\[DNT\]|\bDNT\b|\bTest\b|\bQA\b|\(old\)|Deprecated|^zz|PLACEHOLDER", re.I)


def rows(table, build=None):
    build = build or BUILD
    path = os.path.join(ROOT, "research", "wago", build, table + ".csv")
    if not os.path.exists(path):
        sys.exit("missing %s: python3 tools/fetch_wago.py %s %s" % (path, build, table))
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def icon_names():
    """FileDataID -> icon name, from the listfile the other builders use."""
    out = {}
    for line in open(os.path.join(ROOT, "tools", "icon-listfile.csv"), encoding="utf-8"):
        fid, _, path = line.strip().partition(";")
        if path.startswith("interface/icons/"):
            out[fid] = path[16:].rsplit(".", 1)[0]
    return out


def classic_trainers():
    """The skill a Classic profession trainer asks for each teaching spell: {spell: (skill line, skill)}."""
    import cmangos
    cols, out, table = {}, {}, None
    with gzip.open(CMANGOS, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("CREATE TABLE `"):
                table = line.split("`")[1]
                cols[table] = []
            elif table and line.startswith("  `"):
                cols[table].append(line.split("`")[1].lower())
            elif line.startswith("INSERT INTO `npc_trainer"):
                t = line.split("`")[1]
                idx = {c: k for k, c in enumerate(cols[t])}
                for r in cmangos.rows_of(line[line.index("VALUES") + 6:].strip().rstrip(";")):
                    sk, val = r[idx["reqskill"]], r[idx["reqskillvalue"]]
                    if sk in PROFS:
                        old = out.get(r[idx["spell"]])
                        if not old or val < old[1]:
                            out[r[idx["spell"]]] = (sk, val)
    return out


def main():
    today = datetime.date.today().isoformat()
    db = json.load(open(os.path.join(ROOT, "plan", "items-db.json")))
    byid = {str(x["id"]): x for x in db["items"]}
    sparse = {r["ID"]: r for r in rows("ItemSparse")}
    names = {r["ID"]: r["Name_lang"] for r in rows("SpellName")}
    icons = icon_names()
    spell_icon = {r["SpellID"]: icons.get(r["SpellIconFileDataID"]) for r in rows("SpellMisc") if r["DifficultyID"] == "0"}

    sla = [r for r in rows("SkillLineAbility") if int(r["SkillLine"]) in PROFS]
    era_spells = {r["ID"] for r in rows("SpellName", ERA)}  # what the Classic Era/SoD client has
    prof_cls = {}  # a profession only one class can learn (Poisons: Rogue)
    for r in rows("SkillRaceClassInfo"):
        if int(r["SkillID"]) in PROFS and CLASSBIT.get(int(r["ClassMask"] or 0)):
            prof_cls[PROFS[int(r["SkillID"])]] = CLASSBIT[int(r["ClassMask"])]
    reag = {r["SpellID"]: r for r in rows("SpellReagents")}
    focus = {r["ID"]: r["Name_lang"] for r in rows("SpellFocusObject")}
    station = {r["SpellID"]: focus.get(r["RequiresSpellFocus"]) for r in rows("SpellCastingRequirements") if r["RequiresSpellFocus"] not in ("", "0")}

    want = {r["Spell"] for r in sla}
    eff = collections.defaultdict(list)
    for r in rows("SpellEffect"):
        if r["SpellID"] in want and r["DifficultyID"] == "0":
            eff[r["SpellID"]].append(r)
    # a Classic trainer's teaching spell -> the recipe it teaches (the Era client's SpellEffect 36, learn spell)
    trainer = classic_trainers()
    learns = collections.defaultdict(list)
    for r in rows("SpellEffect", ERA):
        if r["Effect"] == "36" and int(r["SpellID"]) in trainer:
            learns[int(r["SpellID"])].append(r["EffectTriggerSpell"])
    taught_skill = {}
    for ts, (sk, val) in trainer.items():
        for t in [str(ts)] + learns.get(ts, []):
            if t in want and (t not in taught_skill or val < taught_skill[t]):
                taught_skill[t] = val

    # recipe items: ItemEffect trigger 6 (learn spell) -> the recipe they teach
    ie = {r["ID"]: r for r in rows("ItemEffect")}
    teaches = collections.defaultdict(list)
    for r in rows("ItemXItemEffect"):
        e = ie.get(r["ItemEffectID"])
        if e and e["TriggerType"] == "6" and e["SpellID"] != "0":
            teaches[e["SpellID"]].append(r["ItemID"])

    from spelltext import Client
    client = Client(BUILD)
    used = set()

    def item_ok(iid):
        return iid in byid or iid in sparse

    def forever_item(iid):
        """An item Forever's own sources show as new to Forever, not a branch leftover."""
        it = byid.get(iid)
        return bool(it and not it.get("era") and (it.get("nw") or it.get("ft") == "new") and it.get("tt") == "forever")

    out, skipped, seen = [], collections.Counter(), set()
    for r in sla:
        sid = r["Spell"]
        n = names.get(sid)
        rg = reag.get(sid)
        if not n or DEV.search(n):
            skipped["no name or dev row"] += 1
            continue
        if r["AcquireMethod"] == "3":
            skipped["never learned (client)"] += 1
            continue
        if (sid, r["SkillLine"]) in seen:
            skipped["duplicate row"] += 1
            continue
        seen.add((sid, r["SkillLine"]))
        parts = [(rg["Reagent_%d" % k], int(rg["ReagentCount_%d" % k] or 0)) for k in range(8)] if rg else []
        parts = [[int(i), c] for i, c in parts if i not in ("", "0") and c > 0]
        if not parts:
            skipped["no reagents"] += 1
            continue
        es = eff.get(sid, [])
        made = [e for e in es if e["Effect"] == "24" and e["EffectItemType"] not in ("", "0")]
        rec = {"s": int(sid), "n": n, "p": PROFS[int(r["SkillLine"])], "r": parts}
        lo, hi = int(r["TrivialSkillLineRankLow"] or 0), int(r["TrivialSkillLineRankHigh"] or 0)
        if hi:
            rec["c"] = [lo, hi]
        if made:
            m = made[0]
            rec["m"] = int(m["EffectItemType"])
            cnt = int(float(m["EffectBasePointsF"] or 1))
            if cnt > 1:
                rec["k"] = cnt
            if float(m["Variance"] or 0) > 0:
                rec["kv"] = 1  # the count varies; how much is not stated plainly
            used.add(m["EffectItemType"])
            it = byid.get(m["EffectItemType"])
            if it:
                rec["n"] = it["name"]  # what you make, as the item is called
        else:
            txt = client.text(int(sid)) or ""
            if txt:
                rec["fx"] = txt
        if station.get(sid):
            rec["at"] = station[sid]
        by = [i for i in teaches.get(sid, []) if item_ok(i)]
        if by:
            rec["by"] = [int(i) for i in by]
            used.update(by)
            ranks = [int(sparse[i]["RequiredSkillRank"] or 0) for i in by if i in sparse]
            ranks = [x for x in ranks if x > 0]
            if not ranks:  # a server-sent recipe item: the skill its own tooltip asks for
                ranks = [int(byid[i]["sk"][1]) for i in by if i in byid and byid[i].get("sk") and byid[i]["sk"][1]]
            if ranks:
                rec["sk"] = min(ranks)
        if "sk" not in rec and sid in taught_skill:
            rec["sk"], rec["cl"] = taught_skill[sid], 1  # Classic trainer
        if r["AcquireMethod"] in ("1", "2") and "by" not in rec:
            rec["auto"] = 1  # comes with the profession itself
            rec.setdefault("sk", 1)
        for i, _ in parts:
            used.add(str(i))
        out.append(rec)

    # Server-sent recipe items (plan/items-db.json) the client has no learn-spell row for: matched by what their text
    # says they teach, within their profession, to a recipe no item teaches yet. Only an unambiguous match counts.
    linked = {str(i) for x in out for i in x.get("by", [])}
    named = collections.defaultdict(list)
    for x in out:
        named[x["n"].lower()].append(x)
    by_text = 0
    for it in db["items"]:
        if it.get("cat") != "recipe" or it["id"] in linked or not it.get("sk"):
            continue
        m = TEACH.search(" ".join([it.get("flavor") or ""] + (it.get("effects") or [])))
        if not m:
            continue
        cand = [x for x in named.get(m.group(1).strip().lower(), []) if x["p"] == it["sk"][0] and "by" not in x]
        if len(cand) != 1:
            continue
        x = cand[0]
        x["by"] = [int(it["id"])]
        used.add(it["id"])
        if it["sk"][1]:
            x["sk"] = it["sk"][1]
            x.pop("cl", None)
            x.pop("auto", None)
        by_text += 1

    for rec in out:
        sid = str(rec["s"])
        ids = ([str(rec["m"])] if "m" in rec else []) + [str(i) for i in rec.get("by", [])]
        # era: SoD or retail leftovers ride the branch; the product (or the item teaching it) says so
        eras = [byid[i].get("era") for i in ids if i in byid]
        era = next((e for e in eras if e), None)
        if not era and "m" not in rec:
            s = int(sid)
            era = "sod" if 400000 <= s < 470000 else "retail" if 470000 <= s < 1200000 else None
        # a spell the Classic Era/SoD client also has, from SoD's ID range on, is SoD's: a leftover, unless an item new
        # in Forever teaches or makes it (Forever reused the spell)
        if int(sid) >= 400000 and sid in era_spells:
            if any(forever_item(i) for i in ids):
                rec["rs"] = 1
            else:
                era = era or "sod"
        if era:
            rec["e"] = era
        # new in Forever: what it makes or what teaches it is new; else, when the product's history is unknown, a
        # Forever-range spell ID the Era client lacks. Never on a leftover.
        prod = byid.get(str(rec.get("m")))
        if era:
            pass
        elif rec.get("rs") or prod and (prod.get("nw") or prod.get("ft") == "new"):
            rec["nw"] = 1
        elif not (prod and prod.get("ft") in ("same", "changed")) and int(sid) >= 1200000 and sid not in era_spells:
            rec["nw"] = 1
        if rec["p"] in prof_cls:
            rec["cls"] = prof_cls[rec["p"]]
        ic = (prod or {}).get("icon") or spell_icon.get(sid)
        if ic:
            rec["i"] = ic

    # a product in no item table (a server-sent item): named after its recipe, flagged so the page says so
    unlisted = {str(x["m"]): x for x in out if "m" in x and not item_ok(str(x["m"]))}
    items = {}
    for i in sorted(used, key=int):
        it = byid.get(i)
        if it:
            items[i] = [it["name"], it.get("quality") or "common", it.get("icon") or ""]
        elif i in sparse:
            q = int(sparse[i]["OverallQualityID"] or 1)
            items[i] = [sparse[i]["Display_lang"], QUAL[q] if 0 <= q < len(QUAL) else "common", ""]
        elif i in unlisted:
            items[i] = [unlisted[i]["n"], "unknown", "", 1]  # the recipe spell's icon is no guide to the item's
    out.sort(key=lambda x: (x["p"], x.get("sk") or (x.get("c") or [0])[0], x["n"]))
    by_prof = collections.Counter(x["p"] for x in out)
    note = ("Profession recipes in the WoW: Forever beta client, build %s (tools/build_professions.py): recipe, reagents, "
            "product, crafting station and the yellow and grey skill-up thresholds from the client's own tables (green is "
            "not stored). The skill to learn a recipe comes from the recipe item that teaches it (the client's item table, "
            "else the item's own tooltip); where no item teaches it, it is the Classic trainer's requirement from the "
            "CMaNGOS Classic database, marked cl, until Forever's trainers are recorded. Rows marked e are Season of "
            "Discovery or retail leftovers on the branch (the Classic Era/SoD client has the spell); rs marks an SoD spell "
            "that an item new in Forever teaches; nw marks recipes new in Forever (the product or that item is new, or, "
            "where the product's history is unknown, a Forever-range spell ID the Era client lacks); cls is the one class "
            "that can learn the profession. An items entry with a fourth value 1 is a server-sent product in no item table, "
            "named after its recipe." % BUILD)
    json.dump({"note": note, "build": BUILD, "generated": today, "counts": dict(sorted(by_prof.items())),
               "recipes": out, "items": items},
              open(OUT, "w"), ensure_ascii=False, separators=(",", ":"))
    print("wrote %s: %d recipes, %d items" % (os.path.relpath(OUT, ROOT), len(out), len(items)))
    print("  by profession:", dict(by_prof.most_common()))
    print("  skipped:", dict(skipped))
    print("  era:", dict(collections.Counter(x.get("e") for x in out)), "new:", sum(1 for x in out if x.get("nw")))
    keep = [x for x in out if not x.get("e")]
    print("  without leftovers: %d recipes, %d new in Forever, %d SoD spells Forever reuses, %d make an unlisted item" % (
        len(keep), sum(1 for x in keep if x.get("nw")), sum(1 for x in keep if x.get("rs")),
        sum(1 for x in keep if str(x.get("m")) in unlisted)))
    print("  recipe items matched by their text: %d" % by_text)
    for label, rs in (("all", out), ("without leftovers", keep)):
        print("  skill from (%s): item %d, Classic trainer %d, with the profession %d, unknown %d" % (
            label, sum(1 for x in rs if "by" in x and "sk" in x), sum(1 for x in rs if x.get("cl")),
            sum(1 for x in rs if x.get("auto")), sum(1 for x in rs if "sk" not in x)))
    print("  station (without leftovers):", dict(collections.Counter(x.get("at") for x in keep if x.get("at")).most_common(8)))


if __name__ == "__main__":
    main()
