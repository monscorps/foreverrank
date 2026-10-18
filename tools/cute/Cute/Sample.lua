-- SPDX-License-Identifier: GPL-3.0-or-later
-- Sampling: reads every stat on its events and on a five-minute heartbeat, keeps the counters and the tracked
-- values this character accumulates (deaths, dances, time stood still), probes the game's statistics at login and
-- re-reads them in one coalesced pass, and tells Comm when something changed.
-- Every read runs under pcall; a read that errors stores nil and shows "?" with the error in the tooltip.
local _, C = ...
local S = { values = {}, at = {}, err = {}, dirty = {}, scheduled = {}, started = false }
C.Sample = S

local HEARTBEAT = 300  -- seconds between full passes
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
function S:Set(id, v)
  if self.values[id] == v then return end
  local def = C.Stats.byId[id]
  if def and (def.count or def.track) then counters()[id] = v end
  self.values[id], self.at[id], self.err[id] = v, now(), nil
  self.dirty[id] = true
  self:Changed()
end
function S:Bump(id, n)
  self:Set(id, (self:Counter(id) or 0) + (n or 1))
end

----------------------------------------------------------------------------
-- reading
----------------------------------------------------------------------------
local function readOne(def)
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
  if not same(self.values[id], v) then
    self.values[id], self.at[id] = v, now()
    self.dirty[id] = true
    self:Changed()
  elseif self.at[id] == nil then self.at[id] = now() end
end

function S:ReadAll()
  for _, def in ipairs(C.Stats.list) do self:Read(def.id) end
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

-- the XP each level takes in Classic, 1 to 59; Forever's own curve is read off UnitXPMax and scales these
local XP_TO_LEVEL = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8700, 9800, 11000, 12300, 13600, 15000, 16400, 17800, 19300, 20800,
  22400, 24000, 25500, 27200, 28900, 30500, 32200, 33900, 36300, 38800, 41600, 44600, 48000, 51400, 55000, 58700, 62400, 66200, 70200, 74300,
  78500, 82800, 87100, 91600, 96300, 101000, 105800, 110700, 115700, 120900, 126100, 131500, 137000, 142500, 148200, 154000, 159900, 165800, 171800 }
S.XP_TO_LEVEL = XP_TO_LEVEL
-- the XP left to 60 from (lvl, xp, max): this level's rest plus every level ahead, at the ratio of this client's
-- max to Classic's for the current level
local function xpLeft(lvl, xp, max)
  local base = XP_TO_LEVEL[lvl]
  if not base or base <= 0 then return nil end
  local scale = max / base
  local left = max - xp
  for l = lvl + 1, 59 do left = left + XP_TO_LEVEL[l] * scale end
  return left
end
S.XPLeft = xpLeft

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
local EVENTS = {}
local function on(event, fn) EVENTS[event] = EVENTS[event] or {}; table.insert(EVENTS[event], fn) end

-- stats re-read on their events, counters bumped on theirs
local function wire()
  for _, def in ipairs(C.Stats.list) do
    if def.on then for _, ev in ipairs(def.on) do on(ev, function() S:Schedule(def.id) end) end end
    if def.count and def.count:match("^%u[%u_]+$") and not def.count:match("_ENTERED$") then on(def.count, function() S:Bump(def.id) end) end
  end
end

