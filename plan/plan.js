/* The Forge v3: plan a Forever beta character, share it as a link.
 * Class data (full vanilla rows 1-5 talent trees, class-appropriate gear)
 * lives in plan-data.json; races, racials and the quiz live here. Spec is
 * not a step: it is wherever your points went, like the game itself. */
(function () {
  "use strict";

  var CAPS = { 20: 11, 30: 21, 60: 51 };
  var cap = 30;
  function POINTSNOW() { return CAPS[cap]; }
  var CDN = "https://wow.zamimg.com/images/wow/icons/large/";

  var CLASS_COLOUR = {
    WARRIOR: "#c79c6e", PALADIN: "#f58cba", HUNTER: "#abd473", ROGUE: "#fff569",
    PRIEST: "#ffffff", SHAMAN: "#0070de", MAGE: "#69ccf0", WARLOCK: "#9482c9", DRUID: "#ff7d0a"
  };
  var CLASS_ICON = {
    WARRIOR: "classicon_warrior", PALADIN: "classicon_paladin", HUNTER: "classicon_hunter",
    ROGUE: "classicon_rogue", PRIEST: "classicon_priest", SHAMAN: "classicon_shaman",
    MAGE: "classicon_mage", WARLOCK: "classicon_warlock", DRUID: "classicon_druid"
  };
  var CLASS_ORDER = ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"];
  var CLASS_LABEL = { WARRIOR: "Warrior", PALADIN: "Paladin", HUNTER: "Hunter", ROGUE: "Rogue",
    PRIEST: "Priest", SHAMAN: "Shaman", MAGE: "Mage", WARLOCK: "Warlock", DRUID: "Druid" };

  // Why each class is secretly the right answer. Requested verbatim in spirit.
  var CLASS_JOKE = {
    WARRIOR: "Complains regardless of what happens, so nothing is ever your fault. Strong pick.",
    PALADIN: "Owns three vital cooldowns, uses none of them. The bubble is for hearthing.",
    HUNTER: "The pet pulls the second pack. You will type lol and mean it.",
    ROGUE: "Never interrupts, vanishes the moment the wipe starts. Honestly? Efficient.",
    PRIEST: "Heals and Power Infusion are billable hours. The gold earner of the guild.",
    SHAMAN: "Plays whatever the raid is missing. Forever. Our condolences.",
    MAGE: "Always dying, somehow still smug about the decurses. Brings his own funeral snacks.",
    WARLOCK: "Permanently has aggro, insists it is fine, life taps below the healer's dignity.",
    DRUID: "Qualified for every job, currently doing none of them, travel form, wrong direction."
  };

  // Races: what is SHARED from the reveal vs what we ASSUME survives from
  // vanilla, plus vanilla base-stat offsets (relative to Human) for the
  // compare panel. Forever will tune these; the panel says so.
  var RACES = [
    { n: "Human", f: "Alliance", i: "achievement_character_human_male",
      st: { str: 0, agi: 0, sta: 0, int: 0, spi: 0 },
      rx: [["Sword Specialization", "+2% critical strike with swords", "shared"],
           ["Mace Specialization", "+2% critical strike with maces", "shared"],
           ["The Human Spirit", "+5% Spirit", "assumed"],
           ["Diplomacy", "+10% reputation gains", "assumed"]],
      tip: "The beige of races. Beige got crit chance in the rework." },
    { n: "Dwarf", f: "Alliance", i: "achievement_character_dwarf_male",
      st: { str: 2, agi: -4, sta: 3, int: -1, spi: -1 },
      rx: [["Stoneform", "Clears Bleed, Poison and Disease; physical damage reduction", "shared"],
           ["Mace Specialization", "+1% critical strike with maces", "shared"],
           ["Big Game Hunter", "Extra damage versus Beasts", "shared"],
           ["Find Treasure", "See treasure on the minimap; stacks with tracking", "shared"]],
      tip: "A pocket no to half the dungeon's mechanics." },
    { n: "Night Elf", f: "Alliance", i: "achievement_character_nightelf_male",
      st: { str: -4, agi: 4, sta: -1, int: 0, spi: 0 },
      rx: [["Shadowmeld", "Vanish into shadow while still", "shared"],
           ["Wisp Spirit", "Faster ghost. Planning ahead", "shared"],
           ["Elune's Light", "New combat racial; details unrevealed", "shared"],
           ["Quickness", "+1% dodge", "assumed"]],
      tip: "You will die less and corpse-run faster. Cover both outcomes." },
    { n: "Gnome", f: "Alliance", i: "achievement_character_gnome_male",
      st: { str: -5, agi: 3, sta: -1, int: 3, spi: 0 },
      rx: [["Escape Artist", "Break roots and snares", "assumed"],
           ["Expansive Mind", "Increases your maximum resource", "shared"],
           ["Eureka!", "Next 3 spells or abilities cost less and do +10%", "shared"],
           ["Engineering Specialist", "+15 Engineering", "assumed"]],
      tip: "Small hitbox, smaller respect, now with a science button." },
    { n: "Orc", f: "Horde", i: "achievement_character_orc_male",
      st: { str: 3, agi: -3, sta: 2, int: -3, spi: 3 },
      rx: [["Blood Fury", "Attack power burst; heals hurt you briefly", "assumed"],
           ["Hardiness", "Resist stuns more often", "assumed"],
           ["Axe Specialization", "Now +critical strike with axes", "shared"],
           ["Command", "+5% pet damage", "assumed"]],
      tip: "Turns 'stun him!' into a suggestion." },
    { n: "Undead", f: "Horde", i: "achievement_character_undead_male",
      st: { str: -1, agi: -2, sta: 1, int: -2, spi: 5 },
      rx: [["Will of the Forsaken", "Clears Charm, Fear and Sleep; no longer immunity", "shared"],
           ["Cannibalize", "Restores Health AND Mana. Waste not", "shared"],
           ["Touch of the Grave", "Chance to drain life on hit", "shared"],
           ["Underwater Breathing", "Unchanged. Still unnecessary. Still funny", "shared"]],
      tip: "The PvP race, forever. Now the corpse is also lunch." },
    { n: "Tauren", f: "Horde", i: "achievement_character_tauren_male",
      st: { str: 5, agi: -5, sta: 2, int: -5, spi: 2 },
      rx: [["War Stomp", "AoE stun around you", "assumed"],
           ["Endurance", "+5% maximum health", "shared"],
           ["Cultivation", "Bonus herbs, no Herbalism required", "shared"],
           ["Nature Resistance", "+10 Nature resistance", "assumed"]],
      tip: "Walks slowly into melee; everyone still backs up. The economy moos." },
    { n: "Troll", f: "Horde", i: "achievement_character_troll_male",
      st: { str: 1, agi: 2, sta: 1, int: -4, spi: 1 },
      rx: [["Berserking", "Attack and cast speed burst, stronger when hurt", "assumed"],
           ["Beast Slaying", "+5% damage versus Beasts", "shared"],
           ["Bow and Throwing Specialization", "Reworked toward critical strike", "assumed"],
           ["Regeneration", "Extra health regen, some of it in combat", "assumed"]],
      tip: "The levelling racials nobody reads and everybody feels." },
    { n: "Skyborne (High Order)", f: "Alliance", i: "inv_feather_02", nu: true, st: null,
      rx: [["Walk on Air", "Glide downward for 10 seconds", "shared"],
           ["Read Ley Line", "Double Health and Mana regeneration for 15s", "shared"],
           ["Wind Blessed", "+1% melee, ranged and spell haste", "shared"],
           ["Elemental Insight", "+5% damage to Elementals", "shared"]],
      tip: "Requires the Skyborne Heroic Pack. Base stats unpublished; the sky keeps secrets." },
    { n: "Skyborne (Windshaper)", f: "Horde", i: "inv_feather_04", nu: true, st: null,
      rx: [["Walk on Air", "Glide downward for 10 seconds", "shared"],
           ["Skysight", "+10% run speed", "shared"],
           ["Wind Blessed", "+1% melee, ranged and spell haste", "shared"],
           ["Elemental Insight", "+5% damage to Elementals", "shared"]],
      tip: "Requires the Skyborne Heroic Pack. Base stats unpublished; ask the wind." }
  ];

  var COMBOS = {
    WARRIOR: ["Human", "Dwarf", "Night Elf", "Gnome", "Orc", "Undead", "Tauren", "Troll", "Skyborne (High Order)", "Skyborne (Windshaper)"],
    PALADIN: ["Human", "Dwarf", "Undead"],
    HUNTER: ["Human", "Dwarf", "Night Elf", "Orc", "Tauren", "Troll", "Skyborne (High Order)", "Skyborne (Windshaper)"],
    ROGUE: ["Human", "Dwarf", "Night Elf", "Gnome", "Orc", "Undead", "Troll", "Skyborne (High Order)", "Skyborne (Windshaper)"],
    PRIEST: ["Human", "Dwarf", "Night Elf", "Gnome", "Undead", "Troll"],
    SHAMAN: ["Dwarf", "Orc", "Tauren", "Troll", "Skyborne (Windshaper)"],
    MAGE: ["Human", "Gnome", "Orc", "Undead", "Troll", "Skyborne (High Order)"],
    WARLOCK: ["Human", "Gnome", "Orc", "Undead", "Troll"],
    DRUID: ["Night Elf", "Tauren", "Skyborne (High Order)", "Skyborne (Windshaper)"]
  };
  var NEWCOMBOS = { "Human:HUNTER": 1, "Dwarf:SHAMAN": 1, "Gnome:PRIEST": 1, "Orc:MAGE": 1,
    "Troll:WARLOCK": 1, "Undead:PALADIN": 1 };
  function isNewCombo(raceName, clsKey) {
    if (raceName.indexOf("Skyborne") === 0) return true;
    return !!NEWCOMBOS[raceName + ":" + clsKey];
  }

  // "I don't know what to play": three questions, one verdict, zero refunds.
  var QUIZ = [
    { q: "The dungeon pull goes wrong. You:", a: [
      ["Get louder. It was clearly someone else's fault.", { WARRIOR: 2, Orc: 1 }],
      ["Bubble. Hearth. Log off with dignity.", { PALADIN: 2, Undead: 1 }],
      ["Vanish. Historically, you were never here.", { ROGUE: 2, "Night Elf": 1 }],
      ["Keep everyone alive, then invoice them.", { PRIEST: 2, Human: 1 }]] },
    { q: "Your dream Tuesday in Azeroth:", a: [
      ["The same dungeon fourteen times. On principle.", { HUNTER: 2, Dwarf: 1 }],
      ["Reading the auction house like a morning paper.", { MAGE: 2, Gnome: 1 }],
      ["Being needed. Resentfully.", { SHAMAN: 2, Tauren: 1 }],
      ["Setting fire to something with a family.", { WARLOCK: 2, Troll: 1 }]] },
    { q: "Pick the problem you would enjoy having:", a: [
      ["Everything aggroes me. Personally.", { WARLOCK: 2, Undead: 1 }],
      ["I have four jobs and zero thanks.", { DRUID: 2, Tauren: 1 }],
      ["I am somehow the snack dispenser now.", { MAGE: 2, Human: 1 }],
      ["My pet has opinions and a criminal record.", { HUNTER: 2, "Skyborne (High Order)": 1 }]] }
  ];
  var QUIZ_NAMES = ["Pullsplainer", "Bubblehearth", "Notmyfault", "Invoicer", "Sameagain",
    "Ahfresh", "Neededish", "Arsonry", "Aggromagnet", "Fourjobs", "Snackbar", "Petlawyer"];

  // ---- state ----------------------------------------------------------------
  var DATA = null;                       // plan-data.json: full trees + gear per class
  var S = { race: -1, cls: -1, t: [[], [], []], gear: [], name: "" };
  var lastSwap = null;
  var viewStep = null;   // revisit a step without losing the build                   // the compare panel's food
  var STEPS = ["Race", "Class", "Talents", "Gear", "Name it"];
  var GUIDE = {
    0: "First: the body you will regret in dungeons and defend in guild chat. <b>Pick a race</b> and its racials unfold below. Not sure? The coward's button is right there.",
    1: "Now the job. The REAL Forever matrix: Undead Paladins live, Dwarves found totems. <b>Pick a class.</b> Gold NEW tags mark combos vanilla never allowed.",
    2: "No spec step: <b>your points ARE your spec</b>, exactly like the game. 21 points at cap 30, rows open at 5/10/15/20 in a tree. Left click adds, right click removes. Then gear up, name it, share it."
  };

  function $(id) { return document.getElementById(id); }
  function esc(s) { return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
  function cc(k) { return CLASS_COLOUR[k] || "#fff"; }
  function icon(name, cls) { return '<img class="' + (cls || "wi") + '" src="' + CDN + name + '.jpg" alt="" loading="lazy" onerror="this.style.visibility=\'hidden\'">'; }
  function dt(title, body) { return 'data-tip="<b>' + esc(title) + "</b>" + esc(body) + '"'; }
  function qv(band) { return "var(--q-" + ({ grey: "common", uncommon: "uncommon", rare: "rare", epic: "epic" }[band] || "common") + ")"; }
  function clsData() { return DATA && S.cls >= 0 ? DATA.classes[S.cls] : null; }
  function treePts(ti) { return (S.t[ti] || []).reduce(function (a, b) { return a + (b || 0); }, 0); }
  function spent() { return treePts(0) + treePts(1) + treePts(2); }
  function specNow() {
    var c = clsData();
    if (!c) return null;
    var best = 0;
    for (var i = 1; i < 3; i++) if (treePts(i) > treePts(best)) best = i;
    return { name: c.trees[best].name, role: c.trees[best].role, split: treePts(0) + "/" + treePts(1) + "/" + treePts(2) };
  }

  // ---- url as the save (v2 code: race.cls.talents.gear.name) ---------------
  function code() {
    return [S.race, S.cls, S.t.map(function (a) { return a.join(""); }).join("-"),
      S.gear.map(function (g) { return g == null ? "x" : g; }).join("~"),
      encodeURIComponent(S.name || ""), cap].join(".");
  }
  function parseCode(str) {
    var p = String(str || "").split(".");
    if (p.length >= 6 && String(p[3]).indexOf("-") !== -1) p.splice(2, 1); // v1 codes carried a spec index
    var o = { race: +p[0], cls: +p[1], t: [[], [], []], gear: [], name: decodeURIComponent(p[4] || "") };
    if (!(o.race >= 0 && o.race < RACES.length && o.cls >= 0 && o.cls < 9)) return null;
    var segs = String(p[2] || "").split("-");
    for (var ti = 0; ti < 3; ti++) {
      var seg = segs[ti] || "";
      for (var i = 0; i < seg.length; i++) o.t[ti][i] = +seg[i] || 0;
    }
    String(p[3] || "").split("~").forEach(function (ch, g) {
      o.gear[g] = (ch === "x" || ch === "") ? null : +ch;
    });
    o.cap = CAPS[+p[5]] ? +p[5] : 30;
    return o;
  }
  function clampToData(o) {
    if (!DATA || !o) return o;
    var c = DATA.classes[o.cls];
    if (!c) return o;
    for (var ti = 0; ti < 3; ti++) {
      var tal = c.trees[ti].talents;
      o.t[ti] = tal.map(function (t, i) { return Math.min(t.r, o.t[ti][i] || 0); });
    }
    o.gear = c.gear.map(function (g, i) {
      var v = o.gear[i];
      return v != null && v >= 0 && v < g.items.length ? v : null;
    });
    var total = 0;
    for (ti = 0; ti < 3; ti++) for (var i2 = 0; i2 < o.t[ti].length; i2++) {
      total += o.t[ti][i2];
      if (total > POINTSNOW()) { o.t[ti][i2] -= (total - POINTSNOW()); total = POINTSNOW(); }
    }
    return o;
  }
  function syncURL() {
    var done = S.race >= 0 && S.cls >= 0;
    history.replaceState(null, "", done ? "?b=" + code() : location.pathname);
    try { localStorage.setItem("forge3", done ? code() : ""); } catch (e) {}
  }

  // ---- tooltips -------------------------------------------------------------
  var tip = null;
  function bindTips(root) {
    root.querySelectorAll("[data-tip]").forEach(function (el) {
      el.addEventListener("mouseenter", function () {
        tip = $("tip"); tip.innerHTML = el.getAttribute("data-tip"); tip.hidden = false;
      });
      el.addEventListener("mousemove", function (e) {
        if (!tip) return;
        var x = Math.min(e.clientX + 14, window.innerWidth - tip.offsetWidth - 10);
        var y = Math.min(e.clientY + 16, window.innerHeight - tip.offsetHeight - 10);
        tip.style.left = x + "px"; tip.style.top = y + "px";
      });
      el.addEventListener("mouseleave", function () { $("tip").hidden = true; tip = null; });
    });
  }

  // ---- compare: what a swap nets and what it loses --------------------------
  function raceDelta(oldIdx, newIdx) {
    var A = RACES[oldIdx], B = RACES[newIdx], parts = [];
    if (A.st && B.st) {
      var stats = ["str", "agi", "sta", "int", "spi"], lab = { str: "Str", agi: "Agi", sta: "Sta", int: "Int", spi: "Spi" };
      var deltas = stats.map(function (k) {
        var d = B.st[k] - A.st[k];
        return d ? '<span class="' + (d > 0 ? "gain" : "loss") + '">' + (d > 0 ? "+" : "") + d + " " + lab[k] + "</span>" : null;
      }).filter(Boolean);
      parts.push("<b>Stats:</b> " + (deltas.length ? deltas.join(" ") : "a perfect wash") +
        ' <i class="finenote">(vanilla base offsets; Forever tuning pending)</i>');
    } else {
      parts.push("<b>Stats:</b> Skyborne base stats are unpublished. You traded numbers for wings.");
    }
    function abilNames(R) {
      var tf = tfRace(R.n);
      return tf && tf.abilities.length ? tf.abilities.map(function (a) { return a[0]; }) : R.rx.map(function (r) { return r[0]; });
    }
    var an = abilNames(A), bn = abilNames(B);
    var gained = bn.filter(function (x) { return an.indexOf(x) === -1; });
    var lost = an.filter(function (x) { return bn.indexOf(x) === -1; });
    if (gained.length) parts.push('<b>Gained:</b> <span class="gain">' + esc(gained.join(", ")) + "</span>");
    if (lost.length) parts.push('<b>Lost:</b> <span class="loss">' + esc(lost.join(", ")) + "</span>");
    return { title: A.n + " → " + B.n + ", build kept", parts: parts };
  }
  function classDelta(oldK, newK) {
    return { title: CLASS_LABEL[oldK] + " → " + CLASS_LABEL[newK] + ", talents reforged",
      parts: ['<b>Left behind:</b> ' + esc(CLASS_JOKE[oldK]), '<b>Signed up for:</b> ' + esc(CLASS_JOKE[newK]),
        '<i class="finenote">Talent trees do not transfer between classes. The game agrees.</i>'] };
  }
  function swapHTML() {
    if (!lastSwap) return "";
    return '<div class="swapnote"><div class="sw-head"><b>' + esc(lastSwap.title) +
      '</b><button type="button" class="sw-x" id="sw-x" aria-label="Dismiss">&times;</button></div>' +
      lastSwap.parts.map(function (p) { return '<p class="line">' + p + "</p>"; }).join("") + "</div>";
  }

  // ---- rendering ------------------------------------------------------------
  function stepNow() { return S.race < 0 ? 0 : S.cls < 0 ? 1 : 2; }
  function drawSteps() {
    var now = viewStep != null ? viewStep : stepNow();
    $("fsteps").innerHTML = STEPS.map(function (n, i) {
      var logical = i <= 1 ? i : 2;
      var cls = logical < now ? "done" : logical === now ? (i > 2 ? "done" : "now") : "locked";
      return '<li class="' + cls + '" data-step="' + i + '">' + (i + 1) + ". " + n + "</li>";
    }).join("");
    $("guide").innerHTML = "<p>" + GUIDE[now] + "</p>";
  }

  function render() {
    drawSteps(); syncURL();
    var st = $("stage"), now = viewStep != null ? viewStep : stepNow(), html = swapHTML();
    if (!DATA) {
      st.innerHTML = '<div class="verdict">Forging the class data\u2026</div>';
      return;
    }
    if (viewStep === 0 && S.cls < 0 && S.race >= 0)
      $("guide").innerHTML = "<p>That is the body. The racials are unfolded below; read the fine print, then <b>continue to the class.</b></p>";
    if (viewStep === 0 && S.cls >= 0)
      $("guide").innerHTML = "<p>Swap the body, keep the build. The compare panel totals the damage. <b>Races your class cannot be are refused politely.</b></p>";
    if (viewStep === 1 && S.cls >= 0)
      $("guide").innerHTML = "<p>Change the job, lose the talents; that is the game, not us. The compare panel quotes both trades. <b>Pick.</b></p>";
    if (now === 0) html += raceStage() + (S.race >= 0 ? raceExpand(S.race) : "");
    else if (now === 1) html += classStage();
    else html += talentsHTML() + gearHTML() + nameHTML() + buildHTML();
    st.innerHTML = html;
    wire(st); bindTips(st);
  }

  function tfRace(name) {
    if (!DATA || !DATA.races) return null;
    for (var i = 0; i < DATA.races.length; i++) if (DATA.races[i].n === name) return DATA.races[i];
    return null;
  }
  function racialList(r) {
    var tf = tfRace(r.n);
    if (tf && tf.abilities.length) {
      return '<ul class="racials">' + tf.abilities.map(function (a) {
        return "<li>" + (a[2] ? icon(a[2], "wi wi-sm") : "") + '<b>' + esc(a[0]) + '</b><span>' +
          esc(a[1]) + '</span><i class="tag shared">demo</i></li>';
      }).join("") + "</ul>" +
      '<p class="line finenote">Racials transcribed from BlizzCon footage; sources credited on GitHub.</p>';
    }
    return '<ul class="racials">' + r.rx.map(function (x) {
      return "<li>" + '<b>' + esc(x[0]) + '</b><span>' + esc(x[1]) + '</span><i class="tag ' + x[2] + '">' + x[2] + "</i></li>";
    }).join("") + "</ul>";
  }
  function raceStage() {
    var html = '<div class="dunno-row"><button type="button" class="share dunno" id="dunno">I don’t know what to play</button>' +
      '<i class="finenote">Three questions. The Forge decides. No refunds.</i></div>';
    html += '<div class="cards">' + RACES.map(function (r, i) {
      return '<button class="card' + (S.race === i ? " sel" : "") + '" data-race="' + i + '" ' + dt(r.n, r.tip) + ">" +
        icon(r.i, "wi wi-lg") + "<b>" + esc(r.n) + "</b><i>" + r.f + (r.nu ? " (probably)" : "") + "</i></button>";
    }).join("") + "</div>";
    return html;
  }
  function raceExpand(i) {
    var r = RACES[i];
    var st = r.st
      ? '<p class="line finenote">Base stat offsets vs Human (vanilla): ' +
        ["str", "agi", "sta", "int", "spi"].map(function (k) {
          var v = r.st[k]; return (v > 0 ? "+" : "") + v + " " + k.charAt(0).toUpperCase() + k.slice(1);
        }).join(", ") + "</p>"
      : '<p class="line finenote">Base stats unpublished. The sky keeps its spreadsheet.</p>';
    return '<div class="race-x">' + '<div class="rx-head">' + icon(r.i, "wi") + "<b>" + esc(r.n) + "</b><span>" + esc(r.f) + "</span></div>" +
      racialList(r) + st +
      '<div class="b-actions"><button type="button" class="share" id="rcont">' +
      (S.cls < 0 ? "Continue: pick the class" : "Back to the anvil") + "</button></div>" +
      '<p class="line finenote">Swap races any time; the build stays and the compare panel totals the damage.</p></div>';
  }
  function classStage() {
    var rn = RACES[S.race].n;
    return '<div class="cards">' + CLASS_ORDER.map(function (k, i) {
      var ok = COMBOS[k].indexOf(rn) !== -1;
      return '<button class="card' + (ok ? "" : " dis") + (S.cls === i ? " sel" : "") + '"' + (ok ? ' data-cls="' + i + '"' : "") + " " +
        dt(CLASS_LABEL[k], ok ? CLASS_JOKE[k] + (isNewCombo(rn, k) ? " NEW in Forever: vanilla never allowed this." : "") : "A " + rn + " cannot be a " + CLASS_LABEL[k] + ". Even Forever did not go that far.") + ">" +
        icon(CLASS_ICON[k], "wi wi-lg") + '<b class="cc" style="--cc:' + cc(k) + '">' + CLASS_LABEL[k] + "</b><i>" +
        (ok ? (isNewCombo(rn, k) ? '<span class="newtag">NEW</span>' : "") : "not for " + rn) + "</i></button>";
    }).join("") + "</div>";
  }

  function talentsHTML() {
    var c = clsData(), sp = specNow();
    var html = '<div class="talenthead"><h3>Talents</h3><span class="pts">' + (POINTSNOW() - spent()) +
      ' points left</span><span class="specnow">' + esc(sp.split) + " \u2192 <b>" + esc(sp.name) + "</b> (" + sp.role + ')</span>' +
      '<span class="caps">' + [20, 30, 60].map(function (l) {
        return '<button type="button" class="capbtn' + (cap === l ? " on" : "") + '" data-cap="' + l + '">' + l + "</button>";
      }).join("") + '</span>' +
      '<button type="button" class="share bookbtn" id="bookbtn">Demo spellbook</button>' +
      '<i class="finenote">real Forever trees, BlizzCon transcription; estimates marked</i></div><div class="wtrees">';
    c.trees.forEach(function (tr, ti) {
      var pts = treePts(ti);
      html += '<div class="wtree"><div class="wt-head">' + icon(tr.icon, "wi wi-sm") + "<b>" + esc(tr.name) + '</b><u>' + pts + "</u></div><div class=\"wt-grid rows5\">";
      tr.talents.forEach(function (t, i) {
        var r = S.t[ti][i] || 0, gate = (t.row - 1) * 5, open = pts >= gate;
        var d = t.desc && t.desc.length ? t.desc[Math.min(r < t.r ? r : t.r - 1, t.desc.length - 1)] : (t.tip || "");
        var extra = (t.est ? " [numbers still estimates]" : "") + (t.cn ? " \u00b7 " + t.cn + "." : "");
        var how = open ? " \u2014 Left click adds; right click removes." : " \u2014 Needs " + gate + " points in " + tr.name + ".";
        html += '<div class="slot' + (r >= t.r ? " maxed" : r > 0 ? " part" : "") + (open ? "" : " locked") + (t.est ? " est" : "") +
          '" style="grid-column:' + t.col + ";grid-row:" + t.row + '" data-tal="' + ti + ":" + i + '" ' +
          dt(t.n + " (" + r + "/" + t.r + ")" + (r < t.r && t.desc && t.desc.length > 1 ? " \u2014 next rank:" : ""), d + extra + how) + ">" +
          icon(t.icon, "wi") + '<span class="s-rank">' + r + "/" + t.r + "</span></div>";
      });
      html += "</div></div>";
    });
    return html + "</div>";
  }

  function gearHTML() {
    var c = clsData();
    var html = '<div class="talenthead"><h3>Gear</h3><i class="finenote">what a ' + esc(CLASS_LABEL[CLASS_ORDER[S.cls]]) +
      ' actually wears at 15–33; datamined Forever loot replaces this</i></div>';
    c.gear.forEach(function (g, gi) {
      html += '<div class="gearrow"><label>' + esc(g.slot) + '</label><div class="gearopts">' +
        g.items.map(function (o, oi) {
          return '<button class="gitem' + (S.gear[gi] === oi ? " sel" : "") + '" style="--q:' + qv(o.q) + '" data-gear="' + gi + ":" + oi + '" ' +
            dt(o.n, o.stats + " — " + o.src) + ">" + icon(o.icon, "wi wi-sm") + "<span>" + esc(o.n) + "</span></button>";
        }).join("") + "</div></div>";
    });
    return html;
  }

  function nameHTML() {
    return '<div class="namer"><input id="cname" maxlength="16" placeholder="Name the poor thing" value="' + esc(S.name) + '">' +
      '<button type="button" class="share" id="bshare">Share build</button>' +
      '<button type="button" class="share" id="bcopy">Copy as text</button>' +
      '<button type="button" class="share" id="breset">Start over</button></div>';
  }

  function talentList() {
    var c = clsData(), out = [];
    c.trees.forEach(function (tr, ti) {
      tr.talents.forEach(function (t, i) { if ((S.t[ti][i] || 0) > 0) out.push(t.n + " " + S.t[ti][i] + "/" + t.r); });
    });
    return out;
  }
  function buildHTML() {
    var r = RACES[S.race], k = CLASS_ORDER[S.cls], c = clsData(), sp = specNow();
    var gear = c.gear.map(function (g, i) { return S.gear[i] != null ? g.items[S.gear[i]].n : null; }).filter(Boolean);
    var tal = talentList();
    return '<div class="buildcard"><h3>' + esc(S.name || "Unnamed " + CLASS_LABEL[k]) + "</h3>" +
      '<p class="line">' + icon(r.i, "wi wi-sm") + " " + esc(r.n) + ' · <span style="color:' + cc(k) + '">' + CLASS_LABEL[k] + "</span> · " +
      esc(sp.name) + " (" + esc(sp.split) + ') · <span class="rolechip ' + sp.role + '">' + sp.role + "</span> · level " + cap + "</p>" +
      '<p class="line"><i>Talents (' + spent() + "/" + POINTSNOW() + "):</i> " + (tal.length ? esc(tal.join(", ")) : "none yet, a purist") + "</p>" +
      '<p class="line"><i>Gear:</i> ' + (gear.length ? esc(gear.join(", ")) : "honest and naked") + "</p></div>";
  }
  function buildText() {
    var r = RACES[S.race], k = CLASS_ORDER[S.cls], c = clsData(), sp = specNow();
    var gear = c.gear.map(function (g, i) { return S.gear[i] != null ? "  " + g.slot + ": " + g.items[S.gear[i]].n : null; }).filter(Boolean);
    return (S.name || "Unnamed") + " — " + r.n + " " + sp.name + " " + CLASS_LABEL[k] + " (" + sp.role + ", " + sp.split + ", cap " + cap + ")\n" +
      "Talents (" + spent() + "/" + POINTSNOW() + "):\n" + (talentList().map(function (t) { return "  " + t; }).join("\n") || "  none") +
      "\nGear:\n" + (gear.join("\n") || "  none") + "\n" + location.origin + location.pathname + "?b=" + code();
  }

  // ---- the coward's button --------------------------------------------------
  function quizHTML() {
    return '<h2 class="in-name">The Forge decides</h2>' +
      '<p class="in-h">Answer honestly. It knows when you lie.</p>' +
      QUIZ.map(function (q, qi) {
        return '<p class="qq">' + esc(q.q) + '</p><div class="qa">' + q.a.map(function (a, ai) {
          return '<button type="button" class="qopt" data-q="' + qi + '" data-a="' + ai + '">' + esc(a[0]) + "</button>";
        }).join("") + "</div>";
      }).join("") +
      '<div class="b-actions"><button type="button" class="share" id="qgo" disabled>Forge me</button></div>';
  }
  function runQuiz(answers) {
    var score = {};
    answers.forEach(function (ai, qi) {
      var w = QUIZ[qi].a[ai][1];
      Object.keys(w).forEach(function (k) { score[k] = (score[k] || 0) + w[k]; });
    });
    var k = CLASS_ORDER.slice().sort(function (a, b) { return (score[b] || 0) - (score[a] || 0); })[0];
    var allowed = COMBOS[k];
    var race = allowed.slice().sort(function (a, b) { return (score[b] || 0) - (score[a] || 0); })[0];
    S = { race: RACES.map(function (r) { return r.n; }).indexOf(race), cls: CLASS_ORDER.indexOf(k), t: [[], [], []], gear: [], name: QUIZ_NAMES[(answers[0] * 4 + answers[1] + answers[2]) % QUIZ_NAMES.length] };
    // Dump the 21 points down the first tree like a tourist with a map.
    var tal = DATA.classes[S.cls].trees[0].talents, left = POINTSNOW();
    tal.forEach(function (t, i) {
      if (!left) return;
      var pts = treePts(0), gate = (t.row - 1) * 5;
      if (pts < gate) return;
      var take = Math.min(t.r, left);
      S.t[0][i] = take; left -= take;
    });
    lastSwap = { title: "The Forge has spoken: " + race + " " + CLASS_LABEL[k],
      parts: [esc(CLASS_JOKE[k]), '<i class="finenote">Points were poured into the first tree. Rearrange them; the Forge will pretend it agrees.</i>'] };
    viewStep = null;
    $("insight").hidden = true;
    render(); window.scrollTo(0, 0);
  }

  // ---- wiring ---------------------------------------------------------------
  function wire(st) {
    var x = st.querySelector("#sw-x");
    if (x) x.addEventListener("click", function () { lastSwap = null; render(); });
    st.querySelectorAll("[data-race]").forEach(function (el) {
      el.addEventListener("click", function () {
        var i = +el.getAttribute("data-race");
        if (S.race === i) return;
        if (S.race >= 0 && S.cls >= 0) {
          var k = CLASS_ORDER[S.cls];
          if (COMBOS[k].indexOf(RACES[i].n) === -1) {
            lastSwap = { title: RACES[i].n + " refused", parts: ["A " + esc(RACES[i].n) + " cannot be a " + CLASS_LABEL[k] + ". The build stays as it was."] };
            render(); return;
          }
          lastSwap = raceDelta(S.race, i);   // build kept, compare shown
        }
        S.race = i;
        viewStep = 0;                        // stay: the racials unfold first
        render();
      });
    });
    var rc = st.querySelector("#rcont");
    if (rc) rc.addEventListener("click", function () { viewStep = null; render(); window.scrollTo(0, 0); });
    st.querySelectorAll("[data-cls]").forEach(function (el) {
      el.addEventListener("click", function () {
        var i = +el.getAttribute("data-cls");
        if (S.cls === i) { viewStep = null; render(); return; }
        if (S.cls >= 0) lastSwap = classDelta(CLASS_ORDER[S.cls], CLASS_ORDER[i]);
        S.cls = i; S.t = [[], [], []]; S.gear = [];
        viewStep = null;
        render();
      });
    });
    st.querySelectorAll(".slot[data-tal]").forEach(function (el) {
      var p = el.getAttribute("data-tal").split(":"), ti = +p[0], i = +p[1];
      var t = clsData().trees[ti].talents[i];
      el.addEventListener("click", function () {
        if (treePts(ti) < (t.row - 1) * 5 || spent() >= POINTSNOW()) return;
        S.t[ti][i] = Math.min(t.r, (S.t[ti][i] || 0) + 1); render();
      });
      el.addEventListener("contextmenu", function (e) {
        e.preventDefault();
        if ((S.t[ti][i] || 0) > 0) { S.t[ti][i]--; render(); }
      });
    });
    st.querySelectorAll("[data-gear]").forEach(function (el) {
      el.addEventListener("click", function () {
        var p = el.getAttribute("data-gear").split(":");
        S.gear[+p[0]] = S.gear[+p[0]] === +p[1] ? null : +p[1]; render();
      });
    });
    st.querySelectorAll(".capbtn").forEach(function (b) {
      b.addEventListener("click", function () {
        cap = +b.getAttribute("data-cap");
        S = clampToData(S) || S;   // shed points over the new budget
        render();
      });
    });
    var bk = st.querySelector("#bookbtn");
    if (bk) bk.addEventListener("click", function () {
      var c = clsData(), book = c.book || {};
      var html = '<h2 class="in-name">Demo spellbook</h2>' +
        '<p class="in-h">Read off the BlizzCon demo at level ' + (book.level || "?") + ". What exists, not what it costs.</p>";
      (book.tabs || []).forEach(function (tb) {
        html += '<p class="qq">' + esc(tb.name) + "</p><div class=\"roster\">" +
          tb.spells.map(function (sp2) {
            var d2 = (book.desc || {})[sp2[0]];
            return '<span' + (d2 ? " " + dt(sp2[0] + (sp2[1] ? " (" + sp2[1] + ")" : ""), d2) : "") + ">" + esc(sp2[0]) + "</span>";
          }).join("") + "</div>";
      });
      if ((book.general || []).length) {
        html += '<p class="qq">General</p><div class="roster">' +
          book.general.map(function (sp2) { return "<span>" + esc(sp2[0]) + "</span>"; }).join("") + "</div>";
      }
      $("insight-body").innerHTML = html;
      $("insight").hidden = false;
      bindTips($("insight-body"));
    });

    var nm = st.querySelector("#cname");
    if (nm) nm.addEventListener("input", function () { S.name = nm.value; syncURL(); });
    function copyBtn(id, textFn) {
      var b = st.querySelector(id);
      if (!b) return;
      var orig = b.textContent;
      b.addEventListener("click", function () {
        var txt = textFn();
        function done() { b.textContent = "Copied"; setTimeout(function () { b.textContent = orig; }, 1600); }
        if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(txt).then(done, function () { prompt("Copy this:", txt); });
        else prompt("Copy this:", txt);
      });
    }
    copyBtn("#bshare", function () { return location.origin + location.pathname + "?b=" + code(); });
    copyBtn("#bcopy", buildText);
    var br = st.querySelector("#breset");
    if (br) br.addEventListener("click", function () { S = { race: -1, cls: -1, t: [[], [], []], gear: [], name: "" }; lastSwap = null; render(); window.scrollTo(0, 0); });
    var dk = st.querySelector("#dunno");
    if (dk) dk.addEventListener("click", function () {
      $("insight-body").innerHTML = quizHTML();
      $("insight").hidden = false;
      var picks = [null, null, null];
      $("insight-body").querySelectorAll(".qopt").forEach(function (b) {
        b.addEventListener("click", function () {
          var qi = +b.getAttribute("data-q");
          picks[qi] = +b.getAttribute("data-a");
          $("insight-body").querySelectorAll('.qopt[data-q="' + qi + '"]').forEach(function (o) { o.classList.remove("sel"); });
          b.classList.add("sel");
          $("qgo").disabled = picks.some(function (v) { return v == null; });
        });
      });
      $("qgo").addEventListener("click", function () { runQuiz(picks); });
    });
    document.querySelectorAll("#fsteps li").forEach(function (li) {
      li.addEventListener("click", function () {
        var i = +li.getAttribute("data-step");
        if (i === 0) { viewStep = 0; }
        else if (i === 1 && S.race >= 0) { viewStep = 1; }
        else if (S.cls >= 0) { viewStep = null; }
        else return;
        render(); window.scrollTo(0, 0);
      });
    });
  }

  // ---- raid composer --------------------------------------------------------
  function parseAny(line) {
    var m = String(line).match(/[?&](?:b|raid)=([^&\s]+)/);
    if (m && line.indexOf("raid=") !== -1) return m[1].split(",").map(parseCode).filter(Boolean);
    if (m) { var one = parseCode(m[1]); return one ? [one] : []; }
    var direct = parseCode(line.trim());
    return direct ? [direct] : [];
  }
  function specOf(b) {
    var c = DATA.classes[b.cls], best = 0, pts = [0, 1, 2].map(function (ti) {
      return (b.t[ti] || []).reduce(function (a, x) { return a + (x || 0); }, 0);
    });
    for (var i = 1; i < 3; i++) if (pts[i] > pts[best]) best = i;
    return { name: c.trees[best].name, role: c.trees[best].role, pts: pts[0] + pts[1] + pts[2] };
  }
  function bcode(b) {
    return [b.race, b.cls, b.t.map(function (a) { return a.join(""); }).join("-"),
      b.gear.map(function (g) { return g == null ? "x" : g; }).join("~"), encodeURIComponent(b.name || "")].join(".");
  }
  function compose() {
    if (!DATA) return;
    var lines = $("raid-in").value.split("\n").map(function (l) { return l.trim(); }).filter(Boolean);
    var builds = [];
    lines.forEach(function (l) { builds = builds.concat(parseAny(l)); });
    builds = builds.map(clampToData).filter(Boolean);
    var out = $("raid-out");
    if (!builds.length) {
      out.innerHTML = '<div class="verdict">Nothing parseable in there. Paste build links from The Forge, one per line.</div>';
      $("raid-link").hidden = true; return;
    }
    var roles = { tank: 0, healer: 0, dps: 0 }, classes = {};
    var rows = builds.map(function (b) {
      var k = CLASS_ORDER[b.cls], sp = specOf(b);
      roles[sp.role]++; classes[k] = (classes[k] || 0) + 1;
      return "<tr><td>" + icon(CLASS_ICON[k], "wi wi-sm") + ' <b style="color:' + cc(k) + '">' + esc(b.name || "Unnamed") + "</b></td>" +
        "<td>" + icon(RACES[b.race].i, "wi wi-sm") + " " + esc(RACES[b.race].n) + "</td><td>" + esc(sp.name) + " " + CLASS_LABEL[k] + "</td>" +
        '<td><span class="rolechip ' + sp.role + '">' + sp.role + "</span></td><td>" + sp.pts + "/" + POINTSNOW() + " pts</td></tr>";
    }).join("");
    var v = [];
    v.push("<b>" + builds.length + "</b> forged: " + roles.tank + " tank" + (roles.tank === 1 ? "" : "s") + ", " +
      roles.healer + " healer" + (roles.healer === 1 ? "" : "s") + ", " + roles.dps + " dps.");
    if (!roles.tank) v.push("Zero tanks: the dungeon will be tanked by whoever pulls first. Tradition.");
    if (!roles.healer) v.push("Zero healers: bold. The spirit healer thanks you for the business.");
    if (roles.tank && roles.healer && builds.length >= 5) v.push("This is, technically, a functioning group. Do not let it go to your heads.");
    if (!(classes.MAGE > 0)) v.push("No mage: bring your own water like peasants.");
    if (classes.WARLOCK >= 2) v.push("Two-plus warlocks: summons for everyone, souls for no one.");
    if (classes.WARRIOR >= 3) v.push("Three warriors: the complaints will at least be synchronised.");
    out.innerHTML = '<table class="raidtable"><thead><tr><th>Name</th><th>Race</th><th>Spec</th><th>Role</th><th>Talents</th></tr></thead><tbody>' +
      rows + "</tbody></table>" + '<div class="verdict">' + v.join(" ") + "</div>";
    var rl = $("raid-link");
    rl.hidden = false;
    rl.onclick = function () {
      var url = location.origin + location.pathname + "?raid=" + builds.map(bcode).join(",");
      function done() { rl.textContent = "Raid link copied"; setTimeout(function () { rl.textContent = "Copy raid link"; }, 1600); }
      if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(url).then(done, function () { prompt("Copy this:", url); });
      else prompt("Copy this:", url);
    };
  }

  // ---- boot -----------------------------------------------------------------
  document.addEventListener("DOMContentLoaded", function () {
    render();
    fetch("plan-data.json", { cache: "no-store" }).then(function (r) { return r.json(); }).then(function (d) {
      DATA = d;
      if (d.races && d.races.length) {
        Object.keys(COMBOS).forEach(function (k) { COMBOS[k] = []; });
        d.races.forEach(function (r) {
          r.classes.forEach(function (cn) {
            var k = cn.toUpperCase();
            if (COMBOS[k] && COMBOS[k].indexOf(r.n) === -1) COMBOS[k].push(r.n);
          });
        });
      }
      var p = new URLSearchParams(location.search);
      if (p.get("raid")) {
        $("raid-in").value = location.href;
        render(); compose();
        $("composer").scrollIntoView();
      } else {
        var use = (p.get("b") && parseCode(p.get("b"))) || null;
        if (!use) { try { use = parseCode(localStorage.getItem("forge3")); } catch (e) {} }
        if (use) { cap = use.cap || 30; S = clampToData(use) || S; }
        render();
      }
    }).catch(function () {
      $("stage").innerHTML = '<div class="verdict">Could not load plan-data.json. The anvil is cold; refresh to relight it.</div>';
    });
    $("compose").addEventListener("click", compose);
    $("insight-x").addEventListener("click", function () { $("insight").hidden = true; });
    $("insight").addEventListener("click", function (e) { if (e.target === $("insight")) $("insight").hidden = true; });
    document.addEventListener("keydown", function (e) { if (e.key === "Escape") $("insight").hidden = true; });
  });
})();
