-- ForeverProbe :: Pace display
--
-- One quiet bar fed by the ported LevelPace engine; the depth lives in the
-- hover tooltip. Drag anywhere, right-click hides, /probe bar brings it back.
local ADDON, NS = ...
local util = NS.util

local bar = CreateFrame("Frame", "ForeverProbeBar", UIParent, "BackdropTemplate")
bar:SetSize(250, 18)
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
local rfill = bar:CreateTexture(nil, "BORDER")  -- rested reach, dimmer
rfill:SetPoint("TOPLEFT", fill, "TOPRIGHT")
rfill:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT")
rfill:SetColorTexture(0.4, 0.6, 0.9, 0.12)
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

local function tip()
  local r = NS.Estimator.result or {}
  local rec = NS.History:Current()
  GameTooltip:SetOwner(bar, "ANCHOR_BOTTOM")
  GameTooltip:AddLine("ForeverProbe pace", 0.9, 0.8, 0.5)
  if r.maxLevel then GameTooltip:AddLine("Max level. Well played.", 0.8, 0.8, 0.8) GameTooltip:Show() return end
  if r.baseRatePerHour then
    GameTooltip:AddDoubleLine("Base XP per hour", util.Short(r.baseRatePerHour), 0.8, 0.82, 0.9, 1, 1, 1)
    GameTooltip:AddDoubleLine("Rate from", r.rateSource or "--", 0.8, 0.82, 0.9, 1, 1, 1)
    GameTooltip:AddDoubleLine("Confidence", r.confidence or "--", 0.8, 0.82, 0.9, 1, 1, 1)
  else
    GameTooltip:AddLine("Gathering a rate. Go earn some XP.", 0.8, 0.8, 0.8)
  end
  if r.mobsLow then
    GameTooltip:AddDoubleLine("Mobs to level", r.mobsLow .. " to " .. r.mobsHigh, 0.8, 0.82, 0.9, 1, 1, 1)
  end
  if (r.restedCovered or 0) > 0 then
    GameTooltip:AddDoubleLine("Rested covers", util.Short(r.restedCovered) .. " XP", 0.5, 0.7, 1, 1, 1, 1)
  end
  if rec then
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("This level", util.FormatTime(rec.elapsed), 0.6, 0.62, 0.72, 0.9, 0.9, 0.9)
    GameTooltip:AddDoubleLine("Kills / quests", (rec.killCount or 0) .. " / " .. (rec.questCount or 0), 0.6, 0.62, 0.72, 0.9, 0.9, 0.9)
    if (rec.deaths or 0) > 0 then GameTooltip:AddDoubleLine("Deaths", rec.deaths, 0.6, 0.62, 0.72, 0.9, 0.9, 0.9) end
    if (rec.largestGap or 0) > 600 then
      GameTooltip:AddLine("Includes a " .. util.FormatTime(rec.largestGap) .. " break. Downtime counts.", 0.55, 0.58, 0.68, true)
    end
  end
  GameTooltip:Show()
end
bar:SetScript("OnEnter", tip)
bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function refresh()
  local r = NS.Estimator:Refresh()
  if r.maxLevel then bar:Hide() return end
  local xp, xpMax = UnitXP("player") or 0, UnitXPMax("player") or 1
  local w = bar:GetWidth() - 2
  fill:SetWidth(math.max(1, w * xp / xpMax))
  local reach = math.min((r.restedCovered or 0), xpMax - xp)
  rfill:SetWidth(math.max(0.001, w * reach / xpMax))
  local rate = r.baseRatePerHour and (util.Short(r.baseRatePerHour) .. "/h") or "--"
  local eta = r.timeToLevel and util.FormatTime(r.timeToLevel) or "--"
  local lowMark = (r.confidence ~= "good" and r.baseRatePerHour) and "~" or ""
  text:SetText(("Lv %d  %.1f%%  %s%s  up in %s%s"):format(UnitLevel("player"), r.percent or 0, lowMark, rate, lowMark, eta))
  if not NS.db().pace.hidden then bar:Show() end
end
NS.paceRefresh = refresh

function NS.paceInit()
  local p = NS.db().pace
  bar:ClearAllPoints()
  if p.pos then bar:SetPoint(p.pos[1], UIParent, p.pos[2], p.pos[3], p.pos[4])
  else bar:SetPoint("TOP", UIParent, "TOP", 0, -4) end
  NS.History:Init()
  NS.Ledger:Prime()
  if p.hidden then bar:Hide() else refresh() end
  if not NS.paceTicker then NS.paceTicker = C_Timer.NewTicker(2, refresh) end
end

function NS.paceToggle()
  local p = NS.db().pace
  p.hidden = not p.hidden
  if p.hidden then bar:Hide() else refresh() end
end

-- events, chained onto the Probe frame
NS.events:RegisterEvent("PLAYER_XP_UPDATE")
NS.events:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
NS.events:RegisterEvent("QUEST_TURNED_IN")
NS.events:RegisterEvent("PLAYER_DEAD")
local prev = NS.onEvent
NS.onEvent = function(event, a1, a2)
  if prev then prev(event, a1, a2) end
  if event == "PLAYER_ENTERING_WORLD" then
    C_Timer.After(2, NS.paceInit)
  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
    NS.Ledger:OnChatXP(a1)
  elseif event == "QUEST_TURNED_IN" then
    NS.Ledger:OnQuestTurnIn(a1, a2)
  elseif event == "PLAYER_XP_UPDATE" then
    NS.Ledger:OnXPUpdate()
    refresh()
  elseif event == "PLAYER_LEVEL_UP" then
    NS.History:OnLevelUp(a1)
    C_Timer.After(1, refresh)
  elseif event == "PLAYER_DEAD" then
    NS.History:OnDeath()
  end
end
