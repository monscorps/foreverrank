#!/usr/bin/env python3
"""Build and check the QuestBank page, so nothing on it is typed by hand or goes stale.

  python3 -I tools/questbank/build_page.py [--page questbank/index.html] [--online]

In order: read the version (QuestBank/QuestBank.toc), the zip sizes (questbank/QuestBank.zip and the Uploader zip, with
the QuestBank version the Uploader carries), the data story's numbers (QuestBank/Data.lua's D.Q and GAPS.md: quests
by level band, Forever data against the Classic seed, what players' games confirmed), stamp them into the page between
<!--@name--> ... <!--/@name--> markers, then check the page:
  - every local href/src exists beside the page or under the repo; the ids the game and the site link to (share,
    install, help) are there, and every /questbank/#id link elsewhere on the site lands on an id
  - every class the page's own style defines starts with qb- and none appears in forever.css; every class the markup
    and the scripts use is styled; no selector reaches past qb- (the one html rule respects reduced motion)
  - no version number, placeholder or retired wording outside the markers and the changelog labels (Prep, No bag,
    third switch, the old tab names, "beta", "unlisted"); the changelog's newest entry is the toc's version
  - the page's greys pass 4.5:1 on the surfaces they sit on; the Download button is dark text on a light button
    through the whole cascade (forever.css included), at rest, on hover and on focus
  - the gallery's pictures: which are there and which the owner still has to capture (a missing one is hidden by
    the page, never a broken picture); the share image
  - the mock window's quest names and levels are the catalog's (D.QN, D.Q), so the hero shows real quests
  - the page's script runs under node with a stub DOM: the mock draws with balanced tags, the gallery hides a
    picture that fails to load, the upload box refuses an empty send, the changelog fold works
  - the visible word count and an estimate of phone screens at 375 px (targets: 500 words, 8 screens)
  --online also fetches every external link (needs the network).
Prints each check; exits 1 with the problems when any fails. Python 3 standard library only; the CSS cascade helpers
come from tools/cute/build.py."""
import html as htmlmod, importlib.util, json, os, re, subprocess, sys, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ADDON = os.path.join(HERE, "QuestBank")
TOC = os.path.join(ADDON, "QuestBank.toc")
DATA = os.path.join(ADDON, "Data.lua")
GAPS = os.path.join(HERE, "GAPS.md")
PAGE_DIR = os.path.join(ROOT, "questbank")
ZIP = os.path.join(PAGE_DIR, "QuestBank.zip")
UPZIP = os.path.join(PAGE_DIR, "QuestBank-Uploader.zip")
SITE_CSS = os.path.join(ROOT, "forever.css")
SHOTS = ["shot-now.jpg", "shot-route.jpg", "shot-map.jpg", "shot-minimap.jpg", "shot-journal.jpg", "shot-party.jpg"]
SHARE_IMG = os.path.join(PAGE_DIR, "img", "share.jpg")
WORD_TARGET, SCREEN_TARGET = 500, 8

_spec = importlib.util.spec_from_file_location("cute_build", os.path.join(ROOT, "tools", "cute", "build.py"))
cute = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cute)
rules_of, classes_in_selectors, winning = cute.rules_of, cute.classes_in_selectors, cute.winning
resolve_color, luminance, contrast, tokens_of = cute.resolve_color, cute.luminance, cute.contrast, cute.tokens_of

problems = []


def problem(s):
    problems.append(s)


def ok(s):
    print("  ok   " + s)


def arg(name, default):
    if name in sys.argv:
        return sys.argv[sys.argv.index(name) + 1]
    return default


# ---------------------------------------------------------------- inputs
def toc_version():
    m = re.search(r"^## Version:\s*(\S+)", open(TOC, encoding="utf-8").read(), re.M)
    if not m:
        sys.exit("QuestBank.toc has no ## Version line")
    return m.group(1)


def zip_kb(path):
    if not os.path.isfile(path):
        sys.exit("no zip at %s" % path)
    return int(round(os.path.getsize(path) / 1024.0))


def uploader_version():
    """the QuestBank version inside QuestBank-Uploader.zip (tools/build_uploader.py packs the addon folder beside the
    uploader's); the page says which it carries, since it can lag the download"""
    with zipfile.ZipFile(UPZIP) as z:
        for n in z.namelist():
            if n.endswith("QuestBank/QuestBank.toc"):
                m = re.search(r"^## Version:\s*(\S+)", z.read(n).decode("utf-8", "replace"), re.M)
                if m:
                    return m.group(1)
    sys.exit("QuestBank-Uploader.zip carries no QuestBank/QuestBank.toc")


