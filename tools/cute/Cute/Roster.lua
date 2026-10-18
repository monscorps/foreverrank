-- SPDX-License-Identifier: GPL-3.0-or-later
-- The roster: the guild as the game lists it (names, ranks, levels, who is online) joined with what each member's
-- Cute addon has told us (CuteDB.roster, kept across sessions so offline members show their last known values).
local _, C = ...
local R = { guild = {}, order = {}, ranks = {}, trusted = false, misses = {} }
C.Roster = R

local CAP, UNSEEN = 200, 90 * 86400

local function now() return C.Now() end

-- the guild roster as the client has it right now
function R:Refresh()
  local n = C.Num(GetNumGuildMembers)
  if not n or n == 0 then return end
  local guild, order, ranks = {}, {}, {}
  for i = 1, n do
    local name, rankName, rankIndex, level, _, zone, _, _, online, _, class = C.Get(GetGuildRosterInfo, i)
    local r = { C.Get(GetGuildRosterInfo, i) }
    name, rankName, rankIndex, level, zone, online, class = r[1], r[2], r[3], r[4], r[6], r[9], r[11]
    if type(name) == "string" and name ~= "" then
      if not name:find("-", 1, true) then
        local realm = C.Get(GetNormalizedRealmName)
        if type(realm) == "string" and realm ~= "" then name = name .. "-" .. realm end
      end
      guild[name] = { rank = type(rankIndex) == "number" and rankIndex or 99, rankName = type(rankName) == "string" and rankName or "",
        level = type(level) == "number" and level or nil, zone = type(zone) == "string" and zone or nil,
        online = online == true, class = type(class) == "string" and class or nil }
      order[#order + 1] = name
      ranks[name] = guild[name].rank
    end
  end
  self.guild, self.order, self.ranks = guild, order, ranks
  self.trusted = true
  -- prune: a name gone from the guild twice in a row, or unseen 90 days
  local db = CuteDB.roster
  for name, e in pairs(db) do
    if not guild[name] then
      self.misses[name] = (self.misses[name] or 0) + 1
      if self.misses[name] >= 2 then db[name] = nil; self.misses[name] = nil end
    else self.misses[name] = nil end
    if e.seen and now() - e.seen > UNSEEN then db[name] = nil end
  end
  -- the cap: the longest unseen go first
  local count = 0
  for _ in pairs(db) do count = count + 1 end
  while count > CAP do
    local oldest, oldestAt
    for name, e in pairs(db) do if not oldestAt or (e.seen or 0) < oldestAt then oldest, oldestAt = name, e.seen or 0 end end
    db[oldest] = nil
    count = count - 1
  end
  if C.UI and C.UI.Refresh then C.UI:Refresh() end
end

function R:Start()
  if self.frame then
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
    return
  end
  local f = CreateFrame("Frame")
  self.frame = f
  f:SetScript("OnEvent", C.Safe(function(_, event)
    if event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then R:Refresh() end
  end, "roster: events"))
  f:RegisterEvent("GUILD_ROSTER_UPDATE")
  f:RegisterEvent("PLAYER_GUILD_UPDATE")
  if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
  -- the game answers a roster request about every ten seconds at most; ask again now and then for ranks and online state
  local function again() C_Timer.After(60, again); if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end end
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
function R:Apply(name, kv)
  local e = self:Entry(name, true)
  local t = now()
  for id, v in pairs(kv) do e.stats[id] = v; e.at[id] = t end
  e.seen, e.online = t, true
  if C.UI and C.UI.Refresh then C.UI:Refresh() end
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
      level = (e and e.stats.level) or (g and g.level), seen = e and e.seen }
    if row.me then
      row.addon, row.online = true, true
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
