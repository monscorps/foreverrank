-- SPDX-License-Identifier: GPL-3.0-or-later
-- The window (/cauras): three tabs in Cute's look.
--   Settings     the bar, the alerts, the group, the camp; Move and Test
--   Blessings    the grid: each class and role in the group down the side, each paladin running Cute Auras across the
--                top, the blessing each gives; a click on your own column (any column for the leader or an assist)
--                changes it, a right-click puts back Cute Auras' choice. Under it: who gives the other buffs
--   Biome gear   where you stand and its biomes, your biome pieces (worn and in your bags) with their cooldowns and
--                whether they work here, and where each one's swaps show: Solo, PvP, 5-man, Raid
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
-- widgets: a check (the whole row clicks), a choice (a row of options), a button
----------------------------------------------------------------------------
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
  b:SetScript("OnClick", function(self) set(not get()); self:Sync() end)
  b:Sync()
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
    b:SetScript("OnClick", function() set(o[1]); f:Sync() end)
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

----------------------------------------------------------------------------
-- Settings
----------------------------------------------------------------------------
local function settingsPage(p)
  local s = function() return A.Settings() end
  local function bar() A.Bar.Dirty("all") end
  local function flag(key, after) return function() return s()[key] ~= false end, function(v) s()[key] = v; if after then after() end; bar() end end
  local x1, x2 = 0, 312
  head(p, x1, 0, "The bar")
  local g, st = flag("on"); check(p, x1, -22, "Show the bar", g, st)
  g, st = flag("camp"); check(p, x1, -44, "Camp, food and sleeping bag", g, st)
  g, st = flag("mine"); check(p, x1, -66, "Your buffs and weapon", g, st)
  g, st = flag("group"); check(p, x1, -88, "Buffs you give the group", g, st)
  g, st = flag("pull"); check(p, x1, -110, "Before the pull (ready check)", g, st)
  choice(p, x1, -136, "In dungeons and raids", { { "buffs", "Buffs only" }, { "all", "Everything" }, { "none", "Nothing" } },
    function() return s().instance end, function(v) s().instance = v; bar() end)
  choice(p, x1, -178, "In a fight", { { "group", "Keep the group's" }, { "hide", "Hide the bar" } },
    function() return s().fight end, function(v) s().fight = v; A.Bar.FightDriver() end)
  choice(p, x1, -220, "Size", { { 0.75, "75%" }, { 1, "100%" }, { 1.25, "125%" }, { 1.5, "150%" } },
    function() return s().scale end, function(v) s().scale = v; A.OutOfFight("bar: place", A.Bar.Place) end)
  choice(p, x1, -262, "Potions, elixirs, flasks and Well Fed", { { "always", "Always" }, { "instance", "Instances" }, { "pull", "Ready check" }, { "off", "Off" } },
    function() return s().consume end, function(v) s().consume = v; bar() end)
  head(p, x1, -312, "Camp")
  g, st = flag("features"); check(p, x1, -334, "Camp items at the fire near you", g, st)
  g, st = flag("blueprints"); check(p, x1, -356, "Blueprints you can use", g, st, "Never one for a profession, level, class or race you don't have.")

  head(p, x2, 0, "Alerts")
  g, st = flag("alerts"); check(p, x2, -22, "Alerts on screen", g, st)
  g, st = flag("rebuff", function() A.Rebuff.Update() end); check(p, x2, -44, "Buff again after a resurrection", g, st, "In a fight too; only the buffer who owes it.")
  g, st = flag("hands"); check(p, x2, -78, "Protection, Freedom and Sacrifice", g, st, "A countdown, then the blessing they lost.")
  g, st = flag("sound"); check(p, x2, -112, "Sound", g, st)
  choice(p, x2, -136, "Card size", { { "small", "Small" }, { "normal", "Normal" }, { "big", "Big" } },
    function() return s().alertSize end, function(v) s().alertSize = v; A.Alerts.Restyle() end)
  choice(p, x2, -178, "Scale", { { 0.75, "75%" }, { 1, "100%" }, { 1.25, "125%" }, { 1.5, "150%" } },
    function() return s().alertScale end, function(v) s().alertScale = v; A.OutOfFight("alerts: place", A.Alerts.Place) end)
  button(p, x2, -222, "Move", function() Wn.Move(true) end)
  button(p, x2 + 98, -222, "Test", function() A.Alerts.Test() end)
  head(p, x2, -262, "Group")
  choice(p, x2, -284, "Your role", { { "auto", "Auto" }, { "tank", "Tank" }, { "healer", "Heal" }, { "melee", "Melee" }, { "ranged", "Ranged" }, { "caster", "Caster" } },
    function() return s().role end, function(v) s().role = v; A.Roster.Changed(); A.Comm.HelloSoon(1) end)
  g, st = flag("blessings", function() A.Comm.HelloSoon(1); A.Assign.Changed() end); check(p, x2, -328, "Blessings shared out by Cute Auras", g, st)
  g, st = flag("greater"); check(p, x2, -350, "Greater blessings with Symbol of Kings", g, st)
  check(p, x2, -372, "Shadow Protection (priests)", function() return s().opt.shadow == true end,
    function(v) s().opt.shadow = v or nil; A.Comm.HelloSoon(1); A.Assign.Changed() end)
  -- (the Nevers: how many, and all shown again)
  p.nevers = L.Label(p, 11, C.DIM)
  p.nevers:SetPoint("TOPLEFT", p, "TOPLEFT", x1, -400)
  p.show = button(p, x1, -418, "Show them all", function() for k in pairs(A.Settings().never) do A.Settings().never[k] = nil end; A.Bar.Dirty("all"); Wn.Refresh() end, 120)
  function p:Sync()
    local n = 0
    for _ in pairs(A.Settings().never) do n = n + 1 end
    self.nevers:SetText(n == 0 and "Nothing hidden for good." or (n .. " hidden for good (right-click, Never)."))
    self.show:SetShown(n > 0)
  end