def lua_table(src, name):
    """the text of D.name = { ... }: one line (D.QN, D.STATS) or a block closed by a line of its own (D.Q)"""
    m = re.search(r"^D\.%s = (\{[^\n]*\})$" % re.escape(name), src, re.M)
    if not m:
        m = re.search(r"^D\.%s = (\{.*?\n\})\n" % re.escape(name), src, re.S | re.M)
    if not m:
        sys.exit("Data.lua has no D.%s" % name)
    return m.group(1)


def read_catalog():
    """D.Q as {id: [level, req, side, base, mult, turn, give, cat, class, flags]} and D.QN as {id: name}"""
    src = open(DATA, encoding="utf-8").read()
    q = {}
    for qid, body in re.findall(r"^\[(\d+)\]=\{([^}]*)\}", lua_table(src, "Q"), re.M):
        q[int(qid)] = [float(x) if "." in x else int(x) for x in body.split(",")]
    names = {}
    for qid, name in re.findall(r'\[(\d+)\]="((?:[^"\\]|\\.)*)"', lua_table(src, "QN")):
        names[int(qid)] = name.replace('\\"', '"').replace("\\'", "'")
    m = re.search(r'^D\.READ = "([^"]+)"', src, re.M)
    stats = dict(re.findall(r"(\w+)=(\d+)", lua_table(src, "STATS")))
    return q, names, (m.group(1) if m else ""), {k: int(v) for k, v in stats.items()}


def data_story():
    """the counters and the level bands, from Data.lua and GAPS.md; the split (Forever data / Classic seed) must agree
    with D.STATS, which gen_data.py writes with GAPS.md, so the page and the gap report say the same"""
    q, names, read, stats = read_catalog()
    # the level bands count the quests with an XP number, as GAPS.md's table does (gen_data.py's gap_report:
    # base > 0); the first counter is the whole catalog, the ones still without a number included
    planned = {i: r for i, r in q.items() if r[3] > 0}
    forever = {i: r for i, r in planned.items() if not (r[9] & 16)}
    classic = {i: r for i, r in planned.items() if r[9] & 16}
    if len(forever) != stats.get("quests") or len(classic) != stats.get("classic"):
        sys.exit("the catalog's split (%d Forever data, %d Classic seed) differs from D.STATS %s: the flags or the filter changed" % (len(forever), len(classic), stats))
    priced = sum(1 for r in forever.values() if not (r[9] & (8 | 64)))
    new = sum(1 for i, r in forever.items() if i >= 70000 and not (r[9] & 128))
    confirmed = sum(1 for r in forever.values() if r[9] & (512 | 8192))
    gaps = open(GAPS, encoding="utf-8").read()
    m = re.search(r"Seen in Forever by players \((\d+) uploads[^)]*\): (\d+) quests", gaps)
    if not m:
        sys.exit("GAPS.md has no 'Seen in Forever by players' line")
    uploads, seen = int(m.group(1)), int(m.group(2))
    bands = []
    for lo in range(1, 60, 10):
        hi = lo + 9
        f = sum(1 for r in forever.values() if lo <= r[0] <= hi)
        c = sum(1 for r in classic.values() if lo <= r[0] <= hi)
        bands.append((lo, hi, f, c))
    return {"quests": len(q), "forever": len(forever), "classic": len(classic), "priced": priced, "new": new,
            "confirmed": confirmed, "seen": seen, "uploads": uploads, "read": read, "bands": bands, "names": names, "q": q}


def fmt(n):
    return "{:,}".format(n)


def bands_html(bands):
    """one row per level band: the band, a bar split Forever data / Classic seed, the two counts"""
    top = max(f + c for _, _, f, c in bands) or 1
    out = []
    for lo, hi, f, c in bands:
        wf, wc = 100.0 * f / top, 100.0 * c / top
        out.append('<div class="qb-band"><span class="qb-band-l">%d to %d</span>'
                   '<span class="qb-band-bar" role="img" aria-label="%s from Forever data, %s from the Classic seed">'
                   '<i class="qb-band-f" style="width:%.1f%%"></i><i class="qb-band-c" style="width:%.1f%%"></i></span>'
                   '<span class="qb-band-n"><b>%s</b>%s</span></div>'
                   % (lo, hi, fmt(f), fmt(c), wf, wc, fmt(f), (" + " + fmt(c)) if c else ""))
    return "".join(out)


