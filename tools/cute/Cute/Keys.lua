-- SPDX-License-Identifier: GPL-3.0-or-later
-- Keys: the keys that open Cute's windows, as override bindings that follow the player's own. Never the game's binding
-- set: SetBinding and SaveBindings would write the player's account or character keys and leave a key bound to a dead
-- action once Cute is gone; an override binding lives as long as this session's owner frame holds it.
--   CuteKeyOwner holds the overrides; CuteGuildKey and CuteQuestsKey (CuteMapKey with the map) are hidden buttons whose
--   click toggles their window. For each window that is on, out of combat:
--     SetOverrideBindingClick(CuteKeyOwner, false, key, "CuteGuildKey")
--   (the game's own gamepad bindings make overrides the same way, InputButtonBinding.lua:28)
--   The setting, per character: CuteDB.chars[me].keys = { guild = "follow", quests = "follow" }. "follow" takes every
--   key the game has for its own window's action (TOGGLEGUILDTAB, TOGGLEQUESTLOG: Bindings_Camelot.xml:1229, 1248),
--   so rebinding the game's key moves Cute's with it; a key string takes that key; false takes none; nil (a character
--   that never answered the setup card) takes none either.
--   Applied at the first loading screen, on UPDATE_BINDINGS and PLAYER_GUILD_UPDATE, and on a change, always after
--   ClearOverrideBindings(CuteKeyOwner). In a fight the apply waits for PLAYER_REGEN_ENABLED (no written lockdown rule
--   for these calls: treated as protected). The Guild key is taken only while the character is in a guild.
-- The key box (Settings > Keys, the setup card): a click shows "Press a key" (modifiers allowed), Esc keeps the old one,
-- Backspace clears it; a hand-picked key that does something else in the game says what in one line under its row.
local _, C = ...
local K = {}
C.Keys = K

local INK = { 0.86, 0.86, 0.86 }
local WHITE = { 0.96, 0.96, 0.96 }
local WARN = { 0.93, 0.74, 0.35 }
local MUTE = { 0.52, 0.52, 0.52 }

-- the windows a key opens: the guild's always; the quests' while a module addon draws in it (Cute_Quest)
local WINDOWS = {
  { id = "guild", label = "Guild window", game = "Guild & Communities", action = "TOGGLEGUILDTAB", button = "CuteGuildKey", binding = "CUTE_TOGGLE" },
  { id = "quests", label = "Quests window", game = "Quest log", action = "TOGGLEQUESTLOG", button = "CuteQuestsKey", binding = "CUTE_QUESTS" },
}
K.ALL = WINDOWS
function K.Windows()
  local out = {}
  for _, w in ipairs(WINDOWS) do
    if w.id == "guild" or C.Modules.byId[C.UI.SPEC[w.id] and C.UI.SPEC[w.id].home or ""] or K.Expected(w.id) then out[#out + 1] = w end
  end
  return out
end
-- a window whose module addon is on its way: it loads once a fight at the login ends, and registers its pages then
-- (Modules.lua M.BaseComing; one that did not load is no window, so no key is held for it)
function K.Expected(id)
  if id ~= "quests" then return false end
  return C.Modules.BaseComing()
end
local function byId(id) for _, w in ipairs(WINDOWS) do if w.id == id then return w end end end

local function callable(name) return type(_G[name]) == "function" end
local function inCombat() return callable("InCombatLockdown") and C.Get(InCombatLockdown) == true end

-- this character's setting for a window: "follow", a key, false, or nil (never answered)
local function keysTable(create)
  local ch = C.Char()
  if type(ch.keys) ~= "table" then
    if not create then return nil end
    ch.keys = {}
  end
  return ch.keys
end
function K.Get(id) local t = keysTable(false); if t == nil then return nil end return t[id] end
function K.Set(id, v)
  local t = keysTable(true)
  if v ~= "follow" and v ~= false and type(v) ~= "string" then v = false end
  t[id] = v
  K.Apply()
end

-- the keys the game has for an action (GetBindingKey gives its keys in turn, as Blizzard_Keybindings.lua:105 reads
-- them), plain strings only
function K.GameKeys(action)
  local out = {}
  if not callable("GetBindingKey") then return out end
  local keys = { C.Get(GetBindingKey, action) }
  for _, k in ipairs(keys) do if type(k) == "string" and k ~= "" then out[#out + 1] = k end end
  return out
end
-- the keys Cute holds for a window by its setting
function K.KeysFor(id)
  local w = byId(id)
  local v = K.Get(id)
  if not w or v == nil or v == false then return {} end
  if v == "follow" then return K.GameKeys(w.action) end
  return { v }
end
-- what the key box shows: the keys Cute holds, or "-"
function K.Text(id)
  local keys = K.KeysFor(id)
  if #keys == 0 then return "-" end
  return table.concat(keys, ", ")
end
-- a binding of Cute's own set in the game's Key Bindings (Settings, the windows' own), "-" for none
function K.BindingText(binding)
  local keys = K.GameKeys(binding)
  return #keys > 0 and table.concat(keys, ", ") or "-"
end
-- the line under a window's key row: what a hand-picked key did in the game ("replaces Action Button 5", from the
-- game's Key Bindings names: GetBindingAction and BINDING_NAME_), and a key the player gave Cute's binding there
function K.Words(id)
  local w = byId(id)
  if not w then return nil end
  local parts = {}
  local v = K.Get(id)
  if type(v) == "string" and v ~= "follow" and callable("GetBindingAction") then
    local action = C.Plain(C.Get(GetBindingAction, v))
    if type(action) == "string" and action ~= "" and action ~= w.action and action ~= w.binding then
      local name = C.Plain(_G["BINDING_NAME_" .. action])
      parts[#parts + 1] = "replaces " .. ((type(name) == "string" and name ~= "") and name or action)
    end
  end
  local own = K.GameKeys(w.binding)
  if #own > 0 then parts[#parts + 1] = "also " .. table.concat(own, ", ") .. ", from the game's Key Bindings" end
  if id == "guild" and not K.InGuild() then parts[#parts + 1] = "taken once this character is in a guild" end
  return #parts > 0 and table.concat(parts, "; ") or nil
end
function K.InGuild() return callable("IsInGuild") and C.Get(IsInGuild) == true end

----------------------------------------------------------------------------
-- the owner and the buttons a key clicks
----------------------------------------------------------------------------
local owner, regen
local function ensure()
  if owner then return end
  owner = CreateFrame("Frame", "CuteKeyOwner", UIParent)
  for _, w in ipairs(WINDOWS) do
    local b = CreateFrame("Button", w.button, UIParent)
    b:Hide()
    b:SetScript("OnClick", C.Safe(function() C.UI.ToggleWindow(w.id) end, "key: " .. w.id))
    K[w.id .. "Button"] = b
  end
  owner:RegisterEvent("UPDATE_BINDINGS")
  owner:RegisterEvent("PLAYER_GUILD_UPDATE")
  owner:SetScript("OnEvent", C.Safe(function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
      pcall(owner.UnregisterEvent, owner, "PLAYER_REGEN_ENABLED")
      regen = false
    end
    K.Apply()
  end, "keys: events"))
end
K.held = {}
-- the overrides made to match the settings: cleared, then each window's keys; in a fight, after it
function K.Apply()
  ensure()
  if inCombat() then
    if not regen then regen = true; owner:RegisterEvent("PLAYER_REGEN_ENABLED") end
    K.waiting = true
    return false
  end
  K.waiting = false
  if not (callable("ClearOverrideBindings") and callable("SetOverrideBindingClick")) then return false end
  ClearOverrideBindings(owner)
  K.held = {}
  for _, w in ipairs(K.Windows()) do
    if w.id ~= "guild" or K.InGuild() then
      for _, key in ipairs(K.KeysFor(w.id)) do
        if not K.held[key] then
          SetOverrideBindingClick(owner, false, key, w.button)
          K.held[key] = w.id
        end
      end
    end
  end
  K.applied = (K.applied or 0) + 1
  return true
end
-- the first loading screen: the keys this character chose (Core.lua's PLAYER_ENTERING_WORLD reaches here through
-- UI:OnWorld's caller; once a session)
function K.Start()
  if K.started then return end
  K.started = true
  K.Apply()
end

----------------------------------------------------------------------------
-- the key box: a click, then a key
----------------------------------------------------------------------------
local MODIFIER = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, UNKNOWN = true, LMETA = true, RMETA = true }
local function keyName(key)
  local mods = ""
  if IsAltKeyDown and IsAltKeyDown() then mods = mods .. "ALT-" end
  if IsControlKeyDown and IsControlKeyDown() then mods = mods .. "CTRL-" end
  if IsShiftKeyDown and IsShiftKeyDown() then mods = mods .. "SHIFT-" end
  return mods .. key
end
K.KeyName = keyName
-- a box for a window's key (Settings > Keys, the setup card): box:Bind(id) shows its key and takes a new one; box.onKey
-- (where set) is told instead of the setting (the card keeps its choice until Start)
function K.Box(parent)
  local UI = C.UI
  local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  b:SetSize(44, 20)
  UI.Skin(b, { 0.11, 0.11, 0.11 })
  if b.SetBackdropBorderColor then b:SetBackdropBorderColor(0.42, 0.42, 0.42, 1) end
  b.label = UI.Text(b, 12, WHITE, "CENTER")
  b.label:SetPoint("TOPLEFT", 4, 0)
  b.label:SetPoint("BOTTOMRIGHT", -4, 0)
  b:SetHighlightTexture("Interface\\Buttons\\WHITE8x8", "ADD")
  b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
  function b:Show2(text, waiting)
    self.label:SetText(text)
    UI.Color(self.label, waiting and WARN or WHITE)
    local w = ((self.label.GetUnboundedStringWidth or self.label.GetStringWidth)(self.label) or 0) + 16
    self:SetWidth(math.max(waiting and 76 or 44, math.ceil(w)))
  end
  function b:Bind(id, text)
    self.id = id
    self.waiting = false
    self:Show2(text or K.Text(id), false)
  end
  local function stop(self)
    self.waiting = false
    pcall(self.EnableKeyboard, self, false)
    self:SetScript("OnKeyDown", nil)
  end
  b:SetScript("OnClick", C.Safe(function(self)
    if inCombat() then return end -- (keyboard capture is protected in a fight: EnableKeyboard, SimpleFrameAPIDocumentation.lua:247)
    if self.waiting then stop(self); self:Show2(self.onKey and self.shown or K.Text(self.id), false) return end
    self.waiting = true
    self.shown = self.label:GetText()
    self:Show2("Press a key", true)
    pcall(self.EnableKeyboard, self, true)
    pcall(self.SetPropagateKeyboardInput, self, false)
    self:SetScript("OnKeyDown", C.Safe(function(box, key)
      key = C.Plain(key)
      if type(key) ~= "string" or MODIFIER[key] then return end
      stop(box)
      local v
      if key == "ESCAPE" then box:Show2(box.shown, false) return
      elseif key == "BACKSPACE" then v = false
      else v = keyName(key) end
      if box.onKey then box.onKey(v) else K.Set(box.id, v) end
      if C.SettingsPage.Redraw then C.SettingsPage.Redraw() end
    end, "keys: a key"))
  end, "keys: the box"))
  b:SetScript("OnHide", function(self) if self.waiting then stop(self) end end)
  b:SetScript("OnEnter", C.Safe(function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Click, then press a key", 1, 1, 1)
    GameTooltip:AddLine(inCombat() and "After combat." or "Modifiers are allowed. Esc keeps the key; Backspace clears it.", 0.85, 0.85, 0.85, true)
    GameTooltip:Show()
  end, "keys: tooltip"))
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

-- the key bindings Cute adds to the game's (Bindings.xml): the windows' own, and Settings
BINDING_NAME_CUTE_TOGGLE = "Guild window"
BINDING_NAME_CUTE_QUESTS = "Quests window"
