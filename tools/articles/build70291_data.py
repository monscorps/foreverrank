#!/usr/bin/env python3
"""Tooltip data for "Build 70291 datamined" (news/build-70291/).

Every spell text is resolved from the client's own tables in research/wago/<build>/ with tools/spelltext.py, for
1.60.1.70170 (before) and 1.60.1.70291 (now). Talent ranks read the definition that hangs on a live class tree (the
Druid stub tree 1083 carries definitions without rank curves, which would print Natural Instinct at 40%/50%).

Items come from three places, and each tooltip says which:
  - client items: the ItemSparse rows of both builds, decoded with tools/apply_items.py (item budget, armor and
    weapon damage tables). Damage is rounded half up from the tables, so it is computed, not read.
  - server-sent items (the City of Dalaran rewards, the boss-loot block): plan/items-db.json, read only, whose rows
    say where they came from; the tooltip's source line is derived from that field (ForeverChanges' item files at
    build 70291 since 2026-10-09, Wowhead's Forever database before that). Where a player hovered an item in game
    (QuestBank uploads, build 70291: seven rewards and ten block drops over two runs), the tooltip uses the game's own
    lines. Every tooltip's "was" line is read from build-70291.was.json, a frozen snapshot of what ForeverChanges'
    build-70245 files (the rewards) and Wowhead's database (the block, by October 3) had before the dungeon opened,
    so a changed quality or stat is always shown against that fixed earlier state, never against the live row.

The page is a feature page (design pass of 2026-10-09): hero with stat tiles, sticky section nav, the nerf explorer
(class chips over 45 change cards), the boss gallery, the rewards before/after cards and the rebase chart. The chart
reads the "rebase" key below, which build.py inlines because the src opts in with data-json="rebase" on the figure.

  python3 tools/articles/build70291_data.py         # writes tools/articles/build-70291.data.json (spells, items, builds, rebase)
  python3 tools/articles/build.py build-70291       # then build the page (inlines the keys the src references)
  python3 tools/articles/build70291_data.py --seo   # then its head tags (build.py's output has no <!-- seo --> block until this runs)

The chart's numbers ("rebase") are read from SpellEffect and SpellLevels of both builds and checked against the
rebase table in build-70291.src.html on every run; a mismatch stops the build with the first differing cell, so the
chart and the table can never disagree. "brief" on the server-sent items is the one-line stat summary the boss
gallery prints under an item's name; it is derived from the same row the tooltip reads.

--seo runs tools/seo.py's own rewrite() on news/build-70291/ with the values seo.py computes for an article
(title and description from the page, share image and date from its news.json entry). Once the page is in
seo.py's ARTICLES and news.json, a full `python3 tools/seo.py` writes the same block.
"""
import collections, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from spelltext import Client, _rows  # noqa: E402
from apply_talents import icon_names  # noqa: E402
import apply_items as ai  # noqa: E402

OLD, NEW = "1.60.1.70170", "1.60.1.70291"
LIVE_TREES = {"1082", "1089", "1091", "1100", "1111", "1112", "1114", "1116", "1117"}  # the nine class trees


def live_client(build):
    """A Client whose talent ranks come from the definition on a live class tree."""
    c = Client(build)
    tree_of_node = {r["ID"]: r["TraitTreeID"] for r in _rows(build, "TraitNode")}
    def_of_entry = {r["ID"]: r["TraitDefinitionID"] for r in _rows(build, "TraitNodeEntry")}
    trees = collections.defaultdict(set)
    for r in _rows(build, "TraitNodeXTraitNodeEntry"):
        d = def_of_entry.get(r["TraitNodeEntryID"])
        if d:
            trees[d].add(tree_of_node.get(r["TraitNodeID"]))
    orig = c.talent_def

    def talent_def(spell):
        on_live = [d for d in c.defs_by_spell.get(str(spell), []) if trees.get(d, set()) & LIVE_TREES]
        return on_live[0] if on_live else orig(spell)
    c.talent_def = talent_def
    return c


