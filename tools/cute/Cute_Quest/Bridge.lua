-- SPDX-License-Identifier: GPL-3.0-or-later
-- Bridge: after the engine's files. QB.Engine is the engine the pages read: this copy, or QuestBankAPI while QuestBank
-- is loaded (then nothing below runs: QuestBank's own window serves its engine). For the copy, what QuestBank's
-- UI.lua (the window, not copied) gave the engine files: the window verbs on QB.UI (Lists.lua made the table), mapped
-- onto Cute's window; the login the engine never sees (loaded on demand, after PLAYER_LOGIN); the module's first-run
-- defaults; /qb routed to Cute's pages and otherwise to the engine's own handler.
local ADDON, QB = ...
local Cute = Cute
local NEED = "6.1.0" -- the first QuestBank that sets QuestBankAPI
if QB.dormant then
  -- (an older QuestBank sets no QuestBankAPI: no engine for the pages, which say so and draw nothing more; never
  -- this copy, whose files returned at their second line)
  QB.Engine = QuestBankAPI
  if type(QB.Engine) ~= "table" then
    QB.Engine = nil
    local A = type(C_AddOns) == "table" and C_AddOns or nil
    local ok, v = pcall(A and A.GetAddOnMetadata or error, "QuestBank", "Version")
    QB.missing = string.format("QuestBank %s or newer is needed; yours is %s.", NEED, (ok and type(v) == "string" and v ~= "") and v or "older")
  else
    -- (the launch audit) QuestBank's own party sync, beside Cute: never on RAID (as this copy's, E.noRaidSync below) and
    -- never on GUILD, whatever its share.guild says: its 1S carried level, XP, class, a GUID tail and the plan around the
    -- officers' Who sees what. Runtime flags on QuestBank's QB (QuestBankAPI, its Core.lua; Sync.lua reads them), none
    -- of its saved settings written: guild sharing goes through Cute's Comm alone
    QB.Engine.noRaidSync, QB.Engine.noGuildSync = true, true
  end
  return
end
QB.Engine = QB
local E = QB
local UI = E.UI
-- the engine's chat lines carry Cute's prefix; and the copy is quiet (Core.lua QB.quiet): a waypoint clicked, a run's
-- start and end and the errors line stay out of chat, since the step frame and the arrow say those things. A quest
-- complete or gone from the log is said only when asked for (sayXP, the Quests section's "Say XP after each hand-in"),
-- as the hand-in's line is
function E:Print(msg) Cute.Print(msg) end
E.quiet = true
-- the party sync never on RAID (Sync.lua groupChannel): a guild raid would reach members the officers routed level, XP
-- and the quest log away from; in a raid the party sync is silent. Cute's own channel carries what the guild sees
E.noRaidSync = true
-- (the windows round) the on-screen pieces' default places, for the ones never moved: the step frame where the game's
-- quest tracker stands (it takes that job: StepFrame.lua place), the arrow at the top's middle under the game's
-- error text (Arrow.lua A.Place)
E.cornerPlace = true
-- (the windows round) fewer pins on the game's world map: none of ours where the game draws one, touching ones merged with
-- a count (QuestMap.lua QM.Thin); QuestBank alone draws them all
E.thinMap = true
-- (sub-project F) the engine's map canvas is Cute's Map window (M, MapWin.lua): the game's smooth wheel through zones, its
-- right-click up a map, pins merged where they touch and drawn on a continent, the finds (MapPage.lua, QuestMap.lua); and
-- each kind of pin its own look on both maps: an objective's spot its kind's cursor, a stop of the route its number on
-- the game's disc, so the game's own quest disc is the only one with the three dots (Pins.lua P.StyleKind, P.StyleStop)
E.mapWindow, E.kindMarks = true, true
-- the engine's words name the host: "Choose a reward: X is Cute's pick", "Nothing to do: /cute quests", the minimap
-- menu's "Cute settings"; and they leave out the /qb commands a Cute player is never told of (host: Settings alone)
E.NAME, E.CMD, E.host = "Cute", "/cute quests", true
-- (the hud round) the Reminders module is Reminders' only master switch: off, the step frame's line goes with the two
-- pieces (QuestBank alone keeps the line to its rows when "Reminders on screen" is off: Remind.lua)
E.remindAll = true
-- the minimap is the engine's only while Cute's Map module is on (Minimap.lua, Mini.Owned): its wheel, Ctrl-wheel,
-- Alt-drag, right-click menu, size and place, and the tracking menu's Target; off, the game's own
function E.MapOn() return Cute.ModuleOn("map") end

-- the engine's errors on Cute's list too (/cute errors). A real error goes through Cute's public Cute.Safe: recorded
-- with where it happened (Cute says so once a session, as for its own). A call the game blocked is noted there quietly,
-- as Cute's own quiet notes are (Cute/Core.lua, Err.Record with quiet: its shape, the newest first, 20 kept; Cute's API
-- has no public quiet note), and says nothing in chat, Cute's "ran into a problem" line included (Core.lua's
-- Err.Blocked says nothing either). Each goes to Cute the first time it is seen: the engine's own list counts the
-- repeats (an error in an OnUpdate repeats twenty times a second, a blocked call once a redraw, and each Cute.Safe made
-- closures, a table and a stack). Under CUTE_DEV (the harness) Cute.Safe raises: the pcall keeps the engine's own
-- record going either way
local seenError, seenBlocked = {}, {}
local function toCute(msg, where)
  pcall(Cute.Safe(function() error(msg, 0) end, "quest engine: " .. tostring(where or "?")))
