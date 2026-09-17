#!/usr/bin/env python3
"""Stitch Blizzard's painted zone maps from wow.export worldmap tiles.

Usage: python3 tools/build_maps.py <export folder with UiMap*.csv> <tiles root (interface/worldmap)>
Writes map/img/painted-<UiMapID>.jpg for every map whose wired art tiles are
all present, and prints the ones still missing tiles. Uses the community
listfile slice for FDID naming (tools/icon-listfile.csv covers icons only,
so this reads the full listfile if present at ~/Downloads/community-listfile.csv).
"""
import csv, os, sys, collections

EXP = sys.argv[1].rstrip("/") + "/"
TILES = sys.argv[2].rstrip("/") + "/"
LISTFILE = os.path.expanduser("~/Downloads/community-listfile.csv")

from PIL import Image

def load(f):
    with open(EXP + f, encoding="utf-8-sig", errors="replace") as fh:
        return list(csv.DictReader(fh, delimiter=";"))

names = {}
if os.path.exists(LISTFILE):
    for line in open(LISTFILE):
        if "interface/worldmap/" in line:
            i = line.find(";")
            names[line[:i]] = line[i+1:].strip()

uimap = {r["ID"]: r["Name_lang"] for r in load("UiMap.csv")}
xart = {r["UiMapID"]: r["UiMapArtID"] for r in load("UiMapXMapArt.csv")}
tiles = collections.defaultdict(list)
for t in load("UiMapArtTile.csv"):
    if t["LayerIndex"] == "0":
        tiles[t["UiMapArtID"]].append(t)

os.makedirs("map/img", exist_ok=True)
done, missing = 0, []
for mid, art in xart.items():
    ts = tiles.get(art, [])
    if not ts: continue
    paths = {}
    ok = True
    for t in ts:
        p = names.get(t["FileDataID"])
        local = None
        if p:
            rel = p.split("interface/worldmap/")[-1].replace(".blp", ".png")
            cand = TILES + rel
            if os.path.exists(cand): local = cand
        if not local:
            cand = TILES + "unknown/" + t["FileDataID"] + ".png"
            if os.path.exists(cand): local = cand
        if not local: ok = False; break
        paths[(int(t["RowIndex"]), int(t["ColIndex"]))] = local
    if not ok:
        missing.append(uimap.get(mid, mid)); continue
    rows = max(r for r, c in paths) + 1
    cols = max(c for r, c in paths) + 1
    t0 = Image.open(paths[(0, 0)])
    tw, th = t0.size
    canvas = Image.new("RGB", (tw * cols, th * rows))
    for (r, c), p in paths.items():
        canvas.paste(Image.open(p).convert("RGB"), (c * tw, r * th))
    # Logical WoW map canvas is 1002x668 inside the padded tile grid.
    canvas = canvas.crop((0, 0, int(tw * cols * 1002 / (256 * 4)), int(th * rows * 668 / (256 * 3))))
    out = "map/img/painted-" + mid + ".jpg"
    canvas.save(out, quality=82)
    done += 1
    print("stitched", out, uimap.get(mid, ""))
print("---")
print("stitched:", done, "| missing tiles for:", len(missing))
for n in missing: print("  needs tiles:", n)
