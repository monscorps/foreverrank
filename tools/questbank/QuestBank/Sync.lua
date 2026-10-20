-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank party sync. QuestBank users in your party, raid and guild share their level, banked XP,
-- plan and hand-in run, so you can see who needs which dungeon and run it together, copy a
-- friend's plan, and follow each other's run. It also passes on the XP numbers each game reports.
-- Small messages on the addon channel, a few a second at most; nothing goes out while sharing is off.
--   1S|level|xp|fac|class|banked*100|plan*100|at60*100|runMin|runN|runXP|version|guid   status
--   1Q|part|parts|id.code[have/need],...                                    quests (b banked, a in the log with progress, p to fetch)
--   1L|id:xp:level,...                                                         XP the game reported
--   1R                                                                         please send yours
--   1G|text                                                                    the Guide's first step (6.0), for the others' step frames
local _, QB = ...
local S = { members = {}, out = {}, live = {}, stepVer = 0 }
QB.Sync = S
-- stepVer: up whenever a member comes, goes, or sends a step or status (1G, 1S), so the Guide's member-step list
-- (G.MemberSteps) and the step frame can tell nothing changed without a table or a string a tick
local function memberChanged() S.stepVer = S.stepVer + 1 end
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
  -- the GUID's tail names this character even when chat gives the sender a surname the name API doesn't
  local guid = (UnitGUID and UnitGUID("player")) or ""
  return string.format("1S|%d|%d|%s|%s|%d|%d|%d|%d|%d|%d|%s|%s", s.level or 0, s.xp or 0, QB.faction or "A", class or "",
    math.floor((nowR and nowR.level or 0) * 100), math.floor((plan and plan.level or 0) * 100), math.floor((plan and plan.at60 or 0) * 100),
    run and math.floor(QB.Run.Elapsed()) or -1, n or 0, got or 0, QB.version, guid:sub(-10))
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
  if force then QB:Print("Shared your quests with " .. table.concat(chans, " and "):lower() .. ".") end
end

function S:Whisper(name)
  if not self.ready or not name or name == "" then return end
  queue(statusMsg(), "WHISPER", name)
  for _, m in ipairs((questMsgs())) do queue(m, "WHISPER", name) end
  queue("1R", "WHISPER", name)
  QB:Print("Sent your quests to " .. name .. " and asked for theirs. They need QuestBank too.")
end

