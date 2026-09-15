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

    // Legacy: the shared in-game window (legacy.js), with facts on top and ?lg= sharing.
    var lg = d.legacy, LW = null;
    function drawLegacy() {
      if (!LW) LW = LegacyWindow(lg, {
        root: document.getElementById("legacy"), code: new URLSearchParams(location.search).get("lg"),
        full: true, share: true, header: "<h2>The Legacy system</h2>" + facts(lg.facts),
        onApply: function (code) { history.replaceState(null, "", code ? "?lg=" + code + "#legacy" : location.pathname + location.hash); }
      });
      LW.draw();
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
      (un.confirmed && un.confirmed.length ? "<h3>Confirmed in the demo spellbook since</h3>" + sprows(un.confirmed, true) : "") +
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
        '<a class="rm-slide" href="img/roadmap-slide.jpg" target="_blank" rel="noopener">' +
        '<img src="img/roadmap-slide.jpg" alt="The official Forever roadmap slide" loading="lazy"></a>';
      var seasons = [], byS = {};
      d.roadmap.forEach(function (m) {
        var sn = (META[m.title] || {}).season || "Later";
        if (!byS[sn]) { byS[sn] = []; seasons.push(sn); }
        byS[sn].push(m);
      });
      var SICON = { "Autumn": "inv_misc_herb_04", "Winter": "inv_ammo_snowball", "Spring": "inv_misc_flower_02", "Summer": "inv_summerfest_firespirit" };
      var body = seasons.map(function (sn) {
        var sw = sn.split(" ");
        return '<div class="rm-season"><div class="rm-season-head">' + img(SICON[sw[0]] || "inv_misc_map_01") +
          "<b>" + esc(sw[0]) + '</b><span>' + esc(sw[1]) + "</span></div><div class=\"rm-marks\">" +
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
        '</div><p class="board-sub">Off the official slide: more news beyond this roadmap to be shared, features will evolve based on player feedback, content and timing subject to change.</p>');
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
