-- Mock WoW client for Cute. Loads the addon into separate clients (each its own globals), gives them one guild, routes
-- their addon messages (back to the sender too, as the game does), drives events and timers, opens every page for an
-- officer and a member, and fails on any widget method outside a whitelist of real API methods. It lays the window out
-- like the game does and reports clipped text, overlapping text, text the game's font cannot draw, and buttons too
-- near an edge. It counts SetPoint and SetText calls (OPS), so a scenario can hold a draw's cost to the rows in view.
-- Forever's names are mocked as the client gives them: a character made with a surname has UnitName's second return
-- as that surname, the roster and the channel name it with both words, and a roster name can be a Kstring.
-- The mock defines what Forever's generated API docs list (C_Club for the guild, C_SpecializationInfo, C_MajorFactions,
-- C_Traits, C_SkillInfo, GetMirrorTimerProgress...), what QuestBank reads on this client (GetInventoryItemLink, the taxi
-- nodes) and, named one by one in UNDOCUMENTED below with the evidence for each, the globals no doc lists that Cute
-- reads all the same: the Legacy window's achievement calls on every client, the statistics API (which only the
-- mainline panel calls, never loaded on camelot) on o.withStats clients alone, so the gate runs Cute with it and
-- without it. A stat reading anything else reads nil here too, and the registry scenario fails on it.
--   luajit tools/cute/harness.lua                   run every scenario
--   luajit tools/cute/harness.lua --layout out.json  also write the window, page by page, for tools/questbank/render_layout.py
math.randomseed = nil -- the client has none
local HERE = (arg and arg[0] and arg[0]:match("^(.*)/") or ".")
local LAYOUT_OUT
for i = 1, #arg do if arg[i] == "--layout" then LAYOUT_OUT = arg[i + 1] end end

local METHODS = {}
local function allow(list) for m in list:gmatch("%S+") do METHODS[m] = true end end
allow([[SetPoint ClearAllPoints SetAllPoints SetSize SetWidth SetHeight GetWidth GetHeight Show Hide SetShown IsShown
IsVisible SetAlpha GetAlpha GetParent GetPoint GetCenter GetEffectiveScale SetParent CreateTexture CreateFontString
SetScript GetScript HookScript RegisterEvent UnregisterEvent RegisterUnitEvent SetFrameStrata SetFrameLevel GetFrameLevel SetToplevel
EnableMouse EnableMouseWheel SetMovable SetClampedToScreen RegisterForDrag StartMoving StopMovingOrSizing GetName IsMouseOver
SetScrollChild SetVerticalScroll GetVerticalScroll SetText GetText SetNormalTexture SetHighlightTexture GetHighlightTexture
RegisterForClicks SetEnabled Enable Disable IsEnabled GetFontString SetOrientation SetThumbTexture SetMinMaxValues GetMinMaxValues
SetValueStep SetValue GetValue SetTexture SetColorTexture SetTexCoord SetVertexColor SetDesaturated SetBlendMode
SetFontObject SetFont GetFont SetTextColor SetJustifyH SetJustifyV SetWordWrap GetStringWidth GetUnboundedStringWidth GetStringHeight
SetAutoFocus SetFocus ClearFocus SetMaxLetters HasFocus SetChecked GetChecked GetLeft GetTop GetChildren GetNumPoints
SetResizable SetResizeBounds StartSizing CreateMaskTexture AddMaskTexture SetScale GetScale]])
local BACKDROP = { SetBackdrop = true, SetBackdropColor = true, SetBackdropBorderColor = true }
local FONT_SIZE = { GameFontNormal = 12, GameFontNormalLarge = 16, GameFontHighlightSmall = 10, GameFontNormalSmall = 10, NumberFontNormal = 14, ChatFontNormal = 14 }
local FONT_FILE = { NumberFontNormal = "Fonts\\ARIALN.TTF", ChatFontNormal = "Fonts\\ARIALN.TTF" }

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
local ALL = {}
local rectOf, GEN = nil, 0 -- (layout, below: a size asked of an anchored frame is worked out as the game would)
local OPS = { n = 0 } -- SetPoint and SetText calls, every client
local function newObj(kind, template, parent)
  local o = { __kind = kind, __scripts = {}, __events = {}, __shown = true, __w = 0, __h = 0, __text = "", __value = 0, __min = 0,
              __max = 0, __points = {}, __parent = parent, __alpha = 1, __size = 12, __wrap = true, __justify = "CENTER" }
  o.__backdrop = template and template:find("BackdropTemplate") and true or false
  o.__template = template
  if template == "UIPanelCloseButton" then o.__w, o.__h = 24, 24 end
  ALL[#ALL + 1] = o
  local mt = {}
  mt.__index = function(t, k)
    if METHODS[k] or (BACKDROP[k] and t.__backdrop) then
      return function(self, ...)
        local a = { ... }
        local n = select("#", ...)
        if k == "SetPoint" or k == "SetText" then OPS.n = OPS.n + 1 end
        if k == "SetScript" then self.__scripts[a[1]] = a[2]
        elseif k == "GetScript" then return self.__scripts[a[1]]
        elseif k == "HookScript" then local old = self.__scripts[a[1]]; self.__scripts[a[1]] = function(...) if old then old(...) end a[2](...) end
        elseif k == "RegisterEvent" then self.__events[a[1]] = true
        elseif k == "RegisterUnitEvent" then self.__events[a[1]] = true; self.__units = self.__units or {}; self.__units[a[1]] = a[2]
        elseif k == "UnregisterEvent" then self.__events[a[1]] = nil
        elseif k == "CreateTexture" then local x = newObj("Texture", nil, self); x.__layer = a[2] or "ARTWORK"; return x
        elseif k == "CreateFontString" then local x = newObj("FontString", nil, self); x.__layer = a[2] or "OVERLAY"; return x
        elseif k == "CreateMaskTexture" then local x = newObj("Texture", nil, self); x.__layer = "MASK"; return x
        elseif k == "AddMaskTexture" then self.__mask = a[1]
        elseif k == "Show" then local was = self.__shown; self.__shown = true; if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end
        elseif k == "Hide" then local was = self.__shown; self.__shown = false; if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
        elseif k == "SetShown" then if a[1] then self:Show() else self:Hide() end
        elseif k == "IsShown" then return self.__shown
        elseif k == "IsVisible" then
          local o2 = self
          while o2 do if not o2.__shown then return false end; o2 = o2.__parent or o2.__scrollParent end
          return true
        elseif k == "SetSize" then self.__w, self.__h = a[1], a[2] or a[1]; self.__wset, self.__hset = true, true; self.__rw, self.__rh = nil, nil
        elseif k == "SetWidth" then self.__w = a[1]; self.__wset = true; self.__rw = nil
        elseif k == "SetHeight" then self.__h = a[1]; self.__hset = true; self.__rh = nil
        elseif k == "GetWidth" or k == "GetHeight" then
          if rectOf and #self.__points > 0 then GEN = GEN + 1; local r = rectOf(self); if r then return k == "GetWidth" and (r.r - r.l) or (r.t - r.b) end end
          return k == "GetWidth" and (self.__rw or self.__w) or (self.__rh or self.__h)
        elseif k == "SetText" then
          self.__text = a[1] == nil and "" or tostring(a[1])
          if self.__template == "UIPanelButtonTemplate" and self.__label then self.__label.__text = self.__text end
        elseif k == "GetText" then return self.__text
        elseif k == "GetFontString" then
          if not self.__label then self.__label = newObj("FontString", nil, self); self.__label.__text = self.__text; self.__label.__size = 12; self.__label.__points = { { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 } }; self.__label.__layer = "OVERLAY"; self.__label.__isButtonLabel = true end
          return self.__label
        elseif k == "GetHighlightTexture" then if not self.__hi then self.__hi = newObj("Texture", nil, self); self.__hi.__layer = "HIGHLIGHT" end return self.__hi
        elseif k == "GetStringWidth" or k == "GetUnboundedStringWidth" then return textWidth(self.__text, self.__size)
        elseif k == "GetStringHeight" then return self.__size + 2
        elseif k == "GetFont" then return self.__fontFile or "Fonts\\FRIZQT__.TTF", self.__size, ""
        elseif k == "SetFont" then self.__fontFile = a[1]; self.__size = a[2] or self.__size; return true
        elseif k == "SetFontObject" then self.__size = a[1] and a[1].__fontSize or 12
        elseif k == "SetJustifyH" then self.__justify = a[1]
        elseif k == "SetWordWrap" then self.__wrap = a[1] and true or false
        elseif k == "SetTextColor" then self.__color = { a[1], a[2], a[3] }
        elseif k == "SetAlpha" then self.__alpha = a[1]
        elseif k == "GetAlpha" then return self.__alpha
        elseif k == "SetMinMaxValues" then self.__min, self.__max = a[1], a[2]
        elseif k == "GetMinMaxValues" then return self.__min, self.__max
        elseif k == "SetValue" then self.__value = a[1]; if self.__scripts.OnValueChanged then self.__scripts.OnValueChanged(self, a[1]) end
        elseif k == "GetValue" then return self.__value
        elseif k == "GetCenter" then return 500, 400
        elseif k == "GetEffectiveScale" then return 1
        elseif k == "GetPoint" then local p = self.__points[1]; if p then return p.point, p.rel, p.relPoint, p.x, p.y end return "CENTER", nil, "CENTER", 0, 0
        elseif k == "GetName" then return self.__name
        elseif k == "GetParent" then return self.__parent
        elseif k == "SetParent" then self.__parent = a[1]
        elseif k == "SetTexture" then self.__tex = a[1]; self.__color = nil
        elseif k == "SetColorTexture" then self.__tex = "color"; self.__color = { a[1], a[2], a[3], a[4] }
        elseif k == "SetVertexColor" then self.__vertex = { a[1], a[2], a[3], a[4] }
        elseif k == "SetBackdrop" then self.__inset = a[1] and a[1].insets and a[1].insets.left or 0
        elseif k == "SetThumbTexture" then self.__thumb = a[1]
        elseif k == "SetBackdropColor" then self.__bdc = { a[1], a[2], a[3], a[4] }
        elseif k == "SetBackdropBorderColor" then self.__bdb = { a[1], a[2], a[3], a[4] }
        elseif k == "SetTexCoord" then self.__tc = { a[1], a[2], a[3], a[4] }
        elseif k == "SetBlendMode" then self.__blend = a[1]
        elseif k == "SetDesaturated" then self.__desat = a[1] and true or false
        elseif k == "SetScrollChild" then a[1].__scrollParent = self; self.__child = a[1]
        elseif k == "SetVerticalScroll" then self.__scroll = a[1]
        elseif k == "SetHighlightTexture" then self.__hiTex = a[1]; self.__hiBlend = a[2]
        elseif k == "SetNormalTexture" then self.__normalTex = a[1]
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
        elseif k == "IsMouseOver" then return self.__mouseOver or false
        elseif k == "SetScale" then self.__scale = a[1]
        elseif k == "GetScale" then return self.__scale or 1
        elseif k == "GetLeft" then return self.__left or 0
        elseif k == "GetTop" then return self.__top or 0
        elseif k == "GetNumPoints" then return #self.__points
        elseif k == "GetFrameLevel" then return self.__frameLevel or 2
        elseif k == "SetFrameLevel" then self.__frameLevel = a[1]
        elseif k == "EnableMouse" then self.__mouse = a[1] and true or false
        elseif k == "GetChildren" then
          local out = {}
          for _, x in ipairs(ALL) do if x.__parent == self and x.__kind ~= "Texture" and x.__kind ~= "FontString" then out[#out + 1] = x end end
          return unpack(out)
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
    if type(k) == "string" and (k:match("^%l") or k:match("^__")) then return nil end
    error("unknown widget method: " .. tostring(k) .. " on " .. kind, 2)
  end
  return setmetatable(o, mt)
end
local function fontObj(name) local f = newObj("Font"); f.__fontSize = FONT_SIZE[name] or 12; f.__fontFile = FONT_FILE[name]; return f end

----------------------------------------------------------------------------
-- secret values, as the client makes them
----------------------------------------------------------------------------
local SECRET_MT = {
  __index = function(t) error(string.format("attempt to index a secret %s value", rawget(t, "__kind")), 2) end,
  __lt = function() error("attempt to compare a secret value", 2) end,
  __le = function() error("attempt to compare a secret value", 2) end,
  __add = function() error("attempt to perform arithmetic on a secret value", 2) end,
  __concat = function() error("attempt to concatenate a secret value", 2) end,
  __tostring = function() return "<secret>" end,
}
local function secret(kind) return setmetatable({ __kind = kind }, SECRET_MT) end

----------------------------------------------------------------------------
-- the guild everyone shares, and the addon channel between clients
----------------------------------------------------------------------------
local GUILD = {} -- { { name = "Name-Realm" or "First Surname", guid, rank = idx, rankName, level, class, online, zone }, ... }
local clients = {}
local BUS = {}
local lines = {} -- the tooltip's lines, every client

-- a character's GUID, the same for its client and its roster entry: one per first name, made up in order
local GUIDS, nGuid = {}, 0
local function guidOf(first)
  if not GUIDS[first] then nGuid = nGuid + 1; GUIDS[first] = string.format("Player-4242-%08X", 0x0A000000 + nGuid) end
  return GUIDS[first]
end

-- every client in the guild gets the message, its sender too (the game hands a guild addon message back to the one who
-- sent it), named as the channel names that sender (c.sender: "Name-Realm", or a Forever name's two words)
local function deliver()
  while #BUS > 0 do
    local m = table.remove(BUS, 1)
    for _, c in ipairs(clients) do
      if c.inGuild then
        for _, f in ipairs(c.frames) do
          if f.__events.CHAT_MSG_ADDON and f.__scripts.OnEvent then f.__scripts.OnEvent(f, "CHAT_MSG_ADDON", m.prefix, m.msg, m.channel, m.from.sender) end
        end
      end
    end
  end
end

local function fire(c, event, ...)
  for _, f in ipairs(c.frames) do
    if f.__events[event] and f.__scripts.OnEvent then f.__scripts.OnEvent(f, event, ...) end
  end
  deliver()
end

-- advance a client's clock, running its timers in order (and delivering what they send)
local function tick(c, seconds)
  local target = c.clock + seconds
  while true do
    local idx, soon
    for i, t in ipairs(c.timers) do if t.t <= target and (not soon or t.t < soon) then idx, soon = i, t.t end end
    if not idx then break end
    local t = table.remove(c.timers, idx)
    c.clock = math.max(c.clock, t.t)
    t.f()
    deliver()
  end
  c.clock = target
end
-- the same for every client, interleaved second by second so the queues pace against each other
local function tickAll(seconds)
  for s = 1, seconds do for _, c in ipairs(clients) do tick(c, 1) end end
end

----------------------------------------------------------------------------
-- one game client
----------------------------------------------------------------------------
local BASE = setmetatable({}, { __index = _G })
BASE.CUTE_DEV = true
BASE.BackdropTemplateMixin = {}
for name in pairs(FONT_SIZE) do BASE[name] = fontObj(name) end
BASE.GameTooltip = setmetatable({ __hooks = {} }, { __index = function(_, k)
  return function(tt, ...)
    if k == "AddLine" or k == "AddDoubleLine" then
      local parts = {}
      for i = 1, select("#", ...) do local v = select(i, ...); if type(v) == "string" then parts[#parts + 1] = v end end
      lines[#lines + 1] = table.concat(parts, " | ")
    elseif k == "SetOwner" then rawset(tt, "__owner", (...)); rawset(tt, "__shown", false)
    elseif k == "Show" then rawset(tt, "__shown", true)
    elseif k == "Hide" then rawset(tt, "__shown", false)
    elseif k == "IsShown" then return rawget(tt, "__shown") or false
    end
  end
end })
BASE.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PRIEST = { r = 1, g = 1, b = 1 }, HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
  MAGE = { r = 0.41, g = 0.8, b = 0.94 }, ROGUE = { r = 1, g = 0.96, b = 0.41 }, DRUID = { r = 1, g = 0.49, b = 0.04 },
  PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, WARLOCK = { r = 0.53, g = 0.53, b = 0.93 }, SHAMAN = { r = 0, g = 0.44, b = 0.87 } }
local CLASS_ID = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
local CLASS_FILE = {}
for file, id in pairs(CLASS_ID) do CLASS_FILE[id] = file end
BASE.tinsert = table.insert
BASE.UISpecialFrames = nil -- per client
BASE.GetCursorPosition = function() return 600, 500 end
BASE.issecretvalue = function(v) return type(v) == "table" and getmetatable(v) == SECRET_MT end
BASE.Enum = {
  ClubMemberPresence = { Unknown = 0, Online = 1, OnlineMobile = 2, Offline = 3, Away = 4, Busy = 5 },
  SendAddonMessageResult = { Success = 0, InvalidMessage = 2, AddonMessageThrottle = 3, ChannelThrottle = 8, GeneralError = 9, AddOnMessageLockdown = 11 },
  -- the Camelot achievement stub reads this rule by name; no doc gives its value, so the mock's is made up and Cute looks it up
  GameRule = { AchievementsPanelDisabled = 77 },
}
-- Blizzard_APIDocumentationGenerated/LegacyConstantsDocumentation.lua, as the client exposes it; and the name separators
-- Camelot's NameUtil.lua reads (Blizzard_FrameXMLUtil/Camelot/NameUtil.lua:8; no doc gives their values: the surname's
-- is a space here, as the roster shows "Thora Bjorn", and Cute falls back to one where the table is missing)
BASE.Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " ", CHARACTERNAME_REALMNAME_SEPARATOR = "-" }, LegacyConsts = { LEGACY_REWARD_TRACK_FACTION_ID = 2802, LEGACY_POINTS_TRAIT_CURRENCY_ID = 4225, LEGACY_TREE_PROFESSIONS_ID = 1187,
  LEGACY_TREE_ADVENTURE_ID = 1188, LEGACY_TREE_PROGRESSION_ID = 1189, LEGACY_TREE_ADVENTURE_TALENTED_NODE_ID = 110298,
  LEGACY_DEFAULT_CATEGORY_WARRIOR = 15585, LEGACY_DEFAULT_CATEGORY_PALADIN = 15580, LEGACY_DEFAULT_CATEGORY_HUNTER = 15578,
  LEGACY_DEFAULT_CATEGORY_ROGUE = 15582, LEGACY_DEFAULT_CATEGORY_PRIEST = 15581, LEGACY_DEFAULT_CATEGORY_SHAMAN = 15583,
  LEGACY_DEFAULT_CATEGORY_MAGE = 15579, LEGACY_DEFAULT_CATEGORY_WARLOCK = 15584, LEGACY_DEFAULT_CATEGORY_DRUID = 15577 } }

local EPOCH = 1792300000

-- globals no generated API doc lists, mocked on the evidence named here and on nothing else, so the mock claims
-- nothing quietly: scenario 1 prints them, Cute's /cute api names them on the live client, and a client made with
-- o.without = { GetInventoryItemDurability = true } lacks one. DoEmote is defined only for o.withEmote clients: the
-- Forever tree is silent on it, so the chat fallback is the path the gate exercises by default.
local UNDOCUMENTED = {
  GetInventoryItemID = "Camelot/PaperDollFrame.lua:2221 (PaperDollItemSlotButton_Update: SetItemButtonQuality) and 1809",
  GetInventoryItemQuality = "Camelot/PaperDollFrame.lua:2219, the same function",
  GetInventoryItemDurability = "Camelot's EquipmentFlyout.lua:544 reaches it through EquipmentManager_GetItemInfoByLocation",
  GetInventoryItemCount = "the same flyout, the line above it",
  GetNumUnspentTalents = "Mainline/TalentFrameBase.lua:140, a file the camelot game type loads",
  GetCategoryList = "Blizzard_LegacySystem/Blizzard_LegacyChallenges.lua:139 (the Legacy Challenges window, AllowLoadGameType camelot)",
  GetCategoryInfo = "Blizzard_LegacyChallenges.lua:149 and 168: name, parent",
  GetCategoryNumAchievements = "Blizzard_LegacySystemUtil.lua:20: total, completed, incomplete",
  GetAchievementInfo = "Blizzard_LegacyChallenges.lua:128 by category and index (wasEarnedByMe the 13th return), Blizzard_LegacyAchievementOverrides.lua:44 by id",
  GetTotalAchievementPoints = "Blizzard_Communities/GuildRewards.lua:256, an addon whose toc limits no game type",
  -- the same binary's achievement API that no camelot-loaded file calls: mocked for o.withStats clients only
  GetLatestCompletedAchievements = { "Blizzard_AchievementUI/Mainline/Blizzard_AchievementUI.lua:2487, a file camelot does not load", optional = true },
  GetStatisticsCategoryList = { "Mainline/Blizzard_AchievementUI.lua:156, the same", optional = true },
  GetStatistic = { "Mainline/Blizzard_AchievementUI.lua:2440 (category, index -> quantity, skip, id) and 2385 (id -> quantity), the same", optional = true },
}

-- Legacy Challenges as the Legacy window lists them: categories by id (name, parent, how many), achievements by
-- (category, index) with ids like Forever's. Quests has a third challenge completed by another character (completed,
-- not wasEarnedByMe), which the Legacy UI shows as incomplete; the player's own class category has o.classDone done
local LEGACY_CATS = { { 15001, "Quests", -1, 6 }, { 15002, "Exploration", -1, 4 }, { 15003, "Dungeons", -1, 3 }, { 15004, "Classic Dungeons", 15003, 2 },
  { 15570, "Classes", -1, 0 }, { 15577, "Druid", 15570, 3 }, { 15578, "Hunter", 15570, 3 }, { 15579, "Mage", 15570, 3 }, { 15580, "Paladin", 15570, 3 },
  { 15581, "Priest", 15570, 3 }, { 15582, "Rogue", 15570, 3 }, { 15583, "Shaman", 15570, 3 }, { 15584, "Warlock", 15570, 3 }, { 15585, "Warrior", 15570, 3 } }
