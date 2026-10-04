#!/usr/bin/env python3
"""Pull ForeverProbe and QuestBank uploads from the Worker and merge their discoveries.

What players' addons noted in game (QuestBankDB.disc: quests, the NPCs who give and take them,
where those stand, the XP each quest showed, which quests an NPC offers at what level, chain
steps, and where each objective of a quest moved on) arrives at the Worker as three kinds of
upload: an FPROBE2 export, a ForeverProbe.lua SavedVariables file (its ["questbank"] block
carries the same notes), or a QuestBank.lua SavedVariables file. QuestBank 3.6.0 also keeps
QuestBankDB.game on the Forever client: the spells and the bag and gear items of each class and
race played, and item tooltips (what ForeverProbe used to note). This tool pulls the new rows,
keeps each decoded body under research/probe/, and merges every discovery into
research/questbank/disc.json, which gen_data.py reads: a quest seen in Forever loses its
"Classic only" flag, quests seen in game that are not in the catalog at all are listed in
GAPS.md, and where objectives ticked become the map's "seen in players' games" spots. Votes are
kept, not winners: disc.json records how many uploads reported each XP value, each NPC position
and each objective spot. QuestBank also runs on Classic Era: notes from any client but Forever
are left out.

  python3 tools/probe_pull.py                      # pull what is new, merge, report
  python3 tools/probe_pull.py --merge FILE...       # merge local files (a friend's QuestBank.lua) without the Worker
  python3 tools/probe_pull.py --rebuild             # start disc.json over from the uploads kept in research/probe (no pull)
  python3 tools/probe_pull.py --parse FILE          # print a SavedVariables file or export as JSON
  python3 tools/probe_pull.py --selftest            # the parser and the merge against tools/fixtures/probe/

The admin key is read from worker/.probe-admin-key (gitignored) or the PROBE_ADMIN_KEY
environment variable; it is never printed. Nothing here writes to the Worker.
"""
import argparse, base64, datetime, gzip, hashlib, json, os, re, sys, urllib.error, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
ENDPOINT = "https://foreverrank.andustemme.workers.dev"
KEY_FILE = os.path.join(REPO, "worker", ".probe-admin-key")
OUT = os.path.join(REPO, "research", "questbank", "disc.json")
RAW_DIR = os.path.join(REPO, "research", "probe")


# ----------------------------------------------------------------------------- Lua SavedVariables
# WoW writes one assignment per saved variable: NAME = { ["key"] = value, [7] = { ... }, "positional", }
# with strings in double quotes (escapes \n \r \t \\ \" and \ddd), numbers, true/false/nil, and
# "-- [n]" comments after positional entries. That is the whole grammar this reads.
_TOKEN = re.compile(r"""
  (?P<ws>\s+|--[^\n]*) |
  (?P<str>"(?:[^"\\]|\\.)*") |
  (?P<num>-?(?:\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)) |
  (?P<name>[A-Za-z_][A-Za-z0-9_]*) |
  (?P<punct>[{}\[\]=,;])
""", re.X)
_ESC = {"n": "\n", "r": "\r", "t": "\t", "\\": "\\", '"': '"', "'": "'", "a": "\a", "b": "\b", "f": "\f", "v": "\v", "\n": "\n"}


def _unescape(body):
    out, i = [], 0
    while i < len(body):
        c = body[i]
        if c != "\\":
            out.append(c); i += 1; continue
        i += 1
        if i >= len(body):
            break
        c = body[i]
        if c.isdigit():
            j = i
            while j < len(body) and j - i < 3 and body[j].isdigit():
                j += 1
            out.append(chr(int(body[i:j]))); i = j
        else:
            out.append(_ESC.get(c, c)); i += 1
    return "".join(out)


class LuaError(ValueError):
    pass


class _Parser:
    def __init__(self, text):
        self.toks = []
        pos = 0
        while pos < len(text):
            m = _TOKEN.match(text, pos)
            if not m:
                raise LuaError("unexpected character %r at %d" % (text[pos:pos + 20], pos))
            pos = m.end()
            if m.lastgroup == "ws":
                continue
            self.toks.append((m.lastgroup, m.group()))
        self.i = 0

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else (None, None)

    def take(self, kind=None, val=None):
        k, v = self.peek()
        if k is None or (kind and k != kind) or (val is not None and v != val):
            raise LuaError("expected %s %s, got %s %r (token %d)" % (kind, val or "", k, v, self.i))
        self.i += 1
        return v

    def file(self):
        out = {}
        while self.peek()[0] is not None:
            name = self.take("name")
            self.take("punct", "=")
            out[name] = self.value()
        return out

    def value(self):
        k, v = self.peek()
        if k == "punct" and v == "{":
            return self.table()
        if k == "str":
            self.i += 1
            return _unescape(v[1:-1])
        if k == "num":
            self.i += 1
            return int(v) if re.fullmatch(r"-?\d+", v) else float(v)
        if k == "name":
            self.i += 1
            if v == "true":
                return True
            if v == "false":
                return False
            if v == "nil":
                return None
            raise LuaError("bare name %r is not a value" % v)
        raise LuaError("unexpected %s %r" % (k, v))

    def table(self):
        self.take("punct", "{")
        out, n = {}, 0
        while True:
            k, v = self.peek()
            if k == "punct" and v == "}":
                self.i += 1
                break
            if k == "punct" and v == "[":
                self.i += 1
                key = self.value()
                self.take("punct", "]")
                self.take("punct", "=")
                out[key] = self.value()
            elif k == "name" and self.i + 1 < len(self.toks) and self.toks[self.i + 1] == ("punct", "="):
                key = self.take("name")
                self.take("punct", "=")
                out[key] = self.value()
            else:
                n += 1
                out[n] = self.value()
            k, v = self.peek()
            if k == "punct" and v in ",;":
                self.i += 1
        return out


def _jsonable(v):
    """Lua tables with keys 1..n become lists; other keys become strings, as JSON has them."""
    if not isinstance(v, dict):
        return v
    if v and all(isinstance(k, int) for k in v) and sorted(v) == list(range(1, len(v) + 1)):
        return [_jsonable(v[i]) for i in range(1, len(v) + 1)]
    out = {}
    for k, x in v.items():
        if isinstance(k, float) and k == int(k):
            k = int(k)
        out[str(k)] = _jsonable(x)
    return out


def parse_savedvariables(text):
    """The file's variables as JSON-shaped Python: {"QuestBankDB": {...}}."""
    return _jsonable(_Parser(text.lstrip("﻿")).file())


# ------------------------------------------------------------------------------------ the uploads
def decode(text):
    """(kind, data): what an upload holds. data is the JSON-shaped content; disc(data) finds the notes."""
    t = text.lstrip("﻿").strip()
    if re.match(r"^FPROBE[12]:", t):
        return "export", json.loads(t[t.index(":") + 1:])
    if re.match(r"^ForeverProbeDB\s*=", t):
        return "probe-savedvars", parse_savedvariables(t)["ForeverProbeDB"]
    if re.match(r"^QuestBankDB\s*=", t):
        return "questbank-savedvars", parse_savedvariables(t)["QuestBankDB"]
    raise ValueError("not an FPROBE export or a ForeverProbe/QuestBank SavedVariables file")


