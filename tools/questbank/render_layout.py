#!/usr/bin/env python3
"""Draw the harness's layout dump (luajit harness.lua --layout out.json) as an HTML page, one picture per screen:
frames as boxes, text at its size and colour, the game's icons from the icon CDN by name, other art as tinted
placeholders labelled with what they are. A look at what QuestBank really draws, without the game.
  python3 render_layout.py layout.json out.html"""
import html, json, math, os, sys
MAN = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "research", "questbank", "manifest.json")))
BY_ID = {int(v): k for k, v in MAN.items()}

def rgba(c, a=1.0, default="rgba(0,0,0,0)"):
    if not c: return default
    r, g, b = [int(255 * max(0, min(1, x or 0))) for x in c[:3]]
    al = c[3] if len(c) > 3 and c[3] is not None else a
    return "rgba(%d,%d,%d,%.2f)" % (r, g, b, al * (a if len(c) <= 3 or c[3] is None else 1))

import base64
def _svg(body):
    return base64.b64encode(("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'>%s</svg>" % body).encode()).decode()
MARKS = {
    "readycheck-ready.blp": _svg("<path d='M3 13l6 6L21 5' fill='none' stroke='#000' stroke-width='6' stroke-linecap='round'/><path d='M3 13l6 6L21 5' fill='none' stroke='#33dd44' stroke-width='3.5' stroke-linecap='round'/>"),
    "readycheck-notready.blp": _svg("<path d='M5 5l14 14M19 5L5 19' stroke='#000' stroke-width='6' stroke-linecap='round'/><path d='M5 5l14 14M19 5L5 19' stroke='#e03a2a' stroke-width='3.5' stroke-linecap='round'/>"),
    "readycheck-waiting.blp": _svg("<circle cx='12' cy='12' r='8' fill='#888' stroke='#000' stroke-width='2'/>"),
    "availablequesticon.blp": _svg("<text x='12' y='21' text-anchor='middle' font-family='Georgia' font-weight='bold' font-size='22' fill='#ffd100' stroke='#000' stroke-width='1.2'>!</text>"),
    "activequesticon.blp": _svg("<text x='12' y='21' text-anchor='middle' font-family='Georgia' font-weight='bold' font-size='22' fill='#ffd100' stroke='#000' stroke-width='1.2'>?</text>"),
}
GLOW = {"green": "30,255,0", "blue": "0,112,221", "purple": "163,53,238", "orange": "255,128,0", "white": "255,255,255"}
# atlases with no local picture, drawn close enough to judge: the campaign headers' open and closed marks (a gold ring
# with a minus or a plus) and the modern check box with its check
_RING = "<circle cx='12' cy='12' r='9' fill='#2a1d0e' stroke='#c9a24a' stroke-width='2.2'/>"
ATLAS_SVG = {
    "campaign_headericon_closed": _svg(_RING + "<path d='M7.5 12h9M12 7.5v9' stroke='#f2d27a' stroke-width='2.4' stroke-linecap='round'/>"),
    "campaign_headericon_open": _svg(_RING + "<path d='M7.5 12h9' stroke='#f2d27a' stroke-width='2.4' stroke-linecap='round'/>"),
    "checkbox-minimal": _svg("<rect x='2.5' y='2.5' width='19' height='19' rx='3' fill='#0d0f12' stroke='#9a9488' stroke-width='1.6'/>"),
    "checkmark-minimal": _svg("<path d='M6 12.5l4 4 8-9' fill='none' stroke='#ffd24a' stroke-width='3' stroke-linecap='round' stroke-linejoin='round'/>"),
    # the numbered quest marker (its number is a font string over it; gold for the next one), the flight path's green
    # ring, the grey-gold ? of a quest in your log
    "ui-questpoi-questnumber": _svg("<circle cx='12' cy='12' r='9.5' fill='#20160a' stroke='#d9b04a' stroke-width='2.2'/>"),
    "ui-questpoi-questnumber-supertracked": _svg("<circle cx='12' cy='12' r='9.5' fill='#c99a2e' stroke='#3a2608' stroke-width='2.2'/>"),
    "flightpath": _svg("<circle cx='12' cy='12' r='8.5' fill='#1d5a1d' stroke='#7fe07f' stroke-width='2.2'/><path d='M6 13l6-5 6 5' fill='none' stroke='#e8ffe8' stroke-width='2' stroke-linecap='round'/>"),
    "quest-in-progress-icon-yellow": _svg("<text x='12' y='20' text-anchor='middle' font-family='Georgia' font-weight='bold' font-size='20' fill='#b8a35a' stroke='#000' stroke-width='1'>?</text>"),
}

LOCAL_TEX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "research", "qbrender", "tex")

