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
  end
  return
end
QB.Engine = QB
local E = QB
local UI = E.UI
-- the engine's chat lines carry Cute's prefix; and the copy is quiet (Core.lua QB.quiet): a quest complete or gone from
-- the log, a waypoint clicked, a run's start and end and the errors line stay out of chat, since the step frame and
-- the arrow say those things
function E:Print(msg) Cute.Print(msg) end
E.quiet = true
-- the engine's words name the host: "Choose a reward: X is Cute's pick", "Nothing to do: /cute quests", the minimap
-- menu's "Cute settings"; and they leave out the /qb commands a Cute player is never told of (host: Settings alone)
E.NAME, E.CMD, E.host = "Cute", "/cute quests", true
-- the minimap is the engine's only while Cute's Map module is on (Minimap.lua, Mini.Owned): its wheel, Ctrl-wheel,
-- Alt-drag, right-click menu, size and place, and the tracking menu's Target; off, the game's own
function E.MapOn() return Cute.ModuleOn("map") end

-- the engine's errors on Cute's list too (/cute errors), through Cute's public Cute.Safe: an error raised inside it is
-- recorded with where it happened (Cute says so once a session, as for its own). A call the game blocked goes there as
-- well, and nowhere else (Core.lua's Err.Blocked says nothing in chat). Under CUTE_DEV (the harness) Cute.Safe raises:
-- the pcall keeps the engine's own record going either way
local function toCute(msg, where)
  pcall(Cute.Safe(function() error(msg, 0) end, "quest engine: " .. tostring(where or "?")))
end
local record, blocked = E.Err.Record, E.Err.Blocked
function E.Err.Record(msg, stack, where)
  record(msg, stack, where)
  toCute(msg, where)
end
function E.Err.Blocked(event, who, fn, stack)
  local kept = blocked(event, who, fn, stack)
  if kept then
    toCute(string.format("the game %s %s%s", event == "ADDON_ACTION_FORBIDDEN" and "forbade" or "blocked", tostring(E.Plain(fn) or "?"),
      (InCombatLockdown and InCombatLockdown()) and " in combat" or ""), "blocked call")
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
-- as Cute's pages; a page whose module is off (Route, the Guide, Journal) is the Quests page (Cute's own way with an
-- off page is Race: a travel, train, grind or corpse step clicked in the step frame opened the guild's table)
local PAGE = { [1] = "quests", [2] = "quests", [3] = "route", [4] = "guide", [5] = "settings", [6] = "quests", [7] = "journal", [8] = "quests" }
local function pageOf(tab)
  local page = PAGE[tab] or "quests"
  if page ~= "quests" and page ~= "settings" and not Cute.ModuleOn(page) then page = "quests" end
  return page
end
function UI:Open(tab) Cute.Open(pageOf(tab), tab == 5 and "quests" or nil) end
-- the page a click opens, by name, for the engine's words ("Click: the Quests page.": Arrow.lua)
local TITLE = { quests = "Quests", route = "Route", guide = "Guide", settings = "Settings", journal = "Journal" }
function UI.PageName(tab) return TITLE[pageOf(tab)] or "Quests" end
function UI:ShowTab(tab) self:Open(tab) end
function UI:TogglePage(tab) self:Open(tab) end
function UI:Toggle() Cute.Open("quests") end
function UI:Refresh() Cute.Refresh() end
function UI.OpenMap() if type(ToggleWorldMap) == "function" then ToggleWorldMap() end end
function UI.MapPageOn() return false end
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
-- level-up line, no welcome card (the choices are Settings rows), no minimap button (Cute has one). And, once for a
-- fresh install and once for a 0.7 save (0.7.0 shipped it on), no sharing with the whole guild: the engine's 1S (level,
-- XP, class, GUID), 1Q (every quest and its progress) and 1R went to GUILD around the officers' Who sees what; Cute's
-- own channel carries what the guild sees. Party sync stays
local function firstRun()
  local s = E:Settings()
  if not s.cuteGuildOff then
    s.cuteGuildOff = true
    if type(s.share) == "table" then s.share.guild = false end
  end
  if s.cuteDefaults then return end
  s.cuteDefaults = true
  s.mapPage, s.post.auto, s.updates, s.clockLevelMsg, s.welcome = false, false, false, false, nil
  s.minimap.hide = true
end

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
  firstRun()
  -- the modules' switches, now on the saved table (before the engine's login: its files read the flags as they start)
  for id, fn in pairs(QB.Toggles) do fn(Cute.ModuleOn(id)) end
  E:Login()
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
local WORD = { [""] = "quests", route = "route", prep = "quests", plan = "quests", available = "quests", journal = "journal", gear = "gear", map = "quests", maps = "quests", settings = "settings", options = "settings" }
SlashCmdList.QUESTBANK = function(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd = msg:match("^(%S*)"):lower()
  local page = WORD[cmd]
  if page and (cmd == msg:lower() or cmd == "") then Cute.Open(page, page == "settings" and "quests" or nil) return end
  if engineSlash then engineSlash(msg) end
end
