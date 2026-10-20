#!/usr/bin/env python3
"""Write Cute/Known.lua, the seed: what research and the beta say Forever has, each fact with how sure we are.

  python3 tools/cute/gen_known.py             # write Cute/Known.lua (only when a fact changed) and print the counts
  python3 tools/cute/gen_known.py --selftest  # check the joins, the evidence and the file on disk; writes nothing

Nobody knows what Forever holds at launch. The seed is what we believe on the day the addon ships; the addon checks it
against the live client at login and learns the rest from the guild's play (docs/superpowers/specs/
2026-10-19-cute-known-and-rules-design.md). A fact's conf is "beta" when the beta showed it (a level range starting at
or below the beta's cap, with players' records) and "data" when only research or the client's own tables say so.

  dungeons  codex/loot.json's dungeons (players' loot records from ForeverChanges, wowtbc.gg and QuestBank users),
            joined to the client's Map table for the instance id (GetInstanceInfo's eighth return) by name, else by
            where the client's encounter table puts their bosses; wings that share an instance (Scarlet Monastery,
            Dire Maul, Blackrock Spire) are one entry, as the game reports them, naming its wings in a field Rule 4
            reads (a run is one wing, so it doubts no boss there). Bosses are joined to DungeonEncounter
            by name within the instance at the dungeon's own difficulties, or through ALIAS where loot.json names the
            fight otherwise; a pooled entry (POOLED) gives each item to the fight whose boss drops it in the Classic
            database. The client's encounters loot.json lacks are seeded too. A loot.json boss no encounter fits is
            left out (the addon reads bosses by encounter), named in a comment; where a seeded fight there has no
            loot, NOT_THAT_FIGHT says why the boss is not that fight. Players' own loot records (QuestBank
            uploads) mark a fight they ended in the beta, and give it the items of a corpse known to be its boss (the
            game's own creature list, or Wowhead Forever's NPC id for it); a fight only linked by time gives none,
            since the trash looted after a kill is linked the same way. A dungeon the client has no map for yet is
            awaited (AWAITED, below): seeded by its name and level range alone, research's word, no instance id and
            no bosses, so the Guide can list it; an instance of that name two members entered (or where a kill a
            group mate named back was) gives it the instance's id. Any other dungeon that does not join stops the run.
  quests    loot.json's quests per dungeon (its wings' together), each with QuestBank's id where the title joins one
            in its catalog (Data.lua's D.Q and D.QN; several of one title narrowed by side, quest level, required
            level and the catalog's dungeon flag), the level it opens at and the side it is for: the Guide counts
            the ones open to you and asks the client whether you have done one (C_QuestLog, by id).
  enchants  codex/recipes.json's Enchanting recipes (not the Season of Discovery leftovers) whose spell enchants an
            item for good (SpellEffect 53) and that Forever has: new in Forever, taught by a trainer, or taught by a
            formula players' uploads or loot.json show, or the Classic database hands out outside its raids (sold, a
            quest's reward, dropped by a creature or held in a chest that stands outside them, or in a container that
            is); a formula only a Classic raid drops (Molten Core's, Ahn'Qiraj's) keeps its recipe out. Each spell's
            SpellEquippedItems row gives its slots (the inventory types it names, else the hands its weapon or shield
            kinds are held in) and its kinds (the subclass mask); a spell no item in the client's Item table passes
            the game's own test for is left out. Enchant items a Forever source shows obtainable (loot.json, players'
            uploads) are listed in the slots the recipes open and open none of their own: an armor kit or a scope does
            not make legs or the ranged slot count as missing an enchant; the guild teaches those (rule 5).
  xp        QuestBank's D.TO_NEXT (the XP to the next level the client reports), cross-checked against players'
            UnitXPMax readings.
  factions  the factions the quest rewards of Forever's quests name: QuestBank's catalog (quests Wowhead Forever or
            players have met, not its Classic-only or Season of Discovery entries) joined to CMaNGOS Classic's
            quest_template (RewRepFaction1-5, the client's QuestFactionReward table is only the reward amounts), then
            to the client's Faction table; headers (a faction other factions sit under) left out. Quests new in Forever
            have no reward data there, so the client's other factions with a standing are listed as unnamed, for the
            rules to learn.

Reads the newest Forever build under research/wago that has every table it needs, and the newest Classic Era build's
SpellEffect (its trainers' teaching spells name the recipes they teach; Forever's client lacks most of them).
Deterministic and idempotent: the file is rewritten only when a fact changes, and then dated. Python 3 standard
library only."""
import collections, csv, datetime, gzip, json, os, re, shutil, subprocess, sys, textwrap

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "Cute", "Known.lua")
WAGO = os.path.join(ROOT, "research", "wago")
LOOT = "codex/loot.json"
RECIPES = "codex/recipes.json"
QB_DATA = "tools/questbank/QuestBank/Data.lua"
DISC = "research/questbank/disc.json"
NPCS = "research/questbank/forever_npcs.json"
CMANGOS = "research/cmangos/ClassicDB.sql.gz"
TABLES = ("Map", "LFGDungeons", "DungeonEncounter", "SpellEffect", "SpellEquippedItems", "SpellItemEnchantment",
          "SpellName", "Item", "ItemSparse", "ItemEffect", "ItemXItemEffect", "Faction")

# the beta's level cap: Blizzard's notes of 2026-10-01 call that build the level-30 build, and players' UnitXPMax
# readings stop at 30 (the selftest fails if they ever go past it)
BETA_CAP = 30
# dungeons Forever's sources name that the client has no map for yet (no Map row in any 1.60.1 build under
# research/wago, no encounter, no LFG row): their instance ids are unknown, so they cannot be keyed and are left to the
# guild (rule 2 adds an instance once two members entered it). The selftest fails once one of them joins, so the
# list never outlives the client
AWAITED = ("The Drowned City", "Krol'dok Stronghold", "Alcaz Prison", "Blackmaw Hold", "Shaper's Terrace")
# DungeonEncounter difficulties of a dungeon run: 0 (any) and 1 (normal). The same bosses also sit under the Season
# of Discovery raids' difficulties (Blackfathom Deeps and Gnomeregan at 198 and 201, the Sunken Temple at 201 and
# 215); players' loot records in the beta name the 0 and 1 rows (2910-2916 in Blackfathom Deeps, 2768-2772 in
# Gnomeregan), never the others
DUNGEON_DIFFICULTIES = ("0", "1")
# loot.json bosses that are a fight the client's encounter table names otherwise: (instance, loot.json name) ->
# encounter, each with what shows it. The selftest fails on an entry that no longer joins or is no longer needed
ALIAS = {
    # Hall of Thanes: Wowhead Forever's NPC ids rise with the encounter ids (Faldrim Anvilmar 261306 is 3493, Plunder
    # 261311 is 3494, Durgen Dirgehammer 261319 is 3496), and Magmatus, 261316, is the one between: Infurnus, the fight
    # no other boss there holds
    (3065, "Magmatus"): 3495,
    # Ruins of Lordaeron: wowtbc.gg's name for ForeverChanges' Lordaeron Captain, with the same two items, 6641 and 6642
    (2999, "Deathsworn Captain"): 3408,
    # City of Dalaran: Wowhead Forever gives Arcanic Enigma and Mana Elemental one NPC, 246016, and one model
    (2959, "Arcanic Enigma"): 3301,
    # Uldaman: The Lost Dwarves, which the Classic database credits to Baelog; Eric and Olaf stand within sixteen yards
    # of him there
    (70, 'Eric "The Swift"'): 548, (70, "Baelog"): 548, (70, "Olaf"): 548,
    # Blackrock Depths: The Seven, which the Classic database credits to Anger'rel; the seven drop nothing themselves
    # there, and their chest, the Chest of The Seven, holds the items loot.json gives Doom'rel and Anger'rel
    (230, "Doom'rel"): 243, (230, "Anger'rel"): 243, (230, "Chest of The Seven"): 243,
    # Blackrock Depths: The Vault; in the Classic database Watchman Doomgrip, the Dark Coffer and the vault's Secret
    # Safe all hold 22254-22256
    (230, "Watchman Doomgrip"): 2791, (230, "Dark Coffer"): 2791,
    # The Temple of Atal'Hakkar: the Shade of Hakkar drops nothing in the Classic database, and its one item here,
    # 12462, is the Avatar's, the creature the fight is credited to
    (109, "Shade of Hakkar"): 3583,
    # Stratholme: Grand Crusader Dathrohan drops nothing in the Classic database, and his items here include 13353,
    # Balnazzar's, the creature the fight is credited to
    (329, "Grand Crusader Dathrohan"): 478,
    # Blackrock Spire: Gyth carries Rend into the fight; neither has a spawn of its own in the Classic database (a
    # script brings both), and the encounter table has no fight for Gyth
    (229, "Gyth"): 3063,
}
# loot.json entries that pool several fights' loot: each item goes to the one fight of the instance whose boss (the
# creature the Classic database credits the fight to) drops it there, the rest stays out
POOLED = {
    (230, "Guzzler"),  # the Grim Guzzler: Hurley Blackbreath's, Ribbly Screwspigot's and Plugger Spazzring's loot
}
# loot.json bosses left out in an instance where a seeded fight has no loot, looked at and found not to be that fight.
# The selftest fails on any other, so a fight's loot never stays under a name the addon drops
NOT_THAT_FIGHT = {
    (2999, "The Baron"): "new in Forever; the one fight here no boss holds is The Butcher (3355), and nothing ties them yet",
    (329, "Stratholme Courier"): "the Classic database credits no fight to the Courier, and has no Ezra Grimm (2797) at all",
    (329, "Balzaphon"): "a Scourge Invasion boss: the Classic database spawns him only with that event",
}
# a corpse's items players' records add to its boss: weapons, armor, recipes and quest items by the client's item
# class, as tools/apply_loot.py keeps them
KEEP_CLASS = {2, 4, 9, 12}
# SpellEffect.Effect 53: enchant an item for good (54 is a temporary enchant: oils, stones, poisons); 36: learn a spell
ENCHANT_ITEM = "53"
LEARN_SPELL = "36"
# inventory type (Item.InventoryType, the bit of SpellEquippedItems.EquippedItemInvTypes) -> the equipment slots the
# paper doll puts it in: a one-hand weapon in either hand, a ring or a trinket in either of two, relics, wands and
# thrown weapons in the ranged slot. Bags, ammo and quivers take no enchant
INVTYPE_SLOTS = {1: (1,), 2: (2,), 3: (3,), 4: (4,), 5: (5,), 6: (6,), 7: (7,), 8: (8,), 9: (9,), 10: (10,),
                 11: (11, 12), 12: (13, 14), 13: (16, 17), 14: (17,), 15: (18,), 16: (15,), 17: (16,), 19: (19,),
                 20: (5,), 21: (16,), 22: (17,), 23: (17,), 25: (18,), 26: (18,), 28: (18,)}
