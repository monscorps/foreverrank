-- SPDX-License-Identifier: GPL-3.0-or-later
-- Cute: the guild dashboard of <Cute>. Every member's client reads about a hundred facts about its own character
-- (Stats.lua), plus what it meets in play (the bosses it kills, the instances it enters, its factions, the slots it
-- enchants) and the game's own statistics where the client reports them, shares them with the guild on the game's
-- addon channel (Comm.lua), keeps everyone's last known values and what the guild has learned (Roster.lua, CuteDB.known)
-- and shows the whole guild in one window (UI.lua). Officers decide, stat by stat, whether members see each other's
-- (Policy.lua). What research and the beta showed of Forever ships as a seed (Known.lua), checked against the live
-- client at login and outgrown by the rules that learn from the guild's play (Rules.lua). Every page is a module
-- (Modules.lua): the dashboard is the core and always on; the Guide (Guide.lua) and the module addons are switched on
-- in Settings > Modules, per character. Nothing leaves the guild's addon channel (and the whispers to the officers that
-- carry what they keep to themselves, Comm.lua); there is no server.
local ADDON, C = ...
C.version = "0.7.1"
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

-- a function that records its errors instead of raising them; finally, where given, runs after fn on every path,
-- error or none, before the error is recorded (or, under CUTE_DEV, raised): a flag the body sets is reset by it
function C.Safe(fn, where, finally)
  return function(...)
    local n, args = select("#", ...), { ... }
    local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end, catch)
    if finally then finally() end
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
-- C.Get for a question with three answers (does the client have this id?): the first result made plain and true, or
-- nil and false where the call is missing, threw (C.lastErr keeps why) or gave a secret: an answer that says nothing
-- either way, which C.Get alone would read as a plain nil
function C.Ask(fn, ...)
  if type(fn) == "string" then
    local name = fn
    fn = _G[name]
    if type(fn) ~= "function" then C.Missing(name); return nil, false end
  end
  if type(fn) ~= "function" then return nil, false end
  local ok, v = pcall(fn, ...)
  if not ok then C.lastErr = tostring(v); return nil, false end
  local p = C.Plain(v)
  if p == nil and issecretvalue and issecretvalue(v) then return nil, false end
  return p, true
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
  "GetLatestCompletedAchievements", "GetStatisticsCategoryList", "GetStatistic", "GetNumLootItems", "GetLootSlotLink", "GetLootSlotInfo",
  "CanEditGuildInfo" }
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

