#!/usr/bin/env python3
"""Pull WoW: Forever beta client tables from wago.tools as CSV.

wago.tools mirrors every Forever beta build (product wow_classic_beta,
versions 1.60.1.x) and exports any DB2 table as CSV, so a datamine no
longer needs a local client export. Tables land in research/wago/<build>/
(gitignored: raw Blizzard data stays off the repo, the builders that read
it live in tools/).

  python3 tools/fetch_wago.py                    # newest Forever build
  python3 tools/fetch_wago.py 1.60.1.69876       # a specific build
  python3 tools/fetch_wago.py --list             # every Forever build wago has
  python3 tools/fetch_wago.py BUILD Table1 Table2  # just these tables
  python3 tools/fetch_wago.py 1.15.9.70003 --classic  # the Classic Era tables the Classic comparisons read

The Classic Era client (product wow_classic_era) is there too: tools/apply_spellbook.py --classic renders
a spell in it at the same rank as Forever's, and tools/apply_probe_spells.py names Classic's trainer spells.
"""
import json, os, sys, time, urllib.error, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UA = {"User-Agent": "foreverrank.com datamine (github.com/monscorps/foreverrank)"}

TABLES = [
    # items
    "ItemSparse", "Item", "ItemEffect", "ItemXItemEffect", "ItemSet", "ItemSetSpell",
    "ItemNameDescription", "RandPropPoints", "ItemArmorQuality", "ItemArmorTotal",
    "ArmorLocation", "ItemArmorShield", "ItemDamageOneHand", "ItemDamageOneHandCaster",
    "ItemDamageTwoHand", "ItemDamageTwoHandCaster", "ItemDamageAmmo",
    "ItemDisplayInfo", "ItemAppearance", "ItemModifiedAppearance",
    # spells
    "SpellName", "Spell", "SpellEffect", "SpellMisc", "SpellLevels", "SpellCooldowns",
    "SpellPower", "SpellDuration", "SpellRadius", "SpellRange", "SpellCastTimes",
    "SpellAuraOptions", "SpellClassOptions", "SpellReagents",
    "SkillLine", "SkillLineAbility", "SkillRaceClassInfo",
    # what tooltips and the class diff also read: without the curve and
    # description-variable tables the resolver falls back to base x rank and
    # multi-rank talent texts come out wrong
    "Curve", "CurvePoint", "SpellDescriptionVariables", "SpellXDescriptionVariables",
    "SpellTargetRestrictions", "SpellCategory", "SpellCategories", "SpellInterrupts",
    "SpellProcsPerMinute", "SpellShapeshift", "SpellEquippedItems", "SpellLabel",
    "SpellCastingRequirements", "SpellFocusObject", "SpellItemEnchantment",
    "CreatureFamily",
    # talents and legacy
    "TraitTree", "TraitNode", "TraitNodeEntry", "TraitDefinition", "TraitEdge",
    "TraitNodeGroup", "TraitNodeGroupXTraitNode", "TraitNodeXTraitNodeEntry",
    "TraitCond", "TraitCurrency", "TraitCurrencySource", "TraitDefinitionEffectPoints",
    "TraitCost", "TraitSystem",
    # world
    "Map", "LFGDungeons", "ContentTuning", "ContentTuningXExpected", "AreaTable", "AreaPOI",
    "UiMap", "UiMapAssignment", "MapDifficulty", "PlayerCondition",
    "JournalInstance", "JournalEncounter", "JournalEncounterItem",
    "TaxiNodes", "TaxiPath", "TaxiPathNode",
    # quests
    "QuestV2", "QuestXP", "QuestInfo", "QuestSort", "QuestLine", "QuestLineXQuest",
    "QuestPOIPoint", "QuestFactionReward",
    # progression, collections, account
    "Achievement", "Achievement_Category", "Criteria", "CriteriaTree", "ModifierTree",
    "CurrencyTypes", "Mount", "Faction", "CharTitles",
    "ChrRaces", "ChrClasses", "ChrSpecialization", "TransmogSet", "TransmogSetItem", "Toy",
    "ItemLimitCategory", "ManifestInterfaceData",
]

# what tools/spelltext.py needs to render a Classic Era tooltip, plus the learn levels
CLASSIC_TABLES = [
    "SpellName", "Spell", "SpellEffect", "SpellMisc", "SpellLevels", "SpellAuraOptions", "SpellDuration",
    "SpellRadius", "SpellRange", "SpellCastTimes", "SpellTargetRestrictions", "SpellDescriptionVariables",
    "SpellXDescriptionVariables", "SpellPower", "SpellCooldowns", "SkillLineAbility",
]


def builds():
    req = urllib.request.Request("https://wago.tools/api/builds", headers=UA)
    data = json.load(urllib.request.urlopen(req, timeout=60))
    return [b["version"] for b in data.get("wow_classic_beta", []) if b["version"].startswith("1.60.")]


def fetch(build, table, force=False):
    out_dir = os.path.join(ROOT, "research", "wago", build)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, table + ".csv")
    if os.path.exists(path) and not force:
        return path, "cached"
    url = "https://wago.tools/db2/%s/csv?build=%s" % (table, build)
    try:
        body = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120).read()
    except urllib.error.HTTPError as e:
        # wago answers 400 for a table this client does not have (the Journal tables on Forever)
        return None, "no table in this build" if e.code in (400, 404) else "failed: %s" % e
    except Exception as e:
        return None, "failed: %s" % e
    if not body or body[:1] == b"<":
        return None, "no table in this build"
    open(path, "wb").write(body)
    time.sleep(0.4)
    return path, "%d rows" % (body.count(b"\n") - 1)


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["--list"]:
        for b in builds():
            print(b)
        sys.exit()
    classic = "--classic" in args
    args = [a for a in args if a != "--classic"]
    build = args[0] if args else builds()[0]
    tables = args[1:] or (CLASSIC_TABLES if classic else TABLES)
    print("build", build)
    for t in tables:
        _, note = fetch(build, t)
        print("  %-30s %s" % (t, note))
