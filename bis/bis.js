/* The BiS page: renders bis.json (slot rankings compiled from ForeverChanges,
 * credited on the page) with tooltips joined from our own datamined item
 * database plus bis-items.json for pieces newer than our last datamine.
 * Deep links: /bis/?c=priest&s=holy#slot-legs */
(function () {
  "use strict";
  var CDN = "https://wow.zamimg.com/images/wow/icons/large/";
  var CLASSNAMES = { warrior: "Warrior", hunter: "Hunter", mage: "Mage", rogue: "Rogue", priest: "Priest",
    warlock: "Warlock", paladin: "Paladin", druid: "Druid", shaman: "Shaman" };
  var CLASSCOLOR = { warrior: "#c69b6d", hunter: "#aad372", mage: "#3fc7eb", rogue: "#fff468", priest: "#ffffff",
    warlock: "#8788ee", paladin: "#f48cba", druid: "#ff7c0a", shaman: "#0070dd" };
  var STAT_LINE = { strength: "Strength", agility: "Agility", stamina: "Stamina", intellect: "Intellect", spirit: "Spirit" };
  var EQUIPS = [["attackPower", "Equip: +%s Attack Power."], ["spellPower", "Equip: Increases damage and healing done by magical spells and effects by up to %s."],
    ["healing", "Equip: Increases healing done by up to %s."], ["spellDamage", "Equip: Increases damage done by magical spells and effects by up to %s."],
    ["hit", "Equip: Improves your chance to hit by %s%."], ["crit", "Equip: Improves your chance to get a critical strike by %s%."],
    ["mp5", "Equip: Restores %s mana per 5 sec."], ["defense", "Equip: Increased Defense +%s."]];
  var SCHOOL_DMG = { holySpellDamage: "Holy", fireSpellDamage: "Fire", natureSpellDamage: "Nature", frostSpellDamage: "Frost",
    shadowSpellDamage: "Shadow", arcaneSpellDamage: "Arcane" };
  var SLOTLABEL = { "main-hand": "Main Hand", "off-hand": "Off Hand", "one-hand": "One-Hand", "two-hand": "Two-Hand", held: "Held In Off-hand" };

  function esc(s) { return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
  function img(n) { return '<img src="' + CDN + esc(n || "inv_misc_questionmark") + '.jpg" alt="" loading="lazy" onerror="this.onerror=null;this.src=\'' + CDN + 'inv_misc_questionmark.jpg\'">'; }
  function slotLabel(s) { return SLOTLABEL[s] || (s ? s.charAt(0).toUpperCase() + s.slice(1) : ""); }

  var DATA = null, BYID = {};

  function itemTip(row) {
    var it = BYID[row.id];
    if (!it) {
      return '<b class="q-' + esc(row.q || "unknown") + '">' + esc(row.name) + "</b>" +
        '<span class="it-src">' + esc(fromText(row) || "") + "</span>" +
        '<span class="it-conf">On the list, not in the datamine yet: stats land with a later client read.</span>';
    }
    var s = it.stats || {}, L = [];
    L.push('<b class="q-' + esc(it.quality || "common") + '">' + esc(it.name) + "</b>");
    if (it.binding) L.push('<span class="it-l">' + (it.binding === "BoP" ? "Binds when picked up" : "Binds when equipped") + "</span>");
    if (it.unique) L.push('<span class="it-l">' + esc(it.unique === true ? "Unique" : it.unique) + "</span>");
    if ((it.slot && it.slot !== "unknown") || it.type) L.push('<span class="it-row"><i>' + esc(it.slot === "unknown" ? "" : slotLabel(it.slot)) + "</i><i>" + esc(it.type || "") + "</i></span>");
    if (it.damage) L.push('<span class="it-row"><i>' + esc(it.damage) + " Damage</i><i>" + (it.speed ? "Speed " + Number(it.speed).toFixed(2) : "") + "</i></span>");
    if (it.dps) L.push('<span class="it-l">(' + esc(it.dps) + " damage per second)</span>");
    if (it.armor) L.push('<span class="it-l">' + esc(it.armor) + " Armor</span>");
    if (it.block) L.push('<span class="it-l">' + esc(it.block) + " Block</span>");
    Object.keys(STAT_LINE).forEach(function (k) { if (s[k]) L.push('<span class="it-l">+' + esc(s[k]) + " " + STAT_LINE[k] + "</span>"); });
    if (s.resist) Object.keys(s.resist).forEach(function (r) { L.push('<span class="it-l">+' + esc(s.resist[r]) + " " + esc(r.charAt(0).toUpperCase() + r.slice(1)) + " Resistance</span>"); });
    (it.effects || []).forEach(function (e) { L.push('<span class="it-g">' + esc(e) + "</span>"); });
    EQUIPS.forEach(function (x) {
      if (!s[x[0]]) return;
      var already = (it.effects || []).some(function (e) { return e.indexOf(String(s[x[0]])) !== -1; });
      if (!already) L.push('<span class="it-g">' + esc(x[1].replace("%s", s[x[0]])) + "</span>");
    });
    Object.keys(SCHOOL_DMG).forEach(function (k) {
      if (s[k]) L.push('<span class="it-g">Equip: Increases damage done by ' + SCHOOL_DMG[k] + ' spells and effects by up to ' + esc(s[k]) + ".</span>");
    });
    if (it.flavor) L.push('<span class="it-f">"' + esc(it.flavor) + '"</span>');
    if (it.reqLevel) L.push('<span class="it-l">Requires Level ' + esc(it.reqLevel) + "</span>");
    if (it.itemLevel) L.push('<span class="it-y">Item Level ' + esc(it.itemLevel) + "</span>");
    var src = fromText(row) || "";
    if (src && (!it.source || it.source.indexOf(src.slice(0, 24)) === -1)) L.push('<span class="it-src">' + esc(src) + "</span>");
    L.push('<span class="it-conf">' + esc(it.source || "") + "</span>");
    return L.join("");
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
      return '<button type="button" role="tab" aria-selected="' + (s.key === spec.key) + '" data-s="' + s.key + '" class="' + (s.key === spec.key ? "on" : "") + '">' + esc(s.name) + "</button>";
    }).join("");
    var grid = document.getElementById("bisgrid");
    grid.innerHTML = spec.slots.map(function (sl) {
      return '<section class="bis-slotcard" id="slot-' + esc(sl.slot) + '"><h2>' + esc(sl.label) +
        '<a href="#slot-' + esc(sl.slot) + '" title="Link to this slot">#</a></h2>' +
        '<ol class="bis-rows">' + sl.rows.map(function (r, i) {
          var it = BYID[r.id];
          var q = (it && it.quality) || r.q || "unknown";
          var icon = (it && it.icon) || r.icon;
          var src = fromText(r);
          return '<li class="bis-r q-' + esc(q) + '" data-i="' + esc(r.id) + '">' +
            '<span class="bis-rank">' + (r.enchant ? "✦" : i + 1) + "</span>" +
            '<span class="bis-ic">' + img(icon) + "</span>" +
            '<span class="bis-nc"><b>' + esc(r.name) + "</b>" + (src ? "<em>" + esc(src) + "</em>" : "") + "</span>" +
            (r.mats ? '<span class="bis-mats">' + r.mats.map(function (m) {
              return '<span class="bis-mat" data-m="' + esc(m.id) + '" title="' + esc(m.name + (m.n ? " ×" + m.n : "")) + '">' + img(m.icon) + (m.n ? "<b>" + m.n + "</b>" : "") + "</span>";
            }).join("") + "</span>" : "") +
            "</li>";
        }).join("") + "</ol></section>";
    }).join("");
    var kick = document.getElementById("bis-kick");
    kick.innerHTML = "Level <b>" + esc(DATA.level) + "</b> cap &nbsp;·&nbsp; beta build <b>" + esc(DATA.build) + "</b> &nbsp;·&nbsp; lists pulled <b>" + esc(DATA.pulled) + "</b>";
    if (window.TipKit) {
      grid.querySelectorAll(".bis-r").forEach(function (rowEl) {
        var row = null, sl = spec.slots, id = rowEl.getAttribute("data-i");
        for (var a = 0; a < sl.length && !row; a++) for (var b = 0; b < sl[a].rows.length; b++) if (sl[a].rows[b].id === id) { row = sl[a].rows[b]; break; }
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
    rs[1].items.forEach(function (it) { BYID[String(it.id)] = it; });
    rs[2].items.forEach(function (it) { if (!BYID[String(it.id)]) BYID[String(it.id)] = it; });
    wire();
    render();
    if (location.hash) {
      var el = document.querySelector(location.hash.replace(/[^#a-z0-9_-]/gi, ""));
      if (el) el.scrollIntoView();
    }
  });
})();
