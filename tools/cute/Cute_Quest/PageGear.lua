-- SPDX-License-Identifier: GPL-3.0-or-later
-- Gear: the engine's Gear page (Gear.lua) on a host frame, its text in Cute's skin. One setting.
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local G = {}
local H = 440

function G.Draw(ui, scroll)
  local w = scroll:Width()
  local host = Cute.Host(ui, "gear")
  host:ClearAllPoints(); host:SetPoint("TOPLEFT", 0, 0); host:SetSize(w, H)
  if E.Gear then E.Gear.Attach(host, w, H); E.Gear.Refresh() end
  scroll:SetContentHeight(H + 8)
end

function G.Settings(_, col)
  local s = E:Settings()
  col:Head("Gear")
  col:Check("Quests up to 2 levels ahead", s.finderAhead == true, true, function(on) s.finderAhead = on; if E.Gear and E.Gear.RefreshSoon then E.Gear.RefreshSoon() end end)
  col:Note("An upgrade is a quest reward in reach or a dungeon drop at your level, judged for your class and skills.")
end

Cute:RegisterModule({ id = "gear", addon = ADDON, title = "Gear", order = 25,
  notes = "What you wear and the best upgrade for each slot: a quest reward in reach or a dungeon drop.", page = G.Draw, settings = G.Settings })
