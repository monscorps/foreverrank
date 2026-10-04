-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank map pins: a numbered pin on the world map for every stop on the route, a ! where a
-- quest you plan to fetch starts, and a waypoint that moves on to the next stop as you hand in.
local _, QB = ...
local P = { list = {} }
QB.Pins = P

----------------------------------------------------------------------------
-- what every QuestBank layer on the world map shares (this one and the quest icons, QuestMap.lua)
----------------------------------------------------------------------------
-- Combat: the map canvas calls SetPassThroughButtons on every pin it hands out (AcquirePin), and on Forever that is
-- a protected function that can't run in combat; an addon pin acquired in combat raises ADDON_ACTION_BLOCKED, which
-- no pcall catches (HereBeDragons-Pins stubs it for the same reason). So QuestBank's pins make that call only out of
-- combat (right-click then passes through to zoom the map out, as on Blizzard's pins), never acquire or release a pin
-- in combat, and redraw when combat ends.
local function inCombat() return InCombatLockdown and InCombatLockdown() and true or false end
P.InCombat = inCombat

-- the frame's own SetPassThroughButtons, under the one each QuestBank pin mixin puts on top
local function framePassThrough(self, ...)
  local mt = getmetatable(self)
  local index = mt and mt.__index
  local f
  if type(index) == "table" then f = index.SetPassThroughButtons
  elseif type(index) == "function" then f = index(self, "SetPassThroughButtons") end
  if f then f(self, ...) end
end
function P.PassThrough(self, ...)
  if inCombat() then return end
  framePassThrough(self, ...)
end

-- providers that asked for a redraw in combat: they get it when combat ends, if the map is still open (opening it
-- later redraws anyway)
local afterCombat = {}
P.combatFrame = CreateFrame and CreateFrame("Frame")
if P.combatFrame then
  P.combatFrame:SetScript("OnEvent", QB.Safe(function()
    local list = {}
    for provider in pairs(afterCombat) do list[#list + 1] = provider end
    afterCombat = {}
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
    for _, provider in ipairs(list) do provider:RefreshAllData() end
  end, "map pins: after combat"))
  P.combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- run fn once Blizzard's world map is loaded: now, or when it loads after us
local function mapReady()
  return WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin and MapCanvasPinMixin and CreateFromMixins and true or false
end
function P.WhenMap(fn, where)
  if mapReady() then fn() return end
  if not CreateFrame then return end
  local wait = CreateFrame("Frame")
  wait:SetScript("OnEvent", QB.Safe(function(self, _, name)
    if (name == "Blizzard_WorldMap" or name == "Blizzard_MapCanvas") and mapReady() then
      self:UnregisterEvent("ADDON_LOADED")
      fn()
    end
  end, where))
  wait:RegisterEvent("ADDON_LOADED")
  return wait
end

-- a data provider on the world map for the pins of these templates: draw(map, mapID) acquires them, after every pin
-- of the templates has gone. Whatever goes wrong in it stays in it: the map runs every provider in one loop.
function P.NewProvider(templates, draw, where)
  local provider = CreateFromMixins(MapCanvasDataProviderMixin)
  function provider:RemoveAllData()
    local map = self:GetMap()
    for _, t in ipairs(templates) do map:RemoveAllPinsByTemplate(t) end
  end
  provider.RefreshAllData = QB.Safe(function(self)
    local map = self:GetMap()
    if not map then return end
    local shown = map:GetMapID()
    if inCombat() then
      -- nothing acquired or released now: pins drawn for another map hide until the redraw after combat
      if map.EnumeratePinsByTemplate then
        for _, t in ipairs(templates) do
          for pin in map:EnumeratePinsByTemplate(t) do pin:SetShown(shown == self.drawnFor) end
        end
      end
      afterCombat[self] = true
      return
    end
    afterCombat[self] = nil
    self:RemoveAllData()
    self.drawnFor = shown
    if shown then draw(map, shown) end
  end, where)
  function provider:OnMapChanged() self:RefreshAllData() end
  WorldMapFrame:AddDataProvider(provider)
  return provider
end

----------------------------------------------------------------------------
-- the route's pins
----------------------------------------------------------------------------
-- the pin template in Pins.xml mixes QuestBankPinMixin in when a pin is made; it is rebuilt on top of
-- the map's own pin mixin once the world map is loaded
local Pin = {}
QuestBankPinMixin = Pin
Pin.SetPassThroughButtons = P.PassThrough

function Pin:OnLoad()
  if self.UseFrameLevelType then self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI") end
  if self.SetScalingLimits then self:SetScalingLimits(1, 1.0, 1.25) end
end

Pin.OnAcquired = QB.Safe(function(self, data, x, y)
  self.data = data
  self:SetPosition(x, y)
  self.Icon:SetTexture(data.icon)
  self.Icon:SetDesaturated(data.late or false)
  self.Num:SetText(data.num and tostring(data.num) or "")
end, "map pin")

Pin.OnMouseEnter = QB.Safe(function(self)
  local d = self.data
  if not d then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine((d.num and (d.num .. ". ") or "") .. d.name, 1, 0.82, 0)
  if d.when then GameTooltip:AddLine(d.when, 0.8, 0.8, 0.8) end
  for _, line in ipairs(d.lines or {}) do GameTooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 0.6, 1, 0.6) end
  -- the quest icons leave the NPC under this pin to it: what they would have shown there
  if QB.QuestMap and QB.QuestMap.AlsoHere then
    local map = self.GetMap and self:GetMap()
    QB.QuestMap.AlsoHere(GameTooltip, d, map and map:GetMapID())
  end
  GameTooltip:AddLine("Click: waypoint here.", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end, "map pin tooltip")

function Pin:OnMouseLeave() GameTooltip:Hide() end

-- the map canvas calls this on a click (it owns the pin's mouse scripts)
function Pin:OnMouseClickAction(button)
  local d = self.data
  if d and button ~= "RightButton" then QB.API.SetWaypoint(d.m, d.x, d.y, d.name) end
end

-- a point on one map, placed on another (a city on its continent, a zone on the world map)
local function project(d, mapID)
  if d.m == mapID then return d.x / 100, d.y / 100 end
  if not (C_Map and C_Map.GetMapRectOnMap) then return nil end
  local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, d.m, mapID)
  if not ok or not minX or maxX == minX then return nil end
  local x, y = minX + d.x / 100 * (maxX - minX), minY + d.y / 100 * (maxY - minY)
  if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  return x, y
end

function P:Init()
  if self.provider or self.waiting then return end
  self.waiting = P.WhenMap(function()
    if P.provider then return end
    QuestBankPinMixin = CreateFromMixins(MapCanvasPinMixin, Pin)
    P.provider = P.NewProvider({ "QuestBankPinTemplate" }, function(map, shown)
      if not QB:Settings().pins then return end
      for _, d in ipairs(P.list) do
        local x, y = project(d, shown)
        if x then map:AcquirePin("QuestBankPinTemplate", d, x, y) end
      end
    end, "map pins")
  end, "map pins: waiting for the map")
end

-- the route on screen: the run's rest, or what is banked now, else the full plan
function P:Route()
  local now, plan = QB.routeNow, QB.routePlan
  if QB.Run.Get() or (now and now.legs and #now.legs > 0) then return now end
  return plan
end

function P:Build()
  local list = {}
  local T = QB.Data.TEX
  local r = self:Route()
  if r and r.legs then
    for i, leg in ipairs(r.legs) do
      local s = leg.stop
      if s.m and s.m > 0 then
        local lines, ids = {}, {}
        for _, row in ipairs(leg.rows) do
          lines[#lines + 1] = { row.q.name, QB.Comma(row.xp) }
          ids[row.q.id] = true
        end
        -- who: the NPC the pin stands on (a stop stands at its first NPC, and may be named for its town or place);
        -- ids: the quests it lists. The quest icons (QuestMap.lua) read both
        local first = s.npcs and s.npcs[1] and QB.Data.NPC[s.npcs[1]]
        list[#list + 1] = { m = s.m, x = s.x, y = s.y, num = i, name = s.name, who = first and first[1] or nil, ids = ids, icon = T.questActive,
                            late = (leg.late and r.goal == "hour") or nil,
                            when = string.format("At %s, level %.1f to %.1f", QB.Clock(leg.t), leg.arrive, leg.leave), lines = lines }
      end
    end
  end
  -- where the quests you plan to fetch start
  local givers = {}
  for id in pairs(QB:Plan().add) do
    local q = QB.Quest.Get(id)
    if q and not q.repeatable and not QB.state.log[id] then
      local st = QB:Status(q)
      if st.code == "todo" or st.code == "prereq" then
        -- a chain: the first open step's giver, or the held step's hand-in (what the click and the arrow aim at)
        local at, label, step = q.give, nil, q
        if st.code == "prereq" and QB.Arrow and QB.Arrow.FirstStep then
          local first, held = QB.Arrow.FirstStep(q, st)
          if first and first ~= q then
            at, step = held and first.turn or first.give, first
            label = (held and "chain: hand in " or "chain: pick up ") .. first.name
          end
        end
        if at and not at.inside and at.m and at.m > 0 then
          local key = at.n .. at.m
          local g = givers[key]
          if not g then
            g = { m = at.m, x = at.x, y = at.y, name = at.n, who = at.n, ids = {}, icon = T.questAvail, when = "Pick up", lines = {} }
            givers[key] = g
            list[#list + 1] = g
          end
          g.ids[q.id], g.ids[step.id] = true, true
          g.lines[#g.lines + 1] = { q.name, label or (st.code == "prereq" and "chain first" or QB.Comma(QB.Model.XpAt(q, QB.state.level))) }
        end
      end
    end
  end
  self.list = list
  return list
end

function P:Update()
  self:Build()
  if self.provider and WorldMapFrame:IsShown() then self.provider:RefreshAllData() end
  -- then the quest icons, whenever these pins change (a new plan, /qb pins, Settings): they leave the NPCs these
  -- pins stand on to them
  if QB.QuestMap then QB.Try("map icons", QB.QuestMap.Update, QB.QuestMap) end
  -- during a run the waypoint follows the route
  local r = QB.routeNow
  if QB.Run.Get() and QB:Settings().pins and r and r.legs and r.legs[1] then
    local s = r.legs[1].stop
    local key = s.name .. (s.m or 0) .. (s.x or 0) .. (s.y or 0)
    if key ~= self.next then
      self.next = key
      QB.API.SetWaypoint(s.m, s.x, s.y, s.name, true)
    end
  end
end

function P:PinNext(announce)
  local r = self:Route()
  local leg = r and r.legs and r.legs[1]
  if not leg then
    if announce then QB:Print("Nothing on the route yet.") end
    return
  end
  local s = leg.stop
  QB.API.SetWaypoint(s.m, s.x, s.y, s.name, not announce, false) -- the route's own: the arrow stays as it is
end

function P:Toggle()
  local set = QB:Settings()
  set.pins = not set.pins
  QB:Print(set.pins and "Map pins on." or "Map pins off.")
  self:Update()
end
