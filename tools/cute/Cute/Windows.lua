-- SPDX-License-Identifier: GPL-3.0-or-later
-- Windows: what joins Cute's windows to the game and to each other.
--   the game's own windows   each header's button to the game's window: a SecureActionButtonTemplate of type click on
--                            the game's micro button, so the press runs the game's button as the game (Guild &
--                            Communities, the Quest log). It is no child of the window (a protected child would make
--                            the window protected, and Cute's windows open and close in a fight): it sits over its
--                            place in the header, parented to UIParent, placed and shown out of combat; in a fight a
--                            plain stand-in says "After combat" until it ends
--   the menu                 right-click on the minimap button (or the game's addon compartment): every window's tabs,
--                            each Settings section, the on-screen switches; a parent opens its own window when clicked
--   the slash words          /cute quests | route | dungeons | gear | settings [section] | keys | setup | menu; the
--                            old /cute guide and /cute journal open Quests and Dungeons
local _, C = ...
local W = {}
C.Windows = W

local function callable(name) return type(_G[name]) == "function" end
local function inCombat() return callable("InCombatLockdown") and C.Get(InCombatLockdown) == true end

----------------------------------------------------------------------------
-- the header's button to the game's own window
----------------------------------------------------------------------------
-- (MainMenuBarMicroButtons.xml:196 QuestLogMicroButton, :229 GuildMicroButton; SecureTemplates.lua:557 the click action)
local GAME = {
  guild = { label = "Guild & Communities", micro = "GuildMicroButton", tip = "The game's Guild & Communities: chat, the message of the day, notes, ranks and invites." },
  quests = { label = "Quest log", micro = "QuestLogMicroButton", tip = "The game's own quest log." },
}
W.GAME = GAME
local secure = {}
-- the stand-in in the header (always there, so the title knows its room) and, over it out of combat, the secure button
function W.GameButton(win)
  local g = GAME[win.key]
  if not g or win.gameStand then return end
  local UI = C.UI
  local micro = _G[g.micro]
  -- (a UI addon that removed the micro button: no button at all)
  if not micro then return end
  local b = UI.Button(win.head, g.label, 140, 20)
  local w = math.ceil(((b.label.GetUnboundedStringWidth or b.label.GetStringWidth)(b.label) or 0) + 20)
  b:SetWidth(w)
  b:SetPoint("RIGHT", -(win.headRight or 30), 0)
  b:SetScript("OnClick", nil)
  b:SetScript("OnEnter", C.Safe(function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(g.label, 1, 1, 1)
    GameTooltip:AddLine(inCombat() and "After combat: in a fight the game's micro menu opens it." or g.tip, 0.85, 0.85, 0.85, true)
    GameTooltip:Show()
  end, "game button: tooltip"))
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  win.gameStand = b
  W.Place(win)
end
local function makeSecure(win)
  local g = GAME[win.key]
  local micro = g and _G[g.micro]
  if secure[win.key] or not micro or inCombat() then return secure[win.key] end
  local UI = C.UI
  local s = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate" .. (BackdropTemplateMixin and ",BackdropTemplate" or ""))
  s:SetFrameStrata("DIALOG")
  s:RegisterForClicks("AnyUp")
  s:SetAttribute("type", "click")
  s:SetAttribute("clickbutton", micro)
  UI.Skin(s, { 0.11, 0.11, 0.11 })
  s.label = UI.Text(s, 12, UI.COLORS.INK, "CENTER")
  s.label:SetPoint("TOPLEFT", 4, 0)
  s.label:SetPoint("BOTTOMRIGHT", -4, 0)
  s.label:SetText(g.label)
  s:SetHighlightTexture("Interface\\Buttons\\WHITE8x8", "ADD")
  s:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
  s:SetScript("OnEnter", win.gameStand:GetScript("OnEnter"))
  s:SetScript("OnLeave", function() GameTooltip:Hide() end)
  s:Hide()
  secure[win.key] = s
  return s
end
W.secure = secure
-- the secure button over its stand-in while the window shows, out of combat; hidden otherwise. Placed by the
-- stand-in's place on the screen, never anchored to the window (a protected frame anchored to a frame that moves in a
-- fight)
function W.Place(win)
  local stand = win.gameStand
  if not stand or inCombat() then return end
  local s = makeSecure(win)
  if not s then return end
  if win.frame:IsShown() then
    local x, y = stand:GetLeft(), stand:GetTop()
    if type(x) ~= "number" or type(y) ~= "number" then s:Hide() return end
    s:ClearAllPoints()
    s:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    s:SetSize(stand:GetWidth() or 120, 20)
    s:Show()
  else
    s:Hide()
  end
end
-- before a fight's lockdown (PLAYER_REGEN_DISABLED comes before it) every secure button hides; after it, each is placed
-- again
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", C.Safe(function(_, event)
  for key, s in pairs(secure) do
    if event == "PLAYER_REGEN_DISABLED" then s:Hide()
    else local win = C.UI.windows[key]; if win then W.Place(win) end end
  end
  for _, win in pairs(C.UI.windows) do
    if win.gameStand then C.UI.Color(win.gameStand.label, event == "PLAYER_REGEN_DISABLED" and C.UI.COLORS.MUTE or C.UI.COLORS.INK) end
  end
end, "game buttons: combat"))

