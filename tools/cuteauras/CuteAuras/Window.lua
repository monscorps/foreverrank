-- SPDX-License-Identifier: GPL-3.0-or-later
-- The window (/cauras): four tabs in Cute's look.
--   Settings     the bar (a part's own boxes indented under it), the alerts, the group, the minimap button; Move and
--                Test (the window steps aside while they show)
--   Consumables  where you stand and your role; Well Fed and each kind's items (carried, used or chosen), each with its
--                state here and chips for World, PvP, 5-man, Raid and Never; each kind's defaults over its rows
--   Blessings    the grid: each class and role in the group down the side (tanks first; a raid's rows closer, the
--                rest a mouse wheel away), each paladin running Cute Auras or heard on PallyPower across the top
--                (closer for more), the blessing each gives; a click on your own column (any column for the leader or
--                an assist) steps to the next blessing that paladin gives there, a right-click puts back Cute Auras'
--                choice; a cell set in PallyPower is changed there, not here. Under it: who gives the other buffs, who
--                is on PallyPower, who runs neither
--   Biome gear   where you stand and its biomes, your biome pieces (worn and in your bags) with their cooldowns and
--                whether they work here (or can't be worn yet), where each one's swaps show (World, PvP, 5-man, Raid) and
--                its Never; the places learned from your biome auras, and a button to forget them
local _, A = ...
local Wn = A.Part("Window", {})
local L, S, D = A.Look, A.Spells, A.Data
local C = L.C
local plain, call = A.Plain, A.Call
local W, H = 640, 520
local frame, tabs, pages = nil, {}, {}
local current = "settings"

local function panel(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, -62)
  f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -14, 14)
  f:Hide()
  return f
end

----------------------------------------------------------------------------
-- widgets: a check (the whole row clicks), a choice (a row of options), a button. A check and a choice join their
-- page's list (parent.widgets), so the page's Sync reads every one again: a value changed elsewhere (/cauras minimap)
-- shows the next time the page is opened or refreshed. Each click runs through A.Safe: an error lands in
-- /cauras errors instead of nowhere
----------------------------------------------------------------------------
local function joinPage(parent, w)
  parent.widgets = parent.widgets or {}
  parent.widgets[#parent.widgets + 1] = w
end
local function check(parent, x, y, text, get, set, note)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(280, note and 34 or 22)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b.box = b:CreateTexture(nil, "ARTWORK")
  b.box:SetSize(14, 14); b.box:SetPoint("TOPLEFT", 0, -4)
  b.box:SetColorTexture(C.RULE[1], C.RULE[2], C.RULE[3], 1)
  b.tick = b:CreateTexture(nil, "OVERLAY")
  b.tick:SetSize(8, 8); b.tick:SetPoint("CENTER", b.box, "CENTER")
  b.tick:SetColorTexture(C.PINK[1], C.PINK[2], C.PINK[3], 1)
  b.label = L.Label(b, 12, C.INK)
  b.label:SetPoint("TOPLEFT", b.box, "TOPRIGHT", 8, 0)
  b.label:SetText(text)
  if note then
    b.note = L.Label(b, 10, C.DIM)
    b.note:SetPoint("TOPLEFT", b.label, "BOTTOMLEFT", 0, -2)
    b.note:SetWidth(258)
    b.note:SetText(note)
  end
  b.hi = b:CreateTexture(nil, "HIGHLIGHT"); b.hi:SetAllPoints(); b.hi:SetColorTexture(1, 1, 1, 0.04)
  function b:Sync() self.tick:SetShown(get() and true or false) end
  b:SetScript("OnClick", A.Safe(function(self) set(not get()); self:Sync() end, "window: " .. text))
  b:Sync()
  joinPage(parent, b)
  return b
end
local function choice(parent, x, y, text, options, get, set)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(290, 40)
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  f.label = L.Label(f, 12, C.INK)
  f.label:SetPoint("TOPLEFT", 0, 0)
  f.label:SetText(text)
  f.buttons = {}
  local bx = 0
  for i, o in ipairs(options) do
    local b = CreateFrame("Button", nil, f)
    local w = math.max(40, math.floor((o[2]):len() * 6.4) + 14)
    b:SetSize(w, 18)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", bx, -18)
    bx = bx + w + 2
    b.bg = L.Fill(b, "BACKGROUND", C.PANEL2, 1); b.bg:SetAllPoints()
    b.text = L.Label(b, 10, C.DIM, "CENTER"); b.text:SetPoint("CENTER"); b.text:SetText(o[2])
    b.value = o[1]
    b:SetScript("OnClick", A.Safe(function() set(o[1]); f:Sync() end, "window: " .. text))
    f.buttons[i] = b
  end
  function f:Sync()
    local v = get()
    for _, b in ipairs(self.buttons) do
      local on = b.value == v
      b.bg:SetColorTexture(on and C.PINK[1] or C.PANEL2[1], on and C.PINK[2] * 0.75 or C.PANEL2[2], on and C.PINK[3] * 0.8 or C.PANEL2[3], 1)
      local tc = on and C.WHITE or C.DIM
      b.text:SetTextColor(tc[1], tc[2], tc[3])
    end
  end
  f:Sync()
  joinPage(parent, f)
  return f
end
local function button(parent, x, y, text, fn, w)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 92, 22)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b.bg = L.Fill(b, "BACKGROUND", C.PANEL2, 1); b.bg:SetAllPoints()
  b.edge = b:CreateTexture(nil, "BORDER"); b.edge:SetPoint("BOTTOMLEFT"); b.edge:SetPoint("BOTTOMRIGHT"); b.edge:SetHeight(1)
  b.edge:SetColorTexture(C.PINK[1], C.PINK[2], C.PINK[3], 0.8)
  b.text = L.Label(b, 11, C.WHITE, "CENTER"); b.text:SetPoint("CENTER"); b.text:SetText(text)
  b.hi = b:CreateTexture(nil, "HIGHLIGHT"); b.hi:SetAllPoints(); b.hi:SetColorTexture(1, 1, 1, 0.06)
  b:SetScript("OnClick", function() A.Safe(fn, "window: " .. text)() end)
  return b
end
local function head(parent, x, y, text)
  local t = L.Label(parent, 13, C.WHITE)
  t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  t:SetText(text)
  local r = parent:CreateTexture(nil, "ARTWORK")
  r:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -4); r:SetSize(290, 1)
  r:SetColorTexture(C.RULE[1], C.RULE[2], C.RULE[3], 1)
  return t
