#!/usr/bin/env python3
"""Damage done back to attackers: thorns, shield spikes, procs when struck.

Writes, from the client's spell tables (research/wago/<BUILD>):
  plan/items-db.json   rf on every wearable item that reflects damage
  plan/enchants.json   shield spikes and the Retricutioner chest enchant
  plan/reflect.json    Retribution Aura, Holy Shield, Redoubt, Eye for an Eye, druid Thorns

rf entries: {k, s, v, lo, hi, p, up, aoe, sp, src}
  k    "hit"   flat damage to the attacker on every melee hit taken (aura 15, damage shield)
       "proc"  a chance p on being struck to deal v (aura 42 -> trigger spell's damage, or aura 43)
       "block" damage on each block (p below 1 when only a chance on block)
       "use"   an on-use damage shield: v per hit while up, up = duration / cooldown
  s    school; v average damage (base points); lo/hi the range when the spell has variance
  src  "client" (spell tables) or "text" (parsed from the tooltip where the client has no spell for the item)

Item -> ItemXItemEffect -> ItemEffect.SpellID -> SpellEffect, school from SpellMisc.SchoolMask, chance from
SpellAuraOptions.ProcChance, range from SpellEffect.Variance. Where the proc flags cannot tell a block from a hit
(aura 43), the spell's and the item's text decide.

  python3 tools/apply_reflect.py          # rewrite rf, enchants.json, reflect.json
  python3 tools/apply_reflect.py --dry    # report only
Also run at the end of tools/scavenge_items.py.
"""
import math
import collections, csv, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "plan", "items-db.json")
LOOT_ITEMS = os.path.join(ROOT, "codex", "loot-items.json")
ENCHANTS = os.path.join(ROOT, "plan", "enchants.json")
REFLECT = os.path.join(ROOT, "plan", "reflect.json")
BUILD = "1.60.1.70170"
WAGO = os.path.join(ROOT, "research", "wago", BUILD)
SCHOOLS = [(1, "Physical"), (2, "Holy"), (4, "Fire"), (8, "Nature"), (16, "Frost"), (32, "Shadow"), (64, "Arcane")]
SCHOOL_RE = r"(Physical|Holy|Fire|Nature|Frost|Shadow|Arcane)"
# proc flags for being hit: taken melee swing 0x8, melee ability 0x20, ranged swing 0x80, ranged ability 0x200
TAKEN = 0x8 | 0x20 | 0x80 | 0x200
DAMAGE_EFFECTS = ("2", "9")  # SCHOOL_DAMAGE, HEALTH_LEECH


def _rows(table):
    return list(csv.DictReader(open(os.path.join(WAGO, table + ".csv"), encoding="utf-8")))