end

----------------------------------------------------------------------------
-- Blessings
----------------------------------------------------------------------------
local ROLE_WORD = { tank = "Tank", healer = "Healer", melee = "Melee", ranged = "Ranged", caster = "Caster" }
local CYCLE = { "kings", "might", "wisdom" }
local function blessingsPage(p)
  p.title = L.Label(p, 12, C.INK); p.title:SetPoint("TOPLEFT", 0, 0)
  p.cells, p.rows, p.cols, p.lines = {}, {}, {}, {}
  function p:Sync()
    local As = A.Assign
    for _, t in ipairs(self.cells) do t:Hide() end
    for _, t in ipairs(self.rows) do t:Hide() end
    for _, t in ipairs(self.cols) do t:Hide() end
    for _, t in ipairs(self.lines) do t:Hide() end
    local pals, buckets = As.paladins or {}, As.bucketList or {}
    if not A.Roster.InGroup() then
      self.title:SetText("Join a group: the paladins running Cute Auras share the blessings out, one kind each.")
    elseif #pals == 0 then
      self.title:SetText("No paladin in the group runs Cute Auras yet.")
    else
      self.title:SetText("Click your column to change a blessing; right-click for Cute Auras' choice.")
    end
    local me = A.MyGUID()
    for j, pal in ipairs(pals) do
      local c = self.cols[j]
      if not c then c = L.Label(self, 11, C.WHITE, "CENTER"); c:SetWidth(84); self.cols[j] = c end
      c:ClearAllPoints(); c:SetPoint("TOPLEFT", self, "TOPLEFT", 150 + (j - 1) * 88, -26)
      c:SetText(pal.me and "You" or pal.name); c:SetTextColor(L.ClassColor("PALADIN")); c:Show()
    end
    local y = -46
    local n = 0
    for i, b in ipairs(buckets) do
      if i > 12 then break end
      local r = self.rows[i]
      if not r then r = L.Label(self, 11, C.INK); r:SetWidth(144); self.rows[i] = r end
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", self, "TOPLEFT", 0, y - 6)
      local cls = b.class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[b.class] or b.class) or "?"
      r:SetText(cls .. ", " .. (ROLE_WORD[b.role] or b.role or "") .. " (" .. #b .. ")")
      r:SetTextColor(L.ClassColor(b.class)); r:Show()
      for j, pal in ipairs(pals) do
        n = n + 1
        local cell = self.cells[n]
        if not cell then
          cell = L.Icon(nil, self, false, false, 24)
          cell:RegisterForClicks("AnyUp", "RightButtonUp")
          cell:SetScript("OnClick", function(btn, mouse)
            local pg, bk = btn.pal, btn.bucket
            if not (pg and bk) or not As.MayChange(me, pg) then return end
            if mouse == "RightButton" then As.Set(pg, bk, nil) return end
            local cur = As.BlessingOf(pg, bk)
            local idx = 0
            for k, key in ipairs(CYCLE) do if key == cur then idx = k end end
            As.Set(pg, bk, CYCLE[(idx % #CYCLE) + 1])
          end)
          cell:SetScript("OnEnter", function(btn)
            if not GameTooltip then return end
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            local key = As.BlessingOf(btn.pal, btn.bucket)
            GameTooltip:SetText(key and D.BLESS[key].name or "No blessing", C.WHITE[1], C.WHITE[2], C.WHITE[3])
            local ov = As.overrides[btn.pal] and As.overrides[btn.pal][btn.bucket]
            GameTooltip:AddLine(ov and "Set by hand." or "Cute Auras' choice.", C.DIM[1], C.DIM[2], C.DIM[3])
            if not As.MayChange(me, btn.pal) then GameTooltip:AddLine("Only that paladin, the leader or an assist can change it.", C.DIM[1], C.DIM[2], C.DIM[3], true) end
            GameTooltip:Show()
          end)
          cell:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
          self.cells[n] = cell
        end
        cell.pal, cell.bucket = pal.guid, b.key
        local key = As.BlessingOf(pal.guid, b.key)
        L.Art(cell.icon, key and L.SpellIcon(D.BLESS[key].ranks[1], D.BLESS[key].icon) or 134400)
        cell.icon:SetDesaturated(key == nil)
        cell.icon:SetAlpha(key and 1 or 0.3)
        cell:ClearAllPoints(); cell:SetPoint("TOPLEFT", self, "TOPLEFT", 180 + (j - 1) * 88, y)
        cell:Show()
      end
      y = y - 28
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
    local mine = {}
    for _, d in ipairs(As.duties or {}) do
      if not d.bless then mine[#mine + 1] = L.SpellName(d.entry.ranks[1], d.entry.name) .. " to " .. #d.targets end
    end
    if #mine > 0 then say("Yours: " .. table.concat(mine, ", ") .. ".") end
    local without = {}
    for _, m in ipairs(A.Roster.members) do if not A.Comm.Running(m.guid) then without[#without + 1] = m.name end end
    if #without > 0 then say("Without Cute Auras (never given a share): " .. table.concat(without, ", ") .. ".", C.DIM) end
  end
end

----------------------------------------------------------------------------
-- Biome gear
----------------------------------------------------------------------------
local function gearPage(p)
  local G = A.Gear
  p.here = L.Label(p, 12, C.WHITE); p.here:SetPoint("TOPLEFT", 0, 0); p.here:SetWidth(600)
  check(p, 0, -22, "Biome gear on the bar", function() return G.Settings().on ~= false end, function(v) G.Settings().on = v; A.Bar.Dirty("gear") end)
  check(p, 300, -22, "Swap for me (out of a fight)", function() return G.Settings().auto == true end, function(v) G.Settings().auto = v or nil; A.Bar.Dirty("gear") end)
  p.defaults = L.Label(p, 11, C.DIM); p.defaults:SetPoint("TOPLEFT", 0, -50); p.defaults:SetText("New pieces show in:")
  local CTX = { { "solo", "Solo" }, { "pvp", "PvP" }, { "dungeon", "5-man" }, { "raid", "Raid" } }
  for i, c in ipairs(CTX) do
    check(p, 120 + (i - 1) * 80, -46, c[2], function() return G.Settings().show[c[1]] ~= false end,
      function(v) G.Settings().show[c[1]] = v; A.Bar.Dirty("gear"); p:Sync() end).note = nil
  end
  p.rows = {}
  p.empty = L.Label(p, 11, C.DIM); p.empty:SetPoint("TOPLEFT", 0, -84); p.empty:SetWidth(600)
  p.empty:SetText("No biome pieces on you or in your bags yet. Pieces whose effect is stronger in a biome show here as you find them.")
  function p:Sync()
    local here = G.Here()
    local words, at = {}, nil
    for key, place in pairs(here) do words[#words + 1] = G.BIOME[key] and G.BIOME[key].name or key; at = at or place end
    table.sort(words)
    self.here:SetText(#words > 0 and ("Here: " .. table.concat(words, ", ") .. (at and at ~= "water" and (" (" .. at .. ")") or "")) or "No biome here.")
    local pieces = G.Scan()
    self.empty:SetShown(#pieces == 0)
    for _, r in ipairs(self.rows) do r:Hide() end
    for i, piece in ipairs(pieces) do
      if i > 9 then break end
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
          local b = CreateFrame("Button", nil, r)
          b:SetSize(48, 18); b:SetPoint("LEFT", r, "LEFT", 356 + (j - 1) * 50, 0)
          b.bg = L.Fill(b, "BACKGROUND", C.PANEL2, 1); b.bg:SetAllPoints()
          b.text = L.Label(b, 10, C.DIM, "CENTER"); b.text:SetPoint("CENTER"); b.text:SetText(c[2])
          b.key = c[1]
          b:SetScript("OnClick", function(btn) local id = r.id; G.SetShow(id, btn.key, not G.ShowsIn(id, btn.key)); p:Sync() end)
          r.ctx[j] = b
        end
        self.rows[i] = r
      end
      r.id = piece.id
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -80 - (i - 1) * 34)
      L.Art(r.icon.icon, L.ItemIcon(piece.id, 134400))
      r.name:SetText(L.ItemName(piece.id, "Item " .. piece.id))
      local bw = {}
      for _, k in ipairs(piece.biomes) do bw[#bw + 1] = G.BIOME[k] and G.BIOME[k].name or k end
      r.sub:SetText((piece.where == "worn" and "Worn" or "In your bags") .. ", " .. table.concat(bw, ", "))
      local works
      for _, k in ipairs(piece.biomes) do if here[k] then works = true end end
      local cd = piece.cdLeft or 0
      if cd > 0 then r.state:SetText(string.format("Cooldown %d:%02d", math.floor(cd / 60), math.floor(cd % 60))); r.state:SetTextColor(C.WARN[1], C.WARN[2], C.WARN[3])
      elseif works then r.state:SetText("Works here"); r.state:SetTextColor(C.GOOD[1], C.GOOD[2], C.GOOD[3])
      else r.state:SetText("Not here"); r.state:SetTextColor(C.DIM[1], C.DIM[2], C.DIM[3]) end
      for _, b in ipairs(r.ctx) do
        local on = G.ShowsIn(piece.id, b.key)
        b.bg:SetColorTexture(on and C.PINK[1] * 0.75 or C.PANEL2[1], on and C.PINK[2] * 0.6 or C.PANEL2[2], on and C.PINK[3] * 0.65 or C.PANEL2[3], 1)
        local tc = on and C.WHITE or C.DIM
        b.text:SetTextColor(tc[1], tc[2], tc[3])
      end
      r:Show()
    end
  end
end

----------------------------------------------------------------------------
-- the frame
----------------------------------------------------------------------------
local TABS = { { "settings", "Settings" }, { "blessings", "Blessings" }, { "gear", "Biome gear" } }
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
    b:SetScript("OnClick", function() Wn.Open(t[1]) end)
    tabs[t[1]] = b
    pages[t[1]] = panel(frame)
  end
  settingsPage(pages.settings)
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
function Wn.Open(which)
  build()
  current = pages[which or ""] and which or current
  for key, b in pairs(tabs) do
    local on = key == current
    b.line:SetColorTexture(C.PINK[1], C.PINK[2], C.PINK[3], on and 1 or 0)
    local tc = on and C.WHITE or C.DIM
    b.text:SetTextColor(tc[1], tc[2], tc[3])
    pages[key]:SetShown(on)
  end
  frame:Show()
  Wn.Refresh()
end
function Wn.Toggle() if frame and frame:IsShown() then frame:Hide() else Wn.Open() end end

----------------------------------------------------------------------------
-- Move: the bar's and the overlay's handles (out of a fight); a second /cauras move or Done ends it
----------------------------------------------------------------------------
local moving = false
function Wn.Move(on)
  if A.Fighting() then A.Say("Out of a fight, please.") return end
  moving = on and not moving
  local bar, anchor = A.Bar.Frames(), A.Alerts.Anchor()
  for _, f in ipairs({ bar, anchor }) do
    f:EnableMouse(moving)
    if moving then
      f:RegisterForDrag("LeftButton")
      f:SetScript("OnDragStart", function(self) if not A.Fighting() then self:StartMoving() end end)
      f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if self == anchor then A.Alerts.SavePlace() else A.Bar.SavePlace() end
      end)
    else
      f:SetScript("OnDragStart", nil); f:SetScript("OnDragStop", nil)
    end
  end
  anchor.box:SetShown(moving); anchor.label:SetShown(moving)
  if moving then
    if not bar:IsShown() then bar:Show(); bar.movingShown = true end
    if not bar.moveBox then bar.moveBox = L.Fill(bar, "BACKGROUND", C.PINK, 0.18); bar.moveBox:SetAllPoints() end
    bar.moveBox:Show()
    A.Say("Drag the pink boxes. /cauras move again when done.")
  else
    if bar.moveBox then bar.moveBox:Hide() end
    if bar.movingShown then bar.movingShown = nil; A.Bar.Refresh() end
  end
end
A.Settings_ = { Move = Wn.Move }

----------------------------------------------------------------------------
-- the game's Settings > AddOns: a page with the button that opens this window
----------------------------------------------------------------------------
local function gameSettings()
  if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
  local f = CreateFrame("Frame")
  f.title = L.Label(f, 16, C.WHITE); f.title:SetPoint("TOPLEFT", 16, -16); f.title:SetText("Cute Auras")
  f.note = L.Label(f, 12, C.INK); f.note:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8); f.note:SetText("Its settings, blessings and biome gear live in its own window (/cauras).")
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
  A.Say(string.format("%s, group %s, members %d, running Cute Auras %d, duties %d, rebuff slots %d, cards %d",
    A.version, tostring(A.Roster.InGroup()), #A.Roster.members, (function() local n = 1; for _ in pairs(A.Comm.peers) do n = n + 1 end return n end)(),
    #A.Assign.duties, A.Rebuff.slots, A.Rebuff.shows))
  A.Say("Auras secret now: " .. tostring(secretF) .. "; plain in a fight: " .. (#plainIn > 0 and table.concat(plainIn, ", ") or "none known"))
  local here = A.Gear.Here()
  local hw = {}
  for k in pairs(here) do hw[#hw + 1] = k end
  A.Say("Biome here: " .. (#hw > 0 and table.concat(hw, ", ") or "none") .. "; biome pieces " .. #A.Gear.Scan() .. "; context " .. A.Gear.Context())
  A.Say(string.format("Comm sent %d, heard %d; bar refreshes %d; errors %d", A.Comm.sent, A.Comm.heard, A.Bar.refreshes, #A.errors))
end

function Wn:Init()
  gameSettings()
  for _, ev in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA" }) do
    A.On(ev, function() A.After(0.5, Wn.Refresh, "window") end)
  end
end

-- the game's addon drawer (the minimap's compartment button): the window
function CuteAuras_OnCompartment() Wn.Toggle() end