# ---------------------------------------------------------------- stamping
def stamp(html, values):
    def one(m):
        name = m.group(1)
        if name not in values:
            problem("marker <!--@%s--> has no value to stamp" % name)
            return m.group(0)
        return "<!--@%s-->%s<!--/@%s-->" % (name, values[name], name)
    out, n = re.subn(r"<!--@([\w:]+)-->(.*?)<!--/@\1-->", one, html, flags=re.S)
    for name in ("v", "kb", "upv", "n:quests", "bands"):
        if not re.search(r"<!--@%s-->" % re.escape(name), html):
            problem("the page has no <!--@%s--> marker" % name)
    return out, n


# ---------------------------------------------------------------- checks
def unstamped(html):
    return re.sub(r"<!--@([\w:]+)-->.*?<!--/@\1-->", "", html, flags=re.S)


def page_style(html):
    """the page's style without its @keyframes (the cascade helpers read rules, and a keyframe's stops are none)"""
    m = re.search(r"<style>(.*?)</style>", html, re.S)
    css = m.group(1) if m else ""
    out, i = [], 0
    while True:
        j = css.find("@keyframes", i)
        if j < 0:
            out.append(css[i:]); break
        out.append(css[i:j])
        k, depth = css.find("{", j), 0
        while k < len(css):
            depth += {"{": 1, "}": -1}.get(css[k], 0)
            k += 1
            if depth == 0:
                break
        i = k
    return "".join(out)


def markup_only(html):
    """the page without its scripts: the link and class scans read markup, not the mock's code"""
    return re.sub(r"<script\b[^>]*>.*?</script>", " ", html, flags=re.S)


def page_script(html):
    """the page's own inline script (the one without src)"""
    for m in re.finditer(r"<script(?P<attrs>[^>]*)>(?P<body>.*?)</script>", html, re.S):
        if "src=" not in m.group("attrs") and "application/json" not in m.group("attrs"):
            return m.group("body")
    return ""


def check_links(html):
    bad = []
    for attr, url in re.findall(r"(?<![\w-])(href|src)=\"([^\"]+)\"", markup_only(html)):
        if url.startswith(("http://", "https://", "mailto:", "#", "data:")):
            continue
        path = url.split("#")[0].split("?")[0]
        if not path:
            continue
        f = os.path.join(ROOT, path.lstrip("/")) if path.startswith("/") else os.path.join(PAGE_DIR, path)
        if os.path.isdir(f):
            f = os.path.join(f, "index.html")
        if not os.path.isfile(f):
            bad.append(url)
    # the gallery's pictures are referenced from data-src (the page loads them itself, to hide the missing ones)
    shots = set(re.findall(r'data-src="img/([^"]+)"', html))
    if shots != set(SHOTS):
        bad.append("gallery slots %s (expected %s)" % (sorted(shots), SHOTS))
    ids = set(re.findall(r'\bid="([^"]+)"', html))
    for frag in re.findall(r'href="#([^"]+)"', html):
        if frag not in ids:
            bad.append("#" + frag)
    for must in ("share", "install", "help"):  # Core.lua, UI.lua and Discover.lua send players to these
        if must not in ids:
            bad.append("id %s, which the game's own text points players at" % must)
    # links into the page from the rest of the site
    for f in ("index.html", "nav.js", "addon/index.html", "addons/cute/index.html", "news.json", "uploader/README.txt", "sitemap.xml"):
        src = open(os.path.join(ROOT, f), encoding="utf-8").read()
        for frag in re.findall(r"questbank/#([\w-]+)", src):
            if frag not in ids:
                bad.append("%s links to /questbank/#%s" % (f, frag))
    if bad:
        problem("links to missing files or ids: " + ", ".join(sorted(set(bad))))
    else:
        ok("every local link, image and id resolves; share, install and help are there; the site's links in land")


def check_online(html):
    if "--online" not in sys.argv:
        print("  skip external links (--online fetches them)")
        return
    import urllib.request
    bad = []
    hints = set(re.findall(r"<link[^>]*rel=\"(?:preconnect|dns-prefetch)\"[^>]*href=\"([^\"]+)\"", html))
    for url in sorted(set(re.findall(r"\b(?:href|src)=\"(https?://[^\"]+)\"", html)) - hints):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (questbank build check)"})
            with urllib.request.urlopen(req, timeout=15) as r:
                if r.status >= 400:
                    bad.append("%s (%d)" % (url, r.status))
        except Exception as e:  # noqa: BLE001
            bad.append("%s (%s)" % (url, e))
    if bad:
        problem("external links that do not answer: " + "; ".join(bad))
    else:
        ok("every external link answers")


