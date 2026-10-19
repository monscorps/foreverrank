-- SPDX-License-Identifier: GPL-3.0-or-later
-- The guild channel. Small addon messages, one a second at most, GUILD only:
--   1D|regver|k=v;k=v;...          what changed since the last send
--   1F|part|parts|regver|k=v;...   the full record, in chunks (at the hello, and when asked); the game's statistics, where
--                                  the client reports them, and what this character discovered (bosses, instances,
--                                  factions) follow in a pass of their own a minute and a half later
--   1R|guid                        please send your full record (answered after a random 1 to 20 s, the statistics
--                                  60 to 90 s on; one answer however many ask while it waits). The asker's GUID tells
--                                  it its own ask, which the game hands back to it (0.3.0 sent a bare 1R, still answered)
--   1P|at|threshold|id=a;id=s;...  the officers' visibility policy (a statistics category is gc<id>, a discovered one
--                                  gc_bosses, gc_dungeons, gc_raids or gc_rep)
--   1L|key=label;key=label;...     the names of what this character discovered, so a member who never met a boss, an
--                                  instance or a faction shows it: e<encounterID>:<instanceID> for a boss and the
--                                  instance it was killed in, i<instanceID>:<p|r|w> for an instance and its kind (party,
--                                  raid, or the continent an open-world boss stood on: outside an instance
--                                  GetInstanceInfo names the continent, "Eastern Kingdoms" or "Kalimdor"),
--                                  f<factionID> for a faction. Sent for a
--                                  new discovery a second after it, and in a labels pass after the statistics pass (at
--                                  the hello and in answer to an ask), for the ids in this character's own record
-- The full record starts with the sender's GUID (guid=, Stats.lua's hidden stat), so a receiver joins it to the roster's
-- member and knows its own record when the game hands it back; then ench_kinds= (hidden too: the kind of each enchanted
-- item, "slot:class.subclass" space-separated, which the guild learns its enchants from; a delta carries it when it
-- changes).
-- Values: ints in base 36, flags 1/0, text as UTF-8 without | ; = (a client's own names, accents included), lists as
-- base-36 bitmaps over the stat's list, pips as digits. A client ignores ids it does not know, except the dynamic ones
-- (a statistic's g<id>, a discovered e<id>, i<id>, f<id>), whose values it keeps as ints whether or not it has defined
-- them: a client that learns a statistic, or a label, later shows the others' at once. Stats marked slow in the
-- registry (time played, XP into the level, every statistic, the standings) go out on a two-minute flush rather than as
-- they tick.
local _, C = ...
local M = { out = {}, lastSent = {}, queued = {}, started = false, hello = false, helloDue = false, senders = {} }
C.Comm = M
local PREFIX = "Cute"
local LIMIT = 255       -- the client's cap on one addon message, header included
local SLOW_FLUSH = 120  -- seconds between sends of the slow stats
local RETRIES = 5       -- "try later" answers before a message is given up
local GAME_AFTER = 90   -- seconds after the hello before the statistics pass: a login's first minute stays small

local DIG = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
  n = math.floor(n + 0.5)
  if n == 0 then return "0" end
  local neg = n < 0
  n = math.abs(n)
  local s = ""
  while n > 0 do local d = n % 36; s = DIG:sub(d + 1, d + 1) .. s; n = (n - d) / 36 end
  return (neg and "-" or "") .. s
end
local function unb36(s) return tonumber(s, 36) end
M.b36, M.unb36 = b36, unb36

-- text as it may travel and be shown: no separators, no control characters, UTF-8 kept whole (0.3.x dropped every byte
-- over 127, so a zone with an accent lost a letter); 24 bytes, or the stat's own max (the GUID's 40), never cutting a
-- character in two (Stats.lua's CleanText)
local function cleanText(s, max) return C.Stats.CleanText(s, max or 24) end

-- a stat's value as its wire text; nil when there is nothing to send
function M.Encode(def, v)
  if v == nil then return nil end
  if def.kind == "int" then return type(v) == "number" and b36(v) or nil
  elseif def.kind == "flag" then return v and "1" or "0"
  elseif def.kind == "text" then return type(v) == "string" and cleanText(v, def.max) or nil
  elseif def.kind == "pips" then return type(v) == "string" and v:gsub("[^%d]", "") or nil
  elseif def.kind == "list" then
    if type(v) ~= "table" then return nil end
    local bits = 0
    for i, e in ipairs(def.of) do if v[e[1]] then bits = bits + 2 ^ (i - 1) end end
    return b36(bits)
  end
end

-- the wire text back to a value; nil for anything a well-behaved client would not have sent
function M.Decode(def, s)
  if def.kind == "int" then
    local n = unb36(s)
    if not n or n ~= n or math.abs(n) > 2 ^ 40 then return nil end
    return n
  elseif def.kind == "flag" then if s == "1" then return true elseif s == "0" then return false end return nil
  elseif def.kind == "text" then return cleanText(s, def.max)
  elseif def.kind == "pips" then return s:match("^%d*$") and s or nil
  elseif def.kind == "list" then
    local bits = unb36(s)
    if not bits or bits < 0 or bits >= 2 ^ 30 then return nil end
    local out = {}
    for i, e in ipairs(def.of) do if math.floor(bits / 2 ^ (i - 1)) % 2 == 1 then out[e[1]] = true end end
    return out
  end
end

-- "k=v" parts cut into messages that fit the limit, each starting with head; every chunk knows the ids it carries
local function pack(head, parts, limit)
  limit = limit or LIMIT
  local msgs, cur = {}, nil
  for _, p in ipairs(parts) do
    if cur and #cur.msg + 1 + #p.kv > limit then msgs[#msgs + 1] = cur; cur = nil end
    if not cur then cur = { msg = head .. p.kv, ids = {} } else cur.msg = cur.msg .. ";" .. p.kv end
    cur.ids[p.id] = p.s
  end
  if cur then msgs[#msgs + 1] = cur end
  return msgs
end

-- one try at the client: sent, later (and how long to wait), or drop
local function send(msg)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return "sent" end
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
  if not ok then return "drop", tostring(res) end
  res = C.Plain(res)
  if res == nil or res == true or res == 0 then return "sent" end
  -- Enum.SendAddonMessageResult: 3 AddonMessageThrottle and 8 ChannelThrottle pass; 9 GeneralError and
  -- 11 AddOnMessageLockdown pass too, given longer
  if res == 3 or res == 8 then return "later", 3 end
  if res == 9 or res == 11 then return "later", 10 end
  return "drop", "result " .. tostring(res)
end

local function mark(e, sent)
  for id, s in pairs(e.ids or {}) do
    if M.queued[id] == s then M.queued[id] = nil end
    if sent then M.lastSent[id] = s
    else C.Sample.dirty[id] = true end -- back on the list, so it goes with the next change
  end
end

local pumping = false
local pump
pump = C.Safe(function()
  local e = M.out[1]
  if not e then pumping = false return end
  local r, extra = send(e.msg)
  if r == "later" then
    e.tries = (e.tries or 0) + 1
    if e.tries <= RETRIES then C_Timer.After(extra or 3, pump) return end
    r, extra = "drop", "still throttled after " .. RETRIES .. " tries"
  end
  table.remove(M.out, 1)
  if r == "sent" then mark(e, true)
  else
    mark(e, false)
    C.Err.Note("addon message not sent (" .. tostring(extra) .. "); its stats go with the next change", "comm: sending")
  end
  C_Timer.After(1, pump)
end, "comm: sending")
local function queue(e)
  if CUTE_DEV then assert(#e.msg <= LIMIT, "an addon message of " .. #e.msg .. " bytes") end
  for _, m in ipairs(M.out) do if m.msg == e.msg then return end end
  M.out[#M.out + 1] = e
  for id, s in pairs(e.ids or {}) do M.queued[id] = s end
  if not pumping then pumping = true; C_Timer.After(0.05, pump) end
end
M.Queue = queue

-- the "k=v" parts for a set of ids, skipping values already sent or already queued
local function partsFor(ids, force)
  local list = {}
  for _, id in ipairs(ids) do
    local def = C.Stats.byId[id]
    local s = def and M.Encode(def, C.Sample:Value(id))
    if s ~= nil and (force or (M.lastSent[id] ~= s and M.queued[id] ~= s)) then list[#list + 1] = { id = id, kv = id .. "=" .. s, s = s } end
  end
  return list
end

-- send what changed since the last send; slow stats wait for the flush (all = true) unless asked
function M:Changed(all)
  if not self.started or not C.Roster:InGuild() then return end
  -- before the hello nothing goes out: its full record carries it all
  if not self.hello then return end
  local ids = {}
  for id in pairs(C.Sample.dirty) do
    local def = C.Stats.byId[id]
    if def and (all or not def.slow) then ids[#ids + 1] = id; C.Sample.dirty[id] = nil end
  end
  table.sort(ids)
  if #ids == 0 then return end
  for _, e in ipairs(pack("1D|" .. C.REGVER .. "|", partsFor(ids))) do queue(e) end
end

-- "k=v" parts as 1F chunks whose header is counted against the limit
local function chunks(parts)
  local head = string.format("1F|%d|%d|%d|", 99, 99, C.REGVER) -- the longest header a chunk can get
  local list = pack("", parts, LIMIT - #head)
  for i, e in ipairs(list) do
    e.msg = string.format("1F|%d|%d|%d|%s", i, #list, C.REGVER, e.msg)
    queue(e)
  end
end

-- the whole record but the statistics and the discoveries, which have their own pass; the hidden stats first (Stats.lua:
-- the GUID, so the first chunk names the sender, then the kinds of your enchanted items)
function M:Full()
  if not C.Roster:InGuild() then return end
  local ids = {}
  for _, id in ipairs(C.Stats.HIDDEN_ORDER) do ids[#ids + 1] = id; C.Sample.dirty[id] = nil end
  C.Sample.values.guid = C.MyGUID() or C.Sample.values.guid
  for _, def in ipairs(C.Stats.list) do
    if def.cat ~= "game" and def.cat ~= "found" then ids[#ids + 1] = def.id; C.Sample.dirty[def.id] = nil end
  end
  chunks(partsFor(ids, true))
end

-- the statistics and the discoveries this character has a value for: at login a minute and a half after the hello,
-- and when asked; the labels pass follows them. force sends values already sent (an asker has not seen them); without
-- it only what has not gone out yet goes
local function passIds()
  local ids = {}
  for _, cat in ipairs({ "game", "found" }) do
    for _, def in ipairs(C.Stats.byCat[cat]) do ids[#ids + 1] = def.id; C.Sample.dirty[def.id] = nil end
  end
  return ids
end
function M:FullGame(force)
  if not C.Roster:InGuild() then return end
  local ids = passIds()
  if #ids > 0 then chunks(partsFor(ids, force)) end
  self:Labels(nil, force)
end

-- the labels: "key=label" for every discovered id with a value in this character's own record, the instance of each
-- boss with it, once each. only: these ids (a new discovery), else all; force: every one (an asker has seen none),
-- else the ones not sent yet this session (the hello's own pass, after an answer that carried them)
local labelSent = {}
local function labelPart(id)
  local k = C.Stats.Known()
  local label = k and k.labels and k.labels[id]
  if type(label) ~= "string" or label == "" then return nil end
  local p, num = id:sub(1, 1), tonumber(id:sub(2))
  local key = id
  if p == "e" then local inst = k.inst and k.inst[num]; if type(inst) == "number" then key = id .. ":" .. inst end
  elseif p == "i" then local kind = k.kind and k.kind[num]; key = id .. ":" .. (kind == "party" and "p" or (kind == "raid" and "r" or "w")) end
  return { id = id, kv = key .. "=" .. label }
end
function M:Labels(only, force)
  if not (self.hello and C.Roster:InGuild()) then return end
  local k = C.Stats.Known()
  if not k then return end
  local seen, parts = {}, {}
  local function add(id)
    if seen[id] then return end
    seen[id] = true
    local part = labelPart(id)
    if part and (force or only or not labelSent[part.kv]) then parts[#parts + 1] = part; labelSent[part.kv] = true end
    -- a boss's instance goes with it, named
    local num = id:match("^e(%d+)$")
    local inst = num and k.inst and k.inst[tonumber(num)]
    if type(inst) == "number" then add("i" .. inst) end
  end
  if only then
    for _, id in ipairs(only) do add(id) end
  else
    local ids = {}
    for id, v in pairs(C.Sample.values) do if type(id) == "string" and id:match("^[efi]%d+$") and v ~= nil then ids[#ids + 1] = id end end
    table.sort(ids)
    for _, id in ipairs(ids) do add(id) end
  end
  if #parts == 0 then return end
  for _, e in ipairs(pack("1L|", parts)) do queue({ msg = e.msg }) end
end
-- a discovery's label, told a second after it (several at once go together); before the hello the labels pass covers it
function M:LabelSoon(id)
  if not (self.started and self.hello) then return end
  self.newLabels = self.newLabels or {}
  self.newLabels[#self.newLabels + 1] = id
  if self.labelsDue then return end
  self.labelsDue = true
  C_Timer.After(1, C.Safe(function()
    M.labelsDue = false
    local list = M.newLabels
    M.newLabels = {}
    M:Labels(list)
  end, "comm: labels"))
end

function M:Ask()
  if not C.Roster:InGuild() then return end
  local guid = C.MyGUID()
  queue({ msg = guid and ("1R|" .. (guid:gsub("[|;=]", ""))) or "1R" })
end
function M:SendPolicy()
  local at, threshold, parts = C.Policy:Parts()
  if not at or not C.Roster:InGuild() then return end
  -- one message per chunk that fits, all under the same "at": the first replaces the receiver's policy, the rest add
  local head = string.format("1P|%d|%d|", at, threshold)
  local list = {}
  for _, kv in ipairs(parts) do list[#list + 1] = { kv = kv, id = kv:match("^[^=]+"), s = kv:match("=(.*)$") } end
  local msgs = pack(head, list)
  if #msgs == 0 then msgs = { { msg = head } } end
  for _, m in ipairs(msgs) do queue({ msg = m.msg }) end
end

----------------------------------------------------------------------------
-- receiving
----------------------------------------------------------------------------
-- a dynamic id this client has not defined (a statistic its own probe found none of, a boss whose label has not come
-- yet) still decodes as the int it is
local INT = { kind = "int" }
local function decodeBody(body)
  local kv = {}
  for id, s in (body or ""):gmatch("([%l%d_]+)=([^;]*)") do
    local def = C.Stats.byId[id] or (C.Stats.IsDynamic(id) and INT) or nil
    if def then
      local v = M.Decode(def, s)
      if v ~= nil then kv[id] = v end
    end
  end
  return kv
end

-- the first three senders the channel named, any prefix, for /cute diag (how this client names people, you included).
-- (Sender strings are compared here, and below, only with sender strings: the channel's own, kept as given, the way
-- they key CuteDB.roster. None is compared with a name, and a secret is asked about before anything compares it)
function M:Saw(sender, prefix)
  if #self.senders >= 3 then return end
  if issecretvalue and issecretvalue(sender) then self.senders[#self.senders + 1] = { secret = true, prefix = prefix }; return end
  if sender == nil then return end
  for _, e in ipairs(self.senders) do if e.sender == sender and e.prefix == prefix then return end end
  self.senders[#self.senders + 1] = { sender = sender, prefix = prefix }
end

function M:Receive(text, channel, sender)
  text, channel, sender = C.Plain(text), C.Plain(channel), C.Plain(sender)
  if type(text) ~= "string" or type(sender) ~= "string" then return end
  if channel ~= "GUILD" then return end
  local R = C.Roster
  local kind = text:sub(1, 2)
  -- the GUID a full record or an ask carries decides whether the message is yours, handed back by the game; a delta
  -- or a policy carries none, and Roster.lua goes by the sender string (R:FromMe)
  local kv, guid
  if kind == "1F" then kv = decodeBody(text:match("^1F|%d+|%d+|[^|]*|(.*)$")); guid = kv.guid
  elseif kind == "1R" then guid = text:match("^1R|(.+)$") end
  local me, how = R:FromMe(sender, guid)
  if me then
    R:SelfSender(sender, how)
    for _, e in ipairs(self.senders) do if e.sender == sender then e.me = true end end
    return
  end
  if guid then R:NotMe(sender) end
  if kind == "1D" then
    local body = text:match("^1D|[^|]*|(.*)$")
    R:Apply(sender, decodeBody(body))
  elseif kind == "1F" then
    R:Apply(sender, kv)
  elseif kind == "1R" then
    -- everyone answers, spread over twenty seconds so a login does not fire twenty clients at once, and once for all
    -- who ask while the answer waits (an asker is online by the time it goes); an officer adds the policy, so a fresh
    -- install gets it without waiting for the next officer login. The statistics follow a minute later, in their own pass
    if not M.answering then
      M.answering = true
      local wait = 1 + (math.random and math.random(0, 19) or 5)
      C_Timer.After(wait, C.Safe(function() M.answering = false; M:Full() end, "comm: answer"))
      if C.Roster:MeOfficer() then C_Timer.After(wait + 1, C.Safe(function() M:SendPolicy() end, "comm: answer policy")) end
    end
    if not M.answeringGame and (#C.Stats.byCat.game > 0 or #C.Stats.byCat.found > 0) then
      M.answeringGame = true
      local wait = GAME_AFTER - 30 + (math.random and math.random(0, 29) or 5)
      C_Timer.After(wait, C.Safe(function() M.answeringGame = false; M:FullGame(true) end, "comm: answer statistics"))
    end
  elseif kind == "1P" then
    local at, thr, body = text:match("^1P|(%d+)|(%d+)|(.*)$")
    C.Policy:Receive(sender, at, thr, body)
  elseif kind == "1L" then
    self:ReceiveLabels(text:match("^1L|(.*)$"))
  end
end

-- labels from the channel: each fills a gap in what this client knows (one it found itself stays), and defines the
-- stat it names, so the Statistics page shows it with every member's value already kept. A key that does not parse,
-- an id out of range or a label that cleans to nothing is skipped
local MAX_ID = 2 ^ 31
function M:ReceiveLabels(body)
  if type(body) ~= "string" then return 0 end
  local S, n, before = C.Stats, 0, C.Stats.foundVersion
  for key, label in body:gmatch("([^=;]+)=([^;]*)") do
    local p, num, extra = key:match("^([efi])(%d+):?([%w]*)$")
    num = tonumber(num)
    if p and num and num < MAX_ID and #key <= 24 then
      if p == "e" then
        local inst = tonumber(extra)
        S.Label("e" .. num, label, false, (inst and inst < MAX_ID) and inst or nil)
        n = n + 1
      elseif p == "i" and (extra == "p" or extra == "r" or extra == "w") then
        S.Label("i" .. num, label, false, nil, extra)
        n = n + 1
      elseif p == "f" and extra == "" then
        S.Label("f" .. num, label, false)
        n = n + 1
      end
    end
  end
  if S.foundVersion ~= before and C.UI and C.UI.Refresh then C.UI:Refresh() end
  return n
end

-- hello: ask for everyone's record (your GUID in the ask, so the game's copy of it tells you your sender string), send
-- ours, say the policy if we hold one, and the statistics a minute and a half on. Said only in a guild: a character
-- that logs in without one says it on the first roster refresh after joining (Roster.lua), before any change goes out
-- as a delta. (A hello counted as said while guildless would let your deltas, which carry no GUID, come back after a
-- join under a sender string nothing knows as you, and make 0.3.0's ghost row again)
function M:Hello()
  if self.hello or not self.helloDue or not self.started or not C.Roster:InGuild() then return end
  self.hello = true
  self:Ask()
  self:Full()
  if C.Roster:MeOfficer() then self:SendPolicy() end
  C_Timer.After(GAME_AFTER, C.Safe(function() M:FullGame(false) end, "comm: statistics"))
end

function M:Start()
  if self.started then return end
  if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return end
  pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
  self.started = true
  local f = CreateFrame("Frame")
  self.frame = f
  f:SetScript("OnEvent", C.Safe(function(_, event, prefix, text, channel, sender)
    if event ~= "CHAT_MSG_ADDON" then return end
    prefix = C.Plain(prefix)
    if #M.senders < 3 then M:Saw(sender, prefix) end
    if prefix == PREFIX then M:Receive(text, channel, sender) end
  end, "comm: receiving"))
  f:RegisterEvent("CHAT_MSG_ADDON")
  -- the hello, eight seconds in (or when you join a guild)
  C_Timer.After(8, C.Safe(function() M.helloDue = true; M:Hello() end, "comm: hello"))
  -- the slow stats, every two minutes
  local function flush()
    C_Timer.After(SLOW_FLUSH, C.Safe(flush, "comm: flush"))
    M:Changed(true)
  end
  C_Timer.After(SLOW_FLUSH, C.Safe(flush, "comm: flush"))
end
