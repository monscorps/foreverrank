#!/usr/bin/env python3
"""Current tooltips for the BiS page: bis/bis-items.json.

Our plan/items-db.json is the beta client at build 1.60.1.69876 and the
beta keeps moving; items on the lists change between builds. So EVERY
item bis/bis.json cites - row or crafting mat - gets its tooltip read
fresh from its foreverchanges.pro item page (server-rendered, itself
datamined from the current client), and the BiS page prefers this file
over the older db. The main db stays pure: only what we datamined.

Run from the repo root, after build_bis.py:  python3 tools/build_bis_items.py
Pages cache in tools/.bis-cache/ next to the list pages; delete that
folder to force a fresh pull.
"""
import html as htmlmod
import json, os, re, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

BASE = "https://foreverchanges.pro"
CACHE = "tools/.bis-cache"
os.makedirs(CACHE, exist_ok=True)

def fetch(path):
    slug = path.strip("/").replace("/", "_")
    cached = os.path.join(CACHE, slug + ".html")
    if os.path.exists(cached):
        return open(cached, encoding="utf-8").read()
    req = urllib.request.Request(BASE + path, headers={"User-Agent": "foreverrank.com data compile (contact via site Discord)"})
    html = urllib.request.urlopen(req, timeout=30).read().decode("utf-8")
    open(cached, "w", encoding="utf-8").write(html)
    time.sleep(0.6)
    return html

def clean(s):
    return htmlmod.unescape(re.sub(r"<[^>]+>", "", s)).replace(" ", " ").strip()

SLOT_WORDS = {"Head": "head", "Neck": "neck", "Shoulder": "shoulder", "Back": "back", "Chest": "chest",
              "Wrist": "wrist", "Hands": "hands", "Waist": "waist", "Legs": "legs", "Feet": "feet",
              "Finger": "finger", "Trinket": "trinket", "Main Hand": "main-hand", "Off Hand": "off-hand",
              "One-Hand": "one-hand", "Two-Hand": "two-hand", "Ranged": "ranged", "Relic": "relic",
              "Thrown": "thrown", "Held In Off-hand": "off-hand", "Held In Off-Hand": "off-hand",
              "Shield": "off-hand", "Projectile": "ranged"}
TYPE_WORDS = {"Cloth", "Leather", "Mail", "Plate", "Shield", "Axe", "Sword", "Mace", "Dagger", "Staff",
              "Polearm", "Bow", "Gun", "Crossbow", "Wand", "Fist Weapon", "Fishing Pole", "Idol", "Libram", "Totem"}
STATS = {"Strength": "strength", "Agility": "agility", "Stamina": "stamina", "Intellect": "intellect", "Spirit": "spirit"}

