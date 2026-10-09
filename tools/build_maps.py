#!/usr/bin/env python3
"""Stitch Blizzard's painted maps for the Atlas.

  python3 tools/build_maps.py --wago [BUILD]
      Forever's own world and continent art (world_c60, easternkingdoms_c60,
      kalimdor_c60) straight from wago.tools, which serves any client file by
      FileDataID as BLP (Pillow reads it). Writes map/img/world.jpg and
      map/img/cont-ek.jpg / cont-kal.jpg, the continents cut to the windows in
      tools/build_atlas.py (CROP) so its overlays and map.js hotspots line up.
      Tiles are cached in research/wago/<BUILD>/tiles/.

  python3 tools/build_maps.py <export folder with UiMap*.csv> <tiles root (interface/worldmap)>
      The old wow.export path: writes map/img/painted-<UiMapID>.jpg for every map
      whose wired art tiles are all present, and prints the ones still missing
      tiles. Uses the community listfile slice for FDID naming (tools/icon-listfile.csv
      covers icons only, so this reads the full listfile if present at
      ~/Downloads/community-listfile.csv).
"""
import csv, os, sys, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def wago(build):
    """World and continent art from wago.tools, continents cut to build_atlas.CROP."""
    import time, urllib.request
    from PIL import Image
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    from fetch_wago import UA, fetch
    from build_atlas import CROP

    def rows(table):
        path, note = fetch(build, table)
        if not path:
            sys.exit("%s: %s" % (table, note))
        with open(path, encoding="utf-8-sig") as fh:
            return list(csv.DictReader(fh))

    art = {r["UiMapID"]: r["UiMapArtID"] for r in rows("UiMapXMapArt")}
    tiles = collections.defaultdict(list)
    for t in rows("UiMapArtTile"):
        if t["LayerIndex"] == "0":
            tiles[t["UiMapArtID"]].append(t)
    cache = os.path.join(ROOT, "research", "wago", build, "tiles")
    os.makedirs(cache, exist_ok=True)

    def stitch(uimap):
        canvas = Image.new("RGB", (1024, 768))
        for t in tiles[art[uimap]]:
            path = os.path.join(cache, t["FileDataID"] + ".blp")
            if not os.path.exists(path):
                url = "https://wago.tools/api/casc/%s?version=%s&download" % (t["FileDataID"], build)
                body = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
                if body[:4] != b"BLP2":
                    sys.exit("tile %s: not a BLP file" % t["FileDataID"])
                open(path, "wb").write(body)
                time.sleep(0.4)
            canvas.paste(Image.open(path).convert("RGB"), (int(t["ColIndex"]) * 256, int(t["RowIndex"]) * 256))
        # the logical WoW map canvas is 1002x668 inside the 4x3 tile grid
        return canvas.crop((0, 0, 1002, 668))

    out = os.path.join(ROOT, "map", "img")
    stitch("947").save(os.path.join(out, "world.jpg"), quality=84)
    print("wrote map/img/world.jpg")
    for key, uimap in (("ek", "1415"), ("kal", "1414")):
        u0, u1, v0, v1 = CROP[key]
        box = (u0 * 1002, v0 * 668, u1 * 1002, v1 * 668)
        # sub-pixel cut, at twice the art's own size so it stays smooth on big and dense screens
        size = (round((box[2] - box[0]) * 2), round((box[3] - box[1]) * 2))
        im = stitch(uimap).transform(size, Image.EXTENT, box, Image.BICUBIC)
        im.save(os.path.join(out, "cont-%s.jpg" % key), quality=84)
        print("wrote map/img/cont-%s.jpg" % key, im.size)


def export(exp_dir, tiles_dir):
    EXP = exp_dir.rstrip("/") + "/"
    TILES = tiles_dir.rstrip("/") + "/"
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


if __name__ == "__main__":
    if sys.argv[1:2] == ["--wago"]:
        wago(sys.argv[2] if len(sys.argv) > 2 else sorted(
            (b for b in os.listdir(os.path.join(ROOT, "research", "wago")) if b.startswith("1.60.")),
            key=lambda b: [int(x) for x in b.split(".")])[-1])
    elif len(sys.argv) == 3:
        export(sys.argv[1], sys.argv[2])
    else:
        sys.exit(__doc__)
