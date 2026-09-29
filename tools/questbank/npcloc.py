"""NPC and object positions from Wowhead Forever tooltips (nether.wowhead.com), cached in
research/questbank/npcloc.json. About one request a second; a rate-limit answer (403, 429, 5xx) is
never cached: the fetch waits and tries again."""
import json, os, sys, time, urllib.error, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(os.path.dirname(os.path.dirname(HERE)), "research", "questbank", "npcloc.json")
cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
SPACING = 2.5


def get(kind, i, tries=4):
    key = "%s/%s" % (kind, i)
    if key in cache:
        return cache[key]
    url = "https://nether.wowhead.com/forever/tooltip/%s/%s?dataEnv=16" % (kind, i)
    for attempt in range(tries):
        try:
            body = json.loads(urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=30).read())
            break
        except urllib.error.HTTPError as e:
            if e.code == 404:
                body = {"error": "HTTP Error 404: Not Found"}
                break
            print("  %s: HTTP %d, waiting" % (key, e.code), flush=True)
            time.sleep(180 if e.code in (403, 429) else 20)
        except Exception as e:
            print("  %s: %s, waiting" % (key, e), flush=True)
            time.sleep(20)
    else:
        return {"name": None, "zone": None, "coords": [], "err": "gave up"}
    m = body.get("map") or {}
    cache[key] = {"name": body.get("name"), "zone": m.get("zone"), "coords": (m.get("coords") or {}).get("0", [])[:3], "err": body.get("error")}
    json.dump(cache, open(CACHE, "w"))
    time.sleep(SPACING)
    return cache[key]


if __name__ == "__main__":
    ids = json.load(open(sys.argv[1]))
    for kind, i in ids:
        get(kind, i)
    print(len(cache))
