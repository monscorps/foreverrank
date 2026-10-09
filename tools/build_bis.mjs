#!/usr/bin/env node
/* Build bis/bis.json: ForeverRank's own best-in-slot rankings for the WoW: Forever beta.
 *
 * Nothing here comes from anyone's hand-picked list. Every slot is ranked per class, spec, faction and level
 * by The Forge's own scorer: plan/gear.js is loaded unchanged into a Node vm with a small window/localStorage
 * shim, and its ForgeGear score() and weight presets() rank our own item database (plan/items-db.json).
 * The Forge's gear picker and this page therefore order items the same way; the script checks that on every run
 * against the picker's own HTML (pickerHTML) and stops if they disagree.
 *
 * What a list may hold (a character of that level, on that faction, could have it now):
 *   - wearable by the class (gear.js canUse at the list's level, the item's own class restriction),
 *     required level <= the list's level (gear.js effReq: an item with no stored required level counts as item level
 *     minus 5, The Forge's own rule), not junk or era-tagged leftover rows (as The Forge); quest rewards that rule holds
 *     back although their quest is open at the list's level are counted per level ("held" in the output);
 *   - a known Forever source in our data:
 *       dungeon drop  codex/loot.json, dungeon open in the beta now (OPEN below, from Blizzard's development
 *                     notes of 1 and 8 October 2026) and enterable at the list's level;
 *       quest reward  codex/loot.json dungeon quests and QuestBank's quest catalogue
 *                     (tools/questbank/QuestBank/Data.lua: rewards, level, side, class and race limits);
 *                     quests QuestBank marks Classic-only or Season of Discovery leftovers are skipped;
 *       crafted       a recipe item in the database (Plans, Pattern, Schematic, Formula) that is not a leftover
 *                     row, at a profession skill the level allows (Classic training caps: 150 below 20, 225 to 34);
 *       seen          gear that binds when equipped and that players' games have shown (the database's sg count),
 *                     when nothing else places it;
 *     there is no vendor, PvP-vendor or world-drop data in our sources yet, so such items appear only when seen;
 *     an item row may also carry "craft": [profession, skill] (the client's profession tables), which counts the same;
 *   - Classic estimates (est "classic") only with a Forever loot record (a drop or a quest);
 *   - no level gate Blizzard has announced above the list's level (GATED below);
 *   - a positive score under the spec's weights.
 * Faction: dungeon drops and crafts are open to both; a quest reward counts for the quest's side, and for
 * race-limited quests only when a race of that faction can be that class (plan/plan-data.json races).
 * Weapons as The Forge: the main-hand list holds one-handers and two-handers, a two-hander charged the score of
 * the best off-hand item this class could hold instead (here: the best obtainable one); the off-hand list is
 * scored for the off hand (weapon DPS counts half). Rings and trinkets come with a legal pair: Unique and
 * Unique-Equipped (and their groups) respected, and a quest reward counts as one copy.
 * A row's score is the whole number The Forge's picker shows for it (rounded once, from the exact score).
 * Each spec links ForeverChanges' own list for it (title and URL only); where they keep one list per class at a level
 * (Mage at level 20), the spec links that one.
 *
 * Run from the repo root:
 *   node tools/build_bis.mjs              # levels 30 and 20, writes bis/bis.json
 *   node tools/build_bis.mjs --level 30   # one level only
 *   node tools/build_bis.mjs --dry        # everything but the write
 * Reads (never writes): plan/gear.js, plan/items-db.json, plan/enchants.json, plan/reflect.json,
 * plan/plan-data.json, plan/plan.js (race and class order, for links into The Forge), codex/loot.json,
 * tools/questbank/QuestBank/Data.lua. Deterministic: the same inputs give the same bytes; the list date is the
 * newest date the inputs carry, not the clock. Takes a few seconds.
 */
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
process.chdir(ROOT);

const ARGS = process.argv.slice(2);
const DRY = ARGS.includes("--dry");
const LV_ARG = ARGS.indexOf("--level") !== -1 ? [+ARGS[ARGS.indexOf("--level") + 1]] : null;
const LEVELS = LV_ARG || [30, 20];
const OUT = "bis/bis.json";
const TOP = 5;

// Dungeons open in the beta now, with an entry level where Blizzard gave one. Blizzard's development notes,
// 1 October 2026 (us.forums.blizzard.com/en/wow/t/2360696/4): Razorfen Downs (25+) and Uldaman (30+) join RFC,
// Hall of Thanes, Ruins of Lordaeron, WC, Deadmines, SFK, Stockade, BFD, Gnomeregan, RFK and Scarlet Monastery,
// and Excavation Site: Wetlands opens; 8 October (…/2360696/5): the City of Dalaran dungeon opens.
const OPEN = {
  "Ragefire Chasm": 0, "Hall of Thanes": 0, "Ruins of Lordaeron": 0, "Wailing Caverns": 0, "The Deadmines": 0,
  "Shadowfang Keep": 0, "The Stockade": 0, "Blackfathom Deeps": 0, "Gnomeregan": 0, "Razorfen Kraul": 0,
  "Scarlet Monastery: Graveyard": 0, "Scarlet Monastery: Library": 0, "Scarlet Monastery: Armory": 0,
  "Scarlet Monastery: Cathedral": 0, "Excavation Site: Wetlands": 0, "Razorfen Downs": 25, "Uldaman": 30,
  "City of Dalaran": 0
};
// Level gates Blizzard announced that our item and quest data do not carry yet. Development notes of 8 October 2026
// (us.forums.blizzard.com/en/wow/t/2360696/5): the new Gelkis and Magram quests in Desolace need level 35, and their
// sixteen rewards will need level 35 to equip.
const GATED = { level: 35, names: ["Abandoned Ferocity", "Blade of the Magram Clan", "Bludgeon of Betrayed Virtues", "Centaur Spear",
  "Ceremonial Centaur Blanket", "Desert Crawler's Claw", "Desperate Barrier", "Greatstaff of the Necrokhans", "Kolkar Hunter's Belt",
  "Kolkar Marauder Chain", "Scavenged Magram Armament", "Soulsplatter Mace", "Staff of Revelations", "Thrice-Damned Effigy",
  "Traitor's Finger", "Wanderer's Broadsword"] };
