#!/usr/bin/env python3
"""Build the ForeverProbe bundle: brand .ico + one zip with addon and companion.

Run from the repo root:  python3 tools/build_companion.py
Writes addon/companion/ForeverProbe.ico and addon/ForeverProbe.zip
(zip holds ForeverProbe/ for AddOns plus Companion/ for the Windows sync).
"""
import os, zipfile
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

# ---- the icon: gold infinity on the site's dark navy, multi-size ----------
def draw_mark(size):
    img = Image.new("RGBA", (size, size), (13, 22, 38, 255))
    d = ImageDraw.Draw(img)
    r = max(2, size // 6)
    w = max(1, size // 28)
    d.rounded_rectangle([w, w, size - 1 - w, size - 1 - w], radius=r,
                        outline=(229, 204, 128, 255), width=w)
    font = None
    for p in ("/System/Library/Fonts/Helvetica.ttc",
              "/System/Library/Fonts/HelveticaNeue.ttc",
              "/Library/Fonts/Arial Unicode.ttf",
              "C:/Windows/Fonts/arial.ttf"):
        try:
            font = ImageFont.truetype(p, int(size * 0.72))
            break
        except Exception:
            pass
    t = "\u221e"
    bb = d.textbbox((0, 0), t, font=font)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    d.text(((size - tw) / 2 - bb[0], (size - th) / 2 - bb[1]), t,
           font=font, fill=(229, 204, 128, 255))
    return img

ico_path = "addon/companion/ForeverProbe.ico"
draw_mark(256).save(ico_path, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("wrote", ico_path)

# ---- the bundle -----------------------------------------------------------
zip_path = "addon/ForeverProbe.zip"
if os.path.exists(zip_path):
    os.remove(zip_path)
zf = zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED)

for base, _, files in os.walk("addon/ForeverProbe"):
    for f in sorted(files):
        if f == ".DS_Store":
            continue
        full = os.path.join(base, f)
        arc = os.path.relpath(full, "addon")
        zf.write(full, arc)

for f in ("ForeverProbe-Sync.ps1", "Install.bat", "Uninstall.bat", "README.txt", "ForeverProbe.ico"):
    zf.write(os.path.join("addon/companion", f), "Companion/" + f)

zf.close()
print("wrote", zip_path, os.path.getsize(zip_path) // 1024, "KB")
for n in zipfile.ZipFile(zip_path).namelist():
    print("  ", n)
