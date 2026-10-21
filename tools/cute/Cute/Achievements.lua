-- SPDX-License-Identifier: GPL-3.0-or-later
-- Achievements: the run report's design, section 5 (with 9.1, 12, 13.2 and 14). A built-in module, on by default,
-- which a member may switch off for themselves (Settings > Modules) and the officers for the whole guild (its own
-- section: a switch that travels with the officers' rules, as a threshold does, Rules.lua and Policy.lua). Forever's
-- achievements are its Legacy Challenges, read with the achievement API by id.
--   Earns    your own ACHIEVEMENT_EARNED (none the account earned before, no guild achievement) goes to the officers as
--            1A|<id>|<server time>, on GUILD where the officers' policy routes Achievements (ac) Everyone, else
--            whispered to each officer online; held in CuteDB.chars[me].pending while inside a dungeon or raid, while
--            the game holds addon chat back and while the policy is in doubt (a result 11 spends no try: Comm.lua)
--   Recent   ach_recent, hidden: up to 20 earns of the last 14 days as <id>:<day> (days since 2026-01-01, both base
--            36), whispered to the officers alone (Comm.lua sends a stat marked officers so, whatever its route) in the
--            record an officer's ask is answered with, so an officer who was away learns them at their next login;
--            never in the guild's part of a record, and no delta of its own (an officer online has the 1A)
--   Officers every earn heard (a 1A, a member's ach_recent, the server's guild line, guild news) goes into the day's
--            achievements row of the officers' Queue (Halls.lua), once per member and achievement, marked "server"
--            where the server's line or guild news shows it; guild news' guild achievements make guild cards. Trust:
--            an untrusted member's earn, an id this client does not know and a 1A past 20 from one sender in ten
--            minutes are dropped; a 1A is dated by its own time only where that is within six hours before it came
--   Firsts   the ledger, CuteDB.halls[club].firsts, on officers' clients only: per achievement (a<id>), boss (b<id>)
--            and level cap (c<level>) the earliest member known, when, and what it rests on; seeded 90 s into an
--            officer's first login with this version (guild news, the members' ach_recent, the kills the guild
--            corroborated, the roster's levels). An earn with no earlier entry, or one resting on another member's Cute
--            alone, a boss's first corroborated kill (Rules.lua rule 9) and the first member at the cap each become a
--            "Guild first?" row: a suggestion, never published by itself
-- Nothing of a member's in /cute diag cards: counts and states.
local _, C = ...
local A = { refused = 0, sent = 0, earned = 0, lines = 0, secret = 0, taken = 0, firsts = 0, takenFrom = {}, recentTaken = {}, news = { state = "none", n = 0, guild = 0 } }
C.Achievements = A

local RECENT_MAX, RECENT_DAYS, RECENT_BYTES = 20, 14, 200
local PENDING_MAX = 40       -- earns held at most (the oldest out first)
local TAKE_MAX, TAKE_WINDOW = 20, 600 -- 1A taken from one sender in ten minutes
local HELD_MAX = 6 * 3600    -- a 1A is dated by its own time where it is at most this old as it comes
local SEEN_MAX = 3000        -- member and achievement pairs an officer remembers having queued
local LEDGER_MAX, LEDGER_V = 2000, 1
local READY_AFTER = 90       -- a login's hello answers are in: the ledger may suggest
local NEWS_FIRST, NEWS_EVERY, NEWS_WAIT = 30, 3600, 10
local FIRSTS_DAY = 10        -- first rows a day, then the day's row
local KILL_LIVE = 900        -- a boss's first kill is suggested where its claim is this recent
local DAY0 = 1767225600      -- 2026-01-01 00:00 UTC: the day ach_recent counts from
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

local function now() return C.ServerNow() end
local function gtime() return (GetTime and GetTime()) or 0 end
local function callable(name) return type(_G[name]) == "function" end
-- a global client function, quietly nothing where this client has none
local function call(name, ...) if not callable(name) then return nil end return C.Get(_G[name], ...) end
local function b36(n) return C.Comm.b36(n) end
local function unb36(s) return C.Comm.unb36(s) end
local function sfxOf(g) return type(g) == "string" and g:match("([^%-]+)$") or nil end
local function H() return C.Halls end
local function officer() return C.Roster and C.Roster:MeOfficer() or false end

----------------------------------------------------------------------------
-- the registry (core: every client knows the code, routes by it and decodes ach_recent, the module on or off).
-- Achievements (ac) is a policy code with no value of its own, as the run fields are (Runs.lua): kept out of S.list,
-- so no record carries it, a row of its own under an Achievements heading in Who sees what, and on the Me page whether
-- this character sends its earns. A live earn tells the latest challenge, its step in Challenges done and its points,
-- so ac and the Legacy Challenge stats reveal each other and go the strictest way of any of them. ach_recent travels
-- with ac (Policy.lua P:Route) and only ever to the officers (officers: Comm.lua's parts)
----------------------------------------------------------------------------
local LEGACY = { "lc_last", "lc_done", "lc_pts", "lc_cats" }
do
  local S = C.Stats
  S.byCat.ach = S.byCat.ach or {}
  S.CATS[#S.CATS + 1] = "ach"
  S.CAT_LABEL.ach = "Achievements"
  S.CAT_DEFAULT.ach = "all"
  assert(not S.byCode.ac and not S.byId.achievements, "the Achievements code")
  local e = { id = "achievements", label = "Achievements as earned", cat = "ach", kind = "flag", code = "ac", default = "all", track = true, policyOnly = true,
    reveals = {}, hint = "your earns, sent to the guild's officers as they happen" }
  for _, id in ipairs(LEGACY) do
    local d = S.byId[id]
    if d then
      e.reveals[#e.reveals + 1] = id
      d.reveals = d.reveals or {}
      d.reveals[#d.reveals + 1] = "achievements"
    end
  end
  S.byId[e.id], S.byCode[e.code] = e, e.id
  S.codeVersion = (S.codeVersion or 0) + 1
  table.insert(S.byCat.ach, e)
  S.HIDDEN.ach_recent = { id = "ach_recent", label = "Recent achievements", cat = "hidden", kind = "text", max = RECENT_BYTES, default = "all", hidden = true,
    with = "achievements", officers = true }
  S.HIDDEN_ORDER[#S.HIDDEN_ORDER + 1] = "ach_recent"
  S.byId.ach_recent = S.HIDDEN.ach_recent
  -- (the globals no doc lists that this file reads, each where Blizzard's own code calls it on this client, for /cute
  -- api: GetAchievementCategory, Blizzard_FrameXMLUtil/AchievementUtil.lua:42, a file the toc loads for the mainline
  -- family with no camelot exclusion; QueryGuildNews, GetNumGuildNews and GetGuildNewsFilters, Blizzard_Communities/
  -- GuildNews.lua:49, 88 and 298, a toc that limits no game type)
  for _, n in ipairs({ "GetAchievementCategory", "QueryGuildNews", "GetNumGuildNews", "GetGuildNewsFilters" }) do C.UNDOCUMENTED[#C.UNDOCUMENTED + 1] = n end
  -- the officers' switch for the whole guild: a rule, 1 on and 0 off, sent and taken with the policy's rules (newest
  -- wins, who set it kept) by its entry in TUNE_BY and LOWER; left out of R.TUNE, the list Settings > Rules draws as
  -- thresholds: it is a switch, drawn in this module's own section
  local R = C.Rules
  R.RULES.achGuild = 1
  local t = { "achGuild", "Achievements for the guild", 0, 1, 1, nil, "Off: no member's Cute sends achievements.", "ach" }
  R.TUNE_BY.achGuild, R.LOWER.achguild = t, "achGuild"
end

----------------------------------------------------------------------------
-- on and off, days and dates
----------------------------------------------------------------------------
local function moduleOn() local def = C.Modules.byId.ach; return def ~= nil and def.active == true end
function A.GuildOn() return C.Rules.Get("achGuild") ~= 0 end
-- this character sends its own earns, and an officer's client takes the guild's: the module on, the guild's switch on
function A.Sending() return moduleOn() and A.GuildOn() end
function A.Taking() return A.Sending() and C.Roster:InGuild() and C.Roster:OfficerStill() end
-- server days since 2026-01-01, and a day's noon
function A.Day(t) return math.floor(((t or now()) - DAY0) / 86400) end
local function dayTime(d) return DAY0 + d * 86400 + 43200 end
-- "21 Oct"
local function dayText(t)
  local d = date and date("*t", t)
  if type(d) ~= "table" or not MONTHS[d.month] then return "" end
  return d.day .. " " .. MONTHS[d.month]
end
A.DayText = dayText
-- days since 1970 of a calendar date (guild news gives one), worked out here rather than by time(), which would read it
-- in the client's own time zone
local function daysOf(y, m, d)
  local n = 0
  for yy = 1970, y - 1 do n = n + ((yy % 4 == 0 and (yy % 100 ~= 0 or yy % 400 == 0)) and 366 or 365) end
  local feb = (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)) and 29 or 28
  local lens = { 31, feb, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  for mm = 1, m - 1 do n = n + lens[mm] end
  return n + d - 1
end

----------------------------------------------------------------------------
-- an achievement as the client holds it, by id: every client has every achievement's name, icon and description.
-- GetAchievementInfo(id): id, name, points, completed, month, day, year, description, flags, icon, rewardText,
-- isGuild, wasEarnedByMe, earnedBy, isStatistic (Blizzard_LegacySystem/Blizzard_LegacyAchievementOverrides.lua:44 by
-- id; AlertFrames.lua:526); a guild one by C_AchievementInfo.IsGuildAchievement too (AchievementInfoDocumentation.lua);
-- its category's name by GetAchievementCategory and GetCategoryInfo (AchievementUtil.lua:42, the Legacy window's
-- Blizzard_LegacyChallenges.lua:149). Nil for an id this client does not know, and for a statistic
----------------------------------------------------------------------------
function A.Info(id)
  if type(id) ~= "number" or id <= 0 or id >= 10000000 then return nil end
  local got, name, _, _, _, _, _, desc, _, icon, _, isGuild, _, _, isStat = call("GetAchievementInfo", id)
  if got == nil or type(name) ~= "string" or name == "" or isStat == true then return nil end
  local guild = isGuild == true
  local AI = C_AchievementInfo
  if not guild and type(AI) == "table" and type(AI.IsGuildAchievement) == "function" then guild = C.Get(AI.IsGuildAchievement, id) == true end
  icon = tonumber(icon)
  local cat
  local cid = call("GetAchievementCategory", id)
  if type(cid) == "number" then
    local cname = call("GetCategoryInfo", cid)
    if type(cname) == "string" and cname ~= "" then cat = cname end
  end
  return { id = id, name = name, desc = type(desc) == "string" and desc or "", icon = (icon and icon > 0) and icon or nil, guild = guild, cat = cat }
end

----------------------------------------------------------------------------
-- your own earns: ach_recent and the pending 1A
----------------------------------------------------------------------------
-- the earns of the last 14 days, newest first: { { id, d }, ... }, 20 at most (CuteDB.chars[me].achRecent)
local function recentList()
  local ch = C.Char()
  if type(ch.achRecent) ~= "table" then ch.achRecent = {} end
  local list, today = ch.achRecent, A.Day()
  for i = #list, 1, -1 do
    local e = list[i]
    if type(e) ~= "table" or type(e.id) ~= "number" or type(e.d) ~= "number" or e.d < today - RECENT_DAYS then table.remove(list, i) end
  end
  while #list > RECENT_MAX do table.remove(list) end
  return list
end
-- the hidden value: what goes to the officers, nothing while switched off (here or for the guild)
function A:SetRecent()
  local S = C.Sample
  local text
  if A.Sending() then
    local parts = {}
    for _, e in ipairs(recentList()) do
      local p = b36(e.id) .. ":" .. b36(e.d)
      if #table.concat(parts, ".") + 1 + #p > RECENT_BYTES then break end
      parts[#parts + 1] = p
    end
    if #parts > 0 then text = table.concat(parts, ".") end
  end
  -- (set, not marked changed: it goes with the record an officer's ask is answered with, not as a delta of its own)
  S.values.ach_recent = text
  -- (the Me page and Who sees what: whether this character sends its earns)
  S.values.achievements = A.Sending()
end

function A:Earned(id, already)
  id, already = C.Plain(id), C.Plain(already)
  if type(id) ~= "number" or already == true or not A.Sending() or not C.Roster:InGuild() then return end
  local info = A.Info(id)
  if not info or info.guild then return end
  local t = math.floor(now())
  local list = recentList()
  for i = #list, 1, -1 do if list[i].id == id then table.remove(list, i) end end
  table.insert(list, 1, { id = id, d = A.Day(t) })
  while #list > RECENT_MAX do table.remove(list) end
  self:SetRecent()
  local ch = C.Char()
  if type(ch.pending) ~= "table" then ch.pending = {} end
  ch.pending[#ch.pending + 1] = { id = id, t = t }
  while #ch.pending > PENDING_MAX do table.remove(ch.pending, 1) end
  A.earned = A.earned + 1
  -- (an officer's own earn: into its own queue now; the game hands its 1A back, which Comm drops as its own)
  if officer() then self:Earn({ g = C.MyGUID(), id = id, t = t, src = "cute", from = "me" }) end
  self:Flush()
end

-- the pending earns go once out of any dungeon or raid, the chat restriction over and the policy settled (it decides
-- the way): on GUILD where Achievements goes to everyone, else whispered to each officer online (none online: the
-- officers learn them from ach_recent at their next login)
local function inside()
  local _, kind = call("IsInInstance")
  return kind == "party" or kind == "raid"
end
function A:Flush()
  local ch = C.Char()
  local list = ch.pending
  if type(list) ~= "table" or #list == 0 then return end
  if not A.Sending() then ch.pending = nil; return end
  local M = C.Comm
  if inside() or M:Locked() or not C.Policy:Settled() or not M.hello or not C.Roster:InGuild() then
    if not A.flushDue then
      A.flushDue = true
      C_Timer.After(10, C.Safe(function() A.flushDue = false; A:Flush() end, "achievements: pending"))
    end
    return
  end
  ch.pending = nil
  local everyone = C.Policy:Route("achievements") == "all"
  local targets = everyone and {} or C.Roster:OfficerTargets()
  for _, e in ipairs(list) do
    if type(e) == "table" and type(e.id) == "number" and type(e.t) == "number" then
      local msg = "1A|" .. b36(e.id) .. "|" .. b36(e.t)
      if everyone then M.Queue({ msg = msg }) else for _, to in ipairs(targets) do M.Queue({ msg = msg, target = to }) end end
      A.sent = A.sent + 1
    end
  end
end

----------------------------------------------------------------------------
-- the officers' side: every earn heard, into the day's row of the Queue, once per member and achievement
----------------------------------------------------------------------------
local function store()
  local d = H().DB()
  if type(d.achSeen) ~= "table" then d.achSeen = {} end
  return d
end
-- a member as a card names them: the roster's, else your own
local function member(g)
  if g == C.MyGUID() then
    local _, class = call("UnitClass", "player")
    return { guid = g, name = C.Roster:MyDisplay(), class = class }
  end
  local m = C.Roster.byGuid and C.Roster.byGuid[g]
  if not m then return nil end
  return { guid = g, name = (m.name and C.Short(m.name)) or "?", class = m.class }
end
local function clean(s, max) return H().Clean(s, max) end
local function achCard(info, m, t, kind)
  return { guid = m.guid, sfx = sfxOf(m.guid), name = m.name, class = m.class, kind = kind or "ach", title = clean(info.name, 24),
    line = kind == "first" and "First in the guild to earn it." or clean(info.desc, 56), value = "Earned " .. dayText(t),
    valueLabel = clean(info.cat or "Legacy Challenge", 24), icon = info.icon, source = "a" .. info.id }
end
-- the remembered pairs: a pair queued once is not queued again (ach_recent repeats an earn for 14 days). Pruned past 15
-- days at each login's seed time and whenever they pass SEEN_MAX, the oldest days first down to nine tenths of it
-- (counted as they come: a login's answers bring thousands, and no walk is made per pair)
local function prune(d)
  local seen, cut, n = d.achSeen, A.Day() - RECENT_DAYS - 1, 0
  for k, day in pairs(seen) do if type(day) ~= "number" or day < cut then seen[k] = nil else n = n + 1 end end
  if n > SEEN_MAX then
    local days = {}
    for _, day in pairs(seen) do days[#days + 1] = day end
    table.sort(days)
    local upto = days[n - math.floor(SEEN_MAX * 0.9)]
    n = 0
    for k, day in pairs(seen) do if day <= upto then seen[k] = nil else n = n + 1 end end
  end
  d.achSeenN = n
end
A.Prune = function() prune(store()) end
local function remember(d, key, day)
  if d.achSeen[key] == nil then d.achSeenN = (tonumber(d.achSeenN) or 0) + 1 end
  d.achSeen[key] = day
  if d.achSeenN > SEEN_MAX then prune(d) end
end
-- an earn: e = { g, id, t, src ("cute", "line", "news"), from, approx (dated by its day alone: ach_recent, guild news) }.
-- True where it was queued
function A:Earn(e)
  if not A.Taking() then return false end
  local server = e.src == "line" or e.src == "news"
  local d = store()
  local key = e.g .. ":" .. e.id
  -- (a repeat from ach_recent, which tells an earn for 14 days: nothing new)
  if d.achSeen[key] and e.approx and not server then return false end
  local m = member(e.g)
  if not m or C.Policy:Untrusted(e.g) then A.refused = A.refused + 1; return false end
  local info = A.Info(e.id)
  if not info or info.guild then A.refused = A.refused + 1; return false end
  local t = math.floor(e.t or now())
  self:Record("a" .. e.id, { g = e.g, n = m.name, t = t, src = e.src, approx = e.approx }, function() return achCard(info, m, t, "first") end, info.name)
  local id = "a:" .. key
  if d.achSeen[key] then
    -- (the server shows one Cute sent: marked so in the queue; one dated by its day alone takes the 1A's time)
    local it = H().Item(id)
    if it and server and not it.mark then it.mark = "server"; H().Refresh() end
    if it and it.approx and not e.approx then it.t, it.approx = t, nil; if it.card then it.card.value = "Earned " .. dayText(t) end end
    return false
  end
  -- (remembered once queued: one the day's row had no room for may come again with tomorrow's ach_recent)
  local ok = H():Queue({ id = id, src = "ach", from = e.from or "server", digest = "ach", what = info.name, mark = server and "server" or nil, t = t,
    approx = e.approx or nil, lock = not H().Open("a" .. e.id) or nil, card = achCard(info, m, t) })
  if ok then remember(d, key, A.Day(t)); A.taken = A.taken + 1 end
  return ok
end
-- a guild achievement from guild news: a guild card (no member: the guild's name, the achievement's icon)
local function guildName()
  local club = C.Get(C.Api("C_Club", "GetGuildClubId"))
  local info = club ~= nil and C.Get(C.Api("C_Club", "GetClubInfo"), club) or nil
  local name = type(info) == "table" and C.Plain(info.name) or nil
  return (type(name) == "string" and name ~= "") and name or "The guild"
end
A.GuildName = guildName
function A:GuildEarn(id, t)
  if not A.Taking() then return false end
  local info = A.Info(id)
  if not info then return false end
  local d = store()
  local key = "guild:" .. id
  if d.achSeen[key] then return false end
  local ok = H():Queue({ id = "g:" .. id, src = "ach", from = "server", digest = "ach", what = info.name, mark = "server", t = t,
    lock = not H().Open("a" .. id) or nil,
    card = { guild = true, sfx = "G", name = clean(guildName(), 24), kind = "ach", title = clean(info.name, 24), line = clean(info.desc, 56),
      value = "Earned " .. dayText(t), valueLabel = clean(info.cat or "Guild achievement", 24), icon = info.icon, source = "a" .. id } })
  if ok then remember(d, key, A.Day(t)) end
  return ok
end

-- 1A (Comm.lua hands it over, on GUILD or whispered): an officer's client takes it; a member's ignores it
function A:Receive(text, sender)
  if not A.Taking() then return end
  local id, t = text:match("^1A|(%w+)|(%w+)$")
  id, t = unb36(id or ""), unb36(t or "")
  if not (id and t) then return end
  local g = C.Roster:GuidOf(sender)
  if not g or C.Policy:Untrusted(g) then A.refused = A.refused + 1; return end
  -- (20 from one sender in ten minutes: a login fires no earns, so a burst past it is an edited copy)
  local list = A.takenFrom[g] or {}
  A.takenFrom[g] = list
  local at = gtime()
  for i = #list, 1, -1 do if at - list[i] >= TAKE_WINDOW then table.remove(list, i) end end
  if #list >= TAKE_MAX then A.refused = A.refused + 1; return end
  list[#list + 1] = at
  -- (its own time where it was held through an instance, six hours at most; else when it came)
  local arrived = now()
  if t > arrived + 60 or t < arrived - HELD_MAX then t = arrived end
  self:Earn({ g = g, id = id, t = t, src = "cute", from = sender })
end

-- a member's ach_recent (whispered, Comm.lua M:Receive before the roster takes it): the earns this officer has not
-- queued, 20 new from one sender a day at most, none later than this officer's own day. The number taken
function A:Recent(sender, text)
  if not A.Taking() or type(text) ~= "string" then return 0 end
  local g = C.Roster:GuidOf(sender)
  if not g or C.Policy:Untrusted(g) then return 0 end
  local today = A.Day()
  local key = g .. ":" .. today
  local n = 0
  for a, b in text:gmatch("(%w+):(%w+)") do
    local id, day = unb36(a), unb36(b)
    if id and day and day <= today and day >= today - RECENT_DAYS then
      if (A.recentTaken[key] or 0) >= RECENT_MAX then break end
      if self:Earn({ g = g, id = id, t = dayTime(day), src = "cute", from = sender, approx = true }) then
        n = n + 1
        A.recentTaken[key] = (A.recentTaken[key] or 0) + 1
      end
    end
  end
  return n
end

-- the server's guild line, where it comes plain: the achievement by the link in its text, the member by its guid
-- (the twelfth argument, ChatInfoDocumentation.lua:1649-1672), checked against the roster. A secret line is skipped
function A:Line(text, guid)
  if not A.Taking() then return end
  if (issecretvalue and (issecretvalue(text) or issecretvalue(guid))) or type(text) ~= "string" or type(guid) ~= "string" then A.secret = A.secret + 1; return end
  local id = tonumber(text:match("|Hachievement:(%d+):") or "")
  if not id or not (C.Roster.byGuid and C.Roster.byGuid[guid]) then return end
  A.lines = A.lines + 1
  self:Earn({ g = guid, id = id, t = now(), src = "line", from = "server" })
end

----------------------------------------------------------------------------
-- guild news, on an officer's client: asked 30 s after login and once an hour (QueryGuildNews), read on
-- GUILD_NEWS_UPDATE or 10 s after the ask where none came (the game's own frame calls GuildNewsSort after its ask,
-- which Cute never does, nor does it set the news filters: the officer's own view stays as they left it). The list
-- follows those filters (GetGuildNewsFilters, read only as the game's filter popup reads them: 1 guild achievements,
-- 2 achievements, the popup's button ids, GuildNews.xml:401-406): with achievements off, guild news is unavailable
-- for seeding and dating, which the "Guild first?" tooltip and /cute diag cards say. Each entry by
-- C_GuildInfo.GetGuildNewsInfo(index) (GuildInfoDocumentation.lua:61: newsType 1 a member's achievement, 0 the
-- guild's, whoText the member, newsDataID the achievement, day and month from 0, GuildUtil.lua:57-84)
----------------------------------------------------------------------------
local NEWS_MAX = 300
function A:QueryNews()
  if not A.Taking() then return end
  if not callable("QueryGuildNews") then A.news.state = "missing"; return end
  call("QueryGuildNews")
  A.news.askedAt = gtime()
  if A.news.state == "none" then A.news.state = "asked" end
  local asked = A.news.askedAt
  C_Timer.After(NEWS_WAIT, C.Safe(function() if (A.news.readAt or -1) < asked then A:ReadNews() end end, "achievements: guild news"))
end
-- (guild achievements, achievements: on where the client says so; both on where it says nothing at all)
local function newsFilters(ok, ...)
  if not ok or select("#", ...) < 2 then return true, true end
  local guildOn, achOn = ...
  return C.Plain(guildOn) and true or false, C.Plain(achOn) and true or false
end
local function filters()
  if not callable("GetGuildNewsFilters") then return true, true end
  return newsFilters(pcall(GetGuildNewsFilters))
end
function A:ReadNews()
  if not A.Taking() then return end
  A.news.readAt = gtime()
  local GI = C_GuildInfo
  if not (callable("GetNumGuildNews") and type(GI) == "table" and type(GI.GetGuildNewsInfo) == "function") then A.news.state = "missing"; return end
  local guildOn, achOn = filters()
  A.news.filter = achOn
  local n = C.Num("GetNumGuildNews") or 0
  local read, guild, unknown = 0, 0, 0
  for i = 1, math.min(n, NEWS_MAX) do
    local e = C.Get(GI.GetGuildNewsInfo, i)
    if type(e) == "table" and C.Plain(e.isHeader) ~= true then
      local kind, id = C.Plain(e.newsType), C.Plain(e.newsDataID)
      local y, mo, d = C.Plain(e.year), C.Plain(e.month), C.Plain(e.day)
      local t
      if type(y) == "number" and type(mo) == "number" and type(d) == "number" then
        if y < 100 then y = y + 2000 end
        t = daysOf(y, mo + 1, d + 1) * 86400 + 43200
      end
      if type(id) == "number" and t then
        if kind == 1 and achOn then
          local who = C.Plain(e.whoText)
          local m = type(who) == "string" and A.MemberNamed(who) or nil
          if m then read = read + 1; self:Earn({ g = m.guid, id = id, t = t, src = "news", from = "server", approx = true }) else unknown = unknown + 1 end
        elseif kind == 0 and guildOn then
          guild = guild + 1
          self:GuildEarn(id, t)
        end
      end
    end
  end
  A.news.n, A.news.guild, A.news.unknown = read, guild, unknown
  A.news.state = not achOn and "off" or (n > 0 and "read" or "empty")
end
-- a member by the name guild news gives: the sender string's way (Roster.lua R:SenderMember), else one whose short
-- name it is, where only one has it
function A.MemberNamed(who)
  local R = C.Roster
  local m = R.SenderMember and R:SenderMember(who)
  if m and m.guid then return m end
  local found
  for _, x in ipairs(R.members or {}) do
    if x.guid and x.name and C.Short(x.name) == who then if found then return nil end found = x end
  end
  return found
end
local function newsSettled() local s = A.news.state; return s == "read" or s == "off" or s == "empty" or s == "missing" end
-- what guild news says about a first, where it cannot vouch for one (nil where it reads as it should)
function A.NewsWords()
  local s = A.news.state
  if s == "off" then return "Guild news is hidden by your news filters (achievements off)." end
  if s == "missing" then return "Guild news does not read on this client." end
  if s == "empty" then return "Guild news shows nothing yet." end
  return nil
end

----------------------------------------------------------------------------
-- the firsts ledger (officers only). e = { g, n, t, src }: src "cute" (one member's Cute: a 1A or ach_recent), "line"
-- (the server's line), "news" (guild news), "kill" (a kill two members' Cute corroborated, Rules.lua rule 9), "level"
-- (a member's level as their Cute sent it), "roster" (the roster's level), "seed" (what the guild had before)
----------------------------------------------------------------------------
function A.Firsts()
  if not (C.Roster and C.Roster:OfficerStill()) then return nil end
  local d = H().DB()
  if type(d.firsts) ~= "table" then d.firsts = { e = {}, n = 0 } end
  local L = d.firsts
  if type(L.e) ~= "table" then L.e, L.n = {}, 0 end
  return L
end
-- may the ledger suggest: seeded with this version, a login's answers in (90 s), guild news read this session (where
-- the server keeps it and the filters allow it)
function A.Ready()
  local L = A.Firsts()
  return L ~= nil and L.v == LEDGER_V and A.loginAt ~= nil and gtime() - A.loginAt >= READY_AFTER and newsSettled()
end
local function firstsToday()
  local n, today = 0, date and date("%Y-%m-%d") or ""
  for _, r in ipairs(H().Rows()) do if r.src == "first" and r.day == today then n = n + 1 end end
  return n
end
-- an entry for a key, where it is the earliest known; and a "Guild first?" row where the ledger may suggest and this
-- is a first: no earlier entry, or an earlier one resting on another member's Cute alone (shown beside it). make(earlier)
-- gives the row's card; what names it in the row's tooltip
local RESTS = {
  a = "No earlier earn in guild news or from any member's Cute.",
  b = "No earlier kill of it two members' Cute agreed on.",
  c = "No member at the level cap before.",
}
function A:Record(key, e, make, what)
  local L = A.Firsts()
  if not L or type(key) ~= "string" then return end
  local t = math.floor(e.t or 0)
  local s = sfxOf(e.g)
  local entry = L.e[key]
  if entry and s and entry.g == s then
    -- (the same member again: a time to the second over a day's, else the earlier; a server's word over one Cute's)
    if entry.a and not e.approx then entry.t, entry.a = t, nil
    elseif t < (entry.t or 0) and (e.approx or not entry.a) then entry.t = t end
    if entry.src == "cute" and (e.src == "line" or e.src == "news") then entry.src = e.src end
    return
  end
  -- (an entry dated by its day alone is at or before anything of that day: which came first within it nobody knows)
  local first = entry and ((entry.a or e.approx) and A.Day(entry.t or 0) <= A.Day(t) or (entry.t or 0) <= t)
  -- (someone earlier on more than one member's Cute, or from the server: no first)
  if first and entry.src ~= "cute" then return end
  local earlier = first and entry or nil
  if not first then
    if not entry and (L.n or 0) >= LEDGER_MAX then return end
    if not entry then L.n = (L.n or 0) + 1 end
    L.e[key] = { g = s, n = e.n, t = t, src = e.src, a = e.approx or nil }
  end
  if e.quiet or not make or not A.Ready() or not s then return end
  local card = make(earlier)
  if not card then return end
  local kind = key:sub(1, 1)
  local rests = earlier and string.format("Earlier: %s, %s, on %s's Cute alone. You choose.", earlier.n or "?", dayText(earlier.t or 0), earlier.n or "?") or RESTS[kind]
  if kind == "a" and not earlier then rests = rests .. (A.NewsWords() and (" " .. A.NewsWords()) or "") end
  A.firsts = A.firsts + 1
  -- (from the member: ten rows a sender is ten firsts a member, Halls.lua)
  H():Queue({ id = "f:" .. key .. ":" .. s, src = "first", from = "m:" .. s, what = what or card.title, mark = "Guild first?", t = t,
    digest = firstsToday() >= FIRSTS_DAY and "first" or nil, first = { key = key, earlier = earlier and { n = earlier.n, t = earlier.t, src = earlier.src } or nil },
    rests = rests, lock = not H().Open(card.source) or nil, card = card })
end

-- a boss's first corroborated kill (Rules.lua rule 9: the claim that made another member's name it back): its claim's
-- time, the claimant on the card. Suggested where the claim is recent (a login's claims told again are old news)
local function bossCard(enc, g, t)
  local m = member(g)
  if not m then return nil end
  local S = C.Stats
  local inst = S.InstOf and S.InstOf(enc)
  return { guid = g, sfx = sfxOf(g), name = m.name, class = m.class, kind = "first", title = clean(S.LabelOf("e" .. enc) or "A boss", 24),
    line = "First in the guild to bring it down.", value = "Killed " .. dayText(t), valueLabel = clean(inst and S.LabelOf("i" .. inst) or "", 24), source = "b" .. enc }
end
function A:Killed(enc, g, t)
  if not (A.Taking() and type(enc) == "number" and type(g) == "string" and type(t) == "number") then return end
  local m = member(g)
  self:Record("b" .. enc, { g = g, n = m and m.name, t = t, src = "kill", quiet = now() - t > KILL_LIVE }, function() return bossCard(enc, g, t) end)
end
do
  local R = C.Rules
  local claim = R.Claim
  -- (every claim, a member's from the channel and your own, goes through R.Claim: the moment a boss's kills are
  -- corroborated for the first time is its first kill by the guild)
  R.Claim = function(guid, enc, t, with)
    local before = R.KilledSeen(enc)
    claim(guid, enc, t, with)
    if not before and R.KilledSeen(enc) then C.Safe(function() A:Killed(enc, guid, t) end, "achievements: first kill")() end
  end
end

-- the first member at the level cap: a member's level from a delta (live; a full record's is recorded quietly), your
-- own level up; the roster's levels seed it
local function capCard(cap, g, t)
  local m = member(g)
  if not m then return nil end
  return { guid = g, sfx = sfxOf(g), name = m.name, class = m.class, kind = "first", title = "Level " .. cap, line = "First in the guild to reach the cap.",
    value = "Reached " .. dayText(t), valueLabel = "the level cap", source = "c" .. cap }
end
function A:Level(g, level, live)
  if not (A.Taking() and type(level) == "number" and type(g) == "string") then return end
  local cap = C.Rules.Cap()
  if not cap or level < cap then return end
  local m = member(g)
  local t = math.floor(now())
  self:Record("c" .. cap, { g = g, n = m and m.name, t = t, src = "level", quiet = not live }, function() return capCard(cap, g, t) end)
end

-- Comm.lua hands every record and delta here before the roster takes it: a member's ach_recent (whispered to the
-- officers only: one on GUILD is an edited copy's) and a member's level at the cap. A level is taken as the roster
-- takes it (Roster.lua R:Apply holds one the guild roster does not bear out yet and judges it once the roster reads
-- again, R:Dings): looked at in the record 3 s and 20 s on; a delta's (1D) is live, a full record's (1F) quiet
local function levelCheck(sender, live)
  if not A.Taking() then return end
  local e = CuteDB.roster and CuteDB.roster[sender]
  local lvl = type(e) == "table" and type(e.stats) == "table" and e.stats.level or nil
  local g = C.Roster:GuidOf(sender)
  if type(lvl) == "number" and g and C.Roster.byGuid[g] and not C.Policy:Untrusted(g) then A:Level(g, lvl, live) end
end
function A:Seen(sender, kv, whispered, kind)
  if type(kv) ~= "table" or not A.Taking() then return end
  if type(kv.ach_recent) == "string" and whispered then self:Recent(sender, kv.ach_recent) end
  local cap = C.Rules.Cap()
  if type(kv.level) == "number" and cap and kv.level >= cap then
    local live = kind == "1D"
    for _, wait in ipairs({ 3, 20 }) do C_Timer.After(wait, C.Safe(function() levelCheck(sender, live) end, "achievements: the cap")) end
  end
end

-- the seed, 90 s into an officer's login while the ledger has not this version's: the members' ach_recent the records
-- hold (whispered to this officer), the kills the guild corroborated and the bosses its members met, and the members
-- the roster lists at the cap; guild news joins it as it is read. All quiet: what the guild had is no first
function A:Seed()
  local L = A.Firsts()
  if not (L and A.Taking()) or L.v == LEDGER_V then return end
  for _, e in pairs(CuteDB.roster or {}) do
    local st = type(e) == "table" and e.stats
    local g = type(st) == "table" and st.guid
    if type(g) == "string" and type(st.ach_recent) == "string" and not C.Policy:Untrusted(g) then
      local m = member(g)
      for a, b in st.ach_recent:gmatch("(%w+):(%w+)") do
        local id, day = unb36(a), unb36(b)
        if id and day and id > 0 and id < 10000000 then self:Record("a" .. id, { g = g, n = m and m.name, t = dayTime(day), src = "cute", approx = true, quiet = true }) end
      end
    end
  end
  local k = C.Stats.Known()
  for enc in pairs(k and type(k.kills) == "table" and k.kills or {}) do if type(enc) == "number" then self:Record("b" .. enc, { t = 0, src = "seed", quiet = true }) end end
  local model = k and type(k.model) == "table" and k.model.bosses
  for enc, b in pairs(type(model) == "table" and model or {}) do
    if type(enc) == "number" and type(b) == "table" and (tonumber(b.kills) or 0) > 0 then self:Record("b" .. enc, { t = 0, src = "seed", quiet = true }) end
  end
  local cap = C.Rules.Cap()
  for _, m in ipairs(C.Roster.members or {}) do
    if m.guid and type(m.level) == "number" and cap and m.level >= cap then self:Record("c" .. cap, { g = m.guid, n = m.name and C.Short(m.name), t = 0, src = "roster", quiet = true }) end
  end
  L.v, L.at = LEDGER_V, math.floor(now())
end

----------------------------------------------------------------------------
-- /cute diag cards: the achievements' line (counts and states, no name)
----------------------------------------------------------------------------
function A.Diag()
  local L = A.Firsts()
  local ch = C.Char()
  return {
    string.format("diag cards: achievements %s (guild %s) | earned %d, 1A sent %d, held %d | taken %d, refused %d | server lines %d, secret %d | guild news read %d (%s, achievements filter %s), no member by its name %d, guild ones %d | ledger %s, firsts %d",
      moduleOn() and "on" or "off", A.GuildOn() and "on" or "off", A.earned, A.sent, type(ch.pending) == "table" and #ch.pending or 0, A.taken, A.refused,
      A.lines, A.secret, A.news.n or 0, A.news.state, A.news.filter == false and "off" or (A.news.filter and "on" or "unknown"), A.news.unknown or 0, A.news.guild or 0,
      L and string.format("%d entries, %s", L.n or 0, L.v == LEDGER_V and "seeded" or "not seeded") or "none (members keep none)", A.firsts),
  }
end

----------------------------------------------------------------------------
-- Settings > Achievements: the officers' switch for the whole guild (greyed for members, who set it said), and where
-- guild news cannot vouch for a first on this officer's client, why
----------------------------------------------------------------------------
function A.Settings(_, col)
  local isOfficer = C.Roster:MeOfficer()
  col:Head("Achievements")
  col:Check("On for the whole guild", A.GuildOn(), isOfficer, function(on)
    C.Policy:SetRule("achGuild", (not on) and 0 or nil)
    C.Comm:PolicySoon()
    A:SetRecent()
    C.UI:Draw()
  end, not isOfficer and "Set by the officers" or nil, function(tip)
    tip:AddLine("On for the whole guild", 1, 1, 1)
    tip:AddLine("Off: no member's Cute sends achievements. Each member can also switch Achievements off in Modules.", 0.85, 0.85, 0.85, true)
    local by = C.Rules.SetBy("achGuild")
    if by then tip:AddLine("Switched off by " .. C.Rules.WhoName(by) .. ".", 0.7, 0.7, 0.7, true) end
  end)
  if isOfficer and A.NewsWords() then col:Note(A.NewsWords()) end
end

----------------------------------------------------------------------------
-- events. The module's own (heard while it is on): your earns, the server's line, guild news, your level. And a core
-- frame for the loading screen: the login's time, the pending earns, guild news' first ask and the seed
----------------------------------------------------------------------------
local function newsSoon()
  if A.newsReadDue then return end
  A.newsReadDue = true
  C_Timer.After(1, C.Safe(function() A.newsReadDue = false; A:ReadNews() end, "achievements: guild news"))
end
local events = {
  ACHIEVEMENT_EARNED = function(id, already) A:Earned(id, already) end,
  -- (text, playerName, ..., lineID, guid: the twelfth)
  CHAT_MSG_GUILD_ACHIEVEMENT = function(text, _, _, _, _, _, _, _, _, _, _, guid) A:Line(text, guid) end,
  GUILD_NEWS_UPDATE = function() if A.Taking() then newsSoon() end end,
  PLAYER_LEVEL_UP = function(level) level = C.Plain(level); if officer() and type(level) == "number" then A:Level(C.MyGUID(), level, true) end end,
}
local function newsEvery()
  A:QueryNews()
  C_Timer.After(NEWS_EVERY, C.Safe(newsEvery, "achievements: guild news"))
end
local function seedLater()
  C_Timer.After(READY_AFTER, C.Safe(function()
    if A.Taking() and A.Firsts() then A:Seed(); prune(store()) else C_Timer.After(300, C.Safe(seedLater, "achievements: seed")) end
  end, "achievements: seed"))
end
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", C.Safe(function()
  if not A.loginAt then
    A.loginAt = gtime()
    C_Timer.After(NEWS_FIRST, C.Safe(newsEvery, "achievements: guild news"))
    seedLater()
  end
  A:SetRecent()
  C_Timer.After(3, C.Safe(function() A:Flush() end, "achievements: pending"))
end, "achievements: events"))
-- the switch a rule: when the officers' rules change (here or from the channel), what this character sends follows
do
  local R = C.Rules
  local retuned = R.Retuned
  R.Retuned = function(self, ...)
    retuned(self, ...)
    C.Safe(function() A:SetRecent() end, "achievements: the guild's switch")()
  end
end

C:RegisterModule({
  id = "ach", title = "Achievements", order = 46, builtin = true, default = true,
  notes = "Achievements as members earn them, and guild firsts, reach the officers' Queue.",
  settings = function(ui, col) A.Settings(ui, col) end,
  events = events,
  onToggle = function(on)
    -- (switched off: no 1A, nothing held to send later, no ach_recent)
    if not on then C.Char().pending = nil end
    A:SetRecent()
  end,
})
