-- SPDX-License-Identifier: GPL-3.0-or-later
-- The roster: the guild as the game lists it (names, ranks, levels, who is online) joined with what each member's
-- Cute addon has told us (CuteDB.roster, kept across sessions so offline members show their last known values).
-- The guild is read through C_Club, the documented roster on this client, which lists every member whether or not
-- the guild window shows offline ones. (Forever's own UI code never calls GetGuildRosterInfo, so there is no fallback.)
local _, C = ...
local R = { guild = {}, order = {}, ranks = {}, trusted = false, misses = {}, updatedAt = nil, empties = 0 }
C.Roster = R

local CAP, UNSEEN = 200, 90 * 86400

local function now() return C.Now() end

-- "Name" to "Name-Realm", as the addon channel names people
local function qualify(name)
  if name:find("-", 1, true) then return name end
  local realm = C.Get(GetNormalizedRealmName)
  if type(realm) == "string" and realm ~= "" then return name .. "-" .. realm end
  return name
end

-- Enum.ClubMemberPresence: Online 1, OnlineMobile 2, Away 4 and Busy 5 are online; Unknown 0 and Offline 3 are not
local function onlinePresences()
  local e = Enum and Enum.ClubMemberPresence
  if type(e) == "table" and e.Online then return { [e.Online] = true, [e.OnlineMobile] = true, [e.Away] = true, [e.Busy] = true } end
  return { [1] = true, [2] = true, [4] = true, [5] = true }
end

-- the guild through C_Club; nil until the clubs have loaded (INITIAL_CLUBS_LOADED) or when the client lacks it
local function viaClub()
  local clubId = C.Get(C.Api("C_Club", "GetGuildClubId"))
  if clubId == nil then return nil end
  local members = C.Get(C.Api("C_Club", "GetClubMembers"), clubId)
  if type(members) ~= "table" then return nil end
  local getInfo, classInfo = C.Api("C_Club", "GetMemberInfo"), C.Api("C_CreatureInfo", "GetClassInfo")
  local online = onlinePresences()
  local list = {}
  for _, mid in ipairs(members) do
    local m = C.Get(getInfo, clubId, mid)
    local name = type(m) == "table" and C.Plain(m.name) or nil
    if type(name) == "string" and name ~= "" then
      local order, classID = C.Plain(m.guildRankOrder), C.Plain(m.classID)
      local class
      if type(classID) == "number" then local ci = C.Get(classInfo, classID); class = type(ci) == "table" and C.Plain(ci.classFile) or nil end
      list[#list + 1] = { name = qualify(name), rankName = C.Plain(m.guildRank), rank = type(order) == "number" and order - 1 or nil,
        level = C.Plain(m.level), zone = C.Plain(m.zone), online = online[C.Plain(m.presence)] == true, class = class }
    end
  end
  return list, true
end

-- the guild roster as the client has it right now
function R:Refresh()
  if not self:InGuild() then
    if next(self.guild) then
      self.guild, self.order, self.ranks, self.trusted = {}, {}, {}, false
      self.updatedAt = now()
      if C.UI and C.UI.Refresh then C.UI:Refresh() end
    end
    return
  end
  local list, complete = viaClub()
  if not list or #list == 0 then
    -- in a guild with nothing listed: the clubs may still be loading, so keep what we had and say so if it lasts
    self.empties = self.empties + 1
    if self.empties == 3 then C.Err.Note("guild roster: C_Club listed no member", "roster") end
    return
  end
  self.empties = 0
  local guild, order, ranks, sig = {}, {}, {}, {}
  for _, m in ipairs(list) do
    if not guild[m.name] then
      guild[m.name] = { rank = type(m.rank) == "number" and m.rank or 99, rankName = type(m.rankName) == "string" and m.rankName or "",
        level = type(m.level) == "number" and m.level or nil, zone = type(m.zone) == "string" and m.zone or nil,
        online = m.online == true, class = type(m.class) == "string" and m.class or nil }
      order[#order + 1] = m.name
      ranks[m.name] = guild[m.name].rank
      sig[#sig + 1] = m.name .. (m.online and "+" or "-") .. guild[m.name].rank .. ":" .. tostring(guild[m.name].level)
    end
  end
  table.sort(sig)
  local signature = table.concat(sig, "|")
  local changed = signature ~= self.signature
  self.guild, self.order, self.ranks, self.signature = guild, order, ranks, signature
  self.trusted = true
  if complete then
    -- prune: a name gone from the guild twice in a row, or unseen 90 days (only against a complete list)
    local db = CuteDB.roster
    for name, e in pairs(db) do
      if not guild[name] then
        self.misses[name] = (self.misses[name] or 0) + 1
        if self.misses[name] >= 2 then db[name] = nil; self.misses[name] = nil; changed = true end
      else self.misses[name] = nil end
      if e.seen and now() - e.seen > UNSEEN then db[name] = nil; changed = true end
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

-- a member's rank index (0 is the guild master); nil until the roster is known or when the name is not in the guild
function R:Rank(name) return self.ranks[name] end
function R:IsOfficer(name)
  local rank = self.ranks[name]
  if rank == nil then return false end
  return rank <= C.Policy:Threshold()
end
function R:MeOfficer() return self:IsOfficer((C.Me())) end

-- a member's record from their addon, made on first contact
function R:Entry(name, create)
  local e = CuteDB.roster[name]
  if not e and create then
    e = { seen = now(), online = true, stats = {}, at = {} }
    CuteDB.roster[name] = e
  end
  return e
end

-- values that arrived from a member's addon
local MAX_GAME = 1000 -- statistics kept per member from the wire (the probe caps its own at the same)
function R:Apply(name, kv)
  local e = self:Entry(name, true)
  local t = now()
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
  if C.UI and C.UI.Refresh then C.UI:Refresh() end
end

-- your own class file name, for the colour when the roster has not listed you yet
local function myClass()
  local _, file = C.Get(UnitClass, "player")
  return type(file) == "string" and file or nil
end

-- every row the dashboard shows: guild members (with or without the addon) plus addon records of people the roster
-- hasn't listed yet. You first, then online members, then the rest; ties by name
function R:Rows()
  local me = C.Me()
  local rows, seen = {}, {}
  local function add(name)
    if seen[name] then return end
    seen[name] = true
    local g, e = self.guild[name], CuteDB.roster[name]
    local online = (g and g.online) or false
    local row = { name = name, short = C.Short(name), me = name == me, guild = g, entry = e, addon = e ~= nil,
      online = online, rank = g and g.rank or (e and e.rank) or 99, class = g and g.class or (e and e.class),
      level = (e and e.stats.level) or (g and g.level), zone = g and g.zone, seen = e and e.seen }
    if row.me then
      row.addon, row.online = true, true
      row.class = row.class or myClass()
      row.stats = C.Sample.values
      row.at = C.Sample.at
    else
      row.stats = e and e.stats or {}
      row.at = e and e.at or {}
    end
    rows[#rows + 1] = row
  end
  if me then add(me) end
  for _, name in ipairs(self.order) do add(name) end
  for name in pairs(CuteDB.roster) do add(name) end
  table.sort(rows, function(a, b)
    if a.me ~= b.me then return a.me end
    if a.online ~= b.online then return a.online end
    if a.addon ~= b.addon then return a.addon end
    return a.short < b.short
  end)
  return rows
end