def disc_of(kind, data):
    """QuestBankDB.disc wherever the upload keeps it, or None."""
    if not isinstance(data, dict):
        return None
    if kind == "questbank-savedvars":
        d = data.get("disc")
    else:
        qb = data.get("questbank")
        d = qb.get("disc") if isinstance(qb, dict) else None
    if isinstance(d, dict) and d.get("v") == 1 and isinstance(d.get("q"), dict):
        return d
    return None


# ------------------------------------------------------------------------------- which client wrote it
# QuestBank also loads on Classic Era (Interface 11507), and the uploader watches every game folder: what an Era
# character saw must not count as seen in Forever. The Forever client's interface numbers are 16xxx.
FIRST_FOREVER_BUILD = 69876  # the oldest Forever build datamined (research/wago/1.60.1.69876): a lower build is another client


def forever_iface(v):
    """True for a Forever interface number, False for another client's, None when there is none."""
    try:
        v = int(v)
    except (TypeError, ValueError):
        return None
    return 16000 <= v <= 16999


def from_forever(data):
    """Whether a QuestBank.lua's notes (disc, turnins, live), or ForeverProbe's copy of the disc, came from the Forever
    client. The interface stamp decides (disc.iface from QuestBank 3.6.0, diag.addons.iface from 3.5.2). An unstamped
    file goes by its build; with no build either it is kept, since every unstamped upload so far came from Forever."""
    disc = data.get("disc") if isinstance(data.get("disc"), dict) else {}
    diag = data.get("diag") if isinstance(data.get("diag"), dict) else {}
    addons = diag.get("addons") if isinstance(diag.get("addons"), dict) else {}
    for v in (disc.get("iface"), addons.get("iface")):
        if forever_iface(v) is not None:
            return forever_iface(v)
    try:
        return int(str(disc.get("build") or addons.get("build")).split(".")[-1]) >= FIRST_FOREVER_BUILD
    except (TypeError, ValueError):
        return True


# --------------------------------------------------------------------------------------- the merge
def empty():
    return {"meta": {"last_id": 0, "uploads": 0, "with_notes": 0, "sources": {}, "pulled": None},
            "q": {}, "npc": {}, "offer": {}, "chain": {}, "item": {}, "seen": {}, "seen_at": {}, "os": {}}


# ----------------------------------------------------------------------------------- the XP seen
CUT_DAY = "2026-10-02"  # Blizzard's dungeon-XP cut landed with build 70170 late on 2026-10-01; hand-ins dated before this day are pre-cut


def merge_seen(acc, kind, data):
    """What the game paid: QuestBankDB.turnins (every hand-in, with the XP the event reported) and the
    player's own quest-window readings in QuestBankDB.live (src npc/log/turnin; party-shared ones are
    someone else's reading and are left out). Votes per quest, keyed "xp:level:build:src:era" where
    build is the client build the upload ran on (disc.build) and era is QuestBankDB.liveEra (the
    addon's purge of pre-cut readings: 0 means the table may still hold them; hand-ins carry 9, each
    one is dated). gen_data.py decides what counts."""
    if kind != "questbank-savedvars" or not isinstance(data, dict):
        return 0
    disc = data.get("disc") if isinstance(data.get("disc"), dict) else {}
    try:
        build = int(disc.get("build") or 0)
    except (TypeError, ValueError):
        build = 0
    try:
        era = int(data.get("liveEra") or 0)
    except (TypeError, ValueError):
        era = 0
    seen = acc.setdefault("seen", {})
    counted = acc.setdefault("seen_at", {})  # "qid:at" of hand-ins already counted: the same growing file comes back upload after upload
    n = 0

    def vote(qid, xp, lvl, src, e, at=None):
        nonlocal n
        try:
            qid, xp, lvl = int(qid), int(xp), int(lvl or 0)
        except (TypeError, ValueError):
            return
        if qid <= 0 or xp <= 0:
            return
        # a dated row speaks for itself: a hand-in before the cut is pre-cut whatever build uploaded it (the client
        # writes the build at login, and QuestBankDB.turnins is never pruned); build 0 marks it
        b = 0 if (isinstance(at, str) and at[:10] < CUT_DAY) else build
        key = "%d:%d:%d:%s:%d" % (xp, lvl, b, src, e)
        q = seen.setdefault(str(qid), {})
        q[key] = q.get(key, 0) + 1
        n += 1

    mine = set()
    for t in data.get("turnins") or []:
        if isinstance(t, dict) and not t.get("hidden") and isinstance(t.get("xp"), (int, float)):
            tag = "%s:%s" % (t.get("id"), t.get("at"))
            try:
                mine.add((int(t.get("id")), int(t["xp"])))
            except (TypeError, ValueError):
                pass
            if t.get("at") and tag in counted:
                continue
            counted[tag] = 1
            vote(t.get("id"), t["xp"], t.get("level"), "turnin", 9, t.get("at"))
    live = data.get("live") if isinstance(data.get("live"), dict) else {}
    for qid, v in live.items():
        if isinstance(v, dict) and v.get("src") in ("npc", "log", "turnin") and isinstance(v.get("full"), (int, float)):
            try:
                if (int(qid), int(v["full"])) in mine:
                    continue  # the hand-in's own copy, counted above
            except (TypeError, ValueError):
                pass
            if v.get("at"):  # a dated reading (3.4.6+) counts once across uploads; older ones carry no date
                tag = "live:%s:%s:%s" % (qid, v["full"], v["at"])
                if tag in counted:
                    continue
                counted[tag] = 1
            vote(qid, v["full"], v.get("lvl"), v["src"], era, v.get("at"))
    return n


def _vote(table, key, value):
    votes = table.setdefault(str(key), {})
    votes[str(value)] = votes.get(str(value), 0) + 1


