#!/usr/bin/env python3
"""Fill plan/items-db.json with what the client does not carry.

Blizzard sends most new Forever items from the server: the client has an Item
row (class, slot, icon) but no ItemSparse row, so no name, stats or tooltip.
Wowhead's Forever database has them, and its tooltip service is public, so:

  1. candidates  every item a dungeon or quest in codex/loot.json names, and
                 every client Item row without ItemSparse in the Classic or
                 Forever ID bands (SoD-era rows stay out unless loot names them)
  2. fetch       nether.wowhead.com/forever/tooltip/item/<id>, cached per item
                 in tools/.wh-cache/ (gitignored), four at a time
  3. parse       the tooltip into the database's own fields (stats, effects,
                 damage, armor, set, requirements)
  4. merge       new items join; items already in the database take Wowhead's
                 numbers where it has them (it reads the live server data our
                 budget decode approximates); every item a boss or quest gives
                 gets `drops` / `quests` from codex/loot.json

  python3 tools/scavenge_items.py            # fetch what is missing, then merge
  python3 tools/scavenge_items.py --all      # also refresh every gear item
  python3 tools/scavenge_items.py --dry      # report only
"""
import collections, concurrent.futures, csv, html, json, os, re, sys, threading, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "plan", "items-db.json")
LOOT = os.path.join(ROOT, "codex", "loot.json")
CACHE = os.path.join(ROOT, "tools", ".wh-cache")
SITE = os.path.join(ROOT, "tools", ".loot-cache", "site-items.json")
BUILD = "1.60.1.70009"
WAGO = os.path.join(ROOT, "research", "wago", BUILD)
UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36 foreverrank.com"}
QUAL = ["poor", "common", "uncommon", "rare", "epic", "legendary", "artifact", "heirloom"]
SLOT = {"1": "head", "2": "neck", "3": "shoulder", "4": "shirt", "5": "chest", "6": "waist", "7": "legs",
        "8": "feet", "9": "wrist", "10": "hands", "11": "finger", "12": "trinket", "13": "one-hand",
        "14": "off-hand", "15": "ranged", "16": "back", "17": "two-hand", "19": "tabard", "20": "chest",
        "21": "main-hand", "22": "off-hand", "23": "off-hand", "25": "thrown", "26": "ranged", "28": "relic"}
PRIMARY = {"3": "agility", "4": "strength", "5": "intellect", "6": "spirit", "7": "stamina"}
SCHOOL = {"fire": "fireSpellDamage", "frost": "frostSpellDamage", "nature": "natureSpellDamage", "shadow": "shadowSpellDamage",
          "arcane": "arcaneSpellDamage", "holy": "holySpellDamage"}
# Dev and test rows the database has always left out (SOURCES.md, cleanup passes 1 and 2).
JUNK = re.compile(r"^(monster -|test|qa |zz|dnt|\[ph\]|ph |deprecated|unused|gm |debug|nyi |old )|\b(test|dnt|deprecated|placeholder)\b|\(old\)|\(test\)", re.I)
lock = threading.Lock()


def rows(table):
    return list(csv.DictReader(open(os.path.join(WAGO, table + ".csv"), encoding="utf-8")))


def fetch(iid):
    path = os.path.join(CACHE, "%s.json" % iid)
    if os.path.exists(path):
        return json.load(open(path))
    url = "https://nether.wowhead.com/forever/tooltip/item/%s" % iid
    for attempt in range(4):
        try:
            body = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30).read().decode("utf-8")
            d = json.loads(body)
            break
        except urllib.error.HTTPError as e:
            if e.code == 404:
                d = {"error": "Entity not found"}
                break
            time.sleep(3 + attempt * 5)
        except Exception:
            time.sleep(3 + attempt * 5)
    else:
        return None
    with open(path, "w") as f:
        json.dump(d, f)
    return d


def spans(tt, cls):
    """Inner HTML of every <span ... class="cls" ...>, nested spans included."""
    out = []
    for m in re.finditer(r'<span[^>]*\bclass="%s"[^>]*>' % re.escape(cls), tt):
        j, depth = m.end(), 1
        while depth:
            o, c = tt.find("<span", j), tt.find("</span>", j)
            if c < 0:
                break
            if 0 <= o < c:
                depth, j = depth + 1, o + 5
            else:
                depth, j = depth - 1, c + 7
        if depth == 0:
            out.append(tt[m.end():j - 7])
    return out


