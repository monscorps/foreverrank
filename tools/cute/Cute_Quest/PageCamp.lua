-- SPDX-License-Identifier: GPL-3.0-or-later
-- Camp: no page of its own. The camp bar, the missing-buffs banner, the sleeping bag and the sellers (Camp.lua), and
-- the interact light (Glow.lua), as switches. Off, the bar, the banner and the light are off; on, all three on.
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local Cp = {}
local STYLES = { { "Sparkle", "sparkle" }, { "Light", "light" }, { "Game's", "game" } }

local function light(s, on) if E.Glow then E.Glow.Set(on) else s.glow.on = on end end
function Cp.Settings(_, col)
  local s = E:Settings()
  col:Head("Camp")
  col:Check("Camp bar", s.campBar ~= false, true, function(on) s.campBar = on end)
  col:Check("Missing buffs when you leave town", s.remind.buffs ~= false, true, function(on) s.remind.buffs = on end)
  col:Check("Sleeping bag", s.remind.bag ~= false, true, function(on) s.remind.bag = on end)
  col:Check("Sellers of camp goods", s.remind.wood ~= false, true, function(on) s.remind.wood = on end)
  col:Check("Interact light", s.glow.on ~= false, true, function(on) light(s, on) end)
  local names, current = {}, "Sparkle"
  for _, st in ipairs(STYLES) do names[#names + 1] = st[1]; if s.glow.style == st[2] then current = st[1] end end
  col:Choice("Light style", names, current, function(v) for _, st in ipairs(STYLES) do if st[1] == v then if E.Glow then E.Glow.SetStyle(st[2]) else s.glow.style = st[2] end end end end)
end

function Cp.Toggle(on)
  if QB.dormant or not E then return end
  local s = E:Settings()
  s.campBar, s.remind.buffs = on, on
  light(s, on)
end

Cute:RegisterModule({ id = "camp", addon = ADDON, title = "Camp", order = 26,
  notes = "The camp bar, the missing-buffs banner and the interact light.", settings = Cp.Settings, onToggle = Cp.Toggle })
