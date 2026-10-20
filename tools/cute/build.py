#!/usr/bin/env python3
"""Build and check the Cute page, so nothing on it can go stale.

  python3 tools/cute/build.py [--no-zip] [--online]

In order: write the seed (Cute/Known.lua, gen_known.py) and run its selftest (the build stops when either fails), write
Cute/Changes.lua from the page's changelog (the build stops when the toc's version has no entry), copy QuestBank's
engine into Cute_Quest (build_quest: the only writer of that folder but its own nine files), zip both folders the
way the owner does (skipped with --no-zip or when a folder is missing), regenerate
addons/cute/stats.js from the registry (luajit page_stats.lua), stamp the version (Cute.toc), the zip size (KB) and
the stat counts into addons/cute/index.html between <!--@name--> ... <!--/@name--> markers, then check the page:
  - every local href/src exists beside the page; every site-absolute path exists under the repo
  - every class the page's own style defines starts with cu- and none appears in forever.css; every class the markup
    uses is defined somewhere (the page's style or forever.css, for the nav)
  - no version number, TODO or placeholder outside the markers and the changelog labels; no middle dots or arrows in
    the body text
  - the changelog's newest entry is the toc's version
  - the page's greys pass 4.5:1 on every surface they sit on
  - the Download button is black text on a white button through the whole cascade (forever.css included), at rest
    and on hover
  --online also fetches every external link (needs the network).
Prints each check; exits 1 with the problems when any fails. Python 3 standard library only."""
import html as htmlmod, os, re, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ADDON = os.path.join(HERE, "Cute")
TOC = os.path.join(ADDON, "Cute.toc")
PAGE_DIR = os.path.join(ROOT, "addons", "cute")
PAGE = os.path.join(PAGE_DIR, "index.html")
ZIP = os.path.join(PAGE_DIR, "Cute.zip")
STATS = os.path.join(PAGE_DIR, "stats.js")
CHANGES = os.path.join(ADDON, "Changes.lua")
SITE_CSS = os.path.join(ROOT, "forever.css")
QB_DIR = os.path.join(ROOT, "tools", "questbank", "QuestBank")
QB_TOC = os.path.join(QB_DIR, "QuestBank.toc")
QUEST = os.path.join(HERE, "Cute_Quest")
QUEST_TOC = os.path.join(QUEST, "Cute_Quest.toc")
# QuestBank's engine, as Cute_Quest carries it: every file QuestBank.toc may list. UI.lua (the window) is never copied;
# a file not here stops the build until it has been checked in Cute's harness
ENGINE_KNOWN = {
    "Data.lua", "Core.lua", "Lists.lua", "Discover.lua", "Survey.lua", "Game.lua", "Loot.lua", "Observe.lua", "Timer.lua",
    "Link.lua", "MinimapTiles.lua", "MinimapView.lua", "MinimapRoute.lua", "Minimap.lua", "DungeonMap.lua", "Glow.lua",
    "Walk.lua", "Camp.lua", "Model.lua", "Legacy.lua", "Travel.lua", "Pins.lua", "QuestMap.lua", "Pins.xml", "Arrow.lua",
    "Target.lua", "Sync.lua", "Auto.lua", "Guide.lua", "MapPage.lua", "Gear.lua", "StepFrame.lua", "Tips.lua",
}
# Cute_Quest's own files, in the toc's order after the engine
OWN = ["Bridge.lua", "Band.lua", "PageQuests.lua", "PageRoute.lua", "PageMap.lua", "PageJournal.lua", "PageGear.lua", "PageCamp.lua"]

problems = []


def problem(s):
    problems.append(s)


def ok(s):
    print("  ok   " + s)


# ---------------------------------------------------------------- build steps
def toc_version():
    m = re.search(r"^## Version:\s*(\S+)", open(TOC, encoding="utf-8").read(), re.M)
    if not m:
        sys.exit("Cute.toc has no ## Version line")
    return m.group(1)