class Client:
    def __init__(self):
        self.ixe = collections.defaultdict(list)
        ie = {r["ID"]: r for r in _rows("ItemEffect")}
        for r in _rows("ItemXItemEffect"):
            if r["ItemEffectID"] in ie:
                self.ixe[r["ItemID"]].append(ie[r["ItemEffectID"]])
        self.se = collections.defaultdict(list)
        for r in _rows("SpellEffect"):
            if r["DifficultyID"] == "0":
                self.se[r["SpellID"]].append(r)
        for v in self.se.values():
            v.sort(key=lambda e: int(e["EffectIndex"]))
        self.misc = {r["SpellID"]: r for r in _rows("SpellMisc") if r["DifficultyID"] == "0"}
        self.aura = {r["SpellID"]: r for r in _rows("SpellAuraOptions") if r["DifficultyID"] == "0"}
        self.dur = {r["ID"]: int(r["Duration"]) for r in _rows("SpellDuration")}
        self.cd = {r["SpellID"]: r for r in _rows("SpellCooldowns") if r["DifficultyID"] == "0"}
        self.levels = {r["SpellID"]: r for r in _rows("SpellLevels") if r["DifficultyID"] == "0"}
        self.name = {r["ID"]: r["Name_lang"] for r in _rows("SpellName")}
        self.desc = {r["ID"]: r["Description_lang"] or "" for r in _rows("Spell")}

    def school(self, sid):
        mask = int((self.misc.get(sid) or {}).get("SchoolMask") or 1)
        for bit, name in SCHOOLS[1:]:
            if mask & bit:
                return name
        return "Physical"

    def chance(self, sid):
        """Proc chance 0..1, None when always (100 or 101 in the table)."""
        a = self.aura.get(sid)
        pc = int(a["ProcChance"]) if a and a["ProcChance"] else 100
        return None if pc >= 100 else round(pc / 100.0, 3)

    def proc_mask(self, sid):
        a = self.aura.get(sid)
        return int(a["ProcTypeMask_0"] or 0) if a else 0

    def duration_ms(self, sid):
        m = self.misc.get(sid)
        return self.dur.get(m["DurationIndex"], 0) if m else 0

    def cooldown_ms(self, sid, item_effect=None):
        c = [int(item_effect.get(k) or 0) for k in ("CoolDownMSec", "CategoryCoolDownMSec")] if item_effect else []
        r = self.cd.get(sid)
        if r:
            c += [int(r["RecoveryTime"] or 0), int(r["CategoryRecoveryTime"] or 0)]
        return max(c + [0])

    def learn(self, sid):
        r = self.levels.get(sid)
        return int(r["BaseLevel"] or r["SpellLevel"] or 0) if r else 0


def num(x):
    f = float(x or 0)
    return int(f) if f == int(f) else round(f, 2)


def dmg(e, school, sid):
    """{s, v[, lo, hi], sp} for a damage effect."""
    v = num(e["EffectBasePointsF"])
    out = {"s": school, "v": v, "sp": int(sid)}
    var = float(e.get("Variance") or 0)
    if var > 0:
        # half up: 38.5 -> 39; the float32 Variance is rounded first, else 38.4999999 drops a point
        out["lo"], out["hi"] = int(math.floor(round(v * (1 - var / 2), 4) + 0.5)), int(math.floor(round(v * (1 + var / 2), 4) + 0.5))
    return out


def is_aoe(c, sid, e, text):
    return bool(int(e.get("EffectRadiusIndex_0") or 0)) or bool(re.search(r"all nearby|nearby enemies|all targets around|all attackers", text, re.I))


def client_rf(c, iid, effects_text):
    """rf from the client's tables for one item, or []."""
    out = []
    for ie in c.ixe.get(str(iid), []):
        trig, sid = ie["TriggerType"], ie["SpellID"]
        if trig not in ("0", "1") or sid not in c.se:
            continue
        if re.search(r"victim of a critical", c.desc.get(sid, ""), re.I):
            continue  # flat damage only when a critical strike lands on you (Bonespike Shoulder): no kind for it yet
        for e in c.se[sid]:
            aura = e["EffectAura"]
            if e["Effect"] not in ("6", "35"):
                continue
            if aura == "15":  # damage shield: every hit taken
                r = dict(dmg(e, c.school(sid), sid), k="hit" if trig == "1" else "use")
                if trig == "0":
                    d, cd = c.duration_ms(sid), c.cooldown_ms(sid, ie)
                    r["dur"] = round(d / 1000.0, 1) if d > 0 else None
                    r["cd"] = round(cd / 1000.0, 1) if cd > 0 else None
                    r["up"] = round(min(1.0, d / float(cd)), 3) if d > 0 and cd > 0 else (1 if d < 0 else None)
                    r = {k: v for k, v in r.items() if v is not None}
                out.append(r)
            elif aura == "43":  # proc: damage to the attacker
                # the spell's own text decides block vs hit (an item's "+N Block Rating" line says nothing about this proc)
                block = re.search(r"\bblock", c.desc.get(sid, ""), re.I)
                if not c.proc_mask(sid) & TAKEN and not block:
                    continue
                r = dict(dmg(e, c.school(sid), sid), k="block" if block else "proc")
                p = c.chance(sid)
                if p is not None: r["p"] = p
                out.append(r)
            elif aura == "42":  # proc: cast a spell
                ts = e["EffectTriggerSpell"]
                block = re.search(r"\bblock", c.desc.get(sid, ""), re.I)
                if not (block or c.proc_mask(sid) & TAKEN) or ts not in c.se:
                    continue
                for te in c.se[ts]:
                    if te["Effect"] in DAMAGE_EFFECTS and float(te["EffectBasePointsF"] or 0) > 0:
                        r = dict(dmg(te, c.school(ts), sid), k="block" if block else "proc")
                        p = c.chance(sid)
                        if p is not None: r["p"] = p
                        if is_aoe(c, ts, te, c.desc.get(sid, "")): r["aoe"] = True
                        out.append(r)
                        break
    for r in out:
        r["src"] = "client"
    return out


