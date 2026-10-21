-- SPDX-License-Identifier: GPL-3.0-or-later
-- The guild channel. Small addon messages, one a second at most, on GUILD:
--   1D|regver|k=v;k=v;...          what changed since the last send
--   1F|part|parts|regver|k=v;...   the full record, in chunks (at the hello, and when asked); the game's statistics, where
--                                  the client reports them, and what this character discovered (bosses, instances,
--                                  factions) follow in a pass of their own a minute and a half later. regver "4s":
--                                  the part of it that went on GUILD after an ask's since (M:Full), which a receiver
--                                  holding no record of the sender takes as a part and asks the whole of (1Q)
--   1R|guid|stamp|word|fp[since]   please send your full record (answered after a random 2 to 40 s, the statistics
--                                  60 to 90 s on; one answer however many ask while it waits, one ask a sender in
--                                  three minutes, the statistics once in half an hour and one pass forced for the
--                                  guild in ten minutes whoever asks, never for a bare 0.3/0.5 ask; an officer's always
--                                  gets the part the officers keep, whispered; one heard before this login's own record
--                                  went is answered by it). since, in hex right after the fingerprint (a 0.6 or 0.7
--                                  client reads a field of another length as no fingerprint, which it never answers
--                                  by): the server time to which the asker holds everything said on GUILD (M:Logout),
--                                  and a responder whose record went whole before it sends only what went after it. A
--                                  /reload asks nothing (M:Wire). The asker's GUID tells
--                                  it its own ask, which the game hands back to it (0.3.0 sent a bare 1R, 0.5.x no
--                                  stamp: both still answered; they take the GUID to be everything after "1R|", which
--                                  names nobody they know, so the rest passes them by). stamp: when the officers' word
--                                  the asker holds was set (an officer whose own is newer answers with the policy);
--                                  fp: the fingerprint of the policy it routes by (kept on the wire; no client answers
--                                  by it, Guild Info's line carries the policy itself); word: when the
--                                  newest officers' word the asker holds was said (1N): an officer whose own is newer
--                                  answers with it
--   1Q|guid                        the record of the member with this GUID, whole: asked by a client that holds none
--                                  of it after a part since its since or a delta came (M:WantWhole), answered by that
--                                  member alone with its guild part; a 0.5-0.7 client passes it by
--   1N|at|i/n|key=value;...        the officers' word: what the guild learned from what members' clients do not receive
--                                  (with the defaults, which slots and kinds of item take an enchant), no GUID, no
--                                  member's value, no count (Rules.lua R.WordParts). Sent by an officer's client when it
--                                  changes (once a minute at most, unless it takes something back) and in answer to an
--                                  ask; a long one in parts under one "at", i of n, taken once every part is in. Taken
--                                  only from a sender the roster names an officer by
--   1P|at|threshold|i/n|+go;-zo;...  the officers' policy, part i of n under one "at", taken once whole: what differs
--                                  from the defaults by code (Stats.lua S.CODES; "+" Everyone, "-" Only you; a
--                                  statistics category by its number), then the rules' thresholds and the untrusted.
--                                  Taken only from an officer by the roster's rank (Policy.lua P:Receive), its routing
--                                  only where the guild has no line in Guild Info (a line carries the policy itself)
--   1L|key=label;key=label;...     the names of what this character discovered, so a member who never met a boss, an
--                                  instance or a faction shows it: e<encounterID>:<instanceID> for a boss and the
--                                  instance it was killed in, i<instanceID>:<p|r|w> for an instance and its kind (party,
--                                  raid, or the continent an open-world boss stood on: outside an instance
--                                  GetInstanceInfo names the continent, "Eastern Kingdoms" or "Kalimdor"),
--                                  f<factionID> for a faction, and l<encounterID>=<item>.<item>... for the items
--                                  this character saw in a boss's loot window (base 36; Rules.lua rule 8; a 0.4.0
--                                  client skips the key). Sent for a
--                                  new discovery a second after it, and in a labels pass after the statistics pass (at
--                                  the hello and in answer to an ask), for the ids in this character's own record
--   1K|enc@time:sfx.sfx;...        a boss kill and the group it was killed in: the encounter, the server's time in base
--                                  36 and the last part of each group member's GUID ("Player-4242-0A000001" is
--                                  "0A000001"). Rules.lua rule 9 weighs it: a kill teaches where another member of the
--                                  group names this one back within a minute. Sent at the kill, and each boss's first
--                                  kill in a group again with the discoveries
-- Only-you is routing, not hiding (Policy.lua P:Route): a value the officers keep to themselves never goes on GUILD. It
-- goes in the same messages (1D, 1F, 1L, 1K) whispered to each officer online (Roster.lua R:OfficerTargets: the roster's
-- ranks, the policy's threshold, the sender strings their own Cute's messages came under, each one the roster names
-- that officer by), and to an officer who logs in later in the answer to their ask (an asker the roster names an
-- officer by its sender string: a GUID in the ask proves nothing). A whisper is taken only of those four kinds and only
-- from a sender string this client has heard on the guild channel, which the game delivers from the guild alone
-- (Roster.lua R:GuildSender); a member's client keeps none of another's Only-you values whatever comes (R:Apply).
-- Where a value goes is decided as it leaves, not as it is queued: a policy that comes while a message waits its turn
-- keeps what it closes off the guild channel, and a whisper goes only to a sender string the roster still names an
-- officer by. And nothing of yours goes but the ask and the policy while this client does not hold the policy Guild
-- Info names (Policy.lua P:Settled: at login until Guild Info is read, and until a line's policy has come): the record
-- waits (M.holding) and the queue sends nothing else, so a client that was offline when the officers closed a stat
-- does not send it by the old policy.
-- The full record starts with the sender's GUID (guid=, Stats.lua's hidden stat), so a receiver joins it to the roster's
-- member and knows its own record when the game hands it back; then ench_kinds= (hidden too: the kind of each enchanted
-- item, "slot:class.subclass" space-separated, which the guild learns its enchants from; a delta carries it when it
-- changes).
-- Values: ints in base 36, flags 1/0, text as UTF-8 without | ; = (a client's own names, accents included), lists as
-- base-36 bitmaps over the stat's list, pips as digits. A client ignores ids it does not know, except the dynamic ones
-- (a statistic's g<id>, a discovered e<id>, i<id>, f<id>, and k<encounterID>, the level this character had at that
-- boss's first kill), whose values it keeps as ints whether or not it has defined them: a client that learns a
-- statistic, or a label, later shows the others' at once. (The kill level is a value of the member's record, not a
-- label: it is per member, and a record is joined by GUID, kept and pruned with its member, where a label is kept once
-- per id. Rules.lua learns a dungeon's level range from them.) Stats marked slow in the
-- registry (time played, XP into the level, every statistic, the standings) go out on a two-minute flush rather than as
-- they tick.
local _, C = ...
-- lastSent and queued: what went (or waits to go) on GUILD, by id; lastTold and queuedTold the same for the officers'
-- whispers, per officer (lastTold[target][id]), so a copy one officer missed goes again to that officer alone. askers:
-- the officers whose ask the next answer whispers the Only-you values to
local M = { out = {}, lastSent = {}, queued = {}, lastTold = {}, queuedTold = {}, started = false, hello = false, helloDue = false,
  holding = false, senders = {}, askers = {}, gameAskers = {} }
C.Comm = M
local PREFIX = "Cute"
local LIMIT = 255       -- the client's cap on one addon message, header included
local SLOW_FLUSH = 120  -- seconds between sends of the slow stats
local RETRIES = 5       -- "try later" answers before a message is given up
local GAME_AFTER = 90   -- seconds after the hello before the statistics pass: a login's first minute stays small
local FAIR = 10         -- seconds a whisper waits behind guild messages at most

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
-- a dynamic id this client has no definition for (a statistic its own probe found none of, a boss whose label has not
-- come yet, a kill level) still encodes and decodes as the int it is
local INT = { kind = "int" }
local function defOf(id) return C.Stats.byId[id] or (C.Stats.IsDynamic(id) and INT) or nil end

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

-- what went, and what waits its turn, per kind of part and per way: values (v) by id, their wire text kept; labels (l)
-- and kill claims (k) by their text. On GUILD (sent, queued) and per officer whispered to (sentTo[target],
-- queuedTo[target]). A part counts as gone only once the client took it
local STATE = {
  v = { sent = M.lastSent, queued = M.queued, sentTo = M.lastTold, queuedTo = M.queuedTold },
  l = { sent = {}, queued = {}, sentTo = {}, queuedTo = {} },
  k = { sent = {}, queued = {}, sentTo = {}, queuedTo = {} },
}
local function state(kind, target)
  local st = STATE[kind]
  if not target then return st.sent, st.queued end
  st.sentTo[target] = st.sentTo[target] or {}
  st.queuedTo[target] = st.queuedTo[target] or {}
  return st.sentTo[target], st.queuedTo[target]
end
-- when each part's text first went on GUILD this login, by kind and key (a resend of the same text keeps its time):
-- what an ask's since is held against (M:Answer)
M.sentAt = { v = {}, l = {}, k = {} }

-- what went, kept across a /reload (CuteDB.chars[me].wire, the same tables live: the saved variables write them at
-- logout and at a /reload): a /reload is the same login, so it sends again only what changed since the last send
-- before it, asks nothing and sends no forced record (0.7.0's /reload asked, and every client online resent its whole
-- record and statistics). A login starts afresh: its record goes whole, its statistics pass after it. login: when this
-- login began; base: when its record had gone (an ask whose since is later holds it, M:Answer); passAt: the last
-- statistics pass forced for the guild; asked: when an ask of this login left
local function fill(dst, src) for k, v in pairs(type(src) == "table" and src or {}) do if type(k) == "string" then dst[k] = v end end end
function M:Wire(reloading)
  local ch = C.Char()
  local w = ch.wire
  local again = reloading and type(w) == "table" and tonumber(w.login) ~= nil
  if again then
    fill(STATE.v.sent, w.sent); fill(STATE.l.sent, w.labels); fill(STATE.k.sent, w.claims)
    for t, sent in pairs(type(w.told) == "table" and w.told or {}) do if type(t) == "string" and type(sent) == "table" then fill(state("v", t), sent) end end
    for kind, at in pairs(type(w.sentAt) == "table" and w.sentAt or {}) do if M.sentAt[kind] then fill(M.sentAt[kind], at) end end
    fill(self.toldTo, w.toldTo)
    self.base, self.passAt = tonumber(w.base), tonumber(w.passAt)
    self.reloaded = true
    -- (an ask of this login that never left goes after the /reload)
    self.askOwed = not (tonumber(w.asked) and tonumber(w.asked) >= tonumber(w.login)) or nil
  end
  ch.wire = { login = again and tonumber(w.login) or C.ServerNow(), sent = STATE.v.sent, labels = STATE.l.sent, claims = STATE.k.sent,
    told = STATE.v.sentTo, sentAt = M.sentAt, toldTo = self.toldTo, base = self.base, passAt = self.passAt, asked = again and tonumber(w.asked) or nil }
  self.wire = ch.wire
end
-- the guild as this character holds it: CuteDB.chars[me].hold = { club, at }, everything sent on GUILD up to at. Moved
-- on at logout (and at a /reload) only where this login's ask left a while before and was answered, and nothing heard
-- was lost (the early buffer full): a /reload, which asks nothing, misses what was said during its loading screen, so
-- its hold stays at the last one. The next login's ask carries it as since (M:Ask)
local SYNCED_AFTER = 100 -- seconds after the ask left: its answers and their statistics pass have come
function M:AskLeft()
  local w = self.wire
  if w then w.asked = C.ServerNow() end
  self.syncedAt = C.Now()
  if self.AskWholes then self:AskWholes() end
end
function M:Logout()
  local club = C.Roster:ClubId()
  if club == nil or not self.syncedAt or C.Now() - self.syncedAt < SYNCED_AFTER or self.lost then return end
  C.Char().hold = { club = tostring(club), at = math.floor(C.ServerNow()) }
end
-- the since an ask carries, in hex after the policy's fingerprint (a 0.6 or 0.7 client reads that field as a
-- fingerprint, which it never answers by, and takes one of another length for none; 0.5.x takes the whole ask for a
-- GUID it does not know): nothing where this character holds nothing of this guild
function M:SinceHex()
  local h, club = C.Char().hold, C.Roster:ClubId()
  if type(h) ~= "table" or club == nil or h.club ~= tostring(club) or not tonumber(h.at) then return "" end
  return string.format("%x", math.floor(tonumber(h.at)))
end
-- force as a part is chosen: true, every part; a number (an ask's since), every part whose text went on GUILD after it,
-- or never this login; else none (only what changed goes)
local function forced(force, kind, key)
  if force == true then return true end
  if type(force) == "number" then local t = M.sentAt[kind][key]; return t == nil or t > force end
  return false
end

-- parts cut into messages that fit the limit, each starting with head. A part is { id (the id its route is the
-- policy's for), key (what went is kept by), kv (its text), s (a value's wire text, or true) }; every message keeps its
-- parts, so it can be built again as it leaves
local function pack(head, parts, limit, kind)
  limit = limit or LIMIT
  local msgs, cur = {}, nil
  for _, p in ipairs(parts) do
    if cur and #cur.msg + 1 + #p.kv > limit then msgs[#msgs + 1] = cur; cur = nil end
    if not cur then cur = { head = head, msg = head .. p.kv, parts = { p }, kind = kind } else cur.msg = cur.msg .. ";" .. p.kv; cur.parts[#cur.parts + 1] = p end
  end
  if cur then msgs[#msgs + 1] = cur end
  return msgs
end

-- where a part goes: its id's route (Policy.lua P:Route), and the stricter of that and also's (a kill claim names the
-- group it was killed in, so it goes the way Grouped with does too)
local function routeOf(p)
  if C.Policy:Route(p.id) == "self" or (p.also and C.Policy:Route(p.also) == "self") then return "self" end
  return "all"
end

-- the message as it leaves, its parts routed now: a whisper only to a sender string the roster still names an officer
-- by (the officer ranks may have come down since it was queued: Policy.lua), and on GUILD only what the policy lets go
-- there now (one that came since may keep some to the officers). The message (nil where nothing is left), and the
-- parts kept and held back
local function build(e)
  -- (a policy answer goes only while what was heard since the ask does not already hold it: AnswerPolicy)
  if e.covered and e.covered() then return nil, nil, nil end
  if not e.parts then return e.msg, nil, nil end
  if e.target then
    if not C.Roster:OfficerSender(e.target) then return nil, {}, e.parts end
    return e.msg, e.parts, {}
  end
  local kept, back = {}, {}
  for _, p in ipairs(e.parts) do
    if routeOf(p) == "self" then back[#back + 1] = p else kept[#kept + 1] = p end
  end
  if #back == 0 then return e.msg, kept, back end
  if #kept == 0 then return nil, kept, back end
  local list = {}
  for i, p in ipairs(kept) do list[i] = p.kv end
  return e.head .. table.concat(list, ";"), kept, back
end

-- one try at the client: sent, later (and how long to wait), locked (the game holds addon chat back), gone (the officer
-- it was whispered to logged off) or drop. e.target: a whisper to that sender string (C_ChatInfo.SendAddonMessage's
-- WHISPER and target, documented). The last result each way is kept for /cute diag (M.lastResult: GUILD, WHISPER)
M.lastResult = {}
local function send(e, msg)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return "sent" end
  local ok, res
  if e.target then ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "WHISPER", e.target)
  else ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD") end
  M.lastResult[e.target and "WHISPER" or "GUILD"] = { res = ok and C.Plain(res) or "threw", at = C.Now() }
  if not ok then return "drop", tostring(res) end
  res = C.Plain(res)
  if res == nil or res == true or res == 0 then return "sent" end
  -- Enum.SendAddonMessageResult (ChatConstantsDocumentation.lua): 3 AddonMessageThrottle and 8 ChannelThrottle pass;
  -- 9 GeneralError passes too, given longer; 11 AddOnMessageLockdown is the chat lockdown (M:Locked), waited out
  -- without counting a try; 12 TargetOffline is an officer gone, who gets it when they ask
  if res == 3 or res == 8 then return "later", 3 end
  if res == 9 then return "later", 10 end
  if res == 11 then return "locked" end
  if res == 12 and e.target then return "gone" end
  return "drop", "result " .. tostring(res)
end

-- the chat lockdown: while the game holds addon chat back (an encounter, a challenge or PvP match, a map that restricts
-- communication such as a dungeon or raid: SecretPredicatesDocumentation.lua, SecretInChatMessagingLockdown) a message
-- sent is answered 11, AddOnMessageLockdown. Asked before each send: C_ChatInfo.InChatMessagingLockdown
-- (ChatInfoDocumentation.lua:293), C_RestrictedActions.IsAddOnRestrictionActive with Enum.AddOnRestrictionType.Chat
-- (RestrictedActionsDocumentation.lua:55, RestrictedActionsConstantsDocumentation.lua:31), and the state
-- ADDON_RESTRICTION_STATE_CHANGED said last (RestrictedActionsDocumentation.lua:97: it comes before a restriction
-- starts, while IsAddOnRestrictionActive still says false, and after one ends: its Activating counts for LOCK_POLL
-- seconds, the functions saying the rest, so an end the event never told cannot hold the queue for good); a result 11
-- counts as the lockdown for LOCK_POLL seconds where none of them says so. While it holds the queue waits, no try
-- counted (0.7.0 counted 11 as a try and gave a message up after five, the hello's ask with it: a relog inside a
-- dungeon heard nobody's record all session), the answers it owes wait as owed rather than queued, and it goes again
-- when the lockdown ends
local LOCK_POLL = 10
M.lockEvent, M.lockSeen = nil, nil
local function restrictionKind()
  local kinds = Enum and Enum.AddOnRestrictionType
  return type(kinds) == "table" and C.Plain(kinds.Chat) or nil
end
function M:Locked()
  if self.lockEvent and C.Now() - self.lockEvent < LOCK_POLL then return true end
  local CI = C_ChatInfo
  if type(CI) == "table" and type(CI.InChatMessagingLockdown) == "function" and C.Get(CI.InChatMessagingLockdown) == true then return true end
  local RA, kind = C_RestrictedActions, restrictionKind()
  if type(RA) == "table" and type(RA.IsAddOnRestrictionActive) == "function" and kind ~= nil and C.Get(RA.IsAddOnRestrictionActive, kind) == true then return true end
  return self.lockSeen ~= nil and C.Now() - self.lockSeen < LOCK_POLL
end
-- (for /cute diag: the channel as this client last used it, by way: the last result of each, never a name; the queue,
-- what was given up, the prefix's registration; and whether this rank may speak in guild chat at all
-- (GuildInfoDocumentation.lua: C_GuildInfo.CanSpeakInGuildChat))
function M:ChannelReport()
  local function last(way)
    local r = self.lastResult[way]
    if not r then return way .. " none sent" end
    return string.format("%s result %s %d s ago", way, tostring(r.res), math.floor(C.Now() - (r.at or C.Now())))
  end
  local GI = type(C_GuildInfo) == "table" and C_GuildInfo or {}
  local speak = type(GI.CanSpeakInGuildChat) == "function" and tostring(C.Get(GI.CanSpeakInGuildChat)) or "missing"
  return string.format("channel: %s | %s | queue %d, given up %d (%d past the cap)%s | prefix %s | CanSpeakInGuildChat %s",
    last("GUILD"), last("WHISPER"), #self.out, self.drops or 0, self.capped or 0, self.paused and (", held since " .. math.floor(C.Now() - self.paused) .. " s") or "",
    tostring(self.prefixResult), speak)
end
-- (and how far this character holds the guild, and this login's record: M:Wire, M:Logout)
function M:SyncReport()
  local h, club = C.Char().hold, C.Roster:ClubId()
  local held = (type(h) == "table" and club ~= nil and h.club == tostring(club) and tonumber(h.at)) and (math.floor(C.ServerNow() - h.at) .. " s ago") or "nothing"
  return string.format("sync: holds the guild to %s | this login %s, its record %s, %s | asked %s",
    held, self.reloaded and "reloaded" or "fresh", self.base and ("whole " .. math.floor(C.ServerNow() - self.base) .. " s ago") or "not whole yet",
    self.passAt and ("a pass " .. math.floor(C.Now() - self.passAt) .. " s ago") or "no pass forced", self.askOwed and "not yet (owed)" or (self.askLeft and (math.floor(C.Now() - self.askLeft) .. " s ago") or "not this login"))
end
-- (for /cute diag: what each way of asking says now)
function M:LockReport()
  local function said(fn, ...) if type(fn) ~= "function" then return "missing" end local v = C.Get(fn, ...); return tostring(v) end
  local CI, RA = type(C_ChatInfo) == "table" and C_ChatInfo or {}, type(C_RestrictedActions) == "table" and C_RestrictedActions or {}
  local kind = restrictionKind()
  return string.format("lockdown %s (InChatMessagingLockdown %s, restriction %s, event %s, result 11 %s) | AreOutgoingAddonChatMessagesRestricted %s",
    self:Locked() and "on" or "off", said(CI.InChatMessagingLockdown), kind ~= nil and said(RA.IsAddOnRestrictionActive, kind) or "missing",
    self.lockEvent and (math.floor(C.Now() - self.lockEvent) .. " s ago") or "never", self.lockSeen and (math.floor(C.Now() - self.lockSeen) .. " s ago") or "never",
    said(CI.AreOutgoingAddonChatMessagesRestricted))
end

-- a message done with: its parts leave the queue; what the client took counts as gone that way. A value held back (the
-- policy keeps it to the officers now, or its whisper's target is no officer now) or that the client dropped is
-- marked to go again, so it goes its way with the next change (to the officers alone where it is theirs: one
-- officer's lost copy goes again to that officer, the others have it); a label or a claim the policy keeps to the
-- officers now goes to them at once, whispered (a repeat kill's claim is kept nowhere else), and one the client
-- dropped with the next pass. An officer gone gets them when they ask
local whisper -- (below)
local function mark(e, r, kept, back)
  if not (e.parts and e.kind) then return end
  local sent, q = state(e.kind, e.target)
  for _, p in ipairs(e.parts) do if q[p.key] == p.s then q[p.key] = nil end end
  if r == "sent" then
    local at, t = not e.target and M.sentAt[e.kind], C.ServerNow()
    for _, p in ipairs(kept or {}) do
      if at and sent[p.key] ~= p.s then at[p.key] = t end
      sent[p.key] = p.s
    end
  end
  if r == "gone" then return end
  if e.kind ~= "v" then
    if not e.target and back and #back > 0 and type(e.head) == "string" then
      local told = {}
      for _, t in ipairs(C.Roster:OfficerTargets()) do told[t] = back end
      local head, kind = e.head, e.kind
      whisper(told, function(parts) return pack(head, parts, nil, kind) end)
    end
    return
  end
  local again = r == "drop" and e.parts or back or {}
  for _, p in ipairs(again) do if p.id ~= "guid" then C.Sample.dirty[p.id] = true end end
  if #again > 0 and C.Sample.Changed then C.Sample:Changed() end
end

local function clock() return (GetTime and GetTime()) or C.Now() end
-- the message whose turn it is: the policy first (the ask, an answer with one, an officer's broadcast: e.first), so an
-- asker waiting for the policy Guild Info names has it however much else waits here, and nothing else while this
-- client does not hold that policy itself (Policy.lua P:Settled); then the first on the guild channel, ahead of the
-- whispers to the officers, so the guild's deltas never wait behind them; the first in the queue where none is, or
-- where it is a whisper that has waited FAIR seconds (a guild channel busy every second still lets the whispers
-- through)
local function nextUp()
  for i = 1, #M.out do if M.out[i].first then return M.out[i] end end
  if not C.Policy:Settled() then return nil end
  local head = M.out[1]
  if not head or not head.target or (head.at and clock() - head.at >= FAIR) then return head end
  for i = 2, #M.out do if not M.out[i].target then return M.out[i] end end
  return head
end

-- the pump: one message a turn. Its next turn is booked before anything that may raise: an error on the way (in
-- building, routing or marking a message) takes that message out of the queue, its values marked to go with the next
-- change, and the queue goes on (0.7.0's stopped for the session: nothing of yours left until /reload). A turn booked
-- again replaces the one booked before (book), so the end of a lockdown can start the queue at once without two pumps
local pumping, booked, current = false, false, nil
local pump
local bookGen = 0
local function book(sec)
  bookGen = bookGen + 1
  local g = bookGen
  booked = true
  C_Timer.After(sec, function() if g == bookGen then pump() end end)
end
M.drops, M.paused = 0, nil
-- (the ask that left, or that will not: the hello's is sent again where it never left, M:AskAgain)
local function asked(e, r)
  if not e.ask then return end
  if r == "sent" then M.askOwed = nil; M.askLeft = C.Now(); if M.AskLeft then M:AskLeft() end
  elseif r ~= "gone" then M.askOwed = true; M:AskAgain() end
end
-- (this login's record gone whole on GUILD for the first time: an ask whose since is later holds it, M:Answer)
-- (and its first chunk gone: an ask heard before it is answered by that record, M.fullOut)
local function based(e, r)
  if r ~= "sent" or M.base or e.rec ~= "full" or e.target then return end
  M.fullOut = M.fullOut or C.Now()
  local i, n = (type(e.head) == "string" and e.head or ""):match("^1F|(%d+)|(%d+)|")
  if i and i == n then M.base = C.ServerNow(); if M.wire then M.wire.base = M.base end end
end
pump = C.Safe(function()
  booked, current = false, nil
  local e = nextUp()
  if not e then pumping = false; booked = true return end
  -- (the lockdown: nothing goes, no try counted, the queue asked again in a while or when it ends)
  if M:Locked() then M.paused = M.paused or C.Now(); book(LOCK_POLL) return end
  M.paused = nil
  current = e
  local msg, kept, back = build(e)
  local r, extra = "none", nil
  if msg then r, extra = send(e, msg) end
  if r == "locked" then M.lockSeen = C.Now(); M.paused = C.Now(); book(LOCK_POLL) return end
  if r == "later" then
    e.tries = (e.tries or 0) + 1
    -- (a kill claim is never given up: a repeat kill's is kept nowhere else)
    if e.tries <= RETRIES or e.kind == "k" then book(math.min(30, extra or 3)) return end
    r, extra = "drop", "still throttled after " .. RETRIES .. " tries"
  end
  -- (a kill claim the client refused goes to the back of the queue, a few times)
  if r == "drop" and e.kind == "k" and (e.again or 0) < 5 then
    e.again, e.tries = (e.again or 0) + 1, 0
    for i, x in ipairs(M.out) do if x == e then table.remove(M.out, i) break end end
    M.out[#M.out + 1] = e
    book(1)
    return
  end
  for i, x in ipairs(M.out) do if x == e then table.remove(M.out, i) break end end
  -- (nothing left to send took no turn of the client's)
  book(r == "none" and 0.05 or 1)
  asked(e, r)
  based(e, r)
  mark(e, r, kept, back)
  if e.done then e.done() end
  if r == "drop" then M.drops = M.drops + 1; C.Perf.Count("drops"); C.Err.Note("addon message not sent (" .. tostring(extra) .. "); its stats go with the next change", "comm: sending") end
  current = nil
end, "comm: sending", function()
  local e = current
  current = nil
  if booked then return end
  -- (an error on the way: the message it came on leaves the queue, which would raise it again, and is done with as one
  -- the client dropped; then the next turn)
  if e then
    for i, x in ipairs(M.out) do if x == e then table.remove(M.out, i) break end end
    pcall(asked, e, "drop")
    pcall(mark, e, "drop")
    if e.done then pcall(e.done) end
    M.drops = M.drops + 1
    C.Perf.Count("drops")
  end
  book(1)
end)
-- the queue going again: a message queued, or the policy held at last (M:PolicySettled), or the lockdown over
function M.Kick() if not pumping and #M.out > 0 then pumping = true; book(0.05) end end
function M.Resume() if pumping then book(0.05) else M.Kick() end end
-- a delta to a way (the guild channel, or one officer) that already has one waiting goes into that one: a newer value
-- of an id takes the older one's place, a new id joins it while the message fits, and it keeps its turn; what does not
-- fit goes as a message of its own. Every value message still waiting that way behind it (a later delta, a record's
-- chunk) loses the ids that went in, which it holds older: an older value never arrives after a newer one, or a
-- lifetime count would seem to go down and its sender be marked. Every delta waiting that way is tried, in order: a
-- value whose id one of them holds takes its place there (or, where it no longer fits there, leaves it for a message
-- of its own at the end), a new one joins the first with room. So a value that changes every second waits in one
-- message per way, never in a line of them, even behind a full one: 0.6.0's first build queued a guild delta and a
-- whisper per officer every second, and with four officers online and gold changing every second the queue fell 175
-- messages behind in a minute. The delta, with only what went in nowhere, or nil where all of it did
local function isDelta(m, e) return m.kind == "v" and m.parts ~= nil and m.target == e.target and m.head == e.head end
local function joined(m) local list = {}; for i, p in ipairs(m.parts) do list[i] = p.kv end; return m.head .. table.concat(list, ";") end
-- (a value that went in at pos leaves every value message behind it that way, a record's chunks too)
local function strip(e, pos, id)
  for i = #M.out, pos + 1, -1 do
    local m = M.out[i]
    if m.kind == "v" and m.parts and m.target == e.target and type(m.head) == "string" then
      local left = {}
      for _, p in ipairs(m.parts) do if p.id ~= id then left[#left + 1] = p end end
      if #left == 0 then table.remove(M.out, i)
      elseif #left < #m.parts then m.parts = left; m.msg = joined(m) end
    end
  end
end
local function merge(e)
  if e.kind ~= "v" or not e.parts or type(e.head) ~= "string" or e.head:sub(1, 3) ~= "1D|" then return e end
  local deltas = {}
  for i, m in ipairs(M.out) do if isDelta(m, e) then deltas[#deltas + 1] = i end end
  if #deltas == 0 then return e end
  local rest = {}
  local _, q = state("v", e.target)
  for _, p in ipairs(e.parts) do
    local pos
    -- where a delta holds the id: there, in its place
    for _, i in ipairs(deltas) do
      local m = M.out[i]
      local j
      for k, x in ipairs(m.parts) do if x.id == p.id then j = k break end end
      if j then
        if #m.msg + #p.kv - #m.parts[j].kv <= LIMIT then m.parts[j] = p; m.msg = joined(m); pos = i
        else
          table.remove(m.parts, j)
          if #m.parts == 0 then m.parts[1] = p; m.msg = joined(m); pos = i else m.msg = joined(m) end
        end
        break
      end
    end
    -- else the first with room (everything behind it that way gives the id up)
    if not pos then
      for _, i in ipairs(deltas) do
        local m = M.out[i]
        if #m.msg + 1 + #p.kv <= LIMIT then m.parts[#m.parts + 1] = p; m.msg = joined(m); pos = i break end
      end
    end
    if pos then
      q[p.key] = p.s
      if p.id ~= "guid" then strip(e, pos, p.id) end
      -- (a message the strip emptied moved the ones behind it: their places again)
      deltas = {}
      for i, m in ipairs(M.out) do if isDelta(m, e) then deltas[#deltas + 1] = i end end
    else rest[#rest + 1] = p end
  end
  if #rest == 0 then return nil end
  e.parts = rest
  e.msg = joined(e)
  return e
end

-- true when queued (a message already waiting with the same text to the same way is not queued twice, and a delta to a
-- way with one waiting goes into it)
-- The queue holds OUT_CAP messages at most: past it the oldest that may go makes room (its values marked to go with
-- the next change, a label with the next pass); the ask, the policy and the word's answers (first) and a kill claim
-- never do. 0.7.0's grew without bound while a lockdown or a storm of asks held it
local OUT_CAP = 200
local function room()
  if #M.out < OUT_CAP then return end
  for i, m in ipairs(M.out) do
    if not (m.first or m.ask or m.kind == "k" or m == current) then
      table.remove(M.out, i)
      pcall(mark, m, "drop")
      M.drops, M.capped = M.drops + 1, (M.capped or 0) + 1
      C.Perf.Count("drops")
      return
    end
  end
end
local function queue(e)
  if CUTE_DEV then assert(#e.msg <= LIMIT, "an addon message of " .. #e.msg .. " bytes") end
  for _, m in ipairs(M.out) do if m.msg == e.msg and m.target == e.target then return false end end
  e = merge(e)
  if not e then return true end
  room()
  e.at = clock()
  M.out[#M.out + 1] = e
  if e.parts and e.kind then
    local _, q = state(e.kind, e.target)
    for _, p in ipairs(e.parts) do q[p.key] = p.s end
  end
  M.Kick()
  return true
end
M.Queue = queue

-- the "k=v" parts for a set of ids, skipping values already sent or already queued: those for the guild channel, and
-- those the policy keeps to the officers (Policy.lua P:Route), per officer in targets (every one online where none
-- given), each against what went its own way
-- (gforce: the guild channel's own, where it differs: an answer's since filters the guild's part, never the part an
-- officer who asked is whispered)
local function partsFor(ids, force, targets, gforce)
  targets = targets or C.Roster:OfficerTargets()
  if gforce == nil then gforce = force end
  local guild, told = {}, {}
  for _, id in ipairs(ids) do
    local def = defOf(id)
    local s = def and M.Encode(def, C.Sample:Value(id))
    if s ~= nil then
      local p = { id = id, key = id, kv = id .. "=" .. s, s = s }
      if C.Policy:Route(id) == "self" then
        for _, t in ipairs(targets) do
          local sent, q = state("v", t)
          if force == true or (sent[id] ~= s and q[id] ~= s) then told[t] = told[t] or {}; table.insert(told[t], p) end
        end
      else
        local sent, q = state("v")
        if forced(gforce, "v", id) or (sent[id] ~= s and q[id] ~= s) then guild[#guild + 1] = p end
      end
    end
  end
  return guild, told
end
-- messages made of parts, whispered to each officer its own: told maps a target to its parts. Never on GUILD; with no
-- officer online nothing goes, and an officer who logs in gets them in the answer to their ask
function whisper(told, make)
  local targets = {}
  for t, parts in pairs(told) do if #parts > 0 then targets[#targets + 1] = t end end
  table.sort(targets)
  for _, t in ipairs(targets) do
    for _, e in ipairs(make(told[t])) do e.target = t; queue(e) end
  end
end
local function packer(head, kind) return function(parts) return pack(head, parts, nil, kind) end end

-- send what changed since the last send; slow stats wait for the flush (all = true) unless asked. The stats that change
-- at every coin, kill, loot or step and say little each time (LAZY) go once in LAZY_EVERY seconds at most, the change
-- waiting till then: 0.7.0 sent gold at every coin, a whisper to each officer online each time
local LAZY, LAZY_EVERY = { gold = true, rested = true, bags_free = true, durability = true, subzone = true }, 10
M.wentAt = {}
function M:Changed(all)
  if not self.started or not C.Roster:InGuild() then return end
  -- before the hello nothing goes out: its full record carries it all; nor while the record waits for the policy
  if not self.hello or self.holding then return end
  local ids, t, soonest = {}, clock(), nil
  for id in pairs(C.Sample.dirty) do
    local def = defOf(id)
    if def and (all or not def.slow) then
      local wait = (LAZY[id] and not all and self.wentAt[id]) and (self.wentAt[id] + LAZY_EVERY - t) or 0
      if wait > 0 then soonest = math.min(soonest or wait, wait)
      else
        ids[#ids + 1] = id
        C.Sample.dirty[id] = nil
        if LAZY[id] then self.wentAt[id] = t end
      end
    end
  end
  if soonest and not self.lazyDue then
    self.lazyDue = true
    C_Timer.After(soonest, C.Safe(function() M.lazyDue = false; M:Changed() end, "comm: the changes held"))
  end
  table.sort(ids)
  if #ids == 0 then return end
  local guild, told = partsFor(ids)
  local head = "1D|" .. C.REGVER .. "|"
  for _, e in ipairs(pack(head, guild, nil, "v")) do queue(e) end
  whisper(told, packer(head, "v"))
end
-- the officers opened these stats to everyone: they go on the guild channel from now on, the values held now too (the
-- rest waits for its own change; before the hello, or while the record waits for the policy, the full record carries
-- them). A discovery opened goes with its label, which went to the officers alone while it was closed (a member's
-- client shows no boss it has no name for), and a boss with its kill claims
function M:Opened(ids)
  for _, id in ipairs(ids) do self.lastSent[id] = nil end
  if not (self.started and self.hello and C.Roster:InGuild()) or self.holding then return end
  table.sort(ids)
  local guild = partsFor(ids)
  for _, e in ipairs(pack("1D|" .. C.REGVER .. "|", guild, nil, "v")) do queue(e) end
  local found, boss = {}, false
  for _, id in ipairs(ids) do if id:match("^[efi]%d+$") then found[#found + 1] = id; boss = boss or id:sub(1, 1) == "e" end end
  if #found > 0 then self:Labels(found) end
  if boss then self:Claims(true) end
end

-- "k=v" parts as 1F chunks whose header is counted against the limit. rec: what the record is ("full", the whole
-- record; "game", the statistics pass; "since", what changed since an ask's since, its version field marked "s" so a
-- receiver that holds no record of the sender asks for the whole one: a 0.7 client takes the field for the version it
-- never reads), kept on each chunk
local function chunked(parts, rec)
  local reg = C.REGVER .. (rec == "since" and "s" or "")
  local longest = string.format("1F|%d|%d|%s|", 99, 99, reg) -- the longest header a chunk can get
  local list = pack("", parts, LIMIT - #longest, "v")
  for i, e in ipairs(list) do e.head = string.format("1F|%d|%d|%s|", i, #list, reg); e.msg = e.head .. e.msg; e.rec = rec end
  return list
end
-- a newer record of the same kind replaces the chunks of an older one still waiting that way (the same ids, older
-- values): their parts leave the queue's marks, the newer chunks queued in their place at the back
local function superseded(rec, target)
  if rec ~= "full" and rec ~= "game" then return end
  for i = #M.out, 1, -1 do
    local m = M.out[i]
    if m.rec == rec and m.target == target and m ~= current then
      table.remove(M.out, i)
      local _, q = state("v", target)
      for _, p in ipairs(m.parts or {}) do if q[p.key] == p.s then q[p.key] = nil end end
    end
  end
end
-- a record in chunks: the guild's part on GUILD, each officer's part whispered to that officer (after its own GUID, so
-- an officer joins it to its member as the guild's part). whisperOnly: the officers' part alone
local function record(guild, mine, whisperOnly, rec)
  if not whisperOnly then
    superseded(rec, nil)
    for _, e in ipairs(chunked(guild, rec)) do queue(e) end
  end
  local gs = M.Encode(C.Stats.byId.guid, C.MyGUID())
  if gs then for _, parts in pairs(mine) do table.insert(parts, 1, { id = "guid", key = "guid", kv = "guid=" .. gs, s = gs }) end end
  for t in pairs(mine) do superseded(rec, t) end
  whisper(mine, function(parts) return chunked(parts, rec ~= "since" and rec or nil) end)
end

-- the whole record but the statistics and the discoveries, which have their own pass; the hidden stats first (Stats.lua:
-- the GUID, so the first chunk names the sender, then the kinds of your enchanted items). told: the officers whose ask
-- this answers, who get the Only-you part (nil: every officer online, as at the hello). Each officer told is
-- remembered for the session (toldTo)
M.toldTo = {}
-- (keep: the changes waiting stay waiting, for a record that goes to one officer alone)
-- (the version right after them, so the first chunk says what the record's Cute is: a receiver judges its Ready by it,
-- and whispers to an officer only once it says one that takes them)
local function recordIds(keep)
  local ids = {}
  for _, id in ipairs(C.Stats.HIDDEN_ORDER) do ids[#ids + 1] = id; if not keep then C.Sample.dirty[id] = nil end end
  ids[#ids + 1] = "addon_ver"
  C.Sample.values.guid = C.MyGUID() or C.Sample.values.guid
  for _, def in ipairs(C.Stats.list) do
    if def.cat ~= "game" and def.cat ~= "found" then
      if def.id ~= "addon_ver" then ids[#ids + 1] = def.id end
      if not keep then C.Sample.dirty[def.id] = nil end
    end
  end
  return ids
end
-- since: the guild's part only what went on GUILD after it (an ask's since, M:Answer), the GUID and the version first
-- whatever, and nothing at all where nothing else did; the officers told get their part whole
local HEAD = { guid = true, addon_ver = true }
function M:Full(told, whisperOnly, since)
  if not C.Roster:InGuild() then return end
  told = told or C.Roster:OfficerTargets()
  local guild, mine = partsFor(recordIds(whisperOnly), true, told, since or true)
  if since then
    local rest = 0
    for _, p in ipairs(guild) do if not HEAD[p.id] then rest = rest + 1 end end
    if rest == 0 then guild = {} end
    -- (the head named whatever: a since part sent before it would leave a receiver without a record nothing to join)
    local have = {}
    for _, p in ipairs(guild) do have[p.id] = true end
    if rest > 0 then
      for i, id in ipairs({ "guid", "addon_ver" }) do
        if not have[id] then
          local def = defOf(id)
          local s = def and M.Encode(def, C.Sample:Value(id))
          if s then table.insert(guild, i, { id = id, key = id, kv = id .. "=" .. s, s = s }) end
        end
      end
    end
  end
  record(guild, mine, whisperOnly or (since and #guild == 0), since and "since" or "full")
  for _, t in ipairs(told) do self.toldTo[t] = true end
end
-- an officer heard from for the first time this session (their record came after your hello: you logged in after
-- them), or one made an officer since (game: a promotion, the officers' threshold raised; M:Officers): the Only-you
-- part of your record, whispered to them a few seconds on, once. The statistics and discoveries of yours they keep to
-- themselves go with your own pass, a minute and a half after the hello, or, where it has gone and game, whispered to
-- them alone with it. (While your record waits for the policy, its release whispers to every officer online)
function M:TellOfficer(sender, game)
  if self.toldTo[sender] or not self.hello or self.holding or not C.Roster:TakesWhispers(sender) then return end
  self.toldTo[sender] = true
  C_Timer.After(2, C.Safe(function()
    if not C.Roster:InGuild() then return end
    local _, mine = partsFor(recordIds(true), true, { sender })
    record({}, mine)
    if game and M.passDone then M:FullGame(true, { sender }, true) end
  end, "comm: tell an officer"))
end
-- the roster refreshed (Roster.lua): an officer no more is forgotten, so they are told again when made one again, and
-- a sender this client heard on the guild channel as a member that the roster now names an officer is told (a
-- promotion, or the officers' threshold raised, seen here before or after the new officer's own client saw it: their
-- ask, answered by a roster that still named them a member, whispered them nothing). Built again only when who is who
-- or the threshold changed
M.wasMember = {}
function M:Officers()
  local R = C.Roster
  if not R.trusted then return end
  local thr = C.Policy:LineThreshold()
  if self.officersAt == R.idVersion and self.officersThr == thr then return end
  self.officersAt, self.officersThr = R.idVersion, thr
  for t in pairs(self.toldTo) do if not R:OfficerSender(t) then self.toldTo[t] = nil end end
  for key, e in pairs(CuteDB.roster) do
    if type(e) == "table" and e.ch then
      local officer = R:OfficerSender(key)
      if officer and self.wasMember[key] then self:TellOfficer(key, true) end
      self.wasMember[key] = not officer or nil
    end
  end
end

-- the statistics and the discoveries this character has a value for: at login a minute and a half after the hello,
-- and when asked; the labels pass follows them. force sends values already sent (an asker has not seen them); without
-- it only what has not gone out yet goes
local function passIds(keep)
  local ids = {}
  for _, cat in ipairs({ "game", "found" }) do
    for _, def in ipairs(C.Stats.byCat[cat]) do ids[#ids + 1] = def.id; if not keep then C.Sample.dirty[def.id] = nil end end
  end
  -- the levels of this character's first kills, beside the kills
  local levels = {}
  for id in pairs(C.Sample.values) do if type(id) == "string" and id:match("^k%d+$") then levels[#levels + 1] = id; if not keep then C.Sample.dirty[id] = nil end end end
  table.sort(levels)
  for _, id in ipairs(levels) do ids[#ids + 1] = id end
  return ids
end
-- whisperOnly: the part the officers keep, to told alone (an officer's ask the guild's part answered lately, a new
-- officer); passDone once this character's own pass has gone
-- force: true, everything (an asker has seen none of it); a number, an ask's since: what went on GUILD after it
function M:FullGame(force, told, whisperOnly)
  if not C.Roster:InGuild() then return end
  -- (never while the record waits for the policy: a few seconds on)
  if self.holding then C_Timer.After(5, C.Safe(function() M:FullGame(force, told, whisperOnly) end, "comm: statistics")); return end
  local ids = passIds(whisperOnly)
  if #ids > 0 then
    local guild, mine = partsFor(ids, force, told)
    record(guild, mine, whisperOnly, force == true and "game" or (type(force) == "number" and "since" or nil))
  end
  self:Labels(nil, force, told, whisperOnly)
  self:Claims(force, told, whisperOnly)
  if not told then self.passDone = true end
end

-- the labels: "key=label" for every discovered id with a value in this character's own record, the instance of each
-- boss with it, once each. only: these ids (a new discovery), else all; force: every one (an asker has seen none),
-- else the ones not sent yet this session (the hello's own pass, after an answer that carried them). A label goes the
-- way its stat's value does (a boss's loot its boss's): a label tells who met the thing, so a category the officers
-- keep to themselves has its labels whispered to them, to told or to every officer online, and counts as told to an
-- officer only once the client took it
local function labelPart(id)
  local k = C.Stats.Known()
  -- a boss's loot: the items this character saw drop from it
  local enc = id:match("^l(%d+)$")
  if enc then
    local text = C.Rules.LootText(tonumber(enc))
    return text and { id = id, kv = id .. "=" .. text } or nil
  end
  local label = k and k.labels and k.labels[id]
  if type(label) ~= "string" or label == "" then return nil end
  local p, num = id:sub(1, 1), tonumber(id:sub(2))
  local key = id
  if p == "e" then local inst = k.inst and k.inst[num]; if type(inst) == "number" then key = id .. ":" .. inst end
  elseif p == "i" then local kind = k.kind and k.kind[num]; key = id .. ":" .. (kind == "party" and "p" or (kind == "raid" and "r" or "w")) end
  return { id = id, kv = key .. "=" .. label }
end
-- a part of a kind (labels, claims) for the guild channel or for each officer in targets: those not sent or queued
-- that way yet, or every one where force
local function sortParts(kind, part, force, targets, guild, mine)
  part.key, part.s = part.kv, true
  if routeOf(part) == "self" then
    for _, t in ipairs(targets) do
      local sent, q = state(kind, t)
      if force == true or not (sent[part.key] or q[part.key]) then mine[t] = mine[t] or {}; table.insert(mine[t], part) end
    end
  else
    local sent, q = state(kind)
    if forced(force, kind, part.key) or not (sent[part.key] or q[part.key]) then guild[#guild + 1] = part end
  end
end
function M:Labels(only, force, told, whisperOnly)
  if not (self.hello and C.Roster:InGuild()) or self.holding then return end
  local k = C.Stats.Known()
  if not k then return end
  local targets = told or C.Roster:OfficerTargets()
  local seen, parts, mine = {}, {}, {}
  local function add(id)
    if seen[id] then return end
    seen[id] = true
    local part = labelPart(id)
    if part then sortParts("l", part, (only ~= nil) or force, targets, parts, mine) end
    -- a boss's instance goes with it, named, and the loot this character saw it drop
    local num = id:match("^e(%d+)$")
    local inst = num and k.inst and k.inst[tonumber(num)]
    if type(inst) == "number" then add("i" .. inst) end
    if num then add("l" .. num) end
  end
  if only then
    for _, id in ipairs(only) do add(id) end
  else
    local ids = {}
    for id, v in pairs(C.Sample.values) do if type(id) == "string" and id:match("^[efi]%d+$") and v ~= nil then ids[#ids + 1] = id end end
    table.sort(ids)
    for _, id in ipairs(ids) do add(id) end
  end
  if not whisperOnly then for _, e in ipairs(pack("1L|", parts, nil, "l")) do queue(e) end end
  whisper(mine, packer("1L|", "l"))
end

-- a boss kill's claim on the wire: "enc@time:sfx.sfx", the time the server's in base 36, the group as the last part of
-- each member's GUID, sorted; never longer than one message holds (Rules.lua names a group that fits; one kept from
-- before is cut to fit)
local function claimText(enc, t, with)
  local sfx = {}
  for g in pairs(type(with) == "table" and with or {}) do
    local s = type(g) == "string" and g:match("([^%-]+)$")
    if s then sfx[#sfx + 1] = (s:gsub("[^%w]", "")) end
  end
  table.sort(sfx)
  local head = math.floor(enc) .. "@" .. b36(t) .. ":"
  local text = table.concat(sfx, ".")
  while #sfx > 0 and #head + #text > LIMIT - #"1K|" do table.remove(sfx); text = table.concat(sfx, ".") end
  return head .. text
end
-- a claim goes the way its boss's kills do and the way Grouped with does (it names the group): on GUILD, or whispered
-- to the officers where they keep either to themselves. whisperOnly: the officers' part alone
local function claimsOut(list, force, told, whisperOnly)
  local targets = told or C.Roster:OfficerTargets()
  local parts, mine = {}, {}
  for _, c in ipairs(list) do sortParts("k", { id = "e" .. c.enc, also = "group", kv = claimText(c.enc, c.t, c.with) }, force, targets, parts, mine) end
  if not whisperOnly then for _, e in ipairs(pack("1K|", parts, nil, "k")) do queue(e) end end
  whisper(mine, packer("1K|", "k"))
end
-- your kill, with your group (Rules.lua R:Killed): told now, or, while your record waits for the policy, as it goes
-- (M:Release: a repeat kill's claim is kept nowhere else)
M.waitingClaims = {}
function M:Claim(enc, t, with)
  if not (self.started and self.hello and C.Roster:InGuild()) then return end
  if self.holding then
    if #self.waitingClaims < 64 then self.waitingClaims[#self.waitingClaims + 1] = { enc = enc, t = t, with = with } end
    return
  end
  claimsOut({ { enc = enc, t = t, with = with } })
end
-- the discoveries pass: each boss's first kill in a group, as this character keeps it (only those not told this
-- session; force: all, for an asker)
function M:Claims(force, told, whisperOnly)
  if not (self.hello and C.Roster:InGuild()) or self.holding then return end
  local list = {}
  for enc, c in pairs(C.Rules.OwnClaims()) do list[#list + 1] = { enc = enc, t = c.t, with = c.with } end
  table.sort(list, function(a, b) return a.enc < b.enc end)
  claimsOut(list, force, told, whisperOnly)
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

-- the ask, with the stamp of the officers' word this client holds (Policy.lua P:Stamp), of the newest officers' word
-- (1N) it holds (Rules.lua R.WordStamp) and the fingerprint of the policy it routes by (Policy.lua P:Fp)
function M:Ask()
  if not C.Roster:InGuild() then return end
  local guid = C.MyGUID()
  -- (one ask waiting at a time: a second would only be answered as the first)
  for _, m in ipairs(self.out) do if m.ask then return end end
  queue({ msg = "1R|" .. (guid and (guid:gsub("[|;=]", "")) or "") .. "|" .. string.format("%.0f", C.Policy:Stamp()) .. "|"
    .. string.format("%.0f", C.Rules.WordStamp()) .. "|" .. C.Policy:Fp() .. (self.SinceHex and self:SinceHex() or ""), first = true, ask = true })
end
-- an ask that never left (the client refused it, or an error on the way): asked again half a minute on, and when the
-- lockdown ends (M:Restriction)
function M:AskAgain()
  if not self.askOwed or self.askAgainDue then return end
  self.askAgainDue = true
  C_Timer.After(30, C.Safe(function()
    M.askAgainDue = false
    if M.askOwed and M.hello and not M:Locked() then M:Ask() elseif M.askOwed then M:AskAgain() end
  end, "comm: ask again"))
end
-- parts as messages under one head, each saying which of how many it is ("i/n|" after the head): a receiver takes
-- the whole once every part is in (a policy, the officers' word), and none of more than 64 messages, so what does not
-- fit in 64 is left out here (parts in the order given: the caller puts first what must go)
local NUMBERED_MAX = 64
local function numbered(head, parts)
  local list = {}
  for _, kv in ipairs(parts) do list[#list + 1] = { kv = kv, id = kv:match("^[^=]+"), key = kv, s = true } end
  local msgs = pack("", list, LIMIT - #head - #"64/64|")
  while #msgs > NUMBERED_MAX do table.remove(msgs) end
  if #msgs == 0 then msgs = { { msg = "" } } end
  local out = {}
  for i, m in ipairs(msgs) do out[i] = head .. i .. "/" .. #msgs .. "|" .. m.msg end
  return out
end
-- a policy as its messages: one per part that fits, all under the same "at"
local function policyMessages(at, threshold, parts) return numbered(string.format("1P|%.0f|%d|", at, threshold), parts) end
-- the policy held, to the guild: an officer's change, Broadcast now, an officer's login, a save to Guild Info. Only
-- while this client holds the line's policy (Policy.lua P:Settled): an officer who missed a save and has not read Guild
-- Info since would send the old line's routing stamped now, and every member online would wait for Guild Info, those
-- inside an instance the whole run. It goes once the client holds it (M:PolicySettled)
function M:SendPolicy()
  if not C.Roster:InGuild() then return end
  if not C.Policy:Settled() then self.policyOwed = true return end
  self.policyOwed = nil
  local at, threshold, parts = C.Policy:Parts()
  for _, m in ipairs(policyMessages(at, threshold, parts)) do queue({ msg = m, first = true }) end
end
-- Broadcast now (Settings, the Officers page): the policy stamped now and sent, the officers' word newer than any.
-- Where the guild has a line, who sees what goes by Guild Info alone, and the chat line says so
function M:Broadcast()
  if not C.Roster:MeOfficer() then return end
  C.Policy:Restamp()
  self:SendPolicy()
  if self.policyOwed then
    C.Print("the policy goes to the guild once Guild Info is read.")
  elseif type(C.Policy.line) == "table" then
    C.Print(C.Policy:EditPending() and "sent the rules and the untrusted; who sees what goes by Guild Info: Save to Guild Info to change it."
      or "sent the rules and the untrusted; who sees what goes by Guild Info.")
  else
    C.Print("sent the policy to the guild: who sees what, the rules and the untrusted.")
  end
end
-- Save to Guild Info (Settings' button, a click: Policy.lua P:Save), then the policy sent, so the clients online stop
-- sending and read Guild Info again at once (Policy.lua P.doubt, Roster.lua R:AskSoon), not at their next minute's
-- roster read. True, or false and why
function M:SaveLine()
  if not C.Roster:MeOfficer() then return false, "officers only" end
  local ok, why = C.Policy:Save()
  if not ok then C.Print("the policy was not saved: " .. tostring(why)); return false, why end
  self:SendPolicy()
  C.Print("saved the policy to Guild Info: every client routes by it.")
  return true
end
-- an officer's change in Settings goes to the guild on its own, three seconds after the last of a run of clicks (each
-- click starts the wait again: only the last one's timer sends)
function M:PolicySoon()
  self.policyGen = (self.policyGen or 0) + 1
  local gen = self.policyGen
  C_Timer.After(3, C.Safe(function() if M.policyGen == gen and C.Roster:MeOfficer() then M:SendPolicy() end end, "comm: the policy"))
end

-- an ask answered with the policy (the ask carries the asker's stamp). An officer answers an asker whose officers'
-- word is older than its own, with its rules and untrusted (and, where the guild has no line, its visibility and
-- ranks); nobody else does: where the guild has a line every client reads the policy in it. One answer (a round) waits
-- for every ask that comes meanwhile, a second and a second more for each officer who may answer before it (place,
-- below), and goes only while what was heard since does not already say it, checked again as each message leaves the
-- queue: an officer's word at least as new. So the officers online answer once, and a copy that answers first
-- silences nobody
local rounds = {} -- the rounds still to answer, waiting their time or their turn in the queue: { route, word, heard, left }
local function over(r)
  for i = #rounds, 1, -1 do if rounds[i] == r then table.remove(rounds, i) end end
end
-- this client's place among those who may answer, by GUID: the members online whose Cute has spoken on the guild
-- channel (an officer: the officers online), ten at most. The lowest answers first and each next a second later, so the
-- rest hear the first answer before their own goes (a random wait alone let a cohort that drew the same second answer
-- together, none hearing the others)
-- (GUIDs ordered byte by byte, as Policy.lua orders its codes: Lua's < on strings asks the C runtime's collation,
-- which a Norwegian or German Windows client may order otherwise, and two clients would each take the first place)
local function before(a, b)
  for i = 1, math.min(#a, #b) do
    local x, y = a:byte(i), b:byte(i)
    if x ~= y then return x < y end
  end
  return #a < #b
end
M.Before = before
local function place(officer)
  local mine, n = C.MyGUID() or "", 0
  local R = C.Roster
  if not R.trusted then return 0 end
  if officer then
    for _, t in ipairs(R:OfficerTargets()) do
      local e = CuteDB.roster[t]
      local g = type(e) == "table" and type(e.stats) == "table" and e.stats.guid
      if type(g) == "string" and before(g, mine) then n = n + 1 end
    end
  else
    for key, e in pairs(CuteDB.roster) do
      local g = type(e) == "table" and e.ch and type(e.stats) == "table" and e.stats.guid
      if type(g) == "string" and before(g, mine) then
        local m = R.byGuid[g]
        if m and m.online and not m.self then n = n + 1 end
      end
    end
  end
  return math.min(n, 10)
end
M.Place = place
function M:AskedPolicy(stamp)
  local P = C.Policy
  if not (C.Roster:MeOfficer() and stamp ~= nil and P:Stamp() > stamp) then return end
  if self.round then return end
  local r = { heard = {}, left = 0 }
  self.round = r
  rounds[#rounds + 1] = r
  local f = math.random and math.random() or 0.5
  C_Timer.After(1 + place(true) + 0.4 * f, C.Safe(function() M:AnswerPolicy(r) end, "comm: answer policy"))
end
function M:AnswerPolicy(r)
  if self.round == r then self.round = nil end
  -- (as things stand now: this client may be no officer any more, or wait for Guild Info)
  if not (C.Roster:MeOfficer() and C.Roster:InGuild() and C.Policy:Settled()) then over(r); return end
  local at, threshold, parts = C.Policy:Parts()
  local function covered()
    for _, h in ipairs(r.heard) do if h.officer and h.at >= at then return true end end
    return false
  end
  if covered() then over(r); return end
  local function done() r.left = r.left - 1; if r.left <= 0 then over(r) end end
  for _, m in ipairs(policyMessages(at, threshold, parts)) do
    if queue({ msg = m, covered = covered, done = done, first = true }) then r.left = r.left + 1 end
  end
  if r.left == 0 then over(r) end
end

-- the officers' word (1N, Rules.lua R.WordParts): what an officer's client learned from what members' clients do not
-- receive, said on the guild channel when it changes and in answer to an ask whose word is older than this client's
-- last. Never while the record waits for the policy (which decides what the members do not receive), and nothing where
-- there is nothing to say. Several officers' clients learn the same thing at once (a member's record reaches them all),
-- so it is said once: each waits until what it queued before has gone (its record at login), then the officer online
-- with the lowest GUID a second or so, the others four to eight and a second more for each message the word takes (so
-- the first one's has all gone by then), and a message whose parts another officer said meanwhile does not leave
-- (checked as it leaves the queue). heard: each officer's newest word heard, by sender: { at, parts }
local word = { heard = {} }
local WORD_EVERY = 60 -- seconds before a word, unasked, follows the last (ten for each message it takes, if more)
local function wordMessages(at, parts) return numbered(string.format("1N|%.0f|", at), parts) end
-- every part said in another officer's newest word, which the members hold (Rules.lua R.Word: each officer's newest)
local function wordSaid(parts)
  local said = {}
  for sender, h in pairs(word.heard) do if C.Roster:OfficerVoice(sender) then for kv in pairs(h.parts) do said[kv] = true end end end
  for _, kv in ipairs(parts) do if not said[kv] then return false end end
  return #parts > 0
end
-- the officer who says it first: the lowest GUID among you and the officers the roster lists online (at login their
-- Cute's records may not have come yet, and two who each took themselves for the first both said it whole)
local function first()
  local mine = C.MyGUID() or ""
  local thr = C.Policy:LineThreshold()
  for _, m in ipairs(C.Roster.members) do
    if m.online and not m.self and m.rank <= thr and type(m.guid) == "string" and before(m.guid, mine) then return false end
  end
  return true
end
-- fn once the queue is empty and the wait above is over
local function quietly(fn, what)
  local function try()
    if #M.out > 0 then C_Timer.After(1, C.Safe(try, what)) return end
    local r = math.random and math.random() or 0.5
    C_Timer.After(first() and (0.5 + r) or (4 + 4 * r + #wordMessages(0, C.Rules.WordParts())), C.Safe(fn, what))
  end
  try()
end
function M:SendWord(answer, since)
  if not (self.started and self.hello and C.Roster:InGuild() and C.Roster:MeOfficer()) or self.holding then return end
  -- (while an officer's change of who sees what is not saved, the members route by the line: the word said last stays
  -- right, and goes as it was, so a click on an unrelated pair sends nothing)
  local parts = (C.Policy:EditPending() and word.parts) or C.Rules.WordParts()
  local text = table.concat(parts, ";")
  -- (a /reload or a relog: what this client said last, by its hash, is what the members hold, under its stamp; said again
  -- only as an answer)
  local h, saved = C.Policy.Fnv(text, 2166136261) .. ":" .. #text, C.Char().word
  if word.text == nil and type(saved) == "table" and saved.h == h and tonumber(saved.at) then
    word.text, word.at, word.parts = text, tonumber(saved.at), parts
    if not answer then return end
  end
  -- (unchanged since it was last said goes again only as an answer, and not where it was said since the ask came;
  -- nothing to say never goes)
  if (not answer and text == (word.text or "")) or (answer and #parts == 0) then return end
  if answer and text == word.text and word.said and since and word.said >= since then return end
  -- a word that takes something back goes whatever another officer said: the members hold this client's last one
  -- until it says otherwise (a range moved, a member the officers marked untrusted taught it). Unasked, a word goes
  -- once in WORD_EVERY at most, or ten seconds for each message it takes where that is longer: the whole word goes each
  -- time (up to 64 messages where the officers keep Bosses), so a run of kills, or a range moving a level, says it once
  -- and keeps the officer's own deltas moving; it names nobody, and late costs nothing. What the officers did
  -- themselves (a member marked untrusted, a rule retuned, the policy changed: word.urgent) goes at once
  local now, back = {}, false
  for _, kv in ipairs(parts) do now[kv] = true end
  for kv in (word.text or ""):gmatch("[^;]+") do if not now[kv] then back = true end end
  local every = math.max(WORD_EVERY, 10 * #wordMessages(0, parts))
  if not answer and not word.urgent and word.sentAt and clock() - word.sentAt < every then
    if not word.later then
      word.later = true
      C_Timer.After(every - (clock() - word.sentAt), C.Safe(function() word.later = false; M:SendWord(false, since) end, "comm: the officers' word"))
    end
    return
  end
  word.sentAt, word.urgent, word.said = clock(), nil, C.ServerNow()
  -- (its stamp stays while what it says does not change, a /reload or a relog included (CuteDB.chars[me].word: the
  -- text's hash): a member holding it neither asks it again nor takes it again)
  local at
  if word.at and text == word.text then at = word.at
  elseif type(saved) == "table" and saved.h == h and tonumber(saved.at) then at = tonumber(saved.at)
  else
    at = math.floor(C.ServerNow())
    if word.at and at <= word.at then at = word.at + 1 end
  end
  word.text, word.at, word.parts = text, at, parts
  C.Char().word = { h = h, at = at }
  -- (the parts the messages carry: a word past 64 messages goes cut, Rules.lua puts first what must go)
  local msgs, carried = wordMessages(at, parts), {}
  for _, m in ipairs(msgs) do for kv in (m:match("^1N|%d+|%d+/%d+|(.*)$") or ""):gmatch("[^;]+") do carried[#carried + 1] = kv end end
  local covered = (not back) and function() return wordSaid(carried) end or nil
  for _, m in ipairs(msgs) do queue({ msg = m, covered = covered }) end
end
function M:WordSoon(urgent)
  if urgent then word.urgent = true end
  if word.due or not (self.started and self.hello) or self.holding or not C.Roster:MeOfficer() then return end
  word.due = true
  local since = C.ServerNow()
  quietly(function() word.due = false; M:SendWord(false, since) end, "comm: the officers' word")
end
-- an ask from a member: an officer whose last word is newer than the asker's (or who has said none yet and has
-- something to say) answers with it, unless another officer's answer said it all meanwhile; the same word once in
-- WORD_AGAIN seconds an asker (who: its GUID or sender string), so a copy asking every three minutes with an old
-- stamp has the whole word, up to 64 messages, resent once in half an hour. A client that sends no word stamp (0.5.x)
-- cannot read one
word.answered = {}
local WORD_AGAIN = 1800
function M:AskedWord(stamp, who)
  if stamp == nil or word.answering or not C.Roster:MeOfficer() then return end
  if word.at and stamp >= word.at then return end
  local a = who and word.answered[who]
  if a and a.at == word.at and C.Now() - a.t < WORD_AGAIN then return end
  if who then word.answered[who] = { t = C.Now(), at = word.at } end
  word.answering = true
  local since = C.ServerNow()
  quietly(function() word.answering = false; M:SendWord(true, since) end, "comm: answer the officers' word")
end
-- an officer's word heard (Comm:Receive has checked the sender): for the check above, its parts gathered under its
-- stamp (a long one comes in several messages), a newer stamp starting afresh
local function heardWord(sender, at, body)
  local h = word.heard[sender]
  if h and h.at > at then return end
  if not h or h.at ~= at then h = { at = at, parts = {}, n = 0 }; word.heard[sender] = h end
  for kv in (body or ""):gmatch("[^;]+") do if not h.parts[kv] and h.n < 512 then h.parts[kv] = true; h.n = h.n + 1 end end
end

-- the officers who asked since the last answer, as a list, and none waiting
local function takeAskers(field)
  local out = {}
  for sender in pairs(M[field]) do out[#out + 1] = sender end
  table.sort(out)
  M[field] = {}
  return out
end
-- the answer to the asks that came while it waited: the record (the guild's part where a fresh ask wants it, the
-- officers' part to each officer who asked), and the statistics pass
-- (since: the earliest since of the fresh asks, nil where one wants the whole record: M.answerFull)
function M:Answer()
  local guild, since = M.answerGuild, (not M.answerFull) and M.answerSince or nil
  M.answerGuild, M.answerFull, M.answerSince = false, nil, nil
  M:Full(takeAskers("askers"), not guild, guild and since or nil)
end
-- the statistics pass for the guild: what changed since the asks' since, or the whole pass, once in PASS_EVERY seconds
-- whoever asks (the asks meanwhile wait for the next: 0.7.0 resent it whole for every new asker, about sixty messages a
-- month in from each client online for every login); the officers who asked get their part whole at once
local PASS_EVERY = 600
function M:AnswerGame()
  local guild, since = M.answerGameGuild, (not M.gameFull) and M.gameSince or nil
  M.answerGameGuild, M.gameFull, M.gameSince = false, nil, nil
  local officers = takeAskers("gameAskers")
  if guild and since then
    M:FullGame(since, {}, false)
    if #officers > 0 then M:FullGame(true, officers, true) end
    return
  end
  if guild then
    local wait = M.passAt and (M.passAt + PASS_EVERY - C.Now()) or 0
    if wait > 0 then
      if #officers > 0 then M:FullGame(true, officers, true) end
      if not M.passDue then
        M.passDue = true
        C_Timer.After(wait, C.Safe(function()
          M.passDue = false
          M.answerGameGuild, M.gameFull = true, true
          if not C.Policy:Settled() or M:Locked() then M.gameOwed = true; return end
          M:AnswerGame()
        end, "comm: statistics, the next pass"))
      end
      return
    end
    M.passAt = C.Now()
    if M.wire then M.wire.passAt = M.passAt end
  end
  M:FullGame(true, officers, not guild)
end
-- an answer to the asks, once for all that come while it waits: two to forty seconds on, so a login heard by a guild
-- online is answered over forty seconds, not twenty
function M:AnswerSoon()
  if M.answering then return end
  M.answering = true
  local wait = 2 + (math.random and (38 * math.random()) or 10)
  C_Timer.After(wait, C.Safe(function()
    M.answering = false
    if M.holding then return end
    -- (while this client waits for the line, P.doubt, or the game holds addon chat back, the answer waits too: what
    -- it would queue could not leave)
    if not C.Policy:Settled() or M:Locked() then M.answerOwed = true; return end
    M:Answer()
  end, "comm: answer"))
end
-- what an ask's since is worth here: the since, where this client's own record went whole on GUILD this login before
-- it (M.base: the asker heard it, or asked after it and had it answered), else nil, the whole record
local function sinceOf(since)
  if type(since) ~= "number" or not M.base or since < M.base then return nil end
  return math.min(since, C.ServerNow())
end
-- a member who holds no record of yours asks for it whole (1Q: after a since answer or a delta from a sender it holds
-- none of), answered as a fresh ask wanting the whole record, the guild's part alone, once in ASK_AGAIN seconds
M.wholeAsked, M.wholeAskedOf = {}, {}
function M:AskedWhole(sender)
  local who = C.Roster:GuidOf(sender) or sender
  local t = C.Now()
  if M.wholeAsked[who] and t - M.wholeAsked[who] < 180 then return end
  M.wholeAsked[who] = t
  M.answerGuild, M.answerFull = true, true
  self:AnswerSoon()
end
-- the record of a sender this client holds none of came in part (a delta, or an answer since its since: partial):
-- its whole record asked for (1Q), of the member the roster names by the sender string (by GUID: no name on the
-- wire), once a session, unless a whole one came meanwhile (any record chunk not marked "s"). Not before this client's
-- own ask left and a minute on, whose answers bring most (after a /reload, which asks nothing, at once)
M.partialOf, M.wholeOf = {}, {}
function M:WantWhole(sender, had, partial)
  if not partial then self.wholeOf[sender] = true return end
  if had or self.wholeOf[sender] then return end
  self.partialOf[sender] = true
  self:AskWholes()
end
function M:AskWholes()
  if not self.hello or next(self.partialOf) == nil then return end
  if not (self.reloaded or (self.syncedAt and C.Now() - self.syncedAt >= 60)) then
    if self.syncedAt and not self.wholesDue then
      self.wholesDue = true
      C_Timer.After(61 - (C.Now() - self.syncedAt), C.Safe(function() M.wholesDue = false; M:AskWholes() end, "comm: whole records"))
    end
    return
  end
  local list = {}
  for sender in pairs(self.partialOf) do list[#list + 1] = sender end
  table.sort(list)
  self.partialOf = {}
  for _, sender in ipairs(list) do
    local m = C.Roster:SenderMember(sender)
    if not (self.wholeOf[sender] or self.wholeAskedOf[sender]) and m and type(m.guid) == "string" and not m.self then
      self.wholeAskedOf[sender] = true
      queue({ msg = "1Q|" .. m.guid:gsub("[|;=]", ""), first = true })
    end
  end
end
-- the hold, ended (this client holds the policy Guild Info names: Policy.lua P:Settled): the record goes, routed by
-- the policy as it stands now, its Only-you part to every officer online and to the officers who asked meanwhile; then
-- what changed while it waited, and the kills claimed meanwhile; an officer's client says the officers' word it holds,
-- for a member online that holds an older one. Never before the roster is known (it is, where Guild Info was read)
function M:Release()
  if not self.holding then return end
  if not C.Roster.trusted then
    local gen = self.holdGen
    C_Timer.After(2, C.Safe(function() if M.holdGen == gen then M:Release() end end, "comm: release"))
    return
  end
  self.holding = false
  -- (the officers' policy is known now: whether this client is an officer, and what it keeps, Roster.lua)
  if C.Roster.PurgeCheck then C.Roster:PurgeCheck() end
  if not C.Roster:InGuild() then return end
  if C.Roster:MeOfficer() and C.Policy:Stamp() > 0 then self:SendPolicy() end
  local told, seen = {}, {}
  for _, t in ipairs(C.Roster:OfficerTargets()) do if not seen[t] then seen[t] = true; told[#told + 1] = t end end
  for t in pairs(self.askers) do if not seen[t] and C.Roster:OfficerSender(t) then seen[t] = true; told[#told + 1] = t end end
  self.askers = {}
  table.sort(told)
  self:ReleaseRecord(told)
  self:Changed()
  local claims = self.waitingClaims
  self.waitingClaims = {}
  if #claims > 0 then claimsOut(claims) end
  -- (an officer's client: the guild's knowledge, now that the policy is known)
  self:WordSoon()
end
-- the record at the release: whole at a login; after a /reload only what changed since the last send before it, as
-- deltas, to the guild and to each officer (the guild holds the rest: M:Wire)
function M:ReleaseRecord(told)
  if not self.reloaded then self:Full(told) return end
  local head = "1D|" .. C.REGVER .. "|"
  local guild, mine = partsFor(recordIds(), false, told)
  for _, e in ipairs(pack(head, guild, nil, "v")) do queue(e) end
  whisper(mine, packer(head, "v"))
  for _, t in ipairs(told) do self.toldTo[t] = true end
end
-- the policy Guild Info names is held now (or the guild has no line): the record waiting at login goes, and the queue
-- moves again (Policy.lua P:Settle)
function M:PolicySettled(settled)
  if not settled then return end
  if self.holding then self:Release() end
  -- (an officer's change made while it waited: sent now)
  if self.policyOwed and C.Roster:MeOfficer() then self:SendPolicy() end
  self:PayOwed()
  M.Kick()
end
-- the answers that waited (for the policy Guild Info names, or for the lockdown to end), once each, by the policy now
function M:PayOwed()
  if not C.Policy:Settled() or self:Locked() then return end
  if self.answerOwed and not self.holding then
    self.answerOwed = nil
    self:Answer()
  end
  if self.gameOwed then
    self.gameOwed = nil
    self:AnswerGame()
  end
end
-- ADDON_RESTRICTION_STATE_CHANGED (type, state: RestrictedActionsDocumentation.lua:97): for the chat restriction,
-- Activating (1) and Active (2) hold the queue, Inactive (0) lets it go. The lockdown over: the answers owed go, an
-- ask that never left goes again, the queue at once
function M:Restriction(kind, state)
  kind, state = C.Plain(kind), C.Plain(state)
  if kind == nil or kind ~= restrictionKind() then return end
  local states = Enum and Enum.AddOnRestrictionState
  local inactive = type(states) == "table" and C.Plain(states.Inactive) or 0
  if state ~= nil and state ~= inactive then self.lockEvent = C.Now() return end
  self.lockEvent, self.lockSeen = nil, nil
  if self:Locked() then return end
  self:PayOwed()
  if self.askOwed and self.hello then self:Ask() end
  M.Resume()
end
-- out of the guild: the hello is owed again, said on the next refresh in one (Roster.lua), and the hold with it
function M:Left()
  self.hello, self.holding, self.policyOwed = false, false, nil
  self.holdGen = (self.holdGen or 0) + 1
  -- (another guild, or this one again: its hello asks, and its record goes whole)
  self.reloaded, self.base, self.fullOut = nil, nil, nil
end

----------------------------------------------------------------------------
-- receiving
----------------------------------------------------------------------------
local function decodeBody(body)
  local kv = {}
  for id, s in (body or ""):gmatch("([%l%d_]+)=([^;]*)") do
    local def = defOf(id)
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

-- what a whisper may carry: the values, labels and kill claims the officers alone see
local WHISPERED = { ["1D"] = true, ["1F"] = true, ["1L"] = true, ["1K"] = true }
-- whispers that come before the roster is known (an officer's client, its roster slow at login): kept in memory and
-- judged once it is (Roster.lua calls ReplayEarly), not dropped while the members count them as told. And the records
-- and deltas from the guild channel too: a record made before the roster listed anyone would decide whose guild the
-- saved variables of 0.5.x are (Policy.lua P:Adopt), by what this session heard rather than what was saved
M.early, M.waiting = {}, {}
-- (a guild of hundreds answers a login with hundreds of records: 2000 hold them while C_Club is slow after a restart;
-- one dropped is a loss this login's hold does not move past, M:Logout)
local EARLY_CAP, EARLY_EACH = 2000, 32 -- (of one sender: a copy's burst pushes no officer's or member's whispers out)
function M:ReplayEarly()
  local list = self.early
  self.early = {}
  for _, m in ipairs(list) do self:Receive(m[1], m[2], m[3]) end
end
-- the asks answered lately, by asker (one ask a sender in ASK_AGAIN seconds starts an answer), and when the statistics
-- pass last answered each member's (once in GAME_AGAIN seconds a member; an officer's always): a copy that asks every
-- few seconds makes nobody resend
local ASK_AGAIN, GAME_AGAIN, POLICY_AGAIN, UNTRUSTED_AGAIN = 180, 1800, 30, 300
M.answered, M.gameAnswered, M.policyAsked = {}, {}, {}

function M:Receive(text, channel, sender)
  text, channel, sender = C.Plain(text), C.Plain(channel), C.Plain(sender)
  if type(text) ~= "string" or type(sender) ~= "string" then return end
  local whispered = channel == "WHISPER"
  if channel ~= "GUILD" and not whispered then return end
  local R = C.Roster
  local kind = text:sub(1, 2)
  if whispered and not WHISPERED[kind] then return end
  if not R.trusted and (whispered or kind == "1F" or kind == "1D") then
    local n = 0
    for _, m in ipairs(self.early) do if m[3] == sender then n = n + 1 end end
    if #self.early < EARLY_CAP and n < EARLY_EACH then self.early[#self.early + 1] = { text, channel, sender } else self.lost = true end
    return
  end
  -- the GUID a full record or an ask carries decides whether the message is yours, handed back by the game; a delta
  -- or a policy carries none, and Roster.lua goes by the sender string (R:FromMe). It is taken only where the roster
  -- bears it out (R:Vet): an edited copy can put any member's GUID in its messages, an officer's included, and one the
  -- roster gives a member the sender string does not name is dropped, the sender marked suspect. Who is an officer
  -- goes by the member the sender string names, never by a GUID (R:OfficerSender)
  local kv, guid, forged, stamp, wstamp, fp, since
  if kind == "1F" then kv = decodeBody(text:match("^1F|%d+|%d+|[^|]*|(.*)$")); guid = kv.guid
  elseif kind == "1R" then
    local rest = text:match("^1R|(.*)$")
    if rest then
      guid = rest:match("^([^|]*)")
      local s1, s2, s3 = rest:match("^[^|]*|(%d+)|?(%d*)|?(%x*)$")
      stamp, wstamp = tonumber(s1 or ""), tonumber(s2 or "")
      -- (the fingerprint's 16 hex digits, then the since in hex where the asker holds the guild from a time: M:Ask)
      if s3 and #s3 >= 16 then
        fp = s3:sub(1, 16):lower()
        if #s3 > 16 and #s3 <= 24 then since = tonumber(s3:sub(17), 16) end
      end
      if guid == "" then guid = nil end
    end
  end
  if guid then
    local ok, why = R:Vet(sender, guid)
    if not ok then guid, forged = nil, why end
  end
  -- a whisper from someone the roster does not show in the guild, or carrying a GUID that is not the sender's, is no
  -- one's; one from a member whose full record has not come on the guild channel yet waits for it (M.waiting)
  if whispered then
    local ok = not forged and R:GuildSender(sender, guid)
    if ok == "wait" then
      local w = M.waiting[sender]
      if not w then w = {}; M.waiting[sender] = w end
      if #w < 32 then w[#w + 1] = text end
      return
    end
    if not ok then R:Forged(sender, forged, false); return end
  else
    R.heard[sender] = true
  end
  local me, how
  if forged then me = R:NamesMe(sender) else me, how = R:FromMe(sender, guid) end
  if me then
    R:SelfSender(sender, how)
    for _, e in ipairs(self.senders) do if e.sender == sender then e.me = true end end
    return
  end
  if guid or forged then R:NotMe(sender) end
  if kind == "1D" then
    local body = text:match("^1D|[^|]*|(.*)$")
    local had = CuteDB.roster[sender] ~= nil
    R:Apply(sender, decodeBody(body), whispered)
    if not whispered then self:WantWhole(sender, had, true) end
  elseif kind == "1F" then
    -- (the record as it came: Apply vets its GUID again and marks the sender; a part since an ask's since, its version
    -- field marked "s", from a sender this client held no record of, asks for the whole one)
    local had = CuteDB.roster[sender] ~= nil
    R:Apply(sender, kv, whispered)
    if not whispered then self:WantWhole(sender, had, (text:match("^1F|%d+|%d+|([^|]*)|") or ""):sub(-1) == "s") end
    -- (whispers that waited for this sender's record to carry its GUID are taken now)
    local w = not whispered and M.waiting[sender]
    if w then
      M.waiting[sender] = nil
      for _, t in ipairs(w) do self:Receive(t, "WHISPER", sender) end
    end
    -- an officer's record on the guild channel: one you have not told your Only-you values this session gets them
    if not whispered and not forged and R:OfficerSender(sender) then self:TellOfficer(sender) end
  elseif kind == "1R" then
    -- everyone answers, spread over twenty seconds so a login does not fire twenty clients at once, and once for all
    -- who ask while the answer waits (an asker is online by the time it goes); the policy goes on its own, sooner, from
    -- a client holding the one Guild Info names where the asker holds another, and from an officer whose word is newer
    -- (AskedPolicy). The statistics follow a minute later, in their own pass. An officer who asked
    -- gets the Only-you part too, whispered (one who logs in after the values went); an ask with a GUID that is not the
    -- sender's is answered as anyone's, its sender marked. While your own record waits for the policy the answer waits
    -- with it, and its release answers them all
    -- (an officer's ask whispers it the Only-you part; a 0.5.x officer's, which carries no stamp, would drop the whisper)
    local officer = not forged and R:OfficerSender(sender) and stamp ~= nil
    if forged then R:Forged(sender, forged, true)
    elseif officer then M.askers[sender] = true; M.gameAskers[sender] = true; M.toldTo[sender] = true end
    -- (the policy once in POLICY_AGAIN seconds an asker, while what this client would answer with is the same: a copy
    -- that asks every second keeps no queue busy with it, an honest asker's next ask after a change is answered; a
    -- member the officers marked untrusted once in UNTRUSTED_AGAIN, whatever changed)
    local g = R:GuidOf(sender)
    local bad = g ~= nil and C.Policy:Untrusted(g)
    local said, key = M.policyAsked[g or sender], C.Policy:Fp() .. ":" .. C.Policy:Stamp()
    if not (said and (said.key == key or bad) and C.Now() - said.t < (bad and UNTRUSTED_AGAIN or POLICY_AGAIN)) then
      M.policyAsked[g or sender] = { t = C.Now(), key = key }
      self:AskedPolicy(stamp)
    end
    -- a member the officers marked untrusted gets the policy alone; anyone else's ask starts an answer (the officers'
    -- word, the record) once in ASK_AGAIN seconds, and the statistics pass once in GAME_AGAIN. An officer's ask always
    -- gets the part the officers keep, whispered; the guild's part, which a /reload keeps, goes again on those terms
    -- alone (every officer's /reload made every client resend all of it on GUILD)
    if bad then return end
    local t, who = C.Now(), g or sender
    local fresh = not (M.answered[who] and t - M.answered[who] < ASK_AGAIN)
    if not (fresh or officer) then return end
    -- (since: an asker that holds the guild from a time is sent what changed since, M:Answer; the earliest of the asks
    -- an answer covers, the whole record where one wants it)
    local s = sinceOf(since)
    -- (an ask heard before this login's own record started out is answered by that record, and by its own statistics
    -- pass after it: everyone online hears both. A login wave's asks no longer make each client send its record twice)
    local covered = self.hello and not self.reloaded and not self.fullOut
    if fresh then
      M.answered[who] = t
      if not covered then
        M.answerGuild = true
        if s == nil then M.answerFull = true elseif not M.answerFull then M.answerSince = math.min(M.answerSince or s, s) end
      end
    end
    -- (an officer has what the word is made of)
    if fresh and not R:OfficerVoice(sender) then self:AskedWord(wstamp, who) end
    self:AnswerSoon()
    -- the statistics pass, never for a bare ask (0.3.x, 0.5.x: the record alone)
    if stamp ~= nil and (#C.Stats.byCat.game > 0 or #C.Stats.byCat.found > 0 or next(C.Rules.OwnClaims()) ~= nil) then
      -- (an ask while a pass waits is answered by it: counted only where it makes that pass the guild's too)
      local gameFresh = not (M.gameAnswered[who] and t - M.gameAnswered[who] < GAME_AGAIN)
      if gameFresh and not covered then
        if s == nil then M.gameFull = true elseif not M.gameFull then M.gameSince = math.min(M.gameSince or s, s) end
      end
      if gameFresh and (not M.answeringGame or not M.answerGameGuild) then M.gameAnswered[who] = t; if not covered then M.answerGameGuild = true end end
      if (gameFresh or officer) and not M.answeringGame then
        M.answeringGame = true
        local wait = GAME_AFTER - 30 + (math.random and (29 * math.random()) or 5)
        C_Timer.After(wait, C.Safe(function()
          M.answeringGame = false
          if not C.Policy:Settled() or M:Locked() then M.gameOwed = true; return end
          M:AnswerGame()
        end, "comm: answer statistics"))
      end
    end
  elseif kind == "1P" then
    -- (a part of how many: 0.6.0's. 0.5.x's says none, and names stats by id: passed by)
    local at, thr, part, parts, body = text:match("^1P|(%d+)|(%d+)|(%d+)/(%d+)|(.*)$")
    local h = at and C.Policy:Receive(sender, at, thr, body, part, parts)
    -- (heard whole while an answer of ours waits: ours goes only where it says something this one does not)
    if type(h) == "table" and rounds[1] then
      -- (an officer the officers marked untrusted covers nothing: honest officers answer all the same)
      local x = { fp = h.fp, at = h.at, officer = R:OfficerVoice(sender) }
      for _, r in ipairs(rounds) do if #r.heard < 64 then r.heard[#r.heard + 1] = x end end
    end
  elseif kind == "1N" then
    -- the officers' word, only from a sender the roster names an officer by: an edited copy's teaches nothing
    local at, part, parts, body = text:match("^1N|(%d+)|(%d+)/(%d+)|(.*)$")
    if not at then at, body = text:match("^1N|(%d+)|(.*)$") end
    at = tonumber(at)
    if at and R:OfficerVoice(sender) then
      heardWord(sender, at, body)
      C.Rules.ReceiveWord(sender, at, body, part, parts)
    end
  elseif kind == "1Q" then
    -- (a member asking for this client's record whole, by its GUID: another's is passed by)
    local g = text:match("^1Q|([^|;=]+)$")
    if g and g == C.MyGUID() then self:AskedWhole(sender) end
  elseif kind == "1L" then
    self:ReceiveLabels(text:match("^1L|(.*)$"), sender)
  elseif kind == "1K" then
    self:ReceiveClaims(text:match("^1K|(.*)$"), sender)
  end
end

-- kill claims from a member (Rules.lua rule 9 weighs them): the sender's GUID by the roster, each group member's by the
-- last part of their GUID among the roster's and the records'. An untrusted sender's, and on a member's client a claim
-- on a boss the officers keep to themselves, or while they keep Grouped with (a claim names the group: only a modified
-- Cute would send it on GUILD), are passed by
function M:ReceiveClaims(body, sender)
  if type(body) ~= "string" then return 0 end
  local R = C.Roster
  local g = R:GuidOf(sender)
  if not g or C.Policy:Untrusted(g) then return 0 end
  -- (an officer at the last read that said, while this one lists her without a rank, is one still: Roster.lua)
  local officer, n = R:OfficerStill(), 0
  if not officer and C.Policy:Route("group") == "self" then return 0 end
  for enc, t, list in body:gmatch("(%d+)@(%w+):([%w%.]*)") do
    enc, t = tonumber(enc), unb36(t)
    if enc and enc < 2 ^ 31 and t and n < 64 and (officer or C.Policy:Route("e" .. enc) == "all") then
      local with, k = {}, 0
      for s in list:gmatch("%w+") do
        local wg = R:GuidBySuffix(s)
        if wg and wg ~= g and k < 40 then with[wg] = true; k = k + 1 end
      end
      C.Rules.Claim(g, enc, t, with)
      n = n + 1
    end
  end
  return n
end

-- labels from the channel: each is the sender's voice (Stats.lua S.Label: a name where none is, two members' word where
-- something is decided), and defines the stat it names once a member's value for it came or two agree, so the
-- Statistics page shows it with every member's value already kept. A key that does not parse, an id out of range or a
-- label that cleans to nothing is skipped. A boss's loot names who saw it (by GUID, in what the guild learns), taken
-- only for a boss the guild has a name for or a kill a group mate named back. A label says who met the thing, so on a
-- member's client one of a category the officers keep to themselves, a boss's loot with its boss, is passed by, as its
-- claims are (only a modified or 0.5.x Cute sends it on GUILD)
local MAX_ID = 2 ^ 31
-- the id a label's route is the policy's for: its own, or for an instance whose kind this client does not know for sure
-- the kind the label says (its own route would be the stricter of Dungeons and Raids, and a member's client would
-- learn no dungeon's name while the officers keep Raids)
local KIND_ROUTE = { p = "gc_dungeons", r = "gc_raids" }
local function labelRoute(p, num, extra)
  if p == "i" and KIND_ROUTE[extra] then local _, sure = C.Stats.KindOf(num); if not sure then return KIND_ROUTE[extra] end end
  return p .. num
end
function M:ReceiveLabels(body, sender)
  if type(body) ~= "string" then return 0 end
  local S, n, before = C.Stats, 0, C.Stats.foundVersion
  -- (who said it: a voice in what the labels decide, and who saw a boss's loot, in rule 8; both need two. Nothing
  -- from a member the officers marked untrusted, nor from a sender the roster has no GUID for)
  local who = sender and C.Roster:GuidOf(sender) or nil
  if not who or C.Policy:Untrusted(who) then return 0 end
  local officer = C.Roster:OfficerStill()
  for key, label in body:gmatch("([^=;]+)=([^;]*)") do
    local p, num, extra = key:match("^([efi])(%d+):?([%w]*)$")
    num = tonumber(num)
    local loot = tonumber(key:match("^l(%d+)$"))
    if loot and loot < MAX_ID then
      local named = S.LabelOf("e" .. loot) ~= nil
      if (officer or C.Policy:Route("e" .. loot) == "all") and (named or C.Rules.KilledSeen(loot)) then
        -- a boss's loot as a member saw it: item ids in base 36, dots between
        local ids = {}
        for x in label:gmatch("[%w]+") do local id = unb36(x); if id and id > 0 and id < MAX_ID and #ids < 24 then ids[#ids + 1] = id end end
        C.Rules.LearnLoot(loot, ids, false, who)
        n = n + 1
      end
    elseif p and num and num < MAX_ID and #key <= 24 and (officer or C.Policy:Route(labelRoute(p, num, extra)) == "all") then
      if p == "e" then
        local inst = tonumber(extra)
        S.Label("e" .. num, label, false, (inst and inst < MAX_ID) and inst or nil, nil, who)
        n = n + 1
      elseif p == "i" and (extra == "p" or extra == "r" or extra == "w") then
        S.Label("i" .. num, label, false, nil, extra, who)
        n = n + 1
      elseif p == "f" and extra == "" then
        S.Label("f" .. num, label, false, nil, nil, who)
        n = n + 1
      end
    end
  end
  if S.foundVersion ~= before then
    if C.UI and C.UI.Refresh then C.UI:Refresh() end
    -- (a dungeon or a boss joins the rules' model by its label: one that comes after the kills it names is weighed now,
    -- not at the next record)
    if C.Rules and C.Rules.Dirty then C.Rules:Dirty() end
  end
  return n
end

-- hello: ask for everyone's record (your GUID in the ask, so the game's copy of it tells you your sender string; the
-- stamp of your officers' word, so an officer whose word is newer answers with it), and the statistics a minute and a
-- half on. The record waits until this client holds the policy
-- Guild Info names (M:Release, Policy.lua P:Settled): at once where it does. Said only in a guild: a character that
-- logs in without one says it on the first roster refresh after joining (Roster.lua), before any change goes out as a
-- delta. (A hello counted as said while guildless would let your deltas, which carry no GUID, come back after a join
-- under a sender string nothing knows as you, and make 0.3.0's ghost row again)
function M:Hello()
  if self.hello or not self.helloDue or not self.started or not C.Roster:InGuild() then return end
  self.hello, self.holding, self.helloAt = true, true, C.Now()
  self.holdGen = (self.holdGen or 0) + 1
  -- (a /reload asks nothing: the saved records are the guild as it was a moment ago, M:Wire; an ask of this login that
  -- never left goes now. The ask waits for the roster to read: answers that came before it would crowd the early
  -- buffer)
  if not self.reloaded or self.askOwed then
    if C.Roster.trusted then self:Ask() else self.askDue = true end
  end
  if C.Policy:Settled() then self:Release() end
  C_Timer.After(GAME_AFTER, C.Safe(function() M:FullGame(false) end, "comm: statistics"))
end

-- the roster read for the first time (Roster.lua): the hello's ask, where it waited for it
function M:RosterTrusted()
  if self.askDue then self.askDue = nil; self:Ask() end
end
-- every loading screen (Core.lua): the lockdown may have ended with it (a dungeon left), so what waited goes.
-- reloading: PLAYER_ENTERING_WORLD's isReloadingUi, at the first (M:Wire)
function M:Start(reloading)
  if self.started then
    if not self:Locked() then self:PayOwed(); if self.askOwed and self.hello then self:Ask() end; M.Resume() end
    return
  end
  if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return end
  -- (RegisterAddonMessagePrefixResult, ChatConstantsDocumentation.lua: 0 Success, 1 DuplicatePrefix; 2 InvalidPrefix
  -- and 3 MaxPrefixes leave Cute deaf and mute, which is said once in chat and kept for /cute diag)
  local ok, res = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
  res = ok and C.Plain(res) or "threw"
  self.prefixResult = res
  if not (res == nil or res == true or res == 0 or res == 1) then
    C.Err.Record("the game did not register Cute's addon channel (result " .. tostring(res) .. "): nothing is heard or said until it does", "", "comm: prefix")
  end
  self.started = true
  self:Wire(reloading)
  local f = CreateFrame("Frame")
  self.frame = f
  -- (every addon's messages come here, DBM's and WeakAuras' in a raid too: Cute's prefix is picked out before anything
  -- else runs, and only Cute's go through C.Safe; ADDON_RESTRICTION_STATE_CHANGED is the lockdown, M:Restriction)
  local saw = C.Safe(function(sender, prefix) M:Saw(sender, prefix) end, "comm: senders")
  local timed = C.Perf.Timed("receive", function(text, channel, sender) C.Perf.Count("cute"); M:Receive(text, channel, sender) end)
  local receive = C.Safe(timed, "comm: receiving")
  local restriction = C.Safe(function(kind, state) M:Restriction(kind, state) end, "comm: chat lockdown")
  f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if event == "CHAT_MSG_ADDON" then
      if C.Perf then C.Perf.Count("addon") end
      local prefix = C.Plain(a1)
      if #M.senders < 3 then saw(a4, prefix) end
      if prefix == PREFIX then receive(a2, a3, a4) end
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then restriction(a1, a2) end
  end)
  f:RegisterEvent("CHAT_MSG_ADDON")
  pcall(f.RegisterEvent, f, "ADDON_RESTRICTION_STATE_CHANGED") -- (a client without the event says no)
  -- the hello, eight seconds in (or when you join a guild)
  C_Timer.After(8, C.Safe(function() M.helloDue = true; M:Hello() end, "comm: hello"))
  -- the slow stats, every two minutes
  local function flush()
    C_Timer.After(SLOW_FLUSH, C.Safe(flush, "comm: flush"))
    M:Changed(true)
  end
  C_Timer.After(SLOW_FLUSH, C.Safe(flush, "comm: flush"))
end