def merge_disc(acc, d):
    """One upload's notes into the accumulator. Lists are unioned, contested values are counted."""
    for qid, q in (d.get("q") or {}).items():
        if not isinstance(q, dict):
            continue
        a = acc["q"].setdefault(str(qid), {"n": 0, "xp": {}, "from": [], "to": []})
        a["n"] += 1
        if q.get("t"):
            a["t"] = q["t"]
        for f in ("lv", "g"):
            if isinstance(q.get(f), (int, float)) and q[f] > 0:
                a[f] = int(q[f])
        if isinstance(q.get("min"), (int, float)) and 0 < q["min"] < 99:
            a["min"] = min(a.get("min", 99), int(q["min"]))
        if isinstance(q.get("paid"), (int, float)) and q["paid"] > 0:
            a["paid"] = a.get("paid", 0) + int(q["paid"])
        for lvl, xp in (q.get("xp") or {}).items():
            if isinstance(xp, (int, float)) and xp > 0:
                _vote(a["xp"], lvl, int(xp))
        for f in ("from", "to"):
            for who in q.get(f) or []:
                if isinstance(who, str) and who not in a[f]:
                    a[f].append(who)
        # the reward items the quest window showed (QuestBank 3.5.7+): the newest upload's list stands
        rw = q.get("rw")
        if isinstance(rw, dict):
            a["rw"] = {k: [int(x) for x in (rw.get(k) or []) if isinstance(x, (int, float)) or str(x).isdigit()] for k in ("c", "r")}
    for key, n in (d.get("npc") or {}).items():
        if not isinstance(n, dict):
            continue
        a = acc["npc"].setdefault(str(key), {"p": {}})
        if n.get("n"):
            a["n"] = n["n"]
        for spot in n.get("p") or []:
            if isinstance(spot, str):
                a["p"][spot] = a["p"].get(spot, 0) + 1
    for npc, offers in (d.get("offer") or {}).items():
        if not isinstance(offers, dict):
            continue
        a = acc["offer"].setdefault(str(npc), {})
        for qid, lvl in offers.items():
            if isinstance(lvl, (int, float)) and 0 < lvl < 99:
                a[str(qid)] = min(a.get(str(qid), 99), int(lvl))
    for step, flag in (d.get("chain") or {}).items():
        if flag:
            acc["chain"][str(step)] = acc["chain"].get(str(step), 0) + 1
    for item, qid in (d.get("item") or {}).items():
        if isinstance(qid, (int, float)):
            acc["item"][str(item)] = int(qid)


# ----------------------------------------------------------------------------- where objectives tick
# QuestBank 3.6.0 notes, on the Forever client, where the player stood each time an objective of a quest in the log
# moved on: QuestBankDB.disc.os = { [questId] = { [objective index] = { t = "monster", p = { {map, x, y, n}, ... } } } },
# x and y in permille of that map, n the sightings the addon merged into the point (it merges within 15 permille, keeps
# 8 points per objective and 400 quests). Kept in disc.json under "os" in the same shape, each point as
# [map, x, y, n, votes, last]: votes is how many uploads had a point there, n the most sightings one upload had there
# (the same growing file comes back upload after upload, so adding them up would count the same kills again), last the
# upload with spots that last had it (meta.with_spots then). gen_data.py turns them into the map's "seen in players'
# games" spots, weighing each point by n. Next to os the addon keeps osN and osAt, counters it bumps on every sighting
# (which quest it touched last): they are no spot and no note, so neither digest sees them.
SPOT_KEYS = ("os", "osAt", "osN")  # what QuestBankDB.disc keeps for the spots
SPOT_NEAR = 15    # permille: a point this close on the same map is the same point (the addon's own rule)
SPOT_KEEP = 40    # points kept per objective in disc.json; past that the ones no upload has had for longest go, so a
                  # spot that moved in a later build gets in and the old one fades, however many votes it had
SPOT_W = 20       # sightings one point weighs at most on the map (gen_data.py's GAME_W): the tie-break when pruning
SPOT_UPLOAD = (400, 8)  # quests and points per objective the addon keeps: a file over that is read up to it
SPOT_TYPES = {"monster", "item", "object", "event", "areatrigger", "log", "reputation", "player", "progressbar", "spell", "currency"}


def _pairs(v):
    """(key, value) of a Lua table read back as an object, or (keys 1..n) as a list."""
    if isinstance(v, dict):
        return list(v.items())
    if isinstance(v, list):
        return [(i + 1, x) for i, x in enumerate(v)]
    return []


def _whole(v, lo, hi):
    """A number from a saved file as an int in lo..hi, or None (true/false and strings are not numbers here)."""
    if isinstance(v, bool) or not isinstance(v, (int, float)) or v != v or v in (float("inf"), float("-inf")):
        return None
    v = int(v + 0.5) if v >= 0 else -int(-v + 0.5)
    return v if lo <= v <= hi else None


def _key(k, hi):
    """A table key (a quest id, an objective index) as an int in 1..hi, or None."""
    try:
        return _whole(int(k), 1, hi)
    except (TypeError, ValueError):
        return None


def _spot(p):
    """(map, x, y, n) of one point {map, x, y, n}, or None."""
    if isinstance(p, dict):
        p = [p.get(k, p.get(str(i + 1))) for i, k in enumerate("mxyn")]
    if not isinstance(p, list) or len(p) < 3:
        return None
    m, x, y = _whole(p[0], 1, 99999), _whole(p[1], 0, 1000), _whole(p[2], 0, 1000)
    n = 1 if len(p) < 4 or p[3] is None else _whole(p[3], 1, 10 ** 9)
    if None in (m, x, y, n):
        return None
    return m, x, y, min(n, 999)  # one odd file's count can't outweigh everyone's


def _sans_spots(d):
    """The disc without its objective spots and the addon's counters for them (os has a digest of its own): an upload
    whose only change is new spots, or a sighting the addon left out, doesn't count its notes again, and the digests
    stored before the spots existed still match."""
    if isinstance(d, dict) and any(k in d for k in SPOT_KEYS):
        return {k: v for k, v in d.items() if k not in SPOT_KEYS}
    return d


def merge_spots(acc, spots):
    """One upload's QuestBankDB.disc.os into disc.json's "os". Each stored point gets one vote from an upload however
    many of its points fall on it; a point no stored one is near is added. Only numbers and the game's objective type
    are kept. Over SPOT_KEEP points, the ones no upload has had for longest go (then the least seen): this upload's
    points always stay. Returns the number of points voted for; an upload that votes for any counts in
    meta.with_spots."""
    out = acc.setdefault("os", {})
    meta = acc.setdefault("meta", {})
    stamp = meta.get("with_spots", 0) + 1
    quests = {}  # quest -> its objectives; a quest written twice ([33] and ["033"]) is read once
    for k, objs in _pairs(spots):
        q = _key(k, 999999)
        if q and q not in quests:
            quests[q] = objs
    voted = 0
    for qid in sorted(quests)[:SPOT_UPLOAD[0]]:
        done = set()  # and an objective written twice
        for idx, ob in _pairs(quests[qid]):
            idx = _key(idx, 16)
            if not idx or idx in done or not isinstance(ob, dict):
                continue
            done.add(idx)
            pts = [s for s in (_spot(p) for _, p in _pairs(ob.get("p"))) if s]
            if not pts:
                continue
            pts = sorted(pts, key=lambda s: -s[3])[:SPOT_UPLOAD[1]]
            a = out.setdefault(str(qid), {}).setdefault(str(idx), {"p": []})
            t = ob.get("t")
            if isinstance(t, str) and t.lower() in SPOT_TYPES:
                a["t"] = t.lower()
            stored = a["p"]
            for p in stored:
                p.extend([0] * (6 - len(p)))  # a point stored without its last upload: the stalest
            got = {}  # stored point -> [sightings, x * sightings, y * sightings] from this upload
            for m, x, y, n in pts:
                near, best = None, SPOT_NEAR * SPOT_NEAR
                for i, p in enumerate(stored):
                    d = (p[1] - x) ** 2 + (p[2] - y) ** 2
                    if p[0] == m and d <= best:
                        near, best = i, d
                if near is None:
                    stored.append([m, x, y, 0, 0, 0])
                    near = len(stored) - 1
                g = got.setdefault(near, [0, 0, 0])
                g[0] += n; g[1] += x * n; g[2] += y * n
            for i, (n, sx, sy) in got.items():
                p, v = stored[i], stored[i][4]
                # the place moves to the mean of the uploads that had it, each upload one share
                p[1] = int((p[1] * v + sx / n) / (v + 1) + 0.5)
                p[2] = int((p[2] * v + sy / n) / (v + 1) + 0.5)
                p[3], p[4], p[5] = max(p[3], n), v + 1, stamp
            if len(stored) > SPOT_KEEP:
                stored.sort(key=lambda p: (-p[5], -min(p[3], SPOT_W), -p[4], p[0], p[1], p[2]))
                del stored[SPOT_KEEP:]
            stored.sort(key=lambda p: (-p[4], -p[3], p[0], p[1], p[2]))
            voted += sum(1 for p in stored if p[5] == stamp)
    if voted:
        meta["with_spots"] = stamp
    return voted


