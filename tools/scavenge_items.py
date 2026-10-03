#!/usr/bin/env python3
"""Fill plan/items-db.json with the current Forever tooltip of every item.

The client holds only part of it: Blizzard sends most new Forever items from
the server (Item row, no ItemSparse row), and changed Classic items get their
new numbers the same way, so a client datamine shows old or no stats. Three
sources, in this order, each used only where the one above has nothing:

  1. ForeverChanges  foreverchanges.pro/items/{new,changed,same}.json: the
                     current beta tooltip of ~19,500 items in Forever's own
                     wording ("+14 Critical Strike Rating"), with the Classic
                     version of every changed item alongside
  2. Wowhead         nether.wowhead.com/forever/tooltip/item/<id>, the public
                     tooltip service; complete but behind on changed items
  3. our datamine    the client's own rows

Every item a dungeon boss or quest gives (codex/loot.json) gets drops/quests.
Caches: tools/.wh-cache/ and tools/.loot-cache/ (both gitignored).

  python3 tools/scavenge_items.py            # fetch what is missing, then merge
  python3 tools/scavenge_items.py --all      # also check Wowhead for every gear item
  python3 tools/scavenge_items.py --refresh  # re-download ForeverChanges' item files
  python3 tools/scavenge_items.py --dry      # report only
  python3 tools/scavenge_items.py --recheck-missing   # ask again about old "not found" answers (fetch only)
  python3 tools/scavenge_items.py --refresh-found     # ask again about Wowhead-only items older than FOUND_DAYS (fetch only)
  python3 tools/scavenge_items.py --refresh-found --ids=23577,17943   # just these
  python3 tools/scavenge_items.py --no-fetch # merge from the caches only
"""
import collections, concurrent.futures, csv, html, json, os, re, sys, threading, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(ROOT, "plan", "items-db.json")
LOOT = os.path.join(ROOT, "codex", "loot.json")
CACHE = os.path.join(ROOT, "tools", ".wh-cache")
SITE = os.path.join(ROOT, "tools", ".loot-cache", "site-items.json")
BUILD = "1.60.1.70170"
WAGO = os.path.join(ROOT, "research", "wago", BUILD)
UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36 foreverrank.com"}
QUAL = ["poor", "common", "uncommon", "rare", "epic", "legendary", "artifact", "heirloom"]
INVTYPE = {"INVTYPE_HEAD": "1", "INVTYPE_NECK": "2", "INVTYPE_SHOULDER": "3", "INVTYPE_BODY": "4", "INVTYPE_CHEST": "5",
           "INVTYPE_WAIST": "6", "INVTYPE_LEGS": "7", "INVTYPE_FEET": "8", "INVTYPE_WRIST": "9", "INVTYPE_HAND": "10",
           "INVTYPE_FINGER": "11", "INVTYPE_TRINKET": "12", "INVTYPE_WEAPON": "13", "INVTYPE_SHIELD": "14", "INVTYPE_RANGED": "15",
           "INVTYPE_CLOAK": "16", "INVTYPE_2HWEAPON": "17", "INVTYPE_BAG": "18", "INVTYPE_TABARD": "19", "INVTYPE_ROBE": "20",
           "INVTYPE_WEAPONMAINHAND": "21", "INVTYPE_WEAPONOFFHAND": "22", "INVTYPE_HOLDABLE": "23", "INVTYPE_AMMO": "24",
           "INVTYPE_THROWN": "25", "INVTYPE_RANGEDRIGHT": "26", "INVTYPE_QUIVER": "27", "INVTYPE_RELIC": "28"}
SLOT = {"1": "head", "2": "neck", "3": "shoulder", "4": "shirt", "5": "chest", "6": "waist", "7": "legs",
        "8": "feet", "9": "wrist", "10": "hands", "11": "finger", "12": "trinket", "13": "one-hand",
        "14": "off-hand", "15": "ranged", "16": "back", "17": "two-hand", "19": "tabard", "20": "chest",
        "21": "main-hand", "22": "off-hand", "23": "off-hand", "25": "thrown", "26": "ranged", "28": "relic"}
PRIMARY = {"3": "agility", "4": "strength", "5": "intellect", "6": "spirit", "7": "stamina"}
SCHOOL = {"fire": "fireSpellDamage", "frost": "frostSpellDamage", "nature": "natureSpellDamage", "shadow": "shadowSpellDamage",
          "arcane": "arcaneSpellDamage", "holy": "holySpellDamage"}
# Dev and test rows the database has always left out (SOURCES.md, cleanup passes 1 and 2).
# "High Test" is a real fishing line (19971 High Test Eternium Fishing Line), not a test row.
JUNK = re.compile(r"^(monster -|test|qa |qaench|zz|dnt|\[ph\]|ph |deprecated|unused|gm |debug|nyi |old )|\b(?<!high )test\b|\b(dnt|deprecated|placeholder)\b|\(old\)|\(test\)|\(nyi\)|\([a-z]*test\)", re.I)
lock = threading.Lock()


