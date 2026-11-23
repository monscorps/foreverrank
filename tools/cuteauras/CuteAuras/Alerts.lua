-- SPDX-License-Identifier: GPL-3.0-or-later
-- The alerts overlay: warnings you can place and size, apart from the bar. Each alert is a card: a game icon (with a
-- countdown's sweep and its seconds in big type), a title in white or the member's class colour, a line under it, a bar
-- at its left in its kind's colour, and a pulse as it comes. Cards stack downward from the overlay's top; the secure
-- rebuff card (Rebuff.lua) takes the top while it shows. A card works in a fight: it is plain art, never the game's
-- secure button (that one is Rebuff's alone). Right-click a card: dismiss it.
--   Alerts.Show(key, spec)  spec = { icon, title, text, class, color, expires, duration, sound, onClick, keep }
--   Alerts.Hide(key)
local _, A = ...
local Al = A.Part("Alerts", { cards = {}, order = {} })
local L = A.Look
local C = L.C

local SIZES = { small = 36, normal = 48, big = 64 }
function Al.IconSize() return SIZES[A.Settings().alertSize or "normal"] or 48 end
local GAP = 6

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
    anchor:SetPoint("TOP", UIParent, "CENTER", 0, 230 / k)
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
  -- (Move mode's handle: a box with its name, dragged out of a fight)
  anchor.box = L.Fill(anchor, "BACKGROUND", C.PINK, 0.18)
  anchor.box:SetAllPoints()
  anchor.box:Hide()
  anchor.label = L.Text(anchor, 12, C.WHITE)
  anchor.label:SetPoint("CENTER")
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
  f.text = L.Text(f, 11, C.INK, 190, "LEFT")
  f.glow = f:CreateTexture(nil, "OVERLAY")
  f.glow:SetColorTexture(1, 1, 1, 1)
  f.glow:SetAlpha(0)
  f:SetScript("OnClick", function(self, button)
    if button == "RightButton" then Al.Hide(self.key) return end
    local spec = self.spec
    if spec and spec.onClick then A.Safe(spec.onClick, "alerts: click")(self) end
  end)
  f:SetScript("OnEnter", function(self)
    local spec = self.spec
    if not (spec and GameTooltip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(spec.title or "", C.WHITE[1], C.WHITE[2], C.WHITE[3])
    if spec.text then GameTooltip:AddLine(spec.text, C.INK[1], C.INK[2], C.INK[3], true) end
    if spec.tip then GameTooltip:AddLine(spec.tip, C.DIM[1], C.DIM[2], C.DIM[3], true) end
    GameTooltip:AddLine("Right-click: dismiss.", C.DIM[1], C.DIM[2], C.DIM[3], true)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() if GameTooltip and GameTooltip:GetOwner() then GameTooltip:Hide() end end)
  return f
end
-- a card's size and parts for the overlay's icon size
local function shape(f)
  local s = Al.IconSize()
  if f.size == s then return end
  f.size = s
  f:SetSize(s + 210, s + 8)
  f.icon:SetSize(s, s)
  f.icon:ClearAllPoints(); f.icon:SetPoint("LEFT", f, "LEFT", 7, 0)
  f.big:SetFont(L.Font(), math.floor(s * 0.42), "OUTLINE")
  f.title:ClearAllPoints(); f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 9, -math.floor(s * 0.08))
  f.text:ClearAllPoints(); f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
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
  local top = 0
  local rb = A.Rebuff and A.Rebuff.button
  if rb and rb:IsShown() then top = (rb:GetHeight() or 0) + GAP end
  local hb = A.Hands and A.Hands.button
  if hb and hb:IsShown() then top = 2 * ((hb:GetHeight() or 0) + GAP) end
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
  if A.Settings().alerts == false then return nil end
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
  layout()
end

-- /cauras test: four cards as they come in play, for placing and sizing the overlay
function Al.Test()
  local t = A.Now()
  local D = A.Data
  Al.Show("test:rebuff", { icon = L.SpellIcon(1243, 135987), title = "Back up: Anna", text = "Power Word: Fortitude. Click to buff them.", class = "MAGE",
    color = C.GROUP, sound = true, life = 15 })
  Al.Show("test:hand", { icon = L.SpellIcon(1022, D.HANDS.protection.icon), title = "Blessing of Protection: Bram", class = "WARRIOR",
    text = "Kings goes back on as it ends.", color = C.PINK, expires = t + 10, duration = 10 })
  Al.Show("test:restore", { icon = L.SpellIcon(20217, D.BLESS.kings.icon), title = "Kings back on Bram", class = "WARRIOR",
    text = "Your Blessing of Protection ended.", color = C.QUEST, life = 15 })
  Al.Show("test:swap", { icon = 134400, title = "Snowy here: Froststrider", text = "Swap in for your boots.", color = C.WHITE, life = 15 })
  A.Say("Test alerts for 15 s. /cauras move to place them, Settings to size them.")
end

function Al:Init()
  Al.Anchor()
end
