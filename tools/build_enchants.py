#!/usr/bin/env python3
"""plan/enchants.json: every permanent enchant a player can put on gear in WoW: Forever, from the beta client.

An enchant here is an item you use on a piece of gear: Forever's Enchanting scrolls (Enchant Boots - Agility and the
rest, items 273458-273635, made by enchanters and usable by anyone), armor kits, scopes, counterweights and weapon
chains, shield spikes, the librams' arcanums, the Zandalar and Argent Dawn head and leg and shoulder enchants, and
Naxxramas' Scourge shoulder enchants. The client says what each does: the item's Use casts a spell whose "enchant
item" effect names a SpellItemEnchantment row; that row's effects are flat stats (type 5, an item stat id), an equip
spell (type 3, read like any buff), armor (4), weapon damage (2) or a proc (1). The same spell's SpellEquippedItems
row says which slots and weapon kinds take it. The recipe that makes the item (codex/recipes.json) says the
profession and skill; the Enchanting scrolls are matched to their recipe by name.

What is left out: temporary enchants (oils, sharpening stones, poisons: SpellItemEnchantment rows with a duration),
Blizzard's QA test scrolls, and items the client keeps from Season of Discovery that Forever never shows (not in
plan/items-db.json). The reflect enchants (shield spikes, Retricutioner) come from tools/apply_reflect.py with their
damage numbers and keep their old ids, so saved plans still find them.

  python3 tools/build_enchants.py            # writes plan/enchants.json
  python3 tools/build_enchants.py --selftest # checks known enchants against the client, writes nothing
Run after apply_reflect.py and build_professions.py (it reads items-db, recipes.json and the client tables).
"""
import json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import apply_reflect as ar
import apply_effects as ae

ROOT = ar.ROOT
OUT = os.path.join(ROOT, "plan", "enchants.json")
RECIPES = os.path.join(ROOT, "codex", "recipes.json")

# item stat ids (ItemSparse / SpellItemEnchantment type 5) -> the Forge's stat keys
ITEM_STAT = {3: "agility", 4: "strength", 5: "intellect", 6: "spirit", 7: "stamina", 12: "defense", 13: "dodge", 14: "parry",
             15: "blockChance", 31: "hit", 32: "crit", 36: "haste", 37: "expertise", 38: "attackPower", 39: "rangedAttackPower",
             41: "healing", 42: "spellDamage", 43: "mp5", 45: "spellPower", 46: "hp5", 47: "spellPiercing", 48: "blockValue",
             50: "bonusArmor", 51: "fireResist", 52: "frostResist", 53: "holyResist", 54: "shadowResist", 55: "natureResist",
             56: "arcaneResist", 84: "holySpellDamage", 85: "fireSpellDamage", 86: "natureSpellDamage", 87: "frostSpellDamage",
             88: "shadowSpellDamage", 89: "arcaneSpellDamage", 114: "skinning", 124: "spirit"}
# auras the buff reader (apply_effects.aura_stat) does not map but an enchant uses as a plain stat
AURA_EXTRA = {"49": "dodge", "51": "blockChance", "65": "haste", "342": "haste", "140": "haste", "319": "haste", "290": "crit"}
SKILL_STAT = {"95": "defense", "182": "herbalism", "186": "mining", "393": "skinning", "356": "fishing", "762": "riding"}
# inventory types (SpellEquippedItems.EquippedItemInvTypes bits) -> the Forge's slot keys and the item slots they hold
INV = {1: ("head", "head"), 2: ("neck", "neck"), 3: ("shoulder", "shoulder"), 5: ("chest", "chest"), 20: ("chest", "chest"),
       6: ("waist", "waist"), 7: ("legs", "legs"), 8: ("feet", "feet"), 9: ("wrist", "wrist"), 10: ("hands", "hands"),
       11: ("finger", "finger"), 12: ("trinket", "trinket"), 16: ("back", "back"), 14: ("offhand", "off-hand"),
       23: ("offhand", "off-hand"), 13: ("mainhand", "one-hand"), 17: ("mainhand", "two-hand"), 21: ("mainhand", "main-hand"),
       22: ("offhand", "off-hand"), 15: ("ranged", "ranged"), 26: ("ranged", "ranged"), 25: ("ranged", "thrown"), 28: ("ranged", "relic")}
