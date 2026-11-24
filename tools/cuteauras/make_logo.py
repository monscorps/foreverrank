#!/usr/bin/env python3
"""Cute Auras' emblem (the owner, 2026-11-24: "cant have exact same minimap icon as cute addon, we need a flavour for
this one"): Cute's girl in front of a rose aura instead of Cute's dark-teal disc. It is the minimap button, the addon
list's icon and the addon compartment's (CuteAuras.toc's IconTexture).

  python3 tools/cuteauras/make_logo.py [SRC] [OUT]
      (defaults: tools/cute/Cute/art/logo.png -> tools/cuteauras/CuteAuras/art/logo.png)

Needs Pillow, numpy and scipy (the user site-packages, so no -I: it reads only our own art). Picked from four
directions (rose, holy light, arcane, a glowing rim) by three judges looking at the 1080p minimap next to Cute's
button: the hue jump teal -> rose reads at 28 px, the dark bottom replaces Cute's white letter blocks.

Only the teal disc, the clipped CUTE letters and the light around her change. Her face, eyes, hair and clothes keep
their exact pixels, except her lowest bust rows, which sink into shadow where the letters were.

Steps
  1. Find the teal disc: hue 150-192, saturated, as connected pieces outside the face box (the irises carry a little
     teal; they are left alone).
  2. Un-mix the soft edge: each pixel just outside the disc is split into "teal" and "whatever is next to it" (the
     nearest solid non-teal pixel), and only the teal share is swapped. Pixels where red leads are never touched.
     A few line-work pixels further out that still carry a grey-green cast keep their brightness and take the
     aura's hue.
  3. The aura: a soft lobe of light behind and above her crown (a little left of centre, so both crescents come out
     the same rose at 28 px) fills the upper crescents with pale rose, and falls through dusky rose to deep wine at
     the gold ring and down by her shoulders. A 1-2 px graze of the addon pink (1, 0.6, 0.84) runs along her
     outline where the light is strongest. A slow fixed-seed unevenness and the disc's own paint grain keep it from
     reading as a flat gradient. No sparkles: they do not survive 28 px.
  4. The bottom: the clipped CUTE letters are lifted out (filled from the dark brown round them, so no letter shape
     survives) and her bust sinks into the aura's wine shadow along a shallow curve that follows the frame, starting
     below the brooch's knot: first darkening (so the blue keeps its hue), then turning wine, never dipping darker
     than the wine on the way. The crescents' lower ends sink into the same shadow, the art's gold ring keeps its
     lower right run, and a thin rose crescent of light pools just inside the bottom of the frame, swelling and
     thinning along its length, so the disc reads as one lit circle and not a cut.

  5. Round: everything outside the square's inscribed circle is cleared (a soft edge), so the uncut icon in the
     addon list and the compartment is a round coin too; the minimap's portrait mask cuts there anyway.

Deterministic: the noise is seeded, two runs give the same bytes.
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "tools", "cute", "Cute", "art", "logo.png")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "CuteAuras", "art", "logo.png")

GAME_DISC = np.array([8, 8, 10]) / 255.0  # the dark disc the game draws under the emblem
FACE = (80, 95, 176, 150)                 # x0, y0, x1, y1: her face and eyes; nothing in here may change
MASK_C, MASK_R = 128.0, 125.4             # the game's round portrait mask (the inscribed circle, a touch inside)

# The aura's colour ramp, dark to light. Dusky rose and wine in the middle, the addon pink only near the top.
STOPS = [
    (0.00, (30, 4, 18)),      # at the ring: almost black wine
    (0.18, (64, 12, 40)),     # deep wine
    (0.40, (116, 26, 74)),    # wine-rose
    (0.62, (198, 82, 138)),   # dusky rose
    (0.82, (255, 153, 214)),  # the addon pink (1, 0.6, 0.84)
    (1.00, (255, 214, 236)),  # never reached: the light is capped below white
]


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def gradient_map(t, stops=STOPS):
    """t in [0,1] -> RGB (0..1) through (pos, (r,g,b)) stops, interpolated in linear light."""
    pos = np.array([p for p, _ in stops])
    cols = (np.array([c for _, c in stops], dtype=float) / 255.0) ** 2.2
    out = np.empty(t.shape + (3,))
    for k in range(3):
        out[..., k] = np.interp(t, pos, cols[:, k])
    return np.clip(out, 0, 1) ** (1 / 2.2)


def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rm = m & (mx == r)
    gm = m & (mx == g) & ~rm
    bm = m & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = (b - r)[gm] / d[gm] + 2
    h[bm] = (r - g)[bm] / d[bm] + 4
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    return h * 60.0, s, mx


def main():
    src = np.asarray(Image.open(SRC).convert("RGBA")).astype(float) / 255.0
    H, W = src.shape[:2]
    rgb, alpha = src[..., :3].copy(), src[..., 3].copy()
    hue, sat, val = rgb_to_hsv(rgb)
    yy, xx = np.mgrid[0:H, 0:W].astype(float) + 0.5
    rr = np.hypot(xx - MASK_C, yy - MASK_C)
    in_face = (xx >= FACE[0]) & (xx < FACE[2]) & (yy >= FACE[1]) & (yy < FACE[3])
    rng = np.random.default_rng(20261124)
    cloud = ndi.gaussian_filter(rng.standard_normal((H, W)), 9.0)
    cloud /= np.abs(cloud).max()

    # 1. the teal disc ------------------------------------------------------------------------------------------
    teal = (hue > 150) & (hue < 192) & (sat > 0.2) & (alpha > 40 / 255)
    lab, _ = ndi.label(teal, structure=np.ones((3, 3)))
    core = np.zeros_like(teal)
    for i, sl in enumerate(ndi.find_objects(lab), start=1):
        ys, xs = sl
        inside_face = xs.start >= FACE[0] and xs.stop <= FACE[2] and ys.start >= FACE[1] and ys.stop <= FACE[3]
        if not inside_face and (lab[sl] == i).sum() >= 3:
            core |= lab == i
    core = (ndi.binary_closing(core, structure=np.ones((3, 3)), iterations=1) | core) & ~in_face

    # 2. un-mix the edge band -----------------------------------------------------------------------------------
    band = ndi.binary_dilation(core, iterations=3) & ~core & ~in_face
    solid_other = (~core) & (~band) & (alpha > 0.85)
    _, (ty, tx) = ndi.distance_transform_edt(~core, return_indices=True)
    _, (oy, ox) = ndi.distance_transform_edt(~solid_other, return_indices=True)
    T = rgb[ty, tx]
    O = rgb[oy, ox]
    TO = T - O
    den = (TO * TO).sum(-1)
    a_mix = np.clip(((rgb - O) * TO).sum(-1) / np.maximum(den, 1e-6), 0, 1)
    a_mix = np.where(den < 0.01, 0.0, a_mix)
    lean = smoothstep(-0.02, 0.06, np.minimum(rgb[..., 1], rgb[..., 2]) - rgb[..., 0])
    A = np.where(core, 1.0, np.where(band, a_mix * lean, 0.0))

    # 3. the aura -----------------------------------------------------------------------------------------------
    # How far across its crescent each disc pixel sits: 1 against her, 0 against the gold ring (or the mask edge,
    # where the art's ring runs outside the game's round cut, down the left side).
    opaque_other = (~core) & (~band) & (alpha > 0.5)
    her = opaque_other & (rr < 108)
    ring = (opaque_other & (rr >= 108)) | (rr >= 123.5)
    d_her = ndi.distance_transform_edt(~her)
    d_ring = ndi.distance_transform_edt(~ring)
    across = d_ring / np.maximum(d_her + d_ring, 1e-6)
    # The light sits behind and above her crown: a broad lobe that fills the upper crescents and dims down by her
    # shoulders. It fills each crescent and only gives way to wine in the last stretch before the ring, so it does
    # not hug her outline like an outer glow. Its centre sits a little left of hers: the right crescent is wider
    # and reaches higher (by her ear), so a centred light leaves the left side wine and the right one pale. Here
    # the two crescents average within a few levels of each other at 28 px.
    lx, ly, sx, sy = 106.0, 60.0, 150.0, 100.0
    lobe = np.exp(-0.5 * (((xx - lx) / sx) ** 2 + ((yy - ly) / sy) ** 2))
    fill = smoothstep(0.0, 0.75, across) ** 0.85
    ring_dark = smoothstep(0.0, 7.0, d_ring)  # the last few px against the ring are wine, whatever the width
    # painted backlight: a 1-2 px graze of the addon pink along her outline, where the light is strong
    graze = np.exp(-np.maximum(d_her - 0.5, 0) / 1.6) * smoothstep(0.35, 0.75, lobe)
    # the aura's light caught in the bottom of the bowl: a soft rose crescent hugging the frame, from the lower
    # right round under her and up the lower left (where the left crescent meets the game's ring)
    theta = np.degrees(np.arctan2(yy - MASK_C, xx - MASK_C))  # 0 = right, 90 = straight down, 180 = left
    t_arc = np.where(theta < 100, (theta - 100) / 58.0, (theta - 100) / 66.0)
    arc_w = np.cos(np.radians(np.clip(t_arc * 90, -90, 90))) ** 2 * (theta > 0)
    # Peaks ~8 px inside the mask edge: the game's soft mask and the tracking ring's inner shadow eat the last few.
    d_edge = MASK_R - rr  # px inside the mask edge
    pk = 8.0
    arc_prof = np.where(d_edge < pk, np.exp(-0.5 * ((d_edge - pk) / 3.2) ** 2), np.exp(-(d_edge - pk) / 9.0))
    pool = np.exp(-np.maximum(d_edge - pk, 0) / 18.0)  # and a faint lift of the whole bowl toward it
    # uneven along its length, like a painted stroke: swells and thins with a slow noise sampled round the circle
    swell = ndi.gaussian_filter1d(rng.standard_normal(720), 18.0, mode="wrap")
    swell /= np.abs(swell).max()
    swell = swell[(np.round(theta * 2).astype(int)) % 720]
    arc = (arc_prof * (1.0 + 0.50 * swell) + 0.35 * pool) * arc_w * (1.0 + 0.20 * cloud)
    intensity = 0.12 + (0.88 * lobe * fill) * (0.65 + 0.35 * ring_dark) + 0.16 * graze + 0.24 * arc
    intensity = np.clip(intensity * (1.0 + 0.08 * cloud), 0, 0.84)
    aura = gradient_map(intensity)
    vmed = np.median(val[core])
    grain = np.clip(val[ty, tx] / vmed, 0.8, 1.2) ** 0.7  # the disc's own paint grain
    aura = np.clip(aura * grain[..., None], 0, 1)

    out = rgb + A[..., None] * (aura - T)  # swap only the teal share of each pixel
    out = np.where(core[..., None], aura, out)
    out = np.clip(out, 0, 1)
    # A few line-work pixels a little further out still carry a grey-green cast from the old disc (thin gaps
    # between hair strands, the soft rim of the outlines). They keep their brightness and take the aura's hue.
    near = ndi.binary_dilation(core, iterations=8) & ~core & ~in_face
    oh, _, _ = rgb_to_hsv(out)
    cast = near & (oh > 70) & (oh < 200)
    cast_w = np.where(cast, smoothstep(0.004, 0.04, out[..., 1] - out[..., 0]), 0.0)

    def lum(c):
        return 0.299 * c[..., 0] + 0.587 * c[..., 1] + 0.114 * c[..., 2]
    tint = aura[ty, tx]
    rehued = np.clip(tint * (lum(out) / np.maximum(lum(tint), 1e-4))[..., None], 0, 1)
    out = out + cast_w[..., None] * (rehued - out)

    # 4. the bottom ---------------------------------------------------------------------------------------------
    # The clipped letters: pale cream (her chest skin is the same hue but more saturated), below her bust.
    cream = (sat < 0.34) & (val > 0.70) & (hue > 18) & (hue < 65) & (yy > 210) & (alpha > 0.5)
    lab, _ = ndi.label(cream, structure=np.ones((3, 3)))
    letters = np.zeros_like(cream)
    for i, sl in enumerate(ndi.find_objects(lab), start=1):
        if sl[0].stop >= 236 and (lab[sl] == i).sum() >= 40:  # letters run down to the bottom edge
            letters |= lab == i
    # with their shading and the soft pixels round them
    letters = ndi.binary_dilation(ndi.binary_closing(letters, iterations=2), iterations=2)
    letters_soft = np.clip(ndi.gaussian_filter(letters.astype(float), 1.0) * 1.5, 0, 1)
    # Her bust sinks into shadow along a shallow curve that follows the frame: lowest in the middle, so the whole
    # brooch and her shoulders survive; spread over ~20 px so it reads as shadow, not a crop line.
    ylift = yy + 0.0010 * (xx - 128) ** 2
    fade = smoothstep(212, 231, ylift) ** 1.5
    # the crescents' own lower ends sink into the same shadow a little earlier, so they meet it without a seam
    fade = np.maximum(fade, A * smoothstep(192, 216, yy) ** 1.3)
    fade = np.where(in_face, 0.0, fade)

    # The shadow is the aura's own wine, with a little life in it: a touch brighter toward the sides where the
    # crescents come down, darkest straight under her, and the same slow unevenness as the light; the rose
    # crescent of light in the bottom of the bowl runs through it.
    side = smoothstep(25, 105, np.abs(xx - 128))
    shade_i = (0.08 + 0.08 * side) * (1.0 + 0.35 * cloud) * (1.0 - 0.30 * smoothstep(225, 250, yy)) + 0.36 * arc
    shade = gradient_map(np.clip(shade_i, 0, 0.84))

    disc = GAME_DISC
    shown = out * alpha[..., None] + disc * (1 - alpha[..., None])  # what the game shows today
    # The letters are taken out first and filled with what is round them below her bust (the dark brown of her
    # clothes and hair ends, never her pale chest), so no letter shape, light or dark, survives into the shadow.
    body = (alpha > 0.9) & (val < 0.5) & ~letters & (yy > 196)
    wgt = ndi.gaussian_filter(body.astype(float), 5.0)
    behind = np.stack([ndi.gaussian_filter(shown[..., k] * body, 5.0) for k in range(3)], -1) / np.maximum(wgt, 1e-3)[..., None]
    behind = np.where((wgt > 0.02)[..., None], behind, disc) * 0.8
    shown = shown * (1 - letters_soft[..., None]) + behind * letters_soft[..., None]
    fade = np.maximum(fade, letters_soft * smoothstep(214, 222, yy))
    # First darken (her colours keep their hue), then turn to wine. Never darker than the wine itself on the way:
    # dark pixels (her line-work, the see-through gaps) go straight toward the wine, so there is no black trough
    # along the shadow's edge.
    Lx, Ls = lum(shown), lum(shade)
    k = 1.0 - 0.80 * smoothstep(0.0, 0.65, fade)
    k = np.maximum(k, np.minimum(1.0, Ls / np.maximum(Lx, 1e-4)))
    darkened = shown * k[..., None]
    w = smoothstep(0.35, 1.0, fade)
    w = np.maximum(w, np.clip(1.0 - Lx / np.maximum(Ls, 1e-4), 0, 1) * smoothstep(0.05, 0.40, fade))
    w = w[..., None]
    target = darkened * (1 - w) + shade * w
    # the shadow fills the letters' transparent outlines, so the pixel turns opaque as the fade comes in
    new_alpha = alpha + (1 - alpha) * np.minimum(1.0, fade * 3.0)
    out = np.clip((target - disc * (1 - new_alpha[..., None])) / np.maximum(new_alpha[..., None], 1e-6), 0, 1)
    alpha = new_alpha

    # every pixel neither in the disc's reach nor in the shadow keeps its exact source value
    untouched = (A <= 0) & (fade <= 0) & (cast_w <= 0)
    out = np.where(untouched[..., None], rgb, out)
    alpha = np.where(untouched, src[..., 3], alpha)

    # 5. round: clear outside the inscribed circle, 4x supersampled for a soft edge
    ss = 4
    sy, sx = np.mgrid[0:H * ss, 0:W * ss].astype(float) + 0.5
    disc_in = (np.hypot(sx / ss - W / 2.0, sy / ss - H / 2.0) <= W / 2.0 - 0.5).astype(float)
    alpha = alpha * disc_in.reshape(H, ss, W, ss).mean(axis=(1, 3))

    img = np.dstack([out, alpha])
    Image.fromarray(np.round(img * 255).astype(np.uint8)).save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
