# Cute_Quest: QuestBank's guiding as Cute modules (design)

Date: 2026-10-20. Cute 0.7.0. Repository `foreverrank`, `tools/cute` and `tools/questbank`.

## Why

The owner's brief: "take the main questing bank addon stuff into the cute addon, make it all in one go ... done
properly and modular and easy to view and oversightful and not messy and not a bunch of unwanted data, less is more on
guidance as long as it's modular and easy to change and clear". He called Cute's Guide tab today "a black boring
non-useful list of dungeons".

Cute's Guide is a page of cards: every dungeon in range with bars, pips, quests, mates, gear strips, a pace strip, a
timeline, and the officers' lines. It answers "what to run" with a whole catalogue. QuestBank answers "what to do
now" in one line (the step frame) and keeps the rest a click away. The guild wants QuestBank's answer inside Cute's
window, in Cute's look, switched on per module, with the Guide reduced to the step now and one dungeon.

The owner's rules that bind this design (memory): game-native icons; always-visible state; no catalogues (lead with
the window); no chat spam; learn, do not list; one addon for players, modules as toggles; Cute's look is black and
white, flat 1 px borders, ARIALN, minimal.

## The decision

Cute's zip gains one LoadOnDemand module folder, `Cute_Quest`, beside `Cute`:

- Its toc says `## Dependencies: Cute`, `## LoadOnDemand: 1`, `## X-Cute-Module: 1`, `## SavedVariables: CuteQuestDB`.
  Cute's Modules.lua finds it in the client's addon list and loads it when one of its modules is ticked in Settings >
  Modules; a member who keeps every quest module off never loads it (Data.lua is 1.1 MB).
- Its Lua is QuestBank's engine, copied at build time by `tools/cute/build.py` from `tools/questbank/QuestBank`, the
  single source of truth. Nothing is rewritten in the copy. QuestBank's window, `UI.lua`, is not copied: Cute draws
  its own pages. The window-free half of today's `UI.lua` (the Now, Available and Highest XP computations, the quest
  tooltip, the right-click menu, the chat links, the reward finders) moves on QuestBank's side into a new engine file,
  `Lists.lua`, on the same `QB.UI` table, so both addons run the same code.
- A copied file addresses its addon table as `local _, QB = ...`: inside `Cute_Quest` that table is Cute_Quest's own.
  Two files of Cute_Quest's own bracket the engine: `Shim.lua` first (what QuestBank's `Core.lua` gets from being the
  addon: the saved variables, the dormant flag) and `Bridge.lua` after the engine (what the engine files got from
  `UI.lua`: the window verbs `Open`, `Toggle`, `Refresh`, `ShowMenu`, `CopyLink`, `PostDialog`, `ShowErrors`,
  `OpenMap`, mapped onto Cute's window; the login the engine never sees; `/qb` routed). `Core.lua` is copied whole:
  its API, quest cache, settings, plan, run, recompute and event frame are the engine, and shimming them would copy
  most of its 3,000 lines by hand. Only its window calls are redirected (they go through `QB.UI`, which Bridge
  provides) and its slash handler is wrapped.
- If the addon QuestBank is loaded (`C_AddOns.IsAddOnLoaded("QuestBank")`), Cute_Quest does not run its copy. Every
  engine file's second line is `if QB.dormant then return end` (QuestBank's own files carry the line; the harness
  loads them with `dormant` nil, so QuestBank is unchanged by it). `Shim.lua` sets `QB.dormant` before they run, and
  the module's pages talk to `QuestBankAPI`, the global QuestBank's `Core.lua` sets to its own `QB` table (one line).
  Nothing runs twice: no second event frame, no second `/qb`, no second tooltip hook, no second sync prefix, no
  second chat line, no second upload note; the copy's 1.1 MB of data is never built.
- Cute's Modules.lua learns that one addon may register several modules: the first registered is the addon's
  primary, keyed by the folder (`Cute_Quest`), the rest keyed under it (`Cute_Quest:route`); each is its own row in
  Settings > Modules and its own choice per character; the addon loads when any is on and is disabled in the game's
  AddOns list only when all are off. A module may also say `onToggle = function(on)`, called when its choice changes.

## What the player sees