# ---- spells ---------------------------------------------------------------------------------------------------
# (key, spell id, kind, rank shown, extras)
#   kind t = talent (texts at the rank shown), s = spell description, a = aura text, x = text given in extras,
#        r = as the game prints it (spelltext's game_text: ranges where the amount varies)
#   extras: added / gone (build), note, col, new / old (hand-written where the template cannot be resolved),
#           cut (words dropped from both texts; the note must say why)
SPELLS = [
    # rebase (Blizzard Oct 8)
    ("Wrath R4", 5179, "s", 0, {"note": "Rank 4 of 6. Base 38 to 37; growth per level 0.9 to 0.6."}),
    ("Fireball R5", 8400, "s", 0, {"note": "Rank 5 of 6. Base 108 to 120; growth per level 1.5 to 1.4."}),
    ("Frostbolt R5", 8406, "x", 0, {"new": "Base damage 104 Frost (rank 5, level 26 to 30), plus 1.3 per level.",
                                    "old": "Base damage 95 Frost (rank 5, level 26 to 30), plus 1.5 per level.",
                                    "note": "Read from SpellEffect: Frostbolt's tooltip template uses a variable our resolver cannot fill."}),
    ("Arcane Missiles R3", 5145, "s", 0, {"note": "Rank 3 of 4. Per missile: base 44 to 47; growth per level 0.5 to 0.4."}),
    ("Smite R4", 984, "s", 0, {"note": "Rank 4 of 5. Base 59 to 60; growth per level 1 to 0.7."}),
    ("Lesser Heal R3", 2053, "s", 0, {"note": "Rank 3 of 3. Base 141 to 163; growth per level 1.6 to 1.2."}),
    ("Heal R2", 2055, "s", 0, {"note": "Rank 2 of the Heal ranks under the cap. Base 405 to 375; growth per level 3.2 to 2.9."}),
    ("Lightning Bolt R5", 943, "s", 0, {"note": "Rank 5 of 6. Base 72 to 82; growth per level 0.7 to 0.5."}),
    ("Shadow Bolt R4", 1088, "s", 0, {"note": "Rank 4 of 5. Base 56 to 58; growth per level 0.9 to 0.8."}),
    # warrior
    ("t:WARRIOR:Furious Precision", 1323963, "t", 3, {"added": "70291"}),
    ("t:WARRIOR:Lingering Rage", 1323964, "t", 5, {"added": "70291"}),
    ("t:WARRIOR:Gore Drinker", 1323967, "t", 2, {"added": "70291"}),
    ("t:WARRIOR:Improved Cleave", 12329, "t", 3, {"gone": "70291"}),
    ("t:WARRIOR:Boundless Rage", 1310236, "t", 3, {"gone": "70291"}),
    ("t:WARRIOR:Precision", 1225295, "t", 3, {"gone": "70291"}),
    ("t:WARRIOR:Toughness", 12299, "t", 5, {"gone": "70291"}),
    ("t:WARRIOR:Iron Will", 12962, "t", 5, {"note": "Moved from Fury row 2 to Protection row 1."}),
    ("t:WARRIOR:Bloodthirst", 23881, "t", 1, {}),
    ("t:WARRIOR:Dual Wield Specialization", 23584, "t", 5, {}),
    ("t:WARRIOR:Raging Blows", 1310315, "t", 1, {}),
    ("t:WARRIOR:Booming Voice", 12321, "t", 5, {}),
    ("t:WARRIOR:Unbridled Wrath", 12322, "t", 5, {}),
    ("t:WARRIOR:Blood Craze", 16487, "t", 3, {}),
    ("t:WARRIOR:Improved Slam", 12862, "t", 2, {}),
    ("t:WARRIOR:Flurry", 12319, "t", 5, {"note": "Now requires Death Wish (was Enrage), and sits one column left."}),
    ("t:WARRIOR:Impale", 16493, "t", 2, {"note": "Requires Deep Wounds again."}),
    ("Berserker Rage", 18499, "s", 0, {"note": "Trained at level 30 now (was 32)."}),
    ("Whirlwind", 1680, "s", 0, {}),
    ("Demoralizing Shout", 1160, "s", 0, {"note": "Rank 1. Every rank gained a threat effect: 11 / 19 / 27 / 35 / 43, plus 0.8 per level."}),
    ("Intimidating Shout", 5246, "s", 0, {}),
    ("Piercing Howl", 12323, "s", 0, {"note": "The client now prints \"within 0 yds\": the template reads a second radius the spell lacks. Its radius is still 10 yards."}),
    ("Spearing Strike", 1310222, "s", 0, {}),
    # paladin
    ("Retribution Aura R5", 10301, "s", 0, {"note": "Rank 5. Ranks 1 to 5: 7/12/18/24/30 to 5/8/12/16/20."}),
    ("Retribution Aura R2", 10298, "s", 0, {"note": "Rank 2, the rank from level 26 to 35. Ranks 1 to 5: 7/12/18/24/30 to 5/8/12/16/20."}),
    ("t:PALADIN:Redoubt", 20127, "t", 5, {"note": "Unchanged between 70170 and 70291. Build 70170 (October 1) cut it from 6/12/18/24/30% to 4/8/12/16/20%, as Blizzard's October 1 notes say."}),
    ("Holy Shield", 20925, "s", 0, {"note": "Rank 1. Unchanged between 70170 and 70291. Build 70170 (October 1) raised the block chance from 20% to 30%, as Blizzard's October 1 notes say."}),
    ("t:PALADIN:Reckoning", 20177, "t", 5, {}),
    ("Vindication buff", 440668, "a", 0, {"note": "The buff the Vindication talent applies. The talent itself still says 1/2/3%."}),
    ("Judgement of Justice", 20184, "s", 0, {"note": "One of the Judgement texts that were blank in 70170."}),
    ("Infusion of Light", 437063, "s", 0, {}),
    ("Seals", 1323522, "s", 0, {"added": "70291", "note": "A spellbook flyout. Not in any skill line yet."}),
    # hunter
    ("t:HUNTER:Expose Prey", 1310532, "t", 2, {}),
    ("Unleashed Fury", 19616, "s", 0, {"note": "Same text; the effect moved from a percent modifier to a flat modifier (aura 108 to 107)."}),
    ("Improved Concussive Shot", 19407, "t", 5, {"note": "Same text; the proc entry's chance went from 20 to 100, so the talent's own points now set it (inferred)."}),
    ("Improved Wing Clip", 19228, "t", 3, {"note": "Same text; the proc entry's chance went from 4 to 100."}),
    ("Freezing Trap", 14309, "s", 0, {"note": "Rank 3. Was blank in 70170, and the spell lost the word \"Effect\" from its name."}),
    ("Immolation Trap", 14301, "s", 0, {"note": "Rank 5. Was blank in 70170."}),
    ("Aspects", 1324056, "s", 0, {"added": "70291", "note": "A spellbook flyout. Not in any skill line yet."}),
    ("Furious Howl", 24597, "s", 0, {"note": "Rank 4 of the wolf's howl. Unchanged between 70170 and 70291. Build 70170 (October 1) cut it from 136 to 82 (rank 3: 100 to 60), the 40% Blizzard's September 24 notes announced."}),
    # priest
    ("t:PRIEST:Penance", 402174, "t", 1, {"note": "Rank 1, the rank under the cap. Mana 100 to 150."}),
    ("Touch of Weakness", 2943, "s", 0, {}),
    ("Weakened Soul", 6788, "s", 0, {}),
    # shaman
    ("Water Shield buff", 408510, "a", 0, {"note": "The buff text. The 15 sec category cooldown is gone from the spell."}),
    ("Mana Tide Totem", 16190, "s", 0, {"note": "Trained at level 25 now (was 40)."}),
    ("Totemic Recall", 39104, "s", 0, {"added": "70291", "note": "Spell 39104 is new in 70291. The Forever copy 1323420 still prints 0%."}),
    ("Earth Totems", 1323772, "s", 0, {"added": "70291", "note": "One of seven totem flyouts (two Earth, one Air, two Fire, two Water)."}),
    ("Ancestral Fortitude", 16177, "s", 0, {}),
    # mage
    ("Chilled", 6136, "s", 0, {}),
    # warlock
    ("Demonic Brand", 1293695, "x", 0, {
        "new": "Your Searing Pain generates less threat and brands the target. Your pet's next attacks against the target deal Fire or Shadow damage based on the pet. If Shadow damage is dealt, it has high threat.",
        "old": "Your Searing Pain generates less threat and brands the target. Your pet's next attacks against the target generate high threat and deal Fire or Shadow damage based on the pet.",
        "note": "The client's wording with its numbers left out: the template uses variables our resolver cannot fill."}),
    ("Summoning Disorientation", 1324106, "a", 0, {"added": "70291", "note": "A 10 sec stun. Nothing in the client says what casts it."}),
    # druid
    ("Thorns R6", 9910, "s", 0, {"note": "Rank 6. Ranks 1 to 6: 4/9/11/13/16/22 to 3/6/9/12/15/18."}),
    ("Thorns R3", 1075, "s", 0, {"note": "Rank 3, the rank from level 24 to 33. Ranks 1 to 6: 4/9/11/13/16/22 to 3/6/9/12/15/18."}),
    ("t:DRUID:Natural Instinct", 1223242, "t", 2, {"note": "Was Predatory Instincts."}),
    ("t:DRUID:Thick Hide", 16929, "t", 3, {"note": "Same text. Its armor effect now grows 3 per level (levels 1 to 60)."}),
    ("t:DRUID:Furor", 17056, "t", 5, {}),
    ("Wolfshead Helm", 17768, "s", 0, {"note": "The helm's equip effect."}),
    ("Demoralizing Roar", 99, "s", 0, {"note": "Rank 1. Every rank gained a threat effect: 8 / 16 / 26 / 34 / 42, plus 0.8 per level."}),
    # racial
    ("Will of the Forsaken", 7744, "s", 0, {"note": "Same text. Its three dispels became 100 ms immunities, so it works while asleep or charmed."}),
    # Dalaran
    ("Violet Meditation", 1324318, "s", 0, {"added": "70291", "note": "4-piece bonus. Its chance is not in the client."}),
    ("Summon Arcane Elemental", 1324323, "s", 0, {"added": "70291", "note": "5-piece bonus. Summons creature 277729 for 20 sec. Its chance is not in the client."}),
    ("Archmagister's Wisdom", 1292997, "s", 0, {"note": "The use effect of an unnamed neck in the probable Dalaran boss-loot block."}),
    ("Arcane Explosion NPC", 1324306, "r", 0, {"added": "70291", "note": "No class owns this copy (inferred: an NPC spell)."}),
    ("Mana Void", 1324282, "x", 0, {"added": "70291", "new": "2 sec cast. 90 Arcane damage to enemies within 60 yards of the caster, and a 5 sec silence.",
                                     "note": "No tooltip text: read from SpellEffect and SpellCastTimes."}),
    # sets
    ("Krol'dok Resolve", 1324298, "r", 0, {"added": "70291", "note": "As the game prints it: the heal (spell 1324296) is 18 with 0.5 variance."}),
    ("Ogre Dominance", 1324309, "s", 0, {"added": "70291"}),
    ("Defias Juggernaut", 1324684, "s", 0, {"added": "70291"}),
    # world and legacy
    ("Legacy Reputation Reward", 1324722, "s", 0, {"added": "70291"}),
    ("Collapsing Star", 1271414, "s", 0, {"cut": " for 0 sec",
                                          "note": "Anara Chillwind, Hyjal Summit. The text reads the aura's duration, which the client sets to -1 (no fixed length), so a template reader prints \"for 0 sec\"; we left those words out of both builds' text."}),
    ("Lunar Venting", 1271100, "s", 0, {}),
    ("Dreamfall", 1269045, "s", 0, {"note": "Its encounter is not in its text (inferred: Nythus the Dreambound)."}),
    ("Rot", 1295744, "r", 0, {"note": "The proc of Rot-Covered Harpoon."}),
]