def text(h):
    h = re.sub(r"<br\s*/?>", " ", h)
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", "", h))).replace("\xa0", " ").strip()


def equip_stats(line, st):
    """Stat lines the database searches on, read from an Equip text."""
    t = line
    def add(k, v):
        st[k] = st.get(k, 0) + v
    m = re.search(r"damage and healing done by magical spells and effects by up to (\d+)", t, re.I) or re.search(r"^Equip: \+(\d+) Spell Power", t)
    if m: add("spellPower", int(m.group(1))); return
    m = re.search(r"Increases healing done by up to (\d+) and damage done by up to (\d+)", t, re.I)
    if m: add("healing", int(m.group(1))); add("spellDamage", int(m.group(2))); return
    m = re.search(r"Increases healing done by (?:spells and effects )?(?:by )?up to (\d+)", t, re.I)
    if m: add("healing", int(m.group(1))); return
    m = re.search(r"damage done by (Fire|Frost|Nature|Shadow|Arcane|Holy) spells and effects by up to (\d+)", t, re.I)
    if m: add(SCHOOL[m.group(1).lower()], int(m.group(2))); return
    m = re.search(r"damage done by magical spells and effects by up to (\d+)", t, re.I) or re.search(r"^Equip: \+(\d+) Spell Damage", t)
    if m: add("spellDamage", int(m.group(1))); return
    m = re.search(r"\+(\d+) ranged Attack Power", t, re.I)
    if m: add("rangedAttackPower", int(m.group(1))); return
    m = re.search(r"\+(\d+) Attack Power", t, re.I)
    if m and "form" not in t.lower(): add("attackPower", int(m.group(1))); return
    m = re.search(r"chance to hit with spells by (\d+)%", t, re.I)
    if m: add("spellHit", int(m.group(1))); return
    m = re.search(r"critical strike with spells by (\d+)%", t, re.I)
    if m: add("spellCrit", int(m.group(1))); return
    m = re.search(r"chance to hit by (\d+)%", t, re.I)
    if m: add("hit", int(m.group(1))); return
    m = re.search(r"chance to get a critical strike by (\d+)%", t, re.I)
    if m: add("crit", int(m.group(1))); return
    m = re.search(r"Restores (\d+) mana per 5 sec", t, re.I)
    if m: add("mp5", int(m.group(1))); return
    m = re.search(r"Restores (\d+) health per 5 sec", t, re.I)
    if m: add("hp5", int(m.group(1))); return
    m = re.search(r"Increased Defense \+(\d+)", t, re.I)
    if m: add("defense", int(m.group(1))); return
    m = re.search(r"chance to dodge an attack by (\d+)%", t, re.I)
    if m: add("dodge", int(m.group(1))); return
    m = re.search(r"chance to parry an attack by (\d+)%", t, re.I)
    if m: add("parry", int(m.group(1))); return
    m = re.search(r"chance to block attacks with a shield by (\d+)%", t, re.I)
    if m: add("blockChance", int(m.group(1))); return
    m = re.search(r"block value of your shield by (\d+)", t, re.I)
    if m: add("blockValue", int(m.group(1))); return
    m = re.search(r"magical resistances of your spell targets by (\d+)", t, re.I)
    if m: add("spellPiercing", int(m.group(1))); return
    m = re.search(r"Increased (Axes|Swords|Maces|Daggers|Two-handed Axes|Two-handed Swords|Two-handed Maces|Bows|Guns|Crossbows|Fist Weapons|Staves|Polearms) \+(\d+)", t, re.I)
    if m:
        k = {"axes": "axeSkill", "swords": "swordSkill", "maces": "maceSkill", "daggers": "daggerSkill", "fist weapons": "unarmedSkill"}.get(m.group(1).lower().replace("two-handed ", ""), "weaponSkill")
        add(k, int(m.group(2)))


