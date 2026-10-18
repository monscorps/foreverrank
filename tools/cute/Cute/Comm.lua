-- SPDX-License-Identifier: GPL-3.0-or-later
-- The guild channel. Small addon messages, one a second at most, GUILD only:
--   1D|regver|k=v;k=v;...          what changed since the last send
--   1F|part|parts|regver|k=v;...   the full record, in chunks (at login, and when asked)
--   1R                             please send your full record (answered after a random 1 to 20 s)
--   1P|at|threshold|id=a;id=s;...  the officers' visibility policy
-- Values: ints in base 36, flags 1/0, text as ASCII without | ; =, lists as base-36 bitmaps over the stat's list,
-- pips as digits. A client ignores ids it does not know. Stats marked slow in the registry (time played, XP into
-- the level) go out on a two-minute flush rather than as they tick.
local _, C = ...
local M = { out = {}, lastSent = {}, queued = {}, started = false, hello = false }
C.Comm = M
local PREFIX = "Cute"
local LIMIT = 255       -- the client's cap on one addon message, header included
local SLOW_FLUSH = 120  -- seconds between sends of the slow stats
local RETRIES = 5       -- "try later" answers before a message is given up

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

-- text as it may travel and be shown: no separators, no control characters, nothing the game's font draws as a box
local function cleanText(s)
  s = tostring(s):gsub("[|;=]", ""):gsub("%c", ""):gsub("[\128-\255]", "")
  return s:sub(1, 24)
end

-- a stat's value as its wire text; nil when there is nothing to send
function M.Encode(def, v)
  if v == nil then return nil end
  if def.kind == "int" then return type(v) == "number" and b36(v) or nil
  elseif def.kind == "flag" then return v and "1" or "0"
  elseif def.kind == "text" then return type(v) == "string" and cleanText(v) or nil
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
  elseif def.kind == "text" then return cleanText(s)
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
  -- before the hello nothing goes out: the full record at 8 s carries it all
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

-- the whole record, in chunks whose header is counted against the limit
function M:Full()
  if not C.Roster:InGuild() then return end
  local ids = {}
  for _, def in ipairs(C.Stats.list) do ids[#ids + 1] = def.id; C.Sample.dirty[def.id] = nil end
  local head = string.format("1F|%d|%d|%d|", 99, 99, C.REGVER) -- the longest header a chunk can get
  local chunks = pack("", partsFor(ids, true), LIMIT - #head)
  for i, e in ipairs(chunks) do
    e.msg = string.format("1F|%d|%d|%d|%s", i, #chunks, C.REGVER, e.msg)
    queue(e)
  end
end

function M:Ask() if C.Roster:InGuild() then queue({ msg = "1R" }) end end
function M:SendPolicy()
  local body = C.Policy:Encode()
  if body and C.Roster:InGuild() then queue({ msg = "1P|" .. body }) end
end

----------------------------------------------------------------------------
-- receiving
----------------------------------------------------------------------------
local function decodeBody(body)
  local kv = {}
  for id, s in (body or ""):gmatch("([%l%d_]+)=([^;]*)") do
    local def = C.Stats.byId[id]
    if def then
      local v = M.Decode(def, s)
      if v ~= nil then kv[id] = v end
    end
  end
  return kv
end

function M:Receive(text, channel, sender)
  text, channel, sender = C.Plain(text), C.Plain(channel), C.Plain(sender)
  if type(text) ~= "string" or type(sender) ~= "string" then return end
  if channel ~= "GUILD" then return end
  local me = C.Me()
  if sender == me then return end
  local kind = text:sub(1, 2)
  if kind == "1D" then
    local body = text:match("^1D|[^|]*|(.*)$")
    C.Roster:Apply(sender, decodeBody(body))
  elseif kind == "1F" then
    local body = text:match("^1F|%d+|%d+|[^|]*|(.*)$")
    C.Roster:Apply(sender, decodeBody(body))
  elseif kind == "1R" then
    -- everyone answers, spread over twenty seconds so a login does not fire twenty clients at once; an officer
    -- adds the policy, so a fresh install gets it without waiting for the next officer login
    local wait = 1 + (math.random and math.random(0, 19) or 5)
    C_Timer.After(wait, C.Safe(function() M:Full() end, "comm: answer"))
    if C.Roster:MeOfficer() then C_Timer.After(wait + 1, C.Safe(function() M:SendPolicy() end, "comm: answer policy")) end
  elseif kind == "1P" then
    local at, thr, body = text:match("^1P|(%d+)|(%d+)|(.*)$")
    C.Policy:Receive(sender, at, thr, body)
  end
end

function M:Start()
  if self.started then return end
  if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return end
  pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
  self.started = true
  local f = CreateFrame("Frame")
  self.frame = f
  f:SetScript("OnEvent", C.Safe(function(_, event, prefix, text, channel, sender)
    if event == "CHAT_MSG_ADDON" and C.Plain(prefix) == PREFIX then M:Receive(text, channel, sender) end
  end, "comm: receiving"))
  f:RegisterEvent("CHAT_MSG_ADDON")
  -- hello: ask for everyone's record, send ours, and say the policy if we hold one
  C_Timer.After(8, C.Safe(function()
    M.hello = true
    M:Ask()
    M:Full()
    if C.Roster:MeOfficer() then M:SendPolicy() end
  end, "comm: hello"))
  -- the slow stats, every two minutes
  local function flush()
    C_Timer.After(SLOW_FLUSH, C.Safe(flush, "comm: flush"))
    M:Changed(true)
  end
  C_Timer.After(SLOW_FLUSH, C.Safe(flush, "comm: flush"))
end
