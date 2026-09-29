import json, os, sys, time, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(os.path.dirname(os.path.dirname(HERE)), "research", "questbank", "npcloc.json")
cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
def get(kind, i):
    key = "%s/%s" % (kind, i)
    if key in cache: return cache[key]
    url = "https://nether.wowhead.com/forever/tooltip/%s/%s?dataEnv=16" % (kind, i)
    try:
        body = json.loads(urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=30).read())
    except Exception as e:
        body = {"error": str(e)}
    m = body.get("map") or {}
    cache[key] = {"name": body.get("name"), "zone": m.get("zone"), "coords": (m.get("coords") or {}).get("0", [])[:3], "err": body.get("error")}
    json.dump(cache, open(CACHE, "w"))
    time.sleep(0.35)
    return cache[key]
if __name__ == "__main__":
    ids = json.load(open(sys.argv[1]))
    for kind, i in ids: get(kind, i)
    print(len(cache))
