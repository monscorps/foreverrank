-- SPDX-License-Identifier: GPL-3.0-or-later
-- Quests: the quest window's first tab (L), the base. The band over the whole width is the step now (Cute's Guide.lua
-- draws it: Cute.Guide.DrawBand): its icon, words and count, its progress, the next two, your level and the XP bar.
-- Under it, at 1000 px wide and more, two columns: on the left the questing (the three places worth your time in the
-- engine's XP-a-minute order, your zone open with its first five quests, then the other places and the best XP anywhere,
-- folded); on the right, 396 px with its own scroll bar, the guild's dungeon pick as a card (Cute.Guide.DrawPick, with
-- the Dungeons tab on), the best gear upgrade within reach (with the Gear tab on) and your party's steps (while grouped).
-- Narrower, one column: the right's sections after the left's. Rows in the windows' look (Cute.Look: pattern A, a
-- place 40 px, a quest 34). A quest row's click reads the quest (Reader.lua), Ctrl-click shows it on the arrow,
-- Shift-click puts it on the pick-up list, right-click is its menu. The module is the folder's primary and the base:
-- always on, it switches the engine's guide (the step band, the frame) on with it.
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local P = { open = {}, all = {}, others = false, best = false }
local SIDE_W, TWO_AT, FIRST = 396, 1000, 5
local DOT = " \194\183 "
local function redraw() Cute.Refresh() end
local function plain(v) if issecretvalue and issecretvalue(v) then return nil end return v end

-- banking (an engine that cannot say: no)
local function banking() return E.Banking ~= nil and E:Banking() or false end

-- where an NPC stands, in words: the town within 200 yards (Travel.lua TV.TownNear), else its zone
local function placeOf(npc)
  if not npc then return nil end
  local n = npc.idx and E.Data.NPC[npc.idx]
  local town = n and E.Travel and E.Travel.TownNear and E.Travel.TownNear(n[5], n[6], n[7], 200)
  return town or npc.place or (E.Data.MAPNAME and E.Data.MAPNAME[npc.m]) or nil
end
-- a held quest's objectives in a line, each its cursor at 12 px and "Kobold Vermin 3/8"; a finished one the ready check
-- and the muted grey
local MUTE = "|cff858585"
local function objectivesLine(e, L)
  local parts = {}
  for slot, o in ipairs(e.objectives or {}) do
    local text = plain(o.text)
    local name, have, need
    if E.Guide.ParseLine then name, have, need = E.Guide.ParseLine(text) else name = text end
    if name and name ~= "" then
      local words = (have and need) and string.format("%s %d/%d", name, have, need) or name
      if plain(o.done) == true then parts[#parts + 1] = L.Inline("ready", 12) .. " " .. MUTE .. words .. "|r"
      else parts[#parts + 1] = L.Inline(QB.ObjKind(e.id, slot, text), 12) .. " " .. words end
    end
  end
  return #parts > 0 and table.concat(parts, "   ") or nil
end
-- a quest's reward as a 16 px icon: its best gear for you (the finders' UI.BestReward), else nothing
local function rewardOf(q, level)
  if not (E.UI and E.UI.BestReward) then return nil end
  local ok, id = pcall(E.UI.BestReward, q.id, "gear", level)
  if not (ok and type(id) == "number") then return nil end
  local CI = C_Item
  local okI, icon = pcall(CI and CI.GetItemIconByID or error, id)
  local okQ, qual = pcall(CI and CI.GetItemQualityByID or error, id)
  return { item = (okI and type(icon) == "number") and icon or 134400, q = (okQ and type(qual) == "number") and qual or 1 }
end

-- a quest as a row (pattern A, two lines): the quest POI for one you hold (in progress or ready), the offer's ! for one
-- you could take; its level in the game's colour ("23+" for a group's); its name, white for the arrow's target; line 2
-- its objectives, or whom it goes to or comes from; on the right where it is (minutes, "ready"), its XP, its reward
local function questRow(ui, q, st, value, who, L, K)
  local e = E.state.log[q.id]
  local icon
  if e then icon = { poi = e.complete and "ready" or "log" } else icon = { art = q.repeatable and "repeatable" or "accept" } end
  if E.QuestMap and E.QuestMap.Grey and E.QuestMap.Grey(q, E.state.level) then icon.desat = true end
  local line2
  if e and e.complete then
    local n = q.turn
    line2 = n and n.n and ("to " .. n.n .. ((placeOf(n) and (DOT .. placeOf(n))) or "")) or "ready to hand in"
  elseif e then
    line2 = objectivesLine(e, L) or "in your log"
  else
    -- (a giver the catalog has no NPC for, a quest the game told QuestBank of: its place, else so)
    local n = q.give
    line2 = (n and n.n and ("from " .. n.n .. ((placeOf(n) and (DOT .. placeOf(n))) or "")))
      or (q.cat and q.cat.name and ("in " .. q.cat.name)) or "who gives it is not known yet"
  end
  local whoC = K.DIM
  if e and e.complete then who, whoC = "ready", K.GOOD end
  local target = E.Target and E.Target.cur and E.Target.cur.qid == q.id
  return { kind = "two", bar = K.QUEST, icon = icon, lvl = tostring(q.lvl or "") .. (q.group and "+" or ""), lvlC = L.LevelColor(q.lvl),
    name = q.name, nameC = target and K.WHITE or nil, bg = target and 0.06 or nil, line2 = line2, who = who, whoC = whoC,
    val = E.Comma(math.floor((value or 0) + 0.5)), rew = rewardOf(q, E.state.level),
    fn = function(_, which) QB.RowClick(ui, q, st, which) end,
    tip = function(tip) E.UI.QuestTooltip(tip, q, st, value) end }
