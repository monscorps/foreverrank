-- SPDX-License-Identifier: GPL-3.0-or-later
-- Cute: the guild dashboard of <Cute>. Every member's client reads about a hundred facts about its own character
-- (Stats.lua), plus what it meets in play (the bosses it kills, the instances it enters, its factions, the slots it
-- enchants) and the game's own statistics where the client reports them, shares them with the guild on the game's
-- addon channel (Comm.lua), keeps everyone's last known values and what the guild has learned (Roster.lua, CuteDB.known)
-- and shows the whole guild in one window (UI.lua). Officers decide, stat by stat, whether members see each other's
-- (Policy.lua). Nothing leaves the guild channel; there is no server.
local ADDON, C = ...
C.version = "0.4.0"
C.REGVER = 4 -- the stat registry's wire version (informational: a client ignores ids it does not know)
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
-- the client's values: a secret value (Midnight's restrictions) is nil to us, never compared or concatenated. A raw
-- value is asked issecretvalue (or made plain) before anything compares it, nil included: the client may raise on
-- the comparison itself, which the test harness cannot show (Lua 5.1 compares a table with nil without asking it)
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

-- the client functions no generated API doc lists, which Cute reads all the same (Stats.lua says on what evidence),
-- and the ones it probes for (the statistics API, the latest achievements). /cute api prints which of them this
-- client has, a line to paste, so a stat leaning on a missing one can be dropped.
C.UNDOCUMENTED = { "GetInventoryItemID", "GetInventoryItemQuality", "GetInventoryItemDurability", "GetInventoryItemCount", "GetNumUnspentTalents", "DoEmote", "GetAverageItemLevel",
  "GetCategoryList", "GetCategoryInfo", "GetCategoryNumAchievements", "GetAchievementInfo", "GetTotalAchievementPoints",
  "GetLatestCompletedAchievements", "GetStatisticsCategoryList", "GetStatistic" }
-- a global this client has, asked without the note a Get by name leaves when it has not
function C.Callable(name) return type(_G[name]) == "function" end
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

----------------------------------------------------------------------------
-- who you are. Forever names a character with two words, "Helga Bluntforce": on camelot UnitName's second return is
-- the surname, not a realm (Blizzard_FrameXMLUtil/Camelot/NameUtil.lua, which loads on camelot only, joins the two with
-- Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR). The guild roster lists you with both words,
-- the guild channel names a sender its own way, and ClubMemberInfo.name "may be encoded as a Kstring"
-- (ClubDocumentation.lua): a |K...|k escape the font draws as the name, which is not the name's text and is never
-- compared with ==. So no name is a key: your roster member is the one marked isSelf (NeverSecret) or carrying your
-- GUID, and every full record carries its sender's GUID (the hidden "guid" stat, Stats.lua), which Roster.lua joins on.
-- Names are matched only where no GUID has come yet, loosely (C.Canon). /cute diag prints what this client gives.
----------------------------------------------------------------------------
function C.IsKstring(s) return type(s) == "string" and s:find("|K", 1, true) ~= nil end
function C.MyGUID()
  local g = C.Get(UnitGUID, "player")
  return (type(g) == "string" and g ~= "") and g or nil
end
function C.SurnameSep()
  local t = type(Constants) == "table" and Constants.CharacterNameSeparatorConsts or nil
  local sep = type(t) == "table" and C.Plain(t.CHARACTERNAME_SURNAME_SEPARATOR) or nil
  return (type(sep) == "string" and sep ~= "") and sep or " "
end
-- your names as this client gives them: the first name, the surname (nil where the client has none) and the two
-- joined as Forever shows them
function C.MyName()
  local first, second = C.Get(UnitName, "player")
  if type(first) ~= "string" or first == "" or C.IsKstring(first) then return nil end
  if type(second) == "string" and second ~= "" and not C.IsKstring(second) then return first, second, first .. C.SurnameSep() .. second end
  return first, nil, first