Cute's look throughout: `UI.FONT` (ARIALN), `UI.COLORS` (WHITE, INK, DIM, MUTE, GOOD, WARN, BAD), flat rows
(`UI:MakeLine`), one height (`UI.ROW`, 20 px), the band above the scroll area, virtual lists (`ui:List`). Icons are
the game's own (quest icons, class colours). Nothing lists what the module tracks.

### Guide (Cute's built-in module, rebuilt)

The band, which stays in view:

| Row | Text | Colour | Tooltip / click |
|---|---|---|---|
| 1 | The step now, from the quest engine: `G.Text(step)`, e.g. "Kill Kobold Vermin 3/8", "Hand in 2 quests at Marshal McBride", "Accept Investigate Echo Ridge from Marshal McBride" | WHITE, 15 px | the whole line where the row cut it; click opens Quests; right-click the step's menu (Not now, Drop, Lock, Scale, Hide) |
| 2, 3 | The next two steps, `G.Text` | DIM, 12 px | the whole line |
| 4 | Time to level, `G.TimeToLevel()`: "about 14 min to level 6" | MUTE | "From your XP an hour this level" or "From the plan's XP a minute" |
| 5+ | Your party's steps, `G.MemberSteps()`: "Brann: Kill Kobold Vermin 3/8" | the member's class colour | none |

With no step: row 1 says "Nothing to do yet: Quests says why." and opens Quests. With the Quests module off, the band
is one DIM line, "Tick Quests in Settings, Modules for the step now.", and a click opens Settings > Modules; the
dungeon card below stays.

Under the band, one list:

| Row | Content |
|---|---|
| head | `plan.next.line` from `G.Pick`: "Run The Deadmines: 3 guild mates online in range, 7 bosses you have not killed, 5 quests", or "No dungeon known for level 14 yet; The Deadmines opens at 18." For officers, `who` on the right is `plan.guild.line` ("Most members are 18-23: The Deadmines"). Tooltip: the pick's reasons (`G.Pick`'s `why`), then where the knowledge comes from (`G.Source`), then, for officers, the "Learned in play" lines |
| card | the picked dungeon alone: its name, level bar, the range, how sure (unchanged from today's card row) |
| bosses | its pips, "N left" |
| quests | the research's quests as they stand for you |
| mate... | the guild mates online in range, class-coloured, level, an Invite button each; "and N more online in range" |

Everything else today's Guide draws (every other dungeon's card, Missing enchants, Pace, Next up, the officers' per
dungeon lines, Learned in play as rows) leaves the page. The officers' learned lines live in the head's tooltip; the
rest is reachable where it was before the Guide (Statistics, Me, /cute rules, /cute diag). The Guide's Settings
section keeps its two rules and, while Quests is on, gains three rows: "Step frame" (the small movable frame the
engine draws, reskinned flat), "Direction arrow", "Lock the step frame".

The step frame and the arrow are the engine's `StepFrame.lua` and `Arrow.lua`, drawn by the copy. They take a skin
from `QB.Skin` when a host sets one (Cute_Quest's `Band.lua` does): the font path, INK, SOFT, ACCENT colours, and a
`Backdrop(frame)` that gives a flat fill and a 1 px edge. QuestBank itself sets no skin and looks as before.

### Quests (module `quests`, the addon's primary)

One list, no band:

| Row | Content |
|---|---|
| head "Now" | `who`: "from <hub>" where the engine places you |
| place x3 | the three places worth your time, in the order the engine's Available view gives them (`UI.PlaceGroups`): name = the zone or dungeon, `val` = XP there for you (`QB.Short`), `who` = "N quests, M min" (`g.open + g.picks + g.held`, `g.nearest`). Click folds its quests open under it |
| quest (under an open place) | name; `val` = XP; `who` = the status word (`st.text`); INK when held, DIM otherwise. Click: the engine's `QuestClick` (a waypoint on the arrow; Shift puts it on the pick-up list); right-click: the quest's menu. Tooltip: the engine's quest tooltip |
| head "Available" | `who`: "N more places" |
| more | "Show them" / "Fewer": the other places as place rows, folded by default |
| head "Highest XP" | |
| quest x8 | the engine's `Candidates(8)`: name, `val` = XP, `who` = minutes to its giver or its place |

Before the engine has read your log: one note row, "Reading your quest log." Settings section "Quests" (5 rows):
Accept for me (Off, On my route, Worth taking), Hand finished quests in for me, Progress in mob tooltips, Share with
your party, Note what the game shows for foreverrank.com.

### Route (module `route`)

Band: one line, "4,250 XP, level 12.3, 38 min" (`r.xp`, `r.level`, `r.t`), and one band button, "Start run" / "End
run" (`QB.Run.Start`, `QB.Run.Stop`). List: a row per leg of `QB.Target.Route()` (the route the arrow and the minimap
follow): "1. Goldshire", `val` = "12 min" (`leg.t`), `who` = "3 quests" (`#leg.rows`); the first leg carries the
row's white bar (the one target); tooltip: the leg's quests with their XP. With no legs: one DIM row, "Nothing to
hand in yet." Settings section "Route" (3 rows): Follow (The plan, Ready now), Show the way step by step on the
arrow, The hearthstone may be a step.

