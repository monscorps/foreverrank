#!/usr/bin/env python3
"""Dungeon loot tables for WoW: Forever, merged from the fansites that record
them, into codex/loot.json.

The Forever client carries no Dungeon Journal, so who drops what cannot be
datamined: it comes from players' loot records, published by
  - foreverchanges.pro/dungeons/<slug>  bosses, rare spawns, quests and rewards
  - wowtbc.gg page-data JSON            boss tables for every dungeon
Each boss and quest keeps the sites that list it. Raw pages are cached in
tools/.loot-cache/ (gitignored); --refresh refetches them.

  python3 tools/scavenge_loot.py [--refresh]
"""
import datetime, html as htmlmod, json, os, re, sys, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "tools", ".loot-cache")
UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36 foreverrank.com"}
FC = "https://foreverchanges.pro"
WTBC = "https://wowtbc.gg"
REFRESH = "--refresh" in sys.argv


def get(url, name):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name)
    if os.path.exists(path) and not REFRESH:
        return open(path, encoding="utf-8").read()
    for attempt in range(3):
        try:
            body = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read().decode("utf-8", "replace")
            open(path, "w", encoding="utf-8").write(body)
            time.sleep(0.6)
            return body
        except Exception as e:
            err = e
            time.sleep(2 + attempt * 3)
    print("  failed", url, err)
    return None


def next_payload(html):
    """The React Server Components stream a Next.js page ships its data in."""
    chunks = re.findall(r'self\.__next_f\.push\(\[1,"(.*?)"\]\)', html, re.S)
    return "".join(json.loads('"' + c + '"') for c in chunks)


def grab(blob, key):
    """The JSON array or object that follows `key` in the payload."""
    i = blob.find(key)
    if i < 0:
        return None
    j = i + len(key) - 1
    depth, ins, esc = 0, False, False
    for k in range(j, len(blob)):
        ch = blob[k]
        if ins:
            if esc: esc = False
            elif ch == "\\": esc = True
            elif ch == '"': ins = False
            continue
        if ch == '"': ins = True
        elif ch in "[{": depth += 1
        elif ch in "]}":
            depth -= 1
            if depth == 0:
                return json.loads(blob[j:k + 1])
    return None


def norm(s):
    s = re.sub(r"[^a-z0-9 ]", "", (s or "").lower().replace("'", ""))
    return re.sub(r"^the ", "", re.sub(r"\s+", " ", s)).strip()


# Stratholme is one dungeon in wowtbc's list and two wings on ForeverChanges.
ALIAS = {"stratholme main gate": "stratholme", "stratholme service gate": "stratholme",
         "excavation site": "excavation site wetlands", "sunken temple": "temple of atalhakkar",
         "lower blackrock spire": "blackrock spire lower", "upper blackrock spire": "blackrock spire upper"}


def dkey(name):
    n = norm(name)
    return ALIAS.get(n, n)


