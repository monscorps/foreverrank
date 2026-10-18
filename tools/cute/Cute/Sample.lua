-- SPDX-License-Identifier: GPL-3.0-or-later
-- Sampling: reads every stat on its events and on a five-minute heartbeat, keeps the counters and the tracked
-- values this character accumulates (deaths, dances, time stood still), and tells Comm when something changed.
-- Every read runs under pcall; a read that errors stores nil and shows "?" with the error in the tooltip.
local _, C = ...
local S = { values = {}, at = {}, err = {}, dirty = {}, scheduled = {}, started = false }
C.Sample = S

local HEARTBEAT = 300  -- seconds between full passes
local SLICE = 20       -- stats read per slice of the heartbeat
local TICK = 5         -- the ticker that watches movement, ghosts, taxis and AFK

local function now() return C.Now() end
local function gtime() return (GetTime and GetTime()) or 0 end

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
  local ok, v = pcall(def.read)
  if not ok then return nil, tostring(v) end
  return C.Plain(v)
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
-- the heartbeat: the whole registry in slices, so no frame reads 120 stats
----------------------------------------------------------------------------
local beatIndex = 0
local function slice()
  local list = C.Stats.list
  if beatIndex >= #list then beatIndex = 0; return false end
  for i = beatIndex + 1, math.min(#list, beatIndex + SLICE) do
    local def = list[i]
    if not (def.count or def.track) then S:Read(def.id) end
  end
  beatIndex = math.min(#list, beatIndex + SLICE)
  return beatIndex < #list
end
local function heartbeat()
  if slice() then C_Timer.After(0.5, C.Safe(heartbeat, "sample: heartbeat")) else C_Timer.After(HEARTBEAT, C.Safe(heartbeat, "sample: heartbeat")) end
end

----------------------------------------------------------------------------
-- the day: counters marked daily reset when the date changes
----------------------------------------------------------------------------
local DAILY = { quests_today = true, deaths_today = true, levelups = true }
local function dayCheck()
  local ch = C.Char()
  local today = date and date("%Y-%m-%d") or ""
  if ch.day ~= today then
    ch.day = today
    for id in pairs(DAILY) do counters()[id] = 0; S.values[id] = 0; S.dirty[id] = true end
  end
end

----------------------------------------------------------------------------
-- the ticker: movement, ghosts, taxis, AFK, XP pace, time played
----------------------------------------------------------------------------
local T = { lastPos = nil, stillSince = nil, ghostSince = nil, lastGhostPos = nil, taxiSince = nil, wasAfk = false,
  xp = {}, sessionStart = nil, sessionXP = 0, falling = 0 }
S.track = T

local function pos()
  local y, x, _, inst = C.Get(UnitPosition, "player")
  if type(x) == "number" and type(y) == "number" then return x, y, inst end
end

local function tick()
  local t = gtime()
  local x, y, inst = pos()
  -- standing still
  if x and T.lastPos and T.lastPos[3] == inst and math.abs(T.lastPos[1] - x) < 0.5 and math.abs(T.lastPos[2] - y) < 0.5 then
    T.stillSince = T.stillSince or t
    local span = math.floor(t - T.stillSince)
    if span > S:Counter("still") then S:Set("still", span) end
  else T.stillSince = nil end
  -- ghosts: time and yards run
  if C.Get(UnitIsGhost, "player") == true then
    T.ghostSince = T.ghostSince or t
    if x and T.lastGhostPos and T.lastGhostPos[3] == inst then
      local dx, dy = x - T.lastGhostPos[1], y - T.lastGhostPos[2]
      S:Bump("ghost_yards", math.floor(math.sqrt(dx * dx + dy * dy)))
    end
    T.lastGhostPos = x and { x, y, inst } or nil
    S:Bump("ghost_time", TICK)
  else T.ghostSince, T.lastGhostPos = nil, nil end
  -- taxis
  if C.Get(UnitOnTaxi, "player") == true then
    T.taxiSince = T.taxiSince or t
  elseif T.taxiSince then
    local span = math.floor(t - T.taxiSince)
    T.taxiSince = nil
    T.lastFlightEnd = t
    S:Bump("flights")
    if span > S:Counter("longest_flight") then S:Set("longest_flight", span) end
  end
  -- AFK
  local afk = C.Get(UnitIsAFK, "player") == true
  if afk and not T.wasAfk then S:Bump("afk") end
  T.wasAfk = afk
  -- falling, for the fall-death heuristic
  if C.Get(IsFalling) == true then T.falling = t end
  -- time played and session
  S:Bump("played", TICK)
  S:Bump("played_lvl", TICK)
  if T.sessionStart then
    local span = math.floor(t - T.sessionStart)
    S:Set("session", span)
    if span > S:Counter("longest") then S:Set("longest", span) end
    local hours = span / 3600
    S:Set("xp_session", hours > 0.05 and math.floor(T.sessionXP / hours) or 0)
  end
  -- XP an hour over the last hour, from the ring of XP samples
  local xp = C.Num(UnitXP, "player")
  if xp then
    local ring = T.xp
    ring[#ring + 1] = { t, xp, C.Num(UnitLevel, "player") or 0 }
    while #ring > 0 and t - ring[1][1] > 3600 do table.remove(ring, 1) end
    if #ring >= 2 then
      local gained = 0
      for i = 2, #ring do
        local a, b = ring[i - 1], ring[i]
        if b[3] > a[3] then gained = gained + (T.lastMax or 0) - a[2] + b[2] else gained = gained + math.max(0, b[2] - a[2]) end
      end
      local span = (t - ring[1][1]) / 3600
      local rate = span > 0.05 and math.floor(gained / span) or 0
      S:Set("xp_hour", rate)
      local max = C.Num(UnitXPMax, "player")
      T.lastMax = max
      local lvl = C.Num(UnitLevel, "player")
      if rate > 0 and max and lvl and lvl < 60 then
        -- the levels left at Forever's XP curve, by the sum of the maxes of the levels ahead (approximated as this one)
        local left = (max - xp) + (59 - lvl) * max
        S:Set("to60", math.floor(left / rate))
      end
    end
  end
  C_Timer.After(TICK, C.Safe(tick, "sample: tick"))
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
  if t - T.falling < 2 then S:Bump("falls") end
  for i = 1, 3 do
    local name, value = C.Get(GetMirrorTimerInfo, i)
    if name == "BREATH" and type(value) == "number" and value <= 0 then S:Bump("drownings") end
    if name == "EXHAUSTION" and type(value) == "number" and value <= 0 then S:Bump("fatigue") end
  end
  local lvl = C.Num(UnitLevel, "player")
  if lvl and lvl < 60 then S:Bump("deaths_lvl") end
end)
on("PLAYER_LEVEL_UP", function() S:Set("played_lvl", 0) end)
on("PLAYER_MONEY", function()
  local m = C.Num(GetMoney)
  if not m then return end
  local last = T.money
  T.money = m
  if last and m > last then
    S:Bump("gold_earned", math.floor((m - last) / 10000))
    if T.merchant then S:Bump("vendor_sales", math.floor((m - last) / 10000)) end
    if T.guildBank then S:Bump("bank_out", math.floor((m - last) / 10000)) end
  elseif last and m < last and T.guildBank then S:Bump("bank_in", math.floor((last - m) / 10000)) end
end)
on("QUEST_TURNED_IN", function(_, _, money)
  money = C.Plain(money)
  if type(money) == "number" and money > 0 then S:Bump("gold_quests", math.floor(money / 10000)) end
end)
on("MERCHANT_SHOW", function() T.merchant = true end)
on("MERCHANT_CLOSED", function() T.merchant = false end)
on("GUILDBANKFRAME_OPENED", function() T.guildBank = true end)
on("GUILDBANKFRAME_CLOSED", function() T.guildBank = false end)
on("ZONE_CHANGED_NEW_AREA", function()
  local z = C.Get(GetZoneText)
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
  local _, kind = C.Get(GetInstanceInfo)
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
on("CHAT_MSG_WHISPER", function() S:Bump("whispers_n"); local h = math.max(0.25, (S:Counter("session") or 0) / 3600); S:Set("whispers", math.floor(S:Counter("whispers_n") / h)) end)
on("CHAT_MSG_GUILD", function(_, sender)
  sender = C.Plain(sender)
  local me, short = C.Me()
  if type(sender) == "string" and (sender == me or sender == short or C.Short(sender) == short) then S:Bump("gchat") end
end)
on("TAXIMAP_OPENED", function()
  local n = C.Num(NumTaxiNodes)
  if not n then return end
  local known = 0
  for i = 1, n do local kind = C.Get(TaxiNodeGetType, i); if kind == "REACHABLE" or kind == "CURRENT" then known = known + 1 end end
  if known > 0 then S:Set("flights_known", known) end
end)
on("TIME_PLAYED_MSG", function(total, level)
  total, level = C.Plain(total), C.Plain(level)
  if type(total) == "number" then S:Set("played", total) end
  if type(level) == "number" then S:Set("played_lvl", level) end
end)
-- recipes, as the trade skill window lists them
on("TRADE_SKILL_LIST_UPDATE", function()
  local all = C.Get(C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs)
  local info = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo
  if type(all) ~= "table" or not info then return end
  local ch = C.Char()
  ch.recipes = ch.recipes or {}
  local learned = {}
  for _, id in ipairs(all) do
    local r = C.Get(info, id)
    if type(r) == "table" and C.Plain(r.learned) == true then learned[id] = true end
  end
  local prof = C.Get(C_TradeSkillUI.GetTradeSkillLine)
  prof = type(prof) == "string" and prof or (type(prof) == "number" and tostring(prof)) or "?"
  ch.recipes[prof] = learned
  local n, raid = 0, {}
  for _, set in pairs(ch.recipes) do for id in pairs(set) do n = n + 1; raid[id] = true end end
  S:Set("recipes", n)
  local def = C.Stats.byId.raid_recipes
  local have = {}
  for _, e in ipairs(def.of) do if raid[e[1]] then have[e[1]] = true end end
  counters().raid_recipes = have
  S.values.raid_recipes, S.at.raid_recipes, S.dirty.raid_recipes = have, now(), true
  S:Changed()
end)
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
  end
  if JumpOrAscendStart then hooksecurefunc("JumpOrAscendStart", C.Safe(function() S:Bump("jumps") end, "jump hook")) end
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) and "C_ChatInfo" or (SendChatMessage and "global")
  local function said(text, kind)
    text, kind = C.Plain(text), C.Plain(kind)
    if type(text) ~= "string" then return end
    if kind ~= "PARTY" and kind ~= "RAID" and kind ~= "INSTANCE_CHAT" then return end
    local t = text:lower()
    if t:find("where are you", 1, true) or t:find("where r u", 1, true) or t:match("%f[%w]wya%f[%W]") or t:find("where are u", 1, true) then S:Bump("where") end
  end
  if send == "C_ChatInfo" then hooksecurefunc(C_ChatInfo, "SendChatMessage", C.Safe(said, "chat hook"))
  elseif send == "global" then hooksecurefunc("SendChatMessage", C.Safe(said, "chat hook")) end
end

----------------------------------------------------------------------------
-- start
----------------------------------------------------------------------------
function S:Start()
  if self.started then self:ReadAll(); return end
  self.started = true
  wire()
  local f = CreateFrame("Frame")
  self.frame = f
  f:SetScript("OnEvent", C.Safe(function(_, event, ...)
    for _, fn in ipairs(EVENTS[event] or {}) do fn(...) end
  end, "sample: event"))
  for event in pairs(EVENTS) do
    if event ~= "COMBAT_LOG_EVENT_UNFILTERED" then pcall(f.RegisterEvent, f, event) end
  end
  hooks()
  dayCheck()
  -- this login
  T.sessionStart = gtime()
  T.sessionXP = 0
  T.money = C.Num(GetMoney)
  S:Bump("logins")
  S:Set("last_login", now())
  -- the game says how long you have played; its chat line is the price
  if RequestTimePlayed then pcall(RequestTimePlayed) end
  -- load every counter and tracked value into the live table
  for _, def in ipairs(C.Stats.list) do if def.count or def.track then self.values[def.id] = readOne(def); self.at[def.id] = now() end end
  self:ReadAll()
  C_Timer.After(TICK, C.Safe(tick, "sample: tick"))
  C_Timer.After(HEARTBEAT, C.Safe(heartbeat, "sample: heartbeat"))
  C_Timer.After(60, C.Safe(function() dayCheck(); C_Timer.After(600, dayCheck) end, "sample: day"))
end

-- the session's XP, for the pace
C.frame:HookScript("OnEvent", function(_, event)
  if event == "PLAYER_ENTERING_WORLD" then T.sessionXP = 0 end
end)
local xpFrame = CreateFrame("Frame")
xpFrame:RegisterEvent("PLAYER_XP_UPDATE")
xpFrame:SetScript("OnEvent", C.Safe(function()
  local xp = C.Num(UnitXP, "player")
  if xp and T.lastXP then
    if xp >= T.lastXP then T.sessionXP = T.sessionXP + (xp - T.lastXP) else T.sessionXP = T.sessionXP + xp end
  end
  T.lastXP = xp
end, "sample: xp"))

-- every stat's current value, for Comm and the UI
function S:Value(id) return self.values[id] end
function S:Error(id) return self.err[id] end