### Map (module `map`, no page)

Owns the switches of the engine's map files, which draw on the game's own maps: Settings section "Map" (5 rows):
Quest icons on the world map (`mapIcons`), Route pins on the world map (`pins`), Route on the minimap (`minimapPins`
and `minimapLines` together), A ! on the minimap for quests you can take (`minimapGivers`), Minimap far view
(`mmExtended`). The module off sets all five false; on sets all five true. QuestBank's own Map page (`MapPage.lua`)
is never on in Cute (`mapPage = false`): the Map key opens the game's map.

### Journal (module `journal`)

The engine's Dungeon Journal (`DungeonMap.lua`, `DM.Attach`) on a host frame inside Cute's scroll area, 468 px high,
the cover art and floor art as they are (the art is the point). Settings section "Journal" (4 rows): Bosses, Rares,
Trash, Chests and events (`djShow`).

### Gear (module `gear`)

The engine's Gear page (`Gear.lua`, `G.Attach`) on a host frame, 440 px high, its text through `QB.Skin`. Settings
section "Gear": one row, Quests up to 2 levels ahead (`finderAhead`), and a note on how upgrades are judged. (Fewer
rows than the others: the page has one setting.)

### Camp (module `camp`, no page)

Settings section "Camp" (6 rows): Camp bar (`campBar`), Missing buffs when you leave town (`remind.buffs`), Sleeping
bag (`remind.bag`), Sellers of camp goods (`remind.wood`), Interact light (`glow.on`), Light style (Sparkle, Light,
Game's: `glow.style`). The module off: bar, banner and light off; on: all three on.

### Chat

The engine says one thing in play: the XP a hand-in paid ("Kobold Camp Cleanup: +250 XP"). Everything else it could
print is off by the module's defaults (below) or routed: `/qb` and `/questbank` open Cute's Quests page; `/qb route`,
`journal`, `gear`, `map` open those pages; any other `/qb` word reaches the engine's own handler (`/qb skip
Kalimdor`, `/qb way`, `/qb done`). `/cute quests`, `/cute route`, `/cute journal`, `/cute gear` work as every page's
name does.

## The module registry entries

All six are registered from Cute_Quest's own files with `Cute:RegisterModule` (external: never core nor built in,
off on a fresh install). `order` places them after the Guide (20) and before Prog (30).

```lua
-- PageQuests.lua
Cute:RegisterModule({ id = "quests", addon = ADDON, title = "Quests", order = 21,
  notes = "The three places worth your time, the rest folded, the highest XP; the step now in the Guide.",
  page = PageQuests.Draw, settings = PageQuests.Settings, onToggle = PageQuests.Toggle,
  events = { QUEST_LOG_UPDATE = redraw, QUEST_ACCEPTED = redraw, QUEST_TURNED_IN = redraw, PLAYER_LEVEL_UP = redraw, ZONE_CHANGED_NEW_AREA = redraw } })
-- PageRoute.lua
Cute:RegisterModule({ id = "route", addon = ADDON, title = "Route", order = 22, notes = "The hand-in stops in order with minutes; the first is where the arrow points.",
  page = PageRoute.Draw, settings = PageRoute.Settings, events = { QUEST_LOG_UPDATE = redraw, QUEST_TURNED_IN = redraw, ZONE_CHANGED_NEW_AREA = redraw } })
-- PageMap.lua
Cute:RegisterModule({ id = "map", addon = ADDON, title = "Map", order = 23, notes = "Quest icons and the route on the game's world map and minimap.", settings = PageMap.Settings, onToggle = PageMap.Toggle })
-- PageJournal.lua
Cute:RegisterModule({ id = "journal", addon = ADDON, title = "Journal", order = 24, notes = "Every dungeon: its bosses, their recorded loot, its quests, its floors.", page = PageJournal.Draw, settings = PageJournal.Settings })
-- PageGear.lua
Cute:RegisterModule({ id = "gear", addon = ADDON, title = "Gear", order = 25, notes = "What you wear and the best upgrade for each slot: a quest reward in reach or a dungeon drop.", page = PageGear.Draw, settings = PageGear.Settings })
-- PageCamp.lua
Cute:RegisterModule({ id = "camp", addon = ADDON, title = "Camp", order = 26, notes = "The camp bar, the missing-buffs banner and the interact light.", settings = PageCamp.Settings, onToggle = PageCamp.Toggle })
```

`redraw` is each file's `function() Cute.Refresh() end` (Cute's `UI:Refresh`, which draws at most once a second
while the window is shown). The Guide's band reads `Cute.QuestBand`, which `Band.lua` sets:

```lua
Cute.QuestBand = {
  On = function() return Cute.ModuleOn("quests") and E.logReady == true end,
  Steps = function() return E.Guide.Steps() end,      -- the engine's pooled step tables
  Text = function(s) return E.Guide.Text(s) end,
  TimeToLevel = function() return E.Guide.TimeToLevel() end,
  Members = function() return E.Guide.MemberSteps() end,
  Open = function() Cute.Open("quests") end,
  Menu = function(s) E.StepFrame:Menu(s) end,
  Settings = function(col) ... the three Guide rows ... end,
}
```

`E` is `QB.Engine`: this copy's `QB`, or `QuestBankAPI` when QuestBank is loaded. The global `Cute` table gains, for
module addons: `Cute.Open(page, section)`, `Cute.Refresh()`, `Cute.Print(msg)`, `Cute.Page()`, `Cute.ModuleOn(id)`,
`Cute.Safe(fn, where)`, `Cute.Font()`, `Cute.Host(ui, key)` (a frame under the scroll area that Cute hides when its
page is not drawn: the Journal's and the Gear's).

## The shim

Cute_Quest's toc, generated by the build, in this order: `Shim.lua`; the engine files in QuestBank's toc order with
`UI.lua` left out (`Data.lua`, `Core.lua`, `Lists.lua`, `Discover.lua`, `Survey.lua`, `Game.lua`, `Loot.lua`,
`Observe.lua`, `Timer.lua`, `Link.lua`, `MinimapTiles.lua`, `MinimapView.lua`, `MinimapRoute.lua`, `Minimap.lua`,
`DungeonMap.lua`, `Glow.lua`, `Walk.lua`, `Camp.lua`, `Model.lua`, `Legacy.lua`, `Travel.lua`, `Pins.lua`,
`QuestMap.lua`, `Pins.xml`, `Arrow.lua`, `Target.lua`, `Sync.lua`, `Auto.lua`, `Guide.lua`, `MapPage.lua`,
`Gear.lua`, `StepFrame.lua`, `Tips.lua`); then `Bridge.lua`, `Band.lua`, `PageQuests.lua`, `PageRoute.lua`,
`PageMap.lua`, `PageJournal.lua`, `PageGear.lua`, `PageCamp.lua`. The art folder is copied whole. The engine names
its art by the folder `Interface\AddOns\QuestBank\art\`, which a Cute-only player does not have, so `Shim.lua` sets
`QB.ART = "Interface\\AddOns\\" .. ADDON .. "\\art\\"` and the seven engine files that hard-code the path
(`Arrow.lua:503`, `Camp.lua:466`, `Glow.lua:587`, `DungeonMap.lua:22`, `Minimap.lua:29`, `Pins.lua:452`,
`MinimapRoute.lua:13`) read `QB.ART or "Interface\\AddOns\\QuestBank\\art\\"` (a one-line change each on QuestBank's
side; QuestBank sets no `QB.ART`).

What `Core.lua` needed from being the addon, and how each is met:

| Need | QuestBank | Cute_Quest |
|---|---|---|
| `ADDON` (vararg) for `ADDON_LOADED` and blocked-action attribution | "QuestBank" | "Cute_Quest": `Core.lua` compares `a1 == ADDON`, so its `ADDON_LOADED` branch runs for the copy |
| `QuestBankDB` saved variables | `## SavedVariables: QuestBankDB` | `## SavedVariables: CuteQuestDB`; at `ADDON_LOADED` for Cute_Quest, `Shim.lua`'s frame (made first, so it hears first) sets `QuestBankDB = CuteQuestDB`. `Core.lua` only ever does `QuestBankDB = QuestBankDB or {}` and writes fields, so both names stay one table and the game saves it under CuteQuestDB. Errors recorded before the alias (a file-load error) are appended to it |
| `PLAYER_LOGIN` (the engine's `Init` chain) | the event | never fires for an addon loaded on demand: QuestBank's `Core.lua` moves that branch into `function QB:Login()` (the handler calls it), and `Bridge.lua` calls `E:Login()` from its own `ADDON_LOADED` (its frame is made after `Core.lua`'s, so the alias and `QB:Settings()` have run) |
| `/qb` | `SlashCmdList.QUESTBANK` | kept, wrapped by Bridge: page words go to Cute's pages, the rest to the engine's handler |
| `QB.UI` (the window) | `UI.lua` | `Lists.lua` (copied) makes the table and its window-free functions; Bridge adds the window verbs |
| `QB.Minimap` (the minimap button, in `UI.lua`) | `UI.lua` | absent: `Core.lua` guards every call with `if QB.Minimap` |
| The welcome card (`settings.welcome`) | the step frame asks the auto choice | never: Bridge sets `welcome = nil` at the module's first run; the choice is a Settings row |

Bridge's window verbs on `E.UI` (the copy only): `Open(tab)` maps QuestBank's tab numbers to Cute's pages (1, 2, 6 →
quests; 3 → route; 4 → guide; 5 → settings, section quests; 7 → journal; 8 → map, which has no page, so quests);
`ShowTab`, `TogglePage` the same; `Toggle` → quests; `Refresh` → `Cute.Refresh()`; `OpenMap` → `ToggleWorldMap()`;
`MapPageOn` → false; `ShowMenu(title, items)` → the game's `MenuUtil.CreateContextMenu` (a title and a button per
item; without MenuUtil, one chat line naming the items); `CopyLink(title, url)` → one chat line; `PostDialog` → nothing
(`post.auto` is off); `ShowErrors` → the count and the newest five of `QuestBankDB.errors` in chat; `Caret` → nothing;
`frame`, `tab`, `lastTab`, `postFrame`, `scrollToQuest` → nil (every engine read of them is guarded).

The module's first-run defaults, set once by Bridge when `CuteQuestDB.settings.cuteDefaults` is nil: `mapPage =
false`, `post.auto = false`, `updates = false`, `clockLevelMsg = false`, `welcome = nil`, `minimap.hide = true`;
`guide.on`, `guide.frame`, `arrow`, `minimapGivers`, `tipProgress` as the module toggles set them. In dormant mode
Bridge sets nothing: QuestBank owns its settings, and the pages only read them and edit them where a row says so.

## The build

`tools/cute/build.py` gains `build_quest(version)`, run before the zip:

1. Reads `tools/questbank/QuestBank/QuestBank.toc`. Every file it lists must be in `ENGINE_KNOWN` (the list above) or
   be `UI.lua`; any other name stops the build: "QuestBank.toc lists X, which build.py does not know: check it in
   Cute's harness, then add it to ENGINE_KNOWN".
2. Copies each engine file and `Pins.xml` to `tools/cute/Cute_Quest/`, and `art/*` to `Cute_Quest/art/`, byte for
   byte (`shutil.copyfile` where the bytes differ), then reads both back and compares; a difference is a problem.
3. Checks each copied `.lua` has `if QB.dormant then return end` as the first statement after its `local ..., QB =
   ...` line.
4. Refuses a `.lua` or `.xml` in `Cute_Quest/` that is neither copied nor one of the nine own files.
5. Writes `Cute_Quest/Cute_Quest.toc` (the only file it generates), with `## Version:` Cute's and `## X-QuestBank:`
   QuestBank's toc version, when its text changed.
6. The zip is `zip -rq Cute.zip Cute Cute_Quest -x "*.DS_Store"`; the page's KB covers both folders.

The copied files are committed (the zip and the harness need them; a diff shows what a QuestBank change brings in).
The build is the only thing that writes them.

## Settings: kept, forced, left at their defaults

QuestBank's `DEFAULTS` (Core.lua) has 67 keys. In Cute:

- As rows (16): `autoAccept`, `autoTurnIn`, `tipProgress`, `share.party`, `noteGame` (Quests); `guide.frame`, `arrow`,
  `guide.locked` (Guide); `routeQuest`, `arrowTravel`, `arrowHearth` (Route); `mapIcons`, `pins`, `minimapPins` +
  `minimapLines`, `minimapGivers`, `mmExtended` (Map); `djShow.boss`, `djShow.rare`, `djShow.trash`, `djShow.other`
  (Journal); `finderAhead` (Gear); `campBar`, `remind.buffs`, `remind.bag`, `remind.wood`, `glow.on`, `glow.style`
  (Camp).
- Forced once at the module's first run (6): `mapPage = false`, `post.auto = false`, `updates = false`, `clockLevelMsg
  = false`, `welcome = nil`, `minimap.hide = true`.
- Set by a module's toggle (5): `guide.on` and `guide.frame` (Quests on/off), `arrow` (Quests off switches it off; on
  again needs the Guide row), the Map's five, the Camp's three.
- Left at QuestBank's defaults, reachable through `/qb` where it has a command (the rest): `mounted`, `goal`,
  `routeMode`, `tab`, `share.guild`, `rangeAbove`, `rangeBelow`, `skipCat`, `skipCont` (`/qb skip`), `autoAcceptOther`,
  `sayAccept`, `sayComplete`, `autoKey`, `profiles`, `clock.show`, `minimapPickups`, `minimapEntrances`,
  `minimapObjectives`, `minimapLabel`, `markerStyle`, `mmRing`, `mmGlyphPct`, `mmColor`, `oneColor`, `zmWidth`,
  `zmAlpha`, `mmArrowSize`, `goldenPath`, `gpSpacing`, `gpWidth`, `gpAlpha`, `gpColor`, `compassSize`, `compassBg`,
  `arrowStyle`, `mapIconPct`, `mmCenter`, `mmParty`, `mmAreas`, `minimapSteps`, `glow.npcs`, `glow.everyNpc`,
  `glow.other`, `glow.combat`, `glow.plates`, `walkRecord`, `walkShow`, `remind.camp`, `remind.food`, `remind.fire`,
  `remind.quietInstance`, `remind.sit`, `remind.bagChain`, `arrowMode` (`/qb arrow`), `survey`, `mapGive`, `mapTurn`,
  `mapObj`, `mapDungeons`, `mapRoute`, `mapFlights`, `guide.scale` (the step frame's menu).

Module on/off is Cute's (`CuteDB.chars[me].modules`); the engine's settings are the engine's (`CuteQuestDB.settings`,
or QuestBank's own when it is loaded), so a player with both addons has one set.

## Testing

Cute's harness (`cd tools/cute && luajit harness.lua`, must end `layout problems: 0` then `OK`) grows:

- `test/quest_mocks.lua`, `install(env, c, o)`: the mocks the engine reads that Cute's mock lacks, ported from
  `tools/questbank/harness.lua`'s `newClient` (lines 405-1146) and its map canvas (281-379): `C_Map`, `C_TaxiMap`,
  `C_QuestLog`'s objectives, watch, tag, push and load calls, `C_Minimap`, `C_GossipInfo`, `C_CVar`, `C_DeathInfo`,
  `C_NamePlate`, `C_SpellBook`, `C_Texture`, `C_TooltipInfo`, `C_Item`'s icon, cooldown and load calls,
  `C_Container`'s id, link and quest-info calls, `MenuUtil`, the minimap cluster, `WorldMapFrame` and the
  `MapCanvasMixin` family, `GetQuestLogSpecialItemInfo`, `UnitPosition` in the engine's shape, the secret values; and
  the widget whitelist grows by QuestBank's (`SetAtlas`, `SetPassThroughButtons`, `SetCooldown`,
  `SetHideCountdownNumbers`, `SetRotation`, `SetUserPlaced`, `GetZoom`, `SetZoom`, `GetZoomLevels`, `CreateLine`,
  `SetStartPoint`, `SetEndPoint`, `SetThickness`, `SetTextInsets`, `SetAttribute`, `GetAttribute`, `SetGradient`,
  `SetClipsChildren`, `PingLocation`, `SetSnapToPixelGrid`, `SetTexelSnappingBias`, `IsForbidden`,
  `SetPushedTexture`, `GetTextColor`, `SetMultiLine`, `HighlightText`, and the backdrop, model and POI methods).
  A client made with `o.quest = true` gets them.
- A module addon's folder is looked for under `test/` first, then under `tools/cute/` (where the build writes
  `Cute_Quest`).
- Scenarios: Cute_Quest listed by its toc title and not loaded; Quests ticked loads it (`QuestBankDB` is
  `CuteQuestDB`, the engine's `Data` built, `E:Login()` ran, the step frame up and flat), its tab and section come,
  the Guide's band shows the step now, the next two, the time to level; every quest page at both window sizes for an
  officer and a member with every module on, through `check(root, label)`; each module's section rows write the
  engine's settings; Route, Map, Journal, Gear, Camp each ticked alone load the addon and show their own row only;
  unticked, the tab goes, and the addon is disabled in the AddOns list only once all six are off; a client where
  QuestBank is loaded (`C_AddOns.IsAddOnLoaded("QuestBank")` true, `QuestBankAPI` a stub engine) ticks Quests and the
  copy stays dormant: no `Data`, no `SLASH_QUESTBANK1` from the copy, no frame of the copy registered
  `QUEST_TURNED_IN`, the band drawn from the stub; the Guide with Quests off says so in one line and keeps the card.
- Memory and garbage gates, ported from QuestBank's harness block (17519-18080): what the copy keeps after login with
  every quest page opened, reachable from the module's private table and `CuteQuestDB` (`kept`, budget 11 MB in
  LuaJIT's layout, QuestBank's own); `QB:Changed()` with the window shut under 100 KB of the copy's own garbage;
  `QB.Guide.Replan()` with nothing changed under 64 KB (`ownBytes` charging allocations to files whose source names
  `Cute_Quest/`).

QuestBank's harness (`cd tools/questbank && luajit harness.lua`, must end `OK`) keeps passing after each
QuestBank-side change: the guard lines, `QB:Login`, `QuestBankAPI`, `Lists.lua`, `UI.PlaceGroups`, `QB.ART`,
`QB.Skin`.

`python3 tools/cute/build.py` must end `problems: 0` then `OK`, and refuses an unknown engine file, a copy that
differs from its source, a stray file in `Cute_Quest/`, a copied file without its guard line.

Machine safety: one `luajit` at a time, never both harnesses together; `memory_pressure | tail -1` must read normal
before QuestBank's harness (its memory block builds 8,000 trail points and loads the catalog several times).

## The page (`addons/cute/index.html`)

- The window mock's Guide shows the band as the addon draws it with Quests on: the step now in white, the next two
  dim, the time to level, then the pick's line and one card. A viewer with Quests off in the mock's Settings >
  Modules sees the one-line band.
- The mock's Settings > Modules lists Guide, then Quests, Route, Map, Journal, Gear, Camp, each with its notes in the
  tooltip; ticking one adds its tab (Quests, Route, Journal, Gear) or only its section (Map, Camp).
- Install: "You get two folders, Cute and Cute_Quest. Put both in Interface\AddOns." One sentence after it: "Quests,
  Route, Map, Journal, Gear and Camp switch on in Settings, Modules; the Guide then shows your next step."
- One changelog line for 0.7.0. No list of what the modules track.

## Out of scope

- QuestBank's window stays QuestBank's; nothing of it moves to Cute (Settings page, Party page, Quest Log page, Map
  page, the post dialog, the minimap button).
- The QuestBank Uploader, the site's upload merge and the saved-file shape are untouched: `CuteQuestDB` has
  `QuestBankDB`'s shape, and the uploader reads `QuestBank.lua`, not `Cute_Quest.lua` (a Cute-only player's notes
  reach the site in a later round: the uploader learns the second file name).
- Reskinning the Dungeon Journal and the Gear page beyond their text (their art stays).
- The Guide's gear and pace strips, Next up, the officers' per dungeon lines as rows: gone from the Guide; not
  moved elsewhere in this round.
- A stat in Cute's registry from the quest engine (none: less is more).
- Cute's own step frame or arrow: the engine's are reused through the skin hook.
