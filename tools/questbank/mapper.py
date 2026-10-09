"""Objective places from Wowhead Forever's quest pages, for the quests the CMaNGOS Classic database
can't place: every quest that exists only in Forever, then the Classic quests whose objectives have no
spawn or POI there.

A quest page (www.wowhead.com/forever/quest=<id>) carries two things we read:
  - its objective list under the title: one row per objective, with the creature, object or item it
    links, its name and the count ("Kobold Vermin slain (10)"); provided items are marked as such
  - its Mapper block, `new Mapper({"objectives": {<AreaTable id>: {"zone", "levels": [[point, ...], ...]}}})`:
    per zone and floor, every point with its kind ("start", "end", "requirement" for a creature or object
    to kill or use, "sourcerequirement" for a creature or chest that drops a quest item, naming the item),
    id, name and spawn coordinates in percent of that zone's map
Pages are kept as they come in tools/.wh-quest-cache/<id>.html (gitignored); a quest Wowhead doesn't
know leaves <id>.404. One request every 3.2 s, across runs (the last request's time sits in the cache
folder); an answer of 403, 429 or 5xx is never cached: the fetch waits and asks again, and gives up on
the run when Wowhead keeps refusing. CloudFront's "Request blocked" page stops the run at once (on
2026-10-04 it answered every script request to www.wowhead.com; nether.wowhead.com still answered).
Fetching is resumable: a cached page is never asked for again. Pages saved from a browser go into the
cache with --import.

  python3 tools/questbank/mapper.py --list                  # which quests --fetch asks for, and how long that takes
  python3 tools/questbank/mapper.py --fetch                 # fetch only, resumable (Ctrl-C is safe)
  python3 tools/questbank/mapper.py --fetch --limit=50      # the first 50 of the list still missing
  python3 tools/questbank/mapper.py --fetch --ids=7,92744   # just these (--force asks again even when cached)
  python3 tools/questbank/mapper.py --fetch --max-requests=10  # never more than 10 requests (retries and redirects count)
  python3 tools/questbank/mapper.py --import=~/Downloads/wh  # quest pages saved from a browser, into the cache
  python3 tools/questbank/mapper.py --parse                 # tools/.wh-quest-cache -> research/questbank/mapper.json
  python3 tools/questbank/mapper.py --show=7                # one quest's parsed record, from its cached page

research/questbank/mapper.json, coordinates as Wowhead gives them (0-100 of that uiMap; gen_data.py
moves the redrawn maps' Classic-frame points with FrameFix and clusters them):
  {"<questId>": {"name": "...",
                 "objectives": [{"kind": "k|c|u|e", "slot": n, "id": n, "name": "...", "count": n, "index": n,
                                 "spots": [{"uiMap": n, "coords": [[x, y], ...], "type": "npc|object", "id": n, "name": "..."}]}],
                 "start": [{"uiMap": n, "coords": [[x, y]], "type": "npc|object", "id": n, "name": "...", "item": "..."}],
                 "end": [...],
                 "provided": [{"id": n, "name": "...", "count": n}],             # only when the quest hands items over
                 "unmapped": [{"area": n, "floor": n, "point": "...", "id": n}]}} # only when Wowhead's zone has no uiMap here
  kind: k kill (a creature), u use or click (an object), or a creature row that isn't a kill (speak with,
        heal: the game counts those as "monster" lines too), c collect (an item: its spots are where its
        sources stand), e anything else (an escort, explore, an event, a row that links nothing); id is the
        creature, object or item (0 for a row that links nothing)
  slot: creature, object and event rows 1-4 in the page's order, item rows 5-8 (4 + the n-th item), as
        CMaNGOS numbers ReqCreatureOrGO and ReqItem; index: the row's place in the page's list (1-based)
  spots: one entry per source and map: the creature or object (for c, the one that drops the item) and its
        Forever positions, the busiest source first. A requirement point goes to the objective its "objective"
        field names (the creature or object the game counts), so kill credit under another creature lands right.
        Wowhead lists every source an item has ever dropped from (quest 33's Tough Wolf Meat names 31 creatures,
        kobolds and spiders among the wolves) and the quest page gives no drop rates: all are kept, and a
        source's share of the points is the only weight. Only the first floor of a zone is placed; dungeons and
        other floors go to unmapped.
  start: where the quest's giver stands, or, for a quest that starts from an item, where that item drops
        (Wowhead's "sourcestart" points, with "item" naming it).
  The cache holds every quest asked for, so mapper.json can hold quests the Classic data places too; the
  reader uses it only where the Classic data has nothing.
"""
import csv, errno, fcntl, html, json, os, re, sys, time, urllib.error, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
RAW = os.path.join(REPO, "research", "questbank")
CACHE = os.path.join(REPO, "tools", ".wh-quest-cache")
OUT = os.path.join(RAW, "mapper.json")
DATA = os.path.join(HERE, "QuestBank", "Data.lua")
BUILD = "1.60.1.70291"
URL = "https://www.wowhead.com/forever/quest=%d"
UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36 foreverrank.com",
      "Accept": "text/html,application/xhtml+xml", "Accept-Language": "en-US,en;q=0.9"}
