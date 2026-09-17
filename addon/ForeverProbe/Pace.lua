--[[ The one quality-of-life piece: a quiet pace bar.
     Level, percent, XP per hour, time to level. Drag it anywhere,
     right-click to hide, /probe bar to bring it back.                ]]

local ADDON, NS = ...

local bar = CreateFrame("Frame", "ForeverProbeBar", UIParent, "BackdropTemplate")
bar:SetSize(230, 18)
bar:SetFrameStrata("MEDIUM")
bar:SetMovable(true)
bar:EnableMouse(true)
bar:RegisterForDrag("LeftButton")
bar:SetClampedToScreen(true)
if bar.SetBackdrop then
  bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  bar:SetBackdropColor(0.03, 0.06, 0.12, 0.92)
  bar:SetBackdropBorderColor(0.9, 0.8, 0.5, 0.35)
end

local fill = bar:CreateTexture(nil, "BORDER")
fill:SetPoint("TOPLEFT", 1, -1)
fill:SetPoint("BOTTOMLEFT", 1, 1)
fill:SetColorTexture(0.9, 0.8, 0.5, 0.14)

local text = bar:CreateFontString(nil, "OVERLAY")
text:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
text:SetPoint("CENTER")
text:SetTextColor(0.94, 0.9, 0.78)

bar:SetScript("OnDragStart", bar.StartMoving)
bar:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local p, _, rp, x, y = self:GetPoint()
  NS.db().pace.pos = { p, rp, x, y }
end)
bar:SetScript("OnMouseUp", function(self, btn)
  if btn == "RightButton" then NS.db().pace.hidden = true; self:Hide() end
end)

local session = { xp0 = 0, t0 = 0, started = false }

local function fmtTime(sec)
  if not sec or sec ~= sec or sec > 359999 then return "--" end
  local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60)
  if h > 0 then return h .. "h " .. m .. "m" end
  return m .. "m"
end

local function short(n)
  if n >= 10000 then return string.format("%.1fk", n / 1000) end
  return tostring(math.floor(n))
end

local function refresh()
  local lvl = UnitLevel("player")
  local xp, xpMax = UnitXP("player"), UnitXPMax("player")
  if not xp or not xpMax or xpMax == 0 then bar:Hide() return end
  local pct = xp / xpMax * 100
  local elapsed = GetTime() - session.t0
  local gained = (lvl > session.lvl0 and xp + (session.maxSeen or 0)) or (xp - session.xp0)
  local perHr = (session.started and elapsed > 60 and gained > 0) and (gained / elapsed * 3600) or 0
  local eta = perHr > 0 and ((xpMax - xp) / perHr * 3600) or nil
  fill:SetWidth(math.max(1, (bar:GetWidth() - 2) * xp / xpMax))
  text:SetText(("Lv %d  %.1f%%  %s XP/h  up in %s"):format(lvl, pct, perHr > 0 and short(perHr) or "--", fmtTime(eta)))
  bar:Show()
end

function NS.paceInit()
  local p = NS.db().pace
  bar:ClearAllPoints()
  if p.pos then bar:SetPoint(p.pos[1], UIParent, p.pos[2], p.pos[3], p.pos[4])
  else bar:SetPoint("TOP", UIParent, "TOP", 0, -4) end
  session.xp0 = UnitXP("player") or 0
  session.lvl0 = UnitLevel("player")
  session.t0 = GetTime()
  session.started = true
  if p.hidden then bar:Hide() else refresh() end
end

function NS.paceToggle()
  local p = NS.db().pace
  p.hidden = not p.hidden
  if p.hidden then bar:Hide() else refresh() end
end

local prev = NS.onEvent
NS.onEvent = function(event, ...)
  if prev then prev(event, ...) end
  if event == "PLAYER_ENTERING_WORLD" then
    C_Timer.After(2, NS.paceInit)
  elseif event == "PLAYER_LEVEL_UP" then
    session.maxSeen = (session.maxSeen or 0) + (UnitXPMax("player") or 0)
    C_Timer.After(1, refresh)
  end
end
NS.events:RegisterEvent("PLAYER_XP_UPDATE")
local old = NS.events:GetScript("OnEvent")
NS.events:SetScript("OnEvent", function(self, event, ...)
  if old then old(self, event, ...) end
  if event == "PLAYER_XP_UPDATE" then refresh() end
end)
