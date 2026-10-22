-- SPDX-License-Identifier: GPL-3.0-or-later
-- CardFrame: CuteCardFrame, the card screen (the run report's design, 8.3 and 8.4). Report mode: a run's header
-- (the label, the place, the day and the members, the facts on the right; a dungeon's or a raid's cover where
-- Cute_Quest gives one), up to five cards centred, the gone-early line, a raid's mentions, and Send to party, History
-- and Close (a test report: Print to chat, Next and Close). A plain frame, strata DIALOG, dragged by its header, closed
-- by Esc (UISpecialFrames) or Close; the windows design's tokens and type. Width 32 + n x 180 + (n - 1) x 12 units for
-- n cards, at least 420; height 560, a raid's 662; scaled to fit where the screen is narrower. Announcement mode (CF:Announce):
-- a published set (GUILD NEWS, GUILD FIRST, NEW RECORD, HALL OF FAME, HALL OF SHAME), who published it and when, a
-- hall's Members ranked, its cards, News and Close (a record this client showed itself says so instead of who
-- published it); Preview mode: an officer's set before it goes, the guild chat line it would post under the cards,
-- Publish and Back. A look (a record's Preview on the Records chip): its card as it stands, Close alone.
local _, C = ...
local CF = { cards = {} }
C.CardFrame = CF

local W_MIN, H, MENTIONS_H = 420, 560, 102
local H_SET = H -- (an announcement's height: a report's without mentions)
local WHITE, INK, DIM, MUTE = { 0.96, 0.96, 0.96 }, { 0.86, 0.86, 0.86 }, { 0.58, 0.58, 0.58 }, { 0.52, 0.52, 0.52 }
local BG, LINE = { 0.035, 0.035, 0.035 }, { 0.2, 0.2, 0.2 }
local DOT = " \194\183 " -- (a middle dot in Windows-1252; the file stays ASCII)
local BD = BackdropTemplateMixin and "BackdropTemplate" or nil
local LABEL = { d = "DUNGEON RECAP", r = "RAID RECAP", g = "GROUP RECAP" }
local function color(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end
local function hex(c) return C.UI.Hex(c) end
local function callable(name) return type(_G[name]) == "function" end
local function call(name, ...) if not callable(name) then return nil end return C.Get(_G[name], ...) end
local function A() return C.Awards end

function CF.Width(n) return math.max(W_MIN, 32 + n * 180 + math.max(0, n - 1) * 12) end
function CF.Height(rep) return (rep and rep.mentions and #rep.mentions > 0) and (H + MENTIONS_H) or H end

local function build()
  if CF.frame then return CF.frame end
  local U = C.UI
  local f = CreateFrame("Frame", "CuteCardFrame", UIParent, BD)
  CF.frame = f
  f:SetSize(980, H)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  U.Skin(f, BG, 0.97)
  f:Hide()
  tinsert(UISpecialFrames, "CuteCardFrame")
  -- the header: dragged by it
  local head = CreateFrame("Frame", nil, f)
  head:SetPoint("TOPLEFT", 1, -1)
  head:SetPoint("TOPRIGHT", -1, -1)
  head:SetHeight(71)
  head:EnableMouse(true)
  head:RegisterForDrag("LeftButton")
  head:SetScript("OnDragStart", function() f:StartMoving() end)
  head:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
  CF.head = head
  local rule = U.Flat(f, "ARTWORK", LINE, 1)
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", 1, -72)
  rule:SetPoint("TOPRIGHT", -1, -72)
  CF.cover = f:CreateTexture(nil, "ARTWORK")
  CF.cover:SetSize(130, 72)
  CF.cover:SetPoint("TOPLEFT", 1, -1)
  CF.atlas = f:CreateTexture(nil, "ARTWORK")
  CF.atlas:SetSize(20, 20)
  CF.label = U.Text(f, 11, WHITE, "LEFT", 300)
  CF.title = U.Text(f, 20, WHITE, "LEFT", 420)
  CF.sub = U.Text(f, 11, DIM, "LEFT", 420)
  CF.facts = {}
  for i = 1, 4 do
    local v = U.Text(f, 15, WHITE, "RIGHT", 76)
    local l = U.Text(f, 11, DIM, "RIGHT", 76)
    CF.facts[i] = { v = v, l = l }
  end
  CF.x = U.Button(f, "x", 20, 20)
  CF.x:SetPoint("TOPRIGHT", -8, -8)
  CF.x:SetScript("OnClick", function() f:Hide() end)
  -- the cards
  for i = 1, 5 do CF.cards[i] = C.Cards.Make(f) end
  CF.gone = U.Text(f, 11, DIM, "LEFT", 900)
  CF.mentions = {}
  for i = 1, 10 do CF.mentions[i] = U.Text(f, 11, INK, "LEFT", 466) end
  CF.posted = U.Text(f, 11, DIM, "RIGHT", 220)
  CF.buttons = {}
  for i = 1, 3 do
    local b = U.Button(f, "", 90, 24)
    b:SetScript("OnClick", function(self) if self.fn then self.fn() end end)
    b:SetScript("OnEnter", C.Safe(function(self)
      if not self.why then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.why, 1, 1, 1, true)
      GameTooltip:Show()
    end, "card screen: tooltip"))
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    CF.buttons[i] = b
  end
  return f
end

-- a member's name as this client knows it, and their class colour code
local function nameOf(rep, sfx)
  local m = rep.members and rep.members[sfx]
  return m and m.n or nil
end
local function classed(rep, sfx)
  local m = rep.members and rep.members[sfx]
  local name = m and m.n or "?"
  return "|cff" .. hex(C.UI.ClassColor(m and m.c)):sub(5) .. name .. "|r"
end
-- the day, the time and the members, as the header's line says them: "Tuesday 21:40, a dot, 5 members"
local function when(rep)
  local t = rep.start
  local s = (date and t) and date("%A %H:%M", t) or ""
  return s .. DOT .. rep.n .. (rep.n == 1 and " member" or " members")
end

-- the Send to party button's state (8.4): greyed with the reason where the game blocks the post, the report is not
-- ready to go, or it is not the run that just ended with this group (Earlier run, Not this group)
function CF.SendState(rep)
  if not rep then return false, "No report" end
  if rep.test then return true end
  if not (C.RunComm.Channel()) then return false, "Not in a group" end
  if C.Runs.sentFor == rep.id then return false, "Sent" end
  local fresh, why = C.Runs.Postable(rep)
  if not fresh then return false, why end
  if not C.Policy:Settled() then return false, "Waiting for Guild Info" end
  local IE = C_InstanceEncounter
  if call("InCombatLockdown") == true or (type(IE) == "table" and type(IE.IsEncounterInProgress) == "function" and C.Get(IE.IsEncounterInProgress) == true) then
    return false, "After the fight"
  end
  local CI = C_ChatInfo
  if type(CI) == "table" and type(CI.InChatMessagingLockdown) == "function" and C.Get(CI.InChatMessagingLockdown) == true then return false, "Outside the instance" end
  return true
end

-- the report on the screen. opts.test: the test report (TEST RECAP; Print to chat, Next, Close)
function CF:Report(rep, opts)
  if type(rep) ~= "table" then return end
  opts = opts or {}
  local f = build()
  local U = C.UI
  -- (as the policy held now lets it show: a field closed since takes its cards off, Runs.lua R.Visible)
  rep = C.Runs.Visible(rep)
  self.rep, self.test, self.set, self.publishButton = rep, opts.test, nil, nil
  local cards = rep.cards or {}
  -- the header: the cover (a dungeon's or a raid's, where Cute_Quest gives one: Band.lua Cute.QuestCover, by the
  -- place's name, cut for the 130 x 72 cover) or the atlas beside the label
  local cover
  if rep.kind ~= "g" and rep.inst and Cute and type(Cute.QuestCover) == "function" then
    local okC, c = pcall(Cute.QuestCover, rep.inst, rep.place, 130, 72)
    cover = okC and type(c) == "table" and c or nil
  end
  local x0 = 16
  if cover then
    local ok = pcall(function()
      CF.cover:SetTexture(cover.texture or cover[1])
      local tc = cover.texcoords or cover[2]
      if type(tc) == "table" then CF.cover:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
    end)
    CF.cover:SetShown(ok)
    if ok then x0 = 146 end
  else CF.cover:Hide() end
  local label = opts.test and "TEST RECAP" or (LABEL[rep.kind] or "RECAP")
  local labelColor = (rep.kind == "g") and WHITE or C.Cards.GROUP
  CF.atlas:ClearAllPoints()
  if not cover and rep.kind ~= "g" then
    CF.atlas:SetAtlas(rep.kind == "r" and "Raid" or "Dungeon")
    CF.atlas:SetPoint("TOPLEFT", x0, -8)
    CF.atlas:Show()
    CF.label:SetPoint("TOPLEFT", x0 + 24, -12)
  else
    CF.atlas:Hide()
    CF.label:SetPoint("TOPLEFT", x0, -12)
  end
  color(CF.label, labelColor)
  CF.label:SetText(label)
  CF.title:ClearAllPoints(); CF.title:SetPoint("TOPLEFT", x0, -30)
  CF.sub:ClearAllPoints(); CF.sub:SetPoint("TOPLEFT", x0, -54)
  -- the facts on the right, 76 units each, ending 40 units from the edge
  local facts = rep.kind == "g" and { { A().Clock(rep.dur), "Time" }, { tostring(rep.wipes or 0), "Wipes" }, { tostring(rep.deaths or 0), "Deaths" } }
    or { { (rep.bosses or 0) .. "/" .. math.max(rep.known or 0, rep.bosses or 0), "Bosses" }, { A().Clock(rep.dur), "Time" }, { tostring(rep.wipes or 0), "Wipes" }, { tostring(rep.deaths or 0), "Deaths" } }
  local factsW = #facts * 76
  -- the width: the cards', or wider where the header's place and line need it (never past five cards' 980), so a
  -- report of two never cuts the place's name
  local width = CF.title.GetUnboundedStringWidth or CF.title.GetStringWidth
  CF.title:SetText(rep.place or "?"); CF.sub:SetText(when(rep))
  local need = x0 + math.max(width(CF.title), width(CF.sub)) + 20 + factsW + 40
  local w = math.max(CF.Width(#cards), math.min(980, math.ceil(need)))
  local h = CF.Height(rep)
  f:SetSize(w, h)
  -- (scaled to fit a narrow screen)
  local uw = UIParent and UIParent:GetWidth() or 1600
  f:SetScale((uw > 0 and uw < w + 40) and (uw - 40) / w or 1)
  local right = w - 40
  for i = 1, 4 do
    local fc, d = CF.facts[i], facts[i]
    if d then
      local x = right - (#facts - i + 1) * 76
      fc.v:ClearAllPoints(); fc.v:SetPoint("TOPLEFT", x, -18); fc.v:SetWidth(76); fc.v:SetText(d[1]); fc.v:Show()
      fc.l:ClearAllPoints(); fc.l:SetPoint("TOPLEFT", x, -40); fc.l:SetWidth(76); fc.l:SetText(d[2]); fc.l:Show()
    else fc.v:Hide(); fc.l:Hide() end
  end
  -- (the title and its line take the room the facts leave)
  local room = right - factsW - x0 - 12
  CF.title:SetWidth(room); CF.sub:SetWidth(room)
  U.FitText(CF.title, rep.place or "?", room - 4)
  U.FitText(CF.sub, when(rep), room - 4)
  -- the cards, centred
  local total = #cards * 180 + math.max(0, #cards - 1) * 12
  local cx = math.floor((w - total) / 2)
  for i = 1, 5 do
    local card = CF.cards[i]
    local c = cards[i]
    if c then
      local a = A().Of(c[2])
      local m = rep.members and rep.members[c[1]] or {}
      local v, what = A().Show(c[2], c[3])
      card:ClearAllPoints()
      card:SetPoint("TOPLEFT", cx + (i - 1) * 192, -88)
      C.Cards.Fill(card, { guid = m.g or CF.GuidOf(rep, c[1]), name = m.n or "?", class = m.c, race = m.r, sex = m.s, kind = a and a.kind,
        label = a and A().KINDS[a.kind] or "", title = a and a.title or c[2], line = a and a.quip or "", value = v, valueLabel = what, headline = i == 1 and not rep.test and (a and a.kind ~= "thanks"),
        tip = function(tip) CF.Tip(tip, rep, c) end })
    else card:Hide() end
  end
  -- the gone-early line, or a raid's mentions in two columns of five
  local y = 472
  local gone = rep.gone or {}
  if #gone > 0 then
    local names = {}
    for i = 1, math.min(8, #gone) do names[i] = classed(rep, gone[i]) end
    local s = "Gone before the end: " .. table.concat(names, ", ") .. (#gone > 8 and (" and " .. (#gone - 8) .. " more") or "")
    CF.gone:ClearAllPoints(); CF.gone:SetPoint("TOPLEFT", 16, -y); CF.gone:SetWidth(w - 32)
    CF.gone:SetText(s); CF.gone:Show()
  else CF.gone:Hide() end
  local mentions = rep.mentions or {}
  for i = 1, 10 do
    local fs, mn = CF.mentions[i], mentions[i]
    if mn then
      local a = A().Of(mn[2])
      local v, what = A().Show(mn[2], mn[3])
      local kc = a and C.Cards.KindColor(a.kind) or WHITE
      local col, row = (i - 1) >= 5 and 1 or 0, (i - 1) % 5
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", 16 + col * 474, -(y + (#gone > 0 and 18 or 0) + row * 18))
      fs:SetWidth(466)
      U.FitText(fs, "|cff" .. hex(kc):sub(5) .. (a and a.title or mn[2]) .. "|r" .. DOT .. classed(rep, mn[1]) .. DOT .. "|cff949494" .. v .. " " .. what .. "|r", 462)
      fs:Show()
    else fs:Hide() end
  end
  -- the buttons, from the right: Close, History, Send to party (a test: Close, Next, Print to chat)
  local by = h - 58
  local list
  if opts.test then
    list = { { "Close", 80, function() f:Hide() end }, { "Next", 90, function() if C.RunsUI and C.RunsUI.Test then C.RunsUI.Test(rep.kind == "r", true) end end },
      { "Print to chat", 120, function() if C.RunsUI then C.RunsUI.PrintToChat(rep) end end } }
  else
    list = { { "Close", 80, function() f:Hide() end }, { "History", 90, function() f:Hide(); C.UI:Open("runs") end },
      { "Send to party", 120, function() if C.RunsUI then C.RunsUI.SendToParty(rep) end end } }
  end
  local bx = w - 16
  for i, d in ipairs(list) do
    local b = CF.buttons[i]
    b:Show()
    b:SetWidth(d[2])
    bx = bx - d[2]
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", bx, -by)
    b:SetLabel(d[1])
    b.fn = d[3]
    b.why = nil
    b:SetOn(true)
    bx = bx - 8
  end
  CF.sendButton = (not opts.test) and CF.buttons[3] or nil
  CF.posted:ClearAllPoints()
  CF.posted:SetPoint("TOPRIGHT", f, "TOPLEFT", bx, -(by + 6))
  CF.posted:SetText("")
  CF:DrawSend()
  f:Show()
  CF.Watch()
end

-- Send to party's state follows the game while the screen shows (an encounter, the lockdown, the group, the policy
-- settling, a loading screen): drawn again once a second, one timer at a time, none while the screen is closed
function CF.Watch()
  if CF.watching then return end
  CF.watching = true
  C_Timer.After(1, C.Safe(function()
    CF.watching = false
    if not (CF.frame and CF.frame:IsShown() and CF.sendButton) then return end
    CF:DrawSend()
    CF.Watch()
  end, "card screen: Send to party"))
end

-- the GUID behind a suffix: the run's member, else the roster's
function CF.GuidOf(rep, sfx)
  local run = C.Runs.run
  local m = run and run.members and run.members[sfx]
  if m then return m.g end
  if sfx == (C.MyGUID() or ""):match("([^%-]+)$") then return C.MyGUID() end
  return C.Roster and C.Roster.GuidBySuffix and C.Roster:GuidBySuffix(sfx) or nil
end

-- a card's tooltip: its rule in one line, and the member's other values this client may show
local RULE = {
  HD = "The most damage, at least 1.25 fair shares", LF = "The most healing, at least 1.25 fair shares", OS = "The most interrupts, at least 5 (8 in a raid)",
  CW = "The most dispels, at least 5 (10 in a raid)", IW = "The most damage taken, no deaths, two bosses or more", BW = "The most absorbs, at least 1.25 fair shares",
  TJ = "Top two in damage and at least 15% of the healing", NS = "No deaths, three or more in the group", PW = "Quests handed in that another member handed in too, at least 3",
  LB = "The best drop, rare or better", FH = "A roll of 100", TB = "The most yards, 1.2 times the median", NR = "The most lines typed, at least 15",
  DG = "A level gained", CM = "The most gold looted", WL = "The most consumables used, at least 3", FI = "The most deaths, at least 3",
  OA = "The run's first death", SP = "The longest dead, three minutes or more", WF = "The most avoidable damage, 1.5 times the median",
  LO = "Asked where everyone was", PG = "The most jumps, at least 100", NA = "The most need rolls, at least 4", BD = "The lowest roll, 5 or less",
  GC = "In the run with us", SH = "Deaths at most the group's middle" }
CF.RULE = RULE
function CF.Tip(tip, rep, c)
  local a = A().Of(c[2])
  tip:AddLine((a and a.title or c[2]) .. ": " .. (nameOf(rep, c[1]) or "?"), 1, 1, 1)
  if RULE[c[2]] then tip:AddLine(RULE[c[2]] .. ".", 0.85, 0.85, 0.85, true) end
end

-- Send to party's state on the button: greyed with the reason, or live; "Brann posted" beside it where another
-- member's 2P came (the button stays live: nobody can tell a post went)
function CF:DrawSend()
  local b = self.sendButton
  if not (b and self.frame and self.rep) then return end
  local ok, why = CF.SendState(self.rep)
  b:SetOn(ok and true or false)
  b:SetLabel(ok and "Send to party" or why)
  b.why = ok and "Posts the report in your group's chat as plain text, for those without Cute." or nil
  local posted = C.Runs.posted
  if posted and posted.id == self.rep.id then self.posted:SetText(posted.by .. " posted") else self.posted:SetText("") end
end
function CF:Posted(id) if self.frame and self.frame:IsShown() and self.rep and self.rep.id == id then self:DrawSend() end end

----------------------------------------------------------------------------
-- announcement and preview (8.3): a set from the officers (Halls.lua). The header: its label in its colour (GUILD
-- FIRST, NEW RECORD and HALL OF FAME the cards' STAR, HALL OF SHAME their BLOOPER, GUILD NEWS white), its title, who
-- published it and when; a hall's Members ranked on the right. Its cards centred, a first with the white edge. The
-- buttons from the right: Close and News; a preview Back and Publish, with the guild chat line it would post under the
-- cards; a test Close alone
----------------------------------------------------------------------------
local FACT_W = 100 -- ("Members ranked" at 11)
-- the guild chat line under a preview's cards: the line Publish posts, or why none goes now
local function chatText(set)
  local HL = C.Halls
  if not HL.ChatState() then return "No guild chat line: the game holds chat back here." end
  return "Guild chat: " .. HL.ChatLine(set)
end
function CF:Announce(set, opts)
  opts = opts or {}
  if type(set) ~= "table" then return end
  local U, HL = C.UI, C.Halls
  -- (a set held, as the policy held now lets it show: a card closed since leaves it, one left with none shows nothing,
  -- Halls.lua H.Visible; a preview, a test and a look are this client's own, shown as they are)
  if not (opts.preview or opts.test or opts.look) then
    set = HL.Visible(set)
    if not set then if self.frame then self.frame:Hide() end return end
  end
  local f = build()
  self.rep, self.test, self.set, self.sendButton, self.publishButton = nil, opts.test, set, nil, nil
  self.preview = opts.preview
  local cards = set.cards or {}
  CF.cover:Hide(); CF.atlas:Hide()
  local x0 = 16
  CF.label:ClearAllPoints(); CF.label:SetPoint("TOPLEFT", x0, -12)
  color(CF.label, HL.HeadColor(set.kind))
  CF.label:SetText((HL.HEAD[set.kind] or HL.HEAD.n) .. (opts.preview and " PREVIEW" or ""))
  CF.title:ClearAllPoints(); CF.title:SetPoint("TOPLEFT", x0, -30)
  CF.sub:ClearAllPoints(); CF.sub:SetPoint("TOPLEFT", x0, -54)
  local sub
  if opts.preview then sub = "Not published yet"
  elseif opts.test then sub = "A test: nothing is sent or kept"
  elseif opts.look then sub = "The card this record gives now: nothing is sent"
  elseif set.rec then sub = "Guild record" .. ((set.got or set.at) and (DOT .. (U.Ago(set.got or set.at) or "")) or "")
  else sub = "Published by " .. (set.by or "?") .. ((set.got or set.at) and (DOT .. (U.Ago(set.got or set.at) or "")) or "") end
  local facts = ((set.kind == "h" or set.kind == "s") and tonumber(set.ranked)) and { { tostring(set.ranked), "Members ranked" } } or {}
  local factsW = #facts * FACT_W
  local width = CF.title.GetUnboundedStringWidth or CF.title.GetStringWidth
  CF.title:SetText(set.title or ""); CF.sub:SetText(sub)
  local need = x0 + math.max(width(CF.title), width(CF.sub)) + 20 + factsW + 40
  -- (a preview's guild chat line, whole on two lines at most: the frame as wide as two lines of it need, and a long
  -- word's width more, which a line break may leave at the end of the first)
  local chat = opts.preview and set.chat and chatText(set) or nil
  if chat then
    if not CF.chat then CF.chat = U.Text(f, 11, DIM, "LEFT", 900); CF.chat:SetWordWrap(true) end
    CF.chat:SetText(chat)
    need = math.max(need, math.ceil(width(CF.chat) / 2) + 80 + 32)
  end
  local w = math.max(CF.Width(#cards), math.min(980, math.ceil(need)))
  f:SetSize(w, H_SET)
  local uw = UIParent and UIParent:GetWidth() or 1600
  f:SetScale((uw > 0 and uw < w + 40) and (uw - 40) / w or 1)
  local right = w - 40
  for i = 1, 4 do
    local fc, d = CF.facts[i], facts[i]
    if d then
      local x = right - (#facts - i + 1) * FACT_W
      fc.v:ClearAllPoints(); fc.v:SetPoint("TOPLEFT", x, -18); fc.v:SetWidth(FACT_W); fc.v:SetText(d[1]); fc.v:Show()
      fc.l:ClearAllPoints(); fc.l:SetPoint("TOPLEFT", x, -40); fc.l:SetWidth(FACT_W); fc.l:SetText(d[2]); fc.l:Show()
    else fc.v:Hide(); fc.l:Hide() end
  end
  local room = right - factsW - x0 - 12
  CF.title:SetWidth(room); CF.sub:SetWidth(room)
  U.FitText(CF.title, set.title or "", room - 4)
  U.FitText(CF.sub, sub, room - 4)
  local total = #cards * 180 + math.max(0, #cards - 1) * 12
  local cx = math.floor((w - total) / 2)
  for i = 1, 5 do
    local card, c = CF.cards[i], cards[i]
    if c then
      card:ClearAllPoints()
      card:SetPoint("TOPLEFT", cx + (i - 1) * 192, -88)
      C.Cards.Fill(card, { guid = c.guid, name = c.name or "?", class = c.class, race = c.race, sex = c.sex, kind = c.kind, label = HL.LABEL[c.kind] or "",
        title = c.title or "", line = c.line or "", value = c.value or "", valueLabel = c.valueLabel or "", icon = c.icon, headline = c.kind == "first", guild = c.guild,
        tip = function(tip) HL.CardTip(tip, set, c) end })
    else card:Hide() end
  end
  for i = 1, 10 do CF.mentions[i]:Hide() end
  -- (a preview: the guild chat line the set would post, where the officer ticked it, whole; or that none goes while
  -- the game holds chat back, Halls.lua H.ChatState)
  CF.gone:Hide()
  if chat then
    CF.chat:ClearAllPoints(); CF.chat:SetPoint("TOPLEFT", 16, -472); CF.chat:SetWidth(w - 32)
    CF.chat:Show()
  elseif CF.chat then CF.chat:Hide() end
  local by = H_SET - 58
  local list
  if opts.preview then
    list = { { "Back", 80, function() f:Hide() end }, { "Publish", 90, function() HL.PublishClick(set) end } }
  elseif opts.test or opts.look then
    list = { { "Close", 80, function() f:Hide() end } }
  else
    list = { { "Close", 80, function() f:Hide() end }, { "News", 90, function() f:Hide(); HL.OpenChip("news") end } }
  end
  local bx = w - 16
  for i = 1, 3 do
    local b, d = CF.buttons[i], list[i]
    if d then
      b:SetWidth(d[2])
      bx = bx - d[2]
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", bx, -by)
      b:SetLabel(d[1])
      b.fn, b.why = d[3], nil
      b:SetOn(true)
      b:Show()
      bx = bx - 8
    else b:Hide() end
  end
  -- (beside the buttons: why Publish waits, in DIM, whole, the button keeping its label)
  CF.posted:ClearAllPoints()
  CF.posted:SetPoint("TOPRIGHT", f, "TOPLEFT", bx, -(by + 6))
  CF.posted:SetWidth(math.min(220, bx - 16))
  CF.posted:SetText("")
  self.publishButton = opts.preview and CF.buttons[2] or nil
  CF:DrawPublish()
  f:Show()
  CF.WatchPublish()
end
-- Publish's state on the button, greyed where it waits, and why beside it (Wait a minute, Checking for news...: a
-- button's 80 units cut most of them), once a second while the preview shows
function CF:DrawPublish()
  local b = self.publishButton
  if not (b and self.set and self.frame) then return end
  if self.chat and self.chat:IsShown() and self.set.chat then self.chat:SetText(chatText(self.set)) end
  local ok, why = C.Halls.PublishState(self.set)
  b:SetOn(ok and true or false)
  b:SetLabel("Publish")
  b.why = ok and "Sends the set to the guild: every member with Cute sees it." or why
  C.UI.FitText(self.posted, ok and "" or (why or ""), (self.posted:GetWidth() or 220) - 4)
end
-- (a report draws on the same frame: a preview's guild line goes as one opens)
do
  local report = CF.Report
  function CF:Report(rep, opts) if CF.chat then CF.chat:Hide() end return report(self, rep, opts) end
end
function CF.WatchPublish()
  if CF.watchingPublish then return end
  CF.watchingPublish = true
  C_Timer.After(1, C.Safe(function()
    CF.watchingPublish = false
    if not (CF.frame and CF.frame:IsShown() and CF.publishButton) then return end
    CF:DrawPublish()
    CF.WatchPublish()
  end, "card screen: Publish"))
end
