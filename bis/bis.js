/* The BiS page: ForeverRank's own best-in-slot rankings. bis.json (built by tools/build_bis.mjs) ranks every slot
 * per class, spec, faction and level by The Forge's stat weights over our item database; nobody's hand-picked list
 * is copied. Tooltips come from plan/items-db.json through the one shared renderer, plan/gear.js itemTip.
 * Deep links: /bis/?c=priest&s=holy&f=h&l=20#slot-legs. Old ?s= keys resolve through bis.json's aliases. */
(function () {
  "use strict";
  var CDN = "https://wow.zamimg.com/images/wow/icons/large/";
  var CLASSCOLOR = { warrior: "#c69b6d", hunter: "#aad372", mage: "#3fc7eb", rogue: "#fff468", priest: "#ffffff",
    warlock: "#8788ee", paladin: "#f48cba", druid: "#ff7c0a", shaman: "#0070dd" };
  var FACTION = { a: "Alliance", h: "Horde" }, ARTICLE = { a: "an", h: "a" };
  // the old page's slot anchors
  var OLDSLOT = { "two-hand": "mainhand", "main-hand": "mainhand", "one-hand": "mainhand", "off-hand": "offhand", held: "offhand", shield: "offhand", relic: "ranged" };

  function esc(s) { return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
  function img(n) { return '<img src="' + CDN + esc(n || "inv_misc_questionmark") + '.jpg" alt="" loading="lazy" onerror="this.onerror=null;this.src=\'' + CDN + 'inv_misc_questionmark.jpg\'">'; }
  function lsGet(k) { try { return window.localStorage.getItem(k); } catch (e) { return null; } }
  function lsSet(k, v) { try { window.localStorage.setItem(k, v); } catch (e) {} }

  var DATA = null, GK = null, DBSTATE = "loading", BYID = {};

  // ---- state: class, spec, level and faction live in the URL; the faction is also remembered per viewer ----
  function state() {
    var p = new URLSearchParams(location.search);
    var f = p.get("f");
    if (f !== "a" && f !== "h") f = lsGet("bis-faction");
    if (f !== "a" && f !== "h") f = "a";
    var l = +p.get("l");
    if (DATA.levels.indexOf(l) === -1) l = DATA.level;
    return { c: String(p.get("c") || "").toLowerCase(), s: String(p.get("s") || "").toLowerCase(), f: f, l: l };
  }
  function setState(o, keepHash) {
    var url = "?c=" + encodeURIComponent(o.c) + "&s=" + encodeURIComponent(o.s) + (o.l !== DATA.level ? "&l=" + o.l : "") + "&f=" + o.f +
      (keepHash ? location.hash : "");
    history.replaceState(null, "", url);
  }
  function findClass(key) {
    for (var i = 0; i < DATA.classes.length; i++) if (DATA.classes[i].key === key) return DATA.classes[i];
    return DATA.classes[0];
  }
  function findSpec(cls, key) {
    var i, alias = (DATA.aliases[cls.key] || {})[key];
    for (i = 0; i < cls.specs.length; i++) if (cls.specs[i].key === key) return cls.specs[i];
    if (alias) for (i = 0; i < cls.specs.length; i++) if (cls.specs[i].key === alias) return cls.specs[i];
    return cls.specs[0];
  }

  // ---- words ----
  function statName(k) {
    var by = window.ForgeItem && window.ForgeItem.STATBY;
    return by && by[k] ? by[k][1] : k;
  }
  function num(v) { return String(Math.round(v * 100) / 100); }
  function weightsText(w) {
    return Object.keys(w).sort(function (a, b) { return w[b] - w[a] || a.localeCompare(b); })
      .map(function (k) { return statName(k) + " " + num(w[k]); }).join(" · ");
  }
  function itemName(id) { var m = DATA.items[id]; return m ? m[0] : "item " + id; }
  function specTitle(cls, spec) { return spec.key === "all" ? cls.name : spec.label + " " + cls.name; }

  // ---- tooltips: plan/gear.js draws the item; our source lines follow where the item's own data lacks them ----
  // itemTip prints an "Estimate: ... likely a dungeon boss drop" line for any item without drops or quests in items-db.
  // Every row here has a source from our data, so that guess is replaced by the source (the renderer is not forked).
  var ESTLINE = /<span class="it-src it-est">Estimate:[^<]*<\/span>/;
  function tipFor(r) {
    var it = BYID[r[0]], m = DATA.items[r[0]] || [r[0], "unknown"];
    var srcs = r[2].map(function (i) { return DATA.src[i]; });
    if (!it || !GK) {
      return '<b class="q-' + esc(m[1]) + '">' + esc(m[0]) + "</b>" +
        srcs.map(function (s) { return '<span class="it-drop">' + esc(s[1]) + "</span>"; }).join("") +
        '<span class="it-conf">' + (DBSTATE === "loading" ? "Loading the item database for the full tooltip." : "Full tooltip unavailable: the item database did not load.") + "</span>";
    }
    var extra = srcs.filter(function (s) {
      return !(s[0] === "drop" && it.drops && it.drops.length) && !(s[0] === "quest" && it.quests && it.quests.length);
    }).map(function (s) { return '<span class="it-drop">' + esc(s[1]) + "</span>"; }).join("");
    var tip = GK.itemTip(it);
    if (!srcs.length) return tip + extra;
    return ESTLINE.test(tip) ? tip.replace(ESTLINE, function () { return extra; }) : tip + extra;
  }

  // ---- rendering ----
  function rowHTML(r, i, spec, sl) {
    var m = DATA.items[r[0]] || [r[0], "unknown", "", 0];
    var srcs = r[2].map(function (x) { return DATA.src[x][1]; });
    var tags = (r[3] ? '<i class="bis-tag f-' + r[3] + '">' + FACTION[r[3]] + " only</i>" : "") +
      (r[4] ? '<i class="bis-tag">Two-hand</i>' : "") + (m[3] ? '<i class="bis-tag est">Classic stats</i>' : "");
    return '<li class="bis-r q-' + esc(m[1]) + '" tabindex="0" data-tipkit="1">' +
      '<span class="bis-rank">' + (i + 1) + "</span>" +
      '<span class="bis-ic">' + img(m[2]) + "</span>" +
      '<span class="bis-nc"><b>' + esc(m[0]) + "</b>" + (tags ? '<span class="bis-tags">' + tags + "</span>" : "") +
        (srcs.length ? "<em>" + esc(srcs.join("; ")) + "</em>" : "") + "</span>" +
      '<span class="bis-sc" title="Score with The Forge\'s ' + esc(spec.label) + " weights" + (r[4] && sl.charge ? ", minus the best off hand it replaces" : "") + '">' +
        Math.round(r[1]) + "</span></li>";
  }
  function pairHTML(sl) {
    if (sl.pair) {
      var second = sl.rows.length > 1 && sl.rows[1][0] !== sl.pair[1] && sl.pair[0] !== sl.pair[1];
      return '<p class="bis-pair">' + (sl.pair[0] === sl.pair[1] ? "Wear two of <b>" + esc(itemName(sl.pair[0])) + "</b>."
        : "Wear <b>" + esc(itemName(sl.pair[0])) + "</b> and <b>" + esc(itemName(sl.pair[1])) + "</b>." +
          (second ? " The second-best pick stays out: a Unique rule or a one-time quest reward." : "")) + "</p>";
    }
    var w = sl.set;
    if (!w) return "";
    var out = w.two ? "Best setup: <b>" + esc(itemName(w.two)) + "</b> in both hands."
      : w.oh ? "Best setup: <b>" + esc(itemName(w.mh)) + "</b> with <b>" + esc(itemName(w.oh)) + "</b> in the off hand."
      : w.mh ? "Best setup: <b>" + esc(itemName(w.mh)) + "</b>; no off-hand item adds to it." : "";
    if (sl.charge) out += " A two-hander's score here is its own minus the best off hand on this page (" + Math.round(sl.charge) + "), the way The Forge charges it.";
    return out ? '<p class="bis-pair">' + out + "</p>" : "";
  }
  function fcHTML(spec, L) {
    var links = spec.fc[L] || [], pve = links.filter(function (x) { return !x[2]; }), pvp = links.filter(function (x) { return x[2]; });
    function a(x) { return '<a href="' + esc(x[1]) + '" rel="noopener">' + esc(x[0]) + "</a>"; }
    var out = [];
    if (pve.length) out.push("ForeverChanges' hand-picked list" + (pve.length > 1 ? "s" : "") + ": " + pve.map(a).join(", "));
    if (pvp.length) out.push((pve.length ? "their" : "ForeverChanges'") + " PvP pick" + (pvp.length > 1 ? "s" : "") + ": " + pvp.map(a).join(", "));
    return out.length ? '<p class="bis-fc">' + out.join("; ") + ". We rank PvE only.</p>" : "";
  }

  function render() {
    var st = state(), cls = findClass(st.c), spec = findSpec(cls, st.s), L = st.l, f = st.f;
    var list = (spec.lists[L] || spec.lists[DATA.level])[f];
    setState({ c: cls.key, s: spec.key, l: L, f: f }, true);
    document.getElementById("clsstrip").innerHTML = DATA.classes.map(function (c) {
      var on = c.key === cls.key;
      return '<button type="button" role="tab" aria-selected="' + on + '" data-c="' + c.key + '" class="' + (on ? "on" : "") +
        '" style="--cc:' + CLASSCOLOR[c.key] + '"><img src="' + CDN + "classicon_" + c.key + '.jpg" alt="">' + esc(c.name) + "</button>";
    }).join("");
    document.getElementById("spectabs").innerHTML = cls.specs.map(function (s) {
      var on = s.key === spec.key;
      return '<button type="button" role="tab" aria-selected="' + on + '" data-s="' + s.key + '" class="' + (on ? "on" : "") + '">' +
        (s.icon ? '<img src="' + CDN + esc(s.icon) + '.jpg" alt="">' : "") + esc(s.name) + "</button>";
    }).join("");
    document.getElementById("bisbar").innerHTML =
      '<div class="bis-seg" role="group" aria-label="Faction">' + ["a", "h"].map(function (k) {
        return '<button type="button" data-f="' + k + '" class="f-' + k + (k === f ? " on" : "") + '" aria-pressed="' + (k === f) + '">' + FACTION[k] + "</button>";
      }).join("") + "</div>" +
      (DATA.levels.length > 1 ? '<div class="bis-seg" role="group" aria-label="Level">' + DATA.levels.map(function (l) {
        return '<button type="button" data-l="' + l + '" class="' + (l === L ? "on" : "") + '" aria-pressed="' + (l === L) + '">Level ' + l + "</button>";
      }).join("") + "</div>" : "");

    var forge = "../plan/" + (list.forge || "");
    document.getElementById("bishead").innerHTML =
      '<div class="bis-hd-t"><img src="' + CDN + esc(spec.icon || "classicon_" + cls.key) + '.jpg" alt=""><h2 style="--cc:' + CLASSCOLOR[cls.key] + '">' +
        esc(specTitle(cls, spec)) + "</h2><span>Level " + L + " · " + FACTION[f] + "</span></div>" +
      '<p class="bis-by">Ranked by <a href="' + esc(forge) + '" title="Opens The Forge as ' + ARTICLE[f] + " " + esc(FACTION[f]) + " " + esc(cls.name) +
        (spec.tree ? " with one point in " + esc(spec.tree) + " (so it uses these weights)" : "") + ' and the picks below equipped">The Forge\'s ' +
        esc(spec.label) + " weights</a>: " + '<span class="bis-w">' + esc(weightsText(spec.w)) + "</span></p>" +
      (spec.pick ? '<p class="bis-note">The Forge opens on its ' + esc(spec.tree) + " weights; choose " + esc(spec.label) + " under Weights in any gear slot to rank the same way.</p>" : "") +
      fcHTML(spec, L) +
      '<p class="bis-note">A score is the item\'s stats times these weights, the number The Forge\'s gear picker shows. ' +
        (spec.w.procDps ? "Chance-on-hit damage counts where the game data gives the chance; other procs, on-use effects and set bonuses do not. "
          : "Procs, on-use effects and set bonuses do not count. ") +
        "An item with no stored required level counts as needing its item level minus 5, as in The Forge" +
        (DATA.held && DATA.held[L] ? ", which for now holds back " + DATA.held[L] + " quest rewards (all classes and factions) from quests open at level " + L + ". " : ". ") +
        "Listed is only gear our data can place: drops from dungeons open in the beta now, quest rewards the " + FACTION[f] + " can take, crafts with a recipe item, " +
        "and tradeable gear players' games have shown. Vendor and PvP-reward gear, other world drops and recipes trainers teach are missing until our data has them.</p>";

    var grid = document.getElementById("bisgrid"), flat = [];
    grid.innerHTML = list.slots.map(function (sl) {
      var rows = sl.rows.map(function (r, i) { flat.push(r); return rowHTML(r, i, spec, sl); }).join("");
      return '<section class="bis-slotcard" id="slot-' + esc(sl.slot) + '"><h2>' + esc(sl.label) +
        '<a href="#slot-' + esc(sl.slot) + '" title="Link to this slot">#</a></h2>' +
        (rows ? '<ol class="bis-rows">' + rows + "</ol>" + pairHTML(sl)
          : '<p class="bis-empty">Nothing our data can place for this class scores above zero with these weights.</p>') + "</section>";
    }).join("");
    document.getElementById("bis-kick").innerHTML = "Level <b>" + L + "</b> &nbsp;·&nbsp; items build <b>" + esc(DATA.build) +
      "</b> &nbsp;·&nbsp; ranked <b>" + esc(DATA.date) + "</b>";
    // rows bind in document order, which is the order they rendered
    grid.querySelectorAll(".bis-r").forEach(function (el, idx) {
      var row = flat[idx];
      el._row = row;
      if (window.TipKit) TipKit.hover(el, function () { return tipFor(row); }, function () { return "itemtip"; });
    });
  }

  function openTip(el) {
    if (!el || !el._row || !window.TipKit) return;
    TipKit.openSheet(tipFor(el._row), [], { cls: "itemtip", owner: "bis:" + el._row[0] });
  }
  function wire() {
    function go(patch) {
      var st = state(), cls = findClass(st.c), spec = findSpec(cls, st.s);
      var o = { c: cls.key, s: spec.key, l: st.l, f: st.f };
      Object.keys(patch).forEach(function (k) { o[k] = patch[k]; });
      setState(o, false);
      render();
    }
    document.getElementById("clsstrip").addEventListener("click", function (e) {
      var b = e.target.closest("button[data-c]");
      if (b) go({ c: b.getAttribute("data-c"), s: "" });
    });
    document.getElementById("spectabs").addEventListener("click", function (e) {
      var b = e.target.closest("button[data-s]");
      if (b) go({ s: b.getAttribute("data-s") });
    });
    document.getElementById("bisbar").addEventListener("click", function (e) {
      var b = e.target.closest("button[data-f],button[data-l]");
      if (!b) return;
      if (b.hasAttribute("data-f")) { lsSet("bis-faction", b.getAttribute("data-f")); go({ f: b.getAttribute("data-f") }); }
      else go({ l: +b.getAttribute("data-l") });
    });
    // Touch, pen and keyboard: the tooltip opens as a bottom sheet (mouse hover is bound per row in render).
    var grid = document.getElementById("bisgrid");
    grid.addEventListener("click", function (e) {
      var el = e.target.closest(".bis-r");
      if (el && window.TipKit && (TipKit.touchy() || e.detail === 0)) openTip(el);
    });
    grid.addEventListener("keydown", function (e) {
      if (e.key !== "Enter" && e.key !== " ") return;
      var el = e.target.closest(".bis-r");
      if (el) { e.preventDefault(); openTip(el); }
    });
  }
  function scrollToHash() {
    var h = (location.hash || "").replace(/^#slot-/, "");
    if (!h) return;
    var el = document.getElementById("slot-" + (OLDSLOT[h] || h).replace(/[^a-z0-9_-]/gi, ""));
    if (el) el.scrollIntoView();
  }

  fetch("bis.json?schema=3").then(function (r) { return r.json(); }).then(function (d) {
    if (!d || d.schema !== 3) throw new Error("old bis.json");
    DATA = d;
    wire();
    render();
    scrollToHash();
    // The full item database (about 9 MB) only feeds the tooltips, so it loads after the lists are on screen.
    return fetch("/plan/items-db.json").then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; }).then(function (db) {
      if (!db || !Array.isArray(db.items) || !window.ForgeGear) { DBSTATE = "failed"; return; }
      db.items.forEach(function (it) { BYID[String(it.id)] = it; });
      try { GK = window.ForgeGear({ items: db, get: function () { return {}; } }); DBSTATE = "ready"; } catch (e) { GK = null; DBSTATE = "failed"; }
    });
  }).catch(function () {
    document.getElementById("bisgrid").innerHTML = '<p class="bis-empty">Could not load the lists. Refresh to try again.</p>';
  });
})();