ICON_FALLBACK = {"Seals": "spell_holy_sealofwrath", "Aspects": "ability_hunter_aspectofthemonkey",
                 "Earth Totems": "spell_nature_earthbindtotem", "Mana Void": "spell_arcane_arcane02",
                 "Legacy Reputation Reward": "achievement_reputation_01"}
# decorative icons where the client's own is a placeholder (set bonuses carry the generic shield; a few spells "temp")
ICON_OVERRIDE = {"Violet Meditation": "inv_chest_cloth_17", "Summon Arcane Elemental": "inv_chest_cloth_17",
                 "Krol'dok Resolve": "inv_chest_plate16", "Ogre Dominance": "inv_chest_plate16",
                 "Defias Juggernaut": "inv_chest_leather_07", "Wolfshead Helm": "inv_helmet_04",
                 "Summoning Disorientation": "spell_shadow_summonimp", "Totemic Recall": "spell_shaman_totemrecall"}


def spells():
    cs = {OLD: live_client(OLD), NEW: live_client(NEW)}
    icons = {}
    for b in (OLD, NEW):
        icons.update(icon_names(b))

    def icon(sp, key):
        if key in ICON_OVERRIDE:
            return ICON_OVERRIDE[key]
        for b in (NEW, OLD):
            m = cs[b].misc.get(str(sp))
            if m and icons.get(m["SpellIconFileDataID"]):
                return icons[m["SpellIconFileDataID"]]
        return ICON_FALLBACK.get(key.split(":")[-1], "inv_misc_questionmark")

    def render(c, sp, kind, r):
        s = str(sp)
        if s not in c.spell:
            return None
        if kind == "t":
            return c.talent_text(sp, r, r)
        if kind == "a":
            return c.text(sp, "AuraDescription_lang")
        if kind == "r":
            return c.item_text(sp)
        return c.text(sp)

    out = {}
    for key, sp, kind, r, ex in SPELLS:
        s = str(sp)
        e = {"id": sp, "n": cs[NEW].name.get(s) or cs[OLD].name.get(s) or key, "icon": icon(sp, key)}
        if r > 1:
            e["r"] = r
        if kind == "x":
            new, old = ex.get("new"), ex.get("old")
        else:
            new = None if ex.get("gone") else render(cs[NEW], sp, kind, r)
            old = None if ex.get("added") else render(cs[OLD], sp, kind, r)
        if ex.get("cut"):  # a template slip the note explains
            new, old = [t.replace(ex["cut"], "") if t else t for t in (new, old)]
        if new:
            e["new"] = new
        if old and old != new:
            e["old"] = old
        for k in ("added", "gone", "note"):
            if ex.get(k):
                e[k] = ex[k]
        if not e.get("new") and not e.get("old") and not e.get("note"):
            sys.exit("no text for " + key)
        out[key] = e
    return out


