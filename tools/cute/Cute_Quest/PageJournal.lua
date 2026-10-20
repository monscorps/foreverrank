-- SPDX-License-Identifier: GPL-3.0-or-later
-- Journal: the engine's Dungeon Journal (DungeonMap.lua) on a host frame inside Cute's scroll area, its cover and floor
-- art as they are. Its four kinds as the section.
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local J = {}
local H = 468

function J.Draw(ui, scroll)
  if not E then return QB.NeedPage(ui, scroll, "journal") end
  local w = scroll:Width()
  local host = Cute.Host(ui, "journal")
  host:ClearAllPoints(); host:SetPoint("TOPLEFT", 0, 0); host:SetSize(w, H)
  if E.DMap then E.DMap.Attach(host, w, H); E.DMap.Refresh() end
  scroll:SetContentHeight(H + 8)
end

local KINDS = { { "boss", "Bosses" }, { "rare", "Rares" }, { "trash", "Trash" }, { "other", "Chests and events" } }
function J.Settings(_, col)
  if not E then return QB.NeedSettings(col, "Journal") end
  local s = E:Settings()
  col:Head("Journal")
  for _, k in ipairs(KINDS) do
    col:Check(k[2], s.djShow[k[1]] == true, true, function(on) s.djShow[k[1]] = on; if E.DMap then E.DMap.Refresh() end end)
  end
end

Cute:RegisterModule({ id = "journal", addon = ADDON, title = "Journal", order = 24,
  notes = "Every dungeon: its bosses, their recorded loot, its quests, its floors.", page = J.Draw, settings = J.Settings })