-- 1G|text: your Guide's first step, for the others' step frames (6.0, Guide.lua). Sent to the group when it changes,
-- at most once every STEP_GAP seconds (a change within the gap goes when it ends), cut to STEP_LEN bytes, no escape
-- codes (the Guide's texts are plain). An empty text clears it for them
local STEP_GAP, STEP_LEN = 10, 120
function S:Step(text)
  if not self.ready or type(text) ~= "string" then return end
  text = text:gsub("|", ""):sub(1, STEP_LEN)
  if text == (self.lastStep or "") then return end
  local t = now()
  if self.stepAt and t - self.stepAt < STEP_GAP then
    if not self.stepSoon then
      self.stepSoon = true
      C_Timer.After(STEP_GAP - (t - self.stepAt), QB.Safe(function()
        S.stepSoon = false
        S:Step(QB.Guide and QB.Guide.Text(QB.Guide.Current()) or "")
      end, "party sync: step"))
    end
    return
  end
  local chan = groupChannel()
  if not chan or not QB:Settings().share.party then return end
  self.lastStep, self.stepAt = text, t
  queue("1G|" .. text, chan)
end

-- a change: tell the others a few seconds later, once (the Guide's step at once, when it changed)
function S:Changed()
  if not self.ready then return end
  if QB.Guide and QB.Guide.Current then self:Step(QB.Guide.Text(QB.Guide.Current())) end
  if self.waiting then return end
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
-- posts in party and guild chat, which people read: only ever sent from the Post button (UI:PostDialog)
----------------------------------------------------------------------------
function S.PostChannels()
  local out = {}
  local g = groupChannel()
  if g then out.party = { channel = g, label = g == "RAID" and "Raid" or (g == "INSTANCE_CHAT" and "Instance" or "Party") } end
  if IsInGuild and IsInGuild() then out.guild = { channel = "GUILD", label = "Guild" } end
  return out
end

-- chat takes one line of at most 255 bytes, and no escape codes
function S.CleanPost(msg)
  msg = (msg or ""):gsub("[\r\n]+", " "):gsub("|", "/"):gsub("^%s+", ""):gsub("%s+$", "")
  if #msg > 255 then msg = msg:sub(1, 255):gsub("[\192-\255][\128-\191]*$", "") end
  return msg
end

-- post it where you ticked; how many channels took it
function S:Post(msg, want)
  msg = S.CleanPost(msg)
  if msg == "" then return 0 end
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  local ch, n = S.PostChannels(), 0
  for _, key in ipairs({ "party", "guild" }) do
    if want[key] and ch[key] then
      local ok, err = pcall(send, msg, ch[key].channel)
      if ok then n = n + 1 else QB.Err.Record(tostring(err), "", "posting in " .. ch[key].label:lower() .. " chat") end
    end
  end
  return n
end

----------------------------------------------------------------------------
-- what we receive
----------------------------------------------------------------------------
local function split(s, sep)
  local out = {}
  for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
  return out
end

-- the game echoes party and guild messages back to the sender. The realm may be written any way, and in
-- Forever the sender carries a surname the name API doesn't ("Helga Bluntforce" against "Helga"), so a
-- name match isn't enough: the first echoed status message carries our GUID, and that names the sender
-- string that is us from then on.
local function isMe(sender)
  if not sender then return false end
  if S.mySender and sender == S.mySender then return true end
  local name = sender:match("^([^%-]+)")
  if name == UnitName("player") then return true end
  local full = UnitFullName and UnitFullName("player")
  return full ~= nil and name == full
end
S.IsMe = isMe

local function statusIsMine(msg)
  local tail = msg:match("^1S|.-|([^|]*)$")
  local guid = (UnitGUID and UnitGUID("player")) or ""
  return tail ~= nil and tail ~= "" and #guid >= 10 and tail == guid:sub(-10)
end

function S:Receive(msg, channel, sender)
  if not sender or type(msg) ~= "string" or #msg > 255 then return end
  if isMe(sender) then return end
  local kind = msg:sub(1, 2)
  if kind == "1V" then
    -- the realm-wide version notice: never a party member, never anything else
    local v = channel == "CHANNEL" and msg:match("^1V|(%d+%.%d+%.?%d*)$")
    if v then self:HeardVersion(v, sender) end
    return
  end
  if kind == "1S" and statusIsMine(msg) then
    -- our own echo, under a sender string we didn't recognise: it is us from now on
    S.mySender = sender
    if self.members[sender] then memberChanged() end
    self.members[sender] = nil
    return
  end
  local m = self.members[sender]
  if not m and kind ~= "1R" then
    m = { key = sender, name = sender:match("^([^%-]+)") or sender }
    self.members[sender] = m
    memberChanged()
  end
  if m then m.seen, m.via = now(), channel end
  if kind == "1S" then
    local f = split(msg, "|")
    if m.class ~= f[5] or m.level == nil then memberChanged() end -- (the frame colours the name by class; a member is listed once its level is known)
    m.level, m.xp, m.fac, m.class = tonumber(f[2]), tonumber(f[3]), f[4] == "H" and "H" or "A", f[5]
    m.banked, m.plan, m.at60 = (tonumber(f[6]) or 0) / 100, (tonumber(f[7]) or 0) / 100, (tonumber(f[8]) or 0) / 100
    local runMin = tonumber(f[9]) or -1
    m.runStart = runMin >= 0 or nil
    m.runMin, m.runN, m.runXP = runMin, tonumber(f[10]) or 0, tonumber(f[11]) or 0
    m.version = f[12] and f[12]:match("^%d+%.%d+%.?%d*$") or m.version
    if m.version then QB:SawVersion(m.version, m.name) end
  elseif kind == "1Q" then
    local part, parts, body = msg:match("^1Q|(%d+)|(%d+)|(.*)$")
    part, parts = tonumber(part), tonumber(parts)
    if not (part and parts) or parts > 20 or part > parts then return end
    if part == 1 or not m.pending then m.pending = {} end
    for id, code, prog in body:gmatch("(%d+)%.(%a)([%d/]*)") do
      m.pending[tonumber(id)] = { code = code, prog = prog ~= "" and prog or nil }
    end
    if part == parts then m.quests, m.pending = m.pending, nil end
  elseif kind == "1G" then
    local text = msg:match("^1G|(.*)$")
    local step = (text and text ~= "") and text:sub(1, STEP_LEN) or nil
    if step ~= m.step then m.step = step; memberChanged() end
    if QB.StepFrame and QB.StepFrame.Refresh then QB.StepFrame.Refresh() end
    return
  elseif kind == "1L" then
    local before = QB.liveVer
    for id, xp, lvl in msg:gmatch("(%d+):(%d+):(%d+)") do
      QB.Live.Record(tonumber(id), tonumber(xp), tonumber(lvl), "party")
    end
    if QB.liveVer ~= before then QB:MarkDirty() end
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
    if m.age > STALE then self.members[key] = nil; memberChanged() elseif m.level then out[#out + 1] = m end
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
  local level = QB.state.level or 1
  local cats, list = {}, {}
  local function note(catIdx, qid, who, name, me, code, prog, class)
    local cat = D.CAT[catIdx]
    if not (cat and cat.dungeon) then return end
    local c = cats[catIdx]
    if not c then
      c = { cat = cat, quests = {}, byQ = {}, people = {}, classOf = {}, seen = {}, xp = 0, left = 0 }
      cats[catIdx] = c
      list[#list + 1] = c
    end
    local e = c.byQ[qid]
    if not e then
      e = { id = qid, q = QB.Quest.Get(qid), who = {}, need = 0 }
      c.byQ[qid] = e
      c.quests[#c.quests + 1] = e
    end
    e.who[#e.who + 1] = { name = name, me = me, code = code, prog = prog, class = class }
    if code ~= "b" then
      e.need = e.need + 1
      c.left = c.left + 1
      if e.q then c.xp = c.xp + QB.Model.XpAt(e.q, level) end
    end
    if not c.seen[who] then c.seen[who] = true; c.people[#c.people + 1] = name; c.classOf[name] = class end
  end
  local myClass = select(2, UnitClass("player"))
  for _, e in ipairs(QB:RouteEntries("plan")) do
    local code = e.st.code == "banked" and "b" or (e.st.code == "active" and "a" or "p")
    local have, need = QB:Progress(e.q.id)
    note(D.Q[e.q.id][8], e.q.id, "me", "You", true, code, need and (have .. "/" .. need) or nil, myClass)
  end
  for key, m in pairs(self.members) do
    if m.quests and m.fac == QB.faction then
      for id, v in pairs(m.quests) do
        local r = D.Q[id]
        if r then note(r[8], id, key, m.name, false, v.code, v.prog, m.class) end
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

-- the class colour table the player's other frames use, then the game's own
local function classColors() return CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS end
S.ClassColors = classColors

-- "ffRRGGBB" for a class; dark cuts it to 70%, for text on the parchment
function S.ClassColor(class, dark)
  local t = classColors()
  local c = t and class and t[class]
  if not c then return nil end
  if c.colorStr and not dark then return c.colorStr end
  local k = dark and 0.7 or 1
  return string.format("ff%02x%02x%02x", math.floor(c.r * k * 255 + 0.5), math.floor(c.g * k * 255 + 0.5), math.floor(c.b * k * 255 + 0.5))
end

-- a name in its class colour, for text that mixes several people
function S.ColorName(name, class, dark)
  local hex = S.ClassColor(class, dark)
  if not hex then return name end
  return "|c" .. hex .. name .. "|r"
end

-- everyone here who holds this quest, you included (held, or planned and not yet done): { { name, class, me }, ... }
function S:WhoHas(id, exceptKey)
  local out = {}
  if QB.state.log[id] or (QB:Plan().add[id] and not QB.API.IsDone(id)) then out[#out + 1] = { name = "you", class = select(2, UnitClass("player")), me = true } end
  for key, m in pairs(self.members) do
    if key ~= exceptKey and m.quests and m.quests[id] then out[#out + 1] = { name = m.name or key, class = m.class } end
  end
  return out
end

function S:MemberTooltip(tip, key)
  local m = self.members[key]
  if not m then return end
  local cc = classColors() and m.class and classColors()[m.class]
  tip:AddDoubleLine(m.name, m.version and ("QuestBank " .. m.version) or "", cc and cc.r or 1, cc and cc.g or 0.82, cc and cc.b or 0, 0.6, 0.6, 0.6)
  tip:AddLine(string.format(QB:Banking() and "Level %s, banked to %.1f, plan to %.1f (%.1f in the first hour)" or "Level %s, ready quests take them to %.1f, their plan to %.1f",
    m.level or "?", m.banked or 0, m.plan or 0, m.at60 or 0), 1, 1, 1, true)
  if m.runStart then tip:AddLine(string.format("Running for %s: %d handed in, +%s XP", QB.Clock(m.runMin), m.runN, QB.Comma(m.runXP)), 0.4, 1, 0.4) end
  if not m.quests then tip:AddLine("Their quest list hasn't arrived yet.", 0.6, 0.6, 0.6) return end
  local list = {}
  for id, v in pairs(m.quests) do
    local q = QB.Quest.Get(id)
    if q then list[#list + 1] = { q = q, code = v.code, prog = v.prog, xp = QB.Model.XpAt(q, m.level or QB.state.level or 1) } end
  end
  table.sort(list, function(a, b) return a.xp > b.xp end)
  local label = { b = QB:Banking() and "banked" or "ready to hand in", a = "in their log", p = "to pick up" }
  -- twenty at a time, so the tooltip stays a tooltip; Shift held while hovering shows them all
  local cap = (IsShiftKeyDown and IsShiftKeyDown()) and #list or 20
  tip:AddLine(string.format("%d quest%s. Who else here holds each one, in their class colour:", #list, #list == 1 and "" or "s"), 0.6, 0.6, 0.6, true)
  for i = 1, math.min(cap, #list) do
    local it = list[i]
    local others = {}
    for _, w in ipairs(self:WhoHas(it.q.id, key)) do others[#others + 1] = S.ColorName(w.name, w.class) end
    local shared = #others > 0 and ("  " .. table.concat(others, ", ")) or ""
    local state = it.code == "a" and it.prog and ("in their log, " .. it.prog) or (label[it.code] or "")
    tip:AddDoubleLine(it.q.name .. shared, state .. ", " .. QB.Short(it.xp), 1, 1, 1, 0.6, 1, 0.6)
  end
  if #list > cap then tip:AddLine(string.format("and %d more (hold Shift for all)", #list - cap), 0.6, 0.6, 0.6) end
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
-- the version notice, realm-wide. Every QuestBank joins one quiet chat channel and says its version
-- there: on arrival, every ten minutes, and when someone older speaks up. So "a newer one is out"
-- reaches you from anyone on the realm who runs it, not only your party and guild. Nothing else
-- travels on it, it never shows in a chat window, and Settings' Updates switch keeps you out of it.
----------------------------------------------------------------------------
local VCHAN = "QuestBankVer"
S.ver = { joined = false, lastSaid = -1000, lastAnswer = -1000, quiet = -1000, pending = false }

local function verChannelId()
  if not GetChannelName then return 0 end
  local ok, id = pcall(GetChannelName, VCHAN)
  return (ok and tonumber(id)) or 0
end

function S:SayVersion()
  local id = verChannelId()
  if id == 0 then return false end
  queue("1V|" .. QB.version, "CHANNEL", tostring(id))
  self.ver.lastSaid = now()
  return true
end

function S:JoinVersionChannel()
  if self.ver.joined or not QB:Settings().updates then return end
  if not (JoinTemporaryChannel and GetChannelName) then return end
  if verChannelId() == 0 then pcall(JoinTemporaryChannel, VCHAN) end
  if verChannelId() == 0 then return end -- not yet: the heartbeat tries again
  self.ver.joined = true
  if ChatFrame_RemoveChannel and DEFAULT_CHAT_FRAME then pcall(ChatFrame_RemoveChannel, DEFAULT_CHAT_FRAME, VCHAN) end
  self:SayVersion()
end

function S:LeaveVersionChannel()
  if not self.ver.joined then return end
  self.ver.joined = false
  if LeaveChannelByName then pcall(LeaveChannelByName, VCHAN) end
end

-- the Updates switch changed: in or out, right away
function S:ApplyVersionSetting()
  if QB:Settings().updates then self:JoinVersionChannel() else self:LeaveVersionChannel() end
end

-- someone said their version on the channel
function S:HeardVersion(v, sender)
  QB:SawVersion(v, sender:match("^([^%-]+)") or sender)
  local t = now()
  if not QB.Newer(QB.version, v) then
    self.ver.quiet = t -- someone at least as new as us spoke: nothing to add for a while
    return
  end
  -- they run an older one: say ours, once a minute at most, unless someone newer speaks first
  if t - self.ver.lastAnswer < 60 or self.ver.pending then return end
  self.ver.pending = true
  C_Timer.After(1 + math.random() * 4, QB.Safe(function()
    S.ver.pending = false
    local n = now()
    if n - S.ver.quiet < 6 or n - S.ver.lastSaid < 30 then return end
    if S:SayVersion() then S.ver.lastAnswer = n end
  end, "version notice"))
end

-- the channel's own notices (joined, left, who else came and went) stay out of the chat windows
local function quietNotice(_, _, ...)
  local chan, base = select(4, ...), select(9, ...)
  if (type(chan) == "string" and chan:find(VCHAN, 1, true)) or (type(base) == "string" and base:find(VCHAN, 1, true)) then return true end
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
  -- the version channel: join once the world has settled, say our version every ten minutes
  if ChatFrame_AddMessageEventFilter then
    for _, ev in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
      pcall(ChatFrame_AddMessageEventFilter, ev, quietNotice)
    end
  end
  C_Timer.After(20, QB.Safe(function() S:JoinVersionChannel() end, "version notice: join"))
  local vbeat
  vbeat = QB.Safe(function()
    C_Timer.After(600, vbeat)
    if not QB:Settings().updates then S:LeaveVersionChannel()
    elseif not S.ver.joined then S:JoinVersionChannel()
    else S:SayVersion() end
  end, "version notice")
  C_Timer.After(600, vbeat)
end

----------------------------------------------------------------------------
-- the party as the game sees it, with or without QuestBank on the other side: who is here, how far, what they lack
-- of your quests, and the share itself (the game's own push, one quest every second and a half so the prompts
-- do not pile up). A quest is shareable when the client says so (C_QuestLog.IsPushableQuest).
----------------------------------------------------------------------------
local SHARE_GAP = 1.5

-- { { unit, name, class (file name), level, me = true for you, pos = { c, wx, wy } or nil }, ... }, you first
function S.GroupUnits()
  local out = {}
  local function add(unit, me)
    if not (UnitExists and QB.Plain(UnitExists(unit)) == true) then return end
    local name = QB.Plain(UnitName and UnitName(unit))
    local _, class = nil, nil
    if UnitClass then local okC, a, b = pcall(UnitClass, unit); if okC then _, class = QB.Plain(a), QB.Plain(b) end end
    local level = UnitLevel and QB.Plain(UnitLevel(unit)) or nil
    local pos
    if UnitPosition then
      local ok, y, x, _, inst = pcall(UnitPosition, unit)
      y, x, inst = QB.Plain(y), QB.Plain(x), QB.Plain(inst)
      if ok and type(x) == "number" and type(y) == "number" then pos = { inst = inst, wx = x, wy = y } end
    end
    out[#out + 1] = { unit = unit, name = type(name) == "string" and name or "?", class = type(class) == "string" and class or nil,
                      level = type(level) == "number" and level or nil, me = me or nil, pos = pos }
  end
  add("player", true)
  local n = GetNumGroupMembers and QB.Plain(GetNumGroupMembers()) or 0
  if type(n) == "number" and n > 1 and not (IsInRaid and QB.Plain(IsInRaid()) == true) then
    for i = 1, 4 do add("party" .. i) end
  end
  return out
end

-- yards between you and a member outdoors, nil when the game hides it
function S.YardsTo(member)
  if not (member.pos and not member.me) then return nil end
  local me = S.GroupUnits()[1]
  if not (me and me.pos and me.pos.inst == member.pos.inst) then return nil end
  local dx, dy = member.pos.wx - me.pos.wx, member.pos.wy - me.pos.wy
  return math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)
end

-- the quests in your log the game lets you share
function S.Shareable()
  local out = {}
  if not (C_QuestLog and C_QuestLog.IsPushableQuest) then return out end
  for _, e in ipairs(QB.state.logOrder or {}) do
    local ok, can = pcall(C_QuestLog.IsPushableQuest, e.id)
    if ok and QB.Plain(can) == true then out[#out + 1] = e.id end
  end
  return out
end

-- the sync record of a party member by name, when they run QuestBank
-- (the chat's sender name may carry more than the unit's: the first word decides)
local function firstWord(n) return type(n) == "string" and n:match("^[^%s%-]+") or n end
function S:MemberByName(name)
  local want = firstWord(name)
  for _, m in pairs(self.members) do if m.name == name or firstWord(m.name) == want then return m end end
  return nil
end

-- what a member lacks of your shareable quests: known for a QuestBank user, every shareable one otherwise
function S:Lacking(member, shareable)
  shareable = shareable or S.Shareable()
  local m = self:MemberByName(member.name)
  if not (m and m.quests) then return shareable, false end
  local out = {}
  for _, id in ipairs(shareable) do if not m.quests[id] and not QB.API.IsDone(id) then out[#out + 1] = id end end
  return out, true
end

-- the share: the game's push, which goes to the whole party; one quest, then the next after a pause
local queue, sharing = {}, false
local function pushOne()
  local id = table.remove(queue, 1)
  if not id then sharing = false; return end
  local okIdx, index = pcall(C_QuestLog.GetLogIndexForQuestID, id)
  index = okIdx and QB.Plain(index) or nil
  if index and QuestLogPushQuest then pcall(QuestLogPushQuest, index)
  elseif QuestUtil and QuestUtil.ShareQuest then pcall(QuestUtil.ShareQuest, id) end
  S.shared = (S.shared or 0) + 1
  C_Timer.After(SHARE_GAP, QB.Safe(pushOne, "share quests"))
end
function S:Share(ids)
  if not (C_QuestLog and C_QuestLog.GetLogIndexForQuestID) then return 0 end
  local n = 0
  for _, id in ipairs(ids or {}) do queue[#queue + 1] = id; n = n + 1 end
  if n > 0 and not sharing then sharing = true; pushOne() end
  return n
end

-- the next step as a line for party chat: the route's first stop and its quests, else the Now page's first place
function S.NextStepText()
  local r = QB.routeNow
  local leg = r and r.legs and r.legs[1]
  if leg and leg.stop then
    local names = {}
    for i, row in ipairs(leg.rows or {}) do if i <= 3 then names[#names + 1] = row.q.name end end
    local xp = 0
    for _, row in ipairs(leg.rows or {}) do xp = xp + (row.xp or 0) end
    return string.format("QuestBank next stop: %s%s%s", leg.stop.name, #names > 0 and (": " .. table.concat(names, ", ")) or "",
                         xp > 0 and string.format(" (+%s XP)", QB.Comma(xp)) or "")
  end
  return nil
end