end
-- a small toggle, 48 x 18 (the Consumables' and Biome gear's places and Never), its tooltip its word and a line. x:
-- from its parent's left edge, centred on it (nil: its caller places it). outline: a default's chip, a 1 px border and
-- no fill, so it never reads as an item's own choice
local EDGES = { { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }
local function chip(parent, x, label, tip, outline)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(48, 18)
  if x then b:SetPoint("LEFT", parent, "LEFT", x, 0) end
  if outline then
    b.edges = {}
    for i, pt in ipairs(EDGES) do
      local e = b:CreateTexture(nil, "BORDER")
      e:SetPoint(pt[1]); e:SetPoint(pt[2])
      if i <= 2 then e:SetHeight(1) else e:SetWidth(1) end
      b.edges[i] = e
    end
  else
    b.bg = L.Fill(b, "BACKGROUND", C.PANEL2, 1); b.bg:SetAllPoints()
  end
  b.outline = outline and true or false
  b.text = L.Label(b, 10, C.DIM, "CENTER"); b.text:SetPoint("CENTER"); b.text:SetText(label)
  b.tip = tip
  local function tipNow(self)
    if not GameTooltip then return end
    self.tipShown = self.tip
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(label, C.WHITE[1], C.WHITE[2], C.WHITE[3])
    GameTooltip:AddLine(self.tip, C.INK[1], C.INK[2], C.INK[3], true)
    GameTooltip:Show()
  end
  b:SetScript("OnEnter", tipNow)
  -- (the game's tooltip asks its owner again every 0.2 s: a click's new words show under the cursor)
  function b:UpdateTooltip() if self.tip ~= self.tipShown then tipNow(self) end end
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  function b:Paint(on, dim)
    if self.outline then
      local ec = on and C.PINK or C.RULE
      for _, e in ipairs(self.edges) do e:SetColorTexture(ec[1], ec[2], ec[3], 1) end
    else
      self.bg:SetColorTexture(on and C.PINK[1] * 0.75 or C.PANEL2[1], on and C.PINK[2] * 0.6 or C.PANEL2[2], on and C.PINK[3] * 0.65 or C.PANEL2[3], 1)
    end
    local tc = on and C.WHITE or C.DIM
    self.text:SetTextColor(tc[1], tc[2], tc[3])
    self:SetAlpha(dim and 0.4 or 1)
    self.on = on and true or false
  end
  return b
end

----------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------
local function settingsPage(p)
  local s = function() return A.Settings() end
  local function bar() A.Bar.Dirty("all") end
  local function flag(key, after) return function() return s()[key] ~= false end, function(v) s()[key] = v; if after then after() end; bar() end end
  local x1, x2 = 0, 312
  -- (a part's own boxes sit under it, indented, greyed while that part is off: the camp's two, the buffs others give
  -- you, which show in yours)
  local IN = 16
  head(p, x1, 0, "The bar")
  -- (what you give the group follows the bar: off, its group part off or Nothing in dungeons and raids, a new hello)
  local function gives() A.Comm.GivesChanged() end
  -- (a box others' words follow: the page read again)
  local function resync() if p.Sync then p:Sync() end end
  local g, st = flag("on", function() gives(); resync() end); check(p, x1, -22, "Show the bar", g, st)
  local featCheck, bpCheck, othersCheck
  local function partDeps()
    local now = s()
    local campA, mineA = now.camp ~= false and 1 or 0.45, now.mine ~= false and 1 or 0.45
    featCheck:SetAlpha(campA); bpCheck:SetAlpha(campA); othersCheck:SetAlpha(mineA)
  end
  g, st = flag("camp", partDeps); check(p, x1, -44, "Camp, food and sleeping bag", g, st)
  g, st = flag("features"); featCheck = check(p, x1 + IN, -66, "Camp items at the fire near you", g, st)
  g, st = flag("blueprints"); bpCheck = check(p, x1 + IN, -88, "Blueprints you can use", g, st, "Only for your professions, level, class and race.")
  -- (the consumables show in your buffs and before the pull: their row greyed only while both are off; Before the
  -- pull shows only consumables, so it is greyed and says so while they are Off)
  local consumeRow, pullCheck
  local function consumeDep()
    local now = s()
    if consumeRow then consumeRow:SetAlpha((now.mine ~= false or now.pull ~= false) and 1 or 0.45) end
    if pullCheck then
      local off = not A.Consume.On()
      pullCheck:SetAlpha(off and 0.45 or 1)
      pullCheck.label:SetText(off and "Before the pull: consumables Off" or "Before the pull (ready check)")
    end
  end
  g, st = flag("mine", function() consumeDep(); partDeps() end); check(p, x1, -122, "Your buffs and weapon", g, st)
  g, st = flag("others"); othersCheck = check(p, x1 + IN, -144, "Buffs others give you", g, st)
  partDeps()
  g, st = flag("group", function() gives(); resync() end); check(p, x1, -166, "Buffs you give the group", g, st)
  g, st = flag("pull", consumeDep); pullCheck = check(p, x1, -188, "Before the pull (ready check)", g, st)
  choice(p, x1, -214, "In dungeons and raids", { { "buffs", "Buffs only" }, { "all", "Everything" }, { "none", "Nothing" } },
    function() return s().instance end, function(v) s().instance = v; bar(); gives() end)
  choice(p, x1, -256, "In a fight", { { "group", "Keep the group's" }, { "hide", "Hide the bar" } },
    function() return s().fight end, function(v) s().fight = v; A.Bar.FightDriver(); resync() end)
  choice(p, x1, -298, "Size", { { 0.75, "75%" }, { 1, "100%" }, { 1.25, "125%" }, { 1.5, "150%" } },
    function() return s().scale end, function(v) s().scale = v; A.OutOfFight("bar: place", A.Bar.Place) end)
  -- (what is asked where: the Consumables tab; this box is all of them, on or off)
  consumeRow = check(p, x1, -340, "Potions, elixirs, flasks and food", function() return A.Consume.On() end,
    function(v) A.Consume.Settings().on = v and true or false; consumeDep(); bar() end, "What is asked where: the Consumables tab.")
  consumeDep()

  head(p, x2, 0, "Alerts")
  -- (the rebuff card is an alert, so it waits for Alerts on screen: its tick greyed then; the Hands keep the bar's glow)
  local rebuffCheck, handsCheck
  local function deps()
    local on = s().alerts ~= false
    rebuffCheck:SetAlpha(on and 1 or 0.45)
    rebuffCheck.note:SetText(on and "In a fight too; only the buffer who owes it." or "Needs Alerts on screen: it is an alert.")
    -- (with alerts off a restore is only the row's glow in the bar's group list: none when that list never shows)
    local rows = s().on ~= false and s().group ~= false and s().fight ~= "hide"
    handsCheck.note:SetText(on and "A countdown, then the blessing they lost."
      or rows and "Alerts off: only their row in the bar glows."
      or "Alerts off and no group list in a fight: nothing.")
  end
  g, st = flag("alerts", function() deps(); A.Rebuff.Update(); A.Hands.Refresh(); if s().alerts == false then A.Alerts.Clear() end end)
  check(p, x2, -22, "Alerts on screen", g, st)
  g, st = flag("rebuff", function() A.Rebuff.Update() end)
  rebuffCheck = check(p, x2, -44, "Buff again after a resurrection", g, st, "In a fight too; only the buffer who owes it.")
  g, st = flag("hands", function() A.Hands.Setting() end)
  handsCheck = check(p, x2, -78, "Protection, Freedom and Sacrifice", g, st, "A countdown, then the blessing they lost.")
  deps()
  g, st = flag("sound"); check(p, x2, -112, "Sound", g, st)
  -- (Show as: 36 px icons, the words in their tooltips, or the cards with their words on them)
  choice(p, x2, -136, "Show as", { { "icons", "Icons" }, { "small", "Small cards" }, { "normal", "Cards" }, { "big", "Big cards" } },
    function() return A.Alerts.Icons() and "icons" or s().alertLook end, function(v) s().alertLook = v; A.Alerts.Restyle() end)
  choice(p, x2, -178, "Scale", { { 0.75, "75%" }, { 1, "100%" }, { 1.25, "125%" }, { 1.5, "150%" } },
    function() return s().alertScale end, function(v) s().alertScale = v; A.OutOfFight("alerts: place", A.Alerts.Place) end)
  -- (Move and Test show what sits under this window: the bar and the overlay are near the screen's centre, so the
  -- window steps aside while they show and comes back after)
  p.moveBtn = button(p, x2, -222, "Move", function() Wn.Move(true) end)
  button(p, x2 + 98, -222, "Test", function() Wn.Test() end)
  head(p, x2, -262, "Group")
  choice(p, x2, -284, "Your role", { { "auto", "Auto" }, { "tank", "Tank" }, { "healer", "Heal" }, { "melee", "Melee" }, { "ranged", "Ranged" }, { "caster", "Caster" } },
    function() return A.Char().role or "auto" end,
    function(v) A.Char().role = v ~= "auto" and v or nil; A.Roster.Changed(); A.Comm.HelloSoon(1) end)
  g, st = flag("blessings", function() A.Comm.HelloSoon(1); A.Assign.Changed() end); check(p, x2, -324, "Blessings shared out by Cute Auras", g, st)
  g, st = flag("greater"); check(p, x2, -346, "Greater blessings with Symbol of Kings", g, st)
  check(p, x2, -368, "Shadow Protection (priests)", function() return s().opt.shadow == true end,
    function(v) s().opt.shadow = v or nil; A.Comm.HelloSoon(1); A.Assign.Changed() end)
  -- (the minimap button is no group setting: its own heading at the foot of the column)
  head(p, x2, -396, "Minimap")
  g, st = flag("minimap", function() A.Minimap.Update() end); check(p, x2, -418, "Button on the minimap", g, st)
  -- (the Nevers: how many of the 32 the bar keeps, and all shown again)
  p.nevers = L.Label(p, 11, C.DIM)
  p.nevers:SetPoint("TOPLEFT", p, "TOPLEFT", x1, -390)
  p.show = button(p, x1, -408, "Show them all", function() for k in pairs(A.Settings().never) do A.Settings().never[k] = nil end; A.Bar.Dirty("all"); gives(); Wn.Refresh() end, 120)
  function p:Sync()
    for _, w in ipairs(self.widgets or {}) do w:Sync() end
    consumeDep(); deps(); partDeps()
    self.moveBtn.text:SetText(Wn.Moving() and "Done" or "Move")
    local n, most = A.Bar.NeverCount(), A.Bar.NEVER_MAX
    self.nevers:SetText(n == 0 and "Nothing hidden for good." or (n .. " of " .. most .. " hidden for good (right-click, Never)."))
    self.show:SetShown(n > 0)
  end
end

----------------------------------------------------------------------------
-- Blessings
----------------------------------------------------------------------------
local ROLE_WORD = { tank = "Tank", healer = "Healer", melee = "Melee", ranged = "Ranged", caster = "Caster" }
-- the rows' order on the page: tanks first, then healers, melee, ranged and casters, each by class (the share-out's own
-- order is left as it is)
local ROLE_ORDER = { tank = 1, healer = 2, melee = 3, ranged = 4, caster = 5 }
local CYCLE = { "kings", "might", "wisdom" }
-- the page is 612 by 444: the paladins' names across from x 150, the rows from y -46, two lines of words under them
local PAGE_W, PAGE_H, LEFT, TOP, BELOW = 612, 444, 150, 46, 42
-- what a left click on a cell sets: the next blessing in Kings, Might, Wisdom order after the one set now (by hand, else
-- Cute Auras' choice) that the paladin gives, never Wisdom to a bucket without a mana bar; nil when there is no other
local function nextFor(As, pg, bk)
  local m = A.Roster.ByGUID(pg)
  local k = (m and As.HelloOf(m)) or {}
  local mana = false
  for _, x in ipairs(As.buckets and As.buckets[bk] or {}) do if x.mana then mana = true end end
  local ov = As.overrides[pg] and As.overrides[pg][bk]
  local cur = (ov and not ov.clear and ov.key) or As.BlessingOf(pg, bk)
  local at = 0
  for i, key in ipairs(CYCLE) do if key == cur then at = i end end
  for step = 1, #CYCLE do
    local key = CYCLE[(at + step - 1) % #CYCLE + 1]
    if key ~= cur and (k[key] or 0) > 0 and (key ~= "wisdom" or mana) then return key end
  end
  return nil
end
-- (a cell set in PallyPower: a paladin on PallyPower alone, or a PallyPower cell of one running both)
local function ppCell(As, pg, bk) return As.Source(pg, bk) == "pp" end
-- names in a line as many as fit its width, the rest counted ("Without Cute Auras ...: A, B and 3 more.")
local function namesLine(t, head, names)
  for k = #names, 0, -1 do
    local rest = #names - k
    local text = head .. table.concat(names, ", ", 1, k) .. (rest > 0 and ((k > 0 and " and " or "") .. rest .. " more") or "") .. "."
    t:SetText(text)
    if k == 0 or L.Width(t) <= t:GetWidth() then break end
  end
end
local function blessingsPage(p)
  p.title = L.Label(p, 12, C.INK); p.title:SetPoint("TOPLEFT", 0, 0); p.title:SetWidth(PAGE_W)
  -- (more rows than fit: which ones show, and the mouse wheel moves them)
  p.more = L.Label(p, 11, C.DIM); p.more:SetPoint("TOPLEFT", 0, -28); p.more:SetWidth(LEFT - 6)
  p.first = 1
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(self, delta) self.first = (self.first or 1) - delta; self:Sync() end)
  p.cells, p.rows, p.cols, p.lines, p.cut = {}, {}, {}, {}, {}
  function p:Sync()
    local As = A.Assign
    for _, t in ipairs(self.cells) do t:Hide() end
    for _, t in ipairs(self.rows) do t:Hide() end
    for _, t in ipairs(self.cols) do t:Hide() end
    for _, t in ipairs(self.lines) do t:Hide() end
    local pals = As.paladins or {}
    local buckets = {}
    for _, b in ipairs(As.bucketList or {}) do buckets[#buckets + 1] = b end
    table.sort(buckets, function(a, b)
      local ra, rb = ROLE_ORDER[a.role or ""] or 9, ROLE_ORDER[b.role or ""] or 9
      if ra ~= rb then return ra < rb end
      return a.key < b.key
    end)
    -- the columns: 88 apart, closer for more paladins, never under 28 (sixteen across the page)
    local nCols = math.min(#pals, math.floor((PAGE_W - LEFT) / 28))
    local colW = nCols > 0 and math.min(88, math.floor((PAGE_W - LEFT) / nCols)) or 88
    -- (the lines under the grid: yours, the paladins on PallyPower, the members on neither)
    local Ps = A.PallySync
    local mine, ppNames, without = {}, {}, {}
    for _, d in ipairs(As.duties or {}) do
      if not d.bless then mine[#mine + 1] = L.SpellName(d.entry.ranks[1], d.entry.name) .. " to " .. #d.targets end
    end
    for _, m in ipairs(A.Roster.members) do
      local pp = Ps and Ps.pals[m.guid] ~= nil
      if pp then ppNames[#ppNames + 1] = m.me and "You" or m.name end
      if not pp and not A.Comm.Running(m.guid) then without[#without + 1] = m.name end
    end
    local nLines = (#mine > 0 and 1 or 0) + (#ppNames > 0 and 1 or 0) + (#without > 0 and 1 or 0)
    -- the rows: 28 apart, down to 20 for a raid's fifteen kinds; more than fit scroll
    local room = PAGE_H - TOP - math.max(BELOW, 10 + 16 * nLines)
    local rowH = math.max(20, math.min(28, math.floor(room / math.max(1, #buckets))))
    local fit = math.floor(room / rowH)
    local first = math.max(1, math.min(self.first or 1, #buckets - fit + 1))
    self.first = first
    local last = math.min(#buckets, first + fit - 1)
    local size = math.min(24, rowH - 4, colW - 4)
    local why = A.Comm.WhyNoBlessings()
    -- (the paladins heard on PallyPower, not you)
    local ppOthers = {}
    for _, m in ipairs(A.Roster.members) do if Ps and Ps.pals[m.guid] and not m.me then ppOthers[#ppOthers + 1] = m end end
    local meM = A.Roster.Me()
    -- (what you may click: a paladin, your column; one who is no paladin, any cell as the leader or an assist, else none,
    -- so no title asks it of them. PallyPower's own paladins' cells never click)
    local isPal = meM ~= nil and meM.class == "PALADIN"
    local leads = not isPal and meM ~= nil and (A.Yes(UnitIsGroupLeader, meM.unit) or A.Yes(UnitIsGroupAssistant, meM.unit))
    local anyCute = false
    for _, pal in ipairs(pals) do if not (As.ppOnly and As.ppOnly[pal.guid]) then anyCute = true end end
    local ppClick = isPal and " Click your column; right-click for Cute Auras' choice."
      or ((leads and anyCute) and " Click another paladin's cell to change it." or "")
    if not A.Roster.InGroup() then
      self.title:SetText("Join a group: the paladins running Cute Auras share the blessings out, one kind each.")
    elseif why and Ps and Ps.Here() and isPal and Ps.pals[meM.guid] then
      -- (your PallyPower still casts your column, shown as it set it; Cute Auras adds nothing to it)
      self.title:SetText("Your PallyPower sets your column; Cute Auras fills none of it: " .. why .. ".")
    elseif why then
      -- (you left yourself out: no column of yours, and the box that did it named; before PallyPower's titles, which
      -- ask you to click a column you do not have)
      self.title:SetText("You give no blessings now: " .. why .. " (Settings).")
    elseif Ps and Ps.Here() and isPal then
      self.title:SetText("Your PallyPower sets your column; Cute Auras fills what it leaves empty.")
    elseif #ppOthers == 1 then
      self.title:SetText(ppOthers[1].name .. " uses PallyPower: shown as set there." .. ppClick)
    elseif #ppOthers > 1 then
      self.title:SetText(#ppOthers .. " paladins use PallyPower: shown as set there." .. ppClick)
    elseif #pals == 0 then
      self.title:SetText("No paladin in the group runs Cute Auras yet.")
    elseif nCols < #pals then
      local click = isPal and " Click your column; right-click for Cute Auras' choice."
        or (leads and " Click a cell; right-click for Cute Auras' choice." or "")
      self.title:SetText("The first " .. nCols .. " of " .. #pals .. " paladins." .. click)
    elseif isPal then
      self.title:SetText("Click your column to change a blessing; right-click for Cute Auras' choice.")
    elseif leads then
      self.title:SetText("Click a cell to change a blessing; right-click for Cute Auras' choice.")
    else
      self.title:SetText("Each paladin sets their own column; the leader or an assist can set any.")
    end
    self.more:SetText(#buckets > fit and ("Scroll: " .. first .. "-" .. last .. " of " .. #buckets) or "")
    local me = A.MyGUID()
    for j in pairs(self.cut) do self.cut[j] = nil end
    for j = 1, nCols do
      local pal = pals[j]
      local c = self.cols[j]
      if not c then c = L.Label(self, 11, C.WHITE, "CENTER"); self.cols[j] = c end
      c:SetWidth(colW - 4)
      c:ClearAllPoints(); c:SetPoint("TOPLEFT", self, "TOPLEFT", LEFT + (j - 1) * colW, -26)
      -- (cut clean to its column, no dots: then its cells' tooltips name the paladin in full)
      local full = pal.me and "You" or pal.name or ""
      local fit = L.Fit(c, full, colW - 4) or ""
      self.cut[j] = fit ~= full and full or nil
      c:SetText(fit); c:SetTextColor(L.ClassColor("PALADIN")); c:Show()
    end
    local y = -TOP
    local n = 0
    for i = first, last do
      local b = buckets[i]
      local r = self.rows[i - first + 1]
      if not r then r = L.Label(self, 11, C.INK); r:SetWidth(LEFT - 6); self.rows[i - first + 1] = r end
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", self, "TOPLEFT", 0, y - math.max(0, math.floor(size / 2) - 6))
      local cls = b.class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[b.class] or b.class) or "?"
      r:SetText(cls .. ", " .. (ROLE_WORD[b.role] or b.role or "") .. " (" .. #b .. ")")
      r:SetTextColor(L.ClassColor(b.class)); r:Show()
      for j = 1, nCols do
        local pal = pals[j]
        n = n + 1
        local cell = self.cells[n]
        if not cell then
          cell = L.Icon(nil, self, false, false, 24)
          cell:RegisterForClicks("AnyUp", "RightButtonUp")
          cell:SetScript("OnClick", A.Safe(function(btn, mouse)
            local pg, bk = btn.pal, btn.bucket
            if not (pg and bk) or not As.MayChange(me, pg) then return end
            -- (set in PallyPower: changed there)
            if ppCell(As, pg, bk) then return end
            if mouse == "RightButton" then As.Set(pg, bk, nil) return end
            local key = nextFor(As, pg, bk)
            if key then As.Set(pg, bk, key) end
          end, "blessings: a cell"))
          cell:SetScript("OnEnter", A.Safe(function(btn)
            if not GameTooltip then return end
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            local key = As.BlessingOf(btn.pal, btn.bucket)
            GameTooltip:SetText(key and D.BLESS[key].name or "No blessing", C.WHITE[1], C.WHITE[2], C.WHITE[3])
            -- (last: the column's paladin in full, when the name over it is cut to fit)
            local function whose()
              if btn.palName then GameTooltip:AddLine("Paladin: " .. btn.palName .. ".", C.DIM[1], C.DIM[2], C.DIM[3]) end
            end
            local ov = As.overrides[btn.pal] and As.overrides[btn.pal][btn.bucket]
            if ppCell(As, btn.pal, btn.bucket) then
              GameTooltip:AddLine("Set in PallyPower.", C.DIM[1], C.DIM[2], C.DIM[3])
              GameTooltip:AddLine("Change it in PallyPower.", C.DIM[1], C.DIM[2], C.DIM[3], true)
              whose()
              GameTooltip:Show()
              return
            end
            local said = "Cute Auras' choice."
            if ov and not ov.clear then said = ov.pp and "Set by the leader in PallyPower." or "Set by hand." end
            GameTooltip:AddLine(said, C.DIM[1], C.DIM[2], C.DIM[3])
            if not As.MayChange(me, btn.pal) then
              GameTooltip:AddLine("Only that paladin, the leader or an assist can change it.", C.DIM[1], C.DIM[2], C.DIM[3], true)
            else
              local nx = nextFor(As, btn.pal, btn.bucket)
              GameTooltip:AddLine(nx and ("Click: " .. D.BLESS[nx].name .. ".") or "No other blessing this paladin gives here.", C.DIM[1], C.DIM[2], C.DIM[3], true)
              -- (a cell set by hand, or by a cast of yours: the right-click gives it back, said here whatever the title says)
              if ov and not ov.clear then GameTooltip:AddLine("Right-click: Cute Auras' choice.", C.DIM[1], C.DIM[2], C.DIM[3], true) end
            end
            whose()
            GameTooltip:Show()
          end, "blessings: a cell's tooltip"))
          cell:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
          self.cells[n] = cell
        end
        cell.pal, cell.bucket, cell.palName = pal.guid, b.key, self.cut[j]
        local key = As.BlessingOf(pal.guid, b.key)
        L.Art(cell.icon, key and L.SpellIcon(D.BLESS[key].ranks[1], D.BLESS[key].icon) or 134400)
        cell.icon:SetDesaturated(key == nil)
        cell.icon:SetAlpha(key and 1 or 0.3)
        cell:SetSize(size, size)
        cell:ClearAllPoints(); cell:SetPoint("TOPLEFT", self, "TOPLEFT", LEFT + (j - 1) * colW + math.floor((colW - 4 - size) / 2), y)
        cell:Show()
      end
      y = y - rowH
    end
    -- the other buffs: who gives which to whom
    local line = 0
    local function say(text, col)
      line = line + 1
      local t = self.lines[line]
      if not t then t = L.Label(self, 11, C.INK); t:SetWidth(600); self.lines[line] = t end
      t:ClearAllPoints(); t:SetPoint("TOPLEFT", self, "TOPLEFT", 0, y - 10 - (line - 1) * 16)
      t:SetText(text); t:SetTextColor((col or C.INK)[1], (col or C.INK)[2], (col or C.INK)[3]); t:Show()
    end
    if #mine > 0 then say("Yours: " .. table.concat(mine, ", ") .. ".") end
    -- (who is on PallyPower, and who runs neither: as many names as fit the line, the rest counted, so a raid's list
    -- is never cut mid-name)
    if #ppNames > 0 then
      say("", C.INK)
      namesLine(self.lines[line], "Set in PallyPower: ", ppNames)
    end
    if #without > 0 then
      say("", C.DIM)
      namesLine(self.lines[line], "Without Cute Auras (never given a share): ", without)
    end
  end
end

----------------------------------------------------------------------------
-- Consumables: where you stand and your role on the top line; Well Fed, then each kind with rows (a header, its
-- defaults' chips over the rows' own), each item's state here and its chips: World, PvP, 5-man, Raid, Never. The page
-- is 612 by 444: the list from y -24 to -424, 28 an entry, the rest a mouse wheel away
----------------------------------------------------------------------------
local KIND_HEAD = { fed = "Food", flask = "Flasks", elixir = "Elixirs", potion = "Potions", scroll = "Scrolls", other = "Other", weapon = "Weapon" }
local KIND_TIP = { flask = "flasks", elixir = "elixirs", potion = "potions", scroll = "scrolls", other = "other items", weapon = "oils, stones and poisons" }
local ROLE_FROM = { choice = "(your choice)", talents = "(talents)", group = "(the group)" }
local CN_TOP, CN_ENTRY, CN_LIST, CN_CHIPS, CN_STEP, CN_NEVER = -24, 28, 400, 356, 50, 556
local NOT_HERE = "Never is on: click Never to choose again."
local function capital(s) return (s:gsub("^%l", string.upper)) end
local function consumePage(p)
  local Cn = A.Consume
  local PLACES = Cn.PLACES
  -- (the list's parts sit on the page by its own corner; their parent, the list, greys them all while consumables are off)
  p.list = CreateFrame("Frame", nil, p)
  p.list:SetAllPoints(p)
  p.here = L.Label(p, 12, C.WHITE); p.here:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0); p.here:SetWidth(600)
  p.more = L.Label(p, 11, C.DIM); p.more:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -428); p.more:SetWidth(600)
  p.empty = L.Label(p.list, 11, C.DIM); p.empty:SetWidth(600)
  p.empty:SetText("No elixir, flask, potion or scroll in your bags yet.")
  p.first = 1
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(self, delta) self.first = (self.first or 1) - delta; self:Sync() end)
  -- (a row's timed word, a cooldown's or a buff's m:ss, ticks: the page read again once a second while it shows one)
  p.tickT = 0
  local tickSync = A.Safe(function() p:Sync() end, "consumables: the clock")
  p:SetScript("OnUpdate", function(self, elapsed)
    if not self.timed then return end
    self.tickT = self.tickT + (elapsed or 0)
    if self.tickT < 1 then return end
    self.tickT = 0
    if self:IsVisible() then tickSync() end
  end)
  p.heads, p.rows, p.entries = {}, {}, {}
  local function at(o, x, y) o:ClearAllPoints(); o:SetPoint("TOPLEFT", p, "TOPLEFT", x, y) end
  -- a kind's header: its name, its defaults ("By default:" and four outlined chips), a rule under them
  local function newHead(i)
    local h = { chips = {} }
    h.name = L.Label(p.list, 12, C.WHITE); h.name:SetWidth(240)
    h.label = L.Label(p.list, 11, C.DIM, "RIGHT"); h.label:SetWidth(100); h.label:SetText("By default:")
    for j, pl in ipairs(PLACES) do
      local b = chip(p.list, nil, pl[2], "", true)
      b.key = pl[1]
      b:SetScript("OnClick", A.Safe(function(btn)
        if not btn.kind then return end
        Cn.SetKindDefault(btn.kind, btn.key, not Cn.KindDefault(btn.kind, btn.key))
        p:Sync()
      end, "consumables: a default"))
      h.chips[j] = b
    end
    h.rule = p.list:CreateTexture(nil, "ARTWORK")
    h.rule:SetSize(600, 1)
    h.rule:SetColorTexture(C.RULE[1], C.RULE[2], C.RULE[3], 1)
    p.heads[i] = h
    return h
  end
  -- a row's tooltip: the item's own, then what the bar does with it
  local function rowTip(self)
    local id = self.id
    if id == nil or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if id == "fed" then GameTooltip:SetText("Well Fed", C.WHITE[1], C.WHITE[2], C.WHITE[3])
    elseif GameTooltip.SetItemByID then GameTooltip:SetItemByID(id)
    else GameTooltip:SetText(L.ItemName(id, "Item " .. id), C.WHITE[1], C.WHITE[2], C.WHITE[3]) end
    local function dim(s) GameTooltip:AddLine(s, C.DIM[1], C.DIM[2], C.DIM[3], true) end
    if id == "fed" then
      dim("Its last 2 minutes count down wherever you are, out of town.")
    else
      local rep = Cn.Replaces(id)
      if #rep > 0 then dim("Replaces: " .. table.concat(rep, ", ") .. ".") end
      if Cn.KindOf(id) == "flask" and A.Acct().flasksStack ~= true then dim("One flask at a time.") end
      if Cn.Quiet(id) then dim("Shown 30 minutes and not used: asked again once you use it or choose for it here.") end
      if A.Bar.Never("pull:" .. id) then dim("A Never from 0.2.2: not before the pull, and elsewhere only as a habit or where you choose.") end
    end
    if Cn.HasChoice(id) or (id ~= "fed" and A.Bar.Never("pull:" .. id)) then dim("Right-click: back to the defaults.") end
    GameTooltip:Show()
  end
  local function rowMenu(self, mouse)
    local id = self.id
    if mouse ~= "RightButton" or id == nil then return end
    if not (Cn.HasChoice(id) or (id ~= "fed" and A.Bar.Never("pull:" .. id))) then return end
    if type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function" then
      MenuUtil.CreateContextMenu(self, function(_, root)
        root:CreateButton("Back to the defaults", A.Safe(function() Cn.ClearChoice(id); p:Sync() end, "consumables: back to the defaults"))
      end)
    end
  end
  -- an item's row: its icon, name and what it raises, its state here, its places and Never
  local function newRow(i)
    local r = { chips = {} }
    r.icon = L.Icon(nil, p.list, false, false, 24); r.icon:EnableMouse(false)
    r.name = L.Label(p.list, 12, C.WHITE); r.name:SetWidth(220)
    r.sub = L.Label(p.list, 10, C.DIM); r.sub:SetWidth(220)
    r.state = L.Label(p.list, 11, C.INK); r.state:SetWidth(90)
    -- (the row's left part hovers its tooltip and right-clicks its menu; the chips are their own buttons)
    r.hit = CreateFrame("Button", nil, p.list)
    r.hit:SetSize(352, CN_ENTRY)
    r.hit:RegisterForClicks("RightButtonUp")
    r.hit:SetScript("OnEnter", A.Safe(rowTip, "consumables: a row's tooltip"))
    r.hit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    r.hit:SetScript("OnClick", A.Safe(rowMenu, "consumables: a row's menu"))
    for j, pl in ipairs(PLACES) do
      local b = chip(p.list, nil, pl[2], "")
      b.key = pl[1]
      -- (while Never is on, its places wait under it, untouched)
      b:SetScript("OnClick", A.Safe(function(btn)
        local id = r.id
        if id == nil or A.Bar.Never(Cn.NeverKey(id)) then return end
        Cn.SetChoice(id, btn.key, not Cn.Asks(id, btn.key))
        p:Sync()
      end, "consumables: a place"))
      r.chips[j] = b
    end
    r.never = chip(p.list, nil, "Never", "")
    r.never:SetScript("OnClick", A.Safe(function()
      local id = r.id
      if id == nil then return end
      local key = Cn.NeverKey(id)
      Cn.Unquiet(id)
      if A.Bar.Never(key) then A.Bar.SetNever(key, nil, false)
      elseif not A.Bar.SetNever(key, id == "fed" and "Well Fed" or L.ItemName(id, "Item " .. id)) then
        A.Say(A.Bar.NEVER_MAX .. " hidden for good already. Settings, Show them all, makes room.")
      end
      p:Sync()
    end, "consumables: never"))
    p.rows[i] = r
    return r
  end
  local function hideHead(h)
    h.name:Hide(); h.label:Hide(); h.rule:Hide()
    for _, b in ipairs(h.chips) do b:Hide() end
  end
  local function hideRow(r)
    r.icon:Hide(); r.name:Hide(); r.sub:Hide(); r.state:Hide(); r.hit:Hide(); r.never:Hide()
    for _, b in ipairs(r.chips) do b:Hide() end
    r.id = nil; r.hit.id = nil
  end
  local function layHead(h, kind, y)
    h.name:SetText(KIND_HEAD[kind] or kind); at(h.name, 0, y - 5); h.name:Show()
    at(h.rule, 0, y - 26); h.rule:Show()
    local food = kind == "fed"
    h.label:SetShown(not food)
    if not food then at(h.label, CN_CHIPS - 10 - 100, y - 6) end
    for j, b in ipairs(h.chips) do
      if food then b:Hide()
      else
        b.kind = kind
        local on = Cn.KindDefault(kind, b.key)
        b:Paint(on)
        local place = Cn.PLACE_TEXT[b.key]
        local when = kind == "weapon" and "when your main hand has nothing on" or "when they fit your role"
        b.tip = on and (capital(KIND_TIP[kind]) .. " with no choice of their own are asked for in " .. place .. " " .. when .. ". Click: not there.")
          or ("Click: ask for " .. KIND_TIP[kind] .. " with no choice of their own in " .. place .. ", " .. when .. ".")
        at(b, CN_CHIPS + (j - 1) * CN_STEP, y - 3); b:Show()
      end
    end
  end
  local function layRow(r, id, y, where, names, ids)
    r.id, r.hit.id = id, id
    local fed = id == "fed"
    local kind = fed and "fed" or Cn.KindOf(id)
    local food = fed and A.Camp.BestFood(where ~= "solo") or nil
    L.Art(r.icon.icon, fed and (food and L.ItemIcon(food, 133945) or 133945) or L.ItemIcon(id, 134400))
    at(r.icon, 0, y - 2); r.icon:Show()
    r.name:SetText(fed and "Well Fed" or L.ItemName(id, "Item " .. id)); at(r.name, 30, y - 1); r.name:Show()
    local sub
    if fed then sub = food and ("Best you carry: " .. L.ItemName(food, "food")) or "No food that gives it"
    elseif kind == "weapon" then sub = "Main hand"
    else sub = Cn.SubLine(Cn.Words(id), S.Count(id)) end
    r.sub:SetText(sub); at(r.sub, 30, y - 15); r.sub:Show()
    local word, col = Cn.State(id, where, names, ids)
    -- (a countdown ticks; In a fight is looked at again each second too, so the words come back as it ends)
    if word == "In a fight" or word:find("^Cooldown %d") or word:find("^On you %d") then p.timed = true end
    local cc = C[col] or C.DIM
    r.state:SetText(word); r.state:SetTextColor(cc[1], cc[2], cc[3]); at(r.state, 262, y - 8); r.state:Show()
    at(r.hit, 0, y); r.hit:Show()
    local never = A.Bar.Never(Cn.NeverKey(id))
    local when = kind == "weapon" and "when your main hand has nothing on" or "when its buff is missing"
    for j, b in ipairs(r.chips) do
      local place = (fed and b.key == "solo") and "the open world (the camp's Eat)" or Cn.PLACE_TEXT[b.key]
      local on = not never and Cn.Asks(id, b.key)
      b:Paint(on, never)
      b.tip = never and NOT_HERE or on and ("Asked for in " .. place .. " " .. when .. ". Click: not there.")
        or ("Click: ask for it in " .. place .. " " .. when .. ".")
      at(b, CN_CHIPS + (j - 1) * CN_STEP, y - 5); b:Show()
    end
    r.never:Paint(never)
    r.never.tip = never and "Never asked. Click to ask for it again."
      or (fed and "Click: never asked, not before the pull and not as the camp's Eat." or "Click: never asked, not even before the pull.")
    at(r.never, CN_NEVER, y - 5); r.never:Show()
  end
  function p:Sync()
    local where = Cn.Where()
    local on = Cn.On()
    local place = Cn.PLACE_WORD[where] or where
    -- (Settings that keep the bar from asking: said, and the list greyed when nothing is asked at all)
    local s = A.Settings()
    local why = on and Cn.Blocked() or nil
    local eat = where == "solo" and s.camp ~= false and Cn.Asks("fed", "solo")
    local still = why == "mine" and ((s.pull ~= false and eat and "only Before the pull and the camp's Eat ask")
      or (s.pull ~= false and "only Before the pull asks") or (eat and "only the camp's Eat asks")) or nil
    if not on then
      self.here:SetText("Off in Settings: nothing here is asked; the camp's Eat follows Camp.")
    elseif why == "bar" then
      self.here:SetText("Show the bar is off in Settings: nothing is asked.")
    elseif why == "none" then
      self.here:SetText("Here: " .. place .. ". In dungeons and raids is Nothing in Settings: nothing is asked here.")
    elseif why == "mine" and still then
      self.here:SetText("Here: " .. place .. ". Your buffs and weapon is off in Settings: " .. still .. ".")
    elseif why == "mine" then
      self.here:SetText("Here: " .. place .. ". Your buffs and weapon and Before the pull are off in Settings: nothing is asked.")
    elseif A.Yes(IsResting) then
      -- (Before the pull asks wherever a ready check comes, a city too)
      self.here:SetText("Here: " .. place .. ", in a city or inn: " .. (s.pull ~= false and "only a ready check asks." or "nothing is asked there."))
    else
      local role, _, from = A.Roster.MyRole()
      local rw = ROLE_WORD[role] or tostring(role)
      self.here:SetText("Here: " .. place .. ". Your role: " .. rw .. " "
        .. (from == "class" and "(a guess: Settings, Your role)" or ROLE_FROM[from] or "") .. ".")
    end
    self.list:SetAlpha((on and (why == nil or still ~= nil)) and 1 or 0.45)
    -- (your auras: out of a fight only, and once the bar has read them since the last one: till then they are the ones
    -- from before the pull. The states say In a fight meanwhile, which ticks, so the page reads again after that read)
    local names, ids
    if not A.Fighting() and A.Bar.ReadSinceFight() then
      local n, i, hidden = A.Camp.Mine()
      if not hidden then names, ids = n, i end
    end
    -- the entries: a header, then its rows
    local list = self.entries
    for i = #list, 1, -1 do list[i] = nil end
    local byKind = Cn.Rows()
    local nRows = 0
    list[#list + 1] = { head = "fed" }
    list[#list + 1] = { id = "fed" }
    for _, k in ipairs(Cn.KINDS) do
      local rows = byKind[k]
      if k ~= "fed" and rows and #rows > 0 then
        list[#list + 1] = { head = k }
        for _, id in ipairs(rows) do list[#list + 1] = { id = id }; nRows = nRows + 1 end
      end
    end
    local total = #list
    local fit = math.floor(CN_LIST / CN_ENTRY)
    local first = math.max(1, math.min(self.first or 1, total - fit + 1))
    self.first = first
    local n = math.min(fit, total - first + 1)
    -- (a header is never the last one shown: it goes to the next page with its first row)
    if first + n - 1 < total and list[first + n - 1].head then n = n - 1 end
    local last = first + n - 1
    self.more:SetText(total > n and ("Scroll: " .. first .. "-" .. last .. " of " .. total) or "")
    self.shownFirst, self.shownLast, self.total = first, last, total
    local nh, nr = 0, 0
    self.timed = false
    for i = first, last do
      local e = list[i]
      local y = CN_TOP - (i - first) * CN_ENTRY
      if e.head then
        nh = nh + 1
        layHead(self.heads[nh] or newHead(nh), e.head, y)
      else
        nr = nr + 1
        layRow(self.rows[nr] or newRow(nr), e.id, y, where, names, ids)
      end
    end
    for i = nh + 1, #self.heads do hideHead(self.heads[i]) end
    for i = nr + 1, #self.rows do hideRow(self.rows[i]) end
    -- (no item rows: said under the Food section)
    if nRows == 0 then at(self.empty, 0, CN_TOP - 2 * CN_ENTRY - 6); self.empty:Show() else self.empty:Hide() end
  end
end

----------------------------------------------------------------------------
-- Biome gear
----------------------------------------------------------------------------
local function gearPage(p)
  local G = A.Gear
  p.here = L.Label(p, 12, C.WHITE); p.here:SetPoint("TOPLEFT", 0, 0); p.here:SetWidth(600)
  -- (a stripe in the first biome's colour under where you stand)
  p.stripe = p:CreateTexture(nil, "ARTWORK"); p.stripe:SetPoint("TOPLEFT", p.here, "BOTTOMLEFT", 0, -3); p.stripe:SetSize(600, 2); p.stripe:Hide()
  check(p, 0, -22, "Biome gear on the bar", function() return G.Settings().on ~= false end, function(v) G.Settings().on = v; A.Bar.Dirty("gear") end)
  check(p, 300, -22, "Swap for me (out of a fight)", function() return A.Char().gearAuto == true end, function(v) A.Char().gearAuto = v or nil; A.Bar.Dirty("gear") end)
  -- the places, as the piece rows' and the defaults' columns (x 356 on, 50 apart): the consumables' words
  local CTX = A.Consume.PLACES
  -- the defaults, right above the rows' own toggles: they are that column's head too
  p.defaultsRow = CreateFrame("Frame", nil, p)
  p.defaultsRow:SetSize(600, 18); p.defaultsRow:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -50)
  p.defaults = L.Label(p.defaultsRow, 11, C.DIM, "RIGHT"); p.defaults:SetPoint("RIGHT", p.defaultsRow, "LEFT", 346, 0); p.defaults:SetWidth(340)
  p.defaults:SetText("By default:")
  p.defaultChips = {}
  for i, c in ipairs(CTX) do
    local b = chip(p.defaultsRow, 356 + (i - 1) * 50, c[2], "", true)
    b.key = c[1]
    b:SetScript("OnClick", A.Safe(function(btn) local show = G.Settings().show; show[btn.key] = show[btn.key] == false; A.Bar.Dirty("gear"); p:Sync() end, "biome gear: a default"))
    p.defaultChips[i] = b
  end
  p.rows = {}
  p.empty = L.Label(p, 11, C.DIM); p.empty:SetPoint("TOPLEFT", 0, -84); p.empty:SetWidth(600)
  p.empty:SetWordWrap(true); p.empty:SetMaxLines(2)
  p.empty:SetText("No biome pieces on you or in your bags yet. Pieces whose effect is stronger in a biome show here as you find them.")
  p.more = L.Label(p, 11, C.DIM); p.more:SetPoint("TOPLEFT", 0, -388); p.more:SetWidth(600)
  -- the places learned from your pieces' biome auras, and a button to forget them
  p.learned = L.Label(p, 11, C.DIM); p.learned:SetPoint("TOPLEFT", 0, -421); p.learned:SetWidth(420)
  p.forget = button(p, 440, -416, "Forget learned places", function() G.ForgetPlaces(); p:Sync() end, 160)
  -- (a bag piece you can't wear yet: its level, else that you can't; nil while the client has no answer)
  local function wearNote(piece)
    if piece.where ~= "bag" or piece.usable then return nil end
    local name, _, _, _, minLevel = call(C_Item.GetItemInfo, piece.id)
    if plain(name) == nil then return nil end
    minLevel = plain(minLevel)
    local level = plain(call(UnitLevel, "player")) or 1
    if type(minLevel) == "number" and minLevel > level then return "Level " .. minLevel end
    return "Can't wear"
  end
  local order = {}
  function p:Sync()
    local here = G.Here()
    local keys, at = {}, nil
    for key, place in pairs(here) do keys[#keys + 1] = key; at = at or place end
    table.sort(keys)
    self.here:SetText(#keys > 0 and ("Here: " .. G.ColoredList(keys) .. (at and at ~= "water" and (" (" .. at .. ")") or "")) or "No biome here.")
    local col = keys[1] and G.COLOR[keys[1]]
    if col then self.stripe:SetColorTexture(col[1], col[2], col[3], 0.9); self.stripe:Show() else self.stripe:Hide() end
    local show = G.Settings().show
    -- (a default rules every piece with no choice of its own, old or new: its words say so, and what a click does)
    for i, b in ipairs(self.defaultChips) do
      local on = show[b.key] ~= false
      b:Paint(on)
      b.tip = on and ("Pieces with no choice of their own show their swaps on the bar in " .. CTX[i][3] .. ". Click: not there.")
        or ("Click: show swaps on the bar in " .. CTX[i][3] .. " for pieces with no choice of their own.")
    end
    -- (the pieces in their order: worn first, then the ones you can wear that work here, then the rest you can wear,
    -- then the ones you can't; G.pieces is the bar's too, so a copy)
    for i = #order, 1, -1 do order[i] = nil end
    for _, piece in ipairs(G.Scan()) do
      local works = false
      for _, k in ipairs(piece.biomes) do if here[k] then works = true end end
      local rank = piece.where == "worn" and 0 or not piece.usable and 3 or works and 1 or 2
      order[#order + 1] = { piece = piece, rank = rank, note = wearNote(piece) }
    end
    table.sort(order, function(a, b) if a.rank ~= b.rank then return a.rank < b.rank end return a.piece.id < b.piece.id end)
    self.empty:SetShown(#order == 0)
    self.more:SetText(#order > 9 and ("And " .. (#order - 9) .. " more, not shown here.") or "")
    local nPlaces = G.LearnedCount()
    self.learned:SetText(nPlaces == 0 and "No places learned from your biome auras yet."
      or (nPlaces .. (nPlaces == 1 and " place" or " places") .. " learned from your biome auras."))
    self.forget:SetShown(nPlaces > 0)
    for _, r in ipairs(self.rows) do r:Hide() end
    for i, o in ipairs(order) do
      if i > 9 then break end
      local piece = o.piece
      local r = self.rows[i]
      if not r then
        r = CreateFrame("Frame", nil, self)
        r:SetSize(600, 30)
        r.icon = L.Icon(nil, r, false, false, 24); r.icon:SetPoint("LEFT", 0, 0); r.icon:EnableMouse(false)
        r.name = L.Label(r, 12, C.WHITE); r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 0); r.name:SetWidth(220)
        r.sub = L.Label(r, 10, C.DIM); r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2); r.sub:SetWidth(220)
        r.state = L.Label(r, 11, C.INK); r.state:SetPoint("LEFT", r, "LEFT", 262, 0); r.state:SetWidth(90)
        r.ctx = {}
        for j, c in ipairs(CTX) do
          local b = chip(r, 356 + (j - 1) * 50, c[2], "")
          b.key = c[1]
          -- (while Never is on the piece's own choices wait under it, untouched: a click does nothing then)
          b:SetScript("OnClick", A.Safe(function(btn)
            local id = r.id
            if G.Never(id) then return end
            G.SetShow(id, btn.key, not G.ShowsIn(id, btn.key)); p:Sync()
          end, "biome gear: show it in"))
          r.ctx[j] = b
        end
        -- (Never: the bar's own Never for this piece, as its right-click sets it; a click again shows it again)
        r.never = chip(r, 356 + 4 * 50, "Never", "")
        r.never:SetScript("OnClick", A.Safe(function()
          local id = r.id
          if G.SetNever(id, not G.Never(id)) == false then
            A.Say(A.Bar.NEVER_MAX .. " hidden for good already. Settings, Show them all, makes room.")
          end
          p:Sync()
        end, "biome gear: never"))
        self.rows[i] = r
      end
      r.id = piece.id
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -80 - (i - 1) * 34)
      L.Art(r.icon.icon, L.ItemIcon(piece.id, 134400))
      r.name:SetText(L.ItemName(piece.id, "Item " .. piece.id))
      r.sub:SetText((piece.where == "worn" and "Worn" or "In your bags") .. ", " .. G.ColoredList(piece.biomes))
      -- (the piece's first biome as a bar at its left)
      if not r.side then r.side = r:CreateTexture(nil, "ARTWORK"); r.side:SetPoint("TOPLEFT", r, "TOPLEFT", -6, 0); r.side:SetSize(2, 28) end
      local pc = G.COLOR[piece.biomes[1] or ""] or C.DIM
      r.side:SetColorTexture(pc[1], pc[2], pc[3], 1)
      local works
      for _, k in ipairs(piece.biomes) do if here[k] then works = true end end
      local cd = piece.cdLeft or 0
      local function state(t, c) r.state:SetText(t); r.state:SetTextColor(c[1], c[2], c[3]) end
      if o.note then state(o.note, C.DIM)
      elseif cd > 0 then state(string.format("Cooldown %d:%02d", math.floor(cd / 60), math.floor(cd % 60)), C.WARN)
      elseif works then state("Works here", C.GOOD)
      elseif G.Keeps(piece, here) then state("Can't tell", C.DIM)
      else state("Not here", C.DIM) end
      local never = G.Never(piece.id)
      for j, b in ipairs(r.ctx) do
        local on = not never and G.ShowsIn(piece.id, b.key)
        b:Paint(on, never)
        b.tip = never and "Never is on for this piece: click Never to choose again."
          or on and ("Its swaps show on the bar in " .. CTX[j][3] .. ". Click: not there.")
          or ("Click: show its swaps on the bar in " .. CTX[j][3] .. ".")
      end
      r.never:Paint(never)
      r.never.tip = never and "Its swaps never show on the bar. Click to show them again."
        or "Click: its swaps never show on the bar, wherever you are."
      r:Show()
    end
  end
end

----------------------------------------------------------------------------
-- the frame
----------------------------------------------------------------------------
local TABS = { { "settings", "Settings" }, { "consume", "Consumables" }, { "blessings", "Blessings" }, { "gear", "Biome gear" } }
local function build()
  if frame then return frame end
  frame = CreateFrame("Frame", "CuteAurasWindow", UIParent)
  frame:SetSize(W, H)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  frame.bg = L.Fill(frame, "BACKGROUND", C.PANEL, 0.97); frame.bg:SetAllPoints()
  frame.top = frame:CreateTexture(nil, "BORDER"); frame.top:SetPoint("TOPLEFT"); frame.top:SetPoint("TOPRIGHT"); frame.top:SetHeight(2)
  frame.top:SetColorTexture(C.PINK[1], C.PINK[2], C.PINK[3], 1)
  frame.title = L.Label(frame, 16, C.WHITE); frame.title:SetPoint("TOPLEFT", 14, -12); frame.title:SetText("Cute Auras")
  frame.ver = L.Label(frame, 10, C.DIM); frame.ver:SetPoint("LEFT", frame.title, "RIGHT", 8, -1); frame.ver:SetText(A.version)
  frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  frame.close:SetPoint("TOPRIGHT", -4, -4)
  frame.close:SetScript("OnClick", function() frame:Hide() end)
  for i, t in ipairs(TABS) do
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(104, 24)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", 14 + (i - 1) * 108, -32)
    b.bg = L.Fill(b, "BACKGROUND", C.PANEL2, 1); b.bg:SetAllPoints()
    b.line = b:CreateTexture(nil, "BORDER"); b.line:SetPoint("BOTTOMLEFT"); b.line:SetPoint("BOTTOMRIGHT"); b.line:SetHeight(2)
    b.text = L.Label(b, 12, C.DIM, "CENTER"); b.text:SetPoint("CENTER"); b.text:SetText(t[2])
    b:SetScript("OnClick", A.Safe(function() Wn.Open(t[1]) end, "window: a tab"))
    tabs[t[1]] = b
    pages[t[1]] = panel(frame)
  end
  Wn.pages = pages -- (for /dump)
  settingsPage(pages.settings)
  consumePage(pages.consume)
  blessingsPage(pages.blessings)
  gearPage(pages.gear)
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "CuteAurasWindow") end
  frame:Hide()
  Wn.frame = frame
  return frame
end
function Wn.Refresh()
  if not (frame and frame:IsShown()) then return end
  local p = pages[current]
  if p and p.Sync then A.Safe(function() p:Sync() end, "window: " .. current)() end
end
local openedAt = 0
function Wn.Open(which)
  build()
  openedAt = A.Now()
  current = pages[which or ""] and which or current
  for key, b in pairs(tabs) do
    local on = key == current
    b.line:SetColorTexture(C.PINK[1], C.PINK[2], C.PINK[3], on and 1 or 0)
    local tc = on and C.WHITE or C.DIM
    b.text:SetTextColor(tc[1], tc[2], tc[3])
    pages[key]:SetShown(on)
  end
  frame:Show()
  -- (the Blessings tab opened: the asker asks PallyPower users for their SELF, PallySync.lua)
  if current == "blessings" and A.PallySync then A.PallySync.AskTab() end
  Wn.Refresh()
end
function Wn.Toggle() if frame and frame:IsShown() then frame:Hide() else Wn.Open() end end

----------------------------------------------------------------------------
-- Move: the bar's and the overlay's handles (out of a fight), each a pink box with its name; a second /cauras move,
-- the Done under the alerts' box or Settings' Move (Done while moving) ends it. Both sit near the screen's centre,
-- under where this window opens, so the window steps aside while they move and comes back after
----------------------------------------------------------------------------
local moving, reopen = false, false
function Wn.Moving() return moving end
function Wn.Move(on)
  if A.Fighting() then A.Say("Out of a fight, please.") return end
  moving = on and not moving
  local bar, anchor = A.Bar.Frames(), A.Alerts.Anchor()
  for _, f in ipairs({ bar, anchor }) do
    f:EnableMouse(moving)
    if moving then
      f:RegisterForDrag("LeftButton")
      f:SetScript("OnDragStart", function(self) if not A.Fighting() then self:StartMoving(); self.caMoving = true end end)
      -- (both hold secure buttons, so the stop is a protected call: a drag let go in a fight stops, and its place is
      -- saved, as the fight ends; a release with no drag started stops nothing)
      f:SetScript("OnDragStop", function(self)
        if not self.caMoving then return end
        A.OutOfFight(self == anchor and "move: the alerts" or "move: the bar", function()
          self.caMoving = nil
          self:StopMovingOrSizing()
          if self == anchor then A.Alerts.SavePlace() else A.Bar.SavePlace() end
        end)
      end)
    else
      f:SetScript("OnDragStart", nil); f:SetScript("OnDragStop", nil)
    end
  end
  anchor.box:SetShown(moving); anchor.label:SetShown(moving)
  -- (the overlay's Done, in its box under its name: the way back while the window is away)
  if moving and not anchor.done then
    anchor.done = button(anchor, (260 - 72) / 2, -32, "Done", function() Wn.Move(true) end, 72)
    -- (over any card showing in the box: a test card or a restore card would cover it, and the window is away)
    anchor.done:SetFrameStrata("DIALOG")
    anchor.done:SetFrameLevel((anchor:GetFrameLevel() or 1) + 30)
  end
  if anchor.done then anchor.done:SetShown(moving) end
  if moving then
    reopen = frame and frame:IsShown() or false
    if frame then frame:Hide() end
    if not bar:IsShown() then bar:Show(); bar.movingShown = true end
    if not bar.moveBox then
      bar.moveBox = L.Fill(bar, "BACKGROUND", C.PINK, 0.18); bar.moveBox:SetAllPoints()
      -- (its name over it, as the overlay's box has one: the bar may be a single icon or none)
      bar.moveLabel = L.Text(bar, 12, C.WHITE)
      bar.moveLabel:SetPoint("BOTTOM", bar, "TOP", 0, 4)
      bar.moveLabel:SetText("Cute Auras bar")
    end
    bar.moveBox:Show(); bar.moveLabel:Show()
    A.Say("Drag the pink boxes, then Done (or /cauras move again).")
  else
    if bar.moveBox then bar.moveBox:Hide(); bar.moveLabel:Hide() end
    if bar.movingShown then bar.movingShown = nil; A.Bar.Refresh() end
    if reopen then reopen = false; Wn.Open("settings") end
  end
  Wn.Refresh()
end
-- Settings' Test: the sample cards hang from the overlay's top, under this window, so it steps aside for their 15 s
-- and comes back as they go, unless it was opened again meanwhile. Alerts off: the chat line alone, the window stays
function Wn.Test()
  if not A.Alerts.On() then A.Alerts.Test() return end
  local at = A.Now()
  if frame then frame:Hide() end
  A.Alerts.Test()
  A.After(15.2, function()
    if frame and not frame:IsShown() and not moving and openedAt <= at then Wn.Open("settings") end
  end, "window: after the test")
end
A.Settings_ = { Move = Wn.Move }

----------------------------------------------------------------------------
-- the game's Settings > AddOns: a page with the button that opens this window
----------------------------------------------------------------------------
local function gameSettings()
  if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
  local f = CreateFrame("Frame")
  f.title = L.Label(f, 16, C.WHITE); f.title:SetPoint("TOPLEFT", 16, -16); f.title:SetText("Cute Auras")
  f.note = L.Label(f, 12, C.INK); f.note:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8); f.note:SetText("Its settings, consumables, blessings and biome gear live in its own window (/cauras).")
  button(f, 16, -64, "Open Cute Auras", function() if SettingsPanel and SettingsPanel.Hide then SettingsPanel:Hide() end; Wn.Open("settings") end, 140)
  local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, f, "Cute Auras")
  if ok and cat and Settings.RegisterAddOnCategory then pcall(Settings.RegisterAddOnCategory, cat) end
end

----------------------------------------------------------------------------
-- /cauras diag: what the client answers, for the owner's paste (numbers and words, never a member's name)
----------------------------------------------------------------------------
function A.Diag()
  local secretF = S.AurasSecret()
  local plainIn = {}
  for key, e in pairs(D.BLESS) do if S.AuraPlainInFight(e.ranks[1]) then plainIn[#plainIn + 1] = key end end
  for _, list in pairs(D.BUFFS) do for _, e in ipairs(list) do if e.ranks and S.AuraPlainInFight(e.ranks[1]) then plainIn[#plainIn + 1] = e.key end end end
  A.Say(string.format("%s, group %s, members %d, running Cute Auras %d, duties %d, rebuff slots %d, rebuffs shown %d",
    A.version, tostring(A.Roster.InGroup()), #A.Roster.members, (function() local n = 1; for _ in pairs(A.Comm.peers) do n = n + 1 end return n end)(),
    #A.Assign.duties, A.Rebuff.slots, A.Rebuff.shows))
  A.Say("Auras secret now: " .. tostring(secretF) .. "; plain in a fight: " .. (#plainIn > 0 and table.concat(plainIn, ", ") or "none known"))
  local here = A.Gear.Here()
  local hw = {}
  for k in pairs(here) do hw[#hw + 1] = k end
  A.Say("Biome here: " .. (#hw > 0 and table.concat(hw, ", ") or "none") .. "; biome pieces " .. #A.Gear.Scan() .. "; context " .. A.Gear.Context())
  local kinds, times = A.ErrorCount()
  A.Say(string.format("Comm sent %d, heard %d; bar refreshes %d; errors %d (%d times)", A.Comm.sent, A.Comm.heard, A.Bar.refreshes, kinds, times))
  -- (after the last fight: the refreshes the client refused while it still restricted, and when one went through)
  A.Say(A.Bar.LateLine())
  -- (the consumables: where you stand, your role and where it came from, what is asked and why)
  A.Say(A.Consume.DiagLine())
  -- (PallyPower: on this client or not, who asks, what was heard and taken, what we sent; the O1s refused for a name)
  A.Say(A.PallySync.DiagLine())
  -- (the forms names come in: our own sender as the game echoes it, and UnitName's answers)
  A.Say(A.Roster.NamesLine())
  -- (your target's blessings: kinds and whose, so two paladins' same kind on one target shows)
  A.Say(A.Buffs.TargetBlessLine())
  -- (the bar's grid: how many icons, how wide, the widest verb at the client's own font, the names cut to fit)
  A.Say(A.Bar.DiagLine())
  -- (the alerts: their look, what shows, where the overlay sits on this screen)
  A.Say(A.Alerts.DiagLine())
end

local itemWait = false
function Wn:Init()
  gameSettings()
  -- (an item's data in from the server: its name, icon and kind on the Consumables tab, one refresh a half second)
  A.On("GET_ITEM_INFO_RECEIVED", function()
    if itemWait then return end
    itemWait = true
    A.After(0.5, function() itemWait = false; Wn.Refresh() end, "window: item data")
  end)
  -- (a fight's start and end too: the Consumables tab's In a fight, and its words back after it)
  -- (and your rest: an inn's rest area reaches past its subzone, so In town comes and goes with no zone event)
  for _, ev in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA",
                        "ZONE_CHANGED_INDOORS", "PLAYER_UPDATE_RESTING", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    A.On(ev, function() A.After(0.5, Wn.Refresh, "window") end)
  end
  -- (your auras changed with no other event: Well Fed lands seconds after the food left your bags, or from a feast; and
  -- your weapon's oil or stone on or run out, no aura and no bag change: the inventory's event, as the bar reads it.
  -- The Consumables tab read again, one a half second, after the bar's own read of them)
  local tabWait = false
  local function tabSoon()
    if tabWait or current ~= "consume" or not (frame and frame:IsShown()) then return end
    tabWait = true
    A.After(0.5, function() tabWait = false; Wn.Refresh() end, "window: the Consumables tab")
  end
  A.OnUnit("UNIT_AURA", { "player" }, tabSoon, "window: your auras")
  A.OnUnit("UNIT_INVENTORY_CHANGED", { "player" }, tabSoon, "window: your weapon")
  A.On("WEAPON_ENCHANT_CHANGED", tabSoon, "window: your weapon")
end

-- the game's addon drawer (the minimap's compartment button): the window
function CuteAuras_OnCompartment() Wn.Toggle() end
