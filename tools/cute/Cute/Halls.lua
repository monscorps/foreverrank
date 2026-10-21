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
--            source the policy routes Only you now is dropped. Cute's own guild line from an officer is hidden
--            (H.LineFilter), so a member with Cute sees a set once
--   1G       every client once, a minute after its hello: the newest set it holds and the stamp of the records the
--            officers turned on (Records.lua). An officer holding newer ones answers with them (the last five, and 1O),
--            the lowest GUID first and the others only where no answer came meanwhile, once in half an hour an asker
--   1W       a run's cards to the officers (9.3): the run's guild member with the smallest GUID among those with Runs on
--            whispers them to each officer online, held while inside an instance; an officer takes 4 a sender an hour,
--            one per run, and queues them
--   Halls    a set from stats (9.5): Fame or Shame, All time, This week or Last week, five stats from the picker
--            (Halls.PickStat, the game's MenuUtil menu), the leaders from the officer's roster (members with Cute, not
--            untrusted, the stat routed Everyone, within its bounds; no member twice). Last week is each member's value
--            as a reset replaced it (H:Seen keeps it as the roster takes it)
--   The tab  J's Halls tab is the core's shame page retitled (its id kept): chips Hall of Shame (0.7's live cards),
--            News, Records (Records.lua's, while it is on) and Queue for officers; Settings > Halls; /cute halls, /cute
--            card test [hall], /cute diag cards
--   Local    a set this client made itself, never sent (a fastest clear that fell, Records.lua): kept in News and toasted
--            as a set is, once a day an instance; no 1G asks for it or answers with it
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

----------------------------------------------------------------------------
-- cards and sets. A card is { guid, sfx, name, class, race, sex, kind, title, line, value, valueLabel, icon, source }
-- (Cards.lua draws it); a set is { at, kind, title, by, period, ranked, cards }, its kind the announcement's header
----------------------------------------------------------------------------
H.LABEL = { star = "GOLD STAR", shout = "SHOUT-OUT", blooper = "BLOOPER", thanks = "THANKS", first = "GUILD FIRST", ach = "ACHIEVEMENT", record = "RECORD" }
H.KINDS = { "star", "shout", "blooper", "thanks", "first", "ach", "record" }
-- (a card's kind on the wire, one letter for life)
local CODE = { star = "S", shout = "O", blooper = "B", thanks = "T", first = "F", ach = "A", record = "R" }
local KIND_OF = {}
for k, v in pairs(CODE) do KIND_OF[v] = k end
H.HEAD = { n = "GUILD NEWS", f = "GUILD FIRST", r = "NEW RECORD", h = "HALL OF FAME", s = "HALL OF SHAME" }
local PERIOD_WORD = { a = "all time", w = "this week", l = "last week" }
H.PERIOD_WORD = PERIOD_WORD
-- the colour of a header: GUILD FIRST, NEW RECORD and HALL OF FAME the cards' STAR, HALL OF SHAME their BLOOPER, GUILD
-- NEWS white (8.1)
function H.HeadColor(kind)
  if kind == "f" or kind == "r" or kind == "h" then return C.Cards.STAR end
  if kind == "s" then return C.Cards.BLOOPER end
  return WHITE
end
-- text as a card may carry it on the wire: no | ; = and no comma (a comma and the spaces after it one space), cut to max
-- bytes, UTF-8 whole
local function clean(s, max) return C.Stats.CleanText((tostring(s or ""):gsub(",%s*", " ")), max) end
H.Clean = clean
local function bare(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function copy(t) local o = {}; for k, v in pairs(t) do o[k] = v end return o end
-- (a draft's tables its own: a draft opened and edited, then cleared, leaves the saved one as it was)
local function deep(t, depth)
  if type(t) ~= "table" or (depth or 0) > 4 then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = deep(v, (depth or 0) + 1) end
  return o
end
H.Deep = deep
local function officer() return C.Roster and C.Roster:MeOfficer() or false end
local function today() return date and date("%Y-%m-%d") or "" end
local function refresh() local U = C.UI; if U and U.frame and U.frame:IsShown() and U.page == "shame" then U:Refresh() end end
H.Refresh = refresh

-- may a card with this source show under the policy held now (12): a stat routed Everyone (s<stat>), every field a
-- run's award reads (r<run>.<CODE>), Achievements (a<id>), a boss's kills (b<encounter>, a first kill), the level
-- (c<level>, the first at the cap); a card by hand has none
function H.Open(source)
  if type(source) ~= "string" or source == "" then return true end
  local P, S = C.Policy, C.Stats
  local kind, rest = source:sub(1, 1), source:sub(2)
  if kind == "s" then
    if S.byId[rest] or S.IsDynamic(rest) then return P:Route(rest) == "all" end
    return false
  elseif kind == "r" then
    local code = rest:match("%.(%u%u)$")
    local a = code and C.Awards and C.Awards.Of(code)
    if not a then return false end
    for _, k in ipairs(a.reads) do local id = S.byCode[k]; if not id or P:Route(id) ~= "all" then return false end end
    return true
  elseif kind == "a" then
    local id = S.byCode.ac
    return id == nil or P:Route(id) == "all"
  elseif kind == "b" then
    return rest:match("^%d+$") ~= nil and P:Route("e" .. rest) == "all"
  elseif kind == "c" then
    return rest:match("^%d+$") ~= nil and P:Route("level") == "all"
  end
  return false
end

----------------------------------------------------------------------------
-- the officers' queue (9.1): newest first. A row is an item { id, src, from, at, day, card, what, lock, pub } or a
-- digest { id, digest, day, at, entries = { item, ... } }, or a draft { id, src = "draft", set }
----------------------------------------------------------------------------
local TITLES = { first = "Guild first", ach = "Achievements", record = "Records", run = "From the runs", card = "Guild news", hall = "Hall" }
function H.Rows() return H.DB().queue end
local function nonDraft(r) return r.src ~= "draft" end
local function prune()
  local q = H.Rows()
  local cutoff = now() - QUEUE_DAYS * 86400
  for i = #q, 1, -1 do
    local r = q[i]
    if type(r) ~= "table" or (nonDraft(r) and (tonumber(r.at) or 0) < cutoff) then table.remove(q, i) end
  end
  -- (10 rows from one sender: the newest kept)
  local per = {}
  for i = 1, #q do
    local r = q[i]
    if r and not r.entries and nonDraft(r) then
      per[r.from or "?"] = (per[r.from or "?"] or 0) + 1
      if per[r.from or "?"] > PER_SENDER then r.drop = true end
    end
  end
  for i = #q, 1, -1 do if q[i].drop then table.remove(q, i) end end
  -- (100 at most: the oldest goes first, never a draft)
  while #q > QUEUE_MAX do
    local gone = false
    for i = #q, 1, -1 do if nonDraft(q[i]) then table.remove(q, i); gone = true break end end
    if not gone then break end
  end
end
-- an item into this officer's queue: its own row, or the day's digest of its source (item.digest); one of the same id
-- is not queued twice. True where it was
function H:Queue(item)
  if not officer() or type(item) ~= "table" or type(item.id) ~= "string" then return false end
  item.at, item.day, item.from = item.at or now(), item.day or today(), item.from or "me"
  local q = H.Rows()
  for _, r in ipairs(q) do
    if r.id == item.id then return false end
    for _, e in ipairs(r.entries or {}) do if e.id == item.id then return false end end
  end
  if item.digest then
    local row
    for _, r in ipairs(q) do if r.digest == item.digest and r.day == item.day then row = r end end
    if not row then
      row = { id = "d:" .. item.digest .. ":" .. item.day, digest = item.digest, day = item.day, at = item.at, entries = {} }
      table.insert(q, 1, row)
    end
    if #row.entries >= DIGEST_MAX then return false end
    table.insert(row.entries, 1, item)
    row.at = math.max(row.at or 0, item.at)
  else
    table.insert(q, 1, item)
  end
  prune()
  refresh()
  return true
end
-- items out of the queue by id (published, or cleared); a digest emptied goes
function H:Unqueue(ids)
  local set = {}
  for _, id in ipairs(ids or {}) do set[id] = true end
  local q = H.Rows()
  for i = #q, 1, -1 do
    local r = q[i]
    if set[r.id] then table.remove(q, i)
    elseif r.entries then
      for j = #r.entries, 1, -1 do if set[r.entries[j].id] then table.remove(r.entries, j) end end
      if #r.entries == 0 then table.remove(q, i) end
    end
  end
  for id in pairs(set) do H.ticked[id] = nil end
end
-- an item another officer published greys in this one's queue: "Published by Brann". By its source and its member (an
-- achievement's source is the achievement's: another member's earn of it is not published)
function H:Grey(set, by)
  local srcs = {}
  for _, c in ipairs(set.cards or {}) do if type(c.source) == "string" and c.source ~= "" then srcs[c.source .. "|" .. (c.sfx or sfxOf(c.guid) or "")] = true end end
  local function mark(it)
    local c = it.card
    if c and srcs[tostring(c.source) .. "|" .. (c.sfx or sfxOf(c.guid) or "")] then it.pub = by; H.ticked[it.id] = nil end
  end
  for _, r in ipairs(H.Rows()) do
    mark(r)
    for _, e in ipairs(r.entries or {}) do mark(e) end
  end
end
-- every item, rows and digest entries, by id
function H.Item(id)
  for _, r in ipairs(H.Rows()) do
    if r.id == id then return r end
    for _, e in ipairs(r.entries or {}) do if e.id == id then return e end end
  end
end
-- the items ticked, in the queue's order
function H.Ticked()
  local out = {}
  for _, r in ipairs(H.Rows()) do
    if H.ticked[r.id] and r.card then out[#out + 1] = r end
    for _, e in ipairs(r.entries or {}) do if H.ticked[e.id] then out[#out + 1] = e end end
  end
  return out
end
-- may an item be ticked: one with a card, not published, not Only you
function H.Tickable(it) return it ~= nil and it.card ~= nil and not it.pub and not it.lock and H.Open(it.card.source) end

-- a set composed from 1 to 5 items (9.2): the cards in the order a run's report would have them (a GOLD STAR first, a
-- BLOOPER last), the title from the first, each card prefilled from its item
local RANK = { first = 1, star = 2, record = 3, ach = 4, shout = 5, thanks = 6, blooper = 7 }
function H:Compose(items)
  local list = {}
  for i, it in ipairs(items or {}) do if it.card then list[#list + 1] = { it = it, i = i } end end
  table.sort(list, function(a, b)
    local ra, rb = RANK[a.it.card.kind] or 9, RANK[b.it.card.kind] or 9
    if ra ~= rb then return ra < rb end
    return a.i < b.i
  end)
  local cards, from = {}, {}
  for _, e in ipairs(list) do
    if #cards < 5 then cards[#cards + 1] = copy(e.it.card); from[#from + 1] = e.it.id end
  end
  local first = list[1] and list[1].it or {}
  local kind = (first.src == "first" and "f") or (first.src == "record" and "r") or "n"
  return { kind = kind, title = TITLES[first.src] or "Guild news", cards = cards, from = from, chat = H.Prefs().chat ~= false }
end
-- a composed set kept as a row (Save draft), up to 6
function H:SaveDraft(set)
  if not officer() or type(set) ~= "table" then return false end
  local q, n = H.Rows(), 0
  for _, r in ipairs(q) do if r.src == "draft" then n = n + 1 end end
  if set.draftId then for i, r in ipairs(q) do if r.id == set.draftId then table.remove(q, i) n = n - 1 break end end end
  if n >= DRAFTS then return false, "Six drafts at most" end
  local id = "draft:" .. math.floor(now()) .. ":" .. math.floor(gtime() * 1000) % 100000
  local keep = deep(set)
  keep.draftId = id
  table.insert(q, 1, { id = id, src = "draft", at = now(), day = today(), from = "me", set = keep })
  refresh()
  return true
end

----------------------------------------------------------------------------
-- 1C: a set on the wire (13.2). h=<kind>,<title>,<by>,<period>,<ranked>, then a c= part per card: <suffix>,<name>,
-- <class>,<race>,<sex>,<label>,<icon>,<source>,<title>,<line>,<value>,<value label>. Parts packed into messages of
-- 255 bytes, i of n under one stamp: 1C|<at>|<i>/<n>|... (an answer to 1G: 1C|<at>|a|<i>/<n>|...); 1C|<at>|x withdraws
----------------------------------------------------------------------------
local LIMIT, PARTS_MAX = 255, 8
function H.Messages(set, answer)
  local parts = { "h=" .. table.concat({ set.kind or "n", clean(set.title, TITLE), clean(set.by, NAME), set.period or "", tostring(tonumber(set.ranked) or "") }, ",") }
  for _, c in ipairs(set.cards or {}) do
    parts[#parts + 1] = "c=" .. table.concat({ (c.sfx or sfxOf(c.guid) or ""):gsub("[^%w]", ""), clean(c.name, NAME), clean(c.class, 12), clean(c.race, 12), tostring(tonumber(c.sex) or ""),
      CODE[c.kind] or "O", tostring(tonumber(c.icon) or ""), clean(c.source, 24), clean(c.title, TITLE), clean(c.line, LINE), clean(bare(c.value), VALUE), clean(c.valueLabel, VLABEL) }, ",")
  end
  local head = "1C|" .. string.format("%.0f", set.at or 0) .. "|" .. (answer and "a|" or "")
  local bodies, cur = {}, nil
  for _, p in ipairs(parts) do
    if cur and #head + 4 + #cur + 1 + #p > LIMIT then bodies[#bodies + 1] = cur; cur = nil end
    cur = cur and (cur .. ";" .. p) or p
  end
  bodies[#bodies + 1] = cur
  local out = {}
  for i, b in ipairs(bodies) do out[i] = head .. i .. "/" .. #bodies .. "|" .. b end
  return out
end
local function fields(s) local out = {}; for f in ((s or "") .. ","):gmatch("([^,]*),") do out[#out + 1] = f end return out end
-- a set's parts read back; nil for one with no known kind or no card
function H.Parse(at, body)
  local set = { at = at, cards = {} }
  for part in (body or ""):gmatch("[^;]+") do
    local k, v = part:match("^(%a)=(.*)$")
    if k == "h" and not set.kind then
      local f = fields(v)
      set.kind = H.HEAD[f[1]] and f[1] or nil
      set.title, set.by = clean(f[2], TITLE), clean(f[3], NAME)
      set.period = PERIOD_WORD[f[4] or ""] and f[4] or nil
      set.ranked = tonumber(f[5] or "")
    elseif k == "c" and #set.cards < 5 then
      local f = fields(v)
      local kind = KIND_OF[f[6] or ""]
      if #f >= 12 and kind then
        local sex = tonumber(f[5])
        set.cards[#set.cards + 1] = { sfx = (f[1] or ""):match("^%w+$"), name = clean(f[2], NAME), class = (f[3] or ""):match("^%u+$"),
          race = (f[4] or ""):match("^%a+$"), sex = (sex == 2 or sex == 3) and sex or nil, kind = kind, icon = tonumber(f[7]),
          source = (f[8] or ""):match("^[%w%.%-_]+$") or "", title = clean(f[9], TITLE), line = clean(f[10], LINE), value = clean(f[11], VALUE),
          valueLabel = clean(f[12], VLABEL) }
      end
    end
  end
  if not set.kind or #set.cards == 0 then return nil end
  return set
end

-- the sets held, newest first (the last 30), and the newest one's stamp
function H.Sets() return H.DB().sets end
-- (a local set, rec, is none of the officers': 1G neither asks for it nor answers with it)
function H.Newest() for _, s in ipairs(H.Sets()) do if not s.rec then return tonumber(s.at) or 0 end end return 0 end
local function newestAny() local s = H.Sets()[1]; return s and tonumber(s.at) or 0 end
local function keep(set)
  local sets = H.Sets()
  local at = 1
  while sets[at] and (tonumber(sets[at].at) or 0) > set.at do at = at + 1 end
  table.insert(sets, at, set)
  while #sets > SETS do table.remove(sets) end
end
-- News (9.4): every set held, newest first, by its filter ("all", "halls", "records")
function H.News(filter)
  local out = {}
  for _, s in ipairs(H.Sets()) do
    if not filter or filter == "all" or (filter == "halls" and (s.kind == "h" or s.kind == "s")) or (filter == "records" and s.kind == "r") then out[#out + 1] = s end
  end
  return out
end
-- sets a sender published within the hour (H.senders, by GUID or sender string)
local function recent(list, within)
  local t, n = now(), 0
  for i = #list, 1, -1 do if t - list[i] >= within then table.remove(list, i) else n = n + 1 end end
  return n
end

----------------------------------------------------------------------------
-- publishing (9.2, 9.6)
----------------------------------------------------------------------------
-- this officer's sets in the last hour and the last set heard from any officer, kept across a /reload and a relog
-- (H.DB: the limits are the guild's, not a session's)
local function mine() local d = H.DB(); if type(d.mine) ~= "table" then d.mine = {} end return d.mine end
H.Mine = mine
local function lastSet() return tonumber(H.DB().lastSetAt) end
local function setHeard() H.DB().lastSetAt = now() end
-- may this officer publish now: true, or false and why (the button's grey words)
function H.PublishState(set)
  if not (C.Roster and C.Roster:InGuild()) then return false, "Not in a guild" end
  if not officer() then return false, "Officers only" end
  if not C.Policy:Settled() then return false, "Waiting for Guild Info" end
  if H.loginAt and gtime() - H.loginAt < LOGIN_WAIT and not H.answerHeard then return false, "Checking for news" end
  if lastSet() and now() - lastSet() < GAP then return false, "Wait a minute" end
  if recent(mine(), HOUR) >= PUBLISH_HOUR then return false, "10 sets this hour" end
  if set then
    if #(set.cards or {}) == 0 then return false, "No cards" end
    for _, c in ipairs(set.cards) do if not H.Open(c.source) then return false, "A card is Only you" end end
  end
  return true
end
-- may the guild chat line go: not while the game holds chat back (a blocked post fails silently, 8.4)
function H.ChatState()
  local CI = C_ChatInfo
  if type(CI) == "table" and type(CI.InChatMessagingLockdown) == "function" and C.Get(CI.InChatMessagingLockdown) == true then return false, "Outside the instance" end
  return true
end
-- the guild chat line for a set (9.2), 255 bytes at most: "Cute, a dot, Guild first: Brann earned ..." for one
-- achievement, else the title (a hall's after its kind) and each card's member and title
H.PREFIX = "Cute" .. DOT
local HALL_WORD = { h = "Hall of Fame", s = "Hall of Shame" }
function H.ChatLine(set)
  local title = (set.title and set.title ~= "") and set.title or H.HEAD[set.kind or "n"]
  -- (a hall says which: "Hall of Fame, Week of 19 Oct")
  if HALL_WORD[set.kind] and title ~= HALL_WORD[set.kind] then title = HALL_WORD[set.kind] .. ", " .. title end
  local head = H.PREFIX .. title .. ": "
  local cards = set.cards or {}
  local function fit(s) if #s <= LIMIT then return s end return s:sub(1, LIMIT) end
  -- (one card: an achievement earned, a boss's first kill, the cap reached)
  local one = #cards == 1 and (cards[1].source or ""):sub(1, 1)
  local VERB = { a = " earned ", b = " brought down ", c = " reached " }
  if one and VERB[one] and (cards[1].source or ""):match("^%a%d") then return fit(head .. (cards[1].name or "?") .. VERB[one] .. (cards[1].title or "") .. ".") end
  local s = head
  for i, c in ipairs(cards) do
    local part = (i > 1 and ", " or "") .. (c.name or "?") .. " (" .. (c.title or "") .. ")"
    local more = (i < #cards) and (" and " .. (#cards - i) .. " more") or ""
    if #s + #part + #more > LIMIT then return fit(s .. " and " .. (#cards - i + 1) .. " more") end
    s = s .. part
  end
  return fit(s)
end
-- a card as it goes: its text cut to the wire's sizes
local function sendable(c)
  local o = copy(c)
  o.sfx = o.sfx or sfxOf(o.guid)
  o.name, o.title, o.line = clean(o.name, NAME), clean(o.title, TITLE), clean(o.line, LINE)
  o.value, o.valueLabel = clean(bare(o.value), VALUE), clean(o.valueLabel, VLABEL)
  return o
end
-- Publish: the set on GUILD as 1C and on this officer's screen as everyone sees it; the guild line in the same click
-- where chatLine; the items it was made of leave the queue. True, or false and why
function H:Publish(set, chatLine)
  local ok, why = H.PublishState(set)
  if not ok then return false, why end
  local at = math.floor(now())
  if at <= H.Newest() then at = H.Newest() + 1 end
  local out = { at = at, kind = set.kind or "n", title = clean(set.title, TITLE), period = set.period, ranked = set.ranked, cards = {},
    by = C.Roster:MyDisplay(), byGuid = C.MyGUID(), got = now() }
  for i, c in ipairs(set.cards) do if i <= 5 then out.cards[i] = sendable(c) end end
  for _, m in ipairs(H.Messages(out, false)) do C.Comm.Queue({ msg = m }) end
  keep(out)
  setHeard()
  table.insert(mine(), now())
  H:Unqueue(set.from)
  -- (what is left in this officer's own queue with the same source and member greys as the others' do)
  self:Grey(out, out.by)
  if set.draftId then H:Unqueue({ set.draftId }) end
  H.draft = nil
  if chatLine and H.ChatState() then
    local CI = C_ChatInfo
    if type(CI) == "table" and type(CI.SendChatMessage) == "function" then
      -- (in this click's own call stack; Cute's line never counts as typed: Sample.lua's chat hook passes it by)
      H.lineFrom = { guid = C.MyGUID(), at = now() }
      C.Sample.quiet = true
      pcall(CI.SendChatMessage, H.ChatLine(out), "GUILD")
      C.Sample.quiet = nil
      H.posted = (H.posted or 0) + 1
    end
  end
  if C.CardFrame and C.CardFrame.Announce then C.CardFrame:Announce(out) end
  refresh()
  return true
end
-- Withdraw (officers, a published set in News): 1C with its stamp and x; gone from every client's News
function H:Withdraw(at)
  at = tonumber(at)
  if not (at and officer()) then return false end
  C.Comm.Queue({ msg = "1C|" .. string.format("%.0f", at) .. "|x" })
  H:Withdrawn(at)
  return true
end
function H:Withdrawn(at)
  local d = H.DB()
  local sets = d.sets
  for i = #sets, 1, -1 do if tonumber(sets[i].at) == at then table.remove(sets, i) end end
  d.gone[tostring(at)] = now()
  -- (the last 30 withdrawals kept, so an answer to 1G brings none back)
  local n, oldest, ok = 0, nil, nil
  for k, t in pairs(d.gone) do n = n + 1; if not oldest or t < oldest then oldest, ok = t, k end end
  if n > SETS and ok then d.gone[ok] = nil end
  for i = #H.toasts, 1, -1 do if H.toasts[i].at == at then table.remove(H.toasts, i) end end
  local CF = C.CardFrame
  if CF and CF.set and CF.set.at == at and CF.frame and CF.frame:IsShown() then CF.frame:Hide() end
  if H.toastNow and H.toastNow.at == at and H.toastFrame then H.toastFrame:Hide(); H.toastNow = nil end
  refresh()
end

----------------------------------------------------------------------------
-- receiving 1C and 1G (Comm.lua hands them over: GUILD only), and 1W (whispered only)
----------------------------------------------------------------------------
function H:Receive(kind, text, sender, whispered)
  if type(text) ~= "string" then return end
  if kind == "1C" and not whispered then return self:ReceiveSet(text, sender)
  elseif kind == "1G" and not whispered then return self:Asked(text, sender)
  elseif kind == "1W" and whispered then return self:ReceiveRun(text, sender) end
end
function H:ReceiveSet(text, sender)
  local at, rest = text:match("^1C|(%d+)|(.*)$")
  at = tonumber(at)
  if not at then return end
  -- (from an officer by the roster, not marked untrusted: a member's or an untrusted officer's set is nobody's)
  if not C.Roster:OfficerVoice(sender) then H.refused = (H.refused or 0) + 1; return end
  if rest == "x" then return self:Withdrawn(at) end
  local answer = rest:sub(1, 2) == "a|"
  if answer then rest = rest:sub(3) end
  local i, n, body = rest:match("^(%d+)/(%d+)|(.*)$")
  i, n = tonumber(i), tonumber(n)
  if not (i and n and i >= 1 and i <= n and n <= PARTS_MAX) then return end
  -- (parts gathered by sender and stamp; a set half heard two minutes ago is forgotten, and 64 wait at most)
  local t, count = gtime(), 0
  for k, p in pairs(H.parts) do if t - p.t > 120 then H.parts[k] = nil else count = count + 1 end end
  local key = sender .. "|" .. at
  local p = H.parts[key]
  if not p or p.n ~= n then
    if count >= 64 then return end
    p = { n = n, got = {}, k = 0, t = t }
    H.parts[key] = p
  end
  if not p.got[i] then p.got[i] = body; p.k = p.k + 1 end
  if p.k < n then return end
  H.parts[key] = nil
  -- (an answer heard, whatever it holds: another officer said it, H:Answer)
  if answer then H.answerHeard = true; H.heardAnswerAt = math.max(H.heardAnswerAt or 0, at) end
  local set = H.Parse(at, table.concat(p.got, ";"))
  if set then self:Took(set, sender, answer) end
end
-- a whole set heard: kept, its items greyed in this officer's queue, shown once
function H:Took(set, sender, answer)
  local d = H.DB()
  if d.gone[tostring(set.at)] then return end
  for _, s in ipairs(d.sets) do if tonumber(s.at) == set.at then return end end
  local R = C.Roster
  local g = R:GuidOf(sender)
  local m = g and R.byGuid[g]
  -- (a live set is named by its sender's roster entry; an answer was published by whom its header says)
  if not answer then set.by = (m and m.name and C.Short(m.name)) or R:Display(sender) end
  set.byGuid, set.got = (not answer) and g or nil, now()
  local kept = {}
  for _, c in ipairs(set.cards) do
    -- (a guild card, a guild achievement's: no member, the guild's own name; G is no GUID's last part, which is hex)
    if c.sfx == "G" then c.guild = true; c.name = C.Achievements and C.Achievements.GuildName() or c.name end
    c.guid = c.sfx and not c.guild and R:GuidBySuffix(c.sfx) or nil
    local rm = c.guid and R.byGuid[c.guid]
    if rm then c.name = (rm.name and C.Short(rm.name)) or c.name; c.class = rm.class or c.class end
    if H.Open(c.source) then kept[#kept + 1] = c end
  end
  if #kept == 0 then return end
  set.cards = kept
  set.answer = answer or nil
  keep(set)
  if officer() then self:Grey(set, set.by) end
  if not answer then
    setHeard()
    local who = g or sender
    H.senders[who] = H.senders[who] or {}
    local list = H.senders[who]
    list[#list + 1] = now()
    H.lineFrom = { guid = g, sender = sender, at = now() }
    -- (a toast, unless the sender is past 10 sets in the hour or this client wants News alone)
    if recent(list, HOUR) <= PUBLISH_HOUR and H.Prefs().toast ~= false then self:Toast(set) end
  end
  refresh()
end

-- a set this client made itself (Records.lua: a fastest clear that fell), key its instance's: kept in News and toasted
-- as a set is, once a day a key; a second one the same day takes the first one's News row, quietly (9.6). Its stamp
-- is a half second, so no officer's set (a whole second) is ever taken for it
function H:KeepLocal(set, key)
  local d = H.DB()
  if type(d.recDay) ~= "table" then d.recDay = {} end
  local day = today()
  local again = d.recDay[key] == day
  if again then
    for i = #d.sets, 1, -1 do local s = d.sets[i]; if s.rec and s.key == key and s.day == day then table.remove(d.sets, i) end end
  end
  set.at = math.floor(now()) + 0.5
  while true do
    local taken = false
    for _, s in ipairs(d.sets) do if tonumber(s.at) == set.at then taken = true end end
    if not taken then break end
    set.at = set.at + 1
  end
  set.rec, set.key, set.day, set.got = true, key, day, now()
  keep(set)
  d.recDay[key] = day
  if not again and H.Prefs().toast ~= false then self:Toast(set) end
  refresh()
  return set
end

-- 1G: the newest set this client holds, asked once a minute after its hello (not at a /reload: the saved sets are the
-- guild's as it was a moment ago). An officer holding newer sets answers (13.2)
function H:Ask()
  if H.asked or not (C.Roster and C.Roster:InGuild()) then return end
  H.asked = true
  C.Comm.Queue({ msg = "1G|" .. string.format("%.0f", H.Newest()) .. "|" .. string.format("%.0f", C.Records and C.Records.Stamp() or 0) })
end
-- the lowest GUID among this officer and the officers the roster lists online answers first
local function firstOfficer()
  local mine, before = C.MyGUID() or "", C.Comm.Before
  local thr = C.Policy:LineThreshold()
  for _, m in ipairs(C.Roster.members or {}) do
    if m.online and not m.self and m.rank <= thr and type(m.guid) == "string" and not C.Policy:Untrusted(m.guid) and before(m.guid, mine) then return false end
  end
  return true
end
-- (the records' stamp beside the sets': an officer whose list of the records on is newer answers with 1O too)
local function recStamp() return C.Records and C.Records.Stamp() or 0 end
function H:Asked(text, sender)
  local a, ra = text:match("^1G|(%d+)|(%d*)$")
  a, ra = tonumber(a or ""), tonumber(ra or "") or 0
  if not a or not officer() or (H.Newest() <= a and recStamp() <= ra) then return end
  local who = C.Roster:GuidOf(sender) or sender
  for k, t in pairs(H.answered) do if now() - t >= ANSWER_AGAIN then H.answered[k] = nil end end
  if H.answered[who] then return end
  H.waiting[who] = math.min(H.waiting[who] or a, a)
  H.waitingRec = math.min(H.waitingRec or ra, ra)
  if H.answering then return end
  H.answering = true
  local heard0, recHeard0 = H.heardAnswerAt or 0, C.Records and C.Records.heardAt or 0
  C_Timer.After(firstOfficer() and (1 + 0.4 * rnd()) or (4 + 4 * rnd()), C.Safe(function() H:Answer(heard0, recHeard0) end, "halls: answer"))
end
-- one answer covers every asker waiting: the sets newer than the oldest of theirs, the last five; 1O where this
-- officer's list of the records on is newer than the oldest asker's
function H:Answer(heard0, recHeard0)
  H.answering = false
  local waiting, recSince = H.waiting, H.waitingRec
  H.waiting, H.waitingRec = {}, nil
  if not officer() then return end
  local since
  for who, a in pairs(waiting) do since = since and math.min(since, a) or a; H.answered[who] = now() end
  if not since then return end
  -- (another officer's 1O since, as new as this one's list, said it)
  local Rc = C.Records
  if Rc and recSince and recStamp() > recSince and not ((Rc.heardAt or 0) > (recHeard0 or 0) and (Rc.heardAt or 0) >= recStamp()) then
    C.Comm.Queue({ msg = Rc.Message() })
    Rc.sent = (Rc.sent or 0) + 1
  end
  -- (another officer's answer since, as new as this one's newest, said it: the askers count as answered all the same)
  local heard = H.heardAnswerAt or 0
  if H.Newest() <= since or (heard > (heard0 or 0) and heard >= H.Newest()) then return end
  local list = {}
  for _, s in ipairs(H.Sets()) do if not s.rec and tonumber(s.at) > since and #list < ANSWER_SETS then list[#list + 1] = s end end
  for i = #list, 1, -1 do for _, m in ipairs(H.Messages(list[i], true)) do C.Comm.Queue({ msg = m }) end end
  H.answers = (H.answers or 0) + 1
end

----------------------------------------------------------------------------
-- 1W: a run's cards to the officers (9.3). 1W|<run>|k=<kind>;i=<instance or map>;s=<start>;d=<seconds>;b=<bosses>;
-- c=<suffix>.<CODE>.<value>,...;m=<suffix>.<suffix>... (the sender first). Sent by the run's guild member with the
-- smallest GUID among those with Runs on (the hellos held), for guild members' cards alone, as the policy shows them
-- now; held in CuteDB.chars[me].pendingW while inside an instance or the chat lockdown holds addon chat back
----------------------------------------------------------------------------
local PENDING_W = 4
function H:RunEnded(run, rep)
  if type(run) ~= "table" or type(rep) ~= "table" or rep.test or not (C.Roster and C.Roster:InGuild()) then return end
  local R, before = C.Roster, C.Comm.Before
  local me = C.MyGUID()
  local mine = sfxOf(me)
  if not (me and mine and R.byGuid) or C.Policy:Untrusted(me) then return end
  -- (who is in the guild: the roster as this client last read it, which keeps its list through an instance)
  local guild, smallest = { [mine] = me }, me
  for s, m in pairs(run.members or {}) do
    if type(m) == "table" and type(m.g) == "string" and m.g ~= me and R.byGuid[m.g] then
      guild[s] = m.g
      if m.hello and not C.Policy:Untrusted(m.g) and before(m.g, smallest) then smallest = m.g end
    end
  end
  if smallest ~= me then return end
  local vis = C.Runs and C.Runs.Visible and C.Runs.Visible(rep) or rep
  local cards = {}
  for _, c in ipairs(vis.cards or {}) do
    if guild[c[1]] and type(c[2]) == "string" then cards[#cards + 1] = c[1] .. "." .. c[2] .. "." .. b36(math.floor(tonumber(c[3]) or 0)) end
  end
  if #cards == 0 then return end
  local others = {}
  for s in pairs(guild) do if s ~= mine then others[#others + 1] = s end end
  table.sort(others)
  local msg = "1W|" .. tostring(rep.id) .. "|" .. table.concat({ "k=" .. tostring(rep.kind), "i=" .. b36(rep.inst or rep.map or 0), "s=" .. b36(rep.start or 0),
    "d=" .. b36(rep.dur or 0), "b=" .. b36(rep.bosses or 0), "c=" .. table.concat(cards, ",") }, ";") .. ";m=" .. mine
  for _, s in ipairs(others) do if #msg + 1 + #s > LIMIT then break end msg = msg .. "." .. s end
  if #msg > LIMIT then return end
  local ch = C.Char()
  if type(ch.pendingW) ~= "table" then ch.pendingW = {} end
  while #ch.pendingW >= PENDING_W do table.remove(ch.pendingW, 1) end
  ch.pendingW[#ch.pendingW + 1] = { msg = msg, at = now() }
  self:FlushRuns()
end
-- the held ones go once out of the instance and the lockdown, whispered to each officer online (and into this
-- client's own queue where it is an officer); with no officer online, nobody to tell
local function inside()
  local _, kind = call("IsInInstance")
  return kind == "party" or kind == "raid"
end
function H:FlushRuns()
  local ch = C.Char()
  local list = ch.pendingW
  if type(list) ~= "table" or #list == 0 then return end
  if inside() or C.Comm:Locked() then
    if not H.flushDue then
      H.flushDue = true
      C_Timer.After(10, C.Safe(function() H.flushDue = false; H:FlushRuns() end, "halls: run cards"))
    end
    return
  end
  ch.pendingW = nil
  local targets = C.Roster:OfficerTargets()
  for _, e in ipairs(list) do
    if type(e) == "table" and type(e.msg) == "string" then
      for _, t in ipairs(targets) do C.Comm.Queue({ msg = e.msg, target = t }) end
      if officer() then self:TakeRun(e.msg, nil, C.MyGUID()) end
      H.wSent = (H.wSent or 0) + 1
    end
  end
end
-- an officer's client takes a 1W from a guild member among the run's members, 4 a sender an hour, one per run (the
-- same place, a member in common and a start within 10 minutes: clients that heard no hellos inside may each send)
function H:ReceiveRun(text, sender)
  if not C.Roster:OfficerStill() then return end
  local g = C.Roster:GuidOf(sender)
  if not g or C.Policy:Untrusted(g) then H.refused = (H.refused or 0) + 1; return end
  return self:TakeRun(text, sender, g)
end
H.runsFrom = {}
function H:TakeRun(text, sender, g)
  local id, body = text:match("^1W|([%w%-]+)|(.*)$")
  if not id then return end
  local kv = {}
  for k, v in body:gmatch("(%a)=([^;]*)") do kv[k] = v end
  local members = {}
  for s in (kv.m or ""):gmatch("%w+") do members[s] = true end
  if not members[sfxOf(g)] then H.refused = (H.refused or 0) + 1; return end
  local kind, inst, start, dur = kv.k, unb36(kv.i or ""), unb36(kv.s or ""), unb36(kv.d or "")
  if not ((kind == "d" or kind == "r" or kind == "g") and inst and start and dur and dur >= 0 and dur < 86400) then return end
  if sender then
    H.runsFrom[g] = H.runsFrom[g] or {}
    if recent(H.runsFrom[g], HOUR) >= W_HOUR then H.refused = (H.refused or 0) + 1; return end
    table.insert(H.runsFrom[g], now())
  end
  for _, r in ipairs(H.runsHeard) do
    if r.inst == inst and math.abs(r.start - start) <= W_SAME then
      for s in pairs(members) do if r.members[s] then return end end
    end
  end
  H.runsHeard[#H.runsHeard + 1] = { inst = inst, start = start, members = members }
  while #H.runsHeard > 50 do table.remove(H.runsHeard, 1) end
  -- (the place named here: the instance's name, or the map's for a group run)
  local place
  if kind == "g" then
    local info = C.Get(C.Api("C_Map", "GetMapInfo"), inst)
    place = type(info) == "table" and C.Plain(info.name) or nil
  else place = call("GetRealZoneText", inst) end
  if type(place) ~= "string" or place == "" then place = (C.Stats.LabelOf and C.Stats.LabelOf("i" .. inst)) or (kind == "g" and "A long group" or "A run") end
  local A, R = C.Awards, C.Roster
  local n = 0
  for s, code, v in (kv.c or ""):gmatch("(%w+)%.(%u%u)%.(%w+)") do
    local cg = members[s] and R:GuidBySuffix(s) or nil
    local rm = cg and R.byGuid[cg]
    local a = A and A.Of(code)
    v = unb36(v)
    if rm and a and v and A.ValueOK(code, v, dur) and n < 5 then
      n = n + 1
      local shown, what = A.Show(code, v)
      local source = "r" .. id .. "." .. code
      self:Queue({ id = source, src = "run", from = sender or "me", place = place, what = a.title .. DOT .. place, digest = a.kind ~= "star" and "run" or nil,
        lock = not H.Open(source) or nil,
        card = { guid = cg, sfx = s, name = rm.name and C.Short(rm.name) or "?", class = rm.class, kind = a.kind, title = a.title, line = a.quip,
          value = bare(shown), valueLabel = what, source = source } })
    end
  end
end

----------------------------------------------------------------------------
-- halls (9.5): a set from stats. def = { kind = "fame" or "shame", period = "a", "w" or "l", stats = { id or false,
-- ... five }, titles, lines, title }. The leaders from the officer's roster: members with Cute, not untrusted, a value
-- the policy routes Everyone within its bounds; the highest first (the lowest for a stat whose record is the least),
-- ties to the smaller GUID; no member holds two cards, a stat whose leader has one goes to its next
----------------------------------------------------------------------------
H.FAME_LINES = { "The guild salutes you.", "Somebody had to set the bar. You did.", "Raise a mug: this one is yours.",
  "The rest of us are taking notes.", "Steady, stubborn and simply the best." }
H.SHAME_LINES = { "We will never let this go.", "Framed, signed and hung in the guild hall.", "Legends are made. So are mistakes.",
  "We checked twice. It really was you.", "Your secret is safe with the whole guild." }
-- may a stat make a hall card for this period: an int routed Everyone; a week's only for This week and Last week
function H.Statable(id, period)
  local def = C.Stats.byId[id]
  if not def or def.kind ~= "int" or def.hidden or def.runField or def.fixed then return false end
  if C.Policy:Route(id) ~= "all" then return false end
  if period == "w" or period == "l" then return C.Sample.WEEKLY[id] == true end
  return true
end
function H.ValueOf(row, id, period)
  if period == "w" then return H.ThisWeek(row.guid, id) end
  if period == "l" then return H.LastWeek(row.guid, id) end
  return row.stats and row.stats[id]
end
function H.HallTitle(period)
  if period == "w" then return H.WeekTitle() end
  if period == "l" then local n = H.WeekNow(); return n and H.WeekTitle(n - 1) or "Last week" end
  return "All time"
end
-- a new hall's stats: a Shame hall the live Hall of Shame's ticked ones in their order; a Fame hall the runs' and the
-- guild's counts; each only where the period allows it
local FAME = { a = { "honors", "runs", "quests_done", "bosses", "dungeons" }, w = { "honors_week", "runs_week", "quests_week", "weekly_raids", "logins" } }
FAME.l = FAME.w
function H.HallStats(kind, period)
  local out = {}
  local function add(id) if #out < 5 and H.Statable(id, period) then out[#out + 1] = id end end
  if kind == "shame" then
    local ticked = C.UI and C.UI.Ticked and C.UI.Ticked("shame") or {}
    for _, def in ipairs(C.Stats.byCat.funny) do if ticked[def.id] then add(def.id) end end
  else
    for _, id in ipairs(FAME[period] or FAME.a) do add(id) end
  end
  return out
end
function H:ComputeHall(def)
  local period = def.period or "a"
  local list, ranked = {}, 0
  for _, row in ipairs(C.Roster:Rows()) do
    if row.addon and not row.untrusted and type(row.guid) == "string" then ranked = ranked + 1; list[#list + 1] = row end
  end
  local cards, used = {}, {}
  local lines = def.kind == "shame" and H.SHAME_LINES or H.FAME_LINES
  for i = 1, 5 do
    local id = def.stats and def.stats[i]
    if id and H.Statable(id, period) then
      local sdef = C.Stats.byId[id]
      local low = sdef.record == "min"
      local cands = {}
      for _, row in ipairs(list) do
        local v = H.ValueOf(row, id, period)
        if type(v) == "number" and (low or v > 0) and not used[row.guid] and not C.Stats.Implausible(id, v) then cands[#cands + 1] = { row = row, v = v } end
      end
      table.sort(cands, function(a, b)
        if a.v ~= b.v then if low then return a.v < b.v end return a.v > b.v end
        return C.Comm.Before(a.row.guid, b.row.guid)
      end)
      local top = cands[1]
      if top then
        used[top.row.guid] = true
        local kind = def.kind == "shame" and "blooper" or (#cards == 0 and "star" or "shout")
        local title = def.titles and def.titles[i]
        local line = def.lines and def.lines[i]
        cards[#cards + 1] = { guid = top.row.guid, sfx = sfxOf(top.row.guid), name = top.row.short, class = top.row.class, kind = kind,
          title = (title and title ~= "") and title or sdef.label, line = (line and line ~= "") and line or lines[#cards + 1],
          value = C.UI.Format(sdef, top.v), valueLabel = PERIOD_WORD[period], source = "s" .. id, stat = id }
      end
    end
  end
  return { kind = def.kind == "shame" and "s" or "h", title = (def.title and def.title ~= "") and def.title or H.HallTitle(period), period = period,
    ranked = ranked, cards = cards, hall = def }
end
-- Update (officers, a published hall): its leaders again for the same stats, under a new stamp; a week's hall takes
-- the week's title now, so a weekly hall is one click a week
function H:Update(set)
  if not (type(set) == "table" and (set.kind == "h" or set.kind == "s")) then return false end
  local stats, titles, lines = {}, {}, {}
  for i, c in ipairs(set.cards or {}) do stats[i] = (c.source or ""):match("^s(.+)$") or false; titles[i] = c.title; lines[i] = c.line end
  local period = set.period or "a"
  local fresh = self:ComputeHall({ kind = set.kind == "s" and "shame" or "fame", period = period, stats = stats, titles = titles, lines = lines,
    title = (period == "a") and set.title or H.HallTitle(period) })
  return self:Publish(fresh, false)
end

-- the stat picker (9.5): one menu for New hall (and Records' Add, R4), the game's MenuUtil.CreateContextMenu, a
-- submenu per category listing only the stats routed Everyone the period allows; the game's statistics by the client's
-- own categories. onPick(id) (nil for None)
local GROUPS = { { "leveling", "Leveling" }, { "prog", "Progress" }, { "funny", "Hall of Shame" }, { "runs", "Runs" } }
function H.PickStat(period, onPick, owner, allow)
  local M = MenuUtil
  if not (type(M) == "table" and type(M.CreateContextMenu) == "function") then return false end
  allow = allow or function(id) return H.Statable(id, period) end
  M.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Choose a statistic")
    root:CreateButton("None", function() onPick(nil) end)
    local S = C.Stats
    for _, g in ipairs(GROUPS) do
      local list = {}
      for _, def in ipairs(S.byCat[g[1]] or {}) do if allow(def.id) then list[#list + 1] = def end end
      if #list > 0 then
        local sub = root:CreateButton(g[2])
        if #list > 20 and sub.SetScrollMode then sub:SetScrollMode(20 * 20) end
        for _, def in ipairs(list) do sub:CreateButton(def.label, function() onPick(def.id) end) end
      end
    end
    local cats = {}
    for _, cat in ipairs(S.game and S.game.cats or {}) do
      local list = {}
      for _, def in ipairs(cat.stats or {}) do if allow(def.id) then list[#list + 1] = def end end
      if #list > 0 then cats[#cats + 1] = { cat = cat, list = list } end
    end
    if #cats > 0 then
      local game = root:CreateButton("Game statistics")
      for _, e in ipairs(cats) do
        local sub = game:CreateButton(e.cat.name)
        if #e.list > 20 and sub.SetScrollMode then sub:SetScrollMode(20 * 20) end
        for _, def in ipairs(e.list) do sub:CreateButton(def.label, function() onPick(def.id) end) end
      end
    end
  end)
  return true
end

----------------------------------------------------------------------------
-- showing (9.6): a set first as a toast, one row 420 x 48 at the top centre, 100 below the screen's top: the label in
-- its colour, the title, up to three names in class colour; a click opens the set; it goes after 10 s unless the
-- mouse is on it. One at a time, three waiting, two an hour, the rest to News quietly; never in combat, an encounter,
-- a loading screen or a dungeon or raid: waiting ones show after PLAYER_REGEN_ENABLED and out of the instance
----------------------------------------------------------------------------
H.toastLog = {}
local FLAT = "Interface\\Buttons\\WHITE8x8"
local BD = BackdropTemplateMixin and "BackdropTemplate" or nil
local function quietNow()
  if call("InCombatLockdown") == true then return false, "combat" end
  local IE = C_InstanceEncounter
  if type(IE) == "table" and type(IE.IsEncounterInProgress) == "function" and C.Get(IE.IsEncounterInProgress) == true then return false, "encounter" end
  if H.loadingUntil and gtime() < H.loadingUntil then return false, "loading" end
  if inside() then return false, "instance" end
  return true
end
H.Quiet = quietNow
function H:Toast(set)
  if #H.toasts >= TOAST_WAIT then return false end
  H.toasts[#H.toasts + 1] = set
  self:NextToast()
  return true
end
local function names(set, max)
  local out, U = {}, C.UI
  for i, c in ipairs(set.cards or {}) do
    if i > max then break end
    out[#out + 1] = "|cff" .. U.Hex(U.ClassColor(c.class)):sub(5) .. (c.name or "?") .. "|r"
  end
  local more = #(set.cards or {}) - max
  return table.concat(out, ", ") .. (more > 0 and (" and " .. more .. " more") or "")
end
local function toastFrame()
  if H.toastFrame then return H.toastFrame end
  local U = C.UI
  local f = CreateFrame("Button", nil, UIParent, BD)
  f:SetSize(420, 48)
  f:SetPoint("TOP", UIParent, "TOP", 0, -100)
  f:SetFrameStrata("DIALOG")
  U.Skin(f, { 0.035, 0.035, 0.035 }, 0.97)
  f.bar = U.Flat(f, "ARTWORK", WHITE, 1)
  f.bar:SetPoint("TOPLEFT", 1, -1)
  f.bar:SetPoint("BOTTOMLEFT", 1, 1)
  f.bar:SetWidth(2)
  f.label = U.Text(f, 11, WHITE, "LEFT", 140)
  f.label:SetPoint("TOPLEFT", 12, -8)
  f.title = U.Text(f, 13, WHITE, "LEFT", 250)
  f.title:SetPoint("TOPLEFT", 156, -7)
  f.names = U.Text(f, 12, INK, "LEFT", 396)
  f.names:SetPoint("TOPLEFT", 12, -27)
  f:SetHighlightTexture(FLAT, "ADD")
  f:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)
  f:SetScript("OnClick", C.Safe(function(self)
    local set = H.toastNow
    self:Hide()
    H.toastNow = nil
    if set and C.CardFrame then C.CardFrame:Announce(set, { test = set.test }) end
    H:NextToast()
  end, "halls: toast"))
  f:Hide()
  H.toastFrame = f
  return f
end
function H:NextToast()
  if H.toastNow then return end
  local set = H.toasts[1]
  if not set then return end
  if not quietNow() then return end
  -- (two an hour: the rest stay in News)
  if recent(H.toastLog, HOUR) >= TOAST_HOUR then H.toasts = {}; return end
  table.remove(H.toasts, 1)
  self:ShowToast(set)
end
function H:ShowToast(set, test)
  local f = toastFrame()
  local U = C.UI
  H.toastNow = set
  if not test then H.toastLog[#H.toastLog + 1] = now() end
  H.toastsShown = (H.toastsShown or 0) + 1
  local kc = H.HeadColor(set.kind)
  f.bar:SetColorTexture(kc[1], kc[2], kc[3], 1)
  color(f.label, kc)
  U.FitText(f.label, H.HEAD[set.kind] or H.HEAD.n, 136)
  -- (the title right after the label, on its baseline)
  local lw = math.ceil(((f.label.GetUnboundedStringWidth or f.label.GetStringWidth)(f.label)) or 0)
  f.title:ClearAllPoints()
  f.title:SetPoint("TOPLEFT", 12 + lw + 10, -6)
  f.title:SetWidth(396 - lw - 10)
  U.FitText(f.title, set.title or "", 392 - lw - 10)
  U.FitText(f.names, names(set, 3), 392)
  f:SetAlpha(1)
  f:Show()
  local shown = set
  local function fade()
    if H.toastNow ~= shown or not f:IsShown() then return end
    if f:IsMouseOver() then C_Timer.After(1, C.Safe(fade, "halls: toast")) return end
    f:Hide()
    H.toastNow = nil
    C_Timer.After(0.5, C.Safe(function() H:NextToast() end, "halls: toast"))
  end
  C_Timer.After(TOAST_SHOW, C.Safe(fade, "halls: toast"))
end

-- Cute's own guild line (9.6): a client with Cute hides a plain line beginning "Cute, a dot" from an officer (by the
-- GUID the line carries, else its sender, as R:OfficerVoice judges one: not you, not marked untrusted), and your own
-- for a minute after you published, so a member sees a set once. Not only from the officer whose set came in the last
-- minute, as the design first had it: the line goes in the publish click, ahead of the set's addon messages, which the
-- guild channel's queue sends a second or more later, so the line comes first and a client cannot wait for the set;
-- every client with Cute gets that officer's set. A secret line is never handed to a filter (ChatFrameFilters.lua
-- ApplyFilter's canaccessvalue) and is left alone here too
function H.LineFilter(_, _, text, author, ...)
  if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return false end
  if text:sub(1, #H.PREFIX) ~= H.PREFIX then return false end
  local guid = select(10, ...)
  if issecretvalue and (issecretvalue(guid) or issecretvalue(author)) then return false end
  local R = C.Roster
  local m = type(guid) == "string" and R.byGuid and R.byGuid[guid] or nil
  local voice = m ~= nil and not m.self and type(m.rank) == "number" and m.rank <= C.Policy:LineThreshold() and not C.Policy:Untrusted(guid)
  if not voice and not m and type(author) == "string" then voice = R:OfficerVoice(author) end
  local lf = H.lineFrom
  local mine = lf ~= nil and now() - lf.at <= 60 and ((lf.guid ~= nil and guid == lf.guid) or (lf.sender ~= nil and author == lf.sender))
  if voice or mine then H.hidden = (H.hidden or 0) + 1; return true end
  return false
end

-- a card's tooltip: who, its rule or source in one line
function H.CardTip(tip, set, c)
  tip:AddLine((c.title or "") .. ": " .. (c.name or "?"), 1, 1, 1)
  local src = c.source or ""
  local code = src:match("^r.-%.(%u%u)$")
  local stat = src:match("^s(.+)$")
  local sdef = stat and C.Stats.byId[stat]
  local line
  if code and C.CardFrame and C.CardFrame.RULE and C.CardFrame.RULE[code] then line = C.CardFrame.RULE[code] .. ", in a run."
  elseif sdef then line = "The guild's best at " .. sdef.label .. " (" .. (PERIOD_WORD[set.period or "a"] or "all time") .. ")."
  elseif src:match("^a%d") then line = c.kind == "first" and "A guild first, as the officers judged it." or (c.guild and "An achievement the guild earned." or "An achievement a guild member earned.")
  elseif src:match("^b%d") then line = "A guild first: the first kill two members' Cute agreed on."
  elseif src:match("^c%d") then line = "A guild first: the first member at the level cap."
  elseif src == "" then line = "Written by the officers." end
  if line then tip:AddLine(line, 0.85, 0.85, 0.85, true) end
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
-- the test announcement (9.7): the toast, then a set of three cards: you with your newest earned Legacy Challenge (a
-- made-up line where you have none), a made-up member under GUILD FIRST and a NEW RECORD card for a made-up clear.
-- hall: a Hall of Shame from the live cards. Nothing sent or kept
function H.TestSet(hall)
  if hall then
    local set = H:ComputeHall({ kind = "shame", period = "a", stats = H.HallStats("shame", "a"), title = "Hall of Shame" })
    set.test = true
    return set
  end
  local me = C.Roster:MyDisplay()
  local _, class = call("UnitClass", "player")
  local _, race = call("UnitRace", "player")
  local sex = call("UnitSex", "player")
  local you = { guid = C.MyGUID(), name = me, class = class, race = race, sex = sex, kind = "ach", title = "Legacy Challenge",
    line = "Your newest challenge shows here once you earn one.", value = "Earned " .. (date and (date("%d %b"):gsub("^0", "")) or ""), valueLabel = "Legacy Challenges" }
  -- (the newest by GetLatestCompletedAchievements where the client has it; else the name Sample keeps of it)
  local lc = C.Sample:Value("lc_last")
  if type(lc) == "string" and lc ~= "" then you.title = lc end
  local latest = callable("GetLatestCompletedAchievements") and C.Get(GetLatestCompletedAchievements) or nil
  if type(latest) == "number" then
    local _, name, _, _, month, day, _, desc, _, icon = C.Get(GetAchievementInfo, latest)
    if type(name) == "string" and name ~= "" then
      you.title, you.icon = name, tonumber(icon)
      if type(desc) == "string" and desc ~= "" then you.line = desc end
      -- (the month as the achievement window gives it, 1 to 12: FormatShortDate's day, month, year)
      local mon = type(month) == "number" and MONTHS[month] or nil
      if mon and type(day) == "number" then you.value = "Earned " .. day .. " " .. mon end
    end
  end
  local set = { kind = "n", title = "Test announcement", by = me, test = true, cards = { you,
    { name = "Kettlewick", class = "MAGE", race = "Gnome", sex = 3, kind = "first", title = "First in the guild", line = "Reached the level cap before anyone else.",
      value = "Level 60", valueLabel = "the level cap" },
    { name = "Mossbottom", class = "WARRIOR", race = "Dwarf", sex = 2, kind = "record", title = "Fastest clear", line = "With 4 guild mates.",
      value = "18:42", valueLabel = "a made-up clear" } } }
  return set
end
function H.Test(hall)
  local set = H.TestSet(hall)
  if not hall then H:ShowToast(set, true) end
  if C.CardFrame then C.CardFrame:Announce(set, { test = true }) end
  return set
end

----------------------------------------------------------------------------
-- the Halls tab (9.4): the core's shame page, retitled (its id kept: saved settings and /cute shame still find it).
-- Chips in the band: Hall of Shame (0.7's live cards, drawn as they were), News, and Queue for the officers; a module
-- may add one (H.AddChip: Records, R4). The tab opens on News where a set came since you last looked, else on the Hall
-- of Shame, so a member who upgrades finds the cards they had
----------------------------------------------------------------------------
H.chips = {
  { id = "shame", title = "Hall of Shame", order = 10, tip = "The guild's live cards: who leads each funny statistic now." },
  { id = "news", title = "News", order = 20, tip = "Every set the officers published, newest first." },
  { id = "queue", title = "Queue", order = 90, officer = true, tip = "What you may publish: run cards, halls and cards you write. Only you see your queue." },
}
-- the Halls tab at a chip
function H.OpenChip(chip) H.want = chip; C.UI:Open("shame") end
function H.AddChip(def)
  if type(def) ~= "table" or type(def.id) ~= "string" or type(def.draw) ~= "function" then return false end
  for _, c in ipairs(H.chips) do if c.id == def.id then return false end end
  H.chips[#H.chips + 1] = def
  table.sort(H.chips, function(a, b) return (a.order or 50) < (b.order or 50) end)
  return true
end
-- (a chip's when: shown only while it says so, a module's chip while the module is on)
local function chipsFor(isOfficer)
  local out = {}
  for _, c in ipairs(H.chips) do if (not c.officer or isOfficer) and (not c.when or c.when()) then out[#out + 1] = c end end
  return out
end
-- sets come since the News chip was last open
function H.Unseen()
  local seen, n = tonumber(H.DB().seenAt) or 0, 0
  for _, s in ipairs(H.Sets()) do if (tonumber(s.at) or 0) > seen then n = n + 1 end end
  return n
end
local NEWS_FILTERS = { { "all", "All" }, { "halls", "Halls" }, { "records", "Records" } }
local function measure(fs, s) fs:SetText(s); local w = (fs.GetUnboundedStringWidth or fs.GetStringWidth)(fs); return math.ceil(w or 0) end
-- a chip: a band line, white with its bar where it is open
-- (at x, or ending at x where right)
local function chipLine(ui, x, title, open, fn, tip, dim, right)
  local U, ROW = C.UI, C.UI.ROW
  local l = ui.bandLines:Get()
  local tw = measure(l.name, title)
  local w = tw + 20
  l:ClearAllPoints()
  l:SetPoint("TOPLEFT", right and (x - w) or x, -4)
  l:SetSize(w, ROW)
  l.bg:SetColorTexture(1, 1, 1, open and 0.06 or 0)
  l.bar:SetShown(open)
  l.bar:SetColorTexture(WHITE[1], WHITE[2], WHITE[3], 1)
  l.val:Hide(); l.who:Hide()
  l.name:ClearAllPoints(); l.name:SetPoint("LEFT", 10, 0); l.name:SetJustifyH("LEFT")
  l.name:SetWidth(tw + 4)
  color(l.name, open and WHITE or (dim or INK))
  l.name:SetText(title)
  l.name:Show()
  l.fn, l.tip = fn, tip
  return w
end
local function bandButton(ui, x, w, label, on, fn, tip)
  local b = ui.bandButtons:Get()
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", x, -4)
  b:SetWidth(w)
  b:SetLabel(label)
  b:SetOn(on and true or false)
  b:SetScript("OnClick", function() if on then fn() end end)
  if tip then
    b:SetScript("OnEnter", C.Safe(function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); tip(GameTooltip); GameTooltip:Show() end, "halls: tooltip"))
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  else b:SetScript("OnEnter", nil); b:SetScript("OnLeave", nil) end
  return b
end
H.BandButton = bandButton
function H.Draw(ui)
  local isOfficer = C.Roster:MeOfficer()
  local list = chipsFor(isOfficer)
  local valid = {}
  for _, c in ipairs(list) do valid[c.id] = c end
  -- (a chip asked for, H.OpenChip; else, another page drew last: the tab was opened again, so it opens where it should)
  if H.want then H.chip, H.want = H.want, nil
  elseif H.drawnAt ~= (ui.draws or 0) - 1 then H.chip = nil end
  H.drawnAt = ui.draws
  local chip = H.chip
  if not (chip and valid[chip]) then chip = H.Unseen() > 0 and "news" or "shame" end
  H.chip = chip
  ui.header:Hide()
  local w = ui.scroll:Width()
  local x = 0
  -- (News open: what came is seen now, its count gone from the chip as it opens)
  if chip == "news" then H.DB().seenAt = newestAny() end
  local unseen = H.Unseen()
  for _, c in ipairs(list) do
    local title = c.title
    if c.id == "news" and unseen > 0 then title = title .. " (" .. unseen .. ")" end
    x = x + chipLine(ui, x, title, c.id == chip, function() H.chip = c.id; C.UI:Draw() end, function(tip)
      tip:AddLine(c.title, 1, 1, 1)
      if c.tip then tip:AddLine(c.tip, 0.85, 0.85, 0.85, true) end
    end) + 4
  end
  -- (the chip's own controls on the right)
  if chip == "news" then
    local fx = w
    for i = #NEWS_FILTERS, 1, -1 do
      local f = NEWS_FILTERS[i]
      fx = fx - chipLine(ui, fx, f[2], (H.filter or "all") == f[1], function() H.filter = f[1]; C.UI:Draw() end, nil, DIM, true) - 4
    end
  elseif chip == "queue" and not H.draft then
    local n = #H.Ticked()
    local function newCard()
      H.draft = { mode = "card", kind = "n", title = "Guild news", cards = { { kind = "shout", title = "", line = "" } }, chat = H.Prefs().chat ~= false }
      C.UI:Draw()
    end
    local function compose()
      local d = H:Compose(H.Ticked())
      d.mode = "set"
      H.draft = d
      C.UI:Draw()
    end
    local why = n == 0 and "Tick one to five items first." or (n > 5 and "Five cards at most: untick some." or "Makes a set of the items ticked.")
    local bx = w - 90
    bandButton(ui, bx, 90, "New card", true, newCard)
    bx = bx - 94; bandButton(ui, bx, 90, "New hall", true, function() H.NewHall("shame", "a"); C.UI:Draw() end)
    bx = bx - 94; bandButton(ui, bx, 90, "Compose", n >= 1 and n <= 5, compose, function(tip) tip:AddLine("Compose", 1, 1, 1); tip:AddLine(why, 0.85, 0.85, 0.85, true) end)
  elseif valid[chip].band then
    -- (a module's chip draws its own controls on the right: Records' Add)
    valid[chip].band(ui, w)
  end
  ui:SetBand(28)
  if chip == "shame" then if ui.DrawShame then ui:DrawShame() end
  elseif chip == "news" then H.DrawNews(ui)
  elseif chip == "queue" then if H.draft then H.DrawCompose(ui) else H.DrawQueue(ui) end
  else valid[chip].draw(ui) end
end

-- a row of the windows design's pattern A (20 units): the 2 px bar, an icon, a name, what, and a word on the right
local function makeRow(parent)
  local U = C.UI
  local r = U:MakeLine(parent)
  r.box = CreateFrame("Frame", nil, r, BD)
  r.box:SetSize(14, 14)
  U.Skin(r.box, { 0.11, 0.11, 0.11 })
  if r.box.SetBackdropBorderColor then r.box:SetBackdropBorderColor(0.42, 0.42, 0.42, 1) end
  r.fill = U.Flat(r.box, "ARTWORK", WHITE, 1)
  r.fill:SetPoint("TOPLEFT", 3, -3)
  r.fill:SetPoint("BOTTOMRIGHT", -3, 3)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.what = U.Text(r, 12, INK, "LEFT", 200)
  r.kind = U.Text(r, 11, DIM, "LEFT", 104)
  r.kind:Hide()
  r.lock = r:CreateTexture(nil, "ARTWORK")
  r.lock:SetSize(12, 12)
  return r
end
local LOCK, TROPHY, GENERAL = 130944, 311945, 236544 -- UI-ChatFrame-LockIcon, INV_Misc_Trophy_Argent, Achievement_General
local function setIcon(t, it)
  t:SetTexCoord(0, 1, 0, 1)
  local c = it.card
  if it.src == "run" then t:SetAtlas("Dungeon")
  elseif it.src == "record" then t:SetTexture(TROPHY)
  elseif c and tonumber(c.icon) then t:SetTexture(tonumber(c.icon))
  else t:SetTexture(GENERAL) end
end
local function say(ui, x, y, w, s, c)
  local l = ui.labels:Get()
  l:ClearAllPoints()
  l:SetPoint("TOPLEFT", x, -y)
  l:SetWidth(w)
  l:SetJustifyH("LEFT")
  color(l, c or MUTE)
  C.UI.FitText(l, s, w - 4)
  return l
end
H.Say = say
local function scrollButton(ui, x, y, w, label, fn)
  local b = ui.buttons:Get()
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", x, -y)
  b:SetWidth(w)
  b:SetLabel(label)
  b:SetOn(true)
  b:SetScript("OnClick", fn)
  b:SetScript("OnEnter", nil); b:SetScript("OnLeave", nil)
  return b
end
local function dayOf(t) return (date and t) and (date("%d %b", t):gsub("^0", "")) or "" end

-- News: every set held, newest first, by the filter; a click opens it, an officer's right-click offers Update (a
-- hall) and Withdraw. With nothing published, a line saying so and the test announcement
function H.DrawNews(ui)
  local U, ROW = C.UI, C.UI.ROW
  local sf = ui.scroll
  local w = sf:Width()
  ui.rows:Clear()
  local list = H.News(H.filter or "all")
  local y = 4
  if #list == 0 then
    say(ui, 6, y + 2, w - 180, (H.filter or "all") == "all" and "Nothing published yet." or "Nothing of these yet.")
    scrollButton(ui, w - 170, y, 170, "Test announcement", function() H.Test(false) end)
    y = y + 26
    if C.Roster:MeOfficer() and #H.Sets() == 0 then
      say(ui, 6, y + 2, w - 180, "Publish the first set from Queue.")
      scrollButton(ui, w - 170, y, 170, "Open Queue", function() H.OpenChip("queue") end)
      y = y + 26
    end
    sf:SetContentHeight(y + 8)
    return
  end
  local rows = ui:List("halls.news", makeRow)
  local DAY = 70
  rows:Set(#list, 0, ROW, function(r, i, ly)
    local set = list[i]
    r:SetHeight(ROW)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, -ly)
    r:SetWidth(w)
    r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
    local kc = set.kind == "n" and C.Cards.EDGE or H.HeadColor(set.kind)
    r.bar:Show(); r.bar:SetColorTexture(kc[1], kc[2], kc[3], 1)
    r.box:Hide(); r.icon:Hide(); r.lock:Hide()
    -- (the label in its colour, GUILD NEWS dim: what kind of set, before its title)
    r.kind:ClearAllPoints(); r.kind:SetPoint("LEFT", 8, 0); r.kind:Show()
    color(r.kind, set.kind == "n" and DIM or H.HeadColor(set.kind))
    U.FitText(r.kind, H.HEAD[set.kind] or "", 100)
    r.name:ClearAllPoints(); r.name:SetPoint("LEFT", 112, 0); r.name:SetWidth(180); r.name:SetJustifyH("LEFT")
    color(r.name, INK)
    U.FitText(r.name, set.title or "", 176)
    r.what:ClearAllPoints(); r.what:SetPoint("LEFT", 300, 0); r.what:SetWidth(w - 300 - DAY - 12); r.what:Show()
    U.FitText(r.what, names(set, 3), w - 300 - DAY - 16)
    r.val:Hide()
    r.who:ClearAllPoints(); r.who:SetPoint("RIGHT", -4, 0); r.who:SetWidth(DAY); r.who:SetJustifyH("RIGHT"); r.who:Show()
    color(r.who, DIM)
    r.who:SetText(dayOf(set.at))
    r.fn = function(_, which)
      if which == "RightButton" then
        -- (a local set, a record this client showed, is nobody's to update or withdraw)
        if not set.rec and C.Roster:MeOfficer() and type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function" then
          MenuUtil.CreateContextMenu(r, function(_, root)
            root:CreateTitle(set.title or "")
            if set.kind == "h" or set.kind == "s" then root:CreateButton("Update", function() local ok, why = H:Update(set); if not ok and why then C.Print("not updated: " .. why .. ".") end end) end
            root:CreateButton("Withdraw", function() H:Withdraw(set.at) end)
          end)
        end
        return
      end
      if C.CardFrame then C.CardFrame:Announce(set) end
    end
    r.tip = function(tip)
      tip:AddLine((H.HEAD[set.kind] or "") .. ": " .. (set.title or ""), 1, 1, 1)
      tip:AddLine(set.rec and ("A guild record, " .. (U.Ago(set.got or set.at) or "")) or ("Published by " .. (set.by or "?") .. ", " .. (U.Ago(set.got or set.at) or "")), 0.7, 0.7, 0.7)
      for _, c in ipairs(set.cards or {}) do tip:AddLine((c.title or "") .. ": " .. (c.name or "?"), 0.85, 0.85, 0.85) end
      tip:AddLine((C.Roster:MeOfficer() and not set.rec) and "Click: the set. Right-click: update or withdraw it." or "Click: the set.", 0.5, 0.5, 0.5, true)
    end
  end)
  ui.virtual = function() rows:Show(ui.scroll.bar:GetValue() or 0, ui.scroll:View()) end
  sf:SetContentHeight(#list * ROW + 8)
end

-- the Queue (9.1, 9.2): a tick box, the source's icon, the member in class colour, what, and when (or "Published by
-- Brann", or the lock for an item that routes Only you); a digest row opens in place to its entries; a draft opens
-- in the composer
local function queueEntries()
  local out = {}
  for _, r in ipairs(H.Rows()) do
    out[#out + 1] = { it = r }
    if r.entries and H.open[r.id] then for _, e in ipairs(r.entries) do out[#out + 1] = { it = e, sub = true } end end
  end
  return out
end
local DIGEST_WORD = { run = { "run card today", "run cards today" }, ach = { "achievement today", "achievements today" }, first = { "guild first today", "guild firsts today" } }
function H.DrawQueue(ui)
  local U, ROW = C.UI, C.UI.ROW
  local sf = ui.scroll
  local w = sf:Width()
  ui.rows:Clear()
  local entries = queueEntries()
  if #entries == 0 then
    say(ui, 6, 6, w - 12, "Nothing waiting.")
    sf:SetContentHeight(30)
    return
  end
  local rows = ui:List("halls.queue", makeRow)
  local RIGHT = 140
  rows:Set(#entries, 0, ROW, function(r, i, ly)
    local e = entries[i]
    local it = e.it
    local ind = e.sub and 16 or 0
    r.kind:Hide()
    r:SetHeight(ROW)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, -ly)
    r:SetWidth(w)
    r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
    r.bar:Show(); r.bar:SetColorTexture(C.Cards.EDGE[1], C.Cards.EDGE[2], C.Cards.EDGE[3], 1)
    r.val:Hide()
    r.icon:ClearAllPoints(); r.icon:SetPoint("LEFT", 28 + ind, 0); r.icon:Show()
    r.lock:Hide()
    r.who:ClearAllPoints(); r.who:SetPoint("RIGHT", -4, 0); r.who:SetWidth(RIGHT); r.who:SetJustifyH("RIGHT"); r.who:Show()
    color(r.who, DIM)
    r.name:ClearAllPoints(); r.name:SetPoint("LEFT", 50 + ind, 0); r.name:SetJustifyH("LEFT"); r.name:SetWidth(120)
    r.what:ClearAllPoints(); r.what:SetPoint("LEFT", 176 + ind, 0); r.what:SetWidth(w - 176 - ind - RIGHT - 12); r.what:Show()
    local whatW = w - 176 - ind - RIGHT - 16
    if it.entries then
      r.box:Hide()
      r.icon:SetTexCoord(0, 1, 0, 1); r.icon:SetTexture(GENERAL)
      color(r.name, INK)
      local words = DIGEST_WORD[it.digest] or { "item today", "items today" }
      r.name:SetWidth(300)
      U.FitText(r.name, #it.entries .. " " .. (#it.entries == 1 and words[1] or words[2]), 296)
      r.what:SetText("")
      r.who:SetText(H.open[it.id] and "Hide" or "Show")
      r.fn = function() H.open[it.id] = not H.open[it.id] or nil; C.UI:Draw() end
      r.tip = function(tip) tip:AddLine(r.name:GetText() or "", 1, 1, 1); tip:AddLine("Click to show or hide them; tick the ones to publish.", 0.7, 0.7, 0.7, true) end
      return
    end
    if it.src == "draft" then
      r.box:Hide()
      r.icon:SetTexCoord(0, 1, 0, 1); r.icon:SetTexture(GENERAL)
      color(r.name, INK)
      U.FitText(r.name, "Draft", 116)
      local set = it.set or {}
      -- (a hall's draft: its title and the cards its statistics make)
      local title, n = set.title or "", #(set.cards or {})
      if set.hall then
        title, n = set.hall.title or "", 0
        for i = 1, 5 do if set.hall.stats and set.hall.stats[i] then n = n + 1 end end
      end
      U.FitText(r.what, title .. DOT .. n .. (n == 1 and " card" or " cards"), whatW)
      r.who:SetText(U.Ago(it.at) or "")
      r.fn = function(_, which)
        if which == "RightButton" then H:Unqueue({ it.id }); C.UI:Draw() return end
        local d = deep(set)
        d.mode = d.mode or "set"; d.draftId = it.id
        H.draft = d
        C.UI:Draw()
      end
      r.tip = function(tip) tip:AddLine("Draft: " .. title, 1, 1, 1); tip:AddLine("Click: open it. Right-click: delete it.", 0.7, 0.7, 0.7, true) end
      return
    end
    local c = it.card or {}
    local can = H.Tickable(it)
    r.box:ClearAllPoints(); r.box:SetPoint("LEFT", 8 + ind, 0); r.box:Show()
    r.fill:SetShown(H.ticked[it.id] == true)
    r.fill:SetVertexColor(1, 1, 1, can and 1 or 0.4)
    setIcon(r.icon, it)
    color(r.name, c.guild and WHITE or U.ClassColor(c.class))
    U.FitText(r.name, c.name or "?", 116)
    color(r.what, can and INK or MUTE)
    local whoW
    if it.pub then whoW = measure(r.who, "Published by " .. it.pub)
    elseif it.lock or not H.Open(c.source) then
      local tw = measure(r.who, "Only you")
      r.lock:ClearAllPoints(); r.lock:SetPoint("RIGHT", r.who, "RIGHT", -(tw + 6), 0); r.lock:SetTexture(LOCK); r.lock:Show()
      whoW = tw + 18
    else whoW = measure(r.who, U.Ago(it.at) or "") end
    -- (its mark in DIM before the right-hand words: "server" where the server shows it too, "Guild first?")
    if it.mark then
      local mw = math.min(96, measure(r.kind, it.mark) + 4)
      r.kind:ClearAllPoints(); r.kind:SetPoint("RIGHT", r, "RIGHT", -(4 + math.min(whoW, RIGHT) + 10), 0)
      r.kind:SetWidth(mw); r.kind:SetJustifyH("RIGHT"); color(r.kind, DIM); r.kind:Show()
      U.FitText(r.kind, it.mark, mw)
      local room = w - 176 - ind - (4 + math.min(whoW, RIGHT) + 10 + mw + 8)
      r.what:SetWidth(room); whatW = room - 4
    end
    U.FitText(r.what, it.what or c.title or "", whatW)
    r.fn = function(_, which)
      if which == "RightButton" then
        if type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function" then
          MenuUtil.CreateContextMenu(r, function(_, root)
            root:CreateTitle(c.name or "")
            root:CreateButton("Remove from the queue", function() H:Unqueue({ it.id }); C.UI:Draw() end)
          end)
        end
        return
      end
      if not H.Tickable(it) then return end
      H.ticked[it.id] = not H.ticked[it.id] or nil
      C.UI:Draw()
    end
    r.tip = function(tip)
      tip:AddLine((c.title or "") .. ": " .. (c.name or "?"), 1, 1, 1)
      if c.line and c.line ~= "" then tip:AddLine(c.line, 0.85, 0.85, 0.85, true) end
      if c.value and c.value ~= "" then tip:AddLine(c.value .. " " .. (c.valueLabel or ""), 0.85, 0.85, 0.85) end
      -- (a first: what it rests on; an earn the server shows too)
      if it.rests then tip:AddLine("Guild first? " .. it.rests, 0.85, 0.85, 0.85, true)
      elseif it.mark == "server" then tip:AddLine("Guild news or the server's guild line shows it too.", 0.7, 0.7, 0.7, true) end
      if it.pub then tip:AddLine("Published by " .. it.pub .. ".", 0.7, 0.7, 0.7, true)
      elseif not can then tip:AddLine("Only you and the officers see this: it cannot be published.", 0.7, 0.7, 0.7, true)
      else tip:AddLine("Click to tick it; right-click to remove it.", 0.5, 0.5, 0.5, true) end
    end
  end)
  ui.virtual = function() rows:Show(ui.scroll.bar:GetValue() or 0, ui.scroll:View()) end
  sf:SetContentHeight(#entries * ROW + 8)
end

----------------------------------------------------------------------------
-- the composer (9.2, 9.5): in the Queue chip's place, drawn as Settings draws its column (a heading, a label and its
-- box, a choice, a check row, a row of buttons), on a frame of its own under the scroll child (UI:Host). H.draft is
-- what it edits: { mode = "set" (items or a draft), "hall" (New hall) or "card" (New card), kind, title, cards, from,
-- chat, hall = { kind, period, stats, titles, lines, title }, draftId }
----------------------------------------------------------------------------
local HEAD_H, ROW_H, STEP, BTNS, GAP_H, LABEL_W = 20, 20, 24, 28, 10, 90
local function cpool(host, make)
  local p = { items = {}, used = 0 }
  function p:Get() self.used = self.used + 1; local it = self.items[self.used]; if not it then it = make(host); self.items[self.used] = it end it:Show(); return it end
  function p:Reset() self.used = 0 end
  function p:HideRest() for i = self.used + 1, #self.items do self.items[i]:Hide() end end
  return p
end
local POOLS = { "labels", "buttons", "checks", "edits" }
local function composerHost(ui)
  local host = ui:Host("halls.compose")
  if not host.labels then
    host.labels = cpool(host, function(p) return C.UI.Text(p, 12, INK, "LEFT", 300) end)
    host.buttons = cpool(host, function(p) return C.UI.Button(p, "", 140) end)
    host.checks = cpool(host, function(p) return C.UI.CheckRow(p) end)
    host.edits = cpool(host, function(p)
      local e = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
      e:SetSize(160, 20)
      e:SetAutoFocus(false)
      e:SetFont(C.UI.FONT, 12, "")
      return e
    end)
  end
  for _, k in ipairs(POOLS) do host[k]:Reset() end
  host:ClearAllPoints()
  host:SetPoint("TOPLEFT", 0, 0)
  return host
end
local function tipOn(owner, fill)
  if not fill then owner:SetScript("OnEnter", nil); owner:SetScript("OnLeave", nil) return end
  owner:SetScript("OnEnter", C.Safe(function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); fill(GameTooltip); GameTooltip:Show() end, "halls: tooltip"))
  owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
local Col = {}
Col.__index = Col
local function column(host, x, w) return setmetatable({ host = host, x = x, w = w, y = 4, fresh = true }, Col) end
function Col:Label(x, y, w, s, c, justify)
  local l = self.host.labels:Get()
  l:ClearAllPoints()
  l:SetPoint("TOPLEFT", x, -y)
  l:SetWidth(w)
  l:SetJustifyH(justify or "LEFT")
  color(l, c or INK)
  C.UI.FitText(l, s, w - 4)
  return l
end
function Col:Head(s)
  if not self.fresh then self.y = self.y + GAP_H end
  self.fresh = false
  self:Label(self.x, self.y, self.w, s, WHITE)
  self.y = self.y + HEAD_H
end
-- a line of explanation, dim; under a box where under
function Col:Note(s, c, under)
  self.fresh = false
  local x = under and (self.x + LABEL_W + 10) or self.x
  self:Label(x, self.y, self.w - (x - self.x), s, c or DIM)
  self.y = self.y + 18
end
-- a text box after its label (max letters; wide: the line's): what is typed is kept as it is typed
function Col:Edit(text, get, set, max, wide)
  self.fresh = false
  self:Label(self.x, self.y + 3, LABEL_W, text, DIM)
  local e = self.host.edits:Get()
  e:ClearAllPoints()
  e:SetPoint("TOPLEFT", self.x + LABEL_W + 10, -self.y)
  e:SetWidth(math.min(wide and 400 or 200, self.w - LABEL_W - 14))
  e:SetMaxLetters(max or TITLE)
  if not e:HasFocus() then e:SetText(get() or "") end
  e:SetScript("OnTextChanged", function(b, user) if user then set(b:GetText() or "") end end)
  e:SetScript("OnEnterPressed", function(b) set(b:GetText() or ""); b:ClearFocus() end)
  e:SetScript("OnEscapePressed", function(b) b:SetText(get() or ""); b:ClearFocus() end)
  e:SetScript("OnEditFocusLost", function(b) set(b:GetText() or "") end)
  self.y = self.y + STEP
  return e
end
-- a button after its label that opens a menu (a card's label, a hall's statistic)
function Col:Pick(text, value, fn, tip)
  self.fresh = false
  self:Label(self.x, self.y + 3, LABEL_W, text, DIM)
  local b = self.host.buttons:Get()
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", self.x + LABEL_W + 10, -self.y)
  b:SetWidth(200)
  b:SetLabel(value)
  b:SetOn(true)
  b:SetScript("OnClick", function(btn) fn(btn) end)
  tipOn(b, tip)
  self.y = self.y + STEP
  return b
end
-- a choice of one among a few, each a short check row
function Col:Choice(text, options, current, fn)
  self.fresh = false
  self:Label(self.x, self.y + 2, LABEL_W, text, DIM)
  local cx = self.x + LABEL_W + 10
  for _, opt in ipairs(options) do
    local cb = self.host.checks:Get()
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", cx, -self.y)
    cb:SetWidth(94)
    cb.label:SetWidth(74)
    C.UI.FitText(cb.label, opt, 72)
    cb:Set(current == opt)
    cb:SetOn(true)
    cb.fn = function(b) if b:GetChecked() then fn(opt) else b:Set(true) end end
    cx = cx + 98
  end
  self.y = self.y + ROW_H
end
function Col:Check(text, on, enabled, fn, right)
  self.fresh = false
  local cb = self.host.checks:Get()
  cb:ClearAllPoints()
  cb:SetPoint("TOPLEFT", self.x, -self.y)
  local room = self.w - (right and 160 or 0)
  cb:SetWidth(room)
  cb.label:SetWidth(room - 24)
  C.UI.FitText(cb.label, text, room - 28)
  cb:Set(on and true or false)
  cb:SetOn(enabled ~= false)
  cb.fn = function(b) if enabled == false then b:Set(on and true or false) return end fn(b:GetChecked()) end
  if right then self:Label(self.x + self.w - 156, self.y + 3, 156, right, MUTE, "RIGHT") end
  self.y = self.y + ROW_H
  return cb
end
function Col:Buttons(list)
  if not self.fresh then self.y = self.y + 6 end
  self.fresh = false
  local bx = self.x
  for _, d in ipairs(list) do
    local b = self.host.buttons:Get()
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", bx, -self.y - 2)
    b:SetWidth(120)
    b:SetLabel(d[1])
    b:SetOn(d[2] and true or false)
    b:SetScript("OnClick", function() if d[2] then d[3]() end end)
    tipOn(b, d[4])
    bx = bx + 126
  end
  self.y = self.y + BTNS
end

-- a card's label, from a menu of the seven
local function kindMenu(owner, c)
  if not (type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function") then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Label")
    for _, k in ipairs(H.KINDS) do root:CreateButton(H.LABEL[k], function() c.kind = k; C.UI:Draw() end) end
  end)
end
local function classed(name, class) return "|cff" .. C.UI.Hex(C.UI.ClassColor(class)):sub(5) .. (name or "?") .. "|r" end
-- a member of the roster by what an officer typed: a name whole, else the one name it starts
function H.FindMember(text)
  text = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return nil end
  local found, n = nil, 0
  for _, row in ipairs(C.Roster:Rows()) do
    local s = (row.short or ""):lower()
    if row.guid and s == text then return row end
    if row.guid and s:sub(1, #text) == text then found, n = row, n + 1 end
  end
  return n == 1 and found or nil
end
-- New hall: the composer filled for a kind and period (9.5): its title and stats, each card's title and line
function H.NewHall(kind, period, keepId)
  local stats = H.HallStats(kind, period)
  local titles, lines = {}, {}
  local L = kind == "shame" and H.SHAME_LINES or H.FAME_LINES
  for i = 1, 5 do
    local d = stats[i] and C.Stats.byId[stats[i]]
    titles[i], lines[i] = d and d.label or "", L[i]
  end
  H.draft = { mode = "hall", chat = H.Prefs().chat ~= false, draftId = keepId,
    hall = { kind = kind, period = period, stats = stats, titles = titles, lines = lines, title = H.HallTitle(period) } }
end
local PERIODS = { { "a", "All time" }, { "w", "This week" }, { "l", "Last week" } }
local function periodName(p) for _, e in ipairs(PERIODS) do if e[1] == p then return e[2] end end return "All time" end
local function drawHall(cc, d)
  local h = d.hall
  cc:Head("New hall")
  cc:Choice("Kind", { "Fame", "Shame" }, h.kind == "shame" and "Shame" or "Fame", function(v) H.NewHall(v == "Shame" and "shame" or "fame", h.period, d.draftId); C.UI:Draw() end)
  cc:Choice("Period", { "All time", "This week", "Last week" }, periodName(h.period), function(v)
    for _, e in ipairs(PERIODS) do if e[2] == v then H.NewHall(h.kind, e[1], d.draftId) end end
    C.UI:Draw()
  end)
  cc:Edit("Title", function() return h.title end, function(v) h.title = v end, TITLE)
  for i = 1, 5 do
    local id = h.stats[i]
    local def = id and C.Stats.byId[id]
    cc:Head("Card " .. i)
    cc:Pick("Statistic", def and def.label or "None", function(btn)
      H.PickStat(h.period, function(pick)
        local old = h.stats[i] and C.Stats.byId[h.stats[i]]
        h.stats[i] = pick or false
        local new = pick and C.Stats.byId[pick]
        -- (the title follows the statistic unless the officer wrote one)
        if not h.titles[i] or h.titles[i] == "" or (old and h.titles[i] == old.label) then h.titles[i] = new and new.label or "" end
        C.UI:Draw()
      end, btn)
    end, function(tip) tip:AddLine("Statistic", 1, 1, 1); tip:AddLine("Its leader gets the card; None leaves the card out.", 0.85, 0.85, 0.85, true) end)
    cc:Edit("Title", function() return h.titles[i] end, function(v) h.titles[i] = v end, TITLE)
    cc:Edit("Line", function() return h.lines[i] end, function(v) h.lines[i] = v end, LINE, true)
  end
end
local function drawCards(cc, d)
  cc:Head(d.mode == "card" and "New card" or "Compose")
  cc:Edit("Title", function() return d.title end, function(v) d.title = v end, TITLE)
  for i, c in ipairs(d.cards) do
    if d.mode == "card" then
      cc:Head("The card")
      cc:Edit("Member", function() return d.member end, function(v)
        d.member = v
        local row = H.FindMember(v)
        c.guid, c.sfx, c.name, c.class = row and row.guid, row and sfxOf(row.guid), row and row.short, row and row.class
        if d.shown ~= (row and row.guid or false) then d.shown = row and row.guid or false; C.UI:Refresh() end
      end, NAME * 2)
      cc:Note(c.guid and classed(c.name, c.class) or "No member by that name yet.", c.guid and INK or MUTE, true)
    else
      cc:Head("Card " .. i .. ": " .. classed(c.name, c.class))
    end
    cc:Pick("Label", H.LABEL[c.kind] or "SHOUT-OUT", function(btn) kindMenu(btn, c) end)
    cc:Edit("Title", function() return c.title end, function(v) c.title = v end, TITLE)
    cc:Edit("Line", function() return c.line end, function(v) c.line = v end, LINE, true)
  end
end
-- the set the composer holds now, as Preview shows it and Publish sends it
function H.Built()
  local d = H.draft
  if not d then return nil end
  local set
  if d.mode == "hall" then set = H:ComputeHall(d.hall)
  else
    set = { kind = d.kind or "n", title = clean(d.title, TITLE), cards = {}, from = d.from }
    for _, c in ipairs(d.cards or {}) do if c.name and (c.guid or d.mode ~= "card") then set.cards[#set.cards + 1] = copy(c) end end
  end
  set.chat, set.draftId = d.chat, d.draftId
  return set
end
function H.Preview()
  local set = H.Built()
  if set and C.CardFrame then C.CardFrame:Announce(set, { preview = true }) end
  return set
end
-- Publish from the preview, in its click (the guild line goes in the same call stack)
function H.PublishClick(set)
  local ok, why = H:Publish(set, set and set.chat)
  if not ok and why then C.Print("not published: " .. why .. ".") end
  return ok
end
function H.DrawCompose(ui)
  local sf = ui.scroll
  ui.rows:Clear()
  local d = H.draft
  local w = math.min(540, sf:Width() - 12)
  local host = composerHost(ui)
  local cc = column(host, 6, w)
  if d.mode == "hall" then drawHall(cc, d) else drawCards(cc, d) end
  local okChat, why = H.ChatState()
  cc:Check("Also post a line in guild chat", d.chat, okChat, function(on) d.chat = on; H.Prefs().chat = on end, not okChat and why or nil)
  -- (Preview only for a set with a card: a member found, a statistic with a leader)
  local built = H.Built()
  local any = built and #(built.cards or {}) > 0
  cc:Buttons({ { "Preview", any, function() H.Preview() end, function(tip)
      tip:AddLine("Preview", 1, 1, 1)
      tip:AddLine(any and "The set as the guild would see it; nothing goes until Publish." or "No card yet: a member, or a statistic with a leader.", 0.85, 0.85, 0.85, true)
    end },
    { "Save draft", true, function() local ok, why2 = H:SaveDraft(d); if ok then H.draft = nil elseif why2 then C.Print(why2 .. ".") end C.UI:Draw() end },
    { "Clear", true, function() H.draft = nil; C.UI:Draw() end } })
  for _, k in ipairs(POOLS) do host[k]:HideRest() end
  host:SetSize(sf:Width(), cc.y + 8)
  sf:SetContentHeight(cc.y + 8)
end

----------------------------------------------------------------------------
-- Settings > Halls (14): announcements on my screen, and the test announcement. The live Hall of Shame's checklist
-- of cards follows it in the same section
----------------------------------------------------------------------------
function H.SettingsSection(_, col)
  col:Head("Announcements")
  col:Check("Announcements on my screen", H.Prefs().toast ~= false, true, function(on) H.Prefs().toast = on; C.UI:Draw() end, nil, function(tip)
    tip:AddLine("Announcements on my screen", 1, 1, 1)
    tip:AddLine("A set the officers publish shows as a toast at the top of the screen. Off: it goes to News alone.", 0.85, 0.85, 0.85, true)
  end)
  col:Buttons({ { "Test announcement", true, function() H.Test(false) end, function(tip)
    tip:AddLine("Test announcement", 1, 1, 1)
    tip:AddLine("A toast and three made-up cards on your screen; nothing is sent or kept.", 0.85, 0.85, 0.85, true)
  end } })
end

----------------------------------------------------------------------------
-- /cute halls, /cute card test [hall], /cute diag cards (no name: counts and states)
----------------------------------------------------------------------------
function H.Diag()
  local d = H.DB()
  local rows, items, drafts = 0, 0, 0
  for _, r in ipairs(d.queue) do rows = rows + 1; if r.src == "draft" then drafts = drafts + 1 end; items = items + (r.entries and #r.entries or (r.card and 1 or 0)) end
  local newest = H.Newest()
  local quiet, why = quietNow()
  local out = {
    string.format("diag cards: %d sets held (newest %s), %d unseen | queue %d rows, %d items, %d drafts | officer %s", #d.sets, newest > 0 and (math.floor(now() - newest) .. " s ago") or "none",
      H.Unseen(), rows, items, drafts, tostring(officer())),
    string.format("diag cards: toasts shown %d, waiting %d, %d this hour, now %s | guild line filter %s, lines hidden %d, posted %d | refused %d | 1G %s, answers %d | 1W sent %d, held %d",
      H.toastsShown or 0, #H.toasts, recent(H.toastLog, HOUR), quiet and "free" or ("held: " .. tostring(why)), H.filterOK and "on" or "missing", H.hidden or 0, H.posted or 0, H.refused or 0,
      H.asked and "asked" or "not asked", H.answers or 0, H.wSent or 0, type(C.Char().pendingW) == "table" and #C.Char().pendingW or 0),
  }
  -- (the achievements' own: Achievements.lua; the records': Records.lua)
  if C.Achievements and C.Achievements.Diag then for _, l in ipairs(C.Achievements.Diag()) do out[#out + 1] = l end end
  if C.Records and C.Records.Diag then for _, l in ipairs(C.Records.Diag()) do out[#out + 1] = l end end
  return out
end
do
  local core = SlashCmdList.CUTE
  SlashCmdList.CUTE = C.Safe(function(msg)
    local m = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if m == "halls" then C.UI:Open("shame") return end
    if m == "hall of shame" or m == "hallofshame" then H.OpenChip("shame") return end
    if m == "card test" then H.Test(false) return end
    if m == "card test hall" then H.Test(true) return end
    if m == "diag cards" then for _, l in ipairs(H.Diag()) do C.Print(l) end return end
    return core(msg)
  end, "slash")
end

----------------------------------------------------------------------------
-- events: a loading screen (the toasts wait 2 s after it; held run cards may go; the first one asks the officers for
-- the sets newer than this client holds, a minute after the hello), combat's end and an encounter's (a waiting toast)
----------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("ENCOUNTER_END")
local function askLater()
  if H.asked then return end
  local M = C.Comm
  if M.hello and M.helloAt and C.Now() - M.helloAt >= ASK_AFTER then H:Ask() return end
  C_Timer.After(5, C.Safe(askLater, "halls: ask"))
end
ev:SetScript("OnEvent", C.Safe(function(_, event, a1, a2)
  if event == "PLAYER_ENTERING_WORLD" then
    H.loadingUntil = gtime() + 2
    C_Timer.After(2.1, C.Safe(function() H:NextToast() end, "halls: toast"))
    local initial, reloading = C.Plain(a1) == true, C.Plain(a2) == true
    if not H.filtered then
      H.filtered = true
      local CF = ChatFrameUtil
      if type(CF) == "table" and type(CF.AddMessageEventFilter) == "function" then H.filterOK = pcall(CF.AddMessageEventFilter, "CHAT_MSG_GUILD", H.LineFilter) end
    end
    if initial and not H.loginAt then H.loginAt = gtime() end
    if not reloading and not H.askStarted then H.askStarted = true; C_Timer.After(5, C.Safe(askLater, "halls: ask")) end
    C_Timer.After(3, C.Safe(function() H:FlushRuns() end, "halls: run cards"))
  elseif event == "PLAYER_REGEN_ENABLED" then H:NextToast()
  elseif event == "ENCOUNTER_END" then C_Timer.After(1, C.Safe(function() H:NextToast() end, "halls: toast")) end
end, "halls: events"))

----------------------------------------------------------------------------
-- the tab: the core's shame page becomes the Halls tab (9.4), its id kept. Its page draws the chips (the Hall of
-- Shame chip is 0.7's own page, UI:DrawShame), its Settings section Halls' rows above the live cards' checklist
----------------------------------------------------------------------------
do
  local def = C.Modules and C.Modules.byId and C.Modules.byId.shame
  if def then
    local cards = def.settings
    def.title, def.tab = "Halls", 64
    def.page = function(ui) H.Draw(ui) end
    def.settings = function(ui, col) H.SettingsSection(ui, col); if cards then cards(ui, col) end end
  else
    -- (a window without the shame page: the tab registered here under its id, the live cards where the window has them)
    C:RegisterModule({ id = "shame", title = "Halls", order = 40, core = true, tab = 64, page = function(ui) H.Draw(ui) end,
      settings = function(ui, col) H.SettingsSection(ui, col) end })
  end
end
