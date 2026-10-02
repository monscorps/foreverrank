-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank discoveries: Forever is a discovery version of the game, so what players see beats any
-- database. This notes what the game shows you while you quest, in QuestBank's own saved file:
--   quests   title, quest level, and the XP the quest window and the hand-in show at your level
--   npcs     who gives and who takes each quest, with where they stand (map and position)
--   offers   which quests an NPC offers you, and the lowest level you were offered each at
--   chains   a quest offered straight after you hand one in, by the same NPC
-- No player, guild or realm names; just your level, race and class for what you were offered.
-- It never leaves your PC on its own: upload QuestBank.lua at foreverrank.com/questbank/, or let ForeverProbe
-- (optional) carry it in its export. Everyone's notes are merged into the next QuestBank release.
local _, QB = ...
local Disc = {}
QB.Discover = Disc

local MAX_PLACES = 4 -- positions kept per NPC (they wander a little, and some stand in two places)

local function db()
  QuestBankDB = QuestBankDB or {}
  local d = QuestBankDB.disc
  if not d or d.v ~= 1 then
    d = { v = 1, q = {}, npc = {}, offer = {}, chain = {}, item = {} }
    QuestBankDB.disc = d
  end
  return d
end
Disc.DB = db

-- "Creature-0-...-<id>-..." -> "c123"; "GameObject-..." -> "o456"; players and pets don't count
local function who(unit)
  if not UnitGUID then return nil end
  local ok, guid = pcall(UnitGUID, unit)
  -- the Forever client hands addons a secret value for some units (seen in uploads): nobody, not an error
  if not ok or type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end
  local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
  if kind == "Creature" or kind == "Vehicle" then return "c" .. id, guid end
  if kind == "GameObject" then return "o" .. id, guid end
  return nil
end
Disc.Who = who

-- where you stand: "uiMap:x,y" in map percent, one decimal
local function here()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
  local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
  if not ok or not m then return nil end
  local ok2, pos = pcall(C_Map.GetPlayerMapPosition, m, "player")
  if not ok2 or not pos then return nil end
  local x, y = pos.x, pos.y
  if pos.GetXY then x, y = pos:GetXY() end
  if not x or not y or (x == 0 and y == 0) then return nil end
  return string.format("%d:%.1f,%.1f", m, x * 100, y * 100)
end
Disc.Here = here

local function level() return UnitLevel and UnitLevel("player") or 0 end

local function quest(id, title)
  local d = db()
  local q = d.q[id]
  if not q then
    q = { xp = {} }
    d.q[id] = q
  end
  if title and title ~= "" then q.t = title end
  return q
end

local function noteNpc(key, name, spot)
  if not key then return end
  local d = db()
  local n = d.npc[key]
  if not n then
    n = { p = {} }
    d.npc[key] = n
  end
  if name and name ~= "" then n.n = name end
  if spot then
    for _, p in ipairs(n.p) do if p == spot then return end end
    if #n.p < MAX_PLACES then n.p[#n.p + 1] = spot end
  end
end