# ---- items ----------------------------------------------------------------------------------------------------
SLOTN = {"neck": "Neck", "finger": "Finger", "off-hand": "Held In Off-hand", "chest": "Chest", "legs": "Legs",
         "main-hand": "Main Hand", "one-hand": "One-Hand", "two-hand": "Two-Hand", "feet": "Feet", "waist": "Waist",
         "wrist": "Wrist", "hands": "Hands", "shoulder": "Shoulder", "back": "Back", "head": "Head", "ranged": "Ranged",
         "trinket": "Trinket", "tabard": "Tabard", "shirt": "Shirt", "thrown": "Thrown"}
PRIM = [("strength", "Strength"), ("agility", "Agility"), ("stamina", "Stamina"), ("intellect", "Intellect"), ("spirit", "Spirit")]
RES = [("arcaneResist", "Arcane"), ("fireResist", "Fire"), ("frostResist", "Frost"), ("natureResist", "Nature"), ("shadowResist", "Shadow")]
SHORT = {"strength": "Str", "agility": "Agi", "stamina": "Sta", "intellect": "Int", "spirit": "Spi", "spellPower": "spell power",
         "attackPower": "Attack Power", "hp5": "health per 5", "mp5": "mana per 5", "healing": "Healing", "spellDamage": "Spell Damage",
         "natureSpellDamage": "Nature Spell Damage", "arcaneSpellDamage": "Arcane Spell Damage", "bonusArmor": "Armor",
         "critRating": "Crit Rating", "crit": None, "arcaneResist": "Arcane Resistance", "fireResist": "Fire Resistance",
         "frostResist": "Frost Resistance", "natureResist": "Nature Resistance", "shadowResist": "Shadow Resistance"}
RESIST_RE = __import__("re").compile(r"^\+(\d+) (Arcane|Fire|Frost|Nature|Shadow) Resistance$")
BONUS_ARMOR_RE = __import__("re").compile(r"^\+(\d+) Armor$")

SRC_CLIENT = "Client build 70291: ItemSparse, decoded from the item budget; armor and damage computed from the client's tables."
SRC_QB = "Read in game, build %d."
QNAME = {0: "poor", 1: "common", 2: "uncommon", 3: "rare", 4: "epic", 5: "legendary"}
PRIM_RE = __import__("re").compile(r"^\+(\d+) (Strength|Agility|Stamina|Intellect|Spirit)$")
SRC_WH = "Wowhead's Forever database (server data, read by the site's item database)."
WAS = json.load(open(os.path.join(HERE, "build-70291.was.json"), encoding="utf-8"))["items"]
_BUILD_RE = __import__("re").compile(r"1\.60\.1\.(\d+)")
_GRAMMAR_RE = __import__("re").compile(r"\|4([^:|;]*):([^;|]*);")  # the client's |4singular:plural; escape in a raw tooltip line


def src_of(row, note=""):
    """The tooltip's source line, from the database row's own source field (never a hard-coded build)."""
    s = row.get("source") or ""
    m = _BUILD_RE.search(s)
    if "foreverchanges" in s.lower() and m:
        line = "ForeverChanges' item files, build 1.60.1.%s." % m.group(1)
    elif "wowhead" in s.lower():
        line = SRC_WH
    else:
        line = "plan/items-db.json: " + s
    return (line + " " + note).strip()


def _view(row):
    """What the 'was' comparison looks at: quality, every stat but the derived crit percent, armor, damage and speed."""
    st = {k: v for k, v in (row.get("stats") or {}).items() if k != "crit" and v}
    return (row.get("quality"), st, row.get("armor"), row.get("damage"), row.get("speed"))


def was_of(row, snap):
    """(text, source) of the snapshot's state where the current row differs from it; None where nothing moved."""
    if not snap or _view(row) == _view(snap):
        return None
    parts = []
    if snap.get("armor"):
        parts.append("%d armor" % snap["armor"])
    if snap.get("damage"):
        lo, hi = snap["damage"].split("-")
        parts.append("%s - %s damage, speed %.2f (%.1f dps)" % (lo, hi, snap["speed"], snap["dps"]))
    strip = lambda x: __import__("re").sub(r"\s*\([^)]*\)\.?$", "", x).rstrip(".")
    now_fx = {strip(x) for x in (row.get("effects") or [])}
    gone = [x for x in (snap.get("effects") or []) if strip(x) not in now_fx]
    parts.append(brief(snap.get("stats"), short_effects(gone, snap.get("stats"))))
    return snap["quality"] + " · " + ", ".join(parts), snap["at"]


def brief(stats, extra=None):
    out = []
    for k, v in (stats or {}).items():
        if k == "crit" or not v:
            continue
        name = SHORT.get(k, k)
        if k in ("strength", "agility", "stamina", "intellect", "spirit"):
            out.append("%s %d" % (dict(PRIM)[k], v))
        else:
            out.append("+%s %s" % (v if v != int(v) else int(v), name))
    if extra:
        out.append(extra)
    return ", ".join(out) or "no stats"


EFFECT_SHORT = [  # the long-form Equip: sentences that are plain stats, shortened; "+N Stat" lines are the stats row itself
    (__import__("re").compile(r"^Equip: Increases damage and healing done by magical spells and effects by up to (\d+)\.?$"), "+{0} spell power", "spellPower"),
    (__import__("re").compile(r"^Equip: Increases damage done by (\w+) spells and effects by up to (\d+)\.?$"), "+{1} {0} spell damage", "spellDamage"),
    (__import__("re").compile(r"^Equip: Increases healing done by up to (\d+) and damage done by up to (\d+) for all magical spells and effects\.?$"), "+{0} healing, +{1} spell damage", "healing"),
    (__import__("re").compile(r"^Equip: Restores (\d+) mana per 5 sec\.?$", __import__("re").I), "+{0} mana per 5", "mp5"),
]
PLAIN_STAT = __import__("re").compile(r"^Equip: \+\d+ [A-Za-z ]+\.?$")  # "+5 Spell Power", "+12 Attack Power": brief() prints these from the stats row


