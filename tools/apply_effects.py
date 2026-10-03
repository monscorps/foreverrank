#!/usr/bin/env python3
"""Proc, on-use and chance-on-hit effects of wearable items: fx in plan/items-db.json and codex/loot-items.json.

fx entries: {k, what, s, v, lo, hi, ticks, dur, p, ppm, ps, cd, icd, aoe, stat, only, sp, src, t}
  k     "hit"   a proc on landing a melee or ranged hit (ItemEffect TriggerType 2 "Chance on hit:", or an equip proc
                aura whose proc flags are melee/ranged hits done)
        "use"   an on-use effect (TriggerType 0)
        "equip" any other equip proc: on spell cast or spell hit, on being struck (when it is not damage back at the
                attacker, which rf already lists), on a kill, on dying...
  what  "damage" direct damage, "dot" damage over time (v is the total), "heal" (v the amount, a hot's total),
        "buff" on you (stat holds Forge stat keys when the aura maps to one), "debuff" on the target, "summon",
        "mana", "other"
  s     school, for damage and dot; v the average (base points), lo/hi the range (half up, as apply_reflect)
  ticks, dur  ticks and seconds; p chance per hit 0..1; ppm procs per minute (the client's SpellProcsPerMinute)
  pn    a sentence about the chance where the client's numbers are not usable as they stand (it contradicts itself,
        or gives only a raised chance); p is then absent
  ct    the Forever client's own sentence for the effect, where the item shows Classic text or no line at all
  tn    a note where that sentence quotes an older spell's numbers than the spell the effect casts
  ps    where p or ppm comes from: "client" (spell tables), "wowhead" (its "(Proc chance: N%)" note on the line),
        "tooltip" (the line itself says "N% chance"); absent when the chance is not known
  cd    cooldown seconds (use); icd internal cooldown seconds of a proc (SpellAuraOptions.ProcCategoryRecovery,
        or "Ns cooldown" in Wowhead's tooltip), shown only from 1 s up
  aoe   true when it hits several targets
  only  the proc works only against these targets ("Murlocs", "Frozen targets"...): not part of a general estimate
  sp    the item's client spell id (the ItemEffect spell, as rf.sp)
  src   "client" (spell tables) or "text" (parsed from the tooltip where the client has no spell rows)
  t     the item's tooltip line it came from

Several fx entries can share one proc (same k and sp): a spell that deals damage and slows gives a damage and a
debuff entry with the same chance. They are one roll, so the damage entries add up and the rest is description.

The client carries no chance for "Chance on hit:" weapon procs (TriggerType 2): the server decides it. p stays
absent then and the site says "chance unknown"; nothing here assumes Classic's 1 PPM. No item spell in this build
references SpellProcsPerMinute either, so ppm is filled only if a later build starts using it.

Damage reflected at attackers stays in rf (tools/apply_reflect.py) and is not repeated here.

  python3 tools/apply_effects.py          # rewrite fx in plan/items-db.json and codex/loot-items.json
  python3 tools/apply_effects.py --dry    # report only
  python3 tools/apply_effects.py --report # report with the top weapons and the chance-unknown list
Also run at the end of tools/scavenge_items.py.
"""
import collections, csv, json, math, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import apply_reflect as ar

ROOT = ar.ROOT
DB, LOOT_ITEMS, WAGO = ar.DB, ar.LOOT_ITEMS, ar.WAGO
SCHOOL_RE = ar.SCHOOL_RE

# proc flags (ProcTypeMask_0): done melee swing 0x4, melee ability 0x10, ranged swing 0x40, ranged ability 0x100
DONE_HIT = 0x4 | 0x10 | 0x40 | 0x100
AURA_APPLY = ("6", "35", "27", "119", "128", "129", "143", "174", "202")
ENEMY_TARGETS = {"6", "15", "16", "22", "28", "53", "54", "77"}  # target enemy, area enemy around, cone, chain...
AREA_TARGETS = {"15", "16", "22", "28", "8", "30", "31", "53", "54", "104", "108", "110"}
STAT_NAMES = {0: "strength", 1: "agility", 2: "stamina", 3: "intellect", 4: "spirit"}
SPELL_SCHOOL_KEYS = {2: "holySpellDamage", 4: "fireSpellDamage", 8: "natureSpellDamage", 16: "frostSpellDamage",
                     32: "shadowSpellDamage", 64: "arcaneSpellDamage"}
RESIST_KEYS = {1: "bonusArmor", 2: "holyResist", 4: "fireResist", 8: "natureResist", 16: "frostResist",
               32: "shadowResist", 64: "arcaneResist", 126: "allResist"}
DEBUFF_WORDS = r"reduc|slow|lower|decreas|stun|silenc|sleep|fear|root|immobil|snare|curse|poison|disarm|confus|weaken|cripple"


def _rows(table):
    path = os.path.join(WAGO, table + ".csv")
    return list(csv.DictReader(open(path, encoding="utf-8"))) if os.path.exists(path) else []


class Client(ar.Client):
    def __init__(self):
        ar.Client.__init__(self)
        self.ppm_rate = {r["ID"]: float(r["BaseProcRate"] or 0) for r in _rows("SpellProcsPerMinute")}
        self.radius = {r["ID"]: r for r in _rows("SpellRadius")}

    def aura_opts(self, sid):
        return self.aura.get(sid) or {}

    def raw_chance(self, sid):
        a = self.aura.get(sid)
        return int(a["ProcChance"]) if a and a["ProcChance"] not in ("", None) else None

    def ppm(self, sid):
        pid = self.aura_opts(sid).get("SpellProcsPerMinuteID") or "0"
        r = self.ppm_rate.get(pid)
        return round(r, 2) if r else None

    def icd(self, sid):
        ms = int(self.aura_opts(sid).get("ProcCategoryRecovery") or 0)
        return round(ms / 1000.0, 1) if ms >= 1000 else None