def merge_probe(acc, kind, data):
    """What players' games showed, without a name in it: the spells a class (and the racials a race) had learned and the
    lowest level a character was seen with each, the item ids in bags and gear, item tooltips, and what profession
    trainers asked. Two sources: QuestBankDB.game (QuestBank 3.6.0+, written on the Forever client only: one reading per
    class and race, and tooltips) and ForeverProbe's own snapshots and tooltips (ForeverProbe.lua and FPROBE2 exports
    from installs that still have it). Kept in disc.json under "probe" (research/, never published);
    tools/apply_probe_spells.py takes the spells to the site's spellbook, tools/scavenge_items.py the items and tooltips."""
    if not isinstance(data, dict):
        return
    if kind == "questbank-savedvars":
        g = data.get("game")
        if not isinstance(g, dict) or forever_iface(g.get("iface")) is not True:
            return  # no block, or another client's: QuestBank writes it on Forever only, and an odd file is skipped all the same
        snaps, tips_in, trainers = g.get("snap"), g.get("items"), None
    elif kind in ("probe-savedvars", "export"):
        snaps, tips_in, trainers = data.get("snapshots"), data.get("items"), data.get("trainers")
    else:
        return
    pr = acc.setdefault("probe", {"spells": {}, "racials": {}, "items": {}, "trainers": {}})
    snaps = list(snaps.values()) if isinstance(snaps, dict) else (snaps if isinstance(snaps, list) else [])
    had = set()  # the item ids this upload showed: each counts once, however many characters or readings carried it
    for sn in snaps:
        if not isinstance(sn, dict) or forever_iface(sn.get("interface")) is False:
            continue
        cls, race, lvl = str(sn.get("class") or "").upper(), str(sn.get("race") or ""), sn.get("level")
        if not cls or not isinstance(lvl, (int, float)) or lvl < 1:
            continue
        book = pr["spells"].setdefault(cls, {})
        for sid in sn.get("spells") or []:
            try:
                sid = str(int(sid.get("id") if isinstance(sid, dict) else sid))
            except (TypeError, ValueError):
                continue
            book[sid] = min(book.get(sid, 99), int(lvl))
            if race:
                pr["racials"].setdefault(race, {})[sid] = 1
        for it in sn.get("items") or []:
            try:
                had.add(str(int(it.get("id") if isinstance(it, dict) else it)))
            except (TypeError, ValueError):
                continue
    for iid in had:
        pr["items"][iid] = pr["items"].get(iid, 0) + 1
    # item tooltips as the game showed them: the newest build's copy of each wins, then the newest reading; English
    # clients only, since the site parses the game's English wording. cv is the client version ("1.60.1") from the
    # tooltip's own b ("1.60.1.70205"). A b that is a build alone carries none: ForeverProbe wrote those, and QuestBank
    # keeps them as they were when it copies ForeverProbe's tooltips in, while QuestBankDB.game.client is whatever
    # client wrote the file last, not the one that read the tooltip
    tips = pr.setdefault("tips", {})
    for iid, it in (tips_in.items() if isinstance(tips_in, dict) else []):
        if not isinstance(it, dict) or not it.get("n"):
            continue
        if it.get("lc") and str(it["lc"]) not in ("enUS", "enGB"):
            continue
        x = it.get("x")
        x = x if isinstance(x, list) else ([] if isinstance(x, dict) and not x else None)
        if x is None:
            continue
        parts = str(it.get("b") or "0").split(".")
        try:
            b = int(parts[-1])
        except ValueError:
            b = 0
        cv = ".".join(parts[:-1]) if len(parts) == 4 else None
        if b and b < FIRST_FOREVER_BUILD:
            continue  # an older client's tooltip (an Era ForeverProbe.lua or export): not Forever's numbers
        at = it.get("at") if isinstance(it.get("at"), (int, float)) else 0
        old = tips.get(str(iid))
        if old and (int(old.get("b") or 0), old.get("at") or 0) > (b, at):
            continue
        tips[str(iid)] = {"b": b, "at": at, "n": it["n"], "q": it.get("q"), "l": it.get("l"), "r": it.get("r"), "el": it.get("el"),
                          "c": it.get("c"), "u": it.get("u"), "e": it.get("e"), "ic": it.get("ic"), "x": [str(v) for v in x][:40]}
        if cv:
            tips[str(iid)]["cv"] = cv
    for tr in list(trainers.values()) if isinstance(trainers, dict) else (trainers if isinstance(trainers, list) else []):
        if not isinstance(tr, dict):
            continue
        for sv in tr.get("services") or []:
            if not isinstance(sv, dict):
                continue
            name, cost = sv.get("n") or sv.get("name"), sv.get("c") if sv.get("c") is not None else sv.get("cost")
            if name and isinstance(cost, (int, float)):
                t = pr["trainers"].setdefault(str(name), {})
                t[str(int(cost))] = t.get(str(int(cost)), 0) + 1


def _digest(v):
    return hashlib.sha256(json.dumps(v, sort_keys=True, default=str).encode("utf-8")).hexdigest()[:20]


