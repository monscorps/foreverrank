/* LevelPace Forever — plan-stage board. No framework, no build step.
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

  // ---- demo characters (deterministic, obviously invented) ------------------
  function mk(name, cls, level, pace, deaths, hks, dungeons, alive) {
    // pace: rough seconds per level at level 10, grows ~9%/level
    var perLevel = [], total = 0;
    for (var l = 1; l < level; l++) {
      var s = Math.round(pace * Math.pow(1.09, l - 10) * (1 + 0.18 * Math.sin(l * 2.3 + name.length)));
      if (s < 120) s = 120;
      perLevel.push(s); total += s;
    }
    return { name: name, cls: cls, level: level, perLevel: perLevel, seconds: total,
             lph: total > 0 ? (level - 1) / (total / 3600) : 0, deaths: deaths, hks: hks,
             kills: Math.round(hks * 1.18), pvpDeaths: Math.round(hks / (1.1 + name.length % 3)),
             dungeons: dungeons, quests: 40 + level * 9 + (name.length * 7) % 60,
             ilvl: 8 + Math.round(level * 0.85), alive: alive, realm: "Beta 1" };
  }
  var DEMO = [
    mk("Rickmyrolls", "PRIEST", 30, 680, 2, 214, 6, true),
    mk("Thundermaw", "SHAMAN", 30, 760, 5, 158, 5, true),
    mk("Skydancer", "HUNTER", 29, 705, 1, 96, 4, true),
    mk("Grimveil", "WARLOCK", 28, 810, 7, 61, 4, true),
    mk("Oakenheart", "DRUID", 27, 890, 3, 44, 3, true),
    mk("Sunblade", "PALADIN", 26, 940, 0, 39, 3, true),
    mk("Vexley", "ROGUE", 24, 870, 9, 122, 2, false),
    mk("Emberlyn", "MAGE", 22, 795, 4, 71, 2, true),
    mk("Ironjaw", "WARRIOR", 19, 1010, 6, 18, 1, false),
    mk("Whisperwind", "PRIEST", 14, 930, 1, 5, 1, true)
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
    if (now < BETA) { target = BETA; kick = "The <b>beta</b> opens in"; phase = "PRE-BETA"; note = "Beta Sept 17 – Oct 21, level cap 30 · Launch Nov 4 (times estimated)"; }
    else if (now < LAUNCH) { target = LAUNCH; kick = "<b>Forever</b> launches in"; phase = "BETA · CAP 30"; note = "Beta is live until Oct 21 · launch Nov 4 (times estimated)"; }
    else { target = null; kick = "<b>Forever</b> is live"; phase = "LIVE · CAP 60"; note = ""; }
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
  function demoFlag() { return '<p class="demo-flag">Demo data — nothing real yet</p>'; }

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
              '<td class="r pct" style="--c:' + v + '">' + (p == null ? "—" : Math.round(p)) + "</td></tr>";
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
              '<td class="r pct" style="--c:' + v + '">' + (p == null ? "—" : Math.round(p)) + "</td></tr>";
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
              '<td class="r pct" style="--c:' + v + '">' + (p == null ? "—" : Math.round(p)) + "</td></tr>";
          }).join("");
        return '<table class="ranktable">' + head([["#", "rank"], ["Character"], ["Lvl", "r"], ["Dungeons", "r"], ["Quests", "r"], ["Gear", "r"], ["Parse", "r"]]) + "<tbody>" + rows + "</tbody></table>";
      }
    }
  };

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
      '<div class="in-meta"><span class="chip">' + esc(c.cls.toLowerCase()) + '</span><span class="chip">' + esc(c.realm) + '</span><span class="chip">' + (c.alive ? "alive" : "fallen") + '</span><span class="demo-flag">Demo</span></div>' +
      '<div class="in-stats">' +
        "<div><b>" + c.level + "</b><span>level</span></div>" +
        "<div><b>" + hm(c.seconds) + "</b><span>time played</span></div>" +
        "<div><b>" + c.lph.toFixed(2) + "</b><span>lvl / hr</span></div>" +
        "<div><b>" + c.deaths + "</b><span>deaths</span></div>" +
        "<div><b>" + c.hks + "</b><span>honor kills</span></div>" +
        "<div><b>" + c.dungeons + "/9</b><span>dungeons</span></div>" +
      "</div>" +
      '<p class="in-h">Every level, timed — colour is the percentile at that level</p>' +
      '<ol class="lvlbars">' + bars + "</ol>" +
      '<p class="in-note">' + proj + " Real insights use exactly this layout once uploads exist.</p>";
    $("insight").hidden = false;
  }

  // ---- rendering ------------------------------------------------------------
  var view = "levelling";
  function render() {
    var v = VIEWS[view];
    $("board-sub").textContent = v.sub;
    $("cap-note").innerHTML = Date.now() < LAUNCH
      ? "Beta caps at <b>level 30</b> — every board ranks 1&ndash;30 until launch."
      : "Launched — the ladder runs to <b>level 60</b>.";
    var b = $("board");
    if (!demoOn()) {
      b.innerHTML = '<div class="empty"><h3>No uploads have <span>happened yet</span></h3>' +
        "<p>The game is not out. The countdown above is real; everything else waits for it.</p>" +
        '<p>Curious how it will look? The gear (top right) switches the demo back on.</p></div>';
      return;
    }
    b.classList.remove("is-drawn");
    b.innerHTML = demoFlag() + v.render(DEMO);
    requestAnimationFrame(function () { requestAnimationFrame(function () { b.classList.add("is-drawn"); }); });
    var rows = b.querySelectorAll("tr[data-c]");
    Array.prototype.forEach.call(rows, function (r) {
      r.addEventListener("click", function () {
        var c = DEMO.filter(function (x) { return x.name === r.getAttribute("data-c"); })[0];
        if (c) insight(c);
      });
    });
  }

  // ---- wiring ---------------------------------------------------------------
  document.addEventListener("DOMContentLoaded", function () {
    tickCountdown(); setInterval(tickCountdown, 1000);

    var tabs = document.querySelectorAll(".tab[data-view]");
    Array.prototype.forEach.call(tabs, function (t) {
      t.addEventListener("click", function () {
        Array.prototype.forEach.call(tabs, function (o) { o.classList.remove("is-active"); o.setAttribute("aria-selected", "false"); });
        t.classList.add("is-active"); t.setAttribute("aria-selected", "true");
        view = t.getAttribute("data-view"); render();
      });
    });

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
