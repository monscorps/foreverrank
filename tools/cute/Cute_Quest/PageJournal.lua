-- SPDX-License-Identifier: GPL-3.0-or-later
-- Dungeons (the module keeps its 0.7 id, journal): the quest window's Dungeons tab. Across its top the guild's pick as a
-- card (Cute's Guide.lua, the windows' pattern C, the Quests tab's own), then the engine's Dungeon Journal
-- (DungeonMap.lua) on a host frame inside the window's scroll area, its cover and floor art as they are, opened on the
-- pick the first time; under Cute's skin its tiles carry their range on a plate in its colours and the open one a white
-- edge. Its four kinds are the band's chips (on, white; off, muted; a click flips one) and the rows of Settings >
-- Dungeons and gear, which holds the Gear tab's row too
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
  -- the guild's pick across the top
  local top = 0
  local pick = Cute.Host(ui, "journalPick")
  pick:ClearAllPoints(); pick:SetPoint("TOPLEFT", 0, 0)
  if Cute.Guide and Cute.Guide.DrawPick then
    top = Cute.Guide.DrawPick(ui, pick, 0, w, false) + 8
    pick:SetSize(w, top)
  end
  local host = Cute.Host(ui, "journal")
  host:ClearAllPoints(); host:SetPoint("TOPLEFT", 0, -top); host:SetSize(w, H)
  if E.DMap then
    E.DMap.Attach(host, w, H)
    -- (opened on the pick the first time the tab draws: the journal's own Fill, never its Open, which opens a window)
    local shown = pick.pickShown
    local cat = not J.opened and shown and shown.card and E.DMap.Find and E.DMap.Find(shown.card.d.name)
    if cat and E.DMap.Fill then J.opened = true; E.DMap.Fill(cat, "map") end
    E.DMap.Refresh()
  end
  scroll:SetContentHeight(top + H + 8)
end

Cute:RegisterModule({ id = "journal", addon = ADDON, title = "Dungeons", order = 24, window = "quests",
  notes = "Every dungeon: its bosses, their recorded loot, its quests, its floors.", page = J.Draw })

-- Settings > Dungeons and gear, while either tab is on: the journal's kinds in one wrapping row, the gear finder's reach
if E then
  Cute.AddSection({ id = "dungeons", title = "Dungeons and gear", group = "quests", order = 24,
    shown = function() return Cute.ModuleOn("journal") or Cute.ModuleOn("gear") end,
    draw = function(_, col)
      local s = E:Settings()
      col:Head("Dungeons and gear")
      local names = {}
      for _, k in ipairs(KINDS) do names[#names + 1] = k[2] end
      col:Checks("Journal shows", names, function(i) return s.djShow[KINDS[i][1]] == true end,
        function(i, on) s.djShow[KINDS[i][1]] = on; if E.DMap then E.DMap.Refresh() end; Cute.Refresh() end)
      col:Check("Gear: quests up to 2 levels ahead", s.finderAhead == true, true, function(on) s.finderAhead = on; if E.Gear and E.Gear.RefreshSoon then E.Gear.RefreshSoon() end end)
    end })
end