def rows(table):
    return list(csv.DictReader(open(os.path.join(WAGO, table + ".csv"), encoding="utf-8")))


NF_DAYS = 3        # a "not found" answer is asked again after this many days: Wowhead adds Forever items as players see them
FOUND_DAYS = 5     # an item only Wowhead knows is asked again after this many days: the server's numbers move (The Hungering
                   # Cold read 213 dps for a week after Wowhead had 73)
SPACING = 3.2      # seconds between requests to Wowhead
_last = [0.0]


def stale_nf(iid):
    """Is the cached answer a "not found" older than NF_DAYS?"""
    path = os.path.join(CACHE, "%s.json" % iid)
    if not os.path.exists(path):
        return False
    try:
        d = json.load(open(path))
    except ValueError:
        return True
    if "error" not in d:
        return False
    at = d.get("at") or os.path.getmtime(path)
    return time.time() - at > NF_DAYS * 86400


def fetch(iid, recheck=False, force=False):
    path = os.path.join(CACHE, "%s.json" % iid)
    if os.path.exists(path) and not force and not (recheck and stale_nf(iid)):
        return json.load(open(path))
    wait = SPACING - (time.time() - _last[0])
    if wait > 0:
        time.sleep(wait)
    _last[0] = time.time()
    url = "https://nether.wowhead.com/forever/tooltip/item/%s" % iid
    for attempt in range(4):
        try:
            body = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30).read().decode("utf-8")
            d = json.loads(body)
            break
        except urllib.error.HTTPError as e:
            if e.code == 404:
                d = {"error": "Entity not found", "at": int(time.time())}
                break
            time.sleep(3 + attempt * 5)
        except Exception:
            time.sleep(3 + attempt * 5)
    else:
        return None
    with open(path, "w") as f:
        json.dump(d, f)
    return d


def cached(iid):
    """The cached Wowhead answer, or None. A file another run is writing right now reads as None."""
    path = os.path.join(CACHE, "%s.json" % iid)
    if not os.path.exists(path):
        return None
    try:
        return json.load(open(path))
    except ValueError:
        return None


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


def plus_line(line, add):
    """'Equip: +N <stat>[ Rating][.]' in Forever's wording (ForeverChanges and Wowhead both write it, Wowhead with a
    full stop). Returns True when the line was a stat line it knows."""
    m = re.match(r"^Equip: ([+-]\d+) (.+?)\.?$", line.strip())
    if not m:
        return False
    v, what = int(m.group(1)), m.group(2)
    rm = re.match(r"^(.+) Rating$", what)
    if rm and RATING.get(rm.group(1)):
        key = RATING[rm.group(1)]
        add(key[0], v)
        if key[1]: add(key[1], v / key[2])
        return True
    sm = re.match(r"^(Fire|Frost|Nature|Shadow|Arcane|Holy) Spell Damage$", what)
    if sm:
        add(sm.group(1).lower() + "SpellDamage", v)
        return True
    for pat, key in FC_EQUIP:
        if what == pat:
            add(key, v)
            return True
    km = re.match(r"^(Axes|Swords|Maces|Daggers|Fist Weapons|Staves|Polearms|Bows|Guns|Crossbows|Two-Handed Axes|Two-Handed Swords|Two-Handed Maces) Skill$", what)
    if km:
        add({"Axes": "axeSkill", "Swords": "swordSkill", "Maces": "maceSkill", "Daggers": "daggerSkill", "Fist Weapons": "unarmedSkill"}.get(km.group(1).replace("Two-Handed ", ""), "weaponSkill"), v)
        return True
    return False


# Wowhead's Forever tooltips word ratings as "Increases your critical strike by 14." (the same number ForeverChanges
# writes as "+14 Critical Strike Rating")
WH_RATING = {"critical strike": "Critical Strike", "hit": "Hit", "haste": "Haste", "expertise": "Expertise", "dodge": "Dodge",
             "parry": "Parry", "block": "Block"}


