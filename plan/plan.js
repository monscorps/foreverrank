/* The Forge: plan a Forever beta character, share it as a link.
 * Classic bones, retail-quality presentation: vanilla talent data (condensed
 * to the beta's 21 points), the classic three-tree calculator layout, real
 * spell icons served from Wowhead's public icon CDN the way every fansite
 * and talent calculator does it. Corrected the day the beta is datamined. */
(function () {
  "use strict";

  var CAP = 30, POINTS = 21;
  var ICON_CDN = "https://wow.zamimg.com/images/wow/icons/large/";

  var CLASS_COLOUR = {
    WARRIOR: "#c79c6e", PALADIN: "#f58cba", HUNTER: "#abd473", ROGUE: "#fff569",
    PRIEST: "#ffffff", SHAMAN: "#0070de", MAGE: "#69ccf0", WARLOCK: "#9482c9", DRUID: "#ff7d0a"
  };

  var RACES = [
    { n: "Human", f: "Alliance", i: "achievement_character_human_male", tip: "Sword Specialization is now +2% crit with swords, not weapon skill. Extra Spirit, diplomacy. The beige of races; beige got buffed." },
    { n: "Dwarf", f: "Alliance", i: "achievement_character_dwarf_male", tip: "Stoneform still deletes bleeds, poisons and diseases. Mace crit, Find Treasure, and Big Game Hunter for extra beast damage. The mountain diversified." },
    { n: "Night Elf", f: "Alliance", i: "achievement_character_nightelf_male", tip: "Shadowmeld and Wisp Spirit stay; Elune's Light is new for combat. Dying fashionably remains free." },
    { n: "Gnome", f: "Alliance", i: "achievement_character_gnome_male", tip: "Expansive Mind now raises your maximum resource, and Eureka! makes your next 3 spells cheaper and 10% harder. Science, weaponised." },
    { n: "Orc", f: "Horde", i: "achievement_character_orc_male", tip: "Axe Specialization is now crit chance. Blood Fury and stun resistance carry on. The classics, sharpened." },
    { n: "Undead", f: "Horde", i: "achievement_character_undead_male", tip: "Will of the Forsaken clears fear, charm and sleep but no longer grants immunity. Cannibalize restores mana AND health; Touch of the Grave drains life. Still the PvP menace." },
    { n: "Tauren", f: "Horde", i: "achievement_character_tauren_male", tip: "War Stomp, +5% health, and Cultivation: bonus herbs with no Herbalism needed. The economy moos." },
    { n: "Troll", f: "Horde", i: "achievement_character_troll_male", tip: "Berserking and beast slaying, rework details still landing. The percentages are shy; the aggression is not." },
    { n: "Skyborne (High Order)", f: "Alliance", i: "inv_feather_02", nu: true, tip: "Alliance Skyborne. Walk on Air (10s glide), Wind Blessed (+1% haste), Elemental Insight (+5% vs elementals), Read Ley Line (double regen 15s). Requires the Skyborne Heroic Pack. Announced, not yet datamined." },
    { n: "Skyborne (Windshaper)", f: "Horde", i: "inv_feather_04", nu: true, tip: "Horde Skyborne. Walk on Air, Wind Blessed, Elemental Insight, and Skysight (+10% run speed). Requires the Skyborne Heroic Pack. Announced, not yet datamined." }
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
  // Combos Forever ADDED to the vanilla matrix; the cards wear a NEW tag.
  var NEWCOMBOS = { "Human:HUNTER": 1, "Dwarf:SHAMAN": 1, "Gnome:PRIEST": 1, "Orc:MAGE": 1,
    "Troll:WARLOCK": 1, "Undead:PALADIN": 1 };
  function isNewCombo(raceName, clsKey) {
    if (raceName.indexOf("Skyborne") === 0) return true;
    return !!NEWCOMBOS[raceName + ":" + clsKey];
  }

  // Talents: [name, maxRanks, tier(1-3), col(1-4), icon, tip].
  // Tiers gate at 0/5/10 points spent IN THAT TREE, exactly as in the game.
  var CLASSES = [
    { n: "Warrior", k: "WARRIOR", i: "classicon_warrior", tip: "Hits things. Is hit by things. Complains about neither.", specs: [
      { n: "Arms", role: "dps", i: "ability_warrior_savageblow", tip: "Big weapon, bigger opinions.", t: [
        ["Improved Heroic Strike", 3, 1, 1, "ability_rogue_ambush", "Cheaper Heroic Strike. Rage is money; this is a coupon."],
        ["Deflection", 5, 1, 2, "ability_parry", "+1% parry per rank. Politely returning what was sent."],
        ["Improved Rend", 3, 1, 3, "ability_gouge", "Rend bleeds harder. Rude in duels, ruder at level 19."],
        ["Tactical Mastery", 5, 2, 2, "spell_nature_enchantarmor", "Keep rage when you swap stances. The talent that makes warriors playable."],
        ["Sweeping Strikes", 1, 3, 2, "ability_rogue_slicedice", "Your swings hit an extra target. Maths, but violent."]] },
      { n: "Fury", role: "dps", i: "ability_warrior_innerrage", tip: "Two weapons, zero patience.", t: [
        ["Cruelty", 5, 1, 2, "ability_rogue_eviscerate", "+1% crit per rank. The whole personality, honestly."],
        ["Unbridled Wrath", 5, 1, 3, "spell_nature_stoneclawtotem", "Chance for bonus rage on hit. Anger, subsidised."],
        ["Piercing Howl", 1, 2, 1, "spell_shadow_deathscream", "AoE slow via shouting. Diplomacy."],
        ["Enrage", 5, 2, 3, "spell_shadow_unholyfrenzy", "More damage after being crit. Punish them for succeeding."],
        ["Blood Craze", 3, 3, 2, "spell_shadow_summonimp", "Regenerate health after being crit. Two wrongs make a right."]] },
      { n: "Protection", role: "tank", i: "ability_warrior_defensivestance", tip: "The reason everyone else gets to make mistakes.", t: [
        ["Shield Specialization", 5, 1, 2, "inv_shield_06", "+1% block per rank. The shield was not decorative."],
        ["Toughness", 5, 1, 3, "spell_holy_devotion", "+2% armour per rank. Become furniture."],
        ["Last Stand", 1, 2, 1, "spell_holy_ashestoashes", "+30% max health for 20s. The 'not yet' button."],
        ["Improved Shield Block", 3, 2, 2, "ability_defend", "Block more attacks per Shield Block. Crush-proofing, vanilla style."],
        ["Defiance", 5, 3, 2, "ability_warrior_defensivestance", "+3% threat per rank in Defensive Stance. Your job, but louder."]] }
    ]},
    { n: "Paladin", k: "PALADIN", i: "classicon_paladin", tip: "Insurance, but it wears plate and takes five minutes to buff.", specs: [
      { n: "Holy", role: "healer", i: "spell_holy_holybolt", tip: "The light giveth. Mostly to the warrior.", t: [
        ["Divine Strength", 5, 1, 2, "spell_holy_fistofjustice", "+2% Strength per rank. Yes, in the healing tree. Vanilla was like this."],
        ["Spiritual Focus", 5, 1, 3, "spell_holy_healingaura", "Heals resist pushback. Concentrate through the slapping."],
        ["Illumination", 5, 2, 2, "spell_holy_greaterheal", "Mana back on crit heals. The talent that pays the bills."],
        ["Consecration", 1, 2, 3, "spell_holy_innerfire", "Ground fire. The one button that makes prot-adjacent dreams real."],
        ["Divine Favor", 1, 3, 2, "spell_holy_heal", "Next heal crits. On purpose. Imagine."]] },
      { n: "Protection", role: "tank", i: "spell_holy_devotionaura", tip: "Tanking with extra steps and better auras.", t: [
        ["Redoubt", 5, 1, 1, "ability_defend", "Block chance after being crit. Reactive furniture."],
        ["Precision", 3, 1, 2, "ability_marksmanship", "+1% hit per rank. Threat starts with connecting."],
        ["Guardian's Favor", 2, 2, 1, "spell_holy_sealofprotection", "Better Blessing of Protection and Freedom. Bureaucracy, weaponised."],
        ["Blessing of Kings", 1, 2, 3, "spell_magic_magearmor", "+10% all stats to a friend. The most requested spell in the game."],
        ["Holy Shield", 1, 3, 2, "spell_holy_blessingofprotection", "Block charges that deal Holy damage. The pally-tank thesis statement."]] },
      { n: "Retribution", role: "dps", i: "spell_holy_auraoflight", tip: "Justice, delivered on a random number generator.", t: [
        ["Benediction", 5, 1, 1, "spell_frost_windwalkon", "Cheaper Seals and Judgements. Piety, discounted."],
        ["Improved Judgement", 2, 1, 2, "spell_holy_righteousfury", "Judge more often. The gavel never rests."],
        ["Deflection", 5, 2, 1, "ability_parry", "+1% parry per rank. Even justice ducks."],
        ["Seal of Command", 1, 2, 3, "ability_warrior_innerrage", "Chance for big extra Holy damage. The whole spec is this coin flip."],
        ["Conviction", 5, 3, 2, "spell_holy_retributionaura", "+1% melee crit per rank. When the coin lands right, it LANDS."]] }
    ]},
    { n: "Hunter", k: "HUNTER", i: "classicon_hunter", tip: "Comes with a pet and a reputation. Both bite.", specs: [
      { n: "Beast Mastery", role: "dps", i: "ability_hunter_beasttaming", tip: "The pet does the work. You take the credit.", t: [
        ["Improved Aspect of the Hawk", 5, 1, 2, "spell_nature_ravenform", "Chance for faster shooting. The bird approves."],
        ["Endurance Training", 5, 1, 3, "spell_nature_reincarnation", "+3% pet health per rank. Feed it points, not just meat."],
        ["Thick Hide", 3, 2, 1, "inv_misc_pelt_bear_03", "+10% pet armour per rank. Your tank now, apparently."],
        ["Unleashed Fury", 5, 2, 3, "ability_bullrush", "+4% pet damage per rank. Off the leash, on the meters."],
        ["Intimidation", 1, 3, 2, "ability_devour", "Pet stuns its target. HR has been notified."]] },
      { n: "Marksmanship", role: "dps", i: "ability_marksmanship", tip: "The arrow was the plan all along.", t: [
        ["Improved Concussive Shot", 5, 1, 2, "spell_frost_stun", "Chance to stun with Concussive. Kiting becomes bullying."],
        ["Lethal Shots", 5, 1, 3, "ability_searingarrow", "+1% ranged crit per rank. Simple pleasures."],
        ["Efficiency", 5, 2, 2, "spell_frost_wizardmark", "Cheaper shots and stings. Mana is ammo too."],
        ["Aimed Shot", 1, 2, 3, "inv_spear_07", "Wind up, delete someone. The scariest cast bar at level 30."],
        ["Mortal Shots", 5, 3, 2, "ability_piercedamage", "+6% ranged crit damage per rank. The part after the crit."]] },
      { n: "Survival", role: "dps", i: "ability_hunter_swiftstrike", tip: "Traps, knives and spite.", t: [
        ["Monster Slaying", 3, 1, 1, "inv_misc_head_dragon_black", "More damage and crit vs beasts, giants, dragonkin. Azeroth is mostly those."],
        ["Humanoid Slaying", 3, 1, 2, "spell_holy_prayerofhealing", "Same, but people. PvP says hello."],
        ["Deterrence", 1, 2, 2, "ability_whirlwind", "+25% dodge and parry for 10s. The 'you first' stance."],
        ["Survivalist", 5, 2, 3, "spell_shadow_twilight", "+2% health per rank. It is called Survival."],
        ["Trap Mastery", 2, 3, 2, "ability_ensnare", "Traps resist less. Freezing Trap becomes a promise."]] }
    ]},
    { n: "Rogue", k: "ROGUE", i: "classicon_rogue", tip: "You will not see the build coming either.", specs: [
      { n: "Assassination", role: "dps", i: "ability_rogue_eviscerate", tip: "Numbers so sharp they are technically knives.", t: [
        ["Malice", 5, 1, 2, "ability_racial_bloodrage", "+1% crit per rank. Premeditated."],
        ["Ruthlessness", 3, 1, 3, "ability_druid_disembowel", "Chance to keep a combo point after finishing. Efficiency with a record."],
        ["Relentless Strikes", 1, 2, 1, "ability_warrior_decisivestrike", "Finishers can refund energy. The engine of every rogue you fear."],
        ["Lethality", 5, 2, 3, "ability_criticalstrike", "+6% crit damage on combo moves per rank. The knife, but more so."],
        ["Cold Blood", 1, 3, 2, "spell_ice_lament", "Next ability crits. Guaranteed. Sign here."]] },
      { n: "Combat", role: "dps", i: "ability_backstab", tip: "Stealth optional. Violence mandatory.", t: [
        ["Improved Sinister Strike", 2, 1, 1, "spell_shadow_ritualofsacrifice", "Cheaper Sinister Strike. The button you press ten thousand times, discounted."],
        ["Precision", 5, 1, 3, "ability_marksmanship", "+1% hit per rank. Whiffing is for other specs."],
        ["Dual Wield Specialization", 5, 2, 1, "ability_dualwield", "+10% offhand damage per rank. The left hand learns."],
        ["Riposte", 1, 2, 3, "ability_warrior_challange", "After a parry, strike back and disarm. Rude both ways."],
        ["Blade Flurry", 1, 3, 2, "ability_warrior_punishingblow", "Attack speed up, hits cleave. Two people problems, one rogue solution."]] },
      { n: "Subtlety", role: "dps", i: "ability_stealth", tip: "The spec your battleground nightmares are made of.", t: [
        ["Master of Deception", 5, 1, 2, "spell_shadow_charm", "Harder to spot in stealth. You were never here."],
        ["Opportunity", 5, 1, 3, "ability_warrior_warcry", "More damage from behind. Positional ethics."],
        ["Camouflage", 5, 2, 1, "ability_stealth", "Faster in stealth, quicker restealth. Commute upgrade."],
        ["Ghostly Strike", 1, 2, 3, "spell_shadow_curse", "A strike that raises your dodge. Hit them and haunt them."],
        ["Setup", 3, 3, 2, "spell_nature_mirrorimage", "Combo point when you dodge. They attack, you profit."]] }
    ]},
    { n: "Priest", k: "PRIEST", i: "classicon_priest", tip: "Everyone's best friend until the shadow form drops.", specs: [
      { n: "Discipline", role: "healer", i: "spell_holy_wordfortitude", tip: "Prevention is cheaper than cure, and smugger.", t: [
        ["Unbreakable Will", 5, 1, 2, "spell_magic_magearmor", "Resist stuns, fears, silences. The mind says no."],
        ["Improved Power Word: Shield", 3, 1, 3, "spell_holy_powerwordshield", "Stronger bubbles. The signature move, thickened."],
        ["Inner Focus", 1, 2, 2, "spell_frost_windwalkon", "Next spell free and crit-happier. A tiny miracle on a cooldown."],
        ["Meditation", 3, 2, 3, "spell_nature_sleep", "Mana regen keeps ticking while casting. The tree's actual crown jewel."],
        ["Mental Agility", 5, 3, 2, "ability_hibernation", "Cheaper instants. Snappy piety."]] },
      { n: "Holy", role: "healer", i: "spell_holy_renew", tip: "The reason the tank's health bar is a suggestion.", t: [
        ["Healing Focus", 2, 1, 1, "spell_holy_healingfocus", "Heals resist pushback. Serenity under fire."],
        ["Improved Renew", 3, 1, 2, "spell_holy_renew", "Stronger HoT. Set it, forget it, save a life."],
        ["Spell Warding", 5, 2, 1, "spell_holy_sealofsalvation", "-2% spell damage taken per rank. Personal weather."],
        ["Divine Fury", 5, 2, 3, "spell_holy_sealofwrath", "Faster Smite and Heals. Impatience, sanctified."],
        ["Holy Nova", 1, 3, 2, "spell_holy_holynova", "Heal friends, hurt enemies, no threat. Sneaky halo."]] },
      { n: "Shadow", role: "dps", i: "spell_shadow_shadowwordpain", tip: "The word of the day is 'pain', and the word repeats.", t: [
        ["Spirit Tap", 5, 1, 2, "spell_shadow_requiem", "Huge Spirit after a killing blow. Levelling on tap. Literally."],
        ["Blackout", 5, 1, 3, "spell_shadow_gathershadows", "Shadow spells can stun. The dark says sit."],
        ["Improved Shadow Word: Pain", 2, 2, 1, "spell_shadow_shadowwordpain", "Longer Pain. The brand promise."],
        ["Mind Flay", 1, 2, 3, "spell_shadow_siphonmana", "Channelled misery that slows. The soundtrack of vanilla levelling."],
        ["Shadow Focus", 5, 3, 2, "spell_shadow_burningspirit", "-2% shadow resist chance per rank. Doubt, removed."]] }
    ]},
    { n: "Shaman", k: "SHAMAN", i: "classicon_shaman", tip: "Horde's excuse. Drops totems, jaws.", specs: [
      { n: "Elemental", role: "dps", i: "spell_nature_lightning", tip: "Weather forecast: you.", t: [
        ["Convection", 5, 1, 2, "spell_nature_wispsplode", "Cheaper Lightning and Shock. Storms on a budget."],
        ["Concussion", 5, 1, 3, "spell_fire_fireball", "+1% Lightning and Shock damage per rank. Louder weather."],
        ["Call of Thunder", 5, 2, 2, "spell_nature_callstorm", "+1% crit to Lightning per rank. The sky takes sides."],
        ["Elemental Focus", 1, 2, 3, "spell_shadow_manaburn", "Crits make the next spell cheaper. The storm feeds itself."],
        ["Call of Flame", 3, 3, 2, "spell_fire_immolation", "+5% fire totem damage per rank. Searing Totem, employee of the month."]] },
      { n: "Enhancement", role: "dps", i: "spell_nature_lightningshield", tip: "Caster stats, melee dreams, windfury prayers.", t: [
        ["Ancestral Knowledge", 5, 1, 2, "spell_shadow_grimward", "+1% mana per rank. The ancestors kept receipts."],
        ["Shield Specialization", 5, 1, 3, "inv_shield_06", "Block more, gain mana blocking. Vanilla enhance tanked. Sort of."],
        ["Thundering Strikes", 5, 2, 2, "ability_thunderbolt", "+1% melee crit per rank. The windfury lottery, better odds."],
        ["Improved Ghost Wolf", 2, 2, 3, "spell_nature_spiritwolf", "Faster wolf form cast. The commute matters at 30."],
        ["Flurry", 5, 3, 2, "ability_ghoulfrenzy", "Attack speed after a crit. When the lottery pays, it pays fast."]] },
      { n: "Restoration", role: "healer", i: "spell_nature_healingwavegreater", tip: "Chain Heal is at 40. Until then: hope, expressed as waves.", t: [
        ["Improved Healing Wave", 5, 1, 2, "spell_nature_magicimmunity", "Faster big heal. The wave arrives on time."],
        ["Tidal Focus", 5, 1, 3, "spell_frost_manarecharge", "Cheaper heals. The tide is a budget too."],
        ["Ancestral Healing", 3, 2, 1, "spell_nature_undyingstrength", "Crit heals armour the target. Heal them AND dress them."],
        ["Healing Focus", 5, 2, 2, "spell_holy_healingfocus", "Pushback resistance. Waves do not flinch."],
        ["Nature's Swiftness", 1, 3, 2, "spell_nature_ravenform", "Next nature spell instant. The best panic button in the game."]] }
    ]},
    { n: "Mage", k: "MAGE", i: "classicon_mage", tip: "Food, water, portals, and opinions. All conjured.", specs: [
      { n: "Arcane", role: "dps", i: "spell_holy_magicalsentry", tip: "Pure magic, purer mana problems.", t: [
        ["Arcane Subtlety", 2, 1, 1, "spell_holy_dispelmagic", "Less threat. The tank thanks you by not noticing."],
        ["Arcane Focus", 5, 1, 2, "spell_holy_devotion", "-2% arcane resist chance per rank. Insistence."],
        ["Improved Arcane Missiles", 5, 2, 2, "spell_nature_starfall", "Channel through the slapping. All five missiles, delivered."],
        ["Evocation", 1, 2, 3, "spell_nature_purge", "Mana bar refills. Briefly mortal, then very much not."],
        ["Arcane Concentration", 5, 3, 2, "spell_shadow_manaburn", "Chance for a free spell. Clearcasting: the drug."]] },
      { n: "Fire", role: "dps", i: "spell_fire_firebolt02", tip: "The meter is also on fire.", t: [
        ["Improved Fireball", 5, 1, 2, "spell_fire_flamebolt", "Faster Fireball. The classic, quickened."],
        ["Impact", 5, 1, 3, "spell_fire_meteorstorm", "Fire spells can stun. Surprise physics."],
        ["Ignite", 5, 2, 2, "spell_fire_incinerate", "Crits burn for 8% more per rank. The crit that keeps crittin'."],
        ["Pyroblast", 1, 2, 3, "spell_fire_fireball02", "The big one. Cast time of a novel, payoff of a headline."],
        ["Critical Mass", 3, 3, 2, "spell_nature_wispheal", "+2% fire crit per rank. More ignites for the ignite god."]] },
      { n: "Frost", role: "dps", i: "spell_frost_frostbolt02", tip: "Control, survival, and the smuggest kiting on Azeroth.", t: [
        ["Frost Warding", 2, 1, 1, "spell_frost_frostward", "Better frost armour and ward. Wear the weather."],
        ["Improved Frostbolt", 5, 1, 2, "spell_frost_frostbolt", "Faster Frostbolt. The metronome of the spec."],
        ["Cold Snap", 1, 2, 1, "spell_frost_wizardmark", "Reset frost cooldowns. Two of everything, once."],
        ["Ice Shards", 5, 2, 2, "spell_frost_iceshard", "+20% frost crit damage per rank. Cold, then colder."],
        ["Shatter", 5, 3, 2, "spell_frost_frostshock", "+10% crit vs frozen per rank. The combo the spec bends toward."]] }
    ]},
    { n: "Warlock", k: "WARLOCK", i: "classicon_warlock", tip: "Has a guy for everything. The guy is a demon.", specs: [
      { n: "Affliction", role: "dps", i: "spell_shadow_deathcoil", tip: "Damage over time, guilt over never.", t: [
        ["Suppression", 5, 1, 1, "spell_shadow_unsummonbuilding", "-2% affliction resist chance per rank. The curses stick."],
        ["Improved Corruption", 5, 1, 2, "spell_shadow_abominationexplosion", "Corruption casts faster, then instant. The one-button plague."],
        ["Improved Life Tap", 2, 2, 1, "spell_shadow_burningspirit", "More mana per tap. Your health was always the mana bar."],
        ["Amplify Curse", 1, 2, 2, "spell_shadow_contagion", "Supercharge the next curse. Louder doom."],
        ["Nightfall", 2, 3, 2, "spell_shadow_twilight", "DoT ticks can make Shadow Bolt instant. The lottery, but evil."]] },
      { n: "Demonology", role: "dps", i: "spell_shadow_metamorphosis", tip: "Middle management for the damned.", t: [
        ["Improved Healthstone", 2, 1, 1, "inv_stone_04", "Bigger candy. The raid's favourite talent you took."],
        ["Demonic Embrace", 5, 1, 2, "spell_shadow_metamorphosis", "+3% Stamina, -1% Spirit per rank. Hugged by the void, insured by it."],
        ["Improved Voidwalker", 3, 2, 1, "spell_shadow_summonvoidwalker", "Better blueberry. He was trying his best already."],
        ["Fel Domination", 1, 2, 2, "spell_nature_removecurse", "Next demon summons fast and cheap. HR turnaround, hellish edition."],
        ["Fel Intellect", 5, 3, 2, "spell_holy_magicalsentry", "More pet mana. The imp reads at a college level now."]] },
      { n: "Destruction", role: "dps", i: "spell_shadow_rainoffire", tip: "Affliction with the patience surgically removed.", t: [
        ["Improved Shadow Bolt", 5, 1, 1, "spell_shadow_shadowbolt", "Crits amplify the next shadow damage. Doom compounds."],
        ["Bane", 5, 1, 2, "spell_shadow_deathpact", "Faster Shadow Bolt and Immolate. The cast bar diet."],
        ["Aftermath", 5, 2, 1, "spell_fire_fire", "Destruction spells can daze. Running is also cancelled."],
        ["Shadowburn", 1, 2, 3, "spell_shadow_scourgebuild", "Instant shadow damage for a shard. The finisher with a receipt."],
        ["Devastation", 5, 3, 2, "spell_fire_flameshock", "+1% destruction crit per rank. The point of the exercise."]] }
    ]},
    { n: "Druid", k: "DRUID", i: "classicon_druid", tip: "Every class in one, scheduling conflicts included.", specs: [
      { n: "Balance", role: "dps", i: "spell_nature_starfall", tip: "Boomkin is at 40. Until then: angry poetry.", t: [
        ["Improved Wrath", 5, 1, 2, "spell_nature_abolishmagic", "Faster Wrath. The pew, accelerated."],
        ["Nature's Grasp", 1, 1, 3, "spell_nature_naturesblessing", "Attackers get rooted. Trees fight back."],
        ["Improved Moonfire", 5, 2, 2, "spell_nature_starsurge", "More Moonfire damage and crit. Yes, the button you spam. Own it."],
        ["Natural Weapons", 5, 2, 3, "ability_druid_ravage", "+2% physical damage per rank in forms. Feeds the cat you also are."],
        ["Omen of Clarity", 1, 3, 2, "spell_nature_crystalball", "Procs free abilities. The whole druid economy."]] },
      { n: "Feral", role: "tank", i: "ability_racial_bearform", tip: "Cat when winning, bear when sorry.", t: [
        ["Ferocity", 5, 1, 2, "ability_hunter_pet_hyena", "Cheaper Maul, Swipe, Claw, Rake. Rage and energy respect you now."],
        ["Feral Aggression", 5, 1, 3, "ability_druid_demoralizingroar", "Stronger Ferocious Bite, meaner Demoralizing Roar. Both moods."],
        ["Feline Swiftness", 2, 2, 1, "spell_nature_spiritwolf", "+15% outdoor cat speed per rank. The commute IS the content."],
        ["Thick Hide", 5, 2, 2, "inv_misc_pelt_bear_03", "+2% armour per rank. Bear math."],
        ["Feral Charge", 1, 3, 2, "ability_hunter_pet_bear", "Bear leap that interrupts. The talent that makes mages hate druids."]] },
      { n: "Restoration", role: "healer", i: "spell_nature_healingtouch", tip: "HoTs, tears, and one very fast heal per three minutes.", t: [
        ["Improved Mark of the Wild", 5, 1, 2, "spell_nature_regeneration", "Better buff. Applause at every dungeon door."],
        ["Furor", 5, 1, 3, "spell_holy_blessingofstamina", "Rage and energy on shapeshift. The multi-tool stays sharp."],
        ["Reflection", 3, 2, 1, "spell_frost_windwalkon", "Mana regen while casting. Quiet engine."],
        ["Improved Healing Touch", 5, 2, 2, "spell_nature_healingtouch", "Faster big heal. The novel becomes a short story."],
        ["Nature's Swiftness", 1, 3, 2, "spell_nature_ravenform", "Next nature spell instant. Druid panic, resolved."]] }
    ]},
  ];

  var GEAR = [
    { slot: "Weapon", opts: [
      ["Cruel Barb", "rare", "22.9 DPS dagger, +12 Attack Power", "Deadmines: VanCleef's parting gift."],
      ["Shadowfang", "rare", "19.3 DPS sword, shadow damage proc", "Shadowfang Keep. The name does the marketing."],
      ["Twisted Chanter's Staff", "rare", "Staff, +10 Int, +5 Sta, +5 Spi", "Wailing Caverns. Caster levelling royalty."],
      ["Corpsemaker", "rare", "2H axe, 25.9 DPS, +10 Str", "Razorfen Kraul. Subtlety was never the plan."],
      ["Smite's Mighty Hammer", "rare", "2H mace, 24.3 DPS, +11 Str", "Deadmines. Borrowed permanently from Mr. Smite."]]},
    { slot: "Off-hand", opts: [
      ["Commander's Crest", "rare", "Shield, 664 armour, +7 Sta, +3 Spi", "Deadmines. A door you can hold."],
      ["Arctic Buckler", "rare", "Shield, +7 Sta, +4 Spi, frost flavoured", "Gnomeregan. Cold storage."],
      ["Tome of Knowledge", "uncommon", "Held book, +6 Int", "World drop. Reading buffs are real."],
      ["Nothing yet", "grey", "Empty hand, full heart", "The off-hand of the honest leveller."]]},
    { slot: "Chest", opts: [
      ["Blackened Defias Armor", "rare", "Leather, +11 Sta, +4 Spi", "Deadmines. Crime pays armour."],
      ["Tunic of Westfall", "rare", "Leather, +10 Agi, +9 Sta", "Deadmines quest. The people's tunic."],
      ["Robes of Arugal", "rare", "Cloth, +9 Int, +10 Sta, +3 Spi", "Shadowfang Keep. Wizard chic."],
      ["Green Iron Hauberk", "rare", "Mail, crafted classic", "Blacksmithing. Friendship with a forge."]]},
    { slot: "Legs", opts: [
      ["Leggings of the Fang", "rare", "Leather, +5 Agi, +9 Str", "Wailing Caverns. Ask any feral druid ever."],
      ["Smelting Pants", "rare", "Cloth, +9 Int, +6 Spi", "Gnomeregan. Business casual, fireproof."],
      ["Silver-thread Pants", "uncommon", "Cloth, +7 Int, +4 Spi", "World drop. Reliable trousers."],
      ["Barbaric Cloth Leggings", "uncommon", "Cloth, +8 Int crafted", "Tailoring. Barbaric is a strong word."]]},
    { slot: "Ring", opts: [
      ["Ring of Precision", "rare", "+7 Agi and hit vibes", "Deadmines. On-theme for not missing."],
      ["Silverlaine's Family Seal", "rare", "+7 Str, +7 Sta", "Shadowfang Keep. Heirloom, involuntarily."],
      ["Seal of Wrynn", "rare", "+5 Sta, +5 Spi, +5 Int", "Stockade quest. The king owed you one."],
      ["Plain gold band", "grey", "+0 everything, +100 commitment", "Vendor. For the RP realm."]]},
    { slot: "Trinket", opts: [
      ["Nifty Stopwatch", "rare", "On use: +40% run speed 10s", "Westfall quest. The commute trinket."],
      ["Minor Recombobulator", "uncommon", "On use: heal and de-gnome yourself", "Gnomeregan. Engineering's apology."],
      ["Rabbit's Foot", "grey", "+0 stats, +1 hope", "The RNG respects tribute."],
      ["Nothing yet", "grey", "Trinkets are earned, not given", "Both slots honest at 30."]]},
  ];

  // ---- state ----------------------------------------------------------------
  var S = { race: -1, cls: -1, spec: -1, t: [[], [], []], gear: [], name: "" };
  var STEPS = ["Race", "Class", "Spec", "Talents", "Gear", "Name it"];
  var GUIDE = {
    0: "First: the body you will regret in dungeons and defend in guild chat. <b>Pick a race.</b> Hover anything for the truth.",
    1: "Now the job. This is the REAL Forever matrix from the reveal: Undead Paladins live, Human Hunters exist, Dwarves found totems. <b>Pick a class.</b> Gold NEW tags mark combos vanilla never allowed.",
    2: "The spec names your role; the points can still go anywhere, like the game intended. <b>Pick one of three.</b>",
    3: "Three trees, <b>21 points</b>, spend them anywhere. Rows open at 5 and 10 points in a tree. Left click adds, right click removes. Numbers are the vanilla skeleton until the Forever calculators firm up.",
    4: "Gear: the vanilla classics your bracket actually fights over. Datamined Forever loot lands here the day it exists. <b>Pick per slot,</b> or stay honest and naked.",
    5: "Name it, admire it, <b>share the link.</b> The link IS the save."
  };

  function $(id) { return document.getElementById(id); }
  function esc(s) { return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
  function cc(k) { return CLASS_COLOUR[k] || "#fff"; }
  function qv(band) { return "var(--q-" + ({ grey: "common", uncommon: "uncommon", rare: "rare", epic: "epic" }[band] || "common") + ")"; }
  function icon(name, cls) { return '<img class="' + (cls || "wi") + '" src="' + ICON_CDN + name + '.jpg" alt="" loading="lazy" onerror="this.style.visibility=\'hidden\'">'; }
  function treePts(ti) { return (S.t[ti] || []).reduce(function (a, b) { return a + (b || 0); }, 0); }
  function spent() { return treePts(0) + treePts(1) + treePts(2); }
  function dt(title, body) { return 'data-tip="<b>' + esc(title) + "</b>" + esc(body) + '"'; }

  // ---- url as the save ------------------------------------------------------
  function code() {
    return [S.race, S.cls, S.spec,
      S.t.map(function (a) { return a.join(""); }).join("-"),
      S.gear.map(function (g) { return g == null ? "x" : g; }).join(""),
      encodeURIComponent(S.name || "")].join(".");
  }
  function parseCode(str) {
    var p = String(str || "").split(".");
    var o = { race: +p[0], cls: +p[1], spec: +p[2], t: [[], [], []], gear: [], name: decodeURIComponent(p[5] || "") };
    if (!(o.race >= 0 && o.race < RACES.length && o.cls >= 0 && o.cls < CLASSES.length)) return null;
    if (!(o.spec >= 0 && o.spec < 3)) o.spec = 0;
    var segs = String(p[3] || "").split("-");
    for (var ti = 0; ti < 3; ti++) {
      var tal = CLASSES[o.cls].specs[ti].t, seg = segs.length === 3 ? segs[ti] : (ti === o.spec ? segs[0] : "");
      for (var i = 0; i < tal.length; i++) o.t[ti][i] = Math.min(tal[i][1], +((seg || "")[i]) || 0);
    }
    for (var g = 0; g < GEAR.length; g++) {
      var ch = (p[4] || "")[g];
      o.gear[g] = (ch === "x" || ch == null) ? null : Math.min(GEAR[g].opts.length - 1, +ch || 0);
    }
    return o;
  }
  function syncURL() {
    var done = S.race >= 0 && S.cls >= 0 && S.spec >= 0;
    history.replaceState(null, "", done ? "?b=" + code() : location.pathname);
    try { localStorage.setItem("forge-build", done ? code() : ""); } catch (e) {}
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

  // ---- steps ----------------------------------------------------------------
  function stepNow() {
    if (S.race < 0) return 0;
    if (S.cls < 0) return 1;
    if (S.spec < 0) return 2;
    return 3;
  }
  function drawSteps() {
    var now = stepNow();
    $("fsteps").innerHTML = STEPS.map(function (n, i) {
      var cls = i < now ? "done" : i === now ? "now" : (i > 2 && now >= 3 ? "done" : "locked");
      return '<li class="' + cls + '" data-step="' + i + '">' + (i + 1) + ". " + n + "</li>";
    }).join("");
    $("guide").innerHTML = "<p>" + GUIDE[Math.min(now, 5)] + "</p>";
  }

  function render() {
    drawSteps(); syncURL();
    var st = $("stage"), now = stepNow(), html = "";
    if (now === 0) {
      html = '<div class="cards">' + RACES.map(function (r, i) {
        return '<button class="card' + (S.race === i ? " sel" : "") + '" data-race="' + i + '" ' + dt(r.n, r.tip) + ">" +
          icon(r.i, "wi wi-lg") + "<b>" + r.n + "</b><i>" + r.f + (r.nu ? " (probably)" : "") + "</i></button>";
      }).join("") + "</div>";
    } else if (now === 1) {
      var rn = RACES[S.race].n;
      html = '<div class="cards">' + CLASSES.map(function (c, i) {
        var ok = COMBOS[c.k].indexOf(rn) !== -1;
        return '<button class="card' + (ok ? "" : " dis") + (S.cls === i ? " sel" : "") + '"' + (ok ? ' data-cls="' + i + '"' : "") + " " +
          dt(c.n, ok ? c.tip + (isNewCombo(rn, c.k) ? " NEW in Forever: this combo did not exist in vanilla." : "") : "A " + rn + " cannot be a " + c.n + ". Even Forever did not go that far.") + ">" +
          icon(c.i, "wi wi-lg") + '<b class="cc" style="--cc:' + cc(c.k) + '">' + c.n + "</b><i>" + (ok ? (isNewCombo(rn, c.k) ? '<span class="newtag">NEW</span>' : "") : "not for " + rn) + "</i></button>";
      }).join("") + "</div>";
    } else if (now === 2) {
      html = '<div class="cards">' + CLASSES[S.cls].specs.map(function (sp, i) {
        return '<button class="card' + (S.spec === i ? " sel" : "") + '" data-spec="' + i + '" ' + dt(CLASSES[S.cls].n + ": " + sp.n, sp.tip) + ">" +
          icon(sp.i, "wi wi-lg") + "<b>" + sp.n + '</b><i class="role">' + sp.role + "</i></button>";
      }).join("") + "</div>";
    } else {
      html = talentsHTML() + gearHTML() + nameHTML() + buildHTML();
    }
    st.innerHTML = html;
    wire(st); bindTips(st);
  }

  // ---- talents: the classic three-tree calculator ---------------------------
  function talentsHTML() {
    var html = '<div class="talenthead"><h3>Talents</h3><span class="pts">' + (POINTS - spent()) +
      ' points left</span><i class="finenote">vanilla numbers, corrected on datamining</i></div><div class="wtrees">';
    CLASSES[S.cls].specs.forEach(function (sp, ti) {
      var pts = treePts(ti);
      html += '<div class="wtree' + (ti === S.spec ? " main" : "") + '"><div class="wt-head">' +
        icon(sp.i, "wi wi-sm") + "<b>" + esc(sp.n) + '</b><u>' + pts + "</u></div><div class=\"wt-grid\">";
      sp.t.forEach(function (t, i) {
        var r = S.t[ti][i] || 0, gate = (t[2] - 1) * 5, open = pts >= gate;
        html += '<div class="slot' + (r >= t[1] ? " maxed" : r > 0 ? " part" : "") + (open ? "" : " locked") +
          '" style="grid-column:' + t[3] + ";grid-row:" + t[2] + '" data-tal="' + ti + ":" + i + '" ' +
          dt(t[0] + " (" + r + "/" + t[1] + ")", t[5] + (open ? " Left click adds; right click removes." : " Needs " + gate + " points in " + sp.n + ".")) + ">" +
          icon(t[4], "wi") + '<span class="s-rank">' + r + "/" + t[1] + "</span></div>";
      });
      html += "</div></div>";
    });
    return html + "</div>";
  }

  function gearHTML() {
    var html = '<div class="talenthead"><h3>Gear</h3><i class="finenote">the classics of levels 1–30; datamined Forever loot replaces this table</i></div>';
    GEAR.forEach(function (g, gi) {
      html += '<div class="gearrow"><label>' + esc(g.slot) + '</label><div class="gearopts">' +
        g.opts.map(function (o, oi) {
          return '<button class="gitem' + (S.gear[gi] === oi ? " sel" : "") + '" style="--q:' + qv(o[1]) + '" data-gear="' + gi + ":" + oi + '" ' +
            dt(o[0], o[2] + " — " + o[3]) + ">" + esc(o[0]) + "</button>";
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
    var out = [];
    CLASSES[S.cls].specs.forEach(function (sp, ti) {
      sp.t.forEach(function (t, i) { if ((S.t[ti][i] || 0) > 0) out.push(t[0] + " " + S.t[ti][i] + "/" + t[1]); });
    });
    return out;
  }
  function buildHTML() {
    var r = RACES[S.race], c = CLASSES[S.cls], sp = c.specs[S.spec];
    var tal = talentList();
    var gear = GEAR.map(function (g, i) { return S.gear[i] != null ? g.opts[S.gear[i]][0] : null; }).filter(Boolean);
    return '<div class="buildcard"><h3>' + esc(S.name || "Unnamed " + c.n) + "</h3>" +
      '<p class="line">' + icon(r.i, "wi wi-sm") + " " + esc(r.n) + ' · <span style="color:' + cc(c.k) + '">' + esc(c.n) + "</span> · " + esc(sp.n) +
      ' · <span class="rolechip ' + sp.role + '">' + sp.role + "</span> · level " + CAP + " (beta cap)</p>" +
      '<p class="line"><i>Talents (' + spent() + "/" + POINTS + "):</i> " + (tal.length ? esc(tal.join(", ")) : "none yet, a purist") + "</p>" +
      '<p class="line"><i>Gear:</i> ' + (gear.length ? esc(gear.join(", ")) : "honest and naked") + "</p></div>";
  }
  function buildText() {
    var r = RACES[S.race], c = CLASSES[S.cls], sp = c.specs[S.spec];
    var gear = GEAR.map(function (g, i) { return S.gear[i] != null ? "  " + g.slot + ": " + g.opts[S.gear[i]][0] : null; }).filter(Boolean);
    return (S.name || "Unnamed") + " — " + r.n + " " + sp.n + " " + c.n + " (" + sp.role + ", beta cap " + CAP + ")\n" +
      "Talents (" + spent() + "/" + POINTS + "):\n" + (talentList().map(function (t) { return "  " + t; }).join("\n") || "  none") +
      "\nGear:\n" + (gear.join("\n") || "  none") + "\n" + location.origin + location.pathname + "?b=" + code();
  }

  // ---- wiring ---------------------------------------------------------------
  function wire(st) {
    st.querySelectorAll("[data-race]").forEach(function (el) {
      el.addEventListener("click", function () { S.race = +el.getAttribute("data-race"); S.cls = -1; S.spec = -1; S.t = [[], [], []]; render(); });
    });
    st.querySelectorAll("[data-cls]").forEach(function (el) {
      el.addEventListener("click", function () { S.cls = +el.getAttribute("data-cls"); S.spec = -1; S.t = [[], [], []]; render(); });
    });
    st.querySelectorAll("[data-spec]").forEach(function (el) {
      el.addEventListener("click", function () { S.spec = +el.getAttribute("data-spec"); render(); });
    });
    st.querySelectorAll(".slot[data-tal]").forEach(function (el) {
      var p = el.getAttribute("data-tal").split(":"), ti = +p[0], i = +p[1];
      var t = CLASSES[S.cls].specs[ti].t[i];
      el.addEventListener("click", function () {
        if (treePts(ti) < (t[2] - 1) * 5 || spent() >= POINTS) return;
        S.t[ti][i] = Math.min(t[1], (S.t[ti][i] || 0) + 1); render();
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
    if (br) br.addEventListener("click", function () { S = { race: -1, cls: -1, spec: -1, t: [[], [], []], gear: [], name: "" }; render(); window.scrollTo(0, 0); });
    document.querySelectorAll("#fsteps li.done, #fsteps li.now").forEach(function (li) {
      li.addEventListener("click", function () {
        var i = +li.getAttribute("data-step");
        if (i === 0) { S.race = -1; S.cls = -1; S.spec = -1; S.t = [[], [], []]; }
        else if (i === 1 && S.race >= 0) { S.cls = -1; S.spec = -1; S.t = [[], [], []]; }
        else if (i === 2 && S.cls >= 0) { S.spec = -1; }
        render();
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
  function bcode(b) {
    return [b.race, b.cls, b.spec, b.t.map(function (a) { return a.join(""); }).join("-"),
      b.gear.map(function (g) { return g == null ? "x" : g; }).join(""), encodeURIComponent(b.name || "")].join(".");
  }
  function compose() {
    var lines = $("raid-in").value.split("\n").map(function (l) { return l.trim(); }).filter(Boolean);
    var builds = [];
    lines.forEach(function (l) { builds = builds.concat(parseAny(l)); });
    var out = $("raid-out");
    if (!builds.length) {
      out.innerHTML = '<div class="verdict">Nothing parseable in there. Paste build links from The Forge, one per line.</div>';
      $("raid-link").hidden = true; return;
    }
    var roles = { tank: 0, healer: 0, dps: 0 }, classes = {};
    var rows = builds.map(function (b) {
      var c = CLASSES[b.cls], sp = c.specs[b.spec] || c.specs[0];
      roles[sp.role]++; classes[c.n] = (classes[c.n] || 0) + 1;
      var pts = b.t.reduce(function (a, arr) { return a + arr.reduce(function (x, y) { return x + (y || 0); }, 0); }, 0);
      return "<tr><td>" + icon(c.i, "wi wi-sm") + ' <b style="color:' + cc(c.k) + '">' + esc(b.name || "Unnamed") + "</b></td>" +
        "<td>" + icon(RACES[b.race].i, "wi wi-sm") + " " + esc(RACES[b.race].n) + "</td><td>" + esc(sp.n) + " " + esc(c.n) + "</td>" +
        '<td><span class="rolechip ' + sp.role + '">' + sp.role + "</span></td><td>" + pts + "/" + POINTS + " pts</td></tr>";
    }).join("");
    var v = [];
    v.push("<b>" + builds.length + "</b> forged: " + roles.tank + " tank" + (roles.tank === 1 ? "" : "s") + ", " +
      roles.healer + " healer" + (roles.healer === 1 ? "" : "s") + ", " + roles.dps + " dps.");
    if (!roles.tank) v.push("Zero tanks: the dungeon will be tanked by whoever pulls first. Tradition.");
    if (!roles.healer) v.push("Zero healers: bold. The spirit healer thanks you for the business.");
    if (roles.tank && roles.healer && builds.length >= 5) v.push("This is, technically, a functioning group. Do not let it go to your heads.");
    if (!(classes["Mage"] > 0)) v.push("No mage: bring your own water like peasants.");
    if (classes["Warlock"] >= 2) v.push("Two-plus warlocks: summons for everyone, souls for no one.");
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
    var p = new URLSearchParams(location.search);
    if (p.get("raid")) {
      $("raid-in").value = location.href;
      compose();
      $("composer").scrollIntoView();
    } else {
      var fromURL = p.get("b") && parseCode(p.get("b"));
      var saved = null;
      if (!fromURL) { try { saved = parseCode(localStorage.getItem("forge-build")); } catch (e) {} }
      if (fromURL || saved) S = fromURL || saved;
    }
    $("compose").addEventListener("click", compose);
    render();
  });
})();
