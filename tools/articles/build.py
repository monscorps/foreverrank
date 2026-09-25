#!/usr/bin/env python3
"""Build a data-driven news article: tools/articles/<slug>.src.html plus
<slug>.data.json become news/<slug>/index.html, with only the items and
spells the page references (data-k="i:<id>" or data-k="<spell key>")
inlined for its tooltips. Then run tools/seo.py for the head tags.

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
if missing:
    sys.exit("no data for: " + ", ".join(missing))
blob = json.dumps(keep, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
out_dir = os.path.join(ROOT, "news", slug)
os.makedirs(out_dir, exist_ok=True)
open(os.path.join(out_dir, "index.html"), "w", encoding="utf-8").write(src.replace("/*DATA*/", blob))
print("built news/%s/index.html (%d spells, %d items)" % (slug, len(keep["spells"]), len(keep["items"])))