def merge_upload(acc, text, source="local"):
    """Decode one upload and merge it. Returns (kind, had_notes). The same notes arriving again (an unchanged file re-sent,
    or ForeverProbe's copy of QuestBank's notes next to QuestBank's own file) are merged once. A QuestBank.lua has three
    parts with a digest each, its notes (disc, turnins, live), where its objectives ticked (disc.os) and QuestBankDB.game,
    so a file where only a tooltip or a spot changed still brings that, and one where only the notes changed doesn't
    count its items or vote for its spots again. Notes from a client other than Forever are left out, spots too."""
    kind, data = decode(text)
    meta = acc["meta"]
    meta["uploads"] += 1
    meta["sources"][source] = meta["sources"].get(source, 0) + 1
    seen_hashes = meta.setdefault("hashes", [])
    fresh = spotted = False
    if kind == "questbank-savedvars" and isinstance(data, dict):
        g = data.get("game")
        if isinstance(g, dict) and g:
            h = _digest({"game": g})
            if h not in seen_hashes:
                seen_hashes.append(h)
                merge_probe(acc, kind, data)
                fresh = True
        if not from_forever(data):
            meta["other_client"] = meta.get("other_client", 0) + 1
            return kind, False
        # the spots come from QuestBank's own file only: ForeverProbe's copy of the disc carries the same ones, and an
        # old tray still sends both files
        spots = (disc_of(kind, data) or {}).get("os")
        if spots:
            h = _digest({"os": spots})
            if h not in seen_hashes:
                seen_hashes.append(h)
                spotted = merge_spots(acc, spots) > 0
                fresh = True
        # the notes' digest is the one earlier pulls stored, so a rebuild isn't needed for old uploads to stay merged once
        h = _digest({k: _sans_spots(data.get(k)) if k == "disc" else data.get(k) for k in ("disc", "turnins", "live", "liveEra")})
        if h in seen_hashes:
            if not fresh:
                meta["repeats"] = meta.get("repeats", 0) + 1
            return kind, spotted
        seen_hashes.append(h)
        merge_seen(acc, kind, data)
    else:
        merge_probe(acc, kind, data)
    d = disc_of(kind, data)
    if d is None:
        return kind, spotted
    if kind != "questbank-savedvars" and not from_forever({"disc": d}):
        # ForeverProbe's copy of the notes carries QuestBank's own stamps: one loaded on Era as an out-of-date addon copies Era's
        meta["other_client"] = meta.get("other_client", 0) + 1
        return kind, False
    h = _digest(_sans_spots(d))
    if h in seen_hashes:
        if not fresh:
            meta["repeats"] = meta.get("repeats", 0) + 1
        return kind, spotted
    seen_hashes.append(h)
    meta["with_notes"] += 1
    merge_disc(acc, d)
    return kind, True


def summary(acc):
    contested = sum(1 for q in acc["q"].values() for votes in q["xp"].values() if len(votes) > 1)
    sightings = sum(sum(v.values()) for v in (acc.get("seen") or {}).values())
    pr = acc.get("probe") or {}
    out = "%d uploads (%d with notes): %d quests, %d NPCs, %d offering NPCs, %d chain steps, %d item starts; %d XP readings disagree; %d XP sightings on %d quests" % (
        acc["meta"]["uploads"], acc["meta"]["with_notes"], len(acc["q"]), len(acc["npc"]), len(acc["offer"]),
        len(acc["chain"]), len(acc["item"]), contested, sightings, len(acc.get("seen") or {}))
    out += "; games: spells of %d classes and %d races, %d items had, %d tooltips" % (
        len(pr.get("spells") or {}), len(pr.get("racials") or {}), len(pr.get("items") or {}), len(pr.get("tips") or {}))
    spots = acc.get("os") or {}
    out += "; objective spots: %d points on %d objectives of %d quests, from %d upload(s)" % (
        sum(len(o.get("p") or []) for q in spots.values() for o in q.values()), sum(len(q) for q in spots.values()),
        len(spots), acc["meta"].get("with_spots", 0))
    if acc["meta"].get("other_client"):
        out += "; %d upload(s) from another client left out" % acc["meta"]["other_client"]
    return out


# ----------------------------------------------------------------------------------------- the pull
def admin_key():
    key = os.environ.get("PROBE_ADMIN_KEY", "").strip()
    if not key and os.path.exists(KEY_FILE):
        key = open(KEY_FILE).read().strip()
    if not key:
        sys.exit("no admin key: put it in %s (gitignored) or PROBE_ADMIN_KEY" % os.path.relpath(KEY_FILE, REPO))
    return key