def check_classes(html, page_rules, site_rules):
    defined = classes_in_selectors(page_rules)
    site = classes_in_selectors(site_rules)
    off = sorted(c for c in defined if not c.startswith("qb-"))
    if off:
        problem("classes the page defines without the qb- prefix: " + ", ".join(off))
    clash = sorted(defined & site)
    if clash:
        problem("classes defined both here and in forever.css: " + ", ".join(clash))
    loose = sorted(set(sel for sel, _, _ in page_rules if ".qb-" not in sel and sel not in (":root", "html")))
    if loose:
        problem("selectors in the page's style that reach past qb-: " + ", ".join(loose))
    # the markup's class attributes (the nav and the footer wear forever.css's), and every qb- token the page's
    # scripts build a class from; a prefix the script completes from data ("qb-mk-" + kind, "qb-w-" + kind) names
    # its kinds here
    used = set()
    for s in re.findall(r"\bclass=\"([^\"]*)\"", markup_only(html)):
        used.update(s.split())
    ids = set(re.findall(r'\bid="([^"]+)"', html))
    used.update(t for t in re.findall(r"\bqb-[\w-]*\w", page_script(html)) if t not in ids)
    used.difference_update(["qb-mk", "qb-w"])  # prefixes the script completes from data: their kinds follow
    used.update(["qb-mk-avail", "qb-mk-wait", "qb-mk-ready", "qb-w-log", "qb-w-done", "qb-w-bad", "qb-band-f", "qb-band-c"])
    known = defined | site
    unknown = sorted(c for c in used if c not in known)
    if unknown:
        problem("classes used but styled nowhere: " + ", ".join(unknown))
    if not off and not clash and not loose and not unknown:
        ok("%d page classes, all qb-, none in forever.css; every class used is styled" % len(defined))


STALE = [
    (r"\bPrep\b", "Prep (the tab is Available)"),
    (r"No bag", "No bag (the sleeping bag switch went in 3.4.7)"),
    (r"third switch", "third switch"),
    (r"\bHand-in Route\b", "Hand-in Route (the page is Route)"),
    (r"\bPlan tab\b|\bPlan page\b|\bthe Plan\b", "the Plan tab (Available since 3.4.9)"),
    (r"\bbeta\b", "beta (stale from 4 November 2026)"),
    (r"\bunlisted\b", "unlisted"),
    (r"\bBanked now\b", "Banked now (the Route's switch is Ready now while questing)"),
    (r"Next: pins on the minimap", "a promise already kept"),
    (r"\bTODO\b|\bFIXME\b|lorem|\bXXX\b", "a placeholder"),
    (r"\bcoming soon\b", "coming soon"),
]


def check_stale(html, version):
    body = unstamped(html)
    body = re.sub(r"<li><b>\d+\.\d+\.\d+</b>", "<li><b></b>", body)
    body = re.sub(r"<svg\b.*?</svg>", "", body, flags=re.S)
    body = re.sub(r"<script\b[^>]*>.*?</script>", "", body, flags=re.S)  # the mock's data and the upload box
    body = body.split("</head>", 1)[-1]
    # the changelog's lines are history: a retired word there names what changed
    log = re.search(r'<section[^>]*id="changelog".*?</section>', body, re.S)
    outside = body.replace(log.group(0), "") if log else body
    vers = sorted(set(re.findall(r"\b\d+\.\d+\.\d+\b", outside)))
    if vers:
        problem("version numbers typed by hand (stamp them or move them to the changelog): " + ", ".join(vers))
    found = []
    for pat, what in STALE:
        if re.search(pat, outside):
            found.append(what)
    if found:
        problem("stale or retired wording: " + "; ".join(found))
    text = re.sub(r"<[^>]+>", " ", outside)
    glyphs = [g for g in ("\u00b7", "\u2192", "\u2014") if g in text]
    if glyphs:
        problem("middle dots, arrows or dashes in the body text: " + " ".join(glyphs))
    logs = re.findall(r"<li><b>(\d+\.\d+\.\d+)</b>", html)
    if not logs:
        problem("the changelog has no entries")
    elif logs[0] != version:
        problem("the changelog's newest entry is %s but QuestBank.toc says %s: bump the toc or add the entry" % (logs[0], version))
    if not vers and not found and not glyphs and logs and logs[0] == version:
        ok("no stale text; changelog newest = toc = %s" % version)


