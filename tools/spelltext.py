#!/usr/bin/env python3
"""Resolve WoW spell tooltip templates against one Forever client build.

Descriptions in Spell.csv are templates: "$s1", "$d", "${$m1/-1000}.2",
"$/10;s1", "$?a5487[...][...]", "$lpoint:points;", "$1289681d" and so on.
This fills them from the build's own tables (research/wago/<build>/, pulled
by fetch_wago.py). Talent ranks come from the Trait system: a definition's
effect points follow a curve indexed by rank.

    from spelltext import Client
    c = Client("1.60.1.70009")
    c.text(5923)                 # a spell's description
    c.talent_text(5923, rank=3)  # a talent's description at rank 3

Checked by tools/verify_spelltext.py, which resolves the previous build and
compares against the text already on the site; a talent's new text is only
trusted where its old text reproduces exactly.
"""
import csv, math, os, re

csv.field_size_limit(1 << 30)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _rows(build, table):
    path = os.path.join(ROOT, "research", "wago", build, table + ".csv")
    if not os.path.exists(path):
        return []
    with open(path, newline="", encoding="utf-8") as f:
        r = csv.reader(f)
        cols = next(r)
        if any(c.startswith("Field_") for c in cols):
            import diff_builds  # borrows names from another build of the same table
            cols = diff_builds.named_header(table, len(cols)) or cols
        return [dict(zip(cols, v)) for v in r]


def _num(v, default=0.0):
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def fmt(v, decimals=None):
    if decimals is not None:
        return ("%." + str(decimals) + "f") % v
    v = abs(v)
    if abs(v - round(v)) < 1e-6:
        return str(int(round(v)))
    return ("%.2f" % v).rstrip("0").rstrip(".")


