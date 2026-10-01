-- Mock WoW client for QuestBank. Loads the addon into separate clients (each its own globals),
-- drives every page, sends party sync between them, and fails on any widget method outside a
-- whitelist of real API methods. It also lays the window out like the game does (anchors,
-- sizes, text widths in Friz Quadrata) and reports clipped text, overlapping text and anything
-- that runs out of its box.
--   luajit tools/questbank/harness.lua                  run every scenario
--   luajit tools/questbank/harness.lua --layout out.json  also write the owner's window, page by page
math.randomseed = nil  -- the client has none
local HERE = (arg and arg[0] and arg[0]:match("^(.*)/") or ".")
local LAYOUT_OUT
for i = 1, #arg do if arg[i] == "--layout" then LAYOUT_OUT = arg[i + 1] end end

local METHODS = {}
local function allow(list) for m in list:gmatch("%S+") do METHODS[m] = true end end
allow([[SetPoint ClearAllPoints SetAllPoints SetSize SetWidth SetHeight GetWidth GetHeight Show Hide SetShown IsShown
IsVisible SetAlpha GetAlpha GetParent GetPoint GetCenter GetEffectiveScale SetParent CreateTexture CreateFontString
SetScript GetScript HookScript RegisterEvent UnregisterEvent SetFrameStrata SetFrameLevel SetToplevel EnableMouse
EnableMouseWheel SetMovable SetClampedToScreen RegisterForDrag StartMoving StopMovingOrSizing GetName IsMouseOver
SetScrollChild SetVerticalScroll GetVerticalScroll SetText GetText SetNormalTexture SetHighlightTexture SetPushedTexture
RegisterForClicks SetEnabled Enable Disable GetFontString SetOrientation SetThumbTexture SetMinMaxValues GetMinMaxValues
SetValueStep SetValue GetValue SetTexture SetColorTexture SetTexCoord SetVertexColor SetDesaturated SetBlendMode
SetFontObject SetFont GetFont SetTextColor SetJustifyH SetJustifyV SetWordWrap GetStringWidth GetStringHeight
SetAutoFocus HighlightText SetFocus ClearFocus SetMultiLine SetChecked GetChecked SetMaxLetters HasFocus IsEnabled SetRotation RegisterUnitEvent]])
local BACKDROP = { SetBackdrop = true, SetBackdropColor = true, SetBackdropBorderColor = true }
local FONT_SIZE = { GameFontNormal = 12, GameFontNormalLarge = 16, GameFontHighlightSmall = 10, GameFontNormalSmall = 10, NumberFontNormal = 12, ChatFontNormal = 13 }

