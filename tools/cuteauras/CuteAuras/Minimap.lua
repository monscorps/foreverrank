-- SPDX-License-Identifier: GPL-3.0-or-later
-- The minimap button (the owner, 2026-11-23): the round one every addon has, as Cute's (Cute/UI.lua): the emblem cut
-- round on the minimap's dark disc under the tracking ring, dragged around the minimap's edge (its angle kept,
-- settings.minimapPos). The emblem is Cute's girl on a rose aura, not Cute's teal (the owner, 2026-11-24: the two
-- buttons sit side by side; tools/cuteauras/make_logo.py makes it from Cute's). A click: the window. A right-click: a menu to its tabs, the test alerts and Move. Settings'
-- "Button on the minimap" (under Minimap) or /cauras minimap shows or hides it.
local _, A = ...
local Mm = A.Part("Minimap", {})
local L = A.Look

local RING = "Interface\\Minimap\\MiniMap-TrackingBorder"
local DISC = "Interface\\Minimap\\UI-Minimap-Background"
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GLOW = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
local LOGO = "Interface\\AddOns\\CuteAuras\\art\\logo.png" -- (a .png needs its extension in the path on this client)

local button
local function tex(b, layer, file, w, h)
  local t = b:CreateTexture(nil, layer)
  t:SetTexture(file)
  t:SetSize(w, h)
  return t
end
-- around the minimap's edge: a circle on the round minimap, the square's edge where a minimap addon made it square
local function place()
  if not (button and Minimap) then return end
  local angle = math.rad(tonumber(A.Settings().minimapPos) or 245)
  local r = (Minimap:GetWidth() or 140) / 2 + 10
  local x, y = math.cos(angle) * r, math.sin(angle) * r
  local shape = type(GetMinimapShape) == "function" and A.Plain(select(2, pcall(GetMinimapShape))) or "ROUND"
  if shape ~= "ROUND" and type(shape) == "string" then
    local d = r * 1.4142
    x = math.max(-r, math.min(r, math.cos(angle) * d))
    y = math.max(-r, math.min(r, math.sin(angle) * d))
  end
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end
Mm.Place = place

local function menu(owner)
  if type(MenuUtil) ~= "table" or type(MenuUtil.CreateContextMenu) ~= "function" then return end
  -- (each entry runs later, from the game's menu: wrapped on its own, so an error lands in /cauras errors)
  local function entry(root, text, fn) root:CreateButton(text, A.Safe(fn, "minimap menu: " .. text)) end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Cute Auras")
    entry(root, "Settings", function() A.Window.Open("settings") end)
    entry(root, "Consumables", function() A.Window.Open("consume") end)
    entry(root, "Blessings", function() A.Window.Open("blessings") end)
    entry(root, "Biome gear", function() A.Window.Open("gear") end)
    root:CreateDivider()
    entry(root, "Test the alerts", function() A.Window.Test() end)
    entry(root, "Move the bar and alerts", function() A.Window.Move(true) end)
  end)
end

local function build()
  if button or not Minimap then return end
  local b = CreateFrame("Button", "CuteAurasMinimapButton", Minimap)
  button = b
  b:SetSize(32, 32)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetMovable(true)
  local disc = tex(b, "BACKGROUND", DISC, 20, 20)
  disc:SetPoint("TOPLEFT", 7, -5)
  local icon = tex(b, "ARTWORK", LOGO, 20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  if b.CreateMaskTexture and icon.AddMaskTexture then
    local mask = b:CreateMaskTexture()
    mask:SetTexture(ROUND, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    pcall(icon.AddMaskTexture, icon, mask)
  else
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  end
  local ring = tex(b, "OVERLAY", RING, 54, 54)
  ring:SetPoint("TOPLEFT")
  b.icon, b.ring = icon, ring
  b:SetHighlightTexture(GLOW, "ADD")
  local drag = A.Safe(function()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    if not (mx and cx and scale) then return end
    cx, cy = cx / scale, cy / scale
    A.Settings().minimapPos = math.deg(math.atan2(cy - my, cx - mx))
    place()
  end, "minimap button: drag")
  b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", drag) end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnClick", A.Safe(function(self, which)
    if which == "RightButton" then menu(self) else A.Window.Toggle() end
  end, "minimap button"))
  b:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Cute Auras", 1, 0.6, 0.84)
    GameTooltip:AddLine("Click: settings, consumables, blessings and biome gear. Right-click: menu. Drag: move.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  place()
end
-- shown or hidden as Settings says
function Mm.Update()
  if A.Settings().minimap == false then if button then button:Hide() end return end
  build()
  if button then button:Show(); place() end
end

function Mm:Init()
  Mm.Update()
end
