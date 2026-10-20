-- SPDX-License-Identifier: GPL-3.0-or-later
-- Map: no page of its own. The switches of the engine's map files, which draw on the game's world map and minimap
-- (QuestMap.lua, Pins.lua, Minimap.lua, MinimapView.lua). Off, every switch is off; on, every one on. The flags are
-- set and the files told to draw again (their own /qb toggles say so in chat; a Settings row says nothing).
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local M = {}

local function mini() if E.Mini and E.Mini.Invalidate then E.Mini.Invalidate() end end
local function icons(s, on) s.mapIcons = on; if E.QuestMap and E.QuestMap.Update then E.QuestMap:Update() end end
local function pins(s, on) s.pins = on; if E.Pins and E.Pins.Update then E.Pins:Update() end end
function M.Settings(_, col)
  local s = E:Settings()
  col:Head("Map")
  col:Check("Quest icons on the world map", s.mapIcons ~= false, true, function(on) icons(s, on) end)
  col:Check("Route pins on the world map", s.pins ~= false, true, function(on) pins(s, on) end)
  col:Check("Route on the minimap", s.minimapPins ~= false and s.minimapLines ~= false, true, function(on) s.minimapPins, s.minimapLines = on, on; mini() end)
  col:Check("A ! on the minimap for quests you can take", s.minimapGivers == true, true, function(on) s.minimapGivers = on; mini() end)
  col:Check("Minimap far view", s.mmExtended ~= false, true, function(on) s.mmExtended = on; mini() end)
end

function M.Toggle(on)
  if QB.dormant or not E then return end
  local s = E:Settings()
  icons(s, on)
  pins(s, on)
  s.minimapPins, s.minimapLines, s.minimapGivers, s.mmExtended = on, on, on, on
  mini()
  E:MarkDirty()
end

Cute:RegisterModule({ id = "map", addon = ADDON, title = "Map", order = 23,
  notes = "Quest icons and the route on the game's world map and minimap.", settings = M.Settings, onToggle = M.Toggle })