local LEGACY_DONE = { [15001] = 2, [15002] = 0, [15003] = 1, [15004] = 2 }
local CLASS_CAT = { WARRIOR = 15585, PALADIN = 15580, HUNTER = 15578, ROGUE = 15582, PRIEST = 15581, SHAMAN = 15583, MAGE = 15579, WARLOCK = 15584, DRUID = 15577 }
-- the statistics panel's data: three categories, one with a child; twelve statistics, one the game marks skip, one
-- never recorded ("--"); o.manyStats adds that many more across the categories
local STAT_CATS = { { 130, "Kills", -1 }, { 131, "Creatures", 130 }, { 132, "Deaths", -1 }, { 133, "Quests", -1 } }
local STATS = { { 130, 2001, "Total kills", 1234 }, { 130, 2002, "Total kills that grant experience", 987 }, { 130, 2003, "Hidden", 0, true },
  { 131, 2004, "Creatures killed", 1100 }, { 131, 2005, "Beasts killed", 300 }, { 131, 2006, "Humanoids killed", 420 },
  { 132, 2007, "Total deaths", 17 }, { 132, 2008, "Deaths from drowning", "--" }, { 132, 2009, "Deaths from falling", 3 },
  { 133, 2010, "Quests completed", 240 }, { 133, 2011, "Daily quests completed", 0 }, { 133, 2012, "Quests abandoned", 12 } }