def parse(tt):
    r = {"stats": {}, "effects": []}
    m = re.search(r"<!--ilvl-->(\d+)", tt)
    if m: r["itemLevel"] = int(m.group(1))
    m = re.search(r"<!--rlvl-->(\d+)", tt)
    if m: r["reqLevel"] = int(m.group(1))
    for k, v in (("Binds when picked up", "BoP"), ("Binds when equipped", "BoE"), ("Binds when used", "BoU"), ("Quest Item", "Quest"), ("Soulbound", "BoP")):
        if k in tt:
            r["binding"] = v
            break
    m = re.search(r"<br>(Unique(?:-Equipped)?(?: \(\d+\))?)<", tt)
    if m: r["unique"] = True if m.group(1) == "Unique" else m.group(1)
    m = re.search(r'<table width="100%"><tr><td>([^<]*)</td>(?:<th>(?:<!--scstart\d+:\d+-->)?(?:<span class="q1">)?([^<]*))?', tt)
    if m:
        r["slotText"], r["typeText"] = m.group(1).strip(), (m.group(2) or "").strip()
    m = re.search(r"<!--dmg-->([\d,]+) - ([\d,]+)", tt)
    if m: r["damage"] = "%s-%s" % (m.group(1).replace(",", ""), m.group(2).replace(",", ""))
    m = re.search(r"<!--spd-->([\d.]+)", tt)
    if m: r["speed"] = float(m.group(1))
    m = re.search(r"<!--dps-->\(([\d.,]+) damage per second", tt)
    if m: r["dps"] = float(m.group(1).replace(",", ""))
    m = re.search(r"<!--amr-->([\d,]+) Armor", tt)
    if m: r["armor"] = int(m.group(1).replace(",", ""))
    m = re.search(r">(\d+) Block<", tt)
    if m: r["block"] = int(m.group(1))
    for sid, v in re.findall(r"<!--stat(\d+)-->([+-]?\d+)", tt):
        if sid in PRIMARY:
            r["stats"][PRIMARY[sid]] = r["stats"].get(PRIMARY[sid], 0) + int(v)
    for v, school in re.findall(r"\+(\d+) (Fire|Frost|Nature|Shadow|Arcane) Resistance", tt):
        k = school.lower() + "Resist"
        r["stats"][k] = r["stats"].get(k, 0) + int(v)
    m = re.search(r"\+(\d+) All Resistances", tt)
    if m: r["stats"]["allResist"] = int(m.group(1))
    for inner in spans(tt, "q2"):
        line = text(inner)
        if re.match(r"^\+\d+ ", line):
            # green stat-block bonus ("+8 Attack Power"): an Equip line without the word
            line = "Equip: " + line.rstrip(".") + "."
        if re.match(r"^(Equip|Use|Chance on hit):", line):
            r["effects"].append(line)
            if line.startswith("Equip:"):
                equip_stats(line, r["stats"])
    m = re.search(r"Classes: (.*?)</", tt)
    if m: r["cls"] = [text(c) for c in re.findall(r">([^<]+)</a>", m.group(0) + "</") if text(c)] or [text(m.group(1))]
    m = re.search(r'<a href="/forever/item-set=(\d+)[^"]*"[^>]*>([^<]+)</a>', tt)
    if m:
        r["setName"] = html.unescape(m.group(2))
        r["setPieces"] = [html.unescape(n) for _, n in re.findall(r'<!--si(\d+)--><a [^>]*>([^<]+)</a>', tt)]
        r["setBonuses"] = [[int(n), text(b)] for n, b in re.findall(r"\((\d+)\) Set\s*:\s*(.*?)</span>", tt)]
    m = re.search(r'<span class="q">&quot;(.*?)&quot;</span>', tt) or re.search(r'<span class="q">"(.*?)"</span>', tt)
    if m: r["flavor"] = text(m.group(1))
    if "This Item Begins a Quest" in tt: r["startsQuest"] = True
    m = re.search(r"Requires ([A-Z][A-Za-z' ]+) \((\d+)\)", text(tt))
    if m and m.group(1) not in ("Level",): r["reqSkill"] = "%s %s" % (m.group(1), m.group(2))
    return r