def parse_item(html, iid):
    # the Forever-side tooltip block (the Classic one, when present, comes first)
    tips = re.split(r'<div class="it-tip', html)
    for_tip = None
    for t in tips[1:]:
        if "Forever beta" in t.split("</div>", 2)[0] or "it-empty" not in t.split(">", 1)[0]:
            for_tip = t.split("</section>")[0]
    if for_tip is None or "Not in" in for_tip[:400] and "it-empty" in for_tip[:200]:
        return None
    it = {"id": iid}
    label_m = re.search(r'<div class="it-label">([^<]*)</div>', for_tip)
    label = clean(label_m.group(1)) if label_m else ""
    m = re.search(r'<div class="it-name (q\d)">([^<]+)</div>', for_tip)
    if not m:
        return None
    QUAL = {"q0": "poor", "q1": "common", "q2": "uncommon", "q3": "rare", "q4": "epic", "q5": "legendary"}
    it["quality"] = QUAL.get(m.group(1), "common")
    it["name"] = htmlmod.unescape(m.group(2))
    ic = re.search(r'class="it-icon" src="/icon/([a-z0-9_-]+)\.jpg"', for_tip)
    if ic:
        it["icon"] = ic.group(1)
    lv = re.search(r"Item level (\d+)", for_tip)
    if lv:
        it["itemLevel"] = int(lv.group(1))
    stats, effects = {}, []
    # a line can carry diff markers (it-add / it-del) and two-column spans
    lines = []
    for m3 in re.finditer(r'<div class="it-line ([^"]*)">(.*?)</div>', for_tip, re.S):
        kinds, inner = m3.group(1), m3.group(2)
        spans = re.findall(r"<span[^>]*>(.*?)</span>", inner, re.S)
        parts = [clean(s) for s in spans] if spans else [clean(inner)]
        for p in parts:
            lines.append((kinds, p))
    dmg_seen = False
    for kind, text in lines:
        if not text:
            continue
        if "it-flavor" in kind:
            it["flavor"] = text.strip('"')
            continue
        if "it-muted" in kind or not ("it-plain" in kind or "it-good" in kind or "it-use" in kind):
            continue
        m2 = re.match(r"^\+(\d+) (Strength|Agility|Stamina|Intellect|Spirit)$", text)
        if m2:
            stats[STATS[m2.group(2)]] = int(m2.group(1))
            continue
        m2 = re.match(r"^\+(\d+) (\w+) Resistance$", text)
        if m2:
            stats.setdefault("resist", {})[m2.group(2).lower()] = int(m2.group(1))
            continue
        m2 = re.match(r"^(\d+) Armor$", text)
        if m2:
            it["armor"] = int(m2.group(1))
            continue
        m2 = re.match(r"^(\d+) Block$", text)
        if m2:
            it["block"] = int(m2.group(1))
            continue
        m2 = re.match(r"^Requires Level (\d+)", text)
        if m2:
            it["reqLevel"] = int(m2.group(1))
            continue
        m2 = re.match(r"^Requires (.+)$", text)
        if m2:
            effects.append(text)
            continue
        if text in ("Binds when picked up", "Binds when equipped", "Binds when used"):
            it["binding"] = "BoP" if "picked" in text else "BoE"
            continue
        if text.startswith("Unique"):
            it["unique"] = True if text == "Unique" else text
            continue
        m2 = re.match(r"^([0-9]+) - ([0-9]+) Damage$", text)
        if m2:
            it["damage"] = m2.group(1) + " - " + m2.group(2)
            dmg_seen = True
            continue
        m2 = re.match(r"^Speed ([0-9.]+)$", text)
        if m2:
            it["speed"] = float(m2.group(1))
            continue
        m2 = re.match(r"^\(([0-9.]+) damage per second\)$", text)
        if m2:
            it["dps"] = float(m2.group(1))
            continue
        if text in SLOT_WORDS:
            it["slot"] = SLOT_WORDS[text]
            continue
        if text in TYPE_WORDS:
            it["type"] = text
            continue
        if re.match(r"^(Equip:|Use:|Chance on hit:|Set:)", text):
            effects.append(text)
            continue
        # two-column line the markup renders as one string ("Neck Miscellaneous")
        matched = False
        for w, slot in SLOT_WORDS.items():
            if text.startswith(w):
                it["slot"] = slot
                rest = text[len(w):].strip()
                if rest in TYPE_WORDS:
                    it["type"] = rest
                matched = True
                break
        if not matched:
            effects.append(text)
    if stats:
        it["stats"] = stats
    if effects:
        it["effects"] = effects
    # first line per source only: the where, not their commentary
    src_m = re.search(r'<ul class="it-sources">(.*?)</ul>', html, re.S)
    srcs = []
    if src_m:
        for li in re.findall(r"<li>(.*?)</li>", src_m.group(1), re.S):
            parts = [clean(p) for p in re.findall(r"<p>(.*?)</p>", li, re.S)]
            head = next((p for p in parts if p), "")
            if head:
                srcs.append(head[:110])
    joined = "; ".join(srcs[:2])
    it["source"] = (joined[:160] + " · " if joined else "") + (label + ", " if label else "") + "via foreverchanges.pro"
    it["cat"] = "armor" if it.get("armor") or it.get("slot") in ("neck", "finger", "trinket", "back") else ("weapon" if dmg_seen else "misc")
    it["nw"] = 1
    return it

bis = json.load(open("bis/bis.json"))
need = {}
for c in bis["classes"]:
    for sp in c["specs"]:
        for sl in sp["slots"]:
            for r in sl["rows"]:
                if r.get("id"):
                    need[r["id"]] = r["name"]
                for mt in r.get("mats", []):
                    if mt.get("id"):
                        need[mt["id"]] = mt["name"]
print("fetching", len(need), "item pages (everything the lists cite)")

items, failed = [], []
for iid in sorted(need, key=int):
    try:
        it = parse_item(fetch("/item/" + iid), iid)
    except Exception as e:
        it = None
    if it:
        items.append(it)
    else:
        failed.append(iid + " " + need[iid])

out = {"note": "Current tooltips for the BiS page: every item its lists cite, read from "
               "foreverchanges.pro item pages (themselves datamined from the current beta client). "
               "The BiS page prefers these over plan/items-db.json, which is pinned to build "
               "1.60.1.69876. Credited in SOURCES.md.",
       "items": items}
json.dump(out, open("bis/bis-items.json", "w"), separators=(",", ":"))
print("wrote bis/bis-items.json: %d items (%d KB)" % (len(items), os.path.getsize("bis/bis-items.json") // 1024))
if failed:
    print("could not parse %d:" % len(failed))
    for f in failed[:10]:
        print("  ", f)
