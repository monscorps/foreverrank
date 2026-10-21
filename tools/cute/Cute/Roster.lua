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
-- The server's facts win: a member's level, class, zone, rank and whether they are online come from the roster, not
-- from what their addon says, and a value their addon sends that cannot be (Stats.lua S.Implausible: a level the
-- roster contradicts, a count that went down, a number out of its bounds) is dropped and the record marked suspect
-- for the officers, with the reason.
-- Who sent a message is the server's word too, never the message's. The channel gives the sender string and C_Club the
-- members' names and GUIDs, and an edited copy of Cute chooses none of them; it can put any GUID in its messages, and
-- the roster gives every member the officers'. So a GUID a message claims is taken only where the roster bears it
-- out (R:Vouch, R:Vet): one the roster gives a member the sender string does not name is dropped and the sender marked
-- suspect. Whether a sender is an officer (the Only-you values whispered to it, its policy applied) goes by the member
-- the sender string names (R:SenderMember), never by a GUID; a record never moves to another sender string but under
-- the GUID of the member that string names; and a record keeps the one GUID it came with, so one copy is one voice.
-- The sender string and the roster's name need not be the same text, so they are matched loosely (R:SenderMember says
-- how): QuestBank found Forever's sender carrying a surname its name API does not give, and ClubMemberInfo.name may be
-- a Kstring, where the name GetPlayerInfoByGUID gives the member's GUID stands in. Which forms the live client gives is
-- not known yet; /cute diag's names line says, as shapes.
local _, C = ...
local R = { members = {}, byGuid = {}, byFirst = {}, trusted = false, misses = {}, charMisses = {}, updatedAt = nil, empties = 0,
  version = 0, idVersion = 0, levelVersion = 0, maxLevel = nil, selfSenders = {}, notSelf = {}, guidNames = {}, guidMisses = {}, dings = {},
  heard = {}, classFiles = {}, recVersion = 0 }
C.Roster = R

-- records kept at most (a guild holds a thousand), how long a record lives unseen, and how far apart two complete
-- lists that lack a record's member must be to delete it
local CAP, UNSEEN, MISS_APART, PRUNE_EVERY, LEFT_SURE = 1000, 90 * 86400, 60, 3600, 30

local function now() return C.Now() end