def check_contrast(page_rules):
    t = tokens_of(page_rules)
    text = ["--qb-ink", "--qb-dim", "--qb-mute"]
    surfaces = ["--qb-bg", "--qb-panel", "--qb-stage", "--qb-hero"]
    bad = []
    for fg in text:
        for bg in surfaces:
            a, b = resolve_color(t.get(fg, ""), t), resolve_color(t.get(bg, ""), t)
            if not a or not b:
                bad.append("%s or %s is not a colour" % (fg, bg)); continue
            c = contrast(a, b)
            if c < 4.5:
                bad.append("%s on %s is %.2f:1" % (fg, bg, c))
    # the gold on the panels (links, the counters) and the small print on the gold button
    gold = resolve_color(t.get("--qb-gold", ""), t)
    for bg in surfaces:
        b = resolve_color(t.get(bg, ""), t)
        if gold and b and contrast(gold, b) < 4.5:
            bad.append("--qb-gold on %s is %.2f:1" % (bg, contrast(gold, b)))
    btn = resolve_color(t.get("--qb-btn", ""), t)
    if not btn or contrast((0x12, 0x0c, 0x02), btn) < 4.5:
        bad.append("the button's ink on --qb-btn")
    # the mock window's own inks on its panels (UI.lua's INK, INK_SOFT and GOLD_SOFT on the panel and the card)
    for name, rgb in (("INK", (237, 224, 199)), ("INK_SOFT", (168, 153, 128)), ("GOLD_SOFT", (199, 158, 77))):
        for sname, s in (("panel", (23, 28, 38)), ("card", (10, 13, 18)), ("header", (31, 38, 51))):
            if contrast(rgb, s) < 4.5:
                bad.append("the window's %s on its %s is %.2f:1" % (name, sname, contrast(rgb, s)))
    if bad:
        problem("contrast under 4.5:1: " + "; ".join(bad))
    else:
        ok("greys and gold pass 4.5:1 on the page's surfaces; the window's inks on its panels too")


def check_download_cascade(page_rules, site_rules):
    rules = [(s, d, o) for s, d, o in site_rules] + [(s, d, o + 100000) for s, d, o in page_rules]
    tokens = tokens_of(page_rules)
    tokens.update(tokens_of(site_rules))
    path = [
        {"tag": "html", "classes": []},
        {"tag": "body", "classes": ["qb-page"]},
        {"tag": "main", "classes": ["qb-main"]},
        {"tag": "header", "classes": ["qb-hero"]},
        {"tag": "div", "classes": ["qb-wrap", "qb-hero-in"]},
        {"tag": "div", "classes": ["qb-cta"]},
        {"tag": "a", "classes": ["qb-dl"], "attrs": {"href": "QuestBank.zip", "class": "qb-dl"}, "target": True},
    ]
    bad = []
    for state in ({}, {"hover": True}, {"focus": True}):
        label = "hover" if state.get("hover") else "focus" if state.get("focus") else "rest"
        color = (0, 0, 0)
        w = None
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
        small = path + [{"tag": "small", "classes": [], "target": False}]
        ws = winning(["color"], rules, small, {}, tokens)
        sc = resolve_color(ws[1], tokens) if ws and ws[1] != "inherit" else color
        if sc is None or contrast(sc, bgc) < 4.5:
            bad.append("%s: the small print is %s on %s" % (label, ws[1] if ws else "inherited", "#%02x%02x%02x" % bgc))
    if bad:
        problem("the Download button's cascade: " + "; ".join(bad))
    else:
        ok("Download button is dark text on a gold button at rest, on hover and on focus; the small print too")


def build_share():
    """img/share.jpg, the 1200x630 share image, cut from the Now page's screenshot once the owner has captured it
    (img/shot-now.jpg): its middle, scaled to width, through Pillow where it is installed (the user's site-packages
    too, under python3 -I). Written only when the screenshot is newer than it."""
    src = os.path.join(PAGE_DIR, "img", "shot-now.jpg")
    if not os.path.isfile(src):
        return False
    if os.path.isfile(SHARE_IMG) and os.path.getmtime(SHARE_IMG) >= os.path.getmtime(src):
        return True
    try:
        from PIL import Image
    except ImportError:
        import site
        sys.path.append(site.getusersitepackages())
        try:
            from PIL import Image
        except ImportError:
            print("  note img/shot-now.jpg is in but Pillow is not: no share.jpg written")
            return False
    im = Image.open(src).convert("RGB")
    w, h = im.size
    target = 1200 / 630.0
    if w / float(h) > target:
        nw = int(round(h * target)); im = im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
    else:
        nh = int(round(w / target)); im = im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
    im = im.resize((1200, 630), Image.LANCZOS)
    im.save(SHARE_IMG, "JPEG", quality=88, optimize=True)
    ok("share image img/share.jpg written from shot-now.jpg (1200x630)")
    return True