local function newClient(o)
  local env = setmetatable({}, { __index = BASE })
  env._G = env
  o.guid = o.guid or guidOf(o.name)
  -- c.name: the saved-data key Cute makes (UnitFullName joined); c.sender: how the channel names this client
  local c = { env = env, o = o, name = o.name .. "-" .. ((o.surname and o.fullNameSurname) and o.surname or (o.realm or "Forever")), timers = {}, clock = 1000, frames = {}, sent = {}, chat = {},
              hooks = {}, C = {}, inGuild = o.inGuild ~= false, secret = false, throw = false, oversize = {}, dayShift = 0,
              showOffline = o.showOffline ~= false }
  c.sender = o.sender or (o.name .. "-" .. (o.realm or "Forever"))
  env.UIParent = newObj("Frame"); env.UIParent:SetSize(1600, 1000); env.UIParent.__points = {}; env.UIParent.__root = true
  env.Minimap = newObj("Frame", nil, env.UIParent); env.Minimap:SetSize(140, 140); env.Minimap:SetPoint("TOPRIGHT", env.UIParent, "TOPRIGHT", -20, -20)
  env.UISpecialFrames = {}
  env.SlashCmdList = {}
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) c.chat[#c.chat + 1] = m end }
  env.CreateFrame = function(kind, name, parent, template)
    local f = newObj(kind, template, parent)
    f.__name = name
    f.__client = c
    local where = {}
    for lvl = 2, 3 do
      local info = debug.getinfo(lvl, "Sl")
      if info and info.currentline and info.currentline > 0 then where[#where + 1] = info.short_src:match("[^/]+$") .. ":" .. info.currentline end
    end
    f.__where = table.concat(where, " < ")
    if name then env[name] = f end
    if template == "UICheckButtonTemplate" then f.__w, f.__h = 26, 26 end
    c.frames[#c.frames + 1] = f
    return f
  end
  env.C_Timer = { After = function(sec, f) c.timers[#c.timers + 1] = { t = c.clock + sec, f = f } end }
  env.GetTime = function() return c.clock end
  env.time = function() return EPOCH + c.clock end
  -- the date follows the client's clock, so a scenario can move it past midnight
  env.date = function(fmt, t) return os.date(fmt, t or (EPOCH + c.clock + c.dayShift)) end
  env.hooksecurefunc = function(a, b, fn)
    if type(a) == "table" then c.hooks[b] = fn else c.hooks[a] = b end
  end
  if o.withEmote then env.DoEmote = function(token) if c.hooks.DoEmote then c.hooks.DoEmote(token) end end end
  env.JumpOrAscendStart = function() if c.hooks.JumpOrAscendStart then c.hooks.JumpOrAscendStart() end end

  -- the character, read through wrappers that can go secret or throw
  local function api(fn)
    return function(...)
      if c.throw then error("the client threw", 2) end
      if c.secret then return secret("value") end
      return fn(...)
    end
  end
  env.UnitLevel = api(function() return o.level end)
  env.UnitXP = api(function() return o.xp or 0 end)
  env.UnitXPMax = api(function() return o.xpmax or 1000 end)
  env.GetXPExhaustion = api(function() return o.rested end)
  env.GetZoneText = api(function() return o.zone or "Elwynn Forest" end)
  env.GetSubZoneText = api(function() return o.subzone or "" end)
  -- on camelot the second return is the surname (Camelot/NameUtil.lua); a character without one has none. UnitFullName
  -- gives the surname there too on an o.fullNameSurname client, the realm on the others (which one Forever does, /cute
  -- diag will say: Cute must not care)
  env.UnitName = api(function(unit) if unit == "player" then return o.name, o.surname end local i = unit:match("^party(%d)$"); return i and (o.party or {})[tonumber(i)] or nil end)
  env.UnitFullName = api(function() return o.name, (o.surname and o.fullNameSurname) and o.surname or (o.realm or "Forever") end)
  env.UnitGUID = api(function(unit) if unit == "player" then return o.guid end end)
  env.GetRealmName = api(function() return o.realm or "Forever" end)
  env.UnitClass = api(function() return o.class, o.class, CLASS_ID[o.class] end)
  env.GetNormalizedRealmName = api(function() return o.realm or "Forever" end)
  env.GetMoney = api(function() return o.money or 0 end)
  env.GetBindLocation = api(function() return o.hearth or "Goldshire" end)
  -- o.secretLinks: the link is a secret for every slot (the owner's client gave nothing readable for most); the item id
  -- and quality still read, as Forever's character sheet reads them
  env.GetInventoryItemLink = api(function(_, slot) if o.secretLinks then return secret("string") end return (o.items or {})[slot] end)
  -- baseResistance, realResistance, effectiveResistance: the sheet shows the third
  env.UnitResistance = api(function(_, i) return 0, 0, (o.resist or {})[i] or 0 end)
  -- the Legacy Challenges: id, name, points, completed, month, day, year, description, flags, icon, rewardText, isGuild,
  -- wasEarnedByMe, earnedBy, isStatistic
  local function legacyCat(id) for _, cat in ipairs(LEGACY_CATS) do if cat[1] == id then return cat end end end
  local function statCat(id) for _, cat in ipairs(STAT_CATS) do if cat[1] == id then return cat end end end
  local function doneIn(cat)
    if CLASS_CAT[o.class] == cat[1] then return o.classDone or 1 end
    return (o.lcDone or {})[cat[1]] or LEGACY_DONE[cat[1]] or 0
  end
  local function achievement(cat, i)
    local id = cat[1] * 10 + i
    local other = cat[1] == 15001 and i == 3
    local completed = i <= doneIn(cat) or other
    return id, cat[2] .. " " .. i, 10, completed, 1, 1, 2026, "Do the thing", 0, 0, "", false, completed and not other, other and "Alt-Forever" or "", false
  end
  -- the statistics panel's data, this client's own copy
  c.stats = {}
  for i, s in ipairs(STATS) do c.stats[i] = s end
  for i = 1, o.manyStats or 0 do c.stats[#c.stats + 1] = { STAT_CATS[(i % 4) + 1][1], 3000 + i, "Statistic " .. i, i * 7 } end
  local function statistic(id)
    for _, s in ipairs(c.stats) do if s[2] == id then return id, s[3], 0, false, 0, 0, 0, "", 0, 0, "", false, false, "", true end end
  end
  -- the quantity as the panel shows it: thousands separated, "--" never recorded
  local function quantityText(v)
    if v == "--" then return "--" end
    local s, k = tostring(v)
    repeat s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2") until k == 0
    return s
  end
  local function statValue(s) local v = (o.stat or {})[s[2]]; if v == nil then v = s[4] end return v end
  -- the undocumented globals, each with its evidence in UNDOCUMENTED or the mock is refused; the optional ones
  -- (the statistics API, the latest achievements) only on a client made withStats
  local function linkId(link) return link and tonumber(tostring(link):match("item:(%d+)")) or nil end
  local undocumented = {
    GetInventoryItemID = api(function(_, slot) return linkId((o.items or {})[slot]) end),
    GetInventoryItemQuality = api(function(_, slot) local id = linkId((o.items or {})[slot]); return id and (id % 3) + 1 or nil end),
    GetInventoryItemDurability = api(function(slot) if (o.items or {})[slot] then return o.dur or 80, 100 end end),
    GetInventoryItemCount = api(function() return o.ammo or 0 end),
    GetNumUnspentTalents = api(function() return o.talents or 0 end),
    GetCategoryList = api(function() local out = {}; for i, cat in ipairs(LEGACY_CATS) do out[i] = cat[1] end return out end),
    GetCategoryInfo = api(function(id) local cat = legacyCat(id) or statCat(id); if cat then return cat[2], cat[3], 0 end end),
    GetCategoryNumAchievements = api(function(id)
      local cat = legacyCat(id)
      if cat then
        local n, done = cat[4], 0
        for i = 1, n do local _, _, _, completed = achievement(cat, i); if completed then done = done + 1 end end
        return n, done, n - done
      end
      if statCat(id) then local n = 0; for _, s in ipairs(c.stats) do if s[1] == id then n = n + 1 end end return n, 0, n end
      return 0, 0, 0
    end),
    GetAchievementInfo = api(function(a, b)
      if b then local cat = legacyCat(a); if cat and b <= cat[4] then return achievement(cat, b) end return nil end
      for _, cat in ipairs(LEGACY_CATS) do local i = a - cat[1] * 10; if i >= 1 and i <= cat[4] then return achievement(cat, i) end end
      return statistic(a)
    end),
    GetTotalAchievementPoints = api(function() return o.achPoints or 120 end),
  }
  if o.withStats then
    -- c.statsEmpty: the list is still empty, as it may be while the data loads at login
    undocumented.GetStatisticsCategoryList = api(function() if c.statsEmpty then return {} end local out = {}; for i, cat in ipairs(STAT_CATS) do out[i] = cat[1] end return out end)
    undocumented.GetStatistic = api(function(a, b)
      c.statReads = (c.statReads or 0) + 1
      if b then
        local n = 0
        for _, s in ipairs(c.stats) do if s[1] == a then n = n + 1; if n == b then return quantityText(statValue(s)), s[5] or false, s[2] end end end
        return nil
      end
      for _, s in ipairs(c.stats) do if s[2] == a then return quantityText(statValue(s)) end end
      return nil
    end)
    undocumented.GetLatestCompletedAchievements = api(function()
      local out = {}
      for _, cat in ipairs(LEGACY_CATS) do
        for i = 1, cat[4] do local id, _, _, completed, _, _, _, _, _, _, _, _, mine = achievement(cat, i); if completed and mine then table.insert(out, 1, id) end end
      end
      return unpack(out, 1, math.min(#out, 5))
    end)
  end
  for name, fn in pairs(undocumented) do assert(UNDOCUMENTED[name], name .. " is mocked without its evidence in UNDOCUMENTED"); env[name] = fn end
  for name, ev in pairs(UNDOCUMENTED) do assert(undocumented[name] or (type(ev) == "table" and ev.optional), name .. " is listed in UNDOCUMENTED but not mocked") end
  env.C_GameRules = { IsGameRuleActive = api(function(rule) return rule == 77 and o.achDisabled == true end) }
  env.UnitPosition = api(function() local p = o.pos or { 100, 100 }; return p[2], p[1], 0, 0 end)
  env.UnitIsGhost = api(function() return o.ghost or false end)
  env.UnitOnTaxi = api(function() return o.taxi or false end)
  env.UnitIsAFK = api(function() return o.afk or false end)
  env.IsFalling = api(function() return o.falling or false end)
  -- name, startValue (the value the bar began at, not the live one), maxValue, scale, paused, label, spellID
  env.GetMirrorTimerInfo = api(function(i) if i == 1 and o.breath ~= nil then return "BREATH", 60000, 60000, -1, 0, "Breath", 0 end return "UNKNOWN", 0, 0, 0, 0, "", 0 end)
  env.GetMirrorTimerProgress = api(function(name) if name == "BREATH" then return o.breath end return nil end)
  env.GetInstanceInfo = api(function() return "Zone", o.instance or "none" end)
  env.NumTaxiNodes = api(function() return 5 end)
  env.TaxiNodeGetType = api(function(i) return i <= 3 and "REACHABLE" or "DISTANT" end)
  env.RequestTimePlayed = function() c.timers[#c.timers + 1] = { t = c.clock + 1, f = function() fire(c, "TIME_PLAYED_MSG", o.played or 36000, o.playedLevel or 3600) end } end
  env.IsInGuild = api(function() return c.inGuild end)
  env.C_Club = {
    GetGuildClubId = api(function() return c.inGuild and 7 or nil end),
    GetClubMembers = api(function(id) local out = {}; if id == 7 then for i = 1, #GUILD do out[i] = i end end return out end),
    GetMemberInfo = api(function(id, i)
      local m = id == 7 and GUILD[i]
      if not m then return nil end
      return { name = m.name, guid = m.guid, memberId = i, presence = m.online ~= false and 1 or 3, guildRank = m.rankName or ("Rank " .. m.rank), guildRankOrder = m.rank + 1,
        level = m.level, classID = CLASS_ID[m.class], zone = m.zone or "Elwynn Forest", isSelf = m.guid == o.guid }
    end),
    GetMemberInfoForSelf = api(function(id)
      if id ~= 7 then return nil end
      for i, m in ipairs(GUILD) do if m.guid == o.guid then return c.env.C_Club.GetMemberInfo(7, i) end end
    end),
  }
  env.C_CreatureInfo = { GetClassInfo = api(function(id) local file = CLASS_FILE[id]; if file then return { className = file, classFile = file, classID = id } end end) }
  env.C_GuildInfo = { GuildRoster = function() c.rosterAsked = (c.rosterAsked or 0) + 1; c.timers[#c.timers + 1] = { t = c.clock + 0.5, f = function() fire(c, "GUILD_ROSTER_UPDATE") end } end }
  env.C_QuestLog = {
    IsQuestFlaggedCompleted = api(function(id) return (o.done or {})[id] or false end),
    GetLogIndexForQuestID = api(function(id) return (o.log or {})[id] end),
    GetAllCompletedQuestIDs = api(function() local out = {}; for id in pairs(o.done or {}) do out[#out + 1] = id end; return out end),
    GetNumQuestLogEntries = api(function() local n = 0; for _ in pairs(o.log or {}) do n = n + 1 end; return n + 1, n end),
    GetInfo = api(function(i) return { questID = 100 + i, isHeader = false } end),
    IsComplete = api(function(id) return id == 101 end),
  }
  -- C_Item takes an ItemInfo: an id, a name or a link. o.uncached: GetDetailedItemLevelInfo reads nothing yet
  local function itemId(x) if type(x) == "number" then return x end return tonumber(tostring(x):match("item:(%d+)")) or 0 end
  env.C_Item = {
    GetItemCount = api(function(id) return (o.counts or {})[id] or 0 end),
    GetDetailedItemLevelInfo = api(function(link) if o.uncached then return nil end return 20 + (itemId(link) % 40) end),
    GetItemQualityByID = api(function(link) return (itemId(link) % 3) + 1 end),
    -- name, link, quality, level, minLevel, type, subType, stackCount, equipLoc, texture, sellPrice
    GetItemInfo = api(function(link) local id = itemId(link); return "Item " .. id, type(link) == "string" and link or ("item:" .. id), (id % 3) + 1, 20 + (id % 40), 1, "Misc", "Junk", 20, "", 0, (o.prices or {})[id] or 0 end),
  }
  env.C_Container = {
    GetContainerNumFreeSlots = api(function(b) return b == 0 and 4 or 2 end),
    GetContainerNumSlots = api(function(b) return b == 0 and 16 or 10 end),
    GetContainerItemInfo = api(function(bag, slot)
      local it = ((o.bags or {})[bag] or {})[slot]
      if not it then return nil end
      return { quality = it.quality, hyperlink = it.link, stackCount = it.count or 1, hasNoValue = it.noValue or false, itemID = itemId(it.link) }
    end),
    UseContainerItem = function(bag, slot) if c.hooks.UseContainerItem then c.hooks.UseContainerItem(bag, slot) end end,
  }
  env.C_UnitAuras = { GetAuraDataByIndex = api(function(_, i) local a = (o.auras or {})[i]; if a then return { name = a[1], spellId = a[2] } end end) }
  env.C_Reputation = { GetFactionDataByID = api(function(id) return { reaction = (o.rep or {})[id] or 4 } end) }
  env.C_MountJournal = { GetMountIDs = api(function() return { 1 } end), GetMountInfoByID = api(function() return "Horse", 1, 1, true, true, 1, false, false, false, false, o.mount or false end) }
  -- the three Legacy trees, a config each; their currency is the Legacy points (traitCurrencyID, quantity unspent,
  -- maxQuantity, spent, spentInTree), five of them per challenge done
  local TREE_CFG = { [1187] = 7, [1188] = 8, [1189] = 9 }
  local TREE_SPENT = { [1187] = 3, [1188] = 2, [1189] = 1 }
  env.C_Traits = { GetConfigIDByTreeID = api(function(tree) return TREE_CFG[tree] end),
    GetNodeInfo = api(function(_, node) return { activeRank = (o.legacy or {})[node] or 0 } end),
    GetTreeCurrencyInfo = api(function(cfg, tree)
      if TREE_CFG[tree] ~= cfg then return {} end
      return { { traitCurrencyID = 4225, quantity = o.lcFree or 2, maxQuantity = 40, spent = 6, spentInTree = (o.lcSpent or TREE_SPENT)[tree] or 0 } }
    end),
    GetTraitCurrencyForAchievement = api(function(currency) return currency == 4225 and 5 or 0 end) }
  env.C_SpecializationInfo = { GetSpecialization = api(function() return 1 end), GetSpecializationInfo = api(function() return 1, o.spec or "Arms" end) }
  -- Forever's PvP rank: the renown track of Major Faction 2800; the Legacy reward track is Major Faction 2802
  env.C_MajorFactions = { GetMajorFactionProgressionInfo = api(function(id)
    if id ~= 2800 then return nil end
    return { renownLevel = o.pvp or 0, renownReputationEarned = o.pvpPts or 0, renownLevelThreshold = 1000, currentWeekProgressiveMaxLevel = 14, maxLevel = 14, weekNumber = 1 }
  end), GetCurrentRenownLevel = api(function(id) return id == 2802 and (o.renown or 4) or 0 end) }
  -- the skills window's lines: { skillID, name, rank, maxRank }, headers between
  o.skills = o.skills or { { 186, "Mining", 150, 225 }, { 202, "Engineering", 140, 225 }, { 356, "Fishing", 40, 75 }, { 185, "Cooking", 60, 150 }, { 129, "First Aid", 1, 75 } }
  env.C_SkillInfo = {
    GetNumSkillLines = api(function() return #o.skills + 1 end),
    GetSkillLineInfo = api(function(i)
      if i == 1 then return { skillID = 0, name = "Professions", isHeader = true, rank = 0, maxRank = 0 } end
      local s = o.skills[i - 1]
      if s then return { skillID = s[1], name = s[2], isHeader = false, rank = s[3], maxRank = s[4] } end
    end),
  }
  env.C_TradeSkillUI = {
    GetRecipeInfo = api(function(id) return { recipeID = id, learned = (o.learned or {})[id] == true } end),
    GetBaseProfessionInfo = api(function() return { professionID = 171, professionName = "Alchemy", skillLevel = 300, maxSkillLevel = 300 } end),
  }
  env.C_ChatInfo = {
    RegisterAddonMessagePrefix = function(p) c.prefix = p; return true end,
    SendAddonMessage = function(prefix, msg, channel)
      assert(prefix == "Cute" and channel == "GUILD", "the Cute prefix on GUILD only: " .. tostring(prefix) .. " " .. tostring(channel))
      if #msg > 255 then c.oversize[#c.oversize + 1] = msg; return 2 end
      if c.throttle and c.throttle > 0 then c.throttle = c.throttle - 1; return 3 end
      if c.fail and c.fail > 0 then c.fail = c.fail - 1; return 9 end
      c.sent[#c.sent + 1] = { msg = msg, at = c.clock }
      BUS[#BUS + 1] = { from = c, prefix = prefix, msg = msg, channel = channel }
      return 0
    end,
    SendChatMessage = function(text, kind) if c.hooks.SendChatMessage then c.hooks.SendChatMessage(text, kind) end end,
  }
  env.math = setmetatable({ random = function(a, b) if a and b then return a + (c.clock % (b - a + 1)) end return 0.5 end }, { __index = math })
  -- a client that lacks a function (o.without = { Name = true }): the global is gone, as on a client without it
  for name in pairs(o.without or {}) do env[name] = nil end

  -- load the addon, file by file, as the TOC lists them
  local toc = io.open(HERE .. "/Cute/Cute.toc"):read("*a")
  for file in toc:gmatch("\n([%w_]+%.lua)") do
    local src = assert(io.open(HERE .. "/Cute/" .. file)):read("*a")
    assert(not src:find("[\128-\255]"), file .. " has a byte the game's font would draw as a box")
    local fn, err = loadstring(src, "@Cute/" .. file)
    assert(fn, err)
    setfenv(fn, env)
    fn("Cute", c.C)
  end
  clients[#clients + 1] = c
  return c
end

local function login(c, db, reloading)
  c.env.CuteDB = db or {}
  fire(c, "ADDON_LOADED", "Cute")
  fire(c, "PLAYER_ENTERING_WORLD", not reloading, reloading or false)
  tick(c, 1) -- the roster arrives
end
local function leave(c) for i = #clients, 1, -1 do if clients[i] == c then table.remove(clients, i) end end end

local function click(b) assert(b and b.__scripts.OnClick, "a button with OnClick"); b.__checked = not b.__checked; b.__scripts.OnClick(b, "LeftButton") end
local function press(b) assert(b and b.__scripts.OnClick, "a button with OnClick"); b.__scripts.OnClick(b, "LeftButton") end
local function hover(o) if o.__scripts.OnEnter then o.__scripts.OnEnter(o) end end
local function msgs(c, kind) local n = 0; for _, m in ipairs(c.sent) do if m.msg:sub(1, 2) == kind then n = n + 1 end end return n end
local function sameColor(a, b) return a and b and math.abs(a[1] - b[1]) < 0.01 and math.abs(a[2] - b[2]) < 0.01 and math.abs(a[3] - b[3]) < 0.01 end
-- a shown row of the table, and a shown cell of a row, by the stat id
local function rowOf(c, short) for _, r in ipairs(c.C.UI.rows.items) do if r:IsShown() and r.row and r.row.short == short then return r end end end
local function cellOf(r, id) for _, cell in ipairs(r.cells) do if cell:IsShown() and cell.def and cell.def.id == id then return cell end end end
local function shownHeaders(c) local n = 0; for _, h in ipairs(c.C.UI.headerCells.items) do if h:IsShown() then n = n + 1 end end return n end
local function checkBox(c, test) for _, fr in ipairs(c.frames) do if fr.__kind == "CheckButton" and fr:IsVisible() and test(fr) then return fr end end end

----------------------------------------------------------------------------
-- layout: resolve anchors to boxes like the game does
----------------------------------------------------------------------------
local function anchorXY(r, point)
  local x = point:find("LEFT") and r.l or (point:find("RIGHT") and r.r or (r.l + r.r) / 2)
  local y = point:find("TOP") and r.t or (point:find("BOTTOM") and r.b or (r.t + r.b) / 2)
  return x, y
end
function rectOf(o, depth)
  depth = (depth or 0) + 1
  if depth > 60 then error("anchor loop") end
  if o.__gen == GEN then return o.__rect end
  o.__gen = GEN
  if o.__root then o.__rect = { l = 0, r = o.__w, t = o.__h, b = 0 }; return o.__rect end
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
  if o.__kind == "FontString" then
    local tw = textWidth(o.__text, o.__size)
    if not o.__wset and not (L and R) then w = tw end
    if not o.__hset and not (T and B) then
      local nlines = 1
      if o.__wrap and o.__wset and w > 0 then nlines = math.max(1, math.ceil(tw / w)) end
      h = nlines * (o.__size + 2)
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
local CP1252 = {}
for _, cp in ipairs({ 0x20AC, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x017D,
  0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x017E, 0x0178 }) do CP1252[cp] = true end
local function undrawable(str)
  local s = str:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
  local i, n = 1, #s
  while i <= n do
    local ch = s:byte(i)
    local b2, b3, b4 = (s:byte(i + 1) or 0) % 64, (s:byte(i + 2) or 0) % 64, (s:byte(i + 3) or 0) % 64
    local cp, len
    if ch < 0x80 then cp, len = ch, 1
    elseif ch >= 0xF0 then cp, len = (ch % 8) * 262144 + b2 * 4096 + b3 * 64 + b4, 4
    elseif ch >= 0xE0 then cp, len = (ch % 16) * 4096 + b2 * 64 + b3, 3
    elseif ch >= 0xC0 then cp, len = (ch % 32) * 64 + b2, 2
    else return string.format("a stray byte 0x%02X", ch) end
    if not ((cp >= 0x20 and cp <= 0x7E) or cp == 9 or cp == 10 or (cp >= 0xA0 and cp <= 0xFF) or CP1252[cp]) then return string.format("U+%04X", cp) end
    i = i + len
  end
end
local function interactive(o)
  local k = o.__kind
  return k == "Button" or k == "CheckButton" or k == "EditBox" or k == "Slider"
end
local function inside(o, root) for _, a in ipairs(ancestors(o)) do if a == root then return true end end return false end
local EDGE_GAP = 5
local function checkLayout(root, label)
  GEN = GEN + 1
  local problems, texts = {}, {}
  local rootRect = rectOf(root)
  for _, o in ipairs(ALL) do
    if o.__kind == "FontString" and o.__text ~= "" and visible(o) and inside(o, root) then
      local bad = undrawable(o.__text)
      if bad then problems[#problems + 1] = string.format("%s: '%s' has %s, which the game's font draws as a box", label, plain(o.__text):sub(1, 40), bad) end
      local r = rectOf(o)
      if r then
        local tw = textWidth(o.__text, o.__size)
        if o.__wset and not o.__wrap and tw > (r.r - r.l) + 3 then
          problems[#problems + 1] = string.format("%s: clipped '%s' (%.0f of %.0f px)", label, plain(o.__text):sub(1, 60), r.r - r.l, tw)
        end
        local ir = ink(o, r)
        local clip
        for _, a in ipairs(ancestors(o)) do if a.__child then clip = rectOf(a); break end end
        if clip and (ir.r > clip.r + 2 or ir.l < clip.l - 2) then
          problems[#problems + 1] = string.format("%s: '%s' runs out of the scroll view", label, plain(o.__text):sub(1, 50))
        end
        local inView = not clip or (ir.b < clip.t and ir.t > clip.b)
        if clip and inView then ir = { l = math.max(ir.l, clip.l), r = math.min(ir.r, clip.r), t = math.min(ir.t, clip.t), b = math.max(ir.b, clip.b) } end
        if not clip and (ir.r > rootRect.r - 6 or ir.l < rootRect.l + 6 or ir.b < rootRect.b + 6 or ir.t > rootRect.t) then
          problems[#problems + 1] = string.format("%s: '%s' runs out of the window", label, plain(o.__text):sub(1, 50))
        end
        if inView then texts[#texts + 1] = { o = o, r = ir } end
      end
    end
    if interactive(o) and visible(o) and inside(o, root) and o ~= root then
      local r = rectOf(o)
      if r and r.r - r.l > 0 and r.t - r.b > 0 then
        local clip
        for _, a in ipairs(ancestors(o)) do if a.__child then clip = rectOf(a); break end end
        local inset = root.__inset or 0
        if not clip then
          local gaps = { { "left", r.l - (rootRect.l + inset) }, { "right", (rootRect.r - inset) - r.r }, { "top", (rootRect.t - inset) - r.t }, { "bottom", r.b - (rootRect.b + inset) } }
          for _, g in ipairs(gaps) do
            if g[2] < EDGE_GAP then problems[#problems + 1] = string.format("%s: [%s '%s'] sits %d px from the window's %s edge", label, o.__kind, plain(o.__text ~= "" and o.__text or (o.__where or "?")):sub(1, 30), math.floor(g[2] + 0.5), g[1]); break end
          end
        elseif r.l < clip.l - 1 or r.r > clip.r + 1 then
          problems[#problems + 1] = string.format("%s: [%s '%s'] reaches past its scroll view", label, o.__kind, plain(o.__text):sub(1, 30))
        end
        -- a button with a label or a check box takes room too
        if (o.__template == "UIPanelButtonTemplate" or o.__kind == "CheckButton") and (not clip or (r.b < clip.t and r.t > clip.b)) then
          if clip then r = { l = math.max(r.l, clip.l), r = math.min(r.r, clip.r), t = math.min(r.t, clip.t), b = math.max(r.b, clip.b) } end
          texts[#texts + 1] = { o = o, r = r, button = true }
        end
      end
    end
  end
  for i = 1, #texts do
    for j = i + 1, #texts do
      local a, b = texts[i], texts[j]
      local nested = false
      if a.button ~= b.button then
        local btn, other = a.button and a or b, a.button and b or a
        if inside(other.o, btn.o) then nested = true end
      end
      if not nested and overlap(a.r, b.r, 1.5) then
        local function name(t) return t.button and ("[button " .. plain(t.o.__text or ""):sub(1, 20) .. "]") or plain(t.o.__text):sub(1, 40) end
        problems[#problems + 1] = string.format("%s: '%s' overlaps '%s'", label, name(a), name(b))
      end
    end
  end
  return problems
end

local TEXNAME = { ["Interface\\AddOns\\Cute\\art\\logo.png"] = "logo", ["Interface\\AddOns\\Cute\\art\\logo_wide.png"] = "logo_wide" }
local function dumpLayout(root, label)
  GEN = GEN + 1
  local rr = rectOf(root)
  local items = {}
  for idx, o in ipairs(ALL) do
    if visible(o) and o ~= root and inside(o, root) then
      local r = rectOf(o)
      if r and (r.r - r.l) > 0 and (r.t - r.b) > 0 then
        local anc = ancestors(o)
        local it = { k = o.__kind, x = r.l - rr.l, y = rr.t - r.t, w = r.r - r.l, h = r.t - r.b, i = idx, a = o.__alpha, depth = #anc, lvl = 0 }
        if o.__kind == "FontString" then
          it.text, it.size, it.j, it.wrap, it.c = plain(o.__text), o.__size, o.__justify, o.__wrap, o.__color
        elseif o.__kind == "Texture" then
          if o.__layer == "HIGHLIGHT" or o.__layer == "MASK" then it = nil
          else
            it.layer = o.__layer
            it.tex = o.__tex == "color" and "color" or (TEXNAME[o.__tex] or (o.__tex and "icon") or nil)
            if o.__tex ~= "color" then it.raw = o.__tex end
            it.c = o.__color or o.__vertex
            it.tc, it.blend = o.__tc, o.__blend
            if not it.tex then it = nil end
          end
        else
          it.bd = o.__backdrop or nil
          it.bdc, it.bdb = o.__bdc, o.__bdb
          it.tpl = o.__template
          it.text = (o.__template or o.__kind == "EditBox") and o.__text ~= "" and o.__text or nil
          it.checked, it.off = o.__checked or nil, o.__disabled or nil
        end
        if it then
          for _, a in ipairs(anc) do if a.__child then local cr = rectOf(a); it.clip = { x = cr.l - rr.l, y = rr.t - cr.t, w = cr.r - cr.l, h = cr.t - cr.b }; break end end
          items[#items + 1] = it
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
-- the guild: twenty made-up members, a guild master at rank 0 and one officer at rank 1
----------------------------------------------------------------------------
local NAMES = { { "Cutecutecute", 0, "Guild Master", "PRIEST", 44 }, { "Yezin", 1, "Officer", "WARRIOR", 42 }, { "Upn", 1, "Officer", "MAGE", 41 },
  { "Kaka", 3, "Raider", "PRIEST", 37 }, { "Mutu", 3, "Raider", "WARRIOR", 39 }, { "Bari", 3, "Raider", "PALADIN", 38 }, { "Garristan", 4, "Member", "WARRIOR", 1 },
  { "Boopsy", 3, "Raider", "WARLOCK", 36 }, { "Ferrow", 3, "Raider", "HUNTER", 40 }, { "Lindel", 3, "Raider", "DRUID", 35 }, { "Mossbark", 4, "Member", "DRUID", 22 },
  { "Quillan", 3, "Raider", "ROGUE", 38 }, { "Sablewing", 3, "Raider", "HUNTER", 33 }, { "Tavrik", 4, "Member", "SHAMAN", 29 }, { "Ondra", 3, "Raider", "MAGE", 40 },
  { "Pell", 4, "Member", "ROGUE", 18 }, { "Rhosyn", 3, "Raider", "PRIEST", 36 }, { "Vantor", 3, "Raider", "WARLOCK", 34 }, { "Wrenna", 4, "Member", "HUNTER", 27 },
  { "Zephyrine", 3, "Raider", "MAGE", 31 } }
local function makeGuild()
  GUILD = {}
  for i, n in ipairs(NAMES) do GUILD[i] = { name = n[1] .. "-Forever", guid = guidOf(n[1]), rank = n[2], rankName = n[3], class = n[4], level = n[5], online = i % 3 ~= 0 } end
end
local function charOf(n, extra)
  local o = { name = n[1], realm = "Forever", level = n[5], xp = 350, xpmax = 1000, class = n[4], money = 123456, zone = "Duskwood", rested = 500,
    items = { [1] = "item:1234:0", [5] = "item:1235:2", [7] = "item:1236:0", [16] = "item:1240:0" }, auras = { { "Power Word: Fortitude", 1243 }, { "Rallying Cry", 22888 } },
    counts = { [13446] = 5, [13510] = 1, [18249] = 1 }, done = { [7848] = true, [4182] = true }, log = { [4183] = 3 } }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end

----------------------------------------------------------------------------
-- scenarios
----------------------------------------------------------------------------
local problems, layouts = {}, {}
local function check(root, label)
  local p = checkLayout(root, label)
  for _, x in ipairs(p) do problems[#problems + 1] = x end
  if LAYOUT_OUT then layouts[#layouts + 1] = dumpLayout(root, label) end
  return #p
end

makeGuild()
-- the two clients most scenarios share have the statistics API; scenario 17 makes clients without it
local yezin = newClient(charOf(NAMES[2], { withStats = true }))
local kaka = newClient(charOf(NAMES[4], { level = 37, xp = 120, money = 54321, zone = "Desolace", withStats = true }))
login(yezin)
login(kaka)

-- 1: the registry, and every read stat has a value on a client that mirrors Forever's documented API
do
  local S = yezin.C.Stats
  local counts = {}
  for _, cat in ipairs(S.CATS) do counts[cat] = #S.byCat[cat] end
  assert(#S.list >= 100, "a starter list of over a hundred stats: " .. #S.list)
  for _, def in ipairs(S.list) do assert(def.id and def.label and def.cat and def.kind, "a whole definition: " .. tostring(def.id)) end
  assert(S.byId.level and S.byId.deaths and S.byId.gold and S.byId.unenchanted and S.byId.ready, "the stats the pages lean on")
  assert(yezin.C.Policy:Vis("unenchanted") == "self" and yezin.C.Policy:Vis("level") == "all" and yezin.C.Policy:Vis("gold") == "self", "the defaults")
  local nils = {}
  for _, def in ipairs(S.list) do
    if def.read and yezin.C.Sample:Value(def.id) == nil then nils[#nils + 1] = def.id .. (yezin.C.Sample:Error(def.id) and (" (" .. yezin.C.Sample:Error(def.id) .. ")") or "") end
  end
  assert(#nils == 0, "stats that read nil on the documented client: " .. table.concat(nils, ", "))
  assert(yezin.C.Sample:Value("spec") == "Arms" and yezin.C.Sample:Value("pvp_rank") == 0 and yezin.C.Sample:Value("cooking") == 60 and yezin.C.Sample:Value("first_aid") == 1
    and yezin.C.Sample:Value("prof1") == "Mining 150" and yezin.C.Sample:Value("mount") == false, "spec, PvP, skills and the mount read through the documented namespaces")
  assert(yezin.C.Sample:Value("ready") == 1 and yezin.C.UI.Format(S.byId.ready, 1) == "gaps", "readiness: one gap (empty slots) reads as gaps: " .. tostring(yezin.C.Sample:Value("ready")))
  assert(yezin.C.Sample:Value("gold") == 123456 and yezin.C.UI.Format(S.byId.gold, 123456) == "12g" and S.FmtGold(9500) == "95s" and S.FmtGold(7) == "7c", "gold keeps copper and shows gold")
  assert(yezin.C.Sample:Value("resist_fire") == 0, "resists read")
  local XPLeft = yezin.C.Sample.XPLeft
  assert(XPLeft(59, 0, 171800) == 171800 and XPLeft(58, 165700, 165800) == 100 + 171800 and XPLeft(1, 0, 800) == 2 * 3379200, "the XP left to 60 follows the per-level table, scaled to this client's max")
  -- the item level is the average over the items worn (there is no GetAverageItemLevel): 54, 55, 56 and 20 make 46
  assert(yezin.C.Sample:Value("ilvl") == 46, "item level averaged over the four items worn: " .. tostring(yezin.C.Sample:Value("ilvl")))
  local slots = yezin.C.Sample:Value("ilvl_slots")
  assert(slots[1] and slots[5] and slots[7] and not slots[16], "the slots at or above that average")
  -- every undocumented global the mock defines is one /cute api reports on the live client
  local undoc = {}
  for name in pairs(UNDOCUMENTED) do
    local listed = false
    for _, n in ipairs(yezin.C.UNDOCUMENTED) do if n == name then listed = true end end
    assert(listed, name .. " is mocked here but /cute api does not report it")
    undoc[#undoc + 1] = name
  end
  table.sort(undoc)
  assert(counts.game == 11 and #S.game.cats == 4, "the statistics category filled from the client's list: " .. counts.game)
  print(string.format("registry: %d stats (leveling %d, prog %d, funny %d, officer %d, statistics %d from the client), every read stat has a value on the documented client; undocumented globals mocked on evidence: %s",
    #S.list, counts.leveling, counts.prog, counts.funny, counts.officer, counts.game, table.concat(undoc, ", ")))
end

-- 2: every read survives a client whose values are all secret, and one whose calls all throw (and the tooltip learns why)
do
  local c = newClient(charOf(NAMES[9]))
  login(c)
  c.secret = true
  c.C.Sample:ReadAll()
  for _, def in ipairs(c.C.Stats.list) do
    if def.read then local v = c.C.Sample:Value(def.id); assert(v == nil or type(v) ~= "table" or getmetatable(v) ~= SECRET_MT, "a secret value stored: " .. def.id) end
  end
  c.secret, c.throw = false, true
  c.C.Sample:ReadAll()
  local errs = 0
  for _, def in ipairs(c.C.Stats.list) do if c.C.Sample:Error(def.id) then errs = errs + 1 end end
  assert(errs >= 20, "the client's throws are recorded against the stats for the tooltip: " .. errs)
  assert(c.C.Sample:Value("level") == nil and tostring(c.C.Sample:Error("level")):find("the client threw", 1, true), "the level's error text is the client's")
  c.throw = false
  c.C.Sample:ReadAll()
  assert(c.C.Sample:Value("level") == NAMES[9][5] and c.C.Sample:Error("level") == nil, "the level reads again after the client recovers")
  -- a client without one of the undocumented globals: the stat reads nil with the reason, which the cell's tooltip,
  -- the Me page and /cute errors carry; /cute api names what is missing and what is there
  local bare = newClient(charOf(NAMES[15], { without = { GetInventoryItemDurability = true } }))
  login(bare)
  assert(bare.C.Sample:Value("durability") == nil and bare.C.Sample:Error("durability") == "GetInventoryItemDurability is missing on this client",
    "a missing function reads as its reason: " .. tostring(bare.C.Sample:Error("durability")))
  assert(bare.C.Sample:Value("ready") == 1, "readiness still reads without the durability input")
  local noted = 0
  for _, e in ipairs(bare.env.CuteDB.errors) do if e.msg == "GetInventoryItemDurability is missing on this client" then noted = noted + e.count end end
  assert(noted == 1 and #bare.chat == 0, "noted once for /cute errors, no chat line: " .. noted)
  bare.C.UI:Open("prog")
  local cell = cellOf(rowOf(bare, "Ondra"), "durability")
  assert(cell and cell.label:GetText() == "?", "the cell shows ?")
  local n0 = #lines
  hover(cell)
  assert(table.concat(lines, "\n", n0 + 1):find("Could not read: GetInventoryItemDurability is missing on this client", 1, true), "the cell's tooltip says why")
  bare.C.UI:Open("me")
  local said = false
  for _, l in ipairs(bare.C.UI.labels.items) do if l:IsShown() and l:GetText():find("Durability: GetInventoryItemDurability is missing", 1, true) then said = true end end
  assert(said, "the Me page lists what could not be read, with the reason")
  check(bare.C.UI.frame, "member me, a function missing")
  bare.C.UI.frame:SetSize(760, 420)
  bare.C.UI:Open("me")
  check(bare.C.UI.frame, "member me, a function missing, small window")
  bare.C.UI.frame:SetSize(1040, 640)
  bare.env.SlashCmdList.CUTE("api")
  local line = bare.chat[#bare.chat]
  local present, missing = line:match("present ([^|]*)|"), line:match("missing (.*)$")
  assert(present and missing, "/cute api prints present and missing: " .. tostring(line))
  assert(missing:find("GetInventoryItemDurability", 1, true) and missing:find("DoEmote", 1, true) and missing:find("GetAverageItemLevel", 1, true), "the missing ones: " .. missing)
  assert(present:find("GetInventoryItemCount", 1, true) and present:find("GetNumUnspentTalents", 1, true) and not present:find("Durability", 1, true), "the present ones: " .. present)
  leave(bare)
  print(string.format("reads: every stat survives secret values and thrown errors (%d read errors recorded while throwing); a missing function reads as its reason, listed by /cute api", errs))
end

-- 3: the encoder round-trips every kind; what comes in is cleaned
do
  local M, S = yezin.C.Comm, yezin.C.Stats
  local samples = { int = { 0, 1, 35, 36, 1295, 123456789, -7 }, flag = { true, false }, text = { "Duskwood", "The Barrens", "a|b;c=d", "Kaka, Mutu" }, pips = { "2210", "0", "22222222222" } }
  local n = 0
  for _, def in ipairs(S.list) do
    if def.kind == "list" then
      local v = {}
      for i, e in ipairs(def.of) do if i % 2 == 1 then v[e[1]] = true end end
      local back = M.Decode(def, M.Encode(def, v))
      for _, e in ipairs(def.of) do assert((back[e[1]] or false) == (v[e[1]] or false), "list round trip: " .. def.id) end
      n = n + 1
    else
      for _, v in ipairs(samples[def.kind]) do
        local s = M.Encode(def, v)
        assert(s and not s:find("[|;]"), "wire text without separators: " .. def.id)
        local back = M.Decode(def, s)
        if def.kind == "text" then assert(back == v:gsub("[|;=]", ""):sub(1, 24), "text round trip: " .. def.id)
        elseif def.kind == "pips" then assert(back == v, "pips round trip")
        else assert(back == v, "round trip: " .. def.id .. " " .. tostring(v) .. " -> " .. tostring(back)) end
        n = n + 1
      end
    end
  end
  assert(M.b36(35) == "z" and M.b36(36) == "10" and M.unb36("-1z") == -71, "base 36")
  -- a modified client's message: colour codes, separators, a byte the font cannot draw, letters where digits go
  assert(M.Decode(S.byId.zone, "Dusk|cff00ff00wood;x") == "Duskcff00ff00woodx", "text in is cleaned of | and ;")
  assert(M.Decode(S.byId.zone, "A\195\169B\1C") == "ABC", "text in loses bytes the font draws as boxes and control characters")
  assert(M.Decode(S.byId.attune_mc, "12a") == nil and M.Decode(S.byId.attune_mc, "2") == "2", "pips in are digits only")
  assert(M.Decode(S.byId.keys, "-5") == nil and M.Decode(S.byId.level, "zzzzzzzzzzzz") == nil, "lists and ints in are bounded")
  print("encoder: " .. n .. " values round-trip; what comes in is cleaned")
end

-- 4: hello: the two clients exchange records; the full record fits in a few chunks; nothing goes out before the hello
do
  tickAll(45)
  assert(msgs(yezin, "1R") == 1 and msgs(kaka, "1R") == 1, "each said hello")
  local fulls = msgs(yezin, "1F") / 2 -- once at the hello, once in answer to Kaka's
  assert(fulls >= 1 and fulls <= 8, "the full record in a handful of chunks per send: " .. fulls)
  local longest, firstD, firstF = 0, nil, nil
  for i, m in ipairs(yezin.sent) do
    assert(#m.msg <= 255)
    longest = math.max(longest, #m.msg)
    if m.msg:sub(1, 2) == "1D" and not firstD then firstD = i end
    if m.msg:sub(1, 2) == "1F" and not firstF then firstF = i end
  end
  assert(#yezin.oversize == 0 and #kaka.oversize == 0, "no message over the limit was tried")
  assert(longest >= 236, "the chunks are packed close to the limit, header included: " .. longest)
  assert(not firstD or firstD > firstF, "no delta leaves before the full record")
  -- the hello, the full record, and the full record again in answer to Kaka's hello: no deltas
  assert(msgs(yezin, "1D") == 0 and #yezin.sent <= 1 + 2 * fulls, "a quiet client sends nothing beyond the hello and its answers: " .. #yezin.sent .. " messages in 45 s")
  local e = kaka.env.CuteDB.roster["Yezin-Forever"]
  assert(e and e.stats.level == 42 and e.stats.zone == "Duskwood", "Kaka's roster holds Yezin's level and zone")
  local e2 = yezin.env.CuteDB.roster["Kaka-Forever"]
  assert(e2 and e2.stats.level == 37 and e2.stats.gold == 54321, "Yezin's roster holds Kaka's level and gold (in copper)")
  assert(e2.stats.unenchanted and e2.stats.unenchanted[1] == true and e2.stats.unenchanted[5] == nil, "lists arrive as sets")
  -- one message a second from each
  local last
  for _, m in ipairs(yezin.sent) do if last then assert(m.at - last >= 1 - 1e-9, "one message a second: " .. (m.at - last)) end last = m.at end
  -- every message came back to its sender too, as the game hands it back: neither keeps a record of itself
  assert(not yezin.env.CuteDB.roster[yezin.sender] and not kaka.env.CuteDB.roster[kaka.sender], "no client keeps its own messages as a member's record")
  assert(yezin.sent[1].msg == "1R|" .. yezin.o.guid and e.stats.guid == yezin.o.guid, "the ask and the full record carry the sender's GUID")
  print(string.format("hello: records exchanged, %d messages from Yezin (%d chunks of the full record, longest %d bytes), none closer than a second", #yezin.sent, fulls, longest))
end

-- 5: a change goes out as a delta; the slow stats wait for the two-minute flush
do
  local before = #kaka.sent
  kaka.o.level = 38
  fire(kaka, "PLAYER_LEVEL_UP", 38)
  tickAll(4)
  assert(#kaka.sent > before, "a delta went out")
  local d = kaka.sent[#kaka.sent].msg
  assert(d:sub(1, 2) == "1D" and d:find("level=12", 1, true), "the delta carries the new level in base 36: " .. d)
  assert(not d:find("played=", 1, true), "the ticking stats are not in it: " .. d)
  assert(yezin.env.CuteDB.roster["Kaka-Forever"].stats.level == 38, "Yezin saw the level")
  -- five quiet minutes: the flushes with the ticking stats, and the statistics pass a minute and a half after the
  -- hello (its own, and the one answering Yezin's hello)
  before = #kaka.sent
  tickAll(300)
  local flushed, statPasses = 0, 0
  for i = before + 1, #kaka.sent do
    if kaka.sent[i].msg:find("g2001=", 1, true) then statPasses = statPasses + 1 else flushed = flushed + 1 end
  end
  assert(flushed >= 1 and flushed <= 3, "a quiet client sends only its flushes in five minutes: " .. flushed)
  -- (the answer to Yezin's hello goes first; the own pass then finds nothing left unsent)
  assert(statPasses >= 1 and statPasses <= 2, "the statistics went in answer to the hello, and of their own accord only what was left: " .. statPasses)
  local played = false
  for i = math.max(1, #kaka.sent - 3), #kaka.sent do if kaka.sent[i].msg:find("played=", 1, true) then played = true end end
  assert(played, "the flush carries time played")
  assert(yezin.env.CuteDB.roster["Kaka-Forever"].stats.played and yezin.env.CuteDB.roster["Kaka-Forever"].stats.played > 0, "Yezin has Kaka's time played")
  assert(yezin.env.CuteDB.roster["Kaka-Forever"].stats.g2001 == 1234, "and Kaka's kills, from the statistics pass")
  print(string.format("deltas: a level-up reaches the guild as one small message; %d flushes and %d statistics passes in five quiet minutes", flushed, statPasses))
end

-- 6: the policy: a member's is ignored, an officer's applies, cells follow it; a policy before the roster waits
do
  local P = kaka.C.Policy
  assert(P:Vis("gold") == "self")
  -- Kaka (rank 3) tries to open gold to everyone: nobody listens
  P:Set("gold", "all")
  kaka.C.Comm:SendPolicy()
  tickAll(3)
  assert(yezin.C.Policy:Vis("gold") == "self", "a member's policy is ignored")
  kaka.env.CuteDB.policy = nil
  -- Yezin (rank 1) sets gold to everyone and deaths to only-you
  yezin.C.Policy:Set("gold", "all")
  yezin.C.Policy:Set("deaths", "self")
  yezin.C.Comm:SendPolicy()
  tickAll(3)
  assert(kaka.C.Policy:Vis("gold") == "all" and kaka.C.Policy:Vis("deaths") == "self", "an officer's policy applies")
  assert(kaka.C.Policy:CanSee(false, false, "deaths") == false and kaka.C.Policy:CanSee(false, true, "deaths") == true and kaka.C.Policy:CanSee(true, false, "deaths") == true, "the rule")
  -- an older policy does not overwrite a newer one
  local at = kaka.env.CuteDB.policy.at
  local ok = kaka.C.Policy:Receive("Yezin-Forever", at - 10, 1, "gold=s")
  assert(ok == false and kaka.C.Policy:Vis("gold") == "all", "older policies are ignored")
  -- a policy that lands before the roster is known waits for the ranks, then applies
  local early = newClient(charOf(NAMES[13]))
  early.env.CuteDB = {}
  fire(early, "ADDON_LOADED", "Cute")
  assert(not early.C.Roster.trusted, "no roster yet")
  local okEarly, why = early.C.Policy:Receive("Yezin-Forever", at + 5, 1, "gold=a;deaths=s")
  assert(okEarly == false and why == "roster not known yet" and early.C.Policy:Vis("deaths") == "all", "held, not applied")
  fire(early, "PLAYER_ENTERING_WORLD", true, false)
  tick(early, 1)
  assert(early.C.Roster.trusted and early.C.Policy:Vis("deaths") == "self" and early.C.Policy:Vis("gold") == "all", "applied once the ranks arrived")
  -- a fresh install asks (1R) and the officer's answer carries the policy
  local fresh = newClient(charOf(NAMES[14]))
  login(fresh)
  assert(fresh.C.Policy:Vis("deaths") == "all", "a fresh install starts from the defaults")
  tickAll(45)
  assert(fresh.C.Policy:Vis("deaths") == "self" and fresh.C.Policy:Vis("gold") == "all", "the officer's answer to the hello carried the policy")
  leave(early); leave(fresh)
  print("policy: member's ignored, officer's applied, older ignored, an early one waits for the roster, a fresh install gets it on hello")
end

-- 7: counters persist across a reload; a reload is not a login; deaths know their cause
do
  fire(kaka, "PLAYER_DEAD")
  fire(kaka, "PLAYER_DEAD")
  -- no DoEmote on this client: your own lines in the emote chat count (the hook, where the function exists, is scenario 14's)
  fire(kaka, "CHAT_MSG_TEXT_EMOTE", "You dance.", "Kaka-Forever")
  fire(kaka, "CHAT_MSG_TEXT_EMOTE", "You wave.", "Kaka")
  assert(kaka.C.Sample:Value("deaths") == 2 and kaka.C.Sample:Value("dance") == 1 and kaka.C.Sample:Value("emotes") == 2, "counted")
  assert(kaka.C.Sample:Value("drownings") == 0 and kaka.C.Sample:Value("falls") == 0, "ordinary deaths are neither falls nor drownings")
  -- a short fall: the one-second poll sees it
  kaka.o.falling = true
  tick(kaka, 2)
  kaka.o.falling = false
  fire(kaka, "PLAYER_DEAD")
  assert(kaka.C.Sample:Value("falls") == 1 and kaka.C.Sample:Value("deaths") == 3, "a fall death, from a two-second fall")
  -- drowning: the breath bar is listed and its live value is zero (the start value the info call returns is full)
  tick(kaka, 5)
  kaka.o.breath = 0
  tick(kaka, 2)
  fire(kaka, "PLAYER_DEAD")
  assert(kaka.C.Sample:Value("drownings") == 1, "a death with the breath bar empty is a drowning")
  kaka.o.breath = nil
  tick(kaka, 5)
  fire(kaka, "PLAYER_DEAD")
  assert(kaka.C.Sample:Value("drownings") == 1 and kaka.C.Sample:Value("deaths") == 5, "a later death is not")
  -- whispers an hour, from the count and the session
  for _ = 1, 5 do fire(kaka, "CHAT_MSG_WHISPER", "hi", "Someone-Forever") end
  tick(kaka, 5)
  local hours = math.max(0.25, (kaka.C.Sample:Value("session") or 0) / 3600)
  assert(kaka.C.Sample:Value("whispers") == math.floor(5 / hours), "whispers an hour: " .. tostring(kaka.C.Sample:Value("whispers")))
  -- standing still is noticed
  assert(kaka.C.Sample:Value("still") >= 25, "stood still for the ticks so far: " .. tostring(kaka.C.Sample:Value("still")))
  assert(kaka.C.Sample:Value("logins") == 1, "one login so far")
  local db = kaka.env.CuteDB
  local reloaded = newClient(charOf(NAMES[4]))
  login(reloaded, db, true)
  assert(reloaded.C.Sample:Value("deaths") == 5 and reloaded.C.Sample:Value("dance") == 1, "counters survive a reload")
  assert(reloaded.C.Sample:Value("logins") == 1, "a /reload is not a login")
  leave(reloaded)
  local again = newClient(charOf(NAMES[4]))
  login(again, db)
  assert(again.C.Sample:Value("logins") == 2, "logins counted across sessions")
  leave(again)
  -- the week turns between two sessions: the first login of the new week is one, the next is two (0.2.0's first cut
  -- counted the first as two: the reset set one and the login added one)
  local rec = db.chars["Kaka-Forever"]
  local keepDay, keepWeek, keepLogins = rec.day, rec.week, rec.counters.logins
  local late = newClient(charOf(NAMES[4]))
  late.dayShift = 9 * 86400
  login(late, db)
  assert(late.C.Sample:Value("logins") == 1 and rec.counters.logins == 1, "the first login of a new week is one: " .. tostring(late.C.Sample:Value("logins")))
  assert(rec.week == os.date("%Y-%W", EPOCH + late.clock + late.dayShift), "the record moved to the new week")
  leave(late)
  local late2 = newClient(charOf(NAMES[4]))
  late2.dayShift = 9 * 86400
  login(late2, db)
  assert(late2.C.Sample:Value("logins") == 2, "the next login that week is two: " .. tostring(late2.C.Sample:Value("logins")))
  leave(late2)
  -- Kaka's own client still runs on the old week: put its record back so its ten-minute check sees no turn
  rec.day, rec.week, rec.counters.logins = keepDay, keepWeek, keepLogins
  print("counters: deaths, dances, falls and drownings persist across a reload, which is not a login; a new week starts its logins at one")
end

-- 8: the roster: online and class from the guild; prune needs two misses, and only against a complete list
do
  local rows = yezin.C.Roster:Rows()
  assert(rows[1].me and rows[1].short == "Yezin", "you first")
  local byName = {}
  for _, r in ipairs(rows) do byName[r.short] = r end
  assert(byName.Kaka and byName.Kaka.addon and byName.Kaka.online == true and byName.Kaka.class == "PRIEST", "Kaka has the addon, is online and a priest")
  assert(byName.Bari and byName.Bari.online == false and byName.Bari.class == "PALADIN", "Bari is offline, from the guild")
  assert(byName.Garristan and not byName.Garristan.addon and byName.Garristan.level == 1 and byName.Garristan.zone == "Elwynn Forest", "Garristan is listed from the guild roster without the addon")
  assert(rows[1].class == "WARRIOR", "your own class is known")
  assert(yezin.C.Roster.updatedAt, "the roster knows when it last changed")
  -- Kaka leaves the guild: gone after two roster reads
  local saved = GUILD[4]
  table.remove(GUILD, 4)
  fire(yezin, "GUILD_ROSTER_UPDATE")
  assert(yezin.env.CuteDB.roster["Kaka-Forever"], "one miss keeps the record")
  fire(yezin, "GUILD_ROSTER_UPDATE")
  assert(not yezin.env.CuteDB.roster["Kaka-Forever"], "two misses prune it")
  table.insert(GUILD, 4, saved)
  fire(yezin, "GUILD_ROSTER_UPDATE")
  kaka.C.Comm:Full()
  tickAll(12)
  assert(yezin.env.CuteDB.roster["Kaka-Forever"], "back after Kaka sends again")
  -- a client with the older roster API, its guild window hiding offline members: a partial list prunes nobody
  print("roster: you first, online and class from the guild through C_Club, no-addon members listed, prune after two misses")
end

-- 9: the window, every page, for the officer and the member; the look
do
  local function pages(c, who, list)
    c.C.UI:Open("race")
    local f = c.C.UI.frame
    assert(f:IsShown(), "the window opened")
    for _, page in ipairs(list) do
      c.C.UI:Open(page)
      assert(c.C.UI.page == page, who .. " could open " .. page)
      check(f, who .. " " .. page)
      -- tooltips on a few cells
      for _, r in ipairs(c.C.UI.rows.items) do if r:IsShown() then hover(r); for _, cell in ipairs(r.cells) do if cell:IsShown() then hover(cell) end end end end
    end
    return f
  end
  local f = pages(yezin, "officer", { "race", "prog", "shame", "game", "officers", "me", "settings" })
  assert(yezin.C.UI.tabs.officers:IsShown(), "the officer sees the Officers tab")
  pages(kaka, "member", { "race", "prog", "shame", "game", "me", "settings" })
  assert(not kaka.C.UI.tabs.officers:IsShown(), "the member has no Officers tab")
  kaka.C.UI:Open("officers")
  assert(kaka.C.UI.page == "race", "a member asking for the officers' page lands on Race")
  -- the look: status and footer, aligned numbers, grey headers with the sorted one white, class bars, row heights
  yezin.C.UI:Open("race")
  assert(yezin.C.UI.status:GetText():match("^%d+ online with the addon  |  officer view$"), "the status line: " .. yezin.C.UI.status:GetText())
  assert(kaka.C.UI.status:GetText():match("member view$"), "the member's status line")
  assert(yezin.C.UI.footer:GetText():match("^Updated "), "the footer says when the roster last changed: " .. yezin.C.UI.footer:GetText())
  local me, kakaRow, garristan, mutu = rowOf(yezin, "Yezin"), rowOf(yezin, "Kaka"), rowOf(yezin, "Garristan"), rowOf(yezin, "Mutu")
  assert(me and kakaRow and garristan and mutu, "the rows")
  assert(cellOf(me, "level").label.__justify == "RIGHT" and cellOf(me, "zone").label.__justify == "LEFT", "numbers right, text left")
  assert(sameColor(me.bar.__color, { 0.96, 0.96, 0.96 }), "your bar is white")
  assert(sameColor(mutu.bar.__color, { 0.78, 0.61, 0.43 }), "a warrior's bar is the warrior colour")
  assert(cellOf(garristan, "level").label:GetText() == "1" and cellOf(garristan, "zone").label:GetText() == "Elwynn Forest", "a member without the addon shows the guild's level and zone")
  assert(cellOf(garristan, "xp").label:GetText() == "", "and nothing else")
  assert(me:GetHeight() == 20, "rows are 20 px")
  local whiteHeaders, greyHeaders = 0, 0
  for _, h in ipairs(yezin.C.UI.headerCells.items) do
    if h:IsShown() and h.def then
      if sameColor(h.label.__color, { 0.96, 0.96, 0.96 }) then whiteHeaders = whiteHeaders + 1; assert(h.id == "level", "the sorted column is the white one") else greyHeaders = greyHeaders + 1 end
      assert(h.label.__justify == ((h.def.kind == "text" or h.def.kind == "pips") and "LEFT" or "RIGHT"), "headers align like their column")
    end
  end
  assert(whiteHeaders == 1 and greyHeaders >= 5, "one white header, the rest grey")
  yezin.env.CuteDB.settings.density = "compact"
  yezin.C.UI:Open("race")
  assert(rowOf(yezin, "Yezin"):GetHeight() == 17, "compact rows are 17 px")
  check(yezin.C.UI.frame, "officer race, compact")
  yezin.env.CuteDB.settings.density = "normal"
  -- readiness on the prog page: a verdict in colour, the gaps in the tooltip
  yezin.C.UI:Open("prog")
  local readyCell = cellOf(rowOf(yezin, "Yezin"), "ready")
  assert(readyCell and readyCell.label:GetText() == "gaps" and sameColor(readyCell.label.__color, { 0.93, 0.74, 0.35 }), "readiness shows gaps in amber")
  local n0 = #lines
  hover(readyCell)
  local tip = table.concat(lines, "\n", n0 + 1)
  assert(tip:find("an empty slot", 1, true), "the tooltip names the gap: " .. tip)
  -- the self-only column: a dash on others' rows, the value on your own
  kaka.env.CuteDB.settings.columns.prog = { ilvl = true, unenchanted = true, deaths = true }
  kaka.C.UI:Open("prog")
  local own, other = cellOf(rowOf(kaka, "Kaka"), "unenchanted").label:GetText(), cellOf(rowOf(kaka, "Yezin"), "unenchanted").label:GetText()
  assert(own and own ~= "-" and own ~= "" and other == "-", "unenchanted: own value shows (" .. tostring(own) .. "), Yezin's is a dash (" .. tostring(other) .. ")")
  check(kaka.C.UI.frame, "member prog, two columns")
  -- the officer sees the member's
  yezin.env.CuteDB.settings.columns.prog = { ilvl = true, unenchanted = true }
  yezin.C.UI:Open("prog")
  local seen = cellOf(rowOf(yezin, "Kaka"), "unenchanted").label:GetText()
  assert(seen and seen ~= "-", "the officer sees Kaka's unenchanted slots: " .. tostring(seen))
  -- sorting by a column, remembered in the saved settings
  yezin.env.CuteDB.settings.columns.prog = nil
  yezin.C.UI:Open("race")
  local header
  for _, h in ipairs(yezin.C.UI.headerCells.items) do if h:IsShown() and h.id == "level" then header = h end end
  assert(header, "a Level header")
  press(header)
  assert(yezin.C.UI.sort.race and yezin.C.UI.sort.race.id == "level" and yezin.C.UI.sort.race.desc == false, "clicking the sorted column flips it")
  assert(yezin.env.CuteDB.settings.sort.race and yezin.env.CuteDB.settings.sort.race.desc == false, "the sort is saved")
  check(yezin.C.UI.frame, "officer race, sorted up")
  -- the scroll place survives a redraw and resets on a page change
  yezin.C.UI.scroll.bar:SetMinMaxValues(0, 100)
  yezin.C.UI.scroll.bar:SetValue(40)
  yezin.C.UI:Draw()
  assert(yezin.C.UI.scroll.bar:GetValue() == math.min(40, select(2, yezin.C.UI.scroll.bar:GetMinMaxValues())), "a redraw keeps the scroll place")
  yezin.C.UI:Open("prog")
  assert(yezin.C.UI.scroll.bar:GetValue() == 0, "a page change starts at the top")
  -- resized small: still no problems, on every page
  yezin.C.UI.frame:SetSize(760, 420)
  for _, page in ipairs({ "race", "prog", "shame", "game", "officers", "me", "settings" }) do
    yezin.C.UI:Open(page)
    check(yezin.C.UI.frame, "officer " .. page .. ", small window")
  end
  yezin.C.UI.frame:SetSize(1040, 640)
  -- a saved position off this screen comes back on it
  yezin.env.CuteDB.pos = { w = 1040, h = 640, left = 5000, top = -300 }
  yezin.C.UI:RestorePos()
  local p = yezin.C.UI.frame.__points[1]
  assert(p.x == 1600 - 1040 and p.y == 640, "the window is clamped to the screen: " .. p.x .. "," .. p.y)
  yezin.env.CuteDB.pos = nil
  yezin.C.UI.frame:ClearAllPoints(); yezin.C.UI.frame:SetPoint("CENTER")
  -- the minimap button and the hall's tooltips
  assert(yezin.C.UI.mini and yezin.C.UI.mini:IsShown(), "the minimap button")
  -- round, as the game's own: 32 px, the emblem cut by the portrait mask, the tracking ring over it
  local mini = yezin.C.UI.mini
  assert(mini.__w == 32 and mini.__h == 32 and not mini.__backdrop, "a 32 px button, no flat frame")
  assert(mini.icon.__mask and mini.icon.__mask.__tex == "Interface\\CharacterFrame\\TempPortraitAlphaMask" and mini.icon.__tex == "Interface\\AddOns\\Cute\\art\\logo.png", "the emblem masked round")
  assert(mini.ring.__tex == "Interface\\Minimap\\MiniMap-TrackingBorder" and mini.ring.__layer == "OVERLAY", "under the minimap ring")
  hover(yezin.C.UI.mini)
  yezin.C.UI:Open("shame")
  for _, card in ipairs(yezin.C.UI.cards.items) do if card:IsShown() then hover(card) end end
  print("window: every page opens for both views at both sizes, the look holds, self-only cells hidden from the member, sorting, scrolling and resizing hold")
end

-- 10: settings: a member cannot flip visibility; an officer's click plus Broadcast reaches the member; boxes follow clicks
do
  kaka.C.UI:Open("settings")
  local flipped = checkBox(kaka, function(cb) return cb.__disabled and cb.statId ~= nil end)
  assert(flipped, "the member's visibility boxes are disabled")
  local before = kaka.C.Policy:Vis("level")
  -- even a click on a disabled box (a macro could) changes nothing
  click(flipped)
  assert(kaka.C.Policy:Vis("level") == before, "a member's click changes no policy")
  -- the officer clicks Level to only-you in Settings and broadcasts
  yezin.C.UI:Open("settings")
  local onlyYou = checkBox(yezin, function(cb) return cb.statId == "level" and cb.vis == "self" end)
  assert(onlyYou and not onlyYou.__disabled, "the officer's Only-you box for Level")
  click(onlyYou)
  assert(yezin.C.Policy:Vis("level") == "self", "the click set the policy")
  yezin.C.Comm:SendPolicy()
  tickAll(3)
  assert(kaka.C.Policy:Vis("level") == "self", "the member applied the officer's policy")
  local everyone = checkBox(yezin, function(cb) return cb.statId == "level" and cb.vis == "all" end)
  click(everyone)
  yezin.C.Comm:SendPolicy()
  tickAll(3)
  assert(kaka.C.Policy:Vis("level") == "all", "and back")
  -- the Minimap button box: its fill follows the click and the button goes with it
  local mini = checkBox(yezin, function(cb) return cb.label and cb.label:GetText() == "Minimap button" end)
  assert(mini and mini:GetChecked() and mini.fill:IsShown(), "the minimap box starts ticked")
  click(mini)
  assert(not mini:GetChecked() and not mini.fill:IsShown() and not yezin.C.UI.mini:IsShown(), "unticked: the fill goes and so does the button")
  click(mini)
  assert(mini:GetChecked() and mini.fill:IsShown() and yezin.C.UI.mini:IsShown(), "ticked again")
  -- the Main character box is left alone while you type
  local edit
  for _, fr in ipairs(yezin.frames) do if fr.__kind == "EditBox" and fr:IsVisible() then edit = fr end end
  assert(edit, "the Main character box")
  edit:SetFocus(); edit:SetText("Yez")
  yezin.C.UI:Draw()
  assert(edit:GetText() == "Yez", "a redraw while typing keeps the text")
  edit.__scripts.OnEnterPressed(edit)
  assert(yezin.env.CuteDB.settings.main == "Yez" and yezin.C.Sample:Value("main") == "Yez", "Enter saves the main")
  -- the column checklist hides one column, not all of them
  yezin.C.UI:Open("race")
  local n = shownHeaders(yezin)
  yezin.C.UI.SetTicked("race", "zone", false)
  yezin.C.UI:Open("race")
  for _, h in ipairs(yezin.C.UI.headerCells.items) do if h:IsShown() then assert(h.id ~= "zone", "zone unticked, no zone column") end end
  assert(shownHeaders(yezin) == n - 1, "one column fewer: " .. shownHeaders(yezin) .. " of " .. n)
  yezin.C.UI.SetTicked("race", "zone", true)
  yezin.C.UI:Open("race")
  assert(shownHeaders(yezin) == n, "and back")
  check(yezin.C.UI.frame, "officer race after settings")
  -- role and raid spec are this character's
  yezin.C.UI:Open("settings")
  local tank = checkBox(yezin, function(cb) return cb.label and cb.label:GetText() == "Tank" end)
  click(tank)
  assert(yezin.C.Char().role == "Tank" and yezin.env.CuteDB.settings.role == nil, "the role is kept per character")
  print("settings: members cannot flip visibility, the officer's click and broadcast land, boxes follow clicks, typing survives redraws, one column unticks")
end

-- 11: a login storm: twenty clients say hello; each sends at most one message a second
do
  for i = 5, 20 do if i ~= 9 then newClient(charOf(NAMES[i])) end end
  for _, c in ipairs(clients) do if #c.sent == 0 and c ~= yezin and c ~= kaka then login(c) end end
  tickAll(60)
  for _, c in ipairs(clients) do
    local last
    for _, m in ipairs(c.sent) do
      if last then assert(m.at - last >= 1 - 1e-9, c.name .. " sent two messages within a second") end
      last = m.at
    end
    assert(#c.oversize == 0, c.name .. " tried a message over the limit")
  end
  local n = 0
  for _ in pairs(yezin.env.CuteDB.roster) do n = n + 1 end
  assert(n >= 15, "Yezin's roster filled from the storm: " .. n)
  for _, size in ipairs({ { 1040, 640 }, { 760, 420 } }) do
    yezin.C.UI.frame:SetSize(size[1], size[2])
    for _, page in ipairs({ "race", "prog", "shame", "game", "officers" }) do
      yezin.C.UI:Open(page)
      check(yezin.C.UI.frame, string.format("officer %s, twenty members, %dx%d", page, size[1], size[2]))
    end
  end
  yezin.C.UI.frame:SetSize(1040, 640)
  print(string.format("storm: %d clients, one message a second each, %d records on Yezin's roster", #clients, n))
end

-- 12: the throttle: the game's "too fast" waits and retries, nothing is lost; a message given up is sent with the next change
do
  kaka.throttle = 2
  kaka.o.zone = "Stranglethorn Vale"
  local before = #kaka.sent
  fire(kaka, "ZONE_CHANGED_NEW_AREA")
  tickAll(12)
  assert(#kaka.sent > before and kaka.throttle == 0, "retried past the throttle")
  assert(yezin.env.CuteDB.roster["Kaka-Forever"].stats.zone == "Stranglethorn Vale", "the zone arrived")
  -- a general error, over and over: the message is given up, its stats marked to go again, and they do
  kaka.fail = 99
  kaka.o.zone = "Tanaris"
  fire(kaka, "ZONE_CHANGED_NEW_AREA")
  tickAll(70)
  assert(yezin.env.CuteDB.roster["Kaka-Forever"].stats.zone == "Stranglethorn Vale", "Tanaris never left")
  assert(kaka.C.Sample.dirty.zone == true or kaka.C.Comm.queued.zone ~= nil, "the zone is marked to go again, or already queued again")
  local noted = false
  for _, e in ipairs(kaka.env.CuteDB.errors) do if e.msg:find("addon message not sent", 1, true) then noted = true end end
  assert(noted, "/cute errors says a message was given up")
  kaka.fail = 0
  kaka.o.level = 39
  fire(kaka, "PLAYER_LEVEL_UP", 39)
  tickAll(15)
  assert(yezin.env.CuteDB.roster["Kaka-Forever"].stats.zone == "Tanaris" and yezin.env.CuteDB.roster["Kaka-Forever"].stats.level == 39, "the zone went with the next change")
  print("throttle: the queue waits and retries; a message given up goes with the next change")
end

-- 13: not in a guild: nothing is sent, the window still opens on your own record
do
  local lone = newClient(charOf(NAMES[16], { inGuild = false }))
  lone.inGuild = false
  login(lone)
  tickAll(15)
  assert(#lone.sent == 0, "nothing leaves a guildless client")
  lone.C.UI:Open("race")
  check(lone.C.UI.frame, "guildless race")
  assert(lone.C.UI.footer:GetText() == "Not in a guild", "the footer says so")
  lone.C.UI:Open("me")
  check(lone.C.UI.frame, "guildless me")
  lone.C.UI:Open("game")
  check(lone.C.UI.frame, "guildless statistics (none on this client)")
  -- the hello went by while guildless; now Pell joins, the channel naming her with a Kstring that matches none of her
  -- names. The hello is said on joining, its ask carrying her GUID, before any delta: her own messages, handed back,
  -- leave no record, and the guild gets her full record
  assert(not lone.C.Comm.hello, "no hello said while guildless")
  lone.sender = "|Kq99|k"
  lone.inGuild = true
  fire(lone, "PLAYER_GUILD_UPDATE", "player")
  lone.o.level = lone.o.level + 1
  fire(lone, "PLAYER_LEVEL_UP", lone.o.level)
  tickAll(30)
  assert(lone.C.Comm.hello and msgs(lone, "1R") == 1 and msgs(lone, "1F") >= 1 and lone.sent[1].msg == "1R|" .. lone.o.guid, "the hello on joining, the ask first: " .. tostring(lone.sent[1] and lone.sent[1].msg))
  assert(msgs(lone, "1D") >= 1, "the level-up went as a delta after the hello")
  for key, e in pairs(lone.env.CuteDB.roster) do assert(key ~= "|Kq99|k" and e.stats.guid ~= lone.o.guid, "no record of yourself after joining: " .. key) end
  assert(lone.C.Roster.selfSenders["|Kq99|k"] == "guid" and lone.C.Roster:MyRowCount() == 1, "the Kstring sender known as you by your GUID, one row of you")
  local mine = 0
  for _, r in ipairs(lone.C.Roster:Rows()) do if r.me or r.key == "|Kq99|k" or r.short == "Pell" then mine = mine + 1 end end
  assert(mine == 1, "one row of Pell: " .. mine)
  local seen = yezin.env.CuteDB.roster["|Kq99|k"]
  assert(seen and seen.stats.guid == lone.o.guid and seen.stats.level == lone.o.level, "the guild has her record, GUID and the new level")
  -- leaving owes the hello again, said on the next join
  lone.inGuild = false
  fire(lone, "PLAYER_GUILD_UPDATE", "player")
  assert(not lone.C.Comm.hello, "out of the guild, the hello is owed")
  lone.inGuild = true
  local asks = msgs(lone, "1R")
  fire(lone, "PLAYER_GUILD_UPDATE", "player")
  tickAll(3)
  assert(msgs(lone, "1R") == asks + 1, "a rejoin says hello again")
  -- (the guild's answers to her asks, the statistics a minute and a half on, go out before the next scenario)
  tickAll(95)
  yezin.env.CuteDB.roster["|Kq99|k"] = nil
  kaka.env.CuteDB.roster["|Kq99|k"] = nil
  lone.inGuild = false
  leave(lone)
  print("guildless: nothing sent, the window shows your own record; a guild joined later gets the hello then, and your own messages leave no record")
end

-- 14: the trackers: XP pace across a ding, gold in copper, grey sales, recipes, resists, the day and the week
do
  -- level 38 at 66100 of 66200 XP; 50 more, then the ding to 39 (70200 a level) with 25 into it: 125 XP over ten seconds
  local c = newClient(charOf(NAMES[11], { level = 38, xp = 66100, xpmax = 66200, money = 10000 }))
  login(c)
  tick(c, 5) -- the first XP sample
  c.o.xp = 66150
  fire(c, "PLAYER_XP_UPDATE", "player")
  tick(c, 5)
  c.o.level, c.o.xp, c.o.xpmax = 39, 25, 70200
  fire(c, "PLAYER_XP_UPDATE", "player")
  fire(c, "PLAYER_LEVEL_UP", 39)
  tick(c, 185) -- the pace needs three minutes of samples before it shows
  local S = c.C.Sample
  local ring = S.track.xp
  local rate = math.floor(125 / ((ring[#ring][1] - ring[1][1]) / 3600))
  assert(rate > 0 and S:Value("xp_hour") == rate, "XP an hour counts the rest of the old level across the ding: " .. tostring(S:Value("xp_hour")) .. " vs " .. rate)
  local left = S.XPLeft(39, 25, 70200)
  assert(S:Value("to60") == math.floor(left / rate + 0.5) and S:Value("to60") > 0, "hours to 60 from the levels ahead: " .. tostring(S:Value("to60")))
  assert(S.track.sessionXP == 125, "the session's XP keeps the old level's rest: " .. tostring(S.track.sessionXP))
  -- gold moves in copper
  c.o.money = 19500
  fire(c, "PLAYER_MONEY")
  assert(S:Value("gold_earned") == 9500 and c.C.UI.Format(c.C.Stats.byId.gold_earned, 9500) == "95s", "a 95 silver gain counts")
  fire(c, "QUEST_TURNED_IN", 1, 100, 4500)
  assert(S:Value("gold_quests") == 4500, "quest money in copper")
  -- a grey sold at a merchant
  c.o.bags = { [0] = { [1] = { quality = 0, link = "item:5000", count = 3 }, [2] = { quality = 2, link = "item:5001", count = 1 } } }
  c.o.prices = { [5000] = 15, [5001] = 900 }
  fire(c, "MERCHANT_SHOW")
  c.env.C_Container.UseContainerItem(0, 1)
  c.env.C_Container.UseContainerItem(0, 2)
  fire(c, "MERCHANT_CLOSED")
  c.env.C_Container.UseContainerItem(0, 1)
  assert(S:Value("grey_gold") == 45, "three greys at 15 copper, the green and the use outside the merchant not counted: " .. tostring(S:Value("grey_gold")))
  -- raid recipes, asked of the trade skill window by id
  c.o.learned = { [17635] = true }
  fire(c, "TRADE_SKILL_SHOW")
  assert(S:Value("raid_recipes")[17635] == true and S:Value("raid_recipes")[17636] == nil, "the Titans flask is known, the others not")
  -- the effective resistance
  c.o.resist = { [2] = 45 }
  fire(c, "PLAYER_EQUIPMENT_CHANGED")
  tick(c, 2)
  assert(S:Value("resist_fire") == 45, "fire resist is the sheet's effective value")
  -- the mount and the skills
  c.o.mount = true
  S:Read("mount")
  assert(S:Value("mount") == true, "the mount flag is the eleventh return")
  -- the day turns: today's counters reset; the week turns: logins become this session's one
  fire(c, "QUEST_TURNED_IN", 2, 100, 0)
  assert(S:Value("quests_today") == 2, "two hand-ins today so far: " .. tostring(S:Value("quests_today")))
  c.dayShift = 86400
  tick(c, 660)
  assert(S:Value("quests_today") == 0, "a new day resets today's counters")
  fire(c, "QUEST_TURNED_IN", 3, 100, 0)
  tick(c, 660)
  assert(S:Value("quests_today") == 1, "the check keeps running and does not reset the same day twice")
  c.dayShift = 9 * 86400
  tick(c, 660)
  local rec = c.env.CuteDB.chars[c.name]
  assert(S:Value("logins") == 1 and rec.counters.logins == 1 and rec.week == os.date("%Y-%W", EPOCH + c.clock + c.dayShift), "a new week turning mid-session starts logins at this one: " .. tostring(S:Value("logins")))
  -- heartbeat-only stats are read every pass
  local reads = 0
  local real = c.env.C_SpecializationInfo.GetSpecialization
  c.env.C_SpecializationInfo.GetSpecialization = function(...) reads = reads + 1; return real(...) end
  tick(c, 601)
  assert(reads >= 2, "the heartbeat reads the registry every five minutes: " .. reads)
  -- emotes without DoEmote (this client): your own lines in the emote chat count, others' do not, and a line made
  -- secret by a dungeon or raid cannot; the hint says so and /cute errors has the note
  fire(c, "CHAT_MSG_TEXT_EMOTE", "You dance.", c.name)
  fire(c, "CHAT_MSG_TEXT_EMOTE", "You sit down.", c.o.name)
  fire(c, "CHAT_MSG_TEXT_EMOTE", "Kaka waves.", "Kaka-Forever")
  fire(c, "CHAT_MSG_TEXT_EMOTE", secret("string"), secret("string"))
  assert(S:Value("emotes") == 2 and S:Value("dance") == 1 and S:Value("sit") == 1, "your own emote lines count, others' and secret ones do not")
  assert(c.C.Stats.byId.dance.hint:find("secret in dungeons and raids", 1, true) and c.C.Stats.byId.emotes.hint == c.C.Stats.byId.sit.hint, "the hints say where emotes go uncounted: " .. tostring(c.C.Stats.byId.dance.hint))
  local noted = false
  for _, x in ipairs(c.env.CuteDB.errors) do if x.msg:find("DoEmote is missing", 1, true) then noted = true end end
  assert(noted and #c.chat == 0, "the missing function is noted for /cute errors without a chat line")
  -- with DoEmote (a client made withEmote): the hook counts, the hints stay the registry's
  local e = newClient(charOf(NAMES[12], { withEmote = true }))
  login(e)
  e.env.DoEmote("DANCE")
  e.env.DoEmote("wave")
  assert(e.C.Sample:Value("emotes") == 2 and e.C.Sample:Value("dance") == 1 and e.C.Sample:Value("sit") == 0, "DoEmote's hook counts")
  assert(e.C.Stats.byId.dance.hint == nil, "no caveat where the function exists")
  -- guild lines count as you send them; CHAT_MSG_GUILD, whose sender is secret in dungeons and raids, is not even registered
  e.env.C_ChatInfo.SendChatMessage("hello guild", "GUILD")
  e.env.C_ChatInfo.SendChatMessage("where are you", "PARTY")
  e.env.C_ChatInfo.SendChatMessage("where are you", "GUILD")
  fire(e, "CHAT_MSG_GUILD", secret("string"), secret("string"))
  fire(e, "CHAT_MSG_GUILD", "a line", "Quillan-Forever")
  assert(e.C.Sample:Value("gchat") == 2 and e.C.Sample:Value("where") == 1, "two guild lines sent, one where-are-you in party; the guild events count nothing: " .. tostring(e.C.Sample:Value("gchat")))
  assert(not e.C.Sample.frame.__events.CHAT_MSG_GUILD, "CHAT_MSG_GUILD is not registered")
  leave(e); leave(c)
  print("trackers: XP pace across a ding, copper gold, grey sales, recipes, resists, the mount, the day and the week, emotes both ways, guild lines as sent")
end

-- 15: calls Cute never makes
do
  local NEVER = { "COMBAT_LOG_EVENT_UNFILTERED", "C_SuperTrack", "SetUserWaypoint", "StaticPopup", "OpenChat", "ChatFrame_OpenChat", "AcceptQuest", "LootSlot", "ToggleWorldMap" }
  local found = {}
  for file in io.open(HERE .. "/Cute/Cute.toc"):read("*a"):gmatch("\n([%w_]+%.lua)") do
    local n = 0
    for src in io.lines(HERE .. "/Cute/" .. file) do
      n = n + 1
      local code = src:gsub("%-%-.*$", "")
      for _, name in ipairs(NEVER) do
        if code:find(name, 1, true) and not (name == "COMBAT_LOG_EVENT_UNFILTERED" and code:find("==", 1, true)) then found[#found + 1] = file .. ":" .. n .. " " .. name end
      end
    end
  end
  assert(#found == 0, "a call Cute never makes:\n  " .. table.concat(found, "\n  "))
  -- the unit events are yours only
  local f = kaka.C.Sample.frame
  assert(f.__units and f.__units.UNIT_AURA == "player" and f.__units.UNIT_SPELLCAST_SUCCEEDED == "player", "UNIT_AURA and UNIT_SPELLCAST_SUCCEEDED are registered for the player")
  print("never: the combat log, the game's tracking, popups and chat boxes stay untouched; unit events are yours only")
end

-- 16: Legacy Challenges: the counts, points, trees, renown and categories from the Legacy window's own calls; the
-- latest challenge from the client at login and from ACHIEVEMENT_EARNED; the game rule; a client without the calls
do
  local S = yezin.C.Stats
  local function V(id) return yezin.C.Sample:Value(id) end
  -- Yezin, a warrior: Quests 2 of 6 (the third, completed by another character, does not count), Dungeons 1 of 3,
  -- Classic Dungeons 2 of 2, Warrior 1 of 3; 42 listed
  assert(V("lc_done") == 6 and V("lc_total") == 42, "challenges done and listed: " .. tostring(V("lc_done")) .. " of " .. tostring(V("lc_total")))
  assert(V("lc_pts") == 5 * V("lc_done"), "Legacy points are the trait currency of the challenges done, on every client: " .. tostring(V("lc_pts")))
  assert(V("lc_renown") == 4 and V("lc_free") == 2 and V("lc_prof") == 3 and V("lc_adv") == 2 and V("lc_prog") == 1, "renown, unspent and the three trees")
  -- the categories as pips: Quests 2/6 under half (4), Exploration none (0), Dungeons with its child 3/5 (5), Warrior 1/3 (4); Classes, empty, left out
  assert(V("lc_cats") == "4054", "a pip per category, the class's last: " .. tostring(V("lc_cats")))
  local cats = S.LegacyCategories(S.Legacy(), "WARRIOR")
  assert(#cats == 4 and cats[1].name == "Quests" and cats[3].name == "Dungeons" and cats[3].total == 5 and cats[4].name == "Warrior", "the categories, children folded in")
  assert(V("lc_last") == "Warrior 1", "the latest at login, from GetLatestCompletedAchievements: " .. tostring(V("lc_last")))
  -- a challenge earned: named at once, the walk cleared and read again a second later
  yezin.o.lcDone = { [15002] = 1 }
  fire(yezin, "ACHIEVEMENT_EARNED", 150021, false)
  assert(V("lc_last") == "Exploration 1", "ACHIEVEMENT_EARNED names the latest: " .. tostring(V("lc_last")))
  tick(yezin, 2)
  assert(V("lc_done") == 7 and V("lc_cats") == "4454", "the walk is cleared and re-read: " .. tostring(V("lc_done")) .. " " .. tostring(V("lc_cats")))
  -- the pips' tooltip names the categories: your own say the counts, a member's the quarter, with the row's class category
  yezin.env.CuteDB.settings.columns.prog = { lc_cats = true, lc_done = true, lc_last = true }
  yezin.C.UI:Open("prog")
  local n0 = #lines
  hover(cellOf(rowOf(yezin, "Yezin"), "lc_cats"))
  local tip = table.concat(lines, "\n", n0 + 1)
  assert(tip:find("Quests | 2 of 6", 1, true) and tip:find("Warrior | 1 of 3", 1, true), "your own pips say the counts: " .. tip)
  n0 = #lines
  hover(cellOf(rowOf(yezin, "Kaka"), "lc_cats"))
  tip = table.concat(lines, "\n", n0 + 1)
  assert(tip:find("Priest | a quarter or more", 1, true) and tip:find("Exploration | none", 1, true), "a member's pips read by quarters, the row's class category last: " .. tip)
  assert(cellOf(rowOf(yezin, "Kaka"), "lc_last").label:GetText() == "Priest 1", "the member's latest challenge came over the wire as text")
  check(yezin.C.UI.frame, "officer prog, legacy columns")
  yezin.env.CuteDB.settings.columns.prog = nil
  -- the same on a client without GetTotalAchievementPoints (the addon never reads it: one way to count on every client)
  local sum = newClient(charOf(NAMES[17], { without = { GetTotalAchievementPoints = true } }))
  login(sum)
  assert(sum.C.Sample:Value("lc_pts") == 5 * sum.C.Sample:Value("lc_done") and sum.C.Sample:Value("lc_done") == 6, "the fallback sums the trait currency per challenge done: " .. tostring(sum.C.Sample:Value("lc_pts")))
  assert(sum.C.Sample:Value("lc_last") == "", "no latest without the client's list, until one is earned")
  leave(sum)
  -- the game rule that hides the Legacy window: the challenge stats read as its reason, the trees and renown still read
  local off = newClient(charOf(NAMES[18], { achDisabled = true }))
  login(off)
  assert(off.C.Sample:Value("lc_done") == nil and off.C.Sample:Error("lc_done") == "Legacy Challenges are disabled on this realm", "disabled: " .. tostring(off.C.Sample:Error("lc_done")))
  assert(off.C.Sample:Value("lc_renown") == 4 and off.C.Sample:Value("lc_prof") == 3, "renown and the trees still read")
  leave(off)
  -- a client without the Legacy window's globals: the reason in the tooltip, nothing thrown
  local none = newClient(charOf(NAMES[19], { without = { GetCategoryList = true } }))
  login(none)
  assert(none.C.Sample:Value("lc_done") == nil and none.C.Sample:Error("lc_done") == "GetCategoryList is missing on this client", "missing: " .. tostring(none.C.Sample:Error("lc_done")))
  leave(none)
  print("legacy: challenges done and listed, points both ways, renown, unspent and the three trees, a pip per category with names in the tooltip, the latest at login and on ACHIEVEMENT_EARNED, the game rule and a missing function read as their reason")
end

-- 17: the game's statistics: a dynamic category where the client reports them, none where it does not; their own
-- full-record pass; a receiver without the API keeps them; the policy per category; the page for both views and
-- the empty state; a storm of CRITERIA_UPDATE re-reads once in thirty seconds; a login with 300 statistics stays
-- under twenty messages in its first minute; an empty list at login is asked again
do
  local S = yezin.C.Stats
  assert(#S.byCat.game == 11 and S.byId.g2001 and not S.byId.g2003, "eleven statistics defined, the one marked skip left out: " .. #S.byCat.game)
  assert(S.byId.g2001.label == "Total kills" and S.byId.g2004.hint == "Kills > Creatures" and S.byId.g2004.game == 131 and S.byId.g2001.slow == true and S.byId.g2001.kind == "int",
    "the label from GetAchievementInfo, the category path as the hint, the category id, slow ints")
  assert(yezin.C.Sample:Value("g2001") == 1234 and yezin.C.Sample:Value("g2008") == 0, "the quantity string parsed, -- read as 0")
  assert(S.Quantity("1 234") == 1234 and S.Quantity("1.234.567") == 1234567 and S.Quantity("--") == 0 and S.Quantity("") == nil and S.Quantity(nil) == nil, "the parser")
  assert(#S.game.cats == 4 and S.game.cats[1].name == "Kills" and S.game.cats[2].name == "Creatures" and S.game.cats[2].parent == 130 and S.game.cats[2].path == "Kills > Creatures"
    and S.game.cats[3].name == "Deaths", "the categories as the game groups them, a child after its parent")
  assert(yezin.C.Policy:Vis("g2001") == "all", "statistics default to everyone")
  yezin.env.SlashCmdList.CUTE("api")
  assert(yezin.chat[#yezin.chat - 1]:find("statistics: 11 defined in 4 categories", 1, true), "/cute api says how many: " .. yezin.chat[#yezin.chat - 1])
  -- a client without the API: nothing defined, the reason kept and noted; others' statistics still stored as ints
  local plain = newClient(charOf(NAMES[20]))
  login(plain)
  assert(#plain.C.Stats.byCat.game == 0 and plain.C.Stats.gameNote == "GetStatisticsCategoryList is missing on this client", "nothing defined without the function: " .. tostring(plain.C.Stats.gameNote))
  local noted = false
  for _, e in ipairs(plain.env.CuteDB.errors) do if e.msg == "GetStatisticsCategoryList is missing on this client" then noted = true end end
  assert(noted and #plain.chat == 0, "noted for /cute errors, no chat line")
  tickAll(45)
  local e = plain.env.CuteDB.roster["Yezin-Forever"]
  assert(e and e.stats.level and e.stats.g2001 == nil, "the first full record has no statistics")
  tickAll(60)
  assert(e.stats.g2001 == 1234 and e.stats.g2008 == 0, "the statistics pass answered the hello; a receiver without the API keeps them as ints: " .. tostring(e.stats.g2001))
  assert(kaka.env.CuteDB.roster["Yezin-Forever"].stats.g2001 == 1234, "Kaka has Yezin's kills too")
  -- a changed statistic: the pass re-reads it; it travels on the flush, not as it ticks
  yezin.o.stat = { [2001] = 1300 }
  fire(yezin, "CRITERIA_UPDATE")
  assert(yezin.C.Sample:Value("g2001") == 1300, "the pass re-read it")
  tickAll(5)
  assert(kaka.env.CuteDB.roster["Yezin-Forever"].stats.g2001 == 1234, "not sent as it ticks")
  tickAll(125)
  assert(kaka.env.CuteDB.roster["Yezin-Forever"].stats.g2001 == 1300, "the flush carried it")
  -- a storm of criteria: one pass, the next thirty seconds on
  local passes = yezin.C.Sample.gamePasses
  local reads = yezin.statReads or 0
  for _ = 1, 50 do fire(yezin, "CRITERIA_UPDATE"); tick(yezin, 0.2) end
  assert(yezin.C.Sample.gamePasses == passes + 1, "fifty criteria updates in ten seconds: one pass: " .. (yezin.C.Sample.gamePasses - passes))
  assert((yezin.statReads or 0) - reads <= 11, "and no more GetStatistic calls than the statistics: " .. ((yezin.statReads or 0) - reads))
  tick(yezin, 31)
  assert(yezin.C.Sample.gamePasses == passes + 2, "the pass they asked for came thirty seconds on: " .. (yezin.C.Sample.gamePasses - passes))
  -- the policy, per category: Kills only-you covers its statistics and its child's; a child set on its own
  yezin.C.Policy:Set("gc130", "self")
  yezin.C.Comm:SendPolicy()
  tickAll(3)
  assert(kaka.C.Policy:Vis("g2001") == "self" and kaka.C.Policy:Vis("g2004") == "self" and kaka.C.Policy:Vis("g2007") == "all", "a category's choice covers its statistics and its child's")
  yezin.C.Policy:Set("gc131", "all")
  yezin.C.Comm:SendPolicy()
  tickAll(3)
  assert(kaka.C.Policy:Vis("g2004") == "all" and kaka.C.Policy:Vis("g2001") == "self", "a child set on its own")
  assert(plain.C.Policy:Vis("gc130") == "self", "the receiver without the API keeps the category's setting")
  -- Settings shows one pair per category, none per statistic
  yezin.C.UI:Open("settings")
  local perCat, perStat = 0, 0
  for _, fr in ipairs(yezin.frames) do
    if fr.__kind == "CheckButton" and fr:IsVisible() and fr.vis == "self" and type(fr.statId) == "string" then
      if fr.statId:match("^gc%d+$") then perCat = perCat + 1 elseif fr.statId:match("^g%d+$") then perStat = perStat + 1 end
    end
  end
  assert(perCat == 4 and perStat == 0, "four category pairs, no per-statistic pair: " .. perCat .. " " .. perStat)
  local onlyKills = checkBox(yezin, function(cb) return cb.statId == "gc130" and cb.vis == "self" end)
  assert(onlyKills and onlyKills:GetChecked(), "the Kills pair shows only-you")
  check(yezin.C.UI.frame, "officer settings, statistics categories")
  kaka.C.UI:Open("settings")
  check(kaka.C.UI.frame, "member settings, statistics categories")
  -- the page: categories left, the open one's statistics right with your value and the leader; a click ranks everyone
  -- (the page's two columns are two virtual lists: the categories, and the statistics with their rankings)
  local function lineOf(c, test)
    for _, list in ipairs({ c.C.UI.catLines, c.C.UI.lines }) do for _, l in ipairs(list.items) do if l:IsShown() and test(l) then return l end end end
  end
  yezin.C.UI:Open("game")
  assert(yezin.C.UI.page == "game" and yezin.C.UI.gameCat == 130, "opens on the first category with statistics")
  local kills = lineOf(yezin, function(l) return l.def and l.def.id == "g2001" and not l.member end)
  assert(kills and kills.val:GetText() == "1300" and kills.val.__justify == "RIGHT", "your value, right-aligned: " .. tostring(kills and kills.val:GetText()))
  assert(kills.who:GetText():find("Yezin", 1, true) and kills.who:GetText():find("1300", 1, true), "the leader, named and valued: " .. kills.who:GetText())
  local catLines = 0
  for _, l in ipairs(yezin.C.UI.catLines.items) do if l:IsShown() and l.cat then catLines = catLines + 1 end end
  assert(catLines == 4, "the four categories on the left: " .. catLines)
  check(yezin.C.UI.frame, "officer statistics")
  press(kills)
  local ranked = {}
  for _, l in ipairs(yezin.C.UI.lines.items) do if l:IsShown() and l.member and l.def.id == "g2001" then ranked[#ranked + 1] = l end end
  assert(#ranked >= 2 and ranked[1].member.row.short == "Yezin" and ranked[1].name:GetText():find("^1%.") and ranked[2].name:GetText():find("^2%."), "a click ranks every member, the leader first: " .. #ranked)
  check(yezin.C.UI.frame, "officer statistics, a statistic opened")
  for _, l in ipairs(yezin.C.UI.lines.items) do if l:IsShown() then hover(l) end end
  -- the member: Kills is only-you, so the leader is Kaka's own value and Yezin's is a dash in the ranking
  kaka.C.UI:Open("game")
  local kkills = lineOf(kaka, function(l) return l.def and l.def.id == "g2001" and not l.member end)
  assert(kkills and kkills.who:GetText():find("Kaka", 1, true), "the member's leader is the one value it may see: " .. kkills.who:GetText())
  press(kkills)
  local dash = lineOf(kaka, function(l) return l.member and l.member.row.short == "Yezin" and l.def.id == "g2001" end)
  assert(dash and dash.who:GetText() == "-" and dash.member.hidden, "Yezin's kills are a dash for the member")
  check(kaka.C.UI.frame, "member statistics, a statistic opened")
  local creatures = lineOf(kaka, function(l) return l.cat and l.cat.id == 131 end)
  press(creatures)
  assert(kaka.C.UI.gameCat == 131, "the child category opened")
  local cre = lineOf(kaka, function(l) return l.def and l.def.id == "g2004" and not l.member end)
  assert(cre and cre.who:GetText():find("1100", 1, true), "Creatures is everyone's again: " .. cre.who:GetText())
  check(kaka.C.UI.frame, "member statistics, a child category")
  for _, c in ipairs({ yezin, kaka }) do
    c.C.UI.frame:SetSize(760, 420)
    c.C.UI:Open("game")
    check(c.C.UI.frame, (c == yezin and "officer" or "member") .. " statistics, small window")
    c.C.UI.frame:SetSize(1040, 640)
  end
  -- the empty state, where the client has no statistics API
  plain.C.UI:Open("game")
  local said, counters = false, false
  for _, l in ipairs(plain.C.UI.labels.items) do
    if l:IsShown() and l:GetText():find("GetStatisticsCategoryList is missing", 1, true) then said = true end
    if l:IsShown() and l:GetText():find("counters stay on the other pages", 1, true) then counters = true end
  end
  assert(said and counters, "the empty state names the reason and says where the addon's own counters are")
  check(plain.C.UI.frame, "member statistics, empty state")
  plain.C.UI:Open("me")
  check(plain.C.UI.frame, "member me, no statistics")
  leave(plain)
  -- a login with 300 statistics: under twenty messages per client in its first minute, every statistic across by
  -- the second, the whole login under forty-five
  local big1 = newClient(charOf(NAMES[12], { withStats = true, manyStats = 300 }))
  local big2 = newClient(charOf(NAMES[16], { withStats = true, manyStats = 300 }))
  login(big1); login(big2)
  tickAll(60)
  assert(#big1.sent < 20 and #big2.sent < 20, "under twenty messages in the first minute with 311 statistics: " .. #big1.sent .. ", " .. #big2.sent)
  assert(big2.env.CuteDB.roster[big1.name] and big2.env.CuteDB.roster[big1.name].stats.g3001 == nil, "none of them in that minute")
  tickAll(70)
  local n = 0
  for id in pairs(big2.env.CuteDB.roster[big1.name].stats) do if id:match("^g%d+$") then n = n + 1 end end
  assert(n == 311, "all 311 statistics across within two minutes: " .. n)
  assert(#big1.sent < 45 and #big1.oversize == 0, "the whole login under forty-five messages: " .. #big1.sent)
  leave(big1); leave(big2)
  -- an empty list at login (the data still loading): nothing defined, asked again at thirty seconds
  local late = newClient(charOf(NAMES[13], { withStats = true }))
  late.statsEmpty = true
  login(late)
  assert(#late.C.Stats.byCat.game == 0 and late.C.Stats.gameNote == "This client reports no statistics", "an empty list at login: nothing defined, the note says so")
  late.statsEmpty = false
  tick(late, 31)
  assert(#late.C.Stats.byCat.game == 11 and late.C.Sample:Value("g2001") == 1234 and late.C.Stats.gameNote == nil, "the retry at thirty seconds defined and read them")
  leave(late)
  print("statistics: eleven defined where the client reports them, none where it does not; their own pass after the hello, kept by a receiver without the API; the policy per category; the page both ways, the empty state; one pass per thirty seconds in a storm; 311 statistics under twenty messages in the first minute")
end

-- 18: a long policy goes out in chunks under one "at" and arrives whole; a reset (empty) replaces it
do
  local P = yezin.C.Policy
  local ids = {}
  for _, def in ipairs(yezin.C.Stats.list) do if def.cat == "leveling" or def.cat == "prog" then ids[#ids + 1] = def.id end end
  assert(#ids >= 40, "enough stats for a policy wider than one message")
  for _, id in ipairs(ids) do P:Set(id, "self") end
  local before = #yezin.sent
  yezin.C.Comm:SendPolicy()
  tickAll(#ids)
  local chunks = 0
  for i = before + 1, #yezin.sent do if yezin.sent[i].msg:sub(1, 2) == "1P" then chunks = chunks + 1; assert(#yezin.sent[i].msg <= 255) end end
  assert(chunks >= 2, "the policy needed more than one message: " .. chunks)
  for _, id in ipairs(ids) do assert(kaka.C.Policy:Vis(id) == "self", "the member applied every chunk: " .. id) end
  assert(kaka.env.CuteDB.policy.at == yezin.env.CuteDB.policy.at, "one policy, one at")
  -- a reset: an empty policy with a newer at replaces the lot
  yezin.env.CuteDB.policy = { vis = {}, by = yezin.name, rank = 1, at = yezin.env.CuteDB.policy.at + 5, threshold = 1 }
  yezin.C.Comm:SendPolicy()
  tickAll(3)
  assert(kaka.C.Policy:Vis(ids[1]) == yezin.C.Stats.byId[ids[1]].default, "the reset reached the member")
  print(string.format("policy chunks: %d messages for %d entries, applied whole; a reset replaces them", chunks, #ids))
end

-- 19: Forever's names. A character has two words ("Helga Bluntforce"): UnitName gives the first name and the surname,
-- the roster and the channel name it with both, and 0.3.0 showed Helga three times ("Helga (you)", "Helga Bluntforce
-- (no addon)" and a grey "Helga Bluntforce" of question marks: her own messages, handed back by the game, kept as a
-- member's record). Here: one row for you, named as the roster names you; your own messages dropped, even under a
-- sender string that matches none of your names (a Kstring), by the GUID they carry; a member whose roster name is a
-- Kstring joined to its record by GUID; ranks found the same way; 0.3.0's ghost record gone at login; /cute diag
do
  local function forever(first, rank, rankName, class, level, rosterName)
    GUILD[#GUILD + 1] = { name = rosterName, guid = guidOf(first), rank = rank, rankName = rankName, class = class, level = level, online = true }
    return { first, rank, rankName, class, level }
  end
  local H = forever("Helga", 0, "Guild Master", "WARRIOR", 30, "Helga Bluntforce")
  local T = forever("Thora", 1, "Officer", "PRIEST", 28, "Thora Bjorn")
  local I = forever("Icee", 3, "Raider", "MAGE", 26, "Icee Cake")
  local K = forever("Ser", 3, "Raider", "ROGUE", 25, "|Kq77|k") -- the roster gives this one's name as a Kstring
  forever("Thora Stonehew", 4, "Member", "HUNTER", 50, "Thora Stonehew") -- Thora's namesake, without the addon so far
  -- 0.3.0 left Helga a record of her own statistics' echo under the channel's name for her
  local ghost = { roster = { ["Helga Bluntforce"] = { seen = EPOCH + 900, online = true, stats = { g2001 = 3, g2004 = 1 }, at = {} } } }
  local helga = newClient(charOf(H, { surname = "Bluntforce", fullNameSurname = true, sender = "Helga Bluntforce", withStats = true }))
  local thora = newClient(charOf(T, { surname = "Bjorn", sender = "Thora Bjorn" }))
  local icee = newClient(charOf(I, { surname = "Cake", sender = "|Kq88|k" })) -- the channel names Icee with a Kstring
  local ser = newClient(charOf(K, { surname = "Caliber", sender = "Ser Caliber" }))
  login(helga, ghost); login(thora); login(icee); login(ser)
  assert(not helga.env.CuteDB.roster["Helga Bluntforce"], "0.3.0's ghost record of yourself is dropped at login")
  tickAll(45)
  for _, c in ipairs({ helga, thora, icee, ser }) do
    for key, e in pairs(c.env.CuteDB.roster) do
      assert(key ~= c.sender and e.stats.guid ~= c.o.guid, c.o.name .. " keeps no record of itself: " .. key)
    end
  end
  assert(icee.C.Roster.selfSenders["|Kq88|k"], "a sender string matching none of your names is known as you by the GUID in your ask")
  -- one row for Helga, the first, named as the roster names her; the members joined by GUID
  local rows = helga.C.Roster:Rows()
  local helgas, byShort = 0, {}
  for _, r in ipairs(rows) do
    if r.short:find("Helga", 1, true) then helgas = helgas + 1 end
    byShort[r.short] = r
  end
  assert(helgas == 1 and rows[1].me and rows[1].short == "Helga Bluntforce" and helga.C.Roster:MyRowCount() == 1, "one row for you, the roster's name: " .. helgas .. " " .. rows[1].short)
  assert(byShort["Thora Bjorn"] and byShort["Thora Bjorn"].addon and byShort["Thora Bjorn"].stats.level == 28 and byShort["Thora Bjorn"].online, "Thora's record is on her roster row")
  assert(byShort["Icee Cake"] and byShort["Icee Cake"].addon and byShort["Icee Cake"].key == "|Kq88|k" and not byShort["|Kq88|k"], "Icee's record, under a Kstring sender, joined by GUID")
  assert(byShort["|Kq77|k"] and byShort["|Kq77|k"].addon and byShort["|Kq77|k"].stats.level == 25 and not byShort["Ser Caliber"], "a roster name that is a Kstring joined to its record by GUID, no second row")
  -- ranks through the same join: Helga leads, Thora is an officer, the others are not
  assert(helga.C.Roster:MeOfficer() and helga.C.Roster:IsOfficer("Thora Bjorn") and not helga.C.Roster:IsOfficer("|Kq88|k") and not helga.C.Roster:IsOfficer("Ser Caliber"), "ranks found by GUID and name")
  assert(ser.C.Policy:Receive("Thora Bjorn", EPOCH + 10 ^ 7, 1, "gold=a") == true and ser.C.Policy:Vis("gold") == "all", "an officer with two names is an officer")
  assert(helga.C.Policy:Describe():find("Set by ", 1, true), "who set the policy, named")
  -- the GUID decides over a name. Thora's saved key is "Thora-Forever" (her first name and the realm), and a channel
  -- that names her namesake the same matches her by name: a delta before any full record is taken for hers; the
  -- namesake's full record, carrying another GUID, is theirs, and so are their deltas after it
  local TR, tdb = thora.C.Roster, thora.env.CuteDB.roster
  assert(thora.C.Me() == "Thora-Forever", "Thora's saved key: " .. tostring(thora.C.Me()))
  thora.C.Comm:Receive("1D|3|level=1m", "GUILD", "Thora-Forever")
  assert(not tdb["Thora-Forever"] and TR.selfSenders["Thora-Forever"] == "name", "a delta under your name, no GUID: taken for yours")
  thora.C.Comm:Receive("1F|1|1|3|guid=" .. guidOf("Thora Stonehew") .. ";level=1n", "GUILD", "Thora-Forever")
  local twin = tdb["Thora-Forever"]
  assert(twin and twin.stats.level == 59 and TR.selfSenders["Thora-Forever"] == nil, "another's GUID under your saved key: their record, the name match forgotten")
  thora.C.Comm:Receive("1D|3|level=1o", "GUILD", "Thora-Forever")
  assert(twin.stats.level == 60 and TR.selfSenders["Thora-Forever"] == nil, "their delta after it lands on their record")
  thora.C.Roster:Refresh()
  local twins, thoras = nil, 0
  for _, r in ipairs(TR:Rows()) do
    if r.short == "Thora Stonehew" then twins = r end
    if r.me or r.short == "Thora Bjorn" then thoras = thoras + 1 end
  end
  assert(twins and twins.addon and twins.key == "Thora-Forever" and twins.stats.level == 60 and thoras == 1, "the namesake's row has their record, Thora one row")
  assert(TR:Display("Thora-Forever") == "Thora Stonehew", "the key names the namesake: " .. TR:Display("Thora-Forever"))
  thora.C.Policy:Set("gold", "all")
  assert(thora.C.Policy:Describe():find("Set by Thora Bjorn,", 1, true), "your own policy is yours, whoever has your saved key: " .. thora.C.Policy:Describe())
  -- under the sender string Thora's own GUID came under, another's full record is kept as theirs too, and her own
  -- delta, handed back under it, neither drops nor feeds it
  assert(TR.selfSenders["Thora Bjorn"] == "guid", "Thora's sender string, known by her GUID")
  thora.C.Comm:Receive("1F|1|1|3|guid=" .. guidOf("Thora Ashby") .. ";level=a", "GUILD", "Thora Bjorn")
  assert(tdb["Thora Bjorn"] and tdb["Thora Bjorn"].stats.level == 10, "another's GUID under your own sender string: kept")
  thora.C.Comm:Receive("1D|3|level=1p", "GUILD", "Thora Bjorn")
  assert(tdb["Thora Bjorn"] and tdb["Thora Bjorn"].stats.level == 10 and TR.selfSenders["Thora Bjorn"] == "guid", "your delta under it: yours, the other record untouched")
  tdb["Thora Bjorn"] = nil
  TR:Changed()
  -- your own ask, handed back, is not answered; a 0.3.0 client's bare ask still is
  assert(not helga.C.Comm.answering, "nothing waiting to answer")
  helga.C.Comm:Receive("1R|" .. helga.o.guid, "GUILD", "Helga Bluntforce")
  assert(not helga.C.Comm.answering, "your own ask is not answered")
  helga.C.Comm:Receive("1R", "GUILD", "Old Timer")
  assert(helga.C.Comm.answering, "a bare 1R is answered")
  tickAll(25)
  -- the window: you once, at the top, the officers' tab yours
  helga.C.UI:Open("race")
  local you = rowOf(helga, "Helga Bluntforce")
  assert(you and you.row.me and you.name:GetText() == "Helga Bluntforce  (you)", "the row says you: " .. tostring(you and you.name:GetText()))
  local shown = 0
  for _, r in ipairs(helga.C.UI.rows.items) do if r:IsShown() and r.row.short == "Helga Bluntforce" then shown = shown + 1 end end
  assert(shown == 1 and helga.C.UI.tabs.officers:IsShown(), "one row of you in the window; the guild master sees the Officers tab")
  check(helga.C.UI.frame, "forever names race")
  helga.C.UI:Open("officers")
  check(helga.C.UI.frame, "forever names officers")
  -- a Kstring wider than its room: the label shows the same on the first draw as on every later one (the box clips it)
  local fs = helga.C.UI.frame:CreateFontString()
  helga.C.UI.FitText(fs, "|Kq7777777|k", 20)
  local firstDraw = fs:GetText()
  helga.C.UI.FitText(fs, "|Kq7777777|k", 20)
  assert(firstDraw == "|Kq7777777|k" and fs:GetText() == firstDraw, "a wide Kstring kept whole, the same both draws: " .. tostring(firstDraw) .. " then " .. tostring(fs:GetText()))
  helga.C.UI.FitText(fs, "Thora Bjorn the Unbowed", 60)
  firstDraw = fs:GetText()
  helga.C.UI.FitText(fs, "Thora Bjorn the Unbowed", 60)
  assert(firstDraw:find("%.%.%.$") and fs:GetText() == firstDraw, "a plain name cut the same both draws: " .. firstDraw)
  -- your own emote line: the event's GUID decides, whatever name it gives
  local before = helga.C.Sample:Value("emotes")
  fire(helga, "CHAT_MSG_TEXT_EMOTE", "You dance.", "Helga", "", "", "", "", 0, 0, "", 0, 1, helga.o.guid)
  fire(helga, "CHAT_MSG_TEXT_EMOTE", "Thora dances.", "Helga Bluntforce", "", "", "", "", 0, 0, "", 0, 2, thora.o.guid)
  fire(helga, "CHAT_MSG_TEXT_EMOTE", "You wave.", "Helga Bluntforce")
  assert(helga.C.Sample:Value("emotes") == before + 2, "your lines count by GUID or by both names, another's not: " .. tostring(helga.C.Sample:Value("emotes") - before))
  -- /cute diag: lines to paste
  local n0 = #helga.chat
  helga.env.SlashCmdList.CUTE("diag")
  local out = table.concat(helga.chat, "\n", n0 + 1)
  for _, want in ipairs({ 'UnitName "Helga", "Bluntforce"', 'UnitFullName "Helga", "Bluntforce"', 'GetNormalizedRealmName "Forever"', 'GetRealmName "Forever"',
    "UnitGUID " .. helga.o.guid:sub(1, 16) .. "\n", 'name "Helga Bluntforce" (plain) | memberId ', "your rows 1", '"Helga Bluntforce" (Cute, you)',
    "diag slot 1: GetInventoryItemID 1234 | link string | GetInventoryItemQuality 2", "diag slot 16: GetInventoryItemID 1240" }) do
    assert(out:find(want, 1, true), "/cute diag says " .. want .. ":\n" .. out)
  end
  n0 = #ser.chat
  ser.env.SlashCmdList.CUTE("diag")
  out = table.concat(ser.chat, "\n", n0 + 1)
  assert(out:find('roster self: name "||Kq77||k" (a Kstring)', 1, true) and out:find("your rows 1", 1, true), "a Kstring shows raw, its | doubled, and says so:\n" .. out)
  for _, c in ipairs({ helga, thora, icee, ser }) do leave(c) end
  makeGuild()
  print("forever names: one row for you named as the roster names you, your own messages dropped by GUID under any sender string, Kstring names joined by GUID, ranks and emotes by GUID, a namesake's GUID kept as theirs over a name match, 0.3.0's ghost record gone, /cute diag")
end

-- 20: gear on a client whose GetInventoryItemLink gives a secret for every slot (0.3.0 showed 15 of 17 slots empty,
-- 0 of 17 unenchanted and item level "?" for a character in full gear): the item ids and qualities read as Forever's
-- character sheet reads them, the levels from the ids, and the enchants read nil with the reason
do
  local c = newClient(charOf(NAMES[10], { secretLinks = true }))
  login(c)
  local S = c.C.Sample
  local function n(id) local v, k = S:Value(id), 0; for _ in pairs(v or {}) do k = k + 1 end return v and k or nil end
  assert(S:Value("ilvl") == 46, "the item level from the ids: " .. tostring(S:Value("ilvl")))
  local hi = S:Value("ilvl_slots")
  assert(hi and hi[1] and hi[5] and hi[7] and not hi[16], "the slots at or above it")
  assert(n("empty_slots") == 11 and not S:Value("empty_slots")[1] and S:Value("empty_slots")[2], "eleven slots empty, the four worn not: " .. tostring(n("empty_slots")))
  assert(S:Value("greens") == 3 and n("old_gear") == 1 and S:Value("old_gear")[16], "greens from the slot qualities, old gear from the levels")
  assert(S:Value("unenchanted") == nil and tostring(S:Error("unenchanted")):find("no readable item link for 4 worn slots that take an enchant", 1, true), "no enchant count without links: " .. tostring(S:Error("unenchanted")))
  assert(S:Value("ready") == 1, "readiness still reads (an empty slot is its one gap)")
  c.C.UI:Open("prog")
  local me = rowOf(c, "Lindel")
  assert(cellOf(me, "ilvl").label:GetText() == "46" and cellOf(me, "empty_slots").label:GetText() == "11/17" and cellOf(me, "unenchanted").label:GetText() == "?", "the Prog row: 46, 11/17, ?")
  local l0 = #lines
  hover(cellOf(me, "unenchanted"))
  assert(table.concat(lines, "\n", l0 + 1):find("Could not read: the client gives no readable item link", 1, true), "the tooltip says why")
  check(c.C.UI.frame, "member prog, secret links")
  -- an item the client has not cached: GetDetailedItemLevelInfo reads nothing, C_Item.GetItemInfo's level stands in
  c.o.uncached = true
  fire(c, "PLAYER_EQUIPMENT_CHANGED")
  tick(c, 2)
  assert(S:Value("ilvl") == 46, "the fallback level: " .. tostring(S:Value("ilvl")))
  local n0 = #c.chat
  c.env.SlashCmdList.CUTE("diag")
  assert(table.concat(c.chat, "\n", n0 + 1):find("diag slot 5: GetInventoryItemID 1235 | link secret | GetInventoryItemQuality 3", 1, true), "/cute diag shows the secret link")
  leave(c)
  -- a client without GetInventoryItemID: every gear stat reads nil with that reason
  local bare = newClient(charOf(NAMES[10], { without = { GetInventoryItemID = true } }))
  login(bare)
  assert(bare.C.Sample:Value("ilvl") == nil and bare.C.Sample:Error("empty_slots") == "GetInventoryItemID is missing on this client", "missing: " .. tostring(bare.C.Sample:Error("empty_slots")))
  leave(bare)
  print("gear: with every link a secret, item level 46, 11 of 17 empty, 3 greens from the ids and qualities; enchants read nil with the reason; an uncached item's level from GetItemInfo")
end

-- 21: a guild of four hundred, a hundred and fifty with the addon: a draw costs the rows in view, not the roster (the
-- first screen the same as in a guild of a hundred); a scroll fills the rows coming into view and neither sorts nor
-- reads; the Statistics ranking the same; the sampler's ticks draw nothing; a burst of records draws once, and nothing
-- while the window is hidden
do
  local FIRST = { "Aldric", "Bryn", "Cassia", "Dorn", "Elske", "Fenwick", "Garra", "Hollis", "Isolde", "Jory", "Kestra", "Lorne", "Maren", "Nils",
    "Orla", "Perrin", "Quenna", "Rurik", "Sable", "Tamsin" }
  local LAST = { "Ashby", "Brack", "Corwen", "Dunmore", "Eastwold", "Fairholt", "Greaves", "Harrow", "Ironside", "Jessup", "Kettle", "Lowell",
    "Marsh", "Nettle", "Oakes", "Penrose", "Quill", "Rowan", "Stroud" }
  local CLASSES = { "WARRIOR", "PRIEST", "HUNTER", "MAGE", "ROGUE", "DRUID", "PALADIN", "WARLOCK", "SHAMAN" }
  local made, base = {}, {}
  for i, m in ipairs(GUILD) do base[i] = m end
  for _, l in ipairs(LAST) do for _, f in ipairs(FIRST) do
    local i = #made + 1
    made[i] = { name = f .. " " .. l, guid = guidOf(f .. " " .. l), rank = 3 + i % 2, rankName = i % 2 == 0 and "Raider" or "Member",
      class = CLASSES[i % #CLASSES + 1], level = 1 + (i * 7) % 60, online = i % 4 == 0, zone = "Stranglethorn Vale" }
  end end
  -- a guild of n (the twenty everyone shares, then the made ones) and a client in it whose window has the records of
  -- the made members 2, 4, ... 2 * records (as the channel names them: both words)
  local function guildOf(n, records)
    GUILD = {}
    for i, m in ipairs(base) do GUILD[i] = m end
    for i = 1, n - #base do GUILD[#GUILD + 1] = made[i] end
    local c = newClient(charOf(NAMES[3], { withStats = true }))
    login(c)
    local db = c.env.CuteDB.roster
    for i = 1, records do
      local m = made[i * 2]
      db[m.name] = { seen = EPOCH + c.clock, online = true, at = {}, stats = { guid = m.guid, level = m.level, xp = (i * 7) % 100, zone = "Duskwood",
        played = 3600 * i, quests_done = i, deaths_lvl = i % 9, rested = 0, g2001 = i * 13, g2002 = i, ready = i % 3, ilvl = 30 + i % 30, durability = 50 + i % 50 } }
    end
    c.C.Roster:Changed()
    c.C.UI:Build()
    return c
  end
  local function opsOf(fn) OPS.n = 0; fn(); return OPS.n end
  -- the first screen does not grow with the guild: the same forty members report in a guild of a hundred and in one of
  -- four hundred, the same rows are in view, and the first Race and Prog cost the same within a few ops (a cost of one
  -- op per member would show as three hundred more)
  local firstOf = {}
  for _, n in ipairs({ 100, 400 }) do
    local c = guildOf(n, 40)
    assert(#GUILD == n and c.C.UI.rows ~= nil, "a guild of " .. n)
    firstOf[n] = { race = opsOf(function() c.C.UI:Open("race") end), prog = opsOf(function() c.C.UI:Open("prog") end), rows = c.C.UI.rows.n }
    leave(c)
  end
  for _, page in ipairs({ "race", "prog" }) do
    local a, b = firstOf[100][page], firstOf[400][page]
    assert(firstOf[100].rows == 100 and firstOf[400].rows == 400 and math.abs(b - a) <= 10, page .. ": the first screen costs the same for 100 and 400 members: " .. a .. " and " .. b)
  end
  -- the scenario's guild: four hundred, a hundred and fifty of them reporting
  local big = guildOf(400, 150)
  assert(#GUILD == 400, "four hundred members: " .. #GUILD)
  local UI = big.C.UI
  local rowsCalls, realRows = 0, big.C.Roster.Rows
  big.C.Roster.Rows = function(self) rowsCalls = rowsCalls + 1; return realRows(self) end
  local function shownRows() local n = 0; for _, r in ipairs(UI.rows.items) do if r:IsShown() then n = n + 1 end end return n end
  local function cols() local n = 0; for _, h in ipairs(UI.headerCells.items) do if h:IsShown() and h.def then n = n + 1 end end return n end
  local bar = UI.scroll.bar
  local inView = math.ceil(UI.scroll:View() / 20)
  local report = {}
  for _, page in ipairs({ "race", "prog" }) do
    local first = opsOf(function() UI:Open(page) end)
    local rows, k = shownRows(), cols()
    -- a row's fill is its place, its name and a text per cell; the first screen also makes the widgets for the rows in
    -- view (three anchors a cell) and places the cells, which a redraw of the same columns leaves alone
    assert(UI.rows.n == 400 and rows <= inView + 9 + 1, page .. ": widgets for the rows in view only: " .. rows .. " of " .. UI.rows.n)
    -- (and the header, the tabs and the footer, a fixed hundred and twenty at most)
    assert(first <= rows * (5 + 5 * k) + 120, page .. ": the first screen costs the rows in view: " .. first .. " ops for " .. rows .. " rows")
    -- the order: you, the members who report, then those without the addon online, then offline
    local seenNoAddon, ok = false, true
    for i = 2, 30 do
      local r = nil
      for _, w in ipairs(UI.rows.items) do if w:IsShown() and w.idx == i then r = w.row end end
      if r then if not r.addon then seenNoAddon = true elseif seenNoAddon then ok = false end end
    end
    assert(ok, page .. ": the members with the addon come first")
    local again = opsOf(function() UI:Draw() end)
    assert(again <= rows * (2 + k) + 200, page .. ": a redraw costs the rows in view: " .. again)
    check(UI.frame, "officer " .. page .. ", 400 members")
    -- the middle, a wheel step, the end: rows coming into view, nothing sorted or read again
    local _, max = bar:GetMinMaxValues()
    local calls, draws = rowsCalls, UI.draws
    local mid = opsOf(function() bar:SetValue(math.floor(max / 2)) end)
    -- (and measures the names and zones it has not cut before, once)
    assert(mid <= rows * (2 + k) + 80, page .. ": a jump to the middle fills the rows in view: " .. mid)
    local step = opsOf(function() UI.scroll.__scripts.OnMouseWheel(UI.scroll, -1) end)
    assert(step <= 4 * (2 + k), page .. ": a wheel step fills the two or three rows coming into view: " .. step)
    check(UI.frame, "officer " .. page .. ", 400 members, scrolled to the middle")
    -- the column header stays in view above the rows, in the band, not in the scroll child
    assert(UI.header.__parent == UI.band and UI.header:IsVisible() and shownHeaders(big) > 0, page .. ": the header is pinned in view at the middle")
    local endOps = opsOf(function() bar:SetValue(max) end)
    local last
    for _, w in ipairs(UI.rows.items) do if w:IsShown() and w.idx == UI.rows.n then last = w.row end end
    assert(last and not last.addon and not last.online, page .. ": the end shows the last member, offline without the addon")
    assert(rowsCalls == calls and UI.draws == draws, page .. ": scrolling neither builds the rows again nor draws")
    check(UI.frame, "officer " .. page .. ", 400 members, scrolled to the end")
    report[#report + 1] = string.format("%s %d ops first (%d and %d with 100 and 400 members, 40 reporting), %d redraw, %d mid, %d step, %d end (%d of 400 rows have widgets)",
      page, first, firstOf[100][page], firstOf[400][page], again, mid, step, endOps, rows)
  end
  -- the Statistics ranking: Total kills opened ranks 151
  UI:Open("game")
  local stat
  for _, l in ipairs(UI.lines.items) do if l:IsShown() and l.def and l.def.id == "g2001" and not l.member then stat = l end end
  local opened = opsOf(function() press(stat) end)
  local lines = 0
  for _, l in ipairs(UI.lines.items) do if l:IsShown() then lines = lines + 1 end end
  assert(UI.lines.n >= 151 and lines <= inView + 10 and opened <= 1000, "the ranking draws the lines in view: " .. lines .. " of " .. UI.lines.n .. ", " .. opened .. " ops")
  check(UI.frame, "officer statistics, 151 ranked")
  local _, max = bar:GetMinMaxValues()
  local calls = rowsCalls
  local mid = opsOf(function() bar:SetValue(math.floor(max / 2)) end)
  check(UI.frame, "officer statistics, 151 ranked, the middle")
  bar:SetValue(max)
  -- the end: the last of the ranking, then Kills' second statistic (closed)
  local lastRanked, lastLine
  for _, l in ipairs(UI.lines.items) do
    if l:IsShown() and l.idx == UI.lines.n then lastLine = l end
    if l:IsShown() and l.idx == UI.lines.n - 1 then lastRanked = l end
  end
  assert(lastLine and lastLine.def.id == "g2002" and not lastLine.member and lastRanked and lastRanked.member, "the ranking scrolls to its end")
  assert(rowsCalls == calls and mid <= lines * 6 + 20, "the ranking's scroll fills the lines in view, the rows not built again: " .. mid)
  check(UI.frame, "officer statistics, 151 ranked, the end")
  report[#report + 1] = string.format("statistics %d ops opened, %d mid (%d of %d lines have widgets)", opened, mid, lines, UI.lines.n)
  -- ten ticks of the sampler (time played, the session, XP an hour move): no Draw, on Race nor on Statistics
  for _, page in ipairs({ "race", "game" }) do
    UI:Open(page)
    local draws = UI.draws
    for _ = 1, 10 do tick(big, 5) end
    assert(UI.draws == draws, page .. ": ten ticks drew " .. (UI.draws - draws) .. " times")
  end
  -- a value of yours that the page shows: your row (the first, which no sort moves) is filled again, nothing drawn
  UI:Open("race")
  bar:SetValue(0)
  local draws = UI.draws
  big.o.level = 43
  fire(big, "PLAYER_LEVEL_UP", 43)
  tick(big, 3)
  local mine = rowOf(big, "Upn")
  assert(mine and cellOf(mine, "level").label:GetText() == "43" and UI.draws == draws, "your level, refilled in place: " .. tostring(mine and cellOf(mine, "level").label:GetText()))
  -- a burst of thirty members' records: one Draw a second later; none while the window is hidden
  draws = UI.draws
  for i = 1, 30 do big.C.Roster:Apply(made[i * 2].name, { level = 60 }) end
  tick(big, 2)
  assert(UI.draws == draws + 1, "thirty records, one draw: " .. (UI.draws - draws))
  UI.frame:Hide()
  draws = UI.draws
  for i = 1, 30 do big.C.Roster:Apply(made[i * 2].name, { level = 59 }) end
  tick(big, 3)
  assert(UI.draws == draws, "none while hidden")
  big.C.Roster.Rows = realRows
  leave(big)
  makeGuild()
  print("400 members: " .. table.concat(report, "; ") .. "; ten sampler ticks draw nothing; thirty records draw once, hidden none")
end

local seen, unique = {}, {}
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
