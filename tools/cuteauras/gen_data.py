#!/usr/bin/env python3
# Cute Auras' data: each class's buffs read from the Forever client's own tables (research/wago/<build>), the camp items,
# foods and blueprints from the site's item database (plan/items-db.json) and QuestBank's generated camp tables.
#   python3 -I tools/cuteauras/gen_data.py        writes tools/cuteauras/CuteAuras/Data.lua
# A curated spell missing from the client stops the run: the client is the truth, not Classic's lists.
import csv, json, os, re, sys, collections

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
BUILD = "1.60.1.71037"
W = os.path.join(REPO, "research", "wago", BUILD)
OUT = os.path.join(HERE, "CuteAuras", "Data.lua")

def rd(name): return list(csv.DictReader(open(os.path.join(W, name), encoding="utf-8")))
NAMES = {int(r["ID"]): r["Name_lang"] for r in rd("SpellName.csv")}
MISC = {int(r["SpellID"]): r for r in rd("SpellMisc.csv") if r["DifficultyID"] == "0"}
DUR = {r["ID"]: int(r["Duration"]) for r in rd("SpellDuration.csv")}
LEVEL = {int(r["SpellID"]): int(r["BaseLevel"] or 0) for r in rd("SpellLevels.csv") if r["DifficultyID"] == "0"}
REAGENT = {int(r["SpellID"]): int(r["Reagent_0"] or 0) for r in rd("SpellReagents.csv")}
SLA = collections.defaultdict(list)
for r in rd("SkillLineAbility.csv"): SLA[int(r["SkillLine"])].append(int(r["Spell"]))
EFFECT = collections.defaultdict(dict)  # [spell][effect index] = its SpellEffect row
for r in rd("SpellEffect.csv"):
    if r["DifficultyID"] == "0": EFFECT[int(r["SpellID"])][int(r["EffectIndex"])] = r

# each class's skill lines: the three talent trees and the class line (ChrClasses' own)
LINES = {"WARRIOR": [26, 256, 257, 840], "PALADIN": [594, 267, 184, 800], "HUNTER": [50, 163, 51, 795], "ROGUE": [253, 38, 39, 796],
         "PRIEST": [613, 56, 78, 804], "SHAMAN": [375, 373, 374, 801], "MAGE": [237, 8, 6, 799], "WARLOCK": [355, 354, 593, 797],
         "DRUID": [574, 134, 573, 798]}

def ranks(cls, name, need=True):
    ids = sorted({s for ln in LINES[cls] for s in SLA[ln] if NAMES.get(s) == name and s in MISC}, key=lambda s: (LEVEL.get(s, 0), s))
    if not ids and need: sys.exit("%s: no spell named %r in %s's skill lines (build %s)" % (cls, name, cls, BUILD))
    return ids
def icon(sid): return int(MISC[sid]["SpellIconFileDataID"] or 0)
def dur(sid): return max(0, DUR.get(MISC[sid]["DurationIndex"], 0) // 1000)

# the curated list: which spells are buffs worth keeping up, and who wants them. Everything else (ids, ranks, levels,
# icons, durations, reagents) is read from the client.
#   other   it can be cast on another player (else on yourself only)
#   want    all | mana (a mana user) | tank (the group's tank, and you when you tank)
#   group   the group version (Prayer, Brilliance, Gift): any rank of it counts as the buff
#   one     a self buff where any of these counts (an armor, an aspect, an aura, a shield); the first is cast
#   opt     off until switched on in Settings
CLASS = {
  "MAGE": [dict(key="int", name="Arcane Intellect", group="Arcane Brilliance", other=True, want="mana"),
           dict(key="armor", one=["Ice Armor", "Frost Armor", "Mage Armor"])],
  "PRIEST": [dict(key="fort", name="Power Word: Fortitude", group="Prayer of Fortitude", other=True, want="all"),
             dict(key="spirit", name="Divine Spirit", group="Prayer of Spirit", other=True, want="mana"),
             dict(key="shadow", name="Shadow Protection", group="Prayer of Shadow Protection", other=True, want="all", opt=True),
             dict(key="innerfire", one=["Inner Fire"])],
  "DRUID": [dict(key="motw", name="Mark of the Wild", group="Gift of the Wild", other=True, want="all"),
            dict(key="thorns", name="Thorns", other=True, want="tank")],
  "SHAMAN": [dict(key="earthshield", name="Earth Shield", other=True, want="tank", single=True),
             dict(key="shield", one=["Lightning Shield", "Water Shield"])],
  "WARLOCK": [dict(key="armor", one=["Demon Armor", "Fel Armor", "Demon Skin"])],
  "HUNTER": [dict(key="aspect", one=["Aspect of the Hawk", "Aspect of the Monkey"],
                  also=["Aspect of the Cheetah", "Aspect of the Pack", "Aspect of the Wild", "Aspect of the Beast"])],
  "PALADIN": [dict(key="aura", one=["Devotion Aura", "Retribution Aura", "Concentration Aura"],
                   also=["Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura", "Sanctity Aura"])],
}
BLESS = [("kings", "Blessing of Kings", "Greater Blessing of Kings"), ("might", "Blessing of Might", "Greater Blessing of Might"),
         ("wisdom", "Blessing of Wisdom", "Greater Blessing of Wisdom")]
HANDS = [("protection", "Blessing of Protection"), ("freedom", "Blessing of Freedom"), ("sacrifice", "Blessing of Sacrifice")]
RES = {"PRIEST": "Resurrection", "PALADIN": "Redemption", "SHAMAN": "Ancestral Spirit", "DRUID": "Rebirth"}

def lua(v, ind=""):
    if isinstance(v, bool): return "true" if v else "false"
    if isinstance(v, (int, float)): return repr(v)
    if isinstance(v, str): return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, list): return "{ " + ", ".join(lua(x) for x in v) + " }"
    if isinstance(v, dict):
        parts = []
        for k, x in v.items():
            key = k if isinstance(k, str) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k) else "[" + lua(k) + "]"
            parts.append("%s = %s" % (key, lua(x)))
        return "{ " + ", ".join(parts) + " }"
    raise TypeError(v)