-- each window built: its game button, and the secure one following it as it shows, hides, moves and is resized
local built = C.UI.OnBuilt
function C.UI:OnBuilt()
  if built then built(self) end
  W.GameButton(self)
  if self.gameStand then
    self.frame:HookScript("OnShow", function() W.Place(self) end)
    self.frame:HookScript("OnHide", function() W.Place(self) end)
    self.frame:HookScript("OnSizeChanged", function() W.Place(self) end)
    self.head:HookScript("OnDragStop", function() W.Place(self) end)
    self.grip:HookScript("OnMouseUp", function() W.Place(self) end)
  end
end

-- /cute diag's line for what only the live client shows: each game button (none, waiting, shown, hidden, and whether
-- the client calls its frame protected), the keys held by override (the key names alone), whether they wait for a
-- fight's end, and the game's menus. Never a name
function W.DiagLine()
  local parts = {}
  for _, key in ipairs({ "guild", "quests" }) do
    local win, s = C.UI.windows[key], secure[key]
    local state
    if not (win and win.gameStand) then state = _G[GAME[key].micro] and "unbuilt" or "no micro button"
    elseif not s then state = "waiting"
    else
      -- (IsProtected's answer may be secret: SimpleScriptRegionAPIDocumentation.lua:540, ObjectSecurity)
      local okP, prot = pcall(s.IsProtected, s)
      state = (s:IsShown() and "shown" or "hidden") .. ((okP and C.Plain(prot) == true) and " protected" or "")
    end
    parts[#parts + 1] = key .. " " .. state
  end
  local held = {}
  for k, id in pairs(C.Keys and C.Keys.held or {}) do held[#held + 1] = k .. "=" .. id end
  table.sort(held)
  return string.format("diag windows: game buttons %s; keys %s (applied %d)%s; menus %s; in combat %s", table.concat(parts, ", "),
    #held > 0 and table.concat(held, " ") or "none", C.Keys and C.Keys.applied or 0, (C.Keys and C.Keys.waiting) and ", waiting for the fight's end" or "",
    (type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function") and "yes" or "no", inCombat() and "yes" or "no")
end
do
  local coreDiag = C.Diag
  function C.Diag()
    local lines = coreDiag and coreDiag() or {}
    local ok, l = pcall(W.DiagLine)
    lines[#lines + 1] = ok and l or ("diag windows: " .. tostring(l))
    return lines
  end
end

----------------------------------------------------------------------------
-- the menu: right-click on the minimap button, or the game's addon compartment
----------------------------------------------------------------------------
-- a window's name with the key this character has for it: "Guild (J)"
local function withKey(text, id)
  local k = C.Keys and C.Keys.KeysFor(id)[1]
  return k and (text .. " (" .. k .. ")") or text
end
W.WithKey = withKey
-- (MenuUtil.CreateContextMenu, as camelot's own code builds its menus, FriendsFrame.lua:2191; a parent with a submenu
-- opens its own window when clicked: SetShouldRespondIfSubmenu, Menu.lua:742)
function W.Menu(owner)
  if not (type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function") then
    -- (a client without the game's menus: Settings, where every part is)
    C.UI.OpenSettings()
    return
  end
  local UI, M = C.UI, C.Modules
  MenuUtil.CreateContextMenu(owner or UIParent, function(_, root)
    local officer = C.Roster:MeOfficer()
    root:CreateTitle("Cute")
    local function parent(text, fn)
      local d = root:CreateButton(text, C.Safe(fn, "menu"))
      if d and d.SetShouldRespondIfSubmenu then d:SetShouldRespondIfSubmenu(true) end
      return d
    end
    local function item(d, text, fn) if d then d:CreateButton(text, C.Safe(fn, "menu: " .. text)) end end
    local g = parent(withKey("Guild", "guild"), function() UI:Open(UI.page or "race") end)
    for _, m in ipairs(M.Pages(officer, "guild")) do item(g, m.title, function() UI:Open(m.id) end) end
    local tabs = M.Pages(officer, "quests")
    if #tabs > 0 then
      local q = parent(withKey("Quests", "quests"), function() UI:Open("quests") end)
      for _, m in ipairs(tabs) do item(q, m.title, function() UI:Open(m.id) end) end
      -- the on-screen switches (Cute_Quest's Band.lua: the step frame, the arrow)
      local switches = C.API.OnScreen and C.API.OnScreen() or {}
      if #switches > 0 and q then
        q:CreateDivider()
        for _, sw in ipairs(switches) do q:CreateCheckbox(sw[1], sw[2], C.Safe(sw[3], "menu: " .. sw[1])) end
      end
    end
    local s = parent("Settings", function() UI.OpenSettings() end)
    for _, sec in ipairs(C.SettingsPage.Sections(officer)) do item(s, sec.title, function() UI.OpenSettings(sec.id) end) end
    local staged, setup = M.Staged(), C.Setup and C.Setup.Pending()
    if staged or setup then root:CreateDivider() end
    if staged then root:CreateButton("Reload to apply", C.Safe(function() if not M.Commit() then UI.OpenSettings("modules") end end, "menu: reload")) end
    if setup then root:CreateButton("Set up Cute...", C.Safe(function() C.Setup.Show(true) end, "menu: setup")) end
  end)
end
-- the game's addon compartment (Cute.toc "## AddonCompartmentFunc"; the compartment passes the mouse button,
-- Mainline/AddonCompartment.lua:81-104): a click opens the guild window, a right-click the menu, as the minimap button
function Cute_OnCompartment(_, button)
  C.Safe(function()
    if button == "RightButton" then W.Menu() else C.UI:Toggle() end
  end, "compartment")()
end

----------------------------------------------------------------------------
-- the slash words, before the core's (Core.lua's /cute takes the rest)
----------------------------------------------------------------------------
local WORD = { quests = "quests", guide = "quests", route = "route", dungeons = "journal", journal = "journal", gear = "gear" }
local function sectionOf(rest)
  if rest == "" then return nil end
  for _, sec in ipairs(C.SettingsPage.Sections(C.Roster:MeOfficer())) do
    if sec.id == rest or sec.title:lower() == rest or sec.title:lower():gsub("%s+", "") == rest:gsub("%s+", "") then return sec.id end
  end
  return nil
end
do
  local core = SlashCmdList.CUTE
  SlashCmdList.CUTE = C.Safe(function(msg)
    local m = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local word, rest = m:match("^(%S*)%s*(.-)$")
    local page = WORD[word]
    if page and rest == "" then
      if not C.Modules.byId.quests then C.Print("the quest window comes with Cute_Quest, which this client does not have.") return end
      if not C.Modules.Page(page, C.Roster:MeOfficer()) then C.Print(C.Modules.byId[page] and (C.Modules.byId[page].title .. " is off for this character: Settings, Modules switches it on.") or "no such tab.") C.UI.OpenSettings("modules") return end
      C.UI:Open(page)
      return
    end
    if word == "settings" or word == "options" then C.UI.OpenSettings(sectionOf(rest)) return end
    if word == "keys" and rest == "" then C.UI.OpenSettings("keys") return end
    if word == "setup" and rest == "" then C.Setup.Show(true) return end
    if word == "menu" and rest == "" then W.Menu() return end
    -- (help in two lines, as the core's, naming both windows: the core's first line knew one)
    if m == "help" then
      C.Print("/cute opens the guild window, /cute quests your quests" .. (C.Modules.byId.quests and "" or " (with Cute_Quest)") .. "; /cute settings, keys, setup or menu; /cute race, prog, shame, statistics, officers, me, route, dungeons, gear or a module's name opens that tab.")
      C.Print("/cute modules lists the modules; /cute resend asks the guild for their records again; /cute help more: what to paste in a bug report.")
      return
    end
    return core(msg)
  end, "slash")
end
