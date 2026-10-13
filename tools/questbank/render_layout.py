#!/usr/bin/env python3
"""Draw the harness's layout dump (luajit harness.lua --layout out.json) as an HTML page, one picture per screen:
frames as boxes, text at its size and colour, the game's icons from the icon CDN by name, other art as tinted
placeholders labelled with what they are. A look at what QuestBank really draws, without the game.
  python3 render_layout.py layout.json out.html"""
import html, json, os, sys
MAN = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "research", "questbank", "manifest.json")))
BY_ID = {int(v): k for k, v in MAN.items()}

def rgba(c, a=1.0, default="rgba(0,0,0,0)"):
    if not c: return default
    r, g, b = [int(255 * max(0, min(1, x or 0))) for x in c[:3]]
    al = c[3] if len(c) > 3 and c[3] is not None else a
    return "rgba(%d,%d,%d,%.2f)" % (r, g, b, al * (a if len(c) <= 3 or c[3] is None else 1))

def tex_style(it):
    raw = it.get("raw")
    path = BY_ID.get(int(raw)) if isinstance(raw, (int, float)) else (raw if isinstance(raw, str) else None)
    if path and path.startswith("interface/icons/"):
        name = path[len("interface/icons/"):-4]
        url = "https://wow.zamimg.com/images/wow/icons/large/%s.jpg" % name
        tint = ""
        if it.get("desat"): tint = "filter:grayscale(1);"
        return "background:url(%s) center/cover;%s" % (url, tint), None
    if isinstance(raw, str) and raw.startswith("atlas:"):
        return "background:rgba(242,207,107,.85);border-radius:50%;", raw[6:]
    if path and path.endswith(".tga"):
        pass
    c = it.get("c")
    label = (path or str(raw or it.get("tex") or "")).split("/")[-1].replace(".blp", "")
    if it.get("tex") == "color" or (path and path.endswith("white8x8.blp")) or (isinstance(raw, str) and "WHITE8x8" in raw):
        return "background:%s;" % rgba(c, 1), None
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
