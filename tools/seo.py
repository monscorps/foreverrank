#!/usr/bin/env python3
"""Search and share metadata for every page, plus sitemap.xml and robots.txt.

  python3 tools/seo.py          # rewrite heads, sitemap.xml, robots.txt
  python3 tools/seo.py --check  # report what would change, write nothing
  python3 tools/seo.py --indexnow  # after a deploy: ping Bing and friends

One table below owns each page's title, description, canonical URL and share
image. The script replaces the <title>, meta description and canonical in
place and swaps a marked block of Open Graph / Twitter / JSON-LD tags. New
page: add a row here, rerun. News articles are dated from news.json.
"""
import html, json, os, re, subprocess, sys, datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = "https://foreverrank.com"
DEFAULT_IMG = "/assets/og.jpg"  # 1200x630 crop of the hero art

PAGES = {
    "/": ("ForeverRank: WoW Forever News, Datamines and Tools",
          "WoW Forever news and beta datamines, plus a talent calculator, a datamined item and spell database, BiS lists, and the character and guild progression ladder for launch.",
          DEFAULT_IMG),
    "/plan/": ("WoW Forever Talent Calculator and Planner · The Forge",
               "WoW Forever talent calculator and character planner: race, class, talents, Legacy trees and gear from the beta client. Share builds as links and compose whole raids.",
               DEFAULT_IMG),
    "/codex/": ("WoW Forever Database: Items, Spells, Legacy · ForeverRank",
                "The WoW Forever database: search over 17,000 datamined items and spells, the Legacy system, item sets, hidden systems and the roadmap, from beta build 1.60.1.70009.",
                DEFAULT_IMG),
    "/classes/": ("WoW Forever Class Changes and Spellbooks · ForeverRank",
                  "WoW Forever class changes by datamine: every class's spellbook and talents, hidden spells, Soul Engraving, and what moved since the BlizzCon demo.",
                  DEFAULT_IMG),
    "/rankings/": ("WoW Forever Spec Rankings (Estimates) · ForeverRank",
                   "WoW Forever spec rankings for PvE and PvP: honest estimates from beta client data and demo footage until the ladder has real parses.",
                   DEFAULT_IMG),
    "/world/": ("WoW Forever Dungeons, Raids and Zones · ForeverRank",
                "WoW Forever zones, dungeons, raids and battlegrounds, announced and datamined, with boss names, level ranges and the full zone Atlas.",
                "/codex/img/hyjal-summit.jpg"),
    "/bis/": ("WoW Forever BiS Lists for Every Class · ForeverRank",
              "WoW Forever best-in-slot gear for every class and spec at the beta's level-20 cap, with sources, crafting mats and datamined tooltips.",
              "/codex/img/excavation-site.jpg"),
    "/news/": ("WoW Forever News and Datamines · ForeverRank",
               "WoW Forever news in one place, newest first: Blizzard posts, fansite coverage and ForeverRank's own beta client datamines.",
               DEFAULT_IMG),
    "/addon/": ("ForeverProbe, the WoW Forever Addon · ForeverRank",
                "ForeverProbe is ForeverRank's WoW Forever addon: a levelling pace bar and character snapshots you export yourself. The download returns soon.",
                DEFAULT_IMG),
}
ARTICLES = ["/news/build-70009/", "/news/hidden-systems/", "/news/era-verdict/",
            "/news/soul-engraving/", "/news/set-rework/"]
NO_CRAWL = ["/tools/", "/worker/", "/probe/", "/addon/companion/"]

BEGIN, END = "<!-- seo:begin -->", "<!-- seo:end -->"


def esc(s):
    return html.escape(s, quote=True)


def page_file(path):
    return os.path.join(ROOT, path.strip("/"), "index.html") if path != "/" else os.path.join(ROOT, "index.html")


def lastmod(f):
    try:
        out = subprocess.check_output(["git", "-C", ROOT, "status", "--porcelain", "--", f]).decode().strip()
        if out:
            return datetime.date.today().isoformat()
        return subprocess.check_output(["git", "-C", ROOT, "log", "-1", "--format=%cs", "--", f]).decode().strip()
    except Exception:
        return datetime.date.today().isoformat()


def article_meta():
    news = json.load(open(os.path.join(ROOT, "news.json")))
    by = {i["l"]: i for i in news["items"] if i.get("s") == "FOREVERRANK"}
    out = {}
    for path in ARTICLES:
        f = page_file(path)
        h = open(f, encoding="utf-8").read()
        title = re.search(r"<title>([^<]*)</title>", h).group(1)
        base = re.sub(r"\s*·.*$", "", title)
        desc = re.search(r'<meta name="description" content="([^"]*)"', h).group(1)
        item = by.get(path, {})
        out[path] = (base + " · WoW Forever · ForeverRank", html.unescape(desc), item.get("img") or DEFAULT_IMG,
                     item.get("d"), html.unescape(base))
    return out


