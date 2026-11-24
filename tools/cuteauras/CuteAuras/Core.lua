-- SPDX-License-Identifier: GPL-3.0-or-later
-- Cute Auras: the buffs of a camp, your own, the ones you give, a paladin's blessings, and what to put back after a death
-- or a Hand. Built from QuestBank's camp and reminders (Camp.lua, Remind.lua) as a standalone addon for the Cute page.
-- This file: the namespace, the saved settings (CuteAurasDB), events, the guards for the client's secret values, the
-- work kept for after a fight, and the slash commands. Each other file adds one part (see the toc's order).
local ADDON, A = ...
A.version = "0.2.1"
A.NAME = "Cute Auras"
A.ADDON = ADDON
CuteAuras = A -- (for /dump and for QuestBank's and Cute's step-aside, which ask C_AddOns first)

----------------------------------------------------------------------------
-- secret values: Forever's client hides some answers in a fight (Midnight's secret values). A secret is never compared,
-- indexed or concatenated: plain() turns it into nil
----------------------------------------------------------------------------
local issecret = issecretvalue
local function plain(v)
  if v ~= nil and issecret and issecret(v) then return nil end
  return v
end
A.Plain = plain
-- a call whose first answer is plain true
function A.Yes(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, v = pcall(fn, ...)
  return ok and plain(v) == true
end
-- a call's answers, nil where it failed (pcall's ok dropped)
function A.Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  return select(2, pcall(fn, ...))
end
function A.Now() return GetTime and GetTime() or 0 end
function A.Fighting() return InCombatLockdown and InCombatLockdown() or false end

