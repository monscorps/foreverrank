import json, os
HERE = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'research', 'questbank')
AREAS = {int(k): v for k, v in json.load(open(os.path.join(HERE, 'areas.json'))).items()}
LOC = json.load(open(os.path.join(HERE, 'npcloc.json')))
ZONE_STOP = {1537: 'IF', 1: 'DM', 1519: 'SW', 40: 'WF', 44: 'RR', 10: 'DW', 38: 'LM', 11: 'WL', 148: 'AUB',
             1657: 'DARN', 141: 'DARN', 17: 'BAR', 331: 'ASH', 406: 'STM', 12: 'EL', 267: 'HB', 33: 'STV', 15: 'DUST'}
def npc(i):
    return LOC.get('npc/%s' % i) or {}
def stop_of(end_id):
    n = npc(end_id)
    z = n.get('zone')
    s = ZONE_STOP.get(z, AREAS.get(z, str(z)))
    c = (n.get('coords') or [[None, None]])[0]
    if s == 'BAR' and c and c[0] is not None:
        s = 'RATCHET' if c[0] > 55 else ('WCMOUND' if 40 < c[0] < 52 and 28 < c[1] < 42 else 'BAR')
    if s == 'DM' and c and c[0] is not None:
        s = 'KHARANOS' if 44 < c[0] < 52 and 45 < c[1] < 56 else 'DM'
    return s, n.get('name'), c
