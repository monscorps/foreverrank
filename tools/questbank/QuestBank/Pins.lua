-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank map pins: a numbered pin on the world map for every stop on the route, a ! where a
-- quest you plan to fetch starts, and a waypoint that moves on to the next stop as you hand in.
local _, QB = ...
local P = { list = {} }
QB.Pins = P

-- the pin template in Pins.xml mixes QuestBankPinMixin in when a pin is made; it is rebuilt on top of
-- the map's own pin mixin once the world map is loaded
local Pin = {}
QuestBankPinMixin = Pin

function Pin:OnLoad()
  if self.UseFrameLevelType then self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI") end
  if self.SetScalingLimits then self:SetScalingLimits(1, 1.0, 1.25) end
end

function Pin:OnAcquired(data, x, y)
  self.data = data
  self:SetPosition(x, y)
  self.Icon:SetTexture(data.icon)
  self.Icon:SetDesaturated(data.late or false)
  self.Num:SetText(data.num and tostring(data.num) or "")
end

function Pin:OnMouseEnter()
  local d = self.data
  if not d then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine((d.num and (d.num .. ". ") or "") .. d.name, 1, 0.82, 0)
  if d.when then GameTooltip:AddLine(d.when, 0.8, 0.8, 0.8) end
  for _, line in ipairs(d.lines or {}) do GameTooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 0.6, 1, 0.6) end
  GameTooltip:AddLine("Click: waypoint here.", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

function Pin:OnMouseLeave() GameTooltip:Hide() end

function Pin:OnMouseClickAction()
  local d = self.data
  if d then QB.API.SetWaypoint(d.m, d.x, d.y, d.name) end
end

function Pin:OnClickHandler()
  self:OnMouseClickAction()
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
  if self.provider then return end
  if not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin and MapCanvasPinMixin and CreateFromMixins) then
    -- the world map can load after us: try again when it does
    if not self.waiting and CreateFrame then
      self.waiting = CreateFrame("Frame")
      self.waiting:SetScript("OnEvent", function(_, _, name) if name == "Blizzard_WorldMap" or name == "Blizzard_MapCanvas" then P:Init() end end)
      self.waiting:RegisterEvent("ADDON_LOADED")
    end
    return
  end
  if self.waiting then self.waiting:UnregisterEvent("ADDON_LOADED") end
  QuestBankPinMixin = CreateFromMixins(MapCanvasPinMixin, Pin)
  local provider = CreateFromMixins(MapCanvasDataProviderMixin)
  function provider:RemoveAllData() self:GetMap():RemoveAllPinsByTemplate("QuestBankPinTemplate") end
  function provider:RefreshAllData()
    self:RemoveAllData()
    if not QB:Settings().pins then return end
    local map = self:GetMap()
    local shown = map:GetMapID()
    if not shown then return end
    for _, d in ipairs(P.list) do
      local x, y = project(d, shown)
      if x then map:AcquirePin("QuestBankPinTemplate", d, x, y) end
    end
  end
  function provider:OnMapChanged() self:RefreshAllData() end
  WorldMapFrame:AddDataProvider(provider)
  self.provider = provider
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
        local lines = {}
        for _, row in ipairs(leg.rows) do lines[#lines + 1] = { row.q.name, QB.Comma(row.xp) } end
        list[#list + 1] = { m = s.m, x = s.x, y = s.y, num = i, name = s.name, icon = T.questActive, late = leg.late,
                            when = string.format("At %s, level %.1f to %.1f", QB.Clock(leg.t), leg.arrive, leg.leave), lines = lines }
      end
    end
  end
  -- where the quests you plan to fetch start
  local givers = {}
  for id in pairs(QB:Plan().add) do
    local q = QB.Quest.Get(id)
    if q and q.give and not q.give.inside and q.give.m > 0 and not QB.state.log[id] then
      local st = QB:Status(q)
      if st.code == "todo" or st.code == "prereq" then
        local key = q.give.n .. q.give.m
        local g = givers[key]
        if not g then
          g = { m = q.give.m, x = q.give.x, y = q.give.y, name = q.give.n, icon = T.questAvail, when = "Pick up", lines = {} }
          givers[key] = g
          list[#list + 1] = g
        end
        g.lines[#g.lines + 1] = { q.name, st.code == "prereq" and "chain first" or QB.Comma(QB.Model.XpAt(q, math.max(QB.state.level, 20))) }
      end
    end
  end
  self.list = list
  return list
end

function P:Update()
  self:Build()
  if self.provider and WorldMapFrame:IsShown() then self.provider:RefreshAllData() end
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
  QB.API.SetWaypoint(s.m, s.x, s.y, s.name, not announce)
end

function P:Toggle()
  local set = QB:Settings()
  set.pins = not set.pins
  QB:Print(set.pins and "Map pins on." or "Map pins off.")
  self:Update()
end