----------------------------------------------------------------------------
-- errors: a part's error stops that part's call alone and lands in /cauras errors, never a Lua error popup (the game's
-- own is hidden while scriptErrors is off, so an error that escaped would show nowhere). One error a message: an
-- OnUpdate's error comes every frame, so a repeat counts up on its first line instead of pushing the others out. The
-- last 20 kinds are kept in CuteAurasDB.errors (from PLAYER_LOGIN on), so a tester's /reload or logout keeps them
-- for the owner; a new version starts a clean list. A wrapped call answers nothing, so a menu's callback wrapped in
-- it still closes its menu (MenuUtil reads a callback's answer as what the menu does next)
----------------------------------------------------------------------------
local MAX_ERRORS = 20
A.errors = {}
local seenError = {}
local function now() return type(time) == "function" and time() or 0 end
local function noteError(where, err)
  local msg = (where or "?") .. ": " .. ((issecret and issecret(err)) and "(a secret value)" or tostring(err))
  local list = A.errors
  local e = seenError[msg]
  if e then
    e.n = (e.n or 1) + 1
    e.last = now()
    return
  end
  if #list >= MAX_ERRORS then
    local gone = table.remove(list, 1)
    if type(gone) == "table" then seenError[gone.msg] = nil end
  end
  e = { msg = msg, n = 1, first = now(), v = A.version }
  e.last = e.first
  list[#list + 1] = e
  seenError[msg] = e
  if A.debug and DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffff6060Cute Auras|r " .. msg) end
end
function A.Safe(fn, where)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then noteError(where, err) end
  end
end
-- the saved list: this version's errors from before, then the ones caught since the files loaded
local function keepErrors()
  local saved = type(CuteAurasDB.errors) == "table" and CuteAurasDB.errors or {}
  local list = {}
  for k in pairs(seenError) do seenError[k] = nil end
  for _, e in ipairs(saved) do
    if type(e) == "table" and type(e.msg) == "string" and e.v == A.version and not seenError[e.msg] then
      list[#list + 1] = e
      seenError[e.msg] = e
    end
  end
  for _, e in ipairs(A.errors) do
    local had = seenError[e.msg]
    if had then had.n = (had.n or 1) + (e.n or 1); had.last = e.last
    else list[#list + 1] = e; seenError[e.msg] = e end
  end
  while #list > MAX_ERRORS do seenError[table.remove(list, 1).msg] = nil end
  CuteAurasDB.errors = list
  A.errors = list
end
-- how many kinds and how many times in all
function A.ErrorCount()
  local total = 0
  for _, e in ipairs(A.errors) do total = total + (e.n or 1) end
  return #A.errors, total
end
function A.ClearErrors()
  for i = #A.errors, 1, -1 do A.errors[i] = nil end
  for k in pairs(seenError) do seenError[k] = nil end
end

----------------------------------------------------------------------------
-- settings: CuteAurasDB.settings, account-wide; CuteAurasDB.chars[GUID], this character's (meals learned, habits, your
-- role, Swap for me, the group saved over a reload)
----------------------------------------------------------------------------
A.DEFAULTS = {
  on = true,                -- the bar
  camp = true, mine = true, group = true, pull = true, -- its parts, and Before the pull on a ready check
  others = true,            -- in yours: a buff a member gives that you lack, their name under it
  instance = "buffs",       -- in dungeons and raids: "buffs" (no camp), "all", "none"
  fight = "group",          -- in a fight: the group's icons stay ("group") or the whole bar hides ("hide")
  scale = 1,                -- the bar's size (0.5 to 2)
  alerts = true,            -- the alerts overlay
  alertSize = "normal",     -- small, normal, big
  alertScale = 1,
  rebuff = true,            -- buff again after a resurrection in a fight
  hands = true,             -- Blessing of Protection, Freedom and Sacrifice: countdown and restore
  sound = true,
  blessings = true,         -- paladins: blessings shared out by Cute Auras
  greater = true,           -- Greater blessings for three or more of a class, with Symbol of Kings
  blueprints = true,        -- blueprints you can use, at a fire
  features = true,          -- camp items you can place at the fire near you
  minimap = true,           -- the minimap button
  consume = "instance",     -- potions, elixirs, flasks, scrolls you keep up, and Well Fed: "always" (out of town),
                            -- "instance" (dungeons and raids), "pull" (the ready check only), "off"
}
local function copyDefaults(t, d)
  for k, v in pairs(d) do if t[k] == nil then t[k] = v end end
end
function A.Settings()
  CuteAurasDB = type(CuteAurasDB) == "table" and CuteAurasDB or {}
  local s = CuteAurasDB.settings
  if type(s) ~= "table" then s = {}; CuteAurasDB.settings = s end
  copyDefaults(s, A.DEFAULTS)
  if type(s.never) ~= "table" then s.never = {} end
  if type(s.opt) ~= "table" then s.opt = {} end
  -- (your role is each character's, A.Char().role: an old account-wide one is let go, since which character chose it
  -- can't be told, so no alt announces another's role)
  s.role = nil
  return s
end
local meGUID
function A.MyGUID()
  if meGUID then return meGUID end
  local g = plain(A.Call(UnitGUID, "player"))
  if type(g) == "string" then meGUID = g end
  return meGUID
end
function A.Char()
  CuteAurasDB = type(CuteAurasDB) == "table" and CuteAurasDB or {}
  CuteAurasDB.chars = type(CuteAurasDB.chars) == "table" and CuteAurasDB.chars or {}
  local key = A.MyGUID() or "?"
  local c = CuteAurasDB.chars[key]
  if type(c) ~= "table" then c = {}; CuteAurasDB.chars[key] = c end
  return c
end
-- (the account's: meals that gave Well Fed or did not)
function A.Acct()
  CuteAurasDB = type(CuteAurasDB) == "table" and CuteAurasDB or {}
  if type(CuteAurasDB.acct) ~= "table" then CuteAurasDB.acct = {} end
  return CuteAurasDB.acct
end

----------------------------------------------------------------------------
-- events: A.On(event, fn) adds a handler; a unit event for one unit has its own frame (RegisterUnitEvent), so the main
-- frame never hears every unit's
----------------------------------------------------------------------------
local handlers = {}
local frame = CreateFrame("Frame", "CuteAurasEvents")
A.frame = frame
frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do list[i](event, ...) end
end)
function A.On(event, fn, where)
  local list = handlers[event]
  if not list then
    list = {}
    handlers[event] = list
    pcall(frame.RegisterEvent, frame, event)
  end
  list[#list + 1] = A.Safe(fn, where or event)
end
local unitFrames = {}
function A.OnUnit(event, units, fn, where)
  local key = event .. ":" .. table.concat(units, ",")
  local f = unitFrames[key]
  if not f then
    f = CreateFrame("Frame")
    unitFrames[key] = f
    f.list = {}
    f:SetScript("OnEvent", function(_, ev, ...) for i = 1, #f.list do f.list[i](ev, ...) end end)
    if f.RegisterUnitEvent then pcall(f.RegisterUnitEvent, f, event, unpack(units)) else pcall(f.RegisterEvent, f, event) end
  end
  f.list[#f.list + 1] = A.Safe(fn, where or event)
end
function A.After(seconds, fn, where)
  local safe = A.Safe(fn, where or "timer")
  if C_Timer and C_Timer.After then C_Timer.After(seconds, safe) else safe() end
end

----------------------------------------------------------------------------
-- work for after a fight: the game's secure buttons are set, shown, moved and sized out of a fight only. A part that
-- meets a fight queues its work by key (the last one for a key wins) and it runs as the fight ends
----------------------------------------------------------------------------
local later, laterOrder = {}, {}
function A.OutOfFight(key, fn)
  if not A.Fighting() then fn() return true end
  if not later[key] then laterOrder[#laterOrder + 1] = key end
  later[key] = fn
  return false
end
A.On("PLAYER_REGEN_ENABLED", function()
  local keys = laterOrder
  laterOrder = {}
  for _, key in ipairs(keys) do
    local fn = later[key]
    later[key] = nil
    if fn then A.Safe(fn, "after the fight: " .. key)() end
  end
end)

----------------------------------------------------------------------------
-- start: the parts' Init in the toc's order once the saved variables are in (PLAYER_LOGIN), each on its own
----------------------------------------------------------------------------
A.parts = {}
function A.Part(name, part)
  part.name = name
  A.parts[#A.parts + 1] = part
  A[name] = part
  return part
end
A.On("PLAYER_LOGIN", function()
  A.Settings()
  keepErrors()
  for _, p in ipairs(A.parts) do
    if p.Init then A.Safe(function() p:Init() end, p.name .. ": start")() end
  end
  A.ready = true
end)

----------------------------------------------------------------------------
-- the chat line: Cute Auras' own word in the chat frame, for the slash commands' replies and what a click can't show
-- (Move's and Test's way back, a full Never list)
----------------------------------------------------------------------------
function A.Say(msg)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffff9ad5Cute Auras|r " .. tostring(msg)) end
end

-- /cauras (and /cuteauras): the window; move: the pieces' handles; test: sample alerts; grid: the blessings;
-- minimap: the minimap button shown or hidden; diag: what the client answers; errors: the last errors (errors clear:
-- forget them)
SLASH_CUTEAURAS1, SLASH_CUTEAURAS2 = "/cauras", "/cuteauras"
SlashCmdList.CUTEAURAS = A.Safe(function(msg)
  msg = (type(msg) == "string" and msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "move" then if A.Settings_ then A.Settings_.Move(true) end
  elseif msg == "test" then if A.Alerts then A.Alerts.Test() end
  elseif msg == "grid" or msg == "blessings" then if A.Window then A.Window.Open("blessings") end
  elseif msg == "diag" then if A.Diag then A.Diag() end
  elseif msg == "errors" then
    if #A.errors == 0 then A.Say("No errors.") end
    for _, e in ipairs(A.errors) do A.Say(e.msg .. ((e.n or 1) > 1 and (" (" .. e.n .. " times)") or "")) end
  elseif msg == "errors clear" then A.ClearErrors(); A.Say("Errors cleared.")
  elseif msg == "refresh" then if A.Bar then A.Bar.Refresh() end
  elseif msg == "minimap" then
    local s = A.Settings()
    s.minimap = s.minimap == false
    if A.Minimap then A.Minimap.Update() end
    A.Say(s.minimap and "Minimap button shown." or "Minimap button hidden. /cauras minimap shows it again.")
    if A.Window then A.Window.Refresh() end
  else if A.Window then A.Window.Open("settings") end end
end, "slash command")
