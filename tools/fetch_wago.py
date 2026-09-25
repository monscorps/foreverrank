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
"""
import json, os, sys, time, urllib.request

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
    "SkillLine", "SkillLineAbility",
    # talents and legacy
    "TraitTree", "TraitNode", "TraitNodeEntry", "TraitDefinition", "TraitEdge",
    "TraitNodeGroup", "TraitNodeGroupXTraitNode", "TraitNodeXTraitNodeEntry",
    "TraitCond", "TraitCurrency", "TraitCurrencySource", "TraitDefinitionEffectPoints",
    "TraitCost", "TraitSystem",
    # world
    "Map", "LFGDungeons", "ContentTuning", "AreaTable", "UiMap", "UiMapAssignment",
    "JournalInstance", "JournalEncounter", "JournalEncounterItem",
    # progression, collections, account
    "Achievement", "CriteriaTree", "CurrencyTypes", "Mount", "Faction", "CharTitles",
    "ChrRaces", "ChrClasses", "ChrSpecialization", "TransmogSet", "Toy",
    "ManifestInterfaceData",
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
    build = args[0] if args else builds()[0]
    tables = args[1:] or TABLES
    print("build", build)
    for t in tables:
        _, note = fetch(build, t)
        print("  %-30s %s" % (t, note))
