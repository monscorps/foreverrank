-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank party sync. QuestBank users in your party, raid and guild share their level, banked XP,
-- plan and hand-in run, so you can see who needs which dungeon and run it together, copy a
-- friend's plan, and follow each other's run. It also passes on the XP numbers each game reports.
-- Small messages on the addon channel, a few a second at most; nothing goes out while sharing is off.
--   1S|level|xp|fac|class|banked*100|plan*100|at60*100|runMin|runN|runXP     status
--   1Q|part|parts|id.code[have/need],...                                    quests (b banked, a in the log with progress, p to fetch)
--   1L|id:xp:level,...                                                         XP the game reported
--   1R                                                                         please send yours
local _, QB = ...
local S = { members = {}, out = {}, live = {} }
QB.Sync = S
local PREFIX = "QuestBank"
local STALE = 30 * 60

local function now() return GetTime and GetTime() or 0 end

-- "sent", "later" (the game's addon throttle said too fast) or "drop" (not in a group any more,
-- no such player, a bad channel: trying again won't help)
local function send(msg, channel, target)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return "sent" end
  if ChatThrottleLib and ChatThrottleLib.SendAddonMessage then
    ChatThrottleLib:SendAddonMessage("NORMAL", PREFIX, msg, channel, target)
    return "sent"
  end
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel, target)
  if not ok then return "drop" end
  if res == nil or res == true or res == 0 then return "sent" end
  if res == 3 or res == 8 then return "later" end -- Enum.SendAddonMessageResult AddonMessageThrottle, ChannelThrottle
  return "drop"
end

