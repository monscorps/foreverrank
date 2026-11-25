-- SPDX-License-Identifier: GPL-3.0-or-later
-- The addon channel (PARTY, RAID or INSTANCE_CHAT, prefix "CuteAuras"). What a member's Cute Auras says, kept by GUID:
--   H1|guid|version|role|spec|level|known|pp  hello: the role and spec it plays, its level and the buffs it gives
--                                            others, "key:rank" joined by ";" ("-" none); pp when PallyPower runs on
--                                            that client, else "-" (0.2.3; older ones send 7 fields). Sent on joining,
--                                            on a change, and once to each member heard for the first time
--   O1|from|paladin|bucket|key|stamp|pp     a blessing set by hand in the grid ("-" back to Cute Auras' choice); only
--                                            the paladin or the group's leader or an assist may set it. pp (0.2.3): a
--                                            PallyPower leader set it for that paladin, who sends it as its own
--   Q1                                       everyone's hello again (a reload, a new group, a premade into its
--                                            battleground: the channel moved)
--   P1|sender|text                           a PallyPower message whispered to the asker, passed to the group as the
--                                            sender's (PallySync.lua; a NASSIGN too long for one, in parts)
--   S1|guid                                  our SELF on PLPWR comes next (a paladin running Cute Auras alone, before
--                                            each it sends): a SELF from a member whose hello says Cute Auras alone with
--                                            no S1 before it is PallyPower's, their hello old (Cute Auras turned off
--                                            there), and is let go
-- PallyPower's own prefix, PLPWR, is heard here too and handed to PallySync.lua, which speaks it through this queue.
-- Nothing waits on a message in a fight: the client may lock addon messages down there (SendAddonMessageResult 11),
-- and every client computes the same assignment from what it heard before. A message that can't go now goes after it.
local _, A = ...
local Cm = A.Part("Comm", { peers = {}, sent = 0, heard = 0, refusedName = 0, helloSent = false, selfMark = {} })
local plain, call = A.Plain, A.Call
local PREFIX = "CuteAuras"
Cm.PREFIX = PREFIX

-- (an instance group inside its instance, a battleground's: its chat, a premade's home group too, so the whole raid
-- the roster shares out over hears it, as PallyPower speaks there; an instance group alone, wherever)
local function channel()
  local inst = LE_PARTY_CATEGORY_INSTANCE or 2
  if A.Yes(IsInGroup, inst) and (A.Yes(IsInInstance) or not A.Yes(IsInGroup, LE_PARTY_CATEGORY_HOME or 1)) then return "INSTANCE_CHAT" end
  if A.Yes(IsInRaid) then return "RAID" end
  if A.Yes(IsInGroup) then return "PARTY" end
  return nil
end
Cm.Channel = channel