def main():
    dungeons, items_fc, items_wt = {}, {}, {}

    def dungeon(name):
        k = dkey(name)
        if k not in dungeons:
            dungeons[k] = {"name": "Stratholme" if k == "stratholme" else name, "slug": "", "levels": None, "new": False, "bosses": [], "quests": [], "src": []}
        return dungeons[k]

    def boss(d, name, kind, level, ids, site):
        for b in d["bosses"]:
            if norm(b["name"]) == norm(name):
                b["items"] += [i for i in ids if i not in b["items"]]
                if site not in b["src"]: b["src"].append(site)
                if level and not b.get("level"): b["level"] = level
                if kind == "rare": b["kind"] = "rare"
                return
        d["bosses"].append({"name": name, "kind": kind or "boss", "level": level, "items": list(ids), "src": [site]})

    # ForeverChanges: bosses, rares and quests with their rewards
    index = get(FC + "/dungeons", "fc-dungeons.html") or ""
    slugs = sorted(set(re.findall(r'href="/dungeons/([a-z0-9-]+)"', index)))
    print("foreverchanges: %d dungeons" % len(slugs))
    for slug in slugs:
        html = get(FC + "/dungeons/" + slug, "fc-" + slug + ".html")
        if not html:
            continue
        blob = next_payload(html)
        h1 = re.search(r"<h1[^>]*>([^<]+)", html)
        name = htmlmod.unescape(h1.group(1)).strip() if h1 else slug.replace("-", " ").title()
        d = dungeon(name)
        d["slug"] = d["slug"] or slug
        if "foreverchanges.pro" not in d["src"]: d["src"].append("foreverchanges.pro")
        for b in grab(blob, '"bosses":[') or []:
            ids = []
            for it in b.get("items") or []:
                ids.append(it["i"])
                items_fc[str(it["i"])] = it
            boss(d, b["name"], b.get("kind"), b.get("level"), ids, "foreverchanges.pro")
        for q in grab(blob, '"quests":[') or []:
            rew = (q.get("choice") or []) + (q.get("given") or [])
            for it in rew: items_fc[str(it["i"])] = it
            ids = [it["i"] for it in rew]
            if not ids: continue
            d["quests"].append({"name": q.get("title"), "level": q.get("level"), "min": q.get("min"), "side": q.get("side"),
                                "items": ids, "src": ["foreverchanges.pro"]})

    # wowtbc.gg: boss tables for every dungeon, with their level ranges
    first = get(WTBC + "/page-data/warcraftforever/loot-tables/dungeons/ruins-of-lordaeron/page-data.json", "wt-ruins-of-lordaeron.json")
    links = json.loads(first)["result"]["pageContext"]["dungeonLinks"] if first else []
    print("wowtbc.gg: %d dungeons" % len(links))
    for ln in links:
        slug = ln["path"].rstrip("/").split("/")[-1]
        raw = get(WTBC + "/page-data" + ln["path"] + "page-data.json", "wt-" + slug + ".json")
        if not raw: continue
        pc = json.loads(raw)["result"]["pageContext"]
        for g in pc.get("gearData") or []: items_wt[str(g["id"])] = g
        for L in pc.get("loot") or []:
            d = dungeon(L.get("dungeon") or ln["name"])
            if dkey(d["name"]) != "stratholme": d["name"] = L.get("dungeon") or ln["name"]
            d["levels"] = d["levels"] or L.get("levels") or ln.get("levels")
            d["new"] = d["new"] or bool(L.get("new") or ln.get("isNew"))
            if "wowtbc.gg" not in d["src"]: d["src"].append("wowtbc.gg")
            for b in L.get("bosses") or []:
                boss(d, b["name"], "boss", None, [int(i) for i in b.get("items") or []], "wowtbc.gg")
            for q in L.get("quests") or []:
                ids = [int(i) for i in q.get("items") or []]
                known = next((x for x in d["quests"] if norm(x["name"]) == norm(q.get("name"))), None)
                if known:
                    known["items"] += [i for i in ids if i not in known["items"]]
                    if "wowtbc.gg" not in known["src"]: known["src"].append("wowtbc.gg")
                elif ids:
                    d["quests"].append({"name": q.get("name"), "level": q.get("level"), "items": ids, "src": ["wowtbc.gg"]})

    out = sorted(dungeons.values(), key=lambda d: ((d["levels"] or [99])[0], d["name"]))
    for d in out:
        if not d["slug"]: d["slug"] = re.sub(r"[^a-z0-9]+", "-", d["name"].lower()).strip("-")
    n_items = len({i for d in out for b in d["bosses"] for i in b["items"]} | {i for d in out for q in d["quests"] for i in q["items"]})
    doc = {"note": "Who drops what in WoW: Forever. The client has no Dungeon Journal, so these are players' loot records as "
                   "published by foreverchanges.pro and wowtbc.gg (each boss and quest lists its sites). Beta data: bosses, drops "
                   "and levels can change before launch.",
           "generated": datetime.date.today().isoformat(), "dungeons": out}
    json.dump(doc, open(os.path.join(ROOT, "codex", "loot.json"), "w"), ensure_ascii=False, separators=(",", ":"))
    json.dump({"fc": items_fc, "wtbc": items_wt}, open(os.path.join(CACHE, "site-items.json"), "w"), ensure_ascii=False)
    print("codex/loot.json: %d dungeons, %d bosses, %d quests, %d items" % (
        len(out), sum(len(d["bosses"]) for d in out), sum(len(d["quests"]) for d in out), n_items))


if __name__ == "__main__":
    main()
