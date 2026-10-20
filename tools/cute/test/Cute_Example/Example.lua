-- SPDX-License-Identifier: GPL-3.0-or-later
-- Cute_Example: the harness's module addon, the smallest there is, and no part of Cute's zip. It walks the path every
-- module takes: its toc ("## Dependencies: Cute", "## LoadOnDemand: 1", "## X-Cute-Module: 1") lists it in Cute's
-- Settings > Modules, switching it on there loads it (C_AddOns.LoadAddOn, no reload), and as it loads it registers
-- with Cute:RegisterModule: a page in Cute's look, its own Settings section, an event it hears while it is on and a
-- stat in Cute's registry.
local ADDON, E = ...
E.heard, E.wide = 0, false

Cute:RegisterModule({
  id = "example", addon = ADDON, title = "Example", order = 90,
  notes = "The harness's example module.",
  -- the page: the window's own pieces, into the shared scroll area
  page = function(ui, scroll)
    local w = scroll:Width()
    local l = ui.labels:Get()
    l:SetPoint("TOPLEFT", 6, -6)
    l:SetWidth(w - 12)
    l:SetJustifyH("LEFT")
    ui.Color(l, ui.COLORS.INK)
    ui.FitText(l, "Level ups heard while on: " .. E.heard .. (E.wide and ", counted wide." or "."), w - 16)
    scroll:SetContentHeight(30)
  end,
  -- its section: the column Settings hands it
  settings = function(_, col)
    col:Head("Example")
    col:Check("Count wide", E.wide, true, function(on) E.wide = on end)
  end,
  events = { PLAYER_LEVEL_UP = function() E.heard = E.heard + 1 end },
  stats = function(D) D("ex_heard", "Level ups heard", "funny", { read = function() return E.heard end }) end,
})

-- a second module from the same folder: its own row in Settings > Modules (keyed Cute_Example:example_two), its own
-- choice; the folder loads when either is on and is off in the AddOns list only when both are off
Cute:RegisterModule({
  id = "example_two", addon = ADDON, title = "Example two", order = 91,
  notes = "The example's second module.",
  page = function(ui, scroll)
    local l = ui.labels:Get()
    l:SetPoint("TOPLEFT", 6, -6)
    l:SetWidth(scroll:Width() - 12)
    ui.FitText(l, "Toggled " .. (E.toggled or 0) .. " times.", scroll:Width() - 16)
    scroll:SetContentHeight(30)
  end,
  settings = function(_, col) col:Head("Example two") end,
  onToggle = function(on) E.toggled = (E.toggled or 0) + 1; E.lastOn = on end,
})