def check_images(html):
    have, missing = [], []
    for s in SHOTS:
        (have if os.path.isfile(os.path.join(PAGE_DIR, "img", s)) else missing).append(s)
    if missing:
        print("  note the gallery waits for %d of %d pictures (the page hides their slots): %s" % (len(missing), len(SHOTS), ", ".join(missing)))
    else:
        ok("all %d gallery pictures are in" % len(SHOTS))
    if build_share():
        ok("share image img/share.jpg is in (tools/seo.py's row may point at it)")
    else:
        print("  note no share image yet (img/share.jpg, 1200x630, cut from shot-now.jpg): tools/seo.py keeps route.jpg until it is")
    # the gallery never shows a broken picture: each slot starts hidden and the page shows it once the file loads
    slots = re.findall(r'<figure class="qb-shot"[^>]*>', html)
    if len(slots) != len(SHOTS) or not all("hidden" in s for s in slots):
        problem("every gallery slot must start hidden (the page shows it when its picture loads)")
    if re.search(r'<img[^>]*src="img/shot-', html):
        problem("a gallery picture is in a plain <img src>: a missing one would show as broken")
    if "<noscript>" not in html.split('id="window"', 1)[-1].split("</section>", 1)[0]:
        problem("the mock's stage has no noscript fallback")
    return have, missing


def check_mock(html, story):
    """the hero's window draws real quests: every name in the mock's data is in D.QN at the level D.Q gives it"""
    m = re.search(r'<script type="application/json" id="qb-mock">(.*?)</script>', html, re.S)
    if not m:
        problem("the page has no qb-mock data"); return
    try:
        mock = json.loads(m.group(1))
    except ValueError as e:
        problem("qb-mock is not JSON: %s" % e); return
    names = {v: k for k, v in story["names"].items()}
    bad, n = [], 0
    for card in mock["cards"]:
        for row in card["rows"]:
            n += 1
            qid = names.get(row["name"])
            if qid is None:
                bad.append("%s is no catalog quest" % row["name"]); continue
            lvl = "L%d" % story["q"][qid][0]
            if row["lvl"] != lvl:
                bad.append("%s is %s in the catalog, not %s" % (row["name"], lvl, row["lvl"]))
    if bad:
        problem("the mock's quests: " + "; ".join(bad))
    else:
        ok("the mock's %d quest rows name catalog quests at their catalog levels" % n)


