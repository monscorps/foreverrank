# the logo's grey background (31,31,31) keyed out: pixels joined to the border through near-background colours become
# transparent, the anti-aliased rim keeps a soft alpha with its colour un-mixed from the grey
import site, sys
sys.path.append(site.getusersitepackages())
from PIL import Image
from collections import deque
src, out_wide, out_emblem = sys.argv[1], sys.argv[2], sys.argv[3]
im = Image.open(src).convert("RGB")
w, h = im.size
px = im.load()
bg = (31, 31, 31)
T0, T1 = 7, 46
def d(c): return max(abs(c[0] - bg[0]), abs(c[1] - bg[1]), abs(c[2] - bg[2]))
alpha = [[255] * w for _ in range(h)]
seen = [[False] * w for _ in range(h)]
q = deque()
for x in range(w):
    for y in (0, h - 1): q.append((x, y))
for y in range(h):
    for x in (0, w - 1): q.append((x, y))
while q:
    x, y = q.popleft()
    if seen[y][x]: continue
    seen[y][x] = True
    dist = d(px[x, y])
    if dist >= T1: continue
    alpha[y][x] = 0 if dist <= T0 else int(255 * (dist - T0) / (T1 - T0))
    for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
        if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx]: q.append((nx, ny))
rgba = Image.new("RGBA", (w, h))
op = rgba.load()
for y in range(h):
    for x in range(w):
        a = alpha[y][x]
        r, g, b = px[x, y]
        if 0 < a < 255:
            f = a / 255.0
            r = max(0, min(255, int((r - bg[0] * (1 - f)) / f)))
            g = max(0, min(255, int((g - bg[1] * (1 - f)) / f)))
            b = max(0, min(255, int((b - bg[2] * (1 - f)) / f)))
        op[x, y] = (r, g, b, a)
bbox = rgba.getbbox()
logo = rgba.crop(bbox)
# the wide texture: 512x256, the logo fitted with a small margin, centred
W, H = 512, 256
scale = min((W - 8) / logo.width, (H - 8) / logo.height)
fit = logo.resize((int(logo.width * scale), int(logo.height * scale)), Image.LANCZOS)
canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
canvas.paste(fit, ((W - fit.width) // 2, (H - fit.height) // 2), fit)
canvas.save(out_wide)
# the emblem for the minimap: the round badge above the word, square, 256x256 (the button masks it round)
em = rgba.crop((225, 15, 525, 315)).resize((256, 256), Image.LANCZOS)
em.save(out_emblem)
print("bbox", bbox, "wide fit", fit.size)
