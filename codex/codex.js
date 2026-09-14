/* The Codex: renders codex.json. Icons hotlinked like everywhere else. */
(function () {
  "use strict";
  var CDN = "https://wow.zamimg.com/images/wow/icons/large/";
  var CLASS_COLOUR = { Warrior: "#c79c6e", Paladin: "#f58cba", Hunter: "#abd473", Rogue: "#fff569",
    Priest: "#ffffff", Shaman: "#0070de", Mage: "#69ccf0", Warlock: "#9482c9", Druid: "#ff7d0a" };
  function esc(s) { return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
  function img(n) {
    return '<img src="' + CDN + n + '.jpg" alt="" loading="lazy" onerror="this.onerror=null;this.src=\'' + CDN + 'inv_misc_questionmark.jpg\'">';
  }
  function facts(list) {
    return '<ul class="facts">' + list.map(function (f) { return "<li>" + esc(f) + "</li>"; }).join("") + "</ul>";
  }

  fetch("codex.json", { cache: "no-store" }).then(function (r) { return r.json(); }).then(function (d) {
    var out = [], nav = [];
    function section(id, title, html) {
      nav.push('<a href="#' + id + '">' + title + "</a>");
      out.push('<section id="' + id + '"><h2>' + title + "</h2>" + html + "</section>");
    }

    // Legacy: not a list, a CALCULATOR. 16 points, spend them, share the link.
    var lg = d.legacy;
    var BUDGET = 16;
    var LG = lg.trees.map(function (t) { return (t.perks || []).map(function () { return 0; }); });
    (function () {
      var p = new URLSearchParams(location.search).get("lg");
      if (!p) return;
      p.split("-").forEach(function (seg, ti) {
        for (var i = 0; i < seg.length; i++) if (LG[ti]) LG[ti][i] = +seg[i] || 0;
      });
    })();
    function lgSpent() { return LG.reduce(function (a, t) { return a + t.reduce(function (x, y) { return x + y; }, 0); }, 0); }
    function lgURL() {
      var code = LG.map(function (t) { return t.join(""); }).join("-");
      history.replaceState(null, "", lgSpent() ? "?lg=" + code + "#legacy" : location.pathname + "#legacy");
    }
    function legacyHTML() {
      var left = BUDGET - lgSpent();
      return '<div class="talenthead"><h3>Spend your 16</h3><span class="pts' + (left === 0 ? " alldone" : "") + '">' +
        (left === 0 ? "All 16 placed" : left + " points left") + "</span>" +
        '<button type="button" class="share" id="lg-share">Share legacy build</button>' +
        '<button type="button" class="share" id="lg-reset">Reset</button></div>' +
        '<div class="lgtrees">' +
        lg.trees.map(function (t, ti) {
          var pts = LG[ti].reduce(function (a, b) { return a + b; }, 0);
          var slots = (t.perks || []).map(function (p, i) {
            var r = LG[ti][i] || 0;
            return '<div class="lslot' + (r >= p[1] ? " maxed" : r > 0 ? " part" : "") + '" data-lg="' + ti + ":" + i + '" ' +
              'data-tip="' + esc(p[0]) + "|Rank " + r + "/" + p[1] + "|" + esc(p[2]) + '">' +
              img(p[3] || "inv_misc_questionmark") + '<span class="l-rank">' + r + "/" + p[1] + "</span></div>";
          }).join("");
          if (t.name === "Professions")
            slots += '<div class="lslot locked" data-tip="Placeholder||To be added in future patch content."></div>' +
                     '<div class="lslot locked" data-tip="Placeholder||To be added in future patch content."></div>';
          return '<div class="lgtree"><div class="lg-head">' + img(t.icon) + "<b>" + esc(t.name) +
            '</b><u>' + pts + "</u></div><div class=\"lg-grid\">" + slots + "</div></div>";
        }).join("") + "</div>" +
        '<p class="board-sub">Left click adds a point, right click removes. Hover a perk for the tooltip. ' + esc(lg.treeNote) +
        " In game the trees are tiered like talent trees, with some perks locked behind earlier choices; the demo footage never showed which perk sits in which tier, so this calculator leaves every perk open until the beta client settles the layout.</p>";
    }
    var lgTip = null;
    function lgTipShow(slot, x, y) {
      var parts = (slot.getAttribute("data-tip") || "").split("|");
      if (!lgTip) { lgTip = document.createElement("div"); lgTip.className = "tip"; document.body.appendChild(lgTip); }
      lgTip.innerHTML = "<b>" + parts[0] + "</b>" + (parts[1] ? '<u>' + parts[1] + "</u>" : "") + "<p>" + (parts[2] || "") + "</p>";
      lgTip.style.display = "block";
      var w = lgTip.offsetWidth, h = lgTip.offsetHeight;
      lgTip.style.left = Math.min(x + 14, window.innerWidth - w - 8) + "px";
      lgTip.style.top = Math.max(8, Math.min(y + 14, window.innerHeight - h - 8)) + "px";
    }
    function lgTipHide() { if (lgTip) lgTip.style.display = "none"; }
    function drawLegacy() {
      var el = document.getElementById("legacy");
      lgTipHide();
      el.innerHTML = "<h2>The Legacy system</h2>" + facts(lg.facts) + legacyHTML();
      lgURL();
      el.querySelectorAll(".lslot").forEach(function (s) {
        s.addEventListener("mousemove", function (e) { lgTipShow(s, e.clientX, e.clientY); });
        s.addEventListener("mouseleave", lgTipHide);
      });
      el.querySelectorAll(".lslot:not(.locked)").forEach(function (card) {
        var pr = card.getAttribute("data-lg").split(":"), ti = +pr[0], i = +pr[1];
        card.addEventListener("click", function () {
          if (lgSpent() >= BUDGET) return;
          LG[ti][i] = Math.min(lg.trees[ti].perks[i][1], (LG[ti][i] || 0) + 1);
          drawLegacy();
        });
        card.addEventListener("contextmenu", function (e) {
          e.preventDefault();
          if ((LG[ti][i] || 0) > 0) { LG[ti][i]--; drawLegacy(); }
        });
      });
      var sh = document.getElementById("lg-share");
      if (sh) sh.addEventListener("click", function () {
        var url = location.href;
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(url).then(function () {
            sh.textContent = "Link copied"; setTimeout(function () { sh.textContent = "Share legacy build"; }, 1600);
          });
        } else prompt("Copy this:", url);
      });
      var rs = document.getElementById("lg-reset");
      if (rs) rs.addEventListener("click", function () {
        LG = lg.trees.map(function (t) { return (t.perks || []).map(function () { return 0; }); });
        drawLegacy();
      });
    }
    section("legacy", "The Legacy system", "");

    // Unseen spells
    var un = d.unseen;
    function sprows(list, withIcon) {
      return '<div class="spellrows">' + list.map(function (r) {
        return '<div class="sprow">' + img(withIcon ? (r[3] || "inv_misc_questionmark") : "inv_misc_questionmark") +
          '<b style="color:' + (CLASS_COLOUR[r[0]] || "#fff") + '">' + esc(r[1]) + '</b><span class="cls">' + esc(r[0]) +
          '</span><span class="why">' + esc(r[2]) + "</span></div>";
      }).join("") + "</div>";
    }
    section("unseen", "Spells the tooltips admit to", "<p class=\"board-sub\">" + esc(un.note) + "</p>" +
      "<h3>Genuinely new spells</h3>" + sprows(un.new, true) +
      "<h3>Granted by talents (already in the trees)</h3>" + sprows(un.granted || [], true) +
      "<h3>Classic spells above the demo's level</h3>" + sprows(un.higher, false));

    // Class changes
    var cc = d.classChanges;
    var ccHtml = Object.keys(cc).map(function (k) {
      return "<details><summary style=\"color:" + (CLASS_COLOUR[k] || "#fff") + '">' +
        '<img class="clsico" src="https://wow.zamimg.com/images/wow/icons/large/classicon_' + k.toLowerCase() + '.jpg" alt="">' +
        esc(k) + " <i>" + cc[k].length + " changes seen</i></summary>" +
        cc[k].map(function (a) {
          return '<div class="abil">' + img(a[2] || "inv_misc_questionmark") + "<div><b>" + esc(a[0]) + "</b><p>" + esc(a[1]) + "</p></div></div>";
        }).join("") + "</details>";
    }).join("");
    section("classes", "Class changes, as seen in the demo", ccHtml);

    // World: cards, not tables.
    var w = d.world;
    function placecards(rows) {
      return '<div class="placecards">' + rows.map(function (r) {
        var shot = r[4] ? '<div class="place-shot"><img src="' + esc(r[4]) + '" alt="" loading="lazy">' +
          '<span class="place-name">' + esc(r[0]) + "</span>" +
          (r[3] ? '<span class="lvlchip">' + esc(r[3]) + "</span>" : "") + "</div>" : "";
        return '<div class="place' + (r[4] ? " hasimg" : "") + '">' + shot + img(r[2] || "inv_misc_map_01") +
          (r[4] ? "" : '<div class="place-t"><b>' + esc(r[0]) + "</b>" +
            (r[3] ? '<span class="lvlchip">' + esc(r[3]) + "</span>" : "") + "</div>") +
          '<p>' + esc(r[1] || "") + "</p></div>";
      }).join("") + "</div>";
    }
    section("world", "The new world",
      (w.facts ? facts(w.facts) : "") +
      "<h3>Zones</h3>" + placecards(w.zones) + "<h3>Dungeons</h3>" + placecards(w.dungeons) +
      "<h3>Raids</h3>" + placecards(w.raids) + "<h3>Battlegrounds</h3>" + placecards(w.battlegrounds));

    // Systems: one card each, icon in the header.
    // Roadmap: seasons, icons, a live pulse and a progress bar.
    if (d.roadmap) {
      var now = Date.now();
      var META = {
        "Beta": { on: "2026-09-17", icon: "inv_scroll_11", season: "Autumn 2026" },
        "Name reservation": { on: "2026-10-27", icon: "inv_scroll_02", season: "Autumn 2026" },
        "Launch": { on: "2026-11-04", icon: "inv_misc_rune_01", season: "Autumn 2026", featured: true },
        "Raids unlock": { on: "2026-12-09", icon: "inv_misc_head_dragon_01", season: "Winter 2026" },
        "Hardcore": { on: "2026-12-21", icon: "inv_misc_bone_humanskull_01", season: "Winter 2026", featured: true },
        "First major update": { on: "2027-04-01", icon: "spell_nature_naturetouchgrow", season: "Spring 2027" },
        "Second major update": { on: "2027-07-01", icon: "spell_fire_fire", season: "Summer 2027" }
      };
      var passed = 0, nextIdx = -1;
      d.roadmap.forEach(function (m, i) {
        var t = Date.parse((META[m.title] || {}).on || 0);
        if (t <= now) passed++;
        else if (nextIdx === -1) nextIdx = i;
      });
      var nextM = nextIdx >= 0 ? d.roadmap[nextIdx] : null;
      var launchDays = Math.max(0, Math.floor((Date.parse("2026-11-04T23:00:00Z") - now) / 86400000));
      var hero = '<p class="rm-years">2026–2027</p>' +
        '<p class="rm-intro">The official year-one plan, beat by beat, as Blizzard laid it out at BlizzCon.</p>' +
        (nextM ? '<p class="rm-now"><span class="rm-pulse"></span>Next: <b>' + esc(nextM.title) + "</b>, " + esc(nextM.when) + "." +
          (launchDays > 0 ? " Launch is <b>" + launchDays + " days</b> away." : "") + "</p>" : "") +
        '<div class="rm-progress"><span style="width:' + Math.round(passed / d.roadmap.length * 100) + '%"></span></div>' +
        '<p class="rm-count">' + passed + " of " + d.roadmap.length + " milestones passed</p>" +
        '<div class="rm-stills">' +
        ["img/city-of-dalaran.jpg", "img/hyjal-summit.jpg", "img/the-drowned-city.jpg", "img/shaper-s-terrace.jpg"].map(function (u) {
          return '<img src="' + u + '" alt="" loading="lazy">';
        }).join("") + "</div>";
      var seasons = [], byS = {};
      d.roadmap.forEach(function (m) {
        var sn = (META[m.title] || {}).season || "Later";
        if (!byS[sn]) { byS[sn] = []; seasons.push(sn); }
        byS[sn].push(m);
      });
      var body = seasons.map(function (sn) {
        return '<div class="rm-season"><div class="rm-season-head"><b>' + esc(sn.split(" ")[0]) +
          '</b><span>' + esc(sn.split(" ")[1]) + "</span></div><div class=\"rm-marks\">" +
          byS[sn].map(function (m) {
            var mt = META[m.title] || {}, i = d.roadmap.indexOf(m);
            var t = Date.parse(mt.on || 0), state = t <= now ? " past" : i === nextIdx ? " next" : "";
            return '<div class="rm' + state + (mt.featured ? " featured" : "") + '">' +
              '<div class="rm-dot"></div><div class="rm-body"><div class="rm-mark-head">' + img(mt.icon || "inv_misc_questionmark") +
              '<div><span class="rm-when">' + esc(m.when) + (i === nextIdx ? '<em class="rm-next">next</em>' : "") +
              "</span><b>" + esc(m.title) + "</b></div></div>" +
              '<ul>' + m.items.map(function (x) { return "<li>" + esc(x) + "</li>"; }).join("") + "</ul></div></div>";
          }).join("") + "</div></div>";
      }).join("");
      section("roadmap", "Roadmap", hero + '<div class="rmap">' + body +
        '</div><p class="board-sub">Content and timing per Blizzard’s published plan; all of it subject to change.</p>');
    }

    var sysHtml = '<div class="syscards">' + d.systems.map(function (sys, i) {
      return '<div class="syscard" id="sys' + i + '"><div class="sys-head">' + img(sys.icon || "inv_misc_book_09") +
        "<b>" + esc(sys.t) + "</b></div>" + facts(sys.facts) + "</div>";
    }).join("") + "</div>";
    section("systems", "Systems", sysHtml);

    // Hero stat band: the Codex counts itself.
    var nDun = w.dungeons.length, nRaid = w.raids.length,
      nPerk = d.legacy.trees.reduce(function (a, t) { return a + t.perks.length; }, 0),
      nCC = Object.keys(d.classChanges).reduce(function (a, k) { return a + d.classChanges[k].length; }, 0),
      nSpell = (d.unseen.new || []).length + (d.unseen.granted || []).length + (d.unseen.higher || []).length;
    var hero = '<div class="cxstats">' +
      [[nPerk, "Legacy perks"], [nDun, "new dungeons"], [nRaid, "raids"], [nCC, "class changes"], [nSpell, "spells foretold"]]
        .map(function (s) { return '<div class="cxstat"><b>' + s[0] + "</b><span>" + s[1] + "</span></div>"; }).join("") + "</div>";

    document.getElementById("cxnav").innerHTML = nav.join("");
    document.getElementById("cx").innerHTML = hero + out.join("");
    drawLegacy();
    // Scrollspy: the nav knows where you are.
    var links = document.querySelectorAll(".cxnav a");
    var obs = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (!en.isIntersecting) return;
        links.forEach(function (a) { a.classList.toggle("on", a.getAttribute("href") === "#" + en.target.id); });
      });
    }, { rootMargin: "-20% 0px -70% 0px" });
    document.querySelectorAll(".cx section").forEach(function (sec) { obs.observe(sec); });
  }).catch(function (e) {
    document.getElementById("cx").innerHTML = "<p>The Database failed to load. Refresh; the scribes are embarrassed.</p>";
  });
})();
