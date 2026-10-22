-- SPDX-License-Identifier: GPL-3.0-or-later
-- Layout: the pieces on screen moved, scaled, shown and locked (the windows design's section 6). Cute's windows are not
-- among them: they always move by their header and size by their corner (UI.lua); Reset windows puts them back.
--   the pieces   the quest engine's (Cute_Quest's QB.Movers: the step frame, the arrow, Reminders, Buffs, the clock),
--                handed over by its Bridge.lua (L.Attach) before the engine's login places them. With the addon QuestBank loaded the
--                engine is QuestBank's own: no pieces here, nothing of its settings written, the rows greyed
--   the lock     one for them all (Lock frames, in the menu and Settings > Layout), on by default: locked, nothing on
--                screen drags; unlocked, each piece drags where it stands. The engine's own drags and menus ask it
--                (QB.LayoutLocked, QB.SetLayoutLocked). The minimap is the game's Edit Mode's to place: always locked
--   layout mode  Move frames (the menu, Settings > Layout, /cute layout, the Move frames key, the game's Edit Mode):
--                a mover over each piece that is on, shown or not. Drag (an 8 px grid and the other movers' edges within
--                6 px; Shift: free), the wheel (50 to 200 % in steps of 5), the arrow keys over a mover (1 px), its
--                right-click (Reset, 80 / 100 / 120 / 150 %, Hide or Show). A bar at the top's middle: Snap, Reset all,
--                Done. Esc is Done, and Done locks. Out of a fight only: a fight's start ends it, saved
--   saved        per character, CuteDB.chars[me].layout = { locked, snap, pieces = { step = { point, x, y, scale }, ...
--                } } (the engine's get: points against UIParent's own); Done also writes it as the account's starting
--                layout (CuteDB.layoutDefault) for a character that has none; Copy from takes another character's.
--                Written back at every drop and at logout (an engine drag or a menu's scale moves the engine's own)
local _, C = ...
local L = { on = false, movers = {}, from = nil, keys = { nudged = 0, done = 0, passed = 0 } }
C.Layout = L

local KEYS = { "step", "arrow", "camp", "buffs", "clock" }
local GRID, SNAP = 8, 6
local MIN_PCT, MAX_PCT, PCT_STEP = 50, 200, 5
local MENU_PCTS = { 80, 100, 120, 150 }
local DOT = " \194\183 " -- (the middle dot, in Windows-1252)
local PANEL = { 0.07, 0.07, 0.07 }
local EDGE = { 0.42, 0.42, 0.42 }

local function inCombat() return C.Callable("InCombatLockdown") and C.Get(InCombatLockdown) == true end
local function shift() return C.Callable("IsShiftKeyDown") and C.Get(IsShiftKeyDown) == true end
local function questBankLoaded()
  local A = type(C_AddOns) == "table" and C_AddOns or nil
  return A ~= nil and type(A.IsAddOnLoaded) == "function" and C.Get(A.IsAddOnLoaded, "QuestBank") == true
end

----------------------------------------------------------------------------
-- the saved layout
----------------------------------------------------------------------------
-- a kept place as the engine gave it, checked (a hand-edited or broken file gives nil for a part that is not a number)
local function clean(p)
  if type(p) ~= "table" then return nil end
  local out = { scale = tonumber(p.scale) }
  if out.scale and (out.scale < 0.5 or out.scale > 2) then out.scale = nil end
  if type(p.point) == "string" and tonumber(p.x) and tonumber(p.y) then out.point, out.x, out.y = p.point, tonumber(p.x), tonumber(p.y) end
  return out
end
local function copyPieces(pieces)
  local out = {}
  for _, key in ipairs(KEYS) do out[key] = clean(type(pieces) == "table" and pieces[key] or nil) end
  return out
end
-- this character's, made the first time: from the account's starting layout, else from where the engine's pieces stand
-- now (filled at L.Attach: the places 0.7 left, account-wide). Locked either way
function L.Get()
  local ch = C.Char()
  local lay = ch.layout
  if type(lay) ~= "table" then
    local def = CuteDB.layoutDefault
    if type(def) == "table" then lay = { snap = def.snap ~= false, pieces = copyPieces(def.pieces) }
    else lay = { snap = true, pieces = {}, fresh = true } end
    lay.locked = true
    ch.layout = lay
  end
  if type(lay.pieces) ~= "table" then lay.pieces = {} end
  if lay.locked == nil then lay.locked = true end
  if lay.snap == nil then lay.snap = true end
  return lay
end
-- the engine's pieces (Cute_Quest's Bridge.lua, before the engine's login): this character's layout into the engine's
-- settings, or, on a layout just made, the engine's places into it
function L.Attach(movers)
  if type(movers) ~= "table" then return end
  L.pieces = movers
  local lay = L.Get()
  for _, key in ipairs(KEYS) do
    local m = movers[key]
    if m then
      -- (each on its own: one piece's error, recorded, leaves the others theirs. A piece a layout has no place for, one
      -- that came after it was made (the clock, merge3), keeps the engine's own place and the layout takes it)
      C.Safe(function()
        if lay.fresh or lay.pieces[key] == nil then lay.pieces[key] = clean(m.get()) else m.set(clean(lay.pieces[key])) end
      end, "layout: " .. key)()
    end
  end
  lay.fresh = nil
end
local function mover(key) return L.pieces and L.pieces[key] or nil end
function L.Save(key)
  local m = mover(key)
  if m then L.Get().pieces[key] = clean(m.get()) end
end
function L.SaveAll() for _, key in ipairs(KEYS) do C.Safe(function() L.Save(key) end, "layout: save " .. key)() end end
-- why there is nothing to move (the rows greyed with it), or nil
function L.Why()
  if L.pieces then return nil end
  if questBankLoaded() then return "QuestBank is loaded: its frames are its own." end
  return "Nothing on screen to move."
end

----------------------------------------------------------------------------
-- the lock
----------------------------------------------------------------------------
function L.Locked(key)
  if key == "minimap" then return true end -- (the game's Edit Mode places the minimap under Cute)
  return L.Get().locked ~= false
end
function L.SetLocked(on)
  L.Get().locked = on and true or false
  if C.SettingsPage and C.SettingsPage.Redraw then C.SettingsPage.Redraw() end
end

----------------------------------------------------------------------------
-- the movers
----------------------------------------------------------------------------
local bar
local function pctOf(m)
  local p = m.get()
  return math.floor(((p and tonumber(p.scale)) or 1) * 100 + 0.5)
end
local function screen() return UIParent:GetWidth() or 1920, UIParent:GetHeight() or 1080 end
-- the mover's frame over its piece's rect (mv.l, mv.t, mv.w, mv.h, which the snapping reads): at least 30 px tall, a
-- piece shorter than its labels (the clock's 24 px strip, merge3) having its mover reach as far above it as below
local MOVER_MIN_H = 30
local function placeMover(mv)
  local hv = math.max(MOVER_MIN_H, mv.h)
  mv:SetSize(math.max(24, mv.w), hv)
  mv:ClearAllPoints()
  mv:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", mv.l, mv.t + (hv - mv.h) / 2)
end
-- a mover over its piece, where the piece stands now (its rect), with its name and its scale
local function sync(mv)
  local m = mover(mv.key)
  if not m then return end
  local l, t, w, h = m.rect()
  mv.l, mv.t, mv.w, mv.h = l, t, w, h
  placeMover(mv)
  -- (a mover too short for its two lines, the clock's: the name and the scale side by side)
  local one = math.max(MOVER_MIN_H, h) < 44
  if mv.oneLine ~= one then
    mv.oneLine = one
    mv.name:ClearAllPoints(); mv.scaleText:ClearAllPoints()
    if one then
      mv.name:SetPoint("RIGHT", mv, "CENTER", -3, 0); mv.scaleText:SetPoint("LEFT", mv, "CENTER", 3, 0)
    else
      mv.name:SetPoint("BOTTOM", mv, "CENTER", 0, 1); mv.scaleText:SetPoint("TOP", mv, "CENTER", 0, -1)
    end
  end
  local on = m.on()
  mv.scaleText:SetText(on and (pctOf(m) .. "%") or ("Hidden" .. DOT .. pctOf(m) .. "%"))
  mv:SetAlpha(on and 1 or 0.5)
end
local function syncAll() for _, mv in pairs(L.movers) do if mv:IsShown() then sync(mv) end end end
-- the client's layout cache never fights the saved place (the windows design: SetUserPlaced(false) on every moved one)
local function unplaced(m)
  local f = m and m.frame()
  if f and f.SetUserPlaced and not inCombat() then pcall(f.SetUserPlaced, f, false) end
end
-- after a drop, a size or a reset: every mover over its piece again (Buffs stands on Reminders by default, the arrow
-- under the step frame), the piece's place kept
local function dropped(mv)
  syncAll()
  unplaced(mover(mv.key))
  L.Save(mv.key)
end

-- snapping: the low edge (or the high one) of the mover onto another mover's edge within SNAP px, else its low edge
-- on the GRID from the screen's middle
local function snapAxis(lo, size, edges, mid)
  local best, bestD
  for _, e in ipairs(edges) do
    for _, mine in ipairs({ lo, lo + size }) do
      local d = math.abs(mine - e)
      if d <= SNAP and (not bestD or d < bestD) then best, bestD = lo + (e - mine), d end
    end
  end
  if best then return best end
  return mid + math.floor((lo - mid) / GRID + 0.5) * GRID
end
local xs, ys = {}, {}
local function snapped(mv, l, t)
  for i = #xs, 1, -1 do xs[i] = nil end
  for i = #ys, 1, -1 do ys[i] = nil end
  for _, o in pairs(L.movers) do
    if o ~= mv and o:IsShown() and o.l then
      xs[#xs + 1], xs[#xs + 2] = o.l, o.l + o.w
      ys[#ys + 1], ys[#ys + 2] = o.t - o.h, o.t
    end
  end
  local W, H = screen()
  local nl = snapAxis(l, mv.w, xs, W / 2)
  local nb = snapAxis(t - mv.h, mv.h, ys, H / 2)
  return nl, nb + mv.h
end
-- within the screen
local function clamp(mv, l, t)
  local W, H = screen()
  return math.max(0, math.min(l, W - mv.w)), math.max(mv.h, math.min(t, H))
end
local function cursor()
  local x, y = GetCursorPosition()
  local s = UIParent:GetEffectiveScale() or 1
  return (x or 0) / s, (y or 0) / s
end
-- a drag: the mover follows the cursor from where it was taken, snapped unless Shift is down; let go, the piece moves
local function follow(mv)
  local cx, cy = cursor()
  local l, t = cx - mv.grabX, cy - mv.grabY
  if L.Get().snap ~= false and not shift() then l, t = snapped(mv, l, t) end
  l, t = clamp(mv, l, t)
  mv.l, mv.t = l, t
  placeMover(mv)
end
local function dragStart(mv)
  if not L.on or inCombat() then return end
  local cx, cy = cursor()
  mv.grabX, mv.grabY = cx - mv.l, cy - mv.t
  mv.dragging = true
  mv:SetScript("OnUpdate", C.Safe(follow, "layout: drag"))
end
local function dragStop(mv)
  if not mv.dragging then return end
  mv.dragging = nil
  mv:SetScript("OnUpdate", nil)
  local m = mover(mv.key)
  if not m or inCombat() then sync(mv) return end
  follow(mv)
  m.move(mv.l, mv.t)
  dropped(mv)
end
-- the wheel: 5 % a notch, 50 to 200 %
local function wheel(mv, delta)
  local m = mover(mv.key)
  if not (m and L.on) or inCombat() then return end
  local pct = pctOf(m) + (delta > 0 and PCT_STEP or -PCT_STEP)
  pct = math.max(MIN_PCT, math.min(MAX_PCT, math.floor(pct / PCT_STEP + 0.5) * PCT_STEP))
  m.scale(pct / 100)
  dropped(mv)
end
-- a nudge of 1 px from the arrow keys, on the mover under the mouse
local NUDGE = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }
local function nudge(mv, key)
  local m, d = mover(mv.key), NUDGE[key]
  if not (m and d) then return false end
  m.move(mv.l + d[1], mv.t + d[2])
  dropped(mv)
  return true
end
-- a piece's own switch. (The hud review) Reminders' is the Reminders module (Cute_Quest's camp), Reminders' and Buffs'
-- only master: Hide turns the module off and Show on, and Buffs shown while it is off turns it on too; every mover
-- over its piece again after, Buffs going with Reminders
local function switch(m, on)
  local mod = C.Modules and C.Modules.byId.camp
  if mod and (m.key == "camp" or (m.key == "buffs" and on and not mod.active)) then C.Modules.Set(mod.key, on) end
  if m.key ~= "camp" or not mod then m.switch(on) end
  syncAll()
end
-- its right-click: Reset, four sizes, its own switch
local function menu(mv)
  local m = mover(mv.key)
  if not m or not (type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function") then return end
  MenuUtil.CreateContextMenu(mv, function(_, root)
    root:CreateTitle(m.name)
    root:CreateButton("Reset", C.Safe(function() m.set(nil); dropped(mv) end, "layout: reset " .. m.key))
    local now = pctOf(m)
    for _, pct in ipairs(MENU_PCTS) do
      local pick = C.Safe(function() m.scale(pct / 100); dropped(mv) end, "layout: size " .. m.key)
      -- (the game's radio where the client has it, Blizzard_Menu's CreateRadio; a button with the word else)
      if root.CreateRadio then root:CreateRadio(pct .. "%", function() return pctOf(m) == pct end, pick)
      else root:CreateButton(pct .. "%" .. (now == pct and "  (now)" or ""), pick) end
    end
    root:CreateButton(m.on() and "Hide" or "Show", C.Safe(function() switch(m, not m.on()) end, "layout: show " .. m.key))
  end)
end
local function makeMover(key)
  local UI = C.UI
  local mv = CreateFrame("Button", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  mv.key = key
  mv:SetFrameStrata("DIALOG")
  mv:SetClampedToScreen(true)
  mv:EnableMouse(true)
  mv:EnableMouseWheel(true)
  mv:RegisterForDrag("LeftButton")
  mv:RegisterForClicks("RightButtonUp")
  if mv.SetBackdrop then
    mv:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    mv:SetBackdropColor(PANEL[1], PANEL[2], PANEL[3], 0.88)
    mv:SetBackdropBorderColor(EDGE[1], EDGE[2], EDGE[3], 1)
  end
  mv:SetHighlightTexture("Interface\\Buttons\\WHITE8x8", "ADD")
  mv:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)
  mv.name = UI.Text(mv, 12, UI.COLORS.WHITE, "CENTER")
  mv.name:SetPoint("BOTTOM", mv, "CENTER", 0, 1)
  mv.scaleText = UI.Text(mv, 11, UI.COLORS.DIM, "CENTER")
  mv.scaleText:SetPoint("TOP", mv, "CENTER", 0, -1)
  mv:SetScript("OnDragStart", C.Safe(dragStart, "layout: drag"))
  mv:SetScript("OnDragStop", C.Safe(dragStop, "layout: drop"))
  mv:SetScript("OnMouseWheel", C.Safe(wheel, "layout: wheel"))
  mv:SetScript("OnClick", C.Safe(function(self, button) if button == "RightButton" then menu(self) end end, "layout: menu"))
  mv:SetScript("OnEnter", C.Safe(function(self)
    L.hover = self
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(mover(self.key) and mover(self.key).name or "", 1, 1, 1)
    GameTooltip:AddLine("Drag to move; Shift: no snap. Wheel: size. Arrow keys: 1 px. Right-click: reset, size, hide.", 0.85, 0.85, 0.85, true)
    GameTooltip:Show()
  end, "layout: tooltip"))
  mv:SetScript("OnLeave", function(self) if L.hover == self then L.hover = nil end GameTooltip:Hide() end)
  mv:Hide()
  L.movers[key] = mv
  return mv
end

----------------------------------------------------------------------------
-- the bar at the top's middle: Move frames, Snap, Reset all, Done; Esc is Done and the arrow keys nudge
----------------------------------------------------------------------------
local function onKey(self, key)
  if inCombat() then return end
  local used = false
  if key == "ESCAPE" then L.Done(); used = true; L.keys.done = L.keys.done + 1
  elseif NUDGE[key] and L.hover and L.hover:IsShown() then used = nudge(L.hover, key); if used then L.keys.nudged = L.keys.nudged + 1 end end
  if not used then L.keys.passed = L.keys.passed + 1 end
  -- (a key Layout has no use for goes on to the game: moving, the action bars)
  self:SetPropagateKeyboardInput(not used)
end
local function makeBar()
  local UI = C.UI
  local b = CreateFrame("Frame", "CuteLayoutBar", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  b:SetFrameStrata("DIALOG")
  b:SetFrameLevel(100)
  b:SetHeight(32)
  b:SetPoint("TOP", UIParent, "TOP", 0, -12)
  b:EnableMouse(true)
  UI.Skin(b, UI.COLORS.PANEL2)
  b.title = UI.Text(b, 12, UI.COLORS.WHITE, "LEFT")
  b.title:SetPoint("LEFT", 12, 0)
  b.title:SetText("Move frames")
  local function dot()
    local d = UI.Text(b, 12, UI.COLORS.DIM, "CENTER")
    d:SetText(DOT)
    return d
  end
  b.dot1, b.dot2, b.dot3 = dot(), dot(), dot()
  b.snap = UI.CheckRow(b)
  b.snap.label:SetText("Snap")
  b.snap.fn = function(r) L.Get().snap = r:GetChecked() end
  b.reset = UI.Button(b, "Reset all", 80, 20)
  b.reset:SetScript("OnClick", C.Safe(function() L.ResetAll() end, "layout: reset all"))
  b.done = UI.Button(b, "Done", 60, 20)
  b.done:SetScript("OnClick", C.Safe(function() L.Done() end, "layout: done"))
  -- laid out left to right by what each takes
  local function w(fs) return math.ceil(((fs.GetUnboundedStringWidth or fs.GetStringWidth)(fs)) or 0) end
  local x = 12 + w(b.title)
  for _, part in ipairs({ { b.dot1 }, { b.snap, 14 + 6 + w(b.snap.label) + 4 }, { b.dot2 }, { b.reset, 80 }, { b.dot3 }, { b.done, 60 } }) do
    local f, width = part[1], part[2] or w(part[1])
    f:ClearAllPoints()
    f:SetPoint("LEFT", b, "LEFT", x, 0)
    if part[2] then f:SetWidth(width) end
    if f == b.snap then f:SetHeight(20) end
    x = x + width
  end
  b:SetWidth(x + 12)
  b:SetScript("OnKeyDown", C.Safe(onKey, "layout: keys"))
  b:Hide()
  return b
end

----------------------------------------------------------------------------
-- in and out
----------------------------------------------------------------------------
-- layout mode on (from: "edit" when the game's Edit Mode opened it); false, and a line, where it cannot be (none for
-- Edit Mode's: it opens for the game's own frames, nothing of Cute's asked)
function L.Enter(from)
  if L.on then return true end
  local why = L.Why() or (inCombat() and "after combat.") or nil
  if why then
    if from ~= "edit" then C.Print("Move frames: " .. why) end
    return false
  end
  L.on, L.from = true, from
  bar = bar or makeBar()
  bar.snap:Set(L.Get().snap ~= false)
  bar:Show()
  -- (the game's Edit Mode has its own keys: Cute takes none while it is open)
  if bar.EnableKeyboard then bar:EnableKeyboard(from ~= "edit"); if from ~= "edit" then bar:SetPropagateKeyboardInput(true) end end
  for _, key in ipairs(KEYS) do
    local m = mover(key)
    local mv = L.movers[key]
    if m and m.on() then
      mv = mv or makeMover(key)
      mv.name:SetText(m.name)
      mv:Show()
      sync(mv)
    elseif mv then mv:Hide() end
  end
  if C.SettingsPage and C.SettingsPage.Redraw then C.SettingsPage.Redraw() end
  return true
end
-- layout mode off: every place saved, locked, and the account's starting layout written from this one
function L.Done()
  if not L.on then return end
  L.on, L.from, L.hover = false, nil, nil
  for _, mv in pairs(L.movers) do
    if mv.dragging then mv.dragging = nil; mv:SetScript("OnUpdate", nil) end
    mv:Hide()
  end
  if bar then
    if bar.EnableKeyboard and not inCombat() then bar:EnableKeyboard(false) end
    bar:Hide()
  end
  for _, key in ipairs(KEYS) do unplaced(mover(key)) end
  L.SaveAll()
  local lay = L.Get()
  lay.locked = true
  CuteDB.layoutDefault = { snap = lay.snap ~= false, pieces = copyPieces(lay.pieces) }
  if C.SettingsPage and C.SettingsPage.Redraw then C.SettingsPage.Redraw() end
end
function L.Toggle() if L.on then L.Done() else L.Enter() end end
-- every piece back at its default place at 100%
function L.ResetAll()
  if not L.pieces or inCombat() then return end
  for _, key in ipairs(KEYS) do
    local m = mover(key)
    if m then C.Safe(function() m.set(nil) end, "layout: reset " .. key)(); L.Save(key) end
  end
  syncAll()
end
-- every window at its default size, centred (their places kept in CuteDB.pos and CuteDB.winPos, UI.lua's posOf)
function L.ResetWindows()
  CuteDB.pos, CuteDB.winPos = nil, nil
  local UI = C.UI
  for key, win in pairs(UI.windows) do
    local f, spec = rawget(win, "frame"), UI.SPEC[key]
    if f and spec then
      f:SetSize(spec.w, spec.h)
      f:ClearAllPoints()
      f:SetPoint("CENTER")
    end
  end
  if C.Windows and C.Windows.PlaceAll then C.Windows.PlaceAll() end
end
-- the characters whose layout this one may take: { { key, layout }, ... } by name
function L.Others()
  local me, out = C.Me(), {}
  for key, rec in pairs(CuteDB.chars or {}) do
    if key ~= me and type(rec) == "table" and type(rec.layout) == "table" and type(rec.layout.pieces) == "table" then out[#out + 1] = { key, rec.layout } end
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  return out
end
-- another character's places taken, and put on screen
function L.CopyFrom(key)
  local rec = type(CuteDB.chars) == "table" and CuteDB.chars[key]
  if not (type(rec) == "table" and type(rec.layout) == "table") or inCombat() then return false end
  local lay = L.Get()
  lay.pieces = copyPieces(rec.layout.pieces)
  for _, k in ipairs(KEYS) do
    local m = mover(k)
    if m then C.Safe(function() m.set(clean(lay.pieces[k])) end, "layout: copy " .. k)() end
  end
  syncAll()
  return true
end
function L.CopyMenu(owner)
  if not (type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function") then return end
  MenuUtil.CreateContextMenu(owner or UIParent, function(_, root)
    root:CreateTitle("Copy the layout of")
    for _, o in ipairs(L.Others()) do root:CreateButton(o[1], C.Safe(function() L.CopyFrom(o[1]) end, "layout: copy")) end
  end)
end

----------------------------------------------------------------------------
-- the menu's two entries (Windows.lua W.Menu), Settings > Layout (Settings.lua), the slash word and the key
----------------------------------------------------------------------------
function L.Menu(root)
  root:CreateDivider()
  local why = L.Why()
  local lock = root:CreateCheckbox("Lock frames", function() return L.Get().locked ~= false end,
    C.Safe(function() L.SetLocked(L.Get().locked == false) end, "menu: lock frames"))
  if lock and why and lock.SetEnabled then lock:SetEnabled(false) end
  local move = root:CreateButton("Move frames...", C.Safe(function() L.Enter() end, "menu: move frames"))
  local fight = inCombat()
  if move and (why or fight) then
    move:SetEnabled(false)
    if move.SetTooltip then move:SetTooltip(function(tip) tip:AddLine(why or "After combat", 1, 1, 1, true) end) end
  end
end
function L.Draw(col)
  local lay, why = L.Get(), L.Why()
  local fight = inCombat()
  col:Head("Layout")
  if why then col:Note(why) end
  col:Check("Lock frames", lay.locked ~= false, why == nil, function(on) L.SetLocked(on) end)
  col:Note("The step frame, the arrow, Reminders, Buffs and the clock. Windows always move by their header.")
  col:Check("Snap to the grid", lay.snap ~= false, why == nil, function(on) lay.snap = on end)
  local after = function(tip) tip:AddLine(fight and "After combat." or (why or ""), 1, 1, 1, true) end
  col:Buttons({
    { "Move frames", why == nil and not fight and not L.on, function() L.Enter() end, (why or fight) and after or nil },
    { "Reset all", why == nil and not fight, function() L.ResetAll() end, (why or fight) and after or nil },
    { "Reset windows", true, function() L.ResetWindows() end },
    { "Copy from...", why == nil and not fight and #L.Others() > 0, function() L.CopyMenu(C.UI.Window("settings").frame) end },
  })
end

-- /cute diag's line for what only the live client shows: each piece on or off, its scale and whether it was moved,
-- the lock, layout mode, and the keys the bar took and passed on (the client's keyboard rules for an addon frame,
-- SetPropagateKeyboardInput HasRestrictions, SimpleFrameAPIDocumentation.lua:1426). Never a name
function L.DiagLine()
  local parts = {}
  for _, key in ipairs(KEYS) do
    local m = mover(key)
    if m then
      local p = m.get()
      parts[#parts + 1] = string.format("%s %s %d%%%s", key, m.on() and "on" or "off", pctOf(m), (p and p.point) and " moved" or "")
    end
  end
  local k = L.keys
  return string.format("diag layout: %s; locked %s; mode %s; keys nudged %d, done %d, passed %d", #parts > 0 and table.concat(parts, ", ") or (L.Why() or "none"),
    L.Get().locked ~= false and "yes" or "no", L.on and (L.from or "on") or "off", k.nudged, k.done, k.passed)
end
do
  local coreDiag = C.Diag
  function C.Diag()
    local lines = coreDiag and coreDiag() or {}
    local ok, l = pcall(L.DiagLine)
    -- (before the game buttons' line, which stays the last: Windows.lua's)
    table.insert(lines, math.max(1, #lines), ok and l or ("diag layout: " .. tostring(l)))
    return lines
  end
end

BINDING_NAME_CUTE_LAYOUT = "Move frames"
do
  local before = SlashCmdList.CUTE
  SlashCmdList.CUTE = C.Safe(function(msg)
    local m = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if m == "layout" then L.Toggle() return end
    return before(msg)
  end, "slash")
end

-- a fight's start ends layout mode, saved (PLAYER_REGEN_DISABLED comes before the lockdown); every place written back
-- at logout and at a /reload; the game's Edit Mode opens and closes it (EventRegistry, as camelot's
-- MainMenuBarEndCaps.lua:7-11 hears Edit Mode, Shared/EditModeManager.lua:105, 124)
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:SetScript("OnEvent", C.Safe(function(_, event)
  if event == "PLAYER_REGEN_DISABLED" then L.Done() else L.SaveAll() end
end, "layout: events"))
if type(EventRegistry) == "table" and type(EventRegistry.RegisterCallback) == "function" then
  pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Enter", C.Safe(function() L.Enter("edit") end, "layout: edit mode"), L)
  pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit", C.Safe(function() if L.from == "edit" then L.Done() end end, "layout: edit mode"), L)
end

-- the door the quest engine's Bridge.lua reaches (Cute is the one global Cute makes, Modules.lua)
C.API.Layout = { Attach = L.Attach, Locked = L.Locked, SetLocked = L.SetLocked, Toggle = C.Safe(L.Toggle, "binding: move frames") }
