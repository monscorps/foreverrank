#!/usr/bin/env python3
"""The faces of the bosses in Forever's own dungeons, which the Classic database has never heard of: each boss's NPC
id and creature display id from its Wowhead Forever page (dataEnv 16), found by the NPC id players' games recorded
(codex/loot.json) or else by a search for its name among the NPCs new in Forever that Wowhead places in that dungeon
(or nowhere). gen_data.py gives them to the Dungeon Journal (b.d draws the face, b.c the loot panel's model when there
is no display id).

  python3 tools/questbank/forever_npcs.py            # the bosses not read yet -> research/questbank/forever_npcs.json
  python3 tools/questbank/forever_npcs.py --refresh  # read them all again

{name: {"npc": NPC id, "display": display id}}. A name Wowhead doesn't know, or knows more than once there, is left
out and printed, so the next run asks again. Requests keep 3.2 s apart, shared with npcloc.py and mapper.py
(tools/.wh-quest-cache/.last); a refusal (403, 429) is never worked around: the script stops and says so.
"""
import html, json, os, re, sys, urllib.error, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from npcloc import pace  # noqa: E402

OUT = os.path.join(REPO, "research", "questbank", "forever_npcs.json")
UA = {"User-Agent": "foreverrank.com datamine (github.com/monscorps/foreverrank)"}
# Forever's own dungeons in codex/loot.json, and the zone Wowhead files their NPCs under (Dalaran's: Alterac, 36)
DUNGEONS = {"City of Dalaran": 36, "Excavation Site: Wetlands": 16732, "Ruins of Lordaeron": 16611, "Hall of Thanes": 16919}


class Refused(Exception):
    pass


def page(path):
    """A Wowhead Forever page's HTML, or None for a 404."""
    pace()
    url = "https://www.wowhead.com/forever/" + path
    try:
        return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30).read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise Refused("%s: HTTP %d" % (url, e.code))


def search(name, zone):
    """The NPC id of the one NPC called `name` that is new in Forever (first seen in patch 16001 or later) and that
    Wowhead places in `zone` or nowhere; None when there is none or more than one (a Classic namesake stays out)."""
    body = page("npcs/name:" + urllib.parse.quote(name)) or ""
    m = re.search(r'new Listview\(\{.*?"id":"npcs".*?"data":(\[.*?\])\s*,\s*"extraCols"', body, re.S)
    rows = [r["id"] for r in (json.loads(m.group(1)) if m else []) if r.get("name", "").lower() == name.lower()
            and (r.get("firstseenpatch") or 0) >= 16001 and (r.get("location") or [zone]) in ([zone], [])]
    return rows[0] if len(rows) == 1 else None


def model(npc):
    """The NPC's name and the display id its page shows in its 3D viewer (None where it shows none)."""
    body = page("npc=%d" % npc) or ""
    name, shown = re.search(r'<h1 class="heading-size-1">([^<]*)</h1>', body), re.search(r'data-mv-display-id="(\d+)"', body)
    return html.unescape(name.group(1)) if name else None, int(shown.group(1)) if shown else None


def main():
    refresh = "--refresh" in sys.argv
    known = {} if refresh or not os.path.exists(OUT) else json.load(open(OUT))
    loot = json.load(open(os.path.join(REPO, "codex", "loot.json")))
    missed = []
    try:
        for d in loot.get("dungeons", []):
            zone = DUNGEONS.get(d.get("name"))
            for b in d.get("bosses", []) if zone else []:
                if b.get("kind") in ("trash", "object") or b["name"] in known:
                    continue
                npc = (b.get("games") or {}).get("npc") or search(b["name"], zone)
                name, shown = model(npc) if npc else (None, None)
                if shown:
                    known[b["name"]] = {"npc": npc, "display": shown}
                    # players' games tie a boss to the NPC killed at the same time: Wowhead may name it otherwise
                    print("  %s: npc %d%s, display %d" % (b["name"], npc, "" if name == b["name"] else " (Wowhead: %s)" % name, shown), flush=True)
                else:
                    missed.append("%s: %s" % (d["name"], b["name"]))
    except Refused as e:
        print("Wowhead refused (%s); stopping, what was read is kept" % e)
    json.dump(known, open(OUT, "w"), indent=1, sort_keys=True)
    print("%d bosses of Forever's own dungeons with a display id -> %s" % (len(known), os.path.relpath(OUT, REPO)))
    if missed:
        print("not found on Wowhead Forever (%d):" % len(missed))
        for m in missed:
            print("  " + m)


if __name__ == "__main__":
    main()