def _secs(n, unit):
    return int(n) * (60 if unit.lower().startswith("min") else 3600 if unit.lower().startswith("hour") else 1)


def text_rf(effects):
    """rf parsed from tooltip lines, for items the client has no spell for."""
    out = []
    for line in effects or []:
        m = re.search(r"When struck in combat,? inflicts (\d+) %s damage to the attacker" % SCHOOL_RE, line, re.I) \
            or re.search(r"Deals (\d+) %s damage to anyone who strikes you with a melee attack\.?$" % SCHOOL_RE, line, re.I) \
            or re.search(r"Deals? (\d+) %s damage to melee attackers" % SCHOOL_RE, line, re.I)
        if m and line.startswith("Equip:"):
            out.append({"k": "hit", "s": m.group(2).capitalize(), "v": int(m.group(1))})
            continue
        m = re.search(r"When struck in combat you inflict (\d+) %s and (\d+) %s damage to the attacker" % (SCHOOL_RE, SCHOOL_RE), line, re.I)
        if m:
            out.append({"k": "hit", "s": m.group(2).capitalize(), "v": int(m.group(1))})
            out.append({"k": "hit", "s": m.group(4).capitalize(), "v": int(m.group(3))})
            continue
        m = re.search(r"has a (\d+(?:\.\d+)?)%% chance of inflicting (\d+) to (\d+) %s damage to the attacker" % SCHOOL_RE, line, re.I)
        if m:
            lo, hi = int(m.group(2)), int(m.group(3))
            out.append({"k": "proc", "s": m.group(4).capitalize(), "v": round((lo + hi) / 2.0, 1), "lo": lo, "hi": hi,
                        "p": round(float(m.group(1)) / 100, 3)})
            continue
        m = re.search(r"Deals (\d+) to (\d+) %s damage every time you block" % SCHOOL_RE, line, re.I) \
            or re.search(r"Deals (\d+)() %s damage every time you block" % SCHOOL_RE, line, re.I)
        if m:
            lo = int(m.group(1)); hi = int(m.group(2) or lo)
            r = {"k": "block", "s": m.group(3).capitalize(), "v": round((lo + hi) / 2.0, 1)}
            if hi != lo: r["lo"], r["hi"] = lo, hi
            out.append(r)
            continue
        m = re.search(r"^Use: .*?causing (\d+) %s damage to attackers when hit\.\s*Lasts (\d+) (sec|min|hour)" % SCHOOL_RE, line, re.I) \
            or re.search(r"^Use: .*?deals (\d+) %s damage to anyone who strikes you with a melee attack for (\d+) (sec|min|hour)" % SCHOOL_RE, line, re.I)
        if m:
            r = {"k": "use", "s": m.group(2).capitalize(), "v": int(m.group(1)), "dur": _secs(m.group(3), m.group(4))}
            cm = re.search(r"\((\d+) (Sec|Min|Hour)s? Cooldown\)", line, re.I)
            if cm:
                r["cd"] = _secs(cm.group(1), cm.group(2))
                r["up"] = round(min(1.0, r["dur"] / float(r["cd"])), 3)
            out.append(r)
    for r in out:
        r["src"] = "text"
    return out


def wearable(it):
    return it.get("slot") not in (None, "", "unknown")


