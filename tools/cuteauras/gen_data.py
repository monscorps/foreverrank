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
                    rg = REAGENT.get(g[-1], 0)
                    if rg: r["reagent"] = rg
            if e.get("opt"): r["opt"] = True
            if e.get("single"): r["single"] = True
        rows.append(r)
    out[cls] = rows
lines.append("-- each class's buffs: key, the spell's name, icon, ranks (lowest first) with their levels and the last rank's")
lines.append("-- duration; other: castable on another player, want: who wants it (all, mana, tank); group: its group version's")
lines.append("-- ranks (any counts as the buff) and reagent; one: a self buff of which any counts, the first cast; alsoIds: auras")
lines.append("-- that count too (another aspect, another aura); opt: off until Settings switches it on")
lines.append("D.BUFFS = {")
for cls in sorted(out): lines.append("  %s = { %s }," % (cls, ", ".join(lua(r) for r in out[cls])))
lines.append("}")

bless = {}
for key, name, greater in BLESS:
    s = spell("PALADIN", name)
    g = ranks("PALADIN", greater, need=False)
    if g:
        s["group"], s["groupName"], s["groupLevels"] = g, greater, [LEVEL.get(x, 0) for x in g]
        rg = REAGENT.get(g[-1], 0)
        if rg: s["reagent"] = rg
    bless[key] = s
lines.append("-- the paladin's long blessings and their Greater versions (all members of the target's class)")
lines.append("D.BLESS = " + lua(bless))
hands = {}
for key, name in HANDS:
    s = spell("PALADIN", name)
    s["durs"] = [dur(x) for x in s["ranks"]]
    hands[key] = s
lines.append("-- the short blessings that take a paladin's long one off its target (one blessing per paladin per target)")
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
for want in ("D.CAMP = ", "D.FOOD = "):
    row = next((l for l in qbdata if l.startswith(want)), None)
    if not row: sys.exit("QuestBank's Data.lua has no " + want.strip())
    lines.append(row)
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
lines.append("-- the camp items that need a Cooking Fire (any campfire counts): no buff, a cook's tool or a feast")
lines.append("D.COOKFIRE = " + lua(dict(sorted(cookfire.items()))))
lines.append("-- the blueprints: what each crafts, and the profession and skill the item asks (the tooltip's red line says the rest)")
lines.append("D.BLUEPRINT = " + lua(dict(sorted(blueprint.items()))))
stones = sorted(int(it["id"]) for it in ITEMS if re.match(r"^(Minor |Lesser |Greater |Major )?Soulstone$", it["name"]))
lines.append("-- the soulstones a warlock makes and uses on a friendly target")
lines.append("D.SOULSTONE = " + lua(stones))
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
biomes = []
for key, name, _ in BIOME_WORDS:
    e = {"key": key, "name": name}
    groups = sorted(g for g, k in GROUP.items() if k == key)
    if groups:
        e["groups"] = [int(g) for g in groups]
        e["areas"] = sorted({a for g in groups for a in AGM[g]})
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
lines.append("-- Forever's biomes: key, name, the client's area groups and their areas (zones and subzones by AreaTable id)")
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
print("wrote", OUT, "classes", len(out), "blueprints", len(blueprint), "cookfire", len(cookfire), "soulstones", stones)
