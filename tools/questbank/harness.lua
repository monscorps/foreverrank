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
SetAutoFocus HighlightText SetFocus ClearFocus SetMultiLine SetChecked GetChecked SetMaxLetters HasFocus IsEnabled SetRotation RegisterUnitEvent
SetAtlas SetPassThroughButtons SetScale]])
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
        elseif k == "SetAtlas" then self.__tex = "atlas:" .. tostring(a[1]); self.__atlas = a[1]; self.__color = nil
        elseif k == "SetScale" then self.__scale = a[1]
        elseif k == "SetFrameLevel" then self.__frameLevel = a[1]
        elseif k == "EnableMouse" then self.__mouse = a[1] and true or false
        -- protected on Forever, with combat restrictions: an addon calling it in combat is blocked (ADDON_ACTION_BLOCKED)
        elseif k == "SetPassThroughButtons" then
          if self.__client and self.__client.combat then error("ADDON_ACTION_BLOCKED: SetPassThroughButtons in combat", 2) end
          self.__passThrough = { ... }
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
  return function(_, ...)
    if k == "SetItemByID" then lines[#lines + 1] = "ITEM:" .. tostring((...)) return end
    if k == "AddLine" or k == "AddDoubleLine" then
      local parts = {}
      for i = 1, select("#", ...) do local v = select(i, ...); if type(v) == "string" then parts[#parts + 1] = v end end
      lines[#lines + 1] = table.concat(parts, " | ")
    end
  end
end })
BASE.date = os.date
BASE.time = os.time
BASE.debugprofilestop = function() return os.clock() * 1000 end
BASE.GetCursorPosition = function() return 600, 500 end
BASE.SetPortraitTexture = function() end
BASE.geterrorhandler = function() return error end
BASE.UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m = m, x = x, y = y } end }
-- the game's super-tracking: QuestBank never touches it (SUPER_TRACKING_CHANGED and the waypoint's listeners would run
-- as QuestBank). Any use of any of it errors here
BASE.C_SuperTrack = setmetatable({}, { __index = function(_, k)
  return function() error("QuestBank called C_SuperTrack." .. tostring(k) .. ": the game's tracking is the player's own", 2) end
end })
BASE.CreateVector2D = function(x, y) return { x = x, y = y } end
BASE.Ambiguate = function(name) return name end
BASE.CLASS_ICON_TCOORDS = { PALADIN = { 0, 0.25, 0.5, 0.75 }, WARRIOR = { 0, 0.25, 0, 0.25 }, SHAMAN = { 0.25, 0.49, 0.25, 0.5 } }
BASE.RAID_CLASS_COLORS = { PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, SHAMAN = { r = 0, g = 0.44, b = 0.87 } }
BASE.CreateFromMixins = function(...)
  local t = {}
  for i = 1, select("#", ...) do for k, v in pairs(select(i, ...)) do t[k] = v end end
  return t
