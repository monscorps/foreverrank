#!/usr/bin/env python3
"""Build a data-driven news article: tools/articles/<slug>.src.html plus
<slug>.data.json become news/<slug>/index.html, with only the items and
spells the page references (data-k="i:<id>" or data-k="<spell key>")
inlined for its tooltips. Any other top-level key of the data file is
inlined only when the src opts in with data-json="<key>" on some element
(e.g. a chart figure that reads D.rebase). A src whose art-data script tag
carries data-inline-icons also gets every data-k icon's image, its item
quality class and the item's one-line brief written into the markup at
build time, so the page shows them without JavaScript (the page's script
only fills what is still empty). Srcs without these attributes get exactly
the spells and items they reference, as before. Then run tools/seo.py for
the head tags.

  python3 tools/articles/build.py build-70009
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

slug = sys.argv[1]
src = open(os.path.join(HERE, slug + ".src.html"), encoding="utf-8").read()
data = json.load(open(os.path.join(HERE, slug + ".data.json"), encoding="utf-8"))
keep = {"spells": {}, "items": {}}
missing = []
for k in sorted(set(re.findall(r'data-k="([^"]+)"', src))):
    if k.startswith("i:"):
        (keep["items"].__setitem__(k[2:], data["items"][k[2:]]) if k[2:] in data["items"] else missing.append(k))
    else:
        (keep["spells"].__setitem__(k, data["spells"][k]) if k in data["spells"] else missing.append(k))
for k in sorted(set(re.findall(r'data-json="([^"]+)"', src))):
    (keep.__setitem__(k, data[k]) if k in data and k not in ("spells", "items") else missing.append("json:" + k))
if missing:
    sys.exit("no data for: " + ", ".join(missing))
if re.search(r'<script[^>]*id="art-data"[^>]*\bdata-inline-icons\b', src):
    import html
    CDN = "https://wow.zamimg.com/images/wow/icons/large/"

    def ent(k):
        if k.startswith("i:"):
            it = keep["items"].get(k[2:])
            return it and (it.get("icon"), it.get("quality"), it.get("brief"))
        sp = keep["spells"].get(k)
        return sp and (sp.get("icon"), None, None)

    def styled(cls, icon, q):
        if q and "q-" not in cls:
            cls += " q-" + q
        url = icon if icon.startswith("/") else CDN + icon + ".jpg"
        return cls, ' style="background-image:url(' + url + ')"'

    def own(m):  # <span class="ico ..." ... data-k="K" ...></span>: the icon is the node itself
        cls, pre, k, post = m.group(1), m.group(2), m.group(3), m.group(4)
        e = ent(k)
        if not e or not e[0] or "style=" in pre + post:
            return m.group(0)
        cls, st = styled(cls, e[0], e[1])
        return '<span class="%s"%s data-k="%s"%s%s></span>' % (cls, pre, k, post, st)

    def child(m):  # <tag ... data-k="K" ...><span class="ico"></span>: the icon is the first child
        e = ent(m.group(2))
        if not e or not e[0]:
            return m.group(0)
        cls, st = styled("ico", e[0], e[1])
        return m.group(1) + '<span class="%s"%s></span>' % (cls, st)

    def brief(m):  # ... data-k="i:ID" ...><span class="brief"></span> on the same line
        e = ent("i:" + m.group(2))
        return m.group(1) + ('<span class="brief">%s</span>' % html.escape(e[2]) if e and e[2] else '<span class="brief"></span>')

    src = re.sub(r'<span class="(ico[^"]*)"([^>]*?) data-k="([^"]+)"([^>]*)></span>', own, src)
    src = re.sub(r'(<[a-z]+\b[^>]*\bdata-k="([^"]+)"[^>]*>)<span class="ico"></span>', child, src)
    src = re.sub(r'(<[a-z]+\b[^>]*\bdata-k="i:(\d+)"[^>]*>(?:(?!data-k=)[^\n])*?)<span class="brief"></span>', brief, src)
blob = json.dumps(keep, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
out_dir = os.path.join(ROOT, "news", slug)
os.makedirs(out_dir, exist_ok=True)
open(os.path.join(out_dir, "index.html"), "w", encoding="utf-8").write(src.replace("/*DATA*/", blob))
extra = sorted(k for k in keep if k not in ("spells", "items"))
print("built news/%s/index.html (%d spells, %d items%s)" % (slug, len(keep["spells"]), len(keep["items"]), (", " + ", ".join(extra)) if extra else ""))
