#!/usr/bin/env python3
"""Compile bis/bis.json from ForeverChanges' beta BiS lists.

foreverchanges.pro publishes hand-ranked best-in-slot lists for the WoW
Forever beta (level-20 cap), one page per class and spec, as plain
server-rendered HTML. This pulls the factual rows only - slot, item id,
ranked order, source, crafting mats - and drops their editorial prose;
page copy on /bis/ is our own, and the page credits them by name.
Item ids are the client's own, so every row joins our datamined
plan/items-db.json for stats and tooltips; the script reports coverage.

Run from the repo root:  python3 tools/build_bis.py
Fetched pages are cached in tools/.bis-cache/ (gitignored); delete the
folder to force a fresh pull.
"""
import html as htmlmod
import json, os, re, sys, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

BASE = "https://foreverchanges.pro"
CLASSES = ["warrior", "hunter", "mage", "rogue", "priest", "warlock", "paladin", "druid", "shaman"]
CACHE = "tools/.bis-cache"
QUAL = {"q0": "poor", "q1": "common", "q2": "uncommon", "q3": "rare", "q4": "epic", "q5": "legendary"}

os.makedirs(CACHE, exist_ok=True)

def fetch(path):
    slug = path.strip("/").replace("/", "_") or "home"
    cached = os.path.join(CACHE, slug + ".html")
    if os.path.exists(cached):
        return open(cached, encoding="utf-8").read()
    req = urllib.request.Request(BASE + path, headers={"User-Agent": "foreverrank.com data compile (contact via site Discord)"})
    html = urllib.request.urlopen(req, timeout=30).read().decode("utf-8")
    open(cached, "w", encoding="utf-8").write(html)
    time.sleep(1)  # be polite; ~20 pages once
    return html

def strip_tags(s):
    return htmlmod.unescape(re.sub(r"<[^>]+>", "", s)).strip()

def parse_specs(html, cls):
    """Spec tabs are plain links: /bis/<class> is the first spec, /bis/<class>/<spec> the rest."""
    specs = []
    for m in re.finditer(r'<a class="bis-spec"[^>]*href="(/bis/[^"#]+)"[^>]*>(.*?)</a>', html, re.S):
        path, label = m.group(1), strip_tags(m.group(2))
        icon = re.search(r'src="/icon/([a-z0-9_-]+)\.jpg"', m.group(2))
        key = path.rstrip("/").split("/")[-1]
        if key == cls:
            key = label.lower().replace(" ", "-")
        if not any(s["path"] == path for s in specs):
            specs.append({"key": key, "name": label, "path": path, "icon": icon.group(1) if icon else ""})
    return specs

def parse_from(li):
    """The bis-from cell: a link (or plain text), trailing text, and note spans,
    with separators kept between nested spans and duplicates collapsed."""
    from_m = re.search(r'<div class="bis-from">(.*?)</div>', li, re.S)
    if not from_m:
        return []
    src = []
    for p in re.findall(r"<p>(.*?)</p>", from_m.group(1), re.S):
        link = re.search(r"<a[^>]*>(.*?)</a>", p, re.S)
        rest = re.sub(r"<a[^>]*>.*?</a>", "", p, flags=re.S)
        rest = re.sub(r"(</span>|</em>|</b>|</i>)\s*(<span[^>]*>|<em>|<b>|<i>)", " · ", rest)
        pieces, seen = [], set()
        for frag in strip_tags(rest).split(" · "):
            frag = frag.strip(" ·.")
            if frag and frag not in seen:
                seen.add(frag)
                pieces.append(frag)
        entry = {"t": strip_tags(link.group(1)) if link else (pieces.pop(0) if pieces else "")}
        if pieces:
            entry["n"] = " · ".join(pieces)
        if entry["t"] or entry.get("n"):
            src.append(entry)
    blob = " ".join(e.get("t", "") + " " + e.get("n", "") for e in src)
    if re.search(r"not known yet|nothing places it yet", blob, re.I):
        src = [{"t": "Source not yet known"}]
    return src

