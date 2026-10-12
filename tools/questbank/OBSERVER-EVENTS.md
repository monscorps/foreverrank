# What the Forever client tells addons, event by event

Filled from players' QuestBank 3.7.0 uploads (QuestBankDB.diag.ev, written by QuestBank/Observe.lua): per event, how
many times it fired, how many times every read was plain (ok), how many times at least one read was a secret value
(secret), how many times a call gave nothing (missing), and one sample of the fields read with the kind of value each
held. This table decides the observer's design (docs/superpowers/specs/2026-10-12-observer-and-roadmap-design.md,
Part B): an event is usable when ok is most of n; a field is usable when its sample kind is not "secret".

Read it off an upload with: `python3 tools/probe_pull.py` then `python3 tools/observer_events.py` (to be written with
Part B; until then, `/qb events` in game prints the same table).

| event | reads | seen | ok | secret | missing | usable? |
|---|---|---|---|---|---|---|
| UNIT_SPELLCAST_START | unit, guid, name, level, cls, hp, hpmax, cast, castStart, castSpell, chan, castId, spellId | | | | | |
| UNIT_SPELLCAST_SUCCEEDED | same | | | | | |
| UNIT_SPELLCAST_CHANNEL_START | same | | | | | |
| UNIT_SPELLCAST_INTERRUPTED | same | | | | | |
| UNIT_SPELLCAST_FAILED | same | | | | | |
| UNIT_SPELLCAST_STOP | same | | | | | |
| UNIT_HEALTH | unit, guid, name, level, cls, hp, hpmax, cast, chan | | | | | |
| PLAYER_TARGET_CHANGED | the target's unit reads | | | | | |
| UNIT_AURA (player, party1-4) | unit, n, name, spellId, source, kind | | | | | |
| NAME_PLATE_UNIT_ADDED / _REMOVED | the nameplate's unit reads | | | | | |
| VIGNETTE_MINIMAP_UPDATED | id, objectGUID, atlas, name | | | | | |
| MERCHANT_SHOW | guid, items, id, price, link | | | | | |
| LOOT_OPENED | slots, src | | | | | |
| ENCOUNTER_START / _END | id, diff, t | | | | | |
| PLAYER_REGEN_DISABLED / _ENABLED | t | | | | | |

Units read: target, focus, mouseover, pettarget, boss1-5, nameplate1-40, party1-4's targets. Never the player, the
party or a pet themselves. Kinds: string, number, boolean, table, secret (a Midnight secret value), nil (the call gave
nothing or is missing), none (nothing there and that is normal: a unit not casting, a vendor with no wares).