const gated = (it, L) => L < GATED.level && GATED.names.indexOf(String(it.name).replace(/\u2019/g, "'")) !== -1;
// Classic profession training caps by character level (Journeyman 10, Expert 20, Artisan 35).
function skillCap(lv) { return lv >= 35 ? 300 : lv >= 20 ? 225 : lv >= 10 ? 150 : 75; }

// The page's class order (unchanged from the old page) and The Forge's class names.
const CLASSES = ["warrior", "hunter", "mage", "rogue", "priest", "warlock", "paladin", "druid", "shaman"];
const CLASSBIT = { WARRIOR: 1, PALADIN: 2, HUNTER: 4, ROGUE: 8, PRIEST: 16, SHAMAN: 64, MAGE: 128, WARLOCK: 256, DRUID: 1024 };
const RACEBIT = { "Human": 1, "Orc": 2, "Dwarf": 4, "Night Elf": 8, "Undead": 16, "Tauren": 32, "Gnome": 64, "Troll": 128 };

// ForeverChanges' own hand-picked lists, linked (never copied) per spec. Paths from their hub as of 2026-10-08;
// level 20 lives under /bis/level-20. [title, path, levels]
const FC_BASE = "https://foreverchanges.pro";
const FC = {
  warrior: { pve: [["Warrior PvE", "/warrior", [30, 20]]], tank: [["Warrior Tank", "/warrior/tank", [30, 20]]], pvp: [["Warrior PvP", "/warrior/pvp", [30, 20]]] },
  hunter: { pve: [["Hunter PvE", "/hunter", [30, 20]]], pvp: [["Hunter PvP", "/hunter/pvp", [30, 20]]] },
  mage: { frost: [["Frost Mage PvE", "/mage", [30]], ["Mage PvE", "/mage", [20]]], fire: [["Fire Mage PvE", "/mage/fire", [30]]],
    arcane: [["Arcane Mage PvE", "/mage/arcane", [30]]], pvp: [["Frost Mage PvP", "/mage/pvp", [30]], ["Mage PvP", "/mage/pvp", [20]]],
    firepvp: [["Fire Mage PvP", "/mage/fire-pvp", [30]]] },
  rogue: { pve: [["Combat Rogue PvE", "/rogue", [30]], ["Rogue PvE", "/rogue", [20]], ["Assassination Rogue PvE", "/rogue/assassination", [30]]],
    pvp: [["Subtlety Rogue PvP", "/rogue/pvp", [30]], ["Rogue PvP", "/rogue/pvp", [20]]] },
  priest: { shadow: [["Shadow Priest PvE", "/priest", [30, 20]]], shadowpvp: [["Shadow Priest PvP", "/priest/shadow-pvp", [30, 20]]],
    holy: [["Holy Priest PvE", "/priest/holy", [30, 20]]], discpvp: [["Discipline Priest PvP", "/priest/discipline-pvp", [30, 20]]] },
  warlock: { pve: [["Warlock PvE", "/warlock", [30, 20]]], pvp: [["Warlock PvP", "/warlock/pvp", [30, 20]]] },
  paladin: { ret: [["Retribution Paladin PvE", "/paladin", [30, 20]]], retpvp: [["Retribution Paladin PvP", "/paladin/retribution-pvp", [30, 20]]],
    holy: [["Holy Paladin PvE", "/paladin/holy", [30, 20]]], holypvp: [["Holy Paladin PvP", "/paladin/holy-pvp", [30, 20]], ["Shockadin Paladin PvP", "/paladin/shockadin", [30, 20]]],
    tank: [["Paladin Tank", "/paladin/tank", [30, 20]]] },
  druid: { feral: [["Feral Druid PvE", "/druid", [30, 20]], ["Druid Tank", "/druid/tank", [30, 20]]], feralpvp: [["Feral Druid PvP", "/druid/feral-pvp", [30, 20]]],
    balance: [["Balance Druid PvE", "/druid/balance", [30, 20]]], balancepvp: [["Balance Druid PvP", "/druid/balance-pvp", [30, 20]]],
    resto: [["Restoration Druid", "/druid/restoration", [30, 20]]] },
  shaman: { ele: [["Elemental Shaman PvE", "/shaman", [30, 20]]], elepvp: [["Elemental Shaman PvP", "/shaman/elemental-pvp", [30, 20]]],
    enh: [["Enhancement Shaman PvE", "/shaman/enhancement", [30, 20]]], enhpvp: [["Enhancement Shaman PvP", "/shaman/enhancement-pvp", [30, 20]]],
    resto: [["Restoration Shaman", "/shaman/restoration", [30, 20]]] }
};
// Our spec (The Forge preset id) -> which of their lists to link, PvE first then PvP.
const FC_FOR = {
  warrior: { arms: ["pve", "pvp"], fury: ["pve", "pvp"], protection: ["tank"] },
  hunter: { class: ["pve", "pvp"] },
  mage: { class: ["frost", "pvp"], arcane: ["arcane"], fire: ["fire", "firepvp"], frost: ["frost", "pvp"] },
  rogue: { class: ["pve", "pvp"] },
  priest: { discipline: ["discpvp"], holy: ["holy", "discpvp"], shadow: ["shadow", "shadowpvp"] },
  warlock: { class: ["pve", "pvp"] },
  paladin: { holy: ["holy", "holypvp"], protection: ["tank"], retribution: ["ret", "retpvp"], reflect: ["tank"] },
  druid: { balance: ["balance", "balancepvp"], feral: ["feral", "feralpvp"], restoration: ["resto"] },
  shaman: { elemental: ["ele", "elepvp"], enhancement: ["enh", "enhpvp"], restoration: ["resto"] }
};
// The old page's ?s= keys (ForeverChanges' level-20 spec names) keep working.
const ALIASES = {
  warrior: { pve: "arms", pvp: "arms", tank: "protection" },
  hunter: { pve: "all", pvp: "all" },
  mage: { pve: "all", pvp: "all", "fire-pvp": "fire" },
  rogue: { pve: "all", pvp: "all", assassination: "all" },
  priest: { "shadow-pve": "shadow", "shadow-pvp": "shadow", "holy-pvp": "discipline", "discipline-pvp": "discipline" },
  warlock: { pve: "all", pvp: "all" },
  paladin: { "retribution-pve": "retribution", "retribution-pvp": "retribution", "holy-pvp": "holy", shockadin: "holy", tank: "protection" },
  druid: { "feral-pve": "feral", "feral-pvp": "feral", tank: "feral", "balance-pvp": "balance" },
  shaman: { "elemental-pve": "elemental", "elemental-pvp": "elemental", "enhancement-pvp": "enhancement" }
};

