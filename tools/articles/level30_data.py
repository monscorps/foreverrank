#!/usr/bin/env python3
"""Tooltip data for the "Level 30, build by build" article (news/level-30/).

Spell and talent texts are resolved from the client's own tables in
research/wago/<build>/ (tools/spelltext.py), before and after, with icons from
SpellMisc. Item numbers are the client's ItemSparse rows for 70170 and 70291,
decoded with the item budget (the same reading as tools/apply_items.py, plus
the spell-school and healing stats it does not decode yet); they are written
out below so the article does not depend on a half-carried items-db.

  python3 tools/articles/level30_data.py      # writes tools/articles/level-30.data.json
  python3 tools/articles/build.py level-30    # then build the page
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE)))
from spelltext import Client  # noqa: E402
from apply_talents import icon_names  # noqa: E402

B0, B1, B2 = "1.60.1.70009", "1.60.1.70170", "1.60.1.70291"
SHORT = {B0: "70009", B1: "70170", B2: "70291"}

# (key, spell id, max rank or 0 for a plain spell, build it changed in, extras)
TALENTS = [
    ("WARRIOR", "Booming Voice", 12321, 5, B2, {}),
    ("WARRIOR", "Unbridled Wrath", 12322, 5, B2, {}),
    ("WARRIOR", "Dual Wield Specialization", 23584, 5, B2,
        {"note": "In between, build 70170 had no off-hand Rage bonus and kept the 10% off-hand hit."}),
    ("WARRIOR", "Bloodthirst", 23881, 1, B2, {}),
    ("WARRIOR", "Improved Slam", 12862, 2, B2, {}),
    ("WARRIOR", "Raging Blows", 1310315, 1, B2, {}),
    ("WARRIOR", "Furious Precision", 1323963, 3, B2, {"added": True}),
    ("WARRIOR", "Lingering Rage", 1323964, 5, B2, {"added": True}),
    ("WARRIOR", "Gore Drinker", 1323967, 2, B2, {"added": True}),
    ("WARRIOR", "Improved Cleave", 12329, 3, B2, {"gone": True}),
    ("WARRIOR", "Boundless Rage", 1310236, 3, B2, {"gone": True}),
    ("WARRIOR", "Precision", 1225295, 3, B2, {"gone": True}),
    ("WARRIOR", "Toughness", 12299, 5, B2, {"gone": True}),
    ("WARRIOR", "Iron Will", 12962, 5, B2, {"note": "Moved from Fury to Protection, row 1."}),
    ("PALADIN", "Redoubt", 20127, 5, B1, {}),
    ("PALADIN", "Holy Shield", 20925, 1, B1, {}),
    ("PALADIN", "Champion of the Light", 1311084, 3, B1, {}),
    ("PALADIN", "Reckoning", 20177, 5, B2, {}),
    ("HUNTER", "Deflection", 19295, 5, B1, {}),
    ("HUNTER", "Sniper Shot", 1310687, 1, B1, {}),
    ("HUNTER", "Expose Prey", 1310532, 2, B2, {}),
    ("ROGUE", "Setup", 13983, 3, B1, {}),
    ("PRIEST", "Penance", 402174, 1, B2, {}),
    ("PRIEST", "Inner Focus", 14751, 1, B1, {}),
    ("SHAMAN", "Mana Tide Totem", 16190, 1, B2, {"note": "Learned at level 25 now, was 40."}),
    ("SHAMAN", "Water Shield", 408510, 1, B2, {"note": "The client drops a 15 sec cooldown that Blizzard says never applied in play."}),
    ("MAGE", "Combustion", 11129, 1, B1, {}),
    ("MAGE", "Heating Up", 400624, 1, B1, {}),
    ("WARLOCK", "Soul Harvest", 437032, 2, B1, {}),
    ("DRUID", "Shifting Power", 1322605, 1, B1, {"added": True,
        "text": "Instantly convert 55% of base Mana into 40 Energy. Cat Form only. 16 sec cooldown.",
        "note": "Read from the spell's data: the client's tooltip template cannot print its own numbers yet."}),
    ("DRUID", "Improved Shifting Power", 1322670, 2, B1, {"added": True}),
    ("DRUID", "King of the Jungle", 417046, 3, B1, {"gone": True}),
    ("DRUID", "Natural Instinct", 1223242, 2, B2, {}),
]
# plain spells: key, spell id, build
SPELLS = [
    ("Retribution Aura", 10301, B2), ("Thorns", 9910, B2), ("Berserker Rage", 18499, B2),
    ("Fireball", 8400, B2), ("Arcane Missiles", 5145, B2), ("Lightning Bolt", 943, B2), ("Shadow Bolt", 1088, B2),
    ("Smite", 984, B2), ("Lesser Heal", 2053, B2), ("Heal", 2055, B2), ("Wrath", 5179, B2),
    ("Disease Cleansing Totem", 8170, B1), ("Disengage", 781, B1), ("Sonic Blast", 1264482, B1),
    ("Will of the Forsaken", 7744, B2), ("Furious Howl", 24597, B1),
]
NOTES = {
    "Berserker Rage": "Trained at level 30 now, was 32.",
    "Disengage": "Threat drop doubled in the data on 1 October (rank 1: 140 to 280); Blizzard's 8 October notes say it now really applies.",
    "Will of the Forsaken": "Same text. The data now grants a short immunity instead of a dispel, so it works while asleep or charmed.",
    "Sonic Blast": "Added to the Bat pet's abilities, ranks 1 to 5. Rank 5 shown.",
    "Furious Howl": "Wolf pet ability, rank 4 shown. Not in Blizzard's notes.",
    "Retribution Aura": "Rank 5 shown. Blizzard: base damage back to Vanilla, spell power ratio 13.3% to 6%.",
    "Thorns": "Rank 6 shown. Blizzard: base damage back to Vanilla, spell power ratio 13.3% to 6%.",
}

# Items: client ItemSparse 70170 (before) and 70291 (now).
ITEMS = {
    "271667": dict(name="Ironwood Destroyer", slot="two-hand", type="Mace", itemLevel=33, quality="uncommon", oldQuality="rare",
                   stats={"natureSpellDamage": 19}, oldStats={"stamina": 9, "spirit": 7, "attackPower": 24}, quest="Horrors in the Highland"),
    "271664": dict(name="Hornbeam Heft", slot="one-hand", type="Axe", itemLevel=33, quality="uncommon", oldQuality="rare",
                   stats={"strength": 6}, oldStats={"stamina": 6, "strength": 3, "spirit": 3}, quest="Horrors in the Highland"),
    "271670": dict(name="Curl of Life", slot="finger", itemLevel=33, quality="uncommon", oldQuality="rare",
                   stats={"stamina": 5, "spellPower": 5}, oldStats={"stamina": 7, "spellPower": 5, "hp5": 5}, quest="Horrors in the Highland"),
    "271740": dict(name="Knife-Polishing Rag", slot="wrist", type="Cloth", itemLevel=33, quality="uncommon", oldQuality="rare",
                   stats={"spirit": 4, "spellPower": 6}, oldStats={"intellect": 4, "spirit": 7, "spellPower": 5}, quest="Open the Maw"),
    "271732": dict(name="Dirt-Heavy Bracers", slot="wrist", type="Leather", itemLevel=33, quality="uncommon", oldQuality="rare",
                   stats={"spirit": 4, "attackPower": 10}, oldStats={"spirit": 7, "attackPower": 8, "stamina": 4}, quest="Open the Maw"),
    "271769": dict(name="Daewyn's Girdle", slot="waist", type="Cloth", itemLevel=33, quality="uncommon", oldQuality="rare",
                   stats={"spirit": 6, "spellPower": 7}, oldStats={"spirit": 9, "spellPower": 6, "hp5": 10}, quest="Fallen in the Fen"),
    "271716": dict(name="Explorer's League Dustcover", slot="back", itemLevel=33, quality="rare",
                   stats={"intellect": 5, "spirit": 5, "agility": 5}, oldStats={"intellect": 7, "strength": 4, "agility": 4}, quest="Prehistoric Prism"),
    "271719": dict(name="Furs of the Earthen Ring", slot="back", itemLevel=33, quality="rare",
                   stats={"intellect": 5, "strength": 5, "spirit": 5}, oldStats={"intellect": 5, "stamina": 3, "strength": 4, "spirit": 4}, quest="Earthen Echo"),
    "271766": dict(name="Heavehammer", slot="two-hand", type="Mace", itemLevel=33, quality="rare",
                   stats={"attackPower": 32, "bonusArmor": 60}, oldStats={"attackPower": 26, "agility": 7, "bonusArmor": 70}, quest="Earthen Echo"),
    "274957": dict(name="Lumber Luggers", itemLevel=38, oldItemLevel=43, quality="uncommon",
                   stats={"strength": 11}, oldStats={"strength": 13}),
    "274941": dict(name="Bristle Hills Mystic Robe", slot="chest", type="Cloth", itemLevel=40, oldItemLevel=42, quality="uncommon",
                   stats={"intellect": 11, "spellPower": 12}, oldStats={"intellect": 11, "spellPower": 13}),
    "274944": dict(name="Bloodsnout Striker", itemLevel=40, oldItemLevel=42, quality="uncommon",
                   stats={"stamina": 11, "attackPower": 18}, oldStats={"stamina": 12, "attackPower": 20}),
    "8345": dict(name="Wolfshead Helm", slot="head", type="Leather", itemLevel=45, reqLevel=40, quality="rare", stats={"spirit": 10},
                 effects=["Equip: You gain an additional 5 Rage from activating Enrage and an additional 5 Energy from activating Shifting Power."],
                 oldEffects=["Equip: You gain an additional 5 Rage from activating Enrage and an additional 20 Energy from activating Shifting Power."]),
}
# spells that sat unused in the older client and were handed out in this window
FRESH = {"Sonic Blast"}


def main():
    cs = {b: Client(b) for b in (B0, B1, B2)}
    icons = {}
    for b in (B0, B2):
        icons.update(icon_names(b))

    def icon(sp):
        for b in (B2, B1, B0):
            m = cs[b].misc.get(str(sp))
            if m and icons.get(m["SpellIconFileDataID"]):
                return icons[m["SpellIconFileDataID"]]
        return "inv_misc_questionmark"

    spells = {}
    for cls, name, sp, r, b, ex in TALENTS:
        s = str(sp)
        old = None if ex.get("added") else cs[B0].talent_text(sp, r, r)
        new = None if ex.get("gone") else (ex.get("text") or cs[B2].talent_text(sp, r, r))
        e = {"id": sp, "n": name, "icon": icon(sp), "r": r, "b": SHORT[b]}
        if old: e["old"] = old
        if new: e["new"] = new
        if ex.get("gone"): e["gone"] = SHORT[b]
        if ex.get("added"): e["added"] = SHORT[b]
        if ex.get("note"): e["note"] = ex["note"]
        oname = cs[B0].name.get(s)
        if oname and oname != name and not ex.get("added"):
            e["oldName"] = oname
        spells["t:%s:%s" % (cls, name)] = e
    for name, sp, b in SPELLS:
        s = str(sp)
        old = cs[B0].text(sp) if s in cs[B0].spell and name not in FRESH else None
        new = cs[B2].text(sp)
        e = {"id": sp, "n": cs[B2].name.get(s, name), "icon": icon(sp), "b": SHORT[b], "new": new}
        if old and old != new: e["old"] = old
        if not old: e["added"] = SHORT[b]
        # plain spells carry no rank of their own; name it unless the note does
        rank = cs[B2].spell.get(s, {}).get("NameSubtext_lang", "")
        note = NOTES.get(name, "")
        if rank.startswith("Rank ") and "rank" not in note.lower():
            note = (rank + " shown. " + note).strip()
        if note: e["note"] = note
        spells[name] = e

    db = json.load(open(os.path.join(os.path.dirname(os.path.dirname(HERE)), "plan", "items-db.json"), encoding="utf-8"))
    by_id = {i["id"]: i for i in db["items"]}
    items = {}
    for iid, it in ITEMS.items():
        e = dict(it)
        e["icon"] = by_id.get(iid, {}).get("icon", "inv_misc_questionmark")
        for k in ("binding", "slot", "type"):
            if by_id.get(iid, {}).get(k):
                e.setdefault(k, by_id[iid][k])
        items[iid] = e
    out = {"spells": spells, "items": items,
           "builds": {"before": "1.60.1.70009 (talents and spells), 1.60.1.70170 (items)", "now": B2}}
    path = os.path.join(HERE, "level-30.data.json")
    json.dump(out, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("wrote %s (%d spells, %d items)" % (os.path.relpath(path), len(spells), len(items)))


if __name__ == "__main__":
    main()
