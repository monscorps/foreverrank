#!/usr/bin/env python3
"""Page views on foreverrank.com, from the Worker's own count (worker/src/index.js: /api/hit, /api/hits).

  python3 tools/visits.py            # the last 30 days
  python3 tools/visits.py 7          # the last 7 days

What the count is: one beacon per page load (nav.js), kept as a total per day and page and per day and referring site.
No IP addresses, cookies or anything per reader, so these are page views, not people; readers whose browser asks not
to be tracked are not counted, and neither are requests that say they are bots.

The admin key is read from worker/.probe-admin-key (gitignored) or the PROBE_ADMIN_KEY environment variable; it is
never printed. Nothing here writes to the Worker.
"""
import json, os, sys, urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENDPOINT = "https://foreverrank.andustemme.workers.dev/api/hits"
KEY_FILE = os.path.join(REPO, "worker", ".probe-admin-key")


def admin_key():
    key = os.environ.get("PROBE_ADMIN_KEY") or (open(KEY_FILE).read().strip() if os.path.exists(KEY_FILE) else "")
    if not key:
        sys.exit("no admin key: put it in worker/.probe-admin-key or PROBE_ADMIN_KEY")
    return key


def bar(n, top, width=28):
    return "#" * max(1 if n else 0, round(width * n / top)) if top else ""


def main():
    days = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 30
    req = urllib.request.Request("%s?days=%d" % (ENDPOINT, days),
                                 headers={"x-admin-key": admin_key(), "user-agent": "foreverrank visits report"})
    try:
        data = json.load(urllib.request.urlopen(req, timeout=30))
    except urllib.error.HTTPError as e:
        sys.exit("the Worker said %d: %s" % (e.code, "wrong admin key" if e.code == 401 else
                                           "not deployed yet? (cd worker && npx --yes wrangler deploy)" if e.code == 404 else e.reason))
    print("Page views since %s (%d days): %d" % (data["since"], data["days"], data["total"]))
    if not data["total"]:
        print("Nothing counted yet: the count starts with the first page view after the Worker deploy.")
        return
    top = max(r["n"] for r in data["perDay"])
    print("\nPer day")
    for r in data["perDay"]:
        print("  %s %6d  %s" % (r["day"], r["n"], bar(r["n"], top)))
    print("\nPages")
    for r in data["perPage"][:25]:
        print("  %6d  %s" % (r["n"], r["path"]))
    if data["perRef"]:
        print("\nCame from")
        for r in data["perRef"][:20]:
            print("  %6d  %s" % (r["n"], r["host"]))


if __name__ == "__main__":
    main()