// ---------------------------------------------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------------------------------------------
const readJSON = (p) => JSON.parse(fs.readFileSync(p, "utf8"));
const optJSON = (p) => { try { return readJSON(p); } catch (e) { return null; } };

const DB = readJSON("plan/items-db.json");
const LOOT = readJSON("codex/loot.json");
const PLANDATA = readJSON("plan/plan-data.json");
const PLANJS = fs.readFileSync("plan/plan.js", "utf8");
const QBSRC = fs.readFileSync("tools/questbank/QuestBank/Data.lua", "utf8");

// A Lua table literal (QuestBank's generated Data.lua) as JSON: positional tables become arrays.
function luaTable(src, name) {
  const m = new RegExp("^" + name.replace(/\./g, "\\.") + "\\s*=\\s*", "m").exec(src);
  if (!m) throw new Error("Data.lua: " + name + " not found");
  let i = m.index + m[0].length;
  function ws() {
    for (;;) {
      while (i < src.length && /\s/.test(src[i])) i++;
      if (src.startsWith("--", i)) { while (i < src.length && src[i] !== "\n") i++; continue; }
      return;
    }
  }
  function str() {
    const q = src[i++];
    let out = "";
    while (src[i] !== q) {
      if (src[i] === "\\") {
        i++;
        const e = src[i];
        if (/\d/.test(e)) { const d = /^\d{1,3}/.exec(src.slice(i, i + 3))[0]; out += String.fromCharCode(+d); i += d.length; continue; }
        out += e === "n" ? "\n" : e === "t" ? "\t" : e;
        i++;
      } else out += src[i++];
    }
    i++;
    return out;
  }
  function val() {
    ws();
    const c = src[i];
    if (c === "{") return tbl();
    if (c === '"' || c === "'") return str();
    const num = /^-?(?:0x[0-9a-f]+|\d+(?:\.\d*)?(?:e[-+]?\d+)?|\.\d+)/i.exec(src.slice(i, i + 40));
    if (num) { i += num[0].length; return Number(num[0]); }
    const w = /^[A-Za-z_]\w*/.exec(src.slice(i, i + 40));
    if (!w) throw new Error("Data.lua: cannot read at " + i + ": " + src.slice(i, i + 30));
    i += w[0].length;
    if (w[0] === "true") return true;
    if (w[0] === "false") return false;
    if (w[0] === "nil") return null;
    throw new Error("Data.lua: unexpected " + w[0]);
  }
  function tbl() {
    i++;
    const arr = [], obj = {};
    let keyed = false;
    for (;;) {
      ws();
      if (src[i] === "}") { i++; break; }
      let key = null;
      if (src[i] === "[") {
        i++; key = val(); ws();
        if (src[i] !== "]") throw new Error("Data.lua: ] expected at " + i);
        i++; ws();
        if (src[i] !== "=") throw new Error("Data.lua: = expected at " + i);
        i++;
      } else {
        const k = /^([A-Za-z_]\w*)\s*=(?!=)/.exec(src.slice(i, i + 80));
        if (k) { key = k[1]; i += k[0].length; }
      }
      const v = val();
      if (key === null) arr.push(v); else { obj[key] = v; keyed = true; }
      ws();
      if (src[i] === "," || src[i] === ";") i++;
    }
    if (!keyed) return arr;
    arr.forEach((v, k) => { obj[k + 1] = v; });
    return obj;
  }
  return val();
}

