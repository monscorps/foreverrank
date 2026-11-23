-- SPDX-License-Identifier: GPL-3.0-or-later
-- The addon channel (PARTY, RAID or INSTANCE_CHAT, prefix "CuteAuras"). What a member's Cute Auras says, kept by GUID:
--   H1|guid|version|role|spec|level|known   hello: the role and spec it plays, its level and the buffs it gives others,
--                                            "key:rank" joined by ";" ("-" none). Sent on joining, on a change, and
--                                            once to each member heard for the first time
--   O1|from|paladin|bucket|key|stamp        a blessing set by hand in the grid ("-" back to Cute Auras' choice); only
--                                            the paladin or the group's leader or an assist may set it
--   Q1                                       everyone's hello again (a reload, a new group)
-- Nothing waits on a message in a fight: the client may lock addon messages down there (SendAddonMessageResult 11),
-- and every client computes the same assignment from what it heard before. A message that can't go now goes after it.
local _, A = ...
local Cm = A.Part("Comm", { peers = {}, sent = 0, heard = 0 })
local plain, call = A.Plain, A.Call
local PREFIX = "CuteAuras"
Cm.PREFIX = PREFIX

local function channel()
  local inst = LE_PARTY_CATEGORY_INSTANCE or 2
  if A.Yes(IsInGroup, inst) and not A.Yes(IsInGroup, LE_PARTY_CATEGORY_HOME or 1) then return "INSTANCE_CHAT" end
  if A.Yes(IsInRaid) then return "RAID" end
  if A.Yes(IsInGroup) then return "PARTY" end
  return nil
end
Cm.Channel = channel

----------------------------------------------------------------------------
-- sending: one message every 0.3 s; one the client refuses (a lockdown, a throttle) is kept and sent after the fight.
-- A hello in the queue is replaced by the newer one
----------------------------------------------------------------------------
local queue, running = {}, false
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
  local msg = queue[1]
  local ok, res = pcall(send, PREFIX, msg, ch)
  res = plain(res)
  local RES = Enum and Enum.SendAddonMessageResult or {}
  if ok and (res == nil or res == 0 or res == true or res == RES.Success) then
    table.remove(queue, 1)
    Cm.sent = Cm.sent + 1
  elseif res == RES.AddOnMessageLockdown or res == 11 then
    if A.Fighting() then A.OutOfFight("comm", function() later(0.5) end) else later(5) end
    return
  elseif res == RES.AddonMessageThrottle or res == RES.ChannelThrottle or res == 3 or res == 8 then
    later(1.5) -- (the throttle: kept, tried again)
    return
  else
    table.remove(queue, 1) -- (not in a group any more, a bad message: dropped, never retried for ever)
  end
  if #queue > 0 then later(0.3) end
end
function Cm.Send(msg)
  if not channel() then return false end
  if msg:sub(1, 3) == "H1|" then
    for i = #queue, 1, -1 do if queue[i]:sub(1, 3) == "H1|" then table.remove(queue, i) end end
  end
  -- (a blessing set again for the same paladin and bucket replaces the one still waiting)
  local key = msg:match("^O1|[^|]*|([^|]*|[^|]*)|")
  if key then
    for i = #queue, 1, -1 do if queue[i]:match("^O1|[^|]*|([^|]*|[^|]*)|") == key then table.remove(queue, i) end end
  end
  if #queue >= 30 then table.remove(queue, 1) end
  queue[#queue + 1] = msg
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
  local msg = string.format("H1|%s|%s|%s|%s|%d|%s", guid, A.version, role or "", tostring(spec or 0), level, Cm.Known())
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
  if type(guid) ~= "string" or guid == A.MyGUID() then return end
  local peers = Cm.peers
  local was = peers[guid]
  local known = parts[7] or "-"
  local p = { ver = parts[3], role = parts[4] ~= "" and parts[4] or nil, spec = tonumber(parts[5]) ~= 0 and tonumber(parts[5]) or nil,
              level = tonumber(parts[6]), knownText = known, known = parseKnown(known), at = A.Now(), sender = sender }
  peers[guid] = p
  local changed = not was or was.role ~= p.role or was.spec ~= p.spec or was.knownText ~= p.knownText or was.level ~= p.level
  -- (one heard for the first time hears yours back, once: a few seconds on, so a new group's hellos don't cross)
  if not was then
    Cm.HelloSoon(1 + (#guid % 7) * 0.3, true)
    if A.Assign then A.Assign.Resend() end -- (and the blessings you set by hand, with their stamps)
  end
  if changed then
    A.Roster.Changed()
    if A.Assign then A.Assign.Changed() end
  end
end
local function onOverride(parts, sender)
  local from, pal, bucket, key, stamp = parts[2], parts[3], parts[4], parts[5], tonumber(parts[6]) or 0
  if not (from and pal and bucket and key) or from == A.MyGUID() then return end
  local m = A.Roster.ByGUID(from)
  if not m then return end
  -- (the sender's name must be that member's: a message names its sender's GUID, the server names the sender)
  local short = type(sender) == "string" and (sender:match("^([^%-]+)") or sender) or nil
  if short and m.name ~= "?" and short ~= m.name then return end
  if A.Assign then A.Assign.SetOverride(pal, bucket, key ~= "-" and key or nil, stamp, from) end
end
local function onMessage(_, prefix, text, _, sender)
  prefix, text, sender = plain(prefix), plain(text), plain(sender)
  if prefix ~= PREFIX or type(text) ~= "string" then return end
  Cm.heard = Cm.heard + 1
  local parts = {}
  for p in (text .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = p end
  local kind = parts[1]
  if kind == "H1" then onHello(parts, sender)
  elseif kind == "O1" then onOverride(parts, sender)
  elseif kind == "Q1" then
    Cm.HelloSoon(1 + math.random() * 2, true)
    if A.Assign then A.Assign.Resend() end
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
    peers[guid] = { ver = p.ver, role = p.role, spec = p.spec, level = p.level, known = p.knownText }
  end
  -- (who was in the group: what is read back must be the same group, not a next one sharing a paladin)
  local members = {}
  for _, m in ipairs(A.Roster.members) do if m.guid and not m.me then members[#members + 1] = m.guid end end
  c.group = { at = serverNow(), peers = peers, overrides = A.Assign and A.Assign.Mine() or nil, members = members }
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
                         known = parseKnown(known), at = A.Now(), restored = true }
      any = true
    end
  end
  -- (the roles the peers announced, before the share-out is computed)
  if any then A.Roster.Scan() end
  if A.Assign then A.Assign.Restore(saved.overrides) end
end

-- members no longer in the group are forgotten
function Cm.Prune()
  for guid in pairs(Cm.peers) do if not A.Roster.ByGUID(guid) then Cm.peers[guid] = nil end end
end
-- the members running Cute Auras now (you too): { [guid] = peer }
function Cm.Running(guid) return guid == A.MyGUID() or Cm.peers[guid] ~= nil end

function Cm:Init()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
  A.On("CHAT_MSG_ADDON", onMessage)
  local inGroup = A.Roster.InGroup()
  A.On("GROUP_ROSTER_UPDATE", function()
    local now = A.Roster.InGroup()
    -- (in a group at last: a login the group was not known at yet reads back what was saved)
    if now and not inGroup then Cm.Restore(); Cm.Send("Q1"); Cm.HelloSoon(1, true)
    elseif now then Cm.HelloSoon(2) end
    if not now then for k in pairs(Cm.peers) do Cm.peers[k] = nil end; lastHello = nil end
    -- (you left: the blessings set by hand there are let go, and nothing is kept for a next login)
    if not now and inGroup then
      A.Char().group = nil
      if A.Assign then A.Assign.Forget() end
    end
    inGroup = now
    A.After(1, Cm.Prune, "comm: prune")
  end)
  A.On("PLAYER_LOGOUT", Cm.Save)
  -- (into or out of a dungeon or raid: the bar's Nothing there may change what you give)
  A.On("PLAYER_ENTERING_WORLD", function() if A.Roster.InGroup() then Cm.GivesChanged() end end)
  for _, ev in ipairs({ "SPELLS_CHANGED", "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "PLAYER_ROLES_ASSIGNED",
                        "ACTIVE_TALENT_GROUP_CHANGED", "ACTIVE_COMBAT_CONFIG_CHANGED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" }) do
    A.On(ev, function() if A.Roster.InGroup() then Cm.HelloSoon(4) end end)
  end
  -- (a chat restriction lifted: what waits goes)
  A.On("ADDON_RESTRICTION_STATE_CHANGED", function() if #queue > 0 then later(0.5) end end)
  if inGroup then Cm.Restore(); Cm.Send("Q1"); Cm.HelloSoon(3, true) end
end