def pull(acc, endpoint, key, raw_dir, limit=20):
    after = acc["meta"].get("last_id", 0)
    new = 0
    os.makedirs(raw_dir, exist_ok=True)
    while True:
        # a named user agent: Cloudflare answers the bare Python one with 403 before the Worker runs
        req = urllib.request.Request("%s/api/probe/pull?after=%d&limit=%d" % (endpoint.rstrip("/"), after, limit),
                                     headers={"x-admin-key": key, "user-agent": "foreverrank-probe-pull/1.0 (tools/probe_pull.py)"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                page = json.load(r)
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "replace")[:200]
            if e.code == 401:
                sys.exit("the Worker refused the admin key (401): check worker/.probe-admin-key against the PROBE_ADMIN_KEY secret")
            sys.exit("HTTP %d from %s: %s" % (e.code, endpoint, body or e.reason))
        rows = page.get("rows") or []
        if not rows:
            break
        for row in rows:
            text = gzip.decompress(base64.b64decode(row["body_gzip_base64"])).decode("utf-8", "replace")
            ext = "txt" if row["kind"] == "export" else "lua"
            open(os.path.join(raw_dir, "%05d-%s.%s" % (row["id"], row["kind"], ext)), "w", encoding="utf-8").write(text)
            try:
                kind, notes = merge_upload(acc, text, row.get("source") or "unknown")
            except (ValueError, LuaError, KeyError) as e:
                print("  upload #%d (%s) could not be read: %s" % (row["id"], row["kind"], e))
                kind, notes = row["kind"], False
            s = row.get("summary") or {}
            print("  #%d %s from %s: %s%s" % (row["id"], kind, row.get("source"), s.get("char") or s.get("addon") or "", "" if notes else " (no QuestBank notes)"))
            after = row["id"]
            new += 1
        acc["meta"]["last_id"] = after
        if len(rows) < limit:
            break
    return new


# ------------------------------------------------------------------------------------- the selftest
def selftest():
    fx = os.path.join(HERE, "fixtures", "probe")
    qb = parse_savedvariables(open(os.path.join(fx, "QuestBank.lua")).read())["QuestBankDB"]
    assert qb["disc"]["q"]["7"]["t"] == "Kobold Camp Cleanup", qb["disc"]["q"]["7"]
    assert qb["disc"]["q"]["7"]["xp"] == {"3": 250, "2": 250}
    assert qb["disc"]["q"]["7"]["from"] == ["c197"], "positional entries become a list"
    assert qb["disc"]["q"]["2158"]["xp"] == {}, "an empty table stays an object"
    assert qb["disc"]["npc"]["c197"]["p"] == ["1429:48.2,42.1", "1429:48.3,42.0"]
    assert qb["disc"]["offer"]["c197"] == {"7": 2, "15": 3}, "numeric keys read back as strings"
    assert qb["disc"]["chain"] == {"7>15": True}
    assert qb["disc"]["item"] == {"1000": 2158}
    assert qb["settings"]["escaped"] == 'He said "hi"\\n|cffffffffwhite|r', qb["settings"]["escaped"]
    assert qb["settings"]["neg"] == -1.5 and qb["settings"]["big"] == 1e15 and qb["settings"]["arrow"] is False
    assert qb["errors"] == {}
    assert _sans_spots(qb["disc"]) is qb["disc"], "a disc with no spots digests as it always did"
    assert _sans_spots({"v": 1, "q": {}, "os": {}, "osN": 3, "osAt": {"7": 3}}) == {"v": 1, "q": {}}, "nor do the addon's spot counters"
    fp = parse_savedvariables(open(os.path.join(fx, "ForeverProbe.lua")).read())["ForeverProbeDB"]
    assert fp["snapshots"][0]["name"] == "Helga" and fp["meta"]["addon"] == "0.4.0"
    assert fp["questbank"]["disc"]["q"]["176"]["t"] == 'Wanted: "Hogger"'
    kind, data = decode(open(os.path.join(fx, "export.txt")).read())
    assert kind == "export" and disc_of(kind, data)["q"]["62"]["xp"] == {"7": 650, "8": 650}
    try:
        decode("hello there")
        raise AssertionError("junk was accepted")
    except ValueError:
        pass

    acc = empty()
    for name in ("QuestBank.lua", "ForeverProbe.lua", "export.txt"):
        k, notes = merge_upload(acc, open(os.path.join(fx, name)).read(), "fixture")
        assert notes, name
    q7 = acc["q"]["7"]
    assert q7["n"] == 3 and q7["xp"]["3"] == {"250": 2, "260": 1} and q7["xp"]["2"] == {"250": 1}, q7
    assert q7["from"] == ["c197"] and q7["to"] == ["c197"] and q7["paid"] == 2 and q7["min"] == 2
    assert acc["chain"] == {"7>15": 2, "15>18": 1, "62>76": 1}, acc["chain"]
    assert acc["npc"]["c197"]["p"] == {"1429:48.2,42.1": 2, "1429:48.3,42.0": 1}
    assert acc["npc"]["c240"]["n"] == "Marshal Dughan"
    assert acc["offer"]["c197"] == {"7": 2, "15": 3} and acc["offer"]["c240"] == {"62": 6}
    assert acc["item"] == {"1000": 2158} and acc["q"]["2158"]["from"] == ["i1000", "c823"]
    assert acc["meta"]["uploads"] == 3 and acc["meta"]["with_notes"] == 3 and acc["meta"]["sources"] == {"fixture": 3}
    # what the game paid: hand-ins and own window readings vote, party readings and hidden numbers don't
    acc2 = empty()
    upload = {
        "disc": {"v": 1, "q": {}, "build": 70170}, "liveEra": 3,
        "turnins": [{"id": 971, "xp": 6550, "level": 22, "at": "2026-10-02 03:10:05"}, {"id": 971, "xp": 6550, "level": 22, "at": "2026-10-02 03:10:05"},
                    {"id": 971, "xp": 6550, "level": 22, "at": "2026-10-02 04:00:00"}, {"id": 5, "xp": 0, "level": 3, "at": "2026-10-02 01:00:00"},
                    {"id": 166, "xp": 9750, "level": 20, "at": "2026-09-30 22:00:00"},
                    {"id": 1200, "xp": None, "level": 24, "hidden": True, "at": "2026-10-02 05:00:00"}],
        "live": {"386": {"full": 4200, "lvl": 22, "src": "npc", "at": "2026-10-02"}, "971": {"full": 6550, "lvl": 22, "src": "turnin"},
                 "1200": {"full": 8007, "lvl": 20, "src": "party"}}}
    n = merge_seen(acc2, "questbank-savedvars", upload)
    # the two identical dated rows count once, the second hand-in counts, the pre-cut one is keyed build 0, the live
    # copy of a counted hand-in is skipped, party readings and hidden numbers are left out
    assert n == 4 and acc2["seen"] == {"971": {"6550:22:70170:turnin:9": 2}, "166": {"9750:20:0:turnin:9": 1}, "386": {"4200:22:70170:npc:3": 1}}, acc2["seen"]
    assert merge_seen(acc2, "questbank-savedvars", upload) == 0, "the same file uploaded again adds no votes"
    assert merge_seen(acc2, "export", {"turnins": [{"id": 1, "xp": 5, "level": 1}]}) == 0, "exports carry no hand-ins"

    # what players' games showed: an old ForeverProbe file still merges, then QuestBank 3.6.0's game block on Forever;
    # a QuestBank.lua from Classic Era adds nothing, its notes and its game block alike
    fp_text, qb_text, era_text = (open(os.path.join(fx, n)).read() for n in ("ForeverProbe.lua", "QuestBank-forever.lua", "QuestBank-era.lua"))
    acc3 = empty()
    assert merge_upload(acc3, fp_text, "fixture")[1]
    assert merge_upload(acc3, qb_text, "fixture") == ("questbank-savedvars", True)
    assert merge_upload(acc3, era_text, "fixture") == ("questbank-savedvars", False)
    pr = acc3["probe"]
    assert pr["spells"] == {"PALADIN": {"635": 12, "20271": 12, "20594": 12, "2481": 12}, "MAGE": {"133": 5, "168": 5, "20580": 5}}, pr["spells"]
    assert set(pr["racials"]) == {"Dwarf", "NightElf"} and pr["racials"]["NightElf"] == {"133": 1, "168": 1, "20580": 1}, pr["racials"]
    # once per upload: two ForeverProbe snapshots and two QuestBank readings carry 2361, 45 and 159; Era's 25 and 159 don't count
    assert pr["items"] == {"2361": 2, "45": 2, "2589": 1, "159": 1, "35": 1, "6096": 1}, pr["items"]
    t = pr["tips"]
    assert set(t) == {"2361", "45", "159", "2589"}, "the German and the Era tooltips are left out: %s" % sorted(t)
    assert t["2361"]["b"] == 70205 and t["2361"]["cv"] == "1.60.1" and t["2361"]["x"][1] == "6 - 11 Damage\tSpeed 2.90", t["2361"]
    assert "cv" not in t["45"] and t["159"]["cv"] == "1.60.0" and t["159"]["b"] == 69990, "the tooltip's own version, never the block's"
    assert "cv" not in t["2589"] and t["2589"]["x"] == [], "ForeverProbe's tooltips carry no client version"
    assert "33" in acc3["q"] and "783" not in acc3["q"] and "c823" not in acc3["npc"], "Era's notes are left out"
    assert set(acc3["seen"]) == {"33"} and acc3["seen"]["33"] == {"170:2:70205:turnin:9": 1}, acc3["seen"]
    assert acc3["meta"]["other_client"] == 1 and acc3["meta"].get("repeats", 0) == 0, acc3["meta"]
    # where objectives ticked: numbers and the game's objective type only (the fixture's odd type, name and values are
    # left out), the two points one upload has close together are one point voted for once; Era's spots stay out
    spots = {"33": {"1": {"t": "item", "p": [[1429, 472, 395, 6, 1, 1], [1429, 526, 386, 3, 1, 1]]}},
             "7": {"1": {"t": "monster", "p": [[1429, 493, 363, 9, 1, 1], [1429, 500, 500, 1, 1, 1]]}},
             "60005": {"2": {"p": [[2482, 300, 701, 2, 1, 1], [2482, 410, 620, 1, 1, 1]]}}}
    assert acc3["os"] == spots and acc3["meta"]["with_spots"] == 1, acc3["os"]
    # the same file again is a repeat; a new tooltip reading merges the game block alone (its items count again, once);
    # new notes merge the notes alone
    assert merge_upload(acc3, qb_text, "fixture") == ("questbank-savedvars", False)
    assert acc3["meta"]["repeats"] == 1 and pr["items"]["2361"] == 2
    tip_text = qb_text.replace('["at"] = 1791100000,', '["at"] = 1791100600,')
    assert tip_text != qb_text
    assert merge_upload(acc3, tip_text, "fixture") == ("questbank-savedvars", False)
    assert acc3["meta"]["repeats"] == 1 and pr["items"]["2361"] == 3 and pr["items"]["159"] == 2 and t["2361"]["at"] == 1791100600
    assert acc3["q"]["33"]["n"] == 1 and acc3["seen"]["33"] == {"170:2:70205:turnin:9": 1}, "the notes were not merged again"
    # (with an undated quest-window reading, as QuestBank before 3.4.6 wrote them: it counts each time the notes merge)
    notes_text = tip_text.replace('["lv"] = 2,\n\t\t\t\t["min"] = 1,', '["lv"] = 3,\n\t\t\t\t["min"] = 1,').replace(
        '\t["turnins"] = {', '\t["live"] = {\n\t\t[7] = {\n\t\t\t["full"] = 250,\n\t\t\t["lvl"] = 2,\n\t\t\t["src"] = "npc",\n\t\t},\n\t},\n\t["turnins"] = {', 1)
    assert notes_text.count('["live"]') == 1
    assert merge_upload(acc3, notes_text, "fixture") == ("questbank-savedvars", True)
    assert acc3["q"]["33"]["n"] == 2 and acc3["q"]["33"]["lv"] == 3 and pr["items"]["2361"] == 3, "the game block was not merged again"
    assert acc3["os"] == spots, "a repeat, a tooltip or new notes vote for no spot again"
    # every sighting bumps the addon's counters (osN, and osAt of the quest), also one it left out of a full objective:
    # with nothing else new that is a repeat
    def ticked(text, quest, was, to):
        out = text.replace('["osN"] = %d,' % was, '["osN"] = %d,' % to, 1)
        out = re.sub(r'(\["osAt"\] = \{[^}]*?\[%d\] = )\d+,' % quest, r"\g<1>%d," % to, out, count=1)
        assert out.count('= %d,' % to) == 2, "osN and osAt[%d] both moved" % quest
        return out
    left_out = ticked(notes_text, 7, 21, 22)
    assert merge_upload(acc3, left_out, "fixture") == ("questbank-savedvars", False) and acc3["meta"]["repeats"] == 2
    assert acc3["q"]["33"]["n"] == 2 and acc3["seen"]["7"] == {"250:2:70205:npc:0": 1} and acc3["os"] == spots
    # new spots alone merge the spots alone: each point of the upload gets one more vote, the most sightings stand
    spots_text = ticked(re.sub(r"(395, -- \[3\]\s+)6(, -- \[4\])", r"\g<1>7\2", left_out, count=1), 33, 22, 23)
    assert merge_upload(acc3, spots_text, "fixture") == ("questbank-savedvars", True)
    assert acc3["q"]["33"]["n"] == 2 and acc3["seen"]["33"] == {"170:2:70205:turnin:9": 1} and acc3["meta"]["repeats"] == 2
    assert acc3["seen"]["7"] == {"250:2:70205:npc:0": 1} and acc3["meta"]["with_notes"] == 3, "the notes were not merged again"
    assert acc3["os"]["33"]["1"]["p"] == [[1429, 472, 395, 7, 2, 2], [1429, 526, 386, 3, 2, 2]] and acc3["meta"]["with_spots"] == 2, acc3["os"]
    assert acc3["os"]["60005"]["2"]["p"] == [[2482, 300, 701, 2, 2, 2], [2482, 410, 620, 1, 2, 2]], acc3["os"]
    assert merge_upload(acc3, spots_text, "fixture") == ("questbank-savedvars", False) and acc3["meta"]["repeats"] == 3
    assert all(set(o) <= {"t", "p"} for q in acc3["os"].values() for o in q.values())
    # merge_spots alone: a near point on the same map is the same place (moved to the uploads' mean), another map's is
    # not; a file over the addon's caps is read up to them, a quest or objective written twice is read once
    acc5 = empty()
    assert merge_spots(acc5, {"7": [{"t": "MONSTER", "p": [[1429, 493, 363, 9]]}]}) == 1
    assert merge_spots(acc5, {"7": {"1": {"t": "monster", "p": [[1429, 500, 370, 4], [1430, 493, 363, 1], [1429, 600, 600, True], [1429, 600, 600, -1]]}}}) == 2
    assert acc5["os"]["7"]["1"] == {"t": "monster", "p": [[1429, 497, 367, 9, 2, 2], [1430, 493, 363, 1, 1, 2]]}, acc5["os"]
    assert merge_spots(acc5, {"7": {"1": {"p": [[1430, 493, 363, 1]]}, "01": {"p": [[1430, 493, 363, 1]]}}, "007": {"1": {"p": [[1430, 493, 363, 1]]}}}) == 1
    assert acc5["os"]["7"]["1"]["p"][1] == [1430, 493, 363, 1, 2, 3] and acc5["meta"]["with_spots"] == 3, acc5["os"]
    many = {"1": {"t": "item", "p": [[1429, 30 * i, 0, i + 1] for i in range(10)]}, "17": {"p": [[1429, 1, 1, 1]]}, "0": {"p": [[1429, 1, 1, 1]]}}
    assert merge_spots(acc5, {"92": many, "x": many, "-3": many}) == 8
    assert list(acc5["os"]["92"]) == ["1"] and [p[1] for p in acc5["os"]["92"]["1"]["p"]] == [270, 240, 210, 180, 150, 120, 90, 60]
    assert merge_spots(acc5, {q: {"1": {"p": [[1429, 1, 1, 1]]}} for q in range(1000, 1500)}) == 400
    assert "1399" in acc5["os"] and "1400" not in acc5["os"]
    # past 40 points an objective loses the points no upload has had for longest, however many votes they had: five
    # players' 8 points each, every file sent twice, fill it; a sixth player's spots (a later build moved them) get in
    # and the first player's go; a player who sends again keeps theirs, and the next new spots push out the stalest
    for row in range(5):
        for _ in range(2):
            assert merge_spots(acc5, {"93": {"1": {"t": "monster", "p": [[1429, 40 * i + 5, 100 * row + 50, 3] for i in range(8)]}}}) == 8
    p93 = acc5["os"]["93"]["1"]["p"]
    assert len(p93) == SPOT_KEEP and min(p[4] for p in p93) == 2
    assert merge_spots(acc5, {"93": {"1": {"p": [[1429, 40 * i + 5, 900, 200] for i in range(8)]}}}) == 8
    assert len(p93) == SPOT_KEEP and sorted({p[2] for p in p93}) == [150, 250, 350, 450, 900], sorted({p[2] for p in p93})
    assert merge_spots(acc5, {"93": {"1": {"p": [[1429, 40 * i + 5, 150, 3] for i in range(8)]}}}) == 8
    assert merge_spots(acc5, {"93": {"1": {"p": [[1429, 40 * i + 5, 800, 1] for i in range(8)]}}}) == 8
    assert len(p93) == SPOT_KEEP and sorted({p[2] for p in p93}) == [150, 350, 450, 800, 900], sorted({p[2] for p in p93})
    assert [p[2] for p in p93[:8]] == [150] * 8 and [p[3:5] for p in p93[24:33]] == [[200, 1]] * 8 + [[1, 1]], "by votes, then sightings"
    # ForeverProbe's copy of the notes goes by the disc's own stamp: a copy made on Era adds no notes, its snapshots still
    # go by their own interface
    acc4 = empty()
    ex_text = open(os.path.join(fx, "export.txt")).read()
    stamp = lambda iface: (fp_text.replace('["disc"] = {\n\t\t\t["v"] = 1,', '["disc"] = {\n\t\t\t["iface"] = %d,\n\t\t\t["v"] = 1,' % iface),
                           ex_text.replace('"disc":{"v":1,', '"disc":{"v":1,"iface":%d,' % iface))
    era_fp, era_ex = stamp(11507)
    assert era_fp != fp_text and era_ex != ex_text
    assert merge_upload(acc4, era_fp, "fixture") == ("probe-savedvars", False)
    assert merge_upload(acc4, era_ex, "fixture") == ("export", False)
    assert acc4["q"] == {} and acc4["meta"]["with_notes"] == 0 and acc4["meta"]["other_client"] == 2, acc4["meta"]
    assert acc4["probe"]["spells"]["PALADIN"], "the Forever snapshots in the same file still count"
    assert [merge_upload(acc4, t, "fixture")[1] for t in stamp(16001)] == [True, True] and "62" in acc4["q"]
    # ForeverProbe's copy of the disc brings no spots (QuestBank.lua does), and they don't change its digest
    acc6 = empty()
    fp_os = fp_text.replace('["disc"] = {\n\t\t\t["v"] = 1,', '["disc"] = {\n\t\t\t["os"] = { [176] = { { ["t"] = "monster", ["p"] = { { 1429, 300, 300, 2 } } } } },'
                            '\n\t\t\t["osN"] = 2,\n\t\t\t["osAt"] = { [176] = 2 },\n\t\t\t["v"] = 1,')
    assert fp_os != fp_text and merge_upload(acc6, fp_text, "fixture")[1]
    assert merge_upload(acc6, fp_os, "fixture") == ("probe-savedvars", False) and acc6["meta"]["repeats"] == 1 and acc6["os"] == {}
    # which client wrote an unstamped file: its build, else Forever
    assert from_forever({"disc": {"v": 1, "q": {}, "build": "70058"}}) is True
    assert from_forever({"disc": {"v": 1, "q": {}, "build": "61582"}}) is False, "older than Forever's first build"
    assert from_forever({"disc": {"v": 1, "q": {}}}) is True and from_forever({}) is True
    assert from_forever({"disc": {"build": "70205"}, "diag": {"addons": {"iface": 11507}}}) is False, "the stamp decides over the build"
    assert from_forever({"disc": {"build": "61582", "iface": 16001}}) is True
    json.dumps(acc), json.dumps(acc3), json.dumps(acc4), json.dumps(acc5)  # everything JSON-clean
    print("selftest OK:", summary(acc))
    print("selftest OK:", summary(acc3))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--endpoint", default=ENDPOINT, help="Worker base URL (default %s)" % ENDPOINT)
    ap.add_argument("--out", default=OUT, help="merged discoveries (default research/questbank/disc.json)")
    ap.add_argument("--raw-dir", default=RAW_DIR, help="where decoded uploads are kept (default research/probe)")
    ap.add_argument("--merge", nargs="+", metavar="FILE", help="merge these local files instead of pulling")
    ap.add_argument("--parse", metavar="FILE", help="print one file as JSON and exit")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--rebuild", action="store_true",
                    help="start over from the decoded uploads in --raw-dir, without pulling (run plain afterwards for what is new)")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.parse:
        kind, data = decode(open(a.parse, encoding="utf-8").read())
        print(json.dumps({"kind": kind, "data": data}, indent=1, ensure_ascii=False))
        return
    acc = json.load(open(a.out)) if os.path.exists(a.out) else empty()
    stamp = lambda t: datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    pulled = stamp(datetime.datetime.now(datetime.timezone.utc).timestamp())
    if a.rebuild:
        # a rebuild alone pulls nothing, so the pull date GAPS.md gives stays the last pull's; with no disc.json, the
        # newest decoded upload's, since pull() writes each one as it arrives
        if not a.merge:
            raw = [os.path.getmtime(os.path.join(a.raw_dir, f)) for f in os.listdir(a.raw_dir) if re.match(r"^\d+-", f)]
            pulled = acc["meta"].get("pulled") or (stamp(max(raw)) if raw else None)
        acc = empty()
        for f in sorted(os.listdir(a.raw_dir)):
            m = re.match(r"^(\d+)-", f)
            if not m:
                continue
            acc["meta"]["last_id"] = max(acc["meta"]["last_id"], int(m.group(1)))
            try:
                kind, notes = merge_upload(acc, open(os.path.join(a.raw_dir, f), encoding="utf-8").read(), "rebuild")
            except (ValueError, KeyError) as e:
                print("  %s could not be read, skipped: %s" % (f, e))
        print("rebuilt from %d decoded upload(s) up to #%d" % (acc["meta"]["uploads"], acc["meta"]["last_id"]))
    if a.merge:
        for f in a.merge:
            kind, notes = merge_upload(acc, open(f, encoding="utf-8").read(), "local")
            print("  %s: %s%s" % (os.path.basename(f), kind, "" if notes else " (no QuestBank notes)"))
    elif not a.rebuild:
        new = pull(acc, a.endpoint, admin_key(), a.raw_dir)
        print("pulled %d new upload(s) after #%d" % (new, acc["meta"]["last_id"]))
    acc["meta"]["pulled"] = pulled
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    json.dump(acc, open(a.out, "w"), indent=0, sort_keys=True)
    print("wrote %s: %s" % (os.path.relpath(a.out, REPO) if a.out.startswith(REPO) else a.out, summary(acc)))


if __name__ == "__main__":
    main()
