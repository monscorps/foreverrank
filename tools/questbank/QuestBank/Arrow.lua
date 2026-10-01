-- SPDX-License-Identifier: GPL-3.0-or-later
-- The direction arrow (opt-in, Settings or /qb arrow): points from where you stand and the way you
-- face to a target, with its name and how far it is. What it points at is yours to choose: right-click
-- it, or /qb arrow route|handin|pickup|pin.
--   route    the next stop on your route, as it re-plans (questing and mid-run, from where you stand;
--            banking, the one you'll run)
--   handin   the nearest NPC you can hand a finished quest in to
--   pickup   the nearest giver of a quest in your plan you haven't taken yet (a chain: its first step)
--   pin      whatever you last clicked a waypoint for in QuestBank: a quest, a stop, an entrance.
--            Clicking one while the arrow is up switches to this by itself.
local _, QB = ...
local A = {}
QB.Arrow = A

local atan2, sqrt = math.atan2 or function(y, x) return math.atan(y, x) end, math.sqrt
local MODES = { route = "the next stop on your route", handin = "the nearest hand-in", pickup = "the nearest pick-up", pin = "where you last clicked" }
local ORDER = { "route", "handin", "pickup", "pin" }
A.MODES = MODES

function A.Mode()
  local m = QB:Settings().arrowMode
  return MODES[m] and m or "route"
end

-- the nearest of several places; another continent counts as far
local function nearest(list)
  local here = QB.API.WorldPosition()
  local best, bd
  for _, t in ipairs(list) do
    local d = 1e9
    if here and here.c == t.c then local dn, dw = here.wx - t.wx, here.wy - t.wy; d = sqrt(dn * dn + dw * dw) end
    if not best or d < bd then best, bd = t, d end
  end
  return best
end

local function routeTarget()
  local set = QB:Settings()
  local r = QB.routeNow
  if QB:Banking() and not (QB.Run and QB.Run.Get()) and set.routeMode == "plan" then r = QB.routePlan end
  local leg = r and r.legs and r.legs[1]
  if not leg or not leg.stop then return nil end
  local st = leg.stop
  return { name = st.name, c = st.c, wx = st.wx, wy = st.wy, quests = #(leg.rows or {}), what = "to hand in there", kind = "route" }
end

-- finished quests in your log, by the NPC who takes them, outside dungeons
local function handinTarget()
  local Q, M = QB.Quest, QB.Model
  local byNpc, list = {}, {}
  for _, e in ipairs(QB.state.logOrder or {}) do
    if e.complete then
      local q = Q.Get(e.id)
      local p = q and q.turn and not q.turn.inside and M.NpcPlace(q.turnIdx, QB.faction)
      if p then
        local t = byNpc[q.turnIdx]
        if not t then
          t = { name = q.turn.n, c = p.c, wx = p.wx, wy = p.wy, quests = 0, what = "to hand in there", kind = "handin" }
          byNpc[q.turnIdx] = t
          list[#list + 1] = t
        end
        t.quests = t.quests + 1
      end
    end
  end
  return nearest(list)
end

-- the first step of a chain, or the quest itself
local function firstStep(q, st)
  if st.code == "prereq" and st.pre then
    local p = type(st.pre) == "table" and st.pre[1] or st.pre
    return QB.Quest.Get(p) or q
  end
  return q
end
A.FirstStep = firstStep

-- quests in your plan you haven't taken yet, by the NPC who gives them (or gives their first step)
local function pickupTarget()
  local Q, M = QB.Quest, QB.Model
  local byNpc, list = {}, {}
  for id in pairs(QB:Plan().add) do
    local q = Q.Get(id)
    if q and not QB.state.log[id] and not QB.API.IsDone(id) then
      local st = QB:Status(q)
      if st.code == "todo" or st.code == "prereq" then
        local g = firstStep(q, st)
        local p = g.give and not g.give.inside and M.NpcPlace(g.giveIdx, QB.faction)
        if p then
          local t = byNpc[g.giveIdx]
          if not t then
            t = { name = g.give.n, c = p.c, wx = p.wx, wy = p.wy, quests = 0, what = "to pick up there", kind = "pickup" }
            byNpc[g.giveIdx] = t
            list[#list + 1] = t
          end
          t.quests = t.quests + 1
        end
      end
    end
  end
  return nearest(list)
end

-- what the arrow points at
function A.Target()
  local m = A.Mode()
  if m == "pin" then
    local p = QB:Settings().arrowPin
    if p and p.c and p.wx and p.wy then return { name = p.name or "your waypoint", c = p.c, wx = p.wx, wy = p.wy, kind = "pin" } end
    return nil
  elseif m == "handin" then return handinTarget()
  elseif m == "pickup" then return pickupTarget()
  end
  return routeTarget()
end

local NOTHING = { route = { "No stop to go to", nil }, handin = { "Nothing finished to hand in", "Finish a quest and the arrow finds its NPC" },
                  pickup = { "Nothing in your plan to pick up", "Add quests on the Plan page" }, pin = { "Nothing chosen yet", "Click a quest or a stop in QuestBank" } }
local HEAD = { route = "Next stop: %s", handin = "Hand in at %s", pickup = "Pick up at %s", pin = "You chose: %s" }

-- world x runs north and world y west; facing counts anticlockwise from north, as SetRotation turns
function A.Bearing(me, t, facing)
  local dn, dw = t.wx - me.wx, t.wy - me.wy
  return atan2(dw, dn) - (facing or 0), sqrt(dn * dn + dw * dw)
end

local function distanceText(yards)
  if yards >= 1000 then return string.format("%.1fk yards", yards / 1000) end
  return string.format("%d yards", math.floor(yards / 5 + 0.5) * 5)
end

-- what you clicked a waypoint for in QuestBank: remembered, and pointed at while the arrow is up
function A:Pin(name, c, wx, wy)
  if not (c and wx and wy) then return end
  local set = QB:Settings()
  set.arrowPin = { name = name, c = c, wx = wx, wy = wy }
  if set.arrow and A.Mode() ~= "pin" then
    set.arrowMode = "pin"
    if not self.toldPin then
      self.toldPin = true
      QB:Print(string.format("The arrow points at %s now. Right-click it to follow the route again.", name or "your waypoint"))
    end
  end
  self:Update()
end

function A:SetMode(m)
  if not MODES[m] then return end
  QB:Settings().arrowMode = m
  self:Update()
end

function A:Menu()
  if not QB.UI then return end
  local items = {}
  for _, m in ipairs(ORDER) do
    local label = (MODES[m]:gsub("^%l", string.upper))
    if A.Mode() == m then label = label .. "  (now)" end
    if m == "pin" and not QB:Settings().arrowPin then label = label .. " (nothing yet)" end
    items[#items + 1] = { label, function() A:SetMode(m) end }
  end
  items[#items + 1] = { "Hide the arrow", function()
    A:Set(false)
    QB:Print("Direction arrow off. Settings or /qb arrow brings it back.")
  end }
  QB.UI:ShowMenu("The arrow points at", items)
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
    if which == "RightButton" then A:Menu()
    elseif QB.UI then QB.UI:Open(3) end
  end, "arrow click"))
  f:SetScript("OnEnter", QB.Safe(function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    local t, m = A.Target(), A.Mode()
    GameTooltip:AddLine(t and string.format(HEAD[t.kind] or "%s", t.name) or NOTHING[m][1], 1, 0.82, 0)
    if t and t.quests then GameTooltip:AddLine(string.format("%d quest%s %s.", t.quests, t.quests == 1 and "" or "s", t.what or ""), 1, 1, 1) end
    GameTooltip:AddLine("Pointing at " .. MODES[m] .. ".", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Click: the Hand-in Route. Drag: move. Right-click: choose what it points at, or hide it.", 0.6, 0.6, 0.6, true)
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
    local m = A.Mode()
    f.name:SetText(NOTHING[m][1])
    f.dist:SetText(NOTHING[m][2] or (QB:Banking() and "Nothing banked yet" or "Nothing ready to hand in"))
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
