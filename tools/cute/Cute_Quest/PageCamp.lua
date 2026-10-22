-- SPDX-License-Identifier: GPL-3.0-or-later
-- Reminders (the module keeps its id, camp, and so its saved state): no page of its own. One Settings section: the
-- engine's rows (Remind.ROWS, the same QuestBank's page draws: your buffs, the party's, camp, upkeep, class, dungeons and
-- raids) and the interact light's two. The module is the master switch, Reminders and Buffs on screen (remind.on), and
-- applies at once; each row keeps its own state whatever the module does. Under a row, while one of its reminders is
-- hidden for good (Never), an indented row with it, unticked: a tick shows it again. With QuestBank loaded its
-- reminders are its own: the section greyed, nothing written.
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local Cp = {}
local STYLES = { { "Sparkle", "sparkle" }, { "Light", "light" }, { "Game's", "game" } }
local TITLE = "Reminders"

local function light(s, on) if E.Glow then E.Glow.Set(on) else s.glow.on = on end end
function Cp.Settings(_, col)
  if not E then return QB.NeedSettings(col, TITLE) end
  local s = E:Settings()
  local R = E.Remind
  col:Head(TITLE)
  if not R then col:Note("This QuestBank has no reminders: 6.2.0 or newer has them.") return end
  local own = not QB.dormant
  if not own then col:Note("QuestBank is loaded: its reminders are its own.") end
  local r = R.Settings()
  for _, row in ipairs(R.ROWS) do
    if row.choice then
      local names, current = {}, row.choice[1][1]
      for _, c in ipairs(row.choice) do names[#names + 1] = c[1]; if r[row.key] == c[2] then current = c[1] end end
      if own then
        col:Choice(row.label, names, current, function(v) for _, c in ipairs(row.choice) do if c[1] == v then R.SetRow(row.key, c[2]) end end end)
      else
        col:Check(row.label .. ": " .. current, true, false, function() end)
      end
    else
      col:Check(row.label, r[row.key] ~= false, own, function(on) R.SetRow(row.key, on) end, nil,
        row.note and function(tip) tip:AddLine(row.label, 1, 1, 1); tip:AddLine(row.note, 0.85, 0.85, 0.85, true) end or nil)
    end
    -- (what this row keeps hidden for good: an indented row each, unticked; a tick shows it again)
    if own then
      for _, h in ipairs(R.Hidden(row.key)) do
        col:Check(h[2], false, true, function(on) if on then R.SetNever(h[1], nil, false) end end, "hidden", nil, 20)
      end
    end
  end
  col:Check("Interact light", s.glow.on ~= false, own, function(on) light(s, on) end)
  local names, current = {}, "Sparkle"
  for _, st in ipairs(STYLES) do names[#names + 1] = st[1]; if s.glow.style == st[2] then current = st[1] end end
  if own then
    col:Choice("Light style", names, current, function(v) for _, st in ipairs(STYLES) do if st[1] == v then if E.Glow then E.Glow.SetStyle(st[2]) else s.glow.style = st[2] end end end end)
  else
    col:Check("Light style: " .. current, true, false, function() end)
  end
end

-- the switch: Reminders and Buffs on screen (remind.on) with the box; QB.Follow keeps its value across off and on, and
-- every row keeps its own. The interact light is its own row (and the first-run card's), never the module's. Before
-- the engine's login the flag alone: Remind's first refresh reads it
function Cp.Toggle(on)
  if QB.dormant or not E or not QB.ready then return end
  if not QB.Follow("camp", { "remind.on" }, on) or not E.loginDone then return end
  if E.Remind and E.Remind.Refresh then E.Remind.Refresh() end
end
QB.Toggles.camp = Cp.Toggle

Cute:RegisterModule({ id = "camp", addon = ADDON, title = TITLE, order = 26, group = "quests",
  notes = "Reminders and Buffs on screen: what is worth a click out of a fight.", settings = Cp.Settings, onToggle = Cp.Toggle })
