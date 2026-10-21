-- SPDX-License-Identifier: GPL-3.0-or-later
-- RunsUI: the Runs module's face (the run report's design, 8.4, 8.5, 9.7 and 14): the Runs tab in the guild window (the
-- history, a run on in its band, the leader's End run), Settings > Runs, Send to party, the test report and the slash
-- words (/cute run, /cute run end, /cute run test [raid], /cute diag runs). It registers the module.
local _, C = ...
local RU = {}
C.RunsUI = RU

----------------------------------------------------------------------------
-- the module
----------------------------------------------------------------------------
C:RegisterModule({
  id = "runs", title = "Runs", order = 45, builtin = true, default = true, tab = 64,
  notes = "Run reports after dungeons, raids and long groups: a card for each of you, with Send to party.",
  page = function(ui) if RU.Draw then RU.Draw(ui) end end,
  settings = function(ui, col) if RU.Settings then RU.Settings(ui, col) end end,
  events = C.Runs.events,
  onToggle = function(on)
    local R = C.Runs
    if on then
      R.Register()
      R.startTimers()
    else
      -- (switched off: nothing counted or sent from now; the run, if any, is dropped without a report)
      R.run = nil
      C.Char().run = nil
      R:Counting(false)
      C.RunComm:Clear()
    end
    -- (the Me page: whether this character's Runs counts the run fields)
    for _, f in ipairs(C.Stats.RUNFIELDS) do C.Sample.values[f[1]] = on and true or false end
  end,
})