def spell(cls, name, need=True):
    ids = ranks(cls, name, need)
    if not ids: return None
    return {"name": name, "icon": icon(ids[0]), "ranks": ids, "levels": [LEVEL.get(s, 0) for s in ids], "dur": dur(ids[-1])}

# a ranked buff's power: its aura's main amount, each rank's (and its group version's), read from SpellEffect: the apply
# aura effect (Effect 6) of this aura type, of this misc value when one is given. Fortitude's Stamina, Arcane Intellect's
# Intellect, Divine Spirit's Spirit, Shadow Protection's resistance, Mark of the Wild's armor, Thorns' damage, Might's
# attack power, Wisdom's mana every 5 seconds. A buff of one rank (Kings) or not listed (Earth Shield) has none, and a
# buff without one is never read as a lower rank. The amount is EffectBasePointsF as it stands: see the checks below
POWER = {"fort": (29, 2), "int": (29, 3), "spirit": (29, 4), "shadow": (22, 32), "motw": (674, 1), "thorns": (15, None),
         "might": (99, None), "wisdom": (24, 0)}
def powers(ids, aura, misc):
    out = []
    for sid in ids:
        e = next((x for _, x in sorted(EFFECT[sid].items()) if x["Effect"] == "6" and int(x["EffectAura"]) == aura
                  and (misc is None or int(x["EffectMiscValue_0"] or 0) == misc)), None)
        if not e: sys.exit("%s (%d): no aura %d%s in SpellEffect (build %s)" % (NAMES.get(sid), sid, aura, "" if misc is None else " of misc %d" % misc, BUILD))
        v = float(e["EffectBasePointsF"])
        out.append(int(v) if v == int(v) else v)
    return out
def addPower(r, key):
    if key not in POWER: return
    r["power"] = powers(r["ranks"], *POWER[key])
    if r.get("group"): r["groupPower"] = powers(r["group"], *POWER[key])

lines = ["-- SPDX-License-Identifier: GPL-3.0-or-later",
         "-- Generated by tools/cuteauras/gen_data.py from the Forever client's tables (build %s), the site's item" % BUILD,
         "-- database and QuestBank's camp tables. Edit the generator, not this file.",
         "local _, A = ...", "local D = {}", "A.Data = D", 'D.BUILD = "%s"' % BUILD]

out = {}
for cls, entries in CLASS.items():
    rows = []
    for e in entries:
        r = {"key": e["key"]}
        if "one" in e:
            r["one"] = [s for s in (spell(cls, n, need=(i == 0)) for i, n in enumerate(e["one"])) if s]
            alsoIds = []
            for n in e.get("also", []): alsoIds += ranks(cls, n, need=False)
            if alsoIds: r["alsoIds"] = alsoIds
        else:
            s = spell(cls, e["name"])
            r.update(s)
            r["other"], r["want"] = bool(e.get("other")), e["want"]
            if e.get("group"):
                g = ranks(cls, e["group"], need=False)
                if g:
                    r["group"], r["groupName"], r["groupLevels"] = g, e["group"], [LEVEL.get(x, 0) for x in g]
                    # (each rank its own reagent: Prayer of Fortitude 1 takes a Holy Candle, 2 a Sacred Candle)
                    rgs = [REAGENT.get(x, 0) for x in g]
                    if any(rgs): r["groupReagents"] = rgs
                    if rgs[-1]: r["reagent"] = rgs[-1]
            if e.get("opt"): r["opt"] = True
            if e.get("single"): r["single"] = True
            addPower(r, e["key"])
        rows.append(r)
    out[cls] = rows