def tex_style(it):
    raw = it.get("raw")
    # client art fetched once as PNG (research/qbrender/tex/<file id>.png): the dungeon floors, covers and portraits
    if isinstance(raw, (int, float)) and os.path.exists(os.path.join(LOCAL_TEX, "%d.png" % int(raw))):
        round = "border-radius:50%;" if it.get("mask") else ""
        return "background:url(tex/%d.png) center/100%% 100%%;%s" % (int(raw), round), None
    path = BY_ID.get(int(raw)) if isinstance(raw, (int, float)) else (raw if isinstance(raw, str) else None)
    if path and path.startswith("interface/icons/"):
        name = path[len("interface/icons/"):-4]
        url = "https://wow.zamimg.com/images/wow/icons/large/%s.jpg" % name
        tint = ""
        if it.get("desat"): tint = "filter:grayscale(1);"
        return "background:url(%s) center/cover;%s" % (url, tint), None
    # the bags' glow round an item (bags-glow-green and its kin): a soft coloured edge inside the slot
    if isinstance(raw, str) and raw.lower().startswith("atlas:bags-glow-"):
        col = GLOW.get(raw[len("atlas:bags-glow-"):].lower(), "255,255,255")
        return "box-shadow:inset 0 0 4px 2px rgba(%s,.95),0 0 3px 1px rgba(%s,.7);border-radius:3px;" % (col, col), None
    if isinstance(raw, str) and raw.startswith("atlas:"):
        name = raw[6:].lower()
        rot = ("transform:rotate(%.3frad);" % -it["rot"]) if it.get("rot") else ""
        if os.path.exists(os.path.join(LOCAL_TEX, "atlas_%s.png" % name)):
            c = it.get("c")
            if it.get("desat") and c:
                # the game greys the art and multiplies by the tint: a tinted silhouette is close enough to judge
                col = rgba(c, 1)
                return ("background:%s;-webkit-mask:url(tex/atlas_%s.png) center/100%% 100%% no-repeat;mask:url(tex/atlas_%s.png) center/100%% 100%% no-repeat;%s" % (col, name, name, rot)), None
            return "background:url(tex/atlas_%s.png) center/100%% 100%% no-repeat;%s" % (name, rot), None
        if name in ATLAS_SVG:
            return "background:url(data:image/svg+xml;base64,%s) center/contain no-repeat;" % ATLAS_SVG[name], None
        return "background:rgba(242,207,107,.85);border-radius:50%;", raw[6:]
    if path and path.endswith(".tga"):
        pass
    # the game's small marks, drawn as close as a picture can: the ready check, the red X, the waiting disc, the gossip !
    mark = MARKS.get((path or "").split("/")[-1])
    if mark:
        return "background:url(data:image/svg+xml;base64,%s) center/contain no-repeat;" % mark, None
    c = it.get("c")
    label = (path or str(raw or it.get("tex") or "")).split("/")[-1].replace(".blp", "")
    if it.get("tex") == "color" or (path and path.endswith("white8x8.blp")) or (isinstance(raw, str) and "WHITE8x8" in raw):
        return "background:%s;" % rgba(c, 1), None
    if isinstance(raw, str) and "ReadyCheck-Ready" in raw:
        return "background:url(data:image/svg+xml;base64,PHN2ZyB4bWxucz0naHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmcnIHZpZXdCb3g9JzAgMCAyNCAyNCc+PHBhdGggZD0nTTMgMTNsNiA2TDIxIDUnIGZpbGw9J25vbmUnIHN0cm9rZT0nIzAwMCcgc3Ryb2tlLXdpZHRoPSc2JyBzdHJva2UtbGluZWNhcD0ncm91bmQnLz48cGF0aCBkPSdNMyAxM2w2IDZMMjEgNScgZmlsbD0nbm9uZScgc3Ryb2tlPScjMzNkZDQ0JyBzdHJva2Utd2lkdGg9JzMuNScgc3Ryb2tlLWxpbmVjYXA9J3JvdW5kJy8+PC9zdmc+) center/contain no-repeat;transform:rotate(-17deg);", None
    if isinstance(raw, str) and raw.endswith("art\\ring"):
        return "border:2px solid %s;border-radius:50%%;" % rgba(c or (1, 0.82, 0.3), 1), None
    if isinstance(raw, str) and raw.startswith("Interface\\AddOns\\QuestBank\\art\\"):
        return "background:radial-gradient(%s,transparent 70%%);" % rgba(c or (1, 0.82, 0.3), 0.8), None
    return "background:%s;outline:1px dashed rgba(255,255,255,.12);" % rgba(c or (0.3, 0.3, 0.35), 0.35), label