def equip_stats(line, st):
    """Stat lines the database searches on, read from an Equip text (Classic's wording or Forever's)."""
    t = line.strip()
    def add(k, v):
        st[k] = round(st.get(k, 0) + v, 2)
    if plus_line(t, add): return
    m = re.search(r"damage and healing done by magical spells and effects by up to (\d+)", t, re.I) or re.search(r"^Equip: \+(\d+) Spell Power\.?$", t)
    if m: add("spellPower", int(m.group(1))); return
    m = re.search(r"Increases healing done by up to (\d+) and damage done by up to (\d+)", t, re.I)
    if m: add("healing", int(m.group(1))); add("spellDamage", int(m.group(2))); return
    m = re.search(r"Increases healing done by (?:magical )?(?:spells and effects )?(?:by )?up to (\d+)", t, re.I)
    if m: add("healing", int(m.group(1))); return
    m = re.search(r"damage done by (Fire|Frost|Nature|Shadow|Arcane|Holy) spells and effects by up to (\d+)", t, re.I)
    if m: add(SCHOOL[m.group(1).lower()], int(m.group(2))); return
    m = re.search(r"damage done by magical spells and effects by up to (\d+)", t, re.I) or re.search(r"^Equip: \+(\d+) Spell Damage\.?$", t)
    if m: add("spellDamage", int(m.group(1))); return
    m = re.search(r"\+(\d+) ranged Attack Power", t, re.I)
    if m: add("rangedAttackPower", int(m.group(1))); return
    m = re.search(r"\+(\d+) Attack Power", t, re.I)
    # "+N Attack Power Vs Beasts", "when fighting Undead", "in Cat, Bear ... forms only" are conditional
    if m and not re.search(r"form| vs |fighting|Attack Power against", t, re.I): add("attackPower", int(m.group(1))); return  # "+16 Attack Power against Beasts"
    m = re.search(r"chance to hit with spells by ([\d.]+)%", t, re.I)
    if m: add("spellHit", float(m.group(1))); return
    m = re.search(r"critical strike with spells by ([\d.]+)%", t, re.I)
    if m: add("spellCrit", float(m.group(1))); return
    m = re.search(r"chance to hit by ([\d.]+)%", t, re.I)
    if m: add("hit", float(m.group(1))); return
    m = re.search(r"chance to get a critical strike by ([\d.]+)%", t, re.I)
    if m: add("crit", float(m.group(1))); return
    # Forever's ratings as Wowhead shows them since early October 2026: percentages
    m = re.search(r"Increases your attack speed and casting speed by ([\d.]+)%", t, re.I)
    if m: add("haste", float(m.group(1))); return
    m = re.search(r"Reduces chance to be Dodged or Parried by ([\d.]+)%", t, re.I)
    if m: add("expertise", float(m.group(1))); return
    m = re.search(r"Restores (\d+) mana per 5 sec", t, re.I)
    if m: add("mp5", int(m.group(1))); return
    m = re.search(r"Restores (\d+) health per 5 sec", t, re.I)
    if m: add("hp5", int(m.group(1))); return
    m = re.search(r"Increased Defense \+(\d+)", t, re.I)
    if m: add("defense", int(m.group(1))); return
    m = re.search(r"Increases defense skill by (\d+)", t, re.I)
    if m:
        key = RATING["Defense"]
        add(key[0], int(m.group(1))); add(key[1], int(m.group(1)) / key[2]); return
    m = re.search(r"chance to dodge an attack by ([\d.]+)%", t, re.I)
    if m: add("dodge", float(m.group(1))); return
    m = re.search(r"chance to parry an attack by ([\d.]+)%", t, re.I)
    if m: add("parry", float(m.group(1))); return
    m = re.search(r"chance to block attacks with a shield by ([\d.]+)%", t, re.I)
    if m: add("blockChance", float(m.group(1))); return
    m = re.search(r"block value of your shield by (\d+)\b(?!\s*%)", t, re.I) or re.search(r"Increases your shield block by (\d+)\b(?!\s*%)", t, re.I)
    if m and not re.search(r"\bwhile\b", t, re.I): add("blockValue", int(m.group(1))); return  # not Steadfast Libram's 30% during Holy Shield
    m = re.search(r"^Equip: Increases your (critical strike|hit|haste|expertise|dodge|parry|block) by (\d+)\.?$", t, re.I)
    if m:
        key = RATING[WH_RATING[m.group(1).lower()]]
        add(key[0], int(m.group(2)))
        if key[1]: add(key[1], int(m.group(2)) / key[2])
        return
    m = re.search(r"magical resistances of your spell targets by (\d+)", t, re.I) or re.search(r"Your spells pierce (\d+) Magical Resistances", t, re.I)
    if m: add("spellPiercing", int(m.group(1))); return
    m = re.search(r"^Equip: Increases all Resistances by (\d+)", t, re.I)
    if m: add("allResist", int(m.group(1))); return
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
        elif sid == "50":  # "+140 Armor" in the white stat block: bonus armor (newer Wowhead tooltips)
            r["stats"]["bonusArmor"] = r["stats"].get("bonusArmor", 0) + int(v)
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


FC_FILES = ("new", "changed", "same", "missing")
RATING = {"Critical Strike": ("critRating", "crit", 14), "Hit": ("hitRating", "hit", 10), "Dodge": ("dodgeRating", "dodge", 12),
          "Parry": ("parryRating", "parry", 15), "Block": ("blockRating", "blockChance", 5), "Defense": ("defenseRating", "defense", 1),
          "Haste": ("hasteRating", None, 0), "Expertise": ("expertiseRating", None, 0)}
FC_EQUIP = [(r"Spell Power", "spellPower"), (r"Healing", "healing"), (r"Spell Damage", "spellDamage"), (r"Attack Power", "attackPower"),
            (r"Ranged Attack Power", "rangedAttackPower"), (r"Mana Regeneration", "mp5"), (r"Health Regeneration", "hp5"),
            (r"Block Value", "blockValue"), (r"Spell Penetration", "spellPiercing"), (r"Armor Penetration", "armorPen"),
            (r"Fishing", "fishing"), (r"Bonus Armor", "bonusArmor"), (r"Weapon Damage", "weaponDamage")]