lines.append("-- each class's buffs: key, the spell's name, icon, ranks (lowest first) with their levels and the last rank's")
lines.append("-- duration; other: castable on another player, want: who wants it (all, mana, tank); group: its group version's")
lines.append("-- ranks (any counts as the buff), the top rank's reagent and each rank's (groupReagents); one: a self buff of which")
lines.append("-- any counts, the first cast; alsoIds: auras that count too (another aspect, another aura); opt: off until")
lines.append("-- Settings switches it on; power: each rank's main amount (Stamina, Intellect, armor, attack power, ...), groupPower")
lines.append("-- each group rank's")
lines.append("D.BUFFS = {")
for cls in sorted(out): lines.append("  %s = { %s }," % (cls, ", ".join(lua(r) for r in out[cls])))
lines.append("}")

bless = {}
for key, name, greater in BLESS:
    s = spell("PALADIN", name)
    g = ranks("PALADIN", greater, need=False)
    if g:
        s["group"], s["groupName"], s["groupLevels"] = g, greater, [LEVEL.get(x, 0) for x in g]
        rgs = [REAGENT.get(x, 0) for x in g]
        if any(rgs): s["groupReagents"] = rgs
        if rgs[-1]: s["reagent"] = rgs[-1]
    addPower(s, key)
    bless[key] = s
# every blessing the paladin's lines hold is listed here, long (BLESS) or short (HANDS).
# Forever has no Salvation, Light or Sanctuary: client 70862 removed 1038, 19977-19979, 25890, 25895 (SpellName.csv);
# Sanctuary was never in 1.60. codex/spellbook.json's rows are the beta's.
# Buffs.lua's "no blessing on you at all" counts BLESS alone, so one the client adds stops the run
listed = {n for _, n, _ in BLESS} | {g for _, _, g in BLESS} | {n for _, n in HANDS}
extra = sorted({NAMES[s] for ln in LINES["PALADIN"] for s in SLA[ln]
                if s in MISC and re.match(r"(Greater )?Blessing of ", NAMES.get(s, "")) and NAMES[s] not in listed})
if extra: sys.exit("paladin blessings not listed: %r (build %s): add a long one to BLESS, or the blessing check misses it" % (extra, BUILD))

# the power's convention, from the buffs Forever left at Classic's numbers: EffectBasePointsF is the amount itself (Classic's
# EffectBasePoints was the amount less one, its one-sided die adding it back), so Arcane Intellect 5 is 31 Intellect, not
# 30. Then Forever's own numbers, the ones it changed from Classic's (its tooltips, codex/spellbook.json, say the same);
# and each group rank as strong as the single rank of its level, the one a Prayer or a Greater stands in for
def check(what, got, want):
    if got != want: sys.exit("power: %s reads %r, not %r (build %s): the client's EffectBasePoints convention, or Forever's numbers, changed" % (what, got, want, BUILD))
buff = {r["key"]: r for rows in out.values() for r in rows if "power" in r}
check("Arcane Intellect", buff["int"]["power"], [2, 7, 15, 22, 31]); check("Arcane Brilliance", buff["int"]["groupPower"], [31])
check("Divine Spirit", buff["spirit"]["power"], [17, 23, 33, 40]); check("Prayer of Spirit", buff["spirit"]["groupPower"], [40])
check("Shadow Protection", buff["shadow"]["power"], [30, 45, 60]); check("Prayer of Shadow Protection", buff["shadow"]["groupPower"], [60])
check("Thorns", buff["thorns"]["power"], [3, 6, 9, 12, 15, 18])
# (Forever's: Fortitude 6 70 Stamina, Classic 54; Prayer of Fortitude 1 and 2 56 and 70, Classic 43 and 54; Mark of the
# Wild 7 385 armor, Classic 285; Might 7 133 attack power, Classic 185, Greater Might 112 and 133, Classic 155 and 185;
# Wisdom 6 40 mana, Classic 33, Greater Wisdom 36 and 40, Classic 30 and 33)
check("Power Word: Fortitude", buff["fort"]["power"], [4, 10, 26, 42, 56, 70]); check("Prayer of Fortitude", buff["fort"]["groupPower"], [56, 70])
check("Mark of the Wild", buff["motw"]["power"], [34, 88, 142, 203, 263, 324, 385]); check("Gift of the Wild", buff["motw"]["groupPower"], [324, 385])
check("Blessing of Might", bless["might"]["power"], [14, 25, 40, 61, 83, 112, 133]); check("Greater Blessing of Might", bless["might"]["groupPower"], [112, 133])
check("Blessing of Wisdom", bless["wisdom"]["power"], [12, 18, 24, 30, 36, 40]); check("Greater Blessing of Wisdom", bless["wisdom"]["groupPower"], [36, 40])
for e in list(buff.values()) + [b for b in bless.values() if "power" in b]:
    if any(b <= a for a, b in zip(e["power"], e["power"][1:])): sys.exit("power: %s's ranks don't each give more: %r" % (e["name"], e["power"]))
    for gid, lv, p in zip(e.get("group", []), e.get("groupLevels", []), e.get("groupPower", [])):
        same = [q for q, l in zip(e["power"], e["levels"]) if l == lv]
        if same != [p]: sys.exit("power: %s (%d, level %d) gives %r, the single rank of its level %r" % (e["groupName"], gid, lv, p, same))