def short_effects(effects, stats):
    """One short clause per Equip: line that is not already a stat brief() prints: procs and use effects, word for word."""
    out = []
    for line in effects or []:
        if PLAIN_STAT.match(line) and stats:
            continue
        for rx, fmt, key in EFFECT_SHORT:
            m = rx.match(line)
            if m:
                if not (key and (stats or {}).get(key)):
                    out.append(fmt.format(*m.groups()))
                break
        else:
            out.append((line[7:] if line.startswith("Equip: ") else line).rstrip("."))
    return ", ".join(out) or None


def tip_brief(lines):
    """The one-line brief from the game's own tooltip lines: primary stats, then resistances, bonus armor and Equip effects."""
    prim = {m.group(2).lower(): int(m.group(1)) for m in (PRIM_RE.match(x) for x in lines) if m}
    extra = ["+%s %s Resistance" % m.groups() for m in (RESIST_RE.match(x) for x in lines) if m]
    extra += ["+%s Armor" % m.group(1) for m in (BONUS_ARMOR_RE.match(x) for x in lines) if m]
    fx = short_effects([x for x in lines if x.startswith("Equip:")], None)
    if fx:
        extra.append(fx)
    return brief(prim, ", ".join(extra) or None)


def stat_lines(stats, effects=None):
    L = []
    s = stats or {}
    if s.get("bonusArmor"):
        L.append(["l", "+%d Armor" % s["bonusArmor"]])
    for k, n in PRIM:
        if s.get(k):
            L.append(["l", "+%d %s" % (s[k], n)])
    for k, n in RES:
        if s.get(k):
            L.append(["l", "+%d %s Resistance" % (s[k], n)])
    for line in effects or []:
        L.append(["g", line])
    return L


def icon_file(name):
    """The icon's file name on the icon CDN, which spells spaces as hyphens (jewelcrafting_uncut-epic-gem_color1)."""
    return (name or "inv_misc_questionmark").strip().replace(" ", "-")


def half(x):
    return ai.half_up(x)


def client_item(iid, A, B, db, extra):
    """Tooltip lines from the 70291 ItemSparse row (and the 70170 one for the 'was' line)."""
    a, b = A.view(iid), B.view(iid)
    row = db.get(iid, {})
    e = {"name": b["name"], "quality": b["quality"], "icon": icon_file(row.get("icon")), "itemLevel": b["itemLevel"]}
    slot = row.get("slot")
    typ = row.get("type") or (row.get("sub") if row.get("cat") == "armor" else None)
    L = []
    if b["binding"] == "BoP":
        L.append(["l", "Binds when picked up"])
    elif b["binding"] == "BoE":
        L.append(["l", "Binds when equipped"])
    if row.get("unique") or extra.get("unique"):
        L.append(["l", "Unique"])
    if slot and slot != "unknown":
        L.append(["l", SLOTN.get(slot, slot.title()) + ("\t" + typ if typ else "")])
    if b["armorM"]:
        L.append(["l", "%d Armor" % half(b["armorM"])])
    if b["dmgM"]:
        lo, hi, spd = b["dmgM"]
        L.append(["l", "%d - %d Damage\tSpeed %.2f" % (half(lo), half(hi), spd)])
        L.append(["l", "(%.1f damage per second)" % ((lo + hi) / 2 / spd)])
    others = [x for x in (row.get("effects") or []) if not x.startswith("Equip: +")]
    if extra.get("effects") is not None:
        others = extra["effects"]
    L += stat_lines(b["stats"], (b["lines"] or []) + others)
    if b["cls"]:
        L.append(["l", "Classes: " + ", ".join(b["cls"])])
    if b["flavor"]:
        L.append(["d", '"%s"' % b["flavor"]])
    if b["reqLevel"] and b["reqLevel"] > 1:
        L.append(["l", "Requires Level %d" % b["reqLevel"]])
    L.append(["y", "Item Level %d" % b["itemLevel"]])
    e["lines"] = L
    if a:
        moved = []
        if a["quality"] != b["quality"]:
            moved.append(a["quality"])
        if a["itemLevel"] != b["itemLevel"]:
            moved.append("item level %d" % a["itemLevel"])
        if (a["reqLevel"] or 0) != (b["reqLevel"] or 0):
            moved.append("requires level %s" % (a["reqLevel"] or "none"))
        if (a["stats"] or {}) != (b["stats"] or {}):
            moved.append(brief(a["stats"]))
        if a["armorM"] and b["armorM"] and half(a["armorM"]) != half(b["armorM"]):
            moved.append("%d armor" % half(a["armorM"]))
        if a["dmgM"] and b["dmgM"] and a["dmgM"] != b["dmgM"]:
            lo, hi, spd = a["dmgM"]
            moved.append("%d - %d damage, speed %.2f (%.1f dps)" % (half(lo), half(hi), spd, (lo + hi) / 2 / spd))
        if (a["cls"] or None) != (b["cls"] or None):
            moved.append("classes: " + (", ".join(a["cls"]) if a["cls"] else "any"))
        if extra.get("was"):
            moved.append(extra["was"])
        if moved:
            e["was"] = "; ".join(moved)
            e["oldQuality"] = a["quality"] if a["quality"] != b["quality"] else None
            if e["oldQuality"] is None:
                del e["oldQuality"]
    e["src"] = extra.get("src", SRC_CLIENT)
    return e