# weapon subclasses (EquippedItemSubclass bits, class 2) -> item type, and whether one- or two-handed
WEAPON = {0: ("Axe", 1), 1: ("Axe", 2), 2: ("Bow", 0), 3: ("Gun", 0), 4: ("Mace", 1), 5: ("Mace", 2), 6: ("Polearm", 2),
          7: ("Sword", 1), 8: ("Sword", 2), 10: ("Staff", 2), 13: ("Fist Weapon", 1), 15: ("Dagger", 1), 18: ("Crossbow", 0),
          19: ("Wand", 0), 20: ("Fishing Pole", 2)}
SKIP_NAMES = re.compile(r"^(QA|Test|TEST)\b")


def rows(table):
    return ar._rows(table)


def load():
    db = json.load(open(ar.DB))
    by = {str(i["id"]): i for i in db["items"]}
    rec = json.load(open(RECIPES))["recipes"]
    rec_by_item, rec_by_name = {}, {}
    for r in rec:
        if r.get("m"): rec_by_item.setdefault(str(r["m"]), r)
        rec_by_name.setdefault(r["n"], r)
    return db, by, rec_by_item, rec_by_name


def enchant_stats(c, ench, se):
    """(stats, notes) for one SpellItemEnchantment row: flat stats and buff-like equip spells become stats; the rest a note."""
    st, notes = {}, []
    def add(k, v):
        if v: st[k] = round(st.get(k, 0) + v, 2)
    for i in range(3):
        t, arg, pts = ench["Effect_%d" % i], int(ench["EffectArg_%d" % i] or 0), ar.num(ench["EffectPointsMin_%d" % i])
        if t == "0": continue
        if t == "5":
            k = ITEM_STAT.get(arg)
            if k: add(k, pts)
            else: notes.append("stat %d +%s" % (arg, pts))
        elif t == "4":
            add("bonusArmor", pts)
        elif t == "2":
            add("weaponDamage", pts)
        elif t == "1":
            notes.append("proc: " + (c.name.get(str(arg)) or "spell %d" % arg))
        elif t == "3":
            for e in se.get(str(arg), []):
                m = ae.aura_stat(e)
                if m:
                    for k, v in m.items(): add(k, v)
                    continue
                aura, misc, v = e["EffectAura"], int(e["EffectMiscValue_0"] or 0), ar.num(e["EffectBasePointsF"])
                if aura in AURA_EXTRA:
                    k = AURA_EXTRA[aura]
                    if k == "haste": st[k] = max(st.get(k, 0), v)  # melee, ranged and spell haste auras: one number
                    else: add(k, v)
                elif aura == "30" and str(misc) in SKILL_STAT: add(SKILL_STAT[str(misc)], v)
                elif aura == "43": pass  # damage shield: the reflect tool carries it as rf
                else: notes.append("aura %s%s %s" % (aura, " (%d)" % misc if misc else "", v))
        else:
            notes.append("effect type %s" % t)
    return st, notes


def fits(eqrow):
    """(slot keys, item slots, item types) from a SpellEquippedItems row; None where anything goes."""
    if not eqrow: return [], None, None
    cls, sub, inv = int(eqrow["EquippedItemClass"] or 0), int(eqrow["EquippedItemSubclass"] or 0), int(eqrow["EquippedItemInvTypes"] or 0)
    slots, islots, itypes = [], [], []
    if cls == 2:
        hands = set()
        for bit, (tname, h) in WEAPON.items():
            if sub & (1 << bit):
                itypes.append(tname); hands.add(h)
        if 1 in hands: slots += ["mainhand", "offhand"]; islots += ["one-hand", "main-hand", "off-hand"]
        if 2 in hands: slots.append("mainhand"); islots.append("two-hand")
        if 0 in hands: slots.append("ranged"); islots.append("ranged")
    else:
        for bit, (slot, islot) in INV.items():
            if inv & (1 << bit):
                slots.append(slot); islots.append(islot)
        if inv & (1 << 14): itypes.append("Shield")
        if not inv and sub & ((1 << 6) | (1 << 5)):  # armor subclass shield (or buckler), no inventory mask: the spikes
            slots.append("offhand"); islots.append("off-hand"); itypes.append("Shield")
        if inv & (1 << 23): itypes.append("none")  # a held off-hand (no weapon type)
        if inv & (1 << 13): islots += ["one-hand", "main-hand", "off-hand"]
    def uniq(xs): return sorted(set(xs), key=xs.index) if xs else None
    return uniq(slots) or [], uniq(islots), uniq(itypes)


