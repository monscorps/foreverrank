# QuestBank observer and the 2026-10 roadmap

Agreed with the owner on 2026-10-12 ("yep lets do it, go").

## The principle

Every feature on the list is the same loop: observe in game, upload, aggregate across runs, show in the
addon and on the site. QuestBank already does this for quests, NPCs, trainers, loot windows and item tooltips.
This roadmap extends the observer to everything else an addon can see, then the views are cheap because they
read one shared data shape. "Scale without iterations": the owner plays, the data tightens, nobody edits a boss
or a gear list by hand.

One addon, modules as toggles. WoW loads every addon's files at login regardless, so a suite saves nothing at
start; what costs is per-frame work, and each view only runs while shown. One install, one upload, one version.

## Roadmap (each step gets its own plan)

1. **Event probe** (this spec, part A): a hidden diagnostic in the next QuestBank release that records which
   unit events deliver readable (non-secret) data on the Forever client. The owner plays one dungeon as usual.
2. **Observer + aggregation** (this spec, part B): creature casts, debuffs, deaths, encounter timing, owner
   notes, vendors, chests, rares; the site tool that merges uploads into per-creature and per-item data and
   writes it back into the addon's data file.
3. **Enchants datamine** and the **site design system**, in parallel (own specs).
4. **Timeline, timers, links, modifier and context profiles** in the addon (own spec).
5. **Camping and awareness**, and the loot and gear page redesign on the provenance data (own spec).

## Part A: event probe (QuestBank 3.7.0, hidden diagnostic)

Goal: learn, from one ordinary run, which of these deliver usable values on build 1.60.1.7xxxx:

- UNIT_SPELLCAST_START / _SUCCEEDED / _CHANNEL_START / _INTERRUPTED / _FAILED for units target, focus,
  boss1..5, nameplate1..40, party1..4 targets.
- UNIT_AURA on player and party1..4 with C_UnitAuras / UnitAura reads (name, spellId, source unit).
- UNIT_DIED is CLEU-only (restricted); deaths come from UNIT_HEALTH reaching 0 on a watched unit and from
  ENCOUNTER_END / BOSS_KILL (already handled by Loot.lua).
- NAME_PLATE_UNIT_ADDED / _REMOVED, UnitGUID, UnitClassification, UnitLevel, UnitName on nameplate units.
- MERCHANT_SHOW: GetMerchantNumItems, GetMerchantItemInfo / GetMerchantItemLink, GetMerchantItemID; the
  merchant NPC via UnitGUID("npc").
- LOOT_OPENED with GetLootSourceInfo for GameObject GUIDs (chests, nodes).
- PLAYER_TARGET_CHANGED with UnitGUID("target"), and VIGNETTE_MINIMAP_UPDATED / C_VignetteInfo for rares.
- Encounter time: ENCOUNTER_START time base, PLAYER_REGEN_DISABLED/ENABLED, GetTime().

Recording: QuestBankDB.diag.ev = { [eventName] = { n = count, ok = count of calls where every read value
passed issecretvalue == false, secret = count where at least one was secret, nil = count of nil reads,
sample = one redacted sample: field names and value types only, never names of players } }. Capped at 60
event keys and one sample each; cleared on upload like other diag tables. Every event handler is wrapped in
QB.Safe; every RegisterEvent is pcall'd; nothing is registered when the client lacks the API.

Privacy: no player, character, guild or realm names are stored; creature names are fine (they are game data).
Uploads stay opt-in as today.

Done when: the harness has a test that drives each event with a mix of plain and secret values and checks
the counts; the owner's next upload shows diag.ev; a short table of "works / secret / absent" per event is
written to tools/questbank/OBSERVER-EVENTS.md and decides Part B's design.

## Part B: observer and aggregation

Design is fixed only where it does not depend on Part A's answer.

### In the addon (Observe.lua)

- **Creature record**, keyed by creature id (from the GUID), per zone and instance:
  - casts: { spellId, name, tCombat (seconds since this unit's combat start, or since ENCOUNTER_START),
    kind = start|success|channel|interrupted }, kept as a list per fight, fights capped (last 20 per creature).
  - auras seen on the player/party from this creature: spellId, name, debuff type, tCombat.
  - level, classification (elite, rare, boss), first seen zone + coordinates, times killed, fight lengths.
- **Owner notes**: `/qb note <text>` stamps the current target (creature id), tCombat, zone, build. Shown on
  the creature's timeline and uploaded. Also `/qb note` with no target stores a zone note.
- **Provenance records** (extend Game.lua/Loot.lua):
  - vendors: per merchant NPC id: zone, coordinates, items sold {itemId, price, currency, limited stock}.
  - objects: LOOT_OPENED from a GameObject GUID: object id, zone, coordinates, items.
  - rares: first sighting of classification rare/rareelite: creature id, level, zone, coordinates, time.
  - quest rewards and boss drops: as today.
- Everything goes through the existing tooltip queue so item names and stats arrive with the record.
- Module toggles in /qb options: Observe creatures, Notes, Vendors and objects. Off = unregister events.
- Size guard: QuestBankDB.obs is trimmed to the newest 500 creatures and 300 vendors; the harness tests it.

### On the site (tools/apply_observe.py)

- Reads every upload's obs block (probe_pull.py merges them as it does disc.loot).
- Per creature: ability list with name, spell id, median first-cast time, median interval between casts
  (from the fights that saw two or more), how many fights, whether it interrupts, debuffs it applies;
  notes with the owner's text (credited "a player's note", no names).
- Per item: a `from` list joining loot.json bosses, quest rewards, vendors, objects, rares and crafts, into
  plan/items-db.json as item.from = [{k: drop|quest|vendor|object|rare|craft, id, name, zone, inst}].
  This is the provenance index the gear picker, the codex loot browser and the addon filters read.
- Writes codex/creatures.json (site) and the creatures block of tools/questbank data (addon), with a
  selftest fixture like apply_loot.py's.

### Non-goals here

Timeline UI, timers, links, context profiles, camping, enchants, page design: later steps, own specs.
