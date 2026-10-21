-- SPDX-License-Identifier: GPL-3.0-or-later
-- RunComm: the run report's group channel (the run report's design, 13.1). Prefix CuteRun, on RAID in a raid,
-- INSTANCE_CHAT in an instance group, else PARTY. Comm.lua's prefix and queue stay the guild's; its receive takes GUILD
-- and WHISPER only, so nothing of this reaches it.
--   2H|<run>|<version>|<flags>       a hello: at a run's start, on a resume, the scribe's answer to a newcomer. flags:
--                                    the kind and the place, "d.<instance>", "r.<instance>" or "g.<map>" (base 36),
--                                    ".a" after them for an answer
--   2V|<run>|<seq>|<i>/<n>|k=v;...   this client's own values, whole, the highest seq kept (a checkpoint, the end)
--   2Q|<run>                         the scribe: the group's run ends, send your last values
--   2A|<run>|<i>/<n>|k=v;...         the scribe's report: codes, suffixes and numbers alone
--   2E|<run>                         the leader's End run
--   2P|<run>                         Send to party was clicked here
--   2R|<run>|<suffix>                a member back from a crash asks for its last checkpoint
--   2W|<run>|<suffix>|<i>/<n>|k=v;... the scribe: that member's last checkpoint, back
-- The queue is its own and keeps Comm's rule for the chat lockdown (Comm.lua M:Locked, asked before each send): one
-- message a second; hellos, 2E, 2Q, 2A, 2R and 2W ahead of 2P and 2V; a newer 2V takes the place of one waiting; a
-- checkpoint waits for the end of combat. Results as Comm reads them (Enum.SendAddonMessageResult,
-- ChatConstantsDocumentation.lua): 3 and 8 (throttle) try again in 3 s, 9 (GeneralError) in 10 s, five times (a
-- checkpoint as often as it takes); 5 (NotInGroup) empties the queue;
-- 11 (AddOnMessageLockdown) spends no try and drops nothing: the queue waits for ADDON_RESTRICTION_STATE_CHANGED with
-- the Chat type and the Inactive state (RestrictedActionsDocumentation.lua:97; it also fires Activating just before a
-- restriction starts), and C_RestrictedActions.IsAddOnRestrictionActive, which reads false during any of the event's
-- dispatches, is read only on a 5-second timer (through Comm's M:Locked), never inside the event.
-- A message is taken only from a sender whose name is a group unit's, and a GUID suffix in it only where that unit's
-- GUID ends with it (Runs.lua says who is heard for what).
local _, C = ...
local RC = { out = {}, parts = {}, counts = {}, results = {}, held = nil }
C.RunComm = RC
RC.PREFIX = "CuteRun"
local LIMIT = 255
local RETRIES = 5
local POLL = 5 -- (the lockdown asked again, out of the event)

local FIRST = { ["2H"] = 1, ["2E"] = 1, ["2Q"] = 1, ["2A"] = 1, ["2R"] = 1, ["2W"] = 1, ["2P"] = 2, ["2V"] = 3 }
local function clock() return (GetTime and GetTime()) or C.Now() end
local function callable(name) return type(_G[name]) == "function" end
local function inCombat() return callable("InCombatLockdown") and C.Get(InCombatLockdown) == true end

-- the group's channel, as Send to party chooses it too (IsInRaid, IsInGroup: ChatFrameEditBox.lua:581-590 asks them
-- the same way; 2 is LE_PARTY_CATEGORY_INSTANCE); nil out of a group
function RC.Channel()
  if not callable("IsInGroup") then return nil end
  if callable("IsInRaid") and C.Get(IsInRaid) == true then return "RAID" end
  if C.Get(IsInGroup, 2) == true then return "INSTANCE_CHAT" end
  if C.Get(IsInGroup) == true then return "PARTY" end
  return nil
end

