-- SPDX-License-Identifier: GPL-3.0-or-later
-- Quests: the three places worth your time (the engine's Now view, its first three, by XP a minute), the rest folded
-- (the Available view's order), and the quests that pay the most XP a minute; a place opens to its quests. One list in
-- Cute's rows. The module is the folder's primary: its switch loads Cute_Quest, and switches the engine's guide (the
-- step band, the frame) on with it.
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local P = { open = {}, more = false }
local function redraw() Cute.Refresh() end
-- the minutes to a place or a giver as the engine's own list says them: "here" under a minute
local function minutes(m) if not m then return nil end return m < 1 and "here" or (math.floor(m + 0.5) .. " min") end

-- banking (an engine that cannot say: no)
local function banking() return E.Banking ~= nil and E:Banking() or false end

-- a place: questing, what its set pays and the minutes it takes, the trip there included (the owner: "3 quests for 5k
-- each" against "15 for 15k total"); banking, or an engine older than XP a minute, what you hold and could fetch there
-- and the nearest giver
local function placeRow(g, K)
  local open = g.open + g.picks + g.held
  local val = E.Short(g.fetch + g.left) .. " XP"
  local who = open .. (open == 1 and " quest" or " quests") .. (g.nearest and (", " .. minutes(g.nearest)) or "")
  if g.set and #g.set > 0 and (g.setXP or 0) > 0 and g.setMins and not banking() then
    val = E.Short(g.setXP) .. " XP"
    who = #g.set .. (#g.set == 1 and " quest, " or " quests, ") .. (g.tripEst and "est. " or "") .. math.max(1, math.floor(g.setMins + 0.5)) .. " min"
  end
  return { kind = "place", g = g, name = g.cat and g.cat.name or "?", val = val, who = who,
    c = P.open[g.idx] and K.WHITE or K.INK,
    fn = function() P.open[g.idx] = not P.open[g.idx] or nil; Cute.Refresh() end,
    tip = function(tip)
      tip:AddLine(g.cat and g.cat.name or "?", 1, 1, 1)
      for _, it in ipairs(g.quests) do if it.grp ~= 6 then tip:AddDoubleLine(it.q.name, it.st.text or "", 0.85, 0.85, 0.85, 0.6, 0.6, 0.6) end end
      tip:AddLine("Click: its quests.", 0.5, 0.5, 0.5)
    end }
end
local function questRow(q, st, value, who, K)
  return { kind = "quest", name = q.name, val = E.Short(value) .. " XP", who = who or st.text, c = (E.state.log[q.id] and K.INK) or K.DIM,
    fn = function(_, which) E.UI.QuestClick(q, st, which) end,
    tip = function(tip) E.UI.QuestTooltip(tip, q, st, value) end }
end

local function items(K)
  local out = {}
  if not E.logReady then out[1] = { kind = "note", name = "Reading your quest log.", c = K.MUTE }; return out end
  local order, _, _, _, hubName = E.UI.PlaceGroups(nil, true)
  local avail = E.UI.PlaceGroups()
  out[#out + 1] = { kind = "head", name = "Now", who = hubName and ("from " .. hubName) or nil }
  local function place(g)
    out[#out + 1] = placeRow(g, K)
    if P.open[g.idx] then
      for _, it in ipairs(g.quests) do
        if it.grp <= 4 then out[#out + 1] = questRow(it.q, it.st, it.value, nil, K) end
      end
    end
  end
  local shown = {}
  for i = 1, math.min(3, #order) do place(order[i]); shown[order[i].idx] = true end
  if #order == 0 then out[#out + 1] = { kind = "note", name = E.Model.Busy() and "Planning." or "Nothing to suggest here yet.", c = K.MUTE } end
  local rest = {}
  for _, g in ipairs(avail) do if not shown[g.idx] then rest[#rest + 1] = g end end
  if #rest > 0 then
    out[#out + 1] = { kind = "head", name = "Available", who = #rest .. (#rest == 1 and " more place" or " more places") }
    out[#out + 1] = { kind = "more", name = P.more and "Fewer" or "Show them", c = K.DIM, fn = function() P.more = not P.more; Cute.Refresh() end }
    if P.more then for _, g in ipairs(rest) do place(g) end end
  end
  -- the quests that pay the most for your time (the engine's candidates, ranked by XP a minute; banking, by XP), each
  -- with its minutes, the trip to its giver included ("est." where its zone's usual stands in)
  out[#out + 1] = { kind = "head", name = banking() and "Highest XP" or "Most XP a minute" }
  local D = E.Data
  for _, c in ipairs(E.UI:Candidates(8, E.state.level)) do
    local q = E.Quest.Get(c.id)
    if q then
      -- (a quest no way is known to: its minutes are math.huge, so its place's name, never "inf min")
      local who = (c.T and c.T < math.huge and E.Model.MinutesText and E.Model.MinutesText(c.T, c.est)) or minutes(c.mins) or (D.CAT[c.cat] and D.CAT[c.cat].name) or nil
      out[#out + 1] = questRow(q, E:Status(q), c.full, who, K)
    end
  end
  return out
end

local function make(parent, ui)
  local r = ui:MakeLine(parent)
  return r
end

function P.Draw(ui, scroll)
  if not E then return QB.NeedPage(ui, scroll, "quests") end
  local K, ROW = ui.COLORS, ui.ROW
  local w = scroll:Width()
  local list = items(K)
  local v = ui:List("quests", function(parent) return make(parent, ui) end)
  v:Set(#list, 0, ROW, function(r, i, ly)
    local it = list[i]
    r:SetHeight(ROW)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, -ly)
    r:SetWidth(w)
    r.bg:SetColorTexture(1, 1, 1, it.kind == "head" and 0.06 or (it.kind == "place" and 0.035) or 0)
    r.bar:Hide()
    r.fn, r.tip = it.fn, it.tip
    local x = it.kind == "quest" and 24 or 8
    local right = (it.val and 100 or 0) + (it.who and 150 or 0)
    r.name:ClearAllPoints(); r.name:SetPoint("LEFT", x, 0); r.name:SetWidth(w - x - right - 8); r.name:SetJustifyH("LEFT")
    ui.Color(r.name, it.c or (it.kind == "head" and K.WHITE) or K.INK)
    ui.FitText(r.name, it.name or "", w - x - right - 12)
    if it.who then r.who:ClearAllPoints(); r.who:SetPoint("RIGHT", -4, 0); r.who:SetWidth(146); r.who:SetJustifyH("RIGHT"); ui.Color(r.who, K.DIM); ui.FitText(r.who, it.who, 142); r.who:Show() else r.who:Hide() end
    if it.val then r.val:ClearAllPoints(); r.val:SetPoint("RIGHT", it.who and -154 or -4, 0); r.val:SetWidth(96); r.val:SetJustifyH("RIGHT"); ui.Color(r.val, K.INK); ui.FitText(r.val, it.val, 92); r.val:Show() else r.val:Hide() end
  end)
  ui.virtual = function() v:Show(ui.scroll.bar:GetValue() or 0, ui.scroll:View()) end
  scroll:SetContentHeight(#list * ROW + 8)
end

local ACCEPT = { { "Off", "off" }, { "On my route", "route" }, { "Worth taking", "worth" } }
function P.Settings(_, col)
  if not E then return QB.NeedSettings(col, "Quests") end
  local s = E:Settings()
  col:Head("Quests")
  -- the step frame and the arrow (the engine's settings; QuestBank's own while it is loaded; the frame's own menu locks it)
  col:Check("Step frame", s.guide.frame == true, true, function(on) s.guide.frame = on; if E.StepFrame then E.StepFrame.Apply() end end)
  col:Check("Direction arrow", s.arrow == true, true, function(on) if E.Arrow then E.Arrow:Set(on) else s.arrow = on end end)
  -- (6.1.1) the game's quest tracker out of sight while the step frame shows (the engine's StepFrame.lua SF.Tracker)
  col:Check("Hide the game's quest tracker with the step frame", s.guide.hideTracker ~= false, true, function(on) s.guide.hideTracker = on; if E.StepFrame then E.StepFrame.Apply() end end)
  local names, current = {}, "Off"
  for _, a in ipairs(ACCEPT) do names[#names + 1] = a[1]; if s.autoAccept == a[2] then current = a[1] end end
  col:Choice("Accept for me", names, current, function(v) for _, a in ipairs(ACCEPT) do if a[1] == v then s.autoAccept = a[2] end end end)
  col:Check("Hand finished quests in for me", s.autoTurnIn == true, true, function(on) s.autoTurnIn = on end)
  col:Check("Progress in mob tooltips", s.tipProgress ~= false, true, function(on) s.tipProgress = on end)
  -- the line in chat as a quest is handed in, complete or dropped (the engine's sayXP, read in its Core.lua; off since the
  -- launch round, as QuestBank's Guide section and the step frame's menu have it). Eight rows: the section's most
  col:Check("Say XP after each hand-in", s.sayXP == true, true, function(on) s.sayXP = on and true or false end, nil, function(tip)
    tip:AddLine("Say XP after each hand-in", 1, 1, 1)
    tip:AddLine("A line in chat as you hand a quest in, with the XP it paid, and as a quest is complete or leaves your log. Off, chat stays quiet: the step frame and the Route page show the XP.", 0.85, 0.85, 0.85, true)
  end)
  col:Check("Share with your party", s.share.party ~= false, true, function(on) s.share.party = on end)
end

-- the switch: the engine's guide (the step band, the frame as its row says) with it; off, the arrow is put away and
-- on brings it back (s.cuteArrow remembers that it was up). While QuestBank is loaded its settings are its own:
-- nothing is set. Before the engine's login the flags alone: Arrow:Init and StepFrame:Init read them
function P.Toggle(on)
  if QB.dormant or not E or not QB.ready then Cute.Refresh() return end
  local s = E:Settings()
  s.guide.on = on
  if s.welcome then s.welcome = nil end
  if on then
    if s.cuteArrow then
      s.cuteArrow = nil
      if E.loginDone and E.Arrow then E.Arrow:Set(true) else s.arrow = true end
    end
  elseif s.arrow then
    s.cuteArrow = true
    if E.loginDone and E.Arrow then E.Arrow:Set(false) else s.arrow = false end
  end
  if not E.loginDone then return end
  if E.StepFrame then E.StepFrame.Apply() end
  E:MarkDirty()
end
QB.Toggles.quests = P.Toggle

Cute:RegisterModule({
  id = "quests", addon = ADDON, title = "Quests", order = 21,
  notes = "The three places worth your time, the rest folded, the most XP a minute; the step now in the Guide.",
  page = P.Draw, settings = P.Settings, onToggle = P.Toggle,
  events = { QUEST_LOG_UPDATE = redraw, QUEST_ACCEPTED = redraw, QUEST_TURNED_IN = redraw, PLAYER_LEVEL_UP = redraw, ZONE_CHANGED_NEW_AREA = redraw },
})