end
-- a place (pattern A, 40 px): its painted picture (cat.img, the middle of its 256 x 128) or its icon, its name, how many
-- quests and how far, its XP and its XP a minute; a click opens or folds it
local function placeRow(g, open, L, K)
  local a = g.cat or {}
  local n = 0
  for _, it in ipairs(g.quests) do if it.grp <= 4 then n = n + 1 end end
  local far
  if g.nearest and g.nearest < math.huge then far = g.nearest < 1 and "you are here" or string.format("%d min away", math.floor(g.nearest + 0.5)) end
  local xp = (g.setXP and g.setXP > 0 and not banking()) and g.setXP or (g.fetch + g.left)
  local sub
  if not banking() and g.value and g.value > 0 then sub = string.format("%s%s XP a minute", g.tripEst and "est. " or "", E.Comma(math.floor(g.value + 0.5))) end
  return { kind = "place", bar = K.QUEST, bg = open and 0.06 or nil,
    pic = a.img and { a.img, { 0.1, 0.9, 0, 1 } } or nil, icon = (not a.img) and { art = { nil, a.zi or a.icon or 134400 }, crop = true } or nil,
    name = a.name or "?", line2 = n .. (n == 1 and " quest" or " quests") .. (far and (DOT .. far) or ""),
    val = E.Comma(math.floor(xp / 10 + 0.5) * 10) .. " XP", sub = sub,
    fn = function() P.open[g.idx] = not open; redraw() end,
    tip = function(tip)
      tip:AddLine(a.name or "?", 1, 1, 1)
      for _, it in ipairs(g.quests) do if it.grp <= 4 then tip:AddDoubleLine(it.q.name, it.st.text or "", 0.85, 0.85, 0.85, 0.6, 0.6, 0.6) end end
      tip:AddLine(open and "Click: fold it." or "Click: its quests.", 0.5, 0.5, 0.5)
    end }
end
-- a place's quests, the most XP a minute first (banking: the most XP)
local function byRate(a, b)
  local ra, rb = a.rate or 0, b.rate or 0
  if ra ~= rb then return ra > rb end
  return (a.value or 0) > (b.value or 0)
end