end
local function noteCute(msg, where)
  local db = type(CuteDB) == "table" and CuteDB or nil
  if not db then return end
  if type(db.errors) ~= "table" then db.errors = {} end
  local list = db.errors
  local now = date and date("%Y-%m-%d %H:%M:%S") or ""
  for _, e in ipairs(list) do
    if e.msg == msg then e.count, e.last = (e.count or 1) + 1, now; return end
  end
  table.insert(list, 1, { msg = msg, stack = "", where = where, count = 1, first = now, last = now, version = Cute.version })
  while #list > 20 do table.remove(list) end
end
local record, blocked = E.Err.Record, E.Err.Blocked
function E.Err.Record(msg, stack, where)
  record(msg, stack, where)
  local key = tostring(msg)
  if seenError[key] then return end
  seenError[key] = true
  toCute(msg, where)
end
function E.Err.Blocked(event, who, fn, stack)
  local kept = blocked(event, who, fn, stack)
  if not kept then return kept end
  local name = E.Plain(fn)
  local key = type(name) == "string" and name or "?"
  if not seenBlocked[key] then
    seenBlocked[key] = true
    noteCute(string.format("the game %s %s%s", event == "ADDON_ACTION_FORBIDDEN" and "forbade" or "blocked", key,
      (InCombatLockdown and InCombatLockdown()) and " in combat" or ""), "quest engine: blocked call")
  end
  return kept
