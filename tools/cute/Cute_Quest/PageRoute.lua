-- SPDX-License-Identifier: GPL-3.0-or-later
-- Route: the hand-in stops in order with the minutes to each, the first marked (the one target the arrow and the
-- minimap follow); the band holds the route's sum and the run button. Nothing here is clicked but the button.
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local R = {}
local function redraw() Cute.Refresh() end

function R.Draw(ui, scroll)
  local K, ROW = ui.COLORS, ui.ROW
  local w = scroll:Width()
  local r = (E.Target and E.Target.Route()) or E.routeNow or { legs = {} }
  local run = E.Run and E.Run.Get()
  -- the band: one line and one button
  local l = ui.bandLines:Get()
  l:ClearAllPoints(); l:SetPoint("TOPLEFT", 0, -4); l:SetSize(w - 170, ROW)
  l.bg:SetColorTexture(1, 1, 1, 0); l.bar:Hide(); l.val:Hide(); l.who:Hide(); l.fn, l.tip = nil, nil
  l.name:ClearAllPoints(); l.name:SetPoint("LEFT", 8, 0); l.name:SetWidth(w - 186); l.name:SetJustifyH("LEFT")
  ui.Color(l.name, K.INK)
  ui.FitText(l.name, string.format("%s XP, level %.1f, %d min%s", E.Comma(r.xp or 0), r.level or 0, math.floor((r.t or 0) + 0.5), (E.Model and E.Model.Busy()) and ", planning" or ""), w - 190)
  l.name:Show()
  local b = ui.bandButtons:Get()
  b:ClearAllPoints(); b:SetPoint("TOPRIGHT", 0, -3); b:SetWidth(160)
  b:SetLabel(run and "End run" or "Start run")
  b:SetOn(E.Run ~= nil)
  b:SetScript("OnClick", Cute.Safe(function() if E.Run.Get() then E.Run.Stop() else E:Recompute(true); E.Run.Start() end; Cute.Refresh() end, "route: run"))
  ui:SetBand(ROW + 8)
  -- the legs
  local items = {}
  for i, leg in ipairs(r.legs or {}) do
    local n = #(leg.rows or {})
    items[#items + 1] = { name = i .. ". " .. (leg.stop and leg.stop.name or "?"), val = math.floor((leg.t or 0) + 0.5) .. " min",
      who = n .. (n == 1 and " quest" or " quests"), first = i == 1,
      tip = function(tip)
        tip:AddLine(leg.stop and leg.stop.name or "?", 1, 1, 1)
        for _, row in ipairs(leg.rows or {}) do tip:AddDoubleLine(row.q and row.q.name or "?", E.Comma(row.xp or 0) .. " XP", 0.85, 0.85, 0.85, 0.6, 0.6, 0.6) end
      end }
  end
  if #items == 0 then items[1] = { name = "Nothing to hand in yet.", c = K.MUTE } end
  local v = ui:List("route", function(parent) return ui:MakeLine(parent) end)
  v:Set(#items, 0, ROW, function(row, i, ly)
    local it = items[i]
    row:SetHeight(ROW); row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -ly); row:SetWidth(w)
    row.bg:SetColorTexture(1, 1, 1, it.first and 0.035 or 0)
    row.bar:SetShown(it.first == true); row.bar:SetColorTexture(K.WHITE[1], K.WHITE[2], K.WHITE[3], 1)
    row.fn, row.tip = nil, it.tip
    row.name:ClearAllPoints(); row.name:SetPoint("LEFT", 8, 0); row.name:SetWidth(w - 260); row.name:SetJustifyH("LEFT")
    ui.Color(row.name, it.c or (it.first and K.WHITE) or K.INK)
    ui.FitText(row.name, it.name, w - 264)
    if it.who then row.who:ClearAllPoints(); row.who:SetPoint("RIGHT", -4, 0); row.who:SetWidth(146); row.who:SetJustifyH("RIGHT"); ui.Color(row.who, K.DIM); ui.FitText(row.who, it.who, 142); row.who:Show() else row.who:Hide() end
    if it.val then row.val:ClearAllPoints(); row.val:SetPoint("RIGHT", -154, 0); row.val:SetWidth(96); row.val:SetJustifyH("RIGHT"); ui.Color(row.val, K.INK); ui.FitText(row.val, it.val, 92); row.val:Show() else row.val:Hide() end
  end)
  ui.virtual = function() v:Show(ui.scroll.bar:GetValue() or 0, ui.scroll:View()) end
  scroll:SetContentHeight(#items * ROW + 8)
end

function R.Settings(_, col)
  local s = E:Settings()
  col:Head("Route")
  col:Choice("Follow", { "The plan", "Ready now" }, s.routeQuest == "now" and "Ready now" or "The plan", function(v) s.routeQuest = v == "Ready now" and "now" or nil; E:MarkDirty() end)
  col:Check("Show the way step by step on the arrow", s.arrowTravel ~= false, true, function(on) s.arrowTravel = on; if E.Arrow and E.Arrow.Invalidate then E.Arrow.Invalidate() end end)
  col:Check("The hearthstone may be a step", s.arrowHearth ~= false, true, function(on) s.arrowHearth = on; if E.Arrow and E.Arrow.Invalidate then E.Arrow.Invalidate() end end)
end

Cute:RegisterModule({
  id = "route", addon = ADDON, title = "Route", order = 22,
  notes = "The hand-in stops in order with minutes; the first is where the arrow points.",
  page = R.Draw, settings = R.Settings,
  events = { QUEST_LOG_UPDATE = redraw, QUEST_TURNED_IN = redraw, ZONE_CHANGED_NEW_AREA = redraw },
})
