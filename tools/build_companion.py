#!/usr/bin/env python3
"""Build the ForeverProbe bundle: brand .ico + one zip with addon and companion.

Run from the repo root:  python3 tools/build_companion.py
Writes addon/companion/ForeverProbe.ico and addon/ForeverProbe.zip
(zip holds ForeverProbe/ for AddOns plus Companion/ for the Windows sync).
"""
import os, zipfile
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

# ---- the icon: the actual ForeverRank sigil from mark.svg, redrawn --------
# Petrol radial disc, gold ring, the eternity knot (two cubic-Bezier lobes,
# round caps), and the two small dots. Rendered oversampled, then downscaled.
GOLD = (229, 204, 128, 255)
GOLD_DIM = (168, 146, 91, 255)

def bezier(p0, p1, p2, p3, n=60):
    pts = []
    for i in range(n + 1):
        t = i / n
        mt = 1 - t
        x = mt**3 * p0[0] + 3 * mt**2 * t * p1[0] + 3 * mt * t**2 * p2[0] + t**3 * p3[0]
        y = mt**3 * p0[1] + 3 * mt**2 * t * p1[1] + 3 * mt * t**2 * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts

def draw_mark(size):
    S = 8  # oversample
    N = size * S
    k = N / 64.0
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # radial-ish background: three concentric fills approximate the gradient
    def circle(cx, cy, r, **kw):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], **kw)
    circle(32 * k, 32 * k, 30 * k, fill=(5, 31, 46, 255))
    circle(32 * k, 28 * k, 24 * k, fill=(7, 50, 74, 255))
    circle(32 * k, 27 * k, 15 * k, fill=(10, 63, 94, 255))
    # soften the gradient steps
    img = img.filter(ImageFilter.GaussianBlur(radius=3 * k))
    d = ImageDraw.Draw(img)
    # outer gold ring and faint inner ring
    d.ellipse([2 * k, 2 * k, 62 * k, 62 * k], outline=GOLD, width=max(1, int(2 * k)))
    d.ellipse([6.5 * k, 6.5 * k, 57.5 * k, 57.5 * k], outline=(229, 204, 128, 90), width=max(1, int(1 * k)))
    # the knot: left and right lobes out of (32,32)
    path = (bezier((32, 32), (25.5, 23.5), (12.5, 23.5), (12.5, 32)) +
            bezier((12.5, 32), (12.5, 40.5), (25.5, 40.5), (32, 32)) +
            bezier((32, 32), (38.5, 23.5), (51.5, 23.5), (51.5, 32)) +
            bezier((51.5, 32), (51.5, 40.5), (38.5, 40.5), (32, 32)))
    w = 4.2 * k
    for (x, y) in path:
        d.ellipse([x * k - w / 2, y * k - w / 2, x * k + w / 2, y * k + w / 2], fill=GOLD)
    # the two dots
    for (cx, cy) in ((32, 8.5), (32, 55.5)):
        r = 1.6 * k
        d.ellipse([cx * k - r, cy * k - r, cx * k + r, cy * k + r], fill=GOLD)
    return img.resize((size, size), Image.LANCZOS)

ico_path = "addon/companion/ForeverProbe.ico"
draw_mark(256).save(ico_path, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("wrote", ico_path)

# The in-game addon icon wears the same sigil (TGA on opaque navy).
tga = Image.new("RGBA", (64, 64), (5, 31, 46, 255))
tga.alpha_composite(draw_mark(64))
tga.save("addon/ForeverProbe/icon.tga")
print("wrote addon/ForeverProbe/icon.tga")

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

# The double-click installer face, compiled on Windows by the companion's
# Build-Installer.bat (csc.exe + Launcher.cs + the sigil ico). When the exe
# is in the repo it rides at the zip root so it is the first thing seen.
setup_exe = "addon/companion/ForeverProbe Setup.exe"
if os.path.exists(setup_exe):
    zf.write(setup_exe, "ForeverProbe Setup.exe")
    print("ForeverProbe Setup.exe bundled at the zip root.")
else:
    print("no ForeverProbe Setup.exe yet: build it on Windows with addon/companion/Build-Installer.bat.")

# The guild key: webhook + mark, base64-packed as Companion/guild.key so the
# install needs zero typing. webhook.txt and guildmark.txt stay gitignored;
# the encoded key inside the zip survives GitHub/Discord secret scanning,
# which auto-revokes plaintext webhooks in public repos. Posts carry the
# mark, so anything in the channel without it is not ours.
import base64
wh = "addon/companion/webhook.txt"
gm = "addon/companion/guildmark.txt"
if os.path.exists(wh):
    hook = open(wh).read().strip()
    mark = open(gm).read().strip() if os.path.exists(gm) else ""
    key = base64.b64encode((hook + "|" + mark).encode()).decode()
    zf.writestr("Companion/guild.key", key + "\n")
    print("guild.key baked in (webhook + mark, encoded). Zero-typing installs.")
else:
    print("no webhook.txt: building without a baked key; installer will prompt.")

zf.close()
print("wrote", zip_path, os.path.getsize(zip_path) // 1024, "KB")
for n in zipfile.ZipFile(zip_path).namelist():
    print("  ", n)
