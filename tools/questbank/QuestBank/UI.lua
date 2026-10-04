-- SPDX-License-Identifier: GPL-3.0-or-later
-- QuestBank window: a quest-log-styled toolbox with four pages.
--   Quest Log  - your 40 slots as a bank, your bags, and swaps that gain XP
--   Plan       - the best quests for your level, by dungeon and zone, for your faction, class and race
--   Settings   - mode (auto, questing, banking), next cap, updates, chat, sharing, map, discoveries
--   Hand-in    - the turn-in route with a clock and your level at every stop, and the run as you go
--   Party      - QuestBank users in your group and guild: banks, runs, dungeons worth running together
-- Built on first open, rows are pooled, and nothing updates while it is hidden.
local _, QB = ...
local UI = {}
QB.UI = UI

local W, H = 800, 620
local INK = { 0.20, 0.12, 0.05 }
local INK_SOFT = { 0.40, 0.29, 0.16 }
local GOOD = { 0.05, 0.40, 0.08 }
local BAD = { 0.55, 0.12, 0.05 }
local GOLD = { 1, 0.82, 0 }
local WHITE = { 0.95, 0.93, 0.88 }
local QUALITY = {
  { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 },
}
local STATUS = {
  done = { 0.45, 0.42, 0.38 }, banked = GOOD, active = { 0.60, 0.36, 0.0 }, partial = { 0.60, 0.36, 0.0 },
  bagstart = { 0.60, 0.36, 0.0 }, item = INK_SOFT, locked = BAD, prereq = BAD, todo = INK_SOFT, follow = { 0.25, 0.25, 0.45 },
  wrong = { 0.45, 0.42, 0.38 },
}
local BD = BackdropTemplateMixin and "BackdropTemplate" or nil
local T -- QB.Data.TEX
local Q = QB.Quest

local function tier(xp)
  if not xp then return 1 end
  xp = xp / QB.Scale(QB.state.level) -- the colours were set at level 20; a level 3's quests pay less
  if xp >= 12000 then return 6 elseif xp >= 9000 then return 5 elseif xp >= 6000 then return 4
  elseif xp >= 3000 then return 3 elseif xp >= 1500 then return 2 end
  return 1
end

local function hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

----------------------------------------------------------------------------
-- small builders
----------------------------------------------------------------------------
local function tex(parent, layer, file, w, h)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  if file then t:SetTexture(file) end
  if w then t:SetSize(w, h or w) end
  return t
end

-- a one-line label; with a width it truncates instead of running into its neighbours
local function text(parent, obj, size, color, justify, width)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  local fo = _G[obj] or GameFontNormal
  fs:SetFontObject(fo)
  if size then
    local path, _, flags = fo:GetFont()
    if path then fs:SetFont(path, size, flags) end
  end
  if color then fs:SetTextColor(color[1], color[2], color[3]) end
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  if width then fs:SetWidth(width) end
  return fs
end

local function para(parent, obj, size, color, width)
  local fs = text(parent, obj, size, color, "LEFT", width)
  fs:SetWordWrap(true)
  fs:SetJustifyV("TOP")
  return fs
end

local function backdrop(frame, bg, edge, edgeSize, inset, tile)
  if not frame.SetBackdrop then return end
  frame:SetBackdrop({
    bgFile = bg, edgeFile = edge, tile = tile and true or false, tileSize = 32, edgeSize = edgeSize,
    insets = { left = inset, right = inset, top = inset, bottom = inset },
  })
end

local function tooltip(owner, fill)
  owner:SetScript("OnEnter", QB.Safe(function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    fill(GameTooltip, self)
    GameTooltip:Show()
  end, "tooltip"))
  owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function iconButton(parent, size, icon)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.icon = tex(b, "ARTWORK", icon)
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.border = tex(b, "OVERLAY", T.slot, size * 1.83, size * 1.83)
  b.border:SetPoint("CENTER")
  b:SetHighlightTexture(T.hilite, "ADD")
  return b
end

local function button(parent, label, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 110, 22)
  b:SetText(label)
  return b
end

local function setIcon(t, icon) t:SetTexture(icon or T.questGeneric) end

-- the bags' green upgrade arrow (atlas bags-greenarrow in Interface\ContainerFrame\Bags)
local UPGRADE_TC = { 66 / 512, 86 / 512, 93 / 256, 115 / 256 }
local function upgradeMark(parent, w, h)
  local t = tex(parent, "OVERLAY", T.upgrade, w, h)
  t:SetTexCoord(UPGRADE_TC[1], UPGRADE_TC[2], UPGRADE_TC[3], UPGRADE_TC[4])
  t:Hide()
  return t
end

-- UI-WorldMap-QuestIcon holds three question marks; the yellow one sits in the top-left quarter
-- (its pixels: 11 to 23 across, 7 to 24 down, of 64), cropped square around it
local PIN_TC = { 0.1172, 0.4141, 0.0938, 0.3906 }
local function pinButton(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.t = tex(b, "ARTWORK", T.mapPin)
  b.t:SetAllPoints()
  b.t:SetTexCoord(PIN_TC[1], PIN_TC[2], PIN_TC[3], PIN_TC[4])
  b.hi = tex(b, "HIGHLIGHT", T.mapPin)
  b.hi:SetAllPoints()
  b.hi:SetTexCoord(PIN_TC[1], PIN_TC[2], PIN_TC[3], PIN_TC[4])
  b.hi:SetBlendMode("ADD")
  return b
end

local function pool(parent, make)
  local p = { items = {}, used = 0 }
  function p:Get()
    self.used = self.used + 1
    local it = self.items[self.used]
    if not it then it = make(parent); self.items[self.used] = it end
    it:Show()
    return it
  end
  function p:Reset() self.used = 0 end
  function p:HideRest() for i = self.used + 1, #self.items do self.items[i]:Hide() end end
  return p
end

-- ScrollFrame, content child and a knob slider, no templates needed
local function scrollArea(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  sf:SetPoint("TOPLEFT", 6, -6)
  sf:SetPoint("BOTTOMRIGHT", -24, 6)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(W - 90, 10)
  sf:SetScrollChild(child)
  local bar = CreateFrame("Slider", nil, parent)
  bar:SetOrientation("VERTICAL")
  bar:SetPoint("TOPRIGHT", -8, -10)
  bar:SetPoint("BOTTOMRIGHT", -8, 10)
  bar:SetWidth(14)
  local track = tex(bar, "BACKGROUND")
  track:SetColorTexture(0.25, 0.17, 0.08, 0.25)
  track:SetPoint("TOPLEFT", 4, 0)
  track:SetPoint("BOTTOMRIGHT", -4, 0)
  local knob = tex(bar, "OVERLAY", T.knob, 18, 24)
  bar:SetThumbTexture(knob)
  bar:SetMinMaxValues(0, 0)
  bar:SetValueStep(1)
  bar:SetValue(0)
  bar:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(_, delta)
    local lo, hi = bar:GetMinMaxValues()
    bar:SetValue(math.max(lo, math.min(hi, bar:GetValue() - delta * 44)))
  end)
  sf:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then child:SetWidth(w) end end)
  sf.child, sf.bar = child, bar
  function sf:SetContentHeight(h)
    child:SetHeight(math.max(h, 1))
    local view = self:GetHeight() or 0
    if view < 100 then view = (H - 128 - 42) - 12 end -- not laid out yet: the content area less the insets
    local max = math.max(0, h - view)
    bar:SetMinMaxValues(0, max)
    bar:SetShown(max > 0)
    if bar:GetValue() > max then bar:SetValue(max) end
  end
  function sf:Width()
    local w = self:GetWidth() or 0
    if w < 200 then w = W - 32 - 36 end
    return w
  end
  return sf
end

----------------------------------------------------------------------------
-- quests: tooltip and clicks shared by every page
----------------------------------------------------------------------------
local function npcLine(tip, label, n)
  if not n then return end
  local where
  if n.inside then
    where = n.n .. ", inside the dungeon"
  else
    local zone = QB.Data.MAPNAME[n.m] or ""
    where = string.format("%s, %s %.0f, %.0f", n.n, n.place or zone, n.x, n.y)
  end
  tip:AddDoubleLine(label, where, 0.6, 0.6, 0.6, 1, 1, 1)
end