// ---------------------------------------------------------------------------------------------------------------
// The Forge's scorer: plan/gear.js, unchanged, in a vm
// ---------------------------------------------------------------------------------------------------------------
const GEAR_SRC = fs.readFileSync("plan/gear.js", "utf8");
const ANCHOR = /return \{\s*html: html,/g;
function forgeWindow(code) {
  const store = {};
  const localStorage = {
    getItem: (k) => (Object.prototype.hasOwnProperty.call(store, k) ? store[k] : null),
    setItem: (k, v) => { store[k] = String(v); },
    removeItem: (k) => { delete store[k]; }
  };
  const window = { localStorage };
  vm.runInContext(code, vm.createContext({ window, console }), { filename: "plan/gear.js" });
  return window;
}
function loadForge(items) {
  const extras = { enchants: optJSON("plan/enchants.json"), reflect: optJSON("plan/reflect.json"), dungeons: LOOT.dungeons };
  const opts = { items: { items }, get: () => ({}), ench: () => ({}), cons: () => [] };
  let win = forgeWindow(GEAR_SRC);
  win.ForgeGear.extras(extras);
  let inst = win.ForgeGear(opts);
  let api = typeof inst.score === "function" && typeof inst.presets === "function" ? { score: inst.score, presets: inst.presets } : null;
  if (!api) {
    // score() and presets() live inside ForgeGear's closure; until gear.js exports them, the same file is run with
    // one line added to the object it returns. The file on disk is never changed.
    if ((GEAR_SRC.match(ANCHOR) || []).length !== 1) throw new Error("plan/gear.js changed: cannot reach score() and presets(); export them from ForgeGear");
    win = forgeWindow(GEAR_SRC.replace(ANCHOR, "return { __bis: { score: score, presets: presets }, html: html,"));
    win.ForgeGear.extras(extras);
    inst = win.ForgeGear(opts);
    api = inst.__bis;
  }
  return { FI: win.ForgeItem, inst, score: api.score, presets: api.presets };
}

// ---------------------------------------------------------------------------------------------------------------
// Items as The Forge sees them
// ---------------------------------------------------------------------------------------------------------------
const ALL = DB.items;
const FORGE = loadForge(ALL);
const FI = FORGE.FI;
const BYID = {};
ALL.forEach((it) => { BYID[String(it.id)] = it; });
const ITEMS = ALL.filter((it) => !it.era && !FI.isJunk(it)); // The Forge's own pool
const ACCEPT = {
  head: ["head"], neck: ["neck"], shoulder: ["shoulder"], back: ["back"], chest: ["chest"], wrist: ["wrist"], hands: ["hands"],
  waist: ["waist"], legs: ["legs"], feet: ["feet"], finger1: ["finger"], trinket1: ["trinket"],
  mainhand: ["main-hand", "one-hand", "two-hand"], offhand: ["off-hand", "one-hand"], ranged: ["ranged", "relic", "thrown"]
};
// The Forge's gear-code slot order (plan/gear.js SLOTS): the index is what a ?b= link carries.
const SLOT_KEYS = ["head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet", "finger1", "finger2",
  "trinket1", "trinket2", "mainhand", "offhand", "ranged"];
if (FORGE.inst.SLOT_KEYS && FORGE.inst.SLOT_KEYS.join() !== SLOT_KEYS.join()) throw new Error("plan/gear.js slot order changed: update SLOT_KEYS");
// Dual wield as gear.js decides it (its DUAL table is private): an off-hand dagger passes canUse only for those classes.
const dual = (C) => FI.canUse(C, { type: "Dagger", slot: "off-hand", cat: "weapon" }, 60);

// ---------------------------------------------------------------------------------------------------------------
// Sources, from our data
// ---------------------------------------------------------------------------------------------------------------
const SRC = [], SRC_AT = {};
function srcId(kind, text, side) {
  const key = kind + "|" + text + "|" + (side || "");
  if (!(key in SRC_AT)) { SRC_AT[key] = SRC.length; SRC.push([kind, text, side || ""]); }
  return SRC_AT[key];
}
// item id -> [{ k, lv (lowest list level it is open at), side ("a", "h", ""), races (mask or 0), cls (mask or 0), copies (1 for a quest), t }]
const SOURCES = {};
function addSource(id, s) { (SOURCES[String(id)] = SOURCES[String(id)] || []).push(s); }

// Dungeon drops and dungeon quests: codex/loot.json
const lootQuestNames = new Set();
LOOT.dungeons.forEach((d) => {
  if (!(d.name in OPEN)) return;
  const entry = OPEN[d.name];
  d.bosses.forEach((b) => {
    const who = b.kind === "trash" ? "" : b.kind === "rare" ? b.name + " (rare spawn)" : b.name;
    b.items.forEach((id) => addSource(id, { k: "drop", lv: entry, side: "", copies: 9, d: d.name, who, t: (who || "trash") + "|" + d.name }));
  });
  (d.quests || []).forEach((q) => {
    lootQuestNames.add(q.name.toLowerCase());
    const side = q.side === "a" || q.side === "h" ? q.side : "";
    const lv = Math.max(entry, q.min || 0);
    const t = "Quest: " + q.name + (q.level ? " (level " + q.level + ")" : "") + ", " + d.name;
    q.items.forEach((id) => addSource(id, { k: "quest", lv, side, copies: 1, t, qn: q.name.toLowerCase(), qname: q.name, qlevel: q.level || 0, where: d.name }));
  });
});

// World and dungeon quests: QuestBank's catalogue
const QB = {
  Q: luaTable(QBSRC, "D.Q"), QN: luaTable(QBSRC, "D.QN"), CAT: luaTable(QBSRC, "D.CAT"),
  RITEMS: luaTable(QBSRC, "D.RITEMS"), RACE: luaTable(QBSRC, "D.RACE"), READ: (/^D\.READ = "([^"]+)"/m.exec(QBSRC) || [])[1] || ""
};
let qbQuests = 0;
Object.keys(QB.Q).forEach((qid) => {
  const q = QB.Q[qid], rw = QB.RITEMS[qid];
  if (!rw) return;
  const flags = q[9] || 0;
  if (flags & 16 || flags & 128) return;          // Classic only (not in Forever's data yet) or a Season of Discovery leftover
  if (flags & 4096) return;                        // repeatable turn-ins: never a gear reward worth ranking
  const name = QB.QN[qid];
  if (!name) return;
  const cat = QB.CAT[q[7] - 1] || null;
  const side = q[2] === 1 ? "a" : q[2] === 2 ? "h" : "";
  const where = cat && cat.key !== "class" && cat.key !== "misc" ? cat.name : "";
  const t = "Quest: " + name + " (level " + q[0] + ")" + (where ? ", " + where : "");
  const ids = [].concat(rw.c || [], rw.r || [], rw.u || []);
  qbQuests++;
  ids.forEach((id) => addSource(id, { k: "quest", qb: 1, lv: q[1] || 0, side, races: QB.RACE[qid] || 0, cls: q[8] || 0, copies: 1, t,
    qn: name.toLowerCase(), qname: name, qlevel: q[0] || 0, where }));
});

// One quest from both catalogues: the dungeon line from the loot records, side, class and race limits from QuestBank
// (it reads the game's own quest data; one name can be an Alliance and a Horde quest, which makes it both).
Object.keys(SOURCES).forEach((id) => {
  const list = SOURCES[id], out = [];
  list.forEach((s) => {
    if (s.k !== "quest" || s.qb) { out.push(s); return; }
    const qb = list.filter((o) => o.qb && o.qn === s.qn);
    if (!qb.length) { out.push(s); return; }
    const sides = new Set(qb.map((o) => o.side));
    out.push(Object.assign({}, s, {
      side: sides.size === 1 ? [...sides][0] : "",
      races: qb.some((o) => !o.races) ? 0 : qb.reduce((a, o) => a | o.races, 0),
      cls: qb.some((o) => !o.cls) ? 0 : qb.reduce((a, o) => a | o.cls, 0),
      lv: Math.max(s.lv, Math.min(...qb.map((o) => o.lv)))
    }));
  });
  SOURCES[id] = out.filter((s) => !(s.qb && out.some((o) => !o.qb && o.k === "quest" && o.qn === s.qn)));
});