lines.append("-- the paladin's long blessings and their Greater versions (all members of the target's class)")
lines.append("D.BLESS = " + lua(bless))
# a talent that makes a Hand last longer (Guardian's Favor and Freedom): a paladin talent whose text says "the duration of
# your <Hand> by $/1000;sN sec", its effect N a flat modifier (aura 107) of the duration (misc 1); seconds per rank
DESC = {int(r["ID"]): r["Description_lang"] for r in rd("Spell.csv")}
def durationMods(name):
    mods = {}
    pat = re.compile(r"duration of your " + re.escape(name) + r" by \$/1000;s(\d)")
    for sid in sorted({x for ln in LINES["PALADIN"] for x in SLA[ln]}):
        m = pat.search(DESC.get(sid, ""))
        e = m and EFFECT[sid].get(int(m.group(1)) - 1)
        if e and e["EffectAura"] == "107" and e["EffectMiscValue_0"] == "1":
            mods[sid] = int(float(e["EffectBasePointsF"])) // 1000
    return mods
hands = {}
for key, name in HANDS:
    s = spell("PALADIN", name)
    s["durs"] = [dur(x) for x in s["ranks"]]
    mods = durationMods(name)
    if mods: s["mods"] = mods
    hands[key] = s
lines.append("-- the short blessings that take a paladin's long one off its target (one blessing per paladin per target);")
lines.append("-- mods: a talent that makes it last longer, [talent's spell] = seconds a rank")
lines.append("D.HANDS = " + lua(hands))
res = {}
for cls, name in RES.items():
    s = spell(cls, name, need=False)
    if s: res[cls] = {"name": name, "icon": s["icon"], "ranks": s["ranks"]}
lines.append("-- each class's resurrection (Rebirth works in a fight)")
lines.append("D.RES = " + lua(res))

# the camp: QuestBank's tables as gen_data.py made them, the Cooking Fire items (an Iron Oven, Cookie's Feast) and the
# blueprints, which craft a camp item for a cook, a tailor, ...
qbdata = open(os.path.join(REPO, "tools", "questbank", "QuestBank", "Data.lua"), encoding="utf-8").read().split("\n")
ITEMCLS = {int(r["ID"]): (int(r["ClassID"]), int(r["SubclassID"])) for r in rd("Item.csv")}
USE = {}
for r in rd("ItemEffect.csv"):
    if r["TriggerType"] == "0": USE[r["ID"]] = int(r["SpellID"])
ITEMUSE = {}  # an item's use spell (its first on-use effect)
for r in rd("ItemXItemEffect.csv"):
    sid = USE.get(r["ItemEffectID"])
    if sid: ITEMUSE.setdefault(int(r["ItemID"]), sid)
# what a food's Well Fed raises, as D.CONSUME's words (Buffs.lua fits them to your role), from its text: "" for a
# profession's skill or a zone's speed alone (nothing for a fight); a text not listed here stops the run
FOOD_WORDS = [("Attack Power", "ap"), ("Spell Damage", "spell"), ("Healing Power", "heal"), ("Critical Strike", "crit"),
              ("Strength", "str"), ("Agility", "agi"), ("Stamina", "sta"), ("Intellect", "int"), ("Spirit", "spi"), ("Armor", "armor")]
FOOD_NONE = re.compile(r"^\+\d+ (Fishing|Herbalism) [Ss]kill|movement speed while in ")
def foodWords(g):
    if g == "Well Fed": return None
    if FOOD_NONE.search(g): return ""
    out, rest = [], g
    for text, w in FOOD_WORDS:
        if text in rest: out.append(w); rest = rest.replace(text, "")
    if not out: sys.exit("D.FOOD: no words for the text %r (add it to FOOD_WORDS or FOOD_NONE)" % g)
    return " ".join(out)