SPACING = 3.2      # seconds between requests to Wowhead, never less
TRIES = 4          # per quest; a refusal (403, 429, 5xx) waits before the next try
REFUSED_WAIT = 180  # seconds after a 403 or 429 (or what Retry-After asks, if longer)
ERROR_WAIT = 20     # seconds after a 5xx or a network error
GIVE_UP = 3         # quests in a row that end in a refusal stop the run: Wowhead wants us to go away for now
BLOCKED = "Request blocked"  # CloudFront's firewall page (403): the run stops at once, nothing is retried
LAST = os.path.join(CACHE, ".last")   # the time of the last request, so a new run keeps the spacing too
LOCK = os.path.join(CACHE, ".lock")   # one fetcher at a time
# zones Travel.area_map leaves out (continents and the world, the Zephras Isle twin with no area)
NOT_ZONES = {947, 1414, 1415, 1463, 1464, 2665}


# ---------------------------------------------------------------------------
# which quests to fetch
# ---------------------------------------------------------------------------
def load(name, default=None):
    p = os.path.join(RAW, name)
    if not os.path.exists(p):
        return default
    with open(p, encoding="utf-8") as f:
        try:
            return json.load(f)
        except ValueError as e:
            raise SystemExit("can't read %s (%s): is another script writing it right now?" % (p, e))


def catalog():
    """QuestBank's quests: the keys of D.Q in Data.lua."""
    s = open(DATA, encoding="utf-8").read()
    i = s.find("\nD.Q = {")
    j = s.find("\n}", i + 1)
    if i < 0 or j < 0:
        raise SystemExit("no D.Q table in %s (is gen_data.py writing it right now?)" % DATA)
    return {int(k) for k in re.findall(r"^\[(\d+)\]=", s[i:j], re.M)}


def placed():
    """Quests whose objectives the Classic database places, spawns or POI outlines: objectives.py's spots.json,
    the file gen_data reads D.SPOT from (the older objectives.json only while there is no spots.json: gen_data
    no longer reads it, and quests 324 and 1046 have areas there but none in spots.json). Any non-empty list of
    spots or areas in a quest's entry counts."""
    def has(v):
        if isinstance(v, dict):
            return any((k in ("areas", "spots") and isinstance(x, list) and x) or has(x) for k, x in v.items())
        if isinstance(v, list):
            return any(has(x) for x in v)
        return False
    spots = load("spots.json")
    entries = (spots or {}).get("q") or {} if spots is not None else load("objectives.json", {}) or {}
    return {int(k) for k, v in entries.items() if has(v)}


def listed():
    """Quests Wowhead Forever lists (all3, wowhead, extra) or that we have read a page of (det2, det3)."""
    ids = {q["id"] for q in load("all3.json", []) or []}
    for name in ("wowhead.json", "extra.json"):
        for src in (load(name, {}) or {}).values():
            for q in src if isinstance(src, list) else []:
                ids.add(q["id"])
    for name in ("det2.json", "det3.json"):
        ids |= {int(k) for k, d in (load(name, {}) or {}).items() if d.get("status") == 200}
    return ids


def needs_place(c):
    """A Classic quest with something to do out in the world: a creature, object or item to get (other than
    the item it hands you to deliver), or an area to explore. Talk-to and delivery quests need none."""
    if (c.get("special") or 0) & 2:
        return True
    if not c.get("objectives"):
        return False
    items = c.get("items") or []
    return not (items and len(items) == c["objectives"] and all(i == c.get("src") for i, _ in items))


