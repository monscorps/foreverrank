-- SPDX-License-Identifier: GPL-3.0-or-later
-- Journal: the engine's Dungeon Journal (DungeonMap.lua) on a host frame inside Cute's scroll area, its cover and floor
-- art as they are. Its four kinds are the band's chips: on, white; off, muted; a click flips one. No section
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local J = {}
local H = 468
local KINDS = { { "boss", "Bosses" }, { "rare", "Rares" }, { "trash", "Trash" }, { "other", "Chests and events" } }

function J.Draw(ui, scroll)
  if not E then return QB.NeedPage(ui, scroll, "journal") end
  local K, ROW = ui.COLORS, ui.ROW
  local w = scroll:Width()
  local s = E:Settings()
  local bw = math.min(160, math.floor((w - 18) / #KINDS))
  for i, k in ipairs(KINDS) do
    local b = ui.bandButtons:Get()
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", (i - 1) * (bw + 6), -3); b:SetWidth(bw)
    b:SetLabel(k[2]); b:SetOn(true)
    local on = s.djShow[k[1]] == true
    ui.Color(b.label, on and K.WHITE or K.MUTE)
    b:SetScript("OnClick", Cute.Safe(function() s.djShow[k[1]] = s.djShow[k[1]] ~= true; if E.DMap then E.DMap.Refresh() end; Cute.Refresh() end, "journal: " .. k[1]))
    -- (a pooled band button may come from Settings' steps, with their tooltip)
    b:SetScript("OnEnter", nil); b:SetScript("OnLeave", nil)
  end
  ui:SetBand(ROW + 8)
  local host = Cute.Host(ui, "journal")
  host:ClearAllPoints(); host:SetPoint("TOPLEFT", 0, 0); host:SetSize(w, H)
  if E.DMap then E.DMap.Attach(host, w, H); E.DMap.Refresh() end
  scroll:SetContentHeight(H + 8)
end

Cute:RegisterModule({ id = "journal", addon = ADDON, title = "Journal", order = 24,
  notes = "Every dungeon: its bosses, their recorded loot, its quests, its floors.", page = J.Draw })