FOODS = set()  # (the Well Fed foods' item ids: the camp and the Well Fed row cover them, never D.CONSUME's "other")
for want in ("D.CAMP = ", "D.FOOD = "):
    row = next((l for l in qbdata if l.startswith(want)), None)
    if not row: sys.exit("QuestBank's Data.lua has no " + want.strip())
    if want == "D.FOOD = ":
        # (QuestBank's foods from the items' Use lines, less a recipe that teaches one (Item class 9: Recipe: Westfall
        # Stew carries the stew's Use line, and its click learns the recipe), each with its words, w)
        kept = []
        for iid, body in re.findall(r"\[(\d+)\]=\{([^{}]*)\}", row):
            cs = ITEMCLS.get(int(iid))
            if cs and cs[0] != 0: continue
            FOODS.add(int(iid))
            g = re.search(r'g="([^"]*)"', body)
            ws = foodWords(g.group(1)) if g else None
            kept.append("[%s]={%s%s}" % (iid, body, "" if ws is None else ',w="%s"' % ws))
        row = "D.FOOD = {" + ",".join(kept) + "}"
        lines.append("-- the foods that make you Well Fed: n, g (what it gives), i (icon), w: what it raises (D.CONSUME's words; \"\"")
        lines.append("-- a profession's skill or a zone's speed alone)")
    lines.append(row)
# the sellers of Simple Wood and Flint and Tinder (QuestBank's D.CAMP_SELL, from the CMaNGOS Classic database, GPL-3.0):
#   {npc id, name, continent, world x, world y, uiMap, x, y, goods (1 Simple Wood, 2 Flint and Tinder), side (1 Alliance,
#    2 Horde, 3 both)}; Classic data, Forever may have moved some
at = next((i for i, l in enumerate(qbdata) if l.startswith("D.CAMP_SELL = {")), None)
if at is None: sys.exit("QuestBank's Data.lua has no D.CAMP_SELL")
end = next(i for i in range(at, len(qbdata)) if qbdata[i].startswith("}"))
lines.append("-- who sells Simple Wood and Flint and Tinder: {npc, name, continent, world x, world y, uiMap, x, y, goods (1 wood, 2 flint),")
lines.append("-- side (1 Alliance, 2 Horde, 3 both)}; the CMaNGOS Classic database's (GPL-3.0), which Forever may have moved")
lines.extend(qbdata[at:end + 1])
ITEMS = json.load(open(os.path.join(REPO, "plan", "items-db.json"), encoding="utf-8"))["items"]
byName = {}
for it in ITEMS: byName.setdefault(it["name"], it)
cookfire, blueprint = {}, {}
for it in ITEMS:
    use = " ".join(e for e in (it.get("effects") or []) if e.startswith("Use:"))
    if "Requires a Cooking Fire nearby" in use and not it["name"].startswith("Blueprint"):
        sk = it.get("reqSkill") or ""
        prof, lvl = (sk.rsplit(" ", 1) + ["0"])[:2] if sk else (None, "0")
        g = "the most advanced cooking recipes" if "advanced cooking" in use else ("Stamina food for the camp" if "Stamina" in use else None)
        cookfire[int(it["id"])] = {"n": it["name"], "p": prof, "s": int(lvl) if lvl.isdigit() else 0, "i": it.get("icon"), "g": g}
        # (its use spell: placing one spends the camp features' shared hour, as a feature's does)
        if ITEMUSE.get(int(it["id"])): cookfire[int(it["id"])]["sp"] = ITEMUSE[int(it["id"])]
    if it["name"].startswith("Blueprint: "):
        m = re.search(r"Craft (?:an? )?([^.]+)\.", use)
        product = m and m.group(1).strip() or it["name"][len("Blueprint: "):]
        made = byName.get(product) or byName.get(product + " Kit")
        sk = it.get("reqSkill") or ""
        prof, lvl = (sk.rsplit(" ", 1) + ["0"])[:2] if sk else (None, "0")
        e = {"n": product, "i": it.get("icon")}
        if prof: e["p"], e["s"] = prof, int(lvl) if lvl.isdigit() else 0
        if made: e["makes"] = int(made["id"])
        blueprint[int(it["id"])] = e
