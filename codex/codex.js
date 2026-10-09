/* The Codex: renders codex.json. Icons hotlinked like everywhere else. */
(function () {
  "use strict";
  var CDN = "https://wow.zamimg.com/images/wow/icons/large/";
  var CLASS_COLOUR = { Warrior: "#c79c6e", Paladin: "#f58cba", Hunter: "#abd473", Rogue: "#fff569",
    Priest: "#ffffff", Shaman: "#0070de", Mage: "#69ccf0", Warlock: "#9482c9", Druid: "#ff7d0a" };
  function esc(s) { return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;"); }
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
    return '<div class="factgrid">' + list.map(function (f) {
      return '<div class="factc"><p>' + esc(f) + "</p></div>";
    }).join("") + "</div>";
  }
  function modal() {
    var m = document.getElementById("cxmodal");
    if (!m) {
      m = document.createElement("div"); m.id = "cxmodal"; m.className = "cxmodal"; m.hidden = true;
      m.innerHTML = '<div class="cxm-card" role="dialog" aria-modal="true" aria-labelledby="cxm-title" tabindex="-1"><button type="button" class="cxm-x" aria-label="Close">&times;</button><div class="cxm-body"></div></div>';
      document.body.appendChild(m);
      var shut = function () {
        if (m.hidden) return;
        m.hidden = true;
        if (window.TipKit) TipKit.hide();
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
    return m;
  }
  function showModal(m, wide) {
    m.querySelector(".cxm-card").classList.toggle("wide", !!wide);
    m.hidden = false;
    m.querySelector(".cxm-card").scrollTop = 0;
    m.querySelector(".cxm-card").focus();
  }
  function openTopic(key) {
    var t = TOPICS[key]; if (!t) return;
    var m = modal();
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
    showModal(m, false);
  }

  // ---- dungeon loot tables: codex/loot.json, items from codex/loot-items.json ----
  var LOOTITEMS = null, LGK = null;
  function absent(i) { return !!(LOOT.absent && LOOT.absent[i] != null); }
  function lootCount(d) {
    var ids = {}, qids = {};
    d.bosses.forEach(function (b) { b.items.forEach(function (i) { if (!absent(i)) ids[i] = 1; }); });
    d.quests.forEach(function (q) { q.items.forEach(function (i) { if (!absent(i)) qids[i] = 1; }); });
    return { drops: Object.keys(ids).length, quests: Object.keys(qids).length,
      bosses: d.bosses.filter(function (b) { return b.kind !== "rare"; }).length, rares: d.bosses.filter(function (b) { return b.kind === "rare"; }).length };
  }
  function lootTiles() {
    return '<div class="loottiles">' + LOOT.dungeons.map(function (d) {
      var n = lootCount(d), empty = !n.drops && !n.quests;
      return '<button type="button" class="loottile' + (empty ? " empty" : "") + '" data-loot="' + esc(d.name) + '"' + (empty ? " disabled" : "") + ">" +
        '<span class="lt-h"><b>' + esc(d.name) + "</b>" + (d.new ? '<i class="lt-new">New</i>' : "") + "</span>" +
        '<span class="lt-m">' + (d.levels ? "Levels " + d.levels[0] + "\u2013" + d.levels[1] : "") + "</span>" +
        '<span class="lt-c">' + (empty ? "No loot recorded yet" : [n.bosses + (n.bosses === 1 ? " boss" : " bosses"), n.drops + " drops", n.rares ? n.rares + (n.rares === 1 ? " rare" : " rares") : "", n.quests ? n.quests + " quest rewards" : ""].filter(Boolean).join(" \u00b7 ")) + "</span></button>";
    }).join("") + "</div>";
  }
  function gist(it) {
    var s = it.stats || {}, bits = [], sp = sv(s, "spellPower"), sd = sv(s, "spellDamage") + schoolMax(s);
    if (sp) bits.push("+" + sp + " spell power");
    if (sd) bits.push("+" + sd + " spell damage");
    if (s.healing) bits.push("+" + s.healing + " healing");
    [["strength", "Str"], ["agility", "Agi"], ["stamina", "Sta"], ["intellect", "Int"], ["spirit", "Spi"]].forEach(function (k) { if (s[k[0]]) bits.push("+" + s[k[0]] + " " + k[1]); });
    if (s.attackPower) bits.push("+" + s.attackPower + " AP");
    if (s.critRating) bits.push("+" + s.critRating + " crit rating"); else if (s.crit) bits.push(s.crit + "% crit");
    if (s.hitRating) bits.push("+" + s.hitRating + " hit rating"); else if (s.hit) bits.push(s.hit + "% hit");
    if (s.defenseRating) bits.push("+" + s.defenseRating + " defense");
    if (s.bonusArmor) bits.push("+" + s.bonusArmor + " armor");
    if (s.mp5) bits.push(s.mp5 + " mp5");
    return bits.slice(0, 4).join(" \u00b7 ");
  }
  // Where a loot table comes from: the fansites that published players' records, and since October 2026 our own
  // players' loot windows (QuestBank), marked "players' games" in a src list by tools/apply_loot.py.
  var PG = "players' games";
  function joinList(a) { return a.length < 3 ? a.join(" and ") : a.slice(0, -1).join(", ") + " and " + a[a.length - 1]; }
  function lootSrcText(src) {
    var sites = (src || []).filter(function (s) { return s !== PG; }), ours = sites.length !== (src || []).length;
    return (sites.length ? "as published by " + joinList(sites) : "") + (ours ? (sites.length ? ", and " : "") + "seen in players' games through QuestBank" : "");
  }
  function lootSeen(b) {
    var g = b.games, n = g && g.kills;
    if (!n) return "";
    // link "time": the game named no creature for the fight, so the corpse looted first after the kill was taken for the boss
    var time = g.link === "time";
    return "<small" + (time ? ' title="The game did not name this fight\'s creature; the corpse looted first after the kill was taken for the boss."' : "") +
      ">Seen in players' games: " + (b.kind === "object" || b.kind === "trash" ? "looted " + n + (n === 1 ? " time" : " times") : n + (n === 1 ? " kill" : " kills")) +
      (time ? " (linked by time)" : "") + "</small>";
  }
  function lootRow(id, ours) {
    var it = LOOTITEMS[id];
    if (!it) return "";
    var kind = [slotName(it.slot), it.type && it.type !== slotName(it.slot) ? it.type : ""].filter(Boolean).join(" ");
    var g = gist(it);
    return '<button type="button" class="lr q-' + esc(it.quality || "common") + '" data-lid="' + esc(id) + '"><span class="lr-ic">' + img(it.icon) + "</span>" +
      '<span class="lr-t"><b>' + esc(it.name) + "</b><em>" + esc([kind, g, it.est === "classic" ? "Classic stats (est.)" : "", ours === true ? "players' games only" : ""].filter(Boolean).join(" \u00b7 ") || (it.sub && it.sub !== "Other" ? it.sub : "Item")) + "</em></span></button>";
  }
  function openLoot(name) {
    var d = LOOT && LOOT.dungeons.filter(function (x) { return x.name === name; })[0];
    if (!d) return;
    if (!LOOTITEMS) {
      fetch("/codex/loot-items.json", { cache: "no-store" }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; }).then(function (j) {
        LOOTITEMS = {};
        ((j && j.items) || []).forEach(function (it) { LOOTITEMS[it.id] = it; });
        if (window.ForgeGear) { try { LGK = ForgeGear({ items: { items: (j && j.items) || [] }, get: function () { return {}; } }); } catch (e) { LGK = null; } }
        openLoot(name);
      });
      return;
    }
    var n = lootCount(d), m = modal();
    var html = '<div class="cxm-head loot-head"><b id="cxm-title">' + esc(d.name) + "</b>" +
      (d.levels ? '<span class="lvlchip">Levels ' + d.levels[0] + "\u2013" + d.levels[1] + "</span>" : "") + (d.new ? '<span class="lt-new">New in Forever</span>' : "") + "</div>" +
      '<p class="loot-sub">' + [n.bosses + (n.bosses === 1 ? " boss" : " bosses"), n.drops + " drops", n.quests ? n.quests + " quest rewards" : ""].filter(Boolean).join(" \u00b7 ") +
      ". Recorded by players in the beta, " + esc(lootSrcText(d.src)) + ". Bosses and drops can still change." +
      (d.bosses.concat(d.quests || []).some(function (b) { return (b.items || []).some(function (i) { return LOOTITEMS[i] && LOOTITEMS[i].est === "classic"; }); })
        ? " Items marked Classic stats are on these lists, but nobody has seen their Forever numbers yet: the stats shown are WoW Classic's." : "") + "</p>";
    function here(ids) { return ids.filter(function (i) { return !absent(i) && LOOTITEMS[i]; }); }
    function gone(ids) { return ids.filter(absent).map(function (i) { return LOOT.absent[i]; }).filter(Boolean); }
    html += d.bosses.filter(function (b) { return b.items.length; }).map(function (b) {
      var h = here(b.items), g = gone(b.items);
      return '<section class="loot-boss' + (b.kind === "rare" ? " rare" : "") + (h.length ? "" : " bare") + '"><h4>' + esc(b.name) + (b.kind === "rare" ? '<i class="lt-rare">Rare spawn</i>' : "") +
        (b.level ? "<small>Level " + b.level + "</small>" : "") + lootSeen(b) + "</h4>" +
        (h.length ? '<div class="lr-grid">' + h.map(function (i) { return lootRow(i, (b.gamesOnly || []).indexOf(i) !== -1); }).join("") + "</div>" : '<p class="lr-none">No Forever drop recorded yet.</p>') +
        (g.length ? '<p class="lr-gone"><b>From Classic\'s table, not yet seen in Forever:</b> ' + g.map(esc).join(", ") + ".</p>" : "") + "</section>";
    }).join("");
    var qs = d.quests.filter(function (q) { return here(q.items).length; });
    if (qs.length) html += '<section class="loot-boss quests"><h4>Quest rewards</h4>' + qs.map(function (q) {
      return '<p class="lq">' + esc(q.name) + (q.level ? " <small>level " + q.level + (q.side === "a" ? ", Alliance" : q.side === "h" ? ", Horde" : "") + "</small>" : "") + '</p><div class="lr-grid">' + here(q.items).map(lootRow).join("") + "</div>";
    }).join("") + "</section>";
    html += '<p class="loot-foot"><a href="/codex/?src=' + encodeURIComponent(d.name) + '">Search this dungeon in the Database &rsaquo;</a></p>';
    m.querySelector(".cxm-body").innerHTML = html;
    if (m.hidden) m._prev = document.activeElement;
    showModal(m, true);
    if (window.TipKit && LGK) m.querySelectorAll(".lr[data-lid]").forEach(function (row) {
      TipKit.hover(row, function (el) { return LGK.itemTip(LOOTITEMS[el.getAttribute("data-lid")]); }, function () { return "itemtip"; });
      row.addEventListener("click", function (e) {
        if (TipKit.touchy() || e.detail === 0) TipKit.openSheet(LGK.itemTip(LOOTITEMS[row.getAttribute("data-lid")]), [], { cls: "itemtip", owner: "loot:" + row.getAttribute("data-lid") });
      });
    });
  }

  // ---- Database search: Forever items (../plan/items.json) plus this page's places, perks, spells and systems ----
  var PAGE = window.CODEX_PAGE || "db";
  var CATS = [["all", "All"], ["weapon", "Weapons"], ["armor", "Armor"], ["accessory", "Accessories"], ["offhand", "Off-hands and relics"],
    ["consumable", "Consumables"], ["recipe", "Recipes"], ["craft", "Crafting"], ["pvp", "PvP"], ["misc", "Misc"], ["place", "Places"],
    ["rare", "Rare spawns"], ["perk", "Legacy perks"], ["soul", "Souls"], ["spell", "Spells"], ["talent", "Talents"], ["racial", "Racials"],
    ["set", "Item sets"], ["system", "Systems"]];
  var SUBFIRST = ["Cloth", "Leather", "Mail", "Plate", "Shield", "Neck", "Ring", "Trinket", "Cloak", "Alchemy", "Cooking", "First Aid", "Zone", "Dungeon", "Raid", "Battleground",
    "Eastern Kingdoms", "Kalimdor", "Dungeons", "Rank"];
  var QUAL = ["poor", "common", "uncommon", "rare", "epic", "legendary", "heirloom"];
  var SYNC = function () {};
  var IDX = [], GK = null, SQ = { q: "", cat: "all", sub: "", qual: "", lvl: "", cls: "", prof: "", sk: "", era: false, cl: false, stat: "", src: "", at: [], ms: "", fx: [], sort: "" }, SHOWN = 60;
  // Classic items Forever has not shown yet (est "classic"): listed only when a Forever loot record names them, unless asked for
  function unseenClassic(it) { return it && it.est === "classic" && !((it.drops && it.drops.length) || (it.quests && it.quests.length)); }
  // Item helpers shared with The Forge (plan/gear.js); pages that do not load it get plain fallbacks.
  var FI = window.ForgeItem || null;
  function fiVal(it, k) { return FI ? FI.statVal(it, k) : (+((it && it.stats) || {})[k] || 0); }
  function effLvl(it) { return FI ? FI.effReq(it) : { lvl: +it.reqLevel || 0, est: false }; }
  var ARMORS = ["Cloth", "Leather", "Mail", "Plate", "Shield"];
  var MAINS = [["strength", "Strength"], ["agility", "Agility"], ["intellect", "Intellect"], ["sta", "Stamina, no Str/Agi/Int"], ["spirit", "Spirit"]];
  // Categories with no items in them: the item-only filters (stat, main stat, armor, effects, source, profession,
  // sort by stat) mean nothing there, so they are ignored and hidden rather than emptying the list.
  var NONITEM = { place: 1, perk: 1, soul: 1, spell: 1, talent: 1, racial: 1, set: 1, system: 1, craft: 1, rare: 1 };
  function itemFilters(cat) { return !NONITEM[cat]; }
  // Crafting rows are recipes, not items: of the item filters only profession and skill mean something there.
  var CRAFTCAT = { craft: 1 };
  // What any class can have: a class filter keeps these (a racial, a profession's recipes, a PvP rank, a rare spawn).
  // Recipes of a one-class profession (Poisons, Comprehension) carry that class instead.
  var CLASSLESS = { racial: 1, craft: 1, pvprank: 1, rare: 1 };
  function armorFilters(cat) { return cat === "all" || cat === "armor"; } // weapons, jewelry and held items have no armor type
  var GEARCAT = { all: 1, weapon: 1, armor: 1, accessory: 1, offhand: 1 }; // PvP holds one stat-less token
  function fxKeys(cat) { return GEARCAT[cat] ? SQ.fx : SQ.fx.filter(function (k) { return k === "rf"; }); } // procs are read for gear only
  function mainOK(it, ms) {
    var st = (FI ? FI.istats(it) : it.stats) || {}, m = FI ? FI.mainStat(it) : "", top = Math.max(st.strength || 0, st.agility || 0, st.intellect || 0);
    if (ms === "sta") return !m && (st.stamina || 0) > 0 && (st.stamina || 0) >= (st.spirit || 0);
    if (ms === "spirit") return !!st.spirit && st.spirit >= top;
    return !!st[ms] && st[ms] >= top; // a tie counts for both: +3 Str +3 Agi is a Strength and an Agility item
  }
  // The level a row is filtered and sorted by: gear without a stored requirement uses the item-level estimate,
  // anything else without one is usable from level 1.
  function lvlOf(it) { return slotName(it.slot) ? effLvl(it).lvl : (+it.reqLevel || 1); }
  // Provenance credits ("Beta build ..., via foreverchanges.pro", the Classic-estimate disclaimer) are not where an
  // item comes from: kept out of the search text so "forever" or "pro" does not match everything.
  var PROVENANCE = /foreverchanges\.pro|Wowhead's Forever database|^Beta (build|client)|^Estimate:|^Season of Discovery data|^Server data via/;
  var SETROWS = {}, ITEMBYID = {}; // set name -> its items-db rows, item id -> row: class and level of sets the set table gives none
  // Effects: chance on hit, use, equip procs and reflect (plan/gear.js reads them from the item data or its tooltip text).
  var FXP = (FI && FI.FXPILLS) || [["rf", "Reflect", "Items that hurt whoever hits you: thorns, damage on block, shield spikes."]];
  function hasFx(it, k) { return !!FI && (FI.hasFx ? FI.hasFx(it, k) : k === "rf" && FI.reflect(it).length > 0); }
  function fxChip(it) { // the effect the list is sorted or filtered by comes first, else the strongest proc, else reflect
    if (!FI || !FI.fxChips) return "";
    var all = FI.fxChips(it).concat(FI.chips(it).filter(function (x) { return x[0] === "reflect"; }));
    var want = SQ.sort || SQ.stat || (SQ.fx.length === 1 && SQ.fx[0] === "rf" ? "reflect" : "");
    var c = all.filter(function (x) { return x[0] === want; })[0] || all[0];
    return c ? c[1] : "";
  }
  function sv(s, k) { return s[k] || 0; }
  function schoolMax(s) { return Math.max(sv(s, "fireSpellDamage"), sv(s, "frostSpellDamage"), sv(s, "natureSpellDamage"), sv(s, "shadowSpellDamage"), sv(s, "arcaneSpellDamage"), sv(s, "holySpellDamage")); }
  // What people search gear by. Spell damage counts damage-and-healing and
  // school damage too, since that is what a caster means by it.
  var STATF = [
    ["spelldmg", "Spell damage", " spell damage", function (s) { return sv(s, "spellPower") + sv(s, "spellDamage") + schoolMax(s); }],
    ["healing", "Healing", " healing", function (s) { return sv(s, "healing") + sv(s, "spellPower"); }],
    ["strength", "Strength", " Strength"], ["agility", "Agility", " Agility"], ["stamina", "Stamina", " Stamina"],
    ["intellect", "Intellect", " Intellect"], ["spirit", "Spirit", " Spirit"],
    ["attackPower", "Attack power", " attack power", function (s) { return sv(s, "attackPower") + sv(s, "rangedAttackPower"); }],
    ["crit", "Crit", "% crit"], ["hit", "Hit", "% hit"], ["spellCrit", "Spell crit", "% spell crit"], ["spellHit", "Spell hit", "% spell hit"],
    ["mp5", "Mana per 5 sec", " mp5"], ["defense", "Defense", " defense"], ["dodge", "Dodge", "% dodge"],
    ["parry", "Parry", "% parry", function (s, it) { return fiVal(it, "parry"); }],
    ["blockChance", "Block chance", "% block", function (s, it) { return fiVal(it, "blockChance"); }],
    ["blockValue", "Block value", " block value", function (s, it) { return fiVal(it, "blockValue"); }],
    ["armor", "Armor", " armor", function (s, it) { return fiVal(it, "armor"); }],
    ["reflect", "Reflect (per enemy swing, 10% block)", " reflect", function (s, it) { return FI ? Math.round((FI.rfHit(it) + FI.rfBlock(it) * 0.10) * 100) / 100 : 0; }],
    ["procDps", "Proc damage per second (est.)", " proc DPS (est.)", function (s, it) { return FI && FI.procDps ? FI.procDps(it) : 0; }],
    ["procDmg", "Proc damage per proc", " per proc", function (s, it) { return FI && FI.procDmg ? FI.procDmg(it) : 0; }],
    ["useDmg", "On-use damage", " on-use damage", function (s, it) { return FI && FI.useAvg ? FI.useAvg(it) : 0; }],
    ["spellPiercing", "Spell penetration", " spell penetration", function (s, it) { return fiVal(it, "spellPiercing"); }],
    ["haste", "Haste %", "% haste", function (s, it) { return fiVal(it, "haste"); }],
    ["expertise", "Expertise %", "% expertise", function (s, it) { return fiVal(it, "expertise"); }],
    ["resist", "Resistance", " resistance", function (s) { return Math.max(sv(s, "fireResist"), sv(s, "frostResist"), sv(s, "natureResist"), sv(s, "shadowResist"), sv(s, "arcaneResist")) + sv(s, "allResist"); }]
  ];
  var STATBY = {};
  STATF.forEach(function (f) { STATBY[f[0]] = f; });
  function rfKey(k) { return k === "reflectHit" || k === "reflectBlock" ? "reflect" : k; } // older links
  function statOf(it, key) {
    var f = STATBY[key], s = (it && it.stats) || {};
    var v = f ? (f[3] ? f[3](s, it) : sv(s, f[0])) : 0;
    return Math.round(v * 100) / 100;
  }
  var STATWORDS = { spellPower: "spell power spell damage spelldmg healing", spellDamage: "spell damage spelldmg", healing: "healing", attackPower: "attack power ap",
    mp5: "mp5 mana regen regeneration", crit: "crit", hit: "hit", spellCrit: "spell crit", spellHit: "spell hit", defense: "defense", dodge: "dodge",
    critRating: "crit critical strike rating", hitRating: "hit rating", defenseRating: "defense rating", dodgeRating: "dodge rating", parryRating: "parry rating",
    blockRating: "block rating", hasteRating: "haste rating", expertiseRating: "expertise rating", bonusArmor: "armor bonus armor", spellPiercing: "spell penetration" };
  var LOOT = null;
  var CLASSES9 = ["Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid"];
  var PROFS = ["Alchemy", "Blacksmithing", "Comprehension", "Cooking", "Enchanting", "Engineering", "First Aid", "Fishing", "Herbalism", "Leatherworking", "Mining", "Poisons", "Skinning", "Tailoring"];
  function slotName(sl) {
    return { "main-hand": "Main Hand", "off-hand": "Off Hand", "one-hand": "One-Hand", "two-hand": "Two-Hand", head: "Head", neck: "Neck", shoulder: "Shoulder",
      back: "Back", chest: "Chest", wrist: "Wrist", hands: "Hands", waist: "Waist", legs: "Legs", feet: "Feet", finger: "Finger", trinket: "Trinket",
      ranged: "Ranged", relic: "Relic", thrown: "Thrown", tabard: "Tabard", shirt: "Shirt" }[sl] || "";
  }
  function buildSouls(d) {
    if (!d.souls || !d.souls.list) return;
    headList(d.souls.list.map(function (s) { return s[0] + ": " + s[1]; }), "souls", "Soul Engraving: " + d.souls.list.length + " shoulder souls", "spell_shadow_soulleech_3");
    d.souls.list.forEach(function (s) {
      IDX.push({ kind: "soul", cat: "soul", sub: "Shoulder soul", name: s[0], icon: s[3] || (s[2] ? "classicon_" + s[2].toLowerCase() : "spell_shadow_soulleech_3"), q: "unknown",
        cls: s[2] ? s[2].charAt(0) + s[2].slice(1).toLowerCase() : undefined,
        meta: "Soul Engraving \u00b7 " + (s[2] ? s[2].charAt(0) + s[2].slice(1).toLowerCase() : "class unsorted"), topic: "souls", text: (s[0] + " " + s[1] + " " + (s[2] || "")).toLowerCase() });
    });
  }
  var SRC_LABEL = { client: "Beta client", sod: "SoD wiring", classic: "Classic text", basic: "General", classiconly: "Not in Forever" };
  // The client builds the spellbook and set files were read from, when the files say (spellbook.json build, sets.json build).
  var BOOK_BUILD = "", SET_BUILD = "", BOOK_PRICE = {};
  function onBuild(b) { return b ? ", build " + b : ""; }
  function srcTip(src) {
    return {
      client: "Tooltip read from the beta client's spell data" + onBuild(BOOK_BUILD) + ".",
      sod: "Season of Discovery wiring in the client: class-masked but with no Forever learn level yet. May change before launch.",
      classic: "Classic placeholder text: the Forever tooltip has not been read yet.",
      basic: "A general spell every class has, from the beta client" + onBuild(BOOK_BUILD) + ".",
      classiconly: "A Classic spell the Forever client's spellbook does not list: cut, renamed, or learned another way."
    }[src] || "";
  }
  // Racial text still carried from the BlizzCon demo says so in its own last sentence.
  function racialSrc(r) { return r.src || (/Read from (the demo|a demo)/i.test(r.d || "") ? "demo" : "client"); }
  var VERDICT = { "same": "same text as Classic", "changed": "text changed from Classic", "new": "new in Forever", "rank": "rank layout differs", "renamed": "renamed from Classic", "moved": "moved from Classic", "unverified": "tooltip unverified", "removed": "removed in a later beta build" };
  var ERA_LABEL = { forever: "Forever-authored", sod: "SoD spell reused", retail: "Retail-era spell", classic: "Classic-era spell" };
  function buildBook(sb) {
    BOOK_BUILD = sb.build || "";
    BOOK_PRICE = sb.trainPrice || {}; // per class: what the trainer prices players saw do and don't tell
    (sb.spells || []).forEach(function (p) {
      IDX.push({ kind: "bookspell", cat: "spell", sub: p.c, name: p.n, icon: p.icon || "inv_misc_questionmark", q: "unknown",
        cls: p.c, lvlKey: typeof p.lvl === "number" ? p.lvl : undefined, sb: p, side: SRC_LABEL[p.src] || "",
        meta: [p.c, p.tab, p.lvl ? "Level " + p.lvl : (p.src === "sod" ? "no learn level yet" : ""), p.tag, VERDICT[p.s] || "", p.seen ? "seen in game" : ""].filter(Boolean).join(" \u00b7 "),
        text: (p.n + " " + p.c + " " + p.tab + " " + (p.d || "")).toLowerCase() });
    });
    (sb.talents || []).forEach(function (t) {
      IDX.push({ kind: "talent", cat: "talent", sub: t.c, name: t.n, icon: t.icon || "inv_misc_questionmark", q: "unknown",
        cls: t.c, lvlKey: 10 + (t.row - 1) * 5, tl: t, side: "Beta client",
        meta: [t.c, t.tree + " tree", "Tier " + t.row, t.r + (t.r === 1 ? " rank" : " ranks"), VERDICT[t.s] || "", t.seen ? "seen in game" : ""].filter(Boolean).join(" \u00b7 "),
        text: (t.n + " " + t.c + " " + t.tree + " " + (t.d || "")).toLowerCase() });
    });
    (sb.racials || []).forEach(function (r) {
      IDX.push({ kind: "racial", cat: "racial", sub: r.race, name: r.n, icon: r.icon || "inv_misc_questionmark", q: "unknown",
        lvlKey: 1, rc: r, side: racialSrc(r) === "demo" ? "BlizzCon demo" : "Beta client",
        meta: [r.race, r.kind === "active" ? "Active racial" : "Passive racial", r.seen ? "seen in game" : ""].filter(Boolean).join(" \u00b7 "),
        text: (r.n + " " + r.race + " " + (r.d || "")).toLowerCase() });
    });
  }
  function buildSets(st) {
    SET_BUILD = st.build || "";
    (st.sets || []).forEach(function (p) {
      IDX.push({ kind: "itemset", cat: "set", sub: p.cat, name: p.n, icon: (p.pieces[0] && p.pieces[0].icon) || "inv_chest_chain_07", q: "unknown",
        cls: p.cls.length === 1 ? p.cls[0] : undefined, lvlKey: p.reqLevel || undefined, st: p, era: p.era,
        side: p.era === "sod" ? "SoD-era data" : p.era === "retail" ? "Retail-era data" : p.touched ? "Reworked for Forever" : "Classic data",
        meta: [p.cat, p.era === "sod" ? "SoD-era duplicate" : "", p.pieces.length + " pieces", p.cls.join("/"), p.reqLevel ? "Level " + p.reqLevel : ""].filter(Boolean).join(" \u00b7 "),
        text: (p.n + " " + p.cat + " " + p.cls.join(" ") + " " + p.bonuses.map(function (b) { return b.spell + " " + (b.fx || ""); }).join(" ")).toLowerCase() });
    });
  }
  // ---- Crafting (codex/recipes.json), rare spawns (codex/rares.json), PvP ranks (codex/pvp.json) ----
  var RC = null, RS = null, PV = null;
  var PROF_ICON = { Alchemy: "trade_alchemy", Blacksmithing: "trade_blacksmithing", Comprehension: "inv_scroll_03", Cooking: "inv_misc_food_15",
    Enchanting: "trade_engraving", Engineering: "trade_engineering", "First Aid": "spell_holy_sealofsacrifice", Fishing: "trade_fishing",
    Herbalism: "trade_herbalism", Leatherworking: "inv_misc_armorkit_17", Mining: "trade_mining", Poisons: "trade_brewpoison",
    Skinning: "inv_misc_pelt_wolf_01", Tailoring: "trade_tailoring" };
  function fmtN(v) { return String(v).replace(/\B(?=(\d{3})+(?!\d))/g, ","); }
  function near(station) { return "Needs " + (/^[aeiou]/i.test(station) ? "an " : "a ") + station + " nearby."; }
  // The skill a recipe is learned at; where nothing records it, the skill it turns yellow at (never below the real one).
  function craftSkill(cr) { return cr.sk || (cr.c ? cr.c[0] : 0); }
  // An item a recipe names: the item database's row when it has one, else the recipe file's own name, quality and icon.
  // A product in no item table (server-sent) is named after its recipe; the file flags it.
  function rcItem(id) {
    var it = ITEMBYID[id], x = RC && RC.items[id];
    return it ? { name: it.name, q: it.quality || "common", icon: it.icon, it: it } : x ? { name: x[0], q: x[1], icon: x[2], unl: !!x[3] } : { name: "Item " + id, q: "common", icon: "" };
  }
  function reagentText(cr) { return (cr.r || []).map(function (r) { return rcItem(r[0]).name + (r[1] > 1 ? " (" + r[1] + ")" : ""); }).join(", "); }
  // The profession and the skill to learn it; a skill from Classic's trainers says so.
  function skillTxt(cr) { return cr.p + (cr.sk ? (cr.cl ? " (Classic trainer: skill " + cr.sk + ")" : " " + cr.sk) : ""); }
  function craftLearn(cr) {
    if (cr.by) return "Learned from " + rcItem(cr.by[0]).name + (cr.sk ? " at skill " + cr.sk : "") + ".";
    if (cr.auto) return "Comes with the profession.";
    if (cr.cl) return "How Forever teaches it is not recorded yet. In Classic, trainers taught it at skill " + cr.sk + ".";
    return "How it is learned is not recorded yet" + (cr.c ? " (it turns yellow at " + cr.c[0] + ")" : "") + ".";
  }
  // The client stores where a recipe turns yellow and grey; green is worked out by Classic's rule (halfway).
  function craftColours(cr) {
    var lo = cr.c[0], hi = cr.c[1];
    return lo && lo < hi ? "Skill-ups: yellow from " + lo + ", grey from " + hi + "; green from about " + Math.floor((lo + hi) / 2) + " by Classic's rule." : "Grey from " + hi + ".";
  }
  function buildCrafts(rc) {
    RC = rc;
    (rc.recipes || []).forEach(function (cr) {
      var made = cr.m ? rcItem(cr.m) : null;
      IDX.push({ kind: "craft", cat: "craft", sub: cr.p, name: cr.n, icon: cr.i || PROF_ICON[cr.p] || "inv_misc_questionmark", q: made ? made.q : "common",
        cr: cr, era: cr.e, cls: cr.cls, side: cr.e === "sod" ? "SoD-era data" : cr.e === "retail" ? "Retail-era data" : "Beta client",
        meta: [cr.p + (cr.sk && !cr.cl ? " " + cr.sk : ""), cr.at || "", cr.k > 1 ? "makes " + cr.k : "", cr.nw ? "New" : "",
          cr.by ? rcItem(cr.by[0]).name : cr.auto ? "comes with the profession" : cr.cl ? "Classic trainer: skill " + cr.sk : ""].filter(Boolean).join(" \u00b7 "),
        text: [cr.n, cr.p, cr.at || "", reagentText(cr), (cr.by || []).map(function (i) { return rcItem(i).name; }).join(" "), cr.fx || ""].join(" ").toLowerCase() });
    });
    addReagents();
  }
  // Recipe items and what recipes make show their reagents in the item tooltip, from the client's recipe tables.
  function addReagents() {
    if (!RC) return;
    RC.recipes.forEach(function (cr) {
      var txt = [reagentText(cr), skillTxt(cr), cr.at || ""].filter(Boolean).join(" \u00b7 ");
      [cr.m].concat(cr.by || []).forEach(function (id) {
        var it = id && ITEMBYID[id];
        if (it && (!it.reagents || it.reagents === "not shown")) it.reagents = txt;
      });
    });
  }
  function lvTxt(lv) { return Array.isArray(lv) ? lv[0] + "\u2013" + lv[1] : String(lv); }
  function buildRares(rs) {
    RS = rs;
    (rs.rares || []).forEach(function (r) {
      var z = rs.zones[r.z] || ["", ""];
      IDX.push({ kind: "rare", cat: "rare", sub: z[1] || "Unknown", name: r.n, icon: r.i || "inv_misc_head_dragon_bronze", q: "unknown", rr: r,
        lvlKey: Array.isArray(r.lv) ? r.lv[0] : r.lv, side: "Classic data",
        meta: [r.rk === "rare elite" ? "Rare elite" : "Rare", "Level " + lvTxt(r.lv), z[0], r.fam ? r.fam + (r.tame ? ", tameable" : "") : r.ty || ""].filter(Boolean).join(" \u00b7 "),
        text: [r.n, r.sub || "", z[0], z[1], r.rk, r.ty || "", r.fam || "", r.tame ? "tameable pet" : ""].join(" ").toLowerCase() });
    });
  }
  // Rares players met in Forever's dungeons: the loot records' rare spawns (codex/loot.json).
  var LOOT_RARES = false;
  function addLootRares() {
    if (LOOT_RARES || !LOOT || PAGE !== "db") return;
    LOOT_RARES = true;
    LOOT.dungeons.forEach(function (d) {
      d.bosses.forEach(function (b) {
        if (b.kind !== "rare") return;
        var nd = b.items.filter(function (i) { return !absent(i); }).length;
        IDX.push({ kind: "rare", cat: "rare", sub: "Dungeons", name: b.name, icon: "inv_misc_head_dragon_bronze", q: "unknown", dun: d.name, lb: b,
          lvlKey: Array.isArray(b.level) ? b.level[0] : b.level || undefined, side: "Players' loot records",
          meta: ["Rare", b.level ? "Level " + lvTxt(b.level) : "", d.name, nd + (nd === 1 ? " drop" : " drops")].filter(Boolean).join(" \u00b7 "),
          text: [b.name, d.name, "dungeon rare"].join(" ").toLowerCase() });
      });
    });
  }
  // Classic respawn times, as a reader says them.
  function respawn(rs) {
    function hr(v) { return Math.round(v / 360) / 10; }
    function mn(v) { return Math.round(v / 60); }
    var a = rs[0], b = rs[1];
    if (!a) return b >= 3600 ? "within " + hr(b) + " hours" : "within " + mn(b) + " min";
    if (a >= 3600) return a === b ? hr(a) + " hours" : hr(a) + " to " + hr(b) + " hours";
    if (b < 3600) return a === b ? mn(a) + " min" : mn(a) + " to " + mn(b) + " min";
    return mn(a) + " min to " + hr(b) + " hours";
  }
  function spots(r) { // "The Barrens 62.0, 33.3; 61.2, 34.5", a zone named once per run of its points
    var out = [], last = null;
    r.pts.forEach(function (p) {
      var zn = (RS.zones[p[0]] || [""])[0];
      out.push((zn !== last ? zn + " " : "") + p[1].toFixed(1) + ", " + p[2].toFixed(1));
      last = zn;
    });
    return out.join("; ");
  }
  function rankName(r) { return r.a === r.h ? r.a : r.a + " / " + r.h; }
  function buildRanks(pv) {
    PV = pv;
    (pv.ranks || []).forEach(function (r) {
      IDX.push({ kind: "pvprank", cat: "pvp", sub: "Rank", name: "Rank " + r.r + ": " + rankName(r), icon: r.icon || "inv_bannerpvp_02", q: "unknown", rk: r, href: "#pvp",
        side: "Beta client", meta: [fmtN(r.pts) + " rank points", r.reward ? "Blizzard: " + r.reward : "", r.lp ? "Legacy Point" : ""].filter(Boolean).join(" \u00b7 "),
        text: ["rank " + r.r, r.a, r.h, r.reward || "", "pvp honor rank"].join(" ").toLowerCase() });
    });
  }
  // The PvP ranks section: facts on top, then one row per rank in the rankings' row style.
  function drawPvp(pv) {
    var box = document.getElementById("pvpbox");
    if (!box || !pv.ranks || !pv.ranks.length) return;
    var top = Math.max.apply(null, pv.ranks.map(function (r) { return r.pts; })) || 1;
    var lps = pv.ranks.filter(function (r) { return r.lp; }).map(function (r) { return r.r; });
    var wk = pv.weekly || [], full = wk.filter(function (w) { return w[1] >= 14; })[0];
    var cards = [
      "<b>Honor cap " + fmtN(pv.honorCap) + ".</b>" + (pv.honorWas ? " It was " + fmtN(pv.honorWas[0]) + " until build " + esc(pv.honorSince) + ", when Blizzard also raised most Honor costs by about half." : ""),
      "<b>" + fmtN(pv.total) + " rank points</b> from Private or Scout to Grand Marshal or High Warlord: each rank is its own bar, from " + fmtN(pv.ranks[0].pts) + " points to " + fmtN(top) + ".",
      wk.length ? "<b>A rank cap that rises each week.</b> Rank " + wk[0][1] + " in week 1" + (full ? ", rank 14 from week " + full[0] : "") + " of a season." : "",
      lps.length ? "<b>Legacy Points</b> for reaching rank " + lps.join(", ").replace(/, (\d+)$/, " and $1") + "." : "",
      pv.rankPoints && pv.rankPoints.about ? "<b>Rank Points</b>, in the client's own words: " + esc(pv.rankPoints.about) : ""
    ].filter(Boolean);
    var rows = pv.ranks.map(function (r) {
      return '<li class="rk-row" data-name="' + esc("Rank " + r.r + ": " + rankName(r)) + '"><span class="rk-n">' + r.r + "</span>" + img(r.icon || "inv_bannerpvp_02") +
        '<span class="rk-t"><b>' + esc(rankName(r)) + "</b><em>" + esc([r.reward ? "Blizzard: " + r.reward : "", r.lp ? "Legacy Point" : "", r.week ? "open from week " + r.week : ""].filter(Boolean).join(" \u00b7 ")) + "</em></span>" +
        '<span class="rk-s"><span class="rk-bar"><i style="width:' + Math.round(r.pts / top * 100) + '%"></i></span><b>' + fmtN(r.pts) + "</b><small>rank points</small></span></li>";
    }).join("");
    box.innerHTML = '<div class="factgrid">' + cards.map(function (c) { return '<div class="factc"><p>' + c + "</p></div>"; }).join("") + "</div>" +
      '<ul class="rk-list">' + rows + "</ul>" +
      '<p class="rk-small">Rank names, rank points, weeks, the Honor cap and Legacy Points: beta client' + esc(onBuild(pv.build)) +
      ". Reading the client's curves as each rank's bar and as weeks of a season is our inference. Rewards per rank are " +
      '<a href="' + esc(pv.rewardsSrc) + '" rel="noopener">Blizzard\'s, from Oct 7</a>; the seals, sets and vendors behind them are server data.</p>';
  }
  // A recipe's item as a loot-table row: hover for its tooltip, click to find it in the Database.
  function itemRowFor(id, extra) {
    var x = rcItem(id), it = x.it;
    var kind = it ? [slotName(it.slot), it.sub && it.sub !== "Other" ? it.sub : ""].filter(Boolean).join(" \u00b7 ") : x.unl ? "Not in the client's item table: named after its recipe" : "";
    return '<button type="button" class="lr q-' + esc(x.q || "common") + '" data-iid="' + esc(id) + '" data-q="' + esc(x.name) + '"><span class="lr-ic">' + img(x.icon) + "</span>" +
      '<span class="lr-t"><b>' + esc(x.name) + "</b><em>" + esc([extra || "", kind || (extra ? "" : "Item")].filter(Boolean).join(" \u00b7 ")) + "</em></span></button>";
  }
  function wireItemRows(root) {
    root.querySelectorAll(".lr[data-iid]").forEach(function (row) {
      function it() { return ITEMBYID[row.getAttribute("data-iid")]; }
      if (window.TipKit && GK) TipKit.hover(row, function () { return it() ? GK.itemTip(it()) : ""; }, function () { return "itemtip"; });
      row.addEventListener("click", function (e) {
        var name = row.getAttribute("data-q");
        if (window.TipKit && GK && it() && (TipKit.touchy() || e.detail === 0)) {
          TipKit.openSheet(GK.itemTip(it()), [{ label: "Find in the Database", onClick: function () { showInDb({ q: name, find: it() }); } }], { cls: "itemtip", owner: "craft:" + row.getAttribute("data-iid") });
          return;
        }
        showInDb({ q: name, find: it() });
      });
    });
  }
  // Point the Database search at something from a popup (a reagent, a profession's recipes) without reloading the page.
  // Finding an item by name (o.q) clears the filters; its row (o.find) turns on the data toggle it needs, so it is listed.
  var CLEARF = function () {};
  function showInDb(o) {
    var qi = document.getElementById("dbs-qi");
    if (!qi) {
      location.href = "/codex/?" + (o.q ? "q=" + encodeURIComponent(o.q) : "cat=" + encodeURIComponent(o.cat || "all")) + (o.prof ? "&prof=" + encodeURIComponent(o.prof) : "");
      return;
    }
    var m = document.getElementById("cxmodal");
    if (m && !m.hidden) m.hidden = true;
    if (window.TipKit) { TipKit.hide(); if (TipKit.sheetOpen()) TipKit.closeSheet(); }
    SQ.q = qi.value = o.q || ""; SQ.cat = o.cat || "all"; SQ.sub = ""; SQ.qual = "";
    if (o.q) {
      CLEARF();
      if (o.find && o.find.era) SQ.era = true;
      if (unseenClassic(o.find)) SQ.cl = true;
    }
    if (o.prof != null) { SQ.prof = o.prof; var ps = document.getElementById("dbf-prof"); if (ps) ps.value = o.prof; }
    SHOWN = 60; SYNC(); drawSearch(); syncUrl();
    document.getElementById("dbs").scrollIntoView({ behavior: "smooth", block: "start" });
  }
  function openCraft(cr) {
    var m = modal();
    if (m.hidden) m._prev = document.activeElement;
    var html = '<div class="cxm-head loot-head">' + img(cr.i || PROF_ICON[cr.p]) + '<b id="cxm-title">' + esc(cr.n) + "</b>" +
      '<span class="lvlchip">' + esc(cr.p + (cr.sk && !cr.cl ? " " + cr.sk : "")) + "</span>" + (cr.nw ? '<span class="lt-new">New in Forever</span>' : "") + "</div>" +
      '<p class="loot-sub">' + esc([craftLearn(cr), cr.at ? near(cr.at) : "", cr.c ? craftColours(cr) : ""].filter(Boolean).join(" ")) + "</p>";
    if (cr.m) html += '<section class="loot-boss"><h4>Makes' + (cr.k > 1 || cr.kv ? "<small>" + (cr.kv ? "about " : "") + (cr.k || 1) + " per craft</small>" : "") + '</h4><div class="lr-grid">' + itemRowFor(cr.m) + "</div></section>";
    else if (cr.fx) html += '<section class="loot-boss"><h4>What it does</h4><p class="lr-none">' + esc(cr.fx) + "</p></section>";
    html += '<section class="loot-boss"><h4>Reagents</h4><div class="lr-grid">' + (cr.r || []).map(function (r) { return itemRowFor(r[0], "\u00d7" + r[1]); }).join("") + "</div></section>";
    if (cr.by) html += '<section class="loot-boss"><h4>Taught by</h4><div class="lr-grid">' + cr.by.map(function (i) { return itemRowFor(i); }).join("") + "</div></section>";
    html += '<p class="loot-foot">Recipe, reagents, station and the yellow and grey skill-ups from the beta client' + esc(onBuild(RC && RC.build)) +
      (cr.cl ? "; the trainer's skill is Classic's, from the CMaNGOS Classic database" : "") +
      (cr.e ? ". " + (cr.e === "sod" ? "Season of Discovery" : "Retail-era") + " data on the branch: it may not be in Forever" : "") +
      (cr.rs ? ". The spell is Season of Discovery's; an item new in Forever teaches it" : "") +
      (cr.m && rcItem(cr.m).unl ? ". What it makes is in no item table yet: the server sends it" : "") +
      '. <button type="button" class="cx-more" data-craftprof="' + esc(cr.p) + '">All ' + esc(cr.p) + " recipes &rsaquo;</button></p>";
    m.querySelector(".cxm-body").innerHTML = html;
    showModal(m, true);
    wireItemRows(m);
    var all = m.querySelector("[data-craftprof]");
    if (all) all.addEventListener("click", function () { showInDb({ cat: "craft", prof: all.getAttribute("data-craftprof") }); });
  }
  // Kinds whose rows carry a tooltip of their own (sbTip), shown as a sheet on touch.
  var SBT = { bookspell: 1, talent: 1, racial: 1, itemset: 1, craft: 1, rare: 1, pvprank: 1 };
  function coin(c) {
    var g = Math.floor(c / 10000), s = Math.floor(c / 100) % 100, k = c % 100;
    return [g ? g + "g" : "", s ? s + "s" : "", k || !(g || s) ? k + "c" : ""].filter(Boolean).join(" ");
  }
  function sbTip(e) {
    var h = "<b>" + esc(e.name) + "</b>" + '<span class="sbt-m">' + esc(e.meta) + "</span>";
    if (e.kind === "bookspell") {
      var p = e.sb;
      if (p.d) h += "<p>" + esc(p.d) + "</p>";
      if (p.note) h += '<p class="sbt-note">' + esc(p.note) + "</p>";
      if (p.cl && p.s && p.s !== "same") h += '<p class="sbt-note">Classic trains it at level ' + p.cl + ".</p>";
      if (p.seen) h += '<p class="sbt-note">Seen in game: a level ' + p.seen + " " + esc(p.c) + " in players' games had it.</p>";
      // [rank, level, copper] per rank, as trainer windows in players' games showed them
      if (p.train && p.train.length) h += '<p class="sbt-note">Trainer windows in players\u2019 games: ' + esc(p.train.map(function (x) {
        return (x[0] ? "rank " + x[0] + ", " : "") + "level " + x[1] + ", " + coin(x[2]);
      }).join("; ")) + ". " + esc(BOOK_PRICE[p.c] || "Prices are what those characters paid; reputation discounts may apply.") + "</p>";
      h += '<p class="sbt-src">' + esc(srcTip(p.src)) + "</p>";
    } else if (e.kind === "talent") {
      var t = e.tl;
      if (t.d) h += "<p>" + esc(t.d) + (t.r > 1 ? " (rank 1 of " + t.r + ")" : "") + "</p>";
      // the client's talent-point sources: one point a level from 10, plus one per rank of the Legacy perk Talented
      h += '<p class="sbt-note">Tier ' + t.row + " needs " + (t.row - 1) * 5 + " points in the tree: level " + e.lvlKey + " at the earliest, up to 5 levels sooner with the Legacy perk Talented.</p>";
      if (t.added) h += '<p class="sbt-note">' + (t.from ? "Moved here from " + esc(t.from) : "New") + " in beta build " + esc(t.added) + ".</p>";
      if (t.gone) h += '<p class="sbt-note">Removed from the tree in beta build ' + esc(t.gone) + ".</p>";
      if (t.was) h += '<p class="sbt-note">Called ' + esc(t.was) + " in earlier builds.</p>";
      if (t.note) h += '<p class="sbt-note">' + esc(t.note) + "</p>";
      if (t.seen) h += '<p class="sbt-note">Seen in game: a level ' + t.seen + " " + esc(t.c) + " in players' games had it.</p>";
      h += '<p class="sbt-src">Talent text from the beta client' + esc(onBuild(BOOK_BUILD)) + ".</p>";
    } else if (e.kind === "racial") {
      if (e.rc.d) h += "<p>" + esc(e.rc.d) + "</p>";
      if (e.rc.seen) h += '<p class="sbt-note">Seen in game: a ' + esc(e.rc.race) + " in players' games had it.</p>";
      h += '<p class="sbt-src">' + (racialSrc(e.rc) === "demo"
        ? "Text read from BlizzCon demo footage (talentsforever.com export, CC BY 4.0); not re-read from the client yet."
        : "Racial text from the beta client" + esc(onBuild(BOOK_BUILD)) + ".") + "</p>";
    } else if (e.kind === "itemset") {
      var st = e.st;
      h += '<ul class="sbt-pieces">' + st.pieces.map(function (pc) {
        var m = /^Item (\d+)/.exec(pc.n || ""), it = ITEMBYID[pc.id] || (m && ITEMBYID[m[1]]); // "Item 11729 - not itemized..." when the set table has no name
        var est = pc.est === "classic" || (it && it.est === "classic") ? ' <i class="sbt-int">Classic estimate</i>' : "";
        if (it) return '<li class="q-' + esc(it.quality || "unknown") + '">' + esc(it.name) + (slotName(it.slot) ? " \u2013 " + esc(slotName(it.slot)) : "") + est + "</li>";
        return '<li class="q-' + esc(pc.q) + '">' + esc(pc.n) + (pc.slot ? " \u2013 " + esc(slotName(pc.slot) || pc.slot) : "") + est + "</li>";
      }).join("") + "</ul>";
      st.bonuses.forEach(function (b) {
        h += '<p class="sbt-bonus"><b>(' + b.p + ")</b> " + esc(b.fx || b.spell) +
          (b.fx ? "" : b.fx0 ? ' <i class="sbt-int">internal name: the client\'s text has a number it fills with 0</i>' : ' <i class="sbt-int">internal name, no tooltip text in the client</i>') +
          ' <i class="sbt-era sbt-era-' + b.era + '">' + ERA_LABEL[b.era] + "</i></p>";
      });
      h += '<p class="sbt-src">Item set tables from the beta client' + esc(onBuild(SET_BUILD)) + ". Era per bonus read from spell ID bands.</p>";
    } else if (e.kind === "craft") {
      var cr = e.cr;
      h += "<p>" + esc(cr.m ? "Makes " + rcItem(cr.m).name + (cr.k > 1 ? " (" + cr.k + ")" : "") + "." : cr.fx || "") + "</p>";
      h += '<p class="sbt-note">Reagents: ' + esc(reagentText(cr)) + ".</p>";
      if (cr.at) h += '<p class="sbt-note">' + esc(near(cr.at)) + "</p>";
      h += '<p class="sbt-note">' + esc(craftLearn(cr)) + (cr.c ? " " + esc(craftColours(cr)) : "") + "</p>";
      h += '<p class="sbt-src">Recipe from the beta client' + esc(onBuild(RC && RC.build)) + (cr.cl ? "; the trainer's skill is Classic's (CMaNGOS)" : "") +
        (cr.rs ? "; the spell is Season of Discovery's, taught by an item new in Forever" : "") + ". Click for each reagent's tooltip.</p>";
    } else if (e.kind === "rare" && e.dun) {
      var lb = e.lb, got = lb.items.filter(function (i) { return !absent(i) && ITEMBYID[i]; }).map(function (i) { return ITEMBYID[i].name; });
      h += "<p>A rare spawn in " + esc(e.dun) + "." + (got.length ? " Drops: " + esc(got.join(", ")) + "." : "") + "</p>";
      h += '<p class="sbt-src">From players\' dungeon loot records, ' + esc(lootSrcText(lb.src)) + ". Click for the loot table.</p>";
    } else if (e.kind === "rare") {
      var rr = e.rr;
      if (rr.sub || rr.ty) h += "<p>" + esc([rr.sub ? "<" + rr.sub + ">" : "", rr.fam ? rr.fam + (rr.tame ? ", tameable by hunters" : "") : rr.ty || ""].filter(Boolean).join(" ")) + "</p>";
      h += '<p class="sbt-note">Spawn points: ' + esc(spots(rr)) + (rr.more ? ", and " + rr.more + " more" : "") + ".</p>";
      if (rr.rs) h += '<p class="sbt-note">Respawns ' + esc(respawn(rr.rs)) + " after a kill, in Classic.</p>";
      h += '<p class="sbt-src">Classic data (CMaNGOS): it may have moved, changed or gone in Forever. Points drawn on the beta client\'s maps' + esc(onBuild(RS && RS.build)) + ".</p>";
    } else if (e.kind === "pvprank") {
      var rk = e.rk;
      h += "<p>" + fmtN(rk.pts) + " rank points fill this rank" + (rk.week ? "; open from week " + rk.week + " of a season" : "") + ".</p>";
      if (rk.reward) h += '<p class="sbt-note">Reward, per Blizzard: ' + esc(rk.reward) + ".</p>";
      if (rk.lp) h += '<p class="sbt-note">Reaching it pays a Legacy Point.</p>';
      h += '<p class="sbt-src">Rank, points, week and Legacy Point from the beta client' + esc(onBuild(PV && PV.build)) + "; reading its curves as points per rank and weeks is ours. Rewards from Blizzard's Oct 7 post.</p>";
    }
    return h;
  }
  function buildIndex(d, items) {
    var dupName = {}, dupKey = {};
    (items || []).forEach(function (it) {
      if ((FI && FI.isJunk(it)) || it.era || unseenClassic(it)) return; // twins among the rows shown by default
      dupName[it.name] = (dupName[it.name] || 0) + 1;
      var k = it.name + "|" + (it.itemLevel || "");
      dupKey[k] = (dupKey[k] || 0) + 1;
    });
    (items || []).forEach(function (it) {
      if (FI && FI.isJunk(it)) return; // test, template and placeholder rows, as The Forge leaves them out
      if (it.setName) (SETROWS[it.setName] = SETROWS[it.setName] || []).push(it);
      ITEMBYID[it.id] = it;
      var er = effLvl(it), wearable = !!slotName(it.slot);
      var lvlTxt = er.quest ? "Quest level " + er.lvl : er.est && wearable ? "Level ~" + er.lvl + " (est.)" : it.reqLevel ? "Level " + it.reqLevel : "";
      var clsTxt = it.cls && it.cls.length && it.cls.length < 9 ? it.cls.map(function (c) { return c.charAt(0) + c.slice(1).toLowerCase(); }).join("/") : "";
      var meta = [it.era === "sod" ? "SoD-era data" : it.era === "retail" ? "Retail-era data" : "", it.ft === "new" || it.nw ? "New" : it.ft === "changed" ? "Changed" : "", it.est === "classic" ? "Classic stats (est.)" : "", it.sub, slotName(it.slot), lvlTxt, clsTxt,
        dupName[it.name] > 1 && it.itemLevel ? "ilvl " + it.itemLevel : "", it.sg ? "seen in game" : "",
        dupKey[it.name + "|" + (it.itemLevel || "")] > 1 ? (gist(it) || String((it.effects || [])[0] || "").replace(/^(Equip|Use|Chance on hit): /, "").slice(0, 60)) : "",
        it.sk ? it.sk[0] + (it.sk[1] ? " " + it.sk[1] : "") : ""].filter(function (x, i, a) { return x && a.indexOf(x) === i; });
      var st = it.stats || {}, words = Object.keys(st).map(function (k) { return STATWORDS[k] || (/SpellDamage$/.test(k) ? "spell damage spelldmg " + k.replace("SpellDamage", "") : k); });
      var from = (it.drops || []).map(function (d) { return d[1] + " " + d[0]; }).concat((it.quests || []).map(function (q) { return q[0] + " " + q[1] + " quest"; }));
      IDX.push({ kind: "item", cat: it.cat || "misc", sub: it.sub || "Other", name: it.name, icon: it.icon, q: it.quality || "unknown", it: it, meta: meta.join(" \u00b7 "),
        side: it.drops ? it.drops[0][1] + " \u00b7 " + it.drops[0][0] : it.quests ? "Quest: " + it.quests[0][0] : it.source, wear: wearable,
        text: [it.name, it.sub, it.type, slotName(it.slot), PROVENANCE.test(it.source || "") ? "" : it.source, it.setName, (it.effects || []).join(" "), words.join(" "), from.join(" "), clsTxt].join(" ").toLowerCase() });
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
    (d.systems || []).forEach(function (sy, i) {
      IDX.push({ kind: "page", cat: "system", sub: "System", name: sy.t, icon: sy.icon, meta: (sy.facts || []).length + " facts", topic: "systems:" + i, text: (sy.t + " " + (sy.facts || []).join(" ")).toLowerCase() });
    });
  }
  // A set's classes: the set table's list, else the classes its pieces are limited to, else every class that can
  // wear all of its pieces (Magister's Regalia is cloth: no class lock in Forever's data).
  function setRows(st) { // the piece ids the set table names ("Item 16685 - ..."), else wearable rows of that set name
    var rows = [];
    (st.pieces || []).forEach(function (pc) {
      var m = /^Item (\d+)/.exec(pc.n || ""), it = ITEMBYID[pc.id] || (m && ITEMBYID[m[1]]);
      if (it && rows.indexOf(it) === -1) rows.push(it);
    });
    if (rows.length) return rows;
    return (SETROWS[st.n] || []).filter(function (it) { return slotName(it.slot) && !it.era; }); // not its recipes or seed copies
  }
  function setClassOK(st, cls, lvl) {
    if (st.cls && st.cls.length) return st.cls.indexOf(cls) !== -1;
    var rows = setRows(st), locked = rows.filter(function (it) { return it.cls && it.cls.length; });
    if (locked.length) return locked.some(function (it) { return it.cls.indexOf(cls) !== -1; });
    if (!rows.length) return false; // nothing known about its pieces: not shown as fit for a class
    var hands = rows.filter(function (it) { return it.cat === "weapon" && /^(one-hand|main-hand|off-hand)$/.test(it.slot); });
    if (hands.length > 1 && ["WARRIOR", "ROGUE", "HUNTER"].indexOf(String(cls).toUpperCase()) === -1) return false; // two weapons: dual wield
    return !GK || !GK.canUse || rows.every(function (it) { return GK.canUse(cls, it, lvl || 60); });
  }
  function setLevel(e) {
    if (typeof e.lvlKey === "number") return e.lvlKey;
    var rows = setRows(e.st);
    return rows.length ? Math.max.apply(null, rows.map(lvlOf)) : null;
  }
  // One entry against the filters, as if category `cat` were picked (the chip counts ask per category).
  function passes(e, words, cat, chips) {
    if (cat !== "all" && e.cat !== cat) return false;
    if (!chips) {
      if (SQ.sub && e.sub !== SQ.sub) return false;
      if (SQ.qual && e.q !== SQ.qual) return false;
    }
    if (((e.kind === "item" && e.it.era) || e.era) && !SQ.era) return false;
    if (e.kind === "item" && unseenClassic(e.it) && !SQ.cl) return false;
    if (itemFilters(cat)) {
      var gear = GEARCAT[cat];
      if (gear && SQ.stat && (e.kind !== "item" || statOf(e.it, SQ.stat) <= 0)) return false;
      // sorting by a stat lists the items that have it, best first (not the whole database with the stat's owners on top)
      if (gear && SQ.sort && STATBY[SQ.sort] && (e.kind !== "item" || statOf(e.it, SQ.sort) <= 0)) return false;
      if (armorFilters(cat) && SQ.at.length && (e.kind !== "item" || !FI || SQ.at.indexOf(FI.armorType(e.it)) === -1)) return false;
      if (gear && SQ.ms && (e.kind !== "item" || !mainOK(e.it, SQ.ms))) return false;
      var fxk = fxKeys(cat);
      if (fxk.length && (e.kind !== "item" || !fxk.some(function (k) { return hasFx(e.it, k); }))) return false;
      if (SQ.src) {
        if (e.kind !== "item") return false;
        var dr = e.it.drops || [], qs = e.it.quests || [];
        if (SQ.src === "dungeon") { if (!dr.length) return false; }
        else if (SQ.src === "ft:new") { if (!(e.it.ft === "new" || e.it.nw)) return false; }
        else if (SQ.src.indexOf("ft:") === 0) { if (e.it.ft !== SQ.src.slice(3)) return false; }
        else if (SQ.src === "quest") { if (!qs.length) return false; }
        else if (!dr.some(function (d) { return d[0] === SQ.src; }) && !qs.some(function (q) { return q[1] === SQ.src; })) return false;
      }
    }
    if ((SQ.prof || SQ.sk) && (itemFilters(cat) || CRAFTCAT[cat])) { // a skill cap with no profession: any profession's items and recipes up to that skill
      var skr = e.kind === "item" ? e.it.sk : e.kind === "craft" ? [e.cr.p, craftSkill(e.cr)] : null;
      if (!skr) return false;
      if (SQ.prof && skr[0] !== SQ.prof) return false;
      if (SQ.sk && (skr[1] || 0) > +SQ.sk) return false;
    }
    if (SQ.lvl) {
      if (e.kind === "item") { if (lvlOf(e.it) > +SQ.lvl) return false; }
      else if (e.kind === "itemset") { var sl = setLevel(e); if (sl && sl > +SQ.lvl) return false; }
      else if (typeof e.lvlKey === "number") { if (e.lvlKey > +SQ.lvl) return false; } // no known level: no limit
    }
    if (SQ.cls) {
      if (e.kind === "item") {
        if (e.it.cls && e.it.cls.indexOf(SQ.cls) === -1) return false;
        if (GK && GK.canUse && !GK.canUse(SQ.cls, e.it, +SQ.lvl || 60)) return false;
      }
      else if (e.kind === "itemset") { if (!setClassOK(e.st, SQ.cls, +SQ.lvl || 60)) return false; }
      else if (e.cls) { if (e.cls !== SQ.cls) return false; }
      else if (!CLASSLESS[e.kind]) return false;
    }
    for (var i = 0; i < words.length; i++) if (e.text.indexOf(words[i]) === -1) return false;
    return true;
  }
  function matches() {
    var words = SQ.q.toLowerCase().split(/\s+/).filter(Boolean), live = itemFilters(SQ.cat), gear = GEARCAT[SQ.cat];
    var sortBy = live && (gear || !STATBY[SQ.sort]) ? SQ.sort : "", statBy = live && gear ? SQ.stat : "";
    return IDX.filter(function (e) { return passes(e, words, SQ.cat, false); }).sort(function (a, b) {
      // names that start with the search come first, unless a sort, stat or level cap was picked: then that decides
      var ql = !sortBy && !statBy && !SQ.lvl && SQ.q.toLowerCase(), as = ql && a.name.toLowerCase().indexOf(ql) === 0 ? 0 : 1, bs = ql && b.name.toLowerCase().indexOf(ql) === 0 ? 0 : 1;
      if (as !== bs) return as - bs;
      if (sortBy && a.kind === "item" && b.kind === "item") {
        var sa = sortBy === "ilvl" ? +a.it.itemLevel || 0 : sortBy === "req" ? lvlOf(a.it) : statOf(a.it, sortBy);
        var sb = sortBy === "ilvl" ? +b.it.itemLevel || 0 : sortBy === "req" ? lvlOf(b.it) : statOf(b.it, sortBy);
        if (sa !== sb) return sb - sa;
      } else if (sortBy && (a.kind === "item") !== (b.kind === "item")) return a.kind === "item" ? -1 : 1;
      if (statBy) {
        var av = statOf(a.it, statBy), bv = statOf(b.it, statBy);
        if (av !== bv) return bv - av;
      }
      if (SQ.lvl) {
        // A level cap is set: gear nearest the cap first, so the filter is
        // visibly doing its job instead of re-showing the same level 1 epics.
        var al = (a.it && lvlOf(a.it)) || (a.kind === "itemset" && setLevel(a)) || a.lvlKey || 0, bl = (b.it && lvlOf(b.it)) || (b.kind === "itemset" && setLevel(b)) || b.lvlKey || 0;
        if (al !== bl) return bl - al;
      }
      if (a.kind === b.kind && KINDSORT[a.kind]) { var ks = KINDSORT[a.kind](a, b); if (ks) return ks; }
      var aq = QUAL.indexOf(a.q), bq = QUAL.indexOf(b.q);
      if (aq !== bq) return bq - aq;
      return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
    });
  }
  // Lists that read best in their own order: recipes by skill (nearest a skill cap first), ranks 1 to 14, rares by level.
  var KINDSORT = {
    craft: function (a, b) {
      var x = craftSkill(a.cr), y = craftSkill(b.cr);
      if (!x !== !y) return x ? -1 : 1; // nothing known about its skill: last either way
      return SQ.sk ? y - x : x - y;
    },
    pvprank: function (a, b) { return a.rk.r - b.rk.r; },
    rare: function (a, b) { return (a.lvlKey || 0) - (b.lvlKey || 0); }
  };
  // Dungeons in level order, from codex/loot.json; only those with known loot.
  function fillSources() {
    var sel = document.getElementById("dbf-src");
    if (!sel || !LOOT || sel.getAttribute("data-filled")) return;
    sel.setAttribute("data-filled", "1");
    [].slice.call(sel.querySelectorAll("option[data-fb]")).forEach(function (o) { o.remove(); }); // a link's stand-in, now listed for real
    sel.innerHTML += LOOT.dungeons.filter(function (d) { var n = lootCount(d); return n.drops || n.quests; }).map(function (d) {
      return '<option value="' + esc(d.name) + '">' + esc(d.name) + (d.levels ? " (" + d.levels[0] + "\u2013" + d.levels[1] + ")" : "") + "</option>";
    }).join("");
    ensureSrcOpt(sel);
  }
  // A source from a link (?src=...) the list lacks gets its own option, as plain text, so it shows and Clear removes it.
  function ensureSrcOpt(sel) {
    if (!sel) return;
    if (SQ.src && ![].some.call(sel.options, function (o) { return o.value === SQ.src; })) { var o = new Option(SQ.src, SQ.src); o.setAttribute("data-fb", "1"); sel.add(o); }
    sel.value = SQ.src;
  }
  function drawSearch() {
    var box = document.getElementById("dbs");
    if (!box) return;
    var active = true; // results always show; typing or a chip narrows them
    function eraOK(e) { return !(((e.kind === "item" && e.it.era) || e.era) && !SQ.era) && !(e.kind === "item" && unseenClassic(e.it) && !SQ.cl); }
    var words0 = SQ.q.toLowerCase().split(/\s+/).filter(Boolean);
    var pool = IDX.filter(function (e) { return passes(e, words0, SQ.cat, true); });
    var subs = [];
    pool.forEach(function (e) { if (SQ.cat !== "all" && (!SQ.qual || e.q === SQ.qual) && subs.indexOf(e.sub) === -1) subs.push(e.sub); });
    subs.sort(function (a, b) {
      var ai = SQ.cat === "craft" ? -1 : SUBFIRST.indexOf(a), bi = SQ.cat === "craft" ? -1 : SUBFIRST.indexOf(b); // professions: A to Z
      if (ai !== -1 || bi !== -1) return (ai === -1 ? 99 : ai) - (bi === -1 ? 99 : bi);
      return /^Unknown|^Other/.test(a) ? 1 : /^Unknown|^Other/.test(b) ? -1 : a < b ? -1 : 1;
    });
    if (SQ.sub && SQ.cat !== "all" && subs.indexOf(SQ.sub) === -1) subs.push(SQ.sub);
    var quals = QUAL.filter(function (q) { return q === SQ.qual || pool.some(function (e) { return e.q === q && (!SQ.sub || e.sub === SQ.sub); }); });
    // Each chip counts what clicking it would list: the search and the filters applied, sub and quality cleared.
    var words = words0, perCat = { all: 0 };
    IDX.forEach(function (e) {
      if (passes(e, words, e.cat, true)) perCat[e.cat] = (perCat[e.cat] || 0) + 1;
      if (passes(e, words, "all", true)) perCat.all++;
    });
    document.getElementById("dbs-cats").innerHTML = CATS.map(function (c) {
      var n = perCat[c[0]] || 0;
      if (!n && SQ.cat === c[0]) return '<button type="button" data-dbcat="' + c[0] + '" class="on">' + esc(c[1]) + "<i>0</i></button>"; // the picked chip stays, to unpick
      return n ? '<button type="button" data-dbcat="' + c[0] + '"' + (SQ.cat === c[0] ? ' class="on"' : "") + ">" + esc(c[1]) + "<i>" + n + "</i></button>" : "";
    }).join("");
    var sr = document.getElementById("dbs-subs");
    sr.hidden = !(subs.length > 1 || (quals.length > 1 && active) || SQ.sub || SQ.qual);
    sr.innerHTML = (subs.length > 1 || SQ.sub ? subs.map(function (x) { return '<button type="button" data-dbsub="' + esc(x) + '"' + (SQ.sub === x ? ' class="on"' : "") + ">" + esc(x) + "</button>"; }).join("") : "") +
      (quals.length > 1 || SQ.qual ? '<span class="dbs-q">' + quals.map(function (q) { return '<button type="button" class="q-' + q + (SQ.qual === q ? " on" : "") + '" data-dbqual="' + q + '">' + q + "</button>"; }).join("") + "</span>" : "");
    if (window.TipKit) TipKit.hide();
    var out = document.getElementById("dbs-out"), res = active ? matches() : [];
    // With a proc filter on, say how many of the procs listed have a known chance; the rest say "not known yet".
    var pxAll = FI && FI.chanceKnown && (SQ.fx.indexOf("hit") !== -1 || SQ.fx.indexOf("equip") !== -1)
      ? res.filter(function (e) { return e.kind === "item" && (hasFx(e.it, "hit") || hasFx(e.it, "equip")); }) : null;
    var pxk = pxAll ? pxAll.filter(function (e) { return FI.chanceKnown(e.it); }).length : 0;
    document.getElementById("dbs-n").textContent = active ? res.length + (res.length === 1 ? " result" : " results") + (SQ.lvl ? " usable at " + SQ.lvl : "") +
      (pxAll && pxAll.length ? "; proc chance known for " + pxk + " of " + pxAll.length : "") : IDX.length + " entries";
    document.getElementById("dbs-n").title = SQ.lvl ? "Items the client stores no required level for use item level - 5; their rows say \"Level ~N (est.)\"." : "";
    fillSources();
    out.hidden = !active;
    if (!active) return;
    out.innerHTML = res.length ? res.slice(0, SHOWN).map(function (e) {
      var i = IDX.indexOf(e), fxc = e.kind === "item" && e.wear ? fxChip(e.it) : "";
      var hasSbt = !!SBT[e.kind];
      return '<button type="button" class="dbs-row' + (e.kind === "item" || e.kind === "craft" ? " q-" + esc(e.q) : "") + '" data-dbi="' + i + '"' + (e.kind === "item" ? ' data-tipkit="1"' : hasSbt ? ' data-sbt="1"' : "") + ">" +
        '<span class="dbs-ic">' + img(e.icon || "inv_misc_questionmark") + "</span>" +
        '<span class="dbs-t"><b>' + esc(e.name) + "</b><em>" + sortVal(e) + esc(SQ.sort === "ilvl" && e.kind === "item" ? e.meta.split(" \u00b7 ").filter(function (x) { return x !== "ilvl " + e.it.itemLevel; }).join(" \u00b7 ") : e.meta) + "</em>" + (fxc ? '<i class="dbs-fx">' + esc(fxc) + "</i>" : "") + "</span>" +
        '<span class="dbs-s' + (e.kind === "item" && isEst(e) ? " dbs-est" : "") + '">' + esc(e.kind === "item" ? sideOf(e) : (e.side || { place: "The new world", perk: "The Legacy system", spell: "Spells", system: "Systems" }[e.cat] || "")) + "</span></button>";
    }).join("") + (res.length > SHOWN ? '<button type="button" class="dbs-more" data-dbmore="1">Show all ' + res.length + "</button>" : "")
      : '<p class="dbs-none">Nothing matches. Try fewer words or clear a filter.</p>';
    if (window.TipKit && GK) out.querySelectorAll(".dbs-row[data-tipkit]").forEach(function (row) {
      TipKit.hover(row, function (el) { return GK.itemTip(IDX[+el.getAttribute("data-dbi")].it); }, function () { return "itemtip"; });
    });
    if (window.TipKit) out.querySelectorAll(".dbs-row[data-sbt]").forEach(function (row) {
      TipKit.hover(row, function (el) { return sbTip(IDX[+el.getAttribute("data-dbi")]); }, function () { return "itemtip"; });
    });
  }
  // The number a row is filtered or sorted by, shown before its meta ("+24 Stamina", "ilvl 63").
  function sortVal(e) {
    if (e.kind !== "item") return "";
    var gear = GEARCAT[SQ.cat], k = gear && SQ.sort && STATBY[SQ.sort] ? SQ.sort : gear && SQ.stat ? SQ.stat : "";
    var h = k ? '<i class="dbs-sv">' + (k === "reflect" || k === "armor" || k === "blockValue" || /^proc|^use/.test(k) ? "" : "+") + statOf(e.it, k) + esc(STATBY[k][2]) + "</i> " : "";
    if (SQ.sort === "ilvl" && e.it.itemLevel) h += '<i class="dbs-sv">ilvl ' + esc(e.it.itemLevel) + "</i> ";
    return h;
  }
  function isEst(e) { return !!(FI && e.wear && !FI.hasSource(e.it)); }
  function sideOf(e) {
    if (isEst(e)) return FI.estimateSource(e.it, LOOT && LOOT.dungeons) || e.side;
    return e.side;
  }
  function syncUrl() {
    try {
      var u = new URL(location.href);
      ["q", "cat", "sub", "qual", "lvl", "stat", "src", "cls", "prof", "sk", "ms", "sort"].forEach(function (k) { var v = k === "q" ? SQ.q.trim() : SQ[k]; if (v && v !== "all") u.searchParams.set(k, v); else u.searchParams.delete(k); });
      if (SQ.at.length) u.searchParams.set("at", SQ.at.join(",")); else u.searchParams.delete("at");
      ["era", "cl"].forEach(function (k) { if (SQ[k]) u.searchParams.set(k, "1"); else u.searchParams.delete(k); });
      u.searchParams.delete("rf");
      if (SQ.fx.length) u.searchParams.set("fx", SQ.fx.join(",")); else u.searchParams.delete("fx");
      history.replaceState(null, "", u.pathname + u.search + u.hash);
    } catch (e) {}
  }
  function initSearch() {
    var box = document.getElementById("dbs");
    if (!box) return;
    box.innerHTML = '<div class="dbs-bar"><input type="search" id="dbs-qi" placeholder="Search items, recipes, spells, talents, rares, dungeons" autocomplete="off" spellcheck="false" aria-label="Search the Database">' +
      '<span id="dbs-n"></span></div><div class="dbs-cats" id="dbs-cats" role="group" aria-label="Type"></div>' +
      '<div class="dbs-filt" id="dbs-filt"><input type="number" id="dbf-lvl" min="1" max="60" placeholder="Max level" aria-label="Max level: show only what is usable at that level">' +
      '<select id="dbf-cls" aria-label="Class"><option value="">Any class</option>' + CLASSES9.map(function (c) { return '<option>' + c + '</option>'; }).join("") + '</select>' +
      '<select id="dbf-prof" aria-label="Profession"><option value="">Any profession</option>' + PROFS.map(function (c) { return '<option>' + c + '</option>'; }).join("") + '</select>' +
      '<input type="number" id="dbf-sk" min="1" max="300" placeholder="Max skill" aria-label="Maximum profession skill">' +
      '<select id="dbf-stat" aria-label="Stat"><option value="">Any stat</option>' + STATF.map(function (f) { return '<option value="' + f[0] + '">' + f[1] + "</option>"; }).join("") + "</select>" +
      '<select id="dbf-ms" aria-label="Main stat"><option value="">Any main stat</option>' + MAINS.map(function (m) { return '<option value="' + m[0] + '">' + m[1] + (m[0] === "sta" || m[0] === "spirit" ? "" : " main stat") + "</option>"; }).join("") + "</select>" +
      '<select id="dbf-sort" aria-label="Sort items by"><option value="">Sort: best match</option><option value="ilvl">Sort: item level</option><option value="req">Sort: required level</option>' + STATF.map(function (f) { return '<option value="' + f[0] + '">Sort: ' + f[1].toLowerCase() + "</option>"; }).join("") + "</select>" +
      '<span class="dbf-at" role="group" aria-label="Armor type">' + ARMORS.map(function (a) { return '<button type="button" data-dbat="' + a + '" aria-pressed="false">' + a + "</button>"; }).join("") + "</span>" +
      '<span class="dbf-fx" role="group" aria-label="Effects">' + FXP.map(function (f) { var tip = esc(f[2] + " Read from the item data, or its tooltip text."); return '<button type="button" data-dbfx="' + f[0] + '" aria-pressed="false" title="' + tip + '" data-tip="' + tip + '">' + esc(f[1]) + "</button>"; }).join("") + "</span>" +
      '<select id="dbf-src" aria-label="Where it comes from"><option value="">Any source</option><option value="dungeon">Any dungeon drop</option><option value="quest">Any quest reward</option><option value="ft:new">New in Forever</option><option value="ft:changed">Changed from Classic</option></select>' +
      '<button type="button" id="dbf-era" aria-pressed="false" title="The branch carries Season of Discovery and retail leftovers. Hidden unless you ask; every such row is labeled." data-tip="The branch carries Season of Discovery and retail leftovers. Hidden unless you ask; every such row is labeled.">SoD and retail data: hidden</button>' +
      '<button type="button" id="dbf-cl" aria-pressed="false" title="Items Forever&#39;s data has an id for but nobody has seen in Forever yet, with their WoW Classic stats. The ones a Forever loot record lists are always shown." data-tip="Items Forever&#39;s data has an id for but nobody has seen in Forever yet, with their WoW Classic stats. Forever may have changed or removed them. The ones a Forever loot record lists are always shown, labeled Classic stats.">Classic items not seen in Forever: hidden</button>' +
      '<button type="button" id="dbf-x" hidden>Clear</button></div>' +
      '<div class="dbs-subs" id="dbs-subs" hidden></div><div class="dbs-out" id="dbs-out" hidden></div>';
    try {
      var sp = new URLSearchParams(location.search);
      SQ.q = sp.get("q") || ""; SQ.cat = sp.get("cat") || "all"; SQ.sub = sp.get("sub") || ""; SQ.qual = sp.get("qual") || "";
      SQ.lvl = sp.get("lvl") || ""; SQ.stat = STATBY[rfKey(sp.get("stat"))] ? rfKey(sp.get("stat")) : ""; SQ.src = sp.get("src") || "";
      SQ.cls = CLASSES9.indexOf(sp.get("cls")) !== -1 ? sp.get("cls") : ""; SQ.prof = PROFS.indexOf(sp.get("prof")) !== -1 ? sp.get("prof") : ""; SQ.sk = sp.get("sk") || "";
      SQ.era = sp.get("era") === "1"; SQ.cl = sp.get("cl") === "1";
      SQ.fx = String(sp.get("fx") || "").split(",").filter(function (k, i, a) { return a.indexOf(k) === i && FXP.some(function (f) { return f[0] === k; }); });
      if (sp.get("rf") === "1" && SQ.fx.indexOf("rf") === -1) SQ.fx.push("rf");   // older links
      SQ.ms = MAINS.some(function (m) { return m[0] === sp.get("ms"); }) ? sp.get("ms") : "";
      SQ.sort = sp.get("sort") === "ilvl" || sp.get("sort") === "req" || STATBY[rfKey(sp.get("sort"))] ? rfKey(sp.get("sort")) : "";
      SQ.at = String(sp.get("at") || "").split(",").filter(function (a) { return ARMORS.indexOf(a) !== -1; });
    } catch (e) {}
    var qi = document.getElementById("dbs-qi"), tmr = null;
    function fEl(id) { return document.getElementById(id); }
    function readFilt() {
      SQ.lvl = fEl("dbf-lvl").value; SQ.cls = fEl("dbf-cls").value; SQ.prof = fEl("dbf-prof").value; SQ.sk = fEl("dbf-sk").value;
      SQ.stat = fEl("dbf-stat").value; SQ.ms = fEl("dbf-ms").value;
      SQ.sort = fEl("dbf-sort").value || (STATBY[SQ.sort] && !GEARCAT[SQ.cat] ? SQ.sort : ""); // a stat sort set aside here is kept
      var srcSel = fEl("dbf-src");
      SQ.src = srcSel.value;
      syncFiltUI();
      SHOWN = 60; drawSearch(); syncUrl();
    }
    var ftmr = null;
    ["dbf-lvl", "dbf-sk"].forEach(function (id) { fEl(id).addEventListener("input", function () { clearTimeout(ftmr); ftmr = setTimeout(readFilt, 200); }); });
    ["dbf-cls", "dbf-prof", "dbf-stat", "dbf-src", "dbf-ms", "dbf-sort"].forEach(function (id) { fEl(id).addEventListener("change", readFilt); });
    // Toggle buttons and the Clear button follow SQ, so a shared link opens with its filters shown.
    SYNC = syncFiltUI; // showInDb switches category from outside this function
    function syncFiltUI() {
      var b = fEl("dbf-era");
      b.textContent = SQ.era ? "SoD and retail data: shown" : "SoD and retail data: hidden";
      b.setAttribute("aria-pressed", String(SQ.era));
      b.classList.toggle("on", SQ.era);
      var bc = fEl("dbf-cl");
      if (bc) {
        bc.textContent = SQ.cl ? "Classic items not seen in Forever: shown" : "Classic items not seen in Forever: hidden";
        bc.setAttribute("aria-pressed", String(SQ.cl));
        bc.classList.toggle("on", SQ.cl);
      }
      box.querySelectorAll("[data-dbfx]").forEach(function (x) { var on = SQ.fx.indexOf(x.getAttribute("data-dbfx")) !== -1; x.classList.toggle("on", on); x.setAttribute("aria-pressed", String(on)); });
      box.querySelectorAll("[data-dbat]").forEach(function (x) { var on = SQ.at.indexOf(x.getAttribute("data-dbat")) !== -1; x.classList.toggle("on", on); x.setAttribute("aria-pressed", String(on)); });
      var live = itemFilters(SQ.cat);
      ["dbf-sort", "dbf-src", "dbf-cl"].forEach(function (id) { fEl(id).hidden = !live; });
      ["dbf-prof", "dbf-sk"].forEach(function (id) { fEl(id).hidden = !live && !CRAFTCAT[SQ.cat]; }); // recipes filter by them too
      ["dbf-stat", "dbf-ms"].forEach(function (id) { fEl(id).hidden = !live || !GEARCAT[SQ.cat]; }); // gear stats: not on potions or recipes
      [].forEach.call(fEl("dbf-sort").options, function (o) { o.hidden = o.disabled = !!STATBY[o.value] && !GEARCAT[SQ.cat]; });
      fEl("dbf-sort").value = STATBY[SQ.sort] && !GEARCAT[SQ.cat] ? "" : SQ.sort;
      box.querySelector(".dbf-fx").hidden = !live;
      box.querySelectorAll("[data-dbfx]").forEach(function (x) { x.hidden = !GEARCAT[SQ.cat] && x.getAttribute("data-dbfx") !== "rf"; });
      box.querySelector(".dbf-at").hidden = !live || !armorFilters(SQ.cat);
      fEl("dbf-sk").placeholder = SQ.prof ? "Max skill" : "Max skill (any profession)";
      fEl("dbf-x").hidden = !(SQ.lvl || SQ.cls || SQ.prof || SQ.sk || SQ.stat || SQ.src || SQ.ms || SQ.sort || SQ.at.length || SQ.fx.length);
    }
    fEl("dbf-era").addEventListener("click", function () { SQ.era = !SQ.era; syncFiltUI(); SHOWN = 60; drawSearch(); syncUrl(); });
    fEl("dbf-cl").addEventListener("click", function () { SQ.cl = !SQ.cl; syncFiltUI(); SHOWN = 60; drawSearch(); syncUrl(); });
    box.querySelectorAll("[data-dbfx]").forEach(function (x) {
      x.addEventListener("click", function () {
        var k = x.getAttribute("data-dbfx"), i = SQ.fx.indexOf(k);
        if (i === -1) SQ.fx.push(k); else SQ.fx.splice(i, 1);
        syncFiltUI(); SHOWN = 60; drawSearch(); syncUrl();
      });
    });
    box.querySelectorAll("[data-dbat]").forEach(function (x) {
      x.addEventListener("click", function () {
        var a = x.getAttribute("data-dbat"), i = SQ.at.indexOf(a);
        if (i === -1) SQ.at.push(a); else SQ.at.splice(i, 1);
        syncFiltUI(); SHOWN = 60; drawSearch(); syncUrl();
      });
    });
    function clearFilt() {
      ["dbf-lvl", "dbf-sk", "dbf-cls", "dbf-prof", "dbf-stat", "dbf-src", "dbf-ms", "dbf-sort"].forEach(function (id) { fEl(id).value = ""; });
      SQ.lvl = SQ.cls = SQ.prof = SQ.sk = SQ.stat = SQ.src = SQ.ms = SQ.sort = ""; SQ.at = []; SQ.fx = [];
    }
    CLEARF = clearFilt;
    fEl("dbf-x").addEventListener("click", function () { clearFilt(); readFilt(); });
    qi.value = SQ.q;
    if (SQ.lvl) fEl("dbf-lvl").value = SQ.lvl;
    if (SQ.stat) fEl("dbf-stat").value = SQ.stat;
    fEl("dbf-cls").value = SQ.cls; fEl("dbf-prof").value = SQ.prof; fEl("dbf-sk").value = SQ.sk;
    fEl("dbf-ms").value = SQ.ms; fEl("dbf-sort").value = SQ.sort;
    ensureSrcOpt(fEl("dbf-src"));
    syncFiltUI();
    qi.addEventListener("input", function () {
      clearTimeout(tmr);
      tmr = setTimeout(function () { SQ.q = qi.value; SHOWN = 60; drawSearch(); syncUrl(); }, 120);
    });
    box.addEventListener("click", function (e) {
      var b = e.target.closest && e.target.closest("button");
      if (!b || !box.contains(b)) return;
      if (b.hasAttribute("data-dbcat")) { var c = b.getAttribute("data-dbcat"); SQ.cat = SQ.cat === c && c !== "all" ? "all" : c; SQ.sub = ""; SQ.qual = ""; SHOWN = 60; syncFiltUI(); }
      else if (b.hasAttribute("data-dbsub")) { var s2 = b.getAttribute("data-dbsub"); SQ.sub = SQ.sub === s2 ? "" : s2; SHOWN = 60; }
      else if (b.hasAttribute("data-dbqual")) { var q2 = b.getAttribute("data-dbqual"); SQ.qual = SQ.qual === q2 ? "" : q2; SHOWN = 60; }
      else if (b.hasAttribute("data-dbmore")) { SHOWN = 1e9; }
      else if (b.hasAttribute("data-dbi")) {
        var en = IDX[+b.getAttribute("data-dbi")];
        if (en.kind === "item") {
          if (window.TipKit && GK && (TipKit.touchy() || e.detail === 0)) TipKit.openSheet(GK.itemTip(en.it), [], { cls: "itemtip", owner: "db:" + en.name });
          return;
        }
        if (en.kind === "craft") { openCraft(en.cr); return; }
        if (en.kind === "rare" && en.dun) { openLoot(en.dun); return; }
        if (SBT[en.kind]) {
          if (window.TipKit && (TipKit.touchy() || e.detail === 0)) { TipKit.openSheet(sbTip(en), [], { cls: "itemtip", owner: "db:" + en.name }); return; }
          if (!en.href) return;
        }
        if (en.topic) { openTopic(en.topic); return; }
        if (en.href && !document.querySelector(en.href)) {
          var PAGE_OF = { "#world": "/world/", "#classes": "/classes/", "#ranks": "/rankings/", "#pvp": "/codex/" };
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

    var SOUL_CC = { WARRIOR: "#C79C6E", PALADIN: "#F58CBA", HUNTER: "#ABD473", ROGUE: "#FFF569", PRIEST: "#FFFFFF", SHAMAN: "#0070DE", MAGE: "#69CCF0", WARLOCK: "#9482C9", DRUID: "#FF7D0A" };
    function soulLabel(k) { return k ? k.charAt(0) + k.slice(1).toLowerCase() : "Unsorted"; }
    if (PAGE === "classes" && d.souls && d.souls.list.length) {
      var sl = d.souls.list;
      var sCounts = {};
      sl.forEach(function (s) { var k = s[2] || "_"; sCounts[k] = (sCounts[k] || 0) + 1; });
      var chipKeys = Object.keys(SOUL_CC).filter(function (k) { return sCounts[k]; });
      function crest(k) { return k && k !== "_" ? '<img class="soulico" src="' + CDN + "classicon_" + k.toLowerCase() + '.jpg" alt="" loading="lazy">' : '<img class="soulico" src="' + CDN + 'spell_shadow_soulleech_3.jpg" alt="" loading="lazy">'; }
      function fxHtml(t) { return esc(t).replace(/(&#?\w+;)|(\d+(?:\.\d+)?%?)/g, function (m, ent, num) { return ent || "<em>" + num + "</em>"; }); } // never inside an entity
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

    // Class changes: the client diff between the level-20 and level-30 beta builds, per class.
    var cc = d.classChanges;
    var ccKeys = Object.keys(cc);
    var ccTotal = ccKeys.reduce(function (n, k) { return n + cc[k].length; }, 0);
    var ccHtml = (d.classNote ? '<p class="board-sub">' + esc(d.classNote) + ' <a href="/news/level-30/#classes">Every change, with Blizzard\'s notes &rsaquo;</a></p>' : "") +
      '<div class="soulchips">' +
      '<button type="button" class="soulchip on" data-ccf="">All ' + ccTotal + "</button>" +
      ccKeys.map(function (k) {
        return '<button type="button" class="soulchip" data-ccf="' + esc(k) + '" style="--cc:' + (CLASS_COLOUR[k] || "#8b93a7") + '">' +
          '<img class="soulico" src="' + CDN + 'classicon_' + k.toLowerCase() + '.jpg" alt="" loading="lazy">' + esc(k) + " " + cc[k].length + "</button>";
      }).join("") + "</div>" +
      '<div class="soulgrid" id="ccgrid">' + ccKeys.map(function (k) {
        return cc[k].map(function (a) {
          return '<div class="soulc hasspell" data-ck="' + esc(k) + '" data-name="' + esc(a[0]) + '" style="--cc:' + (CLASS_COLOUR[k] || "#8b93a7") + '">' +
            '<span class="soulring"><img class="soulico" src="' + CDN + esc(a[2] || "inv_misc_questionmark") + '.jpg" alt="" loading="lazy"></span>' +
            '<span class="soulhead"><b>' + esc(a[0]) + "</b><i>" + esc(k + (a[3] ? " \u00b7 build " + a[3] : "")) + "</i></span>" +
            "<p>" + esc(a[1]) + "</p></div>";
        }).join("");
      }).join("") + "</div>";
    if (PAGE === "classes") section("classes", "Class changes in the level-30 builds", ccHtml);

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
      '<h3 id="zones">Zones</h3>' + placecards(w.zones) + '<h3 id="dungeons">Dungeons</h3>' + placecards(w.dungeons) +
      '<h3 id="loot">Dungeon loot</h3><p class="loot-lede">Every dungeon in level order: who drops what, rare spawns and quest rewards. The client has no Dungeon Journal, so these are players\' loot records from the beta.</p><div id="lootbox"><p class="loot-lede">Loading the loot tables\u2026</p></div>' +
      '<h3 id="raids">Raids</h3>' + placecards(w.raids) + '<h3 id="battlegrounds">Battlegrounds</h3>' + placecards(w.battlegrounds));
    // One section on this page, so the bar jumps between its parts instead.
    if (PAGE === "world") nav = [["zones", "Zones"], ["dungeons", "New dungeons"], ["loot", "Dungeon loot"], ["raids", "Raids"], ["battlegrounds", "Battlegrounds"]]
      .map(function (x) { return '<a href="#' + x[0] + '">' + x[1] + "</a>"; });

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
    if (PAGE === "db") section("pvp", "PvP ranks", '<p class="board-sub">The honor ladder as the beta client defines it. Search a rank by name above; Blizzard\'s rewards sit beside each one.</p>' +
      '<div id="pvpbox"><p class="board-sub">Loading the rank table\u2026</p></div>');

    // Hero stat band: the Codex counts itself.
    var nDun = w.dungeons.length, nRaid = w.raids.length,
      nPerk = d.legacy.trees.reduce(function (a, t) { return a + t.perks.length; }, 0),
      nCC = Object.keys(d.classChanges).reduce(function (a, k) { return a + d.classChanges[k].length; }, 0);
    function stripChip(s) {
      return '<a href="' + s[2] + '" style="--img:url(/codex/img/' + s[3] + '.jpg)"><b>' + s[0] + "</b><span>" + s[1] + "</span></a>";
    }
    var nSouls = d.souls && d.souls.list ? d.souls.list.length : 0;
    var hero = '<div class="cxstrip" id="cxstrip">' +
      [[nPerk, "Legacy perks", "/codex/#legacy", "stat-legacy"], [nDun, "dungeons", "/world/#world", "stat-dungeons"], [nRaid, "raids", "/world/#world", "stat-raids"],
        [nCC, "class changes", "/classes/#classes", "stat-classes"]]
        .concat(nSouls ? [[nSouls, "shoulder souls", "/classes/#souls", "the-barrow-deeps"]] : [])
        .map(stripChip).join("") + "</div>";
    fetch("/codex/counts.json", { cache: "no-store" }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; }).then(function (n) {
      var el = document.getElementById("cxstrip");
      if (!n || !el) return;
      el.innerHTML += [[n.book, "class spells", "/codex/?cat=spell", "city-of-dalaran"],
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
      // a strip chip into the Database search switches category in place, without reloading the page
      var a = e.target.closest && e.target.closest(".cxstrip a[href^='/codex/?cat=']");
      if (a && document.getElementById("dbs-qi")) { e.preventDefault(); showInDb({ cat: a.getAttribute("href").split("cat=")[1] }); }
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
    if (PAGE === "db" || PAGE === "world") fetch("/codex/loot.json", { cache: "no-store" }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; }).then(function (j) {
      if (!j || !j.dungeons) return;
      LOOT = j;
      if (window.ForgeGear && window.ForgeGear.extras) window.ForgeGear.extras({ dungeons: j.dungeons });
      fillSources();
      addLootRares();
      if (document.getElementById("dbs-out")) drawSearch();
      var box = document.getElementById("lootbox");
      if (box) {
        box.innerHTML = lootTiles();
        box.addEventListener("click", function (e) {
          var b = e.target.closest && e.target.closest("[data-loot]");
          if (b && !b.disabled) openLoot(b.getAttribute("data-loot"));
        });
        var key = function (n) { return String(n).toLowerCase().replace(/^the /, ""); }, byKey = {};
        LOOT.dungeons.forEach(function (d) { if (lootCount(d).drops) byKey[key(d.name)] = d; });
        document.querySelectorAll(".place[data-name]").forEach(function (card) {
          var d = byKey[key(card.getAttribute("data-name"))];
          if (!d) return;
          var b = document.createElement("button");
          b.type = "button"; b.className = "place-loot"; b.setAttribute("data-loot", d.name);
          b.textContent = "Loot table: " + lootCount(d).drops + " drops";
          b.addEventListener("click", function () { openLoot(d.name); });
          card.appendChild(b);
        });
        var want = /[?&]loot=([^&]+)/.exec(location.search);
        if (want) openLoot(decodeURIComponent(want[1].replace(/\+/g, " ")));
      }
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
      function getJson(u) { return fetch(u, { cache: "no-store" }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; }); }
      var gotRc = getJson("/codex/recipes.json"), gotRs = getJson("/codex/rares.json"), gotPv = getJson("/codex/pvp.json");
      gotRc.then(function (rc) { if (rc && rc.recipes) { buildCrafts(rc); drawSearch(); } });
      gotRs.then(function (rs) { if (rs && rs.rares) { buildRares(rs); drawSearch(); } });
      gotPv.then(function (pv) { if (pv && pv.ranks) { buildRanks(pv); drawPvp(pv); drawSearch(); } });
      Promise.all([gotRc, gotRs, gotPv]).then(function (g) {
        var el = document.getElementById("cxstrip");
        if (!el) return;
        // the counts the category chips show by default: no branch leftovers, and the dungeon rares when the loot records are in
        var nDunRare = LOOT ? LOOT.dungeons.reduce(function (a, d) { return a + d.bosses.filter(function (b) { return b.kind === "rare"; }).length; }, 0) : 0;
        el.innerHTML += [g[0] && g[0].recipes && [fmtN(g[0].recipes.filter(function (x) { return !x.e; }).length), "recipes", "/codex/?cat=craft", "excavation-site"],
          g[1] && g[1].rares && [g[1].rares.length + nDunRare, "rare spawns", "/codex/?cat=rare", "krol-dok-stronghold"],
          g[2] && g[2].ranks && [g[2].ranks.length, "PvP ranks", "/codex/#pvp", "ruins-of-lordaeron"]].filter(Boolean).map(stripChip).join("");
      });
      // Then the full client database replaces the curated seed.
      fetch("/plan/items-db.json", { cache: "no-store" }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; }).then(function (db) {
        if (!db || !Array.isArray(db.items) || !db.items.length) return;
        try { GK = ForgeGear({ items: db, get: function () { return {}; } }); } catch (e) {}
        IDX = IDX.filter(function (e) { return e.kind !== "item"; }); SETROWS = {}; ITEMBYID = {};
        buildIndex({ world: { zones: [], dungeons: [], raids: [], battlegrounds: [] }, legacy: { trees: [] }, systems: [] }, db.items);
        addReagents();
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