// Crafted: a recipe item in the database names what it makes
const RECIPE = /^(Plans|Pattern|Schematic|Formula): (.+)$/;
const BYNAME = {};
ITEMS.forEach((it) => { if (it.slot && it.slot !== "unknown") (BYNAME[it.name] = BYNAME[it.name] || []).push(it); });
let recipes = 0;
ITEMS.forEach((r) => {
  if (r.cat !== "recipe" || r.est === "classic" || !r.sk) return;
  const m = RECIPE.exec(r.name);
  if (!m) return;
  (BYNAME[m[2]] || []).forEach((it) => {
    recipes++;
    addSource(it.id, { k: "craft", lv: 0, skill: +r.sk[1] || 0, side: "", copies: 9,
      t: "Crafted: " + r.sk[0] + " " + r.sk[1] + (it.binding === "BoP" ? ", only the crafter can wear it" : "") });
  });
});

// Crafted, as the database may record it per item: "craft": [profession, skill] (from the client's profession tables)
ITEMS.forEach((it) => {
  if (!Array.isArray(it.craft) || !it.craft[0]) return;
  const t = "Crafted: " + it.craft[0] + (it.craft[1] ? " " + it.craft[1] : "") + (it.binding === "BoP" ? ", only the crafter can wear it" : "");
  if ((SOURCES[it.id] || []).some((s) => s.k === "craft" && s.t === t)) return;
  recipes++;
  addSource(it.id, { k: "craft", lv: 0, skill: +it.craft[1] || 0, side: "", copies: 9, t });
});

// The database's own loot links (built from the same loot records), for anything the passes above missed
ITEMS.forEach((it) => {
  if (SOURCES[it.id]) return;
  (it.drops || []).forEach((d) => {
    if (!(d[0] in OPEN)) return;
    const who = d[1] === "Trash mobs" ? "" : d[1] + (d[2] === "rare" ? " (rare spawn)" : "");
    addSource(it.id, { k: "drop", lv: OPEN[d[0]], side: "", copies: 9, d: d[0], who, t: (who || "trash") + "|" + d[0] });
  });
});

// Seen in players' games: QuestBank and ForeverProbe uploads (the database's sg count) showed a player holding it. For gear
// that binds when equipped, with no other source on record, that proves it can be had now and that it trades (a world
// drop, a trainer craft, a vendor: our data does not say which). Soulbound gear seen that way stays out: its source and
// side are unknown.
ITEMS.forEach((it) => {
  if (!it.sg || it.binding !== "BoE" || SOURCES[it.id]) return;
  addSource(it.id, { k: "seen", lv: 0, side: "", copies: 9, t: "Seen in players' games; binds when equipped, source not in our data yet" });
});

// Races per faction and class: plan/plan-data.json, so a race-limited quest counts only where a race can take it
const RACES = PLANDATA.races.map((r) => ({ n: r.n, f: r.f === "Alliance" ? "a" : "h", cls: r.classes.map((c) => c.toUpperCase()) }));
function raceOK(mask, C, f) {
  if (!mask) return true;
  return RACES.some((r) => r.f === f && r.cls.indexOf(C) !== -1 && (RACEBIT[r.n] ? (mask & RACEBIT[r.n]) !== 0 : false));
}
// The sources an item has for this class, faction and level
function sourcesFor(it, C, f, L) {
  const out = [];
  (SOURCES[it.id] || []).forEach((s) => {
    if (s.lv > L) return;
    if (s.k === "craft" && s.skill > skillCap(L)) return;
    if (s.side && s.side !== f) return;
    if (s.cls && !(s.cls & CLASSBIT[C])) return;
    if (s.races && !raceOK(s.races, C, f)) return;
    if (out.some((o) => o.t === s.t)) return;
    out.push(s);
  });
  return out;
}
// Our words for where it comes from: drops grouped by dungeon, then quests and crafts one line each
function andList(a) { return a.length < 2 ? a.join("") : a.slice(0, -1).join(", ") + " and " + a[a.length - 1]; }
function dungeonNames(names) { // "Scarlet Monastery: Graveyard, Library and Armory"
  const out = [];
  names.forEach((n) => {
    const m = /^(.+?): (.+)$/.exec(n), last = out[out.length - 1];
    if (m && last && last.pre === m[1]) last.parts.push(m[2]);
    else out.push(m ? { pre: m[1], parts: [m[2]] } : { pre: "", parts: [n] });
  });
  return andList(out.map((x) => (x.pre ? x.pre + ": " + andList(x.parts) : x.parts[0])));
}
function srcTexts(list) {
  const out = [], byD = new Map();
  list.filter((s) => s.k === "drop").forEach((s) => { if (!byD.has(s.d)) byD.set(s.d, []); if (byD.get(s.d).indexOf(s.who) === -1) byD.get(s.d).push(s.who); });
  const ds = [...byD.keys()];
  if (ds.length > 2) out.push({ k: "drop", t: "Drops in " + dungeonNames(ds) });
  else ds.forEach((d) => {
    const who = byD.get(d), bosses = who.filter(Boolean), trash = who.indexOf("") !== -1;
    if (!bosses.length) out.push({ k: "drop", t: "Trash in " + d });
    else if (bosses.length > 3) out.push({ k: "drop", t: bosses.length + " bosses" + (trash ? " and trash" : "") + " in " + d });
    else out.push({ k: "drop", t: bosses.join(" or ") + (trash ? " or trash" : "") + ", " + d });
  });
  // one quest named in several places (a Scarlet Monastery quest under every wing): one line
  const byQ = new Map();
  list.filter((s) => s.k === "quest").forEach((s) => {
    const key = s.qn + "|" + s.side;
    if (!byQ.has(key)) byQ.set(key, { s, where: [] });
    if (s.where && byQ.get(key).where.indexOf(s.where) === -1) byQ.get(key).where.push(s.where);
  });
  byQ.forEach(({ s, where }) => out.push({ k: "quest", side: s.side,
    t: "Quest: " + s.qname + (s.qlevel ? " (level " + s.qlevel + ")" : "") + (where.length ? ", " + dungeonNames(where) : "") }));
  list.filter((s) => s.k !== "drop" && s.k !== "quest").forEach((s) => out.push({ k: s.k, t: s.t, side: s.side }));
  return out;
}
function sideOf(it, C, L) { // "a" or "h" when only one faction can get it, else ""
  const a = sourcesFor(it, C, "a", L).length > 0, h = sourcesFor(it, C, "h", L).length > 0;
  return a && !h ? "a" : h && !a ? "h" : "";
}