-- shift-click with the chat box open puts a link in it, as the game's own quest log and bags do
-- chat, through ChatFrameUtil where the client has it (Forever's ChatEdit_* names are deprecation aliases)
local function chatFn(new, old) return (ChatFrameUtil and ChatFrameUtil[new]) or _G[old] end
local function chatInsert(link) local f = chatFn("InsertLink", "ChatEdit_InsertLink"); if f then return f(link) end end
local function chatOpen()
  local active = chatFn("GetActiveWindow", "ChatEdit_GetActiveWindow")
  return active and active() and chatFn("InsertLink", "ChatEdit_InsertLink") and true or false
end

function UI.QuestTooltip(tip, q, st, xp, pct, plvl, rewardRow)
  tip:AddLine(q.name, GOLD[1], GOLD[2], GOLD[3])
  local cat = q.cat and q.cat.name or ""
  tip:AddDoubleLine(string.format("Level %d, needs %d", q.lvl, q.req or 1), cat, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
  local full = Q.Full(q)
  local src
  if q.liveFull then
    src = QB.Live.Source(q) or "the game's own number"
  elseif q.xpUnknown then
    src = "not known yet"
  elseif q.confirmed and q.seenOnly then
    src = QB.Comma(q.base) .. ", as players' games showed it"
  elseif q.confirmed then
    src = string.format(q.near and "%s x %s; the game paid within a few percent of this after the cut" or "%s x %s, as the game paid after the cut",
      QB.Comma(q.base), (tostring(q.mult):gsub("%.?0+$", "")))
  elseif q.dungeonMult then
    src = string.format("%s x %s, as its dungeon's other quests", QB.Comma(q.base), (tostring(q.mult):gsub("%.?0+$", "")))
  elseif q.unconfirmed then
    src = string.format("Classic %s, Forever multiplier not read yet", QB.Comma(q.base))
  elseif q.mult ~= 1 then
    src = string.format("%s x %s", QB.Comma(q.base), (tostring(q.mult):gsub("%.?0+$", "")))
  else
    src = QB.Comma(q.base) .. " x 1"
  end
  tip:AddDoubleLine("Forever XP " .. ((q.xpUnknown and not q.liveFull) and "?" or QB.Comma(full)), src, 1, 1, 1, 0.55, 0.75, 1)
  UI.RewardLines(tip, q)
  if st and st.behind and st.later then
    tip:AddLine(string.format("Probably behind you: %s, a later step of this chain, is %s, and the game only offers a step once the ones before it are handed in.", QB.Quest.Label(st.later), st.how == "held" and "in your log" or "done"), 1, 0.6, 0.3, true)
  end
  if q.sodLeftover then
    tip:AddLine("A Season of Discovery leftover in Forever's data: nobody has met its NPC in Forever yet, so QuestBank doesn't suggest it.", 1, 0.5, 0.3, true)
  end
  if q.classic and not q.liveFull then
    tip:AddLine("From the Classic database: not seen in Forever yet, so it may differ or not exist.", 1, 0.6, 0.3, true)
  end
  if q.seenOnly then
    tip:AddLine(string.format("New in Forever and known only from players' notes: Wowhead doesn't list it yet. Level %d as the game showed it; it may unlock before level %d.%s",
      q.lvl, q.req or q.lvl, q.turn and "" or " Where it's handed in isn't known yet."), 0.75, 0.75, 1, true)
  end
  if q.nerfed and not q.confirmed and not q.liveFull and not q.xpUnknown then
    tip:AddLine("An estimate: Wowhead's reading from before Blizzard's 1 October cut, with the cut applied. Quests in your log use the game's own number.", 1, 0.6, 0.3, true)
  end
  if q.liveFull and math.abs(q.liveFull - QB.Model.Listed(q)) > 25 then
    tip:AddLine(string.format(q.nerfed and "The catalog lists %s. QuestBank uses the game's number." or "Wowhead lists %s. QuestBank uses the game's number.", QB.Comma(QB.Model.Listed(q))), 1, 0.6, 0.3, true)
  end
  if xp then
    local line = QB.Comma(xp) .. " XP " .. QB:OnTheDay()
    if pct and pct < 100 then line = line .. string.format(" (%d%% at level %d)", pct, plvl) end
    tip:AddLine(line, pct and pct < 100 and 1 or 0.6, pct and pct < 100 and 0.6 or 1, pct and pct < 100 and 0.3 or 0.6)
  end
  if st then
    local c = STATUS[st.code] or WHITE
    tip:AddLine(st.text, math.min(1, c[1] * 1.6 + 0.25), math.min(1, c[2] * 1.6 + 0.25), math.min(1, c[3] * 1.6 + 0.25), true)
  end
  -- every objective, and what it asks you to bring: in your bags and in your bank
  local e = QB.state.log[q.id]
  if e and e.objectives and #e.objectives > 0 then
    for _, o in ipairs(e.objectives) do
      if o.text and o.text ~= "" then
        if o.done then tip:AddLine("  " .. o.text, 0.4, 0.9, 0.4, true) else tip:AddLine("  " .. o.text, 0.9, 0.9, 0.9, true) end
      end
    end
  end
  local items = QB.Bank.Items(q)
  if items then
    local _, at = QB.Bank.Count(items[1].id)
    for _, it in ipairs(items) do
      local have = it.bags + it.bank
      local line = string.format("%s: %d of %d in your bags", it.name, math.min(it.bags, it.need), it.need)
      if it.bank > 0 then line = line .. string.format(", %d more in your bank", it.bank) end
      local enough = it.bags >= it.need
      local r, g, b = 0.9, 0.9, 0.9
      if enough then r, g, b = 0.4, 0.9, 0.4 elseif have >= it.need then r, g, b = 1, 0.82, 0 end
      tip:AddDoubleLine(line, enough and "all here" or (have >= it.need and "in your bank" or string.format("%d to go", it.need - have)), r, g, b, r, g, b)
    end
    if not at then tip:AddLine("Open your bank once and QuestBank remembers what's in it.", 0.6, 0.6, 0.6, true) end
  end
  if q.tip then tip:AddLine(q.tip, 0.85, 0.8, 0.7, true) end
  if q.group then tip:AddLine("Group quest.", 1, 0.5, 0.3) end
  local chain = Q.ChainText(q)
  if chain then tip:AddLine("Chain: " .. chain, 0.75, 0.75, 1, true) end
  if st and st.code == "prereq" then
    local cc = QB:ChainCost(q)
    if cc then
      local pay = ""
      if cc.xp > 0 then
        pay = QB:Mode() == "lock" and string.format("; the steps pay nothing at the cap (%s XP otherwise)", QB.Comma(cc.xp))
          or string.format("; the steps pay %s XP along the way", QB.Comma(cc.xp))
      end
      tip:AddLine(string.format("%d step%s first%s%s.", cc.n, cc.n == 1 and "" or "s",
        cc.minutes and cc.minutes > 0 and string.format(", about %d min of moving from where you stand", cc.minutes) or "", pay), 0.75, 0.75, 1, true)
    end
  end
  if q.nextSteps then
    local names = {}
    for _, n in ipairs(q.nextSteps) do
      local nq = Q.Get(n)
      if nq and Q.ForMe(nq) then names[#names + 1] = string.format("%s (%s)", nq.name, QB.Short(QB.Model.XpAt(nq, QB.state.level))) end
    end
    if #names > 0 then tip:AddLine("Leads on to: " .. table.concat(names, ", "), 0.75, 0.75, 1, true) end
  end
  local up, upV, upDepth = QB:Upgrade(q)
  if up then
    if QB:Banking() then
      tip:AddLine(string.format("Upgrade: hand it in now and bank %s instead%s, +%s XP.", up.name,
        upDepth > 1 and string.format(" (%d steps on)", upDepth) or "", QB.Comma(upV - (xp or QB.Model.XpAt(q, QB.state.level)))), 0.3, 1, 0.3, true)
    else
      tip:AddLine(string.format("Carry the chain on: %s pays %s XP%s.", up.name, QB.Comma(upV),
        upDepth > 1 and string.format(", %d steps on", upDepth) or ""), 0.3, 1, 0.3, true)
    end
  end
  npcLine(tip, "From", q.give)
  npcLine(tip, "Hand in", q.turn)
  local inLog = QB.state.log[q.id]
  local shift
  if inLog or (st and st.bag) then
    shift = QB:IsCut(q.id) and "Shift-click: keep it" or "Shift-click: cut it"
  else
    shift = QB:IsAdded(q.id) and "Shift-click: take it off your pick-up list" or "Shift-click: put it on your pick-up list"
  end
  if chatOpen() then shift = "Shift-click: link it in chat" end
  if rewardRow then shift = "Shift-click: link the reward" end -- Find quests' reward rows link the item, not the quest
  tip:AddLine("Click: waypoint.  " .. shift .. ".  Right-click: more.", 0.5, 0.5, 0.5, true)
end

function UI.QuestLink(q)
  local link
  if GetQuestLink then
    local ok, l = pcall(GetQuestLink, q.id)
    if ok and type(l) == "string" and l:find("|Hquest:") then link = l end
  end
  if not link and C_QuestLog and C_QuestLog.RequestLoadQuestByID then pcall(C_QuestLog.RequestLoadQuestByID, q.id) end
  -- the game makes the link once it knows the quest; until then, its name in brackets
  return link or ("[" .. q.name .. "]")
end

function UI.LinkQuest(q)
  if not chatOpen() then return false end
  chatInsert(UI.QuestLink(q))
  return true
end

function UI.LinkItem(id, name)
  if not (id and chatOpen()) then return false end
  local link
  local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if info then
    local ok, _, l = pcall(info, id)
    if ok and type(l) == "string" then link = l end
  end
  chatInsert(link or ("[" .. (name or ("Item " .. id)) .. "]"))
  return true
end

-- an item's link into chat: into the open chat box, or a new one
function UI.LinkItemAlways(id)
  if UI.LinkItem(id) then return true end
  local name, link = QB.API.ItemInfo(id)
  local open = chatFn("OpenChat", "ChatFrame_OpenChat")
  if open then open(link or ("[" .. (name or ("Item " .. id)) .. "]")) return true end
  return false
end

-- a quest's reward items in a tooltip, by name in their quality colour; says so plainly when nobody knows them yet
function UI.RewardLines(tip, q)
  local rw, how = Q.Rewards(q)
  if how == "unknown" then
    tip:AddLine("Rewards: not known yet. Open the quest in game and QuestBank notes them.", 0.75, 0.75, 1, true)
    return
  end
  local c, r, u = rw and rw.c or {}, rw and rw.r or {}, rw and rw.u or {}
  if #c + #r + #u == 0 then
    tip:AddLine(how == "game" and "No item rewards (as your quest window showed)." or "No item rewards.", 0.6, 0.6, 0.6)
    return
  end
  local function line(id)
    local name, _, quality, icon = QB.API.ItemInfo(id)
    local cr, cg, cb = 0.8, 0.8, 0.8
    if quality and C_Item and C_Item.GetItemQualityColor then
      local ok, qr, qg, qb = pcall(C_Item.GetItemQualityColor, quality)
      if ok and qr then cr, cg, cb = qr, qg, qb end
    elseif quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
      local col = ITEM_QUALITY_COLORS[quality]
      cr, cg, cb = col.r, col.g, col.b
    end
    tip:AddLine("   " .. (icon and ("|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or "") .. (name or ("Item " .. id .. " (the game is loading it)")), cr, cg, cb)
  end
  if #r > 0 then
    tip:AddLine("You get:", 1, 0.82, 0)
    for i = 1, math.min(#r, 6) do line(r[i]) end
  end
  if #c > 0 then
    tip:AddLine(#c > 1 and "Choose one:" or "Reward:", 1, 0.82, 0)
    for i = 1, math.min(#c, 6) do line(c[i]) end
  end
  if #u > 0 then
    tip:AddLine("Rewards include:", 1, 0.82, 0) -- a loot page lists them without saying which are a choice
    for i = 1, math.min(#u, 6) do line(u[i]) end
  end
  tip:AddLine((how == "game" and "As your quest window showed them. " or "") .. "Right-click the quest to link one in chat.", 0.6, 0.6, 0.6, true)
end

local questClick
function UI.QuestClick(q, st, which) QB.Try("click", questClick, q, st, which) end
questClick = function(q, st, which)
  if which == "RightButton" then UI.QuestMenu(q, st) return end
  if IsShiftKeyDown and IsShiftKeyDown() then
    if UI.LinkQuest(q) then return end
    QB:ToggleAdd(q.id)
    UI:Refresh()
    return
  end
  local target = q.turn
  if st and (st.code == "todo" or st.code == "locked" or st.code == "prereq") and q.give then target = q.give end
  if st and st.code == "prereq" and QB.Arrow then
    -- a chain: the giver of its first open step, or the turn-in of the step you hold
    local first, held = QB.Arrow.FirstStep(q, st)
    if first then target = (held and first.turn) or first.give or target end
  end
  if target and not target.inside then
    QB.API.SetWaypoint(target.m, target.x, target.y, target.n, nil, QB.Model.NpcPlace(target.idx, QB.faction))
  end
end

----------------------------------------------------------------------------
-- right-click menu: what you can do with a quest
----------------------------------------------------------------------------
local menu
local function menuFrame()
  if menu then return menu end
  T = T or QB.Data.TEX
  menu = CreateFrame("Frame", "QuestBankMenu", UIParent, BD)
  menu:SetFrameStrata("DIALOG")
  menu:SetFrameLevel(20)
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  backdrop(menu, T.tipBg, T.tipBorder, 12, 3)
  if menu.SetBackdropColor then menu:SetBackdropColor(0.06, 0.05, 0.04, 0.96) end
  menu.title = text(menu, "GameFontNormal", 12, GOLD, "LEFT", 224)
  menu.title:SetPoint("TOPLEFT", 10, -9)
  menu.items = {}
  -- a click anywhere else closes it
  menu.catcher = CreateFrame("Button", nil, UIParent)
  menu.catcher:SetAllPoints(UIParent)
  menu.catcher:SetFrameStrata("DIALOG")
  menu.catcher:SetFrameLevel(10)
  menu.catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  menu.catcher:SetScript("OnClick", function() menu:Hide() end)
  menu.catcher:Hide()
  menu:SetScript("OnHide", function() menu.catcher:Hide() end)
  if UISpecialFrames then table.insert(UISpecialFrames, "QuestBankMenu") end
  menu:Hide()
  return menu
end

function UI:ShowMenu(title, items)
  local m = menuFrame()
  m.title:SetText(title)
  local y = -30
  for i, it in ipairs(items) do
    local b = m.items[i]
    if not b then
      b = CreateFrame("Button", nil, m)
      b:SetSize(232, 20)
      b.hi = tex(b, "HIGHLIGHT", T.rowHi)
      b.hi:SetAllPoints()
      b.hi:SetBlendMode("ADD")

      b.hi:SetAlpha(0.6)
      b.label = text(b, "GameFontHighlightSmall", 12, WHITE, "LEFT", 220)
      b.label:SetPoint("LEFT", 8, 0)
      b:SetScript("OnClick", function(self)
        m:Hide()
        if self.func then self.func() end
      end)
      m.items[i] = b
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 6, y)
    b.label:SetText(it[1])
    b.func = it[2]
    b:Show()
    y = y - 20
  end
  for i = #items + 1, #m.items do m.items[i]:Hide() end
  m:SetSize(244, -y + 10)
  local x, cy = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  m:ClearAllPoints()
  m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 6, cy / scale - 6)
  m.catcher:Show()
  m:Show()
end

-- a box with the link selected, ready for Ctrl+C
function UI:CopyLink(title, url)
  T = T or QB.Data.TEX
  local f = self.linkFrame
  if not f then
    f = CreateFrame("Frame", "QuestBankLink", UIParent, BD)
    self.linkFrame = f
    f:SetSize(380, 84)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(30)
    f:EnableMouse(true)
    backdrop(f, T.bg, T.border, 24, 7, true)
    f.title = text(f, "GameFontNormal", 12, GOLD, "LEFT", 320)
    f.title:SetPoint("TOPLEFT", 16, -16)
    f.hint = text(f, "GameFontHighlightSmall", 10, WHITE, "LEFT", 320)
    f.hint:SetPoint("TOPLEFT", 16, -60)
    f.hint:SetText("Ctrl+C copies it. Esc closes.")
    f.eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.eb:SetSize(340, 20)
    f.eb:SetPoint("TOPLEFT", 20, -34)
    f.eb:SetAutoFocus(false)
    f.eb:SetScript("OnEscapePressed", function() f:Hide() end)
    f.eb:SetScript("OnEnterPressed", function() f:Hide() end)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    if UISpecialFrames then table.insert(UISpecialFrames, "QuestBankLink") end
  end
  f.title:SetText(title)
  f.eb:SetText(url)
  f:Show()
  f.eb:SetFocus()
  f.eb:HighlightText()
end

-- posting in party and guild chat: the message as people will read it (yours to edit), where it goes,
-- and nothing is sent until you press Post
local GREY = { 0.62, 0.6, 0.56 }
function UI:PostDialog(msg, why, offered)
  T = T or QB.Data.TEX
  local f = self.postFrame
  -- an offer never replaces a message you're writing
  if f and offered and f:IsShown() and (f.edited or f.eb:HasFocus()) then return end
  if not f then
    f = CreateFrame("Frame", "QuestBankPost", UIParent, BD)
    self.postFrame = f
    f:SetSize(420, 256)
    local pos = QB:Settings().post.pos
    if pos then f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else f:SetPoint("TOP", 0, -120) end
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(30)
    f:EnableMouse(true)
    -- drag it out of your way; it opens there next time
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      local p, _, _, x, y = self:GetPoint()
      QB:Settings().post.pos = { p, x, y }
    end)
    backdrop(f, T.bg, T.border, 24, 7, true)
    f.title = text(f, "GameFontNormal", 13, GOLD, "LEFT", 380)
    f.title:SetPoint("TOPLEFT", 20, -18)
    f.title:SetText("Post in chat")
    f.why = text(f, "GameFontHighlightSmall", 11, WHITE, "LEFT", 380)
    f.why:SetPoint("TOPLEFT", 20, -36)
    f.box = CreateFrame("Frame", nil, f, BD)
    f.box:SetPoint("TOPLEFT", 16, -54)
    f.box:SetSize(388, 96)
    backdrop(f.box, T.tipBg, T.tipBorder, 12, 3)
    if f.box.SetBackdropColor then f.box:SetBackdropColor(0, 0, 0, 0.6) end
    f.box:EnableMouse(true)
    f.eb = CreateFrame("EditBox", nil, f.box)
    f.eb:SetFontObject(ChatFontNormal)
    f.eb:SetPoint("TOPLEFT", 10, -8)
    f.eb:SetSize(368, 80)
    f.eb:SetMultiLine(true)
    f.eb:SetMaxLetters(255)
    f.eb:SetAutoFocus(false)
    f.eb:EnableMouse(true)
    f.eb:SetTextColor(1, 1, 1)
    f.box:SetScript("OnMouseDown", function() f.eb:SetFocus() end)
    f.eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    f.eb:SetScript("OnTextChanged", function(self, typed)
      if not typed then return end
      -- one line, no escape codes: the chat box doesn't take them
      local t = self:GetText()
      local one = t:gsub("[\r\n|]", "")
      if one ~= t then self:SetText(one) end
      f.edited = true
      UI:PostState()
    end)
    local function check(x, key)
      local c = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
      c:SetSize(24, 24)
      c:SetPoint("TOPLEFT", x, -156)
      c.label = text(f, "GameFontNormal", 12, WHITE, "LEFT", 150)
      c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
      c.key = key
      c:SetScript("OnClick", function() UI:PostState() end)
      return c
    end
    f.party = check(16, "party")
    f.guild = check(210, "guild")
    f.auto = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    f.auto:SetSize(20, 20)
    f.auto:SetPoint("TOPLEFT", 18, -184)
    f.autoLabel = text(f, "GameFontHighlightSmall", 11, GREY, "LEFT", 356)
    f.autoLabel:SetPoint("LEFT", f.auto, "RIGHT", 2, 0)
    f.autoLabel:SetText("Offer a post during hand-in runs: each level, the hour, the end")
    f.auto:SetScript("OnClick", function(self) QB:Settings().post.auto = self:GetChecked() and true or false end)
    f.post = button(f, "Post", 110)
    f.post:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 18)
    f.post:SetScript("OnClick", QB.Safe(function() UI:PostSend() end, "posting in chat"))
    f.cancel = button(f, "Cancel", 110)
    f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 18)
    f.cancel:SetScript("OnClick", function() f:Hide() end)
    f:SetScript("OnHide", function() f.eb:ClearFocus() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "QuestBankPost") end
  end
  f.why:SetText(why or "")
  f.eb:SetText(msg or "")
  f.edited = false
  -- ticked the way you left them, where you can post right now
  local set = QB:Settings().post
  local ch = QB.Sync and QB.Sync.PostChannels() or {}
  for _, c in ipairs({ f.party, f.guild }) do
    local where = ch[c.key]
    c:SetEnabled(where ~= nil)
    c:SetChecked((where ~= nil and set[c.key]) and true or false)
    if where then
      c.label:SetText(where.label)
      c.label:SetTextColor(WHITE[1], WHITE[2], WHITE[3])
    else
      c.label:SetText(c.key == "party" and "Party (not in a group)" or "Guild (not in one)")
      c.label:SetTextColor(GREY[1], GREY[2], GREY[3])
    end
  end
  f.auto:SetChecked(set.auto and true or false)
  self:PostState()
  f:Show()
end

-- Post works when a ticked channel can take it and there's something to say
function UI:PostState()
  local f = self.postFrame
  local on = (f.party:GetChecked() and f.party:IsEnabled()) or (f.guild:GetChecked() and f.guild:IsEnabled())
  f.post:SetEnabled((on and QB.Sync.CleanPost(f.eb:GetText()) ~= "") and true or false)
end

function UI:PostSend()
  local f = self.postFrame
  local want = { party = f.party:GetChecked() and true or false, guild = f.guild:GetChecked() and true or false }
  -- next time it's ticked the way you left it
  local set, ch = QB:Settings().post, QB.Sync.PostChannels()
  for key, on in pairs(want) do if ch[key] then set[key] = on end end
  local n = QB.Sync:Post(f.eb:GetText(), want)
  f:Hide()
  if n == 0 then QB:Print("Nothing was posted: you're not in that group or guild any more.") end
end

function UI.QuestMenu(q, st)
  st = st or QB:Status(q)
  local items = {}
  local function way(n, what)
    if n and not n.inside and n.m and n.m > 0 then
      items[#items + 1] = { string.format("Waypoint: %s (%s)", n.n, what), function() QB.API.SetWaypoint(n.m, n.x, n.y, n.n) end }
    end
  end
  way(q.give, "gives it")
  if not (q.give and q.turn and q.give.idx == q.turn.idx) then way(q.turn, "hand in") end
  local held = QB.state.log[q.id] or st.bag
  if held then
    items[#items + 1] = { QB:IsCut(q.id) and "Keep it in the route" or "Leave it out of the route", function() QB:ToggleAdd(q.id); UI:Refresh() end }
  elseif st.code ~= "done" and st.code ~= "wrong" then
    items[#items + 1] = { QB:IsAdded(q.id) and "Take it off my pick-up list" or "Put it on my pick-up list", function() QB:ToggleAdd(q.id); UI:Refresh() end }
  end
  local rw = Q.Rewards(q)
  if rw then
    local ids, seen = {}, {}
    for _, list in ipairs({ rw.r or {}, rw.c or {}, rw.u or {} }) do
      for _, id in ipairs(list) do if not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
    end
    for i = 1, math.min(#ids, 6) do
      local id = ids[i]
      local name = QB.API.ItemInfo(id)
      items[#items + 1] = { "Link " .. (name or ("item " .. id)) .. " in chat", function() UI.LinkItemAlways(id) end }
    end
  end
  items[#items + 1] = { "Copy the Wowhead link", function() UI:CopyLink(q.name, "https://www.wowhead.com/forever/quest=" .. q.id) end }
  UI:ShowMenu(q.name, items)
end

----------------------------------------------------------------------------
-- frame
----------------------------------------------------------------------------
function UI:Create()
  if self.frame then return self.frame end
  T = QB.Data.TEX
  local set = QB:Settings()
  local f = CreateFrame("Frame", "QuestBankFrame", UIParent, BD)
  self.frame = f
  f:SetSize(W, H)
  if set.pos then
    f:SetPoint(set.pos[1], UIParent, set.pos[1], set.pos[2], set.pos[3])
  else
    f:SetPoint("CENTER")
  end
  f:SetFrameStrata("MEDIUM")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, _, x, y = self:GetPoint()
    QB:Settings().pos = { p, x, y }
  end)
  f:SetScript("OnShow", function() UI:Refresh() end)
  f:Hide()
  backdrop(f, T.bg, T.border, 32, 11, true)
  if UISpecialFrames then table.insert(UISpecialFrames, "QuestBankFrame") end

  local plate = tex(f, "ARTWORK", T.header, 320, 64)
  plate:SetPoint("TOP", 0, 12)
  local title = text(f, "GameFontNormalLarge", 15, GOLD, "CENTER", 200)
  title:SetPoint("TOP", plate, "TOP", 0, -14)
  title:SetText("QuestBank")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -5, -5)

  self:CreateHeader(f)
  self:CreateContent(f)
  self:CreateTabs(f)
  self:ShowTab(set.tab or 1)
  return f
end

-- header: portrait, name, the XP bar from 20 to 30, four switches
local BAR_X, BAR_W = 92, 400
function UI:CreateHeader(f)
  local h = {}
  self.header = h
  h.portrait = tex(f, "ARTWORK", nil, 58, 58)
  h.portrait:SetPoint("TOPLEFT", 22, -34)
  h.name = text(f, "GameFontNormalLarge", 16, GOLD, "LEFT", BAR_W)
  h.name:SetPoint("TOPLEFT", BAR_X, -34)
  h.sub = text(f, "GameFontHighlightSmall", 11, WHITE, "LEFT", BAR_W)
  h.sub:SetPoint("TOPLEFT", BAR_X, -54)
  h.legend = text(f, "GameFontHighlightSmall", 11, WHITE, "LEFT", BAR_W)
  h.legend:SetPoint("TOPLEFT", BAR_X, -70)

  local bar = CreateFrame("Frame", nil, f, BD)
  bar:SetPoint("TOPLEFT", BAR_X - 4, -86)
  bar:SetSize(BAR_W + 8, 22)
  backdrop(bar, T.tipBg, T.tipBorder, 10, 2)
  if bar.SetBackdropColor then bar:SetBackdropColor(0, 0, 0, 0.75) end
  local function fill(layer, r, g, b, a)
    local t = tex(bar, layer, T.bar)
    t:SetPoint("TOPLEFT", 4, -4)
    t:SetHeight(14)
    t:SetVertexColor(r, g, b, a)
    t:SetWidth(1)
    return t
  end
  h.fillPlan = fill("BORDER", 0.75, 0.55, 1, 0.35)
  h.fillNow = fill("ARTWORK", 0.58, 0.0, 0.55, 0.85)
  h.fillCur = fill("OVERLAY", 0.25, 0.5, 1, 1)
  h.bar = bar
  h.ticks, h.labels = {}, {}
  for i = 1, 20 do
    local tick = tex(bar, "OVERLAY")
    tick:SetColorTexture(0, 0, 0, 0.8)
    tick:SetSize(1, 14)
    h.ticks[i] = tick
  end
  for i = 1, 11 do h.labels[i] = text(f, "GameFontHighlightSmall", 10, { 0.75, 0.72, 0.65 }, "CENTER", 24) end
  tooltip(bar, function(tip)
    local lo, hi = UI.barLo or 1, UI.barHi or 2
    tip:AddLine(string.format("Level %d to %d", lo, hi), GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Blue: where you are now.", 0.5, 0.7, 1)
    tip:AddLine(QB:Banking() and "Purple: after handing in everything banked now." or "Purple: after handing in the quests that are ready.", 0.8, 0.4, 0.8)
    tip:AddLine("Pale: after the whole plan.", 0.85, 0.75, 1)
    local need = 0
    for l = lo, hi - 1 do need = need + (QB.Data.TO_NEXT[l] or 0) end
    tip:AddLine(string.format("Level %d to %d takes %s XP.", lo, hi, QB.Comma(need)), 0.8, 0.8, 0.8)
    local held, nextCap = QB:Lock()
    if held then
      tip:AddLine(string.format("The game holds you at level %d for now. QuestBank banks your log for the cap going up to %d.", held, nextCap), 1, 0.82, 0, true)
    elseif QB:Mode() == "rush" then
      tip:AddLine("The level cap went up: time to cash your bank in.", 1, 0.82, 0, true)
    else
      tip:AddLine(string.format("Questing: the game lets you level to %d, so hand quests in as you go.", QB.CAP), 0.8, 0.8, 0.8, true)
    end
    local D, st = QB.Data, QB.Data.STATS
    if st then
      tip:AddLine(" ")
      tip:AddLine(string.format("Quest data read %s, Forever client %s.", D.READ or "", D.BUILD or ""), 0.6, 0.6, 0.6, true)
      tip:AddLine(string.format("Of %d quests players have met in Forever: %d without a read multiplier, %d without a known turn-in spot, %d handed in inside a dungeon.",
        st.quests, st.noMult, st.noTurn, st.inside), 0.6, 0.6, 0.6, true)
      if st.classic and st.classic > 0 then
        tip:AddLine(string.format("%d more come from the Classic database and are marked until someone sees them in Forever.", st.classic), 0.6, 0.6, 0.6, true)
      end
    end
  end)

  h.toggles = {}
  local defs = {
    { key = "mounted", icon = T.mount }, { key = "goal", icon = T.hourglass }, { key = "pins", icon = T.map },
  }
  for i, d in ipairs(defs) do
    local b = iconButton(f, 30, d.icon)
    b:SetPoint("TOPRIGHT", -(34 + (#defs - i) * 66), -46)
    b.caption = text(f, "GameFontHighlightSmall", 10, WHITE, "CENTER", 64)
    b.caption:SetPoint("TOP", b, "BOTTOM", 0, -8)
    b.key = d.key
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", QB.Safe(function(self, which) UI:Switch(self.key, which) end, "header switch"))
    tooltip(b, function(tip, self) UI:SwitchTooltip(tip, self.key) end)
    h.toggles[d.key] = b
  end
end

function UI:Switch(key, which)
  local set = QB:Settings()
  if key == "mounted" then
    if which == "RightButton" then
      set[key] = "auto"
    else
      set[key] = not QB:Mounted()
    end
  elseif key == "goal" then
    if which == "RightButton" then
      -- stop banking: back to looking for a lock if you forced one, else questing from here
      QB:SetLock(QB:LockChoice() == "on" and "auto" or "off")
    else
      set.goal = set.goal == "hour" and "route" or "hour"
    end
  elseif key == "lock" then
    QB:SetLock(QB:LockChoice() == "off" and "auto" or "on")
  elseif key == "pins" then
    if which == "RightButton" then
      if QB.Pins then QB.Pins:PinNext(true) end
      return
    end
    if QB.Pins then QB.Pins:Toggle() else set.pins = not set.pins end
  end
  QB:MarkDirty()
  self:Refresh()
end

function UI:SwitchTooltip(tip, key)
  local set = QB:Settings()
  if key == "mounted" then
    local on, auto = QB:Mounted()
    tip:AddLine(on and "Mounted" or "On foot", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("A mount cuts every stretch on foot to 62%. Flights, boats and zeppelins take as long as they take.", 1, 1, 1, true)
    tip:AddLine(auto and "Set from your riding skill. Right-click keeps it on auto." or "Set by you. Right-click goes back to auto.", 0.6, 0.6, 0.6, true)
  elseif key == "goal" then
    tip:AddLine(set.goal == "hour" and "Plan for the first hour" or "Plan for the whole route", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("First hour: the highest level at the 60-minute mark, whatever comes after. Whole route: the highest level at the end, in the least time.", 1, 1, 1, true)
    local held, nextCap = QB:Lock()
    if held then
      tip:AddLine(string.format("Banking: the game holds you at level %d, and the plan is for the cap going up to %d.", held, nextCap), 0.8, 0.8, 0.8, true)
    end
    tip:AddLine("Right-click: stop banking and plan for questing.", 0.6, 0.6, 0.6, true)
  elseif key == "lock" then
    tip:AddLine("Questing", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("No level lock: the game lets you level, so hand quests in as you go. The route plans the quickest way to hand in what's ready, and the green arrows mark chains worth carrying on.", 1, 1, 1, true)
    tip:AddLine(QB:LockChoice() == "off" and "You turned banking off. Click to let QuestBank look for a level lock again."
      or "Banking only pays off while the game holds your level at a cap. Click to bank anyway.", 0.6, 0.6, 0.6, true)
  elseif key == "pins" then
    tip:AddLine(set.pins and "Map pins on" or "Map pins off", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("Numbered pins on the world map for every stop on the route, and ! pins where planned quests start.", 1, 1, 1, true)
    tip:AddLine("Right-click: waypoint on the next stop.", 0.6, 0.6, 0.6)
  end
end

function UI:CreateContent(f)
  local c = CreateFrame("Frame", nil, f, BD)
  c:SetPoint("TOPLEFT", 16, -128)
  c:SetPoint("BOTTOMRIGHT", -16, 42)
  backdrop(c, nil, T.tipBorder, 14, 3)
  local parch = tex(c, "BACKGROUND", T.parchH)
  parch:SetPoint("TOPLEFT", 4, -4)
  parch:SetPoint("BOTTOMRIGHT", -4, 4)
  self.content = c
  self.views = {
    self:CreateLogView(c),
    self:CreatePrepView(c),
    self:CreateRouteView(c),
    self:CreatePartyView(c),
    self:CreateSettingsView(c),
  }
end

function UI:CreateTabs(f)
  self.tabs = {}
  local names = { "Quest Log", "Available", "Hand-in Route", "Party", "Settings" }
  local x = 20
  for i, name in ipairs(names) do
    local b = CreateFrame("Button", nil, f)
    local w = 118
    b:SetSize(w, 32)
    b:SetPoint("TOPLEFT", self.content, "BOTTOMLEFT", x, 2)
    x = x + w + 2
    local function piece(file, w2, l, r, bottom, h2)
      local t = tex(b, "BACKGROUND", file)
      t:SetSize(w2, h2)
      t:SetTexCoord(l, r, 0, bottom)
      return t
    end
    b.onL = piece(T.tabOn, 20, 0, 0.15625, 0.546875, 35)
    b.onR = piece(T.tabOn, 20, 0.84375, 1, 0.546875, 35)
    b.onM = piece(T.tabOn, w - 40, 0.15625, 0.84375, 0.546875, 35)
    b.offL = piece(T.tabOff, 20, 0, 0.15625, 1, 32)
    b.offR = piece(T.tabOff, 20, 0.84375, 1, 1, 32)
    b.offM = piece(T.tabOff, w - 40, 0.15625, 0.84375, 1, 32)
    for _, set in ipairs({ { b.onL, b.onM, b.onR, 3 }, { b.offL, b.offM, b.offR, 0 } }) do
      set[1]:SetPoint("TOPLEFT", 0, set[4])
      set[2]:SetPoint("TOPLEFT", set[1], "TOPRIGHT")
      set[3]:SetPoint("TOPLEFT", set[2], "TOPRIGHT")
    end
    local hi = tex(b, "HIGHLIGHT", T.tabHi)
    hi:SetPoint("TOPLEFT", 6, -2)
    hi:SetPoint("BOTTOMRIGHT", -6, 6)
    hi:SetBlendMode("ADD")
    b.label = text(b, "GameFontNormalSmall", 12, GOLD, "CENTER", w - 16)
    b.label:SetPoint("CENTER", 0, 2)
    b.label:SetText(name)
    b:SetScript("OnClick", function() UI:ShowTab(i) end)
    self.tabs[i] = b
  end
end

function UI:ShowErrors()
  T = T or QB.Data.TEX
  local list = QuestBankDB.errors or {}
  local out = { string.format("QuestBank %s, %d problem%s recorded (Ctrl+A then Ctrl+C copies all):", QB.version, #list, #list == 1 and "" or "s"), "" }
  for _, e in ipairs(list) do
    out[#out + 1] = string.format("[%s] %sx, %s, version %s", e.last or "", e.count or 1, e.where or "?", e.version or "?")
    out[#out + 1] = e.msg or ""
    out[#out + 1] = e.stack or ""
    out[#out + 1] = ""
  end
  if #list == 0 then out[#out + 1] = "Nothing recorded. If Blizzard's error window showed one, copy its text instead." end
  local f = self.errFrame
  if not f then
    f = CreateFrame("Frame", "QuestBankErrors", UIParent, BD)
    self.errFrame = f
    f:SetSize(560, 360)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(30)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    backdrop(f, T.bg, T.border, 24, 7, true)
    f.title = text(f, "GameFontNormal", 13, GOLD, "LEFT", 480)
    f.title:SetPoint("TOPLEFT", 18, -16)
    f.title:SetText("QuestBank problems")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 18, -40)
    sf:SetPoint("BOTTOMRIGHT", -36, 18)
    f.eb = CreateFrame("EditBox", nil, sf)
    f.eb:SetMultiLine(true)
    f.eb:SetAutoFocus(false)
    f.eb:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    f.eb:SetWidth(490)
    f.eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(f.eb)
    if UISpecialFrames then table.insert(UISpecialFrames, "QuestBankErrors") end
  end
  f.eb:SetText(table.concat(out, "\n"))
  f:Show()
  f.eb:SetFocus()
  f.eb:HighlightText()
end

function UI:ShowTab(i)
  QB:Settings().tab = i
  self.tab = i
  for k, v in ipairs(self.views) do v:SetShown(k == i) end
  for k, b in ipairs(self.tabs) do
    local on = k == i
    for _, t in ipairs({ b.onL, b.onM, b.onR }) do t:SetShown(on) end
    for _, t in ipairs({ b.offL, b.offM, b.offR }) do t:SetShown(not on) end
    b.label:SetTextColor(on and 1 or GOLD[1], on and 1 or GOLD[2], on and 1 or GOLD[3])
  end
  if self.frame and self.frame:IsShown() then self:Refresh() end
end

function UI:Open(tab)
  self:Create()
  self.frame:Show()
  if tab then self:ShowTab(tab) end
end

function UI:Toggle()
  self:Create()
  self.frame:SetShown(not self.frame:IsShown())
end

----------------------------------------------------------------------------
-- refresh
----------------------------------------------------------------------------
local refresh
function UI:Refresh() QB.Try("window", refresh, self) end
refresh = function(self)
  if not (self.frame and self.frame:IsShown()) then return end
  if not QB.fresh then QB:Recompute() end
  self:RefreshHeader()
  local v = self.views[self.tab or 1]
  if v and v.Refresh then v:Refresh() end
end

function UI:RefreshHeader()
  local h, s = self.header, QB.state
  if SetPortraitTexture then SetPortraitTexture(h.portrait, "player") end
  h.name:SetText(s.name or "")
  local cls = UnitClass and (UnitClass("player")) or ""
  local bind = QB.API.BindName()
  h.sub:SetText(string.format("Level %d %s, %s.  Hearthstone: %s", s.level, cls or "", QB.faction == "H" and "Horde" or "Alliance",
    bind ~= "" and bind or "not set"))
  local cur = QB.Model.Frac(s.level, s.xp)
  local now, plan = QB.routeNow, QB.routePlan
  local banking = QB:Banking()
  -- the bar's window: from the lock to the next cap when banking, else your next ten levels
  local lo, hi
  if banking then
    local held = QB:Lock()
    local was = QB:Held()
    lo = held or (was and was.level) or math.floor(cur)
    hi = QB.CAP
  else
    lo = math.floor(cur)
    hi = math.min(lo + 10, QB.CAP)
  end
  if lo >= QB.MAXLEVEL then lo = QB.MAXLEVEL - 1 end
  if hi <= lo then hi = lo + 1 end
  UI.barLo, UI.barHi = lo, hi
  local span = hi - lo
  local function w(level) return math.max(1, math.min(BAR_W, BAR_W * (level - lo) / span)) end
  local tstep = span <= 20 and 1 or 5
  local ti = 0
  for l = lo + tstep, hi - 1, tstep do
    ti = ti + 1
    local t = h.ticks[ti]
    if not t then break end
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", 4 + BAR_W * (l - lo) / span, -4)
    t:Show()
  end
  for i = ti + 1, #h.ticks do h.ticks[i]:Hide() end
  local step = span <= 5 and 1 or (span <= 10 and 2 or 5)
  local k = 0
  for l = lo, hi, step do
    k = k + 1
    local lab = h.labels[k]
    if not lab then break end
    lab:ClearAllPoints()
    lab:SetPoint("TOP", h.bar, "BOTTOMLEFT", 4 + BAR_W * (l - lo) / span, 0)
    lab:SetText(l)
    lab:Show()
  end
  for i = k + 1, #h.labels do h.labels[i]:Hide() end
  h.fillCur:SetWidth(w(cur))
  local nowL = (now and not now.empty) and now.level or cur
  local planL = (plan and not plan.empty) and plan.level or cur
  local plan60 = (plan and not plan.empty) and plan.at60 or cur
  h.fillNow:SetWidth(w(nowL))
  h.fillPlan:SetWidth(w(planL))
  if banking then
    h.legend:SetText(string.format("|cff6f9fffNow %.1f|r    |cffc080c0Banked %.1f|r    |cffd8c8ffLog and pick-ups %.1f|r    |cffaaaaaaAt 60 min %.1f|r",
      cur, nowL, planL, plan60))
  else
    h.legend:SetText(string.format("|cff6f9fffNow %.1f|r    |cffc080c0Ready %.1f|r    |cffd8c8ffLog and pick-ups %.1f|r", cur, nowL, planL))
  end
  local set = QB:Settings()
  local tg = h.toggles
  local mounted = QB:Mounted()
  setIcon(tg.mounted.icon, mounted and T.mount or T.foot)
  tg.mounted.caption:SetText(mounted and "Mounted" or "On foot")
  -- the third switch: the hour's goal when banking, the lock itself when questing
  local g = tg.goal
  if banking then
    g.key = "goal"
    setIcon(g.icon, T.hourglass)
    g.caption:SetText(set.goal == "hour" and "First hour" or "Whole route")
  else
    g.key = "lock"
    setIcon(g.icon, T.questGeneric)
    g.caption:SetText("Questing")
  end
  tg.pins.icon:SetDesaturated(not set.pins)
  tg.pins.caption:SetText(set.pins and "Pins on" or "Pins off")
end

----------------------------------------------------------------------------
-- page 1: the quest log as a bank
----------------------------------------------------------------------------
local LEFT, RIGHT = 16, 420

-- what the finder looks for among the quests you could still take
UI.FINDS = {
  { key = "xp", name = "Highest XP", tip = "The quests that pay the most XP for a slot: advance a chain, fill a free slot, or swap out a weak quest." },
  { key = "gear", name = "Best gear", tip = "Quests whose reward is a piece you can wear or wield, the highest item level first." },
  { key = "trinket", name = "Trinkets", tip = "Quests that reward a trinket, a ring or a necklace, the highest item level first." },
  { key = "recipe", name = "Recipes", tip = "Quests that reward a recipe, pattern, plan or formula." },
}
UI.findMode = "xp"

-- the heaviest armour you can wear, by class: everything lighter fits too. Warriors and paladins wear mail
-- until plate at 40; hunters and shamans leather until mail at 40
local ARMOR = { WARRIOR = 512, PALADIN = 512, HUNTER = 256, SHAMAN = 256, ROGUE = 128, DRUID = 128, MAGE = 64, PRIEST = 64, WARLOCK = 64 }
local function wearable(kinds, level)
  local offered = 0
  for _, bit in ipairs({ 512, 256, 128, 64 }) do if math.floor(kinds / bit) % 2 == 1 then offered = offered + bit end end
  if offered == 0 then return true end -- weapons, rings, trinkets, cloaks: no armour class
  local mine = ARMOR[QB.state.class or ""] or 512
  if (level or 60) < 40 and mine >= 256 then mine = mine / 2 end
  for _, bit in ipairs({ 64, 128, 256, 512 }) do
    if math.floor(offered / bit) % 2 == 1 and bit <= mine then return true end
  end
  return false
end

local function itemName(id)
  if not id or id == 0 then return nil end
  local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
  if not name and GetItemInfo then name = GetItemInfo(id) end
  return name
end

-- the finder's rows for a reward kind: quests you could take (any status but done, wrong or held) whose rewards
-- fit the kind, the best item level first; { q, value, st, reward = { ilvl, kinds, id } }
function UI:FindRewards(kind, level)
  local R = QB.Data.REWARD
  if not R then return {} end
  local out = {}
  for _, c in ipairs(self:Candidates(nil, level)) do
    local r = R[c.id]
    if r and not c.behind then
      local kinds = r[2]
      local hit
      if kind == "gear" then hit = kinds % 2 == 1 and r[1] > 0 and wearable(kinds, level)
      elseif kind == "trinket" then hit = math.floor(kinds / 2) % 2 == 1 or math.floor(kinds / 4) % 2 == 1
      elseif kind == "recipe" then hit = math.floor(kinds / 8) % 2 == 1 end
      if hit then
        local q = Q.Get(c.id)
        if q then out[#out + 1] = { q = q, value = QB.Model.XpAt(q, level), st = QB:Status(q), reward = r, mins = c.mins } end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.reward[1] ~= b.reward[1] then return a.reward[1] > b.reward[1] end
    return a.value > b.value
  end)
  return out
end

local modWatch = CreateFrame("Frame")
modWatch:RegisterEvent("MODIFIER_STATE_CHANGED")
modWatch:SetScript("OnEvent", function()
  local r = UI.hoverRow
  if r and r.rewardId and r:IsVisible() and r.IsMouseOver and r:IsMouseOver() then
    local f = r:GetScript("OnEnter")
    if f then f(r) end
  end
end)

function UI:CreateLogView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()
  v.title = text(v, "GameFontNormalLarge", 15, INK, "LEFT", 150)
  v.title:SetPoint("TOPLEFT", LEFT, -12)
  v.worth = text(v, "GameFontNormal", 12, INK_SOFT, "LEFT", 250)
  v.worth:SetPoint("TOPLEFT", LEFT + 150, -14)
  v.slots = {}
  for i = 1, QB.LOG_SLOTS do
    local b = iconButton(v, 36, nil)
    local col, row = (i - 1) % 8, math.floor((i - 1) / 8)
    b:SetPoint("TOPLEFT", LEFT + 4 + col * 46, -42 - row * 46)
    b.frame = tex(b, "OVERLAY", T.iconFrame)
    b.frame:SetAllPoints()
    b.xp = text(b, "NumberFontNormal", 11, WHITE, "RIGHT", 40)
    b.xp:SetPoint("BOTTOMRIGHT", 0, 2)
    b.mark = tex(b, "OVERLAY", nil, 14, 14)
    b.mark:SetPoint("TOPLEFT", 1, -1)
    b.up = upgradeMark(b, 13, 14)
    b.up:SetPoint("TOPRIGHT", -1, -1)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, which) if self.q then UI.QuestClick(self.q, self.st, which) end end)
    tooltip(b, function(tip, self)
      if self.q then
        if self.pick then tip:AddLine("To pick up: not in your log yet. Click for a waypoint to whoever gives it; right-click to take it off the list.", 1, 0.82, 0, true) end
        UI.QuestTooltip(tip, self.q, self.st, self.value, self.pct, self.plvl)
        if self.advice then tip:AddLine(self.advice, 1, 0.55, 0.45, true) end
      elseif self.entry then
        tip:AddLine(self.entry.title, GOLD[1], GOLD[2], GOLD[3])
        tip:AddLine("Not in QuestBank's catalog, so the route can't place it.", 1, 1, 1, true)
        tip:AddLine(self.entry.complete and "Complete" or "Not complete", 0.8, 0.8, 0.8)
        tip:AddLine("Hand it in or abandon it to free the slot.", 1, 0.55, 0.45, true)
      else
        tip:AddLine("Free slot", GOLD[1], GOLD[2], GOLD[3])
        tip:AddLine("Fill it with the best quest from the swaps on the right.", 1, 1, 1, true)
      end
    end)
    v.slots[i] = b
  end
  v.bagLabel = text(v, "GameFontNormal", 13, INK, "LEFT", 380)
  v.bagLabel:SetPoint("TOPLEFT", LEFT, -278)
  v.bagLabel:SetText("In your bags, no log slot needed")
  v.bagSlots = {}
  for i = 1, 8 do
    local b = iconButton(v, 32, nil)
    b:SetPoint("TOPLEFT", LEFT + 4 + (i - 1) * 46, -300)
    b.count = text(b, "NumberFontNormal", 11, WHITE, "RIGHT", 40)
    b.count:SetPoint("BOTTOMRIGHT", 0, 2)
    tooltip(b, function(tip, self)
      local it = self.item
      if not it then return end
      tip:AddLine(it.name or "", GOLD[1], GOLD[2], GOLD[3])
      if it.need then tip:AddLine(string.format("%d of %d in your bags", QB.API.ItemCount(it.id), it.need), 1, 1, 1) end
      if it.q then UI.QuestTooltip(tip, it.q, QB:Status(it.q), (QB:Value(it.q.id))) end
      if it.id == 211527 then tip:AddLine("Camp in it: your rested XP builds faster.", 0.8, 0.8, 0.8, true) end
    end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", QB.Safe(function(self, which)
      local it = self.item
      if not it then return end
      if IsShiftKeyDown and IsShiftKeyDown() and UI.LinkItem(it.id, it.name) then return end
      if it.q then UI.QuestClick(it.q, QB:Status(it.q), which) end
    end, "bag slot"))
    v.bagSlots[i] = b
  end
  v.dropTitle = text(v, "GameFontNormal", 12, BAD, "LEFT", 300)
  v.dropTitle:SetPoint("TOPLEFT", LEFT, -346)
  v.dropClear = button(v, "Clear", 64)
  v.dropClear:SetPoint("TOPLEFT", LEFT + 316, -342)
  v.dropClear:SetScript("OnClick", function()
    local p = QB:Plan()
    for k in pairs(p.removed) do p.removed[k] = nil end
    UI:Refresh()
  end)
  v.drops = para(v, "GameFontNormalSmall", 11, INK_SOFT, 380)
  v.drops:SetPoint("TOPLEFT", LEFT, -366)
  v.drops:SetHeight(50)

  -- the finder: what to look for in the quests you could still take
  local st = text(v, "GameFontNormalLarge", 15, INK, "LEFT", 320)
  st:SetPoint("TOPLEFT", RIGHT, -12)
  st:SetText("Find quests")
  v.finds = {}
  for i, m in ipairs(UI.FINDS) do
    local b = CreateFrame("Button", nil, v)
    b:SetSize(80, 18)
    b:SetPoint("TOPLEFT", RIGHT + (i - 1) * 84, -34)
    b.hi = tex(b, "HIGHLIGHT", T.rowHi)
    b.hi:SetAllPoints()
    b.hi:SetBlendMode("ADD")
    b.label = text(b, "GameFontNormalSmall", 10, INK_SOFT, "CENTER", 80)
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetText(m.name)
    b.label.base = m.name
    b.key = m.key
    b:SetScript("OnClick", function(self) UI.findMode = self.key; UI:Refresh() end)
    tooltip(b, function(tip, self)
      tip:AddLine(m.name, GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine(m.tip, 1, 1, 1, true)
    end)
    v.finds[i] = b
  end
  v.swaps = {}
  for i = 1, 8 do
    local r = CreateFrame("Button", nil, v)
    r:SetSize(334, 38)
    r:SetPoint("TOPLEFT", RIGHT, -58 - (i - 1) * 40)
    r.hi = tex(r, "HIGHLIGHT", T.rowHi)
    r.hi:SetAllPoints()
    r.hi:SetBlendMode("ADD")

    r.hi:SetAlpha(0.6)
    r.addIcon = tex(r, "ARTWORK", nil, 30, 30)
    r.addIcon:SetPoint("LEFT", 2, 0)
    r.addIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.addName = text(r, "GameFontNormal", 12, INK, "LEFT", 240)
    r.addName:SetPoint("TOPLEFT", 40, -4)
    r.cutName = text(r, "GameFontNormalSmall", 10, INK_SOFT, "LEFT", 240)
    r.cutName:SetPoint("TOPLEFT", 40, -21)
    r.gain = text(r, "GameFontNormal", 13, GOOD, "RIGHT", 52)
    r.gain:SetPoint("RIGHT", -4, 0)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, which)
      local q = self.add
      if not q then return end
      -- on a reward row (Best gear, Trinkets, Recipes), Shift-click links the reward item instead of the quest
      if self.rewardId and which ~= "RightButton" and IsShiftKeyDown and IsShiftKeyDown() then UI.LinkItemAlways(self.rewardId) return end
      -- one path decides where a click sends you: the giver, a chain's first step, a held step's turn-in
      UI.QuestClick(q, QB:Status(q), which)
    end)
    tooltip(r, function(tip, self)
      UI.hoverRow = self
      if self.rewardId and IsShiftKeyDown and IsShiftKeyDown() and tip.SetItemByID then
        tip:SetItemByID(self.rewardId) -- the item itself, as the game shows it
        return
      end
      if self.cutTitle then
        tip:AddLine("Drop: " .. self.cutTitle, 1, 0.5, 0.4)
        tip:AddLine(QB.Comma(self.cutValue or 0) .. " XP " .. QB:OnTheDay(), 0.8, 0.8, 0.8)
        tip:AddLine(" ")
      end
      if self.via then
        tip:AddLine(string.format("Take %s now and hand it in inside %s. That gives you %s" .. (QB:Banking() and " to bank." or "."), self.via.name,
          self.via.cat and self.via.cat.name or "the dungeon", self.add.name), 1, 0.82, 0, true)
        tip:AddLine(" ")
      end
      if self.add then UI.QuestTooltip(tip, self.add, QB:Status(self.add), self.addValue, nil, nil, self.rewardId) end
      if self.reward then tip:AddLine(self.reward, 0.75, 0.75, 1, true) end
      if self.rewardId then tip:AddLine("Hold Shift to see the item. To put the quest on your pick-up list, right-click it.", 0.6, 0.6, 0.6, true) end
    end)
    v.swaps[i] = r
  end
  v.noSwaps = para(v, "GameFontNormal", 12, INK_SOFT, 320)
  v.noSwaps:SetPoint("TOPLEFT", RIGHT, -64)
  v.noSwaps:SetHeight(44)
  v.legend = text(v, "GameFontNormalSmall", 10, INK_SOFT, "LEFT", 334)
  v.legend:SetPoint("TOPLEFT", RIGHT, -384)

  v.Refresh = function() UI:RefreshLogView(v) end
  return v
end

-- the best quests to fetch: for your faction and class, not done, not held, most XP on the day first.
-- Not the ones handed in inside a dungeon: those can't wait in your log for the day.
-- where you stand: the place the route model uses, the mount factor, and the flight master's town
function UI.Here()
  local fac = QB.faction
  local wp = QB.API.WorldPosition()
  local here
  if wp then
    here = QB.Model.Place(fac, wp.c, wp.wx, wp.wy)
    if here.hub == 0 then here = nil end
  end
  local mf = QB:Mounted() and 0.625 or 1
  local hub = here and QB.Data.HUB[fac] and QB.Data.HUB[fac][here.hub]
  return here, mf, hub and hub[1] or nil
end

-- minutes from where you stand to a quest's giver (a giver inside a dungeon: to its entrance, else to its
-- hand-in); nil when the giver can't be placed or you can't
function UI.MinutesTo(q, here, mf)
  if not (here and q) then return nil end
  local D, M, fac = QB.Data, QB.Model, QB.faction
  local giveIdx = q.giveIdx and q.giveIdx > 0 and q.giveIdx or nil
  local to = giveIdx and M.NpcPlace(giveIdx, fac) or nil
  if not to and giveIdx and D.NPC[giveIdx] and D.NPC[giveIdx][5] < 0 then
    local ent = q.cat and q.cat.entrance
    local w = ent and M.World and M.World(ent.m, ent.x, ent.y)
    to = (w and M.Place(fac, w.c, w.wx, w.wy)) or (q.turnIdx and q.turnIdx > 0 and M.NpcPlace(q.turnIdx, fac)) or nil
  end
  if not to then return nil end
  return M.Between(here, to, fac, mf)
end

function UI:Candidates(limit, level)
  local D = QB.Data
  local s = QB.state
  level = level or s.level
  local fac = QB.faction
  local banking = QB:Banking()
  local above, below = QB:Range()
  -- the same question asked several times a refresh: answer it once a second
  local key = table.concat({ limit or 0, level, s.level, s.logCount or 0, tostring(banking), fac or "", s.mapID or 0, above, below, QB:SkipSignature(), QB.doneVer or 0 }, ":")
  local now = GetTime and GetTime() or 0
  UI.candMemo = UI.candMemo or {}
  local memo = UI.candMemo[key]
  if memo and now - memo.t < 1 then return memo.list end
  local bit, rbit = QB.API.ClassBit(), QB.API.RaceBit()
  -- questing: nothing far above you; banking: dungeon quests well above you are the big payers.
  -- Settings can widen or narrow both ends (QB:Range)
  local ceiling = level + above
  -- how far each giver is from you: the minutes column in both modes; questing, nearby quests come first
  local here, mf = UI.Here()
  local out = {}
  for id, r in pairs(D.Q) do
    local side, cls = r[3], r[9]
    local turn = D.NPC[(fac == "H" and D.TURNH and D.TURNH[id]) or r[6]]
    local race = D.RACE[id]
    if (side == 0 or (side == 1 and fac == "A") or (side == 2 and fac == "H"))
      and (cls == 0 or bit == 0 or math.floor(cls / bit) % 2 == 1)
      and (not race or rbit == 0 or rbit > 128 or math.floor(race / rbit) % 2 == 1)
      and r[2] <= s.level + 2 and r[1] >= level - below and r[1] <= ceiling and not s.log[id] and not D.FOLLOW[id]
      and math.floor(r[10] / 128) % 2 == 0 -- never suggest Season of Discovery leftovers
      and math.floor(r[10] / 4096) % 2 == 0 -- nor repeatables
      and not (turn and turn[5] < 0)
      and not QB:Skipped(r[8], turn and turn[5]) then -- nor anything where you said to skip
      local live = QuestBankDB.live and QuestBankDB.live[id]
      out[#out + 1] = { id = id, full = live and live.full or math.floor(r[4] * r[5] + 0.5), lvl = r[1], cat = r[8], give = r[7],
                        turn = (fac == "H" and D.TURNH and D.TURNH[id]) or r[6] }
    end
  end
  local M = QB.Model
  local dropped = 0
  for _, c in ipairs(out) do
    local m = level - c.lvl
    local f = c.full
    if m >= 10 then f = f * 0.1 elseif m >= 6 then f = f * (1 - (m - 5) * 0.2) end
    c.value, c.rank = f, f
    c.behind = QB.Quest.Behind(c.id) and true or nil -- a later step is held or done: probably behind you (banking keeps the raw XP; the swap list leaves it out)
    -- the trip to the giver, in both modes (the Available tab shows the minutes)
    local giveIdx = c.give and c.give > 0 and c.give or nil
    local give = giveIdx and M.NpcPlace(giveIdx, fac) or nil
    local turnP = c.turn and c.turn > 0 and M.NpcPlace(c.turn, fac) or nil
    local to = give
    if not to and giveIdx and D.NPC[giveIdx] and D.NPC[giveIdx][5] < 0 then
      -- a giver inside a dungeon: the trip is to its entrance, or failing that to where it is handed in
      local ent = D.CAT[c.cat] and D.CAT[c.cat].entrance
      local w = ent and M.World and M.World(ent.m, ent.x, ent.y)
      to = (w and M.Place(fac, w.c, w.wx, w.wy)) or turnP
    end
    c.mins = (here and to) and M.Between(here, to, fac, mf) or nil
    if not banking then
      -- questing: XP for the time. The trip to the giver, the quest's own loop from giver to turn-in,
      -- and half of what its chain leads on to.
      -- a giver the catalog can't place (an item drop, a Forever quest nobody has met): no trip is known,
      -- so a modest ten minutes stands in, and it is never dropped on ignorance
      c.away = c.mins or ((here and not to) and 10 or 0)
      c.back = (give and turnP) and M.Between(give, turnP, fac, mf) or 0
      c.lead = QB:ChainLead(c.id)
      local minutes = c.away + c.back + 3 -- three for the quest itself, so one at your feet isn't infinite
      c.time = 1 / (1 + minutes / 10)
      c.rank = (f + c.lead * 0.5) * c.time * (c.behind and 0.25 or 1)
      -- a waste, for the swap list only (the Plan page still lists it in its zone): more than twenty minutes
      -- to a placed giver, or too little XP for the time, judged more strictly the further away: nothing
      -- under four minutes, the full 60 XP a minute (at level 20's scale) from sixteen
      local strict = math.max(0, math.min(1, (c.away - 4) / 12))
      c.waste = here ~= nil and to ~= nil and (c.away > 20 or (strict > 0 and (f + c.lead) / minutes < 60 * QB.Scale(level) * strict))
      if c.waste then dropped = dropped + 1 end
    end
  end
  UI.candDropped = dropped
  table.sort(out, function(a, b) return a.rank > b.rank end)
  local kept = {}
  for _, c in ipairs(out) do
    if not QB.API.IsDone(c.id) then
      kept[#kept + 1] = c
      if limit and #kept >= limit then break end
    end
  end
  local n = 0
  for k, m in pairs(UI.candMemo) do if now - m.t >= 1 then UI.candMemo[k] = nil else n = n + 1 end end
  UI.candMemo[key] = { t = now, list = kept }
  return kept
end

function UI:RefreshLogView(v)
  local s = QB.state
  local entries, total = {}, 0
  for _, e in ipairs(s.logOrder) do
    local q = Q.Get(e.id)
    local value = q and QB:Value(e.id) or nil
    local it = { e = e, q = q, value = value }
    if q then
      it.st = QB:Status(q)
      it.cut = QB:IsCut(e.id)
      if not it.cut then total = total + (value or 0) end
    end
    entries[#entries + 1] = it
  end
  table.sort(entries, function(a, b)
    if (a.cut or false) ~= (b.cut or false) then return not a.cut end
    return (a.value or -1) > (b.value or -1)
  end)
  v.title:SetText(string.format("Quest log  %d/%d", #entries, QB.LOG_SLOTS))
  -- the quests you chose to pick up fill the free slots, faded, with the pick-up mark: still yours to fetch
  local picks = {}
  for id in pairs(QB:Plan().add) do
    local q = Q.Get(id)
    if q and not s.log[id] then
      local st = QB:Status(q)
      if st.code ~= "done" and st.code ~= "wrong" then picks[#picks + 1] = { q = q, st = st, value = QB.Model.XpAt(q, s.level) } end
    end
  end
  table.sort(picks, function(a, b) return a.value > b.value end)
  -- the colour steps, at your level
  local k = QB.Scale(s.level)
  local function step(x)
    x = x * k
    if x >= 1000 then return QB.Short(math.floor(x / 100 + 0.5) * 100) end
    return tostring(math.floor(x / 10 + 0.5) * 10)
  end
  v.legend:SetText(string.format("|cffff8000Orange|r %s+  |cffa335eePurple|r %s+  |cff0070ddBlue|r %s+  |cff1eff00Green|r %s+  White %s+",
    step(12000), step(9000), step(6000), step(3000), step(1500)))
  local overflow = #picks - (QB.LOG_SLOTS - #entries)
  if overflow > 0 then
    v.worth:SetText(string.format("worth about %s XP · %d more to pick up", QB.Comma(total), overflow))
  else
    v.worth:SetText(string.format("worth about %s XP %s", QB.Comma(total), QB:OnTheDay()))
  end
  for i, b in ipairs(v.slots) do
    local it = entries[i]
    b.q, b.st, b.entry, b.value, b.pct, b.plvl, b.pick, b.advice = nil, nil, nil, nil, nil, nil, nil, nil
    b.icon:SetAlpha(1)
    b.frame:SetAlpha(1)
    if it then
      b.entry, b.value = it.e, it.value
      -- what to do about a slot that earns nothing: the advice the old Make room card gave
      if it.q then
        local low = (it.value or 0) < 500 * QB.Scale(s.level)
        if it.cut then b.advice = QB.Data.CUT_NOTES[it.e.id] or "Left out of the route: hand it in or abandon it to free the slot."
        elseif low then b.advice = QB.Data.CUT_NOTES[it.e.id] or string.format(it.e.complete and "Pays next to nothing at level %d: hand it in now for the rewards." or "Pays next to nothing at level %d: abandon it to free the slot.", s.level) end
      end
      if it.q then b.q, b.st = it.q, it.st end
      setIcon(b.icon, it.q and it.q.icon or (it.e.complete and T.questActive or T.questAvail))
      b.icon:SetDesaturated(it.cut or false)
      local c = QUALITY[tier(it.value)]
      b.frame:SetVertexColor(c[1], c[2], c[3])
      b.frame:SetShown(not it.cut)
      b.xp:SetText((it.value and not (it.q and it.q.xpUnknown and not it.q.liveFull)) and QB.Short(it.value) or "?")
      if it.cut or not it.q then
        b.mark:SetTexture(T.notready)
      elseif it.e.complete then
        b.mark:SetTexture(T.ready)
      else
        b.mark:SetTexture(T.waiting)
      end
      b.mark:Show()
      b.up:SetShown(it.q ~= nil and not it.cut and QB:Upgrade(it.q) ~= nil)
    else
      local pk = picks[i - #entries]
      if pk then
        b.q, b.st, b.value, b.pick = pk.q, pk.st, pk.value, true
        setIcon(b.icon, pk.q.icon)
        b.icon:SetDesaturated(false)
        b.icon:SetAlpha(0.55)
        local c = QUALITY[tier(pk.value)]
        b.frame:SetVertexColor(c[1], c[2], c[3])
        b.frame:SetAlpha(0.55)
        b.frame:Show()
        b.xp:SetText(QB.Short(pk.value))
        b.mark:SetTexture(T.questAvail)
        b.mark:Show()
        b.up:Hide()
      else
        b.icon:SetTexture(nil)
        b.frame:Hide()
        b.xp:SetText("")
        b.mark:Hide()
        b.up:Hide()
      end
    end
  end

  -- bags: the sleeping bag, and quests that wait in your bags
  local bagItems = {}
  for _, it in ipairs(QB.Data.TRACKED_ITEMS) do
    if not it.side or (it.side == 1 and QB.faction == "A") or (it.side == 2 and QB.faction == "H") then
      local q = it.quest and Q.Get(it.quest)
      if not (q and QB.API.IsDone(q.id)) then
        bagItems[#bagItems + 1] = { id = it.id, name = it.name, need = it.need, icon = it.icon, q = q }
      end
    end
  end
  for id in pairs(s.bagStarts) do
    local q = Q.Get(id)
    local dup = false
    for _, b in ipairs(bagItems) do if b.q and b.q.id == id then dup = true end end
    -- an item for a quest you already handed in starts nothing any more
    if q and not dup and not QB.API.IsDone(id) then bagItems[#bagItems + 1] = { id = q.bag and q.bag[1], name = q.name, q = q, icon = q.icon } end
  end
  for i, b in ipairs(v.bagSlots) do
    local it = bagItems[i]
    b.item = it
    if it then
      local n = it.id and QB.API.ItemCount(it.id) or 1
      setIcon(b.icon, QB.API.ItemIcon(it.id, it.icon))
      b.icon:SetDesaturated(n == 0)
      b.count:SetText((it.need and it.need > 1) and (n .. "/" .. it.need) or "")
      b:Show()
    else
      b:Hide()
    end
  end

  -- quests that left the log without a hand-in, and quests the catalog can't place
  local p = QB:Plan()
  local lines = {}
  for _, r in pairs(p.removed) do
    lines[#lines + 1] = r.title .. (r.value and ("  " .. QB.Short(r.value)) or "")
  end
  table.sort(lines)
  local unknown = QB:Unknown()
  v.dropTitle:SetShown(#lines > 0 or #unknown > 0)
  v.dropClear:SetShown(#lines > 0)
  if #lines > 0 then
    v.dropTitle:SetText("Left your log without a hand-in")
    local shown = {}
    for i = 1, math.min(3, #lines) do shown[i] = lines[i] end
    local extra = #lines > 3 and string.format("  and %d more", #lines - 3) or ""
    v.drops:SetText(table.concat(shown, ",  ") .. extra)
  elseif #unknown > 0 then
    v.dropTitle:SetText("Not in QuestBank's catalog")
    local names = {}
    for i = 1, math.min(4, #unknown) do names[i] = unknown[i].title end
    v.drops:SetText(table.concat(names, ",  ") .. ". The route can't place them.")
  else
    v.drops:SetText("")
  end

  -- the finder's mode buttons
  for _, b in ipairs(v.finds) do
    local on = b.key == UI.findMode
    local col = on and INK or INK_SOFT
    b.label:SetTextColor(col[1], col[2], col[3])
    b.label:SetText(on and ("[" .. b.label.base .. "]") or b.label.base)
  end
  if UI.findMode ~= "xp" then
    local found = self:FindRewards(UI.findMode, s.level)
    for i, r in ipairs(v.swaps) do
      local d = found[i]
      if d then
        r:Show()
        r.add, r.addValue, r.via, r.cutTitle, r.cutValue = d.q, d.value, nil, nil, nil
        local id = d.reward[3]
        local name = itemName(id) or (id and id > 0 and ("item " .. id)) or (UI.findMode == "recipe" and "a recipe" or "a reward")
        setIcon(r.addIcon, (id and id > 0 and QB.API.ItemIcon(id, d.q.icon)) or d.q.icon)
        r.addName:SetText(d.q.name)
        local place = d.q.cat and d.q.cat.name or ""
        local mins = d.mins and string.format(", %d min", math.floor(d.mins + 0.5)) or ""
        local room = r.cutName:GetWidth() - 2
        for _, line in ipairs({ name .. " · " .. place .. mins, name .. " · " .. place, name }) do
          r.cutName:SetText(line)
          if r.cutName:GetStringWidth() <= room then break end
        end
        r.gain:SetText(d.reward[1] > 0 and ("iL " .. d.reward[1]) or QB.Short(d.value))
        r.reward = string.format("Rewards %s%s. %s XP %s.", name, d.reward[1] > 0 and string.format(" (item level %d)", d.reward[1]) or "", QB.Comma(d.value), QB:OnTheDay())
        r.rewardId = (id and id > 0) and id or nil
      else
        r:Hide()
      end
    end
    v.noSwaps:SetShown(#found == 0)
    v.noSwaps:SetText(UI.findMode == "gear" and "No quest within your level range rewards a piece you can wear. Settings widens the range."
      or UI.findMode == "trinket" and "No quest within your level range rewards a trinket, ring or necklace."
      or "No quest within your level range rewards a recipe.")
    return
  end
  for _, r in ipairs(v.swaps) do r.reward, r.rewardId = nil, nil end

  -- swaps: advance a chain you hold, fill a free slot, or swap a weak quest for a better one
  local lvl = s.level
  local rows, used = {}, {}
  -- a chain you hold: the best later step you could bank instead (questing, the arrows show chains)
  for _, it in ipairs(entries) do
    if QB:Banking() and it.q and it.q.nextSteps and not it.cut then
      local best, bestV, bestDepth
      local function walk(q, depth)
        if depth > 3 or not q.nextSteps then return end
        for _, nid in ipairs(q.nextSteps) do
          local nq = Q.Get(nid)
          if nq and Q.ForMe(nq) and not QB.API.IsDone(nid) and not s.log[nid] and (nq.req or 1) <= lvl
            and not nq.sodLeftover and not nq.repeatable and not QB.Quest.Behind(nq.id) and not QB:SkipsQuest(nq) then
            local v = QB.Model.XpAt(nq, lvl)
            -- a step handed in inside a dungeon can't be banked; the one after it can
            if not (nq.turn and nq.turn.inside) and (not bestV or v > bestV) then best, bestV, bestDepth = nq, v, depth end
            walk(nq, depth + 1)
          end
        end
      end
      walk(it.q, 1)
      if best and bestV > (it.value or 0) + 300 * QB.Scale(lvl) then
        rows[#rows + 1] = { add = { q = best, value = bestV }, cut = it, cutValue = it.value or 0, gain = bestV - (it.value or 0),
                            chain = bestDepth }
        used[best.id] = true
      end
    end
  end
  local cuts = {}
  for _, it in ipairs(entries) do
    if it.cut or not it.q or (it.value or 0) < 1500 * QB.Scale(lvl) then cuts[#cuts + 1] = it end
  end
  table.sort(cuts, function(a, b)
    if (a.cut or false) ~= (b.cut or false) then return a.cut end
    return (a.value or 0) < (b.value or 0)
  end)
  local adds = {}
  for _, c in ipairs(self:Candidates(60)) do
    if c.waste or c.behind then c = nil end -- questing: a long run for little is no suggestion
    if c then
    local q = Q.Get(c.id)
    local st = q and QB:Status(q)
    -- quests you can pick up now and that need a log slot, and the ones a single step handed in inside
    -- the dungeon stands before (Blackfathom Villainy after In Search of Thaelrid): take that step, finish
    -- it in there, bank what it gives you. Longer chains and bag quests live on the Plan page.
    local via
    if q and st.code == "prereq" and type(st.pre) == "number" then
      local p = Q.Get(st.pre)
      if p and p.turn and p.turn.inside and QB:Status(p).code == "todo" then via = p end
    end
    local chain
    if q and st.code == "prereq" and not via then chain = QB:ChainCost(q) end
    if q and not used[q.id] and not QB:IsAdded(q.id) and (st.code == "todo" or via or chain) and not (q.bag and q.bag[3] == 1) then
      adds[#adds + 1] = { q = q, value = QB.Model.XpAt(q, lvl), st = st, via = via, chain = chain, rank = c.rank, lead = c.lead }
    end
    end
  end
  local ai = 1
  for _ = 1, QB.LOG_SLOTS - #entries do
    if adds[ai] then rows[#rows + 1] = { add = adds[ai], cutValue = 0, gain = adds[ai].value }; ai = ai + 1 end
  end
  for _, c in ipairs(cuts) do
    local a = adds[ai]
    if not a then break end
    local cv = c.cut and 0 or (c.value or 0)
    if a.value > cv + 300 * QB.Scale(lvl) then
      rows[#rows + 1] = { cut = c, add = a, cutValue = cv, gain = a.value - cv }
      ai = ai + 1
    end
  end
  -- banking: the biggest gain first; questing: the gain for the trip (nearby first)
  for _, r in ipairs(rows) do
    local near = (not QB:Banking() and r.add.rank and r.add.value and r.add.value > 0) and r.add.rank / r.add.value or 1
    r.key = r.gain * near
  end
  table.sort(rows, function(a, b) return a.key > b.key end)
  for i, r in ipairs(v.swaps) do
    local d = rows[i]
    if d then
      r:Show()
      r.add, r.addValue, r.via = d.add.q, d.add.value, d.add.via
      r.cutTitle = d.cut and d.cut.e.title or nil
      r.cutValue = d.cutValue
      if d.chain then
        r.cutName:SetText("hand in " .. d.cut.e.title .. " now, " .. (d.chain > 1 and string.format("%d steps on", d.chain) or "bank the next step"))
      else
        -- the line under the name: what it replaces, then what it costs or leads to, as far as the room allows
        local base = d.cut and ("instead of " .. d.cut.e.title .. (d.cutValue > 0 and ("  " .. QB.Short(d.cutValue)) or "")) or "into a free slot"
        local ch = d.add.chain
        local mins = ch and ch.minutes and ch.minutes > 0 and string.format(", ~%d min", ch.minutes) or ""
        local long = ch and string.format(" · %d step%s first%s", ch.n, ch.n == 1 and "" or "s", mins) or ""
        local short = ch and string.format(" · %d step%s%s", ch.n, ch.n == 1 and "" or "s", mins) or ""
        -- questing: what the quest leads on to is part of why it's here
        local lead = (not QB:Banking() and d.add.lead and d.add.lead > 0 and not ch) and (" · leads to +" .. QB.Short(d.add.lead)) or ""
        local classic = (d.add.q.classic and not d.add.q.liveFull) and " · Classic only" or ""
        local room = r.cutName:GetWidth() - 2
        for _, line in ipairs({ base .. long .. lead .. classic, base .. short .. classic, base .. short .. lead, base .. short, base .. lead, base }) do
          r.cutName:SetText(line)
          if r.cutName:GetStringWidth() <= room then break end
        end
      end
      setIcon(r.addIcon, d.add.q.icon)
      r.addName:SetText(d.add.q.name)
      r.gain:SetText("+" .. QB.Short(d.gain))
    else
      r:Hide()
    end
  end
  v.noSwaps:SetShown(#rows == 0)
  v.noSwaps:SetText("No swap gains XP right now. Everything in your log earns its slot.")
end

----------------------------------------------------------------------------
-- page 2: prep
----------------------------------------------------------------------------
local function makeRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(22)
  r.hi = tex(r, "HIGHLIGHT", T.rowHi)
  r.hi:SetAllPoints()
  r.hi:SetBlendMode("ADD")

  r.hi:SetAlpha(0.6)
  -- the mark sits on a small button: on a quest you can pick up, a click puts it on your pick-up list
  r.pick = CreateFrame("Button", nil, r)
  r.pick:SetSize(20, 20)
  r.pick:SetPoint("LEFT", 1, 0)
  r.mark = tex(r.pick, "ARTWORK", nil, 14, 14)
  r.mark:SetPoint("CENTER", 0, 0)
  r.pick:SetScript("OnClick", QB.Safe(function(self)
    local row = self:GetParent()
    if self.pickable and row.q then QB:ToggleAdd(row.q.id); UI:Refresh() end
  end, "pick up"))
  tooltip(r.pick, function(tip, self)
    local row = self:GetParent()
    if self.pickable and row.q then
      if QB:IsAdded(row.q.id) then
        tip:AddLine("To pick up", GOLD[1], GOLD[2], GOLD[3])
        tip:AddLine("Click: take it off your pick-up list.", 1, 1, 1, true)
      else
        tip:AddLine("Pick it up", GOLD[1], GOLD[2], GOLD[3])
        tip:AddLine("Click: put it on your pick-up list. It shows in your Quest Log as To pick up, with a ! on its giver on the map.", 1, 1, 1, true)
      end
    elseif row.q then
      UI.QuestTooltip(tip, row.q, row.st, row.value)
    else
      tip:AddLine(row.step and row.step.name or (row.entry and row.entry.title) or "", GOLD[1], GOLD[2], GOLD[3])
    end
  end)
  r.icon = tex(r, "ARTWORK", nil, 18, 18)
  r.icon:SetPoint("LEFT", 22, 0)
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.name = text(r, "GameFontNormal", 12, INK, "LEFT", 270)
  r.name:SetPoint("LEFT", 46, 0)
  r.up = upgradeMark(r, 10, 11)
  r.up:SetPoint("LEFT", 320, 0)
  r.lvl = text(r, "GameFontNormalSmall", 10, INK_SOFT, "LEFT", 30)
  r.lvl:SetPoint("LEFT", 340, 0)
  r.status = text(r, "GameFontNormalSmall", 11, INK, "LEFT", 250)
  r.status:SetPoint("LEFT", 392, 0)
  r.away = text(r, "GameFontNormalSmall", 11, INK_SOFT, "RIGHT", 40)
  r.away:SetPoint("RIGHT", -72, 0)
  r.xp = text(r, "GameFontNormal", 12, INK, "RIGHT", 60)
  r.xp:SetPoint("RIGHT", -8, 0)
  -- a chain: open it to see every step, done, held, next and later
  r.chain = CreateFrame("Button", nil, r)
  r.chain:SetSize(16, 16)
  r.chain:SetPoint("LEFT", 372, 0)
  r.chain.label = text(r.chain, "GameFontNormalSmall", 11, { 0.45, 0.25, 0.05 }, "CENTER", 16)
  r.chain.label:SetPoint("CENTER", 0, 0)
  r.chain:SetScript("OnClick", QB.Safe(function(self)
    local row = self:GetParent()
    if not row.q then return end
    UI.chainOpen = UI.chainOpen or {}
    UI.chainOpen[row.q.id] = not UI.chainOpen[row.q.id] or nil
    UI:Refresh()
  end, "chain"))
  tooltip(r.chain, function(tip, self)
    local row = self:GetParent()
    tip:AddLine("The chain", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine((UI.chainOpen and row.q and UI.chainOpen[row.q.id]) and "Click: fold it away." or "Click: every step of it, done, in your log, next and later, under this row.", 1, 1, 1, true)
  end)
  r.chain:Hide()
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self, which)
    if self.q then UI.QuestClick(self.q, self.st, which)
    elseif self.entry then
      local q = Q.Get(self.entry.id)
      if q then UI.QuestClick(q, QB:Status(q), which) end
    elseif self.step and self.step.m then QB.API.SetWaypoint(self.step.m, self.step.x, self.step.y, self.step.name) end
  end)
  tooltip(r, function(tip, self)
    if self.q then
      UI.QuestTooltip(tip, self.q, self.st, self.value)
      if self.together then tip:AddLine("Done in the same spot as: " .. table.concat(self.together, ", ") .. ". Do them together.", 0.75, 0.75, 1, true) end
    elseif self.entry then
      tip:AddLine(self.entry.title, GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine(self.advice or "", 1, 0.55, 0.45, true)
    elseif self.step then
      tip:AddLine(self.step.name, GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine(self.step.where, 1, 1, 1, true)
      if self.step.m then tip:AddLine("Click: map pin.", 0.5, 0.5, 0.5) end
    end
  end)
  return r
end

local function makeCard(parent)
  local c = CreateFrame("Frame", nil, parent, BD)
  backdrop(c, nil, T.tipBorder, 12, 3)
  if c.SetBackdropBorderColor then c:SetBackdropBorderColor(0.45, 0.33, 0.16, 0.9) end
  c.art = tex(c, "BACKGROUND")
  c.art:SetPoint("TOPLEFT", 3, -3)
  c.art:SetPoint("TOPRIGHT", -3, -3)
  c.art:SetHeight(42)
  c.shade = tex(c, "BORDER")
  c.shade:SetColorTexture(0.06, 0.04, 0.02, 0.55)
  c.shade:SetAllPoints(c.art)
  c.icon = tex(c, "ARTWORK", nil, 32, 32)
  c.icon:SetPoint("TOPLEFT", 10, -8)
  c.title = text(c, "GameFontNormalLarge", 15, GOLD, "LEFT", 380)
  c.title:SetPoint("TOPLEFT", 50, -9)
  c.where = text(c, "GameFontHighlightSmall", 11, WHITE, "LEFT", 420)
  c.where:SetPoint("TOPLEFT", 50, -28)
  c.gain = text(c, "GameFontNormalLarge", 15, GOLD, "RIGHT", 150)
  c.gain:SetPoint("TOPRIGHT", -50, -9)
  c.count = text(c, "GameFontHighlightSmall", 11, WHITE, "RIGHT", 150)
  c.count:SetPoint("TOPRIGHT", -50, -28)
  c.pin = pinButton(c, 22)
  c.pin:SetPoint("TOPRIGHT", -12, -7)
  c.pin:SetScript("OnClick", function(self)
    local e = self.entrance
    if e then QB.API.SetWaypoint(e.m, e.x, e.y, self.label) end
  end)
  tooltip(c.pin, function(tip, self) tip:AddLine("Map pin: " .. (self.label or ""), GOLD[1], GOLD[2], GOLD[3]) end)
  -- skip this place: nothing here is suggested until you click again (Settings lists the skipped ones)
  c.skip = CreateFrame("Button", nil, c)
  c.skip:SetSize(34, 14)
  c.skip:SetPoint("TOPRIGHT", -8, -31)
  c.skip.label = text(c.skip, "GameFontNormalSmall", 11, WHITE, "RIGHT", 34)
  c.skip.label:SetPoint("RIGHT", 0, 0)
  c.skip:SetScript("OnClick", QB.Safe(function(self)
    if self.key then QB:SetSkip(self.key, not QB:Settings().skipCat[self.key]) end
  end, "plan: skip"))
  tooltip(c.skip, function(tip, self)
    local on = self.key and QB:Settings().skipCat[self.key]
    tip:AddLine(on and "Skipped: nothing here is suggested." or "Skip this place: QuestBank stops suggesting quests here.", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine(on and "Click to bring it back." or "Click again to bring it back; Settings and /qb skip list them.", 0.8, 0.8, 0.8, true)
  end)
  c.rows = pool(c, makeRow)
  c.more = CreateFrame("Button", nil, c)
  c.more:SetSize(400, 18)
  c.more.label = text(c.more, "GameFontNormalSmall", 11, { 0.45, 0.25, 0.05 }, "LEFT", 400)
  c.more.label:SetPoint("LEFT", 0, 0)
  c.more:SetScript("OnClick", function(self)
    UI.expanded = UI.expanded or {}
    UI.expanded[self.key] = not UI.expanded[self.key] or nil
    UI:Refresh()
  end)
  return c
end

-- the marks are the game's own language: a green check for a quest ready to hand in, the waiting disc for
-- one in your log, the yellow ! for one you can pick up (chosen or not), a red X for one you cut
local MARK = { banked = "ready", active = "waiting", partial = "waiting", bagstart = "waiting" }
STATUS.pickup = { 0.25, 0.25, 0.45 }

-- it = { q, st, value, held, chosen, cut, mins, sub (a step shown under its chain), together (names) }
local function fillRow(r, it, width)
  local q, st = it.q, it.st
  r.q, r.st, r.entry, r.step, r.value, r.together = q, st, nil, nil, it.value, it.together
  r:SetWidth(width)
  local held, chosen = it.held, it.chosen
  local pickable = not held and st.code ~= "done" and not st.behind and (st.code == "todo" or st.code == "item")
  local mark
  if it.cut then mark = T.notready
  elseif held and MARK[st.code] then mark = T[MARK[st.code]]
  elseif pickable then mark = T.questAvail end
  if mark then r.mark:SetTexture(mark); r.mark:Show() else r.mark:Hide() end
  r.pick.pickable = pickable or nil
  r.pick:EnableMouse(pickable and true or false)
  setIcon(r.icon, q.icon)
  r.icon:SetDesaturated(st.code == "done" or st.code == "locked" or st.behind or false)
  r.name:SetText((it.sub and "\226\134\179 " or "") .. q.name)
  local c = (held or chosen) and INK or INK_SOFT
  r.name:SetTextColor(c[1], c[2], c[3])
  r.up:SetShown(held and not it.cut and QB:Upgrade(q) ~= nil)
  r.lvl:SetText("L" .. q.lvl)
  local mins = (not held and st.code ~= "done" and not st.behind) and it.mins or nil
  local awayText = mins and (mins < 1 and "here" or string.format("%d min", math.floor(mins + 0.5))) or ""
  -- a chain opens under its row; a step shown under one carries no toggle of its own
  local chained = not it.sub and ((q.pre ~= nil) or (q.nextSteps ~= nil and #q.nextSteps > 0))
  if chained then
    r.chain.label:SetText((UI.chainOpen and UI.chainOpen[q.id]) and "\226\150\190" or "\226\150\184")
    r.chain:Show()
  else
    r.chain:Hide()
  end
  -- a chain's row says what its steps cost; the minutes to its giver would only crowd that out
  if st.code == "prereq" then awayText = "" end
  -- the minutes column takes room from the status only when it has something to say
  r.status:SetWidth(math.max(120, width - 392 - 76 - (awayText ~= "" and 48 or 0)))
  local status, color = st.text, STATUS[st.code] or INK
  if chosen and not st.behind then
    if st.code == "todo" or st.code == "item" then status, color = "To pick up", STATUS.pickup
    else status = "To pick up. " .. st.text end
  end
  -- from the Classic database, not seen in Forever yet: said in the row, not only the tooltip
  if q.classic and not q.liveFull and st.code ~= "done" and st.code ~= "banked" and st.code ~= "active" and st.code ~= "partial" then status = status .. " · Classic only" end
  if st.code == "prereq" then
    local cc = QB:ChainCost(q)
    if cc and cc.minutes and cc.minutes > 0 then
      local room = r.status:GetWidth() - 4
      for _, suffix in ipairs({ string.format(", ~%d min on the move", cc.minutes), string.format(", ~%d min", cc.minutes) }) do
        r.status:SetText(status .. suffix)
        if r.status:GetStringWidth() <= room then status = status .. suffix break end
      end
    end
  end
  if it.together and #it.together > 0 then
    local room = r.status:GetWidth() - 4
    local suffix = string.format(" · with %d", #it.together)
    r.status:SetText(status .. suffix)
    if r.status:GetStringWidth() <= room then status = status .. suffix end
  end
  r.status:SetText(status)
  r.status:SetTextColor(color[1], color[2], color[3])
  r.away:SetText(awayText)
  r.xp:SetText(QB.Comma(it.value or Q.Full(q)))
end

-- the whole line of a chain, for the drill-down: the steps before this quest (done, in your log, or still to
-- take), then the steps after it along the best-paying branch, three on at most
function UI.ChainLine(q, here, mf)
  local s, D = QB.state, QB.Data
  local out, seen = {}, { [q.id] = true }
  local function item(sq, done)
    if not sq or seen[sq.id] then return end
    seen[sq.id] = true
    local held = s.log[sq.id] ~= nil
    local st = (done and not held) and { code = "done", text = "Done" } or QB:Status(sq)
    out[#out + 1] = { q = sq, st = st, value = QB.Model.XpAt(sq, s.level), held = held or st.bag or false,
                      chosen = (not held) and st.code ~= "done" and QB:IsAdded(sq.id) or false, cut = held and QB:IsCut(sq.id) or false,
                      mins = UI.MinutesTo(sq, here, mf), sub = true }
  end
  for _, p in ipairs(q.pre or {}) do
    local sq = QB:PreStep(p) or (type(p) ~= "table" and Q.Get(p)) or nil
    item(sq, Q.PreDone(p))
  end
  local cur, hops = q, 0
  while cur and cur.nextSteps and hops < 3 do
    local best, bestV
    for _, nid in ipairs(cur.nextSteps) do
      local nq = Q.Get(nid)
      if nq and Q.ForMe(nq) and not seen[nid] then
        local v = QB.Model.XpAt(nq, s.level)
        if not bestV or v > bestV then best, bestV = nq, v end
      end
    end
    if not best then break end
    item(best, false)
    cur, hops = best, hops + 1
  end
  return out
end

-- the quests among these done in the same spot (their objective areas within 300 yards, from D.OBJ):
-- sets it.together = { names of the others } on each member of a group
function UI.Together(items)
  local OBJ = QB.Data.OBJ
  if not OBJ then return end
  local placed = {}
  for _, it in ipairs(items) do
    if it.q and it.st.code ~= "done" and OBJ[it.q.id] then placed[#placed + 1] = it end
  end
  for i = 1, #placed do
    for j = i + 1, #placed do
      local a, b = placed[i], placed[j]
      local near = false
      for _, pa in ipairs(OBJ[a.q.id]) do
        for _, pb in ipairs(OBJ[b.q.id]) do
          if pa[1] == pb[1] then
            local dx, dy = pa[2] - pb[2], pa[3] - pb[3]
            if dx * dx + dy * dy <= 300 * 300 then near = true end
          end
        end
      end
      if near then
        a.together = a.together or {}; b.together = b.together or {}
        a.together[#a.together + 1] = b.q.name
        b.together[#b.together + 1] = a.q.name
      end
    end
  end
end

function UI:CreatePrepView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()
  v.scroll = scrollArea(v)
  local child = v.scroll.child
  v.intro = text(child, "GameFontNormal", 12, INK_SOFT, "LEFT", 470)
  v.intro:SetPoint("TOPLEFT", 4, -4)
  v.introR = text(child, "GameFontNormal", 12, INK_SOFT, "RIGHT", 200)
  v.introR:SetPoint("TOPLEFT", 486, -4)
  v.cards = pool(child, makeCard)
  v.foot = text(child, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", 660)
  v.foot:Hide()
  v.empty = para(child, "GameFontNormal", 13, INK_SOFT, 560)
  v.empty:SetPoint("TOPLEFT", 60, -40)
  v.empty:SetHeight(40)
  v.empty:Hide()
  v.Refresh = function() UI:RefreshPrepView(v) end
  return v
end

local PER_CARD = 8
-- every quest for you by place: what you hold, what you chose to pick up, what you could pick up now, what
-- comes later, and what a later step says you have already done
function UI:RefreshPrepView(v)
  local D = QB.Data
  local s = QB.state
  local level = s.level
  local fac = QB.faction
  local banking = QB:Banking()
  local M = QB.Model
  local width = v.scroll:Width() - 6
  v.cards:Reset()
  local here, mf, hubName = UI.Here()

  local groups, order = {}, {}
  local function group(cat)
    local g = groups[cat]
    if not g then
      g = { cat = D.CAT[cat], idx = cat, quests = {}, left = 0, fetch = 0, avail = 0, score = 0,
            held = 0, ready = 0, picks = 0, open = 0, notyet = 0, behind = 0, done = 0, nearest = nil, lvlSum = 0, lvlN = 0 }
      groups[cat] = g
      order[#order + 1] = g
    end
    return g
  end
  local seen = {}
  -- grp: 1 to pick up, 2 available now, 3 in your log, 4 not yet, 5 probably behind you, 6 done (counted, not shown)
  local function add(q, near, mins)
    if seen[q.id] then return end
    seen[q.id] = true
    local st = QB:Status(q)
    if st.code == "wrong" then return end
    local value = M.XpAt(q, level)
    local g = group(D.Q[q.id][8])
    local held = s.log[q.id] ~= nil or st.bag or false
    local chosen = (not held) and st.code ~= "done" and QB:IsAdded(q.id) or false
    local cut = held and QB:IsCut(q.id) or false
    local it = { q = q, st = st, value = value, held = held, chosen = chosen, cut = cut, mins = mins }
    if st.code == "done" then it.grp = 6
    elseif held then it.grp = 3
    elseif chosen then it.grp = 1
    elseif st.behind then it.grp = 5
    elseif st.code == "todo" or st.code == "item" then it.grp = 2
    else it.grp = 4 end
    g.quests[#g.quests + 1] = it
    if held then
      g.held = g.held + 1
      if st.code == "banked" then g.ready = g.ready + 1 elseif not cut then g.left = g.left + value end
      g.score = g.score + value
    elseif chosen then
      g.picks = g.picks + 1
      g.left = g.left + value
      g.score = g.score + value
    elseif st.code == "done" then
      g.done = g.done + 1
    else
      if it.grp == 2 then g.open = g.open + 1 elseif it.grp == 4 then g.notyet = g.notyet + 1 else g.behind = g.behind + 1 end
      g.fetch = g.fetch + value
      g.avail = g.avail + value * (near or 1)
      g.score = g.score + value * 0.25 * (near or 1)
    end
    if mins and not held and st.code ~= "done" and (not g.nearest or mins < g.nearest) then g.nearest = mins end
    if st.code ~= "done" then g.lvlSum, g.lvlN = g.lvlSum + q.lvl, g.lvlN + 1 end
  end
  for _, e in ipairs(s.logOrder) do local q = Q.Get(e.id); if q then add(q, 1) end end
  for _, id in ipairs(QB:BagQuests()) do
    local q = Q.Get(id)
    -- quests you hold as an item in your bags; the rest are ordinary candidates below
    if q and (s.bagStarts[id] or QB.API.ItemCount(q.bag[1]) > 0) then add(q, 1) end
  end
  -- every quest you could fetch, with the minutes to its giver; questing, a zone near you outranks a richer
  -- one across the world (never above one: the lead is for the swap list)
  for _, c in ipairs(self:Candidates(nil, level)) do
    add(Q.Get(c.id), c.time or 1, c.mins)
  end
  -- what you chose outside the window or in a place you skip still shows, with its minutes
  for id in pairs(QB:Plan().add) do
    local q = Q.Get(id)
    if q and not seen[id] then add(q, 1, UI.MinutesTo(q, here, mf)) end
  end
  -- what you have done in each place, counted for the card
  local bit, rbit = QB.API.ClassBit(), QB.API.RaceBit()
  for id, r in pairs(D.Q) do
    local g = groups[r[8]]
    if g and not seen[id] then
      local side, cls, race = r[3], r[9], D.RACE[id]
      if (side == 0 or (side == 1 and fac == "A") or (side == 2 and fac == "H"))
        and (cls == 0 or bit == 0 or math.floor(cls / bit) % 2 == 1)
        and (not race or rbit == 0 or rbit > 128 or math.floor(race / rbit) % 2 == 1)
        and QB.API.IsDone(id) then g.done = g.done + 1 end
    end
  end
  -- questing: zone by zone from the lowest, an order that holds still while you move (the minutes column says
  -- what is near); banking: the richest place first, what you hold plus what you could fetch
  for _, g in ipairs(order) do g.band = g.lvlN > 0 and g.lvlSum / g.lvlN or 99 end
  table.sort(order, function(a, b)
    if not banking then
      if math.abs(a.band - b.band) >= 0.5 then return a.band < b.band end
      return (a.cat.name or "") < (b.cat.name or "")
    end
    local ka, kb = a.left + a.avail, b.left + b.avail
    if ka ~= kb then return ka > kb end
    return a.score > b.score
  end)

  -- the intro: the window and where the minutes count from
  local above, below = QB:Range()
  local picksAll, openAll = 0, 0
  for _, g in ipairs(order) do picksAll, openAll = picksAll + g.picks, openAll + g.open end
  local order_word = banking and "richest place first" or "zone by zone from the lowest"
  v.intro:SetText(hubName and string.format("Level %d to %d, %s. Minutes from %s.", level - below, level + above, order_word, hubName)
    or string.format("Level %d to %d, %s.", level - below, level + above, order_word))
  v.introR:SetText(string.format("%d available" .. (picksAll > 0 and " · %d to pick up" or ""), openAll, picksAll))

  local y = 24
  local function place(card, h)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", v.scroll.child, "TOPLEFT", 0, -y)
    card:SetSize(width, h)
    y = y + h + 8
  end
  local function header(c, art, icon, title, where, gain, count)
    c.rows:Reset()
    if type(art) == "table" then c.art:SetColorTexture(art[1], art[2], art[3], 1); c.art:SetTexCoord(0, 1, 0, 1)
    else c.art:SetTexture(art); c.art:SetTexCoord(0, 1, 0.18, 0.5) end
    c.icon:SetTexture(icon)
    c.title:SetText(title)
    c.where:SetText(where)
    c.gain:SetText(gain)
    c.gain:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    c.count:SetText(count or "")
    c.pin:Hide()
    c.more:Hide()
    c.skip:Hide()
    c.skip.key = nil
    c:SetAlpha(1)
  end
  -- the card's count line, as much of it as fits: available, to pick up, in your log (ready), not yet, done
  local function countLine(c, g)
    local parts = {}
    if g.open > 0 then parts[#parts + 1] = g.open .. " available" end
    if g.picks > 0 then parts[#parts + 1] = g.picks .. " to pick up" end
    if g.held > 0 then
      parts[#parts + 1] = g.held .. " in your log" .. (g.ready > 0 and string.format(" (%d %s)", g.ready, banking and "banked" or "ready") or "")
    end
    if g.notyet > 0 then parts[#parts + 1] = g.notyet .. " not yet" end
    if g.done > 0 then parts[#parts + 1] = g.done .. " done" end
    if #parts == 0 then return g.behind > 0 and "probably behind you" or "" end
    local room = c.count:GetWidth() - 2
    for n = #parts, 1, -1 do
      local line = table.concat(parts, " · ", 1, n)
      c.count:SetText(line)
      if c.count:GetStringWidth() <= room or n == 1 then return line end
    end
    return parts[1]
  end

  local shownCards = 0
  -- every place you hold or chose quests in gets a card, wherever it sorts; places with nothing of yours stop
  -- after the 14 richest
  local fetchOnly = 0
  for _, g in ipairs(order) do
    local mine = g.held + g.picks > 0
    if not mine then fetchOnly = fetchOnly + 1 end
    if mine or fetchOnly <= 14 then
      local c = v.cards:Get()
      shownCards = shownCards + 1
      local a = g.cat
      local worth = math.floor((g.left + g.fetch) / 10 + 0.5) * 10
      local minsText = ""
      if g.nearest then
        minsText = g.nearest < 1 and " · you're here" or string.format(a.dungeon and " · %d min to the entrance" or " · %d min away", math.floor(g.nearest + 0.5))
      end
      local where
      if a.dungeon then where = (a.where ~= "" and a.where or "Dungeon") .. minsText .. ". Bring a group."
      else where = (a.where ~= "" and a.where or "") .. minsText end
      header(c, a.bg or { 0.16, 0.12, 0.08 }, a.icon, a.name, where,
        worth > 0 and ("+" .. QB.Comma(worth)) or (g.held > 0 and (banking and "All banked" or "All ready") or ""), "")
      c.count:SetText(countLine(c, g))
      if g.held > 0 and g.left == 0 and g.fetch == 0 and g.picks == 0 then c.gain:SetTextColor(0.4, 0.9, 0.4) end
      if a.key ~= "class" and a.key ~= "misc" then
        -- skipped here (the button flips it) or with its whole continent (Settings does)
        local set = QB:Settings()
        local viaCat = set.skipCat[a.key] == true
        local viaCont = a.cont ~= nil and set.skipCont[a.cont] == true
        c.skip.key = a.key
        c.skip.label:SetText(viaCat and "Back" or "Skip")
        c.skip:SetShown(viaCat or not viaCont)
        if viaCat or viaCont then c.gain:SetText("Skipped"); c.gain:SetTextColor(0.75, 0.75, 0.75); c:SetAlpha(0.8) end
        if viaCont and not viaCat then c.where:SetText((a.dungeon and a.where ~= "" and (a.where .. ". ") or "") .. QB.CONTINENTS[a.cont] .. " is skipped in Settings.") end
      end
      c.pin:SetShown(a.entrance and true or false)
      c.pin.entrance, c.pin.label = a.entrance, a.name .. " entrance"
      table.sort(g.quests, function(x, z)
        if x.grp ~= z.grp then return x.grp < z.grp end
        if x.grp == 3 and (x.st.code == "banked") ~= (z.st.code == "banked") then return x.st.code == "banked" end
        return x.value > z.value
      end)
      UI.Together(g.quests)
      c.band = g.band
      local ry = 50
      local extra, hidden = 0, 0
      local open = UI.expanded and UI.expanded[a.key]
      for _, it in ipairs(g.quests) do
        local show = false
        if it.grp == 6 then show = false
        elseif it.grp == 1 or it.grp == 3 then show = true
        else
          show = open or extra < PER_CARD
          if show then extra = extra + 1 else hidden = hidden + 1 end
        end
        if show then
          local r = c.rows:Get()
          r:ClearAllPoints()
          r:SetPoint("TOPLEFT", 4, -ry)
          fillRow(r, it, width - 8)
          ry = ry + 22
          -- the chain, opened: its steps under the row
          if UI.chainOpen and UI.chainOpen[it.q.id] then
            for _, sit in ipairs(UI.ChainLine(it.q, here, mf)) do
              local r2 = c.rows:Get()
              r2:ClearAllPoints()
              r2:SetPoint("TOPLEFT", 4, -ry)
              fillRow(r2, sit, width - 8)
              ry = ry + 22
            end
          end
        end
      end
      if hidden > 0 or open then
        c.more:ClearAllPoints()
        c.more:SetPoint("TOPLEFT", 46, -ry - 2)
        c.more.key = a.key
        c.more.label:SetText(open and "Show fewer" or string.format("Show %d more here", hidden))
        c.more:Show()
        ry = ry + 20
      end
      c.rows:HideRest()
      place(c, ry + 8)
    end
  end

  -- the sleeping bag chain, last, while you don't have the bag
  if QB.API.ItemCount(211527) == 0 then
    local c = v.cards:Get()
    shownCards = shownCards + 1
    local steps, doneSteps = #D.SLEEP_CHAIN, 0
    local nextStep, heldStep
    for _, step in ipairs(D.SLEEP_CHAIN) do
      local done = QB.API.IsDone(step.id) or QB.Quest.Behind(step.id) ~= nil
      if done then doneSteps = doneSteps + 1 end
      if not nextStep then
        if s.log[step.id] then nextStep, heldStep = step, true
        elseif not done then nextStep = step end
      end
    end
    header(c, { 0.10, 0.12, 0.22 }, T.sleep, "Cozy Sleeping Bag", "Finish Stepping Stones: a bag that builds rested XP faster.", "Bag",
      string.format("%d of %d steps done", doneSteps, steps))
    local hq = heldStep and QB.Quest.Get(nextStep.id)
    if hq and hq.turn and hq.turn.m and hq.turn.m > 0 and not hq.turn.inside then
      c.pin:SetShown(true)
      c.pin.entrance = { m = hq.turn.m, x = hq.turn.x, y = hq.turn.y }; c.pin.label = hq.turn.n
    else
      c.pin:SetShown(nextStep and nextStep.m and true or false)
      if nextStep then c.pin.entrance = nextStep.m and { m = nextStep.m, x = nextStep.x, y = nextStep.y } or nil; c.pin.label = nextStep.where end
    end
    local ry = 50
    for _, step in ipairs(D.SLEEP_CHAIN) do
      local r = c.rows:Get()
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 4, -ry)
      r:SetWidth(width - 8)
      r.q, r.st, r.entry = nil, nil, nil
      r.step = step
      local done = QB.API.IsDone(step.id) or QB.Quest.Behind(step.id) ~= nil
      r.mark:SetTexture(done and T.ready or (s.log[step.id] and T.waiting or T.questAvail))
      r.mark:Show()
      r.pick.pickable = nil
      r.pick:EnableMouse(false)
      r.chain:Hide()
      r.together = nil
      setIcon(r.icon, T.map)
      r.icon:SetDesaturated(done)
      r.name:SetText(step.name)
      r.name:SetTextColor(INK[1], INK[2], INK[3])
      r.up:Hide()
      r.lvl:SetText("")
      r.status:SetWidth(math.max(120, width - 392 - 76)) -- no minutes column on these rows: the whole width for where the step is
      local where = step.where or ""
      r.status:SetText(where)
      if r.status:GetStringWidth() > r.status:GetWidth() - 4 then where = (where:gsub(",[^,]*$", "")) end -- without the zone when it is tight
      r.status:SetText(done and "Done" or (s.log[step.id] and "In your log" or where))
      local sc = done and GOOD or INK_SOFT
      r.status:SetTextColor(sc[1], sc[2], sc[3])
      r.away:SetText("")
      r.xp:SetText("")
      ry = ry + 22
    end
    c.rows:HideRest()
    place(c, ry + 8)
  end
  v.cards:HideRest()

  -- the footer: what you skip
  local skipped = QB:SkipList()
  if #skipped > 0 then
    local names
    if #skipped <= 3 then
      names = #skipped == 1 and skipped[1] or (table.concat(skipped, ", ", 1, #skipped - 1) .. " and " .. skipped[#skipped])
    else
      names = table.concat(skipped, ", ", 1, 3) .. string.format(" and %d more", #skipped - 3)
    end
    v.foot:ClearAllPoints()
    v.foot:SetPoint("TOPLEFT", v.scroll.child, "TOPLEFT", 4, -y)
    v.foot:SetText(string.format("Skipping %s: nothing there is suggested. Settings or /qb skip brings them back.", names))
    v.foot:Show()
    y = y + 20
  else
    v.foot:Hide()
  end
  -- nothing at all
  if shownCards == 0 then
    local set = QB:Settings()
    v.empty:SetText((set.skipCont[0] and set.skipCont[1]) and "You skip Kalimdor and Eastern Kingdoms, so nothing is suggested. Settings brings them back."
      or string.format("Nothing for you between level %d and %d. Settings widens the levels; /qb skip lists the places you skip.", level - below, level + above))
    v.empty:Show()
    y = math.max(y, 90)
  else
    v.empty:Hide()
  end
  v.scroll:SetContentHeight(y)
end

----------------------------------------------------------------------------
-- page 3: hand-in route
----------------------------------------------------------------------------
local KIND = {
  start = "Start here", hearth = "Hearthstone", flight = "Flight", foot = "On foot", tram = "Deeprun Tram", boat = "Boat",
  zeppelin = "Zeppelin", portal = "Portal", done = "Handed in",
}

local function makeLeg(parent)
  local l = CreateFrame("Frame", nil, parent)
  l.line = tex(l, "BACKGROUND")
  l.line:SetColorTexture(0.55, 0.42, 0.2, 0.6)
  l.line:SetWidth(2)
  l.line:SetPoint("TOPLEFT", 51, 0)
  l.line:SetPoint("BOTTOMLEFT", 51, 0)
  l.divider = text(l, "GameFontNormal", 12, BAD, "LEFT", 400)
  l.divider:SetPoint("TOPLEFT", 70, -4)
  l.node = tex(l, "ARTWORK", T.taxiGray, 18, 18)
  l.clock = text(l, "GameFontNormal", 12, INK, "RIGHT", 40)
  l.travelIcon = tex(l, "ARTWORK", nil, 16, 16)
  l.travel = text(l, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", 300)
  l.name = text(l, "GameFontNormalLarge", 15, INK, "LEFT", 330)
  l.level = text(l, "GameFontNormal", 12, INK_SOFT, "RIGHT", 150)
  l.pin = pinButton(l, 20)
  l.pin:SetScript("OnClick", function(self)
    local s = self.stop
    if s and s.m and s.m > 0 then QB.API.SetWaypoint(s.m, s.x, s.y, s.name) end
  end)
  tooltip(l.pin, function(tip, self) tip:AddLine("Waypoint: " .. (self.stop and self.stop.name or ""), GOLD[1], GOLD[2], GOLD[3]) end)
  l.note = text(l, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", 500)
  l.rows = {}
  return l
end

local function legRow(l, i)
  local r = l.rows[i]
  if r then r:Show() return r end
  r = CreateFrame("Button", nil, l)
  r:SetHeight(20)
  r.hi = tex(r, "HIGHLIGHT", T.rowHi)
  r.hi:SetAllPoints()
  r.hi:SetBlendMode("ADD")

  r.hi:SetAlpha(0.6)
  r.icon = tex(r, "ARTWORK", nil, 16, 16)
  r.icon:SetPoint("LEFT", 2, 0)
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.tick = tex(r, "OVERLAY", T.ready, 14, 14)
  r.tick:SetPoint("LEFT", 4, 0)
  r.name = text(r, "GameFontNormal", 12, INK, "LEFT", 290)
  r.name:SetPoint("LEFT", 24, 0)
  r.npc = text(r, "GameFontNormalSmall", 10, INK_SOFT, "LEFT", 170)
  r.npc:SetPoint("LEFT", 320, 0)
  r.xp = text(r, "GameFontNormal", 12, INK, "RIGHT", 110)
  r.xp:SetPoint("RIGHT", -6, 0)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self, which) if self.q then UI.QuestClick(self.q, self.st, which) end end)
  tooltip(r, function(tip, self)
    if self.q then UI.QuestTooltip(tip, self.q, self.st, self.xpv, self.pct, self.plvl) end
    if self.doneXP then tip:AddLine(string.format("Handed in: +%s XP", QB.Comma(self.doneXP)), 0.4, 1, 0.4) end
  end)
  l.rows[i] = r
  return r
end

function UI:CreateRouteView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()
  v.modeNow = button(v, "Banked now", 110)
  v.modeNow:SetPoint("TOPLEFT", 14, -10)
  v.modePlan = button(v, "Log and pick-ups", 130)
  v.modePlan:SetPoint("TOPLEFT", 128, -10)
  v.modeNow:SetScript("OnClick", function() QB:Settings().routeMode = "now"; UI:Refresh() end)
  v.modePlan:SetScript("OnClick", function() QB:Settings().routeMode = "plan"; UI:Refresh() end)
  v.run = button(v, "Start run", 96)
  v.run:SetPoint("TOPRIGHT", -14, -10)
  v.run:SetScript("OnClick", QB.Safe(function()
    if QB.Run.Get() then QB.Run.Stop() else QB:Recompute(true); QB.Run.Start() end
    UI:Refresh()
  end, "run button"))
  tooltip(v.run, function(tip)
    if QB.Run.Get() then
      tip:AddLine("End the run", GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine("Saves it with its times and XP.", 1, 1, 1)
    else
      tip:AddLine("Start the hand-in run", GOLD[1], GOLD[2], GOLD[3])
      tip:AddLine("Starts a clock, ticks each quest off with the XP it paid, and re-plans the rest from where you stand.", 1, 1, 1, true)
      if QB:Banking() then tip:AddLine("When the level cap goes up, your first hand-in starts it by itself.", 1, 1, 1, true) end
    end
  end)
  v.post = button(v, "Post", 64)
  v.post:SetPoint("TOPRIGHT", -114, -10)
  v.post:SetScript("OnClick", function() UI:PostDialog(QB.Run.PostText("status")) end)
  tooltip(v.post, function(tip)
    tip:AddLine("Post in party or guild chat", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine(QB.Run.Get() and "How your hand-in run is going: minutes, level, quests and XP."
      or (QB:Banking() and "The level your banked quests take you to, and your plan's." or "The level the quests ready in your log take you to, and your plan's."), 1, 1, 1, true)
    tip:AddLine("You see the message first. Nothing is posted until you press Post.", 0.6, 0.6, 0.6, true)
  end)
  v.summary = text(v, "GameFontNormal", 12, INK, "RIGHT", 336)
  v.summary:SetPoint("TOPRIGHT", -184, -14)
  v.setup = para(v, "GameFontNormal", 12, INK, W - 64)
  v.setup:SetPoint("TOPLEFT", 16, -40)
  v.setup:SetHeight(30)
  local holder = CreateFrame("Frame", nil, v)
  holder:SetPoint("TOPLEFT", 0, -70)
  holder:SetPoint("BOTTOMRIGHT", 0, 0)
  v.scroll = scrollArea(holder)
  v.legs = pool(v.scroll.child, makeLeg)
  v.empty = para(v.scroll.child, "GameFontNormal", 13, INK_SOFT, 560)
  v.empty:SetPoint("TOPLEFT", 60, -20)
  v.Refresh = function() UI:RefreshRouteView(v) end
  return v
end

local function travelIcon(kind)
  if kind == "hearth" then return T.hearth elseif kind == "flight" then return QB.faction == "H" and T.wyvern or T.gryphon
  elseif kind == "boat" then return T.boat elseif kind == "tram" then return T.tram elseif kind == "zeppelin" then return T.zeppelin
  elseif kind == "portal" then return T.portal elseif kind == "start" then return T.book elseif kind == "done" then return T.ready end
  return QB:Mounted() and T.mount or T.foot
end

-- one leg: the clock, how you get there, the stop, and the quests handed in there
local function layLeg(l, width, y, parent)
  l:ClearAllPoints()
  l:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
  l:SetWidth(width)
  local top = l.divider:IsShown() and 22 or 0
  l.node:ClearAllPoints(); l.node:SetPoint("TOPLEFT", 43, -8 - top)
  l.clock:ClearAllPoints(); l.clock:SetPoint("TOPLEFT", 0, -10 - top)
  l.travelIcon:ClearAllPoints(); l.travelIcon:SetPoint("TOPLEFT", 70, -6 - top)
  l.travel:ClearAllPoints(); l.travel:SetPoint("TOPLEFT", 92, -7 - top)
  l.name:ClearAllPoints(); l.name:SetPoint("TOPLEFT", 70, -24 - top)
  l.level:ClearAllPoints(); l.level:SetPoint("TOPRIGHT", -34, -27 - top)
  l.pin:ClearAllPoints(); l.pin:SetPoint("TOPRIGHT", -8, -25 - top)
  l.note:ClearAllPoints(); l.note:SetPoint("TOPLEFT", 70, -44 - top)
  l.note:SetWidth(width - 110)
  return top
end

function UI:RefreshRouteView(v)
  local set = QB:Settings()
  local run = QB.Run.Get()
  local mode = run and "now" or (set.routeMode == "plan" and "plan" or "now")
  local r = mode == "plan" and QB.routePlan or QB.routeNow
  v.modeNow:SetEnabled(mode ~= "now")
  v.modePlan:SetEnabled(mode ~= "plan" and not run)
  local banking = QB:Banking()
  v.modeNow:SetText(banking and "Banked now" or "Ready now")
  v.run:SetText(run and "End run" or "Start run")
  local width = v.scroll:Width() - 6
  local busy = QB.Model.Busy() and "  |cff8a6a3aplanning...|r" or ""
  if banking then
    v.summary:SetText(string.format("%s XP  |  level %.2f  |  %d min  |  at 60 min %.2f%s",
      QB.Comma(r.xp or 0), r.level or 0, math.floor((r.t or 0) + 0.5), r.at60 or 0, busy))
  else
    v.summary:SetText(string.format("%s XP  |  level %.2f  |  %d min%s", QB.Comma(r.xp or 0), r.level or 0, math.floor((r.t or 0) + 0.5), busy))
  end
  v.legs:Reset()

  -- the setup line: where to log out and where to bind, or how the run is going
  local line
  if run then
    local got, n = QB.Run.Totals()
    local pace = QB.Run.Pace()
    line = string.format("Run %s.  %d handed in, |cff0a6a0a+%s XP|r.", QB.Clock(QB.Run.Elapsed()), n, QB.Comma(got))
    if pace then
      if math.abs(pace) < 1 then line = line .. "  On pace."
      elseif pace > 0 then line = line .. string.format("  %.0f min ahead of the plan.", pace)
      else line = line .. string.format("  |cffa0400a%.0f min behind the plan.|r", -pace) end
    end
    if r.legs[1] then line = line .. "  Next: |cff7a2e0a" .. r.legs[1].stop.name .. "|r." end
  elseif not banking then
    line = r.legs and r.legs[1] and ("From where you stand. First stop: |cff7a2e0a" .. r.legs[1].stop.name .. "|r.")
      or (mode == "now" and "Nothing in your log is ready to hand in yet." or "Nothing on your pick-up list yet. The ! on a quest on Available puts it there, and the route takes it in.")
  elseif r.legs and r.legs[1] then
    line = (QB.mode == "rush" and "Start at |cff7a2e0a" or "Log out at |cff7a2e0a") .. r.legs[1].stop.name .. "|r."
    if r.bind then
      local bind = QB.API.BindName()
      line = line .. " Bind your hearthstone in |cff7a2e0a" .. r.bind.town .. "|r"
      if bind ~= "" and not (bind:find(r.bind.town, 1, true) or r.bind.town:find(bind, 1, true)) then line = line .. " (it is set to " .. bind .. ")" end
      line = line .. "."
    end
    if r.lateFrom and r.goal == "hour" then line = line .. " Stops after the first hour come last." end
  end
  v.setup:SetText(line or "")

  local y = 0
  local mapID = QB.state.mapID
  -- handed in during the run
  if run then
    local done = {}
    for id, d in pairs(run.done) do done[#done + 1] = { id = id, d = d } end
    table.sort(done, function(a, b) return (a.d.n or 0) < (b.d.n or 0) end)
    if #done > 0 then
      local l = v.legs:Get()
      l.divider:Hide()
      layLeg(l, width, y, v.scroll.child)
      l.node:SetTexture(T.taxiG)
      l.clock:SetText(QB.Clock(done[#done].d.t))
      l.travelIcon:SetTexture(T.ready)
      l.travel:SetText("Handed in so far")
      l.name:SetText(#done == 1 and "1 quest" or string.format("%d quests", #done))
      l.level:SetText("")
      l.pin:Hide()
      l.note:SetText("")
      local ry = 48
      for k, it in ipairs(done) do
        local rr = legRow(l, k)
        rr:ClearAllPoints()
        rr:SetPoint("TOPLEFT", 66, -ry)
        rr:SetWidth(width - 74)
        local q = Q.Get(it.id)
        rr.q, rr.st, rr.xpv, rr.pct, rr.plvl, rr.doneXP = q, q and { code = "done", text = "Handed in" }, nil, nil, nil, it.d.xp
        rr.icon:Hide()
        rr.tick:Show()
        rr.name:SetText(q and q.name or it.d.name or ("Quest " .. it.id))
        rr.name:SetTextColor(GOOD[1], GOOD[2], GOOD[3])
        rr.npc:SetText(QB.Clock(it.d.t))
        rr.xp:SetText("+" .. QB.Comma(it.d.xp or 0))
        ry = ry + 20
      end
      for k = #done + 1, #l.rows do l.rows[k]:Hide() end
      l:SetHeight(ry + 8)
      y = y + ry + 8
    end
  end

  if not r.legs or #r.legs == 0 then
    v.empty:SetText(run and "Everything that was ready is handed in. End the run to save it." or
      (mode == "now" and ((QB:Banking() and "Nothing is banked yet." or "Nothing is ready to hand in yet.") .. " Finished quests and quest items in your bags show up here in hand-in order. Full plan shows the route you're building towards.") or
        "Nothing in your log or on your pick-up list yet. The ! on a quest on Available puts it there."))
    v.empty:ClearAllPoints()
    v.empty:SetPoint("TOPLEFT", 60, -y - 20)
    v.empty:Show()
  else
    v.empty:Hide()
  end

  for i, leg in ipairs(r.legs or {}) do
    local l = v.legs:Get()
    local s = leg.stop
    local lateStart = leg.late and not (r.legs[i - 1] and r.legs[i - 1].late) and r.goal == "hour" and not run
    l.divider:SetShown(lateStart)
    l.divider:SetText("After the first hour")
    layLeg(l, width, y, v.scroll.child)
    l.node:SetTexture(i == 1 and T.taxiY or T.taxiGray)
    l.clock:SetText(QB.Clock(leg.t))
    local kind = leg.kind
    l.travelIcon:SetTexture(travelIcon(kind))
    local label = KIND[kind] or kind
    if kind == "start" then
      label = QB.mode == "lock" and "Log in here" or "Start here"
    else
      label = label .. string.format(", about %d min", math.max(1, math.floor(leg.travel + 0.5)))
      if kind == "hearth" and leg.inn then label = label .. " to " .. QB.Data.HUB[r.fac][leg.inn][1] end
    end
    l.travel:SetText(label)
    local here = mapID and mapID == s.m and "  |cff0a6a0ayou are here|r" or ""
    l.name:SetText(s.name .. here)
    l.level:SetText(string.format("level %.1f > %.1f", leg.arrive, leg.leave))
    l.pin.stop = s
    l.pin:SetShown(s.m and s.m > 0)
    l.note:SetText("")
    local top = l.divider:IsShown() and 22 or 0
    local ry = 46 + top
    for k, row in ipairs(leg.rows) do
      local rr = legRow(l, k)
      rr:ClearAllPoints()
      rr:SetPoint("TOPLEFT", 66, -ry)
      rr:SetWidth(width - 74)
      rr.q, rr.st, rr.xpv, rr.pct, rr.plvl, rr.doneXP = row.q, row.e.st, row.xp, row.pct, row.plvl, nil
      rr.icon:Show()
      rr.tick:Hide()
      setIcon(rr.icon, row.q.icon)
      rr.name:SetText(row.q.name)
      local c = row.blocked and INK_SOFT or INK
      rr.name:SetTextColor(c[1], c[2], c[3])
      rr.npc:SetText(row.q.turn and row.q.turn.n or "")
      local xpText = QB.Comma(row.xp)
      if row.blocked then xpText = "|cffa0400aafter its first step|r"
      elseif row.pct < 100 then xpText = string.format("|cffa0400a%d%%|r  %s", row.pct, xpText) end
      rr.xp:SetText(xpText)
      ry = ry + 20
    end
    for k = #leg.rows + 1, #l.rows do l.rows[k]:Hide() end
    l:SetAlpha(leg.late and r.goal == "hour" and not run and 0.75 or 1)
    l:SetHeight(ry + 10)
    y = y + ry + 10
  end

  -- what the route could not place
  if r.unplaced and #r.unplaced > 0 then
    local l = v.legs:Get()
    l.divider:Hide()
    layLeg(l, width, y, v.scroll.child)
    l.node:SetTexture(T.taxiGray)
    l.clock:SetText("")
    l.travelIcon:SetTexture(T.unknown)
    l.travel:SetText("Not on the route")
    l.name:SetText(#r.unplaced .. (#r.unplaced == 1 and " quest" or " quests"))
    l.level:SetText("")
    l.pin:Hide()
    l.note:SetText("Handed in inside a dungeon, or where QuestBank has no position for the NPC. Hand them in on the way.")
    local ry = 64
    for k, e in ipairs(r.unplaced) do
      local rr = legRow(l, k)
      rr:ClearAllPoints()
      rr:SetPoint("TOPLEFT", 66, -ry)
      rr:SetWidth(width - 74)
      rr.q, rr.st, rr.xpv, rr.pct, rr.plvl, rr.doneXP = e.q, e.st, QB:Value(e.q.id), nil, nil, nil
      rr.icon:Show()
      rr.tick:Hide()
      setIcon(rr.icon, e.q.icon)
      rr.name:SetText(e.q.name)
      rr.name:SetTextColor(INK[1], INK[2], INK[3])
      rr.npc:SetText(e.q.turn and (e.q.turn.inside and (e.q.turn.n .. ", inside") or e.q.turn.n) or "NPC unknown")
      rr.xp:SetText(QB.Comma(rr.xpv or 0))
      ry = ry + 20
    end
    for k = #r.unplaced + 1, #l.rows do l.rows[k]:Hide() end
    l:SetAlpha(1)
    l:SetHeight(ry + 10)
    y = y + ry + 10
  end
  v.legs:HideRest()
  v.scroll:SetContentHeight(y + 10)
end

----------------------------------------------------------------------------
-- page 4: party
----------------------------------------------------------------------------
local function makeMember(parent)
  local m = CreateFrame("Button", nil, parent)
  m:SetHeight(40)
  m.hi = tex(m, "HIGHLIGHT", T.rowHi)
  m.hi:SetAllPoints()
  m.hi:SetBlendMode("ADD")

  m.hi:SetAlpha(0.6)
  m.class = tex(m, "ARTWORK", T.classes, 30, 30)
  m.class:SetPoint("LEFT", 6, 0)
  m.dot = tex(m, "OVERLAY", T.dotGreen, 12, 12)
  m.dot:SetPoint("BOTTOMRIGHT", m.class, "BOTTOMRIGHT", 3, -3)
  m.name = text(m, "GameFontNormal", 13, INK, "LEFT", 150)
  m.name:SetPoint("TOPLEFT", 44, -5)
  m.sub = text(m, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", 150)
  m.sub:SetPoint("TOPLEFT", 44, -22)
  m.bank = text(m, "GameFontNormal", 12, INK, "LEFT", 150)
  m.bank:SetPoint("TOPLEFT", 196, -5)
  m.run = text(m, "GameFontNormalSmall", 11, INK_SOFT, "LEFT", 150)
  m.run:SetPoint("TOPLEFT", 196, -22)
  m.copy = iconButton(m, 24, T.letter)
  m.copy:SetPoint("RIGHT", -10, 0)
  m.copy:SetScript("OnClick", function(self)
    local n = QB.Sync and QB.Sync:CopyPlan(self:GetParent().who) or 0
    QB:Print(n > 0 and string.format("Added %d of their quests to your plan.", n) or "Nothing of theirs fits your plan.")
    UI:Refresh()
  end)
  tooltip(m.copy, function(tip)
    tip:AddLine("Copy their plan", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine(QB:Banking() and "Adds the quests they are banking that you can do too." or "Adds the quests they hold or plan to fetch that you can do too.", 1, 1, 1, true)
  end)
  tooltip(m, function(tip, self) if QB.Sync then QB.Sync:MemberTooltip(tip, self.who) end end)
  return m
end

-- a party member's quest, in the mode you are in: banking speaks of banked quests, questing of ready ones
local function stateWord(code)
  if code == "b" then return QB:Banking() and "banked" or "ready to hand in" end
  if code == "p" then return "to pick up" end
  if code == "a" then return "in log" end
  return ""
end

local function whoText(e)
  local parts = {}
  for _, w in ipairs(e.who) do
    local state = w.code == "a" and (w.prog or "in log") or stateWord(w.code)
    local name = QB.Sync and QB.Sync.ColorName(w.name, w.class, true) or w.name -- the dark cut: this sits on parchment
    if w.me then state = "|cff0a4a8a" .. state .. "|r" elseif w.code == "b" then state = "|cff6f6a61" .. state .. "|r" end
    parts[#parts + 1] = name .. " " .. state
  end
  return table.concat(parts, ",  ")
end

-- "A, B and C", as many as fit in room bytes, then "and 2 more"
local function nameList(names, room)
  for n = #names, 1, -1 do
    local shown = {}
    for i = 1, n do shown[i] = names[i] end
    local s
    if n == #names then
      s = #shown > 1 and (table.concat(shown, ", ", 1, n - 1) .. " and " .. shown[n]) or shown[1]
    else
      s = table.concat(shown, ", ") .. string.format(" and %d more", #names - n)
    end
    if #s <= room then return s end
  end
  return string.format("%d quests", #names)
end

-- a post asking for a group: the quests you still need in there, or the group's if you have none left
function UI.DungeonPost(d)
  local mine, theirs = {}, {}
  for _, e in ipairs(d.quests) do
    if e.need > 0 and e.q then
      local me = false
      for _, w in ipairs(e.who) do if w.me and w.code ~= "b" then me = true end end
      if me then mine[#mine + 1] = e.q.name else theirs[#theirs + 1] = e.q.name end
    end
  end
  local head = "Anyone up for " .. d.cat.name:gsub("^The ", "") .. "? "
  if #mine > 0 then
    local lead = "I still need "
    return head .. lead .. nameList(mine, 254 - #head - #lead) .. ".", d.cat.name .. ": the quests you still need in there."
  end
  local lead = "Quests still to do: "
  return head .. lead .. nameList(theirs, 254 - #head - #lead) .. ".", d.cat.name .. ": the quests your group still needs in there."
end

local function makeDungeonRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(32)
  r.hi = tex(r, "HIGHLIGHT", T.rowHi)
  r.hi:SetAllPoints()
  r.hi:SetBlendMode("ADD")

  r.hi:SetAlpha(0.6)
  r.icon = tex(r, "ARTWORK", nil, 18, 18)
  r.icon:SetPoint("TOPLEFT", 4, -3)
  r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.name = text(r, "GameFontNormal", 12, INK, "LEFT", 240)
  r.name:SetPoint("TOPLEFT", 28, -4)
  r.who = text(r, "GameFontNormalSmall", 10, INK_SOFT, "LEFT", 256)
  r.who:SetPoint("TOPLEFT", 28, -18)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self, which) if self.q then UI.QuestClick(self.q, QB:Status(self.q), which) end end)
  tooltip(r, function(tip, self)
    if not self.q then return end
    UI.QuestTooltip(tip, self.q, QB:Status(self.q))
    tip:AddLine(" ")
    for _, w in ipairs(self.e.who) do
      local state = w.code == "a" and ("in their log" .. (w.prog and (", " .. w.prog) or "")) or stateWord(w.code)
      if w.me then state = w.code == "a" and ("in your log" .. (w.prog and (", " .. w.prog) or "")) or (w.code == "p" and "yours to pick up" or state) end
      tip:AddDoubleLine(w.name, state, 1, 1, 1, w.code == "b" and 0.6 or 0.4, w.code == "b" and 0.6 or 1, w.code == "b" and 0.6 or 0.4)
    end
  end)
  return r
end

local function makeDungeonCard(parent)
  local c = CreateFrame("Frame", nil, parent, BD)
  backdrop(c, nil, T.tipBorder, 12, 3)
  if c.SetBackdropBorderColor then c:SetBackdropBorderColor(0.45, 0.33, 0.16, 0.9) end
  c.head = CreateFrame("Button", nil, c)
  c.head:SetPoint("TOPLEFT", 3, -3)
  c.head:SetPoint("TOPRIGHT", -3, -3)
  c.head:SetHeight(36)
  c.art = tex(c.head, "BACKGROUND")
  c.art:SetAllPoints()
  c.shade = tex(c.head, "BORDER")
  c.shade:SetColorTexture(0.06, 0.04, 0.02, 0.6)
  c.shade:SetAllPoints()
  c.icon = tex(c.head, "ARTWORK", nil, 26, 26)
  c.icon:SetPoint("LEFT", 6, 0)
  c.title = text(c.head, "GameFontNormal", 13, GOLD, "LEFT", 170)
  c.title:SetPoint("TOPLEFT", 38, -4)
  c.people = text(c.head, "GameFontHighlightSmall", 10, WHITE, "LEFT", 170)
  c.people:SetPoint("TOPLEFT", 38, -20)
  c.gain = text(c.head, "GameFontNormal", 12, GOLD, "RIGHT", 70)
  c.gain:SetPoint("TOPRIGHT", -8, -4)
  c.left = text(c.head, "GameFontHighlightSmall", 10, WHITE, "RIGHT", 90)
  c.left:SetPoint("TOPRIGHT", -8, -20)
  c.head:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  c.head:SetScript("OnClick", function(self, which)
    if which == "RightButton" then
      if self.data then UI:PostDialog(UI.DungeonPost(self.data)) end
      return
    end
    local e = self.cat and self.cat.entrance
    if e then QB.API.SetWaypoint(e.m, e.x, e.y, self.cat.name .. " entrance") end
  end)
  tooltip(c.head, function(tip, self)
    if not self.cat then return end
    tip:AddLine(self.cat.name, GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine(string.format("%d quests still to do among %s, worth about %s XP together.", self.data.left, table.concat(self.data.people, ", "), QB.Comma(self.data.xp)), 1, 1, 1, true)
    tip:AddLine((self.cat.entrance and "Click: waypoint on the entrance.  " or "") .. "Right-click: ask your party or guild to come along.", 0.5, 0.5, 0.5, true)
  end)
  c.rows = pool(c, makeDungeonRow)
  return c
end

function UI:CreatePartyView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()
  v.title = text(v, "GameFontNormalLarge", 15, INK, "LEFT", 380)
  v.title:SetPoint("TOPLEFT", LEFT, -12)
  v.hint = para(v, "GameFontNormalSmall", 11, INK_SOFT, 380)
  v.hint:SetPoint("TOPLEFT", LEFT, -32)
  v.hint:SetHeight(30)
  v.members = pool(v, makeMember)
  v.empty = para(v, "GameFontNormal", 12, INK_SOFT, 380)
  v.empty:SetPoint("TOPLEFT", LEFT, -72)
  v.sharePartyBtn = button(v, "Party: on", 96)
  v.sharePartyBtn:SetPoint("BOTTOMLEFT", LEFT, 12)
  v.sharePartyBtn:SetScript("OnClick", function() local s = QB:Settings().share; s.party = not s.party; UI:Refresh() end)
  v.shareGuildBtn = button(v, "Guild: on", 96)
  v.shareGuildBtn:SetPoint("BOTTOMLEFT", LEFT + 102, 12)
  v.shareGuildBtn:SetScript("OnClick", function() local s = QB:Settings().share; s.guild = not s.guild; UI:Refresh() end)
  v.syncBtn = button(v, "Send now", 96)
  v.syncBtn:SetPoint("BOTTOMLEFT", LEFT + 204, 12)
  v.syncBtn:SetScript("OnClick", QB.Safe(function() if QB.Sync then QB.Sync:Broadcast(true) end end, "send now"))
  tooltip(v.syncBtn, function(tip)
    tip:AddLine("Share your quests now", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine((QB:Banking() and "Sends your level, banked XP and plan" or "Sends your level, what you have ready and what you plan to fetch") .. " to QuestBank users in your party and guild. /qb sync Name whispers one friend.", 1, 1, 1, true)
  end)

  v.runTitle = text(v, "GameFontNormalLarge", 15, INK, "LEFT", 330)
  v.runTitle:SetPoint("TOPLEFT", RIGHT, -12)
  v.runTitle:SetText("Dungeons")
  v.runHint = para(v, "GameFontNormalSmall", 11, INK_SOFT, 330)
  v.runHint:SetPoint("TOPLEFT", RIGHT, -32)
  v.runHint:SetHeight(28)
  v.runHint:SetText("The quests each of you still has to do there, and how far along you are.")
  local holder = CreateFrame("Frame", nil, v)
  holder:SetPoint("TOPLEFT", RIGHT - 10, -58)
  holder:SetPoint("BOTTOMRIGHT", 0, 0)
  v.dscroll = scrollArea(holder)
  v.dcards = pool(v.dscroll.child, makeDungeonCard)
  v.noRuns = para(v.dscroll.child, "GameFontNormal", 12, INK_SOFT, 300)
  v.noRuns:SetPoint("TOPLEFT", 8, -8)
  v.Refresh = function() UI:RefreshPartyView(v) end
  return v
end

function UI:RefreshPartyView(v)
  local S = QB.Sync
  local share = QB:Settings().share
  v.sharePartyBtn:SetText(share.party and "Party: on" or "Party: off")
  v.shareGuildBtn:SetText(share.guild and "Guild: on" or "Guild: off")
  local members = S and S:Members() or {}
  v.title:SetText(#members > 0 and string.format("QuestBank users  %d", #members) or "QuestBank users")
  v.hint:SetText(QB:Banking() and "Everyone here shares their level, banked XP and plan. Hover a name for their bank."
    or "Everyone here shares their level, what they have ready to hand in and what they plan to fetch. Hover a name for their quests.")
  v.members:Reset()
  for i, m in ipairs(members) do
    if i > 8 then break end
    local row = v.members:Get()
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", LEFT - 4, -66 - (i - 1) * 42)
    row:SetWidth(390)
    row.who = m.key
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[m.class or ""]
    if coords then row.class:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) else row.class:SetTexCoord(0, 0.25, 0, 0.25) end
    local cc = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS) and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[m.class or ""]
    row.name:SetText(m.name or m.key)
    if cc then row.name:SetTextColor(cc.r * 0.7, cc.g * 0.7, cc.b * 0.7) else row.name:SetTextColor(INK[1], INK[2], INK[3]) end
    row.sub:SetText(string.format("Level %s %s", m.level or "?", m.fac == "H" and "Horde" or "Alliance"))
    row.bank:SetText(string.format(QB:Banking() and "Banked %.1f, plan %.1f" or "Ready %.1f, plan %.1f", m.banked or 0, m.plan or 0))
    if m.runStart then
      row.run:SetText(string.format("Running %s, %d in, +%s", QB.Clock(m.runMin or 0), m.runN or 0, QB.Short(m.runXP or 0)))
      row.run:SetTextColor(GOOD[1], GOOD[2], GOOD[3])
    else
      row.run:SetText(m.age and m.age > 90 and string.format("Seen %d min ago", math.floor(m.age / 60)) or "Online")
      row.run:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
    end
    row.dot:SetTexture(m.age and m.age > 600 and T.dotGray or (m.runStart and T.dotYellow or T.dotGreen))
    row.copy:SetShown(m.fac == QB.faction and m.quests ~= nil)
  end
  v.members:HideRest()
  v.empty:SetShown(#members == 0)
  v.empty:SetText("Nobody with QuestBank in your party or guild yet. When friends install it and group up, their quests show here and you can plan dungeon runs together. To share with one friend outside your group: /qb sync Name")

  local dungeons = S and S:Dungeons() or {}
  local width = v.dscroll:Width() - 4
  if width > 330 then width = 316 end
  v.dcards:Reset()
  local y = 0
  for _, d in ipairs(dungeons) do
    local c = v.dcards:Get()
    c.rows:Reset()
    c.head.cat, c.head.data = d.cat, d
    if d.cat.bg then c.art:SetTexture(d.cat.bg); c.art:SetTexCoord(0, 1, 0.2, 0.45) else c.art:SetColorTexture(0.16, 0.12, 0.08, 1) end
    c.icon:SetTexture(d.cat.icon)
    c.title:SetText(d.cat.name)
    local people = {}
    for i, n in ipairs(d.people) do people[i] = QB.Sync and QB.Sync.ColorName(n, d.classOf and d.classOf[n]) or n end
    c.people:SetText(table.concat(people, ", "))
    c.gain:SetText("+" .. QB.Short(d.xp))
    c.left:SetText(d.left == 1 and "1 still to do" or string.format("%d still to do", d.left))
    local ry = 42
    for _, e in ipairs(d.quests) do
      if e.need > 0 and e.q then
        local r = c.rows:Get()
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 4, -ry)
        r:SetWidth(width - 8)
        r.name:SetWidth(width - 44)
        r.who:SetWidth(width - 36)
        r.q, r.e = e.q, e
        setIcon(r.icon, e.q.icon)
        r.name:SetText(string.format("%s  |cff6b4d28L%d|r", e.q.name, e.q.lvl))
        r.who:SetText(whoText(e))
        ry = ry + 32
      end
    end
    c.rows:HideRest()
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", v.dscroll.child, "TOPLEFT", 0, -y)
    c:SetSize(width, ry + 6)
    y = y + ry + 14
  end
  v.dcards:HideRest()
  v.noRuns:SetShown(#dungeons == 0)
  v.noRuns:SetText("No dungeon quests in your log or on your pick-up list yet. Choose some on Available; your party's show here too.")
  v.dscroll:SetContentHeight(math.max(y, 40))
end

----------------------------------------------------------------------------
-- page 5: settings
----------------------------------------------------------------------------
local function checkRow(parent, x, y, label, width)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(24, 24)
  c:SetPoint("TOPLEFT", x, y)
  c.label = text(parent, "GameFontNormal", 12, INK, "LEFT", width or 320)
  c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
  c.label:SetText(label)
  return c
end

local function heading(parent, x, y, label, width)
  local t = text(parent, "GameFontNormalLarge", 15, INK, "LEFT", width or 330)
  t:SetPoint("TOPLEFT", x, y)
  t:SetText(label)
  return t
end

function UI:CreateSettingsView(parent)
  local v = CreateFrame("Frame", nil, parent)
  v:SetAllPoints()
  -- more than one screen of switches: the page scrolls
  v.scroll = scrollArea(v)
  local p = v.scroll.child
  local LEFT, RIGHT = 12, 390
  -- mode: found for you, or set by you
  heading(p, LEFT, -12, "Mode", 370)
  v.modeBtns = {}
  for i, m in ipairs({ { "auto", "Auto" }, { "off", "Questing" }, { "on", "Banking" } }) do
    local b = button(p, m[2], 110)
    b:SetPoint("TOPLEFT", LEFT + (i - 1) * 116, -38)
    b.val = m[1]
    b:SetScript("OnClick", QB.Safe(function(self)
      QB:SetLock(self.val)
      UI:Refresh()
    end, "settings: mode"))
    v.modeBtns[i] = b
  end
  v.modeText = para(p, "GameFontNormal", 12, INK_SOFT, 370)
  v.modeText:SetPoint("TOPLEFT", LEFT, -68)
  v.modeText:SetHeight(64)
  v.capLabel = text(p, "GameFontNormal", 12, INK, "LEFT", 250)
  v.capLabel:SetPoint("TOPLEFT", LEFT, -144)
  v.capDown = button(p, "-", 26)
  v.capDown:SetPoint("TOPLEFT", LEFT + 262, -140)
  v.capUp = button(p, "+", 26)
  v.capUp:SetPoint("TOPLEFT", LEFT + 292, -140)
  local function moveCap(d)
    local _, p = QB:LockChoice()
    local held, nextCap = QB:Lock()
    local was = QB:Held()
    local base = held or (was and was.level) or QB.state.level
    local cur = nextCap or (was and was.next) or math.min(base + 10, QB.MAXLEVEL)
    local new = math.max(base + 1, math.min(QB.MAXLEVEL, cur + d))
    p.nextCap = new
    if was and not held then was.next = new end -- the rush: the cap it went to
    QB:MarkDirty()
    UI:Refresh()
  end
  v.capDown:SetScript("OnClick", function() moveCap(-1) end)
  v.capUp:SetScript("OnClick", function() moveCap(1) end)

  heading(p, LEFT, -188, "Map", 370)
  v.pins = checkRow(p, LEFT, -212, "Numbered route pins on the world map")
  v.pins:SetScript("OnClick", function(self)
    if QB.Pins then
      if (self:GetChecked() and true or false) ~= (QB:Settings().pins and true or false) then QB.Pins:Toggle() end
    else
      QB:Settings().pins = self:GetChecked() and true or false
    end
    UI:Refresh()
  end)
  v.minimap = checkRow(p, LEFT, -240, "Button on the minimap")
  v.minimap:SetScript("OnClick", function(self)
    QB:Settings().minimap.hide = not self:GetChecked()
    if QB.Minimap then QB.Minimap:Update() end
  end)
  v.arrow = checkRow(p, LEFT, -268, "Direction arrow (right-click it for what it points at)")
  v.arrow:SetScript("OnClick", function(self) if QB.Arrow then QB.Arrow:Set(self:GetChecked() and true or false) end end)

  heading(p, LEFT, -304, "Discoveries", 370)
  -- the spells and item tooltips of the Forever client (Game.lua); quests and NPCs are always noted. Unticking
  -- clears what was noted, ticking takes over ForeverProbe's notes if it is still there
  v.noteGame = checkRow(p, LEFT, -328, "Note items and spells you see, for foreverrank.com", 340)
  v.noteGame:SetScript("OnClick", function(self)
    if QB.Game then QB.Game.SetOn(self:GetChecked() and true or false) end
    UI:Refresh()
  end)
  v.noteGame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Note items and spells you see", 1, 1, 1)
    GameTooltip:AddLine("Tooltips of the items you see and the spells you know, with no names in them, so foreverrank.com can list them. Unticking forgets what was noted.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  v.noteGame:SetScript("OnLeave", function() GameTooltip:Hide() end)
  v.discText = para(p, "GameFontNormal", 12, INK_SOFT, 370)
  v.discText:SetPoint("TOPLEFT", LEFT, -356)
  v.discText:SetHeight(64)

  -- updates: what others on the realm run
  heading(p, RIGHT, -12, "Updates")
  v.verText = para(p, "GameFontNormal", 12, INK_SOFT, 330)
  v.verText:SetPoint("TOPLEFT", RIGHT, -38)
  v.verText:SetHeight(46)
  v.updates = checkRow(p, RIGHT, -86, "Tell me when anyone on the realm runs a newer one", 300)
  v.updates:SetScript("OnClick", function(self)
    QB:Settings().updates = self:GetChecked() and true or false
    if QB.Sync and QB.Sync.ApplyVersionSetting then QB.Sync:ApplyVersionSetting() end
  end)
  v.link = button(p, "Copy the download link", 190)
  v.link:SetPoint("TOPLEFT", RIGHT + 4, -116)
  v.link:SetScript("OnClick", function() UI:CopyLink("QuestBank download page", QB.DOWNLOAD) end)

  heading(p, RIGHT, -154, "Sharing and chat")
  v.shareParty = checkRow(p, RIGHT, -178, "Share my quests with my party", 300)
  v.shareParty:SetScript("OnClick", function(self) QB:Settings().share.party = self:GetChecked() and true or false; UI:Refresh() end)
  v.shareGuild = checkRow(p, RIGHT, -204, "Share them with my guild", 300)
  v.shareGuild:SetScript("OnClick", function(self) QB:Settings().share.guild = self:GetChecked() and true or false; UI:Refresh() end)
  v.offers = checkRow(p, RIGHT, -230, "Offer a post during hand-in runs", 300)
  v.offers:SetScript("OnClick", function(self) QB:Settings().post.auto = self:GetChecked() and true or false end)
  v.shareHint = para(p, "GameFontNormalSmall", 11, INK_SOFT, 330)
  v.shareHint:SetPoint("TOPLEFT", RIGHT, -258)
  v.shareHint:SetHeight(30)
  v.shareHint:SetText("Over the game's addon channel, to QuestBank users only; nothing shows in chat. Posts go out only when you press Post.")

  -- suggestions: how far the Plan page and the swaps look, and where they never look
  heading(p, RIGHT, -298, "Suggestions")
  v.rangeAboveLabel = text(p, "GameFontNormal", 12, INK, "LEFT", 210)
  v.rangeAboveLabel:SetPoint("TOPLEFT", RIGHT, -324)
  v.rangeAboveDown = button(p, "-", 26)
  v.rangeAboveDown:SetPoint("TOPLEFT", RIGHT + 214, -320)
  v.rangeAboveUp = button(p, "+", 26)
  v.rangeAboveUp:SetPoint("TOPLEFT", RIGHT + 244, -320)
  v.rangeAuto = button(p, "Auto", 48)
  v.rangeAuto:SetPoint("TOPLEFT", RIGHT + 276, -320)
  v.rangeBelowLabel = text(p, "GameFontNormal", 12, INK, "LEFT", 210)
  v.rangeBelowLabel:SetPoint("TOPLEFT", RIGHT, -350)
  v.rangeBelowDown = button(p, "-", 26)
  v.rangeBelowDown:SetPoint("TOPLEFT", RIGHT + 214, -346)
  v.rangeBelowUp = button(p, "+", 26)
  v.rangeBelowUp:SetPoint("TOPLEFT", RIGHT + 244, -346)
  local function moveRange(key, d)
    local above, below = QB:Range()
    local cur = key == "rangeAbove" and above or below
    QB:Settings()[key] = math.max(0, math.min(40, cur + d))
    UI:Refresh()
  end
  v.rangeAboveDown:SetScript("OnClick", function() moveRange("rangeAbove", -1) end)
  v.rangeAboveUp:SetScript("OnClick", function() moveRange("rangeAbove", 1) end)
  v.rangeBelowDown:SetScript("OnClick", function() moveRange("rangeBelow", -1) end)
  v.rangeBelowUp:SetScript("OnClick", function() moveRange("rangeBelow", 1) end)
  v.rangeAuto:SetScript("OnClick", function()
    local set = QB:Settings()
    set.rangeAbove, set.rangeBelow = "auto", "auto"
    UI:Refresh()
  end)
  tooltip(v.rangeAuto, function(tip)
    tip:AddLine("Auto", GOLD[1], GOLD[2], GOLD[3])
    tip:AddLine("QuestBank's own window: 12 levels above you while banking (dungeon quests well above you are the big payers), 4 while questing, 7 below.", 0.8, 0.8, 0.8, true)
  end)
  v.skipKal = checkRow(p, RIGHT, -372, "Skip Kalimdor", 110)
  v.skipKal:SetScript("OnClick", function(self) QB:SetSkip(1, self:GetChecked() and true or false) end)
  v.skipEK = checkRow(p, RIGHT + 146, -372, "Skip Eastern Kingdoms", 170)
  v.skipEK:SetScript("OnClick", function(self) QB:SetSkip(0, self:GetChecked() and true or false) end)
  v.skipText = para(p, "GameFontNormalSmall", 11, INK_SOFT, 330)
  v.skipText:SetPoint("TOPLEFT", RIGHT, -400)
  v.skipText:SetHeight(44)

  -- at the quest giver: accept and hand in for you (Auto.lua), off until asked for
  heading(p, LEFT, -432, "At the quest giver", 370)
  v.autoAccept = checkRow(p, LEFT, -456, "Accept quests for me, escorts too", 340)
  v.autoAccept:SetScript("OnClick", function(self) QB:Settings().autoAccept = self:GetChecked() and true or false end)
  v.acceptHint = para(p, "GameFontNormalSmall", 11, INK_SOFT, 370)
  v.acceptHint:SetPoint("TOPLEFT", LEFT, -482)
  v.acceptHint:SetHeight(44)
  v.acceptHint:SetText("At an NPC, from a party member who shares one, and escorts a party member starts. Hold Shift to do it by hand. Not repeatable or grey quests, nor places you skip.")
  v.autoTurnIn = checkRow(p, LEFT, -530, "Hand in finished quests for me", 340)
  v.autoTurnIn:SetScript("OnClick", function(self) QB:Settings().autoTurnIn = self:GetChecked() and true or false end)
  v.turnInHint = para(p, "GameFontNormalSmall", 11, INK_SOFT, 370)
  v.turnInHint:SetPoint("TOPLEFT", LEFT, -556)
  v.turnInHint:SetHeight(58)
  v.turnInHint:SetText("Questing and the rush: everything. While you bank: only quests you left out of the route, ones that pay next to nothing on the day, and a step you hand in to bank a better one. A reward to choose, or a quest QuestBank can't value, waits for you.")

  -- party chat: two plain lines, off until asked for
  heading(p, RIGHT, -460, "Party chat")
  v.sayAccept = checkRow(p, RIGHT, -484, "Say which quests I pick up", 300)
  v.sayAccept:SetScript("OnClick", function(self) QB:Settings().sayAccept = self:GetChecked() and true or false end)
  v.sayComplete = checkRow(p, RIGHT, -510, "Say when a quest is complete", 300)
  v.sayComplete:SetScript("OnClick", function(self) QB:Settings().sayComplete = self:GetChecked() and true or false end)
  v.sayHint = para(p, "GameFontNormalSmall", 11, INK_SOFT, 330)
  v.sayHint:SetPoint("TOPLEFT", RIGHT, -538)
  v.sayHint:SetHeight(30)
  v.sayHint:SetText("Only while you are in a party or raid, as plain lines. Nothing else goes to chat without Post.")
  v.Refresh = function() UI:RefreshSettingsView(v) end
  return v
end

function UI:RefreshSettingsView(v)
  local set = QB:Settings()
  local choice = QB:LockChoice()
  local vals = { auto = 1, off = 2, on = 3 }
  for i, b in ipairs(v.modeBtns) do b:SetEnabled(vals[choice] ~= i) end
  local mode = QB:Mode()
  local held, nextCap = QB:Lock()
  local was = QB:Held()
  local line
  if mode == "lock" then
    line = string.format("Banking: the game holds you at level %d. Keep finished quests in your log and hand them all in when the cap goes up to %d; the Hand-in Route plans that hour.", held, nextCap)
  elseif mode == "rush" then
    line = "The cap went up: cash your bank in. Your first hand-in starts the run and the route re-plans as you go."
  elseif choice == "off" then
    line = "Questing, chosen by you: hand quests in as you go. No banking, no hand-in hour."
  else
    line = string.format("Questing: the game lets you level to %d, so hand quests in as you go. QuestBank switches to banking by itself when the game holds your level at a cap.", QB.CAP)
  end
  if choice == "auto" then line = "Auto. " .. line end
  v.modeText:SetText(line)
  local banking = mode ~= "quest"
  local capNow = nextCap or (was and was.next)
  v.capLabel:SetText(banking and capNow and string.format("When the cap goes up, it goes to %d", capNow) or "Next cap: only used while banking")
  v.capDown:SetEnabled(banking)
  v.capUp:SetEnabled(banking)
  v.pins:SetChecked(set.pins and true or false)
  v.minimap:SetChecked(not (set.minimap and set.minimap.hide))
  v.arrow:SetChecked(set.arrow and true or false)
  local newest = QB.newest
  v.verText:SetText(newest and string.format("You run QuestBank %s. |cff0a6a0a%s runs %s: time to update.|r", QB.version, newest.who or "Someone", newest.version)
    or string.format("You run QuestBank %s, the newest anyone on the realm has shown.", QB.version))
  v.updates:SetChecked(set.updates and true or false)
  local nq, nn, nc = QB.Discover.Count()
  -- the box only means something on the Forever client: elsewhere it is greyed out and says so
  local G = QB.Game -- missing only when the files were swapped under a running game
  local forever = G and G.Forever() or false
  v.noteGame:SetEnabled(forever)
  v.noteGame:SetChecked(forever and set.noteGame ~= false)
  v.noteGame.label:SetText(forever and "Note items and spells you see, for foreverrank.com" or "Note items and spells you see (Forever client only)")
  local ink = forever and INK or INK_SOFT
  v.noteGame.label:SetTextColor(ink[1], ink[2], ink[3])
  local items = (G and G.On()) and string.format(", %d items", (G.Count())) or ""
  v.discText:SetText(string.format("Noted in game so far: %d quests, %d quest NPCs, %d chain steps%s. Forever is still being discovered: upload your QuestBank.lua at foreverrank.com/questbank/ and it goes into the next release for everyone.", nq, nn, nc, items))
  v.offers:SetChecked(set.post.auto and true or false)
  v.shareParty:SetChecked(set.share.party and true or false)
  v.shareGuild:SetChecked(set.share.guild and true or false)
  local above, below, autoA, autoB = QB:Range()
  v.rangeAboveLabel:SetText(string.format("Up to %d levels above me%s", above, autoA and " (auto)" or ""))
  v.rangeBelowLabel:SetText(string.format("Down to %d below%s", below, autoB and " (auto)" or ""))
  v.skipKal:SetChecked(set.skipCont[1] == true)
  v.skipEK:SetChecked(set.skipCont[0] == true)
  v.autoAccept:SetChecked(set.autoAccept == true)
  v.autoTurnIn:SetChecked(set.autoTurnIn == true)
  v.sayAccept:SetChecked(set.sayAccept == true)
  v.sayComplete:SetChecked(set.sayComplete == true)
  local zones = {}
  for _, c in ipairs(QB.Data.CAT) do if set.skipCat[c.key] then zones[#zones + 1] = c.name end end
  table.sort(zones)
  local first = {}
  for i = 1, math.min(3, #zones) do first[i] = zones[i] end
  local more = #zones - #first
  v.skipText:SetText(#zones > 0 and ("Skipped: " .. table.concat(first, ", ") .. (more > 0 and string.format(" and %d more", more) or "")
      .. ". Back on its card on Available, or /qb skip and the name, brings one back; /qb skip lists them all.")
    or "Skip a zone or dungeon with the Skip button on its Plan card, or /qb skip and its name. Skipped places are never suggested; what you already hold there stays.")
  v.scroll:SetContentHeight(628) -- here, once the view has its height, so the knob runs exactly what doesn't fit
end

----------------------------------------------------------------------------
-- minimap button
----------------------------------------------------------------------------
local MB = {}
QB.Minimap = MB

function MB:Create()
  if self.button or not Minimap then return end
  T = T or QB.Data.TEX
  local b = CreateFrame("Button", "QuestBankMinimapButton", Minimap)
  self.button = b
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture(T.minimapHi)
  local bg = tex(b, "BACKGROUND", T.minimapBg, 20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = tex(b, "ARTWORK", T.book, 17, 17)
  icon:SetPoint("TOPLEFT", 7, -6)
  local ring = tex(b, "OVERLAY", T.ring, 53, 53)
  ring:SetPoint("TOPLEFT")
  b:SetScript("OnClick", QB.Safe(function(_, which)
    if which == "RightButton" then UI:Open(3) else UI:Toggle() end
  end, "minimap button"))
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      QB:Settings().minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
      MB:Update()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  tooltip(b, function(tip)
    tip:AddLine("QuestBank", GOLD[1], GOLD[2], GOLD[3])
    local r = QB.routeNow
    if r and r.legs and r.legs[1] then
      tip:AddLine(string.format("%s: %s XP, level %.1f", QB:Banking() and "Banked" or "Ready to hand in", QB.Comma(r.xp), r.level), 1, 1, 1)
      tip:AddLine("Next stop: " .. r.legs[1].stop.name, 0.8, 0.8, 0.8)
    end
    if QB.Run.Get() then
      local got, n = QB.Run.Totals()
      tip:AddLine(string.format("Run %s: %d in, +%s XP", QB.Clock(QB.Run.Elapsed()), n, QB.Comma(got)), 0.4, 1, 0.4)
    end
    tip:AddLine("Click: open.  Right-click: hand-in route.  Drag: move.", 0.6, 0.6, 0.6)
  end)
  self:Update()
end

function MB:Update()
  local b = self.button
  if not b then return end
  local m = QB:Settings().minimap
  b:SetShown(not m.hide)
  local a = math.rad(m.angle or 205)
  local radius = (Minimap:GetWidth() or 140) / 2 + 10
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * radius, math.sin(a) * radius)
end
