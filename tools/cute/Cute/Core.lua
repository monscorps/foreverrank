-- SPDX-License-Identifier: GPL-3.0-or-later
-- Cute: the guild dashboard of <Cute>. Every member's client reads about a hundred and ten facts about its own
-- character (Stats.lua), shares them with the guild on the game's addon channel (Comm.lua), keeps everyone's last
-- known values (Roster.lua) and shows the whole guild in one window (UI.lua). Officers decide, stat by stat, whether
-- members see each other's (Policy.lua). Nothing leaves the guild channel; there is no server.
local ADDON, C = ...
C.version = "0.2.0"
C.REGVER = 2 -- the stat registry's wire version (informational: a client ignores ids it does not know)
C.COLOR = "|cffe8b24a"

----------------------------------------------------------------------------
-- errors: caught where Cute runs code, recorded with the stack, never in your way. /cute errors lists them.
-- (CUTE_DEV makes them fatal again, for the test harness.)
----------------------------------------------------------------------------
local Err = {}
C.Err = Err
local toldErrors = false

local function catch(e)
  local stack = (debugstack and debugstack(2, 16, 4)) or (debug and debug.traceback and debug.traceback("", 2)) or ""
  return { msg = tostring(e), stack = stack }
end

-- quiet: a diagnostic worth listing under /cute errors without the chat line (a client function missing, say)
function Err.Record(msg, stack, where, quiet)
  CuteDB = CuteDB or {}
  CuteDB.errors = CuteDB.errors or {}
  local list = CuteDB.errors
  local now = date and date("%Y-%m-%d %H:%M:%S") or ""
  for _, e in ipairs(list) do
    if e.msg == msg then e.count, e.last = e.count + 1, now; return end
  end
  table.insert(list, 1, { msg = msg, stack = stack, where = where, count = 1, first = now, last = now, version = C.version })
  while #list > 20 do table.remove(list) end
  if not toldErrors and not quiet then
    toldErrors = true
    C.Print("ran into a problem and carried on. /cute errors shows the details.")
  end
end
function Err.Note(msg, where) Err.Record(msg, "", where, true) end

-- a function that records its errors instead of raising them
function C.Safe(fn, where)
  return function(...)
    local n, args = select("#", ...), { ... }
    local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end, catch)
    if not ok then
      if CUTE_DEV then error(err.msg .. "\n" .. err.stack, 0) end
      Err.Record(err.msg, err.stack, where)
    end
  end
end