end
-- your realm without spaces, as the channel appends it ("-Realm"); asked once
local realmCache
local function myRealm()
  if realmCache then return realmCache end
  local r = C.Get(GetNormalizedRealmName)
  if type(r) ~= "string" or r == "" then r = C.Get(GetRealmName); r = type(r) == "string" and (r:gsub("[%s%-]", "")) or nil end
  if type(r) == "string" and r ~= "" and not C.IsKstring(r) then realmCache = r end
  return realmCache
end
-- a name with a trailing "-Realm" of your own realm cut
local function noRealm(s)
  local realm = myRealm()
  if realm and #s > #realm + 1 and s:sub(-(#realm + 1)):lower() == ("-" .. realm):lower() then return s:sub(1, -(#realm + 2)) end
  return s
end
-- a name as a loose key: your realm cut, spaces and hyphens one space, lower case; nil for a Kstring, a secret or
-- nothing. A fallback only: where a GUID is known it decides
function C.Canon(s)
  s = C.Plain(s)
  if type(s) ~= "string" or s == "" or C.IsKstring(s) then return nil end
  return (noRealm(s):gsub("[%s%-]+", " "):lower())
end

-- the key this character's saved data lives under (CuteDB.chars), and who set a policy: UnitFullName's two returns
-- joined with "-", the realm where the second is empty. Kept as 0.3.0 built it, so nobody's counters move; it names
-- nobody in the window (Roster.lua does that)
function C.Me()
  local name, realm = C.Get(UnitFullName, "player")
  if type(name) ~= "string" then name = C.Get(UnitName, "player") end
  if type(name) ~= "string" then return nil end
  if type(realm) ~= "string" or realm == "" then realm = C.Get(GetNormalizedRealmName) end
  if type(realm) ~= "string" or realm == "" then return name, name end
  return name .. "-" .. realm, name
end

-- a name to show: a trailing "-Realm" of your own realm cut, the rest as given (a Kstring draws itself)
function C.Short(name)
  name = C.Plain(name)
  if type(name) ~= "string" then return "?" end
  if C.IsKstring(name) then return name end
  return noRealm(name)
end