def build_known():
    gen = os.path.join(HERE, "gen_known.py")
    r = subprocess.run([sys.executable, gen], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("gen_known.py failed:\n" + r.stdout + r.stderr)
    ok(r.stdout.strip().splitlines()[-1])
    # the seed's own checks (the joins, the neck in and the head, shoulder and legs out, the XP against players'
    # readings, the file loading in LuaJIT) stop the build too
    t = subprocess.run([sys.executable, gen, "--selftest"], capture_output=True, text=True)
    out = t.stdout + t.stderr
    if t.returncode != 0:
        sys.exit("gen_known.py --selftest failed:\n" + (out[out.find("problems:"):] if "problems:" in out else out))
    ok("the seed's selftest: problems 0")


def lua_str(s):
    """a Lua string literal in ASCII (gen_known.py's): the game's font draws any other byte in a source file as a box,
    so UTF-8 travels as three-digit decimal escapes"""
    out = []
    for b in s.encode("utf-8"):
        if b in (0x22, 0x5C):
            out.append("\\" + chr(b))
        elif 32 <= b < 127:
            out.append(chr(b))
        else:
            out.append("\\%03d" % b)
    return '"' + "".join(out) + '"'


def changelog(html):
    """[(version, text)] from the page's changelog, newest first: each <li><b>X.Y.Z</b>...</li>, its markup taken out,
    its entities read, its white space one space"""
    out = []
    for v, body in re.findall(r"<li><b>(\d+\.\d+\.\d+)</b>(.*?)</li>", html, re.S):
        out.append((v, " ".join(htmlmod.unescape(re.sub(r"<[^>]+>", "", body)).split())))
    return out


def build_changes(version):
    """Cute/Changes.lua, C.CHANGES = { ["0.5.0"] = "...", ... }: the page's changelog lines, which the addon prints
    once at the first login on a new version, so the game and the page say the same. Written only when a line changed;
    the build stops when the toc's version has no entry (or an empty one), or one is there twice"""
    entries = changelog(open(PAGE, encoding="utf-8").read())
    seen = set()
    for v, text in entries:
        if v in seen:
            sys.exit("the page's changelog names %s twice" % v)
        seen.add(v)
    if not dict(entries).get(version):
        sys.exit("the page's changelog has no entry for %s, the toc's version: add its <li><b>%s</b>...</li> line" % (version, version))
    lines = ["-- Generated by tools/cute/build.py from the changelog of addons/cute/index.html; edit the page, not this file.",
             "-- One line per version, newest first: Core.lua prints this version's at the first login on it.",
             "local _, C = ...",
             "C.CHANGES = {"]
    for v, text in entries:
        lines.append('  ["%s"] = %s,' % (v, lua_str(text)))
    lines.append("}")
    src = "\n".join(lines) + "\n"
    old = open(CHANGES, encoding="ascii").read() if os.path.isfile(CHANGES) else None
    if old != src:
        open(CHANGES, "w", encoding="ascii", newline="\n").write(src)
    ok("Changes.lua: %d changelog lines, %s's there (%s)" % (len(entries), version, "written" if old != src else "unchanged"))


def qb_version():
    m = re.search(r"^## Version:\s*(\S+)", open(QB_TOC, encoding="utf-8").read(), re.M)
    return m.group(1) if m else "?"


def build_quest(version):
    """Cute_Quest: QuestBank's engine files copied byte for byte (UI.lua left out), its art, and the toc this writes.
    Stops on a file QuestBank.toc lists that ENGINE_KNOWN does not, a copy that differs from its source after writing,
    a copied Lua file without its dormant guard, or a stray file in the folder"""
    listed = [l.strip() for l in open(QB_TOC, encoding="utf-8").read().splitlines() if re.match(r"^[\w]+\.(lua|xml)$", l.strip())]
    unknown = [f for f in listed if f not in ENGINE_KNOWN and f != "UI.lua"]
    if unknown:
        sys.exit("QuestBank.toc lists files build.py does not know: %s. Check each in Cute's harness, then add it to ENGINE_KNOWN." % ", ".join(unknown))
    engine = [f for f in listed if f != "UI.lua"]
    os.makedirs(os.path.join(QUEST, "art"), exist_ok=True)
    pairs = [(os.path.join(QB_DIR, f), os.path.join(QUEST, f)) for f in engine]
    for name in sorted(os.listdir(os.path.join(QB_DIR, "art"))):
        if not name.startswith("."):
            pairs.append((os.path.join(QB_DIR, "art", name), os.path.join(QUEST, "art", name)))
    written = 0
    for src, dst in pairs:
        data = open(src, "rb").read()
        if not os.path.isfile(dst) or open(dst, "rb").read() != data:
            shutil.copyfile(src, dst)
            written += 1
        if open(dst, "rb").read() != data:
            problem("Cute_Quest/%s differs from its source after the copy" % os.path.relpath(dst, QUEST))
    for f in engine:
        if f.endswith(".lua"):
            src = open(os.path.join(QUEST, f), encoding="ascii", errors="replace").read()
            if not re.search(r"^local \w+, QB = \.\.\.\nif QB\.dormant then return end\n", src, re.M):
                problem("Cute_Quest/%s has no `if QB.dormant then return end` after its vararg line" % f)
    own = {"Shim.lua"} | set(OWN)
    for name in sorted(os.listdir(QUEST)):
        if name.endswith((".lua", ".xml")) and name not in engine and name not in own:
            problem("Cute_Quest/%s is neither QuestBank's nor one of Cute_Quest's own files: remove it" % name)
    for name in sorted(own):
        if not os.path.isfile(os.path.join(QUEST, name)):
            problem("Cute_Quest/%s is missing" % name)
    toc = "\n".join([
        "## Interface: 16001",
        "## Title: |cffe8b24aCute|r Quest",
        "## Notes: QuestBank's guiding as Cute modules: the step now in the Guide, and Quests, Route, Map, Journal, Gear and Camp, each a switch in Settings, Modules. Loads only while one is on.",
        "## Author: Mikal",
        "## Version: %s" % version,
        "## X-License: GPL-3.0-or-later",
        "## X-QuestBank: %s" % qb_version(),
        "## Dependencies: Cute",
        "## LoadOnDemand: 1",
        "## X-Cute-Module: 1",
        "## X-Cute-Title: Quests",
        "## SavedVariables: CuteQuestDB",
        "",
        "Shim.lua",
    ] + engine + OWN) + "\n"
    old = open(QUEST_TOC, encoding="ascii").read() if os.path.isfile(QUEST_TOC) else None
    if old != toc:
        open(QUEST_TOC, "w", encoding="ascii", newline="\n").write(toc)
    ok("Cute_Quest: %d engine files from QuestBank %s (%d written), toc %s" % (len(engine), qb_version(), written, "written" if old != toc else "unchanged"))


def build_zip():
    if "--no-zip" in sys.argv:
        print("  skip zip (--no-zip)")
        return
    if not (os.path.isdir(ADDON) and os.path.isdir(QUEST)):
        print("  skip zip (no Cute or Cute_Quest folder)")
        return
    if os.path.exists(ZIP):
        os.remove(ZIP)
    subprocess.run(["zip", "-rq", ZIP, "Cute", "Cute_Quest", "-x", "*.DS_Store"], cwd=HERE, check=True)
    ok("Cute.zip built, %d bytes (Cute and Cute_Quest)" % os.path.getsize(ZIP))


def build_stats():
    r = subprocess.run(["luajit", os.path.join(HERE, "page_stats.lua")], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("page_stats.lua failed:\n" + r.stdout + r.stderr)
    ok(r.stdout.strip())
    js = open(STATS, encoding="utf-8").read()
    cats = re.findall(r'^\s*\{ id: "[^"]+",.*?", cat: "([^"]+)"', js, re.M)
    if not cats:
        sys.exit("stats.js has no stats")
    # the mock's Rules section and its enchant voices read these, Rules.lua's and Stats.lua's own
    for name in ("CUTE_TUNE", "CUTE_RULES", "CUTE_VOICES"):
        if "window.%s = " % name not in js:
            sys.exit("stats.js has no window.%s (page_stats.lua writes it)" % name)
    counts = {"n": len(cats)}
    for c in cats:
        counts["n:" + c] = counts.get("n:" + c, 0) + 1
    return counts


def stamp(html, values):
    def one(m):
        name = m.group(1)
        if name not in values:
            problem("marker <!--@%s--> has no value to stamp" % name)
            return m.group(0)
        return "<!--@%s-->%s<!--/@%s-->" % (name, values[name], name)
    out, n = re.subn(r"<!--@([\w:]+)-->(.*?)<!--/@\1-->", one, html, flags=re.S)
    for name in ("v", "kb", "n"):
        if not re.search(r"<!--@%s-->" % re.escape(name), html):
            problem("the page has no <!--@%s--> marker" % name)
    return out, n


# ---------------------------------------------------------------- CSS, enough of it for the checks
def strip_comments(css):
    return re.sub(r"/\*.*?\*/", "", css, flags=re.S)


def rules_of(css):
    """[(selector, {prop: value}, order)] over the whole sheet, @media blocks flattened (their rules count as
    applying: the cascade check is conservative), other at-rules dropped"""
    css = strip_comments(css)
    out = []
    i, n, order = 0, len(css), 0
    while i < n:
        j = css.find("{", i)
        if j < 0:
            break
        sel = css[i:j].strip()
        if sel.startswith("@"):
            if sel.startswith("@media") or sel.startswith("@supports"):
                depth, k = 1, j + 1
                while k < n and depth:
                    depth += {"{": 1, "}": -1}.get(css[k], 0)
                    k += 1
                for s, d, _ in rules_of(css[j + 1:k - 1]):
                    out.append((s, d, order))
                    order += 1
                i = k
                continue
            k = css.find("}", j)
            i = k + 1
            continue
        k = css.find("}", j)
        body = css[j + 1:k]
        decls = {}
        for part in body.split(";"):
            if ":" in part:
                p, v = part.split(":", 1)
                decls[p.strip().lower()] = v.strip()
        for s in sel.split(","):
            s = s.strip()
            if s:
                out.append((s, decls, order))
                order += 1
        i = k + 1
    return out


def classes_in_selectors(rules):
    s = set()
    for sel, _, _ in rules:
        s.update(re.findall(r"\.(-?[_a-zA-Z][\w-]*)", sel))
    return s


def parse_compound(c):
    """one compound selector -> (tag, classes, id, attrs[(name, value|None)], pseudos[str], nots[compound])"""
    tag, classes, cid, attrs, pseudos, nots = None, [], None, [], [], []
    i = 0
    while i < len(c):
        ch = c[i]
        if ch == ".":
            m = re.match(r"\.(-?[_a-zA-Z][\w-]*)", c[i:]); classes.append(m.group(1)); i += m.end()
        elif ch == "#":
            m = re.match(r"#([\w-]+)", c[i:]); cid = m.group(1); i += m.end()
        elif ch == "[":
            m = re.match(r"\[\s*([\w-]+)\s*(?:([~|^$*]?=)\s*(\"[^\"]*\"|'[^']*'|[^\]\s]+))?\s*\]", c[i:])
            attrs.append((m.group(1), m.group(3).strip("\"'") if m.group(3) else None, m.group(2))); i += m.end()
        elif ch == ":":
            if c.startswith(":not(", i):
                depth, k = 1, i + 5
                while k < len(c) and depth:
                    depth += {"(": 1, ")": -1}.get(c[k], 0); k += 1
                nots.append(parse_compound(c[i + 5:k - 1].strip())); i = k
            else:
                m = re.match(r"::?[\w-]+(\([^)]*\))?", c[i:]); pseudos.append(m.group(0)); i += m.end()
        else:
            m = re.match(r"[\w*-]+", c[i:])
            if not m:
                raise ValueError("selector: " + c)
            tag = m.group(0); i += m.end()
    return (tag, classes, cid, attrs, pseudos, nots)


def specificity(sel):
    a = b = c = 0
    for comp in re.split(r"\s*[>+~]\s*|\s+", sel.strip()):
        if not comp:
            continue
        tag, classes, cid, attrs, pseudos, nots = parse_compound(comp)
        if cid: a += 1
        b += len(classes) + len(attrs) + len([p for p in pseudos if not p.startswith("::") and p not in (":root",)])
        if ":root" in pseudos: b += 1
        if tag and tag != "*": c += 1
        for nt in nots:
            sa, sb, sc = specificity_compound(nt); a += sa; b += sb; c += sc
    return (a, b, c)


def specificity_compound(parsed):
    tag, classes, cid, attrs, pseudos, nots = parsed
    return (1 if cid else 0, len(classes) + len(attrs) + len(pseudos), 1 if tag and tag != "*" else 0)


def match_compound(parsed, el, state):
    tag, classes, cid, attrs, pseudos, nots = parsed
    if tag and tag != "*" and tag.lower() != el["tag"]:
        return False
    if cid and el.get("id") != cid:
        return False
    for c in classes:
        if c not in el["classes"]:
            return False
    for name, val, op in attrs:
        if name == "class":
            have = " ".join(el["classes"]) if el["classes"] else None
        else:
            have = el.get("attrs", {}).get(name)
        if have is None:
            return False
        if val is not None and op == "=" and have != val:
            return False
    for p in pseudos:
        if p == ":root":
            if el["tag"] != "html": return False
        elif p == ":hover":
            if not (state.get("hover") and el.get("target")): return False
        elif p == ":focus-visible":
            if not (state.get("focus") and el.get("target")): return False
        elif p in (":first-child", ":last-child"):
            if not el.get(p[1:]): return False
        else:
            return False  # a state this element is not in (:checked, :disabled, ::after ...)
    for nt in nots:
        if match_compound(nt, el, state):
            return False
    return True


def match_selector(sel, path, state):
    """right-to-left over ' ' and '>' combinators; path is root..target"""
    parts = re.split(r"(\s*>\s*|\s+)", sel.strip())
    comps, combs = [], []
    for p in parts:
        if not p or p.isspace():
            continue
        if ">" in p and not re.search(r"[\w.#\[:*]", p):
            combs.append(">")
        elif p.isspace():
            combs.append(" ")
        else:
            comps.append(parse_compound(p))
            if len(comps) > len(combs) + 1:
                return False
    if len(combs) != len(comps) - 1:
        combs = [" "] * (len(comps) - 1)  # whitespace tokens were swallowed by the split: descendants
    i = len(path) - 1
    if not match_compound(comps[-1], path[i], state):
        return False
    ci = len(comps) - 2
    while ci >= 0:
        comb = combs[ci]
        i -= 1
        if comb == ">":
            if i < 0 or not match_compound(comps[ci], path[i], state):
                return False
        else:
            while i >= 0 and not match_compound(comps[ci], path[i], state):
                i -= 1
            if i < 0:
                return False
        ci -= 1
    return True


def winning(prop_names, rules, path, state, tokens):
    best = None
    for sel, decls, order in rules:
        val = None
        for p in prop_names:
            if p in decls:
                val = decls[p]
        if val is None:
            continue
        try:
            if not match_selector(sel, path, state):
                continue
            key = (specificity(sel), order)
        except ValueError:
            continue
        if best is None or key > best[0]:
            best = (key, val, sel)
    return best


def resolve_color(val, tokens):
    val = val.strip()
    m = re.match(r"var\((--[\w-]+)\)", val)
    if m:
        val = tokens.get(m.group(1), "").strip()
    if val in ("white",): return (255, 255, 255)
    if val in ("black",): return (0, 0, 0)
    m = re.match(r"#([0-9a-fA-F]{3,8})$", val)
    if m:
        h = m.group(1)
        if len(h) in (3, 4): h = "".join(ch * 2 for ch in h[:3])
        return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    m = re.match(r"rgba?\(\s*(\d+)\D+(\d+)\D+(\d+)", val)
    if m:
        return tuple(int(x) for x in m.groups())
    m = re.match(r"(#[0-9a-fA-F]{3,8}|rgba?\([^)]*\))", val)  # a background shorthand: its colour part
    if m and m.group(1) != val:
        return resolve_color(m.group(1), tokens)
    return None


def luminance(rgb):
    def ch(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = rgb
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def tokens_of(rules):
    t = {}
    for sel, decls, _ in rules:
        if sel == ":root":
            for k, v in decls.items():
                if k.startswith("--"):
                    t[k] = v
    return t


# ---------------------------------------------------------------- checks
def check_links(html):
    bad = []
    for attr, url in re.findall(r"\b(href|src)=\"([^\"]+)\"", html):
        if url.startswith(("http://", "https://", "mailto:", "#", "data:")):
            continue
        path = url.split("#")[0].split("?")[0]
        if not path:
            continue
        if path.startswith("/"):
            f = os.path.join(ROOT, path.lstrip("/"))
        else:
            f = os.path.join(PAGE_DIR, path)
        if os.path.isdir(f):
            f = os.path.join(f, "index.html")
        if not os.path.isfile(f):
            bad.append(url)
    if bad:
        problem("links to missing files: " + ", ".join(sorted(set(bad))))
    else:
        ok("every local link and image exists")


def check_online(html):
    if "--online" not in sys.argv:
        print("  skip external links (--online fetches them)")
        return
    import urllib.request
    bad = []
    # preconnect and dns-prefetch hints name an origin, not a page: nothing to fetch there
    hints = set(re.findall(r"<link[^>]*rel=\"(?:preconnect|dns-prefetch)\"[^>]*href=\"([^\"]+)\"", html))
    for url in sorted(set(re.findall(r"\b(?:href|src)=\"(https?://[^\"]+)\"", html)) - hints):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (cute build check)"})
            with urllib.request.urlopen(req, timeout=15) as r:
                if r.status >= 400:
                    bad.append("%s (%d)" % (url, r.status))
        except Exception as e:  # noqa: BLE001 - any failure is a dead link for a reader
            bad.append("%s (%s)" % (url, e))
    if bad:
        problem("external links that do not answer: " + "; ".join(bad))
    else:
        ok("every external link answers")


def page_style(html):
    m = re.search(r"<style>(.*?)</style>", html, re.S)
    return m.group(1) if m else ""


def check_classes(html, page_rules, site_rules):
    defined = classes_in_selectors(page_rules)
    site = classes_in_selectors(site_rules)
    off = sorted(c for c in defined if not c.startswith("cu-"))
    if off:
        problem("classes the page defines without the cu- prefix: " + ", ".join(off))
    clash = sorted(defined & site)
    if clash:
        problem("classes defined both here and in forever.css: " + ", ".join(clash))
    # every selector the page writes names a cu- class, or is the root (the one html rule respects reduced motion)
    loose = sorted(set(sel for sel, _, _ in page_rules if ".cu-" not in sel and sel not in (":root", "html")))
    if loose:
        problem("selectors in the page's style that reach past cu-: " + ", ".join(loose))
    # classes the markup and the scripts use must be styled somewhere; JS builds class strings too
    used = set()
    for s in re.findall(r"class=\\?\"([^\"\\]*)", html):
        used.update(re.findall(r"-?[_a-zA-Z][\w-]*", s))
    for s in re.findall(r"\bclass(?:Name)?\s*=\s*\"([^\"]*)\"", html):
        used.update(s.split())
    # the pip shades are built as "cu-p" + digit: check the shades, not the prefix
    used.discard("cu-p")
    used.update("cu-p%d" % d for d in range(1, 9))
    known = defined | site
    unknown = sorted(c for c in used if c not in known)
    if unknown:
        problem("classes used but styled nowhere: " + ", ".join(unknown))
    if not off and not clash and not loose and not unknown:
        ok("%d page classes, all cu-, none in forever.css; every class used is styled" % len(defined))


def check_stale(html, version):
    body = re.sub(r"<!--@([\w:]+)-->.*?<!--/@\1-->", "", html, flags=re.S)
    body = re.sub(r"<li><b>\d+\.\d+\.\d+</b>", "<li><b></b>", body)
    body = re.sub(r"<svg\b.*?</svg>", "", body, flags=re.S)  # path data looks like version numbers
    vers = sorted(set(re.findall(r"\b\d+\.\d+\.\d+\b", body)))
    if vers:
        problem("version numbers typed by hand (stamp them or move them to the changelog): " + ", ".join(vers))
    words = [w for w in ("TODO", "FIXME", "lorem", "n/a", "XXX") if w in body]
    if words:
        problem("placeholders left in the page: " + ", ".join(words))
    after_head = html.split("</head>", 1)[-1]
    glyphs = [g for g in ("\u00b7", "\u2192") if g in after_head]
    if glyphs:
        problem("middle dots or arrows in the body text: " + " ".join(glyphs))
    logs = re.findall(r"<li><b>(\d+\.\d+\.\d+)</b>", html)
    if not logs:
        problem("the changelog has no entries")
    elif logs[0] != version:
        problem("the changelog's newest entry is %s but Cute.toc says %s: bump the toc or add the entry" % (logs[0], version))
    if not vers and not words and not glyphs and logs and logs[0] == version:
        ok("no stale text; changelog newest = toc = %s" % version)


def check_contrast(page_rules):
    t = tokens_of(page_rules)
    text = ["--cu-ink", "--cu-dim", "--cu-mute"]
    surfaces = ["--cu-black", "--cu-bg", "--cu-panel", "--cu-panel2", "--cu-stage"]
    bad = []
    for fg in text:
        for bg in surfaces:
            a, b = resolve_color(t.get(fg, ""), t), resolve_color(t.get(bg, ""), t)
            if not a or not b:
                bad.append("%s or %s is not a colour" % (fg, bg)); continue
            c = contrast(a, b)
            if c < 4.5:
                bad.append("%s on %s is %.2f:1" % (fg, bg, c))
    # the small print on the white button
    c = contrast((0x44, 0x44, 0x44), resolve_color(t.get("--cu-white", ""), t))
    if c < 4.5:
        bad.append("#444 on the button is %.2f:1" % c)
    # a control's edge (an unticked box, a radio) against the panels it sits on and its own fill: 3:1, a non-text
    # contrast (WCAG 1.4.11). The window's own box (UI.lua's EDGE, 0.42 on 0.07 and 0.11) is the same grey
    edge = resolve_color(t.get("--cu-edge", ""), t)
    if not edge:
        bad.append("--cu-edge is not a colour")
    else:
        for bg in ["--cu-panel", "--cu-panel2"]:
            b = resolve_color(t.get(bg, ""), t)
            c = contrast(edge, b) if b else 0
            if c < 3:
                bad.append("--cu-edge on %s is %.2f:1 (a control's edge needs 3:1)" % (bg, c))
    lua = open(os.path.join(HERE, "Cute", "UI.lua"), encoding="utf-8").read()
    m = re.search(r"^local EDGE = ([\d.]+)", lua, re.M)
    if not m:
        bad.append("UI.lua has no EDGE for the check box")
    else:
        g = round(float(m.group(1)) * 255)
        for fill in (0.07, 0.11):
            f = round(fill * 255)
            c = contrast((g, g, g), (f, f, f))
            if c < 3:
                bad.append("the window's box edge %.2f on %.2f is %.2f:1" % (float(m.group(1)), fill, c))
    # the window's muted text (UI.lua's and Settings.lua's MUTE: "nobody yet", a dash, the notes) on its panels: 4.5:1
    for name in ("UI.lua", "Settings.lua"):
        src = open(os.path.join(HERE, "Cute", name), encoding="utf-8").read()
        m = re.search(r"^local MUTE = \{ ([\d.]+),", src, re.M)
        if not m:
            bad.append("%s has no MUTE" % name); continue
        g = round(float(m.group(1)) * 255)
        for fill in (0.07, 0.11):
            f = round(fill * 255)
            c = contrast((g, g, g), (f, f, f))
            if c < 4.5:
                bad.append("%s's muted text %.2f on %.2f is %.2f:1" % (name, float(m.group(1)), fill, c))
    # a tag ("(suspect)", "offline") on a picked Officers row, whose background is the panel lightened to #2a2a2a
    pk = [d.get("color") for sel, d, _ in page_rules if sel.strip() == ".cu-rows tbody tr.cu-picked .cu-tag"]
    col = resolve_color(pk[0], t) if pk and pk[0] else None
    if not col:
        bad.append("no colour for a tag on a picked row")
    elif contrast(col, (0x2a, 0x2a, 0x2a)) < 4.5:
        bad.append("a tag on a picked row is %.2f:1" % contrast(col, (0x2a, 0x2a, 0x2a)))
    if bad:
        problem("contrast under 4.5:1 (text) or 3:1 (a control's edge): " + "; ".join(bad))
    else:
        ok("greys pass 4.5:1 on black, the window, its panels and the stage, a picked row's tags too, and the window's muted text on its panels; a box's edge 3:1 on the page and in the window")


def check_download_cascade(page_rules, site_rules):
    rules = [(s, d, o) for s, d, o in site_rules] + [(s, d, o + 100000) for s, d, o in page_rules]
    tokens = tokens_of(page_rules)
    tokens.update(tokens_of(site_rules))
    path = [
        {"tag": "html", "classes": []},
        {"tag": "body", "classes": ["cu-page"]},
        {"tag": "main", "classes": []},
        {"tag": "header", "classes": ["cu-hero"]},
        {"tag": "div", "classes": ["cu-hero-text"]},
        {"tag": "div", "classes": ["cu-cta"]},
        {"tag": "a", "classes": ["cu-dl"], "attrs": {"href": "Cute.zip", "class": "cu-dl"}, "target": True},
    ]
    bad = []
    for state in ({}, {"hover": True}, {"focus": True}):
        label = "hover" if state.get("hover") else "focus" if state.get("focus") else "rest"
        # colour inherits down the path; "inherit" and no rule mean the parent's
        color = (0, 0, 0)
        for i in range(len(path)):
            w = winning(["color"], rules, path[:i + 1], state if i == len(path) - 1 else {}, tokens)
            if w and w[1] != "inherit":
                c = resolve_color(w[1], tokens)
                if c is None:
                    bad.append("%s: cannot read colour %r from %s" % (label, w[1], w[2])); break
                color = c
        bg = winning(["background-color", "background"], rules, path, state, tokens)
        bgc = resolve_color(bg[1], tokens) if bg else None
        if bgc is None:
            bad.append("%s: the button has no background" % label); continue
        if contrast(color, bgc) < 4.5:
            bad.append("%s: text %s on button %s is %.1f:1 (text from %r, button from %r)" % (label, "#%02x%02x%02x" % color, "#%02x%02x%02x" % bgc, contrast(color, bgc), w[2] if w else "nothing", bg[2]))
        if luminance(color) > luminance(bgc):
            bad.append("%s: the button is not dark text on a light button" % label)
        # the small print inside
        small = path + [{"tag": "small", "classes": [], "target": False}]
        ws = winning(["color"], rules, small, {}, tokens)
        sc = resolve_color(ws[1], tokens) if ws and ws[1] != "inherit" else color
        if sc is None or contrast(sc, bgc) < 4.5:
            bad.append("%s: the small print is %s on %s" % (label, ws[1] if ws else "inherited", "#%02x%02x%02x" % bgc))
    if bad:
        problem("the Download button's cascade: " + "; ".join(bad))
    else:
        ok("Download button is dark text on a light button at rest, on hover and on focus; the small print too")


def main():
    print("build: Cute page")
    version = toc_version()
    build_known()
    build_changes(version)
    build_quest(version)
    if problems:
        print("problems: %d" % len(problems))
        for p in problems:
            print("  - " + p)
        sys.exit(1)
    build_zip()
    if not os.path.isfile(ZIP):
        sys.exit("no Cute.zip at %s: build it or drop --no-zip" % ZIP)
    kb = int(round(os.path.getsize(ZIP) / 1024.0))
    counts = build_stats()
    html = open(PAGE, encoding="utf-8").read()
    values = {"v": version, "kb": str(kb)}
    values.update({k: str(v) for k, v in counts.items()})
    stamped, n = stamp(html, values)
    if stamped != html:
        open(PAGE, "w", encoding="utf-8").write(stamped)
        ok("stamped %d markers: version %s, %d KB, %d stats (page written)" % (n, version, kb, counts["n"]))
    else:
        ok("stamped %d markers: version %s, %d KB, %d stats (page unchanged)" % (n, version, kb, counts["n"]))
    html = stamped
    page_rules = rules_of(page_style(html))
    site_rules = rules_of(open(SITE_CSS, encoding="utf-8").read())
    check_links(html)
    check_online(html)
    check_classes(html, page_rules, site_rules)
    check_stale(html, version)
    check_contrast(page_rules)
    check_download_cascade(page_rules, site_rules)
    if problems:
        print("problems: %d" % len(problems))
        for p in problems:
            print("  - " + p)
        sys.exit(1)
    print("problems: 0")
    print("OK")


if __name__ == "__main__":
    main()
