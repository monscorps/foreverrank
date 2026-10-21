-- SPDX-License-Identifier: GPL-3.0-or-later
-- Runs: the run report's run (the run report's design, sections 3, 4, 7, 10, 12 and 14). A built-in module, on by
-- default; only a member who runs it counts and sends its own values, and a member may switch it off.
--   Kinds   a Dungeon or a Raid run starts with a loading screen into an instance GetInstanceInfo calls party or raid,
--           in a group (or GROUP_JOINED inside one); a Group run outside instances, in a group, a group mate on your map
--           at a 30-second sample (Settings > Runs "Long groups"). A /reload is never a start, and a ghost's loading
--           screens change nothing: the run is the instance's
--   Hello   each client says 2H with a provisional id (its start in server time, base 36, a dash, its GUID's last
--           part) and every client adopts the earliest it hears within 30 s of its own start; a member who joins later
--           is answered by the scribe (another holder only after 2 to 6 s with no answer heard) and adopts the answer
--   Scribe  the leader's client where the leader said hello, else the smallest GUID among the hellos held of members
--           still in the group; each client works it out alone, and only the scribe's 2Q, 2A and 2W are taken
--   Ends    the leader's End run (2E), a full clear with the scribe out alive, the scribe out alive past the grace (3
--           minutes, 10 in a raid), an open-world group apart for 5 minutes or under two; a disband, or leaving within
--           10 minutes of the last boss, ends your run with a report built here; leaving at another time is leaving
--           early. The scribe sends 2Q, waits for the members' last values (15 s at most), builds the report and sends
--           it as 2A; a client with no 2A 20 s after its 2Q builds its own
--   Values  each client's own counts (4.1), as 2V checkpoints after every boss kill and at the end; what every client
--           observes besides (deaths by UNIT_DIED, the damage meter's rows out of combat, the loot history, bosses and
--           wipes), so any client can build a report alone. A key whose policy code routes Only you is never sent; the
--           codes the guild set for itself (deaths, "where are you", jumps, consumables, level, gold) go only while
--           every member of the group is in the guild; a policy in doubt sends the run's clock alone
--   State   CuteDB.chars[me].run, which the game writes at a /reload and at a logout: a /reload resumes it, a login
--           within 30 minutes with two of its members in your group (and in its instance) resumes it, a crash asks the
--           scribe for this client's last checkpoint (2R, 2W)
-- What the report shows (Awards.lua chooses, CardFrame.lua draws) is saved in CuteDB.chars[me].runs.list, newest
-- first. The run stats (Runs, Shout-outs, Bloopers and their weeks) are the core's: defined here as the file loads, so
-- a client with Runs off still decodes, ranks and shows a guild mate's.
local _, C = ...
local R = { run = nil, heard = {} }
C.Runs = R

local GRACE = { d = 180, r = 600 }  -- seconds outside, alive, before the scribe ends the run
local APART = 300                    -- seconds an open-world group may be apart
local MIN_RUN = 300                  -- a dungeon or raid run reports from five minutes, a member counts from five
local MIN_GROUP = 900                -- a group run reports from fifteen minutes
local LATE = 120                     -- a member's run stopped this long before the end is gone early
local WAIT_Q, WAIT_A = 15, 20        -- the scribe waits for the last values; a client waits for the scribe's 2A
local AFTER_KILL = 600               -- leaving the group this soon after a boss is no leaving early
local RESUME = 1800                  -- a saved run a login resumes, at most this old
local SAMPLE, TICK = 30, 5