end
-- a module that is a switch over the engine's flags (Map, Camp): off, every flag it names goes off and what they were
-- is kept (s.cuteOff[id]); on, they come back as they were (a fresh install: the engine's defaults). Cute applies a
-- module's state at every login, so on with nothing kept changes nothing: a flag a row set stays as the row set it,
-- and off with every flag already off keeps what was kept. keys are the settings' names, "remind.buffs" a field of a
-- table. Returns true where a flag changed
local function field(s, key)
  local t, k = s, key
  local head, rest = key:match("^(.-)%.(.+)$")
  if head then t, k = s[head], rest end
  return t, k
end
function QB.Follow(id, keys, on)
  local s = E:Settings()
  local kept = s.cuteOff and s.cuteOff[id]
  local changed = false
  if on then
    if not kept then return false end
    for _, key in ipairs(keys) do
      local t, k = field(s, key)
      local v = kept[key]
      if t and v ~= nil and (t[k] == true) ~= v then t[k] = v; changed = true end
    end
    s.cuteOff[id] = nil
    return changed
  end
  local was, any = {}, false
  for _, key in ipairs(keys) do
    local t, k = field(s, key)
    was[key] = t ~= nil and t[k] == true
    if was[key] then any = true end
  end
  if not any then return false end
  s.cuteOff = s.cuteOff or {}
  s.cuteOff[id] = was
  for _, key in ipairs(keys) do local t, k = field(s, key); if t then t[k] = false end end
  return true
end

-- QuestBank's tab numbers (its UI.lua: 1 Quest Log, 2 Plan, 3 Route, 4 Party, 5 Settings, 6 Now, 7 Journal, 8 Map)
-- as the quest window's tabs (the party is the Quests tab's band); a tab whose module is off (Dungeons) is the Quests
-- tab (Cute's own way with an off page is Race: a travel, train, grind or corpse step clicked in the step frame opened
-- the guild's table)
-- (sub-project F: tab 8, the engine's Map page, is Cute's Map window)
local PAGE = { [1] = "quests", [2] = "quests", [3] = "route", [4] = "quests", [5] = "settings", [6] = "quests", [7] = "journal", [8] = "map" }
local function pageOf(tab)
  local page = PAGE[tab] or "quests"
  if page ~= "quests" and page ~= "settings" and not Cute.ModuleOn(page) then page = "quests" end
  return page
end
-- (the step frame's click on a quest's step names the quest, UI.scrollToQuest, and opens tab 1: in Cute the quest window
-- reads that quest, as a click on a quest reads it everywhere; with Ctrl it goes on the arrow instead)
function UI:Open(tab)
  local qid = UI.scrollToQuest
  UI.scrollToQuest = nil
  local q = qid and tab == 1 and E.Quest.Get(qid)
  if q and IsControlKeyDown and IsControlKeyDown() then UI.QuestClick(q, E:Status(q), "LeftButton") return end
  Cute.Open(pageOf(tab), tab == 5 and "quests" or nil)
  local win = q and QB.Reader and Cute.Window and Cute.Window("quests")
  if win and win.frame and win.frame:IsShown() then QB.Reader.Read(win, q) end
end
-- the page a click opens, by name, for the engine's words ("Click: the Quests page.": Arrow.lua)
local TITLE = { quests = "Quests", route = "Route", settings = "Settings", journal = "Dungeons", gear = "Gear", map = "Map" }
function UI.PageName(tab) return TITLE[pageOf(tab)] or "Quests" end
function UI:ShowTab(tab) self:Open(tab) end
-- (the hud round) Settings from a reminder's menu: Cute's Reminders section
function UI.OpenReminders() Cute.Open("settings", "camp") end
function UI:TogglePage(tab) self:Open(tab) end
function UI:Toggle() Cute.Open("quests") end
function UI:Refresh() Cute.Refresh() end
-- the game's world map as QuestBank's own window opens it (QuestBank/UI.lua UI.OpenMap): OpenWorldMap opens it and
-- HideUIPanel shuts it, both the game's own panel code, so the map lays itself out and draws its pins as the game.
-- Never ToggleWorldMap, which the game later blames on the addon; and not in a fight, where addons may not show or
-- hide a panel (UIParentPanelManager.lua:854-858)
function UI.OpenMap(toggle)
  local wm = WorldMapFrame
  if not (wm and OpenWorldMap and HideUIPanel) then return false end
  if InCombatLockdown and InCombatLockdown() then
    E:Print("In a fight only the game's own map key opens the map.")
    return false
  end
  if wm:IsShown() then
    if toggle then pcall(HideUIPanel, wm); return false end
    -- open on another map: shut and opened again, where the game puts it on your zone
    local ok, here = pcall(function() return MapUtil.GetDisplayableMapForPlayer() end)
    here = ok and E.Plain(here) or nil
    if not here or here == E.Plain(wm:GetMapID()) then return true end
    pcall(HideUIPanel, wm)
  end
  pcall(OpenWorldMap)
  return wm:IsShown() and true or false
end
-- (the engine's Map page is Cute's Map window while the Map module is on)
function UI.MapPageOn() return Cute.ModuleOn("map") end
function UI.Caret() end
function UI:ShowMenu(title, items)
  if type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function" then
    MenuUtil.CreateContextMenu(UIParent, function(_, root)
      root:CreateTitle(title)
      for _, it in ipairs(items) do root:CreateButton(it[1], it[2]) end
    end)
    return
  end
  local names = {}
  for _, it in ipairs(items) do names[#names + 1] = it[1] end
  Cute.Print(title .. ": no menu on this client (" .. table.concat(names, ", ") .. ").")
end
function UI:CopyLink(title, url) Cute.Print(title .. ": " .. url) end
function UI:PostDialog() end -- (Cute posts nothing: post.auto is off)
function UI:ShowErrors()
  local list = QuestBankDB and QuestBankDB.errors or {}
  local diag = QuestBankDB and type(QuestBankDB.diag) == "table" and QuestBankDB.diag or {}
  local held = type(diag.blocked) == "table" and diag.blocked or {}
  Cute.Print(#list .. " quest engine errors" .. (#list > 0 and ", the newest first:" or ".") .. (#held > 0 and (" " .. #held .. " calls the game blocked.") or ""))
  for i = 1, math.min(5, #list) do Cute.Print((list[i].where or "?") .. ": " .. tostring(list[i].msg)) end
  for i = #held, math.max(1, #held - 2), -1 do Cute.Print("the game " .. (held[i].kind == "forbidden" and "forbade " or "blocked ") .. tostring(held[i].fn)) end
end
UI.frame, UI.tab, UI.lastTab, UI.postFrame, UI.scrollToQuest = nil, nil, nil, nil, nil

-- the module's defaults, once: no QuestBank map page (the Map key is the game's), no posting, no update nag, no
-- level-up line, no welcome card (the choices are Settings rows), no minimap button (Cute has one). And at every load
-- no sharing with the whole guild (Cute has no row for it): the engine's 1S (level, XP, class, GUID), 1Q (every quest
-- and its progress) and 1R went to GUILD around the officers' Who sees what, and with it off the engine takes nothing
-- from GUILD either (Sync.lua S:Receive); Cute's own channel carries what the guild sees. Party sync stays
-- The second pass (cuteDefaults 2, once for a 0.7 save too): the quest icons on the game's map at the game's own size
-- (QuestBank 5.4.4 halved them at the owner's word; half-size art beside the game's full-size pins looked soft), low-level
-- quests as the game's own option has them (not C_Minimap.IsFilteredOut(Enum.MinimapTrackingFilter.TrivialQuests), as
-- Camelot/InterfaceOverrides.lua:24 reads it; Cute never writes that option), and the minimap's flags given back from
-- the Map module's keeping: they are the Route tab's rows now (QB.MAP_FLAGS, the Map module's, is the world map's two)
QB.MAP_FLAGS = { "mapIcons", "pins" }
local MINI_FLAGS = { "minimapPins", "minimapLines", "minimapGivers", "mmExtended" }
-- (the hud review) whether this account chose the Camp module on some character (its box saved, Cute's own
-- CuteDB.chars[*].modules, Cute/Modules.lua): 0.7's module was off by default, so a light 0.7 kept while it was off is
-- the engine's default unless someone ticked it once
local function campChosen()
  local chars = type(CuteDB) == "table" and type(CuteDB.chars) == "table" and CuteDB.chars or nil
  for _, rec in pairs(chars or {}) do
    if type(rec) == "table" and type(rec.modules) == "table" and rec.modules[ADDON .. ":camp"] ~= nil then return true end
  end
  return false
end
local function firstRun()
  local s = E:Settings()
  -- (the hud round) the engine's reminders' settings as they are now (Remind.Settings: 6.1.1's switches become Nevers,
  -- campBar remind.on), before any module's switch reads them; and a kept cuteOff.camp of 0.7 (the Camp module's
  -- switch then followed campBar, the two buffs rows and the light) rewritten: the module follows remind.on alone, and
  -- the rows it kept go back to them as kept; the light only where the account chose the module once (campChosen),
  -- else it stays off until the first-run card's Interact light row, as on a fresh install (the light changes the
  -- game's soft-target settings, Glow.lua)
  local fresh = not s.cuteDefaults
  if E.Remind and E.Remind.Settings then E.Remind.Settings() end
  local kept = type(s.cuteOff) == "table" and s.cuteOff.camp or nil
  if type(kept) == "table" and kept["remind.on"] == nil and (kept.campBar ~= nil or kept["remind.buffs"] ~= nil or kept["glow.on"] ~= nil) then
    if kept["remind.buffs"] ~= nil then s.remind.buffs = kept["remind.buffs"] end
    if kept["remind.party"] ~= nil then s.remind.party = kept["remind.party"] end
    if kept["glow.on"] ~= nil and type(s.glow) == "table" then
      if campChosen() then s.glow.on = kept["glow.on"] elseif s.glow.on == false then s.cuteLightAsks = true end
    end
    s.cuteOff.camp = { ["remind.on"] = kept.campBar ~= false }
  end
  -- (a fresh install: the interact light off until the first-run card's row says, since the engine's default is on and
  -- the light changes the game's soft-target settings, Glow.lua)
  if fresh and type(s.glow) == "table" then s.glow.on = false; s.cuteLightAsks = true end
  -- (merge3) cuteLightAsks: the light is off only until the card's row says (the row starts at its default, ticked,
  -- Setup.lua); the row's answer, Settings > Reminders' Interact light (PageCamp.lua) or a light found on clears it
  if type(s.glow) ~= "table" or s.glow.on ~= false then s.cuteLightAsks = nil end
  s.cuteGuildOff = true
  if type(s.share) == "table" then s.share.guild = false end
  if not s.cuteDefaults then
    s.cuteDefaults = true
    s.mapPage, s.post.auto, s.updates, s.clockLevelMsg, s.welcome = false, false, false, false, nil
    s.minimap.hide = true
  end
  if s.cuteDefaults == true then
    s.cuteDefaults = 2
    s.mapIconPct = 100
    -- (the step frame in place of the game's tracker: the quests you hold under the steps, three; Settings > Quests)
    if type(s.guide) == "table" and s.guide.quests == nil then s.guide.quests = 3 end
    local MF = type(Enum) == "table" and Enum.MinimapTrackingFilter or nil
    if type(C_Minimap) == "table" and type(C_Minimap.IsFilteredOut) == "function" and MF and MF.TrivialQuests then
      local ok, out = pcall(C_Minimap.IsFilteredOut, MF.TrivialQuests)
      if ok and type(out) == "boolean" then s.mapLowLevel = not out end
    end
    local kept = type(s.cuteOff) == "table" and s.cuteOff.map or nil
    if type(kept) == "table" then
      for _, key in ipairs(MINI_FLAGS) do
        if kept[key] ~= nil then s[key] = kept[key]; kept[key] = nil end
      end
    end
  end
end

-- the setup card's door (Cute/Setup.lua): the engine's settings this copy keeps (never QuestBank's), whether this account
-- saved any before this load, and the card's Start written into them. Reminders on: the switch's keeping cleared, so
-- remind.on stays as the card set it when the module comes on at the reload (Bridge's QB.Follow); the light its own
local savedBefore = false -- (read at ADDON_LOADED, before the engine fills its defaults in)
Cute.QuestSetup = {
  Settings = function() return E:Settings() end,
  Saved = function() return savedBefore end,
  -- (merge3) whether the light is off only until the card's row says (firstRun's cuteLightAsks), not by a choice
  LightAsks = function() return E:Settings().cuteLightAsks == true end,
  Apply = function(p)
    local s = E:Settings()
    if p.step ~= nil then s.guide.frame = p.step and true or false; s.arrow = p.step and true or false end
    if p.campOn then
      -- (the module on: Reminders on screen with it, its only master, PageCamp.lua's Cp.Toggle; an unticked Reminders
      -- row is the module's to answer, the card's Start choosing it)
      if type(s.cuteOff) == "table" then s.cuteOff.camp = nil end
      local r = E.Remind and E.Remind.Settings() or s.remind
      r.on = true
      s.campBar = true
    end
    -- (the interact light is its own row, whatever the Reminders row says)
    if p.light ~= nil then s.glow.on = p.light and true or false; s.cuteLightAsks = nil end
    if p.accept then s.autoAccept = p.accept end
    if p.handin ~= nil then s.autoTurnIn = p.handin and true or false end
  end,
}

-- PLAYER_ENTERING_WORLD for the engine's frames that wait on it (the light's settings, the minimap's size and tracking,
-- the timers' session, the travel guide's re-plan, the arrow's dungeon check, ...): Cute loads this addon from its own
-- handler of that event at a login or a /reload, and in play when a module is ticked, so they register for it while it
-- is under way or long after it. Replayed a frame later to each frame that has not heard it since the load (one the
-- game did deliver to is left alone), as QUEST_LOG_UPDATE is below
local function enteringWorld()
  local frames = {}
  for _, key in ipairs({ "Camp", "Discover", "Game", "Legacy", "Glow", "Loot", "Target", "Survey", "Timer", "Travel", "Walk", "Arrow", "Mini" }) do
    local m = E[key]
    if type(m) == "table" then
      for _, field in ipairs({ "frame", "eventFrame", "trackFrame" }) do
        local fr = m[field]
        if type(fr) == "table" and fr.GetScript and fr:GetScript("OnEvent") then frames[#frames + 1] = fr end
      end
    end
  end
  local heard = {}
  for _, fr in ipairs(frames) do
    fr:HookScript("OnEvent", function(self, event) if event == "PLAYER_ENTERING_WORLD" then heard[self] = true end end)
  end
  C_Timer.After(0, E.Safe(function()
    for _, fr in ipairs(frames) do
      local h = not heard[fr] and fr:GetScript("OnEvent")
      if h then h(fr, "PLAYER_ENTERING_WORLD") end
    end
  end, "cute quest: entering the world"))
end

-- the login: this addon is loaded on demand, after PLAYER_LOGIN; the engine's login runs from here once the saved
-- variables are in (ADDON_LOADED, after Shim.lua's alias and Core.lua's QB:Settings)
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", E.Safe(function(self, _, name)
  if name ~= ADDON then return end
  self:UnregisterEvent("ADDON_LOADED")
  savedBefore = type(CuteQuestDB) == "table" and type(CuteQuestDB.settings) == "table" and next(CuteQuestDB.settings) ~= nil
  firstRun()
  -- the modules' switches, now on the saved table (before the engine's login: its files read the flags as they start)
  for id, fn in pairs(QB.Toggles) do fn(Cute.ModuleOn(id)) end
  -- (the layout round) the on-screen pieces under Cute's layout (Cute/Layout.lua): one lock for them all, which the
  -- pieces' own drags and the step frame's menu ask and set (QB.LayoutLocked, QB.SetLayoutLocked), and their movers
  -- (QB.Movers); this character's layout into the engine's settings before the login places them
  local layout = Cute.Layout
  if type(layout) == "table" then
    E.LayoutLocked, E.SetLayoutLocked = layout.Locked, layout.SetLocked
    layout.Attach(E.Movers)
  end
  E:Login()
  -- (sub-project G) the guild's finds: Cute's door (Cute/Finds.lua) is the engine's host (Finds.lua Finds.host), told what
  -- you find and drawn with yours on the map; attached after the engine's login, once the data file's rows are in, so
  -- what QuestBank's data carries now leaves the guild's
  if E.Finds and Cute.Finds and Cute.Finds.Attach then
    E.Finds.host = Cute.Finds
    Cute.Finds.Attach({
      Known = E.Finds.Known,
      Tally = function() if E.MapPage and E.MapPage.FindTally then return E.MapPage.FindTally() end return 0, 0 end,
      Changed = function() local MP = E.MapPage; if MP and MP.finds and MP.canvas and MP.canvas:IsVisible() then MP.finds:RefreshAllData() end end,
      ShowFinds = function() if QB.MapWin then QB.MapWin.OpenFinds() end end,
    })
  end
  enteringWorld()
  -- the engine takes the log as read at the game's next QUEST_LOG_UPDATE, which after PLAYER_LOGIN comes at once;
  -- loaded on demand in the middle of a session it could wait minutes for one, so the log is read now
  if not E.logReady and E.eventFrame then
    local handler = E.eventFrame:GetScript("OnEvent")
    if handler then handler(E.eventFrame, "QUEST_LOG_UPDATE") end
  end
end, "cute quest: login"))

-- /qb and /questbank: the pages Cute has, by name; everything else is the engine's own command (skip, way, done,
-- arrow, trace...)
local engineSlash = SlashCmdList.QUESTBANK
local WORD = { [""] = "quests", route = "route", prep = "quests", plan = "quests", available = "quests", journal = "journal", gear = "gear", map = "map", maps = "map", settings = "settings", options = "settings" }
SlashCmdList.QUESTBANK = function(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd = msg:match("^(%S*)"):lower()
  local page = WORD[cmd]
  -- (/qb map with the Map module off: the Quests tab, as 0.7 did; /qb map <zone> is the engine's own, which opens tab 8)
  if page == "map" and not Cute.ModuleOn("map") then page = "quests" end
  if page and (cmd == msg:lower() or cmd == "") then Cute.Open(page, page == "settings" and "quests" or nil) return end
  if engineSlash then engineSlash(msg) end
end
