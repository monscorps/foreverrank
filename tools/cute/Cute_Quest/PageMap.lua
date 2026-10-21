-- SPDX-License-Identifier: GPL-3.0-or-later
-- Map: no page of its own until Cute's map window. The switches of the engine's files that draw on the game's world
-- map (QuestMap.lua, Pins.lua): off, both are off; on, each as its row says. The minimap's rows are the Route tab's
-- (the base). The flags are set and the files told to draw again (a Settings row says nothing).
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
  -- (6.1.1) grey quests' ! on the world map and the minimap only when asked (the engine's QuestMap.lua givers)
  col:Check("Show low-level quests", s.mapLowLevel == true, true, function(on) s.mapLowLevel = on; if E.QuestMap and E.QuestMap.Update then E.QuestMap:Update() end; mini() end)
  col:Note("Quests the game calls trivial. Their level number's colour says how low.")
  col:Check("Our icons on the game's map", s.mapIcons ~= false and s.pins ~= false, true, function(on) icons(s, on); pins(s, on) end)
end

-- the switch: the engine's map flags with the box (QB.Follow keeps a row's choice across off and on). Before the
-- engine's login the flags alone: its files read them as they start
function M.Toggle(on)
  if QB.dormant or not E or not QB.ready then return end
  if not QB.Follow("map", QB.MAP_FLAGS, on) or not E.loginDone then return end
  if E.QuestMap and E.QuestMap.Update then E.QuestMap:Update() end
  if E.Pins and E.Pins.Update then E.Pins:Update() end
  mini()
  E:MarkDirty()
end
QB.Toggles.map = M.Toggle

Cute:RegisterModule({ id = "map", addon = ADDON, title = "Map", order = 23, group = "quests",
  notes = "Quest icons and the route on the game's world map.", settings = M.Settings, onToggle = M.Toggle })
