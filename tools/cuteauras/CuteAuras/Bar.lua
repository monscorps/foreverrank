-- SPDX-License-Identifier: GPL-3.0-or-later
-- The bar: one row of icons in three parts, left to right: camp (gold), yours (white), the group's (teal); Before the
-- pull joins yours on a ready check. Built from QuestBank's Remind.lua (the hud round): every icon is a provider's
-- record, { key, part, order, groups, read = function(add, ctx) }, read out of a fight on its groups' events, one
-- refresh a frame for a burst.
-- A left-click acts through the game's secure button (type1: an unmodified left click alone); a waiting icon's click
-- shows its why. Right-click: Not now (the part, ten minutes), Never: <it> (undone in Settings), Settings.
-- In a fight: camp and yours hide (the game's state driver), the group's part stays as it was, clickable, its flyout
-- opening on hover through a secure wrap. Nothing is read or laid out in a fight; 1 s after it, one fresh look.
local _, A = ...
local B = A.Part("Bar", { list = {}, byKey = {}, refreshes = 0, layouts = 0 })
local L, S = A.Look, A.Spells
local C = L.C
local plain, call = A.Plain, A.Call
local SIZE, GAP = L.SIZE, L.GAP
local PART_GAP = 14
local PADX, PADT, PADB = 10, 4, 9
local WORD_Y = SIZE + 6
local ROW_H = WORD_Y + 13
local MAX = { camp = 4, mine = 6, pull = 6, group = 6, gear = 3 }
local SNOOZE = 600
local AFTER = 1
B.SIZE, B.MAX, B.SNOOZE = SIZE, MAX, SNOOZE

----------------------------------------------------------------------------
-- providers and records
----------------------------------------------------------------------------
local dirty, pending = {}, false
local flushNow
function B.Add(p)
  assert(type(p) == "table" and type(p.key) == "string" and type(p.read) == "function", "a provider: key and read")
  if B.byKey[p.key] then return B.byKey[p.key] end
  p.recs, p.n, p.order = {}, 0, p.order or 1000
  p.safeRead = A.Safe(p.read, "bar: " .. p.key)
  B.byKey[p.key] = p
  B.list[#B.list + 1] = p
  table.sort(B.list, function(a, b) return a.order < b.order end)
  for _, g in ipairs(p.groups or {}) do dirty[g] = true end
  return p
end
local flushNext = A.Safe(function() pending = false; flushNow() end, "bar")
-- events set their group's bit; the refresh runs on the next frame, once for a burst (the group's at most every 0.5 s)
local groupAt = 0
function B.Dirty(group)
  dirty[group or "all"] = true
  if pending then return end
  pending = true
  local wait = 0
  if group == "group" then wait = math.max(0, 0.5 - (A.Now() - groupAt)) end
  if C_Timer and C_Timer.After then C_Timer.After(wait, flushNext) else pending = false; flushNow() end
end
local reading
local function add()
  local p = reading
  p.n = p.n + 1
  local rec = p.recs[p.n]
  if not rec then rec = {}; p.recs[p.n] = rec end
  for k in pairs(rec) do if k ~= "clickBuf" then rec[k] = nil end end
  rec.p, rec.key, rec.part = p, p.key, p.part
  return rec
end
B.NewRecord = add
-- a record's click: the secure type and what it reads (a spell, an item by id, a macro's text), the unit, and the
-- target slot (a poison or a stone on a weapon: 16 or 17, SecureTemplates.lua's target-slot)
function B.Click(rec, kind, value, unit, slot)
  local c = rec.clickBuf
  if not c then c = {}; rec.clickBuf = c end
  c.type, c.spell, c.item, c.macro, c.unit, c.slot = kind, nil, nil, nil, unit, slot
  if kind == "spell" then c.spell = value elseif kind == "item" then c.item = value else c.macro = value end
  rec.click = c
  return c
end

----------------------------------------------------------------------------
-- what the game says of you, once a refresh
----------------------------------------------------------------------------
local ctx = {}
B.ctx = ctx
local inCinematic = false
local function away()
  return A.Yes(UnitIsDeadOrGhost, "player") or A.Yes(UnitOnTaxi, "player") or A.Yes(UnitInVehicle, "player")
    or A.Yes(UnitHasVehicleUI, "player") or inCinematic
end
local function instanceKind()
  if type(IsInInstance) ~= "function" then return nil end
  local ok, inside, kind = pcall(IsInInstance)
  if not ok or plain(inside) ~= true then return nil end
  return plain(kind) == "raid" and "raid" or "party"
end
B.InstanceKind = instanceKind
-- the client's restrictions as in a fight (C_RestrictedActions, Combat and Encounter)
local function restricted()
  local RA, kinds = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
  if not (RA and type(RA.IsAddOnRestrictionActive) == "function" and kinds) then return false end
  for _, name in ipairs({ "Combat", "Encounter" }) do
    if kinds[name] ~= nil and A.Yes(RA.IsAddOnRestrictionActive, kinds[name]) then return true end
  end
  return false
end
function B.Blocked() return A.Fighting() or restricted() or S.AurasSecret() end

-- your bags: { [item id] = { bag, slot } } of bags 0 to NUM_BAG_SLOTS, scanned again after BAG_UPDATE_DELAYED
local bags, bagsStale = {}, true
local slotPool = {}
function B.Bags()
  if not bagsStale then return bags end
  bagsStale = false
  for k in pairs(bags) do bags[k] = nil end
  local CC = C_Container
  if not (CC and type(CC.GetContainerNumSlots) == "function" and type(CC.GetContainerItemID) == "function") then return bags end
  local used = 0
  for bag = 0, (type(NUM_BAG_SLOTS) == "number" and NUM_BAG_SLOTS or 4) do
    local n = plain(call(CC.GetContainerNumSlots, bag)) or 0
    for slot = 1, math.min(type(n) == "number" and n or 0, 40) do
      local id = plain(call(CC.GetContainerItemID, bag, slot))
      if type(id) == "number" and not bags[id] then
        used = used + 1
        local e = slotPool[used]
        if not e then e = {}; slotPool[used] = e end
        e.bag, e.slot = bag, slot
        bags[id] = e
      end
    end
  end
  return bags
end
function B.BagsChanged() bagsStale = true end

-- standing still 20 s: the pause icons (Light, Sleep); one that showed and that you walk off from unclicked snoozes
local stillAt, still, paused, snoozedSelf = nil, false, {}, {}
function B.Still() return still end
local function stopped()
  stillAt = A.Now()
  local at = stillAt
  A.After(20.05, function() if stillAt == at then still = true; B.Dirty("camp") end end, "bar: still")
end
local function started()
  stillAt, still = nil, false
  for key in pairs(paused) do snoozedSelf[key] = A.Now() + SNOOZE end
  B.Dirty("camp")
end
function B.Snoozed(key)
  local t = snoozedSelf[key]
  if t and A.Now() < t then return true end
  snoozedSelf[key] = nil
  return false
end
function B.Clicked(key) paused[key] = nil end

----------------------------------------------------------------------------
-- the frames: the bar (placed, sized), its two holders (yours and the camp's, hidden in a fight by the game's state
-- driver; the group's, which stays), each icon a secure button
----------------------------------------------------------------------------
local bar, own, grp
local icons = { own = {}, group = {} }
local flyouts = {}
local function scale()
  local v = tonumber(A.Settings().scale)
  if v and v >= 0.5 and v <= 2 then return v end
  return 1
end
local function place()
  if not bar or A.Fighting() then return end
  local k = scale()
  if bar:GetScale() ~= k then bar:SetScale(k) end
  bar:ClearAllPoints()
  local pos = A.Settings().pos
  if type(pos) == "table" and tonumber(pos.x) and tonumber(pos.y) then
    bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x / k, pos.y / k)
  else
    bar:SetPoint("CENTER", UIParent, "CENTER", 0, -170 / k)
  end
end
B.Place = place
local function fightDriver()
  if not (grp and type(RegisterStateDriver) == "function") then return end
  if A.Settings().fight == "hide" then
    pcall(RegisterStateDriver, grp, "visibility", "[combat] hide; show")
  elseif type(UnregisterStateDriver) == "function" then
    pcall(UnregisterStateDriver, grp, "visibility")
  end
end
B.FightDriver = function() A.OutOfFight("bar: fight driver", fightDriver) end
local function frames()
  if bar then return end
  bar = CreateFrame("Frame", "CuteAurasBar", UIParent)
  bar:SetSize(SIZE + PADX * 2, PADT + ROW_H + PADB)
  bar:SetFrameStrata("MEDIUM")
  bar:SetClampedToScreen(true)
  bar:SetMovable(true)
  own = CreateFrame("Frame", "CuteAurasBarOwn", bar)
  own:SetSize(1, ROW_H)
  grp = CreateFrame("Frame", "CuteAurasBarGroup", bar)
  grp:SetSize(1, ROW_H)
  if type(RegisterStateDriver) == "function" then pcall(RegisterStateDriver, own, "visibility", "[combat] hide; show") end
  fightDriver()
  place()
  B.bar, B.own, B.grp = bar, own, grp
end
B.Frames = function() frames(); return bar end

-- Alt-drag moves the bar out of a fight
local function moveStart(self, button)
  if button ~= "LeftButton" or A.Fighting() or not (IsAltKeyDown and IsAltKeyDown()) then return end
  bar:StartMoving(); bar.moving = true
end
local function moveStop()
  if not (bar and bar.moving) then return end
  bar.moving = nil
  if A.Fighting() then bar.stopAfter = true return end
  bar:StopMovingOrSizing()
  B.SavePlace()
end
function B.SavePlace()
  local x, y = bar:GetCenter()
  if not x then return end
  local fs, us = bar:GetEffectiveScale() or 1, UIParent:GetEffectiveScale() or 1
  local k = us > 0 and fs / us or 1
  A.Settings().pos = { x = x * k, y = y * k }
  place()
end

----------------------------------------------------------------------------
-- an icon's click, tooltip and menu
----------------------------------------------------------------------------
local ATTRS = { "spell", "item", "macrotext", "unit", "target-slot" }
local function attr(b, k, v) if b:GetAttribute(k) ~= v then b:SetAttribute(k, v) end end
local function setClick(b, rec)
  local c = rec.click
  local kind = (c and rec.lit) and c.type or nil
  attr(b, "type1", kind)
  for _, k in ipairs(ATTRS) do
    local v
    if kind then
      if k == "spell" then v = c.spell
      elseif k == "item" then v = c.item and ("item:" .. c.item) or nil
      elseif k == "macrotext" then v = c.macro
      elseif k == "unit" then v = c.unit
      elseif k == "target-slot" then v = c.slot end
    end
    attr(b, k, v)
  end
end
B.SetClick = setClick
local function tipLine(s, col, wrap) GameTooltip:AddLine(s, col[1], col[2], col[3], wrap) end
function B.Tip(owner, rec)
  if not rec or not GameTooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_TOP")
  GameTooltip:SetText(rec.name or "", C.WHITE[1], C.WHITE[2], C.WHITE[3])
  if rec.why then tipLine(rec.why, C.INK, true) end
  if rec.p and rec.p.tip then rec.p.tip(GameTooltip, rec) end
  if rec.far then tipLine("Out of range.", C.WARN, true) end
  if rec.clickWord then tipLine("Click: " .. rec.clickWord .. ".", C.INK, true) end
  if rec.flyout then tipLine("Hover for the list; click a name there to buff them.", C.DIM, true) end
  tipLine("Right-click: not now, never, settings.", C.DIM, true)
  GameTooltip:Show()
end
local function onEnter(self) B.Tip(self, self.rec) end
local function onLeave() if GameTooltip and GameTooltip:GetOwner() then GameTooltip:Hide() end end

-- Not now and Never: the parts' own quiet, and the account's list (32 at most)
local partSnooze, snoozedKeys = {}, {}
function B.SnoozePart(part)
  partSnooze[part] = A.Now() + SNOOZE
  local kept = {}
  for _, p in ipairs(B.list) do
    for i = 1, p.n do local rec = p.recs[i]; if rec.part == part then kept[rec.never or rec.key] = true end end
  end
  snoozedKeys[part] = kept
  A.After(SNOOZE + 0.1, function() B.Dirty("all") end, "bar: not now")
  B.Dirty("all")
end
local function partQuiet(rec)
  local untilT = partSnooze[rec.part]
  if not untilT then return false end
  if A.Now() >= untilT then partSnooze[rec.part] = nil return false end
  -- (something new on a quiet part brings it back)
  if not (snoozedKeys[rec.part] or {})[rec.never or rec.key] then partSnooze[rec.part] = nil return false end
  return true
end
function B.Never(key) return A.Settings().never[key] ~= nil end
function B.SetNever(key, name, on)
  local never = A.Settings().never
  if on == false then never[key] = nil
  else
    local n = 0
    for _ in pairs(never) do n = n + 1 end
    if n >= 32 and never[key] == nil then return false end
    never[key] = name or key
  end
  B.Dirty("all")
  return true
end
local function menuFor(b)
  if A.Fighting() then return end
  local rec = b.rec
  if not rec then return end
  local key, name = rec.never or rec.key, rec.neverName or rec.name or rec.key
  local entries = {
    { "Not now", function() B.SnoozePart(rec.part) end },
    { "Never: " .. name, function() B.SetNever(key, name) end },
  }
  if rec.part == "group" then entries[#entries + 1] = { "Blessings and buffers...", function() if A.Window then A.Window.Open("blessings") end end } end
  if rec.part == "gear" then entries[#entries + 1] = { "Biome gear...", function() if A.Window then A.Window.Open("gear") end end } end
  entries[#entries + 1] = { "Settings...", function() if A.Window then A.Window.Open("settings") end end }
  if type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function" then
    MenuUtil.CreateContextMenu(b, function(_, root)
      for _, e in ipairs(entries) do root:CreateButton(e[1], e[2]) end
      -- (a provider's own entries: the biome pieces' "Show it in")
      if rec.p and rec.p.menu then
        if root.CreateDivider then root:CreateDivider() end
        rec.p.menu(root, rec)
      end
    end)
  end
end
B.Menu = menuFor
local lastClick = -10
local function onClick(self, button, down)
  if down then return end
  local rec = self.rec
  if not rec then return end
  if button == "RightButton" then menuFor(self) return end
  if button ~= "LeftButton" or (IsAltKeyDown and IsAltKeyDown()) then return end
  local t = A.Now()
  if t - lastClick < 0.3 then return end
  lastClick = t
  B.Clicked(rec.key)
  if rec.lit and rec.click then
    if rec.p and rec.p.used then rec.p.used(rec) end
    -- (a buff given: the group's part looks again once the aura lands)
    if rec.part == "group" then A.After(0.6, function() B.Dirty("group") end, "bar: after a click") end
    return
  end
  if type(rec.go) == "function" then rec.go(rec) end
end
local function newIcon(name, parent, part)
  local b = L.Icon(name, parent, true, true)
  b.part = part
  if part == "group" then
    -- (a Hand's restore waiting on one of its members: a gold wash, art only, so it shows in a fight too)
    b.glowTex = b:CreateTexture(nil, "OVERLAY")
    b.glowTex:SetAllPoints()
    b.glowTex:SetColorTexture(C.QUEST[1], C.QUEST[2], C.QUEST[3], 0.35)
    b.glowTex:Hide()
  end
  b:SetScript("OnEnter", onEnter)
  b:SetScript("OnLeave", onLeave)
  b:HookScript("OnClick", A.Safe(onClick, "bar: click"))
  b:HookScript("OnMouseDown", moveStart)
  b:HookScript("OnMouseUp", moveStop)
  b:Hide()
  return b
end

----------------------------------------------------------------------------
-- a group icon's flyout: one secure button a member it covers, shown on hover through a secure wrap (so it opens in a
-- fight too), hidden 0.4 s after the mouse leaves both (the game's RegisterAutoHide). Built out of a fight
----------------------------------------------------------------------------
local wrapper
local function header()
  if wrapper then return wrapper end
  wrapper = CreateFrame("Frame", "CuteAurasBarWrap", UIParent, "SecureHandlerBaseTemplate")
  return wrapper
end
local ROW = 22
local function flyoutOf(b)
  local f = flyouts[b]
  if f then return f end
  f = CreateFrame("Frame", b:GetName() .. "Fly", b, "SecureHandlerBaseTemplate")
  f:SetFrameStrata("DIALOG")
  f:SetSize(150, ROW)
  f:SetPoint("BOTTOM", b, "TOP", 0, 6)
  f.bg = L.Fill(f, "BACKGROUND", C.PANEL, 0.92)
  f.bg:SetAllPoints()
  f.rows = {}
  f:Hide()
  flyouts[b] = f
  -- (the icon keeps a handle to its flyout; the wrap runs as the header's, in a fight too)
  if type(SecureHandlerSetFrameRef) == "function" and type(SecureHandlerWrapScript) == "function" then
    SecureHandlerSetFrameRef(b, "fly", f)
    SecureHandlerWrapScript(b, "OnEnter", header(), [[
      local f = self:GetFrameRef("fly")
      if f and self:GetAttribute("hasfly") then f:Show(); f:RegisterAutoHide(0.4); f:AddToAutoHide(self) end
    ]])
  end
  return f
end
local function flyRow(f, i)
  local r = f.rows[i]
  if r then return r end
  r = CreateFrame("Button", f:GetName() .. "R" .. i, f, "SecureActionButtonTemplate")
  r:SetSize(150, ROW)
  r:RegisterForClicks("AnyUp", "AnyDown")
  r.hi = r:CreateTexture(nil, "HIGHLIGHT"); r.hi:SetAllPoints(); r.hi:SetColorTexture(1, 1, 1, 0.1)
  r.glow = r:CreateTexture(nil, "BACKGROUND"); r.glow:SetAllPoints(); r.glow:SetColorTexture(C.QUEST[1], C.QUEST[2], C.QUEST[3], 0.22); r.glow:Hide()
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 4, 0); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = L.Text(r, 11, C.INK, 92, "LEFT"); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.state = L.Text(r, 10, C.DIM, 40, "RIGHT"); r.state:SetPoint("RIGHT", -4, 0)
  r:HookScript("OnClick", function() A.After(0.6, function() B.Dirty("group") end, "bar: flyout click") end)
  f.rows[i] = r
  return r
end
-- the flyout's rows from a record's list: { unit, name, class, spell, has, far, dead, glow } each
local function layFlyout(b, rec)
  local list = rec.flyout
  if not list or #list == 0 then
    attr(b, "hasfly", nil)
    local f = flyouts[b]
    if f and f:IsShown() then f:Hide() end
    return
  end
  local f = flyoutOf(b)
  attr(b, "hasfly", true)
  local n = math.min(#list, 40)
  f:SetSize(150, n * ROW + 4)
  for i = 1, n do
    local e = list[i]
    local r = flyRow(f, i)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -2 - (i - 1) * ROW)
    attr(r, "type1", e.spell and "spell" or nil)
    attr(r, "spell", e.spell)
    attr(r, "unit", e.unit)
    L.Art(r.icon, e.tex or rec.tex)
    r.icon:SetDesaturated(e.has == true)
    r.name:SetText(e.name or "?")
    r.name:SetTextColor(L.ClassColor(e.class))
    local st, col = "", C.DIM
    if e.dead then st, col = "dead", C.BAD elseif e.off then st, col = "offline", C.DIM
    elseif e.far then st, col = "far", C.WARN elseif e.has then st, col = "on", C.GOOD else st, col = "missing", C.QUEST end
    r.state:SetText(st)
    r.state:SetTextColor(col[1], col[2], col[3])
    r.glow:SetShown(e.glow == true)
    r.member = e.guid
    if not r:IsShown() then r:Show() end
  end
  for i = n + 1, #f.rows do if f.rows[i]:IsShown() then f.rows[i]:Hide() end end
end
-- a glow on a member's row (a Hand's restore in a fight: insecure art, allowed there)
function B.GlowMember(guid, on)
  for _, f in pairs(flyouts) do
    for _, r in ipairs(f.rows) do if r.member == guid then r.glow:SetShown(on) end end
  end
  for _, b in pairs(icons.group) do
    if b:IsShown() and b.rec and b.rec.flyout then
      for _, e in ipairs(b.rec.flyout) do if e.guid == guid then e.glow = on end end
      if b.glowTex then b.glowTex:SetShown(on or false) end
    end
  end
end

----------------------------------------------------------------------------
-- the refresh: the dirty groups' providers read, the bar laid out (out of a fight only)
----------------------------------------------------------------------------
local shown = { camp = {}, mine = {}, pull = {}, group = {}, gear = {} }
B.shown = shown
local set
local after = { waiting = false, gen = 0 }
local function offPart(p)
  local s = set
  if s.on == false then return true end
  local part = p.part
  if part == "camp" and s.camp == false then return true end
  if part == "mine" and s.mine == false then return true end
  if part == "group" and s.group == false then return true end
  if part == "pull" and s.pull == false then return true end
  return false
end
local function allowed(rec)
  local key = rec.never or rec.key
  if set.never[key] ~= nil then return false end
  if B.Snoozed(rec.key) then return false end
  return true
end
local function readAll()
  ctx.t = A.Now()
  ctx.town = A.Yes(IsResting)
  ctx.inst = instanceKind()
  ctx.group = A.Roster.InGroup()
  ctx.raid = A.Roster.InRaid()
  ctx.level = plain(call(UnitLevel, "player")) or 1
  ctx.still = still
  ctx.pull = B.PullOn()
  local any = dirty.all
  for _, p in ipairs(B.list) do
    local want = any
    if not want then for _, g in ipairs(p.groups or {}) do if dirty[g] then want = true break end end end
    if p.timed and B.clockOn then want = true end
    if want then
      p.n = 0
      if not offPart(p) then
        reading = p
        p.safeRead(add, ctx)
        reading = nil
      end
    end
  end
  for k in pairs(dirty) do dirty[k] = nil end
end
local function collect()
  for _, l in pairs(shown) do for i = #l, 1, -1 do l[i] = nil end end
  local inst, mode = ctx.inst, set.instance
  if inst and mode == "none" then return end
  for _, p in ipairs(B.list) do
    for i = 1, p.n do
      local rec = p.recs[i]
      if allowed(rec) and not partQuiet(rec) then
        local part = rec.part or "mine"
        -- (in a dungeon or raid, "buffs": no camp)
        if not (inst and mode ~= "all" and part == "camp") then
          local l = shown[part]
          if l and #l < MAX[part] then l[#l + 1] = rec end
        end
      end
    end
  end
  for k in pairs(paused) do paused[k] = nil end
  for _, rec in ipairs(shown.camp) do if rec.pause then paused[rec.key] = true end end
  if ctx.pull and #shown.pull == 0 then B.PullEnd() end
end
local usedBuf = {}
local function layPart(container, list, which, startX)
  local used = usedBuf
  for k in pairs(used) do used[k] = nil end
  local x = startX
  for _, rec in ipairs(list) do
    local key = rec.key
    used[key] = true
    local b = icons[which][key]
    if not b then b = newIcon("CuteAuras" .. (which == "group" and "Group_" or "Bar_") .. key:gsub("[^%w]", "_"), container, which); icons[which][key] = b end
    L.Paint(b, rec)
    setClick(b, rec)
    if which == "group" then layFlyout(b, rec) end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", container, "TOPLEFT", x, 0)
    if not b:IsShown() then b:Show() end
    x = x + SIZE + GAP
  end
  for key, b in pairs(icons[which]) do
    if not used[key] and b:IsShown() then b:Hide(); b.rec = nil; if flyouts[b] then flyouts[b]:Hide() end end
  end
  return x
end
local ownList = {}
local function layout()
  for i = #ownList, 1, -1 do ownList[i] = nil end
  for _, part in ipairs({ "camp", "mine", "pull", "gear" }) do
    for _, rec in ipairs(shown[part]) do ownList[#ownList + 1] = rec end
  end
  local nOwn, nGrp = #ownList, #shown.group
  local wOwn = nOwn > 0 and (nOwn * SIZE + (nOwn - 1) * GAP) or 0
  local wGrp = nGrp > 0 and (nGrp * SIZE + (nGrp - 1) * GAP) or 0
  local gap = (nOwn > 0 and nGrp > 0) and PART_GAP or 0
  local w = PADX * 2 + math.max(SIZE, wOwn + gap + wGrp)
  bar:SetSize(w, PADT + ROW_H + PADB)
  own:ClearAllPoints(); own:SetPoint("TOPLEFT", bar, "TOPLEFT", PADX, -PADT); own:SetSize(math.max(1, wOwn), ROW_H)
  grp:ClearAllPoints(); grp:SetPoint("TOPLEFT", bar, "TOPLEFT", PADX + wOwn + gap, -PADT); grp:SetSize(math.max(1, wGrp), ROW_H)
  layPart(own, ownList, "own", 0)
  layPart(grp, shown.group, "group", 0)
  local any = nOwn + nGrp > 0
  if any and not bar:IsShown() then bar:Show() elseif not any and bar:IsShown() then bar:Hide() end
end
local function hideAll() if bar and bar:IsShown() then bar:Hide() end end

-- the clock: once a second while a word changes with time (a countdown, a range), a fresh look of the timed providers
local clock
local function wantClock()
  for _, l in pairs(shown) do for _, rec in ipairs(l) do if rec.timed then return true end end end
  return #shown.group > 0
end
local tickAt = 0
local function onClock(self, dt)
  tickAt = tickAt + (dt or 0)
  if tickAt < 1 then return end
  tickAt = 0
  if not B.clockOn then self:SetScript("OnUpdate", nil); self.running = false return end
  dirty.timed = true
  B.Dirty("timed")
end
local function runClock()
  if not clock then clock = CreateFrame("Frame"); B.clock = clock end
  if clock.running then return end
  clock.running = true
  clock:SetScript("OnUpdate", A.Safe(onClock, "bar: clock"))
end

function flushNow()
  if A.Fighting() then after.waiting = true return end
  if after.waiting and after.gen > 0 then return end
  if restricted() or S.AurasSecret() then after.waiting = true return end
  set = A.Settings()
  if dirty.group then groupAt = A.Now() end
  B.refreshes = B.refreshes + 1
  readAll()
  collect()
  frames()
  if set.on == false or away() then hideAll() else layout() end
  B.layouts = B.layouts + 1
  B.clockOn = wantClock()
  if B.clockOn then runClock() end
  if A.Gear and #shown.gear > 0 then A.After(0.2, A.Gear.Auto, "bar: swap for me") end
  set = nil
end
function B.Refresh()
  dirty.all = true
  bagsStale = true
  pending = false
  flushNow()
end
function B.Shown(part) return shown[part] end

-- a fight: the state driver hides yours, the group's stays; after it, 1 s, then a fresh look
local function fightOver()
  if bar and bar.stopAfter then bar.stopAfter = nil; bar:StopMovingOrSizing(); place() end
  after.gen = after.gen + 1
  local gen = after.gen
  after.waiting = true
  A.After(AFTER, function()
    if gen ~= after.gen or A.Fighting() then return end
    after.gen, after.waiting = 0, false
    B.Refresh()
  end, "bar: after the fight")
end

----------------------------------------------------------------------------
-- Before the pull: a ready check (or entering a raid), 3 s on, out of a fight; ends 10 s after READY_CHECK_FINISHED,
-- 60 s after the entry, when nothing is left, or at the first fight
----------------------------------------------------------------------------
local pull = { untilT = nil, gen = 0 }
function B.PullOn()
  if not pull.untilT then return false end
  if A.Now() >= pull.untilT then pull.untilT = nil return false end
  return true
end
function B.StartPull(seconds, delay)
  pull.gen = pull.gen + 1
  local gen = pull.gen
  A.After(delay or 0, function()
    if gen ~= pull.gen then return end
    pull.untilT = A.Now() + seconds
    B.Dirty("pull")
    A.After(seconds + 0.1, function() if gen == pull.gen then B.Dirty("pull") end end, "bar: pull")
  end, "bar: pull")
end
function B.PullEnd(delay)
  if not pull.untilT then return end
  if delay then pull.untilT = math.min(pull.untilT, A.Now() + delay)
  else pull.untilT = nil end
  B.Dirty("pull")
end

----------------------------------------------------------------------------
-- events, by group (a payload that can be secret is never read)
----------------------------------------------------------------------------
local EVENTS = {
  UNIT_INVENTORY_CHANGED = "mine", BAG_UPDATE_DELAYED = "all", BAG_UPDATE_COOLDOWN = "camp", PLAYER_UPDATE_RESTING = "camp",
  ZONE_CHANGED_NEW_AREA = "all", PLAYER_LEVEL_UP = "all", SPELLS_CHANGED = "all", LEARNED_SPELL_IN_TAB = "all",
  SKILL_LINES_CHANGED = "camp", PLAYER_MOUNT_DISPLAY_CHANGED = "camp", PLAYER_ALIVE = "all", PLAYER_UNGHOST = "all",
  PLAYER_DEAD = "all", GROUP_ROSTER_UPDATE = "group", UNIT_FLAGS = "group", UNIT_CONNECTION = "group",
  PLAYER_SOFT_INTERACT_CHANGED = "camp", UPDATE_SHAPESHIFT_FORM = "mine",
}
function B:Init()
  frames()
  for ev, g in pairs(EVENTS) do
    A.On(ev, function()
      if ev == "BAG_UPDATE_DELAYED" then bagsStale = true end
      if ev == "PLAYER_LEVEL_UP" or ev == "SKILL_LINES_CHANGED" or ev == "LEARNED_SPELL_IN_TAB" then S.ForgetUsable() end
      B.Dirty(g)
    end)
  end
  -- (your auras: the camp's and yours; a group member's: the group's)
  A.On("UNIT_AURA", function(_, unit)
    unit = plain(unit)
    if unit == "player" then dirty.camp = true; B.Dirty("mine")
    elseif type(unit) == "string" and (unit:find("^party%d") or unit:find("^raid%d")) then B.Dirty("group") end
  end)
  A.On("PLAYER_STARTED_MOVING", started)
  A.On("PLAYER_STOPPED_MOVING", stopped)
  A.On("PLAYER_REGEN_DISABLED", function() after.gen = after.gen + 1; after.waiting = true; pull.untilT = nil end)
  A.On("PLAYER_REGEN_ENABLED", fightOver)
  A.On("READY_CHECK", function() B.StartPull(45, 3) end)
  A.On("READY_CHECK_FINISHED", function() B.PullEnd(10) end)
  A.On("CINEMATIC_START", function() inCinematic = true; B.Dirty("all") end)
  A.On("CINEMATIC_STOP", function() inCinematic = false; B.Dirty("all") end)
  A.On("PLAYER_ENTERING_WORLD", function()
    local inst = instanceKind()
    if inst == "raid" then B.StartPull(60, 5) end
    B.Dirty("all")
  end)
  B.Dirty("all")
end