-- the queue: about one message a second, the rate the game refills its addon allowance
local pumping = false
local pump
pump = QB.Safe(function()
  local m = S.out[1]
  if not m then pumping = false return end
  local r = send(m[1], m[2], m[3])
  if r == "later" then
    C_Timer.After(3.0, pump)
  else
    table.remove(S.out, 1)
    C_Timer.After(1.0, pump)
  end
end, "party sync: sending")
local function queue(msg, channel, target)
  for _, m in ipairs(S.out) do
    if m[1] == msg and m[2] == channel and m[3] == target then return end
  end
  S.out[#S.out + 1] = { msg, channel, target }
  if not pumping then pumping = true; C_Timer.After(0.05, pump) end
end

local function groupChannel()
  if not (IsInGroup and IsInGroup()) then return nil end
  if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then return "INSTANCE_CHAT" end
  return (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
end

local function channels()
  local share = QB:Settings().share
  local out = {}
  local g = share.party and groupChannel()
  if g then out[#out + 1] = g end
  if share.guild and IsInGuild and IsInGuild() then out[#out + 1] = "GUILD" end
  return out
end

----------------------------------------------------------------------------
-- what we send
----------------------------------------------------------------------------
local function statusMsg()
  local s = QB.state
  local nowR, plan = QB.routeNow, QB.routePlan
  local run = QB.Run.Get()
  local got, n = QB.Run.Totals()
  local _, class = UnitClass("player")
  return string.format("1S|%d|%d|%s|%s|%d|%d|%d|%d|%d|%d", s.level or 0, s.xp or 0, QB.faction or "A", class or "",
    math.floor((nowR and nowR.level or 0) * 100), math.floor((plan and plan.level or 0) * 100), math.floor((plan and plan.at60 or 0) * 100),
    run and math.floor(QB.Run.Elapsed()) or -1, n or 0, got or 0)
end

local function questMsgs()
  local parts = {}
  local codes = { banked = "b", active = "a" }
  for _, e in ipairs(QB:RouteEntries("plan")) do
    local c = codes[e.st.code] or (e.st.code ~= "follow" and "p") or nil
    if c then
      local have, need = QB:Progress(e.q.id)
      parts[#parts + 1] = e.q.id .. "." .. c .. ((c == "a" and need) and (have .. "/" .. need) or "")
    end
  end
  local msgs, cur = {}, {}
  local len = 0
  for _, p in ipairs(parts) do
    if len + #p + 1 > 220 then msgs[#msgs + 1] = table.concat(cur, ","); cur, len = {}, 0 end
    cur[#cur + 1] = p
    len = len + #p + 1
  end
  if #cur > 0 or #msgs == 0 then msgs[#msgs + 1] = table.concat(cur, ",") end
  for i, body in ipairs(msgs) do msgs[i] = string.format("1Q|%d|%d|%s", i, #msgs, body) end
  return msgs, table.concat(parts, ",")
end

function S:Broadcast(force)
  if not self.ready then return end
  local chans = channels()
  if #chans == 0 then
    if force then QB:Print("Not in a party or guild, or sharing is off. /qb sync Name shares with one friend.") end
    return
  end
  local status = statusMsg()
  local msgs, sig = questMsgs()
  for _, ch in ipairs(chans) do
    if force or status ~= self.lastStatus then queue(status, ch) end
    if force or sig ~= self.lastQuests then for _, m in ipairs(msgs) do queue(m, ch) end end
  end
  self.lastStatus, self.lastQuests = status, sig
  if force then QB:Print("Shared your bank with " .. table.concat(chans, " and "):lower() .. ".") end
end

function S:Whisper(name)
  if not self.ready or not name or name == "" then return end
  queue(statusMsg(), "WHISPER", name)
  for _, m in ipairs((questMsgs())) do queue(m, "WHISPER", name) end
  queue("1R", "WHISPER", name)
  QB:Print("Sent your bank to " .. name .. " and asked for theirs. They need QuestBank too.")
end

-- a change: tell the others a few seconds later, once
function S:Changed()
  if not self.ready or self.waiting then return end
  self.waiting = true
  C_Timer.After(3, QB.Safe(function()
    S.waiting = false
    S:Broadcast(false)
  end, "party sync: sharing"))
end

function S:QueueLive(id, xp, level)
  self.live[#self.live + 1] = id .. ":" .. xp .. ":" .. level
  if self.liveWaiting then return end
  self.liveWaiting = true
  C_Timer.After(5, QB.Safe(function()
    S.liveWaiting = false
    local chans = channels()
    while #S.live > 0 do
      local batch = {}
      while #S.live > 0 and #batch < 14 do batch[#batch + 1] = table.remove(S.live, 1) end
      for _, ch in ipairs(chans) do queue("1L|" .. table.concat(batch, ","), ch) end
    end
  end, "party sync: XP"))
end

----------------------------------------------------------------------------
-- what we receive
----------------------------------------------------------------------------
local function split(s, sep)
  local out = {}
  for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
  return out
end

-- the game echoes party and guild messages back to the sender; the name decides, not how the realm is written
local function isMe(sender)
  local name = sender and sender:match("^([^%-]+)")
  return name ~= nil and name == UnitName("player")
end
S.IsMe = isMe

function S:Receive(msg, channel, sender)
  if not sender or type(msg) ~= "string" or #msg > 255 then return end
  if isMe(sender) then return end
  local kind = msg:sub(1, 2)
  local m = self.members[sender]
  if not m and kind ~= "1R" then
    m = { key = sender, name = sender:match("^([^%-]+)") or sender }
    self.members[sender] = m
  end
  if m then m.seen, m.via = now(), channel end
  if kind == "1S" then
    local f = split(msg, "|")
    m.level, m.xp, m.fac, m.class = tonumber(f[2]), tonumber(f[3]), f[4] == "H" and "H" or "A", f[5]
    m.banked, m.plan, m.at60 = (tonumber(f[6]) or 0) / 100, (tonumber(f[7]) or 0) / 100, (tonumber(f[8]) or 0) / 100
    local runMin = tonumber(f[9]) or -1
    m.runStart = runMin >= 0 or nil
    m.runMin, m.runN, m.runXP = runMin, tonumber(f[10]) or 0, tonumber(f[11]) or 0
  elseif kind == "1Q" then
    local part, parts, body = msg:match("^1Q|(%d+)|(%d+)|(.*)$")
    part, parts = tonumber(part), tonumber(parts)
    if not (part and parts) or parts > 20 or part > parts then return end
    if part == 1 or not m.pending then m.pending = {} end
    for id, code, prog in body:gmatch("(%d+)%.(%a)([%d/]*)") do
      m.pending[tonumber(id)] = { code = code, prog = prog ~= "" and prog or nil }
    end
    if part == parts then m.quests, m.pending = m.pending, nil end
  elseif kind == "1L" then
    for id, xp, lvl in msg:gmatch("(%d+):(%d+):(%d+)") do
      QB.Live.Record(tonumber(id), tonumber(xp), tonumber(lvl), "party")
    end
  elseif kind == "1R" then
    local target = channel == "WHISPER" and sender or nil
    if target then
      queue(statusMsg(), "WHISPER", target)
      for _, q in ipairs((questMsgs())) do queue(q, "WHISPER", target) end
    else
      self.lastStatus, self.lastQuests = nil, nil
      self:Changed()
    end
    return
  end
  if QB.UI and QB.UI.frame and QB.UI.frame:IsShown() and QB.UI.tab == 4 then QB.UI:Refresh() end
end

----------------------------------------------------------------------------
-- for the Party page
----------------------------------------------------------------------------
function S:Members()
  local out = {}
  local t = now()
  for key, m in pairs(self.members) do
    m.age = t - (m.seen or t)
    if m.age > STALE then self.members[key] = nil elseif m.level then out[#out + 1] = m end
  end
  table.sort(out, function(a, b)
    if (a.runStart or false) ~= (b.runStart or false) then return a.runStart or false end
    return (a.age or 0) < (b.age or 0)
  end)
  return out
end

-- every dungeon where you or the others still have quests to do: which quests, who needs each one,
-- and how far along they are. Yours are there when you're on your own too.
function S:Dungeons()
  local D = QB.Data
  local level = math.max(QB.state.level or 20, 20)
  local cats, list = {}, {}
  local function note(catIdx, qid, who, name, me, code, prog)
    local cat = D.CAT[catIdx]
    if not (cat and cat.dungeon) then return end
    local c = cats[catIdx]
    if not c then
      c = { cat = cat, quests = {}, byQ = {}, people = {}, seen = {}, xp = 0, left = 0 }
      cats[catIdx] = c
      list[#list + 1] = c
    end
    local e = c.byQ[qid]
    if not e then
      e = { id = qid, q = QB.Quest.Get(qid), who = {}, need = 0 }
      c.byQ[qid] = e
      c.quests[#c.quests + 1] = e
    end
    e.who[#e.who + 1] = { name = name, me = me, code = code, prog = prog }
    if code ~= "b" then
      e.need = e.need + 1
      c.left = c.left + 1
      if e.q then c.xp = c.xp + QB.Model.XpAt(e.q, level) end
    end
    if not c.seen[who] then c.seen[who] = true; c.people[#c.people + 1] = name end
  end
  for _, e in ipairs(QB:RouteEntries("plan")) do
    local code = e.st.code == "banked" and "b" or (e.st.code == "active" and "a" or "p")
    local have, need = QB:Progress(e.q.id)
    note(D.Q[e.q.id][8], e.q.id, "me", "You", true, code, need and (have .. "/" .. need) or nil)
  end
  for key, m in pairs(self.members) do
    if m.quests and m.fac == QB.faction then
      for id, v in pairs(m.quests) do
        local r = D.Q[id]
        if r then note(r[8], id, key, m.name, false, v.code, v.prog) end
      end
    end
  end
  local out = {}
  for _, c in ipairs(list) do
    if c.left > 0 then
      table.sort(c.quests, function(a, b)
        if a.need ~= b.need then return a.need > b.need end
        return (a.q and a.q.lvl or 0) < (b.q and b.q.lvl or 0)
      end)
      out[#out + 1] = c
    end
  end
  table.sort(out, function(a, b)
    if #a.people ~= #b.people then return #a.people > #b.people end
    return a.xp > b.xp
  end)
  return out
end

function S:MemberTooltip(tip, key)
  local m = self.members[key]
  if not m then return end
  tip:AddLine(m.name, 1, 0.82, 0)
  tip:AddLine(string.format("Level %s, banked to %.1f, plan to %.1f (%.1f in the first hour)", m.level or "?", m.banked or 0, m.plan or 0, m.at60 or 0), 1, 1, 1, true)
  if m.runStart then tip:AddLine(string.format("Running for %s: %d handed in, +%s XP", QB.Clock(m.runMin), m.runN, QB.Comma(m.runXP)), 0.4, 1, 0.4) end
  if not m.quests then tip:AddLine("Their quest list hasn't arrived yet.", 0.6, 0.6, 0.6) return end
  local list = {}
  for id, v in pairs(m.quests) do
    local q = QB.Quest.Get(id)
    if q then list[#list + 1] = { q = q, code = v.code, prog = v.prog, xp = QB.Model.XpAt(q, math.max(m.level or 20, 20)) } end
  end
  table.sort(list, function(a, b) return a.xp > b.xp end)
  local label = { b = "banked", a = "in their log", p = "to pick up" }
  for i = 1, math.min(12, #list) do
    local it = list[i]
    local shared = QB.state.log[it.q.id] and "  (you too)" or ""
    local state = it.code == "a" and it.prog and ("in their log, " .. it.prog) or (label[it.code] or "")
    tip:AddDoubleLine(it.q.name .. shared, state .. ", " .. QB.Short(it.xp), 1, 1, 1, 0.6, 1, 0.6)
  end
  if #list > 12 then tip:AddLine(string.format("and %d more", #list - 12), 0.6, 0.6, 0.6) end
end

-- add their quests that you can do to your plan
function S:CopyPlan(key)
  local m = self.members[key]
  if not (m and m.quests) then return 0 end
  local plan = QB:Plan()
  local n = 0
  for id in pairs(m.quests) do
    local q = QB.Quest.Get(id)
    if q and QB.Quest.ForMe(q) and not QB.state.log[id] and not plan.add[id] and not QB.API.IsDone(id) then
      plan.add[id] = true
      n = n + 1
    end
  end
  if n > 0 then QB:MarkDirty() end
  return n
end

----------------------------------------------------------------------------
-- events
----------------------------------------------------------------------------
function S:Init()
  if self.ready then return end
  if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return end
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  self.ready = true
  local f = CreateFrame("Frame")
  self.frame = f
  f:SetScript("OnEvent", QB.Safe(function(_, event, a1, a2, a3, a4)
    if event == "CHAT_MSG_ADDON" then
      if a1 == PREFIX then S:Receive(a2, a3, a4) end
    elseif event == "GROUP_ROSTER_UPDATE" then
      local ch = groupChannel()
      if ch and ch ~= S.lastGroup and QB:Settings().share.party then
        S.lastStatus, S.lastQuests = nil, nil
        queue("1R", ch)
        S:Changed()
      end
      S.lastGroup = ch
    end
  end, "party sync: receiving"))
  f:RegisterEvent("CHAT_MSG_ADDON")
  f:RegisterEvent("GROUP_ROSTER_UPDATE")
  -- say hello once the plan is ready, and keep a run visible to the others
  C_Timer.After(12, QB.Safe(function()
    local chans = channels()
    for _, ch in ipairs(chans) do queue("1R", ch) end
    S:Changed()
  end, "party sync: hello"))
  local beat
  beat = QB.Safe(function()
    C_Timer.After(60, beat)
    if QB.Run.Get() then S.lastStatus = nil; S:Broadcast(false) end
  end, "party sync: run")
  C_Timer.After(60, beat)
end
