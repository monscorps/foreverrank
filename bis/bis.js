/* The BiS page: renders bis.json (slot rankings compiled from ForeverChanges,
 * credited on the page) with tooltips from our item database, drawn by the
 * shared tooltip in plan/gear.js; bis-items.json fills pieces it lacks.
 * Deep links: /bis/?c=priest&s=holy#slot-legs */
(function () {
  "use strict";
  var CDN = "https://wow.zamimg.com/images/wow/icons/large/";
  var CLASSNAMES = { warrior: "Warrior", hunter: "Hunter", mage: "Mage", rogue: "Rogue", priest: "Priest",
    warlock: "Warlock", paladin: "Paladin", druid: "Druid", shaman: "Shaman" };
  var CLASSCOLOR = { warrior: "#c69b6d", hunter: "#aad372", mage: "#3fc7eb", rogue: "#fff468", priest: "#ffffff",
    warlock: "#8788ee", paladin: "#f48cba", druid: "#ff7c0a", shaman: "#0070dd" };
  var SLOTLABEL = { "main-hand": "Main Hand", "off-hand": "Off Hand", "one-hand": "One-Hand", "two-hand": "Two-Hand", held: "Held In Off-hand" };

  function esc(s) { return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
  function img(n) { return '<img src="' + CDN + esc(n || "inv_misc_questionmark") + '.jpg" alt="" loading="lazy" onerror="this.onerror=null;this.src=\'' + CDN + 'inv_misc_questionmark.jpg\'">'; }
  function slotLabel(s) { return SLOTLABEL[s] || (s ? s.charAt(0).toUpperCase() + s.slice(1) : ""); }

  var DATA = null, BYID = {};

  var GK = null;
  function itemTip(row) {
    var it = BYID[row.id];
    if (!it || !GK) {
      return '<b class="q-' + esc(row.q || "unknown") + '">' + esc(row.name) + "</b>" +
        '<span class="it-src">' + esc(fromText(row) || "") + "</span>" +
        '<span class="it-conf">On the list, not in the datamine yet: stats land with a later client read.</span>';
    }
    var src = fromText(row) || "";
    var from = src && !(it.drops || it.quests) ? '<span class="it-drop">' + esc(src) + "</span>" : "";
    return GK.itemTip(it) + from;
  }
  function fromText(row) {
    return (row.from || []).map(function (f) { return f.t + (f.n ? " · " + f.n : ""); }).join("; ");
  }

  function state() {
    var p = new URLSearchParams(location.search);
    return { c: p.get("c") || "warrior", s: p.get("s") || "" };
  }
  function setState(c, s, keepHash) {
    var url = "?c=" + encodeURIComponent(c) + (s ? "&s=" + encodeURIComponent(s) : "") + (keepHash ? location.hash : "");
    history.replaceState(null, "", url);
  }

  function findClass(key) {
    for (var i = 0; i < DATA.classes.length; i++) if (DATA.classes[i].key === key) return DATA.classes[i];
    return DATA.classes[0];
  }
  function findSpec(cls, key) {
    for (var i = 0; i < cls.specs.length; i++) if (cls.specs[i].key === key) return cls.specs[i];
    return cls.specs[0];
  }

  function render() {
    var st = state(), cls = findClass(st.c), spec = findSpec(cls, st.s);
    var strip = document.getElementById("clsstrip");
    strip.innerHTML = DATA.classes.map(function (c) {
      return '<button type="button" role="tab" aria-selected="' + (c.key === cls.key) + '" data-c="' + c.key + '" class="' + (c.key === cls.key ? "on" : "") +
        '" style="--cc:' + CLASSCOLOR[c.key] + '">' + '<img src="' + CDN + "classicon_" + c.key + '.jpg" alt="">' + esc(CLASSNAMES[c.key] || c.key) + "</button>";
    }).join("");
    var tabs = document.getElementById("spectabs");
    tabs.innerHTML = cls.specs.map(function (s) {
      return '<button type="button" role="tab" aria-selected="' + (s.key === spec.key) + '" data-s="' + s.key + '" class="' + (s.key === spec.key ? "on" : "") + '">' +
        (s.icon ? '<img src="' + CDN + esc(s.icon) + '.jpg" alt="">' : "") + esc(s.name) + "</button>";
    }).join("");
    var grid = document.getElementById("bisgrid"), flat = [];
    grid.innerHTML = spec.slots.map(function (sl) {
      return '<section class="bis-slotcard" id="slot-' + esc(sl.slot) + '"><h2>' + esc(sl.label) +
        '<a href="#slot-' + esc(sl.slot) + '" title="Link to this slot">#</a></h2>' +
        '<ol class="bis-rows">' + sl.rows.map(function (r, i) {
          var it = BYID[r.id];
          var q = (it && it.quality) || r.q || "unknown";
          var icon = (it && it.icon) || r.icon;
          var src = fromText(r);
          flat.push(r);
          var label = (r.eslot ? r.eslot + ": " : "") + r.name;
          return '<li class="bis-r q-' + esc(q) + '" data-i="' + esc(r.id) + '" data-n="' + i + '">' +
            '<span class="bis-rank">' + (r.enchant ? "✦" : i + 1) + "</span>" +
            '<span class="bis-ic">' + img(icon) + "</span>" +
            '<span class="bis-nc"><b>' + esc(label) + "</b>" + (src ? "<em>" + esc(src) + "</em>" : "") + "</span>" +
            (r.mats ? '<span class="bis-mats">' + r.mats.map(function (m) {
              return '<span class="bis-mat" data-m="' + esc(m.id) + '" title="' + esc(m.name + (m.n ? " ×" + m.n : "")) + '">' + img(m.icon) + (m.n ? "<b>" + m.n + "</b>" : "") + "</span>";
            }).join("") + "</span>" : "") +
            "</li>";
        }).join("") + "</ol></section>";
    }).join("");
    var kick = document.getElementById("bis-kick");
    kick.innerHTML = "Level <b>" + esc(DATA.level) + "</b> cap &nbsp;·&nbsp; beta build <b>" + esc(DATA.build) + "</b> &nbsp;·&nbsp; lists pulled <b>" + esc(DATA.pulled) + "</b>";
    if (window.TipKit) {
      // rows bind in document order, which is exactly the order they rendered
      grid.querySelectorAll(".bis-r").forEach(function (rowEl, idx) {
        var row = flat[idx];
        if (!row) return;
        TipKit.hover(rowEl, function () { return itemTip(row); }, function () { return "itemtip"; });
      });
    }
  }

  function wire() {
    document.getElementById("clsstrip").addEventListener("click", function (e) {
      var b = e.target.closest("button[data-c]");
      if (!b) return;
      setState(b.getAttribute("data-c"), "", false);
      render();
    });
    document.getElementById("spectabs").addEventListener("click", function (e) {
      var b = e.target.closest("button[data-s]");
      if (!b) return;
      setState(state().c, b.getAttribute("data-s"), false);
      render();
    });
  }

  Promise.all([
    fetch("bis.json").then(function (r) { return r.json(); }),
    fetch("/plan/items-db.json").then(function (r) { return r.ok ? r.json() : { items: [] }; }).catch(function () { return { items: [] }; }),
    fetch("bis-items.json").then(function (r) { return r.ok ? r.json() : { items: [] }; }).catch(function () { return { items: [] }; })
  ]).then(function (rs) {
    DATA = rs[0];
    // The main database carries the current build's tooltips (tools/scavenge_items.py);
    // bis-items.json only fills pieces it lacks.
    rs[2].items.forEach(function (it) { BYID[String(it.id)] = it; });
    rs[1].items.forEach(function (it) { BYID[String(it.id)] = it; });
    if (window.ForgeGear) {
      try { GK = ForgeGear({ items: { items: Object.keys(BYID).map(function (k) { return BYID[k]; }) }, get: function () { return {}; } }); } catch (e) { GK = null; }
    }
    wire();
    render();
    if (location.hash) {
      var el = document.querySelector(location.hash.replace(/[^#a-z0-9_-]/gi, ""));
      if (el) el.scrollIntoView();
    }
  });
})();