----------------------------------------------------------------------------
-- the run stats and the run fields (the core's registry, Stats.lua's S.def; the design's section 10 and 12)
----------------------------------------------------------------------------
do
  local S = C.Stats
  S.byCat.runs = S.byCat.runs or {}
  S.CATS[#S.CATS + 1] = "runs"
  S.CAT_LABEL.runs = "Runs"
  S.CAT_DEFAULT.runs = "all"
  local function def(id, label, o) o.track, o.slow = true, true; return S.def(id, label, "runs", o) end
  -- (each lifetime count reveals its weekly one, as Deaths its daily one: no weekly value opens what the lifetime count
  -- keeps closed)
  def("runs", "Runs", { code = "ru", grows = true, reveals = { "runs_week" }, hint = "run reports, counted from this character's own build of each" })
  def("runs_week", "Runs this week", { code = "rw", hint = "run reports since Monday" })
  def("honors", "Shout-outs", { code = "ho", grows = true, reveals = { "honors_week" }, hint = "GOLD STAR and SHOUT-OUT cards in run reports" })
  def("honors_week", "Shout-outs this week", { code = "hk", hint = "GOLD STAR and SHOUT-OUT cards since Monday" })
  def("roasts", "Bloopers", { code = "rx", grows = true, reveals = { "roasts_week" }, hint = "BLOOPER cards in run reports" })
  def("roasts_week", "Bloopers this week", { code = "rk", hint = "BLOOPER cards since Monday" })
  for _, id in ipairs({ "runs_week", "honors_week", "roasts_week" }) do C.Sample.WEEKLY[id] = true end
  -- the run fields: a policy code each (two letters for life), set under the Runs heading of Who sees what. No value of
  -- their own travels (kept out of S.list, so no record carries them): they route the run's own keys (Awards.lua
  -- A.KEYS), and the Me page shows whether this character's Runs counts them
  S.RUNFIELDS = { { "run_meter", "Meter in runs", "rm" }, { "run_quests", "Quests in runs", "rq" }, { "run_chat", "Chat lines in runs", "rc" },
    { "run_yards", "Yards in runs", "yw" }, { "run_loot", "Loot in runs", "rl" } }
  for _, f in ipairs(S.RUNFIELDS) do
    assert(not S.byCode[f[3]] and not S.byId[f[1]], "run field code: " .. f[3])
    local e = { id = f[1], label = f[2], cat = "runs", kind = "flag", code = f[3], default = "all", track = true, runField = true,
      hint = "in a run, sent to the group and the guild's run cards" }
    S.byId[e.id], S.byCode[e.code] = e, e.id
    S.codeVersion = (S.codeVersion or 0) + 1
    table.insert(S.byCat.runs, e)
  end
  -- the hidden sex beside the GUID, 2 male or 3 female (UnitSex, UnitDocumentation.lua): a card of a member out of
  -- range draws their race's portrait by it (Cards.lua). Everyone's always: the roster's to give
  S.HIDDEN.sex = { id = "sex", label = "Sex", cat = "hidden", kind = "int", default = "all", hidden = true, lo = 2, hi = 3 }
  S.HIDDEN_ORDER[#S.HIDDEN_ORDER + 1] = "sex"
  S.byId.sex = S.HIDDEN.sex
end

----------------------------------------------------------------------------
-- small things
----------------------------------------------------------------------------
local function now() return C.ServerNow() end
local function gtime() return (GetTime and GetTime()) or 0 end
local function callable(name) return type(_G[name]) == "function" end
-- a global client function, quietly nothing where this client has none (the Runs module asks every client)
local function call(name, ...) if not callable(name) then return nil end return C.Get(_G[name], ...) end
local function b36(n) return C.Comm.b36(n) end
local function unb36(s) return C.Comm.unb36(s) end
local function sfxOf(g) return type(g) == "string" and g:match("([^%-]+)$") or nil end
local function inCombat() return call("InCombatLockdown") == true end
local function rnd(a, b) return (math.random and math.random(a, b)) or a end
local A = function() return C.Awards end

-- this character's runs: the history, newest first, and Settings > Runs
function R.DB()
  local ch = C.Char()
  if type(ch.runs) ~= "table" then ch.runs = {} end
  local r = ch.runs
  if type(r.list) ~= "table" then r.list = {} end
  if r.keep ~= 10 and r.keep ~= 20 and r.keep ~= 50 then r.keep = 20 end
  if r.show == nil then r.show = true end
  if r.long == nil then r.long = true end
  return r
end

-- seconds into the run
local function el(run) return math.max(0, now() - (run.start or now())) end

-- the instance you are in: kind "d" or "r" and its id, nil outside one
local function instanceNow()
  local _, kind, _, _, _, _, _, id = call("GetInstanceInfo")
  if kind == "party" and type(id) == "number" then return "d", id end
  if kind == "raid" and type(id) == "number" then return "r", id end
  return nil, nil
end
local function myMap()
  local M = C_Map
  if type(M) ~= "table" or type(M.GetBestMapForUnit) ~= "function" then return nil end
  local m = C.Get(M.GetBestMapForUnit, "player")
  return type(m) == "number" and m or nil
end
local function ghost() return call("UnitIsDeadOrGhost", "player") == true end
local function inGroup() return call("IsInGroup") == true end

----------------------------------------------------------------------------
-- the group: its units as this client reads them now (identity where it is plain), cached until the roster changes
----------------------------------------------------------------------------
local PARTY, RAID = { "party1", "party2", "party3", "party4" }, {}
for i = 1, 40 do RAID[i] = "raid" .. i end
local groupCache, groupAt, groupGen = nil, -100, 0
function R.Dirty() groupGen = groupGen + 1 end
local function unitInfo(unit)
  local g = call("UnitGUID", unit)
  if type(g) ~= "string" or g == "" then return nil end
  local first, second = call("UnitName", unit)
  local _, class = call("UnitClass", unit)
  local _, race = call("UnitRace", unit)
  local sex = call("UnitSex", unit)
  local name = (type(first) == "string" and first ~= "" and not C.IsKstring(first)) and first or nil
  local full = name and type(second) == "string" and second ~= "" and not C.IsKstring(second) and (name .. " " .. second) or nil
  return { unit = unit, guid = g, sfx = sfxOf(g), name = name, full = full, class = type(class) == "string" and class or nil,
    race = type(race) == "string" and race or nil, sex = (sex == 2 or sex == 3) and sex or nil }
end
-- { [sfx] = { unit, guid, name, class, race, sex, me }, n = members, units = the group's units (UnitExists: those
-- whose GUID does not read are there all the same), leader = sfx }
function R.Group()
  local t = gtime()
  if groupCache and groupCache.gen == groupGen and t - groupAt < 5 then return groupCache end
  local out = { n = 0, units = 1, gen = groupGen, canon = {} }
  local me = C.MyGUID()
  if me then
    local e = unitInfo("player") or { unit = "player", guid = me, sfx = sfxOf(me) }
    e.me = true
    out[e.sfx] = e
    out.n = 1
  end
  if inGroup() then
    local raid = call("IsInRaid") == true
    -- (a raid's units name you too: raidN for every member, partyN for the others)
    out.units = raid and 0 or 1
    for _, u in ipairs(raid and RAID or PARTY) do
      if call("UnitExists", u) == true then out.units = out.units + 1 end
      local e = unitInfo(u)
      if e and e.guid ~= me and not out[e.sfx] then
        out[e.sfx] = e
        out.n = out.n + 1
        local k1, k2 = e.name and C.Canon(e.name), e.full and C.Canon(e.full)
        if k1 then out.canon[k1] = e end
        if k2 then out.canon[k2] = e end
      end
    end
    for sfx, e in pairs(out) do
      if type(e) == "table" and e.unit and call("UnitIsGroupLeader", e.unit) == true then out.leader = sfx end
    end
  end
  groupCache, groupAt = out, t
  return out
end
-- the group member a sender string names (CHAT_MSG_ADDON's): by its name, your realm cut (C.Canon), or its first word;
-- you as { me = true }
function R.UnitOf(sender)
  local key = C.Canon(sender)
  if not key then return nil end
  local g = R.Group()
  local e = g.canon[key] or g.canon[key:match("^(%S+)") or ""]
  if e then return e end
  local mine = C.Canon((C.MyName()))
  if mine and (key == mine or key:match("^(%S+)") == mine) then return { me = true } end
  return nil
end

----------------------------------------------------------------------------
-- the run: start, members, the hello
----------------------------------------------------------------------------
function R.Current() return R.run end
local function save(run) local ch = C.Char(); ch.run = run end
local function lootNow()
  local L = C_LootHistory
  if type(L) ~= "table" or type(L.GetLootHistoryTime) ~= "function" then return nil end
  local t = C.Get(L.GetLootHistoryTime)
  return type(t) == "number" and t or nil
end

-- the members as the group gives them now: new ones added, a name, class, race and sex kept where they read, a member
-- no longer in the group marked gone (the time), one back unmarked
function R:Sync()
  local run = self.run
  if not run then return end
  local g = R.Group()
  local t = el(run)
  for sfx, e in pairs(g) do
    if type(e) == "table" and e.guid then
      local m = run.members[sfx]
      if not m then
        local n = 0
        for _ in pairs(run.members) do n = n + 1 end
        if n < 60 then m = { g = e.guid, first = t, obs = {} }; run.members[sfx] = m end
      end
      if m then
        m.n = e.name or m.n
        m.c, m.r, m.s = e.class or m.c, e.race or m.r, e.sex or m.s
        m.gone = nil
      end
    end
  end
  for sfx, m in pairs(run.members) do if not g[sfx] and not m.gone then m.gone = t end end
end

local function flags(run, answer)
  return run.kind .. "." .. b36(run.inst or run.map or 0) .. (answer and ".a" or "")
end
function R:Hello(answer)
  local run = self.run
  if not run then return end
  C.RunComm:Send("2H", run.id .. "|" .. C.version .. "|" .. flags(run, answer))
end

function R:Start(kind, place)
  local me = C.MyGUID()
  if not me then return end
  local t = now()
  local run = { id = b36(t) .. "-" .. sfxOf(me), kind = kind, start = t, at = t, lc = lootNow(), seq = 0, members = {}, own = {},
    bosses = {}, nb = 0, wipes = 0, dorder = 0, fought = false, together = 1, maps = {}, meter = { done = {}, tot = {} }, loot = {} }
  if kind == "g" then run.map = place
  else
    run.inst = place
    -- (the instance's name as GetInstanceInfo gives it inside)
    local name = call("GetInstanceInfo")
    run.place = (type(name) == "string" and name ~= "" and not C.IsKstring(name)) and name or nil
  end
  self.run = run
  save(run)
  C.RunComm.counts, C.RunComm.results = {}, {}
  self:Sync()
  self:Counting(true)
  R.MarkSessions(run)
  -- the damage meter here (DamageMeterDocumentation.lua IsDamageMeterAvailable: isAvailable, failureReason)
  local DM = C_DamageMeter
  if type(DM) == "table" and type(DM.IsDamageMeterAvailable) == "function" then
    local ok, why = C.Get(DM.IsDamageMeterAvailable)
    run.meterOK = ok == true
    run.meterWhy = (ok ~= true) and (type(why) == "string" and why or "unavailable") or nil
  else
    run.meterOK, run.meterWhy = false, "C_DamageMeter is missing on this client"
  end
  if kind == "g" then
    local g = R.Group()
    run.together = g.n
  end
  local id = run.id
  C_Timer.After(rnd(0, 3), C.Safe(function() if R.run and R.run.id == id then R:Hello() end end, "runs: hello"))
end

-- the counting on or off for this client (Sample.lua counts the yards and the bag drops while it is on)
function R:Counting(on)
  C.Sample.runOn = on and true or nil
  if C.Sample.track then C.Sample.track.runYards = 0 end
end

-- a member's GUID suffix from the group, you included
local function mySfx() return sfxOf(C.MyGUID()) end

----------------------------------------------------------------------------
-- the scribe
----------------------------------------------------------------------------
-- (of a given run, the group as it is now: a message queued while this client was scribe is judged again as it leaves)
function R.ScribeOf(run)
  if not run then return nil end
  local g = R.Group()
  local me = mySfx()
  local lead = g.leader
  local lm = lead and run.members[lead]
  if lead and (lead == me or (lm and lm.hello and not lm.out)) then return lead end
  if not inGroup() then return me end
  local best, bestG = me, C.MyGUID() or ""
  for sfx, m in pairs(run.members) do
    if m.hello and g[sfx] and not m.gone and not m.out and m.g < bestG then best, bestG = sfx, m.g end
  end
  return best
end
function R:Scribe() return R.ScribeOf(self.run) end
function R:IsScribe() return self:Scribe() == mySfx() end

----------------------------------------------------------------------------
-- this client's own values, as a 2V carries them (by the policy as it leaves)
----------------------------------------------------------------------------
-- may a key leave this client: its code routed Everyone; the reused codes only while every member of the group is in
-- the guild (the roster as last read); with the policy in doubt, the clock alone. A member whose GUID does not read
-- (UnitGUID is SecretWhenUnitIdentityRestricted, UnitDocumentation.lua) is nobody this client can find in the roster:
-- with one in the group, the group is not all the guild's
local function allGuild()
  local Ro = C.Roster
  if not (Ro and Ro.trusted) then return false end
  local g = R.Group()
  if (g.units or 0) > g.n then return false end
  for sfx, e in pairs(g) do
    if type(e) == "table" and e.guid and not e.me and not Ro.byGuid[e.guid] then return false end
  end
  return true
end
function R.Route(code)
  if not code then return true end
  if not C.Policy:Settled() then return false end
  local id = C.Stats.byCode[code]
  if not id then return false end
  return C.Policy:Route(id) == "all"
end
local function sendable(key, settled, guildOnly)
  local code = A().CodeOf(key)
  if not code then return true end
  if not settled then return false end
  if A().REUSED[code] and not guildOnly then return false end
  return R.Route(code)
end
R.AllGuild = allGuild
-- the route a report's cards take (A.Pick's, and a received 2A's check): the policy's; with anyone outside the guild
-- in the group, no award reading a code the guild set for itself, but deaths, which every client observes of every
-- member (UNIT_DIED, 4.4): the others' values of those were never sent, so only the builder's own would rank, and
-- its 2A and Send to party would carry them to the stranger
function R.CardRoute(guildOnly)
  return function(code)
    if code ~= "de" and A().REUSED[code] and not guildOnly then return false end
    return R.Route(code)
  end
end

-- own values now: the counts, the clock (t), when this client stopped (o), the meter's own row, the dead seconds so far
function R:OwnValues()
  local run = self.run
  if not run then return {} end
  local o = run.own
  local v = {}
  for k, x in pairs(o) do v[k] = x end
  local t = el(run)
  v.t = run.out or run.ended or t
  v.o = run.out or 0
  -- (deaths are known here to be none: an award for no deaths reads a 0, which a member's absent key is not)
  v.de = v.de or 0
  if run.deadAt then v.dt = (v.dt or 0) + math.max(0, (run.out or t) - run.deadAt) end
  local mt = run.meter.tot[mySfx()]
  if mt then for k, x in pairs(mt) do if k ~= "dd" then v[k] = math.floor(x) end end; v.mt = 1 end
  if v.yd then v.yd = math.floor(v.yd) end
  return v
end

-- the k=v parts of a 2V (or a 2W) for values v, each key as A.KEYS bounds it
local function encode(v, filter)
  local kv = {}
  for _, k in ipairs(A().ORDER) do
    local x = v[k]
    if x ~= nil and (not filter or filter(k)) then
      if k == "q" then
        if type(x) == "table" and #x > 0 then
          local ids = {}
          for i = 1, math.min(16, #x) do ids[i] = b36(x[i]) end
          kv[#kv + 1] = "q=" .. table.concat(ids, ".")
        end
      elseif type(x) == "number" then kv[#kv + 1] = k .. "=" .. b36(math.floor(x)) end
    end
  end
  return kv
end
local function decode(body, dur)
  local v = {}
  for k, s in (body or ""):gmatch("([%l]+)=([^;]*)") do
    local key = A().KEYS[k]
    if key then
      local x
      if key.list then
        x = {}
        for id in s:gmatch("[^%.]+") do x[#x + 1] = unb36(id) end
      else x = unb36(s) end
      if x ~= nil and A().InBounds(k, x, dur) then v[k] = x end
    end
  end
  return v
end
R.Encode, R.Decode = encode, decode

-- this client's values as a 2V, built as it leaves (the policy then): every key it may send
function R:Values(final)
  local run = self.run
  if not run then return end
  run.seq = (run.seq or 0) + 1
  local id, seq = run.id, run.seq
  C.RunComm:Send("2V", function()
    local r = R.run
    if not r or r.id ~= id then return nil end
    local settled = C.Policy:Settled()
    local guildOnly = allGuild()
    local kv = encode(R:OwnValues(), function(k) return sendable(k, settled, guildOnly) end)
    R.sentKeys = kv
    return C.RunComm.Pack("2V|" .. id .. "|" .. seq .. "|", kv)
  end, { ooc = not final, key = "2V" })
end

----------------------------------------------------------------------------
-- what this client counts of its own (4.1)
----------------------------------------------------------------------------
local function counting() local run = R.run; return run and not run.out and not run.ended and run or nil end
local function add(k, n) local run = counting(); if run then run.own[k] = (run.own[k] or 0) + (n or 1) end end
R.Add = add

-- Sample.lua's bumps and lines: "where are you", jumps, the consumables used; the lines you type, any chat
C.Sample:OnBump(function(id, n)
  if not counting() then return end
  if id == "where" then add("wy", n) elseif id == "jumps" then add("ju", n) elseif id == "consumed" then add("cn", n) end
end)
C.Sample:OnChat(function() if counting() then add("ch") end end)

-- the yards Sample counted, into the run, every tick
local function yards()
  local T = C.Sample.track
  if not (T and T.runYards and T.runYards > 0) then return end
  local run = counting()
  if run then run.own.yd = (run.own.yd or 0) + T.runYards end
  T.runYards = 0
end

-- dead: your own death; the seconds dead until UnitIsDeadOrGhost reads false
local function died()
  local run = counting()
  if not run then return end
  local t = el(run)
  add("de")
  if not run.own.fd then run.own.fd = t; run.dorder = run.dorder + 1; run.ownOrder = run.dorder end
  run.deadAt = run.deadAt or t
  C_Timer.After(0.5, C.Safe(function() R:WipeCheck() end, "runs: wipe"))
end
local function alive()
  local run = R.run
  if not (run and run.deadAt) or ghost() then return end
  run.own.dt = (run.own.dt or 0) + math.max(0, (run.out or el(run)) - run.deadAt)
  run.deadAt = nil
  run.wiped = nil
end

-- a group member's death (UNIT_DIED, its GUID where plain), counted per member; yours is PLAYER_DEAD's
local function unitDied(guid)
  local run = R.run
  guid = C.Plain(guid)
  if not run or run.ended or type(guid) ~= "string" or guid == C.MyGUID() then return end
  local m = run.members[sfxOf(guid)]
  if not m or m.g ~= guid then return end
  local t = el(run)
  m.obs.de = (m.obs.de or 0) + 1
  if not m.obs.fd then m.obs.fd = t; run.dorder = run.dorder + 1; m.order = run.dorder end
  m.deadAt = m.deadAt or t
  C_Timer.After(0.5, C.Safe(function() R:WipeCheck() end, "runs: wipe"))
end

-- a wipe outside an encounter: every member known to be on the scribe's map (in a raid its subgroup, the party units)
-- dead or a ghost at once, counted once until one of them is alive again
function R:WipeCheck()
  local run = self.run
  if not run or run.wiped or not self:IsScribe() then return end
  local IE = C_InstanceEncounter
  if type(IE) == "table" and type(IE.IsEncounterInProgress) == "function" and C.Get(IE.IsEncounterInProgress) == true then return end
  local map = myMap()
  if not ghost() then return end
  local n = 1
  for _, u in ipairs(PARTY) do
    if call("UnitExists", u) == true then
      local M = C_Map
      local m = type(M) == "table" and type(M.GetBestMapForUnit) == "function" and C.Get(M.GetBestMapForUnit, u) or nil
      if m ~= nil and m == map then
        if call("UnitIsDeadOrGhost", u) ~= true then return end
        n = n + 1
      end
    end
  end
  if n >= 2 then run.wipes = run.wipes + 1; run.wiped = true end
end

----------------------------------------------------------------------------
-- the damage meter, read out of combat (4.3): GetCombatSessionFromID is SecretWhenInCombat. Each session id not read
-- yet that has a duration is read once per type; its rows summed per member (your own by isLocalPlayer, NeverSecret;
-- the others by sourceGUID where it is plain, ConditionalSecret). Cute never resets the meter nor sets its CVars
----------------------------------------------------------------------------
-- Enum.DamageMeterType (DamageMeterConstantsDocumentation.lua): DamageDone 0, HealingDone 2, Absorbs 4, Interrupts 5,
-- Dispels 6, DamageTaken 7, AvoidableDamageTaken 8, Deaths 9
local TYPES = { { 0, "dm" }, { 2, "hl" }, { 4, "ab" }, { 5, "in" }, { 6, "dp" }, { 7, "tk" }, { 8, "av" }, { 9, "dd" } }
-- the sessions the meter lists now, marked read without reading them: at a run's start they are fights from before it
-- (the meter keeps them unless the player's damageMeterResetOnNewInstance is on, and a group run enters no instance;
-- a session has no start time to tell, DamageMeterAvailableCombatSession), so neither your own row nor a member's
-- counts them. GetAvailableCombatSessions is no secret in combat (DamageMeterDocumentation.lua)
function R.MarkSessions(run)
  local DM = C_DamageMeter
  if not run or type(DM) ~= "table" or type(DM.GetAvailableCombatSessions) ~= "function" then return end
  local list = C.Get(DM.GetAvailableCombatSessions)
  for _, s in ipairs(type(list) == "table" and list or {}) do
    local sid = type(s) == "table" and C.Plain(s.sessionID) or nil
    if type(sid) == "number" then run.meter.done[sid] = true end
  end
end
function R:ReadMeter()
  local run = self.run
  local DM = C_DamageMeter
  if not (run and run.meterOK) or inCombat() or type(DM) ~= "table" or type(DM.GetAvailableCombatSessions) ~= "function" then return end
  local list = C.Get(DM.GetAvailableCombatSessions)
  if type(list) ~= "table" then return end
  local me, mine = C.MyGUID(), mySfx()
  for _, s in ipairs(list) do
    local sid = type(s) == "table" and C.Plain(s.sessionID) or nil
    local dur = type(s) == "table" and C.Plain(s.durationSeconds) or nil
    if type(sid) == "number" and type(dur) == "number" and not run.meter.done[sid] then
      run.meter.done[sid] = true
      run.meter.reads = (run.meter.reads or 0) + 1
      for _, ty in ipairs(TYPES) do
        local ok, session = pcall(DM.GetCombatSessionFromID, sid, ty[1])
        session = ok and C.Plain(session) or nil
        local rows = type(session) == "table" and C.Plain(session.combatSources) or nil
        for _, row in ipairs(type(rows) == "table" and rows or {}) do
          local isMe = C.Plain(row.isLocalPlayer) == true
          local g = isMe and me or C.Plain(row.sourceGUID)
          local amt = C.Plain(row.totalAmount)
          local sfx = sfxOf(g)
          if type(amt) == "number" and sfx and (isMe or (run.members[sfx] and run.members[sfx].g == g)) then
            local tot = run.meter.tot[sfx] or {}
            run.meter.tot[sfx] = tot
            tot[ty[2]] = (tot[ty[2]] or 0) + amt
            if isMe then run.own.mt = 1 end
          end
        end
      end
    end
  end
end

----------------------------------------------------------------------------
-- the loot history at the end (4.4): the drops of the encounters killed in this run, on the loot history's own clock
-- (GetLootHistoryTime, which the game's LootHistory.lua:508 sets against the drops' startTime)
----------------------------------------------------------------------------
local function quality(link)
  local I = C_Item
  local q = type(I) == "table" and type(I.GetItemQualityByID) == "function" and C.Get(I.GetItemQualityByID, link) or nil
  return type(q) == "number" and q or nil
end
function R:ReadLoot()
  local run = self.run
  local L = C_LootHistory
  if not run or type(L) ~= "table" or type(L.GetAllEncounterInfos) ~= "function" or type(run.lc) ~= "number" then return end
  local infos = C.Get(L.GetAllEncounterInfos)
  local loot = {}
  for _, info in ipairs(type(infos) == "table" and infos or {}) do
    local enc, st = C.Plain(info.encounterID), C.Plain(info.startTime)
    if type(enc) == "number" and run.bosses[enc] and type(st) == "number" and st >= run.lc then
      local drops = C.Get(L.GetSortedDropsForEncounter, enc)
      for _, d in ipairs(type(drops) == "table" and drops or {}) do
        local w = C.Plain(d.winner)
        local wg = type(w) == "table" and C.Plain(w.playerGUID) or nil
        if type(wg) == "string" and run.members[sfxOf(wg)] or wg == C.MyGUID() then
          local e = loot[sfxOf(wg)] or {}
          loot[sfxOf(wg)] = e
          e.wn = (e.wn or 0) + 1
          local q = quality(C.Plain(d.itemHyperlink))
          if q and q > (e.lq or -1) then e.lq = q end
        end
        for _, ri in ipairs(type(C.Plain(d.rollInfos)) == "table" and d.rollInfos or {}) do
          local g, roll, st2 = C.Plain(ri.playerGUID), C.Plain(ri.roll), C.Plain(ri.state)
          local sfx = sfxOf(g)
          if sfx and (run.members[sfx] or g == C.MyGUID()) then
            local e = loot[sfx] or {}
            loot[sfx] = e
            if type(roll) == "number" then
              if not e.hr or roll > e.hr then e.hr = roll end
              if not e.lr or roll < e.lr then e.lr = roll end
            end
            -- (Enum.EncounterLootDropRollState NeedMainSpec 0, LootHistoryDocumentation.lua)
            if st2 == 0 then e.nd = (e.nd or 0) + 1 end
          end
        end
      end
    end
  end
  run.loot = loot
end

----------------------------------------------------------------------------
-- the report (section 7): the members, their values, the choice
----------------------------------------------------------------------------
local METER = { "dm", "hl", "ab", "tk", "av", "in", "dp" }
-- the place's name: the instance's, as GetInstanceInfo gives it inside (kept at the start), else the map the group
-- spent the most samples on (C_Map.GetMapInfo)
local function placeOf(run)
  if run.place then return run.place end
  if run.kind == "g" then
    local best, n = run.map, 0
    for m, k in pairs(run.maps or {}) do if k > n then best, n = m, k end end
    local M = C_Map
    local info = best and type(M) == "table" and type(M.GetMapInfo) == "function" and C.Get(M.GetMapInfo, best) or nil
    return type(info) == "table" and type(C.Plain(info.name)) == "string" and C.Plain(info.name) or "Out in the world"
  end
  return "?"
end
R.PlaceOf = placeOf
-- the bosses the guild knows in an instance (the rules' model, the seed's included, and the labels that say it): a
-- full clear is every one of them killed in this run
function R.KnownBosses(inst)
  local set, n = {}, 0
  if not inst then return set, 0 end
  local ok, m = pcall(C.Rules.Model)
  local d = ok and type(m) == "table" and m.dungeons and m.dungeons[inst] or nil
  for _, enc in ipairs(d and d.bosses or {}) do
    local b = m.bosses[enc]
    if b and not b.optional and b.state ~= "stale" and not set[enc] then set[enc] = true; n = n + 1 end
  end
  for _, def in ipairs(C.Stats.byCat.found or {}) do
    if def.learned == "bosses" and def.num and not set[def.num] and C.Stats.InstOf(def.num) == inst then set[def.num] = true; n = n + 1 end
  end
  return set, n
end
local function fullClear(run)
  if run.kind == "g" or run.nb < 1 then return false end
  local set, n = R.KnownBosses(run.inst)
  if n == 0 then return false end
  for enc in pairs(set) do if not run.bosses[enc] then return false end end
  return true
end
R.FullClear = fullClear

-- a member's values for the choice: their own 2V's (none for a member the officers marked untrusted, ranked on what
-- this client observed alone), the observed meter rows where they lack one or differ by more than a tenth, the deaths
-- this client saw where their 2V says none, the loot history's
function R.MemberValues(run, sfx, m, endT)
  local v = {}
  local own = sfx == mySfx()
  local src = own and R:OwnValues() or ((m and not C.Policy:Untrusted(m.g)) and m.v) or {}
  for k, x in pairs(src or {}) do v[k] = x end
  local tot = run.meter.tot[sfx]
  if tot and not own then
    for _, k in ipairs(METER) do
      local o = tot[k]
      if type(o) == "number" then
        local x = v[k]
        if type(x) ~= "number" or math.abs(x - o) > 0.1 * math.max(math.abs(o), math.abs(x), 1) then
          -- (a guild member's own value the meter contradicts: their record marked suspect for the officers, once a run)
          if type(x) == "number" and m and not m.suspect then m.suspect = true; R.Suspect(m.g, k) end
          v[k] = math.floor(o)
        end
      end
    end
  end
  if m and not own then
    local obs = m.obs or {}
    if v.de == nil and obs.de then v.de = obs.de elseif type(v.de) == "number" and type(obs.de) == "number" and obs.de > v.de then v.de = obs.de end
    if v.fd == nil and obs.fd then v.fd = obs.fd end
    if v.dt == nil and obs.dt then v.dt = obs.dt end
    if v.de == nil and tot and type(tot.dd) == "number" then v.de = tot.dd end
    if v.de == nil then v.de = 0 end
  end
  local l = run.loot and run.loot[sfx]
  if l then
    for _, k in ipairs({ "hr", "lr", "nd", "wn" }) do if l[k] ~= nil then v[k] = l[k] end end
    if l.lq and (not v.lq or l.lq > v.lq) then v.lq = l.lq end
  end
  local first = own and (run.joined or 0) or (m and m.first or 0)
  v.t = math.max(0, math.min(endT, (m and m.gone) or endT) - first)
  return v
end

-- a guild member's record marked suspect (Roster.lua R:Suspect: the reason, which the officers alone see)
function R.Suspect(guid, key)
  local Ro = C.Roster
  local k = Ro and Ro.KeysByGuid and Ro:KeysByGuid()[guid]
  local e = k and CuteDB.roster[k]
  if type(e) == "table" then Ro:Suspect(e, "run values the damage meter contradicts (" .. tostring(key) .. ")") end
end

function R:Build(run, why)
  run = run or self.run
  if not run then return nil end
  local endT = run.ended or el(run)
  local me = mySfx()
  local members, gone, deaths = {}, {}, 0
  local list = {}
  for sfx, m in pairs(run.members) do list[#list + 1] = { sfx = sfx, m = m } end
  table.sort(list, function(a, b) return a.m.g < b.m.g end)
  for _, x in ipairs(list) do
    local sfx, m = x.sfx, x.m
    local stop = m.gone or (m.v and m.v.o and m.v.o > 0 and m.v.o) or m.away
    if sfx == me then stop = run.out end
    local inRun = (stop or endT) - ((sfx == me) and (run.joined or 0) or (m.first or 0))
    local v = R.MemberValues(run, sfx, m, endT)
    deaths = deaths + (v.de or 0)
    if inRun >= MIN_RUN then
      if stop and endT - stop > LATE then gone[#gone + 1] = sfx
      elseif not m.gone then members[#members + 1] = { sfx = sfx, guid = m.g, name = m.n, v = v, order = (sfx == me) and run.ownOrder or m.order } end
    end
  end
  local db = R.DB()
  local cards, mentions = A().Pick(members, { n = #members, raid = run.kind == "r" or #members >= 6, bosses = run.nb, runId = run.id, history = db.list }, R.CardRoute(allGuild()))
  local _, known = R.KnownBosses(run.inst)
  local rep = { id = run.id, kind = run.kind, inst = run.inst, map = run.map, place = placeOf(run), start = run.start, dur = endT,
    bosses = run.nb, known = math.max(known, run.nb), wipes = run.wipes, deaths = deaths, cards = cards, mentions = mentions, gone = gone,
    n = #members, members = {}, at = now() }
  local function keep(sfx)
    local m = run.members[sfx]
    if m then rep.members[sfx] = { n = m.n, c = m.c, r = m.r, s = m.s, g = m.g } end
  end
  for _, c in ipairs(cards) do keep(c[1]) end
  for _, c in ipairs(mentions) do keep(c[1]) end
  for _, sfx in ipairs(gone) do keep(sfx) end
  for _, c in ipairs(cards) do if c[1] == me then rep.mine = { c[2], c[3] } end end
  for _, c in ipairs(mentions) do if c[1] == me and not rep.mine then rep.mine = { c[2], c[3], mention = true } end end
  return rep
end

-- a report goes to the history the moment it is built or received (newest first, Settings > Runs keeps 10, 20 or 50)
function R.Keep(rep)
  local db = R.DB()
  for i = #db.list, 1, -1 do if db.list[i].id == rep.id then table.remove(db.list, i) end end
  table.insert(db.list, 1, rep)
  while #db.list > db.keep do table.remove(db.list) end
end
-- the run stats, from the card this client's own build gives you (a 2A only shows)
local function bump(rep)
  local S = C.Sample
  S:Bump("runs"); S:Bump("runs_week")
  local mine = rep.mine and not rep.mine.mention and A().Of(rep.mine[1])
  if mine and (mine.kind == "star" or mine.kind == "shout") then S:Bump("honors"); S:Bump("honors_week")
  elseif mine and mine.kind == "blooper" then S:Bump("roasts"); S:Bump("roasts_week") end
end

-- the report shown: never in combat or during a loading screen (it waits for PLAYER_REGEN_ENABLED, and 2 s after
-- PLAYER_ENTERING_WORLD); with Settings > Runs "Show the report when a run ends" unticked, the history alone
function R:Show(rep)
  self.shown = rep
  if not R.DB().show then return end
  if inCombat() or (self.loadingUntil and gtime() < self.loadingUntil) then self.toShow = rep; return end
  self.toShow = nil
  if C.CardFrame and C.CardFrame.Report then C.CardFrame:Report(rep) end
end
local function showWaiting()
  local rep = R.toShow
  if rep and not inCombat() and not (R.loadingUntil and gtime() < R.loadingUntil) then R:Show(rep) end
end

-- the run over on this client: its report (where it reports), the history, the run stats; nothing left counting
local function reports(run)
  local dur = run.ended or el(run)
  if run.kind == "g" then return dur >= MIN_GROUP and (run.together or 0) >= 2 end
  return dur >= MIN_RUN and run.fought and (run.together or 0) >= 2
end
function R:Finish(rep, shown)
  local run = self.run
  if not run then return end
  self.run = nil
  -- (no new run in this instance until you have been out of it: the members still inside hear the roster change after
  -- the end)
  local _, inst = instanceNow()
  self.endedIn = inst
  save(nil)
  self:Counting(false)
  if rep then
    -- (a policy in doubt: no award is eligible, so this client's own report waits until it settles)
    R.Keep(shown or rep)
    bump(rep)
    self:Show(shown or rep)
  end
end
-- this client's own build, now or once the policy settles
function R:BuildOwn(shown)
  local run = self.run
  if not run then return end
  if not reports(run) then self:Finish(nil) return end
  if not C.Policy:Settled() then self.pending = { run = run, shown = shown } return end
  self:ReadMeter()
  self:ReadLoot()
  self:Finish(self:Build(run), shown)
end

----------------------------------------------------------------------------
-- ends
----------------------------------------------------------------------------
-- the scribe ends the group's run: 2Q, the members' last values (15 s at most), the report as 2A
function R:GroupEnd(why)
  local run = self.run
  if not run or run.ended then return end
  run.ended, run.endWhy = el(run), why
  self:ReadMeter()
  self:ReadLoot()
  -- (sent only while this client is the scribe as it leaves: a held one is dropped where another is scribe by then)
  C.RunComm:Send("2Q", function() if R.ScribeOf(run) ~= mySfx() then return nil end return { "2Q|" .. run.id } end)
  run.qAt = gtime()
  local id = run.id
  local function done()
    local r = R.run
    if not r or r.id ~= id or r.aSent then return end
    r.aSent = true
    R:ScribeReport()
  end
  local function check()
    local r = R.run
    if not r or r.id ~= id or r.aSent then return end
    local g = R.Group()
    for sfx, m in pairs(r.members) do
      if m.hello and g[sfx] and not m.gone and not m.final then
        if gtime() - r.qAt < WAIT_Q then C_Timer.After(1, C.Safe(check, "runs: waiting")) return end
      end
    end
    done()
  end
  C_Timer.After(1, C.Safe(check, "runs: waiting"))
end
-- the scribe's report: its own build, sent as 2A (not while its policy is in doubt: the others build their own)
function R:ScribeReport()
  local run = self.run
  if not run then return end
  if not reports(run) then self:Finish(nil) return end
  if not C.Policy:Settled() then self.pending = { run = run } return end
  local rep = self:Build(run)
  local kv = { "k=" .. run.kind, "i=" .. b36(run.inst or run.map or 0), "s=" .. b36(run.start), "d=" .. b36(rep.dur), "b=" .. b36(rep.bosses),
    "n=" .. b36(rep.known), "w=" .. b36(rep.wipes), "x=" .. b36(rep.deaths) }
  local function list(cards)
    local out = {}
    for _, c in ipairs(cards) do out[#out + 1] = c[1] .. "." .. c[2] .. "." .. b36(math.floor(c[3] or 0)) end
    return table.concat(out, ",")
  end
  if #rep.cards > 0 then kv[#kv + 1] = "c=" .. list(rep.cards) end
  if #rep.mentions > 0 then
    -- (two halves where ten mentions would not fit one part)
    local a, b = {}, {}
    for i, c in ipairs(rep.mentions) do if i <= 5 then a[#a + 1] = c else b[#b + 1] = c end end
    kv[#kv + 1] = "h=" .. list(a)
    if #b > 0 then kv[#kv + 1] = "j=" .. list(b) end
  end
  if #rep.gone > 0 then kv[#kv + 1] = "g=" .. table.concat(rep.gone, ".", 1, math.min(#rep.gone, 20)) end
  local id = run.id
  C.RunComm:Send("2A", function() if R.ScribeOf(run) ~= mySfx() then return nil end return C.RunComm.Pack("2A|" .. id .. "|", kv) end)
  self:Finish(rep)
end

-- a client ends its own run on the scribe's 2Q: its last values (0 to 5 s on), then the scribe's 2A, or its own build
-- 20 s after the 2Q
function R:Ended()
  local run = self.run
  if not run or run.ended then return end
  run.ended = el(run)
  self:ReadMeter()
  self:ReadLoot()
  local id = run.id
  C_Timer.After(rnd(0, 5), C.Safe(function() if R.run and R.run.id == id then R:Values(true) end end, "runs: last values"))
  C_Timer.After(WAIT_A, C.Safe(function() if R.run and R.run.id == id then R:BuildOwn() end end, "runs: no report"))
end

-- the leader's End run (the Runs tab, /cute run end): 2E to the group, and the scribe's end
function R:EndRun()
  local run = self.run
  if not run then return false end
  if inGroup() and call("UnitIsGroupLeader", "player") ~= true then return false end
  C.RunComm:Send("2E", run.id)
  if self:IsScribe() then self:GroupEnd("leader") end
  return true
end
-- R:End(reason), the design's unit interface: the scribe's end of the group's run, or this client's own
function R:End(reason)
  if not self.run then return end
  if self:IsScribe() then self:GroupEnd(reason or "end") else self:BuildOwn() end
end
-- a snapshot of the run for the Runs tab's band and /cute diag runs
function R:Snapshot()
  local run = self.run
  if not run then return nil end
  local g = R.Group()
  local s = self:Scribe()
  local scribe = (s == mySfx()) and "you" or (run.members[s] and run.members[s].n) or (g[s] and g[s].name) or "?"
  return { id = run.id, kind = run.kind, place = placeOf(run), t = el(run), bosses = run.nb, wipes = run.wipes, scribe = scribe, out = run.out,
    meter = run.meterOK and "on" or ("off: " .. tostring(run.meterWhy)), reads = run.meter.reads or 0 }
end

-- you stopped counting (outside past the grace while the scribe is in): "out", your last values
local function stop(run)
  if run.out then return end
  alive()
  run.out = el(run)
  R:Counting(false)
  R:Values(true)
end

----------------------------------------------------------------------------
-- receiving (RunComm hands each message here with the group unit that sent it)
----------------------------------------------------------------------------
local function idTime(id) local t, s = tostring(id):match("^(%w+)%-(%w+)$"); return t and unb36(t) or nil, s end
-- the run's clock moved back to an id adopted from the group (every client counts "seconds into the run" from the same
-- start, so first deaths and stops compare): what was kept against the old start moves with it, and this client's own
-- time in the run starts where it joined
local function rebase(run, t)
  local shift = run.start - t
  if shift <= 0 then return end
  run.start = t
  local function mv(tb, k) if type(tb[k]) == "number" then tb[k] = tb[k] + shift end end
  for _, m in pairs(run.members) do mv(m, "first"); mv(m, "gone"); mv(m, "away"); mv(m, "deadAt"); mv(m.obs, "fd") end
  for _, k in ipairs({ "deadAt", "lastKill", "outAt", "out", "apartAt" }) do mv(run, k) end
  mv(run.own, "fd")
  run.joined = (run.joined or 0) + shift
end
R.Rebase = rebase

function R:Heard(kind, rest, who)
  local run = self.run
  if kind == "2H" then return self:HeardHello(rest, who) end
  -- (Send to party clicked by a group mate: the report on the screen says who, run or none: the run is over by then)
  if kind == "2P" then
    local id = rest:match("^([^|]+)")
    self.posted = { by = who.name or "?", at = now(), id = id }
    if C.CardFrame and C.CardFrame.Posted then C.CardFrame:Posted(id) end
    return
  end
  if not run then
    -- (a crash's return: the scribe's answer to a 2R, taken below; anything else needs a run)
    return
  end
  local id, body = rest:match("^([^|]*)|?(.*)$")
  if id ~= run.id then return end
  local m = run.members[who.sfx]
  if kind == "2V" then
    local seq, data = body:match("^(%d+)|(.*)$")
    seq = tonumber(seq)
    if not (m and seq) or (m.seq and seq <= m.seq) then return end
    m.seq, m.v = seq, decode(data, el(run))
    m.hello = m.hello or true
    if run.ended and run.qAt then m.final = true end
    -- (a member out: its counting stopped while the scribe stays)
    if m.v.o and m.v.o > 0 then m.out = m.v.o end
  elseif kind == "2Q" then
    if who.sfx == self:Scribe() then self:Ended() end
  elseif kind == "2E" then
    if call("UnitIsGroupLeader", who.unit) == true and self:IsScribe() then self:GroupEnd("leader") end
  elseif kind == "2A" then
    if who.sfx ~= self:Scribe() then return end
    self:HeardReport(body)
  elseif kind == "2R" then
    -- (a member back from a crash: the scribe gives it back its last checkpoint)
    local sfx = body:match("^(%w+)$")
    if sfx ~= who.sfx or not self:IsScribe() or not (m and m.v) then return end
    local kv = encode(m.v)
    C.RunComm:Send("2W", function() return C.RunComm.Pack("2W|" .. run.id .. "|" .. sfx .. "|", kv) end)
  elseif kind == "2W" then
    local sfx, data = body:match("^(%w+)|(.*)$")
    if sfx ~= mySfx() or not self.asked or who.sfx ~= self:Scribe() then return end
    self.asked = nil
    local cp = decode(data, el(run))
    local o = run.own
    for k, x in pairs(cp) do
      if k == "fd" then if not o.fd or x < o.fd then o.fd = x end
      elseif k == "lq" then if not o.lq or x > o.lq then o.lq = x end
      elseif k == "q" then o.q = o.q or {}; for _, qid in ipairs(x) do if #o.q < 16 then o.q[#o.q + 1] = qid end end
      elseif k ~= "t" and k ~= "o" and k ~= "mt" and not (k == "dm" or k == "hl" or k == "ab" or k == "tk" or k == "av" or k == "in" or k == "dp") then
        o[k] = (o[k] or 0) + x
      end
    end
    self.restored = true
  end
end

-- a hello: the earliest id within 30 s of this client's start for this group, kind and place; a newcomer's answered
function R:HeardHello(rest, who)
  local run = self.run
  local id, ver, fl = rest:match("^([^|]*)|([^|]*)|([^|]*)$")
  if not (id and fl) then return end
  local kind, place, answer = fl:match("^([drg])%.(%w+)(%.?a?)$")
  if not kind then return end
  place = unb36(place)
  answer = answer == ".a"
  local t, sfx = idTime(id)
  if not (t and sfx) then return end
  if not run then return end
  if kind ~= run.kind or place ~= (run.inst or run.map or 0) then return end
  local m = run.members[who.sfx]
  if m then m.hello = ver ~= "" and ver or true end
  if id == run.id then
    if answer then self.answerHeard = gtime() end
    return
  end
  local myT, mySf = idTime(run.id)
  -- the newcomer's way: an answer from the group with an id older than this client's, taken (from the scribe where
  -- the leader said hello); then a 2R, in case this client counted in it before a crash
  if answer then
    if t < myT and (not run.answered) and (who.sfx == self:Scribe() or not (R.Group().leader and run.members[R.Group().leader] and run.members[R.Group().leader].hello)) then
      run.id, run.answered = id, true
      rebase(run, t)
      self.asked = true
      C.RunComm:Send("2R", id .. "|" .. mySfx())
    end
    return
  end
  -- within 30 s of this client's start: the smaller time, then the smaller suffix
  if math.abs(t - myT) <= 30 then
    if t < myT or (t == myT and sfx < mySf) then run.id = id; rebase(run, t) end
    return
  end
  -- a newcomer (its start later than ours by more than 30 s): the scribe answers at once, another holder after 2 to
  -- 6 s where no answer was heard meanwhile
  if t > myT + 30 then
    if self:IsScribe() then self:Hello(true)
    else
      local asked = gtime()
      C_Timer.After(rnd(2, 6), C.Safe(function()
        if R.run and R.run.id == run.id and not ((R.answerHeard or 0) >= asked) then R:Hello(true) end
      end, "runs: answer"))
    end
  end
end

-- the scribe's 2A: codes, suffixes and numbers alone; the place and the names this client's own. An award this
-- client's policy does not allow (a scribe of another guild's), or a suffix it never saw: its own build instead
function R:HeardReport(body)
  local run = self.run
  if not run or run.got2A then return end
  local kv = {}
  for k, s in body:gmatch("(%l)=([^;]*)") do kv[k] = s end
  local route = R.CardRoute(allGuild())
  local function cards(s, out)
    out = out or {}
    for sfx, code, v in (s or ""):gmatch("(%w+)%.(%u%u)%.(%w+)") do
      local a = A().Of(code)
      local value = unb36(v)
      if not a or not value then return nil end
      for _, r in ipairs(a.reads) do if not route(r) then return nil end end
      if sfx ~= mySfx() and not run.members[sfx] then return nil end
      out[#out + 1] = { sfx, code, value, a.kind }
    end
    return out
  end
  local list = cards(kv.c)
  local mentions = list and cards(kv.h) or nil
  if mentions and kv.j then mentions = cards(kv.j, mentions) end
  if not (list and mentions) then return end
  run.got2A = true
  local shown = { id = run.id, kind = run.kind, inst = run.inst, map = run.map, place = placeOf(run), start = run.start,
    dur = unb36(kv.d or "") or el(run), bosses = unb36(kv.b or "") or run.nb, known = unb36(kv.n or "") or run.nb, wipes = unb36(kv.w or "") or run.wipes,
    deaths = unb36(kv.x or "") or 0, cards = list, mentions = mentions, gone = {}, n = #list, members = {}, at = now(), from = "scribe" }
  for sfx in (kv.g or ""):gmatch("%w+") do if run.members[sfx] then shown.gone[#shown.gone + 1] = sfx end end
  local me = mySfx()
  local function keep(sfx) local m = run.members[sfx]; if m then shown.members[sfx] = { n = m.n, c = m.c, r = m.r, s = m.s, g = m.g } end end
  for _, c in ipairs(list) do keep(c[1]); if c[1] == me then shown.mine = { c[2], c[3] } end end
  for _, c in ipairs(mentions) do keep(c[1]) end
  for _, sfx in ipairs(shown.gone) do keep(sfx) end
  -- (this client's own build counts the stats; the scribe's shows)
  if not run.ended then run.ended = el(run) end
  self:ReadMeter()
  self:ReadLoot()
  if not reports(run) then self:Finish(nil) return end
  if not C.Policy:Settled() then self.pending = { run = run, shown = shown } return end
  self:Finish(self:Build(run), shown)
end

----------------------------------------------------------------------------
-- starts, the loading screens, the samples
----------------------------------------------------------------------------
-- a loading screen: into an instance, out of one, a /reload, a login (initial, reloading: PLAYER_ENTERING_WORLD's)
function R:World(initial, reloading)
  self.loadingUntil = gtime() + 2
  C_Timer.After(2.1, C.Safe(showWaiting, "runs: show"))
  R.Dirty()
  local run = self.run
  local kind, inst = instanceNow()
  if not self.loggedIn then
    self.loggedIn = true
    local saved = C.Char().run
    if type(saved) == "table" and type(saved.id) == "string" and type(saved.members) == "table" then
      if reloading then self:Resume(saved, false) return end
      -- a login: within 30 minutes, two of its members in the group now, and (a dungeon or a raid) in its instance
      local g, both = R.Group(), 0
      for sfx in pairs(saved.members) do if g[sfx] then both = both + 1 end end
      if g[mySfx()] and not saved.members[mySfx()] then both = both + 1 end
      if now() - (saved.at or 0) < RESUME and both >= 2 and (saved.kind == "g" or saved.inst == inst) then self:Resume(saved, true) return end
      save(nil)
    end
    run = nil
  end
  if reloading then return end
  -- (outside an instance the guard a run that ended in one set is over: the group may reset it and run it again)
  if not kind then self.endedIn = nil end
  if run then
    if run.kind == "g" then
      -- an instance entered ends a group run (its report where it lasted 15 minutes) and starts one there
      -- (each client enters itself: each ends its own at once, with its own build)
      if kind and inGroup() then
        run.ended = el(run)
        self:BuildOwn()
        if not self.run then self:Start(kind, inst) end
      end
      return
    end
    if inst == run.inst then run.outAt = nil; return end
    -- out of the instance: a ghost's corpse run changes nothing; alive, the grace begins (the tick watches it); a full
    -- clear and the scribe out alive ends the run at once
    if not ghost() then
      run.outAt = run.outAt or el(run)
      if self:IsScribe() and fullClear(run) then self:GroupEnd("clear") return end
    end
    if kind and inst ~= run.inst and not ghost() then
      -- (another instance entered: this one is over for this client)
      if self:IsScribe() then self:GroupEnd("moved") else stop(run) end
    end
    return
  end
  if kind and inGroup() and self.endedIn ~= inst then self:Start(kind, inst) end
end

function R:Resume(saved, login)
  self.run = saved
  saved.at = now()
  -- (the loot history's clock read again: kept at the start and at each resume)
  local lt = lootNow()
  if lt then saved.lc = lt - (now() - saved.start) end
  self:Counting(not saved.out and not saved.ended)
  -- (after a relog the meter's sessions and their ids are its own again: the marks start over from what it lists, the
  -- sums read so far kept; a /reload keeps the meter and the marks)
  if login and type(saved.meter) == "table" then saved.meter.done = {}; R.MarkSessions(saved) end
  if login then self:Sync(); self:Hello() end
end

-- GROUP_JOINED inside an instance starts a run there; a group left ends this client's run (a report where the group
-- disbanded within 10 minutes of a kill, or a group run of 15 minutes; else you left early)
function R:Roster()
  R.Dirty()
  local run = self.run
  if not run then
    local kind, inst = instanceNow()
    if kind and inGroup() and self.endedIn ~= inst then self:Start(kind, inst) end
    return
  end
  if not inGroup() then
    local t = el(run)
    if run.ended or (run.kind ~= "g" and run.lastKill and t - run.lastKill <= AFTER_KILL) or (run.kind == "g" and t >= MIN_GROUP) then
      run.ended = run.ended or t
      self:BuildOwn()
    else
      self:Finish(nil)
    end
    C.RunComm:Clear()
    return
  end
  self:Sync()
end

-- every 30 seconds: the run's state saved, the members synced, who is together; a group run's start and its end
function R:Sample()
  if not (C.Modules.byId.runs and C.Modules.byId.runs.active) then return end
  local run = self.run
  local kind, inst = instanceNow()
  if not run then
    if not kind and inGroup() and R.DB().long then
      local map = myMap()
      local g = R.Group()
      local mates = 0
      for _, e in pairs(g) do
        if type(e) == "table" and e.unit and not e.me and e.unit:match("^party%d$") then
          local M = C_Map
          local m = type(M) == "table" and type(M.GetBestMapForUnit) == "function" and C.Get(M.GetBestMapForUnit, e.unit) or nil
          if map and m == map then mates = mates + 1 end
        end
      end
      if map and mates >= 1 then self:Start("g", map); if self.run then self.run.together = mates + 1 end end
    end
    return
  end
  run.at = now()
  self:Sync()
  local g = R.Group()
  if run.kind ~= "g" then
    if inst == run.inst then run.together = math.max(run.together or 0, g.n) end
    return
  end
  -- an open-world group: the map the group is on; apart for five minutes, or under two, ends it
  local map = myMap()
  if map then run.maps[map] = (run.maps[map] or 0) + 1 end
  local mates = 0
  for sfx, e in pairs(g) do
    if type(e) == "table" and e.unit and not e.me and e.unit:match("^party%d$") then
      local M = C_Map
      local m = type(M) == "table" and type(M.GetBestMapForUnit) == "function" and C.Get(M.GetBestMapForUnit, e.unit) or nil
      if map and m == map then mates = mates + 1
      elseif m ~= nil and self:IsScribe() and run.members[sfx] then run.members[sfx].away = run.members[sfx].away or el(run) end
      if m == map and run.members[sfx] then run.members[sfx].away = nil end
    end
  end
  if mates > 0 then run.apartAt = nil else run.apartAt = run.apartAt or el(run) end
  if self:IsScribe() and ((run.apartAt and el(run) - run.apartAt >= APART) or g.n < 2) then self:GroupEnd("apart") end
end

-- every 5 seconds: the yards, the dead seconds of members whose values lack them, the grace outside, a policy that
-- settled for a report waiting on it
function R:Tick()
  yards()
  local run = self.run
  if self.pending and C.Policy:Settled() then
    local p = self.pending
    self.pending = nil
    -- (a scribe in doubt sent no 2A: the others built their own, and so does it)
    if self.run == p.run then self:BuildOwn(p.shown) end
  end
  showWaiting()
  if not run then return end
  local t = el(run)
  if run.deadAt and not ghost() then alive() end
  -- members dead now (UnitIsDeadOrGhost by unit): their seconds dead, for those whose 2V says none
  local g = R.Group()
  for sfx, e in pairs(g) do
    local m = type(e) == "table" and not e.me and run.members[sfx]
    if m and not (m.v and m.v.dt) then
      if call("UnitIsDeadOrGhost", e.unit) == true then
        m.obs.dt = (m.obs.dt or 0) + TICK
      end
    end
  end
  -- outside the instance alive past the grace: the scribe ends the group's run, another member stops counting
  if run.kind ~= "g" and not run.ended then
    local _, inst = instanceNow()
    if inst ~= run.inst and not ghost() then
      run.outAt = run.outAt or t
      if t - run.outAt >= (GRACE[run.kind] or 180) then
        if self:IsScribe() then self:GroupEnd("outside") else stop(run) end
      end
    elseif inst == run.inst then run.outAt = nil end
  end
end

----------------------------------------------------------------------------
-- events (heard while the module is on)
----------------------------------------------------------------------------
local money = { last = nil, quest = 0, open = {} }
local OPEN = { MERCHANT_SHOW = "m", MERCHANT_CLOSED = "m", MAIL_SHOW = "a", MAIL_CLOSED = "a", TRADE_SHOW = "t", TRADE_CLOSED = "t",
  BANKFRAME_OPENED = "b", BANKFRAME_CLOSED = "b" }
local function opened(ev) money.open[OPEN[ev]] = (ev:match("SHOW$") or ev:match("OPENED$")) and true or nil end

local events = {
  CHAT_MSG_ADDON = function(...) C.RunComm:Receive(...) end,
  ADDON_RESTRICTION_STATE_CHANGED = function(kind, state) C.RunComm:Restriction(kind, state) end,
  GROUP_JOINED = function() R:Roster() end,
  GROUP_LEFT = function() R:Roster() end,
  GROUP_ROSTER_UPDATE = function() R:Roster() end,
  PARTY_LEADER_CHANGED = function() R.Dirty() end,
  PLAYER_REGEN_DISABLED = function() if R.run then R.run.fought = true end end,
  PLAYER_REGEN_ENABLED = function()
    C_Timer.After(1, C.Safe(function() R:ReadMeter() end, "runs: meter"))
    showWaiting()
  end,
  ENCOUNTER_END = function(enc, _, _, _, success)
    local run = R.run
    enc, success = C.Plain(enc), C.Plain(success)
    if not run or run.ended or type(enc) ~= "number" then return end
    if success == 1 then
      if not run.bosses[enc] then run.bosses[enc] = true; run.nb = run.nb + 1 end
      run.lastKill = el(run)
      run.fought = true
      -- a checkpoint, 5 to 20 s on and out of combat
      local id = run.id
      C_Timer.After(rnd(5, 20), C.Safe(function() if R.run and R.run.id == id and not R.run.ended then R:Values() end end, "runs: checkpoint"))
    elseif success == 0 then
      run.wipes = run.wipes + 1
    end
  end,
  -- (the fallback for a kill the game reports only this way, as Sample.lua takes it: counted where no ENCOUNTER_END for
  -- it came in five seconds)
  BOSS_KILL = function(enc)
    enc = C.Plain(enc)
    local run = R.run
    if not run or type(enc) ~= "number" or run.bosses[enc] then return end
    C_Timer.After(5, C.Safe(function()
      local r = R.run
      if r and not r.bosses[enc] then r.bosses[enc] = true; r.nb = r.nb + 1; r.lastKill = el(r) end
    end, "runs: boss kill"))
  end,
  PLAYER_DEAD = died,
  PLAYER_ALIVE = alive,
  PLAYER_UNGHOST = alive,
  UNIT_DIED = unitDied,
  QUEST_TURNED_IN = function(id, _, reward)
    id, reward = C.Plain(id), C.Plain(reward)
    if type(reward) == "number" and reward > 0 then money.quest = money.quest + reward end
    local run = counting()
    if run and type(id) == "number" then
      run.own.q = run.own.q or {}
      if #run.own.q < 16 then run.own.q[#run.own.q + 1] = id end
    end
  end,
  PLAYER_LEVEL_UP = function() add("lv") end,
  -- gold looted: the purse rising with no merchant, mail, trade or bank open, less a quest's money reward
  PLAYER_MONEY = function()
    local m = call("GetMoney")
    if type(m) ~= "number" then return end
    local last = money.last
    money.last = m
    if not last or m <= last then return end
    local rise = m - last
    local q = math.min(rise, money.quest)
    money.quest = money.quest - q
    rise = rise - q
    if rise > 0 and not next(money.open) then add("gd", rise) end
  end,
  MERCHANT_SHOW = function() opened("MERCHANT_SHOW") end, MERCHANT_CLOSED = function() opened("MERCHANT_CLOSED") end,
  MAIL_SHOW = function() opened("MAIL_SHOW") end, MAIL_CLOSED = function() opened("MAIL_CLOSED") end,
  TRADE_SHOW = function() opened("TRADE_SHOW") end, TRADE_CLOSED = function() opened("TRADE_CLOSED") end,
  BANKFRAME_OPENED = function() opened("BANKFRAME_OPENED") end, BANKFRAME_CLOSED = function() opened("BANKFRAME_CLOSED") end,
  -- an item you received: CHAT_MSG_LOOT whose GUID argument (the 12th, ChatInfoDocumentation.lua) is yours, its
  -- quality by C_Item.GetItemQualityByID; uncommon or better counted
  CHAT_MSG_LOOT = function(text, _, _, _, _, _, _, _, _, _, _, guid)
    text, guid = C.Plain(text), C.Plain(guid)
    local run = counting()
    if not run or type(text) ~= "string" or guid ~= C.MyGUID() then return end
    local link = text:match("|Hitem:[^|]+|h")
    local q = link and quality(link) or nil
    if q and q >= 2 then
      run.own.ln = (run.own.ln or 0) + 1
      if not run.own.lq or q > run.own.lq then run.own.lq = q end
    end
  end,
  DAMAGE_METER_RESET = function() if R.run then R.run.meter.done = {} end end,
}

-- PLAYER_ENTERING_WORLD on a frame of its own: the module's frame is made as Cute's own handler of the first one runs
-- (Modules.lua M.Start), so the first loading screen reaches this one, which acts only while the module is on
local world = CreateFrame("Frame")
world:RegisterEvent("PLAYER_ENTERING_WORLD")
world:SetScript("OnEvent", C.Safe(function(_, _, initial, reloading)
  if not (C.Modules.byId.runs and C.Modules.byId.runs.active) then return end
  if money.last == nil then money.last = call("GetMoney") end
  R:World(C.Plain(initial) == true, C.Plain(reloading) == true)
end, "runs: loading screen"))

local ticking = false
local function startTimers()
  if ticking then return end
  ticking = true
  local function sample() C_Timer.After(SAMPLE, C.Safe(sample, "runs: sample")); R:Sample() end
  local function tick() C_Timer.After(TICK, C.Safe(tick, "runs: tick")); if C.Modules.byId.runs and C.Modules.byId.runs.active then R:Tick() end end
  C_Timer.After(SAMPLE, C.Safe(sample, "runs: sample"))
  C_Timer.After(TICK, C.Safe(tick, "runs: tick"))
end

R.events = events
R.startTimers = startTimers
-- the prefix, once: RegisterAddonMessagePrefix (ChatInfoDocumentation.lua); a result that is no success is kept for
-- /cute diag runs
function R.Register()
  if R.prefixDone or not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return end
  R.prefixDone = true
  local ok, res = pcall(C_ChatInfo.RegisterAddonMessagePrefix, C.RunComm.PREFIX)
  R.prefixResult = ok and C.Plain(res) or "threw"
end