NODE_CHECK = r"""
// the page's script under a stub DOM: the mock draws, the gallery hides a failed picture, the upload box refuses an
// empty send, the stage's swipe note reads. Usage: node - <page.html>
const fs = require("fs");
const html = fs.readFileSync(process.argv[2], "utf8");
const scripts = [...html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)].filter(m => !/src=/.test(m[1]) && !/application\/json/.test(m[1])).map(m => m[2]);
const mockJson = /<script type="application\/json" id="qb-mock">([\s\S]*?)<\/script>/.exec(html)[1];
const byId = {}, created = [];
function el(tag, id) {
  const e = { tag, id, dataset: {}, attrs: {}, listeners: {}, hidden: false, textContent: "", innerHTML: "", style: {}, className: "", children: [],
    classList: { add(c) { e.className += " " + c; }, remove() {}, toggle() {}, contains(c) { return e.className.indexOf(c) >= 0; } },
    setAttribute(k, v) { this.attrs[k] = v; }, getAttribute(k) { return this.attrs[k] === undefined ? null : this.attrs[k]; }, removeAttribute(k) { delete this.attrs[k]; },
    addEventListener(t, f) { (this.listeners[t] = this.listeners[t] || []).push(f); }, appendChild(c) { this.children.push(c); return c; },
    querySelector() { return null; }, querySelectorAll() { return []; }, closest() { return null; }, focus() {}, scrollIntoView() {},
    getBoundingClientRect() { return { left: 0, top: 0, right: 375, bottom: 600, width: 375, height: 600 }; }, files: [], value: "" };
  if (id) byId[id] = e;
  return e;
}
const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(m => m[1]);
ids.forEach(i => el("div", i));
byId["qb-mock"].textContent = mockJson;
byId["qb-upcount"].textContent = "No account, no login.";
const shots = [...html.matchAll(/<figure class="qb-shot"[^>]*data-src="([^"]+)"[^>]*>/g)].map(m => { const f = el("figure"); f.dataset.src = m[1]; f.hidden = true; return f; });
const images = [];
global.Image = function () { const i = { }; images.push(i); return i; };
global.window = { addEventListener() {}, matchMedia() { return { matches: false, addEventListener() {} }; }, innerWidth: 375, scrollY: 0 };
global.location = { search: "", hash: "" };
global.URLSearchParams = function () { return { get() { return null; } }; };
global.FormData = function () { this.parts = []; this.append = (k, v) => this.parts.push(k); };
let fetched = [];
global.fetch = (url) => { fetched.push(url); return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve({ uploads: 3, last: Date.now() / 1000 - 90 }) }); };
global.document = {
  getElementById(id) { return byId[id] || null; },
  querySelectorAll(sel) { if (sel === ".qb-shot") return shots; return []; },
  querySelector() { return null; },
  createElement(tag) { const e = el(tag); created.push(e); return e; },
  addEventListener() {}, body: el("body"), documentElement: el("html"),
};
global.setTimeout = (f) => { f(); return 1; }; global.clearTimeout = () => {};
scripts.forEach(s => new Function(s)());
const fail = m => { console.log("FAIL", m); process.exitCode = 1; };
const ok = m => console.log("  ok   " + m);
function balanced(h, what) {
  const stack = [], VOID = new Set(["input", "col", "br", "img", "i", "path", "circle", "use"]);
  for (const m of h.matchAll(/<(\/?)([a-z0-9]+)[^>]*?>/g)) {
    const close = m[1] === "/", tag = m[2];
    if (tag === "i" && !close && !/<\/i>/.test(h)) continue;
    if (VOID.has(tag) && tag !== "i") continue;
    if (!close) stack.push(tag);
    else if (stack.pop() !== tag) { fail(what + ": unbalanced </" + tag + ">"); return; }
  }
  if (stack.length) fail(what + ": unclosed " + stack.join(","));
}
// the mock
const win = byId["qb-win"];
if (!win.innerHTML || win.innerHTML.length < 2000) fail("the mock window drew nothing: " + win.innerHTML.length);
balanced(win.innerHTML, "the mock window");
const mock = JSON.parse(mockJson);
const text = win.innerHTML.replace(/<[^>]+>/g, " ");
for (const c of mock.cards) { if (text.indexOf(c.name) < 0) fail("card " + c.name + " not drawn"); for (const r of c.rows) if (text.indexOf(r.name.replace(/&/g, "&amp;").replace(/'/g, "&#39;")) < 0 && text.indexOf(r.name) < 0) fail("row " + r.name + " not drawn"); }
if (text.indexOf(mock.who.name) < 0) fail("the character's name is not drawn");
const arrow = byId["qb-arrow"];
if (!arrow.innerHTML || arrow.innerHTML.indexOf(mock.arrow.name) < 0) fail("the arrow is not drawn with its target");
balanced(arrow.innerHTML, "the arrow");
ok("mock: window " + win.innerHTML.length + " chars, " + mock.cards.length + " cards, " + mock.cards.reduce((n, c) => n + c.rows.length, 0) + " rows; arrow to " + mock.arrow.name);
// the gallery: a picture that loads shows its slot, one that fails leaves it hidden (never a broken picture)
if (images.length !== shots.length) fail("the gallery asked for " + images.length + " pictures, has " + shots.length + " slots");
images[0].onload && images[0].onload();
images[1].onerror && images[1].onerror();
if (shots[0].hidden) fail("a picture that loaded leaves its slot hidden");
if (!shots[1].hidden) fail("a picture that failed shows its slot");
const slotBtn = shots[0].children[0];
if (!slotBtn || slotBtn.tag !== "button" || !slotBtn.children.length || slotBtn.children[0] !== images[0]) fail("the loaded picture is not put in its slot's button (tap to enlarge)");
if (!slotBtn.listeners.click) fail("the slot's button has no click to enlarge");
ok("gallery: a loaded picture shows its slot, a failed one stays hidden (" + shots.length + " slots)");
// the upload box
const form = byId["qb-upform"], stat = byId["qb-upstat"];
if (!form.listeners.submit) fail("the upload form has no submit handler");
form.listeners.submit[0]({ preventDefault() {} });
if (!/Choose your QuestBank\.lua first/.test(stat.textContent)) fail("an empty send is not refused: " + stat.textContent);
if (!fetched.some(u => /\/api\/probe\/stats$/.test(u))) fail("the upload count is not fetched from the Worker");
byId["qb-uptext"].value = "QuestBankDB = {}";
form.listeners.submit[0]({ preventDefault() {} });
if (!fetched.some(u => /\/api\/probe$/.test(u))) fail("a pasted file is not posted to /api/probe");
ok("upload box: refuses an empty send, posts text to /api/probe, reads /api/probe/stats; " + fetched.length + " fetches");
console.log(process.exitCode ? "FAILED" : "  ok   page script ok under node");
"""


