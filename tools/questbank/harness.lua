-- Mock WoW client for QuestBank: loads the addon, drives every page, fails on any
-- widget method outside a whitelist of real API methods.
math.randomseed = nil  -- the client has none
local unpack = unpack or table.unpack

local METHODS = {}
local function allow(list) for m in list:gmatch("%S+") do METHODS[m] = true end end
allow([[SetPoint ClearAllPoints SetAllPoints SetSize SetWidth SetHeight GetWidth GetHeight Show Hide SetShown IsShown
IsVisible SetAlpha GetAlpha GetParent GetPoint GetCenter GetEffectiveScale SetParent CreateTexture CreateFontString
SetScript GetScript HookScript RegisterEvent UnregisterEvent SetFrameStrata SetFrameLevel SetToplevel EnableMouse
EnableMouseWheel SetMovable SetClampedToScreen RegisterForDrag StartMoving StopMovingOrSizing GetName IsMouseOver
SetScrollChild SetVerticalScroll GetVerticalScroll SetText GetText SetNormalTexture SetHighlightTexture SetPushedTexture
RegisterForClicks SetEnabled Enable Disable GetFontString SetOrientation SetThumbTexture SetMinMaxValues GetMinMaxValues
SetValueStep SetValue GetValue SetTexture SetColorTexture SetTexCoord SetVertexColor SetDesaturated SetBlendMode
SetFontObject SetFont GetFont SetTextColor SetJustifyH SetJustifyV SetWordWrap GetStringWidth GetStringHeight]])
local BACKDROP = { SetBackdrop = true, SetBackdropColor = true, SetBackdropBorderColor = true }

local created = 0
local function newObj(kind, template)
  created = created + 1
  local o = { __kind = kind, __scripts = {}, __shown = kind ~= "Frame-hidden", __w = 0, __h = 0, __text = "", __value = 0, __min = 0, __max = 0 }
  o.__backdrop = template and template:find("BackdropTemplate") and true or false
  local mt = {}
  mt.__index = function(t, k)
    if METHODS[k] or (BACKDROP[k] and t.__backdrop) then
      return function(self, ...)
        local a = { ... }
        if k == "SetScript" then self.__scripts[a[1]] = a[2]
        elseif k == "GetScript" then return self.__scripts[a[1]]
        elseif k == "HookScript" then local old = self.__scripts[a[1]]; self.__scripts[a[1]] = function(...) if old then old(...) end a[2](...) end
        elseif k == "CreateTexture" then return newObj("Texture")
        elseif k == "CreateFontString" then return newObj("FontString")
        elseif k == "Show" then local was = self.__shown; self.__shown = true; if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end
        elseif k == "Hide" then local was = self.__shown; self.__shown = false; if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
        elseif k == "SetShown" then if a[1] then self:Show() else self:Hide() end
        elseif k == "IsShown" or k == "IsVisible" then return self.__shown
        elseif k == "SetSize" then self.__w, self.__h = a[1], a[2]
        elseif k == "SetWidth" then self.__w = a[1]
        elseif k == "SetHeight" then self.__h = a[1]
        elseif k == "GetWidth" then return self.__w
        elseif k == "GetHeight" then return self.__h
        elseif k == "SetText" then self.__text = a[1] == nil and "" or tostring(a[1])
        elseif k == "GetText" then return self.__text
        elseif k == "GetStringWidth" then return #self.__text * 6
        elseif k == "GetStringHeight" then return 14
        elseif k == "GetFont" then return "Fonts\\FRIZQT__.TTF", 12, ""
        elseif k == "SetMinMaxValues" then self.__min, self.__max = a[1], a[2]
        elseif k == "GetMinMaxValues" then return self.__min, self.__max
        elseif k == "SetValue" then self.__value = a[1]; if self.__scripts.OnValueChanged then self.__scripts.OnValueChanged(self, a[1]) end
        elseif k == "GetValue" then return self.__value
        elseif k == "GetCenter" then return 500, 400
        elseif k == "GetEffectiveScale" then return 1
        elseif k == "GetPoint" then return "CENTER", nil, "CENTER", 0, 0
        elseif k == "GetName" then return self.__name
        elseif k == "SetTexture" then self.__tex = a[1]
        elseif k == "SetColorTexture" then self.__tex = "color"
        end
        return nil
      end
    end
    if type(k) == "string" and k:match("^%l") then return nil end  -- plain fields read nil, like on a real frame
    error("unknown widget method: " .. tostring(k) .. " on " .. kind, 2)
  end
  return setmetatable(o, mt)
end