def todo():
    """(Forever-only quests, Classic quests the Classic database can't place, Classic quests that need a
    place but Wowhead Forever doesn't list): the first two are what --fetch asks for, in this order."""
    cat, cm = catalog(), (load("cmangos.json", {}) or {}).get("quests") or {}
    ok, wh = placed(), listed()
    forever = sorted(q for q in cat if str(q) not in cm)
    want = sorted(q for q in cat if str(q) in cm and q not in ok and needs_place(cm[str(q)]))
    return forever, [q for q in want if q in wh], [q for q in want if q not in wh]


def cached(qid):
    return os.path.exists(os.path.join(CACHE, "%d.html" % qid)) or os.path.exists(os.path.join(CACHE, "%d.404" % qid))


def span(seconds):
    m = int(round(seconds / 60.0))
    return "%d h %02d min" % (m // 60, m % 60) if m >= 60 else "%d min" % m


def list_todo():
    forever, classic, unlisted = todo()
    total = 0
    for title, ids in (("Forever-only quests (no CMaNGOS row)", forever),
                       ("Classic quests the CMaNGOS data can't place", classic)):
        miss = [q for q in ids if not cached(q)]
        total += len(miss)
        print("%s: %d, cached %d, to fetch %d" % (title, len(ids), len(ids) - len(miss), len(miss)))
        if miss:
            print("  " + ",".join(str(q) for q in miss))
    print("Left out: %d Classic quests that need a place but Wowhead Forever doesn't list (nobody has met them yet)" % len(unlisted))
    print("To fetch: %d pages, about %s at %.1f s each" % (total, span(total * SPACING), SPACING))


# ---------------------------------------------------------------------------
# fetching
# ---------------------------------------------------------------------------
class NoRedirect(urllib.request.HTTPRedirectHandler):
    """A redirect is a second request: hand it back so it waits its turn like any other."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


OPENER = urllib.request.build_opener(NoRedirect)


def pace():
    """Wait until SPACING seconds have passed since the last request (this run's or an earlier one's)."""
    try:
        last = float(open(LAST).read().strip() or 0)
    except (OSError, ValueError):
        last = 0.0
    wait = SPACING - (time.time() - last)
    if wait > 0:
        time.sleep(min(wait, SPACING))
    with open(LAST, "w") as f:
        f.write("%.3f" % time.time())


MAX_REQUESTS = [None]  # --max-requests: a hard cap on this run's requests, retries and redirects included
SENT = [0]


class Budget(Exception):
    pass


def request(url):
    """(status, body, headers) of one GET; no redirects followed."""
    if MAX_REQUESTS[0] is not None and SENT[0] >= MAX_REQUESTS[0]:
        raise Budget()
    pace()
    SENT[0] += 1
    try:
        r = OPENER.open(urllib.request.Request(url, headers=UA), timeout=30)
        return r.status, r.read().decode("utf-8", "replace"), r.headers
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", "replace")
        except Exception:
            pass
        return e.code, body, e.headers
    except Exception as e:  # network trouble: no answer at all
        return None, str(e), {}


def write(path, text):
    """Whole or not at all: an interrupted run never leaves half a page."""
    tmp = path + ".part"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def is_page(qid, body):
    return ('/forever/quest=%d/' % qid) in body or ('/forever/quest=%d"' % qid) in body


def fetch(qid, force=False):
    """Fetch one quest page into the cache. Returns "cached", "ok", "missing" (404, kept as <id>.404),
    "blocked" (the CDN's firewall page), "refused" (403, 429, 5xx or no answer, TRIES times),
    "odd" (a 200 that isn't the quest's page) or "error"."""
    if cached(qid) and not force:
        return "cached"
    url = URL % qid
    hops = 0
    for attempt in range(TRIES):
        status, body, headers = request(url)
        if status in (301, 302, 303, 307, 308) and hops < 2:
            new = urllib.parse.urljoin(url, headers.get("Location") or "")
            if urllib.parse.urlparse(new).netloc != urllib.parse.urlparse(URL).netloc or "/forever/" not in new:
                print("  %d: redirected away to %s; not followed" % (qid, new), flush=True)
                return "error"
            url, hops = new, hops + 1
            continue
        if status == 200 and is_page(qid, body):
            write(os.path.join(CACHE, "%d.html" % qid), body)
            if os.path.exists(os.path.join(CACHE, "%d.404" % qid)):
                os.remove(os.path.join(CACHE, "%d.404" % qid))
            return "ok"
        if status == 404:
            write(os.path.join(CACHE, "%d.404" % qid), "HTTP 404 at %d\n" % int(time.time()))
            if os.path.exists(os.path.join(CACHE, "%d.html" % qid)):  # the latest answer wins, as a 200 drops a .404
                os.remove(os.path.join(CACHE, "%d.html" % qid))
                print("  %d: the cached page now answers 404; dropped" % qid, flush=True)
            return "missing"
        if status == 200:  # a page, but not this quest's (a challenge, a front page): not kept, not asked again now
            t = re.search(r"<title>(.*?)</title>", body, re.S)
            print("  %d: an answer that isn't the quest page (%s); skipped" % (qid, text(t.group(1))[:60] if t else "no title"), flush=True)
            return "odd"
        if status == 403 and BLOCKED in body:
            # the CDN's firewall turns this client away (2026-10-04: every script request to www.wowhead.com,
            # while nether.wowhead.com's tooltips still answer); waiting a few minutes doesn't lift it
            return "blocked"
        if status in (403, 429) or status is None or status >= 500:
            if attempt + 1 == TRIES:
                print("  %d: %s, giving up on it" % (qid, "HTTP %s" % status if status else body[:80]), flush=True)
                break
            ra = headers.get("Retry-After") if headers else None
            wait = REFUSED_WAIT if status in (403, 429) else ERROR_WAIT
            if ra and ra.isdigit():
                wait = max(wait, min(int(ra), 900))
            print("  %d: %s, waiting %d s" % (qid, "HTTP %s" % status if status else body[:80], wait), flush=True)
            time.sleep(wait)
            continue
        print("  %d: HTTP %s, skipped" % (qid, status), flush=True)
        return "error"
    return "refused"


def fetch_all(ids, force=False, limit=None):
    os.makedirs(CACHE, exist_ok=True)
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as e:
        if e.errno in (errno.EAGAIN, errno.EACCES):
            raise SystemExit("another mapper.py --fetch is running (%s)" % LOCK)
        raise
    todo_ids = [q for q in ids if force or not cached(q)]
    if limit is not None:
        todo_ids = todo_ids[:limit]
    print("fetching %d of %d quest pages, about %s at %.1f s each" % (len(todo_ids), len(ids), span(len(todo_ids) * SPACING), SPACING), flush=True)
    counts, refused_run, t0 = {}, 0, time.time()
    for n, qid in enumerate(todo_ids, 1):
        try:
            r = fetch(qid, force)
        except Budget:
            print("stopped at %d requests (--max-requests)" % SENT[0], flush=True)
            break
        counts[r] = counts.get(r, 0) + 1
        refused_run = refused_run + 1 if r in ("refused", "odd") else 0
        if r == "blocked":
            print("www.wowhead.com's CDN blocks this client (CloudFront: \"Request blocked\", HTTP 403); stopping. "
                  "Nothing was cached for %d. Pages saved from a browser can go in with --import=<folder>." % qid, flush=True)
            break
        if refused_run >= GIVE_UP:
            print("Wowhead refused %d quests in a row; stopping. Run again later: cached pages are kept." % refused_run, flush=True)
            break
        if n % 25 == 0 or n == len(todo_ids):
            left = (time.time() - t0) / n * (len(todo_ids) - n)
            print("  %d/%d  %s  (about %s left)" % (n, len(todo_ids), " ".join("%s %d" % kv for kv in sorted(counts.items())), span(left)), flush=True)
    print("requests sent: %d" % SENT[0], flush=True)
    return counts


# ---------------------------------------------------------------------------
# parsing
# ---------------------------------------------------------------------------
def area_maps():
    """AreaTable id -> uiMap, as Travel.area_map builds it (UiMapAssignment, first row of each map)."""
    maps = {}
    with open(os.path.join(REPO, "research", "wago", BUILD, "UiMapAssignment.csv"), encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["OrderIndex"] != "0" or r["UiMapID"] in ("947",):
                continue
            maps[int(r["UiMapID"])] = int(r["AreaID"])
    return {a: m for m, a in maps.items() if a and m not in NOT_ZONES}


def mapper_block(page):
    """The object passed to `new Mapper(...)`, or None."""
    i = page.find("new Mapper(")
    if i < 0:
        return None
    try:
        obj, _ = json.JSONDecoder().raw_decode(page, i + len("new Mapper("))
        return obj
    except ValueError:
        return None


TAG = re.compile(r"<[^>]+>")
# relative as Wowhead sends them; absolute in a page a browser saved as "Webpage, Complete" (Firefox writes them so)
LINK = re.compile(r'<a href="(?:https?://www\.wowhead\.com)?/forever/(npc|object|item|spell|zone|quest)=(\d+)[^"]*"[^>]*>(.*?)</a>', re.S)


def text(s):
    return re.sub(r"\s+", " ", html.unescape(TAG.sub(" ", s)).replace("\xa0", " ")).strip()


# a row that links a creature: the game shows it as a "monster" line whatever its words (CMaNGOS counts speak-with and
# heal rows as kill credit), so it is k, or u when it isn't a kill; only an escort is the game's "event" line (the
# escort quests 155, 219, 309, 836 carry the event flag and no creature objective), so it stays e
KILL = re.compile(r"\b(slain|killed|defeated|destroyed|exterminated|kill|slay|defeat|destroy)\b", re.I)
ESCORT = re.compile(r"\b(escort|escorted|protect|protected)\b", re.I)


def objective_rows(page):
    """The objective list under the title: [{type, id, name, count, text, provided}] in the page's order."""
    i = page.find('<h1 class="heading-size-1">')
    if i < 0:
        return []
    ends = [k for k in (page.find('id="data.mapper.objectiveTerms"', i), page.find("new Mapper(", i),
                        page.find('<h2 class="heading-size-3">', i)) if k > 0]
    region = page[i:min(ends)] if ends else page[i:]
    out, provided = [], False
    # a heading between tables ("Provided item:") marks the rows after it
    for part in re.split(r"(<table class=\"icon-list\">.*?</table>)", region, flags=re.S):
        if not part.startswith('<table class="icon-list">'):
            if re.search(r"Provided items?\s*:?\s*$", text(part), re.I):
                provided = True
            continue
        for row in re.findall(r"<tr\b.*?</tr>", part, re.S):
            q = re.search(r'data-icon-list-quantity="(\d+)"', row)
            td = re.search(r"<td\b[^>]*>(.*?)</td>", row, re.S)
            body = td.group(1) if td else row
            label = re.sub(r"\(\s*\d+\s*\)\s*$", "", text(body)).strip()
            m = LINK.search(body)
            out.append({"type": m.group(1) if m else None, "id": int(m.group(2)) if m else 0,
                        "name": text(m.group(3)) if m else label, "count": int(q.group(1)) if q else 1, "text": label,
                        "provided": provided or bool(re.search(r"\(Provided\)|^Provided item", label, re.I))})
    return out


def coords(e):
    pts = e.get("coords") or ([e["coord"]] if e.get("coord") else [])
    return [[round(float(p[0]), 1), round(float(p[1]), 1)] for p in pts if isinstance(p, list) and len(p) >= 2]


POINT_TYPE = {1: "npc", 2: "object", 3: "item"}


def parse_page(qid, page, amap):
    rows = objective_rows(page)
    t = re.search(r'<h1 class="heading-size-1">(.*?)</h1>', page, re.S)
    rec = {"name": text(t.group(1)) if t else None, "objectives": [], "start": [], "end": []}
    objs, n_item, n_other = [], 0, 0
    for r in rows:
        if r["provided"]:
            rec.setdefault("provided", []).append({"id": r["id"] if r["type"] == "item" else 0, "name": r["name"], "count": r["count"]})
            continue
        if r["type"] == "item":
            n_item += 1
            kind, slot = "c", 4 + n_item
        else:
            n_other += 1
            if r["type"] == "object":
                kind = "u"
            elif r["type"] == "npc":
                kind = "k" if KILL.search(r["text"]) or r["text"] == r["name"] else "e" if ESCORT.search(r["text"]) else "u"
            else:
                kind = "e"
            slot = n_other
        o = {"kind": kind, "slot": slot if slot <= (8 if kind == "c" else 4) else 0, "id": r["id"] if r["type"] in ("npc", "object", "item") else 0,
             "name": r["name"], "count": r["count"], "index": len(objs) + 1, "spots": []}
        o["_type"], o["_text"] = r["type"], r["text"].lower()
        o["_obj"] = o["id"] if r["type"] in ("npc", "object") else 0
        objs.append(o)

    def find(e):
        """The objective a mapper point belongs to: the one its "objective" names (the creature or object the game
        counts, so kill credit under another creature lands right), else the same creature or object, else the name."""
        typ = POINT_TYPE.get(e.get("type"))
        if e.get("point") == "sourcerequirement":
            item = (e.get("item") or "").strip().lower()
            cands = [o for o in objs if o["kind"] == "c"]
            hit = [o for o in cands if o["name"].lower() == item]
            return hit[0] if hit else (cands[0] if len(cands) == 1 else None)
        cands = [o for o in objs if o["kind"] != "c"]
        want = e.get("objective") or 0
        hit = [o for o in cands if want and o["_obj"] == want]
        hit = hit or [o for o in cands if o["_type"] == typ and o["id"] == e.get("id")]
        name = (e.get("name") or "").lower()
        if not hit and name:
            hit = [o for o in cands if o["name"].lower() == name] or [o for o in cands if not want and name in o["_text"]]
        rows = [o for o in cands if o["index"]]  # the page's own rows, not a point's objective made up below
        return hit[0] if hit else (rows[0] if len(rows) == 1 else None)

    mp = mapper_block(page) or {}
    other = {}
    for area, z in sorted((mp.get("objectives") or {}).items(), key=lambda kv: int(kv[0])):
        area = int(area)
        levels = z.get("levels") or []
        if isinstance(levels, dict):
            levels = [levels[k] for k in sorted(levels, key=int)]
        for floor, level in enumerate(levels):
            ui = amap.get(area) if floor == 0 else None
            for e in level or []:
                pts = coords(e)
                if not pts:
                    continue
                if not ui:
                    rec.setdefault("unmapped", []).append({"area": area, "floor": floor, "point": e.get("point"), "id": e.get("id")})
                    continue
                spot = {"uiMap": ui, "coords": pts, "type": POINT_TYPE.get(e.get("type"), str(e.get("type"))), "id": e.get("id"), "name": e.get("name")}
                point = e.get("point")
                if point in ("start", "end"):
                    rec[point].append(spot)
                elif point == "sourcestart":
                    # a quest that starts from an item: where that item drops, which is what gen_data's D.START reads
                    # from "start" (such a quest has no giver to point at)
                    if e.get("item"):
                        spot["item"] = e["item"]
                    rec["start"].append(spot)
                elif point in ("requirement", "sourcerequirement"):
                    o = find(e)
                    if o is None:
                        # a point the list doesn't show (a kill credit under another name): its own objective, one per
                        # objective Wowhead names
                        src = point == "sourcerequirement"  # an item the list doesn't show: its id is unknown here
                        o = {"kind": "c" if src else ("u" if spot["type"] == "object" else "k"), "slot": 0,
                             "id": 0 if src else (e.get("id") or 0), "name": e.get("item") if src else e.get("name"),
                             "count": 0, "index": 0, "spots": [], "_type": "item" if src else spot["type"], "_text": "",
                             "_obj": 0 if src else (e.get("objective") or 0)}
                        objs.append(o)
                    o["spots"].append(spot)
                else:
                    other.setdefault(point, []).append(spot)
    for o in objs:
        for k in ("_type", "_text", "_obj"):
            o.pop(k, None)
        # the busiest source first: a quest page gives no drop rates, and Wowhead names every creature an item ever
        # dropped from (quest 33's Tough Wolf Meat: Mangy Wolf 214 points, Kobold Worker 31), so a source's share of
        # the points (its coords against the objective's) is the only weight there is
        o["spots"].sort(key=lambda s: -len(s["coords"]))
    rec["start"].sort(key=lambda s: -len(s["coords"]))
    rec["objectives"] = objs
    if other:
        rec["other"] = other
    return rec


def parse_all():
    amap = load_amap()
    out, stats = {}, {"pages": 0, "missing": 0, "no mapper": 0, "objectives": 0, "with spots": 0, "unmapped": 0}
    points = {}
    for name in sorted(os.listdir(CACHE), key=lambda n: (len(n), n)) if os.path.isdir(CACHE) else []:
        if name.endswith(".404"):
            stats["missing"] += 1
            continue
        if not name.endswith(".html") or not name[:-5].isdigit():
            continue
        qid = int(name[:-5])
        if os.path.exists(os.path.join(CACHE, "%d.404" % qid)):  # left by an older mapper.py: the 404 came later
            continue
        page = open(os.path.join(CACHE, name), encoding="utf-8").read()
        stats["pages"] += 1
        if "new Mapper(" not in page:
            stats["no mapper"] += 1
        rec = parse_page(qid, page, amap)
        out[str(qid)] = rec
        stats["objectives"] += len(rec["objectives"])
        stats["with spots"] += sum(1 for o in rec["objectives"] if o["spots"])
        stats["unmapped"] += len(rec.get("unmapped", []))
        for k in rec.get("other", {}):
            points[k] = points.get(k, 0) + 1
    write(OUT, json.dumps(out, separators=(",", ":"), ensure_ascii=False))
    print("wrote %s: %d quests" % (OUT, len(out)))
    print("  " + ", ".join("%s %d" % kv for kv in stats.items()))
    if points:
        print("  other mapper point kinds (quests): " + ", ".join("%s %d" % kv for kv in sorted(points.items())))
    return out


def import_pages(folder):
    """Quest pages saved from a browser (the page source as Wowhead sends it) into the cache. Each file's quest
    comes from its canonical link, so the file names don't matter."""
    os.makedirs(CACHE, exist_ok=True)
    n = 0
    for name in sorted(os.listdir(folder)):
        if not name.lower().endswith((".html", ".htm")):
            continue
        page = open(os.path.join(folder, name), encoding="utf-8", errors="replace").read()
        m = re.search(r'<link rel="canonical" href="https://www\.wowhead\.com/forever/quest=(\d+)', page)
        if not m or '<h1 class="heading-size-1">' not in page:
            print("  %s: not a Wowhead Forever quest page; skipped" % name)
            continue
        qid = int(m.group(1))
        rows = objective_rows(page)
        if rows and not any(r["type"] for r in rows):
            # every row unlinked: a save that rewrote the links in a way LINK doesn't read, or a quest of events only
            print("  %s (quest %d): %d objective rows and none links a creature, object or item; check --show=%d"
                  % (name, qid, len(rows), qid))
        write(os.path.join(CACHE, "%d.html" % qid), page)
        if os.path.exists(os.path.join(CACHE, "%d.404" % qid)):
            os.remove(os.path.join(CACHE, "%d.404" % qid))
        n += 1
    print("imported %d quest pages into %s" % (n, CACHE))


_AMAP = None


def load_amap():
    global _AMAP
    if _AMAP is None:
        _AMAP = area_maps()
    return _AMAP


def show(qid):
    path = os.path.join(CACHE, "%d.html" % qid)
    if not os.path.exists(path):
        raise SystemExit("%d is not cached%s" % (qid, " (Wowhead doesn't know it)" if cached(qid) else ""))
    rec = parse_page(qid, open(path, encoding="utf-8").read(), load_amap())
    print(json.dumps({str(qid): rec}, indent=1, ensure_ascii=False))


def main(argv):
    opts = {}
    for a in argv:
        k, _, v = a.partition("=")
        opts[k] = v
    if "--list" in opts:
        list_todo()
    if "--fetch" in opts:
        if opts.get("--max-requests"):
            MAX_REQUESTS[0] = int(opts["--max-requests"])
        if opts.get("--ids"):
            ids = [int(x) for x in opts["--ids"].split(",") if x.strip()]
        else:
            forever, classic, _ = todo()
            ids = forever + classic
        fetch_all(ids, force="--force" in opts, limit=int(opts["--limit"]) if opts.get("--limit") else None)
    if opts.get("--import"):
        import_pages(os.path.expanduser(opts["--import"]))
    if "--parse" in opts:
        parse_all()
    if opts.get("--show"):
        for x in opts["--show"].split(","):
            show(int(x))
    if not any(k in opts for k in ("--list", "--fetch", "--import", "--parse", "--show")):
        print(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
