#!/usr/bin/env python3
"""Diff two Forever beta builds table by table (research/wago/<build>/).

  python3 tools/diff_builds.py 1.60.1.69876 1.60.1.70009           # counts per table
  python3 tools/diff_builds.py OLD NEW ItemSparse                  # row detail for one table
  python3 tools/diff_builds.py OLD NEW ItemSparse --json out.json  # machine-readable

Rows match on ID. "changed" lists the columns that moved; columns that
churn on every build without meaning anything (file data ids, hashes)
are ignored so the report shows content, not noise.
"""
import csv, json, os, sys

csv.field_size_limit(1 << 30)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NOISE = {"VerifiedBuild"}


def named_header(table, width):
    """wago.tools has no column names for some tables in some builds (it
    prints Field_<build>_000...). Borrow the names from any other build of
    the same table with the same width; the layouts line up position for
    position (verified by near-total row equality across builds)."""
    base = os.path.join(ROOT, "research", "wago")
    for b in sorted(os.listdir(base), reverse=True):
        p = os.path.join(base, b, table + ".csv")
        if os.path.exists(p):
            with open(p, newline="", encoding="utf-8") as f:
                h = next(csv.reader(f))
            if len(h) == width and not h[0].startswith("Field_"):
                return h
    return None


def load(build, table):
    path = os.path.join(ROOT, "research", "wago", build, table + ".csv")
    if not os.path.exists(path):
        return None, []
    with open(path, newline="", encoding="utf-8") as f:
        rows = csv.reader(f)
        cols = next(rows)
        if any(c.startswith("Field_") for c in cols):
            cols = named_header(table, len(cols)) or cols
        key = "ID" if "ID" in cols else cols[0]
        out = {}
        for vals in rows:
            row = dict(zip(cols, vals))
            out[row[key]] = row
        return out, cols


def diff(old, new, table):
    a, _ = load(old, table)
    b, cols = load(new, table)
    if a is None or b is None:
        return None
    added = [b[k] for k in b if k not in a]
    removed = [a[k] for k in a if k not in b]
    changed = []
    for k in b:
        if k in a and a[k] != b[k]:
            moved = [c for c in cols if c not in NOISE and a[k].get(c) != b[k].get(c)]
            if moved:
                changed.append({"id": k, "cols": moved,
                                "old": {c: a[k].get(c) for c in moved},
                                "new": {c: b[k].get(c) for c in moved}})
    return {"added": added, "removed": removed, "changed": changed}


if __name__ == "__main__":
    old, new = sys.argv[1], sys.argv[2]
    rest = sys.argv[3:]
    out_json = None
    if "--json" in rest:
        i = rest.index("--json")
        out_json = rest[i + 1]
        rest = rest[:i] + rest[i + 2:]
    tables = rest or sorted(f[:-4] for f in os.listdir(os.path.join(ROOT, "research", "wago", new)) if f.endswith(".csv"))
    report = {}
    for t in tables:
        d = diff(old, new, t)
        if d is None:
            continue
        report[t] = d
        if not rest or len(rest) > 1:
            if d["added"] or d["removed"] or d["changed"]:
                print("%-28s +%-6d -%-6d ~%d" % (t, len(d["added"]), len(d["removed"]), len(d["changed"])))
        else:
            print("%s: +%d -%d ~%d" % (t, len(d["added"]), len(d["removed"]), len(d["changed"])))
            name = next((c for c in ("Display_lang", "Name_lang", "Title_lang", "MapName_lang", "Description_lang") if d["added"] and c in d["added"][0]), None)
            for row in d["added"][:40]:
                print("  +", row.get("ID"), row.get(name, "") if name else "")
            for row in d["removed"][:20]:
                print("  -", row.get("ID"), row.get(name, "") if name else "")
            for ch in d["changed"][:40]:
                print("  ~", ch["id"], ", ".join("%s: %s -> %s" % (c, ch["old"][c], ch["new"][c]) for c in ch["cols"][:6]))
    if out_json:
        json.dump(report, open(out_json, "w"), indent=1)
        print("wrote", out_json)
