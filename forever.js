/* LevelPace Forever: plan-stage board. No framework, no build step.
 * Until the game exists the board opens on an explainer; placeholder rows
 * are one click (or ?preview=1) away, and the gear toggles the same switch.
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
  // Stats are seeded from each name so the ladder is stable across reloads,
  // and invented, like everything here, until the game exists.
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
  // Primary professions, icon per trade. Two each, like the game hands out.
  var PROFS = [
    ["Alchemy", "trade_alchemy"], ["Blacksmithing", "trade_blacksmithing"],
    ["Enchanting", "trade_engraving"], ["Engineering", "trade_engineering"],
    ["Herbalism", "spell_nature_naturetouchgrow"], ["Leatherworking", "inv_misc_armorkit_17"],
    ["Mining", "trade_mining"], ["Skinning", "inv_misc_pelt_wolf_01"], ["Tailoring", "trade_tailoring"]
  ];
  function profCap(level) { return level >= 35 ? 300 : level >= 20 ? 225 : level >= 10 ? 150 : 75; }
  // Four serverless servers. Names unknown until Blizzard says; types are the plan.
  var REALMS = ["Normal", "PvP", "Hardcore", "RP"];
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
    var out = mk(name, ov.cls || cls, ov.level != null ? ov.level : level, ov.pace || pace,
              ov.deaths != null ? ov.deaths : deaths, ov.hks != null ? ov.hks : hks,
              ov.dungeons != null ? ov.dungeons : dungeons, ov.alive != null ? ov.alive : alive, ov.tag);
    out.realm = ov.realm || REALMS[Math.floor(r() * REALMS.length)];
    var p1 = Math.floor(r() * PROFS.length), p2 = (p1 + 1 + Math.floor(r() * (PROFS.length - 1))) % PROFS.length;
    var capSk = profCap(out.level);
    out.profs = [
      { n: PROFS[p1][0], i: PROFS[p1][1], sk: Math.max(1, Math.round(capSk * (0.45 + 0.55 * r()))), cap: capSk },
      { n: PROFS[p2][0], i: PROFS[p2][1], sk: Math.max(1, Math.round(capSk * (0.30 + 0.55 * r()))), cap: capSk }
    ];
    return out;
  }
  // Twenty invented characters. Forever gives every character a first and a
  // second name, so the placeholders do too: some played in character, some
  // one-life, some for the joke. Every realm and class is represented.
  var DEMO = [
    gen("Aldric Stormhollow", { cls: "PALADIN", level: 27, pace: 640, dungeons: 6, realm: "RP", alive: true, tag: "Never breaks character" }),
    gen("Seraphine Duskwhisper", { cls: "PRIEST", level: 24, realm: "RP", alive: true }),
    gen("Morwen Ashgrove", { cls: "WARLOCK", level: 22, realm: "RP", alive: true, tag: "Runs the Undercity book club" }),
    gen("Thalindra Moonbrook", { cls: "DRUID", level: 26, realm: "RP", alive: true }),
    gen("Garrosk Emberhide", { cls: "SHAMAN", level: 19, realm: "RP", alive: true }),
    gen("Hilde Lastlight", { cls: "PRIEST", level: 30, pace: 700, deaths: 0, dungeons: 9, realm: "Hardcore", alive: true, tag: "Zero deaths, zero risks" }),
    gen("Varek Deathless", { cls: "WARRIOR", level: 28, pace: 610, deaths: 0, realm: "Hardcore", alive: true }),
    gen("Rook Stillbreathing", { cls: "ROGUE", level: 25, deaths: 0, realm: "Hardcore", alive: true, tag: "Still breathing" }),
    gen("Oskar Onelife", { cls: "HUNTER", level: 17, realm: "Hardcore", alive: false, tag: "Fell at 17 in the Ruins of Lordaeron" }),
    gen("Nyx Nightsworn", { cls: "MAGE", level: 22, realm: "Hardcore", alive: false, tag: "Pulled two packs, met the third" }),
    gen("Tamsin Carefulstep", { cls: "PALADIN", level: 21, deaths: 0, realm: "Hardcore", alive: true }),
    gen("Brannoc Ironvein", { cls: "WARRIOR", level: 30, pace: 580, hks: 240, dungeons: 8, realm: "PvP", alive: true }),
    gen("Crit Happens", { cls: "ROGUE", level: 29, pace: 600, hks: 255, realm: "PvP", alive: true, tag: "Top of the PvP ladder" }),
    gen("Sir Loin", { cls: "DRUID", level: 26, hks: 150, realm: "PvP", alive: true, tag: "A Tauren of taste" }),
    gen("Arrow Dynamic", { cls: "HUNTER", level: 27, hks: 180, realm: "PvP", alive: true }),
    gen("Gnome Chomsky", { cls: "MAGE", level: 23, hks: 90, realm: "PvP", alive: true, tag: "Theorycrafter" }),
    gen("Tank Sinatra", { cls: "WARRIOR", level: 26, dungeons: 9, realm: "Normal", alive: true, tag: "Does it his way" }),
    gen("Barry Hotfix", { cls: "SHAMAN", level: 20, realm: "Normal", alive: true }),
    gen("Holly Wood", { cls: "DRUID", level: 18, realm: "Normal", alive: true }),
    gen("Justin Case", { cls: "PRIEST", level: 24, dungeons: 8, realm: "Normal", alive: true, tag: "Heals just in case" })
  ];
  var query = "";
  var realmFilter = "all";
  var PAGE = 50;
  var page = 0;
  // Ranks and percentiles come from the WHOLE pool; only the display is cut.
  function pageSlice(arr) {
    var pages = Math.max(1, Math.ceil(arr.length / PAGE));
    if (page >= pages) page = pages - 1;
    if (page < 0) page = 0;
    return arr.slice(page * PAGE, (page + 1) * PAGE);
  }
  function pager(total) {
    if (total <= PAGE) return "";
    var pages = Math.ceil(total / PAGE);
    return '<div class="pager">' +
      '<button type="button" data-pg="-1"' + (page === 0 ? " disabled" : "") + ">&lsaquo; Prev</button>" +
      "<span>Page " + (page + 1) + " of " + pages + ". " + total + " ranked</span>" +
      '<button type="button" data-pg="1"' + (page >= pages - 1 ? " disabled" : "") + ">Next &rsaquo;</button></div>";
  }

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
  function mkGuild(name, tag, members, sc, roster, realm) {
    var total = 0, wsum = 0;
    GUILD_CATS.forEach(function (c) { total += (sc[c.key] || 0) * c.w; wsum += c.w; });
    return { name: name, tag: tag, members: members, cats: sc,
             overall: total / wsum, roster: roster, realm: realm || "Normal" };
  }
  var GUILDS = [
    mkGuild("Eternal Vanguard", "EV", 24, { levelling: 91, dungeons: 88, pvp: 94, hardcore: 20, quests: 72 }, ["Brannoc Ironvein", "Crit Happens", "Arrow Dynamic"], "PvP"),
    mkGuild("Skyborne Pact", "SKY", 15, { levelling: 78, dungeons: 92, pvp: 31, hardcore: 30, quests: 71 }, ["Tank Sinatra", "Justin Case", "Barry Hotfix", "Holly Wood"], "Normal"),
    mkGuild("Ashes of Lordaeron", "ASH", 14, { levelling: 66, dungeons: 61, pvp: 86, hardcore: 25, quests: 62 }, ["Sir Loin", "Gnome Chomsky"], "PvP"),
    mkGuild("Riverglade Company", "RGC", 12, { levelling: 58, dungeons: 64, pvp: 12, hardcore: 40, quests: 93 }, ["Aldric Stormhollow", "Seraphine Duskwhisper", "Morwen Ashgrove", "Thalindra Moonbrook", "Garrosk Emberhide"], "RP"),
    mkGuild("Gravebound", "GRV", 11, { levelling: 70, dungeons: 66, pvp: 8, hardcore: 97, quests: 74 }, ["Hilde Lastlight", "Varek Deathless", "Rook Stillbreathing", "Tamsin Carefulstep", "Oskar Onelife", "Nyx Nightsworn"], "Hardcore")
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
  // Placeholder preview is opt-in: the explainer is what a first visit sees.
  var preview = false;
  try { preview = localStorage.getItem("fr-preview") === "on"; } catch (e) {}
  function demoOn() { return preview; }
  function setPreview(on) {
    preview = !!on;
    try { localStorage.setItem("fr-preview", preview ? "on" : "off"); } catch (e) {}
    var t = $("demo-toggle");
    if (t) t.checked = preview;
  }

  // ---- countdown ------------------------------------------------------------
  function tickCountdown() {
    var now = Date.now(), target, kick, note, phase;
    if (now < BETA) { target = BETA; kick = "The <b>beta</b> opens in"; phase = "PRE-BETA"; note = "Beta Sept 17 to Oct 22, level cap 30. Launch Nov 4 (times estimated)"; }
    else if (now < LAUNCH) { target = LAUNCH; kick = "<b>Forever</b> launches in"; phase = "BETA. CAP 30"; note = "Beta is live until Oct 22. launch Nov 4 (times estimated)"; }
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

  function progScore(c) { return c.level * 10 + c.dungeons * 14 + c.quests / 10 + c.ilvl + (c.profs ? (c.profs[0].sk + c.profs[1].sk) / 12 : 0); }
  function profCell(c) {
    if (!c.profs) return "";
    return c.profs.map(function (pr) {
      return '<img class="profico" src="https://wow.zamimg.com/images/wow/icons/large/' + pr.i + '.jpg" alt="" title="' + esc(pr.n) + " " + pr.sk + "/" + pr.cap + '"> ' + pr.sk;
    }).join(" ");
  }
  var VIEWS = {
    professions: {
      sub: "The tradesfolk's ladder: both primaries added up. Camps made professions part of progress, so the ladder treats them that way.",
      render: function (d) {
        var sum = function (c) { return c.profs ? c.profs[0].sk + c.profs[1].sk : 0; };
        var all = d.map(sum);
        var sorted = d.slice().sort(function (a, b) { return sum(b) - sum(a) || b.level - a.level; });
        var rows = pageSlice(sorted).map(function (c, i) {
            var p = pctile(sum(c), all), v = bandVar(p);
            return '<tr data-c="' + esc(c.name) + '"><td class="rank">' + (page * PAGE + i + 1) + "</td>" + nameCell(c) +
              '<td class="r lvl">' + c.level + "</td>" +
              '<td class="r">' + profCell(c) + "</td>" +
              '<td class="r">' + sum(c) + "</td>" +
              '<td class="r pct" style="--c:' + v + '">' + (p == null ? "" : Math.round(p)) + '</td><td class="go">&rsaquo;</td></tr>';
          }).join("");
        return '<table class="ranktable">' + head([["#", "rank"], ["Character"], ["Lvl", "r"], ["Trades", "r"], ["Total", "r"], ["Parse", "r"], ["", "go"]]) + "<tbody>" + rows + "</tbody></table>" + pager(sorted.length);
      }
    },
    levelling: {
      sub: "The race to " + CAP + ": highest level first, time played breaks ties. The coloured parse is your pace against everyone at your level.",
      render: function (d) {
        var byLvl = {};
        d.forEach(function (c) { (byLvl[c.level] = byLvl[c.level] || []).push(c.lph); });
        var sorted = d.slice().sort(function (a, b) { return b.level - a.level || a.seconds - b.seconds; });
        var rows = pageSlice(sorted).map(function (c, i) {
            var p = pctile(c.lph, byLvl[c.level]), v = bandVar(p);
            return '<tr data-c="' + esc(c.name) + '"><td class="rank">' + (page * PAGE + i + 1) + "</td>" + nameCell(c) +
              '<td class="r lvl">' + c.level + "</td>" +
              '<td class="r xs">' + c.lph.toFixed(2) + "</td>" +
              '<td class="r pct" style="--c:' + v + '">' + (p == null ? "" : Math.round(p)) + '</td><td class="go">&rsaquo;</td></tr>';
          }).join("");
        return '<table class="ranktable">' + head([["#", "rank"], ["Character"], ["Lvl", "r"], ["Lvl/hr", "r xs"], ["Parse", "r"], ["", "go"]]) + "<tbody>" + rows + "</tbody></table>" + pager(sorted.length);
      }
    },
    hardcore: {
      sub: "One life. The ladder ranks the living by level; the fallen keep their place in the record at the level death found them.",
      render: function (d) {
        var sorted = d.slice().sort(function (a, b) { return (b.alive - a.alive) || b.level - a.level || a.seconds - b.seconds; });
        var rows = pageSlice(sorted).map(function (c, i) {
            return '<tr data-c="' + esc(c.name) + '"><td class="rank">' + (page * PAGE + i + 1) + "</td>" + nameCell(c) +
              '<td class="r lvl">' + c.level + "</td>" +
              '<td class="r">' + (c.alive ? '<span class="alive">Alive</span>' : '<span class="dead">Fallen</span>') + '</td><td class="go">&rsaquo;</td></tr>';
          }).join("");
        return '<table class="ranktable">' + head([["#", "rank"], ["Character"], ["Lvl", "r"], ["Status", "r"], ["", "go"]]) + "<tbody>" + rows + "</tbody></table>" + pager(sorted.length);
      }
    },
    pvp: {
      sub: "Honorable kills, vanilla rank titles, and an honest K/D. Nemesis tracking follows once the beta shows what the combat log carries.",
      render: function (d) {
        var hks = d.map(function (c) { return c.hks; });
        var sorted = d.slice().sort(function (a, b) { return b.hks - a.hks; });
        var rows = pageSlice(sorted).map(function (c, i) {
            var p = pctile(c.hks, hks), v = bandVar(p);
            var rank = PVP_RANKS[Math.min(PVP_RANKS.length - 1, Math.floor(c.hks / 18))];
            return '<tr data-c="' + esc(c.name) + '"><td class="rank">' + (page * PAGE + i + 1) + "</td>" + nameCell(c) +
              '<td class="r xs">' + esc(rank) + "</td>" +
              '<td class="r">' + c.hks + "</td>" +
              '<td class="r">' + (c.pvpDeaths > 0 ? (c.kills / c.pvpDeaths).toFixed(2) : c.kills.toFixed(0)) + "</td>" +
              '<td class="r pct" style="--c:' + v + '">' + (p == null ? "" : Math.round(p)) + '</td><td class="go">&rsaquo;</td></tr>';
          }).join("");
        return '<table class="ranktable">' + head([["#", "rank"], ["Character"], ["Rank", "r xs"], ["HKs", "r"], ["K/D", "r"], ["Parse", "r"], ["", "go"]]) + "<tbody>" + rows + "</tbody></table>" + pager(sorted.length);
      }
    },
    progression: {
      sub: "The whole character, not one number: dungeons of the nine cleared, quests done, gear. Weights get honest once the beta shows what an addon can read.",
      render: function (d) {
        var score = progScore;
        var all = d.map(score);
        var sorted = d.slice().sort(function (a, b) { return score(b) - score(a); });
        var rows = pageSlice(sorted).map(function (c, i) {
            var p = pctile(score(c), all), v = bandVar(p);
            return '<tr data-c="' + esc(c.name) + '"><td class="rank">' + (page * PAGE + i + 1) + "</td>" + nameCell(c) +
              '<td class="r lvl">' + c.level + "</td>" +
              '<td class="r">' + c.dungeons + "/9</td>" +
              '<td class="r xs">' + c.quests + "</td>" +
              '<td class="r xs">' + c.ilvl + "</td>" +
              '<td class="r xs">' + profCell(c) + "</td>" +
              '<td class="r pct" style="--c:' + v + '">' + (p == null ? "" : Math.round(p)) + '</td><td class="go">&rsaquo;</td></tr>';
          }).join("");
        return '<table class="ranktable">' + head([["#", "rank"], ["Character"], ["Lvl", "r"], ["Dungeons", "r"], ["Quests", "r xs"], ["Gear", "r xs"], ["Trades", "r xs"], ["Parse", "r"], ["", "go"]]) + "<tbody>" + rows + "</tbody></table>" + pager(sorted.length);
      }
    }
  ,
    guilds: {
      sub: "Guild progress overall, not one lucky log: levelling pace, the nine dungeons, PvP, hardcore survival and quests, weighted into one score. Click a guild for the breakdown.",
      render: function () {
        var pool = GUILDS;
        if (realmFilter !== "all") pool = pool.filter(function (g) { return g.realm === realmFilter; });
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
              '<span class="meta">' + g.members + " members. " + esc(g.realm) + "</span></td>" +
              '<td class="r lvl">' + g.overall.toFixed(1) + "</td>" +
              '<td class="r xs">' + g.cats.levelling + "</td>" +
              '<td class="r xs">' + g.cats.dungeons + "</td>" +
              '<td class="r xs">' + g.cats.pvp + "</td>" +
              '<td class="r pct" style="--c:' + v + '">' + (p == null ? "" : Math.round(p)) + '</td><td class="go">&rsaquo;</td></tr>';
          }).join("");
        return '<table class="ranktable">' + head([["#", "rank"], ["Guild"], ["Overall", "r"], ["Lvl", "r xs"], ["Dng", "r xs"], ["PvP", "r xs"], ["Parse", "r"], ["", "go"]]) + "<tbody>" + rows + "</tbody></table>";
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
      '<div class="in-meta"><span class="chip">' + g.members + ' members</span><span class="chip">' + esc(g.realm) + ' server</span><span class="chip">overall ' + g.overall.toFixed(1) + '</span><span class="demo-flag">Demo</span></div>' +
      '<p class="in-h">Category breakdown: colour is the score band</p>' +
      '<ol class="gbars">' + bars + "</ol>" +
      '<p class="in-h">Notable members</p><div class="roster">' + roster + "</div>" +
      '<p class="in-note">Weights: levelling and dungeons 3, PvP 2, hardcore and quests 1. Real categories get argued about in the open once uploads exist.</p>';
    $("insight").hidden = false;
  }

  function bracketChip(c) {
    var peers = DEMO.filter(function (x) { return x.level === c.level && x.cls === c.cls; });
    if (peers.length < 2) return "";
    var better = peers.filter(function (x) { return x.lph > c.lph; }).length;
    if (better > 0) return "";
    return '<span class="chip chip-gold">#1 ' + esc(c.cls.toLowerCase()) + " at level " + c.level + "</span>";
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
      '<div class="in-meta"><span class="chip">' + esc(c.cls.toLowerCase()) + '</span><span class="chip">' + esc(c.realm) + '</span><span class="chip">' + (c.alive ? "alive" : "fallen") + '</span>' + bracketChip(c) + (c.tag ? '<span class="chip chip-gold">' + esc(c.tag) + "</span>" : "") + '<span class="demo-flag">Demo</span></div>' +
      '<div class="in-stats">' +
        "<div><b>" + c.level + "</b><span>level</span></div>" +
        "<div><b>" + hm(c.seconds) + "</b><span>time played</span></div>" +
        "<div><b>" + c.lph.toFixed(2) + "</b><span>lvl / hr</span></div>" +
        "<div><b>" + c.deaths + "</b><span>deaths</span></div>" +
        "<div><b>" + c.hks + "</b><span>honor kills</span></div>" +
        "<div><b>" + c.dungeons + "/9</b><span>dungeons</span></div>" +
      "</div>" +
      (c.profs ? '<p class="in-h">Professions</p><ol class="lvlbars profbars">' + c.profs.map(function (pr) {
        return "<li><b>" + esc(pr.n) + "</b>" +
          '<i style="--w:' + Math.max(4, (pr.sk / pr.cap) * 100) + '%;--c:var(--gold)"></i>' +
          "<u>" + pr.sk + "/" + pr.cap + "</u></li>";
      }).join("") + "</ol>" : "") +
      '<p class="in-h">Every level, timed: colour is the percentile at that level</p>' +
      '<ol class="lvlbars">' + bars + "</ol>" +
      '<p class="in-note">' + proj + " Real insights use exactly this layout once uploads exist.</p>";
    $("insight").hidden = false;
  }

  // ---- the explainer's two mock dashboards ----------------------------------
  // Drawn from the same placeholder people the preview ranks, so the numbers
  // agree wherever Aldric or his guild show up.
  var ICON = "https://wow.zamimg.com/images/wow/icons/large/";
  function hydrateExplainer() {
    function x(k) { return document.querySelector('[data-x="' + k + '"]'); }
    if (!x("c-lvl")) return;
    var c = DEMO.filter(function (d) { return d.name === "Aldric Stormhollow"; })[0];
    if (c) {
      x("c-lvl").textContent = c.level;
      x("c-ring").style.setProperty("--p", Math.min(1, c.level / CAP));
      x("c-sub").textContent = c.cls.charAt(0) + c.cls.slice(1).toLowerCase() + " · " + c.realm + " server · " + (c.alive ? "alive" : "fallen");
      var pips = "";
      for (var i = 0; i < 9; i++) pips += '<i class="' + (i < c.dungeons ? "on" : "") + '"></i>';
      x("c-pips").innerHTML = pips;
      var pp = pctile(progScore(c), DEMO.map(progScore));
      x("c-parse").textContent = Math.round(pp);
      x("c-parse").style.setProperty("--c", bandVar(pp));
      var worst = Math.max.apply(null, c.perLevel), bars = "";
      c.perLevel.forEach(function (sec, li) {
        var others = [];
        DEMO.forEach(function (o) { if (o.perLevel[li] != null) others.push(3600 / o.perLevel[li]); });
        bars += '<i title="Level ' + (li + 1) + " to " + (li + 2) + ": " + hm(sec) + '" style="--h:' + Math.max(12, sec / worst * 100) + "%;--c:" + bandVar(pctile(3600 / sec, others)) + '"></i>';
      });
      x("c-bars").innerHTML = bars;
      x("c-profs").innerHTML = (c.profs || []).map(function (pr) {
        return '<div><span class="ico s" style="background-image:url(' + ICON + pr.i + '.jpg)"></span>' + esc(pr.n) +
          '<em><u style="--w:' + Math.round(pr.sk / pr.cap * 100) + '%"></u></em><small>' + pr.sk + "/" + pr.cap + "</small></div>";
      }).join("");
    }
    var g = GUILDS.filter(function (d) { return d.name === "Riverglade Company"; })[0];
    if (g) {
      x("g-overall").textContent = Math.round(g.overall);
      x("g-ring").style.setProperty("--p", g.overall / 100);
      x("g-sub").textContent = g.members + " members · " + g.realm + " server";
      x("g-cats").innerHTML = GUILD_CATS.map(function (k) {
        var v = g.cats[k.key] || 0, col = bandVar(v);
        return "<div>" + esc(k.label) + '<em><u style="--w:' + v + "%;--c:" + col + '"></u></em><b style="--c:' + col + '">' + v + "</b></div>";
      }).join("");
      x("g-race").innerHTML = g.roster.map(function (n) {
        var m = DEMO.filter(function (d) { return d.name === n; })[0];
        if (!m) return "";
        return '<span class="' + (m.alive ? "" : "fell") + '" title="' + esc(n) + ", level " + m.level + '" style="--cc:' + cc(m.cls) + ";--p:" + Math.min(1, m.level / CAP) + '"></span>';
      }).join("");
    }
  }

  // ---- rendering ------------------------------------------------------------
  var view = "progression";
  function filtered() {
    var pool = DEMO;
    // Some ladders only exist where their rules do: one life is a Hardcore-
    // realm rule, world PvP a PvP-realm one. Even "All realms" respects that.
    if (view === "hardcore") pool = pool.filter(function (c) { return c.realm === "Hardcore"; });
    if (view === "pvp") pool = pool.filter(function (c) { return c.realm === "PvP"; });
    if (realmFilter !== "all") pool = pool.filter(function (c) { return c.realm === realmFilter; });
    if (query) {
      var q = query.toLowerCase();
      pool = pool.filter(function (c) { return c.name.toLowerCase().indexOf(q) !== -1; });
    }
    return pool;
  }
  function realmClash() {
    if (view === "pvp" && realmFilter !== "all" && realmFilter !== "PvP")
      return ["World PvP lives on the", "PvP server", "Duels are all a " + realmFilter + " server allows. Switch the server box to PvP or All servers."];
    if (view === "hardcore" && realmFilter !== "all" && realmFilter !== "Hardcore")
      return ["One life is a", "Hardcore rule", "The " + realmFilter + " server resurrects you. Switch the server box to Hardcore or All servers."];
    return null;
  }
  var REALM_OPTS = ["all", "Normal", "PvP", "Hardcore", "RP"];
  function syncURL() {
    var p = new URLSearchParams();
    if (demoOn()) {
      p.set("preview", "1");
      if (view !== "progression") p.set("ladder", view);
      if (realmFilter !== "all") p.set("realm", realmFilter);
      if (query) p.set("q", query);
      if (page > 0) p.set("p", String(page + 1));
    }
    var qs = p.toString();
    history.replaceState(null, "", (qs ? "?" + qs : location.pathname) + location.hash);
  }
  function readURL() {
    var p = new URLSearchParams(location.search);
    // A shared preview link opens the placeholder ladder for this visit only.
    if (p.get("preview") === "1" || p.get("ladder")) preview = true;
    var l = p.get("ladder");
    if (l && VIEWS[l]) view = l;
    var r = p.get("realm");
    if (r && REALM_OPTS.indexOf(r) !== -1) realmFilter = r;
    query = (p.get("q") || "").trim();
    var pg = parseInt(p.get("p"), 10);
    if (pg > 1) page = pg - 1;
  }
  function syncControls() {
    [["dd-view", view], ["dd-realm", realmFilter]].forEach(function (pair) {
      var root = $(pair[0]);
      if (!root) return;
      var label = root.querySelector(".dd-btn span");
      Array.prototype.forEach.call(root.querySelectorAll("li[data-v]"), function (li) {
        var on = li.getAttribute("data-v") === pair[1];
        li.classList.toggle("is-sel", on);
        li.setAttribute("aria-selected", String(on));
        if (on && label) label.textContent = li.textContent;
      });
    });
    var search = $("search");
    if (search) search.value = query;
  }
  function render() {
    syncURL();
    var v = VIEWS[view];
    var scope = realmFilter === "all"
      ? (view === "pvp" ? " Across all realms; only PvP-server characters fight for it."
        : view === "hardcore" ? " Across all realms; only Hardcore-server characters qualify."
        : " Across all four servers.")
      : " " + realmFilter + " server only.";
    var hint = view === "guilds" ? " Click a guild for its breakdown." : " Click a name for the full character.";
    $("board-sub").textContent = v.sub + scope + hint;
    $("cap-note").innerHTML = Date.now() < LAUNCH
      ? "Beta opens capped at <b>level 20</b>, rising to 30 after a couple of weeks. Boards rank to the live cap."
      : "Launched: the ladder runs to <b>level 60</b>.";
    var b = $("board");
    $("explain").hidden = demoOn();
    $("lad-live").hidden = !demoOn();
    Array.prototype.forEach.call(document.querySelectorAll("#lad-switch button"), function (btn) {
      var on = (btn.getAttribute("data-mode") === "preview") === demoOn();
      btn.classList.toggle("on", on);
      btn.setAttribute("aria-selected", String(on));
    });
    if (!demoOn()) { hydrateExplainer(); return; }
    var clash = realmClash();
    if (clash) {
      b.innerHTML = '<div class="empty"><h3>' + clash[0] + ' <span>' + clash[1] + '</span></h3><p>' + clash[2] + "</p></div>";
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
    Array.prototype.forEach.call(b.querySelectorAll("button[data-pg]"), function (btn) {
      btn.addEventListener("click", function () {
        page += Number(btn.getAttribute("data-pg"));
        render();
        b.scrollIntoView({ block: "start" });
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

  // ---- latest news ----------------------------------------------------------
  // Our own datamine leads; outlet headlines fill the grid; the rest of our
  // pieces ride a rail; everything else folds into a list.
  var SRC = { "FOREVERRANK": ["#e5cc80", "FR"], "Wowhead": ["#f06a5e", "WH"], "Icy Veins": ["#6cc0ff", "IV"],
    "Warcraft Tavern": ["#e9ad52", "WT"], "Blizzard": ["#35b5ff", "B"], "Blizzard Forums": ["#35b5ff", "B"],
    "Blizzard Watch": ["#8fd3ff", "BW"], "Kotaku": ["#ffd84d", "K"] };
  function srcTag(s) {
    var m = SRC[s] || ["#9fb0bb", (s || "?").slice(0, 2).toUpperCase()];
    return '<span class="hn-src" style="--sc:' + m[0] + '">' + esc(s === "FOREVERRANK" ? "ForeverRank" : s) + "</span>";
  }
  function when(d) {
    var dt = new Date(d + "T12:00:00Z");
    return isNaN(dt) ? d : dt.toLocaleDateString("en-GB", { day: "numeric", month: "short" });
  }
  function bg(url) { return "--img:url('" + String(url).replace(/'/g, "%27") + "')"; }
  // Outlets without a picture borrow tinted site art, picked by headline.
  var ART = ["/codex/img/hyjal-summit.jpg", "/codex/img/the-drowned-city.jpg", "/codex/img/krol-dok-stronghold.jpg",
    "/codex/img/blackmaw-hold.jpg", "/codex/img/the-barrow-deeps.jpg", "/codex/img/halls-of-thanes.jpg",
    "/codex/img/ruins-of-lordaeron.jpg", "/codex/img/city-of-dalaran.jpg"];
  function renderNews(n) {
    if (!n || !n.items || !$("hn-feature")) return;
    var items = n.items;
    var ours = items.filter(function (i) { return i.s === "FOREVERRANK"; });
    var theirs = items.filter(function (i) { return i.s !== "FOREVERRANK"; });
    var f = ours[0];
    if (f) {
      var hl = (f.hl || []).map(function (h) {
        return '<li><span class="ico s" style="background-image:url(' + ICON + esc(h.i) + '.jpg)"></span>' + esc(h.t) + "</li>";
      }).join("");
      var box = $("hn-feature");
      box.outerHTML = '<a class="hn-feature" id="hn-feature" href="' + esc(f.l) + '">' +
        '<div class="hn-art" style="' + bg(f.img || "/assets/og.jpg") + '">' + srcTag(f.s) + "<h3>" + esc(f.t) + "</h3></div>" +
        '<div class="hn-side"><span class="hn-date">' + esc(when(f.d)) + " · our datamine</span>" +
        (hl ? '<ul class="hn-hl">' + hl + "</ul>" : "") + '<span class="hn-read">Read the datamine &rsaquo;</span></div></a>';
    }
    // Six from the freshest twenty: art first, but at most three per outlet.
    var per = {}, grid = [];
    theirs.slice(0, 20).sort(function (a, b) { return (b.img ? 1 : 0) - (a.img ? 1 : 0); }).forEach(function (it) {
      if (grid.length < 6 && (per[it.s] || 0) < 3) { grid.push(it); per[it.s] = (per[it.s] || 0) + 1; }
    });
    grid.sort(function (a, b) { return a.d < b.d ? 1 : a.d > b.d ? -1 : 0; });
    $("hn-grid").innerHTML = grid.map(function (it) {
      var m = SRC[it.s] || ["#9fb0bb", "?"];
      var art = ART[hash(it.t) % ART.length];
      return '<a class="hn-card" href="' + esc(it.l) + '" rel="noopener"><span class="pic' + (it.img ? "" : " none") + '" data-mark="' + esc(m[1]) + '" style="--sc:' + m[0] + ";" + (it.img ? bg(it.img) : "--art:url('" + art + "')") + '">' + srcTag(it.s) + "</span>" +
        '<span class="txt"><b>' + esc(it.t) + "</b><i>" + esc(when(it.d)) + "</i></span></a>";
    }).join("");
    $("hn-rail").innerHTML = ours.slice(1).map(function (it) {
      return '<a class="hn-mini" href="' + esc(it.l) + '" style="' + bg(it.img || "/assets/og.jpg") + '"><i>' + esc(when(it.d)) + "</i><b>" + esc(it.t) + "</b></a>";
    }).join("");
    var rest = theirs.filter(function (i) { return grid.indexOf(i) === -1; }).slice(0, 40);
    $("hn-list").innerHTML = rest.map(function (it) {
      return "<li><span>" + esc(when(it.d)) + '</span><a href="' + esc(it.l) + '" rel="noopener">' + esc(it.t) + "</a><em>" + esc(it.s) + "</em></li>";
    }).join("") + '<li><span></span><a href="news/">Every headline on the news page &rsaquo;</a><em></em></li>';
  }

  // ---- wiring ---------------------------------------------------------------
  document.addEventListener("DOMContentLoaded", function () {
    tickCountdown(); setInterval(tickCountdown, 1000);

    function dropdown(id, onPick) {
      var root = $(id);
      if (!root) return;
      var btn = root.querySelector(".dd-btn"), list = root.querySelector(".dd-list"),
          label = root.querySelector(".dd-btn span");
      btn.addEventListener("click", function (e) {
        e.stopPropagation();
        var open = !list.hidden;
        Array.prototype.forEach.call(document.querySelectorAll(".dd-list"), function (l) { l.hidden = true; });
        Array.prototype.forEach.call(document.querySelectorAll(".dd"), function (d) { d.classList.remove("open"); });
        list.hidden = open;
        root.classList.toggle("open", !open);
        btn.setAttribute("aria-expanded", String(!open));
      });
      list.addEventListener("click", function (e) {
        var li = e.target;
        while (li && li !== list && !li.getAttribute("data-v")) li = li.parentNode;
        if (!li || li === list) return;
        Array.prototype.forEach.call(list.querySelectorAll("li"), function (o) { o.classList.remove("is-sel"); o.setAttribute("aria-selected", "false"); });
        li.classList.add("is-sel"); li.setAttribute("aria-selected", "true");
        label.textContent = li.textContent;
        list.hidden = true; root.classList.remove("open");
        onPick(li.getAttribute("data-v"));
      });
    }
    dropdown("dd-view", function (v) { view = v; page = 0; render(); });
    dropdown("dd-realm", function (v) { realmFilter = v; page = 0; render(); });
    document.addEventListener("click", function () {
      Array.prototype.forEach.call(document.querySelectorAll(".dd-list"), function (l) { l.hidden = true; });
      Array.prototype.forEach.call(document.querySelectorAll(".dd"), function (d) { d.classList.remove("open"); });
    });

    var search = $("search");
    if (search) {
      var deb = null;
      search.addEventListener("input", function () {
        clearTimeout(deb);
        deb = setTimeout(function () { query = search.value.trim(); page = 0; render(); }, 120);
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
    toggle.addEventListener("change", function () { setPreview(toggle.checked); render(); });
    function goLadder() { var l = $("ladder"); if (l) l.scrollIntoView({ block: "start" }); }
    $("preview-on").addEventListener("click", function () { setPreview(true); render(); goLadder(); });
    $("lad-switch").addEventListener("click", function (e) {
      var b = e.target.closest("button[data-mode]");
      if (!b) return;
      setPreview(b.getAttribute("data-mode") === "preview");
      page = 0;
      render();
    });

    var share = $("share");
    if (share) share.addEventListener("click", function () {
      var url = location.href;
      function done() {
        share.textContent = "Link copied";
        setTimeout(function () { share.textContent = "Share view"; }, 1600);
      }
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(url).then(done, function () { window.prompt("Copy this link:", url); });
      } else { window.prompt("Copy this link:", url); }
    });

    $("insight-x").addEventListener("click", function () { $("insight").hidden = true; });
    $("insight").addEventListener("click", function (e) { if (e.target === $("insight")) $("insight").hidden = true; });
    document.addEventListener("keydown", function (e) { if (e.key === "Escape") $("insight").hidden = true; });

    fetch("news.json", { cache: "no-store" }).then(function (r) { return r.json(); }).then(renderNews).catch(function () {});

    readURL();
    toggle.checked = demoOn();
    syncControls();
    render();
  });
})();
