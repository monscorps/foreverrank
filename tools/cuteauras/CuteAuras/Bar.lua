-- SPDX-License-Identifier: GPL-3.0-or-later
-- The bar: one row of icons in three parts, left to right: camp (gold), yours (white), the group's (teal); Before the
-- pull joins yours on a ready check. Built from QuestBank's Remind.lua (the hud round): every icon is a provider's
-- record, { key, part, order, groups, read = function(add, ctx) }, read out of a fight on its groups' events, one
-- refresh a frame for a burst (off = function(), when its part is switched off instead; quiet = true, see Not now).
-- A left-click acts through the game's secure button (type1: an unmodified left click alone); a waiting icon's click
-- shows its why. Right-click: Not now (the part, ten minutes), Never: <it> (undone in Settings), Settings.
-- In a fight: camp and yours hide (the game's state driver), the group's part stays as it was, clickable, its flyout
-- opening on hover through a secure wrap. Nothing is read or laid out in a fight; 1 s after it, one fresh look. A look
-- the client refuses (it still restricts, or keeps auras secret) is tried again as a restriction lifts
-- (ADDON_RESTRICTION_STATE_CHANGED), else every second. Meanwhile your casts mark what they covered, art only
-- (B.Repaint, Buffs.lua's marks), until the next look.
local _, A = ...
local B = A.Part("Bar", { list = {}, byKey = {}, refreshes = 0, layouts = 0 })
local L, S = A.Look, A.Spells
local C = L.C
local plain, call = A.Plain, A.Call
-- (one fixed grid: every icon takes COL, 36 px, its word cut to fit (Look.lua's L.Paint), so the bar's width follows
-- its icon count alone and never shifts as a name changes; 8 px between yours and the group's, 4 px of padding)
local SIZE, GAP, COL = L.SIZE, L.GAP, L.COL
local PART_GAP = 8
local PADX, PADT, PADB = 4, 4, 9
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
  if type(p.off) == "function" then p.safeOff = A.Safe(p.off, "bar: " .. p.key .. " off") end
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
B.Away = away -- (Swap for me does nothing while the bar is away: Gear.lua)
local function instanceKind()
  if type(IsInInstance) ~= "function" then return nil end
  local ok, inside, kind = pcall(IsInInstance)
  if not ok or plain(inside) ~= true then return nil end
  return plain(kind) == "raid" and "raid" or "party"
end
B.InstanceKind = instanceKind
-- the client's restrictions as in a fight (C_RestrictedActions, Combat and Encounter): the first active one's name,
-- else false
local RESTRICTIONS = { "Combat", "Encounter" }
local function restricted()
  local RA, kinds = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
  if not (RA and type(RA.IsAddOnRestrictionActive) == "function" and kinds) then return false end
  for _, name in ipairs(RESTRICTIONS) do
    if kinds[name] ~= nil and A.Yes(RA.IsAddOnRestrictionActive, kinds[name]) then return name end
  end
  return false
end
-- why the bar can't read now, out of a fight: a restriction's name or "auras secret"; nil when it can
local function refusedBy()
  return restricted() or (S.AurasSecret() and "auras secret") or nil
end
function B.Blocked() return A.Fighting() or refusedBy() ~= nil end

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
-- how long each of your records has been on screen this session (B.ShownFor): the seconds each record laid out lit in
-- yours spent while that part was visible (never in a fight, where the game's driver hides it, nor while the bar is
-- away or off; never greyed, a potion waiting on the shared cooldown, which no click could use). No frame ticks for
-- it: each record's time on screen opens at a layout or as the part shows, and closes as it hides, greys or leaves.
-- The consumables' quiet counts this, not the clock on the wall
local shownFor, seenSince, laidOwn = {}, {}, {}
function B.ShownFor(key)
  local v = shownFor[key] or 0
  local at = seenSince[key]
  if at then v = v + math.max(0, A.Now() - at) end
  return v
end
local function seenUpdate()
  local t = A.Now()
  for key, at in pairs(seenSince) do
    shownFor[key] = (shownFor[key] or 0) + math.max(0, t - at)
    seenSince[key] = nil
  end
  if own and own:IsVisible() then for _, key in ipairs(laidOwn) do seenSince[key] = t end end
end
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
  -- (yours shown or hidden, by the fight's driver or the bar's own: the time on screen opens or closes; hooks only,
  -- nothing of the frames changed)
  local seen = A.Safe(seenUpdate, "bar: time on screen")
  for _, f in ipairs({ bar, own }) do f:HookScript("OnShow", seen); f:HookScript("OnHide", seen) end
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
-- a group icon's tooltip beside its open list, never over the names: right of it where the screen has room for the
-- tooltip, else left of it, else past the list's far end (above it, or below a list that opens downward). The game
-- clamps its tooltip to the screen, so one put where there is no room would be pushed back over the list
local function besideList(f)
  local tt = GameTooltip
  local need = (plain(call(tt.GetWidth, tt)) or 0) + 8
  local left, right = plain(call(f.GetLeft, f)), plain(call(f.GetRight, f))
  local screen = plain(call(UIParent.GetRight, UIParent))
  tt:ClearAllPoints()
  if type(left) == "number" and type(right) == "number" and type(screen) == "number" then
    -- (the list has the bar's scale; the room is counted in the screen's units, as the tooltip's width is)
    local us = plain(call(UIParent.GetEffectiveScale, UIParent)) or 1
    local k = (plain(call(f.GetEffectiveScale, f)) or us) / (us > 0 and us or 1)
    if screen - right * k < need then
      if left * k >= need then tt:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", -8, 0)
      elseif f.below then tt:SetPoint("TOP", f, "BOTTOM", 0, -8)
      else tt:SetPoint("BOTTOM", f, "TOP", 0, 8) end
      return
    end
  end
  tt:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 8, 0)
end
function B.Tip(owner, rec)
  if not rec or not GameTooltip then return end
  local f = flyouts[owner]
  local beside = rec.flyout and f and f:IsShown()
  GameTooltip:SetOwner(owner, beside and "ANCHOR_NONE" or "ANCHOR_TOP")
  GameTooltip:SetText(rec.name or "", C.WHITE[1], C.WHITE[2], C.WHITE[3])
  if rec.why then tipLine(rec.why, C.INK, true) end
  if rec.p and rec.p.tip then rec.p.tip(GameTooltip, rec) end
  if rec.far then tipLine("Out of range.", C.WARN, true) end
  if rec.clickWord then tipLine("Click: " .. rec.clickWord .. ".", C.INK, true) end
  if rec.flyout then tipLine("Click a name in the list to buff them.", C.DIM, true) end
  tipLine("Right-click: not now, never, settings.", C.DIM, true)
  GameTooltip:Show()
  -- (placed once its lines are in: its width is known then)
  if beside then besideList(f) end
end
local function onEnter(self) B.Tip(self, self.rec) end
local function onLeave() if GameTooltip and GameTooltip:GetOwner() then GameTooltip:Hide() end end

-- Not now and Never: the parts' own quiet, and the account's list (32 at most: Settings counts them and shows them all
-- again)
B.NEVER_MAX = 32
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
  -- (something new on a quiet part brings it back; a provider's own quiet = true never does, its record stays quiet
  -- with the part: a buff someone else gives, its wait over after you said Not now. Unless the record is loud: that
  -- buff at a ready check shows alone, the part still quiet)
  if not (snoozedKeys[rec.part] or {})[rec.never or rec.key] then
    if rec.p and rec.p.quiet then return not rec.loud end
    partSnooze[rec.part] = nil
    return false
  end
  return true
end
function B.Never(key) return A.Settings().never[key] ~= nil end
function B.NeverCount()
  local n = 0
  for _ in pairs(A.Settings().never) do n = n + 1 end
  return n
end
function B.SetNever(key, name, on)
  local never = A.Settings().never
  if on == false then never[key] = nil
  else
    if B.NeverCount() >= B.NEVER_MAX and never[key] == nil then return false end
    never[key] = name or key
  end
  B.Dirty("all")
  -- (a buff you give the group on Never or back: your hello says so, and the share-out moves it to another buffer)
  if type(key) == "string" and key:sub(1, 5) == "duty:" and A.Comm then A.Comm.GivesChanged() end
  -- (the window open on it, the Consumables tab's Never: read again)
  if A.Window and A.Window.Refresh then A.Window.Refresh() end
  return true
end
local function menuFor(b)
  if A.Fighting() then return end
  local rec = b.rec
  if not rec then return end
  local key, name = rec.never or rec.key, rec.neverName or rec.name or rec.key
  local entries = {
    { "Not now", function() B.SnoozePart(rec.part) end },
    -- (the list full: the icon stays, and the chat line says why and where to make room)
    { "Never: " .. name, function()
      if not B.SetNever(key, name) then
        A.Say(B.NEVER_MAX .. " hidden for good already. Settings, Show them all, makes room.")
      end
    end },
  }
  if rec.part == "group" then entries[#entries + 1] = { "Blessings and buffers...", function() if A.Window then A.Window.Open("blessings") end end } end
  if rec.part == "gear" then entries[#entries + 1] = { "Biome gear...", function() if A.Window then A.Window.Open("gear") end end } end
  -- (a provider's own tab: the consumables' "Consumables..."; a record's own first, false for none)
  local tab = rec.window
  if tab == nil and rec.p then tab = rec.p.window end
  if tab then entries[#entries + 1] = { tab[2], function() if A.Window then A.Window.Open(tab[1]) end end } end
  entries[#entries + 1] = { "Settings...", function() if A.Window then A.Window.Open("settings") end end }
  if type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function" then
    MenuUtil.CreateContextMenu(b, function(_, root)
      -- (each runs later, from the game's menu, outside the click's A.Safe: wrapped on its own)
      for _, e in ipairs(entries) do root:CreateButton(e[1], A.Safe(e[2], "bar: menu, " .. e[1])) end
      -- (a provider's own entries: the biome pieces' "Show it in"; a record's own first, false for none)
      local own = rec.menu
      if own == nil and rec.p then own = rec.p.menu end
      if own then
        if root.CreateDivider then root:CreateDivider() end
        own(root, rec)
      end
    end)
  end
end
B.Menu = menuFor
-- (the member a click of ours casts on, its unit as it is now, and its spell: a name the client hides in the cast's
-- SENT is them, Roster.MemberFor)
local noteClick = A.Roster.NoteClick
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
  b:HookScript("PreClick", noteClick)
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
-- (a row: the icon, the name (twelve letters, the game's most) and its state, "Low rank" the longest, side by side:
-- 4 + 16 + 6, the name's 92, the state's 44, 4; the two boxes never overlap)
local ROW, COLW, PER_COL = 22, 166, 10
local function flyoutOf(b)
  local f = flyouts[b]
  if f then return f end
  f = CreateFrame("Frame", b:GetName() .. "Fly", b, "SecureHandlerBaseTemplate")
  f:SetFrameStrata("DIALOG")
  f:SetSize(COLW, ROW)
  f:SetPoint("BOTTOM", b, "TOP", 0, 6)
  -- (a raid's list is four columns, 664 wide, centred on its icon: kept on the screen, as in a fight the bar can't be
  -- moved to reach names past its edge)
  f:SetClampedToScreen(true)
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
  r:SetSize(COLW, ROW)
  r:RegisterForClicks("AnyUp", "AnyDown")
  r.hi = r:CreateTexture(nil, "HIGHLIGHT"); r.hi:SetAllPoints(); r.hi:SetColorTexture(1, 1, 1, 0.1)
  r.glow = r:CreateTexture(nil, "BACKGROUND"); r.glow:SetAllPoints(); r.glow:SetColorTexture(C.QUEST[1], C.QUEST[2], C.QUEST[3], 0.22); r.glow:Hide()
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 4, 0); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = L.Text(r, 11, C.INK, 92, "LEFT"); r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
  r.state = L.Text(r, 10, C.DIM, 44, "RIGHT"); r.state:SetPoint("RIGHT", -4, 0)
  r:HookScript("PreClick", noteClick)
  r:HookScript("OnClick", function() A.After(0.6, function() B.Dirty("group") end, "bar: flyout click") end)
  f.rows[i] = r
  return r
end
-- the flyout's rows from a record's list: { unit, name, class, spell, has, far, dead, glow, low (ending), weak (a lower
-- rank), mark } each
-- (a row's art and words, every one set: legal in a fight, where Buffs' marks repaint a row; a mark's "on" never
-- stays on a row the next layout gives someone else. A marked row, a cast of yours since the read, reads on whatever
-- was read; its mark let go, the read shows again)
local function paintRow(r, e, rec)
  local on = e.mark == true
  r:SetAlpha((not on and (e.far or e.dead or e.off)) and 0.5 or 1)
  L.Art(r.icon, e.tex or rec.tex)
  r.icon:SetDesaturated(on or (e.has == true and not e.low and not e.weak))
  r.name:SetText(e.name or "?")
  r.name:SetTextColor(L.ClassColor(e.class))
  local st, col = "", C.DIM
  if on then st, col = "on", C.GOOD
  elseif e.dead then st, col = "dead", C.BAD elseif e.off then st, col = "offline", C.DIM
  elseif e.far then st, col = "far", C.WARN
  -- (on, at a lower rank than you give: a click gives yours)
  elseif e.weak then st, col = "Low rank", C.WARN
  -- (on, about to end: its time left)
  elseif e.low and e.left then st, col = string.format("%d:%02d", math.floor(e.left / 60), math.floor(e.left % 60)), C.WARN
  elseif e.has then st, col = "on", C.GOOD else st, col = "missing", C.QUEST end
  r.state:SetText(st)
  r.state:SetTextColor(col[1], col[2], col[3])
  r.glow:SetShown(e.glow == true)
  r.member = e.guid
end
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
  -- (over the icon; under it, past its word, when the bar sits in the screen's top half, so the list has room)
  local below = false
  local _, by = bar:GetCenter()
  local sh, us = plain(call(UIParent.GetHeight, UIParent)), plain(call(UIParent.GetEffectiveScale, UIParent)) or 1
  if type(by) == "number" and type(sh) == "number" and us > 0 then below = by * (bar:GetEffectiveScale() or 1) / us > sh / 2 end
  if f.below ~= below then
    f.below = below
    f:ClearAllPoints()
    if below then f:SetPoint("TOP", b, "BOTTOM", 0, -(ROW_H - SIZE + 4)) else f:SetPoint("BOTTOM", b, "TOP", 0, 6) end
  end
  local n = math.min(#list, 40)
  -- (ten rows a column, the columns side by side: a raid's list stays a short box over the icon)
  local cols = math.ceil(n / PER_COL)
  local rows = math.min(n, PER_COL)
  f:SetSize(cols * COLW, rows * ROW + 4)
  for i = 1, n do
    local e = list[i]
    local r = flyRow(f, i)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", f, "TOPLEFT", math.floor((i - 1) / PER_COL) * COLW, -2 - ((i - 1) % PER_COL) * ROW)
    attr(r, "type1", e.spell and "spell" or nil)
    attr(r, "spell", e.spell)
    attr(r, "unit", e.unit)
    paintRow(r, e, rec)
    if not r:IsShown() then r:Show() end
  end
  for i = n + 1, #f.rows do if f.rows[i]:IsShown() then f.rows[i]:Hide() end end
end
-- a group icon's gold wash: lit while a member its own list reaches waits for a Hand's restore (Hands.Glowing), so
-- only the icon whose list holds them glows, and one restore done leaves another's lit; a hidden icon keeps none. Read
-- from its rows, laid out from the list: a roster change in a fight renames them (B.RenameRows)
local function washOf(b)
  if not b.glowTex then return end
  local on = false
  local list = b:IsShown() and b.rec and b.rec.flyout
  local f = list and flyouts[b]
  if f and A.Hands then
    for i = 1, math.min(#list, #f.rows) do
      local r = f.rows[i]
      if r:IsShown() and r.member and A.Hands.Glowing(r.member, b.rec.key) then on = true break end
    end
  end
  if b.glowTex:IsShown() ~= on then b.glowTex:SetShown(on) end
end
-- a roster change in a fight moves the unit tokens under the rows (raid5 is someone else then), and a row's unit can't
-- be set again until the fight ends: each shown row names the member its click now reaches, from its unit (insecure
-- text, allowed there), its state blank (it was the old member's), the row's unit with no one on it greyed. A renamed
-- row glows when its member now waits for a Hand's restore of that list's blessing; the washes and the restores' words
-- (Hands.Renamed) follow
function B.RenameRows()
  local H = A.Hands
  for b, f in pairs(flyouts) do
    for _, r in ipairs(f.rows) do
      local unit = r:IsShown() and r:GetAttribute("unit")
      -- (decided by who the unit now is, not by the row's words: your own row reads "You", never your name)
      local guid = type(unit) == "string" and plain(call(UnitGUID, unit)) or nil
      local me = type(unit) == "string" and A.Yes(UnitIsUnit, unit, "player")
      local name = type(unit) == "string" and (me and "You" or plain(call(UnitName, unit))) or nil
      local same
      if type(guid) == "string" then same = guid == r.member else same = name == r.name:GetText() end
      if type(unit) == "string" and not same then
        local ok, _, class = pcall(UnitClass, unit)
        class = ok and plain(class) or nil
        if type(name) ~= "string" then
          -- (no one: the row claims no member, so no mark or glow of theirs paints it again)
          r.member = nil
          r.name:SetText("?"); r.name:SetTextColor(C.DIM[1], C.DIM[2], C.DIM[3]); r.state:SetText("")
          r.glow:Hide()
        else
          r.member = type(guid) == "string" and guid or nil
          r.name:SetText(name)
          r.name:SetTextColor(L.ClassColor(type(class) == "string" and class or nil))
          r.state:SetText("")
          local lit = r.member ~= nil and H ~= nil and b.rec ~= nil and H.Glowing(r.member, b.rec.key) == true
          r.glow:SetShown(lit)
        end
      end
    end
  end
  for _, b in pairs(icons.group) do washOf(b) end
  if H and H.Renamed then H.Renamed() end
end
-- a shown row of your shown list of that blessing reaches the member now (the restore's words say their row glows only
-- then, Hands.lua)
function B.Reaches(guid, bless)
  local key = "duty:bless:" .. tostring(bless)
  for b, f in pairs(flyouts) do
    if b:IsShown() and b.rec and b.rec.key == key and b.rec.flyout then
      for i = 1, math.min(#b.rec.flyout, #f.rows) do
        local r = f.rows[i]
        if r:IsShown() and r.member == guid then return true end
      end
    end
  end
  return false
end
-- a glow on a member's row and its icon's wash (a Hand's restore in a fight: insecure art, allowed there), only in the
-- list of the blessing the restore names (Hands.Glowing)
function B.GlowMember(guid, on)
  local H = A.Hands
  for b, f in pairs(flyouts) do
    local lit = on and (H == nil or H.Glowing(guid, (b.rec and b.rec.key) or "")) or false
    for _, r in ipairs(f.rows) do if r.member == guid then r.glow:SetShown(lit) end end
  end
  for _, b in pairs(icons.group) do
    if b.rec and b.rec.flyout then
      local lit = on and (H == nil or H.Glowing(guid, b.rec.key)) or false
      for _, e in ipairs(b.rec.flyout) do if e.guid == guid then e.glow = lit end end
    end
    washOf(b)
  end
end
-- one record painted again from its fields, art only (legal in a fight): its icon, and its list's rows that still show
-- the member they were laid out for (a roster change in a fight renames the others: B.RenameRows). Buffs' marks call
-- it; the next layout paints every field again from a fresh read
function B.Repaint(rec)
  local b = rec and icons[rec.part == "group" and "group" or "own"][rec.key]
  if not (b and b.rec == rec) then return end
  L.Paint(b, rec)
  local f = rec.flyout and flyouts[b]
  if not f then return end
  for i, e in ipairs(rec.flyout) do
    local r = f.rows[i]
    if r and r:IsShown() and r.member == e.guid then paintRow(r, e, rec) end
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
-- a provider read again on the clock: timed = true, every tick; "own", only while one of its own records counts down
-- (the group's duties: forty members' states, not re-read for someone else's countdown)
local function onClockToo(p)
  if p.timed == true then return true end
  if p.timed == "own" then for i = 1, p.n do if p.recs[i].timed then return true end end end
  return false
end
local function readAll()
  ctx.t = A.Now()
  ctx.town = A.Yes(IsResting)
  ctx.inst = instanceKind()
  -- (where you stand as the consumables' chips name it: solo, pvp, dungeon, raid)
  ctx.where = A.Consume and A.Consume.Where() or "solo"
  ctx.group = A.Roster.InGroup()
  ctx.raid = A.Roster.InRaid()
  ctx.level = plain(call(UnitLevel, "player")) or 1
  ctx.still = still
  ctx.pull = B.PullOn()
  local any = dirty.all
  for _, p in ipairs(B.list) do
    local want = any
    if not want then for _, g in ipairs(p.groups or {}) do if dirty[g] then want = true break end end end
    if B.clockOn and onClockToo(p) then want = true end
    if want then
      p.n = 0
      if not offPart(p) then
        reading = p
        p.safeRead(add, ctx)
        reading = nil
      -- (its part off: what the provider keeps between reads let go, so the part back on starts fresh)
      elseif p.safeOff then
        p.safeOff()
      end
    end
  end
  for k in pairs(dirty) do dirty[k] = nil end
end
local function collect()
  for _, l in pairs(shown) do for i = #l, 1, -1 do l[i] = nil end end
  local inst, mode = ctx.inst, set.instance
  if inst and mode == "none" then return end
  -- (Before the pull's icons put off with Not now: it runs its course, quiet, and yours and the camp's Eat stay aside
  -- for it; it ends early only with nothing left to ask)
  local pullQuiet = false
  for _, p in ipairs(B.list) do
    for i = 1, p.n do
      local rec = p.recs[i]
      if allowed(rec) then
        if not partQuiet(rec) then
          local part = rec.part or "mine"
          -- (in a dungeon or raid, "buffs": no camp)
          if not (inst and mode ~= "all" and part == "camp") then
            local l = shown[part]
            if l and #l < MAX[part] then l[#l + 1] = rec end
          end
        elseif rec.part == "pull" then pullQuiet = true end
      end
    end
  end
  for k in pairs(paused) do paused[k] = nil end
  for _, rec in ipairs(shown.camp) do if rec.pause then paused[rec.key] = true end end
  if ctx.pull and #shown.pull == 0 and not pullQuiet then B.PullEnd() end
end
local usedBuf = {}
-- a part's icons left to right, each COL on from the one before (its word, cut to fit, centred under it in a box as
-- wide as the column: Look.lua)
local function layPart(container, list, which)
  local used = usedBuf
  for k in pairs(used) do used[k] = nil end
  if which == "own" then for i = #laidOwn, 1, -1 do laidOwn[i] = nil end end
  local x = 0
  for _, rec in ipairs(list) do
    local key = rec.key
    used[key] = true
    if which == "own" and rec.lit ~= false then laidOwn[#laidOwn + 1] = key end
    local b = icons[which][key]
    if not b then b = newIcon("CuteAuras" .. (which == "group" and "Group_" or "Bar_") .. key:gsub("[^%w]", "_"), container, which); icons[which][key] = b end
    L.Paint(b, rec)
    setClick(b, rec)
    if which == "group" then layFlyout(b, rec) end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", container, "TOPLEFT", x, 0)
    if not b:IsShown() then b:Show() end
    washOf(b)
    x = x + COL
  end
  for key, b in pairs(icons[which]) do
    if not used[key] and b:IsShown() then b:Hide(); b.rec = nil; washOf(b); if flyouts[b] then flyouts[b]:Hide() end end
  end
end
local ownList = {}
local function layout()
  for i = #ownList, 1, -1 do ownList[i] = nil end
  for _, part in ipairs({ "camp", "mine", "pull", "gear" }) do
    for _, rec in ipairs(shown[part]) do ownList[#ownList + 1] = rec end
  end
  local nOwn, nGrp = #ownList, #shown.group
  local gap = (nOwn > 0 and nGrp > 0) and PART_GAP or 0
  -- (each part's width from its icon count alone: n columns, the last one's gap not counted)
  local wOwn = nOwn > 0 and (nOwn * COL - GAP) or 0
  local wGrp = nGrp > 0 and (nGrp * COL - GAP) or 0
  own:ClearAllPoints(); own:SetPoint("TOPLEFT", bar, "TOPLEFT", PADX, -PADT)
  layPart(own, ownList, "own")
  own:SetSize(math.max(1, wOwn), ROW_H)
  grp:ClearAllPoints(); grp:SetPoint("TOPLEFT", bar, "TOPLEFT", PADX + wOwn + gap, -PADT)
  layPart(grp, shown.group, "group")
  grp:SetSize(math.max(1, wGrp), ROW_H)
  bar:SetSize(PADX * 2 + math.max(SIZE, wOwn + gap + wGrp), PADT + ROW_H + PADB)
  local any = nOwn + nGrp > 0
  if any and not bar:IsShown() then bar:Show() elseif not any and bar:IsShown() then bar:Hide() end
  seenUpdate()
end
local function hideAll() if bar and bar:IsShown() then bar:Hide() end end
-- its line for /cauras diag, numbers alone (never a word or a name): the icons laid, the bar's width, the widest verb
-- at the client's own font against the room a word has (a verb over it needs a shorter word) and the words cut to fit
local meter
function B.DiagLine()
  if not bar then return "Bar: not made yet." end
  local n, cut, widest = 0, 0, 0
  for _, which in ipairs({ "own", "group" }) do
    for _, b in pairs(icons[which]) do
      local rec = b:IsShown() and b.rec
      if rec and b.word then
        n = n + 1
        local whole = b.caWord or ""
        if b.word:GetText() ~= whole then cut = cut + 1 end
        -- (a verb: no member's name, which wears its class's colour)
        if not (rec.class and rec.status == nil) and whole ~= "" then
          if not meter then meter = L.Text(UIParent, 11, C.INK); meter:Hide() end
          meter:SetText(whole)
          widest = math.max(widest, L.Width(meter))
        end
      end
    end
  end
  return string.format("Bar: %s%d icons, %d wide; widest word %d of %d; names cut %d", bar:IsShown() and "" or "hidden, ", n,
    math.floor((bar:GetWidth() or 0) + 0.5), math.ceil(widest), L.ROOM, cut)
end

-- the clock: once a second while a word counts down, a fresh look of the timed providers (a range changes on the
-- group's own 3 s look, Buffs.lua)
local clock
local function wantClock()
  for _, l in pairs(shown) do for _, rec in ipairs(l) do if rec.timed then return true end end end
  return false
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

-- a look the client refused out of a fight (it still restricts, or keeps auras secret) never given up: tried again as a
-- restriction lifts (ADDON_RESTRICTION_STATE_CHANGED, B:Init), and every second meanwhile, one timer at a time (none
-- in a fight: fightOver takes over). For /cauras diag, after the last fight (at, its PLAYER_REGEN_ENABLED): the looks
-- refused, why (Combat, Encounter, auras secret), and the seconds to the first that went through (took)
local late = { at = nil, refused = 0, took = nil, why = {}, waiting = false, timer = false, lifted = false }
B.late = late
local RETRY = 1
local function refused(why)
  late.waiting = true
  if late.at and not late.took then
    late.refused = late.refused + 1
    late.why[why] = true
  end
  if late.timer then return end
  late.timer = true
  A.After(RETRY, function()
    late.timer = false
    if late.waiting and not A.Fighting() then B.Refresh() end
  end, "bar: refused, again")
end
-- the bar has read your auras since the last fight ended (until it has, what Camp.Mine keeps is from before the pull:
-- the Consumables tab waits for this read, as the bar's own refuses while the client restricts)
function B.ReadSinceFight() return not (late.at and not late.took) end
-- its line for /cauras diag
function B.LateLine()
  if not late.at then return "After a fight: no fight yet." end
  local why = {}
  for _, k in ipairs({ "Combat", "Encounter", "auras secret" }) do if late.why[k] then why[#why + 1] = k end end
  local n = late.refused == 1 and "1 refresh" or (late.refused .. " refreshes")
  return "After the last fight: " .. n .. " refused" .. (#why > 0 and (", by " .. table.concat(why, " and ")) or "") .. "; "
    .. (late.took and string.format("read again %.1f s after it.", late.took) or "still waiting.")
end

function flushNow()
  if A.Fighting() then after.waiting = true return end
  if after.waiting and after.gen > 0 then return end
  local why = refusedBy()
  if why then after.waiting = true; refused(why) return end
  late.waiting = false
  if late.at and not late.took then late.took = A.Now() - late.at end
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
  late.at, late.refused, late.took = A.Now(), 0, nil
  for k in pairs(late.why) do late.why[k] = nil end
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
-- 60 s after the entry, when nothing is left, or at the first fight. A fight before the start (a pull at once, a
-- /reload in a raid's fight): no start. A finish before it (a check all answered at once): it starts, and ends 10 s
-- after that finish
----------------------------------------------------------------------------
local pull = { untilT = nil, gen = 0, waiting = false, endAt = nil }
function B.PullOn()
  if not pull.untilT then return false end
  if A.Now() >= pull.untilT then pull.untilT = nil return false end
  return true
end
function B.StartPull(seconds, delay)
  pull.gen = pull.gen + 1
  local gen = pull.gen
  pull.waiting, pull.endAt = true, nil
  A.After(delay or 0, function()
    if gen ~= pull.gen then return end
    pull.waiting = false
    if A.Fighting() then return end
    local untilT = A.Now() + seconds
    if pull.endAt then untilT = math.min(untilT, pull.endAt) end
    pull.endAt = nil
    if untilT <= A.Now() then return end
    pull.untilT = untilT
    B.Dirty("pull")
    A.After(untilT - A.Now() + 0.1, function() if gen == pull.gen then B.Dirty("pull") end end, "bar: pull")
  end, "bar: pull")
end
-- (a fight: over, and a start still waiting called off)
local function pullFight()
  pull.gen = pull.gen + 1
  pull.untilT, pull.waiting, pull.endAt = nil, false, nil
end
function B.PullEnd(delay)
  -- (a finish before the start: the start keeps its end, an earlier pull still on or not; that one ends by it too)
  if pull.waiting and delay then pull.endAt = A.Now() + delay end
  if not pull.untilT then return end
  if delay then
    pull.untilT = math.min(pull.untilT, A.Now() + delay)
    -- (read again as it ends: its icons go, and the camp's Eat it stood in for comes back, then and not at the 45 s)
    local gen = pull.gen
    A.After(delay + 0.1, function() if gen == pull.gen then B.Dirty("pull") end end, "bar: pull")
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
  A.On("PLAYER_REGEN_DISABLED", function() after.gen = after.gen + 1; after.waiting = true; pullFight() end)
  A.On("PLAYER_REGEN_ENABLED", fightOver)
  -- (a restriction lifted while a look waits: every unit's auras read afresh, the whole bar looked at again. A frame
  -- on: while the client tells this, it answers every restriction inactive. Several lifted in one frame (a boss's end:
  -- Encounter, Chat, Combat) are one look, and none once a look went through)
  A.On("ADDON_RESTRICTION_STATE_CHANGED", function(_, _, state)
    local states = Enum and Enum.AddOnRestrictionState
    if plain(state) ~= (states and states.Inactive or 0) or not late.waiting or A.Fighting() then return end
    if A.Buffs then A.Buffs.Stale(nil) end
    if late.lifted then return end
    late.lifted = true
    A.After(0, function()
      late.lifted = false
      if late.waiting and not A.Fighting() then B.Refresh() end
    end, "bar: a restriction lifted")
  end)
  A.On("GROUP_ROSTER_UPDATE", function() if A.Fighting() then B.RenameRows() end end, "bar: rows renamed")
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
