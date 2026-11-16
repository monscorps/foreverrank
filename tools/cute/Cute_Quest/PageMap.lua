-- SPDX-License-Identifier: GPL-3.0-or-later
-- Map: the Map module, the window M (CuteMapFrame, MapWin.lua: QuestBank's map canvas with our list beside it), and the
-- switches of the engine's files that draw on the game's world map (QuestMap.lua, Pins.lua): off, the window goes, M
-- is the game's and both switches are off; on, M opens Cute's map and each switch is as its row says. The minimap's rows
-- are the Route tab's (the base). The flags are set and the files told to draw again (a Settings row says nothing).
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local M = {}

local function mini() if E.Mini and E.Mini.Invalidate then E.Mini.Invalidate() end end
local function icons(s, on) s.mapIcons = on; if E.QuestMap and E.QuestMap.Update then E.QuestMap:Update() end end
local function pins(s, on) s.pins = on; if E.Pins and E.Pins.Update then E.Pins:Update() end end
-- (the window's map drawn again: its finds layer, and the list beside it)
local function finds()
  local MP = E.MapPage
  if MP and MP.finds and MP.canvas and MP.canvas:IsVisible() then MP.finds:RefreshAllData() end
  Cute.Refresh()
end
function M.Settings(_, col)
  if not E then return QB.NeedSettings(col, "Map") end
  local s = E:Settings()
  col:Head("Map")
  -- (6.1.1) grey quests' ! on the world map and the minimap only when asked (the engine's QuestMap.lua givers)
  col:Check("Show low-level quests", s.mapLowLevel == true, true, function(on) s.mapLowLevel = on; if E.QuestMap and E.QuestMap.Update then E.QuestMap:Update() end; mini() end)
  col:Note("Quests the game calls trivial. Their level number's colour says how low.")
  -- (sub-project F) the Map window's finds layer and its list's Finds here (MapPage.lua MP.Finds: what players learned)
  col:Check("Finds on the map", s.mapFinds ~= false, true, function(on) s.mapFinds = (not on) and false or nil; finds() end, nil, function(tip)
    tip:AddLine("Finds on the map", 1, 1, 1)
    tip:AddLine("Books, locks, chests and rares that you or other players found, on Cute's map. Never a book's text or where a key leads.", 0.85, 0.85, 0.85, true)
  end)
  col:Check("Our icons on the game's map", s.mapIcons ~= false and s.pins ~= false, true, function(on) icons(s, on); pins(s, on) end)
  -- (0.9.9) the icons' size against the game's own pins (the engine's Pins.lua mapIconPct, QuestBank's Settings has the
  -- same button): the game's own size on a fresh install; where a click lands stays the game's size either way
  local pct = tonumber(s.mapIconPct) or 100
  local cur = pct <= 50 and "Half size" or pct < 100 and "Three quarters" or "Game's size"
  col:Choice("Their size", { "Half size", "Three quarters", "Game's size" }, cur, function(v)
    s.mapIconPct = v == "Half size" and 50 or v == "Three quarters" and 75 or 100
    if E.Pins and E.Pins.Update then E.Pins:Update() end
    if E.QuestMap and E.QuestMap.Update then E.QuestMap:Update() end
  end)
  col:Note("Our !, ? and route stops on the game's map and on M, drawn at the game's own size or smaller. Where a click lands stays the game's size.")
end

-- the switch: the engine's map flags with the box (QB.Follow keeps a row's choice across off and on), and the engine's
-- Map page (mapPage: the engine's own /qb map and its Map tab, which the Bridge sends to this window). Before the
-- engine's login the flags alone: its files read them as they start
function M.Toggle(on)
  if QB.dormant or not E or not QB.ready then return end
  E:Settings().mapPage = on and true or false
  if not QB.Follow("map", QB.MAP_FLAGS, on) or not E.loginDone then return end
  if E.QuestMap and E.QuestMap.Update then E.QuestMap:Update() end
  if E.Pins and E.Pins.Update then E.Pins:Update() end
  mini()
  E:MarkDirty()
end
QB.Toggles.map = M.Toggle

local function redraw() Cute.Refresh() end
-- (with the addon QuestBank loaded this copy sleeps, and QuestBank's own Map page is its map: no window, so M stays the
-- game's: Keys.lua holds a key only for a window with a page)
Cute:RegisterModule({ id = "map", addon = ADDON, title = "Map", order = 23, group = "quests", window = "map",
  notes = "Cute's map on M, our quest list beside it.", page = (not QB.dormant) and function(ui, scroll) QB.MapWin.Draw(ui, scroll) end or nil,
  settings = M.Settings, onToggle = M.Toggle,
  events = { QUEST_LOG_UPDATE = redraw, QUEST_ACCEPTED = redraw, QUEST_TURNED_IN = redraw, PLAYER_LEVEL_UP = redraw,
    PLAYER_REGEN_DISABLED = redraw, PLAYER_REGEN_ENABLED = redraw } })
