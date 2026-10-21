-- SPDX-License-Identifier: GPL-3.0-or-later
-- Sampling: reads every stat on its events and on a one-minute heartbeat, keeps the counters and the tracked
-- values this character accumulates (deaths, dances, time stood still, the bosses it kills and the instances it
-- enters), reads the gear and the bags again after every loading screen, discovers the bosses, instances and factions
-- it meets (Stats.lua's found category), probes the game's statistics at login and re-reads them in one coalesced pass,
-- gathers what the rules learn from (Rules.lua: the level at a boss's first kill, a boss's loot, the XP a level takes)
-- and tells Comm when something changed. (Comm sends only what changed, so the heartbeat's reads cost the channel
-- nothing while nothing moves.)
-- Every read runs under pcall; a read that errors stores nil and shows "?" with the error in the tooltip.
local _, C = ...
local S = { values = {}, at = {}, err = {}, dirty = {}, scheduled = {}, started = false }
C.Sample = S

local HEARTBEAT = 60   -- seconds between full passes
local SLICE = 20       -- stats read per slice of the heartbeat
local TICK = 5         -- the ticker that watches movement, ghosts, taxis and AFK
local POLL = 1         -- the quick poll for falling and the breath bar (two cheap client calls a second)

local function now() return C.Now() end
local function gtime() return (GetTime and GetTime()) or 0 end
local api = C.Api

----------------------------------------------------------------------------
-- counters and tracked values live in CuteDB.chars[me].counters
----------------------------------------------------------------------------
local function counters() return C.Char().counters end
function S:Counter(id) return counters()[id] or 0 end
-- the window hears of a change only where it shows the stat and its text changed (UI.lua), so the five-second ticker
-- that moves time played and the session draws nothing on a page that does not show them
local function shown(id, old, new) if C.UI and C.UI.ValueChanged then C.UI:ValueChanged(id, old, new) end end
function S:Set(id, v)
  local old = self.values[id]
  if old == v then return end
  local def = C.Stats.byId[id]
  if def and (def.count or def.track) then counters()[id] = v end
  self.values[id], self.at[id], self.err[id] = v, now(), nil
  self.dirty[id] = true
  self:Changed()
  shown(id, old, v)
end
function S:Bump(id, n)
  self:Set(id, (self:Counter(id) or 0) + (n or 1))
end

----------------------------------------------------------------------------
-- reading
----------------------------------------------------------------------------
local function readOne(def)
  -- a discovered count this character never had is no value at all (a boss it has not killed sends nothing, not a 0)
  if def.learned and def.track then return counters()[def.id] end
  if def.count or def.track then return counters()[def.id] or (def.kind == "list" and {} or (def.kind == "text" and "" or (def.kind == "flag" and false or (def.kind == "pips" and "" or 0)))) end
  C.lastErr = nil
  local ok, v = pcall(def.read)
  if not ok then return nil, tostring(v) end
  v = C.Plain(v)
  -- a nil from a client call that threw inside C.Get carries the error to the tooltip
  if v == nil and C.lastErr then return nil, C.lastErr end
  return v
end

local function same(a, b)
  if type(a) == "table" and type(b) == "table" then
    for k in pairs(a) do if b[k] ~= a[k] then return false end end
    for k in pairs(b) do if a[k] ~= b[k] then return false end end
    return true
  end
  return a == b
end

function S:Read(id)
  local def = C.Stats.byId[id]
  if not def then return end
  local v, err = readOne(def)
  self.err[id] = err
  local old = self.values[id]
  if not same(old, v) then
    self.values[id], self.at[id] = v, now()
    self.dirty[id] = true
    self:Changed()
    shown(id, old, v)
  elseif self.at[id] == nil then self.at[id] = now() end
end

function S:ReadAll()
  C.Stats.GearClear(); C.Stats.BagClear(); C.Stats.FactionsClear()
  for _, def in ipairs(C.Stats.list) do self:Read(def.id) end
end

-- the gear and the bags read afresh: 2 s and 10 s after every loading screen, for the inventory that arrives after it
-- (Forever's own character sheet refreshes on UNIT_INVENTORY_CHANGED for that, Stats.lua says where)
function S:GearPass()
  C.Stats.GearClear(); C.Stats.BagClear()
  for _, def in ipairs(C.Stats.list) do if def.gear or def.bag then self:Read(def.id) end end
end
function S:GearSoon()
  for _, wait in ipairs({ 2, 10 }) do C_Timer.After(wait, C.Safe(function() S:GearPass() end, "sample: gear")) end
end

-- a stat re-read at most once a second, however often its events fire
function S:Schedule(id)
  if self.scheduled[id] then return end
  self.scheduled[id] = true
  C_Timer.After(1, C.Safe(function() S.scheduled[id] = nil; S:Read(id) end, "sample: " .. id))
end

-- Comm is told once a second at most
function S:Changed()
  if self.telling or not self.started then return end
  self.telling = true
  C_Timer.After(1, C.Safe(function() S.telling = false; C.Comm:Changed() end, "sample: changed"))
end

----------------------------------------------------------------------------
-- the heartbeat: the whole registry in slices, so no frame reads 110 stats
----------------------------------------------------------------------------
local beatIndex = 0
local function slice()
  local list = C.Stats.list
  for i = beatIndex + 1, math.min(#list, beatIndex + SLICE) do
    local def = list[i]
    if not (def.count or def.track) then S:Read(def.id) end
  end
  beatIndex = math.min(#list, beatIndex + SLICE)
  if beatIndex >= #list then beatIndex = 0 end
end
local function heartbeat()
  -- the next beat is booked before the reads, so an error in one read never ends the heartbeat for the session
  local more = beatIndex + SLICE < #C.Stats.list
  C_Timer.After(more and 0.5 or HEARTBEAT, C.Safe(heartbeat, "sample: heartbeat"))
  -- a pass starts on a fresh gear, bag and faction scan
  if beatIndex == 0 then C.Stats.GearClear(); C.Stats.BagClear(); C.Stats.FactionsClear() end
  slice()
end

----------------------------------------------------------------------------
-- the day and the week: counters marked daily or weekly reset when the date changes (checked every ten minutes)
----------------------------------------------------------------------------
local DAILY = { quests_today = true, deaths_today = true, levelups = true }
local WEEKLY = { logins = true, weekly_raids = true }
-- live: called by the ten-minute timer, not by Start (which resets here and then counts the login itself)
local function dayCheck(live)
  local ch = C.Char()
  local today = date and date("%Y-%m-%d") or ""
  local week = date and date("%Y-%W") or "" -- %W: the week starts on Monday
  local reset = false
  if ch.day ~= today then
    ch.day = today
    for id in pairs(DAILY) do counters()[id] = 0; S.values[id] = 0; S.dirty[id] = true end
    reset = true
  end
  if ch.week ~= week then
    local turned = ch.week ~= nil -- (nil: the first run on this character)
    ch.week = week
    for id in pairs(WEEKLY) do counters()[id] = 0; S.values[id] = 0; S.dirty[id] = true end
    -- a week turning while you play: this session is its first login
    if turned and live then counters().logins = 1; S.values.logins = 1 end
    reset = true
  end
  if reset then S:Changed() end
end
local function day()
  C_Timer.After(600, C.Safe(day, "sample: day"))
  dayCheck(true)
end

----------------------------------------------------------------------------
-- the ticker: movement, ghosts, taxis, AFK, XP pace, time played
----------------------------------------------------------------------------
local T = { lastPos = nil, stillSince = nil, ghostSince = nil, lastGhostPos = nil, taxiSince = nil, wasAfk = false,
  xp = {}, sessionStart = nil, sessionXP = 0, falling = -100, mirrorEmpty = {}, whispers = 0 }
S.track = T

-- the XP left to 60 from (lvl, xp, max): this level's rest plus every level ahead, over the curve the guild has learned
-- (Rules.lua rule 6: the members' UnitXPMax at each level, the seed's where they have not agreed yet). 0.4.0 scaled
-- Classic's table by your own max, which is gone
local function xpLeft(lvl, xp, max) return C.Rules.XPLeft(lvl, xp, max, 60) end
S.XPLeft = xpLeft
-- the XP your level takes, as the guild learns its curve from it: the hidden xpmax ("level:max") and your own sample.
-- Taken only when two reads five seconds apart agree, so a ding read halfway (the new level with the old max) is never
-- kept
local function xpSample(lvl, max, sure)
  if not (lvl and max and max > 0) then return end
  local text = math.floor(lvl) .. ":" .. math.floor(max)
  if not sure and T.xpPair ~= text then T.xpPair = text; return end
  T.xpPair = text
  if S.values.xpmax ~= text then S:Set("xpmax", text) end
  C.Rules.LearnXP(lvl, C.MyGUID() or "me", max)
end

local function pos()
  local y, x, _, inst = C.Get("UnitPosition", "player")
  if type(x) == "number" and type(y) == "number" then return x, y, inst end
end

local function tick()
  -- the next tick is booked first, so an error below never stops played, session and pace for the session
  C_Timer.After(TICK, C.Safe(tick, "sample: tick"))
  local t = gtime()
  local x, y, inst = pos()
  -- standing still
  if x and T.lastPos and T.lastPos[3] == inst and math.abs(T.lastPos[1] - x) < 0.5 and math.abs(T.lastPos[2] - y) < 0.5 then
    T.stillSince = T.stillSince or (t - TICK)
    local span = math.floor(t - T.stillSince)
    if span > S:Counter("still") then S:Set("still", span) end
  else T.stillSince = nil end
  T.lastPos = x and { x, y, inst } or nil
  -- ghosts: time and yards run
  if C.Get("UnitIsGhost", "player") == true then
    T.ghostSince = T.ghostSince or t
    if x and T.lastGhostPos and T.lastGhostPos[3] == inst then
      local dx, dy = x - T.lastGhostPos[1], y - T.lastGhostPos[2]
      S:Bump("ghost_yards", math.floor(math.sqrt(dx * dx + dy * dy)))
    end
    T.lastGhostPos = x and { x, y, inst } or nil
    S:Bump("ghost_time", TICK)
  else T.ghostSince, T.lastGhostPos = nil, nil end
  -- taxis
  if C.Get("UnitOnTaxi", "player") == true then
    T.taxiSince = T.taxiSince or t
  elseif T.taxiSince then
    local span = math.floor(t - T.taxiSince)
    T.taxiSince = nil
    T.lastFlightEnd = t
    S:Bump("flights")
    if span > S:Counter("longest_flight") then S:Set("longest_flight", span) end
  end
  -- AFK
  local afk = C.Get("UnitIsAFK", "player") == true
  if afk and not T.wasAfk then S:Bump("afk") end
  T.wasAfk = afk
  -- time played and session
  S:Bump("played", TICK)
  S:Bump("played_lvl", TICK)
  if T.sessionStart then
    local span = math.floor(t - T.sessionStart)
    S:Set("session", span)
    if span > S:Counter("longest") then S:Set("longest", span) end
    local hours = span / 3600
    S:Set("xp_session", hours > 0.05 and math.floor(T.sessionXP / hours) or 0)
    S:Set("whispers", math.floor(T.whispers / math.max(0.25, hours)))
  end
  -- XP an hour over the last hour, from the ring of XP samples { time, xp, level, max }
  local xp, max, lvl = C.Num("UnitXP", "player"), C.Num("UnitXPMax", "player"), C.Num("UnitLevel", "player")
  if xp and max and lvl then
    local ring = T.xp
    ring[#ring + 1] = { t, xp, lvl, max }
    while #ring > 0 and t - ring[1][1] > 3600 do table.remove(ring, 1) end
    if #ring >= 2 then
      local gained = 0
      for i = 2, #ring do
        local a, b = ring[i - 1], ring[i]
        -- across a ding, the rest of the old level (its own max) plus what is into the new one
        if b[3] > a[3] then gained = gained + (a[4] - a[2]) + b[2] else gained = gained + math.max(0, b[2] - a[2]) end
      end
      local span = (t - ring[1][1]) / 3600
      local rate = span > 0.05 and math.floor(gained / span) or 0
      S:Set("xp_hour", rate)
      -- XP left over XP an hour is hours; 0 (shown as "-") until there is a pace
      local left = (rate > 0 and lvl < 60) and xpLeft(lvl, xp, max) or nil
      S:Set("to60", left and math.floor(left / rate + 0.5) or 0)
    end
    T.lastMax = max
    xpSample(lvl, max)
  end
end

-- the quick poll: falling, for the fall-death heuristic; the breath and fatigue bars, for drownings
local MIRROR = { "BREATH", "EXHAUSTION" }
local function mirrorEmpty(name)
  -- the bar is listed and its live value is at zero
  for i = 1, 3 do
    local n = C.Get("GetMirrorTimerInfo", i)
    if n == name then
      local v = C.Num("GetMirrorTimerProgress", name)
      return v ~= nil and v <= 0
    end
  end
  return false
end
local function poll()
  C_Timer.After(POLL, C.Safe(poll, "sample: poll"))
  local t = gtime()
  if C.Get("IsFalling") == true then T.falling = t end
  for _, name in ipairs(MIRROR) do if mirrorEmpty(name) then T.mirrorEmpty[name] = t end end
end

----------------------------------------------------------------------------
-- events
----------------------------------------------------------------------------
local WHERE -- the "where are you" phrases (the chat hook below fills it)
local EVENTS = {}
local function on(event, fn) EVENTS[event] = EVENTS[event] or {}; table.insert(EVENTS[event], fn) end

-- stats re-read on their events, counters bumped on theirs
local function wire()
  for _, def in ipairs(C.Stats.list) do
    if def.on then for _, ev in ipairs(def.on) do on(ev, function() S:Schedule(def.id) end) end end
    if def.count and def.count:match("^%u[%u_]+$") then on(def.count, function() S:Bump(def.id) end) end
  end
end

on("PLAYER_DEAD", function()
  local t = gtime()
  if t - T.falling < 3 then S:Bump("falls") end
  -- the bar at zero now, or seen at zero by the poll in the last three seconds (the timer stops as you die)
  if mirrorEmpty("BREATH") or (T.mirrorEmpty.BREATH and t - T.mirrorEmpty.BREATH < 3) then S:Bump("drownings") end
  if mirrorEmpty("EXHAUSTION") or (T.mirrorEmpty.EXHAUSTION and t - T.mirrorEmpty.EXHAUSTION < 3) then S:Bump("fatigue") end
  local lvl = C.Num("UnitLevel", "player")
  if lvl and lvl < C.Rules.Cap() then S:Bump("deaths_lvl") end
end)
-- (a level up asks Missing enchants and the verdict again a second on, when UnitLevel has the new level: from the
-- rules' enchant level the research's slots count, Rules.lua rule 5)
on("PLAYER_LEVEL_UP", function() S:Set("played_lvl", 0); S:Schedule("unenchanted"); S:Schedule("ready") end)
-- Legacy Challenges and the game's statistics. ACHIEVEMENT_EARNED (achievementID) names the latest challenge and
-- clears the Legacy walk (the lc_ stats re-read through their own events); it and CRITERIA_UPDATE, which fires on
-- every kill and loot, start the statistics pass, which runs at most once in thirty seconds however many come, so a
-- storm of criteria never re-reads hundreds of statistics per event
local GAME_PASS = 30
function S:GamePass()
  if #C.Stats.byCat.game == 0 then return end
  local t = gtime()
  if self.gamePassAt and t - self.gamePassAt < GAME_PASS then
    if not self.gamePassDue then
      self.gamePassDue = true
      C_Timer.After(GAME_PASS - (t - self.gamePassAt), C.Safe(function() S.gamePassDue = false; S:GamePass() end, "sample: statistics"))
    end
    return
  end
  self.gamePassAt = t
  self.gamePasses = (self.gamePasses or 0) + 1
  for _, def in ipairs(C.Stats.byCat.game) do self:Read(def.id) end
end
on("ACHIEVEMENT_EARNED", function(id)
  C.Stats.LegacyClear()
  id = C.Plain(id)
  if type(id) == "number" then
    local _, name = C.Get("GetAchievementInfo", id)
    if type(name) == "string" and name ~= "" then S:Set("lc_last", name) end
  end
  S:GamePass()
end)
on("CRITERIA_UPDATE", function() S:GamePass() end)

-- the statistics probe (Stats.lua ProbeGame): at login, and again at 30 s and at two minutes when the client has the
-- function but listed nothing yet (achievement data can still be on its way at PLAYER_ENTERING_WORLD). Statistics
-- defined late are read at once; their first values go out with the next flush, and an asker gets them in full. While
-- a probe is still to come (Stats.gamePending) a member's client holds the guild's values of statistics it has not
-- defined aside, and the probe's last word keeps or drops them by their category (Roster.lua R:ReleaseHeld)
local RETRY = { 30, 120 }
function S:ProbeGame(attempt)
  attempt = attempt or 1
  local ok, what, again = C.Stats.ProbeGame()
  if ok then
    C.Stats.gamePending = false
    if attempt > 1 then
      for _, def in ipairs(C.Stats.byCat.game) do self:Read(def.id) end
      if C.UI and C.UI.Refresh then C.UI:Refresh() end
    end
    C.Roster:ReleaseHeld()
    return
  end
  if again and RETRY[attempt] then
    C.Stats.gamePending = true
    C_Timer.After(RETRY[attempt], C.Safe(function() S:ProbeGame(attempt + 1) end, "sample: statistics probe"))
  else
    C.Stats.gamePending = false
    C.Roster:ReleaseHeld()
    C.Err.Note(tostring(what), "statistics")
  end
end
-- money moves in copper; the gold stats keep copper and show gold
on("PLAYER_MONEY", function()
  local m = C.Num("GetMoney")
  if not m then return end
  local last = T.money
  T.money = m
  if last and m > last then
    S:Bump("gold_earned", m - last)
    if T.merchant then S:Bump("vendor_sales", m - last) end
    if T.guildBank then S:Bump("bank_out", m - last) end
  elseif last and m < last and T.guildBank then S:Bump("bank_in", last - m) end
end)
on("QUEST_TURNED_IN", function(_, _, money)
  money = C.Plain(money)
  if type(money) == "number" and money > 0 then S:Bump("gold_quests", money) end
end)
on("MERCHANT_SHOW", function() T.merchant = true end)
on("MERCHANT_CLOSED", function() T.merchant = false end)
on("GUILDBANKFRAME_OPENED", function() T.guildBank = true end)
on("GUILDBANKFRAME_CLOSED", function() T.guildBank = false end)
on("ZONE_CHANGED_NEW_AREA", function()
  local z = C.Get("GetZoneText")
  if type(z) ~= "string" or z == "" then return end
  local ch = C.Char()
  ch.zones = ch.zones or {}
  if not ch.zones[z] then
    ch.zones[z] = true
    local n = 0
    for _ in pairs(ch.zones) do n = n + 1 end
    S:Set("zones_seen", n)
  end
end)
-- every loading screen: the instance you are in (an entry where it is a new one), the gear and the bags a moment on
on("PLAYER_ENTERING_WORLD", function(initial, reloading)
  S:InstanceCheck(C.Plain(initial) == true, C.Plain(reloading) == true)
  S:GearSoon()
end)
-- a Fishing cast is known by its name: C_Spell.GetSpellName of the spell is the Fishing skill line's name as the skills
-- window gives it, so whatever Fishing spell Forever teaches counts (0.4.0's first build matched Classic's four rank
-- ids). The name is kept once found; a character without the skill reads it at most once a second (Stats.lua's cache)
local fishName
local function fishing(spellId)
  if type(spellId) ~= "number" then return false end
  fishName = fishName or C.Stats.SkillName(C.Stats.FISHING)
  if not fishName then return false end
  return C.Get(api("C_Spell", "GetSpellName"), spellId) == fishName
end
on("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellId)
  if C.Plain(unit) ~= "player" then return end
  spellId = C.Plain(spellId)
  if spellId == 8690 then
    S:Bump("hearths")
    if T.lastFlightEnd and gtime() - T.lastFlightEnd < 120 then S:Bump("hearth_waste") end
  elseif fishing(spellId) then T.fishingAt = gtime() end
end)
on("LOOT_OPENED", function() if T.fishingAt and gtime() - T.fishingAt < 30 then S:Bump("fish"); T.fishingAt = nil end end)
-- whispers are counted here; the ticker turns the count into an hourly rate. (Guild lines are counted as you send
-- them, in the chat hook below: CHAT_MSG_GUILD's sender is secret in dungeons and raids, where a guild talks most.)
on("CHAT_MSG_WHISPER", function() T.whispers = T.whispers + 1 end)
on("TAXIMAP_OPENED", function()
  local n = C.Num("NumTaxiNodes")
  if not n then return end
  local known = 0
  for i = 1, n do local kind = C.Get("TaxiNodeGetType", i); if kind == "REACHABLE" or kind == "CURRENT" then known = known + 1 end end
  if known > 0 then S:Set("flights_known", known) end
end)
on("TIME_PLAYED_MSG", function(total, level)
  total, level = C.Plain(total), C.Plain(level)
  if type(total) == "number" then S:Set("played", total) end
  if type(level) == "number" then S:Set("played_lvl", level) end
end)
-- consumables that leave your bags in a raid: the potions, elixirs, flasks and food the bag scan counts by class
on("BAG_UPDATE_DELAYED", function()
  if not T.inRaid then T.consumables = nil; return end
  C.Stats.BagClear()
  local total = 0
  for _, id in ipairs({ "potions", "elixirs", "flasks", "food" }) do
    local ok, v = pcall(C.Stats.byId[id].read)
    v = ok and C.Plain(v) or nil
    if type(v) == "number" then total = total + v end
  end
  if T.consumables and total < T.consumables then S:Bump("consumed", T.consumables - total) end
  T.consumables = total
end)

----------------------------------------------------------------------------
-- discovered in play: instances entered, bosses killed, factions (Stats.lua's found category). Each is a stat defined
-- the first time it is met, labelled with the game's own name for it, and the label is told to the guild (Comm.lua's
-- "1L"), so a member who never met it shows it all the same
----------------------------------------------------------------------------
local function tell(id) if C.Comm and C.Comm.LabelSoon then C.Comm:LabelSoon(id) end end
-- the counts behind the summary ints: different bosses killed, different dungeons entered
local function distinct()
  local k = C.Stats.Known() or {}
  local bosses, dungeons = 0, 0
  for id, v in pairs(counters()) do
    if type(id) == "string" and type(v) == "number" and v > 0 then
      if id:match("^e%d+$") then bosses = bosses + 1
      else
        local inst = tonumber(id:match("^i(%d+)$"))
        if inst and k.kind and k.kind[inst] == "party" then dungeons = dungeons + 1 end
      end
    end
  end
  return bosses, dungeons
end
function S:Summaries()
  local bosses, dungeons = distinct()
  self:Set("bosses", bosses)
  self:Set("dungeons_seen", dungeons)
end
-- the instance you are in, as GetInstanceInfo says at this moment: name, kind, id. Outside an instance that is the
-- continent ("Eastern Kingdoms", id 0; "Kalimdor", id 1), so a world boss is filed under its continent, not its zone:
-- a zone has no instance id of its own, and two zones sharing the continent's would rename it with every kill.
-- GetRealZoneText names it only where GetInstanceInfo gives no name
local function instanceNow()
  local name, kind, _, _, _, _, _, id = C.Get("GetInstanceInfo")
  if type(name) ~= "string" or name == "" then name = C.Get("GetRealZoneText") end
  return { name = type(name) == "string" and name or nil, kind = type(kind) == "string" and kind or nil, id = type(id) == "number" and id or nil }
end
-- an entry: a dungeon or a raid whose id differs from the last instance this character was in, or the first after a
-- login (the character left the world). The last one is kept across loading screens, so zoning out and back in, a
-- wipe's run back, is the same entry; a /reload is never one
function S:InstanceCheck(initial, reloading)
  local here = instanceNow()
  T.inDungeon, T.inRaid = here.kind == "party", here.kind == "raid"
  local ch = C.Char()
  if initial and not reloading and not T.leftWorld then T.leftWorld = true; ch.lastInst = nil end
  if not (T.inDungeon or T.inRaid) or not here.id then return end
  if reloading then ch.lastInst = here.id; return end
  if ch.lastInst == here.id then return end
  ch.lastInst = here.id
  local id = "i" .. here.id
  if here.name and C.Stats.Label(id, here.name, true, nil, here.kind) then tell(id) end
  if C.Stats.byId[id] then self:Bump(id) end
  if T.inDungeon then self:Bump("dungeons") else self:Bump("raids"); self:Bump("weekly_raids") end
  self:Summaries()
end
-- a boss killed: its count, the first kill's time (kept here, not sent), its label and its instance's, and the level
-- you were at the first kill (k<encounterID>: no stat of its own, it goes with the discoveries and Rules.lua learns the
-- dungeon's level range from it); the kill's claim with your group, which a group mate's corroborates (Rules.lua rule
-- 9). The kill opens a minute for its loot window (LOOT_OPENED, below)
local LOOT_WINDOW = 60
local function killed(encounter, name, here)
  local id = "e" .. encounter
  if not (type(name) == "string" and name ~= "") then name = "Boss " .. encounter end
  if here.id and here.name then
    local kind = (here.kind == "party" or here.kind == "raid") and here.kind or "w"
    if C.Stats.Label("i" .. here.id, here.name, true, nil, kind) then tell("i" .. here.id) end
  end
  if C.Stats.Label(id, name, true, here.id) then tell(id) end
  if not C.Stats.byId[id] then return end -- (the cap)
  S:Bump(id)
  local ch = C.Char()
  ch.firstKill = type(ch.firstKill) == "table" and ch.firstKill or {}
  if not ch.firstKill[encounter] then
    ch.firstKill[encounter] = now()
    local lvl = C.Num("UnitLevel", "player")
    if lvl then counters()["k" .. encounter] = lvl; S.values["k" .. encounter] = lvl; S.dirty["k" .. encounter] = true end
  end
  T.lastKill = { enc = encounter, inst = here.id, at = gtime() }
  S:Summaries()
  C.Rules:Killed(encounter)
  C.Rules:Dirty(true)
end
-- ENCOUNTER_END (encounterID, encounterName, difficultyID, groupSize, success): a kill when success is 1. BOSS_KILL
-- (encounterID, encounterName) counts only where no ENCOUNTER_END for the same encounter came within five seconds
-- either side, so a kill is never counted twice and a boss the game reports only one way is still counted
local BOSS_WINDOW = 5
T.encounterEnd, T.bossKill = {}, {}
on("ENCOUNTER_END", function(encounter, name, _, _, success)
  encounter, name, success = C.Plain(encounter), C.Plain(name), C.Plain(success)
  if type(encounter) ~= "number" or success ~= 1 then return end
  T.encounterEnd[encounter] = gtime()
  killed(encounter, name, instanceNow())
end)
on("BOSS_KILL", function(encounter, name)
  encounter, name = C.Plain(encounter), C.Plain(name)
  if type(encounter) ~= "number" then return end
  local at, here = gtime(), instanceNow()
  local function ended() local e = T.encounterEnd[encounter]; return e ~= nil and math.abs(e - at) <= BOSS_WINDOW end
  if ended() or (T.bossKill[encounter] and at - T.bossKill[encounter] <= BOSS_WINDOW) then return end
  T.bossKill[encounter] = at
  C_Timer.After(BOSS_WINDOW, C.Safe(function() if not ended() then killed(encounter, name, here) end end, "sample: boss kill"))
end)
-- a boss's loot: the first corpse's loot window opened within a minute of a kill, in the same instance, that holds an
-- item green or better, is that boss's. Its items are read (GetNumLootItems, GetLootSlotLink and GetLootSlotInfo, as
-- Forever's own loot frame reads them, Mainline/LootFrame.lua:227-228 and 515), never looted: coin, currency and grey
-- or white items are left out (a quest item or a trade good is no boss's loot table). LOOT_OPENED (autoLoot,
-- isFromItem; LootDocumentation.lua) says when the window is a container opened from the bags, which is no corpse; a
-- trash corpse of greys looted first leaves the boss's window to come. No documented call names the corpse a window
-- belongs to, so an add's or a trash mob's corpse with a green on it, looted before the boss's, still passes for the
-- boss's. Rules.lua keeps them as the boss's loot, seen, and the guild hears it in the labels message
on("LOOT_OPENED", function(_, isFromItem)
  if C.Plain(isFromItem) == true then return end
  local kill = T.lastKill
  if not kill or kill.looted or gtime() - kill.at > LOOT_WINDOW or instanceNow().id ~= kill.inst then return end
  local n = C.Callable("GetNumLootItems") and C.Num("GetNumLootItems") or nil
  if not n then return end
  local ids = {}
  for slot = 1, math.min(n, 16) do
    local link = C.Get("GetLootSlotLink", slot)
    local _, _, _, currency, quality = C.Get("GetLootSlotInfo", slot)
    local item = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    if item and currency == nil and type(quality) == "number" and quality >= 2 then ids[#ids + 1] = item end
  end
  if #ids == 0 then return end
  kill.looted = true
  if C.Rules.LearnLoot(kill.enc, ids, true) then tell("l" .. kill.enc) end
end)
-- your factions: the reputation list read once a second at most however many UPDATE_FACTION come; a faction met for
-- the first time is labelled and told, and every faction's standing is read again
function S:FactionPass()
  C.Stats.FactionsClear()
  local list = C.Stats.Factions()
  if not list then return end
  for fid, e in pairs(list) do
    local id = "f" .. fid
    if e.name and C.Stats.Label(id, e.name, true) then tell(id) end
  end
  for _, def in ipairs(C.Stats.byCat.found) do if def.learned == "rep" then self:Read(def.id) end end
end
function S:FactionSoon()
  if self.factionDue then return end
  self.factionDue = true
  C_Timer.After(1, C.Safe(function() S.factionDue = false; S:FactionPass() end, "sample: factions"))
end
on("UPDATE_FACTION", function() S:FactionSoon() end)

----------------------------------------------------------------------------
-- hooks: the game's own functions, after they run (hooksecurefunc taints nothing)
----------------------------------------------------------------------------
-- your own line: the event's GUID where it gives one, else the name (Roster.lua knows your names, both words on Forever)
local function isMe(who, guid) return C.Roster:IsMe(who, guid) end
local function hooks()
  if not hooksecurefunc then return end
  if DoEmote then
    hooksecurefunc("DoEmote", C.Safe(function(token)
      token = C.Plain(token)
      if type(token) ~= "string" then return end
      token = token:upper()
      S:Bump("emotes")
      if token == "DANCE" then S:Bump("dance") elseif token == "SIT" then S:Bump("sit") end
    end, "emote hook"))
  else
    -- no function to hook: count your own lines of the emote chat instead (the texts are English's). That chat is
    -- secret in dungeons and raids, so emotes there go uncounted; the three tooltips say so rather than count wrong
    C.Err.Note("DoEmote is missing on this client; emotes are counted from CHAT_MSG_TEXT_EMOTE", "emote hook")
    for _, id in ipairs({ "emotes", "dance", "sit" }) do
      C.Stats.byId[id].hint = "counted from your lines in the emote chat, which is secret in dungeons and raids: none count there"
    end
    on("CHAT_MSG_TEXT_EMOTE", function(text, who, _, _, _, _, _, _, _, _, _, guid)
      text, who = C.Plain(text), C.Plain(who)
      if not isMe(who, guid) then return end
      S:Bump("emotes")
      if type(text) == "string" then
        local t = text:lower()
        if t:find("^you dance") then S:Bump("dance") elseif t:find("^you sit") then S:Bump("sit") end
      end
    end)
  end
  if JumpOrAscendStart then hooksecurefunc("JumpOrAscendStart", C.Safe(function() S:Bump("jumps") end, "jump hook")) end
  -- the ways to ask, each padded with spaces so only whole words match
  WHERE = { " where are you ", " where r u ", " where are u ", " where r you ", " wya ", " where you at ", " where u at ",
    " hvor er du ", " hvor er dere ", " wo bist du ", " wo seid ihr " }
  -- your own lines, seen as you send them: the hook gets the caller's plain arguments where the chat events' text and
  -- sender are secret in dungeons and raids
  if C_ChatInfo and C_ChatInfo.SendChatMessage then
    hooksecurefunc(C_ChatInfo, "SendChatMessage", C.Safe(function(text, kind)
      text, kind = C.Plain(text), C.Plain(kind)
      if type(text) ~= "string" then return end
      if kind == "GUILD" then S:Bump("gchat") end
      -- "where are you" counts wherever you type it (say, party, raid, guild, a whisper, a channel: 0.2.0 counted
      -- party and raid only, so the owner's "where are you?" in /say never counted). Whole words only, so "where are
      -- your boots" does not; the guild's languages too
      local t = " " .. text:lower():gsub("[%p%c]", " "):gsub("%s+", " ") .. " "
      for _, phrase in ipairs(WHERE) do
        if t:find(phrase, 1, true) then S:Bump("where"); break end
      end
    end, "chat hook"))
  else
    C.Err.Note("C_ChatInfo.SendChatMessage is missing on this client; guild lines and \"where are you\" go uncounted", "chat hook")
  end
  -- a grey item right-clicked while a merchant is open is a sale: its vendor price, times the stack
  if C_Container and C_Container.UseContainerItem then
    hooksecurefunc(C_Container, "UseContainerItem", C.Safe(function(bag, slot)
      if not T.merchant then return end
      bag, slot = C.Plain(bag), C.Plain(slot)
      if type(bag) ~= "number" or type(slot) ~= "number" then return end
      local info = C.Get(api("C_Container", "GetContainerItemInfo"), bag, slot)
      if type(info) ~= "table" or C.Plain(info.quality) ~= 0 or C.Plain(info.hasNoValue) == true then return end
      local link, n = C.Plain(info.hyperlink), C.Plain(info.stackCount)
      if type(link) ~= "string" then return end
      local r = { C.Get(api("C_Item", "GetItemInfo"), link) }
      local price = r[11] -- sellPrice
      if type(price) == "number" and price > 0 then S:Bump("grey_gold", price * (type(n) == "number" and n or 1)) end
    end, "grey sale hook"))
  end
end

----------------------------------------------------------------------------
-- start
----------------------------------------------------------------------------
function S:Start(initial, reloading)
  if self.started then self:ReadAll(); return end
  self.started = true
  wire()
  hooks()
  local f = CreateFrame("Frame")
  self.frame = f
  f:SetScript("OnEvent", C.Safe(function(_, event, ...)
    -- a unit event is yours only (RegisterUnitEvent asks for that; a client without it gets every unit's)
    if event:match("^UNIT_") and C.Plain((...)) ~= "player" then return end
    -- the client has an item's data now: the gear and bag stats again only when it is one you wear or carry (a chat
    -- link, another addon or the Legacy window asks about items all the time; Stats.lua keeps the scans' ids)
    if event == "GET_ITEM_INFO_RECEIVED" and not C.Stats.ItemWanted(C.Plain((...))) then return end
    for _, fn in ipairs(EVENTS[event] or {}) do fn(...) end
  end, "sample: event"))
  for event in pairs(EVENTS) do
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
      -- never: the client restricts it
    elseif event:match("^UNIT_") then
      -- yours only, not every unit in sight; where that fails (no RegisterUnitEvent, or it throws) every unit's, and the
      -- unit check above keeps yours
      if not pcall(f.RegisterUnitEvent, f, event, "player") then pcall(f.RegisterEvent, f, event) end
    else pcall(f.RegisterEvent, f, event) end
  end
  dayCheck(false)
  -- this login
  T.sessionStart = gtime()
  T.sessionXP, T.whispers = 0, 0
  T.money = C.Num("GetMoney")
  T.lastXP, T.lastMax = C.Num("UnitXP", "player"), C.Num("UnitXPMax", "player")
  if not reloading then S:Bump("logins") end
  S:Set("last_login", now())
  -- your GUID, for the full record only (Stats.lua's hidden stat): set, not marked to send
  self.values.guid = C.MyGUID()
  -- the game says how long you have played; its chat line is the price
  if RequestTimePlayed then pcall(RequestTimePlayed) end
  -- the game's statistics, where this client reports them
  self:ProbeGame()
  -- the latest challenge at login, where the client can say (a tracked value, set on ACHIEVEMENT_EARNED from then on)
  if (counters().lc_last or "") == "" and C.Callable("GetLatestCompletedAchievements") then
    local latest = C.Get("GetLatestCompletedAchievements")
    if type(latest) == "number" then
      local _, name = C.Get("GetAchievementInfo", latest)
      if type(name) == "string" and name ~= "" then counters().lc_last = name end
    end
  end
  -- what the guild learned before: every saved label defines its stat again, the saved records teach the enchants;
  -- then, every value's route known, the saved records keep none of the others' Only-you values (Roster.lua)
  C.Stats.LoadKnown()
  self.loaded = true
  C.Roster:PurgeCheck()
  -- load every counter and tracked value into the live table, and the levels of your first kills (Rules.lua's evidence)
  for _, def in ipairs(C.Stats.list) do if def.count or def.track then self.values[def.id] = readOne(def); self.at[def.id] = now() end end
  for id, v in pairs(counters()) do if type(id) == "string" and id:match("^k%d+$") and type(v) == "number" then self.values[id] = v end end
  -- the XP your level takes, sure at login (no ding is halfway through a loading screen)
  xpSample(C.Num("UnitLevel", "player"), C.Num("UnitXPMax", "player"), true)
  -- the instance you logged in to, your factions, then every stat
  self:InstanceCheck(initial, reloading)
  self:FactionPass()
  self:Summaries()
  self:ReadAll()
  C_Timer.After(TICK, C.Safe(tick, "sample: tick"))
  C_Timer.After(POLL, C.Safe(poll, "sample: poll"))
  C_Timer.After(HEARTBEAT, C.Safe(heartbeat, "sample: heartbeat"))
  C_Timer.After(60, C.Safe(day, "sample: day"))
  self:GearSoon()
end

-- the stats a module defines once Sample has started (Modules.lua): wired to their events and read now, as Start does
-- for the registry; the heartbeat reads them from then on. Before Start they are in the registry already and Start
-- does it
function S:Adopt(defs)
  if not self.started then return end
  for _, def in ipairs(defs) do
    local events = {}
    if def.on then for _, ev in ipairs(def.on) do on(ev, function() S:Schedule(def.id) end); events[#events + 1] = ev end end
    if def.count and def.count:match("^%u[%u_]+$") then on(def.count, function() S:Bump(def.id) end); events[#events + 1] = def.count end
    for _, ev in ipairs(events) do
      if ev == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- never: the client restricts it
      elseif ev:match("^UNIT_") then
        if not pcall(self.frame.RegisterUnitEvent, self.frame, ev, "player") then pcall(self.frame.RegisterEvent, self.frame, ev) end
      else pcall(self.frame.RegisterEvent, self.frame, ev) end
    end
    if def.count or def.track then self.values[def.id] = readOne(def); self.at[def.id] = now() else self:Read(def.id) end
  end
end

-- the session's XP, for the pace: across a ding, the rest of the old level counts too
local xpFrame = CreateFrame("Frame")
xpFrame:RegisterEvent("PLAYER_XP_UPDATE")
xpFrame:SetScript("OnEvent", C.Safe(function()
  local xp = C.Num("UnitXP", "player")
  if xp and T.lastXP then
    if xp >= T.lastXP then T.sessionXP = T.sessionXP + (xp - T.lastXP) else T.sessionXP = T.sessionXP + ((T.lastMax or 0) - T.lastXP) + xp end
  end
  T.lastXP = xp
  T.lastMax = C.Num("UnitXPMax", "player")
end, "sample: xp"))

-- every stat's current value, for Comm and the UI
function S:Value(id) return self.values[id] end
function S:Error(id) return self.err[id] end