local function addTo(list, value)
  for _, v in ipairs(list) do if v == value then return end end
  list[#list + 1] = value
end

-- the XP a quest pays at a level: the quest window's and the hand-in's, with the sleeping bag noted
local function noteXP(q, xp, how)
  if issecretvalue and issecretvalue(xp) then return end
  if not xp or xp <= 0 then return end
  local key = level() .. ((QB.API and QB.API.HasWellRested and QB.API.HasWellRested()) and "b" or "")
  q.xp[key] = xp
  if how == "turnin" then q.paid = (q.paid or 0) + 1 end
end

local lastTurnIn -- { id, npc, t }: a quest offered by the same NPC right after it is the next step
local lastComplete -- { id, npc }: the reward window, since the NPC may be gone by the hand-in event

local function now() return GetTime and GetTime() or 0 end

function Disc.OnEvent(event, a1, a2)
  if event == "QUEST_DETAIL" then
    local id = QB.Plain(GetQuestID and GetQuestID())
    if not id or id == 0 then return end
    local q = quest(id, QB.Plain(GetTitleText and GetTitleText()))
    local npc = who("npc")
    local item = tonumber(QB.Plain(a1))
    if item and item > 0 then
      db().item[item] = id
      q.from = q.from or {}
      addTo(q.from, "i" .. item)
    elseif npc then
      noteNpc(npc, UnitName and UnitName("npc"), here())
      q.from = q.from or {}
      addTo(q.from, npc)
      if lastTurnIn and lastTurnIn.npc == npc and lastTurnIn.id ~= id and now() - lastTurnIn.t < 8 then
        db().chain[lastTurnIn.id .. ">" .. id] = true
      end
    end
    noteXP(q, GetRewardXP and GetRewardXP(), "window")
    if GetSuggestedGroupNum then q.g = GetSuggestedGroupNum() or q.g end
  elseif event == "QUEST_COMPLETE" then
    local id = QB.Plain(GetQuestID and GetQuestID())
    if not id or id == 0 then return end
    local q = quest(id, QB.Plain(GetTitleText and GetTitleText()))
    local npc = who("npc")
    if npc then
      noteNpc(npc, UnitName and UnitName("npc"), here())
      q.to = q.to or {}
      addTo(q.to, npc)
    end
    lastComplete = { id = id, npc = npc }
    noteXP(q, GetRewardXP and GetRewardXP(), "window")
  elseif event == "QUEST_TURNED_IN" then
    local id, xp = a1, a2
    if not id or (issecretvalue and issecretvalue(id)) then return end
    local q = quest(id)
    noteXP(q, xp, "turnin")
    local npc = who("npc") or (lastComplete and lastComplete.id == id and lastComplete.npc) or nil
    lastTurnIn = { id = id, npc = npc, t = now() }
  elseif event == "QUEST_ACCEPTED" then
    -- (questID in the modern event; the log index first on Classic-style clients)
    local id = QB.Plain(a2 or a1)
    if not id or not C_QuestLog then return end
    local q = quest(id)
    if C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetInfo then
      local i = C_QuestLog.GetLogIndexForQuestID(id)
      local info = i and C_QuestLog.GetInfo(i)
      if info then
        if info.title then q.t = info.title end
        if info.level and info.level > 0 then q.lv = info.level end
        if info.suggestedGroup and info.suggestedGroup > 0 then q.g = info.suggestedGroup end
      end
    end
    q.min = math.min(q.min or 99, level())
  elseif event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
    local npc = who("npc")
    if not npc then return end
    noteNpc(npc, UnitName and UnitName("npc"), here())
    local offers = db().offer
    offers[npc] = offers[npc] or {}
    local lvl = level()
    local function offered(id, title, qlevel)
      if not id or id == 0 then return end
      local q = quest(id, title)
      if qlevel and qlevel > 0 then q.lv = qlevel end
      q.from = q.from or {}
      addTo(q.from, npc)
      offers[npc][id] = math.min(offers[npc][id] or 99, lvl)
      q.min = math.min(q.min or 99, lvl)
    end
    if event == "GOSSIP_SHOW" and C_GossipInfo and C_GossipInfo.GetAvailableQuests then
      for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do offered(info.questID, info.title, info.questLevel) end
      for _, info in ipairs((C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests()) or {}) do
        if info.questID and info.isComplete then
          local q = quest(info.questID, info.title)
          q.to = q.to or {}
          addTo(q.to, npc)
        end
      end
    elseif event == "QUEST_GREETING" and GetNumAvailableQuests and GetAvailableQuestInfo then
      for i = 1, GetNumAvailableQuests() or 0 do
        local _, _, _, _, id = GetAvailableQuestInfo(i)
        offered(id, GetAvailableTitle and GetAvailableTitle(i), GetAvailableLevel and GetAvailableLevel(i))
      end
    end
  end
end

-- how much is noted, for /qb discoveries and the Settings page
function Disc.Count()
  local d = db()
  local nq, nn, nc = 0, 0, 0
  for _ in pairs(d.q) do nq = nq + 1 end
  for _ in pairs(d.npc) do nn = nn + 1 end
  for _ in pairs(d.chain) do nc = nc + 1 end
  return nq, nn, nc
end

function Disc:Init()
  if self.frame then return end
  local f = CreateFrame("Frame")
  self.frame = f
  f:SetScript("OnEvent", QB.Safe(function(_, event, a1, a2) Disc.OnEvent(event, a1, a2) end, "discoveries"))
  for _, e in ipairs({ "QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "GOSSIP_SHOW", "QUEST_GREETING" }) do
    pcall(f.RegisterEvent, f, e)
  end
  local d = db()
  d.build = (GetBuildInfo and select(2, GetBuildInfo())) or d.build
  d.ver = QB.version
end
