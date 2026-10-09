#!/usr/bin/env python3
"""PvP ranks and Honor from the Forever client: codex/pvp.json for the Database's PvP ranks section.

From the client build (research/wago/<BUILD>/, pulled by tools/fetch_wago.py):
  rank names    the Legacy challenge achievements "Reach the rank of <Alliance> or <Horde> ..." (title "Rank N"),
                spelled as the titles in CharTitles; their icons from Achievement.IconFileID
  rank points   Faction 2800 "PvP Rank Points" -> RenownThresholdCurveID (Curve 103650): the points each rank asks
  weekly cap    CurrencyTypes 3473 "Renown - PvP Rank" -> MaxQtyCurveID (Curve 102601): the highest rank by week
  Honor cap     CurrencyTypes 1792 MaxQty, and what it was in the oldest build on disk
  Legacy        which rank achievements pay a Legacy Point (Reward_lang)
  brackets      PVPDifficulty and BattlemasterList for Darkspear Islands
Rank rewards are Blizzard's word (How PvP Progression Works, Oct 7 2026), not client data; the file says so.

  python3 tools/build_pvp.py                 # build below
  python3 tools/build_pvp.py 1.60.1.70291
"""
import collections, csv, datetime, json, os, re, sys

csv.field_size_limit(1 << 30)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = sys.argv[1] if len(sys.argv) > 1 else "1.60.1.70291"
OUT = os.path.join(ROOT, "codex", "pvp.json")
BLIZZ = "https://worldofwarcraft.blizzard.com/en-us/news/24303316"
# Blizzard's rank rewards (How PvP Progression in World of Warcraft: Forever Works, 2026-10-07)
REWARDS = {1: "Tabard", 2: "PvP trinket", 3: "Cloaks", 4: "Necklace", 5: "Combat potions", 6: "Tabard", 7: "Battle standard",
           8: "Epic bracers or belt token", 9: "Epic boots token", 10: "Epic gloves token", 11: "Mounts",
           12: "Epic legs or shoulders token", 13: "Epic chest or helm token", 14: "Epic weapons"}


def rows(table, build=None):
    path = os.path.join(ROOT, "research", "wago", build or BUILD, table + ".csv")
    if not os.path.exists(path):
        return None
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def need(table):
    r = rows(table)
    if r is None:
        sys.exit("missing table %s: python3 tools/fetch_wago.py %s %s" % (table, BUILD, table))
    return r


def curve(cid, points):
    return [(int(float(r["Pos_0"])), int(float(r["Pos_1"]))) for r in sorted(points, key=lambda r: int(r["OrderIndex"])) if r["CurveID"] == str(cid)]


def key(s):
    return re.sub(r"[^a-z]", "", s.lower())


def main():
    icons = {}
    for line in open(os.path.join(ROOT, "tools", "icon-listfile.csv"), encoding="utf-8"):
        fid, _, path = line.strip().partition(";")
        if path.startswith("interface/icons/"):
            icons[fid] = path[16:].rsplit(".", 1)[0]
    titles = {key(r["Name_lang"].replace("%s", "")): r["Name_lang"].replace("%s", "").strip() for r in need("CharTitles") if r["Flags"] == "4"}
    faction = {r["ID"]: r for r in need("Faction")}["2800"]
    cur = {r["ID"]: r for r in need("CurrencyTypes")}
    points = need("CurvePoint")
    bars = dict(curve(faction["RenownThresholdCurveID"], points))
    weekly = [[w, r] for w, r in curve(cur["3473"]["MaxQtyCurveID"], points) if w > 0]

    ranks, legacy = {}, set()
    for a in need("Achievement"):
        m = re.match(r"(?:Hidden: )?Rank (\d+)$", a["Title_lang"])
        t = re.match(r"Reach the rank of (.+?) in the Player vs\. Player Honor System", a["Description_lang"])
        if not (m and t):
            continue
        n = int(m.group(1))
        both = t.group(1).split(" or ")
        named = [titles.get(key(x), x) for x in both]
        ranks.setdefault(n, {"r": n, "a": named[0], "h": named[-1], "icon": icons.get(a["IconFileID"], "")})
        if "Legacy Point" in (a["Reward_lang"] or ""):
            legacy.add(n)
    out_ranks = []
    for n in sorted(ranks):
        x = ranks[n]
        x["pts"] = bars.get(n, 0)
        x["week"] = next((w for w, r in weekly if r >= n), None)
        if n in legacy:
            x["lp"] = 1
        x["reward"] = REWARDS.get(n, "")
        out_ranks.append(x)

    # what the Honor cap was before, from the oldest build on disk that still differs
    honor = int(cur["1792"]["MaxQty"])
    was, changed = None, None
    builds = sorted((d for d in os.listdir(os.path.join(ROOT, "research", "wago")) if d.startswith("1.60.")), key=lambda b: [int(x) for x in b.split(".")])
    for b in builds:
        old = rows("CurrencyTypes", b) or []
        v = next((int(r["MaxQty"]) for r in old if r.get("ID") == "1792" and r.get("MaxQty")), None)
        if v is None:
            continue  # table not pulled for this build, or under other column names
        if v != honor:
            was, changed = [v, b], None
        elif changed is None:
            changed = b

    seals = [{"id": int(r["ID"]), "n": r["Display_lang"], "lvl": int(r["RequiredLevel"] or 0)}
             for r in need("ItemSparse") if r["Display_lang"].startswith("Premier Emboldened")]
    bm = {r["ID"]: r for r in need("BattlemasterList")}.get("1157") or {}
    brackets = sorted([[int(r["MinLevel"]), int(r["MaxLevel"])] for r in need("PVPDifficulty") if r["MapID"] == "2997"])
    mp = {r["ID"]: r for r in need("Map")}.get("2997") or {}

    out = {
        "note": ("PvP ranks and Honor in the WoW: Forever beta client, build %s (tools/build_pvp.py). Rank names, rank "
                 "points, the weekly rank cap, the Honor cap and Legacy Points are client data; reading the rank-point "
                 "curve as the points each rank's bar asks, and the cap curve's steps as weeks of a season, is our "
                 "inference. Rewards per rank are Blizzard's (%s)." % (BUILD, BLIZZ)),
        "build": BUILD, "generated": datetime.date.today().isoformat(),
        "honorCap": honor, "honorWas": was, "honorSince": changed,
        "rankPoints": {"name": cur["3468"]["Name_lang"], "about": cur["3468"]["Description_lang"]} if "3468" in cur else None,
        "total": sum(x["pts"] for x in out_ranks), "weekly": weekly, "ranks": out_ranks, "seals": seals,
        "rewardsSrc": BLIZZ,
        "darkspear": {"levels": [int(bm.get("MinLevel") or 0), int(bm.get("MaxLevel") or 0)], "players": int(bm.get("MaxPlayers") or 0),
                      "brackets": brackets, "goal": [x.strip(" -") for x in re.split(r"[\r\n]+", mp.get("PvpLongDescription_lang") or "") if x.strip(" -")]},
    }
    json.dump(out, open(OUT, "w"), ensure_ascii=False, separators=(",", ":"))
    print("wrote %s: %d ranks, %d rank points to 14, Honor cap %d (was %s, since %s), weekly %s" % (
        os.path.relpath(OUT, ROOT), len(out_ranks), out["total"], honor, was, changed, weekly))
    for x in out_ranks:
        print("  %2d %-22s %-20s %5d week %s%s  %s" % (x["r"], x["a"], x["h"], x["pts"], x["week"], " LP" if x.get("lp") else "", x["icon"]))
    print("  darkspear", out["darkspear"])


if __name__ == "__main__":
    main()