----------------------------------------------------------------------------
-- saved variables
----------------------------------------------------------------------------
-- known: what the guild has learned in play (Stats.lua): what it enchants, by slot and kind of item, the labels of
-- the bosses, instances and factions it found (and which instance a boss is in, which kind an instance is), the raid
-- buffs guild mates cast, the standing ranges of the reactions. Kept apart from the roster, so pruning a record loses
-- none of it
local DEFAULTS = {
  settings = { columns = {}, density = "normal", offline = true, minimap = true, main = "", sort = {} },
  roster = {}, chars = {}, errors = {},
  known = { enchant = {}, labels = {}, mine = {}, inst = {}, kind = {}, buffs = {}, reactions = {} },
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

-- /cute diag: what this client says about you, your gear and the channel's senders, and what the guild has learned
-- (the enchant slots, the labels), as lines to paste. Values are
-- shown raw: a string quoted with its | doubled (so a Kstring shows its |K...|k), a secret as "secret"
local function shown(v)
  if issecretvalue and issecretvalue(v) then return "secret" end
  if type(v) == "string" then return '"' .. (v:gsub("|", "||")) .. '"' end
  return tostring(v)
end
local function returns(name, n, ...)
  local fn = _G[name]
  if type(fn) ~= "function" then return name .. " missing" end
  local r = { pcall(fn, ...) }
  if not r[1] then return name .. " threw " .. tostring(r[2]) end
  local out = {}
  for i = 2, n + 1 do out[#out + 1] = shown(r[i]) end
  return name .. " " .. table.concat(out, ", ")
end
function C.Diag()
  local lines = {}
  local function add(s) lines[#lines + 1] = s end
  add(string.format("diag %s: %s | %s | %s | %s | saved as %s", C.version, returns("UnitName", 2, "player"), returns("UnitFullName", 2, "player"),
    returns("GetNormalizedRealmName", 1), returns("GetRealmName", 1), shown(C.Me())))
  local guid = C.MyGUID()
  add("diag guid: UnitGUID " .. (guid and guid:sub(1, 16) or shown(C.Get(UnitGUID, "player"))))
  -- the guild roster's member for you, as the client gives it and as Cute matched it
  local club = type(C_Club) == "table" and C_Club or nil
  local clubId = club and C.Get(club.GetGuildClubId)
  local info = (club and clubId ~= nil) and C.Get(club.GetMemberInfoForSelf, clubId) or nil
  if type(info) == "table" then
    -- (the secret asked about before anything compares the name)
    local name, g = info.name, C.Plain(info.guid)
    local kind = (issecretvalue and issecretvalue(name)) and "secret" or (name == nil and "none" or (C.IsKstring(name) and "a Kstring" or "plain"))
    add(string.format("diag roster self: name %s (%s) | memberId %s | guid %s | isSelf %s", shown(name), kind, shown(info.memberId),
      type(g) == "string" and g:sub(1, 16) or shown(g), shown(info.isSelf)))
  else
    add("diag roster self: " .. (clubId == nil and "no guild club" or "GetMemberInfoForSelf gave nothing"))
  end
  local me = C.Roster and C.Roster.self
  add(string.format("diag matched: %s | your rows %d | records %d | senders known as you %d",
    me and ("member " .. shown(me.name) .. (me.guid and (" guid " .. me.guid:sub(1, 16)) or "")) or "no roster member is you yet",
    C.Roster and C.Roster:MyRowCount() or 0, C.Roster and C.Roster:RecordCount() or 0, C.Roster and C.Roster:SelfSenderCount() or 0))
  -- the first senders the guild channel named
  local seen = C.Comm and C.Comm.senders or {}
  local s = {}
  for _, e in ipairs(seen) do s[#s + 1] = (e.secret and "secret" or shown(e.sender)) .. " (" .. tostring(e.prefix) .. (e.me and ", you" or "") .. ")" end
  add("diag senders: " .. (#s > 0 and table.concat(s, ", ") or "none seen yet"))
  -- three gear slots as Forever's character sheet reads them
  for _, slot in ipairs({ 1, 5, 16 }) do
    local fn = _G.GetInventoryItemLink
    local link = "missing"
    if type(fn) == "function" then
      local ok, l = pcall(fn, "player", slot)
      if not ok then link = "threw"
      elseif issecretvalue and issecretvalue(l) then link = "secret"
      elseif l == nil then link = "nil"
      else link = type(l) end
    end
    add(string.format("diag slot %d: %s | link %s | %s", slot, returns("GetInventoryItemID", 1, "player", slot), link, returns("GetInventoryItemQuality", 1, "player", slot)))
  end
  -- what the guild has learned: the enchant slots (how many members were seen with one, the kinds of item), the labels known
  add("diag " .. C.Stats.KnownReport())
  return lines
end

SLASH_CUTE1 = "/cute"
SlashCmdList.CUTE = C.Safe(function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "settings" or msg == "options" then C.UI:Open("settings")
  elseif msg == "errors" then errorsList()
  elseif msg == "resend" then C.Comm:Ask(); C.Print("asked the guild to send their records again.")
  elseif msg == "me" then C.UI:Open("me")
  elseif msg == "api" then C.Print(C.Stats.GameReport()); C.Print(C.ApiReport())
  elseif msg == "diag" then for _, l in ipairs(C.Diag()) do C.Print(l) end
  elseif msg == "help" then
    C.Print("/cute opens the dashboard. /cute settings, /cute me, /cute resend, /cute errors, /cute api (which client functions exist here), /cute diag (names, roster, senders and gear as this client gives them, and what the guild has learned).")
  else C.UI:Toggle() end
end, "slash")

-- the key bindings (Bindings.xml)
BINDING_HEADER_CUTE = "Cute"
BINDING_NAME_CUTE_TOGGLE = "Toggle the Cute dashboard"
BINDING_NAME_CUTE_SETTINGS = "Open Cute's settings"
function Cute_Toggle() C.Safe(function() C.UI:Toggle() end, "binding")() end
function Cute_Settings() C.Safe(function() C.UI:Open("settings") end, "binding")() end