# the hands a weapon or a shield is held in by its subclass (Enum.ItemWeaponSubclass and Enum.ItemArmorSubclass in
# Forever's generated API docs, ItemConstantsDocumentation.lua), for a spell that names kinds of item and no inventory
# type: a weapon enchant names the weapon kinds, a shield enchant the shield. Cloth to plate, generic and cosmetic armor
# is worn in any slot, so a spell naming them names its inventory types too
HELD = {(2, s): (16, 17) for s in (0, 4, 7, 9, 13, 14, 15)}  # Axe1H, Mace1H, Sword1H, Warglaive, Unarmed, Generic, Dagger
HELD.update({(2, s): (16,) for s in (1, 5, 6, 8, 10, 17, 20)})  # Axe2H, Mace2H, Polearm, Sword2H, Staff, Obsolete3, Fishingpole
HELD.update({(2, s): (18,) for s in (2, 3, 16, 18, 19)})  # Bows, Guns, Thrown, Crossbow, Wand
HELD.update({(4, 6): (17,)})  # Shield
HELD.update({(4, s): (18,) for s in (7, 8, 9, 10, 11)})  # Libram, Idol, Totem, Sigil, Relic
ALL_BITS = 0xFFFFFFFF  # a subclass mask of -1: every subclass
SLOT_NAME = {1: "head", 2: "neck", 3: "shoulder", 4: "shirt", 5: "chest", 6: "waist", 7: "legs", 8: "feet",
             9: "wrist", 10: "hands", 11: "finger", 12: "finger", 13: "trinket", 14: "trinket", 15: "back",
             16: "main hand", 17: "off hand", 18: "ranged", 19: "tabard"}
# the slots the design says take no enchant in Forever yet (docs/superpowers/specs/2026-10-19-cute-known-and-rules-
# design.md: "No head, shoulder or legs"): the selftest fails when a recipe opens one, so the evidence is looked at
NO_ENCHANT_YET = (1, 3, 7)
# QuestBank's quest flags (Data.lua, D.Q): 16 Classic only (not met in Forever yet), 128 a Season of Discovery leftover
QB_NOT_FOREVER = 16 | 128
# Faction.ReputationFlags_0: 0x4 hidden, 0x8 invisible (profession specialisations and the like); Faction.Flags marks
# the client's own bookkeeping rows (PvP rank points, the legacy track)
FACTION_UNSEEN = 0x4 | 0x8
# the CMaNGOS Classic database's tables the seed reads and the columns of each (all whole numbers)
CLASSIC = {
    "quest_template": ("entry",) + tuple("RewRepFaction%d" % i for i in range(1, 6)) + tuple("RewRepValue%d" % i for i in range(1, 6))
                      + tuple("RewItemId%d" % i for i in range(1, 5)) + tuple("RewChoiceItemId%d" % i for i in range(1, 7)),
    "creature_template": ("Entry", "LootId", "VendorTemplateId"),
    "creature": ("guid", "id", "map"),
    "creature_spawn_entry": ("guid", "entry"),
    "gameobject_template": ("entry", "type", "data1"),
    "gameobject": ("guid", "id", "map"),
    "gameobject_spawn_entry": ("guid", "entry"),
    "npc_vendor": ("entry", "item"),
    "npc_vendor_template": ("entry", "item"),
    "npc_trainer": ("spell",),
    "npc_trainer_template": ("spell",),
    "instance_encounters": ("entry", "creditType", "creditEntry"),
    "instance_dungeon_encounters": ("Id", "MapId"),
}
# the loot templates read (<kind>_loot_template): a creature's corpse, a chest, a container item, and the shared
# references the others point to
LOOT_KINDS = ("creature", "gameobject", "item", "reference")
for _k in LOOT_KINDS:
    CLASSIC[_k + "_loot_template"] = ("entry", "item", "mincountOrRef")
# gameobject_template.type of a chest, whose data1 is its loot template
CHEST = 3


class Fail(Exception):
    pass


def path(rel):
    return os.path.join(ROOT, rel)


def norm(s):
    """a name as the joins compare it: case, punctuation and a leading "The" ignored"""
    s = re.sub(r"[^a-z0-9 ]+", "", s.lower().replace("’", "'"))
    s = " ".join(s.split())
    return s[4:] if s.startswith("the ") else s


def qb_catalog(qb):
    """QuestBank's catalog (Data.lua): {id: (quest level, required level, side 0 both 1 Alliance 2 Horde, flags)} from
    D.Q, and {id: title} from D.QN"""
    m = re.search(r"^D\.Q = \{\n(.*?)\n\}", qb, re.S | re.M)
    if not m:
        raise Fail("%s has no D.Q" % QB_DATA)
    quests = {}
    for q, b in re.findall(r"^\[(\d+)\]=\{([^}]*)\}", m.group(1), re.M):
        f = b.split(",")
        quests[int(q)] = (int(f[0]), int(f[1]), int(f[2]), int(f[9]))
    m = re.search(r"^D\.QN = \{(.*)\}$", qb, re.M)
    if not m:
        raise Fail("%s has no D.QN" % QB_DATA)
    names = {int(q): n.replace('\\"', '"') for q, n in re.findall(r'\[(\d+)\]="((?:[^"\\]|\\.)*)"', m.group(1))}
    return quests, names


def pick_build():
    """the newest 1.60.1 build (Forever's client) under research/wago that has every table; newer ones without are
    named so a partial download is never read silently"""
    builds = []
    for d in os.listdir(WAGO):
        m = re.match(r"^1\.60\.1\.(\d+)$", d)
        if m:
            builds.append((int(m.group(1)), d))
    skipped = []
    for _, d in sorted(builds, reverse=True):
        missing = [t for t in TABLES if not os.path.isfile(os.path.join(WAGO, d, t + ".csv"))]
        if not missing:
            return d, skipped
        skipped.append("%s (no %s)" % (d, ", ".join(missing)))
    raise Fail("no 1.60.1 build under research/wago has every table: " + "; ".join(skipped))


def pick_era():
    """the newest Classic Era build (1.15) under research/wago with a SpellEffect table"""
    builds = sorted((tuple(int(x) for x in d.split(".")), d) for d in os.listdir(WAGO)
                    if re.match(r"^1\.15\.\d+\.\d+$", d) and os.path.isfile(os.path.join(WAGO, d, "SpellEffect.csv")))
    if not builds:
        raise Fail("no Classic Era build (1.15) under research/wago has SpellEffect.csv: the trainers' recipes are unknown")
    return builds[-1][1]


def table(build, name, cols=None):
    """a client table as dicts (only the columns named, for the wide ones)"""
    with open(os.path.join(WAGO, build, name + ".csv"), encoding="utf-8", newline="") as f:
        rd = csv.reader(f)
        head = next(rd)
        idx = [(c, head.index(c)) for c in (cols or head)]
        return [{c: r[i] for c, i in idx} for r in rd]


SQL_FIELD = re.compile(r"'((?:[^'\\]|\\.)*)'|(NULL)|(-?[\d.eE+-]+)")


def sql_rows(values):
    """the tuples of one INSERT ... VALUES line (tools/questbank/cmangos.py reads the dump the same way)"""
    i, n = 0, len(values)
    while i < n:
        if values[i] != "(":
            i += 1
            continue
        i += 1
        row = []
        while True:
            m = SQL_FIELD.match(values, i)
            if not m:
                raise Fail("%s: bad value at %d" % (CMANGOS, i))
            s, null, num = m.groups()
            row.append(s if s is not None else None if null else num)
            i = m.end()
            if values[i] == ",":
                i += 1
                continue
            if values[i] == ")":
                i += 1
                break
            raise Fail("%s: unexpected %r at %d" % (CMANGOS, values[i], i))
        yield row


