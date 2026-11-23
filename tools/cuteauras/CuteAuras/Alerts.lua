-- SPDX-License-Identifier: GPL-3.0-or-later
-- The alerts overlay: warnings you can place and size, apart from the bar. Each alert is a card: a game icon (with a
-- countdown's sweep and its seconds in big type), a title in white or the member's class colour, a line under it (two
-- lines at most), a bar at its left in its kind's colour, and a pulse as it comes. Cards stack downward from the
-- overlay's top; the secure cards (Hands' restore, Rebuff's rebuff) take the top while they show. A card works in a
-- fight: it is plain art, never the game's secure button. Right-click a card: dismiss it (onDismiss runs first).
-- "Alerts on screen" off: no card at all, the secure ones too.
--   Alerts.Show(key, spec)  spec = { icon, title, text, tip, class, color, expires, duration, sound, onClick, onDismiss, keep }
--   Alerts.Hide(key)
local _, A = ...
local Al = A.Part("Alerts", { cards = {}, order = {} })
local L = A.Look
local C = L.C

local SIZES = { small = 36, normal = 48, big = 64 }
function Al.IconSize() return SIZES[A.Settings().alertSize or "normal"] or 48 end
local GAP = 6
Al.GAP = GAP
-- a card's type: Small is smaller words too (two lines still, so a name and its line read whole), Big bigger
local FONTS = { small = { 12, 10 }, normal = { 14, 11 }, big = { 16, 12 } }
function Al.Fonts() local f = FONTS[A.Settings().alertSize or "normal"] or FONTS.normal; return f[1], f[2] end
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
-- a card
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
-- a card's tooltip, the art cards' and the secure ones' alike: its whole title and line (a card cuts them only past its
-- room), a tip, what a click does
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
-- a card's size and parts for the overlay's icon size, the three kinds alike: the icon at the left, the title at the
-- card's top, the line under it (a secure card's own: shaped out of a fight only)
function Al.ShapeCard(f, s)
  f:SetSize(s + 210, Al.CardHeight())
  local t, x = Al.Fonts()
  f.title:SetFont(L.Font(), t, "OUTLINE")
  f.text:SetFont(L.Font(), x, "OUTLINE")
  f.icon:SetSize(s, s)
  f.icon:ClearAllPoints(); f.icon:SetPoint("LEFT", f, "LEFT", 7, 0)
  f.title:ClearAllPoints(); f.title:SetPoint("TOPLEFT", f, "TOPLEFT", s + 16, -6)
  f.text:ClearAllPoints(); f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
end
local function shape(f)
  local s = Al.IconSize()
  if f.size == s then return end
  f.size = s
  Al.ShapeCard(f, s)
  f.big:SetFont(L.Font(), math.floor(s * 0.42), "OUTLINE")
  f.glow:ClearAllPoints(); f.glow:SetAllPoints(f.icon)
end
Al.Shape = shape

local function paint(f, spec)
  shape(f)
  L.Art(f.icon.icon, spec.icon or 134400)
  f.icon.icon:SetDesaturated(spec.dim == true)
  f.title:SetText(spec.title or "")
  if spec.class then f.title:SetTextColor(L.ClassColor(spec.class)) else f.title:SetTextColor(C.WHITE[1], C.WHITE[2], C.WHITE[3]) end
  f.text:SetText(spec.text or "")
  local col = spec.color or C.QUEST
  f.side:SetColorTexture(col[1], col[2], col[3], 1)
  if spec.expires and spec.duration and spec.duration > 0 then
    f.icon.cd:SetCooldown(spec.expires - spec.duration, spec.duration)
  else
    f.icon.cd:SetCooldown(0, 0)
  end
  f.big:SetText("")
end

----------------------------------------------------------------------------
-- the stack, the clock (countdowns, pulses, ends) and the sound
----------------------------------------------------------------------------
local clock
local function layout()
  -- (the art cards under the secure ones shown: Hands' restore at the top, Rebuff's card under it or at the top)
  local top = 0
  local rb = A.Rebuff and A.Rebuff.button
  if rb and rb:IsShown() then top = top + (rb:GetHeight() or 0) + GAP end
  local hb = A.Hands and A.Hands.button
  if hb and hb:IsShown() then top = top + (hb:GetHeight() or 0) + GAP end
  for _, key in ipairs(Al.order) do
    local f = Al.cards[key]
    if f then
      f:ClearAllPoints()
      f:SetPoint("TOP", Al.Anchor(), "TOP", 0, -top)
      top = top + (f:GetHeight() or 0) + GAP
    end
  end
end
Al.Layout = layout
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
  for key, f in pairs(Al.cards) do
    any = true
    local spec = f.spec
    if spec.expires then
      local left = spec.expires - t
      if left <= 0 then
        if spec.onEnd then A.Safe(spec.onEnd, "alerts: end")(spec) end
        if Al.cards[key] == f and f.spec == spec then remove(key) end
      else
        f.big:SetText(left >= 10 and tostring(math.floor(left)) or string.format("%.1f", left))
      end
    elseif spec.until_ and t >= spec.until_ then
      remove(key)
    end
    -- (the pulse: the first 1.5 s of a card, a white flash over its icon that fades three times)
    local age = t - (f.born or t)
    if age < 1.5 then f.glow:SetAlpha(0.45 * math.abs(math.sin(age * math.pi * 2))) elseif f.glow:GetAlpha() > 0 then f.glow:SetAlpha(0) end
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
  if not f then
    f = table.remove(pool) or newCard()
    Al.cards[key] = f
    table.insert(Al.order, 1, key)
    f.born = A.Now()
  end
  f.key, f.spec = key, spec
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
-- the overlay's size changed (Settings): every card again
function Al.Restyle()
  for _, f in pairs(Al.cards) do f.size = nil; paint(f, f.spec) end
  if A.Rebuff and A.Rebuff.Restyle then A.Rebuff.Restyle() end
  if A.Hands and A.Hands.Refresh then A.Hands.Refresh() end
  layout()
end

-- /cauras test: the three cards as they come in play, their words as the game's own make them (long names: a card
-- that fits these fits play), for placing and sizing the overlay
function Al.Test()
  if not Al.On() then A.Say("Alerts are off: tick Alerts on screen in Settings first.") return end
  local t = A.Now()
  local D, H, Rb = A.Data, A.Hands, A.Rebuff
  local name = "Bramblewoode"
  local fort = L.SpellName(1243, "Power Word: Fortitude")
  local title, text = Rb.Words(name, fort, "cast")
  Al.Show("test:rebuff", { icon = L.SpellIcon(1243, 135987), title = title, text = text, class = "MAGE", color = C.GROUP, sound = true, life = 15 })
  title, text = H.HandWords(name, L.SpellName(1022, D.HANDS.protection.name), "kings")
  Al.Show("test:hand", { icon = L.SpellIcon(1022, D.HANDS.protection.icon), title = title, class = "WARRIOR", text = text, color = C.PINK,
    expires = t + 10, duration = 10 })
  title, text = H.RestoreWords(name, "kings", L.SpellName(1022, D.HANDS.protection.name), "fight", true)
  Al.Show("test:restore", { icon = L.SpellIcon(20217, D.BLESS.kings.icon), title = title, class = "WARRIOR", text = text, color = C.QUEST, life = 15 })
  A.Say("Test alerts for 15 s. /cauras move to place them, Settings to size them.")
end

function Al:Init()
  Al.Anchor()
end
