-- SPDX-License-Identifier: GPL-3.0-or-later
-- The quest to read: a quest row's click, anywhere in the quest window (its lists, the step band), gives way to the
-- quest itself in place of the list; Back returns to the list where it was. It holds the title in its level's colour,
-- the level and the XP at yours, the game's own text for a quest in your log (GetQuestLogQuestText(questLogIndex), as
-- Mainline/QuestMapFrame.lua:40 reads it) or what the catalog knows of one you do not hold, the objectives with their
-- progress, the chain, the rewards, the hand-in or the giver, and its buttons: Show on arrow, Share (in a group, for a
-- quest the game lets you share: C_QuestLog.IsPushableQuest and QuestLogPushQuest(questLogIndex), as QuestUtils.lua:358
-- does) and Abandon (the engine's UI.ConfirmAbandon: the game's own words, your click); a quest not taken has Show on
-- arrow and Pick-up list. Never QuestMapFrame_OpenToQuestDetails, which opens the game's panel.
-- The click, everywhere a quest is a row (QB.RowClick): read it; Ctrl-click: show it on the arrow; Shift-click: on (or
-- off) the pick-up list, or its link in an open chat box; right-click: its menu.
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local R = {}
QB.Reader = R

local function callable(name) return type(_G[name]) == "function" end
local function plain(v) if issecretvalue and issecretvalue(v) then return nil end return v end
local DOT = " \194\183 "

-- the window's quest to read: ui.reading = { id, scroll } while one is open
function R.Open(ui) return ui.reading ~= nil end
function R.Read(ui, q)
  if not (ui and q) then return end
  ui.reading = { id = q.id, scroll = ui.scroll.bar:GetValue() or 0, page = ui.page }
  ui.scrollTo = 0
  ui:Draw()
end
function R.Back(ui)
  local r = ui.reading
  ui.reading = nil
  if r then ui.scrollTo = r.scroll end
  ui:Draw()
end
-- a tab change leaves the quest it was reading
function R.Left(ui) if ui.reading and ui.reading.page ~= ui.page then ui.reading = nil end end

