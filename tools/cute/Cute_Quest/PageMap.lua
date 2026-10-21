-- SPDX-License-Identifier: GPL-3.0-or-later
-- Map: no page of its own. The switches of the engine's map files, which draw on the game's world map and minimap
-- (QuestMap.lua, Pins.lua, Minimap.lua, MinimapView.lua). Off, every switch is off; on, each as its row says. The
-- flags are set and the files told to draw again (their own /qb toggles say so in chat; a Settings row says nothing).
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local M = {}

local function mini() if E.Mini and E.Mini.Invalidate then E.Mini.Invalidate() end end
local function icons(s, on) s.mapIcons = on; if E.QuestMap and E.QuestMap.Update then E.QuestMap:Update() end end
local function pins(s, on) s.pins = on; if E.Pins and E.Pins.Update then E.Pins:Update() end end
function M.Settings(_, col)
  if not E then return QB.NeedSettings(col, "Map") end
  local s = E:Settings()
  col:Head("Map")
  col:Check("Quest icons on the world map", s.mapIcons ~= false, true, function(on) icons(s, on) end)
  col:Check("Route pins on the world map", s.pins ~= false, true, function(on) pins(s, on) end)
  col:Check("Route on the minimap", s.minimapPins ~= false and s.minimapLines ~= false, true, function(on) s.minimapPins, s.minimapLines = on, on; mini() end)
  col:Check("A ! on the minimap for quests you can take", s.minimapGivers == true, true, function(on) s.minimapGivers = on; mini() end)
  -- (6.1.1) grey quests' ! on the world map and the minimap only when asked (the engine's QuestMap.lua givers)
  col:Check("Low-level quests", s.mapLowLevel == true, true, function(on) s.mapLowLevel = on; if E.QuestMap and E.QuestMap.Update then E.QuestMap:Update() end; mini() end)
  -- (6.1.1) one stroke, you to where the arrow leads, unless the whole route is asked (Minimap.lua, MapPage.lua)
  col:Check("Show the whole route", s.wholeRoute == true, true, function(on) s.wholeRoute = on; mini() end)
end

-- the switch: the engine's map flags with the box (QB.Follow keeps a row's choice across off and on). Before the
-- engine's login the flags alone: its files read them as they start
function M.Toggle(on)
  if QB.dormant or not E or not QB.ready then return end
  if not QB.Follow("map", { "mapIcons", "pins", "minimapPins", "minimapLines", "minimapGivers", "mmExtended" }, on) or not E.loginDone then return end
  if E.QuestMap and E.QuestMap.Update then E.QuestMap:Update() end
  if E.Pins and E.Pins.Update then E.Pins:Update() end
  mini()
  E:MarkDirty()
end
QB.Toggles.map = M.Toggle

Cute:RegisterModule({ id = "map", addon = ADDON, title = "Map", order = 23,
  notes = "Quest icons and the route on the game's world map and minimap.", settings = M.Settings, onToggle = M.Toggle })
