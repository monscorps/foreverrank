-- SPDX-License-Identifier: GPL-3.0-or-later
-- Reminders (the module keeps its id, camp, and so its saved state): no page of its own. One Settings section: the
-- engine's rows (Remind.ROWS, the same QuestBank's page draws: your buffs, the party's, camp, upkeep, class, dungeons and
-- raids) and the interact light's two. The module is the master switch, Reminders and Buffs on screen (remind.on), and
-- applies at once; each row keeps its own state whatever the module does. A row's note under it, DIM; under a row,
-- while it keeps reminders hidden for good (Never), one DIM line naming them with its Show, which brings that row's
-- back (the windows design's notes, the reminders design's "Hidden: Eat [Show]"). With QuestBank loaded its
-- reminders are its own: the section greyed, nothing written. (The final audit) while the module is off, the light's two
-- rows have a section of their own, Interact light: the light is never the module's (the reminders design's section 7),
-- so a light left on keeps its switch, as the first-run card's "Settings puts them back" says
local ADDON, QB = ...
local Cute = Cute
local E = QB.Engine
local Cp = {}
local STYLES = { { "Sparkle", "sparkle" }, { "Light", "light" }, { "Game's", "game" } }
local TITLE = "Reminders"

-- (merge3) the player's choice: the setup card's light row starts from it now (Bridge.lua's cuteLightAsks cleared)
local function light(s, on) s.cuteLightAsks = nil; if E.Glow then E.Glow.Set(on) else s.glow.on = on end end
-- the light's two rows, under Reminders' or in their own section
local function drawLight(col, s, own)
  col:Check("Interact light", s.glow.on ~= false, own, function(on) light(s, on) end)
  local names, current = {}, "Sparkle"
  for _, st in ipairs(STYLES) do names[#names + 1] = st[1]; if s.glow.style == st[2] then current = st[1] end end
  if own then
    col:Choice("Light style", names, current, function(v) for _, st in ipairs(STYLES) do if st[1] == v then if E.Glow then E.Glow.SetStyle(st[2]) else s.glow.style = st[2] end end end end)
  else
    col:Check("Light style: " .. current, true, false, function() end)
  end
end
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
      col:Check(row.label, r[row.key] ~= false, own, function(on) R.SetRow(row.key, on) end)
    end
    if row.note then col:Note(row.note) end
    -- (what this row keeps hidden for good, on one line, and its Show)
    local hidden = own and R.Hidden(row.key) or nil
    if hidden and #hidden > 0 then
      local names = {}
      for i, h in ipairs(hidden) do names[i] = h[2] end
      col:Hidden("Hidden: " .. table.concat(names, ", "), function() for _, h in ipairs(hidden) do R.SetNever(h[1], nil, false) end end)
    end
  end
  drawLight(col, s, own)
end

-- the switch: Reminders and Buffs on screen (remind.on) with the box; QB.Follow keeps its value across off and on, and
-- every row keeps its own. The interact light is its own row (and the first-run card's), never the module's. Before
-- the engine's login the flag alone: Remind's first refresh reads it. (The hud review) the module is the only master:
-- on, Reminders are on screen whatever was left off before (a 0.7 save's camp bar switch, the first-run card's
-- unticked row, a mover's Hide), so the box and the screen never part
function Cp.Toggle(on)
  if QB.dormant or not E or not QB.ready then return end
  local changed = QB.Follow("camp", { "remind.on" }, on)
  if on and E.Remind and E.Remind.Settings then
    local r = E.Remind.Settings()
    if r.on == false then r.on = true; E:Settings().campBar = true; changed = true end
  end
  if not changed or not E.loginDone then return end
  if E.Remind and E.Remind.Refresh then E.Remind.Refresh() end
end
QB.Toggles.camp = Cp.Toggle

-- (on by default, the one module addon's module Cute lets start on, Modules.lua: a character who answers the first-run
-- card "Not now" still gets Reminders; the light stays its own, off until its row is answered, Bridge.lua)
Cute:RegisterModule({ id = "camp", addon = ADDON, title = TITLE, order = 26, group = "quests", default = true,
  notes = "Reminders and Buffs on screen: what is worth a click out of a fight.", settings = Cp.Settings, onToggle = Cp.Toggle })

-- Settings > Interact light, while Reminders is off: the light's two rows (order 27, where Reminders' section was)
if E then
  Cute.AddSection({ id = "light", title = "Interact light", group = "quests", order = 27,
    shown = function() return not Cute.ModuleOn("camp") end,
    draw = function(_, col)
      local s = E:Settings()
      col:Head("Interact light")
      if type(s.glow) ~= "table" then col:Note("This QuestBank has no interact light.") return end
      local own = not QB.dormant
      if not own then col:Note("QuestBank is loaded: its interact light is its own.") end
      drawLight(col, s, own)
    end })
end
