/* The Codex: renders codex.json. Icons hotlinked like everywhere else. */
(function () {
  "use strict";
  var CDN = "https://wow.zamimg.com/images/wow/icons/large/";
  var CLASS_COLOUR = { Warrior: "#c79c6e", Paladin: "#f58cba", Hunter: "#abd473", Rogue: "#fff569",
    Priest: "#ffffff", Shaman: "#0070de", Mage: "#69ccf0", Warlock: "#9482c9", Druid: "#ff7d0a" };
  function esc(s) { return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
  function img(n) {
    var src = n && String(n).indexOf("/") !== -1 ? n : CDN + (n || "inv_misc_questionmark") + ".jpg";
    return '<img src="' + src + '" alt="" loading="lazy" onerror="this.onerror=null;this.src=\'' + CDN + 'inv_misc_questionmark.jpg\'">';
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
    var bodyHtml;
    if (key === "souls") {
      bodyHtml = '<div class="cxm-souls">' + t.list.map(function (f) {
        var cut = f.indexOf(": ");
        return '<div class="soulcard"><b>' + esc(cut > 0 ? f.slice(0, cut) : f) + "</b><p>" + esc(cut > 0 ? f.slice(cut + 2) : "") + "</p></div>";
      }).join("") + "</div>";
    } else {
      bodyHtml = '<ol class="cxm-list">' + t.list.map(function (f, i) { return "<li><b>" + esc(hs[i]) + "</b><p>" + esc(f) + "</p></li>"; }).join("") + "</ol>";
    }
    m.querySelector(".cxm-body").innerHTML = '<div class="cxm-head">' + img(t.icon || "inv_misc_book_09") + "<b id=\"cxm-title\">" + esc(t.title) + "</b></div>" + bodyHtml;
    m.hidden = false;
    m.querySelector(".cxm-card").scrollTop = 0;
    m.querySelector(".cxm-card").focus();
  }

  // ---- Database search: Forever items (../plan/items.json) plus this page's places, perks, spells and systems ----
  var PAGE = window.CODEX_PAGE || "db";
  var CATS = [["all", "All"], ["weapon", "Weapons"], ["armor", "Armor"], ["accessory", "Accessories"], ["offhand", "Off-hands and relics"],
    ["consumable", "Consumables"], ["recipe", "Recipes"], ["pvp", "PvP"], ["misc", "Misc"], ["place", "Places"], ["perk", "Legacy perks"],
    ["soul", "Souls"], ["spell", "Spells"], ["talent", "Talents"], ["racial", "Racials"], ["set", "Item sets"], ["system", "Systems"]];
  var SUBFIRST = ["Cloth", "Leather", "Mail", "Plate", "Shield", "Neck", "Ring", "Trinket", "Cloak", "Alchemy", "Cooking", "First Aid", "Zone", "Dungeon", "Raid", "Battleground"];
  var QUAL = ["poor", "common", "uncommon", "rare", "epic", "legendary"];
  var IDX = [], GK = null, SQ = { q: "", cat: "all", sub: "", qual: "", lvl: "", cls: "", prof: "", sk: "", era: false }, SHOWN = 60;
  var CLASSES9 = ["Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid"];
  var PROFS = ["Alchemy", "Blacksmithing", "Comprehension", "Cooking", "Enchanting", "Engineering", "First Aid", "Fishing", "Herbalism", "Leatherworking", "Mining", "Poisons", "Skinning", "Tailoring"];
  function slotName(sl) {
    return { "main-hand": "Main Hand", "off-hand": "Off Hand", "one-hand": "One-Hand", "two-hand": "Two-Hand", head: "Head", neck: "Neck", shoulder: "Shoulder",
      back: "Back", chest: "Chest", wrist: "Wrist", hands: "Hands", waist: "Waist", legs: "Legs", feet: "Feet", finger: "Finger", trinket: "Trinket",
      ranged: "Ranged", relic: "Relic", thrown: "Thrown", tabard: "Tabard", shirt: "Shirt" }[sl] || "";
  }
  function buildSouls(d) {
    if (!d.souls || !d.souls.list) return;
    headList(d.souls.list.map(function (s) { return s[0] + ": " + s[1]; }), "souls", "Soul Engraving: 204 shoulder souls", "spell_shadow_soulleech_3");
    d.souls.list.forEach(function (s) {
      IDX.push({ kind: "soul", cat: "soul", sub: "Shoulder soul", name: s[0], icon: s[3] || (s[2] ? "classicon_" + s[2].toLowerCase() : "spell_shadow_soulleech_3"), q: "unknown",
        cls: s[2] ? s[2].charAt(0) + s[2].slice(1).toLowerCase() : undefined,
        meta: "Soul Engraving \u00b7 " + (s[2] ? s[2].charAt(0) + s[2].slice(1).toLowerCase() : "class unsorted"), topic: "souls", text: (s[0] + " " + s[1] + " " + (s[2] || "")).toLowerCase() });
    });
  }
  var SRC_LABEL = { client: "Beta client", sod: "SoD wiring", classic: "Classic text", basic: "Demo book", classiconly: "Not in Forever" };
  var SRC_TIP = {
    client: "Tooltip read from beta client data, build 1.60.1.69876.",
    sod: "Season of Discovery wiring in the client: class-masked but with no Forever learn level yet. May change before launch.",
    classic: "Classic placeholder text; the demo tooltip was never captured, so the Forever version is unverified.",
    basic: "Listed in the level-38 demo spellbook. Universal basics.",
    classiconly: "A Classic spell the Forever demo book does not list: possibly cut, moved above the demo level, or hidden until discovered."
  };
  var VERDICT = { "same": "same text as Classic", "changed": "text changed from Classic", "new": "new in Forever", "rank": "rank layout differs", "renamed": "renamed from Classic", "moved": "moved from Classic", "unverified": "tooltip unverified" };
  var ERA_LABEL = { forever: "Forever-authored", sod: "SoD spell reused", retail: "Retail-era spell", classic: "Classic-era spell" };
  function buildBook(sb) {
    (sb.spells || []).forEach(function (p) {
      IDX.push({ kind: "bookspell", cat: "spell", sub: p.c, name: p.n, icon: p.icon || "inv_misc_questionmark", q: "unknown",
        cls: p.c, lvlKey: typeof p.lvl === "number" ? p.lvl : undefined, sb: p, side: SRC_LABEL[p.src] || "",
        meta: [p.c, p.tab, p.lvl ? "Level " + p.lvl : (p.src === "sod" ? "no learn level yet" : ""), p.tag, VERDICT[p.s] || ""].filter(Boolean).join(" \u00b7 "),
        text: (p.n + " " + p.c + " " + p.tab + " " + (p.d || "")).toLowerCase() });
    });
    (sb.talents || []).forEach(function (t) {
      IDX.push({ kind: "talent", cat: "talent", sub: t.c, name: t.n, icon: t.icon || "inv_misc_questionmark", q: "unknown",
        cls: t.c, lvlKey: 10 + (t.row - 1) * 5, tl: t, side: "Demo transcription",
        meta: [t.c, t.tree + " tree", "Tier " + t.row, t.r + (t.r === 1 ? " rank" : " ranks"), VERDICT[t.s] || ""].filter(Boolean).join(" \u00b7 "),
        text: (t.n + " " + t.c + " " + t.tree + " " + (t.d || "")).toLowerCase() });
    });
    (sb.racials || []).forEach(function (r) {
      IDX.push({ kind: "racial", cat: "racial", sub: r.race, name: r.n, icon: r.icon || "inv_misc_questionmark", q: "unknown",
        lvlKey: 1, rc: r, side: "Demo transcription",
        meta: [r.race, r.kind === "active" ? "Active racial" : "Passive racial"].filter(Boolean).join(" \u00b7 "),
        text: (r.n + " " + r.race + " " + (r.d || "")).toLowerCase() });
    });
  }
  function buildSets(st) {
    (st.sets || []).forEach(function (p) {
      IDX.push({ kind: "itemset", cat: "set", sub: p.cat, name: p.n, icon: (p.pieces[0] && p.pieces[0].icon) || "inv_chest_chain_07", q: "unknown",
        cls: p.cls.length === 1 ? p.cls[0] : undefined, lvlKey: p.reqLevel || undefined, st: p, era: p.era,
        side: p.era === "sod" ? "SoD-era data" : p.era === "retail" ? "Retail-era data" : p.touched ? "Reworked for Forever" : "Classic data",
        meta: [p.cat, p.era === "sod" ? "SoD-era duplicate" : "", p.pieces.length + " pieces", p.cls.join("/"), p.reqLevel ? "Level " + p.reqLevel : ""].filter(Boolean).join(" \u00b7 "),
        text: (p.n + " " + p.cat + " " + p.cls.join(" ") + " " + p.bonuses.map(function (b) { return b.spell + " " + (b.fx || ""); }).join(" ")).toLowerCase() });
    });
  }
  function sbTip(e) {
    var h = "<b>" + esc(e.name) + "</b>" + '<span class="sbt-m">' + esc(e.meta) + "</span>";
    if (e.kind === "bookspell") {
      var p = e.sb;
      if (p.d) h += "<p>" + esc(p.d) + "</p>";
      if (p.note) h += '<p class="sbt-note">' + esc(p.note) + "</p>";
      if (p.cl && p.s && p.s !== "same") h += '<p class="sbt-note">Classic trains it at level ' + p.cl + ".</p>";
      h += '<p class="sbt-src">' + esc(SRC_TIP[p.src] || "") + "</p>";
    } else if (e.kind === "talent") {
      var t = e.tl;
      if (t.d) h += "<p>" + esc(t.d) + (t.r > 1 ? " (rank 1 of " + t.r + ")" : "") + "</p>";
      h += '<p class="sbt-note">Tier ' + t.row + ": earliest around level " + e.lvlKey + " by Classic one-point-per-level pacing. An estimate, not Forever data.</p>";
      h += '<p class="sbt-src">Transcribed from BlizzCon demo footage (talentsforever.com export, CC BY 4.0).</p>';
    } else if (e.kind === "racial") {
      if (e.rc.d) h += "<p>" + esc(e.rc.d) + "</p>";
      h += '<p class="sbt-src">Transcribed from BlizzCon demo footage and reveal panels (talentsforever.com export, CC BY 4.0).</p>';
    } else if (e.kind === "itemset") {
      var st = e.st;
      h += '<ul class="sbt-pieces">' + st.pieces.map(function (pc) {
        return '<li class="q-' + esc(pc.q) + '">' + esc(pc.n) + (pc.slot ? " \u2013 " + esc(slotName(pc.slot) || pc.slot) : "") + "</li>";
      }).join("") + "</ul>";
      st.bonuses.forEach(function (b) {
        h += '<p class="sbt-bonus"><b>(' + b.p + ")</b> " + esc(b.fx || b.spell) +
          (b.fx ? "" : ' <i class="sbt-int">internal name, no tooltip text in the client</i>') +
          ' <i class="sbt-era sbt-era-' + b.era + '">' + ERA_LABEL[b.era] + "</i></p>";
      });
      h += '<p class="sbt-src">ItemSet tables from beta client 1.60.1.69876. Era per bonus read from spell ID bands.</p>';
    }
    return h;
  }
  function buildIndex(d, items) {
    (items || []).forEach(function (it) {
      var meta = [it.era === "sod" ? "SoD-era data" : it.era === "retail" ? "Retail-era data" : "", it.sub, slotName(it.slot), it.reqLevel ? "Level " + it.reqLevel : "", it.sk ? it.sk[0] + (it.sk[1] ? " " + it.sk[1] : "") : ""].filter(function (x, i, a) { return x && a.indexOf(x) === i; });
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
      if (((e.kind === "item" && e.it.era) || e.era) && !SQ.era) return false;
      if (SQ.prof) {
        if (e.kind !== "item") return false;
        if (!e.it.sk || e.it.sk[0] !== SQ.prof) return false;
        if (SQ.sk && e.it.sk[1] > +SQ.sk) return false;
      }
      if (SQ.lvl) {
        if (e.kind === "item") { if (!e.it.reqLevel || e.it.reqLevel > +SQ.lvl) return false; }
        else if (typeof e.lvlKey === "number") { if (e.lvlKey > +SQ.lvl) return false; }
        else return false;
      }
      if (SQ.cls) {
        if (e.kind === "item") {
          if (e.it.cls && e.it.cls.indexOf(SQ.cls) === -1) return false;
          if (GK && GK.canUse && !GK.canUse(SQ.cls, e.it, +SQ.lvl || 60)) return false;
        }
        else if (e.cls) { if (e.cls !== SQ.cls) return false; }
        else if (e.kind !== "racial") return false;
      }
      for (var i = 0; i < words.length; i++) if (e.text.indexOf(words[i]) === -1) return false;
      return true;
    }).sort(function (a, b) {
      var ql = SQ.q.toLowerCase(), as = ql && a.name.toLowerCase().indexOf(ql) === 0 ? 0 : 1, bs = ql && b.name.toLowerCase().indexOf(ql) === 0 ? 0 : 1;
      if (as !== bs) return as - bs;
      if (SQ.lvl) {
        // A level cap is set: gear nearest the cap first, so the filter is
        // visibly doing its job instead of re-showing the same level 1 epics.
        var al = (a.it && a.it.reqLevel) || a.lvlKey || 0, bl = (b.it && b.it.reqLevel) || b.lvlKey || 0;
        if (al !== bl) return bl - al;
      }
      var aq = QUAL.indexOf(a.q), bq = QUAL.indexOf(b.q);
      if (aq !== bq) return bq - aq;
      return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
    });
  }
  function drawSearch() {
    var box = document.getElementById("dbs");
    if (!box) return;
    var active = true; // results always show; typing or a chip narrows them
    function eraOK(e) { return !(((e.kind === "item" && e.it.era) || e.era) && !SQ.era); }
    var pool = IDX.filter(function (e) { return eraOK(e) && (SQ.cat === "all" || e.cat === SQ.cat); });
    var subs = [];
    pool.forEach(function (e) { if (SQ.cat !== "all" && subs.indexOf(e.sub) === -1) subs.push(e.sub); });
    subs.sort(function (a, b) {
      var ai = SUBFIRST.indexOf(a), bi = SUBFIRST.indexOf(b);
      if (ai !== -1 || bi !== -1) return (ai === -1 ? 99 : ai) - (bi === -1 ? 99 : bi);
      return /^Unknown|^Other/.test(a) ? 1 : /^Unknown|^Other/.test(b) ? -1 : a < b ? -1 : 1;
    });
    var quals = QUAL.filter(function (q) { return pool.some(function (e) { return e.q === q; }); });
    document.getElementById("dbs-cats").innerHTML = CATS.map(function (c) {
      var n = IDX.filter(function (e) { return eraOK(e) && (c[0] === "all" || e.cat === c[0]); }).length;
      return n ? '<button type="button" data-dbcat="' + c[0] + '"' + (SQ.cat === c[0] ? ' class="on"' : "") + ">" + esc(c[1]) + "<i>" + n + "</i></button>" : "";
    }).join("");
    var sr = document.getElementById("dbs-subs");
    sr.hidden = !(subs.length > 1 || (quals.length > 1 && active));
    sr.innerHTML = (subs.length > 1 ? subs.map(function (x) { return '<button type="button" data-dbsub="' + esc(x) + '"' + (SQ.sub === x ? ' class="on"' : "") + ">" + esc(x) + "</button>"; }).join("") : "") +
      (quals.length > 1 ? '<span class="dbs-q">' + quals.map(function (q) { return '<button type="button" class="q-' + q + (SQ.qual === q ? " on" : "") + '" data-dbqual="' + q + '">' + q + "</button>"; }).join("") + "</span>" : "");
    if (window.TipKit) TipKit.hide();
    var out = document.getElementById("dbs-out"), res = active ? matches() : [];
    document.getElementById("dbs-n").textContent = active ? res.length + (res.length === 1 ? " result" : " results") + (SQ.lvl ? " usable at " + SQ.lvl : "") : IDX.length + " entries";
    out.hidden = !active;
    if (!active) return;
    out.innerHTML = res.length ? res.slice(0, SHOWN).map(function (e) {
      var i = IDX.indexOf(e);
      var hasSbt = e.kind === "bookspell" || e.kind === "talent" || e.kind === "racial" || e.kind === "itemset";
      return '<button type="button" class="dbs-row' + (e.kind === "item" ? " q-" + esc(e.q) : "") + '" data-dbi="' + i + '"' + (e.kind === "item" ? ' data-tipkit="1"' : hasSbt ? ' data-sbt="1"' : "") + ">" +
        '<span class="dbs-ic">' + img(e.icon || "inv_misc_questionmark") + "</span>" +
        '<span class="dbs-t"><b>' + esc(e.name) + "</b><em>" + esc(e.meta) + "</em></span>" +
        '<span class="dbs-s">' + esc(e.kind === "item" ? e.side : (e.side || { place: "The new world", perk: "The Legacy system", spell: "Spells", system: "Systems" }[e.cat] || "")) + "</span></button>";
    }).join("") + (res.length > SHOWN ? '<button type="button" class="dbs-more" data-dbmore="1">Show all ' + res.length + "</button>" : "")
      : '<p class="dbs-none">Nothing matches yet. Forever has shown only so much; the beta adds the rest.</p>';
    if (window.TipKit && GK) out.querySelectorAll(".dbs-row[data-tipkit]").forEach(function (row) {
      TipKit.hover(row, function (el) { return GK.itemTip(IDX[+el.getAttribute("data-dbi")].it); }, function () { return "itemtip"; });
    });
    if (window.TipKit) out.querySelectorAll(".dbs-row[data-sbt]").forEach(function (row) {
      TipKit.hover(row, function (el) { return sbTip(IDX[+el.getAttribute("data-dbi")]); }, function () { return "itemtip"; });
    });
  }
  function syncUrl() {
    try {
      var u = new URL(location.href);
      ["q", "cat", "sub", "qual", "lvl"].forEach(function (k) { var v = k === "q" ? SQ.q.trim() : SQ[k]; if (v && v !== "all") u.searchParams.set(k, v); else u.searchParams.delete(k); });
      history.replaceState(null, "", u.pathname + u.search + u.hash);
    } catch (e) {}
  }
  function initSearch() {
    var box = document.getElementById("dbs");
    if (!box) return;
    box.innerHTML = '<div class="dbs-bar"><input type="search" id="dbs-qi" placeholder="Search items, spells, talents, sets, souls, dungeons" autocomplete="off" spellcheck="false" aria-label="Search the Database">' +
      '<span id="dbs-n"></span></div><div class="dbs-cats" id="dbs-cats" role="group" aria-label="Type"></div>' +
      '<div class="dbs-filt" id="dbs-filt"><input type="number" id="dbf-lvl" min="1" max="60" placeholder="Max level" aria-label="Max level: show only what is usable at that level">' +
      '<select id="dbf-cls" aria-label="Class"><option value="">Any class</option>' + CLASSES9.map(function (c) { return '<option>' + c + '</option>'; }).join("") + '</select>' +
      '<select id="dbf-prof" aria-label="Profession"><option value="">Any profession</option>' + PROFS.map(function (c) { return '<option>' + c + '</option>'; }).join("") + '</select>' +
      '<input type="number" id="dbf-sk" min="1" max="300" placeholder="Skill" aria-label="Maximum profession skill">' +
      '<button type="button" id="dbf-era" aria-pressed="false" data-tip="The branch carries Season of Discovery and retail leftovers. Hidden unless you ask; every such row is labeled.">SoD and retail data: hidden</button>' +
      '<button type="button" id="dbf-x" hidden>Clear</button></div>' +
      '<div class="dbs-subs" id="dbs-subs" hidden></div><div class="dbs-out" id="dbs-out" hidden></div>';
    try {
      var sp = new URLSearchParams(location.search);
      SQ.q = sp.get("q") || ""; SQ.cat = sp.get("cat") || "all"; SQ.sub = sp.get("sub") || ""; SQ.qual = sp.get("qual") || "";
      SQ.lvl = sp.get("lvl") || "";
    } catch (e) {}
    var qi = document.getElementById("dbs-qi"), tmr = null;
    function fEl(id) { return document.getElementById(id); }
    function readFilt() {
      SQ.lvl = fEl("dbf-lvl").value; SQ.cls = fEl("dbf-cls").value; SQ.prof = fEl("dbf-prof").value; SQ.sk = fEl("dbf-sk").value;
      fEl("dbf-x").hidden = !(SQ.lvl || SQ.cls || SQ.prof || SQ.sk);
      SHOWN = 60; drawSearch(); syncUrl();
    }
    var ftmr = null;
    ["dbf-lvl", "dbf-sk"].forEach(function (id) { fEl(id).addEventListener("input", function () { clearTimeout(ftmr); ftmr = setTimeout(readFilt, 200); }); });
    ["dbf-cls", "dbf-prof"].forEach(function (id) { fEl(id).addEventListener("change", readFilt); });
    fEl("dbf-era").addEventListener("click", function () {
      SQ.era = !SQ.era;
      var b = fEl("dbf-era");
      b.textContent = SQ.era ? "SoD and retail data: shown" : "SoD and retail data: hidden";
      b.setAttribute("aria-pressed", String(SQ.era));
      b.classList.toggle("on", SQ.era);
      SHOWN = 60; drawSearch();
    });
    fEl("dbf-x").addEventListener("click", function () {
      ["dbf-lvl", "dbf-sk"].forEach(function (id) { fEl(id).value = ""; });
      ["dbf-cls", "dbf-prof"].forEach(function (id) { fEl(id).value = ""; });
      readFilt();
    });
    qi.value = SQ.q;
    if (SQ.lvl) { fEl("dbf-lvl").value = SQ.lvl; fEl("dbf-x").hidden = false; }
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
        if (en.kind === "bookspell" || en.kind === "talent" || en.kind === "racial" || en.kind === "itemset") {
          if (window.TipKit && (TipKit.touchy() || e.detail === 0)) TipKit.openSheet(sbTip(en), [], { cls: "itemtip", owner: "db:" + en.name });
          return;
        }
        if (en.topic) { openTopic(en.topic); return; }
        if (en.href && !document.querySelector(en.href)) {
          var PAGE_OF = { "#world": "/world/", "#unseen": "/classes/", "#classes": "/classes/", "#ranks": "/rankings/" };
          if (PAGE_OF[en.href]) { location.href = PAGE_OF[en.href] + en.href; return; }
        }
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

  fetch("/codex/codex.json", { cache: "no-store" }).then(function (r) { return r.json(); }).then(function (d) {
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
    if (PAGE === "db") section("legacy", "The Legacy system", headList(lg.facts, "legacy", "The Legacy system", "inv_misc_book_07") + '<div id="legacy-win"></div>');

    // Unseen spells
    var un = d.unseen;
    function sprows(list, withIcon) {
      return '<div class="soulgrid">' + list.map(function (r) {
        return '<div class="soulc hasspell" data-name="' + esc(r[1]) + '" style="--cc:' + (CLASS_COLOUR[r[0]] || "#8b93a7") + '">' +
          '<span class="soulring"><img class="soulico" src="' + CDN + esc(withIcon ? (r[3] || "inv_misc_questionmark") : "inv_misc_questionmark") + '.jpg" alt="" loading="lazy"></span>' +
          '<span class="soulhead"><b>' + esc(r[1]) + "</b><i>" + esc(r[0]) + "</i></span>" +
          "<p>" + esc(r[2]) + "</p></div>";
      }).join("") + "</div>";
    }
    var SOUL_CC = { WARRIOR: "#C79C6E", PALADIN: "#F58CBA", HUNTER: "#ABD473", ROGUE: "#FFF569", PRIEST: "#FFFFFF", SHAMAN: "#0070DE", MAGE: "#69CCF0", WARLOCK: "#9482C9", DRUID: "#FF7D0A" };
    function soulLabel(k) { return k ? k.charAt(0) + k.slice(1).toLowerCase() : "Unsorted"; }
    if (PAGE === "classes" && d.souls && d.souls.list.length) {
      var sl = d.souls.list;
      var sCounts = {};
      sl.forEach(function (s) { var k = s[2] || "_"; sCounts[k] = (sCounts[k] || 0) + 1; });
      var chipKeys = Object.keys(SOUL_CC).filter(function (k) { return sCounts[k]; });
      function crest(k) { return k && k !== "_" ? '<img class="soulico" src="' + CDN + "classicon_" + k.toLowerCase() + '.jpg" alt="" loading="lazy">' : '<img class="soulico" src="' + CDN + 'spell_shadow_soulleech_3.jpg" alt="" loading="lazy">'; }
      function fxHtml(t) { return esc(t).replace(/(\d+(?:\.\d+)?%?)/g, "<em>$1</em>"); }
      var chips = '<button type="button" class="soulchip on" data-soulf="">All ' + sl.length + "</button>" +
        chipKeys.map(function (k) {
          return '<button type="button" class="soulchip" data-soulf="' + k + '" style="--cc:' + SOUL_CC[k] + '">' + crest(k) + soulLabel(k) + " " + sCounts[k] + "</button>";
        }).join("") +
        (sCounts._ ? '<button type="button" class="soulchip" data-soulf="_">' + crest("_") + "Unsorted " + sCounts._ + "</button>" : "");
      var cards = sl.map(function (s) {
        var k = s[2] || "_";
        var ring = s[3] ? '<img class="soulico" src="' + CDN + esc(s[3]) + '.jpg" alt="" loading="lazy">' : crest(k);
        return '<div class="soulc' + (s[3] ? " hasspell" : "") + '" data-sk="' + k + '" style="--cc:' + (SOUL_CC[s[2]] || "#8b93a7") + '">' +
          '<span class="soulring">' + ring + "</span><span class=\"soulhead\"><b>" + esc(s[0]) + "</b><i>" + soulLabel(s[2]) + "</i></span><p>" + fxHtml(s[1]) + "</p></div>";
      }).join("");
      section("souls", "Soul Engraving",
        '<p class="soul-warn">DATAMINED, HIDDEN IN THE CLIENT. In active development; nothing here is confirmed for launch.</p>' +
        '<p class="board-sub">The client gives nearly every soul the same placeholder icon, so where the effect text names a spell, the card wears that spell\u2019s icon; the rest wear their class crest.</p>' +
        '<p class="board-sub">' + esc(d.souls.note) + "</p>" +
        '<div class="soulchips">' + chips + '</div><div class="soulgrid">' + cards + "</div>");
    }
    if (PAGE === "classes") section("unseen", "Spells the tooltips admit to", "<p class=\"board-sub\">" + esc(un.note) + "</p>" +
      "<h3>Genuinely new spells</h3>" + sprows(un.new, true) +
      (un.confirmed && un.confirmed.length ? "<h3>Confirmed in the demo spellbook since</h3>" + sprows(un.confirmed, true) : "") +
      "<h3>Granted by talents (already in the trees)</h3>" + sprows(un.granted || [], true) +
      "<h3>Classic spells above the demo's level</h3>" + sprows(un.higher, true));

    // Class changes
    var cc = d.classChanges;
    var ccKeys = Object.keys(cc);
    var ccTotal = ccKeys.reduce(function (n, k) { return n + cc[k].length; }, 0);
    var ccHtml = '<div class="soulchips">' +
      '<button type="button" class="soulchip on" data-ccf="">All ' + ccTotal + "</button>" +
      ccKeys.map(function (k) {
        return '<button type="button" class="soulchip" data-ccf="' + esc(k) + '" style="--cc:' + (CLASS_COLOUR[k] || "#8b93a7") + '">' +
          '<img class="soulico" src="' + CDN + 'classicon_' + k.toLowerCase() + '.jpg" alt="" loading="lazy">' + esc(k) + " " + cc[k].length + "</button>";
      }).join("") + "</div>" +
      '<div class="soulgrid" id="ccgrid">' + ccKeys.map(function (k) {
        return cc[k].map(function (a) {
          return '<div class="soulc hasspell" data-ck="' + esc(k) + '" data-name="' + esc(a[0]) + '" style="--cc:' + (CLASS_COLOUR[k] || "#8b93a7") + '">' +
            '<span class="soulring"><img class="soulico" src="' + CDN + esc(a[2] || "inv_misc_questionmark") + '.jpg" alt="" loading="lazy"></span>' +
            '<span class="soulhead"><b>' + esc(a[0]) + "</b><i>" + esc(k) + "</i></span>" +
            "<p>" + esc(a[1]) + "</p></div>";
        }).join("");
      }).join("") + "</div>";
    if (PAGE === "classes") section("classes", "Class changes, as seen in the demo", ccHtml);
    if (PAGE === "rankings") section("ranks", "Spec rankings, estimated", '<div id="ranks-body"><p class="board-sub">Loading the estimates\u2026</p></div>');

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
    if (PAGE === "world") section("world", "The new world",
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
        '<a class="rm-slide" href="/codex/img/roadmap-slide.jpg" target="_blank" rel="noopener">' +
        '<img src="/codex/img/roadmap-slide.jpg" alt="The official Forever roadmap slide" loading="lazy"></a>';
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
      if (PAGE === "db") section("roadmap", "Roadmap", hero + '<div class="rmap">' + body +
        '</div><p class="board-sub">Off the official slide: more news beyond this roadmap to be shared, features will evolve based on player feedback, content and timing subject to change.</p>');
    }

    var sysHtml = '<div class="systiles">' + d.systems.map(function (sys, i) {
      topic("systems:" + i, sys.t, sys.icon, sys.facts);
      return '<button type="button" class="systile" id="sys' + i + '" data-topic="systems:' + i + '">' + img(sys.icon || "inv_misc_book_09") +
        "<b>" + esc(sys.t) + "</b><span>" + sys.facts.length + " facts</span></button>";
    }).join("") + "</div>";
    if (PAGE === "db") section("systems", "Systems", sysHtml);

    // Hero stat band: the Codex counts itself.
    var nDun = w.dungeons.length, nRaid = w.raids.length,
      nPerk = d.legacy.trees.reduce(function (a, t) { return a + t.perks.length; }, 0),
      nCC = Object.keys(d.classChanges).reduce(function (a, k) { return a + d.classChanges[k].length; }, 0),
      nSpell = (d.unseen.new || []).length + (d.unseen.granted || []).length + (d.unseen.higher || []).length;
    function stripChip(s) {
      return '<a href="' + s[2] + '" style="--img:url(/codex/img/' + s[3] + '.jpg)"><b>' + s[0] + "</b><span>" + s[1] + "</span></a>";
    }
    var nSouls = d.souls && d.souls.list ? d.souls.list.length : 0;
    var hero = '<div class="cxstrip" id="cxstrip">' +
      [[nPerk, "Legacy perks", "/codex/#legacy", "stat-legacy"], [nDun, "dungeons", "/world/#world", "stat-dungeons"], [nRaid, "raids", "/world/#world", "stat-raids"],
        [nCC, "class changes", "/classes/#classes", "stat-classes"], [nSpell, "spells foretold", "/classes/#unseen", "stat-spells"]]
        .concat(nSouls ? [[nSouls, "shoulder souls", "/classes/#souls", "the-barrow-deeps"]] : [])
        .map(stripChip).join("") + "</div>";
    fetch("/codex/counts.json", { cache: "no-store" }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; }).then(function (n) {
      var el = document.getElementById("cxstrip");
      if (!n || !el) return;
      el.innerHTML += [[n.book, "spells in the book", "/codex/?cat=spell", "city-of-dalaran"],
        [n.talents, "talents", "/codex/?cat=talent", "halls-of-thanes"],
        [n.sets, "item sets", "/codex/?cat=set", "blackmaw-hold"]].map(stripChip).join("");
    });

    document.getElementById("cxnav").innerHTML = nav.join("");
    var cxEl = document.getElementById("cx");
    cxEl.innerHTML = hero + out.join("");
    if (location.hash && /^#[a-z0-9-]+$/.test(location.hash)) {
      var hashTarget = document.querySelector(location.hash);
      if (hashTarget) setTimeout(function () { hashTarget.scrollIntoView({ block: "start" }); }, 80);
    }
    cxEl.addEventListener("click", function (e) {
      var t = e.target.closest && e.target.closest("[data-topic]");
      if (t) openTopic(t.getAttribute("data-topic"));
    });
    var sg = document.querySelector(".soulchips");
    if (sg) sg.addEventListener("click", function (e) {
      var b = e.target.closest && e.target.closest("[data-soulf]");
      if (!b) return;
      var f = b.getAttribute("data-soulf");
      sg.querySelectorAll(".soulchip").forEach(function (x) { x.classList.toggle("on", x === b); });
      document.querySelectorAll(".soulgrid").forEach(function (gr) { gr.classList.toggle("onecls", !!f && f !== "_"); });
      document.querySelectorAll(".soulgrid .soulc").forEach(function (card) {
        card.hidden = !!f && card.getAttribute("data-sk") !== f;
      });
    });
    document.addEventListener("click", function (e) {
      var b = e.target.closest && e.target.closest("[data-ccf]");
      if (!b) return;
      var f = b.getAttribute("data-ccf");
      var grid = document.getElementById("ccgrid");
      if (!grid) return;
      b.parentNode.querySelectorAll(".soulchip").forEach(function (x) { x.classList.toggle("on", x === b); });
      grid.querySelectorAll(".soulc").forEach(function (card) {
        card.hidden = !!f && card.getAttribute("data-ck") !== f;
      });
    });
    if (document.getElementById("legacy-win")) drawLegacy();
    fetch("/codex/rankings.json", { cache: "no-store" }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; }).then(function (rk) {
      var box = document.getElementById("ranks-body");
      if (!box) return;
      if (!rk || !rk.lists) { box.innerHTML = '<p class="board-sub">The estimates could not load.</p>'; return; }
      var TABS = [["dps_30", "Damage, level 30"], ["dps_60", "Damage, level 60"], ["heal_30", "Healing, level 30"], ["heal_60", "Healing, level 60"]], cur = "dps_30";
      function draw() {
        var list = rk.lists[cur] || [], top = list.length ? list[0].score : 100;
        box.innerHTML = '<p class="rk-warn"><b>Estimate, not measurement.</b> ' + esc(rk.note) + "</p>" +
          '<div class="rk-tabs" role="tablist">' + TABS.map(function (tb) { return '<button type="button" role="tab" data-rk="' + tb[0] + '"' + (tb[0] === cur ? ' class="on" aria-selected="true"' : "") + ">" + tb[1] + "</button>"; }).join("") + "</div>" +
          '<ol class="rk-list">' + list.map(function (e) {
            var p = e.pulse ? (e.pulse.strong || e.pulse.weak ? "Community: " + e.pulse.strong + " strong, " + e.pulse.weak + " weak" : "") : "";
            return '<li class="rk-row"><span class="rk-n">' + e.rank + "</span>" + img(e.icon) +
              '<span class="rk-t"><b style="color:' + (CLASS_COLOUR[e.cls] || "#fff") + '">' + esc(e.spec) + " " + esc(e.cls) + "</b>" +
              "<em>" + esc(e.why) + "</em></span>" +
              '<span class="rk-s"><span class="rk-bar"><i style="width:' + Math.max(4, Math.round(e.score / top * 100)) + '%"></i></span><b>' + e.score + "</b>" +
              "<small>" + esc(e.conf) + " confidence" + (p ? " \u00b7 " + esc(p) : "") +
              (e.meas && e.meas.samples ? " \u00b7 Demo meters: " + e.meas.samples + (e.meas.samples === 1 ? " reading" : " readings") + (e.meas.avg ? ", about " + e.meas.avg + (cur.indexOf("heal") === 0 ? " hps" : " dps") : "") : "") + "</small></span></li>";
          }).join("") + "</ol>" +
          (cur.indexOf("dps") === 0 && rk.meters && rk.meters.length ? '<h3>Measured in the demo</h3><p class="rk-small">Damage meter readings from BlizzCon demo streams (premade level 38 characters, mostly Drowned City trash), read by eye from the video. Most rows show the class but not the spec, and many classes rest on one to three players. No healing meter appeared in any frame.</p>' +
            '<div class="rk-mt-wrap"><table class="rk-mt"><thead><tr><th>Class</th><th>Spec or role</th><th>Readings</th><th>Players</th><th>Avg dps</th><th>Top of meter</th></tr></thead><tbody>' +
            rk.meters.map(function (m) {
              return '<tr><td style="color:' + (CLASS_COLOUR[m.cls] || "#fff") + '">' + esc(m.cls) + "</td><td>" + esc(m.spec || m.role || "") + "</td><td>" + m.samples + "</td><td>" + m.players + "</td><td>" + (m.avgDps == null ? "" : m.avgDps) + "</td><td>" + (m.topShare == null ? "" : Math.round(m.topShare * 100) + "%") + "</td></tr>";
            }).join("") + "</tbody></table></div>" : "") +
          (rk.quotes && rk.quotes.length ? '<h3>What demo players reported</h3><ul class="facts">' + rk.quotes.map(function (q) {
            return "<li>" + esc(q.quote) + ' <span class="rk-who">(' + esc(q.who) + ", " + esc(q.where) + ", " + esc(q.date) + ", not checked against footage)</span></li>";
          }).join("") + "</ul>" : "") +
          '<p class="rk-small">' + (rk.caveats || []).map(esc).join(" ") + "</p>";
      }
      box.addEventListener("click", function (e) {
        var b = e.target.closest && e.target.closest("[data-rk]");
        if (b) { cur = b.getAttribute("data-rk"); draw(); }
      });
      draw();
    });
    if (PAGE === "db") fetch("/plan/items.json", { cache: "no-store" }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; }).then(function (it) {
      var items = it && Array.isArray(it.items) ? it.items : [];
      if (window.ForgeGear && items.length) { try { GK = ForgeGear({ items: it, get: function () { return {}; } }); } catch (e) { GK = null; } }
      if (PAGE !== "db") return;
      buildSouls(d);
      buildIndex(d, items);
      initSearch();
      fetch("/codex/spellbook.json", { cache: "no-store" }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; }).then(function (sb) {
        if (sb) { buildBook(sb); drawSearch(); }
      });
      fetch("/codex/sets.json", { cache: "no-store" }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; }).then(function (st) {
        if (st) { buildSets(st); drawSearch(); }
      });
      // Then the full client database replaces the curated seed.
      fetch("/plan/items-db.json", { cache: "no-store" }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; }).then(function (db) {
        if (!db || !Array.isArray(db.items) || !db.items.length) return;
        try { GK = ForgeGear({ items: db, get: function () { return {}; } }); } catch (e) {}
        IDX = IDX.filter(function (e) { return e.kind !== "item"; });
        buildIndex({ world: { zones: [], dungeons: [], raids: [], battlegrounds: [] }, legacy: { trees: [] }, unseen: {}, systems: [] }, db.items);
        drawSearch();
      });
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
