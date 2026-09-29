-- QuestBank core: game-state reads, quest status, settings, events, export.
-- Everything here only reads the game. Nothing changes your character.
local ADDON, QB = ...
QB.version = "2.0.0"
QB.CAP = 30

local D = QB.Data
local API = {}
QB.API = API

----------------------------------------------------------------------------
-- API shims: the Forever client carries the modern API, Classic names are the
-- fallback so the addon also loads on a Classic-era client.
----------------------------------------------------------------------------
function API.IsDone(id)
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
    return C_QuestLog.IsQuestFlaggedCompleted(id) and true or false
  end
  if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(id) and true or false end
  return false
end

local function isComplete(questID, flag)
  if C_QuestLog and C_QuestLog.IsComplete then
    local ok, v = pcall(C_QuestLog.IsComplete, questID)
    if ok and v ~= nil then return v and true or false end
  end
  if IsQuestComplete then
    local ok, v = pcall(IsQuestComplete, questID)
    if ok and v ~= nil then return v and true or false end
  end
  return flag == 1 or flag == true
end

function API.Objectives(questID, index)
  local out = {}
  if C_QuestLog and C_QuestLog.GetQuestObjectives then
    local ok, objs = pcall(C_QuestLog.GetQuestObjectives, questID)
    if ok and objs then
      for _, o in ipairs(objs) do
        out[#out + 1] = { text = o.text, done = o.finished and true or false, have = o.numFulfilled, need = o.numRequired }
      end
      return out
    end
  end
  if index and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
    for j = 1, (GetNumQuestLeaderBoards(index) or 0) do
      local text, _, finished = GetQuestLogLeaderBoard(j, index)
      out[#out + 1] = { text = text, done = finished and true or false }
    end
  end
  return out
end

function API.LogQuests()
  local out, order = {}, {}
  local n = 0
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
    n = C_QuestLog.GetNumQuestLogEntries() or 0
  elseif GetNumQuestLogEntries then
    n = GetNumQuestLogEntries() or 0
  end
  for i = 1, n do
    local title, level, isHeader, flag, questID
    if C_QuestLog and C_QuestLog.GetInfo then
      local info = C_QuestLog.GetInfo(i)
      if info then title, level, isHeader, questID = info.title, info.level, info.isHeader, info.questID end
    elseif GetQuestLogTitle then
      local t, l, _, h, _, c, _, id = GetQuestLogTitle(i)
      title, level, isHeader, flag, questID = t, l, h, c, id
    end
    if title and not isHeader and questID and questID > 0 then
      local e = { id = questID, title = title, level = level, index = i, complete = isComplete(questID, flag) }
      e.objectives = API.Objectives(questID, i)
      out[questID] = e
      order[#order + 1] = e
    end
  end
  return out, order
end

function API.ItemCount(itemID)
  local f = (C_Item and C_Item.GetItemCount) or GetItemCount
  if not f then return 0 end
  local ok, n = pcall(f, itemID)
  return ok and n or 0
end

function API.ItemIcon(itemID, fallback)
  local f = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
  if f then
    local ok, icon = pcall(f, itemID)
    if ok and icon then return icon end
  end
  return fallback
end

function API.MapID()
  if C_Map and C_Map.GetBestMapForUnit then
    local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
    if ok then return m end
  end
end

function API.BindStop()
  local where = GetBindLocation and GetBindLocation() or ""
  if where:find("Stormwind") then return "SW", where end
  if where:find("Ironforge") then return "IF", where end
  return nil, where
end

function API.KnowsRiding()
  local known = IsPlayerSpell or IsSpellKnown
  if not known then return false end
  for _, id in ipairs({ 33388, 33391, 34090 }) do
    local ok, v = pcall(known, id)
    if ok and v then return true end
  end
  return false
end

function API.HasWellRested()
  if AuraUtil and AuraUtil.FindAuraByName then
    local ok, name = pcall(AuraUtil.FindAuraByName, "Well Rested", "player", "HELPFUL")
    if ok and name then return true end
  end
  return false
end

function API.SetWaypoint(m, x, y, title)
  if not (m and x and y) then return false end
  if TomTom and TomTom.AddWaypoint then
    TomTom:AddWaypoint(m, x / 100, y / 100, { title = title, from = "QuestBank" })
    return true
  end
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    local okCan = not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(m)
    if okCan then
      local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(m, x / 100, y / 100))
      if ok then
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
          pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        end
        QB:Print(string.format("Map pin set: %s (%.1f, %.1f).", title or "", x, y))
        return true
      end
    end
  end
  QB:Print(string.format("%s is at %.1f, %.1f.", title or "Target", x, y))
  return false
end

----------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------
function QB:Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffc6af8dQuestBank|r " .. msg)
  else
    print("QuestBank " .. msg)
  end
end

function QB.Comma(n)
  local s = tostring(math.floor((n or 0) + 0.5))
  local k
  repeat s, k = s:gsub("^(%-?%d+)(%d%d%d)", "%1,%2") until k == 0
  return s
end

function QB.Short(n)
  n = n or 0
  if n >= 1000 then return string.format("%.1fk", n / 1000):gsub("%.0k", "k") end
  return tostring(n)
end

----------------------------------------------------------------------------
-- settings
----------------------------------------------------------------------------
local DEFAULTS = {
  mounted = "auto", bag = "auto", barrens = true, bind = "auto", goal = "hour",
  routeMode = "now", tab = 1, plan = {}, minimap = { angle = 205, hide = false },
}

function QB:Settings()
  QuestBankDB = QuestBankDB or {}
  local db = QuestBankDB
  -- 1.0 stored snapshots at the top level; move them under chars.
  db.chars = db.chars or {}
  for k, v in pairs(db) do
    if type(v) == "table" and v.completed and k ~= "chars" then db.chars[k] = v; db[k] = nil end
  end
  db.settings = db.settings or {}
  for k, v in pairs(DEFAULTS) do
    if db.settings[k] == nil then
      if type(v) == "table" then
        local c = {}
        for kk, vv in pairs(v) do c[kk] = vv end
        db.settings[k] = c
      else
        db.settings[k] = v
      end
    end
  end
  db.turnins = db.turnins or {}
  return db.settings
end

function QB:Mounted()
  local s = self:Settings().mounted
  if s == "auto" then return API.KnowsRiding(), true end
  return s == true, false
end

function QB:BagBonus()
  local s = self:Settings().bag
  if s == "auto" then return API.HasWellRested(), true end
  return s == true, false
end

function QB:Bind()
  local s = self:Settings().bind
  local found, where = API.BindStop()
  if s == "auto" then return found or "SW", true, where end
  return s, false, where
end

function QB:IsPlanned(q)
  local v = self:Settings().plan[q.id]
  if v == nil then return q.on end
  return v
end

----------------------------------------------------------------------------
-- state
----------------------------------------------------------------------------
QB.state = { level = 1, xp = 0, log = {}, logOrder = {} }

function QB:ReadState()
  local s = self.state
  s.level = UnitLevel("player") or 1
  s.xp = UnitXP("player") or 0
  s.xpMax = UnitXPMax("player") or 1
  s.log, s.logOrder = API.LogQuests()
  s.logCount = #s.logOrder
  s.mapID = API.MapID()
  local _, class = UnitClass("player")
  s.class = class
  s.name = UnitName("player")
  return s
end

local function progressText(entry)
  local parts = {}
  for _, o in ipairs(entry.objectives or {}) do
    if not o.done then
      if o.have and o.need and o.need > 0 then
        parts[#parts + 1] = o.have .. "/" .. o.need
      elseif o.text then
        parts[#parts + 1] = o.text
      end
    end
  end
  if #parts == 0 then return "In your log" end
  return "In your log: " .. table.concat(parts, ", ")
end

-- code: done | banked | active | partial | locked | prereq | todo | follow
function QB:Status(q)
  local s = self.state
  if q.follow then
    if API.IsDone(q.id) then return { code = "done", text = "Turned in already" } end
    return { code = "follow", text = "Given on the day by the quest before it" }
  end
  if API.IsDone(q.id) then return { code = "done", text = "Turned in already" } end
  local e = s.log[q.id]
  if e then
    if e.complete then return { code = "banked", text = "Banked, ready to hand in" } end
    return { code = "active", text = progressText(e) }
  end
  if q.bagItem and not q.bagIsTool then
    local n = API.ItemCount(q.bagItem)
    if n >= (q.bagNeed or 1) then return { code = "banked", text = "Banked in your bags", bag = true } end
    if n > 0 then return { code = "partial", text = n .. "/" .. q.bagNeed .. " in your bags" } end
  end
  if s.level < (q.req or 1) then return { code = "locked", text = "Needs level " .. q.req } end
  if q.pre then
    for _, p in ipairs(q.pre) do
      if not API.IsDone(p) then
        local name = D.QUEST_NAMES[p] or ("quest " .. p)
        if s.log[p] then return { code = "prereq", text = "Hand in " .. name .. " first", pre = p } end
        return { code = "prereq", text = "First: " .. name, pre = p }
      end
    end
  end
  return { code = "todo", text = "Not started" }
end

----------------------------------------------------------------------------
-- plans: the route with what is banked now, and with the whole plan
----------------------------------------------------------------------------
function QB:RouteQuests(mode)
  local list, included = {}, {}
  for _, q in ipairs(D.QUESTS) do
    if not q.follow then
      local st = self:Status(q)
      local want
      if mode == "plan" then
        want = self:IsPlanned(q) and st.code ~= "done"
      else
        want = st.code == "banked"
      end
      if want then list[#list + 1] = { q = q, st = st }; included[q.id] = true end
    end
  end
  for _, q in ipairs(D.QUESTS) do
    if q.follow and included[q.follow] and not API.IsDone(q.id) then
      list[#list + 1] = { q = q, st = { code = "follow", text = "Given on the day" } }
    end
  end
  return list
end

-- The planner only runs again when something it depends on changed.
local function signature(list, opts)
  local parts = { opts.level, opts.xp, tostring(opts.mounted), tostring(opts.bonus), opts.goal }
  for _, e in ipairs(list) do parts[#parts + 1] = e.q.id end
  return table.concat(parts, ":")
end

function QB:Recompute()
  self:ReadState()
  local set = self:Settings()
  local opts = {
    level = self.state.level, xp = self.state.xp, mounted = (self:Mounted()), bonus = (self:BagBonus()), goal = set.goal,
  }
  local now, plan = self:RouteQuests("now"), self:RouteQuests("plan")
  local sigNow, sigPlan = signature(now, opts), signature(plan, opts)
  if sigNow ~= self.sigNow or not self.routeNow then self.routeNow = QB.Model.Build(now, opts); self.sigNow = sigNow end
  if sigPlan ~= self.sigPlan or not self.routePlan then self.routePlan = QB.Model.Build(plan, opts); self.sigPlan = sigPlan end
  self.dirty = false
  return self.routeNow, self.routePlan
end

-- XP a quest in your log is worth on the day
function QB:LogValue(questID)
  for _, r in ipairs({ self.routePlan, self.routeNow }) do
    if r and r.byQuest and r.byQuest[questID] then return r.byQuest[questID], true end
  end
  local c = D.XP[questID]
  if not c then return nil end
  local lvl = self.routePlan and math.floor(self.routePlan.level) or self.state.level
  return QB.Model.XpAt(c[2], c[3] or 1, c[1], lvl), false
end

function QB:QuestByID(id)
  if not self.byID then
    self.byID = {}
    for _, q in ipairs(D.QUESTS) do self.byID[q.id] = q end
  end
  return self.byID[id]
end

----------------------------------------------------------------------------
-- export: the file Claude reads to check progress
----------------------------------------------------------------------------
local function completedIDs()
  local out = {}
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    local ids = C_QuestLog.GetAllCompletedQuestIDs()
    if ids then for i = 1, #ids do out[#out + 1] = ids[i] end end
  end
  if #out == 0 and GetQuestsCompleted then
    local t = GetQuestsCompleted()
    if t then for id in pairs(t) do out[#out + 1] = id end end
  end
  table.sort(out)
  return out
end

local function bagItems()
  local found = {}
  local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local itemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
  local itemLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
  local itemInfo = C_Container and C_Container.GetContainerItemInfo
  if not (numSlots and itemID) then return {} end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (numSlots(bag) or 0) do
      local id = itemID(bag, slot)
      if id then
        local count = 1
        if itemInfo then
          local info = itemInfo(bag, slot)
          if info and info.stackCount then count = info.stackCount end
        elseif GetContainerItemInfo then
          local _, c = GetContainerItemInfo(bag, slot)
          count = c or 1
        end
        local link = itemLink and itemLink(bag, slot)
        local e = found[id]
        if not e then
          e = { id = id, name = link and link:match("%[(.-)%]") or nil, count = 0 }
          found[id] = e
        end
        e.count = e.count + count
      end
    end
  end
  local list = {}
  for _, e in pairs(found) do list[#list + 1] = e end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

function QB:Snapshot(reason)
  local s = self:ReadState()
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "?"
  local _, race = UnitRace("player")
  local log = {}
  for _, e in ipairs(s.logOrder) do
    log[#log + 1] = { id = e.id, title = e.title, level = e.level, complete = e.complete, objectives = e.objectives }
  end
  local done = completedIDs()
  QuestBankDB.chars[(s.name or "?") .. "-" .. realm] = {
    saved = date("%Y-%m-%d %H:%M"), reason = reason, version = QB.version,
    level = s.level, xp = s.xp, xpMax = s.xpMax, class = s.class, race = race,
    faction = UnitFactionGroup("player"), completed = done, log = log, bags = bagItems(),
  }
  return #done, #log
end

----------------------------------------------------------------------------
-- events
----------------------------------------------------------------------------
local frame = CreateFrame("Frame")
QB.eventFrame = frame
local pending = false

function QB:MarkDirty()
  self.dirty = true
  if pending then return end
  if QB.UI and QB.UI.frame and QB.UI.frame:IsShown() then
    pending = true
    C_Timer.After(0.3, function()
      pending = false
      if QB.UI.frame:IsShown() then QB.UI:Refresh() end
    end)
  end
end

local function onTurnIn(questID, xpReward)
  local q = QB:QuestByID(questID)
  if not q then return end
  local predicted = QB.routeNow and QB.routeNow.byQuest and QB.routeNow.byQuest[questID]
  table.insert(QuestBankDB.turnins, {
    id = questID, xp = xpReward, predicted = predicted, level = UnitLevel("player"), at = date("%Y-%m-%d %H:%M:%S"),
  })
  local msg = string.format("%s: +%s XP", q.name, QB.Comma(xpReward or 0))
  if predicted and xpReward and predicted ~= xpReward then
    msg = msg .. string.format(" (plan said %s)", QB.Comma(predicted))
  end
  QB:Print(msg)
end

frame:SetScript("OnEvent", function(_, event, a1, a2)
  if event == "ADDON_LOADED" then
    if a1 == ADDON then
      D = QB.Data
      QB:Settings()
    end
    return
  elseif event == "PLAYER_LOGIN" then
    QB:ReadState()
    if QB.Minimap then QB.Minimap:Create() end
    C_Timer.After(8, function() QB:Snapshot("login") end)
    return
  elseif event == "PLAYER_LOGOUT" then
    QB:Snapshot("logout")
    return
  elseif event == "QUEST_TURNED_IN" then
    onTurnIn(a1, a2)
  elseif event == "UNIT_AURA" and a1 ~= "player" then
    return
  end
  QB:MarkDirty()
end)

for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN",
  "QUEST_ACCEPTED", "QUEST_REMOVED", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE",
  "ZONE_CHANGED_NEW_AREA", "UNIT_AURA", "HEARTHSTONE_BOUND" }) do
  pcall(frame.RegisterEvent, frame, e)
end

----------------------------------------------------------------------------
-- slash
----------------------------------------------------------------------------
SLASH_QUESTBANK1 = "/questbank"
SLASH_QUESTBANK2 = "/qb"
SlashCmdList.QUESTBANK = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "export" then
    local done, inLog = QB:Snapshot("manual")
    QB:Print(done .. " completed quests and " .. inLog .. " in your log saved. Type /reload to write the file.")
  elseif msg == "reset" then
    QB:Settings().pos = nil
    if QB.UI.frame then QB.UI.frame:ClearAllPoints(); QB.UI.frame:SetPoint("CENTER") end
  elseif msg == "minimap" then
    local m = QB:Settings().minimap
    m.hide = not m.hide
    if QB.Minimap then QB.Minimap:Update() end
  elseif msg == "route" then
    QB.UI:Open(3)
  elseif msg == "prep" then
    QB.UI:Open(2)
  else
    QB.UI:Toggle()
  end
end
