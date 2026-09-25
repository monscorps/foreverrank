#!/usr/bin/env python3
"""Check the tooltip resolver against the site: resolve every Forge talent
rank from a build and compare with plan/plan-data.json's text.

  python3 tools/verify_spelltext.py 1.60.1.69876          # match rate + misses
  python3 tools/verify_spelltext.py 1.60.1.69876 -v       # every miss, both sides

Run it against the build the site text came from. Talents that reproduce
exactly are the ones whose next-build text can be trusted.
"""
import json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spelltext import Client

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def norm(s):
    return re.sub(r"\s+", " ", (s or "").replace(" ", " ")).strip()


def talents():
    p = json.load(open(os.path.join(ROOT, "plan", "plan-data.json")))
    for ci, c in enumerate(p["classes"]):
        for ti, tr in enumerate(c["trees"]):
            for i, t in enumerate(tr["talents"]):
                yield (ci, ti, i), c, tr, t


def check(client, verbose=False):
    ok, bad, err = [], [], []
    for key, c, tr, t in talents():
        if not t.get("sp"):
            continue
        per = []
        for r, want in enumerate(t.get("desc") or [], 1):
            if not want:
                continue
            try:
                got = client.talent_text(t["sp"], r, t.get("r", 1))
            except Exception as e:
                err.append((t["n"], r, str(e)))
                per = None
                break
            per.append(norm(got) == norm(want))
            if norm(got) != norm(want) and verbose:
                print("MISS %-26s r%d\n   site: %s\n   ours: %s" % (t["n"], r, norm(want), norm(got)))
        if per is None:
            continue
        (ok if per and all(per) else bad).append((key, t["n"]))
    return ok, bad, err


if __name__ == "__main__":
    build = sys.argv[1]
    v = "-v" in sys.argv
    ok, bad, err = check(Client(build), v)
    total = len(ok) + len(bad) + len(err)
    print("talents reproduced exactly: %d / %d (%.0f%%)   mismatched %d   resolver errors %d"
          % (len(ok), total, 100.0 * len(ok) / max(total, 1), len(bad), len(err)))
    for e in err[:15]:
        print("  ERR", e)
