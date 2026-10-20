-- SPDX-License-Identifier: GPL-3.0-or-later
-- Modules: the window's pages and what joins them. Cute's core is the shell (the window and its tabs, the flat skin,
-- Settings, the guild channel, the roster, the policy, the stats registry and the knowledge model); every page
-- registers itself here, and the tabs and Settings' sections are drawn from this list:
--   C:RegisterModule({ id, title, order, page, settings, stats, events, officer, builtin, default })
--   page      function(ui, scroll): draws into the shared scroll area and the band with the window's own pieces
--             (UI.Button, UI.Check, UI.Text, UI.FitText, the pools and virtual lists, ui:SetBand), so it looks like
--             one addon
--   settings  function(ui, column): its own section in Settings, drawn with the column Settings.lua hands it
--   stats     function(D): registry entries, D as Stats.lua's S.def; defined the first time the module is on in a
--             session and kept until the next login
--   events    { EVENT = function(...) }: heard while the module is on
--   officer   for officer ranks only: no tab and no section for members
-- Three kinds:
--   core      the dashboard (Race, Prog, Hall of Shame, Statistics, Officers, Me): always on, never listed
--   built-in  shipped inside Cute, switched on in Settings > Modules (the Guide, off on a fresh install)
--   external  an addon folder of its own whose toc says "## Dependencies: Cute" and "## X-Cute-Module: 1", ideally
--             "## LoadOnDemand: 1": listed in Settings > Modules from the client's addon list (C_AddOns, documented
--             in Forever's AddOnsDocumentation.lua) and loaded with C_AddOns.LoadAddOn when switched on, no reload;
--             its files call Cute:RegisterModule as they load. Switched off, its tab, section and events go at once
--             and it is not loaded at the next login (Cute loads only what is on, and the game's AddOns list has it
--             off for this character)
-- The choice is per character (CuteDB.chars[me].modules, by module id or, for an external one, its folder). Every
-- character starts with the dashboard alone, one that ran 0.5.x, where the Guide was a fixed tab, too.
local _, C = ...
local M = { list = {}, byId = {}, found = {}, failed = {}, pending = {} }
C.Modules = M

-- Settings' own sections and the Settings tab: no module takes these ids
local RESERVED = { settings = true, general = true, vis = true, rules = true, modules = true }

