"""Forever quest XP model: Wowhead's Forever formula (base x multiplier, classic grey
penalty, rounding to 10/50) on the Classic 1.12 level curve (Forever GameTables)."""
import json, math, os

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(os.path.dirname(os.path.dirname(HERE)), "research", "questbank")
TO_NEXT = [400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000,
           17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
           50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700]  # index = level-1


def jsround(x):
    return math.floor(x + 0.5)


def round_quest_xp(e):
    t = 10 if e < 1000 else 50
    return jsround(e / t) * t


def full_xp(base, mult):
    return round_quest_xp(jsround((base or 0) * (mult if mult is not None else 1)))


def xp_at(base, mult, qlevel, plevel):
    f = jsround((base or 0) * (mult if mult is not None else 1))
    m = plevel - qlevel
    if m >= 10:
        f *= 0.1
    elif m >= 6:
        f *= 1 - (m - 5) * 0.2
    return round_quest_xp(f)


class Char:
    def __init__(self, level=20, xp=0, cap=30):
        self.level, self.xp, self.cap = level, xp, cap

    def gain(self, amount):
        self.xp += amount
        while self.level < self.cap and self.xp >= TO_NEXT[self.level - 1]:
            self.xp -= TO_NEXT[self.level - 1]
            self.level += 1

    @property
    def frac(self):
        if self.level >= self.cap:
            return float(self.cap)
        return self.level + self.xp / TO_NEXT[self.level - 1]


def load():
    base = json.load(open(os.path.join(RAW, "wowhead.json")))
    extra = json.load(open(os.path.join(RAW, "extra.json")))
    det = {}
    for name in ("det2_partial.json", "det2.json"):
        p = os.path.join(RAW, name)
        if os.path.exists(p):
            det.update({int(k): v for k, v in json.load(open(p)).items() if v.get("status") == 200})
    for k, v in base["details"].items():
        det.setdefault(int(k), v)
    quests = {}
    for q in base["cand"] + extra["lo"] + extra["hi"]:
        quests[q["id"]] = dict(q)
    for qid, d in det.items():
        if qid in quests:
            quests[qid]["det"] = d
    return quests
