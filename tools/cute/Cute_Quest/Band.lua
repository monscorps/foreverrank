-- SPDX-License-Identifier: GPL-3.0-or-later
-- The step band: what the Guide's band draws while the Quests module is on, read from the engine (Cute.QuestBand), and
-- the three Guide rows for the step frame and the arrow. Sets the engine's skin, so the step frame and the arrow the
-- copy draws are flat, in Cute's font and greys (QuestBank's own, while QuestBank is loaded, keep QuestBank's look).
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
if not E then return end

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
  Steps = function() return E.Guide.Steps() end,
  Text = function(s) return E.Guide.Text(s) end,
  TimeToLevel = function() return E.Guide.TimeToLevel() end,
  Members = function() return E.Guide.MemberSteps() end,
  Open = function() Cute.Open("quests") end,
  Menu = function(s) if E.StepFrame and E.StepFrame.Menu then E.StepFrame:Menu(s) end end,
  -- the Guide's rows for the frame and the arrow (the engine's settings; QuestBank's own while it is loaded)
  Settings = function(col)
    local s = E:Settings()
    col:Head("The step now")
    col:Check("Step frame", s.guide.frame == true, true, function(on) s.guide.frame = on; if E.StepFrame then E.StepFrame.Apply() end end)
    col:Check("Direction arrow", s.arrow == true, true, function(on) if E.Arrow then E.Arrow:Set(on) else s.arrow = on end end)
    col:Check("Lock the step frame", s.guide.locked == true, true, function(on) s.guide.locked = on; if E.StepFrame then E.StepFrame.Apply() end end)
  end,
}
