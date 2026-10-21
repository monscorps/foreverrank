-- SPDX-License-Identifier: GPL-3.0-or-later
-- Route: the quest window's second tab, always there (the base). The hand-in stops in order with the minutes to each,
-- the first marked (the one target the arrow and the minimap follow); the band holds the route's sum and the run
-- button. Its section has the route's own rows and the minimap's (they belong to the base, not to the Map module: a
-- player who keeps the game's map keeps them).
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local R = {}
local function redraw() Cute.Refresh() end

function R.Draw(ui, scroll)
  if not E then return QB.NeedPage(ui, scroll, "route") end
  QB.Reader.Left(ui)
  if QB.Reader.Open(ui) then return QB.Reader.Draw(ui, scroll) end
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
  -- (the review round) a stop by its place in words, as the map's pins, the step frame and the arrow name it
  -- (TV.StopPlace: "Goldshire", not Model.lua's "Elwynn Forest (42, 65)"); its tooltip titled as its pin is (the NPC and
  -- the town: P.StopTitle)
  local TV, Pn = E.Travel, E.Pins
  for i, leg in ipairs(r.legs or {}) do
    local n = #(leg.rows or {})
    local stop = leg.stop
    local place = stop and ((TV and TV.StopPlace and TV.StopPlace(stop)) or stop.name) or "?"
    items[#items + 1] = { name = i .. ". " .. place, val = math.floor((leg.t or 0) + 0.5) .. " min",
      who = n .. (n == 1 and " quest" or " quests"), first = i == 1,
      tip = function(tip)
        tip:AddLine(stop and ((Pn and Pn.StopTitle and Pn.StopTitle(stop)) or place) or "?", 1, 1, 1)
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
  if not E then return QB.NeedSettings(col, "Route") end
  local s = E:Settings()
  col:Head("Route")
  col:Choice("Follow", { "The plan", "Ready now" }, s.routeQuest == "now" and "Ready now" or "The plan", function(v) s.routeQuest = v == "Ready now" and "now" or nil; E:MarkDirty() end)
  col:Check("Show the way step by step on the arrow", s.arrowTravel ~= false, true, function(on) s.arrowTravel = on; if E.Arrow and E.Arrow.Invalidate then E.Arrow.Invalidate() end end)
  col:Check("The hearthstone may be a step", s.arrowHearth ~= false, true, function(on) s.arrowHearth = on; if E.Arrow and E.Arrow.Invalidate then E.Arrow.Invalidate() end end)
  -- the minimap's (Minimap.lua, MinimapView.lua): the route, one stroke unless the whole route is asked (6.1.1), the ! of
  -- the quests you can take, the far view
  local function mini() if E.Mini and E.Mini.Invalidate then E.Mini.Invalidate() end end
  col:Check("Route on the minimap", s.minimapPins ~= false and s.minimapLines ~= false, true, function(on) s.minimapPins, s.minimapLines = on, on; mini() end)
  col:Check("Show the whole route", s.wholeRoute == true, true, function(on) s.wholeRoute = on; mini() end)
  col:Note("Off, one stroke: from you to where the arrow leads.")
  col:Check("A ! on the minimap for quests you can take", s.minimapGivers == true, true, function(on) s.minimapGivers = on; mini() end)
  col:Check("Minimap far view", s.mmExtended == true, true, function(on) s.mmExtended = on; mini() end)
end

Cute:RegisterModule({
  id = "route", addon = ADDON, title = "Route", order = 22, window = "quests", base = true,
  notes = "The hand-in stops in order with minutes; the first is where the arrow points.",
  page = R.Draw, settings = R.Settings,
  events = { QUEST_LOG_UPDATE = redraw, QUEST_TURNED_IN = redraw, ZONE_CHANGED_NEW_AREA = redraw },
})