// ---------------------------------------------------------------------------------------------------------------
// Ranking
// ---------------------------------------------------------------------------------------------------------------
const QUALITY = ["poor", "common", "uncommon", "rare", "epic", "legendary"];
const hasSource = (it) => !!((it.drops && it.drops.length) || (it.quests && it.quests.length));
// Who may hold it in this slot: the picker's own pool rules (plan/gear.js pickerHTML)
function forgePool(C, slotKey, L) {
  const clsName = C.charAt(0) + C.slice(1).toLowerCase();
  return ITEMS.filter((it) => {
    if (ACCEPT[slotKey].indexOf(it.slot) === -1) return false;
    if (!FI.canUse(C, it, L)) return false;
    if (it.cls && it.cls.indexOf(clsName) === -1) return false;
    if (slotKey === "offhand" && it.cat === "weapon" && !dual(C)) return false;
    if (FI.effReq(it).lvl > L) return false;
    if (it.est === "classic" && !hasSource(it)) return false;
    return true;
  });
}
function cmp(a, b) {
  return (b.sc - a.sc) || ((+b.it.itemLevel || 0) - (+a.it.itemLevel || 0)) || QUALITY.indexOf(b.it.quality) - QUALITY.indexOf(a.it.quality) ||
    a.it.name.localeCompare(b.it.name); // then the database's own order (a stable sort), exactly as the picker
}
function ranked(pool, W, slotKey, charge) {
  return pool.map((it) => ({ it, sc: FORGE.score(it, W, slotKey) - (charge && it.slot === "two-hand" ? charge : 0), two: it.slot === "two-hand" }))
    .sort(cmp);
}

// Unique rules: how many of one item a character may wear, and its Unique-Equipped group
function maxWorn(it, copies) {
  const u = it.unique;
  let n = 2;
  if (u === true || u === "Unique" || u === "Unique-Equipped" || /^Unique-Equipped: /.test(String(u))) n = 1;
  else if (/^Unique \((\d+)\)$/.test(String(u))) n = Math.min(2, +/\((\d+)\)/.exec(u)[1]);
  return Math.min(n, copies);
}
function ugroup(it) { const m = typeof it.unique === "string" && /^Unique-Equipped: (.+) \((\d+)\)$/.exec(it.unique); return m ? [m[1], +m[2]] : null; }
// Best legal pair from two ranked lists (rings: the same list twice; weapons: main hand and off hand)
function bestPair(A, B, copiesOf) {
  let best = null;
  const a = A.slice(0, 40), b = B.slice(0, 40);
  a.forEach((x) => b.forEach((y) => {
    if (x.it.id === y.it.id && maxWorn(x.it, copiesOf(x.it)) < 2) return;
    const gx = ugroup(x.it), gy = ugroup(y.it);
    if (gx && gy && gx[0] === gy[0] && gx[1] < 2) return;
    const s = x.sc + y.sc;
    if (!best || s > best.s + 1e-9) best = { s, x, y };
  }));
  return best;
}

const SLOTDEFS = [
  ["head", "Head"], ["neck", "Neck"], ["shoulder", "Shoulders"], ["back", "Back"], ["chest", "Chest"], ["wrist", "Wrists"],
  ["hands", "Hands"], ["waist", "Waist"], ["legs", "Legs"], ["feet", "Feet"], ["finger1", "Rings"], ["trinket1", "Trinkets"],
  ["mainhand", "Main Hand"], ["offhand", "Off Hand"], ["ranged", "Ranged"]
];
const RANGED_LABEL = { PALADIN: "Libram", SHAMAN: "Totem", DRUID: "Idol", PRIEST: "Wand", MAGE: "Wand", WARLOCK: "Wand" };

// The Forge link: race, class, one talent point in the spec's tree (so The Forge opens on that spec's weights),
// the list's #1 picks equipped, and the level cap. Format: plan/plan.js code() and parseCode().
const PJ_RACES = [...PLANJS.matchAll(/\{\s*n:\s*"([^"]+)",\s*f:\s*"(Alliance|Horde)"/g)].map((m) => ({ n: m[1], f: m[2] === "Alliance" ? "a" : "h" }));
const PJ_ORDER = (/var CLASS_ORDER = \[([^\]]+)\]/.exec(PLANJS) || [])[1];
const CLASS_ORDER = PJ_ORDER ? PJ_ORDER.match(/[A-Z]+/g) : ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"];
const PJ_CAPS = [...((/var CAPS = \{([^}]+)\}/.exec(PLANJS) || [])[1] || "20: 1, 30: 1, 60: 1").matchAll(/(\d+)\s*:/g)].map((m) => +m[1]);
function forgeLink(C, specTree, f, L, eq) {
  const ci = CLASS_ORDER.indexOf(C);
  const race = PJ_RACES.findIndex((r) => r.f === f && !/^Skyborne/.test(r.n) && RACES.some((x) => x.n === r.n && x.cls.indexOf(C) !== -1));
  if (ci < 0 || race < 0 || PJ_CAPS.indexOf(L) === -1) return "";
  const cdata = PLANDATA.classes.find((c) => c.cls === C);
  const segs = ["", "", ""];
  if (specTree >= 0 && cdata) {
    const tal = cdata.trees[specTree].talents;
    const first = tal.findIndex((t) => t.row === 1 && !t.req && !t.gone);
    if (first >= 0) segs[specTree] = "0".repeat(first) + "1";
  }
  const gear = SLOT_KEYS.map((k, i) => (eq[k] && /^[A-Za-z0-9_-]+$/.test(eq[k]) ? i.toString(36) + eq[k] : null)).filter(Boolean).join("~");
  return "?b=" + [race, ci, segs.join("-"), gear, "", L].join(".");
}