local function note(msg) C.Err.Note(msg, "modules") end
local function sortList()
  table.sort(M.list, function(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.id < b.id
  end)
end

-- this character's choices: key = a module id, or an external module's folder; true or false, nil for its default
local function choices()
  local ch = C.Char()
  if type(ch.modules) ~= "table" then ch.modules = {} end
  return ch.modules
end

----------------------------------------------------------------------------
-- registering
----------------------------------------------------------------------------
function C:RegisterModule(def)
  if type(def) ~= "table" or type(def.id) ~= "string" or not def.id:match("^[%l%d_]+$") or #def.id > 24
    or type(def.title) ~= "string" or def.title == "" then
    note("a module without a lowercase id or a title was not registered")
    return false
  end
  local id = def.id
  if RESERVED[id] or M.byId[id] then note("module " .. id .. " was not registered: the id is taken"); return false end
  for _, k in ipairs({ "page", "settings", "stats" }) do
    if def[k] ~= nil and type(def[k]) ~= "function" then note("module " .. id .. " was not registered: " .. k .. " is no function"); return false end
  end
  if def.events ~= nil and type(def.events) ~= "table" then note("module " .. id .. " was not registered: events is no table"); return false end
  def.order = tonumber(def.order) or 100
  if not (def.core or def.builtin) then
    -- an external module: the folder it came from, as it says or as Cute is loading it now
    def.addon = type(def.addon) == "string" and def.addon or M.loading
    if not def.addon then note("module " .. id .. " was not registered: no addon folder named"); return false end
  end
  def.key = def.addon or id
  def.active = def.core == true -- (the dashboard is on from the start; the rest as Apply finds them)
  M.byId[id] = def
  M.list[#M.list + 1] = def
  sortList()
  if M.started then M.Apply(def) end
  if C.UI and C.UI.frame and C.UI.frame:IsShown() then C.UI:Refresh() end
  return true
end

-- the one global Cute makes for module addons: Cute:RegisterModule({ ... }) from their own files, external always
Cute = { version = C.version }
function Cute:RegisterModule(def)
  -- (an external module is never core nor built in, and starts off: a fresh install starts with the dashboard)
  if type(def) == "table" then def.core, def.builtin, def.default = nil, nil, nil end
  return C:RegisterModule(def)
end

----------------------------------------------------------------------------
-- on and off
----------------------------------------------------------------------------
-- whether a module (or an external module's folder, by key) is on for this character
function M.OnKey(key, default)
  local v = choices()[key]
  if v == nil then return default == true end
  return v == true
end
function M.On(def)
  if def.core then return true end
  return M.OnKey(def.key, def.default)
end

-- the stats a module defines, in Stats.lua's registry and read like the rest (Sample.lua adopts them once it runs)
local function defineStats(def)
  if def.statsDone or not def.stats then return end
  def.statsDone = true
  local new = {}
  def.stats(function(id, label, cat, o)
    local d = C.Stats.def(id, label, cat, o)
    d.module = def.id
    new[#new + 1] = d
    return d
  end)
  if #new > 0 and C.Sample and C.Sample.Adopt then C.Sample:Adopt(new) end
end

-- the module's live state made to match its choice: its stats (once a session) and its events
function M.Apply(def)
  local on = M.On(def)
  if on == def.active then return end
  def.active = on
  if on then
    C.Safe(defineStats, "module " .. def.id .. ": stats")(def)
    if def.events and next(def.events) then
      if not def.frame then
        def.frame = CreateFrame("Frame")
        def.frame:SetScript("OnEvent", C.Safe(function(_, event, ...)
          local fn = def.active and def.events[event]
          if type(fn) == "function" then fn(...) end
        end, "module " .. def.id .. ": event"))
      end
      for event in pairs(def.events) do pcall(def.frame.RegisterEvent, def.frame, event) end
    end
  elseif def.frame then
    for event in pairs(def.events) do pcall(def.frame.UnregisterEvent, def.frame, event) end
  end
end

-- a module whose page shows for this viewer: on, registered, and an officer's where it is for officers
function M.Page(id, officer)
  local def = M.byId[id]
  if def and def.page and def.active and (not def.officer or officer) then return def end
  return nil
end
function M.Pages(officer)
  local out = {}
  for _, def in ipairs(M.list) do if M.Page(def.id, officer) then out[#out + 1] = def end end
  return out
end
-- the modules with a Settings section for this viewer
function M.Sections(officer)
  local out = {}
  for _, def in ipairs(M.list) do
    if def.settings and def.active and (not def.officer or officer) then out[#out + 1] = def end
  end
  return out
end

----------------------------------------------------------------------------
-- module addons: found in the client's addon list, loaded on demand
----------------------------------------------------------------------------
local function addons() return type(C_AddOns) == "table" and C_AddOns or nil end
-- the character the game's AddOns list keeps a choice for: the GUID, as the mainline client's own code passes it
-- (Blizzard_Minimap/Mainline/AddonCompartment.lua:79, GetAddOnEnableState(addonIndex, UnitGUID("player")))
local function character() return C.MyGUID() or C.Get(UnitName, "player") end
local function save()
  local A = addons()
  if A and type(A.SaveAddOns) == "function" then pcall(A.SaveAddOns) end
end
local function plainTitle(s, fallback)
  s = C.Plain(s)
  if type(s) ~= "string" or s == "" or C.IsKstring(s) then return fallback end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return s ~= "" and s or fallback
end
-- does the addon at index i name Cute among its dependencies (where the client can say)
local function needsCute(A, i)
  if type(A.GetAddOnDependencies) ~= "function" then return true end
  local deps = { C.Get(A.GetAddOnDependencies, i) }
  for _, d in ipairs(deps) do if type(d) == "string" and d:lower() == "cute" then return true end end
  return false
end
-- every module addon the client lists: { name, title, notes, lod }. Asked once a session, at the first loading screen
-- (the list does not change while you play)
function M.Scan()
  local A, out = addons(), {}
  if not (A and type(A.GetNumAddOns) == "function" and type(A.GetAddOnInfo) == "function" and type(A.GetAddOnMetadata) == "function") then return out end
  local n = C.Num(A.GetNumAddOns) or 0
  for i = 1, math.min(n, 500) do
    local name, title, notes = C.Get(A.GetAddOnInfo, i)
    if type(name) == "string" and name ~= "" and name:lower() ~= "cute" and tonumber(C.Get(A.GetAddOnMetadata, i, "X-Cute-Module")) == 1 and needsCute(A, i) then
      out[#out + 1] = { name = name, title = plainTitle(title, name), notes = plainTitle(notes, nil),
        lod = type(A.IsAddOnLoadOnDemand) == "function" and C.Get(A.IsAddOnLoadOnDemand, i) == true }
    end
  end
  table.sort(out, function(a, b) return a.title:lower() < b.title:lower() end)
  return out
end
function M.Found(name) for _, a in ipairs(M.found) do if a.name == name then return a end end end
local function loaded(name)
  local A = addons()
  return A and type(A.IsAddOnLoaded) == "function" and C.Get(A.IsAddOnLoaded, name) == true or false
end
local function registered(name) for _, def in ipairs(M.list) do if def.addon == name then return def end end end

-- the game's AddOns list for this character: on before Cute loads one (a module switched off before is off there),
-- off when it is switched off, so a module that is no LoadOnDemand one stays out at the next login too
local function enable(name, on)
  local A = addons()
  if not A then return end
  local me = character()
  if on then
    local state = type(A.GetAddOnEnableState) == "function" and C.Get(A.GetAddOnEnableState, name, me) or nil
    if type(state) == "number" and state > 0 then return end
    if type(A.EnableAddOn) == "function" and pcall(A.EnableAddOn, name, me) then save() end
  elseif type(A.DisableAddOn) == "function" and pcall(A.DisableAddOn, name, me) then save() end
end

-- the regen frame: a module switched on in combat loads when combat ends (loading one may make frames, and Cute
-- changes nothing secure in combat)
local regen
local function inCombat() return C.Callable("InCombatLockdown") and C.Get(InCombatLockdown) == true end
function M.Load(name)
  local A = addons()
  if not (A and type(A.LoadAddOn) == "function") then M.failed[name] = "C_AddOns.LoadAddOn is missing on this client"; return end
  if inCombat() then
    M.pending[name] = true
    if not regen then
      regen = CreateFrame("Frame")
      regen:SetScript("OnEvent", C.Safe(function()
        pcall(regen.UnregisterEvent, regen, "PLAYER_REGEN_ENABLED")
        for n in pairs(M.pending) do M.pending[n] = nil; if M.OnKey(n) then M.Load(n) end end
        if C.UI and C.UI.frame and C.UI.frame:IsShown() then C.UI:Draw() end
      end, "modules: after combat"))
    end
    pcall(regen.RegisterEvent, regen, "PLAYER_REGEN_ENABLED")
    return
  end
  M.pending[name] = nil
  enable(name, true)
  if loaded(name) then return end
  M.loading, C.lastErr = name, nil
  local ok, why = C.Get(A.LoadAddOn, name)
  M.loading = nil
  if ok then M.failed[name] = nil
  else
    -- the client's own words for why, where it has them (ADDON_DISABLED, ADDON_MISSING...)
    local reason = type(why) == "string" and why or (C.lastErr or "unknown")
    local said = C.Plain(_G["ADDON_" .. reason])
    M.failed[name] = type(said) == "string" and said ~= "" and said or reason
    note("module " .. name .. " did not load: " .. M.failed[name])
  end
end

-- this character's choice set, and made true at once: a built-in module's tab, section and events come and go now; an
-- external one is loaded now (or after combat) and registers as it loads, and off it is off in the game's AddOns list
function M.Set(key, on)
  on = on and true or false
  choices()[key] = on
  for _, def in ipairs(M.list) do if def.key == key then M.Apply(def) end end
  if M.Found(key) then
    if on then if not registered(key) then M.Load(key) else enable(key, true) end
    else M.pending[key] = nil; enable(key, false) end
  end
  if C.UI and C.UI.frame and C.UI.frame:IsShown() then C.UI:Draw() end
end

-- what Settings > Modules lists: the built-in modules and the module addons the client has, each { key, title, on,
-- status, notes }; an external one is named by its toc until it registers
function M.Available(officer)
  local out = {}
  for _, def in ipairs(M.list) do
    if def.builtin and (not def.officer or officer) then out[#out + 1] = { key = def.key, title = def.title, notes = def.notes, def = def } end
  end
  for _, a in ipairs(M.found) do
    local def = registered(a.name)
    if not (def and def.officer and not officer) then
      out[#out + 1] = { key = a.name, title = def and def.title or a.title, notes = (def and def.notes) or a.notes, def = def, addon = a }
    end
  end
  for _, e in ipairs(out) do
    e.on = M.OnKey(e.key, e.def and e.def.default)
    -- a few words where something is not as the box says: waiting for combat to end, refused by the client, loaded
    -- but never registered, or switched off with stats that stay until the next login
    if e.on and M.pending[e.key] then e.status = "loads after combat"
    elseif e.on and M.failed[e.key] then e.status = "did not load: " .. M.failed[e.key]
    elseif e.on and e.addon and not e.def and loaded(e.key) then e.status = "loaded, no page"
    elseif not e.on and e.def and e.def.statsDone then e.status = "its stats leave at the next login" end
  end
  return out
end

-- at the first loading screen of a session: the built-in modules that are on start, the module addons are found, and
-- the ones on for this character load. One the player switched off in the game's AddOns list since is the player's
-- word: its box goes unticked, and only a tick in Settings turns it on again
local function offInList(name)
  local A = addons()
  local state = A and type(A.GetAddOnEnableState) == "function" and C.Get(A.GetAddOnEnableState, name, character()) or nil
  return state == 0
end
function M.Start()
  if M.started then return end
  M.started = true
  for _, def in ipairs(M.list) do M.Apply(def) end
  M.found = M.Scan()
  for _, a in ipairs(M.found) do
    if M.OnKey(a.name) and not registered(a.name) then
      if offInList(a.name) then choices()[a.name] = false else M.Load(a.name) end
    end
  end
end
