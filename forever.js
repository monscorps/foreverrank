/* LevelPace Forever: plan-stage board. No framework, no build step.
 * Every row is demo data until the game exists; the gear toggles it off.
 * Rendering follows WarcraftLogs' discipline: class colour on the name,
 * band colour on the parse, everything else muted. No chips, no badges. */
(function () {
  "use strict";

  var BETA = Date.parse("2026-09-17T17:00:00Z");    // announced date; hour estimated
  var LAUNCH = Date.parse("2026-11-04T15:00:00Z");  // announced date; hour estimated
  var CAP = Date.now() < LAUNCH ? 30 : 60;

  var BANDS = ["--q-common", "--q-uncommon", "--q-rare", "--q-epic", "--q-legendary", "--q-pink", "--q-artifact"];
  var CLASS_COLOUR = {
    WARRIOR: "#c79c6e", PALADIN: "#f58cba", HUNTER: "#abd473", ROGUE: "#fff569",
    PRIEST: "#ffffff", SHAMAN: "#0070de", MAGE: "#69ccf0", WARLOCK: "#9482c9", DRUID: "#ff7d0a"
  };
  var PVP_RANKS = ["Private", "Corporal", "Sergeant", "Master Sergeant", "Sergeant Major",
    "Knight", "Knight-Lieutenant", "Knight-Captain", "Knight-Champion", "Lieutenant Commander",
    "Commander", "Marshal", "Field Marshal", "Grand Marshal"];

  // ---- the roster -----------------------------------------------------------
  // The guild's own Discord, name for name (mains before the slash). Stats
  // are seeded from each name so the ladder is stable across reloads -- and
  // invented, like everything here, until the game exists.
  function mk(name, cls, level, pace, deaths, hks, dungeons, alive, tag) {
    var perLevel = [], total = 0;
    for (var l = 1; l < level; l++) {
      var sec = Math.round(pace * Math.pow(1.09, l - 10) * (1 + 0.18 * Math.sin(l * 2.3 + name.length)));
      if (sec < 120) sec = 120;
      perLevel.push(sec); total += sec;
    }
    return { name: name, cls: cls, level: level, perLevel: perLevel, seconds: total,
             lph: total > 0 ? (level - 1) / (total / 3600) : 0, deaths: deaths, hks: hks,
             kills: Math.round(hks * 1.18), pvpDeaths: Math.max(1, Math.round(hks / (1.1 + name.length % 3))),
             dungeons: dungeons, quests: 40 + level * 9 + (name.length * 7) % 60,
             ilvl: 8 + Math.round(level * 0.85), alive: alive, realm: "Beta 1", tag: tag };
  }
  function hash(str) {
    var h = 5381;
    for (var i = 0; i < str.length; i++) h = ((h << 5) + h + str.charCodeAt(i)) >>> 0;
    return h;
  }
  function rng(seed) {
    return function () { seed = (seed * 1103515245 + 12345) >>> 0; return seed / 4294967296; };
  }
  var CLASSES = ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"];
  function gen(name, ov) {
    ov = ov || {};
    var r = rng(hash(name));
    var cls = CLASSES[Math.floor(r() * CLASSES.length)];
    var level = 8 + Math.floor(r() * 23);
    var pace = 620 + Math.floor(r() * 520);
    var deaths = Math.floor(r() * 10);
    var hks = Math.floor(r() * r() * 260);
    var dungeons = Math.min(9, Math.floor(r() * 10));
    var alive = r() > 0.12;
    return mk(name, ov.cls || cls, ov.level != null ? ov.level : level, ov.pace || pace,
              ov.deaths != null ? ov.deaths : deaths, ov.hks != null ? ov.hks : hks,
              ov.dungeons != null ? ov.dungeons : dungeons, ov.alive != null ? ov.alive : alive, ov.tag);
  }
  var ROSTER = ["Tpau", "Treefy", "Uglysin", "Ultranstinct", "Upn", "Villepou", "Whiterock",
    "Willamok", "Xynnz", "Yezin", "Zjolnir", "Zuprise", "Eldritch", "Sebzki", "Shiruy",
    "Shockill", "Sjongejonge", "Slons", "Sne", "Stoupe", "Stumfa", "Suki", "Swissotel",
    "Swobuda", "Tony", "Noakesy", "Noximos", "Pain", "Petteri", "Phazed", "Pobs",
    "Poffgone", "Priestage", "Ratiok", "Rezola", "Rhero", "Roach", "Roshlock", "Korjin",
    "Korns", "Kranny", "Lachesis", "Mahito", "Marrion", "Meryla", "Mikhaeraw", "Mingles",
    "Mitre", "Naty", "Nissehaderen", "Fladdo", "Flower", "Flurst", "Gambino", "Gnomwarlock",
    "Goldy", "Happymeal", "Jayme", "Johnsen", "Turalionovna", "Jaegerinden", "Kizerine", "Kony",
    "Chikn", "Christina", "Ckodi", "Clav", "Cloakedblade", "Colonelkitten", "Daddysupreme",
    "Darkmaster", "Didster", "Epowk", "Executia", "Exoxo", "Fake", "Alsong", "Alz",
    "Antigoon", "Anzu", "Arcanehealer", "Ashebarrett", "Bari", "Boynic", "Celuna",
    "Piven", "Prythegywy", "Sauriel", "Shaggrath", "Shazzers", "Trajan", "Vendji",
    "Zhnon", "Crnky", "Emei", "Shins", "Zablefahr", "Aev", "Annsie", "Atropos",
    "Chaipaku", "Collymonk", "Helpstepbro", "Imnotatroll", "Isah", "Maetel", "Peremi",
    "Boopsy", "Colter", "Luseria", "Mandragoran", "Mudpeefrgogo", "Noula", "Suu",
    "Valentina", "Xullue", "Hal", "Koebjeste", "Lanten", "Mular", "Odlid",
    "Orosmomentet", "Pepegasussy", "Thices", "Zerash", "Sixflags", "Timmy",
    "Emillionaire", "Faint", "Zucco", "Ahri", "Ares", "Dreadelf", "Exapt"];
  var DEMO = [
    // Ordained, not rolled: the two the guild would riot over.
    gen("Athgaar", { cls: "WARRIOR", level: 30, pace: 560, deaths: 1, hks: 244, dungeons: 9,
                     alive: true, tag: "Top warrior of the guild. Noob Slayer" }),
    gen("Mutuwa", { cls: "WARRIOR", level: 30, pace: 705, deaths: 0, hks: 88, dungeons: 9,
                    alive: true, tag: "Main tank: nine of nine, zero deaths" }),
    gen("Rickmyrolls", { cls: "PRIEST", level: 30, pace: 648, deaths: 2, hks: 130, dungeons: 7 })
  ];
  ROSTER.forEach(function (n) { DEMO.push(gen(n)); });
  var query = "";

  // ---- demo guilds ----------------------------------------------------------
  // WarcraftLogs ranks combat logs; this ranks GUILD PROGRESS overall, broken
  // into categories. Each category is a 0-100 score; overall is the weighted
  // mean, so a guild that only PvPs does not top a levelling ladder.
  var GUILD_CATS = [
    { key: "levelling", label: "Levelling pace", w: 3 },
    { key: "dungeons", label: "Dungeons of the Nine", w: 3 },
    { key: "pvp", label: "PvP", w: 2 },
    { key: "hardcore", label: "Hardcore survival", w: 1 },
    { key: "quests", label: "Quests", w: 1 }
  ];
  function mkGuild(name, tag, members, sc, roster) {
    var total = 0, wsum = 0;
    GUILD_CATS.forEach(function (c) { total += (sc[c.key] || 0) * c.w; wsum += c.w; });
    return { name: name, tag: tag, members: members, cats: sc,
             overall: total / wsum, roster: roster };
  }
  var GUILDS = [
    mkGuild("Eternal Vanguard", "EV", 24, { levelling: 91, dungeons: 88, pvp: 64, hardcore: 70, quests: 84 }, ["Athgaar", "Mutuwa", "Rickmyrolls", "Willamok"]),
    mkGuild("Skyborne Pact", "SKY", 15, { levelling: 78, dungeons: 92, pvp: 41, hardcore: 88, quests: 71 }, ["Mikhaeraw", "Eldritch", "Kizerine"]),
    mkGuild("Ashes of Lordaeron", "ASH", 14, { levelling: 66, dungeons: 71, pvp: 90, hardcore: 35, quests: 62 }, ["Pain", "Yezin", "Xynnz", "Roach"]),
    mkGuild("Riverglade Company", "RGC", 12, { levelling: 52, dungeons: 44, pvp: 22, hardcore: 95, quests: 90 }, ["Flower", "Goldy", "Sne", "Naty"])
  ];

  // ---- tiny utils -----------------------------------------------------------
  function $(id) { return document.getElementById(id); }
  function esc(s) { return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
  function cc(cls) { return CLASS_COLOUR[cls] || "var(--text)"; }
  function hm(sec) {
    var h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
    return h > 0 ? h + "h " + m + "m" : m + "m";
  }
  function pctile(v, list) {           // n-1 divisor, like the 3.3.5 worker
    var below = 0, n = list.length;
    if (n <= 1) return null;
    for (var i = 0; i < n; i++) if (list[i] < v) below++;
    return Math.max(0, Math.min(100, (below / (n - 1)) * 100));
  }
  function bandVar(p) {
    if (p == null) return "var(--q-common)";
    var t = [0, 25, 50, 75, 95, 99, 100], i = 0;
    for (var k = 0; k < t.length; k++) if (p >= t[k]) i = k;
    return "var(" + BANDS[i] + ")";
  }
  function demoOn() {
    try { return localStorage.getItem("lpf-demo") !== "off"; } catch (e) { return true; }
  }

  // ---- countdown ------------------------------------------------------------
  function tickCountdown() {
    var now = Date.now(), target, kick, note, phase;
    if (now < BETA) { target = BETA; kick = "The <b>beta</b> opens in"; phase = "PRE-BETA"; note = "Beta Sept 17 to Oct 21, level cap 30. Launch Nov 4 (times estimated)"; }
    else if (now < LAUNCH) { target = LAUNCH; kick = "<b>Forever</b> launches in"; phase = "BETA. CAP 30"; note = "Beta is live until Oct 21. launch Nov 4 (times estimated)"; }
    else { target = null; kick = "<b>Forever</b> is live"; phase = "LIVE. CAP 60"; note = ""; }
    $("count-kick").innerHTML = kick;
    $("phase-chip").textContent = phase;
    $("count-note").textContent = note;
    if (!target) { $("count-grid").hidden = true; return; }
    var s = Math.max(0, Math.floor((target - now) / 1000));
    $("cd-d").textContent = Math.floor(s / 86400);
    $("cd-h").textContent = String(Math.floor(s / 3600) % 24).padStart(2, "0");
    $("cd-m").textContent = String(Math.floor(s / 60) % 60).padStart(2, "0");
    $("cd-s").textContent = String(s % 60).padStart(2, "0");
  }

  // ---- views ----------------------------------------------------------------
  function nameCell(c) {
    return '<td><span class="name" style="--cc:' + cc(c.cls) + '">' + esc(c.name) + "</span>" +
      '<span class="meta">' + esc(c.realm) + "</span></td>";
  }
  function head(cols) {
    return "<thead><tr>" + cols.map(function (h) {
      return '<th class="' + (h[1] || "") + '">' + h[0] + "</th>";
    }).join("") + "</tr></thead>";
  }
  function demoFlag() { return '<p class="demo-flag">Demo data: nothing real yet</p>'; }

  var VIEWS = {
    levelling: {
      sub: "The race to " + CAP + ": highest level first, time played breaks ties. The coloured parse is your levels-per-hour percentile among everyone on the ladder.",
      render: function (d) {
        var rates = d.map(function (c) { return c.lph; });
        var rows = d.slice().sort(function (a, b) { return b.level - a.level || a.seconds - b.seconds; })
          .map(function (c, i) {
            var p = pctile(c.lph, rates), v = bandVar(p);
            return '<tr data-c="' + esc(c.name) + '"><td class="rank">' + (i + 1) + "</td>" + nameCell(c) +
              '<td class="r lvl">' + c.level + "</td>" +
              '<td class="r">' + hm(c.seconds) + "</td>" +
              '<td class="r">' + c.lph.toFixed(2) + "</td>" +
              '<td class="r pct" style="--c:' + v + '">' + (p == null ? "" : Math.round(p)) + "</td></tr>";
          }).join("");
        return '<table class="ranktable">' + head([["#", "rank"], ["Character"], ["Lvl", "r"], ["Time played", "r"], ["Lvl/hr", "r"], ["Parse", "r"]]) + "<tbody>" + rows + "</tbody></table>";
      }
    },
    hardcore: {
      sub: "One life. The ladder ranks the living by level; the fallen keep their place in the record at the level death found them.",
      render: function (d) {
        var rows = d.slice().sort(function (a, b) { return (b.alive - a.alive) || b.level - a.level || a.seconds - b.seconds; })
          .map(function (c, i) {
            return '<tr data-c="' + esc(c.name) + '"><td class="rank">' + (i + 1) + "</td>" + nameCell(c) +
              '<td class="r lvl">' + c.level + "</td>" +
              '<td class="r">' + hm(c.seconds) + "</td>" +
              '<td class="r">' + (c.alive ? '<span class="alive">Alive</span>' : '<span class="dead">Fallen</span>') + "</td></tr>";
          }).join("");
        return '<table class="ranktable">' + head([["#", "rank"], ["Character"], ["Lvl", "r"], ["Time played", "r"], ["Status", "r"]]) + "<tbody>" + rows + "</tbody></table>";
      }
    },
    pvp: {
      sub: "Honorable kills, vanilla rank titles, and an honest K/D. Nemesis tracking follows once the beta shows what the combat log carries.",
      render: function (d) {
        var hks = d.map(function (c) { return c.hks; });
        var rows = d.slice().sort(function (a, b) { return b.hks - a.hks; })
          .map(function (c, i) {
            var p = pctile(c.hks, hks), v = bandVar(p);
            var rank = PVP_RANKS[Math.min(PVP_RANKS.length - 1, Math.floor(c.hks / 18))];
            return '<tr data-c="' + esc(c.name) + '"><td class="rank">' + (i + 1) + "</td>" + nameCell(c) +
              '<td class="r">' + esc(rank) + "</td>" +
              '<td class="r">' + c.hks + "</td>" +
              '<td class="r">' + (c.pvpDeaths > 0 ? (c.kills / c.pvpDeaths).toFixed(2) : c.kills.toFixed(0)) + "</td>" +
              '<td class="r pct" style="--c:' + v + '">' + (p == null ? "" : Math.round(p)) + "</td></tr>";
          }).join("");
        return '<table class="ranktable">' + head([["#", "rank"], ["Character"], ["Rank", "r"], ["HKs", "r"], ["K/D", "r"], ["Parse", "r"]]) + "<tbody>" + rows + "</tbody></table>";
      }
    },
    progression: {
      sub: "The whole character, not one number: dungeons of the nine cleared, quests done, gear. Weights get honest once the beta shows what an addon can read.",
      render: function (d) {
        var score = function (c) { return c.level * 10 + c.dungeons * 14 + c.quests / 10 + c.ilvl; };
        var all = d.map(score);
        var rows = d.slice().sort(function (a, b) { return score(b) - score(a); })
          .map(function (c, i) {
            var p = pctile(score(c), all), v = bandVar(p);
            return '<tr data-c="' + esc(c.name) + '"><td class="rank">' + (i + 1) + "</td>" + nameCell(c) +
              '<td class="r lvl">' + c.level + "</td>" +
              '<td class="r">' + c.dungeons + "/9</td>" +
              '<td class="r">' + c.quests + "</td>" +
              '<td class="r">' + c.ilvl + "</td>" +
              '<td class="r pct" style="--c:' + v + '">' + (p == null ? "" : Math.round(p)) + "</td></tr>";
          }).join("");
        return '<table class="ranktable">' + head([["#", "rank"], ["Character"], ["Lvl", "r"], ["Dungeons", "r"], ["Quests", "r"], ["Gear", "r"], ["Parse", "r"]]) + "<tbody>" + rows + "</tbody></table>";
      }
    }
  ,
    guilds: {
      sub: "Guild progress overall, not one lucky log: levelling pace, the nine dungeons, PvP, hardcore survival and quests, weighted into one score. Click a guild for the breakdown.",
      render: function () {
        var pool = GUILDS;
        if (query) {
          var q = query.toLowerCase();
          pool = GUILDS.filter(function (g) {
            return g.name.toLowerCase().indexOf(q) !== -1 ||
              g.roster.some(function (m) { return m.toLowerCase().indexOf(q) !== -1; });
          });
        }
        if (!pool.length) return '<div class="empty"><h3>No guild or member called <span>\u201c' + esc(query) + '\u201d</span></h3></div>';
        var all = GUILDS.map(function (g) { return g.overall; });
        var rows = pool.slice().sort(function (a, b) { return b.overall - a.overall; })
          .map(function (g, i) {
            var p = pctile(g.overall, all), v = bandVar(p);
            return '<tr data-g="' + esc(g.name) + '"><td class="rank">' + (i + 1) + "</td>" +
              '<td><span class="name">&lt;<span class="gtag">' + esc(g.name) + "</span>&gt;</span>" +
              '<span class="meta">' + g.members + " members</span></td>" +
              '<td class="r lvl">' + g.overall.toFixed(1) + "</td>" +
              '<td class="r">' + g.cats.levelling + "</td>" +
              '<td class="r">' + g.cats.dungeons + "</td>" +
              '<td class="r">' + g.cats.pvp + "</td>" +
              '<td class="r pct" style="--c:' + v + '">' + (p == null ? "" : Math.round(p)) + "</td></tr>";
          }).join("");
        return '<table class="ranktable">' + head([["#", "rank"], ["Guild"], ["Overall", "r"], ["Lvl", "r"], ["Dng", "r"], ["PvP", "r"], ["Parse", "r"]]) + "<tbody>" + rows + "</tbody></table>";
      }
    }
  };

  function guildInsight(g) {
    var bars = GUILD_CATS.map(function (c) {
      var val = g.cats[c.key] || 0, v = bandVar(val);
      return "<li><b>" + esc(c.label) + '</b><i style="--w:' + Math.max(4, val) + "%;--c:" + v + '"></i><u style="--c:' + v + '">' + val + "</u></li>";
    }).join("");
    var roster = g.roster.map(function (n) {
      var c = DEMO.filter(function (x) { return x.name === n; })[0];
      return '<span style="--cc:' + (c ? cc(c.cls) : "inherit") + '">' + esc(n) + "</span>";
    }).join("");
    $("insight-body").innerHTML =
      '<h2 class="in-name">&lt;<span class="gtag">' + esc(g.name) + "</span>&gt;</h2>" +
      '<div class="in-meta"><span class="chip">' + g.members + ' members</span><span class="chip">overall ' + g.overall.toFixed(1) + '</span><span class="demo-flag">Demo</span></div>' +
      '<p class="in-h">Category breakdown: colour is the score band</p>' +
      '<ol class="gbars">' + bars + "</ol>" +
      '<p class="in-h">Notable members</p><div class="roster">' + roster + "</div>" +
      '<p class="in-note">Weights: levelling and dungeons 3, PvP 2, hardcore and quests 1. Real categories get argued about in the open once uploads exist.</p>';
    $("insight").hidden = false;
  }

  // ---- character insight ----------------------------------------------------
  function insight(c) {
    // Percentile per level against everyone else's time at that level.
    var bars = "";
    var worst = Math.max.apply(null, c.perLevel.length ? c.perLevel : [1]);
    for (var i = 0; i < c.perLevel.length; i++) {
      var mine = c.perLevel[i], others = [];
      for (var j = 0; j < DEMO.length; j++) {
        var o = DEMO[j];
        if (o.perLevel[i] != null) others.push(3600 / o.perLevel[i]);
      }
      var p = pctile(3600 / mine, others), v = bandVar(p);
      bars += "<li><b>" + (i + 1) + "&rarr;" + (i + 2) + "</b>" +
        '<i style="--w:' + Math.max(4, (mine / worst) * 100) + "%;--c:" + v + '"></i>' +
        "<u>" + hm(mine) + "</u></li>";
    }
    var toCap = CAP - c.level;
    var proj = toCap > 0 && c.lph > 0
      ? "At this pace: level " + CAP + " in about " + hm(Math.round(toCap / c.lph * 3600)) + " more played time."
      : "At the cap.";
    $("insight-body").innerHTML =
      '<h2 class="in-name" style="--cc:' + cc(c.cls) + '">' + esc(c.name) + "</h2>" +
      '<div class="in-meta"><span class="chip">' + esc(c.cls.toLowerCase()) + '</span><span class="chip">' + esc(c.realm) + '</span><span class="chip">' + (c.alive ? "alive" : "fallen") + '</span>' + (c.tag ? '<span class="chip chip-gold">' + esc(c.tag) + "</span>" : "") + '<span class="demo-flag">Demo</span></div>' +
      '<div class="in-stats">' +
        "<div><b>" + c.level + "</b><span>level</span></div>" +
        "<div><b>" + hm(c.seconds) + "</b><span>time played</span></div>" +
        "<div><b>" + c.lph.toFixed(2) + "</b><span>lvl / hr</span></div>" +
        "<div><b>" + c.deaths + "</b><span>deaths</span></div>" +
        "<div><b>" + c.hks + "</b><span>honor kills</span></div>" +
        "<div><b>" + c.dungeons + "/9</b><span>dungeons</span></div>" +
      "</div>" +
      '<p class="in-h">Every level, timed: colour is the percentile at that level</p>' +
      '<ol class="lvlbars">' + bars + "</ol>" +
      '<p class="in-note">' + proj + " Real insights use exactly this layout once uploads exist.</p>";
    $("insight").hidden = false;
  }

  // ---- rendering ------------------------------------------------------------
  var view = "levelling";
  function filtered() {
    if (!query) return DEMO;
    var q = query.toLowerCase();
    return DEMO.filter(function (c) { return c.name.toLowerCase().indexOf(q) !== -1; });
  }
  function render() {
    var v = VIEWS[view];
    $("board-sub").textContent = v.sub;
    $("cap-note").innerHTML = Date.now() < LAUNCH
      ? "Beta caps at <b>level 30</b>: every board ranks 1&ndash;30 until launch."
      : "Launched: the ladder runs to <b>level 60</b>.";
    var b = $("board");
    if (!demoOn()) {
      b.innerHTML = '<div class="empty"><h3>No uploads have <span>happened yet</span></h3>' +
        "<p>The game is not out. The countdown above is real; everything else waits for it.</p>" +
        '<p>Curious how it will look? The gear (top right) switches the demo back on.</p></div>';
      return;
    }
    var data = filtered();
    if (!data.length && view !== "guilds") {
      b.innerHTML = '<div class="empty"><h3>No one called <span>\u201c' + esc(query) + '\u201d</span></h3>' +
        "<p>" + DEMO.length + " players are on the ladder. Try fewer letters.</p></div>";
      return;
    }
    b.classList.remove("is-drawn");
    b.innerHTML = demoFlag() + v.render(data);
    requestAnimationFrame(function () { requestAnimationFrame(function () { b.classList.add("is-drawn"); }); });
    var rows = b.querySelectorAll("tr[data-c]");
    Array.prototype.forEach.call(rows, function (r) {
      r.addEventListener("click", function () {
        var c = DEMO.filter(function (x) { return x.name === r.getAttribute("data-c"); })[0];
        if (c) insight(c);
      });
    });
    var grows = b.querySelectorAll("tr[data-g]");
    Array.prototype.forEach.call(grows, function (r) {
      r.addEventListener("click", function () {
        var g = GUILDS.filter(function (x) { return x.name === r.getAttribute("data-g"); })[0];
        if (g) guildInsight(g);
      });
    });
  }

  // ---- wiring ---------------------------------------------------------------
  document.addEventListener("DOMContentLoaded", function () {
    tickCountdown(); setInterval(tickCountdown, 1000);

    var sel = $("view-select");
    if (sel) sel.addEventListener("change", function () { view = sel.value; render(); });

    var search = $("search");
    if (search) {
      var deb = null;
      search.addEventListener("input", function () {
        clearTimeout(deb);
        deb = setTimeout(function () { query = search.value.trim(); render(); }, 120);
      });
    }

    var gear = $("gear"), settings = $("settings"), toggle = $("demo-toggle");
    toggle.checked = demoOn();
    gear.addEventListener("click", function () {
      settings.hidden = !settings.hidden;
      gear.setAttribute("aria-expanded", settings.hidden ? "false" : "true");
    });
    document.addEventListener("click", function (e) {
      if (!settings.hidden && !settings.contains(e.target) && e.target !== gear) settings.hidden = true;
    });
    toggle.addEventListener("change", function () {
      try { localStorage.setItem("lpf-demo", toggle.checked ? "on" : "off"); } catch (e) {}
      render();
    });

    $("insight-x").addEventListener("click", function () { $("insight").hidden = true; });
    $("insight").addEventListener("click", function (e) { if (e.target === $("insight")) $("insight").hidden = true; });
    document.addEventListener("keydown", function (e) { if (e.key === "Escape") $("insight").hidden = true; });

    render();
  });
})();