function buildList(C, preset, specTree, f, L, pools) {
  const W = preset.w;
  const copies = (it) => sourcesFor(it, C, f, L).reduce((a, s) => a + (s.copies || 1), 0);
  const ok = (it) => !gated(it, L) && sourcesFor(it, C, f, L).length > 0;
  const R = {};
  let charge = 0;
  ["offhand"].concat(SLOTDEFS.map((d) => d[0]).filter((k) => k !== "offhand")).forEach((k) => {
    const pool = pools[k].filter(ok);
    if (k === "mainhand") charge = R.offhand.length ? Math.max(0, R.offhand[0].sc) : 0;
    R[k] = ranked(pool, W, k, k === "mainhand" ? charge : 0).filter((x) => x.sc > 0);
  });
  const row = (x) => {
    const o = [String(x.it.id), Math.round(x.sc), srcTexts(sourcesFor(x.it, C, f, L)).map((z) => srcId(z.k, z.t, z.side)), sideOf(x.it, C, L), x.two ? 1 : 0];
    while (o.length > 3 && !o[o.length - 1]) o.pop();
    return o;
  };
  const eq = {};
  const slots = SLOTDEFS.map(([k, label]) => {
    const list = R[k];
    const out = { slot: k.replace(/1$/, ""), label: k === "ranged" ? (RANGED_LABEL[C] || "Ranged") : label, rows: list.slice(0, TOP).map(row) };
    if (k === "mainhand" && charge && list.slice(0, TOP).some((x) => x.two)) out.charge = Math.round(charge);
    if (list[0]) eq[k] = String(list[0].it.id);
    if (k === "finger1" || k === "trinket1") {
      const p = bestPair(list, list, copies);
      if (p) { out.pair = [String(p.x.it.id), String(p.y.it.id)]; eq[k] = out.pair[0]; eq[k.replace("1", "2")] = out.pair[1]; }
    }
    return out;
  });
  // Weapons: a two-hander at the top of Main Hand takes both hands; otherwise the best legal main hand + off hand
  const mh = R.mainhand, oh = R.offhand, weap = {};
  if (mh.length && mh[0].it.slot === "two-hand") { weap.two = String(mh[0].it.id); delete eq.offhand; eq.mainhand = weap.two; }
  else if (mh.length) {
    const p = oh.length ? bestPair(mh.filter((x) => x.it.slot !== "two-hand"), oh, copies) : null;
    if (p) { weap.mh = String(p.x.it.id); weap.oh = String(p.y.it.id); eq.mainhand = weap.mh; eq.offhand = weap.oh; }
    else { weap.mh = String(mh[0].it.id); eq.mainhand = weap.mh; delete eq.offhand; }
  }
  slots.find((s) => s.slot === "mainhand").set = weap;
  return { forge: forgeLink(C, specTree, f, L, eq), slots };
}

// ---------------------------------------------------------------------------------------------------------------
// Agreement with The Forge: the picker's own HTML must order every item the way this script does
// ---------------------------------------------------------------------------------------------------------------
function pickerCheck(C, preset, L) {
  const inst = FORGE.inst;
  inst.setSpec(preset.label, C, L);
  inst.pickSet("preset", preset.id);
  let bad = 0, n = 0;
  Object.keys(ACCEPT).forEach((k) => {
    const html = inst.pickerHTML(k);
    const ids = [...html.matchAll(/data-gpick="([^"]+)"/g)].map((m) => m[1]);
    const scs = [...html.matchAll(/<span class="gp-sc"[^>]*>([^<]*)<\/span>/g)].map((m) => m[1]);
    let charge = 0;
    if (k === "mainhand") {
      const oh = forgePool(C, "offhand", L);
      oh.forEach((it) => { charge = Math.max(charge, FORGE.score(it, preset.w, "offhand")); });
    }
    const mine = ranked(forgePool(C, k, L), preset.w, k, charge).slice(0, ids.length);
    n++;
    const same = mine.length === ids.length && mine.every((x, i) => String(x.it.id) === ids[i] && (x.sc ? String(Math.round(x.sc)) : "–") === scs[i]);
    if (!same) {
      bad++;
      const at = mine.findIndex((x, i) => String(x.it.id) !== ids[i]);
      console.error("  disagrees with The Forge's picker: " + C + " " + preset.label + " L" + L + " " + k + " at row " + at + " (" + (mine[at] && mine[at].it.id) + " vs " + ids[at] + ")");
    }
  });
  return [n, bad];
}

