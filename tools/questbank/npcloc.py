"""NPC and object positions from Wowhead Forever tooltips (nether.wowhead.com), cached in
research/questbank/npcloc.json, and quest tooltips (name, text, what it asks for) in
research/questbank/qtips.json. A rate-limit answer (403, 429, 5xx) is never cached: the fetch waits and
tries again. Requests keep 3.2 s apart, shared with mapper.py's quest pages (the time of the last request
to Wowhead sits in tools/.wh-quest-cache/.last), so the two together never ask faster than that.

  python3 tools/questbank/npcloc.py ids.json                 # [["npc", 3441], ["object", 409289], ...]
  python3 tools/questbank/npcloc.py --quests=99411,92434     # quest tooltips, into qtips.json
"""
import html, json, os, re, sys, time, urllib.error, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(os.path.dirname(os.path.dirname(HERE)), "research", "questbank")
CACHE = os.path.join(RAW, "npcloc.json")
QCACHE = os.path.join(RAW, "qtips.json")
cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
qcache = json.load(open(QCACHE)) if os.path.exists(QCACHE) else {}
SPACING = 3.2
LAST = os.path.join(os.path.dirname(HERE), ".wh-quest-cache", ".last")


def pace():
    """Wait until SPACING seconds have passed since the last request to Wowhead (this script's or mapper.py's)."""
    try:
        last = float(open(LAST).read().strip() or 0)
    except (OSError, ValueError):
        last = 0.0
    wait = SPACING - (time.time() - last)
    if wait > 0:
        time.sleep(min(wait, SPACING))
    os.makedirs(os.path.dirname(LAST), exist_ok=True)
    with open(LAST, "w") as f:
        f.write("%.3f" % time.time())


def tooltip(kind, i, tries=4):
    """The tooltip's JSON, {"error": ...} for a 404, or None when Wowhead keeps refusing."""
    url = "https://nether.wowhead.com/forever/tooltip/%s/%s?dataEnv=16" % (kind, i)
    for attempt in range(tries):
        pace()
        try:
            return json.loads(urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=30).read())
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return {"error": "HTTP Error 404: Not Found"}
            print("  %s/%s: HTTP %d, waiting" % (kind, i, e.code), flush=True)
            time.sleep(180 if e.code in (403, 429) else 20)
        except Exception as e:
            print("  %s/%s: %s, waiting" % (kind, i, e), flush=True)
            time.sleep(20)
    return None


def get(kind, i, tries=4):
    key = "%s/%s" % (kind, i)
    if key in cache:
        return cache[key]
    body = tooltip(kind, i, tries)
    if body is None:
        return {"name": None, "zone": None, "coords": [], "err": "gave up"}
    m = body.get("map") or {}
    cache[key] = {"name": body.get("name"), "zone": m.get("zone"), "coords": (m.get("coords") or {}).get("0", [])[:3], "err": body.get("error")}
    json.dump(cache, open(CACHE, "w"))
    return cache[key]


def text(s):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", s or ""))).strip()


def quest(i, tries=4):
    """A quest's tooltip: its name, the text under it and the lines under "Requirements". It carries no level,
    XP or NPC id; the quest page has those (mapper.py)."""
    key = str(i)
    if key in qcache:
        return qcache[key]
    body = tooltip("quest", i, tries)
    if body is None:
        return {"name": None, "text": "", "req": [], "err": "gave up"}
    tip = body.get("tooltip") or ""
    head, _, req = tip.partition('<span class="q">Requirements:</span>')
    head = re.sub(r"^<table>.*?</table>", "", head, count=1, flags=re.S)  # the title row
    rows = [text(r).lstrip("- ").strip() for r in re.split(r"<br\s*/?>", req)]
    qcache[key] = {"name": body.get("name"), "text": text(head), "req": [r for r in rows if r], "err": body.get("error")}
    json.dump(qcache, open(QCACHE, "w"), indent=0, ensure_ascii=False)
    return qcache[key]


if __name__ == "__main__":
    args = dict(a.partition("=")[::2] for a in sys.argv[1:])
    if args.get("--quests"):
        ids = [int(x) for x in args["--quests"].split(",") if x.strip()]
        for n, q in enumerate(ids, 1):
            r = quest(q)
            print("  %d/%d %d: %s" % (n, len(ids), q, r.get("name") or r.get("err")), flush=True)
        print(len(qcache))
    elif len(sys.argv) > 1:
        for kind, i in json.load(open(sys.argv[1])):
            get(kind, i)
        print(len(cache))
    else:
        print(__doc__)