-- the left column: the questing
local function questing(ui, L, K)
  local out = {}
  if not E.logReady then out[1] = { kind = "note", x = 10, name = "Reading your quest log." }; return out end
  local order = E.UI.PlaceGroups(nil, true)
  local all = E.UI.PlaceGroups()
  local three = math.min(3, #order)
  out[#out + 1] = { kind = "head", bar = K.QUEST, icon = { art = "accept" }, name = "Questing", who = three .. (three == 1 and " place" or " places") }
  if three == 0 then out[#out + 1] = { kind = "note", x = 10, name = E.Model.Busy() and "Planning." or "Nothing to suggest here yet." } end
  -- your zone open: where a giver stands within a minute, else the first place
  local hereIdx
  for i = 1, three do local g = order[i]; if g.nearest and g.nearest < 1 then hereIdx = g.idx; break end end
  hereIdx = hereIdx or (order[1] and order[1].idx)
  local shown = {}
  local function place(g)
    local open = P.open[g.idx]
    if open == nil then open = g.idx == hereIdx end
    out[#out + 1] = placeRow(g, open, L, K)
    if not open then return end
    local list = {}
    for _, it in ipairs(g.quests) do if it.grp <= 4 then list[#list + 1] = it end end
    table.sort(list, byRate)
    local n = P.all[g.idx] and #list or math.min(FIRST, #list)
    for i = 1, n do
      local it = list[i]
      local who = it.trip and it.trip >= 1 and it.trip < math.huge and (math.floor(it.trip + 0.5) .. " min") or nil
      out[#out + 1] = questRow(ui, it.q, it.st, it.value, who, L, K)
    end
    if #list > n then
      out[#out + 1] = { kind = "note", bar = K.QUEST, name = (#list - n) .. " more in " .. (g.cat and g.cat.name or "this place"),
        fn = function() P.all[g.idx] = true; redraw() end, tip = function(tip) tip:AddLine("Click: show them all.", 1, 1, 1) end }
    end
  end
  for i = 1, three do place(order[i]); shown[order[i].idx] = true end
  local rest = {}
  for _, g in ipairs(all) do if not shown[g.idx] then rest[#rest + 1] = g end end
  -- (folded heads, each its icon: the map for the other places, the offer's ! for the best quests; a click opens one)
  if #rest > 0 then
    out[#out + 1] = { kind = "head", bar = K.QUEST, icon = { art = { nil, 134269 }, crop = true }, name = "Other places", who = #rest .. (#rest == 1 and " place" or " places"),
      fn = function() P.others = not P.others; redraw() end, tip = function(tip) tip:AddLine(P.others and "Click: fold them." or "Click: every other place with quests for you.", 1, 1, 1) end }
    if P.others then for _, g in ipairs(rest) do place(g) end end
  end
  -- the quests that pay the most for your time anywhere (the engine's candidates, by XP a minute; banking, by XP)
  out[#out + 1] = { kind = "head", bar = K.QUEST, icon = { art = "accept" }, name = banking() and "Highest XP anywhere" or "Best XP anywhere", who = P.best and "8 quests" or "folded",
    fn = function() P.best = not P.best; redraw() end, tip = function(tip) tip:AddLine(P.best and "Click: fold them." or "Click: the eight quests that pay the most for your time.", 1, 1, 1) end }
  if P.best then
    local D = E.Data
    for _, c in ipairs(E.UI:Candidates(8, E.state.level)) do
      local q = E.Quest.Get(c.id)
      if q then
        -- (a quest no way is known to: its minutes are math.huge, so its place's name, never "inf min")
        local who = (c.T and c.T < math.huge and E.Model.MinutesText and E.Model.MinutesText(c.T, c.est)) or (c.mins and c.mins < math.huge and (math.floor(c.mins + 0.5) .. " min")) or (D.CAT[c.cat] and D.CAT[c.cat].name) or nil
        out[#out + 1] = questRow(ui, q, E:Status(q), c.full, who, L, K)
      end
    end
  end
  return out
end

-- the best gear upgrade within reach (Gear.lua's G.Upgrades: the slot that gains the most item levels), worked out at
-- most every ten seconds: the Gear page walks every dungeon's loot
local gearMemo = { t = -100 }
local function bestGear()
  if not (E.Gear and E.Gear.Upgrades) then return nil end
  local now = GetTime and GetTime() or 0
  if now - gearMemo.t > 10 or gearMemo.level ~= E.state.level then
    gearMemo.t, gearMemo.level, gearMemo.best = now, E.state.level, nil
    local best, gain
    for _, r in ipairs(E.Gear.Upgrades()) do
      local c = r.best
      local g = c and (c.ilvl - (r.worn and r.worn.ilvl or 0)) or 0
      if c and (not gain or g > gain) then best, gain = r, g end
    end
    gearMemo.best, gearMemo.gain = best, gain
  end
  return gearMemo.best, gearMemo.gain
end
local function itemFacts(id)
  local CI = C_Item
  local okI, icon = pcall(CI and CI.GetItemIconByID or error, id)
  local okQ, qual = pcall(CI and CI.GetItemQualityByID or error, id)
  local name = E.API and E.API.ItemInfo and E.API.ItemInfo(id) or nil
  return (okI and type(icon) == "number") and icon or 134400, (okQ and type(qual) == "number") and qual or 1, name or ("Item " .. id)
end

-- the right column: the guild's pick (the Dungeons tab on), the gear upgrade (the Gear tab on), the party (grouped);
-- into host from y, w wide; returns the height
local function rightColumn(ui, host, w, narrow, L, K)
  local y = 0
  host.pool = host.pool or ui.Pool(host, function(parent) return L.MakeRow(parent) end)
  host.pool:Reset()
  local function row(it)
    local r = host.pool:Get()
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y)
    y = y + L.FillRow(r, it, w)
  end
  if Cute.ModuleOn("journal") and Cute.Guide and Cute.Guide.DrawPick then
    y = y + Cute.Guide.DrawPick(ui, host, y, w, narrow) + 8
  else
    for _, k in ipairs({ "pickHead", "pickCard", "pickNote" }) do if host[k] then host[k]:Hide() end end
  end
  if Cute.ModuleOn("gear") then
    local r = bestGear()
    local c = r and r.best
    if c then
      local icon, qual, name = itemFacts(c.id)
      local from
      if c.q then from = "from " .. c.q.name .. ((c.q.give and c.q.give.n) and (DOT .. c.q.give.n) or "")
      elseif c.boss then from = "from " .. (c.boss.n or "?") .. ((c.cat and c.cat.name) and (DOT .. c.cat.name) or "") end
      local worn = r.worn and r.worn.ilvl or 0
      row({ kind = "head", bar = K.LINE, icon = { item = icon, q = qual }, name = "Gear", who = r.slot and r.slot.name and r.slot.name:lower() or nil })
      row({ kind = "two", bar = K.LINE, icon = { item = icon, q = qual, up = true }, name = name, nameC = L.QualityName(qual), line2 = from,
        val = "+" .. (c.ilvl - worn) .. " item level", valW = 100,
        fn = function() Cute.Open("gear") end,
        tip = function(tip)
          tip:AddLine(name, L.QualityName(qual)[1], L.QualityName(qual)[2], L.QualityName(qual)[3])
          if from then tip:AddLine(from, 0.85, 0.85, 0.85, true) end
          tip:AddLine(string.format("Item level %d, %d over what you wear.", c.ilvl, c.ilvl - worn), 0.7, 0.7, 0.7, true)
          tip:AddLine("Click: the Gear tab.", 0.45, 0.45, 0.45)
        end })
      y = y + 8
    end
  end
  local members = E.Guide.MemberSteps()
  if #members > 0 then
    row({ kind = "head", bar = K.LINE, icon = { art = "party" }, name = "Party", who = tostring(#members) })
    for i = 1, math.min(4, #members) do
      local m = members[i]
      local cc = ui.ClassColor(m.class)
      row({ kind = "mate", bar = cc, name = m.name, nameC = cc, line2 = m.text, tip = function(tip) tip:AddLine(m.name, cc[1], cc[2], cc[3]); tip:AddLine(m.text, 0.85, 0.85, 0.85, true) end })
    end
    if #members > 4 then
      local rest = {}
      for i = 5, #members do rest[#rest + 1] = members[i] end
      row({ kind = "note", x = 12, name = "and " .. #rest .. " more in your group", tip = function(tip)
        tip:AddLine("Your group's steps", 1, 1, 1)
        for _, m in ipairs(rest) do local c = ui.ClassColor(m.class); tip:AddLine(m.name .. ": " .. m.text, c[1], c[2], c[3], true) end
      end })
    end
  end
  host.pool:HideRest()
  return y
end

-- a list of rows into a host, from y; returns the height
local function fill(ui, host, items, y, w, L)
  host.pool = host.pool or ui.Pool(host, function(parent) return L.MakeRow(parent) end)
  host.pool:Reset()
  for _, it in ipairs(items) do
    local r = host.pool:Get()
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y)
    y = y + L.FillRow(r, it, w)
  end
  host.pool:HideRest()
  return y
end

function P.Draw(ui, scroll)
  if not E then return QB.NeedPage(ui, scroll, "quests") end
  QB.Reader.Left(ui)
  if QB.Reader.Open(ui) then return QB.Reader.Draw(ui, scroll) end
  local K, L = ui.COLORS, ui.Look
  -- the band over both columns
  if Cute.Guide and Cute.Guide.DrawBand then Cute.Guide.DrawBand(ui) end
  local two = (ui.frame:GetWidth() or 0) >= TWO_AT
  local side = two and Cute.Side(ui, SIDE_W) or nil
  local w = scroll:Width()
  local left = Cute.Host(ui, "quests")
  left:ClearAllPoints(); left:SetPoint("TOPLEFT", 0, 0)
  local h = fill(ui, left, questing(ui, L, K), 0, w, L)
  left:SetSize(w, math.max(1, h))
  if side then
    local sw = side:Width()
    local right = Cute.Host(ui, "questsSide", true)
    right:ClearAllPoints(); right:SetPoint("TOPLEFT", 0, 0)
    local rh = rightColumn(ui, right, sw, sw < 420, L, K)
    right:SetSize(sw, math.max(1, rh))
    side:SetContentHeight(rh + 8)
  else
    -- one column: the right's sections after the questing
    local right = Cute.Host(ui, "questsUnder")
    right:ClearAllPoints(); right:SetPoint("TOPLEFT", 0, -(h + 12))
    local rh = rightColumn(ui, right, w, false, L, K)
    right:SetSize(w, math.max(1, rh))
    h = h + 12 + rh
  end
  scroll:SetContentHeight(h + 8)
end

local ACCEPT = { { "Off", "off" }, { "On my route", "route" }, { "Worth taking", "worth" } }
function P.Settings(_, col)
  if not E then return QB.NeedSettings(col, "Quests") end
  local s = E:Settings()
  col:Head("Quests")
  -- the step frame and the arrow (the engine's settings; QuestBank's own while it is loaded; the frame's own menu locks it)
  col:Check("Step frame", s.guide.frame == true, true, function(on) s.guide.frame = on; if E.StepFrame then E.StepFrame.Apply() end end)
  -- (the windows round) the quests you hold listed under the steps (StepFrame.lua SF.DrawQuests), 0 to 10
  local nq = math.max(0, math.min((E.StepFrame and E.StepFrame.QUESTS_MAX) or 10, tonumber(s.guide.quests) or 0))
  local function setQ(n) s.guide.quests = n; if E.StepFrame then E.StepFrame.Apply() end; Cute.Refresh() end
  col:Step("Quests under the step", tostring(nq), false, nq > 0 and function() setQ(nq - 1) end or nil,
    nq < ((E.StepFrame and E.StepFrame.QUESTS_MAX) or 10) and function() setQ(nq + 1) end or nil, function(tip)
      tip:AddLine("Quests under the step", 1, 1, 1)
      tip:AddLine("The quests you hold that the step and the next two do not name, the route's first. 0 shows none.", 0.85, 0.85, 0.85, true)
    end)
  -- the step frame stands on the world with no backdrop (Cute's look); this brings Cute's flat one behind it, as the
  -- frame's own menu does (StepFrame.lua SF.Apply reads guide.backdrop). Greyed while the frame is off
  col:Check("Backdrop behind the step frame", s.guide.backdrop == true, s.guide.frame == true, function(on)
    s.guide.backdrop = on and true or nil
    if E.StepFrame then E.StepFrame.Apply() end
  end)
  col:Check("Direction arrow", s.arrow == true, true, function(on) if E.Arrow then E.Arrow:Set(on) else s.arrow = on end end)
  -- (6.1.1) the game's quest tracker out of sight while the step frame shows (the engine's StepFrame.lua SF.Tracker)
  -- (greyed while the step frame is off: the tracker is the game's then)
  col:Check("Hide the game's quest tracker with the step frame", s.guide.hideTracker ~= false, s.guide.frame == true, function(on) s.guide.hideTracker = on; if E.StepFrame then E.StepFrame.Apply() end end)
  local names, current = {}, "Off"
  for _, a in ipairs(ACCEPT) do names[#names + 1] = a[1]; if s.autoAccept == a[2] then current = a[1] end end
  col:Choice("Accept for me", names, current, function(v) for _, a in ipairs(ACCEPT) do if a[1] == v then s.autoAccept = a[2] end end end)
  col:Check("Hand finished quests in for me", s.autoTurnIn == true, true, function(on) s.autoTurnIn = on end)
  col:Check("Progress in mob tooltips", s.tipProgress ~= false, true, function(on) s.tipProgress = on end)
  -- the line in chat as a quest is handed in, complete or dropped (the engine's sayXP, read in its Core.lua; off since the
  -- launch round, as QuestBank's Guide section and the step frame's menu have it). Nine rows: the section's most
  col:Check("Say XP after each hand-in", s.sayXP == true, true, function(on) s.sayXP = on and true or false end, nil, function(tip)
    tip:AddLine("Say XP after each hand-in", 1, 1, 1)
    tip:AddLine("A line in chat as you hand a quest in, with the XP it paid, and as a quest is complete or leaves your log. Off, chat stays quiet: the step frame and the Route page show the XP.", 0.85, 0.85, 0.85, true)
  end)
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

-- (the band's Invite buttons follow combat and your group; the pick follows your quests)
Cute:RegisterModule({
  id = "quests", addon = ADDON, title = "Quests", order = 21, window = "quests", base = true,
  notes = "The step now, the guild's dungeon pick, and the places worth your time by XP a minute.",
  page = P.Draw, settings = P.Settings, onToggle = P.Toggle,
  events = { QUEST_LOG_UPDATE = redraw, QUEST_ACCEPTED = redraw, QUEST_TURNED_IN = redraw, PLAYER_LEVEL_UP = redraw, ZONE_CHANGED_NEW_AREA = redraw,
    PLAYER_REGEN_DISABLED = redraw, PLAYER_REGEN_ENABLED = redraw, GROUP_ROSTER_UPDATE = redraw },
})

-- Settings > Data you share (the Cute group): what the engine notes and shares, and where it goes. The guild never: the
-- engine's guild sharing is off under Cute (Bridge.lua), Cute's own channel carries what the guild sees
if E then
  Cute.AddSection({ id = "share", title = "Data you share", group = "cute", order = 5, draw = function(_, col)
    local s = E:Settings()
    col:Head("Data you share")
    -- (the engine's own switches: Game.lua's notes, Survey.lua's questions to the game; QuestBank's Settings has the same)
    col:Check("Note what the game shows for foreverrank.com", s.noteGame ~= false, true, function(on) if E.Game and E.Game.SetOn then E.Game.SetOn(on) else s.noteGame = on end end,
      nil, function(tip)
        -- (the words of QuestBank's own box, Settings > Data you share: the finds, Finds.lua, are noted under it too)
        tip:AddLine("Note what the game shows", 1, 1, 1)
        tip:AddLine("Tooltips of the items you loot, carry or see, the spells you know, and which creatures and chests dropped what you loot (by id), and where you found them, with no names in them, so foreverrank.com can list them. Unticking forgets what was noted.", 0.85, 0.85, 0.85, true)
      end)
    col:Check("Learn quests from the game", s.survey ~= false, true, function(on) if E.Survey and E.Survey.SetOn then E.Survey.SetOn(on) else s.survey = on end end)
    col:Check("Share your quests with your party", s.share.party ~= false, true, function(on) s.share.party = on end)
    -- (where it comes from, once Cute's page offers Cute-Uploader.zip at release: build.py check_uploader_note holds
    -- the two together)
    col:Note("The QuestBank Uploader sends what you found in the world to foreverrank.com, never a name or anything about your guild.")
  end })
end