def db_item(iid, db, tip=None, note="", extra=None):
    """Tooltip lines from plan/items-db.json (server-sent items), or from a player's in-game reading; the source line
    comes from the row (or the upload), the 'was' line from the build-70291.was.json snapshot."""
    row = db[iid]
    e = {"name": row["name"], "quality": row["quality"], "icon": icon_file(row.get("icon")), "itemLevel": row.get("itemLevel")}
    if tip:
        import datetime
        if tip.get("n") and tip["n"] != row["name"]:
            sys.exit("item %s: the game printed %r, the database row says %r" % (iid, tip["n"], row["name"]))
        L = []
        lines = [_GRAMMAR_RE.sub(r"\2", x) for x in tip["x"]]
        for x in lines:
            L.append(["g" if x.startswith(("Equip:", "Use:", "Chance on hit:")) else "l", x])
        if row.get("reqLevel", 0) > 1 and not any(x.startswith("Requires Level") for x in lines):
            L.append(["l", "Requires Level %d" % row["reqLevel"]])
        L.append(["y", "Item Level %d" % tip["l"]])
        e["lines"] = L
        e["brief"] = tip_brief(lines)
        e["quality"] = QNAME.get(tip.get("q"), row["quality"])
        if e["quality"] != row["quality"]:
            sys.exit("item %s: the game printed quality %r, the database row says %r" % (iid, e["quality"], row["quality"]))
        when = datetime.datetime.fromtimestamp(tip["at"], datetime.timezone.utc).strftime("%-d %B, %H:%M")
        e["src"] = (SRC_QB % tip["b"] + " " + note).strip()
        w = was_of(row, WAS.get(iid))
        if w:
            e["was"], e["wasAt"] = w
            if WAS[iid]["quality"] != e["quality"]:
                e["oldQuality"] = WAS[iid]["quality"]
        e.update(extra or {})
        return e
    L = []
    if row.get("binding") == "BoP":
        L.append(["l", "Binds when picked up"])
    if row.get("unique"):
        L.append(["l", row["unique"] if isinstance(row["unique"], str) else "Unique"])
    slot, typ = row.get("slot"), row.get("type") or (row.get("sub") if row.get("cat") == "armor" else None)
    if slot and slot != "unknown":
        L.append(["l", SLOTN.get(slot, slot.title()) + ("\t" + typ if typ else "")])
    if row.get("armor"):
        L.append(["l", "%d Armor" % row["armor"]])
    if row.get("damage"):
        lo, hi = row["damage"].split("-")
        L.append(["l", "%s - %s Damage\tSpeed %.2f" % (lo, hi, row["speed"])])
        L.append(["l", "(%.1f damage per second)" % row["dps"]])
    L += stat_lines(row.get("stats"), row.get("effects"))
    if row.get("flavor"):
        L.append(["d", '"%s"' % row["flavor"]])
    if row.get("reqLevel", 0) > 1:
        L.append(["l", "Requires Level %d" % row["reqLevel"]])
    if row.get("itemLevel", 0) > 1:
        L.append(["y", "Item Level %d" % row["itemLevel"]])
    e["lines"] = L
    e["src"] = src_of(row, note)
    w = was_of(row, WAS.get(iid))
    if w:
        e["was"], e["wasAt"] = w
        if WAS[iid]["quality"] != e["quality"]:
            e["oldQuality"] = WAS[iid]["quality"]
    e["brief"] = brief(row.get("stats"), short_effects(row.get("effects"), row.get("stats")))
    e.update(extra or {})
    return e


DALARAN_REWARDS = ["251962", "279849", "279839", "279840", "279841", "279835", "279836", "251963", "251965",
                   "279847", "279848", "279842", "279843", "279844", "279837", "279838"]
# the 15 named rows of the boss-loot block 273031 to 273055, each with how it is tied to Dalaran (the tooltip's last words)
_RUN = "Looted in a City of Dalaran run (QuestBank upload); which boss dropped it was not recorded."
_DEMO = "Seen dropping at Blizzard's BlizzCon demo run of the dungeon, per ForeverChanges' notes."
_PROB = "Dalaran link inferred: the row sits in the client's probable boss-loot block; no one has seen it drop."
BOSS_BLOCK = {"273033": _RUN, "273035": _RUN, "273036": _RUN, "273038": _RUN, "273041": _RUN, "273045": _RUN, "273047": _RUN,
              "273048": _RUN, "273049": _RUN, "273054": _RUN, "273046": _DEMO, "273052": _DEMO,
              "273039": _PROB, "273042": _PROB, "273044": _PROB}
DALARAN_MISC = ["277507", "251961", "275997", "251983", "275996", "275989", "276561", "285327", "10327", "212792"]
EXCAVATION = ["271667", "271664", "271670", "271740", "271732", "271769", "280766", "271716", "271719", "271766"]
# Healer's Staff: its client row is identical in 70170 and 70291, but the client's damage tables give it 27.9 dps where
# ForeverChanges' item file (a caster staff) has 43 - 65, so its tooltip uses the database row and says why.
SAME_ROW = ["271767"]
RIVERGLADES = ["274957", "274915", "274916", "274918", "274922", "274928", "274929", "274938", "274939", "274940",
               "274941", "274942", "274943", "274944", "274946", "274955", "274961", "274963"]
OTHER = ["6975", "6976", "6977", "280604", "281286", "272184", "272185", "279450", "221518", "273658", "277254",
         "251485", "251486", "287958", "287959", "287992", "287963", "287964", "287971", "287966",
         "280404", "280729", "279182", "280623", "280740", "280614", "221192", "276538", "274748", "8345"]
EXTRA = {
    "274963": {"effects": None},  # filled below from the 70291 client (the database still has 25)
    # Whisper: the database row's "Equip: Increases your critical strike by 17." is the old Season of Discovery line; the
    # decoded 70291 budget already prints its +7 Critical Strike Rating, so no database effect is added
    "221518": {"src": SRC_CLIENT + " The site's database flags this as Season of Discovery data.", "effects": []},
    "8345": {"effects": ["Equip: You gain an additional 5 Rage from activating Enrage and an additional 5 Energy from activating Shifting Power."],
             "was": "20 Energy from Shifting Power"},
    "287958": {"unique": True}, "287959": {"unique": True},
}


