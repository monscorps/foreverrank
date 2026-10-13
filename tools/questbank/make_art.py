#!/usr/bin/env python3
"""QuestBank's own textures (QuestBank/art/*.tga): a soft glow, a four-point sparkle, a ring, and a line strip, drawn
here as 32-bit TGA with alpha, which every WoW client loads. Sizes are powers of two. python3 make_art.py rewrites them."""
import math, os, struct
HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "QuestBank", "art")

def tga(path, w, h, px):
    """px(x, y) -> (r, g, b, a) in 0..255; TGA stores bottom-up BGRA."""
    with open(path, "wb") as f:
        f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8))
        rows = []
        for y in range(h - 1, -1, -1):
            row = bytearray()
            for x in range(w):
                r, g, b, a = px(x, y)
                row += bytes((b, g, r, a))
            rows.append(bytes(row))
        f.write(b"".join(rows))

def smooth(t):
    t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)

def glow(size=128):
    c = (size - 1) / 2
    def px(x, y):
        d = math.hypot(x - c, y - c) / c
        a = (1 - smooth(d)) ** 1.6
        return 255, 255, 255, int(255 * a)
    return px

def ring(size=128, inner=0.72, width=0.14):
    c = (size - 1) / 2
    def px(x, y):
        d = math.hypot(x - c, y - c) / c
        a = max(0.0, 1 - abs(d - (inner + width / 2)) / (width / 2))
        a = smooth(a) * (0.0 if d > 1 else 1.0)
        return 255, 255, 255, int(255 * a)
    return px

def sparkle(size=128):
    c = (size - 1) / 2
    def px(x, y):
        dx, dy = (x - c) / c, (y - c) / c
        d = math.hypot(dx, dy)
        # four thin rays plus a bright core
        ray = max(math.exp(-((abs(dx) * 9) ** 2)) * (1 - abs(dy)) ** 2, math.exp(-((abs(dy) * 9) ** 2)) * (1 - abs(dx)) ** 2)
        diag = 0.35 * max(math.exp(-((abs(dx - dy) * 10) ** 2)), math.exp(-((abs(dx + dy) * 10) ** 2))) * (1 - d) ** 2
        core = math.exp(-((d * 4) ** 2))
        a = min(1.0, ray + diag + core)
        return 255, 255, 255, int(255 * a)
    return px

def line(w=16, h=64):
    def px(x, y):
        u = (x - (w - 1) / 2) / ((w - 1) / 2)
        a = (1 - abs(u)) ** 1.4
        return 255, 255, 255, int(255 * max(0.0, a))
    return px

def border(size=256, inner=0.90, width=0.045):
    """a thin ring with a soft dark halo outside: the big map's edge"""
    c = (size - 1) / 2
    def px(x, y):
        d = math.hypot(x - c, y - c) / c
        ring = max(0.0, 1 - abs(d - (inner + width / 2)) / (width / 2))
        halo = 0.0
        if d > inner + width: halo = max(0.0, 1 - (d - inner - width) / (1 - inner - width)) * 0.85
        a = min(1.0, smooth(ring) + halo)
        v = 255 if ring > 0.05 else 0
        return v, v, v, int(255 * a)
    return px

def diamond(size=32):
    """a diamond with a light rim: an objective's mark"""
    c = (size - 1) / 2
    def px(x, y):
        d = (abs(x - c) + abs(y - c)) / c
        if d > 1: return 0, 0, 0, 0
        edge = smooth((1 - d) * 6)
        rim = 1.0 if d > 0.72 else 0.0
        v = int(255 * (0.75 + 0.25 * rim))
        return v, v, v, int(255 * edge)
    return px

def dot(size=32):
    c = (size - 1) / 2
    def px(x, y):
        d = math.hypot(x - c, y - c) / c
        edge = smooth((1 - d) * 4)
        return 255, 255, 255, int(255 * edge)
    return px

if __name__ == "__main__":
    os.makedirs(HERE, exist_ok=True)
    tga(os.path.join(HERE, "glow.tga"), 128, 128, glow())
    tga(os.path.join(HERE, "ring.tga"), 128, 128, ring())
    tga(os.path.join(HERE, "sparkle.tga"), 128, 128, sparkle())
    tga(os.path.join(HERE, "line.tga"), 16, 64, line())
    tga(os.path.join(HERE, "dot.tga"), 32, 32, dot())
    tga(os.path.join(HERE, "border.tga"), 256, 256, border())
    tga(os.path.join(HERE, "diamond.tga"), 32, 32, diamond())
    print("wrote", sorted(os.listdir(HERE)))
