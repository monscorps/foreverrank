-- ForeverProbe :: dormant collectors for the features the site ships later.
--
-- Nemesis (PvP kills taken and dealt), guild roster snapshots, and richer
-- character progression. All of it sits quietly in SavedVariables and only
-- leaves the game inside the manual export, like everything else here.
local ADDON, NS = ...
local Nemesis = {}
NS.Nemesis = Nemesis

local band = bit.band
local HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40
local IS_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x400
local lastHit

local function safe(fn, ...)
  local ok, a, b, c = pcall(fn, ...)
  if ok then return a, b, c end
end

local function stamp() return date("!%Y-%m-%dT%H:%M:%SZ") end

local function store()
  local d = NS.db()
  d.nemesis = d.nemesis or { kills = {}, deaths = {} }
  return d.nemesis
end

local function push(list, e, cap)
  list[#list + 1] = e
  while #list > (cap or 400) do table.remove(list, 1) end
end

local function classOf(guid)
  if guid and GetPlayerInfoByGUID then
    local _, cls = safe(GetPlayerInfoByGUID, guid)
    return cls
  end
end

function Nemesis:OnCLEU()
  if not CombatLogGetCurrentEventInfo then return end
  local _, sub, _, srcGUID, srcName, srcFlags, _, dstGUID, dstName, dstFlags = CombatLogGetCurrentEventInfo()
  local me = UnitGUID("player")
  if dstGUID == me and srcGUID and srcGUID ~= me and sub and sub:find("_DAMAGE") then
    if band(srcFlags or 0, IS_PLAYER) > 0 and band(srcFlags or 0, HOSTILE) > 0 then
      lastHit = { name = srcName, guid = srcGUID, t = GetTime() }
    end
  elseif sub == "PARTY_KILL" and srcGUID == me and band(dstFlags or 0, IS_PLAYER) > 0 then
    push(store().kills, { t = stamp(), who = dstName, cls = classOf(dstGUID),
      zone = safe(GetRealZoneText), lvl = UnitLevel("player") })
  end
end

function Nemesis:OnDeath()
  -- Only a player who hit you inside the last 10 seconds counts as a nemesis.
  if lastHit and GetTime() - lastHit.t < 10 then
    push(store().deaths, { t = stamp(), who = lastHit.name, cls = classOf(lastHit.guid),
      zone = safe(GetRealZoneText), lvl = UnitLevel("player") })
  end
  lastHit = nil
end

-- Guild: one roster snapshot per session, when the client hands it over.
local guildDone = false
function Nemesis:OnGuildRoster()
  if guildDone then return end
  local gname = safe(GetGuildInfo, "player")
  if not gname then return end
  local n = safe(GetNumGuildMembers) or 0
  if n == 0 then return end
  local roster = {}
  for i = 1, math.min(n, 300) do
    local name, _, _, lvl, _, _, _, _, online = safe(GetGuildRosterInfo, i)
    if name then roster[#roster + 1] = { n = name, lvl = lvl, on = online and 1 or nil } end
  end
  local d = NS.db()
  d.guild = { at = stamp(), name = gname, members = n, roster = roster }
  guildDone = true
end

-- Character progression: professions and money ride along on every snapshot.
function NS.progExtras()
  local out = { money = safe(GetMoney) }
  local skills = {}
  if GetNumSkillLines then
    for i = 1, (safe(GetNumSkillLines) or 0) do
      local name, isHeader, _, rank, _, _, maxRank = safe(GetSkillLineInfo, i)
      if name and not isHeader and (rank or 0) > 0 then skills[#skills + 1] = { n = name, r = rank, m = maxRank } end
    end
  elseif GetProfessions then
    local idx = { safe(GetProfessions) }
    for _, i in ipairs(idx) do
      if i then
        local name, _, rank, maxRank = safe(GetProfessionInfo, i)
        if name then skills[#skills + 1] = { n = name, r = rank, m = maxRank } end
      end
    end
  end
  if #skills > 0 then out.skills = skills end
  return out
end

NS.events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
NS.events:RegisterEvent("GUILD_ROSTER_UPDATE")
local prev = NS.onEvent
NS.onEvent = function(event, a1, a2)
  if prev then prev(event, a1, a2) end
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then Nemesis:OnCLEU()
  elseif event == "PLAYER_DEAD" then Nemesis:OnDeath()
  elseif event == "GUILD_ROSTER_UPDATE" then Nemesis:OnGuildRoster()
  elseif event == "PLAYER_ENTERING_WORLD" then
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_Timer.After(8, function() pcall(C_GuildInfo.GuildRoster) end)
    elseif GuildRoster then C_Timer.After(8, function() pcall(GuildRoster) end) end
  end
end
