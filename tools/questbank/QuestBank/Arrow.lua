-- SPDX-License-Identifier: GPL-3.0-or-later
-- The direction arrow (opt-in, Settings or /qb arrow): points from where you stand and the way you
-- face to the next stop on your route, with its name and how far it is. It follows the route as it
-- re-plans: questing and mid-run, the route from where you stand; banking, the one you'll run.
local _, QB = ...
local A = {}
QB.Arrow = A

local atan2, sqrt = math.atan2 or function(y, x) return math.atan(y, x) end, math.sqrt

-- the stop the arrow points at
function A.Target()
  local set = QB:Settings()
  local r = QB.routeNow
  if QB:Banking() and not (QB.Run and QB.Run.Get()) and set.routeMode == "plan" then r = QB.routePlan end
  local leg = r and r.legs and r.legs[1]
  if not leg or not leg.stop then return nil end
  local st = leg.stop
  return { name = st.name, c = st.c, wx = st.wx, wy = st.wy, quests = #(leg.rows or {}) }
end

-- world x runs north and world y west; facing counts anticlockwise from north, as SetRotation turns
function A.Bearing(me, t, facing)
  local dn, dw = t.wx - me.wx, t.wy - me.wy
  return atan2(dw, dn) - (facing or 0), sqrt(dn * dn + dw * dw)
end

local function distanceText(yards)
  if yards >= 1000 then return string.format("%.1fk yards", yards / 1000) end
  return string.format("%d yards", math.floor(yards / 5 + 0.5) * 5)
end

function A:Create()
  if self.frame then return self.frame end
  local T = QB.Data.TEX
  local f = CreateFrame("Button", "QuestBankArrow", UIParent)
  self.frame = f
  f:SetSize(170, 84)
  local pos = QB:Settings().arrowPos
  if pos then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else f:SetPoint("TOP", 0, -170) end
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, _, x, y = self:GetPoint()
    QB:Settings().arrowPos = { p, x, y }
  end)
  f.arrow = f:CreateTexture(nil, "ARTWORK")
  f.arrow:SetTexture(T.questArrow)
  f.arrow:SetSize(40, 40)
  f.arrow:SetPoint("TOP", 0, 0)
  f.name = f:CreateFontString(nil, "OVERLAY")
  f.name:SetFontObject(GameFontNormal)
  f.name:SetPoint("TOP", 0, -42)
  f.name:SetWidth(150)
  f.name:SetWordWrap(false)
  f.dist = f:CreateFontString(nil, "OVERLAY")
  f.dist:SetFontObject(GameFontHighlightSmall)
  f.dist:SetPoint("TOP", 0, -58)
  f.dist:SetWidth(150)
  f.dist:SetWordWrap(false)
  f:SetScript("OnClick", QB.Safe(function(_, which)
    if which == "RightButton" then
      A:Set(false)
      QB:Print("Direction arrow off. Settings or /qb arrow brings it back.")
    elseif QB.UI then
      QB.UI:Open(3)
    end
  end, "arrow click"))
  f:SetScript("OnEnter", QB.Safe(function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    local t = A.Target()
    GameTooltip:AddLine(t and ("Next stop: " .. t.name) or "No stop to go to", 1, 0.82, 0)
    if t then GameTooltip:AddLine(string.format("%d quest%s to hand in there.", t.quests, t.quests == 1 and "" or "s"), 1, 1, 1) end
    GameTooltip:AddLine("Click: the Hand-in Route. Drag: move. Right-click: hide.", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end, "arrow tooltip"))
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local wait = 0
  f:SetScript("OnUpdate", QB.Safe(function(_, elapsed)
    wait = wait - (elapsed or 0)
    if wait > 0 then return end
    wait = 0.05
    A:Update()
  end, "arrow"))
  f:Hide()
  return f
end

function A:Update()
  local f = self.frame
  if not f then return end
  local t = A.Target()
  if not t then
    f.name:SetText("No stop to go to")
    f.dist:SetText(QB:Banking() and "Nothing banked yet" or "Nothing ready to hand in")
    f.arrow:SetAlpha(0.3)
    return
  end
  f.name:SetText(t.name)
  local me = QB.API.WorldPosition()
  if not me then
    f.dist:SetText("")
    f.arrow:SetAlpha(0.3)
    return
  end
  if me.c ~= t.c then
    f.dist:SetText("On the other continent")
    f.arrow:SetRotation(0)
    f.arrow:SetAlpha(0.3)
    return
  end
  local facing = GetPlayerFacing and GetPlayerFacing()
  local angle, yards = A.Bearing(me, t, facing)
  if yards < 15 then
    f.dist:SetText("You're there")
    f.arrow:SetRotation(0)
    f.arrow:SetAlpha(0.5)
    return
  end
  f.dist:SetText(distanceText(yards))
  -- facing is unknown in some places (instances): show the distance, dim the arrow
  f.arrow:SetRotation(facing and angle or 0)
  f.arrow:SetAlpha(facing and 1 or 0.3)
end

function A:Set(on)
  QB:Settings().arrow = on and true or false
  self:Create()
  self.frame:SetShown(on and true or false)
  if on then self:Update() end
end

function A:Init()
  if QB:Settings().arrow then self:Set(true) end
end