def fc_items(refresh=False):
    """ForeverChanges' item files, cached. Returns ({id: record}, meta)."""
    out, meta = {}, {}
    for name in FC_FILES:
        path = os.path.join(ROOT, "tools", ".loot-cache", "fc-items-%s.json" % name)
        if refresh or not os.path.exists(path):
            body = urllib.request.urlopen(urllib.request.Request("https://foreverchanges.pro/items/%s.json" % name, headers=UA), timeout=120).read()
            open(path, "wb").write(body)
        d = json.load(open(path))
        meta = {k: d[k] for k in ("forever_build", "forever_build_date") if k in d}
        for it in d.get("items") or []:
            out[str(it["i"])] = it
    return out, meta


def fc_parse(f, sets):
    """One ForeverChanges record in the database's fields, wording kept."""
    r = {"stats": {}, "effects": []}
    st = r["stats"]
    def add(k, v):
        st[k] = round(st.get(k, 0) + v, 2)
    for line in f.get("x") or []:
        if line in ("Binds when picked up", "Soulbound"): r["binding"] = "BoP"; continue
        if line == "Binds when equipped": r["binding"] = "BoE"; continue
        if line == "Binds when used": r["binding"] = "BoU"; continue
        if line == "Quest Item": r["binding"] = "Quest"; continue
        if line.startswith("Unique"): r["unique"] = True if line == "Unique" else line; continue
        if line == "This Item Begins a Quest": r["startsQuest"] = True; continue
        if line.startswith("Sell Price") or "\t" in line and not re.search(r"Damage\tSpeed", line): continue
        m = re.match(r"^([\d,]+) - ([\d,]+) Damage\tSpeed ([\d.]+)", line)
        if m: r["damage"], r["speed"] = "%s-%s" % (m.group(1).replace(",", ""), m.group(2).replace(",", "")), float(m.group(3)); continue
        m = re.match(r"^\(([\d.,]+) damage per second\)", line)
        if m: r["dps"] = float(m.group(1).replace(",", "")); continue
        m = re.match(r"^\+[\d,]+ - [\d,]+ \w+ Damage$", line)
        if m: r["dmgExtra"] = line; continue
        m = re.match(r"^([\d,]+) Armor$", line)
        if m: r["armor"] = int(m.group(1).replace(",", "")); continue
        m = re.match(r"^\+([\d,]+) Armor$", line)
        if m: add("bonusArmor", int(m.group(1).replace(",", ""))); continue
        m = re.match(r"^([\d,]+) Block$", line)
        if m: r["block"] = int(m.group(1).replace(",", "")); continue
        m = re.match(r"^([+-]\d+) (Strength|Agility|Stamina|Intellect|Spirit)$", line)
        if m: add(m.group(2).lower(), int(m.group(1))); continue
        m = re.match(r"^([+-]\d+) (.+?) Rating$", line)  # a rating as a plain green line (ForeverChanges writes "Equip: +N ... Rating")
        if m and RATING.get(m.group(2)):
            key = RATING[m.group(2)]
            add(key[0], int(m.group(1)))
            if key[1]: add(key[1], int(m.group(1)) / key[2])
            continue
        m = re.match(r"^\+(\d+) (Fire|Frost|Nature|Shadow|Arcane|Holy) Resistance$", line)
        if m: add(m.group(2).lower() + "Resist", int(m.group(1))); continue
        m = re.match(r"^\+(\d+) All Resistances$", line)
        if m: add("allResist", int(m.group(1))); continue
        m = re.match(r"^Requires Level (\d+)", line)
        if m: r["reqLevel"] = int(m.group(1)); continue
        m = re.match(r"^Requires ([A-Z][A-Za-z' ]+) \((\d+)\)$", line)
        if m: r["reqSkill"] = "%s %s" % (m.group(1), m.group(2)); continue
        m = re.match(r"^Classes: (.+)$", line)
        if m: r["cls"] = [c.strip() for c in m.group(1).split(",")]; continue
        m = re.match(r"^(.+) \(\d+/(\d+)\)$", line)
        if m: r["setName"] = m.group(1); continue
        m = re.match(r"^\((\d+)\) Set: (.+)$", line)
        if m: r.setdefault("setBonuses", []).append([int(m.group(1)), m.group(2)]); continue
        if line.startswith('"') and line.endswith('"'): r["flavor"] = line.strip('"'); continue
        if re.match(r"^(Equip|Use|Chance on hit):", line):
            r["effects"].append(line)
            if line.startswith("Equip:"):
                # Forever's "+N <stat>[ Rating]" first, then the Classic wording ForeverChanges keeps for some items
                # (all of its 'missing' file): "Increases damage and healing done by ... by up to N."
                equip_stats(line, st)
    if f.get("o"): r["cls"] = [c.strip() for c in str(f["o"]).split(",")]
    if f.get("e") and sets.get(f["e"]): r["setPieces"] = sets[f["e"]]
    if f.get("l"): r["itemLevel"] = f["l"]
    if f.get("r") and "reqLevel" not in r: r["reqLevel"] = f["r"]
    return r