def render(layout):
    out = ['<div class="shot"><h2>%s</h2><div class="win" style="width:%dpx;height:%dpx">' % (html.escape(layout["label"]), layout["w"], layout["h"])]
    items = sorted(layout["items"], key=lambda it: (it.get("depth", 0), {"BACKGROUND": 0, "BORDER": 1, "ARTWORK": 2, "OVERLAY": 3, "HIGHLIGHT": 4}.get(it.get("layer"), 2), it["i"]))
    for it in items:
        x, y, w, h = it["x"], it["y"], it["w"], it["h"]
        clip = it.get("clip")
        if clip and (y + h < clip["y"] or y > clip["y"] + clip["h"]): continue
        a = it.get("a", 1) or 1
        base = "left:%dpx;top:%dpx;width:%dpx;height:%dpx;opacity:%.2f;" % (x, y, w, h, a)
        # a scroll view shows only what is inside it, as the game cuts it
        if clip:
            ct, cb = max(0, clip["y"] - y), max(0, (y + h) - (clip["y"] + clip["h"]))
            cl, cr = max(0, clip["x"] - x), max(0, (x + w) - (clip["x"] + clip["w"]))
            if ct or cb or cl or cr: base += "clip-path:inset(%dpx %dpx %dpx %dpx);" % (ct, cr, cb, cl)
        if it["k"] == "Line":
            # a stroke of line_arrow.png: a light core in its colour between dark edges, turned from its start
            dx, dy = it["x2"] - it["x1"], it["y2"] - it["y1"]
            th, col = it.get("thick") or 2, rgba(it.get("c") or (1, 0.84, 0.18), 1)
            out.append('<div style="left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;opacity:%.2f;transform-origin:0 50%%;transform:rotate(%.4frad);'
                       'background:linear-gradient(rgba(0,0,0,.75),%s 30%%,%s 70%%,rgba(0,0,0,.75));border-radius:%.1fpx"></div>'
                       % (it["x1"], it["y1"] - th / 2, math.hypot(dx, dy), th, a, math.atan2(dy, dx), col, col, th / 2))
            continue
        if it["k"] == "FontString":
            c = rgba(it.get("c") or (0.93, 0.88, 0.78), 1)
            size = it.get("size") or 12
            j = {"LEFT": "left", "RIGHT": "right", "CENTER": "center"}.get(it.get("j"), "left")
            ws = "normal" if it.get("wrap") else "nowrap"
            out.append('<div class="t" style="%scolor:%s;font-size:%dpx;text-align:%s;white-space:%s">%s</div>' % (base, c, size, j, ws, html.escape(it.get("text") or "").replace("\n", "<br>")))
        elif it["k"] == "Texture":
            st, label = tex_style(it)
            if it.get("blend") == "ADD": st += "mix-blend-mode:screen;"
            out.append('<div class="x" style="%s%s"%s></div>' % (base, st, (' title="%s"' % html.escape(label)) if label else ""))
        else:
            st = ""
            if it.get("bd"):
                st = "background:%s;border:1px solid %s;border-radius:3px;" % (rgba(it.get("bdc") or (0.08, 0.1, 0.14), 0.9), rgba(it.get("bdb") or (0.45, 0.36, 0.2), 1))
            if it.get("tpl") == "UIPanelButtonTemplate":
                st = "background:linear-gradient(#5a1a10,#3a0f08);border:1px solid #8a6a2f;border-radius:3px;"
            if it.get("tpl") == "UICheckButtonTemplate":
                st = "background:#0b1119;border:1px solid #6a5a3a;border-radius:2px;"
            if it.get("tpl") == "UIPanelCloseButton":
                st = "background:#5a1a10;border-radius:3px;"
            # a live 3D model (the journal's loot face): a shaded bust where the creature would stand
            if it["k"] == "PlayerModel":
                st = "background:radial-gradient(circle at 50% 38%,#8a7660 0,#4a3a2a 45%,transparent 70%);"
            if st:
                txt = html.escape(it.get("text") or "")
                out.append('<div class="f" style="%s%s">%s</div>' % (base, st, ('<span>%s</span>' % txt) if txt else ""))
    out.append("</div></div>")
    return "\n".join(out)

def main():
    src, dst = sys.argv[1], sys.argv[2]
    data = json.load(open(src))
    pick = sys.argv[3].split(",") if len(sys.argv) > 3 else None
    body = [render(L) for L in data if not pick or any(p.lower() in L["label"].lower() for p in pick)]
    page = """<!doctype html><html><head><meta charset="utf-8"><title>QuestBank as drawn</title><style>
body{margin:0;padding:20px;background:#05070a;color:#ccc;font:13px Inter,Arial,sans-serif}
h2{font:600 14px Arial;color:#f2cf6b;margin:24px 0 8px}
.win{position:relative;background:#0b0f15;outline:1px solid #333;overflow:hidden}
.win div{position:absolute;box-sizing:border-box}
.t{font-family:"Friz Quadrata TT","Palatino Linotype",Georgia,serif;line-height:1.15;overflow:hidden;text-shadow:0 1px 0 #000}
.f span{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;color:#f2cf6b;font:12px Georgia,serif}
</style></head><body>%s</body></html>""" % "\n".join(body)
    open(dst, "w").write(page)
    print("wrote", dst, len(body), "screens")

if __name__ == "__main__":
    main()