local function fontObj() local f = newObj("Font"); return f end
_G.GameFontNormal = fontObj(); _G.GameFontNormalLarge = fontObj(); _G.GameFontHighlightSmall = fontObj()
_G.GameFontNormalSmall = fontObj(); _G.NumberFontNormal = fontObj()
_G.BackdropTemplateMixin = {}
_G.UIParent = newObj("Frame"); _G.Minimap = newObj("Frame"); Minimap:SetSize(140, 140)
_G.UISpecialFrames = {}
local lines = {}
_G.GameTooltip = setmetatable({}, { __index = function(_, k)
  return function(_, ...) if k == "AddLine" or k == "AddDoubleLine" then lines[#lines + 1] = table.concat({ tostring((...)) }, " ") end end
end })
function _G.CreateFrame(kind, name, parent, template)
  local o = newObj(kind, template)
  o.__name = name
  if name then _G[name] = o end
  if kind == "Frame" or kind == "Button" then end
  return o
end
local timers = {}
_G.C_Timer = { After = function(_, f) timers[#timers + 1] = f end }
local function runTimers() local t = timers; timers = {}; for _, f in ipairs(t) do f() end end
local chat = {}
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
_G.SlashCmdList = {}
_G.date = os.date
_G.IsShiftKeyDown = function() return _G.__shift end
_G.GetCursorPosition = function() return 600, 500 end
_G.SetPortraitTexture = function() end
_G.GetBindLocation = function() return "Stormwind City" end
_G.IsPlayerSpell = function() return _G.__riding or false end
_G.AuraUtil = { FindAuraByName = function(name) if _G.__rested and name == "Well Rested" then return name end end }
_G.UnitName = function() return "Mikal" end
_G.UnitLevel = function() return _G.__level or 20 end
_G.UnitXP = function() return _G.__xp or 0 end
_G.UnitXPMax = function() return 23200 end
_G.UnitClass = function() return "Paladin", "PALADIN" end
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance" end
_G.GetNormalizedRealmName = function() return "ForeverNormal" end
local pins = {}
_G.UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m = m, x = x, y = y } end }
_G.C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }

-- the user's log: C = objectives done
local LOG = {
  { 971, 1 }, { 1275, 1 }, { 1199, 1 }, { 97894, 1 }, { 2922, 0 }, { 2926, 0 }, { 2928, 0 }, { 454, 1 }, { 217, 0 }, { 297, 0 },
  { 255, 0 }, { 143, 1 }, { 131, 1 }, { 116, 1 }, { 92, 0 }, { 118, 1 }, { 150, 1 }, { 98387, 1 }, { 127, 0 }, { 91, 0 },
  { 34, 0 }, { 128, 0 }, { 95999, 1 }, { 169, 1 }, { 180, 1 }, { 95189, 1 }, { 399, 1 }, { 353, 1 }, { 343, 1 }, { 79192, 1 },
  { 168, 1 }, { 167, 1 }, { 391, 1 }, { 1486, 1 }, { 1487, 1 }, { 276, 0 }, { 470, 0 }, { 1654, 1 },
}
local DONE = { [96393] = true, [96394] = true, [96395] = true, [96403] = true, [98423] = true, [96391] = true, [6981] = true,
  [155] = true, [142] = true, [141] = true, [135] = true, [132] = true, [65] = true, [1198] = false, [389] = true, [373] = true }