def fmt_duration(ms):
    ms = abs(ms)
    if ms >= 3600000 and ms % 3600000 == 0:
        h = int(ms // 3600000)
        return "%d hour%s" % (h, "" if h == 1 else "s") if h < 24 else "%d days" % (h // 24)
    if ms >= 60000 and ms % 60000 == 0:
        return "%d min" % (ms // 60000)
    if ms >= 60000:
        return fmt(ms / 60000.0) + " min"
    return fmt(ms / 1000.0) + " sec"


class Client:
    def __init__(self, build):
        self.build = build
        self.name = {r["ID"]: r["Name_lang"] for r in _rows(build, "SpellName")}
        self.spell = {r["ID"]: r for r in _rows(build, "Spell")}
        self.eff = {}
        for r in _rows(build, "SpellEffect"):
            if r.get("DifficultyID", "0") not in ("0", ""):
                continue
            self.eff.setdefault(r["SpellID"], {})[int(r["EffectIndex"])] = r
        self.misc = {}
        for r in _rows(build, "SpellMisc"):
            if r.get("DifficultyID", "0") in ("0", ""):
                self.misc[r["SpellID"]] = r
        self.aura = {}
        for r in _rows(build, "SpellAuraOptions"):
            if r.get("DifficultyID", "0") in ("0", ""):
                self.aura[r["SpellID"]] = r
        self.targets = {r["SpellID"]: r for r in _rows(build, "SpellTargetRestrictions")}
        self.duration = {r["ID"]: r for r in _rows(build, "SpellDuration")}
        self.radius = {r["ID"]: r for r in _rows(build, "SpellRadius")}
        self.range = {r["ID"]: r for r in _rows(build, "SpellRange")}
        self.cast = {r["ID"]: r for r in _rows(build, "SpellCastTimes")}
        self.curve = {}
        for r in _rows(build, "CurvePoint"):
            self.curve.setdefault(r["CurveID"], []).append((_num(r["Pos_0"]), _num(r["Pos_1"]), int(r["OrderIndex"] or 0)))
        for k in self.curve:
            self.curve[k].sort(key=lambda p: (p[0], p[2]))
        self.defs_by_spell = {}
        for r in _rows(build, "TraitDefinition"):
            self.defs_by_spell.setdefault(r["SpellID"], []).append(r["ID"])
        self.def_points = {}
        for r in _rows(build, "TraitDefinitionEffectPoints"):
            self.def_points.setdefault(r["TraitDefinitionID"], {})[int(r["EffectIndex"])] = (r["OperationType"], r["CurveID"])
        # a definition is live when its entry hangs on an actual tree node;
        # builds keep orphaned entries around (Bloodthrill had two in 69876)
        on_node = {r["TraitNodeEntryID"] for r in _rows(build, "TraitNodeXTraitNodeEntry")}
        self.live_defs = {r["TraitDefinitionID"] for r in _rows(build, "TraitNodeEntry") if r["ID"] in on_node}
        dv = {r["ID"]: r["Variables"] for r in _rows(build, "SpellDescriptionVariables")}
        self.desc_vars = {}
        for r in _rows(build, "SpellXDescriptionVariables"):
            self.desc_vars[r["SpellID"]] = dv.get(r["SpellDescriptionVariablesID"], "")

    # ---- numbers --------------------------------------------------------
    def curve_at(self, cid, x):
        pts = self.curve.get(cid) or []
        if not pts:
            return None
        if x <= pts[0][0]:
            return pts[0][1]
        for (x0, y0, _), (x1, y1, _) in zip(pts, pts[1:]):
            if x0 <= x <= x1:
                return y0 if x1 == x0 else y0 + (y1 - y0) * (x - x0) / (x1 - x0)
        return pts[-1][1]

    def talent_def(self, spell):
        defs = self.defs_by_spell.get(str(spell), [])
        live = [d for d in defs if d in self.live_defs]
        return (live or defs or [None])[0]

    def points(self, spell, idx, ctx):
        """Effect idx (0-based) base points; a talent rank in ctx overrides via its curve."""
        spell = str(spell)
        e = self.eff.get(spell, {}).get(idx)
        base = _num(e["EffectBasePointsF"]) if e else 0.0
        if ctx.get("rank") and str(ctx.get("root")) == spell:
            d = self.talent_def(spell)
            pts = self.def_points.get(d, {}).get(idx)
            if pts:
                v = self.curve_at(pts[1], ctx["rank"])
                if v is not None:
                    return v
            # no curve on a multi-rank node: each rank adds the base again
            if ctx.get("maxrank", 1) > 1:
                return base * ctx["rank"]
        return base

    def dur_ms(self, spell):
        m = self.misc.get(str(spell))
        d = self.duration.get(m["DurationIndex"]) if m else None
        return _num(d["Duration"]) if d else 0.0

    def var(self, spell, letter, idx, ctx):
        spell = str(spell)
        i = (idx or 1) - 1
        e = self.eff.get(spell, {}).get(i)
        L = letter
        if L in ("s", "m", "M", "w", "W", "b", "S"):
            return self.points(spell, i, ctx)
        if L == "o":
            amp = _num(e["EffectAuraPeriod"]) if e else 0
            ticks = self.dur_ms(spell) / amp if amp else 1
            return self.points(spell, i, ctx) * ticks
        if L == "t":
            return (_num(e["EffectAuraPeriod"]) if e else 0) / 1000.0
        if L in ("a", "A"):
            if not e:
                return 0.0
            r = self.radius.get(e["EffectRadiusIndex_0"]) or self.radius.get(e["EffectRadiusIndex_1"])
            return _num(r["Radius"]) if r else 0.0
        if L == "x":
            return _num(e["EffectChainTargets"]) if e else 0.0
        if L == "e":
            return _num(e["EffectAmplitude"]) if e else 0.0
        if L == "q":
            return _num(e["EffectMiscValue_0"]) if e else 0.0
        if L == "h":
            return _num((self.aura.get(spell) or {}).get("ProcChance"))
        if L == "n":
            return _num((self.aura.get(spell) or {}).get("ProcCharges"))
        if L == "u":
            return _num((self.aura.get(spell) or {}).get("CumulativeAura"))
        if L == "i":
            return _num((self.targets.get(spell) or {}).get("MaxTargets"))
        if L in ("r", "R"):
            m = self.misc.get(spell)
            rg = self.range.get(m["RangeIndex"]) if m else None
            return _num(rg["RangeMax_0"]) if rg else 0.0
        if L in ("d", "D"):
            return self.dur_ms(spell)
        return None

    # ---- text -------------------------------------------------------------
    VAR = re.compile(r"\$(\d*)([a-zA-Z])(\d?)")

    def _value_expr(self, expr, spell, ctx):
        def sub(m):
            sid = m.group(1) or spell
            v = self.var(sid, m.group(2), int(m.group(3) or 0) or None, ctx)
            if v is None:
                raise ValueError("unknown var $" + m.group(0))
            if m.group(2) in ("d", "D"):
                v = v / 1000.0
            return "(" + repr(v) + ")"
        e = re.sub(r"\$(max|min|floor|ceil|abs|gt|lt|ge|le|cond)\(", r"\1(", expr)
        # character stats read as zero (the site shows no particular character);
        # player level reads as the level in ctx, or 60
        e = re.sub(r"\$(PL|pl)\b", str(ctx.get("level", 60)), e)
        e = e.replace("$proccooldown", repr(_num((self.aura.get(str(spell)) or {}).get("ProcCategoryRecovery")) / 1000.0))
        e = re.sub(r"\$(SPI|SPS|SPH|SPN|SPF|SPA|SPFR|SP|RAP|AP|STR|AGI|INT|STA|MHP|mhp|MWS|mws|MWB|mwb|mw|MW|PI)\b", "0", e)
        e = e.replace("PI", str(math.pi))
        e = self.VAR.sub(sub, e)
        if re.search(r"[^0-9eE.+\-*/(), <>=a-z]", e):
            raise ValueError("unsafe expr " + e)
        env = {"max": max, "min": min, "floor": math.floor, "ceil": math.ceil, "abs": abs,
               "gt": lambda a, b: a > b, "lt": lambda a, b: a < b, "ge": lambda a, b: a >= b, "le": lambda a, b: a <= b,
               "cond": lambda c, a, b: a if c else b, "__builtins__": {}}
        return eval(e, env)

    def _bracket(self, s, i):
        """s[i] == '['; return index after the matching ']'."""
        depth = 0
        for j in range(i, len(s)):
            if s[j] == "[":
                depth += 1
            elif s[j] == "]":
                depth -= 1
                if depth == 0:
                    return j + 1
        return len(s)

    def _conditionals(self, s):
        # $?cond[yes][no]: the site shows the reader with no special auras or spells, so "no".
        while True:
            m = re.search(r"\$\?[^\[]*\[", s)
            if not m:
                return s
            a0 = m.end() - 1
            a1 = self._bracket(s, a0)
            if a1 < len(s) and s[a1] == "[":
                b1 = self._bracket(s, a1)
                pick = s[a1 + 1:b1 - 1]
                s = s[:m.start()] + pick + s[b1:]
            else:
                s = s[:m.start()] + s[a1:]

    def resolve(self, template, spell, ctx=None, depth=0):
        ctx = dict(ctx or {})
        ctx.setdefault("root", str(spell))
        s = template or ""
        s = self._conditionals(s)
        # colored "Requires <form>" preambles are UI state, not tooltip text
        s = re.sub(r"\|C[Ff]{2}[0-9A-Fa-f]{6}Re(?:q?u)?ires [^|]*\|R\s*", "", s)
        s = re.sub(r"\|c[0-9A-Fa-f]{8}|\|[rR]|\|C[0-9A-Fa-f]{8}", "", s)
        s = s.replace("|n", "\n")
        # description variables ($<name>)
        dvars = {}
        for line in (self.desc_vars.get(str(spell)) or "").splitlines():
            m = re.match(r"\s*\$(\w+)\s*=\s*(.+)", line)
            if m:
                dvars[m.group(1)] = m.group(2).strip()
        out, i = [], 0
        while i < len(s):
            c = s[i]
            if c != "$":
                out.append(c)
                i += 1
                continue
            rest = s[i:]
            m = re.match(r"\$\{(.*?)\}(?:\.(\d))?", rest)
            if m:
                v = self._value_expr(m.group(1), str(spell), ctx)
                out.append(fmt(abs(v), int(m.group(2))) if m.group(2) else fmt(v))
                i += m.end()
                continue
            m = re.match(r"\$<(\w+)>", rest)
            if m:
                expr = dvars.get(m.group(1))
                if expr is None:
                    raise ValueError("no desc var " + m.group(1))
                expr = re.sub(r"\$<(\w+)>", lambda mm: "(" + dvars.get(mm.group(1), "0") + ")", expr)
                out.append(fmt(self._value_expr(expr, str(spell), ctx)))
                i += m.end()
                continue
            m = re.match(r"\$([/*])(\d+(?:\.\d+)?);(\d*)([a-zA-Z])(\d?)", rest)
            if m:
                v = self.var(m.group(3) or spell, m.group(4), int(m.group(5) or 0) or None, ctx)
                if v is None:
                    raise ValueError("unknown var in " + m.group(0))
                n = float(m.group(2))
                out.append(fmt(v / n if m.group(1) == "/" else v * n))
                i += m.end()
                continue
            m = re.match(r"\$[lL]([^:;]*):([^;]*);", rest)
            if m:
                prev = re.findall(r"(\d+(?:\.\d+)?)", "".join(out))
                one = prev and abs(float(prev[-1]) - 1) < 1e-9
                out.append(m.group(1) if one else m.group(2))
                i += m.end()
                continue
            m = re.match(r"\$[gG]([^:;]*):([^;]*);", rest)
            if m:
                out.append(m.group(1))
                i += m.end()
                continue
            m = re.match(r"\$@(spelldesc|spellname|spellaura)(\d+)", rest)
            if m:
                sid = m.group(2)
                if m.group(1) == "spellname":
                    out.append(self.name.get(sid, ""))
                elif depth < 3:
                    col = "Description_lang" if m.group(1) == "spelldesc" else "AuraDescription_lang"
                    out.append(self.resolve((self.spell.get(sid) or {}).get(col, ""), sid, {}, depth + 1))
                i += m.end()
                continue
            m = self.VAR.match(rest)
            if m:
                sid = m.group(1) or str(spell)
                v = self.var(sid, m.group(2), int(m.group(3) or 0) or None, ctx)
                if v is None:
                    raise ValueError("unknown var " + m.group(0))
                out.append(fmt_duration(v) if m.group(2) in ("d", "D") else fmt(v))
                i += m.end()
                continue
            out.append(c)
            i += 1
        text = "".join(out)
        text = re.sub(r"[ \t]+", " ", text)
        text = re.sub(r"\s*\n\s*", " ", text).strip()
        return text

    def text(self, spell, col="Description_lang"):
        return self.resolve((self.spell.get(str(spell)) or {}).get(col, ""), spell)

    def talent_text(self, spell, rank, maxrank=1, col="Description_lang"):
        return self.resolve((self.spell.get(str(spell)) or {}).get(col, ""), spell,
                            {"rank": rank, "maxrank": maxrank, "root": str(spell)})