def secs(ms):
    s = ms / 1000.0
    return int(s) if s == int(s) else round(s, 1)


def eff_aoe(e):
    return bool(int(e.get("EffectRadiusIndex_0") or 0)) or e.get("ImplicitTarget_0") in AREA_TARGETS \
        or int(e.get("EffectChainTargets") or 0) > 1


def on_enemy(e):
    return e.get("ImplicitTarget_0") in ENEMY_TARGETS or e.get("ImplicitTarget_1") in ENEMY_TARGETS


def aura_stat(e):
    """{forge stat key: value} for a buff aura that maps to one, else {}."""
    aura, misc, v = e["EffectAura"], int(e["EffectMiscValue_0"] or 0), ar.num(e["EffectBasePointsF"])
    if aura == "29":
        if misc == -1:
            return {k: v for k in STAT_NAMES.values()}
        return {STAT_NAMES[misc]: v} if misc in STAT_NAMES else {}
    if aura == "99":
        return {"attackPower": v}
    if aura == "124":
        return {"rangedAttackPower": v}
    if aura == "13":
        if misc & 126 == 126 or misc == 127:
            return {"spellDamage": v}
        return {SPELL_SCHOOL_KEYS[misc]: v} if misc in SPELL_SCHOOL_KEYS else {}
    if aura == "135":
        return {"healing": v}
    if aura == "22":
        return {RESIST_KEYS[misc]: v} if misc in RESIST_KEYS else {}
    if aura == "52":
        return {"crit": v}
    if aura == "54":
        return {"hit": v}
    if aura == "57":
        return {"spellCrit": v}
    if aura == "55":
        return {"spellHit": v}
    if aura == "85" and misc == 0:
        return {"mp5": v}
    if aura == "161":
        return {"hp5": v}
    return {}