local BAGS = { [268540] = 4, [251522] = 1 }
_G.C_QuestLog = {
  IsQuestFlaggedCompleted = function(id) return DONE[id] or false end,
  GetNumQuestLogEntries = function() return #LOG + 3 end,
  GetInfo = function(i)
    if i == 1 then return { title = "Redridge Mountains", isHeader = true } end
    if i == 2 then return { title = "Dungeons", isHeader = true } end
    if i == 3 then return { title = "Loch Modan", isHeader = true } end
    local e = LOG[i - 3]
    if not e then return nil end
    return { title = "Quest " .. e[1], level = 20, questID = e[1], isHeader = false }
  end,
  IsComplete = function(id) for _, e in ipairs(LOG) do if e[1] == id then return e[2] == 1 end end return false end,
  GetQuestObjectives = function(id) return { { text = "thing", finished = false, numFulfilled = 3, numRequired = 10 } } end,
  GetAllCompletedQuestIDs = function() local t = {} for k, v in pairs(DONE) do if v then t[#t + 1] = k end end return t end,
}
_G.C_Item = { GetItemCount = function(id) return BAGS[id] or 0 end, GetItemIconByID = function(id) return 133328 end }
_G.C_Map = { GetBestMapForUnit = function() return 1453 end, CanSetUserWaypointOnMap = function() return true end,
  SetUserWaypoint = function(p) pins[#pins + 1] = p end }
_G.C_Container = {
  GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
  GetContainerItemID = function(_, slot) return slot == 1 and 268540 or 251522 end,
  GetContainerItemLink = function(_, slot) return slot == 1 and "[Bloodied Insignia]" or "[Blood-Stained Letter]" end,
  GetContainerItemInfo = function(_, slot) return { stackCount = slot == 1 and 4 or 1 } end,
}

-- load the addon in TOC order
local QB = {}
for _, f in ipairs({ "Data.lua", "Core.lua", "Model.lua", "UI.lua" }) do
  local chunk = assert(loadfile((arg and arg[0] and arg[0]:match("^(.*)/") or ".") .. "/QuestBank/" .. f))
  chunk("QuestBank", QB)
end
local ev = QB.eventFrame.__scripts.OnEvent
ev(QB.eventFrame, "ADDON_LOADED", "QuestBank")
ev(QB.eventFrame, "PLAYER_LOGIN")
runTimers()
assert(QuestBankDB.chars["Mikal-ForeverNormal"], "login snapshot")

-- open and walk every page
SlashCmdList.QUESTBANK("")
local UI = QB.UI
assert(UI.frame:IsShown(), "window opens")
for tab = 1, 3 do UI:ShowTab(tab) end
local v1, v2, v3 = UI.views[1], UI.views[2], UI.views[3]
print("log title:", v1.title:GetText(), "|", v1.worth:GetText())
print("header:", UI.header.legend:GetText())

-- hover and click everything that has a script
local function poke(obj)
  local s = obj.__scripts
  if s.OnEnter then lines = {}; s.OnEnter(obj); assert(#lines > 0, "tooltip empty"); s.OnLeave(obj) end
  if s.OnClick then s.OnClick(obj, "LeftButton") end
end
UI:ShowTab(1)
for _, b in ipairs(v1.slots) do poke(b) end
for _, b in ipairs(v1.bagSlots) do poke(b) end
for _, r in ipairs(v1.swaps) do if r:IsShown() then poke(r) end end
local shown = 0
for _, r in ipairs(v1.swaps) do if r:IsShown() then shown = shown + 1; print(string.format("  swap: %-28s -> %-32s %s", r.cutName:GetText(), r.addName:GetText(), r.gain:GetText())) end end
print("swaps shown:", shown)
UI:ShowTab(2)
for _, c in ipairs(v2.cards.items) do
  if c:IsShown() then
    print(string.format("  card %-26s %-12s %s", c.title:GetText(), c.gain:GetText(), c.count:GetText()))
    poke(c.pin)
    for _, r in ipairs(c.rows.items) do if r:IsShown() then poke(r) end end
  end
end
UI:ShowTab(3)
print("route now:", v3.summary:GetText())
print("setup:", v3.setup:GetText())
for _, l in ipairs(v3.legs.items) do
  if l:IsShown() then
    print(string.format("  %s %-22s %-28s %s", l.clock:GetText(), l.name:GetText(), l.travel:GetText(), l.level:GetText()))
    poke(l.pin)
    for _, r in ipairs(l.rows) do if r:IsShown() then poke(r) end end
  end
end
v3.modePlan.__scripts.OnClick(v3.modePlan)
print("route plan:", v3.summary:GetText())
print("setup:", v3.setup:GetText())

-- header toggles, left and right click
for _, key in ipairs({ "mounted", "bag", "goal", "pin" }) do
  local b = UI.header.toggles[key]
  lines = {}; b.__scripts.OnEnter(b); assert(#lines > 0)
  b.__scripts.OnClick(b, "LeftButton")
  b.__scripts.OnClick(b, "RightButton")
end
UI:ShowTab(3)
print("after toggles:", v3.summary:GetText())

-- shift-click a prep row out of the plan and back
UI:ShowTab(2)
_G.__shift = true
local row
for _, c in ipairs(v2.cards.items) do for _, r in ipairs(c.rows.items) do if r:IsShown() and r.q then row = row or r end end end
local id = row.q.id
row.__scripts.OnClick(row, "LeftButton")
assert(QuestBankDB.settings.plan[id] ~= nil, "shift-click toggles the plan")
_G.__shift = false

-- events during the turn-in hour
ev(QB.eventFrame, "QUEST_TURNED_IN", 971, 10300)
ev(QB.eventFrame, "BAG_UPDATE_DELAYED")
ev(QB.eventFrame, "UNIT_AURA", "target")
ev(QB.eventFrame, "UNIT_AURA", "player")
runTimers()
print("chat:", chat[#chat])

-- minimap button: drag and click
local mb = QB.Minimap.button
assert(mb, "minimap button")
mb.__scripts.OnDragStart(mb); mb.__scripts.OnUpdate(mb); mb.__scripts.OnDragStop(mb)
mb.__scripts.OnClick(mb, "RightButton")
lines = {}; mb.__scripts.OnEnter(mb); assert(#lines > 0)

-- slash commands and export
SlashCmdList.QUESTBANK("export")
SlashCmdList.QUESTBANK("route")
SlashCmdList.QUESTBANK("prep")
SlashCmdList.QUESTBANK("minimap")
SlashCmdList.QUESTBANK("reset")
ev(QB.eventFrame, "PLAYER_LOGOUT")
print("map pins set:", #pins, "widgets created:", created)

-- level 24 with some XP: the planner follows the character
_G.__level, _G.__xp = 24, 12000
QB:MarkDirty(); UI:Refresh()
print("at level 24:", v3.summary:GetText())
print("OK")
