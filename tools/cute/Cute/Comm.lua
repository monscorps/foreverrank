-- SPDX-License-Identifier: GPL-3.0-or-later
-- The guild channel. Small addon messages, one a second at most, GUILD only:
--   1D|regver|k=v;k=v;...          what changed since the last send
--   1F|part|parts|regver|k=v;...   the full record, in chunks (at login, and when asked)
--   1R                             please send your full record (answered after a random 1 to 20 s)
--   1P|at|threshold|id=a;id=s;...  the officers' visibility policy
-- Values: ints in base 36, flags 1/0, text as ASCII without | ; =, lists as base-36 bitmaps over the stat's list,
-- pips as digits. A client ignores ids it does not know.
local _, C = ...
local M = { out = {}, lastSent = {}, started = false }
C.Comm = M
local PREFIX = "Cute"
local LIMIT = 250

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

local function cleanText(s)
  s = tostring(s):gsub("[|;=]", ""):gsub("[\128-\255]", "")
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

function M.Decode(def, s)
  if def.kind == "int" then return unb36(s)
  elseif def.kind == "flag" then return s == "1"
  elseif def.kind == "text" then return s
  elseif def.kind == "pips" then return s
  elseif def.kind == "list" then
    local bits = unb36(s)
    if not bits then return nil end
    local out = {}
    for i, e in ipairs(def.of) do if math.floor(bits / 2 ^ (i - 1)) % 2 == 1 then out[e[1]] = true end end
    return out
  end
end

-- "k=v;k=v" pairs cut into messages that fit, each with the given head
local function pack(head, pairs_)
  local msgs, cur = {}, nil
  for _, kv in ipairs(pairs_) do
    if cur and #cur + 1 + #kv > LIMIT then msgs[#msgs + 1] = cur; cur = nil end
    if not cur then cur = head .. kv else cur = cur .. ";" .. kv end
  end
  if cur then msgs[#msgs + 1] = cur end
  return msgs
end

local function send(msg)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return "sent" end
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
  if not ok then return "drop" end
  if res == nil or res == true or res == 0 then return "sent" end
  if res == 3 or res == 8 then return "later" end
  return "drop"
end

local pumping = false
local pump
pump = C.Safe(function()
  local m = M.out[1]
  if not m then pumping = false return end
  local r = send(m)
  if r == "later" then C_Timer.After(3, pump) else table.remove(M.out, 1); C_Timer.After(1, pump) end
end, "comm: sending")
local function queue(msg)
  for _, m in ipairs(M.out) do if m == msg then return end end
  M.out[#M.out + 1] = msg
  if not pumping then pumping = true; C_Timer.After(0.05, pump) end
end
M.Queue = queue

-- the pairs for a set of ids
local function pairsFor(ids)
  local list = {}
  for _, id in ipairs(ids) do
    local def = C.Stats.byId[id]
    local s = def and M.Encode(def, C.Sample:Value(id))
    if s then list[#list + 1] = id .. "=" .. s end
  end
  return list
end

-- send what changed since the last send
function M:Changed()
  if not self.started or not C.Roster:InGuild() then return end
  local ids = {}
  for id in pairs(C.Sample.dirty) do
    local def = C.Stats.byId[id]
    local s = def and M.Encode(def, C.Sample:Value(id))
    if s ~= nil and self.lastSent[id] ~= s then ids[#ids + 1] = id; self.lastSent[id] = s end
    C.Sample.dirty[id] = nil
  end
  table.sort(ids)
  if #ids == 0 then return end
  for _, m in ipairs(pack("1D|" .. C.REGVER .. "|", pairsFor(ids))) do queue(m) end
end

-- the whole record
function M:Full()
  if not C.Roster:InGuild() then return end
  local ids = {}
  for _, def in ipairs(C.Stats.list) do ids[#ids + 1] = def.id end
  local list = pairsFor(ids)
  for _, id in ipairs(ids) do local def = C.Stats.byId[id]; self.lastSent[id] = M.Encode(def, C.Sample:Value(id)) end
  local chunks = pack("", list)
  for i, body in ipairs(chunks) do queue(string.format("1F|%d|%d|%d|%s", i, #chunks, C.REGVER, body)) end
end

function M:Ask() if C.Roster:InGuild() then queue("1R") end end
function M:SendPolicy()
  local body = C.Policy:Encode()
  if body and C.Roster:InGuild() then queue("1P|" .. body) end
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
    -- everyone answers, spread over twenty seconds so a login does not fire twenty clients at once
    local wait = 1 + (math.random and math.random(0, 19) or 5)
    C_Timer.After(wait, C.Safe(function() M:Full() end, "comm: answer"))
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
    M:Ask()
    M:Full()
    if C.Roster:MeOfficer() then M:SendPolicy() end
  end, "comm: hello"))
end