lines.append("-- the camp items that need a Cooking Fire (any campfire counts): no buff, a cook's tool or a feast; sp: its use spell")
lines.append("D.COOKFIRE = " + lua(dict(sorted(cookfire.items()))))
lines.append("-- the blueprints: what each crafts, and the profession and skill the item asks (the tooltip's red line says the rest)")
lines.append("D.BLUEPRINT = " + lua(dict(sorted(blueprint.items()))))
stones = sorted(int(it["id"]) for it in ITEMS if re.match(r"^(Minor |Lesser |Greater |Major )?Soulstone$", it["name"]))
lines.append("-- the soulstones a warlock makes and uses on a friendly target")
lines.append("D.SOULSTONE = " + lua(stones))
# the consumables' buffs: what each potion, elixir, flask, scroll (Item class 0, subclass 1 to 4) or juju-like item (class
# 12; class 0 subclass 0, 5 or 8, a Well Fed food aside: Spirit of Zanza, Rumsey Rum Black Label) raises, from its use
# spell's aura effects (SpellEffect) when the aura lasts a minute or more (SpellMisc's duration).
# Before the pull fits them to your role by these words, the same in every client language. Each word:
#   str agi sta int spi all (a stat; all of them), ap rap (attack power, ranged), phys spell (physical or spell damage),
#   fire frost shadow nature arcane holy (one school's spell damage alone: Elixir of Shadow Power stacks with Greater
#   Arcane Elixir, as in Classic, so the kin by first word (Consume.lua) keeps them apart),
#   dmg (all damage), heal, crit, haste, hit, exp (expertise), mp5 mana (mana regained, more mana), hp (more or regained
#   health), armor, res (a resistance), absorb, def (defense, dodge, parry)
# An empty string: the client knows it, and it leaves no lasting stat buff (a healing potion, Water Breathing)
STAT_OF = {0: "str", 1: "agi", 2: "sta", 3: "int", 4: "spi", -1: "all"}
SCHOOL_OF = {2: "holy", 4: "fire", 8: "nature", 16: "frost", 32: "shadow", 64: "arcane"}
def spellWord(mask):
    m = mask & 126
    if not m: return None
    return SCHOOL_OF.get(m, "spell")
def consumeWords(sid):
    m = MISC.get(sid)
    if not m or dur(sid) < 60: return []
    out = []
    for e in sorted(EFFECT.get(sid, {}).values(), key=lambda x: int(x["EffectIndex"])):
        if e["Effect"] not in ("6", "35"): continue
        aura, misc, pts = int(e["EffectAura"]), int(e["EffectMiscValue_0"] or 0), float(e["EffectBasePointsF"] or 0)
        if pts <= 0: continue  # (a malus, or nothing to raise: no stat buff)
        w = None
        if aura in (29, 80): w = STAT_OF.get(misc)                     # a stat, flat or a percent
        elif aura == 99: w = "ap"
        elif aura == 124: w = "rap"
        elif aura == 13: w = "phys" if misc == 1 else spellWord(misc)
        elif aura == 79: w = "dmg"
        elif aura in (135, 136): w = "heal"
        elif aura in (52, 57, 290): w = "crit"
        elif aura == 193: w = "haste"
        elif aura in (54, 55): w = "hit"
        elif aura == 240: w = "exp"
        elif aura in (85, 110) and misc == 0: w = "mp5"
        elif aura == 418 and misc == 0: w = "mana"
        elif aura in (34, 133, 161): w = "hp"
        elif aura in (22, 674): w = "armor" if misc == 1 else "res"
        elif aura == 69: w = "absorb"
        elif aura in (47, 49) or (aura == 30 and misc == 95): w = "def"
        if w and w not in out: out.append(w)
    return out
consume = {}
for r in rd("ItemXItemEffect.csv"):
    cs = ITEMCLS.get(int(r["ItemID"]))
    sid = USE.get(r["ItemEffectID"])
    if not cs or not sid: continue
    ws = consumeWords(sid)
    if cs[0] == 0 and 1 <= cs[1] <= 4: consume[sid] = " ".join(ws)
    elif (cs[0] == 12 or (cs[0] == 0 and cs[1] in (0, 5, 8) and int(r["ItemID"]) not in FOODS)) and ws: consume[sid] = " ".join(ws)
lines.append("-- the consumables' buffs by their use spell: what each raises (words, see gen_data.py), \"\" for none lasting a minute")
lines.append("D.CONSUME = " + lua(dict(sorted(consume.items()))))
# the weapon's: an item's use spell that puts a temporary enchant on a weapon (SpellEffect Effect 54, an oil or a stone;
# 360, a poison): Dense Sharpening Stone 16138, Brilliant Wizard Oil 25122, Deadly Poison 2823. Only one the main hand
# can take (SpellEquippedItems): a weapon (class 2) of a kind other than a fishing pole (subclass 20 alone: the lures,
# Shiny Bauble 8087, Nightcrawlers 8088, Camper's Lure 1331725), or, with no subclass named, one of the main hand's
# inventory types (13 one-hand, 17 two-hand, 21 main hand; not a shield coating, 14 alone). Forever's "Soul of ..."
# shoulder enchants (class 4, 1219740 on) are armor's, never a weapon's
FISHING_POLE = 1 << 20
MAIN_HAND_TYPES = (1 << 13) | (1 << 17) | (1 << 21)
EQUIPPED = collections.defaultdict(list)
for r in rd("SpellEquippedItems.csv"):
    EQUIPPED[int(r["SpellID"])].append((int(r["EquippedItemClass"]), int(r["EquippedItemInvTypes"] or 0), int(r["EquippedItemSubclass"] or 0)))