def recheck_missing():
    """Ask Wowhead again about every cached "not found" older than NF_DAYS: dungeon loot first, then gear the client
    has a row for, then the rest. Fetch only; a normal run merges what comes back."""
    loot = json.load(open(LOOT))
    looted = set()
    for d in loot.get("dungeons") or []:
        for b in d.get("bosses") or []:
            looted |= {str(i) for i in b.get("items") or []}
        for q in d.get("quests") or []:
            looted |= {str(i) for i in q.get("items") or []}
    looted |= {str(i) for i in (loot.get("absent") or {})}
    gear = {r["ID"] for r in rows("Item") if r.get("ClassID") in ("2", "4")}
    stale = [f[:-5] for f in os.listdir(CACHE) if f.endswith(".json") and f[:-5].isdigit() and stale_nf(f[:-5])]
    order = sorted(stale, key=lambda i: (0 if i in looted else 1 if i in gear else 2, int(i)))
    buckets = collections.Counter(0 if i in looted else 1 if i in gear else 2 for i in order)
    print("stale not-found answers: %d (dungeon loot %d, gear %d, other %d); ~%d min at %.1f s each" % (
        len(order), buckets[0], buckets[1], buckets[2], len(order) * SPACING / 60, SPACING), flush=True)
    found = collections.Counter()
    for n, iid in enumerate(order, 1):
        d = fetch(iid, recheck=True)
        if d and "tooltip" in d:
            found[0 if iid in looted else 1 if iid in gear else 2] += 1
        if n % 50 == 0 or n == len(order):
            print("  %d/%d checked; now found: loot %d, gear %d, other %d" % (n, len(order), found[0], found[1], found[2]), flush=True)


def refresh_found(days=FOUND_DAYS, ids=None):
    """Ask Wowhead again about the items whose numbers come only from it (source "Server data via Wowhead's Forever
    database") when the cached answer is older than `days`. Fetch only; a normal run (--no-fetch) merges what comes back."""
    db = json.load(open(DB))
    wh = ids or [str(i["id"]) for i in db["items"] if "Wowhead's Forever database" in (i.get("source") or "")]
    old = []
    for iid in wh:
        path = os.path.join(CACHE, "%s.json" % iid)
        if os.path.exists(path) and (ids or time.time() - os.path.getmtime(path) > days * 86400):
            old.append(iid)
    print("Wowhead-only items: %d; asked again: %d (~%d min at %.1f s each)" % (len(wh), len(old), len(old) * SPACING / 60, SPACING), flush=True)
    changed = 0
    for n, iid in enumerate(old, 1):
        before = json.dumps(json.load(open(os.path.join(CACHE, "%s.json" % iid))), sort_keys=True)
        d = fetch(iid, force=True)
        if d is not None and json.dumps(d, sort_keys=True) != before:
            changed += 1
        if n % 50 == 0 or n == len(old):
            print("  %d/%d asked; changed %d" % (n, len(old), changed), flush=True)