// ---------------------------------------------------------------------------------------------------------------
// Build
// ---------------------------------------------------------------------------------------------------------------
const t0 = Date.now();
const SPECICON = {};
PLANDATA.classes.forEach((c) => { SPECICON[c.cls] = c.trees.map((t) => [t.name, t.icon]); });
const classes = [];
let lists = 0, rows = 0, checks = 0, mismatches = 0;
const used = new Set();
const noFC = [];
CLASSES.forEach((ck) => {
  const C = ck.toUpperCase();
  FORGE.inst.setSpec("", C, LEVELS[0]);
  const presets = FORGE.presets().filter((p) => p.id !== "custom");
  const pools = {};
  LEVELS.forEach((L) => { pools[L] = {}; Object.keys(ACCEPT).forEach((k) => { pools[L][k] = forgePool(C, k, L); }); });
  const trees = SPECICON[C] || [];
  const specs = presets.map((p) => {
    const tree = p.id === "class" ? -1 : p.id === "reflect" ? trees.findIndex((t) => t[0] === "Protection") : trees.findIndex((t) => t[0].indexOf(p.label) === 0);
    const key = p.id === "class" ? "all" : p.id;
    const fcl = {};
    LEVELS.forEach((L) => {
      const links = (id) => (FC_FOR[ck][id] || []).map((g) => (FC[ck][g] || []).filter((x) => x[2].indexOf(L) !== -1)
        .map((x) => [x[0], FC_BASE + "/bis" + (L === 30 ? "" : "/level-" + L) + x[1], /pvp|PvP/.test(x[0]) ? 1 : 0])).flat();
      fcl[L] = links(p.id);
      if (!fcl[L].length) fcl[L] = links("class"); // e.g. Fire and Arcane Mage at level 20: they keep one Mage list there
      if (!fcl[L].length) noFC.push(ck + " " + p.label + " L" + L);
    });
    // The Forge picks its weights from the tree holding the most points; a preset no tree names (Reflect tank) is picked by hand.
    const auto = tree >= 0 ? (presets.find((x) => trees[tree][0].indexOf(x.label) === 0) || presets[0]) : presets[0];
    const out = {
      key, name: p.id === "class" ? "All specs" : p.label, preset: p.id, label: p.label, pick: auto.id === p.id ? 0 : 1,
      icon: tree >= 0 ? trees[tree][1] : "classicon_" + ck, tree: tree >= 0 ? trees[tree][0] : "",
      w: Object.fromEntries(Object.keys(p.w).filter((k) => p.w[k]).sort().map((k) => [k, p.w[k]])),
      fc: fcl, lists: {}
    };
    LEVELS.forEach((L) => {
      FORGE.inst.setSpec(p.label, C, L);
      const [n, bad] = pickerCheck(C, p, L);
      checks += n; mismatches += bad;
      const a = buildList(C, p, tree, "a", L, pools[L]);
      const h = buildList(C, p, tree, "h", L, pools[L]);
      [a, h].forEach((x) => x.slots.forEach((s) => s.rows.forEach((r) => { used.add(r[0]); rows++; })));
      lists += 2;
      out.lists[L] = { a, h };
    });
    return out;
  });
  classes.push({ key: ck, name: C.charAt(0) + C.slice(1).toLowerCase(), forge: C, specs });
});
if (mismatches) { console.error(mismatches + " of " + checks + " picker checks disagree with plan/gear.js; nothing written."); process.exit(1); }
if (noFC.length) console.warn("no ForeverChanges list to link for: " + noFC.join(", ") + " (the page's credit line says every list links one)");

// Quest rewards The Forge's level rule holds back: no stored required level, so effReq takes item level - 5, which lands
// above the list's level although the quest's own required level (known, > 0) fits it. The page says how many.
const GEARSLOTS = new Set(Object.values(ACCEPT).flat());
const held = {};
LEVELS.forEach((L) => {
  held[L] = ITEMS.filter((it) => {
    if (!GEARSLOTS.has(it.slot) || gated(it, L)) return false;
    const er = FI.effReq(it);
    return er.est && er.lvl > L && (SOURCES[it.id] || []).some((s) => s.k === "quest" && s.lv > 0 && s.lv <= L);
  }).length;
});

// Item names and icons for the first paint; the tooltips come from plan/items-db.json through gear.js.
const items = {};
[...used].sort((a, b) => a.localeCompare(b, "en", { numeric: true })).forEach((id) => {
  const it = BYID[id];
  items[id] = [it.name, it.quality || "common", it.icon || "", it.est === "classic" ? 1 : 0];
});
const dates = [DB.scavenged, DB.generated, LOOT.generated, QB.READ].filter((d) => /^\d{4}-\d\d-\d\d$/.test(d || "")).sort();
const doc = {
  schema: 3,
  note: "ForeverRank's own best-in-slot rankings: every slot ranked per class, spec, faction and level by The Forge's weights " +
    "(plan/gear.js score and presets) over our item database. Sources are from our own data: codex/loot.json, QuestBank's quest " +
    "catalogue and the database's recipe items. Built by tools/build_bis.mjs; nobody's hand-picked list is copied. Rows: " +
    "[item id, score (the whole number The Forge's picker shows), indexes into src, side (a or h) when only one faction can get it, 1 for a two-hander]; a main-hand slot's " +
    "charge is what each two-hander's score already lost for the off hand it replaces. src: [kind, text, side]. pair: the legal " +
    "two-slot pick for rings and trinkets; set: the best weapon setup. held: per level, the quest rewards from quests open at " +
    "that level that stay out because their required level is not stored and The Forge's estimate (item level - 5) is higher.",
  build: DB.build,
  date: dates[dates.length - 1],
  level: LEVELS[0],
  levels: LEVELS,
  top: TOP,
  open: Object.keys(OPEN),
  held,
  aliases: ALIASES,
  src: SRC,
  items,
  classes
};
const json = JSON.stringify(doc);
if (!DRY) fs.writeFileSync(OUT, json + "\n");
console.log((DRY ? "[dry] " : "") + "bis.json: " + lists + " lists (" + classes.reduce((a, c) => a + c.specs.length, 0) + " specs x " + LEVELS.length +
  " levels x 2 factions), " + rows + " rows, " + Object.keys(items).length + " distinct items, " + SRC.length + " sources, " +
  (json.length / 1024).toFixed(0) + " KB; " + checks + " picker checks agree with The Forge; " + ((Date.now() - t0) / 1000).toFixed(1) + " s");
console.log("inputs: items " + DB.build + " (" + ALL.length + " rows, " + ITEMS.length + " in The Forge's pool), loot " + LOOT.generated +
  ", QuestBank " + QB.READ + " (" + qbQuests + " quests with rewards), " + recipes + " recipe links");
console.log("held back by an estimated required level (quest open, item level - 5 above the list): " +
  LEVELS.map((L) => held[L] + " quest rewards at level " + L).join(", "));
