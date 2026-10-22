-- SPDX-License-Identifier: GPL-3.0-or-later
-- Finds in the guild (the windows design, 11.4 and 11.5: sub-project G). What members find in the world beyond quests,
-- as the quest engine notes it (QuestBank's Finds.lua: a book read where it stands, an object opened with a key, a chest
-- looted, a rare's nameplate, a crossing), shared inside the guild on Cute's own channel: Comm.lua's queue, with its
-- lockdown, its hold for the policy and its routing as each message leaves. A new kind, after Comm's:
--   1X|entry;entry;...   ids and maps in base 36, a spot in thousandths of its map in base 36:
--     b<object>@<map>:<x>,<y>=<title>             a book read where it stands, by its title (never its text)
--     k<object>@<map>:<x>,<y>                      an object opened with a key (never which key: the uploads carry it)
--     h<object>@<map>:<x>,<y>                      a chest looted (never a herb or ore node: it would name a profession)
--     r<creature>@<map>:<x>,<y>=<level>            a rare up now: a ping, shown ten minutes and never kept
--     x<map>:<x>,<y>><map>:<x>,<y>=<seconds>       a crossing: where it starts, where you came out, how long it took
--     s<b, k or h entry>                           a secret chain's next step (the engine tells which: opened carrying one
--                                                  of its keys, QuestBank's D.SECRETKEY): drawn on a guild mate's map only
--                                                  once two guild mates found it, never dim (the windows design, 11.3)
--   An older Cute passes 1X by; an entry of a kind this one does not know is passed by (an older one's, a secret step).
-- Two voices. A guild mate's find counts (sure: drawn whole on the map, counted, said in the officers' word) once two
-- members agree: two GUIDs the roster lists, neither marked untrusted, spots within NEAR thousandths (its place their
-- mean). One alone is display only, drawn dim; your own is yours at once (the engine's). A rare's ping is display only
-- and goes after PING_LIFE. Kept in CuteDB.known.finds, never in the quest engine's file (the site counts each player's
-- own eyes once, and an edited copy cannot launder guild data into a release): ALL finds at most, EACH that one member
-- alone speaks for, VOICES voices a find, the one touched longest ago out; a find QuestBank's data carries now (a
-- release, the uploader's data file) is dropped as the engine comes up (F.Attach), and never taken.
-- The pace. Only what this client's data and the guild's sure finds lack goes: one message in EVERY seconds and HOUR an
-- hour at most, none in the first FIRST seconds after the hello (the records go then), never from inside an instance,
-- a rare's ping first (one a creature in PING_EVERY). What one sender may cost a receiver is capped as well: HEAR_HOUR
-- messages an hour, PER_MSG entries a message, a ping a creature in PING_EVERY.
-- Who sees it. The Finds category of Who sees what (Stats.lua S.FOUND gains "finds", code "cf", Everyone by default),
-- with Zone (a find says where you stood: Policy.lua P:FindsRoute). Closed, each 1X leaves whispered to the officers
-- online (Comm.lua's build and mark, as any value the officers keep; with none online it waits for one); an officer's
-- client confirms what it hears with two voices and says the guild's sure finds in the officers' word (1N, no GUID:
-- F:WordParts) WORD_AGE after they became sure (never where two members stood a minute ago), which is how the members,
-- and those who log in later, have them. Open, the members heard the voices: the word carries the finds to those who
-- ask later (Comm.lua sends no word for the finds alone). A member's relay proves no voices and is never taken (the
-- word is taken only from an officer's voice, and what it said is sure while that officer is one). A member's client
-- takes no 1X on GUILD while the category is closed (only an edited copy would send one) and keeps no other member's
-- voice (Policy.lua P:Purge, F.StripTraces). With "Share finds with the guild" off your finds are no voice at all.
-- And this character's counts, Statistics' Finds category: Finds first, Books read, Rares seen, Chests looted.
local _, C = ...
local F = { ver = 0, pings = {}, pingFrom = {}, pinged = {}, outPings = {}, rate = {}, sentAt = {},
  heard = 0, taken = 0, refused = 0, capped = 0, unknown = 0 }
C.Finds = F

local NEAR = 15          -- thousandths of the map: two spots this close are one find (QuestBank's Discover OS_NEAR)
local VOICES = 4         -- voices kept for one find
local EACH = 300         -- finds one member's voice alone may hold here
local ALL = 2000         -- finds kept
local CROSSINGS = 100    -- crossings among them
local PER_MSG = 10       -- entries a message (about 20 bytes each)
local LIMIT = 255        -- the client's cap on one addon message
local EVERY = 60         -- seconds between two messages of yours
local HOUR = 30          -- messages of yours an hour
local FIRST = 120        -- seconds after the hello before the first (the records and the statistics go then)
local OUT_MAX = 60       -- finds of yours waiting to go
local PING_EVERY = 300   -- seconds between two pings of one creature, sent or taken
local PING_LIFE = 600    -- seconds a ping shows
local PINGS = 40         -- pings kept
local HEAR_HOUR = 40     -- messages taken from one sender an hour
local WORD_MAX = 48      -- sure finds an officer's word says, the newest
local WORD_AGE = 1800    -- seconds a find is sure before the word says it, where the officers keep Finds or Zone (said
                         -- at once, it would tell every member where two members stood a minute ago)
local SEEN_MAX = 3000    -- this character's finds counted (Statistics' Finds category)
local MAP_MAX, ID_MAX = 99999, 99999999
F.NEAR, F.ALL, F.EACH, F.VOICES, F.HOUR, F.EVERY, F.PING_LIFE = NEAR, ALL, EACH, VOICES, HOUR, EVERY, PING_LIFE

local function now() return C.Now() end
local function clock() return (GetTime and GetTime()) or C.Now() end
local function b36(n) return C.Comm.b36(n) end
local function unb36(s) local n = C.Comm.unb36(s); return (n and n == math.floor(n)) and n or nil end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

-- the public face (Cute.Finds): the quest engine's host (QuestBank's Finds.lua Finds.host: Noted, Rows, Maps, ver), and
-- what Cute_Quest's Bridge attaches (F.Attach) and its Settings section draws (ShareLine, ShareRow)
local D = {}
if C.API then C.API.Finds = D end
F.door = D
-- (the host's ver, as the engine reads it: what the guild shared, and the policy, whose untrusted marks and routing
-- change which voices count; both only go up. The roster changes which voices count as well, a member gone or back:
-- at a change of who is who, F:Voters counts them again and moves F.ver where the count moved)
local function verNow()
  if F.Voters then F:Voters() end
  return F.ver * 100000 + ((C.Policy and C.Policy.ver) or 0) % 100000
end
setmetatable(D, { __index = function(_, k) if k == "ver" then return verNow() end end })

----------------------------------------------------------------------------
-- the category, and this character's counts (Stats.lua's registry, extended here as Runs.lua extends it)
----------------------------------------------------------------------------
do
  local S = C.Stats
  assert(not S.byCode.cf, "the Finds category's code")
  S.FOUND[#S.FOUND + 1] = { "finds", "Finds", "cf" }
  S.byCode.cf = "gc_finds"
  -- (a discovered stat's: a count Sample.lua keeps per character, no value where it never counted one, never down;
  -- standing, defined at load and not by a discovery (Comm.lua owes no statistics pass for one without a value); the
  -- category on the Statistics page once anyone has one, F.StatsShown)
  local function def(id, label, hint)
    return S.def(id, label, "found", { learned = "finds", track = true, grows = true, standing = true, hint = hint, shown = function() return F.StatsShown() end })
  end
  def("finds_first", "Finds first", "books, locks, chests and crossings this character found before anyone in the guild")
  def("books_read", "Books read", "books this character read where they stand")
  def("rares_seen", "Rares seen", "rares this character saw, each once")
  def("chests_looted", "Chests looted", "chests this character looted, each once")
  S.BoardKey = function() return F.StatsShown() end
end
-- does anyone have one of the counts: this character, or a record held (looked at again when the roster changed)
local STATS = { "finds_first", "books_read", "rares_seen", "chests_looted" }
local rosterAt, rosterHas = nil, false
function F.StatsShown()
  if not C.loaded then return false end
  local own = C.Char().counters
  for _, id in ipairs(STATS) do if own[id] then return true end end
  local R = C.Roster
  local v = R and R.version
  if rosterAt ~= v then
    rosterAt, rosterHas = v, false
    for _, e in pairs(CuteDB.roster or {}) do
      local st = type(e) == "table" and e.stats
      if type(st) == "table" then for _, id in ipairs(STATS) do if st[id] ~= nil then rosterHas = true end end end
      if rosterHas then break end
    end
  end
  return rosterHas
end

----------------------------------------------------------------------------
-- the store: CuteDB.known.finds = { n, list }, each { k, id, m, x, y (the mean of its voices), t (a book's title as the
-- guild shows it, titleOf: two voices' alike, else an officer's word's), tv = { [GUID] = the title that voice gave },
-- wt (the title an officer's word gave), m2,
-- x2, y2, s (a crossing's far end and seconds), v = { [GUID] = its spot packed }, o (the sender string of the officer
-- whose word said it: sure while that is an officer's voice), at (n when last touched), sa (n when it became sure), st
-- (the server's time then, to the minute), wx, wy, wx2, wy2 (its place then: the word's key, which a voice moving the
-- mean afterwards leaves as it was) }
----------------------------------------------------------------------------
local function store()
  local k = C.Stats.Known()
  if not k then return nil end
  if type(k.finds) ~= "table" then k.finds = { n = 0, list = {} } end
  local s = k.finds
  if type(s.list) ~= "table" then s.list = {} end
  s.n = tonumber(s.n) or 0
  return s
end
F.Store = store
local function groupOf(e) if e.k == "x" then return "x" .. e.m .. ">" .. (e.m2 or 0) end return e.k .. e.id .. "@" .. e.m end
-- (in memory: the finds by what they are, kept as finds come and go; built again after a prune or a purge)
local index, indexFor = nil, nil
local function byGroup(s)
  if index and indexFor == s.list then return index end
  index, indexFor = {}, s.list
  for _, e in ipairs(s.list) do
    if type(e) == "table" and type(e.v) == "table" then
      local g = groupOf(e)
      index[g] = index[g] or {}
      table.insert(index[g], e)
    end
  end
  return index
end
local function packOf(en) return ((en.x * 1001 + en.y) * 1001 + (en.x2 or 0)) * 1001 + (en.y2 or 0) end
local function unpack4(p)
  p = tonumber(p) or 0
  local y2 = p % 1001; p = (p - y2) / 1001
  local x2 = p % 1001; p = (p - x2) / 1001
  local y = p % 1001
  return (p - y) / 1001, y, x2, y2
end
local function d2(ax, ay, bx, by) return (ax - bx) ^ 2 + (ay - by) ^ 2 end
-- the find an entry is: of its kind and object on its map (a crossing: its two maps), the nearest within NEAR (both ends)
local function match(s, en)
  local best, bestD
  for _, e in ipairs(byGroup(s)[groupOf(en)] or {}) do
    local d = d2(e.x, e.y, en.x, en.y)
    if en.k == "x" then
      if d2(e.x2 or 0, e.y2 or 0, en.x2 or 0, en.y2 or 0) > NEAR * NEAR then d = math.huge end
    end
    if d <= NEAR * NEAR and (not bestD or d < bestD) then best, bestD = e, d end
  end
  return best
end
local function untrusted(g) return C.Policy:Untrusted(g) end
-- a voice that counts: yours, or a member's the roster lists now, never one the officers marked untrusted. A GUID the
-- roster does not list counts for nothing: a member who left, or another guild's (CuteDB.known is the account's, and an
-- alt in another guild shares it: Policy.lua P:ForClub)
local function counts(g, me)
  if untrusted(g) then return false end
  return g == me or C.Roster.byGuid[g] ~= nil
end
-- a find's voices that count, those of others, and whether yours is one (noMe: yours left out, "Share finds with the
-- guild" off)
local function tally(e, noMe)
  local me, n, others, mine = C.MyGUID(), 0, 0, false
  for g in pairs(e.v) do
    if counts(g, me) and not (noMe and g == me) then
      n = n + 1
      if g == me then mine = true else others = others + 1 end
    end
  end
  return n, others, mine
end
-- the officers' word says it: the officer whose word said it is one still (Roster.lua R:OfficerVoice: listed at an
-- officer's rank, not marked untrusted), as Rules.lua's R.Word reads each officer's word again
-- (each sender's answer kept while the roster's who is who, the policy and the line's officer ranks stand: a build reads
-- it for every find the word said)
local voiceAt, voicePol, voiceThr, voiceOf = nil, nil, nil, {}
local function said(e)
  local o = e.o
  if type(o) ~= "string" then return false end
  local R, P = C.Roster, C.Policy
  local thr = P:LineThreshold()
  if voiceAt ~= R.idVersion or voicePol ~= P.ver or voiceThr ~= thr then voiceAt, voicePol, voiceThr, voiceOf = R.idVersion, P.ver, thr, {} end
  local v = voiceOf[o]
  if v == nil then v = R:OfficerVoice(o) and true or false; voiceOf[o] = v end
  return v
end
local function sure(e) return said(e) or (tally(e)) >= 2 end
F.Sure, F.Said = sure, said
-- a book's title as the guild shows and says it: one that two of its voices that count gave alike (each voice keeps its
-- own, e.tv), else the one an officer's word that says it gave (e.wt). Never the first voice's alone: an edited copy's
-- title, joined by an honest member who read the book, was drawn whole on every map and said in the officers' word
local function titleOf(e)
  if e.k ~= "b" then return nil end
  if type(e.tv) == "table" then
    local me, seen = C.MyGUID(), {}
    for g, t in pairs(e.tv) do
      if type(t) == "string" and e.v[g] ~= nil and counts(g, me) then
        seen[t] = (seen[t] or 0) + 1
        if seen[t] >= 2 then return t end
      end
    end
  end
  return (type(e.wt) == "string" and said(e)) and e.wt or nil
end
F.TitleOf = titleOf
-- the voices that count, counted again when the roster's who is who (Roster.lua R.idVersion), the policy or the line's
-- officer ranks changed: where the count moved, the version does (the map and the footers drawn from it again)
local votersAt, votersPol, votersThr, voters = nil, nil, nil, nil
function F:Voters()
  local R, P = C.Roster, C.Policy
  local at, pol, thr = R and R.idVersion, P and P.ver, P and P:LineThreshold()
  if at == votersAt and pol == votersPol and thr == votersThr then return end
  votersAt, votersPol, votersThr = at, pol, thr
  -- (an officer gone or demoted: another officer's word that says the same find holds it)
  if voters ~= nil and self.TakeWord then self:TakeWord(true) end
  local s, me, n = store(), C.MyGUID(), 0
  for _, e in ipairs(s and s.list or {}) do
    if type(e.v) == "table" then for g in pairs(e.v) do if counts(g, me) then n = n + 1 end end end
    if said(e) then n = n + 0.5 end
  end
  if voters ~= nil and n ~= voters then self.ver = self.ver + 1 end
  voters = n
end
local function drop(s, e)
  for i = #s.list, 1, -1 do if s.list[i] == e then table.remove(s.list, i) end end
  -- (out of its group in the index as well: the index stays, never built again for one find gone, as at the cap)
  local group = index and indexFor == s.list and index[groupOf(e)]
  if group then for i = #group, 1, -1 do if group[i] == e then table.remove(group, i) end end end
end
-- room for one more: past EACH of one member's lone finds that member's oldest goes, past CROSSINGS the oldest crossing,
-- past ALL the oldest find
local function oldest(s, test)
  local o
  for _, e in ipairs(s.list) do if test(e) and (not o or (e.at or 0) < (o.at or 0)) then o = e end end
  return o
end
local function room(s, en, g)
  if g then
    local lone = 0
    for _, e in ipairs(s.list) do if e.v[g] and not e.o and count(e.v) == 1 then lone = lone + 1 end end
    if lone >= EACH then drop(s, oldest(s, function(e) return e.v[g] ~= nil and not e.o and count(e.v) == 1 end)); F.capped = F.capped + 1 end
  end
  if en.k == "x" then
    local n = 0
    for _, e in ipairs(s.list) do if e.k == "x" then n = n + 1 end end
    if n >= CROSSINGS then drop(s, oldest(s, function(e) return e.k == "x" end)) end
  end
  while #s.list >= ALL do drop(s, oldest(s, function() return true end)) end
end
-- a new find of the store's, made from an entry
local function make(s, en, g)
  room(s, en, g)
  local idx = byGroup(s)
  local e = { k = en.k, id = en.id, m = en.m, x = en.x, y = en.y, m2 = en.m2, x2 = en.x2, y2 = en.y2, s = en.s, sec = en.sec, v = {} }
  s.list[#s.list + 1] = e
  local key = groupOf(e)
  idx[key] = idx[key] or {}
  table.insert(idx[key], e)
  return e
end
-- its place: the mean of its voices
local function remean(e)
  local n, sx, sy, sx2, sy2 = 0, 0, 0, 0, 0
  for _, p in pairs(e.v) do
    local x, y, x2, y2 = unpack4(p)
    n, sx, sy, sx2, sy2 = n + 1, sx + x, sy + y, sx2 + x2, sy2 + y2
  end
  if n == 0 then return end
  e.x, e.y = math.floor(sx / n + 0.5), math.floor(sy / n + 0.5)
  if e.k == "x" then e.x2, e.y2 = math.floor(sx2 / n + 0.5), math.floor(sy2 / n + 0.5) end
end
-- a voice for a find: member g's (yours too) at the entry's spot, the find it is or a new one (within the caps). The
-- find, and true where it became sure now
function F.Voice(g, en)
  local s = store()
  if not (s and type(g) == "string") then return nil end
  local e = match(s, en) or make(s, en, g)
  local was = sure(e)
  if e.v[g] ~= nil or count(e.v) < VOICES then
    e.v[g] = packOf(en)
    -- (a book's title, each voice its own: titleOf)
    if e.k == "b" and en.t then
      if type(e.tv) ~= "table" then e.tv = {} end
      e.tv[g] = en.t
    end
  end
  remean(e)
  e.t = titleOf(e)
  -- (a secret step stays one: any voice that says so marks it)
  if en.sec then e.sec = true end
  if en.s and e.k == "x" then e.s = math.floor(((e.s or en.s) + en.s) / 2 + 0.5) end
  s.n = s.n + 1
  e.at = s.n
  local became = sure(e) and not was
  if became then
    e.sa, e.st = s.n, math.floor(C.ServerNow() / 60) * 60
    e.wx, e.wy, e.wx2, e.wy2 = e.x, e.y, e.x2, e.y2
  end
  return e, became
end

----------------------------------------------------------------------------
-- the wire
----------------------------------------------------------------------------
-- the maps the client knows: C_Map.GetMapInfo returns nothing for one it lacks (MapDocumentation.lua:312,
-- MayReturnNothing; its argument is our own plain number), asked once a session each
local known, knownN = {}, 0
local function mapKnown(m)
  local k = known[m]
  if k ~= nil then return k end
  local CM = C_Map
  local info = type(CM) == "table" and C.Get(CM.GetMapInfo, m) or nil
  k = type(info) == "table"
  if knownN < 2000 then known[m], knownN = k, knownN + 1 end
  return k
end
local function spotOf(sm, sx, sy)
  local m, x, y = unb36(sm), unb36(sx), unb36(sy)
  if not (m and x and y) or m < 1 or m > MAP_MAX or x < 0 or x > 1000 or y < 0 or y > 1000 then return nil end
  if not mapKnown(m) then return nil end
  return m, x, y
end
local function spotText(m, x, y) return b36(m) .. ":" .. b36(x) .. "," .. b36(y) end
-- a title as it may travel and be shown (Stats.lua's label cleaning: no separators or control characters, 60 bytes)
local function title(t) local s = C.Stats.CleanLabel(t or ""); return s ~= "" and s or nil end
-- a kind a secret step may be: a book, a lock, a chest (never a rare's ping nor a crossing)
local SECRET_KIND = { b = true, k = true, h = true }
-- an entry as its wire text; nil for one that cannot go
function F.Pack(en)
  if en.sec and SECRET_KIND[en.k] then
    local kv = F.Pack({ k = en.k, id = en.id, m = en.m, x = en.x, y = en.y, t = en.t })
    return kv and ("s" .. kv) or nil
  end
  if en.k == "x" then
    return "x" .. spotText(en.m, en.x, en.y) .. ">" .. spotText(en.m2, en.x2, en.y2) .. "=" .. b36(en.s or 1)
  end
  local head = en.k .. b36(en.id) .. "@" .. spotText(en.m, en.x, en.y)
  if en.k == "b" then local t = title(en.t); return t and (head .. "=" .. t) or nil end
  if en.k == "r" then return head .. "=" .. b36(en.lv or 0) end
  return head
end
-- the wire text back to an entry; nil for anything a well-behaved client would not have sent, or of a map, an object or a
-- kind this client does not know
function F.Parse(text)
  if type(text) ~= "string" or #text > LIMIT then return nil end
  local k = text:sub(1, 1)
  if k == "s" then
    if not SECRET_KIND[text:sub(2, 2)] then return nil end
    local en = F.Parse(text:sub(2))
    if en then en.sec = true end
    return en
  end
  if k == "x" then
    local a, b, c, d, e, f, s = text:match("^x(%w+):(%w+),(%w+)>(%w+):(%w+),(%w+)=(%w+)$")
    if not a then return nil end
    local m, x, y = spotOf(a, b, c)
    local m2, x2, y2 = spotOf(d, e, f)
    s = unb36(s)
    if not (m and m2 and s) or s < 1 or s > 3600 then return nil end
    return { k = "x", id = 0, m = m, x = x, y = y, m2 = m2, x2 = x2, y2 = y2, s = s }
  end
  if not (k == "b" or k == "k" or k == "h" or k == "r") then return nil end
  local id, sm, sx, sy, extra = text:match("^%a(%w+)@(%w+):(%w+),(%w+)=?(.*)$")
  id = id and unb36(id)
  if not id or id < 1 or id > ID_MAX then return nil end
  local m, x, y = spotOf(sm, sx, sy)
  if not m then return nil end
  local en = { k = k, id = id, m = m, x = x, y = y }
  if k == "b" then en.t = title(extra); if not en.t then return nil end end
  -- (a rare's level, 0 where its plate gave none: a skull's "??")
  if k == "r" then
    local lv = unb36(extra or "")
    if not lv or lv < 0 or lv > 99 then return nil end
    en.lv = lv > 0 and lv or nil
  end
  return en
end

----------------------------------------------------------------------------
-- the engine (Cute_Quest's Bridge attaches it): what QuestBank's data has, the footers' counts, its map drawn again,
-- the Finds list opened
----------------------------------------------------------------------------
function D.Attach(engine)
  F.engine = type(engine) == "table" and engine or nil
  -- (a find a release or the uploader's data file carries now is the data's: dropped here)
  F:Prune()
  F:Bump()
end
local function dataHas(en)
  local E = F.engine
  if not (E and type(E.Known) == "function") or en.k == "x" or en.k == "r" then return false end
  local ok, yes = pcall(E.Known, en.m, en.k, en.id, en.t)
  return ok and yes == true
end
function F:Prune()
  local s = store()
  if not (s and self.engine) then return 0 end
  local n = 0
  for i = #s.list, 1, -1 do
    local e = s.list[i]
    if type(e) ~= "table" or type(e.v) ~= "table" or dataHas(e) then table.remove(s.list, i); n = n + 1 end
  end
  if n > 0 then index = nil end
  return n
end
-- (the map and the windows drawn again, once a second at most)
function F:Bump()
  self.ver = self.ver + 1
  if self.redrawDue then return end
  self.redrawDue = true
  C_Timer.After(1, C.Safe(function()
    F.redrawDue = false
    local E = F.engine
    if E and type(E.Changed) == "function" then pcall(E.Changed) end
    if C.UI and C.UI.RefreshAll then C.UI.RefreshAll() end
  end, "finds: drawn again"))
end
function F.Tally()
  local E = F.engine
  if not (E and type(E.Tally) == "function") then return 0, 0 end
  local ok, new, sure2 = pcall(E.Tally)
  return (ok and tonumber(new)) or 0, (ok and tonumber(sure2)) or 0
end
function F.ShowFinds()
  local E = F.engine
  if E and type(E.ShowFinds) == "function" then E.ShowFinds() end
end

-- the finds on map m the guild shared, as the engine draws them (QuestBank's Finds.lua GuildRows): those a guild mate
-- saw (one alone, dim) or the officers' word says, and the pings; built once a version for every map
local rowsVer, rowsByMap, rowsMaps = nil, {}, {}
local function build()
  local ver = verNow()
  if rowsVer == ver then return end
  rowsVer, rowsByMap, rowsMaps = ver, {}, {}
  local s = store()
  local function add(m, row)
    local list = rowsByMap[m]
    if not list then list = {}; rowsByMap[m] = list; rowsMaps[#rowsMaps + 1] = m end
    list[#list + 1] = row
  end
  for _, e in ipairs(s and s.list or {}) do
    if e.k ~= "x" then
      local n, others, mine = tally(e)
      local o = said(e)
      -- (a secret step: once two guild mates found it, the officers' word says so, or it is yours too; never dim)
      if (others > 0 or o) and not (e.sec and not (o or mine or others >= 2)) then
        add(e.m, { kind = e.k, id = e.id, x = e.x, y = e.y, name = titleOf(e), mates = others, sure = (o or n >= 2) or nil })
      end
    end
  end
  local t = clock()
  for _, p in pairs(F.pings) do
    if t - p.at < PING_LIFE then add(p.m, { kind = "r", id = p.id, x = p.x, y = p.y, level = p.lv, mates = 1, ping = p.at }) end
  end
  table.sort(rowsMaps)
end
function D.Rows(m) build(); return rowsByMap[m] or {} end
function D.Maps() build(); return rowsMaps end

----------------------------------------------------------------------------
-- yours: told by the engine as you note it (QuestBank's Finds.lua tells its host), counted for Statistics, kept as one
-- voice and queued for the guild
----------------------------------------------------------------------------
local function shareOn() return C.Settings().shareFinds ~= false end
F.ShareOn = shareOn
-- this character's counts: each find once (a chest and a book by object and spot, a rare by creature), in
-- CuteDB.chars[me].finds, SEEN_MAX at most
local STAT = { b = "books_read", r = "rares_seen", h = "chests_looted" }
local function counted(key)
  local ch = C.Char()
  if type(ch.finds) ~= "table" then ch.finds = { n = 0 } end
  local seen = ch.finds
  if seen[key] or (tonumber(seen.n) or 0) >= SEEN_MAX then return true end
  seen[key], seen.n = true, (tonumber(seen.n) or 0) + 1
  return false
end
local function cell(en) return math.floor(en.x / NEAR) .. "," .. math.floor(en.y / NEAR) end
local function bump(id) if C.Sample and C.Sample.Bump then C.Sample:Bump(id) end end
-- the entry the engine tells: kind, id, map, x, y in thousandths, extra (a book's title, a rare's level, a crossing's far
-- end { m, x, y, secs }), whether QuestBank's data has it, and whether it is a secret chain's next step
local function entryOf(kind, id, m, x, y, extra)
  id, m, x, y = tonumber(id), tonumber(m), tonumber(x), tonumber(y)
  if not (m and x and y and id) or m < 1 or m > MAP_MAX or x < 0 or x > 1000 or y < 0 or y > 1000 then return nil end
  x, y = math.floor(x + 0.5), math.floor(y + 0.5)
  if kind == "x" then
    local far = type(extra) == "table" and extra or {}
    local m2, x2, y2, s = tonumber(far.m), tonumber(far.x), tonumber(far.y), tonumber(far.secs)
    if not (m2 and x2 and y2 and s) or m2 < 1 or m2 > MAP_MAX or x2 < 0 or x2 > 1000 or y2 < 0 or y2 > 1000 then return nil end
    return { k = "x", id = 0, m = m, x = x, y = y, m2 = m2, x2 = math.floor(x2 + 0.5), y2 = math.floor(y2 + 0.5), s = math.max(1, math.min(3600, math.floor(s + 0.5))) }
  end
  if not (kind == "b" or kind == "k" or kind == "h" or kind == "r") or id < 1 or id > ID_MAX then return nil end
  local en = { k = kind, id = id, m = m, x = x, y = y }
  if kind == "b" then en.t = title(extra); if not en.t then return nil end end
  if kind == "r" then local lv = tonumber(extra); en.lv = (lv and lv >= 1 and lv <= 99) and math.floor(lv) or nil end
  return en
end
F.EntryOf = entryOf
function D.Noted(kind, id, m, x, y, extra, data, secret)
  C.Safe(function() F:Noted(kind, id, m, x, y, extra, data, secret) end, "finds: noted")()
end
function F:Noted(kind, id, m, x, y, extra, data, secret)
  local en = entryOf(kind, id, m, x, y, extra)
  if not en or not C.loaded then return end
  if secret == true and SECRET_KIND[en.k] then en.sec = true end
  -- (Statistics: every one, the data's too)
  if STAT[en.k] then
    local key = en.k == "r" and ("r" .. en.id) or (en.k .. en.id .. "@" .. en.m .. ":" .. cell(en))
    if not counted(key) then bump(STAT[en.k]) end
  end
  if en.k == "r" then return self:Ping(en) end
  if data == true or dataHas(en) then return end
  local s, me = store(), C.MyGUID()
  if not (s and me) then return end
  -- first in the guild: no guild mate's voice for it yet, nor the officers' word
  local had, others = match(s, en), 0
  if had then local _, o = tally(had); others = o end
  local first = not (had and (others > 0 or said(had)))
  -- (sharing off: your find is no voice, so nothing of where you stood goes out in an officer's word either)
  local e = shareOn() and F.Voice(me, en) or had
  if first and not counted("F" .. groupOf(en) .. ":" .. cell(en)) then bump("finds_first") end
  self:Bump()
  -- the guild's: unless sharing is off, or two others agree on it already
  if not shareOn() or (e and said(e)) then return end
  if e then local _, o2 = tally(e); if o2 >= 2 then return end end
  self:Queue(en)
end
-- a rare up now: a ping, one a creature in PING_EVERY
function F:Ping(en)
  local t = now()
  local last = self.pinged[en.id]
  if last and t - last < PING_EVERY then return end
  self.pinged[en.id] = t
  if not shareOn() then return end
  en.at = clock()
  self.outPings[en.id] = en
  self:FlushSoon(2)
end

----------------------------------------------------------------------------
-- going out: batched in Comm's queue at the pace above
----------------------------------------------------------------------------
-- the finds waiting, kept across a /reload and a relog (CuteDB.chars[me].findsOut; the pings never)
local function outList()
  local ch = C.Char()
  if type(ch.findsOut) ~= "table" then ch.findsOut = {} end
  return ch.findsOut
end
function F:Queue(en)
  local out = outList()
  for _, x in ipairs(out) do
    if groupOf(x) == groupOf(en) and d2(x.x, x.y, en.x, en.y) <= NEAR * NEAR then return end
  end
  out[#out + 1] = en
  while #out > OUT_MAX do table.remove(out, 1) end
  self:FlushSoon(2)
end
function F:FlushSoon(delay)
  if self.flushDue then return end
  self.flushDue = true
  C_Timer.After(math.max(1, delay or 2), C.Safe(function() F.flushDue = false; F:Flush() end, "finds: send"))
end
-- seconds until the next message may go, or nil and why where none can for now
function F:Wait()
  local M = C.Comm
  if not shareOn() then return nil, "sharing off" end
  if not (M.started and M.hello) or M.holding or not C.Policy:Settled() then return nil, "the hello" end
  if not C.Roster:InGuild() then return nil, "no guild" end
  -- (IsInInstance, InstanceDocumentation.lua:170)
  if C.Get("IsInInstance") == true then return nil, "an instance" end
  if M:Locked() then return nil, "the lockdown" end
  -- (the officers keep Finds or Zone: whispered to the officers online, Comm.lua's mark; with none online it would go to
  -- nobody, so it waits for one)
  if C.Policy:FindsRoute() == "self" and #C.Roster:OfficerTargets() == 0 then return nil, "no officer online" end
  local t = now()
  local w = (M.helloAt or t) + FIRST - t
  if self.lastSent then w = math.max(w, self.lastSent + EVERY - t) end
  for i = #self.sentAt, 1, -1 do if t - self.sentAt[i] >= 3600 then table.remove(self.sentAt, i) end end
  if #self.sentAt >= HOUR then w = math.max(w, self.sentAt[1] + 3600 - t) end
  return math.max(0, w)
end
-- the next message: the pings first (fresh ones, the newest first), then the finds as they were noted, PER_MSG at most
-- in LIMIT bytes. Its parts route by the Finds category and by Zone as it leaves (Comm.lua)
function F.Message(pings, out)
  local parts, msg, took = {}, "1X|", { pings = {}, out = 0 }
  local function add(kv)
    if #parts >= PER_MSG or #msg + (#parts > 0 and 1 or 0) + #kv > LIMIT then return false end
    msg = msg .. (#parts > 0 and ";" or "") .. kv
    parts[#parts + 1] = { id = "gc_finds", also = "zone", key = kv, kv = kv, s = true }
    return true
  end
  for _, en in ipairs(pings) do
    local kv = F.Pack(en)
    if kv and add(kv) then took.pings[#took.pings + 1] = en end
  end
  for _, en in ipairs(out) do
    local kv = F.Pack(en)
    if kv and not add(kv) then break end
    took.out = took.out + 1
  end
  if #parts == 0 then return nil, took end
  return { msg = msg, head = "1X|", parts = parts, kind = "f" }, took
end
function F:Flush()
  local out = outList()
  local t = clock()
  local pings = {}
  for id, en in pairs(self.outPings) do if t - en.at < PING_LIFE then pings[#pings + 1] = en else self.outPings[id] = nil end end
  if #pings == 0 and #out == 0 then return end
  if not shareOn() then self.outPings = {}; for i = #out, 1, -1 do out[i] = nil end return end
  local wait, why = self:Wait()
  self.waiting = why
  if wait == nil then self:FlushSoon((why == "no guild" or why == "no officer online") and 60 or 10) return end
  if wait > 0 then self:FlushSoon(wait) return end
  table.sort(pings, function(a, b) if a.at ~= b.at then return a.at > b.at end return a.id < b.id end)
  local e, took = F.Message(pings, out)
  if not e then return end
  for _, en in ipairs(took.pings) do self.outPings[en.id] = nil end
  for _ = 1, took.out do table.remove(out, 1) end
  if C.Comm.Queue(e) then
    self.lastSent = now()
    self.sentAt[#self.sentAt + 1] = self.lastSent
    self.sent = (self.sent or 0) + 1
  end
  if #out > 0 or next(self.outPings) then self:FlushSoon(EVERY) end
end

----------------------------------------------------------------------------
-- coming in (Comm.lua's 1X): a guild mate's finds, or, whispered, a member's to an officer
----------------------------------------------------------------------------
function F:Receive(body, sender, whispered)
  if type(body) ~= "string" then return 0 end
  local R = C.Roster
  local g = R:GuidOf(sender)
  self.heard = self.heard + 1
  -- (nobody the roster lists, a member the officers marked untrusted)
  if not g or untrusted(g) then self.refused = self.refused + 1 return 0 end
  local officer = R:OfficerStill()
  -- (whispered: the officers' alone, a member's client keeps none; on GUILD while the officers keep the category, only
  -- an edited copy sends one)
  if (whispered and not officer) or (not whispered and not officer and C.Policy:FindsRoute() == "self") then self.refused = self.refused + 1 return 0 end
  -- (the sender's pace)
  local t = now()
  local r = self.rate[g]
  if not r or t - r.at >= 3600 then r = { at = t, n = 0 }; self.rate[g] = r end
  if r.n >= HEAR_HOUR then self.capped = self.capped + 1 return 0 end
  r.n = r.n + 1
  local n, becameSure, changed = 0, false, false
  for text in body:gmatch("[^;]+") do
    if n >= PER_MSG then break end
    local en = F.Parse(text)
    if not en then self.unknown = self.unknown + 1
    elseif en.k == "r" then
      n = n + 1
      if self:PingHeard(g, en) then changed = true end
    elseif not dataHas(en) then
      n = n + 1
      local _, became = F.Voice(g, en)
      changed = true
      if became then becameSure = true end
    end
  end
  self.taken = self.taken + n
  if changed then self:Bump() end
  -- (an officer's client says what became sure in the officers' word, where the officers keep Finds or Zone and the
  -- members heard no voice: WORD_AGE on, F:WordLater. Open, they heard both; the word says it to those who ask later)
  if becameSure and R:MeOfficer() and C.Policy:FindsRoute() == "self" then self:WordLater() end
  return n
end
-- a ping heard: one a creature from one sender in PING_EVERY, PINGS kept, each PING_LIFE
function F:PingHeard(g, en)
  local t = now()
  local key = g .. ":" .. en.id
  if self.pingFrom[key] and t - self.pingFrom[key] < PING_EVERY then return false end
  self.pingFrom[key] = t
  self.pings[en.id .. "@" .. en.m] = { id = en.id, m = en.m, x = en.x, y = en.y, lv = en.lv, at = clock(), by = g }
  local n = count(self.pings)
  while n > PINGS do
    local o, ok
    for k2, p in pairs(self.pings) do if not o or p.at < o then o, ok = p.at, k2 end end
    self.pings[ok] = nil
    n = n - 1
  end
  self:Expire()
  return true
end
-- the pings past PING_LIFE go, looked at each minute while any shows
function F:Expire()
  if self.expireDue then return end
  self.expireDue = true
  C_Timer.After(60, C.Safe(function()
    F.expireDue = false
    local t, gone = clock(), false
    for k2, p in pairs(F.pings) do if t - p.at >= PING_LIFE then F.pings[k2] = nil; gone = true end end
    if gone then F:Bump() end
    if next(F.pings) then F:Expire() end
  end, "finds: pings"))
end

----------------------------------------------------------------------------
-- the officers' word (Comm.lua adds these to Rules.lua's parts): an officer's client says the guild's sure finds, the
-- newest WORD_MAX, no GUID and no count: f<kind><object>@<map>:<x>,<y>=<title or 1>, fx<map>:<x>,<y>><map>:<x>,<y>=<s>
----------------------------------------------------------------------------
-- (its place as it became sure: a voice moving the mean since changes no key, so the word stays the same)
local function wordKey(e)
  if e.k == "x" then return "fx" .. spotText(e.m, e.wx or e.x, e.wy or e.y) .. ">" .. spotText(e.m2, e.wx2 or e.x2, e.wy2 or e.y2) end
  return "f" .. e.k .. b36(e.id) .. "@" .. spotText(e.m, e.wx or e.x, e.wy or e.y)
end
-- a part of the word that is a find's (Comm.lua: one leaving the word takes nothing back, and a word that changed in its
-- finds alone waits longer); Rules.lua's parts start n, x, d or b
function F.WordPart(kv) return type(kv) == "string" and kv:sub(1, 1) == "f" end
-- an old enough find: sure for WORD_AGE where the officers keep Finds or Zone
local function aged(e, closed, t) return not closed or not e.st or t - e.st >= WORD_AGE end
function F:WordParts()
  local s = store()
  if not s then return {} end
  local list = {}
  local closed, t = C.Policy:FindsRoute() == "self", C.ServerNow()
  -- (what this client's voices prove: another officer's word may have said it too, and this one says it all the same,
  -- for the members who ask while that officer is away)
  local noMe = not shareOn()
  for _, e in ipairs(s.list) do
    -- (a book whose title no two voices gave alike is not said: titleOf)
    if (tally(e, noMe)) >= 2 and aged(e, closed, t) and (e.k ~= "b" or titleOf(e)) then
      list[#list + 1] = e
      if not e.wx then e.wx, e.wy, e.wx2, e.wy2 = e.x, e.y, e.x2, e.y2 end
    end
  end
  table.sort(list, function(a, b) return (a.sa or 0) > (b.sa or 0) end)
  local out = {}
  for i = 1, math.min(WORD_MAX, #list) do
    local e = list[i]
    local v = (e.k == "b" and title(titleOf(e))) or (e.k == "x" and b36(e.s or 1)) or "1"
    out[#out + 1] = wordKey(e) .. "=" .. v
  end
  table.sort(out)
  return out
end
-- the word once the youngest sure find waiting for it is WORD_AGE old (one look then, and again for the next)
function F:WordLater()
  if self.wordLaterDue then return end
  local s, t = store(), C.ServerNow()
  local soon
  for _, e in ipairs(s and s.list or {}) do
    if e.st and t - e.st < WORD_AGE and (tally(e)) >= 2 then
      local d = e.st + WORD_AGE - t
      if not soon or d < soon then soon = d end
    end
  end
  if not soon then return end
  self.wordLaterDue = true
  C_Timer.After(math.max(1, soon) + 5, C.Safe(function()
    F.wordLaterDue = false
    if C.Roster:MeOfficer() and C.Comm.WordSoon then C.Comm:WordSoon() end
    F:WordLater()
  end, "finds: the officers' word"))
end
-- a word part back to an entry, or nil
local function wordEntry(key, v)
  if type(key) ~= "string" or key:sub(1, 1) ~= "f" then return nil end
  local k = key:sub(2, 2)
  if k == "x" then return F.Parse(key:sub(2) .. "=" .. tostring(v)) end
  if k == "b" then return F.Parse(key:sub(2) .. "=" .. tostring(v)) end
  if k == "k" or k == "h" then return F.Parse(key:sub(2)) end
  return nil
end
F.WordEntry = wordEntry
-- an officer's word came (Comm.lua, after Rules.lua took it): its finds are sure, a second later, once for a burst
function F:WordCame()
  if self.wordDue then return end
  self.wordDue = true
  C_Timer.After(1, C.Safe(function() F.wordDue = false; F:TakeWord() end, "finds: the officers' word"))
end
-- (quiet: from F:Voters, which moves the version itself)
function F:TakeWord(quiet)
  local k, s = C.Stats.Known(), store()
  if not (k and s and type(k.word) == "table") then return 0 end
  local n = 0
  for sender, w in pairs(k.word) do
    if type(w) == "table" and type(w.parts) == "table" and C.Roster:OfficerVoice(sender) then
      for key, v in pairs(w.parts) do
        local en = wordEntry(key, v)
        if en and not dataHas(en) then
          local e = match(s, en)
          if not e then e = make(s, en, nil); s.n = s.n + 1; e.at = s.n end
          if not said(e) then e.o, n = sender, n + 1; e.sa = e.sa or s.n end
          if en.t then e.wt = en.t end
          e.t = titleOf(e)
        end
      end
    end
  end
  if n > 0 and not quiet then self:Bump() end
  return n
end

----------------------------------------------------------------------------
-- the purge (Policy.lua P:Purge, on a member's client while the officers keep Finds or Zone): every other member's
-- voice goes, and the pings; a find left with none, and not the officers' word, goes with them. The number taken out
----------------------------------------------------------------------------
function F.StripTraces(only)
  local s = store()
  if not s then return 0 end
  local me, n = C.MyGUID(), 0
  for i = #s.list, 1, -1 do
    local e = s.list[i]
    if type(e) == "table" and type(e.v) == "table" then
      for g in pairs(e.v) do
        if g ~= me and g ~= "me" and (only == nil or only(g)) then
          e.v[g] = nil; n = n + 1
          if type(e.tv) == "table" then e.tv[g] = nil end
        end
      end
      e.t = titleOf(e)
      if next(e.v) == nil and not e.o then table.remove(s.list, i) else remean(e) end
    end
  end
  if next(F.pings) then F.pings = {}; n = n + 1 end
  if n > 0 then index = nil; F:Bump() end
  return n
end

----------------------------------------------------------------------------
-- Settings > Data you share (Cute_Quest's section draws these): the line, while there is something to say, and the row
----------------------------------------------------------------------------
-- (the line in the L and M footers' words, D.FooterText: under Cute the engine's data is no QuestBank's)
function D.ShareLine(col)
  local new, sure2 = F.Tally()
  if new <= 0 then return end
  col:Note(D.FooterText(new, sure2))
  -- (Show finds while the Map window is there to show them: the Map module on, and no QuestBank loaded beside Cute)
  if not C.Modules.Page("map") then return end
  col:Buttons({ { "Show finds", true, function() F.ShowFinds() end, function(tip)
    tip:AddLine("Show finds", 1, 1, 1)
    tip:AddLine("The Map window's Finds list: yours, the guild's once two agree, and what players' games and guides gave foreverrank.com.", 0.85, 0.85, 0.85, true)
  end } })
end
function D.ShareRow(col)
  col:Check("Share finds with the guild", shareOn(), true, function(on)
    C.Settings().shareFinds = on and true or false
    if not on then F.outPings = {}; local out = outList(); for i = #out, 1, -1 do out[i] = nil end end
    if C.SettingsPage and C.SettingsPage.Redraw then C.SettingsPage.Redraw() end
  end, nil, function(tip)
    tip:AddLine("Share finds with the guild", 1, 1, 1)
    tip:AddLine("What you find in the world, by where you stood, to your guild in game. The officers' Who sees what decides who sees it.", 0.85, 0.85, 0.85, true)
  end)
  col:Note("A guild mate's find counts once two of you agree; one alone shows dim on the map.")
end
-- the footers' words (L and M, Cute_Quest's): "14 new finds, a dot, 3 confirmed by the guild", the numbers in INK
function D.FooterText(new, sure2, inkHex)
  local ink = inkHex or ""
  local close = inkHex and "|r" or ""
  return ink .. new .. close .. (new == 1 and " new find" or " new finds") .. C.UI.Look.DOT .. ink .. sure2 .. close .. " confirmed by the guild"
end
D.PRIVACY = "Cute shares what you find with your guild in game; the optional uploader sends only what you found in the world (quests, NPCs, places, drops), never a name or anything about your guild."

----------------------------------------------------------------------------
-- /cute diag: the store, the pings and the pace, counted (never a name)
----------------------------------------------------------------------------
function F:Report()
  local s = store()
  local all, sure2, lone, word, cross = 0, 0, 0, 0, 0
  for _, e in ipairs(s and s.list or {}) do
    all = all + 1
    if said(e) then word = word + 1 end
    if sure(e) then sure2 = sure2 + 1 elseif count(e.v) == 1 then lone = lone + 1 end
    if e.k == "x" then cross = cross + 1 end
  end
  local now2 = now()
  local hour = 0
  for _, t in ipairs(self.sentAt) do if now2 - t < 3600 then hour = hour + 1 end end
  local out = C.loaded and #outList() or 0
  return string.format("finds: kept %d (sure %d, one voice %d, the officers' %d, crossings %d) | pings %d | yours waiting %d%s, sent %d this hour | heard %d, taken %d, refused %d, past the caps %d, unread %d | %s | engine %s",
    all, sure2, lone, word, cross, count(self.pings), out + count(self.outPings), self.waiting and (" (" .. self.waiting .. ")") or "", hour,
    self.heard, self.taken, self.refused, self.capped, self.unknown, shareOn() and "sharing on" or "sharing off", self.engine and "attached" or "none")
end
do
  local diag = C.Diag
  if diag then
    C.Diag = function()
      local lines = diag()
      local ok, line = pcall(F.Report, F)
      lines[#lines + 1] = "diag " .. (ok and line or ("finds: " .. tostring(line)))
      return lines
    end
  end
end

-- at every loading screen: what waited goes when it may (a relog's queue; an instance left), and an officer's word
-- waiting for a find's half hour has its look again (F:WordLater: the timer a /reload or a relog lost)
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", C.Safe(function()
  if not C.loaded then return end
  if #outList() > 0 or next(F.outPings) then F:FlushSoon(5) end
  F:WordLater()
end, "finds: start"))
