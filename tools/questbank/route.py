"""Simulate a turn-in route: stops in order, quests at each stop handed in lowest level first."""
from xpmodel import Char, xp_at, full_xp, TO_NEXT


def simulate(stops, quests, bonus=0.0, start_level=20, start_xp=0):
    """stops: list of (stop_name, minutes_to_reach_and_work).
    quests: list of dicts with id, name, level, base, mult, stop, kind.
    bonus: e.g. 0.03 for the Cozy Sleeping Bag's Well Rested buff (applied per turn-in)."""
    c = Char(start_level, start_xp)
    t = 0.0
    log = []
    by_stop = {}
    for q in quests:
        by_stop.setdefault(q["stop"], []).append(q)
    seen = set()
    for stop, minutes in stops:
        t += minutes
        for q in sorted(by_stop.get(stop, []), key=lambda q: (q["level"], -full_xp(q["base"], q["mult"]))):
            if q["id"] in seen:
                continue
            seen.add(q["id"])
            x = xp_at(q["base"], q["mult"], q["level"], c.level)
            x = int(round(x * (1 + bonus)))
            before = c.level
            c.gain(x)
            log.append(dict(stop=stop, t=round(t, 1), id=q["id"], name=q["name"], qlevel=q["level"], xp=x,
                            full=full_xp(q["base"], q["mult"]), plevel=before, after=round(c.frac, 2), kind=q.get("kind", "")))
    missed = [q for q in quests if q["id"] not in seen]
    return c, t, log, missed


def total_to(level, frm=20):
    return sum(TO_NEXT[l - 1] for l in range(frm, level))
