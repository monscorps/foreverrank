-- SPDX-License-Identifier: GPL-3.0-or-later
-- Camp: no page of its own. The camp bar and the missing-buffs banner with the party's row (Camp.lua) and the interact
-- light (Glow.lua), as switches. Off, the bar, the banner, the party's row and the light are off; on, each as its row
-- says.
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local Cp = {}
local STYLES = { { "Sparkle", "sparkle" }, { "Light", "light" }, { "Game's", "game" } }

local function light(s, on) if E.Glow then E.Glow.Set(on) else s.glow.on = on end end
function Cp.Settings(_, col)
  if not E then return QB.NeedSettings(col, "Camp") end
  local s = E:Settings()
  col:Head("Camp")
  col:Check("Camp bar", s.campBar ~= false, true, function(on) s.campBar = on end)
  col:Check("Missing buffs", s.remind.buffs ~= false, true, function(on) s.remind.buffs = on; if E.Camp and E.Camp.Refresh then E.Camp.Refresh() end end)
  col:Check("Party members' buffs", s.remind.party ~= false, true, function(on) s.remind.party = on; if E.Camp and E.Camp.Refresh then E.Camp.Refresh() end end)
  col:Check("Interact light", s.glow.on ~= false, true, function(on) light(s, on) end)
  local names, current = {}, "Sparkle"
  for _, st in ipairs(STYLES) do names[#names + 1] = st[1]; if s.glow.style == st[2] then current = st[1] end end
  col:Choice("Light style", names, current, function(v) for _, st in ipairs(STYLES) do if st[1] == v then if E.Glow then E.Glow.SetStyle(st[2]) else s.glow.style = st[2] end end end end)
end

-- the switch: the bar, the banner, the party's row and the light with the box (QB.Follow keeps a row's choice across off and on); the
-- light is set through Glow.Set, which puts the game's settings back as it goes off. Before the engine's login the
-- flags alone: Glow:Init and Camp:Init read them
function Cp.Toggle(on)
  if QB.dormant or not E or not QB.ready then return end
  local s = E:Settings()
  local lit = s.glow.on == true
  if not QB.Follow("camp", { "campBar", "remind.buffs", "remind.party", "glow.on" }, on) or not E.loginDone then return end
  if E.Glow and (s.glow.on == true) ~= lit then E.Glow.Set(s.glow.on == true) end
  if E.Camp and E.Camp.Refresh then E.Camp.Refresh() end
end
QB.Toggles.camp = Cp.Toggle

Cute:RegisterModule({ id = "camp", addon = ADDON, title = "Camp", order = 26,
  notes = "The camp bar, the missing-buffs banner and the interact light.", settings = Cp.Settings, onToggle = Cp.Toggle })