----------------------------------------------------------------------------
-- the client's values: a secret value (Midnight's restrictions) is nil to us, never compared or concatenated
----------------------------------------------------------------------------
function C.Plain(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

-- every result of a client call, each made plain. C.lastErr keeps the text when the call threw, for the tooltip.
local function plainAll(ok, ...)
  if not ok then C.lastErr = tostring((...)); return nil end
  local n = select("#", ...)
  if n <= 1 then return C.Plain((...)) end
  local t = { ... }
  for i = 1, n do t[i] = C.Plain(t[i]) end
  return unpack(t, 1, n)
end
-- a client function this client has not got: the reason goes to the tooltip (C.lastErr) and, once a session, to
-- /cute errors, so a stat that cannot be read here never shows a bare "?"
local missingTold = {}
function C.Missing(name)
  C.lastErr = name .. " is missing on this client"
  if not missingTold[name] then
    missingTold[name] = true
    Err.Note(C.lastErr, "client api")
  end
end
-- call a client function; all its results, plain; nil when it throws or is missing (a secret value reads as nil too).
-- Pass the global's name as a string ("UnitLevel") and a missing function says so instead of reading as nothing.
function C.Get(fn, ...)
  if type(fn) == "string" then
    local name = fn
    fn = _G[name]
    if type(fn) ~= "function" then C.Missing(name); return nil end
  end
  if type(fn) ~= "function" then return nil end
  return plainAll(pcall(fn, ...))
end

-- a number from the client, or nil
function C.Num(fn, ...)
  local v = C.Get(fn, ...)
  return type(v) == "number" and v or nil
end

-- a namespaced client function (C_Item.GetItemCount), looked up at call time; nil, with the reason recorded, when the
-- namespace or the function is not there
function C.Api(ns, name)
  local t = _G[ns]
  local fn = type(t) == "table" and t[name] or nil
  if type(fn) ~= "function" then C.Missing(ns .. "." .. name); return nil end
  return fn
end

-- the client functions no generated API doc lists, which Cute reads all the same (Stats.lua says on what evidence).
-- /cute api prints which of them this client has, a line to paste, so a stat leaning on a missing one can be dropped.
C.UNDOCUMENTED = { "GetInventoryItemDurability", "GetInventoryItemCount", "GetNumUnspentTalents", "DoEmote", "GetAverageItemLevel" }
function C.ApiReport()
  local have, miss = {}, {}
  for _, name in ipairs(C.UNDOCUMENTED) do
    if type(_G[name]) == "function" then have[#have + 1] = name else miss[#miss + 1] = name end
  end
  local build = ""
  if type(GetBuildInfo) == "function" then
    local v, b = C.Get(GetBuildInfo)
    if type(v) == "string" then build = " on client " .. v .. (type(b) == "string" and (" (" .. b .. ")") or "") end
  end
  return string.format("api%s: present %s | missing %s", build, #have > 0 and table.concat(have, ", ") or "none", #miss > 0 and table.concat(miss, ", ") or "none")
end

function C.Now() return (time and time()) or os.time() end

function C.Print(msg)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(C.COLOR .. "Cute|r: " .. tostring(msg)) end
end

-- you, realm-qualified, the way the guild roster and the addon channel name people ("Name-Realm")
function C.Me()
  local name, realm = C.Get(UnitFullName, "player")
  if type(name) ~= "string" then name = C.Get(UnitName, "player") end
  if type(name) ~= "string" then return nil end
  if type(realm) ~= "string" or realm == "" then realm = C.Get(GetNormalizedRealmName) end
  if type(realm) ~= "string" or realm == "" then return name, name end
  return name .. "-" .. realm, name
end

-- "Name" from "Name-Realm"
function C.Short(name) return type(name) == "string" and (name:match("^([^%-]+)") or name) or "?" end

----------------------------------------------------------------------------
-- saved variables
----------------------------------------------------------------------------
local DEFAULTS = {
  settings = { columns = {}, density = "normal", offline = true, minimap = true, main = "", sort = {} },
  roster = {}, chars = {}, errors = {},
}
local function fill(t, d)
  for k, v in pairs(d) do
    if type(v) == "table" then
      if type(t[k]) ~= "table" then t[k] = {} end
      fill(t[k], v)
    elseif t[k] == nil then t[k] = v end
  end
end
function C.InitDB()
  CuteDB = type(CuteDB) == "table" and CuteDB or {}
  fill(CuteDB, DEFAULTS)
  CuteDB.version = C.version
end
function C.Settings() return CuteDB.settings end
-- this character's own record (counters, declared role; the main is account-wide, in settings)
function C.Char()
  local me = C.Me() or "?"
  local rec = CuteDB.chars[me]
  if not rec then rec = { counters = {} }; CuteDB.chars[me] = rec end
  rec.counters = rec.counters or {}
  if rec.role == nil then
    -- 0.1.0 kept the role in the account-wide settings, where the warrior's "Tank" became the priest's: take it once
    rec.role = type(CuteDB.settings.role) == "string" and CuteDB.settings.role or ""
    CuteDB.settings.role = nil
  end
  return rec
end

----------------------------------------------------------------------------
-- events and the slash command
----------------------------------------------------------------------------
C.frame = CreateFrame("Frame")
C.frame:RegisterEvent("ADDON_LOADED")
C.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
C.frame:RegisterEvent("PLAYER_LOGOUT")
C.frame:SetScript("OnEvent", C.Safe(function(_, event, a1, a2)
  if event == "ADDON_LOADED" then
    if a1 ~= ADDON then return end
    C.InitDB()
    C.loaded = true
  elseif event == "PLAYER_ENTERING_WORLD" then
    if not C.loaded then C.InitDB(); C.loaded = true end
    -- (isInitialLogin, isReloadingUi): a /reload is not a login
    local initial, reloading = C.Plain(a1) == true, C.Plain(a2) == true
    -- each on its own, so one part failing never hides the others (the minimap button in particular)
    C.Safe(function() C.Roster:Start() end, "roster: start")()
    C.Safe(function() C.Sample:Start(initial, reloading) end, "sample: start")()
    C.Safe(function() C.Comm:Start() end, "comm: start")()
    C.Safe(function() if C.UI and C.UI.OnWorld then C.UI:OnWorld() end end, "minimap button")()
  elseif event == "PLAYER_LOGOUT" then
    if C.Sample.ReadAll then C.Sample:ReadAll() end
  end
end, "core: events"))

local function errorsList()
  local list = CuteDB and CuteDB.errors or {}
  if #list == 0 then C.Print("no errors recorded.") return end
  for _, e in ipairs(list) do
    C.Print(string.format("%s (x%d, last %s) %s", e.msg, e.count or 1, e.last or "", e.where or ""))
  end
end

SLASH_CUTE1 = "/cute"
SlashCmdList.CUTE = C.Safe(function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "settings" or msg == "options" then C.UI:Open("settings")
  elseif msg == "errors" then errorsList()
  elseif msg == "resend" then C.Comm:Ask(); C.Print("asked the guild to send their records again.")
  elseif msg == "me" then C.UI:Open("me")
  elseif msg == "api" then C.Print(C.ApiReport())
  elseif msg == "help" then
    C.Print("/cute opens the dashboard. /cute settings, /cute me, /cute resend, /cute errors, /cute api (which client functions exist here).")
  else C.UI:Toggle() end
end, "slash")

-- the key bindings (Bindings.xml)
BINDING_HEADER_CUTE = "Cute"
BINDING_NAME_CUTE_TOGGLE = "Toggle the Cute dashboard"
BINDING_NAME_CUTE_SETTINGS = "Open Cute's settings"
function Cute_Toggle() C.Safe(function() C.UI:Toggle() end, "binding")() end
function Cute_Settings() C.Safe(function() C.UI:Open("settings") end, "binding")() end