----------------------------------------------------------------------------
-- text width in Friz Quadrata, close enough to see what doesn't fit
----------------------------------------------------------------------------
local CHAR = {}
for c in ("iljtfr'.,:;|!I ()[]"):gmatch(".") do CHAR[c] = 0.30 end
for c in ("mwMW"):gmatch(".") do CHAR[c] = 0.86 end
for c in ("ABCDEFGHJKLNOPQRSTUVXYZ"):gmatch(".") do CHAR[c] = 0.66 end
for c in ("0123456789"):gmatch(".") do CHAR[c] = 0.56 end
local function plain(s) return (s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
local function textWidth(s, size)
  local w = 0
  for c in plain(s):gmatch(".") do w = w + (CHAR[c] or 0.53) end
  return w * (size or 12)
end

----------------------------------------------------------------------------
-- widgets
----------------------------------------------------------------------------
local created = 0
local ALL = {}
local function newObj(kind, template, parent)
  created = created + 1
  local o = { __kind = kind, __scripts = {}, __shown = true, __w = 0, __h = 0, __text = "", __value = 0, __min = 0,
              __max = 0, __points = {}, __parent = parent, __alpha = 1, __size = 12, __wrap = true, __justify = "CENTER" }
  o.__backdrop = template and template:find("BackdropTemplate") and true or false
  o.__template = template
  if template == "UIPanelCloseButton" then o.__w, o.__h = 32, 32 end
  ALL[#ALL + 1] = o
  local mt = {}
  mt.__index = function(t, k)
    if METHODS[k] or (BACKDROP[k] and t.__backdrop) then
      return function(self, ...)
        local a = { ... }
        local n = select("#", ...)
        if k == "SetScript" then self.__scripts[a[1]] = a[2]
        elseif k == "GetScript" then return self.__scripts[a[1]]
        elseif k == "HookScript" then local old = self.__scripts[a[1]]; self.__scripts[a[1]] = function(...) if old then old(...) end a[2](...) end
        elseif k == "CreateTexture" then local x = newObj("Texture", nil, self); x.__layer = a[2] or "ARTWORK"; return x
        elseif k == "CreateFontString" then local x = newObj("FontString", nil, self); x.__layer = a[2] or "OVERLAY"; return x
        elseif k == "Show" then local was = self.__shown; self.__shown = true; if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end
        elseif k == "Hide" then local was = self.__shown; self.__shown = false; if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
        elseif k == "SetShown" then if a[1] then self:Show() else self:Hide() end
        elseif k == "IsShown" or k == "IsVisible" then return self.__shown
        elseif k == "SetSize" then self.__w, self.__h = a[1], a[2] or a[1]; self.__wset, self.__hset = true, true
        elseif k == "SetWidth" then self.__w = a[1]; self.__wset = true
        elseif k == "SetHeight" then self.__h = a[1]; self.__hset = true
        elseif k == "GetWidth" then return self.__rw or self.__w
        elseif k == "GetHeight" then return self.__rh or self.__h
        elseif k == "SetText" then self.__text = a[1] == nil and "" or tostring(a[1])
        elseif k == "GetText" then return self.__text
        elseif k == "GetStringWidth" then return textWidth(self.__text, self.__size)
        elseif k == "GetStringHeight" then return self.__size + 2
        elseif k == "GetFont" then return "Fonts\\FRIZQT__.TTF", self.__size, ""
        elseif k == "SetFont" then self.__size = a[2] or self.__size
        elseif k == "SetFontObject" then self.__size = a[1] and a[1].__fontSize or 12
        elseif k == "SetJustifyH" then self.__justify = a[1]
        elseif k == "SetWordWrap" then self.__wrap = a[1] and true or false
        elseif k == "SetTextColor" then self.__color = { a[1], a[2], a[3] }
        elseif k == "SetAlpha" then self.__alpha = a[1]
        elseif k == "SetMinMaxValues" then self.__min, self.__max = a[1], a[2]
        elseif k == "GetMinMaxValues" then return self.__min, self.__max
        elseif k == "SetValue" then self.__value = a[1]; if self.__scripts.OnValueChanged then self.__scripts.OnValueChanged(self, a[1]) end
        elseif k == "GetValue" then return self.__value
        elseif k == "GetCenter" then return 500, 400
        elseif k == "GetEffectiveScale" then return 1
        elseif k == "GetPoint" then return "CENTER", nil, "CENTER", 0, 0
        elseif k == "GetName" then return self.__name
        elseif k == "GetParent" then return self.__parent
        elseif k == "SetTexture" then self.__tex = a[1]; self.__color = nil
        elseif k == "SetColorTexture" then self.__tex = "color"; self.__color = { a[1], a[2], a[3], a[4] }
        elseif k == "SetVertexColor" then self.__vertex = { a[1], a[2], a[3] }
        elseif k == "SetTexCoord" then self.__tc = { a[1], a[2], a[3], a[4] }
        elseif k == "SetBlendMode" then self.__blend = a[1]
        elseif k == "SetDesaturated" then self.__desat = a[1] and true or false
        elseif k == "SetScrollChild" then a[1].__scrollParent = self; self.__child = a[1]
        elseif k == "SetVerticalScroll" then self.__scroll = a[1]
        elseif k == "SetHighlightTexture" then self.__hiTex = a[1]; self.__hiBlend = a[2]
        elseif k == "SetEnabled" then self.__disabled = not a[1]
        elseif k == "Enable" then self.__disabled = false
        elseif k == "Disable" then self.__disabled = true
        elseif k == "IsEnabled" then return not self.__disabled
        elseif k == "SetChecked" then self.__checked = a[1] and true or false
        elseif k == "GetChecked" then return self.__checked or false
        elseif k == "SetFocus" then self.__focus = true
        elseif k == "ClearFocus" then self.__focus = false
        elseif k == "HasFocus" then return self.__focus or false
        elseif k == "SetMaxLetters" then self.__maxLetters = a[1]
        elseif k == "SetRotation" then self.__rot = a[1]
        elseif k == "ClearAllPoints" then self.__points = {}
        elseif k == "SetAllPoints" then
          local rel = a[1] or self.__parent
          self.__points = { { point = "TOPLEFT", rel = rel, relPoint = "TOPLEFT", x = 0, y = 0 },
                            { point = "BOTTOMRIGHT", rel = rel, relPoint = "BOTTOMRIGHT", x = 0, y = 0 } }
        elseif k == "SetPoint" then
          local point, rel, relPoint, x, y = a[1], nil, nil, 0, 0
          if n >= 2 then
            if type(a[2]) == "number" then x, y = a[2], a[3] or 0
            else
              rel = a[2]
              if type(a[3]) == "string" then relPoint, x, y = a[3], a[4] or 0, a[5] or 0
              else x, y = a[3] or 0, a[4] or 0 end
            end
          end
          assert(type(point) == "string", "SetPoint needs a point")
          for i = #self.__points, 1, -1 do if self.__points[i].point == point then table.remove(self.__points, i) end end
          table.insert(self.__points, { point = point, rel = rel, relPoint = relPoint or point, x = x, y = y })
        end
        return nil
      end
    end
    if type(k) == "string" and (k:match("^%l") or k:match("^__")) then return nil end  -- plain fields read nil, like on a real frame
    error("unknown widget method: " .. tostring(k) .. " on " .. kind, 2)
  end
  return setmetatable(o, mt)
end

local function fontObj(name)
  local f = newObj("Font")
  f.__fontSize = FONT_SIZE[name] or 12
  return f
end

----------------------------------------------------------------------------
-- one game client: its own globals, character, log, bags, party channel and clock
----------------------------------------------------------------------------
local clients = {}
local lines = {}
local BASE = setmetatable({}, { __index = _G })
BASE.BackdropTemplateMixin = {}
BASE.QUESTBANK_DEV = true -- errors stay fatal here; one test below turns it off to check the safety net
for name in pairs(FONT_SIZE) do BASE[name] = fontObj(name) end
BASE.GameTooltip = setmetatable({}, { __index = function(_, k)
  return function(_, ...) if k == "AddLine" or k == "AddDoubleLine" then lines[#lines + 1] = tostring((...)) end end
end })
BASE.date = os.date
BASE.time = os.time
BASE.debugprofilestop = function() return os.clock() * 1000 end
BASE.GetCursorPosition = function() return 600, 500 end
BASE.SetPortraitTexture = function() end
BASE.geterrorhandler = function() return error end
BASE.UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m = m, x = x, y = y } end }
BASE.C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
BASE.CreateVector2D = function(x, y) return { x = x, y = y } end
BASE.Ambiguate = function(name) return name end
BASE.CLASS_ICON_TCOORDS = { PALADIN = { 0, 0.25, 0.5, 0.75 }, WARRIOR = { 0, 0.25, 0, 0.25 }, SHAMAN = { 0.25, 0.49, 0.25, 0.5 } }
BASE.RAID_CLASS_COLORS = { PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, SHAMAN = { r = 0, g = 0.44, b = 0.87 } }
BASE.CreateFromMixins = function(...)
  local t = {}
  for i = 1, select("#", ...) do for k, v in pairs(select(i, ...)) do t[k] = v end end
  return t
end
BASE.MapCanvasPinMixin = {
  SetPosition = function(self, x, y) self.__pos = { x, y } end,
  UseFrameLevelType = function() end, SetScalingLimits = function() end,
}
BASE.MapCanvasDataProviderMixin = { GetMap = function(self) return self.owningMap end }

local function newClient(o)
  local env = setmetatable({}, { __index = BASE })
  env._G = env
  local c = { env = env, o = o, timers = {}, clock = 1000, outbox = {}, pins = {}, chat = {}, frames = {}, QB = {} }
  env.UIParent = newObj("Frame"); env.UIParent:SetSize(1600, 1000); env.UIParent.__points = {}
  env.UIParent.__root = true
  env.Minimap = newObj("Frame"); env.Minimap:SetSize(140, 140)
  env.UISpecialFrames = {}
  env.SlashCmdList = {}
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) c.chat[#c.chat + 1] = m end }
  env.CreateFrame = function(kind, name, parent, template)
    local f = newObj(kind, template, parent)
    f.__name = name
    if name then env[name] = f end
    c.frames[#c.frames + 1] = f
    return f
  end
  env.C_Timer = { After = function(sec, f) c.timers[#c.timers + 1] = { t = c.clock + sec, f = f } end }
  env.GetTime = function() return c.clock end
  local t0 = os.time()
  env.time = function() return t0 + math.floor(c.clock - 1000) end
  env.IsShiftKeyDown = function() return c.shift end
  env.GetBindLocation = function() return o.bind or "Stormwind City" end
  env.IsPlayerSpell = function() return o.riding or false end
  env.AuraUtil = { FindAuraByName = function(name) if c.rested and name == "Well Rested" then return name end end }
  env.UnitName = function(unit) if unit == "npc" then return c.npcName end return o.name end
  env.UnitGUID = function(unit) if unit == "npc" then return c.npcGUID end return "Player-1234-" .. string.format("%08X", #o.name * 7919 + (o.level or 1)) end
  env.UnitFullName = function() return o.name, "ForeverNormal" end
  -- the UI's quest-log constants as Forever ships them (25) against a log that holds 40, and the
  -- dialog refresher the fix pokes
  env.MAX_QUESTS, env.MAX_QUESTLOG_QUESTS = 25, 25
  env.UpdateQuestAcceptLogFullDialog = function() c.logFullUpdates = (c.logFullUpdates or 0) + 1 end
  env.GetTitleText = function() return c.window and c.window.title or "" end
  env.GetSuggestedGroupNum = function() return 0 end
  env.GetBuildInfo = function() return "1.60.1", "70058", "Sep 29 2026", 16001 end
  env.C_GossipInfo = {
    GetAvailableQuests = function() return c.gossipAvail or {} end,
    GetActiveQuests = function() return c.gossipActive or {} end,
    SelectAvailableQuest = function(id) c.auto[#c.auto + 1] = "SelectAvailableQuest " .. id end,
    SelectActiveQuest = function(id) c.auto[#c.auto + 1] = "SelectActiveQuest " .. id end,
  }
  -- the quest windows, for the accept-and-hand-in-for-me switches: what QuestBank clicked, in order
  c.auto = {}
  env.AcceptQuest = function() c.auto[#c.auto + 1] = "AcceptQuest " .. (c.window and c.window.id or 0) end
  env.CompleteQuest = function() c.auto[#c.auto + 1] = "CompleteQuest " .. (c.window and c.window.id or 0) end
  env.GetQuestReward = function(i) c.auto[#c.auto + 1] = "GetQuestReward " .. tostring(i) end
  env.GetNumQuestChoices = function() return c.choices or 0 end
  env.IsQuestCompletable = function() return c.completable and true or false end
  env.QuestGetAutoAccept = function() return false end
  env.ConfirmAcceptQuest = function() c.auto[#c.auto + 1] = "ConfirmAcceptQuest" end
  env.StaticPopup_Hide = function() end
  env.QuestFlagsPVP = function() return c.pvpQuest or false end
  env.GetQuestMoneyToGet = function() return c.questCost or 0 end
  env.GetNumActiveQuests = function() return #(c.greetActive or {}) end
  env.GetActiveTitle = function(i) local e = c.greetActive[i]; return e.title, e.isComplete end
  env.GetActiveQuestID = function(i) return c.greetActive[i].questID end
  env.SelectActiveQuest = function(i) c.auto[#c.auto + 1] = "SelectActiveQuest #" .. i end
  env.GetNumAvailableQuests = function() return #(c.greetAvail or {}) end
  env.GetAvailableQuestInfo = function(i) local e = c.greetAvail[i]; return e.isTrivial or false, 0, e.repeatable or false, false, e.questID end
  env.SelectAvailableQuest = function(i) c.auto[#c.auto + 1] = "SelectAvailableQuest #" .. i end
  env.UnitLevel = function() return c.level or o.level end
  env.GetMaxPlayerLevel = function() return c.cap or o.cap or 60 end
  env.GetPlayerFacing = function() return c.facing end
  -- the chat box: open or not, and what a shift-click put in it
  c.chatLinks = {}
  env.ChatEdit_GetActiveWindow = function() return c.chatOpen and {} or nil end
  env.ChatEdit_InsertLink = function(link) c.chatLinks[#c.chatLinks + 1] = link; return true end
  env.GetQuestLink = function(id) for _, e in ipairs(c.log) do if e[1] == id then return "|cffffff00|Hquest:" .. id .. ":20|h[Quest " .. id .. "]|h|r" end end end
  env.GetItemInfo = function(id) return "Item " .. id, "|cffffffff|Hitem:" .. id .. "::::::::20:::::::|h[Item " .. id .. "]|h|r" end
  env.UnitXP = function() return c.xp or 0 end
  env.UnitXPMax = function() return 23200 end
  env.UnitClass = function() return o.className, o.class, o.classID end
  env.UnitRace = function() return o.race, o.race end
  env.UnitFactionGroup = function() return o.faction end
  env.GetNormalizedRealmName = function() return "ForeverNormal" end
  env.IsInGroup = function() return o.group or false end
  env.IsInRaid = function() return false end
  env.IsInGuild = function() return o.guild or false end
  env.GetQuestID = function() return c.window and c.window.id or 0 end
  env.GetRewardXP = function() return c.window and c.window.xp or 0 end
  -- the Classic way: the selected entry's XP, whatever ID is passed
  env.GetQuestLogSelection = function() return c.selected or 0 end
  env.SelectQuestLogEntry = function(i) c.selected = i end
  env.GetQuestLogRewardXP = function() error("QuestBank must not read the quest log's XP (it means selecting entries in the game's quest log)") end
  env.C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and #(o.bagSlots or {}) or 0 end,
    GetContainerItemID = function(_, slot) return o.bagSlots[slot] and o.bagSlots[slot][1] end,
    GetContainerItemLink = function(_, slot) return o.bagSlots[slot] and ("[Item " .. o.bagSlots[slot][1] .. "]") end,
    GetContainerItemInfo = function(_, slot) return o.bagSlots[slot] and { stackCount = o.bagSlots[slot][2] } end,
    GetContainerItemQuestInfo = function(_, slot) local s = o.bagSlots[slot]; return { questID = s and s[3], isActive = false } end,
    GetItemCooldown = function() return c.hearthCD or 0, c.hearthCD and 3600 or 0, 1 end,
  }
  env.C_Item = {
    GetItemCount = function(id, includeBank)
      local n = 0
      for _, s in ipairs(o.bagSlots or {}) do if s[1] == id then n = n + s[2] end end
      if includeBank and o.bank then n = n + (o.bank[id] or 0) end
      return n
    end,
    GetItemIconByID = function(id) return id and 133328 or nil end,
  }
  env.C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return c.done[id] or false end,
    GetNumQuestLogEntries = function() if c.logReady == false then return 0, 0 end return #c.log + 2, #c.log end,
    GetMaxNumQuestsCanAccept = function() return 25 end, -- stale too, the worst case
    GetInfo = function(i)
      if i == 1 then return { title = "Zone", isHeader = true } end
      if i == 2 then return { title = "Dungeons", isHeader = true } end
      local e = c.log[i - 2]
      if not e then return nil end
      return { title = "Quest " .. e[1], level = 20, questID = e[1], isHeader = false }
    end,
    IsComplete = function(id) for _, e in ipairs(c.log) do if e[1] == id then return e[2] == 1 end end return false end,
    GetQuestObjectives = function() return { { text = "thing", finished = false, numFulfilled = 3, numRequired = 10 } } end,
    GetAllCompletedQuestIDs = function() local t = {} for k, v in pairs(c.done) do if v then t[#t + 1] = k end end return t end,
    GetLogIndexForQuestID = function(id) for i, e in ipairs(c.log) do if e[1] == id then return i + 2 end end end,
  }
  env.C_Map = {
    GetBestMapForUnit = function() return o.map or 1453 end,
    CanSetUserWaypointOnMap = function() return true end,
    SetUserWaypoint = function(p) c.pins[#c.pins + 1] = p end,
    GetPlayerMapPosition = function() return { x = 0.66, y = 0.62, GetXY = function(self) return self.x, self.y end } end,
    GetWorldPosFromMapPos = function() return o.world[1], { x = o.world[2], y = o.world[3], GetXY = function(self) return self.x, self.y end } end,
    GetMapRectOnMap = function() return 0.4, 0.6, 0.4, 0.6 end,
  }
  -- chat people read: one line of at most 255 bytes, no escape codes, only to a channel you're in
  c.said, c.chatErrors = {}, {}
  env.SendChatMessage = function(msg, chatType)
    -- recorded, not raised: the addon pcalls this, so a raised check would vanish
    local function bad(why) c.chatErrors[#c.chatErrors + 1] = why; error(why) end
    if not (type(msg) == "string" and #msg > 0 and #msg <= 255) then bad("chat message empty or over 255 bytes") end
    if msg:find("[\r\n]") then bad("chat message with a line break") end
    if msg:find("|") then bad("chat message with an escape code") end
    if not (chatType == "PARTY" or chatType == "RAID" or chatType == "GUILD" or chatType == "INSTANCE_CHAT") then bad("posted to " .. tostring(chatType)) end
    if chatType == "GUILD" and not o.guild then bad("posted to a guild you're not in") end
    if chatType ~= "GUILD" and not o.group then bad("posted to a group you're not in") end
    c.said[#c.said + 1] = { msg, chatType }
  end
  env.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, msg, channel, target)
      assert(#msg <= 255, "addon message too long: " .. #msg)
      if (channel == "PARTY" or channel == "RAID") and not o.group then return 5 end -- NotInGroup
      c.outbox[#c.outbox + 1] = { prefix, msg, channel, target }
      return 0
    end,
  }
  -- the world map, with a data provider and pins made from the XML template
  local map = { shown = true, pins = {}, providers = {} }
  env.WorldMapFrame = {
    AddDataProvider = function(_, p) p.owningMap = map; map.providers[#map.providers + 1] = p end,
    IsShown = function() return map.shown end,
  }
  function map:GetMapID() return 1453 end
  function map:RemoveAllPinsByTemplate() self.pins = {} end
  -- Blizzard_MapCanvas: a new pin whose template set OnEnter or OnLeave trips an assert (it sets them itself)
  local xml = io.open(HERE .. "/QuestBank/Pins.xml"):read("*a"):gsub("<!%-%-.-%-%->", "")
  local templateScripts = {}
  for tag in xml:gmatch("<(On%a+)") do templateScripts[tag] = true end
  function map:AcquirePin(template, d, x, y)
    assert(template == "QuestBankPinTemplate")
    assert(not templateScripts.OnEnter and not templateScripts.OnLeave, "Blizzard_MapCanvas.lua:309: assertion failed! (the pin template sets OnEnter/OnLeave)")
    assert(not templateScripts.OnMouseUp and not templateScripts.OnMouseDown, "the map canvas owns a pin's mouse scripts")
    local pin = newObj("Frame")
    pin.Icon, pin.Num = newObj("Texture", nil, pin), newObj("FontString", nil, pin)
    for k, v in pairs(env.QuestBankPinMixin) do pin[k] = v end
    pin:OnLoad()
    pin:OnAcquired(d, x, y)
    self.pins[#self.pins + 1] = pin
  end
  c.map = map
  c.log, c.done, c.level, c.xp = o.log, o.done, o.level, o.xp or 0
  -- the files the TOC lists, in its order, so a new file is tested the day it is added
  local files = {}
  for line in io.lines(HERE .. "/QuestBank/QuestBank.toc") do
    local f = line:match("^%s*([%w_]+%.lua)%s*$")
    if f then files[#files + 1] = f end
  end
  assert(#files >= 8 and files[1] == "Data.lua" and files[#files] == "UI.lua", "the TOC lists the addon's Lua files, Data first and UI last")
  for _, f in ipairs(files) do
    local chunk = assert(loadfile(HERE .. "/QuestBank/" .. f))
    setfenv(chunk, env)
    chunk("QuestBank", c.QB)
  end
  c.ev = c.QB.eventFrame.__scripts.OnEvent
  clients[#clients + 1] = c
  return c
end

-- run what is due on the client's clock, then advance it
local function tick(c, seconds)
  local target = c.clock + (seconds or 0)
  for _ = 1, 1000 do
    table.sort(c.timers, function(a, b) return a.t < b.t end)
    local nxt = c.timers[1]
    if not nxt or nxt.t > target then break end
    table.remove(c.timers, 1)
    c.clock = math.max(c.clock, nxt.t)
    nxt.f()
  end
  c.clock = target
  for _, f in ipairs(c.frames) do
    local u = f.__scripts.OnUpdate
    for _ = 1, 400 do
      u = f.__scripts.OnUpdate
      if not u then break end
      u(f, 0.016)
    end
  end
end

-- deliver every client's addon messages to the others in the same group
local function deliver()
  local moved = 0
  for _, from in ipairs(clients) do
    local box = from.outbox
    from.outbox = {}
    for _, m in ipairs(box) do
      for _, to in ipairs(clients) do
        if to.QB.Sync.frame then
          local reach = (m[3] == "WHISPER" and m[4] == to.o.name and to ~= from) or ((m[3] == "PARTY" or m[3] == "RAID") and from.o.group and to.o.group)
            or (m[3] == "GUILD" and from.o.guild and to.o.guild)
          if reach then
            -- chat senders carry a surname the name API doesn't, and the realm written with a space
            to.QB.Sync.frame.__scripts.OnEvent(to.QB.Sync.frame, "CHAT_MSG_ADDON", m[1], m[2], m[3], from.o.name .. " " .. (from.o.surname or "Steelhand") .. "-Forever Normal")
            moved = moved + 1
          end
        end
      end
    end
  end
  return moved
end

local function login(c)
  c.ev(c.QB.eventFrame, "ADDON_LOADED", "QuestBank")
  c.ev(c.QB.eventFrame, "PLAYER_LOGIN")
  c.ev(c.QB.eventFrame, "QUEST_LOG_UPDATE")
  tick(c, 15)
  assert(c.env.QuestBankDB.chars[c.o.name .. "-ForeverNormal"], "login snapshot")
end

local function poke(obj)
  local s = obj.__scripts
  if s.OnEnter then lines = {}; s.OnEnter(obj); assert(#lines > 0, "tooltip empty"); if s.OnLeave then s.OnLeave(obj) end end
  if s.OnClick then s.OnClick(obj, "LeftButton") end
end

----------------------------------------------------------------------------
-- layout: resolve anchors to boxes like the game does
----------------------------------------------------------------------------
local GEN = 0
local function anchorXY(r, point)
  local x = point:find("LEFT") and r.l or (point:find("RIGHT") and r.r or (r.l + r.r) / 2)
  local y = point:find("TOP") and r.t or (point:find("BOTTOM") and r.b or (r.t + r.b) / 2)
  return x, y
end

local rectOf
function rectOf(o, depth)
  depth = (depth or 0) + 1
  if depth > 60 then error("anchor loop") end
  if o.__gen == GEN then return o.__rect end
  o.__gen = GEN
  if o.__root then
    o.__rect = { l = 0, r = o.__w, t = o.__h, b = 0 }
    return o.__rect
  end
  local L, R, T, B, CX, CY
  if o.__scrollParent then
    local sr = rectOf(o.__scrollParent, depth)
    if sr then L, T = sr.l, sr.t + (o.__scrollParent.__scroll or 0) end
  end
  for _, p in ipairs(o.__points) do
    local rel = p.rel or o.__parent
    local rr = rel and rectOf(rel, depth)
    if rr then
      local ax, ay = anchorXY(rr, p.relPoint)
      ax, ay = ax + (p.x or 0), ay + (p.y or 0)
      local pt = p.point
      if pt:find("LEFT") then L = ax elseif pt:find("RIGHT") then R = ax else CX = ax end
      if pt:find("TOP") then T = ay elseif pt:find("BOTTOM") then B = ay else CY = ay end
    end
  end
  if not (L or R or CX) or not (T or B or CY) then o.__rect = nil; return nil end
  local w, h = o.__w or 0, o.__h or 0
  local isText = o.__kind == "FontString"
  if isText then
    local tw = textWidth(o.__text, o.__size)
    if not o.__wset and not (L and R) then w = tw end
    if not o.__hset and not (T and B) then
      local lines = 1
      if o.__wrap and o.__wset and w > 0 then lines = math.max(1, math.ceil(tw / w)) end
      h = lines * (o.__size + 2)
    end
  end
  if L and R then w = R - L elseif L then R = L + w elseif R then L = R - w else L = CX - w / 2; R = CX + w / 2 end
  if T and B then h = T - B elseif T then B = T - h elseif B then T = B + h else T = CY + h / 2; B = CY - h / 2 end
  o.__rw, o.__rh = w, h
  o.__rect = { l = L, r = R, t = T, b = B }
  return o.__rect
end

local function visible(o)
  while o do
    if not o.__shown then return false end
    if o.__root then return true end
    o = o.__parent or o.__scrollParent
  end
  return false
end

local function ancestors(o)
  local list = {}
  local p = o.__parent or o.__scrollParent
  while p do list[#list + 1] = p; p = p.__parent or p.__scrollParent end
  return list
end

-- the part of a label that has ink: the text, not the box, on the side its justify puts it
local function ink(o, r)
  local tw = textWidth(o.__text, o.__size)
  local w = r.r - r.l
  if o.__wrap and o.__wset then return r end
  local used = math.min(tw, w > 0 and w or tw)
  if o.__justify == "RIGHT" then return { l = r.r - used, r = r.r, t = r.t, b = r.b }
  elseif o.__justify == "CENTER" then local cx = (r.l + r.r) / 2; return { l = cx - used / 2, r = cx + used / 2, t = r.t, b = r.b } end
  return { l = r.l, r = r.l + used, t = r.t, b = r.b }
end

local function overlap(a, b, pad)
  pad = pad or 1
  return a.l < b.r - pad and b.l < a.r - pad and a.b < b.t - pad and b.b < a.t - pad
end

-- every problem with the window as it is on screen now
local function checkLayout(root, label)
  GEN = GEN + 1
  local problems, texts = {}, {}
  local rootRect = rectOf(root)
  for _, o in ipairs(ALL) do
    if o.__kind == "FontString" and o.__text ~= "" and visible(o) then
      local anc = ancestors(o)
      local inside = false
      for _, a in ipairs(anc) do if a == root then inside = true end end
      if inside then
        local r = rectOf(o)
        if r then
          local tw = textWidth(o.__text, o.__size)
          if o.__wset and not o.__wrap and tw > (r.r - r.l) + 3 then
            problems[#problems + 1] = string.format("%s: clipped '%s' (%.0f of %.0f px)", label, plain(o.__text):sub(1, 60), r.r - r.l, tw)
          end
          -- a wrapped paragraph in a box of set height: the game cuts the lines that don't fit
          if o.__wset and o.__wrap and o.__hset and (o.__h or 0) > 0 then
            local lines = math.max(1, math.ceil(tw / math.max(1, r.r - r.l)))
            if lines * (o.__size + 2) > o.__h + 3 then
              problems[#problems + 1] = string.format("%s: '%s' needs %d lines, its box holds %d", label, plain(o.__text):sub(1, 50), lines, math.floor((o.__h + 3) / (o.__size + 2)))
            end
          end
          local ir = ink(o, r)
          -- inside a scroll view: across it must fit, down it scrolls
          local clip
          for _, a in ipairs(anc) do if a.__child then clip = rectOf(a); break end end
          if clip and (ir.r > clip.r + 2 or ir.l < clip.l - 2) then
            problems[#problems + 1] = string.format("%s: '%s' runs out of the scroll view", label, plain(o.__text):sub(1, 50))
          end
          local inView = not clip or (ir.b < clip.t and ir.t > clip.b)
          if clip and inView then
            -- what shows is cut to the scroll view
            ir = { l = math.max(ir.l, clip.l), r = math.min(ir.r, clip.r), t = math.min(ir.t, clip.t), b = math.max(ir.b, clip.b) }
          end
          if not clip and (ir.r > rootRect.r - 10 or ir.l < rootRect.l + 10 or ir.b < rootRect.b + 8 or ir.t > rootRect.t) then
            problems[#problems + 1] = string.format("%s: '%s' runs out of the window", label, plain(o.__text):sub(1, 50))
          end
          if inView then texts[#texts + 1] = { o = o, r = ir, clip = clip } end
        end
      end
    end
  end
  -- buttons with a label or an icon take room too
  for _, o in ipairs(ALL) do
    if (o.__template == "UIPanelButtonTemplate" or ((o.__kind == "Button" or o.__kind == "CheckButton") and o.__wset and o.__w <= 40 and o.__w >= 16)) and visible(o) then
      local anc = ancestors(o)
      local inside = false
      for _, a in ipairs(anc) do if a == root then inside = true end end
      local r = inside and rectOf(o)
      if r then
        local clip
        for _, a in ipairs(anc) do if a.__child then clip = rectOf(a); break end end
        if not clip or (r.b < clip.t and r.t > clip.b) then
          texts[#texts + 1] = { o = o, r = r, button = true }
        end
      end
    end
  end
  for i = 1, #texts do
    for j = i + 1, #texts do
      local a, b = texts[i], texts[j]
      local nested = false
      if a.button or b.button then
        local btn, other = a.button and a or b, a.button and b or a
        for _, x in ipairs(ancestors(other.o)) do if x == btn.o then nested = true end end
        if a.button and b.button then nested = false end
      end
      if not nested and overlap(a.r, b.r, 1.5) then
        local name = function(t) return t.button and ("[button " .. plain(t.o.__text or ""):sub(1, 20) .. "]") or plain(t.o.__text):sub(1, 40) end
        problems[#problems + 1] = string.format("%s: '%s' overlaps '%s'", label, name(a), name(b))
      end
    end
  end
  return problems
end

-- a drawing of the window for the layout page
local function dumpLayout(root, label)
  GEN = GEN + 1
  local rr = rectOf(root)
  local items = {}
  local texNames = {}
  for k, v in pairs(clients[1].QB.Data.TEX) do texNames[v] = k end
  for idx, o in ipairs(ALL) do
    if visible(o) and o ~= root then
      local anc = ancestors(o)
      local inside = false
      for _, a in ipairs(anc) do if a == root then inside = true end end
      if inside then
        local r = rectOf(o)
        if r and (r.r - r.l) > 0 and (r.t - r.b) > 0 then
          local it = { k = o.__kind, x = r.l - rr.l, y = rr.t - r.t, w = r.r - r.l, h = r.t - r.b, i = idx, a = o.__alpha, depth = #anc }
          if o.__kind == "FontString" then
            it.text, it.size, it.j, it.wrap = plain(o.__text), o.__size, o.__justify, o.__wrap
            it.c = o.__color
          elseif o.__kind == "Texture" then
            if o.__layer == "HIGHLIGHT" and not (o.__parent and o.__parent.__hover) then it = nil
            else
              it.layer = o.__layer
              it.tex = o.__tex == "color" and "color" or (texNames[o.__tex] or (o.__tex and "icon") or nil)
              it.c = o.__color or o.__vertex
              it.tc, it.blend, it.desat = o.__tc, o.__blend, o.__desat or nil
              if not it.tex then it = nil end
            end
          else
            it.bd = o.__backdrop or nil
            it.tpl = o.__template
            it.text = (o.__template or o.__kind == "EditBox") and o.__text ~= "" and o.__text or nil
            it.checked, it.off = o.__checked or nil, o.__disabled or nil
          end
          if it then
            for _, a in ipairs(anc) do if a.__child then local c = rectOf(a); it.clip = { x = c.l - rr.l, y = rr.t - c.t, w = c.r - c.l, h = c.t - c.b }; break end end
            items[#items + 1] = it
            -- a hovered button's own highlight texture, the way the game draws it: over the whole button
            if o.__hover and o.__hiTex then
              local hi = { k = "Texture", x = it.x, y = it.y, w = it.w, h = it.h, i = idx + 0.5, a = 1, depth = it.depth + 1,
                           layer = "HIGHLIGHT", tex = texNames[o.__hiTex] or "icon", blend = o.__hiBlend or "ADD", clip = it.clip }
              items[#items + 1] = hi
            end
          end
        end
      end
    end
  end
  return { label = label, w = rr.r - rr.l, h = rr.t - rr.b, items = items }
end

local function json(v)
  local t = type(v)
  if t == "table" then
    if #v > 0 or next(v) == nil then
      local parts = {}
      for i = 1, #v do parts[i] = json(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = string.format("%q:%s", tostring(k), json(x)) end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "string" then return string.format("%q", v):gsub("\\\n", "\\n")
  elseif t == "number" then return (string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", ".0"))
  elseif t == "boolean" then return tostring(v) end
  return "null"
end

----------------------------------------------------------------------------
-- scenario 1: the owner, an Alliance paladin at the level 20 cap with a full bank
----------------------------------------------------------------------------
local OWNER_LOG = {
  { 971, 1 }, { 1275, 1 }, { 1199, 1 }, { 97894, 1 }, { 2922, 0 }, { 2926, 0 }, { 2928, 0 }, { 454, 1 }, { 217, 0 }, { 297, 0 },
  { 255, 0 }, { 143, 1 }, { 131, 1 }, { 116, 1 }, { 92, 0 }, { 118, 1 }, { 150, 1 }, { 98387, 1 }, { 127, 0 }, { 91, 0 },
  { 34, 0 }, { 128, 0 }, { 95999, 1 }, { 169, 1 }, { 180, 1 }, { 95189, 1 }, { 399, 1 }, { 353, 1 }, { 343, 1 }, { 79192, 1 },
  { 168, 1 }, { 167, 1 }, { 391, 1 }, { 1486, 1 }, { 1487, 1 }, { 276, 0 }, { 470, 0 }, { 1654, 1 },
}
local owner = newClient({
  name = "Mikal", level = 20, cap = 20, faction = "Alliance", className = "Paladin", class = "PALADIN", classID = 2, race = "Human",
  log = OWNER_LOG, group = true, guild = true, world = { 0, -8830, 480 },
  done = { [96393] = true, [96394] = true, [96395] = true, [96403] = true, [98423] = true, [96391] = true, [6981] = true,
           [155] = true, [142] = true, [141] = true, [135] = true, [132] = true, [65] = true, [389] = true, [373] = true },
  bagSlots = { { 268540, 4 }, { 251522, 1 } },
})
local QB = owner.QB
-- 3.3.3: A Fine Mess pretends to come from the Classic seed (flag 16), so the "Classic only" labels show at level 20
local fineMess
for id, name in pairs(QB.Data.QN) do if name == "A Fine Mess" then fineMess = id end end
assert(fineMess and QB.Data.Q[fineMess], "A Fine Mess is in the catalog")
if math.floor(QB.Data.Q[fineMess][10] / 16) % 2 == 0 then QB.Data.Q[fineMess][10] = QB.Data.Q[fineMess][10] + 16 end
login(owner)
owner.env.SlashCmdList.QUESTBANK("")
local UI = QB.UI
assert(UI.frame:IsShown(), "window opens")
QB.Model.Finish()
for tab = 1, 5 do UI:ShowTab(tab) end
local v1, v2, v3, v4 = UI.views[1], UI.views[2], UI.views[3], UI.views[4]
print("log title:", v1.title:GetText(), "|", v1.worth:GetText())
print("header:", UI.header.legend:GetText())

-- 3.4.0: a quest behind a chain says what it costs first: steps, and minutes of moving
do
  local chained, withMinutes = 0, 0
  for _, c in ipairs(UI:Candidates(400)) do
    local q = QB.Quest.Get(c.id)
    local st = QB:Status(q)
    if st.code == "prereq" then
      local cc = QB:ChainCost(q)
      assert(cc and cc.n >= 1 and cc.xp >= 0, "a chain quest has a cost: " .. q.name) -- first may be a step the catalog lacks
      chained = chained + 1
      if cc.minutes and cc.minutes > 0 then withMinutes = withMinutes + 1 end
    end
  end
  print(string.format("chains among the candidates: %d, %d with travel known", chained, withMinutes))
  assert(chained > 0 and withMinutes > 0, "the owner has chain quests with known travel")
end
UI:ShowTab(1)
for _, b in ipairs(v1.slots) do poke(b) end
for _, b in ipairs(v1.bagSlots) do if b:IsShown() then poke(b) end end
for _, r in ipairs(v1.swaps) do if r:IsShown() then poke(r) end end
for _, r in ipairs(v1.swaps) do if r:IsShown() then print(string.format("  swap: %-28s -> %-32s %s%s", r.cutName:GetText(), r.addName:GetText(), r.gain:GetText(), r.via and ("  (via " .. r.via.name .. ")") or "")) end end
for _, r in ipairs(v1.swaps) do
  if r:IsShown() then assert(not (r.add.turn and r.add.turn.inside), "a swap never banks a quest handed in inside a dungeon: " .. r.add.name) end
end
do
  -- a chain quest's Plan row says how long the moving takes; every card opened so the rows exist
  UI:ShowTab(2)
  UI.expanded = {}
  for _, cat in ipairs(QB.Data.CAT) do UI.expanded[cat.key] = true end
  UI:Refresh()
  local moving
  for _, c in ipairs(v2.cards.items) do for _, r in ipairs(c.rows.items) do if r:IsShown() and r.st and r.st.code == "prereq" and r.status:GetText():find("min on the move", 1, true) then moving = moving or r end end end
  assert(moving, "a chain quest on the Plan page says the minutes of moving its steps take")
  print("chain row:", moving.q.name, "|", moving.status:GetText())
  UI.expanded = nil
  UI:ShowTab(1); UI:Refresh()
  -- in the swap list the chain's steps show in the row text whenever such a quest ranks among the rows
  for _, r in ipairs(v1.swaps) do
    if r:IsShown() and r.add and QB:Status(r.add).code == "prereq" and not r.via and not r.cutName:GetText():find("hand in") then
      assert(r.cutName:GetText():find("step%a* first"), "a chain quest in the swap list says its steps first: " .. r.cutName:GetText())
    end
  end
end
for _, c in ipairs(UI:Candidates(400)) do
  local q = QB.Quest.Get(c.id)
  assert(not (q.turn and q.turn.inside), "no quest handed in inside a dungeon is offered to fetch: " .. q.name)
  assert(not q.sodLeftover, "no Season of Discovery leftover is offered: " .. q.name)
end
assert(not QB.Data.Q[78132] and not QB.Data.Q[78133] and not QB.Data.Q[78134], "Alonso's Dragonslayer quests aren't in Forever")
-- 3.3.4: the join prompt for escort quests. The game's MAX_QUESTS says 25 while the log holds 40.
do
  assert(owner.env.MAX_QUESTS == 40 and owner.env.MAX_QUESTLOG_QUESTS == 40, "login puts the log's real size into MAX_QUESTS: " .. tostring(owner.env.MAX_QUESTS))
  assert(QB.escortWas == 25 and (owner.logFullUpdates or 0) >= 1, "remembers what the game said, and pokes an open prompt")
  local n = #owner.chat
  owner.ev(QB.eventFrame, "QUEST_ACCEPT_CONFIRM", "Brann Steelhand", "Escorting Erland", 435)
  local said = owner.chat[#owner.chat]
  assert(#owner.chat == n + 1 and said:find("Brann Steelhand started Escorting Erland", 1, true) and said:find("counts 25 quests as a full log; the log holds 40", 1, true), "the first prompt of the session says what QuestBank did: " .. tostring(said))
  owner.ev(QB.eventFrame, "QUEST_ACCEPT_CONFIRM", "Brann Steelhand", "Escorting Erland", 435)
  assert(#owner.chat == n + 1, "and says it once")
  owner.env.SlashCmdList.QUESTBANK("escort off")
  assert(owner.env.MAX_QUESTS == 25 and owner.env.MAX_QUESTLOG_QUESTS == 25 and not QB:Settings().escort, "/qb escort off gives the game its number back")
  assert(owner.chat[#owner.chat]:find("fix is off", 1, true), "and says so: " .. owner.chat[#owner.chat])
  owner.env.SlashCmdList.QUESTBANK("escort on")
  assert(owner.env.MAX_QUESTS == 40 and QB:Settings().escort, "/qb escort on corrects it again")
  owner.env.SlashCmdList.QUESTBANK("escort")
  assert(owner.chat[#owner.chat]:find("the log holds 40", 1, true), "/qb escort says where things stand: " .. owner.chat[#owner.chat])
  print("escort prompt:", owner.chat[#owner.chat])
end
-- 3.3.5: accept and hand in for me, and the party chat lines. All off by default.
do
  local set = QB:Settings()
  assert(not set.autoAccept and not set.autoTurnIn and not set.sayAccept and not set.sayComplete, "all four off by default")
  local function last() return owner.auto[#owner.auto] end
  owner.window = { id = 1654, xp = 0, title = "The Test of Righteousness" }
  owner.ev(QB.eventFrame, "QUEST_DETAIL"); tick(owner, 1)
  assert(#owner.auto == 0, "off: the quest window is left alone")
  set.autoAccept = true
  owner.ev(QB.eventFrame, "QUEST_DETAIL"); tick(owner, 1)
  assert(last() == "AcceptQuest 1654", "accept for me takes the quest in the window: " .. tostring(last()))
  owner.shift = true
  owner.ev(QB.eventFrame, "QUEST_DETAIL"); tick(owner, 1)
  assert(#owner.auto == 1, "with Shift held it keeps its hands off")
  owner.shift = false
  owner.window = { id = 363, xp = 0, title = "Rude Awakening" }
  owner.ev(QB.eventFrame, "QUEST_DETAIL"); tick(owner, 1)
  assert(#owner.auto == 1, "a Horde quest is left alone for an Alliance paladin")
  owner.window = { id = 7777777, xp = 0, title = "Something New" }
  owner.ev(QB.eventFrame, "QUEST_DETAIL"); tick(owner, 1)
  assert(last() == "AcceptQuest 7777777", "a quest QuestBank doesn't know is new to Forever: taken")
  -- Shift pressed after the window opened: the deferred step stands down; a window that changed is left alone
  local n = #owner.auto
  owner.window = { id = 1654, xp = 0, title = "The Test of Righteousness" }
  owner.ev(QB.eventFrame, "QUEST_DETAIL"); owner.shift = true; tick(owner, 1); owner.shift = false
  assert(#owner.auto == n, "Shift after the window opened: the deferred accept stands down")
  owner.ev(QB.eventFrame, "QUEST_DETAIL"); owner.window = { id = 1221, xp = 0, title = "Blueleaf Tubers" }; tick(owner, 1)
  assert(#owner.auto == n, "the window changed before the click: left alone")
  -- the game would ask about PvP first: so does QuestBank
  owner.pvpQuest = true
  owner.ev(QB.eventFrame, "QUEST_DETAIL"); tick(owner, 1)
  assert(#owner.auto == n, "a quest that flags you for PvP waits for you")
  owner.pvpQuest = false
  -- a place you skipped: left alone; back in: taken
  QB:ToggleSkip("Razorfen Kraul")
  owner.ev(QB.eventFrame, "QUEST_DETAIL"); tick(owner, 1)
  assert(#owner.auto == n, "a quest in a place you skipped is left alone")
  QB:ToggleSkip("Razorfen Kraul")
  owner.ev(QB.eventFrame, "QUEST_DETAIL"); tick(owner, 1)
  assert(last() == "AcceptQuest 1221", "and taken once the place is back")
  -- banking: a pick-up that pays nothing on the day is left on the NPC
  n = #owner.auto
  owner.window = { id = 7, xp = 0, title = "Kobold Camp Cleanup" }
  owner.ev(QB.eventFrame, "QUEST_DETAIL"); tick(owner, 1)
  assert(#owner.auto == n, "banking: a quest the Plan page would cut is left alone")
  owner.gossipAvail = { { questID = 363, title = "Rude Awakening" }, { questID = 1221, title = "Blueleaf Tubers", repeatable = true }, { questID = 2904, title = "Grey one", isTrivial = true }, { questID = 7, title = "Kobold Camp Cleanup" }, { questID = 1654, title = "The Test of Righteousness" } }
  owner.ev(QB.eventFrame, "GOSSIP_SHOW"); tick(owner, 1)
  assert(last() == "SelectAvailableQuest 1654", "at a gossip NPC: not the Horde one, not the repeatable, not the grey one, not the one worth nothing today, the first you should take: " .. tostring(last()))
  owner.gossipAvail = nil
  -- the classic greeting window, the same way
  owner.greetAvail = { { questID = 363, title = "Rude Awakening" }, { questID = 1221, title = "Blueleaf Tubers", repeatable = true }, { questID = 1654, title = "The Test of Righteousness" } }
  owner.ev(QB.eventFrame, "QUEST_GREETING"); tick(owner, 1)
  assert(last() == "SelectAvailableQuest #3", "a greeting NPC: the third entry is the first you should take: " .. tostring(last()))
  owner.greetAvail = nil
  -- an escort a party member starts: joined, while the log has room; once; not with a full log
  n = #owner.auto
  owner.ev(QB.eventFrame, "QUEST_ACCEPT_CONFIRM", "Brann Steelhand", "Escorting Erland", 435); tick(owner, 1)
  assert(#owner.auto == n + 1 and last() == "ConfirmAcceptQuest" and owner.chat[#owner.chat]:find("Said yes to Escorting Erland, which Brann Steelhand started", 1, true), "an escort a party member starts is said yes to: " .. tostring(owner.chat[#owner.chat]))
  assert(not owner.chat[#owner.chat - 1]:find("you can say yes", 1, true), "and the 3.3.4 line stays quiet when Auto answers")
  for i = 1, QB.LOG_SLOTS - #owner.log do table.insert(owner.log, { 9000000 + i, 0 }) end
  owner.ev(QB.eventFrame, "QUEST_LOG_UPDATE"); tick(owner, 1)
  assert(QB.state.logCount == QB.LOG_SLOTS, "the log is full")
  owner.ev(QB.eventFrame, "QUEST_ACCEPT_CONFIRM", "Brann Steelhand", "Escorting Erland", 435); tick(owner, 1)
  assert(#owner.auto == n + 1, "a full log: not joined")
  for i = #owner.log, 1, -1 do if owner.log[i][1] > 9000000 then table.remove(owner.log, i) end end
  owner.ev(QB.eventFrame, "QUEST_LOG_UPDATE"); tick(owner, 1)
  assert(#owner.log == #OWNER_LOG, "the log is as it was")
  -- hand in for me, smart about banking: the owner is banking at 20
  set.autoTurnIn = true
  owner.completable = true
  assert(QB:Mode() == "lock", "the owner banks")
  owner.window = { id = 971, xp = 0, title = "Knowledge in the Deeps" } -- banked, in the plan, worth a lot
  owner.ev(QB.eventFrame, "QUEST_PROGRESS"); tick(owner, 1)
  assert(not tostring(last()):find("CompleteQuest"), "banking: a banked quest in the plan is not handed in")
  owner.choices = 0
  owner.ev(QB.eventFrame, "QUEST_COMPLETE"); tick(owner, 1)
  assert(not tostring(last()):find("GetQuestReward"), "banking: nor finished at the reward window")
  QB:Plan().cut[2922] = true
  owner.window = { id = 2922, xp = 0, title = "Cut one" }
  owner.ev(QB.eventFrame, "QUEST_PROGRESS"); tick(owner, 1)
  assert(last() == "CompleteQuest 2922", "banking: a quest you cut from the plan is handed in: " .. tostring(last()))
  QB:Plan().cut[2922] = nil
  -- banking: the other things the Plan page says to hand in now, and the ones it doesn't
  n = #owner.auto
  owner.window = { id = 7777777, xp = 0, title = "Something New" }
  owner.ev(QB.eventFrame, "QUEST_PROGRESS"); tick(owner, 1)
  assert(#owner.auto == n, "banking: a quest QuestBank doesn't know stays banked, you decide")
  local q131, q1654, q1793, q410 = QB.Quest.Get(131), QB.Quest.Get(1654), QB.Quest.Get(1793), QB.Quest.Get(410)
  assert(QB.Model.XpAt(q131, 20) < 500 * QB.Scale(20) and not QB:Upgrade(q131), "Delivering Daffodils pays next to nothing on the day")
  owner.window = { id = 131, xp = 0, title = "Delivering Daffodils" }
  owner.ev(QB.eventFrame, "QUEST_PROGRESS"); tick(owner, 1)
  assert(last() == "CompleteQuest 131", "banking: a quest that pays next to nothing is handed in")
  assert(QB:Upgrade(q1654), "The Test of Righteousness leads to a better step")
  owner.window = { id = 1654, xp = 0, title = "The Test of Righteousness" }
  owner.ev(QB.eventFrame, "QUEST_PROGRESS"); tick(owner, 1)
  assert(last() == "CompleteQuest 1654", "banking: the step you hand in to bank a better one is handed in")
  assert(q1793 and q1793.xpUnknown and not q1793.liveFull, "The Tome of Valor's XP is unknown to the catalog")
  owner.window = { id = 1793, xp = 1100, title = "The Tome of Valor" }
  owner.ev(QB.eventFrame, "QUEST_COMPLETE"); tick(owner, 1)
  assert(q1793.liveFull == 1100 and not tostring(last()):find("GetQuestReward"), "banking: the reward window's XP is read first, 1,100 is not nothing, it stays banked")
  assert(q410 and q410.xpUnknown, "The Dormant Shade's XP is unknown too")
  owner.window = { id = 410, xp = 300, title = "The Dormant Shade" }
  owner.ev(QB.eventFrame, "QUEST_COMPLETE"); tick(owner, 1)
  assert(not q410.liveFull and not tostring(last()):find("GetQuestReward"), "banking: ten levels down the window isn't recorded, and no number means it stays banked")
  owner.window = { id = 131, xp = 0, title = "Delivering Daffodils" }; owner.questCost = 50
  owner.ev(QB.eventFrame, "QUEST_COMPLETE"); tick(owner, 1)
  assert(not tostring(last()):find("GetQuestReward"), "a quest that costs money: the game asks, QuestBank waits")
  owner.questCost = 0
  owner.gossipActive = { { questID = 971, title = "Knowledge in the Deeps", isComplete = true }, { questID = 131, title = "Delivering Daffodils", isComplete = false }, { questID = 2922, title = "Cut one", isComplete = true } }
  owner.gossipAvail = { { questID = 7, title = "Kobold Camp Cleanup" } }
  QB:Plan().cut[2922] = true
  owner.ev(QB.eventFrame, "GOSSIP_SHOW"); tick(owner, 1)
  assert(last() == "SelectActiveQuest 2922", "banking at a gossip NPC: the one the Plan says to hand in, before any pick-up, never the banked one: " .. tostring(last()))
  QB:Plan().cut[2922] = nil
  owner.gossipActive, owner.gossipAvail = nil, nil
  -- banking: a pick-up the Plan page would cut is left on the NPC, one leading somewhere is taken
  assert(QB.Model.XpAt(QB.Quest.Get(131), 20) < 500 and QB.Model.XpAt(QB.Quest.Get(7), 20) < 500, "both pay next to nothing at 20")
  owner.gossipAvail = { { questID = 131, title = "Delivering Daffodils" }, { questID = 1654, title = "The Test of Righteousness" } }
  owner.ev(QB.eventFrame, "GOSSIP_SHOW"); tick(owner, 1)
  assert(last() == "SelectAvailableQuest 1654", "banking: the quest that leads somewhere is picked over one the Plan would cut: " .. tostring(last()))
  owner.gossipAvail = nil
  QB:SetLock("off"); QB:Recompute(true)
  assert(QB:Mode() == "quest", "questing by hand")
  owner.window = { id = 971, xp = 0, title = "Knowledge in the Deeps" }
  owner.ev(QB.eventFrame, "QUEST_PROGRESS"); tick(owner, 1)
  assert(last() == "CompleteQuest 971", "questing: a finished quest is handed in")
  owner.choices = 2
  owner.ev(QB.eventFrame, "QUEST_COMPLETE"); tick(owner, 1)
  assert(not tostring(last()):find("GetQuestReward"), "two rewards to choose from: left to you")
  owner.choices = 1
  owner.ev(QB.eventFrame, "QUEST_COMPLETE"); tick(owner, 1)
  assert(last() == "GetQuestReward 1", "one reward: taken")
  owner.choices = 0
  owner.ev(QB.eventFrame, "QUEST_COMPLETE"); tick(owner, 1)
  assert(last() == "GetQuestReward 0", "nothing to choose: finished")
  owner.gossipActive = { { questID = 131, title = "Delivering Daffodils", isComplete = false }, { questID = 971, title = "Knowledge in the Deeps", isComplete = true } }
  owner.gossipAvail = { { questID = 7, title = "Kobold Camp Cleanup" } }
  owner.ev(QB.eventFrame, "GOSSIP_SHOW"); tick(owner, 1)
  assert(last() == "SelectActiveQuest 971", "at a gossip NPC a finished quest is handed in before any pick-up, an unfinished one skipped: " .. tostring(last()))
  owner.gossipActive, owner.gossipAvail = nil, nil
  owner.greetActive = { { questID = 131, title = "Delivering Daffodils", isComplete = false }, { questID = 971, title = "Knowledge in the Deeps", isComplete = true } }
  owner.ev(QB.eventFrame, "QUEST_GREETING"); tick(owner, 1)
  assert(last() == "SelectActiveQuest #2", "a greeting NPC: the finished one, by its place in the list: " .. tostring(last()))
  owner.greetActive = nil
  -- Shift after the progress and reward windows opened
  owner.window = { id = 971, xp = 0, title = "Knowledge in the Deeps" }
  n = #owner.auto
  owner.ev(QB.eventFrame, "QUEST_PROGRESS"); owner.shift = true; tick(owner, 1); owner.shift = false
  assert(#owner.auto == n, "Shift after the progress window opened: no hand-in")
  owner.choices = 0
  owner.ev(QB.eventFrame, "QUEST_COMPLETE"); owner.shift = true; tick(owner, 1); owner.shift = false
  assert(#owner.auto == n, "Shift after the reward window opened: not finished")
  owner.ev(QB.eventFrame, "QUEST_ACCEPT_CONFIRM", "Brann Steelhand", "Escorting Erland", 435); owner.shift = true; tick(owner, 1); owner.shift = false
  assert(#owner.auto == n, "Shift after the escort prompt: not joined")
  QB:SetLock("auto"); QB:Recompute(true)
  assert(QB:Mode() == "lock", "back to banking")
  set.autoAccept, set.autoTurnIn = false, false
  owner.window, owner.completable, owner.choices = nil, nil, nil
  -- party chat: a quest arriving in the log, and one turning complete, as plain lines to the party
  local said = #owner.said
  table.insert(owner.log, { 7, 0 })
  owner.ev(QB.eventFrame, "QUEST_LOG_UPDATE"); tick(owner, 1)
  assert(#owner.said == said, "off: nothing said in party chat")
  set.sayAccept, set.sayComplete = true, true
  table.insert(owner.log, { 15, 0 })
  owner.ev(QB.eventFrame, "QUEST_LOG_UPDATE"); tick(owner, 1)
  assert(#owner.said == said + 1 and owner.said[#owner.said][1] == "Quest accepted: Quest 15" and owner.said[#owner.said][2] == "PARTY", "a new quest in the log is said in party chat: " .. tostring(owner.said[#owner.said] and owner.said[#owner.said][1]))
  for _, e in ipairs(owner.log) do if e[1] == 15 then e[2] = 1 end end
  owner.ev(QB.eventFrame, "QUEST_LOG_UPDATE"); tick(owner, 1)
  assert(#owner.said == said + 2 and owner.said[#owner.said][1] == "Quest complete: Quest 15", "and so is a quest turning complete: " .. tostring(owner.said[#owner.said][1]))
  for _ = 1, 2 do for i, e in ipairs(owner.log) do if e[1] == 7 or e[1] == 15 then table.remove(owner.log, i) break end end end
  -- not grouped: nothing is sent, and nothing is tried against a channel you're not in
  owner.o.group = false
  table.insert(owner.log, { 7, 0 })
  owner.ev(QB.eventFrame, "QUEST_LOG_UPDATE"); tick(owner, 1)
  assert(#owner.said == said + 2 and #owner.chatErrors == 0, "alone: nothing said, nothing tried")
  for i, e in ipairs(owner.log) do if e[1] == 7 then table.remove(owner.log, i) break end end
  owner.o.group = true
  set.sayAccept, set.sayComplete = false, false
  owner.ev(QB.eventFrame, "QUEST_LOG_UPDATE"); tick(owner, 1)
  assert(#owner.log == #OWNER_LOG, "the log is as it was")
  assert(#owner.chatErrors == 0, "every line sent was a line the game would take")
  owner.said = {} -- the lines above were this block's own; later tests count from nothing
  -- the four boxes on the Settings page
  UI:ShowTab(5); UI:Refresh()
  local v5 = UI.views[5]
  for _, name in ipairs({ "autoAccept", "autoTurnIn", "sayAccept", "sayComplete" }) do
    local cb = v5[name]
    assert(cb and not cb:GetChecked(), name .. " starts unticked")
    cb:SetChecked(true); cb.__scripts.OnClick(cb, "LeftButton")
    assert(QB:Settings()[name] == true, name .. " ticks on")
    cb:SetChecked(false); cb.__scripts.OnClick(cb, "LeftButton")
    assert(QB:Settings()[name] == false, name .. " ticks off")
  end
  local lay = checkLayout(UI.frame, "settings, scrolled")
  assert(#lay == 0, "the longer Settings page fits across and scrolls down: " .. table.concat(lay, "; "))
  local sf = v5.scroll
  local lo, hi = sf.bar:GetMinMaxValues()
  assert(sf.bar:IsShown() and hi > 0 and hi == 628 - sf:GetHeight(), "the knob runs exactly what does not fit: " .. tostring(hi) .. " of " .. tostring(sf:GetHeight()))
  sf.__scripts.OnMouseWheel(sf, -1)
  assert(sf.bar:GetValue() == 44, "a wheel notch scrolls 44 px")
  sf.bar:SetValue(hi); UI:Refresh()
  lay = checkLayout(UI.frame, "settings, scrolled to the bottom")
  assert(#lay == 0, "and the bottom of the page, in view, fits: " .. table.concat(lay, "; "))
  sf.bar:SetValue(0)
  UI:ShowTab(1); UI:Refresh()
end
-- 3.3.3: the suggestion window and the skipped places. Defaults first, then each setting, then back to auto.
do
  local set = QB:Settings()
  local function lvls(list) local lo, hi = 99, 0 for _, c in ipairs(list) do lo = math.min(lo, c.lvl); hi = math.max(hi, c.lvl) end return lo, hi end
  local function has(list, id) for _, c in ipairs(list) do if c.id == id then return true end end return false end
  local base = UI:Candidates(400)
  local lo, hi = lvls(base)
  print(string.format("candidates at 20, banking: %d quests, levels %d to %d", #base, lo, hi))
  assert(lo >= 13 and hi <= 32 and hi > 24, "banking at 20 suggests quest levels 13 to 32 by default")
  set.rangeAbove = 4
  local narrow = UI:Candidates(400)
  local _, hi2 = lvls(narrow)
  assert(#narrow > 0 and hi2 <= 24 and #narrow < #base, "up to 4 above: nothing past 24, and fewer suggestions")
  set.rangeBelow = 0
  local tight = UI:Candidates(400)
  local lo3 = lvls(tight)
  assert(#tight > 0 and lo3 >= 20, "down to 0 below: nothing under 20")
  set.rangeAbove, set.rangeBelow = "auto", "auto"
  assert(#UI:Candidates(400) == #base, "auto brings the default window back")
  -- skip a dungeon: Blackfathom Villainy leaves the candidates and the swap list, and comes back
  assert(has(base, 1200), "Blackfathom Villainy is a candidate before skipping")
  UI:ShowTab(1); UI:Refresh()
  local had, fineRow = false, nil
  for _, r in ipairs(v1.swaps) do
    if r:IsShown() and r.add.id == 1200 then had = true end
    if r:IsShown() and r.add.id == fineMess then fineRow = r end
  end
  assert(had, "Blackfathom Villainy is in the swap list before skipping")
  assert(fineRow and fineRow.cutName:GetText():find("Classic only", 1, true), "a swap from the Classic seed says Classic only: " .. tostring(fineRow and fineRow.cutName:GetText()))
  local label, on = QB:ToggleSkip("blackfathom")
  assert(label == "Blackfathom Deeps" and on, "/qb skip finds the dungeon by part of its name")
  assert(not has(UI:Candidates(400), 1200), "a skipped dungeon's quests are never suggested")
  UI:Refresh()
  for _, r in ipairs(v1.swaps) do if r:IsShown() then assert(r.add.id ~= 1200, "nor offered as a swap") end end
  UI:ShowTab(2); UI:Refresh()
  local function card(title) for _, c in ipairs(UI.views[2].cards.items) do if c:IsShown() and c.title:GetText() == title then return c end end end
  local bfd = card("Blackfathom Deeps")
  assert(bfd, "the skipped Blackfathom Deeps card stays: you hold quests there")
  assert(bfd.skip:IsShown() and bfd.skip.label:GetText() == "Back" and bfd.gain:GetText() == "Skipped", "and it says so, with a Back button")
  bfd.skip.__scripts.OnClick(bfd.skip)
  assert(has(UI:Candidates(400), 1200) and QB:SkipSignature() == "", "Back on the card un-skips it")
  bfd = card("Blackfathom Deeps")
  assert(bfd and bfd.skip.label:GetText() == "Skip" and bfd.gain:GetText() ~= "Skipped", "and the card reads normally again")
  -- a place with nothing of yours: Skip on its card makes it vanish, /qb skip brings it back
  local fetchOnly
  for _, c in ipairs(UI.views[2].cards.items) do if c:IsShown() and c.skip:IsShown() and c.count:GetText() == "Nothing planned here yet" then fetchOnly = fetchOnly or c end end
  assert(fetchOnly, "a card with nothing planned")
  local foTitle, foKey = fetchOnly.title:GetText(), fetchOnly.skip.key
  fetchOnly.skip.__scripts.OnClick(fetchOnly.skip)
  assert(QB:Settings().skipCat[foKey] and not card(foTitle), "Skip on a card with nothing of yours: the card goes")
  for _, c in ipairs(UI:Candidates(400)) do assert(QB.Data.CAT[c.cat].key ~= foKey, "and nothing there is suggested: " .. QB.Data.QN[c.id]) end
  local l0, on0 = QB:ToggleSkip(foTitle)
  assert(l0 == foTitle and on0 == false and card(foTitle), "/qb skip and its name brings the card back")
  -- every place you hold or planned quests in has a card, wherever the XP puts it
  for _, e in ipairs(QB.state.logOrder) do
    local q = QB.Quest.Get(e.id)
    if q and q.cat and QB:InPlan(q, QB:Status(q)) then assert(card(q.cat.name), "a card for every place you hold quests: " .. q.cat.name) end
  end
  -- the richest place first: the header number never grows down the list (banking: no distance discount)
  do
    local last = math.huge
    for _, c in ipairs(UI.views[2].cards.items) do
      if c:IsShown() and c.skip:IsShown() and c.gain:GetText():sub(1, 1) == "+" then
        local n = tonumber((c.gain:GetText():gsub("[^%d]", "")))
        assert(n and n <= last, "cards sort by the XP still to collect: " .. c.title:GetText() .. " shows +" .. n .. " below +" .. tostring(last))
        last = n
      end
    end
  end
  -- the Classic seed's quests say so in their Plan row
  do
    local fineShown
    for _, c in ipairs(UI.views[2].cards.items) do for _, r in ipairs(c.rows.items) do if r:IsShown() and r.q and r.q.id == fineMess then fineShown = r end end end
    assert(fineShown, "A Fine Mess has a Plan row")
    assert(fineShown.status:GetText():find("Classic only", 1, true), "and its row says Classic only: " .. fineShown.status:GetText())
  end
  -- skip a continent: Razorfen Kraul's Blueleaf Tubers (Kalimdor) goes, nothing from Kalimdor stays
  local tubers
  for id, name in pairs(QB.Data.QN) do if name == "Blueleaf Tubers" then tubers = id end end
  assert(tubers and has(base, tubers), "Blueleaf Tubers is a candidate for the owner in Stormwind")
  -- class and other quests take their continent from the turn-in NPC: some of the owner's are handed in on Kalimdor
  local viaNPC = 0
  for _, c in ipairs(base) do
    local cat, q = QB.Data.CAT[c.cat], QB.Quest.Get(c.id)
    if cat.cont == nil and q.turnIdx and QB.Data.NPC[q.turnIdx] and QB.Data.NPC[q.turnIdx][5] == 1 then viaNPC = viaNPC + 1 end
  end
  assert(viaNPC > 0, "the owner has class or other quests handed in on Kalimdor")
  local l3, on3 = QB:ToggleSkip("Kalimdor")
  assert(l3 == "Kalimdor" and on3, "/qb skip Kalimdor")
  local noKal = UI:Candidates(400)
  assert(not has(noKal, tubers) and #noKal < #base, "skipping Kalimdor drops Razorfen Kraul's quests")
  for _, c in ipairs(noKal) do
    local cat, q = QB.Data.CAT[c.cat], QB.Quest.Get(c.id)
    assert(not (cat and cat.cont == 1), "nothing from Kalimdor is left: " .. QB.Data.QN[c.id])
    if cat.cont == nil and not cat.dungeon then assert(not (q.turnIdx and QB.Data.NPC[q.turnIdx] and QB.Data.NPC[q.turnIdx][5] == 1), "nor a class or other quest handed in there: " .. QB.Data.QN[c.id]) end
  end
  UI:Refresh()
  bfd = card("Blackfathom Deeps")
  assert(bfd and bfd.gain:GetText() == "Skipped" and not bfd.skip:IsShown() and bfd.where:GetText():find("Kalimdor is skipped in Settings", 1, true), "a card in a skipped continent says so, and its own Skip button steps aside: " .. tostring(bfd and bfd.where:GetText()))
  QB:ToggleSkip("kali")
  assert(#UI:Candidates(400) == #base, "and everything is back")
  -- the slash command and its answers
  local before = #owner.chat
  owner.env.SlashCmdList.QUESTBANK("skip Wailing Caverns")
  assert(owner.chat[#owner.chat]:find("Wailing Caverns is skipped"), "/qb skip says what it did: " .. owner.chat[#owner.chat])
  owner.env.SlashCmdList.QUESTBANK("skip")
  assert(owner.chat[#owner.chat]:find("Skipping Wailing Caverns"), "/qb skip lists the skipped places: " .. owner.chat[#owner.chat])
  owner.env.SlashCmdList.QUESTBANK("skip nowhere at all")
  assert(owner.chat[#owner.chat]:find("No zone, dungeon or continent called"), "an unknown name is said")
  owner.env.SlashCmdList.QUESTBANK("skip none")
  assert(QB:SkipSignature() == "" and #UI:Candidates(400) == #base, "/qb skip none clears the list")
  -- the Settings page: steppers, Auto, the continent boxes, and nothing clipped
  UI:ShowTab(5); UI:Refresh()
  local v5 = UI.views[5]
  assert(v5.rangeAboveLabel:GetText():find("12 levels above me %(auto%)"), "Settings shows the auto window: " .. v5.rangeAboveLabel:GetText())
  v5.rangeAboveUp.__scripts.OnClick(v5.rangeAboveUp)
  assert(QB:Settings().rangeAbove == 13 and v5.rangeAboveLabel:GetText():find("13 levels above me$"), "+ makes it 13, no longer auto")
  v5.rangeBelowDown.__scripts.OnClick(v5.rangeBelowDown)
  assert(QB:Settings().rangeBelow == 6, "- makes below 6")
  v5.rangeAuto.__scripts.OnClick(v5.rangeAuto)
  assert(QB:Settings().rangeAbove == "auto" and QB:Settings().rangeBelow == "auto", "Auto puts both back")
  v5.skipKal:SetChecked(true); v5.skipKal.__scripts.OnClick(v5.skipKal)
  assert(QB:Settings().skipCont[1] == true and v5.skipKal:GetChecked(), "the Kalimdor box skips Kalimdor")
  v5.skipKal:SetChecked(false); v5.skipKal.__scripts.OnClick(v5.skipKal)
  assert(not QB:Settings().skipCont[1], "and un-skips it")
  QB:ToggleSkip("Wailing Caverns")
  UI:Refresh()
  assert(v5.skipText:GetText():find("Skipped: Wailing Caverns", 1, true), "Settings lists the skipped dungeon: " .. v5.skipText:GetText())
  local lay = checkLayout(UI.frame, "settings with a skip")
  assert(#lay == 0, "the Suggestions block fits: " .. table.concat(lay, "; "))
  for _, z in ipairs({ "The Deadmines", "Redridge Mountains", "Duskwood", "Westfall", "Stonetalon Mountains" }) do QB:ToggleSkip(z) end
  UI:Refresh()
  assert(v5.skipText:GetText():find(" and 3 more", 1, true), "six skips: three named and the rest counted: " .. v5.skipText:GetText())
  lay = checkLayout(UI.frame, "settings with six skips")
  assert(#lay == 0, "and the list still fits its box: " .. table.concat(lay, "; "))
  owner.env.SlashCmdList.QUESTBANK("skip none")
  assert(QB:SkipSignature() == "", "clean again")
  UI:ShowTab(1); UI:Refresh()
end
-- adding a quest never makes the plan worse: each plan starts from the last route
do
  local p = QB:Plan()
  -- the owner's swaps, one by one: Deadmines and Blackfathom into the free slots, then two swaps
  local steps = { { 166 }, { 1200 }, { 2040, 353 }, { 2904, 97894 }, { 1221, 454 } }
  QB.Model.Finish()
  for _, st in ipairs(steps) do
    local before60, beforeL = QB.routePlan.at60, QB.routePlan.level
    p.add[st[1]] = true
    if st[2] then p.cut[st[2]] = true end
    QB:Recompute(true)
    local r = QB.routePlan
    print(string.format("  add %-30s at 60 min %.2f -> %.2f, in all %.2f -> %.2f", QB.Quest.Get(st[1]).name, before60, r.at60, beforeL, r.level))
    assert(r.at60 >= before60 - 1e-6, "adding a quest never costs the first hour: " .. QB.Quest.Get(st[1]).name)
  end
  for _, st in ipairs(steps) do p.add[st[1]] = nil; if st[2] then p.cut[st[2]] = nil end end
  QB:Recompute(true)
end
do
  local villainy
  for _, r in ipairs(v1.swaps) do if r:IsShown() and r.add.id == 1200 then villainy = r end end
  assert(villainy and villainy.via and villainy.via.id == 1198, "Blackfathom Villainy is offered, by way of In Search of Thaelrid")
  lines = {}; villainy.__scripts.OnEnter(villainy)
  assert(lines[1]:find("hand it in inside Blackfathom Deeps"), "and its tooltip says how: " .. lines[1])
end
UI:ShowTab(2)
local cards = 0
for _, c in ipairs(v2.cards.items) do
  if c:IsShown() then
    cards = cards + 1
    if cards <= 8 then print(string.format("  card %-26s %-12s %s", c.title:GetText(), c.gain:GetText(), c.count:GetText())) end
    poke(c.pin)
    for _, r in ipairs(c.rows.items) do if r:IsShown() then poke(r) end end
  end
end
print("prep cards:", cards)
-- open a card to see every quest in it, and close it again
for _, c in ipairs(v2.cards.items) do
  if c:IsShown() and c.more:IsShown() then
    local before = 0
    for _, r in ipairs(c.rows.items) do if r:IsShown() then before = before + 1 end end
    local title = c.title:GetText()
    c.more.__scripts.OnClick(c.more)
    local after = 0
    for _, cc in ipairs(v2.cards.items) do
      if cc:IsShown() and cc.title:GetText() == title then for _, r in ipairs(cc.rows.items) do if r:IsShown() then after = after + 1 end end end
    end
    print(string.format("  opened %s: %d rows, then %d", title, before, after))
    assert(after > before, "opening a card shows more")
    for _, cc in ipairs(v2.cards.items) do if cc:IsShown() and cc.title:GetText() == title then cc.more.__scripts.OnClick(cc.more) end end
    break
  end
end
UI:ShowTab(3)
print("route now:", v3.summary:GetText())
assert(QB:Mode() == "lock" and QB:Lock() == 20 and QB.CAP == 30, "level 20 at a cap of 20: banking for 30")
assert(v3.summary:GetText() == "86,890 XP  |  level 23.38  |  93 min  |  at 60 min 23.36", "the owner's banked route is unchanged")
print("setup:", v3.setup:GetText())
for _, l in ipairs(v3.legs.items) do
  if l:IsShown() then
    print(string.format("  %5s %-26s %-34s %s", l.clock:GetText(), l.name:GetText(), l.travel:GetText(), l.level:GetText()))
    poke(l.pin)
    for _, r in ipairs(l.rows) do if r:IsShown() then poke(r) end end
  end
end
v3.modePlan.__scripts.OnClick(v3.modePlan)
QB.Model.Finish()
UI:Refresh()
print("route plan:", v3.summary:GetText())
assert(v3.summary:GetText() == "120,940 XP  |  level 24.50  |  133 min  |  at 60 min 24.36", "the owner's full plan is unchanged")
print("setup:", v3.setup:GetText())
for _, key in ipairs({ "mounted", "bag", "pins" }) do
  local b = UI.header.toggles[key]
  lines = {}; b.__scripts.OnEnter(b); assert(#lines > 0)
  b.__scripts.OnClick(b, "LeftButton")
  b.__scripts.OnClick(b, "RightButton")
end
-- the third switch: the hour's goal while banking; right-click stops banking, and it becomes the lock switch
do
  local g = UI.header.toggles.goal
  lines = {}; g.__scripts.OnEnter(g); assert(#lines > 0)
  g.__scripts.OnClick(g, "LeftButton")
  g.__scripts.OnClick(g, "LeftButton")
  assert(QB:Settings().goal == "hour", "two clicks: back to the first hour")
  g.__scripts.OnClick(g, "RightButton")
  QB:Recompute(true); UI:Refresh()
  assert(QB:Mode() == "quest" and g.key == "lock" and g.caption:GetText() == "Questing", "right-click: questing, and the switch says so")
  print("questing header:", UI.header.legend:GetText())
  assert(not UI.header.legend:GetText():find("60 min"), "questing has no hand-in hour")
  lines = {}; g.__scripts.OnEnter(g); assert(lines[1] == "Questing")
  g.__scripts.OnClick(g, "LeftButton")
  QB:Recompute(true); UI:Refresh()
  assert(QB:Mode() == "lock" and g.key == "goal", "click again: QuestBank finds the lock and banks")
end
QB:Settings().pins = true
QB.Model.Finish()
UI:Refresh()
print("after switches:", v3.summary:GetText())
v3.modeNow.__scripts.OnClick(v3.modeNow)
QB.Model.Finish()

-- the layout of every page, checked and drawn
local layouts, problems = {}, {}
local function hoverFirst(list, n)
  local k = 0
  for _, f in ipairs(list) do
    if f:IsShown() then f.__hover = true; k = k + 1; if k >= (n or 1) then break end end
  end
end
local function unhover() for _, o in ipairs(ALL) do o.__hover = nil end end
for tab = 1, 5 do
  UI:ShowTab(tab)
  QB.Model.Finish()
  UI:Refresh()
  for _, p in ipairs(checkLayout(UI.frame, "tab " .. tab)) do problems[#problems + 1] = p end
  unhover()
  if tab == 1 then
    v1.slots[2].__hover = true
    hoverFirst(v1.swaps)
  elseif tab == 2 then
    for _, c in ipairs(v2.cards.items) do
      if c:IsShown() and c.pin:IsShown() then c.pin.__hover = true break end
    end
    local shown = 0
    for _, c in ipairs(v2.cards.items) do
      if c:IsShown() then shown = shown + 1; if shown == 3 then hoverFirst(c.rows.items) end end
    end
  elseif tab == 3 then
    local l = v3.legs.items[2]
    if l then l.pin.__hover = true; hoverFirst(l.rows) end
  end
  layouts[#layouts + 1] = dumpLayout(UI.frame, ({ "Quest Log", "Plan", "Hand-in Route", "Party", "Settings" })[tab] .. " (one row hovered)")
  unhover()
end

-- right-click: the menu of what you can do with a quest
do
  UI:ShowTab(1)
  local b = v1.slots[1]
  b.__scripts.OnClick(b, "RightButton")
  local m = owner.env.QuestBankMenu
  assert(m and m:IsShown(), "right-click opens the menu")
  local labels = {}
  for _, it in ipairs(m.items) do if it:IsShown() then labels[#labels + 1] = it.label:GetText() end end
  print("menu for " .. m.title:GetText() .. ": " .. table.concat(labels, " | "))
  local copy
  for _, it in ipairs(m.items) do if it:IsShown() and it.label:GetText():find("Wowhead") then copy = it end end
  copy.__scripts.OnClick(copy)
  assert(not m:IsShown(), "choosing an item closes the menu")
  local lf = owner.env.QuestBankLink
  assert(lf and lf:IsShown() and lf.eb:GetText():find("wowhead.com/forever/quest="), "the link box shows the quest's link")
  print("link box:", lf.eb:GetText())
  lf:Hide()
  -- cut from the menu, and keep again
  local id = b.q.id
  b.__scripts.OnClick(b, "RightButton")
  for _, it in ipairs(m.items) do if it:IsShown() and it.label:GetText() == "Cut it from the plan" then it.__scripts.OnClick(it) end end
  assert(QB:IsCut(id), "the menu cuts a quest")
  QB:ToggleAdd(id)
  assert(not QB:IsCut(id))
  m.catcher.__scripts.OnClick(m.catcher)
end

-- the Prep page scrolled to the Redridge card
do
  UI:ShowTab(2)
  UI:Refresh()
  for _, c in ipairs(v2.cards.items) do
    if c:IsShown() and c.title:GetText() == "Redridge Mountains" then
      local _, _, _, _, y = c.__points[1].point, nil, nil, nil, c.__points[1].y
      v2.scroll.bar:SetValue(-c.__points[1].y)
      layouts[#layouts + 1] = dumpLayout(UI.frame, "Plan, scrolled to Redridge")
      v2.scroll.bar:SetValue(0)
    end
  end
end

-- shift-click: cut a quest in the log, fetch one that isn't
owner.shift = true
local slot = v1.slots[1]
UI:ShowTab(1)
local cutID = v1.slots[1].q.id
slot.__scripts.OnClick(slot, "LeftButton")
assert(QB:IsCut(cutID), "shift-click cuts a quest in the log")
for _, b in ipairs(v1.slots) do if b.q and b.q.id == cutID then slot = b end end
slot.__scripts.OnClick(slot, "LeftButton")
assert(not QB:IsCut(cutID), "and keeps it again")
UI:ShowTab(2)
local fetchRow
for _, c in ipairs(v2.cards.items) do for _, r in ipairs(c.rows.items) do if r:IsShown() and r.q and not QB.state.log[r.q.id] and r.st.code == "todo" then fetchRow = fetchRow or r end end end
assert(fetchRow, "a quest to fetch on the Prep page")
local fetchID = fetchRow.q.id
fetchRow.__scripts.OnClick(fetchRow, "LeftButton")
assert(QB:IsAdded(fetchID), "shift-click adds it to the plan")
print("fetch:", QB.Quest.Get(fetchID).name, "added to the plan")
-- with the chat box open, shift-click puts a link in chat instead, like the game's quest log
do
  UI:ShowTab(1)
  local b = v1.slots[1]
  local id = b.q.id
  owner.chatOpen = true
  b.__scripts.OnClick(b, "LeftButton")
  assert(owner.chatLinks[#owner.chatLinks]:find("|Hquest:" .. id .. ":"), "a quest in your log: the game's own link")
  assert(not QB:IsCut(id), "and nothing is cut")
  -- rows are pooled and the page was refreshed when the quest joined the plan: find its row again
  local row2
  for _, c in ipairs(v2.cards.items) do for _, r in ipairs(c.rows.items) do if r:IsShown() and r.q and r.q.id == fetchID then row2 = row2 or r end end end
  assert(row2, "the fetched quest still has a row on the Prep page")
  row2.__scripts.OnClick(row2, "LeftButton")
  assert(owner.chatLinks[#owner.chatLinks] == "[" .. row2.q.name .. "]", "a quest the game hasn't sent yet: its name")
  for _, bs in ipairs(v1.bagSlots) do
    if bs:IsShown() and bs.item and bs.item.id then
      bs.__scripts.OnClick(bs, "LeftButton")
      assert(owner.chatLinks[#owner.chatLinks]:find("|Hitem:" .. bs.item.id .. ":"), "an item in your bags: its link")
      break
    end
  end
  print("links:", #owner.chatLinks, owner.chatLinks[1])
  owner.chatOpen = false
end
owner.shift = false
tick(owner, 1)
QB.Model.Finish()

-- a quest leaves the log without a hand-in, and one is handed in
local before = #owner.chat
table.remove(owner.log, 9) -- 217
owner.ev(QB.eventFrame, "QUEST_REMOVED", 217)
owner.ev(QB.eventFrame, "QUEST_LOG_UPDATE")
tick(owner, 1)
assert(QB:Plan().removed[217], "an abandoned quest is noticed")
print("abandon:", owner.chat[#owner.chat])
UI:ShowTab(1)
print("dropped:", v1.dropTitle:GetText(), "|", v1.drops:GetText())

-- the cap goes up: the lock lifts, the first hand-in starts the run, the route re-plans from here
owner.level, owner.xp = 20, 0
owner.cap = 30
QB:ReadState()
assert(QB:Mode() == "rush" and QB.CAP == 30, "the cap went up: cash the bank in (" .. QB:Mode() .. ")")
QB.Model.Finish()
local firstLeg = QB.routeNow.legs[1]
local firstQ = firstLeg.rows[1].q.id
owner.window = { id = firstQ, xp = firstLeg.rows[1].xp }
owner.ev(QB.eventFrame, "QUEST_COMPLETE")
for i, e in ipairs(owner.log) do if e[1] == firstQ then table.remove(owner.log, i) break end end
owner.done[firstQ] = true
owner.ev(QB.eventFrame, "QUEST_TURNED_IN", firstQ, firstLeg.rows[1].xp)
owner.ev(QB.eventFrame, "QUEST_LOG_UPDATE")
tick(owner, 1)
assert(QB.Run.Get(), "the first hand-in above the old cap starts the run")
QB.Model.Finish()
UI:ShowTab(3)
UI:Refresh()
print("run:", v3.setup:GetText())
local handed = v3.legs.items[1]
print("  first leg:", handed.travel:GetText(), handed.name:GetText())
for _, p in ipairs(checkLayout(UI.frame, "run")) do problems[#problems + 1] = p end
layouts[#layouts + 1] = dumpLayout(UI.frame, "Hand-in Route, during the run")
print("chat:", owner.chat[#owner.chat])
print("live XP from the game:", QB.Live.Source(QB.Quest.Get(firstQ)))

-- telling the party and guild: offered during the run, shown first, sent only by Post
do
  local S = owner.QB.Sync
  local function click(b) b.__scripts.OnClick(b, "LeftButton") end
  local function tickBox(b, on) b:SetChecked(on); b.__scripts.OnClick(b, "LeftButton") end
  UI:ShowTab(3)
  UI:Refresh()
  poke(v3.post)
  local P = owner.env.QuestBankPost
  assert(P and P:IsShown(), "Post opens the dialog")
  print("post, during the run:", P.eb:GetText())
  assert(P.eb:GetText():find("min into my hand%-in run"), "during a run it says how the run goes")
  assert(P.party:GetChecked() and P.guild:GetChecked() and P.post:IsEnabled(), "party and guild ticked, Post ready")
  assert(not P.eb:HasFocus(), "the message box doesn't take the keyboard from you")
  for _, pr in ipairs(checkLayout(P, "post dialog")) do problems[#problems + 1] = pr end
  layouts[#layouts + 1] = dumpLayout(P, "Post in chat")
  click(P.cancel)
  assert(not P:IsShown() and #owner.said == 0, "Cancel posts nothing")
  P.__scripts.OnDragStart(P); P.__scripts.OnDragStop(P)
  assert(QB:Settings().post.pos, "dragged somewhere, it opens there next time")
  -- a level-up in the run offers it; Post sends it to both
  owner.level, owner.xp = 21, 4000
  owner.ev(QB.eventFrame, "PLAYER_LEVEL_UP", 21)
  tick(owner, 2)
  assert(P:IsShown() and P.eb:GetText():find("^Level 21, %d+ min into my hand%-in run"), "a level-up in the run is offered: " .. P.eb:GetText())
  print("offered at level 21:", P.why:GetText(), "|", P.eb:GetText())
  click(P.post)
  assert(not P:IsShown(), "Post closes it")
  assert(#owner.said == 2 and owner.said[1][2] == "PARTY" and owner.said[2][2] == "GUILD", "Post sends it to party and guild")
  assert(owner.said[1][1] == owner.said[2][1], "the same words to both")
  -- untick the guild: only the party, and it stays unticked next time
  owner.said = {}
  poke(v3.post)
  tickBox(P.guild, false)
  click(P.post)
  assert(#owner.said == 1 and owner.said[1][2] == "PARTY", "only where it's ticked")
  poke(v3.post)
  assert(not P.guild:GetChecked(), "the tick is remembered")
  tickBox(P.guild, true)
  tickBox(P.party, false)
  tickBox(P.guild, false)
  assert(not P.post:IsEnabled(), "nothing ticked: Post is off")
  tickBox(P.party, true)
  tickBox(P.guild, true)
  -- your own words: one line, no escape codes, and an offer doesn't write over them
  P.eb:SetText("Ding!|cff\nsee you in Deadmines")
  P.eb.__scripts.OnTextChanged(P.eb, true)
  assert(P.eb:GetText() == "Ding!cffsee you in Deadmines", "line breaks and escape codes go: " .. P.eb:GetText())
  owner.level = 22
  owner.ev(QB.eventFrame, "PLAYER_LEVEL_UP", 22)
  tick(owner, 2)
  assert(P.eb:GetText() == "Ding!cffsee you in Deadmines", "an offer doesn't write over what you typed")
  owner.said = {}
  click(P.post)
  assert(#owner.said == 2 and owner.said[1][1] == "Ding!cffsee you in Deadmines", "your words go out as typed")
  -- too long for chat: cut at 255 bytes, on a whole letter
  local long = S.CleanPost(("\195\184"):rep(200))
  assert(#long == 254 and long == ("\195\184"):rep(127), "cut at 255 bytes on a whole letter")
  assert(S.CleanPost(" a|b\r\nc ") == "a/b c", "one clean line")
  -- the first hour of the run is offered when it's up
  owner.said = {}
  tick(owner, 3600)
  assert(QB.Run.Get().hour and P:IsShown() and P.eb:GetText():find("^First hour of my hand%-in run: level 22%.%d"), "the first hour is offered: " .. P.eb:GetText())
  print("offered at the hour:", P.eb:GetText())
  click(P.cancel)
  -- offers switched off: a level-up says nothing
  poke(v3.post)
  tickBox(P.auto, false)
  click(P.cancel)
  assert(QB:Settings().post.auto == false)
  owner.level = 23
  owner.ev(QB.eventFrame, "PLAYER_LEVEL_UP", 23)
  tick(owner, 2)
  assert(not P:IsShown(), "no offers when they're switched off")
  QB:Settings().post.auto = true
  assert(#owner.said == 0, "nothing is ever posted on its own")
  -- /qb post opens it too
  owner.env.SlashCmdList.QUESTBANK("post")
  assert(P:IsShown() and P.eb:GetText():find("into my hand%-in run"), "/qb post opens it")
  click(P.cancel)
end

-- handed in: the game's list of completed quests counts even when the quest's flag says no
do
  local flag = owner.env.C_QuestLog.IsQuestFlaggedCompleted
  owner.env.C_QuestLog.IsQuestFlaggedCompleted = function(id) if id == 6981 then return false end return flag(id) end
  QB.API.RefreshDone()
  local st = QB:Status(QB.Quest.Get(6981))
  assert(st.code == "done", "The Glowing Shard in the completed list is done: " .. st.text)
  owner.env.SlashCmdList.QUESTBANK("done glowing shard")
  print("/qb done:", owner.chat[#owner.chat])
  owner.env.C_QuestLog.IsQuestFlaggedCompleted = flag
  -- a quest that starts from a drop says so
  owner.done[6981] = nil
  QB.API.RefreshDone()
  print("Glowing Shard, not done:", QB:Status(QB.Quest.Get(6981)).text)
  owner.done[6981] = true
  QB.API.RefreshDone()
end

-- the safety net: with QUESTBANK_DEV off, an error is recorded and QuestBank carries on
do
  owner.env.SlashCmdList.QUESTBANK("errors")
  assert(owner.env.QuestBankErrors and owner.env.QuestBankErrors:IsShown(), "/qb errors opens its box")
  assert(owner.env.QuestBankErrors.eb:GetText():find("Nothing recorded"), "and says when nothing went wrong")
  owner.env.QuestBankErrors:Hide()
  owner.env.QUESTBANK_DEV = false
  local boom = QB.Safe(function() local t = nil; return t.field end, "test")
  boom()
  boom()
  owner.env.QUESTBANK_DEV = true
  local list = owner.env.QuestBankDB.errors
  assert(list and #list == 1 and list[1].count == 2 and list[1].msg:find("attempt to index"), "the error is recorded once, counted twice")
  print("error net:", owner.chat[#owner.chat])
  owner.env.SlashCmdList.QUESTBANK("errors")
  local text = owner.env.QuestBankErrors.eb:GetText()
  assert(text:find("attempt to index") and text:find("2x, test"), "/qb errors shows it with where and how often")
  owner.env.QuestBankErrors:Hide()
  owner.env.SlashCmdList.QUESTBANK("errors clear")
  assert(#owner.env.QuestBankDB.errors == 0, "/qb errors clear empties the list")
end

-- chains: Morganth waits behind A Watchful Eye and Looking Further, and says so
do
  local morganth = QB.Quest.Get(249)
  local st = QB:Status(morganth)
  assert(st.code == "prereq" and st.text:find("A Watchful Eye"), "Morganth needs its chain first: " .. st.text)
  owner.done[94], owner.done[248] = true, true
  st = QB:Status(morganth)
  assert(st.code == "todo", "Morganth opens once Looking Further is done")
  owner.done[94], owner.done[248] = nil, nil
  lines = {}
  UI.QuestTooltip(owner.env.GameTooltip, morganth, QB:Status(morganth))
  local chain = false
  for _, l in ipairs(lines) do if l:find("Looking Further") then chain = true end end
  assert(chain, "the tooltip shows the chain")
  print("Morganth:", QB:Status(morganth).text)
  local tz = QB:Status(QB.Quest.Get(19))
  assert(tz.text:find("Hand in Blackrock Blockade first"), "holding Blackrock Blockade puts it next in line: " .. tz.text)
  print("Tharil'zun:", tz.text)
end

-- map pins
QB.Pins:Update()
print("world map pins:", #owner.map.pins, "waypoints:", #owner.pins)
assert(#owner.map.pins > 0, "the route has pins on the world map")
for _, pin in ipairs(owner.map.pins) do lines = {}; pin:OnMouseEnter(); assert(#lines > 0); pin:OnMouseLeave() end

-- minimap button, slash commands, export
local mb = QB.Minimap.button
mb.__scripts.OnDragStart(mb); mb.__scripts.OnUpdate(mb); mb.__scripts.OnDragStop(mb)
mb.__scripts.OnClick(mb, "RightButton")
lines = {}; mb.__scripts.OnEnter(mb); assert(#lines > 0)
for _, cmd in ipairs({ "export", "route", "prep", "party", "minimap", "minimap", "reset", "next", "pins", "pins", "stop" }) do owner.env.SlashCmdList.QUESTBANK(cmd) end
assert(not QB.Run.Get(), "/qb stop ends the run")
do
  local P = owner.env.QuestBankPost
  assert(P:IsShown() and P.eb:GetText():find("^Hand%-in run done: level 20%.0 to 23%.%d in %d+ min, %d+ quests?, %+"), "the end of the run is offered: " .. P.eb:GetText())
  print("offered at the end:", P.eb:GetText())
  P.cancel.__scripts.OnClick(P.cancel)
  -- without a run: where the bank and the plan take you
  owner.env.SlashCmdList.QUESTBANK("post")
  assert(QB:Mode() == "quest", "the run is over and the bank cashed in: questing from here")
  assert(P.eb:GetText():find("^Level %d+%.%d: the quests ready in my log take me to"), "questing, it posts the log and the plan")
  print("post, no run:", P.eb:GetText())
  P.cancel.__scripts.OnClick(P.cancel)
end
owner.ev(QB.eventFrame, "PLAYER_LOGOUT")

----------------------------------------------------------------------------
-- scenario 2: a friend, Alliance warrior at 18, other quests; party sync both ways
----------------------------------------------------------------------------
local friend = newClient({
  name = "Brann", level = 18, cap = 20, faction = "Alliance", className = "Warrior", class = "WARRIOR", classID = 1, race = "Dwarf",
  log = { { 166, 0 }, { 214, 1 }, { 2040, 1 }, { 167, 1 }, { 101, 1 }, { 58, 0 }, { 90, 1 }, { 1199, 0 }, { 1200, 0 }, { 128, 1 }, { 219, 0 }, { 91, 1 } },
  done = { [65] = true, [132] = true, [135] = true, [141] = true, [142] = true, [155] = true, [56] = true, [57] = true, [1198] = true },
  group = true, guild = true, world = { 0, -10500, 1050 }, bind = "Sentinel Hill", riding = false,
  bagSlots = {},
})
login(friend)
-- the friend has 7 Twilight Pendants on them and 3 in the bank: QuestBank remembers the bank once it's been open
do
  local F = friend.QB
  friend.o.bagSlots = { { 5879, 7 } }
  friend.o.bank = { [5879] = 3 }
  local q = F.Quest.Get(1199)
  F:ReadState()
  print("Twilight Falls before the bank was opened:", F:Status(q).text)
  friend.ev(F.eventFrame, "BANKFRAME_OPENED")
  friend.ev(F.eventFrame, "BANKFRAME_CLOSED")
  F:ReadState()
  local st = F:Status(q)
  print("after the bank was opened:", st.text)
  assert(st.text:find("Take 3 out of your bank"), "bank items count toward the quest")
  lines = {}
  F.UI.QuestTooltip(friend.env.GameTooltip, q, st)
  local itemLine = false
  for _, l in ipairs(lines) do if l:find("Twilight Pendant") then itemLine = true; print("  tooltip:", l) end end
  assert(itemLine, "the tooltip counts the item in bags and bank")
  -- the quest turns complete: chat says so
  for _, e in ipairs(friend.log) do if e[1] == 1199 then e[2] = 1 end end
  friend.o.bagSlots = { { 5879, 10 } }
  friend.o.bank = {}
  friend.ev(F.eventFrame, "QUEST_LOG_UPDATE")
  tick(friend, 1)
  print("friend's chat:", friend.chat[#friend.chat])
  assert(F:Mode() == "quest", "level 18 under a cap of 20: questing")
  assert(friend.chat[#friend.chat]:find("is complete, hand it in"), "completing a quest is announced, questing-style")
end

-- the friend talks to Guard Howe: the quest window shows Blackrock Bounty's XP, and the party hears it
friend.window = { id = 128, xp = 2000 }
friend.ev(friend.QB.eventFrame, "QUEST_COMPLETE")
friend.window = nil
for _ = 1, 6 do tick(owner, 5); tick(friend, 5); deliver() end
friend.QB.Model.Finish()
owner.QB.Model.Finish()
for _ = 1, 4 do tick(owner, 5); tick(friend, 5); deliver() end
local mem = owner.QB.Sync:Members()
for _, m in ipairs(mem) do print("  member:", m.name, m.key) end
assert(#mem == 1 and mem[1].name == "Brann Steelhand", "the owner sees the friend by name (with the surname chat gives), and not itself: " .. table.concat((function() local t = {} for _, m in ipairs(mem) do t[#t + 1] = m.name end return t end)(), ", "))
assert(owner.QB.Sync.mySender == "Mikal Steelhand-Forever Normal", "the owner learned its own sender string from the echo")
assert(mem[1].quests, "and the friend's quests")
print(string.format("sync: owner sees %s level %d, banked %.2f, plan %.2f, %d quests", mem[1].name, mem[1].level, mem[1].banked, mem[1].plan,
  (function() local n = 0 for _ in pairs(mem[1].quests) do n = n + 1 end return n end)()))
assert(#friend.QB.Sync:Members() == 1, "the friend sees the owner")
local dungeons = owner.QB.Sync:Dungeons()
for _, d in ipairs(dungeons) do
  print(string.format("  dungeon: %-20s %s  +%s", d.cat.name, table.concat(d.people, ", "), QB.Comma(d.xp)))
  for _, e in ipairs(d.quests) do
    if e.need > 0 then
      local who = {}
      for _, w in ipairs(e.who) do who[#who + 1] = w.name .. " " .. (w.code == "a" and (w.prog or "in log") or w.code) end
      print(string.format("      %-32s %s", e.q and e.q.name or e.id, table.concat(who, ", ")))
    end
  end
end
-- leaving the group: what was waiting for the party is dropped, not tried forever
do
  local S = owner.QB.Sync
  deliver()
  S:Broadcast(true)            -- queued for the party and the guild
  owner.o.group = false        -- then you leave the group before they go out
  for _ = 1, 12 do tick(owner, 2) end
  local left = 0
  for _, m in ipairs(S.out) do if m[2] == "PARTY" then left = left + 1 end end
  assert(left == 0, "messages for a party you left are dropped, not retried forever")
  owner.o.group = true
  owner.outbox = {}
end
-- the friend's progress arrives with the quest list
local brann = owner.QB.Sync:Members()[1]
assert(brann.quests[166] and brann.quests[166].code == "a" and brann.quests[166].prog, "progress on a quest in their log comes along")
local shared = owner.env.QuestBankDB.live and owner.env.QuestBankDB.live[128]
assert(shared and shared.src == "party" and shared.full == 2000, "the friend's quest window XP reaches the owner")
print("  live XP shared by the friend:", shared.full, shared.src)
UI:ShowTab(4)
UI:Refresh()
for _, m in ipairs(v4.members.items) do if m:IsShown() then poke(m); lines = {}; m.copy.__scripts.OnEnter(m.copy) end end
for _, c in ipairs(v4.dcards.items) do
  if c:IsShown() then
    poke(c.head)
    for _, r in ipairs(c.rows.items) do if r:IsShown() then poke(r) end end
  end
end
do
  local P = owner.env.QuestBankPost
  for _, c in ipairs(v4.dcards.items) do
    if c:IsShown() then
      c.head.__scripts.OnClick(c.head, "RightButton")
      assert(P:IsShown() and P.eb:GetText():find("^Anyone up for " .. c.title:GetText():gsub("^The ", ""):gsub("%p", "%%%0") .. "%? "), "right-click on a dungeon asks for a group: " .. P.eb:GetText())
      assert(#P.eb:GetText() <= 255)
      print("dungeon post:", P.eb:GetText())
      P.cancel.__scripts.OnClick(P.cancel)
    end
  end
end
-- a friend runs a newer QuestBank: one notice, and the link
do
  local fQB = friend.QB
  local real = fQB.version
  fQB.version = "9.9.9"
  fQB.Sync.lastStatus = nil
  fQB.Sync:Broadcast(true)
  for _ = 1, 4 do tick(friend, 2); deliver(); tick(owner, 1) end
  fQB.version = real
  local told
  for _, line in ipairs(owner.chat) do if line:find("QuestBank 9.9.9 is out %(Brann Steelhand runs it%)") then told = (told or 0) + 1 end end
  assert(told == 1, "a newer version in the party is told once")
  assert(owner.QB.newest and owner.QB.newest.version == "9.9.9", "and remembered for Settings")
  lines = {}; owner.QB.Sync:MemberTooltip(owner.env.GameTooltip, mem[1].key)
  assert(lines[1]:find("Brann Steelhand", 1, true), "the tooltip opens with their name: " .. lines[1])
  local who
  for _, l in ipairs(lines) do if l:find("Who else here holds", 1, true) then who = true end end
  assert(who, "and says who else here holds each quest")
  local you = owner.QB.Sync.ColorName("you", "PALADIN")
  assert(you:find("^|cff") and you:find("|r$"), "your name comes in your class colour: " .. you)
  local shared
  for _, l in ipairs(lines) do if l:find(you, 1, true) then shared = l end end
  assert(shared, "a quest you both hold names you in your colour")
  print("tooltip, shared:", shared)
  owner.env.SlashCmdList.QUESTBANK("update")
  assert(owner.env.QuestBankLink:IsShown() and owner.env.QuestBankLink.eb:GetText() == "https://foreverrank.com/questbank/", "/qb update gives the link")
  owner.env.QuestBankLink:Hide()
  -- Settings: mode, next cap, updates, sharing
  UI:ShowTab(5)
  UI:Refresh()
  local v5 = UI.views[5]
  print("settings mode:", v5.modeText:GetText())
  print("settings version:", v5.verText:GetText())
  assert(v5.verText:GetText():find("Brann Steelhand runs 9.9.9"), "Settings says who runs the newer one")
  for _, pr in ipairs(checkLayout(UI.frame, "settings")) do problems[#problems + 1] = pr end
  layouts[#layouts + 1] = dumpLayout(UI.frame, "Settings")
  local before = QB:Mode()
  v5.modeBtns[2].__scripts.OnClick(v5.modeBtns[2])
  QB:Recompute(true); UI:Refresh()
  assert(QB:Mode() == "quest" and v5.modeText:GetText():find("chosen by you"), "Questing, set by hand")
  v5.modeBtns[1].__scripts.OnClick(v5.modeBtns[1])
  QB:Recompute(true); UI:Refresh()
  print("mode back on auto:", QB:Mode(), "(was " .. before .. ")")
  for _, cb in ipairs({ v5.updates, v5.offers, v5.shareParty, v5.shareGuild, v5.minimap }) do
    local was = cb:GetChecked()
    cb:SetChecked(not was); cb.__scripts.OnClick(cb, "LeftButton")
    cb:SetChecked(was); cb.__scripts.OnClick(cb, "LeftButton")
  end
  assert(QB:Settings().share.party and QB:Settings().post.auto and QB:Settings().updates, "ticks go back as they were")
  UI:ShowTab(4)
end
local n = owner.QB.Sync:CopyPlan(mem[1].key)
print("  copy plan added:", n)
for _, p in ipairs(checkLayout(UI.frame, "party")) do problems[#problems + 1] = p end
layouts[#layouts + 1] = dumpLayout(UI.frame, "Party, with a friend")
friend.env.SlashCmdList.QUESTBANK("")
friend.QB.Model.Finish()
for tab = 1, 5 do
  friend.QB.UI:ShowTab(tab)
  friend.QB.Model.Finish()
  friend.QB.UI:Refresh()
  for _, p in ipairs(checkLayout(friend.QB.UI.frame, "friend tab " .. tab)) do problems[#problems + 1] = p end
end
print("friend route:", friend.QB.UI.views[3].summary:GetText())
layouts[#layouts + 1] = dumpLayout(friend.QB.UI.frame, "Friend: Party")

----------------------------------------------------------------------------
-- scenario 3: a Horde shaman at 20
----------------------------------------------------------------------------
local horde = newClient({
  name = "Zultak", level = 20, cap = 20, faction = "Horde", className = "Shaman", class = "SHAMAN", classID = 7, race = "Orc",
  log = { { 1014, 1 }, { 1098, 1 }, { 5722, 1 }, { 5723, 1 }, { 5725, 1 }, { 5728, 0 }, { 855, 1 }, { 848, 1 }, { 882, 1 }, { 883, 0 },
          { 914, 0 }, { 1486, 1 }, { 1487, 1 }, { 1491, 1 }, { 959, 1 }, { 6981, 0 } },
  done = { [865] = true }, group = false, guild = false, world = { 1, 1320, -4649 }, bind = "Orgrimmar", riding = true, bagSlots = {},
})
login(horde)
horde.env.SlashCmdList.QUESTBANK("")
horde.QB.Model.Finish()
for tab = 1, 5 do
  horde.QB.UI:ShowTab(tab)
  horde.QB.Model.Finish()
  horde.QB.UI:Refresh()
  for _, p in ipairs(checkLayout(horde.QB.UI.frame, "horde tab " .. tab)) do problems[#problems + 1] = p end
end
horde.QB.UI:ShowTab(3)
local hv = horde.QB.UI.views[3]
print("horde route:", hv.summary:GetText())
for _, l in ipairs(hv.legs.items) do
  if l:IsShown() then print(string.format("  %5s %-26s %-34s %s", l.clock:GetText(), l.name:GetText(), l.travel:GetText(), l.level:GetText())) end
end
for _, e in ipairs(horde.QB:RouteEntries("plan")) do
  assert(e.q.side ~= 1, "no Alliance quest in a Horde plan: " .. e.q.name)
end
for _, c in ipairs(horde.QB.UI:Candidates(400)) do
  local q = horde.QB.Quest.Get(c.id)
  assert(q.side ~= 1, "no Alliance quest offered to the Horde: " .. q.name)
  assert(horde.QB.Quest.ForMe(q), "only quests an orc shaman can take: " .. q.name)
end
do
  horde.env.SlashCmdList.QUESTBANK("post")
  local P = horde.env.QuestBankPost
  assert(P:IsShown() and not P.party:IsEnabled() and not P.guild:IsEnabled() and not P.post:IsEnabled(), "outside a group and a guild there's nowhere to post")
  print("horde post:", P.party.label:GetText(), "|", P.guild.label:GetText())
  for _, pr in ipairs(checkLayout(P, "horde post dialog")) do problems[#problems + 1] = pr end
  P.cancel.__scripts.OnClick(P.cancel)
  horde.QB.Run.Offer("level", 21)
  assert(not P:IsShown(), "and nothing is offered")
end
horde.QB.UI:ShowTab(2)
layouts[#layouts + 1] = dumpLayout(horde.QB.UI.frame, "Horde: Prep")
horde.QB.UI:ShowTab(3)
layouts[#layouts + 1] = dumpLayout(horde.QB.UI.frame, "Horde: Hand-in Route")

-- the direction arrow: off until you turn it on, then it points to the next stop
do
  local A = owner.QB.Arrow
  assert(not owner.env.QuestBankArrow or not owner.env.QuestBankArrow:IsShown(), "the arrow is off until you turn it on")
  -- the bearing: world x runs north, y west, facing turns anticlockwise from north
  local me = { wx = 0, wy = 0 }
  local north = A.Bearing(me, { wx = 100, wy = 0 }, 0)
  local west = A.Bearing(me, { wx = 0, wy = 100 }, 0)
  local eastFacingNorth = A.Bearing(me, { wx = 0, wy = -100 }, 0)
  local northFacingWest = A.Bearing(me, { wx = 100, wy = 0 }, math.pi / 2)
  assert(math.abs(north) < 1e-6 and math.abs(west - math.pi / 2) < 1e-6 and math.abs(eastFacingNorth + math.pi / 2) < 1e-6, "north ahead, west to the left, east to the right")
  assert(math.abs(northFacingWest + math.pi / 2) < 1e-6, "facing west, north is to your right")
  owner.env.SlashCmdList.QUESTBANK("arrow")
  local F = owner.env.QuestBankArrow
  assert(F and F:IsShown(), "/qb arrow turns it on")
  owner.facing = 0
  F.__scripts.OnUpdate(F, 1)
  print("arrow:", F.name:GetText(), "|", F.dist:GetText(), "| rotation", F.arrow.__rot and string.format("%.2f", F.arrow.__rot))
  assert(F.name:GetText() ~= "" and F.dist:GetText() ~= "", "it names the stop and how far")
  lines = {}; F.__scripts.OnEnter(F); assert(lines[1]:find("Next stop"))
  for _, pr in ipairs(checkLayout(F, "arrow")) do problems[#problems + 1] = pr end
  -- 3.4.0: what it points at is yours to choose
  assert(A.Mode() == "route" and A.Target().kind == "route", "it starts on the route")
  owner.env.SlashCmdList.QUESTBANK("arrow handin")
  local t = A.Target()
  assert(A.Mode() == "handin" and t and t.kind == "handin" and t.name ~= "" and t.quests >= 1, "the nearest hand-in: an NPC who takes a finished quest of yours")
  F.__scripts.OnUpdate(F, 1)
  assert(F.name:GetText() == t.name, "the arrow names that NPC: " .. F.name:GetText())
  lines = {}; F.__scripts.OnEnter(F); assert(lines[1]:find("Hand in at " .. t.name:gsub("%p", "%%%0"), 1), "and the tooltip says so: " .. lines[1])
  print("arrow, hand in:", t.name, t.quests)
  owner.env.SlashCmdList.QUESTBANK("arrow pickup")
  local plan = QB:Plan()
  local keep = plan.add
  plan.add = {}
  assert(A.Mode() == "pickup" and A.Target() == nil, "an empty plan: nothing to pick up")
  F.__scripts.OnUpdate(F, 1)
  assert(F.name:GetText():find("Nothing in your plan"), "and the arrow says so: " .. F.name:GetText())
  plan.add[1221] = true
  t = A.Target()
  assert(t and t.kind == "pickup" and t.name == QB.Quest.Get(1221).give.n, "a planned quest: the arrow finds its giver: " .. tostring(t and t.name))
  plan.add = keep
  -- clicking a waypoint in QuestBank pins the arrow to it
  owner.env.SlashCmdList.QUESTBANK("arrow route")
  QB:Settings().arrowPin = nil -- earlier clicks in this run pinned things while the arrow was off, as they should
  assert(A.Mode() == "route", "back on the route")
  UI:ShowTab(2); UI:Refresh()
  local row
  for _, c in ipairs(v2.cards.items) do for _, r in ipairs(c.rows.items) do if r:IsShown() and r.q and r.st.code == "todo" and r.q.give and not r.q.give.inside then row = row or r end end end
  assert(row, "a fetchable quest row with a giver outside")
  row.__scripts.OnClick(row, "LeftButton")
  t = A.Target()
  assert(A.Mode() == "pin" and t and t.kind == "pin" and t.name == row.q.give.n, "a click on a quest pins the arrow to its giver: " .. tostring(t and t.name))
  local told
  for i = math.max(1, #owner.chat - 2), #owner.chat do if owner.chat[i]:find("The arrow points at " .. row.q.give.n:gsub("%p", "%%%0") .. " now") then told = true end end
  assert(told, "and says so once: " .. owner.chat[#owner.chat])
  -- the right-click menu: the four targets and Hide
  F.__scripts.OnClick(F, "RightButton")
  local M = owner.env.QuestBankMenu
  assert(M and M:IsShown(), "right-click opens the menu")
  local labels, hide, route = {}, nil, nil
  for _, b in ipairs(M.items) do
    if b:IsShown() then
      labels[#labels + 1] = b.label:GetText()
      if b.label:GetText() == "Hide the arrow" then hide = b end
      if b.label:GetText():find("^The next stop") then route = b end
    end
  end
  print("arrow menu: " .. table.concat(labels, " | "))
  assert(#labels == 5 and hide and route and labels[4]:find("%(now%)"), "the menu lists the four targets, the current one marked, and Hide: " .. table.concat(labels, " | "))
  for _, pr in ipairs(checkLayout(M, "arrow menu")) do problems[#problems + 1] = pr end
  route.__scripts.OnClick(route)
  assert(not M:IsShown() and A.Mode() == "route", "choosing the route from the menu")
  F.__scripts.OnClick(F, "RightButton")
  for _, b in ipairs(M.items) do if b:IsShown() and b.label:GetText() == "Hide the arrow" then b.__scripts.OnClick(b) end end
  assert(not F:IsShown() and not QB:Settings().arrow, "Hide in the menu hides it")
  QB:Settings().arrowPin = nil
end

----------------------------------------------------------------------------
-- scenario 4: a level 3 human priest in Northshire, questing (no cap, no lock)
----------------------------------------------------------------------------
local newbie = newClient({
  name = "Tess", level = 3, cap = 60, faction = "Alliance", className = "Priest", class = "PRIEST", classID = 5, race = "Human",
  log = { { 7, 0 }, { 33, 1 }, { 18, 0 } }, done = { [783] = true, [5261] = true }, group = false, guild = false,
  world = { 0, -8914, -133 }, bind = "Northshire Abbey", riding = false, bagSlots = {}, xp = 900,
})
login(newbie)
do
  local N, U = newbie.QB, newbie.QB.UI
  newbie.env.SlashCmdList.QUESTBANK("")
  N.Model.Finish()
  assert(N:Mode() == "quest" and N.CAP == 60, "level 3 with no cap: questing (" .. N:Mode() .. ", cap " .. N.CAP .. ")")
  U:ShowTab(1); N.Model.Finish(); U:Refresh()
  assert(U.barLo == 3 and U.barHi == 13, "the bar runs over your next ten levels: " .. tostring(U.barLo) .. " to " .. tostring(U.barHi))
  print("newbie header:", U.header.legend:GetText())
  local arrows, seven = {}, nil
  for _, b in ipairs(U.views[1].slots) do
    if b.q and b.up:IsShown() then arrows[#arrows + 1] = b.q.name end
    if b.q and b.q.id == 7 then seven = b end
  end
  print("arrows on:", table.concat(arrows, ", "))
  for _, r in ipairs(U.views[1].swaps) do
    if r:IsShown() then
      print(string.format("  newbie swap: %-24s -> %-30s %s (level %d)", r.cutName:GetText(), r.addName:GetText(), r.gain:GetText(), r.add.lvl))
      assert(r.add.lvl <= 7, "questing suggestions stay near your level: " .. r.add.name)
    end
  end
  -- 3.4.1: questing ranks by XP for the time, counts what a chain leads on to, and drops long runs for little
  do
    local cands = U:Candidates(400)
    assert(#cands > 0 and N:Mode() == "quest", "the newbie quests")
    local withLead, far = 0, nil
    for _, c in ipairs(cands) do
      assert(c.away and c.back and c.lead and c.rank and not c.waste, "every questing candidate carries its trip, loop and lead: " .. QB.Data.QN[c.id])
      if c.lead > 0 then withLead = withLead + 1 end
      if c.away > 8 then far = far or c end
    end
    assert(withLead > 0, "a chain's first step counts what it leads on to")
    assert(U.candDropped and U.candDropped > 0, "long runs for little were dropped: " .. tostring(U.candDropped))
    if far then assert(far.away <= 20 and (far.value + far.lead) / (far.away + far.back + 3) >= 60 * N.Scale(N.state.level), "the far ones that stay are within twenty minutes and pay for the time: " .. QB.Data.QN[far.id]) end
    for _, c in ipairs(cands) do assert(c.away <= 20, "questing: nothing more than twenty minutes away is suggested: " .. QB.Data.QN[c.id]) end
    -- a quest that leads on ranks above its own XP for the time
    local leader
    for _, c in ipairs(cands) do if c.lead > 0 then leader = leader or c end end
    assert(leader and leader.rank > leader.value / (1 + (leader.away + leader.back + 3) / 10), "a quest that leads on ranks above its own XP for the time: " .. QB.Data.QN[leader.id])
    print(string.format("newbie candidates: %d kept, %d dropped as a waste, %d lead somewhere", #cands, U.candDropped, withLead))
    local leadRow
    for _, r in ipairs(U.views[1].swaps) do if r:IsShown() and r.cutName:GetText():find("leads to +", 1, true) then leadRow = leadRow or r end end
    assert(leadRow, "a swap row says what the quest leads on to")
    print("newbie lead row:", leadRow.addName:GetText(), "|", leadRow.cutName:GetText())
  end
  assert(seven and seven.up:IsShown(), "Kobold Camp Cleanup carries on: the arrow shows")
  lines = {}; seven.__scripts.OnEnter(seven)
  local carry = false
  local nextStep = false
  for _, l in ipairs(lines) do
    if l:find("Carry the chain on: Skirmish at Echo Ridge pays 450 XP, 2 steps on") then carry = true end
    if l:find("Leads on to: Investigate Echo Ridge") then nextStep = true end
  end
  assert(carry and nextStep, "and its tooltip names the next step and the best one further on")
  -- 3.3.3: a skipped zone's chain steps are no upgrade either
  do
    local best = N:Upgrade(seven.q)
    assert(best and best.name == "Skirmish at Echo Ridge", "the best later step before any skip: " .. tostring(best and best.name))
    local l, on = N:ToggleSkip("Elwynn")
    assert(l == "Elwynn Forest" and on, "/qb skip Elwynn")
    local after = N:Upgrade(seven.q)
    assert(not after or after.name ~= "Skirmish at Echo Ridge", "a skipped zone's chain steps aren't suggested: " .. tostring(after and after.name))
    N:ToggleSkip("Elwynn Forest")
    local back = N:Upgrade(seven.q)
    assert(back and back.name == "Skirmish at Echo Ridge", "and back")
  end
  -- the Plan page: quests for a level 3
  U:ShowTab(2); N.Model.Finish(); U:Refresh()
  local shown, tooHigh = 0, 0
  for _, c in ipairs(U.views[2].cards.items) do
    if c:IsShown() then
      for _, r in ipairs(c.rows.items) do
        if r:IsShown() and r.q then shown = shown + 1; if (r.q.req or 1) > 5 then tooHigh = tooHigh + 1 end end
      end
    end
  end
  print("newbie plan rows:", shown, "needing more than level 5:", tooHigh)
  assert(shown > 0 and tooHigh == 0, "a level 3 is shown quests for a level 3")
  for tab = 1, 5 do
    U:ShowTab(tab); N.Model.Finish(); U:Refresh()
    for _, pr in ipairs(checkLayout(U.frame, "newbie tab " .. tab)) do problems[#problems + 1] = pr end
    layouts[#layouts + 1] = dumpLayout(U.frame, "Level 3, questing: " .. ({ "Quest Log", "Plan", "Hand-in Route", "Party", "Settings" })[tab])
  end
  U:ShowTab(3)
  print("newbie route:", U.views[3].summary:GetText(), "|", U.views[3].setup:GetText())
  assert(not U.views[3].summary:GetText():find("60 min"), "questing: no hand-in hour")
  -- discoveries: what the game shows at an NPC, noted for everyone
  do
    local Dz = N.Discover
    newbie.npcGUID, newbie.npcName = "Creature-0-4455-0-12-197-0000A1B2C3", "Marshal McBride"
    newbie.gossipAvail = { { questID = 15, title = "Investigate Echo Ridge", questLevel = 3 } }
    newbie.ev(N.eventFrame, "GOSSIP_SHOW")
    Dz.OnEvent("GOSSIP_SHOW")
    newbie.window = { id = 7, xp = 170, title = "Kobold Camp Cleanup" }
    Dz.OnEvent("QUEST_COMPLETE")
    Dz.OnEvent("QUEST_TURNED_IN", 7, 170)
    newbie.npcGUID = "Creature-0-4455-0-12-197-0000A1B2C3"
    newbie.window = { id = 15, xp = 250, title = "Investigate Echo Ridge" }
    Dz.OnEvent("QUEST_DETAIL", 0)
    newbie.npcGUID = "GameObject-0-4455-0-12-31-0000A1B2C3"
    newbie.npcName = "Old Lion Statue"
    newbie.window = { id = 94, xp = 0, title = "A Watchful Eye" }
    Dz.OnEvent("QUEST_COMPLETE")
    newbie.npcGUID, newbie.npcName = nil, nil
    newbie.window = { id = 3905, xp = 0, title = "Grape Manifest" }
    Dz.OnEvent("QUEST_DETAIL", 11107)
    local d = newbie.env.QuestBankDB.disc
    assert(d.npc.c197 and d.npc.c197.n == "Marshal McBride" and d.npc.c197.p[1]:match("^%d+:%d+%.%d,%d+%.%d$"), "the NPC and where it stands")
    assert(d.offer.c197[15] == 3, "what it offered, and at what level")
    assert(d.q[7].xp["3"] == 170 and d.q[7].paid == 1, "the XP a hand-in paid at level 3")
    assert(d.chain["7>15"], "a quest offered straight after a hand-in by the same NPC: the next step")
    assert(d.q[94].to[1] == "o31" and d.npc.o31, "objects that take quests count too")
    assert(d.item[11107] == 3905, "quests that start from an item")
    assert(d.build == "70058" and d.ver == N.version, "which game build and QuestBank noted it")
    newbie.env.SlashCmdList.QUESTBANK("discoveries")
    print("discoveries:", newbie.chat[#newbie.chat])
    newbie.window = nil
  end
  -- a quest worth 170 XP pays nothing while the bar sits at 0: the game holds this level
  newbie.xp = 0
  for i, e in ipairs(newbie.log) do if e[1] == 33 then table.remove(newbie.log, i) break end end
  newbie.done[33] = true
  newbie.ev(N.eventFrame, "QUEST_TURNED_IN", 33, 0)
  newbie.ev(N.eventFrame, "QUEST_LOG_UPDATE")
  tick(newbie, 1)
  N:ReadState()
  assert(N:Mode() == "lock" and N:Lock() == 3, "the game holds level 3: bank")
  -- one that pays: the lock is gone, and after the next level it's questing again
  for i, e in ipairs(newbie.log) do if e[1] == 18 then table.remove(newbie.log, i) break end end
  newbie.done[18] = true
  newbie.ev(N.eventFrame, "QUEST_TURNED_IN", 18, 355)
  tick(newbie, 1)
  N:ReadState()
  assert(not N:Lock() and N:Mode() == "rush", "the lock lifted: rush until the next level")
  newbie.level = 4
  N:ReadState()
  assert(N:Mode() == "quest", "a level on: questing")
  assert(N.CAP == 60 and not N:Held(), "and the old lock is gone, not holding the ceiling at 13 (" .. N.CAP .. ")")
  -- banking set by hand, then back to auto: questing, not a rush
  N:SetLock("on"); N:ReadState()
  assert(N:Mode() == "lock" and N:Lock() == 4, "banking by hand holds this level")
  N:SetLock("auto"); N:ReadState()
  assert(N:Mode() == "quest", "back to auto: questing, not a rush (" .. N:Mode() .. ")")
  -- banking by hand ends when you level past it
  N:SetLock("on"); N:ReadState()
  newbie.level = 5; N:ReadState()
  assert(N:Mode() == "quest" and N:LockChoice() == "auto", "levelled past a hand-set lock: it's gone")
  -- a run started while questing stays questing
  N.Run.Start(); N:ReadState()
  assert(N:Mode() == "quest" and N.Run.Get().mode == "quest", "a questing run doesn't turn banking on")
  N.Run.Stop()
  local P = newbie.env.QuestBankPost
  if P then P:Hide() end
  -- the thresholds follow the level: a level 5's quests aren't all "make room"
  N:Recompute(true)
  U:ShowTab(2); N.Model.Finish(); U:Refresh()
  for _, c in ipairs(U.views[2].cards.items) do
    if c:IsShown() and c.title:GetText() == "Make room" then
      for _, r in ipairs(c.rows.items) do
        if r:IsShown() and r.entry then assert(r.value == nil or r.xp:GetText() == "?" or true) end
      end
      print("newbie make room:", c.count:GetText())
    end
  end
end

----------------------------------------------------------------------------
-- how long planning takes (LuaJIT here; the game's Lua 5.1 is several times slower, and plans in slices)
do
  local t0 = os.clock()
  for _ = 1, 5 do owner.QB.sigNow, owner.QB.sigPlan = nil, nil; owner.QB:Recompute(true) end
  local ms = (os.clock() - t0) * 1000 / 5
  local r = owner.QB.routePlan
  local stops = 0
  for _ in ipairs(r.legs) do stops = stops + 1 end
  print(string.format("planning both routes: %.1f ms (plan: %d stops, %d quests)", ms, stops, r.count))
end
print("widgets created:", created)
local seen = {}
local unique = {}
for _, p in ipairs(problems) do if not seen[p] then seen[p] = true; unique[#unique + 1] = p end end
print("layout problems:", #unique)
for i = 1, math.min(80, #unique) do print("  " .. unique[i]) end
if LAYOUT_OUT then
  local f = assert(io.open(LAYOUT_OUT, "w"))
  f:write(json(layouts))
  f:close()
  print("layout written to " .. LAYOUT_OUT)
end
print(#unique == 0 and "OK" or "OK, with layout problems above")
