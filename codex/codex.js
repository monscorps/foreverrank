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
  // Facts show as short headlines; the full wording lives in one popup per topic.
  var ROWS = {}, TOPICS = {};
  function autoHead(f) {
    var h = String(f).split(/[.:;](\s|$)/)[0];
    return h.length > 46 ? h.slice(0, 44).replace(/\s+\S*$/, "") + "\u2026" : h;
  }
  function heads(list, key) {
    return (list || []).map(function (f, i) { var r = (ROWS[key] || [])[i]; return r && r[0] ? r[0] : autoHead(f); });
  }
  function topic(key, title, icon, list) { TOPICS[key] = { title: title, icon: icon, list: list || [] }; }
  function headList(list, key, title, icon) {
    topic(key, title, icon, list);
    return '<ul class="facts heads">' + heads(list, key).map(function (h) { return "<li>" + esc(h) + "</li>"; }).join("") + "</ul>" +
      '<button type="button" class="cx-more" data-topic="' + esc(key) + '">All details</button>';
  }
  function openTopic(key) {
    var t = TOPICS[key]; if (!t) return;
    var m = document.getElementById("cxmodal");
    if (!m) {
      m = document.createElement("div"); m.id = "cxmodal"; m.className = "cxmodal"; m.hidden = true;
      m.innerHTML = '<div class="cxm-card" role="dialog" aria-modal="true" aria-labelledby="cxm-title" tabindex="-1"><button type="button" class="cxm-x" aria-label="Close">&times;</button><div class="cxm-body"></div></div>';
      document.body.appendChild(m);
      var shut = function () {
        if (m.hidden) return;
        m.hidden = true;
        if (m._prev && m._prev.focus) m._prev.focus();
      };
      m.addEventListener("click", function (e) { if (e.target === m || e.target.closest(".cxm-x")) shut(); });
      document.addEventListener("keydown", function (e) {
        if (m.hidden) return;
        if (e.key === "Escape") { shut(); return; }
        if (e.key !== "Tab") return;
        var f = m.querySelectorAll(".cxm-card, .cxm-x"), card = f[0], x = f[1];
        if (e.shiftKey && (document.activeElement === card || document.activeElement === x)) { e.preventDefault(); (document.activeElement === x ? card : x).focus(); }
        else if (!e.shiftKey && (document.activeElement === x || !m.contains(document.activeElement))) { e.preventDefault(); card.focus(); }
      });
    }
    if (m.hidden) m._prev = document.activeElement;
    var hs = heads(t.list, key);
    m.querySelector(".cxm-body").innerHTML = '<div class="cxm-head">' + img(t.icon || "inv_misc_book_09") + "<b id=\"cxm-title\">" + esc(t.title) + "</b></div>" +
      '<ol class="cxm-list">' + t.list.map(function (f, i) { return "<li><b>" + esc(hs[i]) + "</b><p>" + esc(f) + "</p></li>"; }).join("") + "</ol>";
    m.hidden = false;
    m.querySelector(".cxm-card").scrollTop = 0;
    m.querySelector(".cxm-card").focus();
  }

  // ---- Database search: Forever items (../plan/items.json) plus this page's places, perks, spells and systems ----
  var CATS = [["all", "All"], ["weapon", "Weapons"], ["armor", "Armor"], ["accessory", "Accessories"], ["offhand", "Off-hands and relics"],
    ["consumable", "Consumables"], ["recipe", "Recipes"], ["pvp", "PvP"], ["misc", "Misc"], ["place", "Places"], ["perk", "Legacy perks"],
    ["spell", "Spells"], ["system", "Systems"]];
  var SUBFIRST = ["Cloth", "Leather", "Mail", "Plate", "Shield", "Neck", "Ring", "Trinket", "Cloak", "Alchemy", "Cooking", "First Aid", "Zone", "Dungeon", "Raid", "Battleground"];
  var QUAL = ["poor", "common", "uncommon", "rare", "epic", "legendary"];
  var IDX = [], GK = null, SQ = { q: "", cat: "all", sub: "", qual: "" }, SHOWN = 60;
  function slotName(sl) {
    return { "main-hand": "Main Hand", "off-hand": "Off Hand", "one-hand": "One-Hand", "two-hand": "Two-Hand", head: "Head", neck: "Neck", shoulder: "Shoulder",
      back: "Back", chest: "Chest", wrist: "Wrist", hands: "Hands", waist: "Waist", legs: "Legs", feet: "Feet", finger: "Finger", trinket: "Trinket",
      ranged: "Ranged", relic: "Relic", thrown: "Thrown", tabard: "Tabard", shirt: "Shirt" }[sl] || "";
  }
  function buildIndex(d, items) {
    (items || []).forEach(function (it) {
      var meta = [it.sub, slotName(it.slot), it.reqLevel ? "Level " + it.reqLevel : ""].filter(function (x, i, a) { return x && a.indexOf(x) === i; });
      IDX.push({ kind: "item", cat: it.cat || "misc", sub: it.sub || "Other", name: it.name, icon: it.icon, q: it.quality || "unknown", it: it, meta: meta.join(" \u00b7 "), side: it.source,
        text: [it.name, it.sub, it.type, slotName(it.slot), it.source, it.setName, (it.effects || []).join(" ")].join(" ").toLowerCase() });
    });
    var w = d.world;
    [["zones", "Zone"], ["dungeons", "Dungeon"], ["raids", "Raid"], ["battlegrounds", "Battleground"]].forEach(function (g) {
      (w[g[0]] || []).forEach(function (x) {
        IDX.push({ kind: "page", cat: "place", sub: g[1], name: x[0], icon: x[2], meta: g[1] + (x[3] ? " \u00b7 " + (/^\d/.test(x[3]) && g[1] !== "Raid" && g[1] !== "Battleground" ? "Levels " : "") + x[3] : ""),
          href: "#world", text: (x[0] + " " + g[1] + " " + x[1]).toLowerCase() });
      });
    });
    d.legacy.trees.forEach(function (t) {
      t.perks.forEach(function (pk) {
        IDX.push({ kind: "page", cat: "perk", sub: t.name, name: pk[0], icon: pk[3], meta: t.name + " \u00b7 " + pk[1] + (pk[1] === 1 ? " rank" : " ranks"), href: "#legacy", text: (pk[0] + " " + t.name + " " + pk[2]).toLowerCase() });
      });
    });
    [["new", "New spell"], ["granted", "Granted by a talent"], ["higher", "Above demo level"], ["confirmed", "Confirmed since"]].forEach(function (b) {
      (d.unseen[b[0]] || []).forEach(function (x) {
        IDX.push({ kind: "page", cat: "spell", sub: x[0], name: x[1], icon: x[3], meta: x[0] + " \u00b7 " + b[1], href: "#unseen", text: (x[1] + " " + x[0] + " " + x[2]).toLowerCase() });
      });
    });
    (d.systems || []).forEach(function (sy, i) {
      IDX.push({ kind: "page", cat: "system", sub: "System", name: sy.t, icon: sy.icon, meta: (sy.facts || []).length + " facts", topic: "systems:" + i, text: (sy.t + " " + (sy.facts || []).join(" ")).toLowerCase() });
    });
  }
  function matches() {
    var words = SQ.q.toLowerCase().split(/\s+/).filter(Boolean);
    return IDX.filter(function (e) {
      if (SQ.cat !== "all" && e.cat !== SQ.cat) return false;
      if (SQ.sub && e.sub !== SQ.sub) return false;
      if (SQ.qual && e.q !== SQ.qual) return false;
      for (var i = 0; i < words.length; i++) if (e.text.indexOf(words[i]) === -1) return false;
      return true;
    }).sort(function (a, b) {
      var ql = SQ.q.toLowerCase(), as = ql && a.name.toLowerCase().indexOf(ql) === 0 ? 0 : 1, bs = ql && b.name.toLowerCase().indexOf(ql) === 0 ? 0 : 1;
      if (as !== bs) return as - bs;
      var aq = QUAL.indexOf(a.q), bq = QUAL.indexOf(b.q);
      if (aq !== bq) return bq - aq;
      return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
    });
  }
  function drawSearch() {
    var box = document.getElementById("dbs");
    if (!box) return;
    var active = SQ.q.trim() || SQ.cat !== "all";
    var pool = IDX.filter(function (e) { return SQ.cat === "all" || e.cat === SQ.cat; });
    var subs = [];
    pool.forEach(function (e) { if (SQ.cat !== "all" && subs.indexOf(e.sub) === -1) subs.push(e.sub); });
    subs.sort(function (a, b) {
      var ai = SUBFIRST.indexOf(a), bi = SUBFIRST.indexOf(b);
      if (ai !== -1 || bi !== -1) return (ai === -1 ? 99 : ai) - (bi === -1 ? 99 : bi);
      return /^Unknown|^Other/.test(a) ? 1 : /^Unknown|^Other/.test(b) ? -1 : a < b ? -1 : 1;
    });
    var quals = QUAL.filter(function (q) { return pool.some(function (e) { return e.q === q; }); });
    document.getElementById("dbs-cats").innerHTML = CATS.map(function (c) {
      var n = c[0] === "all" ? IDX.length : IDX.filter(function (e) { return e.cat === c[0]; }).length;
      return n ? '<button type="button" data-dbcat="' + c[0] + '"' + (SQ.cat === c[0] ? ' class="on"' : "") + ">" + esc(c[1]) + "<i>" + n + "</i></button>" : "";
    }).join("");
    var sr = document.getElementById("dbs-subs");
    sr.hidden = !(subs.length > 1 || (quals.length > 1 && active));
    sr.innerHTML = (subs.length > 1 ? subs.map(function (x) { return '<button type="button" data-dbsub="' + esc(x) + '"' + (SQ.sub === x ? ' class="on"' : "") + ">" + esc(x) + "</button>"; }).join("") : "") +
      (quals.length > 1 ? '<span class="dbs-q">' + quals.map(function (q) { return '<button type="button" class="q-' + q + (SQ.qual === q ? " on" : "") + '" data-dbqual="' + q + '">' + q + "</button>"; }).join("") + "</span>" : "");
    if (window.TipKit) TipKit.hide();
    var out = document.getElementById("dbs-out"), res = active ? matches() : [];
    document.getElementById("dbs-n").textContent = active ? res.length + (res.length === 1 ? " result" : " results") : IDX.length + " entries";
    out.hidden = !active;
    if (!active) return;
    out.innerHTML = res.length ? res.slice(0, SHOWN).map(function (e) {
      var i = IDX.indexOf(e);
      return '<button type="button" class="dbs-row' + (e.kind === "item" ? " q-" + esc(e.q) : "") + '" data-dbi="' + i + '"' + (e.kind === "item" ? ' data-tipkit="1"' : "") + ">" +
        '<span class="dbs-ic">' + img(e.icon || "inv_misc_questionmark") + "</span>" +
        '<span class="dbs-t"><b>' + esc(e.name) + "</b><em>" + esc(e.meta) + "</em></span>" +
        '<span class="dbs-s">' + esc(e.kind === "item" ? e.side : ({ place: "The new world", perk: "The Legacy system", spell: "Spells", system: "Systems" }[e.cat] || "")) + "</span></button>";
    }).join("") + (res.length > SHOWN ? '<button type="button" class="dbs-more" data-dbmore="1">Show all ' + res.length + "</button>" : "")
      : '<p class="dbs-none">Nothing matches yet. Forever has shown only so much; the beta adds the rest.</p>';
    if (window.TipKit && GK) out.querySelectorAll(".dbs-row[data-tipkit]").forEach(function (row) {
      TipKit.hover(row, function (el) { return GK.itemTip(IDX[+el.getAttribute("data-dbi")].it); }, function () { return "itemtip"; });
    });
  }
  function syncUrl() {
    try {
      var u = new URL(location.href);
      ["q", "cat", "sub", "qual"].forEach(function (k) { var v = k === "q" ? SQ.q.trim() : SQ[k]; if (v && v !== "all") u.searchParams.set(k, v); else u.searchParams.delete(k); });
      history.replaceState(null, "", u.pathname + u.search + u.hash);
    } catch (e) {}
  }
  function initSearch() {
    var box = document.getElementById("dbs");
    if (!box) return;
    box.innerHTML = '<div class="dbs-bar"><input type="search" id="dbs-qi" placeholder="Search items, dungeons, perks, spells" autocomplete="off" spellcheck="false" aria-label="Search the Database">' +
      '<span id="dbs-n"></span></div><div class="dbs-cats" id="dbs-cats" role="group" aria-label="Type"></div><div class="dbs-subs" id="dbs-subs" hidden></div><div class="dbs-out" id="dbs-out" hidden></div>';
    try {
      var sp = new URLSearchParams(location.search);
      SQ.q = sp.get("q") || ""; SQ.cat = sp.get("cat") || "all"; SQ.sub = sp.get("sub") || ""; SQ.qual = sp.get("qual") || "";
    } catch (e) {}
    var qi = document.getElementById("dbs-qi"), tmr = null;
    qi.value = SQ.q;
    qi.addEventListener("input", function () {
      clearTimeout(tmr);
      tmr = setTimeout(function () { SQ.q = qi.value; SHOWN = 60; drawSearch(); syncUrl(); }, 120);
    });
    box.addEventListener("click", function (e) {
      var b = e.target.closest && e.target.closest("button");
      if (!b || !box.contains(b)) return;
      if (b.hasAttribute("data-dbcat")) { var c = b.getAttribute("data-dbcat"); SQ.cat = SQ.cat === c && c !== "all" ? "all" : c; SQ.sub = ""; SQ.qual = ""; SHOWN = 60; }
      else if (b.hasAttribute("data-dbsub")) { var s2 = b.getAttribute("data-dbsub"); SQ.sub = SQ.sub === s2 ? "" : s2; }
      else if (b.hasAttribute("data-dbqual")) { var q2 = b.getAttribute("data-dbqual"); SQ.qual = SQ.qual === q2 ? "" : q2; }
      else if (b.hasAttribute("data-dbmore")) { SHOWN = 1e9; }
      else if (b.hasAttribute("data-dbi")) {
        var en = IDX[+b.getAttribute("data-dbi")];
        if (en.kind === "item") {
          if (window.TipKit && GK && (TipKit.touchy() || e.detail === 0)) TipKit.openSheet(GK.itemTip(en.it), [], { cls: "itemtip", owner: "db:" + en.name });
          return;
        }
        if (en.topic) { openTopic(en.topic); return; }
        var target = null;
        document.querySelectorAll(en.href + " [data-name]").forEach(function (el) { if (!target && el.getAttribute("data-name") === en.name) target = el; });
        if (target) {
          target.scrollIntoView({ behavior: "smooth", block: "center" });
          target.classList.remove("dbs-flash"); void target.offsetWidth; target.classList.add("dbs-flash");
        } else {
          var sec = document.querySelector(en.href);
          if (sec) sec.scrollIntoView({ behavior: "smooth", block: "start" });
        }
        return;
      } else return;
      drawSearch(); syncUrl();
    });
    drawSearch();
  }

  fetch("codex.json", { cache: "no-store" }).then(function (r) { return r.json(); }).then(function (d) {
    ROWS = d.rows || {};
    var out = [], nav = [];
    function section(id, title, html) {
      nav.push('<a href="#' + id + '">' + title + "</a>");
      out.push('<section id="' + id + '"><h2>' + title + "</h2>" + html + "</section>");
    }

    // Legacy: the shared in-game window (legacy.js), with facts on top and ?lg= sharing.
    var lg = d.legacy, LW = null;
    function drawLegacy() {
      if (!LW) LW = LegacyWindow(lg, {
        root: document.getElementById("legacy-win"), code: new URLSearchParams(location.search).get("lg"),
        full: true, share: true,
        onApply: function (code) {
          try {
            var u = new URL(location.href);
            if (code) u.searchParams.set("lg", code); else u.searchParams.delete("lg");
            history.replaceState(null, "", u.pathname + u.search + (code ? "#legacy" : u.hash));
          } catch (e) {}
        }
      });
      LW.draw();
    }
    section("legacy", "The Legacy system", headList(lg.facts, "legacy", "The Legacy system", "inv_misc_book_07") + '<div id="legacy-win"></div>');

    // Unseen spells
    var un = d.unseen;
    function sprows(list, withIcon) {
      return '<div class="spellrows">' + list.map(function (r) {
        return '<div class="sprow" data-name="' + esc(r[1]) + '">' + img(withIcon ? (r[3] || "inv_misc_questionmark") : "inv_misc_questionmark") +
          '<b style="color:' + (CLASS_COLOUR[r[0]] || "#fff") + '">' + esc(r[1]) + '</b><span class="cls">' + esc(r[0]) +
          '</span><span class="why">' + esc(r[2]) + "</span></div>";
      }).join("") + "</div>";
    }
    section("unseen", "Spells the tooltips admit to", "<p class=\"board-sub\">" + esc(un.note) + "</p>" +
      "<h3>Genuinely new spells</h3>" + sprows(un.new, true) +
      (un.confirmed && un.confirmed.length ? "<h3>Confirmed in the demo spellbook since</h3>" + sprows(un.confirmed, true) : "") +
      "<h3>Granted by talents (already in the trees)</h3>" + sprows(un.granted || [], true) +
      "<h3>Classic spells above the demo's level</h3>" + sprows(un.higher, true));

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
        return '<div class="place' + (r[4] ? " hasimg" : "") + '" data-name="' + esc(r[0]) + '">' + shot + img(r[2] || "inv_misc_map_01") +
          (r[4] ? "" : '<div class="place-t"><b>' + esc(r[0]) + "</b>" +
            (r[3] ? '<span class="lvlchip">' + esc(r[3]) + "</span>" : "") + "</div>") +
          '<p>' + esc(r[1] || "") + "</p></div>";
      }).join("") + "</div>";
    }
    section("world", "The new world",
      (w.facts ? headList(w.facts, "world", "The new world", "inv_misc_map_01") : "") +
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
      var hero = '<p class="rm-years">2026 | 2027</p>' +
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

    var sysHtml = '<div class="systiles">' + d.systems.map(function (sys, i) {
      topic("systems:" + i, sys.t, sys.icon, sys.facts);
      return '<button type="button" class="systile" id="sys' + i + '" data-topic="systems:' + i + '">' + img(sys.icon || "inv_misc_book_09") +
        "<b>" + esc(sys.t) + "</b><span>" + sys.facts.length + " facts</span></button>";
    }).join("") + "</div>";
    section("systems", "Systems", sysHtml);

    // Hero stat band: the Codex counts itself.
    var nDun = w.dungeons.length, nRaid = w.raids.length,
      nPerk = d.legacy.trees.reduce(function (a, t) { return a + t.perks.length; }, 0),
      nCC = Object.keys(d.classChanges).reduce(function (a, k) { return a + d.classChanges[k].length; }, 0),
      nSpell = (d.unseen.new || []).length + (d.unseen.granted || []).length + (d.unseen.higher || []).length;
    var hero = '<div class="cxstats">' +
      [[nPerk, "Legacy perks", "legacy", "legacy"], [nDun, "new dungeons", "world", "dungeons"], [nRaid, "raids", "world", "raids"],
        [nCC, "class changes", "classes", "classes"], [nSpell, "spells foretold", "unseen", "spells"]]
        .map(function (s) {
          return '<a class="cxstat" href="#' + s[2] + '" style="--img:url(img/stat-' + s[3] + '.jpg)"><span class="cxstat-box"><b>' + s[0] + "</b><span>" + s[1] + "</span></span></a>";
        }).join("") + "</div>";

    document.getElementById("cxnav").innerHTML = nav.join("");
    var cxEl = document.getElementById("cx");
    cxEl.innerHTML = hero + out.join("");
    cxEl.addEventListener("click", function (e) {
      var t = e.target.closest && e.target.closest("[data-topic]");
      if (t) openTopic(t.getAttribute("data-topic"));
    });
    drawLegacy();
    fetch("../plan/items.json", { cache: "no-store" }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; }).then(function (it) {
      var items = it && Array.isArray(it.items) ? it.items : [];
      if (window.ForgeGear && items.length) { try { GK = ForgeGear({ items: it, get: function () { return {}; } }); } catch (e) { GK = null; } }
      buildIndex(d, items);
      initSearch();
    });
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
