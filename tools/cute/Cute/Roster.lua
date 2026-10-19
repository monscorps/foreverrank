-- SPDX-License-Identifier: GPL-3.0-or-later
-- The roster: the guild as the game lists it (names, ranks, levels, who is online) joined with what each member's
-- Cute addon has told us (CuteDB.roster, kept across sessions so offline members show their last known values).
-- The guild is read through C_Club, the documented roster on this client, which lists every member whether or not
-- the guild window shows offline ones. (Forever's own UI code never calls GetGuildRosterInfo, so there is no fallback.)
-- No name is a key here (Core.lua says why). A member is its GUID, else its club member id; an addon record is kept
-- under the sender string the channel gave and joined to its member by the GUID its full record carries, by name
-- (C.Canon) only where no GUID has come yet. You are the member marked isSelf (or carrying your GUID): exactly one
-- row, named as the roster names you. The game hands a guild addon message back to its sender too, so a record that
-- turns out to be yours is dropped and its sender remembered as you (R:FromMe: the GUID decides wherever a message or
-- a record carries one; a sender your GUID came under, then your names, only where none does).
local _, C = ...
local R = { members = {}, byGuid = {}, byCanon = {}, trusted = false, misses = {}, updatedAt = nil, empties = 0,
  version = 0, selfSenders = {} }
C.Roster = R

-- records kept at most (a guild holds a thousand), and how long a record lives unseen
local CAP, UNSEEN = 1000, 90 * 86400

local function now() return C.Now() end

-- something about the guild or a record changed: the rows are built again when next asked
function R:Changed() self.version = self.version + 1; self.mine = nil end

-- Enum.ClubMemberPresence: Online 1, OnlineMobile 2, Away 4 and Busy 5 are online; Unknown 0 and Offline 3 are not
local function onlinePresences()
  local e = Enum and Enum.ClubMemberPresence
  if type(e) == "table" and e.Online then return { [e.Online] = true, [e.OnlineMobile] = true, [e.Away] = true, [e.Busy] = true } end
  return { [1] = true, [2] = true, [4] = true, [5] = true }
end

-- the guild through C_Club; nil until the clubs have loaded (INITIAL_CLUBS_LOADED) or when the client lacks it. A
-- member's name is kept as the client gives it (a Kstring draws itself) and never used as a key
local function viaClub()
  local clubId = C.Get(C.Api("C_Club", "GetGuildClubId"))
  if clubId == nil then return nil end
  local members = C.Get(C.Api("C_Club", "GetClubMembers"), clubId)
  if type(members) ~= "table" then return nil end
  local getInfo, classInfo = C.Api("C_Club", "GetMemberInfo"), C.Api("C_CreatureInfo", "GetClassInfo")
  local online = onlinePresences()
  local myGuid = C.MyGUID()
  local list = {}
  for _, mid in ipairs(members) do
    mid = C.Plain(mid)
    local m = mid ~= nil and C.Get(getInfo, clubId, mid) or nil
    if type(m) == "table" then
      local name, guid = C.Plain(m.name), C.Plain(m.guid)
      name = (type(name) == "string" and name ~= "") and name or nil
      guid = (type(guid) == "string" and guid ~= "") and guid or nil
      local isSelf = C.Plain(m.isSelf) == true or (guid ~= nil and guid == myGuid)
      if name or isSelf then
        local order, classID = C.Plain(m.guildRankOrder), C.Plain(m.classID)
        local class
        if type(classID) == "number" then local ci = C.Get(classInfo, classID); class = type(ci) == "table" and C.Plain(ci.classFile) or nil end
        local level, zone, rankName = C.Plain(m.level), C.Plain(m.zone), C.Plain(m.guildRank)
        list[#list + 1] = { key = guid and ("g:" .. guid) or ("m:" .. tostring(mid)), name = name, guid = guid, id = mid, self = isSelf,
          canon = C.Canon(name), rankName = type(rankName) == "string" and rankName or "", rank = type(order) == "number" and order - 1 or 99,
          level = type(level) == "number" and level or nil, zone = type(zone) == "string" and zone or nil,
          online = online[C.Plain(m.presence)] == true, class = type(class) == "string" and class or nil }
      end
    end
  end
  return list, true
end

-- the guild roster as the client has it right now
function R:Refresh()
  if not self:InGuild() then
    -- out of a guild the hello is owed again, said on the next refresh in one (Comm.lua)
    if C.Comm then C.Comm.hello = false end
    if #self.members > 0 then
      self.members, self.byGuid, self.byCanon, self.self, self.trusted = {}, {}, {}, nil, false
      self.updatedAt = now()
      self:Changed()
      if C.UI and C.UI.Refresh then C.UI:Refresh() end
    end
    return
  end
  -- in a guild: a hello not said yet (you joined one since login) goes now, before any change of yours does
  if C.Comm and C.Comm.Hello then C.Comm:Hello() end
  local list, complete = viaClub()
  if not list or #list == 0 then
    -- in a guild with nothing listed: the clubs may still be loading, so keep what we had and say so if it lasts
    self.empties = self.empties + 1
    if self.empties == 3 then C.Err.Note("guild roster: C_Club listed no member", "roster") end
    return
  end
  self.empties = 0
  local members, byGuid, byCanon, seen, sig, me = {}, {}, {}, {}, {}, nil
  for _, m in ipairs(list) do
    if not seen[m.key] then
      seen[m.key] = true
      members[#members + 1] = m
      if m.guid then byGuid[m.guid] = m end
      -- two members of one name: neither is found by name (false), only by GUID
      if m.canon then byCanon[m.canon] = byCanon[m.canon] == nil and m or false end
      if m.self then me = m end
      sig[#sig + 1] = m.key .. (m.online and "+" or "-") .. m.rank .. ":" .. tostring(m.level)
    end
  end
  table.sort(sig)
  local signature = table.concat(sig, "|")
  local changed = signature ~= self.signature
  self.members, self.byGuid, self.byCanon, self.self, self.signature = members, byGuid, byCanon, me, signature
  self.trusted = true
  self:Changed()
  if complete then
    -- your own records go now; another's when its member is gone twice in a row, or unseen 90 days (only against a
    -- complete list)
    local db = CuteDB.roster
    for key, e in pairs(db) do
      if self:IsSelfRecord(key, e) then db[key] = nil; self.misses[key] = nil; changed = true
      elseif not self:MemberOf(key) then
        self.misses[key] = (self.misses[key] or 0) + 1
        if self.misses[key] >= 2 then db[key] = nil; self.misses[key] = nil; changed = true end
      else self.misses[key] = nil end
      if db[key] and e.seen and now() - e.seen > UNSEEN then db[key] = nil; changed = true end
    end
    -- the cap: the longest unseen go first
    local count = 0
    for _ in pairs(db) do count = count + 1 end
    while count > CAP do
      local oldest, oldestAt
      for name, e in pairs(db) do if not oldestAt or (e.seen or 0) < oldestAt then oldest, oldestAt = name, e.seen or 0 end end
      db[oldest] = nil
      count = count - 1
      changed = true
    end
  end
  -- a policy that arrived before the ranks were known is judged now
  if C.Policy and C.Policy.Replay then C.Policy:Replay() end
  if changed then
    self.updatedAt = now()
    if C.UI and C.UI.Refresh then C.UI:Refresh() end
  end
end

-- a refresh soon, for the club events that come once per member
function R:Soon()
  if self.soon then return end
  self.soon = true
  C_Timer.After(2, C.Safe(function() R.soon = false; R:Refresh() end, "roster: soon"))
end

local function askRoster() if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end end

local NOW = { GUILD_ROSTER_UPDATE = true, PLAYER_GUILD_UPDATE = true, INITIAL_CLUBS_LOADED = true, CLUB_MEMBERS_UPDATED = true }
local SOON = { CLUB_MEMBER_UPDATED = true, CLUB_MEMBER_PRESENCE_UPDATED = true, CLUB_MEMBER_ADDED = true, CLUB_MEMBER_REMOVED = true }

function R:Start()
  if self.frame then askRoster(); self:Refresh(); return end
  local f = CreateFrame("Frame")
  self.frame = f
  f:SetScript("OnEvent", C.Safe(function(_, event)
    if NOW[event] then R:Refresh() elseif SOON[event] then R:Soon() end
  end, "roster: events"))
  for event in pairs(NOW) do pcall(f.RegisterEvent, f, event) end
  for event in pairs(SOON) do pcall(f.RegisterEvent, f, event) end
  askRoster()
  self:Refresh()
  -- the game answers a roster request about every ten seconds at most; ask again now and then for ranks and online state
  local function again() C_Timer.After(60, C.Safe(again, "roster: again")); askRoster(); R:Refresh() end
  C_Timer.After(60, C.Safe(again, "roster: again"))
end

function R:InGuild() return C.Get(IsInGuild) == true end

----------------------------------------------------------------------------
-- who is who
----------------------------------------------------------------------------
-- your names as loose keys: the saved-data key, the first name and surname joined, the roster's name for you
local function mine(self)
  if self.mine then return self.mine end
  local set = {}
  local function add(s) local k = C.Canon(s); if k then set[k] = true end end
  add((C.Me()))
  local _, _, full = C.MyName()
  add(full)
  if self.self then add(self.self.name) end
  self.mine = set
  return set
end
-- a name that is you, or an event's GUID that is yours (the GUID decides where there is one)
function R:IsMe(name, guid)
  guid = C.Plain(guid)
  if type(guid) == "string" and guid ~= "" then local g = C.MyGUID(); if g then return guid == g end end
  local k = C.Canon(name)
  return k ~= nil and mine(self)[k] == true
end
-- the GUID an addon record carries, where its full record has come
local function recordGuid(e)
  local g = type(e) == "table" and type(e.stats) == "table" and e.stats.guid or nil
  return (type(g) == "string" and g ~= "") and g or nil
end
-- whether what came under a sender string is yours, and on what ("guid" or "name"). The GUID decides wherever there
-- is one: the message's (a full record, an ask), else the record kept under that sender. Only without one does a
-- sender string your GUID came under count as you, then your names (C.Canon): a namesake's record, which carries its
-- own GUID, is never taken for yours by its name
function R:FromMe(sender, guid)
  if type(sender) ~= "string" then return false end
  local mine = C.MyGUID()
  if type(guid) == "string" and guid ~= "" and mine then return guid == mine, "guid" end
  local how = self.selfSenders[sender]
  if how == "guid" then return true, "guid" end
  local g = recordGuid(CuteDB.roster[sender])
  if g and mine then return g == mine, "guid" end
  return how ~= nil or self:IsMe(sender), "name"
end
function R:IsSelfRecord(key, e) return (self:FromMe(key, recordGuid(e))) end
-- a sender is you: remembered for the session ("guid" when your GUID came under it, else "name"), and its record
-- dropped unless that record carries another's GUID (0.3.0 kept your own messages, handed back by the game under the
-- channel's name for you, as another member: the third row of you, its cells "?")
function R:SelfSender(sender, how)
  if type(sender) ~= "string" then return end
  if self.selfSenders[sender] ~= "guid" then self.selfSenders[sender] = how == "guid" and "guid" or "name" end
  -- (a sender with no record of its own changes no row: the window draws again only when one goes)
  local e = CuteDB.roster[sender]
  if e ~= nil and self:IsSelfRecord(sender, e) then
    CuteDB.roster[sender] = nil
    self.misses[sender] = nil
    self:Changed()
    if C.UI and C.UI.Refresh then C.UI:Refresh() end
  end
end
-- a sender whose message carried another's GUID: a name match that took it for you is forgotten
function R:NotMe(sender)
  if type(sender) == "string" and self.selfSenders[sender] == "name" then self.selfSenders[sender] = nil; self:Changed() end
end

-- the guild member an addon record (or a sender) belongs to: by the GUID its record carries, else by name. A record
-- with a GUID no member has is matched by name only to a member the roster gives no GUID
function R:MemberOf(key)
  local g = recordGuid(CuteDB.roster[key])
  if g and self.byGuid[g] then return self.byGuid[g] end
  local k = C.Canon(key)
  local m = (k and self.byCanon[k]) or nil
  if m and g and m.guid then return nil end
  return m
end

-- a member's rank index (0 is the guild master); nil until the roster is known or when the name is not in the guild
function R:Rank(name) local m = self:MemberOf(name); return m and m.rank or nil end
function R:MyRank() return self.self and self.self.rank or nil end
function R:IsOfficer(name)
  local rank = self:Rank(name)
  if rank == nil then return false end
  return rank <= C.Policy:Threshold()
end
function R:MeOfficer()
  local rank = self:MyRank()
  return rank ~= nil and rank <= C.Policy:Threshold()
end
-- a sender or a saved key as a name to show: yours, its member's, or the key with your realm cut. (Whether it is you
-- goes through FromMe, as everywhere: no sender string is compared with a name of yours)
function R:Display(key)
  if key == nil then return "?" end
  if self:FromMe(key) then return self:MyDisplay() end
  local m = self:MemberOf(key)
  if m and m.name then return C.Short(m.name) end
  return C.Short(key)
end
function R:MyDisplay()
  if self.self and self.self.name then return C.Short(self.self.name) end
  local _, _, full = C.MyName()
  return full or C.Short((C.Me()))
end

-- a member's record from their addon, made on first contact
function R:Entry(name, create)
  local e = CuteDB.roster[name]
  if not e and create then
    e = { seen = now(), online = true, stats = {}, at = {} }
    CuteDB.roster[name] = e
  end
  return e
end

-- values that arrived from a member's addon. What FromMe takes for yours is your own message come back; a record
-- carrying another's GUID is theirs whatever the sender string
local MAX_GAME = 1000 -- statistics kept per member from the wire (the probe caps its own at the same)
function R:Apply(name, kv)
  local me, how = self:FromMe(name, kv.guid)
  if me then self:SelfSender(name, how); return end
  if type(kv.guid) == "string" then self:NotMe(name) end
  local db = CuteDB.roster
  local created = db[name] == nil
  local e = self:Entry(name, true)
  local t = now()
  -- one record per GUID: the same character under another sender string (a rename, or a client that names senders
  -- differently) is folded into this one
  if type(kv.guid) == "string" then
    for k, other in pairs(db) do
      if k ~= name and type(other.stats) == "table" and other.stats.guid == kv.guid then
        for id, v in pairs(other.stats) do if e.stats[id] == nil then e.stats[id] = v; e.at[id] = other.at and other.at[id] end end
        db[k] = nil
        self.misses[k] = nil
      end
    end
  end
  local games
  for id, v in pairs(kv) do
    local keep = true
    if e.stats[id] == nil and id:match("^g%d+$") then
      if not games then games = 0; for k in pairs(e.stats) do if k:match("^g%d+$") then games = games + 1 end end end
      if games >= MAX_GAME then keep = false else games = games + 1 end
    end
    if keep then e.stats[id] = v; e.at[id] = t end
  end
  e.seen, e.online = t, true
  self.updatedAt = t
  self:Changed()
  -- the window draws again only for a new member or a value it shows (UI.lua)
  if C.UI and C.UI.Arrived then C.UI:Arrived(kv, created) end
end

-- your own class file name, for the colour when the roster has not listed you yet
local function myClass()
  local _, file = C.Get(UnitClass, "player")
  return type(file) == "string" and file or nil
end

----------------------------------------------------------------------------
-- the rows
----------------------------------------------------------------------------
-- every row the dashboard shows: guild members (with or without the addon) plus addon records of people the roster
-- hasn't listed. You first (one row, the roster's name for you), then online members, then the rest; ties by name.
-- Built once per change of the guild or a record (R.version), not per draw; the stats tables are the live ones
local function sortKey(name)
  local k = C.Canon(name)
  if k then return k end
  return "~" .. tostring(name) -- (a Kstring: after the plain names, in the client's order)
end
function R:Rows()
  if self.rows and self.rowsAt == self.version then return self.rows end
  local db = CuteDB.roster
  local rows, claimed = {}, {}
  -- the records by the GUID they carry, and by name the ones no GUID has come with; yours left out
  local byGuid, byName = {}, {}
  for key, e in pairs(db) do
    if self:IsSelfRecord(key, e) then claimed[key] = true
    else
      local g = recordGuid(e)
      if g then byGuid[g] = key
      else
        local k = C.Canon(key)
        if k then byName[k] = byName[k] == nil and key or false end
      end
    end
  end
  local function add(row)
    row.short = C.Short(row.name)
    row.sort = sortKey(row.name)
    rows[#rows + 1] = row
  end
  local me
  for _, m in ipairs(self.members) do
    if m.self then
      me = m
    else
      local key = (m.guid and byGuid[m.guid]) or (m.canon and byName[m.canon]) or nil
      if key and claimed[key] then key = nil end
      if key then claimed[key] = true end
      local e = key and db[key] or nil
      add({ key = key or m.key, name = m.name or "?", guild = m, entry = e, addon = e ~= nil, online = m.online, rank = m.rank,
        class = m.class, level = (e and e.stats.level) or m.level, zone = m.zone, seen = e and e.seen,
        stats = e and e.stats or {}, at = e and e.at or {} })
    end
  end
  -- records no member claimed: people the roster has not listed (yet)
  for key, e in pairs(db) do
    local g = recordGuid(e)
    if not claimed[key] and not (g and self.byGuid[g]) then
      add({ key = key, name = key, entry = e, addon = true, online = false, rank = 99, class = e.class,
        level = e.stats.level, seen = e.seen, stats = e.stats, at = e.at })
    end
  end
  -- you: the roster's member for you, else the names the client gives
  local myName = (me and me.name) or select(3, C.MyName()) or C.Me()
  if myName then
    add({ key = me and me.key or "me", name = myName, me = true, guild = me, addon = true, online = true, rank = me and me.rank or 99,
      class = (me and me.class) or myClass(), level = C.Sample.values.level or (me and me.level), zone = me and me.zone,
      stats = C.Sample.values, at = C.Sample.at })
  end
  table.sort(rows, function(a, b)
    if (a.me or false) ~= (b.me or false) then return a.me == true end
    if a.online ~= b.online then return a.online end
    if a.addon ~= b.addon then return a.addon end
    return a.sort < b.sort
  end)
  self.rows, self.rowsAt = rows, self.version
  return rows
end
function R:MeRow() local rows = self:Rows(); return (rows[1] and rows[1].me) and rows[1] or nil end

-- for /cute diag
function R:MyRowCount() local n = 0; for _, r in ipairs(self:Rows()) do if r.me then n = n + 1 end end return n end
function R:RecordCount() local n = 0; for _ in pairs(CuteDB and CuteDB.roster or {}) do n = n + 1 end return n end
function R:SelfSenderCount() local n = 0; for _ in pairs(self.selfSenders) do n = n + 1 end return n end