-- a quest row's click, everywhere (the quest window's lists, the band's step)
function QB.RowClick(ui, q, st, which)
  if not (E and q) then return end
  if which == "RightButton" then E.UI.QuestClick(q, st, "RightButton") return end
  if (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown()) then
    -- (the engine's own click: Shift links it or puts it on the pick-up list; with Ctrl, the arrow)
    E.UI.QuestClick(q, st, "LeftButton")
    return
  end
  R.Read(ui, q)
end

-- the quest's level colour, the game's (GetQuestDifficultyColor), white where the client has none
local function levelColor(level)
  if callable("GetQuestDifficultyColor") then
    local ok, c = pcall(GetQuestDifficultyColor, level or 1)
    if ok and type(c) == "table" and c.r then return { c.r, c.g, c.b } end
  end
  return { 0.96, 0.96, 0.96 }
end
-- the game's text of a quest in your log, by its log index
local function logText(index)
  if not (index and callable("GetQuestLogQuestText")) then return nil end
  local ok, description = pcall(GetQuestLogQuestText, index)
  description = ok and plain(description) or nil
  return type(description) == "string" and description ~= "" and description or nil
end
-- whether the game lets you share it now: in a group, and pushable (QuestMapFrame.lua:1162)
local function shareable(id)
  local L = C_QuestLog
  if not (L and type(L.IsPushableQuest) == "function" and callable("IsInGroup")) then return false end
  local okG, grouped = pcall(IsInGroup)
  local okP, pushable = pcall(L.IsPushableQuest, id)
  return okG and plain(grouped) == true and okP and plain(pushable) == true
end

function R.Draw(ui, scroll)
  local K, ROW = ui.COLORS, ui.ROW
  local w = scroll:Width()
  local q = E.Quest.Get(ui.reading.id)
  -- the band: Back on the left, where the quest stands on the right
  local log = q and E.state.log[q.id]
  local back = ui.bandButtons:Get()
  back:ClearAllPoints(); back:SetPoint("TOPLEFT", 0, -3); back:SetSize(70, 20)
  back:SetLabel("Back"); back:SetOn(true)
  back:SetScript("OnClick", Cute.Safe(function() R.Back(ui) end, "reader: back"))
  back:SetScript("OnEnter", nil); back:SetScript("OnLeave", nil)
  local where = ui.bandLabels:Get()
  where:ClearAllPoints(); where:SetPoint("TOPRIGHT", -4, -7); where:SetWidth(200); where:SetJustifyH("RIGHT")
  ui.Color(where, K.DIM)
  ui.FitText(where, log and (log.complete and "ready to hand in" or "in your log") or "not taken", 196)
  ui:SetBand(ROW + 8)
  if not q then
    local l = ui.labels:Get()
    l:ClearAllPoints(); l:SetPoint("TOPLEFT", 6, -6); l:SetWidth(w - 12); l:SetJustifyH("LEFT")
    ui.Color(l, K.MUTE); l:SetText("This quest is not in the catalog.")
    scroll:SetContentHeight(30)
    return
  end
  local y = 6
  local function line(s, c, size, x, width)
    local l = ui.labels:Get()
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", x or 6, -y)
    l:SetWidth(width or (w - 12))
    l:SetJustifyH("LEFT")
    l:SetWordWrap(true)
    l:SetFont(ui.FONT, size or 13, "")
    l.cuteSize = size or 13
    ui.Color(l, c or K.INK)
    l:SetText(s or "")
    local h = math.max((size or 13) + 2, math.ceil(l:GetStringHeight() or 0))
    y = y + h + 2
    return l
  end
  local function head(s) y = y + 8; line(s, K.DIM, 11) end
  local level = E.state.level or 1
  line(q.name, levelColor(q.lvl), 15)
  local xp = E.Model and E.Model.XpAt and E.Model.XpAt(q, level) or nil
  line(string.format("Level %d%s%s", q.lvl or 0, q.group and (DOT .. "group") or "",
    (xp and xp > 0) and (DOT .. E.Comma(xp) .. " XP at level " .. level) or ""), K.DIM, 11)
  -- the game's own words for a quest you hold; what the catalog knows of one you do not
  local text = log and logText(log.index)
  if text then y = y + 4; line(text, K.INK, 13) end
  local L = ui.Look
  if log and log.objectives and #log.objectives > 0 then
    head("Objectives")
    -- (each its cursor glyph, a finished one the ready check and the muted grey: the windows' look)
    for slot, o in ipairs(log.objectives) do
      local t = plain(o.text) or ""
      local done = plain(o.done) == true
      local glyph = L and L.Inline(done and "ready" or QB.ObjKind(q.id, slot, t), 14) or ""
      line(glyph .. " " .. t, done and K.MUTE or K.INK, 13, 8, w - 14)
    end
  elseif not log and q.tip then
    head("What it asks")
    line(q.tip, K.INK, 13)
  end
  local chain = E.Quest.ChainText and E.Quest.ChainText(q)
  local nextSteps = q.nextSteps
  if chain or nextSteps then
    head("Chain")
    if chain then line((chain:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), K.INK, 13) end
    -- (the next steps this character can take, as the engine's tooltip lists them: Lists.lua, Q.ForMe; a quest that
    -- leads on to each class's letter names this class's alone)
    local names = {}
    for _, id in ipairs(type(nextSteps) == "table" and nextSteps or {}) do
      local nq = E.Quest.Get(id)
      if nq and E.Quest.ForMe(nq) then names[#names + 1] = E.Quest.Label(id) end
    end
    if #names > 0 then line("Leads to " .. table.concat(names, ", "), K.INK, 13) end
  end
  -- the rewards, an icon and a name each (the item's own icon, 134400 until the client has it), in the engine's
  -- tooltip's groups (Lists.lua UI.RewardLines): what comes with the quest, a choice, and a list that does not say
  -- which; the Classic database's said so, DIM (the design's section 8)
  local rw, how = E.Quest.Rewards(q)
  -- (the icons on a host of the reader's own, hidden with it when the list comes back: UI:Host)
  local host = Cute.Host(ui, "reader")
  host:ClearAllPoints(); host:SetPoint("TOPLEFT", 0, 0); host:SetSize(w, 10)
  host.icons = host.icons or {}
  for _, t in ipairs(host.icons) do t:Hide(); if t.edge then t.edge:Hide() end end
  local n, any = 0, false
  local function items(title, list)
    if type(list) ~= "table" or #list == 0 then return end
    any = true
    head(title)
    for i = 1, math.min(6, #list) do
      local id = list[i]
      n = n + 1
      local name, _, _, icon = E.API.ItemInfo(id)
      local t = host.icons[n]
      if not t then
        t = host:CreateTexture(nil, "ARTWORK"); t:SetSize(28, 28); t:SetTexCoord(0.08, 0.92, 0.08, 0.92); host.icons[n] = t
        -- (a 1 px edge in the item's quality colour, as the windows draw an item)
        t.edge = host:CreateTexture(nil, "BORDER"); t.edge:SetPoint("TOPLEFT", t, "TOPLEFT", -1, 1); t.edge:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 1, -1)
      end
      t:ClearAllPoints(); t:SetPoint("TOPLEFT", 7, -y - 1); t:SetTexture(icon or 134400); t:Show()
      local okQ, qual = pcall(C_Item and C_Item.GetItemQualityByID or error, id)
      qual = okQ and type(qual) == "number" and qual or 1
      local e = L and L.QualityEdge(qual) or { 0, 0, 0 }
      t.edge:SetColorTexture(e[1], e[2], e[3], 1); t.edge:Show()
      local y0 = y
      y = y + 7
      line(name or ("Item " .. id), L and L.QualityName(qual) or K.INK, 13, 42, w - 48)
      y = math.max(y, y0 + 32)
    end
  end
  items("You get", rw and rw.r)
  items((rw and rw.c and #rw.c > 1) and "Choose one" or "Reward", rw and rw.c)
  items("Rewards include", rw and rw.u)
  if any and how == "catalog" and E.Data.RCLASSIC and E.Data.RCLASSIC[q.id] then
    y = y + 2
    line("Rewards from Classic data (may differ in Forever).", K.DIM, 11)
  end
  -- the hand-in, or the giver
  local npc = log and q.turn or (q.give or q.turn)
  if npc and npc.n then
    head(log and "Hand in" or "From")
    local place = npc.place or (E.Data.MAPNAME and E.Data.MAPNAME[npc.m])
    -- (the hand-in's glyph or the offer's, as the map draws them)
    local glyph = L and L.Inline(log and "turnin" or "accept", 16) or ""
    line(glyph .. " " .. npc.n .. (place and (DOT .. place) or ""), K.INK, 13)
  end
  -- its buttons
  y = y + 10
  local st = E:Status(q)
  local acts = {}
  acts[#acts + 1] = { "Show on arrow", function() E.UI.QuestClick(q, st, "LeftButton") end }
  if log then
    if shareable(q.id) then acts[#acts + 1] = { "Share", function() if callable("QuestLogPushQuest") then QuestLogPushQuest(log.index) end end } end
    acts[#acts + 1] = { "Abandon", function() E.UI.ConfirmAbandon(q) end }
  elseif st.code ~= "done" then
    acts[#acts + 1] = { E:IsAdded(q.id) and "Off the pick-up list" or "Pick-up list", function() E:ToggleAdd(q.id); ui:Draw() end }
  end
  local x = 6
  for _, a in ipairs(acts) do
    local b = ui.buttons:Get()
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", x, -y)
    b:SetSize(110, 22)
    b:SetLabel(a[1])
    b:SetOn(true)
    b:SetScript("OnClick", Cute.Safe(a[2], "reader: " .. a[1]))
    x = x + 116
  end
  y = y + 30
  scroll:SetContentHeight(y + 8)
end