def build(selftest=False):
    c = ar.Client()
    db, by, rec_by_item, rec_by_name = load()
    ench_rows = {r["ID"]: r for r in rows("SpellItemEnchantment")}
    eq = {r["SpellID"]: r for r in rows("SpellEquippedItems")}
    reflect = {str(e["item"]): e for e in ar.enchants(c, by)["enchants"]}
    out, skipped = [], {"temporary": 0, "qa": 0, "not-in-forever": 0, "no-enchantment": 0}
    for iid, effs in sorted(c.ixe.items(), key=lambda kv: int(kv[0])):
        it = by.get(iid)
        if not it or not it.get("ft"):
            skipped["not-in-forever"] += 1 if any(any(x["Effect"] == "53" for x in c.se.get(e["SpellID"], [])) for e in effs if e["TriggerType"] == "0") else 0
            continue
        if SKIP_NAMES.match(it["name"]):
            skipped["qa"] += 1; continue
        for e in effs:
            if e["TriggerType"] != "0": continue
            sid = e["SpellID"]
            encs = [x["EffectMiscValue_0"] for x in c.se.get(sid, []) if x["Effect"] == "53"]
            if not encs: continue
            stats, notes, names = {}, [], []
            for eid in encs:
                row = ench_rows.get(eid)
                if not row: skipped["no-enchantment"] += 1; continue
                if int(row["Duration"] or 0) > 0: skipped["temporary"] += 1; continue
                s, n = enchant_stats(c, row, c.se)
                for k, v in s.items(): stats[k] = round(stats.get(k, 0) + v, 2)
                notes += n; names.append(row["Name_lang"])
            if not names: continue
            slots, islots, itypes = fits(eq.get(sid))
            if not slots: continue
            use = next((x[5:] for x in it.get("effects", []) if x.startswith("Use: ")), "")
            # the client's weapon mask lists kinds, not hands: a "2H Weapon" scroll's mask names the axe, mace and
            # sword kinds that come in both; the item's own name and Use line say two-handed, and the server goes by that
            if islots and "two-hand" in islots and re.search(r"\b2H Weapon\b|two-handed", it["name"] + " " + use, re.I):
                slots, islots = ["mainhand"], ["two-hand"]
                itypes = [t for t in (itypes or []) if t in ("Axe", "Mace", "Sword", "Polearm", "Staff", "Fishing Pole")] or itypes
            rec = rec_by_item.get(iid) or rec_by_name.get(it["name"])
            en = {"id": "i" + iid, "item": int(iid), "name": it["name"], "slot": slots if len(slots) > 1 else slots[0],
                  "stats": stats, "fx": use, "ench": [int(x) for x in encs], "spell": int(sid), "icon": it.get("icon"),
                  "q": it.get("quality")}
            if islots: en["itSlot"] = islots
            if itypes: en["itType"] = itypes
            if it.get("reqLevel", 1) > 1: en["lvl"] = it["reqLevel"]
            lvl_min = max(int((ench_rows.get(x) or {}).get("ItemLevelMin") or 0) for x in encs)
            if lvl_min: en["ilvlMin"] = lvl_min
            if notes: en["raw"] = "; ".join(notes)  # the client rows the Forge cannot count (procs, threat, speed): fx says it in words
            if rec:
                en["skill"] = [rec["p"], rec.get("sk") or (rec.get("c") or [None])[0]]
                en["made"] = {"p": rec["p"], "s": rec["s"], "sk": rec.get("sk"), "c": rec.get("c")}
                if rec.get("by"): en["made"]["by"] = rec["by"]
            else:
                en["skill"] = None
            for k in ("quests", "drops", "cls", "binding"):
                if it.get(k): en[k] = it[k]
            r = reflect.pop(iid, None)
            if r:
                en["id"], en["rf"] = r["id"], r["rf"]
                if r.get("note"): en["note"] = r["note"]
                if r.get("skill"): en["skill"] = r["skill"]
            out.append(en)
    for r in reflect.values():  # a reflect enchant whose item the walk above did not reach (none today)
        out.append(r)
    out.sort(key=lambda e: ([e["slot"]] if isinstance(e["slot"], str) else e["slot"], e.get("lvl") or 0, e["name"]))
    doc = {"note": "Every permanent enchant a player can put on gear, from the beta client's item and spell tables (build %s, "
                   "tools/build_enchants.py): Forever's Enchanting scrolls, armor kits, scopes, spikes and chains, librams and "
                   "the Zandalar, Argent Dawn and Scourge enchants. stats are what the Forge counts; fx is the item's own Use "
                   "line; skill is the profession level needed to make it, not to use it; rf (shield spikes, Retricutioner) is "
                   "the damage to attackers from tools/apply_reflect.py." % ar.BUILD,
           "build": ar.BUILD, "enchants": out}
    if selftest:
        byn = {}
        for e in out: byn.setdefault(e["name"], e)
        b = byn["Enchant Boots - Agility"]; assert b["stats"] == {"agility": 5} and b["slot"] == "feet" and b["skill"] == ["Enchanting", 235], b
        k = byn["Heavy Armor Kit"]; assert k["stats"].get("bonusArmor") == 24 and k["stats"].get("stamina") and set(k["slot"]) == {"chest", "legs", "hands", "feet"}, k
        cr = byn["Enchant Weapon - Crusader"]; assert cr["slot"] == ["mainhand", "offhand"] and set(cr["itType"]) >= {"Sword", "Axe", "Mace", "Dagger", "Fist Weapon"} and "proc" in cr["raw"] and cr["stats"] == {}, cr
        two = byn["Enchant 2H Weapon - Agility"]; assert two["slot"] == "mainhand" and two["itSlot"] == ["two-hand"] and two["stats"] == {"agility": 25}, two
        gi = byn["Enchant 2H Weapon - Grand Inquisitor"]; assert gi["slot"] == "mainhand" and gi["itSlot"] == ["two-hand"], gi
        sp = byn["Iron Shield Spike"]; assert sp["id"] == "iron-spike" and sp["rf"]["k"] == "block" and sp["itType"] == ["Shield"] and sp["slot"] == "offhand", sp
        ret = byn["Enchant Chest - Retricutioner"]; assert ret["id"] == "retricutioner" and ret["rf"] and ret["slot"] == "chest", ret
        oh = byn["Enchant Off-Hand - Excellent Spirit"]; assert oh["slot"] == "offhand" and oh["itType"] == ["none"] and oh["stats"] == {"spirit": 12}, oh
        sc = byn["Crude Scope"]; assert sc["slot"] == "ranged" and sc["stats"] == {"weaponDamage": 1} and set(sc["itType"]) >= {"Bow", "Gun"} and sc["skill"] == ["Engineering", 60], sc
        nk = byn["Enchant Necklace - Agility"]; assert nk["slot"] == "neck" and nk["stats"] == {"agility": 5}, nk
        arc = byn["Arcanum of Rapidity"]; assert set(arc["slot"]) == {"head", "legs"} and arc["stats"] == {"haste": 1}, arc
        assert all(isinstance(e["slot"], (str, list)) and e["name"] and e["fx"] for e in out)
        assert not any(SKIP_NAMES.match(e["name"]) for e in out)
        ids = [e["id"] for e in out]; assert len(ids) == len(set(ids)), "ids unique"
        print("selftest ok: %d enchants; skipped %s" % (len(out), skipped))
        return doc
    with open(OUT, "w") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
        f.write("\n")
    from collections import Counter
    slots = Counter((e["slot"] if isinstance(e["slot"], str) else "+".join(e["slot"])) for e in out)
    print("wrote plan/enchants.json: %d enchants (%d with stats, %d with a note only); skipped %s" %
          (len(out), sum(1 for e in out if e["stats"]), sum(1 for e in out if not e["stats"] and not e.get("rf")), skipped))
    print("  by slot:", ", ".join("%s %d" % kv for kv in slots.most_common()))
    return doc


if __name__ == "__main__":
    build(selftest="--selftest" in sys.argv)
