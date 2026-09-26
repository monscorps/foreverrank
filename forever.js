/* LevelPace Forever: plan-stage board. No framework, no build step.
 * Until the game exists the board opens on an explainer; placeholder rows
 * are one click (or ?preview=1) away, and the gear toggles the same switch.
 * Rendering follows WarcraftLogs' discipline: class icon and class colour on
 * the name, band colour on the parse, everything else muted. */
(function () {
  "use strict";

  var BETA = Date.parse("2026-09-17T17:00:00Z");    // announced date; hour estimated
  var CAP30 = Date.parse("2026-10-01T17:00:00Z");   // two weeks into the beta; hour estimated
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

  // ---- the rest of a character: completion, PvP, social --------------------
  // Completion is the headline: how much of Forever a character has done,
  // not how fast. Speed stays one ladder among several, for the racers.
  var LEGACY_MAX = 65;
  var COMPLETION = [
    { k: "level", label: "Level", w: 20, of: function (c) { return c.level / CAP; }, txt: function (c) { return c.level + " / " + CAP; } },
    { k: "dng", label: "Dungeons of the Nine", w: 20, of: function (c) { return c.dungeons / 9; }, txt: function (c) { return c.dungeons + " / 9"; } },
    { k: "leg", label: "Legacy challenges", w: 15, of: function (c) { return c.legacy / LEGACY_MAX; }, txt: function (c) { return c.legacy + " / " + LEGACY_MAX; } },
    { k: "prof", label: "Professions", w: 15, of: function (c) { return c.profs ? (c.profs[0].sk / c.profs[0].cap + c.profs[1].sk / c.profs[1].cap) / 2 : 0; },
      txt: function (c) { return c.profs ? c.profs[0].sk + " + " + c.profs[1].sk : "0"; } },
    { k: "quest", label: "Quests", w: 10, of: function (c) { return Math.min(1, c.quests / 450); }, txt: function (c) { return String(c.quests); } },
    { k: "rep", label: "Reputation", w: 10, of: function (c) { return Math.min(1, (c.reps.exalted + c.reps.revered * 0.5) / 5); },
      txt: function (c) { return (c.reps.exalted ? c.reps.exalted + " exalted · " : "") + c.reps.revered + " revered"; } },
    { k: "exp", label: "Exploration", w: 10, of: function (c) { return c.explore / 100; }, txt: function (c) { return c.explore + "%"; } }
  ];
  function completionOf(c) {
    var t = 0;
    COMPLETION.forEach(function (p) { t += Math.max(0, Math.min(1, p.of(c))) * p.w; });
    return Math.round(t);
  }
  // Nemeses are the other faction: names that never reach our ladder.
  var ENEMIES = ["Vex Shadowmere", "Grimjaw Skullsplitter", "Borin Hammerfall", "Zul'kan Bloodfang", "Morrigan Vale",
    "Kael Dawnbreaker", "Thrag Ironhide", "Selene Frostwhisper", "Durak Bonecrusher", "Ysolde Thornfield"];
  var ENEMY_CLS = ["ROGUE", "WARRIOR", "PALADIN", "SHAMAN", "WARLOCK", "MAGE", "WARRIOR", "MAGE", "WARRIOR", "HUNTER"];
  // Where the fighting happens, on the Eastern Kingdoms art: zone centres from
  // the client's UiMapAssignment rectangles (percent of the continent image).
  var HEAT = [
    { n: "Hillsbrad Foothills", x: 40.5, y: 24.7, w: 5, at: "l" }, { n: "Stranglethorn Vale", x: 44.3, y: 87.0, w: 5 },
    { n: "Riverglades", x: 72.8, y: 61.3, w: 4, at: "r" }, { n: "Arathi Highlands", x: 58.7, y: 28.0, w: 3, at: "r" },
    { n: "Redridge Mountains", x: 59.6, y: 67.3, w: 3 }, { n: "Alterac Mountains", x: 41.2, y: 18.7, w: 2, at: "up" },
    { n: "Duskwood", x: 40.4, y: 73.8, w: 2, at: "l" }, { n: "The Hinterlands", x: 65.8, y: 20.6, w: 2 },
    { n: "Badlands", x: 64.3, y: 54.6, w: 1 }, { n: "Wetlands", x: 56.9, y: 38.8, w: 1 }
  ];
  var HEALERS = { PRIEST: 1, PALADIN: 1, SHAMAN: 1, DRUID: 1 };
  DEMO.forEach(function (c) {
    var r = rng(hash(c.name + "|more"));
    c.reps = { exalted: Math.floor(r() * (c.level / 11)), revered: 1 + Math.floor(r() * 3) };
    c.legacy = Math.min(LEGACY_MAX, Math.round(c.level * 0.4 + c.dungeons * 0.9 + r() * 6));
    c.explore = Math.min(100, Math.round(18 + c.level * 1.5 + r() * 16));
    c.completion = completionOf(c);
    var mates = DEMO.filter(function (o) { return o !== c && o.realm === c.realm; })
      .sort(function (a, b) { return hash(c.name + a.name) - hash(c.name + b.name); });
    c.partners = mates.slice(0, 3).map(function (o, i) { return { n: o.name, cls: o.cls, runs: Math.max(2, 9 - i * 2 - Math.floor(r() * 2)) }; });
    c.grouped = 14 + Math.floor(r() * 50) + c.dungeons * 3;
    c.rezzes = HEALERS[c.cls] ? 12 + Math.floor(r() * 40) : Math.floor(r() * 4);
    c.duels = { won: Math.floor(r() * 24), lost: Math.floor(r() * 16) };
    c.hugs = Math.floor(r() * r() * 140);
    c.socialScore = c.grouped + c.partners.reduce(function (a, p) { return a + p.runs * 2; }, 0) + c.rezzes * 1.5 + c.duels.won + c.hugs / 10;
    if (c.realm === "PvP") {
      var e0 = hash(c.name) % ENEMIES.length;
      c.nemeses = [0, 3, 7].map(function (off, i) {
        var k = (e0 + off) % ENEMIES.length;
        return { n: ENEMIES[k], cls: ENEMY_CLS[k], kills: Math.max(2, 8 - i * 2 - Math.floor(r() * 2)), zone: HEAT[(k + i) % 5].n };
      });
      c.bounty = c.nemeses[0].kills >= 6 ? c.nemeses[0] : null;
      var wsum = HEAT.reduce(function (a, z) { return a + z.w; }, 0);
      c.heat = HEAT.map(function (z) { return { n: z.n, x: z.x, y: z.y, at: z.at || "", k: Math.round(c.hks * z.w / wsum * (0.6 + r() * 0.8)) }; });
    }
  });
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
    { key: "completion", label: "Member completion", w: 3 },
    { key: "dungeons", label: "Dungeons of the Nine", w: 3 },
    { key: "quests", label: "Quests", w: 1 },
    { key: "pvp", label: "PvP", w: 2 },
    { key: "hardcore", label: "Hardcore survival", w: 1 },
    { key: "levelling", label: "Levelling pace", w: 1 }
  ];
  function mkGuild(name, tag, members, sc, roster, realm) {
    var total = 0, wsum = 0;
    // member completion is measured, not set: the mean of the roster shown
    var ms = DEMO.filter(function (d) { return roster.indexOf(d.name) !== -1; });
    sc.completion = ms.length ? Math.round(ms.reduce(function (a, d) { return a + d.completion; }, 0) / ms.length) : 0;
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

  // Notable members: each award goes to whoever in the guild does that thing
  // most, one award per member where the roster allows it.
  var AWARDS = [
    { t: "The Completionist", i: "inv_misc_trophy_argent", v: function (c) { return c.completion; }, f: function (c) { return c.completion + "% complete"; } },
    { t: "The Healer", i: "spell_holy_resurrection", v: function (c) { return HEALERS[c.cls] && c.rezzes > 0 ? c.rezzes : -1; }, f: function (c) { return c.rezzes + (c.rezzes === 1 ? " resurrection" : " resurrections") + " cast"; } },
    { t: "The Explorer", i: "inv_misc_map_01", v: function (c) { return c.explore; }, f: function (c) { return c.explore + "% of the world explored"; } },
    { t: "The Slayer", i: "inv_bannerpvp_01", v: function (c) { return c.realm === "PvP" ? c.hks : -1; }, f: function (c) { return c.hks + " honorable kills"; } },
    { t: "The Survivor", i: "spell_holy_divineintervention", v: function (c) { return c.realm === "Hardcore" && c.alive ? c.level : -1; }, f: function (c) { return "alive at " + c.level + ", one life"; } },
    { t: "The Social Butterfly", i: "inv_letter_15", v: function (c) { return c.grouped; }, f: function (c) { return "grouped with " + c.grouped + " players"; } },
    { t: "The Crafter", i: "trade_blacksmithing", v: function (c) { return c.profs[0].sk + c.profs[1].sk; }, f: function (c) { return c.profs[0].n + " and " + c.profs[1].n + ", " + (c.profs[0].sk + c.profs[1].sk); } },
    { t: "The Duelist", i: "ability_dualwield", v: function (c) { return c.duels.won; }, f: function (c) { return c.duels.won + " duels won"; } },
    { t: "The Hugger", i: "inv_valentinescard01", v: function (c) { return c.hugs; }, f: function (c) { return "/hug ×" + c.hugs; } }
  ];
  function notables(g) {
    var ms = DEMO.filter(function (d) { return g.roster.indexOf(d.name) !== -1; }), used = {}, out = [];
    AWARDS.forEach(function (a) {
      var best = ms.filter(function (m) { return a.v(m) >= 0; })
        .sort(function (x, y) { return (used[x.name] ? 1 : 0) - (used[y.name] ? 1 : 0) || a.v(y) - a.v(x); })[0];
      if (!best || used[best.name] && out.length >= ms.length) return;
      used[best.name] = true;
      out.push({ award: a.t, icon: a.i, c: best, stat: a.f(best) });
    });
    return out.slice(0, Math.max(4, ms.length + 1));
  }

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
    if (now < BETA) { target = BETA; kick = "The <b>beta</b> opens in"; phase = "PRE-BETA"; note = "Beta Sept 17 to Oct 22, capped at level 20, then 30 from Oct 1. Launch Nov 4 (times estimated)"; }
    else if (now < LAUNCH) { target = LAUNCH; kick = "<b>Forever</b> launches in"; phase = now < CAP30 ? "BETA. CAP 20" : "BETA. CAP 30"; note = "Beta is live until Oct 22" + (now < CAP30 ? ", level 30 opens Oct 1" : "") + ". Launch Nov 4 (times estimated)"; }
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
  var ICON = "https://wow.zamimg.com/images/wow/icons/large/";
  var REALM_CLS = { Normal: "rd-normal", PvP: "rd-pvp", Hardcore: "rd-hardcore", RP: "rd-rp" };
  function clsName(cls) { return cls.charAt(0) + cls.slice(1).toLowerCase(); }
  function classIcon(cls) { return ICON + "classicon_" + cls.toLowerCase() + ".jpg"; }
  function nameCell(c, note) {
    return '<td><span class="who' + (c.alive ? "" : " fell") + '" style="--cc:' + cc(c.cls) + '">' +
      '<span class="cl" style="background-image:url(' + classIcon(c.cls) + ')"></span>' +
      "<span><b>" + esc(c.name) + '</b><small class="' + REALM_CLS[c.realm] + '"><i></i>' + clsName(c.cls) + " · " + esc(c.realm) +
      (note ? "<em>· " + esc(note) + "</em>" : "") + "</small></span></span></td>";
  }
  function guildCell(g) {
    return '<td><span class="who"><span class="gshield"><span>' + esc(g.tag) + "</span></span>" +
      "<span><b>&lt;" + esc(g.name) + '&gt;</b><small class="' + REALM_CLS[g.realm] + '"><i></i>' + g.members + " members · " + esc(g.realm) + "</small></span></span></td>";
  }
  function head(cols) {
    return "<thead><tr>" + cols.map(function (h) {
      return '<th class="' + (h[1] || "") + '">' + h[0] + "</th>";
    }).join("") + "</tr></thead>";
  }
  // One bar row: label, a band-coloured fill, the value. The explainer and
  // the profiles share it so the same number always looks the same.
  function catBar(label, frac, txt, col) {
    col = col || bandVar(frac * 100);
    return "<div>" + label + '<em><u style="--w:' + Math.round(Math.max(.03, Math.min(1, frac)) * 100) + "%;--c:" + col + '"></u></em><b style="--c:' + col + '">' + esc(txt) + "</b></div>";
  }
  function profsHTML(c) {
    return (c.profs || []).map(function (pr) {
      return '<div><span class="ico s" style="background-image:url(' + ICON + pr.i + '.jpg)"></span>' + esc(pr.n) +
        '<em><u style="--w:' + Math.round(pr.sk / pr.cap * 100) + '%"></u></em><small>' + pr.sk + "/" + pr.cap + "</small></div>";
    }).join("");
  }
  function membersHTML(g) {
    return DEMO.filter(function (d) { return g.roster.indexOf(d.name) !== -1; })
      .sort(function (a, b) { return b.completion - a.completion; }).map(function (m) {
        var col = bandVar(m.completion);
        return '<div class="' + (m.alive ? "" : "fell") + '"><b style="color:' + cc(m.cls) + '">' + esc(m.name) + '</b><em><u style="--w:' + m.completion + "%;--c:" + col + '"></u></em><small style="--c:' + col + '">' + m.completion + "%</small></div>";
      }).join("");
  }
  function partnersHTML(c, unit) {
    var most = Math.max.apply(null, c.partners.map(function (pt) { return pt.runs; })) || 1;
    return c.partners.map(function (pt) {
      return catBar('<span style="color:' + cc(pt.cls) + '">' + esc(pt.n) + "</span>", pt.runs / most, pt.runs + (unit || ""), cc(pt.cls));
    }).join("");
  }
  function nemesesHTML(c, first) {
    return c.nemeses.map(function (nm) {
      return '<div><span class="skull">☠</span><b style="color:' + cc(nm.cls) + '">' + esc(nm.n) + "</b><span>killed " + esc(first) + " " + nm.kills + "× · " + esc(nm.zone) + "</span></div>";
    }).join("");
  }
  function pvpRank(c) { return PVP_RANKS[Math.min(PVP_RANKS.length - 1, Math.floor(c.hks / 18))]; }
  function kd(c) { return c.pvpDeaths > 0 ? (c.kills / c.pvpDeaths).toFixed(2) : String(c.kills); }

  function progScore(c) { return c.completion; }
  function profCell(c) {
    if (!c.profs) return "";
    return c.profs.map(function (pr) {
      return '<img class="profico" src="https://wow.zamimg.com/images/wow/icons/large/' + pr.i + '.jpg" alt="" title="' + esc(pr.n) + " " + pr.sk + "/" + pr.cap + '"> ' + pr.sk;
    }).join(" ");
  }
  function parseCell(p) { return '<td class="r pct" style="--c:' + bandVar(p) + '">' + (p == null ? "" : Math.round(p)) + '</td><td class="go">&rsaquo;</td></tr>'; }
  function rowStart(c, i, note) { return '<tr data-c="' + esc(c.name) + '"><td class="rank">' + (page * PAGE + i + 1) + "</td>" + nameCell(c, note); }
  var VIEWS = {
    progression: {
      label: "Completion", icon: "inv_misc_trophy_argent",
      sub: "How much of Forever each character has done: level, dungeons, Legacy, trades, quests, reputation and exploration, in one percentage.",
      render: function (d) {
        var all = d.map(function (c) { return c.completion; });
        var sorted = d.slice().sort(function (a, b) { return b.completion - a.completion || b.level - a.level; });
        var rows = pageSlice(sorted).map(function (c, i) {
          return rowStart(c, i) +
            '<td class="r lvl sm">' + c.level + "</td>" +
            '<td class="r sm">' + c.dungeons + "/9</td>" +
            '<td class="r xs">' + c.legacy + "/" + LEGACY_MAX + "</td>" +
            '<td class="r xs">' + c.explore + "%</td>" +
            '<td class="r"><span class="cmp" style="--w:' + c.completion + '%"><i></i>' + c.completion + "%</span></td>" +
            parseCell(pctile(c.completion, all));
        }).join("");
        return '<table class="ranktable">' + head([["#", "rank"], ["Character"], ["Level", "r sm"], ["Dungeons", "r sm"], ["Legacy", "r xs"], ["Explored", "r xs"], ["Complete", "r"], ["Parse", "r"], ["", "go"]]) + "<tbody>" + rows + "</tbody></table>" + pager(sorted.length);
      }
    },
    pvp: {
      label: "World PvP", icon: "inv_bannerpvp_01", only: "PvP",
      sub: "Honorable kills, rank and K/D on PvP servers. Your nemesis is whoever has killed you most. Opt-in, because it names other players.",
      render: function (d) {
        var hks = d.map(function (c) { return c.hks; });
        var sorted = d.slice().sort(function (a, b) { return b.hks - a.hks; });
        var rows = pageSlice(sorted).map(function (c, i) {
          var nm = c.nemeses && c.nemeses[0];
          return rowStart(c, i) +
            '<td class="r xs">' + esc(pvpRank(c)) + "</td>" +
            '<td class="r lvl">' + c.hks + "</td>" +
            '<td class="r sm">' + kd(c) + "</td>" +
            '<td class="r xs">' + (nm ? '<span style="color:' + cc(nm.cls) + '">' + esc(nm.n) + "</span> ×" + nm.kills + (c.bounty ? ' <span class="bty" title="Bounty open">☠</span>' : "") : "") + "</td>" +
            parseCell(pctile(c.hks, hks));
        }).join("");
        return '<table class="ranktable">' + head([["#", "rank"], ["Character"], ["Rank", "r xs"], ["Kills", "r"], ["K/D", "r sm"], ["Nemesis", "r xs"], ["Parse", "r"], ["", "go"]]) + "<tbody>" + rows + "</tbody></table>" + pager(sorted.length);
      }
    },
    social: {
      label: "Social", icon: "inv_letter_15",
      sub: "Who plays with whom: players grouped with, the partner you run with most, resurrections and duels. Opt-in, because it names other players.",
      render: function (d) {
        var all = d.map(function (c) { return c.socialScore; });
        var sorted = d.slice().sort(function (a, b) { return b.socialScore - a.socialScore; });
        var rows = pageSlice(sorted).map(function (c, i) {
          var top = c.partners[0];
          return rowStart(c, i) +
            '<td class="r lvl">' + c.grouped + "</td>" +
            '<td class="r xs">' + (top ? '<span style="color:' + cc(top.cls) + '">' + esc(top.n) + "</span> ×" + top.runs : "") + "</td>" +
            '<td class="r xs">' + c.rezzes + "</td>" +
            '<td class="r sm">' + c.duels.won + "–" + c.duels.lost + "</td>" +
            parseCell(pctile(c.socialScore, all));
        }).join("");
        return '<table class="ranktable">' + head([["#", "rank"], ["Character"], ["Grouped", "r"], ["Runs most with", "r xs"], ["Rezzes", "r xs"], ["Duels", "r sm"], ["Parse", "r"], ["", "go"]]) + "<tbody>" + rows + "</tbody></table>" + pager(sorted.length);
      }
    },
    hardcore: {
      label: "Hardcore", icon: "inv_misc_bone_humanskull_01", only: "Hardcore",
      sub: "One life. The living rank by level; the fallen keep the level death found them at.",
      render: function (d) {
        var sorted = d.slice().sort(function (a, b) { return (b.alive - a.alive) || b.level - a.level || a.seconds - b.seconds; });
        var rows = pageSlice(sorted).map(function (c, i) {
          return rowStart(c, i, c.alive ? "" : c.tag) +
            '<td class="r lvl">' + c.level + "</td>" +
            '<td class="r xs">' + c.dungeons + "/9</td>" +
            '<td class="r xs">' + hm(c.seconds) + "</td>" +
            '<td class="r">' + (c.alive ? '<span class="st alive">Alive</span>' : '<span class="st fell">Fallen</span>') + '</td><td class="go">&rsaquo;</td></tr>';
        }).join("");
        return '<table class="ranktable">' + head([["#", "rank"], ["Character"], ["Level", "r"], ["Dungeons", "r xs"], ["Played", "r xs"], ["Status", "r"], ["", "go"]]) + "<tbody>" + rows + "</tbody></table>" + pager(sorted.length);
      }
    },
    professions: {
      label: "Professions", icon: "trade_blacksmithing",
      sub: "Both primary professions, added up. Camps made trades part of progress, so the ladder counts them.",
      render: function (d) {
        var sum = function (c) { return c.profs ? c.profs[0].sk + c.profs[1].sk : 0; };
        var all = d.map(sum);
        var sorted = d.slice().sort(function (a, b) { return sum(b) - sum(a) || b.level - a.level; });
        var rows = pageSlice(sorted).map(function (c, i) {
          return rowStart(c, i) +
            '<td class="r xs">' + profCell(c) + "</td>" +
            '<td class="r lvl">' + sum(c) + "</td>" +
            parseCell(pctile(sum(c), all));
        }).join("");
        return '<table class="ranktable">' + head([["#", "rank"], ["Character"], ["Trades", "r xs"], ["Total", "r"], ["Parse", "r"], ["", "go"]]) + "<tbody>" + rows + "</tbody></table>" + pager(sorted.length);
      }
    },
    guilds: {
      label: "Guilds", icon: "inv_misc_tabardpvp_01",
      sub: "Guild progress across six categories, led by how complete the members are. Open a guild for its notable members.",
      render: function () {
        var pool = GUILDS;
        if (realmFilter !== "all") pool = pool.filter(function (g) { return g.realm === realmFilter; });
        if (query) {
          var q = query.toLowerCase();
          pool = pool.filter(function (g) {
            return g.name.toLowerCase().indexOf(q) !== -1 ||
              g.roster.some(function (m) { return m.toLowerCase().indexOf(q) !== -1; });
          });
        }
        if (!pool.length) return '<div class="empty"><h3>No guild ' + (query ? "or member called <span>“" + esc(query) + "”</span>" : "on this server yet") + "</h3></div>";
        var all = GUILDS.map(function (g) { return g.overall; });
        var rows = pool.slice().sort(function (a, b) { return b.overall - a.overall; }).map(function (g, i) {
          return '<tr data-g="' + esc(g.name) + '"><td class="rank">' + (i + 1) + "</td>" + guildCell(g) +
            '<td class="r lvl">' + Math.round(g.overall) + "</td>" +
            '<td class="r sm"><span class="cmp" style="--w:' + g.cats.completion + '%"><i></i>' + g.cats.completion + "%</span></td>" +
            '<td class="r xs">' + g.cats.dungeons + "</td>" +
            '<td class="r xs">' + g.cats.pvp + "</td>" +
            '<td class="r xs">' + g.cats.hardcore + "</td>" +
            parseCell(pctile(g.overall, all));
        }).join("");
        return '<table class="ranktable">' + head([["#", "rank"], ["Guild"], ["Overall", "r"], ["Members complete", "r sm"], ["Dungeons", "r xs"], ["PvP", "r xs"], ["Hardcore", "r xs"], ["Parse", "r"], ["", "go"]]) + "<tbody>" + rows + "</tbody></table>";
      }
    },
    levelling: {
      label: "Levelling speed", icon: "ability_rogue_sprint",
      sub: "For the racers: highest level first, time played breaks ties, and the parse is pace against everyone at the same level.",
      render: function (d) {
        var byLvl = {};
        d.forEach(function (c) { (byLvl[c.level] = byLvl[c.level] || []).push(c.lph); });
        var sorted = d.slice().sort(function (a, b) { return b.level - a.level || a.seconds - b.seconds; });
        var rows = pageSlice(sorted).map(function (c, i) {
          return rowStart(c, i) +
            '<td class="r lvl">' + c.level + "</td>" +
            '<td class="r xs">' + hm(c.seconds) + "</td>" +
            '<td class="r sm">' + c.lph.toFixed(2) + "</td>" +
            parseCell(pctile(c.lph, byLvl[c.level]));
        }).join("");
        return '<table class="ranktable">' + head([["#", "rank"], ["Character"], ["Level", "r"], ["Played", "r xs"], ["Levels / hour", "r sm"], ["Parse", "r"], ["", "go"]]) + "<tbody>" + rows + "</tbody></table>" + pager(sorted.length);
      }
    }
  };

  // ---- profiles: one sheet per character or guild ------------------------
  function sec(icon, title, note, body, cls) {
    return '<section class="ch-sec' + (cls ? " " + cls : "") + '"><h4><span class="ico s" style="background-image:url(' + ICON + icon + '.jpg)"></span>' + title +
      (note ? "<small>" + note + "</small>" : "") + "</h4>" + body + "</section>";
  }
  function tile(v, unit, label, col) {
    return "<div" + (col ? ' class="pp" style="--c:' + col + '"' : "") + "><b>" + v + (unit ? "<small>" + unit + "</small>" : "") + "</b><span>" + label + "</span></div>";
  }
  function openSheet(html) {
    $("insight-body").innerHTML = html;
    $("insight").hidden = false;
    var card = document.querySelector("#insight .insight-card");
    if (card) card.scrollTop = 0;
  }
  function awardCards(g) {
    return notables(g).map(function (a) {
      return '<div class="award"><span class="ico" style="background-image:url(' + ICON + a.icon + '.jpg)"></span><div><em>' + esc(a.award) + "</em>" +
        '<b style="color:' + cc(a.c.cls) + '">' + esc(a.c.name) + "</b><span>" + esc(a.stat) + "</span></div></div>";
    }).join("");
  }
  function guildInsight(g) {
    var p = pctile(g.overall, GUILDS.map(function (x) { return x.overall; }));
    openSheet(
      '<header class="ch-head"><span class="gshield lg"><span>' + esc(g.tag) + "</span></span>" +
        '<div class="ch-t"><h2 class="in-name">&lt;' + esc(g.name) + "&gt;</h2>" +
        '<p class="ch-sub ' + REALM_CLS[g.realm] + '"><i></i>' + g.members + " members · " + esc(g.realm) + " server</p></div>" +
        '<span class="lb-demo">Placeholder</span></header>' +
      '<div class="ch-hero"><div class="hx-ring big gold" style="--p:' + (g.overall / 100) + '"><b>' + Math.round(g.overall) + "</b><span>overall</span></div>" +
        '<div class="ch-stats">' + tile(g.cats.completion, "%", "members complete") + tile(g.cats.dungeons, "", "dungeons") + tile(g.cats.pvp, "", "PvP") +
        tile(g.cats.hardcore, "", "hardcore") + tile(p == null ? "" : Math.round(p), "", "guild parse", bandVar(p)) + "</div></div>" +
      sec("inv_misc_trophy_argent", "Notable members", "picked by what they do in the world", '<div class="awards">' + awardCards(g) + "</div>") +
      '<div class="ch-duo">' +
        sec("inv_misc_note_01", "Categories", "colour is the score band", '<div class="hx-cats">' + GUILD_CATS.map(function (k) {
          var v = g.cats[k.key] || 0; return catBar(esc(k.label), v / 100, String(v));
        }).join("") + "</div>") +
        sec("inv_misc_tabardpvp_01", "Members", "by completion", '<div class="hx-members">' + membersHTML(g) + "</div>") +
      "</div>" +
      '<p class="in-note">Weights: member completion and dungeons count three, PvP two, quests, hardcore and levelling pace one. Real categories get argued about in the open once uploads exist.</p>');
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
      var lp = pctile(3600 / mine, others), v = bandVar(lp);
      bars += "<li><b>" + (i + 1) + "&rarr;" + (i + 2) + "</b>" +
        '<i style="--w:' + Math.max(4, (mine / worst) * 100) + "%;--c:" + v + '"></i>' +
        "<u>" + hm(mine) + "</u></li>";
    }
    var toCap = CAP - c.level;
    var proj = !c.alive ? "The record stops at level " + c.level + ", where death found " + esc(c.name.split(" ")[0]) + "."
      : toCap > 0 && c.lph > 0 ? "At this pace: level " + CAP + " in about " + hm(Math.round(toCap / c.lph * 3600)) + " more played time."
      : "At the cap.";
    var peers = DEMO.filter(function (x) { return x.level === c.level && x.cls === c.cls; });
    var fastest = peers.length > 1 && !peers.some(function (x) { return x.lph > c.lph; });
    var first = c.name.split(" ")[0];
    var pp = pctile(c.completion, DEMO.map(function (d) { return d.completion; }));
    var status = c.realm === "Hardcore" ? (c.alive ? ' · <span class="st alive">alive</span>' : ' · <span class="st fell">fallen</span>') : "";
    var html =
      '<header class="ch-head" style="--cc:' + cc(c.cls) + '">' +
        '<span class="ch-av" style="background-image:url(' + classIcon(c.cls) + ')"></span>' +
        '<div class="ch-t"><h2 class="in-name">' + esc(c.name) + "</h2>" +
        '<p class="ch-sub ' + REALM_CLS[c.realm] + '"><i></i>Level ' + c.level + " " + clsName(c.cls) + " · " + esc(c.realm) + " server" + status + "</p>" +
        (c.tag ? '<p class="ch-tag">“' + esc(c.tag) + "”</p>" : "") + "</div>" +
        '<span class="lb-demo">Placeholder</span></header>' +
      '<div class="ch-hero"><div class="hx-ring big gold" style="--p:' + (c.completion / 100) + '"><b>' + c.completion + "%</b><span>complete</span></div>" +
        '<div class="ch-stats">' + tile(c.level, "/" + CAP, "level") + tile(c.dungeons, "/9", "dungeons") + tile(c.legacy, "/" + LEGACY_MAX, "legacy") +
        tile(c.explore, "%", "explored") + tile(pp == null ? "" : Math.round(pp), "", "completion parse", bandVar(pp)) + "</div></div>" +
      sec("inv_misc_trophy_argent", "Completion", "what makes up the " + c.completion + "%",
        '<div class="hx-cats wide">' + COMPLETION.map(function (part) { return catBar(esc(part.label), part.of(c), part.txt(c)); }).join("") + "</div>" +
        '<div class="hx-prof">' + profsHTML(c) + "</div>");
    if (c.nemeses) {
      html += sec("inv_bannerpvp_01", "World PvP", "opt-in",
        '<div class="tiles">' + tile(esc(pvpRank(c)), "", "rank") + tile(c.hks, "", "honorable kills") + tile(kd(c), "", "K/D") + "</div>" +
        '<div class="nem">' + nemesesHTML(c, first) + "</div>" +
        (c.bounty ? '<p class="bounty">Bounty open on <b>' + esc(c.bounty.n) + "</b>: " + c.bounty.kills + " kills on " + esc(first) + ". Settle it in the field.</p>" : ""), "pvp");
    }
    html += sec("inv_letter_15", "Social", "opt-in",
      '<div class="hx-cats wide">' + partnersHTML(c, " runs") + "</div>" +
      '<div class="tiles">' + tile(c.grouped, "", "players grouped with") + (HEALERS[c.cls] ? tile(c.rezzes, "", "resurrections cast") : tile(c.hugs, "", "/hugs given")) +
      tile(c.duels.won + "–" + c.duels.lost, "", "duels") + "</div>");
    html += '<details class="ch-sec racer"><summary><span class="ico s" style="background-image:url(' + ICON + 'ability_rogue_sprint.jpg)"></span>For the racers: every level, timed' +
      "<small>" + hm(c.seconds) + " played · " + c.lph.toFixed(2) + " levels an hour" + (fastest ? " · fastest " + clsName(c.cls) + " at " + c.level : "") + "</small></summary>" +
      '<ol class="lvlbars">' + bars + '</ol><p class="in-note">' + proj + "</p></details>" +
      '<p class="in-note">Placeholder data. Real profiles use this layout once uploads exist; the PvP and social parts only with the player\'s own opt-in.</p>';
    openSheet(html);
  }

  // ---- the explainer's four mock dashboards ---------------------------------
  // Drawn from the same placeholder people the preview ranks, so the numbers
  // agree wherever Aldric or his guild show up.
  function hydrateExplainer() {
    function x(k) { return document.querySelector('[data-x="' + k + '"]'); }
    function who(name) { return DEMO.filter(function (d) { return d.name === name; })[0]; }
    if (!x("c-pct") || x("c-pct").getAttribute("data-done")) return;
    x("c-pct").setAttribute("data-done", "1");
    // Character: completion first, pace last
    var c = who("Aldric Stormhollow");
    if (c) {
      x("c-pct").textContent = c.completion + "%";
      x("c-ring").style.setProperty("--p", c.completion / 100);
      x("c-sub").textContent = clsName(c.cls) + " · " + c.realm + " server · level " + c.level;
      x("c-parts").innerHTML = COMPLETION.map(function (p) { return catBar(esc(p.label), p.of(c), p.txt(c)); }).join("");
      var pips = "";
      for (var i = 0; i < 9; i++) pips += '<i class="' + (i < c.dungeons ? "on" : "") + '"></i>';
      x("c-pips").innerHTML = pips;
      var pp = pctile(c.completion, DEMO.map(function (d) { return d.completion; }));
      x("c-parse").textContent = Math.round(pp);
      x("c-parse").style.setProperty("--c", bandVar(pp));
      var worst = Math.max.apply(null, c.perLevel), bars = "";
      c.perLevel.forEach(function (sec, li) {
        var others = [];
        DEMO.forEach(function (o) { if (o.perLevel[li] != null) others.push(3600 / o.perLevel[li]); });
        bars += '<i title="Level ' + (li + 1) + " to " + (li + 2) + ": " + hm(sec) + '" style="--h:' + Math.max(12, sec / worst * 100) + "%;--c:" + bandVar(pctile(3600 / sec, others)) + '"></i>';
      });
      x("c-bars").innerHTML = bars;
      x("c-profs").innerHTML = profsHTML(c);
    }
    // Guild: completion-first categories, members by completion, notable members
    var g = GUILDS.filter(function (d) { return d.name === "Riverglade Company"; })[0];
    if (g) {
      x("g-overall").textContent = Math.round(g.overall);
      x("g-ring").style.setProperty("--p", g.overall / 100);
      x("g-sub").textContent = g.members + " members · " + g.realm + " server";
      x("g-cats").innerHTML = GUILD_CATS.map(function (k) { var v = g.cats[k.key] || 0; return catBar(esc(k.label), v / 100, String(v)); }).join("");
      x("g-members").innerHTML = membersHTML(g);
      x("g-awards").innerHTML = awardCards(g);
    }
    // PvP: the heat map, nemeses, a bounty and the in-game alert
    var p = who("Crit Happens");
    if (p && p.heat) {
      var first = p.name.split(" ")[0], maxk = Math.max.apply(null, p.heat.map(function (h) { return h.k; })) || 1;
      x("p-first").textContent = first;
      x("p-name").textContent = p.name;
      x("p-sub").textContent = clsName(p.cls) + " · " + p.realm + " server · level " + p.level;
      x("p-heat").innerHTML = p.heat.filter(function (h) { return h.k > 0; }).map(function (h, n) {
        return '<i style="--x:' + h.x + "%;--y:" + h.y + "%;--s:" + (1.6 + 3.4 * h.k / maxk).toFixed(2) + "rem;--d:" + (n * .3) + 's"><b>' + h.k + '</b><span class="' + h.at + '">' + esc(h.n) + "</span></i>";
      }).join("");
      x("p-tiles").innerHTML = tile(esc(pvpRank(p)), "", "rank") + tile(p.hks, "", "honorable kills") + tile(kd(p), "", "K/D");
      x("p-nem").innerHTML = nemesesHTML(p, first);
      x("p-bounty").innerHTML = p.bounty ? "Bounty open on <b>" + esc(p.bounty.n) + "</b>: " + p.bounty.kills + " kills on " + esc(first) + ". Settle it in the field." : "";
      var zone = p.nemeses[0].zone, here = p.nemeses.filter(function (nm) { return nm.zone === zone; }).length;
      x("p-toast").textContent = (here > 1 ? here + " of your nemeses are" : p.nemeses[0].n + " is") + " in " + zone + ". Your bounty on " + p.nemeses[0].n + " is open.";
    }
    // Social: who you play with
    var sc = who("Justin Case");
    if (sc) {
      x("s-name").textContent = sc.name;
      x("s-sub").textContent = clsName(sc.cls) + " · " + sc.realm + " server · level " + sc.level;
      x("s-grouped").textContent = sc.grouped;
      x("s-ring").style.setProperty("--p", Math.min(1, sc.grouped / 100));
      x("s-partners").innerHTML = partnersHTML(sc);
      x("s-tiles").innerHTML = tile(sc.rezzes, "", "resurrections cast") + tile(sc.duels.won + "–" + sc.duels.lost, "", "duels") + tile(sc.hugs, "", "/hugs given");
      if (sc.partners[0]) x("s-toast").textContent = sc.partners[0].n + " is online. You have run " + sc.partners[0].runs + " dungeons together.";
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
  // A ladder bound to one server type greys out the others.
  function realmAllowed(r) { var only = VIEWS[view].only; return r === "all" || !only || r === only; }
  function fixRealm() { if (!realmAllowed(realmFilter)) realmFilter = "all"; }
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
    fixRealm();
    query = (p.get("q") || "").trim();
    var pg = parseInt(p.get("p"), 10);
    if (pg > 1) page = pg - 1;
  }
  function syncControls() {
    var rail = $("lb-rail");
    Array.prototype.forEach.call(rail.querySelectorAll("button[data-v]"), function (b) {
      var on = b.getAttribute("data-v") === view;
      b.classList.toggle("on", on);
      b.setAttribute("aria-selected", String(on));
      if (on && rail.scrollWidth > rail.clientWidth) rail.scrollLeft = b.offsetLeft - (rail.clientWidth - b.offsetWidth) / 2;
    });
    var only = VIEWS[view].only;
    Array.prototype.forEach.call(document.querySelectorAll("#lb-realm button[data-r]"), function (b) {
      var r = b.getAttribute("data-r"), on = r === realmFilter;
      b.classList.toggle("on", on);
      b.setAttribute("aria-checked", String(on));
      b.disabled = !realmAllowed(r);
      b.title = b.disabled ? VIEWS[view].label + " only exists on " + only + " servers" : "";
    });
    var search = $("search");
    if (search && search.value !== query) search.value = query;
  }
  function render() {
    syncURL();
    var v = VIEWS[view];
    $("lb-name").textContent = v.label;
    $("lb-ico").style.backgroundImage = "url(" + ICON + v.icon + ".jpg)";
    $("board-sub").textContent = v.sub;
    var now = Date.now();
    $("cap-note").innerHTML = now < CAP30 ? "The beta is capped at <b>level 20</b> until Oct 1, then 30. Boards rank to the live cap."
      : now < LAUNCH ? "The beta is capped at <b>level 30</b>. Boards rank to the live cap."
      : "Launched: the ladder runs to <b>level 60</b>.";
    var b = $("board");
    $("explain").hidden = demoOn();
    $("lad-live").hidden = !demoOn();
    syncControls();
    Array.prototype.forEach.call(document.querySelectorAll("#lad-switch button"), function (btn) {
      var on = (btn.getAttribute("data-mode") === "preview") === demoOn();
      btn.classList.toggle("on", on);
      btn.setAttribute("aria-selected", String(on));
    });
    if (!demoOn()) { hydrateExplainer(); return; }
    var data = filtered();
    if (!data.length && view !== "guilds") {
      b.innerHTML = '<div class="empty"><h3>No one called <span>\u201c' + esc(query) + '\u201d</span></h3>' +
        "<p>" + DEMO.length + " players are on the ladder. Try fewer letters.</p></div>";
      return;
    }
    b.classList.remove("is-drawn");
    b.innerHTML = v.render(data);
    Array.prototype.forEach.call(b.querySelectorAll("tbody tr"), function (tr) {
      var n = parseInt(tr.querySelector(".rank").textContent, 10);
      if (n <= 3) tr.classList.add("p" + n);
    });
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

    function pickView(v) { view = v; fixRealm(); page = 0; render(); }
    $("lb-rail").addEventListener("click", function (e) {
      var b = e.target.closest("button[data-v]");
      if (b) pickView(b.getAttribute("data-v"));
    });
    $("lb-realm").addEventListener("click", function (e) {
      var b = e.target.closest("button[data-r]");
      if (!b || b.disabled) return;
      realmFilter = b.getAttribute("data-r"); page = 0; render();
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
    var chips = document.querySelector(".hx-ladders");
    if (chips) chips.addEventListener("click", function (e) {
      var b = e.target.closest("button[data-open]");
      if (!b) return;
      setPreview(true); pickView(b.getAttribute("data-open")); goLadder();
    });
    var tabs = $("hx-tabs");
    if (tabs) tabs.addEventListener("click", function (e) {
      var b = e.target.closest("button[data-t]");
      if (!b) return;
      var t = b.getAttribute("data-t");
      Array.prototype.forEach.call(tabs.querySelectorAll("button"), function (o) { o.classList.toggle("on", o === b); o.setAttribute("aria-selected", String(o === b)); });
      Array.prototype.forEach.call(document.querySelectorAll(".hx-dash"), function (d) { d.hidden = d.getAttribute("data-p") !== t; });
    });
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
      var label = share.querySelector("span");
      function done() {
        label.textContent = "Link copied";
        setTimeout(function () { label.textContent = "Copy link"; }, 1600);
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
    render();
  });
})();
