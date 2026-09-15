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

  var SPELL_ICONS = {
    // Warrior
    "Battle Shout": "ability_warrior_battleshout", "Charge": "ability_warrior_charge",
    "Rend": "ability_gouge", "Heroic Strike": "ability_rogue_ambush",
    "Thunder Clap": "ability_thunderclap", "Hamstring": "ability_shockwave",
    "Overpower": "ability_meleedamage", "Execute": "inv_sword_48",
    "Whirlwind": "ability_whirlwind", "Shield Block": "ability_defend",
    "Shield Bash": "ability_warrior_shieldbash", "Sunder Armor": "ability_warrior_sunder",
    "Revenge": "ability_warrior_revenge", "Taunt": "spell_nature_reincarnation",
    "Battle Stance": "ability_warrior_offensivestance", "Defensive Stance": "ability_warrior_defensivestance",
    "Berserker Stance": "ability_racial_avatar", "Bloodrage": "ability_racial_bloodrage",
    "Demoralizing Shout": "ability_warrior_warcry", "Cleave": "ability_warrior_cleave",
    "Intimidating Shout": "ability_golemthunderclap", "Disarm": "ability_warrior_disarm",
    "Mocking Blow": "ability_warrior_punishingblow", "Retaliation": "ability_warrior_challange",
    "Berserker Rage": "spell_nature_ancestralguardian", "Intercept": "ability_rogue_sprint",
    "Pummel": "inv_gauntlets_04", "Slam": "ability_warrior_decisivestrike",
    // Paladin
    "Holy Light": "spell_holy_holybolt", "Flash of Light": "spell_holy_flashheal",
    "Blessing of Might": "spell_holy_fistofjustice", "Blessing of Wisdom": "spell_holy_sealofwisdom",
    "Devotion Aura": "spell_holy_devotionaura", "Retribution Aura": "spell_holy_auraoflight",
    "Concentration Aura": "spell_holy_mindsooth", "Judgement": "spell_holy_righteousfury",
    "Seal of Righteousness": "ability_thunderbolt", "Seal of the Crusader": "spell_holy_holysmite",
    "Hammer of Justice": "spell_holy_sealofmight", "Divine Protection": "spell_holy_restoration",
    "Blessing of Protection": "spell_holy_sealofprotection", "Blessing of Freedom": "spell_holy_sealofvalor",
    "Purify": "spell_holy_purify", "Cleanse": "spell_holy_renew", "Redemption": "spell_holy_resurrection",
    "Lay on Hands": "spell_holy_layonhands", "Exorcism": "spell_holy_excorcism_02",
    "Consecration": "spell_holy_innerfire", "Hammer of Wrath": "inv_hammer_04",
    "Turn Undead": "spell_holy_turnundead", "Sense Undead": "spell_holy_senseundead",
    "Righteous Fury": "spell_holy_sealoffury",
    // Hunter
    "Aspect of the Hawk": "spell_nature_ravenform", "Aspect of the Monkey": "ability_hunter_aspectofthemonkey",
    "Aspect of the Cheetah": "ability_mount_jungletiger", "Aspect of the Beast": "ability_mount_pinktiger",
    "Aspect of the Pack": "ability_mount_whitetiger", "Arcane Shot": "ability_impalingbolt",
    "Serpent Sting": "ability_hunter_quickshot", "Concussive Shot": "spell_frost_stun",
    "Multi-Shot": "ability_upgrademoonglaive", "Aimed Shot": "inv_spear_07",
    "Rapid Fire": "ability_hunter_runningshot", "Hunter's Mark": "ability_hunter_snipershot",
    "Mend Pet": "ability_hunter_mendpet", "Call Pet": "ability_hunter_beastcall",
    "Tame Beast": "ability_hunter_beasttaming", "Eyes of the Beast": "ability_eyeoftheowl",
    "Freezing Trap": "spell_frost_chainsofice", "Immolation Trap": "spell_fire_immolation",
    "Frost Trap": "spell_frost_freezingbreath", "Explosive Trap": "spell_fire_selfdestruct",
    "Raptor Strike": "ability_meleedamage", "Mongoose Bite": "ability_hunter_swiftstrike",
    "Wing Clip": "ability_rogue_trip", "Disengage": "ability_rogue_feint",
    "Feign Death": "ability_rogue_feigndeath", "Track Beasts": "ability_tracking",
    "Scorpid Sting": "ability_hunter_criticalshot", "Viper Sting": "ability_hunter_aimedshot",
    "Flare": "spell_fire_flare", "Volley": "ability_marksmanship", "Auto Shot": "ability_whirlwind",
    // Rogue
    "Sinister Strike": "spell_shadow_ritualofsacrifice", "Eviscerate": "ability_rogue_eviscerate",
    "Backstab": "ability_backstab", "Stealth": "ability_stealth", "Pick Pocket": "inv_misc_bag_11",
    "Gouge": "ability_gouge", "Slice and Dice": "ability_rogue_slicedice",
    "Sprint": "ability_rogue_sprint", "Evasion": "spell_shadow_shadowward",
    "Kick": "ability_kick", "Garrote": "ability_rogue_garrote", "Expose Armor": "ability_warrior_riposte",
    "Vanish": "ability_vanish", "Kidney Shot": "ability_rogue_kidneyshot",
    "Cheap Shot": "ability_cheapshot", "Ambush": "ability_rogue_ambush",
    "Sap": "ability_sap", "Distract": "ability_rogue_distract", "Pick Lock": "spell_nature_moonkey",
    "Blind": "spell_shadow_mindsteal", "Rupture": "ability_rogue_rupture", "Feint": "ability_rogue_feint",
    // Priest
    "Smite": "spell_holy_holysmite", "Lesser Heal": "spell_holy_lesserheal", "Heal": "spell_holy_heal",
    "Greater Heal": "spell_holy_greaterheal", "Renew": "spell_holy_renew",
    "Power Word: Shield": "spell_holy_powerwordshield", "Power Word: Fortitude": "spell_holy_wordfortitude",
    "Shadow Word: Pain": "spell_shadow_shadowwordpain", "Mind Blast": "spell_shadow_unholyfrenzy",
    "Mind Flay": "spell_shadow_siphonmana", "Fade": "spell_magic_lesserinvisibilty",
    "Psychic Scream": "spell_shadow_psychicscream", "Dispel Magic": "spell_holy_dispelmagic",
    "Inner Fire": "spell_holy_innerfire", "Resurrection": "spell_holy_resurrection",
    "Flash Heal": "spell_holy_flashheal", "Holy Fire": "spell_holy_searinglight",
    "Prayer of Healing": "spell_holy_prayerofhealing", "Divine Spirit": "spell_holy_divinespirit",
    "Mind Soothe": "spell_holy_mindsooth", "Mind Vision": "spell_holy_mindvision",
    "Shackle Undead": "spell_nature_slow", "Levitate": "spell_holy_layonhands",
    "Fear Ward": "spell_holy_excorcism",
    // Shaman
    "Lightning Bolt": "spell_nature_lightning", "Chain Lightning": "spell_nature_chainlightning",
    "Earth Shock": "spell_nature_earthshock", "Flame Shock": "spell_fire_flameshock",
    "Frost Shock": "spell_frost_frostshock", "Healing Wave": "spell_nature_magicimmunity",
    "Lesser Healing Wave": "spell_nature_healingwavelesser", "Lightning Shield": "spell_nature_lightningshield",
    "Rockbiter Weapon": "spell_nature_rockbiter", "Flametongue Weapon": "spell_fire_flametounge",
    "Frostbrand Weapon": "spell_frost_frostbrand", "Windfury Weapon": "spell_nature_cyclone",
    "Ghost Wolf": "spell_nature_spiritwolf", "Ancestral Spirit": "spell_nature_regenerate",
    "Astral Recall": "spell_nature_astralrecal", "Far Sight": "spell_nature_farsight",
    "Purge": "spell_nature_purge", "Cure Poison": "spell_nature_nullifypoison",
    "Water Breathing": "spell_shadow_demonbreath", "Water Walking": "spell_frost_windwalkon",
    // Mage
    "Fireball": "spell_fire_flamebolt", "Frostbolt": "spell_frost_frostbolt02",
    "Arcane Missiles": "spell_nature_starfall", "Arcane Intellect": "spell_holy_magicalsentry",
    "Arcane Explosion": "spell_nature_wispsplode", "Frost Nova": "spell_frost_frostnova",
    "Frost Armor": "spell_frost_frostarmor02", "Ice Armor": "spell_frost_frostarmor02",
    "Fire Blast": "spell_fire_fireball", "Flamestrike": "spell_fire_flameshock",
    "Blink": "spell_arcane_blink", "Polymorph": "spell_nature_polymorph",
    "Counterspell": "spell_frost_iceshock", "Blizzard": "spell_frost_icestorm",
    "Cone of Cold": "spell_frost_glacier", "Scorch": "spell_fire_soulburn",
    "Slow Fall": "spell_magic_featherfall", "Mana Shield": "spell_shadow_detectlesserinvisibility",
    "Evocation": "spell_nature_purge", "Conjure Food": "inv_misc_food_10",
    "Conjure Water": "inv_drink_06", "Remove Lesser Curse": "spell_nature_removecurse",
    "Amplify Magic": "spell_holy_flashheal", "Dampen Magic": "spell_nature_abolishmagic",
    // Warlock
    "Shadow Bolt": "spell_shadow_shadowbolt", "Corruption": "spell_shadow_abominationexplosion",
    "Curse of Agony": "spell_shadow_curseofsargeras", "Immolate": "spell_fire_immolation",
    "Life Tap": "spell_shadow_burningspirit", "Drain Life": "spell_shadow_lifedrain02",
    "Drain Soul": "spell_shadow_haunting", "Drain Mana": "spell_shadow_siphonmana",
    "Fear": "spell_shadow_possession", "Health Funnel": "spell_shadow_lifedrain",
    "Create Healthstone": "inv_stone_04", "Create Soulstone": "spell_shadow_soulgem",
    "Summon Imp": "spell_shadow_summonimp", "Summon Voidwalker": "spell_shadow_summonvoidwalker",
    "Summon Succubus": "spell_shadow_summonsuccubus", "Summon Felhunter": "spell_shadow_summonfelhunter",
    "Demon Skin": "spell_shadow_ragingscream", "Demon Armor": "spell_shadow_ragingscream",
    "Unending Breath": "spell_shadow_demonbreath", "Eye of Kilrogg": "spell_shadow_evileye",
    "Ritual of Summoning": "spell_shadow_twilight", "Curse of Weakness": "spell_shadow_curseofmannoroth",
    "Banish": "spell_shadow_cripple", "Rain of Fire": "spell_shadow_rainoffire",
    "Searing Pain": "spell_fire_soulburn", "Hellfire": "spell_fire_incinerate",
    // Druid
    "Wrath": "spell_nature_abolishmagic", "Moonfire": "spell_nature_starfall",
    "Healing Touch": "spell_nature_healingtouch", "Rejuvenation": "spell_nature_rejuvenation",
    "Regrowth": "spell_nature_resistnature", "Mark of the Wild": "spell_nature_regeneration",
    "Thorns": "spell_nature_thorns", "Entangling Roots": "spell_nature_stranglevines",
    "Bear Form": "ability_racial_bearform", "Cat Form": "ability_druid_catform",
    "Aquatic Form": "ability_druid_aquaticform", "Travel Form": "ability_druid_travelform",
    "Maul": "ability_druid_maul", "Swipe": "inv_misc_monsterclaw_03", "Claw": "ability_druid_rake",
    "Rake": "ability_druid_disembowel", "Rip": "ability_ghoulfrenzy", "Prowl": "ability_ambush",
    "Growl": "ability_physical_taunt", "Demoralizing Roar": "ability_druid_demoralizingroar",
    "Faerie Fire": "spell_nature_faeriefire", "Hibernate": "spell_nature_sleep",
    "Remove Curse": "spell_holy_removecurse", "Cure Poison": "spell_nature_nullifypoison",
    "Rebirth": "spell_nature_reincarnation", "Starfire": "spell_arcane_starfire",
    "Tranquility": "spell_nature_tranquility", "Barkskin": "spell_nature_stoneclawtotem",
    // General
    "Attack": "ability_meleedamage", "Shoot": "ability_marksmanship", "Throw": "ability_throw",
    "Dodge": "spell_nature_invisibilty", "Parry": "ability_parry", "Block": "ability_defend",
    "Dual Wield": "ability_dualwield", "Armor Proficiency": "inv_shield_06",
    "Languages": "inv_misc_book_09", "Beast Training": "ability_hunter_beastcall",
    "Find Herbs": "inv_misc_flower_02", "Find Minerals": "spell_nature_earthquake"
  };
  function spellIcon(name, fallback) {
    return (DATA && DATA.spellIcons && DATA.spellIcons[name]) || SPELL_ICONS[name] || fallback;
  }
  function iconFB(name, fb, cls) {
    // Two-stage safety net: unknown names wear the tab icon; a 404 swaps to
    // it live. No spell goes bare.
    var primary = CDN + name + ".jpg", backup = CDN + fb + ".jpg";
    return '<img class="' + (cls || "wi") + '" src="' + primary + '" data-fb="' + backup +
      '" alt="" loading="lazy" onerror="if(this.src!==this.getAttribute(\'data-fb\')){this.src=this.getAttribute(\'data-fb\');}else{this.onerror=null;this.style.visibility=\'hidden\';}">';
  }

  // ---- state ----------------------------------------------------------------
  var DATA = null;                       // plan-data.json: full trees + gear per class
  var S = { race: -1, cls: -1, t: [[], [], []], gear: [], name: "", lg: "" };
  var LEGACY = null, LEGACY_LOADING = null;   // codex.json legacy block, fetched on first open
  var GEAR = null;                            // ForgeGear over plan/items.json
  var lastSwap = null;
  var CMP = false;
  var CMPF = "";                         // light only one compare status                       // the Classic layer: both tooltips, differences marked
  var CMP_LABEL = { "new": "NEW", changed: "CHG", moved: "MOV", renamed: "REN", rank: "RNK", unverified: "?", same: "" };
  var CMP_WORD = { "new": "New in Forever", changed: "Changed from Classic", moved: "Moved in the tree",
    renamed: "Renamed from Classic", rank: "Different rank by 38", same: "Same as Classic", removed: "Classic only",
    unverified: "Not captured yet" };
  // Word-level diff (LCS). Returns [classicHTML, foreverHTML] with <del>/<ins> marks.
  function wordDiff(oldT, newT) {
    var a = String(oldT || "").match(/\S+/g) || [], b = String(newT || "").match(/\S+/g) || [];
    var n = a.length, m = b.length, L = [], i, j;
    function k(w) { return w.toLowerCase().replace(/[.,;:()"]/g, ""); }
    for (i = 0; i <= n; i++) { L.push([]); for (j = 0; j <= m; j++) L[i].push(0); }
    for (i = n - 1; i >= 0; i--) for (j = m - 1; j >= 0; j--)
      L[i][j] = k(a[i]) === k(b[j]) ? L[i + 1][j + 1] + 1 : Math.max(L[i + 1][j], L[i][j + 1]);
    var oa = [], ob = []; i = 0; j = 0;
    while (i < n && j < m) {
      if (k(a[i]) === k(b[j])) { oa.push(esc(a[i])); ob.push(esc(b[j])); i++; j++; }
      else if (L[i + 1][j] >= L[i][j + 1]) oa.push("<del>" + esc(a[i++]) + "</del>");
      else ob.push("<ins>" + esc(b[j++]) + "</ins>");
    }
    while (i < n) oa.push("<del>" + esc(a[i++]) + "</del>");
    while (j < m) ob.push("<ins>" + esc(b[j++]) + "</ins>");
    return [oa.join(" ").replace(/<\/del> <del>/g, " "), ob.join(" ").replace(/<\/ins> <ins>/g, " ")];
  }
  function firstRank(ds) {
    for (var q = 0; q < (ds || []).length; q++) if (ds[q]) return q;
    return -1;
  }
  function cmpBadge(s) { return s && CMP_LABEL[s] ? '<i class="cmpf cmp-' + s + '">' + CMP_LABEL[s] + "</i>" : ""; }
  // Both tooltips in one card. kind: "t" talent, others arrive with spell/racial data.
  function cmpCard(title, s, foreverText, classicText, meta, foot) {
    var head = '<div class="cmp-h"><b>' + esc(title) + '</b><span class="cmp-pill cmp-' + s + '">' + esc(CMP_WORD[s] || s) + "</span></div>";
    if (s === "new" || !classicText) {
      return head + '<div class="cmp-cols one"><div class="cmp-new"><h6>Forever</h6><p>' + esc(foreverText || "No tooltip transcribed.") + "</p></div></div>" +
        (meta ? '<p class="cmp-meta">' + esc(meta) + "</p>" : "") + (foot ? '<p class="cmp-foot">' + esc(foot) + "</p>" : "");
    }
    if (s === "removed" || !foreverText) {
      return head + '<div class="cmp-cols one"><div class="cmp-old"><h6>Classic</h6><p>' + esc(classicText) + "</p></div></div>" +
        (meta ? '<p class="cmp-meta">' + esc(meta) + "</p>" : "") + (foot ? '<p class="cmp-foot">' + esc(foot) + "</p>" : "");
    }
    var dd = wordDiff(classicText, foreverText);
    return head + '<div class="cmp-cols"><div class="cmp-old"><h6>Classic</h6><p>' + dd[0] + '</p></div><div class="cmp-new"><h6>Forever</h6><p>' + dd[1] + "</p></div></div>" +
      (meta ? '<p class="cmp-meta">' + esc(meta) + "</p>" : "") + (foot ? '<p class="cmp-foot">' + esc(foot) + "</p>" : "");
  }
  function cmpTalent(ti, i) {
    var c = clsData(); if (!c) return "";
    var tr = c.trees[ti], t = tr.talents[i], cl = t.c || { s: "same" };
    var fr = firstRank(t.desc), ftxt = fr >= 0 ? t.desc[fr] : (t.tip || "");
    var meta = [];
    if (cl.s !== "new") {
      if (cl.tr && (cl.tr !== tr.name || cl.r !== t.row || cl.co !== t.col))
        meta.push("Classic spot: " + cl.tr + " row " + cl.r + ", column " + cl.co + ". Forever: " + tr.name + " row " + t.row + ", column " + t.col + ".");
      if (cl.m && cl.m !== t.r) meta.push("Ranks: " + cl.m + " in Classic, " + t.r + " in Forever.");
    } else meta.push("Not in the Classic trees. " + t.r + (t.r === 1 ? " rank." : " ranks."));
    var foot = cl.s === "new" ? "" : "Classic rank 1 against Forever rank " + (fr + 1) + (t.est ? "; Forever numbers are still estimates" : "") + ". Struck words are gone, marked words are new.";
    return cmpCard(t.n, cl.s || "same", ftxt, cl.t, meta.join(" "), foot);
  }
  function cmpExtra(p) {
    var c = clsData(), book = c && c.book, e, meta = [];
    if ((p[0] === "s" || p[0] === "co") && book) {
      var name = decodeURIComponent(p[1]);
      if (p[0] === "co") {
        e = (book.classicOnly || []).filter(function (x) { return x.n === name; })[0];
        if (!e) return "";
        if (e.hd) meta.push(e.hd);
        if (e.note) meta.push(e.note);
        return cmpCard(name, "removed", "", e.ct || "Not in the Forever demo book.", meta.join(" "), "A Classic spell a level-38 character could train that the Forever demo book did not list.");
      }
      e = (book.cmp || {})[name];
      if (!e) return "";
      if (e.cn && e.cn !== name) meta.push("Classic name: " + e.cn + ".");
      if (e.cr) meta.push("Classic at 38: " + e.cr + (e.cl ? ", trained at level " + e.cl : "") + ".");
      if (e.hd) meta.push("Classic header: " + e.hd + ".");
      if (e.note) meta.push(e.note);
      return cmpCard(name, e.s || "same", (book.desc || {})[name], e.ct, meta.join(" "),
        e.s === "new" ? "No Classic spell of this name." : "Wowhead Classic tooltip against the BlizzCon demo tooltip" + (e.rk ? " (" + e.rk + ")" : "") + ".");
    }
    if ((p[0] === "r" || p[0] === "rx") && DATA && DATA.races) {
      var R = DATA.races[+p[1]];
      if (!R) return "";
      if (p[0] === "rx") {
        e = (R.classicRemoved || [])[+p[2]];
        if (!e) return "";
        return cmpCard(e.n, "removed", "", e.ct, e.note || "", "Classic racial that Forever's " + R.n + " list does not carry.");
      }
      var a = R.abilities[+p[2]]; if (!a) return "";
      e = (R.cmp || {})[a[0]] || { s: "same" };
      if (e.cn && e.cn !== a[0]) meta.push("Classic name: " + e.cn + ".");
      if (e.note) meta.push(e.note);
      return cmpCard(a[0], e.s, a[1], e.ct, meta.join(" "), e.s === "new" ? "Not a Classic racial." : "Wowhead Classic racial tooltip against the demo tooltip.");
    }
    return "";
  }
  function cmpLookup(key) {
    var p = String(key).split(":");
    if (p[0] === "t") return cmpTalent(+p[1], +p[2]);
    if (typeof cmpExtra === "function") return cmpExtra(p);
    return "";
  }
  var viewStep = null;   // revisit a step without losing the build                   // the compare panel's food
  var STEPS = ["Race", "Class", "Talents", "Legacy", "Gear", "Name it"];
  var GUIDE = {
    0: "<b>Pick a race.</b> Its racials unfold below.",
    1: "<b>Pick a class.</b> NEW marks combos Classic never allowed.",
    2: "<b>Your points are your spec.</b>"
  };

  function $(id) { return document.getElementById(id); }
  function esc(s) { return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
  function cc(k) { return CLASS_COLOUR[k] || "#fff"; }
  function icon(name, cls) { return '<img class="' + (cls || "wi") + '" src="' + CDN + name + '.jpg" alt="" loading="lazy" onerror="this.style.visibility=\'hidden\'">'; }
  function attrEnc(v) { return esc(v).replace(/"/g, "&quot;"); }
  function dt(title, body) { return 'data-tip="' + attrEnc("<b>" + esc(title) + "</b>" + esc(body)) + '"'; }
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
    return [S.race, S.cls, S.t.map(function (a) { var o = ""; for (var i = 0; i < a.length; i++) o += (a[i] || 0); return o; }).join("-"),
      (GEAR ? GEAR.encode(S.eq || {}) : (S.eqRaw || "")),
      encodeURIComponent(S.name || "").replace(/\./g, "%2E"), cap, S.lg || ""].join(".").replace(/\.$/, "");
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
    o.eqRaw = String(p[3] || "");
    o.eq = GEAR ? GEAR.decode(o.eqRaw) : {};
    o.cap = CAPS[+p[5]] ? +p[5] : 30;
    o.lg = /^[0-5]{1,12}(-[0-5]{0,12}){0,4}$/.test(p[6] || "") ? p[6] : "";
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
    // A budget cut can orphan a talent: drop anything whose row gate or prerequisite no longer holds.
    for (ti = 0; ti < 3; ti++) {
      var tl = c.trees[ti].talents, byN = {};
      tl.forEach(function (t, j) { byN[t.n] = j; });
      for (var changed = true; changed;) {
        changed = false;
        tl.forEach(function (t, j) {
          if (!o.t[ti][j]) return;
          var below = 0;
          tl.forEach(function (u, k) { if (u.row < t.row) below += o.t[ti][k] || 0; });
          var reqBad = t.req && byN[t.req] != null && (o.t[ti][byN[t.req]] || 0) < tl[byN[t.req]].r;
          if (below < (t.row - 1) * 5 || reqBad) { o.t[ti][j] = 0; changed = true; }
        });
      }
    }
    return o;
  }
  function syncURL() {
    if (!DATA) return;   // the boot render must not strip an unread ?b link
    var done = S.race >= 0 && S.cls >= 0;
    history.replaceState(null, "", (done ? "?b=" + code() + (CMP ? "&cmp=1" : "") : (CMP ? "?cmp=1" : location.pathname)));
    try { localStorage.setItem("forge3", done ? code() : ""); } catch (e) {}
  }

  // ---- tooltips -------------------------------------------------------------
  // Mouse gets hover tooltips; touch gets a bottom sheet (TipKit, shared with the Database).
  function tipHTML(el) {
    var ck = CMP && el.getAttribute("data-cmp");
    return (ck && cmpLookup(ck)) || el.getAttribute("data-tip");
  }
  function tipCls(el) {
    var ck = CMP && el.getAttribute("data-cmp");
    return ck && cmpLookup(ck) ? "cmp-tip" : (el.getAttribute("data-tipcls") || "");
  }
  function hideTip() { if (window.TipKit) TipKit.hide(); }
  function bindTips(root) {
    root.querySelectorAll("[data-tip]").forEach(function (el) {
      TipKit.hover(el, tipHTML, tipCls);
      if (el.matches("[data-tal], [data-race], [data-cls], button, a")) return;
      el.setAttribute("data-tipkit", "1");
      el.addEventListener("click", function () {
        if (TipKit.touchy()) TipKit.openSheet(tipHTML(el), [], { cls: tipCls(el) });
      });
    });
  }
  // ---- talent points: one rulebook for clicks, right clicks and sheet buttons ----
  function talentRefs(ti, i) {
    var tree = clsData().trees[ti], t = tree.talents[i], byName = {};
    tree.talents.forEach(function (x, j) { byName[x.n] = j; });
    return { tree: tree, t: t, byName: byName };
  }
  function canAdd(ti, i) {
    var R = talentRefs(ti, i), t = R.t;
    var reqOk = !t.req || R.byName[t.req] == null || (S.t[ti][R.byName[t.req]] || 0) >= R.tree.talents[R.byName[t.req]].r;
    return treePts(ti) >= (t.row - 1) * 5 && reqOk && spent() < POINTSNOW() && (S.t[ti][i] || 0) < t.r;
  }
  function canRemove(ti, i) {
    var R = talentRefs(ti, i), t = R.t, tree = R.tree;
    if ((S.t[ti][i] || 0) === 0) return false;
    if (tree.talents.some(function (x, j) { return x.req === t.n && (S.t[ti][j] || 0) > 0; })) return false;
    return !tree.talents.some(function (x, j) {
      if (x.row <= t.row || !(S.t[ti][j] || 0)) return false;
      var below = 0;
      tree.talents.forEach(function (y, k) { if (y.row < x.row) below += (S.t[ti][k] || 0); });
      return below - 1 < (x.row - 1) * 5;
    });
  }
  function lgPoints(codeStr) {
    if (LEGACY && window.LegacyWindow) return LegacyWindow(LEGACY, { code: codeStr }).spent();
    return Math.min(16, String(codeStr || "").replace(/[^0-9]/g, "").split("").reduce(function (a, b) { return a + (+b); }, 0));
  }
  function loadLegacy() {
    if (LEGACY) return Promise.resolve(LEGACY);
    if (!LEGACY_LOADING) LEGACY_LOADING = fetch("../codex/codex.json").then(function (r) { return r.json(); }).then(function (d) { LEGACY = d.legacy; return LEGACY; });
    return LEGACY_LOADING;
  }
  function legacyLines() {
    if (!LEGACY || !S.lg) return [];
    var w = LegacyWindow(LEGACY, { code: S.lg });
    return w.summary().filter(function (t) { return t.points; }).map(function (t) { return t.tree + " " + t.points + ": " + t.perks.join(", "); });
  }
  function gearNames() {
    if (!GEAR) return [];
    return GEAR.SLOT_KEYS.map(function (k) { var it = GEAR.byId[(S.eq || {})[k]]; return it ? it.name : null; }).filter(Boolean);
  }
  var lgCloser = null;
  function closeInsight() {
    if ($("insight").classList.contains("lgmode") && lgCloser) { lgCloser(); return; }
    $("insight").hidden = true;
    $("insight").classList.remove("lgmode", "pkmode");
    hideTip();
    if (window.TipKit) TipKit.closeSheet();
  }
  function openLegacy() {
    hideTip();
    loadLegacy().then(function (lgData) {
      $("insight").classList.remove("sbmode", "pkmode");
      $("insight").classList.add("lgmode");
      $("insight").hidden = false;
      var w = LegacyWindow(lgData, {
        root: $("insight-body"), code: S.lg, base: "../codex/",
        onApply: function (c) { S.lg = c; render(); },
        onClose: function () { lgCloser = null; $("insight").hidden = true; $("insight").classList.remove("lgmode"); render(); }
      });
      lgCloser = w.close;
      w.draw();
    });
  }
  function updateLegacyBtn() {
    var b = $("lg-open");
    if (b) b.querySelector("em").textContent = lgPoints(S.lg) + " / 16";
  }
  function openPicker(slot, q, qual) {
    hideTip();
    $("insight").classList.remove("sbmode", "lgmode");
    $("insight").classList.add("pkmode");
    $("insight-body").innerHTML = GEAR.pickerHTML(slot, q, qual);
    $("insight").hidden = false;
    var box = $("insight-body");
    bindTips(box);
    function close() { $("insight").hidden = true; $("insight").classList.remove("pkmode"); hideTip(); render(); }
    box.querySelectorAll("[data-gpick]").forEach(function (b) {
      b.addEventListener("click", function () {
        var id = b.getAttribute("data-gpick"), it = GEAR.byId[id];
        S.eq = S.eq || {};
        S.eq[slot] = id;
        if (slot === "mainhand" && it && it.slot === "two-hand") delete S.eq.offhand;
        if (slot === "offhand" && S.eq.mainhand && GEAR.byId[S.eq.mainhand] && GEAR.byId[S.eq.mainhand].slot === "two-hand") delete S.eq.mainhand;
        close();
      });
    });
    var qi = box.querySelector("[data-gpq]");
    if (qi) qi.addEventListener("input", function () {
      var caret = qi.selectionStart;
      openPicker(slot, qi.value, qual);
      var q2 = $("insight-body").querySelector("[data-gpq]");
      if (q2) { q2.focus(); try { q2.setSelectionRange(caret, caret); } catch (e) {} }
    });
    box.querySelectorAll("[data-gpqual]").forEach(function (b) {
      b.addEventListener("click", function () { var v = b.getAttribute("data-gpqual"); openPicker(slot, q, qual === v ? "" : v); });
    });
    var un = box.querySelector("[data-gpclear]");
    if (un) un.addEventListener("click", function () { if (S.eq) delete S.eq[slot]; close(); });
    var x = box.querySelector("[data-gpx]");
    if (x) x.addEventListener("click", close);
  }
  function slotEl(ti, i) { return $("stage").querySelector('.slot[data-tal="' + ti + ":" + i + '"]'); }
  function afterTalent(ti, i) {
    render();
    var el = slotEl(ti, i);
    if (!el) return;
    if (TipKit.sheetOpen()) talentSheet(ti, i);
    else if (!TipKit.touchy()) TipKit.show(tipHTML(el), tipCls(el));
  }
  function talentSheet(ti, i) {
    var el = slotEl(ti, i);
    if (!el) return;
    var t = clsData().trees[ti].talents[i], r = S.t[ti][i] || 0;
    TipKit.openSheet(tipHTML(el), [
      { label: "Unlearn \u2212", cls: "unlearn", disabled: !canRemove(ti, i), onClick: function () { if (canRemove(ti, i)) { S.t[ti][i]--; afterTalent(ti, i); } } },
      { label: r + " / " + t.r, cls: "count", disabled: true },
      { label: "Learn +", cls: "learn", disabled: !canAdd(ti, i), onClick: function () { if (canAdd(ti, i)) { S.t[ti][i] = (S.t[ti][i] || 0) + 1; afterTalent(ti, i); } } }
    ], { cls: tipCls(el), owner: "t:" + ti + ":" + i, onClose: function () {
      document.querySelectorAll(".tghost.show").forEach(function (g) { g.classList.remove("show"); });
    } });
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
    var R = S.race >= 0 ? RACES[S.race] : null, K = S.cls >= 0 ? CLASS_ORDER[S.cls] : null;
    var sub = [R ? R.n : "Choose", K ? CLASS_LABEL[K] : "Choose", K && DATA ? spent() + " / " + POINTSNOW() : "Points", lgPoints(S.lg) + " / 16 LP", GEAR ? Object.keys(S.eq || {}).length + " / " + GEAR.SLOT_KEYS.length : "At beta", S.name || "Share"];
    var ico = [R ? icon(R.i, "st-ic") : "", K ? icon(CLASS_ICON[K], "st-ic") : "", "", icon("inv_shield_06", "st-ic"), "", ""];
    $("fsteps").innerHTML = STEPS.map(function (n, i) {
      var logical = i <= 1 ? i : 2;
      var cls = logical < now ? "done" : logical === now ? (i > 2 ? "done" : "now") : "locked";
      if (i === 3) cls = "done lgstep";
      return '<li class="' + cls + (i === 4 && !(GEAR && GEAR.count) ? " soon" : "") + '" data-step="' + i + '">' + (ico[i] || '<span class="st-num">' + (i + 1) + "</span>") +
        '<span class="st-t"><b>' + n + "</b><em" + (i === 1 && K ? ' style="color:' + cc(K) + '"' : "") + ">" + esc(sub[i]) + "</em></span></li>";
    }).join("");
    var keys = now === 2 ? (window.TipKit && TipKit.touchy() ? '<span class="keys"><kbd>Tap</kbd> a talent to learn or unlearn</span>'
      : '<span class="keys"><kbd>Click</kbd> learn <kbd>Right-click</kbd> unlearn <kbd>Shift</kbd> fill or empty</span>') : "";
    $("guide").innerHTML = "<p>" + GUIDE[now] + keys + "</p>";
  }

  function render() {
    drawSteps(); syncURL(); updateLegacyBtn();
    var gb = $("cmp-global");
    if (gb) { gb.classList.toggle("on", CMP); gb.setAttribute("aria-pressed", String(CMP)); }
    var st = $("stage"), now = viewStep != null ? viewStep : stepNow(), html = swapHTML();
    if (!DATA) {
      st.innerHTML = '<div class="verdict">Forging the class data\u2026</div>';
      return;
    }
    if (viewStep === 0 && S.cls < 0 && S.race >= 0)
      $("guide").innerHTML = "<p>Racials below. <b>Continue to the class.</b></p>";
    if (viewStep === 0 && S.cls >= 0)
      $("guide").innerHTML = "<p><b>Swap the race, keep the build.</b></p>";
    if (viewStep === 1 && S.cls >= 0)
      $("guide").innerHTML = "<p><b>Changing class resets talents.</b></p>";
    if (now === 0) html += raceStage() + (S.race >= 0 ? raceExpand(S.race) : "");
    else if (now === 1) html += classStage();
    else html += talentsHTML() + gearHTML() + nameHTML() + buildHTML();
    hideTip();
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
      var ri = DATA.races.indexOf(tf);
      return '<ul class="racials' + (CMP ? " cmp-on" : "") + '">' + tf.abilities.map(function (a, ai) {
        var cs = CMP && tf.cmp ? ((tf.cmp[a[0]] || {}).s || "same") : "";
        return '<li class="' + (cs ? "cmp-" + cs : "") + '" data-tip="' + esc("<b>" + esc(a[0]) + "</b>" + esc(a[1])) + '" data-cmp="r:' + ri + ":" + ai + '">' +
          (a[2] ? icon(a[2], "wi wi-sm") : "") + '<b>' + esc(a[0]) + (cs && CMP_LABEL[cs] ? ' <i class="cmpf inl cmp-' + cs + '">' + CMP_LABEL[cs] + "</i>" : "") + '</b><span>' +
          esc(a[1]) + '</span><i class="tag shared">demo</i></li>';
      }).join("") +
      (CMP && tf.classicRemoved && tf.classicRemoved.length ? tf.classicRemoved.map(function (x, xi) {
        return '<li class="cmp-removed gone" data-tip="' + esc("<b>" + esc(x.n) + "</b>" + esc(x.ct || "")) + '" data-cmp="rx:' + ri + ":" + xi + '">' +
          '<b>' + esc(x.n) + ' <i class="cmpf inl cmp-removed">CLASSIC</i></b><span>' + esc(x.ct || "") + "</span></li>";
      }).join("") : "") + "</ul>" +
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

  function cmpTally(list) {
    var n = { "new": 0, changed: 0, moved: 0, same: 0 };
    list.forEach(function (t) { var s = (t.c && t.c.s) || "same"; n[s] = (n[s] || 0) + 1; });
    return n;
  }
  function cmpCounts(list) {
    var n = cmpTally(list);
    return '<s class="nextrow cmpcount">' + ["new", "changed", "moved"].filter(function (k) { return n[k]; }).map(function (k) {
      return '<em class="cmp-' + k + '">' + n[k] + " " + (k === "changed" ? "chg" : k === "moved" ? "mov" : "new") + "</em>";
    }).join(" ") + (n.same ? ' <em class="cmp-same">' + n.same + " same</em>" : "") + "</s>";
  }
  function cmpLegend(c) {
    var all = [];
    c.trees.forEach(function (tr) { all = all.concat(tr.talents); });
    var n = cmpTally(all), diff = all.length - n.same;
    return '<div class="cmpchips"><span class="cc-sum"><b>' + diff + "</b> of " + all.length + " differ</span>" +
      [["new", "NEW", "Not in Classic"], ["changed", "CHG", "Text or ranks changed"], ["moved", "MOV", "Moved in the tree"], ["same", "SAME", "Same as Classic"]].map(function (x) {
        return '<button type="button" class="cc cmp-' + x[0] + (CMPF === x[0] ? " on" : "") + '" data-cmpf="' + x[0] + '" aria-pressed="' + (CMPF === x[0]) + '" data-tip="' +
          attrEnc("<b>" + x[2] + "</b>Click to light only these; click again for all.") + '"><i class="cmpf inl cmp-' + x[0] + '">' + x[1] + "</i>" + n[x[0]] + "</button>";
      }).join("") + '<span class="cc-hint">Hover a talent for both tooltips</span></div>';
  }

  function talentsHTML() {
    var c = clsData(), sp = specNow();
    var done = spent() >= POINTSNOW();
    var K = CLASS_ORDER[S.cls], total = POINTSNOW(), used = spent(), left = total - used;
    var RR = 18, CIRC = 2 * Math.PI * RR, frac = total ? used / total : 0;
    var html = '<div class="tbar">' +
      '<div class="tb-spec">' + icon(CLASS_ICON[K], "tb-cls") + '<div><b style="color:' + cc(K) + '">' + esc(used ? sp.name : CLASS_LABEL[K]) + "</b>" +
        '<span class="rolechip ' + (used ? sp.role : "") + '">' + (used ? sp.role : "no points yet") + "</span></div></div>" +
      '<div class="tb-points' + (done ? " alldone" : "") + '"><svg class="pring" viewBox="0 0 44 44" aria-hidden="true"><circle cx="22" cy="22" r="18" class="pr-bg"/>' +
        '<circle cx="22" cy="22" r="18" class="pr-fg" style="stroke-dasharray:' + (CIRC * frac).toFixed(1) + " " + CIRC.toFixed(1) + '"/></svg>' +
        "<div><b>" + left + "</b><span>" + (done ? "all placed" : "points left") + "</span></div></div>" +
      '<div class="tb-split">' + c.trees.map(function (tr, ti) {
        var p = treePts(ti);
        return '<span class="' + (p ? "on" : "") + '" data-tip="' + attrEnc("<b>" + esc(tr.name) + "</b>" + p + (p === 1 ? " point" : " points")) + '">' + icon(tr.icon, "wi") + "<b>" + p + "</b></span>";
      }).join("") + "</div>" +
      '<div class="tb-lvl" data-tip="' + attrEnc("<b>Level needed</b>The first talent point arrives at level 10, then one per level.") + '"><b>' + (used ? 9 + used : 10) + "</b><span>level</span></div>" +
      '<div class="tb-cap" role="group" aria-label="Level cap"><span>Cap</span>' + [20, 30, 60].map(function (l) {
        return '<button type="button" class="capbtn' + (cap === l ? " on" : "") + '" data-cap="' + l + '">' + l + "</button>";
      }).join("") + "</div>" +
      '<div class="tb-acts">' +
        '<button type="button" class="tb-btn cmpswitch' + (CMP ? " on" : "") + '" id="cmpbtn" aria-pressed="' + CMP + '" data-tip="' +
          attrEnc("<b>Compare to Classic</b>Badges every talent that is new, changed or moved, with both tooltips side by side.") + '"><i></i><span>Classic</span></button>' +
        '<button type="button" class="tb-btn" id="bookbtn" data-tip="' + attrEnc("<b>Spellbook</b>Every spell the level 38 demo character had.") + '">' + icon("inv_misc_book_11", "wi") + "<span>Spellbook</span></button>" +
        (used ? '<button type="button" class="tb-btn danger" id="treset" data-tip="' + attrEnc("<b>Reset talents</b>Refund every point.") + '"><span class="tb-glyph">\u21ba</span><span>Reset</span></button>' : "") +
      "</div></div>" +
      (CMP ? cmpLegend(c) : "") + '<div class="wtrees">';
    c.trees.forEach(function (tr, ti) {
      var pts = treePts(ti);
      var byName = {}, maxRow = 1;
      tr.talents.forEach(function (t, i) { byName[t.n] = i; if (t.row > maxRow) maxRow = t.row; });
      var nextGate = null;
      for (var rw = 2; rw <= maxRow; rw++) if (pts < (rw - 1) * 5) { nextGate = (rw - 1) * 5; break; }
      html += '<div class="wtree"' + (tr.bg ? ' style="background-image:url(' + tr.bg + ')"' : "") +
        '><div class="wt-head">' + icon(tr.icon, "wi wi-sm") + "<b>" + esc(tr.name) +
        (CMP ? cmpCounts(tr.talents) : nextGate != null ? '<s class="nextrow">next row at ' + nextGate + "</s>" : "") + '</b><u>' + pts + "</u>" +
        (pts > 0 ? '<button type="button" class="tre-reset" data-treset="' + ti + '" title="Reset ' + esc(tr.name) + '">\u21ba</button>' : "") +
        '</div><div class="wt-grid rows5">';
      // Prerequisite arrows, drawn behind the icons.
      var arrows = "";
      tr.talents.forEach(function (t) {
        if (!t.req || byName[t.req] == null) return;
        var s = tr.talents[byName[t.req]];
        var ok = (S.t[ti][byName[t.req]] || 0) >= s.r;
        var x1 = (s.col - 1) * 36 + 15.5, y1 = (s.row - 1) * 41 + 15.5;
        var x2 = (t.col - 1) * 36 + 15.5, y2 = (t.row - 1) * 41 + 15.5;
        arrows += '<line class="tarrow' + (ok ? " ok" : "") + '" x1="' + x1 + '" y1="' + y1 + '" x2="' + x2 + '" y2="' + y2 + '"/>' +
          '<polygon class="tarrow-h' + (ok ? " ok" : "") + '" points="' + (x2 - 4) + "," + (y2 - 22) + " " + (x2 + 4) + "," + (y2 - 22) + " " + x2 + "," + (y2 - 16) + '"/>';
      });
      if (arrows) html += '<svg class="warrows" viewBox="0 0 139 ' + (maxRow * 41 - 5) + '" preserveAspectRatio="none">' + arrows + "</svg>";
      if (CMP) tr.talents.forEach(function (t, i) {
        if (t.c && t.c.s === "moved" && t.c.tr === tr.name && t.c.r && t.c.co)
          html += '<div class="tghost" data-ghost="' + ti + ":" + i + '" style="grid-column:' + t.c.co + ";grid-row:" + t.c.r + '"><span>Classic</span></div>';
      });
      tr.talents.forEach(function (t, i) {
        var r = S.t[ti][i] || 0, gate = (t.row - 1) * 5;
        var reqOk = !t.req || byName[t.req] == null || (S.t[ti][byName[t.req]] || 0) >= tr.talents[byName[t.req]].r;
        var open = pts >= gate && reqOk;
        var want = r < t.r ? r : t.r - 1, ds = t.desc || [], idx = -1, q;
        for (q = want; q >= 0; q--) if (ds[q]) { idx = q; break; }
        if (idx < 0) for (q = want + 1; q < ds.length; q++) if (ds[q]) { idx = q; break; }
        var have = idx >= 0 ? 1 : 0;
        var d = have ? ds[idx] : (t.tip || "");
        var clamped = have > 0 && idx !== want;
        var extra = (clamped ? " [rank " + (idx + 1) + " text; the demo never showed rank " + (want + 1) + "]" : "") +
          (t.est ? " [numbers still estimates]" : "") + (t.cn ? " \u00b7 " + t.cn + "." : "");
        var how = pts < gate ? '<span class="hint lock">Needs ' + gate + " points in " + esc(tr.name) + ".</span>"
          : !reqOk ? '<span class="hint lock">Requires ' + esc(t.req) + " maxed." + (t.reqText ? " " + esc(t.reqText) + "." : "") + "</span>"
          : (done && r < t.r) ? '<span class="hint lock mouse-only">No points left; right-click something to take one back.</span><span class="hint lock touch-only">No points left; unlearn something first.</span>'
          : '<span class="hint mouse-only">Left click adds, right click removes, shift fills or empties.</span>';
        var cs = (t.c && t.c.s) || "same";
        html += '<div class="slot' + (r >= t.r ? " maxed" : r > 0 ? " part" : "") + (open ? "" : " locked") + (t.est ? " est" : "") + (done && r === 0 && open ? " tapped" : "") +
          (CMP ? " cmp cmp-" + cs + (CMPF && CMPF !== cs ? " cmpdim" : "") : "") +
          '" style="grid-column:' + t.col + ";grid-row:" + t.row + '" data-tal="' + ti + ":" + i + '" data-tipkit="1" data-cmp="t:' + ti + ":" + i + '" ' +
          'data-tip="' + attrEnc("<b>" + esc(t.n + " (" + r + "/" + t.r + ")" + (r < t.r && have > 0 && !clamped ? ", rank " + (want + 1) + ":" : "")) + "</b>" + esc(d + extra) + how) + '">' +
          icon(t.icon, "wi") + (CMP ? cmpBadge(cs) : "") + '<span class="s-rank">' + r + "/" + t.r + "</span></div>";
      });
      html += "</div></div>";
    });
    html += "</div>";
    html += '<p class="tfoot">Trees from BlizzCon footage via talentsforever.com. Dashed rank badges are estimates.</p>';
    return html;
  }

  function gearHTML() {
    if (GEAR) {
      var R0 = RACES[S.race], K0 = CLASS_ORDER[S.cls], sp0 = specNow();
      return GEAR.html({ raceIcon: R0 && R0.i, classIcon: CLASS_ICON[K0], classColour: cc(K0), name: S.name || "Unnamed " + CLASS_LABEL[K0],
        line: (R0 ? R0.n + " " : "") + CLASS_LABEL[K0] + (spent() ? ", " + sp0.name : "") + ", level " + cap });
    }
    var slots = ["inv_helmet_03", "inv_jewelry_necklace_07", "inv_shoulder_02", "inv_misc_cape_02", "inv_chest_chain", "inv_bracer_07", "inv_gauntlets_05",
      "inv_belt_03", "inv_pants_03", "inv_boots_05", "inv_jewelry_ring_03", "inv_jewelry_talisman_07", "inv_sword_04", "inv_shield_04"];
    return '<div class="gearlock"><div class="gl-head"><b>Gear</b><span class="gl-badge">Unlocks with the beta</span></div>' +
      '<div class="gl-slots">' + slots.map(function (sl) { return '<span class="gl-slot">' + icon(sl, "wi") + "</span>"; }).join("") + "</div>" +
      "<p>Forever reworked every item. Real loot lands here when the beta opens on September 17.</p></div>";
  }

  function nameHTML() {
    return '<div class="namer"><input id="cname" maxlength="16" placeholder="Name your character" value="' + esc(S.name) + '">' +
      '<button type="button" class="nm-btn primary" id="bshare">Copy share link</button>' +
      '<button type="button" class="nm-btn" id="bcopy">Copy as text</button>' +
      '<button type="button" class="nm-btn ghost" id="breset">Start over</button></div>';
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
    var tal = talentList();
    return '<div class="buildcard"><h3>' + esc(S.name || "Unnamed " + CLASS_LABEL[k]) + "</h3>" +
      '<p class="line">' + icon(r.i, "wi wi-sm") + " " + esc(r.n) + ' · <span style="color:' + cc(k) + '">' + CLASS_LABEL[k] + "</span> · " +
      esc(sp.name) + " (" + esc(sp.split) + ') · <span class="rolechip ' + sp.role + '">' + sp.role + "</span> · level " + cap + "</p>" +
      '<p class="line"><i>Talents (' + spent() + "/" + POINTSNOW() + "):</i> " + (tal.length ? esc(tal.join(", ")) : "none yet, a purist") + "</p>" +
      (S.lg ? '<p class="line"><i>Legacy (' + lgPoints(S.lg) + "/16):</i> " + esc(legacyLines().join(" \u00b7 ") || lgPoints(S.lg) + " points") + "</p>" : "") +
      '<p class="line"><i>Gear:</i> ' + esc(gearNames().join(", ") || "none equipped") + "</p></div>";
  }
  function buildText() {
    var r = RACES[S.race], k = CLASS_ORDER[S.cls], c = clsData(), sp = specNow();
    return (S.name || "Unnamed") + ": " + r.n + " " + sp.name + " " + CLASS_LABEL[k] + " (" + sp.role + ", " + sp.split + ", cap " + cap + ")\n" +
      "Talents (" + spent() + "/" + POINTSNOW() + "):\n" + (talentList().map(function (t) { return "  " + t; }).join("\n") || "  none") +
      (S.lg ? "\nLegacy (" + lgPoints(S.lg) + "/16):\n" + (legacyLines().map(function (l) { return "  " + l; }).join("\n") || "  " + lgPoints(S.lg) + " points") : "") +
      "\nGear:\n" + (gearNames().map(function (g) { return "  " + g; }).join("\n") || "  none") + "\n" + location.origin + location.pathname + "?b=" + code();
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
    lastSwap = { title: "The Forge has spoken: " + race + " " + CLASS_LABEL[k],
      parts: [esc(CLASS_JOKE[k]), '<i class="finenote">The trees below are empty on purpose: the Forge picks the body and the job, the points are yours to place.</i>'] };
    viewStep = null;
    $("insight").hidden = true;
    render(); window.scrollTo(0, 0);
  }

  // ---- wiring ---------------------------------------------------------------
  function wire(st) {
    st.querySelectorAll("[data-gslot]").forEach(function (b) {
      b.addEventListener("click", function () {
        if (b.classList.contains("blocked")) return;
        openPicker(b.getAttribute("data-gslot"), "", "");
      });
    });
    var gcl = st.querySelector("[data-gclear]");
    if (gcl) gcl.addEventListener("click", function () { S.eq = {}; render(); });
    var cb = st.querySelector("#cmpbtn");
    if (cb) cb.addEventListener("click", function () { CMP = !CMP; CMPF = ""; hideTip(); render(); });
    st.querySelectorAll("[data-cmpf]").forEach(function (b) {
      b.addEventListener("click", function () { var k = b.getAttribute("data-cmpf"); CMPF = CMPF === k ? "" : k; hideTip(); render(); });
    });
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
        S.cls = i; S.t = [[], [], []]; S.gear = []; S.eq = {};
        viewStep = null;
        render();
      });
    });
    st.querySelectorAll(".slot[data-tal]").forEach(function (el) {
      var p = el.getAttribute("data-tal").split(":"), ti = +p[0], i = +p[1];
      function ghost(on) { var g = st.querySelector('[data-ghost="' + ti + ":" + i + '"]'); if (g) g.classList.toggle("show", on); }
      el.addEventListener("pointerenter", function () { ghost(true); });
      el.addEventListener("pointerleave", function () { ghost(false); });
      el.addEventListener("click", function (e) {
        if (TipKit.touchy()) {
          st.querySelectorAll(".tghost.show").forEach(function (g) { g.classList.remove("show"); });
          talentSheet(ti, i); ghost(true); return;
        }
        if (!canAdd(ti, i)) return;
        do { S.t[ti][i] = (S.t[ti][i] || 0) + 1; } while (e.shiftKey && canAdd(ti, i));
        afterTalent(ti, i);
      });
      el.addEventListener("contextmenu", function (e) {
        e.preventDefault();
        if (TipKit.touchy()) { talentSheet(ti, i); return; }
        if (!canRemove(ti, i)) return;
        do { S.t[ti][i]--; } while (e.shiftKey && canRemove(ti, i));
        afterTalent(ti, i);
      });
    });
    st.querySelectorAll(".tre-reset").forEach(function (b) {
      b.addEventListener("click", function () {
        S.t[+b.getAttribute("data-treset")] = []; render();
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
    var tr2 = st.querySelector("#treset");
    if (tr2) tr2.addEventListener("click", function () {
      S.t = [[], [], []];           // just the points; race, gear and name stay
      render();
    });
    var bk = st.querySelector("#bookbtn");
    if (bk) bk.addEventListener("click", function () {
      var c = clsData(), book = c.book || {}, k = CLASS_ORDER[S.cls];
      var treeIcon = {};
      c.trees.forEach(function (tr3) { treeIcon[tr3.name] = tr3.icon; });
      var tabs = (book.tabs || []).map(function (tb) {
        return { name: tb.name, icon: treeIcon[tb.name] || CLASS_ICON[k], spells: tb.spells || [] };
      });
      if (book.general && book.general.length) tabs.push({ name: "General", icon: CLASS_ICON[k], spells: book.general });
      tabs = tabs.filter(function (tb) { return tb.spells.length; });
      tabs.sort(function (a, b) {
        function w(t) { return t.name === "General" ? 0 : /^Pet/.test(t.name) ? 2 : 1; }
        return w(a) - w(b);
      });
      var PER = 21, cur = { tab: tabs.length > 1 ? 1 : 0, page: 0, q: "" };
      function cell(sp2, fb) {
        var d2 = (book.desc || {})[sp2[0]], co = sp2[2] === "co";
        var cs = CMP ? (co ? "removed" : ((book.cmp || {})[sp2[0]] || {}).s || "") : "";
        var hdr = (book.hdr || {})[sp2[0]] || [];
        var body = (sp2[1] ? '<span class="sbt-r">' + esc(sp2[1]) + "</span>" : "") +
          hdr.map(function (h) { return '<span class="sbt-l"><i>' + esc(h[0]) + "</i><i>" + esc(h[1]) + "</i></span>"; }).join("") +
          (d2 ? '<span class="sbt-d">' + esc(d2) + "</span>" : "") +
          ((book.src || {})[sp2[0]] === "classic" ? '<span class="sbt-n">Classic placeholder text: the demo tooltip was not captured.</span>' : "");
        var flag = cs && CMP_LABEL[cs] ? '<i class="cmpf cmp-' + cs + '">' + CMP_LABEL[cs] + "</i>" : cs === "removed" ? '<i class="cmpf cmp-removed">CL</i>' : "";
        return '<div class="sbs' + (cs ? " cmp-" + cs : "") + (co ? " gone" : "") + '" data-tipcls="sbtip" data-tip="' + attrEnc("<b>" + esc(sp2[0]) + "</b>" + body) +
          '" data-cmp="' + (co ? "co:" : "s:") + encodeURIComponent(sp2[0]) + '">' +
          '<span class="sbs-ic">' + iconFB(spellIcon(sp2[0], fb), fb) + flag + "</span>" +
          '<span class="sbs-t"><b>' + esc(sp2[0]) + "</b>" + (sp2[1] ? "<em>" + esc(sp2[1]) + "</em>" : "") + "</span></div>";
      }
      function bookTabs() {
        var out = tabs.slice();
        if (CMP && book.classicOnly && book.classicOnly.length)
          out.push({ name: "Classic only", icon: "inv_misc_book_09", spells: book.classicOnly.map(function (x) { return [x.n, x.lvl ? "Classic, level " + x.lvl : "Classic", "co"]; }) });
        return out;
      }
      function bookTally() {
        var n = {}, all = 0;
        tabs.forEach(function (t3) { t3.spells.forEach(function (s3) { var e3 = (book.cmp || {})[s3[0]]; var k3 = e3 ? e3.s : "unchecked"; n[k3] = (n[k3] || 0) + 1; all++; }); });
        var parts = ["new", "changed", "renamed", "rank", "unverified", "same"].filter(function (k3) { return n[k3]; }).map(function (k3) {
          return '<span title="' + esc(CMP_WORD[k3] || k3) + '"><i class="cmpf inl cmp-' + k3 + '">' + (CMP_LABEL[k3] || "SAME") + "</i> " + n[k3] + "</span>";
        });
        if (book.classicOnly && book.classicOnly.length) parts.push('<span title="Classic only"><i class="cmpf inl cmp-removed">CL</i> ' + book.classicOnly.length + "</span>");
        return '<div class="sb-tally">' + parts.join("") + "</div>";
      }
      function allSpells() {
        var out = [];
        bookTabs().forEach(function (t) { t.spells.forEach(function (s) { out.push({ s: s, icon: t.icon }); }); });
        return out;
      }
      function draw() {
        var tabsNow = bookTabs();
        if (cur.tab >= tabsNow.length) cur.tab = 0;
        var tb = tabsNow[cur.tab], list, title;
        if (cur.q.trim()) {
          var q = cur.q.trim().toLowerCase();
          list = allSpells().filter(function (x) { return (x.s[0] + " " + ((book.desc || {})[x.s[0]] || "")).toLowerCase().indexOf(q) !== -1; });
          title = "Search results";
        } else {
          list = tb.spells.map(function (s) { return { s: s, icon: tb.icon }; });
          title = tb.name;
        }
        list = list.slice().sort(function (a, b) { return a.s[0].localeCompare(b.s[0]); });
        var pages = Math.max(1, Math.ceil(list.length / PER));
        if (cur.page >= pages) cur.page = pages - 1;
        var slice = list.slice(cur.page * PER, cur.page * PER + PER);
        var rows = Math.max(1, Math.ceil(slice.length / 3));
        var html = '<div class="sbook">' +
          '<div class="sb-top"><span class="sb-port">' + iconFB(CLASS_ICON[k], CLASS_ICON[k]) + '</span><span class="sb-title">Spellbook</span>' +
          '<button type="button" class="sb-x" id="sb-x" aria-label="Close">&times;</button></div>' +
          '<div class="sb-bar"><div class="sb-tabs">' + tabsNow.map(function (t2, i2) {
            return '<button type="button" class="sb-tab' + (!cur.q.trim() && i2 === cur.tab ? " on" : "") + '" data-btab="' + i2 + '" aria-label="' + esc(t2.name) + '" data-tip="' + attrEnc("<b>" + esc(t2.name) + "</b>") + '">' +
              iconFB(t2.icon, CLASS_ICON[k]) + "</button>";
          }).join("") + "</div>" +
          '<label class="sb-search"><input id="sb-q" type="search" autocomplete="off" placeholder="Search abilities, keywords" value="' + esc(cur.q) + '"><span class="sb-drop" aria-hidden="true">&#9662;</span></label></div>' +
          '<div class="sb-page"><h3 class="sb-h">' + esc(title) + '</h3><div class="sb-rule"></div>' +
          (slice.length ? '<div class="sb-grid" style="grid-template-rows:repeat(' + rows + ',auto)">' + slice.map(function (x) { return cell(x.s, x.icon); }).join("") + "</div>"
            : '<p class="sb-empty">Nothing in this book matches.</p>') +
          '<div class="sb-foot"><span>Page ' + (cur.page + 1) + "/" + pages + "</span>" +
          '<button type="button" class="sb-pg" id="bk-prev"' + (cur.page === 0 ? " disabled" : "") + ' aria-label="Previous page">&#9664;</button>' +
          '<button type="button" class="sb-pg" id="bk-next"' + (cur.page >= pages - 1 ? " disabled" : "") + ' aria-label="Next page">&#9654;</button></div></div>' +
          '<div class="sb-under"><span class="sb-cap">Level ' + (book.level || "?") + " " + esc(book.race || "") + " " + esc(CLASS_LABEL[k]) + ", BlizzCon demo</span>" +
          (CMP && book.cmp ? bookTally() : "") +
          (book.cmp ? '<button type="button" class="sb-cmp' + (CMP ? " on" : "") + '" id="bk-cmp" aria-pressed="' + CMP + '"><i></i>Compare to Classic</button>' : "") +
          "</div></div>";
        $("insight").classList.remove("lgmode", "pkmode");
        $("insight").classList.add("sbmode");
        $("insight-body").innerHTML = html;
        $("insight").hidden = false;
        var box = $("insight-body");
        bindTips(box);
        box.querySelectorAll(".sb-tab").forEach(function (b2) {
          b2.addEventListener("click", function () { cur = { tab: +b2.getAttribute("data-btab"), page: 0, q: "" }; draw(); });
        });
        var qi = box.querySelector("#sb-q");
        if (qi) qi.addEventListener("input", function () {
          var caret = qi.selectionStart;
          cur.q = qi.value; cur.page = 0; draw();
          var q2 = $("insight-body").querySelector("#sb-q");
          if (q2) { q2.focus(); try { q2.setSelectionRange(caret, caret); } catch (e) {} }
        });
        var sx = box.querySelector("#sb-x");
        if (sx) sx.addEventListener("click", function () { $("insight").hidden = true; hideTip(); });
        var bkc = box.querySelector("#bk-cmp");
        if (bkc) bkc.addEventListener("click", function () { CMP = !CMP; hideTip(); draw(); render(); });
        var pv = box.querySelector("#bk-prev"), nx = box.querySelector("#bk-next");
        if (pv) pv.addEventListener("click", function () { if (cur.page > 0) { cur.page--; draw(); } });
        if (nx) nx.addEventListener("click", function () { cur.page++; draw(); });
      }
      draw();
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
      $("insight").classList.remove("sbmode", "lgmode", "pkmode");
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
  }

  // What each class brings to a group. The composer audits against this.
  var BRINGS = {
    buffs: [
      ["Power Word: Fortitude", ["PRIEST"], ["Power Word: Fortitude"]],
      ["Mark of the Wild", ["DRUID"], ["Mark of the Wild"]],
      ["Arcane Intellect", ["MAGE"], ["Arcane Intellect"]],
      ["Blessings (Might/Wisdom/Kings)", ["PALADIN"]],
      ["Battle Shout", ["WARRIOR"]],
      ["Totems (Windfury and friends)", ["SHAMAN"]],
      ["Soulstone and Healthstones", ["WARLOCK"]],
      ["Food and water, conjured", ["MAGE"]]
    ],
    cc: [
      ["Polymorph", ["MAGE"], ["Polymorph"]],
      ["Freezing Trap", ["HUNTER"], ["Freezing Trap"]],
      ["Sap / Blind", ["ROGUE"], ["Sap", "Blind"]],
      ["Fear / Banish / Seduce", ["WARLOCK"], ["Fear", "Banish"]],
      ["Shackle Undead", ["PRIEST"], ["Shackle Undead"]],
      ["Hibernate (beasts)", ["DRUID"], ["Hibernate"]],
      ["Hammer of Justice", ["PALADIN"], ["Hammer of Justice"]]
    ],
    kicks: [
      ["Kick", ["ROGUE"], ["Kick"]],
      ["Pummel / Shield Bash", ["WARRIOR"], ["Pummel", "Shield Bash"]],
      ["Earth Shock", ["SHAMAN"], ["Earth Shock"]],
      ["Counterspell", ["MAGE"], ["Counterspell"]]
    ],
    misc: [
      ["Battle rez (Rebirth)", ["DRUID"]],
      ["Summons (Ritual of Summoning)", ["WARLOCK"]],
      ["Tracking and Feign pulls", ["HUNTER"]]
    ]
  };
  // Does the level-38 demo spellbook for a class actually contain the spell?
  function bookHas(clsKey, names) {
    var ci = CLASS_ORDER.indexOf(clsKey);
    var book = ci >= 0 && DATA.classes[ci].book;
    if (!book || !(book.tabs || []).length) return null;   // no book captured
    var all = {};
    (book.tabs || []).forEach(function (tb) { tb.spells.forEach(function (sp) { all[sp[0]] = 1; }); });
    (book.general || []).forEach(function (sp) { all[sp[0]] = 1; });
    for (var i = 0; i < names.length; i++) if (all[names[i]]) return true;
    return false;
  }
  function coverage(list, have) {
    var got = [], unseen = [], miss = [];
    list.forEach(function (row) {
      var who = row[1].filter(function (k) { return have[k]; });
      if (!who.length) { miss.push(row[0]); return; }
      var verify = row[2] || [row[0]];
      var seen = bookHas(who[0], verify);
      if (seen === false) unseen.push([row[0], who[0]]);
      else got.push([row[0], who[0]]);
    });
    return { got: got, unseen: unseen, miss: miss };
  }
  function coverHTML(title, cov, missTone) {
    var chips = cov.got.map(function (g) {
      return '<span class="cchip good" style="--cc:' + cc(g[1]) + '">' + esc(g[0]) + "</span>";
    }).concat((cov.unseen || []).map(function (g) {
      return '<span class="cchip unseen" style="--cc:' + cc(g[1]) + '" ' +
        dt(g[0], "The class is here, but this spell was not seen in the level-38 demo spellbook. It may unlock later or have changed.") + ">" + esc(g[0]) + "</span>";
    })).concat(cov.miss.map(function (m) {
      return '<span class="cchip ' + missTone + '">' + esc(m) + "</span>";
    })).join("");
    return '<div class="coverrow"><label>' + title + "</label><div>" + chips + "</div></div>";
  }

  // Raid benefits that live in TALENTS: matched against the real Forever
  // talent names in the data, so a wrong guess simply never renders.
  var TALENT_BENEFITS = [
    ["WARRIOR", "Improved Battle Shout", "stronger Battle Shout"],
    ["WARRIOR", "Booming Voice", "longer, wider shouts"],
    ["PALADIN", "Blessing of Kings", "+10% all stats"],
    ["PALADIN", "Improved Blessing of Might", "stronger Might"],
    ["PALADIN", "Improved Devotion Aura", "more armour for everyone"],
    ["PRIEST", "Improved Power Word: Fortitude", "thicker Fortitude"],
    ["PRIEST", "Divine Spirit", "the Spirit buff"],
    ["DRUID", "Improved Mark of the Wild", "stronger Mark"],
    ["DRUID", "Leader of the Pack", "party crit aura"],
    ["DRUID", "Moonkin Form", "spell crit aura"],
    ["MAGE", "Improved Arcane Intellect", "smarter Intellect"],
    ["WARLOCK", "Improved Imp", "bigger Blood Pact"],
    ["WARLOCK", "Improved Healthstone", "bigger candy"],
    ["HUNTER", "Trueshot Aura", "party attack power"],
    ["SHAMAN", "Improved Weapon Totems", "stronger weapon totems"],
    ["SHAMAN", "Restorative Totems", "stronger mana and healing totems"]
  ];
  function talentBenefits(builds) {
    var got = [], untaken = [];
    TALENT_BENEFITS.forEach(function (row) {
      var ci = CLASS_ORDER.indexOf(row[0]);
      if (ci < 0) return;
      var loc = null;
      DATA.classes[ci].trees.forEach(function (tr, ti) {
        tr.talents.forEach(function (t, i) { if (t.n === row[1]) loc = [ti, i]; });
      });
      if (!loc) return;   // not a real Forever talent by that name; stay quiet
      var taker = null, present = false;
      builds.forEach(function (b) {
        if (b.cls !== ci) return;
        present = true;
        if ((b.t[loc[0]] || [])[loc[1]] > 0) taker = b.name || "someone";
      });
      if (taker) got.push([row[1] + " (" + row[2] + ")", row[0]]);
      else if (present) untaken.push([row[1], row[0]]);
    });
    return { got: got, untaken: untaken };
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
    return { name: c.trees[best].name, role: c.trees[best].role,
             pts: pts[0] + pts[1] + pts[2], split: pts.join("/") };
  }
  function bcode(b) {
    return [b.race, b.cls, b.t.map(function (a) { return a.join(""); }).join("-"),
      (GEAR ? GEAR.encode(b.eq || {}) : (b.eqRaw || "")), encodeURIComponent(b.name || "").replace(/\./g, "%2E"), b.cap || cap, b.lg || ""].join(".").replace(/\.$/, "");
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
        "<td>" + icon(RACES[b.race].i, "wi wi-sm") + " " + esc(RACES[b.race].n) + "</td><td>" + esc(sp.name) + " " + CLASS_LABEL[k] + ' <span class="meta">' + sp.split + "</span></td>" +
        '<td><span class="rolechip ' + sp.role + '">' + sp.role + "</span></td><td>" + sp.pts + "/" + POINTSNOW() + " pts</td></tr>";
    }).join("");
    var v = [];
    v.push("<b>" + builds.length + "</b> forged: " + roles.tank + " tank" + (roles.tank === 1 ? "" : "s") + ", " +
      roles.healer + " healer" + (roles.healer === 1 ? "" : "s") + ", " + roles.dps + " dps.");
    if (!roles.tank) v.push("Zero tanks: the dungeon will be tanked by whoever pulls first. Tradition.");
    if (!roles.healer) v.push("Zero healers: bold. The spirit healer thanks you for the business.");
    if (roles.tank && roles.healer && builds.length >= 5) v.push("This is, technically, a functioning group. Do not let it go to your heads.");
    if (classes.WARLOCK >= 2) v.push("Two-plus warlocks: summons for everyone, souls for no one.");
    if (classes.WARRIOR >= 3) v.push("Three warriors: the complaints will at least be synchronised.");
    var buffs = coverage(BRINGS.buffs, classes), ccov = coverage(BRINGS.cc, classes),
        kicks = coverage(BRINGS.kicks, classes), misc = coverage(BRINGS.misc, classes);
    if (!kicks.got.length && !kicks.unseen.length) v.push("Not a single interrupt. Every caster in the dungeon just relaxed.");
    if (!ccov.got.length && !ccov.unseen.length) v.push("No crowd control at all: every pull is a full pull. Godspeed.");
    var tb = talentBenefits(builds);
    var tbChips = tb.got.map(function (g) {
      return '<span class="cchip good" style="--cc:' + cc(g[1]) + '">' + esc(g[0]) + "</span>";
    }).concat(tb.untaken.map(function (g) {
      return '<span class="cchip unseen" style="--cc:' + cc(g[1]) + '" ' +
        dt(g[0], "A " + CLASS_LABEL[g[1]] + " is in the group but nobody spent the points. Awkward.") + ">" + esc(g[0]) + " (untaken)</span>";
    })).join("");
    var audit = '<div class="coverbox"><p class="in-h">What this group brings, and what it prays for</p>' +
      coverHTML("Buffs", buffs, "miss") +
      coverHTML("Crowd control", ccov, "miss") +
      coverHTML("Interrupts", kicks, "miss") +
      (tbChips ? '<div class="coverrow"><label>Talent benefits</label><div>' + tbChips + "</div></div>" : "") +
      coverHTML("Utility", misc, "soft") +
      '<p class="line finenote">Green: someone brings it, confirmed in the demo spellbook or their spent talents. Class-coloured dashed: the class is here but the spell was unseen at 38, or the talent sits untaken. Red: nobody\u2019s job.</p></div>';
    out.innerHTML = '<table class="raidtable"><thead><tr><th>Name</th><th>Race</th><th>Spec</th><th>Role</th><th>Talents</th></tr></thead><tbody>' +
      rows + "</tbody></table>" + audit + '<div class="verdict">' + v.join(" ") + "</div>";
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
    var boot_p = new URLSearchParams(location.search);
    CMP = boot_p.get("cmp") === "1";
    var lgb = $("lg-open");
    if (lgb) {
      lgb.addEventListener("click", openLegacy);
      TipKit.hover(lgb, function () { return "<b>Legacy Tree</b>Spend your 16 account-wide Legacy points without leaving the build."; });
    }
    var gbtn = $("cmp-global");
    if (gbtn) {
      gbtn.addEventListener("click", function () { CMP = !CMP; CMPF = ""; hideTip(); render(); });
      TipKit.hover(gbtn, function () { return "<b>Compare to Classic</b>Marks what is new, changed, moved or gone against WoW Classic, on talents, spells and racials."; });
    }
    render();
    fetch("plan-data.json", { cache: "no-store" }).then(function (r) { return r.json(); }).then(function (d) {
      return fetch("items.json", { cache: "no-store" }).then(function (r) { return r.ok ? r.json() : { items: [] }; }, function () { return { items: [] }; })
        .then(function (it) { GEAR = ForgeGear({ items: it, get: function () { return S.eq; } }); return d; });
    }).then(function (d) {
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
      var p = boot_p;
      if (p.get("raid")) {
        $("raid-in").value = location.href;
        render(); compose();
        $("composer").scrollIntoView();
      } else {
        var rawB = /[?&]b=([^&#]*)/.exec(location.search);
        var use = (rawB && parseCode(rawB[1])) || null;
        if (!use) { try { use = parseCode(localStorage.getItem("forge3")); } catch (e) {} }
        if (use) { cap = use.cap || 30; S = clampToData(use) || S; }
        render();
        if (S.lg) loadLegacy().then(function (d) { S.lg = LegacyWindow(d, { code: S.lg }).code(); render(); });
      }
    }).catch(function () {
      $("stage").innerHTML = '<div class="verdict">Could not load plan-data.json. The anvil is cold; refresh to relight it.</div>';
    });
    $("compose").addEventListener("click", compose);
    $("insight-x").addEventListener("click", closeInsight);
    $("insight").addEventListener("click", function (e) { if (e.target === $("insight")) closeInsight(); });
    document.addEventListener("keydown", function (e) { if (e.key === "Escape" && !$("insight").hidden) closeInsight(); });
    // Step bar: one delegated listener, so redraws of the bar never lose it.
    $("fsteps").addEventListener("click", function (e) {
      var li = e.target.closest && e.target.closest("li[data-step]");
      if (!li) return;
      var i = +li.getAttribute("data-step");
      if (i === 3) { openLegacy(); return; }
      if (i === 0) { viewStep = 0; }
      else if (i === 1 && S.race >= 0) { viewStep = 1; }
      else if (S.cls >= 0) { viewStep = null; }
      else return;
      render(); window.scrollTo(0, 0);
    });
  });
})();
