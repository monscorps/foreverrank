-- SPDX-License-Identifier: GPL-3.0-or-later
-- Halls: the guild base's cards (the run report's design, sections 9, 10 and 13.2): what the officers publish and every
-- member receives, whatever modules they run.
--   Queue    each officer's own (CuteDB.halls[club].queue): a row for what an officer is likely to publish (a GOLD STAR
--            from a run, a hall, a card by hand, a draft) and one digest row a day per source for the rest (the run
--            cards that are no GOLD STAR); 100 rows at most, 10 from one sender, none older than 30 days, the oldest out
--            first and never a draft (6 at most)
--   Publish  an officer's set of one to five cards goes on GUILD as 1C, with its sources (a<id> an achievement,
--            r<run>.<CODE> a run's award, s<stat> a hall's or a record's stat), and shows on the officer's own screen
--            as everyone sees it; one guild chat line in the same click where the officer ticked it. Greyed for 60 s
--            after any officer's set, after 10 of this officer's in an hour, and for an officer three minutes into a
--            login who has had no answer to its 1G. Withdraw sends the set's stamp and x; Update a hall's leaders again
--   Receive  a set from a sender R:OfficerVoice passes (an officer by the roster, not marked untrusted) is kept (the last
--            30), greys the queue items it published in every officer's queue, and shows once as a toast: one at a
--            time, three waiting, two an hour, none in combat, an encounter, a loading screen or a dungeon or raid,
--            nothing from a sender past 10 sets in an hour and nothing for an answer to 1G (News alone). A card whose
--            source the policy routes Only you now is dropped. Cute's own guild line from that officer is hidden for a
--            minute, so a member with Cute sees a set once
--   1G       every client once, a minute after its hello: the newest set it holds. An officer holding newer ones answers
--            with them (the last five), the lowest GUID first and the others only where no answer came meanwhile, once
--            in half an hour an asker
--   1W       a run's cards to the officers (9.3): the run's guild member with the smallest GUID among those with Runs on
--            whispers them to each officer online, held while inside an instance; an officer takes 4 a sender an hour,
--            one per run, and queues them
--   Halls    a set from stats (9.5): Fame or Shame, All time, This week or Last week, five stats from the picker
--            (Halls.PickStat, the game's MenuUtil menu), the leaders from the officer's roster (members with Cute, not
--            untrusted, the stat routed Everyone, within its bounds; no member twice). Last week is each member's value
--            as a reset replaced it (H:Seen keeps it as the roster takes it)
--   The tab  J's Halls tab is the core's shame page retitled (its id kept): chips Hall of Shame (0.7's live cards),
--            News, and Queue for officers; Settings > Halls; /cute halls, /cute card test [hall], /cute diag cards
-- And the two weekly stats the halls read beside the runs' own: Deaths this week and Quests this week (section 10).
local _, C = ...
local H = { parts = {}, toasts = {}, ticked = {}, open = {}, answered = {}, waiting = {}, senders = {}, runsHeard = {} }
C.Halls = H

local QUEUE_MAX, PER_SENDER, QUEUE_DAYS, DRAFTS, DIGEST_MAX = 100, 10, 30, 6, 60
local SETS = 30           -- sets kept, newest first
local GAP, HOUR = 60, 3600
local PUBLISH_HOUR = 10   -- sets an officer publishes in an hour; past it from a sender, News alone
local LOGIN_WAIT = 180    -- an officer's Publish waits this long into a login for an answer to its 1G
local TOAST_SHOW, TOAST_WAIT, TOAST_HOUR = 10, 3, 2
local ASK_AFTER, ANSWER_AGAIN, ANSWER_SETS = 60, 1800, 5
local W_HOUR, W_SAME = 4, 600
local TITLE, LINE, NAME, VALUE, VLABEL = 24, 56, 12, 16, 24
local WHITE, INK, DIM, MUTE = { 0.96, 0.96, 0.96 }, { 0.86, 0.86, 0.86 }, { 0.58, 0.58, 0.58 }, { 0.52, 0.52, 0.52 }
local DOT = " \194\183 " -- (a middle dot in Windows-1252; the file stays ASCII)
local function now() return C.ServerNow() end
local function gtime() return (GetTime and GetTime()) or 0 end
local function callable(name) return type(_G[name]) == "function" end
local function call(name, ...) if not callable(name) then return nil end return C.Get(_G[name], ...) end
local function sfxOf(g) return type(g) == "string" and g:match("([^%-]+)$") or nil end
local function b36(n) return C.Comm.b36(n) end
local function unb36(s) return C.Comm.unb36(s) end
local function color(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end
local function rnd() return (math.random and math.random()) or 0.5 end

----------------------------------------------------------------------------
-- the week: Sample.lua's key ("%Y-%W", the week starting on Monday) as a number, so "last week" is the one before.
-- The Monday of a key is the days since 1970 to it (the year's first Monday, then whole weeks; week 0 is the days
-- before it), and the week's number counts Mondays from 5 January 1970
----------------------------------------------------------------------------
local yearDays = {}
local function daysBefore(y)
  local d = yearDays[y]
  if d then return d end
  d = 0
  for yy = 1970, y - 1 do d = d + ((yy % 4 == 0 and (yy % 100 ~= 0 or yy % 400 == 0)) and 366 or 365) end
  yearDays[y] = d
  return d
end
-- a week's key, its Monday (days since 1970) and its number
function H.Monday(key)
  local y, w = tostring(key or ""):match("^(%d%d%d%d)%-(%d%d)$")
  y, w = tonumber(y), tonumber(w)
  if not (y and w and y >= 1970 and y < 2200) then return nil end
  local d0 = daysBefore(y)
  return d0 + (8 - (d0 + 4) % 7) % 7 + (w - 1) * 7
end
function H.WeekKey() return date and date("%Y-%W") or "" end
function H.WeekOf(key) local m = H.Monday(key); return m and (m + 3) / 7 or nil end
function H.WeekNow() return H.WeekOf(H.WeekKey()) end
-- "Week of 19 Oct" for a week's number (now, or the one before)
function H.WeekTitle(n)
  n = n or H.WeekNow()
  if not (n and date) then return "This week" end
  return "Week of " .. (date("%d %b", (n * 7 - 3) * 86400 + 43200):gsub("^0", ""))
end

----------------------------------------------------------------------------
-- the two weekly stats (section 10): the core's, counted by Sample whatever module is on (PLAYER_DEAD,
-- QUEST_TURNED_IN), reset on Monday as Logins this week is; each lifetime count reveals its week, as Deaths its day
----------------------------------------------------------------------------
do
  local S = C.Stats
  S.def("deaths_week", "Deaths this week", "funny", { code = "dw", count = "PLAYER_DEAD", hint = "deaths since Monday" })
  S.def("quests_week", "Quests this week", "leveling", { code = "qw", count = "QUEST_TURNED_IN", hint = "quests handed in since Monday" })
  for _, p in ipairs({ { "deaths", "deaths_week" }, { "quests_done", "quests_week" } }) do
    local d = S.byId[p[1]]
    if d then d.reveals = d.reveals or {}; d.reveals[#d.reveals + 1] = p[2] end
  end
  C.Sample.WEEKLY.deaths_week, C.Sample.WEEKLY.quests_week = true, true
end

----------------------------------------------------------------------------
-- the guild's own store (CuteDB.halls by club): the queue, the sets, the drafts, the weeks, what was withdrawn
----------------------------------------------------------------------------
function H.DB()
  local club = C.Roster and C.Roster.ClubId and C.Roster:ClubId() or nil
  local key = club ~= nil and tostring(club) or "none"
  if type(CuteDB.halls) ~= "table" then CuteDB.halls = {} end
  local d = CuteDB.halls[key]
  if type(d) ~= "table" then d = {}; CuteDB.halls[key] = d end
  for _, k in ipairs({ "queue", "sets", "weeks", "gone" }) do if type(d[k]) ~= "table" then d[k] = {} end end
  return d
end
local function settings()
  local s = C.Settings()
  if type(s.halls) ~= "table" then s.halls = { toast = true, chat = true } end
  return s.halls
end
H.Prefs = settings

----------------------------------------------------------------------------
-- last week (9.5): each member's weekly values as the officer's roster takes them (H:Seen, from Comm.lua before
-- R:Apply), by GUID: { n = the week they were seen in, v = { id = value }, p = { n, v } the week before's last }. A new
-- week moves what was held to p; a value that falls within a week is the member's own Monday (a client's week turns
-- by its own clock) and moves to p as last week's. Yours are Sample's (CuteDB.chars[me].lastWeek, the week a reset
-- replaced)
----------------------------------------------------------------------------
local function guidOfSender(sender, kv)
  local R = C.Roster
  local g = R and R.GuidOf and R:GuidOf(sender) or nil
  if not g and type(kv.guid) == "string" and R and R.byGuid and R.byGuid[kv.guid] then g = kv.guid end
  return g
end
function H:Seen(sender, kv)
  if type(kv) ~= "table" then return end
  local weekly = C.Sample.WEEKLY
  local any = false
  for id, v in pairs(kv) do if weekly[id] and type(v) == "number" then any = true break end end
  if not any then return end
  local g = guidOfSender(sender, kv)
  local n = H.WeekNow()
  if not (g and n) then return end
  local weeks = H.DB().weeks
  local rec = weeks[g]
  if type(rec) ~= "table" or type(rec.v) ~= "table" then rec = { n = n, v = {} }; weeks[g] = rec end
  if rec.n ~= n and rec.n < n then rec.p = { n = rec.n, v = rec.v }; rec.n, rec.v = n, {} end
  for id, v in pairs(kv) do
    if weekly[id] and type(v) == "number" then
      local cur = rec.v[id]
      if type(cur) == "number" and v < cur then
        if not (type(rec.p) == "table" and rec.p.n == n - 1) then rec.p = { n = n - 1, v = {} } end
        rec.p.v[id] = cur
      end
      rec.v[id] = v
    end
  end
end
-- a member's value of a weekly stat as it stood when last week ended (yours: Sample's); nil where unknown
function H.LastWeek(guid, id)
  local n = H.WeekNow()
  if not n then return nil end
  if guid == C.MyGUID() then
    local lw = C.Char().lastWeek
    if type(lw) == "table" and type(lw.v) == "table" and H.WeekOf(lw.to) == n and H.WeekOf(lw.from) == n - 1 then return lw.v[id] end
    return nil
  end
  local rec = H.DB().weeks[guid]
  if type(rec) ~= "table" then return nil end
  if type(rec.p) == "table" and rec.p.n == n - 1 and type(rec.p.v) == "table" and rec.p.v[id] ~= nil then return rec.p.v[id] end
  if rec.n == n - 1 and type(rec.v) == "table" then return rec.v[id] end
  return nil
end
-- a member's value of a weekly stat this week, as the roster took it this week (one from before Monday is last
-- week's, not this one's); yours as Sample holds it
function H.ThisWeek(guid, id)
  if guid == C.MyGUID() then return C.Sample:Value(id) end
  local rec = H.DB().weeks[guid]
  if type(rec) == "table" and rec.n == H.WeekNow() and type(rec.v) == "table" then return rec.v[id] end
  return nil
end