def check_node(page):
    if subprocess.run(["which", "node"], capture_output=True).returncode != 0:
        print("  skip node check (no node)")
        return
    r = subprocess.run(["node", "-", page], input=NODE_CHECK, capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip()
    for line in out.splitlines():
        print(line if line.startswith("  ok") else "  " + line)
    if r.returncode != 0:
        problem("the page's script under node: " + out.replace("\n", " | ")[:600])


def visible_text(html):
    body = html.split("</head>", 1)[-1]
    body = re.sub(r"<script\b[^>]*>.*?</script>", " ", body, flags=re.S)
    body = re.sub(r"<noscript\b[^>]*>.*?</noscript>", " ", body, flags=re.S)
    body = re.sub(r"<svg\b.*?</svg>", " ", body, flags=re.S)
    # what is folded (details past its summary) does not count as visible
    body = re.sub(r"(<summary\b[^>]*>.*?</summary>).*?</details>", r"\1", body, flags=re.S)
    body = re.sub(r"<[^>]+>", " ", body)
    return htmlmod.unescape(body)


def check_length(html):
    text = visible_text(html)
    words = len(re.findall(r"\d[\d,.]*|[A-Za-z][A-Za-z'’]*", text))  # a number is one word
    # a phone at 375 px: about 7 words a line at 15 px, 23 px a line, plus the blocks that take space on their own
    lines = words / 7.0
    fixed = 56 + 300 + 660 + 60 + 6 * 44 + 3 * 60 + 300 + 6 * 56 + 24 * 6  # nav, hero art, the stage, the swipe note, tiles, buttons, chart, gallery slots, folds
    px = lines * 23 + fixed
    screens = px / 812.0
    note = "visible words %d (target %d), about %.1f phone screens at 375 px (target %d); folded text not counted" % (words, WORD_TARGET, screens, SCREEN_TARGET)
    # a tenth over the word target is a note (the gallery's captions count before their pictures are in); more fails
    if words > WORD_TARGET * 1.1 or screens > SCREEN_TARGET:
        problem(note)
    elif words > WORD_TARGET:
        print("  note " + note)
    else:
        ok(note)


def main():
    print("build: QuestBank page")
    page = arg("--page", os.path.join(PAGE_DIR, "index.html"))
    version = toc_version()
    story = data_story()
    kb, upkb, upv = zip_kb(ZIP), zip_kb(UPZIP), uploader_version()
    ok("version %s, QuestBank.zip %d KB, Uploader %d KB carrying QuestBank %s%s" % (version, kb, upkb, upv, "" if upv == version else " (behind the download: python3 tools/build_uploader.py)"))
    ok("data: %s quests planned (%s Forever data, %s Classic seed), %s priced from Forever's own data, %s new in Forever, %s confirmed by players' games (%s seen, %s uploads)"
       % tuple(fmt(story[k]) for k in ("quests", "forever", "classic", "priced", "new", "confirmed", "seen", "uploads")))
    html = open(page, encoding="utf-8").read()
    values = {"v": version, "kb": str(kb), "upv": upv, "upkb": str(upkb), "read": story["read"],
              "bands": bands_html(story["bands"]), "n:uploads": fmt(story["uploads"])}
    for k in ("quests", "forever", "classic", "priced", "new", "confirmed", "seen"):
        values["n:" + k] = fmt(story[k])
    stamped, n = stamp(html, values)
    if stamped != html:
        open(page, "w", encoding="utf-8").write(stamped)
        ok("stamped %d markers (page written)" % n)
    else:
        ok("stamped %d markers (page unchanged)" % n)
    html = stamped
    page_rules = rules_of(page_style(html))
    site_rules = rules_of(open(SITE_CSS, encoding="utf-8").read())
    check_links(html)
    check_online(html)
    check_classes(html, page_rules, site_rules)
    check_stale(html, version)
    check_contrast(page_rules)
    check_download_cascade(page_rules, site_rules)
    check_images(html)
    check_mock(html, story)
    check_node(page)
    check_length(html)
    if problems:
        print("problems: %d" % len(problems))
        for p in problems:
            print("  - " + p)
        sys.exit(1)
    print("problems: 0")
    print("OK")


if __name__ == "__main__":
    main()
