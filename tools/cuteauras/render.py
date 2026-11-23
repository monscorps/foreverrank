#!/usr/bin/env python3
"""Render Cute Auras' picture for Cute's page: tools/cuteauras/mock.html -> addons/cute/img/auras.webp.

  python3 -I tools/cuteauras/render.py [out.png]

Headless Chrome screenshots the mock at the game's sizes (980 x 470, the icons from Wowhead's image CDN, as the site's),
then a second headless page draws that PNG on a canvas and hands back WebP (the Mac has no cwebp). With an argument the
PNG is kept there too, to look at. Python 3 standard library only."""
import base64, os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
MOCK = os.path.join(HERE, "mock.html")
OUT = os.path.join(ROOT, "addons", "cute", "img", "auras.webp")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 980, 470


def chrome(*args):
    return subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run", "--no-default-browser-check"] + list(args),
                          capture_output=True, text=True, timeout=120)


def main():
    if not os.path.exists(CHROME):
        sys.exit("no Google Chrome at " + CHROME)
    tmp = tempfile.mkdtemp(prefix="cuteauras-render-")
    png = os.path.join(tmp, "auras.png")
    r = chrome("--window-size=%d,%d" % (W, H), "--virtual-time-budget=8000", "--screenshot=" + png, "file://" + MOCK)
    if not os.path.exists(png):
        sys.exit("no screenshot:\n" + r.stderr[-2000:])
    if len(sys.argv) > 1:
        open(sys.argv[1], "wb").write(open(png, "rb").read())
    data = base64.b64encode(open(png, "rb").read()).decode("ascii")
    conv = os.path.join(tmp, "conv.html")
    open(conv, "w").write("""<!doctype html><body><script>
      const img = new Image();
      img.onload = () => { const c = document.createElement('canvas'); c.width = img.width; c.height = img.height;
        c.getContext('2d').drawImage(img, 0, 0); const p = document.createElement('pre'); p.id = 'out';
        p.textContent = c.toDataURL('image/webp', 0.9); document.body.appendChild(p); };
      img.src = 'data:image/png;base64,%s';
    </script></body>""" % data)
    r = chrome("--virtual-time-budget=5000", "--dump-dom", "file://" + conv)
    m = re.search(r"data:image/webp;base64,([A-Za-z0-9+/=]+)", r.stdout)
    if not m:
        sys.exit("no WebP from the canvas:\n" + r.stderr[-2000:])
    webp = base64.b64decode(m.group(1))
    open(OUT, "wb").write(webp)
    print("wrote %s, %d x %d, %d KB" % (os.path.relpath(OUT, ROOT), W, H, round(len(webp) / 1024)))


if __name__ == "__main__":
    main()