def mainHand(sid):
    for cls, inv, sub in EQUIPPED.get(sid, []):
        if cls != 2: continue
        if sub:
            if sub & ~FISHING_POLE: return True
        elif inv & MAIN_HAND_TYPES: return True
    return False
# Each one's value: the weapon kinds it goes on, a mask of weapon subclasses (Dense Sharpening Stone 16138: axes,
# polearms, swords, daggers; Dense Weightstone 16622: maces, staves, fist weapons), or true for any weapon (an oil,
# named by inventory types alone)
def weaponKinds(sid):
    mask = 0
    for cls, inv, sub in EQUIPPED.get(sid, []):
        if cls != 2: continue
        if not sub: return True
        mask |= sub & ~FISHING_POLE
    return mask or True
IMBUE_EFFECTS = ("54", "360")
imbue = {}
for r in rd("ItemXItemEffect.csv"):
    sid = USE.get(r["ItemEffectID"])
    if sid and any(e["Effect"] in IMBUE_EFFECTS for e in EFFECT.get(sid, {}).values()) and mainHand(int(sid)): imbue[sid] = weaponKinds(int(sid))
for sid in (16138, 25122, 25123, 2823):
    if sid not in imbue: sys.exit("D.IMBUE: %d has no weapon enchant effect (54 or 360) for a main hand (build %s)" % (sid, BUILD))
for sid in (8087, 8088, 1331725, 1219740, 463868):
    if sid in imbue: sys.exit("D.IMBUE: %d goes on no main hand (a lure, an armor's or a shield's), yet is in it (build %s)" % (sid, BUILD))
for sid, want in ((16138, 33219), (16622, 9264), (25122, True)):
    if imbue.get(sid) != want: sys.exit("D.IMBUE: %d goes on %r, not %r (build %s)" % (sid, imbue.get(sid), want, BUILD))
lines.append("-- the weapon's: item use spells that put a temporary enchant on a weapon (an oil, a stone, a poison): the weapon")
lines.append("-- subclasses it goes on as a mask (bit n: subclass n; Dense Sharpening Stone's 33219: axes, polearms, swords,")
lines.append("-- daggers), true for any")
lines.append("D.IMBUE = " + lua(dict(sorted(imbue.items()))))
# Forever's biomes (build 71037 onward): an effect gated by an area group (SpellCastingRequirements.RequiredAreasID), its
# words "in Snowy areas", "in Forest and Grassland areas". Each biome: its area group's areas (their names are asked of the
# client at login, so any language matches the zone text), the spells gated by it or naming it, and the items known to
# carry one (the client's item effects and the site's item database). Pieces the server sends that neither knows are
# found in play, by their tooltips.
BIOME_WORDS = [("forest", "Forest and Grassland", ["Forest", "Grassland"]), ("snowy", "Snowy", ["Snowy"]), ("mountainous", "Mountainous", ["Mountainous"]),
               ("desert", "Desert", ["Desert"]), ("wasteland", "Wasteland", ["Wasteland"]), ("swamp", "Swamp and Marsh", ["Swamp", "Marsh"]),
               ("haunted", "Haunted", ["Haunted"]), ("underground", "Cavernous and Underground", ["Cavernous", "Underground"]),
               ("volcanic", "Volcanic", ["Volcanic"]), ("water", "Water", ["Water"])]
WORD2KEY = {w: k for k, _, ws in BIOME_WORDS for w in ws}
SPELL = {r["ID"]: r for r in rd("Spell.csv")}
GATE = {r["SpellID"]: r["RequiredAreasID"] for r in rd("SpellCastingRequirements.csv") if r["RequiredAreasID"] != "0"}
EFF = collections.defaultdict(list)
for r in rd("SpellEffect.csv"): EFF[r["SpellID"]].append(r)
TEXT = re.compile(r"(Forest|Grassland|Snowy|Haunted|Mountainous|Desert|Wasteland|Swamp|Marsh|Volcanic|Cavernous|Underground)(?: (?:and|or) ([A-Z][a-z]+))? areas|in or on (Water)")
def words(sid):
    d = (SPELL.get(sid, {}).get("Description_lang") or "") + " " + (SPELL.get(sid, {}).get("AuraDescription_lang") or "")
    out = set()
    for m in TEXT.finditer(d):
        for w in m.groups():
            if w and w in WORD2KEY: out.add(WORD2KEY[w])
    return out
