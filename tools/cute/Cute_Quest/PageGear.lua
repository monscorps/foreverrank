-- SPDX-License-Identifier: GPL-3.0-or-later
-- Gear: the quest window's Gear tab, the engine's Gear page (Gear.lua) on a host frame, its text in Cute's skin. Its one
-- row is in Settings > Dungeons and gear (PageJournal.lua).
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local G = {}
local H = 440

function G.Draw(ui, scroll)
  if not E then return QB.NeedPage(ui, scroll, "gear") end
  local w = scroll:Width()
  local host = Cute.Host(ui, "gear")
  host:ClearAllPoints(); host:SetPoint("TOPLEFT", 0, 0); host:SetSize(w, H)
  if E.Gear then E.Gear.Attach(host, w, H); E.Gear.Refresh() end
  scroll:SetContentHeight(H + 8)
end

Cute:RegisterModule({ id = "gear", addon = ADDON, title = "Gear", order = 25, window = "quests",
  notes = "What you wear and the best upgrade for each slot: a quest reward in reach or a dungeon drop.", page = G.Draw })