end
-- (QuestBank no longer uses the map canvas's pins, so no MapCanvasPinMixin here: a use of it fails)
BASE.MapCanvasDataProviderMixin = { GetMap = function(self) return self.owningMap end }

SECRET_MT = {
  __index = function(t, k) error(string.format("attempt to index a secret %s value", rawget(t, "__kind")), 2) end,
  __lt = function() error("attempt to compare a secret value", 2) end,
  __le = function() error("attempt to compare a secret value", 2) end,
  __add = function() error("attempt to perform arithmetic on a secret value", 2) end,
  __concat = function() error("attempt to concatenate a secret value", 2) end,
  __tostring = function() return "<secret>" end,
}
SECRET = {
  str = function() return setmetatable({ __kind = "string" }, SECRET_MT) end,
  num = function() return setmetatable({ __kind = "number" }, SECRET_MT) end,
  bool = function() return setmetatable({ __kind = "boolean" }, SECRET_MT) end,
}

-- Blizzard's chat globals: written from QuestBank's code they carry its taint into the chat box (ChatFrameUtil.OpenChat
-- and ActivateChat write them; QuestBank never calls those). A write errors here
local BLIZZARD_ONLY = { ACTIVE_CHAT_EDIT_BOX = true, LAST_ACTIVE_CHAT_EDIT_BOX = true, CHAT_FOCUS_OVERRIDE = true }

local function newClient(o)
  local env = setmetatable({}, { __index = BASE, __newindex = function(t, k, v)
    if BLIZZARD_ONLY[k] then error("QuestBank wrote the game's " .. tostring(k), 2) end
    rawset(t, k, v)
  end })
  env._G = env
  local c = { env = env, o = o, timers = {}, clock = 1000, outbox = {}, pins = {}, chat = {}, frames = {}, QB = {} }
  env.UIParent = newObj("Frame"); env.UIParent:SetSize(1600, 1000); env.UIParent.__points = {}
  env.UIParent.__root = true
  env.Minimap = newObj("Frame"); env.Minimap:SetSize(140, 140)
  env.UISpecialFrames = {}
  env.SlashCmdList = {}
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) c.chat[#c.chat + 1] = m end }
  -- Pins.xml: each template's child regions, as the game builds a frame from it
  local xml = io.open(HERE .. "/QuestBank/Pins.xml"):read("*a"):gsub("<!%-%-.-%-%->", "")
  local templates = {}
  for attrs, body in xml:gmatch("<Frame (name=\"[^\"]+\"[^>]*)>(.-)</Frame>") do
    local t = { name = attrs:match('name="([^"]+)"'), mixin = attrs:match('mixin="([^"]+)"'), scripts = {}, regions = {} }
    for tag in body:gmatch("<(On%a+)") do t.scripts[tag] = true end
    for kind, key in body:gmatch("<(%a+) parentKey=\"(%a+)\"") do t.regions[key] = kind end
    templates[t.name] = t
  end
  c.templates = templates
  env.CreateFrame = function(kind, name, parent, template)
    local f = newObj(kind, template, parent)
    f.__name = name
    f.__client = c
    if name then env[name] = f end
    local t = template and templates[template]
    if template and template:find("^QuestBank") then
      assert(t, "a template Pins.xml defines: " .. template)
      assert(not t.mixin and not next(t.scripts), "QuestBank's map templates carry no mixin or scripts (never the canvas's pins): " .. template)
      for key, rk in pairs(t.regions) do f[key] = newObj(rk, nil, f) end
    end
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
  -- Midnight's secret values, as the Forever client hands them out: type() says "string" or "number", any use
  -- errors, and issecretvalue tells. SECRET.str() / SECRET.num() make one.
  env.issecretvalue = function(v) return getmetatable(v) == SECRET_MT end
  env.type = function(v) if getmetatable(v) == SECRET_MT then return rawget(v, "__kind") end return type(v) end
  env.UnitFullName = function() return o.name, "ForeverNormal" end
  -- the UI's quest-log constants as Forever 1.60.1 (70235) sets them, from the log's size (40; older builds said 25),
  -- and the escort prompt's refresher, which QuestBank never calls: its Yes would be set as QuestBank
  env.MAX_QUESTS, env.MAX_QUESTLOG_QUESTS = 40, 40
  env.UpdateQuestAcceptLogFullDialog = function() error("QuestBank called UpdateQuestAcceptLogFullDialog: the escort prompt's Yes would be set as QuestBank", 2) end
  -- Ctrl, for the game's own map pin (Ctrl+click on the map)
  env.IsControlKeyDown = function() return c.ctrl or false end
  env.WaypointLocationDataProviderMixin = {}
  env.GetTitleText = function() return c.window and c.window.title or "" end
  env.GetSuggestedGroupNum = function() return 0 end
  env.GetBuildInfo = function() return "1.60.1", "70170", "Oct 1 2026", 16001 end
  -- the AddOns list: c.addons[name] = { version, loaded, enabled (0/1/2), reason }; absent = not installed
  env.C_AddOns = {
    DoesAddOnExist = function(n) return (c.addons or {})[n] ~= nil end,
    GetAddOnInfo = function(n)
      local a = (c.addons or {})[n]
      if not a then return n, nil, nil, false, "MISSING", "INSECURE" end
      return n, n, "", a.reason == nil, a.reason, "INSECURE"
    end,
    IsAddOnLoaded = function(n) local a = (c.addons or {})[n]; local l = a and a.loaded or false; return l, l end,
    GetAddOnEnableState = function(n, who) local a = (c.addons or {})[n]; return a and (a.enabled or 2) or 0 end,
    GetAddOnMetadata = function(n, key) local a = (c.addons or {})[n]; return a and key == "Version" and a.version or nil end,
    GetAddOnInterfaceVersion = function(n) return (c.addons or {})[n] and 16001 or 0 end,
    IsAddOnLoadable = function(n, who) local a = (c.addons or {})[n]; if not a then return false, "MISSING" end; return a.reason == nil, a.reason end,
    DoesAddOnHaveLoadError = function(n) local a = (c.addons or {})[n]; return a and a.loadError or false end,
    IsAddonVersionCheckEnabled = function() return true end,
  }
  -- the player's helpful auras: c.auras = { spellId, ... }
  env.C_UnitAuras = {
    GetAuraDataByIndex = function(unit, i, filter) local a = (c.auras or {})[i]; return a and { spellId = a } or nil end,
  }
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
  env.GetNumQuestChoices = function() return (c.window and c.window.rc and #c.window.rc) or c.choices or 0 end
  -- the window's reward items: window.rc = choose one, window.rr = always given (ids); window.unloaded = a link not ready yet
  env.GetNumQuestRewards = function() return (c.window and c.window.rr and #c.window.rr) or 0 end
  env.GetQuestItemLink = function(kind, i)
    local list = c.window and (kind == "choice" and c.window.rc or c.window.rr)
    local id = list and list[i]
    if not id or (c.window.unloaded and c.window.unloaded[id]) then return nil end
    return "|cff1eff00|Hitem:" .. id .. "::::::::20:::::::|h[Item " .. id .. "]|h|r"
  end
  env.GetQuestItemInfo = function(kind, i) return nil end
  -- opening the chat box from QuestBank's code writes the game's chat globals and the box's fields as QuestBank:
  -- never done (the link goes into a box you have open, or into the chat window for you to Shift-click)
  env.ChatFrame_OpenChat = function() error("QuestBank opened the chat box (ChatFrame_OpenChat)", 2) end
  env.IsQuestCompletable = function() return c.completable and true or false end
  env.QuestGetAutoAccept = function() return false end
  -- the escort prompt is the game's: QuestBank neither answers it (no click behind the call) nor hides it (the popup
  -- system's list of popups on screen would be written as QuestBank)
  env.ConfirmAcceptQuest = function() error("QuestBank called ConfirmAcceptQuest: the escort prompt is the player's to answer", 2) end
  env.StaticPopup_Hide = function() error("QuestBank hid a Blizzard popup (StaticPopup_Hide)", 2) end
  env.StaticPopup_Show = function() error("QuestBank showed a Blizzard popup (StaticPopup_Show)", 2) end
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
  -- the chat box: open or not (c.chatOpen; c.chatFocus = false: open but not typed in, as the IM style leaves it),
  -- and what a shift-click put in it
  c.chatLinks = {}
  c.chatBox = { HasFocus = function() return c.chatFocus ~= false end }
  env.ChatEdit_GetActiveWindow = function() return c.chatOpen and c.chatBox or nil end
  env.ChatEdit_InsertLink = function(link) c.chatLinks[#c.chatLinks + 1] = link; return true end
  env.GetQuestLink = function(id) for _, e in ipairs(c.log) do if e[1] == id then return "|cffffff00|Hquest:" .. id .. ":20|h[Quest " .. id .. "]|h|r" end end end
  env.GetItemInfo = function(id) return "Item " .. id, "|cffffffff|Hitem:" .. id .. "::::::::20:::::::|h[Item " .. id .. "]|h|r" end
  env.UnitXP = function() return c.xp or 0 end
  env.UnitXPMax = function() return 23200 end
  env.UnitClass = function() return o.className, o.class, o.classID end
  env.UnitRace = function() return o.race, o.race end
  env.UnitFactionGroup = function() return o.faction end
  env.GetNormalizedRealmName = function() return c.realmGone and nil or "ForeverNormal" end
  env.GetRealmName = function() return "Forever Normal" end
  env.IsInGroup = function() return o.group or false end
  env.IsInRaid = function() return false end
  env.IsInGuild = function() return o.guild or false end
  -- chat channels: the version notice joins one quiet channel; GetChannelName answers 0 until joined
  c.channels = {}
  env.JoinTemporaryChannel = function(name) c.channels[name] = true return 5, name end
  env.LeaveChannelByName = function(name) c.channels[name] = nil end
  env.GetChannelName = function(name) return c.channels[name] and 5 or 0, c.channels[name] and name or nil end
  env.ChatFrame_RemoveChannel = function() end
  env.ChatFrame_AddMessageEventFilter = function(ev, fn) c.chatFilters = c.chatFilters or {}; c.chatFilters[#c.chatFilters + 1] = { ev, fn } end
  env.GetQuestID = function() return c.window and c.window.id or 0 end
  env.GetRewardXP = function() return c.window and c.window.xp or 0 end
  -- the Classic way: the selected entry's XP, whatever ID is passed
  env.GetQuestLogSelection = function() return c.selected or 0 end
  env.SelectQuestLogEntry = function(i) c.selected = i end
  -- the quest log's XP per quest (by id, no selecting); a client may hand back one value for every id: c.logXP = { [id] = xp }
  env.GetQuestLogRewardXP = function(id) return c.logXP and c.logXP[id] or 0 end
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
    -- the whole answer, for the item notes (Game.lua): c.itemClass[id] (4, armor, by default), c.itemQuality[id],
    -- c.itemName[id] (a secret one, say), c.unloaded[id] = not in the client's cache yet
    GetItemInfo = function(id)
      if c.unloaded[id] then return nil end
      return c.itemName[id] or ("Item " .. id), "|cffffffff|Hitem:" .. id .. "::::::::20:::::::|h[Item " .. id .. "]|h|r", c.itemQuality[id],
        27, 22, "Armor", "Cloth", 1, "INVTYPE_CHEST", 133328, 815, c.itemClass[id] or 4, 1, 1, 0, nil
    end,
    RequestLoadItemDataByID = function(id) c.loadRequests[#c.loadRequests + 1] = id end,
  }
  c.itemClass, c.itemQuality, c.itemName, c.unloaded, c.loadRequests = {}, {}, {}, {}, {}
  -- the modern spellbook (ported from tools/foreverprobe/harness.lua): a General line and a class line;
  -- o.book = { { spellID, itemType (1 learned, 2 not yet), isOffSpec }, ... }, the first two in General
  env.Enum = {
    SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
    SpellBookSpellBank = { Player = 0, Pet = 1 },
    TooltipDataType = { Item = 0, Spell = 1, Unit = 2 },
    TooltipDataLineType = { None = 0, Blank = 1, NestedBlock = 2, Separator = 3 },
  }
  c.book = o.book or { { spellID = 6603, itemType = 1 }, { spellID = 20598, itemType = 1 }, { spellID = 635, itemType = 1 }, { spellID = 879, itemType = 2 } }
  env.C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 2 end,
    GetSpellBookSkillLineInfo = function(i)
      if i == 1 then return { name = "General", itemIndexOffset = 0, numSpellBookItems = 2 } end
      if i == 2 then return { name = o.className, itemIndexOffset = 2, numSpellBookItems = #c.book - 2 } end
    end,
    GetSpellBookItemInfo = function(slot, bank)
      if bank ~= 0 and bank ~= 1 then error("bad argument #2 to 'GetSpellBookItemInfo' (Enum.SpellBookSpellBank expected)", 2) end
      return c.book[slot]
    end,
  }
  -- what the character wears: o.gear[slot] = item id
  env.GetInventoryItemID = function(unit, slot) return unit == "player" and (o.gear or {})[slot] or nil end
  -- item tooltips: every post-call hook is kept in c.tipHooks; c.tipLines[id] replaces an item's lines
  c.tipHooks, c.tipLines = {}, {}
  env.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) if kind == 0 then c.tipHooks[#c.tipHooks + 1] = fn end end }
  env.RETRIEVING_ITEM_INFO = "Retrieving item information"
  env.C_TooltipInfo = {
    GetItemByID = function(id)
      if c.tipLines[id] then return { id = id, lines = c.tipLines[id] } end
      return { id = id, lines = { { leftText = "Item " .. id }, { leftText = "Binds when picked up" }, { leftText = "Chest", rightText = "Cloth" },
        { leftText = "39 Armor" }, { leftText = "+5 Stamina" }, { leftText = "Item Level 27" }, { leftText = "Requires Level 22" } } }
    end,
  }
  env.GetLocale = function() return c.locale or "enUS" end
  -- the loot window and a vendor's wares: c.loot = { id, ... }, c.merchant = { id, ... }
  c.loot, c.merchant = {}, {}
  env.GetNumLootItems = function() return #c.loot end
  env.GetLootSlotLink = function(i) local id = c.loot[i]; return id and ("|cff1eff00|Hitem:" .. id .. "::::::::12:::::::|h[Item " .. id .. "]|h|r") or nil end
  env.GetMerchantNumItems = function() return #c.merchant end
  env.GetMerchantItemID = function(i) return c.merchant[i] end
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
    -- c.objectives[id] = the game's lines for one quest; every other quest has one generic line
    GetQuestObjectives = function(id) return (c.objectives or {})[id] or { { text = "thing", finished = false, numFulfilled = 3, numRequired = 10 } } end,
    -- the objective tracker: the game tells the tracker, the quest log and the map's quest pins inside these calls
    -- (QUEST_WATCH_LIST_CHANGED), so they would redraw as QuestBank. QuestBank never calls them
    GetQuestWatchType = function(id) return (c.watched or {})[id] and 0 or nil end,
    AddQuestWatch = function() error("QuestBank called C_QuestLog.AddQuestWatch: the tracker would redraw as QuestBank", 2) end,
    RemoveQuestWatch = function() error("QuestBank called C_QuestLog.RemoveQuestWatch: the tracker would redraw as QuestBank", 2) end,
    GetAllCompletedQuestIDs = function() local t = {} for k, v in pairs(c.done) do if v then t[#t + 1] = k end end return t end,
    GetLogIndexForQuestID = function(id) for i, e in ipairs(c.log) do if e[1] == id then return i + 2 end end end,
  }
  env.C_Map = {
    GetBestMapForUnit = function() return o.map or 1453 end,
    -- c.noPins[m]: a map the game has no pins for (an instance's)
    CanSetUserWaypointOnMap = function(m) return not (c.noPins or {})[m] end,
    -- the game's waypoint: set only by Blizzard's own code (c.blizzard, the player's click on a map-pin link, below).
    -- From QuestBank's code it errors: USER_WAYPOINT_UPDATED runs inside the call, and the map's tracking-pin button
    -- hears it map open or not and hands its state to the waypoint provider, which keeps it, as QuestBank
    SetUserWaypoint = function(p)
      if not c.blizzard then error("QuestBank called C_Map.SetUserWaypoint: the game's waypoint listeners would run as QuestBank", 2) end
      c.pins[#c.pins + 1] = p
      return true
    end,
    ClearUserWaypoint = function()
      if not c.blizzard then error("QuestBank called C_Map.ClearUserWaypoint: the game's waypoint listeners would run as QuestBank", 2) end
    end,
    -- what the game reads from a map-pin link: |Hworldmap:<uiMapID>:<x*10000>:<y*10000>|h
    GetUserWaypointFromHyperlink = function(link)
      local m, x, y = tostring(link):match("worldmap:(%d+):(%d+):(%d+)")
      if not m then return nil end
      return env.UiMapPoint.CreateFromCoordinates(tonumber(m), tonumber(x) / 10000, tonumber(y) / 10000)
    end,
    GetPlayerMapPosition = function() return { x = 0.66, y = 0.62, GetXY = function(self) return self.x, self.y end } end,
    GetWorldPosFromMapPos = function() return o.world[1], { x = o.world[2], y = o.world[3], GetXY = function(self) return self.x, self.y end } end,
    GetMapRectOnMap = function() return 0.4, 0.6, 0.4, 0.6 end,
    -- zones and cities 3, continents 2, the world 1 (Enum.UIMapType); c.mapTypes overrides one
    GetMapInfo = function(id)
      local kind = (c.mapTypes or {})[id] or ({ [947] = 1, [1414] = 2, [1415] = 2 })[id] or 3
      return { mapID = id, mapType = kind, parentMapID = kind == 3 and 1415 or 947, name = "Map " .. id }
    end,
  }
  env.C_Texture = { GetAtlasInfo = function(name) if (c.noAtlas or {})[name] then return nil end return { file = 1, width = 32, height = 32 } end }
  env.InCombatLockdown = function() return c.combat or false end
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
  -- the world map. QuestBank's layers are data providers that the map tells of a refresh (its OnShow), a new map and
  -- a new scale or size; they draw QuestBank's own frames on the canvas. The canvas's own pin calls write into the
  -- map's tables (pin pools, the scroll container's scale and scroll, the pins to nudge) and so error here: QuestBank's
  -- code must never make them. map.id is the map on show (Stormwind unless a test sets it), map.shown whether it is
  -- open, map.scale and map.zoom the canvas's scale and zoom (0 zoomed out, 1 all the way in)
  -- map.WorldMapTrackingPinButton.isActive: the map's pin button, on (a click on the map places the game's pin)
  local map = { shown = true, providers = {}, id = 1453, scale = 1, zoom = 0, WorldMapTrackingPinButton = { isActive = false } }
  local canvas = newObj("Frame"); canvas:SetSize(1002, 668)
  env.WorldMapFrame = {
    AddDataProvider = function(_, p) p.owningMap = map; map.providers[#map.providers + 1] = p end,
    IsShown = function() return map.shown end,
    IsVisible = function() return map.shown end,
    GetCanvas = function() return canvas end,
    -- QuestBank hooks nothing of the map's: its layers hear of the map shutting as its data providers
    HookScript = function(_, script) error("QuestBank hooked the world map's " .. tostring(script), 2) end,
  }
  function map:GetMapID() return self.id end
  function map:GetCanvas() return canvas end
  function map:GetCanvasScale() return self.scale end
  function map:GetCanvasZoomPercent() return self.zoom end
  function map:GetGlobalPinScale() return 1 end
  map.levels = { PIN_FRAME_LEVEL_AREA_POI = 300, PIN_FRAME_LEVEL_INVASION = 250, PIN_FRAME_LEVEL_DIG_SITE = 200, PIN_FRAME_LEVEL_QUEST_BLOB = 100 }
  local levels = { GetValidFrameLevel = function(_, t) return map.levels[t] or 1 end }
  function map:GetPinFrameLevelsManager() return levels end
  -- what Blizzard_MapCanvas does on the client's own UI calls: opening refreshes every provider, a new map tells each,
  -- zooming tells each, closing tells each (MapCanvasMixin:OnHide, secureexecuterange over the providers' OnHide)
  function map:RefreshAll() for _, p in ipairs(self.providers) do p:RefreshAllData() end end
  function map:Open() self.shown = true; self:RefreshAll() end
  function map:Close()
    self.shown = false
    for _, p in ipairs(self.providers) do if p.OnHide then p:OnHide() end end
  end
  function map:SetMapID(id)
    if id == self.id then return end
    self.id = id
    for _, p in ipairs(self.providers) do p:OnMapChanged() end
  end
  function map:Zoom(scale, zoom)
    self.scale, self.zoom = scale, zoom
    for _, p in ipairs(self.providers) do p:OnCanvasScaleChanged() end
  end
  for _, name in ipairs({ "AcquirePin", "RemoveAllPinsByTemplate", "RemovePin", "EnumeratePinsByTemplate", "SetPinPosition", "ApplyPinPosition" }) do
    map[name] = function() error("QuestBank called the map canvas's " .. name .. ": that writes QuestBank's taint into the map", 2) end
  end
  map.ScrollContainer = { MarkCanvasDirty = function() error("QuestBank wrote into the map's scroll container", 2) end }
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

-- QuestBank's own frames on a client's world map, drawn now: every layer's, or one template's
local function ours(c, template)
  local out = {}
  for _, layer in ipairs({ c.QB.Pins and c.QB.Pins.provider or false, c.QB.QuestMap and c.QB.QuestMap.provider or false }) do
    if layer then
      for _, f in ipairs(layer.active) do
        if not template or f.kind.template == template then out[#out + 1] = f end
      end
    end
  end
  return out
end

-- the player clicks the map-pin link in a chat line: Blizzard's handler (ItemRefHandlers.lua, LinkTypes.WorldMapWaypoint)
-- reads the waypoint from the link, sets it and opens the map on it, as the game's own code. The point set, or nil
local function clickMapLink(c, line)
  local link = line and line:match("|H(worldmap:[^|]+)|h")
  if not link then return nil end
  c.blizzard = true
  local wp = c.env.C_Map.GetUserWaypointFromHyperlink("|H" .. link .. "|h")
  local ok = wp and c.env.C_Map.SetUserWaypoint(wp)
  c.blizzard = false
  if ok then c.mapOpenedOn = wp.m end
  return ok and wp or nil
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
            or (m[3] == "CHANNEL" and from.channels.QuestBankVer and to.channels.QuestBankVer and to ~= from)
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
  local pledge = QB.Quest.Get(3638)
  if pledge then
    local cc = QB:ChainCost(pledge)
    assert(cc and cc.first and QB.Quest.ForMe(cc.first) and cc.first.id ~= 3526, "an either-or prerequisite names a step for your faction: " .. tostring(cc and cc.first and cc.first.name))
  end
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
end
for _, c in ipairs(UI:Candidates(400)) do
  local q = QB.Quest.Get(c.id)
  assert(not (q.turn and q.turn.inside), "no quest handed in inside a dungeon is offered to fetch: " .. q.name)
  assert(not q.sodLeftover, "no Season of Discovery leftover is offered: " .. q.name)
end
assert(not QB.Data.Q[78132] and not QB.Data.Q[78133] and not QB.Data.Q[78134], "Alonso's Dragonslayer quests aren't in Forever")
-- the join prompt for escort quests: the game's MAX_QUESTS decides whether its Yes works. 3.3.4 to 3.6.0 wrote the log's
-- size into it; QuestBank only reads it now (an addon's write would make the prompt open as QuestBank)
do
  local env = owner.env
  assert(env.MAX_QUESTS == 40 and env.MAX_QUESTLOG_QUESTS == 40, "login leaves the game's numbers alone")
  assert(QB.state.logCount >= 25, "the owner holds 25 quests or more")
  local n = #owner.chat
  owner.ev(QB.eventFrame, "QUEST_ACCEPT_CONFIRM", "Brann Steelhand", "Escorting Erland", 435)
  assert(#owner.chat == n and env.MAX_QUESTS == 40, "a client that counts 40: nothing to say, nothing written")
  env.SlashCmdList.QUESTBANK("escort")
  assert(#owner.chat == n + 1 and owner.chat[#owner.chat]:find("counts 40 quests as a full log: with fewer, its Yes works.", 1, true), "/qb escort says so: " .. owner.chat[#owner.chat])
  QB.NoteAddons()
  assert(env.QuestBankDB.diag.addons.maxQuests == 40, "the uploads show the game's number")
  -- an older build, whose prompt counts 25: said once a session, the number left as the game has it
  env.MAX_QUESTS, env.MAX_QUESTLOG_QUESTS = 25, 25
  n = #owner.chat
  owner.ev(QB.eventFrame, "QUEST_ACCEPT_CONFIRM", "Brann Steelhand", "Escorting Erland", 435)
  local said = owner.chat[#owner.chat]
  assert(#owner.chat == n + 1 and said:find("Brann Steelhand started Escorting Erland", 1, true)
    and said:find("counts 25 quests as a full log (yours holds 40), so its Yes stays grey", 1, true), "25 or more quests on such a client: why Yes is grey: " .. tostring(said))
  print("escort prompt, an older build:", said)
  owner.ev(QB.eventFrame, "QUEST_ACCEPT_CONFIRM", "Brann Steelhand", "Escorting Erland", 435)
  assert(#owner.chat == n + 1, "and says it once")
  assert(env.MAX_QUESTS == 25 and env.MAX_QUESTLOG_QUESTS == 25, "the game's numbers stay as the game has them")
  for _, arg in ipairs({ "off", "on", "" }) do env.SlashCmdList.QUESTBANK("escort " .. arg) end
  assert(env.MAX_QUESTS == 25 and owner.chat[#owner.chat]:find("QuestBank leaves the game's number alone", 1, true), "/qb escort, on or off: only says where things stand: " .. owner.chat[#owner.chat])
  print("escort prompt:", owner.chat[#owner.chat])
  env.MAX_QUESTS, env.MAX_QUESTLOG_QUESTS = 40, 40
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
  -- an escort a party member starts: the game's prompt is the player's. QuestBank presses nothing and hides nothing
  -- (ConfirmAcceptQuest and StaticPopup_Hide error here), and says so once a session
  n = #owner.auto
  local said = #owner.chat
  owner.ev(QB.eventFrame, "QUEST_ACCEPT_CONFIRM", "Brann Steelhand", "Escorting Erland", 435); tick(owner, 1)
  local escortLine
  for i = said + 1, #owner.chat do if owner.chat[i]:find("say yes in the game's prompt to join", 1, true) then escortLine = owner.chat[i] end end
  assert(#owner.auto == n and escortLine and escortLine:find("Brann Steelhand started Escorting Erland", 1, true),
    "an escort a party member starts: nothing pressed, and it says the prompt is yours: " .. tostring(owner.chat[#owner.chat]))
  print("escort, Accept for me on:", escortLine)
  said = #owner.chat
  owner.ev(QB.eventFrame, "QUEST_ACCEPT_CONFIRM", "Brann Steelhand", "Escorting Erland", 435); tick(owner, 1)
  assert(#owner.auto == n and #owner.chat == said, "said once a session")
  for i = 1, QB.LOG_SLOTS - #owner.log do table.insert(owner.log, { 9000000 + i, 0 }) end
  owner.ev(QB.eventFrame, "QUEST_LOG_UPDATE"); tick(owner, 1)
  assert(QB.state.logCount == QB.LOG_SLOTS, "the log is full")
  owner.ev(QB.eventFrame, "QUEST_ACCEPT_CONFIRM", "Brann Steelhand", "Escorting Erland", 435); tick(owner, 1)
  assert(#owner.auto == n, "a full log: nothing pressed either")
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
  assert(#owner.auto == n, "the escort prompt with Shift: nothing pressed")
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
  assert(sf.bar:IsShown() and hi > 0 and hi == 722 - sf:GetHeight(), "the knob runs exactly what does not fit: " .. tostring(hi) .. " of " .. tostring(sf:GetHeight()))
  sf.__scripts.OnMouseWheel(sf, -1)
  assert(sf.bar:GetValue() == 44, "a wheel notch scrolls 44 px")
  sf.bar:SetValue(hi); UI:Refresh()
  lay = checkLayout(UI.frame, "settings, scrolled to the bottom")
  assert(#lay == 0, "and the bottom of the page, in view, fits: " .. table.concat(lay, "; "))
  sf.bar:SetValue(0)
  UI:ShowTab(1); UI:Refresh()
end
-- 3.4.3: questing, a quest given inside a dungeon is measured to the entrance, kept, and shown on its card
do
  QB:SetLock("off"); QB:Recompute(true)
  assert(QB:Mode() == "quest", "questing by hand")
  QB:Settings().rangeAbove = 12 -- as a player may set it: the dungeon quests above you come into view
  UI.candMemo = nil
  local villainy, inside = nil, 0
  for _, c in ipairs(UI:Candidates(400)) do
    if c.id == 1200 then villainy = c end
    if c.give > 0 and QB.Data.NPC[c.give][5] < 0 then
      inside = inside + 1
      assert(c.away ~= 60 and c.away ~= 10, "a giver inside a dungeon is measured to the entrance, not invented: " .. QB.Data.QN[c.id] .. " " .. tostring(c.away))
    end
  end
  assert(inside > 0 and villainy, "Blackfathom Villainy, given inside the dungeon, is a candidate while questing")
  UI:ShowTab(2)
  UI.expanded = {}
  for _, cat in ipairs(QB.Data.CAT) do UI.expanded[cat.key] = true end
  UI:Refresh()
  local onCard
  for _, c in ipairs(UI.views[2].cards.items) do for _, r in ipairs(c.rows.items) do if r:IsShown() and r.q and r.q.id == 1200 then onCard = true end end end
  assert(onCard, "and it is listed on the Blackfathom Deeps card while questing")
  UI.expanded = nil
  QB:Settings().rangeAbove = "auto"
  QB:SetLock("auto"); QB:Recompute(true)
  assert(QB:Mode() == "lock", "back to banking")
  UI.candMemo = nil
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
  for _, c in ipairs(UI.views[2].cards.items) do
    local t = c.count:GetText() or ""
    if c:IsShown() and c.skip:IsShown() and t:find("available") and not t:find("in your log") and not t:find("to pick up") then fetchOnly = fetchOnly or c end
  end
  assert(fetchOnly, "a card with nothing of yours")
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
assert(v3.summary:GetText() == "64,970 XP  |  level 22.61  |  93 min  |  at 60 min 22.58", "the owner's banked route is unchanged, got: " .. tostring(v3.summary:GetText()))
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
assert(v3.summary:GetText() == "93,610 XP  |  level 23.61  |  121 min  |  at 60 min 23.42", "the owner's full plan is unchanged, got: " .. tostring(v3.summary:GetText()))
print("setup:", v3.setup:GetText())
for _, key in ipairs({ "mounted", "pins" }) do
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
  layouts[#layouts + 1] = dumpLayout(UI.frame, ({ "Quest Log", "Available", "Hand-in Route", "Party", "Settings" })[tab] .. " (one row hovered)")
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
  for _, it in ipairs(m.items) do if it:IsShown() and it.label:GetText() == "Leave it out of the route" then it.__scripts.OnClick(it) end end
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
local routePins = ours(owner, "QuestBankPinTemplate")
print("world map pins:", #routePins, "waypoints:", #owner.pins)
assert(#routePins > 0, "the route has pins on the world map")
for _, pin in ipairs(routePins) do lines = {}; pin:OnMouseEnter(); assert(#lines > 0); pin:OnMouseLeave() end
-- waypoints: QuestBank never sets the game's own (C_Map.SetUserWaypoint, C_SuperTrack error here), map open or shut,
-- in combat or not. Its arrow points there at once, and the chat line carries the game's map-pin link: the player's
-- click on it is Blizzard's handler, which sets the pin as the game's own code
do
  local A = QB.Arrow
  local said = #owner.chat
  assert(owner.map.shown, "the world map is open here")
  QB.API.SetWaypoint(1429, 42, 65, "Goldshire")
  local line = owner.chat[#owner.chat]
  assert(#owner.chat == said + 1 and line:find("Waypoint: Goldshire (42, 65).", 1, true) and line:find("|Hworldmap:1429:4200:6500|h[Map pin]|h", 1, true),
    "a waypoint: one chat line, with the game's map-pin link for the spot: " .. line)
  print("waypoint:", line)
  assert(#owner.pins == 0, "the game's own waypoint is not set by QuestBank")
  local wp = clickMapLink(owner, line)
  assert(wp and wp.m == 1429 and math.abs(wp.x - 0.42) < 1e-6 and math.abs(wp.y - 0.65) < 1e-6 and owner.mapOpenedOn == 1429,
    "the player's click on the link: the game sets its pin there and opens the map on it")
  -- the arrow switched off: it shows for this waypoint, the switch stays off; the line says so
  assert(not QB:Settings().arrow and A.temp and A.temp.name == "Goldshire" and owner.env.QuestBankArrow:IsShown(),
    "the arrow off: it shows for the waypoint")
  assert(line:find("The arrow shows the way until you get there.", 1, true), "and the line says so")
  -- the map shut, and in combat: the same, and still nothing set by QuestBank
  owner.map:Close()
  owner.combat = true
  QB.API.SetWaypoint(1429, 30.06, 70.5, "Somewhere")
  line = owner.chat[#owner.chat]
  assert(line:find("|Hworldmap:1429:3006:7050|h", 1, true) and #owner.pins == 1, "the map shut, in combat: the link, nothing set: " .. line)
  owner.combat = false
  owner.map:Open()
  -- a map the game has no pins for: no link (the arrow still points)
  owner.noPins = { [1581] = true }
  QB.API.SetWaypoint(1581, 50, 50, "Inside")
  assert(not owner.chat[#owner.chat]:find("worldmap", 1, true) and owner.chat[#owner.chat]:find("Waypoint: Inside", 1, true), "no pins on that map: no link")
  owner.noPins = nil
  -- the run's own waypoint, as the next stop changes (quiet): nothing said, nothing set
  said = #owner.chat
  QB.API.SetWaypoint(1429, 40, 40, "Next stop", true)
  assert(#owner.chat == said and #owner.pins == 1, "the run's quiet waypoint: no line, nothing set")
  -- TomTom's arrow when it is there. Its world-map icon is HereBeDragons-Pins', which calls the map canvas's AcquirePin
  -- and RemovePin there and then: with the map open that writes the canvas's scale and scroll, so TomTom is never told
  -- from QuestBank's call then (the mock errors). The newest waypoint waits for the map to shut; shut, at once
  A:EndTemp()
  -- stand-ins first: MapPinEnhanced's TomTom (AddWaypoint only), or the real one with MapPinEnhanced hooked on, and
  -- WaypointTracker's bridge set the game's own waypoint inside the call (the mock errors when QuestBank's code reaches
  -- C_Map.SetUserWaypoint). QuestBank never calls them: its arrow and the link, as with no TomTom
  local function standIn(extra)
    local t = { AddWaypoint = function(_, m, x, y) owner.env.C_Map.SetUserWaypoint({ uiMapID = m, position = { x = x, y = y } }) end }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
  end
  for _, case in ipairs({
    { "MapPinEnhanced's own TomTom", standIn(), nil },
    { "TomTom with MapPinEnhanced hooked on", standIn({ IsCrazyArrowEmpty = function() return true end }),
      { TomTom = { loaded = true }, MapPinEnhanced = { loaded = true } } },
    { "WaypointTracker's bridge", standIn({ IsCrazyArrowEmpty = function() return true end, isWaypointTrackerBridge = true }), nil },
    { "a TomTom table with the TomTom addon not loaded", standIn({ IsCrazyArrowEmpty = function() return true end }), {} },
  }) do
    owner.env.TomTom, owner.addons = case[2], case[3]
    assert(QB.API.TomTom() == nil, case[1] .. ": not TomTom to QuestBank")
    said = #owner.chat
    QB.API.SetWaypoint(1429, 44, 66, "Stand-in")
    QB.API.SetWaypoint(1429, 45, 67, "Stand-in, quiet", true)
    owner.map:Close(); tick(owner, 0); QB:Changed(); owner.map:Open()
    assert(#owner.chat == said + 1 and owner.chat[#owner.chat]:find("worldmap:1429:4400:6600", 1, true), case[1] .. ": the arrow and the link")
    A:EndTemp()
  end
  owner.env.TomTom = nil
  local tt = {}
  owner.addons = { TomTom = { loaded = true } }
  owner.env.TomTom = {
    AddWaypoint = function(_, m, x, y)
      assert(not owner.map.shown, "TomTom told of a waypoint with the map open: HereBeDragons acquires its pin inside QuestBank's call")
      tt[#tt + 1] = { m, x, y }
      return #tt
    end,
    RemoveWaypoint = function() assert(not owner.map.shown, "TomTom's waypoint removed with the map open") end,
    IsCrazyArrowEmpty = function() return true end,
  }
  said = #owner.chat
  assert(owner.map.shown, "the map is open")
  QB.API.SetWaypoint(1429, 40, 40, "Next stop", true)
  assert(#tt == 0 and #owner.chat == said, "the run's quiet waypoint with the map open: TomTom waits, nothing said")
  QB.API.SetWaypoint(1429, 42, 65, "Goldshire")
  line = owner.chat[#owner.chat]
  assert(#tt == 0 and #owner.chat == said + 1 and line:find("Waypoint: Goldshire (42, 65). TomTom gets it when you close the map.", 1, true) and not A.temp,
    "a click with the map open: TomTom waits, one line says so, no arrow of QuestBank's shown for it: " .. line)
  print("waypoint, TomTom, the map open:", line)
  QB:Changed()
  assert(#tt == 0, "a refresh with the map still open: still waiting")
  owner.map:Close()
  assert(#tt == 0, "not inside the map's OnHide")
  tick(owner, 0)
  assert(#tt == 1 and tt[1][1] == 1429 and math.abs(tt[1][2] - 0.42) < 1e-9 and math.abs(tt[1][3] - 0.65) < 1e-9, "once the map has shut: TomTom gets the newest, once")
  tick(owner, 1)
  assert(#tt == 1, "and not again")
  QB.API.SetWaypoint(1429, 30, 30, "Shut map", true)
  QB.API.SetWaypoint(1429, 31, 31, "Shut map")
  assert(#tt == 3 and #owner.chat == said + 1, "the map shut: at once, quiet or not, nothing said (TomTom says its own)")
  owner.map:Open()
  owner.env.TomTom, owner.addons = nil, nil
end

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
friend.window = { id = 128, xp = 2300 } -- well off the catalog's 2,000: a near match would only confirm it (3.4.7)
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
assert(shared and shared.src == "party" and shared.full == 2300, "the friend's quest window XP reaches the owner")
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
  assert(owner.QB.Sync.ColorName("you", "PALADIN", true) ~= you and owner.QB.Sync.ColorName("you", "PALADIN", true):find("^|cff"), "the parchment cut is darker")
  local doneId
  for id, v in pairs(owner.done) do if v then doneId = id break end end
  QB:Plan().add[doneId] = true
  for _, w in ipairs(owner.QB.Sync:WhoHas(doneId)) do assert(not w.me, "a planned quest you already handed in isn't one you hold") end
  QB:Plan().add[doneId] = nil
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
-- banking keeps raw XP: no trip, no lead, nothing flagged
do
  local HU = horde.QB.UI
  HU.candMemo = nil
  local n = 0
  for _, c in ipairs(HU:Candidates(400)) do
    n = n + 1
    assert(c.rank == c.value and c.back == nil and c.lead == nil and c.time == nil and not c.waste, "banking keeps raw XP and weighs no trip: " .. QB.Data.QN[c.id])
  end
  assert(n > 0 and HU.candDropped == 0, "banking drops nothing")
  HU:ShowTab(1); HU:Refresh()
  for _, r in ipairs(HU.views[1].swaps) do if r:IsShown() then assert(not r.cutName:GetText():find("leads to", 1, true), "banking rows don't say what a quest leads to") end end
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
  -- switched off, it showed only for a waypoint clicked above (Core.lua, API.SetWaypoint): until you get there
  assert(not QB:Settings().arrow, "the arrow is off until you turn it on")
  assert(not owner.env.QuestBankArrow or not owner.env.QuestBankArrow:IsShown() or A.temp, "and shows only for a waypoint you click")
  do
    local F = owner.env.QuestBankArrow
    A:EndTemp()
    assert(not F:IsShown() and not A.temp, "a waypoint's arrow goes")
    -- the arrow off: a waypoint shows it, pointing there, the switch still off
    local here = QB.API.WorldPosition()
    QB.API.SetWaypoint(1429, 42, 65, "Goldshire", nil, { c = here.c, wx = here.wx + 300, wy = here.wy })
    assert(F:IsShown() and not QB:Settings().arrow and A.Target().name == "Goldshire" and A.Target().temp, "a waypoint with the arrow off: shown for it")
    owner.facing = 0
    F.__scripts.OnUpdate(F, 1)
    assert(F.name:GetText() == "Goldshire" and F.dist:GetText():find("yards", 1, true), "it points there: " .. F.dist:GetText())
    lines = {}; F.__scripts.OnEnter(F)
    assert(lines[1] == "You chose: Goldshire" and table.concat(lines, "\n"):find("Shown for this waypoint: it goes when you get there.", 1, true),
      "its tooltip says it is up for this waypoint: " .. table.concat(lines, " / "))
    for _, pr in ipairs(checkLayout(F, "arrow for a waypoint")) do problems[#problems + 1] = pr end
    -- you get there: it says so, and goes a few seconds later; the switch is as it was
    QB.API.SetWaypoint(1429, 42, 65, "Goldshire", nil, { c = here.c, wx = here.wx + 5, wy = here.wy })
    F.__scripts.OnUpdate(F, 1)
    assert(F:IsShown() and F.dist:GetText() == "You're there", "there: it says so")
    tick(owner, 5)
    F.__scripts.OnUpdate(F, 1)
    assert(not F:IsShown() and not A.temp and not QB:Settings().arrow, "and goes, the switch still off")
    -- shown for a waypoint, Hide in its menu hides it; choosing what it points at keeps it up
    QB.API.SetWaypoint(1429, 42, 65, "Goldshire", nil, { c = here.c, wx = here.wx + 300, wy = here.wy })
    F.__scripts.OnClick(F, "RightButton")
    local Mn = owner.env.QuestBankMenu
    for _, b in ipairs(Mn.items) do if b:IsShown() and b.label:GetText() == "Hide the arrow" then b.__scripts.OnClick(b) end end
    assert(not F:IsShown() and not A.temp and not QB:Settings().arrow and owner.chat[#owner.chat]:find("A waypoint you click shows it again", 1, true),
      "Hide: gone, the switch off: " .. owner.chat[#owner.chat])
    QB.API.SetWaypoint(1429, 42, 65, "Goldshire", nil, { c = here.c, wx = here.wx + 300, wy = here.wy })
    F.__scripts.OnClick(F, "RightButton")
    for _, b in ipairs(Mn.items) do if b:IsShown() and b.label:GetText():find("^The next stop") then b.__scripts.OnClick(b) end end
    assert(F:IsShown() and QB:Settings().arrow and not A.temp and A.Mode() == "route", "choosing the route from its menu: the arrow stays up")
    A:Set(false)
    assert(not F:IsShown(), "off again")
    QB:Settings().arrowPin = nil
  end
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
  A.Invalidate() -- the plan changed behind QuestBank's back; QB:MarkDirty does this in play
  assert(A.Mode() == "pickup" and A.Target() == nil, "an empty plan: nothing to pick up")
  F.__scripts.OnUpdate(F, 1)
  assert(F.name:GetText():find("Nothing on your pick%-up list"), "and the arrow says so: " .. F.name:GetText())
  plan.add[1221] = true
  A.Invalidate() -- QB:MarkDirty does this when the plan changes through QuestBank
  t = A.Target()
  assert(t and t.kind == "pickup" and t.name == QB.Quest.Get(1221).give.n, "a planned quest: the arrow finds its giver: " .. tostring(t and t.name))
  -- a chain whose only open step you already hold: nothing to pick up, the hand-in covers it
  local q346, q343 = QB.Quest.Get(346), QB.Quest.Get(343)
  assert(q346 and q343 and QB.state.log[343] and QB:Status(q346).code == "prereq", "Return to Kristoff waits on Speaking of Fortitude, which the owner holds")
  plan.add = { [346] = true }
  A.Invalidate()
  t = A.Target()
  local first, held = A.FirstStep(q346, QB:Status(q346))
  assert(first and first.id ~= 343 or held, "the chain's next move is never the giver of the step you already hold")
  if held then
    assert(t == nil, "pickup mode: when only the held step is left it is a hand-in, not a pick-up: " .. tostring(t and t.name))
  else
    assert(t and t.name == first.give.n and t.name ~= q343.give.n, "pickup mode: the giver of the first open step, past the one you hold: " .. tostring(t and t.name))
  end
  UI.QuestClick(q346, QB:Status(q346), "LeftButton")
  local expect = held and q343.turn.n or first.give.n
  assert(QB:Settings().arrowPin and QB:Settings().arrowPin.name == expect, "clicking the chain quest sets the waypoint on " .. (held and "the held step's turn-in" or "the first open step's giver") .. ": " .. tostring(QB:Settings().arrowPin and QB:Settings().arrowPin.name))
  print("chain with a held step:", QB:Status(q346).text, "-> waypoint", expect)
  assert(A.Mode() == "pin", "the click re-aimed the arrow at what was clicked")
  A:SetMode("pickup")
  -- a chain whose only open step is the one you hold: a hand-in, not a pick-up
  do
    local only
    for _, e in ipairs(QB.state.logOrder) do
      local hq = QB.Quest.Get(e.id)
      if hq and hq.nextSteps then
        for _, nid in ipairs(hq.nextSteps) do
          local nq = QB.Quest.Get(nid)
          if nq and not QB.state.log[nid] and not QB.API.IsDone(nid) and QB.Quest.ForMe(nq) then
            local f2, h2 = A.FirstStep(nq, QB:Status(nq))
            if h2 and f2.id == e.id and hq.turn and not hq.turn.inside then only = only or { q = nq, step = hq } end
          end
        end
      end
    end
    if only then
      plan.add = { [only.q.id] = true }
      A.Invalidate()
      assert(A.Target() == nil, "pickup mode: nothing to pick up when the only step left is one you hold: " .. only.q.name)
      UI.QuestClick(only.q, QB:Status(only.q), "LeftButton")
      assert(QB:Settings().arrowPin.name == only.step.turn.n, "and a click aims at the held step's turn-in: " .. tostring(QB:Settings().arrowPin.name))
      print("chain with only a held step left:", only.q.name, "-> hand in", only.step.name, "to", only.step.turn.n)
    else
      print("(no chain with only a held step left in the owner's log; the held-step rule is covered by FirstStep's held flag above)")
    end
  end
  plan.add = keep
  A.Invalidate()
  -- the route's own pins never re-aim the arrow
  owner.env.SlashCmdList.QUESTBANK("arrow route")
  QB.Pins:PinNext(true)
  assert(A.Mode() == "route", "/qb next leaves the arrow on the route")
  -- the menu with 'where you last clicked' chosen and nothing clicked yet fits its width
  QB:Settings().arrowPin = nil
  A:SetMode("pin")
  F.__scripts.OnClick(F, "RightButton")
  local Mn = owner.env.QuestBankMenu
  local pinLabel
  for _, b in ipairs(Mn.items) do if b:IsShown() and b.label:GetText():find("^Where you last clicked") then pinLabel = b.label:GetText() end end
  assert(pinLabel and pinLabel:find("%(now%)") and not pinLabel:find("nothing yet"), "the chosen pin entry says (now) and no more: " .. tostring(pinLabel))
  for _, pr in ipairs(checkLayout(Mn, "arrow menu, pin chosen")) do problems[#problems + 1] = pr end
  Mn:Hide()
  F.__scripts.OnUpdate(F, 1)
  assert(F.name:GetText() == "Nothing chosen yet", "the arrow itself says nothing is chosen: " .. F.name:GetText())
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
  assert(A.toldPin, "and it said so, once this session (the first pin above did)")
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
  -- 3.4.1/3.4.3: questing ranks by XP for the time, counts what a chain leads on to, and keeps long runs
  -- for little off the swap list (flagged, still on the Plan page)
  do
    U.candMemo = nil
    local cands = U:Candidates(400)
    assert(#cands > 0 and N:Mode() == "quest", "the newbie quests")
    local kept, waste, withLead, unknown = 0, 0, 0, 0
    for _, c in ipairs(cands) do
      assert(c.away and c.back and c.lead and c.rank and c.time and c.time <= 1, "every questing candidate carries its trip, loop, lead and time: " .. QB.Data.QN[c.id])
      if c.waste then waste = waste + 1; assert(c.away > 4, "nothing under four minutes is a waste: " .. QB.Data.QN[c.id]) else kept = kept + 1; assert(c.away <= 20, "a suggestion is within twenty minutes: " .. QB.Data.QN[c.id]) end
      if c.lead > 0 then withLead = withLead + 1 end
      if c.give == 0 then unknown = unknown + 1; assert(not c.waste and c.away == 10, "an unknown giver stands in as ten minutes and is never a waste: " .. QB.Data.QN[c.id]) end
    end
    assert(kept > 0 and waste > 0 and U.candDropped == waste, "candidates come back flagged, and the flags are counted: " .. kept .. " kept, " .. waste .. " waste")
    assert(withLead > 0, "a chain's first step counts what it leads on to")
    assert(unknown > 0, "the newbie has candidates whose giver the catalog lacks, and they stay")
    for _, r in ipairs(U.views[1].swaps) do
      if r:IsShown() then for _, c in ipairs(cands) do if c.id == r.add.id then assert(not c.waste, "the swap list never offers a waste: " .. r.add.name) end end end
    end
    -- a quest that leads on ranks above its own XP for the time
    local leader
    for _, c in ipairs(cands) do if c.lead > 0 then leader = leader or c end end
    assert(leader and leader.rank > leader.value * leader.time, "a quest that leads on ranks above its own XP for the time: " .. QB.Data.QN[leader.id])
    -- no position: nothing is a waste and nothing is away
    local savePos = newbie.env.C_Map.GetPlayerMapPosition
    newbie.env.C_Map.GetPlayerMapPosition = function() return nil end
    U.candMemo = nil
    local blind = U:Candidates(400)
    assert(U.candDropped == 0 and blind[1].away == 0, "no position known: nothing is dropped and nothing is away")
    newbie.env.C_Map.GetPlayerMapPosition = savePos
    U.candMemo = nil
    -- close beats far: the same quest ranks higher from Ironforge than from Northshire when it stands in Dun Morogh
    local pick
    for _, c in ipairs(cands) do if QB.Data.CAT[c.cat].key == "z1" and c.lead == 0 and c.value > 0 and c.give > 0 then pick = pick or c end end
    assert(pick, "a Dun Morogh quest with no lead and a placed giver")
    local hereRank = pick.rank
    local saveWorld = newbie.o.world
    newbie.o.world = { 0, -4822, -1155 } -- Ironforge
    U.candMemo = nil
    local there
    for _, c in ipairs(U:Candidates(400)) do if c.id == pick.id then there = c end end
    assert(there and there.rank > hereRank and there.away < pick.away, "closer to its giver, the same quest ranks higher: " .. QB.Data.QN[pick.id])
    newbie.o.world = saveWorld
    U.candMemo = nil
    cands = U:Candidates(400)
    print(string.format("newbie candidates: %d kept, %d flagged as a waste, %d lead somewhere", #cands - U.candDropped, U.candDropped, withLead))
    local leadRow
    for _, r in ipairs(U.views[1].swaps) do if r:IsShown() and r.cutName:GetText():find("leads to +", 1, true) then leadRow = leadRow or r end end
    assert(leadRow, "a swap row says what the quest leads on to")
    print("newbie lead row:", leadRow.addName:GetText(), "|", leadRow.cutName:GetText())
    -- chain quests in the swap list: their steps in the text, and a left click aiming at the right NPC
    local stepRows, chainRow = 0, nil
    for _, r in ipairs(U.views[1].swaps) do
      if r:IsShown() and r.add and N:Status(r.add).code == "prereq" and not r.via and not r.cutName:GetText():find("hand in") then
        local cc = N:ChainCost(r.add)
        assert(cc and r.cutName:GetText():find(" · " .. cc.n .. " step"), "a chain quest's row counts its steps: " .. r.cutName:GetText())
        stepRows = stepRows + 1
        chainRow = chainRow or r
      end
    end
    assert(stepRows > 0, "the newbie's swap list has chain quests with their steps")
    -- a left click aims at the right NPC: the first open step's giver, or a held step's turn-in (a row whose
    -- step the catalog has no NPC for can't be tested that way)
    local clicked
    for _, r in ipairs(U.views[1].swaps) do
      if not clicked and r:IsShown() and r.add and N:Status(r.add).code == "prereq" and not r.via and not r.cutName:GetText():find("hand in") then
        local first, held = N.Arrow.FirstStep(r.add, N:Status(r.add))
        local expect = first and (held and first.turn or first.give)
        if expect and not expect.inside then
          N:Settings().arrowPin = nil
          r.__scripts.OnClick(r, "LeftButton")
          assert(N:Settings().arrowPin and N:Settings().arrowPin.name == expect.n, "a left click on a chain row aims at " .. (held and "the held step's turn-in" or "the first step's giver") .. ": " .. tostring(N:Settings().arrowPin and N:Settings().arrowPin.name))
          print("newbie chain row:", r.addName:GetText(), "|", r.cutName:GetText(), "-> waypoint", expect.n)
          clicked = true
        end
      end
    end
    assert(clicked, "a chain row with a known NPC to aim at")
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
    layouts[#layouts + 1] = dumpLayout(U.frame, "Level 3, questing: " .. ({ "Quest Log", "Available", "Hand-in Route", "Party", "Settings" })[tab])
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
    assert(d.build == "70170" and d.ver == N.version, "which game build and QuestBank noted it")
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
  -- the game's pin doesn't follow the route (QuestBank never sets it): with the arrow off, the start says what does
  local started
  for i = #newbie.chat, 1, -1 do if newbie.chat[i]:find("Hand-in run started", 1, true) then started = newbie.chat[i]; break end end
  assert(started and started:find("/qb arrow points you from stop to stop.", 1, true), "the run's start names the arrow: " .. tostring(started))
  N.Run.Stop()
  local P = newbie.env.QuestBankPost
  if P then P:Hide() end
  -- the thresholds follow the level: a level 5's quests aren't all "make room"
  N:Recompute(true)
  U:ShowTab(2); N.Model.Finish(); U:Refresh()
  for _, c in ipairs(U.views[2].cards.items) do
    assert(not (c:IsShown() and c.title:GetText() == "Make room"), "no Make room card any more: the Quest Log slot tooltip carries that advice")
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

-- 3.4.4: Blizzard's 2026-10-01 cut to dungeon-quest XP ("50% less extra experience beyond normal quest values"):
-- every multiplier above x1 is computed from the earlier read, 1 + (m - 1) / 2, flagged, and said in the tooltip;
-- what the game said about those quests before the cut is forgotten once; secret values from the client are nobody
do
  local D = QB.Data
  assert(D.NERF and D.NERF.factor == 0.5 and D.NERF.date == "2026-10-01", "the cut is in the data")
  local Qs = QB.Quest
  local villainy, brother, arugal, satchel = Qs.Get(1200), Qs.Get(167), Qs.Get(1014), Qs.Get(5724)
  assert(villainy.mult == 2.375 and villainy.nerfed and villainy.dungeon, "Blackfathom Villainy: 3.75 -> 2.375, flagged")
  assert(arugal.mult == 2.675 and arugal.nerfed, "Arugal Must Die: 4.35 -> 2.675")
  assert(satchel.mult == 2.025 and satchel.nerfed, "Returning the Lost Satchel: 3.05 -> 2.025")
  assert(brother.mult == 1 and not brother.nerfed and brother.dungeon, "Oh Brother... stays at x1: no extra to cut")
  -- hand-ins uploaded on 2026-10-02 paid the cut value on multiplied quests outside dungeons too, so the cut
  -- covers every multiplied quest, and a quest the game paid is marked confirmed
  local righteous, cholaruk, knowledge = Qs.Get(1806), Qs.Get(97005), Qs.Get(971)
  assert(righteous.mult == 1.75 and righteous.nerfed and righteous.confirmed and not righteous.dungeon, "The Test of Righteousness: 2.5 -> 1.75, as a hand-in paid")
  assert(cholaruk.mult == 2 and cholaruk.nerfed and cholaruk.confirmed and cholaruk.group, "Chol'aruk the Ravener: 3 -> 2, as a hand-in paid")
  assert(knowledge.confirmed and QB.Model.Full(knowledge) == 6550, "Knowledge in the Deeps: 6,550, as the hand-in paid")
  assert(not villainy.confirmed, "Blackfathom Villainy: only a party member's number so far, still computed")
  lines = {}
  QB.UI.QuestTooltip(owner.env.GameTooltip, knowledge, QB:Status(knowledge), QB.Model.XpAt(knowledge, 20), 100, 20)
  assert(not table.concat(lines, "\n"):find("An estimate", 1, true), "a confirmed quest no longer says its number is computed")
  assert(table.concat(lines, "\n"):find("2,750 x 2.375, as the game paid after the cut", 1, true), "and its source line says the game paid it")
  assert(QB.Model.Full(villainy) == 7850, "3,300 x 2.375 = 7,837.5, rounded to 7,850 (was 12,400), got " .. tostring(QB.Model.Full(villainy)))
  -- the tooltip says the number is computed, and whose number wins
  lines = {}
  QB.UI.QuestTooltip(owner.env.GameTooltip, villainy, QB:Status(villainy), QB.Model.XpAt(villainy, 20), 100, 20)
  local text = table.concat(lines, "\n")
  assert(text:find("Forever XP 7,850", 1, true) and text:find("An estimate", 1, true), "the tooltip shows the cut XP and says why: " .. text:gsub("\n", " / "))
  lines = {}
  QB.UI.QuestTooltip(owner.env.GameTooltip, brother, QB:Status(brother), QB.Model.XpAt(brother, 20), 100, 20)
  assert(not table.concat(lines, "\n"):find("An estimate", 1, true), "an unmultiplied dungeon quest says nothing about the cut")
  -- stale live XP: a party member's pre-cut Deadmines number goes, a zone quest's number stays, once
  local db = owner.env.QuestBankDB
  local keep = db.live
  local unread
  for id, r in pairs(D.Q) do
    if r[10] % 2 == 1 and math.floor(r[10] / 8) % 2 == 1 and r[5] == 1 and (not unread or id < unread) then unread = id end
  end
  assert(unread, "a dungeon quest whose multiplier nobody has read")
  db.live = { [166] = { full = 9750, lvl = 20, src = "party" }, [5] = { full = 400, lvl = 20, src = "npc" },
              [167] = { full = 1550, lvl = 20, src = "npc" }, [unread] = { full = 4000, lvl = 30, src = "party" },
              [971] = { full = 6550, lvl = 22, src = "turnin" }, [1200] = { full = 8007, lvl = 20, src = "party" } }
  db.liveEra = nil
  Qs.Get(166).liveFull = 9750
  QB.Live.Apply()
  assert(db.live[166] == nil and Qs.Get(166).liveFull == nil, "The Defias Brotherhood's pre-cut number is forgotten")
  assert(db.live[5] and db.live[5].full == 400 and Qs.Get(5).liveFull == 400 and db.liveEra == 3, "a zone quest's number stays; the purge is marked done")
  assert(db.live[167] and Qs.Get(167).liveFull == 1550, "Oh Brother..., read at x1, had no extra to lose: its number stays")
  assert(db.live[unread] == nil and Qs.Get(unread).liveFull == nil, "an unread dungeon quest's number may have carried the old extra: forgotten")
  assert(db.live[971] and Qs.Get(971).liveFull == 6550, "a fresh post-cut hand-in number stays")
  assert(db.live[1200] and Qs.Get(1200).liveFull == 8007, "a party number near the cut value (8,007 against 7,850) is fresh and stays")
  -- 3.4.4 and 3.4.5 users (era 2) keep what they learned since, including unread dungeon quests
  db.live = { [unread] = { full = 4000, lvl = 30, src = "npc" }, [166] = { full = 9750, lvl = 20, src = "party" } }
  db.liveEra = 2
  QB.Live.Apply()
  assert(db.live[unread] and db.live[166] == nil and db.liveEra == 3, "era 2: the unread dungeon reading stays, the stale pre-cut number goes")
  Qs.Get(unread).liveFull, Qs.Get(971).liveFull, Qs.Get(1200).liveFull, Qs.Get(167).liveFull = nil, nil, nil, nil
  db.live[166] = { full = 6200, lvl = 20, src = "party" }
  QB.Live.Apply()
  assert(db.live[166] and Qs.Get(166).liveFull == 6200, "after the purge, new numbers for the same quest are kept")
  Qs.Get(166).liveFull, Qs.Get(5).liveFull = nil, nil
  db.live = keep
  QB.Live.Apply()
  -- secret values: the NPC's id (3.3.5's upload error at Discover.lua:33), a window's XP, a hand-in's XP
  local N2 = newbie.QB
  local ndb = newbie.env.QuestBankDB
  local realm = N2.RealmKey()
  local lockBefore = ndb.lock and ndb.lock[realm]
  local modeBefore = N2.mode
  local said
  local print0 = N2.Print
  N2.Print = function(_, msg) said = msg end
  local liveBefore = N2.Quest.Get(15).liveFull
  local function noted() local q = ndb.disc.q[15]; local n = 0; for _ in pairs(q and q.xp or {}) do n = n + 1 end; return n end
  local notedBefore = noted()
  newbie.npcGUID, newbie.npcName = SECRET.str(), "Marshal McBride"
  newbie.window = { id = 15, xp = 0, title = "Investigate Echo Ridge" }
  assert(N2.Discover.Who("npc") == nil, "a secret NPC id is nobody, not an error")
  N2.Discover.OnEvent("QUEST_DETAIL", 0)
  newbie.window = { id = 15, xp = SECRET.num(), title = "Investigate Echo Ridge" }
  newbie.ev(N2.eventFrame, "QUEST_COMPLETE")
  N2.Discover.OnEvent("QUEST_COMPLETE")
  local diag = ndb.diag and ndb.diag.xp
  assert(diag and diag[#diag].how == "complete" and diag[#diag].kind == "secret" and diag[#diag].id == 15, "the diagnostic ring notes a hidden XP number")
  assert(N2.Quest.Get(15).liveFull == liveBefore and noted() == notedBefore, "a hidden number teaches nothing")
  newbie.ev(N2.eventFrame, "QUEST_TURNED_IN", 15, SECRET.num())
  assert(diag[#diag].how == "turnin" and diag[#diag].kind == "secret", "a hidden hand-in number is noted the same way")
  assert((ndb.lock and ndb.lock[realm]) == lockBefore and N2.mode == modeBefore, "a hidden hand-in number is not a level lock")
  assert(said and said:find("hides its XP", 1, true) and not said:find("+0 XP", 1, true) and not said:find("paid no XP", 1, true), "chat says the game hid the number: " .. tostring(said))
  assert(ndb.turnins[#ndb.turnins].hidden == true and ndb.turnins[#ndb.turnins].xp == nil, "the hand-in record says hidden, not 0")
  -- a hidden quest id: the windows note nothing, no table ever gets it as a key, Auto doesn't click
  local st = N2:Settings()
  local acc, turn = st.autoAccept, st.autoTurnIn
  st.autoAccept, st.autoTurnIn = true, true
  local clicks = #newbie.auto
  newbie.window = { id = SECRET.num(), xp = 250, title = "Investigate Echo Ridge" }
  newbie.ev(N2.eventFrame, "QUEST_DETAIL")
  N2.Discover.OnEvent("QUEST_DETAIL", 0)
  newbie.ev(N2.eventFrame, "QUEST_COMPLETE")
  N2.Discover.OnEvent("QUEST_COMPLETE")
  N2.Discover.OnEvent("QUEST_ACCEPTED", SECRET.num(), SECRET.num())
  newbie.ev(N2.eventFrame, "QUEST_ACCEPTED", SECRET.num(), SECRET.num())
  for k in pairs(ndb.disc.q) do assert(type(k) == "number", "a hidden id never becomes a discovery key") end
  assert(diag[#diag].id == -1 and diag[#diag].kind == "number", "the ring notes a hidden id as -1")
  assert(#newbie.auto == clicks, "Auto never clicks on a hidden id")
  st.autoAccept, st.autoTurnIn = acc, turn
  newbie.window = { id = 15, xp = 250, title = "Investigate Echo Ridge" }
  newbie.ev(N2.eventFrame, "QUEST_DETAIL")
  assert(diag[#diag].how == "detail" and diag[#diag].kind == "number" and diag[#diag].v == 250, "a plain number is noted with its value")
  for _ = 1, 14 do newbie.ev(N2.eventFrame, "QUEST_DETAIL") end
  assert(#diag == 12, "the ring keeps a dozen")
  newbie.npcGUID, newbie.npcName, newbie.window = nil, nil, nil
  N2.Print = print0
end

-- 3.4.7: the sleeping bag's 3% is gone. The level-30 build's Well Rested speeds up rested XP instead of adding to
-- quest hand-ins (Wowhead's spell 1225478; the owner's hand-ins paid the unboosted number while the plan counted 3%
-- more), so numbers are taken as the game shows them, and a party member's near match confirms rather than corrects
do
  local N2 = newbie.QB
  local ndb = newbie.env.QuestBankDB
  assert(QB.BagBonus == nil and N2.BagBonus == nil, "no sleeping bag bonus anywhere")
  local n = 0
  for _ in pairs(owner.QB.UI.header and owner.QB.UI.header.toggles or {}) do n = n + 1 end
  assert(n == 0 or n == 3, "the header has three switches: mount, goal, pins (got " .. n .. ")")
  newbie.rested = true
  newbie.window = { id = 15, xp = 250, title = "Investigate Echo Ridge" }
  newbie.ev(N2.eventFrame, "QUEST_DETAIL")
  assert(N2.Quest.Get(15).liveFull == 250 and ndb.live[15] and ndb.live[15].full == 250 and ndb.live[15].at, "a window seen while Well Rested is recorded as shown, not divided by 1.03, and dated")
  newbie.rested, newbie.window = nil, nil
  local k = N2.Quest.Get(971)
  local before = ndb.live[971]
  N2.Live.Record(971, 6650, 22, "party")
  assert(ndb.live[971] == before, "a party number within 5% of the catalog's 6,550 confirms it and is not recorded")
  N2.Live.Record(971, 7500, 22, "party")
  assert(ndb.live[971] and ndb.live[971].full == 7500 and k.liveFull == 7500, "a party number well off the catalog's is recorded")
  N2.Live.Record(971, 6550, 22, "npc")
  assert(ndb.live[971].full == 6550 and ndb.live[971].src == "npc", "your own window wins over a party number")
  ndb.live[971] = before; k.liveFull = before and before.full or nil
  ndb.live[15] = nil; N2.Quest.Get(15).liveFull = nil
end


-- 3.4.8: the version notice reaches you from anyone on the realm who runs QuestBank, through one quiet channel
do
  local S1, S2 = owner.QB.Sync, newbie.QB.Sync
  for _ = 1, 3 do tick(owner, 10); tick(newbie, 10) end
  assert(owner.channels.QuestBankVer and S1.ver.joined, "the owner joined the version channel after logging in")
  assert(newbie.channels.QuestBankVer and S2.ver.joined, "so did the newbie")
  assert(owner.chatFilters and #owner.chatFilters >= 2, "the channel's notices are filtered out of the chat windows")
  local members = 0
  for _ in pairs(S1.members) do members = members + 1 end
  local was = newbie.QB.version
  newbie.QB.version = "9.9.9"
  owner.outbox, newbie.outbox = {}, {}
  S2:SayVersion()
  tick(newbie, 2); deliver(); tick(owner, 2)
  assert(owner.QB.newest and owner.QB.newest.version == "9.9.9", "a newer version said on the channel is noticed: " .. tostring(owner.QB.newest and owner.QB.newest.version))
  local after = 0
  for _ in pairs(S1.members) do after = after + 1 end
  assert(after == members, "a voice on the channel is not a party member")
  -- the older one keeps quiet; the newer one answers an older one, once, after a short random wait
  tick(newbie, 40)
  newbie.outbox = {}
  S1:SayVersion()
  tick(owner, 2); deliver()
  tick(newbie, 6)
  local replied = 0
  for _, m in ipairs(newbie.outbox) do if m[2]:find("^1V|9%.9%.9") and m[3] == "CHANNEL" then replied = replied + 1 end end
  assert(replied == 1, "the newer client answers the older one on the channel, once (got " .. replied .. ")")
  newbie.QB.version = was
  -- the Updates switch: off leaves the channel, on joins it again
  owner.QB:Settings().updates = false
  S1:ApplyVersionSetting()
  assert(not owner.channels.QuestBankVer and not S1.ver.joined, "Updates off leaves the channel")
  owner.QB:Settings().updates = true
  S1:ApplyVersionSetting()
  assert(owner.channels.QuestBankVer and S1.ver.joined, "Updates on joins it again")
  owner.outbox, newbie.outbox = {}, {}
end


-- 3.4.8: the game's own numbers and your own hand-ins, and chains that know where you are
do
  local Qs, U = QB.Quest, QB.UI
  local A = owner.QB.Arrow
  -- the quest log's XP for a quest you hold is the number, grey or not, and it is learned as "your quest log"
  owner.logXP = { [128] = 2000 }
  owner.ev(QB.eventFrame, "QUEST_LOG_UPDATE"); QB:ReadState()
  local q128 = Qs.Get(128)
  assert(q128.logXp == 2000 and QB.Model.XpAt(q128, 20) == 2000, "the quest log's number is used at this level")
  assert(owner.env.QuestBankDB.live[128] and owner.env.QuestBankDB.live[128].src == "log" and owner.env.QuestBankDB.live[128].full == 2000, "and learned from your quest log, over a party member's number")
  lines = {}
  U.QuestTooltip(owner.env.GameTooltip, q128, QB:Status(q128), QB.Model.XpAt(q128, 20), 100, 20)
  assert(table.concat(lines, "\n"):find("your quest log", 1, true), "the tooltip names the quest log as the source")
  -- a client that answers one value for every quest is not believed
  local held5 = {}
  for _, e in ipairs(QB.state.logOrder) do if #held5 < 5 and Qs.Get(e.id) then held5[#held5 + 1] = e.id end end
  assert(#held5 == 5, "five quests in the log")
  owner.logXP = {}
  for _, id in ipairs(held5) do owner.logXP[id] = 777 end
  owner.ev(QB.eventFrame, "QUEST_LOG_UPDATE"); QB:ReadState()
  for _, id in ipairs(held5) do assert(Qs.Get(id).logXp == nil, "five quests at 777 XP: the quest log is not read that way (" .. id .. ")") end
  assert(owner.env.QuestBankDB.live[128].full == 2000, "nothing learned from it either")
  owner.logXP = nil
  owner.ev(QB.eventFrame, "QUEST_LOG_UPDATE"); QB:ReadState()
  -- a secret completed flag is not a completed quest
  local flagWas = owner.env.C_QuestLog.IsQuestFlaggedCompleted
  owner.env.C_QuestLog.IsQuestFlaggedCompleted = function() return SECRET.num() end
  assert(QB.API.IsDone(2) == false, "a hidden flag means not known, not done")
  owner.env.C_QuestLog.IsQuestFlaggedCompleted = flagWas
  -- what you hand in is remembered per character, even when the game's list forgets it
  owner.log[#owner.log + 1] = { 2926, 1 } -- Gnogaine, part 2 of the Gnomeregan chain
  owner.ev(QB.eventFrame, "QUEST_LOG_UPDATE"); QB:ReadState()
  local st2927 = QB:Status(Qs.Get(2927))
  assert(st2927.behind and st2927.text == "Probably behind you" and st2927.later == 2926 and st2927.how == "held", "holding part 2 puts part 1 behind you: " .. st2927.text)
  lines = {}
  U.QuestTooltip(owner.env.GameTooltip, Qs.Get(2927), st2927, QB.Model.XpAt(Qs.Get(2927), 20), 100, 20)
  assert(table.concat(lines, "\n"):find("Gnogaine, a later step of this chain, is in your log", 1, true), "and the tooltip says which step and why")
  local st2962 = QB:Status(Qs.Get(2962))
  assert(st2962.code == "prereq" and st2962.text == "Hand in Gnogaine first", "part 3 says to hand in part 2, not to start part 1: " .. st2962.text)
  local first, held = A.FirstStep(Qs.Get(2962), st2962)
  assert(first and first.id == 2926 and held, "the arrow and the click aim at part 2's hand-in")
  for i = #owner.log, 1, -1 do if owner.log[i][1] == 2926 then table.remove(owner.log, i) end end
  owner.ev(QB.eventFrame, "QUEST_TURNED_IN", 2926, 0)
  owner.ev(QB.eventFrame, "QUEST_LOG_UPDATE"); QB:ReadState()
  assert(QB:Plan().handed[2926], "the hand-in is written down for this character")
  assert(not owner.done[2926], "(the game's list never gets it)")
  QB.API.RefreshDone()
  assert(QB.API.IsDone(2926) and QB:Status(Qs.Get(2926)).code == "done", "and it stays done after the list is read again")
  assert(QB:Status(Qs.Get(2927)).behind, "part 1 is still behind you once part 2 is done")
  QB:Plan().handed[2926] = nil
  QB.API.RefreshDone()
  -- the done list has a version: a change reaches the suggestions within the same second
  U.candMemo = nil
  local l1 = U:Candidates(400)
  assert(#l1 > 0, "candidates")
  owner.done[l1[1].id] = true
  QB.API.RefreshDone()
  local l2 = U:Candidates(400)
  assert(l2[1].id ~= l1[1].id, "a quest done since is gone from the next answer")
  owner.done[l1[1].id] = nil
  QB.API.RefreshDone()
  -- repeatables are never suggested; a finished quest leaves the fetch list
  for _, c in ipairs(U:Candidates(400)) do assert(math.floor(QB.Data.Q[c.id][10] / 4096) % 2 == 0, "a repeatable is never a candidate: " .. c.id) end
  QB:Plan().add[6981] = true
  QB:ReadState()
  assert(QB:Plan().add[6981] == nil, "a quest you finished is dropped from the plan's fetch list")
  -- the character key holds at logout, when the game stops answering the realm's short name
  local keys = 0
  for k in pairs(owner.env.QuestBankDB.chars) do if k:find("^Mikal%-") then keys = keys + 1 end end
  owner.realmGone = true
  owner.ev(QB.eventFrame, "PLAYER_LOGOUT")
  owner.realmGone = nil
  local after = 0
  for k in pairs(owner.env.QuestBankDB.chars) do if k:find("^Mikal%-") then after = after + 1 end end
  assert(after == keys and owner.env.QuestBankDB.chars["Mikal-ForeverNormal"], "one record per character, under the normalized key")
  assert(#owner.env.QuestBankDB.chars["Mikal-ForeverNormal"].completed > 0, "the logout record keeps the completed list")
  -- an older split: the spaced key's plan folds into the normalized one
  owner.env.QuestBankDB.plans["Mikal-Forever Normal"] = { add = { [5] = true }, cut = {}, seen = {}, removed = {} }
  QB:MergeCharKeys()
  assert(owner.env.QuestBankDB.plans["Mikal-Forever Normal"] == nil and QB:Plan().add[5], "the two spellings of the realm are one plan again")
  QB:Plan().add[5] = nil
  assert(tostring(owner.env.QuestBankDB.disc.build) == "70170", "the recorder notes the client build")
end


-- quests you chose to pick up show in the Quest Log grid's free slots, faded, with the pick-up mark
do
  local U = QB.UI
  U.candMemo = nil
  local pick
  for _, c in ipairs(U:Candidates(60)) do
    local q = QB.Quest.Get(c.id)
    if q and not QB.state.log[c.id] and QB:Status(q).code == "todo" and not QB:Plan().add[c.id] then pick = q break end
  end
  assert(pick, "a quest to choose")
  QB:Plan().add[pick.id] = true
  U:ShowTab(1); U:Refresh()
  local v1 = U.views[1]
  local slot
  for _, b in ipairs(v1.slots) do if b.pick and b.q and b.q.id == pick.id then slot = b end end
  assert(slot and slot:IsShown() and slot.mark:IsShown() and slot.mark.__tex == QB.Data.TEX.questAvail, "the chosen quest fills a free slot with the pick-up mark")
  assert(slot.xp:GetText() ~= "", "with its XP at your level")
  lines = {}; slot.__scripts.OnEnter(slot)
  assert(table.concat(lines, "\n"):find("To pick up: not in your log yet", 1, true), "its tooltip says it is still to pick up")
  QB:Plan().add[pick.id] = nil
  U:Refresh()
  local still = false
  for _, b in ipairs(v1.slots) do if b.pick and b.q and b.q.id == pick.id then still = true end end
  assert(not still, "dropping the choice clears the slot")
end


-- 3.4.9: the Available tab. The game's own marks, a ! that puts a quest on your pick-up list, counts per card,
-- and a hand-in run that ends by itself once it has outlived its hour
do
  local U, Dt = QB.UI, QB.Data.TEX
  U.candMemo = nil
  U:ShowTab(2); QB.Model.Finish(); U:Refresh()
  assert(U.tabs[2].label:GetText() == "Available", "the tab is called Available")
  local v2 = U.views[2]
  assert(v2.intro:GetText():find("^Level %d+ to %d+, "), "the intro names the level window and the order: " .. tostring(v2.intro:GetText()))
  local todoRow, heldRow
  for _, c in ipairs(v2.cards.items) do
    if c:IsShown() then
      assert(c.title:GetText() ~= "Make room", "no Make room card: the Quest Log slot tooltip carries that advice")
      for _, r in ipairs(c.rows.items) do
        if r:IsShown() and r.q then
          assert(r.mark.__tex ~= Dt.questActive, "the game's ? is never a mark on Available")
          if r.st.code == "todo" and not QB.state.log[r.q.id] and not QB:IsAdded(r.q.id) and not r.st.behind then todoRow = todoRow or r end
          if QB.state.log[r.q.id] then heldRow = heldRow or r end
        end
      end
    end
  end
  assert(todoRow and todoRow.mark.__tex == Dt.questAvail and todoRow.pick.pickable, "a quest you can pick up carries the game's ! and a live pick button")
  assert(heldRow and (heldRow.mark.__tex == Dt.ready or heldRow.mark.__tex == Dt.waiting) and not heldRow.pick.pickable, "a quest in your log carries the check or the waiting disc")
  assert(heldRow.away:GetText() == "", "no minutes on a quest you hold")
  local id = todoRow.q.id
  todoRow.pick.__scripts.OnClick(todoRow.pick)
  assert(QB:IsAdded(id), "the ! puts it on the pick-up list")
  U:Refresh()
  local row
  for _, c in ipairs(v2.cards.items) do for _, r in ipairs(c.rows.items) do if r:IsShown() and r.q and r.q.id == id then row = r end end end
  assert(row and row.status:GetText():find("^To pick up") and row.mark.__tex == Dt.questAvail, "chosen: To pick up, still with the !: " .. tostring(row and row.status:GetText()))
  assert(row:GetParent().count:GetText():find("to pick up", 1, true), "its card counts it: " .. row:GetParent().count:GetText())
  assert(v2.introR:GetText():find("to pick up", 1, true), "and so does the intro: " .. v2.introR:GetText())
  lines = {}; row.pick.__scripts.OnEnter(row.pick)
  assert(lines[1] == "To pick up" and lines[2]:find("take it off", 1, true), "the pick button's tooltip says what a click does")
  -- the Quest Log: in a free slot, not in the swap list
  U:ShowTab(1); U:Refresh()
  local v1 = U.views[1]
  for _, r in ipairs(v1.swaps) do if r:IsShown() and r.add then assert(r.add.id ~= id, "a chosen quest is not offered as a swap") end end
  local inGrid = false
  for _, b in ipairs(v1.slots) do if b.pick and b.q and b.q.id == id then inGrid = true end end
  -- it fills a free slot, or, when the log and the earlier picks already fill the grid, the worth line counts it
  assert(inGrid or v1.worth:GetText():find("more to pick up", 1, true), "it fills a free slot of the grid, or is counted as more to pick up: " .. v1.worth:GetText())
  QB:ToggleAdd(id)
  assert(not QB:IsAdded(id))
  U:ShowTab(2); U:Refresh()
  -- the Hand-in Route speaks of the log and pick-ups, not of a plan
  assert(U.views[3].modePlan:GetText() == "Log and pick-ups", "the route's second button: " .. tostring(U.views[3].modePlan:GetText()))
  -- a hand-in run ends by itself: two hours on, or an hour and a half with three levels gained
  local N2, ndb = newbie.QB, newbie.env.QuestBankDB
  local tnow = newbie.env.time()
  ndb.run = { started = tnow - 100 * 60, key = N2:CharKey(), level = (newbie.level or 3) - 2, xp = 0, done = {}, plan = {}, mode = "rush", predicted = 0, predictedT = 0 }
  N2:ReadState()
  assert(ndb.run, "100 minutes and two levels on: the run goes on")
  ndb.run.level = (newbie.level or 3) - 3
  N2:ReadState()
  assert(ndb.run == nil and N2:Mode() == "quest", "100 minutes and three levels on: the run ended by itself, questing from here")
  ndb.run = { started = tnow - 130 * 60, key = N2:CharKey(), level = newbie.level or 3, xp = 0, done = {}, plan = {}, mode = "rush", predicted = 0, predictedT = 0 }
  N2:ReadState()
  assert(ndb.run == nil, "two hours on: the run ended by itself")
  if newbie.env.QuestBankPost then newbie.env.QuestBankPost:Hide() end
end


-- 3.5.0: the Available tab holds still while you quest (zone by zone from the lowest), a chain opens under its
-- row, and quests done in the same spot say so
do
  local U, Dt = QB.UI, QB.Data.TEX
  -- the newbie quests: cards in level order, not by where they stand
  local N2, NU = newbie.QB, newbie.QB.UI
  NU.candMemo = nil
  NU:ShowTab(2); N2.Model.Finish(); NU:Refresh()
  local bands, prev = 0, nil
  for _, c in ipairs(NU.views[2].cards.items) do
    if c:IsShown() and c.band and c.band < 99 and c.title:GetText() ~= "Cozy Sleeping Bag" then
      assert(prev == nil or c.band >= prev - 0.5, "cards come zone by zone from the lowest level: " .. c.title:GetText())
      prev = c.band; bands = bands + 1
    end
  end
  assert(bands >= 2, "several cards to order")
  assert(NU.views[2].intro:GetText():find("zone by zone from the lowest", 1, true), "the intro says the order")
  -- a chain opens under its row
  U.candMemo = nil
  U:ShowTab(2); QB.Model.Finish(); U:Refresh()
  local v2 = U.views[2]
  local chainRow
  for _, c in ipairs(v2.cards.items) do if c:IsShown() then for _, r in ipairs(c.rows.items) do
    if r:IsShown() and r.q and r.chain:IsShown() and not chainRow then chainRow = r end
  end end end
  assert(chainRow, "a chain quest shows the toggle")
  assert(chainRow.chain.label:GetText() == "\226\150\184", "folded: a right-pointing chevron")
  local id, card = chainRow.q.id, chainRow:GetParent()
  chainRow.chain.__scripts.OnClick(chainRow.chain)
  assert(U.chainOpen and U.chainOpen[id], "the click opens it")
  local subs, headRow = 0, nil
  for _, r in ipairs(card.rows.items) do
    if r:IsShown() and r.q and r.q.id == id then headRow = r end
    if r:IsShown() and r.name:GetText():find("^\226\134\179 ") then subs = subs + 1; assert(not r.chain:IsShown(), "a step under a chain carries no toggle of its own") end
  end
  assert(subs >= 1 and headRow and headRow.chain.label:GetText() == "\226\150\190", "its steps show under the row, the chevron points down (" .. subs .. " steps)")
  lines = {}; headRow.chain.__scripts.OnEnter(headRow.chain)
  assert(lines[1] == "The chain" and lines[2]:find("fold it away", 1, true), "the toggle's tooltip")
  headRow.chain.__scripts.OnClick(headRow.chain)
  subs = 0
  for _, r in ipairs(card.rows.items) do if r:IsShown() and r.name:GetText():find("^\226\134\179 ") then subs = subs + 1 end end
  assert(subs == 0 and not (U.chainOpen and U.chainOpen[id]), "a second click folds it")
  -- quests done in the same spot: the row tooltip says so
  local items = { { q = QB.Quest.Get(7), st = { code = "todo", text = "" } }, { q = QB.Quest.Get(62), st = { code = "todo", text = "" } } }
  assert(QB.Data.OBJ and QB.Data.OBJ[7], "objective areas are in the data")
  local together
  for _, c in ipairs(v2.cards.items) do if c:IsShown() then for _, r in ipairs(c.rows.items) do
    if r:IsShown() and r.together and not together then together = r end
  end end end
  if together then
    lines = {}; together.__scripts.OnEnter(together)
    assert(table.concat(lines, "\n"):find("Done in the same spot as: ", 1, true), "the tooltip names the quests done in the same spot")
    print("together:", together.q.name, "|", table.concat(together.together, ", "))
  else
    print("together: no two shown quests share a spot in this fixture")
  end
  local before = #items
  U.Together(items)
  assert(#items == before, "Together leaves the list as it was")
end

-- 3.5.1: the Quest Log's right column is a finder: highest XP (the swaps), the best gear you can wear,
-- trinkets and jewellery, recipes
do
  local U, R = QB.UI, QB.Data.REWARD
  assert(R and next(R), "reward data is in the catalog")
  U:ShowTab(1); U:Refresh()
  assert(#v1.finds == 4, "four finder modes")
  local function mode(key) for _, b in ipairs(v1.finds) do if b.key == key then return b end end end
  local function shown() local out = {} for _, r in ipairs(v1.swaps) do if r:IsShown() then out[#out + 1] = r end end return out end
  assert(mode("xp").label:GetText() == "[Highest XP]", "the current mode is bracketed: " .. tostring(mode("xp").label:GetText()))
  for _, r in ipairs(shown()) do assert(r.gain:GetText():sub(1, 1) == "+", "the XP mode shows gains") end
  -- best gear: pieces you can wear, the highest item level first
  poke(mode("gear"))
  assert(U.findMode == "gear" and mode("gear").label:GetText() == "[Best gear]", "clicking a mode selects it")
  local rows = shown()
  assert(#rows > 0, "a level-20 paladin finds gear quests")
  local prev
  for _, r in ipairs(rows) do
    local rw = R[r.add.id]
    assert(rw and rw[2] % 2 == 1 and rw[1] > 0, "a gear row rewards a piece: " .. r.add.name)
    assert(math.floor(rw[2] / 512) % 2 == 0, "no plate before 40: " .. r.add.name)
    assert(prev == nil or rw[1] <= prev, "the highest item level first: " .. r.add.name)
    prev = rw[1]
    assert(r.gain:GetText() == "iL " .. rw[1], "the right column shows the item level: " .. r.gain:GetText())
    assert(r.cutName:GetText():find("Item " .. rw[3], 1, true), "the second line names the item: " .. r.cutName:GetText())
    assert(not QB.Quest.Behind(r.add.id), "a quest you are probably past is not offered")
    assert(not QB.state.log[r.add.id], "nor one already in your log")
  end
  lines = {}; rows[1].__scripts.OnEnter(rows[1])
  assert(table.concat(lines, "\n"):find("Rewards Item " .. R[rows[1].add.id][3] .. " (item level", 1, true), "the tooltip names the reward")
  print(string.format("finder gear: %d rows, best %s (iL %d)", #rows, rows[1].add.name, R[rows[1].add.id][1]))
  -- trinkets, rings and necklaces
  poke(mode("trinket"))
  rows = shown()
  for _, r in ipairs(rows) do
    local k = R[r.add.id][2]
    assert(math.floor(k / 2) % 2 == 1 or math.floor(k / 4) % 2 == 1, "a trinket row rewards a trinket, ring or necklace: " .. r.add.name)
  end
  print(string.format("finder trinkets: %d rows%s", #rows, rows[1] and (", first " .. rows[1].add.name) or ""))
  if #rows == 0 then assert(v1.noSwaps:IsShown() and v1.noSwaps:GetText():find("trinket", 1, true), "an empty mode says so") end
  -- recipes
  poke(mode("recipe"))
  rows = shown()
  for _, r in ipairs(rows) do assert(math.floor(R[r.add.id][2] / 8) % 2 == 1, "a recipe row rewards a recipe: " .. r.add.name) end
  print(string.format("finder recipes: %d rows%s", #rows, rows[1] and (", first " .. rows[1].add.name) or ""))
  -- a cloth wearer never sees mail
  local T2, TU = newbie.QB, newbie.QB.UI
  TU:ShowTab(1); TU.findMode = "gear"; TU:Refresh()
  for _, r in ipairs(TU.views[1].swaps) do
    if r:IsShown() then
      local k = T2.Data.REWARD[r.add.id][2]
      assert(math.floor(k / 256) % 2 == 0 and math.floor(k / 512) % 2 == 0 or math.floor(k / 64) % 2 == 1, "a priest is offered nothing in mail or plate alone: " .. r.add.name)
    end
  end
  TU.findMode = "xp"
  -- back to the swaps
  poke(mode("xp"))
  for _, r in ipairs(shown()) do assert(r.gain:GetText():sub(1, 1) == "+", "the XP mode is back") end
end

-- 3.6.0 (was 3.5.2's ForeverProbe check): QuestBank notes the client's build and interface without asking, and
-- whether the retired ForeverProbe is installed only while it is (the old Windows uploader reads that part and gives
-- advice from it); /qb probe, which the old uploader still names, says ForeverProbe is retired and where the new
-- uploader is
do
  local c, Q2 = owner, owner.QB
  local function probe()
    local n = #c.chat
    c.env.SlashCmdList.QUESTBANK("probe")
    local out = {}
    for i = n + 1, #c.chat do out[#out + 1] = c.chat[i] end
    return table.concat(out, "\n")
  end
  local UPLOADER = "The Windows uploader is QuestBank Uploader: foreverrank.com/questbank/"
  assert(c.env.QuestBankDB.diag.addons and c.env.QuestBankDB.diag.addons.qb == Q2.version, "noted at login, without asking")
  c.addons = nil
  local said = probe()
  assert(said:find(Q2.Game.RETIRED, 1, true) and said:find(UPLOADER, 1, true), "/qb probe: " .. said)
  local a = c.env.QuestBankDB.diag.addons
  assert(a and a.probe == nil and a.build == "70170" and a.iface == 16001, "no ForeverProbe: the build and interface, nothing about it")
  c.addons = { ForeverProbe = { version = "0.4.2", loaded = false, enabled = 0, reason = "DISABLED" } }
  Q2.NoteAddons()
  a = c.env.QuestBankDB.diag.addons
  assert(a.probe and a.probe.exists == true and a.probe.enabled == 0 and a.probe.reason == "DISABLED" and a.probe.loaded == false,
    "ForeverProbe still installed: the old uploader's part is there")
  c.addons.ForeverProbe = { version = "0.4.8", loaded = true, enabled = 2 }
  c.env.ForeverProbeDB = { meta = { addon = "0.4.6" } }
  said = probe()
  assert(said:find(Q2.Game.RETIRED, 1, true) and said:find(UPLOADER, 1, true) and not said:find("is running", 1, true), "loaded or not, the same answer: " .. said)
  a = c.env.QuestBankDB.diag.addons
  assert(a.probe.version == "0.4.8" and a.probe.loaded and a.probe.running == "0.4.6" and a.qb == Q2.version, "the note carries versions")
  -- a hidden character name: the per-character calls degrade, nothing throws
  local realName = c.env.UnitName
  c.env.UnitName = function() return SECRET.str() end
  said = probe()
  assert(said:find(Q2.Game.RETIRED, 1, true), "a hidden name changes nothing: " .. said)
  c.env.UnitName = realName
  -- no AddOns API at all: nobody knows, so nothing about it
  local api, info = c.env.C_AddOns, c.env.GetAddOnInfo
  c.env.C_AddOns, c.env.GetAddOnInfo = nil, nil
  said = probe()
  assert(c.env.QuestBankDB.diag.addons.probe == nil and said:find(Q2.Game.RETIRED, 1, true), "no API: nothing written, the same answer")
  c.env.C_AddOns, c.env.GetAddOnInfo = api, info
  -- nothing in the note is a name
  local function walk(t) for k, v in pairs(t) do
    if type(v) == "table" then walk(v) else
      assert(v ~= c.o.name and not tostring(v):find("Forever Normal", 1, true) and not tostring(v):find("ForeverNormal", 1, true), "no names in the note: " .. tostring(k))
    end
  end end
  walk(c.env.QuestBankDB.diag.addons)
  c.env.ForeverProbeDB = nil; c.addons = nil
  Q2.NoteAddons()
  assert(c.env.QuestBankDB.diag.addons.probe == nil, "gone again with the folder")
  print("/qb probe:", (said:gsub("\n", " | ")))
end

-- 3.5.3: a reading taken under the +3% XP buff is the game's number times 1.03 (give or take one); the addon keeps
-- the game's own number
do
  local Q2 = owner.QB
  for _, c in ipairs({ { 401, 390 }, { 236, 230 }, { 1184, 1150 }, { 1288, 1250 }, { 5665, 5500 }, { 2550, 2550 }, { 875, 875 }, { 1464, 1464 }, { 51, 50 } }) do
    assert(Q2.Unbuff(c[1]) == c[2], ("Unbuff(%d) is %d, got %s"):format(c[1], c[2], tostring(Q2.Unbuff(c[1]))))
  end
  -- a quest window under the buff is stored as the game's number
  local id
  for qid, r in pairs(Q2.Data.Q) do
    local q = Q2.Quest.Get(qid)
    if q and r[4] > 0 and q.lvl and q.lvl <= Q2.state.level and q.lvl >= Q2.state.level - 3 and Q2.Model.Listed(q) >= 1100 and Q2.Model.Listed(q) <= 4000 then id = qid; break end
  end
  assert(id, "a quest to read")
  local q = Q2.Quest.Get(id)
  local listed = Q2.Model.Listed(q)
  local before = owner.env.QuestBankDB.live and owner.env.QuestBankDB.live[id]
  Q2.Live.Record(id, math.floor(listed * 1.03), Q2.state.level, "npc")
  local rec = owner.env.QuestBankDB.live[id]
  assert(rec and rec.full == listed, ("a buffed reading of %d is kept as %d, got %s"):format(math.floor(listed * 1.03), listed, rec and rec.full or "nothing"))
  owner.env.QuestBankDB.live[id] = before
  q.liveFull = before and before.full or nil
  print("unbuff:", math.floor(listed * 1.03), "->", listed)
end

-- 3.5.4: readings saved before the buff fix are unbuffed when loaded; Grant's Shield is open to an Alliance
-- Paladin; each XP reading notes the helpful auras up, by spell id
do
  local Q2, db = owner.QB, owner.env.QuestBankDB
  local was = db.live[2924]
  db.live[2924] = { full = 5665, lvl = 29, src = "npc", at = "2026-10-02" }
  Q2.Live.Apply()
  local q = Q2.Quest.Get(2924)
  assert(q.liveFull == 5500 and db.live[2924].full == 5500, "a saved buffed reading loads as the game's number: " .. tostring(q.liveFull))
  db.live[2924] = was; q.liveFull = was and was.full or nil
  local gs = Q2.Quest.Get(79362)
  assert(gs and Q2.Quest.ForMe(gs), "an Alliance Paladin can take Grant's Shield")
  owner.auras = { 1225478, 465 }
  Q2.NoteXPSeen("detail", 2924, 5665)
  local ring = db.diag.xp
  local last = ring[#ring]
  assert(last.auras and last.auras[1] == 1225478 and last.auras[2] == 465, "the reading notes the auras up")
  owner.auras = nil
  print("auras noted:", #last.auras)
end

-- 3.5.7: reward items in game: every quest tooltip lists them (or says nobody knows them yet), the right-click menu
-- links them in chat, the finder shows a reward row's item on Shift; the quest window teaches QuestBank its rewards
do
  local Q2, D2 = owner.QB, owner.QB.Data
  assert(D2.RITEMS and D2.RUNK, "reward lists are in the catalog")
  local function tipOf(q) lines = {}; owner.env.GameTooltip:ClearLines(); Q2.UI.QuestTooltip(owner.env.GameTooltip, q, Q2:Status(q), 1000); return table.concat(lines, "\n") end
  -- a quest with known reward items: names, quality colours, "Choose one"
  local known
  for id, rw in pairs(D2.RITEMS) do if rw.c and #rw.c >= 2 and Q2.Quest.Get(id) then known = id; break end end
  local t = tipOf(Q2.Quest.Get(known))
  assert(t:find("Choose one:", 1, true) and t:find("Item " .. D2.RITEMS[known].c[1], 1, true), "the tooltip names the reward items: " .. t)
  -- a quest nobody knows the rewards of says so
  local unk
  for id in pairs(D2.RUNK) do if Q2.Quest.Get(id) then unk = id; break end end
  t = tipOf(Q2.Quest.Get(unk))
  assert(t:find("Rewards: not known yet", 1, true), "an unknown quest says so: " .. t)
  -- a quest Wowhead lists with no items
  local none
  for id in pairs(D2.Q) do if not D2.RITEMS[id] and not D2.RUNK[id] then none = id; break end end
  t = tipOf(Q2.Quest.Get(none))
  assert(t:find("No item rewards.", 1, true), "a quest with no items says so: " .. t)
  -- the quest window teaches QuestBank the rewards; an unknown quest becomes known for this player at once
  owner.window = { id = unk, xp = 0, title = "Unknown Rewards Quest", rc = { 280101, 280102 }, rr = { 280103 } }
  Q2.Discover.OnEvent("QUEST_DETAIL", 0); tick(owner, 1)
  local rw, how = Q2.Quest.Rewards(Q2.Quest.Get(unk))
  assert(how == "game" and rw.c[2] == 280102 and rw.r[1] == 280103, "the window's rewards are noted")
  t = tipOf(Q2.Quest.Get(unk))
  assert(t:find("You get:", 1, true) and t:find("As your quest window showed them", 1, true), "and shown as the game's: " .. t)
  -- a window whose item the client hasn't loaded yet is not kept half-read
  owner.window = { id = known, xp = 0, title = "Half", rc = { 1, 2 }, unloaded = { [2] = true } }
  Q2.Discover.OnEvent("QUEST_DETAIL", 0); tick(owner, 1)
  local _, how2 = Q2.Quest.Rewards(Q2.Quest.Get(known))
  assert(how2 == "catalog", "a half-read window changes nothing")
  owner.window = nil
  -- the right-click menu links each reward in chat: into the box you're typing in; with none, the link goes in the
  -- chat window for you to Shift-click once you open the box. QuestBank never opens it (ChatFrame_OpenChat, and the
  -- game's chat globals, error here)
  local function menuItem(pattern)
    Q2.UI.QuestMenu(Q2.Quest.Get(unk))
    local menu = owner.env.QuestBankMenu
    for _, b in ipairs(menu and menu.items or {}) do if b:IsShown() and (b.label and b.label:GetText() or ""):find(pattern) then return b, menu end end
    return nil, menu
  end
  local link, menu = menuItem("^Show Item 28010%d*'s link in chat$")
  assert(link, "the chat box shut: the menu offers to show a reward's link in chat")
  local said = #owner.chat
  link.__scripts.OnClick(link)
  assert(#owner.chat == said + 1 and owner.chat[#owner.chat]:find("Hitem:28010", 1, true) and owner.chat[#owner.chat]:find("press Enter to open chat, then Shift-click this link", 1, true),
    "it shows the link in the chat window, and how to put it in chat: " .. owner.chat[#owner.chat])
  print("link, chat shut:", owner.chat[#owner.chat])
  if menu then menu:Hide() end
  owner.chatOpen = true
  link, menu = menuItem("^Link Item 28010%d* in chat$")
  assert(link, "the chat box open: the menu links it")
  local nLinks = #owner.chatLinks
  link.__scripts.OnClick(link)
  assert(#owner.chatLinks == nLinks + 1 and owner.chatLinks[#owner.chatLinks]:find("Hitem:28010", 1, true), "into the box you're typing in")
  if menu then menu:Hide() end
  -- open but not typed in (the IM style leaves it so): not touched, the link shown instead
  owner.chatFocus = false
  link, menu = menuItem("^Show Item 28010%d*'s link in chat$")
  assert(link, "a box not typed in counts as shut")
  said = #owner.chat
  link.__scripts.OnClick(link)
  assert(#owner.chatLinks == nLinks + 1 and #owner.chat == said + 1, "not put in that box: shown in the chat window")
  if menu then menu:Hide() end
  owner.chatOpen, owner.chatFocus = false, nil
  -- the modern names (ChatFrameUtil), as Forever has them: InsertLink into the focused box, never OpenChat or LinkItem
  do
    local box = { HasFocus = function() return true end }
    local active
    owner.env.ChatFrameUtil = {
      GetActiveWindow = function() return active end,
      InsertLink = function(text) owner.chatLinks[#owner.chatLinks + 1] = text; return true end,
      OpenChat = function() error("QuestBank called ChatFrameUtil.OpenChat", 2) end,
      LinkItem = function() error("QuestBank called ChatFrameUtil.LinkItem", 2) end,
      ActivateChat = function() error("QuestBank called ChatFrameUtil.ActivateChat", 2) end,
    }
    said = #owner.chat
    Q2.UI.LinkItemAlways(28010)
    assert(#owner.chatLinks == nLinks + 1 and #owner.chat == said + 1, "ChatFrameUtil, no box: the link in the chat window")
    active = box
    Q2.UI.LinkItemAlways(28010)
    assert(#owner.chatLinks == nLinks + 2, "ChatFrameUtil, a box typed in: InsertLink")
    owner.env.ChatFrameUtil = nil
  end
  -- the finder: Shift over a reward row shows the item itself; Shift-click links it
  Q2.UI:ShowTab(1); Q2.UI.findMode = "gear"; Q2.UI:Refresh()
  local row
  for _, r in ipairs(Q2.UI.views[1].swaps) do if r:IsShown() and r.rewardId then row = r; break end end
  assert(row, "a gear row has a reward item")
  owner.env.IsShiftKeyDown = function() return true end
  lines = {}; row.__scripts.OnEnter(row)
  assert(lines[1] == "ITEM:" .. row.rewardId, "Shift shows the reward item's own tooltip: " .. tostring(lines[1]))
  said = #owner.chat
  row.__scripts.OnClick(row, "LeftButton")
  assert(#owner.chat == said + 1 and owner.chat[#owner.chat]:find("Hitem:" .. row.rewardId, 1, true), "Shift-click links the reward (in the chat window: the box is shut)")
  owner.chatOpen = true
  local nl = #owner.chatLinks
  row.__scripts.OnClick(row, "LeftButton")
  assert(#owner.chatLinks == nl + 1 and owner.chatLinks[#owner.chatLinks]:find("Hitem:" .. row.rewardId, 1, true), "and into the box when you're typing")
  owner.chatOpen = false
  owner.env.IsShiftKeyDown = function() return false end
  lines = {}; row.__scripts.OnEnter(row)
  assert(table.concat(lines, "\n"):find("Hold Shift to see the item", 1, true), "without Shift, the quest tooltip says how")
  Q2.UI.findMode = "xp"; Q2.UI:Refresh()
  -- a loot page's list, split unknown: "Rewards include"
  local mixed
  for id, rw in pairs(D2.RITEMS) do if rw.u and Q2.Quest.Get(id) then mixed = id; break end end
  if mixed then
    t = tipOf(Q2.Quest.Get(mixed))
    assert(t:find("Rewards include:", 1, true) and not t:find("Choose one:", 1, true), "an unsplit list is not called a choice: " .. t)
  end
  -- no quest lists the same item as given and as a choice
  for id, rw in pairs(D2.RITEMS) do
    local inC = {}
    for _, x in ipairs(rw.c or {}) do inC[x] = true end
    for _, x in ipairs(rw.r or {}) do assert(not inC[x], "item listed twice for quest " .. id) end
  end
  -- a reward row's tooltip says Shift-click links the reward, not the quest
  Q2.UI:ShowTab(1); Q2.UI.findMode = "gear"; Q2.UI:Refresh()
  for _, r in ipairs(Q2.UI.views[1].swaps) do
    if r:IsShown() and r.rewardId then
      lines = {}; r.__scripts.OnEnter(r)
      local tt = table.concat(lines, "\n")
      assert(tt:find("Shift-click: link the reward", 1, true) and not tt:find("Shift-click: put it on your pick-up list", 1, true), "one Shift-click promise: " .. tt)
      break
    end
  end
  Q2.UI.findMode = "xp"; Q2.UI:Refresh()
  print("rewards:", known, "known,", unk, "learned from the window,", none, "none,", mixed or "-", "unsplit")
end

-- 3.6.0: QuestBank takes over what ForeverProbe noted for foreverrank.com (Game.lua): per class and race the spells
-- learned and the items worn and carried, and the tooltips of weapons, armor and recipes the game shows. Only on
-- the Forever client, only with the Settings box ticked, never a name. ForeverProbe's own notes are taken over
-- once, and while it is loaded QuestBank says once a version that its folder can go.
local function names(c, t, extra)
  local bad = { c.o.name, "Forever Normal", "ForeverNormal" }
  for _, x in ipairs(extra or {}) do bad[#bad + 1] = x end
  local function walk(v, path)
    if type(v) == "table" then
      for k, x in pairs(v) do
        assert(not ({ name = 1, realm = 1, guild = 1, char = 1, zone = 1, money = 1, roster = 1, chars = 1 })[k], "no " .. tostring(k) .. " at " .. path)
        walk(x, path .. "." .. tostring(k))
      end
    elseif type(v) == "string" then
      for _, b in ipairs(bad) do assert(not v:find(b, 1, true), "no name at " .. path .. ": " .. v) end
    end
  end
  walk(t, "game")
end
local function hover(c, id) for _, fn in ipairs(c.tipHooks) do fn({}, { id = id }) end end
local function fire(c, event, ...) c.QB.Game.frame.__scripts.OnEvent(c.QB.Game.frame, event, ...) end
local function countOf(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

-- a night elf mage who ran ForeverProbe 0.4.8: its saved notes, with the names it kept, and QuestBank's own notes
-- from before (one item read at a newer build than ForeverProbe's copy, one at an older)
local ingrid = newClient({
  name = "Ingrid", level = 12, cap = 60, faction = "Alliance", className = "Mage", class = "MAGE", classID = 8, race = "NightElf",
  log = {}, done = {}, group = false, guild = false, world = { 0, 9945, 2610 }, map = 1438, bind = "Dolanaar", riding = false, xp = 100,
  bagSlots = { { 6948, 1 }, { 2070, 4 }, { 6948, 1 } }, gear = { [1] = 7413, [5] = 6096, [16] = 2132, [18] = 5071 },
  book = { { spellID = 6603, itemType = 1 }, { spellID = 20582, itemType = 1 }, { spellID = 133, itemType = 1 }, { spellID = 168, itemType = 1 },
           { spellID = 116, itemType = 1 }, { spellID = 2136, itemType = 2 }, { spellID = 543, itemType = 1, isOffSpec = true },
           { spellID = 1459, itemType = 1 }, { spellID = SECRET.num(), itemType = 1 } },
})
do
  local fpItems = {
    [280500] = { b = "70170", n = "Chrome Ring", q = 2, l = 37, r = 32, el = "INVTYPE_FINGER", c = 4, u = 0, ic = 133345, at = 1758000000, lc = "enUS", x = {} },
    [280501] = { b = "70170", n = "Older Boots", c = 4, at = 1758000000, x = { "theirs" } }, -- QuestBank read it at a newer build: stays
    [280502] = { b = "70205", n = "Newer Gloves", c = 4, at = 1758000000, x = { "theirs" } }, -- newer than QuestBank's: replaces it
    [280503] = { b = "70170", n = "Half", c = 4, at = 1758000000 },                            -- no tooltip lines: not a tooltip
  }
  for i = 1, 40 do fpItems[280500].x[i] = "line " .. i end
  for i = 1, 1100 do fpItems[300000 + i] = { b = "69000", n = "Old " .. i, c = 4, at = 1000 + i, x = {} } end
  ingrid.env.ForeverProbeDB = {
    meta = { addon = "0.4.8", greeted = "0.4.8" },
    snapshots = {
      { at = "2026-09-20T10:00:00Z", why = "login", char = "Ingrid-ForeverNormal", name = "Ingrid", realm = "Forever Normal", guild = "Order of Tests",
        level = 11, race = "NightElf", class = "MAGE", zone = "Teldrassil", version = "1.60.1", build = "70170", interface = 16001,
        spells = { 133, 116, 6603, 133 }, futureSpells = { 120 }, items = { 6948, 2070, 6948 }, money = 4200 },
      { at = "2026-09-21T09:30:00Z", why = "levelup", char = "Ingrid-ForeverNormal", name = "Ingrid", realm = "Forever Normal", guild = "Order of Tests",
        level = 12, race = "NightElf", class = "MAGE", zone = "Darnassus", version = "1.60.1", build = "70170", interface = 16001,
        spells = { 133, 116, 6603, 2136 }, items = { 6948, 7413 }, skills = { { n = "Tailoring", r = 40, m = 75 } } },
      { at = "2026-09-21T08:00:00Z", why = "login", char = "Brynja-ForeverNormal", name = "Brynja", realm = "Forever Normal",
        level = 8, race = "Dwarf", class = "WARRIOR", build = "70170", interface = 16001, spells = { 78, 6603 }, items = { 25 } },
      { at = "2026-09-21T08:05:00Z", name = "Eraone", level = 30, race = "Human", class = "PRIEST", interface = 11507, spells = { 1 }, items = {} },
      { name = "Broken", class = "MAGE" },
    },
    items = fpItems,
    trainers = { { npc = "Some Trainer", zone = "Darnassus", chars = { ["Ingrid-ForeverNormal"] = true }, services = { { n = "Frostbolt", c = 900 } } } },
    guild = { name = "Order of Tests", members = 2, roster = { { n = "Brynja-ForeverNormal", lvl = 8, on = true } } },
  }
  ingrid.env.QuestBankDB = { game = { v = 1, snap = {}, items = {
    [280501] = { b = "1.60.1.70205", at = 1757000000, n = "Older Boots", c = 4, x = { "mine" } },
    [280502] = { b = "1.60.1.70170", at = 1759000000, n = "Newer Gloves", c = 4, x = { "mine" } },
  } } }
  ingrid.addons = { ForeverProbe = { version = "0.4.8", loaded = true, enabled = 2 } }
end
login(ingrid)
do
  local c, Q2 = ingrid, ingrid.QB
  local G = Q2.Game
  local g = c.env.QuestBankDB.game
  -- the import
  assert(g and g.v == 1 and g.imported == true, "ForeverProbe's notes are taken over")
  assert(g.client == "1.60.1" and g.build == 70170 and g.iface == 16001, "the client: version, build and interface")
  local s = g.snap["MAGE/NightElf"]
  assert(s and s.level == 12 and s.class == "MAGE" and s.race == "NightElf" and s.build == 70170, "the highest-level snapshot of a class and race")
  assert(table.concat(s.spells, ",") == "116,133,2136,6603" and table.concat(s.items, ",") == "6948,7413", "its spells and items, each once and in order: "
    .. table.concat(s.spells, ",") .. " / " .. table.concat(s.items, ","))
  assert(s.at == 1789983000, "ForeverProbe's time, as seconds (2026-09-21 09:30 UTC): " .. tostring(s.at))
  local dwarf = g.snap["WARRIOR/Dwarf"]
  assert(dwarf and dwarf.level == 8 and dwarf.spells[1] == 78, "another character's class and race")
  assert(not g.snap["PRIEST/Human"] and countOf(g.snap) == 2, "a Classic Era snapshot and a broken one are left out")
  assert(g.items[280500] and g.items[280500].n == "Chrome Ring" and g.items[280500].q == 2 and #g.items[280500].x == G.MAX_LINES, "a tooltip, cut to 30 lines")
  assert(g.items[280501].x[1] == "mine" and g.items[280502].x[1] == "theirs", "the newer reading of an item wins, by build")
  assert(not g.items[280503], "a record without tooltip lines is not a tooltip")
  assert(countOf(g.items) == G.MAX_ITEMS and not g.items[300103] and g.items[300104], "over the cap the oldest go: " .. countOf(g.items))
  names(c, g, { "Brynja", "Order of Tests", "Teldrassil", "Darnassus", "Some Trainer", "Eraone" })
  -- the line about ForeverProbe: once
  local function told()
    local n = 0
    for _, line in ipairs(c.chat) do if line:find(G.RETIRED, 1, true) then n = n + 1 end end
    return n
  end
  assert(told() == 1, "ForeverProbe loaded: told once that its folder can go (" .. told() .. ")")
  assert(c.env.QuestBankDB.diag.addons.probe and c.env.QuestBankDB.diag.addons.probe.version == "0.4.8", "and noted for the old uploader while it is there")
  -- the next session: not again, and nothing imported twice
  c.env.ForeverProbeDB.items[280599] = { b = "70170", n = "Late", c = 4, at = 1758000000, x = { "late" } }
  G.Import(); G.Retire()
  assert(told() == 1 and not g.items[280599], "the next session: the line isn't said again, the notes aren't taken twice")
  -- a new QuestBank version says it once more
  local real = Q2.version
  Q2.version = real .. "-next" -- whatever comes after this one
  G.Retire(); G.Retire()
  assert(told() == 2, "a new version says it once more")
  Q2.version = real
  c.env.ForeverProbeDB, c.addons = nil, nil
  G.Retire()
  assert(told() == 2, "and nothing once ForeverProbe is gone")

  -- a reading of this character at login: its own spells and items replace the imported ones
  fire(c, "PLAYER_ENTERING_WORLD", false, false) -- a loading screen: nothing
  tick(c, 10)
  assert(g.snap["MAGE/NightElf"].spells[3] == 2136, "a loading screen takes no reading")
  fire(c, "PLAYER_ENTERING_WORLD", true, false)
  tick(c, 9)
  s = g.snap["MAGE/NightElf"]
  assert(table.concat(s.spells, ",") == "116,133,168,1459,6603,20582", "learned spells only: not the ones to come, other specs' or hidden ids: " .. table.concat(s.spells, ","))
  assert(table.concat(s.items, ",") == "2070,2132,5071,6096,6948,7413", "worn and carried, each once: " .. table.concat(s.items, ","))
  assert(s.level == 12 and s.at > 1790000000 - 400 * 86400 and s.build == 70170, "level, time and build")
  -- a level up, a lower character of the same class and race, and the logout
  c.level = 13
  fire(c, "PLAYER_LEVEL_UP", 13)
  tick(c, 3)
  assert(g.snap["MAGE/NightElf"].level == 13, "a level up takes a reading")
  c.level = 5
  G.Snap()
  assert(g.snap["MAGE/NightElf"].level == 13, "a lower character of the same class and race doesn't replace it")
  c.level = 13
  c.o.bagSlots[#c.o.bagSlots + 1] = { 4536, 2 }
  fire(c, "PLAYER_LOGOUT")
  assert(table.concat(g.snap["MAGE/NightElf"].items, ","):find("4536", 1, true), "the logout takes a reading")
  -- a hidden race: no reading
  local realRace = c.env.UnitRace
  c.env.UnitRace = function() return SECRET.str(), SECRET.str() end
  c.level = 14
  G.Snap()
  c.env.UnitRace = realRace
  assert(g.snap["MAGE/NightElf"].level == 13 and countOf(g.snap) == 2, "a hidden race is no reading")
  c.level = 13

  -- tooltips: the hook notes the id, the reading happens a moment later
  assert(#c.tipHooks == 1, "one tooltip hook")
  hover(c, 280001)
  assert(not g.items[280001], "the hook only notes the id")
  tick(c, 1)
  local it = g.items[280001]
  assert(it and it.n == "Item 280001" and it.l == 27 and it.r == 22 and it.c == 4 and it.el == "INVTYPE_CHEST" and it.b == "1.60.1.70170" and it.lc == "enUS",
    "a hovered item's tooltip is kept: " .. tostring(it and it.b))
  assert(it.x[1] == "Binds when picked up" and it.x[2] == "Chest\tCloth" and #it.x == 6, "its lines skip the name and keep the right column")
  assert(countOf(g.items) == G.MAX_ITEMS and not g.items[300104] and g.items[300105], "a full table drops its oldest for a new one")
  c.itemQuality[280004] = 0
  c.itemClass[4536] = 0
  hover(c, 280004); hover(c, 4536)
  tick(c, 1)
  assert(g.items[280004] and g.items[280004].q == 0, "a grey item stays grey (quality 0)")
  assert(not g.items[4536], "food is not kept: weapons, armor and recipes only")
  -- loot, one the client hasn't loaded yet
  c.unloaded[280003] = true
  c.loot = { 280002, 280003 }
  fire(c, "LOOT_READY")
  tick(c, 1)
  assert(g.items[280002] and not g.items[280003] and c.loadRequests[#c.loadRequests] == 280003, "loot is kept; an item not loaded yet is asked for")
  c.unloaded[280003] = nil
  fire(c, "ITEM_DATA_LOAD_RESULT", 280003, true)
  tick(c, 1)
  assert(g.items[280003], "and kept once the client has it")
  -- a quest reward (through the quest window's notes) and a vendor's wares
  c.window = { id = 7, xp = 0, title = "Kobold Camp Cleanup", rr = { 280010 } }
  Q2.Discover.OnEvent("QUEST_DETAIL", 0)
  c.window = nil
  c.merchant = { 280011 }
  fire(c, "MERCHANT_SHOW")
  tick(c, 1)
  assert(g.items[280010] and g.items[280011], "quest rewards and vendor wares are kept")
  -- a tooltip still loading, a recipe, a long tooltip
  c.tipLines[280012] = { { leftText = "Item 280012" }, { leftText = "Retrieving item information" } }
  c.itemClass[280013] = 9
  c.tipLines[280013] = { { leftText = "Item 280013" }, { leftText = "Requires Tailoring (125)" }, { leftText = "Use: Teaches you how to sew a shirt." },
    { leftText = "", type = 1 }, { leftText = "Crafted Shirt" }, { leftText = "+6 Strength" } }
  c.tipLines[280014] = {}
  for i = 1, 45 do c.tipLines[280014][i] = { leftText = "line " .. i } end
  hover(c, 280012); hover(c, 280013); hover(c, 280014)
  tick(c, 1)
  assert(not g.items[280012], "a tooltip still loading waits")
  c.tipLines[280012] = nil -- the server's text arrives
  tick(c, 4)
  assert(g.items[280012] and g.items[280012].x[1] == "Binds when picked up", "and is read once the server's text is there")
  assert(g.items[280013] and #g.items[280013].x == 2 and g.items[280013].x[2]:match("^Use:"), "a recipe keeps its own lines, not the crafted item's")
  assert(#g.items[280014].x == G.MAX_LINES, "at most 30 lines")
  -- read again after six hours, not before
  g.items[280001].x = { "kept" }
  hover(c, 280001); tick(c, 1)
  assert(g.items[280001].x[1] == "kept", "not read again within six hours")
  g.items[280001].at = g.items[280001].at - 7 * 3600
  hover(c, 280001); tick(c, 1)
  assert(g.items[280001].x[1] == "Binds when picked up", "read again after six hours")
  -- what the client hides: an id, a name, a line, a class
  for _, fn in ipairs(c.tipHooks) do fn({}, { id = SECRET.num() }) end
  c.itemName[280015] = SECRET.str()
  c.tipLines[280016] = { { leftText = "Item 280016" }, { leftText = SECRET.str() }, { leftText = "+3 Agility", rightText = SECRET.str() } }
  c.itemClass[280017] = SECRET.num()
  c.itemClass[280018] = 9
  c.tipLines[280018] = { { leftText = "Item 280018" }, { leftText = "Requires Cooking (50)", type = SECRET.num() }, { leftText = "Use: Teaches you how to cook a fish." } }
  hover(c, 280015); hover(c, 280016); hover(c, 280017); hover(c, 280018)
  tick(c, 1)
  assert(not g.items[280015] and not g.items[280017], "a hidden name or class: not kept")
  assert(g.items[280018] and #g.items[280018].x == 2, "a recipe line of a hidden kind is kept, not compared")
  assert(g.items[280016] and #g.items[280016].x == 1 and g.items[280016].x[1] == "+3 Agility", "hidden lines are left out: " .. table.concat(g.items[280016].x, " | "))
  assert(countOf(g.items) == G.MAX_ITEMS, "still at most 1000")
  -- Settings: the box, and what it stops
  Q2.UI:Open(5); Q2.UI:Refresh()
  local v5 = Q2.UI.views[5]
  assert(v5.noteGame and v5.noteGame:GetChecked() and v5.noteGame:IsEnabled() and v5.noteGame.label:GetText() == "Note items and spells you see, for foreverrank.com",
    "the Settings box, ticked by default")
  assert(v5.discText:GetText():find(", 1000 items.", 1, true) and not v5.discText:GetText():find("ForeverProbe", 1, true), "the count: " .. v5.discText:GetText())
  local lay = checkLayout(Q2.UI.frame, "settings with the item notes")
  assert(#lay == 0, "the Discoveries part fits: " .. table.concat(lay, "; "))
  local sf = v5.scroll
  local _, hi = sf.bar:GetMinMaxValues()
  sf.bar:SetValue(hi); Q2.UI:Refresh()
  lay = checkLayout(Q2.UI.frame, "settings with the item notes, scrolled")
  assert(#lay == 0, "and scrolled: " .. table.concat(lay, "; "))
  sf.bar:SetValue(0)
  c.env.SlashCmdList.QUESTBANK("discoveries")
  local said = c.chat[#c.chat]
  assert(said:find("1000 items, 2 spellbooks", 1, true) and not said:find("ForeverProbe", 1, true), "/qb discoveries counts them: " .. said)
  names(c, g, { "Brynja", "Order of Tests", "Teldrassil", "Darnassus" })
  local summary = string.format("item notes: %d tooltips, %d spellbooks; %s", countOf(g.items), countOf(g.snap), said:match("so far: (.-)%. They") or said)
  -- unticked: what was noted goes (QuestBank.lua is uploaded whole, and the box is the say over what the site gets),
  -- and nothing new is noted
  v5.noteGame:SetChecked(false); v5.noteGame.__scripts.OnClick(v5.noteGame, "LeftButton")
  assert(Q2:Settings().noteGame == false and c.env.QuestBankDB.game == nil and not v5.discText:GetText():find("items", 1, true),
    "unticked: the notes are cleared")
  hover(c, 280030); tick(c, 1)
  c.level = 20
  G.Snap()
  fire(c, "PLAYER_ENTERING_WORLD", true, false); tick(c, 9)
  fire(c, "PLAYER_LOGOUT")
  assert(c.env.QuestBankDB.game == nil, "unticked: nothing is noted")
  c.env.SlashCmdList.QUESTBANK("discoveries")
  assert(not c.chat[#c.chat]:find("items", 1, true), "/qb discoveries leaves them out: " .. c.chat[#c.chat])
  -- ticked again: noting starts over
  v5.noteGame:SetChecked(true); v5.noteGame.__scripts.OnClick(v5.noteGame, "LeftButton")
  local g2 = c.env.QuestBankDB.game
  assert(Q2:Settings().noteGame == true and g2 and g2.v == 1 and g2.iface == 16001 and countOf(g2.items) == 0 and countOf(g2.snap) == 0,
    "ticked again: a fresh start")
  c.level = 13
  hover(c, 280030); tick(c, 1)
  G.Snap()
  assert(g2.items[280030] and g2.snap["MAGE/NightElf"] and g2.snap["MAGE/NightElf"].level == 13, "and noting again")
  c.env.SlashCmdList.QUESTBANK("discoveries")
  assert(c.chat[#c.chat]:find("1 item, 1 spellbook", 1, true), "/qb discoveries counts again: " .. c.chat[#c.chat])
  Q2.UI.frame:Hide()
  names(c, g2)
  print(summary)
end

-- the box unticked while ForeverProbe is still loaded: nothing is taken over and the line about its folder waits
-- (deleting it then would lose its notes), also when the import fails; ticking the box takes them over and says it
local solveig = newClient({
  name = "Solveig", level = 7, cap = 60, faction = "Alliance", className = "Priest", class = "PRIEST", classID = 5, race = "Human",
  log = {}, done = {}, group = false, guild = false, world = { 0, -8914, -133 }, bind = "Northshire Abbey", riding = false, xp = 50,
  bagSlots = { { 6098, 1 } }, gear = { [5] = 6098 }, book = { { spellID = 585, itemType = 1 }, { spellID = 2050, itemType = 1 } },
})
solveig.env.QuestBankDB = { settings = { noteGame = false } }
solveig.env.ForeverProbeDB = {
  meta = { addon = "0.4.8" },
  snapshots = { { at = "2026-09-22T18:00:00Z", name = "Solveig", realm = "Forever Normal", guild = "Order of Tests", level = 6, race = "Human",
                  class = "PRIEST", build = "70170", interface = 16001, spells = { 585, 2050 }, items = { 6098 } } },
  items = { [280800] = { b = "70170", n = "Priestly Gloves", c = 4, at = 1758000000, x = { "Binds when equipped" } } },
}
solveig.addons = { ForeverProbe = { version = "0.4.8", loaded = true, enabled = 2 } }
login(solveig)
do
  local c, Q2 = solveig, solveig.QB
  local G = Q2.Game
  local function told()
    local n = 0
    for _, line in ipairs(c.chat) do if line:find(G.RETIRED, 1, true) then n = n + 1 end end
    return n
  end
  tick(c, 10)
  assert(c.env.QuestBankDB.game == nil and told() == 0 and c.env.QuestBankDB.settings.toldRetired == nil,
    "unticked: nothing taken over, and nothing said about ForeverProbe's folder")
  Q2.UI:Open(5); Q2.UI:Refresh()
  local v5 = Q2.UI.views[5]
  assert(v5.noteGame:IsEnabled() and not v5.noteGame:GetChecked(), "the box shows it unticked")
  -- ticked, but the import fails: still nothing said
  local realImport = G.Import
  G.Import = function() error("test: the import fails") end
  c.env.QUESTBANK_DEV = false
  v5.noteGame:SetChecked(true); v5.noteGame.__scripts.OnClick(v5.noteGame, "LeftButton")
  c.env.QUESTBANK_DEV = true
  G.Import = realImport
  local g = c.env.QuestBankDB.game
  assert(g and not g.imported and told() == 0, "the import failed: nothing said")
  local errs = c.env.QuestBankDB.errors
  assert(errs and errs[1] and errs[1].msg:find("the import fails", 1, true), "and the error is noted")
  -- unticked and ticked again: taken over, then said once
  v5.noteGame:SetChecked(false); v5.noteGame.__scripts.OnClick(v5.noteGame, "LeftButton")
  v5.noteGame:SetChecked(true); v5.noteGame.__scripts.OnClick(v5.noteGame, "LeftButton")
  g = c.env.QuestBankDB.game
  local s = g and g.snap["PRIEST/Human"]
  assert(g and g.imported and g.items[280800] and s and s.level == 6 and table.concat(s.spells, ",") == "585,2050",
    "ticked: ForeverProbe's notes are taken over")
  assert(told() == 1, "and then the line about its folder, once (" .. told() .. ")")
  G.Import(); G.Retire()
  assert(told() == 1, "not twice")
  names(c, g, { "Order of Tests" })
  Q2.UI.frame:Hide()
  print("unticked:", "nothing taken over until the box is ticked, then told " .. told() .. " time")
end

-- Classic Era (QuestBank runs there too): the game notes stay off, and the quest notes say which client wrote them
local sigrun = newClient({
  name = "Sigrun", level = 10, cap = 60, faction = "Alliance", className = "Warrior", class = "WARRIOR", classID = 1, race = "Dwarf",
  log = {}, done = {}, group = false, guild = false, world = { 0, -6240, 330 }, bind = "Kharanos", riding = false, xp = 50,
  bagSlots = { { 25, 1 } }, gear = { [16] = 25 },
})
sigrun.env.GetBuildInfo = function() return "1.15.7", "63696", "Sep 1 2026", 11507 end
sigrun.env.ForeverProbeDB = { meta = { addon = "0.4.8" }, snapshots = { { class = "WARRIOR", race = "Dwarf", level = 9, spells = { 78 }, items = { 25 } } },
  items = { [280700] = { b = "63696", n = "Era Item", c = 4, at = 1, x = { "x" } } } }
login(sigrun)
do
  local c, Q2 = sigrun, sigrun.QB
  local G = Q2.Game
  assert(not G.Forever() and not G.On() and #c.tipHooks == 0, "Classic Era: not the Forever client, no tooltip hook")
  G.Snap(); G.Want(280001); G.Import()
  G.OnEvent("PLAYER_ENTERING_WORLD", true, false); G.OnEvent("PLAYER_LOGOUT")
  c.loot = { 280002 }
  G.OnEvent("LOOT_READY")
  tick(c, 10)
  assert(c.env.QuestBankDB.game == nil, "nothing written: QuestBankDB.game isn't touched")
  local d = c.env.QuestBankDB.disc
  assert(d and d.iface == 11507 and d.build == "63696", "the quest notes say which client wrote them")
  assert(owner.env.QuestBankDB.disc.iface == 16001, "and on Forever: " .. tostring(owner.env.QuestBankDB.disc.iface))
  assert(c.env.QuestBankDB.diag.addons.iface == 11507 and c.env.QuestBankDB.diag.addons.probe == nil, "the client's stamps, and nothing about ForeverProbe")
  Q2.UI:Open(5); Q2.UI:Refresh()
  local v5 = Q2.UI.views[5]
  assert(not v5.noteGame:IsEnabled() and not v5.noteGame:GetChecked() and v5.noteGame.label:GetText():find("Forever client only", 1, true)
    and not v5.discText:GetText():find("items", 1, true), "the Settings box is greyed out here, and says why")
  assert(not v5.mapIcons:IsEnabled() and not v5.mapIcons:GetChecked() and v5.mapIcons.label:GetText():find("Forever client only", 1, true)
    and not v5.mapGive:IsEnabled() and not v5.mapTurn:IsEnabled() and not v5.mapObj:IsEnabled(), "the map icon rows are greyed out here, and say why")
  for _, pr in ipairs(checkLayout(Q2.UI.frame, "settings on Classic Era")) do problems[#problems + 1] = pr end
  layouts[#layouts + 1] = dumpLayout(Q2.UI.frame, "Settings on Classic Era")
  Q2.UI.frame:Hide()
  -- the map icons: not on this client. No provider, nothing drawn, and the client's missing map calls don't matter
  local QMe = Q2.QuestMap
  c.env.C_Map.GetMapInfo = nil
  c.map.id = 1426
  Q2:Changed(); c.map:RefreshAll()
  assert(not QMe.provider and #QMe:Build(1426) == 0 and not QMe.Draws(1426) and #ours(c, "QuestBankQuestPinTemplate") == 0,
    "Classic Era: no map icons")
  local said = #c.chat
  c.env.SlashCmdList.QUESTBANK("icons")
  assert(#c.chat == said + 1 and c.chat[#c.chat]:find("need the Forever client", 1, true) and Q2:Settings().mapIcons == true, "/qb icons says why, and leaves the switch")
  c.env.SlashCmdList.QUESTBANK("discoveries")
  assert(not c.chat[#c.chat]:find("items", 1, true), "/qb discoveries: quests and NPCs only")
  -- ForeverProbe loaded here: nothing of it is taken over on this client, so the line about its folder is said
  c.addons = { ForeverProbe = { version = "0.4.8", loaded = true, enabled = 2 } }
  G.Retire(); G.Retire()
  local n = 0
  for _, line in ipairs(c.chat) do if line:find(G.RETIRED, 1, true) then n = n + 1 end end
  assert(n == 1 and c.env.QuestBankDB.game == nil, "Classic Era with ForeverProbe loaded: told once, nothing written")
  c.addons = nil
  print("classic era:", "no game notes; disc.iface " .. tostring(d.iface))
end


----------------------------------------------------------------------------
-- map icons (QuestMap.lua): a level 3 human priest in Elwynn on the Forever client. The spots are injected here
-- (gen_data builds the real ones); the givers and hand-ins are the catalog's own
----------------------------------------------------------------------------
local maren = newClient({
  name = "Maren", level = 3, cap = 60, faction = "Alliance", className = "Priest", class = "PRIEST", classID = 5, race = "Human",
  log = { { 7, 0 }, { 33, 1 }, { 18, 0 } }, done = { [783] = true, [5261] = true }, group = false, guild = false,
  world = { 0, -8914, -133 }, bind = "Northshire Abbey", riding = false, bagSlots = {}, xp = 900, map = 1429,
})
maren.map.id = 1429
do
  local M, MQ = maren, maren.QB
  local MD = MQ.Data
  local QMm = MQ.QuestMap
  local SPOT = {
    [7] = "k,1,1429,483,397,25,c,1;k,1,1429,470,350,30,p,1;u,2,1429,450,380,0,g,4",
    [18] = "c,5,1429,540,300,40,w,2;c,6,1429,560,320,0,g,3;c,5,1453,500,500,20,w,2",
    [33] = "k,1,1429,600,600,30,c,1", -- complete: none of its spots show
  }
  local function inject()
    MD.SN = { [1] = "Kobold Vermin", [2] = "Red Burlap Bandana", [3] = "Defias Mask", [4] = "Stolen Crate", [5] = "Northshire Gift Voucher" }
    MD.SPOT, MD.SREQ = {}, { [7] = "1:10,2:1", [18] = "5:12,6:12", [33] = "1:8" }
    for k, v in pairs(SPOT) do MD.SPOT[k] = v end
    MD.START = { [5805] = "s,0,1429,420,640,20,w,5;s,0,1453,100,100,20,c,5" }
  end
  inject()
  M.objectives = {
    [7] = { { text = "Kobold Vermin slain: 3/10", type = "monster", finished = false, numFulfilled = 3, numRequired = 10 } },
    -- the game lists them the other way round, and the masks are done
    [18] = { { text = "Defias Mask: 12/12", type = "item", finished = true, numFulfilled = 12, numRequired = 12 },
             { text = "Red Burlap Bandana: 2/12", type = "item", finished = false, numFulfilled = 2, numRequired = 12 } },
  }
  login(M)
  assert(QMm.provider, "on Forever the icons have their own provider on the world map")
  assert(#MQ.Pins.layers == 2 and MQ.Pins.watcher and MQ.Pins.watcher.__parent == M.map:GetCanvas(),
    "no hook on the world map (the mock's HookScript errors): both layers hear it shut as its providers, and a frame of QuestBank's on its canvas watches the keys")
  local function redraw()
    MQ:Recompute(true); MQ.Model.Finish(); MQ.Pins:Update(); QMm:Update()
  end
  local function icons(kind)
    local out = {}
    for _, pin in ipairs(ours(M, "QuestBankQuestPinTemplate")) do
      if not kind or pin.data.kind == kind then out[#out + 1] = pin end
    end
    return out
  end
  local function areas() return ours(M, "QuestBankAreaPinTemplate") end
  local function routePins() return ours(M, "QuestBankPinTemplate") end
  local function tipOf(pin) lines = {}; pin:OnMouseEnter(); pin:OnMouseLeave(); return table.concat(lines, "\n") end
  local function marksFor(id) local n = 0; for _, pin in ipairs(icons("obj")) do if pin.data.id == id then n = n + 1 end end return n end
  local function near(pin, x, y) return math.abs(pin.mapX - x) < 1e-6 and math.abs(pin.mapY - y) < 1e-6 end

  -- the route's own pins off first: this layer then draws every NPC itself
  MQ:Settings().pins = false
  redraw()
  local give, turn, obj, start = icons("give"), icons("turn"), icons("obj"), icons("start")
  print(string.format("map icons, Elwynn at level 3: %d !, %d ?, %d objective marks, %d item drops, %d areas", #give, #turn, #obj, #start, #areas()))
  assert(#give > 0 and #turn == 1 and #obj == 4 and #start == 1 and #areas() == 4, "the ! , ? , objectives and the item drop are all there")
  -- ! only for quests you can take now: todo, not in the log, not done, for your side; under the route pins
  for _, pin in ipairs(give) do
    assert(pin.levelType == "PIN_FRAME_LEVEL_INVASION" and pin.__frameLevel == M.map.levels.PIN_FRAME_LEVEL_INVASION and pin.Icon.__atlas == "QuestNormal",
      "a ! is the game's own, below the route pins")
    for _, q in ipairs(pin.data.quests) do
      local st = MQ:Status(q)
      assert(st.code == "todo" and not st.behind, "a ! only for a quest you can take now: " .. q.name .. " (" .. st.code .. ")")
      assert(not MQ.state.log[q.id] and not M.done[q.id] and q.side ~= 2, "never one in the log, done or Horde: " .. q.name)
    end
  end
  -- ? where Wolves Across the Border goes, at Eagan Peltskinner's own spot
  local eagan = turn[1]
  assert(eagan.data.title == "Eagan Peltskinner" and eagan.data.quests[1].id == 33 and near(eagan, 0.489, 0.402) and eagan.Icon.__atlas == "QuestTurnin",
    "a ? where the finished quest is handed in: " .. tostring(eagan.data.title))
  -- objectives: Kobold Vermin's two areas and the crate no line of the game's fits; the bandanas, not the finished masks
  assert(marksFor(7) == 3 and marksFor(18) == 1 and marksFor(33) == 0, "the marks: 3 for Kobold Camp Cleanup, 1 for the bandanas, none for a complete quest")
  for _, pin in ipairs(obj) do
    assert(pin.levelType == "PIN_FRAME_LEVEL_DIG_SITE" and pin.__frameLevel == M.map.levels.PIN_FRAME_LEVEL_DIG_SITE, "objective marks sit under the ! and ?")
    if pin.data.id == 18 then assert(pin.data.spot.name == 2 and near(pin, 0.54, 0.30), "the bandanas' spot, not the finished masks'") end
  end
  for _, a in ipairs(areas()) do
    assert(a.levelType == "PIN_FRAME_LEVEL_QUEST_BLOB" and a.__frameLevel == M.map.levels.PIN_FRAME_LEVEL_QUEST_BLOB and a.__scale == nil and a.__mouse == false,
      "an area grows with the map, under every icon, no mouse")
    assert(math.abs(a.__w - 2 * a.data.r * 1002) < 1e-6, "an area is as wide as the ground it covers: " .. a.__w)
  end
  -- the item that starts Welcome! (from a Northshire Gift Voucher): where it drops, with the game's ! on the mark
  assert(MQ:Status(MQ.Quest.Get(5805)).code == "item", "Welcome! starts from an item for Maren")
  assert(start[1].data.id == 5805 and near(start[1], 0.42, 0.64) and start[1].Badge:IsShown(), "where the item that starts a quest drops")
  -- tooltips say what and where from
  local t7 = tipOf(icons("obj")[1])
  assert(t7:find("Kobold Camp Cleanup", 1, true) and t7:find("Kill Kobold Vermin", 1, true) and t7:find("Kobold Vermin slain: 3/10", 1, true)
    and t7:find("Position: Classic data (may have moved in Forever)", 1, true) and t7:find("Click: waypoint.", 1, true) and not t7:find("Shift-click", 1, true),
    "the kill mark's tooltip: " .. t7)
  local sources = {}
  for _, pin in ipairs(icons()) do
    local t = tipOf(pin)
    assert(#t > 0 and t:find("Click: waypoint", 1, true), "every icon has a tooltip")
    for _, src in pairs(QMm.SOURCE) do if t:find("Position: " .. src, 1, true) then sources[src] = true end end
  end
  assert(sources["Wowhead Forever"] and sources["seen in players' games"] and sources["Classic data (may have moved in Forever)"], "tooltips name all three sources")
  local tStart = tipOf(start[1])
  assert(tStart:find("Northshire Gift Voucher", 1, true) and tStart:find("Drops here, and starts:\n[1] Welcome!", 1, true), "the drop's tooltip names the item and the quest: " .. tStart)
  print("map icon tooltip:", (t7:gsub("\n", " | ")))
  print("map icon tooltip, !:", (tipOf(give[1]):gsub("\n", " | ")))
  print("map icon tooltip, ?:", (tipOf(eagan):gsub("\n", " | ")))
  print("map icon tooltip, drop:", (tStart:gsub("\n", " | ")))
  -- left click: the arrow points there at once, and a chat line carries the game's map-pin link; the game's own
  -- waypoint is never set from QuestBank's code (C_Map.SetUserWaypoint errors here), map open or shut, in combat or not
  local function lastLine() return M.chat[#M.chat] or "" end
  local mark = icons("obj")[1]
  local said = #M.chat
  mark:OnMouseClickAction("LeftButton")
  assert(#M.chat == said + 1 and lastLine():find("Waypoint: Kobold Camp Cleanup: Kobold Vermin (48, 40).", 1, true)
    and lastLine():find("|Hworldmap:1429:4830:3970|h", 1, true) and #M.pins == 0,
    "a click with the map open: a waypoint line with the map-pin link, nothing set by QuestBank: " .. lastLine())
  assert(MQ:Settings().arrowPin and MQ:Settings().arrowPin.name == "Kobold Camp Cleanup: Kobold Vermin", "the arrow points there")
  local wp = clickMapLink(M, lastLine())
  assert(wp and wp.m == 1429 and math.abs(wp.x - 0.483) < 1e-6 and math.abs(wp.y - 0.397) < 1e-6, "the link's click: the game's pin on the mark")
  said = #M.chat
  icons("obj")[1]:OnMouseClickAction("RightButton")
  assert(#M.chat == said, "a right-click is the map's (zoom out)")
  -- the frames' own mouse scripts: let go over an icon is a click, let go elsewhere is not
  mark = icons("obj")[1]
  assert(mark.__scripts.OnEnter and mark.__scripts.OnLeave and mark.__scripts.OnMouseUp, "QuestBank's frames have their own mouse scripts")
  lines = {}; mark.__scripts.OnEnter(mark); assert(#lines > 0, "hovering shows the tooltip"); mark.__scripts.OnLeave(mark)
  mark.__scripts.OnMouseUp(mark, "LeftButton", false)
  assert(#M.chat == said, "let go outside the icon: no click")
  mark.__scripts.OnMouseUp(mark, "LeftButton", true)
  assert(#M.chat == said + 1 and lastLine():find("worldmap:", 1, true), "let go over it: a click")
  -- /qb next: the next stop's line and link, the map open or not
  said = #M.chat
  MQ.Pins:PinNext(true)
  assert(#M.chat == said + 1 and (lastLine():find("worldmap:", 1, true) or lastLine():find("Nothing on the route", 1, true)), "/qb next: " .. lastLine())
  -- in combat, the map shut or open: the same, at once
  M.map:Close()
  M.combat = true
  MQ.API.SetWaypoint(1429, 40, 50, "Test spot")
  assert(lastLine():find("|Hworldmap:1429:4000:5000|h", 1, true) and #M.pins == 1, "in combat, the map shut: the line at once, nothing set")
  M.map:Open()
  MQ.API.SetWaypoint(1429, 41, 51, "Test spot")
  assert(lastLine():find("|Hworldmap:1429:4100:5100|h", 1, true) and #M.pins == 1, "in combat, the map open: the same")
  M.combat = false
  MQ.Pins.combatFrame.__scripts.OnEvent(MQ.Pins.combatFrame, "PLAYER_REGEN_ENABLED")
  assert(#M.pins == 1, "and nothing set when combat ends either")
  -- the same frames again, drawn for the map now open
  give, turn, obj, start = icons("give"), icons("turn"), icons("obj"), icons("start")
  eagan = turn[1]
  mark = icons("obj")[1]
  -- Shift-click on a mark or a ?: the game's tracker is left alone (C_QuestLog.AddQuestWatch errors here); a waypoint
  M.shift = true
  said = #M.chat
  mark:OnMouseClickAction("LeftButton")
  assert(#M.chat == said + 1 and lastLine():find("worldmap:", 1, true) and not M.watched, "Shift-click on an objective: a waypoint, the game's tracker untouched")
  eagan:OnMouseClickAction("LeftButton")
  assert(not M.watched and #tipOf(eagan) > 0 and not tipOf(eagan):find("Shift-click", 1, true), "and on a ?: no Shift-click promised")
  M.map:Close(); M.map:Open()
  give, turn, obj, start = icons("give"), icons("turn"), icons("obj"), icons("start")
  eagan = turn[1]
  -- Shift-click on a !: the pick-up list, and the route's own ! takes over that NPC
  local g = give[1]
  local gd = g.data -- (the frame itself is drawn again for whatever comes next)
  local gid = gd.quests[1].id
  assert(not MQ:IsAdded(gid), "not on the pick-up list yet")
  g:OnMouseClickAction("LeftButton")
  M.shift = false
  assert(MQ:IsAdded(gid) and M.chat[#M.chat]:find("On your pick-up list", 1, true), "Shift-click on a ! puts its quests on the pick-up list")
  MQ:Settings().pins = true
  redraw()
  local routed = false
  for _, r in ipairs(MQ.Pins.list) do if r.name == gd.title then routed = true end end
  assert(routed, "the route's pins show that ! now")
  for _, pin in ipairs(icons("give")) do assert(pin.data.title ~= gd.title, "and the map icons leave that NPC to them") end
  -- with the route's pins on, a hand-in on the route is theirs too
  -- (a stop is named for its place when NPCs share it: "Elwynn Forest (49, 40)"; it stands where Eagan does)
  local eaganOnRoute = false
  for _, r in ipairs(MQ.Pins.list) do if r.num and r.m == 1429 and math.abs(r.x - 48.9) < 0.6 and math.abs(r.y - 40.2) < 0.6 then eaganOnRoute = true end end
  assert(eaganOnRoute and #icons("turn") == 0, "the route stands on Eagan: no second ? there")
  for _, id in ipairs(gd.quests) do if MQ:IsAdded(id.id) then MQ:ToggleAdd(id.id) end end
  MQ:Settings().pins = false
  redraw()
  assert(#icons("give") == #give and #icons("turn") == 1, "off the list and the route pins off: as before")

  -- each switch takes its own kind away and leaves the route's pins be
  MQ:Settings().pins = true
  redraw()
  local nRoute = #routePins()
  local function counts() return #icons("give"), #icons("turn"), #icons("obj") + #icons("start"), #areas() end
  local g0, t0, o0, a0 = counts()
  QMm.Set("mapGive", false)
  local g1, t1, o1, a1 = counts()
  assert(g1 == 0 and t1 == t0 and o1 == o0 and a1 == a0 and #routePins() == nRoute, "no ! with Quests you can pick up off")
  QMm.Set("mapGive", true); QMm.Set("mapObj", false)
  g1, t1, o1, a1 = counts()
  assert(g1 == g0 and o1 == 0 and a1 == 0 and #routePins() == nRoute, "no objectives, drops or areas with Objectives and quest items off")
  QMm.Set("mapObj", true)
  M.env.SlashCmdList.QUESTBANK("icons")
  assert(MQ:Settings().mapIcons == false and #icons() == 0 and #areas() == 0 and #routePins() == nRoute and M.chat[#M.chat]:find("off", 1, true), "/qb icons: all off, the route's pins stay")
  M.env.SlashCmdList.QUESTBANK("icons")
  g1, t1, o1, a1 = counts()
  assert(MQ:Settings().mapIcons and g1 == g0 and o1 == o0 and a1 == a0, "/qb icons: back on")
  -- the Settings page: four rows, the three kinds greyed out while the master is off
  MQ.UI:Open(5); MQ.Model.Finish(); MQ.UI:Refresh()
  local v5 = MQ.UI.views[5]
  assert(v5.mapIcons:IsEnabled() and v5.mapIcons:GetChecked() and v5.mapGive:GetChecked() and v5.mapTurn:GetChecked() and v5.mapObj:GetChecked(), "all four on by default")
  v5.mapTurn:SetChecked(false); v5.mapTurn.__scripts.OnClick(v5.mapTurn, "LeftButton")
  assert(MQ:Settings().mapTurn == false and #icons("turn") == 0 and #icons("give") > 0, "Hand-ins off from Settings")
  v5.mapTurn:SetChecked(true); v5.mapTurn.__scripts.OnClick(v5.mapTurn, "LeftButton")
  v5.mapIcons:SetChecked(false); v5.mapIcons.__scripts.OnClick(v5.mapIcons, "LeftButton")
  assert(MQ:Settings().mapIcons == false and #icons() == 0 and not v5.mapGive:IsEnabled() and v5.mapGive:GetChecked(), "master off: no icons, the kinds greyed out and kept")
  for _, pr in ipairs(checkLayout(MQ.UI.frame, "map icons: settings, master off")) do problems[#problems + 1] = pr end
  v5.mapIcons:SetChecked(true); v5.mapIcons.__scripts.OnClick(v5.mapIcons, "LeftButton")
  assert(v5.mapGive:IsEnabled() and #icons("give") == g0, "and back")
  for _, row in ipairs({ v5.mapIcons, v5.mapGive, v5.mapTurn, v5.mapObj }) do lines = {}; row.__scripts.OnEnter(row); assert(#lines > 0) end
  for _, pr in ipairs(checkLayout(MQ.UI.frame, "map icons: settings")) do problems[#problems + 1] = pr end
  MQ.UI.frame:Hide()

  -- objectives finish: their marks go; a slot no line of the game's fits stays until the quest is complete
  M.objectives[7][1] = { text = "Kobold Vermin slain: 10/10", type = "monster", finished = true, numFulfilled = 10, numRequired = 10 }
  redraw()
  assert(marksFor(7) == 1, "Kobold Vermin done: only the crate stays (no line of the game's fits it)")
  M.log[1] = { 7, 1 }
  MQ:Settings().pins = false
  redraw()
  local mcbride
  for _, pin in ipairs(icons("turn")) do if pin.data.title == "Marshal McBride" then mcbride = pin end end
  assert(marksFor(7) == 0 and mcbride, "complete: its marks go, and a ? stands at Marshal McBride")
  for _, pin in ipairs(icons("give")) do assert(pin.data.title ~= "Marshal McBride", "one icon per NPC: his ! goes on the ?") end
  if mcbride.data.offers then assert(tipOf(mcbride):find("Also to pick up:", 1, true), "and its tooltip lists them") end
  M.log[1] = { 7, 0 }
  M.objectives[7][1] = { text = "Kobold Vermin slain: 3/10", type = "monster", finished = false, numFulfilled = 3, numRequired = 10 }
  redraw()
  assert(marksFor(7) == 3, "back as it was")

  -- matching the game's lines: kind and count, then the name, then the name alone when the count changed
  do
    local list = QMm.Spots("k,1,1429,1,1,0,c,1;k,2,1429,1,1,0,c,6;c,5,1429,1,1,0,c,2")
    MD.SN[6] = "Kobold Worker"
    local objs = {
      { text = "Kobold Worker slain: 0/10", type = "monster", need = 10, done = true },
      { text = "Kobold Vermin slain: 2/10", type = "monster", need = 10, done = false },
      { text = "Red Burlap Bandana: 0/8", type = "item", need = 8, done = false },
    }
    local m = QMm.Match(objs, list, { [1] = 10, [2] = 10, [5] = 12 })
    assert(m[1] == objs[2] and m[2] == objs[1], "two kills of ten: told apart by name")
    assert(m[5] == objs[3], "the bandanas: the count changed, the name still fits")
    m = QMm.Match({ { text = "Something else", type = "event", need = 1 } }, list, { [1] = 10, [2] = 10, [5] = 12 })
    assert(next(m) == nil, "nothing fits: nothing matched, so the spots keep showing")
  end
  -- grey quests: the game's own range when the client says, else Classic's rule
  do
    local Qg = { lvl = 13 }
    assert(QMm.Grey(Qg, 20) and not QMm.Grey({ lvl = 14 }, 20) and not QMm.Grey({ lvl = 1 }, 5), "Classic: grey from 7 levels below at 20, never at 5")
    M.env.UnitQuestTrivialLevelRange = function() return 5 end
    assert(QMm.Grey({ lvl = 14 }, 20) and not QMm.Grey({ lvl = 15 }, 20), "the client's range when it gives one")
    M.env.UnitQuestTrivialLevelRange = nil
  end

  -- only zone maps (and Zephras Isle): not a continent; a spot is drawn on its own map only
  M.map:SetMapID(1415)
  assert(#icons() == 0 and #areas() == 0, "no icons on a continent")
  M.mapTypes = { [2521] = 6 }
  MD.SPOT[18] = SPOT[18] .. ";c,5,2521,300,300,10,w,2"
  M.map:SetMapID(2521)
  assert(#icons("obj") == 1 and icons("obj")[1].data.id == 18 and #icons("give") == 0, "Zephras Isle draws its own spots")
  M.map:SetMapID(1453)
  for _, pin in ipairs(icons("obj")) do assert(pin.data.id == 18 and near(pin, 0.5, 0.5), "Stormwind: the spot tagged to Stormwind") end
  MD.SPOT[18] = SPOT[18]
  M.map:SetMapID(1429)
  assert(#icons("obj") == 4, "back on Elwynn")
  -- a hidden map builds nothing
  M.map.shown = false
  local draws = QMm.provider.draws
  redraw()
  assert(QMm.provider.draws == draws, "a hidden map builds nothing")
  M.map.shown = true
  redraw()

  -- QuestBank's own frames: on the canvas, at the map's frame level for their kind, placed and scaled as the map's
  -- own pins are, a right-click passing through to the map; never the canvas's pins (the mock's AcquirePin, its
  -- RemoveAllPinsByTemplate and the scroll container's MarkCanvasDirty error)
  MQ:Settings().pins = true
  redraw()
  local canvas = M.map:GetCanvas()
  assert(#routePins() > 0 and #icons() > 0 and #areas() > 0, "all three kinds drawn")
  for _, f in ipairs(ours(M)) do
    assert(f.__parent == canvas and f.__frameLevel == M.map.levels[f.levelType], "on the canvas at its level: " .. tostring(f.levelType))
    if f.kind.mouse then
      assert(f.__mouse and f.__passThrough and f.__passThrough[1] == "RightButton", "a right-click passes through to zoom the map out")
    else
      assert(f.__mouse == false and not f.__passThrough, "an area takes no mouse")
    end
  end
  -- zoomed halfway in on a canvas at twice its scale: as MapCanvasPinMixin:ApplyCurrentScale and ApplyPinPosition would
  M.map:Zoom(2, 0.5)
  local function placed(f, scale)
    local pt = f.__points[1]
    return #f.__points == 1 and pt.point == "CENTER" and pt.rel == canvas and pt.relPoint == "TOPLEFT"
      and math.abs(pt.x - 1002 * f.mapX / scale) < 1e-6 and math.abs(pt.y + 668 * f.mapY / scale) < 1e-6
  end
  local ic, rp, ar = icons("give")[1], routePins()[1], areas()[1]
  local s1, s2 = (1 + 0.2 * 0.5) / 2, (1 + 0.25 * 0.5) / 2
  assert(math.abs(ic.__scale - s1) < 1e-9 and placed(ic, s1), "an icon: smaller against the canvas zoom, a little bigger zoomed in")
  assert(math.abs(rp.__scale - s2) < 1e-9 and placed(rp, s2), "a route pin: the same, a little bigger again")
  assert(ar.__scale == nil and placed(ar, 1) and math.abs(ar.__w - 2 * ar.data.r * 1002) < 1e-6, "an area keeps the terrain's scale")
  M.map:Zoom(1, 0)
  assert(math.abs(ic.__scale - 1) < 1e-9 and placed(ic, 1), "zoomed out again")

  -- combat: nothing made or drawn (SetPassThroughButtons errors in combat here, as the game's restricted call is
  -- blocked); a redraw waits for the end of combat; zooming still moves what is there
  local made = (MQ.Pins.provider.made or 0) + (QMm.provider.made or 0)
  M.combat = true
  local d1, d2 = MQ.Pins.provider.draws, QMm.provider.draws
  M.objectives[7][1].finished = true
  redraw()
  assert(MQ.Pins.provider.draws == d1 and QMm.provider.draws == d2 and marksFor(7) == 3, "in combat the frames stay as they were")
  M.map:Zoom(1.5, 0.3)
  assert(math.abs(ic.__scale - (1 + 0.2 * 0.3) / 1.5) < 1e-9, "zooming in combat moves and scales them")
  M.map:Zoom(1, 0)
  -- the map changes in combat: the frames drawn for the old one hide, and show again on it
  M.map:SetMapID(1453)
  for _, f in ipairs(ours(M)) do assert(not f:IsShown(), "frames drawn for another map hide in combat") end
  M.map:SetMapID(1429)
  for _, f in ipairs(ours(M)) do assert(f:IsShown(), "and show again back on their map") end
  M.map:SetMapID(1453)
  -- the map opened in combat: the same, nothing made
  M.map:Close(); M.map:Open()
  assert((MQ.Pins.provider.made or 0) + (QMm.provider.made or 0) == made and MQ.Pins.provider.draws == d1, "no frame made or drawn in combat")
  -- combat ends: both layers draw again, for the map on show
  M.combat = false
  local f = MQ.Pins.combatFrame
  f.__scripts.OnEvent(f, "PLAYER_REGEN_ENABLED")
  assert(MQ.Pins.provider.draws > d1 and QMm.provider.draws > d2 and MQ.Pins.provider.drawnFor == 1453 and QMm.provider.drawnFor == 1453,
    "after combat both layers draw the map on show")
  for _, fr in ipairs(ours(M)) do assert(fr:IsShown() and (not fr.kind.mouse or fr.__passThrough[1] == "RightButton"), "every frame shown, right-click passing through") end
  M.map:SetMapID(1429)
  assert(marksFor(7) == 1, "and the kills done in combat are off the map now")
  M.objectives[7][1].finished = false
  -- the frames are kept and drawn again, not made anew each time
  local before = (MQ.Pins.provider.made or 0) + (QMm.provider.made or 0)
  for _ = 1, 3 do redraw() end
  assert((MQ.Pins.provider.made or 0) + (QMm.provider.made or 0) == before, "a redraw makes no new frames")

  -- the game's own map pin: with Ctrl held, or the map's pin button on, QuestBank's frames let the mouse through, so the
  -- player's click lands on the map and the game places its pin as its own code (the cursor over them is the map's pin
  -- cursor then). Let go, they take it again; in combat too (EnableMouse is restricted on protected frames only).
  -- Not on a map the game has no pins for: a click there is QuestBank's waypoint, as without Ctrl
  do
    local function mice()
      local on, off = 0, 0
      for _, fr in ipairs(ours(M)) do
        if fr.kind.mouse then if fr.__mouse then on = on + 1 else off = off + 1 end end
      end
      return on, off
    end
    local on0, off0 = mice()
    assert(on0 > 0 and off0 == 0, "every icon and route pin takes the mouse")
    M.ctrl = true; tick(M, 0)
    local on1, off1 = mice()
    assert(on1 == 0 and off1 == on0, "Ctrl held: each lets the mouse through to the map")
    for _, fr in ipairs(ours(M)) do if not fr.kind.mouse then assert(fr.__mouse == false, "an area still takes none") end end
    redraw()
    assert(mice() == 0, "drawn again with Ctrl held: still through")
    M.combat = true
    M.ctrl = false; tick(M, 0)
    assert(select(2, mice()) == 0, "let go, in combat: they take it again")
    M.ctrl = true; tick(M, 0)
    assert(mice() == 0, "and Ctrl again, in combat: through")
    M.combat = false
    M.ctrl = false; tick(M, 0)
    M.map.WorldMapTrackingPinButton.isActive = true; tick(M, 0)
    assert(mice() == 0, "the map's pin button on: through")
    M.noPins = { [1453] = true }
    M.map:SetMapID(1453); tick(M, 0)
    assert(select(2, mice()) == 0, "a map the game has no pins for: they keep the mouse")
    M.map:SetMapID(1429); tick(M, 0)
    assert(mice() == 0, "back on Elwynn: through")
    M.noPins = nil
    M.map.WorldMapTrackingPinButton.isActive = false; tick(M, 0)
    assert(select(2, mice()) == 0, "the button off: they take it again")
    -- EnableMouse isn't restricted on plain frames: a client whose CheckAllowProtectedFunctions says no (in combat, say)
    -- changes nothing, and isn't asked. A frame that says it is protected keeps the mouse
    local asked = 0
    M.env.C_RestrictedActions = { CheckAllowProtectedFunctions = function() asked = asked + 1; return false end }
    M.combat = true
    M.ctrl = true; tick(M, 0); tick(M, 0)
    assert(mice() == 0 and asked == 0, "a no for protected calls, in combat: through all the same, and not asked")
    M.ctrl = false; tick(M, 0)
    assert(select(2, mice()) == 0, "and back")
    M.combat = false
    M.env.C_RestrictedActions = nil
    local prot = ours(M)[1]
    for _, fr in ipairs(ours(M)) do if fr.kind.mouse then prot = fr; break end end
    prot.IsProtected = function() return true end
    M.ctrl = true; tick(M, 0)
    local on2 = mice()
    assert(on2 == 1 and prot.__mouse, "a protected one keeps the mouse; the rest let it through")
    M.ctrl = false; tick(M, 0)
    prot.IsProtected = nil
    -- the map shut with Ctrl held: drawn with the mouse when it opens; Ctrl still down, through again
    M.ctrl = true; tick(M, 0)
    M.map:Close()
    assert(select(2, mice()) == 0, "the map shut: they take the mouse again")
    tick(M, 0)
    assert(select(2, mice()) == 0, "and the keys aren't watched while it is shut")
    M.map:Open(); tick(M, 0)
    assert(mice() == 0, "opened with Ctrl down: through")
    M.ctrl = false; tick(M, 0)
    assert(select(2, mice()) == 0 and not MQ.Pins.through, "let go")
  end

  -- the game holding addons back as in combat without InCombatLockdown (C_RestrictedActions, an encounter): the layers
  -- wait the same way, and draw when the restriction ends (ADDON_RESTRICTION_STATE_CHANGED, inactive); the frames'
  -- right-click pass-through is set only when the client allows protected calls on the frame (asked silently)
  do
    local E = M.env.Enum
    E.AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 }
    E.AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 }
    local active, allow = {}, true
    M.env.C_RestrictedActions = {
      IsAddOnRestrictionActive = function(kind) return active[kind] or false end,
      CheckAllowProtectedFunctions = function(obj, silent) assert(silent == true, "asked silently: asking never trips the block"); return allow end,
    }
    local pv, cf = MQ.Pins.provider, MQ.Pins.combatFrame
    assert(not MQ.Pins.InCombat(), "nothing held back: not combat")
    active[1] = true
    assert(MQ.Pins.InCombat(), "an encounter's restriction counts as combat")
    local d = pv.draws
    M.map:SetMapID(1453)
    assert(pv.draws == d, "nothing drawn while the game holds addons back")
    cf.__scripts.OnEvent(cf, "ADDON_RESTRICTION_STATE_CHANGED", 1, 1)
    assert(pv.draws == d, "the event before a restriction starts: nothing")
    active[1] = nil
    cf.__scripts.OnEvent(cf, "ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
    assert(pv.draws > d and pv.drawnFor == 1453, "drawn when it ends, for the map on show")
    -- a frame made while the client says no: no pass-through call; set on its next draw once allowed
    allow = false
    local fr = pv:Make(MQ.Pins.ROUTE)
    assert(fr and not fr.passSet and not fr.__passThrough, "made, the protected call left out")
    pv.free[MQ.Pins.ROUTE] = pv.free[MQ.Pins.ROUTE] or {}
    table.insert(pv.free[MQ.Pins.ROUTE], fr)
    allow = true
    local got = pv:Add(MQ.Pins.ROUTE, { name = "Test stop", num = 1, icon = 1 }, 0.5, 0.5)
    assert(got == fr and fr.passSet and fr.__passThrough and fr.__passThrough[1] == "RightButton", "allowed again: set when it is next drawn, once")
    pv:RefreshAllData()
    M.env.C_RestrictedActions = nil
    E.AddOnRestrictionType, E.AddOnRestrictionState = nil, nil
    M.map:SetMapID(1429)
  end

  -- the recorder: a call the game blocked and blamed on QuestBank is kept in QuestBankDB.diag.blocked, its stack with
  -- QuestBank's own files by name and no other path, and said once in chat; another addon's is none of QuestBank's
  do
    local bf = MQ.blockedFrame
    M.env.debugstack = function() return table.concat({
      "[C]: in function 'SetPassThroughButtons'",
      "[Interface/AddOns/Blizzard_MapCanvas/MapCanvas_DataProviderBase.lua]:290: in function 'CheckMouseButtonPassthrough'",
      "[Interface/AddOns/Blizzard_MapCanvas/Blizzard_MapCanvas.lua]:331: in function 'AcquirePin'",
      '[string "@Interface/AddOns/QuestBank/Pins.lua"]:164: in function <Interface/AddOns/QuestBank/Pins.lua:160>',
      "[Interface/AddOns/SomeOtherAddon/Core.lua]:12: in function 'Thing'",
      "C:\\Users\\Someone\\World of Warcraft\\_classic_\\Interface\\AddOns\\QuestBank\\Core.lua:50: in function <...aceBlizzard_MapCanvas/Blizzard_MapCanvas.lua:116>",
      "*Blizzard_WorldMap.xml:78_OnLoad:1: in function 'onCloseCallback'",
    }, "\n") end
    local said = #M.chat
    M.combat = true
    bf.__scripts.OnEvent(bf, "ADDON_ACTION_BLOCKED", "QuestBank", "Frame:SetPassThroughButtons()")
    local list = M.env.QuestBankDB.diag.blocked
    local b = list and list[1]
    assert(b and b.fn == "Frame:SetPassThroughButtons()" and b.combat == true and type(b.at) == "number" and b.kind == "blocked" and b.qb == MQ.version,
      "a blocked call is kept: what, when, in combat")
    local st = b.stack
    assert(not st:find("Interface", 1, true) and not st:find("SomeOtherAddon", 1, true) and not st:find("Users", 1, true) and not st:find("Blizzard_", 1, true)
      and st:find("[QuestBank/Pins.lua]:164: in function <QuestBank/Pins.lua:160>", 1, true) and st:find("[(game)]:331: in function 'AcquirePin'", 1, true)
      and st:find("[(addon)]:12: in function 'Thing'", 1, true) and st:find("QuestBank/Core.lua:50", 1, true) and st:find("[C]: in function 'SetPassThroughButtons'", 1, true),
      "its stack: QuestBank's files by name, no other path:\n" .. st)
    assert(#M.chat == said + 1 and M.chat[#M.chat]:find("calling Frame:SetPassThroughButtons() in combat", 1, true) and M.chat[#M.chat]:find("/qb errors", 1, true),
      "said in chat: " .. M.chat[#M.chat])
    print("blocked, kept:", (st:gsub("\n", " | ")))
    -- the same call again: counted. Others: kept, the last 10. Said once
    bf.__scripts.OnEvent(bf, "ADDON_ACTION_BLOCKED", "QuestBank", "Frame:SetPassThroughButtons()")
    assert(#list == 1 and list[1].n == 2, "the same call again: counted")
    M.combat = false
    for i = 1, 11 do bf.__scripts.OnEvent(bf, "ADDON_ACTION_BLOCKED", "QuestBank", "Thing" .. i .. "()") end
    assert(#list == 10 and list[10].fn == "Thing11()" and list[1].fn == "Thing2()" and list[1].combat == false, "the last 10 kept")
    bf.__scripts.OnEvent(bf, "ADDON_ACTION_FORBIDDEN", "QuestBank", "UseQuestLogSpecialItem()")
    assert(list[#list].kind == "forbidden" and list[#list].fn == "UseQuestLogSpecialItem()", "forbidden ones too")
    bf.__scripts.OnEvent(bf, "ADDON_ACTION_BLOCKED", "SomeOtherAddon", "CastSpellByName()")
    bf.__scripts.OnEvent(bf, "ADDON_ACTION_FORBIDDEN", "SomeOtherAddon", "CastSpellByName()")
    assert(list[#list].fn == "UseQuestLogSpecialItem()" and #M.chat == said + 1, "another addon's: not kept, nothing said")
    -- /qb errors lists them to copy, newest first; /qb errors clear forgets them
    M.env.SlashCmdList.QUESTBANK("errors")
    local text = M.env.QuestBankErrors.eb:GetText()
    assert(text:find("the game forbade UseQuestLogSpecialItem()", 1, true) and text:find("the game blocked Thing11()", 1, true)
      and text:find("the game forbade", 1, true) < text:find("the game blocked Thing11()", 1, true), "/qb errors lists them: " .. text:sub(1, 300))
    M.env.QuestBankErrors:Hide()
    M.env.SlashCmdList.QUESTBANK("errors clear")
    assert(M.env.QuestBankDB.diag.blocked == nil, "/qb errors clear forgets them")
    M.env.debugstack = nil
    -- a long chain: both ends kept. The game cuts debugstack(2, 8, 8) to the top 8 lines and the bottom 8 with "..."
    -- between; the top shows the blocked call, the bottom where the chain began (here an event handler, in another
    -- addon's file: a stale taint has no QuestBank frame in it at all)
    local chain = { "[C]: in function 'SetPassThroughButtons'" }
    for i = 2, 20 do chain[#chain + 1] = "[Interface/AddOns/Blizzard_MapCanvas/Blizzard_MapCanvas.lua]:" .. (100 + i) .. ": in function 'Step" .. i .. "'" end
    chain[#chain + 1] = "[Interface/AddOns/SomeOtherAddon/Libs/AceEvent-3.0.lua]:120: in function <...AceEvent-3.0.lua:119>"
    local asked
    M.env.debugstack = function(start, top, bottom)
      asked = { start, top, bottom }
      local out = {}
      for i = 1, top do out[#out + 1] = chain[i] end
      out[#out + 1] = "..."
      for i = #chain - bottom + 1, #chain do out[#out + 1] = chain[i] end
      return table.concat(out, "\n") .. "\n"
    end
    bf.__scripts.OnEvent(bf, "ADDON_ACTION_BLOCKED", "QuestBank", "Frame:SetPassThroughButtons()")
    assert(asked and asked[1] == 2 and asked[2] == 8 and asked[3] == 8, "the recorder asks for both ends: debugstack(2, 8, 8)")
    local kept = M.env.QuestBankDB.diag.blocked[#M.env.QuestBankDB.diag.blocked].stack
    local rows = {}
    for row in kept:gmatch("[^\n]+") do rows[#rows + 1] = row end
    assert(#rows == 17 and rows[1] == "[C]: in function 'SetPassThroughButtons'" and rows[9] == "..." and rows[17]:find("[(addon)]:120:", 1, true)
      and kept:find("Step8'", 1, true) and not kept:find("Step9'", 1, true) and not kept:find("Step13'", 1, true) and kept:find("Step14'", 1, true),
      "the top 8 and the bottom 8 kept, the middle left out:\n" .. kept)
    -- a stack longer than that however it comes: cut the same way, 16 frames at most
    local long = {}
    for i = 1, 30 do long[#long + 1] = "[Interface/AddOns/QuestBank/UI.lua]:" .. i .. ": in function 'f" .. i .. "'" end
    local cut = MQ.Err.CleanStack(table.concat(long, "\n"))
    rows = {}
    for row in cut:gmatch("[^\n]+") do rows[#rows + 1] = row end
    assert(#rows == 17 and rows[1] == "[QuestBank/UI.lua]:1: in function 'f1'" and rows[8]:find("'f8'", 1, true) and rows[9] == "..."
      and rows[10]:find("'f23'", 1, true) and rows[17]:find("'f30'", 1, true), "a long stack: its two ends:\n" .. cut)
    M.env.debugstack = nil
    M.env.SlashCmdList.QUESTBANK("errors clear")
  end

  -- an older Data.lua: no spots at all, still the ! and ?
  MQ:Settings().pins = false
  MD.SPOT, MD.START, MD.SN, MD.SREQ = nil, nil, nil, nil
  redraw()
  assert(#icons("give") == #give and #icons("turn") == 1 and #icons("obj") == 0 and #icons("start") == 0 and #areas() == 0, "no D.SPOT: the ! and ? still show")
  inject()
  redraw()
  assert(#icons("obj") == 4 and #icons("start") == 1, "and the spots are back")
  -- the atlas missing: the file id
  M.noAtlas = { QuestNormal = true }
  redraw()
  assert(icons("give")[1].Icon.__tex == MD.TEX.questAvail, "no atlas: the gossip ! file")
  M.noAtlas = nil

  -- a tie nothing settles is never guessed by order: on a German client the names don't help, so neither slot is
  -- matched and the spots of both keep showing until the quest is complete
  do
    local list = QMm.Spots("c,5,1429,1,1,0,c,2;c,6,1429,1,1,0,c,3")
    local objs = { { text = "Defiasmaske: 12/12", type = "item", need = 12, done = true },
                   { text = "Rotes Leinenkopftuch: 2/12", type = "item", need = 12, done = false } }
    local m = QMm.Match(objs, list, { [5] = 12, [6] = 12 })
    assert(m[5] == nil and m[6] == nil, "deDE: two items of twelve and no name to tell them apart: neither is guessed")
    -- one settled leaves the other one line: the kill fits only the monster's, then the use has the object's
    local l2 = QMm.Spots("u,1,1429,1,1,0,c,4;k,2,1429,1,1,0,c,1")
    local o2 = { { text = "Kiste benutzt: 0/1", type = "object", need = 1 }, { text = "Koboldungeziefer: 0/1", type = "monster", need = 1 } }
    m = QMm.Match(o2, l2, { [1] = 1, [2] = 1 })
    assert(m[2] == o2[2] and m[1] == o2[1], "deDE: the kill settled by its kind, the use by what is left")
  end

  -- slot 0 is no objective of the catalog's (players' games for a quest it doesn't know, or a spot no slot was found
  -- for): never matched against the game's lines, so its spots show until the quest is complete
  do
    local list = QMm.Spots("k,0,1429,1,1,0,g;e,0,1429,1,1,0,g;k,1,1429,1,1,0,c,1")
    local objs = { { text = "Kobold Vermin slain: 10/10", type = "monster", need = 10, done = true },
                   { text = "Camp explored", type = "event", need = 1, done = true } }
    local m = QMm.Match(objs, list, { [1] = 10 })
    assert(m[0] == nil and m[1] == objs[1], "slot 0 is never matched; slot 1 is")
    m = QMm.Match(objs, QMm.Spots("k,0,1429,1,1,0,g"), {})
    assert(next(m) == nil, "a quest the catalog doesn't know: nothing matched")
    MD.SPOT[7] = SPOT[7] .. ";k,0,1429,300,300,15,g"
    M.objectives[7][1] = { text = "Kobold Vermin slain: 10/10", type = "monster", finished = true, numFulfilled = 10, numRequired = 10 }
    MQ:Settings().pins = false
    redraw()
    local zero
    for _, pin in ipairs(icons("obj")) do if pin.data.id == 7 and pin.data.spot.slot == 0 then zero = pin end end
    assert(marksFor(7) == 2 and zero and near(zero, 0.3, 0.3) and tipOf(zero):find("Position: seen in players' games", 1, true),
      "the kills done: the crate and the players' slot-0 spot stay")
    M.log[1] = { 7, 1 }
    redraw()
    assert(marksFor(7) == 0, "until the quest is complete")
    M.log[1] = { 7, 0 }
    M.objectives[7][1] = { text = "Kobold Vermin slain: 3/10", type = "monster", finished = false, numFulfilled = 3, numRequired = 10 }
    MD.SPOT[7] = SPOT[7]
    redraw()
    assert(marksFor(7) == 3, "back as it was")
  end

  -- a quest the catalog doesn't know (Forever's own) has all its spots in slot 0, each of the kind of the game's line
  -- it was seen for (gen_data: monster k, item c, object u, event e). Where only one line is of that kind and no slot
  -- of the catalog's could be it, the spots are that line's: they go once it is done, and say how far along it is.
  -- Two lines of a kind can't be told apart: their spots stay until the quest is complete. Each kind has its nearest
  -- mark before any has a second, as each slot of the catalog's does
  do
    local objs = { { text = "Gnoll slain: 10/10", type = "monster", need = 10, done = true },
                   { text = "Gnoll Paw: 2/8", type = "item", need = 8 }, { text = "Gnoll Tooth: 0/8", type = "item", need = 8 } }
    local z = QMm.Loose(objs, QMm.Spots("k,0,1429,1,1,0,g;c,0,1429,1,1,0,g;e,0,1429,1,1,0,g"))
    assert(z.k == objs[1] and z.c == nil and z.e == nil, "one kill line: the k spots'; two item lines: neither; no event line: none")
    z = QMm.Loose(objs, QMm.Spots("k,0,1429,1,1,0,g;k,1,1429,1,1,0,c,1"))
    assert(z.k == nil, "a slot of the catalog's could be the kill line: not guessed")
    z = QMm.Loose({ { text = "Something: 0/1", need = 1 }, objs[1] }, QMm.Spots("k,0,1429,1,1,0,g"))
    assert(z.k == nil, "a line whose kind the game doesn't say could be a kill: not guessed")
    MD.SREQ[7], MD.SPOT[7] = nil, "k,0,1429,300,300,15,g;k,0,1429,340,300,15,g;e,0,1429,700,700,15,g;e,0,1429,740,700,15,g"
    M.objectives[7] = { { text = "Kobold Vermin slain: 3/10", type = "monster", finished = false, numFulfilled = 3, numRequired = 10 },
                        { text = "Camp scouted: 0/1", type = "event", finished = false, numFulfilled = 0, numRequired = 1 } }
    MQ:Settings().pins = false
    redraw()
    local order, kill = {}, nil
    for _, d in ipairs(QMm:Build(1429)) do if d.kind == "obj" and d.id == 7 then order[#order + 1] = d.spot.kind end end
    for _, pin in ipairs(icons("obj")) do if pin.data.id == 7 and pin.data.spot.kind == "k" then kill = pin end end
    assert(table.concat(order) == "keke", "each kind its nearest mark first: " .. table.concat(order))
    assert(kill and tipOf(kill):find("Kill here\nKobold Vermin slain: 3/10\nPosition: seen in players' games", 1, true),
      "the kills' spot says how far along they are")
    M.objectives[7][1] = { text = "Kobold Vermin slain: 10/10", type = "monster", finished = true, numFulfilled = 10, numRequired = 10 }
    redraw()
    local left = {}
    for _, pin in ipairs(icons("obj")) do if pin.data.id == 7 then left[#left + 1] = pin.data.spot.kind end end
    assert(table.concat(left) == "ee", "the kills done: only the event's spots stay")
    MD.SREQ[7], MD.SPOT[7] = "1:10,2:1", SPOT[7]
    M.objectives[7] = { { text = "Kobold Vermin slain: 3/10", type = "monster", finished = false, numFulfilled = 3, numRequired = 10 } }
    redraw()
    assert(marksFor(7) == 3, "back as it was")
  end

  -- an item slot is named by its item (D.SREQ's third field, an index into D.SN), not by what drops it: the masks
  -- (done, listed first) and the bandanas both ask for 12, and the spots are named for the Defias who drop them
  do
    MD.SN[11], MD.SN[12] = "Defias Thug", "Defias Footpad"
    MD.SPOT[18] = "c,5,1429,540,300,40,w,11;c,6,1429,560,320,0,g,12"
    MQ:Settings().pins = false
    redraw()
    assert(marksFor(18) == 2, "named for the creatures: a tie, so both keep showing")
    MD.SREQ[18] = "5:12:2,6:12:3"
    redraw()
    local left
    for _, pin in ipairs(icons("obj")) do if pin.data.id == 18 then left = pin end end
    assert(marksFor(18) == 1 and left.data.spot.slot == 5 and near(left, 0.54, 0.30) and left.data.line.text == "Red Burlap Bandana: 2/12",
      "the masks are done, told by their item's name: only the bandanas' spot")
    assert(tipOf(left):find("Loot Defias Thug\nRed Burlap Bandana: 2/12", 1, true), "its tooltip: who drops it, and the game's line")
    local list = QMm.Spots("c,5,1429,1,1,0,c,11;c,6,1429,1,1,0,c,12")
    local objs = { { text = "Defias Mask: 12/12", type = "item", need = 12, done = true }, { text = "Red Burlap Bandana: 2/12", type = "item", need = 12 } }
    local m = QMm.Match(objs, list, { [5] = 12, [6] = 12 }, { [5] = "Red Burlap Bandana", [6] = "Defias Mask" })
    assert(m[5] == objs[2] and m[6] == objs[1], "QM.Match takes the item names")
    MD.SPOT[18], MD.SREQ[18] = SPOT[18], "5:12,6:12"
    redraw()
  end

  -- a log too big for the cap: every ! and ? stays, each objective has its nearest mark first, the areas go first
  do
    local keep = MD.SPOT[7]
    local parts = {}
    for i = 1, 105 do parts[#parts + 1] = string.format("k,1,1429,%d,%d,20,c,1", 100 + (i % 10) * 70, 100 + math.floor(i / 10) * 70) end
    parts[#parts + 1] = "u,2,1429,450,380,0,g,4" -- the crate, last of 106
    MD.SPOT[7] = table.concat(parts, ";")
    MQ:Settings().pins = false
    local full = QMm:Build(1429)
    local n, crate = {}, false
    for _, d in ipairs(full) do
      n[d.kind] = (n[d.kind] or 0) + 1
      if d.kind == "obj" and d.spot.slot == 2 then crate = true end
    end
    assert(#full == 200 and full.cut > 0 and n.give == #give and n.turn == 1 and n.start == 1 and n.obj == 107,
      "at the cap: every !, ? and mark still there, areas left out: " .. #full .. ", " .. tostring(full.cut))
    assert(crate, "the crate's mark comes in its turn, not after 105 kills")
    MD.SPOT[7] = keep
  end

  -- an older Data.lua (no D.QLOCK): the "Other quests" of the Classic database stand in for what QuestBank doesn't
  -- check (a profession, a book): no !
  local realLock = MD.QLOCK
  MD.QLOCK = nil
  do
    local gearing, kaldorei, zephras = MQ.Quest.Get(1618), MQ.Quest.Get(4161), MQ.Quest.Get(92514)
    assert(MQ:Status(gearing).code == "todo" and QMm.Unchecked(gearing) and QMm.Unchecked(kaldorei), "Gearing Redridge: todo, and unchecked")
    for _, m in ipairs({ gearing.give.m, kaldorei.give.m }) do
      for _, d in ipairs(QMm:Build(m)) do
        for _, q in ipairs(d.quests or {}) do assert(q.id ~= 1618 and q.id ~= 4161, "no ! for a profession's quest: " .. q.name) end
      end
    end
    assert(zephras and not QMm.Unchecked(zephras), "Forever's own quests filed under Other quests keep theirs")
  end

  -- D.QLOCK (gen_data: the quests that need a profession's skill or a reputation) replaces that stand-in: a quest
  -- it lists gets no !, an "Other quest" it doesn't list gets its !. Read by quest id, as a list or as "id,id"
  do
    MQ:Settings().pins = false
    local gearing = MQ.Quest.Get(1618)
    local function offered(m, id)
      for _, d in ipairs(QMm:Build(m)) do
        for _, q in ipairs(d.quests or {}) do if d.kind == "give" and q.id == id then return true end end
        for _, q in ipairs(d.offers or {}) do if q.id == id then return true end end
      end
      return false
    end
    local gid = give[1].data.quests[1].id
    assert(offered(1429, gid) and not offered(gearing.give.m, 1618), "no D.QLOCK: the stand-in hides Gearing Redridge")
    MD.QLOCK = { [gid] = "s:202:1" }
    assert(not offered(1429, gid) and QMm.Unchecked(MQ.Quest.Get(gid)), "a quest D.QLOCK lists: no !")
    assert(offered(gearing.give.m, 1618) and not QMm.Unchecked(gearing), "with D.QLOCK the stand-in goes: an Other quest it doesn't list keeps its !")
    MD.QLOCK = { gid, 1618 }
    assert(not offered(1429, gid) and not offered(gearing.give.m, 1618) and not QMm.Unchecked(MQ.Quest.Get(7)), "D.QLOCK as a list of ids")
    MD.QLOCK = gid .. ",1618"
    assert(not offered(1429, gid) and not offered(gearing.give.m, 1618) and not QMm.Unchecked(MQ.Quest.Get(7)), "D.QLOCK as a string")
    MD.QLOCK = {}
    assert(offered(1429, gid) and offered(gearing.give.m, 1618), "an empty D.QLOCK locks nothing")
    MD.QLOCK = nil
    assert(offered(1429, gid) and QMm.Unchecked(gearing), "and without it, as before")
    -- gen_data's own, when this Data.lua has it: Gearing Redridge needs Blacksmithing
    if realLock then
      MD.QLOCK = realLock
      assert(realLock[1618] and QMm.Unchecked(gearing) and not offered(gearing.give.m, 1618), "Data.lua's D.QLOCK: Gearing Redridge is locked")
    end
  end
  MD.QLOCK = realLock

  -- where an NPC's place comes from: Data.lua's letter for it; without one, Classic, or Wowhead on a map new in Forever
  local realSrc = MD.NSRC
  do
    MD.NSRC = nil
    redraw()
    local e = icons("turn")[1]
    local idx = e.data.npc
    assert(e.data.title == "Eagan Peltskinner" and tipOf(e):find("Position: Classic data (may have moved in Forever)", 1, true), "no D.NSRC: Classic")
    MD.NSRC = { [idx] = "w" }
    assert(tipOf(e):find("Position: Wowhead Forever", 1, true), "D.NSRC says Wowhead")
    MD.NSRC = string.rep("c", idx - 1) .. "g"
    assert(tipOf(e):find("Position: seen in players' games", 1, true), "D.NSRC as a string of letters")
    MD.NSRC = nil
    local zi
    for i, rec in ipairs(MD.NPC) do if rec[2] == 2521 then zi = i break end end
    assert(zi and QMm.NpcSource({ npc = zi, m = 2521 }) == "w" and QMm.NpcSource({ npc = idx, m = 1429 }) == "c", "Zephras Isle: Wowhead's")
    -- gen_data's own, when this Data.lua has it: one letter for every NPC
    if realSrc then
      assert(type(realSrc) == "string" and #realSrc == #MD.NPC and not realSrc:find("[^wcg]"), "Data.lua's D.NSRC: one of w, c, g per NPC")
      MD.NSRC = realSrc
      assert(QMm.NpcSource({ npc = idx, m = 1429 }) == realSrc:sub(idx, idx), "and it is what the tooltip says")
    end
  end
  MD.NSRC = nil -- the tests below name their own

  -- the route's pins, at level 10: the NPC a pin stands on is theirs, and what the pin doesn't list goes on its
  -- tooltip; an NPC a step away (the Wanted Poster beside Deputy Rainer) keeps its own !; one at the very spot
  -- (Priestess Josetta where William Pestle stands) goes on the pin's tooltip, as her ! would lie under the pin
  do
    M.level = 10
    MQ:Settings().pins = false
    redraw()
    -- the icon an NPC is on (NPCs at the same spot share one), and that NPC's part of it
    local function iconOf(title)
      for _, pin in ipairs(icons()) do
        for _, w in ipairs(pin.data.who or {}) do if w.title == title then return pin, w end end
      end
    end
    local function routeOn(who) for _, pin in ipairs(routePins()) do if pin.data.who == who then return pin end end end
    local thomas, rainer, pestle = iconOf("Guard Thomas"), iconOf("Deputy Rainer"), iconOf("William Pestle")
    assert(thomas and #thomas.data.quests == 2 and rainer and pestle and iconOf("Wanted Poster") and iconOf("Priestess Josetta"), "level 10: the NPCs this needs")
    -- NPCs at the same spot share one icon (two would lie on top of each other, only the top one to hover): Priestess
    -- Josetta stands where William Pestle does, so one ! lists each of them with their own quests
    do
      local _, pw = iconOf("William Pestle")
      local jp, jw = iconOf("Priestess Josetta")
      assert(jp == pestle and #pestle.data.who == 2 and #pw.give > 0 and #jw.give > 0 and #pestle.data.quests == #pw.give + #jw.give
        and pestle.data.kind == "give", "Pestle and Josetta: one ! for both")
      local t = tipOf(pestle)
      assert(t:find("William Pestle\nTo pick up:\n", 1, true) and t:find("Priestess Josetta\nTo pick up:\n", 1, true) and t:find(jw.give[1].name, 1, true)
        and t:find(pw.give[1].name, 1, true), "its tooltip names each NPC with its quests: " .. t)
      local _, nPos = t:gsub("Position: ", "")
      assert(nPos == 1 and t:find("Shift-click: put them on your pick-up list", 1, true), "one Position line when both places come from the same data")
      -- their places from different data: a line under each
      MD.NSRC = { [pw.npc] = "w", [jw.npc] = "c" } -- (none before this: one line above)
      t = tipOf(pestle)
      _, nPos = t:gsub("Position: ", "")
      assert(nPos == 2 and t:find("To pick up:\n.-Position: Wowhead Forever\nPriestess Josetta", 1) and t:find("Position: Classic data", 1, true), "a Position line under each: " .. t)
      MD.NSRC = nil
      print("map icons, two NPCs at one spot:", (tipOf(pestle):gsub("\n", " | ")))
      -- Kobold Candles done and in the log: Pestle takes it, so their icon is a ?, Josetta's quests on it to pick up
      table.insert(M.log, { 60, 1 })
      redraw()
      local tp = iconOf("Priestess Josetta")
      t = tipOf(tp)
      assert(tp.data.kind == "turn" and tp.Icon.__atlas == "QuestTurnin" and #tp.data.quests == 1 and tp.data.quests[1].id == 60 and #tp.data.offers >= #jw.give
        and t:find("William Pestle\nHand in:\n[7] Kobold Candles", 1, true) and t:find("Priestess Josetta\nTo pick up:\n", 1, true)
        and t:find("Click: waypoint.", 1, true) and not t:find("Shift-click", 1, true), "a ? at the spot, each NPC's part on it: " .. t)
      print("map icons, a ? and a ! at one spot:", (t:gsub("\n", " | ")))
      table.remove(M.log)
      redraw()
      -- the Stonefields' farm: Ma Stonefield and "Auntie" Bernice, 0.14 % apart, one icon too when both have quests
      local ma, bernice = iconOf("Ma Stonefield"), iconOf('"Auntie" Bernice Stonefield')
      assert(not (ma and bernice) or ma == bernice, "the Stonefields share an icon")
    end
    local other = thomas.data.quests[2]
    local _, pw = iconOf("William Pestle")
    local listed = { thomas.data.quests[1].id, rainer.data.quests[1].id, pw.give[1].id }
    for _, id in ipairs(listed) do MQ:ToggleAdd(id) end
    -- /qb pins: the icons follow without being told
    M.env.SlashCmdList.QUESTBANK("pins")
    assert(MQ:Settings().pins and routeOn("Guard Thomas") and not iconOf("Guard Thomas"), "/qb pins: Guard Thomas has the route's pin, and no icon")
    local tip = tipOf(routeOn("Guard Thomas"))
    assert(tip:find("Also to pick up here:", 1, true) and tip:find(other.name, 1, true), "what his pin doesn't list is on its tooltip: " .. tip)
    M.map:SetMapID(1415)
    assert(routeOn("Guard Thomas") and not tipOf(routeOn("Guard Thomas")):find("Also to", 1, true), "on the continent, where no icon draws, his pin says only its own")
    M.map:SetMapID(1429)
    assert(routeOn("Deputy Rainer") and iconOf("Wanted Poster") and not tipOf(routeOn("Deputy Rainer")):find("Wanted Poster", 1, true),
      "the Wanted Poster beside Deputy Rainer keeps its own !")
    assert(routeOn("William Pestle") and not iconOf("Priestess Josetta") and tipOf(routeOn("William Pestle")):find("Priestess Josetta, to pick up:", 1, true),
      "Priestess Josetta, at the very spot of William Pestle's pin: on its tooltip")
    M.env.SlashCmdList.QUESTBANK("pins")
    assert(not MQ:Settings().pins and #routePins() == 0 and iconOf("Guard Thomas") and iconOf("Priestess Josetta"), "/qb pins off: their icons are back")
    -- the Settings box: the same, untold
    MQ.UI:Open(5); MQ.UI:Refresh()
    local v = MQ.UI.views[5]
    v.pins:SetChecked(true); v.pins.__scripts.OnClick(v.pins, "LeftButton")
    assert(MQ:Settings().pins and not iconOf("Guard Thomas") and iconOf("Wanted Poster"), "the Settings box: route pins on, the icons follow")
    v.pins:SetChecked(false); v.pins.__scripts.OnClick(v.pins, "LeftButton")
    assert(not MQ:Settings().pins and iconOf("Guard Thomas"), "and off")
    MQ.UI.frame:Hide()
    for _, id in ipairs(listed) do MQ:ToggleAdd(id) end
    M.level = 3
    redraw()
    print(string.format("map icons, the route's pin on Guard Thomas: %s", (tip:gsub("\n", " | "))))
  end
end

----------------------------------------------------------------------------
-- players' objective spots (Discover.lua): where an objective of a quest in the log ticks, as the map and the
-- position in thousandths; a sighting within 15 of a point on the same map is that point; at most 8 points an
-- objective and 400 quests. The Forever client only, never in an instance, at the bank or mailbox, for an item made
-- at a crafting window, just after a loading screen or a quest came into the log, or when the client hides the
-- position; no names. gen_data shows them on the map as "seen in players' games"
----------------------------------------------------------------------------
do
  local M, MQ = maren, maren.QB
  local Dz = MQ.Discover
  local f = Dz.frame
  local DB = M.env.QuestBankDB
  local C = M.env.C_Map
  local savePos, saveBest = C.GetPlayerMapPosition, C.GetBestMapForUnit
  local px, py, map = 0.4, 0.5, 1429
  C.GetPlayerMapPosition = function(m, unit)
    assert(m == map and unit == "player", "the position on the map you are on")
    return { x = px, y = py, GetXY = function(self) return self.x, self.y end }
  end
  C.GetBestMapForUnit = function() return map end
  local function update(event, unit) f.__scripts.OnEvent(f, event or "QUEST_LOG_UPDATE", unit); tick(M, 0) end
  local kills = M.objectives[7][1]
  local have = 3
  local function kill() have = have + 1; kills.numFulfilled = have; kills.text = "Kobold Vermin slain: " .. have .. "/10" end
  local function spotsOf() return DB.disc.os end
  local function pts(id, i) local q = spotsOf() and spotsOf()[id]; return q and q[i] and q[i].p or {} end
  local function total() local n = 0; for _, q in pairs(spotsOf() or {}) do for _, o in pairs(q) do for _, p in ipairs(o.p) do n = n + p[4] end end end; return n end
  local errs0 = #(DB.errors or {})

  kills.numFulfilled, kills.finished = have, false
  update()
  assert(spotsOf() == nil or next(spotsOf()) == nil, "the first look only learns where things stand")
  tick(M, 4)
  update()
  assert(spotsOf() == nil or next(spotsOf()) == nil, "nothing moved: nothing noted")
  kill()
  update()
  local p = pts(7, 1)
  assert(spotsOf()[7][1].t == "monster" and #p == 1 and p[1][1] == 1429 and p[1][2] == 400 and p[1][3] == 500 and p[1][4] == 1,
    "a kill: noted where you stand, in thousandths of the map")
  -- a step away: the same point, now at the middle of its sightings; further: a point of its own; another map: another
  px = 0.41; kill(); update()
  p = pts(7, 1)
  assert(#p == 1 and p[1][2] == 405 and p[1][3] == 500 and p[1][4] == 2, "within 15 thousandths: the same point")
  px = 0.44; kill(); update()
  p = pts(7, 1)
  assert(#p == 2 and p[2][2] == 440 and p[2][4] == 1, "further off: a point of its own")
  map = 1453; px = 0.405; kill(); update()
  p = pts(7, 1)
  assert(#p == 3 and p[3][1] == 1453 and p[1][4] == 2, "the same place on another map is another point")
  map, px = 1429, 0.4
  -- many updates at once (a loot window): one look, one sighting
  kill()
  for _ = 1, 3 do f.__scripts.OnEvent(f, "QUEST_LOG_UPDATE") end
  f.__scripts.OnEvent(f, "UNIT_QUEST_LOG_CHANGED", "player")
  tick(M, 0)
  assert(pts(7, 1)[1][4] == 3, "four updates, one sighting")
  kill(); update("UNIT_QUEST_LOG_CHANGED", "player")
  assert(pts(7, 1)[1][4] == 4, "the log changing for you counts too")
  -- an item objective, as the game numbers its lines (the bandanas are its second); the masks didn't move
  local bandanas = M.objectives[18][2]
  bandanas.numFulfilled, bandanas.text = 3, "Red Burlap Bandana: 3/12"
  px, py = 0.54, 0.3
  update()
  assert(spotsOf()[18][2].t == "item" and #pts(18, 2) == 1 and pts(18, 2)[1][2] == 540 and spotsOf()[18][1] == nil, "an item looted: the game's second line")
  -- finished without a count (an area reached, an event): noted too
  M.objectives[7][2] = { text = "Camp scouted", type = "event", finished = false }
  update()
  assert(spotsOf()[7][2] == nil, "a new line: where it stands is learned first")
  M.objectives[7][2].finished = true
  update()
  assert(spotsOf()[7][2].t == "event" and #pts(7, 2) == 1, "the event done: noted")
  M.objectives[7][2] = nil
  -- a quest new to your log brings what you had already: not noted; nor what comes for it a look later (the server
  -- can send an item objective's count a moment after the quest); nor what comes just after it is accepted again
  table.insert(M.log, { 4242, 0 })
  M.objectives[4242] = { { text = "Linen Cloth: 5/10", type = "item", finished = false, numFulfilled = 5, numRequired = 10 } }
  update()
  assert(spotsOf()[4242] == nil, "a quest just taken: its progress so far isn't from here")
  table.insert(M.log, { 4244, 0 })
  M.objectives[4244] = { { text = "Wool Cloth: 0/10", type = "item", finished = false, numFulfilled = 0, numRequired = 10 } }
  update()
  tick(M, 1)
  M.objectives[4244][1].numFulfilled, M.objectives[4244][1].text = 6, "Wool Cloth: 6/10"
  update()
  assert(spotsOf()[4244] == nil, "its count a look after the quest: not from here either")
  tick(M, 4)
  f.__scripts.OnEvent(f, "QUEST_ACCEPTED", 4244)
  M.objectives[4244][1].numFulfilled = 7
  update()
  assert(spotsOf()[4244] == nil, "accepted again (abandoned in between): what it has now isn't from here")
  tick(M, 4)
  M.objectives[4244][1].numFulfilled = 8
  update()
  assert(#pts(4244, 1) == 1, "a moment later, a rise is")
  table.remove(M.log)
  M.objectives[4244] = nil
  -- less than before (an item sold or destroyed): nothing; back up again: noted
  M.objectives[4242][1].numFulfilled = 4; update()
  assert(spotsOf()[4242] == nil, "less: nothing")
  M.objectives[4242][1].numFulfilled = 5; update()
  assert(#pts(4242, 1) == 1, "more again: noted")
  table.remove(M.log)
  M.objectives[4242] = nil

  -- not where it was found: the bank, the mailbox, a trade; nor in an instance; nor where the client hides the place
  local n0 = total()
  M.env.MailFrame = { IsShown = function() return true end }
  kill(); update()
  M.env.MailFrame = nil
  MQ.bankOpen = true
  kill(); update()
  MQ.bankOpen = nil
  M.env.IsInInstance = function() return true, "party" end
  kill(); update()
  M.env.IsInInstance = function() return false, "none" end
  assert(total() == n0, "the mailbox, the bank, an instance: nothing noted")
  local asking = C.GetPlayerMapPosition
  C.GetPlayerMapPosition = function() return { x = px, y = py } end -- a place on any map, so only the map id is hidden
  C.GetBestMapForUnit = function() return SECRET.num() end
  kill(); update()
  C.GetBestMapForUnit = function() return nil end
  kill(); update()
  C.GetPlayerMapPosition = asking
  C.GetBestMapForUnit = function() return map end
  C.GetPlayerMapPosition = function() return SECRET.str() end
  kill(); update()
  C.GetPlayerMapPosition = function() return nil end
  kill(); update()
  C.GetPlayerMapPosition = function() return { x = SECRET.num(), y = 0.5 } end
  kill(); update()
  C.GetPlayerMapPosition = function() return { x = 0, y = 0 } end
  kill(); update()
  assert(total() == n0, "a hidden map or position, or none: nothing noted, and no error")
  -- the client hides the objectives themselves: nothing, no error; once they show again they are a fresh start
  C.GetPlayerMapPosition = function() return { x = px, y = py } end
  kills.numFulfilled = SECRET.num(); update()
  kills.numFulfilled = have; update()
  assert(total() == n0, "hidden counts: nothing noted")
  kill(); update()
  assert(total() == n0 + 1, "and counted again once they show")
  M.env.IsInInstance = nil
  -- a hidden "finished" is not "not finished": the line showing finished again, with nothing done, is no progress
  M.objectives[7][2] = { text = "Camp scouted", type = "event", finished = true }
  update()
  M.objectives[7][2].finished = SECRET.bool(); update()
  M.objectives[7][2].finished = true; update()
  assert(total() == n0 + 1, "finished, hidden, finished again: nothing noted")
  M.objectives[7][2].finished = SECRET.bool(); update()
  M.objectives[7][2].finished = false; update()
  M.objectives[7][2].finished = true; update()
  assert(total() == n0 + 2, "not finished, then finished: noted")
  M.objectives[7][2] = nil

  -- what you make is not found where you stand: an item objective that ticks with a crafting window open, or a moment
  -- after it shut or after a craft was cast ("create all" can go on with the window shut), is not noted. A kill
  -- meanwhile is; so is an item bought (the vendor is where it is got), or one that comes after a spell that makes
  -- nothing (a fish, an herb, a hide are found where you stand)
  table.insert(M.log, { 4245, 0 })
  local bandage = { text = "Linen Bandage: 0/10", type = "item", finished = false, numFulfilled = 0, numRequired = 10 }
  M.objectives[4245] = { bandage }
  update()
  tick(M, 4)
  local function make() bandage.numFulfilled = bandage.numFulfilled + 1; update() end
  local function cast(spell) f.__scripts.OnEvent(f, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. spell, spell) end
  local n1 = total()
  local window = { IsShown = function() return true end }
  M.env.ProfessionsFrame = window
  M.env.C_TradeSkillUI = { GetRecipeInfo = function(spell) return spell == 3275 and { recipeID = 3275 } or nil end }
  f.__scripts.OnEvent(f, "TRADE_SKILL_SHOW")
  tick(M, 6)
  make()
  assert(total() == n1, "made at the crafting window: nothing noted")
  kill(); update()
  assert(total() == n1 + 1, "a kill with the window open: noted")
  cast(3275) -- Linen Bandage, made at the window
  cast(133) -- a spell cast with the window open that makes nothing: no recipe
  tick(M, 6)
  window.IsShown = function() return false end
  f.__scripts.OnEvent(f, "TRADE_SKILL_CLOSE")
  tick(M, 1); make()
  assert(total() == n1 + 1, "made as the window shut: nothing noted")
  tick(M, 6)
  cast(3275) -- create all goes on, the window shut
  tick(M, 1); make()
  assert(total() == n1 + 1, "made with the window shut: nothing noted")
  tick(M, 6)
  f.__scripts.OnEvent(f, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-hidden", SECRET.num()) -- a cast the client hides
  cast(133)
  tick(M, 1); make()
  assert(total() == n1 + 2, "after a spell that makes nothing: noted")
  M.env.ProfessionsFrame = nil
  M.env.MerchantFrame = { IsShown = function() return true end }
  make()
  assert(total() == n1 + 3, "bought: noted, at the vendor")
  M.env.MerchantFrame = nil
  M.env.TradeSkillFrame = { IsShown = function() return true end }
  make()
  assert(total() == n1 + 3, "the Classic crafting window too")
  M.env.TradeSkillFrame, M.env.C_TradeSkillUI = nil, nil
  table.remove(M.log)
  M.objectives[4245] = nil

  -- no names: a kind and numbers, nothing else
  for id, q in pairs(spotsOf()) do
    assert(type(id) == "number", "by quest id")
    for i, o in pairs(q) do
      assert(type(i) == "number" and (o.t == nil or ({ monster = true, item = true, object = true, event = true })[o.t]), "the game's kind of objective")
      for k in pairs(o) do assert(k == "t" or k == "p", "only t and p: " .. tostring(k)) end
      for _, pt in ipairs(o.p) do
        assert(#pt == 4, "map, x, y, sightings")
        for _, v in ipairs(pt) do assert(type(v) == "number" and v == math.floor(v), "whole numbers") end
        assert(pt[2] >= 0 and pt[2] <= 1000 and pt[3] >= 0 and pt[3] <= 1000, "in thousandths")
      end
    end
  end

  -- at most 8 points an objective: a ninth place puts out the oldest of those seen fewest times; once every point
  -- was seen more than once, a new place is the one left out
  for i = 1, 8 do Dz.NoteSpot(4243, 1, "monster", 1429, i * 100, 100) end
  Dz.NoteSpot(4243, 1, "monster", 1429, 205, 100) -- the second place, seen twice
  Dz.NoteSpot(4243, 1, "monster", 1429, 950, 950)
  p = pts(4243, 1)
  assert(#p == 8 and p[1][2] == 203 and p[1][4] == 2 and p[2][2] == 300 and p[8][2] == 950, "the first place (seen once) went for the ninth")
  for _, pt in ipairs(p) do if pt[4] == 1 then Dz.NoteSpot(4243, 1, "monster", pt[1], pt[2], pt[3]) end end
  assert(Dz.NoteSpot(4243, 1, "monster", 1429, 50, 900) == nil and #pts(4243, 1) == 8, "every point seen twice: the new place is left out")
  -- at most 400 quests: the one touched longest ago goes
  local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
  for id = 500001, 500400 do Dz.NoteSpot(id, 1, "item", 1429, 10, 10) end
  assert(count(spotsOf()) == 400 and spotsOf()[7] == nil and spotsOf()[4243] == nil and spotsOf()[500001], "400 quests: the oldest went")
  Dz.NoteSpot(500001, 1, "item", 1429, 10, 10)
  Dz.NoteSpot(500401, 1, "item", 1429, 10, 10)
  assert(count(spotsOf()) == 400 and spotsOf()[500001] and spotsOf()[500002] == nil and spotsOf()[500401], "touched again, it stays; the next oldest goes")
  assert(count(DB.disc.osAt) == 400, "and nothing is kept for a quest that went")
  print(string.format("objective spots: %d quests kept, %d points for the last", count(spotsOf()), #pts(500401, 1)))
  assert(#(DB.errors or {}) == errs0, "objective spots: no errors, " .. tostring(((DB.errors or {})[errs0 + 1] or {}).msg))
  DB.disc.os, DB.disc.osAt, DB.disc.osN = nil, nil, nil
  C.GetPlayerMapPosition, C.GetBestMapForUnit = savePos, saveBest
  kills.numFulfilled, kills.text, kills.finished = 3, "Kobold Vermin slain: 3/10", false
  bandanas.numFulfilled, bandanas.text = 2, "Red Burlap Bandana: 2/12"
end

-- a fresh login: for its first seconds the log only learns where things stand (the server fills objectives in
-- after the quest list); then a kill is noted
do
  local tam = newClient({
    name = "Tamsin", level = 3, cap = 60, faction = "Alliance", className = "Mage", class = "MAGE", classID = 8, race = "Human",
    log = { { 7, 0 } }, done = { [783] = true }, group = false, guild = false, world = { 0, -8914, -133 }, bind = "Northshire Abbey",
    riding = false, bagSlots = {}, xp = 100, map = 1429,
  })
  tam.objectives = { [7] = { { text = "Kobold Vermin slain: 0/10", type = "monster", finished = false, numFulfilled = 0, numRequired = 10 } } }
  tam.ev(tam.QB.eventFrame, "ADDON_LOADED", "QuestBank")
  tam.ev(tam.QB.eventFrame, "PLAYER_LOGIN")
  local f = tam.QB.Discover.frame
  local function update() f.__scripts.OnEvent(f, "QUEST_LOG_UPDATE"); tick(tam, 1) end
  update()
  tam.objectives[7][1].numFulfilled = 4
  update()
  local d = tam.env.QuestBankDB.disc
  assert(d.os == nil or next(d.os) == nil, "just logged in: the counts the server sends now are no progress")
  tick(tam, 15)
  tam.objectives[7][1].numFulfilled = 5
  update()
  assert(d.os and d.os[7] and d.os[7][1].p[1][1] == 1429 and d.os[7][1].p[1][2] == 660 and d.os[7][1].p[1][3] == 620, "settled: a kill is noted")
end

-- a slow load: the loading screen outlasts those first seconds, so the wait starts again when the world shows; and
-- every loading screen after it (a boat, a portal: the server can send the objectives anew) starts it again
do
  local tove = newClient({
    name = "Tove", level = 3, cap = 60, faction = "Alliance", className = "Mage", class = "MAGE", classID = 8, race = "Human",
    log = { { 7, 0 } }, done = { [783] = true }, group = false, guild = false, world = { 0, -8914, -133 }, bind = "Northshire Abbey",
    riding = false, bagSlots = {}, xp = 100, map = 1429,
  })
  local line = { text = "Kobold Vermin slain: 0/10", type = "monster", finished = false, numFulfilled = 0, numRequired = 10 }
  tove.objectives = { [7] = { line } }
  tove.ev(tove.QB.eventFrame, "ADDON_LOADED", "QuestBank")
  tove.ev(tove.QB.eventFrame, "PLAYER_LOGIN")
  local f = tove.QB.Discover.frame
  local function on(event, ...) f.__scripts.OnEvent(f, event, ...) end
  local function update() on("QUEST_LOG_UPDATE"); tick(tove, 1) end
  local d = tove.env.QuestBankDB.disc
  local function noted() local p = d.os and d.os[7] and d.os[7][1] and d.os[7][1].p[1]; return p and p[4] or 0 end
  on("PLAYER_ENTERING_WORLD", true, false)
  update()
  tick(tove, 12) -- still loading
  on("LOADING_SCREEN_DISABLED")
  line.numFulfilled = 4
  update()
  assert(noted() == 0, "a slow load: the counts that come as the world shows are no progress")
  tick(tove, 11)
  line.numFulfilled = 5
  update()
  assert(noted() == 1, "then a kill is noted")
  on("PLAYER_ENTERING_WORLD", false, false)
  line.numFulfilled = 6
  update()
  assert(noted() == 1, "just through a loading screen: not noted")
  tick(tove, 11)
  line.numFulfilled = 7
  update()
  assert(noted() == 2, "a moment later: noted again")
  assert(#(tove.env.QuestBankDB.errors or {}) == 0, "loading screens: no errors")
end

-- Classic Era: nothing noted (gen_data shows these as Forever's)
do
  local c = sigrun
  local f = c.QB.Discover.frame
  c.log = { { 7, 0 } }
  c.objectives = { [7] = { { text = "Kobold Vermin slain: 3/10", type = "monster", finished = false, numFulfilled = 3, numRequired = 10 } } }
  f.__scripts.OnEvent(f, "QUEST_LOG_UPDATE"); tick(c, 0)
  c.objectives[7][1].numFulfilled = 4
  f.__scripts.OnEvent(f, "QUEST_LOG_UPDATE"); tick(c, 0)
  c.QB.Discover.Look(); c.objectives[7][1].numFulfilled = 5; c.QB.Discover.Look()
  assert(c.env.QuestBankDB.disc.os == nil, "Classic Era: no objective spots")
  c.log, c.objectives = {}, nil
end

-- the Horde shaman in the Barrens sees no Alliance quests; the owner in Stormwind, how long a full redraw takes
do
  local H = horde.QB
  horde.map.id = 1413
  H:Settings().pins = false
  H:Recompute(true); H.Model.Finish(); H.Pins:Update(); H.QuestMap:Update()
  local n = 0
  for _, pin in ipairs(ours(horde, "QuestBankQuestPinTemplate")) do
    for _, q in ipairs(pin.data.quests or {}) do assert(q.side ~= 1, "no Alliance quest on the Horde's map: " .. q.name) end
    n = n + 1
  end
  assert(n > 0, "the Horde has icons in the Barrens")
  print("map icons, the Barrens for the Horde shaman:", n)
  local O = owner.QB
  owner.map.id = 1453
  local t0 = owner.env.debugprofilestop()
  for _ = 1, 10 do O.QuestMap.provider:RefreshAllData() end
  print(string.format("map icons, Stormwind for the owner: %d icons, %.1f ms a redraw", #ours(owner, "QuestBankQuestPinTemplate"), (owner.env.debugprofilestop() - t0) / 10))
  -- the real data, whatever gen_data has written so far: every map with a spot draws without an error
  local D0 = O.Data
  if D0.SPOT then
    local maps, spots = {}, 0
    for _, str in pairs(D0.SPOT) do for _, sp in ipairs(O.QuestMap.Spots(str) or {}) do maps[sp.m] = true; spots = spots + 1 end end
    for _, str in pairs(D0.START or {}) do for _, sp in ipairs(O.QuestMap.Spots(str) or {}) do maps[sp.m] = true; spots = spots + 1 end end
    local drawn = 0
    for m in pairs(maps) do drawn = drawn + #O.QuestMap:Build(m) end
    print(string.format("map icons, real data: %d spots on %d maps; %d icons for the owner", spots, (function() local k = 0 for _ in pairs(maps) do k = k + 1 end return k end)(), drawn))
  end
end

----------------------------------------------------------------------------
-- calls QuestBank's code never makes, read from the files themselves (code only, comments left out). Each one runs
-- the game's own code as QuestBank, where the game later blocks it and blames QuestBank:
--   the game's waypoint and tracking (USER_WAYPOINT_UPDATED, SUPER_TRACKING_CHANGED and QUEST_WATCH_LIST_CHANGED run
--   Blizzard's listeners inside the call), Blizzard's popups (their list of popups on screen), opening the chat box
--   (the game's chat globals), the escort prompt's Yes with no click behind it and its count of a full log (MAX_QUESTS:
--   read, never written; the prompt reads it as it opens), and the map canvas's pin calls
----------------------------------------------------------------------------
do
  -- whole names (CanSetUserWaypointOnMap, a question, is fine), and the start of a family (StaticPopup_Show, _Hide...)
  local NEVER = { "SetUserWaypoint", "ClearUserWaypoint", "C_SuperTrack", "AddQuestWatch", "RemoveQuestWatch",
    "AddWorldQuestWatch", "AddQuestWatchForQuestID", "StaticPopupDialogs", "OpenChat", "ChatFrame_OpenChat", "ActivateChat",
    "ACTIVE_CHAT_EDIT_BOX", "LAST_ACTIVE_CHAT_EDIT_BOX", "ConfirmAcceptQuest", "AcquirePin", "RemoveAllPinsByTemplate",
    "RemovePin", "SetPinPosition", "MarkCanvasDirty", "UpdateQuestAcceptLogFullDialog", "MAX_QUESTLOG_QUESTS" }
  local FAMILIES = { "StaticPopup_", "SetSuperTracked" }
  local PATTERNS = {}
  for _, name in ipairs(NEVER) do PATTERNS[#PATTERNS + 1] = { "%f[%w_]" .. name .. "%f[^%w_]", name } end
  for _, name in ipairs(FAMILIES) do PATTERNS[#PATTERNS + 1] = { "%f[%w_]" .. name, name .. "*" } end
  -- ChatFrameUtil's LinkItem opens the box when none is open: the name in a string is how QuestBank would reach it
  PATTERNS[#PATTERNS + 1] = { "[\"']LinkItem[\"']", "ChatFrameUtil LinkItem" }
  -- the game's MAX_QUESTS is read (the escort prompt's count), never written: the prompt reads it as it opens
  PATTERNS[#PATTERNS + 1] = { "%f[%w_]MAX_QUESTS%s*=%f[^=]", "MAX_QUESTS =" }
  -- a line without its comment (a "--" outside a string)
  local function code(line)
    local q, i = nil, 1
    while i <= #line do
      local ch = line:sub(i, i)
      if q then
        if ch == "\\" then i = i + 1 elseif ch == q then q = nil end
      elseif ch == '"' or ch == "'" then q = ch
      elseif line:sub(i, i + 1) == "--" then return line:sub(1, i - 1) end
      i = i + 1
    end
    return line
  end
  local found, files = {}, 0
  for line in io.lines(HERE .. "/QuestBank/QuestBank.toc") do
    local f = line:match("^%s*([%w_]+%.lua)%s*$")
    if f and f ~= "Data.lua" then
      files = files + 1
      local n = 0
      for src in io.lines(HERE .. "/QuestBank/" .. f) do
        n = n + 1
        local c = code(src)
        for _, pat in ipairs(PATTERNS) do
          if c:find(pat[1]) then found[#found + 1] = string.format("%s:%d %s", f, n, pat[2]) end
        end
      end
    end
  end
  assert(files >= 10, "every Lua file the TOC lists was read")
  assert(#found == 0, "QuestBank's code makes a call that runs the game's code as QuestBank:\n  " .. table.concat(found, "\n  "))
  print("calls QuestBank never makes:", #PATTERNS, "names, none in", files, "files")
end

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
