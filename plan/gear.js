/* ForgeGear: the inspect-style gear step. Paperdoll slots, a picker per slot,
 * WoW-style item tooltips and a stat panel that totals what is equipped.
 * Items come from plan/items.json: only items Forever footage or previews have shown. */
(function () {
  "use strict";
  var CDN = "https://wow.zamimg.com/images/wow/icons/large/";
  function esc(s) { return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
  function attr(v) { return esc(v); }
  function img(n, cls) { return '<img class="' + (cls || "") + '" src="' + CDN + (n || "inv_misc_questionmark") + '.jpg" alt="" loading="lazy" onerror="this.onerror=null;this.src=\'' + CDN + 'inv_misc_questionmark.jpg\'">'; }

  var SLOTS = {
    left: [["head", "Head", "inventoryslot_head"], ["neck", "Neck", "inventoryslot_neck"], ["shoulder", "Shoulders", "inventoryslot_shoulder"],
      ["back", "Back", "inventoryslot_chest"], ["chest", "Chest", "inventoryslot_chest"], ["wrist", "Wrists", "inventoryslot_wrists"]],
    right: [["hands", "Hands", "inventoryslot_hands"], ["waist", "Waist", "inventoryslot_waist"], ["legs", "Legs", "inventoryslot_legs"], ["feet", "Feet", "inventoryslot_feet"],
      ["finger1", "Finger", "inventoryslot_finger"], ["finger2", "Finger", "inventoryslot_finger"], ["trinket1", "Trinket", "inventoryslot_trinket"], ["trinket2", "Trinket", "inventoryslot_trinket"]],
    bottom: [["mainhand", "Main Hand", "inventoryslot_mainhand"], ["offhand", "Off Hand", "inventoryslot_offhand"], ["ranged", "Ranged or Relic", "inventoryslot_ranged"]]
  };
  var ACCEPT = { head: ["head"], neck: ["neck"], shoulder: ["shoulder"], back: ["back"], chest: ["chest"], wrist: ["wrist"], hands: ["hands"],
    waist: ["waist"], legs: ["legs"], feet: ["feet"], finger1: ["finger"], finger2: ["finger"], trinket1: ["trinket"], trinket2: ["trinket"],
    mainhand: ["main-hand", "one-hand", "two-hand"], offhand: ["off-hand", "one-hand"], ranged: ["ranged", "relic", "ammo"] };
  var SLOT_KEYS = [].concat(SLOTS.left, SLOTS.right, SLOTS.bottom).map(function (s) { return s[0]; });
  var STAT_GROUPS = [
    ["Attributes", [["strength", "Strength"], ["agility", "Agility"], ["stamina", "Stamina"], ["intellect", "Intellect"], ["spirit", "Spirit"]]],
    ["Offense", [["attackPower", "Attack Power"], ["spellPower", "Spell Power"], ["healing", "Bonus Healing"], ["hit", "Hit %"], ["crit", "Crit %"], ["expertise", "Expertise"], ["weaponSkill", "Weapon Skill"]]],
    ["Defense", [["armor", "Armor"], ["defense", "Defense"], ["mp5", "Mana per 5"]]]
  ];
  var STAT_LINE = { strength: "Strength", agility: "Agility", stamina: "Stamina", intellect: "Intellect", spirit: "Spirit" };
  var QUALITY = ["poor", "common", "uncommon", "rare", "epic", "legendary"];

  window.ForgeGear = function (opts) {
    var items = (opts.items && opts.items.items) || [];
    var byId = {};
    items.forEach(function (it) { byId[it.id] = it; });

    function eq() { return opts.get() || {}; }
    function itemTip(it) {
      if (!it) return "";
      var s = it.stats || {}, L = [];
      L.push('<b class="q-' + esc(it.quality || "common") + '">' + esc(it.name) + "</b>");
      if (it.binding) L.push('<span class="it-l">' + (it.binding === "BoP" ? "Binds when picked up" : "Binds when equipped") + "</span>");
      if (it.slot || it.type) L.push('<span class="it-row"><i>' + esc(slotLabel(it.slot)) + "</i><i>" + esc(it.type || "") + "</i></span>");
      if (it.damage) L.push('<span class="it-row"><i>' + esc(it.damage) + " Damage</i><i>" + (it.speed ? "Speed " + Number(it.speed).toFixed(2) : "") + "</i></span>");
      if (it.dps) L.push('<span class="it-l">(' + esc(it.dps) + " damage per second)</span>");
      if (it.armor) L.push('<span class="it-l">' + esc(it.armor) + " Armor</span>");
      Object.keys(STAT_LINE).forEach(function (k) { if (s[k]) L.push('<span class="it-l">+' + esc(s[k]) + " " + STAT_LINE[k] + "</span>"); });
      if (s.resist) Object.keys(s.resist).forEach(function (r) { L.push('<span class="it-l">+' + esc(s.resist[r]) + " " + esc(r.charAt(0).toUpperCase() + r.slice(1)) + " Resistance</span>"); });
      (it.effects || []).forEach(function (e) { L.push('<span class="it-g">' + esc(e) + "</span>"); });
      [["attackPower", "Equip: +%s Attack Power."], ["spellPower", "Equip: Increases damage and healing done by spells by up to %s."], ["healing", "Equip: Increases healing done by up to %s."],
        ["hit", "Equip: Improves your chance to hit by %s%."], ["crit", "Equip: Improves your chance to get a critical strike by %s%."],
        ["expertise", "Equip: Increases your expertise by %s."], ["weaponSkill", "Equip: Increased weapon skill +%s."], ["mp5", "Equip: Restores %s mana per 5 sec."], ["defense", "Equip: Increased Defense +%s."]]
        .forEach(function (x) {
          if (s[x[0]] && !(it.effects || []).some(function (e) { return /Equip:/.test(e) && e.toLowerCase().indexOf(String(s[x[0]])) !== -1; }))
            L.push('<span class="it-g">' + esc(x[1].replace("%s", s[x[0]])) + "</span>");
        });
      if (it.setName) L.push('<span class="it-set">' + esc(it.setName) + "</span>");
      if (it.reqLevel) L.push('<span class="it-l">Requires Level ' + esc(it.reqLevel) + "</span>");
      if (it.itemLevel) L.push('<span class="it-y">Item Level ' + esc(it.itemLevel) + "</span>");
      if (it.source) L.push('<span class="it-src">' + esc(it.source) + "</span>");
      L.push('<span class="it-conf">' + (it.confidence === "tooltip" ? "Tooltip read from Forever footage" : it.confidence === "partial" ? "Partly seen: some lines never shown" : "Named by Blizzard or previews; no tooltip shown yet") + "</span>");
      return L.join("");
    }
    function slotLabel(slot) {
      var m = { "main-hand": "Main Hand", "off-hand": "Off Hand", "one-hand": "One-Hand", "two-hand": "Two-Hand", finger: "Finger", trinket: "Trinket", ranged: "Ranged", relic: "Relic" };
      return m[slot] || (slot ? slot.charAt(0).toUpperCase() + slot.slice(1) : "");
    }
    function totals() {
      var t = {}, E = eq();
      SLOT_KEYS.forEach(function (k) {
        var it = byId[E[k]]; if (!it) return;
        var s = it.stats || {};
        Object.keys(s).forEach(function (x) { if (typeof s[x] === "number") t[x] = (t[x] || 0) + s[x]; });
        if (it.armor) t.armor = (t.armor || 0) + it.armor;
      });
      return t;
    }
    function slotHTML(def) {
      var it = byId[eq()[def[0]]];
      var blocked = def[0] === "offhand" && byId[eq().mainhand] && byId[eq().mainhand].slot === "two-hand";
      return '<button type="button" class="gslot' + (it ? " filled q-" + esc(it.quality || "common") : "") + (blocked ? " blocked" : "") + '" data-gslot="' + def[0] + '" data-tip="' +
        attr(it ? itemTip(it) : "<b>" + esc(def[1]) + "</b>" + (blocked ? "Your two-hander fills this." : "Empty. Click to pick an item.")) + '"' + (it ? ' data-tipcls="itemtip"' : "") + ">" +
        '<span class="gs-ic">' + img(it ? it.icon : def[2]) + "</span>" +
        '<span class="gs-t"><em>' + esc(def[1]) + "</em><b>" + (it ? esc(it.name) : "Empty") + "</b></span></button>";
    }
    function html(ctx) {
      var t = totals(), count = SLOT_KEYS.filter(function (k) { return byId[eq()[k]]; }).length;
      var stats = STAT_GROUPS.map(function (g) {
        return '<div class="gst-g"><h6>' + g[0] + "</h6>" + g[1].map(function (x) {
          var v = t[x[0]] || 0;
          return '<div class="gst' + (v ? " on" : "") + '"><span>' + x[1] + "</span><b>" + (v ? (/%$/.test(x[1]) ? v + "%" : v) : "0") + "</b></div>";
        }).join("") + "</div>";
      }).join("");
      return '<div class="gear2"><div class="g2-head"><b>Gear</b><span class="g2-count">' + count + " / " + SLOT_KEYS.length + " equipped</span>" +
        '<span class="g2-db">' + items.length + " Forever items known so far</span>" +
        (count ? '<button type="button" class="nm-btn ghost" data-gclear="1">Clear gear</button>' : "") + "</div>" +
        '<div class="g2-doll"><div class="g2-col">' + SLOTS.left.map(slotHTML).join("") + "</div>" +
          '<div class="g2-mid"><div class="g2-hero">' + (ctx.raceIcon ? img(ctx.raceIcon, "g2-race") : "") + (ctx.classIcon ? img(ctx.classIcon, "g2-class") : "") +
            '<b style="color:' + esc(ctx.classColour || "#fff") + '">' + esc(ctx.name || "Unnamed") + "</b><span>" + esc(ctx.line || "") + "</span></div>" +
            '<div class="g2-stats">' + stats + '<p class="g2-note">Totals from equipped items only. Base stats per race and level are not published yet.</p></div></div>' +
          '<div class="g2-col">' + SLOTS.right.map(slotHTML).join("") + "</div></div>" +
        '<div class="g2-bottom">' + SLOTS.bottom.map(slotHTML).join("") + "</div></div>";
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
      return SLOT_KEYS.map(function (k, i) { return E[k] != null && byId[E[k]] ? i.toString(36) + E[k] : null; }).filter(Boolean).join("~");
    }
    function decode(seg) {
      var E = {};
      String(seg || "").split("~").forEach(function (part) {
        var m = /^([0-9a-z])([A-Za-z0-9_-]+)$/.exec(part);
        if (!m) return;
        var k = SLOT_KEYS[parseInt(m[1], 36)];
        if (k && byId[m[2]] && (ACCEPT[k] || []).indexOf(byId[m[2]].slot) !== -1) E[k] = m[2];
      });
      return E;
    }
    return { html: html, pickerHTML: pickerHTML, itemTip: itemTip, encode: encode, decode: decode, byId: byId, count: items.length, SLOT_KEYS: SLOT_KEYS };
  };
})();