----------------------------------------------------------------------------
-- messages: a body of k=v parts cut to fit, each part with its head
----------------------------------------------------------------------------
-- head: "2V|<run>|<seq>|" (the part's "i/n|" goes after it); kv: { "k=v", ... }. One message where it all fits
function RC.Pack(head, kv)
  local out, cur = {}, {}
  local room = LIMIT - #head - 6
  local len = 0
  for _, p in ipairs(kv) do
    if #p > room then p = p:sub(1, room) end
    if len > 0 and len + 1 + #p > room then out[#out + 1] = table.concat(cur, ";"); cur, len = {}, 0 end
    cur[#cur + 1] = p
    len = len + (len > 0 and 1 or 0) + #p
  end
  if #cur > 0 or #out == 0 then out[#out + 1] = table.concat(cur, ";") end
  local msgs = {}
  for i, body in ipairs(out) do msgs[i] = head .. i .. "/" .. #out .. "|" .. body end
  return msgs
end

----------------------------------------------------------------------------
-- the queue
----------------------------------------------------------------------------
-- Send(kind, body, opts): body a message's text after its kind and bar ("<run>|..."), or a function giving the whole
-- messages as they leave (a 2V is built as it goes, by the policy then: Runs.lua). opts.ooc: wait for the end of combat
-- (a checkpoint); opts.key: a message waiting with the same key is replaced in its place (the newest 2V)
function RC:Send(kind, body, opts)
  opts = opts or {}
  local e = { kind = kind, body = body, ooc = opts.ooc, key = opts.key, at = clock(), tries = 0 }
  if e.key then
    for i, x in ipairs(self.out) do if x.key == e.key and not x.msgs then self.out[i] = e; self:Kick(); return true end end
  end
  local pos = #self.out + 1
  for i, x in ipairs(self.out) do if (FIRST[x.kind] or 3) > (FIRST[kind] or 3) and not x.msgs then pos = i break end end
  table.insert(self.out, pos, e)
  self:Kick()
  return true
end
-- empty, the group gone
function RC:Clear() self.out = {} end

-- the message whose turn it is: the first that may go now (a checkpoint waits for the end of combat; one cut in parts
-- goes on first, its parts one a second)
local function nextUp(self)
  for _, e in ipairs(self.out) do if e.msgs then return e end end
  local combat = nil
  for _, e in ipairs(self.out) do
    if e.ooc then
      if combat == nil then combat = inCombat() end
      if not combat then return e end
    else return e end
  end
  return nil
end

local function count(kind) RC.counts[kind] = (RC.counts[kind] or 0) + 1 end
local function send(msg, channel)
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, RC.PREFIX, msg, channel)
  if not ok then return "drop", tostring(res) end
  res = C.Plain(res)
  RC.last = { res = res, at = C.Now() }
  if res == nil or res == true or res == 0 then return "sent" end
  -- (9 GeneralError passes too, given longer, as Comm reads it)
  if res == 3 or res == 8 then return "later", nil, 3 end
  if res == 9 then return "later", nil, 10 end
  if res == 5 then return "nogroup" end
  if res == 11 then return "locked" end
  return "drop", "result " .. tostring(res)
end

local pump
local gen = 0
local function book(sec)
  gen = gen + 1
  local g = gen
  RC.booked = true
  C_Timer.After(sec, function() if g == gen then pump() end end)
end
function RC:Kick() if not self.booked and #self.out > 0 then book(0.05) end end
-- (the lockdown asked again every POLL seconds while the queue waits: out of the event, through Comm's M:Locked)
local function holdOn(why)
  RC.held = RC.held or { since = C.Now(), why = why }
  book(POLL)
end
pump = C.Safe(function()
  RC.booked = false
  local e = nextUp(RC)
  if not e then return end
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then RC.out = {}; return end
  local channel = RC.Channel()
  if not channel then RC.out = {}; return end
  -- (the chat lockdown as Comm knows it: the functions, its event's Activating, a recent result 11)
  if C.Comm and C.Comm.Locked and C.Comm:Locked() then holdOn("lockdown") return end
  -- (a result 11 the functions do not report: waited out POLL seconds at a time, no try spent)
  if RC.waitInactive and C.Now() - RC.waitInactive < POLL then holdOn("result 11") return end
  RC.waitInactive = nil
  RC.held = nil
  if not e.msgs then
    local msgs = type(e.body) == "function" and e.body() or { e.kind .. "|" .. e.body }
    if type(msgs) == "string" then msgs = { msgs } end
    if type(msgs) ~= "table" or #msgs == 0 then
      for i, x in ipairs(RC.out) do if x == e then table.remove(RC.out, i) break end end
      book(0.05)
      return
    end
    e.msgs, e.i = msgs, 1
  end
  local r, why, wait = send(e.msgs[e.i], channel)
  if r == "locked" then
    -- (no try spent, nothing dropped: the queue waits for the Chat restriction's Inactive, or a poll that finds none)
    local IE = C_InstanceEncounter
    local inEnc = type(IE) == "table" and type(IE.IsEncounterInProgress) == "function" and C.Get(IE.IsEncounterInProgress) == true or false
    RC.results[#RC.results + 1] = { at = C.Now(), kind = e.kind, encounter = inEnc }
    while #RC.results > 20 do table.remove(RC.results, 1) end
    RC.waitInactive = C.Now()
    holdOn("result 11")
    return
  end
  if r == "later" then
    e.tries = e.tries + 1
    -- (the newest checkpoint is never given up for a throttle or an error: it waits its 3 s, or 10, as often as it
    -- takes)
    if e.tries <= RETRIES or e.kind == "2V" then book(wait or 3) return end
    r, why = "drop", "still refused after " .. RETRIES .. " tries"
  end
  if r == "nogroup" then RC.out = {}; return end
  if r == "sent" then
    count(e.kind)
    e.i = e.i + 1
    if e.i <= #e.msgs then book(1) return end
  else
    RC.drops = (RC.drops or 0) + 1
    C.Err.Note("run message not sent (" .. tostring(why) .. ")", "runs: sending")
  end
  for i, x in ipairs(RC.out) do if x == e then table.remove(RC.out, i) break end end
  if #RC.out > 0 then book(1) end
end, "runs: sending", function() if not RC.booked and #RC.out > 0 then book(1) end end)

-- ADDON_RESTRICTION_STATE_CHANGED (type, state): the Chat restriction's Inactive lets the queue go (a moment on, out
-- of the event's dispatch); Activating and Active hold it (Comm's M:Locked counts them)
function RC:Restriction(kind, state)
  kind, state = C.Plain(kind), C.Plain(state)
  local kinds = Enum and Enum.AddOnRestrictionType
  local chat = type(kinds) == "table" and C.Plain(kinds.Chat) or nil
  if kind == nil or kind ~= chat then return end
  local states = Enum and Enum.AddOnRestrictionState
  local inactive = type(states) == "table" and C.Plain(states.Inactive) or 0
  if state ~= inactive then return end
  self.waitInactive = nil
  if #self.out > 0 then gen = gen + 1; self.booked = false; book(0.05) end
end

----------------------------------------------------------------------------
-- receiving: the sender a group unit, the message's parts put back together
----------------------------------------------------------------------------
-- the parts of a message cut in pieces, by sender and head, kept a minute
local function assemble(sender, head, i, n, body)
  if n <= 1 then return body end
  local key = sender .. "\1" .. head
  local p = RC.parts[key]
  if not p or p.n ~= n or clock() - p.at > 60 then p = { n = n, got = 0, list = {}, at = clock() }; RC.parts[key] = p end
  if not p.list[i] then p.list[i] = body; p.got = p.got + 1 end
  if p.got < n then return nil end
  RC.parts[key] = nil
  return table.concat(p.list, ";", 1, n)
end
-- (fewer than 40 senders' parts at once: an edited copy's endless first parts crowd nothing out)
local function prune()
  local n, oldest, ok = 0, nil, nil
  for k, p in pairs(RC.parts) do n = n + 1; if not oldest or p.at < oldest then oldest, ok = p.at, k end end
  if n > 40 and ok then RC.parts[ok] = nil end
end

-- CHAT_MSG_ADDON (prefix, text, channel, sender): CuteRun's, from a group unit not you; handed to Runs.lua
function RC:Receive(prefix, text, channel, sender)
  if C.Plain(prefix) ~= RC.PREFIX then return end
  text, channel, sender = C.Plain(text), C.Plain(channel), C.Plain(sender)
  if type(text) ~= "string" or type(sender) ~= "string" then return end
  if channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" then return end
  local Runs = C.Runs
  local who = Runs and Runs.UnitOf and Runs.UnitOf(sender)
  -- (a sender no group unit names: counted for /cute diag runs, which says whether the group's names read inside)
  if not who then RC.unknown = (RC.unknown or 0) + 1 return end
  if who.me then return end
  local kind, rest = text:match("^(2%u)|(.*)$")
  if not kind then return end
  if kind == "2V" or kind == "2A" or kind == "2W" then
    local head, i, n, body
    if kind == "2V" then head, i, n, body = rest:match("^([^|]*|%d+)|(%d+)/(%d+)|(.*)$")
    elseif kind == "2A" then head, i, n, body = rest:match("^([^|]*)|(%d+)/(%d+)|(.*)$")
    else head, i, n, body = rest:match("^([^|]*|[^|]*)|(%d+)/(%d+)|(.*)$") end
    i, n = tonumber(i), tonumber(n)
    if not (head and i and n and n >= 1 and n <= 8 and i >= 1 and i <= n) then return end
    prune()
    local whole = assemble(sender, kind .. head, i, n, body)
    if not whole then return end
    rest = head .. "|" .. whole
  end
  Runs:Heard(kind, rest, who)
end

-- for /cute diag runs: what this client sent on the group channel in the last run, the waiting, the lockdown
function RC.Report()
  local kinds = {}
  for _, k in ipairs({ "2H", "2V", "2Q", "2A", "2E", "2P", "2R", "2W" }) do if RC.counts[k] then kinds[#kinds + 1] = k .. " " .. RC.counts[k] end end
  local r11 = {}
  for _, r in ipairs(RC.results) do r11[#r11 + 1] = r.kind .. (r.encounter and " in an encounter" or " out of one") end
  local restricted = type(C_ChatInfo) == "table" and type(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted) == "function" and C.Get(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)
  return string.format("group channel: sent %s | waiting %d%s | result 11: %s | outgoing restricted %s | locked %s | from no group unit %d",
    #kinds > 0 and table.concat(kinds, ", ") or "nothing", #RC.out, RC.held and (" (held: " .. RC.held.why .. ")") or "",
    #r11 > 0 and table.concat(r11, ", ", math.max(1, #r11 - 5)) or "none", tostring(restricted), tostring(C.Comm and C.Comm:Locked() or false), RC.unknown or 0)
end