def classic_tables():
    """CLASSIC's tables from the CMaNGOS Classic database, each row a dict of its columns"""
    cols, table_, out = {}, None, {t: [] for t in CLASSIC}
    with gzip.open(path(CMANGOS), "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("CREATE TABLE `"):
                table_ = line.split("`")[1]
                cols[table_] = []
                continue
            if table_ and line.startswith("  `"):
                cols[table_].append(line.split("`")[1])
                continue
            if line.startswith("INSERT INTO `"):
                t = line.split("`")[1]
                if t not in CLASSIC:
                    continue
                missing = [c for c in CLASSIC[t] if c not in cols.get(t, ())]
                if missing:
                    raise Fail("%s: %s has no %s" % (CMANGOS, t, ", ".join(missing)))
                idx = [(c, cols[t].index(c)) for c in CLASSIC[t]]
                body = line[line.index("VALUES") + 6:].strip().rstrip(";")
                for r in sql_rows(body):
                    out[t].append({c: int(float(r[i])) if r[i] is not None else 0 for c, i in idx})
    empty = [t for t in ("quest_template", "creature", "creature_loot_template", "instance_encounters") if not out[t]]
    if empty:
        raise Fail("%s has no rows for %s" % (CMANGOS, ", ".join(empty)))
    return out


# ---------------------------------------------------------------- the Classic database
class Classic:
    """the CMaNGOS Classic database, read once: quest rewards, where creatures and chests stand, who sells, gives,
    drops or holds an item, the trainers' spells, and the creature each fight is credited to"""

    def __init__(self, maps):
        t = classic_tables()
        self.raid = {m for m, r in maps.items() if r["InstanceType"] == "2"}
        self.map_name = {m: r["MapName_lang"] for m, r in maps.items()}
        self.rep, self.rewarded = {}, set()  # quest -> [(faction, amount)]; items some quest gives
        for r in t["quest_template"]:
            self.rep[r["entry"]] = [(r["RewRepFaction%d" % i], r["RewRepValue%d" % i]) for i in range(1, 6) if r["RewRepFaction%d" % i]]
            self.rewarded.update(r[c] for c in CLASSIC["quest_template"][11:] if r[c])

        def stands(spawns, alt):
            """entry -> the maps its spawns stand in (a spawn may stand for one of several entries)"""
            out, of = collections.defaultdict(set), collections.defaultdict(list)
            for r in alt:
                of[r["guid"]].append(r["entry"])
            for r in spawns:
                for e in ([r["id"]] if r["id"] else of.get(r["guid"], ())):
                    out[e].add(r["map"])
            return out
        self.creature_maps = stands(t["creature"], t["creature_spawn_entry"])
        self.object_maps = stands(t["gameobject"], t["gameobject_spawn_entry"])
        self.by_loot, self.loot_id = collections.defaultdict(list), {}  # loot template -> creatures; creature -> its template
        vendor_template = collections.defaultdict(set)
        for r in t["npc_vendor_template"]:
            vendor_template[r["entry"]].add(r["item"])
        self.sold = collections.defaultdict(set)  # item -> the creatures selling it
        for r in t["npc_vendor"]:
            self.sold[r["item"]].add(r["entry"])
        for r in t["creature_template"]:
            self.loot_id[r["Entry"]] = r["LootId"]
            if r["LootId"]:
                self.by_loot[r["LootId"]].append(r["Entry"])
            for item in vendor_template.get(r["VendorTemplateId"], ()):
                self.sold[item].add(r["Entry"])
        self.chests = collections.defaultdict(list)  # loot template -> the chests opening it
        for r in t["gameobject_template"]:
            if r["type"] == CHEST and r["data1"]:
                self.chests[r["data1"]].append(r["entry"])
        self.holds = collections.defaultdict(list)  # item -> [(kind, template)] listing it
        self.refs = collections.defaultdict(list)  # reference template -> [(kind, template)] pointing to it
        self.creature_loot = collections.defaultdict(set)  # creature loot template -> the items it lists itself
        for kind in LOOT_KINDS:
            for r in t[kind + "_loot_template"]:
                if r["mincountOrRef"] < 0:
                    self.refs[-r["mincountOrRef"]].append((kind, r["entry"]))
                    continue
                self.holds[r["item"]].append((kind, r["entry"]))
                if kind == "creature":
                    self.creature_loot[r["entry"]].add(r["item"])
        self.trainer_spells = {r["spell"] for k in ("npc_trainer", "npc_trainer_template") for r in t[k]}
        self.credit = {r["entry"]: r["creditEntry"] for r in t["instance_encounters"] if r["creditType"] == 0}
        self.fight_map = {r["Id"]: r["MapId"] for r in t["instance_dungeon_encounters"]}

    def holders(self, kind, entry, seen=None):
        """the templates that hand out a template's items: itself, or, for a shared reference, those pointing to it"""
        if kind != "reference":
            yield kind, entry
            return
        seen = set() if seen is None else seen
        if entry in seen:
            return
        seen.add(entry)
        for k, e in self.refs.get(entry, ()):
            yield from self.holders(k, e, seen)

    def outside(self, maps):
        """a creature or a chest that stands somewhere, and nowhere in a Classic raid"""
        return bool(maps) and not (maps & self.raid)

    def elsewhere(self, item, depth=0):
        """how the Classic database hands an item out outside its raids, or None: sold, a quest's reward, dropped by
        a creature or held in a chest that stands outside them, or in a container that is handed out so"""
        if any(self.outside(self.creature_maps.get(v)) for v in sorted(self.sold.get(item, ()))):
            return "sold"
        if item in self.rewarded:
            return "a quest's reward"
        for kind, entry in self.holds.get(item, ()):
            for k, e in self.holders(kind, entry):
                if k == "creature" and any(self.outside(self.creature_maps.get(c)) for c in self.by_loot.get(e, ())):
                    return "dropped"
                if k == "gameobject" and any(self.outside(self.object_maps.get(g)) for g in self.chests.get(e, ())):
                    return "in a chest"
                if k == "item" and depth < 3 and self.elsewhere(e, depth + 1):
                    return "in a container"
        return None

    def raid_drops(self, item):
        """the Classic raids an item drops in, when creatures standing in them are all that hand it out, else None"""
        if self.elsewhere(item):
            return None
        maps = set()
        for kind, entry in self.holds.get(item, ()):
            for k, e in self.holders(kind, entry):
                if k == "creature":
                    for c in self.by_loot.get(e, ()):
                        maps |= self.creature_maps.get(c, set()) & self.raid
        return sorted(self.map_name.get(m, str(m)) for m in maps) or None

    def credited_drops(self, enc, mid):
        """the items the creature a fight is credited to drops itself (no shared reference), when the Classic
        database has that fight in that instance"""
        if self.fight_map.get(enc) != mid or enc not in self.credit:
            return set()
        return self.creature_loot.get(self.loot_id.get(self.credit[enc]), set())


# ---------------------------------------------------------------- sources
class Sources:
    def __init__(self):
        self.build, self.skipped = pick_build()
        self.era = pick_era()
        b = self.build
        self.read = ([LOOT, RECIPES] + ["research/wago/%s/%s.csv" % (b, t) for t in TABLES]
                     + ["research/wago/%s/SpellEffect.csv" % self.era, QB_DATA, DISC, NPCS, CMANGOS])
        self.loot = json.load(open(path(LOOT), encoding="utf-8"))
        self.recipes = json.load(open(path(RECIPES), encoding="utf-8"))
        self.disc = json.load(open(path(DISC), encoding="utf-8"))
        self.npc_of = {norm(n): v["npc"] for n, v in json.load(open(path(NPCS), encoding="utf-8")).items() if v.get("npc")}
        self.maps = {int(r["ID"]): r for r in table(b, "Map", ["ID", "MapName_lang", "InstanceType"])}
        self.lfg = table(b, "LFGDungeons", ["ID", "Name_lang", "MapID"])
        self.enc = [{"name": r["Name_lang"], "id": int(r["ID"]), "map": int(r["MapID"]), "diff": r["DifficultyID"],
                     "order": int(r["OrderIndex"])} for r in table(b, "DungeonEncounter")]
        self.spell_name = {int(r["ID"]): r["Name_lang"] for r in table(b, "SpellName")}
        self.ench_ids = {int(r["ID"]) for r in table(b, "SpellItemEnchantment", ["ID"])}
        self.enchant_of = {}  # spell -> the enchant its Effect 53 applies (the lowest effect index on difficulty 0)
        for r in sorted(table(b, "SpellEffect", ["SpellID", "Effect", "EffectMiscValue_0", "DifficultyID", "EffectIndex"]),
                        key=lambda r: (int(r["DifficultyID"]), int(r["EffectIndex"]))):
            if r["Effect"] == ENCHANT_ITEM:
                self.enchant_of.setdefault(int(r["SpellID"]), int(r["EffectMiscValue_0"]))
        self.equipped = collections.defaultdict(list)  # spell -> [(class, subclass mask, inventory type mask)]
        for r in sorted(table(b, "SpellEquippedItems"), key=lambda r: int(r["ID"])):
            self.equipped[int(r["SpellID"])].append(
                (int(r["EquippedItemClass"]), int(r["EquippedItemSubclass"]) & 0xFFFFFFFF, int(r["EquippedItemInvTypes"]) & 0xFFFFFFFF))
        self.items = {int(r["ID"]): (int(r["ClassID"]), int(r["SubclassID"]), int(r["InventoryType"]))
                      for r in table(b, "Item", ["ID", "ClassID", "SubclassID", "InventoryType"])}
        self.item_kinds = set(self.items.values())  # (class, subclass, inventory type) of the client's items
        sparse = table(b, "ItemSparse", ["ID", "Display_lang", "RequiredLevel"])
        self.item_name = {int(r["ID"]): r["Display_lang"] for r in sparse}
        self.item_level = {int(r["ID"]): int(r["RequiredLevel"] or 0) for r in sparse}
        effects = {int(r["ID"]): r for r in table(b, "ItemEffect", ["ID", "TriggerType", "SpellID"])}
        self.item_use = collections.defaultdict(list)  # item -> its on-use spells
        for r in table(b, "ItemXItemEffect", ["ItemEffectID", "ItemID"]):
            e = effects.get(int(r["ItemEffectID"]))
            if e and e["TriggerType"] == "0":
                self.item_use[int(r["ItemID"])].append(int(e["SpellID"]))
        self.factions = {int(r["ID"]): r for r in table(b, "Faction", ["ID", "Name_lang", "ReputationIndex", "ParentFactionID",
                                                                        "ReputationFlags_0", "Flags"])}
        self.qb = open(path(QB_DATA), encoding="utf-8").read()
        self.qb_quests, self.qb_names = qb_catalog(self.qb)
        self.qb_by_name = collections.defaultdict(list)  # a title as the joins compare it -> the catalog's ids
        for q, n in sorted(self.qb_names.items()):
            if q in self.qb_quests:
                self.qb_by_name[norm(n)].append(q)
        self.classic = Classic(self.maps)
        # the recipes Classic trainers teach: the trainer's spell itself, or the recipe its learn effect names (the Era
        # client has the teaching spells)
        self.trained = set(self.classic.trainer_spells)
        for r in table(self.era, "SpellEffect", ["SpellID", "Effect", "EffectTriggerSpell"]):
            if r["Effect"] == LEARN_SPELL and int(r["SpellID"]) in self.classic.trainer_spells:
                self.trained.add(int(r["EffectTriggerSpell"]))
        self.uploaded = self.uploaded_items()
        self.looted = self.loot_items()

    def uploaded_items(self):
        """item ids players' uploads show in the beta: in bags or worn, tooltips read, items looted"""
        pr, out = self.disc.get("probe", {}), set()
        for k in list(pr.get("items", {})) + list(pr.get("tips", {})):
            out.add(int(k))
        for rec in self.disc.get("loot", {}).values():
            out.update(int(k) for k in rec.get("i", {}))
        return out

    def loot_items(self):
        out = set()
        for d in self.loot["dungeons"]:
            for b in d["bosses"]:
                out.update(b["items"])
            for q in d["quests"]:
                out.update(q["items"])
        return out

    def fights(self):
        """{instance: {encounter: [(record key, record)]}}: the fights players' loot records say a kill ended, by the
        game's own creature list (e) or by time (ei)"""
        out = collections.defaultdict(lambda: collections.defaultdict(list))
        for key, rec in sorted(self.disc.get("loot", {}).items()):
            for m in rec.get("im", {}):
                for e in sorted(set(rec.get("e", {})) | set(rec.get("ei", {}))):
                    out[int(m)][int(e)].append((key, rec))
        return out


# ---------------------------------------------------------------- dungeons and bosses
def near(a, b):
    """two names for one boss: one the start of the other (Kirtonos the Herald and the encounter Kirtonos, Ras
    Frostwhisper and Ras Frostwhisperer), or one letter apart (Gelihast and Geilhast); the shorter at least five
    letters, so a word alone joins nothing"""
    short, long_ = sorted((a, b), key=len)
    if len(short) < 5 or a == b:
        return False
    if long_.startswith(short):
        return True
    if len(long_) - len(short) > 1 or len(short) < 6:
        return False
    if len(a) == len(b):
        diff = [i for i in range(len(a)) if a[i] != b[i]]
        return len(diff) == 1 or (len(diff) == 2 and diff[1] == diff[0] + 1 and a[diff[0]] == b[diff[1]] and a[diff[1]] == b[diff[0]])
    return any(long_[:i] + long_[i + 1:] == short for i in range(len(long_)))


SIDE = {1: "a", 2: "h"}


def quest_id(src, q, report):
    """the id of a dungeon quest loot.json names, from QuestBank's catalog: the title's ids, narrowed while more than
    one is left by the side, the quest level, the required level, the catalog's dungeon flag and its Forever flags in
    turn (a step that would leave none is skipped). None where none or several are left: the Guide then names the quest
    and cannot ask the client whether it was done"""
    ids = list(src.qb_by_name.get(norm(q["name"]), ()))
    side = q.get("side")
    steps = (
        lambda i: side not in ("a", "h") or src.qb_quests[i][2] in (0, 1 if side == "a" else 2),
        lambda i: q.get("level") is None or src.qb_quests[i][0] == q["level"],
        lambda i: q.get("min") is None or src.qb_quests[i][1] == q["min"],
        lambda i: src.qb_quests[i][3] & 1,
        lambda i: not src.qb_quests[i][3] & QB_NOT_FOREVER,
    )
    for keep in steps:
        if len(ids) <= 1:
            break
        narrowed = [i for i in ids if keep(i)]
        if narrowed:
            ids = narrowed
    if len(ids) == 1:
        return ids[0]
    report["quests"]["ambiguous" if ids else "unknown"].add(q["name"])
    return None


def join_quests(src, ws, report):
    """a dungeon's quests, its wings' together (Scarlet Monastery's wings share theirs): each once, by id, else by
    title and side; [{name, id, level, min, side}], side "a" or "h" for one faction's, none for both or not known (the
    catalog's side where loot.json gives none). Ordered by the level they open at, then title"""
    out, seen = [], set()
    for w in ws:
        for q in w["quests"]:
            qid = quest_id(src, q, report)
            side = q.get("side") if q.get("side") in ("a", "h") else None
            if side is None and qid is not None:
                side = SIDE.get(src.qb_quests[qid][2])
            key = qid if qid is not None else (norm(q["name"]), side)
            if key in seen:
                continue
            seen.add(key)
            level = q.get("level") or (src.qb_quests[qid][0] if qid is not None else None)
            low = q.get("min") or (src.qb_quests[qid][1] if qid is not None else None)
            out.append({"name": q["name"], "id": qid, "level": level, "min": low, "side": side})
    return sorted(out, key=lambda q: (q["min"] or q["level"] or 0, q["name"], q["id"] or 0))


def join_dungeons(src, report):
    inst = {i: r for i, r in src.maps.items() if r["InstanceType"] in ("1", "2")}
    by_name = collections.defaultdict(set)
    for i, r in inst.items():
        by_name[norm(r["MapName_lang"])].add(i)
    lfg_maps = 0
    for r in src.lfg:  # LFGDungeons names a map on no row in today's client (MapID 0); used as soon as it does
        m = int(r["MapID"])
        if m in inst:
            by_name[norm(r["Name_lang"])].add(m)
            lfg_maps += 1
    report["lfg_maps"] = lfg_maps
    normal = [e for e in src.enc if e["diff"] in DUNGEON_DIFFICULTIES]
    maps_of_boss = collections.defaultdict(set)
    for e in normal:
        if e["map"] in inst:
            maps_of_boss[norm(e["name"])].add(e["map"])

    wings, awaited, failed = collections.defaultdict(list), [], []
    for d in src.loot["dungeons"]:
        names = [d["name"]] + ([d["name"].split(":")[0]] if ":" in d["name"] else [])
        named = set()
        for n in names:
            named = by_name.get(norm(n), set())
            if named:
                break
        votes = collections.Counter()
        for b in d["bosses"]:
            for m in maps_of_boss.get(norm(b["name"]), ()):
                votes[m] += 1
        top = votes.most_common(2)
        by_bosses = top[0][0] if top and (len(top) == 1 or top[0][1] > top[1][1]) else None
        if len(named) == 1:
            mid = next(iter(named))
            if by_bosses is not None and by_bosses != mid:
                failed.append("%s: its name is map %d, its bosses map %d" % (d["name"], mid, by_bosses))
                continue
        elif len(named) > 1:
            mid = by_bosses if by_bosses in named else None
            if mid is None:
                failed.append("%s: its name fits maps %s and its bosses settle nothing" % (d["name"], sorted(named)))
                continue
        else:
            mid = by_bosses
        if mid is None:
            if d["name"] in AWAITED:
                awaited.append(d)
                continue
            failed.append("%s: no instance in the client's Map table has its name or its bosses" % d["name"])
            continue
        if d["name"] in AWAITED:
            report["awaited_joined"].append("%s (map %d)" % (d["name"], mid))
        wings[mid].append(d)
    for n in AWAITED:
        if not any(d["name"] == n for d in src.loot["dungeons"]):
            report["awaited_gone"].append(n)
    if failed:
        raise Fail("dungeons with no instance id:\n  " + "\n  ".join(failed))

    fights = src.fights()
    dungeons = {}
    for mid, ws in wings.items():
        row = inst[mid]
        low = min(w["levels"][0] for w in ws)
        encs = sorted((e for e in normal if e["map"] == mid), key=lambda e: (e["order"], e["id"]))
        by_n = collections.defaultdict(list)
        for e in encs:
            by_n[norm(e["name"])].append(e)
        by_id = {e["id"]: e for e in encs}
        others = collections.defaultdict(list)  # the same names at the raid difficulties or in other maps
        for e in src.enc:
            if not (e["map"] == mid and e["diff"] in DUNGEON_DIFFICULTIES):
                others[norm(e["name"])].append(e)
        # loot.json names a fight of several bosses "Encounter: boss" (Blackrock Depths' "Ring of Law: Grizzle"), and
        # may name the same boss again alone: both are that encounter's
        alias = {}
        for w in ws:
            for b in w["bosses"]:
                if ":" in b["name"] and norm(b["name"]) not in by_n:
                    head, tail = b["name"].split(":", 1)
                    if norm(head) in by_n:
                        alias[norm(tail)] = by_n[norm(head)]
        joined, left, pooled = {}, [], []

        def fight(e):
            return joined.setdefault(e["id"], {"name": e["name"], "enc": e["id"], "loot": [], "beta": False, "e": e,
                                               "names": [], "aka": [], "pooled": []})

        def give(j, items):
            j["loot"] += [i for i in dict.fromkeys(items) if i not in j["loot"]]

        for w in ws:
            wing_beta = w["levels"][0] <= BETA_CAP
            for b in w["bosses"]:
                es = by_n.get(norm(b["name"])) or by_n.get(norm(b["name"].split(":")[0])) or alias.get(norm(b["name"]))
                if not es and b["kind"] == "boss":  # a rare or trash sharing a boss's first name stays out (Aku'mai Snapjaw)
                    close = [n for n in by_n if near(norm(b["name"]), n)]
                    if len(close) == 1:
                        es = by_n[close[0]]
                        report["near"].append("%s / %s = %s (%d)" % (w["name"], b["name"], es[0]["name"], es[0]["id"]))
                aka = None
                if not es and (mid, b["name"]) in ALIAS:
                    report["alias_used"].add((mid, b["name"]))
                    e = by_id.get(ALIAS[(mid, b["name"])])
                    if e:
                        es, aka = [e], b["name"]
                    else:
                        report["alias_bad"].append("%s / %s: encounter %d is not a dungeon encounter of map %d"
                                                   % (w["name"], b["name"], ALIAS[(mid, b["name"])], mid))
                elif es and (mid, b["name"]) in ALIAS:
                    report["alias_needless"].append("%s / %s joins by name now" % (w["name"], b["name"]))
                if es:
                    j = fight(es[0])
                    give(j, b["items"])
                    j["beta"] = j["beta"] or (wing_beta and bool(b["src"]))
                    j["names"].append(b["name"])
                    if aka:
                        j["aka"].append(aka)
                elif (mid, b["name"]) in POOLED:
                    pooled.append((b, wing_beta))
                elif b["kind"] == "boss":
                    o = others.get(norm(b["name"]), [])
                    here = sorted({x["diff"] for x in o if x["map"] == mid})
                    there = sorted({x["map"] for x in o if x["map"] != mid})
                    why = NOT_THAT_FIGHT.get((mid, b["name"])) or (
                        "the encounter table has it here only at difficulty %s, a Season of Discovery raid's" % "/".join(here)
                        if here else "the encounter table puts it in map %s" % "/".join(map(str, there))
                        if there else "not in the client's encounter table for map %d" % mid)
                    left.append({"name": b["name"], "loot": list(dict.fromkeys(b["items"])), "why": why})
                # anything else with no encounter (a rare, trash, a chest, a quest NPC) is not a boss
        # a pooled entry: each item to the one fight whose credited creature drops it in the Classic database
        for b, wing_beta in pooled:
            report["pooled_used"].add((mid, b["name"]))
            placed = collections.defaultdict(list)
            for i in dict.fromkeys(b["items"]):
                to = [e for e in encs if i in src.classic.credited_drops(e["id"], mid)]
                if len(to) == 1:
                    placed[to[0]["id"]].append(i)
            for k in placed:
                j = fight(by_id[k])
                give(j, placed[k])
                j["beta"] = j["beta"] or (wing_beta and bool(b["src"]))
                j["pooled"].append(b["name"])
            report["pooled"].append({"n": sum(map(len, placed.values())), "text": "%s / %s: %d of its %d items to %s" % (
                ws[0]["name"] if len(ws) == 1 else row["MapName_lang"], b["name"], sum(map(len, placed.values())),
                len(set(b["items"])), ", ".join("%s (%d)" % (by_id[k]["name"], len(placed[k])) for k in sorted(placed)) or "none")})
        for e in encs:
            if e["id"] not in joined:
                fight(e)["client"] = True
        # players' loot records: a fight a kill ended in the beta's range, and the items of a corpse known to be its
        # boss (the game's own creature list, or the NPC id Wowhead Forever gives a name it goes by)
        for k, j in joined.items():
            recs = fights.get(mid, {}).get(k, [])
            if not recs or low > BETA_CAP:
                continue
            j["beta"] = j["players"] = True
            npcs = {src.npc_of[norm(n)] for n in [j["name"]] + j["names"] if norm(n) in src.npc_of}
            for key, rec in recs:
                if key[0] == "c" and (str(k) in rec.get("e", {}) or int(key[1:]) in npcs):
                    items = sorted((int(i) for i in rec.get("i", {}) if int(i) in src.items and src.items[int(i)][0] in KEEP_CLASS),
                                   key=lambda i: (-rec["i"][str(i)]["v"], i))
                    new = [i for i in items if i not in j["loot"]]
                    if new:
                        give(j, new)
                        j["recorded"] = True
        bosses = [joined[k] for k in sorted(joined, key=lambda k: (joined[k]["e"]["order"], k))]
        dungeons[mid] = {
            "name": ws[0]["name"] if len(ws) == 1 else row["MapName_lang"],
            "min": low, "max": max(w["levels"][1] for w in ws),
            "new": any(w["new"] for w in ws), "conf": "beta" if any(
                w["levels"][0] <= BETA_CAP and any(b["src"] for b in w["bosses"]) for w in ws) else "data",
            "kind": "party" if row["InstanceType"] == "1" else "raid", "bosses": bosses, "left": left,
            "wings": [w["name"] for w in ws] if len(ws) > 1 else None,
            "quests": join_quests(src, ws, report),
        }
    # an awaited dungeon is seeded by its name and level range alone, research's word (no instance id to key it, no
    # boss the addon could read without one): the Guide lists it, and an instance of that name two members entered, or
    # where a kill a group mate named back was, gives it the instance's id (Rules.lua, R:Rebuild)
    awaited = [{"name": d["name"], "min": d["levels"][0], "max": d["levels"][1], "new": bool(d["new"]), "conf": "data",
                "kind": "party", "quests": join_quests(src, [d], report)} for d in awaited]
    return dungeons, awaited


# ---------------------------------------------------------------- enchants
def bits(mask):
    return [b for b in range(32) if (mask >> b) & 1]


def merge(out, slot, kinds):
    """add kinds (None: any kind) to a slot's"""
    if slot not in out:
        out[slot] = None if kinds is None else set(kinds)
    elif out[slot] is None or kinds is None:
        out[slot] = None
    else:
        out[slot] |= kinds


def target(src, spell):
    """{slot: {"class.subclass"} or None for any kind} a spell enchants, by its SpellEquippedItems row: the slots of
    the inventory types it names, else the hands its weapon or shield kinds are held in (HELD); kinds from its subclass
    mask, any kind when the mask names every subclass. Nothing when no item in the client's Item table passes the
    game's own test (the class, the subclass in the mask, the inventory type in the mask): Enchant Cloak - Minor
    Agility names the weapon class and the cloak's inventory type, which no item is"""
    out = {}
    for cls, sub, inv in src.equipped.get(spell, ()):
        any_sub = sub in (0, ALL_BITS)
        if not any((cls == -1 or c == cls) and (any_sub or (sub >> s) & 1) and (not inv or (inv >> t) & 1)
                   for c, s, t in src.item_kinds):
            continue
        if inv:
            kinds = None if any_sub or cls == -1 else {"%d.%d" % (cls, s) for s in bits(sub)}
            for t in bits(inv):
                for slot in INVTYPE_SLOTS.get(t, ()):
                    merge(out, slot, kinds)
        else:
            for s in (sorted(s for c, s in HELD if c == cls) if any_sub else bits(sub)):
                for slot in HELD.get((cls, s), ()):
                    merge(out, slot, {"%d.%d" % (cls, s)})
    return out


def recipe_source(src, r):
    """why Forever has an Enchanting recipe, or None: new in Forever, a trainer teaches it, it comes with the
    profession, or a formula teaching it is one players' uploads or loot.json show, or the Classic database hands out
    outside its raids"""
    if r.get("nw") or r.get("rs"):
        return "new in Forever"
    if r.get("cl") or r["s"] in src.trained:
        return "a trainer"
    if "by" not in r:
        return "with the profession" if r.get("auto") else None
    if any(i in src.uploaded for i in r["by"]):
        return "players' uploads"
    if any(i in src.looted for i in r["by"]):
        return "loot.json"
    for i in r["by"]:
        how = src.classic.elsewhere(i)
        if how:
            return "Classic: " + how
    return None


def join_enchants(src, report):
    slots, lists = {}, collections.defaultdict(dict)
    rep = report["enchants"]

    def enchant(spell, name):
        """(enchant, {slot: kinds}) for a spell that enchants an item for good, else None (counted in the report)"""
        ench = src.enchant_of.get(spell)
        if ench is None:
            rep["not_item_enchant"] += 1  # oils, rods, wands, essences: no permanent enchant
            return None
        if ench not in src.ench_ids:
            rep["problems"].append("%s (%d): enchant %d is not in SpellItemEnchantment" % (name, spell, ench))
            return None
        if spell not in src.spell_name:
            rep["problems"].append("%s (%d): not in the client's spell table" % (name, spell))
            return None
        f = target(src, spell)
        if not f:
            rep["fits_nothing"].append("%s (%d): %s" % (name, spell, src.equipped.get(spell) or "no SpellEquippedItems row"))
            return None
        return ench, f

    def add(slot, kinds, spell, name, ench):
        merge(slots, slot, kinds)
        e = lists[slot].setdefault(spell, {"spell": spell, "name": name, "ench": ench})  # a recipe's name before an item's
        # each enchant keeps its own kinds too (a sword's enchant is not a shield's), so the Guide can name the ones that
        # fit the item worn; None: any kind of item in the slot
        if "kinds" not in e: e["kinds"] = None if kinds is None else set(kinds)
        elif e["kinds"] is not None: e["kinds"] = None if kinds is None else e["kinds"] | set(kinds)

    for r in src.recipes["recipes"]:
        if r["p"] != "Enchanting":
            continue
        if r.get("e") == "sod":
            rep["sod"] += 1
            continue
        name = src.spell_name.get(r["s"], r["n"])
        hit = enchant(r["s"], name)
        if not hit:
            continue
        how = recipe_source(src, r)
        if how is None:
            raids = [src.classic.raid_drops(i) for i in r.get("by", ())]
            rep["no_source"].append({"name": name, "spell": r["s"], "by": r.get("by", []),
                                     "raids": sorted({m for x in raids if x for m in x}) if raids and all(raids) else None})
            continue
        rep["how"][how] += 1
        rep["recipe"][r["s"]] = r
        for slot, kinds in hit[1].items():
            add(slot, kinds, r["s"], name, hit[0])
    opened = set(slots)
    # enchant items: an on-use spell that enchants an item for good, not a recipe that teaches one (item class 9).
    # They are listed in the slots the recipes open and open none of their own
    crafted = {r["m"] for r in src.recipes["recipes"] if "m" in r and r.get("e") != "sod"}
    for item in sorted(src.item_use):
        spells = [s for s in src.item_use[item] if s in src.enchant_of]
        info = src.items.get(item)
        if not spells or (info and info[0] == 9):
            continue
        iname = src.item_name.get(item)
        if item in src.uploaded or item in src.looted:
            for s in spells:
                hit = enchant(s, iname or src.spell_name.get(s, "item %d" % item))
                if not hit:
                    continue
                for slot, kinds in hit[1].items():
                    if slot in opened:
                        add(slot, kinds, s, iname or src.spell_name.get(s, "item %d" % item), hit[0])
                        rep["item_spells"].add(s)
                    else:
                        lv = src.item_level.get(item, 0)
                        rep["item_only"][slot].append("%s (%d%s)" % (iname or "?", item, ", level %d" % lv if lv > 1 else ""))
            rep["items_why"].append("%s (%d): %s" % (iname or "?", item, "players' uploads" if item in src.uploaded else "loot.json"))
            continue
        why = ("recipe_spell" if all(s in rep["recipe"] for s in spells) else
               "crafted" if item in crafted else "other")
        rep["left_out"][why] += 1
        for slot in {slot for s in spells for slot in target(src, s)}:
            rep["left_out_slot"][slot] += 1
    for entries in lists.values():
        for e in entries.values():
            if e.get("kinds") is not None: e["kinds"] = sorted(e["kinds"], key=kind_key)
    return {slot: {"conf": "data", "kinds": None if kinds is None else sorted(kinds, key=kind_key),
                   "list": sorted(lists[slot].values(), key=lambda e: (e["name"].lower(), e["spell"]))}
            for slot, kinds in slots.items()}


def kind_key(k):
    c, s = k.split(".")
    return int(c), int(s)


# ---------------------------------------------------------------- xp and factions
def join_xp(src):
    m = re.search(r"^D\.TO_NEXT = \{([\d,\s]+)\}", src.qb, re.M)
    if not m:
        raise Fail("%s has no D.TO_NEXT" % QB_DATA)
    xp = [int(x) for x in m.group(1).split(",") if x.strip()]
    return {i + 1: v for i, v in enumerate(xp)}


def join_factions(src, report):
    m = re.search(r"^D\.Q = \{\n(.*?)\n\}", src.qb, re.S | re.M)
    if not m:
        raise Fail("%s has no D.Q" % QB_DATA)
    quests = {int(q): int(b.split(",")[9]) for q, b in re.findall(r"^\[(\d+)\]=\{([^}]*)\}", m.group(1), re.M)}
    forever = sorted(q for q, flags in quests.items() if not flags & QB_NOT_FOREVER)
    rewards = src.classic.rep
    parents = {int(r["ParentFactionID"]) for r in src.factions.values()}
    named = collections.Counter()
    for q in forever:
        for fid, amount in rewards.get(q, ()):
            if amount > 0:
                named[fid] += 1
    out, rep = {}, report["factions"]
    rep.update(quests=len(forever), known=sum(1 for q in forever if q in rewards),
               naming=sum(1 for q in forever if any(a > 0 for _, a in rewards.get(q, ()))))
    for fid in sorted(named):
        r = src.factions.get(fid)
        if r is None:
            rep["missing"].append(fid)
        elif fid in parents:
            rep["headers"].append("%s (%d)" % (r["Name_lang"], fid))
        elif int(r["ReputationIndex"]) < 0:
            rep["no_standing"].append("%s (%d)" % (r["Name_lang"], fid))
        else:
            out[fid] = {"name": r["Name_lang"], "conf": "data"}
    # the client's factions a player can see a standing with that no source names: Forever's own among them, since
    # its new quests have no reward data in the Classic database. The rules learn them from members' reputations
    rep["unnamed"] = ["%s (%d)" % (r["Name_lang"], fid) for fid, r in sorted(src.factions.items())
                      if int(r["ReputationIndex"]) >= 0 and fid not in parents and fid not in out
                      and not int(r["ReputationFlags_0"]) & FACTION_UNSEEN and int(r["Flags"]) == 0
                      and not r["Name_lang"].startswith("DNT")]
    return out


# ---------------------------------------------------------------- the seed
def new_report():
    return {"awaited_joined": [], "awaited_gone": [], "lfg_maps": 0, "near": [], "alias_used": set(), "alias_bad": [],
            "alias_needless": [], "pooled_used": set(), "pooled": [],
            "enchants": {"how": collections.Counter(), "recipe": {}, "item_spells": set(), "sod": 0, "not_item_enchant": 0,
                         "problems": [], "fits_nothing": [], "no_source": [], "items_why": [],
                         "item_only": collections.defaultdict(list), "left_out": collections.Counter(),
                         "left_out_slot": collections.Counter()},
            "factions": {"missing": [], "headers": [], "no_standing": [], "unnamed": []},
            "quests": {"ambiguous": set(), "unknown": set()}}


def build_seed():
    src = Sources()
    report = new_report()
    dungeons, awaited = join_dungeons(src, report)
    enchants = join_enchants(src, report)
    xp = join_xp(src)
    factions = join_factions(src, report)
    seed = {"build": src.build, "betaCap": BETA_CAP, "cap": len(xp) + 1, "sources": src.read, "dungeons": dungeons,
            "awaited": awaited, "enchants": enchants, "xp": xp,
            "xpConf": {lv: "beta" if lv <= BETA_CAP else "data" for lv in xp}, "factions": factions}
    return src, seed, report


def lua_str(s):
    """a Lua string literal in ASCII: the game's font draws any other byte in a source file as a box, so UTF-8 travels
    as three-digit decimal escapes (a name such as "\\195\\182" stays whole at run time)"""
    out = []
    for b in s.encode("utf-8"):
        if b in (0x22, 0x5C):
            out.append("\\" + chr(b))
        elif 32 <= b < 127:
            out.append(chr(b))
        else:
            out.append("\\%03d" % b)
    return '"' + "".join(out) + '"'


def ascii_text(s):
    """a name in a comment, ASCII as the file must be: any other byte as its decimal escape"""
    return lua_str(s)[1:-1].replace('\\"', '"')


def lua_ints(xs):
    return "{ " + ", ".join(str(x) for x in xs) + " }" if xs else "{}"


def wing_names(d):
    """a merged dungeon's wings by their own names ("Scarlet Monastery: Graveyard" is "Graveyard"); [] for none"""
    return [n.split(":", 1)[-1].strip() for n in d["wings"] or []]


def counts(seed):
    ds = seed["dungeons"]
    bosses = [b for d in ds.values() for b in d["bosses"]]
    return {
        "dungeons": len(ds), "dungeons_beta": sum(d["conf"] == "beta" for d in ds.values()),
        "awaited": len(seed["awaited"]), "loot_dungeons": sum(len(d["wings"]) if d["wings"] else 1 for d in ds.values()),
        "bosses": len(bosses), "bosses_beta": sum(b["beta"] for b in bosses),
        "bosses_client": sum(bool(b.get("client")) for b in bosses), "bosses_aka": sum(bool(b["aka"]) for b in bosses),
        "bosses_recorded": sum(bool(b.get("recorded")) for b in bosses),
        "left": sum(len(d["left"]) for d in ds.values()), "loot": sum(len(b["loot"]) for b in bosses),
        "slots": len(seed["enchants"]), "enchants": sum(len(e["list"]) for e in seed["enchants"].values()),
        "xp": len(seed["xp"]), "xp_beta": sum(c == "beta" for c in seed["xpConf"].values()),
        "factions": len(seed["factions"]),
        "quests": sum(len(d["quests"]) for d in list(ds.values()) + seed["awaited"]),
        "quests_id": sum(q["id"] is not None for d in list(ds.values()) + seed["awaited"] for q in d["quests"]),
    }


def raid_groups(no_source):
    """the left-out recipes by the Classic raids their formulas drop in: [(raids, [names])]; None for no source at all"""
    groups = collections.defaultdict(list)
    for x in no_source:
        groups[tuple(x["raids"]) if x["raids"] else None].append(x["name"])
    return sorted(((k, sorted(v)) for k, v in groups.items()), key=lambda kv: (kv[0] is None, kv[0] or ()))


def item_only_text(item_only):
    return "; ".join("%s: %s" % (SLOT_NAME[s], ", ".join(sorted(set(v)))) for s, v in sorted(item_only.items()))


def render(seed, report, date):
    c = counts(seed)
    rep, fr = report["enchants"], report["factions"]
    L = []
    w = L.append
    head = ("Generated by tools/cute/gen_known.py on %s from Forever's beta client, build %s; edit the generator, not this "
            "file. What research and the beta say Forever has, for Cute to start from: the addon checks it against the "
            "live client at login and learns the rest from the guild's play. conf: \"beta\" seen in the beta (a level "
            "range from %d or below, with players' records), \"data\" from research or the client's tables only."
            % (date, seed["build"], seed["betaCap"]))
    srcs = "Sources: " + ", ".join(seed["sources"]) + "."
    tally = ("%d dungeons (%d beta, %d data) from %d of loot.json's %d, wings that share an instance as one; %d bosses "
             "(%d beta, %d data), each a fight of the client's encounter table (%d that loot.json lacks, %d that it names "
             "otherwise), with %d loot item ids; %d enchantable slots with %d enchants; XP to the next level for %d "
             "levels (%d beta, %d data); %d factions; %d dungeon quests, %d with QuestBank's id."
             % (c["dungeons"], c["dungeons_beta"], c["dungeons"] - c["dungeons_beta"], c["loot_dungeons"],
                c["loot_dungeons"] + c["awaited"], c["bosses"], c["bosses_beta"], c["bosses"] - c["bosses_beta"],
                c["bosses_client"], c["bosses_aka"], c["loot"], c["slots"], c["enchants"], c["xp"], c["xp_beta"],
                c["xp"] - c["xp_beta"], c["factions"], c["quests"], c["quests_id"]))
    paras = [head, srcs, tally]
    if seed["awaited"]:
        paras.append("Awaited, in Forever's sources but not in this client's Map table, so not keyed here: " + ", ".join(
            "%s (%d-%d)" % (d["name"], d["min"], d["max"]) for d in seed["awaited"]) + "; seeded by name and level range "
            "(awaited, below), each given its instance id once two members enter it (or a kill there a group mate names back).")
    if c["left"]:
        paras.append("Left out: %d of loot.json's bosses that no fight of the client's encounter table fits (rares, "
                     "summoned bosses, Scourge Invasion bosses), named under their dungeon; the addon reads bosses by "
                     "encounter." % c["left"])
    groups = raid_groups(rep["no_source"])
    if groups:
        paras.append("Enchants are the Enchanting recipes Forever has (new in Forever, a trainer's, or taught by a formula "
                     "players or loot.json show, or the Classic database hands out outside its raids); %d left out: %s."
                     % (len(rep["no_source"]), "; ".join(
                         ("formulas only in %s: %s" % (" and ".join(k), ", ".join(v))) if k else ("no source: " + ", ".join(v))
                         for k, v in groups)))
    if rep["item_only"]:
        paras.append("Enchant items are listed only in the slots a recipe opens (the design: no head, shoulder or legs "
                     "enchants yet), so these open none and wait for the guild (rule 5): %s." % item_only_text(rep["item_only"]))
    if fr["unnamed"]:
        paras.append("Factions: %d more of the client's, with a standing, are named by no source yet (Forever's new "
                     "quests have no reward data), for the rules to learn: %s." % (len(fr["unnamed"]), ", ".join(fr["unnamed"])))
    for p in paras:
        for line in textwrap.wrap(ascii_text(p), 116, break_long_words=False, break_on_hyphens=False):
            w("-- " + line)
    w("local _, C = ...")
    w("C.Known = {")
    w('  v = 1, build = %s, generated = %s, betaCap = %d, cap = %d,' % (lua_str(seed["build"]), lua_str(date), seed["betaCap"], seed["cap"]))
    w("  sources = {")
    for s in seed["sources"]:
        w("    %s," % lua_str(s))
    w("  },")
    w("  dungeons = {  -- [instance id] = GetInstanceInfo's eighth return")
    for mid in sorted(seed["dungeons"], key=lambda k: (seed["dungeons"][k]["min"], seed["dungeons"][k]["max"], k)):
        d = seed["dungeons"][mid]
        # (a field, not a comment: Rule 4 never doubts a boss in a dungeon whose wings share one instance, since a run
        # is one wing; the first 0.5.0 seed named them in a comment only and the addon read no wings at all)
        wings = " wings = { %s }," % ", ".join(lua_str(n) for n in wing_names(d)) if d["wings"] else ""
        w("    [%d] = { name = %s, min = %d, max = %d, new = %s, conf = %s, kind = %s,%s"
          % (mid, lua_str(d["name"]), d["min"], d["max"], "true" if d["new"] else "false", lua_str(d["conf"]), lua_str(d["kind"]), wings))
        if d["left"]:
            w("      -- left out, no fight in the client: " + ", ".join(ascii_text(b["name"]) for b in d["left"]))
        render_quests(w, d["quests"], "      ")
        if not d["bosses"]:
            w("      bosses = {} },")
            continue
        w("      bosses = {")
        for b in d["bosses"]:
            notes = []
            if b["aka"]:
                notes.append("loot.json's " + ", ".join(ascii_text(n) for n in b["aka"]))
            if b["pooled"]:
                notes.append("items from loot.json's " + ", ".join(ascii_text(n) for n in b["pooled"]))
            if b.get("client"):
                notes.append("the client's encounter table" + ("; players' records show it killed in the beta" if b.get("players") else " alone"))
            if b.get("recorded"):
                notes.append("items from players' loot records")
            w("        { name = %s, enc = %d, conf = %s, loot = %s },%s" % (
                lua_str(b["name"]), b["enc"], lua_str("beta" if b["beta"] else "data"), lua_ints(b["loot"]),
                ("  -- " + "; ".join(notes)) if notes else ""))
        w("      } },")
    w("  },")
    w("  awaited = {  -- in Forever's sources, not in this client's Map table: by name, no instance id and no bosses yet")
    for d in seed["awaited"]:
        w("    { name = %s, min = %d, max = %d, new = %s, conf = %s, kind = %s%s" % (
            lua_str(d["name"]), d["min"], d["max"], "true" if d["new"] else "false", lua_str(d["conf"]), lua_str(d["kind"]),
            "," if d["quests"] else " },"))
        if d["quests"]:
            render_quests(w, d["quests"], "      ")
            w("    },")
    w("  },")
    w("  enchants = {  -- [inventory slot]; kinds: \"class.subclass\" of the items that take one, as Stats.lua's itemKind makes them")
    for slot in sorted(seed["enchants"]):
        e = seed["enchants"][slot]
        kinds = "" if e["kinds"] is None else " kinds = { %s }," % ", ".join(lua_str(k) for k in e["kinds"])
        w("    [%d] = { conf = %s,%s  -- %s" % (slot, lua_str(e["conf"]), kinds, SLOT_NAME[slot]))
        w("      list = {")
        for x in e["list"]:
            xk = "" if x.get("kinds") is None else " kinds = { %s }," % ", ".join(lua_str(k) for k in x["kinds"])
            w("        { spell = %d, name = %s, ench = %d,%s }," % (x["spell"], lua_str(x["name"]), x["ench"], xk))
        w("      } },")
    w("  },")
    w("  xp = {  -- XP to the next level")
    lv = sorted(seed["xp"])
    for i in range(0, len(lv), 10):
        w("    " + " ".join("[%d] = %d," % (k, seed["xp"][k]) for k in lv[i:i + 10]))
    w("  },")
    w("  xpConf = {")
    for i in range(0, len(lv), 10):
        w("    " + " ".join("[%d] = %s," % (k, lua_str(seed["xpConf"][k])) for k in lv[i:i + 10]))
    w("  },")
    w("  factions = {  -- the reputations Forever's quests reward")
    for fid in sorted(seed["factions"]):
        f = seed["factions"][fid]
        w("    [%d] = { name = %s, conf = %s }," % (fid, lua_str(f["name"]), lua_str(f["conf"])))
    w("  },")
    w("}")
    return "\n".join(L) + "\n"


def render_quests(w, quests, pad):
    """a dungeon's quests, one a line: its QuestBank id where one joins, the level it opens at, the side it is for"""
    if not quests:
        return
    w(pad + "quests = {  -- id: QuestBank's catalog, where the title joins one; side: \"a\" Alliance, \"h\" Horde, none both")
    for q in quests:
        parts = ["name = %s" % lua_str(q["name"])]
        if q["id"] is not None:
            parts.append("id = %d" % q["id"])
        if q["level"] is not None:
            parts.append("level = %d" % q["level"])
        if q["min"] is not None:
            parts.append("min = %d" % q["min"])
        if q["side"]:
            parts.append("side = %s" % lua_str(q["side"]))
        w(pad + "  { %s }," % ", ".join(parts))
    w(pad + "},")


def dated(text):
    """the date a seed file carries, None for none"""
    m = re.search(r'generated = "(\d{4}-\d{2}-\d{2})"', text or "")
    return m.group(1) if m else None


def same(disk, seed, report):
    """the file on disk says what this run would, its date aside"""
    return disk is not None and dated(disk) is not None and render(seed, report, dated(disk)) == disk


def on_disk():
    try:
        return open(OUT, encoding="utf-8").read()
    except OSError:
        return None


def summary(seed, report):
    c = counts(seed)
    ds = seed["dungeons"]
    rep = report["enchants"]
    lines = ["seed: build %s, betaCap %d, cap %d" % (seed["build"], seed["betaCap"], seed["cap"])]
    merged = ["%s %d" % (d["name"], len(d["wings"])) for d in ds.values() if d["wings"]]
    lines.append("  dungeons  %3d instances: %d beta, %d data (party %d, raid %d) from %d of loot.json's %d dungeons; wings merged: %s"
                 % (c["dungeons"], c["dungeons_beta"], c["dungeons"] - c["dungeons_beta"],
                    sum(d["kind"] == "party" for d in ds.values()), sum(d["kind"] == "raid" for d in ds.values()),
                    c["loot_dungeons"], c["loot_dungeons"] + c["awaited"], ", ".join(merged) or "none"))
    if seed["awaited"]:
        lines.append("            awaited %d (no map in the client yet), seeded by name and level range: %s" % (
            c["awaited"], ", ".join("%s %d-%d" % (d["name"], d["min"], d["max"]) for d in seed["awaited"])))
    qr = report["quests"]
    lines.append("            quests %d, %d with QuestBank's id; by title alone: %d several fit (%s), %d none (%s)" % (
        c["quests"], c["quests_id"], len(qr["ambiguous"]), ", ".join(sorted(qr["ambiguous"])) or "none",
        len(qr["unknown"]), ", ".join(sorted(qr["unknown"])) or "none"))
    lines.append("            LFGDungeons names a map on %d rows" % report["lfg_maps"])
    lines.append("  bosses    %3d: %d beta, %d data; %d that loot.json lacks (the client's encounter table), %d it names otherwise, "
                 "%d with items from players' loot records; %d loot item ids"
                 % (c["bosses"], c["bosses_beta"], c["bosses"] - c["bosses_beta"], c["bosses_client"], c["bosses_aka"],
                    c["bosses_recorded"], c["loot"]))
    if report["near"]:
        lines.append("            joined by a near name: " + "; ".join(report["near"]))
    aka = ["%s / %s = %s (%d)" % (d["name"], n, b["name"], b["enc"]) for d in sorted(ds.values(), key=lambda d: d["min"])
           for b in d["bosses"] for n in b["aka"]]
    if aka:
        lines.append("            joined by ALIAS: " + "; ".join(aka))
    for p in report["pooled"]:
        lines.append("            pooled: " + p["text"])
    lines.append("            left out, no fight in the client: %d" % c["left"])
    for d in sorted(ds.values(), key=lambda d: d["min"]):
        for b in d["left"]:
            lines.append("              %s / %s: %s" % (d["name"], b["name"], b["why"]))
    how = rep["how"]
    lines.append("  enchants  %3d slots (%s): %d enchants, all data: %d Enchanting recipes (%s), %d from enchant items"
                 % (c["slots"], ", ".join(SLOT_NAME[s] for s in sorted(seed["enchants"])), c["enchants"], sum(how.values()),
                    ", ".join("%s %d" % (k, how[k]) for k in sorted(how)), len(rep["item_spells"])))
    lines.append("            recipes left out, no source outside the Classic raids: %d" % len(rep["no_source"]))
    for k, v in raid_groups(rep["no_source"]):
        lines.append("              %s: %s" % ("formulas only in " + " and ".join(k) if k else "no source", ", ".join(v)))
    lines.append("            enchant items in: %s" % ("; ".join(rep["items_why"]) or "none"))
    if rep["item_only"]:
        lines.append("            enchant items open no slot of their own, left to the guild (rule 5): " + item_only_text(rep["item_only"]))
    lo = rep["left_out"]
    lines.append("            enchant items left out, no Forever source shows them obtainable: %d (%d carry an Enchanting recipe's own spell, %d are crafted by a recipe nobody has shown made, %d others); by slot: %s"
                 % (sum(lo.values()), lo["recipe_spell"], lo["crafted"], lo["other"],
                    ", ".join("%s %d" % (SLOT_NAME[s], n) for s, n in sorted(rep["left_out_slot"].items()))))
    lines.append("            recipes skipped: %d Season of Discovery, %d not a permanent item enchant, %d fit no item in the client: %s"
                 % (rep["sod"], rep["not_item_enchant"], len(rep["fits_nothing"]), "; ".join(rep["fits_nothing"]) or "none"))
    lines.append("  xp        %3d levels: %d beta, %d data" % (c["xp"], c["xp_beta"], c["xp"] - c["xp_beta"]))
    fr = report["factions"]
    lines.append("  factions  %3d, all data: the reputation rewards of %d quests, of the %d in QuestBank's catalog met in Forever (the Classic database has %d of them); headers left out: %s"
                 % (c["factions"], fr["naming"], fr["quests"], fr["known"], ", ".join(fr["headers"]) or "none"))
    if fr["no_standing"]:
        lines.append("            no standing in the client (left out): " + ", ".join(fr["no_standing"]))
    lines.append("            the client's other factions with a standing, named by no source (the rules learn them): %d: %s"
                 % (len(fr["unnamed"]), ", ".join(fr["unnamed"]) or "none"))
    return lines


# ---------------------------------------------------------------- selftest
def selftest(src, seed, report, text):
    problems = []

    def check(cond, msg):
        if not cond:
            problems.append(msg)

    # the run is deterministic
    _, seed2, report2 = build_seed()
    check(render(seed2, report2, "2000-01-01") == render(seed, report, "2000-01-01"), "two runs gave different seeds")
    # every dungeon of loot.json is seeded or awaited, and no awaited one joins now
    seeded = {w for d in seed["dungeons"].values() for w in (d["wings"] or [d["name"]])}
    awaited = {d["name"] for d in seed["awaited"]}
    for d in src.loot["dungeons"]:
        check(d["name"] in seeded or d["name"] in awaited, "%s is neither seeded nor awaited" % d["name"])
    check(not report["awaited_joined"], "AWAITED lists dungeons that now join; drop them from it: " + ", ".join(report["awaited_joined"]))
    check(not report["awaited_gone"], "AWAITED lists dungeons loot.json no longer has: " + ", ".join(report["awaited_gone"]))
    # every awaited dungeon is seeded by its name and loot.json's level range, research's word, with no instance id and
    # no bosses, so the Guide lists it before anyone has entered it (Next up)
    levels = {d["name"]: tuple(d["levels"]) for d in src.loot["dungeons"]}
    for n in AWAITED:
        a = [d for d in seed["awaited"] if d["name"] == n]
        check(len(a) == 1 and (a[0]["min"], a[0]["max"]) == levels.get(n) and a[0]["conf"] == "data" and "bosses" not in a[0]
              and "id" not in a[0], "%s is not seeded once by its name and level range %s: %s" % (n, levels.get(n), a))
    # the quests: every one loot.json lists for a seeded or awaited dungeon is under it, and every id is the catalog's
    # quest of that title
    under = {}
    for d in seed["dungeons"].values():
        for w in d["wings"] or [d["name"]]:
            under[w] = d
    for d in seed["awaited"]:
        under[d["name"]] = d
    for d in src.loot["dungeons"]:
        have = {norm(q["name"]) for q in under[d["name"]]["quests"]} if d["name"] in under else set()
        for q in d["quests"]:
            check(norm(q["name"]) in have, "%s: its quest %s is not in the seed" % (d["name"], q["name"]))
    for d in list(seed["dungeons"].values()) + seed["awaited"]:
        for q in d["quests"]:
            check(q["id"] is None or (q["id"] in src.qb_quests and norm(src.qb_names.get(q["id"], "")) == norm(q["name"])),
                  "%s: quest %s has id %s, which QuestBank's catalog gives another title" % (d["name"], q["name"], q["id"]))
    # bosses: each an encounter of its instance at a dungeon difficulty, none twice; ALIAS, POOLED and NOT_THAT_FIGHT
    # each still needed and still right
    valid = {(e["id"], e["map"]) for e in src.enc if e["diff"] in DUNGEON_DIFFICULTIES}
    encs = collections.Counter()
    for mid, d in seed["dungeons"].items():
        check(src.maps.get(mid, {}).get("InstanceType") in ("1", "2"), "%d is not an instance in the Map table" % mid)
        for b in d["bosses"]:
            check((b["enc"], mid) in valid, "%s / %s: encounter %d is not a dungeon encounter of map %d" % (d["name"], b["name"], b["enc"], mid))
            encs[b["enc"]] += 1
            for i in b["loot"]:
                check(i in src.items, "%s / %s: item %d is not in the client's Item table" % (d["name"], b["name"], i))
        for b in d["left"]:
            check(bool(b["why"]), "%s / %s is left out with no reason" % (d["name"], b["name"]))
        # a fight with no loot beside a left-out boss with loot: the boss must have been looked at (NOT_THAT_FIGHT)
        if any(not b["loot"] for b in d["bosses"]):
            for b in d["left"]:
                check(not b["loot"] or (mid, b["name"]) in NOT_THAT_FIGHT,
                      "%s: %s has loot and no fight while %s has a fight and no loot: ALIAS it, or say in NOT_THAT_FIGHT why not"
                      % (d["name"], b["name"], ", ".join(x["name"] for x in d["bosses"] if not x["loot"])))
    check(not [e for e, n in encs.items() if n > 1], "encounters seeded twice: %s" % [e for e, n in encs.items() if n > 1])
    check(not report["alias_bad"], "ALIAS: " + "; ".join(report["alias_bad"]))
    check(not report["alias_needless"], "ALIAS entries no longer needed: " + "; ".join(report["alias_needless"]))
    check(not set(ALIAS) - report["alias_used"], "ALIAS names bosses loot.json no longer has there: %s" % sorted(set(ALIAS) - report["alias_used"]))
    check(not POOLED - report["pooled_used"], "POOLED names entries loot.json no longer has there: %s" % sorted(POOLED - report["pooled_used"]))
    check(all(p["n"] for p in report["pooled"]), "a POOLED entry placed nothing: " + "; ".join(p["text"] for p in report["pooled"]))
    left = {(mid, b["name"]) for mid, d in seed["dungeons"].items() for b in d["left"]}
    check(not set(NOT_THAT_FIGHT) - left, "NOT_THAT_FIGHT names bosses that are no longer left out: %s" % sorted(set(NOT_THAT_FIGHT) - left))
    # players' loot records: every instance they looted in that is a Forever dungeon is seeded, every fight they saw end
    # there is one of its bosses, and beta where the dungeon starts at or below the cap
    for key, rec in src.disc.get("loot", {}).items():
        for m in rec.get("im", {}):
            m = int(m)
            if m in seed["dungeons"]:
                d = seed["dungeons"][m]
                by_enc = {b["enc"]: b for b in d["bosses"]}
                for e in list(rec.get("e", {})) + list(rec.get("ei", {})):
                    b = by_enc.get(int(e))
                    check(b is not None, "players saw encounter %s end in %s (%s); the seed lacks it" % (e, d["name"], key))
                    check(b is None or d["min"] > BETA_CAP or b["beta"],
                          "players saw %s killed in the beta (%s); the seed has it as data" % (b and b["name"], key))
            elif src.maps.get(m, {}).get("InstanceType") in ("1", "2"):
                check(False, "players looted in instance %d (%s), which the seed lacks" % (m, src.maps[m]["MapName_lang"]))
    # enchants: the neck has them, the head, the shoulder and the legs do not (yet); every slot is opened by a recipe;
    # no recipe is in whose formulas drop only in Classic raids; every spell and enchant is the client's
    en, rep = seed["enchants"], report["enchants"]
    check(2 in en and len(en[2]["list"]) >= 5, "the neck is not enchantable in the seed (Forever's five Enchant Necklace recipes)")
    for slot in NO_ENCHANT_YET:
        check(slot not in en, "the seed makes the %s slot enchantable, against the design: %s" % (SLOT_NAME[slot], (en.get(slot) or {}).get("list")))
    for slot, e in en.items():
        check(e["list"], "slot %d has no enchants" % slot)
        check(any(x["spell"] in rep["recipe"] for x in e["list"]), "the %s slot is opened by enchant items alone" % SLOT_NAME[slot])
        for x in e["list"]:
            check(x["spell"] in src.spell_name and x["ench"] in src.ench_ids, "slot %d: %s is not the client's" % (slot, x))
            r = rep["recipe"].get(x["spell"])
            if r and r.get("by") and not (r.get("nw") or r.get("rs") or r.get("cl") or r["s"] in src.trained
                                          or any(i in src.uploaded or i in src.looted for i in r["by"])):
                check(not all(src.classic.raid_drops(i) for i in r["by"]),
                      "%s (%d) is in, and its formulas drop only in Classic raids" % (x["name"], x["spell"]))
    check(not report["enchants"]["problems"], "enchants: " + "; ".join(report["enchants"]["problems"]))
    # XP: 59 levels, rising, the players' readings agree, beta to the cap
    xp = seed["xp"]
    check(sorted(xp) == list(range(1, 60)), "xp has %d levels, not 1-59" % len(xp))
    check(all(xp[k] < xp[k + 1] for k in range(1, len(xp))), "xp does not rise level by level")
    readings = src.disc.get("probe", {}).get("xpmax", {})
    for lv, vals in readings.items():
        lv = int(lv)
        top = max(vals.items(), key=lambda kv: kv[1])[0]
        check(xp.get(lv) == int(top), "players read UnitXPMax %s at level %d; the seed says %s" % (top, lv, xp.get(lv)))
        check(lv <= BETA_CAP, "players read XP at level %d, past BETA_CAP %d: the beta's cap moved" % (lv, BETA_CAP))
    check(all(seed["xpConf"][k] == ("beta" if k <= BETA_CAP else "data") for k in xp), "xpConf is not beta to the cap, data above")
    # factions: the client's, with a name
    for fid, f in seed["factions"].items():
        check(fid in src.factions and f["name"], "faction %d is not the client's" % fid)
    check(not report["factions"]["missing"], "factions the quests name that the client lacks: %s" % report["factions"]["missing"])
    # every dungeon whose wings share one instance names them in a field on its line, before any comment there: Rule 4
    # reads it and never doubts a boss of a wing nobody ran (the Lua load below reads it back too)
    block = text[text.find("  dungeons = {"):text.find("  enchants = {")]
    for mid, d in sorted(seed["dungeons"].items()):
        if d["wings"]:
            m = re.search(r"^    \[%d\] = \{([^\n]*)$" % mid, block, re.M)
            code = m.group(1).split("--", 1)[0] if m else ""
            check(len(wing_names(d)) > 1 and ("wings = { %s }," % ", ".join(lua_str(n) for n in wing_names(d))) in code,
                  "%s: its wings are not a field of its line in the seed, so Rule 4 would doubt the bosses of a wing nobody ran" % d["name"])
    # the file: ASCII, loads, and is the one this run would write
    check(all(ord(ch) < 128 for ch in text), "the seed has a non-ASCII byte")
    disk = on_disk()
    if disk is None:
        check(False, "%s is missing: run gen_known.py" % os.path.relpath(OUT, ROOT))
    else:
        check(same(disk, seed, report), "%s is stale: run gen_known.py" % os.path.relpath(OUT, ROOT))
        lua = shutil.which("luajit") or shutil.which("lua5.1")
        if lua:
            # (with each merged dungeon's wings as the addon reads them: id=count, by id)
            probe = ("local f = assert(loadfile(%s)); local C = {}; f('Cute', C); local K = C.Known; local n, b, w = 0, 0, {}; "
                     "for id, d in pairs(K.dungeons) do n = n + 1; for _, x in ipairs(d.bosses) do if x.enc then b = b + 1 end end; "
                     "if type(d.wings) == 'table' then w[#w + 1] = id end end; table.sort(w); "
                     "for i, id in ipairs(w) do w[i] = id .. '=' .. #K.dungeons[id].wings end; "
                     "local q, a = 0, {}; for _, d in pairs(K.dungeons) do q = q + #(d.quests or {}) end; "
                     "for _, d in ipairs(K.awaited or {}) do q = q + #(d.quests or {}); "
                     "a[#a + 1] = d.name .. ' ' .. d.min .. '-' .. d.max .. (d.bosses and ' bosses' or '') .. (d.id and ' id' or '') end; "
                     "io.write(K.build, ' ', n, ' ', b, ' ', #K.xp, ' wings ', table.concat(w, ','), ' quests ', q, ' awaited ', table.concat(a, ', '))") % lua_str(OUT)
            r = subprocess.run([lua, "-e", probe], capture_output=True, text=True)
            want = "%s %d %d %d wings %s quests %d awaited %s" % (seed["build"], len(seed["dungeons"]), counts(seed)["bosses"], len(xp), ",".join(
                "%d=%d" % (mid, len(d["wings"])) for mid, d in sorted(seed["dungeons"].items()) if d["wings"]),
                counts(seed)["quests"], ", ".join("%s %d-%d" % (d["name"], d["min"], d["max"]) for d in seed["awaited"]))
            check(r.returncode == 0 and r.stdout.strip() == want, "Lua reads the file as %r, not %r: %s" % (r.stdout.strip(), want, r.stderr.strip()))
            # a name with UTF-8, a quote, a backslash and a digit after an escape comes back byte for byte
            name = "König \"Grün\" \\ é1"
            r = subprocess.run([lua, "-e", "io.write(%s)" % lua_str(name)], capture_output=True)
            check(r.stdout == name.encode("utf-8"), "a UTF-8 name does not survive the escapes: %r" % r.stdout)
        else:
            print("  skip the Lua load (no luajit on PATH)")
    return problems


def main():
    try:
        src, seed, report = build_seed()
    except Fail as e:
        sys.exit("gen_known: " + str(e))
    for s in src.skipped:
        print("  newer build left aside: " + s)
    disk = on_disk()
    if "--selftest" in sys.argv:
        text = render(seed, report, dated(disk) or datetime.date.today().isoformat())
        for line in summary(seed, report):
            print(line)
        problems = selftest(src, seed, report, text)
        if problems:
            print("problems: %d" % len(problems))
            for p in problems:
                print("  - " + p)
            sys.exit(1)
        print("problems: 0")
        print("OK")
        return
    for line in summary(seed, report):
        print(line)
    if same(disk, seed, report):
        state = "unchanged"
    else:
        with open(OUT, "w", encoding="utf-8", newline="\n") as f:
            f.write(render(seed, report, datetime.date.today().isoformat()))
        state = "written"
    c = counts(seed)
    print("Known.lua %s: %d dungeons, %d bosses, %d enchant slots, %d XP levels, %d factions"
          % (state, c["dungeons"], c["bosses"], c["slots"], c["xp"], c["factions"]))


if __name__ == "__main__":
    main()