def payload(c, sid, depth=0, seen=None):
    """Components of what a spell does: list of {what, s, v, lo, hi, ticks, dur, aoe, stat}."""
    seen = set() if seen is None else seen  # an empty set passed in must be filled, not replaced
    if sid in seen or depth > 3 or sid not in c.se:
        return []
    seen.add(sid)
    out = []
    dur_ms = c.duration_ms(sid)
    dur = secs(dur_ms) if dur_ms > 0 else None
    school = c.school(sid)
    for e in c.se[sid]:
        eff, aura = e["Effect"], e["EffectAura"]
        bp = float(e["EffectBasePointsF"] or 0)
        trig = e["EffectTriggerSpell"]
        if eff in ("2", "9") and bp > 0 and e["ImplicitTarget_0"] == "1":
            continue  # damage to yourself (Thorncursed Grips hits both you and the target)
        if eff in ("2", "9") and bp > 0:  # school damage, health leech
            d = ar.dmg(e, school, sid)
            d.pop("sp", None)
            out.append(dict(d, what="damage", aoe=eff_aoe(e)))
        elif eff == "10" and bp > 0:  # heal, with the client's range
            d = ar.dmg(e, None, sid)
            out.append({k: v for k, v in {"what": "heal", "v": d["v"], "lo": d.get("lo"), "hi": d.get("hi"), "aoe": eff_aoe(e)}.items() if v is not None})
        elif eff == "30" and bp > 0:  # energize
            d = ar.dmg(e, None, sid)
            out.append({k: v for k, v in {"what": "mana" if e["EffectMiscValue_0"] == "0" else "other", "v": d["v"], "lo": d.get("lo"), "hi": d.get("hi")}.items() if v is not None})
        elif eff in ("8", "62") and bp > 0:  # power drain, power burn
            out.append({"what": "mana", "v": ar.num(bp)})
        elif eff in ("64", "140", "142", "148") and trig not in ("", "0"):  # trigger spell
            out += payload(c, trig, depth + 1, seen)
        elif eff in ("28", "41", "42", "56", "112"):  # summons
            out.append({"what": "summon", "dur": dur})
        elif eff in AURA_APPLY:
            per = int(e["EffectAuraPeriod"] or 0)
            ticks = int(dur_ms // per) if per > 0 and dur_ms > 0 else None
            if aura in ("3", "53") and bp > 0 and e["ImplicitTarget_0"] == "1":
                continue  # a cost on yourself (Skull of Impending Doom, Circle of Flame)
            if aura == "85" and bp > 0 and e["EffectMiscValue_0"] == "0" and "$o" in (c.desc.get(sid) or ""):
                out.append({"what": "mana", "v": ar.num(bp), "dur": dur})  # drinks: "Restores $o1 mana over $d"
                continue
            if aura in ("3", "53") and bp > 0:  # periodic damage, periodic leech
                r = {"what": "dot", "s": school, "v": ar.num(bp * ticks) if ticks else ar.num(bp), "ticks": ticks,
                     "dur": dur, "aoe": eff_aoe(e)}
                out.append(r)
            elif aura == "8" and bp > 0:  # periodic heal
                out.append({"what": "heal", "v": ar.num(bp * ticks) if ticks else ar.num(bp), "ticks": ticks, "dur": dur})
            elif aura == "24" and bp > 0:  # periodic energize
                out.append({"what": "mana" if e["EffectMiscValue_0"] == "0" else "other",
                            "v": ar.num(bp * ticks) if ticks else ar.num(bp), "ticks": ticks, "dur": dur})
            elif aura in ("23", "226") and trig not in ("", "0"):  # periodic trigger spell
                sub = payload(c, trig, depth + 1, seen)
                for r in sub:
                    if r["what"] == "damage" and ticks:
                        r = dict(r, what="dot", v=ar.num(r["v"] * ticks), ticks=ticks, dur=dur)
                        r.pop("lo", None); r.pop("hi", None)
                    elif r["what"] in ("heal", "mana") and ticks:
                        r = dict(r, v=ar.num(r["v"] * ticks), ticks=ticks, dur=dur)
                    out.append(r)
            elif aura == "15":  # damage shield: rf's job
                out.append({"what": "reflect"})
            elif aura in ("42", "43", "4") and not on_enemy(e):
                out.append({"what": "buff", "dur": dur})
            elif aura not in ("0",):
                if on_enemy(e) or aura in ("33", "12", "26", "27", "5", "7", "6"):
                    out.append({"what": "debuff", "dur": dur, "aoe": eff_aoe(e)})
                else:
                    st = aura_stat(e)
                    out.append({"what": "buff", "dur": dur, "stat": st or None})
        elif eff == "3":  # dummy: a script does it
            out.append({"what": "other", "dur": dur})
    return out


def merge(comps):
    """One entry per kind of outcome: damage of one school adds up, stat buffs merge."""
    by = collections.OrderedDict()
    for r in comps:
        if r["what"] == "reflect":
            continue
        key = (r["what"], r.get("s"))
        if key not in by:
            by[key] = dict(r)
            continue
        m = by[key]
        if r["what"] in ("damage", "dot", "heal", "mana") and r.get("v"):
            if "lo" in m or "lo" in r:
                m["lo"] = ar.num(m.get("lo", m["v"]) + r.get("lo", r["v"]))
                m["hi"] = ar.num(m.get("hi", m["v"]) + r.get("hi", r["v"]))
            m["v"] = ar.num(m["v"] + r["v"])
            m["aoe"] = m.get("aoe") or r.get("aoe")
        if r.get("stat"):
            m["stat"] = dict(m.get("stat") or {}, **r["stat"])
        if r.get("dur") and not m.get("dur"):
            m["dur"] = r["dur"]
    for m in by.values():
        st = m.get("stat") or {}
        if st.get("spellDamage") and st.get("spellDamage") == st.get("healing"):
            st["spellPower"] = st.pop("spellDamage")
            st.pop("healing")
    out = list(by.values())
    # "other" only when nothing else says what the spell does
    if len(out) > 1:
        out = [r for r in out if r["what"] != "other"] or out
    return out


# --- the tooltip -------------------------------------------------------------------------------------------------

PREFIX = {"0": "Use:", "1": "Equip:", "2": "Chance on hit:"}


def line_numbers(s):
    return set(re.findall(r"\d+(?:\.\d+)?", s))


def pick_line(lines, prefix, used, c, sid, comps):
    """The item's tooltip line for this item spell (best word and number overlap with the spell's text)."""
    cands = [(i, l) for i, l in enumerate(lines) if l.startswith(prefix) and i not in used]
    if not cands:
        return None, None
    desc = (c.desc.get(sid) or "") + " " + (c.name.get(sid) or "")
    words = set(w for w in re.findall(r"[a-z]{4,}", desc.lower()))
    nums = set()
    for r in comps:
        for f in ("v", "lo", "hi", "dur"):
            if r.get(f) is not None:
                nums.add(str(ar.num(r[f])))
        for v in (r.get("stat") or {}).values():
            nums.add(str(v))

    def score(il):
        l = il[1].lower()
        return 3 * len(nums & line_numbers(l)) + len(words & set(re.findall(r"[a-z]{4,}", l)))
    best = max(cands, key=score)
    bn = line_numbers(best[1].lower())
    if nums and bn and not nums & bn and score(best) < 3:
        return None, None  # different numbers and little else in common: another effect's line
    if score(best) < 2:
        return None, None  # e.g. a Classic tooltip on an item whose Forever spell does something else
    return best


def _secs(n, unit):
    n = float(n)
    u = unit.lower()
    v = n * (60 if u.startswith("m") else 3600 if u.startswith("h") else 1)
    return int(v) if v == int(v) else v


TEXT_STATS = [
    (r"all (?:stats|attributes) by (\d+)", ["strength", "agility", "stamina", "intellect", "spirit"]),
    (r"(?:increases?|increasing|grants?|gain) (?:your |the wearer's |bearer's )?strength by (\d+)", ["strength"]),
    (r"(?:increases?|increasing|grants?|gain) (?:your |the wearer's |bearer's )?agility by (\d+)", ["agility"]),
    (r"(?:increases?|increasing|grants?|gain) (?:your |the wearer's |bearer's )?stamina by (\d+)", ["stamina"]),
    (r"(?:increases?|increasing|grants?|gain) (?:your |the wearer's |bearer's )?intellect by (\d+)", ["intellect"]),
    (r"(?:increases?|increasing|grants?|gain) (?:your |the wearer's |bearer's )?spirit by (\d+)", ["spirit"]),
    (r"ranged attack power by (\d+)", ["rangedAttackPower"]),
    (r"(?<!ranged )attack power by (\d+)", ["attackPower"]),
    (r"damage and healing (?:done )?(?:by magical spells and effects )?by up to (\d+)", ["spellPower"]),
    (r"damage (?:done )?(?:by|of) (?:your )?(?:magical )?spells(?: and effects)? by up to (\d+)", ["spellDamage"]),
    (r"healing (?:done )?(?:by spells and effects )?by up to (\d+)", ["healing"]),
    (r"(?:increases?|increasing|grants?|gain)[^.]*? (\d+) armor", ["bonusArmor"]),
    (r"armor by (\d+)", ["bonusArmor"]),
]


def text_fx(line):
    """fx entries parsed from one tooltip line, [] when it is no proc or use."""
    if line.startswith("Chance on hit:"):
        k = "hit"
    elif line.startswith("Use:"):
        k = "use"
    elif line.startswith("Equip:"):
        body = line[6:]
        if ar.text_rf([line]) or re.search(r"(improves|increases) your chance to|chance to (get a )?critical|critical effect chance", body, re.I):
            return []
        if not re.search(r"chance|sometimes|when struck|when you kill|killing|dying|harmful spell|spells? land|"
                         r"melee attacks|ranged auto-attacks|attacks with this weapon|on hit|on a successful", body, re.I):
            return []
        k = "hit" if re.search(r"chance on (melee )?hit|melee (?:and ranged )?attacks|ranged auto-attacks|"
                               r"successful melee|melee swing|on striking|attacks with this weapon|melee hit", body, re.I) \
            and not re.search(r"when struck|harmful spell|spells? land", body, re.I) else "equip"
    else:
        return []
    body = re.sub(r"\((?:Proc chance|\d+ (?:Sec|Min|Hour)).*?\)", "", line.split(":", 1)[1])
    base = {"k": k, "src": "text", "t": line}
    m = re.search(r"(\d+(?:\.\d+)?)%\s*chance|chance of (\d+(?:\.\d+)?)%|Proc chance: (\d+(?:\.\d+)?)%", line, re.I)
    if m:
        base["p"] = round(float(next(g for g in m.groups() if g)) / 100, 3)
        base["ps"] = "wowhead" if m.group(3) else "tooltip"  # "(Proc chance: N%)" is Wowhead's addition to the line
    m = re.search(r"Proc chance: [^)]*?(\d+(?:\.\d+)?)\s*(s|m|h)\w* cooldown", line, re.I) \
        or re.search(r"cannot occur more than once every (\d+) (sec|min)", line, re.I)
    if m:
        base["icd"] = _secs(m.group(1), m.group(2))
    m = re.search(r"\((\d+(?:\.\d+)?) (Sec|Min|Hour)s? Cooldown\)", line, re.I)
    if m and k == "use":
        base["cd"] = _secs(m.group(1), m.group(2))
    dm = re.search(r"(?:for|lasts) (\d+(?:\.\d+)?) (sec|min|hour)", body, re.I)
    dur = _secs(dm.group(1), dm.group(2)) if dm else None
    if re.search(r"all (?:nearby )?(?:enemies|targets|party members)|nearby enemies|enemies within|all targets", body, re.I):
        base["aoe"] = True
    out = []
    # damage over time
    m = re.search(r"(\d+) (?:%s )?damage over (\d+(?:\.\d+)?) (sec|min)" % SCHOOL_RE, body, re.I) \
        or re.search(r"(?:bleed|burn|poison\w*)[^.]*? for (\d+)() damage over (\d+) (sec)", body, re.I)
    if m:
        r = dict(base, what="dot", v=int(m.group(1)), dur=_secs(m.group(3), m.group(4)))
        if m.group(2): r["s"] = m.group(2).capitalize()
        elif re.search(r"bleed|wound", body, re.I): r["s"] = "Physical"
        out.append(r)
    else:
        m = re.search(r"(\d+) to (\d+) (?:%s )?damage" % SCHOOL_RE, body, re.I) \
            or re.search(r"(\d+)() (?:%s )?damage" % SCHOOL_RE, body, re.I)
        if m and not re.search(r"absorb|reduc\w* (?:all )?(?:physical )?damage|damage taken", body[:m.end() + 20], re.I):
            lo, hi = int(m.group(1)), int(m.group(2) or m.group(1))
            r = dict(base, what="damage", v=round((lo + hi) / 2.0, 1) if hi != lo else lo)
            if hi != lo: r["lo"], r["hi"] = lo, hi
            if m.group(3): r["s"] = m.group(3).capitalize()
            elif re.search(r"lightning", body, re.I): r["s"] = "Nature"
            out.append(r)
    m = re.search(r"(?:restores?|heals?) (\d+) (health|mana) every (\d+(?:\.\d+)?) sec(?:onds?)?", body, re.I)
    if m and dur:
        out.append(dict(base, what="heal" if m.group(2).lower() == "health" else "mana",
                        v=int(round(int(m.group(1)) * dur / float(m.group(3)))), dur=dur))
        return out
    m = re.search(r"\bheal(?:s|ing)? (?:you|the bearer|bearer|the wielder|all party members[^.]*?)? ?(?:of |for )?(\d+)(?: to (\d+))?", body, re.I) \
        or re.search(r"(?:restores?|gain) (\d+)(?: to (\d+))? health", body, re.I)
    if m and not re.search(r"healing (?:done )?by", body, re.I):
        lo, hi = int(m.group(1)), int(m.group(2) or m.group(1))
        r = dict(base, what="heal", v=round((lo + hi) / 2.0, 1) if hi != lo else lo)
        if hi != lo: r["lo"], r["hi"] = lo, hi
        out.append(r)
    m = re.search(r"(?:restores?|gain|energize you for|restore) (\d+)(?: to (\d+))? mana", body, re.I)
    if m:
        lo, hi = int(m.group(1)), int(m.group(2) or m.group(1))
        r = dict(base, what="mana", v=round((lo + hi) / 2.0, 1) if hi != lo else lo)
        if hi != lo: r["lo"], r["hi"] = lo, hi
        out.append(r)
    if not out:
        st = {}
        for rx, keys in TEXT_STATS:
            sm = re.search(rx, body, re.I)
            if sm and not any(k in st for k in keys):
                for key in keys:
                    st[key] = int(sm.group(1))
        if re.search(r"summon|calls? forth|raise", body, re.I):
            out.append(dict(base, what="summon"))
        elif re.search(DEBUFF_WORDS, body, re.I) and re.search(r"target|enem|attacker|caster of", body, re.I) and not st:
            out.append(dict(base, what="debuff"))
        elif st:
            out.append(dict(base, what="buff", stat=st))
        elif re.search(r"increas|grant|gain|your|you ", body, re.I):
            out.append(dict(base, what="buff"))
        else:
            out.append(dict(base, what="other"))
    for r in out:
        if dur and r["what"] in ("buff", "debuff", "summon", "heal") and "dur" not in r:
            r["dur"] = dur
    return out


# --- the client --------------------------------------------------------------------------------------------------

def only_vs(text):
    """The targets a conditional proc is limited to ("Murlocs", "Frozen targets"), else None."""
    for m in re.finditer(r"\bagainst ([A-Z][a-z]+(?: targets)?)", text or ""):
        near = (text or "")[max(0, m.start() - 60):m.end() + 40]
        if not re.search(r"times as (?:likely|much)|more likely|doubled|increased|tripled", near):
            return m.group(1)
    return None



_ST = []
AMOUNTS = ("damage", "dot", "heal", "mana")
SCHOOLS = {"Physical", "Holy", "Fire", "Nature", "Frost", "Shadow", "Arcane"}


def norm_line(t):
    """A line reduced to letters, digits and %, with a trailing "(N Min Cooldown)" dropped, for comparing texts."""
    t = re.sub(r"\s*\(\d+(?:\.\d+)?\s*(?:sec|min|hour|hr|day)s?\s*cooldown\)\s*$", "", (t or "").lower())
    return re.sub(r"^(equip|use|chance on hit):\s*", "", re.sub(r"[^a-z0-9%:]+", " ", t)).replace(" ", "").replace(":", "")


def client_sentence(sid):
    """The game's own text for an item effect, filled by tools/spelltext.py; None when a token cannot be filled."""
    if not _ST:
        import spelltext
        _ST.append(spelltext.Client(ar.BUILD))
    if str(sid) == "0":
        return None  # only loads the resolver
    try:
        txt = _ST[0].item_text(sid)
    except Exception:
        return None
    return txt if txt and "$" not in txt else None

def client_fx(c, it, rf_sps):
    """fx for one item from the client's tables; [] when the client has no rows for it."""
    lines = it.get("effects") or []
    used = set()
    out = []
    for ie in c.ixe.get(str(it["id"]), []):
        trig, sid = ie["TriggerType"], ie["SpellID"]
        if trig not in ("0", "1", "2") or sid not in c.se or int(sid) in rf_sps:
            continue
        p = ppm = icd = cd = None
        k = {"0": "use", "2": "hit"}.get(trig)
        if trig == "1":
            pe = next((e for e in c.se[sid] if e["EffectAura"] in ("42", "43", "4")), None)
            mask = c.proc_mask(sid)
            if not pe or (pe["EffectAura"] == "4" and not mask):
                continue  # a passive equip bonus, not a proc
            if pe["EffectAura"] == "43" and mask & ar.TAKEN:
                continue  # damage back at the attacker: rf
            psid = pe["EffectTriggerSpell"]
            if psid in ("", "0"):
                ref = re.search(r"\$(\d{3,})[so]\d", c.desc.get(sid, ""))
                psid = ref.group(1) if ref else None
            k = "hit" if mask & DONE_HIT and not mask & ar.TAKEN else "equip"
            if pe["EffectAura"] == "43":
                comps = [dict(ar.dmg(pe, c.school(sid), sid), what="damage")]
                comps[0].pop("sp", None)
            else:
                comps = payload(c, psid) if psid else []
            pc = c.raw_chance(sid)
            ppm, icd = c.ppm(sid), c.icd(sid)
        else:
            comps = payload(c, sid)
            pc = c.raw_chance(sid) if trig == "2" else None
            ppm = c.ppm(sid) if trig == "2" else None
            if trig == "0":
                ms = c.cooldown_ms(sid, ie)
                cd = secs(ms) if ms > 0 else None
        seen = set()
        reach = [sid] + ([psid] if trig == "1" and psid else [])
        for x in reach:
            payload(c, x, 0, seen)
        # spells the text names add what the effect does not already do (Strike of the Hydra's Fire and Frost); a named
        # spell of a kind already cast is an older copy the text still quotes (bomb satchels: 1318061 casts, its text
        # quotes 1318031), not a second hit
        # Only amounts can double: a buff the text names still adds its stat (Diamond Flask's +20 Strength). A named
        # spell whose school is not the one the text prints next to it is borrowed for its number only (Swine Fists
        # quotes Cursed Murloc Eye's 8 Shadow as "Nature damage" while casting 4 Nature).
        have = {(r["what"], r.get("s")) for r in comps}
        direct = any(r["what"] == "damage" for r in comps)
        for x in reach:
            for ref, word in re.findall(r"\$(\d{4,})[mso]\d(?:\s+(\w+))?", c.desc.get(x, "") or ""):
                if ref not in seen and ref in c.se:
                    for r in payload(c, ref, 0, seen):
                        if r["what"] in AMOUNTS and (r["what"], r.get("s")) in have:
                            continue
                        if r["what"] == "damage" and direct and word.capitalize() in SCHOOLS and word.capitalize() != r.get("s"):
                            continue
                        comps.append(r)
        # a use whose outcome is one of several (Satchel of Potions): not every outcome at once
        if trig == "0" and re.search(r"random|hope for the best|one of the following", c.desc.get(sid, "") or "", re.I) \
                and len({r["what"] for r in comps}) > 1:
            comps = [{"what": "other"}]
        comps = merge(comps)
        if any(r["what"] == "reflect" for r in comps) or not comps:
            if trig == "0" and not comps:
                comps = [{"what": "other"}]
            elif not comps:
                comps = [{"what": "other"}]
        i, t = pick_line(lines, PREFIX[trig], used, c, sid, comps)
        if i is not None:
            used.add(i)
        desc = c.desc.get(sid, "")
        m = re.search(r"\$@spelldesc(\d+)", desc)
        if m:  # "$@spelldesc16939": the text lives on another spell
            desc = desc.replace(m.group(0), c.desc.get(m.group(1), "") or "")
        # The chance wording is judged on the client's own text; the item line only when the client has none
        # (an est item's line is Classic text, and Forever may have rewritten the effect: Hurricane).
        said = desc if desc.strip() else (t or "")
        says_chance = re.search(r"chance|sometimes|occasionally", said, re.I)
        pn = None
        if trig in ("1", "2") and pc is not None and pc < 100:
            p = round(pc / 100.0, 3)
            # the tooltip renders formulas such as ${$h/3}%: the number players read is the rendered one
            ph = re.search(r"(\$\{[^}]*\}|\$[a-zA-Z]+\d*)%\s*chance|chance[^.]{0,30}?(\$\{[^}]*\}|\$[a-zA-Z]+\d*)%", desc)
            form = (ph.group(1) or ph.group(2)) if ph else None
            fm = re.match(r"\$\{\$h\s*/\s*(\d+(?:\.\d+)?)\}", form or "")
            if fm:
                p = round(pc / float(fm.group(1)) / 100.0, 4)  # the chance the client itself renders
            elif t and form and form.lower() != "$h" and not it.get("est"):
                m = re.search(r"(\d+(?:\.\d+)?)%\s*chance|chance of (\d+(?:\.\d+)?)%", t)
                if m:
                    p = round(float(m.group(1) or m.group(2)) / 100, 3)
            lit = re.search(r"(?<![$\d.])(\d+(?:\.\d+)?)%\s*chance|chance of (\d+(?:\.\d+)?)%", desc)
            if not form and lit and abs(float(lit.group(1) or lit.group(2)) - pc) > 0.01:
                # Red Whelp Gloves: the text says 5%, the table 10%; nothing says which one the server rolls
                pn = "the game disagrees with itself: its text says %s%%, its spell table %g%%." % (lit.group(1) or lit.group(2), pc)
                p = None
            elif not form and not lit and re.search(r"times as likely|chance is doubled|twice as likely|doubled", desc, re.I):
                # Ironfoe: "against Orcs ... $s2 times as likely" with no base chance rendered. Where the client renders
                # both (Hand of Justice, Lion Horn, Uther's Strength), the table holds the raised chance, not the base.
                pn = "not known in general. The game's spell table gives %g%%, but the text says the chance is higher in some cases and states no base chance, so %g%% is likely the raised chance only." % (pc, pc)
                p = None
        elif trig == "1" and pc is not None and pc >= 100 and said.strip() and not says_chance \
                and (t or client_sentence(sid)):  # with no line to show, "every time" would hide what triggers it
            p = 1  # every hit ("Adds 4 Fire damage to your weapon attack"); 100 or 101 alone, with no text, proves nothing
        ps = "client" if p is not None or ppm else None
        if p is None and t:
            m = re.search(r"Proc chance: (\d+(?:\.\d+)?)%", t)
            if m:
                p, ps = round(float(m.group(1)) / 100, 3), "wowhead"
        if icd is None and t:
            m = re.search(r"Proc chance: [^)]*?(\d+(?:\.\d+)?)\s*(s|m|h)\w* cooldown", t) \
                or re.search(r"cannot occur more than once every (\d+) (sec|min)", t, re.I)
            if m:
                icd = _secs(m.group(1), m.group(2))
        if k == "hit" and p == 1 and trig == "1" and not t and it.get("cat") == "weapon":
            continue  # the weapon's bonus damage, already in its damage line
        vs = only_vs(t or desc)
        ct = client_sentence(sid) if (it.get("est") or not t) else None
        if ct and any(norm_line(ct) in norm_line(l) for l in ([t] if t else []) + list(lines)):
            ct = None  # one of the item's own lines says it already
        # the text can quote an older spell than the one the effect casts: say so where its one amount is not in it
        tn = None
        nums = [r for r in comps if r.get("v") is not None and r["what"] in AMOUNTS]
        full = client_sentence(sid)
        said_nums = [float(x) for x in re.findall(r"(?<![\d.])(\d+(?:\.\d+)?) (?:\w+ )?(?:mana|damage|health)", full or "")]
        if full and len(nums) == 1 and re.search(r"\d", full) and ar.amount(nums[0]) not in full \
                and not (len(said_nums) > 1 and abs(sum(said_nums) - nums[0]["v"]) < 0.6):  # "gain 8 and drain 8": 16
            r0 = nums[0]
            per = (r0["v"] / r0["ticks"]) if r0.get("ticks") else None
            per_said = None
            if per is not None:
                for a, b in re.findall(r"(?<![\d.])(\d+) to (\d+)(?![\d.])", full):
                    if abs((int(a) + int(b)) / 2.0 - per) <= 1:
                        per_said = "%s to %s" % (a, b)  # a per-tick range ("66 to 74 Fire damage for 10 sec")
                if not per_said and re.search(r"(?<![\d.])%s(?![\d.])" % re.escape("%g" % round(per, 1)), full):
                    per_said = "%g" % round(per, 1)
            if per_said:
                per = per_said
                if not re.search(r"every|per |each", full, re.I):  # a per-tick number the sentence doesn't call one
                    tn = "The game's text gives the amount per tick (%s). In total it %s %s%s, and ForeverRank counts that." % (
                        per, "restores" if r0["what"] == "mana" else "heals" if r0["what"] == "heal" else "deals",
                        ("about " if " to " in per else "") + ar.amount(r0),
                        " mana" if r0["what"] == "mana" else (" " + r0["s"] + " damage") if r0.get("s") and r0["what"] == "dot" else "")
            else:
                tn = ar.stale_note(r0, "heal" if r0["what"] == "heal" else "mana" if r0["what"] == "mana" else "damage")
        if ct and not ct.startswith(PREFIX[trig]):
            ct = PREFIX[trig] + " " + ct  # as the game prints it: "Chance on hit: Blasts a target for 140 Fire damage."
        if not t and not desc.strip():
            comps = [r for r in comps if r["what"] != "other"]  # nothing to show for an unnamed script effect
        for r in comps:
            r = dict(r)
            if r["what"] in ("damage", "dot"):
                r.setdefault("s", "Physical")
            else:
                r.pop("s", None)
            if r.get("lo") is not None and r.get("lo") == r.get("hi"):
                r.pop("lo"); r.pop("hi")
            ent = {"k": k, "what": r["what"]}
            for f in ("s", "v", "lo", "hi", "ticks", "dur"):
                if r.get(f) is not None:
                    ent[f] = r[f]
            for f, v in (("p", p), ("ppm", ppm), ("cd", cd), ("icd", icd), ("ps", ps if p is not None or ppm else None)):
                if v is not None:
                    ent[f] = v
            if r.get("aoe"):
                ent["aoe"] = True
            if r.get("stat"):
                ent["stat"] = r["stat"]
            if vs:
                ent["only"] = vs
            if pn:
                ent["pn"] = pn
            ent["sp"] = int(sid)
            ent["src"] = "client"
            if t:
                ent["t"] = t
            if ct:
                ent["ct"] = ct
            if tn and r.get("v") is not None and r["what"] in AMOUNTS:
                ent["tn"] = tn
            out.append(ent)
    return out


def items_fx(it, c):
    rf_sps = {r.get("sp") for r in it.get("rf") or [] if r.get("sp")}
    if any(ie["SpellID"] in c.se for ie in c.ixe.get(str(it["id"]), [])):
        return client_fx(c, it, rf_sps)  # the client knows this item's spells: its tooltip is not parsed on top
    out = []
    for line in it.get("effects") or []:
        out += text_fx(line)
    return out


def compare(fx):
    """Client entries whose tooltip line reads different numbers."""
    diffs = []
    for e in fx:
        if e["src"] != "client" or not e.get("t"):
            continue
        tx = [r for r in text_fx(e["t"]) if r["what"] == e["what"]]
        if not tx:
            continue
        r = tx[0]
        notes = []
        if e["what"] in ("damage", "dot", "heal", "mana") and e.get("v") is not None and r.get("v") is not None:
            if abs(e["v"] - r["v"]) > max(0.6, 0.02 * abs(e["v"])):
                notes.append("v %s vs text %s" % (e["v"], r["v"]))
        if r.get("p") is not None and e.get("p") is not None and abs(r["p"] - e["p"]) > 0.0005:
            notes.append("p %s vs text %s" % (e["p"], r["p"]))
        if r.get("cd") and e.get("cd") and abs(r["cd"] - e["cd"]) > 0.5:
            notes.append("cd %s vs text %s" % (e["cd"], r["cd"]))
        if e["what"] in ("buff", "debuff", "dot") and r.get("dur") and e.get("dur") and abs(r["dur"] - e["dur"]) > 0.5:
            notes.append("dur %s vs text %s" % (e["dur"], r["dur"]))
        if r.get("stat") and e.get("stat"):
            for key, v in r["stat"].items():
                if key in e["stat"] and abs(e["stat"][key] - v) > 0.5:
                    notes.append("%s %s vs text %s" % (key, e["stat"][key], v))
        if notes:
            diffs.append((e, notes))
    return diffs


def apply_items(items, c):
    rep = {"items": 0, "k": collections.Counter(), "what": collections.Counter(), "src": collections.Counter(),
           "differ": []}
    for it in items:
        it.pop("fx", None)
        if not ar.wearable(it):
            continue
        fx = items_fx(it, c)
        if not fx:
            continue
        it["fx"] = fx
        rep["items"] += 1
        for e in fx:
            rep["k"][e["k"]] += 1
            rep["what"][e["what"]] += 1
            rep["src"][e["src"]] += 1
        for e, notes in compare(fx):
            rep["differ"].append((it["id"], it["name"] + (" [Classic text]" if it.get("est") == "classic" else ""), e, notes))
    return rep


# --- estimates, as the site computes them (for the report) --------------------------------------------------------

def proc_dps(it, speed=None):
    """(damage per second, unknown-chance damage entries) for hit procs at the given weapon speed."""
    sp = speed or it.get("speed") or 2.0
    dps, unknown = 0.0, []
    for e in it.get("fx") or []:
        if e["k"] != "hit" or e["what"] not in ("damage", "dot") or e.get("only"):
            continue
        ch = e.get("p") if e.get("p") is not None else (e["ppm"] * sp / 60.0 if e.get("ppm") else None)
        if ch is None:
            unknown.append(e)
            continue
        dps += ch * e["v"] / sp
    return dps, unknown


def fill_tokens(items, c):
    """Effect lines that still carry raw game tokens ("$18798s2", "$@spelldesc1226001"), filled by tools/spelltext.py.
    A token without a spell id is filled only when every spell of the item gives the same text. Returns the count."""
    if not client_sentence("0") and not _ST:
        return 0
    st, n = _ST[0], 0
    for it in items:
        eff = it.get("effects") or []
        if not any("$" in e for e in eff):
            continue
        sids = [ie["SpellID"] for ie in c.ixe.get(str(it["id"]), [])] or ["0"]
        for i, line in enumerate(eff):
            if "$" not in line:
                continue
            if sids == ["0"] and re.search(r"\$(?!@)(?!\d)|\$\{|\$<", line):
                continue  # a token without its spell id, and no spell of the item's own to read it from
            outs = set()
            for sid in sids:
                try:
                    outs.add(st.resolve(line, sid, {"ranges": True}))
                except Exception:
                    outs.add(None)
            if len(outs) == 1 and None not in outs:
                txt = outs.pop()
                if txt and "$" not in txt:
                    eff[i] = txt
                    n += 1
    return n


def run(db, dry=False, verbose=True):
    c = Client()
    filled = fill_tokens(db["items"], c)
    if verbose and filled:
        print("effects: filled game tokens in %d tooltip lines" % filled)
    rep = apply_items(db["items"], c)
    if verbose:
        print("effects: %d items with fx; by k %s; by what %s; by source %s" % (
            rep["items"], dict(rep["k"]), dict(rep["what"]), dict(rep["src"])))
        for iid, name, e, notes in rep["differ"]:
            print("  client and tooltip differ: %s %s (%s %s, spell %s): %s" % (iid, name, e["k"], e["what"], e["sp"], "; ".join(notes)))
    return rep


def write_loot_items(db):
    if not os.path.exists(LOOT_ITEMS):
        return
    by = {str(i["id"]): i for i in db["items"]}
    li = json.load(open(LOOT_ITEMS))
    for it in li["items"]:
        src = by.get(str(it["id"]))
        it.pop("fx", None)
        if src and src.get("fx"):
            it["fx"] = src["fx"]
        if src and any("$" in e for e in it.get("effects") or []) and src.get("effects") and not any("$" in e for e in src["effects"]):
            it["effects"] = src["effects"]  # the lines fill_tokens filled
    with open(LOOT_ITEMS, "w") as f:
        json.dump(li, f, ensure_ascii=False, separators=(",", ":"))


def report(db):
    items = [i for i in db["items"] if i.get("fx")]
    weapons = [i for i in items if i.get("cat") == "weapon" and i.get("speed")]
    ranked = sorted(((proc_dps(i)[0], i) for i in weapons), key=lambda x: -x[0])
    print("\ntop weapons by estimated proc dps at their own speed (known chance only):")
    for d, i in [x for x in ranked if x[0] > 0][:15]:
        hits = [e for e in i["fx"] if e["k"] == "hit" and e["what"] in ("damage", "dot")]
        print("  %6s %-34s %-9s req %-3s spd %-4s %6.2f dps  %s" % (
            i["id"], i["name"][:34], i.get("slot"), i.get("reqLevel", "-"), i["speed"], d,
            ", ".join("%s %s%s p=%s" % (e["what"], e["v"], " " + e.get("s", ""), e.get("p")) for e in hits)))
    unk = [(i, proc_dps(i)[1]) for i in items]
    unk = [(i, u) for i, u in unk if u]
    print("\nchance unknown (damage on hit, the client gives no chance): %d items" % len(unk))
    for i, u in sorted(unk, key=lambda x: -max(e["v"] for e in x[1]))[:40]:
        print("  %6s %-34s %-9s req %-3s spd %-4s %s" % (i["id"], i["name"][:34], i.get("slot"), i.get("reqLevel", "-"),
                                                       i.get("speed", "-"), ", ".join("%s %s %s" % (e["what"], e["v"], e.get("s", "")) for e in u)))


def main():
    dry = "--dry" in sys.argv
    db = json.load(open(DB))
    run(db, dry)
    if "--report" in sys.argv:
        report(db)
    if dry:
        return
    with open(DB, "w") as f:
        json.dump(db, f, ensure_ascii=False, separators=(",", ":"))
    write_loot_items(db)
    print("wrote plan/items-db.json and codex/loot-items.json")


if __name__ == "__main__":
    main()