on("PLAYER_DEAD", function()
  local t = gtime()
  if t - T.falling < 3 then S:Bump("falls") end
  -- the bar at zero now, or seen at zero by the poll in the last three seconds (the timer stops as you die)
  if mirrorEmpty("BREATH") or (T.mirrorEmpty.BREATH and t - T.mirrorEmpty.BREATH < 3) then S:Bump("drownings") end
  if mirrorEmpty("EXHAUSTION") or (T.mirrorEmpty.EXHAUSTION and t - T.mirrorEmpty.EXHAUSTION < 3) then S:Bump("fatigue") end
  local lvl = C.Num("UnitLevel", "player")
  if lvl and lvl < 60 then S:Bump("deaths_lvl") end
end)
on("PLAYER_LEVEL_UP", function() S:Set("played_lvl", 0) end)
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
-- defined late are read at once; their first values go out with the next flush, and an asker gets them in full
local RETRY = { 30, 120 }
function S:ProbeGame(attempt)
  attempt = attempt or 1
  local ok, what, again = C.Stats.ProbeGame()
  if ok then
    if attempt > 1 then
      for _, def in ipairs(C.Stats.byCat.game) do self:Read(def.id) end
      if C.UI and C.UI.Refresh then C.UI:Refresh() end
    end
    return
  end
  if again and RETRY[attempt] then
    C_Timer.After(RETRY[attempt], C.Safe(function() S:ProbeGame(attempt + 1) end, "sample: statistics probe"))
  else
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
on("PLAYER_ENTERING_WORLD", function()
  local _, kind = C.Get("GetInstanceInfo")
  if kind == "party" and not T.inDungeon then S:Bump("dungeons") end
  if kind == "raid" and not T.inRaid then S:Bump("raids"); S:Bump("weekly_raids") end
  T.inDungeon, T.inRaid = kind == "party", kind == "raid"
end)
on("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellId)
  if unit ~= "player" then return end
  spellId = C.Plain(spellId)
  if spellId == 8690 then
    S:Bump("hearths")
    if T.lastFlightEnd and gtime() - T.lastFlightEnd < 120 then S:Bump("hearth_waste") end
  elseif spellId == 7620 or spellId == 7731 or spellId == 7732 or spellId == 18248 then T.fishingAt = gtime() end
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
-- raid recipes: asked of the trade skill window by spell id while it is open (there is no recipe list to walk on
-- this client); a recipe once seen learned stays learned
local function readRecipes()
  local info = api("C_TradeSkillUI", "GetRecipeInfo")
  if not info then return end
  local def = C.Stats.byId.raid_recipes
  local old = counters().raid_recipes
  local have, changed = {}, false
  if type(old) == "table" then for k in pairs(old) do have[k] = true end end
  for _, e in ipairs(def.of) do
    local r = C.Get(info, e[1])
    if type(r) == "table" and C.Plain(r.learned) == true and not have[e[1]] then have[e[1]] = true; changed = true end
  end
  if changed then S:Set("raid_recipes", have) end
end
on("TRADE_SKILL_LIST_UPDATE", readRecipes)
on("TRADE_SKILL_SHOW", readRecipes)
-- consumables that leave your bags in a raid
on("BAG_UPDATE_DELAYED", function()
  if not T.inRaid then return end
  local total = 0
  for _, id in ipairs({ "pot_health", "pot_mana", "flasks", "elixirs", "food", "protpots" }) do
    local def = C.Stats.byId[id]
    local ok, v = pcall(def.read)
    if ok and type(C.Plain(v)) == "number" then total = total + v end
  end
  if T.consumables and total < T.consumables then S:Bump("consumed", T.consumables - total) end
  T.consumables = total
end)

----------------------------------------------------------------------------
-- hooks: the game's own functions, after they run (hooksecurefunc taints nothing)
----------------------------------------------------------------------------
local function isMe(who)
  local me, short = C.Me()
  return type(who) == "string" and (who == me or who == short or C.Short(who) == short)
end
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
    on("CHAT_MSG_TEXT_EMOTE", function(text, who)
      text, who = C.Plain(text), C.Plain(who)
      if not isMe(who) then return end
      S:Bump("emotes")
      if type(text) == "string" then
        local t = text:lower()
        if t:find("^you dance") then S:Bump("dance") elseif t:find("^you sit") then S:Bump("sit") end
      end
    end)
  end
  if JumpOrAscendStart then hooksecurefunc("JumpOrAscendStart", C.Safe(function() S:Bump("jumps") end, "jump hook")) end
  -- your own lines, seen as you send them: the hook gets the caller's plain arguments where the chat events' text and
  -- sender are secret in dungeons and raids
  if C_ChatInfo and C_ChatInfo.SendChatMessage then
    hooksecurefunc(C_ChatInfo, "SendChatMessage", C.Safe(function(text, kind)
      text, kind = C.Plain(text), C.Plain(kind)
      if type(text) ~= "string" then return end
      if kind == "GUILD" then S:Bump("gchat"); return end
      if kind ~= "PARTY" and kind ~= "RAID" and kind ~= "INSTANCE_CHAT" then return end
      local t = text:lower()
      if t:find("where are you", 1, true) or t:find("where r u", 1, true) or t:match("%f[%w]wya%f[%W]") or t:find("where are u", 1, true) then S:Bump("where") end
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
    for _, fn in ipairs(EVENTS[event] or {}) do fn(...) end
  end, "sample: event"))
  for event in pairs(EVENTS) do
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
      -- never: the client restricts it
    elseif event:match("^UNIT_") and f.RegisterUnitEvent then
      -- yours only, not every unit in sight
      pcall(f.RegisterUnitEvent, f, event, "player")
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
  -- load every counter and tracked value into the live table
  for _, def in ipairs(C.Stats.list) do if def.count or def.track then self.values[def.id] = readOne(def); self.at[def.id] = now() end end
  self:ReadAll()
  C_Timer.After(TICK, C.Safe(tick, "sample: tick"))
  C_Timer.After(POLL, C.Safe(poll, "sample: poll"))
  C_Timer.After(HEARTBEAT, C.Safe(heartbeat, "sample: heartbeat"))
  C_Timer.After(60, C.Safe(day, "sample: day"))
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