def main():
    dry, refresh_all = "--dry" in sys.argv, "--all" in sys.argv
    os.makedirs(CACHE, exist_ok=True)
    db = json.load(open(DB))
    by = {str(i["id"]): i for i in db["items"]}
    loot = json.load(open(LOOT))
    site = json.load(open(SITE)) if os.path.exists(SITE) else {"fc": {}, "wtbc": {}}
    item = {r["ID"]: r for r in rows("Item")}
    sparse = {r["ID"] for r in rows("ItemSparse")}

    # who gives what
    drops, quests = collections.defaultdict(list), collections.defaultdict(list)
    for d in loot["dungeons"]:
        for b in d["bosses"]:
            for i in b["items"]:
                e = [d["name"], b["name"]] + (["rare"] if b.get("kind") == "rare" else [])
                if e not in drops[str(i)]: drops[str(i)].append(e)
        for q in d["quests"]:
            for i in q["items"]:
                e = [q["name"], d["name"]]
                if e not in quests[str(i)]: quests[str(i)].append(e)
    looted = set(drops) | set(quests)

    def band_ok(i):
        n = int(i)
        return n < 100000 or n >= 239000
    missing = {i for i in item if i not in sparse and i not in by and band_ok(i)}
    want = looted | missing
    if refresh_all:
        want |= {i for i, it in by.items() if it.get("cat") in ("weapon", "armor", "accessory", "offhand", "consumable")
                 or "..." in " ".join(it.get("effects") or [])}
    todo = sorted((i for i in want if not os.path.exists(os.path.join(CACHE, i + ".json"))), key=int)
    print("candidates %d (loot %d, server-sent %d); to fetch %d" % (len(want), len(looted), len(missing), len(todo)))
    done = [0]
    t0 = time.time()

    def job(i):
        fetch(i)
        with lock:
            done[0] += 1
            if done[0] % 250 == 0:
                rate = done[0] / max(1, time.time() - t0)
                print("  fetched %d/%d (%.1f/s, ~%d min left)" % (done[0], len(todo), rate, (len(todo) - done[0]) / max(rate, .1) / 60), flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
        list(ex.map(job, todo))

    # classify new rows the way the database already classifies their client class
    vote3, vote2 = collections.defaultdict(collections.Counter), collections.defaultdict(collections.Counter)
    for iid, it in by.items():
        ir = item.get(iid)
        if ir:
            vote3[(ir["ClassID"], ir["SubclassID"], ir["InventoryType"])][(it["cat"], it["sub"], it.get("type"))] += 1
            vote2[(ir["ClassID"], ir["SubclassID"])][(it["cat"], it["sub"], it.get("type"))] += 1

    added, refreshed, junk, unknown, absent = [], 0, 0, 0, {}
    for iid in sorted(want, key=int):
        path = os.path.join(CACHE, iid + ".json")
        wh = json.load(open(path)) if os.path.exists(path) else None
        ok = wh and "tooltip" in wh
        p = parse(wh["tooltip"]) if ok else None
        old = by.get(iid)
        is_new = old is None
        if iid in looted and not ok and iid not in sparse and is_new:
            fcn = (site["fc"].get(iid) or {}).get("n") or (site["wtbc"].get(iid) or {}).get("name") or ""
            absent[iid] = html.unescape(fcn)
            continue
        if is_new:
            name = wh["name"] if ok else (site["fc"].get(iid) or {}).get("n") or (site["wtbc"].get(iid) or {}).get("name")
            if not name:
                unknown += 1
                continue
            if JUNK.search(name) and iid not in looted:
                junk += 1
                continue
            ir = item.get(iid, {})
            key3 = (ir.get("ClassID"), ir.get("SubclassID"), ir.get("InventoryType"))
            cat, sub, typ = (vote3.get(key3) or vote2.get(key3[:2]) or collections.Counter({("misc", "Other", None): 1})).most_common(1)[0][0]
            qn = wh.get("quality") if ok else (site["fc"].get(iid) or {}).get("q", 1)
            old = {"id": iid, "name": html.unescape(name), "quality": QUAL[int(qn or 1)],
                   "slot": SLOT.get(ir.get("InventoryType", ""), "unknown"), "cat": cat, "sub": sub,
                   "icon": (wh.get("icon") if ok else (site["fc"].get(iid) or {}).get("k")) or "inv_misc_questionmark"}
            if typ: old["type"] = typ
            if int(iid) >= 239000: old["nw"] = 1
            elif 199000 <= int(iid) < 239000: old["era"] = "sod"
            old["source"] = "Loot record (foreverchanges.pro / wowtbc.gg)"
            added.append(old)
        if ok:
            # Wowhead reads the live server data; where it has an item, its numbers win.
            for k in ("itemLevel", "reqLevel", "binding", "damage", "speed", "dps", "armor", "block", "unique", "flavor", "cls", "reqSkill", "startsQuest"):
                if p.get(k) is not None: old[k] = p[k]
            wearable = old.get("slot") not in (None, "unknown")
            if not wearable:
                pass  # Wowhead lists a potion's buff as stat lines; only gear keeps stats
            elif p["stats"] or p["effects"] or not old.get("stats"):
                old["stats"] = p["stats"] or None
            old["effects"] = p["effects"] or old.get("effects") or None
            if p.get("setName"):
                old["setName"], old["setPieces"], old["setBonuses"] = p["setName"], p["setPieces"], p["setBonuses"]
            old["name"] = html.unescape(wh["name"])
            old["quality"] = QUAL[int(wh.get("quality") or 1)]
            if wh.get("icon"): old["icon"] = wh["icon"]
            old["wh"] = 1
            if iid not in sparse: old["source"] = "Server data via Wowhead's Forever database"
            if not is_new: refreshed += 1
        for k in ("stats", "effects"):
            if not old.get(k): old.pop(k, None)
        # Classic's suffix greens and blues ("of the Eagle"): the base item carries no stats
        if ok and is_new and int(iid) < 100000 and old.get("slot") not in (None, "unknown") and old["quality"] in ("uncommon", "rare") \
                and not old.get("stats") and not old.get("effects"):
            old["rand"] = 1
        if drops.get(iid): old["drops"] = drops[iid]
        if quests.get(iid): old["quests"] = quests[iid]
    # loot links for items that never needed a refetch
    for iid, it in by.items():
        if drops.get(iid): it["drops"] = drops[iid]
        if quests.get(iid): it["quests"] = quests[iid]
        # a recorded Forever drop is wired loot, whatever ID band it sits in
        if iid in looted and it.get("era") in ("sod", "retail"):
            it.pop("era", None)
            it["eraNote"] = "Recorded as Forever loot"

    have = set(by) | {e["id"] for e in added}
    print("added %d, refreshed from Wowhead %d, junk skipped %d, unknown (no name anywhere) %d" % (len(added), refreshed, junk, unknown))
    print("loot items covered %d/%d; %d are Classic loot absent from Forever's data" % (len(looted & have), len(looted), len(absent)))
    print("new by cat", collections.Counter(e["cat"] for e in added).most_common())
    if dry:
        print("(dry run)")
        return
    db["items"] = db["items"] + added
    db["items"].sort(key=lambda i: int(i["id"]))
    db["note"] = re.sub(r"\s*Server-sent items.*$", "", db["note"]) + (
        " Server-sent items (most new dungeon loot and quest rewards: the client holds no stats for them) and live tooltip "
        "text come from Wowhead's Forever database; who drops what comes from codex/loot.json (tools/scavenge_items.py).")
    db["scavenged"] = time.strftime("%Y-%m-%d")
    with open(DB, "w") as f:
        json.dump(db, f, ensure_ascii=False, separators=(",", ":"))
    print("wrote %s: %d items" % (os.path.relpath(DB, ROOT), len(db["items"])))
    loot["absent"] = {k: absent[k] for k in sorted(absent, key=int)}
    loot["note"] = re.sub(r"\s*Items under absent.*$", "", loot["note"]) + (
        " Items under absent are in a site's table (usually Classic's) but not yet in Forever's data: not in the client's item "
        "tables and not in Wowhead's Forever database. Mostly loot above the beta's level cap that nobody has looted yet.")
    with open(LOOT, "w") as f:
        json.dump(loot, f, ensure_ascii=False, separators=(",", ":"))
    # The World page's loot tables load only the items a dungeon or quest names.
    keep = [i for i in db["items"] if str(i["id"]) in looted]
    with open(os.path.join(ROOT, "codex", "loot-items.json"), "w") as f:
        json.dump({"note": "Items named by codex/loot.json, in the database's own format.", "items": keep}, f, ensure_ascii=False, separators=(",", ":"))
    print("wrote codex/loot-items.json: %d items" % len(keep))


if __name__ == "__main__":
    main()
