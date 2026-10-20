-- SPDX-License-Identifier: GPL-3.0-or-later
-- Bridge: after the engine's files. QB.Engine is the engine the pages read: this copy, or QuestBankAPI while QuestBank
-- is loaded (then nothing below runs: QuestBank's own window serves its engine). For the copy, what QuestBank's
-- UI.lua (the window, not copied) gave the engine files: the window verbs on QB.UI (Lists.lua made the table), mapped
-- onto Cute's window; the login the engine never sees (loaded on demand, after PLAYER_LOGIN); the module's first-run
-- defaults; /qb routed to Cute's pages and otherwise to the engine's own handler.
local ADDON, QB = ...
local Cute = Cute
QB.Engine = QB.dormant and QuestBankAPI or QB
if QB.dormant then
  -- (QuestBank older than 6.1 sets no QuestBankAPI: the pages say so and draw nothing)
  if not QB.Engine then QB.missing = "QuestBank 6.1 or newer" end
  return
end
local E = QB
local UI = E.UI

-- QuestBank's tab numbers (its UI.lua: 1 Quest Log, 2 Plan, 3 Route, 4 Party, 5 Settings, 6 Now, 7 Journal, 8 Map)
-- as Cute's pages
local PAGE = { [1] = "quests", [2] = "quests", [3] = "route", [4] = "guide", [5] = "settings", [6] = "quests", [7] = "journal", [8] = "quests" }
function UI:Open(tab) Cute.Open(PAGE[tab] or "quests", tab == 5 and "quests" or nil) end
function UI:ShowTab(tab) self:Open(tab) end
function UI:TogglePage(tab) self:Open(tab) end
function UI:Toggle() Cute.Open("quests") end
function UI:Refresh() Cute.Refresh() end
function UI.OpenMap() if type(ToggleWorldMap) == "function" then ToggleWorldMap() end end
function UI.MapPageOn() return false end
function UI.Caret() end
function UI:ShowMenu(title, items)
  if type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function" then
    MenuUtil.CreateContextMenu(UIParent, function(_, root)
      root:CreateTitle(title)
      for _, it in ipairs(items) do root:CreateButton(it[1], it[2]) end
    end)
    return
  end
  local names = {}
  for _, it in ipairs(items) do names[#names + 1] = it[1] end
  Cute.Print(title .. ": no menu on this client (" .. table.concat(names, ", ") .. ").")
end
function UI:CopyLink(title, url) Cute.Print(title .. ": " .. url) end
function UI:PostDialog() end -- (Cute posts nothing: post.auto is off)
function UI:ShowErrors()
  local list = QuestBankDB and QuestBankDB.errors or {}
  Cute.Print(#list .. " quest engine errors" .. (#list > 0 and ", the newest first:" or "."))
  for i = 1, math.min(5, #list) do Cute.Print((list[i].where or "?") .. ": " .. tostring(list[i].msg)) end
end
UI.frame, UI.tab, UI.lastTab, UI.postFrame, UI.scrollToQuest = nil, nil, nil, nil, nil

-- the module's defaults, once: no QuestBank map page (the Map key is the game's), no posting, no update nag, no
-- level-up line, no welcome card (the choices are Settings rows), no minimap button (Cute has one)
local function firstRun()
  local s = E:Settings()
  if s.cuteDefaults then return end
  s.cuteDefaults = true
  s.mapPage, s.post.auto, s.updates, s.clockLevelMsg, s.welcome = false, false, false, false, nil
  s.minimap.hide = true
end

-- the login: this addon is loaded on demand, after PLAYER_LOGIN; the engine's login runs from here once the saved
-- variables are in (ADDON_LOADED, after Shim.lua's alias and Core.lua's QB:Settings)
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", E.Safe(function(self, _, name)
  if name ~= ADDON then return end
  self:UnregisterEvent("ADDON_LOADED")
  firstRun()
  E:Login()
  -- the engine takes the log as read at the game's next QUEST_LOG_UPDATE, which after PLAYER_LOGIN comes at once;
  -- loaded on demand in the middle of a session it could wait minutes for one, so the log is read now
  if not E.logReady and E.eventFrame then
    local handler = E.eventFrame:GetScript("OnEvent")
    if handler then handler(E.eventFrame, "QUEST_LOG_UPDATE") end
  end
end, "cute quest: login"))

-- /qb and /questbank: the pages Cute has, by name; everything else is the engine's own command (skip, way, done,
-- arrow, trace...)
local engineSlash = SlashCmdList.QUESTBANK
local WORD = { [""] = "quests", route = "route", prep = "quests", plan = "quests", available = "quests", journal = "journal", gear = "gear", map = "quests", maps = "quests", settings = "settings", options = "settings" }
SlashCmdList.QUESTBANK = function(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd = msg:match("^(%S*)"):lower()
  local page = WORD[cmd]
  if page and (cmd == msg:lower() or cmd == "") then Cute.Open(page, page == "settings" and "quests" or nil) return end
  if engineSlash then engineSlash(msg) end
end
