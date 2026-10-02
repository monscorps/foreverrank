#!/usr/bin/env python3
"""Pull ForeverProbe and QuestBank uploads from the Worker and merge their discoveries.

What players' addons noted in game (QuestBankDB.disc: quests, the NPCs who give and take them,
where those stand, the XP each quest showed, which quests an NPC offers at what level, chain
steps) arrives at the Worker as three kinds of upload: an FPROBE2 export, a ForeverProbe.lua
SavedVariables file (its ["questbank"] block carries the same notes), or a QuestBank.lua
SavedVariables file. This tool pulls the new rows, keeps each decoded body under
research/probe/, and merges every discovery into research/questbank/disc.json, which
gen_data.py reads: a quest seen in Forever loses its "Classic only" flag, and quests seen in
game that are not in the catalog at all are listed in GAPS.md. Votes are kept, not winners:
disc.json records how many uploads reported each XP value and each NPC position.

  python3 tools/probe_pull.py                      # pull what is new, merge, report
  python3 tools/probe_pull.py --merge FILE...       # merge local files (a friend's QuestBank.lua) without the Worker
  python3 tools/probe_pull.py --parse FILE          # print a SavedVariables file or export as JSON
  python3 tools/probe_pull.py --selftest            # the parser and the merge against tools/fixtures/probe/

The admin key is read from worker/.probe-admin-key (gitignored) or the PROBE_ADMIN_KEY
environment variable; it is never printed. Nothing here writes to the Worker.
"""
import argparse, base64, datetime, gzip, json, os, re, sys, urllib.error, urllib.request

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


# --------------------------------------------------------------------------------------- the merge
def empty():
    return {"meta": {"last_id": 0, "uploads": 0, "with_notes": 0, "sources": {}, "pulled": None},
            "q": {}, "npc": {}, "offer": {}, "chain": {}, "item": {}, "seen": {}, "seen_at": {}}


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


def merge_upload(acc, text, source="local"):
    """Decode one upload and merge its notes. Returns (kind, had_notes)."""
    kind, data = decode(text)
    acc["meta"]["uploads"] += 1
    acc["meta"]["sources"][source] = acc["meta"]["sources"].get(source, 0) + 1
    merge_seen(acc, kind, data)
    d = disc_of(kind, data)
    if d is None:
        return kind, False
    acc["meta"]["with_notes"] += 1
    merge_disc(acc, d)
    return kind, True


def summary(acc):
    contested = sum(1 for q in acc["q"].values() for votes in q["xp"].values() if len(votes) > 1)
    sightings = sum(sum(v.values()) for v in (acc.get("seen") or {}).values())
    return "%d uploads (%d with notes): %d quests, %d NPCs, %d offering NPCs, %d chain steps, %d item starts; %d XP readings disagree; %d XP sightings on %d quests" % (
        acc["meta"]["uploads"], acc["meta"]["with_notes"], len(acc["q"]), len(acc["npc"]), len(acc["offer"]),
        len(acc["chain"]), len(acc["item"]), contested, sightings, len(acc.get("seen") or {}))


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
    json.dumps(acc)  # everything JSON-clean
    print("selftest OK:", summary(acc))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--endpoint", default=ENDPOINT, help="Worker base URL (default %s)" % ENDPOINT)
    ap.add_argument("--out", default=OUT, help="merged discoveries (default research/questbank/disc.json)")
    ap.add_argument("--raw-dir", default=RAW_DIR, help="where decoded uploads are kept (default research/probe)")
    ap.add_argument("--merge", nargs="+", metavar="FILE", help="merge these local files instead of pulling")
    ap.add_argument("--parse", metavar="FILE", help="print one file as JSON and exit")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--rebuild", action="store_true", help="start over from the decoded uploads in --raw-dir, then pull")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.parse:
        kind, data = decode(open(a.parse, encoding="utf-8").read())
        print(json.dumps({"kind": kind, "data": data}, indent=1, ensure_ascii=False))
        return
    acc = json.load(open(a.out)) if os.path.exists(a.out) else empty()
    if a.rebuild:
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
        print("rebuilt from %d decoded upload(s)" % acc["meta"]["uploads"])
    if a.merge:
        for f in a.merge:
            kind, notes = merge_upload(acc, open(f, encoding="utf-8").read(), "local")
            print("  %s: %s%s" % (os.path.basename(f), kind, "" if notes else " (no QuestBank notes)"))
        new = len(a.merge)
    else:
        new = pull(acc, a.endpoint, admin_key(), a.raw_dir)
        print("pulled %d new upload(s) after #%d" % (new, acc["meta"]["last_id"]))
    acc["meta"]["pulled"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    json.dump(acc, open(a.out, "w"), indent=0, sort_keys=True)
    print("wrote %s: %s" % (os.path.relpath(a.out, REPO) if a.out.startswith(REPO) else a.out, summary(acc)))


if __name__ == "__main__":
    main()