def items():
    db = {i["id"]: i for i in json.load(open(os.path.join(ROOT, "plan", "items-db.json"), encoding="utf-8"))["items"]}
    tips = json.load(open(os.path.join(ROOT, "research", "questbank", "disc.json"), encoding="utf-8"))["probe"]["tips"]
    A, B = ai.Build(OLD), ai.Build(NEW)
    rot = Client(NEW).item_text(1295744)
    EXTRA["274963"]["effects"] = ["Chance on hit: " + rot]
    out = {}
    for iid in DALARAN_REWARDS:
        out[iid] = db_item(iid, db, tips.get(iid))
    for iid, note in BOSS_BLOCK.items():
        out[iid] = db_item(iid, db, tips.get(iid), note)
    for iid in DALARAN_MISC:
        if B.view(iid):
            out[iid] = client_item(iid, A, B, db, {"src": "Client build 70291 (ItemSparse)" + (", in the client since 69876." if int(iid) > 250000 else ".")})
        else:
            out[iid] = db_item(iid, db)
    for iid in SAME_ROW:
        if A.view(iid) != B.view(iid):
            sys.exit("%s changed between the builds" % iid)
        out[iid] = db_item(iid, db, None, "The client's row is identical in 70170 and 70291.")
    for iid in EXCAVATION + RIVERGLADES + OTHER:
        if not B.view(iid):
            sys.exit("no 70291 ItemSparse row for %s" % iid)
        out[iid] = client_item(iid, A, B, db, EXTRA.get(iid, {}))
    for iid, e in out.items():
        if iid not in db:
            sys.exit("item %s is not in plan/items-db.json" % iid)
    return out


# ---- rebase chart -----------------------------------------------------------------------------------------------
# key: (name, class, class colour, the spell key whose icon the chart borrows, rank spell ids low to high)
RANKS = [
    ("wrath", "Wrath", "Druid", "#ff7c0a", "Wrath R4", [5176, 5177, 5178, 5179, 5180, 6780]),
    ("fireball", "Fireball", "Mage", "#3fc7eb", "Fireball R5", [133, 143, 145, 3140, 8400, 8401]),
    ("frostbolt", "Frostbolt", "Mage", "#3fc7eb", "Frostbolt R5", [116, 205, 837, 7322, 8406, 8407]),
    ("arcanemissiles", "Arcane Missiles", "Mage", "#3fc7eb", "Arcane Missiles R3", [5143, 5144, 5145, 8416]),
    ("smite", "Smite", "Priest", "#ffffff", "Smite R4", [585, 591, 598, 984, 1004]),
    ("lesserheal", "Lesser Heal", "Priest", "#ffffff", "Lesser Heal R3", [2050, 2052, 2053]),
    ("heal", "Heal", "Priest", "#ffffff", "Heal R2", [2054, 2055, 6063]),
    ("lightningbolt", "Lightning Bolt", "Shaman", "#2e8fff", "Lightning Bolt R5", [403, 529, 548, 915, 943, 6041]),
    ("shadowbolt", "Shadow Bolt", "Warlock", "#8788ee", "Shadow Bolt R4", [686, 695, 705, 1088, 1106]),
]
REBASE_NOTE = {"arcanemissiles": "per missile (spells 7268 to 7270)", "frostbolt": "damage is its second effect"}
# the chart's one-line reading under each spell: what the table shows, and the level-30 note's own words
REBASE_CAP = {
    "wrath": "A level-30 character's best rank, rank 5, is unchanged at the cap. Ranks 2 and 4 lose base damage, and ranks 1 to 5 grow slower per level.",
    "fireball": "A level-30 character's best rank, rank 6, is unchanged at the cap. The cut lands on ranks 2 and 3 while leveling; ranks 4 and 5 rise.",
    "frostbolt": "Rises at the cap: rank 5 at level 30, 101 → 109.2 (inferred, Classic's per-level rule). Rank 2 is cut; ranks 4 and 5 rise.",
    "arcanemissiles": "Rises at the cap: rank 3 (capped at its level 28), 46 → 48.6 per missile (inferred). Ranks 2 and 3 rise per missile; rank 1 only grows slower.",
    "smite": "A level-30 character's best rank, rank 5, is unchanged at the cap. Ranks 2 and 3 are cut; rank 4 rises.",
    "lesserheal": "Rank 3, the top rank, heals more: 141 → 163, and rank 2 78 → 94. Rank 1 only grows slower per level.",
    "heal": "A level-30 character's best rank, rank 3 (level 28), is unchanged at the cap. Ranks 1 and 2 heal less.",
    "lightningbolt": "Rises at the cap: rank 5 at level 30, 74.8 → 84 (inferred). Rank 1 and ranks 4 and 5 rise; rank 2 is cut.",
    "shadowbolt": "A level-30 character's best rank, rank 5 (level 28), is unchanged at the cap. Ranks 2 and 3 are cut; rank 4 rises.",
}
REBASE_INFERRED = {"frostbolt", "arcanemissiles", "lightningbolt"}  # caps that quote the note's at-level-30 figures


def _fmt(x):
    """Numbers the way the table prints them: 16.6, 114, 0.4."""
    x = round(float(x) + 1e-9, 2)
    return ("%d" % x) if x == int(x) else ("%.2f" % x).rstrip("0")


def _effect_values(build):
    """spell id -> (base, per level) of its damage or heal effect, following a periodic-trigger aura to the spell it fires."""
    rows = collections.defaultdict(list)
    for r in _rows(build, "SpellEffect"):
        rows[r["SpellID"]].append(r)

    def pick(sp, depth=0):
        for r in sorted(rows.get(str(sp), []), key=lambda r: int(r["EffectIndex"])):
            if r["Effect"] in ("2", "10"):  # school damage, heal
                return float(r["EffectBasePointsF"]), float(r["EffectRealPointsPerLevel"])
        for r in rows.get(str(sp), []):
            if r["Effect"] == "6" and r["EffectTriggerSpell"] not in ("", "0") and depth < 2:
                v = pick(r["EffectTriggerSpell"], depth + 1)
                if v:
                    return v
        return None
    return pick


def _levels(build):
    return {r["SpellID"]: (int(r["BaseLevel"]), int(r["MaxLevel"])) for r in _rows(build, "SpellLevels")}