# an area group is a biome when the spells it gates name one biome
groupWords = collections.defaultdict(collections.Counter)
for sid, g in GATE.items():
    for k in words(sid): groupWords[g][k] += 1
GROUP = {}
for g, c in groupWords.items():
    k, n = c.most_common(1)[0]
    if n >= 1 and len(c) == 1: GROUP[g] = k
AGM = collections.defaultdict(list)
for r in rd("AreaGroupMember.csv"): AGM[r["AreaGroupID"]].append(int(r["AreaID"]))
# each area's zone: its top-level ancestor (AreaTable's ParentAreaID walked up). A subzone counts only inside its own
# zone: the outdoor "Dire Maul" in Feralas (2577) is not the Dire Maul instance (2557) that a biome lists
PARENT = {int(r["ID"]): int(r["ParentAreaID"] or 0) for r in rd("AreaTable.csv")}
def zoneOf(a):
    seen = set()
    while PARENT.get(a, 0) and a not in seen:
        seen.add(a)
        a = PARENT[a]
    return a
biomes = []
for key, name, _ in BIOME_WORDS:
    e = {"key": key, "name": name}
    groups = sorted(g for g, k in GROUP.items() if k == key)
    if groups:
        e["groups"] = [int(g) for g in groups]
        e["areas"] = sorted({a for g in groups for a in AGM[g]})
        # (a subzone's zone; a zone, or an instance, has none)
        zones = {a: zoneOf(a) for a in e["areas"] if zoneOf(a) != a}
        if zones: e["zones"] = dict(sorted(zones.items()))
    biomes.append(e)
# the spells: gated by a biome's group, or naming a biome (the doubled and tripled ones), with what they reference
def refs(sid):
    d = SPELL.get(sid, {}).get("Description_lang") or ""
    out = set(re.findall(r"\$(\d{4,})[a-zA-Z]", d))
    for e in EFF.get(sid, []):
        if e["EffectTriggerSpell"] not in ("0", ""): out.add(e["EffectTriggerSpell"])
    return out
bspells = {}
for sid in SPELL:
    ks = set(words(sid))
    if GATE.get(sid) in GROUP: ks.add(GROUP[GATE[sid]])
    if ks: bspells[int(sid)] = sorted(ks)
gated = {int(sid): GROUP[g] for sid, g in GATE.items() if g in GROUP}
# the items: the client's item effects (and what those spells reference), then the site's item database by its words
IE = {r["ID"]: r for r in rd("ItemEffect.csv")}
IXE = collections.defaultdict(list)
for r in rd("ItemXItemEffect.csv"): IXE[r["ItemID"]].append(r["ItemEffectID"])
bitems = {}
for iid, effs in IXE.items():
    ks = set()
    for eid in effs:
        x = IE.get(eid)
        if not x: continue
        todo, seen = [x["SpellID"]], set()
        while todo and len(seen) < 12:
            sid = todo.pop()
            if sid in seen: continue
            seen.add(sid)
            ks |= set(bspells.get(int(sid), []))
            todo += list(refs(sid))
    if ks: bitems[int(iid)] = sorted(ks)
for it in ITEMS:
    ks = set()
    for e in it.get("effects") or []:
        for m in TEXT.finditer(e):
            for w in m.groups():
                if w and w in WORD2KEY: ks.add(WORD2KEY[w])
    if ks: bitems[int(it["id"])] = sorted(set(bitems.get(int(it["id"]), [])) | ks)
lines.append("-- Forever's biomes: key, name, the client's area groups and their areas (zones and subzones by AreaTable id);")
lines.append("-- zones: a subzone's own zone (its top-level area), the only zone it counts in")
lines.append("D.BIOMES = { " + ", ".join(lua(b) for b in biomes) + " }")
lines.append("-- the spells gated by a biome's area group (their aura shows only there: proof of where you stand)")
lines.append("D.BIOME_GATED = " + lua(dict(sorted(gated.items()))))
lines.append("-- every spell that names a biome or is gated by one: its biomes (a tooltip line is matched to their texts)")
lines.append("D.BIOME_SPELLS = " + lua(dict(sorted(bspells.items()))))
lines.append("-- the items known to carry a biome effect: their biomes")
lines.append("D.BIOME_ITEMS = " + lua(dict(sorted(bitems.items()))))
print("biomes", [(b["key"], len(b.get("areas", []))) for b in biomes], "spells", len(bspells), "gated", len(gated), "items", len(bitems))
lines.append("return D")
open(OUT, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("wrote", OUT, "classes", len(out), "blueprints", len(blueprint), "cookfire", len(cookfire), "soulstones", stones,
      "consumables", len(consume), "with a buff", sum(1 for v in consume.values() if v), "imbues", len(imbue))
