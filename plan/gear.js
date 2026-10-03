/* ForgeGear: the inspect-style gear step. Paperdoll slots, a picker per slot,
 * WoW-style item tooltips and a stat panel that totals what is equipped.
 * Items come from plan/items-db.json (the beta client plus server-sent items);
 * plan/items.json is the small seed shown while the full database loads.
 * window.ForgeItem holds the item helpers the Database (codex) shares. */
(function () {
  "use strict";
  var CDN = "https://wow.zamimg.com/images/wow/icons/large/";
  function esc(s) { return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
  function attr(v) { return esc(v); }
  function img(n, cls) { var src = n && n.indexOf("/") !== -1 ? n : CDN + (n || "inv_misc_questionmark") + ".jpg"; return '<img class="' + (cls || "") + '" src="' + esc(src) + '" alt="" loading="lazy" onerror="this.onerror=null;this.src=\'' + CDN + 'inv_misc_questionmark.jpg\'">'; }
  function lsGet(k) { try { var v = window.localStorage.getItem(k); return v ? JSON.parse(v) : null; } catch (e) { return null; } }
  function lsSet(k, v) { try { window.localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} }

  var SLOTS = {
    left: [["head", "Head", "inventoryslot_head"], ["neck", "Neck", "inventoryslot_neck"], ["shoulder", "Shoulders", "inventoryslot_shoulder"],
      ["back", "Back", "inventoryslot_chest"], ["chest", "Chest", "inventoryslot_chest"], ["wrist", "Wrists", "inventoryslot_wrists"]],
    right: [["hands", "Hands", "inventoryslot_hands"], ["waist", "Waist", "inventoryslot_waist"], ["legs", "Legs", "inventoryslot_legs"], ["feet", "Feet", "inventoryslot_feet"],
      ["finger1", "Finger", "inventoryslot_finger"], ["finger2", "Finger", "inventoryslot_finger"], ["trinket1", "Trinket", "inventoryslot_trinket"], ["trinket2", "Trinket", "inventoryslot_trinket"]],
    bottom: [["mainhand", "Main Hand", "inventoryslot_mainhand"], ["offhand", "Off Hand", "inventoryslot_offhand"], ["ranged", "Ranged or Relic", "inventoryslot_ranged"]]
  };
  var ACCEPT = { head: ["head"], neck: ["neck"], shoulder: ["shoulder"], back: ["back"], chest: ["chest"], wrist: ["wrist"], hands: ["hands"],
    waist: ["waist"], legs: ["legs"], feet: ["feet"], finger1: ["finger"], finger2: ["finger"], trinket1: ["trinket"], trinket2: ["trinket"],
    mainhand: ["main-hand", "one-hand", "two-hand"], offhand: ["off-hand", "one-hand"], ranged: ["ranged", "relic", "thrown"] };
  var SLOT_KEYS = [].concat(SLOTS.left, SLOTS.right, SLOTS.bottom).map(function (s) { return s[0]; });
  var ALLSLOTS = [].concat.apply([], Object.keys(ACCEPT).map(function (k) { return ACCEPT[k]; }));
  var STAT_LINE = { strength: "Strength", agility: "Agility", stamina: "Stamina", intellect: "Intellect", spirit: "Spirit" };
  var QUALITY = ["poor", "common", "uncommon", "rare", "epic", "legendary"];

  // ---- Shared item helpers: The Forge and the Database read items the same way ----
  var ARMOR_TYPES = ["Cloth", "Leather", "Mail", "Plate", "Shield"];
  var SCHOOLS = ["Physical", "Holy", "Fire", "Nature", "Frost", "Shadow", "Arcane"];
  // Shield spikes and the Retricutioner chest enchant, from the beta client's spell tables
  // (build 1.60.1.70170): base points and variance of the damage-on-block and damage-shield auras.
  var DEFAULT_ENCHANTS = { note: "Built-in fallback: plan/enchants.json is missing.", enchants: [
    { id: "iron-spike", item: 6042, name: "Iron Shield Spike", slot: "offhand", needs: "Shield", rf: { k: "block", s: "Physical", v: 10, lo: 8, hi: 12, sp: 9784, src: "client" }, stats: {}, skill: ["Blacksmithing", 150], icon: "inv_misc_armorkit_01" },
    { id: "mithril-spike", item: 7967, name: "Mithril Shield Spike", slot: "offhand", needs: "Shield", rf: { k: "block", s: "Physical", v: 18, lo: 16, hi: 20, sp: 9782, src: "client" }, stats: {}, skill: ["Blacksmithing", 215], icon: "inv_misc_armorkit_02" },
    { id: "thorium-spike", item: 12645, name: "Thorium Shield Spike", slot: "offhand", needs: "Shield", rf: { k: "block", s: "Physical", v: 25, lo: 20, hi: 30, sp: 16624, src: "client" }, stats: {}, skill: ["Blacksmithing", 250], icon: "inv_misc_armorkit_20" },
    { id: "retricutioner", item: 273591, name: "Retricutioner", slot: "chest", rf: { k: "hit", s: "Physical", v: 9, sp: 435901, src: "client" }, stats: {}, skill: ["Enchanting", null], icon: "inv_misc_enchantedscroll",
      note: "New in Forever: reflects damage when you are struck in melee." }
  ] };
  // Paladin and druid reflect numbers from the same client tables; reflect.json overrides them when present.
  var DEFAULT_REFLECT = { note: "Built-in fallback: plan/reflect.json is missing. Numbers from the beta client's SpellEffect table, build 1.60.1.70170.", classes: {
    PALADIN: { retAura: [[16, 7, 7294], [26, 12, 10298], [36, 18, 10299], [46, 24, 10300], [56, 30, 10301]], retCoef: 0,
      holyShield: { talent: "Holy Shield", ranks: [[40, 110, 20925], [50, 153, 20927], [60, 221, 20928]], coef: 0.08, charges: 4, dur: 10, cd: 10, block: 30 },
      redoubt: { talent: "Redoubt" }, eyeForAnEye: { talent: "Eye for an Eye", pct: [5, 10] } } },
    buffs: { thorns: { name: "Thorns (druid)", ranks: [[6, 4, 467], [14, 9, 782], [24, 11, 1075], [34, 13, 8914], [44, 16, 9756], [54, 22, 9910]], s: "Nature" } } };
  // Classic levelling zones by band, for BoE world drops whose source nobody has seen yet.
  var ZONEBAND = [[1, 10, "Elwynn Forest, Dun Morogh, Teldrassil, Durotar, Mulgore, Tirisfal Glades"], [10, 20, "Westfall, Loch Modan, Darkshore, The Barrens, Silverpine Forest"],
    [20, 30, "Redridge Mountains, Duskwood, Wetlands, Ashenvale, Stonetalon Mountains, Hillsbrad Foothills"], [30, 40, "Stranglethorn Vale, Arathi Highlands, Desolace, Thousand Needles, Dustwallow Marsh"],
    [40, 50, "Tanaris, Feralas, The Hinterlands, Badlands, Searing Gorge, Swamp of Sorrows"], [50, 61, "Un'Goro Crater, Felwood, Winterspring, Burning Steppes, the Plaguelands, Silithus"]];
  var EXTRA = { enchants: DEFAULT_ENCHANTS.enchants, enchantNote: DEFAULT_ENCHANTS.note, reflect: DEFAULT_REFLECT, dungeons: [] };

  var C_REQ = typeof WeakMap === "function" ? new WeakMap() : null, C_ST = C_REQ ? new WeakMap() : null, C_RF = C_REQ ? new WeakMap() : null;
  function cached(map, it, fn) {
    if (!map || !it || typeof it !== "object") return fn(it);
    var v = map.get(it);
    if (v === undefined) { v = fn(it); map.set(it, v); }
    return v;
  }
  // Required level, or an estimate from the item level (Classic: required = item level - 5) when the client stores none.
  function effReq(it) {
    return cached(C_REQ, it, function (x) {
      var r = +(x && x.reqLevel) || 0, il = +(x && x.itemLevel) || 0;
      if (r > 1 || (r === 1 && il < 20)) return { lvl: r, est: false };
      if (!il) return { lvl: r || 1, est: false };
      return { lvl: Math.max(1, Math.min(60, il - 5)), est: true };
    });
  }
  function isEquipLine(e) { return !/^(Use|Chance on hit):/i.test(e); }
  // Item stats plus what only the tooltip text states (spell penetration, block value, block rating).
  function istats(it) {
    return cached(C_ST, it, function (x) {
      var s = {}, src = (x && x.stats) || {}, m;
      Object.keys(src).forEach(function (k) { s[k] = src[k]; });
      (x && x.effects || []).forEach(function (e) {
        if (!isEquipLine(e)) return;
        if (!s.spellPiercing && ((m = /pierce (\d+) Magical Resistances/i.exec(e)) || (m = /\+(\d+) Spell Penetration/i.exec(e)))) s.spellPiercing = +m[1];
        if (!s.blockValue && ((m = /\+(\d+) Block Value/i.exec(e)) || (m = /Increases your shield block by (\d+)/i.exec(e)) || (m = /block value of your shield by (\d+)\b(?!%)/i.exec(e)))) s.blockValue = +m[1];
        // 5 block rating = 1% block in the client's rating table (Vigilant Buckler: 5 rating, 1.0%).
        if (!s.blockChance && (m = /\+(\d+) Block Rating/i.exec(e))) { s.blockRating = +m[1]; s.blockChance = +m[1] / 5; }
      });
      return s;
    });
  }
  function mainStat(it) {
    var s = istats(it), best = "", v = 0;
    ["strength", "agility", "intellect"].forEach(function (k) { if ((s[k] || 0) > v) { v = s[k]; best = k; } });
    return best;
  }
  function armorType(it) {
    if (!it || it.slot === "back") return "";   // cloaks: every class wears them
    if (ARMOR_TYPES.indexOf(it.type) !== -1) return it.type;
    return ARMOR_TYPES.indexOf(it.sub) !== -1 && it.cat === "armor" ? it.sub : "";
  }
  function cap1(w) { w = String(w || ""); var c = w.charAt(0).toUpperCase() + w.slice(1).toLowerCase(); return SCHOOLS.indexOf(c) !== -1 ? c : "Physical"; }
  // Reflect and thorns effects: rf from the data when it is there, else read from the tooltip text.
  function reflect(it) {
    if (!it) return [];
    if (Array.isArray(it.rf)) return it.rf;
    return cached(C_RF, it, function (x) {
      var out = [], m;
      (x.effects || []).forEach(function (e) {
        if ((m = /When struck in combat,? inflicts (\d+) (\w+) damage to the attacker/i.exec(e))) out.push({ k: "hit", s: cap1(m[2]), v: +m[1], src: "text" });
        else if ((m = /When struck in combat has a (\d+(?:\.\d+)?)% chance of inflicting (\d+) to (\d+) (\w+) damage to the attacker/i.exec(e))) out.push({ k: "proc", s: cap1(m[4]), p: +m[1] / 100, lo: +m[2], hi: +m[3], v: (+m[2] + +m[3]) / 2, src: "text" });
        else if ((m = /Deals (\d+) to (\d+) (\w+) damage every time you block/i.exec(e))) out.push({ k: "block", s: cap1(m[3]), lo: +m[1], hi: +m[2], v: (+m[1] + +m[2]) / 2, src: "text" });
        else if ((m = /Deals (\d+) (\w+) damage every time you block/i.exec(e))) out.push({ k: "block", s: cap1(m[2]), v: +m[1], src: "text" });
        else if ((m = /reflect (\d+) damage back to the attacker when the bearer is struck/i.exec(e))) out.push({ k: "hit", s: "Physical", v: +m[1], src: "text" });
        else if ((m = /^Use:.*deals (\d+) (\w+) damage to anyone who strikes you with a melee attack for (\d+) (min|sec)\.\s*\((\d+) (Min|Sec) Cooldown\)/i.exec(e))) {
          var dur = +m[3] * (/min/i.test(m[4]) ? 60 : 1), cd = +m[5] * (/min/i.test(m[6]) ? 60 : 1);
          out.push({ k: "use", s: cap1(m[2]), v: +m[1], up: Math.min(1, dur / cd), src: "text" });
        }
        else if ((m = /Deals (\d+) (\w+) damage to anyone who strikes you with a melee attack/i.exec(e))) out.push({ k: "hit", s: cap1(m[2]), v: +m[1], src: "text" });
        else if ((m = /Spikes sprout from you causing (\d+) (\w+) damage to attackers when hit\. Lasts (\d+) sec\.\s*\((\d+) Min Cooldown\)/i.exec(e))) out.push({ k: "use", s: cap1(m[2]), v: +m[1], up: Math.min(1, +m[3] / (+m[4] * 60)), src: "text" });
        else if ((m = /chance of raising a thorny shield that inflicts (\d+) (\w+) damage to attackers when hit/i.exec(e))) out.push({ k: "use", s: cap1(m[2]), v: +m[1], up: null, src: "text", note: "chance-based shield, uptime unknown" });
        else if (/When the shield blocks, it releases an electrical charge that damages all nearby enemies/i.test(e)) out.push({ k: "block", s: "Nature", v: null, aoe: true, src: "text", note: "amount not in the tooltip" });
        else if (/Attaches an? \w+ Spike to your shield/i.test(e)) {
          var en = EXTRA.enchants.filter(function (q) { return String(q.item) === String(x.id) && q.rf; })[0];
          if (en) [].concat(en.rf).forEach(function (f) { var r = {}; Object.keys(f).forEach(function (k) { r[k] = f[k]; }); out.push(r); });
        }
      });
      return out;
    });
  }
  // What one effect adds per hit taken and per block, as an expected value.
  function rfPerHit(e) {
    if (!e || e.v == null) return 0;
    if (e.k === "hit") return e.v * (e.p != null ? e.p : 1);
    if (e.k === "proc") return e.v * (e.p != null ? e.p : 1);
    if (e.k === "use") return typeof e.up === "number" ? e.v * e.up : 0;
    return 0;
  }
  function rfPerBlock(e) { return e && e.k === "block" && e.v != null ? e.v * (e.p != null ? e.p : 1) : 0; }
  function rfHit(it) { return reflect(it).reduce(function (a, e) { return a + rfPerHit(e); }, 0); }
  function rfBlock(it) { return reflect(it).reduce(function (a, e) { return a + rfPerBlock(e); }, 0); }
  // Spikes, thorns and block reflect are one thing to a player: damage back per enemy swing. Damage on block counts
  // at the block chance: the character's in The Forge (set by the stats panel), 10% where there is no character.
  var RF_BLOCK = { p: 0.10, mine: false };
  function rfAll(it) { return rfHit(it) + rfBlock(it) * RF_BLOCK.p; }
  function blockValue(it) { return istats(it).blockValue || 0; }
  // ---- Procs and on-use effects: fx from the data when it is there, else read from the tooltip text ----
  // fx rows: { k: hit|use|equip, what: damage|dot|heal|buff|debuff|summon|mana|other, s, v, lo, hi, ticks, dur, p, ppm, cd, icd, aoe, stat, sp, src, t }
  var C_FX = C_REQ ? new WeakMap() : null;
  var HANDS = { "main-hand": 1, "off-hand": 1, "one-hand": 1, "two-hand": 1, ranged: 1, thrown: 1 }, RANGED = { ranged: 1, thrown: 1 };
  function secs(n, unit) { return +n * (/^h/i.test(unit) ? 3600 : /^m(?!s)/i.test(unit) ? 60 : /^ms/i.test(unit) ? 0.001 : 1); }
  function schoolOf(w) {
    w = String(w || "").toLowerCase();
    for (var i = 0; i < SCHOOLS.length; i++) if (w.indexOf(SCHOOLS[i].toLowerCase()) === 0) return SCHOOLS[i];
    return "";
  }
  function avgOf(lo, hi) { return hi != null && hi !== "" ? Math.round((+lo + +hi) / 2 * 100) / 100 : +lo; }
  var FXSTAT = { strength: "strength", agility: "agility", stamina: "stamina", intellect: "intellect", spirit: "spirit", "attack power": "attackPower",
    armor: "armor", defense: "defense" };
  // One tooltip line ("Chance on hit: ...", "Use: ...", a proc-like "Equip: ...") into fx rows.
  function parseFxLine(line, k) {
    var body = String(line).replace(/^(Chance on hit|Use|Equip):\s*/i, ""), out = [], m;
    var cd = null, icd = null, p = null;
    if ((m = /\((\d+) Min(?:, (\d+) Sec)? Cooldown\)/i.exec(body))) cd = +m[1] * 60 + (+m[2] || 0);
    else if ((m = /\((\d+) Sec Cooldown\)/i.exec(body))) cd = +m[1];
    else if ((m = /\((\d+) (?:Hr|Hour)s? Cooldown\)/i.exec(body))) cd = +m[1] * 3600;
    if ((m = /(\d+(?:\.\d+)?)\s*(ms|s|m)\s+cooldown/i.exec(body))) icd = secs(m[1], m[2]);
    else if ((m = /(?:more than )?once every (\d+) sec/i.exec(body))) icd = +m[1];
    if ((m = /Proc chance: (\d+(?:\.\d+)?)%/i.exec(body)) || (m = /(\d+(?:\.\d+)?)% chance/i.exec(body))) p = +m[1] / 100;
    if (k === "use" && icd != null && cd == null) { cd = icd; icd = null; }
    var txt = body.replace(/\([^)]*(?:Cooldown|Proc chance)[^)]*\)/gi, " ").replace(/(\d+) ([A-Za-z]+) and (\d+) ([A-Za-z]+) damage/g, "$1 $2 damage and $3 $4 damage");
    var aoe = /all (?:nearby )?enemies|nearby enemies|all targets|up to \d+ targets|in front of|cone|radius|jump|additional nearby|Affects \d+ targets|around you/i.test(txt);
    function durIn(s) { var d = /(?:for|Lasts(?: for)?) (\d+(?:\.\d+)?) (sec|min|hour)/i.exec(s); return d ? secs(d[1], d[2]) : null; }
    function push(o) {
      o.k = k; o.src = "text"; o.t = line;
      if (p != null && o.p == null) o.p = p;
      if (cd != null) o.cd = cd;
      if (icd != null) o.icd = icd;
      if (aoe && (o.what === "damage" || o.what === "dot")) o.aoe = true;
      out.push(o);
    }
    var rest = txt, lastS = "", pre = /\d+(?: to \d+)? ([A-Za-z]+) damage/gi, pm;
    while ((pm = pre.exec(txt))) if (schoolOf(pm[1])) { lastS = schoolOf(pm[1]); break; }
    // Heals and mana first, so "Heals wielder of 60 damage over 6 sec" is not read as damage.
    if ((m = /\bHeal(?:s)?(?: yourself| the wielder| wielder| you| your target| friendly target| your pet)? (?:of|for) (\d+)(?: to (\d+))?(?![\d%]| sec| min)(?: damage)?(?: over (\d+) (sec|min))?/i.exec(rest))) {
      push({ what: "heal", v: avgOf(m[1], m[2]), lo: m[2] ? +m[1] : undefined, hi: m[2] ? +m[2] : undefined, dur: m[3] ? secs(m[3], m[4]) : undefined });
      rest = rest.replace(m[0], " ");
    } else if ((m = /Restores? (\d+)(?: to (\d+))? health(?: every (\d+) sec for (\d+) sec)?/i.exec(rest))) {
      var hticks = m[3] ? Math.floor(+m[4] / +m[3]) : 1;
      push({ what: "heal", v: avgOf(m[1], m[2]) * hticks, lo: m[2] ? +m[1] * hticks : undefined, hi: m[2] ? +m[2] * hticks : undefined, ticks: m[3] ? hticks : undefined, dur: m[3] ? +m[4] : undefined });
      rest = rest.replace(m[0], " ");
    }
    if ((m = /(?:Restores?|energize you for|gain) (\d+)(?: to (\d+))? mana(?: (?:every|per) (\d+) sec for (\d+) sec)?/i.exec(rest))) {
      var mt = m[3] ? Math.floor(+m[4] / +m[3]) : 1;
      push({ what: "mana", v: avgOf(m[1], m[2]) * mt, lo: m[2] ? +m[1] * mt : undefined, hi: m[2] ? +m[2] * mt : undefined, dur: m[3] ? +m[4] : undefined });
      rest = rest.replace(m[0], " ");
    }
    // Direct damage, skipping absorbs, damage buffs and damage over time.
    var re = /(\d+)(?: to (\d+))? (?:total )?(?:([A-Za-z]+) )?damage(?! over| every| taken| done| caused| is reduced)/gi, dm;
    while ((dm = re.exec(rest))) {
      var before = rest.slice(Math.max(0, dm.index - 40), dm.index);
      if (/absorb\w*(?: up to)?\s*$|protects? you from the next\s*$|up to\s*$|damage by\s*$|reduc\w* [a-z ]*by\s*$|plus\s*$|but deals\s*$|next\s*$/i.test(before)) continue;
      if (/^ or /i.test(rest.slice(dm.index + dm[0].length))) continue;
      if (dm[3] && !schoolOf(dm[3]) && !/^(additional|extra|bonus|more|total)$/i.test(dm[3])) continue;
      var s0 = schoolOf(dm[3]);
      push({ what: "damage", s: s0 || (dm[3] ? lastS : "") || undefined, v: avgOf(dm[1], dm[2]), lo: dm[2] ? +dm[1] : undefined, hi: dm[2] ? +dm[2] : undefined });
    }
    if ((m = /Steals (\d+)(?: to (\d+))? life(?! [^.]*over)/i.exec(rest)) || (m = /stealing (\d+)(?: to (\d+))? life(?! [^.]*over)/i.exec(rest))) push({ what: "damage", s: "Shadow", v: avgOf(m[1], m[2]), lo: m[2] ? +m[1] : undefined, hi: m[2] ? +m[2] : undefined });
    // Damage over time with a tick: "5 Nature damage every 3 sec for 15 sec", "10 health every 5 seconds ... for 25 sec"
    var tre = /(\d+)(?: to (\d+))? (?:([A-Za-z]+) )?(damage|health) every (\d+(?:\.\d+)?) sec(?:onds)?/gi, tm;
    while ((tm = tre.exec(rest))) {
      if (tm[4] === "health" && /Restores?\s*$|regain\w*\s*$/i.test(rest.slice(0, tm.index))) continue;
      if (tm[3] && !schoolOf(tm[3]) && !/^(additional|extra|bonus|more)$/i.test(tm[3])) continue;
      var dur = durIn(rest.slice(tm.index + tm[0].length)) || durIn(txt);
      if (!dur) continue;
      var ticks = Math.max(1, Math.floor(dur / +tm[5] + 1e-9)), per = avgOf(tm[1], tm[2]);
      push({ what: "dot", s: schoolOf(tm[3]) || (tm[4] === "health" ? "Shadow" : lastS) || undefined, v: Math.round(per * ticks * 100) / 100,
        lo: tm[2] ? +tm[1] * ticks : undefined, hi: tm[2] ? +tm[2] * ticks : undefined, ticks: ticks, dur: dur });
    }
    // Damage over time as a total: "bleed for 120 damage over 30 sec", "an additional 18 damage over 6 sec", "steal 30 life ... over 30 sec"
    var ore = /(\d+)(?: to (\d+))? (?:([A-Za-z]+) )?(?:damage|life(?: from [a-z ]+?)?) over (\d+) (sec|min)/gi, om;
    while ((om = ore.exec(rest))) {
      if (/Heals?\b[^.]*$/i.test(rest.slice(Math.max(0, om.index - 30), om.index))) continue;
      push({ what: "dot", s: schoolOf(om[3]) || (/life/i.test(om[0]) ? "Shadow" : lastS) || undefined, v: avgOf(om[1], om[2]), lo: om[2] ? +om[1] : undefined, hi: om[2] ? +om[2] : undefined, dur: secs(om[4], om[5]) });
    }
    var dmgN = out.filter(function (e) { return e.what === "damage" || e.what === "dot"; }).length;
    // Buffs on you: map to Forge stat keys where the text names one.
    var st = {}, bm;
    var reStat = /(?:Increases?|increase|increasing|raise) (?:your |all party member's )?(?:melee and ranged )?(Strength|Agility|Stamina|Intellect|Spirit|attack power|armor|Defense) by (\d+)/gi;
    var stDur = null;
    while ((bm = reStat.exec(txt))) if (!/target|enemy/i.test(txt.slice(Math.max(0, bm.index - 25), bm.index))) { st[FXSTAT[bm[1].toLowerCase()]] = +bm[2]; if (stDur == null) stDur = durIn(txt.slice(bm.index)); }
    if ((bm = /Defense \+(\d+)/i.exec(txt))) st.defense = +bm[1];
    if ((bm = /grants? (?:the wielder |you )?(\d+) defense and (\d+) armor/i.exec(txt))) { st.defense = +bm[1]; st.armor = +bm[2]; }
    else if ((bm = /grant you (\d+) armor/i.exec(txt))) st.armor = +bm[1];
    if ((bm = /chance to Parry attacks by (\d+)%/i.exec(txt))) st.parry = +bm[1];
    if ((bm = /chance to block by (\d+)%/i.exec(txt)) || (bm = /Increases your Block chance by (\d+)%/i.exec(txt))) st.blockChance = +bm[1];
    if ((bm = /Increases your chance to Dodge by (\d+)%/i.exec(txt))) st.dodge = +bm[1];
    if ((bm = /Increases healing done by (?:[a-z ]+ )?up to (\d+)/i.exec(txt)) || (bm = /your healing by up to (\d+)/i.exec(txt))) st.healing = +bm[1];
    if ((bm = /Increases (?:your spell damage|damage done by magical spells and effects) by up to (\d+)/i.exec(txt))) st.spellDamage = +bm[1];
    if ((bm = /damage and healing done by magical spells and effects by up to (\d+)/i.exec(txt)) || (bm = /increase the damage of your spells and effects by (\d+)/i.exec(txt))) st.spellPower = +bm[1];
    if ((bm = /increasing all stats by (\d+)/i.exec(txt)) && !/target|enem/i.test(txt)) ["strength", "agility", "stamina", "intellect", "spirit"].forEach(function (x) { st[x] = +bm[1]; });
    if ((bm = /^(?:Increases|increase) (?:your )?Attack Power by (\d+)/i.exec(txt)) || (bm = /Increases attack power by (\d+)/i.exec(txt))) st.attackPower = +bm[1];
    var dur0 = durIn(txt);
    if (Object.keys(st).length) push({ what: "buff", stat: st, dur: stDur || dur0 || undefined });
    else if (!dmgN && !out.length && /extra attack|attack speed|Increases (?:your )?damage|increasing his damage|run speed|absorb|shield|invulnerable|cast instantly|critical strikes|guaranteed|Immun|Reflects|resistances? by|mana cost|threat/i.test(txt) &&
      !/target|enem|attacker|foe/i.test(txt)) push({ what: "buff", dur: dur0 || undefined });
    if (!out.length) {
      if (/Summons|Calls forth|Creates a (?:Battle|mobile)|Activates your|to fight for you|to protect you|servants/i.test(txt)) push({ what: "summon", dur: dur0 || undefined });
      else if (/target|enem|attacker|foe/i.test(txt) && /lower|reduc|decreas|slow|stun|disarm|silence|knock|cripple|armor|interrupt|disorient|curse|taken|time between|sleep|net|Dispels a magic/i.test(txt)) push({ what: "debuff", dur: dur0 || undefined });
      else push({ what: "other", dur: dur0 || undefined });
    }
    return out;
  }
  // Equip lines that are procs (not stat lines, not reflect: reflect stays in rf).
  var EQ_HIT = /^Equip: (?:Chance on hit\b|Chance to (?:strike|bathe|decapitate|discharge)|Grants a chance on striking|\d+(?:\.\d+)?% chance (?:of dealing [^.]* on a successful melee attack|on melee hit))/i;
  var EQ_PROC = /^Equip: (?:When struck|When damaged|Has a \d+% chance when struck|\d+(?:\.\d+)?% chance (?:when|on successful spellcast)|Harmful spell casts|Chance on harmful spell|Gives a chance when your harmful spells|Chance on landing a damaging spell|Your \w+ spells have a \d+% chance to restore|Causes \w+ to have a \d+% chance)/i;
  function procs(it) {
    if (!it || ALLSLOTS.indexOf(it.slot) === -1) return [];
    if (Array.isArray(it.fx)) return it.fx;
    return cached(C_FX, it, function (x) {
      var out = [];
      (x.effects || []).forEach(function (e) {
        var k = /^Chance on hit:/i.test(e) ? "hit" : /^Use:/i.test(e) ? "use" : EQ_HIT.test(e) ? "hit" : EQ_PROC.test(e) ? "equip" : "";
        if (!k) return;
        if (reflect({ effects: [e] }).length) return;   // reflect and thorns stay in rf
        if (x.rf && x.rf.length && /when struck/i.test(e)) return; // the client's reflect rows already cover "when struck" lines
        out = out.concat(parseFxLine(e, k));
      });
      return out;
    });
  }
  // Procs that belong together (one spell, one tooltip line) group into one event.
  function fxGroups(list) {
    var g = [], by = {};
    (list || []).forEach(function (e, i) {
      var key = e.k + "|" + (e.sp || e.t || i);
      if (!by[key]) { by[key] = { k: e.k, rows: [], t: e.t, sp: e.sp }; g.push(by[key]); }
      by[key].rows.push(e);
    });
    g.forEach(function (x) {
      function first(f) { for (var i = 0; i < x.rows.length; i++) if (x.rows[i][f] != null) return x.rows[i][f]; return null; }
      x.p = first("p"); x.ppm = first("ppm"); x.cd = first("cd"); x.icd = first("icd"); x.src = first("src"); x.only = first("only");
      x.dmg = x.rows.reduce(function (a, e) { return a + ((e.what === "damage" || e.what === "dot") && e.v ? +e.v : 0); }, 0);
    });
    return g;
  }
  function hasFx(it, k) { return k === "rf" ? reflect(it).length > 0 : procs(it).some(function (e) { return e.k === k; }); }
  var FXPILLS = [["hit", "Chance on hit", "A chance to fire on a landed melee or ranged hit: damage, a buff or a debuff."],
    ["use", "Use", "Click to use: trinkets, engineering gear, items with a cooldown."],
    ["equip", "Equip proc", "Other equip procs: on spell cast, on being hit (not reflect), and similar."],
    ["rf", "Reflect", "Items that hurt whoever hits you: thorns, damage on block, shield spikes."]];
  function weaponSpeed(it) { return it && HANDS[it.slot] && +it.speed > 0 ? +it.speed : 0; }
  // Chance per swing: the client's chance, else procs per minute x speed / 60; null when neither is known.
  function procChance(g, speed) {
    if (g.p != null) return Math.min(1, +g.p);
    if (g.ppm) return Math.min(1, g.ppm * speed / 60);
    return null;
  }
  // Expected damage per second from chance-on-hit damage: a weapon's procs at its own speed, anything else at `speed` (main hand, else 2.0 s).
  function procDps(it, speed) {
    var own = weaponSpeed(it), spd = own || +speed || 2.0;
    return fxGroups(procs(it)).reduce(function (a, g) {
      if (g.k !== "hit" || !g.dmg || g.only) return a;   // target-type procs ("only against Swine") are not general damage
      var c = procChance(g, spd); if (c == null) return a;
      var d = c * g.dmg / spd;
      if (g.icd) d = Math.min(d, g.dmg / g.icd);
      return a + d;
    }, 0);
  }
  function procDmg(it) { return fxGroups(procs(it)).reduce(function (a, g) { return g.k !== "use" && g.dmg > a ? g.dmg : a; }, 0); }
  // Average damage of the strongest on-use effect (direct plus its damage over time).
  function useAvg(it) { return fxGroups(procs(it)).reduce(function (a, g) { return g.k === "use" && g.dmg > a ? g.dmg : a; }, 0); }
  function fmtDur(s) { s = +s; return s >= 3600 && s % 3600 === 0 ? s / 3600 + " hr" : s >= 60 && s % 60 === 0 ? s / 60 + " min" : s >= 60 ? Math.floor(s / 60) + " min " + Math.round(s % 60) + " sec" : r2(s) + " sec"; }
  function fxAmt(e) { return e.v == null ? "" : e.lo != null && e.hi != null && e.lo !== e.hi ? e.lo + "–" + e.hi : String(Math.round(e.v * 10) / 10); }
  var FXLBL = { strength: "Str", agility: "Agi", stamina: "Sta", intellect: "Int", spirit: "Spi", attackPower: "AP", armor: "Armor", defense: "Defense", parry: "% Parry", dodge: "% Dodge",
    blockChance: "% Block", spellPower: "Spell power", spellDamage: "Spell dmg", healing: "Healing" };
  // A short phrase for one row: "30 Holy", "120 Physical over 30 sec", "300–700 heal", "+100 Str for 10 sec".
  function fxWhat(e) {
    var a = fxAmt(e);
    switch (e.what) {
      case "damage": return a + (e.s ? " " + e.s : " damage") + (e.aoe ? " (area)" : "");
      case "dot": return a + (e.s ? " " + e.s : " damage") + (e.dur ? " over " + fmtDur(e.dur) : " over time") + (e.aoe ? " (area)" : "");
      case "heal": return a + " heal" + (e.dur ? " over " + fmtDur(e.dur) : "");
      case "mana": return a + " mana" + (e.dur ? " over " + fmtDur(e.dur) : "");
      case "buff": return (e.stat && Object.keys(e.stat).length ? Object.keys(e.stat).map(function (s) { var l = FXLBL[s] || (STATBY[s] ? STATBY[s][2] : s); return "+" + e.stat[s] + (l.charAt(0) === "%" ? l : " " + l); }).join(", ") : "buff") + (e.dur ? " for " + fmtDur(e.dur) : "");
      case "debuff": return "debuff" + (e.dur ? " " + fmtDur(e.dur) : "");
      case "summon": return "summon";
      default: return "effect";
    }
  }
  function grpWhat(g) {
    var main = g.rows.filter(function (e) { return e.what === "damage" || e.what === "dot" || e.what === "heal" || e.what === "mana" || e.what === "buff"; });
    return (main.length ? main : g.rows.slice(0, 1)).map(fxWhat).join(" + ") + (g.only ? " (only against " + g.only + ")" : "");
  }
  function chanceTxt(g, speed) {
    if (g.p != null) return Math.round(g.p * 1000) / 10 + "%";
    if (g.ppm) return speed ? Math.round(procChance(g, speed) * 1000) / 10 + "%" : g.ppm + " PPM";
    return "chance unknown";
  }
  // Chips: "Proc 30 Holy (4%)", "Use 300–700 heal, 30 min", "Equip proc 2%: ...".
  function paren(t, x) { return /\)$/.test(t) ? t.replace(/\)$/, ", " + x + ")") : t + " (" + x + ")"; } // "(area, 2%)", not "(area) (2%)"
  function fxChips(it) { // strongest effect first, so a one-chip list shows the one that matters
    var spd = weaponSpeed(it);
    return fxGroups(procs(it)).map(function (g, i) { return { g: g, i: i }; })
      .sort(function (a, b) { return ((b.g.dmg || 0) - (a.g.dmg || 0)) || a.i - b.i; }).map(function (x) {
        var g = x.g, key = g.k === "use" ? "useDmg" : g.k === "hit" && g.dmg ? "procDps" : "procDmg";
        if (g.k === "use") return [key, "Use " + grpWhat(g) + (g.cd ? ", " + fmtDur(g.cd) : "")];
        if (g.k === "hit") return [key, paren("Proc " + grpWhat(g), chanceTxt(g, spd))];
        return [key, g.p != null || g.ppm ? paren("Equip proc " + grpWhat(g), chanceTxt(g, spd)) : "Equip proc " + grpWhat(g)];
      });
  }
  function hasSource(it) { return !!((it.drops && it.drops.length) || (it.quests && it.quests.length)); }
  // Where an item probably comes from when no drop or quest has been seen: always labelled as an estimate.
  function estimateSource(it, dungeons) {
    if (!it || hasSource(it)) return null;
    var er = effReq(it), lo = er.lvl, il = +it.itemLevel || lo, hi = Math.min(60, Math.max(il, lo + 5));
    var q = it.quality, b = it.binding, kind, where = [];
    var PVP = /^(Premier )?(Grand Marshal|High Warlord|Field Marshal|Warlord|Marshal|General|Lieutenant General|Lieutenant Commander|Knight-Captain|Knight-Lieutenant|Legionnaire|Blood Guard|Stone Guard|Centurion|Sergeant Major|Master Sergeant|First Sergeant)'s /;
    if (it.cat === "pvp" || PVP.test(it.name || "") || (it.effects || []).some(function (e) { return /\(Rank \d+\)/.test(e); })) kind = "likely a PvP rank reward from an honor vendor";
    else if (it.reagents) kind = "crafted";
    else if (it.setName && b === "BoP") kind = "likely a dungeon set piece";
    else if (b === "BoP" && (q === "rare" || q === "epic" || q === "legendary")) kind = "likely a dungeon boss drop";
    else if (b === "BoP") kind = "likely a quest reward or dungeon drop";
    else if (b === "BoE" && (q === "uncommon" || q === "rare" || q === "epic")) kind = "likely a world drop (binds when equipped)";
    else if (q === "poor" || q === "common") kind = "likely a vendor item or common world drop";
    else kind = "source unknown";
    var mid = (lo + hi) / 2, dg = dungeons || EXTRA.dungeons || [];
    if (/dungeon|quest reward/.test(kind) && dg.length) {
      where = dg.filter(function (d) { return d.levels && d.levels.length === 2; }).map(function (d) {
        return { n: d.name, d: Math.abs((d.levels[0] + d.levels[1]) / 2 - mid) };
      }).sort(function (a, b2) { return a.d - b2.d; }).slice(0, 4).map(function (x) { return x.n; });
    } else if (/world drop/.test(kind)) {
      var z = ZONEBAND.filter(function (zb) { return lo >= zb[0] && lo < zb[1]; })[0];
      if (z) where = [z[2] + " (Classic zone band)"];
    }
    return "Estimate: level " + (lo === hi ? lo : lo + "–" + hi) + " content, " + kind + (where.length ? ": " + where.join(", ") : "") + "." +
      (er.est ? " Required level estimated from item level " + il + "." : "");
  }
  function isJunk(it) {
    var n = String(it && it.name || "");
    if (/High Test/i.test(n)) return false;
    return /^OLD|Monster - |\bDNT\b|^QA|\bPH\b|\bTest\b/.test(n);
  }
  // Classic proficiencies as the default lens; the picker's "Any class" lifts it.
  var ARMOR_RANK = { Cloth: 1, Leather: 2, Mail: 3, Plate: 4 };
  var ARMOR_MAX = { WARRIOR: 4, PALADIN: 4, HUNTER: 3, SHAMAN: 3, DRUID: 2, ROGUE: 2, MAGE: 1, WARLOCK: 1, PRIEST: 1 };
  var WEAP = {
    WARRIOR: { t: ["Sword", "Axe", "Mace", "Dagger", "Staff", "Polearm", "Fist Weapon", "Bow", "Gun", "Crossbow", "Thrown", "Shield"], two: true },
    PALADIN: { t: ["Sword", "Mace", "Axe", "Polearm", "Shield", "Libram"], two: true },
    HUNTER: { t: ["Sword", "Axe", "Dagger", "Staff", "Polearm", "Fist Weapon", "Bow", "Gun", "Crossbow", "Thrown"], two: true },
    ROGUE: { t: ["Sword", "Mace", "Dagger", "Fist Weapon", "Bow", "Gun", "Crossbow", "Thrown"], two: false },
    PRIEST: { t: ["Mace", "Dagger", "Staff", "Wand"], two: false },
    SHAMAN: { t: ["Axe", "Mace", "Dagger", "Staff", "Fist Weapon", "Shield", "Totem"], two: true },
    MAGE: { t: ["Sword", "Dagger", "Staff", "Wand"], two: false },
    WARLOCK: { t: ["Sword", "Dagger", "Staff", "Wand"], two: false },
    DRUID: { t: ["Mace", "Dagger", "Staff", "Fist Weapon", "Idol"], two: true }
  };
  function canUse(cls, it, lvl) {
    cls = String(cls || "").toUpperCase();
    if (!WEAP[cls]) return true;
    var t = it.type || "";
    if (!t || t === "Fishing Pole") return true;
    if (ARMOR_RANK[t]) {
      var m = ARMOR_MAX[cls] || 4;
      // Plate wearers hold mail below 40; mail wearers hold leather below 40 (Classic rule).
      if ((lvl || 60) < 40 && (m === 4 || m === 3)) m--;
      return ARMOR_RANK[t] <= m;
    }
    if (WEAP[cls].t.indexOf(t) === -1) return false;
    if (it.slot === "two-hand" && !WEAP[cls].two && t !== "Staff" && t !== "Polearm") return false;
    return true;
  }
  // Every stat the picker and the Database filter and sort by. Derived ones fold in what a player means:
  // healing counts spell power, Holy damage counts spell damage and spell power.
  var SCH = ["holy", "fire", "frost", "nature", "shadow", "arcane"];
  var STATS = [
    ["Attributes", [["strength", "Strength", "Str"], ["agility", "Agility", "Agi"], ["stamina", "Stamina", "Sta"], ["intellect", "Intellect", "Int"], ["spirit", "Spirit", "Spi"]]],
    ["Defense", [["armor", "Armor", "Armor"], ["defense", "Defense", "Defense"], ["dodge", "Dodge %", "Dodge"], ["parry", "Parry %", "Parry"], ["blockChance", "Block Chance %", "Block"],
      ["blockValue", "Block Value", "Block value"], ["reflect", "Reflect (per enemy swing)", "reflect"]]],
    ["Physical", [["attackPower", "Attack Power", "AP"], ["rangedAttackPower", "Ranged Attack Power", "RAP"], ["crit", "Crit %", "Crit"], ["hit", "Hit %", "Hit"],
      ["weaponSkill", "Weapon Skill", "skill"], ["dps", "Weapon DPS", "DPS"]]],
    ["Spell", [["spellPower", "Spell Power", "Spell power"], ["spellDamage", "Spell Damage", "Spell dmg"], ["healing", "Healing", "Healing"], ["holy", "Holy damage", "Holy dmg"],
      ["fire", "Fire damage", "Fire dmg"], ["frost", "Frost damage", "Frost dmg"], ["nature", "Nature damage", "Nature dmg"], ["shadow", "Shadow damage", "Shadow dmg"], ["arcane", "Arcane damage", "Arcane dmg"],
      ["spellPiercing", "Spell Penetration", "Spell pen."], ["mp5", "Mana per 5", "mp5"], ["hp5", "Health per 5", "hp5"]]],
    ["Resistances", [["fireResist", "Fire Resistance", "Fire res."], ["frostResist", "Frost Resistance", "Frost res."], ["natureResist", "Nature Resistance", "Nature res."],
      ["shadowResist", "Shadow Resistance", "Shadow res."], ["arcaneResist", "Arcane Resistance", "Arcane res."], ["allResist", "All Resistances", "All res."]]],
    ["Procs and on-use", [["procDps", "Proc damage per second (est.)", "proc DPS (est.)"], ["procDmg", "Proc damage per proc", "per proc"], ["useDmg", "On-use damage", "per use"]]]
  ];
  var STATBY = {};
  STATS.forEach(function (g) { g[1].forEach(function (x) { STATBY[x[0]] = x; }); });
  STATBY.reflectHit = STATBY.reflectBlock = STATBY.reflect; // older saved filters and links
  function statVal(it, k) {
    if (!it) return 0;
    var s = istats(it), n = function (x) { return +s[x] || 0; };
    switch (k) {
      case "armor": return (+it.armor || 0) + n("bonusArmor");
      case "spellDamage": return n("spellDamage") + n("spellPower");
      case "healing": return n("healing") + n("spellPower");
      case "holy": case "fire": case "frost": case "nature": case "shadow": case "arcane": return n(k + "SpellDamage") + n("spellDamage") + n("spellPower");
      case "weaponSkill": return Object.keys(s).reduce(function (a, x) { return /Skill$/.test(x) && x !== "fishing" ? a + n(x) : a; }, 0);
      case "dps": return +it.dps || 0;
      case "reflect": case "reflectHit": case "reflectBlock": return rfAll(it); // one reflect value
      case "procDps": return procDps(it);
      case "procDmg": return procDmg(it);
      case "useDmg": return useAvg(it);
      case "fireResist": case "frostResist": case "natureResist": case "shadowResist": case "arcaneResist":
        return n(k) + n("allResist") + (s.resist ? +s.resist[k.replace("Resist", "")] || 0 : 0);
      default: return n(k);
    }
  }
  function r2(v) { return Math.round(v * 100) / 100; }
  function sgn(v) { return (v < 0 ? "" : "+") + r2(v); }
  // Short chips for a list row: one per stat, a rating and its percent collapse into the percent.
  function chips(it, first) {
    var s = istats(it), out = [];
    function add(key, txt) { out.push([key, txt]); }
    ["strength", "agility", "stamina", "intellect", "spirit"].forEach(function (k) { if (s[k]) add(k, sgn(s[k]) + " " + STATBY[k][2]); });
    if (s.bonusArmor) add("armor", sgn(s.bonusArmor) + " Armor");
    if (s.attackPower) add("attackPower", sgn(s.attackPower) + " AP");
    if (s.rangedAttackPower) add("rangedAttackPower", sgn(s.rangedAttackPower) + " RAP");
    if (s.spellPower) add("spellPower", sgn(s.spellPower) + " Spell power");
    if (s.healing) add("healing", sgn(s.healing) + " Healing");
    if (s.spellDamage) add("spellDamage", sgn(s.spellDamage) + " Spell dmg");
    SCH.forEach(function (x) { if (s[x + "SpellDamage"]) add(x, sgn(s[x + "SpellDamage"]) + " " + cap1(x) + " dmg"); });
    if (s.crit || s.critRating) add("crit", s.crit ? sgn(s.crit) + "% Crit" : sgn(s.critRating) + " Crit rating");
    if (s.hit || s.hitRating) add("hit", s.hit ? sgn(s.hit) + "% Hit" : sgn(s.hitRating) + " Hit rating");
    if (s.defense || s.defenseRating) add("defense", sgn(s.defense || s.defenseRating) + " Defense");
    if (s.dodge || s.dodgeRating) add("dodge", s.dodge ? sgn(s.dodge) + "% Dodge" : sgn(s.dodgeRating) + " Dodge rating");
    if (s.parry || s.parryRating) add("parry", s.parry ? sgn(s.parry) + "% Parry" : sgn(s.parryRating) + " Parry rating");
    if (s.blockChance) add("blockChance", sgn(s.blockChance) + "% Block");
    if (s.blockValue) add("blockValue", sgn(s.blockValue) + " Block value");
    if (s.spellPiercing) add("spellPiercing", sgn(s.spellPiercing) + " Spell pen.");
    if (s.mp5) add("mp5", s.mp5 + " mp5");
    if (s.hp5) add("hp5", s.hp5 + " hp5");
    if (s.expertiseRating) add("expertise", sgn(s.expertiseRating) + " Expertise rating");
    if (s.hasteRating) add("haste", sgn(s.hasteRating) + " Haste rating");
    var wsk = statVal(it, "weaponSkill");
    if (wsk) add("weaponSkill", sgn(wsk) + " Weapon skill");
    ["fire", "frost", "nature", "shadow", "arcane"].forEach(function (x) { if (s[x + "Resist"]) add(x + "Resist", sgn(s[x + "Resist"]) + " " + cap1(x) + " res."); });
    if (s.allResist) add("allResist", sgn(s.allResist) + " All res.");
    reflect(it).forEach(function (e) {
      var amt = e.v == null ? "?" : e.lo != null && e.hi != null && e.lo !== e.hi ? e.lo + "–" + e.hi : r2(e.v);
      if (e.k === "hit") add("reflect", "Reflect " + amt + " " + e.s);
      else if (e.k === "proc") add("reflect", "Reflect " + Math.round((e.p || 0) * 1000) / 10 + "%: " + amt + " " + e.s);
      else if (e.k === "use") add("reflect", "Reflect " + amt + " " + e.s + " (use)");
      else if (e.k === "block") add("reflect", "Reflect " + amt + " " + e.s + " on block");
      else if (e.k === "crit") add("reflect", "Reflect " + amt + "% of crits");
    });
    fxChips(it).forEach(function (c) { add(c[0], c[1]); });
    if (first) {
      // The stat being sorted or filtered by leads, with what feeds it (spell power feeds healing and school damage).
      var feeds = function (k) {
        if (k === first) return true;
        if (first === "healing") return k === "spellPower";
        if (first === "spellDamage" || SCH.indexOf(first) !== -1) return k === "spellPower" || k === "spellDamage";
        if (/Resist$/.test(first)) return k === "allResist";
        if (first === "procDps" || first === "procDmg") return k === "procDps" || k === "procDmg";
        return false;
      };
      out = out.filter(function (a) { return feeds(a[0]); }).map(function (a) { return [a[0], a[1], 1]; }).concat(out.filter(function (a) { return !feeds(a[0]); }));
    }
    return out;
  }
  window.ForgeItem = { effReq: effReq, mainStat: mainStat, armorType: armorType, reflect: reflect, blockValue: blockValue, estimateSource: estimateSource,
    isJunk: isJunk, istats: istats, statVal: statVal, STATS: STATS, STATBY: STATBY, chips: chips, hasSource: hasSource, canUse: canUse, rfHit: rfHit, rfBlock: rfBlock,
    procs: procs, procDps: procDps, procDmg: procDmg, useAvg: useAvg, fxGroups: fxGroups, fxChips: fxChips, procChance: procChance, weaponSpeed: weaponSpeed,
    hasFx: hasFx, FXPILLS: FXPILLS,
    ARMOR_TYPES: ARMOR_TYPES, extras: function () { return EXTRA; } };

  window.ForgeGear = function (opts) {
    var allItems = (opts.items && Array.isArray(opts.items.items)) ? opts.items.items : [];
    var byId = {};
    allItems.forEach(function (it) { byId[it.id] = it; if (it.alias) byId[it.alias] = it; });
    // Old links name items by the slugs of the first curated list: they stay decodable, never offered in a picker.
    (opts.legacy || []).forEach(function (it) { if (it && it.id != null && !byId[it.id]) byId[it.id] = it; });
    // The Forge plans for Forever: rows the client marks as SoD-era or retail-era data, and dev junk, stay out of the pickers.
    var items = allItems.filter(function (it) { return !it.era && !isJunk(it); });
    var wearable = items.filter(function (it) { return ALLSLOTS.indexOf(it.slot) !== -1; }).length;

    function eq() { return opts.get() || {}; }
    function ench() { return (opts.ench ? opts.ench() : null) || {}; }
    function itemTip(it) {
      if (!it) return "";
      var s = it.stats || {}, L = [];
      L.push('<b class="q-' + esc(it.quality || "common") + '">' + esc(it.name) + "</b>");
      if (it.binding) L.push('<span class="it-l">' + (it.binding === "BoP" ? "Binds when picked up" : "Binds when equipped") + "</span>");
      if (it.unique) L.push('<span class="it-l">' + esc(it.unique === true ? "Unique" : it.unique) + "</span>");
      if ((it.slot && it.slot !== "unknown") || it.type) L.push('<span class="it-row"><i>' + esc(it.slot === "unknown" ? "" : slotLabel(it.slot)) + "</i><i>" + esc(it.type || "") + "</i></span>");
      if (it.damage) L.push('<span class="it-row"><i>' + esc(String(it.damage).replace("-", " - ")) + " Damage</i><i>" + (it.speed ? "Speed " + Number(it.speed).toFixed(2) : "") + "</i></span>");
      if (it.dmgExtra) L.push('<span class="it-l">' + esc(it.dmgExtra) + "</span>");
      if (it.dps) L.push('<span class="it-l">(' + esc(it.dps) + " damage per second)</span>");
      if (it.armor) L.push('<span class="it-l">' + esc(it.armor) + " Armor</span>");
      if (it.block) L.push('<span class="it-l">' + esc(it.block) + " Block</span>");
      Object.keys(STAT_LINE).forEach(function (k) { if (s[k]) L.push('<span class="it-l">+' + esc(s[k]) + " " + STAT_LINE[k] + "</span>"); });
      if (s.resist) Object.keys(s.resist).forEach(function (r) { L.push('<span class="it-l">+' + esc(s.resist[r]) + " " + esc(r.charAt(0).toUpperCase() + r.slice(1)) + " Resistance</span>"); });
      ["fire", "frost", "nature", "shadow", "arcane"].forEach(function (r) { if (s[r + "Resist"]) L.push('<span class="it-l">+' + esc(s[r + "Resist"]) + " " + r.charAt(0).toUpperCase() + r.slice(1) + " Resistance</span>"); });
      if (s.allResist) L.push('<span class="it-l">+' + esc(s.allResist) + " All Resistances</span>");
      if (s.bonusArmor) L.push('<span class="it-l">+' + esc(s.bonusArmor) + " Armor</span>");
      (it.effects || []).forEach(function (e) { L.push('<span class="it-g">' + esc(e) + "</span>"); });
      // The game client's own effect text, where the tooltip lacks it or says something else (Forever changed the spell).
      var said = (it.effects || []).map(normTxt), cx = [];
      (it.rf || []).concat(it.fx || []).forEach(function (e) { if (e && e.t && cx.indexOf(e.t) === -1 && said.indexOf(normTxt(e.t)) === -1) cx.push(e.t); });
      if (cx.length) {
        L.push('<span class="it-src">The Forever client data says:</span>');
        cx.forEach(function (t) { L.push('<span class="it-g">' + esc(/^(Use|Equip|Chance on hit):/.test(t) ? t : "Equip: " + t) + "</span>"); });
      }
      [["attackPower", "Equip: +%s Attack Power.", /attack power/i], ["spellPower", "Equip: Increases damage and healing done by magical spells and effects by up to %s.", /damage and healing/i],
        ["healing", "Equip: Increases healing done by up to %s.", /increases healing/i], ["spellDamage", "Equip: Increases damage done by magical spells and effects by up to %s.", /spell|magical/i],
        ["hit", "Equip: Improves your chance to hit by %s%.", /chance to hit/i], ["crit", "Equip: Improves your chance to get a critical strike by %s%.", /critical strike/i],
        ["expertise", "Equip: Reduces chance to be Dodged or Parried by %s%.", /dodged or parried|expertise/i], ["weaponDamage", "Equip: +%s Weapon Damage.", /weapon damage/i],
        ["mp5", "Equip: Restores %s mana per 5 sec.", /mana per 5/i], ["defense", "Equip: Increased Defense +%s.", /defense/i], ["spellPiercing", "Equip: Your spells pierce %s Magical Resistances.", /pierce|penetration/i],
        ["blockValue", "Equip: +%s Block Value.", /block value|shield block/i]]
        .forEach(function (x) {
          if (!s[x[0]] || it.tt === "forever") return;
          var num = new RegExp("(^|[^0-9.])" + String(s[x[0]]).replace(".", "\\.") + "([^0-9]|$)");
          var named = (it.effects || []).some(function (e) { return x[2].test(e) && num.test(e); });
          if (!named) L.push('<span class="it-g">' + esc(x[1].replace("%s", s[x[0]])) + "</span>");
        });
      if (it.setName) {
        var E = eq(), worn = {};
        SLOT_KEYS.forEach(function (k) { var w = byId[E[k]]; if (w) worn[w.name] = true; });
        var pieces = it.setPieces || [], have = pieces.filter(function (p) { return worn[p]; }).length;
        L.push('<span class="it-set">' + esc(it.setName) + (pieces.length ? " (" + have + "/" + pieces.length + ")" : "") + "</span>");
        pieces.forEach(function (p) { L.push('<span class="it-sp' + (worn[p] ? " on" : "") + '">' + esc(p) + "</span>"); });
        (it.setBonuses || []).forEach(function (b) { L.push('<span class="it-sb' + (have >= b[0] ? " on" : "") + '">(' + esc(b[0]) + ") Set: " + esc(b[1]) + "</span>"); });
      }
      var GEARCATS = { weapon: 1, armor: 1, accessory: 1, offhand: 1 };
      if (it.rand) L.push('<span class="it-g">&lt;Random enchantment&gt;</span>');
      else if (GEARCATS[it.cat] && !it.damage && (!it.effects || !it.effects.length) && !Object.keys(s).length &&
          { uncommon: 1, rare: 1, epic: 1, legendary: 1 }[it.quality]) {
        L.push('<span class="it-src">Not itemized yet: the piece exists in the client, its stat values do not. They land in a later build.</span>');
      }
      if (it.startsQuest) L.push('<span class="it-l">This Item Begins a Quest</span>');
      var er = effReq(it);
      if (it.reqLevel && !er.est) L.push('<span class="it-l">Requires Level ' + esc(it.reqLevel) + "</span>");
      else if (er.est && ALLSLOTS.indexOf(it.slot) !== -1) L.push('<span class="it-l it-est">Requires Level ' + er.lvl + " (estimate from item level)</span>");
      if (it.reqSkill) L.push('<span class="it-l">Requires ' + esc(String(it.reqSkill).replace(/ (\d+)$/, " ($1)")) + "</span>");
      if (it.flavor) L.push('<span class="it-f">"' + esc(it.flavor) + '"</span>');
      if (it.itemLevel) L.push('<span class="it-y">Item Level ' + esc(it.itemLevel) + "</span>");
      if (it.ft === "new" || it.ft === "changed") L.push('<span class="it-ft">' + (it.ft === "new" ? "New in Forever" : "Changed from Classic") + "</span>");
      if (it.est === "classic") L.push('<span class="it-conf it-est">' + ((it.drops || it.quests)
        ? "Estimate: a Forever loot record lists this item, but its Forever numbers have not been seen yet. These are its WoW Classic stats."
        : "Estimate: not seen in Forever yet. These are its WoW Classic stats; Forever may have changed or removed it.") + "</span>");
      (it.drops || []).forEach(function (d) { L.push('<span class="it-drop">Drops from ' + esc(d[1]) + (d[2] === "rare" ? " (rare)" : "") + ", " + esc(d[0]) + "</span>"); });
      (it.quests || []).forEach(function (q) { L.push('<span class="it-drop">Quest reward: ' + esc(q[0]) + " (" + esc(q[1]) + ")</span>"); });
      if (ALLSLOTS.indexOf(it.slot) !== -1) { var es = estimateSource(it); if (es) L.push('<span class="it-src it-est">' + esc(es) + "</span>"); }
      if (it.source && !(it.est === "classic" && /^Estimate: a WoW Classic item/.test(it.source))) L.push('<span class="it-src">' + esc(it.source) + "</span>"); // the est line above says it
      if (it.reagents) L.push('<span class="it-src">Reagents: ' + esc(it.reagents) + "</span>");
      if (it.iconFrom === "placeholder") L.push('<span class="it-conf">Stand-in icon until the real one is seen</span>');
      if (it.confidence) L.push('<span class="it-conf">' + (it.confidence === "tooltip" ? "Tooltip read from Forever footage" : it.confidence === "partial" ? "Partly seen: some lines never shown" : "Named by Blizzard or previews; no tooltip shown yet") + "</span>");
      return L.join("");
    }
    function normTxt(t) { return String(t || "").toLowerCase().replace(/^(equip|use|chance on hit):\s*/, "").replace(/[^a-z0-9%]+/g, ""); }
    function slotLabel(slot) {
      var m = { "main-hand": "Main Hand", "off-hand": "Off Hand", "one-hand": "One-Hand", "two-hand": "Two-Hand", finger: "Finger", trinket: "Trinket", ranged: "Ranged", relic: "Relic" };
      return m[slot] || (slot ? slot.charAt(0).toUpperCase() + slot.slice(1) : "");
    }
    // ---- Consumables: effects read from the verified Forever tooltip text ----
    function cons() { return (opts.cons ? opts.cons() : []) || []; }
    function consumeInfo(it) {
      if (!it || it.cat !== "consumable") return null;
      var txt = (it.effects || []).join(" "), st = [], m, kind = "utility", dur = "";
      function add(stat, v, when) { st.push([stat, +String(v).replace(/,/g, ""), when || ""]); }
      if ((m = /well fed and gain (\d+) (Strength|Agility|Stamina|Intellect|Spirit) for (\d+) min/i.exec(txt))) { kind = "food"; add(m[2].toLowerCase(), m[1]); dur = m[3] + " min"; }
      else if (/^Use: Drink to/i.test(txt)) {
        kind = "elixir"; dur = (/(\d+) min/.exec(txt) || [0, "30"])[1] + " min";
        if ((m = /gain (\d+) Agility and Intellect/i.exec(txt))) { add("agility", m[1]); add("intellect", m[1]); }
        if ((m = /increase your Strength and Agility by (\d+)/i.exec(txt))) { add("strength", m[1]); add("agility", m[1]); }
        if ((m = /increase your (Strength|Agility|Stamina|Intellect|Spirit) by (\d+)/i.exec(txt))) add(m[1].toLowerCase(), m[2]);
        if ((m = /chance to critically hit by (\d+)%/i.exec(txt))) add("crit", m[1]);
        if ((m = /maximum health by (\d+)/i.exec(txt)) || (m = /gain (\d+) maximum health/i.exec(txt))) add("health", m[1]);
        if ((m = /and (\d+) armor/i.exec(txt))) add("armor", m[1]);
        if ((m = /increase (nature|fire|frost|shadow|arcane|holy) spell damage by up to (\d+)/i.exec(txt))) add("spellDamage", m[2], m[1].charAt(0).toUpperCase() + m[1].slice(1) + " spells");
        else if ((m = /increase spell damage by up to (\d+)/i.exec(txt))) add("spellDamage", m[1]);
        if ((m = /healing done by spells and effects by up to (\d+)/i.exec(txt))) add("healing", m[1]);
        if ((m = /regenerate (\d+) mana every 5 sec/i.exec(txt))) add("mp5", m[1]);
        if ((m = /restore (\d+) health and (\d+) mana every 5 sec/i.exec(txt))) { add("hp5", m[1]); add("mp5", m[2]); }
      } else if ((m = /gain (\d+) increased Stamina/i.exec(txt))) { kind = "camp"; add("stamina", m[1]); dur = "camp"; }
      else if (/Cooldown\)/.test(txt)) {
        if ((m = /Attack Power by (\d+) for (\d+) sec/i.exec(txt))) { add("attackPower", m[1]); dur = m[2] + " sec"; }
        if ((m = /healing done by up to (\d+) for (\d+) sec/i.exec(txt))) { add("healing", m[1]); dur = m[2] + " sec"; }
        if ((m = /Spell Damage by (\d+) for (\d+) sec/i.exec(txt))) { add("spellDamage", m[1]); dur = m[2] + " sec"; }
        if ((m = /spell damage by (\d+) against (\w+)\.\s+Lasts (\d+) min/i.exec(txt))) { add("spellDamage", m[1], "against " + m[2]); dur = m[3] + " min"; }
        if (st.length) kind = "potion";
      }
      return { kind: kind, stats: st, dur: dur };
    }
    var CS = { strength: "Str", agility: "Agi", stamina: "Sta", intellect: "Int", spirit: "Spi", crit: "% crit", health: " health", armor: " armor",
      spellDamage: " spell damage", healing: " healing", mp5: " mp5", hp5: " hp5", attackPower: " AP" };
    function consumeLine(inf) {
      return inf.stats.map(function (x) { var pre = "+" + x[1]; return (CS[x[0]] && CS[x[0]].charAt(0) !== " " && CS[x[0]].charAt(0) !== "%" ? pre + " " + CS[x[0]] : pre + (CS[x[0]] || " " + x[0])) + (x[2] ? " (" + x[2] + ")" : ""); }).join(", ");
    }
    // What each spec wants from a consumable; "nature" counts Nature-only spell damage.
    var WANT = {
      WARRIOR: { Arms: "strength:3 crit:3 attackPower:2 agility:1", Fury: "strength:3 crit:3 attackPower:2 agility:1", Protection: "health:3 armor:3 stamina:3 strength:1" },
      PALADIN: { Holy: "healing:3 intellect:3 mp5:3 crit:1 spirit:1", Protection: "health:3 armor:3 stamina:3 spellDamage:1", Retribution: "strength:3 crit:3 attackPower:2 intellect:1" },
      HUNTER: { "*": "agility:3 attackPower:3 crit:2 intellect:1 mp5:1" },
      ROGUE: { "*": "agility:3 strength:2 attackPower:3 crit:3" },
      PRIEST: { Discipline: "healing:3 intellect:3 mp5:3 spirit:2", Holy: "healing:3 intellect:3 mp5:3 spirit:2", Shadow: "spellDamage:3 intellect:2 crit:2 spirit:2 stamina:1" },
      SHAMAN: { Elemental: "spellDamage:3 nature:3 intellect:2 crit:2 mp5:2", Enhancement: "strength:3 agility:2 attackPower:3 crit:3 intellect:1", Restoration: "healing:3 intellect:3 mp5:3" },
      MAGE: { "*": "spellDamage:3 intellect:3 crit:2 mp5:1 spirit:1" },
      WARLOCK: { "*": "spellDamage:3 stamina:2 intellect:2 crit:2 spirit:1" },
      DRUID: { Balance: "spellDamage:3 nature:3 intellect:2 crit:2 mp5:2", Feral: "agility:3 strength:3 attackPower:2 crit:2 stamina:1 armor:1 health:1", Restoration: "healing:3 intellect:3 mp5:3 spirit:2" }
    };
    function wantFor(cls, spec) {
      var byCls = WANT[cls] || {}, w = {};
      function merge(str) { String(str).split(" ").forEach(function (p) { var kv = p.split(":"); w[kv[0]] = Math.max(w[kv[0]] || 0, +kv[1]); }); }
      if (byCls["*"]) merge(byCls["*"]);
      else if (spec) Object.keys(byCls).forEach(function (k) { if (spec.indexOf(k) === 0) merge(byCls[k]); });
      if (!Object.keys(w).length) Object.keys(byCls).forEach(function (k) { merge(byCls[k]); });
      return w;
    }
    function consumeScore(inf, w) {
      return inf.stats.reduce(function (a, x) {
        if (x[2] && /spells$/.test(x[2])) return a + (/^Nature/.test(x[2]) ? (w.nature || 0) : 0);
        if (x[2]) return a;
        return a + (w[x[0]] || 0);
      }, 0);
    }
    function consumesHTML(ctx) {
      var lv = ctx.level || 60, chosen = cons(), w = wantFor(ctx.cls, ctx.specName);
      var all = items.filter(function (it) { return it.cat === "consumable" && (!window.FORGE_LVLCAP || !((it.reqLevel || 0) > LEVEL)); }).map(function (it) { return { it: it, inf: consumeInfo(it) }; });
      function usable(x) { return !x.it.reqLevel || x.it.reqLevel <= lv; }
      function chip(x) {
        var on = chosen.indexOf(x.it.id) !== -1, lock = !usable(x);
        return '<button type="button" class="cchip q-' + esc(x.it.quality || "common") + (on ? " on" : "") + (lock ? " lock" : "") + '" data-cons="' + esc(x.it.id) + '"' + (lock ? " disabled" : "") +
          ' data-tip="' + attr(itemTip(x.it) + (lock ? '<span class="it-src">Needs level ' + esc(x.it.reqLevel) + ".</span>" : "")) + '" data-tipcls="itemtip">' +
          '<span class="cc-ic">' + img(x.it.icon) + "</span><span class=\"cc-t\"><b>" + esc(x.it.name) + "</b><em>" + esc(consumeLine(x.inf) || (x.inf.kind === "utility" ? "Utility" : "")) + "</em></span></button>";
      }
      var sugg = all.filter(function (x) { return usable(x) && x.inf.kind !== "utility" && consumeScore(x.inf, w) >= 3; })
        .sort(function (a, b) { return consumeScore(b.inf, w) - consumeScore(a.inf, w) || (b.it.reqLevel || 0) - (a.it.reqLevel || 0); }).slice(0, 8);
      var active = all.filter(function (x) { return chosen.indexOf(x.it.id) !== -1; });
      var need = active.map(function (x) {
        var per = x.inf.kind === "elixir" ? "2 per hour" : x.inf.kind === "food" ? "4 per hour" : x.inf.kind === "potion" ? "On use, 2 min cooldown" : x.inf.kind === "camp" ? "At a campfire" : "As needed";
        return '<li><span class="cc-ic">' + img(x.it.icon) + '</span><b class="q-' + esc(x.it.quality || "common") + '">' + esc(x.it.name) + "</b><em>" + esc(per) + "</em><i>" + esc(x.it.source || "") + "</i></li>";
      }).join("");
      var groups = [["elixir", "Elixirs"], ["potion", "Potions"], ["food", "Food"], ["camp", "Camp"], ["utility", "First aid and utility"]];
      return '<div class="g2-cons" id="consumables"><div class="g2-cons-h"><h6>Consumables</h6><span>' + active.length + " picked</span>" +
          (active.length ? '<button type="button" class="g2-rx-link" data-cons-clear="1">Clear</button>' : "") + "</div>" +
        '<p class="g2-cons-sub">Suggested for ' + esc(ctx.specName ? ctx.specName + " " + ctx.classLabel : ctx.classLabel || "your class") + " at level " + lv + "</p>" +
        '<div class="cc-grid">' + (sugg.length ? sugg.map(chip).join("") : '<p class="g2-note">Nothing shown so far fits this spec at this level.</p>') + "</div>" +
        '<details class="cc-all"><summary>All Forever consumables (' + all.length + ")</summary>" + groups.map(function (g) {
          var list = all.filter(function (x) { return x.inf.kind === g[0]; });
          return list.length ? "<h6>" + g[1] + '</h6><div class="cc-grid">' + list.map(chip).join("") + "</div>" : "";
        }).join("") + "</details>" +
        (active.length ? '<div class="cc-need"><h6>What you need</h6><ul>' + need + "</ul></div>" : "") +
        '<p class="g2-note">Elixirs and food count in the stats above; potions show as on use. Effects are read from Forever tooltips; stacking rules are unconfirmed until beta.</p></div>';
    }
    var LEVEL = 60, CLS = "";
    if (typeof window.FORGE_LVLCAP === "undefined") window.FORGE_LVLCAP = false;
    // ---- Enchants (plan/enchants.json, or the built-in shield spikes) ----
    function slotMatch(es, slotKey) {
      var list = Array.isArray(es) ? es : [es];
      return list.some(function (x) { return x === slotKey || (x && slotKey.indexOf(x) === 0 && /\d$/.test(slotKey)); });
    }
    function enchantFits(en, it) { return !!it && (!en.needs || it.type === en.needs || it.sub === en.needs); }
    function enchantsFor(slotKey) { return (EXTRA.enchants || []).filter(function (en) { return slotMatch(en.slot, slotKey); }); }
    function enchantById(id) { return (EXTRA.enchants || []).filter(function (en) { return en.id === id; })[0] || null; }
    function activeEnchant(slotKey) {
      var en = enchantById(ench()[slotKey]), it = byId[eq()[slotKey]];
      return en && slotMatch(en.slot, slotKey) && enchantFits(en, it) && !overLevel(it) ? en : null;
    }
    function enchantIcon(en) { var src = byId[en.item]; return en.icon || (src && src.icon) || "inv_misc_enchantedscroll"; }
    function overLevel(it) { return !!it && effReq(it).lvl > LEVEL; }
    function totals() {
      var t = { __c: {}, __over: [] }, E = eq();
      SLOT_KEYS.forEach(function (k) {
        var it = byId[E[k]]; if (!it) return;
        if (overLevel(it)) { t.__over.push(it); return; }   // above your level: shown, not counted
        var s = istats(it);
        Object.keys(s).forEach(function (x) { if (typeof s[x] === "number") t[x] = (t[x] || 0) + s[x]; });
        if (it.armor) t.armor = (t.armor || 0) + it.armor;
        if (s.bonusArmor) t.armor = (t.armor || 0) + s.bonusArmor;
        if (it.block) t.block = (t.block || 0) + it.block;
        var en = activeEnchant(k);
        if (en && en.stats) Object.keys(en.stats).forEach(function (x) { if (typeof en.stats[x] === "number") t[x] = (t[x] || 0) + en.stats[x]; });
      });
      setBonusStats().forEach(function (b) { t[b[0]] = (t[b[0]] || 0) + b[1]; });
      cons().forEach(function (id) {
        var inf = consumeInfo(byId[id]);
        if (!inf || (inf.kind !== "elixir" && inf.kind !== "food" && inf.kind !== "camp")) return;
        if (byId[id].reqLevel && byId[id].reqLevel > LEVEL) return; // cannot be used at this level
        inf.stats.forEach(function (x) { if (x[2]) return; t[x[0]] = (t[x[0]] || 0) + x[1]; t.__c[x[0]] = (t.__c[x[0]] || 0) + x[1]; });
      });
      return t;
    }
    // Active set bonuses whose text is a plain stat line; anything else stays text only.
    function setBonusStats() {
      var E = eq(), worn = {}, sets = {}, out = [];
      SLOT_KEYS.forEach(function (k) { var w = byId[E[k]]; if (w && !overLevel(w)) { worn[w.name] = true; if (w.setName && !sets[w.setName]) sets[w.setName] = w; } });
      Object.keys(sets).forEach(function (n) {
        var it = sets[n], have = (it.setPieces || []).filter(function (p) { return worn[p]; }).length;
        (it.setBonuses || []).forEach(function (b) {
          if (have < b[0]) return;
          var s = String(b[1]).trim(), m;
          if ((m = /^\+(\d+) (Strength|Agility|Stamina|Intellect|Spirit)\.?$/.exec(s))) out.push([m[2].toLowerCase(), +m[1]]);
          else if ((m = /^Increased Spirit \+(\d+)\.?$/.exec(s))) out.push(["spirit", +m[1]]);
          else if ((m = /^\+(\d+) Attack Power\.?$/.exec(s))) out.push(["attackPower", +m[1]]);
          else if ((m = /^\+(\d+) All Resistances\.?$/.exec(s))) out.push(["allResist", +m[1]]);
          else if ((m = /^\+(\d+) (Fire|Frost|Nature|Shadow|Arcane) Resistance\.?$/.exec(s))) out.push([m[2].toLowerCase() + "Resist", +m[1]]);
          else if ((m = /^\+(\d+) Armor\.?$/.exec(s))) out.push(["armor", +m[1]]);
          else if ((m = /^Improves your chance to hit by (\d+(?:\.\d+)?)%\.?$/.exec(s))) out.push(["hit", +m[1]]);
          else if ((m = /^Improves your chance to get a critical strike with spells by (\d+(?:\.\d+)?)%\.?$/.exec(s))) out.push(["spellCrit", +m[1]]);
          else if ((m = /^Improves your chance to get a critical strike(?: with melee attacks)? by (\d+(?:\.\d+)?)%\.?$/.exec(s))) out.push(["crit", +m[1]]);
          else if ((m = /^Restores (\d+) mana per 5 sec\.?$/.exec(s))) out.push(["mp5", +m[1]]);
          else if ((m = /^Increased Defense \+(\d+)\.?$/.exec(s))) out.push(["defense", +m[1]]);
          else if ((m = /^(?:\+(\d+) Block Value|Increases the block value of your shield by (\d+))\.?$/i.exec(s))) out.push(["blockValue", +(m[1] || m[2])]);
          else if ((m = /^Increases healing done by up to (\d+) and damage done by up to (\d+) for all magical spells and effects\.?$/.exec(s))) { out.push(["healing", +m[1]]); out.push(["spellDamage", +m[2]]); }
          else if ((m = /^Increases damage and healing done by magical spells and effects by up to (\d+)\.?$/.exec(s))) out.push(["spellPower", +m[1]]);
        });
      });
      return out;
    }
    function slotHTML(def) {
      var it = byId[eq()[def[0]]], over = overLevel(it), en = it ? activeEnchant(def[0]) : null;
      var blocked = def[0] === "offhand" && byId[eq().mainhand] && byId[eq().mainhand].slot === "two-hand";
      var canEnch = it && enchantsFor(def[0]).some(function (x) { return enchantFits(x, it); });
      var tip = it ? itemTip(it) + (en ? '<span class="it-g">Enchant: ' + esc(en.name) + "</span>" : "") +
        (over ? '<span class="it-warn">Needs level ' + effReq(it).lvl + (effReq(it).est ? " (estimated)" : "") + ": above your level " + LEVEL + ", so the stat panel does not count it.</span>" : "")
        : "<b>" + esc(def[1]) + "</b>" + (blocked ? "Your two-hander fills this." : "Empty. Click to pick an item.");
      return '<div class="gslot-w">' +
        '<button type="button" class="gslot' + (it ? " filled q-" + esc(it.quality || "common") : "") + (blocked ? " blocked" : "") + (over ? " over" : "") + '" data-gslot="' + def[0] + '" data-tip="' +
        attr(tip) + '"' + (it ? ' data-tipcls="itemtip"' : "") + ">" +
        '<span class="gs-ic">' + img(it ? it.icon : def[2]) + "</span>" +
        '<span class="gs-t"><em>' + esc(def[1]) + (over ? ' <i class="gs-over">needs ' + effReq(it).lvl + "</i>" : "") + "</em><b>" + (it ? esc(it.name) : "Empty") + "</b>" +
          (en ? '<i class="gs-en">' + esc(en.name) + "</i>" : "") + "</span></button>" +
        (canEnch ? '<button type="button" class="gs-ench' + (en ? " on" : "") + '" data-gench="' + def[0] + '" aria-label="' + (en ? "Change enchant" : "Add an enchant") + '" data-tip="' +
          attr("<b>" + (en ? esc(en.name) : "Enchant") + "</b>" + (en ? "Change or remove the enchant on this slot." : "Add an enchant or shield spike to this slot.")) + '">' + img(en ? enchantIcon(en) : "inv_misc_enchantedscroll") + "</button>" : "") +
        "</div>";
    }
    // Racial effects that are always on (passives with no condition), plus weapon-conditional crit.
    function racialMods(racials) {
      var m = { pct: {}, add: {}, weaponCrit: [] };
      (racials || []).forEach(function (r) {
        if (r.kind !== "passive") return;
        (r.fx || []).forEach(function (e) {
          if (e.stat === "critWithWeapon") { m.weaponCrit.push({ value: e.value, when: e.when || "", from: r.n }); return; }
          if (e.when) return;
          if (["strength", "agility", "stamina", "intellect", "spirit", "health", "mana", "rage", "energy"].indexOf(e.stat) !== -1) m.pct[e.stat] = (m.pct[e.stat] || 0) + e.value;
          else if (["hit", "crit", "dodge", "haste"].indexOf(e.stat) !== -1) m.add[e.stat] = (m.add[e.stat] || 0) + e.value;
        });
      });
      return m;
    }
    function weaponMatches(when) {
      var E = eq(), w = String(when || "").toLowerCase();
      // "while Holy Shield is active" names a buff, not a shield: buff conditions never count as always on.
      if (/\bactive\b/.test(w)) return false;
      return ["mainhand", "offhand", "ranged"].some(function (k) {
        var it = byId[E[k]]; if (!it || !it.type) return false;
        return w.indexOf(it.type.toLowerCase()) !== -1;
      });
    }
    function row(label, value, tip, on, cls) {
      return '<div class="gst' + (on ? " on" : "") + (cls ? " " + cls : "") + '"' + (tip ? ' data-tip="' + attr("<b>" + esc(label) + "</b>" + tip) + '"' : "") + "><span>" + esc(label) + "</span><b>" + value + "</b></div>";
    }
    // Reflect toggles live per viewer: Retribution Aura on by default for paladins, druid Thorns off.
    var RFT = lsGet("forge-rf") || {};
    function rftOn(k) { return k === "ret" ? RFT.ret !== false : !!RFT[k]; }
    function rankAt(ranks, lv) { var r = null; (ranks || []).forEach(function (x) { if (x[0] <= lv) r = x; }); return r; }
    function rfCfg() { return EXTRA.reflect || DEFAULT_REFLECT; }
    function html(ctx) {
      LEVEL = ctx.level || 60;
      CLS = ctx.cls || "";
      var t = totals(), count = SLOT_KEYS.filter(function (k) { return byId[eq()[k]]; }).length;
      var M = racialMods(ctx.racials), base = ctx.base, lv = ctx.level, TAL = ctx.talents || {};
      // Talent effects at the learned rank; conditional ones count when a matching weapon is equipped.
      var TP = {}, TA = {}, TC = [];
      (ctx.talentFx || []).forEach(function (e) {
        var stat = e[0] === "spellCrit" ? "crit" : e[0] === "spellHit" ? "hit" : e[0], on = !e[3] || weaponMatches(e[3]);
        if (!on) { TC.push(e); return; }
        if (e[1] === "pct") TP[stat] = (TP[stat] || 0) + e[2]; else TA[stat] = (TA[stat] || 0) + e[2];
      });
      var F = ctx.formula || null, li = ctx.levelIdx != null ? ctx.levelIdx : -1, EST = " WoW Classic 1.12 formula, an estimate until Forever publishes its own.";
      var ATTR = [["strength", "Strength"], ["agility", "Agility"], ["stamina", "Stamina"], ["intellect", "Intellect"], ["spirit", "Spirit"]], A = {};
      var attrs = ATTR.map(function (x, i) {
        var b0 = base ? base[i] : null, g = (t[x[0]] || 0) + (TA[x[0]] || 0), pct = (M.pct[x[0]] || 0) + (TP[x[0]] || 0);
        var tot = b0 == null ? null : Math.floor((b0 + g) * (1 + pct / 100));
        A[x[0]] = tot;
        var tip = (b0 == null ? "Base value unpublished for this race. " : "Base " + b0 + " at level " + lv + ". ") + "Gear and set bonuses +" + ((t[x[0]] || 0) - (t.__c[x[0]] || 0)) + "." + (t.__c[x[0]] ? " Consumables +" + t.__c[x[0]] + "." : "") +
          (M.pct[x[0]] ? " Racial +" + M.pct[x[0]] + "%." : "") + (TP[x[0]] || TA[x[0]] ? " Talents " + (TA[x[0]] ? "+" + TA[x[0]] : "") + (TP[x[0]] ? " +" + TP[x[0]] + "%" : "") + "." : "");
        return row(x[1], tot == null ? (g ? "+" + g : "?") : tot + (pct ? '<i class="rx">+' + pct + "%</i>" : ""), tip, tot || g, "");
      }).join("");
      function r1(v) { return Math.round(v * 100) / 100; }
      var known = A.strength != null, hm = ctx.baseHM, power = ctx.power || "mana", pools = "";
      if (hm) {
        var hpPct = (M.pct.health || 0) + (TP.health || 0), sta = A.stamina;
        var hp = sta == null ? null : Math.round((hm[0] + Math.min(sta, 20) + Math.max(sta - 20, 0) * 10) * (1 + hpPct / 100)) + (t.health || 0) + (TA.health || 0);
        pools += row("Health", hp == null ? "?" : hp + (hpPct ? '<i class="rx">+' + hpPct + "%</i>" : ""), "Base " + hm[0] + ", the first 20 Stamina add 1 health each and the rest 10 each" + (t.health ? ", plus " + t.health + " from consumables" : "") + ". 10 health per Stamina matches the beta client's gametables; base health and the first-20 rule are Classic 1.12 estimates.", true, "");
        if (power === "mana" && hm[1]) {
          var mpPct = (M.pct.mana || 0) + (TP.mana || 0), int = A.intellect;
          var mp = int == null ? null : Math.round((hm[1] + Math.min(int, 20) + Math.max(int - 20, 0) * 15) * (1 + mpPct / 100));
          pools += row("Mana", mp == null ? "?" : mp + (mpPct ? '<i class="rx">+' + mpPct + "%</i>" : ""), "Base " + hm[1] + " straight from the beta client (build 1.60.1.69876); the first 20 Intellect add 1 mana each and the rest 15 each, a Classic rule.", true, "");
        } else if (M.pct[power]) pools += row("Max " + power, '<i class="rx">+' + M.pct[power] + "%</i>", "Racial bonus to maximum " + power + ".", true, "");
      }
      var wc = M.weaponCrit.filter(function (w) { return weaponMatches(w.when); }).reduce(function (a, w) { return a + w.value; }, 0);
      function bonusTip(k, racial) {
        return "Gear +" + r1((t[k] || 0) - (t.__c[k] || 0)) + (t.__c[k] ? ", consumables +" + t.__c[k] : "") + (racial ? ", racial +" + racial : "") + (TA[k] ? ", talents +" + TA[k] : "") + ".";
      }
      var off = "";
      if (F && F.ap && known) {
        var ap = Math.max(0, Math.round(A.strength * F.ap[0] + A.agility * F.ap[1] + lv * F.ap[2] + F.ap[3])) + (t.attackPower || 0) + (TA.attackPower || 0);
        off += row("Attack Power", ap, "Strength x" + F.ap[0] + (F.ap[1] ? " + Agility x" + F.ap[1] : "") + (F.ap[2] ? " + level x" + F.ap[2] : "") + " " + F.ap[3] + ", plus " + bonusTip("attackPower") + EST, true, "");
      }
      if (F && F.rap && known && ctx.cls === "HUNTER") {
        off += row("Ranged Attack Power", Math.max(0, Math.round(A.agility * F.rap[1] + lv * F.rap[2] + F.rap[3])) + (t.attackPower || 0) + (t.rangedAttackPower || 0) + (TA.rangedAttackPower || 0), "Agility x" + F.rap[1] + " + level x" + F.rap[2] + " " + F.rap[3] + ", plus gear attack power and ranged attack power." + EST, true, "");
      } else if (t.rangedAttackPower) off += row("Ranged Attack Power", "+" + t.rangedAttackPower, "Ranged attack power from gear only; the base from Agility is not computed for this class.", true, "");
      var critBonus = (t.crit || 0) + (M.add.crit || 0) + wc + (TA.crit || 0);
      if (F && F.mc && known && li >= 0) {
        var mc = F.mc[0][li] + A.agility / F.mc[1][li] + critBonus;
        off += row("Crit", r1(mc) + "%", "Base " + F.mc[0][li] + "% + Agility / " + F.mc[1][li] + " at level " + lv + ", plus " + bonusTip("crit", (M.add.crit || 0) + wc) + EST +
          (M.weaponCrit.length ? " " + M.weaponCrit.map(function (w) { return w.from + ": +" + w.value + "% with " + w.when + (weaponMatches(w.when) ? " (active)" : " (no matching weapon)"); }).join(" ") : ""), true, "");
      } else off += row("Crit", "+" + r1(critBonus) + "%", bonusTip("crit", (M.add.crit || 0) + wc) + " Crit from Agility is unknown for this race.", critBonus, "");
      if (F && F.sc && known && li >= 0) {
        off += row("Spell crit", r1(F.sc[0][li] + A.intellect / F.sc[1][li] + critBonus + (t.spellCrit || 0)) + "%", "Base " + F.sc[0][li] + "% + Intellect / " + F.sc[1][li] + " at level " + lv + ", plus crit from gear, racials and talents (Forever unifies crit)" + (t.spellCrit ? " and +" + t.spellCrit + "% spell crit from set bonuses" : "") + "." + EST, true, "");
      }
      [["hit", "Hit"], ["expertise", "Expertise"], ["haste", "Haste"]].forEach(function (x) {
        var v = (t[x[0]] || 0) + (M.add[x[0]] || 0) + (TA[x[0]] || 0);
        off += row(x[1], "+" + r1(v) + "%", bonusTip(x[0], M.add[x[0]]) + " Base values are unpublished for Forever.", v, "");
      });
      var sp = (t.spellPower || 0) + (TA.spellPower || 0), sdmg = (t.spellDamage || 0) + sp, heal = (t.healing || 0) + sp, holy = sdmg + (t.holySpellDamage || 0);
      if (sdmg) off += row("Spell Damage", sdmg, "Spell damage " + (t.spellDamage || 0) + " + spell power " + sp + " (spell power raises damage and healing)." + (sp ? "" : ""), true, "");
      if (heal) off += row("Healing Power", heal, "Bonus healing " + (t.healing || 0) + " + spell power " + sp + ".", true, "");
      if ((CLS === "PALADIN" || CLS === "PRIEST") && holy) off += row("Holy Damage", holy, "Holy spell damage " + (t.holySpellDamage || 0) + " + spell damage " + (t.spellDamage || 0) + " + spell power " + sp + ". Holy Shield and Consecration scale with it.", true, "");
      ["fire", "frost", "nature", "shadow", "arcane"].forEach(function (x) {
        if (t[x + "SpellDamage"]) off += row(cap1(x) + " Damage", t[x + "SpellDamage"] + sdmg, cap1(x) + " spell damage " + t[x + "SpellDamage"] + " + spell damage and spell power " + sdmg + ".", true, "");
      });
      off += row("Spell Penetration", t.spellPiercing || 0, "Gear " + (t.spellPiercing || 0) + ". Each point lowers the target's resistance to your spells by 1; counted from item stats and, where only the tooltip states it, from the tooltip text.", !!t.spellPiercing, "");
      off += [["weaponDamage", "Weapon Damage"], ["weaponSkill", "Weapon Skill"]].map(function (x) {
        var v = (t[x[0]] || 0) + (TA[x[0]] || 0); return v ? row(x[1], v, bonusTip(x[0]), true, "") : "";
      }).join("");
      // ---- Defense: armor, avoidance and block, with the Classic defense-skill rule on top ----
      var armorItems = (t.armor || 0) + (TA.armor || 0), armorPct = TP.armor || 0;
      var armor = known ? Math.round((armorItems + A.agility * 2) * (1 + armorPct / 100)) : null;
      var aK = ctx.armorK ? ctx.armorK[String(lv)] : null, aDR = armor != null && aK ? r1(100 * armor / (armor + aK)) : null;
      var def = row("Armor", armor == null ? "+" + armorItems : armor + (armorPct ? '<i class="rx">+' + armorPct + "%</i>" : ""), "Items " + armorItems + (known ? " + Agility x2 (Classic rule)" : "") + (armorPct ? ", talents +" + armorPct + "%" : "") + "." + (aDR != null ? " Cuts physical damage from level " + lv + " enemies by " + aDR + "%, using the beta client's armor table." : ""), true, "");
      var defPts = (t.defense || 0) + (TA.defense || 0), defB = r1(defPts * 0.04), DEFRULE = " Defense: each point above 5 x your level adds 0.04% to dodge, parry, block and the chance to be missed (Classic rule; Forever's own value is unpublished).";
      def += row("Defense", 5 * lv + defPts + (defPts ? '<i class="rx">+' + defPts + "</i>" : ""), "Base " + 5 * lv + " (5 x level " + lv + "), plus " + bonusTip("defense") + (defPts ? " Worth +" + defB + "% dodge, parry, block and miss." : "") + DEFRULE, true, "");
      var vMiss = 5 + defB, vDodge = 0, vParry = 0, vBlock = 0, avKnown = true;
      def += row("Miss", r1(vMiss) + "%", "Chance a same-level attacker misses you: 5% base" + (defB ? " + " + defB + "% from defense" : "") + ". Classic rule, an estimate.", true, "");
      var dgBonus = (M.add.dodge || 0) + (t.dodge || 0) + (TA.dodge || 0) + defB;
      if (F && F.dg && known && li >= 0) { vDodge = F.dg[0][li] + A.agility / F.dg[1][li] + dgBonus; def += row("Dodge", r1(vDodge) + "%", "Base " + F.dg[0][li] + "% + Agility / " + F.dg[1][li] + ", plus " + bonusTip("dodge", M.add.dodge) + (defB ? " Defense +" + defB + "%." : "") + EST, true, ""); }
      else { vDodge = dgBonus; avKnown = false; if (dgBonus) def += row("Dodge", "+" + r1(dgBonus) + "%", bonusTip("dodge", M.add.dodge) + (defB ? " Defense +" + defB + "%." : "") + " Dodge from Agility is unknown here.", true, ""); }
      if (F && F.pa) { vParry = F.pa + (TA.parry || 0) + (t.parry || 0) + defB; def += row("Parry", r1(vParry) + "%", "Base " + F.pa + "%" + (TA.parry ? ", talents +" + TA.parry : "") + (t.parry ? ", gear " + (t.parry > 0 ? "+" : "") + r1(t.parry) : "") + (defB ? ", defense +" + defB + "%" : "") + "." + EST, true, ""); }
      else if (t.parry) { vParry = t.parry; def += row("Parry", (t.parry > 0 ? "+" : "") + r1(t.parry) + "%", "Gear parry rating, converted at the client's rating table.", true, ""); }
      var shieldIt = byId[eq().offhand], shield = !!(shieldIt && shieldIt.type === "Shield" && !overLevel(shieldIt));
      if (shield) {
        vBlock = (F && F.bl ? F.bl : 0) + (TA.block || 0) + (t.blockChance || 0) + defB;
        RF_BLOCK.p = Math.max(0, Math.min(1, vBlock / 100)); RF_BLOCK.mine = true;
        def += row("Block", r1(vBlock) + "%", (F && F.bl ? "Base " + F.bl + "% with a shield" : "Base block chance unpublished for this class") + (TA.block ? ", talents +" + TA.block : "") + (t.blockChance ? ", gear +" + r1(t.blockChance) + "% (block rating)" : "") + (defB ? ", defense +" + defB + "%" : "") + "." + EST, true, "");
      } else if (t.blockChance) def += row("Block", "+" + r1(t.blockChance) + "%", "Block rating from gear; it only works with a shield equipped.", false, "");
      var ssR = CLS === "PALADIN" ? +TAL["Shield Specialization"] || 0 : 0, ssPct = ssR * 10;
      var bvStr = known ? Math.floor(A.strength / 20) : 0, bvRaw = (t.block || 0) + (t.blockValue || 0) + bvStr, bv = Math.round(bvRaw * (1 + ssPct / 100));
      if (shield || t.blockValue) def += row("Block Value", bv, "Damage a block stops: shield " + (t.block || 0) + " + gear and set bonuses " + (t.blockValue || 0) + (known ? " + Strength / 20 = " + bvStr + " (Classic rule, an estimate)" : "") +
        (ssPct ? ", then Shield Specialization +" + ssPct + "% (talent text)" : "") + "." + (shield ? "" : " Needs a shield to matter."), shield, "");
      if (F && F.mp5 && known && power === "mana") def += row("Mana per 5", Math.round(A.spirit * F.mp5[0] + F.mp5[1]) + (t.mp5 ? " + " + (t.mp5 + (TA.mp5 || 0)) : ""), "From Spirit while not casting: Spirit x" + F.mp5[0] + " + " + F.mp5[1] + "." + EST + (t.mp5 ? " The second number is gear and consumable mp5, which also works while casting." : ""), true, "");
      else if (t.mp5) def += row("Mana per 5", t.mp5, bonusTip("mp5"), true, "");
      if (t.hp5) def += row("Health per 5", t.hp5, bonusTip("hp5"), true, "");
      if (TC.length) def += row("Conditional talents", TC.length, TC.map(function (e) { return "+" + e[2] + (e[1] === "pct" ? "% " : " ") + e[0] + " when " + e[3]; }).join("; ") + ". Not counted above.", false, "");
      // ---- Resistances ----
      var res = ["fire", "frost", "nature", "shadow", "arcane"].map(function (x) {
        var v = (t[x + "Resist"] || 0) + (t.allResist || 0);
        return [x, v];
      });
      var resHTML = res.some(function (x) { return x[1]; }) ? res.map(function (x) {
        return row(cap1(x[0]), x[1], cap1(x[0]) + " resistance from gear " + (t[x[0] + "Resist"] || 0) + (t.allResist ? " + all resistances " + t.allResist : "") + ". Racial resistances are not added here.", !!x[1], "");
      }).join("") : "";
      // ---- Reflect: damage dealt back to whoever hits you ----
      var RC = rfCfg(), PAL = (RC.classes || {}).PALADIN || DEFAULT_REFLECT.classes.PALADIN, BUFF = (RC.buffs || {}).thorns || DEFAULT_REFLECT.buffs.thorns;
      var hitSrc = [], blockSrc = [], notes = [];
      function srcLine(n, e, per) {
        var amt = e.v == null ? "?" : (e.lo != null && e.hi != null && e.lo !== e.hi ? e.lo + "–" + e.hi + " (avg " + r1(e.v) + ")" : r1(e.v));
        var how = e.k === "proc" ? Math.round((e.p || 0) * 1000) / 10 + "% chance for " + amt + ", counted as " + r1(per)
          : e.k === "use" ? (typeof e.up === "number" ? "on use, " + amt + " while up (" + Math.round(e.up * 100) + "% uptime), counted as " + r1(per) : amt + ", " + (e.note || "uptime unknown") + ": not counted")
          : e.k === "block" && e.p != null && e.p < 1 ? Math.round(e.p * 100) + "% chance for " + amt + " on a block, counted as " + r1(per)
          : amt + (e.v == null ? " (" + (e.note || "amount unknown") + ": not counted)" : "");
        return esc(n) + ": " + esc(how) + " " + esc(e.s || "Physical") + (e.aoe ? ", hits all nearby attackers" : "") + (e.sp ? " (spell " + esc(e.sp) + ")" : "") + (e.src === "text" ? " [read from the tooltip]" : e.src === "client" ? " [client tables]" : "");
      }
      function addRf(n, e) {
        if (e.k === "block") { var b = rfPerBlock(e); blockSrc.push([b, srcLine(n, e, b)]); }
        else if (e.k === "crit") notes.push(esc(n) + ": returns " + esc(e.v) + "% of critical-strike damage taken; depends on the attacker, not counted.");
        else { var h = rfPerHit(e); hitSrc.push([h, srcLine(n, e, h)]); }
      }
      SLOT_KEYS.forEach(function (k) {
        var it = byId[eq()[k]]; if (!it || overLevel(it)) return;
        reflect(it).forEach(function (e) { addRf(it.name, e); });
        var en = activeEnchant(k);
        if (en && en.rf) [].concat(en.rf).forEach(function (f) { addRf(en.name + " (enchant)", f); });
      });
      if (CLS === "PALADIN") {
        var ra = rankAt(PAL.retAura, lv), raIdx = ra ? PAL.retAura.indexOf(ra) + 1 : 0;
        if (rftOn("ret")) {
          if (ra) { var rav = ra[1] + (PAL.retCoef || 0) * holy; hitSrc.push([rav, "Retribution Aura rank " + raIdx + " (learned at " + ra[0] + "): " + r1(rav) + " Holy (spell " + ra[2] + ")" + (PAL.retCoef ? ", " + PAL.retCoef + " x Holy damage" : "")]); }
          else notes.push("Retribution Aura is learned at level " + ((PAL.retAura || [[16]])[0][0]) + ".");
        }
        if (TAL["Holy Shield"]) {
          var HS = PAL.holyShield || DEFAULT_REFLECT.classes.PALADIN.holyShield, hr = rankAt(HS.ranks, lv);
          if (!hr) notes.push("Holy Shield rank 1 is learned at level " + ((HS.ranks || [[40]])[0][0]) + ".");
          else if (!shield) notes.push("Holy Shield needs a shield you can use.");
          if (hr && shield) {
            var hsv = hr[1] + (HS.coef || 0) * holy;
            blockSrc.push([hsv, "Holy Shield rank " + (HS.ranks.indexOf(hr) + 1) + ": " + hr[1] + " + " + (HS.coef || 0) + " x Holy damage " + holy + " = " + r1(hsv) + " Holy per block (spell " + hr[2] + "); " + (HS.charges || 4) + " charges per " + (HS.dur || 10) + " s, counted as if kept up" + (hr[0] > lv ? "; rank 1 needs level " + hr[0] : "") + "."]);
          }
        }
        if (TAL.Redoubt) notes.push("Redoubt: a chance on being hit to raise block chance for a few blocks; not counted.");
        if (TAL["Eye for an Eye"]) { var ef = (PAL.eyeForAnEye || {}).pct || [5, 10]; notes.push("Eye for an Eye: " + (ef[TAL["Eye for an Eye"] - 1] || ef[0]) + "% of critical-strike damage taken goes back to the attacker; depends on the attacker, not counted."); }
      }
      if (rftOn("thorns")) {
        var th = rankAt(BUFF.ranks, lv);
        if (th) hitSrc.push([th[1], esc(BUFF.name || "Thorns") + " rank " + (BUFF.ranks.indexOf(th) + 1) + " (a level " + th[0] + " druid's): " + th[1] + " " + (BUFF.s || "Nature") + (th[2] ? " (spell " + th[2] + ")" : "")]);
        else notes.push("Thorns is learned by druids at level " + ((BUFF.ranks || [[6]])[0][0]) + ".");
      }
      function sum(a) { return a.reduce(function (s, x) { return s + x[0]; }, 0); }
      function parts(a) { var p = a.filter(function (x) { return x[0]; }).map(function (x) { return r1(x[0]); }); return p.length > 1 ? '<i class="rf-sum">' + p.join("+") + "</i>" : ""; }
      hitSrc.sort(function (a, b) { return b[0] - a[0]; });
      var perHit = sum(hitSrc), perBlock = sum(blockSrc);
      var pAvoid = Math.min(1, (vMiss + vDodge + vParry) / 100), pBlock = shield ? Math.min(vBlock / 100, 1 - pAvoid) : 0, pLand = 1 - pAvoid;
      var perSwing = pLand * perHit + pBlock * perBlock;
      var IGN = " Attacker armor and resistances are ignored.";
      var rfHTML = '<div class="rf-tg">' + (CLS === "PALADIN" ? '<button type="button" data-rft="ret" aria-pressed="' + rftOn("ret") + '"' + (rftOn("ret") ? ' class="on"' : "") + ">Retribution Aura</button>" : "") +
          '<button type="button" data-rft="thorns" aria-pressed="' + rftOn("thorns") + '"' + (rftOn("thorns") ? ' class="on"' : "") + ">Thorns (druid)</button></div>" +
        row("Reflect per enemy swing", r1(perSwing),
          (hitSrc.length ? '<span class="it-l"><b>Every hit that lands: ' + r1(perHit) + "</b></span>" + hitSrc.map(function (x) { return '<span class="it-l">' + x[1] + "</span>"; }).join("") : "") +
          (blockSrc.length ? '<span class="it-l"><b>Every block: ' + r1(perBlock) + (shield ? "" : " (needs a shield)") + "</b></span>" + blockSrc.map(function (x) { return '<span class="it-l">' + x[1] + "</span>"; }).join("") : "") +
          (!hitSrc.length && !blockSrc.length ? "Nothing equipped or active hurts whoever hits you." : "") +
          '<span class="it-src">Spikes, thorns and damage on block, as one number: lands ' + Math.round(pLand * 1000) / 10 + "% x " + r1(perHit) + (shield ? " + blocked " + Math.round(pBlock * 1000) / 10 + "% x " + r1(perBlock) : "") +
          ", from this panel's miss " + r1(vMiss) + "%, dodge " + r1(vDodge) + "%, parry " + r1(vParry) + "%" + (shield ? " and block " + r1(vBlock) + "%" : "") + "." + (avKnown ? "" : " Dodge from Agility is unknown here, so this runs high.") + IGN + "</span>", perSwing > 0, "") +
        row("Reflect DPS", r1(perSwing / 2), "Expected damage per swing against one attacker swinging every 2.0 s. Each extra attacker adds as much again." + IGN, perSwing > 0, "") +
        (notes.length ? '<p class="g2-note">' + notes.join(" ") + "</p>" : "");
      // ---- Procs and on-use: chance on hit, use and equip procs of what is equipped ----
      var E0 = eq(), mhIt = byId[E0.mainhand], mhSpd = mhIt && !overLevel(mhIt) && weaponSpeed(mhIt) ? weaponSpeed(mhIt) : 0, baseSpd = mhSpd || 2.0;
      var pxRows = "", pxTot = 0, pxUnknown = 0, PXIGN = " Estimate: every swing is assumed to land (misses, dodges, parries and glancing blows are not modelled), target armor and resistances are ignored, and haste or extra attacks do not add swings.";
      function pct(c) { return Math.round(c * 1000) / 10 + "%"; }
      function srcTag(g) { return g.src === "client" ? " [client spell tables" + (g.sp ? ", spell " + esc(g.sp) : "") + "]" : " [read from the tooltip]"; }
      SLOT_KEYS.forEach(function (k) {
        var it = byId[E0[k]]; if (!it || overLevel(it)) return;
        var own = weaponSpeed(it), spd = own || baseSpd, spdWhy = own ? "its own speed " + own.toFixed(2) + " s" : mhSpd ? "your main hand's speed " + mhSpd.toFixed(2) + " s" : "2.0 s (no main-hand weapon)";
        fxGroups(procs(it)).forEach(function (g) {
          var what = grpWhat(g), L = ['<span class="it-l">' + esc(g.t || what) + "</span>"], val = "", on = false;
          var c = g.k === "hit" ? procChance(g, spd) : null;
          if (g.k === "hit") {
            var cTxt = g.p != null ? pct(c) + " per hit (the client's proc chance)" : g.ppm ? pct(c) + " per swing: " + g.ppm + " procs per minute x " + spdWhy + " / 60" : null;
            if (g.only && g.dmg) { val = "situational"; L.push('<span class="it-l">Only against ' + esc(g.only) + ": not counted in the total.</span>"); }
            else if (g.dmg && RANGED[it.slot] && CLS !== "HUNTER") { val = "ranged only"; L.push('<span class="it-l">Procs on ranged attacks (' + pct(c || 0) + " per shot), which this class rarely makes: not counted in the melee total.</span>"); }
            else if (c == null) { pxUnknown++; L.push('<span class="it-l">Chance unknown: the client gives neither a proc chance nor procs per minute, so it is not counted.</span>'); val = "chance unknown"; }
            else if (g.dmg) {
              var d = c * g.dmg / spd, capped = g.icd && g.dmg / g.icd < d;
              if (capped) d = g.dmg / g.icd;
              pxTot += d; on = true; val = r1(d) + " dps";
              L.push('<span class="it-l">Chance ' + esc(cTxt) + ". Average " + r1(g.dmg) + " damage per proc" + (g.rows.some(function (e) { return e.what === "dot"; }) ? " (damage over time counted in full)" : "") + ".</span>");
              L.push('<span class="it-l">' + pct(c) + " x " + r1(g.dmg) + " / " + spd.toFixed(2) + " s = " + r1(d) + " damage per second" + (capped ? ", capped by the " + g.icd + " s internal cooldown" : "") + ".</span>");
            } else {
              var up = null, bd = null;
              g.rows.forEach(function (e) { if (e.what === "buff" && e.dur) bd = e.dur; });
              if (bd) { up = Math.min(1, c * bd / spd); val = "~" + Math.round(up * 100) + "% up"; }
              else val = pct(c);
              L.push('<span class="it-l">Chance ' + esc(cTxt) + "." + (up != null ? " Estimated uptime " + Math.round(up * 100) + "%: " + pct(c) + " x " + bd + " s / " + spd.toFixed(2) + " s, capped at 100%. Not added to the stats above." : " No damage to count.") + "</span>");
            }
          } else if (g.k === "use") {
            var cdT = g.cd ? fmtDur(g.cd) : "cooldown unknown", main = g.dmg || g.rows.reduce(function (a, e) { return a + ((e.what === "heal" || e.what === "mana") && e.v ? +e.v : 0); }, 0);
            val = (main ? Math.round(main) + " / use" : "use") ;
            L.push('<span class="it-l">On use: ' + esc(what) + (main ? ", average " + r1(main) + " per use" : "") + ". Cooldown " + esc(cdT) + "." +
              (main && g.cd ? " About " + r1(main * 60 / g.cd) + " per minute if used on cooldown." : "") + " Not part of the proc damage per second.</span>");
          } else {
            val = g.p != null ? pct(g.p) : "equip";
            L.push('<span class="it-l">Equip proc' + (g.p != null ? ", " + pct(g.p) + " chance" : ", chance unknown") + (g.icd ? ", at most once every " + fmtDur(g.icd) : "") + ". Triggers on spells, being hit or similar, not on your swings, so it is not part of the proc damage per second.</span>");
          }
          L.push('<span class="it-src">' + (g.k === "hit" ? "Chance on hit" : g.k === "use" ? "Use" : "Equip proc") + srcTag(g) + "." + (g.k === "hit" ? PXIGN : "") + "</span>");
          pxRows += '<div class="gst px-r' + (on ? " on" : "") + '" data-tip="' + attr("<b>" + esc(it.name) + "</b>" + L.join("")) + '"><span><em class="px-k">' + (g.k === "hit" ? "Hit" : g.k === "use" ? "Use" : "Equip") + "</em>" + esc(it.name) + ': <i class="px-w">' + esc(what) + "</i></span><b>" + esc(val) + "</b></div>";
        });
      });
      var pxHTML = row("Proc damage per second (est.)", r1(pxTot), "Sum of the chance-on-hit damage of everything equipped. Weapon procs use that weapon's speed; armor, ring and trinket procs use " +
          (mhSpd ? "your main hand's speed (" + mhSpd.toFixed(2) + " s)" : "2.0 s, since no main-hand weapon is equipped") + ". Chance per swing is the client's proc chance, else procs per minute x speed / 60." +
          (pxUnknown ? " " + pxUnknown + " effect" + (pxUnknown === 1 ? " has" : "s have") + " no known chance and " + (pxUnknown === 1 ? "is" : "are") + " not counted." : "") + '<span class="it-src">' + PXIGN.trim() + " On-use and other equip procs are listed, not added.</span>", pxTot > 0, "") +
        (pxRows || '<p class="g2-note">Nothing equipped has a chance-on-hit, use or equip proc effect.</p>');
      var rx = (ctx.racials || []).map(function (r) {
        var SHOWN = ["strength", "agility", "stamina", "intellect", "spirit", "health", "mana", "rage", "energy", "hit", "crit", "dodge", "haste"];
        var fx = r.fx || [];
        var counted = r.kind === "passive" && fx.some(function (e) { return !e.when && SHOWN.indexOf(e.stat) !== -1; });
        var weapon = r.kind === "passive" && fx.some(function (e) { return e.stat === "critWithWeapon"; });
        var situational = r.kind === "passive" && !counted && !weapon && fx.length;
        var line = counted ? '<span class="it-g">Counted in the stats above.</span>'
          : weapon ? '<span class="it-g">Counted in Crit when a matching weapon is equipped.</span>'
          : situational ? '<span class="it-src">Situational; not part of the panel totals.</span>'
          : r.kind === "active" && fx.length ? '<span class="it-src">Only while active; not counted.</span>' : "";
        var applied = counted || (weapon && M.weaponCrit.some(function (w) { return w.from === r.n && weaponMatches(w.when); }));
        return '<div class="rxchip' + (applied ? " on" : "") + '" data-tip="' + attr("<b>" + esc(r.n) + "</b>" + '<span class="it-l">' + (r.kind === "passive" ? "Passive" : "Active") + "</span>" + esc(r.tip || "") + line) + '">' +
          img(r.icon) + "<span><b>" + esc(r.n) + "</b><em>" + esc(r.summary || (r.kind === "active" ? "Active ability" : "")) + "</em></span></div>";
      }).join("");
      var note = (base ? "Base mana, armor mitigation, rating conversions and 10-health-per-Stamina come from the Forever beta client, build 1.60.1.69876. Base attributes and the crit, dodge, attack power and regen formulas are still WoW Classic 1.12 values for a level " + lv + " " + esc(ctx.raceClass || "") + (ctx.derived ? " (combo new in Forever, derived from " + esc(ctx.derived) + " plus race offsets)" : "") + "." : "Base attributes for this race are unpublished, so formula totals show as ?; bonuses from gear, racials and talents still count.");
      var overNote = t.__over.length ? '<p class="g2-warn">Not counted, above your level ' + lv + ": " + t.__over.map(function (it) { return esc(it.name) + " (needs " + effReq(it).lvl + (effReq(it).est ? ", estimated" : "") + ")"; }).join(", ") + ".</p>" : "";
      return '<div class="gear2" id="gear"><div class="g2-head"><b>Gear</b><span class="g2-count">' + count + " / " + SLOT_KEYS.length + " equipped</span>" +
        '<span class="g2-db">' + wearable + " Forever items to wear so far</span>" +
        (count ? '<button type="button" class="nm-btn ghost" data-gclear="1">Clear gear</button>' : "") + "</div>" +
        '<div class="g2-doll"><div class="g2-col">' + SLOTS.left.map(slotHTML).join("") + "</div>" +
          stageHTML(ctx) +
          '<div class="g2-col">' + SLOTS.right.map(slotHTML).join("") + "</div></div>" +
        '<div class="g2-bottom">' + SLOTS.bottom.map(slotHTML).join("") + "</div>" +
        consumesHTML(ctx) +
        '<div class="g2-info"><div class="g2-stats">' + overNote + '<div class="gst-g"><h6>Attributes</h6>' + attrs + "</div>" +
            (pools ? '<div class="gst-g"><h6>Resources</h6>' + pools + "</div>" : "") +
            '<div class="gst-g"><h6>Offense</h6>' + off + "</div>" +
            '<div class="gst-g"><h6>Defense</h6>' + def + "</div>" +
            (resHTML ? '<div class="gst-g"><h6>Resistances</h6>' + resHTML + "</div>" : "") +
            '<div class="gst-g gst-rf"><h6>Reflect</h6>' + rfHTML + "</div>" +
            '<div class="gst-g gst-px"><h6>Procs and on-use</h6>' + pxHTML + "</div>" +
            '<p class="g2-note">' + note + "</p></div>" +
          (rx ? '<div class="g2-rx"><div class="g2-rx-h"><h6>Racials</h6><button type="button" class="g2-rx-link" data-goto-race="1">Change race</button></div>' + rx + "</div>" : "") +
        "</div></div>";
    }
    var ANIMS = [["Stand", "Idle"], ["Walk", "Walk"], ["Run", "Run"], ["Dance", "Dance"], ["Wave", "Wave"], ["Cheer", "Cheer"], ["Laugh", "Laugh"],
      ["Roar", "Roar"], ["Flex", "Flex"], ["ReadySpell", "Ready"], ["CastSpell", "Cast"], ["Attack", "Attack"], ["SitGround", "Sit"]];
    function stageHTML(ctx) {
      var g = ctx.gender === "f" ? "f" : "m";
      return '<div class="g2-stage">' +
        '<div class="g2-model" data-model="' + esc(ctx.modelKey || "") + '">' +
          '<div class="g2-fallback">' + (ctx.raceIcon ? img(ctx.raceIcon, "g2-race") : "") + (ctx.classIcon ? img(ctx.classIcon, "g2-class") : "") + "</div></div>" +
        '<div class="g2-hero">' + (ctx.classIcon ? img(ctx.classIcon, "g2-class") : "") +
          '<span class="g2-who"><b style="color:' + esc(ctx.classColour || "#fff") + '">' + esc(ctx.name || "Unnamed") + "</b><em>" + esc(ctx.line || "") + "</em></span></div>" +
        '<div class="g2-sex" role="group" aria-label="Body">' +
          '<button type="button" data-gender="m"' + (g === "m" ? ' class="on" aria-pressed="true"' : ' aria-pressed="false"') + ">Male</button>" +
          '<button type="button" data-gender="f"' + (g === "f" ? ' class="on" aria-pressed="true"' : ' aria-pressed="false"') + ">Female</button></div>" +
        '<button type="button" class="g2-zoom" data-m3d-zoom="1" title="Close-up (or double-click the model)">Close-up</button>' +
        (ctx.standIn ? '<p class="g2-standin">Stand-in model: a recoloured blood elf until Skyborne models are in the client.</p>' : "") +
        '<div class="g2-anims" role="group" aria-label="Animation">' + ANIMS.map(function (a) {
          return '<button type="button" data-anim="' + a[0] + '"' + (a[0] === "Stand" ? ' class="on"' : "") + ">" + a[1] + "</button>";
        }).join("") + "</div>" +
        '<p class="g2-drag mouse-only">Drag to turn</p><p class="g2-drag touch-only">Swipe sideways to turn</p>' +
      "</div>";
    }
    // ---- The gear picker: every wearable item for the slot, filtered, weighted and paged ----
    var PF_DEF = { at: [], fx: [], ms: "", stat: "", qual: "", rlo: "", rhi: "", ilo: "", ihi: "", src: "", nw: false, upto: true, any: false, cl: false, sort: "score", preset: "", more: false };
    var PF = (function () {
      var o = {}, saved = lsGet("forge-pick") || {};
      Object.keys(PF_DEF).forEach(function (k) { o[k] = saved[k] !== undefined ? saved[k] : PF_DEF[k]; });
      if (!Array.isArray(o.at)) o.at = [];
      if (!Array.isArray(o.fx)) o.fx = [];
      o.q = ""; o.shown = 60; o.slot = "";
      return o;
    })();
    function savePF() { var o = {}; Object.keys(PF_DEF).forEach(function (k) { o[k] = PF[k]; }); lsSet("forge-pick", o); }
    var CUSTOM = lsGet("forge-weights") || null;
    if (CUSTOM && (CUSTOM.reflectHit || CUSTOM.reflectBlock)) { // reflect per hit and per block became one Reflect
      if (!CUSTOM.reflect) CUSTOM.reflect = CUSTOM.reflectHit || CUSTOM.reflectBlock;
      delete CUSTOM.reflectHit; delete CUSTOM.reflectBlock; lsSet("forge-weights", CUSTOM);
    }
    // Weight presets: the consumable wants per spec, read as gear weights; armor is per point, so it weighs less.
    function presets() {
      var out = [], byCls = WANT[CLS] || {};
      function fromWant(str, tank) {
        var w = {};
        String(str).split(" ").forEach(function (p) {
          var kv = p.split(":"), k = kv[0], v = +kv[1];
          if (k === "health") return;
          if (k === "armor") { w.armor = r2(v * 0.04); return; }
          w[k] = v;
        });
        if (tank) { w.defense = w.defense || 2; w.dodge = w.dodge || 6; w.parry = w.parry || 6; if (CLS === "WARRIOR" || CLS === "PALADIN") { w.blockChance = w.blockChance || 5; w.blockValue = w.blockValue || 1; } }
        return w;
      }
      Object.keys(byCls).forEach(function (k) {
        out.push({ id: k === "*" ? "class" : k.toLowerCase(), label: k === "*" ? CLS.charAt(0) + CLS.slice(1).toLowerCase() : k, w: fromWant(byCls[k], k === "Protection") });
      });
      // Proc damage per second, weighed like 14 attack power per point of DPS (Classic rule: 14 AP = 1 DPS).
      out.forEach(function (p) {
        if (!/^(retribution|arms|fury|enhancement|feral)$/.test(p.id) && !(p.id === "class" && (CLS === "ROGUE" || CLS === "HUNTER"))) return;
        p.w.procDps = Math.round(14 * (p.w.attackPower || 2));
      });
      if (CLS === "PALADIN") out.push({ id: "reflect", label: "Reflect tank", w: { stamina: 3, armor: 0.12, defense: 2, blockValue: 2, blockChance: 5, reflect: 10, strength: 1.5, holy: 1, dodge: 4, parry: 4 } });
      out.push({ id: "custom", label: "Custom", w: CUSTOM || {} });
      return out;
    }
    var SPEC = "";
    function currentPreset() {
      var ps = presets(), want = PF.preset, p = ps.filter(function (x) { return x.id === want; })[0];
      if (!p && SPEC) p = ps.filter(function (x) { return SPEC.indexOf(x.label) === 0; })[0];
      return p || ps[0];
    }
    function score(it, w) { // a bow's or thrown weapon's procs only count for Hunters, who shoot all fight
      var s = 0; Object.keys(w).forEach(function (k) { if (w[k] && !(k === "procDps" && RANGED[it.slot] && CLS !== "HUNTER")) s += w[k] * statVal(it, k); }); return s; }
    function pickSet(name, v) {
      var reset = true;
      if (name === "at" || name === "fx") { var arr = PF[name], i = arr.indexOf(v); if (i === -1) arr.push(v); else arr.splice(i, 1); }
      else if (name === "ms" || name === "qual") PF[name] = PF[name] === v ? "" : v;
      else if (name === "nw" || name === "upto" || name === "any" || name === "cl") PF[name] = !PF[name];
      else if (name === "more") { PF.shown += 60; reset = false; }
      else if (name === "moreopen") { PF.more = !PF.more; reset = false; }
      else if (name === "q") PF.q = String(v || "");
      else if (name === "reset") { Object.keys(PF_DEF).forEach(function (k) { PF[k] = Array.isArray(PF_DEF[k]) ? [] : PF_DEF[k]; }); PF.q = ""; }
      else if (name.indexOf("w:") === 0) {
        CUSTOM = CUSTOM || {};
        var n = parseFloat(v);
        if (isFinite(n) && n) CUSTOM[name.slice(2)] = n; else delete CUSTOM[name.slice(2)];
        lsSet("forge-weights", CUSTOM); PF.preset = "custom";
      } else if (name === "preset") {
        PF.preset = v;
        if (v === "custom" && !CUSTOM) { CUSTOM = {}; var cp = presets().filter(function (x) { return x.id !== "custom"; })[0]; if (cp) Object.keys(cp.w).forEach(function (k) { CUSTOM[k] = cp.w[k]; }); lsSet("forge-weights", CUSTOM); }
      }
      else if (PF_DEF.hasOwnProperty(name)) PF[name] = String(v == null ? "" : v);
      if (reset) PF.shown = 60;
      savePF();
    }
    function statOptions(sel, first) {
      return (first || "") + STATS.map(function (g) {
        return '<optgroup label="' + esc(g[0]) + '">' + g[1].map(function (x) { return '<option value="' + x[0] + '"' + (sel === x[0] ? " selected" : "") + ">" + esc(x[1]) + "</option>"; }).join("") + "</optgroup>";
      }).join("");
    }
    function pickerHTML(slotKey) {
      if (PF.slot !== slotKey) { PF.slot = slotKey; PF.q = ""; PF.shown = 60; }
      var def = [].concat(SLOTS.left, SLOTS.right, SLOTS.bottom).filter(function (s) { return s[0] === slotKey; })[0];
      var acc = ACCEPT[slotKey] || [], clsName = CLS ? CLS.charAt(0) + CLS.slice(1).toLowerCase() : "";
      // Proficiency follows the level you browse at: every level means level 60 rules (plate for a paladin).
      var profLvl = PF.upto ? LEVEL : 60;
      var pool = items.filter(function (it) {
        if (acc.indexOf(it.slot) === -1) return false;
        if (!PF.any && CLS && !canUse(CLS, it, profLvl)) return false;
        if (!PF.any && it.cls && clsName && it.cls.indexOf(clsName) === -1) return false;
        return true;
      });
      var P = currentPreset(), W = P.w, sortKey = PF.sort || "score";
      var ql = PF.q.toLowerCase().split(/\s+/).filter(Boolean);
      var rlo = +PF.rlo || 0, rhi = +PF.rhi || 0, ilo = +PF.ilo || 0, ihi = +PF.ihi || 0;
      var hasArmor = pool.some(function (it) { return armorType(it); });
      // Armor pills are saved across slots; only the types this slot can hold filter it (Shield for the off hand).
      var ARM = slotKey === "offhand" ? ["Shield"] : ["Cloth", "Leather", "Mail", "Plate"];
      var AT = PF.at.filter(function (a) { return ARM.indexOf(a) !== -1; });
      var list = pool.filter(function (it) {
        var er = effReq(it).lvl;
        if (PF.upto && er > LEVEL) return false;
        if (rlo && er < rlo) return false;
        if (rhi && er > rhi) return false;
        if (ilo && (+it.itemLevel || 0) < ilo) return false;
        if (ihi && (+it.itemLevel || 0) > ihi) return false;
        if (PF.qual && it.quality !== PF.qual) return false;
        if (PF.nw && !(it.nw || it.ft === "new")) return false;
        // Classic items Forever has not shown yet: only the ones a Forever loot record lists, unless asked for
        if (it.est === "classic" && !PF.cl && !hasSource(it)) return false;
        if (PF.src === "known" && !hasSource(it)) return false;
        if (PF.src === "est" && hasSource(it)) return false;
        if (AT.length && AT.indexOf(armorType(it)) === -1) return false; // weapons and held items have no armor type: a pill shows armor only
        if (PF.ms) {
          var s = istats(it), m = mainStat(it);
          if (PF.ms === "sta") { if (m || !s.stamina) return false; }
          else if (PF.ms === "spirit") { if (!s.spirit || s.spirit < Math.max(s.strength || 0, s.agility || 0, s.intellect || 0)) return false; }
          else if (m !== PF.ms) return false;
        }
        if (PF.stat && statVal(it, PF.stat) <= 0) return false;
        if (PF.fx.length && !PF.fx.some(function (k) { return hasFx(it, k); })) return false;
        // sorting by a stat lists the items that have it, best first
        if (sortKey !== "score" && sortKey !== "ilvl" && sortKey !== "req" && statVal(it, sortKey) <= 0) return false;
        if (ql.length) {
          var hay = (it.name + " " + (it.type || "") + " " + (it.source || "") + " " + (it.effects || []).join(" ") + " " + (it.setName || "") + " " +
            (it.drops || []).map(function (d) { return d[1] + " " + d[0]; }).join(" ") + " " + (it.quests || []).map(function (q) { return q[0] + " " + q[1]; }).join(" ")).toLowerCase();
          for (var i = 0; i < ql.length; i++) if (hay.indexOf(ql[i]) === -1) return false;
        }
        return true;
      }).map(function (it) { return { it: it, sc: score(it, W) }; });
      function key(x) {
        if (sortKey === "score") return x.sc;
        if (sortKey === "ilvl") return +x.it.itemLevel || 0;
        if (sortKey === "req") return effReq(x.it).lvl;
        return statVal(x.it, sortKey);
      }
      list.sort(function (a, b) {
        return (key(b) - key(a)) || (b.sc - a.sc) || ((+b.it.itemLevel || 0) - (+a.it.itemLevel || 0)) || QUALITY.indexOf(b.it.quality) - QUALITY.indexOf(a.it.quality) || a.it.name.localeCompare(b.it.name);
      });
      var cur = eq()[slotKey], quals = QUALITY.filter(function (x) { return pool.some(function (it) { return it.quality === x; }); });
      var hl = sortKey !== "score" && sortKey !== "ilvl" && sortKey !== "req" ? sortKey : PF.stat;
      function pill(name, v, label, on, tip) {
        return '<button type="button" class="gp-p' + (on ? " on" : "") + '" data-pf="' + name + '" data-v="' + esc(v) + '" aria-pressed="' + (on ? "true" : "false") + '"' + (tip ? ' data-tip="' + attr(tip) + '"' : "") + ">" + esc(label) + "</button>";
      }
      var nFilters = (PF.rlo ? 1 : 0) + (PF.rhi ? 1 : 0) + (PF.ilo ? 1 : 0) + (PF.ihi ? 1 : 0) + (PF.src ? 1 : 0);
      var shownList = list.slice(0, PF.shown);
      var rows = shownList.map(function (x) {
        var it = x.it, er = effReq(it), lock = er.lvl > LEVEL, ch = chips(it, hl).slice(0, 6), known = hasSource(it);
        var srcTip = known ? (it.drops && it.drops.length ? "Drops from " + it.drops[0][1] + ", " + it.drops[0][0] : "Quest reward: " + it.quests[0][0]) : (estimateSource(it) || "Source not seen yet");
        var meta = [slotLabel(it.slot), it.type && it.type !== slotLabel(it.slot) ? it.type : "", it.dps ? it.dps + " dps" : "", it.armor ? it.armor + " armor" : "", it.block ? it.block + " block" : "",
          it.itemLevel ? "ilvl " + it.itemLevel : "", "req " + er.lvl + (er.est ? "~" : "")].filter(Boolean).join(" · ");
        return '<button type="button" class="gp-row' + (cur === it.id ? " on" : "") + (lock ? " lock" : "") + '" data-gpick="' + attr(it.id) + '" data-tipcls="itemtip" data-tip="' +
            attr(itemTip(it) + (lock ? '<span class="it-warn">Needs level ' + er.lvl + (er.est ? " (estimated)" : "") + ": the stat panel will not count it until you are.</span>" : "")) + '">' +
          '<span class="gp-ic q-' + esc(it.quality || "common") + '">' + img(it.icon) + "</span>" +
          '<span class="gp-t"><b class="q-' + esc(it.quality || "common") + '">' + esc(it.name) + (it.est === "classic" ? ' <i class="gp-est">Classic stats</i>' : "") + "</b><em>" + esc(meta) + "</em></span>" +
          '<span class="gp-s">' + (ch.length ? ch.map(function (c) { return "<i" + (c[2] ? ' class="hl"' : "") + ">" + esc(c[1]) + "</i>"; }).join("") : "<i>" + esc(((it.effects || [])[0] || "").slice(0, 60)) + "</i>") + "</span>" +
          '<span class="gp-sc" title="Weighted score (' + esc(P.label) + ')">' + (x.sc ? Math.round(x.sc) : "–") + "</span>" +
          '<span class="gp-src ' + (known ? "k-known" : "k-est") + '" title="' + attr(srcTip) + '">' + (known ? (it.drops && it.drops.length ? "Drop" : "Quest") : "Est.") + "</span></button>";
      }).join("");
      var left = list.length - shownList.length;
      var wEditor = P.id === "custom" ? '<div class="gp-w">' + STATS.map(function (g) {
          return g[1].map(function (x) { return '<label><span>' + esc(x[1]) + '</span><input type="number" step="0.1" inputmode="decimal" data-pfs="w:' + x[0] + '" value="' + (W[x[0]] != null ? esc(W[x[0]]) : "") + '" placeholder="0"></label>'; }).join("");
        }).join("") + "</div>" : '<p class="gp-wtxt">' + esc(P.label) + " weights: " + esc(Object.keys(W).filter(function (k) { return W[k]; }).map(function (k) { return (STATBY[k] ? STATBY[k][1] : k) + " " + W[k]; }).join(", ")) + ". Pick Custom to set your own.</p>";
      return '<div class="gpick"><div class="gp-top">' + img(def[2], "gp-slotic") + "<b>" + esc(def[1]) + '</b><span class="gp-n">' + list.length + " of " + pool.length + (PF.any ? " items, any class" : " for your class") + (PF.upto ? ", up to level " + LEVEL : ", every level") + "</span>" +
        '<button type="button" class="gp-x" data-gpx="1" aria-label="Close">&times;</button></div>' +
        '<div class="gp-bar"><input type="search" data-pfi="q" placeholder="Search name, effect, dungeon, boss" value="' + esc(PF.q) + '" aria-label="Search items">' +
          '<div class="gp-line">' +
            (hasArmor ? '<span class="gp-grp" role="group" aria-label="Armor type">' + ARM.map(function (a) { return pill("at", a, a, PF.at.indexOf(a) !== -1); }).join("") + "</span>" : "") +
            '<span class="gp-grp" role="group" aria-label="Main stat">' + [["strength", "Str"], ["agility", "Agi"], ["intellect", "Int"], ["sta", "Sta only"], ["spirit", "Spi"]].map(function (m) {
              return pill("ms", m[0], m[1], PF.ms === m[0], m[0] === "sta" ? "Stamina with no Strength, Agility or Intellect" : m[0] === "spirit" ? "Spirit is its biggest attribute" : "Main stat: the largest of Strength, Agility and Intellect");
            }).join("") + "</span></div>" +
          '<div class="gp-line"><span class="gp-grp" role="group" aria-label="Effects">' + FXPILLS.map(function (f) { return pill("fx", f[0], f[1], PF.fx.indexOf(f[0]) !== -1, f[2]); }).join("") + "</span></div>" +
          '<div class="gp-line gp-sel">' +
            '<label><span>Sort</span><select data-pfs="sort">' + statOptions(sortKey, '<option value="score"' + (sortKey === "score" ? " selected" : "") + ">Score (weights)</option><option value=\"ilvl\"" + (sortKey === "ilvl" ? " selected" : "") + ">Item level</option><option value=\"req\"" + (sortKey === "req" ? " selected" : "") + ">Required level</option>") + "</select></label>" +
            '<label><span>Has stat</span><select data-pfs="stat">' + statOptions(PF.stat, '<option value="">Any</option>') + "</select></label>" +
            '<label><span>Weights</span><select data-pfs="preset">' + presets().map(function (p) { return '<option value="' + p.id + '"' + (p.id === P.id ? " selected" : "") + ">" + esc(p.label) + "</option>"; }).join("") + "</select></label></div>" +
          '<div class="gp-quals">' + quals.map(function (x) { return '<button type="button" class="gp-q q-' + x + (PF.qual === x ? " on" : "") + '" data-pf="qual" data-v="' + x + '">' + x + "</button>"; }).join("") + "</div>" +
          '<div class="gp-line">' + pill("upto", "1", "Only up to level " + LEVEL, PF.upto, "Hides items whose required level is above yours. Items with no stored requirement use item level - 5, marked ~.") +
            pill("nw", "1", "New in Forever", PF.nw) +
            pill("any", "1", "Any class", PF.any, "Classic proficiencies assumed; Forever may differ. Toggle to browse every armor and weapon type.") +
            pill("cl", "1", "Classic items not seen in Forever", PF.cl, "Items Forever's data has an id for but nobody has seen in Forever yet, with their WoW Classic stats. Forever may have changed or removed them.") +
            '<button type="button" class="gp-p gp-morebtn' + (PF.more ? " on" : "") + '" data-pf="moreopen" data-v="1" aria-expanded="' + (PF.more ? "true" : "false") + '">More filters' + (nFilters ? " (" + nFilters + ")" : "") + "</button>" +
            '<button type="button" class="gp-p gp-reset" data-pf="reset" data-v="1">Reset</button></div>' +
          (PF.more ? '<div class="gp-moref"><div class="gp-line gp-sel">' +
            '<label><span>Required level</span><input type="number" min="1" max="60" data-pfs="rlo" value="' + esc(PF.rlo) + '" placeholder="from"><input type="number" min="1" max="60" data-pfs="rhi" value="' + esc(PF.rhi) + '" placeholder="to"></label>' +
            '<label><span>Item level</span><input type="number" min="1" max="100" data-pfs="ilo" value="' + esc(PF.ilo) + '" placeholder="from"><input type="number" min="1" max="100" data-pfs="ihi" value="' + esc(PF.ihi) + '" placeholder="to"></label>' +
            '<label><span>Source</span><select data-pfs="src"><option value="">Any</option><option value="known"' + (PF.src === "known" ? " selected" : "") + ">Known drop or quest</option><option value=\"est\"" + (PF.src === "est" ? " selected" : "") + ">Estimated source</option></select></label></div>" +
            wEditor + "</div>" : "") +
        "</div>" +
        '<div class="gp-list">' + (list.length ? rows + (left > 0 ? '<button type="button" class="gp-more" data-pf="more" data-v="1">Show ' + Math.min(60, left) + " more <i>(" + left + " left)</i></button>" : "")
          : '<div class="gp-empty">' + img(def[2]) + "<b>Nothing matches.</b><span>" + (pool.length ? "Loosen a filter, or press Reset." : "No " + esc(def[1].toLowerCase()) + " items for this class in the database yet.") + "</span></div>") + "</div>" +
        '<div class="gp-foot"><span class="gp-legend"><i class="gp-src k-known">Drop</i> seen dropping or rewarded <i class="gp-src k-est">Est.</i> source estimated from levels; req ~ is estimated</span>' +
          (cur ? '<button type="button" class="nm-btn ghost" data-gpclear="1">Unequip</button>' : "") + "</div></div>";
    }
    // ---- Enchant picker for one slot ----
    function enchantHTML(slotKey) {
      var it = byId[eq()[slotKey]], cur = ench()[slotKey], list = enchantsFor(slotKey);
      var def = [].concat(SLOTS.left, SLOTS.right, SLOTS.bottom).filter(function (s) { return s[0] === slotKey; })[0];
      function line(en) {
        var bits = [];
        [].concat(en.rf || []).forEach(function (e) {
          bits.push((e.lo != null && e.hi != null ? e.lo + "–" + e.hi : e.v) + " " + (e.s || "Physical") + " damage " + (e.k === "block" ? "each time you block" : "to a melee attacker each hit"));
        });
        Object.keys(en.stats || {}).forEach(function (k) { bits.push("+" + en.stats[k] + " " + (STATBY[k] ? STATBY[k][1] : k)); });
        return bits.join(", ");
      }
      return '<div class="gpick"><div class="gp-top">' + img("inv_misc_enchantedscroll", "gp-slotic") + "<b>Enchant: " + esc(def ? def[1] : slotKey) + '</b><span class="gp-n">' + (it ? esc(it.name) : "") + "</span>" +
        '<button type="button" class="gp-x" data-gpx="1" aria-label="Close">&times;</button></div>' +
        '<div class="gp-list">' + list.map(function (en) {
          var ok = enchantFits(en, it), src = byId[en.item];
          return '<button type="button" class="gp-row gp-erow' + (cur === en.id ? " on" : "") + (ok ? "" : " lock") + '" data-gench-pick="' + esc(en.id) + '"' + (ok ? "" : " disabled") +
              (src ? ' data-tipcls="itemtip" data-tip="' + attr(itemTip(src)) + '"' : "") + ">" +
            '<span class="gp-ic q-' + esc((src && src.quality) || "common") + '">' + img(enchantIcon(en)) + "</span>" +
            '<span class="gp-t"><b class="q-' + esc((src && src.quality) || "common") + '">' + esc(en.name) + "</b><em>" + esc(line(en)) + "</em></span>" +
            '<span class="gp-s"><i>' + esc(en.skill && en.skill[0] ? en.skill[0] + (en.skill[1] ? " " + en.skill[1] : "") : "") + "</i>" + (ok ? "" : "<i>Needs a " + esc(String(en.needs).toLowerCase()) + "</i>") + "</span>" +
            '<span class="gp-sc"></span>' + (([].concat(en.rf || [])[0] || {}).src === "text" ? '<span class="gp-src k-est" title="Read from the tooltip text">Text</span>' : '<span class="gp-src k-known" title="Numbers from the client spell tables">Client</span>') + "</button>";
        }).join("") + (list.length ? "" : '<div class="gp-empty"><b>No enchants listed for this slot yet.</b></div>') + "</div>" +
        '<div class="gp-foot"><span class="gp-legend">' + esc(EXTRA.enchantNote || "") + "</span>" + (cur ? '<button type="button" class="nm-btn ghost" data-gench-clear="1">Remove enchant</button>' : "") + "</div></div>";
    }
    function toggleReflect(k) { RFT[k] = !rftOn(k); lsSet("forge-rf", RFT); }
    // Gear codes: slot index in base 36, then the item id. raw carries tokens this database cannot read yet
    // (the full database is still loading), so a boot render never strips a shared link.
    function encode(E, raw) {
      var carry = {};
      String(raw || "").split("~").forEach(function (part) { var m = /^([0-9a-z])([A-Za-z0-9_-]+)$/.exec(part); if (m && !byId[m[2]]) carry[parseInt(m[1], 36)] = part; });
      return SLOT_KEYS.map(function (k, i) {
        if (E[k] != null && byId[E[k]] && /^[A-Za-z0-9_-]+$/.test(E[k])) return i.toString(36) + E[k];
        return E[k] == null && carry[i] ? carry[i] : null;
      }).filter(Boolean).join("~");
    }
    function decode(seg) {
      var E = {};
      String(seg || "").split("~").forEach(function (part) {
        var m = /^([0-9a-z])([A-Za-z0-9_-]+)$/.exec(part);
        if (!m) return;
        var k = SLOT_KEYS[parseInt(m[1], 36)];
        if (k && byId[m[2]] && (ACCEPT[k] || []).indexOf(byId[m[2]].slot) !== -1) E[k] = m[2];
      });
      if (E.mainhand && byId[E.mainhand].slot === "two-hand") delete E.offhand;
      return E;
    }
    function enchantOK(enId, it) { var en = enchantById(enId); return !!en && enchantFits(en, it); }
    return { html: html, pickerHTML: pickerHTML, enchantHTML: enchantHTML, pickSet: pickSet, enchantOK: enchantOK, setSpec: function (s, cls, lv) { SPEC = s || ""; if (cls) CLS = cls; if (lv) LEVEL = lv; },
      itemTip: itemTip, consumeInfo: consumeInfo, encode: encode, decode: decode, byId: byId, count: items.length, SLOT_KEYS: SLOT_KEYS, canUse: canUse,
      toggleReflect: toggleReflect, enchantById: enchantById, enchantsFor: enchantsFor };
  };
  // Optional data files (plan/enchants.json, plan/reflect.json, codex/loot.json) land here when they load.
  window.ForgeGear.extras = function (o) {
    o = o || {};
    if (o.enchants && Array.isArray(o.enchants.enchants) && o.enchants.enchants.length) { EXTRA.enchants = o.enchants.enchants; EXTRA.enchantNote = o.enchants.note || ""; }
    if (o.reflect && o.reflect.classes) EXTRA.reflect = o.reflect;
    if (o.dungeons && o.dungeons.length) EXTRA.dungeons = o.dungeons;
    return EXTRA;
  };
  window.ForgeGear.encodeEnch = function (map) {
    return SLOT_KEYS.map(function (k, i) { var v = map && map[k]; return v && /^[A-Za-z0-9_-]+$/.test(v) ? i.toString(36) + v : null; }).filter(Boolean).join("~");
  };
  window.ForgeGear.decodeEnch = function (seg) {
    var o = {};
    String(seg || "").split("~").forEach(function (part) { var m = /^([0-9a-z])([A-Za-z0-9_-]+)$/.exec(part); if (m && SLOT_KEYS[parseInt(m[1], 36)]) o[SLOT_KEYS[parseInt(m[1], 36)]] = m[2]; });
    return o;
  };
  window.ForgeGear.item = window.ForgeItem;
})();