def main():
    if "--recheck-missing" in sys.argv:
        recheck_missing()
        return
    if "--refresh-found" in sys.argv:
        ids = next((a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--ids=")), None)
        refresh_found(ids=ids)
        return
    dry, refresh_all, no_fetch = "--dry" in sys.argv, "--all" in sys.argv, "--no-fetch" in sys.argv
    os.makedirs(CACHE, exist_ok=True)
    db = json.load(open(DB))
    by = {str(i["id"]): i for i in db["items"]}
    loot = json.load(open(LOOT))
    site = json.load(open(SITE)) if os.path.exists(SITE) else {"fc": {}, "wtbc": {}}
    item = {r["ID"]: r for r in rows("Item")}
    sparse = {r["ID"] for r in rows("ItemSparse")}
    FC, fc_meta = fc_items("--refresh" in sys.argv)
    fc_live = {k: v for k, v in FC.items() if v.get("t") in ("new", "changed", "same")}
    # Tooltips players' games showed (ForeverProbe 0.4.7+, merged by tools/probe_pull.py): the game's own text, used
    # where ForeverChanges has no item or reads an older build than the game did
    disc = os.path.join(ROOT, "research", "questbank", "disc.json")
    tips = ((json.load(open(disc)).get("probe") or {}).get("tips") or {}) if os.path.exists(disc) else {}
    seen_game = {str(k): v for k, v in (((json.load(open(disc)).get("probe") or {}).get("items") or {}) if os.path.exists(disc) else {}).items()}
    try:
        fc_build = int(str(fc_meta.get("forever_build") or "0").split(".")[-1])
    except ValueError:
        fc_build = 0
    from_game = 0
    for k, g in tips.items():
        if k in fc_live and int(g.get("b") or 0) <= fc_build:
            continue
        game = {"n": g["n"], "q": g.get("q") if g.get("q") is not None else 1, "l": g.get("l"), "r": g.get("r"), "c": g.get("c"),
                "u": g.get("u"), "x": g.get("x") or [], "src": "game", "b": g.get("b"), "el": g.get("el")}
        base = FC.get(k) if FC.get(k, {}).get("t") in ("new", "changed", "same") else None
        if base:
            # the game's newer text over ForeverChanges' record: its verdict (new/changed), set, classes and icon stay
            rec = dict(base)
            rec.update(game)
            rec["fcx"] = base.get("x") or []
        else:
            rec = dict(game, i=int(k), t="new" if int(k) >= 239000 else "seen")
            if g.get("e"):
                rec["e"] = g["e"]
        fc_live[k] = rec
        from_game += 1
    if tips:
        print("players' games: %d item tooltips, %d used (not in ForeverChanges, or a newer build)" % (len(tips), from_game))
    # Classic items ForeverChanges finds nowhere in Forever's data (its 'missing' file), with no client ItemSparse row.
    # What happens to each depends on what else knows it (main loop): a Wowhead Forever tooltip makes a normal row;
    # else a client Item row (Forever has the item, its numbers come from the server) makes a Classic estimate;
    # else it is gone from Forever's data.
    fc_missing = {k for k, v in FC.items() if v.get("t") == "missing" and k not in sparse and k not in fc_live}
    sets = collections.defaultdict(list)
    for v in fc_live.values():
        if v.get("e"): sets[v["e"]].append(html.unescape(v["n"]))
    print("ForeverChanges: %d live items, build %s (%s)" % (len(fc_live), fc_meta.get("forever_build"), fc_meta.get("forever_build_date")))

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
    # rows Wowhead filled before are read again every run, so parser fixes reach them
    want = looted | missing | set(fc_live) | {i for i, it in by.items() if it.get("wh") or it.get("est")}
    if refresh_all:
        want |= {i for i, it in by.items() if it.get("cat") in ("weapon", "armor", "accessory", "offhand", "consumable")
                 or "..." in " ".join(it.get("effects") or [])}
    todo = sorted((i for i in want if (i not in fc_live or (fc_live[i].get("src") == "game" and not fc_live[i].get("k")))
                   and not os.path.exists(os.path.join(CACHE, i + ".json"))), key=int)
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
    if no_fetch:
        print("--no-fetch: %d left unfetched; merging from the caches only" % len(todo))
        todo = []
    for i in todo:  # one at a time, SPACING apart (fetch waits)
        job(i)

    # classify new rows the way the database already classifies their client class
    vote3, vote2 = collections.defaultdict(collections.Counter), collections.defaultdict(collections.Counter)
    for iid, it in by.items():
        ir = item.get(iid)
        if ir:
            vote3[(ir["ClassID"], ir["SubclassID"], ir["InventoryType"])][(it["cat"], it["sub"], it.get("type"))] += 1
            vote2[(ir["ClassID"], ir["SubclassID"])][(it["cat"], it["sub"], it.get("type"))] += 1

    added, refreshed, from_fc, junk, unknown, absent, dropped = [], 0, 0, 0, 0, {}, set()
    rescued, estimates = [], []
    for iid in sorted(want, key=int):
        wh = cached(iid)
        ok = bool(wh and "tooltip" in wh)
        p = parse(wh["tooltip"]) if ok else None
        fc = fc_live.get(iid)
        old = by.get(iid)
        est = None
        if iid in fc_missing:
            if ok:
                rescued.append(iid)  # Wowhead has Forever's tooltip: a normal row below
            elif iid in item:
                est = FC[iid]  # Forever has the item but nobody has shown its numbers: Classic's, as an estimate
            else:
                if old is not None: dropped.add(iid)
                if iid in looted: absent[iid] = html.unescape(FC[iid]["n"])
                continue
        if old is not None and old.get("est") and (ok or fc) and not est:
            old.pop("est", None)  # a real tooltip replaces the estimate, Classic leftovers and all
            if old.get("ft") == "missing": old.pop("ft", None)
            for k in ("stats", "effects", "dmgExtra", "flavor", "setName", "setBonuses", "setPieces", "startsQuest", "reqLevel",
                      "binding", "armor", "block", "damage", "speed", "dps", "unique", "cls", "reqSkill"):
                old.pop(k, None)
        is_new = old is None
        if iid in looted and not ok and not fc and not est and iid not in sparse and is_new:
            fcn = (site["fc"].get(iid) or {}).get("n") or (site["wtbc"].get(iid) or {}).get("name") or ""
            absent[iid] = html.unescape(fcn)
            continue
        if is_new:
            name = (fc or est or {}).get("n") or (wh["name"] if ok else (site["fc"].get(iid) or {}).get("n") or (site["wtbc"].get(iid) or {}).get("name"))
            if not name:
                unknown += 1
                continue
            if JUNK.search(name) and iid not in looted:
                junk += 1
                continue
            ir = item.get(iid, {})
            if not ir and fc and fc.get("src") == "game" and fc.get("c") is not None:
                ir = {"ClassID": str(fc["c"]), "SubclassID": str(fc.get("u") or 0), "InventoryType": INVTYPE.get(fc.get("el") or "", "0")}
            key3 = (ir.get("ClassID"), ir.get("SubclassID"), ir.get("InventoryType"))
            cat, sub, typ = (vote3.get(key3) or vote2.get(key3[:2]) or collections.Counter({("misc", "Other", None): 1})).most_common(1)[0][0]
            qn = fc["q"] if fc else wh.get("quality") if ok else est["q"] if est else (site["fc"].get(iid) or {}).get("q", 1)
            qn = 1 if qn is None else qn
            old = {"id": iid, "name": html.unescape(name), "quality": QUAL[int(qn)],
                   "slot": SLOT.get(ir.get("InventoryType", ""), "unknown"), "cat": cat, "sub": sub,
                   "icon": (wh.get("icon") if ok else (est or site["fc"].get(iid) or {}).get("k")) or "inv_misc_questionmark"}
            if typ: old["type"] = typ
            if int(iid) >= 239000: old["nw"] = 1
            elif 199000 <= int(iid) < 239000: old["era"] = "sod"
            old["source"] = "Loot record (foreverchanges.pro / wowtbc.gg)"
            added.append(old)
        if fc:
            # ForeverChanges' tooltip is the current build's, in Forever's own wording: it replaces
            # every tooltip field, and what it does not show goes.
            p2 = fc_parse(fc, sets)
            if fc.get("fcx"):
                p_fc = fc_parse(dict(fc, x=fc["fcx"]), sets)
                for k in ("setName", "setPieces", "setBonuses", "cls"):
                    if p2.get(k) is None and p_fc.get(k) is not None:
                        p2[k] = p_fc[k]
            for k in ("itemLevel", "reqLevel", "binding", "damage", "speed", "dps", "dmgExtra", "armor", "block", "unique", "flavor", "cls",
                      "reqSkill", "startsQuest", "setName", "setPieces", "setBonuses"):
                if p2.get(k) is not None: old[k] = p2[k]
                elif k not in ("itemLevel", "cls"): old.pop(k, None)
            old["stats"] = p2["stats"] or None
            old["effects"] = p2["effects"] or None
            old["name"] = html.unescape(fc["n"])
            old["quality"] = QUAL[int(fc["q"] if fc.get("q") is not None else 1)]
            if fc.get("k"): old["icon"] = fc["k"]
            old["tt"] = "forever"
            old["ft"] = fc["t"]
            old.pop("wh", None)
            old.pop("rand", None)
            old["source"] = ("Beta build 1.60.1.%s, as players' games showed it (ForeverProbe)" % fc.get("b")) if fc.get("src") == "game" \
                else "Beta build %s, via foreverchanges.pro" % fc_meta.get("forever_build", BUILD)
            from_fc += 1
        elif ok:
            # Wowhead: complete, but behind on changed items; used where ForeverChanges has nothing.
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
            old["quality"] = QUAL[int(wh["quality"] if wh.get("quality") is not None else 1)]
            if wh.get("icon"): old["icon"] = wh["icon"]
            old["wh"] = 1
            if iid not in sparse: old["source"] = "Server data via Wowhead's Forever database"
            if not is_new: refreshed += 1
        elif est:
            # ForeverChanges' Classic tooltip of an item Forever has: every number is Classic's until a real tooltip comes
            p2 = fc_parse(est, sets)
            for k in ("itemLevel", "reqLevel", "binding", "damage", "speed", "dps", "dmgExtra", "armor", "block", "unique", "flavor", "cls",
                      "reqSkill", "startsQuest", "setName", "setBonuses"):
                if p2.get(k) is not None: old[k] = p2[k]
                elif k not in ("itemLevel", "cls"): old.pop(k, None)
            old["stats"] = p2["stats"] or None
            old["effects"] = p2["effects"] or None
            old["name"] = html.unescape(est["n"])
            old["quality"] = QUAL[int(est["q"] if est.get("q") is not None else 1)]
            if est.get("k"): old["icon"] = est["k"]
            old.pop("tt", None)
            old.pop("wh", None)
            old["ft"] = "missing"
            old["est"] = "classic"
            old["source"] = ("Estimate: a WoW Classic item nobody has seen in Forever yet (Forever's data keeps its id, which does not prove "
                             "it drops); these are its Classic numbers, from foreverchanges.pro (build %s). Forever may have changed or removed it"
                             % fc_meta.get("forever_build", BUILD))
            estimates.append(iid)
        for k in ("stats", "effects"):
            if not old.get(k): old.pop(k, None)
        # Classic's suffix greens and blues ("of the Eagle"): the base item carries no stats
        if (ok or fc or est) and int(iid) < 100000 and old.get("slot") not in (None, "unknown") and old["quality"] in ("uncommon", "rare") \
                and not old.get("stats") and not old.get("effects"):
            old["rand"] = 1
        elif old.get("rand") and (old.get("stats") or old.get("effects")):
            old.pop("rand")
        if drops.get(iid): old["drops"] = drops[iid]
        if quests.get(iid): old["quests"] = quests[iid]
    # loot links for items that never needed a refetch
    for iid, it in by.items():
        if iid in dropped: continue
        if drops.get(iid): it["drops"] = drops[iid]
        if quests.get(iid): it["quests"] = quests[iid]
        # a recorded Forever drop is wired loot, whatever ID band it sits in
        if iid in looted and it.get("era") in ("sod", "retail"):
            it.pop("era", None)
            it["eraNote"] = "Recorded as Forever loot"
        # Items players' games had (ForeverProbe snapshots of bags and gear, merged by tools/probe_pull.py): sg is how
        # many uploads showed it. Seen in Forever settles a leftover-era tag the same way a loot record does.
        n = seen_game.get(iid)
        if n:
            it["sg"] = n
            if it.get("era") in ("sod", "retail"):
                it.pop("era", None)
                it["eraNote"] = "Seen in players' games in Forever"
                if "treat as leftover" in (it.get("source") or ""):
                    it["source"] = it["source"].split(";")[0] + "; players' games in Forever have shown it"
        else:
            it.pop("sg", None)

    # Stat lines only the tooltip text carried (datamine rows keep the text but had no stat for these)
    filled = collections.Counter()
    for it in list(by.values()) + added:
        if str(it["id"]) in dropped or it.get("slot") in (None, "unknown"):
            continue
        st = {}
        for line in it.get("effects") or []:
            if line.startswith("Equip:"):
                equip_stats(line, st)
        for k in ("spellPiercing", "blockValue"):
            if st.get(k) and not (it.get("stats") or {}).get(k):
                it.setdefault("stats", {})[k] = st[k]
                filled[k] += 1
    have = (set(by) - dropped) | {e["id"] for e in added}
    looted_rescued = [i for i in rescued if i in looted]
    print("Wowhead tooltips for items ForeverChanges marks missing: %d (dungeon/quest loot %d)" % (len(rescued), len(looted_rescued)))
    print("Classic estimates (client Item row, no Forever tooltip anywhere): %d (dungeon/quest loot %d)" % (
        len(estimates), sum(1 for i in estimates if i in looted)))
    print("stats filled from tooltip text: %s" % dict(filled))
    print("dropped %d Classic items ForeverChanges finds nowhere in Forever" % len(dropped))
    print("added %d; tooltips from ForeverChanges %d, from Wowhead %d; junk skipped %d, unknown (no name anywhere) %d" % (len(added), from_fc, refreshed, junk, unknown))
    print("loot items covered %d/%d; %d are Classic loot absent from Forever's data" % (len(looted & have), len(looted), len(absent)))
    print("new by cat", collections.Counter(e["cat"] for e in added).most_common())
    if dry:
        print("(dry run)")
        return
    db["items"] = [i for i in db["items"] if str(i["id"]) not in dropped] + added
    db["items"].sort(key=lambda i: int(i["id"]))
    # damage reflected at attackers (thorns, shield spikes, procs when struck), from the client's spell tables
    import apply_reflect
    apply_reflect.run(db)
    # procs, on-use and chance-on-hit effects (fx), from the same tables; after rf, which it leaves alone
    import apply_effects
    apply_effects.run(db)
    db["note"] = re.sub(r"\s*Server-sent items.*$", "", db["note"]) + (
        " Server-sent items and current tooltips: ForeverChanges' item files for the current build first (Forever's own wording), "
        "Wowhead's Forever database where they have nothing, the client datamine last; who drops what comes from codex/loot.json "
        "(tools/scavenge_items.py). Rows with est:\"classic\" are items Forever has (the client's item table lists them) whose "
        "Forever numbers no source has shown yet: their stats are Classic's, an estimate. rf lists damage done back to "
        "attackers (tools/apply_reflect.py); fx lists procs, on-use and chance-on-hit effects (tools/apply_effects.py).")
    db["scavenged"] = time.strftime("%Y-%m-%d")
    with open(DB, "w") as f:
        json.dump(db, f, ensure_ascii=False, separators=(",", ":"))
    print("wrote %s: %d items" % (os.path.relpath(DB, ROOT), len(db["items"])))
    loot["absent"] = {k: absent[k] for k in sorted(absent, key=int)}
    loot["note"] = re.sub(r"\s*Items under absent.*$", "", loot["note"]) + (
        " Items under absent are in a site's loot table (usually Classic's) but no source shows them in Forever yet: "
        "ForeverChanges finds them nowhere in Forever's data, Wowhead's Forever database and players' games have not shown "
        "them, and the client has no item row for them. Mostly loot above the beta's level cap that nobody has looted yet. "
        "Items the client does list but nobody has shown are in the item database as Classic estimates instead.")
    with open(LOOT, "w") as f:
        json.dump(loot, f, ensure_ascii=False, separators=(",", ":"))
    # The World page's loot tables load only the items a dungeon or quest names.
    keep = [i for i in db["items"] if str(i["id"]) in looted]
    with open(os.path.join(ROOT, "codex", "loot-items.json"), "w") as f:
        json.dump({"note": "Items named by codex/loot.json, in the database's own format.", "items": keep}, f, ensure_ascii=False, separators=(",", ":"))
    print("wrote codex/loot-items.json: %d items" % len(keep))


if __name__ == "__main__":
    main()