def parse_rows(ol_html):
    rows, dropped = [], 0
    for li in re.split(r'<li class="bis-row', ol_html)[1:]:
        icon_m = re.search(r'src="/icon/([a-z0-9_-]+)\.jpg"[^>]*class="bis-icon (?:bq(\d))?', li)
        row = {"icon": icon_m.group(1) if icon_m else ""}
        ench_m = re.search(r'<small class="bis-enchant-slots">([^<]*)</small>\s*<p class="bis-enchant-line">([^<]*)</p>', li)
        name_m = re.search(r'<a([^>]*)class="bis-name (q\d)"([^>]*)>([^<]+)</a>', li)
        if name_m:
            attrs = name_m.group(1) + name_m.group(3)
            tid = re.search(r'data-tip="(\d+)"', attrs) or re.search(r'href="/item/(\d+)"', attrs)
            row["id"] = tid.group(1) if tid else ""
            row["name"] = htmlmod.unescape(name_m.group(4))
            row["q"] = QUAL.get(name_m.group(2), "unknown")
        elif ench_m:
            # an enchant row names no item; the enchant consumable sits in bis-from
            row["enchant"] = 1
            row["eslot"] = strip_tags(ench_m.group(1))
            row["name"] = htmlmod.unescape(ench_m.group(2)).replace("Enchanted: ", "")
            fid = re.search(r'<div class="bis-from">.*?<a href="/item/(\d+)"', li, re.S)
            row["id"] = fid.group(1) if fid else ""
            row["q"] = "q" + icon_m.group(2) if icon_m and icon_m.group(2) else "common"
            row["q"] = QUAL.get(row["q"], row["q"])
        else:
            dropped += 1
            continue
        src = parse_from(li)
        if src:
            row["from"] = src
        mats = []
        for mat in re.finditer(r'<span class="bis-mat[^"]*" data-tip="(\d+)">(.*?)</span>', li, re.S):
            alt = re.search(r'alt="([^"]*)"', mat.group(2))
            count = re.search(r"<b>(\d+)</b>", mat.group(2))
            m_ic = re.search(r'src="/icon/([a-z0-9_-]+)\.jpg', mat.group(2))
            mats.append({"id": mat.group(1), "name": htmlmod.unescape(alt.group(1)) if alt else "",
                         "icon": m_ic.group(1) if m_ic else "",
                         "n": int(count.group(1)) if count else 0})
        if mats:
            row["mats"] = mats
        rows.append(row)
    return rows, dropped

def parse_page(html):
    slots, dropped = [], 0
    for sec in re.split(r'<section class="bis-slot', html)[1:]:
        sec = sec.split("</section>")[0]
        id_m = re.search(r'id="([a-z-]+)"', sec)
        h2_m = re.search(r"<h2>([^<]+)</h2>", sec)
        rows, drop = parse_rows(sec)
        dropped += drop
        slots.append({"slot": id_m.group(1).replace("slot-", "") if id_m else "enchants",
                      "label": h2_m.group(1) if h2_m else "Enchants",
                      "rows": rows})
    # every bis-row in the HTML must land in a slot, or the run says so
    total_li = html.count('<li class="bis-row')
    parsed = sum(len(s["rows"]) for s in slots)
    if parsed + dropped != total_li or dropped:
        print("  WARNING: page has %d rows, parsed %d, dropped %d" % (total_li, parsed, dropped))
    return slots

# our item db, for the coverage report and to confirm the id join holds
db_ids = set()
try:
    for it in json.load(open("plan/items-db.json"))["items"]:
        db_ids.add(str(it["id"]))
except Exception as e:
    print("warning: could not read plan/items-db.json:", e)

build_m = level_m = None
out = {"note": "BiS lists for the Forever beta. Slot rankings compiled from foreverchanges.pro "
               "(credited on the page and in SOURCES.md); stats and tooltips join our own "
               "datamined item database by the client's item ids. Page copy is ours.",
       "source": "https://foreverchanges.pro/bis", "classes": []}

total = missing = 0
for cls in CLASSES:
    html = fetch("/bis/" + cls)
    if build_m is None:
        build_m = re.search(r"BETA BUILD ([0-9.]+)", html, re.I)
        level_m = re.search(r"level (\d+)", html, re.I)
    specs = parse_specs(html, cls)
    if not specs:
        specs = [{"key": "default", "name": "Default", "path": "/bis/" + cls}]
    centry = {"key": cls, "specs": []}
    for spec in specs:
        page = html if spec["path"].rstrip("/") == "/bis/" + cls else fetch(spec["path"])
        slots = parse_page(page)
        n = sum(len(s["rows"]) for s in slots)
        miss = [r["name"] for s in slots for r in s["rows"] if r["id"] not in db_ids]
        total += n
        missing += len(miss)
        print("%-8s %-14s %2d slots %3d rows%s" % (cls, spec["name"], len(slots), n,
              ("  NOT IN OUR DB: " + ", ".join(miss[:4]) + ("..." if len(miss) > 4 else "")) if miss else ""))
        centry["specs"].append({"key": spec["key"], "name": spec["name"], "icon": spec.get("icon", ""), "slots": slots})
    out["classes"].append(centry)

out["level"] = int(level_m.group(1)) if level_m else 20
out["build"] = build_m.group(1) if build_m else ""
out["pulled"] = time.strftime("%Y-%m-%d")

os.makedirs("bis", exist_ok=True)
json.dump(out, open("bis/bis.json", "w"), separators=(",", ":"))
size = os.path.getsize("bis/bis.json") // 1024
print("\nwrote bis/bis.json (%d KB), beta build %s, level %d" % (size, out["build"], out["level"]))
print("%d rows total, %d not in our item db (%.1f%% joined)" %
      (total, missing, 100.0 * (total - missing) / max(total, 1)))
