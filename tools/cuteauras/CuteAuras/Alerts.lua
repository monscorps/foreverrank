-- SPDX-License-Identifier: GPL-3.0-or-later
-- The alerts overlay: warnings you can place and size, apart from the bar. Show as (Settings): Icons, the default, or
-- Small, Normal or Big cards.
--   Icons: each alert a 36 px game icon (a countdown's sweep and its whole seconds over it), a 2 px bar under it in its
--   kind's colour (PINK a Hand counting, QUEST gold a restore, GROUP teal a rebuff), the member's name under that in
--   their class colour; a restore's edge gold. No box, title or line: those are the tooltip's. Two rows, each centred on
--   the overlay's top: the click row (Hands' secure restore, the restores waiting after it, Rebuff's rebuff; placed out
--   of a fight only, secure icons can't move in one), and under it while it shows the art row (countdowns and restores
--   in a fight, oldest left, newest added right).
--   Cards: a game icon, a title in white or the member's class colour, a line under it (two lines at most), a bar at
--   its left in its kind's colour; stacked downward from the overlay's top, the secure cards first.
-- Both: a pulse as one comes; an art one works in a fight (never the game's secure button); right-click one to dismiss
-- it (onDismiss runs first). "Alerts on screen" off: none at all, the secure ones too.
--   Alerts.Show(key, spec)  spec = { icon, title, text, tip, name, class, color, gold, dim, row, at, expires, duration,
--                                    sound, onClick, onDismiss, onEnd, keep, take, before }
--     name: under the icon; gold: the restore's edge; dim: waiting; row "click": in the click row (at: its order there);
--     take: the key of the alert whose slot this one takes (that one goes); before: a new icon's place, before that key
--   Alerts.Hide(key)
local _, A = ...
local Al = A.Part("Alerts", { cards = {}, order = {} })
local L = A.Look
local C = L.C

local SIZES = { small = 36, normal = 48, big = 64 }
local ICON, NAME_W, ROW_H, SLOT_GAP, ROW_GAP = 36, 76, 58, 8, 6 -- (a row: the icon, 10 to the name, the name's 12)
Al.ICON, Al.ROW_H = ICON, ROW_H
-- Icons unless a card size is chosen
function Al.Icons() return SIZES[A.Settings().alertLook] == nil end
function Al.IconSize() return SIZES[A.Settings().alertLook] or ICON end
local GAP = 6
Al.GAP = GAP
-- a card's type: Small is smaller words too (two lines still, so a name and its line read whole), Big bigger
local FONTS = { small = { 12, 10 }, normal = { 14, 11 }, big = { 16, 12 } }
function Al.Fonts() local f = FONTS[A.Settings().alertLook] or FONTS.normal; return f[1], f[2] end
-- a card's height: the icon's, or the title and two lines of text where that is more
function Al.CardHeight()
  local t, x = Al.Fonts()
  return math.max(Al.IconSize() + 8, 6 + (t + 2) + 3 + 2 * (x + 2) + 4)
end
function Al.On() return A.Settings().alerts ~= false end

local anchor
local function scale()
  local v = tonumber(A.Settings().alertScale)
  if v and v >= 0.5 and v <= 2 then return v end
  return 1
end
local function place()
  if not anchor or A.Fighting() then return end
  local k = scale()
  if anchor:GetScale() ~= k then anchor:SetScale(k) end
  anchor:ClearAllPoints()
  local pos = A.Settings().alertPos
  if type(pos) == "table" and tonumber(pos.x) and tonumber(pos.y) then
    anchor:SetPoint("TOP", UIParent, "BOTTOMLEFT", pos.x / k, pos.y / k)
  else
    -- (the default: 230 over the centre, and never less than 290 under the screen's top, below the game's error lines
    -- (UIErrorsFrame, 122 to 182) and its raid warnings (RaidWarningFrame, 182 to 282) on a short screen or a big UI scale)
    local h = tonumber(UIParent:GetHeight()) or 768
    anchor:SetPoint("TOP", UIParent, "CENTER", 0, math.min(230, h / 2 - 290) / k)
  end
end
Al.Place = place
function Al.Anchor()
  if anchor then return anchor end
  anchor = CreateFrame("Frame", "CuteAurasAlerts", UIParent)
  anchor:SetSize(260, 64)
  anchor:SetFrameStrata("HIGH")
  anchor:SetClampedToScreen(true)
  anchor:SetMovable(true)
  -- (Move mode's handle: a box with its name at its top, dragged out of a fight; the window's Done goes under the name)
  anchor.box = L.Fill(anchor, "BACKGROUND", C.PINK, 0.18)
  anchor.box:SetAllPoints()
  anchor.box:Hide()
  anchor.label = L.Text(anchor, 12, C.WHITE)
  anchor.label:SetPoint("TOP", 0, -10)
  anchor.label:SetText("Cute Auras alerts")
  anchor.label:Hide()
  place()
  Al.anchor = anchor
  return anchor
end
function Al.SavePlace()
  local x, top = anchor:GetCenter(), anchor:GetTop()
  if not (x and top) then return end
  local fs, us = anchor:GetEffectiveScale() or 1, UIParent:GetEffectiveScale() or 1
  local k = us > 0 and fs / us or 1
  A.Settings().alertPos = { x = x * k, y = top * k }
  place()
end

----------------------------------------------------------------------------
-- an alert: its parts, and its two looks (the secure ones' too: Hands' restore and Rebuff's rebuff have the same parts,
-- their icon a texture, shaped out of a fight only)
----------------------------------------------------------------------------
local pool = {}
local function newCard()
  local f = CreateFrame("Button", nil, Al.Anchor())
  f:RegisterForClicks("AnyUp")
  f.bg = L.Fill(f, "BACKGROUND", C.PANEL, 0.78)
  f.bg:SetAllPoints()
  f.side = f:CreateTexture(nil, "BORDER")
  f.side:SetPoint("TOPLEFT"); f.side:SetPoint("BOTTOMLEFT"); f.side:SetWidth(3)
  f.icon = L.Icon(nil, f, false, false, 48)
  f.icon:EnableMouse(false)
  f.big = L.Text(f.icon, 20, C.WHITE)
  f.big:SetPoint("CENTER", f.icon, "CENTER", 0, 0)
  f.title = L.Text(f, 14, C.WHITE, 190, "LEFT")
  f.text = L.Text(f, 11, C.INK, 190, "LEFT", 2)
  f.bar = f:CreateTexture(nil, "ARTWORK")
  f.bar:Hide()
  f.name = L.Text(f, 10, C.WHITE, NAME_W)
  f.name:Hide()
  f.glow = f:CreateTexture(nil, "OVERLAY")
  f.glow:SetColorTexture(1, 1, 1, 1)
  f.glow:SetAlpha(0)
  f:SetScript("OnClick", function(self, button)
    local spec = self.spec
    if button == "RightButton" then
      if spec and spec.onDismiss then A.Safe(spec.onDismiss, "alerts: dismiss")(self) end
      Al.Hide(self.key)
      return
    end
    if spec and spec.onClick then A.Safe(spec.onClick, "alerts: click")(self) end
  end)
  f:SetScript("OnEnter", function(self)
    local spec = self.spec
    if spec then Al.Tip(self, spec.title, spec.text, spec.tip, "Right-click: dismiss.") end
  end)
  f:SetScript("OnLeave", Al.Untip)
  return f
end
-- an alert's tooltip, the art ones' and the secure ones' alike: its title, its line, a tip, what a click does
function Al.Tip(owner, title, text, tip, how)
  if not GameTooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(title or "", C.WHITE[1], C.WHITE[2], C.WHITE[3])
  if text and text ~= "" then GameTooltip:AddLine(text, C.INK[1], C.INK[2], C.INK[3], true) end
  if tip then GameTooltip:AddLine(tip, C.DIM[1], C.DIM[2], C.DIM[3], true) end
  if how then GameTooltip:AddLine(how, C.DIM[1], C.DIM[2], C.DIM[3], true) end
  GameTooltip:Show()
end
function Al.Untip() if GameTooltip and GameTooltip:GetOwner() then GameTooltip:Hide() end end
-- an icon's edge: 1 px black, or a restore's 2 px gold
local BLACK = { 0, 0, 0 }
function Al.Edge(e, ic, gold)
  if not e then return end
  local k = gold and 2 or 1
  if e.caK ~= k then
    e.caK = k
    e:ClearAllPoints()
    e:SetPoint("TOPLEFT", ic, "TOPLEFT", -k, k)
    e:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", k, -k)
  end
  local col = gold and C.QUEST or BLACK
  e:SetColorTexture(col[1], col[2], col[3], 1)
end
-- the icon look: 36 x 36, the bar 4 px under it, the name 10 px under it; no box, strip, title or line
function Al.ShapeIcon(f)
  for _, k in ipairs({ "bg", "side", "title", "text" }) do if f[k] then f[k]:Hide() end end
  f:SetSize(ICON, ICON)
  local ic = f.icon
  ic:SetSize(ICON, ICON)
  ic:ClearAllPoints(); ic:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  if f.edge then f.edge:Show() end
  f.bar:ClearAllPoints(); f.bar:SetSize(ICON, 2); f.bar:SetPoint("TOP", ic, "BOTTOM", 0, -4); f.bar:Show()
  f.name:ClearAllPoints(); f.name:SetPoint("TOP", ic, "BOTTOM", 0, -10); f.name:Show()
  f.rowH = ROW_H
end
-- a card's size and parts for the overlay's icon size, the three kinds alike: the icon at the left, the title at the
-- card's top, the line under it
function Al.ShapeCard(f, s)
  for _, k in ipairs({ "bg", "side", "title", "text" }) do if f[k] then f[k]:Show() end end
  for _, k in ipairs({ "edge", "bar", "name" }) do if f[k] then f[k]:Hide() end end
  f:SetSize(s + 210, Al.CardHeight())
  local t, x = Al.Fonts()
  f.title:SetFont(L.Font(), t, "OUTLINE")
  f.text:SetFont(L.Font(), x, "OUTLINE")
  f.icon:SetSize(s, s)
  f.icon:ClearAllPoints(); f.icon:SetPoint("LEFT", f, "LEFT", 7, 0)
  f.title:ClearAllPoints(); f.title:SetPoint("TOPLEFT", f, "TOPLEFT", s + 16, -6)
  f.text:ClearAllPoints(); f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
  f.rowH = Al.CardHeight()
end
-- the name under an icon: cut to its box (whole UTF-8 characters, no dots), in the class's colour
function Al.Name(f, name, class)
  f.name:SetText(L.Fit(f.name, name or "", NAME_W) or "")
  if class then f.name:SetTextColor(L.ClassColor(class)) else f.name:SetTextColor(C.WHITE[1], C.WHITE[2], C.WHITE[3]) end
end
local function shape(f)
  local look = Al.Icons() and "icons" or A.Settings().alertLook
  if f.look == look then return end
  f.look = look
  if look == "icons" then
    Al.ShapeIcon(f)
    f.big:SetFont(L.Font(), 15, "OUTLINE")
  else
    local s = Al.IconSize()
    Al.ShapeCard(f, s)
    f.big:SetFont(L.Font(), math.floor(s * 0.42), "OUTLINE")
  end
  f.glow:ClearAllPoints(); f.glow:SetAllPoints(f.icon)
end
Al.Shape = shape

-- a countdown's seconds: whole, rounded up (10 to 1), never tenths
local function secs(f, left)
  local s = tostring(math.ceil(left))
  if f.caSec ~= s then f.caSec = s; f.big:SetText(s) end
end
local function paint(f, spec)
  shape(f)
  L.Art(f.icon.icon, spec.icon or 134400)
  f.icon.icon:SetDesaturated(spec.dim == true)
  f.title:SetText(spec.title or "")
  if spec.class then f.title:SetTextColor(L.ClassColor(spec.class)) else f.title:SetTextColor(C.WHITE[1], C.WHITE[2], C.WHITE[3]) end
  f.text:SetText(spec.text or "")
  local col = spec.color or C.QUEST
  f.side:SetColorTexture(col[1], col[2], col[3], 1)
  f.bar:SetColorTexture(col[1], col[2], col[3], 1)
  Al.Edge(f.icon.edge, f.icon, spec.gold == true and f.look == "icons")
  Al.Name(f, spec.name, spec.class)
  if spec.expires and spec.duration and spec.duration > 0 then
    f.icon.cd:SetCooldown(spec.expires - spec.duration, spec.duration)
    f.caSec = nil
    secs(f, math.max(0, spec.expires - A.Now()))
  else
    f.icon.cd:SetCooldown(0, 0)
    f.caSec = nil
    f.big:SetText("")
  end
end

----------------------------------------------------------------------------
-- where they sit
----------------------------------------------------------------------------
-- a slot's width: its name's, 36 at least, its box's 76 at most (76 where the client can't measure)
local function slotW(f)
  local w = f.name and L.Width(f.name) or 0
  if w <= 0 then return NAME_W end
  return math.min(NAME_W, math.max(ICON, math.ceil(w)))
end
local clickArt, artRow = {}, {}
local function byAt(a, b) return (a.spec.at or 0) < (b.spec.at or 0) end
local function layoutIcons(an, hb, rb, hbOn, rbOn)
  for i = #clickArt, 1, -1 do clickArt[i] = nil end
  for i = #artRow, 1, -1 do artRow[i] = nil end
  for _, key in ipairs(Al.order) do
    local f = Al.cards[key]
    if f then if f.spec.row == "click" then clickArt[#clickArt + 1] = f else artRow[#artRow + 1] = f end end
  end
  table.sort(clickArt, byAt)
  -- the click row, out of a fight only: the restore, the restores after it, the rebuff. A hidden rebuff waits at the
  -- centre: it shows in a fight, where the restore's guard has hidden the restore and its line is art in the art row
  if not A.Fighting() then
    local total, n = 0, 0
    local hw = hbOn and slotW(hb) or 0
    local rw = rbOn and slotW(rb) or 0
    if hbOn then total, n = hw, 1 end
    for _, f in ipairs(clickArt) do
      f.caSlot = slotW(f)
      total = total + f.caSlot + (n > 0 and SLOT_GAP or 0); n = n + 1
    end
    if rbOn then total = total + rw + (n > 0 and SLOT_GAP or 0) end
    local x = -total / 2
    if hbOn then A.Hands.Place(x + hw / 2); x = x + hw + SLOT_GAP end
    for _, f in ipairs(clickArt) do
      f:ClearAllPoints(); f:SetPoint("TOP", an, "TOP", x + f.caSlot / 2, 0)
      x = x + f.caSlot + SLOT_GAP
    end
    if rb and A.Rebuff.Stack then A.Rebuff.Stack(rbOn and (x + rw / 2) or 0) end
  end
  -- the art row: at the top, or under the click row while any of it shows. (The rebuff keeps its look and place in a
  -- fight: a card hung under the restore's place, from Cards before a switch, reaches down past that card)
  local h = 0
  if hbOn then h = math.max(h, hb.rowH or ROW_H) end
  if rbOn then
    local under = A.Rebuff.under
    h = math.max(h, (under and ((under:GetHeight() or 0) + GAP) or 0) + (rb.rowH or ROW_H))
  end
  if #clickArt > 0 then h = math.max(h, ROW_H) end
  local y = h > 0 and -(h + ROW_GAP) or 0
  local total = 0
  for i, f in ipairs(artRow) do f.caSlot = slotW(f); total = total + f.caSlot + (i > 1 and SLOT_GAP or 0) end
  local x = -total / 2
  for _, f in ipairs(artRow) do
    f:ClearAllPoints(); f:SetPoint("TOP", an, "TOP", x + f.caSlot / 2, y)
    x = x + f.caSlot + SLOT_GAP
  end
end
local function layoutCards(an, hb, rb, hbOn, rbOn)
  -- (the secure cards at the top, out of a fight: the restore, the rebuff under it; the art cards under both)
  if not A.Fighting() then
    if hbOn then A.Hands.Place(0) end
    if rb and A.Rebuff.Stack then A.Rebuff.Stack(0, hbOn and hb or nil) end
  end
  local top = 0
  if hbOn then top = (hb:GetHeight() or 0) + GAP end
  if rbOn then
    -- (hung under the restore card, which a fight may have hidden: still under its place. Its row as tall as its look:
    -- an icon from Icons before a switch in a fight keeps its name under it till the fight ends)
    local under = A.Rebuff.under
    local from = under and ((under:GetHeight() or 0) + GAP) or 0
    top = math.max(top, from + (rb.rowH or rb:GetHeight() or 0) + GAP)
  end
  for _, key in ipairs(Al.order) do
    local f = Al.cards[key]
    if f then
      f:ClearAllPoints()
      f:SetPoint("TOP", an, "TOP", 0, -top)
      top = top + (f:GetHeight() or 0) + GAP
    end
  end
end
local function layout()
  local an = Al.Anchor()
  local hb = A.Hands and A.Hands.button
  local rb = A.Rebuff and A.Rebuff.button
  local hbOn, rbOn = (hb and hb:IsShown()) and true or false, (rb and rb:IsShown()) and true or false
  if Al.Icons() then layoutIcons(an, hb, rb, hbOn, rbOn) else layoutCards(an, hb, rb, hbOn, rbOn) end
end
Al.Layout = layout

----------------------------------------------------------------------------
-- the clock (countdowns, pulses, ends) and the sound
----------------------------------------------------------------------------
local clock
local function remove(key)
  local f = Al.cards[key]
  if not f then return end
  Al.cards[key] = nil
  for i = #Al.order, 1, -1 do if Al.order[i] == key then table.remove(Al.order, i) end end
  f:Hide()
  f.key, f.spec = nil, nil
  pool[#pool + 1] = f
  layout()
end
local function tick(_, dt)
  local t = A.Now()
  local any = false
  -- (the ones whose time is up, run after the walk: an end may show another alert, and no key is added while pairs
  -- walks the cards)
  local done
  for key, f in pairs(Al.cards) do
    any = true
    local spec = f.spec
    if spec.expires then
      local left = spec.expires - t
      if left <= 0 then
        done = done or {}
        done[#done + 1] = { key, f, spec }
      else
        secs(f, left)
      end
    elseif spec.until_ and t >= spec.until_ then
      done = done or {}
      done[#done + 1] = { key, f, spec }
    end
    -- (the pulse: the first 1.5 s of one, a white flash over its icon that fades three times)
    local age = t - (f.born or t)
    if age < 1.5 then f.glow:SetAlpha(0.45 * math.abs(math.sin(age * math.pi * 2))) elseif f.glow:GetAlpha() > 0 then f.glow:SetAlpha(0) end
  end
  for _, e in ipairs(done or {}) do
    local key, f, spec = e[1], e[2], e[3]
    if spec.expires and spec.onEnd then A.Safe(spec.onEnd, "alerts: end")(spec) end
    if Al.cards[key] == f and f.spec == spec then remove(key) end
  end
  if not any and clock then clock:SetScript("OnUpdate", nil); clock.running = false end
end
local function runClock()
  if not clock then clock = CreateFrame("Frame") end
  if clock.running then return end
  clock.running = true
  clock:SetScript("OnUpdate", A.Safe(tick, "alerts: clock"))
end
local lastSound = 0
local function sound()
  if not A.Settings().sound then return end
  local t = A.Now()
  if t - lastSound < 2 then return end
  lastSound = t
  local kit = SOUNDKIT and (SOUNDKIT.RAID_WARNING or SOUNDKIT.UI_RAID_BOSS_WHISPER_WARNING)
  if type(PlaySound) == "function" then pcall(PlaySound, kit or 8959, "Master") end
end
Al.Sound = sound

function Al.Show(key, spec)
  if not Al.On() then return nil end
  local f = Al.cards[key]
  local fresh = not f
  local take = spec.take ~= key and spec.take and Al.cards[spec.take] and spec.take or nil
  if not f then
    f = table.remove(pool) or newCard()
    Al.cards[key] = f
    local at, put
    if take then for i, k in ipairs(Al.order) do if k == take then at = i end end end
    if not at and spec.before then for i, k in ipairs(Al.order) do if k == spec.before then put = i end end end
    -- (in the slot of the one it takes, or before the one named; else icons add at the right, cards at the top)
    if at then Al.order[at] = key
    elseif put and Al.Icons() then table.insert(Al.order, put, key)
    elseif Al.Icons() then table.insert(Al.order, key)
    else table.insert(Al.order, 1, key) end
    f.born = A.Now()
  end
  f.key, f.spec = key, spec
  if take then remove(take) end
  if not spec.expires and not spec.keep then spec.until_ = A.Now() + (spec.life or 20) end
  paint(f, spec)
  f:Show()
  layout()
  runClock()
  if fresh and spec.sound then sound() end
  return f
end
function Al.Hide(key) remove(key) end
function Al.Has(key) return Al.cards[key] ~= nil end
function Al.Clear() for key in pairs(Al.cards) do remove(key) end end
-- Show as changed (Settings): every art one again at once, in a fight too; the secure ones after it. Icons and cards
-- read the order the other way (oldest left, newest on top), so a switch turns it round
local wasIcons
function Al.Restyle()
  local icons = Al.Icons()
  if wasIcons ~= nil and wasIcons ~= icons then
    local o, n = Al.order, #Al.order
    for i = 1, math.floor(n / 2) do o[i], o[n + 1 - i] = o[n + 1 - i], o[i] end
  end
  wasIcons = icons
  for _, f in pairs(Al.cards) do f.look = nil; paint(f, f.spec) end
  if A.Rebuff and A.Rebuff.Restyle then A.Rebuff.Restyle() end
  if A.Hands and A.Hands.Refresh then A.Hands.Refresh() end
  layout()
end

-- /cauras test: the three as they come in play, left to right a Hand's countdown, its restore and a rebuff, their
-- words as the game's own make them (long names: what fits these fits play), for placing and sizing the overlay
function Al.Test()
  if not Al.On() then A.Say("Alerts are off: tick Alerts on screen in Settings first.") return end
  local t = A.Now()
  local D, H, Rb = A.Data, A.Hands, A.Rebuff
  local name = "Bramblewoode"
  local prot = L.SpellName(1022, D.HANDS.protection.name)
  local title, text = H.HandWords(name, prot, "kings")
  Al.Show("test:hand", { icon = L.SpellIcon(1022, D.HANDS.protection.icon), title = title, name = name, class = "WARRIOR", text = text,
    color = C.PINK, expires = t + 10, duration = 10 })
  title, text = H.RestoreWords(name, "kings", prot, "fight", true)
  Al.Show("test:restore", { icon = L.SpellIcon(20217, D.BLESS.kings.icon), title = title, name = name, class = "WARRIOR", text = text,
    tip = H.FIGHT_TIP, color = C.QUEST, gold = true, life = 15 })
  local fort = L.SpellName(1243, "Power Word: Fortitude")
  title, text = Rb.Words(name, fort, "cast")
  Al.Show("test:rebuff", { icon = L.SpellIcon(1243, 135987), title = title, text = text, name = name, class = "MAGE", color = C.GROUP,
    sound = true, life = 15 })
  A.Say("Test alerts for 15 s. /cauras move to place them, Settings to size them.")
end

-- /cauras diag: the look, what shows, where the overlay sits (numbers and words, never a member's name)
function Al.DiagLine()
  local s = A.Settings()
  local shown, waiting, clicks = 0, 0, 0
  for _, f in pairs(Al.cards) do
    shown = shown + 1
    if f.spec and f.spec.row == "click" then waiting = waiting + 1 end
  end
  for _, b in ipairs({ A.Hands and A.Hands.button or false, A.Rebuff and A.Rebuff.button or false }) do
    if b and b:IsShown() then clicks = clicks + 1 end
  end
  local h = math.floor((tonumber(UIParent:GetHeight()) or 768) + 0.5)
  local pos = s.alertPos
  local where
  if type(pos) == "table" and tonumber(pos.x) and tonumber(pos.y) then
    where = string.format("overlay moved, its top %d up", math.floor(pos.y + 0.5))
  else
    where = string.format("overlay %d over the centre", math.floor(math.min(230, h / 2 - 290) + 0.5))
  end
  return string.format("Alerts %s, scale %d%%, shown %d, click icons %d, restores waiting %d, rebuff slots %d; %s (UI %d tall)",
    Al.Icons() and "icons" or tostring(s.alertLook), math.floor(scale() * 100 + 0.5), shown + clicks, clicks, waiting,
    A.Rebuff and A.Rebuff.slots or 0, where, h)
end

function Al:Init()
  Al.Anchor()
  wasIcons = Al.Icons()
end