----------------------------------------------------------------------------
-- sending: one message every 0.3 s; one the client refuses (a lockdown, a throttle) is kept and sent after the fight.
-- A hello in the queue is replaced by the newer one in its place, and so is a waiting SELF, ASELF or FREEASSIGN on
-- PLPWR (a hello sent ahead of our SELF tells the others it is ours, PallySync's mirror guard). A message may wait on
-- its own (hold: PallySync's REQ while a paladin who would answer fights, the answer refused there and lost); the
-- ones after it go meanwhile. Its sent runs once it has left
----------------------------------------------------------------------------
local queue, running = {}, false
Cm.queue = queue -- ({ msg, prefix, hold, sent } each; for /dump and the harness)
local pump
local function later(seconds) if not running then running = true; A.After(seconds, pump, "comm") end end
-- the client's chat lockdown (a dungeon's or raid's map, an encounter: C_ChatInfo.InChatMessagingLockdown)
local function lockedDown()
  local CI = C_ChatInfo
  return CI ~= nil and type(CI.InChatMessagingLockdown) == "function" and A.Yes(CI.InChatMessagingLockdown)
end
function pump()
  running = false
  if #queue == 0 then return end
  local ch = channel()
  if not ch then for i = #queue, 1, -1 do queue[i] = nil end return end
  local CI = C_ChatInfo
  local send = CI and CI.SendAddonMessage
  if type(send) ~= "function" then return end
  -- (locked down: wait for the fight's end or the restriction's change, a look every 5 s meanwhile)
  if A.Fighting() then A.OutOfFight("comm", function() later(0.5) end) return end
  if lockedDown() then later(5) return end
  -- (the first that need not wait; every one waiting: a look again in 3 s)
  local at
  for i = 1, #queue do
    local hold, held = queue[i].hold, false
    if hold then A.Safe(function() held = hold() == true end, "comm: a message waiting")() end
    if not held then at = i break end
  end
  if not at then later(3) return end
  local item = queue[at]
  local ok, res = pcall(send, item.prefix or PREFIX, item.msg, ch)
  res = plain(res)
  local RES = Enum and Enum.SendAddonMessageResult or {}
  if ok and (res == nil or res == 0 or res == true or res == RES.Success) then
    table.remove(queue, at)
    Cm.sent = Cm.sent + 1
    if item.prefix == nil and item.msg:sub(1, 3) == "H1|" then Cm.helloSent = true end
    if item.sent then A.Safe(item.sent, "comm: a message sent")() end
  elseif res == RES.AddOnMessageLockdown or res == 11 then
    if A.Fighting() then A.OutOfFight("comm", function() later(0.5) end) else later(5) end
    return
  elseif res == RES.AddonMessageThrottle or res == RES.ChannelThrottle or res == 3 or res == 8 then
    later(1.5) -- (the throttle: kept, tried again)
    return
  else
    table.remove(queue, at) -- (not in a group any more, a bad message: dropped, never retried for ever)
  end
  if #queue > 0 then later(0.3) end
end
-- (the kind a newer message replaces in its place: our hello; PallyPower's SELF, ASELF, FREEASSIGN and REQ)
local function kindOf(msg, prefix)
  if prefix == nil then return msg:sub(1, 3) == "H1|" and "H1" or nil end
  local k = msg:match("^(%u+)")
  if k == "SELF" or k == "ASELF" or k == "FREEASSIGN" or k == "REQ" then return prefix .. ":" .. k end
  return nil
end
-- a message of that prefix and kind waits in the queue (PallySync: a SELF waiting has its S1 ahead of it)
function Cm.Waiting(prefix, kind)
  for i = 1, #queue do
    if queue[i].prefix == prefix and queue[i].msg:match("^(%u+)") == kind then return true end
  end
  return false
end
-- a message to the group: on our prefix, or another's (PLPWR). o (or nil): hold, true while it must wait; sent, once
-- it has left
function Cm.Send(msg, prefix, o)
  if not channel() then return false end
  local item = { msg = msg, prefix = prefix, hold = o and o.hold or nil, sent = o and o.sent or nil }
  local kind = kindOf(msg, prefix)
  if kind then
    for i = 1, #queue do
      if kindOf(queue[i].msg, queue[i].prefix) == kind then queue[i] = item; later(0) return true end
    end
  end
  -- (a blessing set again for the same paladin and bucket replaces the one still waiting)
  local key = prefix == nil and msg:match("^O1|[^|]*|([^|]*|[^|]*)|")
  if key then
    for i = #queue, 1, -1 do
      if queue[i].prefix == nil and queue[i].msg:match("^O1|[^|]*|([^|]*|[^|]*)|") == key then table.remove(queue, i) end
    end
  end
  -- (full: the oldest goes, never an S1 nor our SELF after it, which would read as PallyPower's without its S1)
  if #queue >= 30 then
    local at = 1
    for i = 1, #queue do
      local x = queue[i]
      if not ((x.prefix == nil and x.msg:sub(1, 3) == "S1|") or (x.prefix == "PLPWR" and x.msg:sub(1, 5) == "SELF ")) then at = i break end
    end
    table.remove(queue, at)
  end
  queue[#queue + 1] = item
  later(0)
  return true
end

----------------------------------------------------------------------------
-- your hello
----------------------------------------------------------------------------
local function myClass()
  local ok, _, class = pcall(UnitClass, "player")
  return ok and plain(class) or nil
end
-- the buffs you give others, enabled: "key:rank" each (a paladin's blessings too). A buff you'd never be asked for is
-- left out, so the share-out gives it to another buffer: the bar or its group part off, its icon on Never, or the bar
-- set to Nothing in the dungeon or raid you are in (each change sends a new hello)
function Cm.Known()
  local S, D = A.Spells, A.Data
  local s = A.Settings()
  if s.on == false or s.group == false then return "-" end
  if s.instance == "none" and A.Bar and A.Bar.InstanceKind and A.Bar.InstanceKind() then return "-" end
  local never = s.never
  local out = {}
  for _, e in ipairs(D.BUFFS[myClass() or ""] or {}) do
    if e.other and (not e.opt or s.opt[e.key]) and never["duty:" .. e.key] == nil then
      local r = S.RankKnown(e)
      if r > 0 then out[#out + 1] = e.key .. ":" .. r end
    end
  end
  if myClass() == "PALADIN" and s.blessings ~= false then
    for _, key in ipairs({ "kings", "might", "wisdom" }) do
      local r = never["duty:bless:" .. key] == nil and S.RankKnown(D.BLESS[key]) or 0
      if r > 0 then out[#out + 1] = key .. ":" .. r end
    end
  end
  table.sort(out)
  return #out > 0 and table.concat(out, ";") or "-"
end
-- why a paladin running Cute Auras gives no blessings now (nil: they give some, or aren't a paladin), in the
-- Settings' own words, so the Blessings tab can say which box to tick
function Cm.WhyNoBlessings()
  if myClass() ~= "PALADIN" then return nil end
  local s = A.Settings()
  if s.on == false then return "Show the bar is off" end
  if s.group == false then return "Buffs you give the group is off" end
  if s.instance == "none" and A.Bar and A.Bar.InstanceKind and A.Bar.InstanceKind() then return "In dungeons and raids is Nothing" end
  if s.blessings == false then return "Blessings shared out by Cute Auras is off" end
  local any = false
  for _, key in ipairs({ "kings", "might", "wisdom" }) do
    if A.Spells.RankKnown(A.Data.BLESS[key]) > 0 then
      any = true
      if s.never["duty:bless:" .. key] == nil then return nil end
    end
  end
  return any and "every blessing you know is on Never" or nil
end
-- a setting that changes what you give: a new hello, and your own share-out again
function Cm.GivesChanged()
  Cm.HelloSoon(1)
  if A.Assign then A.Assign.Changed() end
end
local lastHello
function Cm.Hello(force)
  local guid = A.MyGUID()
  if not guid then return end
  local role, spec = A.Roster.MyRole()
  local level = plain(call(UnitLevel, "player")) or 1
  local pp = A.PallySync and A.PallySync.Here() and "pp" or "-"
  local msg = string.format("H1|%s|%s|%s|%s|%d|%s|%s", guid, A.version, role or "", tostring(spec or 0), level, Cm.Known(), pp)
  if msg == lastHello and not force then return end
  if Cm.Send(msg) then lastHello = msg end
end
local helloSoon, helloForce = false, false
function Cm.HelloSoon(delay, force)
  -- (a forced hello asked while one waits makes that one forced: a late joiner's ask is never lost)
  if force then helloForce = true end
  if helloSoon then return end
  helloSoon = true
  A.After(delay or 2, function()
    local f = helloForce
    helloSoon, helloForce = false, false
    Cm.Hello(f)
  end, "comm: hello")
end

----------------------------------------------------------------------------
-- hearing
----------------------------------------------------------------------------
local function parseKnown(s)
  local out = {}
  if type(s) ~= "string" or s == "-" then return out end
  for key, rank in s:gmatch("([%a]+):(%d+)") do out[key] = tonumber(rank) end
  return out
end
Cm.ParseKnown = parseKnown
local function onHello(parts, sender)
  local guid = parts[2]
  if type(guid) ~= "string" then return end
  -- (our own, echoed: the sender string the server writes for us, QuestBank's way: Sync.lua)
  if guid == A.MyGUID() then
    if type(sender) == "string" then A.Roster.mySender = sender end
    return
  end
  local peers = Cm.peers
  local was = peers[guid]
  local known = parts[7] or "-"
  local p = { ver = parts[3], role = parts[4] ~= "" and parts[4] or nil, spec = tonumber(parts[5]) ~= 0 and tonumber(parts[5]) or nil,
              level = tonumber(parts[6]), knownText = known, known = parseKnown(known), at = A.Now(), sender = sender,
              ppField = parts[8] ~= "" and parts[8] or nil }
  peers[guid] = p
  -- (Cute Auras alone there: a SELF heard from them is our own, never PallyPower's)
  if p.ppField == "-" and A.PallySync then A.PallySync.Drop(guid) end
  -- (PallyPower turned on there since its last hello, a reload in the group: its SELF at login came before this hello
  -- and was taken for our own. The asker asks again)
  if was and was.ppField == "-" and p.ppField == "pp" and A.PallySync then A.PallySync.PPOn(guid) end
  local changed = not was or was.role ~= p.role or was.spec ~= p.spec or was.knownText ~= p.knownText or was.level ~= p.level
    or was.ppField ~= p.ppField
  -- (one heard for the first time hears yours back, once: a few seconds on, so a new group's hellos don't cross)
  if not was then
    Cm.HelloSoon(1 + (#guid % 7) * 0.3, true)
    if A.Assign then A.Assign.Resend() end -- (and the blessings you set by hand, with their stamps)
    -- (a 0.2.3 one never heard the PallyPower paladins' SELF: the asker asks them again)
    if p.ppField ~= nil and A.PallySync then A.PallySync.PeerHeard() end
  end
  if changed then
    A.Roster.Changed()
    if A.Assign then A.Assign.Changed() end
  end
end
-- S1: the member's SELF next is their Cute Auras' own (one at a time: that SELF takes it, Cm.TakeSelfMark)
local function onSelfMark(parts, sender)
  local guid = parts[2]
  if type(guid) ~= "string" or guid == A.MyGUID() then return end
  local m = A.Roster.ByGUID(guid)
  local who = A.Roster.SenderMember(sender)
  if not m or (who and who ~= m) then return end
  Cm.selfMark[guid] = true
end
function Cm.TakeSelfMark(guid)
  if not Cm.selfMark[guid] then return false end
  Cm.selfMark[guid] = nil
  return true
end
-- a member's hello is old: they speak as PallyPower with no word from their Cute Auras (turned off there). Let go, as if
-- never heard: they are no member running Cute Auras now, and their next hello is a first one
function Cm.Forget(guid)
  if not Cm.peers[guid] then return end
  Cm.peers[guid], Cm.selfMark[guid] = nil, nil
  A.Roster.Changed()
  if A.Assign then A.Assign.Changed() end
end
local function onOverride(parts, sender)
  local from, pal, bucket, key, stamp = parts[2], parts[3], parts[4], parts[5], tonumber(parts[6]) or 0
  if not (from and pal and bucket and key) or from == A.MyGUID() then return end
  local m = A.Roster.ByGUID(from)
  if not m then return end
  -- (the sender must not be another member: a message names its sender's GUID, the server names the sender, with
  -- Forever's surname after the first name, which UnitName leaves out: R.SenderMember)
  local who = A.Roster.SenderMember(sender)
  if who and who ~= m then Cm.refusedName = Cm.refusedName + 1 return end
  if A.Assign then A.Assign.SetOverride(pal, bucket, key ~= "-" and key or nil, stamp, from, parts[7] == "pp") end
end
local function onMessage(_, prefix, text, dist, sender)
  prefix = plain(prefix)
  -- (PallyPower's: PallySync reads it; a secret text or sender counted there)
  if prefix == "PLPWR" then
    if A.PallySync then A.PallySync.OnMessage(plain(text), plain(dist), plain(sender)) end
    return
  end
  text, sender = plain(text), plain(sender)
  if prefix ~= PREFIX or type(text) ~= "string" then return end
  Cm.heard = Cm.heard + 1
  -- (a PallyPower message the asker passes on: its own sender, then the PallyPower paladin's and its text, which may
  -- hold "|")
  if text:sub(1, 3) == "P1|" then
    local who, inner = text:match("^P1|([^|]*)|(.*)$")
    if who and A.PallySync then A.PallySync.OnRelay(sender, who, inner) end
    return
  end
  local parts = {}
  for p in (text .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = p end
  local kind = parts[1]
  if kind == "H1" then onHello(parts, sender)
  elseif kind == "O1" then onOverride(parts, sender)
  elseif kind == "S1" then onSelfMark(parts, sender)
  elseif kind == "Q1" then
    Cm.HelloSoon(1 + math.random() * 2, true)
    if A.Assign then A.Assign.Resend() end
    if A.PallySync then A.PallySync.PeerHeard() end
  end
end

----------------------------------------------------------------------------
-- a reload or a relog in the group: the hellos heard and the blessings you set by hand are saved at logout
-- (CuteAurasDB.chars[you].group) and read back at login, so the share-out is the group's at once, a fight's locked
-- chat or not; the members' own hellos then replace them. Kept an hour, for members still in the group
----------------------------------------------------------------------------
local KEEP = 3600
local function serverNow()
  local t = GetServerTime and plain(call(GetServerTime))
  if type(t) ~= "number" then t = time and time() or 0 end
  return t
end
function Cm.Save()
  local c = A.Char()
  if not A.Roster.InGroup() then c.group = nil return end
  local peers = {}
  for guid, p in pairs(Cm.peers) do
    peers[guid] = { ver = p.ver, role = p.role, spec = p.spec, level = p.level, known = p.knownText, pp = p.ppField }
  end
  -- (who was in the group: what is read back must be the same group, not a next one sharing a paladin)
  local members = {}
  for _, m in ipairs(A.Roster.members) do if m.guid and not m.me then members[#members + 1] = m.guid end end
  c.group = { at = serverNow(), peers = peers, overrides = A.Assign and A.Assign.Mine() or nil, members = members,
              pp = A.PallySync and A.PallySync.SaveTable() or nil }
end
-- the saved group is this one: most of either side's members are in both (a /reload keeps them all; a few joining or
-- leaving meanwhile still counts, a new group sharing one or two members does not)
local function sameGroup(saved)
  if type(saved.members) ~= "table" then return false end
  local now, n, both = {}, 0, 0
  for _, m in ipairs(A.Roster.members) do if m.guid and not m.me then now[m.guid] = true; n = n + 1 end end
  for _, guid in ipairs(saved.members) do if now[guid] then both = both + 1 end end
  local most = math.max(n, #saved.members)
  return most > 0 and both / most >= 0.6
end
function Cm.Restore()
  local c = A.Char()
  local saved = c.group
  if type(saved) ~= "table" or not A.Roster.InGroup() then return end
  c.group = nil
  local age = serverNow() - (tonumber(saved.at) or 0)
  if age < 0 or age > KEEP then return end
  A.Roster.Scan()
  if not sameGroup(saved) then return end
  local any = false
  for guid, p in pairs(type(saved.peers) == "table" and saved.peers or {}) do
    if type(p) == "table" and guid ~= A.MyGUID() and not Cm.peers[guid] and A.Roster.ByGUID(guid) then
      local known = type(p.known) == "string" and p.known or "-"
      Cm.peers[guid] = { ver = p.ver, role = p.role, spec = tonumber(p.spec), level = tonumber(p.level), knownText = known,
                         known = parseKnown(known), at = A.Now(), restored = true, ppField = type(p.pp) == "string" and p.pp or nil }
      any = true
    end
  end
  -- (the roles the peers announced, before the share-out is computed)
  if any then A.Roster.Scan() end
  if A.PallySync then A.PallySync.Restore(saved.pp) end
  if A.Assign then A.Assign.Restore(saved.overrides) end
  -- (your cells back: a leader's NASSIGN for a member who left meanwhile puts its bucket back now)
  if A.PallySync then A.PallySync.Settle() end
end

-- the channel moved under us while in a group (a premade into its battleground, where the battleground's raid hears
-- us, and back out): nobody there heard our hello, nor we theirs. Asked again as on joining: Q1 and our hello, forced;
-- our SELF waits for that hello (Cm.helloSent), as in a new group
local lastChannel
local function channelMoved()
  local ch, was = channel(), lastChannel
  lastChannel = ch
  if not (ch and was and ch ~= was and A.Roster.InGroup()) then return false end
  Cm.helloSent = false
  Cm.Send("Q1")
  Cm.HelloSoon(1, true)
  return true
end

-- members no longer in the group are forgotten
function Cm.Prune()
  for guid in pairs(Cm.peers) do if not A.Roster.ByGUID(guid) then Cm.peers[guid] = nil end end
  for guid in pairs(Cm.selfMark) do if not A.Roster.ByGUID(guid) then Cm.selfMark[guid] = nil end end
end
-- the members running Cute Auras now (you too): { [guid] = peer }
function Cm.Running(guid) return guid == A.MyGUID() or Cm.peers[guid] ~= nil end

function Cm:Init()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, "PLPWR")
  end
  A.On("CHAT_MSG_ADDON", onMessage)
  local inGroup = A.Roster.InGroup()
  A.On("GROUP_ROSTER_UPDATE", function()
    local now = A.Roster.InGroup()
    -- (in a group at last: a login the group was not known at yet reads back what was saved)
    if now and not inGroup then Cm.Restore(); Cm.Send("Q1"); Cm.HelloSoon(1, true); lastChannel = channel()
    elseif now then if not channelMoved() then Cm.HelloSoon(2) end end
    if not now then
      for k in pairs(Cm.peers) do Cm.peers[k] = nil end
      for k in pairs(Cm.selfMark) do Cm.selfMark[k] = nil end
      lastHello, Cm.helloSent, lastChannel = nil, false, nil
    end
    if now and not inGroup then Cm.helloSent = false end
    -- (you left: the blessings set by hand there are let go, and nothing is kept for a next login)
    if not now and inGroup then
      A.Char().group = nil
      if A.PallySync then A.PallySync.Forget() end
      if A.Assign then A.Assign.Forget() end
    end
    inGroup = now
    A.After(1, function()
      Cm.Prune()
      if A.PallySync then A.PallySync.Prune() end
    end, "comm: prune")
  end)
  A.On("PLAYER_LOGOUT", Cm.Save)
  -- (into or out of a dungeon or raid: the bar's Nothing there may change what you give)
  -- (and into a battleground: its raid hears us on another channel)
  A.On("PLAYER_ENTERING_WORLD", function() if A.Roster.InGroup() then channelMoved(); Cm.GivesChanged() end end)
  for _, ev in ipairs({ "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "PLAYER_ROLES_ASSIGNED",
                        "ACTIVE_TALENT_GROUP_CHANGED", "ACTIVE_COMBAT_CONFIG_CHANGED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" }) do
    A.On(ev, function() if A.Roster.InGroup() then Cm.HelloSoon(4) end end)
  end
  -- (a chat restriction lifted: what waits goes)
  A.On("ADDON_RESTRICTION_STATE_CHANGED", function() if #queue > 0 then later(0.5) end end)
  if inGroup then Cm.Restore(); Cm.Send("Q1"); Cm.HelloSoon(3, true) end
  lastChannel = channel()
end
