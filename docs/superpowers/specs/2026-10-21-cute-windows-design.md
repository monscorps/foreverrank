# Cute windows: J, L and M as Cute's own (design)

Date: 2026-10-21, revised the same day after the owner-words and visual reviews (section 17). Builds on **Cute 0.7.1
and QuestBank 6.1.1 as shipped** (commits 290b1ca, f63c9d9, 847947e, 03faafb, 3703440, 56a2ac6). Repository
`foreverrank`: `tools/cute` (Cute, and Cute_Quest built from `tools/questbank/QuestBank` by `tools/cute/build.py`),
`tools/questbank`, `uploader/`, `worker/`, `tools/probe_pull.py`. Client: WoW Forever 1.60.1 (70338), game type
camelot, launch 4 November. API truth: `research/wow-ui-source` at HEAD; client data `research/wago/1.60.1.70338`.
Mockup: `research/qbrender/cute-windows.html` (seven screens, the game's pixel size, the game's own art).

Earlier designs this one changes: `2026-10-20-cute-quest-modules-design.md` (the modules, the Guide band, the Map
module without a page) and `2026-10-20-questbank-guide-design.md` (the step frame). This round is too big for one
plan: section 16 splits it into seven sub-projects in launch order, each shippable alone.

## 0. Summary

1. Three windows on the game's keys, by override bindings that follow the player's own: J Guild (Cute core), L Quests, M Map.
2. Quests (L, with its Route tab) and the step frame are the base, always on; Dungeons and Gear are tabs, Map and Camp modules.
3. A first-run card asks once per character, starting from its saved 0.7 choices, takes the keys and reloads; later only window and tab changes reload.
4. Right-click on the minimap button (or the addon compartment) opens a menu that jumps to every tab, Settings section, zone map and the Finds list.
5. Layout mode moves, scales and locks the on-screen pieces (step frame, arrow, camp bar, banner); windows always drag by their 30 px header.
6. Settings is one window whose section list fits at 760 x 420 and whose labels, notes and choices wrap: nothing is cut.
7. One visual system: icon = kind, 2 px bar = category, text colour = hierarchy, right-hand word = status, background = state; game art only.
8. A quest row's click reads the quest everywhere (text, objectives, rewards, Share, Abandon, Show on arrow); Ctrl-click puts it on the arrow.
9. L's Quests tab: the step band, places by XP a minute, and beside them the guild's dungeon pick, the gear upgrade and the party.
10. The Route tab: a small map with one route stroke beside a timeline whose stops add up the XP bar and mark the level-up.
11. M is QuestBank's map canvas in Cute's window: wheel through zones, drag, pins at the game's size merged when they touch, our list beside it.
12. Built on what 6.1.1 shipped: the game's tracker out of sight (D adds the click fix), low-level quests by the game's word, one stroke, learned rides.
13. Finds (chests, locks and keys, book titles, rares, crossings) noted in play reach foreverrank.com from Cute players too, and come back without a release.
14. In the guild, finds travel as 1X under the officers' routing, change routes only once two members agree, and never go out on RAID or GUILD past the policy.
15. Sub-projects in launch order: A fixes, B finds to the site, C+D windows and look in one release, F the map, G finds in the guild, E layout mode.

## 1. Why

The owner, after playing Cute 0.7.0 and QuestBank 6.1.0 (2026-10-20/21):

- "each module cover the in game features already provided ... 'J' guild & communities in the base cute addon, 'M'
  & 'L' for map etc. This is our base with quests and route and quality of life settings and modules around it."
- "dungeon and gear is just part of the quest, tabs there. but you can enable or disable those tabs."
- "right click cute addon and jump into the specific part i want to open."
- "more settings to customize and lock and move modules etc too on screen."
- The map: scroll cleanly inside it and through zones, drag, show books and keys, and "instead of ... a list of the
  quests we show our list which is more insightful without having to click each quest, but you can also click them
  and read it." It replaces the game's map by default; "we ask what modules they want, and to auto keybind and tell
  them they can change it later in settings and force a reload after settings is changed."
- "The route square is a black box of boredom." "Guide page is boring": colours to categorise, game icons, the
  dungeon and gear images QuestBank already has.
- "icons on map are scuffed as they are wrong size, we also show low level quests as default?"
- "option in settings to hide objectives and its hidden by default, the in game blizzard one, if they use ours."
- "settings cuts off so i cant read them that well."
- "sharing data discovered in game beyond everything found already with questbank is also key."

Rules that still hold: less is more on guidance, modular, clear; "not messy and not a bunch of unwanted data"; black
and white, flat, minimal, "like shadowed unit frames and elvui", professional; game-native icons, never invented
shapes; no Unicode symbols outside Windows-1252 in game text (the "·" is in it, "→" is not); a feature shows something
the first time it is switched on; no catalogues of what an addon does; QuestBank's own arrow, not a compass; one route
line at a time; rank quests by XP per minute; the guild's privacy model stays (Only-you values to officers only, the
officers' settings in a Guild Info line, two voices to learn); Forever is learned in play, never listed.

**Already shipped on 2026-10-21** (QuestBank 6.1.1, Cute 0.7.1). This design builds on these and never redoes them:

| Owner's words | What shipped | Where |
|---|---|---|
| "hide objectives ... hidden by default ... if they use ours" | The game's quest tracker out of sight by its alpha while the step frame shows, a `SetAlpha` hook keeping it out, never in a fight; `guide.hideTracker`, on; the step frame's default place kept 16 px clear of the tracker's header | `StepFrame.lua:418-454` `SF.Tracker`; Cute's row "Hide the game's quest tracker" (`PageQuests.lua:109`); 290b1ca |
| "we also show low level quests as default?" | Grey is the game's word (`C_QuestLog.IsQuestTrivial`) or the level rule; a grey quest's ! shows only with `mapLowLevel` (off), then half bright | `QuestMap.lua:201-205, 420-425`, `Core.lua:1333`; Cute's Map row "Low-level quests" (`PageMap.lua:22`); f63c9d9 |
| "one at a time" (route lines) | One stroke from you to where the arrow leads unless `wholeRoute` | `MapPage.lua:272-274`, `Minimap.lua:905-924`, `Core.lua:1334`; Cute's row "Show the whole route" (`PageMap.lua:24`); 03faafb |
| (boats) | Each boat or zeppelin leg ridden is learned: `disc.rides["<kind>:<town>><town>"]` = boarded, landed, seconds | `Travel.lua:21-26, 183-200`; 847947e |

What is left after 6.1.1, with the evidence:

| Seen in play | Cause in the files |
|---|---|
| Guild and quests share one window and its tabs | `Cute/UI.lua` registers every page as a tab of `CuteFrame` |
| M opens the game's map, as the addon | `Cute_Quest/Bridge.lua:76` calls `ToggleWorldMap()`, which QuestBank forbids (`QuestBank/UI.lua:975-978`: the game later blames the addon) |
| Settings cut "On my route" to "On..." | `Cute/Settings.lua:158` gives a Choice option 42 px; notes are one line; the section list shrinks its rows to 16 px (`Settings.lua:459`) |
| A black box on screen | the step frame drawn with Cute's flat backdrop (`QB.Skin.Backdrop`, `StepFrame.lua:80`) |
| Map icons look soft and mixed | QuestBank draws its quest art at `mapIconPct = 50` (`Core.lua:1298`, `Pins.lua:578-584`, 5.4.4's "massive, can be halved") beside the game's pins at full size |
| The hidden tracker still takes clicks | 6.1.1's own note: "Out of sight, its lines still take a click where they stand" (`StepFrame.lua:425`) |
| Right-click on the minimap button only opens Settings | `Cute/UI.lua:1909-1911` |
| Nothing a Cute-only player notes reaches the site | the uploader watches `QuestBank.lua` only (`uploader/QuestBank-Uploader.ps1:28`), the Worker takes only `QuestBankDB =` (`worker/src/index.js:713`), `probe_pull.py:185` decodes only `QuestBankDB` |
| (not seen, found in review) Cute_Quest's copy of Sync sends level, XP, plan and quest progress past the officers' routing | `share.guild = true` by default (`Core.lua:1260`), never set by Cute: `Sync.lua:71` sends on GUILD, and `Sync.lua:252` takes a single guild mate's XP reading; `share.party` sends the same to RAID in a guild raid (`Sync.lua:60-71`) |

## 2. The shape

Three windows, each on the key the game already uses for that job, and one Settings window:

| Key | Window (frame) | What is inside | Replaces the game's | The game's one click away |
|---|---|---|---|---|
| J | Guild (`CuteFrame`, Cute core, always there) | tabs Race, Prog, Hall of Shame, Statistics, Officers (officers only), Me | Guild & Communities (`TOGGLEGUILDTAB`) | header button "Guild & Communities" |
| L | Quests (`CuteQuestFrame`, Cute_Quest, always there) | tabs **Quests** and **Route** (always), **Dungeons** and **Gear** (each switched on or off) | Quest log (`TOGGLEQUESTLOG`, the quest panel of the world map on this client) | header button "Quest log" |
| M | Map (`CuteMapFrame`, Cute_Quest, the Map module) | the map canvas with zoom and drag across zones, our quest list beside it, the layers (quests, route, flight points, finds, dungeons) | World map (`TOGGLEWORLDMAP`) | header button "Game's map" |
| none | Settings (`CuteSettingsFrame`, Cute core) | every section, nothing cut | | the cog in each window's header |

**The base** (the owner's "our base with quests and route"; decided here, section 13): Guild, Quests with its Route
tab, and the step frame with the arrow are always there for a Cute character; the modules around them are the
Dungeons and Gear tabs, the Map window and Camp. The cost is that every Cute character loads Cute_Quest (Data.lua,
11 MB kept at the memory gate); the on-screen pieces can still be switched off, and Cute_Quest sleeps when the addon
QuestBank is loaded (0.7's dormant rule).

What L covers of the game's quest log: every quest you hold with its objectives, the quest's own text (section 9, the
quest to read), Share and Abandon, the hand-in, and the route. The game's log stays one header click away. What J
leaves to the game's window, one click away: guild chat, the message of the day, member notes, rank edits and guild
invites (Cute shows and learns; the game's window administers).

On screen, with no window: the step frame (the step now and the quests you hold, in place of the game's objective
tracker), QuestBank's arrow, the camp bar with the missing-buffs banner, the interact light.

Module keys stay 0.7's, so every character's choices carry over: `Cute_Quest` (Quests, now always on),
`Cute_Quest:route` (always on), `Cute_Quest:journal` (titled Dungeons), `Cute_Quest:gear`, `Cute_Quest:map`,
`Cute_Quest:camp`. Each module def gains `window = "guild" | "quests" | "map"`; `UI:Open(page, section)` opens the
page's window on that tab, and `Cute.Open` keeps its signature for module addons. The core builds all four windows
with one builder (header, tabs or section list, band, scroll area, footer), so they look and behave alike; a module
addon only draws pages.

The built-in Guide module retires (sub-project C): its band becomes the Quests tab's band, its dungeon pick the Quests
tab's Dungeon section and the Dungeons tab's head, its two officers' rules move to Guild > Rules. Its logic
(`Cute/Guide.lua`: `G.Pick`, `G.CardRows`, the mates and Invite) stays in the core as guild knowledge, read by
Cute_Quest's pages through a new door, `Cute.Guide`. `/cute guide` opens L on Quests.

## 3. First run

**The card** (`CuteSetupFrame`): 480 px wide, centred, PANEL fill, 1 px EDGE border, rows 22 px, no row icons,
nothing cut (it obeys the Settings rules of section 7). Drawn as it stands once sub-project F has shipped; before F
the Map row reads "Quest icons on the game's map" and takes no key (row id `mapicons`).

```
Set up Cute                                     (15 px WHITE)        for Brann (11 px DIM)
Windows
  [x] Guild              always (greyed tick)                [ J ]
  [x] Quests and Route   always (greyed tick)                [ L ]
        [x] Dungeons tab   [ ] Gear tab
  [x] Map                                                    [ M ]
On screen
  [x] Step frame and arrow
  [x] Camp bar and missing buffs
  [x] Interact light
Quests
  Accept for me     (o) Off   ( ) On my route   ( ) Worth taking        (radio circles)
  [ ] Hand finished quests in for me
J, L and M open Cute's windows; each window has a button to the game's own. Change any of this later in Settings:
right-click the minimap button. Window and tab changes reload; the rest applies at once.      (12 px DIM)
                                                     [Start] (WHITE fill, black text)   [Not now]
```

- **When.** Once per character, 3 s after the first `PLAYER_ENTERING_WORLD` that is out of combat and outside an
  instance. 0.7 characters see it too.
- **The ticks start from what the character has.** A row whose setting this character has saved starts from it: the
  modules enabled for the character (`C_AddOns.GetAddOnEnableState` and `CuteDB.chars[me].modules`), `guide.frame`,
  `campBar`, `glow.on`, `auto.accept`, `auto.turnin`. Only a row with nothing saved starts at the default: everything
  on except the two automatic choices, Off as QuestBank asks them ("replaces by default" is the owner's word; the card
  is the question). So a 0.7 character with Gear off and Accept for me "On my route" sees exactly that, and Start
  changes nothing it did not show.
- **Which rows.** Each row has an id (`guild`, `quests`, `dungeons`, `gear`, `mapicons` before F and `mapwin` from F,
  `step`, `camp`, `light`, `accept`, `handin`); the card shows only rows this character has not answered
  (`CuteDB.chars[me].setup[rowId]`). A later sub-project that adds a window adds its row and the card comes back once
  with that row alone: F's `mapwin`, whose tick starts from the `mapicons` answer (unticked there, unticked here). A
  later default needs no row. Rows for a module addon missing from the client's addon list are left out. With the
  addon QuestBank loaded, the On-screen rows are replaced by one DIM line, "QuestBank is loaded: its step frame, arrow
  and camp bar are its own." (0.7's dormant rule: Cute sets none of QuestBank's settings).
- **Key boxes.** A box shows the key that will open the window: by default whatever key the player has for the game's
  action (`GetBindingKey("TOGGLEGUILDTAB" | "TOGGLEQUESTLOG" | "TOGGLEWORLDMAP")`, read through `C.Plain`), so a player
  who moved the map to N gets N. A click shows "Press a key" (modifiers allowed); Esc keeps the old one; Backspace
  clears it (the game's key keeps the game's window). A key chosen by hand that does something else shows one DIM line
  under its row from `GetBindingAction(key)` and `_G["BINDING_NAME_" .. action]`: "replaces Action Button 5". The
  Guild key is taken only while the character is in a guild (`IsInGuild`, applied again on `PLAYER_GUILD_UPDATE`).
- **How rows map to modules.** Camp is on when either of its two rows is ticked (the first sets `campBar` and
  `remind.buffs`, the second `glow.on`).
- **Start.** Writes the choices, `setup` for every row shown, `openAfter = "quests"`, then reloads (`C_UI.Reload`,
  documented with no restriction, `UIManagerDocumentation.lua:65`). After the reload Cute opens L on the Quests tab once,
  so the window shows something the first time. In combat Start is greyed with "After combat".
- **Not now.** Changes nothing: J works from the minimap button and `/cute`, no key is taken. The right-click menu
  carries "Set up Cute..." until Start; the card never comes back by itself.

**Reloads** (decided here, and put in front of the owner at review: "force a reload after settings is changed" is
read as the window and tab choices; the card's copy says so).

- What reloads: which windows, tabs and on-screen modules a character runs (the card, Settings > Modules). Changes
  there are staged in memory and the section shows one band line: "Applies on reload. [Reload now] [Undo]". Closing
  Settings with changes staged shows the game's StaticPopup, "Cute reloads to apply your changes.", Reload (default) or
  Undo; Esc is Undo; there is no Later, so a half-applied state never exists. In combat the buttons are greyed and the
  popup waits for `PLAYER_REGEN_ENABLED`.
- What applies at once: keys (override bindings, section 4), layout and lock, every engine setting (Accept for me, the
  arrow...), the officers' sections. Reloading for a checkbox would be the opposite of quick.
- Why it is right beyond the owner's word: the engine's hooks on the world map, tooltips, minimap and taxi
  (`Pins.lua:493`, `Game.lua:560`, `Tips.lua:73`, `Minimap.lua:1196`, `Travel.lua:1531`) cannot be removed by an addon,
  so 0.7's live switching left a dead engine running; and one path at login replaces 0.7's live load and unload paths.
  Modules still load on demand at login (`C_AddOns.LoadAddOn`) and a module switched off is disabled for the character
  (`DisableAddOn`), as 0.7 does.

## 4. Keys

Decided here (the shell research asked the owner; the evidence settles it): **override bindings**, never the game's
binding set.

- Cute makes one owner frame, `CuteKeyOwner`, and three hidden buttons, `CuteGuildKey`, `CuteQuestsKey`, `CuteMapKey`,
  whose click toggles the window. For each window that is on, out of combat:
  `SetOverrideBindingClick(CuteKeyOwner, false, key, "CuteMapKey")` for every key the setting gives.
- The setting, per character, `CuteDB.chars[me].keys = { guild = "follow", quests = "follow", map = "follow" }`:
  `"follow"` takes every key bound to the game's action (rebinding the game's map key moves Cute's with it), a key
  string takes that key, `false` takes none. Settings > Keys has, per window, the key box, a "Follow the game's ...
  key" tick (ticked: `"follow"`; picking a key by hand unticks it; ticking it again goes back to following) and Clear.
- Applied at `PLAYER_LOGIN`, on `UPDATE_BINDINGS` and `PLAYER_GUILD_UPDATE`, and on a change in Settings, always after
  `ClearOverrideBindings(CuteKeyOwner)`. In combat the apply waits for `PLAYER_REGEN_ENABLED` (no written lockdown rule
  for these calls; Cute 0.6 found none: treat them as protected).
- What this gives: the player's binding file is never written; removing Cute or clearing a row gives J, L and M back
  untouched; the choice is per character like the modules. `SetBinding` plus `SaveBindings` would overwrite the
  player's account or character set and leave M bound to a dead `CUTE_` action after an uninstall.
- `Cute/Bindings.xml` keeps `CUTE_TOGGLE` (now named "Guild window") and `CUTE_SETTINGS`, and gains `CUTE_QUESTS`,
  `CUTE_MAP`, `CUTE_LAYOUT`. Settings and Move frames have no slot in `keys`: their rows in Settings > Keys are
  read-only and say "set in the game's Key Bindings, Cute" with the key the game reports (`GetBindingKey`), "-" for
  none. A window key the player sets there is their own; the window's row then says "also K, from the game's Key
  Bindings".
- Known limits: overrides do not show in the game's Key Bindings window; the micro button's tooltip still says "(L)"
  while Cute holds L, which is wrong (L opens Cute's window) and accepted (the tooltip is the game's); a player with no
  key on the game's map gets "-" in the row.
- Cute's windows are plain frames, not UI panels, so they open and close in a fight. Esc closes them
  (`UISpecialFrames`).
- **The game's windows stay reachable.** Cute hooks none of `ToggleWorldMap`, `ToggleQuestLog`, `ToggleGuildFrame` and
  hides none of their panels (addons may not show or hide panels in a fight, `UIParentPanelManager.lua:852-858`). The
  micro menu, the minimap's zone text and tracker clicks keep opening them. The header buttons:
  - "Guild & Communities" and "Quest log" are `SecureActionButtonTemplate` buttons of type `click` on the game's own
    `GuildMicroButton` and `QuestLogMicroButton` (`SecureTemplates.lua:557`, `MainMenuBarMicroButtons.xml:196, 229`):
    the press runs the game's button as the game, in a fight too. Their attributes are set once, out of combat. Where
    the micro button does not exist (a UI addon removed it) the header button is not shown.
  - "Game's map" calls `OpenWorldMap` and `HideUIPanel`, QuestBank's tested path (`QuestBank/UI.lua:979-994`), out of
    combat; in a fight it is greyed "After combat". Sub-project A puts the same path into `Bridge.lua`'s `UI.OpenMap`.

## 5. The right-click menu

Left-click on Cute's minimap button toggles J; right-click opens the menu; drag moves the button. The same menu opens
from the game's addon compartment (`## AddonCompartmentFunc: Cute_OnCompartment` in `Cute.toc`; the compartment
passes the mouse button, `Mainline/AddonCompartment.lua:81-104`). Tooltip: "Cute. Click: guild. Right-click: menu.
Drag: move."

Built with `MenuUtil.CreateContextMenu` (camelot's own code uses it, `Camelot/FriendsFrame.lua:2191`); a parent with a
submenu opens its own window when clicked (`SetShouldRespondIfSubmenu(true)`, `Menu.lua:742`). An entry for a module
or tab that is off is left out, never greyed. The key in each label is this character's current one.

```
Cute                                 (title)
Guild (J)             > Race, Prog, Hall of Shame, Statistics, Officers*, Me
Quests (L)            > Quests, Route, Dungeons, Gear, ---, [x] Step frame, [x] Direction arrow
Map (M)               > Your zone, the last three zones opened, Finds, ---, Game's map
Settings              > General, Keys, Layout, Modules, Data you share, Columns, Who sees what*, Rules*,
                        Quests, Route, Map, Dungeons and gear, Camp
---
[x] Lock frames       (the on-screen pieces; checkbox)
Move frames...        (greyed in a fight, tooltip "After combat")
---
Reload to apply       (only while module changes are staged)
Set up Cute...        (only before Start)
```

`*` officers only. The game's guild window is not in the menu: a menu entry runs as Cute, and only the secure header
button opens it as the game; "Game's map" is, through QuestBank's tested path (section 4). "Finds" opens M on the
Finds list (section 10). Lock frames and Move frames come with E, the Map entry with F.

Slash words follow the menu: `/cute` toggles J; `/cute quests | route | dungeons | gear | map | finds`; `/cute settings
[section]`; `/cute layout`; `/cute setup`; `/cute keys`; the old `/cute guide` and `/cute journal` open Quests and
Dungeons.

## 6. Layout mode: move, lock, scale, reset

**What it covers: the on-screen pieces only** (decided here: the owner's "lock and move modules etc too on screen";
ElvUI and SUF lock their on-screen frames, not their config windows). Windows always drag by their header and resize
by the game's size grabber (`UI-ChatIM-SizeGrabber-Up`, 386864) in their bottom-right corner; Settings > Layout's
"Reset windows" puts every window back to its default size, centred.

**Ways in:** the menu's "Move frames...", Settings > Layout, `/cute layout`, the `CUTE_LAYOUT` key, and the game's
own Edit Mode: Cute listens to `EventRegistry` "EditMode.Enter" and "EditMode.Exit" (`Shared/EditModeManager.lua:105,
124`; camelot's `MainMenuBarEndCaps.lua:7-11` does the same) and shows and hides its movers with it. Out of combat
only; `PLAYER_REGEN_DISABLED` ends it, saving.

**Movers.** One per piece switched on, shown even when the piece is hidden right now: PANEL at 0.88 alpha (opaque
enough that the piece's text does not show through), 1 px EDGE border, the piece's name at 12 px WHITE and its scale at
11 px DIM, nothing else. A bar at the top centre: "Move frames · [x] Snap · [Reset all] · [Done]"; Esc is Done, and
Done locks.

- Drag moves, snapping to an 8 px grid and to other movers' edges within 6 px; Shift-drag moves freely.
- The wheel scales from 50 to 200 % in steps of 5. The arrow's percent sets `compassSize = clamp(48 * pct / 100, 24,
  128)` (the engine's default 48 and limits, `Core.lua:1292`), so `DialSize` keeps the dial sharp
  (`Arrow.lua:515-527`); its two text lines keep their size.
- The arrow keys nudge the hovered mover by 1 px.
- Right-click: Reset, 80% / 100% / 120% / 150%, Hide or Show (the piece's own switch).

| Piece | Frame | Saved in | Fights |
|---|---|---|---|
| Step frame (with its quest list) | `QuestBankStep` | engine `guide.x/y/scale` | its secure item buttons follow only out of combat (`StepFrame.lua:407-414` already waits) |
| Arrow | `QuestBankArrow` | engine `arrowPos`, `compassSize` | any time |
| Camp bar | `QuestBankCampBar` | engine `remind.pos` | out of combat (secure buttons) |
| Missing buffs | `QuestBankBuffBanner` | new engine `remind.bannerPos` (nil: above the bar, as today) | out of combat |
| Clock, when switched on | the engine's timer strip | engine clock position | any time |

**Saved per character:** `CuteDB.chars[me].layout = { locked = true, snap = true, pieces = { step = { point, x, y,
scale }, ... }, windows = { quests = { point, x, y, w, h }, ... } }`, points against UIParent, `SetUserPlaced(false)` on
every moved frame so the client's layout cache never fights the saved point. Done also writes `CuteDB.layoutDefault`,
the starting layout of a character that has none, so alts look the same without copying; Settings > Layout's "Copy
from..." takes another character's. Bridge copies the character's layout into the engine's settings at
`ADDON_LOADED` before `E:Login` (the order is already right, `Bridge.lua:117-120`) and writes back on every drop.

**With the addon QuestBank loaded** Cute_Quest sleeps and the engine's pieces are QuestBank's: layout mode shows no
mover for them, and QuestBank's own drag and lock rules apply (the dormant rule holds: Cute writes none of QuestBank's
settings). Layout mode then has nothing to move and its menu entry and Settings rows are greyed with "QuestBank is
loaded".

**Lock.** One lock for all the pieces: locked, nothing on screen moves; clicks still pass. Unlocked, each piece drags
where it stands. Default: locked, from the first login on sub-project E (until then the pieces drag as in 0.7). Layout
mode moves everything whatever the lock. The 0.10 changelog line: "Lock frames now locks the step frame, arrow, camp
bar and banner; windows move by their header."

**QuestBank side** (its players see no change): `QB.Movers = { step, arrow, camp, buffs, clock }`, each
`{ frame, name, get, set, secure }`; `QB.Locked(key)`, a hook like `QB.Skin` that returns QuestBank's own lock where no
host sets it; a lock check in the arrow's `OnDragStart` (`Arrow.lua:577`, which drags unconditionally today) and the
camp bar's move start; `remind.bannerPos`; the step frame's existing lock read through `QB.Locked("step")`.

**Default places, no overlaps.** 0.7 puts the step frame (TOP 0,-140, 260x96) and the arrow (TOP 0,-170, 232x98)
on top of each other. Now (sub-project D; only for pieces the player never moved) the step frame takes the hidden
tracker's top right corner (read from `ObjectiveTrackerFrame`, which 6.1.1 keeps shown at alpha 0; 8 px left of it
while the tracker is kept); the arrow goes to TOP (0,-96); the camp bar and banner keep the engine's defaults. Windows
open centred, and Settings opens beside the window whose cog opened it where the screen has room.

**The minimap** is the game's Edit Mode's to place. Under Cute the engine's Alt-drag of `MinimapCluster`
(`Minimap.lua:1106-1124`) is off through `QB.Locked("minimap")`, and Bridge clears the engine's kept minimap place
once. QuestBank alone also re-applies its kept place on "EditMode.Exit" (today only on `PLAYER_ENTERING_WORLD` and
`EDIT_MODE_LAYOUTS_UPDATED`, `Minimap.lua:1175-1187`, so an Edit Mode session snaps it back). Cute's frames are never
registered as Edit Mode systems: `RegisterSystemFrame` is a plain insert walked with `secureexecuterange`
(`EditModeManager.lua:95, 113, 220-231`), and an addon frame there taints Edit Mode with no system id to save under.

## 7. Settings: one window, nothing cut off

`CuteSettingsFrame`: 800 x 560 by default, resizable from 760 x 420 to 1100 x 800. A 30 px header (section 9), then
a section list of 168 px on the left and the column on the right, `min(560, room)` wide.

**Drawing rules** (sub-project A fixes the first four in today's layout; C builds the window):

- A Choice measures each option (`GetUnboundedStringWidth`, as `UI:Tab` does): a cell is 14 px circle + 6 + text +
  12. The label column is 120 px; the options wrap to a second line under it when the row overflows.
- Labels and notes wrap (`SetWordWrap(true)`, height measured): a row grows from 22 px to as many lines as it needs;
  `FitText` is never used on a Settings label or note. Labels 13 px INK; notes 12 px DIM under their row.
- Rows are 22 px (today 20). The section list never shrinks its rows (today down to 16 px). Its three group heads are
  20 px (11 px DIM) and its 13 sections 22 px: 16 + 60 + 286 = 362 px, which fits the 375 px the list has at 420 px
  tall; past that it scrolls with the 10 px thumb the other lists use.
- No section icons: the open section has a 2 px bar in its category colour (QUEST for the quest sections, GROUP for
  Dungeons and gear, NEW for Data you share, WHITE otherwise).
- A check row with words on its right gives them 176 px and the label the rest, wrapping. A stepper row gives the
  label the rest of the width, wrapping, and the stepper 74 px (20 px buttons).
- One column everywhere; the long lists (Columns, Who sees what) take two columns at 1040 px wide and more.
- Each section holds 3 to 8 rows; the officers' lists and Columns are lists by nature.

**Sections.** The list has three DIM group heads; each window's cog opens its group's first section (J: General, L:
Quests, M: Map). The table is Settings once every sub-project has shipped; a row whose sub-project has not is not drawn
(the Layout section and the Move frames key come with E, Finds on the map with F, Share finds with the guild and the
Data you share line with G).

| Group | Section | Rows |
|---|---|---|
| Cute | General (6) | Show offline members; Minimap button; Compact rows; Main character [Edit]; Role: Tank / Heal / Melee / Ranged; Raid spec set (this character) |
| | Keys (5 and a note) | Guild window [J] [x] Follow the game's Guild & Communities key [Clear]; Quests window [L] [x] Follow the game's Quest log key [Clear]; Map window [M] [x] Follow the game's World map key [Clear]; Settings and Move frames read-only, "set in the game's Key Bindings, Cute". Note: "Cleared, the game's own key opens the game's window again." |
| | Layout (3 and a button row) | Lock frames (note: "The step frame, the arrow, the camp bar and the banner. Windows always move by their header."); Snap to the grid; [Move frames] [Reset all] [Reset windows] [Copy from...] |
| | Modules (6, a note, and the band line while staged) | Guild (always, greyed); Quests and Route (always, greyed); Dungeons tab, Gear tab (indented); Map; Camp. Note: "Window and tab changes apply on reload." |
| | Data you share (a line, 4 rows, a note) | Line: "14 finds QuestBank does not have yet · 3 confirmed by the guild [Show finds]" (G). Note what the game shows for foreverrank.com (`noteGame`); Learn quests from the game (`survey`); Share your quests with your party (`share.party`); Share finds with the guild (G; note "A guild mate's find changes your route once two of you agree."). Note: "The QuestBank Uploader sends what you found in the world to foreverrank.com, never a name or anything about your guild. It comes with Cute on Cute's page at foreverrank.com." |
| Guild | Columns (list) | Race, Prog, Hall of Shame, Officers columns (today's four core sections, under heads) |
| | Who sees what (list, officers) | unchanged, plus Finds under Discovered (section 11.4) |
| | Rules (list, officers) | unchanged, plus the Guide's two moved here under "Dungeons and gear": Members near your level, Dungeons ahead; [Broadcast now] [Rules to defaults] |
| Quests | Quests (7) | Step frame; Quests under the step: 0 to 10 (default 3); Backdrop behind the step frame (off); Direction arrow; Hide the game's quest tracker (`guide.hideTracker`, shipped, on; greyed while the step frame is off); Accept for me: Off / On my route / Worth taking; Hand finished quests in for me; Progress in mob tooltips |
| | Route (7) | Follow: The plan / Ready now; Show the way step by step on the arrow; The hearthstone may be a step; Route on the minimap; Show the whole route (`wholeRoute`, shipped, off; note "Off, one stroke: from you to where the arrow leads."); A ! on the minimap for quests you can take (`minimapGivers`); Minimap far view (`mmExtended`) |
| | Map (3) | Show low-level quests (`mapLowLevel`, shipped, off; note "Quests the game calls trivial. Their level number's colour says how low."); Finds on the map (F); Our icons on the game's map (on) |
| | Dungeons and gear (2) | Journal shows: [x] Bosses [x] Rares [ ] Trash [x] Chests and events (one wrapping row); Gear: quests up to 2 levels ahead |
| | Camp (6) | Camp bar; Missing buffs when you leave town; Sleeping bag; Sellers of camp goods; Interact light; Light style: Sparkle / Light / Game's |

`share.guild` has no row: Cute forces it off (section 11.5). The minimap's ! and far view moved from Map to Route
(they belong to the base, not to the Map window, so a player who keeps the game's map keeps them). There is no icon
size row: the game's size only (section 10).

## 8. The visual system

**One channel, one meaning.** Every row and card has five channels, each carrying one kind of meaning:

1. The **icon** (game art) says what kind of thing it is.
2. The **2 px left bar** says its category.
3. **Text colour** gives hierarchy (WHITE, INK, DIM, MUTE). The only exceptions are the names the game itself colours:
   class names, item names by quality, a quest's level number (and a read quest's title) by difficulty.
4. The **right-hand value or word** gives status (GOOD, WARN, BAD, NEW): "ready", "new", "done". A status colour is
   never on a name or a line of text; it is the right-hand word or a segment of a bar.
5. The **background** gives state: white at 0.06 for open, target or you, 0.035 for a group head, +0.05 additive on
   hover.

The look stays black and white; colour appears only where it means something. No drawn marks: no coloured squares,
chips or dots; a category is a bar, a status a word.

**Palette.** Contrast on black and on PANEL2, the lightest surface.

| Token | Hex | Contrast | Use |
|---|---|---|---|
| BG / PANEL / PANEL2 / LINE | #090909 / #121212 / #1C1C1C / #333333 | | surfaces (`Cute/UI.lua:33-45`, kept) |
| EDGE | #6B6B6B | 3.2:1 | boxes, movers, the route's rail |
| WHITE | #F5F5F5 | 19.2 / 15.6 | the step now, a card's name, the target |
| INK | #DBDBDB | 15.2 / 12.3 | reading text |
| DIM | #949494 | 6.9 / 5.6 | meta, Settings notes |
| MUTE | #858585 | 5.7 / 4.6 | off, disabled, footers only (it looks like DIM, so never a second level) |
| GOOD | #73D478 | 11.4 / 9.2 | status only: ready, done; a route's XP gain as bar segments |
| WARN | #EDBD59 | 12.0 / 9.7 | needs attention, only beside the alert icon |
| BAD | #E05C54 | 5.8 / 4.7 | blocked |
| NEW (new) | #78B0FF | 9.5 / 7.7 | status "new": seen in play, not in QuestBank's data yet; and the Finds category's bar |
| QUEST (new) | #FFD100 | 14.4 / 11.7 | category: questing (the game's quest gold); bars and progress bars only, never text |
| GROUP (new) | #4FD1C4 | 11.3 / 9.1 | category: dungeons and raids (teal: no game colour set uses it); bars only |

QUEST gold and WARN are 1.2:1 apart, so they never share a channel; QUEST gold is never text, so it never meets the
difficulty yellow of a level number. Travel has no colour (its icon carries it); gear has no category bar (LINE) and
takes the item's quality colour on its icon's edge and its name only; a "Train at" step takes your class colour. Game
colour sets as the game uses them: QuestDifficultyColors (`Blizzard_FrameXMLBase/Constants.lua:195`) on level numbers
only, which therefore never sit on PANEL2 (impossible red is 4.39 there); item quality as the exact game colour on an
icon's 1 px edge, and for names lifted to keep the hue at 4.5:1 (rare #4094ED, epic #BA69F2); class colours for member
names and member bars. The web page's `--cu-dim` and `--cu-mute` take DIM's and MUTE's values.

**Type.** ARIALN (from `NumberFontNormal`), flat. Over art or the world: a 1 px shadow, and on the on-screen pieces
(no backdrop) the font's OUTLINE flag as well, which the mockup's bright-ground view shows is needed.

| Size | Colour | Use |
|---|---|---|
| 15 | WHITE | the step now; a card's name; a window's title |
| 13 | INK | reading rows: quest names, route stops, Settings labels |
| 12 | INK / DIM | tables, values, tabs, buttons; Settings notes in DIM |
| 11 | DIM | meta: who, objectives line, clock; footers in MUTE |
| 10 | WHITE, outlined | numbers on icons and pins only (counts as a corner badge) |

**Icons.** All game art, drawn through QuestBank's `QB.Art` pattern (the atlas when `C_Texture.GetAtlasInfo` has it,
else the file id), so a missing atlas still draws. `build.py` checks every file id Cute's own files name against the
client manifest (`research/wago/1.60.1.70338/ManifestInterfaceData.csv`; every id below is in it).

| Thing | Icon |
|---|---|
| Quest you can take / repeatable | `QuestNormal` / `UI-QuestPoiRecurring-QuestBang` |
| Quest in your log / ready to hand in | the game's quest POI, as `Pins.lua` `P.StylePoi` draws it: the `UI-QuestPoi-QuestNumber` disc (file 334391) with `Quest-In-Progress-Icon-yellow` (in progress) or `UI-QuestIcon-TurnIn-Normal` (ready) on it; below 18 px the ready one is the bare hand-in glyph |
| Objective kind | the cursor atlases (`Crosshair_Attack_32` 131013, `Crosshair_LootAll_32` 131023, `Crosshair_Interact_32` 131021 and the rest, `QuestMap.lua:46-54`, `QM.PaintKind`) |
| Travel | `D.TEX`: hearth 134414, gryphon 132239, wyvern 132268, boat 1686581, zeppelin 1519491, tram 132996, portal 135741, on foot 132307, mount 132261, the `FlightPath` atlas |
| Train / your corpse | your class icon / `UI-TargetingFrame-Skull` 137025 |
| Dungeon, raid / zone | `Dungeon`, `Raid` atlases or the place's LFG icon (`cat.icon`) / the zone's icon (`cat.zi`) |
| You on a map | the game's player arrow (`UI-WorldMapArrow`; file `WorldMapArrow` 803894) |
| A quest's area on a map | the game's quest blob (`UI-QuestBlob-Inside` 334387, `UI-QuestBlob-Outside` 334388, as `QuestBlobDataProvider` fills it) |
| A find on a map / a rare | the item's or creature's icon, round, in the minimap button ring (`MiniMap-TrackingBorder` 136430, QuestBank's `D.TEX.ring`) / plus `nameplates-icon-elite-silver` at its corner, as the nameplate draws a rare |
| Guild master / officer rank / Only-you value | `UI-Group-LeaderIcon` 132062 / `UI-GROUP-ASSISTANTICON` 132061 / `UI-ChatFrame-LockIcon` 130944 |
| Warning / blocked / ready / waiting | `UI-Dialog-Icon-AlertNew` 357854 / `ReadyCheck-NotReady` 136813 / `ReadyCheck-Ready` 136814 / `ReadyCheck-Waiting` 136815 |
| Header controls | settings: the `QuestLog-icon-setting` atlas (file `UI-OptionsButton` 851903) in a 20 px box; close: `UI-Panel-MinimizeButton-Up` 130832, desaturated, 20 px; resize: `UI-ChatIM-SizeGrabber-Up` 386864 |
| An item not loaded yet | 134400 |

Sizes: 16 in a 20 px row, 20 in a two-line row, 12 for an inline objective glyph, 24 for the step now and a route node,
14 for the next steps, 20 round for a boss face, 22 for a map pin (the game's offer pin). Item icons are 16 / 20 / 28 /
36 (row, card, reward, gear slot), cropped to texcoords 0.08-0.92, with a 1 px edge in the quality colour (black for
poor and common) and, for an upgrade, the bags' green arrow at 10 px as QuestBank's `upgradeMark` draws it.

**Art QuestBank already has.** Dungeon cover: the Encounter Journal's `UI-EJ-DUNGEONBUTTON-*` (180 in the client),
else `UI-LFG-BACKGROUND-*` (`cat.bg`), else a camelot loading screen's middle band (QuestBank's `setCover`). The EJ art
is 174 x 96 inside a 256 x 128 file and the EJ draws it at texcoords 0-0.684 by 0-0.742
(`Blizzard_EncounterJournal.xml:320-328`); `setCover` (`DungeonMap.lua:554`) uses the whole file, so sub-project D
crops it as the EJ does (checked in game: no empty strip on the right) and never scales it past 1.5x. Boss faces:
`UI-EJ-BOSS-*` through `DM.Face`, masked round (the Deadmines' seven are in the client: 5875505-5875509, 5875511,
5875512); a boss without EJ art gets its creature portrait (`SetPortraitTextureFromCreatureDisplayID`,
`UnitDocumentation.lua:584`, round), never a "?" disc. Zone pictures:
`cat.img` (`answer-warboard-classic-*`, 46 in the client, 256 x 128: the place row shows its middle). Items:
`C_Item.GetItemIconByID` with `GetItemQualityByID`.

**Three patterns.** L's lists: the questing column is about 600 px wide at 1040 and the full 716 px at 760 (one
column); the Map list is 320 px.

*A. List row* (Quests tab, Map list, finds, the gear row). Compact 20 px, two-line 34 px, place 40 px.

- x 0: the 2 px category bar. x 8: the icon slot (16, or 20 in two-line).
- A quest: x 28-50 its level, 12 px, right-aligned, in its difficulty colour ("23+" for elite); x 56 its name, 13 px
  INK (WHITE on the 0.06 background when it is the arrow's target). From the right edge in: who, 112 px, 11 px DIM
  (minutes away or nothing; "ready" in GOOD; "new" in NEW for found data; never "here"); value, 64 px, 12 px INK
  ("1,250"); the reward's item icon, 16 px. Line 2 (y 19, x 56, 11 px DIM): the objectives inline, each a 12 px cursor
  glyph and "Kobold Vermin 3/8", 12 px apart; a finished one gets `ReadyCheck-Ready` and MUTE text; for a quest not
  taken, "from Marshal McBride · Northshire Abbey"; for one ready, "to Verner Osgood · Lakeshire". A trivial quest's
  icon is desaturated, and the row shows only with "Show low-level quests" on.
- Names and line 2 ellipsize in any list ("..."), with the full text in the row's tooltip; Settings and the card never
  clip.
- A place: a 64 x 40 picture (`cat.img`, its middle band) at x 4, else the zone icon at 20 px; name 13 px WHITE at x 76;
  line 2 "5 quests · 12 min away" in DIM ("you are here" for your zone); on the right the XP at 12 px INK over "310 XP a
  minute" at 11 px DIM. An open place shows its first five quests by XP a minute, then one DIM row, "9 more in Redridge
  Mountains" (a click shows them all).
- A find: the item's or creature's icon at 20 px, round; the name; line 2 its kind and how ("Chest · looted"), and who
  on the right ("you", "3 guild mates", "Hesk, first · confirmed", "players' games", "guides"); the right-hand word
  "new" in NEW while QuestBank's data lacks it; bar NEW.
- The gear row: the item icon at 20 px with its edge and upgrade arrow; the name in its lifted quality colour; line 2
  the source ("from Kobold Camp Cleanup · Marshal McBride", "from Mr. Smite · The Deadmines"); on the right "+9 item
  level" in INK (the upgrade arrow says it is an upgrade); bar LINE.
- In a list 320 px wide or less (the Map list) the who column goes and the value takes 56 px.
- **A quest row, everywhere:** click reads it (the list gives way to the quest to read, section 9; Back returns to the
  list where it was), Ctrl-click shows it on the arrow, Shift-click puts it on (or takes it off) the pick-up list,
  right-click is its menu, the tooltip is the engine's quest tooltip.

*B. Route stop* (Route tab; the step frame). 40 px plus 18 per quest.

- A 2 px EDGE rail at x 14 joins the stops. The stop's node, 24 px, sits on the rail at y 20: the hand-in POI, the
  offer, the objective's cursor atlas, the `FlightPath` atlas or the hearth (atlases with no square corners).
- The target stop has QuestBank's `ring_frame.png` (30 px) behind its node and the 0.06 background.
- Line 1 (y 4, x 34, 11 px DIM): "+4 min · 420 yd". A travel icon (14 px) and its words ("flight to Darkshire, 2 min")
  in INK only where the way changes from walking (boat, flight, portal, hearth, a mount's first stop); walking has none.
- Line 2 (y 18): the stop's name, 13 px WHITE for the target and INK otherwise; on the right "+4,250 XP" at 12 px INK
  and the level after it, "21.7", at 11 px DIM.
- Quest lines (18 px, x 34): a 14 px quest or objective glyph, the name at 12 px INK, its progress at 11 px DIM, its XP
  at 11 px DIM on the right ("take" for a pick-up); a handed-in quest has `ReadyCheck-Ready` and "done" in GOOD on the
  right.
- The level-up: where the route's XP crosses a level, a 1 px WHITE rule across the list after that stop with "Level
  22" at 11 px WHITE on it.

*C. Dungeon card* (the Quests tab's Dungeon section, 380 px; the Dungeons tab's head, full width). 1 px black border,
PANEL2 fill, 2 px GROUP bar; 98 px tall at full width, 126 px in the 380 px column.

- The art at its native 174 x 96 on the left; nothing written over it but the `Dungeon` or `Raid` atlas at 20 px, top
  right.
- From x 182: y 6 the name at 15 px WHITE and right after it the pick's reason in one DIM phrase ("3 mates online");
  y 28 "18" at 11 px INK, a 4 px track (160 px, 112 px in the column) with the range drawn in its difficulty colour
  against your level (a mark, not text, so PANEL2 is fine) and a 2 x 10 WHITE tick at your level, then "23"; y 46 the
  boss faces, 20 px round, 3 px apart (killed in full colour with a 10 px `ReadyCheck-Ready`, not killed desaturated at
  0.7 alpha, doubted a MUTE ring only) and right after them "4 left" at 11 px DIM.
- The foot (at y 72 from x 182 at full width; at y 100 across the card from x 8 in the column): `QuestNormal` at 14 px
  and "5 quests", the best drop for you as a 20 px item icon, up to four mates in class colour at 11 px, and an Invite
  button (58 x 16) on the right.
- The Invite rules are 0.7's (`C_PartyInfo.InviteUnit`, never in a fight, greyed where `CanInvite` says no).

**Found data.** Anything seen in play that QuestBank's data lacks (Discover's and Survey's notes, finds) has "new" in
NEW as its right-hand word; on a map its pin is unchanged with a tooltip line, "Seen in play by you" or "by 3 guild
mates". Classic-only data stays DIM and its tooltip says it may have moved.

## 9. The windows in detail

**Every window's header**, 30 px: the round 24 px logo, the title at 15 px WHITE, then on the right the game's window
button (a 20 px text button), the cog (20 px box) and the close (20 px). The header drags the window (always: section
6); there is no lock in a header. Tabs sit in a 26 px row under it. The footer is 24 px. Sizes: J and L 1040 x 640 by
default, resizable down to 760 x 420; M 1120 x 640, down to 860 x 500; Settings 800 x 560, down to 760 x 420; the
size grabber sits in the bottom-right corner of all four.

### J: Guild

Today's pages, unchanged in substance: Race, Prog, Hall of Shame, Statistics, Officers (officers only), Me.

- Header: logo, "Guild", then "Guild & Communities" (the secure click, section 4), the cog, the close. Footer:
  "Updated N min ago", as today.
- New marks: the guild master's and officer ranks' icons (12 px) before the class-coloured name on Race and Officers;
  for officers, an Only-you value in MUTE with the chat lock icon at 10 px (members see what they see today). You are
  marked by the 0.06 background, never a white bar (white is the Priest's class colour). The XP column is a 40 px
  track bar (3 px) and the percent.
- Statistics gains a Finds category (sub-project G): Finds first, Books read, Rares seen, Chests looted, with You and
  Leader as the other categories have them, under the Finds category's routing (11.4).
- Not in a guild: one line, "Not in a guild.", and the game's button.
- Not shown: no Guide and no Settings tab any more; no guild chat, member notes, rank edits or guild invites (those are
  the game's window, one click away).

### L: Quests

Header: "Quests", the tabs that are on, then "Quest log" (the secure click), the cog, the close.

**Footer** (sub-project G), only while there is something to say: a button, 2 px NEW bar, a book's item icon at 14 px,
"14 new finds · 3 confirmed by the guild" in DIM with the numbers in INK. "New finds" are the finds this character
noted that the running `Data.lua` lacks (they stop counting when a release or the uploader's data file carries them,
11.3); "confirmed" are those of them a guild mate's find agrees with. A click opens M on the Finds list (section 10).
Its tooltip is the privacy sentence of section 11.5. The Map window has the same footer.

**The quest to read** (a shared view, `Cute_Quest/Reader.lua`, used by L's lists and M's list). A quest row's click
replaces the list with it, Back on top returns to the list at its scroll. It holds: the title in its level's colour;
"Level 20 · 1,550 XP at level 21"; for a quest in your log the game's text (`GetQuestLogQuestText(questLogIndex)`, as
`Mainline/QuestMapFrame.lua:40` reads it), otherwise what the catalog knows (`D.REQ` objectives, `D.TIPS`); its
objectives with progress and cursor glyphs; the chain from `D.PRE` and `D.NEXT`; its rewards as 28 px item icons; the
hand-in (or the giver); and its buttons: **Show on arrow**, **Share** (shown while in a group and
`C_QuestLog.IsPushableQuest(questID)`; `QuestLogPushQuest(questLogIndex)`, as `QuestUtils.lua:358` does) and
**Abandon** (QuestBank's `UI.ConfirmAbandon`, `Lists.lua:442`, the game's own confirmation). A quest not taken has
Show on arrow and Pick-up list instead. Never `QuestMapFrame_OpenToQuestDetails`, which opens the game's panel
(`OpenQuestLog`, `ShowUIPanel`).

**Quests tab** (the Guide, rebuilt; always there)

The band, in view while the list scrolls:

| Row | Content |
|---|---|
| step now | 24 px icon by the step's kind (`QuestNormal` to accept, the cursor atlas for an objective, the hand-in, the travel icon, your class icon to train, the skull for your corpse), the step's text at 15 px WHITE (`G.Text`), the quest's name after it at 11 px DIM when the text does not carry it, the count on the right at 13 px INK ("3/5"); a 2 px progress bar under it in the category colour. Click: read its quest; Ctrl-click: show it on the arrow; right-click: the step's menu (Not now, Drop) |
| next two | 14 px icon and the text at 12 px DIM, short ("Hand in A Baying of Gnolls": the list names the NPC) |
| level | a 6 px XP bar (track #292929, your XP WHITE, what the planned quests add GOOD, a 1 px tick at each level) under "Level 21 · 63% · about 42 min to level 22" at 12 px INK (`G.TimeToLevel`) |

Before the engine has read the log: one line, "Reading your quest log." With nothing worth taking in reach, the step
now is the engine's grind step ("Kill around Brightwood Grove until level 23, then Darkshire").

Under the band, two columns at 1000 px wide and more (one column below, the right column's sections after the left's):

| Column | Section | Rows |
|---|---|---|
| left (rest of the width) | Questing (QUEST bar, `QuestNormal`), right: "3 places" | the three places worth your time as place rows (pattern A), in the engine's XP-per-minute order (`UI.PlaceGroups`); your zone open with its first five quests, the others folded; then "Other places (12)", folded; then "Best XP anywhere", folded (the engine's `Candidates(8)`) |
| right (396 px) | Dungeon (GROUP bar, `Dungeon`), only with the Dungeons tab on | the guild's pick as a dungeon card (pattern C, `Cute.Guide.Pick`), so its art shows on first open; a click opens the Dungeons tab on it. Officers find the guild's line ("Most members are 18-23: The Deadmines") in its tooltip. With no pick, the pick's own sentence ("No dungeon known for level 14 yet; The Deadmines opens at 18.") as one DIM row |
| | Gear (LINE bar, the slot's item icon), only with the Gear tab on | one gear row: the best upgrade within reach and its source; a click opens the Gear tab on its slot. None: no row and no head |
| | Party (LINE bar), only while grouped | up to four members: class-coloured bar and name at 12 px, their step at 12 px DIM (`G.MemberSteps`) |

Not shown: every other dungeon, the pace strip, Next up, missing enchants, counts per level band, quest ids.

**Route tab** (module `route`, always there)

- Band: "Level 21.6 to 22.1 · 11,300 XP · 43 min" at 12 px INK over the 6 px XP bar: your XP WHITE, then each stop's
  gain as its own GOOD segment (1 px apart, in route order), a tick at each level; on the right "Start run" / "End run"
  (`QB.Run.Start`, `QB.Run.Stop`).
- Left, 340 px: the route's map, M's canvas at a fixed zoom framing the stops (340 x 226): the stops' nodes as pins at
  the game's size, merged with a count where they touch (Lakeshire's five hand-ins are one pin with "5"), the one
  stroke from you to the target, you as the game's arrow. Hovering a stop lights its pin. Under it, "Open in the map"
  (opens M). Without the Map module the map is still drawn (it is QuestBank's canvas, built with the tab).
- Right: the stops of `QB.Target.Route()` as a timeline (pattern B), with the level-up rule. The first is the one
  target. A stop's click shows it on the arrow; a quest line's click reads the quest.
- None: one DIM row, "Nothing on the route yet: take a quest from Quests."
- Not shown: gold per stop, NPC ids, the flight paths known, a second route line.

**Dungeons tab** (module `journal`, titled Dungeons)

- At the top the guild's pick as a dungeon card at full width, then the engine's Journal (`DungeonMap.lua`,
  `DM.Attach`) on its host as 0.7 draws it (468 px, the cover and floor art kept), opened on the pick. Its list tiles
  carry the level range on a 70 % black plate under the name (so red and orange ranges read on dark art), and the open
  tile a full 1 px WHITE border.
- Not shown: the other dungeons as cards, the guild per dungeon (officers have it in the card's tooltip).

**Gear tab** (module `gear`)

- The engine's Gear page (`Gear.lua`, `G.Attach`) on its host, 440 px, as 0.7. New through `QB.Skin`: item icons
  with the quality edge and the upgrade arrow, names in the lifted quality colours (a new `QB.Skin.Quality(q)`;
  QuestBank sets no skin and looks as before). A source glyph is the quest's as the map draws it (a quest in your log:
  the in-progress POI, never the offer's "!").

### On screen: the step frame, in place of the game's tracker

The owner's "if they use ours" is read as the step frame: it takes over the objective tracker's job, so the game's is
hidden by default (shipped in 6.1.1).

- The step frame becomes a route stop (pattern B) with **no backdrop** by default ("Backdrop behind the step frame" in
  Settings brings Cute's flat one back): the 24 px icon, the step's text at 15 px WHITE and its quest's name at 11 px
  INK under it, the count on the right, a 2 px progress bar in the category colour, the next two steps at 14 px icon
  and 12 px INK. All its text is outlined and shadowed (section 8); its 11 px lines are INK, not DIM, because it stands
  on the world.
- Under it, the quests you hold that the step and the next two do not already name, the route's first, up to "Quests
  under the step" (default 3, 0 hides the list): per quest, the level number in its difficulty colour, the name at
  12 px INK, "ready" in GOOD on the right for a finished one; its open objectives inline at 11 px INK with their glyphs
  (finished ones dropped); a quest with a usable item has a 20 px secure item button at its left
  (`SecureActionButtonTemplate`, type item, set out of combat as `StepFrame.lua:149-176` does). "+4 more quests" when
  the log holds more; a click opens L. No XP bar (L's band and the game's own bar show XP).
- Clicks: the step as in the band; a quest's row shows its next spot on the arrow; right-click is its menu.
- In a fight the text updates, the order and the item buttons wait for its end (secure buttons cannot be re-anchored
  in one).
- This is QuestBank's `StepFrame.lua` with a new setting, `guide.quests` (QuestBank's default 0: its players see no
  change; Cute's first run sets 3), and the backdrop through `QB.Skin`.
- The missing-buffs banner loses its box as well: "Missing buffs" at 12 px WHITE outlined, then the buffs' icons at
  22 px; right-click hides it for ten minutes (its tooltip says so); no close glyph.

**Hiding the game's objective tracker: what D adds to 6.1.1.** 6.1.1 ships `SF.Tracker` (alpha 0, a `SetAlpha` hook,
never in a fight, `guide.hideTracker` on, the Quests row in QuestBank and Cute). What it leaves: out of sight, the
tracker's lines still take a click where they stand (its own note, `StepFrame.lua:425`), under the step frame's new
default place. D adds, inside `SF.Tracker` and nowhere else:

- `ObjectiveTrackerFrame:SetScale(0.01)` beside the alpha, the scale it had kept for the session and put back with the
  alpha when the row or the step frame goes off. The scale is a C-side property that writes nothing into the frame's
  tables; the container reacts to `OnSizeChanged`, `OnShow` (`ObjectiveTrackerContainer.lua:29-37`) and the managed
  frame's `OnHide` (`ManagedFrameSystem.lua:21-23`), none of which a scale change in the frame's own units fires. The
  frame stays shown, so the game's logic, its item buttons and `autoQuestWatch` are untouched. Not the watches
  (QuestBank 3.6.0's `QuestMap.lua:911-917`: a watch call from addon code marks the tracker dirty as the addon) and not
  `Hide()` (the tracker shows itself again, `ObjectiveTrackerContainer.lua:117-126`).
- On "EditMode.Enter" alpha and scale go back so the player can place it; on "EditMode.Exit" and
  `EDIT_MODE_LAYOUTS_UPDATED` they are set again.
- The harness asserts that `SF.Tracker` calls nothing else on the tracker; the play test reads the taint log through a
  dungeon boss fight and a quest item used from the step frame (section 14), confirms no `OnSizeChanged` fired, and
  that the boss frames stand where they stand. If the taint log names QuestBank, the scale step is dropped (6.1.1's
  alpha stays) until a clean way is found.
- No new file, no card row, no "What's new" line: the setting and its default already shipped.

## 10. The Map module (M)

`CuteMapFrame`: 1120 x 640 by default, resizable from 860 x 500. The canvas on the left, our list on the right (320 px,
260 px at the minimum). Not a UI panel: it opens in a fight.

**The canvas.** QuestBank's `MapPage.lua` canvas on a Cute host: `Mixin(MapCanvasMixin, ...)` with
`MapCanvasFrameScrollContainerTemplate` (`MapPage.lua:473-500`), its `OnUpdate`, `OnShow` and `OnMapChanged`
overridden without the game's shared-cache clearing (`MapPage.lua:83-106`), Blizzard's data providers and QuestBank's
layers. The providers: MapPage's five (exploration, highlight, area labels, your group, the quests' blue areas,
`MapPage.lua:46-47`) and four more so M does what the game's map does for a player on the move: your corpse
(`DeathMapDataProviderMixin`), area points of interest (`AreaPOIDataProviderMixin`), map links (`MapLinkDataProviderMixin`:
the doors and portals between maps) and graveyards while dead (`SelectableGraveyardDataProviderMixin`)
(`Blizzard_WorldMap.lua:213, 229-231`), each checked for taint the way MapPage checked its five (sub-project F's harness
and the play test's taint log). Bridge stops forcing `mapPage = false`; the Map module sets it on, and Bridge's tab 8
maps to `"map"`. The canvas and its pins are built at login out of combat, as MapPage does, so the first M in a fight
finds it ready; a reload in a fight shows "The map is ready after combat." until it ends. Never embedded in
`WorldMapFrame`, never writing into its tables (its action button casts a spell from Blizzard's Lua).

**Moving around** (what the owner asked: "scroll cleanly inside that map also through zones and drag"):

- The wheel zooms smoothly (`SetMouseWheelZoomMode(MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_SMOOTH)`,
  `MapCanvas_ScrollContainerMixin.lua:3`).
- The wheel out at the minimum zoom goes up to the parent map (`NavigateToParentMap`); the wheel in at the minimum zoom
  over a child zone goes into it (`C_Map.GetMapInfoAtPosition`, then `SetMapID`, as `FindBestLocationForClick` does,
  lines 66-91) and keeps zooming. That is how you move through zones.
- Drag pans when zoomed in (the game's rule) and stops at the zone's edge, as the game's map does. Decided here:
  crossing into the neighbour is the continent map's job (wheel out once, drag across, wheel in), which keeps a zone's
  pins and list whole; F's harness confirms QuestBank's quest pins and finds draw on the continent map (QM.ZoneQuests
  per child zone), and F adds them there if MapPage lacks them.
- Left click at the minimum zoom enters the zone under it; right click goes up a map (both the game's); Ctrl-click
  shows that spot on QuestBank's arrow ("Showing ..."). On Cute's host the right click is the game's, an option of the
  canvas's host; QuestBank's own Map page keeps its menu (`MP.MapMenu`), whose entries Cute has in the header.

**Header:** the crumbs (World, Eastern Kingdoms, Redridge Mountains; a map without art greyed), Here (your zone), the
layer switches with their game icons and counts as MapPage has them (`MapPage.lua:52-60`: Ready to hand in, In your
log, To pick up, Route, Dungeons, Flight paths) and one more, Finds (a book's item icon); a layer with nothing on this
map is not drawn. Then "Game's map" (its tooltip Cute's own: MapPage's `MP.KEYS` text, which says M is always the
game's, is not shown), the cog, the close. The layers are on by default and kept in the engine's settings (`mapTurn`,
`mapObj`, `mapGive`, `mapRoute`, `mapDungeons`, `mapFlights`, and the new `mapFinds`).

**Pins.** Every quest pin at the game's size: the offer's `QuestNormal` at 22 px, the quest POI (disc and glyph, 20 px
frame as the game's `QuestPinTemplate`) for a quest in your log or ready, the target as the super-tracked pin, the
flight master's atlas, all times the canvas's pin scale (`P.PinScale`) with the zoom limits the game sets (offers 1 /
1.0 / 1.2, POIs 1 / 1 / 1). The quests' areas are the game's soft blue blob, no outline of ours. Clutter is cut by
showing fewer, never smaller:

- pins that would touch at the current zoom (closer than a pin's width on screen) merge into one pin with a count;
  zoom in and they part. A merged pin is one glyph (the hand-in's if any of them is ready, else the in-progress POI,
  else the offer) with the count as a 10 px WHITE outlined badge on its bottom-right corner, never two glyphs side by
  side. On the minimap, where there is no zoom to part them, givers within 30 yards merge (6.0's rule);
- trivial quests show only with "Show low-level quests" on (`mapLowLevel`, shipped in 6.1.1, the engine's single
  truth for Cute's map, the game's map layer and the minimap); then the level number's colour says how low. Decided
  here: Cute never writes the game's own Interface option (Camelot's "Show trivial quests",
  `PROXY_TRIVIAL_QUEST_FILTERING`, `Camelot/InterfaceOverrides.lua:18-29`, default off), but Cute's first run
  (`cuteDefaults = 2`) starts `mapLowLevel` from it (`not C_Minimap.IsFilteredOut(Enum.MinimapTrackingFilter.
  TrivialQuests)`, as that file reads it), so a player who asked the game for grey quests sees them in ours too;
- one route line at a time: only the stroke to the one target (shipped, `wholeRoute` off);
- on the game's own map (the row "Our icons on the game's map", on) no pin where the game already draws one for that
  quest. That layer is where the owner saw the scuffed icons in 0.7, so the size reaches it first (sub-project C) and
  the thinning next (D).

Decided here: the icon size is the game's, with no size row. QuestBank 5.4.4 halved it at the owner's "massive, can be
halved"; the scuffed look is that half-size art drawn soft beside the game's full-size pins, and three quarters would
be soft the same way. Cute's first run sets `mapIconPct = 100` (a second pass of Bridge's defaults,
`cuteDefaults = 2`, so a 0.7 save gets it once). QuestBank keeps its own saved choice; its default for new installs
becomes 100 in sub-project D. If the owner still finds them big in play, fewer pins (the merge) is the lever, not the
size. The mockup's Map screen draws 100, 75 and 50 % over the real Redridge art so the owner can judge before C ships.

**Finds on the map** (layer "Finds", Settings row "Finds on the map", on): books, keys and the locked objects they open,
chests and other looted objects, rares; each drawn as the item's or the creature's icon at 18 px, round, inside the
game's minimap button ring at 24 px (a rare adds the nameplate's silver elite mark at its corner). Only what players
learned is drawn: QuestBank's data (`D.FIND`, sub-project B, seeded on day one as 11.3 says), the uploader's data file
(11.3), your own notes at once, guild mates' finds once two agree, a single guild mate's as a dim pin (0.5 alpha)
saying "A guild mate saw this" (sub-project G). The tooltip names the thing and who saw it: "Raven Hill Tome · read
here · 3 guild mates". Spoiler-free: never a book's text, never what a key leads to or where a chain goes next. A click
shows it on the arrow.

**Our list** (the right panel; what the owner called "more insightful without having to click each quest"):

- Head: the zone's name at 15 px WHITE, its level range in the range's difficulty colour, "14 quests" in DIM on the
  right.
- Sections from `QM.ZoneQuests(m)`: "Ready to hand in" ("3" in GOOD), "In your log", "To pick up" (in XP-per-minute
  order), each as two-line quest rows (pattern A, the narrow form): held quests show their objectives with progress on
  line 2, quests not taken "from <giver> · <place>"; then "Finds here" (NEW bar) with "All finds" on its right, then the
  find rows. With no finds here: one DIM row, "Nothing found here yet." (no list of kinds).
- Hover a row: its pins glow on the canvas (`MP.Lit`, `MP.Glow`). Hover a pin: its row lights and scrolls into view.
- Click a row: the quest to read (section 9) in place of the list, its pins lit; Back returns.
- **The Finds list** ("All finds", the footer's button, the menu's Map > Finds, `/cute finds`): the list gives way to
  every find you can see, grouped by zone (this zone first, then by distance), each a find row; a click takes the map
  to it and lights its pin; Back returns. Head line: "Yours, the guild's once two agree, and what players' games and
  guides gave QuestBank. Never a book's text or where a key leads."
- Empty: one DIM row, "No quests known here at your level."
- Not shown: quest ids; grey quests while the row is off; other zones' quests; a second route line; book texts;
  anyone's names but the givers' and, in the Finds list, the guild's first finder where the Finds category allows it.

The game's map stays one button away, and the minimap's zone text keeps opening it. With the Map module off, M is the
game's, and Cute draws on the game's map only with "Our icons on the game's map" on.

## 11. Discovery sharing

The owner: "sharing data discovered in game beyond everything found already with questbank is also key." The engine
already notes quests, NPC places, offers, chains, objective spots, survey answers, loot, items, spells and (6.1.1) boat
rides. This round adds what the world holds beyond quests, gets every Cute player's notes to the site, brings them back
without waiting for a release, and shares them live in the guild.

### 11.1 The new discoveries, ranked for launch

Built this round (1 to 4 in sub-project B, the guild part in G):

1. **Objects by place: chests, nodes, locked objects and the keys that opened them, books.** Loot outdoors gains the
   spot: `disc.loot` keeps up to four points per source and map (`GetPlayerMapPosition`, AllowedWhenUntainted; the
   source from `GetLootSourceInfo`, which had a source in 480 of 765 windows in upload 191, the rest skipped by design).
   A looted object's kind is learned from the items it gave (their class and subclass numbers), never from a list. A
   locked object notes the key-class items in your bags at the time (`GetItemInfoInstant` class 13, `Enum.ItemClass.Key`);
   the site joins them with the client's `Lock.csv` (57 locks whose key is a Forever item, such as the Brooch of the
   Wardens 277136 or the Black Tome 276561) to say which key it was. A book is what `ITEM_TEXT_BEGIN` opens: the object
   from the `softinteract` GUID or the item read, your spot, and the title from `ItemTextGetItem` (never the text). The
   client data holds no world books, chests or rares (`GameObjects.csv` is 1,483 signposts of 1,520, `Vignette.csv`
   2 rows), so every one of these is new knowledge. Forever's library books, the sleeping bag chain and the Keystone
   Fragment chain are found this way and shown spoiler-free.
2. **Rares.** `NAME_PLATE_UNIT_ADDED`: classification "rare" or "rareelite", the creature id from the GUID, its level,
   your spot (plates show within about 40 yards); plain in all 2,427 reads of upload 191. Noted as one point per
   creature per map cell, aggregated in memory; in the guild at most one ping per creature per 5 minutes (11.4), never
   one per plate event.
3. **Crossings.** 6.1.1's `disc.rides` learns the boat and zeppelin legs D.LINK knows. B extends it, under the same
   table and the same rule, to crossings no D.LINK row knows: a jump in place (the engine already detects them,
   `Target.lua`) that is none of a flight (the `TakeTaxiNode` hook), a hearth (its spell), a death or a loading screen
   into an instance is kept as `disc.rides["x:<map>:<x>,<y>><map>:<x>,<y>"]` with the spot before (where you last
   stood still for 10 seconds or more in the 3 minutes before it: the pier, the tower, the portal), the spot after,
   the seconds between, rides and when. Portals and the way to Zephras Isle, which reads "No known way there" today.
   Travel's measured flights join them as `disc.flown`, name-free.
4. **Sellers and trainers, merged at last.** `disc.sell` (camp goods sellers), `disc.trainer` and `disc.walk` are uploaded
   today and merged by nothing; `probe_pull.py` merges them.

Ranked for later rounds, in this order: which mob or object counts for an objective (the target's id on an objective
tick); dungeon run times and first-kill levels for the whole site; minutes per quest (`disc.qtime` from Timer.lua);
vendor stock; quest text at the quest window; NPC services; world events (`C_AreaPoiInfo`); death spots. Vignettes stay
counted in Observe only (no `VIGNETTE_MINIMAP_UPDATED` in any of 191 uploads). Not possible on this client: creature
casts, mob health, XP and loot chat text, the combat log (all secret or closed).

Every value is read through `QB.Plain` / `issecretvalue`, and nothing is noted while `ADDON_RESTRICTION_STATE_CHANGED`
says a restriction is active (QuestBank listens already, `Pins.lua:170-178`). A spot is where you stood, about 5 yards
out. The notes live in `QuestBankDB.disc.find` (`CuteQuestDB` under Cute), at most 400 objects and 200 rares, and the
crossings in `disc.rides` at most 100 beyond D.LINK's legs, oldest out, under the "Note what the game shows" switch
like every note.

### 11.2 To foreverrank.com

- **The uploader** watches `Cute_Quest.lua` beside `QuestBank.lua` in each `WTF\Account\<account>\SavedVariables`
  (the file is named after the folder). It refuses `Cute.lua` by name, with a test: CuteDB holds the roster, GUIDs and,
  on officers' clients, members' Only-you values. A Cute bundle of the uploader never installs QuestBank (a loaded
  QuestBank puts Cute_Quest to sleep).
- **Where a Cute player gets it:** Cute's page (`addons/cute/index.html`) offers two downloads side by side, "Cute"
  (the zip as today) and "Cute with the uploader" (the zip plus the QuestBank Uploader's installer and its data addon,
  11.3). Installing the uploader is the consent; Settings > Data you share names it and the page.
- **Name-free at the source.** One allow-list, in three places: the uploader's PowerShell, the page's upload script and
  the Worker before it stores. Kept: `disc`, `game`, `live`, `liveEra`, `turnins` (times cut to the minute, never the
  second), `diag`, `errors` (message and file:line only). Dropped: `bank`, `chars`, `plans`, `held`, `travel`, `runs`,
  `lock`, `run`, `settings`, `profiles`, `reports`, `trace`, `imported`. What was worth sharing in the dropped parts
  moves into `disc` first, without names: `disc.flown` (flight edges with seconds and the Frequent Flier rank); the
  crossings are already in `disc.rides`. Decided here: the same allow-list applies to `QuestBank.lua` (QuestBank's
  upload privacy was the open question in its direction; one rule for both files is simpler and stricter).
- **The hand-in votes survive the cut.** `probe_pull.py` dedups hand-ins in a global `acc["seen_at"]` keyed
  `"qid:at"` (`probe_pull.py:264-293`): a cut to the day would merge every same-day hand-in of a quest, across all
  players, into one vote, shrinking QuestBank's core XP data. So the cut is to the minute, and before the uploader
  strips anything, one commit changes `probe_pull.py` to cut every `at` it reads to the minute (`at[:16]`), migrates
  the stored `seen_at` keys the same way once (so a file counted before is not counted again), and extends
  `--selftest` with a second-precision file followed by its minute-cut re-upload (one vote) and two players' hand-ins of
  one quest a minute apart (two votes). Two hand-ins of one quest in the same minute by two players count once: an
  under-count, rare, and only of identical readings.
- **One file, one voice.** `disc.token`, a random token made once per saved file, so the site counts files, not
  re-uploads of a growing one.
- **The Worker** learns `'cutequest-savedvars': /^\s*CuteQuestDB\s*=/` beside `questbank-savedvars`. The stored rows
  are stripped at read time (`probe_pull.py` applies the allow-list to old rows) and kept until after launch; then,
  owner-run, `disc.flown` is backfilled from the stored `travel` and the `runs` are exported for the run-times round,
  and only then are the dropped keys purged. Both need the owner (wrangler and D1).
- **`probe_pull.py`** decodes `CuteQuestDB` like `QuestBankDB` (source "cute") and merges `disc.find`, `disc.flown`,
  `disc.rides`, `disc.sell`, `disc.trainer` and `disc.walk` into `disc.json`, votes per file token.

### 11.3 Back into the data, without waiting for a release

**By release.** `probe_pull.py` → `research/questbank/disc.json` → `gen_data.py` → QuestBank's `Data.lua` →
`tools/cute/build.py` copies it byte for byte into Cute_Quest. `gen_data.py` writes `D.FIND` (per map: kind, id,
spots, votes, the key or title, the source), adds players' crossings to `D.LINK` (today hand-written from Classic) and
players' trainers and sellers before the Classic seeds, each labelled "seen in players' games". A find needs two files
that agree (within 15 thousandths, as Discover's `OS_NEAR`) before it ships. `GAPS.md` gains a count of new finds per
kind. The guild's own set (11.4) drops what the release now carries.

**Seeded on day one** (so the layer shows something the first time it is on): `D.FIND` starts from what is known now,
each row with source "guides" and shown as such: the library books' places from the secrets research
(`2026-10-21-forever-secrets-research.md` section 1; the guides credited on the site, the books' titles only), and the
locked objects whose key `Lock.csv` names, at Wowhead Forever's object spots where it has them. Not seeded: any step
of a secret chain past its first (spoiler-free: a chain's next step shows only once you or two guild mates found it).

**By the uploader's data file** (the standing rule: an addon update per discovery is not acceptable). The uploader
bundle carries a data-only addon, `QuestBank_Finds` (`## LoadOnDemand: 0`, `## OptionalDeps` of QuestBank and
Cute_Quest, one file `Finds.lua`), TSM AppHelper's pattern. Once a day the uploader fetches the site's merged finds
(`/api/finds.json`, the same two-files-agree rule) and writes `Finds.lua` itself from a fixed schema: numbers and
cleaned short titles only (the `S.LABEL_MAX` cleaning), never Lua or text from the site. At the next login the engine
adds its rows under `D.FIND` where `Data.lua` has none, and its version joins the re-plan signature. Without the
uploader, finds arrive by release and through the guild.

### 11.4 Live inside the guild

- **Own finds count at once.** Today a player's own NPC places and objective spots feed only the next release. A new
  engine overlay, `QB.Finds`, holds your own finds and the guild's confirmed ones, read wherever `Data.lua` and the
  data file have no place or spot; its version joins Core's re-plan signature (as `TV.ver` does), so a confirmed find
  re-plans once.
- **What goes out at once:** a quest giver or ender not in Data (or more than 25 yards off) with its quests; an
  objective spot Data lacks; a crossing; a class trainer not in `D.TRAINER`; a camp goods seller; a rare up now; an
  object, key or book by its place. Everything else is upload-only.
- **The message**, a new Cute kind `1X|entry;entry;...` (Cute's kinds today: 1D, 1F, 1L, 1K, 1R, 1P, 1N), ids and
  maps in base 36, x and y in thousandths in base 36: `g<q>:<npc>@<map>:<x>,<y>` giver, `e...` ender,
  `o<q>.<i>@...` objective spot, `t<npc>@...=<class>` trainer, `v<npc>@...=<item>.<item>` seller,
  `h<obj>@...=<class>.<subclass>` looted object, `k<obj>@...=<item>.<item>` locked object and its key candidates,
  `b<obj>@...` book, `r<npc>@...=<level>` rare, `x<map>:<x>,<y>><map>:<x>,<y>=<seconds>` crossing. About 20 bytes an
  entry, ten to a message. A book's title and an NPC's name travel in the existing `1L` labels (`b<obj>=Title`,
  `n<npc>=Name`, 60 bytes, cleaned as `S.LABEL_MAX` text is); older clients skip unknown keys.
- **Budget.** In Comm's queue after the policy, the guild's deltas and the whispers; a rare ping goes before the other
  finds (it expires in 10 minutes); batched, at most one message a minute and 30 an hour per member; never from inside
  an instance; only finds that this client's Data, the data file and the guild's set lack. About 30 entries a questing
  hour: three or four messages. A rare: one ping per creature per 5 minutes at most.
- **Two voices.** A guild mate's find changes nobody's route until two members agree: two GUIDs the roster lists, not
  marked untrusted (as `S.Sure`), spots within 15 thousandths, the mean routed. Your own find routes you at once. A
  one-voice find is display-only (the dim pin); a rare ping is display-only and expires after 10 minutes.
- **Bounds.** The map must be one the client knows (`C_Map.GetMapInfo`); ids in range; four voices per find at most;
  300 finds per member and 2,000 in all, oldest out; untrusted members and senders without a roster GUID ignored.
- **Who sees it.** A new discovered category, Finds (`S.FOUND` gains `{ "finds", "Finds", "cf" }`, default Everyone),
  which `Policy:Route` sends with Zone (a find says where you stood), objective spots also with Quests in log
  (`quests_log`), looted nodes also with the professions (`prof1`, `prof2`). Closed, finds are whispered to the
  officers like any Only-you value; an officer's client confirms them with two voices and relays them in the officers'
  word (`1N`, no GUID), so members' guides still gain. Members who log in later get confirmed finds only through the
  officers' word: a member's relay cannot prove its voices and is never taken.
- **Kept in `CuteDB.known.finds`**, never in `CuteQuestDB.disc`: the site counts each player's own eyes once, and an
  edited copy cannot launder guild data into a release. A find the new Data.lua or data file carries is dropped at
  login.
- Settings > Data you share: "Share finds with the guild" (on), the member's own switch over sending.

### 11.5 Privacy, and the leaks this round closes

**The page, in one sentence:** "Cute shares what you find with your guild in game; the optional uploader sends only
what you found in the world (quests, NPCs, places, drops), never a name or anything about your guild."

Never leaves the client: character names and Name-Realm keys, GUIDs, account folder names, all of `CuteDB` (roster,
records, Only-you values, policy, untrusted marks, the officers' word), party members' names, chat, times to the
second. The Cute page's "No server, no accounts" and the README's "No server, no uploader" change with sub-project B.

**The guild leak.** Cute_Quest's copy of Sync sends on GUILD under the prefix "QuestBank" (`Sync.lua:18, 71`) while
`share.guild` is true, QuestBank's default (`Core.lua:1260`), which Cute never sets: `1S` (level, XP, plan, banked, run,
a GUID tail) and `1Q` (quest ids with progress). That bypasses the officers' routing: XP into level, Quests in log and
Ready to hand in can be closed in Cute and still go out. And `Sync:Receive` (`Sync.lua:252`) takes any guild mate's
`1L` XP reading as a correction, one voice. Sub-project A: Bridge forces `share.guild = false`, and QuestBank's
`Sync:Receive` takes nothing from GUILD while `share.guild` is off (a one-line gate, right for QuestBank's own players
too). Guild sharing goes through Cute's Comm alone.

**The raid leak.** `share.party` (on, a row in Data you share) sends the same `1S` and `1Q` to the group channel, and in
a raid that is RAID (`Sync.lua:60-71`): a guild raid reaches members the officers routed those values away from.
Sub-project A: Bridge sets `E.noRaidSync = true` beside the copy's `E.quiet` (`Bridge.lua:28-29`), and Sync's
`groupChannel` (`Sync.lua:60-64`) gives PARTY or INSTANCE_CHAT only while it is set, never RAID; in a raid group the
party sync is silent. QuestBank alone keeps RAID for its own players, whose sharing is their own choice.

## 12. What stays from Cute 0.7 and QuestBank 6.1

- **Cute:** the privacy model whole (Only-you routing to officers by whisper, the policy in Guild Info, two voices to
  learn, the officers' word, untrusted members); the dashboard's pages and stats; the rules and the knowledge model; the
  module registry and its keys; load on demand and `DisableAddOn` per character; the flat black-and-white look, ARIALN,
  1 px edges, virtual lists; the minimap button (left-click now J); every `/cute` word.
- **Cute_Quest:** the engine copied byte for byte by `build.py`; the dormant rule when QuestBank is loaded
  (`QB.dormant`, `QuestBankAPI`); `QB.Skin`; `/qb` routed to Cute's pages.
- **QuestBank 6.1.1:** its own window, settings, minimap button and look; the step engine, the one target and the
  route; QuestBank's arrow by default; Accept for me and hand-in as choices; the Map page in its own window; the
  tracker out of sight, `mapLowLevel`, `wholeRoute` and `disc.rides` as shipped. Every QuestBank-side change in this
  round is a hook whose default is today's behaviour (`QB.Locked`, `QB.Movers`, `guide.quests = 0`, `QB.Skin.Quality`),
  a bug fix (the Sync gates, the EJ cover crop, the minimap on Edit Mode exit, the tracker's clicks) or a new note
  (section 11), so QuestBank players see the same addon plus better data.

## 13. Decisions taken here

| Where the owner left room | Decision | Section |
|---|---|---|
| Keys written into the game's set, or overrides | Override bindings that follow the game's own key; per character; a "Follow" tick to go back | 4 |
| "force a reload after settings is changed" | Window and tab choices reload (Reload or Undo, no Later); keys, layout and settings apply at once; the card says so. For the owner's review | 3 |
| "our base with quests and route" | Quests and its Route tab, and the step frame, always on; Dungeons, Gear, Map, Camp are the modules. Every Cute character loads the engine | 2 |
| What Lock covers | The on-screen pieces; windows always drag by their header | 6 |
| "if they use ours" | The step frame is "ours" and gains the quests you hold; the game's tracker is out of sight by default (shipped), D adds the scale so its lines stop taking clicks | 9 |
| "icons ... wrong size" | The game's size only, no size row; fewer pins (merged by screen distance) instead of smaller ones | 10 |
| "low level quests as default?" | Shipped: hidden unless `mapLowLevel`; Cute's first run starts it from the game's own trivial-quest option and never writes that option | 10 |
| What a click on a quest does | Reads it, everywhere; Ctrl-click puts it on the arrow; the reader carries Share and Abandon | 8, 9 |
| Drag across a zone's edge | Stops at the edge; the continent map is where you drag across zones | 10 |
| Where the Guide goes | It becomes the Quests tab; its logic stays in the core; its officers' rules go to Guild > Rules | 2, 9 |
| A site-sharing tick on the first-run card | None: installing the uploader is the consent; the card stays short | 3, 11 |
| Upload privacy for QuestBank.lua too | Yes, one allow-list for both files; hand-in times to the minute, the dedup moved first | 11.2 |
| Finds back to players | By release, seeded on day one, and daily through the uploader's data file | 11.3 |
| Cute's guild knowledge (`CuteDB.known`) to the site | Never; the site gets each player's own notes only | 11.4 |
| Party sync in a guild raid | Never on RAID under Cute | 11.5 |
| The guild key for a character without a guild | J stays the game's until the character joins one | 3 |

## 14. Testing

Cute's harness (`cd tools/cute && luajit harness.lua`, ending `layout problems: 0` then `OK`) and QuestBank's
(`cd tools/questbank && luajit harness.lua`, ending `OK`), one `luajit` at a time, `memory_pressure` normal before
QuestBank's. Each sub-project adds its cases; each case fails on the files before it.

- **A.** `share.guild` false after Bridge's first run on a 0.7 save that had it true; no `QuestBank`-prefix message on
  GUILD from the copy; a guild `1L` XP reading changes nothing while `share.guild` is off (QuestBank's harness too); in
  a mock raid under Cute, no `1S` or `1Q` on RAID, and QuestBank alone still sends there; `UI.OpenMap` calls
  `OpenWorldMap` and never `ToggleWorldMap`; every Settings section at 1040 x 640 and 760 x 420 with no cut label (the
  new gate: `FitText` records a cut, and a visible cut label in a Settings sheet is a layout problem) and the section
  list unscrolled at 760 x 420.
- **B.** `probe_pull.py --selftest` first, in its own commit: a second-precision hand-in file, then its minute-cut
  re-upload, counts one vote; two players' hand-ins of a quest a minute apart count two; the stored keys migrated once.
  QuestBank: a chest looted outdoors keeps its spot; a locked object keeps the key-class items; `ITEM_TEXT_BEGIN` keeps
  the object, spot and title and never the text; a rare plate keeps one point per cell; a portal crossing lands in
  `disc.rides` under an `x:` key, a flight, a hearth, a death and an instance door do not, a boat leg still under its
  D.LINK key; nothing noted under an addon restriction or with a secret GUID; caps hold; the memory and garbage gates
  (11 MB kept, a re-plan under 64 KB); `QuestBank_Finds` rows load under `D.FIND` and never over Data.lua's. Uploader (in
  Docker, `mcr.microsoft.com/dotnet/sdk:8.0`): watches `Cute_Quest.lua`, refuses `Cute.lua`, strips the dropped keys,
  cuts `turnins` to the minute, writes `Finds.lua` from a fixture JSON and refuses a field outside the schema.
  `gen_data.py` self-tests for `D.FIND` (two files agree before a find ships; the seed rows carry "guides"). The Worker
  accepts a `CuteQuestDB` body and refuses a `CuteDB` one.
- **C and D (one release).** The setup card on a fresh character and on a 0.7 save with Gear off and Accept for me
  "route": the rows start from that save, Start changes nothing it did not show; the keys read from the game's
  bindings, a hand-picked key's "replaces" line, Start greyed in a fight, Start reloading and L opening once after it;
  Not now changing nothing; F's `mapwin` row alone, starting from the `mapicons` answer. Keys: overrides set on login,
  `UPDATE_BINDINGS` and `PLAYER_GUILD_UPDATE`, queued in a fight, cleared for a window that is off, J left alone
  without a guild, Follow ticked again after a hand-picked key. The menu's entries per module and rank, a parent click
  opening its window, the compartment. Staged module changes: the band line, the popup on close, Esc as Undo. Every
  window and tab at both sizes for an officer and a member with every module on, and with each tab off. The header
  buttons are secure click buttons on the micro buttons. The quest to read from L, from M and from the step band, Back
  restoring the scroll, Share only in a group and only when pushable, Abandon through `UI.ConfirmAbandon`.
  `mapIconPct` becomes 100 once on a 0.7 save and a size picked in QuestBank after stays; `mapLowLevel` started from
  the game's trivial option at `cuteDefaults = 2` and the game's option never written. Patterns A, B and C at both
  sizes; the step frame with 0, 3 and 10 quests at three scales, the quests the step names left out, its item buttons
  frozen in a fight; `SF.Tracker`'s scale set and put back with the alpha, nothing else called on the tracker (the mock
  records every call on `ObjectiveTrackerFrame`), Edit Mode enter and exit; the default places with no overlap at
  1920 x 1080 and 1366 x 768 screens; merged givers on the game's map and no pin where the game draws one; no text
  outside Windows-1252; every file id in the manifest.
- **E.** Layout mode: a mover for every piece that is on and none for a window, snap, Shift free, the wheel's scale
  (the arrow's `compassSize` clamped), nudges, the right-click menu, Esc, combat ending it; lock and unlock; a new
  character taking `layoutDefault`; Copy from; Reset windows; the arrow's and the camp bar's lock checks in QuestBank's
  harness; the minimap left to Edit Mode; with QuestBank loaded, no mover for the engine's pieces and none of
  QuestBank's settings written.
- **F.** The map: built at login out of combat; opened in a fight; the wheel through zones up and down; drag stopping
  at the zone's edge; QuestBank's pins and finds on the continent map; the four added providers (a corpse pin after a
  death) with a clean taint log; Ctrl-click on the arrow; pins at the game's size; pins merged by screen distance and
  parting when zoomed; the trivial rule; one route line; the list's sections, hover both ways, the quest to read for a
  log quest and a catalog quest, Back; the Finds list from the footer, the menu and "All finds"; finds from `D.FIND`
  (the seed), the data file and your own (`disc.find`); "Nothing found here yet."; both window sizes; the memory gate
  with the map open.
- **G.** `1X` packing and parsing at the 255-byte limit; the budget (a questing hour of finds under 30 messages, a rare
  ping first); two voices, a one-voice dim pin, a rare expiring; bounds and caps; Finds closed: whispered to officers,
  relayed in the officers' word, a member's relay refused; `CuteDB.known.finds` never in `CuteQuestDB`; a find the new
  Data or data file carries dropped; a confirmed find re-planning once; the footer's counts (new, confirmed) and
  Statistics' Finds category under the routing.

**Layout at both sizes.** Every window (J, L with each tab, M, Settings with each section, the setup card) is checked at
its default and minimum size through `check(root, label)`: no clipped or overlapping text, nothing touching a window's
edge, no cut label in Settings or the card (lists ellipsize by design and carry the full text in the tooltip).

**A render pass.** `luajit harness.lua --layout out.json`, then `python3 tools/questbank/render_layout.py out.json
out.html`: one picture per window and size, read before each release as the owner reads the game (the "vibe coded"
check: the whole surface, every control, at both sizes).

**In game** (the owner's testers, Norwegian Windows clients): the keys after the reload and after rebinding the game's
map key; the micro-button clicks in a fight; the taint log (`/console taintLog 1`, then `Logs\taint.log`) after a
dungeon boss fight with the tracker hidden and a quest item used from the step frame; a click where the hidden tracker
stands reaching the world; the step frame read over bright ground (Redridge, Tanaris); the EJ covers without a strip;
the map's wheel across zones and a corpse run with M open; a book read, a chest looted and a rare seen landing in
`Cute_Quest.lua`; the uploader sending it and writing `Finds.lua` back.

**The page** (`addons/cute/index.html`): the window mocks for J, L and M and the setup card as the addon draws them,
reviewed phone-first (the mockup fits each window to the phone's width, with a Real size switch); the privacy sentence;
the two downloads; one changelog line per version; no list of what the modules track.

## 15. Out of scope

- The guild backlog, each a module later: the run report, halls, records, OXM.
- QuestBank's own window, its Map page and its Settings: unchanged but for the hooks and fixes above.
- Edit Mode systems for Cute's frames; the minimap's size and place (the game's Edit Mode).
- The later discoveries of 11.1 (objective counters, run times, quest minutes, vendor stock, quest text, NPC
  services, world events, death spots); a site page that draws finds (this round brings them into the data and the
  addons).
- Cute's guild knowledge on the site, ever.

## 16. Sub-projects, in launch order

Each ships alone, with its harness cases, a render pass and one changelog line. Versions are the next free number at
the time (0.7.1 and 6.1.1 are taken). Order: what the owner asked for in the most detail and what makes play count
first; layout mode, which changes nothing a player sees until they move something, last.

| # | Sub-project | Ships | Depends on |
|---|---|---|---|
| A | **Fixes** (Cute's next 0.7.x, QuestBank's next 6.1.x) | the guild leak closed (Bridge forces `share.guild = false`; Sync's GUILD receive gated); no RAID sync under Cute; `UI.OpenMap` through `OpenWorldMap` and `HideUIPanel`; Settings never cuts (Choice measured, notes wrap, rows 22 px, the list never shrinks, the cut gate) | none |
| B | **Finds to the site and back** (QuestBank 6.2.0, the uploader and its data addon, the Worker, `probe_pull.py`, `gen_data.py`) | `probe_pull.py`'s minute dedup first; the new notes of 11.1 (1-3) in a new engine file `Finds.lua`, which `build.py`'s `ENGINE_KNOWN` learns; `disc.flown`, the `x:` crossings in `disc.rides`, `disc.token`; the uploader reading `Cute_Quest.lua` and refusing `Cute.lua`; one name-free allow-list in three places; the Worker's new kind and `/api/finds.json` (the owner deploys); the merges of 11.1 (4); `D.FIND` with the day-one seed; `QuestBank_Finds`; the page's privacy sentence and the two downloads | A; runs beside C+D |
| C+D | **The windows and the look, one release** (Cute 0.8.0, QuestBank hooks) | J, L and Settings as their own windows from one builder; L's tabs Quests, Route, Dungeons, Gear in the new look (patterns A, B, C; the two columns; the route's map and level-up); the quest to read with Share and Abandon; the Guide retired into it; the setup card from the character's own choices; keys by override; the right-click menu and the compartment; the reload rule; the secure header buttons; the palette, type and icons; the step frame as a route stop with the quests under it (`guide.quests`), no backdrop, outlined; `SF.Tracker`'s scale step; the default places; fewer pins on the game's map; the EJ cover crop; `mapIconPct` 100 (Cute's first run; QuestBank's new installs); the Map module's switches on the game's map until F | A |
| F | **The map** (Cute 0.9.0) | `CuteMapFrame` with the canvas and the four added providers, the wheel through zones, drag, the layers, pins at the game's size merged by screen distance, the list, the quest to read, the Finds list, finds from `D.FIND`, the data file and your own; the M key; the setup card's `mapwin` row, then M opening once | B, C+D |
| G | **Finds in the guild** (Cute 0.10.0) | `QB.Finds`, `1X`, two voices, the Finds category and its routing, the officers' relay, the dim pins, rare pings, the footer's counts, Statistics' Finds category, the Data you share line and row | B, F |
| E | **Layout mode** (Cute 0.11.0, QuestBank hooks) | movers, snap, scale, reset and lock for the on-screen pieces; Edit Mode's enter and exit; per-character layouts with the account default; Reset windows; `QB.Movers`, `QB.Locked`, `remind.bannerPos`, the arrow's and the camp bar's lock checks; the minimap left to Edit Mode | C+D |

Why this order: C and D ship together so the owner never sees today's Guide again in a new window; F (the map, the
owner's most detailed ask) needs only B's data and C+D's windows, not layout mode; G follows F because its pins live
on the map; E comes last because 0.7's drag already works and nothing in A to G waits for it.

## 17. Changes after the 2026-10-21 reviews

- Rebased on QuestBank 6.1.1 and Cute 0.7.1: the tracker, low-level quests, one stroke and boat rides are shipped
  facts; D only adds the tracker's scale; `disc.rides` is extended instead of a new `disc.ride`; the whole-route row is
  in Route; A no longer measures the low-level question.
- The card starts from each character's own choices; row ids `mapicons` and `mapwin`; its copy says what reloads.
- Hand-in times to the minute, with `probe_pull.py`'s dedup moved first; the D1 purge after launch, after a backfill.
- A quest row's click reads it everywhere; L has the reader, with Share and Abandon.
- Quests and Route are the base; Lock covers on-screen pieces only; windows drag by their 30 px header.
- The map keeps the corpse, area points, map links and graveyards; drag stops at a zone's edge; pins merge by screen
  distance; no icon size row; the Finds layer is seeded on day one and the data comes back through the uploader.
- No RAID sync under Cute; the officers' guide rules moved to Guild > Rules; the minimap rows moved to Route.
- The look: no drawn squares or chips, status as the right-hand word, game art for every control and mark, the step
  frame outlined, the route with a map, segments and a level-up rule, the Quests tab in two columns.
- Order: A, B, C+D, F, G, E.