----------------------------------------------------------------------------
-- what the busy paths cost on this client, for /cute diag perf: each timed path's runs, total and longest time
-- (debugprofilestop, milliseconds, where the client has it), and counts per minute (the last whole minute's and this
-- one's). Counting allocates nothing per call
----------------------------------------------------------------------------
local Perf = { n = {}, ms = {}, max = {}, cur = {}, last = {}, minute = nil }
C.Perf = Perf
local function minuteNow() return math.floor(C.Now() / 60) end
function Perf.Count(what, n)
  local m = minuteNow()
  if m ~= Perf.minute then
    if Perf.minute then Perf.last = (m == Perf.minute + 1) and Perf.cur or {} end
    Perf.cur, Perf.minute = {}, m
  end
  Perf.cur[what] = (Perf.cur[what] or 0) + (n or 1)
end
function Perf.Clock() return (debugprofilestop and debugprofilestop()) or 0 end
function Perf.Add(what, ms)
  Perf.n[what] = (Perf.n[what] or 0) + 1
  Perf.ms[what] = (Perf.ms[what] or 0) + ms
  if ms > (Perf.max[what] or 0) then Perf.max[what] = ms end
end
-- fn wrapped to time itself under what (its results passed on)
function Perf.Timed(what, fn)
  return function(...)
    local t0 = Perf.Clock()
    local a, b, c, d = fn(...)
    Perf.Add(what, Perf.Clock() - t0)
    return a, b, c, d
  end
end
function Perf.Report()
  local parts = {}
  for _, what in ipairs({ "refresh", "rebuild", "receive", "draw" }) do
    local n = Perf.n[what] or 0
    parts[#parts + 1] = string.format("%s %d, %.1f ms avg, %.1f max", what, n, n > 0 and (Perf.ms[what] or 0) / n or 0, Perf.max[what] or 0)
  end
  minuteNow()
  Perf.Count("tick", 0)
  local last = Perf.last
  local counts = {}
  for _, what in ipairs({ "addon", "cute", "roster", "rebuilds", "drops" }) do counts[#counts + 1] = what .. " " .. (last[what] or 0) end
  return "perf: " .. table.concat(parts, "; ") .. " | last minute: " .. table.concat(counts, ", ")
end
-- the server's clock (GetServerTime, SystemTimeDocumentation.lua), the one every client shares: the policy is stamped
-- with it and a stamp is judged against it (Policy.lua); this client's own where the call reads nothing
function C.ServerNow() return (C.Callable("GetServerTime") and C.Num("GetServerTime")) or C.Now() end

-- a chat line, "Cute: " first; bare: the line as given (it names Cute its own way)
function C.Print(msg, bare)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(bare and tostring(msg) or (C.COLOR .. "Cute|r: " .. tostring(msg))) end
end

----------------------------------------------------------------------------
-- versions: a newer Cute in the guild, and what is new in this one. Every Cute sends its version (addon_ver, in the
-- full record); one newer than yours says so once a session in chat, and in the window's status line until you
-- update. A /reload is the same session (the saved variables remember the chat line until the next login). The first
-- login on a version prints its changelog line once: Changes.lua, which build.py writes from the page's changelog, so
-- the game and the page say the same
----------------------------------------------------------------------------
C.UPDATE_AT = "foreverrank.com/addons/cute"
-- a version as its numbers, "0.5.10" as { 0, 5, 10 }; nil for anything but two to four dotted numbers (what comes from
-- the channel is anyone's text: "0.5.0-beta", "0..5", "banana" and a bare "5" are no version)
function C.ParseVersion(v)
  if type(v) ~= "string" or #v > 24 or not v:match("^%d[%d%.]*$") then return nil end
  local out = {}
  for part in (v .. "."):gmatch("([^%.]*)%.") do
    if part == "" or #part > 6 then return nil end
    out[#out + 1] = tonumber(part)
  end
  if #out < 2 or #out > 4 then return nil end
  return out
end
-- is version a newer than b, number by number (0.5.10 is newer than 0.5.9; 0.6 is 0.6.0); false where either is no version
function C.VersionNewer(a, b)
  local x, y = C.ParseVersion(a), C.ParseVersion(b)
  if not (x and y) then return false end
  for i = 1, math.max(#x, #y) do
    local p, q = x[i] or 0, y[i] or 0
    if p ~= q then return p > q end
  end
  return false
end
-- a guild member's version, as it arrives (Roster.lua) or as a saved record keeps it (at login), by the GUID it speaks
-- for (who). C.newer is the newest version newer than yours that two members run, it or one newer (two voices, as
-- everything the guild learns: 0.7.0 took one member's word, so one edited copy's version had every client online say
-- an update was out): the status line shows it (UI.lua). One version a member, the last it said (C.newerOf, by GUID:
-- a first build kept 32 versions for the whole guild, and one copy that said 32 made-up ones silenced every real
-- update after them)
C.newerOf = {}
local function voicesAtLeast(v)
  local n = 0
  for _, other in pairs(C.newerOf) do if not C.VersionNewer(v, other) then n = n + 1 end end
  return n
end
function C.SawVersion(v, who)
  v = C.Plain(v)
  if type(who) ~= "string" then return end
  if not C.VersionNewer(v, C.version) then C.newerOf[who] = nil return end
  C.newerOf[who] = v
  if voicesAtLeast(v) < 2 then return end
  if C.newer and not C.VersionNewer(v, C.newer) then return end
  C.newer = v
  if CuteDB and not CuteDB.toldNewer then
    CuteDB.toldNewer = true
    C.Print(C.COLOR .. "Cute " .. v .. "|r is out (you have " .. C.version .. "): " .. C.UPDATE_AT, true)
  end
  if C.UI and C.UI.DrawStatus then C.UI:DrawStatus() end
end
-- at login (and after a /reload), once the roster is known (Roster.lua calls it then too): the versions the saved
-- records keep, yours left out, each only from a record whose GUID the roster lists and the officers have not marked
-- untrusted (Roster.lua R:Apply the same): one edited copy's made-up version announces nothing
function C.SavedVersions()
  if not C.versionsStarted or not C.Roster.trusted then return end
  for key, e in pairs(CuteDB.roster or {}) do
    local st = type(e) == "table" and type(e.stats) == "table" and e.stats or nil
    local g = st and C.Roster:VoiceOf(key, e)
    if g and type(st.addon_ver) == "string" and not C.Roster:IsSelfRecord(key, e) and not C.Policy:Untrusted(g) then C.SawVersion(st.addon_ver, g) end
  end
end
-- the first login on this version: its changelog line, once, ten seconds on, after the login's own lines. A first run
-- (saved variables empty) says hello instead, naming /cute: what changed since a version nobody ran is no news
function C.WhatsNew()
  if C.firstRun then
    C.firstRun = false
    CuteDB.toldChanges = C.version
    C.Print("/cute or the elf on the minimap opens the guild window.")
    return
  end
  local line = type(C.CHANGES) == "table" and C.CHANGES[C.version] or nil
  if type(line) ~= "string" or line == "" or CuteDB.toldChanges == C.version then return end
  local was = CuteDB.toldChanges
  CuteDB.toldChanges = C.version
  C.Print(C.COLOR .. "Cute " .. C.version .. "|r: " .. line, true)
  -- (and the versions between the last one told and this one, newest first, three at most: a 0.5.x user is told the
  -- Guide moved to Settings, Modules in 0.6.0)
  if not C.ParseVersion(was) then return end
  local skipped = {}
  for v, l in pairs(C.CHANGES) do
    if type(l) == "string" and l ~= "" and C.VersionNewer(v, was) and C.VersionNewer(C.version, v) then skipped[#skipped + 1] = v end
  end
  table.sort(skipped, function(a, b) return C.VersionNewer(a, b) end)
  for i = 1, math.min(3, #skipped) do C.Print(C.COLOR .. "Cute " .. skipped[i] .. "|r: " .. C.CHANGES[skipped[i]], true) end
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
-- nothing. A fallback only: where a GUID is known it decides. Kept per string once your realm reads (every roster
-- read asks it of every member's name and every record's sender string), CANON_MAX strings at most
local canonCache, canonN, CANON_MAX = {}, 0, 4096
function C.Canon(s)
  s = C.Plain(s)
  if type(s) ~= "string" or s == "" then return nil end
  local hit = canonCache[s]
  if hit ~= nil then return hit or nil end
  local v = (not C.IsKstring(s)) and (noRealm(s):gsub("[%s%-]+", " "):lower()) or false
  if realmCache then
    if canonN >= CANON_MAX then canonCache, canonN = {}, 0 end
    canonCache[s], canonN = v, canonN + 1
  end
  if C.Perf then C.Perf.Count("canon") end
  return v or nil
end

-- the key this character's saved data lives under (CuteDB.chars), and who set a policy: UnitFullName's two returns
-- joined with "-", the realm where the second is empty. Kept as 0.3.0 built it, so nobody's counters move; it names
-- nobody in the window (Roster.lua does that). Read once a session: the first non-nil key is this session's, so a
-- second return that reads one way early and another later (the surname one call, the realm the next) cannot save
-- a choice under one key and read it back under another
local meKey, meName
function C.Me()
  if meKey then return meKey, meName end
  local name, realm = C.Get(UnitFullName, "player")
  if type(name) ~= "string" then name = C.Get(UnitName, "player") end
  if type(name) ~= "string" then return nil end
  if type(realm) ~= "string" or realm == "" then realm = C.Get(GetNormalizedRealmName) end
  local key = (type(realm) ~= "string" or realm == "") and name or (name .. "-" .. realm)
  meKey, meName = key, name
  return key, name
end

-- a name's shape, never the name, for /cute diag: "Kstring", "none", or how many words it has and whether your realm
-- trails it ("2 words + realm")
function C.NameShape(s)
  s = C.Plain(s)
  if type(s) ~= "string" or s == "" then return "none" end
  if C.IsKstring(s) then return "Kstring" end
  local bare, n = noRealm(s), 0
  for _ in bare:gmatch("[^%s%-]+") do n = n + 1 end
  return n .. (n == 1 and " word" or " words") .. (bare ~= s and " + realm" or "")
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
-- buffs guild mates cast, the standing ranges of the reactions; and what the rules weigh (Rules.lua): the XP each
-- level takes as members reported it, the loot seen per boss, when members were first seen wearing items in a slot,
-- the boss kills corroborated by a group mate (kills), Rule 0's verdict on the seed and the model built from it all.
-- Kept apart from the roster, so pruning a record loses none of it
local DEFAULTS = {
  settings = { columns = {}, density = "normal", offline = true, minimap = true, main = "", sort = {} },
  roster = {}, chars = {}, errors = {},
  known = { enchant = {}, labels = {}, mine = {}, inst = {}, kind = {}, buffs = {}, reactions = {}, xp = {}, loot = {}, watch = {}, kills = {} },
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
  C.firstRun = type(CuteDB) ~= "table" or next(CuteDB) == nil
  CuteDB = type(CuteDB) == "table" and CuteDB or {}
  local was = CuteDB.version
  fill(CuteDB, DEFAULTS)
  -- (0.5.x showed every character the Guide as a fixed tab; from 0.6.0 it is a module, and every character starts
  -- with the statistics alone, as What's new says at the first login on it: Settings > Modules switches it on)
  -- before 0.6.0 only the guild channel made records (there were no whispers): each is one heard there (Roster.lua
  -- R:GuildSender takes a whisper only from such a sender string)
  if C.ParseVersion(was) and C.VersionNewer("0.6.0", was) then
    for _, e in pairs(CuteDB.roster) do if type(e) == "table" then e.ch = true end end
  end
  -- (what members passed on to each other in 0.6.0's builds before the policy lived in Guild Info)
  CuteDB.relay = nil
  -- a file a crash or a hand left odd: a record or a character that is no table goes, and each keeps the tables the
  -- code reads (0.7.0 raised on such at every roster read and every stat, and a refresh that raised read no Guild Info)
  for key, e in pairs(CuteDB.roster) do
    if type(key) ~= "string" or type(e) ~= "table" then CuteDB.roster[key] = nil
    else
      if type(e.stats) ~= "table" then e.stats = {} end
      if type(e.at) ~= "table" then e.at = {} end
      if e.seen ~= nil and type(e.seen) ~= "number" then e.seen = nil end
    end
  end
  for key, rec in pairs(CuteDB.chars) do
    if type(key) ~= "string" or type(rec) ~= "table" then CuteDB.chars[key] = nil
    else
      if type(rec.counters) ~= "table" then rec.counters = {} end
      if rec.modules ~= nil and type(rec.modules) ~= "table" then rec.modules = {} end
    end
  end
  -- (once: the times 0.7.0 kept for every statistic and discovery of every member, which nothing reads, Roster.lua;
  -- and the statistics it kept as 0 from "--", never recorded, which are nothing now (Stats.lua S.Quantity, Roster.lua
  -- R:Apply): a sender never sends that id again, so the 0 stayed for good. In the records held and those parked with
  -- another guild; slimAt 2, so a file the first pass ran on (true) gets the second)
  local slim = CuteDB.slimAt == true and 1 or tonumber(CuteDB.slimAt) or 0
  if slim < 2 and C.Stats and C.Stats.IsDynamic then
    local function slimmed(roster)
      for _, e in pairs(type(roster) == "table" and roster or {}) do
        if type(e) == "table" and type(e.at) == "table" then
          for id in pairs(e.at) do if type(id) == "string" and C.Stats.IsDynamic(id) then e.at[id] = nil end end
        end
        if type(e) == "table" and type(e.stats) == "table" then
          for id, v in pairs(e.stats) do if v == 0 and type(id) == "string" and id:match("^g%d+$") then e.stats[id] = nil end end
        end
      end
    end
    slimmed(CuteDB.roster)
    for _, p in pairs(type(CuteDB.policies) == "table" and CuteDB.policies or {}) do if type(p) == "table" then slimmed(p.roster) end end
    CuteDB.slimAt = 2
  end
  -- (a newer Cute's file, this one run after it: the version stays the newest that ran, so its one-time steps do not
  -- run again when it comes back)
  if not C.VersionNewer(was, C.version) then CuteDB.version = C.version end
end
function C.Settings() return CuteDB.settings end
-- this character's own record (counters, declared role; the main is account-wide, in settings)
function C.Char()
  local me = C.Me() or "?"
  local rec = CuteDB.chars[me]
  local g = C.MyGUID()
  if not rec then
    -- (a rename, a realm transfer, a surname changed: the record this character's GUID kept under its old key, taken
    -- over, so its counters go on and no receiver marks the lifetime counts as gone down)
    if g and me ~= "?" then
      for key, old in pairs(CuteDB.chars) do
        if key ~= me and type(old) == "table" and old.guid == g then rec = old; CuteDB.chars[key] = nil; break end
      end
    end
    rec = rec or { counters = {}, modules = {} }
    CuteDB.chars[me] = rec
  end
  if g and rec.guid == nil and me ~= "?" then rec.guid = g end
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
    -- each on its own, so one part failing never hides the others (the minimap button in particular). The modules
    -- that are on start first, so the stats they define are read with the rest
    C.Safe(function() C.Modules.Start() end, "modules: start")()
    C.Safe(function() C.Roster:Start() end, "roster: start")()
    C.Safe(function() C.Sample:Start(initial, reloading) end, "sample: start")()
    C.Safe(function() C.Comm:Start(reloading) end, "comm: start")()
    -- the seed checked against this client (Rule 0, spread over frames), after the roster, before the Guide draws
    C.Safe(function() C.Rules:Start() end, "rules: start")()
    C.Safe(function() if C.UI and C.UI.OnWorld then C.UI:OnWorld() end end, "minimap button")()
    -- (the window's draws timed for /cute diag perf, once)
    C.Safe(function()
      if C.UI and type(C.UI.Draw) == "function" and not C.drawTimed then C.drawTimed = true; C.UI.Draw = C.Perf.Timed("draw", C.UI.Draw) end
    end, "perf")()
    -- versions: a login (not a /reload, nor a loading screen) may say a newer Cute again; the saved records' versions
    -- once a session; what is new in this one ten seconds on
    C.Safe(function()
      if initial then CuteDB.toldNewer = nil end
      if not C.versionsStarted then
        C.versionsStarted = true
        C.SavedVersions()
        C_Timer.After(10, C.Safe(C.WhatsNew, "what is new"))
      end
    end, "versions")()
  elseif event == "PLAYER_LOGOUT" then
    -- (and at a /reload: how far this character holds the guild, Comm.lua M:Logout. 0.7.0 read every stat again here
    -- for nothing it saved)
    C.Comm:Logout()
  end
end, "core: events"))

-- (Cute's own, then the quest engine's where Cute_Quest runs: its errors are kept in CuteQuestDB, which /qb errors
-- alone listed.) Each once: Cute_Quest's Bridge.lua copies an engine error's first sighting onto Cute's list too
-- (where "quest engine: ..."), so Cute says it once a session, while the engine's own list counts every repeat. The
-- merge review: both were listed, "x1" beside the true count. Such a copy is left out while the engine's own entry
-- stands; a call the game blocked is on Cute's list alone and shows
local ENGINE_WHERE = "quest engine: "
local function errorsList()
  local list = CuteDB and CuteDB.errors or {}
  local engine = type(CuteQuestDB) == "table" and type(CuteQuestDB.errors) == "table" and CuteQuestDB.errors or {}
  if #list == 0 and #engine == 0 then C.Print("no errors recorded.") return end
  local own = {}
  for _, e in ipairs(engine) do if type(e) == "table" and e.msg ~= nil then own[tostring(e.msg)] = true end end
  local function say(e, from)
    if type(e) ~= "table" then return end
    -- (a | doubled: an error's text names a texture or a link, which chat would draw as one)
    C.Print(string.format("%s%s (x%d, last %s) %s", from, (tostring(e.msg):gsub("|", "||")), tonumber(e.count) or 1, tostring(e.last or ""), (tostring(e.where or ""):gsub("|", "||"))))
  end
  for _, e in ipairs(list) do
    local copy = type(e) == "table" and tostring(e.where or ""):sub(1, #ENGINE_WHERE) == ENGINE_WHERE and own[tostring(e.msg)]
    if not copy then say(e, "") end
  end
  for _, e in ipairs(engine) do say(e, "quests: ") end
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
  -- how the senders and the roster's names look here, as shapes (never a name), and how the GUIDs that came fared
  add("diag names: " .. C.Roster:NameShapes())
  -- where the policy comes from: Guild Info's line, and whether this client holds the policy it names
  add("diag policy: " .. C.Policy:Report())
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
  -- the seed: fresh or stale and why, what Rule 0 found absent, how many facts are in each state
  add("diag " .. C.Rules.Report())
  -- the modules on for this character (the dashboard always is) and the ones there that are off, each with its state
  -- where it is not as its box says
  local officer = C.Roster:MeOfficer()
  local on, off = {}, {}
  for _, e in ipairs(C.Modules.Available(officer)) do
    local list = e.on and on or off
    list[#list + 1] = e.title .. (e.addon and (" (" .. e.key .. ")") or "") .. (e.status and (": " .. e.status) or "")
  end
  add("diag modules: on " .. (#on > 0 and table.concat(on, ", ") or "none") .. " | off " .. (#off > 0 and table.concat(off, ", ") or "none"))
  -- the trust marks: the members marked suspect and the ones the officers marked untrusted, counted; who and why for an
  -- officer alone (the marks are the officers')
  local suspect, untrusted = {}, {}
  for _, r in ipairs(C.Roster:Rows()) do
    if not r.me and r.suspect then suspect[#suspect + 1] = r.short .. " (" .. tostring(r.suspect.why) .. ")" end
    if not r.me and r.untrusted then untrusted[#untrusted + 1] = r.short end
  end
  table.sort(suspect); table.sort(untrusted)
  local function named(list) return (officer and #list > 0) and (": " .. table.concat(list, ", ", 1, math.min(8, #list)) .. (#list > 8 and (" and " .. (#list - 8) .. " more") or "")) or "" end
  add(string.format("diag trust: suspect %d%s | untrusted %d%s", #suspect, named(suspect), #untrusted, named(untrusted)))
  -- the channel and the load: the last send each way, the lockdown, the list against the club, the busy paths' cost
  add("diag " .. C.Comm:ChannelReport())
  add("diag " .. C.Comm:LockReport())
  add("diag " .. C.Comm:SyncReport())
  add("diag " .. C.Roster:ListReport())
  add("diag " .. C.Perf.Report())
  return lines
end

-- /cute: the window. /cute <page> opens a page by its module's id or title (race, prog, shame, statistics, officers,
-- me; guide and a module addon's while they are on; a built-in module that is off, the Guide, goes on for this
-- character first, as its box would do it); /cute settings opens Settings; /cute modules lists the modules, on or
-- off, and opens Settings there; /cute resend asks the guild again; /cute errors, api, diag and rules print lines to
-- paste
local function pageFor(msg)
  for _, def in ipairs(C.Modules.list) do
    local title = def.title:lower()
    if def.page and (msg == def.id or msg == title or msg == (title:gsub("%s+", ""))) then return def end
  end
end
-- each module Settings > Modules lists, on or off, in one line
local function modulesLine()
  local parts = {}
  for _, e in ipairs(C.Modules.Available(C.Roster:MeOfficer())) do
    parts[#parts + 1] = e.title .. (e.addon and (" (" .. e.key .. ")") or "") .. (e.on and " on" or " off") .. (e.status and (", " .. e.status) or "")
  end
  return "modules: " .. (#parts > 0 and table.concat(parts, "; ") or "none") .. ". The dashboard's pages are always on."
end
SLASH_CUTE1 = "/cute"
SlashCmdList.CUTE = C.Safe(function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "" then C.UI:Toggle()
  elseif msg == "settings" or msg == "options" then C.UI:Open("settings")
  elseif msg == "modules" then C.Print(modulesLine()); C.UI:Open("settings", "modules")
  elseif msg == "errors" then errorsList()
  elseif msg == "resend" then C.Comm:Ask(); C.Print("asked the guild to send their records again.")
  elseif msg == "api" then C.Print(C.Stats.GameReport()); C.Print(C.ApiReport())
  elseif msg == "diag" then for _, l in ipairs(C.Diag()) do C.Print(l) end
  elseif msg == "rules" then for _, l in ipairs(C.Rules.RulesReport()) do C.Print(l) end
  elseif msg == "help" then
    C.Print("/cute opens the window, /cute settings its Settings; /cute race, prog, shame, statistics, officers, me or a module's name opens that page.")
    C.Print("/cute modules lists the modules; /cute resend asks the guild for their records again; /cute help more: what to paste in a bug report.")
  elseif msg == "help more" then
    C.Print("To paste in a bug report: /cute errors; /cute diag (names, roster, channel and load as this client gives them, what the guild learned); /cute api (the client functions it has); /cute rules (each rule's threshold and who set it).")
  else
    local def, officer = pageFor(msg), C.Roster:MeOfficer()
    if not def then C.Print("no page or command \"" .. msg .. "\". /cute help lists them.")
    elseif def.officer and not officer then C.Print("the " .. def.title .. " page is for officer ranks.")
    elseif not C.Modules.Page(def.id, officer) then
      if def.builtin then
        -- a built-in module that is off goes on for this character, as its box in Settings > Modules would do it,
        -- and its page opens: the command is a second way to the box, for a client where the box takes no click
        C.Modules.Set(def.key, true)
        C.Print(def.title .. " is on for this character; untick it in Settings, Modules to switch it off.")
        C.UI:Open(def.id)
      else
        -- a module addon that is off says where it is switched on, and opens it there
        C.Print(def.title .. " is switched off. Tick it in Settings, Modules.")
        C.UI:Open("settings", "modules")
      end
    else C.UI:Open(def.id) end
  end
end, "slash")

-- the key bindings (Bindings.xml)
BINDING_HEADER_CUTE = "Cute"
BINDING_NAME_CUTE_TOGGLE = "Toggle the Cute dashboard"
BINDING_NAME_CUTE_SETTINGS = "Open Cute's settings"
function Cute_Toggle() C.Safe(function() C.UI:Toggle() end, "binding")() end
function Cute_Settings() C.Safe(function() C.UI:Open("settings") end, "binding")() end