def rebase(sp):
    eff = {OLD: _effect_values(OLD), NEW: _effect_values(NEW)}
    lv = {OLD: _levels(OLD), NEW: _levels(NEW)}
    out = []
    for key, name, cls, cc, icon_key, ids in RANKS:
        ranks = []
        for n, sid in enumerate(ids, 1):
            vo, vn = eff[OLD](sid), eff[NEW](sid)
            lo, ln = lv[OLD].get(str(sid)), lv[NEW].get(str(sid))
            if not (vo and vn and lo and ln):
                sys.exit("rebase: no effect or level row for %s rank %d (%d)" % (name, n, sid))
            if lo != ln:
                sys.exit("rebase: %s rank %d changed its levels (%s -> %s)" % (name, n, lo, ln))
            base, per = (vo[0], vn[0]), (vo[1], vn[1])
            atmax = tuple(b + p * (ln[1] - ln[0]) for b, p in zip(base, per))
            r = {"r": n, "id": sid, "lv": [ln[0], ln[1]], "base": [float(_fmt(x)) for x in base],
                 "per": [float(_fmt(x)) for x in per], "atmax": [float(_fmt(x)) for x in atmax]}
            if _fmt(base[0]) == _fmt(base[1]) and _fmt(per[0]) == _fmt(per[1]):
                r["same"] = True
            ranks.append(r)
        e = {"key": key, "name": name, "cls": cls, "cc": cc, "icon": sp[icon_key]["icon"], "ranks": ranks, "cap": REBASE_CAP[key]}
        if key in REBASE_NOTE:
            e["note"] = REBASE_NOTE[key]
        if key in REBASE_INFERRED:
            e["inf"] = True
        out.append(e)
    check_rebase(out)
    return out


def check_rebase(data):
    """Every base / per level / at max level pair in the src's rebase table must equal what the client gave us."""
    import re
    src = open(os.path.join(HERE, "build-70291.src.html"), encoding="utf-8").read()
    m = re.search(r'id="rebase".*?</section>', src, re.S)
    if not m:
        sys.exit("rebase check: no #rebase section in the src")
    table = {}
    name = None
    for row in re.findall(r"<tr[^>]*>.*?</tr>", m.group(0), re.S):
        g = re.search(r'<td colspan="5">([^<]+?)\s*<small>', row)
        if g:
            name = g.group(1).strip()
            continue
        r = re.search(r"<td>Rank (\d+) <code>(\d+)</code></td>", row)
        if not r:
            continue
        cells = re.findall(r'<td class="n">(.*?)</td>', row)
        lvs = re.match(r"(\d+)–(\d+)", cells[0]) if cells else None
        vals = []
        for c in cells[1:]:
            eq = re.match(r'<span class="eq">([\d.]+)</span>$', c)
            vs = re.match(r'<span class="vs"><s>([\d.]+)</s>→<b class="\w+">([\d.]+)</b></span>$', c)
            vals.append((eq.group(1), eq.group(1)) if eq else (vs.group(1), vs.group(2)) if vs else None)
        table[int(r.group(2))] = (name, int(r.group(1)), (int(lvs.group(1)), int(lvs.group(2))) if lvs else None,
                                  vals if "unchanged" not in row else "unchanged")
    for sp in data:
        for r in sp["ranks"]:
            t = table.get(r["id"])
            if not t:
                sys.exit("rebase check: %s rank %d (%d) is not in the src table" % (sp["name"], r["r"], r["id"]))
            if t[2] and list(t[2]) != r["lv"]:
                sys.exit("rebase check: %s rank %d levels %s in the table, %s in the client" % (sp["name"], r["r"], t[2], r["lv"]))
            if t[3] == "unchanged":
                if not r.get("same"):
                    sys.exit("rebase check: %s rank %d is 'unchanged' in the table but moved in the client" % (sp["name"], r["r"]))
                continue
            for col, pair in zip(("base", "per", "atmax"), t[3]):
                mine = tuple(_fmt(x) for x in r[col])
                if pair is None or tuple(pair) != mine:
                    sys.exit("rebase check: %s rank %d %s is %s in the table, %s in the client" % (sp["name"], r["r"], col, pair, mine))
    print("rebase: %d spells, %d ranks checked against the src table" % (len(data), sum(len(s["ranks"]) for s in data)))


def main():
    sp = spells()
    data = {"spells": sp, "items": items(), "rebase": rebase(sp),
            "builds": {"before": OLD, "now": NEW, "note": "70205, 70235 and 70245 serve the same tables as 70170."}}
    path = os.path.join(HERE, "build-70291.data.json")
    json.dump(data, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    was = sorted(k for k, v in data["items"].items() if v.get("was"))
    game = sorted(k for k, v in data["items"].items() if v.get("src", "").startswith("Read in game"))
    print("wrote %s (%d spells, %d items, %d rebase spells; %d tooltips from a player's game, %d with a 'was' line)"
          % (os.path.relpath(path, ROOT), len(data["spells"]), len(data["items"]), len(data["rebase"]), len(game), len(was)))


PAGE, IMG, DATE = "/news/build-70291/", "/codex/img/city-of-dalaran.jpg", "2026-10-08"


def seo_tags():
    import html, re
    import seo
    f = seo.page_file(PAGE)
    h = open(f, encoding="utf-8").read()
    base = re.sub(r"\s*·.*$", "", re.search(r"<title>([^<]*)</title>", h).group(1))
    desc = html.unescape(re.search(r'<meta name="description" content="([^"]*)"', h).group(1))
    news = json.load(open(os.path.join(ROOT, "news.json"), encoding="utf-8"))
    item = {i["l"]: i for i in news["items"] if i.get("s") == "FOREVERRANK"}.get(PAGE, {})
    img, date = item.get("img") or IMG, item.get("d") or DATE
    org = {"@type": "Organization", "name": "ForeverRank", "url": seo.SITE + "/"}
    ld = {"@context": "https://schema.org", "@type": "NewsArticle", "headline": html.unescape(base), "description": desc,
          "image": [seo.SITE + img], "mainEntityOfPage": seo.SITE + PAGE, "author": org, "publisher": org,
          "datePublished": date, "dateModified": seo.lastmod(f)}
    f, before, after = seo.rewrite(PAGE, base + " · WoW Forever · ForeverRank", desc, img, "article", ld)
    if before != after:
        open(f, "w", encoding="utf-8").write(after)
    print("head tags %s for %s" % ("written" if before != after else "already current", PAGE))


if __name__ == "__main__":
    if "--seo" in sys.argv:
        seo_tags()
    else:
        main()