_ST = []


def amount(r):
    """"70 to 116" or "50", as the game prints an amount."""
    return ("%s to %s" % (r["lo"], r["hi"])) if r.get("lo") is not None and r.get("hi") not in (None, r.get("lo")) else ("%g" % r["v"])


def stale_note(r, what="damage"):
    """The note for a text that quotes other numbers than the spell the effect casts."""
    amt = amount(r)
    if what == "heal":
        does = "heals for %s" % amt
    elif what == "mana":
        does = "restores %s mana" % amt
    else:
        does = "deals %s%s damage" % (amt, (" " + r["s"]) if r.get("s") and r["s"] != "Physical" else "")
    return "The game's text quotes other numbers. The spell this effect actually casts %s, and ForeverRank counts that." % does


def client_text(c, r):
    """The spell's own description with its numbers filled in, or None. tools/spelltext.py fills every token it
    knows from the tables; this file's own small renderer is the fallback, and nothing with a "$" left is returned."""
    sid = str(r.get("sp") or "")
    d = (c.desc.get(sid) or "").strip()
    if not d:
        return None
    try:
        if not _ST:
            import spelltext
            _ST.append(spelltext.Client(BUILD))
        txt = _ST[0].item_text(sid)
        if txt and "$" not in txt:
            return txt
    except Exception:
        pass
    amt = ("%s to %s" % (r["lo"], r["hi"])) if r.get("lo") is not None and r.get("hi") not in (None, r.get("lo")) else str(r["v"])
    pct = ("%g" % round(r["p"] * 100, 2)) if r.get("p") is not None else None
    if pct:
        d = re.sub(r"\$h\d?", pct, d)                 # "$h1% chance"
        d = re.sub(r"\$[sm]1%", pct + "%", d)          # the spell's own first value used as the chance
    d = re.sub(r"\$(\d{3,})?[sm]1", amt, d)
    if re.search(r"\$", d):
        return None  # a token this renderer cannot fill: no half sentence
    return re.sub(r"\s+", " ", d).strip()


def apply_items(items, c):
    """Set rf on every wearable item that reflects damage; returns a report."""
    rep = {"kinds": collections.Counter(), "src": collections.Counter(), "items": 0, "differ": []}
    for it in items:
        it.pop("rf", None)
        if not wearable(it):
            continue
        eff = it.get("effects") or []
        rf = client_rf(c, it["id"], eff)
        if rf:
            # the tooltip shows numbers too: say where the two disagree (the client's spell tables win)
            tr = text_rf(eff)
            for a, b in zip(rf, tr):
                if a["k"] == b["k"] and (abs(a["v"] - b["v"]) > 0.6 or a.get("p") != b.get("p")):
                    rep["differ"].append((it["id"], it["name"], a, b))
            # where the tooltip shown (often Classic's text) doesn't say it, or says other numbers, keep the client's own
            # sentence so the page can show what the reflect is (Razorsteel Shoulders, Razor Gauntlets)
            if len(tr) < len(rf) or any(a["k"] == b["k"] and abs(a["v"] - b["v"]) > 0.6 for a, b in zip(rf, tr)):
                for r in rf:
                    t = client_text(c, r)
                    if t:
                        r["t"] = t
            for r in rf:  # the text can quote an older spell than the one the aura casts (Vile Protector)
                t = client_text(c, r)
                if t and amount(r) not in t and re.search(r"\d+(?: to \d+)? (?:[A-Z][a-z]+ )?damage", t):  # it quotes a number
                    r["tn"] = stale_note(r)
        else:
            rf = text_rf(eff)
        if rf:
            it["rf"] = rf
            rep["items"] += 1
            for r in rf:
                rep["kinds"][r["k"]] += 1
                rep["src"][r["src"]] += 1
    return rep