def block(path, title, desc, img, kind, extra=None):
    url = SITE + path
    img_url = SITE + img
    tags = [
        '<meta property="og:type" content="%s">' % kind,
        '<meta property="og:site_name" content="ForeverRank">',
        '<meta property="og:url" content="%s">' % url,
        '<meta property="og:title" content="%s">' % esc(title),
        '<meta property="og:description" content="%s">' % esc(desc),
        '<meta property="og:image" content="%s">' % img_url,
        '<meta name="twitter:card" content="summary_large_image">',
        '<meta name="twitter:title" content="%s">' % esc(title),
        '<meta name="twitter:description" content="%s">' % esc(desc),
        '<meta name="twitter:image" content="%s">' % img_url,
    ]
    if extra:
        tags.append('<script type="application/ld+json">%s</script>' % json.dumps(extra, ensure_ascii=False))
    return BEGIN + "\n" + "\n".join(tags) + "\n" + END


def rewrite(path, title, desc, img, kind, ld):
    f = page_file(path)
    h = open(f, encoding="utf-8").read()
    before = h
    h = re.sub(r"<title>[^<]*</title>", "<title>%s</title>" % esc(title), h, count=1)
    if re.search(r'<meta name="description" content="[^"]*">', h):
        h = re.sub(r'<meta name="description" content="[^"]*">', '<meta name="description" content="%s">' % esc(desc), h, count=1)
    else:
        h = h.replace("</title>", '</title>\n<meta name="description" content="%s">' % esc(desc), 1)
    canon = '<link rel="canonical" href="%s">' % (SITE + path)
    if re.search(r'<link rel="canonical" href="[^"]*">', h):
        h = re.sub(r'<link rel="canonical" href="[^"]*">', canon, h, count=1)
    else:
        h = re.sub(r'(<meta name="description" content="[^"]*">)', r"\1\n" + canon, h, count=1)
    # drop hand-written social tags and any previous generated block
    h = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n?", "", h, flags=re.S)
    h = re.sub(r'[ \t]*<meta (?:property="og:[^"]*"|name="twitter:[^"]*") content="[^"]*">\n?', "", h)
    h = h.replace(canon, canon + "\n" + block(path, title, desc, img, kind, ld), 1)
    return f, before, h


def main(check):
    org = {"@type": "Organization", "name": "ForeverRank", "url": SITE + "/"}
    jobs = []
    for path, (title, desc, img) in PAGES.items():
        ld = None
        if path == "/":
            ld = {"@context": "https://schema.org", "@type": "WebSite", "name": "ForeverRank", "url": SITE + "/",
                  "description": desc, "publisher": org}
        jobs.append((path, title, desc, img, "website", ld))
    for path, (title, desc, img, date, headline) in article_meta().items():
        f = page_file(path)
        ld = {"@context": "https://schema.org", "@type": "NewsArticle", "headline": headline, "description": desc,
              "image": [SITE + img], "mainEntityOfPage": SITE + path, "author": org, "publisher": org}
        if date:
            ld["datePublished"] = date
        ld["dateModified"] = lastmod(f)
        jobs.append((path, title, desc, img, "article", ld))
    changed = 0
    for path, title, desc, img, kind, ld in jobs:
        f, before, after = rewrite(path, title, desc, img, kind, ld)
        if before != after:
            changed += 1
            print("updated" if not check else "would update", path)
            if not check:
                open(f, "w", encoding="utf-8").write(after)
    urls = []
    for path, title, desc, img, kind, ld in jobs:
        pr = "1.0" if path == "/" else ("0.9" if path in ("/plan/", "/codex/", "/bis/") else ("0.6" if kind == "article" else "0.8"))
        urls.append("  <url><loc>%s</loc><lastmod>%s</lastmod><priority>%s</priority></url>" % (SITE + path, lastmod(page_file(path)), pr))
    sitemap = '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + "\n".join(urls) + "\n</urlset>\n"
    robots = "User-agent: *\nAllow: /\n" + "".join("Disallow: %s\n" % p for p in NO_CRAWL) + "\nSitemap: %s/sitemap.xml\n" % SITE
    if not check:
        open(os.path.join(ROOT, "sitemap.xml"), "w").write(sitemap)
        open(os.path.join(ROOT, "robots.txt"), "w").write(robots)
    print("%d pages %s; sitemap has %d urls" % (changed, "to update" if check else "updated", len(urls)))


def indexnow():
    """Tell Bing, Yandex, Seznam and Naver about every sitemap URL (IndexNow).
    The key file <key>.txt sits at the site root; run after a deploy."""
    import glob, urllib.request
    keys = [os.path.basename(k)[:-4] for k in glob.glob(os.path.join(ROOT, "*.txt")) if re.fullmatch(r"[0-9a-f]{32}\.txt", os.path.basename(k))]
    if not keys:
        sys.exit("no IndexNow key file at the site root")
    urls = re.findall(r"<loc>([^<]+)</loc>", open(os.path.join(ROOT, "sitemap.xml")).read())
    body = json.dumps({"host": "foreverrank.com", "key": keys[0], "keyLocation": "%s/%s.txt" % (SITE, keys[0]), "urlList": urls}).encode()
    req = urllib.request.Request("https://api.indexnow.org/indexnow", data=body, headers={"Content-Type": "application/json; charset=utf-8"})
    with urllib.request.urlopen(req, timeout=30) as r:
        print("IndexNow: HTTP %d for %d urls" % (r.status, len(urls)))


if __name__ == "__main__":
    if "--indexnow" in sys.argv:
        indexnow()
    else:
        main("--check" in sys.argv)
