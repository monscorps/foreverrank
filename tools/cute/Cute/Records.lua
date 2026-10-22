-- SPDX-License-Identifier: GPL-3.0-or-later
-- Records: the run report's design, section 11 (with 5.3, 9.1, 9.6, 10, 12, 13.2 and 14). A built-in module, on by
-- default, which a member may switch off for themselves (Settings > Modules: no table, no Records chip, no record toast)
-- and the officers for the whole guild (its own section: a switch that travels with the officers' rules, as
-- Achievements' does).
--   Registry the core's, whatever module is on: Fastest clears, a discovered category (code cc, as S.FOUND's), whose
--            stats are c<instanceID>, seconds from the run's start to its last kill, routed the strictest of cc and
--            the instance's own i<instanceID>; defined from your own full clear (Runs.lua), from a member's value as it
--            comes (Comm.lua, before the roster takes it) and from the values saved, at login. S.IsDynamic takes c
--            beside g e f i k. Which stats hold a record: the def's record ("max" or "min") and recordIn (in one
--            "run", in a "week", "all" time, a "clear"); every game statistic once an officer adds it
--   Table    every client's own, CuteDB.halls[club].records: per stat (per instance for a clear, per statistic added)
--            the value, the holder's GUID, name and class, when, and for a clear the mates within its five seconds;
--            400 entries at most. Records:Seen runs on every value the roster takes (Comm.lua, after it) and on your
--            own (Sample.lua S:OnValue). Only values routed Everyone, from a guild member the officers have not marked
--            untrusted, within the stat's bounds; a policy that closes a stat, or a holder marked untrusted, takes its
--            entry out
--   Falls    a higher value for "most", a lower one for "fastest". A fastest clear needs two voices: two members'
--            values within five seconds (everyone in a run sets the same time); the record is the larger of the
--            fastest agreeing pair, so no one voice lowers it, its holder the member it is (ties to the smaller GUID).
--            Live only: a delta (1D) 90 s into a login,
--            or your own value changing; a full record (1F) and what changed while you were away update it quietly
--   On       every record ships off. The officers' list, CuteDB.halls[club].recOn, travels as 1O|<at>|<code>.<code>...
--            (the stat's code, a statistic by its id, cc for every fastest clear), taken only from a sender
--            R:OfficerVoice passes, newest wins, a change sent at once and one a minute at most; an officer answering a
--            1G whose records stamp is older sends it (Halls.lua). Turning a record on fills it with today's best
--            silently
--   Shown    a fastest clear that is on, beaten by 5% or more by voices that came live together (one group's, within
--            30 minutes of each other) all within the instance's level range (Rules.lua rule 3; none known, none
--            shown) and not by its own holder, is a NEW RECORD on every client: a set of one
--            card kept in News and toasted (Halls.lua: once a day an instance, within the toasts' limits); nothing is
--            sent, every client decides alone. Any other record that is on, taken by another member live, is a
--            "Record?" row in each officer's own Queue, published by an officer or not at all. A record that is off
--            changes quietly on the Records chip
--   The chip J > Halls > Records: grouped In one run, In a week, All time, Fastest clears; the holder, the value, the
--            day; for officers each row's switch and Preview (the card its holder would get now), the Fastest clears
--            heading's switch for every instance, and Add (the stat picker) for a game statistic
-- Nothing of a member's in /cute diag cards: counts and states.
local _, C = ...
local Rec = { announced = 0, quiet = 0, suggested = 0, sent = 0, taken = 0, refused = 0, defs = 0, heardAt = 0, lone = 0, apart = 0 }
C.Records = Rec

local MAX = 400             -- entries in the table at most
local GAP = 5               -- two voices within this many seconds back a fastest clear
local BETTER = 0.95         -- a fastest clear is shown where it is 5% faster or more
local LIVE_AFTER = 90       -- seconds into a login before a delta is live
local SEND_GAP = 60         -- 1O: one message a minute at most
local CLEARS_CHANNEL = 300  -- clear stats defined from the channel in a session at most (your own always are)
local CLEARS_SENDER = 60    -- and from one member (a session's and the saved roster's at login), well past the instances
local CODES_MAX, LIMIT = 60, 255
local CLEAR_LO, CLEAR_HI = 120, 6 * 3600
local TOGETHER = 1800       -- a NEW RECORD's voices came live within this many seconds of its holder's (one group's)
local DOT = " \194\183 " -- (a middle dot in Windows-1252; the file stays ASCII)
local WHITE, INK, DIM, MUTE = { 0.96, 0.96, 0.96 }, { 0.86, 0.86, 0.86 }, { 0.58, 0.58, 0.58 }, { 0.52, 0.52, 0.52 }
local TROPHY = 311945 -- INV_Misc_Trophy_Argent

local function now() return C.ServerNow() end
local function gtime() return (GetTime and GetTime()) or 0 end
local function callable(name) return type(_G[name]) == "function" end
local function call(name, ...) if not callable(name) then return nil end return C.Get(_G[name], ...) end
local function sfxOf(g) return type(g) == "string" and g:match("([^%-]+)$") or nil end
local function H() return C.Halls end
local function officer() return C.Roster and C.Roster:MeOfficer() or false end
local function color(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end
local function clock(v) return C.Awards and C.Awards.Clock(v) or tostring(v) end

----------------------------------------------------------------------------
-- the registry (core: every client knows the code, routes by it and decodes a clear, the module on or off)
----------------------------------------------------------------------------
-- the stats that hold a record, and where (10): the lifetime counts and the weeks the halls read. The run stats and
-- the personal bests say so where Runs.lua defines them; a statistic and a clear by their prefix
local RECORDS = { deaths = "all", bosses = "all", quests_done = "all", dungeons = "all", raids = "all", jumps = "all", where = "all", fish = "all",
  ghost_yards = "all", gold_earned = "all", deaths_week = "week", quests_week = "week" }
-- the order the chip lists them in, within each group
Rec.ORDER = { "pb_ints", "pb_dispels", "pb_deaths", "runs_week", "honors_week", "roasts_week", "deaths_week", "quests_week", "runs", "honors", "roasts",
  "deaths", "bosses", "quests_done", "dungeons", "raids", "jumps", "where", "fish", "ghost_yards", "gold_earned" }
do
  local S = C.Stats
  for id, within in pairs(RECORDS) do
    local d = S.byId[id]
    if d then d.record, d.recordIn = "max", within end
  end
  -- Fastest clears: a discovered category of its own, its code for life (as S.FOUND's)
  assert(not S.byCode.cc, "the Fastest clears code")
  S.FOUND[#S.FOUND + 1] = { "clears", "Fastest clears", "cc" }
  S.byCode.cc = "gc_clears"
  -- (a clear is an id the wire carries as a bare int whether or not this client defined it, as a boss or an instance)
  local dynamic = S.IsDynamic
  function S.IsDynamic(id) return dynamic(id) or (type(id) == "string" and id:match("^c%d+$") ~= nil and #id <= 12) end
  -- (and one this client has not defined routes as a defined one would: the strictest of Fastest clears and its
  -- instance, as Policy.lua P:Route takes an instance of no known kind; the core's own fall-through sends an id it does
  -- not know to everyone)
  local P = C.Policy
  local route = P.Route
  function P:Route(id)
    if type(id) == "string" and id:byte(1) == 99 and not S.byId[id] then
      local n = id:match("^c(%d+)$")
      if n then return (route(self, "gc_clears") == "self" or route(self, "i" .. n) == "self") and "self" or "all" end
    end
    return route(self, id)
  end
  -- the officers' switch for the whole guild: a rule, 1 on and 0 off, as Achievements' (Achievements.lua): sent and
  -- taken with the policy's rules by its entry in TUNE_BY and LOWER, left out of R.TUNE (a switch, drawn in this
  -- module's own section)
  local R = C.Rules
  R.RULES.recGuild = 1
  local t = { "recGuild", "Records for the guild", 0, 1, 1, nil, "Off: no member's Cute keeps or announces records.", "records" }
  R.TUNE_BY.recGuild, R.LOWER.recguild = t, "recGuild"
end

-- a record's kind ("max" or "min") and where it is held ("run", "week", "all", "clear"); nil for a stat that holds none
function Rec.Kind(id)
  if type(id) ~= "string" then return nil end
  local def = C.Stats.byId[id]
  if def and def.record then return def.record, def.recordIn or "all" end
  if id:match("^c%d+$") then return "min", "clear" end
  if id:match("^g%d+$") then return "max", "all" end
  return nil
end
-- the code a record goes by in 1O: the stat's, a statistic's id, cc for every fastest clear
function Rec.Code(id)
  if type(id) ~= "string" then return nil end
  if id:match("^c%d+$") then return "cc" end
  if id:match("^g%d+$") then return id end
  local def = C.Stats.byId[id]
  return def and def.record and def.code or nil
end

-- an instance's name: the label the guild knows it by (Stats.lua S.LabelOf), else the client's for that map
-- (GetRealZoneText takes a map id: ZoneScriptDocumentation.lua:28, as GuildNews.lua:195 calls it)
function Rec.Place(n)
  local name = C.Stats.LabelOf and C.Stats.LabelOf("i" .. n) or nil
  if type(name) ~= "string" or name == "" then name = call("GetRealZoneText", n) end
  if type(name) ~= "string" or name == "" then name = "An instance" end
  return name
end
-- what a clear reveals: its instance, where this client has its stat, and the category of its kind, Dungeons and Raids
-- both where the kind is not sure here, as Policy.lua P:Route routes such an instance
local KIND_CAT = { party = "gc_dungeons", raid = "gc_raids" }
local function clearReveals(n)
  local out = {}
  if C.Stats.byId["i" .. n] then out[1] = "i" .. n end
  local kind, sure = C.Stats.KindOf(n)
  local cat = sure and KIND_CAT[kind or ""]
  if cat then out[#out + 1] = cat else out[#out + 1] = "gc_dungeons"; out[#out + 1] = "gc_raids" end
  return out
end
-- a clear's stat, defined once: own (your own full clear, or your saved one) always; from a member (by), CLEARS_SENDER
-- from that member and, from the channel this session (not saved), CLEARS_CHANNEL in all: one member's made-up clears
-- spend their own share, not the guild's
Rec.channelDefs, Rec.defsBy = 0, {}
function Rec.ClearDef(n, own, by, saved)
  if type(n) ~= "number" or n ~= n or n < 0 or n >= 2 ^ 31 or n ~= math.floor(n) then return nil end
  local S = C.Stats
  local id = "c" .. n
  local def = S.byId[id]
  if def then
    if def.learned == "clears" then def.reveals = clearReveals(n) end
    return def
  end
  if not own then
    local k = by or "?"
    if (Rec.defsBy[k] or 0) >= CLEARS_SENDER or (not saved and Rec.channelDefs >= CLEARS_CHANNEL) then return nil end
    Rec.defsBy[k] = (Rec.defsBy[k] or 0) + 1
    if not saved then Rec.channelDefs = Rec.channelDefs + 1 end
  end
  def = S.def(id, "Fastest clear: " .. Rec.Place(n), "found", { learned = "clears", num = n, track = true, slow = true, lo = CLEAR_LO, hi = CLEAR_HI,
    record = "min", recordIn = "clear", reveals = clearReveals(n), fmt = clock, default = "all",
    hint = "this character's fastest full clear: from the run's start to its last boss" })
  Rec.defs = Rec.defs + 1
  S.foundVersion = (S.foundVersion or 0) + 1
  return def
end
-- your own full clear (Runs.lua, at a run's end): kept where it is faster than the one you had
function Rec.OwnClear(n, secs)
  if type(secs) ~= "number" or secs < CLEAR_LO or secs > CLEAR_HI then return false end
  local def = Rec.ClearDef(n, true)
  if not def then return false end
  secs = math.floor(secs)
  local had = C.Sample:Counter(def.id)
  if had > 0 and had <= secs then return false end
  C.Sample:Set(def.id, secs)
  return true
end
-- the clears saved define their stats again at login, before Sample loads your own values (Stats.lua S.LoadKnown runs
-- just before): yours from your counters, the members' from the records held
do
  local S = C.Stats
  local load = S.LoadKnown
  function S.LoadKnown(...)
    load(...)
    C.Safe(function()
      for id in pairs(C.Char().counters or {}) do
        local n = type(id) == "string" and tonumber(id:match("^c(%d+)$"))
        if n then Rec.ClearDef(n, true) end
      end
      for key, e in pairs(CuteDB.roster or {}) do
        for id in pairs(type(e) == "table" and type(e.stats) == "table" and e.stats or {}) do
          local n = type(id) == "string" and tonumber(id:match("^c(%d+)$"))
          if n then Rec.ClearDef(n, false, key, true) end
        end
      end
    end, "records: the clears saved")()
  end
end

----------------------------------------------------------------------------
-- on and off
----------------------------------------------------------------------------
local function moduleOn() local def = C.Modules.byId.records; return def ~= nil and def.active == true end
function Rec.GuildOn() return C.Rules.Get("recGuild") ~= 0 end
-- this client keeps the table and shows records: the module on, the guild's switch on, in a guild
function Rec.Active() return moduleOn() and Rec.GuildOn() and C.Roster ~= nil and C.Roster:InGuild() end

-- the records the officers turned on (11.1): { at, codes = { [code] = true }, by }
function Rec.List()
  local d = H().DB()
  if type(d.recOn) ~= "table" then d.recOn = { at = 0, codes = {} } end
  if type(d.recOn.codes) ~= "table" then d.recOn.codes = {} end
  return d.recOn
end
function Rec.Stamp() return tonumber(Rec.List().at) or 0 end
function Rec.IsOn(id) local code = Rec.Code(id); return code ~= nil and Rec.List().codes[code] == true end

----------------------------------------------------------------------------
-- the table
----------------------------------------------------------------------------
-- a member who may hold a record: you, or a guild member by the roster; never one the officers marked untrusted
local function holder(g)
  if type(g) ~= "string" or C.Policy:Untrusted(g) then return nil end
  if g == C.MyGUID() then
    local _, class = call("UnitClass", "player")
    return { name = C.Roster:MyDisplay(), class = class, level = C.Sample:Value("level") or call("UnitLevel", "player") }
  end
  local m = C.Roster.byGuid and C.Roster.byGuid[g]
  if not m then return nil end
  return { name = (m.name and C.Short(m.name)) or "?", class = m.class, level = m.level }
end
-- the entries, each stat's: what the policy closes since, or a holder marked untrusted since, is taken out first
-- (checked again only when the policy changed: P.ver; one held past what the time allows, Rec.Ceiling, as saved by 0.9,
-- goes then too)
local purgedAt
function Rec.Entries()
  local d = H().DB()
  if type(d.records) ~= "table" then d.records = {} end
  local E = d.records
  local P = C.Policy
  if purgedAt ~= P.ver then
    purgedAt = P.ver
    for id, e in pairs(E) do
      if type(e) ~= "table" or type(e.v) ~= "number" or P:Route(id) ~= "all" or P:Untrusted(e.g) or e.v > Rec.Ceiling(id) then E[id] = nil end
    end
  end
  return E
end
local function count(E) local n = 0; for _ in pairs(E) do n = n + 1 end return n end
-- (The launch audit) a "most" record rests on one member's Cute (11.1), and the stats' own bounds let a count be 2^31:
-- an edited copy's 2^31 jumps held the Records chip on every member's screen for good, as no honest value could pass
-- it. A value past what the time since Cute began counting allows holds none: Cute's own counts began with 0.1.0 on 18
-- October 2026, each at most its rate a day since then, a day at least (a death, its release and the run back take 40 s
-- at the least, a new instance 10 minutes, a jump a second, a fish a 4 s cast, a quest handed in 10 s, a ghost runs 9
-- yards a second; 10000 gold a day, a run report each run); a week's count its rate for seven days; what the game
-- counts (quests done, the different bosses killed) far past what the game holds. A copy within them still holds a
-- record until the officers mark it untrusted (Rec.Entries drops it)
local SINCE = 1792281600 -- 18 October 2026, 00:00 UTC: no Cute counted anything before
local PER_DAY = { deaths = 2000, dungeons = 150, raids = 150, jumps = 86400, where = 5000, fish = 20000, ghost_yards = 1000000,
  gold_earned = 100000000, runs = 150, honors = 150, roasts = 150 }
local PER_WEEK = { deaths_week = 7 * 2000, quests_week = 7 * 10000, runs_week = 7 * 150, honors_week = 7 * 150, roasts_week = 7 * 150 }
local AT_MOST = { quests_done = 50000, bosses = 5000 }
function Rec.Ceiling(id)
  local d = PER_DAY[id]
  if d then return d * math.max(1, math.ceil((now() - SINCE) / 86400)) end
  return PER_WEEK[id] or AT_MOST[id] or math.huge
end
-- a value counts toward a record: the stat routed Everyone, a member who may hold one, within the stat's bounds and
-- what the time allows, more than nothing for a "most"
local function counts(id, kind, g, v)
  if type(v) ~= "number" or v ~= v then return nil end
  if kind == "max" and (v <= 0 or v > Rec.Ceiling(id)) then return nil end
  if C.Policy:Route(id) ~= "all" then return nil end
  if C.Stats.Implausible(id, v) then return nil end
  return holder(g)
end
local function better(kind, v, old) if kind == "min" then return v < old end return v > old end
local function changed() local Hl = H(); if Hl and Hl.Refresh then Hl.Refresh() end end

-- a value seen (11.2): a member's as the roster took it, or your own. live: a delta 90 s into a login, or your own
-- value changing
function Rec:Seen(id, g, v, live, from)
  if not Rec.Active() then return end
  local kind, within = Rec.Kind(id)
  if not kind then return end
  if within == "clear" then return self:Clear(tonumber(id:sub(2)), live) end
  -- (a statistic is kept once an officer added it)
  local E = Rec.Entries()
  if id:sub(1, 1) == "g" and not (Rec.IsOn(id) or E[id]) then return end
  local who = counts(id, kind, g, v)
  if not who then return end
  local e = E[id]
  if e and not better(kind, v, e.v) then return end
  if not e and count(E) >= MAX then return end
  local prev = e and e.g
  E[id] = { v = v, g = g, n = who.name, c = who.class, t = math.floor(now()) }
  -- (another member's value taking a record that is on: the officers' "Record?" row; one member's Cute alone makes no
  -- guild-wide claim, so it is the officers' to publish)
  if prev and prev ~= g and live and Rec.IsOn(id) then self:Suggest(id, E[id], from)
  else Rec.quiet = Rec.quiet + 1 end
  changed()
end

-- when a clear's value came live from a member this session (Rec.came[id][guid], GetTime): a NEW RECORD's voices are
-- one group's where they came together
Rec.came = {}
local function came(id, g) local t = Rec.came[id]; if not t then t = {}; Rec.came[id] = t end t[g] = gtime() end
-- the voices for a clear: every member with a value for it that counts, smallest first, ties to the smaller GUID
local function voices(id)
  local out = {}
  local R = C.Roster
  for _, row in ipairs(R:Rows()) do
    local g = row.guid
    local v = row.stats and row.stats[id]
    if type(v) == "number" and type(g) == "string" and (row.me or (row.addon and R.byGuid and R.byGuid[g])) and not row.untrusted and not C.Stats.Implausible(id, v) then
      out[#out + 1] = { g = g, v = v, row = row }
    end
  end
  table.sort(out, function(a, b) if a.v ~= b.v then return a.v < b.v end return C.Comm.Before(a.g, b.g) end)
  return out
end
Rec.Voices = voices
-- the top of an instance's level range as the guild knows it (Rules.lua rule 3: learned, the seed's, the levels seen,
-- the officers'); nil where none is known
function Rec.RangeTop(n)
  local ok, m = pcall(C.Rules.Model)
  local d = ok and type(m) == "table" and m.dungeons and m.dungeons[n] or nil
  return d and type(d.max) == "number" and d.max or nil
end
-- a clear's record (11.3): the smallest time another member's backs from at or under it within five seconds, the
-- larger of the agreeing pair, so no one voice can lower it (an edited copy's a few seconds under a real clear backs
-- the real one); its holder the member with that time, ties to the smaller GUID
function Rec:Clear(n, live)
  if type(n) ~= "number" then return end
  local id = "c" .. n
  -- (its route as its instance is known now; one this client did not define, past the definitions' shares, holds no
  -- record: its bounds are unknown here)
  if not C.Stats.byId[id] then return end
  Rec.ClearDef(n)
  if C.Policy:Route(id) ~= "all" then return end
  local list = voices(id)
  local best
  for j = 2, #list do
    if list[j].v - list[j - 1].v <= GAP then
      for _, a in ipairs(list) do if a.v == list[j].v then best = a break end end
      break
    end
  end
  -- (a faster time no second voice backs: counted, so /cute diag cards says whether a group's times agree in game)
  local first = list[1]
  if first and not (list[2] and list[2].v - first.v <= GAP) then
    local had = Rec.Entries()[id]
    if not had or first.v < had.v then Rec.lone = Rec.lone + 1 end
  end
  if not best then return end
  local group = {}
  for _, b in ipairs(list) do if math.abs(b.v - best.v) <= GAP then group[#group + 1] = b end end
  local E = Rec.Entries()
  local e = E[id]
  if e and e.v <= best.v then
    -- (a third voice for the record as it stands: one more mate)
    if e.v == best.v and e.g == best.g and (e.m or 0) < #group - 1 then e.m = #group - 1; changed() end
    return
  end
  if not e and count(E) >= MAX then return end
  local who = holder(best.g)
  if not who then return end
  local prev = e
  E[id] = { v = best.v, g = best.g, n = who.name, c = who.class, t = math.floor(now()), m = #group - 1 }
  -- shown: on, live, a record before it beaten by 5% or more by another holder, every voice within the range
  local loud = live and Rec.IsOn(id) and prev ~= nil and prev.g ~= best.g and best.v <= prev.v * BETTER
  if loud then
    -- (one group's voices came live together, this session: two runs' times within five seconds of each other, hours
    -- apart, are no group's clear; the card's mates are the voices that came with it)
    local came, together = Rec.came[id] or {}, {}
    local t0 = came[best.g]
    for _, b in ipairs(group) do if t0 and came[b.g] and math.abs(came[b.g] - t0) <= TOGETHER then together[#together + 1] = b end end
    -- (counted: /cute diag cards says whether one group's voices come within the window in game)
    if #together < 2 then loud = false; Rec.apart = Rec.apart + 1 else group = together end
  end
  if loud then
    local top = Rec.RangeTop(n)
    if not top then loud = false end
    for _, b in ipairs(group) do
      local m = holder(b.g)
      if not (top and m and type(m.level) == "number" and m.level <= top) then loud = false end
    end
  end
  if loud then E[id].m = #group - 1; self:Announce(n, E[id]) else Rec.quiet = Rec.quiet + 1 end
  changed()
end

-- a record's card (the chip's Preview, a "Record?" row, a NEW RECORD): the holder, RECORD (BLOOPER for a stat of the
-- Hall of Shame), the stat's label or the instance's name, a line, the value and where it was held
Rec.WITHIN = { run = "in one run", week = "in a week", all = "all time", clear = "fastest clear" }
function Rec.Card(id, e)
  local _, within = Rec.Kind(id)
  local def = C.Stats.byId[id]
  local c = { guid = e.g, sfx = sfxOf(e.g), name = e.n or "?", class = e.c, kind = "record", valueLabel = Rec.WITHIN[within or "all"], source = "s" .. id }
  if within == "clear" then
    local n = tonumber(id:sub(2))
    local mates = tonumber(e.m) or 0
    c.title = Rec.Place(n)
    c.line = (mates > 0 and C.Policy:Route("group") == "all") and string.format("With %d guild %s.", mates, mates == 1 and "mate" or "mates") or "New guild record."
    c.value = clock(e.v)
  else
    c.kind = (def and def.cat == "funny") and "blooper" or "record"
    c.title = def and def.label or ("Statistic " .. id:sub(2))
    c.line = "New guild record."
    c.value = def and C.UI.Format(def, e.v) or tostring(e.v)
  end
  return c
end
-- a fastest clear that fell, shown (9.6): one card, NEW RECORD, in News and as a toast (Halls.lua: once a day an
-- instance, a change within the day its News row again, quietly)
function Rec:Announce(n, e)
  local id = "c" .. n
  local card = Rec.Card(id, e)
  H():KeepLocal({ kind = "r", title = "Fastest clear: " .. card.title, cards = { card } }, id)
  Rec.announced = Rec.announced + 1
end
-- another member's value takes a record that is on: a "Record?" row in this officer's Queue, the stat's own (one at a
-- time: a newer one for the stat takes the place of one not published)
function Rec:Suggest(id, e, from)
  if not (C.Roster:OfficerStill()) then return end
  local Hl = H()
  local key = "rec:" .. id .. ":"
  local stale = {}
  for _, r in ipairs(Hl.Rows()) do if type(r.id) == "string" and r.id:sub(1, #key) == key and not r.pub then stale[#stale + 1] = r.id end end
  if #stale > 0 then Hl:Unqueue(stale) end
  local card = Rec.Card(id, e)
  if Hl:Queue({ id = key .. (card.sfx or "?") .. ":" .. C.Comm.b36(math.floor(e.v)), src = "record", from = from or "me", mark = "Record?",
    what = card.title .. DOT .. card.value, lock = not Hl.Open(card.source) or nil, card = card }) then
    Rec.suggested = Rec.suggested + 1
  end
end

-- a record filled with today's best, quietly (a record turned on, a statistic added, the login's look at what the
-- roster holds): every member's value for it, and for cc every clear the roster holds
function Rec:Fill(id)
  if not Rec.Active() then return end
  if id == "cc" then
    local ns = {}
    for _, row in ipairs(C.Roster:Rows()) do
      for k in pairs(row.stats or {}) do
        local n = type(k) == "string" and tonumber(k:match("^c(%d+)$"))
        if n then ns[n] = true end
      end
    end
    for n in pairs(ns) do self:Clear(n, false) end
    return
  end
  for _, row in ipairs(C.Roster:Rows()) do
    local v = row.stats and row.stats[id]
    if type(v) == "number" and type(row.guid) == "string" then self:Seen(id, row.guid, v, false) end
  end
end
-- a code's records: cc every clear, a statistic, a stat by its code
function Rec:FillCode(code)
  if code == "cc" then return self:Fill("cc") end
  local id = code:match("^g%d+$") and code or C.Stats.byCode[code]
  if id and Rec.Kind(id) then self:Fill(id) end
end
-- the login's look: every record the roster holds, quietly (what came while you were away)
function Rec:Scan()
  if not Rec.Active() then return end
  for _, id in ipairs(Rec.ORDER) do if C.Stats.byId[id] then self:Fill(id) end end
  for code in pairs(Rec.List().codes) do if code:match("^g%d+$") then self:Fill(code) end end
  self:Fill("cc")
end

----------------------------------------------------------------------------
-- what arrives (Comm.lua): a clear's stat defined before the roster takes the value (so its route and bounds are the
-- stat's), then every value it kept, seen; your own as Sample sets it
----------------------------------------------------------------------------
function Rec:Before(kv, sender)
  if type(kv) ~= "table" then return end
  for id in pairs(kv) do
    local n = type(id) == "string" and tonumber(id:match("^c(%d+)$"))
    if n then Rec.ClearDef(n, false, sender) end
  end
end
function Rec:After(sender, kv, delta)
  if type(kv) ~= "table" or not Rec.Active() then return end
  local e = CuteDB.roster and CuteDB.roster[sender]
  local g = C.Roster:GuidOf(sender)
  if type(e) ~= "table" or type(e.stats) ~= "table" or not g then return end
  local live = delta == true and Rec.loginAt ~= nil and gtime() - Rec.loginAt >= LIVE_AFTER
  local clears, on, E
  for id, v in pairs(kv) do
    -- (only what the roster kept: a value it dropped as one that cannot be is none)
    if type(id) == "string" and type(v) == "number" and e.stats[id] == v and Rec.Kind(id) then
      local p = id:sub(1, 1)
      if p == "c" then clears = clears or {}; clears[#clears + 1] = tonumber(id:sub(2)); if live then came(id, g) end
      elseif p == "g" then
        -- (a statistics pass is a thousand of them: only the ones added are looked at)
        on, E = on or Rec.List().codes, E or Rec.Entries()
        if on[id] or E[id] then self:Seen(id, g, v, live, sender) end
      else self:Seen(id, g, v, live, sender) end
    end
  end
  for _, n in ipairs(clears or {}) do self:Clear(n, live) end
end
-- (your own value changing is live; the reads a login makes, from nothing in its first 90 s, are not)
function Rec:Own(id, old, new)
  if type(id) ~= "string" or type(new) ~= "number" or not Rec.Kind(id) then return end
  local live = C.Sample.loaded == true and (old ~= nil or (Rec.loginAt ~= nil and gtime() - Rec.loginAt >= LIVE_AFTER))
  if live and id:sub(1, 1) == "c" then came(id, C.MyGUID()) end
  self:Seen(id, C.MyGUID(), new, live)
end
-- (the five-second ticker moves time played: a stat that holds no record returns here, making nothing)
local own = C.Safe(function(id, old, new) Rec:Own(id, old, new) end, "records: your value")
C.Sample:OnValue(function(id, old, new) if type(new) == "number" and Rec.Kind(id) then own(id, old, new) end end)

----------------------------------------------------------------------------
-- 1O: the records on, from the officers (13.2)
----------------------------------------------------------------------------
function Rec.Message()
  local L = Rec.List()
  local codes = {}
  for code in pairs(L.codes) do codes[#codes + 1] = code end
  table.sort(codes)
  local head = "1O|" .. string.format("%.0f", tonumber(L.at) or 0) .. "|"
  local body = ""
  for _, code in ipairs(codes) do
    local more = (body == "" and "" or ".") .. code
    if #head + #body + #more <= LIMIT then body = body .. more end
  end
  return head .. body
end
function Rec:Send()
  -- (an officer marked untrusted sends nothing: every client refuses their list)
  if not (officer() and C.Roster:InGuild()) or C.Policy:Untrusted(C.MyGUID()) then return end
  C.Comm.Queue({ msg = Rec.Message() })
  Rec.sentAt = gtime()
  Rec.sent = Rec.sent + 1
end
-- a change goes at once, one message a minute at most (the newest list when it goes)
function Rec:SendSoon()
  if Rec.sendDue then return end
  Rec.sendDue = true
  local wait = Rec.sentAt and math.max(0, SEND_GAP - (gtime() - Rec.sentAt)) or 0
  C_Timer.After(wait, C.Safe(function() Rec.sendDue = false; Rec:Send() end, "records: 1O"))
end
-- an officer switches a record on or off (a statistic by its id, every clear by cc): newest wins, filled now
function Rec:SetOn(id, on)
  if not officer() then return false end
  local code = (id == "cc") and "cc" or Rec.Code(id)
  if not code then return false end
  local L = Rec.List()
  if (L.codes[code] == true) == (on == true) then return true end
  L.codes[code] = on and true or nil
  L.at = math.max(math.floor(now()), (tonumber(L.at) or 0) + 1)
  L.by = C.Roster:MyDisplay()
  if on then self:FillCode(code) end
  self:SendSoon()
  changed()
  return true
end
function Rec:Receive(text, sender, whispered)
  if whispered or type(text) ~= "string" then return end
  local at, body = text:match("^1O|(%d+)|([%w_%.]*)$")
  at = tonumber(at)
  if not at then return end
  -- (from an officer by the roster, not marked untrusted: a member's list is nobody's)
  if not C.Roster:OfficerVoice(sender) then Rec.refused = Rec.refused + 1; return end
  if at > Rec.heardAt then Rec.heardAt = at end
  local L = Rec.List()
  if at <= (tonumber(L.at) or 0) then return end
  local codes, n = {}, 0
  for code in body:gmatch("[^%.]+") do
    if n < CODES_MAX and #code <= 12 and code:match("^[%l_][%l%d_]+$") then codes[code] = true; n = n + 1 end
  end
  local was = L.codes
  L.at, L.codes, L.by = at, codes, C.Roster:Display(sender)
  Rec.taken = Rec.taken + 1
  for code in pairs(codes) do if not was[code] then self:FillCode(code) end end
  changed()
end

----------------------------------------------------------------------------
-- the Records chip (11.3): rows of the windows design's pattern A, grouped; a heading per group. For officers each
-- row's switch and Preview, the Fastest clears heading's switch, Add in the band
----------------------------------------------------------------------------
local GROUPS = { { "run", "In one run" }, { "week", "In a week" }, { "all", "All time" }, { "clear", "Fastest clears" } }
-- the chip's lines: { head, within } and { id, e } in the groups' order; a statistic on with no holder yet listed for
-- officers (its switch to turn it off), one this client cannot name (no statistics here) left out; the Fastest clears
-- heading for officers always. And whether any record is held
function Rec.Lines(isOfficer)
  local E = Rec.Entries()
  local by = { run = {}, week = {}, all = {}, clear = {} }
  local seen = {}
  for _, id in ipairs(Rec.ORDER) do
    local _, within = Rec.Kind(id)
    if E[id] and within then by[within][#by[within] + 1] = { id = id, e = E[id] }; seen[id] = true end
  end
  local stats, clears = {}, {}
  for id, e in pairs(E) do
    if not seen[id] then
      if id:match("^g%d+$") then if C.Stats.byId[id] then stats[#stats + 1] = { id = id, e = e } end
      elseif id:match("^c%d+$") then clears[#clears + 1] = { id = id, e = e, place = Rec.Place(tonumber(id:sub(2))) } end
    end
  end
  if isOfficer then
    for code in pairs(Rec.List().codes) do if code:match("^g%d+$") and not E[code] and C.Stats.byId[code] then stats[#stats + 1] = { id = code } end end
  end
  local function label(x) local d = C.Stats.byId[x.id]; return d and d.label or x.id end
  table.sort(stats, function(a, b) if label(a) ~= label(b) then return label(a) < label(b) end return a.id < b.id end)
  table.sort(clears, function(a, b) if a.place ~= b.place then return a.place < b.place end return a.id < b.id end)
  for _, x in ipairs(stats) do by.all[#by.all + 1] = x end
  by.clear = clears
  local out, any = {}, false
  for _, g in ipairs(GROUPS) do
    if #by[g[1]] > 0 or (g[1] == "clear" and isOfficer) then
      out[#out + 1] = { head = g[2], within = g[1] }
      for _, x in ipairs(by[g[1]]) do out[#out + 1] = x; any = any or x.e ~= nil end
    end
  end
  return out, any
end

-- a row: the bar, the trophy, the stat, the holder, the value and the day; an officer's switch and Preview
local function makeRow(parent)
  local U = C.UI
  local r = U:MakeLine(parent)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(16, 16)
  r.what = U.Text(r, 12, INK, "LEFT", 200)
  r.day = U.Text(r, 11, DIM, "RIGHT", 56)
  r.sw = U.Check(r)
  r.pv = U.Button(r, "Preview", 64, 18)
  return r
end
local function dayOf(t) return (date and t) and (date("%d %b", t):gsub("^0", "")) or "" end
-- the card its holder would get now, on the card screen (nothing sent)
function Rec.Preview(id)
  local e = Rec.Entries()[id]
  if not (e and C.CardFrame) then return false end
  local card = Rec.Card(id, e)
  C.CardFrame:Announce({ kind = "r", title = card.title, cards = { card } }, { look = true })
  return true
end
local function switchTip(tip, on, clears)
  tip:AddLine(on and "On" or "Off", 1, 1, 1)
  if clears then tip:AddLine(on and "A fastest clear beaten by 5% or more, within the instance's level range, shows on every member's screen."
    or "Off: fastest clears change quietly here.", 0.85, 0.85, 0.85, true)
  else tip:AddLine(on and "Another member taking it puts it in your Queue as Record?." or "Off: it changes quietly here.", 0.85, 0.85, 0.85, true) end
end
function Rec.Draw(ui)
  local U, ROW = C.UI, C.UI.ROW
  local Hl = H()
  local sf = ui.scroll
  local w = sf:Width()
  ui.rows:Clear()
  local isOfficer = C.Roster:MeOfficer()
  local lines, any = Rec.Lines(isOfficer)
  -- (nothing held: a line saying so, an officer's switches under it)
  local y0 = 0
  if not any then
    Hl.Say(ui, 6, 6, w - 12, "No records yet: they fill in as the guild plays.")
    y0 = 30
    if #lines == 0 then sf:SetContentHeight(y0); return end
  end
  local rows = ui:List("records", makeRow)
  -- (on the right: the day, the value before it; an officer's Preview and switch after them)
  local OFF = isOfficer and 100 or 0
  local VAL = 90
  rows:Set(#lines, y0, ROW, function(r, i, ly)
    local x = lines[i]
    r:SetHeight(ROW)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, -ly)
    r:SetWidth(w)
    r.val:Hide(); r.who:Hide()
    r.sw:ClearAllPoints(); r.sw:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    r.pv:ClearAllPoints(); r.pv:SetPoint("RIGHT", r, "RIGHT", -28, 0)
    if x.head then
      r.bg:SetColorTexture(1, 1, 1, 0)
      r.bar:Hide(); r.icon:Hide(); r.what:Hide(); r.day:Hide(); r.pv:Hide()
      r.name:ClearAllPoints(); r.name:SetPoint("LEFT", 8, 0); r.name:SetWidth(w - 40); r.name:SetJustifyH("LEFT")
      color(r.name, WHITE)
      U.FitText(r.name, x.head, w - 44)
      local clears = x.within == "clear"
      r.sw:SetShown(isOfficer and clears)
      if isOfficer and clears then
        local on = Rec.List().codes.cc == true
        r.sw:Set(on); r.sw:SetOn(true)
        r.sw.fn = function(b) Rec:SetOn("cc", b:GetChecked()); C.UI:Draw() end
        r.sw:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); switchTip(GameTooltip, on, true); GameTooltip:Show() end)
        r.sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
      end
      r.fn = nil
      r.tip = clears and function(tip)
        tip:AddLine(x.head, 1, 1, 1)
        tip:AddLine("Each instance's fastest full clear two members' times agree on, from the run's start to its last boss.", 0.85, 0.85, 0.85, true)
      end or nil
      return
    end
    local id, e = x.id, x.e
    local def = C.Stats.byId[id]
    local clear = id:sub(1, 1) == "c"
    r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0)
    r.bar:Show(); r.bar:SetColorTexture(C.Cards.EDGE[1], C.Cards.EDGE[2], C.Cards.EDGE[3], 1)
    r.icon:ClearAllPoints(); r.icon:SetPoint("LEFT", 8, 0); r.icon:SetTexture(TROPHY); r.icon:Show()
    local label = clear and (x.place or Rec.Place(tonumber(id:sub(2)))) or (def and def.label or id)
    r.name:ClearAllPoints(); r.name:SetPoint("LEFT", 30, 0); r.name:SetWidth(200); r.name:SetJustifyH("LEFT")
    color(r.name, INK)
    U.FitText(r.name, label, 196)
    -- (the holder in class colour; a clear's with its mates where Grouped with goes to everyone: "Brann and 4")
    local whoW = w - 236 - (OFF + VAL + 70)
    r.what:ClearAllPoints(); r.what:SetPoint("LEFT", 236, 0); r.what:SetWidth(whoW); r.what:Show()
    if e then
      local name = "|cff" .. U.Hex(U.ClassColor(e.c)):sub(5) .. (e.n or "?") .. "|r"
      local mates = tonumber(e.m) or 0
      if clear and mates > 0 and C.Policy:Route("group") == "all" then name = name .. " and " .. mates end
      color(r.what, INK)
      U.FitText(r.what, name, whoW - 4)
    else
      color(r.what, MUTE)
      U.FitText(r.what, "No holder yet", whoW - 4)
    end
    r.val:ClearAllPoints(); r.val:SetPoint("RIGHT", r, "RIGHT", -(4 + OFF + 64), 0); r.val:SetWidth(VAL); r.val:SetJustifyH("RIGHT"); r.val:Show()
    color(r.val, WHITE)
    U.FitText(r.val, e and (def and U.Format(def, e.v) or tostring(e.v)) or "", VAL - 4)
    r.day:ClearAllPoints(); r.day:SetPoint("RIGHT", r, "RIGHT", -(4 + OFF), 0); r.day:Show()
    r.day:SetText(e and dayOf(e.t) or "")
    -- (an officer's switch per row; a clear's is the heading's, one for every instance)
    r.sw:SetShown(isOfficer and not clear)
    r.pv:SetShown(isOfficer and e ~= nil)
    if isOfficer and not clear then
      local on = Rec.IsOn(id)
      r.sw:Set(on); r.sw:SetOn(true)
      r.sw.fn = function(b) Rec:SetOn(id, b:GetChecked()); C.UI:Draw() end
      r.sw:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); switchTip(GameTooltip, on, false); GameTooltip:Show() end)
      r.sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    if isOfficer and e then
      r.pv:SetLabel("Preview"); r.pv:SetOn(true)
      r.pv:SetScript("OnClick", C.Safe(function() Rec.Preview(id) end, "records: preview"))
    end
    r.fn = nil
    r.tip = function(tip)
      tip:AddLine(label, 1, 1, 1)
      if e then
        tip:AddLine("Guild record " .. (Rec.WITHIN[(select(2, Rec.Kind(id)))] or "") .. ": " .. (e.n or "?") .. ", " .. r.val:GetText() .. ".", 0.85, 0.85, 0.85, true)
        tip:AddLine("Set " .. (U.Ago(e.t) or "") .. ".", 0.7, 0.7, 0.7)
      end
      if isOfficer then tip:AddLine(Rec.IsOn(id) and "On." or "Off: it changes quietly here.", 0.5, 0.5, 0.5, true) end
    end
  end)
  ui.virtual = function() rows:Show(ui.scroll.bar:GetValue() or 0, ui.scroll:View()) end
  sf:SetContentHeight(y0 + #lines * ROW + 8)
end
-- the band's Add (officers): a game statistic as a record, on, filled with today's best
function Rec.Band(ui, w)
  if not C.Roster:MeOfficer() then return end
  local Hl = H()
  local function allow(id) return id:match("^g%d+$") ~= nil and C.Policy:Route(id) == "all" and not Rec.IsOn(id) end
  local b
  b = Hl.BandButton(ui, w - 90, 90, "Add", true, function()
    Hl.PickStat("a", function(id) if id then Rec:SetOn(id, true); C.UI:Draw() end end, b, allow)
  end, function(tip)
    tip:AddLine("Add", 1, 1, 1)
    tip:AddLine("A game statistic as a guild record, switched on: its leader now, and a Record? row when another member takes it.", 0.85, 0.85, 0.85, true)
  end)
end
H().AddChip({ id = "records", title = "Records", order = 30, when = function() return moduleOn() and Rec.GuildOn() end, draw = Rec.Draw, band = Rec.Band,
  tip = "The guild's records: the most in one run, in a week and of all time, and each instance's fastest clear." })

----------------------------------------------------------------------------
-- Settings > Records: the officers' switch for the whole guild (greyed for members, who set it said)
----------------------------------------------------------------------------
function Rec.Settings(_, col)
  local isOfficer = C.Roster:MeOfficer()
  col:Head("Records")
  col:Check("On for the whole guild", Rec.GuildOn(), isOfficer, function(on)
    C.Policy:SetRule("recGuild", (not on) and 0 or nil)
    C.Comm:PolicySoon()
    C.UI:Draw()
  end, not isOfficer and "Set by the officers" or nil, function(tip)
    tip:AddLine("On for the whole guild", 1, 1, 1)
    tip:AddLine("Off: no member's Cute keeps or announces records. Each member can also switch Records off in Modules.", 0.85, 0.85, 0.85, true)
    local by = C.Rules.SetBy("recGuild")
    if by then tip:AddLine("Switched off by " .. C.Rules.WhoName(by) .. ".", 0.7, 0.7, 0.7, true) end
  end)
  if isOfficer then col:Note("Each record is switched on or off on the Halls tab's Records chip.") end
end

----------------------------------------------------------------------------
-- /cute diag cards: the records' line (counts and states, no name)
----------------------------------------------------------------------------
function Rec.Diag()
  local E = Rec.Entries()
  local n, clears = 0, 0
  for id in pairs(E) do n = n + 1; if id:sub(1, 1) == "c" then clears = clears + 1 end end
  local on = 0
  for _ in pairs(Rec.List().codes) do on = on + 1 end
  return {
    string.format("diag cards: records %s (guild %s) | %d on, list %s | table %d entries (%d clears), clear stats %d, a faster clear with one voice %d, voices apart %d | shown %d, quiet %d, Record? rows %d | 1O sent %d, taken %d, refused %d",
      moduleOn() and "on" or "off", Rec.GuildOn() and "on" or "off", on, Rec.Stamp() > 0 and (math.floor(now() - Rec.Stamp()) .. " s old") or "never set", n, clears, Rec.defs,
      Rec.lone, Rec.apart, Rec.announced, Rec.quiet, Rec.suggested, Rec.sent, Rec.taken, Rec.refused),
  }
end

----------------------------------------------------------------------------
-- the login: when it began (a delta is live 90 s into it), and the look at what the roster holds then
----------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", C.Safe(function()
  if Rec.loginAt then return end
  Rec.loginAt = gtime()
  C_Timer.After(LIVE_AFTER, C.Safe(function() Rec:Scan() end, "records: the login's look"))
end, "records: events"))

C:RegisterModule({
  id = "records", title = "Records", order = 47, builtin = true, default = true,
  notes = "Guild records on the Halls tab, and a toast when a fastest clear falls.",
  settings = function(ui, col) Rec.Settings(ui, col) end,
  onToggle = function(on) if on then C_Timer.After(1, C.Safe(function() Rec:Scan() end, "records: on")) end changed() end,
})