-- something about the guild or a record changed: the rows are built again when next asked. Who is who changed (the
-- roster's members, a record made, gone or folded, a GUID, a version, a record heard on the guild channel): what is
-- built from that alone (the GUIDs' records, the officers to whisper to) is built again too. A value that changed
-- leaves those alone, so a member whose gold changes every second rebuilds no list of officers
function R:Changed() self.version = self.version + 1; self.mine = nil end
-- (roster: the change is the roster's own, a member online or off, a level or a rank; anything else is a record's,
-- which the officers to whisper to are built again for, R:OfficerTargets)
function R:Identity(roster) self.idVersion = self.idVersion + 1; if not roster then self.recVersion = self.recVersion + 1 end; self:Changed() end

-- Enum.ClubMemberPresence: Online 1, OnlineMobile 2, Away 4 and Busy 5 are online; Unknown 0 and Offline 3 are not
local function onlinePresences()
  local e = Enum and Enum.ClubMemberPresence
  if type(e) == "table" and e.Online then return { [e.Online] = true, [e.OnlineMobile] = true, [e.Away] = true, [e.Busy] = true } end
  return { [1] = true, [2] = true, [4] = true, [5] = true }
end

-- a name's first and second words as loose keys (C.Canon: your realm cut, spaces and hyphens one, lower case); nil for
-- a Kstring, a secret or nothing
-- (kept per key, as C.Canon is: SenderMember asks it of every record's sender string at every roster change)
local wordsOf, wordsN = {}, 0
local function words(s)
  local k = C.Canon(s)
  if not k then return nil end
  local w = wordsOf[k]
  if w == nil then
    local a, b = k:match("^%s*(%S+)%s*(%S*)")
    w = a and { a, (b ~= "" and b or nil) } or false
    if wordsN >= 4096 then wordsOf, wordsN = {}, 0 end
    wordsOf[k], wordsN = w, wordsN + 1
  end
  if not w then return nil end
  return w[1], w[2]
end
-- the name GetPlayerInfoByGUID gives a member's GUID (PlayerScriptDocumentation.lua: its sixth return; it may return
-- nothing), for matching a member whose C_Club name is a Kstring or missing; never shown, never a key. Kept per GUID
-- once it reads; a GUID it gave nothing for is asked again a minute on at most
local function guidName(guid)
  local known = R.guidNames[guid]
  if known then return known end
  local t, miss = now(), R.guidMisses[guid]
  if miss and t - miss < 60 then return nil end
  local _, _, _, _, _, name = C.Get("GetPlayerInfoByGUID", guid)
  if type(name) == "string" and name ~= "" and not C.IsKstring(name) then
    R.guidNames[guid], R.guidMisses[guid] = name, nil
    return name
  end
  R.guidMisses[guid] = t
  return nil
end

-- the guild through C_Club; nil until the clubs have loaded (INITIAL_CLUBS_LOADED) or when the client lacks it. A
-- member's name is kept as the client gives it (a Kstring draws itself) and never used as a key; the name it is matched
-- by (match) is that name where it is plain, else the GUID's, else none (such a member is found by GUID alone).
-- complete: the list is the whole guild, which alone may say a record's member left. GetMemberInfo may return nothing
-- (ClubDocumentation.lua:625, Nilable; Blizzard_FrameXMLUtil/CommunitiesUtil.lua checks for it) while the club loads,
-- so a list is whole only where every member read and it holds as many as the club says it has (C_Club.GetClubInfo's
-- memberCount, NeverSecret: ClubDocumentation.lua:1771). 0.7.0 took every list for whole, and two reads at login a
-- second apart, a few members not read yet, deleted their saved records
local function viaClub()
  local clubId = C.Get(C.Api("C_Club", "GetGuildClubId"))
  if clubId == nil then return nil end
  local members = C.Get(C.Api("C_Club", "GetClubMembers"), clubId)
  if type(members) ~= "table" then return nil end
  local getInfo, classInfo = C.Api("C_Club", "GetMemberInfo"), C.Api("C_CreatureInfo", "GetClassInfo")
  local classes = R.classFiles
  local online = onlinePresences()
  local myGuid = C.MyGUID()
  local list, skipped = {}, 0
  for _, mid in ipairs(members) do
    mid = C.Plain(mid)
    local m = mid ~= nil and C.Get(getInfo, clubId, mid) or nil
    if type(m) ~= "table" then skipped = skipped + 1 end
    if type(m) == "table" then
      local name, guid = C.Plain(m.name), C.Plain(m.guid)
      name = (type(name) == "string" and name ~= "") and name or nil
      guid = (type(guid) == "string" and guid ~= "") and guid or nil
      local isSelf = C.Plain(m.isSelf) == true or (guid ~= nil and guid == myGuid)
      if name or isSelf then
        local order, classID = C.Plain(m.guildRankOrder), C.Plain(m.classID)
        -- (a class id's file asked once a session: 0.7.0 asked it of every member at every read)
        local class
        if type(classID) == "number" then
          class = classes[classID]
          if class == nil then local ci = C.Get(classInfo, classID); class = type(ci) == "table" and C.Plain(ci.classFile) or nil; if type(class) == "string" then classes[classID] = class end end
        end
        local level, zone, rankName = C.Plain(m.level), C.Plain(m.zone), C.Plain(m.guildRank)
        local match, from = nil, nil
        if name and not C.IsKstring(name) then match, from = name, "club"
        elseif guid then match = guidName(guid); from = match and "guid" or nil end
        local first, second = words(match)
        list[#list + 1] = { key = guid and ("g:" .. guid) or ("m:" .. tostring(mid)), name = name, guid = guid, id = mid, self = isSelf,
          match = match, from = from, first = first, second = second, canon = C.Canon(match),
          rankName = type(rankName) == "string" and rankName or "", rank = type(order) == "number" and order - 1 or 99,
          level = type(level) == "number" and level or nil, zone = type(zone) == "string" and zone or nil,
          online = online[C.Plain(m.presence)] == true, class = type(class) == "string" and class or nil }
      else skipped = skipped + 1 end
    end
  end
  local info = C.Get(C.Api("C_Club", "GetClubInfo"), clubId)
  local count = type(info) == "table" and C.Plain(info.memberCount) or nil
  R.listed, R.expected, R.skipped = #list, count, skipped
  return list, skipped == 0 and type(count) == "number" and #list >= count
end

-- the guild roster as the client has it right now. event: the game event that asked for it, where one did (Guild Info
-- is read on GUILD_ROSTER_UPDATE alone, as Blizzard_Communities/GuildInfo.lua reads it: on PLAYER_GUILD_UPDATE its
-- panel reads only its permissions, so Cute asks for the roster then, R:Start). One that comes while C_Club lists
-- nobody yet is read at the first refresh that lists the guild (R.infoDue)
local INFO = { GUILD_ROSTER_UPDATE = true }
-- each part of a refresh on its own: one that raises (a saved record left odd, say) leaves the rest to run, Guild
-- Info's read above all (0.7.0 ran the whole refresh as one, and a raise in the prune left the policy unread for the
-- session: nothing of yours ever went)
local function step(where, fn)
  local ok, err = pcall(fn)
  if not ok then
    if CUTE_DEV then error(err, 0) end
    C.Err.Record(tostring(err), "", where)
  end
end
function R:Refresh(event)
  if not self:InGuild() then
    -- out of a guild the hello is owed again, said on the next refresh in one (Comm.lua); its Guild Info is no more ours
    if C.Comm and C.Comm.Left then C.Comm:Left() end
    if C.Policy and C.Policy.line ~= nil then C.Policy:Left() end
    if #self.members > 0 then
      self.members, self.byGuid, self.byFirst, self.self, self.trusted = {}, {}, {}, nil, false
      self.updatedAt = now()
      self.leftAt = now()
      self:Changed()
      if C.UI and C.UI.Refresh then C.UI:Refresh() end
    elseif not self.leftAt then
      -- (a login out of any guild is judged the same way: an officer kicked while offline. A first build judged
      -- only one who stayed online half a minute after leaving)
      if not self.leftDone then self.leftAt = now() end
    elseif now() - self.leftAt >= LEFT_SURE then
      -- (out of the guild at two reads half a minute apart: left or kicked, not a blip; once)
      self.leftAt, self.leftDone = nil, true
      step("roster: left", function() self:LeftGuild() end)
    end
    return
  end
  self.leftAt, self.leftDone = nil, nil
  -- in a guild: this guild's policy (the saved variables are the account's, its characters perhaps in other guilds),
  -- then a hello not said yet (you joined one since login) goes now, before any change of yours does
  if C.Policy and C.Policy.ForClub then C.Policy:ForClub(self:ClubId()) end
  if C.Comm and C.Comm.Hello then C.Comm:Hello() end
  local list, complete = viaClub()
  if INFO[event] then self.infoDue = true end
  if not list or #list == 0 then
    -- in a guild with nothing listed: the clubs may still be loading, so keep what we had and say so if it lasts
    self.empties = self.empties + 1
    if self.empties == 3 then C.Err.Note("guild roster: C_Club listed no member", "roster") end
    return
  end
  self.empties = 0
  self.listedWhole = complete == true
  local members, byGuid, byFirst, seen, sig, names, me, top, unread = {}, {}, {}, {}, {}, {}, nil, nil, 0
  for _, m in ipairs(list) do
    if not seen[m.key] then
      seen[m.key] = true
      members[#members + 1] = m
      if m.guid then byGuid[m.guid] = m end
      -- the members by their first name, for R:SenderMember (namesakes side by side); a member online whose name reads
      -- in no form may be any of them (R:SenderMember)
      if m.first then local l = byFirst[m.first]; if not l then l = {}; byFirst[m.first] = l end; l[#l + 1] = m
      elseif m.online and not m.self then unread = unread + 1 end
      if m.self then me = m end
      if m.level and (not top or m.level > top) then top = m.level end
      -- (the name too: a rename, or a GUID's name read at last, changes who a sender string names)
      sig[#sig + 1] = m.key .. (m.online and "+" or "-") .. m.rank .. ":" .. tostring(m.level) .. ":" .. tostring(m.canon)
      names[#names + 1] = m.key .. ":" .. tostring(m.canon)
    end
  end
  table.sort(sig)
  local signature = table.concat(sig, "|")
  -- (who is named what, online or not: what a sender string names (R:SenderMember) with the unread names online, for
  -- R:OfficerTargets)
  table.sort(names)
  local nameSig = table.concat(names, "|")
  if nameSig ~= self.nameSig then self.nameSig, self.nameVersion = nameSig, (self.nameVersion or 0) + 1 end
  local changed = signature ~= self.signature or unread ~= (self.unread or 0)
  local first = not self.trusted
  self.members, self.byGuid, self.byFirst, self.self, self.signature, self.unread = members, byGuid, byFirst, me, signature, unread
  self.trusted = true
  -- (the highest level the roster lists, for the level cap: Rules.lua reads it here, not from every row)
  if top ~= self.maxLevel then self.maxLevel = top; self.levelVersion = self.levelVersion + 1 end
  -- (saved variables of 0.5.x, which say no guild: this guild's only where this roster lists one of their records,
  -- before anything here reads, learns from or prunes them: Policy.lua P:Adopt)
  local adopted = C.Policy and C.Policy.Adopt and C.Policy:Adopt(self:ClubId(), byGuid)
  if adopted then changed = true end
  if changed or first then self:Identity(not (first or adopted)) else self:Changed() end
  -- (the officers online, by rank, for R:OfficerTargets: built again only when one of them came, went or moved)
  local offs, thrMax = {}, 0
  if C.Policy then thrMax = math.max(C.Policy:Threshold(), C.Policy:LineThreshold()) end
  for _, m in ipairs(members) do if m.online and not m.self and m.rank <= thrMax then offs[#offs + 1] = m.key .. ":" .. m.rank .. ":" .. tostring(m.canon) end end
  table.sort(offs)
  self.offSig = table.concat(offs, "|")
  -- a ding the channel told before this roster had it (R:Apply) is judged now
  step("roster: dings", function() self:Dings() end)
  -- what came before the roster was known, or under an older roster, judged by this one (R:Sweep); then, the first
  -- time, the saved records teach the guild's knowledge (R:VoiceOf waits for the roster)
  step("roster: sweep", function() if (first or changed) and self:Sweep() then changed = true end end)
  if first then
    step("roster: learn", function()
      if C.Sample and C.Sample.loaded then C.Stats.LearnSaved() end
      if C.Rules and C.Rules.started then C.Rules:LearnSaved(); C.Rules:Dirty(true) end
      if C.SavedVersions then C.SavedVersions() end
    end)
    step("roster: ask", function() if C.Comm and C.Comm.RosterTrusted then C.Comm:RosterTrusted() end end)
  end
  step("roster: prune", function()
    -- (the records against the list, where that can find something: the list's members not the last whole list's, a
    -- record made or changed since, a miss being counted, or an hour gone. 0.7.0 walked every record at every read)
    local keysSame = complete and self.keyN == #members and self.keySet ~= nil
    if keysSame then for key in pairs(seen) do if not self.keySet[key] then keysSame = false break end end end
    if complete then self.keySet, self.keyN = seen, #members end
    local pruneNow = complete and not (keysSame and self.prunedRec == self.recVersion and next(self.misses) == nil
      and self.prunedAt and now() - self.prunedAt < PRUNE_EVERY)
    if pruneNow then
      self.prunedAt = now()
      -- your own records go now; another's when its member is missing from two complete lists a minute apart at least
      -- (the reads at login come seconds apart), or unseen 90 days
      local db = CuteDB.roster
      local gone = false
      self.missAt = self.missAt or {}
      for key, e in pairs(db) do
        if self:IsSelfRecord(key, e) then db[key] = nil; self.misses[key] = nil; gone = true
        elseif not self:MemberOf(key) then
          if not self.missAt[key] or now() - self.missAt[key] >= MISS_APART then
            self.misses[key], self.missAt[key] = (self.misses[key] or 0) + 1, now()
          end
          if self.misses[key] >= 2 then db[key] = nil; self.misses[key], self.missAt[key] = nil, nil; gone = true end
        else self.misses[key], self.missAt[key] = nil, nil end
      end
      if gone then changed = true; self:Identity() end
    end
    if complete then
      -- (the account's characters this complete read does not list with a rank, counted once in half a minute, as the
      -- asks after a save read the roster again within seconds: R:AccountOfficer)
      self.charMissAt = self.charMissAt or {}
      for _, rec in pairs(type(CuteDB.chars) == "table" and CuteDB.chars or {}) do
        local g = type(rec) == "table" and type(rec.guid) == "string" and rec.guid or nil
        if g then
          local m = self.byGuid[g]
          if m and m.rank ~= 99 then self.charMisses[g], self.charMissAt[g] = nil, nil
          elseif not self.charMissAt[g] or now() - self.charMissAt[g] >= 30 then
            self.charMisses[g], self.charMissAt[g] = (self.charMisses[g] or 0) + 1, now()
          end
        end
      end
    end
    -- (age and cap, whatever the list: at the session's first read, hourly, and with every prune. A first build
    -- pruned them only at a whole list, and a client whose list never reads whole kept every record for good)
    if pruneNow or not self.expiredAt or now() - self.expiredAt >= PRUNE_EVERY then
      self.expiredAt = now()
      if self:Expire() then changed = true; self:Identity() end
    end
    if pruneNow then self.prunedRec = self.recVersion end
  end)
  -- Guild Info read where the event says it may have changed, and the policy it names applied, with the officers' word
  -- that came before the ranks were known (Policy.lua P:Refresh); then the whispers that came before the roster
  -- (Comm.lua), by the newest policy, so an officer whose threshold it raised keeps them
  local read = self.infoDue == true
  self.infoDue = nil
  step("roster: guild info", function() if C.Policy and C.Policy.Refresh then C.Policy:Refresh(read) end end)
  if first then step("roster: early", function() if C.Comm and C.Comm.ReplayEarly then C.Comm:ReplayEarly() end end) end
  step("roster: purge", function() if self:PurgeCheck() then changed = true end end)
  -- the officers this client tells its Only-you values: one no more is forgotten (told again when made one again), and
  -- one this refresh made an officer is told now (Comm.lua)
  step("roster: officers", function() if C.Comm and C.Comm.Officers then C.Comm:Officers() end end)
  if changed then
    self.updatedAt = now()
    if C.UI and C.UI.Refresh then C.UI:Refresh() end
  end
end

-- out of the guild for sure (left or kicked, at a login out of any guild too), or gone into another one (Policy.lua
-- P:ForClub, before its records are parked): its records stay, but the values its officers keep to themselves go, where
-- this character was one of its officers at its last word (CuteDB.chars[me].officerOf: an alt of another guild, or one
-- never an officer, held none of them) and no other character of this account is one (0.7.0 kept them: an officer who
-- left held every member's Only-you values for good). The number gone
function R:LeftGuild()
  local club, me = CuteDB.policyClub, C.Me()
  if club == nil then return 0 end
  local mine = type(CuteDB.chars) == "table" and CuteDB.chars[me] or nil
  if not (type(mine) == "table" and mine.officerOf ~= nil and mine.officerOf ~= false and tostring(mine.officerOf) == tostring(club)) then return 0 end
  for key, rec in pairs(type(CuteDB.chars) == "table" and CuteDB.chars or {}) do
    if key ~= me and type(rec) == "table" and rec.officerOf ~= nil and rec.officerOf ~= false and tostring(rec.officerOf) == tostring(club) then return 0 end
  end
  local n, routes = 0, {}
  for _, e in pairs(CuteDB.roster or {}) do
    if type(e) == "table" and type(e.stats) == "table" then
      for id in pairs(e.stats) do
        local r = routes[id]
        if r == nil then r = (type(id) == "string" and C.Policy:Route(id)) or "self"; routes[id] = r end
        if r == "self" then e.stats[id] = nil; if type(e.at) == "table" then e.at[id] = nil end; n = n + 1 end
      end
    end
  end
  if n > 0 then self:Changed() end
  return n
end

-- records unseen ninety days, and the longest unseen past the cap: whatever the list, which says nothing of them (a
-- client whose lists never read whole still keeps its file bounded: R:Refresh runs it hourly whatever the list says).
-- True when one went
function R:Expire()
  local db, t, gone, count = CuteDB.roster, now(), false, 0
  for key, e in pairs(db) do
    if type(e) ~= "table" or (e.seen and t - e.seen > UNSEEN) then db[key] = nil; gone = true else count = count + 1 end
  end
  if count <= CAP then return gone end
  local list = {}
  for key, e in pairs(db) do list[#list + 1] = { key = key, seen = tonumber(e.seen) or 0 } end
  table.sort(list, function(a, b) if a.seen ~= b.seen then return a.seen < b.seen end return a.key < b.key end)
  for i = 1, count - CAP do db[list[i].key] = nil end
  return true
end

R.Refresh = C.Perf.Timed("refresh", R.Refresh)

-- the first time the roster says whether you are an officer (once the saved labels and statistics are defined, so
-- each value's route is known: Sample.lua calls this then too), and whenever you stop being one: the saved records
-- keep none of the others' Only-you values (Policy.lua P:Purge). Made one during the session (a promotion, the
-- officers' threshold raised): a fresh ask, which every client answers an officer's with the Only-you part of its
-- record and the statistics kept to the officers, so what does not change reaches you too. This character's being an
-- officer is kept with it (CuteDB.chars), by the guild's club, so another character of the account knows whose the
-- saved variables are (R:AccountOfficer). True when it deleted something
function R:ClubId() local id = C.Get(C.Api("C_Club", "GetGuildClubId")); return (type(id) == "number" or type(id) == "string") and id or nil end
-- the roster lists you, with a rank that reads: only such a read says whether you are an officer (one that lacks you,
-- the clubs still loading, says nothing)
function R:SelfKnown() return self.self ~= nil and type(self.self.rank) == "number" and self.self.rank ~= 99 end
function R:PurgeCheck()
  if not (self.trusted and C.Sample and C.Sample.loaded and C.Policy and C.Policy.Purge) then return false end
  -- (and the first time only once this client holds the policy Guild Info names, or in a guild with no line, where this
  -- character was an officer, an officer's word as new as its own: a threshold the officers changed while you were away
  -- is not taken for theirs, and an officer's file is not purged by it)
  if not self:SelfKnown() then return false end
  if self.wasOfficer == nil and not C.Policy:Settled() then return false end
  if self.wasOfficer == nil and C.Policy:Unconfirmed() then
    -- (judged again once the wait is over: Policy.lua P.UNCONFIRMED after the hello)
    if not self.unconfirmedDue then
      self.unconfirmedDue = true
      C_Timer.After(C.Policy.UNCONFIRMED + 1, C.Safe(function() R.unconfirmedDue = false; R:PurgeCheck() end, "roster: purge, unconfirmed"))
    end
    return false
  end
  local officer = self:MeOfficer()
  -- (an officer whose client dropped a value, whatever the roster said of this character meanwhile: asked again at
  -- this read, an officer's ask always getting the whispered part, its senders counting it told. 0.6.0's first builds
  -- asked only as this character became an officer: one made no officer by a read that listed her without a rank, and
  -- one again by the next, asked for nothing)
  local lost = self.lostUnsettled
  local function ask() if C.Comm and C.Comm.Ask and C.Comm.hello then self.lostUnsettled = nil; C.Comm:Ask() end end
  -- (a member's first purge waits for a roster read that says whose the file is: an officer alt the read does not list,
  -- or lists without a rank, says nothing, R:AccountOfficer)
  if self.wasOfficer == nil and not officer and self:AccountOfficer() == nil then return false end
  local ch, club = C.Char(), self:ClubId()
  -- (an officer no more, this session or since this character's last login: every member's Ready its client holds may
  -- count a gap the officers closed while it was one, which no officer's client purges, so they all go, each member's
  -- next read saying it again)
  local wasOne = self.wasOfficer == true or (self.wasOfficer == nil and club ~= nil and ch.officerOf == club)
  -- (false: a member at this login, so this character's officer or not is known, R:AccountOfficer, by its GUID)
  if club ~= nil then ch.officerOf, ch.guid = officer and club or false, C.MyGUID() or ch.guid end
  if self.wasOfficer == officer then
    if officer and lost then ask() end
    -- (a purge that waited for the roster to say whose the file is: Policy.lua P:Purge)
    if C.Policy.purgeDue and not officer and self:AccountOfficer() ~= nil then return C.Policy:Purge() > 0 end
    return false
  end
  local was = self.wasOfficer
  self.wasOfficer = officer
  -- (an officer at the first word, whose client dropped values while it did not hold the line's policy yet: a login
  -- inside an instance by a character the line's ranks made an officer; or made one during the session. Asked again)
  if officer then self.lostUnsettled = nil end
  if officer and (was == false or lost) then ask() end
  return not officer and C.Policy:Purge(wasOne) > 0
end
-- another character of this account is an officer of this guild: the saved variables are an officer's, which hold the
-- members' Only-you values, and a member character of the account deletes none of them. A character is known by its
-- GUID (kept with officerOf, R:PurgeCheck), never by its name: a namesake officer of the guild vouches for no alt of
-- another realm or surname. The roster decides for a GUID it lists, by its rank now (one demoted while offline is no
-- officer, whatever its last login said); a GUID it does not list is no character of this guild. One without a GUID
-- goes by its last login (officerOf), and saved by 0.5.x, which kept neither, by having set the policy and the roster
-- naming one member of that name an officer now: a setter the roster cannot name (renamed, or gone from the guild)
-- vouches for nothing, and the file is purged (0.6.0's first builds kept it for good). The officer's next login asks
-- again and is whispered what went. Never on this character's own word: its rank is the roster's, read now, so an
-- officer demoted after their own last change purges like any member
-- Nil where the roster has not said: a read that does not list a character an officer at its last login, or lists it
-- with no rank, says nothing of it (the roster may be slow or incomplete, as a read of yourself without a rank says
-- nothing, R:SelfKnown), until two complete reads in a row have lacked it, as a record is pruned (R:Refresh): then it
-- is no character of this guild. A purge waits for the roster to say (Policy.lua P:Purge; 0.6.0's first builds took
-- one such read as "no officer", and a member alt's first purge deleted the officer's held Only-you values)
function R:AccountOfficer()
  local club, mine = self:ClubId(), C.Me()
  if club == nil then return false end
  local chars = CuteDB and CuteDB.chars or {}
  local thr = C.Policy:LineThreshold()
  local function officer(key, rec)
    local g = type(rec) == "table" and type(rec.guid) == "string" and rec.guid or nil
    if g and self.trusted then
      local m = self.byGuid[g]
      if m ~= nil and m.rank ~= 99 then return m.rank <= thr end
      if rec.officerOf == club and (self.charMisses[g] or 0) < 2 then return nil end
      return false
    end
    if type(rec) == "table" and rec.officerOf ~= nil then return rec.officerOf == club end
    return nil
  end
  local unknown = false
  local p = CuteDB and CuteDB.policy
  if type(p) == "table" and p.mine and type(p.by) == "string" and p.by ~= mine then
    local o = officer(p.by, chars[p.by])
    if o == nil and not (type(chars[p.by]) == "table" and chars[p.by].officerOf == club) then local m = self:SenderMember(p.by); o = m ~= nil and not m.self and m.rank <= thr end
    if o then return true elseif o == nil then unknown = true end
  end
  for key, rec in pairs(chars) do
    if key ~= mine and type(rec) == "table" then
      local o = officer(key, rec)
      if o then return true elseif o == nil and rec.officerOf == club then unknown = true end
    end
  end
  if unknown then return nil end
  return false
end
-- this character's guild is another than the saved variables' last (Policy.lua P:ForClub swapped the records in): what
-- was kept of the other guild's records this session goes, and the first purge is this guild's
function R:ClubChanged()
  self.misses, self.charMisses, self.held, self.dings, self.shared, self.unsureGuid, self.wasOfficer = {}, {}, {}, {}, {}, {}, nil
  self:Identity()
  if C.Rules and C.Rules.Dirty then C.Rules:Dirty(true) end
end

-- a refresh soon, for the club events that come once per member
function R:Soon()
  if self.soon then return end
  self.soon = true
  C_Timer.After(2, C.Safe(function() R.soon = false; R:Refresh() end, "roster: soon"))
end

-- the roster asked for (its answer, GUILD_ROSTER_UPDATE, reads Guild Info), every ask Cute makes timed here, so the
-- next one waits ten seconds after it (R:AskSoon), and a wait for Guild Info knows when its first ask went (Policy.lua)
local function askRoster()
  R.askedAt = now()
  if C.Policy and C.Policy.Asked then C.Policy:Asked() end
  if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
end
-- the roster, and Guild Info with it, asked for again soon (a policy came that Guild Info does not name: maybe a line
-- just saved): now, or as ten seconds since the last ask end (the game answers one in ten at most), and once more
-- twelve seconds after that ask where a still() says Guild Info has not answered yet (the game may let an ask pass
-- that came just after another, and a read of the text from before is no answer until then: Policy.lua P:ReadLine)
-- A doubt that outlasts the reads backs off: the re-check twelve seconds on, then 30, 60 and 120 while it keeps finding
-- the doubt (inside an instance, where Guild Info may read empty the whole run, or in the chat lockdown, a minute at
-- least: 0.7.0 asked every twelve seconds for the whole run)
R.stills, R.stillRound = {}, 0
local STILL_WAIT = { 12, 30, 60, 120 }
function R:AskSoon(still)
  if still then self.stills[#self.stills + 1] = still end
  local wait = self.askedAt and (self.askedAt + 10 - now()) or 0
  if wait > 0 then
    if self.askDue then return end
    self.askDue = true
    C_Timer.After(wait, C.Safe(function() R.askDue = false; R:AskSoon() end, "roster: Guild Info soon"))
    return
  end
  askRoster()
  local stills = self.stills
  self.stills = {}
  if #stills == 0 then return end
  local wait2 = STILL_WAIT[math.min(self.stillRound + 1, #STILL_WAIT)]
  if self.stillRound > 0 and (C.Get(IsInInstance) == true or (C.Comm and C.Comm.Locked and C.Comm:Locked())) then wait2 = math.max(wait2, 60) end
  C_Timer.After(wait2, C.Safe(function()
    for _, f in ipairs(stills) do if f() then R.stillRound = R.stillRound + 1; R:AskSoon(); return end end
    R.stillRound = 0
  end, "roster: Guild Info again"))
end

local NOW = { GUILD_ROSTER_UPDATE = true, PLAYER_GUILD_UPDATE = true, INITIAL_CLUBS_LOADED = true, CLUB_MEMBERS_UPDATED = true }
local SOON = { CLUB_MEMBER_UPDATED = true, CLUB_MEMBER_PRESENCE_UPDATED = true, CLUB_MEMBER_ADDED = true, CLUB_MEMBER_REMOVED = true }

function R:Start()
  if self.frame then askRoster(); self:Refresh(); return end
  local f = CreateFrame("Frame")
  self.frame = f
  f:SetScript("OnEvent", C.Safe(function(_, event)
    C.Perf.Count("roster")
    -- (a guild joined or left: the roster asked for, whose answer reads Guild Info)
    if event == "PLAYER_GUILD_UPDATE" then askRoster() end
    if NOW[event] then R:Refresh(event) elseif SOON[event] then R:Soon() end
  end, "roster: events"))
  for event in pairs(NOW) do pcall(f.RegisterEvent, f, event) end
  for event in pairs(SOON) do pcall(f.RegisterEvent, f, event) end
  askRoster()
  self:Refresh()
  -- the game answers a roster request about every ten seconds at most; ask again now and then for ranks and online state
  -- (its answer, GUILD_ROSTER_UPDATE, refreshes the roster: C_Club's own changes come by their events)
  local function again()
    C_Timer.After(60, C.Safe(again, "roster: again"))
    askRoster()
    -- (out of the guild a moment ago: read again, so leaving is judged, R:LeftGuild)
    if R.leftAt then R:Refresh() end
  end
  C_Timer.After(60, C.Safe(again, "roster: again"))
end

function R:InGuild() return C.Get(IsInGuild) == true end

----------------------------------------------------------------------------
-- who is who
----------------------------------------------------------------------------
-- your names as loose keys: the saved-data key, the first name and surname joined, the roster's name for you (or its
-- GUID's, where the roster's is a Kstring). Each as a whole name, never by the first-name match of R:SenderMember
local function mine(self)
  if self.mine then return self.mine end
  local set = {}
  local function add(s) local k = C.Canon(s); if k then set[k] = true end end
  add((C.Me()))
  local _, _, full = C.MyName()
  add(full)
  if self.self then add(self.self.match) end
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
-- is one: the message's (a full record, an ask, vetted first: R:Vet), else the record kept under that sender. Only
-- without one does a sender string your GUID came under count as you, then your names (C.Canon): a namesake's record,
-- which carries its own GUID, is never taken for yours by its name, nor is a sender string another's GUID came under
-- this session (R.notSelf)
function R:FromMe(sender, guid)
  if type(sender) ~= "string" then return false end
  local mine = C.MyGUID()
  if type(guid) == "string" and guid ~= "" and mine then return guid == mine, "guid" end
  local how = self.selfSenders[sender]
  if how == "guid" then return true, "guid" end
  if self.notSelf[sender] then return false, "guid" end
  local g = recordGuid(CuteDB.roster[sender])
  if g and mine then return g == mine, "guid" end
  return how ~= nil or self:IsMe(sender), "name"
end
-- a message whose GUID the roster gives someone else (R:Vet) is yours only under the sender string the roster names
-- you by: nobody else sends under it, and your own Cute sends no GUID but yours
function R:NamesMe(sender) local m = self:SenderMember(sender); return m ~= nil and m.self == true end
function R:IsSelfRecord(key, e) return (self:FromMe(key, recordGuid(e))) end
-- a sender is you: remembered for the session ("guid" when your GUID came under it, else "name"), and its record
-- dropped unless that record carries another's GUID (0.3.0 kept your own messages, handed back by the game under the
-- channel's name for you, as another member: the third row of you, its cells "?")
function R:SelfSender(sender, how)
  if type(sender) ~= "string" then return end
  if self.selfSenders[sender] ~= "guid" then self.selfSenders[sender] = how == "guid" and "guid" or "name" end
  if how == "guid" then self.notSelf[sender] = nil end
  -- (a sender with no record of its own changes no row: the window draws again only when one goes)
  local e = CuteDB.roster[sender]
  if e ~= nil and self:IsSelfRecord(sender, e) then
    CuteDB.roster[sender] = nil
    self.misses[sender] = nil
    self:Identity()
    if C.UI and C.UI.Refresh then C.UI:Refresh() end
  end
end
-- a sender whose message carried another's GUID (true or not): a name match that took it for you is forgotten, and it
-- is not you for the session unless your own GUID came under it
function R:NotMe(sender)
  if type(sender) ~= "string" or self.selfSenders[sender] == "guid" then return end
  self.notSelf[sender] = true
  if self.selfSenders[sender] == "name" then self.selfSenders[sender] = nil; self:Changed() end
end

-- the guild member an addon record (or a sender) belongs to: by the GUID its record carries, else by name. A record
-- with a GUID no member has is matched by name only to a member the roster gives no GUID
function R:MemberOf(key)
  local g = recordGuid(CuteDB.roster[key])
  if g and self.byGuid[g] then return self.byGuid[g] end
  local m = self:SenderMember(key)
  if m and g and m.guid then return nil end
  return m
end

-- the member a sender string names, the server's word on both. The channel's sender string and the roster's name may
-- be different forms of one name ("Helga Bluntforce-Realm", "Helga-Realm", "Helga Bluntforce", "Helga"), so two names
-- agree where their first words agree and their second words do not conflict: a side without a second word is no
-- conflict, and your realm trailing either is cut (C.Canon). The member is the one whose name agrees with the sender's;
-- where several do, the one whose second word is the sender's own (two characters do not share a whole name). Nil
-- before the roster is known, where none agrees, where several do and no second word tells them apart (two members
-- sharing a first name, the sender string giving no surname: unsure, never another's), and for a Kstring sender. A
-- member whose name reads in no form (a Kstring the GUID call does not resolve) is found by GUID alone, and while one
-- such is online it may be anyone's namesake: only a whole name (both words, the same) names a member then
function R:SenderMember(sender)
  if not self.trusted then return nil end
  local a, b = words(sender)
  local list = a and self.byFirst[a] or nil
  if not list then return nil end
  local one, n, whole, nw = nil, 0, nil, 0
  for _, m in ipairs(list) do
    if not (b and m.second and m.second ~= b) then
      one, n = m, n + 1
      if b and m.second == b then whole, nw = m, nw + 1 end
    end
  end
  if nw == 1 then return whole end
  if n == 1 and (self.unread or 0) == 0 then return one end
  return nil
end
-- whether the roster bears out a GUID a message under this sender string claims: "same" where the sender string names
-- the member the roster gives that GUID; "other" where the roster says otherwise: the sender string names another
-- member, or the GUID's member has another first name (the server writes the sender string, so an edited client
-- cannot change its first word; a second word may be missing on one side and proves nothing). Nil where it cannot tell
-- (a Kstring, a first name two members share with no surname to tell them apart, a GUID or a sender the roster does not
-- list or cannot read, or the roster not known yet)
function R:Vouch(sender, guid)
  if not self.trusted or type(guid) ~= "string" or guid == "" then return nil end
  local sm = self:SenderMember(sender)
  if sm and sm.guid then return sm.guid == guid and "same" or "other" end
  local m, a, b = self.byGuid[guid], words(sender)
  if m and m.first and a and m.first ~= a then return "other" end
  -- (namesakes the roster names by the first name alone, the sender string with a surname: the name the game gives the
  -- GUID tells them apart where it has the surname, else nobody can tell)
  if m and m.first == a and not m.second and b then
    local _, gb = words(guidName(guid))
    if gb then return gb == b and "same" or "other" end
  end
  return nil
end
-- a GUID a message claims, as this client takes it: the GUID, or nil and why where the roster gives it someone else
-- (the reason a record is marked suspect with, for the officers)
function R:Vet(sender, guid)
  if type(guid) ~= "string" or guid == "" then return nil end
  if self:Vouch(sender, guid) ~= "other" then return guid end
  local m = self.byGuid[guid]
  local who = m and type(m.name) == "string" and not C.IsKstring(m.name) and C.Short(m.name) or nil
  return nil, who and ("sent " .. who .. "'s GUID as its own") or "sent a GUID that is not its own"
end
-- a sender whose message claimed a GUID that is not its own: its record marked suspect, one made where create and the
-- sender string names a member (someone outside the guild has no record, and gets none)
function R:Forged(sender, why, create)
  if not why then return end
  local e = CuteDB.roster[sender]
  local made = false
  if not e and create and self:SenderMember(sender) then e = self:Entry(sender, true); made = true end
  if not e then return end
  self:Suspect(e, why)
  if made then self:Identity() else self:Changed() end
end
-- R:Refresh, the first time the roster is known and whenever it changes: a record's GUID the roster gives a member its
-- sender string does not name is dropped and the record marked suspect (taken before the roster was known, or kept by
-- a build that took any GUID), and a sender string taken for you by your GUID that the roster names as another member
-- is you no more. True when it changed something
function R:Sweep()
  local changed, mine = false, C.MyGUID()
  for key, e in pairs(CuteDB.roster) do
    local g = recordGuid(e)
    if g then
      local ok, why = self:Vet(key, g)
      if not ok then
        e.stats.guid = nil
        if type(e.at) == "table" then e.at.guid = nil end
        self:Suspect(e, why)
        changed = true
      end
    end
  end
  if mine then
    for s, how in pairs(self.selfSenders) do
      if how == "guid" and self:Vouch(s, mine) == "other" then self.selfSenders[s] = nil; self.notSelf[s] = true; changed = true end
    end
  end
  if changed then self:Identity() end
  return changed
end
-- the GUID a record speaks for in what the guild learns (the enchants, the XP curve, the rules' evidence, a label, a
-- claim, a boss's loot): the one it carries, once the roster is known (R:Sweep has judged it by then) and lists a
-- member with it. Nil before, for a record without one, and for a GUID the roster gives nobody: where the roster cannot
-- tell whose a GUID is (namesakes, a Kstring), a made-up one is kept on the record and never a voice, so a copy that
-- sends a new one each time its record is pruned is no new voice (a member who has just joined is one at the next
-- refresh)
function R:VoiceOf(key, e)
  if not self.trusted then return nil end
  local g = recordGuid(e)
  return (g and self.byGuid[g]) and g or nil
end

-- a member's rank index (0 is the guild master), by the member the sender string names; nil until the roster is known
-- or when the name is not in the guild (or not one name: a Kstring, two members' name). Who else is an officer goes by
-- the line's officer ranks (Policy.lua P:LineThreshold: Guild Info's, where the guild has a line), never by an
-- officer's own change not saved; whether you are, and whom you whisper, by the ranks you route by (P:Threshold)
function R:Rank(name) local m = self:SenderMember(name); return m and m.rank or nil end
function R:MyRank() return self.self and self.self.rank or nil end
function R:IsOfficer(name)
  local rank = self:Rank(name)
  if rank == nil then return false end
  return rank <= C.Policy:LineThreshold()
end
function R:MeOfficer()
  local rank = self:MyRank()
  return rank ~= nil and rank <= C.Policy:Threshold()
end
-- an officer for what comes whispered: one now, or one at the last read that said, while a read lists this character
-- without a rank (a blip of the roster mid-session, which says nothing, R:SelfKnown: 0.6.0's first builds dropped
-- the whispers of those seconds, and nothing asked for them again)
function R:OfficerStill()
  return self:MeOfficer() or (self.wasOfficer == true and not self:SelfKnown())
end
-- an officer's voice: a sender the roster names an officer by, not you (whose policy and word the guild takes), and
-- not one the officers marked untrusted (by GUID), who is as good as absent: it teaches nothing, silences no honest
-- officer's word and cancels no answer of theirs
function R:OfficerVoice(sender)
  local m = self:SenderMember(sender)
  return m ~= nil and not m.self and m.rank <= C.Policy:LineThreshold() and not C.Policy:Untrusted(m.guid)
end

-- the GUID behind a sender string, as a voice in what the guild learns (a kill claim, a boss's loot): its record's,
-- else the member's the sender string names; none before the roster is known
function R:GuidOf(sender)
  if not self.trusted then return nil end
  local g = recordGuid(CuteDB.roster[sender])
  if g then return self.byGuid[g] and g or nil end
  local m = self:SenderMember(sender)
  return m and m.guid or nil
end
-- the record keys by the GUID each record carries, built again only when a record or the guild changed
function R:KeysByGuid()
  if self.keysAt == self.idVersion and self.keys then return self.keys end
  local out = {}
  for key, e in pairs(CuteDB.roster) do local g = recordGuid(e); if g then out[g] = key end end
  self.keys, self.keysAt = out, self.idVersion
  return out
end
-- a GUID by its last part (the 1K messages name a group by it: "Player-4242-0A000001" is "0A000001"), among the
-- roster's members and the records; nil where none or two have it
function R:GuidBySuffix(sfx)
  if type(sfx) ~= "string" or sfx == "" then return nil end
  if self.sfxAt ~= self.idVersion or not self.sfx then
    local map = {}
    local function add(g)
      local s = type(g) == "string" and g:match("([^%-]+)$")
      if s then if map[s] == nil or map[s] == g then map[s] = g else map[s] = false end end
    end
    for g in pairs(self.byGuid) do add(g) end
    for g in pairs(self:KeysByGuid()) do add(g) end
    add(C.MyGUID())
    self.sfx, self.sfxAt = map, self.idVersion
  end
  return self.sfx[sfx] or nil
end
-- the officers online now, each as the channel names them: the members the roster ranks within the line's officer
-- ranks (P:LineThreshold; where this officer lowered them and did not save, within theirs: never wider than the line's,
-- whose officers alone build(), Comm.lua, whispers, so ranks raised and not saved queued a whisper, dropped it and
-- queued it again every second) and lists online, you left out, under the sender
-- string their own Cute's full record came under on the guild channel, the name the game takes for a whisper (a roster
-- name may be a Kstring, which is no name to send to). Only a sender string the roster names that officer by
-- (R:SenderMember), whose record a guild message made (a whisper makes none: R:Apply): a copy that put an officer's
-- GUID in its record, or a stranger whispering under a name like an officer's, is never sent to. Nor an officer still
-- on 0.5.x, whose Cute takes no whisper: what they would lose is kept for when they update and ask. An officer whose
-- Cute has said nothing yet gets the Only-you values in the answer to their ask (1R, Comm.lua). Built again when who
-- is who or the threshold changed
local WHISPERS_FROM = "0.6.0" -- the first Cute that takes a whisper
-- a sender string whose record a guild message made, carrying the GUID of the member it names and a Cute that takes
-- whispers
function R:TakesWhispers(key)
  local e = CuteDB.roster[key]
  if not (type(e) == "table" and e.ch and type(e.stats) == "table") then return false end
  local m = self:SenderMember(key)
  return m ~= nil and m.guid ~= nil and recordGuid(e) == m.guid and C.ParseVersion(e.stats.addon_ver) ~= nil
    and not C.VersionNewer(WHISPERS_FROM, e.stats.addon_ver)
end
function R:OfficerTargets()
  if not self.trusted then return {} end
  local thr = math.min(C.Policy:Threshold(), C.Policy:LineThreshold())
  -- (built again where a record changed who it is, or an officer came, went or moved, or what a sender string names
  -- did (a name, a namesake, an unread name online: R:SenderMember): not for every member online or off, 0.7.0's every
  -- roster change. A first build left the names out, and kept an officer a sender string no longer named)
  local at = self.recVersion .. ":" .. tostring(self.nameVersion) .. ":" .. tostring(self.unread) .. ":" .. tostring(self.offSig)
  if self.targets and self.targetsAt == at and self.targetsThr == thr then return self.targets end
  local out = {}
  for key in pairs(CuteDB.roster) do
    local m = self:SenderMember(key)
    if m and not m.self and m.online and m.rank <= thr and self:TakesWhispers(key) then out[#out + 1] = key end
  end
  table.sort(out)
  self.targets, self.targetsAt, self.targetsThr = out, at, thr
  return out
end
-- is the member a sender string names one this client may whisper the officers' values to (whatever GUID its message
-- carries): ranked within the line's officer ranks (P:LineThreshold)
function R:OfficerSender(sender)
  local m = self:SenderMember(sender)
  return m ~= nil and not m.self and m.rank <= C.Policy:LineThreshold()
end
-- a whisper's sender is in the guild: a sender string this client has heard on the guild channel (its record says so,
-- or this session's R.heard: only a guild message makes a record, R:Apply), the roster has a member for it (by the GUID
-- its record carries, else by name) and, where the message carries a GUID (vetted: R:Vet), it is the one the record
-- has. Someone outside the guild, under a name like a member's in any form, is ignored: the game delivers a whisper from
-- anyone, a guild message only from the guild. "wait" where the sender string was heard on the guild channel but its
-- record has not the GUID the whisper carries yet (its full record on the guild channel is still to come: Comm.lua keeps
-- the whisper until it does)
function R:GuildSender(sender, guid)
  if not self.trusted or type(sender) ~= "string" then return false end
  local e = CuteDB.roster[sender]
  local ch = type(e) == "table" and e.ch
  if not (ch or self.heard[sender]) then return false end
  local m = self:MemberOf(sender)
  if not m then return false end
  local g = type(e) == "table" and recordGuid(e) or nil
  if type(guid) == "string" and guid ~= "" and guid ~= g then
    if g == nil and m.guid == guid then return "wait" end
    return false
  end
  return true
end
-- a member's addon sent what cannot be: marked suspect, the reason and when kept on the record (the officers see it),
-- and the stat whose value the reason names (id), so a member's client keeps no value the officers keep in it
-- (Policy.lua P:Purge)
function R:Suspect(e, why, id)
  local n = (type(e.suspect) == "table" and tonumber(e.suspect.n)) or 0
  e.suspect = { why = tostring(why):sub(1, 120), at = now(), n = n + 1, id = type(id) == "string" and id or nil }
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
-- carrying another's GUID, where the roster does not say otherwise, is theirs whatever the sender string. The kinds of
-- a member's enchanted items (the hidden ench_kinds) teach the guild's knowledge (Stats.lua LearnEnchants), counted
-- once per member by the GUID the record carries: a delta that comes before any full record has brought the GUID
-- teaches nothing yet (counted under the sender string, the member would count twice once the GUID came); the full
-- record, which carries both, does. The rules weigh the rest the same way, by GUID (Rules.lua R:Observe)
-- What arrives is checked first: a GUID the roster gives someone else is dropped and the record marked suspect (R:Vet),
-- a record keeps the GUID it has unless the roster names the sender by the new one, a member's client keeps none of
-- another member's Only-you values, whoever sent them (an honest Cute whispers those to the officers alone; this is
-- for one that does not), and a value that cannot be is dropped and its record marked suspect (Stats.lua
-- S.Implausible). What is kept is what the rest of this sees
local MAX_GAME = 1000 -- dynamic values kept per member from the wire, statistics and discoveries together (g, e, i, f)
local CHECKED = { level = true, xpmax = true } -- (the ids whose check asks the roster's level or the cap)
-- A statistic this client has not defined yet has no category here, so on a member's client it routes as the
-- strictest of the game's categories (Policy.lua P:Route) and would be dropped wherever the officers keep any of them
-- to themselves, though its own category may be open. While this client's probe may still define statistics (Stats.lua
-- S.gamePending: the list was empty at login and is asked again), such a value is held aside instead, in memory only
-- (R.held[key][id], MAX_GAME a member), and kept or dropped by its real route once the probe has defined it or given up
-- (R:ReleaseHeld), so nothing a later probe would show is lost and nothing the officers keep is kept
R.held = {}
local function holdable(id) return C.Stats.gamePending == true and type(id) == "string" and id:match("^g%d+$") ~= nil and not C.Stats.byId[id] end
local function hold(key, id, v, t)
  local h = R.held[key]
  if not h then h = { n = 0, v = {} }; R.held[key] = h end
  if h.v[id] == nil then
    if h.n >= MAX_GAME then return end
    h.n = h.n + 1
  end
  h.v[id] = { v = v, t = t }
end
function R:ReleaseHeld()
  local held = self.held
  self.held = {}
  local officer, n = self:MeOfficer(), 0
  for key, h in pairs(held) do
    local e = CuteDB.roster[key]
    if type(e) == "table" and type(e.stats) == "table" then
      e.at = type(e.at) == "table" and e.at or {}
      local games
      for id, x in pairs(h.v) do
        if (officer or C.Policy:Route(id) == "all") and (e.at[id] == nil or e.at[id] <= x.t) then
          if e.stats[id] == nil then
            if not games then games = 0; for k in pairs(e.stats) do if C.Stats.IsDynamic(k) then games = games + 1 end end end
            if games < MAX_GAME then games = games + 1; e.stats[id] = x.v; e.at[id] = x.t; n = n + 1 end
          else e.stats[id] = x.v; e.at[id] = x.t; n = n + 1 end
        end
      end
    end
  end
  if n > 0 then
    self:Changed()
    if C.UI and C.UI.Refresh then C.UI:Refresh() end
  end
  -- (the saved statistics the purge left for the probe's last word go by their own category now: Policy.lua P:Purge)
  if C.Policy and C.Policy.Purge then C.Policy:Purge() end
  return n
end
-- a member's level as C_Club gives it now (the roster refreshes on its events and once a minute, and a ding reaches
-- the channel first): asked again before a level that disagrees with it is judged
local function freshLevel(m)
  if not (m and m.id ~= nil) then return m and m.level or nil end
  local clubId = C.Get(C.Api("C_Club", "GetGuildClubId"))
  local info = clubId ~= nil and C.Get(C.Api("C_Club", "GetMemberInfo"), clubId, m.id) or nil
  local l = type(info) == "table" and C.Plain(info.level) or nil
  if type(l) == "number" then m.level = l end
  return m.level
end
-- a level the channel told above the roster's, held until the roster agrees, then taken, or DING_WAIT seconds have
-- passed with the roster still disagreeing, then its record marked suspect (two dings in a row reach the channel
-- before the roster, and the game answers a roster request every ten seconds at most); the roster asked again every
-- few seconds meanwhile
local DING_WAIT, DING_AGAIN = 30, 300
function R:Dings()
  local t, waiting = now(), false
  for name, d in pairs(self.dings) do
    local e = CuteDB.roster[name]
    local g = e and recordGuid(e)
    local m = e and ((g and self.byGuid[g]) or (not g and self:MemberOf(name)))
    if e and m and m.level and math.abs(d.l - m.level) > 1 and t - d.t < DING_WAIT then
      waiting = true
    else
      self.dings[name] = nil
      if e and m and m.level then
        if math.abs(d.l - m.level) > 1 then self:Suspect(e, string.format("level %d where the guild roster says %d", d.l, m.level), d.id)
        elseif d.id == "level" and type(e.at) == "table" and (e.at.level or 0) <= d.t then e.stats.level = d.l; e.at.level = d.t; self:Changed() end
      end
    end
  end
  if waiting and not self.dingDue then
    self.dingDue = true
    C_Timer.After(5, C.Safe(function() R.dingDue = false; askRoster(); R:Refresh() end, "roster: a ding held"))
  end
end
-- values that arrived; whispered: from a whisper (Comm.lua), which only adds to a record a guild message made: it
-- makes none, sets or changes no GUID and folds no records (the game delivers a whisper from anyone)
-- Two members whose sender strings are one (namesakes the channel names by the first name alone) cannot be told
-- apart: once two GUIDs the roster cannot vouch for came under one sender string, nobody is marked, the record keeps
-- no GUID (no voice, no row of either) and its values are not held to the ones before, which may be the other's
-- (R.shared, for the session)
R.shared, R.unsureGuid = {}, {}
-- (a list's value is a table each message decodes anew: the same where it holds the same entries)
local function sameValue(a, b)
  if type(a) == "table" and type(b) == "table" then
    for k, x in pairs(a) do if b[k] ~= x then return false end end
    for k, x in pairs(b) do if a[k] ~= x then return false end end
    return true
  end
  return a == b
end
function R:Apply(name, kv, whispered)
  local db = CuteDB.roster
  if whispered then
    local e = db[name]
    if not (type(e) == "table" and (e.ch or self.heard[name])) then return end
    if kv.guid ~= nil and kv.guid ~= recordGuid(e) then return end
    kv.guid = nil
  end
  local claimed, forged = kv.guid, nil
  if claimed ~= nil then
    local ok, why = self:Vet(name, claimed)
    if not ok then kv.guid, forged = nil, why end
  end
  local me, how
  if forged then me = self:NamesMe(name) else me, how = self:FromMe(name, kv.guid) end
  if me then self:SelfSender(name, how); return end
  if type(claimed) == "string" then self:NotMe(name) end
  -- (a GUID the roster cannot vouch for under this sender string because two members share its first name is kept by
  -- no record, whichever came first: a copy sending a namesake's GUID takes no row, voice or invite of hers, and the
  -- namesakes' own records are neither, as never vouched for. A sender string that reads as no name, a Kstring, may be
  -- any member's own; two such GUIDs under one sender string are two namesakes sharing it, R.shared)
  local first = type(kv.guid) == "string" and words(name) or nil
  local unsure = first ~= nil and #(self.byFirst[first] or {}) > 1 and self:Vouch(name, kv.guid) == nil
  if unsure then
    local was = self.unsureGuid[name]
    if was and was ~= kv.guid then self.shared[name] = true end
    self.unsureGuid[name] = was or kv.guid
    kv.guid = nil
  end
  local created = db[name] == nil
  local e = self:Entry(name, true)
  if unsure and type(e.stats.guid) == "string" and self:Vouch(name, e.stats.guid) ~= "same" then
    e.stats.guid = nil
    if type(e.at) == "table" then e.at.guid = nil end
  end
  local guidWas, verWas, chWas = e.stats.guid, e.stats.addon_ver, e.ch
  -- (heard on the guild channel: whispers from this sender string are taken from now on, R:GuildSender)
  if not whispered then e.ch = true end
  if forged then self:Suspect(e, forged) end
  -- one GUID to a record: another replaces it only where the sender string names its member (a copy that sent its own
  -- GUID and then another's would be two voices); where the roster can vouch for neither, two namesakes share the
  -- sender string (R.shared)
  if type(kv.guid) == "string" and type(e.stats.guid) == "string" and e.stats.guid ~= kv.guid and self:Vouch(name, kv.guid) ~= "same" then
    if self:Vouch(name, kv.guid) == nil and self:Vouch(name, e.stats.guid) == nil then
      self.shared[name] = true
      e.stats.guid = nil
      if type(e.at) == "table" then e.at.guid = nil end
    else
      self:Suspect(e, "sent a second GUID")
    end
    kv.guid = nil
  end
  local shared = self.shared[name] == true
  if shared then kv.guid = nil end
  local t = now()
  -- (an officer at the last read that said, while this one lists her without a rank, is one still: kept, not dropped)
  local officer, P, S = self:OfficerStill(), C.Policy, C.Stats
  -- (a value dropped before this client holds the line's policy may be an officer's to keep by it: R:PurgeCheck asks
  -- again once the line makes this client one)
  local unsettled = not officer and not P:Settled()
  -- (Ready from a 0.5.x member counted the gear gaps the officers keep: a member's client keeps none of it)
  local ver = kv.addon_ver or e.stats.addon_ver
  local ctx
  local kept = {}
  for id, v in pairs(kv) do
    if v == 0 and type(id) == "string" and id:match("^g%d+$") then
      -- (a statistic's "--", never recorded, which a 0.7 client sends as 0: kept as nothing, Stats.lua S.Quantity)
      if e.stats[id] ~= nil then e.stats[id] = nil; if type(e.at) == "table" then e.at[id] = nil end end
    elseif not officer and holdable(id) and P:Route(id) == "self" then
      -- (a statistic not defined here yet: held aside until its category is known, its bounds checked now)
      local why = S.Implausible(id, v, nil, nil)
      if why then self:Suspect(e, why, id) else hold(name, id, v, t) end
    elseif id == "ready" and not officer and not P.CurrentReady(ver) then
      if e.stats.ready ~= nil then e.stats.ready = nil; e.at.ready = nil end
    elseif not officer and P:Route(id) ~= "all" then
      -- (dropped: maybe a stat the officers have just opened, sent once by a client that read the new line first;
      -- asked for again once this client holds the line that opens it, Policy.lua P:Settle)
      self.lostUnsettled = true
    else
      if (CHECKED[id] or (type(id) == "string" and id:match("^k%d+$"))) and not ctx then
        -- the member as the roster lists them: by the GUID that came, else the record's, else the sender's name (a GUID
        -- the roster has not got is no member's, and has no level to hold it to)
        local g = (type(kv.guid) == "string" and kv.guid) or (type(e.stats.guid) == "string" and e.stats.guid) or nil
        local m
        if g then m = self.byGuid[g] else m = self:MemberOf(name) end
        ctx = { m = m, level = m and m.level or nil, cap = C.Rules and C.Rules.Cap() or nil }
      end
      local old = not shared and e.stats[id] or nil
      local why = S.Implausible(id, v, old, ctx)
      if why and CHECKED[id] and ctx.m and ctx.level then
        -- (the roster may lag the channel: asked again; a level above it, under the cap, waits for the roster: R:Dings)
        local l = id == "level" and v or tonumber(tostring(v):match("^(%d+):"))
        if type(l) == "number" and math.abs(l - ctx.level) > 1 then
          ctx.level = freshLevel(ctx.m)
          why = S.Implausible(id, v, old, ctx)
          if why and ctx.level and l > ctx.level + 1 and not (ctx.cap and l > ctx.cap) then
            -- (the game asked for the roster again: judged when it comes, a few seconds on; held from the first time, so
            -- a sender saying it again waits no longer nor asks again, and one marked for it minutes ago is marked
            -- again at once)
            local d0, s = self.dings[name], e.suspect
            if d0 or not (type(s) == "table" and s.id == id and t - (tonumber(s.at) or 0) < DING_AGAIN) then
              self.dings[name] = { id = id, l = l, t = d0 and d0.t or t }
              why = "held"
              if not d0 then askRoster(); self:Soon() end
            end
          end
        end
      end
      if why == "held" then -- (judged once the roster has it: R:Dings)
      elseif why then self:Suspect(e, why, id) else kept[id] = v end
    end
  end
  kv = kept
  -- one record per GUID: the same character under another sender string (a rename, or a client that names senders
  -- differently) is folded into this one, only where the roster names this sender by that GUID's member (a copy that
  -- claimed another's GUID would take their record over and delete it), and never from a whisper
  local folded = false
  -- (only where this record's GUID is new, or another record holds it: a record's every first chunk carries its GUID,
  -- and 0.7.0 walked every record for each)
  local other = type(kv.guid) == "string" and self:KeysByGuid()[kv.guid]
  if not whispered and type(kv.guid) == "string" and (guidWas ~= kv.guid or (other and other ~= name)) and self:Vouch(name, kv.guid) == "same" then
    for k, other in pairs(db) do
      if k ~= name and type(other.stats) == "table" and other.stats.guid == kv.guid then
        for id, v in pairs(other.stats) do if e.stats[id] == nil then e.stats[id] = v; e.at[id] = other.at and other.at[id] end end
        db[k] = nil
        self.misses[k] = nil
        folded = true
      end
    end
  end
  local games
  local dynamic = C.Stats.IsDynamic
  local fresh
  -- (prev: the values held before, of the ids whose value changed, false for none: what the rules weigh, Rules.lua
  -- R:Observe, and only that)
  local prev = {}
  for id, v in pairs(kv) do
    local keep = true
    local old = e.stats[id]
    if old == nil and dynamic(id) then
      if not games then games = 0; for k in pairs(e.stats) do if dynamic(k) then games = games + 1 end end end
      if games >= MAX_GAME then keep = false else games = games + 1; fresh = fresh or {}; fresh[#fresh + 1] = id end
    end
    if keep then
      if not sameValue(old, v) then if old == nil then prev[id] = false else prev[id] = old end end
      -- (when a value came is kept for the registry's stats, whose tooltips say "Reported ... ago"; the statistics and
      -- discoveries, a few hundred a member, keep none: half of a month-old file was their times)
      e.stats[id] = v
      if dynamic(id) then e.at[id] = nil else e.at[id] = t end
    end
  end
  -- (a discovery whose label came before a member's value for it is defined now: Stats.lua S.Found)
  if fresh and S.ValueCame then for _, id in ipairs(fresh) do S.ValueCame(id, name) end end
  -- (a voice once the roster is known: the first refresh teaches what came before it, R:Refresh)
  local g = self:VoiceOf(name, e)
  if kv.ench_kinds ~= nil and type(e.stats.ench_kinds) == "string" and g then
    local kinds, enchs = C.Stats.EnchantKinds(e.stats.ench_kinds)
    C.Stats.LearnEnchants(kinds, g, enchs)
  end
  -- what the rules weigh (Rules.lua): the XP a level takes, kills and their levels, levels and worn slots
  if C.Rules then C.Rules:Observe(e.stats, kv, g, prev) end
  -- a member's Cute newer than yours (Core.lua), from a voice the officers have not marked untrusted
  if kv.addon_ver ~= nil and g and not P:Untrusted(g) then C.SawVersion(kv.addon_ver, g) end
  e.seen, e.online = t, true
  self.updatedAt = t
  if created or folded or e.stats.guid ~= guidWas or e.stats.addon_ver ~= verWas or e.ch ~= chWas then self:Identity() else self:Changed() end
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
  -- the records by the GUID they carry, and by the member their sender string names the ones no GUID has come with;
  -- yours left out
  local byGuid, byName = {}, {}
  for key, e in pairs(db) do
    if self:IsSelfRecord(key, e) then claimed[key] = true
    else
      local g = recordGuid(e)
      -- (two records of one GUID: the one whose sender string the roster names by it)
      if g then if byGuid[g] == nil or self:Vouch(key, g) == "same" then byGuid[g] = key end
      else
        local m = self:SenderMember(key)
        if m then byName[m.key] = byName[m.key] == nil and key or false end
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
      local key = (m.guid and byGuid[m.guid]) or byName[m.key] or nil
      if key and claimed[key] then key = nil end
      if key then claimed[key] = true end
      local e = key and db[key] or nil
      -- (the roster's level first: the server's word, not the member's addon's)
      local guid = m.guid or recordGuid(e)
      add({ key = key or m.key, name = m.name or "?", guild = m, entry = e, addon = e ~= nil, online = m.online, rank = m.rank,
        class = m.class, level = m.level or (e and e.stats.level), zone = m.zone, seen = e and e.seen, guid = guid,
        suspect = e and type(e.suspect) == "table" and e.suspect or nil, untrusted = C.Policy:Untrusted(guid),
        stats = e and e.stats or {}, at = e and e.at or {} })
    end
  end
  -- records no member claimed: people the roster has not listed (yet); none out of a guild, where only you show
  local guildless = not self:InGuild()
  for key, e in pairs(guildless and {} or db) do
    local g = recordGuid(e)
    if not claimed[key] and not (g and self.byGuid[g]) then
      add({ key = key, name = key, entry = e, addon = true, online = false, rank = 99, class = e.class, guid = g,
        suspect = type(e.suspect) == "table" and e.suspect or nil, untrusted = C.Policy:Untrusted(g),
        level = e.stats.level, seen = e.seen, stats = e.stats, at = e.at })
    end
  end
  -- you: the roster's member for you, else the names the client gives
  local myName = (me and me.name) or select(3, C.MyName()) or C.Me()
  if myName then
    add({ key = me and me.key or "me", name = myName, me = true, guild = me, addon = true, online = true, rank = me and me.rank or 99, guid = C.MyGUID(),
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

-- for /cute diag: the last list against the club's count, and the namesakes nobody can tell apart (unsure GUIDs, sender
-- strings two members share, members online whose name reads in no form)
function R:ListReport()
  local unsure, shared = 0, 0
  for _ in pairs(self.unsureGuid) do unsure = unsure + 1 end
  for _ in pairs(self.shared) do shared = shared + 1 end
  return string.format("list: %s of %s read (%d not read), %s | unsure namesakes %d, shared senders %d, unread names online %d",
    tostring(self.listed or 0), tostring(self.expected or "?"), self.skipped or 0, self.listedWhole and "whole" or "not whole", unsure, shared, self.unread or 0)
end
-- for /cute diag
function R:MyRowCount() local n = 0; for _, r in ipairs(self:Rows()) do if r.me then n = n + 1 end end return n end
function R:RecordCount() local n = 0; for _ in pairs(CuteDB and CuteDB.roster or {}) do n = n + 1 end return n end
function R:SelfSenderCount() local n = 0; for _ in pairs(self.selfSenders) do n = n + 1 end return n end
-- how this client's names look, as shapes, never the names (C.NameShape): the sender strings records came under (and
-- yours), the roster's names, the names GetPlayerInfoByGUID gave where the roster's are Kstrings, and how the records'
-- GUIDs fared (vouched: the sender string names their member; unsure: the roster cannot say; other: the GUID was
-- another's, dropped and the record marked). One paste says which forms the live client gives
function R:NameShapes()
  if not self.trusted then return "the roster is not known yet" end
  local function tally(t, k) t[k] = (t[k] or 0) + 1 end
  local function said(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    if #keys == 0 then return "none" end
    table.sort(keys, function(x, y) if t[x] ~= t[y] then return t[x] > t[y] end return x < y end)
    for i, k in ipairs(keys) do keys[i] = k .. " (" .. t[k] .. ")" end
    return table.concat(keys, ", ")
  end
  local senders, roster, byGuid = {}, {}, {}
  local vouched, unsure, other = 0, 0, 0
  for key, e in pairs(CuteDB.roster) do
    tally(senders, C.NameShape(key))
    if not self:IsSelfRecord(key, e) then
      local g = recordGuid(e)
      local v = g and self:Vouch(key, g) or nil
      if v == "same" then vouched = vouched + 1
      elseif v == "other" or (not g and type(e.suspect) == "table" and tostring(e.suspect.why):find("GUID", 1, true)) then other = other + 1
      elseif g then unsure = unsure + 1 end
    end
  end
  for s in pairs(self.selfSenders) do if not CuteDB.roster[s] then tally(senders, C.NameShape(s)) end end
  for _, m in ipairs(self.members) do
    tally(roster, C.NameShape(m.name))
    if m.from == "guid" then tally(byGuid, C.NameShape(m.match))
    elseif m.from == nil and m.guid then tally(byGuid, "nothing") end
  end
  return string.format("senders: %s; roster: %s; GUID names: %s; vouched %d, unsure %d, other %d", said(senders), said(roster),
    next(byGuid) and said(byGuid) or "not needed", vouched, unsure, other)
end
