-- SPDX-License-Identifier: GPL-3.0-or-later
-- Setup: the first-run card, once per character, and the reload rule's question when Settings closes.
-- The card (CuteSetupFrame, 480 px, centred): the windows (Guild and Quests always, with the key that opens each; Runs
-- under Guild; the Dungeons and Gear tabs; Cute's Map with its key), what Cute puts on screen (the step frame and
-- arrow, Reminders, the interact light) and the two quest choices (Accept for me, the hand-in). Every row starts
-- from what this character has saved (its modules, the engine's settings), and only a row with nothing saved starts at
-- the default: everything on but the two automatic choices. Start writes the choices, marks every row shown answered
-- (CuteDB.chars[me].setup[row]), keeps the keys (Keys.lua) and reloads; after the reload the quest window opens once (the
-- map's, for a card that came back with its Map row alone).
-- The rows that change the game unasked say how in one dim line under them (Map: the minimap's mouse is the engine's
-- while it is ticked, Minimap.lua Mini.Owned; unticked, the line says the far view stays, the Route tab's own row and
-- on by default, Mini.FarOn: the wheel past the game's widest and the drag; Reminders: what the bar and banner remind
-- of; Interact light: the game's soft-target settings, Glow.lua, put back when it is switched off).
-- Not now changes nothing and the card never comes back by itself (the menu keeps "Set up Cute..." until Start). A row a
-- later round adds comes back alone, once. Nothing on it is cut: labels and the note wrap.
-- Shown 3 s after the first loading screen that is out of combat and outside an instance.
-- With the addon QuestBank loaded its step frame, arrow, Reminders and choices are its own (Cute sets none of
-- QuestBank's settings): those rows give way to one line saying so. Reminders is the Camp module (Cute_Quest:camp, on
-- by default: PageCamp.lua), its row the module's alone; the interact light is its own row, never the module's, and
-- starts from the light: on, ticked; off, unticked, unless it is off only until this row says (Bridge.lua's LightAsks: a
-- fresh install, a 0.7 light the account never chose), which starts at the default.
local _, C = ...
local S = {}
C.Setup = S

local WHITE = { 0.96, 0.96, 0.96 }
local INK = { 0.86, 0.86, 0.86 }
local DIM = { 0.58, 0.58, 0.58 }
local MUTE = { 0.52, 0.52, 0.52 }
local CARD_W, PAD, ROWH = 480, 14, 22
local ACCEPT = { { "Off", "off" }, { "On my route", "route" }, { "Worth taking", "worth" } }

local function callable(name) return type(_G[name]) == "function" end
local function inCombat() return callable("InCombatLockdown") and C.Get(InCombatLockdown) == true end
local function inInstance() return callable("IsInInstance") and C.Get(IsInInstance) == true end

-- this character's answers: CuteDB.chars[me].setup = { [row] = true }
local function answered()
  local ch = C.Char()
  if type(ch.setup) ~= "table" then ch.setup = {} end
  return ch.setup
end
-- the engine's settings (Cute_Quest's Bridge.lua door): nil while QuestBank runs the engine or no copy is here
local function engine() return C.API.QuestSetup end
-- whether this client has the quest window: its addon registered, or loading once a fight ends (its rows are left out
-- otherwise: one the client would not load is no window)
local function hasQuests() return C.Modules.byId.quests ~= nil or C.Modules.BaseComing() end
-- the quest window registered and no engine of its own: the addon QuestBank serves it (Bridge.lua's dormant copy), whose
-- own Map page is its map, so Cute's Map window draws nothing and M stays the game's (Keys.lua holds no key for it)
local function dormant() return C.Modules.byId.quests ~= nil and engine() == nil end

-- the rows, each { id, group, label, kind = "check" | "choice" | "key" | "fixed", ... }; a row only where its part is
local function rows()
  local out = {}
  local quests = hasQuests()
  local q = engine()
  local function add(r) out[#out + 1] = r end
  add({ id = "guild", group = "Windows", label = "Guild", kind = "fixed", key = "guild" })
  -- (the run-report design's 14 and 18) Runs, on by default, sends run values to the group, so the card asks: a row of
  -- its own under Guild, ticked; a character who answered the rest sees it alone, once (unindented: no Guild row over it)
  if C.Modules.byId.runs then add({ id = "runs", group = "Windows", label = "Run reports after dungeons, raids and long groups", kind = "check", module = "runs", indent = 20, under = "guild" }) end
  if quests then
    add({ id = "quests", group = "Windows", label = "Quests and Route", kind = "fixed", key = "quests" })
    add({ id = "dungeons", group = "Windows", label = "Dungeons tab", kind = "check", module = "Cute_Quest:journal", indent = 20 })
    add({ id = "gear", group = "Windows", label = "Gear tab", kind = "check", module = "Cute_Quest:gear", indent = 20 })
    -- (sub-project F) the Map window with its key: row mapwin, whose tick starts from the earlier mapicons answer (the
    -- game's map with Cute's icons, which took no key); a character who answered that sees this row alone, once. Not
    -- asked while QuestBank is loaded (no window to open: asked once it is not)
    if not dormant() then
      add({ id = "mapwin", group = "Windows", label = "Map", kind = "check", module = "Cute_Quest:map", key = "map", note = function()
        -- (merge4) unticked, the minimap is the game's but for the far view, the Route tab's own row (Minimap.lua
        -- Mini.FarOn, on by default): its wheel past the game's widest and its drag stay
        if S.pick and S.pick.on.mapwin == false then
          local s = q and q.Settings and q.Settings() or nil
          if s and s.mmExtended ~= false then return "The minimap stays the game's, but for the far view (Route tab): wheel out past its widest, drag to look around" end
          return "The minimap stays the game's"
        end
        local k = S.KeyText("map")
        return (k ~= "-" and ("Cute's map on " .. k) or "Cute's map window") .. "; the minimap's wheel and right-click become Cute's"
      end })
    end
    if q then
      add({ id = "step", group = "On screen", label = "Step frame and arrow", kind = "check" })
      add({ id = "camp", group = "On screen", label = "Reminders", kind = "check", note = "buffs, food, repair and training, out of a fight" })
      add({ id = "light", group = "On screen", label = "Interact light", kind = "check", note = "turns on the game's Interact key and its icons; Settings puts them back" })
      add({ id = "accept", group = "Quests", label = "Accept for me", kind = "choice" })
      add({ id = "handin", group = "Quests", label = "Hand finished quests in for me", kind = "check" })
    elseif C.Modules.byId.quests then
      -- (the quest window registered and no engine of its own: QuestBank serves it, Bridge.lua's dormant copy)
      add({ id = "dormant", group = "On screen", kind = "line", label = "QuestBank is loaded: its step frame, arrow and Reminders are its own." })
    end
  else
    -- no quest window: Cute_Quest missing (only the Cute folder copied, a common slip) or refused by the client, said
    -- in one line, so the card's J alone is no puzzle
    local M = C.Modules
    if not M.Found("Cute_Quest") then
      add({ id = "questaddon", group = "Windows", kind = "line", label = "Cute_Quest is not in Interface\\AddOns: your quest window comes with it, from the same download." })
    elseif M.failed.Cute_Quest then
      add({ id = "questaddon", group = "Windows", kind = "line", label = "Cute_Quest did not load (" .. tostring(M.failed.Cute_Quest) .. "): your quest window comes with it." })
    end
  end
  local done, shown = answered(), {}
  local ids = {}
  for _, r in ipairs(out) do if r.kind == "line" or not done[r.id] then shown[#shown + 1] = r; ids[r.id] = true end end
  for _, r in ipairs(shown) do if r.under and not ids[r.under] then r.indent = nil end end
  -- (a line alone is no question)
  local asks = 0
  for _, r in ipairs(shown) do if r.kind ~= "line" then asks = asks + 1 end end
  return asks > 0 and shown or {}
end
S.Rows = rows

-- where each row starts: this character's saved choice, else the default (on; the automatic two off)
local function modOn(key)
  local v = (C.Char().modules or {})[key]
  if v ~= nil then return v == true end
  return nil
end
function S.Start(id)
  local q = engine()
  local s = q and q.Settings and q.Settings() or nil
  local saved = q and q.Saved and q.Saved() or false
  local camp = modOn("Cute_Quest:camp")
  if id == "runs" then local v = modOn("runs"); if v == nil then return true end return v end
  if id == "dungeons" then local v = modOn("Cute_Quest:journal"); if v == nil then return true end return v end
  if id == "gear" then local v = modOn("Cute_Quest:gear"); if v == nil then return true end return v end
  if id == "mapwin" or id == "mapicons" then local v = modOn("Cute_Quest:map"); if v == nil then return true end return v end
  if id == "step" then if saved and s then return s.guide.frame ~= false end return true end
  if id == "camp" then
    if camp == nil then return true end
    return camp and (not s or s.campBar ~= false)
  end
  if id == "light" then
    -- (merge3) the light as it is, whatever the Camp module's choice: a 0.8 character who unticked Camp keeps a light
    -- that is on (Bridge.lua gives 0.8's kept light back), and Start never turns it off unasked
    if not s or type(s.glow) ~= "table" or s.glow.on ~= false then return true end
    return not saved or (q.LightAsks ~= nil and q.LightAsks() == true)
  end
  if id == "accept" then if saved and s then return s.autoAccept or "off" end return "off" end
  if id == "handin" then if saved and s then return s.autoTurnIn == true end return false end
  return true
end

----------------------------------------------------------------------------
-- the card
----------------------------------------------------------------------------
local card
local function pool(parent, make)
  local p = { items = {}, used = 0 }
  function p:Get()
    self.used = self.used + 1
    local it = self.items[self.used]
    if not it then it = make(parent); self.items[self.used] = it end
    it:Show()
    return it
  end
  function p:Reset() self.used = 0 end
  function p:HideRest() for i = self.used + 1, #self.items do self.items[i]:Hide() end end
  return p
end
local function build()
  if card then return card end
  local UI = C.UI
  local f = CreateFrame("Frame", "CuteSetupFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  card = f
  f:SetSize(CARD_W, 200)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  UI.Skin(f, { 0.07, 0.07, 0.07 })
  if f.SetBackdropBorderColor then f:SetBackdropBorderColor(0.42, 0.42, 0.42, 1) end
  f.cuteNoCut = true
  f:Hide()
  tinsert(UISpecialFrames, "CuteSetupFrame")
  f.title = UI.Text(f, 15, WHITE, "LEFT")
  f.title:SetPoint("TOPLEFT", PAD, -PAD)
  f.title:SetText("Set up Cute")
  f.who = UI.Text(f, 11, DIM, "RIGHT")
  f.who:SetPoint("TOPRIGHT", -PAD, -PAD - 3)
  f.labels = pool(f, function(p) return UI.Text(p, 13, INK, "LEFT") end)
  f.lines = pool(f, function(p) local t = UI.Flat(p, "ARTWORK", { 0.2, 0.2, 0.2 }, 1); t:SetHeight(1); return t end)
  f.checks = pool(f, function(p) return UI.CheckRow(p) end)
  f.keys = pool(f, function(p) return C.Keys.Box(p) end)
  -- (the choice's options are measured on this one, never shown)
  f.measure = UI.Text(f, 13, INK)
  f.measure:Hide()
  f.start = UI.Button(f, "Start", 76, 22)
  f.later = UI.Button(f, "Not now", 76, 22)
  f.start:SetPoint("BOTTOMRIGHT", -PAD - 82, PAD)
  f.later:SetPoint("BOTTOMRIGHT", -PAD, PAD)
  f.start:SetScript("OnClick", C.Safe(function() S.Go() end, "setup: start"))
  f.later:SetScript("OnClick", C.Safe(function() S.Later() end, "setup: not now"))
  f:RegisterEvent("PLAYER_REGEN_DISABLED")
  f:RegisterEvent("PLAYER_REGEN_ENABLED")
  f:SetScript("OnEvent", C.Safe(function() if f:IsShown() then S.Draw() end end, "setup: combat"))
  return f
end
-- a label that wraps to its width; returns its height
local function say(f, x, y, w, s, c, size)
  local l = f.labels:Get()
  l:ClearAllPoints()
  l:SetPoint("TOPLEFT", x, -y)
  l:SetWidth(w)
  l:SetWordWrap(true)
  if l.cuteSize ~= size then l:SetFont(C.UI.FONT, size, ""); l.cuteSize = size end
  C.UI.Color(l, c)
  l:SetText(s)
  l.cuteCut = nil
  return math.max(size + 2, math.ceil(l:GetStringHeight() or 0))
end
-- the card's choices while it shows (written by Start alone)
S.pick = nil
function S.Draw()
  local f = build()
  local UI = C.UI
  local p = S.pick
  for _, k in ipairs({ "labels", "lines", "checks", "keys" }) do f[k]:Reset() end
  local first = C.MyName and C.MyName() or nil
  f.who:SetText(first and ("for " .. first) or "")
  local inner = CARD_W - 2 * PAD
  local y, group = PAD + 30, nil
  for _, r in ipairs(p.rows) do
    if r.group ~= group then
      group = r.group
      y = y + (y > PAD + 30 and 6 or 0)
      local h = say(f, PAD, y + 4, inner, group, DIM, 11)
      y = y + math.max(20, h + 6)
      local ln = f.lines:Get()
      ln:ClearAllPoints()
      ln:SetPoint("TOPLEFT", PAD, -(y - 2))
      ln:SetWidth(inner)
    end
    local x = PAD + (r.indent or 0)
    if r.kind == "line" then
      local h = say(f, x, y + 4, inner, r.label, DIM, 12)
      y = y + math.max(ROWH, h + 7)
    elseif r.kind == "choice" then
      local lh = say(f, x, y + 4, 116, r.label, INK, 13)
      local cx, line = x + 120, 0
      for _, a in ipairs(ACCEPT) do
        local m = f.measure
        m:SetText(a[1])
        local cw = 14 + 6 + math.ceil(((m.GetUnboundedStringWidth or m.GetStringWidth)(m)) or 0) + 12
        if cx > x + 120 and cx + cw > PAD + inner then cx = x + 120; line = line + 1 end
        local cb = f.checks:Get()
        cb.label:ClearAllPoints(); cb.label:SetPoint("TOPLEFT", 20, -4); cb.label:SetWidth(cw - 20); cb.label:SetWordWrap(true)
        cb.label:SetText(a[1]); cb.label.cuteCut = nil
        cb:ClearAllPoints(); cb:SetPoint("TOPLEFT", cx, -(y + line * ROWH)); cb:SetSize(cw, ROWH)
        cb:Set(p.accept == a[2]); cb:SetOn(true)
        cb.fn = function() p.accept = a[2]; S.Draw() end
        cx = cx + cw
      end
      y = y + math.max((line + 1) * ROWH, lh + 7)
    else
      -- a check row: fixed ones (Guild, Quests) ticked and greyed with "always"; the key box on the right
      local right = r.key and 96 or 0
      local cb = f.checks:Get()
      cb.label:ClearAllPoints(); cb.label:SetPoint("TOPLEFT", 20, -4); cb.label:SetWidth(inner - (r.indent or 0) - right - 24); cb.label:SetWordWrap(true)
      cb.label:SetText(r.label .. (r.kind == "fixed" and "   |cff949494always|r" or "")); cb.label.cuteCut = nil
      local h = math.max(15, math.ceil(cb.label:GetStringHeight() or 0))
      cb:ClearAllPoints(); cb:SetPoint("TOPLEFT", x, -y); cb:SetSize(inner - (r.indent or 0) - right, math.max(ROWH, h + 7))
      if r.kind == "fixed" then
        cb:Set(true); cb:SetOn(false); cb.fn = function(b) b:Set(true) end
      else
        cb:Set(p.on[r.id]); cb:SetOn(true)
        cb.fn = function(b) p.on[r.id] = b:GetChecked(); S.Draw() end
      end
      if r.key then
        local box = f.keys:Get()
        box:ClearAllPoints()
        box:SetPoint("TOPRIGHT", -PAD, -(y + 1))
        box.onKey = function(v) p.keys[r.key] = v; S.Draw() end
        box:Bind(r.key, S.KeyText(r.key))
        if r.key == "guild" and not C.Keys.InGuild() then box:Bind(r.key, "-") end
      end
      y = y + math.max(ROWH, h + 7)
      -- what the row changes in the game, then a hand-picked key that does something else there: a dim line each
      local note = r.note
      if type(note) == "function" then note = note() end
      local under = r.key and S.KeyWords(r.key)
      for _, s in ipairs({ note or false, under or false }) do
        if s then
          local nh = say(f, x + 20, y - 2, inner - 20 - (r.indent or 0), s, DIM, 11)
          y = y + nh + 2
        end
      end
    end
  end
  local nh = say(f, PAD, y + 10, inner, S.KeysLine(p) .. " Change any of this later in Settings: right-click the minimap button. Window and tab changes reload; the rest applies at once.", DIM, 12)
  y = y + 10 + nh + 12
  for _, k in ipairs({ "labels", "lines", "checks", "keys" }) do f[k]:HideRest() end
  local fight = inCombat()
  -- (each button as wide as its word: the card never cuts one)
  for _, d in ipairs({ { f.start, fight and "After combat" or "Start" }, { f.later, "Not now" } }) do
    d[1].label:SetText(d[2])
    d[1]:SetWidth(math.max(76, math.ceil(((d[1].label.GetUnboundedStringWidth or d[1].label.GetStringWidth)(d[1].label) or 0) + 24)))
    d[1]:SetLabel(d[2])
  end
  f.start:ClearAllPoints()
  f.start:SetPoint("BOTTOMRIGHT", -PAD - f.later:GetWidth() - 6, PAD)
  f.start:SetOn(not fight)
  f:SetHeight(y + 22 + PAD)
end
-- the card's sentence on its keys: the keys its boxes show, for the windows this client has (Guild; Quests where its
-- addon is; Map where it is on, or ticked here), a box that reads "-" left out (outside a guild the Guild key waits,
-- Keys.lua). One key names its window; none, and only the buttons to the game's own are said
local WINDOW_WORD = { guild = "guild", quests = "quest", map = "map" }
function S.KeysLine(p)
  local mapOn = p.on.mapwin
  if mapOn == nil then mapOn = C.Modules.OnKey("Cute_Quest:map") and not dormant() end
  local list = {}
  for _, id in ipairs({ "guild", "quests", "map" }) do
    if id == "guild" or (id == "quests" and hasQuests()) or (id == "map" and mapOn) then
      local k = S.KeyText(id)
      if id == "guild" and not C.Keys.InGuild() then k = "-" end
      if k ~= "-" then list[#list + 1] = { id = id, key = k } end
    end
  end
  local own = "each window has a button to the game's own."
  if #list == 0 then return "Each window has a button to the game's own." end
  if #list == 1 then return list[1].key .. " opens Cute's " .. WINDOW_WORD[list[1].id] .. " window; " .. own end
  local keys = {}
  for i, e in ipairs(list) do keys[i] = e.key end
  return table.concat(keys, ", ", 1, #keys - 1) .. " and " .. keys[#keys] .. " open Cute's windows; " .. own
end
-- what a key box on the card shows: the card's own choice ("follow": the game's key for that window)
function S.KeyText(id)
  local v = S.pick and S.pick.keys[id]
  local w
  for _, x in ipairs(C.Keys.ALL) do if x.id == id then w = x end end
  if v == "follow" then local k = w and C.Keys.GameKeys(w.action) or {}; return #k > 0 and table.concat(k, ", ") or "-" end
  if type(v) == "string" then return v end
  return "-"
end
function S.KeyWords(id)
  local v = S.pick and S.pick.keys[id]
  if type(v) ~= "string" or v == "follow" or not callable("GetBindingAction") then return nil end
  local action = C.Plain(C.Get(GetBindingAction, v))
  local w
  for _, x in ipairs(C.Keys.ALL) do if x.id == id then w = x end end
  if type(action) ~= "string" or action == "" or (w and (action == w.action or action == w.binding)) then return nil end
  local name = C.Plain(_G["BINDING_NAME_" .. action])
  return "replaces " .. ((type(name) == "string" and name ~= "") and name or action)
end

-- the card shown: its rows, each from this character's own saved choice (asked: from the menu, Not now or not)
function S.Show(asked)
  local list = rows()
  if #list == 0 then
    if asked then C.Print("set up already: Settings has every choice (right-click the minimap button).") end
    return false
  end
  local pick = { rows = list, on = {}, keys = {} }
  for _, r in ipairs(list) do
    if r.kind == "check" then pick.on[r.id] = S.Start(r.id) end
    if r.kind == "choice" then pick.accept = S.Start(r.id) end
  end
  -- the keys: what this character has, else the game's own key for the window
  for _, w in ipairs(C.Keys.ALL) do
    local v = C.Keys.Get(w.id)
    pick.keys[w.id] = (v == nil) and "follow" or v
  end
  S.pick = pick
  S.Draw()
  card:Show()
  return true
end
-- Start: the choices written, every row shown answered, the keys kept, the quest window to open after the reload
function S.Go()
  if inCombat() then return false end
  local p = S.pick
  if not p then return false end
  local ch, M = C.Char(), C.Modules
  local done = answered()
  local shown = {}
  for _, r in ipairs(p.rows) do if r.kind ~= "line" then done[r.id] = true; shown[r.id] = true end end
  -- the modules (the reload applies them): each shown tab or switch; Reminders (the Camp module) from its own row alone
  if shown.runs then M.Choose("runs", p.on.runs) end
  if shown.dungeons then M.Choose("Cute_Quest:journal", p.on.dungeons) end
  if shown.gear then M.Choose("Cute_Quest:gear", p.on.gear) end
  if shown.mapwin then M.Choose("Cute_Quest:map", p.on.mapwin) end
  if shown.camp then M.Choose("Cute_Quest:camp", p.on.camp and true or false) end
  -- the engine's settings (the copy's own: never QuestBank's)
  local q = engine()
  if q and q.Apply then
    q.Apply({ step = shown.step and p.on.step, camp = shown.camp and p.on.camp, light = shown.light and p.on.light,
      accept = shown.accept and p.accept, handin = shown.handin and p.on.handin, campOn = shown.camp and p.on.camp })
  end
  -- the keys: the card's choice per window; the Guild key waits for a guild (Keys.lua)
  if type(ch.keys) ~= "table" then ch.keys = {} end
  if shown.guild then ch.keys.guild = p.keys.guild end
  if shown.quests then ch.keys.quests = p.keys.quests end
  if shown.mapwin then ch.keys.map = p.keys.map end
  ch.setupLater = nil
  -- (the quest window opens once after the reload; a card with the Map row alone, the map)
  if shown.quests then ch.openAfter = "quests" elseif shown.mapwin and p.on.mapwin then ch.openAfter = "map" end
  card:Hide()
  S.pick = nil
  local reload = (type(C_UI) == "table" and C_UI.Reload) or ReloadUI
  if type(reload) == "function" then reload() end
  return true
end
-- Not now: nothing changes, and the card waits for the menu
function S.Later()
  C.Char().setupLater = true
  card:Hide()
  S.pick = nil
end
-- whether the menu offers "Set up Cute...": a row this character has not answered
function S.Pending() return #rows() > 0 end

-- the first loading screen out of combat and outside an instance: the card, 3 s on, once a session; and after a
-- Start's reload the quest window opens once
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", C.Safe(function()
  local ch = C.Char()
  if ch.openAfter then
    local page = ch.openAfter
    ch.openAfter = nil
    C_Timer.After(1, C.Safe(function() if C.Modules.Page(page, C.Roster:MeOfficer()) then C.UI:Open(page) end end, "setup: open after"))
  end
  if S.told or ch.setupLater then return end
  if inCombat() or inInstance() then return end
  S.told = true
  C_Timer.After(3, C.Safe(function() if not inCombat() then S.Show(false) end end, "setup: show"))
end, "setup: entering the world"))

----------------------------------------------------------------------------
-- the reload rule's question: Settings closed with module changes staged (Modules.lua) asks Reload (the default) or
-- Undo, the game's own popup; Esc is Undo (StaticPopup.lua:788-794, 842-853: hideOnEscape calls OnCancel); there is no
-- Later, so a half-applied state never exists. In a fight the question waits for its end
----------------------------------------------------------------------------
local POPUP = "CUTE_RELOAD"
local waiting
local function ask()
  if not C.Modules.Staged() then return end
  if inCombat() then
    if not waiting then
      waiting = CreateFrame("Frame")
      waiting:SetScript("OnEvent", C.Safe(function(self) self:UnregisterEvent("PLAYER_REGEN_ENABLED"); ask() end, "settings: after combat"))
    end
    waiting:RegisterEvent("PLAYER_REGEN_ENABLED")
    return
  end
  if type(StaticPopupDialogs) ~= "table" or not callable("StaticPopup_Show") then
    -- (no popup on this client: the staged change is undone, as Esc would)
    C.Modules.Undo()
    return
  end
  StaticPopupDialogs[POPUP] = StaticPopupDialogs[POPUP] or {
    text = "Cute reloads to apply your changes.", button1 = "Reload", button2 = "Undo",
    OnAccept = function() C.Modules.Commit() end,
    OnCancel = function() C.Modules.Undo() end,
    hideOnEscape = true, timeout = 0, whileDead = true,
  }
  StaticPopup_Show(POPUP)
end
S.Ask = ask
C.UI.Window("settings").OnClose = function() ask() end
