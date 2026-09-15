/* ForgeGear: the inspect-style gear step. Paperdoll slots, a picker per slot,
 * WoW-style item tooltips and a stat panel that totals what is equipped.
 * Items come from plan/items.json: only items Forever footage or previews have shown. */
(function () {
  "use strict";
  var CDN = "https://wow.zamimg.com/images/wow/icons/large/";
  function esc(s) { return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
  function attr(v) { return esc(v); }
  function img(n, cls) { var src = n && n.indexOf("/") !== -1 ? n : CDN + (n || "inv_misc_questionmark") + ".jpg"; return '<img class="' + (cls || "") + '" src="' + esc(src) + '" alt="" loading="lazy" onerror="this.onerror=null;this.src=\'' + CDN + 'inv_misc_questionmark.jpg\'">'; }

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
  var STAT_GROUPS = [
    ["Attributes", [["strength", "Strength"], ["agility", "Agility"], ["stamina", "Stamina"], ["intellect", "Intellect"], ["spirit", "Spirit"]]],
    ["Offense", [["attackPower", "Attack Power"], ["spellPower", "Spell Power"], ["healing", "Bonus Healing"], ["hit", "Hit %"], ["crit", "Crit %"], ["expertise", "Expertise"], ["weaponSkill", "Weapon Skill"]]],
    ["Defense", [["armor", "Armor"], ["defense", "Defense"], ["mp5", "Mana per 5"]]]
  ];
  var STAT_LINE = { strength: "Strength", agility: "Agility", stamina: "Stamina", intellect: "Intellect", spirit: "Spirit" };
  var QUALITY = ["poor", "common", "uncommon", "rare", "epic", "legendary"];

  window.ForgeGear = function (opts) {
    var items = (opts.items && Array.isArray(opts.items.items)) ? opts.items.items : [];
    var byId = {}, ALLSLOTS = [].concat.apply([], Object.keys(ACCEPT).map(function (k) { return ACCEPT[k]; }));
    var wearable = items.filter(function (it) { return ALLSLOTS.indexOf(it.slot) !== -1; }).length;
    items.forEach(function (it) { byId[it.id] = it; });

    function eq() { return opts.get() || {}; }
    function itemTip(it) {
      if (!it) return "";
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
      [["attackPower", "Equip: +%s Attack Power.", /attack power/i], ["spellPower", "Equip: Increases damage and healing done by magical spells and effects by up to %s.", /damage and healing/i],
        ["healing", "Equip: Increases healing done by up to %s.", /increases healing/i], ["spellDamage", "Equip: Increases damage done by magical spells and effects by up to %s.", /spell|magical/i],
        ["hit", "Equip: Improves your chance to hit by %s%.", /chance to hit/i], ["crit", "Equip: Improves your chance to get a critical strike by %s%.", /critical strike/i],
        ["expertise", "Equip: Reduces chance to be Dodged or Parried by %s%.", /dodged or parried|expertise/i], ["weaponDamage", "Equip: +%s Weapon Damage.", /weapon damage/i],
        ["mp5", "Equip: Restores %s mana per 5 sec.", /mana per 5/i], ["defense", "Equip: Increased Defense +%s.", /defense/i], ["spellPiercing", "Equip: Your spells pierce %s Magical Resistances.", /pierce/i]]
        .forEach(function (x) {
          if (!s[x[0]]) return;
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
      if (it.reqLevel) L.push('<span class="it-l">Requires Level ' + esc(it.reqLevel) + "</span>");
      if (it.itemLevel) L.push('<span class="it-y">Item Level ' + esc(it.itemLevel) + "</span>");
      if (it.source) L.push('<span class="it-src">' + esc(it.source) + "</span>");
      if (it.iconFrom === "placeholder") L.push('<span class="it-conf">Stand-in icon until the real one is seen</span>');
      L.push('<span class="it-conf">' + (it.confidence === "tooltip" ? "Tooltip read from Forever footage" : it.confidence === "partial" ? "Partly seen: some lines never shown" : "Named by Blizzard or previews; no tooltip shown yet") + "</span>");
      return L.join("");
    }
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
      var all = items.filter(function (it) { return it.cat === "consumable"; }).map(function (it) { return { it: it, inf: consumeInfo(it) }; });
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
    var LEVEL = 60;
    function totals() {
      var t = { __c: {} }, E = eq();
      SLOT_KEYS.forEach(function (k) {
        var it = byId[E[k]]; if (!it) return;
        var s = it.stats || {};
        Object.keys(s).forEach(function (x) { if (typeof s[x] === "number") t[x] = (t[x] || 0) + s[x]; });
        if (it.armor) t.armor = (t.armor || 0) + it.armor;
        if (it.block) t.block = (t.block || 0) + it.block;
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
      SLOT_KEYS.forEach(function (k) { var w = byId[E[k]]; if (w) { worn[w.name] = true; if (w.setName && !sets[w.setName]) sets[w.setName] = w; } });
      Object.keys(sets).forEach(function (n) {
        var it = sets[n], have = (it.setPieces || []).filter(function (p) { return worn[p]; }).length;
        (it.setBonuses || []).forEach(function (b) {
          if (have < b[0]) return;
          var s = String(b[1]), m;
          if ((m = /^\+(\d+) (Strength|Agility|Stamina|Intellect|Spirit)\.?$/.exec(s))) out.push([m[2].toLowerCase(), +m[1]]);
          else if ((m = /^\+(\d+) Attack Power\.?$/.exec(s))) out.push(["attackPower", +m[1]]);
          else if ((m = /^Increases healing done by up to (\d+) and damage done by up to (\d+) for all magical spells and effects\.?$/.exec(s))) { out.push(["healing", +m[1]]); out.push(["spellDamage", +m[2]]); }
          else if ((m = /^Increases damage and healing done by magical spells and effects by up to (\d+)\.?$/.exec(s))) out.push(["spellPower", +m[1]]);
        });
      });
      return out;
    }
    function slotHTML(def) {
      var it = byId[eq()[def[0]]];
      var blocked = def[0] === "offhand" && byId[eq().mainhand] && byId[eq().mainhand].slot === "two-hand";
      return '<button type="button" class="gslot' + (it ? " filled q-" + esc(it.quality || "common") : "") + (blocked ? " blocked" : "") + '" data-gslot="' + def[0] + '" data-tip="' +
        attr(it ? itemTip(it) : "<b>" + esc(def[1]) + "</b>" + (blocked ? "Your two-hander fills this." : "Empty. Click to pick an item.")) + '"' + (it ? ' data-tipcls="itemtip"' : "") + ">" +
        '<span class="gs-ic">' + img(it ? it.icon : def[2]) + "</span>" +
        '<span class="gs-t"><em>' + esc(def[1]) + "</em><b>" + (it ? esc(it.name) : "Empty") + "</b></span></button>";
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
      return ["mainhand", "offhand", "ranged"].some(function (k) {
        var it = byId[E[k]]; if (!it || !it.type) return false;
        return w.indexOf(it.type.toLowerCase()) !== -1;
      });
    }
    function row(label, value, tip, on, cls) {
      return '<div class="gst' + (on ? " on" : "") + (cls ? " " + cls : "") + '"' + (tip ? ' data-tip="' + attr("<b>" + esc(label) + "</b>" + tip) + '"' : "") + "><span>" + esc(label) + "</span><b>" + value + "</b></div>";
    }
    function html(ctx) {
      LEVEL = ctx.level || 60;
      var t = totals(), count = SLOT_KEYS.filter(function (k) { return byId[eq()[k]]; }).length;
      var M = racialMods(ctx.racials), base = ctx.base, lv = ctx.level;
      var ATTR = [["strength", "Strength"], ["agility", "Agility"], ["stamina", "Stamina"], ["intellect", "Intellect"], ["spirit", "Spirit"]];
      var attrs = ATTR.map(function (x, i) {
        var b0 = base ? base[i] : null, g = t[x[0]] || 0, pct = M.pct[x[0]] || 0;
        var tot = b0 == null ? null : Math.floor((b0 + g) * (1 + pct / 100));
        var tip = (b0 == null ? "Base value unpublished for this race. " : "Base " + b0 + " at level " + lv + ". ") + "Gear and set bonuses +" + (g - (t.__c[x[0]] || 0)) + "." + (t.__c[x[0]] ? " Consumables +" + t.__c[x[0]] + "." : "") + (pct ? " Racial +" + pct + "%." : "");
        return row(x[1], tot == null ? (g ? "+" + g : "?") : tot + (pct ? '<i class="rx">+' + pct + "%</i>" : ""), tip, tot || g, "");
      }).join("");
      var hm = ctx.baseHM;
      var power = ctx.power || "mana";
      var pools = hm ? row("Base health", Math.round(hm[0] * (1 + (M.pct.health || 0) / 100)) + (M.pct.health ? '<i class="rx">+' + M.pct.health + "%</i>" : ""),
          "WoW Classic 1.12 class base health at level " + lv + ", before Stamina. Forever has not published its own base health or Stamina rate." + (M.pct.health ? " Racial +" + M.pct.health + "% applied." : ""), true, "") +
        (power === "mana" && hm[1] ? row("Base mana", Math.round(hm[1] * (1 + (M.pct.mana || 0) / 100)) + (M.pct.mana ? '<i class="rx">+' + M.pct.mana + "%</i>" : ""),
          "WoW Classic 1.12 class base mana at level " + lv + ", before Intellect. Forever has not published its own." + (M.pct.mana ? " Racial +" + M.pct.mana + "% applied." : ""), true, "") :
          (M.pct[power] ? row("Max " + power, '<i class="rx">+' + M.pct[power] + "%</i>", "Racial bonus to maximum " + power + ".", true, "") : "")) : "";
      if (t.health) pools += row("Bonus health", "+" + t.health, "From consumables" + (t.__c.health !== t.health ? " and gear" : "") + ".", true, "");
      var wc = M.weaponCrit.filter(function (w) { return weaponMatches(w.when); }).reduce(function (a, w) { return a + w.value; }, 0);
      var OFF = [["attackPower", "Attack Power"], ["spellPower", "Spell Power"], ["healing", "Bonus Healing"], ["spellDamage", "Spell Damage"], ["weaponDamage", "Weapon Damage"], ["weaponSkill", "Weapon Skill"]];
      var off = [["hit", "Hit"], ["crit", "Crit"], ["expertise", "Expertise"], ["haste", "Haste"]].map(function (x) {
        var g = t[x[0]] || 0, rr = (M.add[x[0]] || 0) + (x[0] === "crit" ? wc : 0), v = g + rr;
        var tip = "Bonus from gear +" + (g - (t.__c[x[0]] || 0)) + "%." + (t.__c[x[0]] ? " Consumables +" + t.__c[x[0]] + "%." : "") + (rr ? " Racial +" + rr + "%." : "") + (x[0] === "crit" && M.weaponCrit.length ? " " + M.weaponCrit.map(function (w) { return w.from + ": +" + w.value + "% with " + w.when + (weaponMatches(w.when) ? " (active)" : " (no matching weapon)"); }).join(" ") : "");
        return row(x[1], "+" + v + "%", tip + " Base values from attributes are unpublished for Forever.", v, "");
      }).join("") + OFF.map(function (x) { var v = t[x[0]] || 0; return v ? row(x[1], v, "From equipped items and active set bonuses" + (t.__c[x[0]] ? ", including consumables +" + t.__c[x[0]] : "") + ".", true, "") : ""; }).join("");
      var def = row("Armor", "+" + (t.armor || 0), "From equipped items" + (t.__c.armor ? " and consumables +" + t.__c.armor : "") + ". Armor from Agility is unpublished for Forever.", t.armor, "") +
        ((M.add.dodge || t.dodge) ? row("Dodge", "+" + ((M.add.dodge || 0) + (t.dodge || 0)) + "%", "Racial and gear dodge bonuses only. Dodge from Agility is unpublished for Forever.", true, "") : "") +
        ["defense", "block", "mp5", "hp5"].map(function (k) { var v = t[k] || 0; return v ? row({ defense: "Defense", block: "Block", mp5: "Mana per 5", hp5: "Health per 5" }[k], v, "From equipped items and active set bonuses" + (t.__c[k] ? ", including consumables +" + t.__c[k] : "") + ".", true, "") : ""; }).join("");
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
      var note = (base ? "Base attributes, health and mana: WoW Classic 1.12 values for a level " + lv + " " + esc(ctx.raceClass || "") + (ctx.derived ? " (combo new in Forever, derived from " + esc(ctx.derived) + " plus race offsets)" : "") +
        ". Forever has not published its own." : "Base attributes, health and mana for this race are unpublished.") + " Offense and Defense show gear and racial bonuses only.";
      return '<div class="gear2" id="gear"><div class="g2-head"><b>Gear</b><span class="g2-count">' + count + " / " + SLOT_KEYS.length + " equipped</span>" +
        '<span class="g2-db">' + wearable + " Forever items to wear so far</span>" +
        (count ? '<button type="button" class="nm-btn ghost" data-gclear="1">Clear gear</button>' : "") + "</div>" +
        '<div class="g2-doll"><div class="g2-col">' + SLOTS.left.map(slotHTML).join("") + "</div>" +
          stageHTML(ctx) +
          '<div class="g2-col">' + SLOTS.right.map(slotHTML).join("") + "</div></div>" +
        '<div class="g2-bottom">' + SLOTS.bottom.map(slotHTML).join("") + "</div>" +
        consumesHTML(ctx) +
        '<div class="g2-info"><div class="g2-stats"><div class="gst-g"><h6>Attributes</h6>' + attrs + "</div>" +
            (pools ? '<div class="gst-g"><h6>Resources</h6>' + pools + "</div>" : "") +
            '<div class="gst-g"><h6>Offense</h6>' + off + "</div>" +
            '<div class="gst-g"><h6>Defense</h6>' + def + "</div>" +
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
    function pickerHTML(slotKey, q, qual) {
      var def = [].concat(SLOTS.left, SLOTS.right, SLOTS.bottom).filter(function (s) { return s[0] === slotKey; })[0];
      var acc = ACCEPT[slotKey] || [];
      var pool = items.filter(function (it) { return acc.indexOf(it.slot) !== -1; });
      var ql = (q || "").toLowerCase();
      var list = pool.filter(function (it) {
        if (qual && it.quality !== qual) return false;
        if (!ql) return true;
        return (it.name + " " + (it.type || "") + " " + (it.source || "") + " " + (it.effects || []).join(" ")).toLowerCase().indexOf(ql) !== -1;
      }).sort(function (a, b) { return (QUALITY.indexOf(b.quality) - QUALITY.indexOf(a.quality)) || ((b.itemLevel || 0) - (a.itemLevel || 0)) || a.name.localeCompare(b.name); });
      var cur = eq()[slotKey];
      var quals = QUALITY.filter(function (x) { return pool.some(function (it) { return it.quality === x; }); });
      return '<div class="gpick"><div class="gp-top">' + img(def[2], "gp-slotic") + "<b>" + esc(def[1]) + '</b><span class="gp-n">' + pool.length + " known</span>" +
        '<button type="button" class="gp-x" data-gpx="1" aria-label="Close">&times;</button></div>' +
        '<div class="gp-bar"><input type="search" data-gpq="1" placeholder="Search name, effect, source" value="' + esc(q || "") + '">' +
          '<div class="gp-quals">' + quals.map(function (x) { return '<button type="button" class="gp-q q-' + x + (qual === x ? " on" : "") + '" data-gpqual="' + x + '">' + x + "</button>"; }).join("") + "</div></div>" +
        '<div class="gp-list">' + (list.length ? list.map(function (it) {
          var st = it.stats || {}, bits = [];
          Object.keys(st).forEach(function (k) { if (typeof st[k] === "number" && st[k]) bits.push("+" + st[k] + " " + (k === "attackPower" ? "AP" : k === "spellPower" ? "SP" : k.slice(0, 3))); });
          return '<button type="button" class="gp-row' + (cur === it.id ? " on" : "") + '" data-gpick="' + attr(it.id) + '" data-tipcls="itemtip" data-tip="' + attr(itemTip(it)) + '">' +
            '<span class="gp-ic q-' + esc(it.quality || "common") + '">' + img(it.icon) + "</span>" +
            '<span class="gp-t"><b class="q-' + esc(it.quality || "common") + '">' + esc(it.name) + "</b><em>" + esc([slotLabel(it.slot), it.type, it.itemLevel ? "ilvl " + it.itemLevel : ""].filter(Boolean).join(" · ")) + "</em></span>" +
            '<span class="gp-s">' + esc(bits.slice(0, 4).join("  ") || ((it.effects || [])[0] || "").slice(0, 48)) + "</span>" +
            '<span class="gp-conf c-' + esc(it.confidence || "mention") + '" title="' + (it.confidence === "tooltip" ? "Tooltip seen" : it.confidence === "partial" ? "Partly seen" : "Named only") + '"></span></button>';
        }).join("") : '<div class="gp-empty">' + img(def[2]) + "<b>No Forever " + esc(def[1].toLowerCase()) + " items shown yet.</b><span>The beta opens September 17; items land here as soon as they are seen in the client.</span></div>") + "</div>" +
        (cur ? '<div class="gp-foot"><button type="button" class="nm-btn ghost" data-gpclear="1">Unequip</button></div>' : "") + "</div>";
    }
    function encode(E) {
      return SLOT_KEYS.map(function (k, i) { return E[k] != null && byId[E[k]] && /^[A-Za-z0-9_-]+$/.test(E[k]) ? i.toString(36) + E[k] : null; }).filter(Boolean).join("~");
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
    return { html: html, pickerHTML: pickerHTML, itemTip: itemTip, consumeInfo: consumeInfo, encode: encode, decode: decode, byId: byId, count: items.length, SLOT_KEYS: SLOT_KEYS };
  };
})();