def enchants(c, by):
    """plan/enchants.json: reflect enchants and attachments, numbers from the client."""
    def item_skill(iid, default):
        it = by.get(str(iid)) or {}
        sk = it.get("sk") or default
        return sk if sk and sk[1] else None  # unknown: left out rather than shown as "skill 0"

    def spike(eid, iid, name, sid, note):
        e = c.se[sid][0]
        rf = dict(dmg(e, c.school(sid), sid), k="block")
        p = c.chance(sid)
        if p is not None: rf["p"] = p
        return {"id": eid, "item": iid, "name": name, "slot": "offhand", "needs": "Shield", "rf": rf, "stats": {},
                "skill": item_skill(iid, ["Blacksmithing", 0]), "note": note}

    out = [
        spike("iron-spike", 6042, "Iron Shield Spike", "9784",
              "Blacksmithing attachment; damage on each block, client spell 9784. Anyone can attach it to a shield."),
        spike("mithril-spike", 7967, "Mithril Shield Spike", "9782",
              "Blacksmithing attachment; damage on each block, client spell 9782. Anyone can attach it to a shield."),
        spike("thorium-spike", 12645, "Thorium Shield Spike", "16624",
              "Blacksmithing attachment; damage on each block, client spell 16624. Anyone can attach it to a shield."),
    ]
    sid = "435901"
    e = c.se[sid][0]
    rf = dict(dmg(e, c.school(sid), sid), k="hit")
    cd = c.cooldown_ms(sid)
    note = ("Enchanting formula 273591 teaches Enchant Chest - Retricutioner (spell 435903); the enchant's damage shield is "
            "client spell 435901: %s Physical damage to each melee attacker." % rf["v"])
    if cd:
        note += (" The client gives that aura a %g s recovery time; whether it limits how often it hits is not shown in the "
                 "tables, so the Forge counts every hit." % (cd / 1000.0))
    out.append({"id": "retricutioner", "item": 273591, "name": "Enchant Chest - Retricutioner", "slot": "chest", "rf": rf,
                "stats": {}, "skill": item_skill(273591, ["Enchanting", 0]), "note": note})
    return {"note": "Enchants and attachments that damage attackers, numbers from the beta client's spell tables (build %s, "
                    "tools/apply_reflect.py). v is the average, lo-hi the range; skill is the profession level needed to make "
                    "it, not to use it." % BUILD,
            "enchants": out}


