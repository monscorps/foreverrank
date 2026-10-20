-- SPDX-License-Identifier: GPL-3.0-or-later
-- Quests: the three places worth your time (the engine's Now view, its first three), the rest folded (the Available
-- view's order), and the highest XP as a finder; a place opens to its quests. One list in Cute's rows. The module is
-- the folder's primary: its switch loads Cute_Quest, and switches the engine's guide (the step band, the frame) on
-- with it.
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local P = { open = {}, more = false }
local function redraw() Cute.Refresh() end
-- the minutes to a place or a giver as the engine's own list says them: "here" under a minute
local function minutes(m) if not m then return nil end return m < 1 and "here" or (math.floor(m + 0.5) .. " min") end

local function placeRow(g, K)
  local open = g.open + g.picks + g.held
  return { kind = "place", g = g, name = g.cat and g.cat.name or "?", val = E.Short(g.fetch + g.left) .. " XP",
    who = open .. (open == 1 and " quest" or " quests") .. (g.nearest and (", " .. minutes(g.nearest)) or ""),
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
  if QB.missing then out[1] = { kind = "note", name = "Quests needs " .. QB.missing .. ".", c = K.MUTE }; return out end
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
  out[#out + 1] = { kind = "head", name = "Highest XP" }
  local D = E.Data
  for _, c in ipairs(E.UI:Candidates(8, E.state.level)) do
    local q = E.Quest.Get(c.id)
    if q then
      local who = minutes(c.mins) or (D.CAT[c.cat] and D.CAT[c.cat].name) or nil
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
  local s = E:Settings()
  col:Head("Quests")
  local names, current = {}, "Off"
  for _, a in ipairs(ACCEPT) do names[#names + 1] = a[1]; if s.autoAccept == a[2] then current = a[1] end end
  col:Choice("Accept for me", names, current, function(v) for _, a in ipairs(ACCEPT) do if a[1] == v then s.autoAccept = a[2] end end end)
  col:Check("Hand finished quests in for me", s.autoTurnIn == true, true, function(on) s.autoTurnIn = on end)
  col:Check("Progress in mob tooltips", s.tipProgress ~= false, true, function(on) s.tipProgress = on end)
  col:Check("Share with your party", s.share.party ~= false, true, function(on) s.share.party = on end)
  col:Check("Note what the game shows, for foreverrank.com", s.noteGame ~= false, true, function(on) s.noteGame = on end)
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
  notes = "The three places worth your time, the rest folded, the highest XP; the step now in the Guide.",
  page = P.Draw, settings = P.Settings, onToggle = P.Toggle,
  events = { QUEST_LOG_UPDATE = redraw, QUEST_ACCEPTED = redraw, QUEST_TURNED_IN = redraw, PLAYER_LEVEL_UP = redraw, ZONE_CHANGED_NEW_AREA = redraw },
})
