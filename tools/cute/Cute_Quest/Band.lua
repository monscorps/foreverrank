-- SPDX-License-Identifier: GPL-3.0-or-later
-- The step band: what the Guide's band draws while the Quests module is on, read from the engine (Cute.QuestBand).
-- Sets the engine's skin, so the step frame and the arrow the
-- copy draws are flat, in Cute's font and greys (QuestBank's own, while QuestBank is loaded, keep QuestBank's look).
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
if not E then
  -- QuestBank loaded without QuestBankAPI (older than 6.1): no engine. The band says what is needed where the step
  -- would be, and each page draws that one line (QB.NeedPage) or has it as its section (QB.NeedSettings)
  local line = QB.missing or "QuestBank 6.1.0 or newer is needed."
  Cute.QuestBand = { On = function() return false end, Why = function() return line end }
  function QB.NeedPage(ui, scroll, key)
    local K, ROW = ui.COLORS, ui.ROW
    local w = scroll:Width()
    local v = ui:List(key, function(parent) return ui:MakeLine(parent) end)
    v:Set(1, 0, ROW, function(r, _, ly)
      r:SetHeight(ROW); r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -ly); r:SetWidth(w)
      r.bg:SetColorTexture(1, 1, 1, 0); r.bar:Hide(); r.val:Hide(); r.who:Hide(); r.fn, r.tip = nil, nil
      r.name:ClearAllPoints(); r.name:SetPoint("LEFT", 8, 0); r.name:SetWidth(w - 16); r.name:SetJustifyH("LEFT")
      ui.Color(r.name, K.MUTE); ui.FitText(r.name, line, w - 20); r.name:Show()
    end)
    ui.virtual = function() v:Show(ui.scroll.bar:GetValue() or 0, ui.scroll:View()) end
    scroll:SetContentHeight(ROW + 8)
  end
  function QB.NeedSettings(col, title) col:Head(title); col:Note(line) end
  return
end

if not QB.dormant then
  local INK, SOFT, WHITE = { 0.86, 0.86, 0.86 }, { 0.58, 0.58, 0.58 }, { 0.96, 0.96, 0.96 }
  E.Skin = {
    font = Cute.Font(), INK = INK, SOFT = SOFT, ACCENT = WHITE,
    -- a flat fill and a 1 px edge, as Cute's window (UI.lua's skin)
    Backdrop = function(f)
      if not f.SetBackdrop then return end
      f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
      f:SetBackdropColor(0.035, 0.035, 0.035, 0.94)
      f:SetBackdropBorderColor(0, 0, 0, 1)
    end,
  }
end

Cute.QuestBand = {
  On = function() return Cute.ModuleOn("quests") and E.logReady == true end,
  -- why not, in a line (the engine reads the log at the game's first QUEST_LOG_UPDATE)
  Why = function() return "Reading your quest log." end,
  Steps = function() return E.Guide.Steps() end,
  Text = function(s) return E.Guide.Text(s) end,
  TimeToLevel = function() return E.Guide.TimeToLevel() end,
  Members = function() return E.Guide.MemberSteps() end,
  Open = function() Cute.Open("quests") end,
  Menu = function(s) if E.StepFrame and E.StepFrame.Menu then E.StepFrame:Menu(s) end end,
}