def reflect_tables(c):
    """plan/reflect.json: class abilities and buffs that damage attackers."""
    ret = []
    for sid in ("7294", "10298", "10299", "10300", "10301"):
        e = next(x for x in c.se[sid] if x["EffectAura"] == "15")
        ret.append([c.learn(sid), num(e["EffectBasePointsF"]), int(sid)])
    ret_coef = num(next(x for x in c.se["7294"] if x["EffectAura"] == "15")["EffectBonusCoefficient"])
    hs = []
    hs_coef, hs_block, hs_charges, hs_dur, hs_cd = 0, 0, 0, 0, 0
    for sid in ("20925", "20927", "20928"):
        e = next(x for x in c.se[sid] if x["EffectAura"] == "43")
        hs.append([c.learn(sid), num(e["EffectBasePointsF"]), int(sid)])
        hs_coef = round(float(e["EffectBonusCoefficient"] or 0), 3)
        hs_block = num(next(x for x in c.se[sid] if x["EffectAura"] == "51")["EffectBasePointsF"])
        hs_charges = int((c.aura.get(sid) or {}).get("ProcCharges") or 0)
        hs_dur = c.duration_ms(sid) / 1000.0
        hs_cd = c.cooldown_ms(sid) / 1000.0
    red_p = c.chance("20127")
    red = c.se.get("20128", [])
    red_block = num(red[0]["EffectBasePointsF"]) if red else None
    thorns = []
    for sid in ("467", "782", "1075", "8914", "9756", "9910"):
        thorns.append([c.learn(sid), num(c.se[sid][0]["EffectBasePointsF"])])
    eye = num(c.se["9799"][0]["EffectBasePointsF"]) if c.se.get("9799") else None
    return {
        "note": "Damage done back to attackers by class abilities and buffs, from the beta client's spell tables (build %s, "
                "tools/apply_reflect.py) unless a field says otherwise. Retribution Aura ranks are [level learned, damage per "
                "hit taken, spell id]. Blessing of Sanctuary is not in the Forever client at all. Improved Retribution Aura "
                "(spells 20091/20092) still has spell rows in the client, but no Forever talent teaches it, so nothing raises "
                "Retribution Aura's damage." % BUILD,
        "classes": {"PALADIN": {
            "retAura": ret,
            "retCoef": ret_coef,
            "holyShield": {"talent": "Holy Shield", "ranks": hs, "coef": hs_coef, "charges": hs_charges, "dur": hs_dur,
                           "cd": hs_cd, "block": hs_block,
                           "note": "Damage per blocked attack, plus coef x spell power. block is the block chance the client "
                                   "spell adds (%s%%); the Forge's talent text reads 20%%, transcribed from demo footage." % hs_block},
            "redoubt": {"talent": "Redoubt", "p": red_p, "block": [6, 12, 18, 24, 30], "dur": c.duration_ms("20128") / 1000.0 or 10,
                        "charges": int((c.aura.get("20128") or {}).get("ProcCharges") or 5),
                        "note": "A %g%% chance on a damaging melee hit taken (client spell 20127) to raise block chance; the "
                                "buff (spell 20128) lasts dur seconds or charges blocks. The block chance per rank comes from "
                                "the talent text: the client scales it through curve tables our datamine does not have "
                                "(spell 20128 carries %s, the top rank)." % ((red_p or 1) * 100, red_block)},
            "eyeForAnEye": {"talent": "Eye for an Eye", "pct": [5, 10],
                            "note": "Percent of a critical strike's damage dealt back, capped at 50%% of the paladin's health. "
                                    "From the talent text: the client spell 9799 still carries Classic's %s%% and the per-rank "
                                    "curve is not in our datamine." % eye},
        }},
        "buffs": {"thorns": {"name": "Thorns (druid)", "ranks": thorns, "s": c.school("467"), "dur": c.duration_ms("467") / 1000.0,
                             "note": "[level learned, damage per hit taken], spells 467/782/1075/8914/9756/9910."}},
    }


def run(db, dry=False, verbose=True):
    """Fill rf on db["items"] and write enchants.json and reflect.json. db is written by the caller."""
    c = Client()
    rep = apply_items(db["items"], c)
    by = {str(i["id"]): i for i in db["items"]}
    ench, refl = enchants(c, by), reflect_tables(c)
    if verbose:
        print("reflect: %d items with rf; by kind %s; by source %s" % (rep["items"], dict(rep["kinds"]), dict(rep["src"])))
        for iid, name, a, b in rep["differ"]:
            print("  client and tooltip differ: %s %s client %s/%s, tooltip %s/%s" % (iid, name, a["v"], a.get("p"), b["v"], b.get("p")))
    if not dry:
        for path, doc in ((ENCHANTS, ench), (REFLECT, refl)):
            with open(path, "w") as f:
                json.dump(doc, f, ensure_ascii=False, indent=1)
                f.write("\n")
        if verbose:
            print("wrote plan/enchants.json (%d) and plan/reflect.json" % len(ench["enchants"]))
    return rep


def main():
    dry = "--dry" in sys.argv
    db = json.load(open(DB))
    run(db, dry)
    if dry:
        return
    with open(DB, "w") as f:
        json.dump(db, f, ensure_ascii=False, separators=(",", ":"))
    if os.path.exists(LOOT_ITEMS):
        by = {str(i["id"]): i for i in db["items"]}
        li = json.load(open(LOOT_ITEMS))
        for it in li["items"]:
            src = by.get(str(it["id"]))
            it.pop("rf", None)
            if src and src.get("rf"):
                it["rf"] = src["rf"]
        with open(LOOT_ITEMS, "w") as f:
            json.dump(li, f, ensure_ascii=False, separators=(",", ":"))
    print("wrote plan/items-db.json")


if __name__ == "__main__":
    main()
